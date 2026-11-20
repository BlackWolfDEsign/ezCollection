local ADDON, ns = ...
local L = ns.L

--[[
    ezBars – Zusatzleisten im Blizzard-Stil (Esc → Optionen → AddOns → ezCollection → ezBars).

    Blizzards Bearbeitungsmodus auf Forever (Blizzard_EditMode/Shared/EditModeSettingDisplayInfo.lua, Zweig
    „forever“) erlaubt je Aktionsleiste 6 bis 12 Knöpfe in 1 bis 4 Reihen und hat 8 Leisten. Für 2×2, 4×4,
    3×8 oder 4×6 braucht es ezBars. Die Knöpfe sind Blizzards ActionBarButtonTemplate, jeder zeigt einen festen
    Aktionsplatz; Tasten kommen aus Blizzards Tastaturbelegung (Bindings.xml).

    Blizzards Leisten bleiben unberührt: ezBars verschiebt, skaliert und hängt keine davon um und meldet nichts
    beim Bearbeitungsmodus an. Verschoben werden die Leisten über ezCore.Mover (Bars.lua).

    Zweite Leistenart (Entscheidung des Nutzers 14.11.2026, Emote-Leisten über ezBars): Leisten, deren Knöpfe ein
    anderes Modul liefert – ns.RegisterBar unten, Schnittstelle ezCore.API("ezBars").RegisterBar. Diese Knöpfe sind
    gewöhnliche Knöpfe ohne Aktionsplatz und ohne Eintrag in Bindings.xml; ein Klick ruft die Funktion des Anbieters.
]]

-- Je Leiste dieselben Einstellungen (bar<n><Name>); Leiste 1 ist von Anfang an da.
ns.SHOW_VALUES = { "always", "combat", "nocombat", "hidden" }
ns.DEFAULTS = {}
for n = 1, ns.MAX_BARS do
    local prefix = "bar" .. n
    ns.DEFAULTS[prefix .. "On"] = n == 1
    ns.DEFAULTS[prefix .. "Cols"] = 4
    ns.DEFAULTS[prefix .. "Rows"] = 3
    ns.DEFAULTS[prefix .. "Size"] = 100       -- Prozent wie Blizzards „Symbolgröße“
    ns.DEFAULTS[prefix .. "Padding"] = 2      -- Pixel wie Blizzards „Symbolabstand“
    ns.DEFAULTS[prefix .. "Show"] = "always"
    ns.DEFAULTS[prefix .. "Empty"] = true
    ns.DEFAULTS[prefix .. "Page"] = "auto"
end

local Core = ezCore

--[[
    Umstellung der gespeicherten Abstände (Schema 1, Spieltest 15.11.2026): Seit Welle 13 gilt „Abstand“ als Pixel bei
    100 % und wächst mit der Knopfgröße (Bars.PlaceInGrid). Vorher galt er fest in Pixeln. Gespeichert sind auch die
    Standardwerte (Core.FillDefaults, AddDefaults bei RegisterBar) – ohne Umrechnung würde z. B. der alte Standard 3 der
    Emote-Leisten bei 50 % nur noch 1,5 px zeigen. Darum einmalig: Abstand × 100 / Größe, gerundet, auf die Grenzen der
    Regler (0–20). Der sichtbare Abstand bleibt so (bis auf Rundung; über 20 bei kleiner Größe geht nicht). Gilt für die
    Arbeitsdaten (settings) und die gespeicherten Profile (profiles[name].settings), für Aktionsleisten (bar<n>Padding)
    und Leisten anderer Module (x_<id>_Padding, auch solche, deren Anbieter gerade nicht läuft). Vorher exportierte
    Profiltexte tragen den alten Wert (der Text hat keine Angabe, aus welcher Zeit er stammt).
    Gibt die Zahl der geänderten Werte zurück.
]]
function ns.ScalePaddings(settings)
    if type(settings) ~= "table" then return 0 end
    local changed = 0
    for key, value in pairs(settings) do
        local sizeKey
        local bar = type(key) == "string" and key:match("^(bar%d+)Padding$") or nil
        if bar then
            sizeKey = bar .. "Size"
        else
            local id, name = ns.ExtraKeyParts(key)
            if name == "Padding" then sizeKey = ns.ExtraKey(id, "Size") end
        end
        local size = sizeKey and settings[sizeKey]
        if type(value) == "number" and value == value and type(size) == "number" and size == size and size ~= 100 then
            size = math.max(50, math.min(200, size))
            local new = math.max(0, math.min(20, math.floor(value * 100 / size + 0.5)))
            if new ~= value then
                settings[key] = new           -- vorhandenen Schlüssel ändern ist während pairs erlaubt
                changed = changed + 1
            end
        end
    end
    return changed
