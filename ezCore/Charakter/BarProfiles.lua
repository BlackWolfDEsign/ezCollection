local _, ns = ...
local Core = ezCore
local L = Core.L

--[[
    Leisten-Profile – Core.BarProfiles (Architektur-Review 22.11.2026; Entscheidung des Nutzers vom 22.11.2026 im
    ROADMAP-Index). Aktionsleisten samt Makros und auf Wunsch der Tastenbelegung unter einem Namen speichern und auf einem
    anderen Charakter laden – etwa für einen neuen Twink derselben Klasse (wie Myslot). Vorher lag das in ezMacro
    (ezMacroDB.profiles, ezMacro/Profiles.lua), und ezBars hatte ohne ezMacro keine Profile; jetzt nutzen ezMacro (Werkzeug
    „Leisten-Profile“) und ezBars (je Leiste „Als Profil speichern“/„Profil laden“) denselben Dienst.

    Nicht auf dem Gerüst Core.NewProfiles (Charakter/Profiles.lua): das kennt ein aktives Profil, sichert es beim
    Ausloggen und wendet beim Wechsel sofort an. Leisten-Profile sind benannte Schnappschüsse, die nur auf Knopfdruck
    entstehen und erst nach einer Rückfrage geladen werden (nur außerhalb des Kampfes: PickupAction/PlaceAction,
    CreateMacro und SetBinding sind im Kampf gesperrt). Gleiches Muster: Tabelle in der Datenbank, Texte aus ezCore,
    Umschlag über Core.Pack/Unpack, Zuhörer über OnChange.

    Gespeichert: ezCoreDB.barProfiles[name] = { name, class, char, charName, time, slots = { [platz] = daten }, partial,
    order = { plätze … } (Teil-Profil: Reihenfolge fürs Laden nach Reihenfolge), bindings = { { befehl, taste1, taste2 } },
    imported, bindingsDropped }. Plätze: Core.ActionSlots.USABLE (1–120 und 145–180; 121–144 nie anfassen).
    Übernahme: einmal aus ezMacroDB.profiles (Merker ezCoreDB.migrated.ezMacroProfiles, nur gesetzt, wenn ezMacroDB
    geladen war); der Altbestand in ezMacroDB bleibt liegen. Ein gleichnamiges Profil in ezCore bleibt, das alte kommt als
    „Name (2)“ dazu – nichts geht verloren.

      BP.All() → Tabelle aller Profile (übernimmt vorher einmal aus ezMacro)   BP.Migrate() → Anzahl übernommen
      BP.Get(name), BP.Names() (sortiert), BP.Count(profil) → belegte Plätze, Makros
      BP.CaptureSlot(platz), BP.Capture(plätze) → { [platz] = daten }   BP.Remap(daten, order, ziele)
      BP.Save(name, opts) → Profil. opts.slots (nur diese Plätze, Reihenfolge wird gespeichert; ohne Tasten),
          opts.owner (Absender der Meldung, Standard ezCollection)
      BP.Delete(name, opts) → true, wenn die Rückfrage kam
      BP.Export(name) → Text   BP.Import(text | tabelle) → Name | nil, Fehlertext   BP.ShareName(profil)
      BP.CleanSlot(daten), BP.KeyFormat(taste), BP.CleanKey(taste)
      BP.PlaceSpell(platz, id), BP.Place(daten, opts) → belegt, geleert, fehlend (ohne Rückfrage)
      BP.MacroNames() → { [Name] = Anzahl }
      BP.Movable(platz, makronamen) → true, wenn der Inhalt ohne Verlust wiederkäme (Zauber, Makro mit eindeutigem Namen,
          Gegenstand; leer: true)
      BP.Rearrange(plätze, ziel, opts) → verschoben, neu, entfernt, fehlend, Ergebnis (ohne Rückfrage): vorhandene Aktionen
          tauschen ihre Plätze (Aufnehmen/Ablegen, nichts wird neu gebaut), dazu neue Zauber
      BP.Exact(a, b) → genau derselbe Inhalt (Daten aus Capture)?
      BP.Restore(plätze, daten, opts) → belegt, entfernt, { fehlende Plätze } (ohne Rückfrage): genau wie in den Daten
          (Capture), auch der Rang; was auf diesen Plätzen schon liegt, wandert, nur der Rest wird neu aufgenommen
      BP.BindingSet(), BP.BindingSetText(), BP.BindingPlan(liste) → liste, verworfen, geänderte Tasten
      BP.Plan(profil, opts), BP.MacroLines(plan), BP.KeepLine(plan)
      BP.Load(name, opts) → true, wenn die Rückfrage gezeigt wurde. opts: slots, byOrder, macros, bindings, clearEmpty
          (Standard: BP.SetDefaults bzw. BP.DEFAULTS), owner
      BP.BestKnownSpell(id) → höchster gelernter Rang | nil
      BP.SetMacroHelper(h) – ein Modul mit eigener Makro-Verwaltung (ezMacro: lange Makros über 255 Zeichen):
          h.body(index) → ganzer Text, h.write(name, symbol, text, perChar) → Index | nil, h.maxChars() → Zahl,
          h.changed() nach neuen Makros. Ohne Helfer: Core.Macro (bis 255 Zeichen).
      BP.SetDefaults(fn) – fn() → { macros, bindings, clearEmpty } (ezMacro: seine drei Einstellungen)
      BP.OnChange(fn) – nach Speichern, Löschen, Übernehmen aus Text und Laden
]]

local BP = {}
Core.BarProfiles = BP

local AS = Core.ActionSlots

