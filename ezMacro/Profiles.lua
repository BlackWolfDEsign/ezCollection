local _, ns = ...
local L = ns.L
local Core = ezCore
local UI = ns.UI

-- Leisten-Profile (wie Myslot): Aktionsleisten samt Makros und auf Wunsch der Tastenbelegung unter einem
-- Namen speichern und auf einem anderen Charakter laden – etwa für einen neuen Twink derselben Klasse.
-- Profile liegen in ezMacroDB.profiles (für alle Charaktere des Accounts). Laden fragt **einmal** nach (bei mehr als
-- zehn neuen Makros vorher je zehn Namen mit „Weiter“) und geht nur außerhalb des Kampfes (PickupAction/PlaceAction
-- sind im Kampf gesperrt).
-- ezBars nutzt dieselben Profile für seine Leisten (Schnittstelle in API.lua, Teil-Profile nach Reihenfolge).
local Profiles = {}
ns.Profiles = Profiles

-- Aktionsplätze und ihr Inhalt kommen aus ezCore (Core.ActionSlots, ein Plan der Plätze für ezMacro, ezBars
-- und ezCombat): USABLE = 1–120 und 145–180; 121–144 sind Fahrzeug-, Übernahme- und Sonderleisten, nie anfassen.
local AS = Core.ActionSlots

---------------------------------------------------------------------------
-- Erfassen
---------------------------------------------------------------------------

-- Inhalt eines Aktionsplatzes als Tabelle, nil = leer oder gesperrt. Gelesen über ezCore (ActionSlots.Info:
-- Art, ID, Untertyp, Text – nie geheime Werte).
function Profiles.CaptureSlot(slot)
    local info = AS.Info(slot)
    if not info then return nil end
    local kind, id = info.kind, info.id
    if kind == "spell" then
        return { kind = "spell", id = id, name = ns.SpellName(id) }
    elseif kind == "macro" then
        -- Neuere Clients melden bei Makros, die einen Zauber zeigen, dessen ID statt des Makro-Index:
        -- zuerst der Name (Text des Platzes), der Index nur ohne Untertyp.
        local name = info.text
        local index = name and (ns.Macros.Find(name, true) or ns.Macros.Find(name, false))
        if not index and type(id) == "number" and info.subType == nil then index = id end
        if not index then return nil end
        local macroName, icon = GetMacroInfo(index)
        if not macroName then return nil end
        local _, maxAccount = ns.Import.Counts()
        return { kind = "macro", name = macroName, icon = icon, body = ns.Import.BodyOf(index),
            perChar = index > maxAccount }
    elseif kind == "item" then
        return { kind = "item", id = id }
    elseif kind == "summonmount" then
        return { kind = "mount", id = id }
    elseif kind == "summonpet" then
        return { kind = "pet", id = id }
    elseif kind == "equipmentset" then
        return { kind = "equipmentset", id = id }
    elseif kind == "flyout" then
        return { kind = "flyout", id = id }
    end
    return { kind = "other", id = id, type = kind }
end

-- Inhalt mehrerer Plätze: { [slot] = data }. slots = nil: alle Aktionsplätze.
function Profiles.Capture(slots)
    local data = {}
    for _, slot in ipairs(slots or AS.USABLE) do
        data[slot] = Profiles.CaptureSlot(slot)
    end
    return data
end

