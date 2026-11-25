local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Blizzards „Menü“ (Rechtsklick) und „Ziel“ (Linksklick) auf den Einheiten-, Gruppen- und Raidrahmen (Spieltest des
    Nutzers vom 24.11.2026, wörtlich „ich kann nicht das menü beim gruppenmitglied oder mir aufrufen“). Beides gibt es nur,
    solange Blizzards Klick-Zauber-Profil es nennt (Grund und Quelle: Core.ClickBindings.Interactions). ezHeals Vorlagen
    lassen blanken Links- und Rechtsklick frei (T.RESERVED); Blizzards Fenster, ein geladenes Profil oder ein anderes Addon
    können sie trotzdem belegen – ezHeal sagt es dann einmal je Charakter und Lage im Chat, nennt es im Status und bietet
    „Menü und Ziel zurückholen“ an: Menü des Knopfs „Vorlagen“ an Blizzards Fenster „Klick-Zauber“ und Einstellungsseite,
    Abschnitt „Klick-Belegung“. Nie von selbst: Wer einen Zauber auf den Rechtsklick gelegt hat, soll ihn behalten.
    Geschrieben wird nach einer Rückfrage, die nennt, was weicht, nur außerhalb des Kampfes; ezCore sichert vorher, „Zurück“
    holt die alte Belegung.
]]
local M = {}
ns.MenuClick = M

M.DELAY = 8     -- Sekunden nach dem Anmelden bis zum Blick auf die Belegung (der Client lädt sein Profil nach)

local function CB()
    local cb = Core.ClickBindings
    if type(cb) ~= "table" or type(cb.Interactions) ~= "function" or not cb.Available() then return nil end
    return cb
end

-- Lage von „Ziel“ und „Menü“ → Liste (Core.ClickBindings.Interactions) | nil (nicht oder nicht ganz lesbar), dazu die Belegung
function M.State()
    local cb = CB()
    if not cb then return nil end
    local list, complete = cb.List()
    if type(list) ~= "table" or not complete then return nil end
    return cb.Interactions(list), list
end

-- Was liegt auf der Taste? → „Blitzheilung“ | „frei“
local function OnText(entry)
    if not entry then return L.MENUCLICK_FREE end
    return ns.Templates.Describe(entry)
end

