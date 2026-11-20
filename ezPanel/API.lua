local _, ns = ...

--[[
    Schnittstelle für andere ez-Module: eigene Bausteine und Meldungen auf der Leiste (Vollprüfung V-077, V-089),
    dazu die älteren Auskünfte (Sperren, Reparatur). Diese Datei ist die eine Stelle, an der ns.API entsteht
    (Vollprüfung 14.11.2026, W-30) – was hier nicht steht, bietet ezPanel nicht an. Sie lädt nach allen Bausteinen
    (ezPanel.toc); Funktionen, die in ihrer eigenen Datei wohnen, werden hier nur eingetragen.

    Ein Modul fragt beim Einloggen (in seinem ns.OnReady – dann sind alle Addons geladen):

        local panel = ezCore.API("ezPanel")          -- nil, wenn ezPanel nicht läuft
        if panel and panel.AddWarning then … end     -- alte ezPanel-Fassungen haben die Funktionen nicht

    Meldungen (Baustein „Meldungen“, rote Zahl auf der Leiste):

        panel.AddWarning(key, name, fn, tip)   → true | false, Grund ("key", "name", "fn")
            key   eindeutige Kennung, am besten „ezBuff.missing“ (ersetzt eine frühere Anmeldung gleichen Namens)
            name  Anzeigename der Quelle (Tooltip der Meldungen, Menü „Quellen“, Einstellungen → ezPanel →
                  Meldungen). Der Nutzer kann jede Quelle an beiden Stellen einzeln abwählen (gespeichert im
                  ezPanel-Profil): dann zeigt ezPanel keine Zeile von ihr und ruft fn nicht auf
            fn()  → nil, ein Text oder eine Liste von Texten; läuft bei jedem Neuzeichnen (alle 5 Sekunden und
                    nach RefreshWarnings), also nichts Teures rechnen und nichts Gesperrtes zurückgeben
            tip   (auf Wunsch) ein Satz, was die Quelle meldet – Tooltip ihres Häkchens auf der Einstellungsseite;
                  ohne ihn nennt der Tooltip Name und Kennung
        panel.RemoveWarning(key)          → true, wenn es die Quelle gab
        panel.RefreshWarnings()           sofort neu zeichnen (wenn sich beim Modul etwas geändert hat)
        panel.Warnings()                  → { { source = Kennung, name = Quelle, text = … } } aller eingeschalteten
                                            Quellen, auch der Bausteine von ezPanel (nur lesen)

    Bausteine (stehen im Leistenmenü unter „Bausteine“ und lassen sich ziehen wie die eigenen):

        panel.RegisterBlock(def)          → def | nil, Grund ("def", "id", "text", "taken")
            def.id        eindeutige Kennung („ezCraft.cooldowns“); def.owner = Modulname (für Fehlermeldungen)
            def.name      Anzeigename; def.icon, def.label, def.tip (Tooltip in der Liste der Bausteine)
            def:GetText() Text auf der Leiste (nil blendet den Baustein vorübergehend aus) – Pflicht
            sonst alles wie bei den eigenen Bausteinen (Kopf von Blocks.lua): OnTooltip, OnClick, OnMenu, actions,
            events, interval, defaults, Warnings … Ab Werk ist ein fremder Baustein aus (defaults.enabled).
        panel.UpdateBlock(id)             Text neu berechnen (wenn sich beim Modul etwas geändert hat)
        panel.BlockEnabled(id)            → steht er auf der Leiste?

    Fehler in fn, GetText und den übrigen Rückrufen fängt ezPanel ab und meldet sie an einer Stelle
    (ns.BlockError in Blocks.lua) über ns.Error: Sie stehen in ezCores Fehlerliste unter „ezPanel“ mit Rückruf,
    Kennung und Modul („GetText ezCraft.cooldowns (ezCraft): …“); gleiche Meldungen zählt ezCore an einem Eintrag,
    Blizzards Fehleranzeige sieht nur die erste. Nach einem Fehler in fn bzw. GetText oder Warnings hält ezPanel
    die Quelle oder den Baustein an – kein weiterer Aufruf, auf der Leiste „?“, Hinweis im Tooltip. Wieder an:
    Menü des Bausteins „Wieder starten“ bzw. Menü „Meldungen“ → Quellen, Aus- und Einschalten des Bausteins,
    erneutes AddWarning mit derselben Kennung, oder /reload.

    Auskünfte (nur lesen; die Funktionen stehen in ihren Dateien):

        panel.Lockouts(charKey)           → Liste der aktiven Sperren eines Charakters (ohne Schlüssel: der gespielte):
                                            { name, diff, raid, size, done, total, resetAt, ext, worldBoss, bosses }.
                                            Weiterleitung auf ezCore.Lockouts.List (Lockouts.lua) – neue Abnehmer
                                            fragen gleich ezCore.Lockouts.List bzw. IsLocked
        panel.RecentInstances()           → drei Werte: Anzahl der Instanzen in der letzten Stunde (Account; ohne
                                            Besuch 0), Sekunden, bis die älteste herausfällt (ohne Besuch nil), und
                                            die Liste der Besuche { t, id, n, c, reset } – nur lesen
                                            (ezCore.Lockouts.Recent; Lockouts.lua)
        panel.RepairSettings()            → { autoRepair, guild, report, mixed, autoAnywhere } aus den gespeicherten
                                            Profilen des Reparatur-Bausteins, für die einmalige Übernahme in ezCores
                                            gemeinsamen Schaltersatz (Blocks/Repair.lua, Core.Junk.AdoptPanelRepair);
                                            weichen die Profile ab, sind autoRepair und guild aus und mixed = true (T4-6)
]]