local function CaptureBindings()
    local list = {}
    if type(GetNumBindings) ~= "function" or type(GetBinding) ~= "function" then return list end
    for index = 1, GetNumBindings() do
        local command, _, key1, key2 = GetBinding(index)
        if type(command) == "string" and (key1 or key2) then list[#list + 1] = { command, key1, key2 } end
    end
    return list
end

-- Uhrzeit (gespeichert mit dem Profil): Core.Now, eine Stelle für alle Module (W-14)
local Now = Core.Now

-- Kopie einer Platzliste (Reihenfolge für das Laden nach Reihenfolge).
local CopyList = Core.CopyList   -- flache Kopie aus ezCore (Gesamtreview 18.11.2026, T16-7)

-- Daten der Plätze order[k] auf die Plätze targets[k] umlegen (Laden nach Reihenfolge, z. B. ezBars:
-- Leiste 1 liegt beim Magier auf 73–84, beim Krieger auf 145–156).
function Profiles.Remap(data, order, targets)
    local out = {}
    for index, target in ipairs(targets or {}) do
        local source = order and order[index]
        if source and data[source] then out[target] = data[source] end
    end
    return out
end

-- Speichert die Leisten unter einem Namen (überschreibt ein gleichnamiges Profil).
-- opts.slots: nur diese Plätze (ezBars), sonst alle; ihre Reihenfolge wird mitgespeichert (profile.order).
function Profiles.Save(name, opts)
    name = Core.Trim(tostring(name or ""))
    if name == "" then return nil end
    opts = opts or {}
    local info = Core.CharInfo(ns.charKey) or {}
    local profile = {
        name = name, class = ns.playerClass, char = ns.charKey, charName = info.name, time = Now(),
        slots = Profiles.Capture(opts.slots), partial = opts.slots and true or nil,
        order = opts.slots and CopyList(opts.slots) or nil,
        -- Tastenbelegungen gehören dem ganzen Charakter: nur ein volles Profil nimmt sie mit, ein Teil-Profil
        -- (ezBars: eine Leiste) soll beim Laden nie alle Tasten ändern.
        bindings = not opts.slots and CaptureBindings() or nil,
    }
    ns.db.profiles[name] = profile
    ns.Print(L.PROFILE_SAVED:format(name, Profiles.Count(profile)))
    if ns.Tools then ns.Tools.RefreshKey("profiles") end
    return profile
end

function Profiles.Get(name) return ns.db and ns.db.profiles[name] end

function Profiles.Names()
    local names = {}
    for name, profile in pairs(ns.db and ns.db.profiles or {}) do
        if type(profile) == "table" then names[#names + 1] = name end
    end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

-- Belegte Plätze und Makros eines Profils.
function Profiles.Count(profile)
    local slots, macros = 0, 0
    for _, data in pairs(profile and profile.slots or {}) do
        slots = slots + 1
        if data.kind == "macro" then macros = macros + 1 end
    end
    return slots, macros
end

function Profiles.Delete(name)
    if not Profiles.Get(name) then return end
    Core.Confirm(L.PROFILE_DELETE_CONFIRM:format(name), function()
        ns.db.profiles[name] = nil
        ns.Tools.RefreshKey("profiles")
    end)
end

---------------------------------------------------------------------------
-- Als Text (wie Myslot): ezCore.Serialize mit { kind = "ezMacro.profile", v = 1, profile = … }
---------------------------------------------------------------------------

Profiles.KIND = "ezMacro.profile"
Profiles.VERSION = 1      -- Fassung des Umschlags; ein Text mit höherer Fassung stammt aus einem neueren ezMacro


-- Felder, die nicht in einen Text zum Weitergeben gehören (Gesamtreview 18.11.2026, T6-4; wie ezPanels Export-Filter
-- nach V-087): Charakter samt Realm und Charaktername; „imported“ ist nur eine eigene Markierung.
local EXPORT_SKIP = { char = true, charName = true, imported = true }

-- Grenze eines Wortes: Anfang, Ende, Leer- oder Satzzeichen (ein Buchstabe – auch ein Umlaut – ist keine).
local function Boundary(char) return char == "" or char:match("^[%s%p]$") ~= nil end

-- Text ohne jedes Vorkommen von word als ganzes Wort (wörtlich, ohne Muster): „Ann“ fällt aus „Krieger (Ann)“,
-- nicht aus „Annas Leisten“.
local function RemoveWord(text, word)
    if type(word) ~= "string" or word == "" then return text end
    local parts, start, from = {}, 1, 1
    while true do
        local first, last = text:find(word, from, true)
        if not first then break end
        if Boundary(text:sub(first - 1, first - 1)) and Boundary(text:sub(last + 1, last + 1)) then
            parts[#parts + 1] = text:sub(start, first - 1)
            start = last + 1
        end
        from = last + 1
    end
    parts[#parts + 1] = text:sub(start)
    return table.concat(parts)
end

-- Name für den Text zum Weitergeben: ohne Charakter- und Realmnamen (der Vorschlag beim Speichern lautet
-- „Klasse (Charaktername)“). Bleibt nichts übrig, steht der Klassenname da; ohne Klasse nil (der Import vergibt dann
-- „Leisten-Profil“).
function Profiles.ShareName(profile)
    local name = type(profile.name) == "string" and profile.name or ""
    local words = {}
    if type(profile.char) == "string" then
        words[#words + 1] = profile.char
        local short, realm = profile.char:match("^(.-)%-(.+)$")
        if short then words[#words + 1] = short end
        if realm then words[#words + 1] = realm end
    end
    if type(profile.charName) == "string" then words[#words + 1] = profile.charName end
    for _, word in ipairs(words) do name = RemoveWord(name, word) end
    name = name:gsub("%(%s*%)", ""):gsub("%s+", " ")
    name = Core.Trim(name)
    if name == "" then return profile.class and ns.ClassName(profile.class) or nil end
    return name
end

-- Umschlag { kind, v, profile } über ezCore (Core.Pack, MACRO-04); eine Kopie ohne die Felder aus EXPORT_SKIP.
function Profiles.Export(name)
    local profile = Profiles.Get(name)
    if not profile then return nil end
    local copy = {}
    for key, value in pairs(profile) do
        if not EXPORT_SKIP[key] then copy[key] = value end
    end
    copy.name = Profiles.ShareName(profile)
    return (Core.Pack(Profiles.KIND, Profiles.VERSION, { profile = copy }))
end

-- Freier Name „Profil“, „Profil (2)“ … über ezCore (Core.UniqueName, MACRO-03); FreeName bleibt als Weiterleitung.
-- Ein Name aus fremdem Text verliert Farbcodes, Links, „|“, Steuerzeichen und Umbrüche (Core.CleanImportName, T6-5/P19).
local function FreeName(base)
    local clean = base ~= nil and Core.CleanImportName(tostring(base)) or nil
    return Core.UniqueName(clean, function(name) return Profiles.Get(name) ~= nil end, { default = L.TOOL_PROFILES })
end

-- Bekannte Arten eines Platzes und der Typ ihrer ID (Gesamtreview 18.11.2026, T6-1): "number" = nur Zahl, "any" =
-- Zahl oder Text (Begleiter: GUID, Ausrüstungsset: Name), "maybe" = darf fehlen. Makros prüft CleanSlot eigens.
local SLOT_ID = { spell = "number", item = "number", mount = "number", flyout = "number", pet = "any",
    equipmentset = "any", other = "maybe", macro = "macro" }

local function CleanId(value, need)
    if need == "number" then return type(value) == "number" and value or nil end
    if type(value) == "number" or type(value) == "string" then return value end
end

-- Ein Platz aus fremdem Text: nur bekannte Arten und Felder mit passendem Typ (nil = verworfen). Makronamen wie
-- beim Anlegen bereinigt (Import.CleanName), damit Plan, Platzwahl und Anlegen denselben Namen suchen.
function Profiles.CleanSlot(data)
    if type(data) ~= "table" or type(data.kind) ~= "string" then return nil end
    local need = SLOT_ID[data.kind]
    if not need then return nil end
    if need == "macro" then
        local name = type(data.name) == "string" and ns.Import.CleanName(data.name) or ""
        if name == "" then return nil end
        local icon = (type(data.icon) == "number" or type(data.icon) == "string") and data.icon or nil
        return { kind = "macro", name = name, icon = icon, perChar = data.perChar == true,
            body = type(data.body) == "string" and data.body or nil }
    end
    local id = CleanId(data.id, need)
    if id == nil and need ~= "maybe" then return nil end
    local slot = { kind = data.kind, id = id }
    if data.kind == "spell" and type(data.name) == "string" then slot.name = data.name end
    if data.kind == "other" and type(data.type) == "string" then slot.type = data.type end
    return slot
end

-- Tasten, die ein Profil nie belegt (T9-NB5): Esc (Spielmenü) und Druck mit jeder Zusatztaste, die linke und rechte
-- Maustaste ohne Zusatztaste – wie Blizzards eigene Tastenbelegung.
local BLOCKED_KEYS = { ESCAPE = true, PRINTSCREEN = true }
local BLOCKED_PLAIN = { BUTTON1 = true, BUTTON2 = true }
-- Form einer Taste aus fremdem Text: Text ohne Leer-, Steuerzeichen und „|“, Zusatztasten vor der eigentlichen Taste,
-- die eigentliche Taste aus Buchstaben und Ziffern oder genau ein Zeichen (auch ein Umlaut). Prüft ezCore
-- (Core.Keys.NormalizeKey mit opts.sides: linke und rechte Zusatztasten bleiben; Nachlauf zu T9-NB5, P13 D2) –
-- Profiles.KeyFormat bleibt als Umleitung. Gesperrte Tasten haben die richtige Form; ausgefiltert werden sie erst von
-- Profiles.CleanKey. Rückgabe: Taste (in Blizzards Schreibweise), Zusatztasten, eigentliche Taste. „+“ als
-- eigentliche Taste („+“, „CTRL-+“) kennt ezCore seit dem Gesamtreview selbst (vorher fing ezMacro das hier ab).
function Profiles.KeyFormat(key)
    if type(key) ~= "string" then return nil end
    return Core.Keys.NormalizeKey(key, { sides = true })
end

-- Taste, die ein Profil belegen darf: richtige Form (Profiles.KeyFormat) und nicht gesperrt. Rückgabe: Taste oder nil.
function Profiles.CleanKey(key)
    local ok, parts, main = Profiles.KeyFormat(key)
    if not ok or BLOCKED_KEYS[main] or (#parts == 0 and BLOCKED_PLAIN[main]) then return nil end
    return ok
end

-- Übernimmt ein Profil aus Text (nur Plätze 1–120 und 145–180, nur bekannte Arten mit passenden Feldern, Tasten
-- in der Form von Profiles.KeyFormat; der Charaktername des Absenders bleibt draußen, das Profil gilt als „aus Text“).
-- Gesperrte Tasten (Esc …) bleiben im Profil stehen: Profiles.BindingPlan filtert sie beim Laden und nennt sie in der
-- Rückfrage, außer sie lösen schon genau diesen Befehl aus. Einträge ohne brauchbare Taste oder ohne Befehl fallen
-- schon hier weg; ihre Zahl steht in profile.bindingsDropped und zählt beim Laden mit (nach der Gegenprüfung).
-- Rückgabe: Name des neuen Profils oder nil, Fehlertext.
-- Text und Tabelle gehen durch ezCores Umschlag (Core.Unpack: Art und Fassung geprüft, MACRO-04); ein Text aus einem
-- neueren ezMacro bekommt eine eigene Meldung statt „kein Profil“.
function Profiles.Import(value)
    if type(value) == "table" then value = Core.Serialize(value) end
    local why
    value, why = Core.Unpack(value, Profiles.KIND, Profiles.VERSION)
    if why == "newer" then return nil, L.PROFILE_IMPORT_NEWER end
    if type(value) ~= "table" or type(value.profile) ~= "table" or type(value.profile.slots) ~= "table" then
        return nil, L.PROFILE_IMPORT_BAD
    end
    local source = value.profile
    local profile = {
        name = nil, class = type(source.class) == "string" and source.class or nil,
        time = tonumber(source.time) or Now(), slots = {}, bindings = {},
        partial = source.partial and true or nil, imported = true,
    }
    if type(source.order) == "table" then
        local order = {}
        for _, slot in ipairs(source.order) do
            slot = tonumber(slot)
            if AS.IsUsable(slot) then order[#order + 1] = slot end
        end
        profile.order = #order > 0 and order or nil
    end
    for slot, data in pairs(source.slots) do
        slot = tonumber(slot)
        local clean = AS.IsUsable(slot) and Profiles.CleanSlot(data)
        if clean then profile.slots[slot] = clean end
    end
    local dropped = 0
    for _, binding in ipairs(type(source.bindings) == "table" and source.bindings or {}) do
        local key1, key2
        if type(binding) == "table" and type(binding[1]) == "string" and binding[1] ~= ""
            and not binding[1]:find("[%c]") then
            key1, key2 = Profiles.KeyFormat(binding[2]), Profiles.KeyFormat(binding[3])
        end
        if key1 or key2 then
            profile.bindings[#profile.bindings + 1] = { binding[1], key1, key2 }
        else
            dropped = dropped + 1
        end
    end
    profile.bindingsDropped = dropped > 0 and dropped or nil
    local name = FreeName(source.name)
    profile.name = name
    ns.db.profiles[name] = profile
    if ns.Tools then ns.Tools.RefreshKey("profiles") end
    return name
end

-- Dialog „Als Text“: zeigt das gewählte Profil zum Kopieren; eingefügter Text wird ein neues Profil.
function Profiles.TextDialog(name)
    local text = name and Profiles.Export(name) or ""
    return UI.TextDialog({
        title = L.PROFILE_TEXT_TITLE,
        hint = L.PROFILE_TEXT_HINT,
        text = text,
        select = text ~= "",
        accept = true,   -- ezCores „Übernehmen“ (L.TEXTDIALOG_ACCEPT, T18-22)
        onAccept = function(input)
            if text ~= "" and Core.Trim(input or "") == text then return true end   -- unverändert: nur schließen
            local imported, err = Profiles.Import(input)
            if not imported then
                ns.Print(err)
                return false
            end
            ns.Print(L.MACRO_PROFILE_IMPORTED:format(imported))
        end,
    })
end

---------------------------------------------------------------------------
-- Laden
---------------------------------------------------------------------------

local function PickupSpellID(id)
    if C_Spell and C_Spell.PickupSpell then return C_Spell.PickupSpell(id) end
    if PickupSpell then return PickupSpell(id) end
end

local function PickupItemID(id)
    if C_Item and C_Item.PickupItem then return C_Item.PickupItem(id) end
    if PickupItem then return PickupItem(id) end
end

local function PickupMount(mountID)
    local journal = C_MountJournal
    if not (journal and journal.GetNumDisplayedMounts and journal.GetDisplayedMountID and journal.Pickup) then return end
    for index = 1, journal.GetNumDisplayedMounts() do
        if journal.GetDisplayedMountID(index) == mountID then return journal.Pickup(index) end
    end
end

local function PickupFlyout(flyoutID)
    local book, bank = C_SpellBook, Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    local flyoutType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Flyout
    if not (book and book.GetNumSpellBookSkillLines and book.GetSpellBookItemInfo and book.PickupSpellBookItem and bank) then
        return
    end
    for line = 1, book.GetNumSpellBookSkillLines() do
        local skill = book.GetSpellBookSkillLineInfo(line)
        if skill then
            for slot = skill.itemIndexOffset + 1, skill.itemIndexOffset + skill.numSpellBookItems do
                local item = book.GetSpellBookItemInfo(slot, bank)
                if item and item.itemType == flyoutType and item.actionID == flyoutID then
                    return book.PickupSpellBookItem(slot, bank)
                end
            end
        end
    end
end

local function CursorHasAction()
    return type(GetCursorInfo) == "function" and GetCursorInfo() ~= nil
end

-- Legt einen Zauber (genau diese ID, also diesen Rang) auf einen Platz; für „Ränge aktualisieren“.
function Profiles.PlaceSpell(slot, id)
    if ns.InCombat() or not (PlaceAction and ClearCursor) then return false end
    ClearCursor()
    PickupSpellID(id)
    local ok = CursorHasAction()
    if ok then PlaceAction(slot) end
    ClearCursor()
    return ok
end

-- Was ein Platz bekommen soll, schon für den Plan: Zauber nur, wenn gelernt (höchster Rang aus ezCore),
-- Makros nur, wenn es sie gibt oder sie angelegt werden.
local function Placeable(data, macroNames)
    if data.kind == "spell" then return ns.BestKnownSpell(data.id) ~= nil end
    if data.kind == "macro" then
        return macroNames[data.name] or ns.Macros.Find(data.name, data.perChar) ~= nil
            or ns.Macros.Find(data.name, not data.perChar) ~= nil
    end
    return data.kind ~= "other"
end

local function Same(a, b)
    if not (a and b) or a.kind ~= b.kind then return false end
    if a.kind == "macro" then return a.name == b.name end
    if a.kind == "spell" then return ns.BestKnownSpell(a.id) == b.id end
    return a.id == b.id
end

local function Pick(data)
    if data.kind == "spell" then
        local id = ns.BestKnownSpell(data.id)
        if id then PickupSpellID(id) end
    elseif data.kind == "macro" then
        local index = ns.Macros.Find(data.name, data.perChar) or ns.Macros.Find(data.name, not data.perChar)
        if index and PickupMacro then PickupMacro(index) end
    elseif data.kind == "item" then
        PickupItemID(data.id)
    elseif data.kind == "mount" then
        PickupMount(data.id)
    elseif data.kind == "pet" then
        if C_PetJournal and C_PetJournal.PickupPet then C_PetJournal.PickupPet(data.id) end
    elseif data.kind == "equipmentset" then
        local sets = C_EquipmentSet
        local setID = sets and sets.GetEquipmentSetID and sets.GetEquipmentSetID(data.id)
        if setID and sets.PickupEquipmentSet then sets.PickupEquipmentSet(setID) end
    elseif data.kind == "flyout" then
        PickupFlyout(data.id)
    end
end

-- Legt die Daten auf die Plätze (ohne Rückfrage; nur außerhalb des Kampfes).
-- opts.clearEmpty: Plätze leeren, die in den Daten leer sind (nur für opts.slots bzw. alle Plätze).
-- Rückgabe: belegt, geleert, fehlend.
function Profiles.Place(data, opts)
    opts = opts or {}
    if ns.InCombat() or not (PlaceAction and PickupAction and ClearCursor) then return 0, 0, 0 end
    local placed, cleared, missing = 0, 0, 0
    for _, slot in ipairs(opts.slots or AS.USABLE) do
        local want = data[slot]
        if want then
            if not Same(want, Profiles.CaptureSlot(slot)) then
                ClearCursor()
                ns.Try("Place", Pick, want)
                if CursorHasAction() then
                    PlaceAction(slot)
                    placed = placed + 1
                else
                    missing = missing + 1
                end
                ClearCursor()
            end
        elseif opts.clearEmpty and AS.Has(slot) then
            ClearCursor()
            PickupAction(slot)
            ClearCursor()
            cleared = cleared + 1
        end
    end
    return placed, cleared, missing
end

-- Belegungssatz, in den SetBinding schreibt und SaveBindings speichert: Blizzards aktuell gewählter (1 = kontoweit,
-- 2 = je Charakter; Häkchen „Charakterspezifische Tastaturbelegung“). ezMacro stellt ihn nie um (T9-NB4).
local ACCOUNT_SET = 1
function Profiles.BindingSet()
    local set = type(GetCurrentBindingSet) == "function" and GetCurrentBindingSet() or nil
    if Core.IsSecret(set) or set == nil then return 2 end
    return set
end

-- Für Rückfrage und Tooltip: für wen die Tasten gelten.
function Profiles.BindingSetText()
    local account = rawget(_G, "ACCOUNT_BINDINGS") or ACCOUNT_SET
    return Profiles.BindingSet() == account and L.PROFILE_BINDINGS_ACCOUNT or L.PROFILE_BINDINGS_CHAR
end

-- Befehle, die der Client als Tastenbelegung kennt (GetBinding; ohne Überschriften). Nur sie übernimmt ein Profil
-- (T9-NB5): ein eigenes Profil enthält ohnehin nur sie (CaptureBindings), ein fremder Text bringt keinen anderen mit.
local function KnownCommands()
    local known = {}
    if type(GetNumBindings) ~= "function" or type(GetBinding) ~= "function" then return known end
    for index = 1, GetNumBindings() do
        local command = GetBinding(index)
        if type(command) == "string" and not Core.IsSecret(command) and not command:match("^HEADER_") then
            known[command] = true
        end
    end
    return known
end

-- Was die Taste heute auslöst: lesbarer Name und Befehl, nil = nichts (ezCores Core.Keys.Conflict, nach der
-- Gegenprüfung statt einer eigenen Kopie).
local function KeyAction(key)
    local keys = Core.Keys
    if not (keys and keys.Conflict) then return nil end
    return keys.Conflict(key)
end

-- Tastenbelegungen für das Laden: nur bekannte Befehle und erlaubte Tasten. Rückgabe: Liste { befehl, taste1, taste2 },
-- Zahl der verworfenen Einträge, Liste der Tasten, die heute etwas anderes auslösen (je „Taste (bisher …)“ mit dem
-- Namen aus dem Client, „|“ verdoppelt). Eine gesperrte Taste, die schon
-- genau diesen Befehl auslöst (Esc öffnet das Spielmenü, Druck macht ein Bildschirmfoto – so steht es in jedem eigenen
-- Profil), zählt nicht als verworfen: an ihr ändert sich nichts.
-- Ein früherer Befehl aus ezCores Tasten-Dienst (etwa „CLICK ezMacroOneKeyOpen:LeftButton“ aus der Zeit vor den
-- Stellvertretern, Gesamtreview 18.11.2026, Nachlauf zu T9-NB1) zählt als sein heutiger (Core.Keys.CurrentCommand):
-- den früheren kennt der Client nicht mehr, die Taste fiele sonst beim Laden weg. Das gespeicherte Profil bleibt, wie
-- es ist – die Übersetzung gilt bei jedem Laden, auch für eingefügte Texte. Makrotexte mit „/click ezMacroOneKeyOpen“
-- bleiben gültig (der Knopf heißt weiter so), dort ist nichts umzuschreiben.
local function CurrentCommand(command)
    local keys = Core.Keys
    if keys and type(keys.CurrentCommand) == "function" then return keys.CurrentCommand(command) end
    return command
end

function Profiles.BindingPlan(list)
    local known, out, skipped, changed = KnownCommands(), {}, 0, {}
    for _, binding in ipairs(list or {}) do
        local command = type(binding) == "table" and CurrentCommand(binding[1])
        local keys, unchanged = {}, false
        if type(command) == "string" and known[command] then
            for index = 2, 3 do
                local raw = binding[index]
                local key = Profiles.CleanKey(raw)
                if key then
                    keys[index] = key
                    local name, action = KeyAction(key)
                    if action and action ~= command then
                        changed[#changed + 1] = L.PROFILE_KEY_WAS:format(key, (tostring(name):gsub("|", "||")))
                    end
                elseif type(raw) == "string" and select(2, KeyAction(raw)) == command then
                    unchanged = true
                end
            end
        end
        if keys[2] or keys[3] then
            out[#out + 1] = { command, keys[2], keys[3] }
        elseif not unchanged then
            skipped = skipped + 1
        end
    end
    return out, skipped, changed
end

-- Setzt die Tasten (jede einzeln geschützt: eine Taste, die der Client ablehnt, hält die übrigen nicht auf) und
-- speichert sie im aktuellen Belegungssatz. Rückgabe: Zahl der gesetzten Tasten.
local function ApplyBindings(list)
    if type(SetBinding) ~= "function" or type(SaveBindings) ~= "function" then return 0 end
    local n = 0
    for _, binding in ipairs(list or {}) do
        for index = 2, 3 do
            local key = binding[index]
            if key then
                local ok, done = pcall(SetBinding, key, binding[1])
                if ok and done then n = n + 1 end
            end
        end
    end
    SaveBindings(Profiles.BindingSet())
    return n
end

local function Exists(name)
    return type(name) == "string" and (ns.Macros.Find(name, true) or ns.Macros.Find(name, false)) ~= nil
end

-- Plan für das Laden: fehlende Makros (über Import.Plan), Plätze, die sich ändern, Fehlendes.
-- Ein Profil legt nur Makros an, die es unter dem bereinigten Namen in keinem der beiden Bereiche gibt; ein
-- vorhandenes Makro ersetzt es nie (T6-1: sonst fände ein Name wie „Heilen “ dein Makro „Heilen“ und überschriebe es
-- ohne eigene Rückfrage). Die Namen solcher Einträge stehen unter plan.keep (je Name einmal, sortiert): auf ihre
-- Plätze kommt dein vorhandenes Makro, nicht der Text aus dem Profil.
function Profiles.Plan(profile, opts)
    opts = opts or {}
    local macros, macroNames, keep, kept = {}, {}, {}, {}
    if opts.macros ~= false then
        for _, data in pairs(profile.slots or {}) do
            local name = data.kind == "macro" and ns.Import.CleanName(data.name)
            if name and name ~= "" then
                -- vorhanden unter dem gespeicherten oder dem bereinigten Namen, in einem der beiden Bereiche
                if not Exists(data.name) and not Exists(name) then
                    macros[#macros + 1] = { name = name, icon = data.icon, body = data.body, perChar = data.perChar }
                elseif not kept[name] then
                    kept[name] = true
                    keep[#keep + 1] = name
                end
            end
        end
    end
    table.sort(keep)
    local plan = ns.Import.Plan(macros)
    plan.keep, plan.replace = keep, {}   -- replace bleibt leer: Import.Plan sieht nur Makros, die es nicht gibt
    plan.changes = #plan.create
    for _, item in ipairs(plan.create) do macroNames[item.name] = true end
    local change, clear, missing = 0, 0, 0
    for _, slot in ipairs(opts.slots or AS.USABLE) do
        local data = profile.slots[slot]
        if data then
            if not Placeable(data, macroNames) then
                missing = missing + 1
            elseif not Same(data, Profiles.CaptureSlot(slot)) then
                change = change + 1
            end
        elseif opts.clearEmpty and AS.Has(slot) then
            clear = clear + 1
        end
    end
    plan.slotChange, plan.slotClear, plan.slotMissing = change, clear, missing
    plan.bindingList, plan.bindingSkipped, plan.bindingChanged = {}, 0, {}
    if opts.bindings then
        plan.bindingList, plan.bindingSkipped, plan.bindingChanged = Profiles.BindingPlan(profile.bindings)
        -- schon beim Import verworfene Einträge zählen mit (nach der Gegenprüfung)
        plan.bindingSkipped = plan.bindingSkipped + (tonumber(profile.bindingsDropped) or 0)
    end
    plan.bindings = #plan.bindingList
    return plan
end

-- Zeilen der Rückfrage zu den Makros, die neu entstehen (T6-1): je Makro der Name, dahinter rot die Befehle, die
-- Lua-Code ausführen oder Client-Einstellungen ändern. Rückgabe: Zeilen, Zahl der Makros mit solchen Befehlen.
function Profiles.MacroLines(plan)
    local lines, risky = {}, 0
    for _, item in ipairs(plan.create or {}) do
        -- „|“ verdoppelt: ein Name aus fremdem Text färbt oder versteckt so nichts in der Rückfrage
        local line = L.PROFILE_MACRO_LINE:format((item.name:gsub("|", "||")))
        local commands = ns.Import.ScriptCommands(item.body)
        if #commands > 0 then
            risky = risky + 1
            line = line .. " " .. UI.Colored("RED_FONT_COLOR", L.PROFILE_MACRO_SCRIPT:format(table.concat(commands, ", ")))
        end
        lines[#lines + 1] = line
    end
    return lines, risky
end

-- Zeile der Rückfrage zu Makros aus einem fremden Profil, die es bei dir schon gibt (T6-1, nach der Gegenprüfung):
-- sie bleiben unverändert, auf ihre Plätze kommt dein Makro. Die ersten fünf mit Namen, „|“ verdoppelt.
local SHOW_KEEP = 5
function Profiles.KeepLine(plan)
    local keep = plan.keep or {}
    if #keep == 0 then return nil end
    local shown = {}
    for index = 1, math.min(#keep, SHOW_KEEP) do shown[index] = (keep[index]:gsub("|", "||")) end
    local text = table.concat(shown, ", ")
    if #keep > SHOW_KEEP then text = text .. " " .. Core.More(#keep - SHOW_KEEP, true) end
    return L.PROFILE_PLAN_KEEP:format(#keep, text)
end

-- Höchstens so viele Makros je Rückfrage; bei mehr zeigen vorgeschaltete Rückfragen („Weiter“) den Rest, damit
-- kein Makro entsteht, dessen Namen der Spieler nicht gesehen hat (wie ezPanels Rückfrage zu fremden Befehlen).
Profiles.MACROS_PER_PAGE = 10

-- Zeilen der Rückfrage zu den Tasten (T9-NB4, T9-NB5): Anzahl samt Belegungssatz, Verworfenes, Tasten, die heute
-- etwas anderes auslösen (die ersten fünf mit Namen).
local SHOW_KEYS = 5
local function BindingLines(plan, lines)
    if plan.bindings > 0 then
        lines[#lines + 1] = L.PROFILE_PLAN_BINDINGS:format(plan.bindings, Profiles.BindingSetText())
        local changed = plan.bindingChanged
        if #changed > 0 then
            local shown = {}
            for index = 1, math.min(#changed, SHOW_KEYS) do shown[index] = changed[index] end
            local text = table.concat(shown, ", ")
            if #changed > SHOW_KEYS then text = text .. " " .. Core.More(#changed - SHOW_KEYS, true) end
            lines[#lines + 1] = L.PROFILE_PLAN_BINDINGS_CHANGED:format(#changed, text)
        end
    end
    if plan.bindingSkipped > 0 then
        lines[#lines + 1] = L.PROFILE_PLAN_BINDINGS_SKIPPED:format(plan.bindingSkipped)
    end
end

local function LoadOptions(opts)
    opts = opts or {}
    return {
        slots = opts.slots,
        macros = opts.macros == nil and ns.S.profileMacros or opts.macros,
        bindings = opts.bindings == nil and ns.S.profileBindings or opts.bindings,
        clearEmpty = opts.clearEmpty == nil and ns.S.profileClearEmpty or opts.clearEmpty,
        byOrder = opts.byOrder and true or nil,
    }
end

-- Lädt ein Profil nach **einer** Rückfrage. opts wie Profiles.Place, dazu macros/bindings (Standard: Einstellungen).
-- opts.byOrder mit opts.slots: den k-ten gespeicherten Platz (profile.order) auf opts.slots[k] legen.
function Profiles.Load(name, opts)
    local profile = Profiles.Get(name)
    if not profile then return false end
    if ns.InCombat() then
        ns.CombatNotice()
        return false
    end
    opts = LoadOptions(opts)
    local slots = profile.slots
    if opts.byOrder and opts.slots then
        slots = Profiles.Remap(profile.slots, profile.order or opts.slots, opts.slots)
    end
    local view = { slots = slots, bindings = profile.bindings, class = profile.class,
        bindingsDropped = profile.bindingsDropped }
    local plan = Profiles.Plan(view, opts)
    local lines = { L.PROFILE_PLAN_SLOTS:format(plan.slotChange) }
    if plan.slotClear > 0 then lines[#lines + 1] = L.PROFILE_PLAN_CLEAR:format(plan.slotClear) end
    if plan.slotMissing > 0 then lines[#lines + 1] = L.PROFILE_PLAN_MISSING:format(plan.slotMissing) end
    -- nur bei Profilen aus Text: in einem eigenen Profil sind vorhandene Makros der Normalfall
    local keepLine = profile.imported and Profiles.KeepLine(plan)
    if keepLine then lines[#lines + 1] = keepLine end
    BindingLines(plan, lines)
    if profile.class and profile.class ~= ns.playerClass then
        lines[#lines + 1] = L.PROFILE_PLAN_CLASS:format(ns.ClassName(profile.class))
    end
    local title = L.PROFILE_LOAD_TITLE:format(name)
    local function Run()
        local placed, cleared, missing = Profiles.Place(slots, opts)
        local keys = plan.bindings > 0 and ApplyBindings(plan.bindingList) or 0
        ns.Print(L.PROFILE_LOADED:format(name, placed, cleared, missing, keys))
        if ns.Tools then ns.Tools.RefreshKey("profiles") end
    end
    -- Makros, die neu entstehen, mit Namen (T6-1); bei mehr als MACROS_PER_PAGE zuerst Rückfragen mit „Weiter“,
    -- die letzte ist die gewohnte Rückfrage mit dem Plan. „Nein“ an jeder Stelle lädt nichts.
    local macroLines, risky = Profiles.MacroLines(plan)
    local per = Profiles.MACROS_PER_PAGE
    local pages = math.max(1, math.ceil(#macroLines / per))
    local function PageLines(page)
        local out = {}
        for index = (page - 1) * per + 1, math.min(#macroLines, page * per) do out[#out + 1] = macroLines[index] end
        return table.concat(out, "\n")
    end
    local function Head(page)
        local head = pages > 1 and L.PROFILE_MACROS_HEAD_PAGE:format(page, pages) or L.PROFILE_MACROS_HEAD
        -- die Warnung auf der ersten und auf der letzten Rückfrage (deren „Ja“ lädt; nach der Gegenprüfung)
        if risky > 0 and (page == 1 or page == pages) then
            head = L.PROFILE_MACROS_SCRIPT_WARN:format(risky) .. "\n" .. head
        end
        return head
    end
    local function Final()
        local extra = table.concat(lines, "\n")
        if #macroLines > 0 then extra = extra .. "\n\n" .. Head(pages) .. "\n" .. PageLines(pages) end
        return ns.Import.ConfirmPlan(plan, title, Run, extra, true)
    end
    local function Page(page)
        if page >= pages then return Final() end
        if ns.InCombat() then
            ns.CombatNotice()
            return false
        end
        Core.Confirm(title .. "\n\n" .. Head(page) .. "\n" .. PageLines(page), function()
            -- die nächste Rückfrage erst, wenn dieser Dialog zu ist (derselbe Dialog von ezCore)
            C_Timer.After(0, function() Page(page + 1) end)
        end, { accept = L.PROFILE_MACROS_NEXT })
        return true
    end
    return Page(1)
end

---------------------------------------------------------------------------
-- Werkzeug „Leisten-Profile“
---------------------------------------------------------------------------

local function Items()
    local items = {}
    for _, name in ipairs(Profiles.Names()) do
        local profile = Profiles.Get(name)
        local slots, macros = Profiles.Count(profile)
        local who = profile.class and ns.ClassName(profile.class) or ""
        items[#items + 1] = {
            key = name,
            icon = ns.IconPath({ "INV_Misc_Book_09", "INV_Misc_Book_11" }),
            text = name,
            sub = L.PROFILE_ROW:format(slots, macros, who, Core.Ago(profile.time)),
            grey = profile.class ~= nil and profile.class ~= ns.playerClass,
            -- aus Text übernommen: ohne Absender (der Export nimmt ihn seit T6-4 nicht mehr mit)
            tip = profile.imported and L.PROFILE_ROW_TIP_IMPORTED
                or L.PROFILE_ROW_TIP:format(profile.charName or profile.char or "?"),
        }
    end
    return items
end

local function DefaultName()
    local info = Core.CharInfo(ns.charKey) or {}
    return ns.ClassName(ns.playerClass) .. " (" .. tostring(info.name or Core.ShortName(Core.selfName)) .. ")"
end

ns.Tools.Register({
    key = "profiles", order = 30, icon = { "INV_Misc_Book_09", "INV_Misc_Book_11" },
    name = L.TOOL_PROFILES, why = L.TOOL_PROFILES_WHY, desc = L.TOOL_PROFILES_DESC,
    status = function()
        -- Rücksicht (Leitlinie 9): Läuft Myslot (ezCore, Funktion „barProfiles“), sagt die Seite das. ezMacros Profile
        -- tun ohnehin nur etwas auf Knopfdruck – nichts läuft doppelt (Fund aus Welle 5: der Erste Start führt ezMacro
        -- bei Myslot als zurücktretend, die Seite sagte davon nichts).
        local other = ns.OtherFor("barProfiles")
        if other then return UI.Colored("ORANGE_FONT_COLOR", L.PROFILE_OTHER:format(other)) end
        local n = #Profiles.Names()
        return n == 0 and L.PROFILE_NONE or L.PROFILE_STATUS:format(n)
    end,
    build = function(panel)
        panel.clearEmpty = UI.SettingCheck(panel, "profileClearEmpty")
        panel.clearEmpty:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", -4, -4)
        panel.bindings = UI.SettingCheck(panel, "profileBindings")
        panel.bindings:SetPoint("BOTTOMLEFT", panel.clearEmpty, "TOPLEFT", 0, -2)
        panel.macros = UI.SettingCheck(panel, "profileMacros")
        panel.macros:SetPoint("BOTTOMLEFT", panel.bindings, "TOPLEFT", 0, -2)

        panel.save = UI.Button(panel, L.PROFILE_SAVE, 100, function()
            local selected = panel.list:Selected()
            Core.AskText(L.PROFILE_SAVE_ASK, selected and selected.key or DefaultName(), function(text)
                local name = Core.Trim(text or "")
                if name == "" then return end
                if Profiles.Get(name) then
                    Core.Confirm(L.PROFILE_OVERWRITE:format(name), function() Profiles.Save(name) end)
                else
                    Profiles.Save(name)
                end
            end, 40)
        end, L.PROFILE_SAVE, L.PROFILE_SAVE_TIP)
        panel.save:SetPoint("BOTTOMLEFT", panel.macros, "TOPLEFT", 4, 2)
        panel.load = UI.Button(panel, L.PROFILE_LOAD, 90, function()
            local item = panel.list:Selected()
            if item then Profiles.Load(item.key) end
        end, L.PROFILE_LOAD, L.PROFILE_LOAD_TIP)
        panel.load:SetPoint("LEFT", panel.save, "RIGHT", 4, 0)
        panel.delete = UI.Button(panel, Core.Word("DELETE"), 90, function()
            local item = panel.list:Selected()
            if item then Profiles.Delete(item.key) end
        end, Core.Word("DELETE"), L.PROFILE_DELETE_TIP)
        panel.delete:SetPoint("LEFT", panel.load, "RIGHT", 4, 0)
        panel.text = UI.Button(panel, L.PROFILE_TEXT, 100, function()
            local item = panel.list:Selected()
            Profiles.TextDialog(item and item.key)
        end, L.PROFILE_TEXT, L.PROFILE_TEXT_TIP)
        panel.text:SetPoint("LEFT", panel.delete, "RIGHT", 4, 0)

        panel.list = UI.List(panel, "ezMacroProfileList", panel.width, function() ns.Tools.RefreshKey("profiles") end,
            function(item) Profiles.Load(item.key) end)
        -- Unten: drei Häkchen (je 24 hoch) und die Knopfzeile – zusammen rund 98 Punkte.
        panel.list.frame:SetPoint("TOPLEFT", panel.top, "BOTTOMLEFT", 0, -8)
        panel.list.frame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 98)
    end,
    refresh = function(panel)
        panel.list:SetItems(Items(), L.PROFILE_EMPTY)
        local selected = panel.list:Selected() ~= nil
        local free = not ns.InCombat()
        panel.save:SetEnabled(free)
        panel.load:SetEnabled(selected and free)
        panel.delete:SetEnabled(selected)
        panel.macros.Refresh()
        panel.bindings.Refresh()
        panel.clearEmpty.Refresh()
    end,
})
