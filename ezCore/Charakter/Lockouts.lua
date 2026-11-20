local _, ns = ...
local Core = ezCore

--[[
    Instanz- und Raidsperren aller Charaktere und „Instanzen der letzten Stunde“ – als Dienst in ezCore
    (Vollprüfung V-079, V-081; vorher ezPanel/Lockouts.lua, dort nur für den Charaktere-Baustein erreichbar).

    Erfasst wird mit denselben Funktionen wie Blizzards Schlachtzugsinformationen (GetSavedInstanceInfo,
    GetSavedWorldBossInfo) für den gespielten Charakter; abgelegt in seinem Datensatz
    (ezCoreDB.chars[key].lockouts, dasselbe Feld und dieselben Einträge wie bisher von ezPanel). Die Rücksetzzeit
    steht als Zeitpunkt darin – abgelaufene Sperren verschwinden so auch bei Twinks, die nicht eingeloggt sind.

      Lockouts.List(charKey)     → aktive Sperren eines Charakters (ohne Schlüssel: der gespielte), nur lesen:
                                   { name, diff, diffId, raid, size, done, total, resetAt, ext, worldBoss, bosses = { { n, k } } }
      Lockouts.Active(c)         → dasselbe für einen Charakter-Datensatz
      Lockouts.Total(filter)     → Zahl aller aktiven Sperren der Charaktere, die filter(c, key) auswählt
      Lockouts.ByInstance(filter)→ nach Instanz gebündelt: { { name, diff, size, raid, worldBoss, resetAt,
                                   chars = { { key, c, lock, isMe } } } } – Schlachtzüge, Dungeons, Weltbosse
      Lockouts.IsLocked(name, charKey) → Sperre dieses Charakters für die Instanz (Name wie bei Blizzard) oder nil
      Lockouts.Recent()          → Anzahl der in der letzten Stunde betretenen Instanzen (ganzer Account),
                                   Sekunden bis die älteste herausfällt (nil bei 0), Liste { t, id, n, c, reset }
      Lockouts.Scan()            → liest neu (true); Lockouts.Request() fragt den Server (Antwort: UPDATE_INSTANCE_INFO)
      Lockouts.NextExpiry()      → Sekunden bis zur nächsten ablaufenden Sperre aller Charaktere, charKey, Sperre
                                   (nil ohne aktive Sperre) – Welle 23c, A51
      Nachrichten: LOCKOUTS_CHANGED (charKey, grund), INSTANCES_CHANGED (anzahl). grund = "expired", wenn der Dienst
                   den Ablauf einer Sperre selbst meldet (Welle 23c, A51: ein Wecker je nächster Ablauf, höchstens
                   Lockouts.EXPIRY_MAX Sekunden bis zur nächsten Prüfung) – vorher stellte jedes Modul einen eigenen
                   Wecker (ezSocial Locks.Arm). Sonst nil (neu gelesen).

    „Instanzen der letzten Stunde“ liegen in ezCoreDB.instances (vorher ezPanelDB.instances, einmal übernommen):
    Wer dieselbe Instanz erneut betritt (Tod, /reload), zählt nicht doppelt; nach „… wurde zurückgesetzt“ zählt der
    nächste Besuch neu. Nur Daten – die Anzeige bleibt Sache der Module (ezPanel Charaktere-Baustein).
]]

local Lockouts = {}
Core.Lockouts = Lockouts

local HOUR = 3600
Lockouts.HOUR = HOUR

local Now = Core.Now

local function Text(value)
    value = Core.Plain(value)
    if type(value) == "string" and value ~= "" then return value end
    return nil
end

---------------------------------------------------------------------------
-- Erfassen (nur der gespielte Charakter; die Twinks beim nächsten Einloggen)
---------------------------------------------------------------------------