end

-- Schritte für Core.Migrate (über das Gerüst: schema, migrations). Läuft vor dem Eintragen der Standardwerte und
-- kommt mit einem leeren Speicher klar (neue Installation: nichts umzurechnen).
ns.MIGRATIONS = {
    [1] = function(db)
        ns.ScalePaddings(db.settings)
        if type(db.profiles) == "table" then
            for _, profile in pairs(db.profiles) do
                if type(profile) == "table" then ns.ScalePaddings(profile.settings) end
            end
        end
    end,
}

-- Gerüst aus ezCore (Core.ModuleScaffold, seit Welle 1): Datenbank, Einloggen, Befehl /ezbars und Status.
-- ezBarsDB: settings (alle Charaktere), chars[charKey] = { pages = { [n] = { Seite, … } }, spare = … } (Aktionsplätze
-- je Charakter), hints (einmalige Hinweise, fremde Leisten-Addons), tour (gesehene Erklärblasen).
Core.NewModule(ADDON, ns, {
    title = "ezBars",
    -- 1.14.0 wegen Core.ApplySetting (Profiles.lua, nach 1.13.0 ohne eigene Nummer); seit 1.13.0: page:Profiles, opts.shown an page:Button, Mover.Open, Style.SetStrata und Style.ICON kamen alle nach dem
    -- Stand 1.12.0 (Welle 17v); P.SetForClass; StyleIcon (Symbol mit Blizzards Maske und Rahmen auf den Knöpfen anderer
    -- Module, Spieltest 15.11.2026); ApplySetting (Profiles.lua, Welle 23a, ohne neue Nummer nach 1.13.0)
    -- 1.15.0: Bausteine aus dem Gesamtreview vom 18.11.2026, u. a. Core.CombatNotice, Core.HelpLines, Core.SlashReset, Core.TipTitle
    -- (Liste je Modul in docs/roadmap/uebergreifend.md, P7)
    core = "1.15.0", needs = { "scaffold", "tourOwner", "AfterCombat", "OpenPanel", "NewProfiles", "StyleIcon",
        -- Gesamtreview 18.11.2026, P19c (ohne neue Versionsnummer): Ersatzsymbol aus ezCore (T16-NM6)
        "ICON_FALLBACK",
        "Style.SetStrata", "Style.ICON", "ApplySetting", "compartmentMain", "slashMain", "CombatNotice", "KeyBindPathText",
        "SettingsPathText", "TipTitle" },   -- Style: Design-System (Welle 22); TipTitle: Rollen statt Farbzahlen (T9-6)
    db = "ezBarsDB", tables = { "chars", "hints", "tour" },
    schema = 1, migrations = ns.MIGRATIONS,   -- 1: Abstand als Pixel bei 100 % (ns.ScalePaddings oben)
    onLoad = function(db)
        -- Werte außerhalb der Grenzen (alte Version, Hand-Edit) auf den Standard
        for n = 1, ns.MAX_BARS do
            local show = db.settings["bar" .. n .. "Show"]
            local valid = false
            for _, value in ipairs(ns.SHOW_VALUES) do if value == show then valid = true end end
            if not valid then db.settings["bar" .. n .. "Show"] = ns.DEFAULTS["bar" .. n .. "Show"] end
        end
    end,
    login = true,
    -- „optionen“, „status“ und „hilfe“ versteht das Gerüst; die eigenen Wörter stehen in ns.SlashExtra (unten)
    -- reset: „/ezbars zuruecksetzen“ fragt wie der Knopf „Einstellungen zurücksetzen“ und richtet danach die Leisten neu
    -- ein (Core.SlashReset nimmt ask und onReset von page:ResetButton; Gesamtreview T18-20)
    slash = { extra = function(cmd, rest, input) return ns.SlashExtra(cmd, rest, input) end, reset = true },
})

-- Einstellungen einer Leiste eines anderen Moduls (ns.RegisterBar): x_<id>_<Name>, z. B. x_ezMacroEmote1_Cols.
-- Kein „On“ (ob es die Leiste gibt, bestimmt ihr Anbieter), kein „Empty“ und „Page“ (keine Aktionsplätze).
ns.EXTRA_KEYS = { "Cols", "Rows", "Size", "Padding", "Show" }
ns.EXTRA_DEFAULTS = { Cols = 6, Rows = 1, Size = 100, Padding = 2, Show = "always" }
ns.MAX_EXTRA = 32           -- angemeldete Leisten zugleich (Schutz gegen eine Schleife im Anbieter)
ns.EXTRA_ID_MAX = 32        -- Länge einer Kennung