-- Eine Zeile je Interaktion. all: auch, was am Platz liegt. → Liste
function M.Lines(states, all)
    local T, lines = ns.Templates, {}
    for _, info in ipairs(states or {}) do
        local name, key = T.ActionText(info.action), T.KeyText(info.button, "")
        if info.state == "missing" then
            lines[#lines + 1] = L.MENUCLICK_MISSING:format(name, key, OnText(info.on))
        elseif info.state == "moved" then
            local at = T.KeyText(info.entry.button, info.entry.modifiers)
            lines[#lines + 1] = L.MENUCLICK_MOVED:format(name, at, key, OnText(info.on))
        elseif all then
            lines[#lines + 1] = L.MENUCLICK_OK:format(name, key)
        end
    end
    return lines
end

-- Fehlt „Ziel“ oder „Menü“ ganz? (Verlegt ist eine Wahl des Spielers.) → Kennung der Lage | nil. Ohne Zauber-ID: „Ränge
-- aktualisieren“ tauscht nur sie, der Name bleibt (sonst dieselbe Meldung je Rang; Review 24.11.2026).
local function Signature(states)
    local parts = {}
    for _, info in ipairs(states or {}) do
        if info.state == "missing" then
            parts[#parts + 1] = info.action .. "=" .. (info.on and (tostring(info.on.kind) .. ":" .. tostring(OnText(info.on))) or "-")
        end
    end
    return #parts > 0 and table.concat(parts, " ") or nil
end

-- Schon gesagte Lagen dieses Charakters { [Kennung] = true } – sie bleiben gemerkt, auch wenn zwischendurch alles am Platz
-- war (Wechsel der Talentgruppe, „Zurückholen“ und „Zurück“)
local function Told()
    local db, key = ns.db, ns.charKey or Core.charKey
    if type(db) ~= "table" or type(key) ~= "string" then return nil end
    if type(db.menuClick) ~= "table" then db.menuClick = {} end
    if type(db.menuClick[key]) ~= "table" then db.menuClick[key] = {} end
    return db.menuClick[key]
end

-- Vergisst ezCore einen Charakter, vergisst ezHeal seine Meldung mit (Core.lua, CHAR_FORGOTTEN)
function M.Forget(key)
    local db = ns.db
    if type(db) == "table" and type(db.menuClick) == "table" and key then db.menuClick[key] = nil end
end

-- Einmal je Charakter und Lage sagen. Leere Belegung (Client hat sein Profil noch nicht geladen) und ein fremdes Addon fürs
-- Klick-Zaubern (Leitlinie 9): kein Wort. → true, wenn eine Zeile kam
function M.Say()
    if ns.ClickCaster() then return false end
    local states, list = M.State()
    if not states or #list == 0 then return false end
    local signature = Signature(states)
    local told = signature and Told() or nil
    if not told or told[signature] then return false end
    told[signature] = true
    ns.Print(L.MENUCLICK_SAY:format(table.concat(M.Lines(states), " "), L.MENU_MENUCLICK, ns.MenuClickSettingPath()))
    return true
end

function ns.MenuClickSettingPath()
    return Core.SettingsPathText(ADDON, "OPT_HEADER_BINDINGS", "OPT_MENUCLICK", L)
end

-- Zeile für den Status | nil (nicht lesbar)
function M.StatusLine()
    local states = M.State()
    if not states or #states == 0 then return nil end
    return table.concat(M.Lines(states, true), " ")
end

-- Zurückholen ohne Rückfrage → true, Anzahl | true, "same" | false, Grund ("missing", "combat", "unreadable", …)
function M.Apply()
    local cb = CB()
    if not (cb and cb.Writable()) then return false, "missing" end
    if Core.InCombat() then return false, "combat" end
    local states, list = M.State()
    if not states then return false, "unreadable" end
    local new, count = cb.RestoreInteractions(list)
    if count == 0 then return true, "same" end
    local ok, reason = cb.Set(new, { owner = ADDON, keepDefaults = false })
    if not ok then return false, reason end
    if reason ~= "same" then ns.Templates.DefaultsRestored() end
    -- die behobene Lage kennt der Spieler jetzt: „Zurück“ meldet sie nicht noch einmal
    local signature = Signature(states)
    local told = signature and Told() or nil
    if told then told[signature] = true end
    return true, reason == "same" and "same" or count
end

-- Knopf und Menüeintrag: was fehlt, mit Rückfrage zurückholen; fehlt nichts, sagt es der Chat. → true, wenn gefragt wurde
function M.Ask()
    if Core.InCombat() then
        ns.CombatNotice(L.APPLY_COMBAT_WHAT)
        return false
    end
    local cb = CB()
    if not (cb and cb.Writable()) then
        ns.Print(L.ERR_missing)
        return false
    end
    local states, list = M.State()
    if not states then
        ns.Print(L.ERR_unreadable)
        return false
    end
    local _, count = cb.RestoreInteractions(list)
    if count == 0 then
        ns.Print(L.MENUCLICK_FINE:format(table.concat(M.Lines(states, true), " ")))
        return false
    end
    Core.Confirm(L.ASK_MENUCLICK:format(table.concat(M.Lines(states), "\n")), function()
        local ok, reason = M.Apply()
        ns.Print(ok and L.MENUCLICK_DONE or ns.Explain(reason))
    end)
    return true
end

ns.OnReady(function()
    C_Timer.After(M.DELAY, function() ns.Try("Menü per Klick", M.Say) end)
    local cb = CB()
    -- nach jedem Schreiben über ezCore (Profil geladen, „Zurück“, Ränge): fehlt jetzt etwas, einmal sagen
    if cb and type(cb.OnChange) == "function" then
        cb.OnChange(function(ok) if ok then ns.Try("Menü per Klick", M.Say) end end)
    end
end)
