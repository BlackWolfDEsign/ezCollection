local _, ns = ...
local L = ns.L

--[[
    Profile (Titan-Abgleich): Aussehen der Leiste und Bausteine (an/aus, Anordnung, Optionen)
    je Charakter oder – wo das Spiel Spezialisierungen kennt – je Spezialisierung.

    Seit 1.5 über ezCores Gerüst (Core.NewProfiles, eines für ezBag und ezPanel): Liste, Wechsel,
    Zuordnung, Export/Import, Menü, Sichern beim Ausloggen, Wechsel mit der Spezialisierung und die
    allgemeinen Texte kommen von dort. ezPanel liefert nur, was ein Profil ist (Snapshot, Apply, Clean)
    und die Texte, die vom Inhalt der Leiste sprechen.

    Die Arbeitsdaten bleiben ezPanelDB.settings und ezPanelDB.blocks (alle Bausteine greifen über ns.S
    und def.cfg darauf zu). Beim Wechsel werden sie unter dem alten Namen gesichert und die Werte des
    neuen Profils in dieselben Tabellen übernommen – alle Verweise bleiben gültig.
    Gespeichert (Felder von ezCores Gerüst): ezPanelDB.profiles[name], activeProfile (nil = „default“),
    profileFor[charKey | "charKey#Gruppe"], specMode[charKey]. Die Felder bis 1.4 (profileChar,
    profileSpec, loadedProfile) werden beim ersten Start einmal übernommen und dann gelöscht.
    Export-Texte bis 1.4 (Felder oben im Text, Kennung „ezPanel.profile“) lassen sich weiter lesen.
    Seit Welle 7 (PANEL-09, V-087): Der Export-Text entsteht über ezCores Export-Filter ohne Charakter-Schlüssel und
    Fraktionsliste; eigene Befehle des Werkzeug-Bausteins aus einem fremden Text kommen erst nach einer Rückfrage ins
    Profil (Frage 1 a, entschieden 13.11.2026).

    Sichtbar: Einstellungen → ezPanel → „Profile“ (Auswahl, je Spezialisierung, Neu, Exportieren,
    Importieren, Löschen), zusätzlich Rechtsklick auf die Leiste → „Profil“.
    Alle bisherigen Profiles.*-Funktionen bleiben als Weiterleitung (Leitlinie 8).
]]

local Core = ezCore
local Profiles = {}
ns.Profiles = Profiles

local DEFAULT = "default"
local KIND, VERSION = "ezPanel.profile", 1

local function Copy(value)
    return Core.CopyTable(value)
end

-- Arbeitsdaten → Profil (Kopie).
local function Snapshot()
    return { settings = Copy(ns.db.settings), blocks = Copy(ns.db.blocks) }
end

-- Profil → Arbeitsdaten (Typen geprüft, Fehlendes aus dem Standard).
local function Apply(data)
    local src = type(data) == "table" and type(data.settings) == "table" and data.settings or {}
    for key, default in pairs(ns.DEFAULTS) do
        local value = src[key]
        if type(value) ~= type(default) then value = default end
        if ns.S[key] ~= value then ns.SetSetting(key, value) end
    end
    ns.ApplyBlockConfigs(type(data) == "table" and type(data.blocks) == "table" and data.blocks or {})
end

-- Import (der Text kann von irgendwoher kommen; Gesamtreview 18.11.2026, T6-7 – vorher kam jede Tabelle ungeprüft
-- ins Profil und nach ezPanelDB.blocks):
--   - Einstellungen nur mit Schlüsseln aus ns.DEFAULTS und gültigem Wert (Core.ValidSetting: Typ, Grenzen des Reglers,
--     Auswahl des Felds, kurze Texte)
--   - Bausteine nur mit Namen (Text bis ns.BLOCK_MAX_ID Bytes, ohne „|“ und Steuerzeichen) und den Optionen, die
--     ns.CleanBlockConfig (Blocks.lua) zulässt; noch nicht angemeldete höchstens ns.BLOCK_MAX_UNKNOWN (nach Namen)
-- Ausgeblendete Charaktere (cfg.hidden, Schlüssel „Name-Realm“) gelten nur für Charaktere, die es hier gibt:
-- Schlüssel aus einem fremden Export fallen weg (V-087).
local function Clean(data)
    if type(data) ~= "table" then return nil end
    local blocks = {}
    local chars = Core.Chars and Core.Chars() or {}
    local unknown = 0
    if type(data.blocks) == "table" then
        for _, id in ipairs(Core.SortedKeys(data.blocks)) do
            local known = type(id) == "string" and ns.blocks[id] ~= nil
            local cfg = type(id) == "string" and #id <= ns.BLOCK_MAX_ID and not id:find("[%c|]")
                and (known or unknown < ns.BLOCK_MAX_UNKNOWN) and ns.CleanBlockConfig(id, data.blocks[id]) or nil
            if cfg then
                if not known then unknown = unknown + 1 end
                if type(cfg.hidden) == "table" then
                    for key in pairs(cfg.hidden) do
                        if chars[key] == nil then cfg.hidden[key] = nil end
                    end
                end
                blocks[id] = cfg
            end
        end
    end
    local settings = {}
    if type(data.settings) == "table" then
        for key in pairs(ns.DEFAULTS) do
            local value = Core.ValidSetting(ns, key, data.settings[key])
            if value ~= nil then settings[key] = value end
        end
    end
    -- älterer Export ohne tipAlts: den Stand der fünf Bausteine übernehmen (21.11.2026; CleanBlockConfig verwirft cfg.alts)
    if settings.tipAlts == nil then settings.tipAlts = ns.TipAltsFrom(data.blocks) end
    return { settings = settings, blocks = blocks }
