local _, ns = ...
local Core = ezCore

--[[
    Blizzards Klick-Zaubern an einer Stelle (C_ClickBindings; Wunsch ezHeal vom 13.11.2026): lesen, schreiben,
    Fenster öffnen, Belegungen zusammenbauen, benannte Profile. Vorher lasen ezMacro (Ränge aktualisieren) und
    ActionSlots.ClickBindings die Liste je selbst, und geschrieben wurde ohne Kampfprüfung.
    Reine Datenfunktionen – die Oberfläche (Knöpfe, Profil-Liste neben Blizzards Fenster) baut ezHeal.
    Geschrieben wird nur über Blizzards eigene Funktion SetProfileByInfo, per pcall und nur außerhalb des Kampfes;
    nichts in Blizzards Tabellen (Leitlinie 5).

    Eintrag (bereinigt, so liefert und nimmt ihn jede Funktion hier):
      { kind = "spell" | "macro" | "interaction" | "pet" | "other", type = Blizzards Zahl (Enum.ClickBindingType),
        id = actionID, button = "LeftButton" …, modifiers = Zahl (Blizzards Maske),
        name = Makroname (nur kind "macro"), action = "target" | "menu" (nur kind "interaction") }

      Core.ClickBindings.Available() → true, wenn der Client Klick-Zauber lesen kann
      Core.ClickBindings.Writable()  → true, wenn er sie auch schreiben kann (SetProfileByInfo)
      Core.ClickBindings.List()      → liste, vollständig | nil, "missing" | nil, "error"
                                       vollständig = false: Blizzard lieferte Einträge, die sich nicht lesen ließen
      Core.ClickBindings.IDs(kind, liste) → { [actionID] = true } (ohne liste: die aktuelle Belegung)
      Core.ClickBindings.Set(liste, opts) → true | true, "same" (nichts zu ändern) | false, grund; dritter Wert
                                       { skipped = { … }, dropped = { … } }
        opts   keepDefaults  Standard true: Blizzards Einträge „Ziel“ und „Menü“ bleiben (siehe KeepDefaults)
               backup        Standard true: die alte Belegung vorher sichern (siehe Backup)
               checkSpells   true: Zauber auslassen, die der Charakter nicht per Klick wirken kann (Standard bei Load)
               force         true: auch schreiben, wenn die alte Belegung nicht ganz lesbar war
               quiet         true: kein Hinweis im Kampf, keine Meldung bei einem Fehler (der Hinweis auf
                             ungespeicherte Änderungen in Blizzards Fenster kommt trotzdem, siehe Reload)
               owner         Modulname für Fehlerliste und Meldung
               onDone        fn(ok, grund, einzelheiten) – läuft genau einmal: nach dem Schreibversuch, auch wenn es bis
                             zum Kampfende wartete; wird der wartende Wunsch vorher ersetzt (ein weiterer Set) oder
                             gestrichen (Cancel), mit false, "replaced" bzw. false, "cancelled"
        Gründe "combat" (gemerkt, läuft nach dem Kampf; der letzte Set gewinnt, Assign/Unassign schreiben den
               wartenden Wunsch fort), "missing", "invalid" (Liste
               oder ein Eintrag ist kaputt – es wird nichts geschrieben), "unreadable" (alte Belegung nicht ganz
               lesbar), "error" (Blizzards Funktion meldete einen Fehler: Fehlerliste und Meldung im Chat)
      Core.ClickBindings.Pending() → true, solange eine Belegung auf das Kampfende wartet; .Flush(), .Cancel() (onDone
                                       des gestrichenen Wunsches: false, "cancelled")
      Core.ClickBindings.OnChange(fn(ok, grund, einzelheiten)) → nach jedem Schreibversuch
      Core.ClickBindings.Open(opts) / .Toggle(quiet) / .Shown() → Blizzards Fenster über Core.OpenPanel("clickbindings")
      Core.ClickBindings.Reload(quiet) → true | false, "closed" | "unsaved" | "combat" | grund: Blizzards offenes
                                       Fenster neu laden (schließen und öffnen). Es liest die Belegung nur beim Öffnen
                                       und schriebe beim Speichern seinen alten Stand zurück (Forever-Quelle
                                       Blizzard_ClickBindingUI: Refresh in OnShow, SaveButton → SetProfileByInfo).
                                       Läuft nach jedem erfolgreichen Schreiben selbst (Set, Assign, Load, Restore,
                                       Flush nach dem Kampf; T4-NG2) – Module rufen es nicht selbst. Hat der Spieler
                                       dort ungespeicherte Änderungen (pendingChanges), bleibt das Fenster offen, und
                                       ein Hinweis im Chat sagt, dass Speichern dort die neue Belegung überschriebe
                                       (nach dem Schreiben immer, auch bei opts.quiet; nur Reload(true) schweigt).
                                       War die Makroverwaltung offen (ezMacro „Ränge aktualisieren“), ist sie
                                       danach wieder offen statt des Zauberbuchs, das Blizzard beim Öffnen zeigt

    Zusammenbauen (ändern nur die übergebene Liste, nie das Spiel):
      .Button(1–31 | "left" | "right" | "middle" | "button4" … "button31" | Blizzards Name) → "LeftButton" … | nil
      .Modifiers("SHIFT", "CTRL" …) | ("SHIFT-CTRL") | ({ "SHIFT", "ALT" }) | (zahl) → Maske | nil, "missing" | nil, "invalid"
      .ModifierBits() → { SHIFT = Zahl … } aus Blizzards GetStringFromModifiers erfragt (nil: nicht erfragbar)
      .FullMask(maske) → Maske, in der jede Umschalttaste ganz steht (linkes und rechtes Bit; T4-NG4)
      .Dead(eintrag) → true, wenn seine Maske nur eine Hälfte einer Umschalttaste hat (greift beim Klick nie; so
                                       schrieb ezCore vor dem 15.11.2026 „Umschalt“ als 1)
      .ModifierText(maske) → Blizzards Text ("ALT-SHIFT") | "" | nil     (Zahl: wie bisher)
      .ModifierText("SHIFT-CTRL" | { … } | nil) → „Umschalt+Strg“, ohne Umschalttaste „keine“ (für Auswahlfelder)

    Tastentexte (EC-109; vorher doppelt in ezMacro/ClickCast.lua und ezHeal/Templates.lua), Texte in ezCores Locale:
      .KEYS = { buttons = { "left", "right", "middle", "button4", "button5" }, modifiers = { "SHIFT", "CTRL", "ALT" },
                combos = { "", "SHIFT", "CTRL", "ALT", "SHIFT-CTRL", "SHIFT-ALT", "CTRL-ALT", "SHIFT-CTRL-ALT" } }
      .ButtonKey(knopf) → "left" | "right" | "middle" | "button4" … | nil     (aus jeder Schreibweise von .Button)
      .ModifierNames(umschalttasten) → { "SHIFT", "CTRL" } in fester Reihenfolge | nil (Text, Liste oder Maske)
      .ButtonText(knopf) → „Linksklick“, „Maustaste 4“
      .KeyText(knopf, umschalttasten) → „Umschalt + Strg + Linksklick“
      .Describe(eintrag, zaubername) → was auf einer Taste liegt: Zaubername (zaubername oder Core.SpellName, sonst
                                       „#id“), „Makro „Name““, Blizzards „Ziel“/„Menü“, sonst „belegt“; ohne Eintrag „frei“

    Blizzards Selbstwirken (nur gelesen; warum es beim Klick-Zaubern zählt: Kommentar bei .SelfCastKey):
      .SelfCastKey() → "ALT" | "CTRL" | "SHIFT" | nil (keine Taste)   Blizzards Selbstwirk-Taste (ModifiedClick SELFCAST)
      .HitsSelfCast(umschalttasten, selbstwirktaste) → selbstwirktaste | nil   liegt die Taste darauf (Umschalt+Alt trifft Alt)?
      .AutoSelfCast() → true | false | nil                               „Selbstwirken: Automatisch“ (CVar autoSelfCast)
      .Spell(spellID, knopf, umschalttasten) → eintrag | nil, "invalid" | "secret" | "missing" | "unbindable"
      .Macro(name | nummer, knopf, umschalttasten) → eintrag | nil, "invalid" | "secret" | "missing" | "unknown"
      .Interaction("target" | "menu", knopf, umschalttasten) → eintrag | nil, grund
      .Find(liste, knopf, umschalttasten) → eintrag, stelle     .Put(liste, eintrag) → ersetzter Eintrag | nil
      .Remove(liste, knopf, umschalttasten) → entfernter Eintrag | nil
                                       Find trifft zuerst die genaue Maske, sonst einen toten Eintrag derselben Taste
                                       (.Dead, z. B. Maske 1 statt 3); Put und Remove nehmen tote Doppel derselben
                                       Taste mit weg – so verschwinden alte Belegungen beim nächsten Schreiben (T4-NG4)
      .Replace(liste, kind, alteID, neueID) → Anzahl (für „Ränge aktualisieren“)
      .KeepDefaults(liste, aktuell) → neue Liste, verdrängte Einträge
      .Interactions(liste) → { { action, button, state = "ok" | "moved" | "missing", entry, on } } | nil: wo Blizzards
                                       „Ziel“ und „Menü“ liegen (Spieltest 24.11.2026); entry = der Eintrag, on = was
                                       sonst auf der Taste des Standards liegt
      .RestoreInteractions(liste) → neue Liste, Anzahl: beides wieder auf Blizzards Standardtaste (Links, Rechts)
      .Assign(eintrag, opts) / .Unassign(knopf, umschalttasten, opts) → lesen, ändern, Set (ein Aufruf fürs Modul).
                                       Wartet schon ein Wunsch (im Kampf), bauen sie auf dessen Liste auf statt auf
                                       Blizzards Belegung: zwei Assign im Kampf schreiben beide, Load + Assign das
                                       Profil samt Zuweisung; die opts des wartenden gelten weiter (die neuen gehen
                                       vor), sein onDone erfährt das gemeinsame Ergebnis

    Sichern und Profile (in ezCoreDB.clickBindings; Makros werden über ihren Namen wiedergefunden):
      .Backup(welche) → { time, list, owner } | nil   "last" (Standard: vor dem letzten Schreiben) oder "first" (vor dem
                                                 allerersten Schreiben dieses Charakters – wird nie überschrieben).
                                                 owner = opts.owner des Schreibens, das die Sicherung auslöste (EC-115):
                                                 daran erkennt ein Modul, ob „last“ von ihm stammt. Alte Sicherungen
                                                 und Schreiben ohne owner: nil = unbekannt
      .Restore(welche, opts) → wie Set (schreibt die Sicherung zurück; die jetzige Belegung wird dabei „last“)
      .Save(name, liste) → name | nil, grund     aktuelle (oder übergebene) Belegung unter einem Namen merken
      .Load(name, opts) → wie Set                .Delete(name) → true | false     .Has(name)
      .Profile(name) → { name, class, time, list } (Kopie) | nil     .Names() → sortiert     .Profiles() → Liste davon
      .Export(name) → Text | nil, grund          ohne name: die aktuelle Belegung
      .Import(text, name) → name | nil, grund    wird ein neues Profil, angewendet wird nichts; streng geprüft
                                                 (.Clean mit streng), Klasse nur als bekanntes Klassen-Token, höchstens
                                                 CB.MAX_PROFILES Profile (sonst nil, "full")
      .Clean(liste, streng) → saubere Kopie | nil  nur bekannte Felder mit passendem Typ. streng (fremder Text,
                                                 T4-NG3): dazu nur Blizzards Tastennamen (.Button), nur Umschalt-Bits,
                                                 die Blizzard kennt, Art „other“ nur mit einer Zahl aus
                                                 Enum.ClickBindingType, Makronamen höchstens
                                                 Core.Macro.MAX_NAME Zeichen, höchstens CB.MAX_ENTRIES Einträge
      .Count() → Profile, wartend (0 | 1)        .StatusLine() → Zeile für /ez status oder nil
]]

local ADDON = "ezCore"
local CB = {}
Core.ClickBindings = CB

CB.QUEUE_KEY = "ClickBindings"
CB.PANEL = "clickbindings"
CB.EXPORT_KIND, CB.EXPORT_VERSION = "ezCore.clickbindings", 1
CB.MAX_NAME = 40
-- eigene Art → Schlüssel in Enum.ClickBindingType bzw. Enum.ClickBindingInteraction
CB.KINDS = { spell = "Spell", macro = "Macro", interaction = "Interaction", pet = "PetAction" }
CB.INTERACTIONS = { target = "Target", menu = "OpenContextMenu" }
-- Blizzards Standard: Linksklick nimmt ins Ziel, Rechtsklick öffnet das Menü (beides ohne Umschalttaste).
-- Quelle: Blizzards Standardbelegung im Klick-Zauber-Fenster; am Forever-Client zu bestätigen (ezHeal „Im Spiel
-- prüfen“ Punkt 1, ezCore Punkt 39 a).
CB.DEFAULTS = { { action = "target", button = "LeftButton" }, { action = "menu", button = "RightButton" } }
CB.MAX_BUTTON = 31
-- Grenzen für fremden Text (CB.Import, T4-NG3): je Maustaste 16 Kombinationen; Profile kontoweit
CB.MAX_ENTRIES = CB.MAX_BUTTON * 16
CB.MAX_PROFILES = 200
CB.BUTTONS = {
    [1] = "LeftButton", [2] = "RightButton", [3] = "MiddleButton", [4] = "Button4", [5] = "Button5",
    left = "LeftButton", right = "RightButton", middle = "MiddleButton",
    leftbutton = "LeftButton", rightbutton = "RightButton", middlebutton = "MiddleButton",
    button1 = "LeftButton", button2 = "RightButton", button3 = "MiddleButton", button4 = "Button4", button5 = "Button5",
}
CB.MODIFIER_ALIASES = { STRG = "CTRL", CONTROL = "CTRL", UMSCHALT = "SHIFT", CMD = "META" }

local pending            -- { list, opts } – wartet auf das Kampfende
local listeners = {}
local modifierBits       -- Ergebnis von ModifierBits (false: nicht erfragbar)
local modifierUnion      -- { SHIFT = 3 … } Summe aller Bits je Umschalttaste (aus ModifierBits)
local modifierKnown      -- Summe aller Bits, für die Blizzard einen Namen nennt (aus ModifierBits)
local scratch = { profiles = {}, backups = {} }

local function Api(name)
    local api = rawget(_G, "C_ClickBindings")
    local fn = type(api) == "table" and api[name] or nil
    return type(fn) == "function" and fn or nil
end

local function EnumOf(name)
    local enum = rawget(_G, "Enum")
    local values = type(enum) == "table" and enum[name] or nil
    return type(values) == "table" and values or nil
end

local function Whole(value)
    return type(value) == "number" and not Core.IsSecret(value) and value == math.floor(value) and value >= 0
end

local function Text(value)
    return type(value) == "string" and not Core.IsSecret(value) and value ~= ""
end

local function DB()
    local db = Core.db
    if type(db) ~= "table" then return scratch end   -- vor dem Laden: nichts kaputt machen
    if type(db.clickBindings) ~= "table" then db.clickBindings = {} end
    local store = db.clickBindings
    if type(store.profiles) ~= "table" then store.profiles = {} end
    if type(store.backups) ~= "table" then store.backups = {} end
    return store
end

---------------------------------------------------------------------------
-- Arten und Einträge
---------------------------------------------------------------------------

local function TypeOf(kind)
    local types, key = EnumOf("ClickBindingType"), CB.KINDS[kind]
    local value = types and key and types[key] or nil
    return type(value) == "number" and value or nil
end

local function KindOf(typeNumber)
    local types = EnumOf("ClickBindingType")
    if types then
        for kind, key in pairs(CB.KINDS) do
            if types[key] == typeNumber then return kind end
        end
    end
    return "other"
end

local function InteractionID(action)
    local values, key = EnumOf("ClickBindingInteraction"), CB.INTERACTIONS[action]
    local value = values and key and values[key] or nil
    return type(value) == "number" and value or nil
end

local function ActionOf(id)
    local values = EnumOf("ClickBindingInteraction")
    if values then
        for action, key in pairs(CB.INTERACTIONS) do
            if values[key] == id then return action end
        end
    end
    return nil
end

local function MacroName(index)
    local ok, name = Core.PCall(rawget(_G, "GetMacroInfo"), index)
    if ok and Text(name) then return name end
    return nil
end

local function MacroIndex(name)
    local ok, index = Core.PCall(rawget(_G, "GetMacroIndexByName"), name)
    if ok and Whole(index) and index > 0 then return index end
    return nil
end

local function SlotKey(button, modifiers)
    return tostring(button) .. ":" .. tostring(modifiers or 0)
end

local HasBit = Core.HasBit

local MODIFIER_LIMIT = 2 ^ 16   -- CB.ModifierBits fragt die Bits 0 bis 15

-- Nur Umschalt-Bits, die Blizzard kennt (strenge Prüfung fremder Texte); ohne Blizzards Antwort nur bis Bit 15
local function KnownMask(mask)
    if mask >= MODIFIER_LIMIT then return false end
    if not CB.ModifierBits() or not modifierKnown then return true end
    for bit = 0, 15 do
        local value = 2 ^ bit
        if HasBit(mask, value) and not HasBit(modifierKnown, value) then return false end
    end
    return true
end

-- Art „other“ aus fremdem Text: nur eine Zahl, die Blizzards Enum.ClickBindingType kennt (nicht „None“) – so bleibt
-- eine eigene Belegung mit einer Art, die ezCore nicht benennt, teilbar, eine erfundene Zahl nicht
local function KnownOtherType(value)
    if not Whole(value) then return false end
    local types = EnumOf("ClickBindingType")
    if not types then return false end
    for key, number in pairs(types) do
        if number == value and key ~= "None" then return true end
    end
    return false
end

-- Makroname in Blizzards Grenze (Core.Macro.MAX_NAME, gemessen wie Core.Macro.Write)
local function MacroNameFits(name)
    local macro = Core.Macro
    local limit = type(macro) == "table" and tonumber(macro.MAX_NAME) or 16
    local length = type(macro) == "table" and type(macro.NameLength) == "function" and macro.NameLength(name)
        or (strlenutf8 and strlenutf8(name)) or #name
    return length <= limit
end

-- Eintrag prüfen und kopieren: nur bekannte Felder mit passendem Typ. → Kopie | nil
-- strict (fremder Text, T4-NG3): dazu Blizzards Tastenname, bekannte Umschalt-Bits, „other“ nur mit Blizzards Zahl,
-- Makroname in Blizzards Grenze
local function CleanEntry(entry, strict)
    if type(entry) ~= "table" or Core.IsSecret(entry) then return nil end
    local kind, button, modifiers, id = entry.kind, entry.button, entry.modifiers, entry.id
    if modifiers == nil then modifiers = 0 end
    if not (Text(kind) and Text(button) and Whole(modifiers)) then return nil end
    if kind ~= "other" and not CB.KINDS[kind] then return nil end
    if strict then
        if CB.Button(button) ~= button or not KnownMask(modifiers) then return nil end
        if kind == "other" and not KnownOtherType(entry.type) then return nil end
        if kind == "macro" and Text(entry.name) and not MacroNameFits(entry.name) then return nil end
    end
    local out = { kind = kind, button = button, modifiers = modifiers }
    if Whole(entry.type) then out.type = entry.type end
    if kind == "other" and out.type == nil then return nil end
    if kind == "macro" and Text(entry.name) then out.name = entry.name end
    if kind == "interaction" and CB.INTERACTIONS[entry.action] then out.action = entry.action end
    if Whole(id) then
        out.id = id
    elseif not (out.name or out.action) then
        return nil
    end
    return out
end

-- Liste prüfen und kopieren. Ein kaputter Eintrag macht die ganze Liste ungültig (nichts halb schreiben).
-- Liegen zwei Einträge auf derselben Taste, gilt der spätere. strict: siehe CleanEntry, dazu höchstens CB.MAX_ENTRIES.
function CB.Clean(list, strict)
    if type(list) ~= "table" or Core.IsSecret(list) then return nil end
    if strict and #list > CB.MAX_ENTRIES then return nil end
    local out, at = {}, {}
    for _, entry in ipairs(list) do
        local clean = CleanEntry(entry, strict)
        if not clean then return nil end
        local key = SlotKey(clean.button, clean.modifiers)
        if at[key] then
            out[at[key]] = clean
        else
            out[#out + 1] = clean
            at[key] = #out
        end
    end
    return out
end

-- Blizzards Eintrag → eigener Eintrag (nil: nicht lesbar)
local function FromRaw(raw)
    if type(raw) ~= "table" or Core.IsSecret(raw) then return nil end
    local kindType, button, modifiers, id = raw.type, raw.button, raw.modifiers, raw.actionID
    if modifiers == nil then modifiers = 0 end
    if not (Whole(kindType) and Text(button) and Whole(modifiers)) then return nil end
    -- ohne actionID ließe sich der Eintrag weder sichern (CleanEntry verwirft ihn) noch zurückschreiben (ToRaw):
    -- als unlesbar zählen, damit Set ihn nicht stillschweigend verliert
    if not Whole(id) then return nil end
    local entry = { kind = KindOf(kindType), type = kindType, id = id, button = button, modifiers = modifiers }
    if entry.kind == "macro" and id then entry.name = MacroName(id) end
    if entry.kind == "interaction" and id then entry.action = ActionOf(id) end
    return entry
end

-- Eigener Eintrag → Blizzards Eintrag (nil, grund: lässt sich auf diesem Charakter nicht belegen)
local function ToRaw(entry)
    local kindType = TypeOf(entry.kind) or entry.type
    if kindType == nil then return nil, "type" end
    local id = entry.id
    if entry.kind == "macro" and entry.name then
        -- Makros wandern (Nummern verschieben sich, andere Charaktere haben andere): über den Namen wiederfinden
        if not (id and MacroName(id) == entry.name) then id = MacroIndex(entry.name) end
        if not id then return nil, "macro" end
    elseif entry.kind == "interaction" and entry.action then
        id = InteractionID(entry.action) or id
    end
    if id == nil then return nil, "id" end
    return { type = kindType, actionID = id, button = entry.button, modifiers = entry.modifiers }
end

---------------------------------------------------------------------------
-- Lesen
---------------------------------------------------------------------------

function CB.Available()
    return Api("GetProfileInfo") ~= nil and EnumOf("ClickBindingType") ~= nil
end

function CB.Writable()
    return CB.Available() and Api("SetProfileByInfo") ~= nil
end

function CB.List()
    if not CB.Available() then return nil, "missing" end
    local ok, info = pcall(Api("GetProfileInfo"))
    if not ok then
        Core.Error(ADDON, info, "ClickBindings List")
        return nil, "error"
    end
    if type(info) ~= "table" or Core.IsSecret(info) then return nil, "error" end
    local list, complete = {}, true
    for _, raw in ipairs(info) do
        local entry = FromRaw(raw)
        if entry then list[#list + 1] = entry else complete = false end
    end
    return list, complete
end

function CB.IDs(kind, list)
    local out = {}
    if list == nil then list = CB.List() end
    for _, entry in ipairs(type(list) == "table" and list or {}) do
        if type(entry) == "table" and entry.kind == kind and entry.id ~= nil then out[entry.id] = true end
    end
    return out
end

---------------------------------------------------------------------------
-- Zusammenbauen
---------------------------------------------------------------------------

-- Weitere Maustasten (Button6 … Button31) nennt Blizzard wie Button4/Button5; sie werden nur durchgereicht, damit
-- Find/Remove auch Einträge auf solchen Tasten treffen, die Blizzards Fenster angelegt hat.
local function ExtraButton(number)
    if number >= 6 and number <= CB.MAX_BUTTON and number == math.floor(number) then return "Button" .. number end
    return nil
end

function CB.Button(value)
    if Core.IsSecret(value) then return nil end
    if type(value) == "number" then return CB.BUTTONS[value] or ExtraButton(value) end
    if type(value) ~= "string" or value == "" then return nil end
    local lower = value:lower()
    local known = CB.BUTTONS[lower]
    if known then return known end
    local number = tonumber(lower:match("^button(%d+)$"))
    return number and ExtraButton(number) or nil
end

-- Welche Zahl steht für welche Umschalttaste? Blizzard nennt die Werte nicht als Konstanten; gefragt wird
-- deshalb seine eigene Funktion GetStringFromModifiers mit je einem gesetzten Bit. Für einzelne Namen (LSHIFT …) gilt
-- der kleinste Wert je Name, für die Tasten an sich (SHIFT, CTRL, ALT, META) die Summe aller ihrer Bits (siehe unten).
local GENERIC_MODIFIER = {
    LSHIFT = "SHIFT", RSHIFT = "SHIFT", LCTRL = "CTRL", RCTRL = "CTRL", LALT = "ALT", RALT = "ALT",
    LMETA = "META", RMETA = "META",
}

function CB.ModifierBits()
    if modifierBits ~= nil then return modifierBits or nil end
    local get = Api("GetStringFromModifiers")
    if not get then return nil end
    local bits, union, found, known = {}, {}, false, 0
    for bit = 0, 15 do
        local value = 2 ^ bit
        local ok, text = pcall(get, value)
        if ok and Text(text) then
            local name = text:upper():gsub("[^%u]", "")
            if name ~= "" then
                if bits[name] == nil then bits[name] = value end
                known = known + value
                -- Blizzard führt linke und rechte Taste als eigene Bits; die Taste „an sich“ ist beides zusammen
                local generic = GENERIC_MODIFIER[name] or name
                union[generic] = (union[generic] or 0) + value
                found = true
            end
        end
    end
    -- „SHIFT“ ist die Summe ALLER Bits dieser Taste (links und rechts): Beim Klick bildet das Spiel die Maske aus
    -- beiden (MakeModifiers), eine Belegung nur mit dem linken Bit steht richtig in der Liste, greift aber nie.
    -- Beleg im Spiel (15.11.2026, Build 70938): von Hand gesetztes Umschalt+Links hat modifiers = 3, die bisher von
    -- ezCore geschriebene Belegung hatte 1 und wirkte nicht.
    for _, name in ipairs({ "SHIFT", "CTRL", "ALT", "META" }) do
        if union[name] ~= nil then bits[name] = union[name] end
    end
    modifierBits = found and bits or false
    modifierUnion = found and union or nil
    modifierKnown = found and known or nil
    return modifierBits or nil
end

function CB.ResetModifierBits() modifierBits, modifierUnion, modifierKnown = nil, nil, nil end

-- Maske mit ganzen Umschalttasten: Steht ein Bit einer Taste darin (etwa nur das linke Umschalt-Bit 1), kommen
-- deren übrige Bits dazu (3). Ohne Blizzards Antwort oder ohne getrennte Bits: die Maske selbst.
function CB.FullMask(mask)
    if not Whole(mask) or mask >= MODIFIER_LIMIT then return mask end
    if not CB.ModifierBits() or not modifierUnion then return mask end
    local out = mask
    for _, sum in pairs(modifierUnion) do
        local part = false
        for bit = 0, 15 do
            local value = 2 ^ bit
            if HasBit(sum, value) and HasBit(mask, value) then part = true break end
        end
        if part then
            for bit = 0, 15 do
                local value = 2 ^ bit
                if HasBit(sum, value) and not HasBit(out, value) then out = out + value end
            end
        end
    end
    return out
end

-- Toter Eintrag: Seine Maske hat nur eine Hälfte einer Umschalttaste und greift beim Klick nie (siehe oben; so stehen
-- Belegungen, die ezCore vor dem 15.11.2026 schrieb).
function CB.Dead(entry)
    if type(entry) ~= "table" or Core.IsSecret(entry) then return false end
    local mask = entry.modifiers or 0
    if not Whole(mask) then return false end
    return CB.FullMask(mask) ~= mask
end

local function AddModifierNames(names, value)
    if type(value) == "table" then
        for _, part in ipairs(value) do
            if not AddModifierNames(names, part) then return false end
        end
        return true
    end
    if value == nil then return true end
    if type(value) ~= "string" or Core.IsSecret(value) then return false end
    for part in value:upper():gmatch("[^%s%-%+,]+") do
        if part ~= "NONE" then names[#names + 1] = CB.MODIFIER_ALIASES[part] or part end
    end
    return true
end

function CB.Modifiers(...)
    local first = ...
    if select("#", ...) <= 1 and type(first) == "number" then
        if Whole(first) then return first end
        return nil, "invalid"
    end
    local names = {}
    for i = 1, select("#", ...) do
        if not AddModifierNames(names, (select(i, ...))) then return nil, "invalid" end
    end
    if #names == 0 then return 0 end
    local bits = CB.ModifierBits()
    if not bits then return nil, "missing" end
    local mask, seen = 0, {}
    for _, name in ipairs(names) do
        local value = bits[name]
        if not value then return nil, "invalid" end
        if not seen[value] then
            seen[value] = true
            mask = mask + value
        end
    end
    return mask
end

local function BlizzardModifierText(mask)
    if not Whole(mask) then return nil end
    if mask == 0 then return "" end
    local ok, text = Core.PCall(Api("GetStringFromModifiers"), mask)
    if ok and type(text) == "string" and not Core.IsSecret(text) then return text end
    return nil
end

---------------------------------------------------------------------------
-- Tastentexte (EC-109): EINE Stelle für „Umschalt + Strg + Linksklick“
---------------------------------------------------------------------------

CB.KEYS = {
    buttons = { "left", "right", "middle", "button4", "button5" },
    modifiers = { "SHIFT", "CTRL", "ALT" },
    combos = { "", "SHIFT", "CTRL", "ALT", "SHIFT-CTRL", "SHIFT-ALT", "CTRL-ALT", "SHIFT-CTRL-ALT" },
}
local BUTTON_KEYS = { LeftButton = "left", RightButton = "right", MiddleButton = "middle" }
local modifierRank = {}
for index, name in ipairs(CB.KEYS.modifiers) do modifierRank[name] = index end

-- Text aus ezCores Locale oder nil (die Texttabelle liefert für einen fehlenden Schlüssel den Schlüssel selbst)
local function Label(key)
    local value = Core.L[key]
    if type(value) == "string" and value ~= key then return value end
    return nil
end

function CB.ButtonKey(button)
    local name = CB.Button(button)
    if not name then return nil end
    return BUTTON_KEYS[name] or name:lower()
end

-- Umschalttasten als Namen in fester Reihenfolge (Umschalt, Strg, Alt, dann Unbekanntes nach Alphabet), ohne
-- Doppelte. Eine Zahl ist Blizzards Maske (GetStringFromModifiers). nil: nicht lesbar.
function CB.ModifierNames(modifiers)
    if Core.IsSecret(modifiers) then return nil end
    if type(modifiers) == "number" then
        modifiers = BlizzardModifierText(modifiers)
        if modifiers == nil then return nil end
    end
    local raw = {}
    if not AddModifierNames(raw, modifiers) then return nil end
    local names, seen = {}, {}
    for _, name in ipairs(raw) do
        name = name:gsub("^[LR](%u+)$", function(base) return modifierRank[base] and base or nil end)
        if not seen[name] then
            seen[name] = true
            names[#names + 1] = name
        end
    end
    table.sort(names, function(a, b)
        local ra, rb = modifierRank[a] or 99, modifierRank[b] or 99
        if ra ~= rb then return ra < rb end
        return a < b
    end)
    return names
end

local function ModifierLabels(modifiers)
    local names = CB.ModifierNames(modifiers)
    if not names then return nil end
    local parts = {}
    for _, name in ipairs(names) do parts[#parts + 1] = Label("CLICK_MOD_" .. name) or name end
    return parts
end

function CB.ButtonText(button)
    local key = CB.ButtonKey(button)
    if not key then return tostring(Core.Plain(button) or "?") end
    local text = Label("CLICK_BUTTON_" .. key)
    if text then return text end
    local number = tonumber(key:match("^button(%d+)$"))
    if number then return Core.L.CLICK_BUTTON_N:format(number) end
    return key
end

-- „Umschalt + Strg + Linksklick“
function CB.KeyText(button, modifiers)
    local parts = ModifierLabels(modifiers) or {}
    parts[#parts + 1] = CB.ButtonText(button)
    return table.concat(parts, " + ")
end

-- Zahl: Blizzards Text der Maske (wie bisher). Sonst der kurze Text für Auswahlfelder: „Umschalt+Strg“, ohne
-- Umschalttaste „keine“.
function CB.ModifierText(modifiers)
    if Core.IsSecret(modifiers) then return nil end
    if type(modifiers) == "number" then return BlizzardModifierText(modifiers) end
    local parts = ModifierLabels(modifiers)
    if not parts then return nil end
    if #parts == 0 then return Core.L.CLICK_MOD_NONE end
    return table.concat(parts, "+")
end

---------------------------------------------------------------------------
-- Blizzards Selbstwirken (Fehler des Nutzers vom 23.11.2026: Klick auf einen Mitspieler wirkte auf ihn selbst)
---------------------------------------------------------------------------

-- Blizzards Option „Selbstwirken“ (Einstellungen » Gameplay » Kampf) steht ab Werk auf „Automatisch und Tastendruck“
-- mit der Taste Alt (Forever-Quelle, Gethe/wow-ui-source Zweig forever: Blizzard_SettingsDefinitions_Frame/Combat.lua,
-- Vorgabe 4; Blizzard_FrameXML/Bindings_Camelot.xml, ModifiedClick SELFCAST = ALT). Beides gilt auch beim Klick-Zaubern
-- auf Blizzards Rahmen (SecureUnitButton_OnClick ruft C_ClickBindings.ExecuteBinding mit der Einheit des Rahmens; wohin
-- der Zauber geht, entscheidet danach das Spiel):
--   - mit gedrückter Selbstwirk-Taste wirkt der Zauber auf dich statt auf den geklickten Rahmen;
--   - mit „Automatisch“ fällt ein Zauber auf einen Mitspieler außer Reichweite auf dein Ziel bzw. auf dich zurück
--     (Fehler des Spiels seit der Engine von Wrath 3.4.1, Stanzilla/WoWUIBugs #382, von Blizzard nicht behoben).
-- Nur gelesen – ezCore ändert die Option nie; umstellen kann sie der Spieler in Blizzards Fenster (Core.OpenPanel("combat",
-- "SELF_CAST")).

-- Selbstwirk-Taste → "ALT" | "CTRL" | "SHIFT" (mehrere in fester Reihenfolge, mit "-" verbunden) | nil (keine Taste
-- („NONE“) oder nicht lesbar)
function CB.SelfCastKey()
    local ok, value = Core.PCall(rawget(_G, "GetModifiedClick"), "SELFCAST")
    if not ok or not Text(value) then return nil end
    local names = CB.ModifierNames(value)
    if not names or #names == 0 then return nil end
    return table.concat(names, "-")
end

-- Liegt eine Taste auf der Selbstwirk-Taste? modifiers: Text, Liste oder Blizzards Maske (wie .ModifierNames);
-- selfKey: Selbstwirk-Taste (ohne Angabe .SelfCastKey()). → selfKey, wenn jede ihrer Umschalttasten in modifiers
-- steckt, sonst nil. Vorsichtig gezählt: Umschalt+Alt trifft Alt (ob das Spiel bei einer weiteren gedrückten
-- Umschalttaste auch auf dich wirkt, ist am Forever-Client zu bestätigen – lieber gewarnt als auf dich gewirkt).
function CB.HitsSelfCast(modifiers, selfKey)
    if selfKey == nil then selfKey = CB.SelfCastKey() end
    if type(selfKey) ~= "string" then return nil end
    local have, need = CB.ModifierNames(modifiers or ""), CB.ModifierNames(selfKey)
    if not (have and need and #need > 0) then return nil end
    local set = {}
    for _, name in ipairs(have) do set[name] = true end
    for _, name in ipairs(need) do
        if not set[name] then return nil end
    end
    return selfKey
end

-- „Automatisch“ an (CVar autoSelfCast)? → true | false | nil (nicht lesbar)
function CB.AutoSelfCast()
    local ok, value = Core.PCall(Core.CVar, "autoSelfCast")
    if not ok or Core.IsSecret(value) or value == nil then return nil end
    value = tostring(value)
    return value ~= "0" and value ~= ""
end

-- Was liegt auf einer Taste? spellName: Name des Zaubers, wenn das Modul ihn besser kennt (Rang, Ersatzname).
function CB.Describe(entry, spellName)
    local L = Core.L
    if Core.IsSecret(entry) or type(entry) ~= "table" then return L.CLICK_FREE end
    if entry.kind == "spell" and entry.id ~= nil then
        if type(spellName) == "string" and not Core.IsSecret(spellName) and spellName ~= "" then return spellName end
        return Core.SpellName(entry.id) or ("#" .. tostring(Core.Plain(entry.id) or "?"))
    end
    if entry.kind == "macro" then return L.CLICK_IS_MACRO:format(tostring(Core.Plain(entry.name) or Core.Plain(entry.id) or "?")) end
    if entry.kind == "interaction" and type(entry.action) == "string" then
        return Label("CLICK_ACTION_" .. entry.action) or L.CLICK_OTHER
    end
    return L.CLICK_OTHER
end

local function Slot(button, modifiers)
    local name = CB.Button(button)
    if not name then return nil, nil, "invalid" end
    local mask, reason = CB.Modifiers(modifiers)
    if not mask then return nil, nil, reason end
    return name, mask
end

function CB.Spell(spellID, button, modifiers)
    if Core.IsSecret(spellID) then return nil, "secret" end
    if not Whole(spellID) or spellID == 0 then return nil, "invalid" end
    local name, mask, reason = Slot(button, modifiers)
    if not name then return nil, reason end
    local can = Api("CanSpellBeClickBound")
    if can then
        local ok, allowed = pcall(can, spellID)
        if ok and not Core.IsSecret(allowed) and allowed == false then return nil, "unbindable" end
    end
    return { kind = "spell", type = TypeOf("spell"), id = spellID, button = name, modifiers = mask }
end

function CB.Macro(macro, button, modifiers)
    if Core.IsSecret(macro) then return nil, "secret" end
    local index, macroName
    if type(macro) == "number" then
        if not Whole(macro) or macro == 0 then return nil, "invalid" end
        index, macroName = macro, MacroName(macro)
    elseif Text(macro) then
        index, macroName = MacroIndex(macro), macro
    else
        return nil, "invalid"
    end
    if not (index and macroName) then return nil, "unknown" end
    local name, mask, reason = Slot(button, modifiers)
    if not name then return nil, reason end
    return { kind = "macro", type = TypeOf("macro"), id = index, name = macroName, button = name, modifiers = mask }
end

function CB.Interaction(action, button, modifiers)
    if type(action) ~= "string" or not CB.INTERACTIONS[action] then return nil, "invalid" end
    local name, mask, reason = Slot(button, modifiers)
    if not name then return nil, reason end
    return { kind = "interaction", type = TypeOf("interaction"), id = InteractionID(action), action = action,
        button = name, modifiers = mask }
end

-- Zuerst die genaue Maske; sonst ein toter Eintrag derselben Taste (CB.Dead: nur eine Hälfte einer Umschalttaste,
-- z. B. 1 statt 3) – den ersetzt ein Put dann, statt eine zweite Belegung daneben zu legen (T4-NG4).
function CB.Find(list, button, modifiers)
    local name, mask = Slot(button, modifiers)
    if not name or type(list) ~= "table" then return nil end
    local full, near, nearIndex = CB.FullMask(mask), nil, nil
    for index, entry in ipairs(list) do
        if type(entry) == "table" and entry.button == name then
            local entryMask = entry.modifiers or 0
            if entryMask == mask then return entry, index end
            if not near and CB.Dead(entry) and CB.FullMask(entryMask) == full then near, nearIndex = entry, index end
        end
    end
    return near, nearIndex
end

-- Tote Doppel derselben Taste entfernen (keep selbst bleibt). → erster entfernter Eintrag | nil
local function DropDead(list, button, mask, keep)
    local full, first = CB.FullMask(mask), nil
    for index = #list, 1, -1 do
        local entry = list[index]
        if entry ~= keep and type(entry) == "table" and entry.button == button and CB.Dead(entry)
            and CB.FullMask(entry.modifiers or 0) == full then
            first = table.remove(list, index)
        end
    end
    return first
end

function CB.Put(list, entry)
    local clean = CleanEntry(entry)
    if type(list) ~= "table" or not clean then return nil, "invalid" end
    local old, index = CB.Find(list, clean.button, clean.modifiers)
    list[index or (#list + 1)] = clean
    DropDead(list, clean.button, clean.modifiers, clean)
    return old
end

function CB.Remove(list, button, modifiers)
    local old, index = CB.Find(list, button, modifiers)
    if index then
        table.remove(list, index)
        DropDead(list, old.button, old.modifiers or 0)
    end
    return old
end

function CB.Replace(list, kind, oldID, newID)
    local count = 0
    if type(list) ~= "table" or oldID == nil or not Whole(newID) then return count end
    for _, entry in ipairs(list) do
        if type(entry) == "table" and entry.kind == kind and entry.id == oldID then
            entry.id = newID
            if kind == "macro" then entry.name = MacroName(newID) end
            count = count + 1
        end
    end
    return count
end

-- Blizzards Einträge „Ziel“ und „Menü“ erhalten: Jede Interaktion der aktuellen Belegung, die in der neuen Liste
-- nicht vorkommt, bleibt auf ihrer Taste; fehlt sie auch dort, kommt Blizzards Standard dazu (Links = Ziel,
-- Rechts = Menü). Liegt in der neuen Liste etwas anderes auf dieser Taste, weicht es (zweite Rückgabe).
-- Enthält die neue Liste die Interaktion selbst (auf welcher Taste auch immer), gilt die Liste.
function CB.KeepDefaults(list, current)
    local out, dropped = {}, {}
    local have, keep = {}, {}
    local function Mark(entry)
        if entry.kind ~= "interaction" then return nil end
        return entry.action or entry.id
    end
    for _, entry in ipairs(list or {}) do
        local mark = Mark(entry)
        if mark ~= nil then have[mark] = true end
    end
    for _, entry in ipairs(current or {}) do
        local mark = Mark(entry)
        if mark ~= nil and not have[mark] then keep[#keep + 1] = entry end
    end
    -- Blizzards Standard nur ergänzen, wenn die Taste in der neuen Liste frei ist (EC-34, Empfehlung umgesetzt,
    -- Antwort offen): sonst verdrängte er eine eigene Belegung des Spielers auf dem blanken Klick.
    local listed = {}
    for _, entry in ipairs(list or {}) do listed[SlotKey(entry.button, entry.modifiers)] = true end
    for _, default in ipairs(CB.DEFAULTS) do
        local found = have[default.action] or listed[SlotKey(default.button, 0)]
        for _, entry in ipairs(keep) do
            -- schon da – oder ein verlegter Eintrag der alten Belegung sitzt auf der Taste des Standards
            if entry.action == default.action or SlotKey(entry.button, entry.modifiers) == SlotKey(default.button, 0) then
                found = true
            end
        end
        if not found and InteractionID(default.action) ~= nil then
            keep[#keep + 1] = { kind = "interaction", type = TypeOf("interaction"), id = InteractionID(default.action),
                action = default.action, button = default.button, modifiers = 0 }
        end
    end
    local taken = {}
    for _, entry in ipairs(keep) do taken[SlotKey(entry.button, entry.modifiers)] = true end
    for _, entry in ipairs(list or {}) do
        if taken[SlotKey(entry.button, entry.modifiers)] then
            dropped[#dropped + 1] = entry
        else
            out[#out + 1] = entry
        end
    end
    for _, entry in ipairs(keep) do
        out[#out + 1] = CleanEntry(entry) or entry
    end
    return out, dropped
end

-- Wo liegen Blizzards „Ziel“ und „Menü“? Auf Blizzards Einheiten-, Gruppen- und Raidrahmen öffnet ein Rechtsklick das
-- Menü nur, wenn das Klick-Zauber-Profil ihm „Menü“ gibt (Forever-Quelle Blizzard_FrameXML/SecureTemplates.lua,
-- SecureUnitButton_OnClick): Liegt dort ein Zauber, wird gezaubert, liegt dort nichts, geschieht nichts. Blizzards Fenster
-- nimmt der Interaktion die Taste weg, sobald ein Zauber dorthin kommt, und speichert sie dann nicht mit (Spieltest des
-- Nutzers vom 24.11.2026, wörtlich „ich kann nicht das menü beim gruppenmitglied oder mir aufrufen“).
function CB.Interactions(list)
    if type(list) ~= "table" then return nil end
    local out = {}
    for _, default in ipairs(CB.DEFAULTS) do
        if InteractionID(default.action) ~= nil then
            local info = { action = default.action, button = default.button, state = "missing" }
            for _, entry in ipairs(list) do
                if type(entry) == "table" and entry.kind == "interaction" and entry.action == default.action
                    and not CB.Dead(entry) then
                    if entry.button == default.button and (entry.modifiers or 0) == 0 then
                        info.state, info.entry = "ok", entry
                    elseif info.state == "missing" then
                        info.state, info.entry = "moved", entry
                    end
                end
            end
            if info.state ~= "ok" then info.on = CB.Find(list, default.button, 0) end
            out[#out + 1] = info
        end
    end
    return out
end

-- „Ziel“ und „Menü“ wieder auf ihre Standardtaste: Was dort liegt, weicht; von der verlegten Taste geht die Interaktion weg.
function CB.RestoreInteractions(list)
    local out, count = Core.CopyTable(list), 0
    for _, info in ipairs(CB.Interactions(list) or {}) do
        local entry = info.state ~= "ok" and CB.Interaction(info.action, info.button) or nil
        if entry then
            for index = #out, 1, -1 do
                local old = out[index]
                if type(old) == "table" and old.kind == "interaction" and old.action == info.action then
                    table.remove(out, index)
                end
            end
            CB.Put(out, entry)
            count = count + 1
        end
    end
    return out, count
end

---------------------------------------------------------------------------
-- Sichern
---------------------------------------------------------------------------

-- Schlüssel des Charakters – nil, solange er (vor PLAYER_LOGIN) oder ezCoreDB noch nicht feststeht
local function CharKey()
    local key = Core.charKey
    if not Text(key) or type(Core.db) ~= "table" then return nil end
    return key
end

local Now = Core.Now

local early   -- { first, last }: Sicherung vor dem Anmelden; zieht zum Charakter, sobald sein Schlüssel steht

-- Sicherungen des Charakters (create: anlegen, wenn es keine gibt). Vor dem Anmelden: die vorgemerkten.
local function Mine(create)
    local key = CharKey()
    if not key then
        if create and not early then early = {} end
        return early
    end
    local backups = DB().backups
    local mine = backups[key]
    if type(mine) ~= "table" then
        if not (create or early) then return nil end
        mine = {}
        backups[key] = mine
    end
    if early then
        if type(mine.first) ~= "table" then mine.first = early.first end
        mine.last = early.last
        early = nil
    end
    return mine
end

-- → true | false (die Belegung ließ sich nicht bereinigen: dann wird auch nicht geschrieben)
-- owner: wer schreibt (opts.owner von Set) – steht in der Sicherung, damit ein Modul „last“ als seine erkennt (EC-115)
local function StoreBackup(list, owner)
    local clean = CB.Clean(list)
    if not clean then return false end
    local mine = Mine(true)
    local entry = { time = Now(), list = clean }
    if type(owner) == "string" and not Core.IsSecret(owner) and owner ~= "" then entry.owner = owner end
    if type(mine.first) ~= "table" then mine.first = Core.CopyTable(entry) end
    mine.last = entry
    return true
end

-- Beim Anmelden: eine vorher vorgemerkte Sicherung zum Charakter ziehen
Core.Listen("CHARS_READY", function() Mine(false) end)

function CB.Backup(which)
    local mine = Mine(false)
    local entry = type(mine) == "table" and mine[which == "first" and "first" or "last"] or nil
    if type(entry) ~= "table" or type(entry.list) ~= "table" then return nil end
    return Core.CopyTable(entry)
end

---------------------------------------------------------------------------
-- Schreiben (nur außerhalb des Kampfes)
---------------------------------------------------------------------------

function CB.OnChange(fn)
    if type(fn) ~= "function" then return false end
    listeners[#listeners + 1] = fn
    return true
end

local function CallOnDone(opts, ok, reason, detail)
    if type(opts.onDone) == "function" then
        local fine, err = pcall(opts.onDone, ok, reason, detail)
        if not fine then Core.Error(opts.owner or ADDON, err, "ClickBindings onDone") end
    end
end

-- also: opts früherer Wünsche, die in diesen eingeflossen sind (Assign/Unassign auf einen wartenden Wunsch) –
-- ihr onDone erfährt dasselbe Ergebnis
local function Done(opts, ok, reason, detail, also)
    CallOnDone(opts, ok, reason, detail)
    for _, older in ipairs(also or {}) do CallOnDone(older, ok, reason, detail) end
    for _, fn in ipairs(listeners) do
        local fine, err = pcall(fn, ok, reason, detail)
        if not fine then Core.Error(ADDON, err, "ClickBindings OnChange") end
    end
    return ok, reason, detail
end

-- Gleiche Belegung? (Reihenfolge egal)
local function SameRaw(a, b)
    if #a ~= #b then return false end
    local at = {}
    for _, raw in ipairs(a) do at[SlotKey(raw.button, raw.modifiers)] = raw end
    for _, raw in ipairs(b) do
        local other = at[SlotKey(raw.button, raw.modifiers)]
        if not other or other.type ~= raw.type or other.actionID ~= raw.actionID then return false end
    end
    return true
end

local function Apply(list, opts, also)
    local owner = opts.owner or ADDON
    local function Finish(ok, reason, detail) return Done(opts, ok, reason, detail, also) end
    local current, complete = CB.List()
    if not current then return Finish(false, complete or "error") end
    if not complete and not opts.force then return Finish(false, "unreadable") end
    local detail = { skipped = {}, dropped = {} }
    local final = list
    if opts.keepDefaults ~= false then final, detail.dropped = CB.KeepDefaults(list, current) end
    local currentRaw, known = {}, {}
    for _, entry in ipairs(current) do
        local raw = ToRaw(entry)
        if raw then
            currentRaw[#currentRaw + 1] = raw
            known[raw.type .. ":" .. raw.actionID] = true
        end
    end
    local can = opts.checkSpells and Api("CanSpellBeClickBound") or nil
    local raws = {}
    for _, entry in ipairs(final) do
        local raw = ToRaw(entry)
        if raw and can and entry.kind == "spell" and not known[raw.type .. ":" .. raw.actionID] then
            local ok, allowed = pcall(can, raw.actionID)
            if ok and not Core.IsSecret(allowed) and allowed == false then raw = nil end
        end
        if raw then raws[#raws + 1] = raw else detail.skipped[#detail.skipped + 1] = entry end
    end
    if complete and SameRaw(currentRaw, raws) then return Finish(true, "same", detail) end
    if opts.backup ~= false and not StoreBackup(current, opts.owner) then return Finish(false, "unreadable", detail) end
    local ok, err = pcall(Api("SetProfileByInfo"), raws)
    if not ok then
        Core.Error(owner, err, "ClickBindings Set")
        if not opts.quiet then Core.Print(owner, Core.L.CLICKBIND_FAILED) end
        return Finish(false, "error", detail)
    end
    -- Blizzards offenes Fenster zeigte sonst den alten Stand und schriebe ihn beim Speichern zurück (T4-NG2) – eine
    -- Stelle für alle Schreibwege: ezHeal, ezMacro („Ränge aktualisieren“), Nachholen
    -- nach dem Kampf. Ohne opts.quiet: Der Hinweis auf ungespeicherte Änderungen dort warnt vor Datenverlust und ist
    -- keine Kampf- oder Fehlermeldung, die der Aufrufer selbst gibt (Gegenprüfung: ezMacros „Ränge aktualisieren“
    -- schreibt immer mit quiet, Speichern im Fenster schriebe sonst still die alten Ränge zurück).
    CB.Reload()
    return Finish(true, nil, detail)
end

function CB.Flush()
    if not pending or Core.InCombat() then return false end
    local job = pending
    pending = nil
    return Apply(job.list, job.opts, job.also)
end

function CB.Pending() return pending ~= nil end

-- Den wartenden Wunsch streichen. Mit reason erfährt sein onDone (und das der eingeflossenen Wünsche) es als
-- false, reason – die Zuhörer von OnChange nicht, es gab keinen Schreibversuch. → true, wenn einer wartete
local function Drop(reason)
    local job = pending
    if not job then return false end
    pending = nil
    Core.CancelAfterCombat(CB.QUEUE_KEY)
    if reason then
        local detail = { skipped = {}, dropped = {} }
        CallOnDone(job.opts, false, reason, detail)
        for _, older in ipairs(job.also or {}) do CallOnDone(older, false, reason, detail) end
    end
    return true
end

function CB.Cancel() return Drop("cancelled") end

-- Einen bereinigten Wunsch abgeben: außerhalb des Kampfes sofort schreiben, im Kampf als wartenden Wunsch
-- merken. Ein wartender Wunsch wird dabei ersetzt; also (siehe Done) trägt die Wünsche, die in diesen eingeflossen
-- sind. Ohne also erfährt das onDone des ersetzten Wunsches false, "replaced"; mit also steckt er im neuen.
local function Submit(clean, opts, also)
    Drop(also == nil and "replaced" or nil)
    if Core.InCombat() then
        pending = { list = clean, opts = opts, also = also }
        if not opts.quiet then Core.CombatNotice(nil, Core.L.CLICKBIND_WHAT, "later", { center = true, chat = false }) end
        Core.AfterCombat(CB.Flush, CB.QUEUE_KEY, opts.owner or ADDON)
        return false, "combat"
    end
    return Apply(clean, opts, also)
end

function CB.Set(list, opts)
    if type(opts) ~= "table" then opts = {} end
    if not CB.Writable() then return false, "missing" end
    local clean = CB.Clean(list)
    if not clean then return false, "invalid" end
    return Submit(clean, opts)
end

-- Worauf bauen Assign und Unassign auf? Wartet ein Wunsch, auf dessen Liste – sonst ginge er verloren (zwei Assign
-- im Kampf, oder Load im Kampf und danach Assign). Sonst auf Blizzards aktueller Belegung.
-- → liste, vollständig, wartender Wunsch | nil, grund
local function Base()
    if pending then return Core.CopyTable(pending.list), true, pending end
    return CB.List()
end

-- opts für einen Wunsch, der einen wartenden fortschreibt: dessen Einstellungen gelten weiter (z. B. checkSpells
-- von Load, keepDefaults = false von Restore), die neuen gehen vor; das alte onDone erfährt das gemeinsame Ergebnis.
local function Merge(job, opts)
    local use, also = {}, {}
    for key, value in pairs(job.opts) do
        if key ~= "onDone" then use[key] = value end
    end
    for key, value in pairs(type(opts) == "table" and opts or {}) do use[key] = value end
    for _, older in ipairs(job.also or {}) do also[#also + 1] = older end
    also[#also + 1] = job.opts
    return use, also
end

local function Resubmit(list, opts, job)
    if not job then return CB.Set(list, opts) end
    if not CB.Writable() then return false, "missing" end
    local clean = CB.Clean(list)
    if not clean then return false, "invalid" end
    local use, also = Merge(job, opts)
    return Submit(clean, use, also)
end

function CB.Assign(entry, opts)
    local list, complete, job = Base()
    if not list then return false, complete or "error" end
    local _, reason = CB.Put(list, entry)
    if reason then return false, reason end
    if not complete and not (type(opts) == "table" and opts.force) then return false, "unreadable" end
    return Resubmit(list, opts, job)
end

function CB.Unassign(button, modifiers, opts)
    local list, complete, job = Base()
    if not list then return false, complete or "error" end
    if not CB.Remove(list, button, modifiers) then return true, "same" end
    return Resubmit(list, opts, job)
end

function CB.Restore(which, opts)
    local backup = CB.Backup(which)
    if not backup then return false, "missing" end
    local use = { keepDefaults = false }
    for key, value in pairs(type(opts) == "table" and opts or {}) do use[key] = value end
    return CB.Set(backup.list, use)
end

---------------------------------------------------------------------------
-- Blizzards Fenster
---------------------------------------------------------------------------

function CB.Open(opts)
    if not CB.Available() then return false, "missing" end
    return Core.OpenPanel(CB.PANEL, nil, opts)
end

function CB.Toggle(quiet)
    if not CB.Available() then return false, "missing" end
    return Core.TogglePanel(CB.PANEL, nil, quiet)
end

function CB.Shown()
    return Core.PanelShown(CB.PANEL)
end

-- Ungespeicherte Änderungen in Blizzards Fenster? Nur lesen (Blizzards Feld pendingChanges, Forever-Quelle
-- Blizzard_ClickBindingUI.lua: true beim Bearbeiten, false nach Refresh; nur Blizzards Schließen-Knopf fragt danach).
local function Unsaved()
    local frame = rawget(_G, "ClickBindingFrame")
    if type(frame) ~= "table" then return false end
    local ok, value = pcall(function() return frame.pendingChanges end)
    if not ok or Core.IsSecret(value) then return false end
    return value == true
end
CB.Unsaved = Unsaved     -- auch für ezHeal (Zauberbuch und Klick-Zauber zusammen schließen)

-- Lädt ezCore Blizzards Fenster gerade neu (CB.Reload: schließen, öffnen, Makros zurück)? Module, die auf Schließen und
-- Öffnen von Klick-Zauber oder Zauberbuch reagieren (ezHeal, Dock.lua), halten sich solange zurück.
local reloading = false
function CB.Reloading() return reloading end

-- Blizzards Fenster blendet beim Schließen sein „fokussiertes“ Fenster aus, auch die Makroverwaltung (OnHide →
-- ClearFocusedFrame → HideUIPanel), und zeigt beim Öffnen das Zauberbuch (OnShow → SetFocusedFrame(FramePortraits[1]),
-- Porträt 1 = PlayerSpellsFrame; Forever-Quelle Blizzard_ClickBindingUI.lua/.xml). Wer gerade in der Makroverwaltung
-- arbeitet (ezMacro „Ränge aktualisieren“), bekommt sie nach dem Neuladen zurück; das Zauberbuch schließt
-- wieder, wenn es vorher zu war. Nur über den Panel-Dienst, kein eigenes SetFocusedFrame (Leitlinie 5).
local function RestoreMacro(bookBefore)
    if not bookBefore and Core.Panels.FrameVisible("PlayerSpellsFrame") == true then
        Core.ClosePanel("spellbook", nil, true)
    end
    if Core.PanelShown("macro") ~= true then Core.OpenPanel("macro", nil, true) end
end

-- Offenes Fenster neu laden: schließen und öffnen über ezCores Panel-Dienst (Blizzard liest die Belegung in OnShow).
-- Heute schließt und öffnet Klick-Zauber nur der Spieler (Panels.SelfOnly): Es bleibt beim Hinweis, der auch vor dem
-- Speichern im noch offenen Fenster warnt. Das Neuladen selbst gilt, falls selfOnly wieder entfällt.
-- Nichts in Blizzards Tabellen schreiben (Leitlinie 5); nur außerhalb des Kampfes. Ungespeicherte Änderungen des
-- Spielers verwirft ezCore nicht: Dann bleibt das Fenster offen, und ein Hinweis nennt die Gefahr beim Speichern
-- (quiet = true nur für Aufrufer, die selbst warnen; Apply ruft ohne quiet).
-- → true | false, "closed" (nicht offen) | "unsaved" | "combat" | Grund von Core.OpenPanel
function CB.Reload(quiet)
    if CB.Shown() ~= true then return false, "closed" end
    if Core.InCombat() then return false, "combat" end
    if Unsaved() then
        if not quiet then Core.Print(ADDON, Core.L.CLICKBIND_UNSAVED) end
        return false, "unsaved"
    end
    -- Klick-Zauber öffnet und schließt seit dem 23.11.2026 nur der Spieler (Kern/Panels.lua, selfOnly; Entscheidung des
    -- Nutzers „Weg nennen“): Hinweis, dass die neue Belegung nach erneutem Öffnen erscheint
    if Core.Panels.SelfOnly(CB.PANEL) then
        if not quiet then Core.Print(ADDON, Core.L.CLICKBIND_REOPEN) end
        return false, "self"
    end
    local macro = Core.PanelShown("macro") == true
    local book = Core.Panels.FrameVisible("PlayerSpellsFrame") == true
    reloading = true
    local ok, opened, reason = pcall(function()
        local closed, why = CB.Toggle(true)
        if not closed then return false, why end
        if CB.Shown() then return false, "error" end
        local done, because = CB.Open(true)
        if done and macro then RestoreMacro(book) end
        return done, because
    end)
    reloading = false
    if not ok then
        Core.Error(ADDON, opened, "CB.Reload")
        return false, "error"
    end
    return opened, reason
end

---------------------------------------------------------------------------
-- Benannte Profile
---------------------------------------------------------------------------

local function ValidName(name)
    if not Text(name) then return nil end
    name = Core.Trim(name)
    if name == "" then return nil end
    local length = strlenutf8 and strlenutf8(name) or #name
    if length > CB.MAX_NAME then return nil end
    return name
end

function CB.Has(name)
    return Text(name) and type(DB().profiles[name]) == "table" or false
end

function CB.Save(name, list)
    name = ValidName(name)
    if not name then return nil, "invalid" end
    local complete = true
    if list == nil then
        list, complete = CB.List()
        if not list then return nil, complete or "error" end
        if not complete then return nil, "unreadable" end
    end
    local clean = CB.Clean(list)
    if not clean then return nil, "invalid" end
    DB().profiles[name] = { class = Core.PlayerClass and Core.PlayerClass() or nil, time = Now(), list = clean }
    return name
end

function CB.Profile(name)
    if not CB.Has(name) then return nil end
    local stored = DB().profiles[name]
    local list = CB.Clean(stored.list)
    if not list then return nil end
    return { name = name, class = Text(stored.class) and stored.class or nil,
        time = type(stored.time) == "number" and stored.time or 0, list = list }
end

function CB.Names()
    local names = {}
    for name, stored in pairs(DB().profiles) do
        if Text(name) and type(stored) == "table" then names[#names + 1] = name end
    end
    table.sort(names, function(a, b)
        local la, lb = a:lower(), b:lower()
        if la ~= lb then return la < lb end
        return a < b
    end)
    return names
end

function CB.Profiles()
    local out = {}
    for _, name in ipairs(CB.Names()) do
        local profile = CB.Profile(name)
        if profile then out[#out + 1] = profile end
    end
    return out
end

function CB.Delete(name)
    if not CB.Has(name) then return false end
    DB().profiles[name] = nil
    return true
end

function CB.Load(name, opts)
    local profile = CB.Profile(name)
    if not profile then return false, "unknown" end
    local use = { checkSpells = true }
    for key, value in pairs(type(opts) == "table" and opts or {}) do use[key] = value end
    return CB.Set(profile.list, use)
end

function CB.Export(name)
    local list, class, label
    if name ~= nil then
        local profile = CB.Profile(name)
        if not profile then return nil, "unknown" end
        list, class, label = profile.list, profile.class, profile.name
    else
        local complete
        list, complete = CB.List()
        if not list then return nil, complete or "error" end
        if not complete then return nil, "unreadable" end
        list = CB.Clean(list)
        if not list then return nil, "invalid" end
        class = Core.PlayerClass and Core.PlayerClass() or nil
    end
    return Core.Serialize({ kind = CB.EXPORT_KIND, v = CB.EXPORT_VERSION, name = label, class = class, bindings = list })
end

-- Klassen-Token, das ezCore oder der Client kennt (Core.CLASSES, RAID_CLASS_COLORS) – sonst nil
local function KnownClass(class)
    if not Text(class) then return nil end
    for _, token in ipairs(Core.CLASSES or {}) do
        if token == class then return class end
    end
    local colors = rawget(_G, "RAID_CLASS_COLORS")
    if type(colors) == "table" and colors[class] ~= nil then return class end
    return nil
end

function CB.Import(text, name)
    local value, reason = Core.Deserialize(text)
    if type(value) ~= "table" then return nil, reason or "syntax" end
    if value.kind ~= CB.EXPORT_KIND then return nil, "kind" end
    if (tonumber(value.v) or 0) > CB.EXPORT_VERSION then return nil, "version" end
    -- fremder Text: streng (T4-NG3) – nur Blizzards Tasten, Umschalt-Bits und Arten, Grenzen
    local list = CB.Clean(value.bindings, true)
    if not list then return nil, "syntax" end
    if CB.Count() >= CB.MAX_PROFILES then return nil, "full" end
    local profiles = DB().profiles
    -- Name aus fremdem Text ohne Farb-, Link- und Texturcodes, „|“ und Steuerzeichen, gekürzt (Core.CleanImportName wie
    -- bei Profilen und Makros; Gesamtreview 18.11.2026, Nachlauf P19a – vorher ging value.name nur durch ValidName)
    local base = ValidName(name) or ValidName(Core.CleanImportName(value.name, CB.MAX_NAME))
    local unique = Core.UniqueName(base or Core.L.PROFILE_IMPORTED, function(n) return profiles[n] ~= nil end,
        { maxChars = CB.MAX_NAME, default = Core.L.PROFILE_IMPORTED })
    profiles[unique] = { class = KnownClass(value.class), time = Now(), list = list }
    return unique
end

---------------------------------------------------------------------------
-- Status
---------------------------------------------------------------------------

function CB.Count()
    local count = 0
    for name, stored in pairs(DB().profiles) do
        if Text(name) and type(stored) == "table" then count = count + 1 end
    end
    return count, pending and 1 or 0
end

function CB.StatusLine()
    local count, waiting = CB.Count()
    if count == 0 and waiting == 0 then return nil end
    if waiting > 0 then return Core.L.STATUS_CLICKBIND_WAITING:format(count) end
    return Core.L.STATUS_CLICKBIND:format(count)
end
