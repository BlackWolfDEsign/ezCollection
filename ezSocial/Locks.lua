local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Gesperrte Instanzen markieren (Vollprüfung V-081): in „Durchsuchen“ (GroupFinder.lua), im Auswahlmenü
    „Aktivität“ (GroupFinder.lua) und im Reiter „Aus dem Chat“ (ChatTab.lua). Immer an (bis 19.11.2026 Schalter finderLocked).

    Die Sperren führt ezCore (Core.Lockouts – dieselben Daten wie Blizzards Schlachtzugsinformationen, hier nur die
    des gespielten Charakters); welche Instanz zu einer Aktivität gehört, sagt die Dungeon-Tabelle von ezCore
    (Core.Dungeons, Schlüssel = Instanz-ID aus der Aktivität). ezSocial hat keine eigene Liste, fragt den Server
    nicht selbst und zeichnet neu, wenn ezCore LOCKOUTS_CHANGED meldet – auch, wenn eine Sperre abläuft: den Ablauf
    meldet ezCore selbst (LOCKOUTS_CHANGED mit Grund "expired", Wecker Lockouts.ArmExpiry, Fähigkeit lockoutExpiry;
    Welle 23). Bis dahin stellte ezSocial dafür einen eigenen Wecker (Locks.Arm), der damit entfallen ist.

    Blizzards Sperrliste nennt die Instanz nur beim Namen. Verglichen wird deshalb mit allen Namen, unter denen
    die Instanz bekannt ist: Blizzards Name der Instanz-Karte (GetRealZoneText(Instanz-ID) – derselbe Name wie in
    den Schlachtzugsinformationen), der Name aus der Dungeon-Tabelle und die Namen der Flügel. Passt keiner,
    bleibt die Markierung weg (wie bisher). Nennt die Aktivität eine Schwierigkeit, zählt nur eine Sperre
    derselben Schwierigkeit (oder eine ohne Angabe).
]]

local Locks = {}
ns.Locks = Locks

local MARK_RGB = { 1, 0.3, 0.3 }
Locks.RGB = MARK_RGB

local function Text(value)
    value = Core.Plain(value)
    if type(value) == "string" and value ~= "" then return value end
    return nil
end

local function Service()
    local service = Core.Lockouts
    if type(service) == "table" and type(service.IsLocked) == "function" and type(service.List) == "function" then
        return service
    end
    return nil
end

-- ezCore führt die Sperren (immer an seit der Prüfung der Einstellungen vom 19.11.2026, Nr. 26: „gesperrt“ schützt vor
-- vergeblichem Anschreiben; vorher Schalter finderLocked).
function Locks.Enabled()
    return Service() ~= nil
end

-- Hat der gespielte Charakter überhaupt eine laufende Sperre? (Meist nicht – dann ist jede Suche unnötig.)
function Locks.Any()
    return Locks.Enabled() and #Service().List() > 0
end

-- Eintrag der Dungeon-Tabelle zu einer Kennung (Instanz-ID), sonst nil.
local function DungeonEntry(key)
    if type(key) == "table" then return key end
    if key == nil or key == false then return nil end
    local ok, entry = pcall(Core.Dungeons.Get, key)
    if ok and type(entry) == "table" then return entry end
    return nil
end