-- Kennung einer angemeldeten Leiste: Buchstabe, dann Buchstaben und Ziffern (wird Teil von Einstellungs-, Rahmen-
-- und Mover-Namen).
function ns.ValidExtraId(id)
    return type(id) == "string" and #id <= ns.EXTRA_ID_MAX and id:match("^%a[%w]*$") ~= nil
end

function ns.ExtraKey(id, name) return "x_" .. id .. "_" .. name end

-- Kennung und Name aus einem Schlüssel x_<id>_<Name>; nil, wenn es keiner ist.
function ns.ExtraKeyParts(key)
    if type(key) ~= "string" then return nil end
    local id, name = key:match("^x_(%a[%w]*)_(%a+)$")
    if id and #id <= ns.EXTRA_ID_MAX and ns.EXTRA_DEFAULTS[name] ~= nil then return id, name end
    return nil
end

-- Wert einer Leisten-Einstellung, z. B. ns.BarSetting(2, "Cols") oder ns.BarSetting("ezMacroEmote1", "Cols").
function ns.BarSetting(n, name)
    local key = type(n) == "number" and ("bar" .. n .. name) or ns.ExtraKey(n, name)
    local value = ns.S and ns.S[key]
    if value == nil then value = ns.DEFAULTS[key] end
    if value == nil and type(n) ~= "number" then value = ns.EXTRA_DEFAULTS[name] end
    return value
end

function ns.BarName(n) return L.BAR_NAME:format(n) end

---------------------------------------------------------------------------
-- Datenbank: Einstellungen für alle Charaktere, Aktionsplätze je Charakter (angelegt vom Gerüst, siehe oben)
---------------------------------------------------------------------------

-- Daten dieses Charakters (nach PLAYER_LOGIN, wenn ezCore den Namen kennt).
function ns.Char()
    local key = ns.charKey or Core.charKey
    if not (ns.db and key) then return nil end
    local char = ns.db.chars[key]
    if type(char) ~= "table" then
        char = {}
        ns.db.chars[key] = char
    end
    char.pages = type(char.pages) == "table" and char.pages or {}
    return char
end

-- Vergisst ezCore einen Charakter, vergisst ezBars seine Aktionsplätze mit. Die Profil-Zuordnung des Charakters
-- (profileFor, specMode) streicht seit Welle 23a das Profil-Gerüst selbst (P.Forget in Core.NewProfiles).
Core.Listen("CHAR_FORGOTTEN", function(key)
    if ns.db and key then ns.db.chars[key] = nil end
end, ADDON)

-- Einloggen: ns.charKey, ns.realm und ns.me setzt das Gerüst (login = true) und ruft dann ns.RunReady().
-- Die Klasse zuerst – alle späteren OnReady-Funktionen (Leisten einrichten) brauchen sie für die Gestaltseiten.
ns.OnReady(function()
    ns.playerClass = Core.PlayerClass()
end)

---------------------------------------------------------------------------
-- Fremde Leisten-Addons: ezBars bleibt, weist aber einmal darauf hin. Erkannt wird in ezCore
-- (Core.WhoHandles("actionBars"): heute Bartender4 und Dominos, Liste in docs/fremd-addons.md).
---------------------------------------------------------------------------

-- Anzeigename und Schlüssel des Leisten-Addons, das gerade läuft, sonst nil.
function ns.OtherBarAddOn()
    return ns.OtherFor("actionBars")
end

-- Als Liste (für den Status): { Anzeigename } oder leer.
function ns.OtherBarAddOns()
    local label = ns.OtherBarAddOn()
    return label and { label } or {}
end

ns.OnReady(function()
    local label, key = ns.OtherBarAddOn()
    key = key or label
    if label and not ns.db.hints[key] then
        ns.db.hints[key] = true
        ns.Print(L.OTHER_BARS_ADDON:format(label, label, label))
    end
end)

---------------------------------------------------------------------------
-- Blizzards Tastaturbelegung (die Einträge stehen in Bindings.xml)
---------------------------------------------------------------------------