-- Kennung im Text: bleibt „ezMacro.profile“, damit Texte aus der Zeit vor dem Umzug weiter passen.
BP.KIND = "ezMacro.profile"
BP.VERSION = 1      -- Fassung des Umschlags; ein Text mit höherer Fassung stammt aus einem neueren ezCore
-- Höchstens so viele Makros je Rückfrage; bei mehr zeigen vorgeschaltete Rückfragen („Weiter“) den Rest, damit kein
-- Makro entsteht, dessen Namen der Spieler nicht gesehen hat.
BP.MACROS_PER_PAGE = 10
-- Standard beim Laden ohne Einstellungen eines Moduls; gleich wie ezMacros Einstellungen profileMacros,
-- profileBindings, profileClearEmpty (eine Prüfung in ezMacro/Tests hält beide gleich).
BP.DEFAULTS = { macros = true, bindings = false, clearEmpty = false }

local helper = {}
local defaultsFn
local listeners = {}
local scratch = {}   -- vor dem Laden von ezCoreDB: nichts kaputt machen

local function Print(owner, msg) Core.Print(owner or Core.name, msg) end

local function Changed()
    for _, fn in ipairs(listeners) do Core.Try(Core.name, "BarProfiles OnChange", fn) end
end

function BP.OnChange(fn)
    if type(fn) == "function" then listeners[#listeners + 1] = fn end
end

function BP.SetMacroHelper(h)
    helper = type(h) == "table" and h or {}
end

function BP.SetDefaults(fn)
    defaultsFn = type(fn) == "function" and fn or nil
end

local function PlayerClass() return (Core.me and Core.me.class) or Core.PlayerClass() end

---------------------------------------------------------------------------
-- Speicher und einmalige Übernahme aus ezMacro
---------------------------------------------------------------------------

local function Usable(name, profile)
    return type(name) == "string" and not Core.IsSecret(name) and name ~= ""
        and type(profile) == "table" and type(profile.slots) == "table"
end

-- Übernimmt einmal die Profile aus ezMacroDB.profiles. Ohne geladenes ezMacro (ezMacroDB fehlt) bleibt der Merker
-- leer: sobald ezMacro einmal läuft, holt der nächste Zugriff es nach. Der Altbestand bleibt in ezMacroDB liegen.
function BP.Migrate()
    local db = Core.db
    if type(db) ~= "table" then return 0 end
    if type(db.barProfiles) ~= "table" then db.barProfiles = {} end
    if type(db.migrated) ~= "table" then db.migrated = {} end
    if db.migrated.ezMacroProfiles then return 0 end
    local old = rawget(_G, "ezMacroDB")
    if type(old) ~= "table" then return 0 end
    local store, source, names, count = db.barProfiles, old.profiles, {}, 0
    if type(source) == "table" then
        for name, profile in pairs(source) do
            if Usable(name, profile) then names[#names + 1] = name end
        end
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local copy = Core.CopyTable(source[name])
        local target = name
        if store[target] ~= nil then
            target = Core.UniqueName(name, function(n) return store[n] ~= nil end, { default = L.BARPROFILES })
        end
        copy.name = target
        store[target] = copy
        count = count + 1
    end
    db.migrated.ezMacroProfiles = true
    return count
end

function BP.All()
    local db = Core.db
    if type(db) ~= "table" then return scratch end
    BP.Migrate()
    return db.barProfiles
end

function BP.Get(name)
    if type(name) ~= "string" or Core.IsSecret(name) then return nil end
    local profile = BP.All()[name]
    return type(profile) == "table" and profile or nil
end

function BP.Names()
    local names = {}
    for name, profile in pairs(BP.All()) do
        if type(name) == "string" and type(profile) == "table" then names[#names + 1] = name end
    end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

-- Belegte Plätze und Makros eines Profils.
function BP.Count(profile)
    local slots, macros = 0, 0
    for _, data in pairs(type(profile) == "table" and type(profile.slots) == "table" and profile.slots or {}) do
        slots = slots + 1
        if type(data) == "table" and data.kind == "macro" then macros = macros + 1 end
    end
    return slots, macros
end

---------------------------------------------------------------------------
-- Makros und Zauber
---------------------------------------------------------------------------

local function FindMacro(name, perChar)
    return (Core.Macro.Find(name, perChar))
end

local function MacroExists(name)
    return type(name) == "string" and (FindMacro(name, true) or FindMacro(name, false)) ~= nil
end

local function MacroBody(index)
    if type(helper.body) == "function" then
        local ok, body = Core.Try(helper.owner or Core.name, "BarProfiles body", helper.body, index)
        if ok then return body end
    end
    local _, _, body = Core.Call(rawget(_G, "GetMacroInfo"), index)
    return Core.Plain(body)
end

local function MaxChars()
    if type(helper.maxChars) == "function" then
        local ok, n = Core.Try(helper.owner or Core.name, "BarProfiles maxChars", helper.maxChars)
        if ok and Core.Num(n) then return Core.Num(n) end
    end
    return Core.Macro.MAX_CHARS
end

local function WriteMacro(item)
    if type(helper.write) == "function" then
        local ok, index = Core.Try(helper.owner or Core.name, "BarProfiles write", helper.write,
            item.name, item.icon, item.body, item.perChar)
        return ok and index or nil
    end
    return (Core.Macro.Write(item.name, item.icon, item.body, item.perChar))
end

-- Zauber-ID, die auf einen Aktionsplatz kommt: der höchste gelernte Rang aus dem Zauberbuch, sonst die ID selbst,
-- falls bekannt. nil = nicht gelernt.
function BP.BestKnownSpell(id)
    id = tonumber(id)
    if not id then return nil end
    local spells = Core.Spells
    local best = spells.Highest(id)
    if best then return best end
    if spells.IsKnown(id) then return id end
    return nil
end

---------------------------------------------------------------------------
-- Erfassen
---------------------------------------------------------------------------

-- Inhalt eines Aktionsplatzes als Tabelle, nil = leer oder gesperrt. Gelesen über Core.ActionSlots.Info (Art, ID,
-- Untertyp, Text – nie geheime Werte).
function BP.CaptureSlot(slot)
    local info = AS.Info(slot)
    if not info then return nil end
    local kind, id = info.kind, info.id
    if kind == "spell" then
        return { kind = "spell", id = id, name = (Core.Spells.Name(id)) }
    elseif kind == "macro" then
        -- Neuere Clients melden bei Makros, die einen Zauber zeigen, dessen ID statt des Makro-Index:
        -- zuerst der Name (Text des Platzes), der Index nur ohne Untertyp.
        local name = info.text
        local index = name and (FindMacro(name, true) or FindMacro(name, false))
        if not index and type(id) == "number" and info.subType == nil then index = id end
        if not index then return nil end
        local macroName, icon = Core.Call(rawget(_G, "GetMacroInfo"), index)
        macroName, icon = Core.Plain(macroName), Core.Plain(icon)
        if type(macroName) ~= "string" then return nil end
        local maxAccount = Core.Macro.Limits()
        return { kind = "macro", name = macroName, icon = icon, body = MacroBody(index), perChar = index > maxAccount }
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
function BP.Capture(slots)
    local data = {}
    for _, slot in ipairs(slots or AS.USABLE) do
        data[slot] = BP.CaptureSlot(slot)
    end
    return data
end

local function CaptureBindings()
    local list = {}
    if type(GetNumBindings) ~= "function" or type(GetBinding) ~= "function" then return list end
    for index = 1, GetNumBindings() do
        local command, _, key1, key2 = GetBinding(index)
        if type(command) == "string" and not Core.IsSecret(command) and (key1 or key2) then
            list[#list + 1] = { command, key1, key2 }
        end
    end
    return list
end

-- Daten der Plätze order[k] auf die Plätze targets[k] umlegen (Laden nach Reihenfolge, z. B. ezBars:
-- Leiste 1 liegt beim Magier auf 73–84, beim Krieger auf 145–156).
function BP.Remap(data, order, targets)
    local out = {}
    for index, target in ipairs(targets or {}) do
        local source = order and order[index]
        if source and data[source] then out[target] = data[source] end
    end
    return out
end

-- Speichert die Leisten unter einem Namen (überschreibt ein gleichnamiges Profil).
-- opts.slots: nur diese Plätze (ezBars), sonst alle; ihre Reihenfolge wird mitgespeichert (profile.order).
function BP.Save(name, opts)
    name = Core.Trim(tostring(name or ""))
    if name == "" then return nil end
    opts = opts or {}
    local info = Core.CharInfo(Core.charKey) or {}
    local profile = {
        name = name, class = PlayerClass(), char = Core.charKey, charName = info.name, time = Core.Now(),
        slots = BP.Capture(opts.slots), partial = opts.slots and true or nil,
        order = opts.slots and Core.CopyList(opts.slots) or nil,
        -- Tastenbelegungen gehören dem ganzen Charakter: nur ein volles Profil nimmt sie mit, ein Teil-Profil
        -- (ezBars: eine Leiste) soll beim Laden nie alle Tasten ändern.
        bindings = not opts.slots and CaptureBindings() or nil,
    }
    BP.All()[name] = profile
    Print(opts.owner, L.BARPROFILE_SAVED:format(name, (BP.Count(profile))))
    Changed()
    return profile
end

function BP.Delete(name, opts)
    if not BP.Get(name) then return false end
    opts = opts or {}
    Core.Confirm(L.BARPROFILE_DELETE_CONFIRM:format(name), function()
        BP.All()[name] = nil
        Changed()
    end)
    return true
end

---------------------------------------------------------------------------
-- Als Text (wie Myslot): Core.Pack mit { kind = BP.KIND, v = 1, profile = … }
---------------------------------------------------------------------------

-- Felder, die nicht in einen Text zum Weitergeben gehören (Gesamtreview 18.11.2026, T6-4): Charakter samt Realm und
-- Charaktername; „imported“ ist nur eine eigene Markierung.
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
-- „Leisten-Profile“).
function BP.ShareName(profile)
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
    if name == "" then return profile.class and Core.ClassName(profile.class) or nil end
    return name
end

-- Umschlag { kind, v, profile } über Core.Pack; eine Kopie ohne die Felder aus EXPORT_SKIP.
function BP.Export(name)
    local profile = BP.Get(name)
    if not profile then return nil end
    local copy = {}
    for key, value in pairs(profile) do
        if not EXPORT_SKIP[key] then copy[key] = value end
    end
    copy.name = BP.ShareName(profile)
    return (Core.Pack(BP.KIND, BP.VERSION, { profile = copy }))
end

-- Freier Name „Profil“, „Profil (2)“ … (Core.UniqueName). Ein Name aus fremdem Text verliert Farbcodes, Links, „|“,
-- Steuerzeichen und Umbrüche (Core.CleanImportName, T6-5).
local function FreeName(base)
    local clean = base ~= nil and Core.CleanImportName(tostring(base)) or nil
    return Core.UniqueName(clean, function(name) return BP.Get(name) ~= nil end, { default = L.BARPROFILES })
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
-- beim Anlegen bereinigt (Core.Macro.CleanName), damit Plan, Platzwahl und Anlegen denselben Namen suchen.
function BP.CleanSlot(data)
    if type(data) ~= "table" or type(data.kind) ~= "string" then return nil end
    local need = SLOT_ID[data.kind]
    if not need then return nil end
    if need == "macro" then
        local name = type(data.name) == "string" and Core.Macro.CleanName(data.name) or ""
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
-- Form einer Taste aus fremdem Text (Core.Keys.NormalizeKey mit opts.sides: linke und rechte Zusatztasten bleiben).
-- Gesperrte Tasten haben die richtige Form; ausgefiltert werden sie erst von BP.CleanKey. Rückgabe: Taste (in Blizzards
-- Schreibweise), Zusatztasten, eigentliche Taste.
function BP.KeyFormat(key)
    if type(key) ~= "string" then return nil end
    return Core.Keys.NormalizeKey(key, { sides = true })
end

-- Taste, die ein Profil belegen darf: richtige Form (BP.KeyFormat) und nicht gesperrt. Rückgabe: Taste oder nil.
function BP.CleanKey(key)
    local ok, parts, main = BP.KeyFormat(key)
    if not ok or BLOCKED_KEYS[main] or (#parts == 0 and BLOCKED_PLAIN[main]) then return nil end
    return ok
end

-- Übernimmt ein Profil aus Text (nur Plätze 1–120 und 145–180, nur bekannte Arten mit passenden Feldern, Tasten
-- in der Form von BP.KeyFormat; der Charaktername des Absenders bleibt draußen, das Profil gilt als „aus Text“).
-- Gesperrte Tasten (Esc …) bleiben im Profil stehen: BP.BindingPlan filtert sie beim Laden und nennt sie in der
-- Rückfrage, außer sie lösen schon genau diesen Befehl aus. Einträge ohne brauchbare Taste oder ohne Befehl fallen
-- schon hier weg; ihre Zahl steht in profile.bindingsDropped und zählt beim Laden mit.
-- Rückgabe: Name des neuen Profils oder nil, Fehlertext. Ein Text aus einem neueren ezCore bekommt eine eigene Meldung.
function BP.Import(value)
    if type(value) == "table" then value = Core.Serialize(value) end
    local why
    value, why = Core.Unpack(value, BP.KIND, BP.VERSION)
    if why == "newer" then return nil, L.BARPROFILE_IMPORT_NEWER end
    if type(value) ~= "table" or type(value.profile) ~= "table" or type(value.profile.slots) ~= "table" then
        return nil, L.BARPROFILE_IMPORT_BAD
    end
    local source = value.profile
    local profile = {
        name = nil, class = type(source.class) == "string" and source.class or nil,
        time = tonumber(source.time) or Core.Now(), slots = {}, bindings = {},
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
        local clean = AS.IsUsable(slot) and BP.CleanSlot(data)
        if clean then profile.slots[slot] = clean end
    end
    local dropped = 0
    for _, binding in ipairs(type(source.bindings) == "table" and source.bindings or {}) do
        local key1, key2
        if type(binding) == "table" and type(binding[1]) == "string" and binding[1] ~= ""
            and not binding[1]:find("[%c]") then
            key1, key2 = BP.KeyFormat(binding[2]), BP.KeyFormat(binding[3])
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
    BP.All()[name] = profile
    Changed()
    return name
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

-- Legt einen Zauber (genau diese ID, also diesen Rang) auf einen Platz; für ezMacros „Ränge aktualisieren“.
function BP.PlaceSpell(slot, id)
    if Core.InCombat() or not (PlaceAction and ClearCursor) then return false end
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
    if data.kind == "spell" then return BP.BestKnownSpell(data.id) ~= nil end
    if data.kind == "macro" then
        return macroNames[data.name] or FindMacro(data.name, data.perChar) ~= nil
            or FindMacro(data.name, not data.perChar) ~= nil
    end
    return data.kind ~= "other"
end

local function Same(a, b)
    if not (a and b) or a.kind ~= b.kind then return false end
    if a.kind == "macro" then return a.name == b.name end
    if a.kind == "spell" then return BP.BestKnownSpell(a.id) == b.id end
    return a.id == b.id
end

local function Pick(data)
    if data.kind == "spell" then
        local id = BP.BestKnownSpell(data.id)
        if id then PickupSpellID(id) end
    elseif data.kind == "macro" then
        local index = FindMacro(data.name, data.perChar) or FindMacro(data.name, not data.perChar)
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
function BP.Place(data, opts)
    opts = opts or {}
    if Core.InCombat() or not (PlaceAction and PickupAction and ClearCursor) then return 0, 0, 0 end
    local placed, cleared, missing = 0, 0, 0
    for _, slot in ipairs(opts.slots or AS.USABLE) do
        local want = data[slot]
        if want then
            if not Same(want, BP.CaptureSlot(slot)) then
                ClearCursor()
                Core.Try(opts.owner or Core.name, "BarProfiles Place", Pick, want)
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

-- Wie viele Makros tragen diesen Namen? Für Movable: zwei gleichnamige ließen sich nicht auseinanderhalten.
function BP.MacroNames()
    local names = {}
    local account, char = Core.Macro.Counts()
    local first = (Core.Macro.Limits()) + 1
    for _, range in ipairs({ { 1, account }, { first, first + char - 1 } }) do
        for index = range[1], range[2] do
            local name = Core.Plain((Core.Call(rawget(_G, "GetMacroInfo"), index)))
            if type(name) == "string" then names[name] = (names[name] or 0) + 1 end
        end
    end
    return names
end

-- Käme der Inhalt dieses Platzes aus einem Profil genau so wieder? Nur Zauber, Makros (Name nur einmal) und Gegenstände;
-- gesperrte und unbekannte Inhalte, Befehle und Zauber des Begleiters, Reittiere, Sets usw. bleiben beim Umordnen, wo sie
-- sind. Ein leerer Platz ist frei.
function BP.Movable(slot, macroNames)
    if not AS.Has(slot) then return true end
    local data, info = BP.CaptureSlot(slot), AS.Info(slot)
    if not (data and info) then return false end
    if data.kind == "spell" then
        if info.subType == "pet" then return false end
        return Core.Spells.IsKnown(data.id) == true or BP.BestKnownSpell(data.id) ~= nil
    elseif data.kind == "macro" then
        return ((macroNames or BP.MacroNames())[data.name] or 0) <= 1
    end
    return data.kind == "item"
end

-- Genau derselbe Inhalt? Zauber samt Rang, Makros nach Name und Bereich.
function BP.Exact(a, b)
    if not (a and b) or a.kind ~= b.kind then return false end
    if a.kind == "macro" then return a.name == b.name and a.perChar == b.perChar end
    return a.id == b.id
end

-- Was hängt am Mauszeiger, als Text zum Vergleichen (nil: nichts).
local function CursorKey()
    if type(GetCursorInfo) ~= "function" then return nil end
    local parts = { GetCursorInfo() }
    if parts[1] == nil then return nil end
    for i = 1, 4 do parts[i] = tostring(Core.Plain(parts[i])) end
    return table.concat(parts, ":", 1, 4)
end

-- Ordnet die Plätze um (nur außerhalb des Kampfes, nie mit etwas am Mauszeiger; ohne Rückfrage).
-- want[platz] = { from = platz } (Aktion, die jetzt dort liegt) | { spell = id } (neuer Zauber) | nil (danach leer,
-- sofern dort nichts Eigenes landet). Vorhandene Aktionen werden aufgenommen und abgelegt, nicht neu gebaut: Makros,
-- Ränge und Reittiere bleiben genau, wie sie sind. Was kein Ziel hat, geht von der Leiste.
-- → verschoben, neu, entfernt, fehlend, Ergebnis[platz] = { from } | { spell } | nil (leer);
--   nil, Grund ("combat", "cursor", "missing")
function BP.Rearrange(slots, want, opts)
    opts = opts or {}
    if Core.InCombat() then return nil, "combat" end
    if not (PlaceAction and PickupAction and ClearCursor) then return nil, "missing" end
    if CursorHasAction() then return nil, "cursor" end
    local owner = opts.owner or Core.name
    local at, where, content = {}, {}, {}      -- Platz → Herkunft des Inhalts, Herkunft → Platz, Herkunft → Inhalt
    for _, slot in ipairs(slots) do
        if AS.Has(slot) then at[slot], where[slot], content[slot] = slot, slot, BP.CaptureSlot(slot) end
    end
    local moved, placed, removed, missing = 0, 0, 0, 0
    local kept, result = {}, {}
    for _, slot in ipairs(slots) do
        local from = want[slot] and want[slot].from
        if from then
            kept[from] = true
            local now = where[from]
            if not now then
                missing = missing + 1
            elseif now ~= slot then
                PickupAction(now)
                local taken = CursorKey()
                if taken then
                    PlaceAction(slot)                       -- der alte Inhalt hängt danach am Mauszeiger
                    local held, old = CursorKey(), at[slot]
                    if held then PlaceAction(now) end
                    if held and (not old or (held == taken and not BP.Exact(content[from], content[old]))) then
                        missing = missing + 1               -- nicht angenommen: wieder an seinen Platz
                    else
                        if old then where[old] = held and now or nil end
                        at[now], at[slot] = held and old or nil, from
                        where[from] = slot
                        moved = moved + 1
                    end
                else
                    missing = missing + 1
                end
                ClearCursor()
            end
        end
    end
    for _, slot in ipairs(slots) do
        local target, origin = want[slot], at[slot]
        local free = origin ~= nil and not kept[origin]     -- liegt noch da, hat aber kein Ziel
        if target and target.spell then
            if origin == nil or free then
                ClearCursor()
                Core.Try(owner, "BarProfiles Rearrange", PickupSpellID, target.spell)
                local taken = CursorKey()
                local ok = taken ~= nil
                if ok then
                    PlaceAction(slot)
                    local held, old = CursorKey(), origin and content[origin]
                    if held and (origin == nil or (held == taken and not (old and old.kind == "spell" and old.id == target.spell))) then
                        ok = false                          -- nicht angenommen
                    end
                end
                if ok then
                    placed = placed + 1
                    if free then removed = removed + 1 end
                    result[slot], at[slot] = { spell = target.spell }, nil
                else
                    missing = missing + 1
                end
                ClearCursor()
            else
                missing = missing + 1
            end
        elseif free and not target then
            PickupAction(slot)
            ClearCursor()
            at[slot] = nil
            removed = removed + 1
        end
    end
    for _, slot in ipairs(slots) do
        if at[slot] then result[slot] = { from = at[slot] } end
    end
    if moved + placed + removed > 0 then Changed() end
    return moved, placed, removed, missing, result
end

-- Stellt Plätze genau wieder her (nur außerhalb des Kampfes, ohne Rückfrage). data[platz] wie von Capture, fehlt ein
-- Platz dort, wird er leer. Was auf diesen Plätzen schon liegt, wandert an seinen Platz (Rearrange); nur was fehlt, wird
-- neu aufgenommen – Zauber mit ihrem Rang (Place nimmt den höchsten; gibt es den Rang nicht mehr, gilt der höchste).
-- → belegt, entfernt, { fehlende Plätze } | nil, Grund ("combat", "cursor", "missing")
function BP.Restore(slots, data, opts)
    opts = opts or {}
    if Core.InCombat() then return nil, "combat" end
    local now, want, used, build = {}, {}, {}, {}
    for _, slot in ipairs(slots) do now[slot] = BP.CaptureSlot(slot) end
    for _, slot in ipairs(slots) do
        if BP.Exact(data[slot], now[slot]) then want[slot], used[slot] = { from = slot }, true end
    end
    for _, slot in ipairs(slots) do
        if data[slot] and not want[slot] then
            for _, other in ipairs(slots) do
                if not want[slot] and not used[other] and BP.Exact(data[slot], now[other]) then
                    want[slot], used[other] = { from = other }, true
                end
            end
            if not want[slot] then build[#build + 1] = slot end
        end
    end
    local moved, why, removed, _, result = BP.Rearrange(slots, want, opts)
    if not moved then return nil, why end
    local placed, missing = moved, {}
    for _, slot in ipairs(slots) do
        local is = result[slot]
        if want[slot] and not (is and is.from == want[slot].from) then missing[#missing + 1] = slot end
    end
    local function Put(slot, pick, ...)
        ClearCursor()
        Core.Try(opts.owner or Core.name, "BarProfiles Restore", pick, ...)
        local ok = CursorHasAction()
        if ok then
            PlaceAction(slot)
            ok = not CursorHasAction()      -- der Platz war leer: bleibt etwas am Mauszeiger, nahm er es nicht an
        end
        ClearCursor()
        return ok
    end
    for _, slot in ipairs(build) do
        local item, ok = data[slot], false
        -- Liegt dort noch etwas (ließ sich nicht wegnehmen), bleibt es liegen
        if not result[slot] then
            ok = item.kind == "spell" and Put(slot, PickupSpellID, item.id) or Put(slot, Pick, item)
        end
        if ok then placed = placed + 1 else missing[#missing + 1] = slot end
    end
    table.sort(missing)
    Changed()
    return placed, removed, missing
end

-- Belegungssatz, in den SetBinding schreibt und SaveBindings speichert: Blizzards aktuell gewählter (1 = kontoweit,
-- 2 = je Charakter; Häkchen „Charakterspezifische Tastaturbelegung“). Der Dienst stellt ihn nie um (T9-NB4).
local ACCOUNT_SET = 1
function BP.BindingSet()
    local set = type(GetCurrentBindingSet) == "function" and GetCurrentBindingSet() or nil
    if Core.IsSecret(set) or set == nil then return 2 end
    return set
end

-- Für Rückfrage und Tooltip: für wen die Tasten gelten.
function BP.BindingSetText()
    local account = rawget(_G, "ACCOUNT_BINDINGS") or ACCOUNT_SET
    return BP.BindingSet() == account and L.BARPROFILE_BINDINGS_ACCOUNT or L.BARPROFILE_BINDINGS_CHAR
end

-- Befehle, die der Client als Tastenbelegung kennt (GetBinding; ohne Überschriften). Nur sie übernimmt ein Profil
-- (T9-NB5): ein eigenes Profil enthält ohnehin nur sie, ein fremder Text bringt keinen anderen mit.
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

-- Was die Taste heute auslöst: lesbarer Name und Befehl, nil = nichts (Core.Keys.Conflict).
local function KeyAction(key)
    local keys = Core.Keys
    if not (keys and keys.Conflict) then return nil end
    return keys.Conflict(key)
end

-- Ein früherer Befehl aus ezCores Tasten-Dienst zählt als sein heutiger (Core.Keys.CurrentCommand; Nachlauf zu T9-NB1):
-- den früheren kennt der Client nicht mehr, die Taste fiele sonst beim Laden weg. Das gespeicherte Profil bleibt, wie
-- es ist – die Übersetzung gilt bei jedem Laden, auch für eingefügte Texte.
local function CurrentCommand(command)
    local keys = Core.Keys
    if keys and type(keys.CurrentCommand) == "function" then return keys.CurrentCommand(command) end
    return command
end

-- Tastenbelegungen für das Laden: nur bekannte Befehle und erlaubte Tasten. Rückgabe: Liste { befehl, taste1, taste2 },
-- Zahl der verworfenen Einträge, Liste der Tasten, die heute etwas anderes auslösen (je „Taste (bisher …)“ mit dem
-- Namen aus dem Client, „|“ verdoppelt). Eine gesperrte Taste, die schon genau diesen Befehl auslöst (Esc öffnet das
-- Spielmenü, Druck macht ein Bildschirmfoto – so steht es in jedem eigenen Profil), zählt nicht als verworfen.
function BP.BindingPlan(list)
    local known, out, skipped, changed = KnownCommands(), {}, 0, {}
    for _, binding in ipairs(list or {}) do
        local command = type(binding) == "table" and CurrentCommand(binding[1])
        local keys, unchanged = {}, false
        if type(command) == "string" and known[command] then
            for index = 2, 3 do
                local raw = binding[index]
                local key = BP.CleanKey(raw)
                if key then
                    keys[index] = key
                    local name, action = KeyAction(key)
                    if action and action ~= command then
                        changed[#changed + 1] = L.BARPROFILE_KEY_WAS:format(key, (tostring(name):gsub("|", "||")))
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
    SaveBindings(BP.BindingSet())
    return n
end

-- Plan für das Laden: fehlende Makros (über Core.Macro.Plan), Plätze, die sich ändern, Fehlendes.
-- Ein Profil legt nur Makros an, die es unter dem bereinigten Namen in keinem der beiden Bereiche gibt; ein
-- vorhandenes Makro ersetzt es nie (T6-1: sonst fände ein Name wie „Heilen “ dein Makro „Heilen“ und überschriebe es
-- ohne eigene Rückfrage). Die Namen solcher Einträge stehen unter plan.keep (je Name einmal, sortiert): auf ihre
-- Plätze kommt dein vorhandenes Makro, nicht der Text aus dem Profil. opts.macros = false: keine Makros anlegen.
function BP.Plan(profile, opts)
    opts = opts or {}
    local macros, macroNames, keep, kept = {}, {}, {}, {}
    if opts.macros ~= false then
        for _, data in pairs(profile.slots or {}) do
            local name = data.kind == "macro" and Core.Macro.CleanName(data.name)
            if name and name ~= "" then
                -- vorhanden unter dem gespeicherten oder dem bereinigten Namen, in einem der beiden Bereiche
                if not MacroExists(data.name) and not MacroExists(name) then
                    macros[#macros + 1] = { name = name, icon = data.icon, body = data.body, perChar = data.perChar }
                elseif not kept[name] then
                    kept[name] = true
                    keep[#keep + 1] = name
                end
            end
        end
    end
    table.sort(keep)
    local plan = Core.Macro.Plan(macros, { maxChars = MaxChars(), body = MacroBody })
    plan.keep, plan.replace = keep, {}   -- replace bleibt leer: der Plan sieht nur Makros, die es nicht gibt
    plan.changes = #plan.create
    for _, item in ipairs(plan.create) do macroNames[item.name] = true end
    local change, clear, missing = 0, 0, 0
    for _, slot in ipairs(opts.slots or AS.USABLE) do
        local data = profile.slots[slot]
        if data then
            if not Placeable(data, macroNames) then
                missing = missing + 1
            elseif not Same(data, BP.CaptureSlot(slot)) then
                change = change + 1
            end
        elseif opts.clearEmpty and AS.Has(slot) then
            clear = clear + 1
        end
    end
    plan.slotChange, plan.slotClear, plan.slotMissing = change, clear, missing
    plan.bindingList, plan.bindingSkipped, plan.bindingChanged = {}, 0, {}
    if opts.bindings then
        plan.bindingList, plan.bindingSkipped, plan.bindingChanged = BP.BindingPlan(profile.bindings)
        -- schon beim Import verworfene Einträge zählen mit
        plan.bindingSkipped = plan.bindingSkipped + (tonumber(profile.bindingsDropped) or 0)
    end
    plan.bindings = #plan.bindingList
    return plan
end

-- Zeilen der Rückfrage zu den Makros, die neu entstehen (T6-1): je Makro der Name, dahinter rot die Befehle, die
-- Lua-Code ausführen oder Client-Einstellungen ändern. Rückgabe: Zeilen, Zahl der Makros mit solchen Befehlen.
function BP.MacroLines(plan)
    local lines, risky = {}, 0
    for _, item in ipairs(plan.create or {}) do
        -- „|“ verdoppelt: ein Name aus fremdem Text färbt oder versteckt so nichts in der Rückfrage
        local line = L.BARPROFILE_MACRO_LINE:format((item.name:gsub("|", "||")))
        local commands = Core.Macro.ScriptCommands(item.body)
        if #commands > 0 then
            risky = risky + 1
            line = line .. " " .. Core.Style.ColorText("bad", L.BARPROFILE_MACRO_SCRIPT:format(table.concat(commands, ", ")))
        end
        lines[#lines + 1] = line
    end
    return lines, risky
end

-- Zeile der Rückfrage zu Makros aus einem fremden Profil, die es bei dir schon gibt (T6-1): sie bleiben unverändert,
-- auf ihre Plätze kommt dein Makro. Die ersten fünf mit Namen, „|“ verdoppelt.
local SHOW_KEEP = 5
function BP.KeepLine(plan)
    local keep = plan.keep or {}
    if #keep == 0 then return nil end
    local shown = {}
    for index = 1, math.min(#keep, SHOW_KEEP) do shown[index] = (keep[index]:gsub("|", "||")) end
    local text = table.concat(shown, ", ")
    if #keep > SHOW_KEEP then text = text .. " " .. Core.More(#keep - SHOW_KEEP, true) end
    return L.BARPROFILE_PLAN_KEEP:format(#keep, text)
end

-- Zeilen der Rückfrage zu den Tasten (T9-NB4, T9-NB5): Anzahl samt Belegungssatz, Verworfenes, Tasten, die heute
-- etwas anderes auslösen (die ersten fünf mit Namen).
local SHOW_KEYS = 5
local function BindingLines(plan, lines)
    if plan.bindings > 0 then
        lines[#lines + 1] = L.BARPROFILE_PLAN_BINDINGS:format(plan.bindings, BP.BindingSetText())
        local changed = plan.bindingChanged
        if #changed > 0 then
            local shown = {}
            for index = 1, math.min(#changed, SHOW_KEYS) do shown[index] = changed[index] end
            local text = table.concat(shown, ", ")
            if #changed > SHOW_KEYS then text = text .. " " .. Core.More(#changed - SHOW_KEYS, true) end
            lines[#lines + 1] = L.BARPROFILE_PLAN_BINDINGS_CHANGED:format(#changed, text)
        end
    end
    if plan.bindingSkipped > 0 then
        lines[#lines + 1] = L.BARPROFILE_PLAN_BINDINGS_SKIPPED:format(plan.bindingSkipped)
    end
end

-- Wert aus opts, sonst aus den Einstellungen des Moduls (BP.SetDefaults), sonst BP.DEFAULTS. Ein ausgeschalteter
-- Schalter (false) bleibt false (vorher wurde aus „nicht anlegen“ nil und damit doch „anlegen“).
local function Choose(value, defaults, key)
    if value ~= nil then return value and true or false end
    local own = defaults and defaults[key]
    if own ~= nil then return own and true or false end
    return BP.DEFAULTS[key]
end

local function LoadOptions(opts)
    opts = opts or {}
    local defaults
    if defaultsFn then
        local ok, value = Core.Try(Core.name, "BarProfiles defaults", defaultsFn)
        defaults = ok and type(value) == "table" and value or nil
    end
    return {
        slots = opts.slots,
        macros = Choose(opts.macros, defaults, "macros"),
        bindings = Choose(opts.bindings, defaults, "bindings"),
        clearEmpty = Choose(opts.clearEmpty, defaults, "clearEmpty"),
        byOrder = opts.byOrder and true or nil,
        owner = opts.owner,
    }
end

local function CombatNotice(owner)
    Core.CombatNotice(owner or Core.name, L.BARPROFILE_COMBAT_WHAT, nil, { center = true })
end

-- Legt die fehlenden Makros an (außerhalb des Kampfes). Rückgabe: Anzahl.
local function CreateMacros(plan)
    local done = 0
    for _, item in ipairs(plan.create) do
        if WriteMacro(item) then done = done + 1 end
    end
    if done > 0 and type(helper.changed) == "function" then
        Core.Try(helper.owner or Core.name, "BarProfiles changed", helper.changed)
    end
    return done
end

-- Lädt ein Profil nach **einer** Rückfrage (bei mehr als BP.MACROS_PER_PAGE neuen Makros vorher je so viele Namen
-- mit „Weiter“). opts wie BP.Place, dazu macros/bindings/clearEmpty (Standard: BP.SetDefaults, sonst BP.DEFAULTS).
-- opts.byOrder mit opts.slots: den k-ten gespeicherten Platz (profile.order) auf opts.slots[k] legen.
function BP.Load(name, opts)
    local profile = BP.Get(name)
    if not profile then return false end
    opts = LoadOptions(opts)
    local owner = opts.owner
    if Core.InCombat() then
        CombatNotice(owner)
        return false
    end
    local slots = profile.slots
    if opts.byOrder and opts.slots then
        slots = BP.Remap(profile.slots, profile.order or opts.slots, opts.slots)
    end
    local view = { slots = slots, bindings = profile.bindings, class = profile.class,
        bindingsDropped = profile.bindingsDropped }
    local plan = BP.Plan(view, opts)
    local lines = { L.BARPROFILE_PLAN_SLOTS:format(plan.slotChange) }
    if plan.slotClear > 0 then lines[#lines + 1] = L.BARPROFILE_PLAN_CLEAR:format(plan.slotClear) end
    if plan.slotMissing > 0 then lines[#lines + 1] = L.BARPROFILE_PLAN_MISSING:format(plan.slotMissing) end
    -- nur bei Profilen aus Text: in einem eigenen Profil sind vorhandene Makros der Normalfall
    local keepLine = profile.imported and BP.KeepLine(plan)
    if keepLine then lines[#lines + 1] = keepLine end
    BindingLines(plan, lines)
    if profile.class and profile.class ~= PlayerClass() then
        lines[#lines + 1] = L.BARPROFILE_PLAN_CLASS:format(Core.ClassName(profile.class))
    end
    local title = L.BARPROFILE_LOAD_TITLE:format(name)
    local function Run()
        local placed, cleared, missing = BP.Place(slots, opts)
        local keys = plan.bindings > 0 and ApplyBindings(plan.bindingList) or 0
        Print(owner, L.BARPROFILE_LOADED:format(name, placed, cleared, missing, keys))
        Changed()
    end
    -- Makros, die neu entstehen, mit Namen (T6-1); bei mehr als MACROS_PER_PAGE zuerst Rückfragen mit „Weiter“,
    -- die letzte ist die gewohnte Rückfrage mit dem Plan. „Nein“ an jeder Stelle lädt nichts.
    local macroLines, risky = BP.MacroLines(plan)
    local per = math.max(1, math.floor(Core.Num(BP.MACROS_PER_PAGE) or 10))
    local pages = math.max(1, math.ceil(#macroLines / per))
    local function PageLines(page)
        local out = {}
        for index = (page - 1) * per + 1, math.min(#macroLines, page * per) do out[#out + 1] = macroLines[index] end
        return table.concat(out, "\n")
    end
    local function Head(page)
        local head = pages > 1 and L.BARPROFILE_MACROS_HEAD_PAGE:format(page, pages) or L.BARPROFILE_MACROS_HEAD
        -- die Warnung auf der ersten und auf der letzten Rückfrage (deren „Ja“ lädt)
        if risky > 0 and (page == 1 or page == pages) then
            head = L.BARPROFILE_MACROS_SCRIPT_WARN:format(risky) .. "\n" .. head
        end
        return head
    end
    local function Final()
        -- auch nach „Weiter“: im Kampf keine letzte Rückfrage (wie früher ezMacros Import.ConfirmPlan)
        if Core.InCombat() then
            CombatNotice(owner)
            return false
        end
        local text = L.MACRO_PLAN_CONFIRM:format(title, Core.Macro.PlanText(plan)) .. "\n" .. table.concat(lines, "\n")
        if #macroLines > 0 then text = text .. "\n\n" .. Head(pages) .. "\n" .. PageLines(pages) end
        Core.Confirm(text, function()
            if Core.InCombat() then return CombatNotice(owner) end
            local done = CreateMacros(plan)
            Print(owner, L.MACRO_PLAN_DONE:format(title, done, Core.Macro.PlanText(plan)))
            Run()
        end)
        return true
    end
    local function Page(page)
        if page >= pages then return Final() end
        if Core.InCombat() then
            CombatNotice(owner)
            return false
        end
        Core.Confirm(title .. "\n\n" .. Head(page) .. "\n" .. PageLines(page), function()
            -- die nächste Rückfrage erst, wenn dieser Dialog zu ist (derselbe Dialog von ezCore)
            C_Timer.After(0, function() Page(page + 1) end)
        end, { accept = L.BARPROFILE_MACROS_NEXT })
        return true
    end
    return Page(1)
end