local Core = ezCore
local API = {}
ns.API = API

---------------------------------------------------------------------------
-- Meldungen
---------------------------------------------------------------------------

ns.extraWarnings = {}        -- key → Quelle { id, key, name, external = true, Warnings = fn }
ns.extraWarningList = {}     -- dieselben in der Reihenfolge der Anmeldung

local function Text(value)
    value = Core.Plain(value)
    if type(value) == "string" and value ~= "" then return value end
    return nil
end

function API.AddWarning(key, name, fn, tip)
    key, name = Text(key), Text(name)
    if not key then return false, "key" end
    if not name then return false, "name" end
    if type(fn) ~= "function" then return false, "fn" end
    local source = ns.extraWarnings[key]
    if not source then
        source = { id = "ext:" .. key, key = key, external = true }
        ns.extraWarnings[key] = source
        ns.extraWarningList[#ns.extraWarningList + 1] = source
    end
    source.name = name
    source.tip = Text(tip)
    source.halted = nil   -- neue Anmeldung startet eine nach einem Fehler angehaltene Quelle neu (Blocks.lua)
    -- Dieselbe Form wie def:Warnings() der Bausteine: Liste von Texten oder nil.
    function source:Warnings()
        local result = fn()
        if Core.IsSecret(result) or result == nil then return nil end
        if type(result) == "table" then
            local list = {}
            for _, text in ipairs(result) do
                text = Text(text)
                if text then list[#list + 1] = text end
            end
            return list
        end
        local text = Text(result)
        return text and { text } or nil
    end
    if ns.AddAlertSetting then ns.AddAlertSetting(source) end   -- Häkchen unter Einstellungen → Meldungen (Options.lua)
    API.RefreshWarnings()
    return true
end

function API.RemoveWarning(key)
    local source = ns.extraWarnings[key]
    if not source then return false end
    ns.extraWarnings[key] = nil
    for i, entry in ipairs(ns.extraWarningList) do
        if entry == source then
            table.remove(ns.extraWarningList, i)
            break
        end
    end
    API.RefreshWarnings()
    return true
end

function API.RefreshWarnings()
    if ns.ready and ns.QueueUpdate then ns.QueueUpdate("alerts") end
end

function API.Warnings()
    local list = {}
    if not (ns.ready and ns.CollectWarnings) then return list end
    for _, w in ipairs(ns.CollectWarnings()) do
        list[#list + 1] = { source = w.def.key or w.def.id, name = w.def.name, text = w.text }
    end
    return list
end

---------------------------------------------------------------------------
-- Bausteine
---------------------------------------------------------------------------

function API.RegisterBlock(def)
    if type(def) ~= "table" then return nil, "def" end
    local id = Text(def.id)
    if not id then return nil, "id" end
    if type(def.GetText) ~= "function" then return nil, "text" end
    if ns.blocks[id] then return nil, "taken" end
    def.id = id
    def.key = Text(def.key) or id   -- Kennung in Fehlermeldungen und API.Warnings (wie bei AddWarning)
    def.external = Text(def.owner) or true
    def.name = Text(def.name) or id
    if type(def.defaults) ~= "table" then def.defaults = {} end
    if def.defaults.enabled == nil then def.defaults.enabled = false end
    ns.RegisterBlock(def)
    if ns.AddBlockSetting then ns.AddBlockSetting(def) end   -- Häkchen auf der Unterseite „Bausteine“ (Options.lua)
    -- Liefert der Baustein Meldungen, ist er auch eine Quelle: Häkchen auf der Unterseite „Meldungen“
    if ns.AddAlertSetting and type(def.Warnings) == "function" then ns.AddAlertSetting(def) end
    return def
end

function API.UpdateBlock(id)
    local def = ns.blocks[id]
    if not def then return false end
    ns.QueueUpdate(def)
    return true
end

function API.BlockEnabled(id)
    return ns.BlockEnabled(id)
end

---------------------------------------------------------------------------
-- Auskünfte: Sperren (Lockouts.lua), Reparatur-Einstellungen (Blocks/Repair.lua)
---------------------------------------------------------------------------

API.Lockouts = ns.Lockouts.List
API.RecentInstances = ns.Lockouts.RecentInstances
API.RepairSettings = ns.RepairSettings