-- Öffnet Blizzards Seite „Tastaturbelegung“; dort startet Blizzards eigener Knopf den Schnelltastenbelegungsmodus
-- (taint-sicher, ezBars ruft QuickKeybindFrame nicht selbst auf). Der Hinweis im Chat sagt, wo ezBars steht.
-- Geöffnet wird über ezCore (Core.OpenPanel): im Kampf öffnet nichts, ezCore zeigt stattdessen seinen Hinweis.
-- Rückgabe: true, oder false und der Grund von Core.OpenPanel ("combat", "missing", "error").
function ns.OpenKeybindings()
    ns.Print(L.KEYBIND_FALLBACK:format(Core.KeyBindPathText(L.BINDING_HEADER)))
    return Core.OpenPanel("settings", "keybindings")
end

---------------------------------------------------------------------------
-- Status
---------------------------------------------------------------------------

local function SlotText(pages)
    local parts = {}
    for _, page in ipairs(pages) do
        local first, last = ns.Slots.Range(page)
        parts[#parts + 1] = first .. "–" .. last
    end
    return #parts > 0 and table.concat(parts, ", ") or "–"
end

-- ns.PrintStatus kommt vom Gerüst (Kopfzeile ns.StatusHeader(), dann die Statuszeilen, zuletzt eine Meldung von
-- Core.Require); hier stehen nur die Zeilen: je Leiste Raster, Plätze und leere Felder, die Leisten anderer Module,
-- Wartendes, Überschneidungen, fremde Addons.
function ns.StatusText()
    local lines = {}
    for n = 1, ns.MAX_BARS do
        if ns.BarSetting(n, "On") then
            local auto = ns.Slots.ManualPage(n) == nil
            local line = L.STATUS_BAR:format(ns.BarName(n), ns.BarSetting(n, "Cols"), ns.BarSetting(n, "Rows"),
                SlotText(ns.Slots.PagesFor(n)), auto and L.STATUS_AUTO or "")
            -- Felder ohne Aktionsplatz (Bars.EmptyFields: was die Leiste gerade wirklich zeigt)
            local empty = ns.Bars and ns.Bars.EmptyFields(n) or 0
            if empty > 0 then line = line .. L.STATUS_EMPTY:format(empty) end
            lines[#lines + 1] = line
        else
            lines[#lines + 1] = L.CMD_OFF:format(ns.BarName(n))
        end
    end
    -- Leisten anderer Module: Raster, gezeigte von gelieferten Knöpfen, Lage
    for _, entry in ipairs(ns.Extras()) do
        local info = ns.ExtraInfo(entry.id)
        local place = L["ANCHOR_" .. tostring(info.docked or info.anchor)]
        if info.moved then
            place = L.ANCHOR_MOVED
        elseif info.docked and info.docked ~= info.anchor then
            place = L.ANCHOR_FALLBACK:format(L["ANCHOR_" .. info.anchor])
        end
        lines[#lines + 1] = L.STATUS_EXTRA:format(ns.ExtraTitle(entry), info.cols, info.rows, info.shown, info.buttons, place)
    end
    if ns.Bars and ns.Bars.Pending() then lines[#lines + 1] = L.STATUS_PENDING end
    local conflicts = ns.Slots.Conflicts()
    for _, text in ipairs(conflicts) do lines[#lines + 1] = text end
    if #conflicts == 0 then lines[#lines + 1] = L.STATUS_NO_CONFLICTS end
    for _, name in ipairs(ns.OtherBarAddOns()) do lines[#lines + 1] = L.OTHER_BARS_ADDON:format(name, name, name) end
    return lines
end
ns.AddStatusLine(ns.StatusText)

function ns.PrintFreeSlots()
    ns.Print(L.STATUS_FREE_HEAD)
    for _, page in ipairs(ns.Slots.PAGES) do
        local first, last = ns.Slots.Range(page)
        ns.Print(L.PAGE_LABEL:format(first, last, ns.Slots.PageLabel(page)) .. " – " .. ns.Slots.PageState(page))
    end
end

---------------------------------------------------------------------------
-- Leisten-Profile: die Profile führt ezMacro (ezCore.API("ezMacro"), seit 1.2); ezBars baut keine eigenen.
-- Je Leiste ein Profil „ezBars: Leiste n“ (fester Name, unabhängig von der Sprache des Clients, damit jeder
-- Charakter es findet). Laden nach Reihenfolge (byOrder): Knopf i bekommt den i-ten gespeicherten Platz, auch wenn
-- die Leiste auf diesem Charakter andere Aktionsplätze nutzt. Tastenbelegungen lädt ezBars nicht mit.
---------------------------------------------------------------------------

function ns.MacroProfiles()
    local mac = Core.API("ezMacro")
    if mac and type(mac.SaveProfile) == "function" and type(mac.LoadProfile) == "function"
        and type(mac.ProfileNames) == "function" then
        return mac
    end
    return nil
end

function ns.ProfileName(n) return ("ezBars: Leiste %d"):format(n) end

local function BarSlots(n)
    local bar = ns.Slots.Describe()[n]
    return bar and bar.slots or {}
end

-- Speichert die Plätze der Leiste n als Profil (ezMacro meldet das Ergebnis im Chat).
function ns.SaveBarProfile(n)
    local mac = ns.MacroProfiles()
    if not mac then ns.Print(L.PROFILE_NO_MACRO) return false end
    local slots = BarSlots(n)
    if #slots == 0 then ns.Print(L.PROFILE_EMPTY:format(ns.BarName(n))) return false end
    return mac.SaveProfile(ns.ProfileName(n), slots) ~= nil
end

-- Lädt das Profil der Leiste n auf ihre Plätze (ezMacro fragt einmal nach; im Kampf meldet ezMacro die Sperre).
function ns.LoadBarProfile(n)
    local mac = ns.MacroProfiles()
    if not mac then ns.Print(L.PROFILE_NO_MACRO) return false end
    local name, found = ns.ProfileName(n), false
    for _, existing in ipairs(mac.ProfileNames() or {}) do
        if existing == name then found = true end
    end
    if not found then ns.Print(L.PROFILE_MISSING:format(name)) return false end
    local slots = BarSlots(n)
    if #slots == 0 then ns.Print(L.PROFILE_EMPTY:format(ns.BarName(n))) return false end
    return mac.LoadProfile(name, slots, { byOrder = true, bindings = false }) == true
end

function ns.OpenMacroProfiles()
    local mac = Core.API("ezMacro")
    if mac and type(mac.OpenProfiles) == "function" and mac.OpenProfiles() then return true end
    ns.Print(L.PROFILE_NO_MACRO)
    return false
end

---------------------------------------------------------------------------
-- Leisten anderer Module (BARS-01, FP-15). Entscheidung des Nutzers vom 14.11.2026: „ezMacro sollte die ezBar als
-- leiste für emotes benutzen (+größeneinstellbar)“ – ein Modul meldet eine Leiste an und liefert ihre Knöpfe; ezBars
-- stellt sie dar (Bars.lua), verankert sie (Anchors.lua), bietet je Leiste eine Unterseite der Einstellungen
-- (Options.lua: Spalten, Reihen, Knopfgröße, Abstand, Sichtbarkeit), das Verschieben über ezCore.Mover, die Profile
-- (Profiles.lua) und eine Zeile im Status.
--
--   local id, anchor = ezCore.API("ezBars").RegisterBar({
--       id = "ezMacroEmote1",              -- Kennung: Buchstabe, dann Buchstaben/Ziffern, höchstens 32 Zeichen
--       name = "Emote-Leiste 1",           -- Anzeigename in der Sprache des Clients (Seite, Mover, Status)
--       owner = "ezMacro",                 -- Modul, dem die Leiste gehört (Anzeige, Fehlerliste)
--       buttons = {                        -- Knöpfe in ihrer Reihenfolge, höchstens ns.MAX_BUTTONS
--           { icon = <Datei | Datei-ID>, atlas = <Atlasname>,      -- Symbol (Atlas zuerst, wenn es ihn gibt)
--             tooltip = "Titel" | function(knopf) return titel, text end, text = "Erklärung",
--             onClick = function(knopf, maustaste) … end },        -- Links- und Rechtsklick
--       },
--       anchor = "chatSide" | "chatTop" | "free" | { point, rahmen, relPoint, x, y },   -- Standardplatz
--       offset = { x, y },                 -- Versatz zum Standardplatz am Chat (freiwillig)
--       defaults = { cols = 1, rows = 7, size = 50, padding = 2, show = "always" },    -- Standardwerte (freiwillig)
--                                          -- size in % (50–200), padding in px bei 100 %: ezBars skaliert jeden
--                                          -- Knopf als Ganzes, Symbol, Rahmen und Abstand wachsen gemeinsam
--   })
--   → Kennung und der Anker, den ezBars verstanden hat ("chatSide", "chatTop", "free", "custom"); bei einem Fehler
--     nil und der Grund: "def", "id", "name", "buttons", "taken" (Kennung gehört einem anderen Modul), "full".
--     Ein eigener Anker braucht einen der neun Punkte von SetPoint und als Rahmen einen Namen oder einen Rahmen;
--     sonst gilt "free". Lässt sich an ihm im Spiel nicht verankern (SetPoint wirft), steht der Fehler in der
--     Fehlerliste des Anbieters, und die Leiste steht frei, bis er sie neu anmeldet (BarInfo(id).docked == "free").
--
-- Wiederholbar: Dieselbe Kennung vom selben Modul ersetzt Name, Knöpfe und Anker (so ändert der Anbieter seine
-- Leiste); die Einstellungen und eine verschobene Lage bleiben. Im Kampf merkt ezBars die Anmeldung nur vor und baut
-- gleich danach (ns.AfterCombat). Ein Tooltip als Funktion wird beim Zeigen gerufen: Sie gibt Titel und Text zurück
-- oder füllt GameTooltip selbst (SetOwner ist dann schon gesetzt, Show ruft ezBars).
-- Kein Dienst in ezCore: Bisher braucht nur ezBars Raster und Anker (Auftrag BARS-01; braucht ein zweites Modul die
-- Technik statt der Schnittstelle, zieht sie um).
---------------------------------------------------------------------------

local extras, extraOrder = {}, {}       -- [Kennung] = Eintrag; Einträge in der Reihenfolge ihrer Anmeldung

-- Angemeldete Leisten in der Reihenfolge ihrer Anmeldung (die Liste nicht ändern).
function ns.Extras() return extraOrder end
function ns.Extra(id) return extras[id] end

-- Anzeigename mit dem Modul, dem die Leiste gehört: „Emote-Leiste 1 (ezMacro)“.
function ns.ExtraTitle(entry)
    if entry.owner then return L.EXTRA_TITLE:format(entry.name, entry.owner) end
    return entry.name
end

-- Knopfliste des Anbieters prüfen und kopieren (spätere Änderungen an seiner Tabelle wirken erst mit dem nächsten
-- RegisterBar/SetBarButtons). nil, wenn die Liste unbrauchbar ist.
local function CleanButtons(list)
    if type(list) ~= "table" then return nil end
    local out = {}
    for _, button in ipairs(list) do
        if type(button) ~= "table" or type(button.onClick) ~= "function" then return nil end
        if #out >= ns.MAX_BUTTONS then return nil end
        local icon, tooltip = button.icon, button.tooltip
        -- Leitlinie 6: zuerst Core.IsSecret – ein gesperrter Wert lässt sich nicht prüfen, die Leiste zeigt dann
        -- ihr Ersatzsymbol
        if Core.IsSecret(icon) or (type(icon) ~= "string" and type(icon) ~= "number") then icon = nil end
        if type(tooltip) ~= "string" and type(tooltip) ~= "function" then tooltip = nil end
        out[#out + 1] = {
            icon = icon,
            atlas = type(button.atlas) == "string" and button.atlas or nil,
            tooltip = tooltip,
            text = type(button.text) == "string" and button.text or nil,
            onClick = button.onClick,
        }
    end
    return out
end

-- Texte der Einstellungen einer angemeldeten Leiste: OPT_<key> und OPT_<key>_TIP in beiden Sprachen, für alle
-- Leisten gleich (wie bei bar<n> in Locale.lua).
local function AddTexts(id)
    for _, name in ipairs(ns.EXTRA_KEYS) do
        local generic, key = "OPT_EXTRA_" .. name:upper(), "OPT_" .. ns.ExtraKey(id, name)
        for _, tbl in pairs(ns.LOCALES) do
            tbl[key] = tbl[generic]
            tbl[key .. "_TIP"] = tbl[generic .. "_TIP"]
        end
        rawset(L, key, nil)             -- ns.L merkt sich jedes Nachschlagen; ein früher Zugriff darf nicht bleiben
        rawset(L, key .. "_TIP", nil)
    end
end

-- Standardwerte (allgemein, oder die des Anbieters) eintragen und gespeicherte Werte prüfen.
local function AddDefaults(id, wishes)
    for _, name in ipairs(ns.EXTRA_KEYS) do
        local key = ns.ExtraKey(id, name)
        local default = ns.EXTRA_DEFAULTS[name]
        ns.DEFAULTS[key] = default
        local wish = type(wishes) == "table" and ns.Profiles.Valid(key, wishes[name:lower()]) or nil
        if wish ~= nil then
            default = wish
            ns.DEFAULTS[key] = default
        end
        if ns.S then
            local current = ns.Profiles.Valid(key, ns.S[key])
            if current == nil then current = default end
            ns.S[key] = current
        end
    end
end

function ns.RegisterBar(def)
    if type(def) ~= "table" then return nil, "def" end
    local id = def.id
    if not ns.ValidExtraId(id) then return nil, "id" end
    if type(def.name) ~= "string" or def.name == "" then return nil, "name" end
    local buttons = CleanButtons(def.buttons)
    if not buttons then return nil, "buttons" end
    local owner = type(def.owner) == "string" and def.owner ~= "" and def.owner or nil
    local entry = extras[id]
    if entry and entry.owner ~= owner then return nil, "taken" end
    if not entry then
        if #extraOrder >= ns.MAX_EXTRA then return nil, "full" end
        entry = { id = id }
        extras[id] = entry
        extraOrder[#extraOrder + 1] = entry
    end
    entry.name, entry.owner, entry.buttons = def.name, owner, buttons
    entry.anchor, entry.point = ns.Anchors.Parse(def.anchor)
    entry.anchorFailed = nil            -- neuer Anker, neuer Versuch (Bars.ApplyExtras setzt es, wenn SetPoint wirft)
    local offset = type(def.offset) == "table" and def.offset or {}
    entry.offsetX, entry.offsetY = tonumber(offset[1] or offset.x) or 0, tonumber(offset[2] or offset.y) or 0
    AddTexts(id)
    AddDefaults(id, def.defaults)
    if ns.EnsureExtraPage then ns.EnsureExtraPage(id) end
    if ns.Bars then ns.Bars.ApplyExtras() end
    return id, entry.anchor
end

-- Neue Knopfliste für eine angemeldete Leiste (z. B. ein Emote an- oder abgewählt).
function ns.SetBarButtons(id, list)
    local entry = extras[id]
    if not entry then return nil, "id" end
    local buttons = CleanButtons(list)
    if not buttons then return nil, "buttons" end
    entry.buttons = buttons
    if ns.Bars then ns.Bars.ApplyExtras() end
    return true
end

-- Meldet eine Leiste ab: Sie verschwindet (im Kampf gleich danach). Ihre Einstellungen und ihre Lage bleiben für
-- eine spätere Anmeldung; ihre Unterseite der Einstellungen bleibt bis zum nächsten Laden stehen (Blizzards
-- Einstellungen kennen kein Abmelden) und sagt dann in ihrer ersten Zeile, dass die Leiste nicht angemeldet ist
-- (Options.lua: ExtraPage, ns.ExtraGoneHint).
function ns.UnregisterBar(id)
    local entry = extras[id]
    if not entry then return false end
    extras[id] = nil
    for index, other in ipairs(extraOrder) do
        if other == entry then
            table.remove(extraOrder, index)
            break
        end
    end
    if ns.Bars then ns.Bars.ApplyExtras() end
    return true
end

-- Stand einer angemeldeten Leiste (für Status, Tooltips, Tests und den Anbieter); nil ohne Anmeldung.
--   anchor   der gewünschte Standardplatz ("chatSide", "chatTop", "free", "custom")
--   docked   woran die Leiste wirklich hängt, sobald sie gebaut ist ("free": der Chat fehlt, am Anker des Anbieters
--            lässt sich nicht verankern, oder der Nutzer hat sie verschoben)
--   moved    true, wenn der Nutzer sie verschoben hat (ezCore.Mover; „Standardplatz“ auf ihrer Seite setzt zurück)
--   buttons  gelieferte Knöpfe · shown  davon im Raster · cut  die nicht hineinpassen
function ns.ExtraInfo(id)
    local entry = extras[id]
    if not entry then return nil end
    local cols = math.max(1, math.floor(tonumber(ns.BarSetting(id, "Cols")) or 1))
    local rows = math.max(1, math.floor(tonumber(ns.BarSetting(id, "Rows")) or 1))
    local total = #entry.buttons
    local shown = math.min(total, cols * rows)
    local frame = ns.Bars and ns.Bars.ExtraFrame(id) or nil
    return {
        id = id, name = entry.name, owner = entry.owner, anchor = entry.anchor,
        docked = frame and frame.ezDocked or nil,
        moved = ns.Bars ~= nil and Core.StoredPosition(ns.Bars.MoverKey(id)) ~= nil,
        cols = cols, rows = rows, buttons = total, shown = shown, cut = total - shown,
    }
end

---------------------------------------------------------------------------
-- Schnittstelle für andere Module (ezCore.API("ezBars")).
-- Aktionsplätze (Bars, UsedSlots, ButtonForSlot; BARS-07, V-153): UsedSlots nutzt ezMacro seit Welle 6 für das
-- Rang-Leuchten auf ezBars-Plätzen (ezMacro/Ranks.lua, BarSlots); die Leisten-Profile laufen umgekehrt (ezBars ruft
-- ezCore.API("ezMacro")). Bars und ButtonForSlot bleiben für Module, die Leisten bzw. den Knopf zu einem Aktionsplatz
-- suchen (Empfehlung umgesetzt, Antwort des Nutzers offen). Alle drei fragen nur ab und merken nichts
-- (Slots.Resolve ohne commit, V-154).
-- Leisten anderer Module (RegisterBar …): Beschreibung oben.
---------------------------------------------------------------------------

ns.API = {
    -- Leisten mit Anordnung und Aktionsplätzen dieses Charakters:
    -- { { index, name, shown, cols, rows, buttons, slots = { Platz, … }, empty = Felder ohne Platz }, … }
    Bars = function() return ns.Slots.Describe() end,
    -- Alle Aktionsplätze, die ezBars-Leisten zeigen: { [Platz] = Leistennummer }
    UsedSlots = function() return ns.Slots.UsedSlots() end,
    -- Knopf, der einen Aktionsplatz zeigt (oder nil)
    ButtonForSlot = function(slot) return ns.Bars and ns.Bars.ButtonForSlot(slot) or nil end,

    -- Leiste mit eigenen Knöpfen anmelden bzw. ändern → Kennung, Anker | nil, Grund
    RegisterBar = function(def) return ns.RegisterBar(def) end,
    -- Nur die Knöpfe einer angemeldeten Leiste ersetzen → true | nil, Grund
    SetBarButtons = function(id, buttons) return ns.SetBarButtons(id, buttons) end,
    -- Leiste abmelden → true | false
    UnregisterBar = function(id) return ns.UnregisterBar(id) end,
    -- Welche Standardanker ezBars abdeckt: { free = true, chatSide = true, chatTop = true, custom = true }.
    -- Je Fähigkeit eine Abfrage (BarAnchors().chatTop) – so merkt ein Anbieter, wenn ein Anker fehlt.
    BarAnchors = function() return ns.Anchors.Covered() end,
    -- Stand einer Leiste (ns.ExtraInfo) bzw. aller angemeldeten Leisten
    BarInfo = function(id) return ns.ExtraInfo(id) end,
    RegisteredBars = function()
        local list = {}
        for _, entry in ipairs(extraOrder) do list[#list + 1] = ns.ExtraInfo(entry.id) end
        return list
    end,
    -- Rahmen der Leiste (z. B. für eine Erklärblase des Anbieters); nil, solange sie nicht gebaut ist
    BarFrame = function(id) return ns.Bars and ns.Bars.ExtraFrame(id) or nil end,
    -- Unterseite der Leiste in den ezBars-Einstellungen öffnen → true | false
    OpenBarSettings = function(id) return ns.OpenExtraSettings ~= nil and ns.OpenExtraSettings(id) == true end,
}

---------------------------------------------------------------------------
-- Slash-Befehle und Addon-Knopf an der Minikarte
---------------------------------------------------------------------------

-- /ezbars baut das Gerüst (opts.slash: SLASH_EZBARS1, ns.HandleSlash, ns.PrintHelp mit L.CMD_HELP_OWN); es versteht
-- ohne Wort bzw. „optionen/options/einstellungen/config“ (Einstellungen), „status“, „hilfe/help“ und „zuruecksetzen“.
-- Hier nur die eigenen Wörter. Rückgabe true = erledigt.
function ns.SlashExtra(cmd)
    if cmd == "tasten" or cmd == "keys" or cmd == "tastenbelegung" or cmd == "bind" then
        ns.OpenKeybindings()
    elseif cmd == "verschieben" or cmd == "move" then
        if not ns.OpenMover() then ns.PrintHelp() end
    elseif cmd == "plaetze" or cmd == "plätze" or cmd == "slots" then
        ns.PrintFreeSlots()
    else
        return false
    end
    return true
end

-- Addon-Fach (TOC: AddonCompartmentFunc …): ezBars hat kein eigenes Fenster – jeder Klick öffnet die Einstellungen
-- (Entscheidung 5 vom 18.11.2026; Gesamtreview T18-3, T16-10). Tooltip und Befehlszeile baut ezCore. Blizzards
-- Tastaturbelegung (vorher Rechtsklick) bleibt als Knopf „Tasten belegen“ auf der Seite und als „/ezbars tasten“.
ezBars_OnAddonCompartmentClick, ezBars_OnAddonCompartmentEnter, ezBars_OnAddonCompartmentLeave =
    Core.CompartmentHandlers({ ns = ns, title = L.TITLE })