end
Profiles.Clean = Clean

-- Vergessener Twink (ezCore: Core.ForgetChar, Nachricht CHAR_FORGOTTEN; Gesamtreview 18.11.2026, Nachsuche zu T4-2):
-- Sein Schlüssel fällt aus cfg.hidden jedes Bausteins (Gold, Charaktere …), in den Arbeitsdaten und in jedem
-- gespeicherten Profil – sonst wäre er nach einem neuen Login sofort wieder ausgeblendet. Den angemeldeten Charakter
-- vergisst ezCore nie; ein Fehlaufruf mit dem eigenen Schlüssel ändert nichts. → Zahl gestrichener Einträge.
function Profiles.ForgetChar(key)
    local db = ns.db
    if Core.IsSecret(key) or type(key) ~= "string" or key == "" or key == ns.charKey or type(db) ~= "table" then return 0 end
    local gone = 0
    local function Drop(blocks)
        if type(blocks) ~= "table" then return end
        for _, cfg in pairs(blocks) do
            if type(cfg) == "table" and type(cfg.hidden) == "table" and cfg.hidden[key] ~= nil then
                cfg.hidden[key] = nil
                gone = gone + 1
            end
        end
    end
    Drop(db.blocks)
    for _, profile in pairs(type(db.profiles) == "table" and db.profiles or {}) do
        if type(profile) == "table" then Drop(profile.blocks) end
    end
    return gone
end

--[[
    Export-Filter (V-087, PANEL-09; ezCores Angabe export = fn(kopie) → daten): Was nur hier gilt, kommt nicht in den
    Text – Charakter-Schlüssel („Name-Realm“ in cfg.hidden jedes Bausteins, etwa Gold und Charaktere) und die alte
    Fraktionsliste des Ruf-Bausteins (reputation.known; die bekannten Fraktionen merkt seit Welle 7 ezCore je Charakter).
    Das gespeicherte Profil bleibt vollständig (ezCore gibt dem Filter eine Kopie). Eigene Befehle des Werkzeug-
    Bausteins bleiben im Text (Frage 1 a, entschieden 13.11.2026); beim Import fragt ezPanel nach (ImportClean unten).
]]
local PERSONAL = { hidden = true }               -- in jedem Baustein: Schlüssel sind Charakternamen
local PERSONAL_IN = { reputation = { known = true } }

local function ExportFilter(data)
    if type(data) ~= "table" or type(data.blocks) ~= "table" then return data end
    for id, cfg in pairs(data.blocks) do
        if type(cfg) == "table" then
            for key in pairs(PERSONAL) do cfg[key] = nil end
            for key in pairs(PERSONAL_IN[id] or {}) do cfg[key] = nil end
        end
    end
    return data
end
Profiles.ExportFilter = ExportFilter

-- Eigene Befehle, die es hier schon gibt (Arbeitsdaten und alle gespeicherten Profile): → Menge.
local function OwnCommands()
    local own = {}
    local function Add(blocks)
        local tools = type(blocks) == "table" and blocks.tools
        local list = type(tools) == "table" and tools.commands
        if type(list) ~= "table" then return end
        for _, cmd in ipairs(list) do
            if type(cmd) == "string" then own[cmd] = true end
        end
    end
    local db = ns.db
    if type(db) ~= "table" then return own end
    Add(db.blocks)
    for _, profile in pairs(type(db.profiles) == "table" and db.profiles or {}) do
        if type(profile) == "table" then Add(profile.blocks) end
    end
    return own
end

local pendingCommands   -- Befehle aus dem letzten Import, die erst nach der Rückfrage ins Profil kommen