-- Namen, unter denen Blizzards Sperrliste die Instanz eines Eintrags führen kann (ohne Doppelte).
function Locks.Names(entry)
    local names, seen = {}, {}
    local function Add(name)
        name = Text(name)
        local low = name and name:lower()
        if low and not seen[low] then
            seen[low] = true
            names[#names + 1] = name
        end
    end
    if type(entry) ~= "table" then return names end
    local mapID = Core.Num(entry.mapID)
    if mapID and mapID > 0 then Add(Core.Call(rawget(_G, "GetRealZoneText"), mapID)) end
    Add(entry.name)
    for _, wing in ipairs(type(entry.wings) == "table" and entry.wings or {}) do
        if type(wing) == "table" then
            Add(wing.name)
            Add(wing.short)
        end
    end
    return names
end

-- Sperre für einen Namen; mit Schwierigkeit zählt nur dieselbe oder eine Sperre ohne Angabe.
local function Find(service, name, diff)
    if diff then
        local lock = service.IsLocked(name, nil, diff)
        if lock then return lock end
        lock = service.IsLocked(name)
        if lock and lock.diffId == nil then return lock end
        return nil
    end
    return service.IsLocked(name)
end

-- Sperre des gespielten Charakters für einen Dungeon (Eintrag der Dungeon-Tabelle oder dessen Kennung), sonst nil.
-- diff: Schwierigkeit der Aktivität (Blizzards Kennung), wenn sie eine nennt.
function Locks.OfDungeon(entry, diff)
    if not Locks.Any() then return nil end
    local service = Service()
    entry = DungeonEntry(entry)
    if not entry then return nil end
    for _, name in ipairs(Locks.Names(entry)) do
        local lock = Find(service, name, diff)
        if lock then return lock end
    end
    return nil
end

-- Sperre für eine Aktivität der Gruppensuche (Kennung oder Info-Tabelle von C_LFGList.GetActivityInfoTable).
function Locks.OfActivity(activity)
    if not Locks.Any() then return nil end
    local info = activity
    if type(info) ~= "table" then
        info = C_LFGList and Core.Call(C_LFGList.GetActivityInfoTable, activity) or nil
    end
    if type(info) ~= "table" then return nil end
    local mapID = Core.Num(info.mapID)
    if not (mapID and mapID > 0) then return nil end
    local diff = Core.Num(info.difficultyID)
    if diff and diff <= 0 then diff = nil end
    -- Instanz nicht in der Dungeon-Tabelle: mit den Namen der Aktivität selbst vergleichen
    local entry = DungeonEntry(mapID)
        or { mapID = mapID, name = info.fullName, wings = { { name = info.fullName, short = info.shortName } } }
    return Locks.OfDungeon(entry, diff)
end

local function Collect(list, lookup)
    local locks, seen = {}, {}
    for _, item in ipairs(type(list) == "table" and list or {}) do
        local lock = lookup(item)
        if lock and not seen[lock] then
            seen[lock] = true
            locks[#locks + 1] = lock
        end
    end
    return locks
end

-- Sperren zu mehreren Aktivitäten bzw. Dungeons (jede Sperre einmal); leere Liste ohne Sperre.
function Locks.OfActivities(activityIDs) return Collect(activityIDs, Locks.OfActivity) end
function Locks.OfDungeons(keys) return Collect(keys, Locks.OfDungeon) end

-- Der Zusatz hinter einem Namen: „(gesperrt)“ in Rot.
function Locks.Mark()
    return Core.ColorCode(MARK_RGB[1], MARK_RGB[2], MARK_RGB[3]) .. "(" .. L.LOCKED .. ")|r"
end

-- Steht der Zusatz schon im Text? (Ein Menüeintrag wird bei jedem Öffnen neu beschriftet.)
function Locks.HasMark(text)
    return type(text) == "string" and text:find("(" .. L.LOCKED .. ")", 1, true) ~= nil
end

-- Sekunden bis zum Zurücksetzen (0, wenn abgelaufen oder unbekannt).
function Locks.Left(lock, now)
    local resetAt = type(lock) == "table" and Core.Num(lock.resetAt) or nil
    if not resetAt then return 0 end
    return math.max(0, resetAt - (now or time()))
end

-- „Gesperrt: Der Geschmolzene Kern (40 Spieler) – noch 2 Tage 3 Std.“
function Locks.Line(lock, now)
    local name = tostring(lock.name)
    local diff = Text(lock.diff)
    if diff then name = L.LOCKED_NAME_DIFF:format(name, diff) end
    return L.LOCKED_LINE:format(name, Core.TimeLeft(Locks.Left(lock, now)))
end

-- Die Sperren aus einer Liste, die noch laufen.
local function Running(locks, now)
    local running = {}
    for _, lock in ipairs(type(locks) == "table" and locks or {}) do
        if type(lock) == "table" and Locks.Left(lock, now) > 0 then running[#running + 1] = lock end
    end
    return running
end

local function Lines(tooltip, running, now)
    for _, lock in ipairs(running) do
        tooltip:AddLine(Locks.Line(lock, now), MARK_RGB[1], MARK_RGB[2], MARK_RGB[3], true)
        local done, total = Core.Num(lock.done), Core.Num(lock.total)
        if done and total and total > 0 then
            Core.TipLine(tooltip, L.LOCKED_BOSSES:format(done, total), "highlight")
        end
    end
    Core.TipLine(tooltip, L.LOCKED_SOURCE, "hint", true)   -- Quelle grau (Rollen, Gesamtreview T9-6)
end

-- Zeilen in einen Tooltip, der schon einen Titel hat (Nachricht im Reiter „Aus dem Chat“): je Sperre Name und
-- Restzeit (dazu besiegte Bosse), am Ende einmal die Quelle. → false, wenn keine der Sperren mehr läuft
-- (dann kommt keine Zeile dazu).
function Locks.AddLines(tooltip, locks)
    local now = time()
    local running = Running(locks, now)
    if #running == 0 then return false end
    Lines(tooltip, running, now)
    return true
end

-- Ein ganzer Tooltip: Titel, dann die Zeilen wie Locks.AddLines.
-- → false, wenn keine der Sperren mehr läuft (dann bleibt der Tooltip leer).
function Locks.FillTooltip(tooltip, locks, title)
    local now = time()
    local running = Running(locks, now)
    if #running == 0 then return false end
    Core.TipLine(tooltip, Text(title) or L.LOCKED_TITLE, "highlight")
    Lines(tooltip, running, now)
    return true
end

-- Alles neu zeichnen, was Sperren zeigt: die Liste „Durchsuchen“ und der Reiter „Aus dem Chat“ (das Menü
-- „Aktivität“ baut Blizzard bei jedem Öffnen neu).
function Locks.Redraw()
    if ns.Finder then ns.Finder.Refresh() end
    if ns.ChatTab then ns.ChatTab.Refresh() end
end

---------------------------------------------------------------------------
-- Neu zeichnen, wenn ezCore eine Änderung meldet
---------------------------------------------------------------------------

-- LOCKOUTS_CHANGED (charKey, grund): neu gelesen (grund nil) oder eine Sperre abgelaufen (grund "expired", ezCore
-- meldet das selbst). Markiert wird nur, was den gespielten Charakter sperrt – läuft die Sperre eines Twinks ab,
-- bleibt alles, wie es ist. → true, wenn neu gezeichnet wurde.
function Locks.OnChanged(charKey, reason)
    if reason == "expired" and charKey ~= nil and charKey ~= Core.charKey then return false end
    ns.Try("Locks", Locks.Redraw)
    return true
end

Core.Listen("LOCKOUTS_CHANGED", function(charKey, reason) Locks.OnChanged(charKey, reason) end, "ezSocial")

-- Einen Schalter für die Sperren gibt es nicht mehr (Prüfung der Einstellungen vom 19.11.2026); neu gezeichnet wird
-- bei LOCKOUTS_CHANGED (oben).