local function ReadBosses(index, total)
    if type(GetSavedInstanceEncounterInfo) ~= "function" or not total or total <= 0 then return nil end
    local list = {}
    for i = 1, total do
        local ok, name, _, killed = pcall(GetSavedInstanceEncounterInfo, index, i)
        name = ok and Text(name)
        if name then list[#list + 1] = { n = name, k = Core.Bool(killed, false) or nil } end
    end
    return #list > 0 and list or nil
end

local function Count(fn)
    if type(fn) ~= "function" then return 0 end
    local ok, n = pcall(fn)
    return ok and Core.Num(n) or 0
end

local function SortLocks(a, b)
    if a.name ~= b.name then return a.name < b.name end
    return (a.diffId or 0) < (b.diffId or 0)
end

local function LockID(l)
    return table.concat({ l.name, tostring(l.diff or l.diffId or ""), tostring(l.size or ""), l.worldBoss and "w" or "" }, "\001")
end

-- Kurzform einer Liste: ändert sie sich, meldet der Dienst LOCKOUTS_CHANGED.
local function Signature(list)
    local parts = {}
    for _, l in ipairs(list) do
        local killed = 0
        for _, b in ipairs(l.bosses or {}) do if b.k then killed = killed + 1 end end
        parts[#parts + 1] = LockID(l) .. "\002" .. tostring(l.done or "") .. "\002" .. killed .. "\002" .. (l.ext and "e" or "")
            .. "\002" .. tostring(l.resetAt)
    end
    return table.concat(parts, "\003")
end

-- Die Restzeit kommt in Sekunden: zwei Abfragen derselben Sperre ergeben Zeitpunkte, die um Sekunden schwanken.
-- Bleibt der neue Zeitpunkt nah am alten, gilt der alte weiter (ruhige Daten, keine Nachricht ohne Änderung).
local JITTER = 120
local function KeepResetTimes(list, old)
    if type(old) ~= "table" then return end
    local byID = {}
    for _, l in ipairs(old) do
        if type(l) == "table" and type(l.name) == "string" and Core.Num(l.resetAt) then byID[LockID(l)] = l.resetAt end
    end
    for _, l in ipairs(list) do
        local before = byID[LockID(l)]
        if before and math.abs(before - l.resetAt) <= JITTER then l.resetAt = before end
    end
end

function Lockouts.Scan()
    local me = Core.me
    if not me or type(GetSavedInstanceInfo) ~= "function" then return false end
    local now = Now()
    local list = {}
    for i = 1, Count(GetNumSavedInstances) do
        local ok, name, _, reset, diffId, locked, extended, _, isRaid, maxPlayers, diffName, total, done =
            pcall(GetSavedInstanceInfo, i)
        name, reset = ok and Text(name), ok and Core.Num(reset)
        -- Abgelaufene Sperren listet Blizzard bis zum Verlängern weiter (locked = false): nicht zählen.
        if name and reset and reset > 0 and (Core.Bool(locked, false) or Core.Bool(extended, false)) then
            total = Core.Num(total)
            list[#list + 1] = {
                name = name,
                diff = Text(diffName),
                diffId = Core.Num(diffId),
                raid = Core.Bool(isRaid, false) or nil,
                size = Core.Num(maxPlayers),
                done = Core.Num(done),
                total = total,
                resetAt = now + reset,
                ext = Core.Bool(extended, false) or nil,
                bosses = ReadBosses(i, total),
            }
        end
    end
    if type(GetSavedWorldBossInfo) == "function" then
        for i = 1, Count(GetNumSavedWorldBosses) do
            local ok, name, _, reset = pcall(GetSavedWorldBossInfo, i)
            name, reset = ok and Text(name), ok and Core.Num(reset)
            if name and reset and reset > 0 then
                list[#list + 1] = { name = name, worldBoss = true, resetAt = now + reset }
            end
        end
    end
    table.sort(list, SortLocks)
    KeepResetTimes(list, me.lockouts)
    local before = type(me.lockouts) == "table" and Signature(Lockouts.Active(me)) or nil
    me.lockouts, me.lockoutsAt = list, now
    if before ~= Signature(list) then
        Core.Fire("LOCKOUTS_CHANGED", Core.charKey)
        if Lockouts.expiryArmed then Lockouts.ArmExpiry() end   -- neue Sperre: der Wecker gilt dem nächsten Ablauf
    end
    return true
end

-- Fragt gerade jemand anders (Blizzards Schlachtzugsfenster, ein anderes Addon, ezPanel vor seiner Umstellung),
-- reicht dessen Antwort: ezCore stellt dann keine zweite Abfrage. Nur zuhören (hooksecurefunc), nichts ersetzen.
Lockouts.FOREIGN_WINDOW = 2   -- Sekunden
local ownRequest, foreignAt = false, nil
if type(hooksecurefunc) == "function" and type(rawget(_G, "RequestRaidInfo")) == "function" then
    pcall(hooksecurefunc, "RequestRaidInfo", function()
        if not ownRequest then foreignAt = GetTime and GetTime() or nil end
    end)
end

-- Blizzards Abfrage; die Antwort kommt als UPDATE_INSTANCE_INFO. → true (gefragt) | false, Grund ("missing", "recent")
function Lockouts.Request(force)
    if type(RequestRaidInfo) ~= "function" then return false, "missing" end
    local now = GetTime and GetTime() or 0
    if not force and foreignAt and now - foreignAt >= 0 and now - foreignAt < Lockouts.FOREIGN_WINDOW then return false, "recent" end
    ownRequest = true
    local ok = pcall(RequestRaidInfo)
    ownRequest = false
    return ok
end

-- Mehrere Auslöser kurz nacheinander ergeben eine Abfrage: nur der zuletzt gestellte Wecker fragt.
local requestGeneration = 0
function Lockouts.RequestSoon(delay)
    requestGeneration = requestGeneration + 1
    local generation = requestGeneration
    if not (C_Timer and C_Timer.After) then return false end
    C_Timer.After(delay or 2, function()
        if generation == requestGeneration then Lockouts.Request() end
    end)
    return true
end

---------------------------------------------------------------------------
-- Lesen
---------------------------------------------------------------------------

-- Aktive Sperren eines Charakter-Datensatzes (abgelaufene fallen heraus).
function Lockouts.Active(c)
    local list = {}
    if type(c) ~= "table" or type(c.lockouts) ~= "table" then return list end
    local now = Now()
    for _, l in ipairs(c.lockouts) do
        if type(l) == "table" and type(l.name) == "string" and Core.Num(l.resetAt) and l.resetAt > now then
            list[#list + 1] = l
        end
    end
    return list
end

-- Aktive Sperren eines Charakters (Schlüssel wie Core.charKey; ohne Schlüssel: der gespielte).
function Lockouts.List(charKey)
    return Lockouts.Active(Core.Char(charKey or Core.charKey))
end

-- Sperre eines Charakters für eine Instanz (Name wie bei Blizzard, Groß/Klein egal; diff optional) oder nil.
function Lockouts.IsLocked(name, charKey, diff)
    if Core.IsSecret(name) or type(name) ~= "string" or name == "" then return nil end
    local wanted = name:lower()
    for _, l in ipairs(Lockouts.List(charKey)) do
        if l.name:lower() == wanted and (diff == nil or l.diff == diff or l.diffId == diff) then return l end
    end
    return nil
end

-- Zahl aller aktiven Sperren der Charaktere, die filter(c, key) auswählt.
function Lockouts.Total(filter)
    local n = 0
    for _, entry in ipairs(Core.CharacterList(filter)) do n = n + #Lockouts.Active(entry.c) end
    return n
end

local function GroupOrder(a, b)
    if (a.raid or false) ~= (b.raid or false) then return a.raid == true end   -- Schlachtzüge zuerst
    if (a.worldBoss or false) ~= (b.worldBoss or false) then return b.worldBoss == true end
    if a.name ~= b.name then return a.name < b.name end
    return (a.diff or "") < (b.diff or "")
end

-- Alle aktiven Sperren nach Instanz gebündelt; Charaktere in der Reihenfolge von Core.CharacterList.
function Lockouts.ByInstance(filter)
    local groups, order = {}, {}
    for _, entry in ipairs(Core.CharacterList(filter)) do
        for _, l in ipairs(Lockouts.Active(entry.c)) do
            local id = table.concat({ l.name, tostring(l.diff or l.diffId or ""), tostring(l.size or "") }, "\001")
            local g = groups[id]
            if not g then
                g = { name = l.name, diff = l.diff, size = l.size, raid = l.raid == true, worldBoss = l.worldBoss == true,
                    resetAt = l.resetAt, chars = {} }
                groups[id] = g
                order[#order + 1] = g
            end
            if l.resetAt > g.resetAt then g.resetAt = l.resetAt end
            g.chars[#g.chars + 1] = { key = entry.key, c = entry.c, lock = l, isMe = entry.isMe }
        end
    end
    table.sort(order, GroupOrder)
    return order
end

---------------------------------------------------------------------------
-- Instanzen in der letzten Stunde (Account)
---------------------------------------------------------------------------

local function Log()
    local db = Core.db
    if type(db) ~= "table" then return nil end
    if type(db.instances) ~= "table" then db.instances = {} end
    return db.instances
end

local function Prune(log, now)
    local removed = 0
    for i = #log, 1, -1 do
        local e = log[i]
        if type(e) ~= "table" or not Core.Num(e.t) or now - e.t >= HOUR then
            table.remove(log, i)
            removed = removed + 1
        end
    end
    return removed
end

-- Anzahl der in der letzten Stunde betretenen Instanzen, Sekunden bis die älteste herausfällt, die Liste (nur lesen).
function Lockouts.Recent()
    local log = Log()
    if not log then return 0, nil, {} end
    local now = Now()
    Prune(log, now)
    local oldest
    for _, e in ipairs(log) do
        if not oldest or e.t < oldest then oldest = e.t end
    end
    return #log, oldest and (oldest + HOUR - now) or nil, log
end
Lockouts.RecentInstances = Lockouts.Recent   -- Name der alten ezPanel-Schnittstelle

-- Betretene Instanz (Dungeon oder Schlachtzug) merken; dieselbe Instanz desselben Charakters nur einmal.
function Lockouts.NoteInstance()
    if type(GetInstanceInfo) ~= "function" or not Core.charKey then return false end
    local inside, kind = Core.InInstance()
    if inside ~= true or (kind ~= "party" and kind ~= "raid") then return false end
    local ok, name, _, _, _, _, _, _, mapId = pcall(GetInstanceInfo)
    name, mapId = ok and Text(name), ok and Core.Num(mapId)
    if not name then return false end
    local log = Log()
    if not log then return false end
    local now = Now()
    Prune(log, now)
    for _, e in ipairs(log) do
        local same = (mapId and e.id == mapId) or (not mapId and e.n == name)
        if same and e.c == Core.charKey and not e.reset then return false end
    end
    log[#log + 1] = { t = now, id = mapId, n = name, c = Core.charKey }
    Core.Fire("INSTANCES_CHANGED", #log)
    return true
end

-- „<Instanz> wurde zurückgesetzt.“ (INSTANCE_RESET_SUCCESS): der nächste Besuch zählt neu.
local resetPattern
function Lockouts.OnSystemMessage(msg)
    if Core.IsSecret(msg) or type(msg) ~= "string" then return false end
    resetPattern = resetPattern or Core.FormatToPattern(rawget(_G, "INSTANCE_RESET_SUCCESS"))
    local name = resetPattern and msg:match(resetPattern)
    if not name then return false end
    for _, e in ipairs(Log() or {}) do
        if type(e) == "table" and e.n == name and e.c == Core.charKey then e.reset = true end
    end
    return true
end

-- Einmalige Übernahme von ezPanels Zählung (ezPanelDB.instances bleibt liegen). → Anzahl übernommener Einträge.
function Lockouts.MigrateInstances()
    local db = Core.db
    if type(db) ~= "table" then return 0 end
    if type(db.migrated) ~= "table" then db.migrated = {} end
    if db.migrated.ezPanelInstances then return 0 end
    local old = rawget(_G, "ezPanelDB")
    if type(old) ~= "table" then return 0 end   -- ezPanel (noch) nicht da: beim nächsten Anmelden wieder prüfen
    db.migrated.ezPanelInstances = true
    if type(old.instances) ~= "table" then return 0 end
    local log, now, n = Log(), Now(), 0
    for _, e in ipairs(old.instances) do
        if type(e) == "table" and Core.Num(e.t) and now - e.t < HOUR and type(e.n) == "string" then
            local known = false
            for _, mine in ipairs(log) do
                if mine.t == e.t and mine.c == e.c and mine.n == e.n then known = true break end
            end
            if not known then
                log[#log + 1] = { t = e.t, id = Core.Num(e.id), n = e.n, c = e.c, reset = e.reset and true or nil }
                n = n + 1
            end
        end
    end
    table.sort(log, function(a, b) return a.t < b.t end)
    return n
end

---------------------------------------------------------------------------
-- Ablauf melden (Welle 23c, A51)
---------------------------------------------------------------------------

Lockouts.EXPIRY_MAX = HOUR   -- spätestens so oft neu prüfen (Uhr verstellt, neue Sperren eines Twinks)
Core.FEATURES.lockoutExpiry = true

function Lockouts.NextExpiry()
    local now, best, who, lock = Now(), nil, nil, nil
    for _, entry in ipairs(Core.CharacterList(nil)) do
        for _, l in ipairs(Lockouts.Active(entry.c)) do
            local left = l.resetAt - now
            if not best or left < best then best, who, lock = left, entry.key, l end
        end
    end
    return best, who, lock
end

local expiryGeneration, lastCheck = 0, nil

-- Abgelaufene Sperren seit der letzten Prüfung melden: je Charakter einmal LOCKOUTS_CHANGED (charKey, "expired").
function Lockouts.CheckExpired()
    local now = Now()
    local since = lastCheck or now
    lastCheck = now
    local fired = {}
    for _, entry in ipairs(Core.CharacterList(nil)) do
        local c = entry.c
        for _, l in ipairs(type(c) == "table" and type(c.lockouts) == "table" and c.lockouts or {}) do
            local at = type(l) == "table" and Core.Num(l.resetAt) or nil
            if at and at > since - 1 and at <= now and not fired[entry.key] then
                fired[entry.key] = true
                Core.Fire("LOCKOUTS_CHANGED", entry.key, "expired")
            end
        end
    end
    return fired
end

-- Wecker auf den nächsten Ablauf stellen (ein Wecker; jeder neue ersetzt den alten). → Sekunden bis zur Prüfung
function Lockouts.ArmExpiry()
    expiryGeneration = expiryGeneration + 1
    Lockouts.expiryArmed = true
    local generation = expiryGeneration
    if lastCheck == nil then lastCheck = Now() end
    local left = Lockouts.NextExpiry()
    if not (left and C_Timer and C_Timer.After) then return nil end
    local delay = math.max(1, math.min(left + 1, Lockouts.EXPIRY_MAX))
    C_Timer.After(delay, function()
        if generation ~= expiryGeneration then return end
        local ok, err = pcall(Lockouts.CheckExpired)
        if not ok then Core.Error(Core.name, err, "Lockouts.CheckExpired") end
        Lockouts.ArmExpiry()
    end)
    return delay
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------

local ready = false
Core.Listen("CHARS_READY", function()
    ready = true
    local ok, err = pcall(Lockouts.MigrateInstances)
    if not ok then Core.Error(Core.name, err, "Lockouts.MigrateInstances") end
    Lockouts.RequestSoon(5.5)
    Lockouts.ArmExpiry()
end, "ezCore.Lockouts")
ns.On("UPDATE_INSTANCE_INFO", function() Lockouts.Scan() end)
ns.On("PLAYER_ENTERING_WORLD", function()
    if not ready then return end
    Lockouts.NoteInstance()
    Lockouts.RequestSoon(3.5)
end)
-- Nach einem Bosskill speichert der Server die Sperre: kurz danach neu abfragen.
-- (jeweils eine halbe Sekunde nach dem üblichen Zeitpunkt anderer Abfrager, damit deren Abfrage genügt)
ns.On("BOSS_KILL", function() Lockouts.RequestSoon(2.5) end)
ns.On("ENCOUNTER_END", function(_, _, _, _, _, success)
    if Core.Plain(success) == 1 then Lockouts.RequestSoon(2.5) end
end)
ns.On("CHAT_MSG_SYSTEM", function(_, msg)
    if Lockouts.OnSystemMessage(msg) then Lockouts.RequestSoon(1.5) end
end)