-- Import (nach Clean): Eigene Befehle, die es hier noch nicht gibt, kommen erst nach einer Rückfrage ins neue Profil
-- (Frage 1 a, entschieden 13.11.2026). Ein Befehl läuft per Klick (Blocks/Tools.lua); ein
-- fremder Text soll keinen unbemerkt mitbringen. Befehle, die es hier schon gibt (eigener Export), fragt ezPanel nicht.
local function ImportClean(data, v)
    local cleaned = Clean(data, v)
    if not cleaned then return nil end
    -- Eine Fraktionsliste aus einem fremden (alten) Text gehört nicht in dieses Profil: ezCore übernähme sie sonst beim
    -- ersten Anmelden eines Charakters als dessen bekannte Fraktionen (Factions.MigrateKnown liest alle Profile).
    for id, keys in pairs(PERSONAL_IN) do
        local cfg = cleaned.blocks[id]
        if type(cfg) == "table" then
            for key in pairs(keys) do cfg[key] = nil end
        end
    end
    local tools = cleaned.blocks.tools
    local list = type(tools) == "table" and tools.commands
    if type(list) ~= "table" then return cleaned end
    local own, keep, ask = OwnCommands(), {}, {}
    for _, cmd in ipairs(list) do
        if type(cmd) == "string" and cmd:match("^/%S") then
            if own[cmd] then keep[#keep + 1] = cmd else ask[#ask + 1] = cmd end
        end
    end
    tools.commands = keep
    pendingCommands = #ask > 0 and ask or nil
    -- Nach dem Import fragen: dann ist das neue Profil angelegt und aktiv (P.Import läuft danach zu Ende).
    if pendingCommands then C_Timer.After(0, function() Profiles.AskImportedCommands() end) end
    return cleaned
end
Profiles.ImportClean = ImportClean

local P = Core.NewProfiles({
    owner = "ezPanel",
    db = function() return ns.db end,
    snapshot = Snapshot,
    apply = Apply,
    clean = ImportClean,
    export = ExportFilter,
    kind = KIND, version = VERSION, wrap = false, default = DEFAULT,
    perChar = true,
    scopes = { spec = true },
    texts = L, print = ns.Print, hint = L.PROFILE_HINT,
})
Profiles.P = P

-- Befehle in ein Profil übernehmen (das aktive: in die Arbeitsdaten des Werkzeug-Bausteins). → Zahl neu übernommener.
function Profiles.AddCommands(name, list)
    if type(list) ~= "table" then return 0 end
    local target
    if name == P.Active() then
        local def = ns.blocks and ns.blocks.tools
        target = def and def.cfg
    else
        local profile = type(ns.db.profiles) == "table" and ns.db.profiles[name]
        if type(profile) ~= "table" then return 0 end
        if type(profile.blocks) ~= "table" then profile.blocks = {} end
        if type(profile.blocks.tools) ~= "table" then profile.blocks.tools = {} end
        target = profile.blocks.tools
    end
    if type(target) ~= "table" then return 0 end
    if type(target.commands) ~= "table" then target.commands = {} end
    local have, n = {}, 0
    for _, cmd in ipairs(target.commands) do have[cmd] = true end
    for _, cmd in ipairs(list) do
        if type(cmd) == "string" and not have[cmd] then
            target.commands[#target.commands + 1] = cmd
            have[cmd] = true
            n = n + 1
        end
    end
    if name == P.Active() then
        P.Save()
        if ns.blocks.tools and ns.QueueUpdate then ns.QueueUpdate(ns.blocks.tools) end
    end
    ns.Print(L.PROFILE_COMMANDS_ADDED:format(n, P.Label(name)))
    return n
end

-- Rückfrage nach einem Import (Core.Confirm mit der Liste der Befehle). → true, wenn gefragt wurde.
-- Je Rückfrage höchstens SHOW_COMMANDS Befehle; „Ja“ übernimmt genau die gezeigten, für den Rest folgt die nächste
-- Rückfrage. So kommt kein Befehl ins Profil, den der Nutzer nicht gesehen hat. „Nein“ lässt diese und alle weiteren weg.
local SHOW_COMMANDS = 12
local function AskCommands(name, list, first)
    local last = math.min(#list, first + SHOW_COMMANDS - 1)
    local batch, shown = {}, {}
    for i = first, last do
        batch[#batch + 1] = list[i]
        -- wörtlich zeigen (Blizzards Dialog deutet „|“-Codes sonst aus und versteckt so Teile des Befehls), Befehle mit
        -- Lua-Code oder Konsolenbefehlen rot gekennzeichnet (Gesamtreview 18.11.2026, T6-6)
        shown[#shown + 1] = Core.PreviewCommand(list[i])
    end
    local rest = #list - last
    -- „… und 3 weitere (zeigt die nächste Rückfrage)“: der Rest aus ezCore (Core.More), dahinter der eigene Zusatz
    if rest > 0 then shown[#shown + 1] = Core.More(rest) .. " " .. L.PROFILE_COMMANDS_NEXT end
    Core.Confirm(L.PROFILE_COMMANDS_ASK:format(P.Label(name), table.concat(shown, "\n")), function()
        Profiles.AddCommands(name, batch)
        -- die nächste Rückfrage erst, wenn dieser Dialog zu ist
        if rest > 0 then C_Timer.After(0, function() AskCommands(name, list, last + 1) end) end
    end)
end

function Profiles.AskImportedCommands()
    local list = pendingCommands
    pendingCommands = nil
    if type(list) ~= "table" or #list == 0 then return false end
    AskCommands(P.Active(), list, 1)
    return true
end

---------------------------------------------------------------------------
-- Einmalige Übernahme der Felder bis 1.4
---------------------------------------------------------------------------

-- profileChar → profileFor[charKey], profileSpec → profileFor["charKey#Gruppe"],
-- loadedProfile → activeProfile („default“ als nil). Danach sind die alten Felder weg.
function Profiles.MigrateOld()
    local db = ns.db
    if type(db) ~= "table" then return false end
    local moved = false
    if type(db.profileFor) ~= "table" then db.profileFor = {} end
    for _, field in ipairs({ "profileChar", "profileSpec" }) do
        local old = db[field]
        if old ~= nil then
            if type(old) == "table" then
                for key, name in pairs(old) do
                    if type(key) == "string" and type(name) == "string" and db.profileFor[key] == nil then
                        db.profileFor[key] = name
                    end
                end
            end
            db[field] = nil
            moved = true
        end
    end
    if db.loadedProfile ~= nil then
        local name = db.loadedProfile
        if db.activeProfile == nil and type(name) == "string" and name ~= "" and name ~= DEFAULT then
            db.activeProfile = name
        end
        db.loadedProfile = nil
        moved = true
    end
    return moved
end

---------------------------------------------------------------------------
-- Weiterleitungen (die bisherigen Funktionen, Leitlinie 8)
---------------------------------------------------------------------------

-- „default“ heißt „Standard“ bzw. „Default“.
function Profiles.DisplayName(name) return P.Label(name) end
-- Benachrichtigung nach jedem Wechsel (Einstellungsseite zieht die Auswahl nach).
function Profiles.OnChange(fn) return P.OnChange(fn) end
function Profiles.SpecGroup() return P.SpecGroup() end
function Profiles.SpecMode() return P.SpecMode() end
function Profiles.Active() return P.Active() end
-- Alle Profilnamen, „Standard“ zuerst.
function Profiles.List() return P.Names() end
-- Profil, das für den gespielten Charakter (und seine Spezialisierung) gilt.
function Profiles.Wanted() return P.Wanted() end
function Profiles.Save() return P.Save() end
-- Zu einem Profil wechseln (ein neues entsteht als Kopie der aktuellen Einstellungen).
function Profiles.Switch(name, quiet) return P.Switch(name, quiet) end
-- Profil für diesen Charakter (bzw. diese Spezialisierung) wählen und wechseln.
function Profiles.Use(name, quiet) return P.Use(name, quiet) end
-- Je Spezialisierung ein eigenes Profil an/aus (gilt für den gespielten Charakter).
function Profiles.SetSpecMode(on) return P.SetSpecMode(on) end
-- Neues Profil aus den aktuellen Einstellungen → Name (gibt es ihn schon, mit Zusatz).
function Profiles.New(name) return P.Create(name) end
-- Löschen; wer es nutzt, bekommt wieder „Standard“.
function Profiles.Delete(name) return P.Delete(name) end
function Profiles.Export() return P.Export() end
-- Text → neues Profil (Name aus dem Text, bei Gleichheit mit Zusatz). Rückgabe: Name oder nil, Grund.
function Profiles.Import(text) return P.Import(text) end
function Profiles.ShowExport() return P.ShowExport() end
function Profiles.AskImport() return P.ShowImport() end
function Profiles.AskNew() return P.AskNew() end
function Profiles.AskDelete(name) return P.AskDelete(name) end
-- Menü (Rechtsklick auf die Leiste → Profil): Auswahl, Neu, je Spezialisierung, Löschen, Export/Import.
function Profiles.FillMenu(root) return P.FillMenu(root) end

---------------------------------------------------------------------------
-- Start: alte Felder übernehmen, Profil des Charakters laden (nach dem Einrichten der Bausteine).
-- Beim Ausloggen sichert ezCores Gerüst, mit der Spezialisierung wechselt es selbst.
---------------------------------------------------------------------------

ns.OnReady(function()
    Profiles.MigrateOld()
    P.Load(true)
end)
