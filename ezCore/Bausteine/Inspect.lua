local _, ns = ...
local Core = ezCore

--[[
    Betrachten-Dienst (Gesamtreview 18.11.2026, I3): EINE Stelle für `NotifyInspect` in der ganzen Sammlung.
    Vorher lag die einzelne Anfrage im Spieler-Tooltip (UnitTooltip.lua); der Ausrüstungs-Check der Gruppe (ezGear)
    braucht dieselbe Sperre und eine Reihe für viele Mitglieder – beides teilt sich jetzt diesen Zustand, damit sich
    Tooltip und Gruppen-Check nie gegenseitig die Antwort wegnehmen (Leitlinie 2).

      Core.Inspect.Check(unit)              → nil, guid (erlaubt) | Grund: "combat", "window" (Blizzards Betrachten-
                                              Fenster offen), "notPlayer", "self", "unknown" (GUID fehlt oder geheim),
                                              "offline", "range" (CanInspect: zu weit weg)
      Core.Inspect.Wait(höflich)            → Sekunden, bis die nächste Anfrage erlaubt ist (0 = sofort); mit höflich
                                              = true zählt auch die Pause nach einer fremden Anfrage (nur die Reihe)
      Core.Inspect.ForeignWait()            → Sekunden, die die Pause nach einer fremden Anfrage noch dauert
      Core.Inspect.Request(unit, fn, owner) → true | false, Grund ("busy", "wait", "api" oder einer aus Check).
                                              fn(unit, guid) läuft bei INSPECT_READY für genau diesen Spieler, solange
                                              die Daten des Clients gelten (danach ClearInspectPlayer). unit ist die
                                              Einheit dieses Aufrufers, sonst über die GUID neu gesucht
                                              (UnitTokenFromGUID); nil, wenn der Spieler nicht mehr zu finden ist.
      Core.Inspect.Pending()                → GUID der laufenden Anfrage oder nil
      Core.Inspect.OnReady(_, guid)         Zuhörer für INSPECT_READY (auch für Tests)
      Core.Inspect.GroupUnits()             → { "player", "party1" … } bzw. { "raid1" … } (alle Mitglieder samt dir)
      Core.Inspect.NewQueue(opts)           Reihe für viele Mitglieder (unten)

    Regeln (docs/blizzard-regeln.md, Abschnitt 5): nie im Kampf, nie bei offenem Betrachten-Fenster (Blizzards Fenster
    hat Vorrang), höchstens alle GAP Sekunden eine Anfrage – für alle Aufrufer zusammen –, eine verlorene Antwort
    verfällt nach TIMEOUT. Rücksicht auf andere Addons, die selbst betrachten (TacoTip, GearScore …; Leitlinie 9):
    ein hooksecurefunc an NotifyInspect merkt fremde Anfragen; danach wartet die Reihe FOREIGN_PAUSE Sekunden (die
    einzelne Anfrage des Spieler-Tooltips nicht – sie fragte schon vor dem Dienst nach GAP wieder an), und der Dienst
    räumt die Daten des Clients (ClearInspectPlayer) nicht ab, wenn nach der eigenen eine fremde Anfrage kam.
    Geheime Werte: GUIDs und Einheiten werden nur verglichen, wenn sie nicht geheim sind (Core.IsSecret zuerst).
]]

local Inspect = {}
Core.Inspect = Inspect

Inspect.GAP = 1.5            -- Mindestabstand zwischen zwei Anfragen (alle Aufrufer zusammen)
Inspect.TIMEOUT = 3          -- bleibt INSPECT_READY so lange aus, gilt die Anfrage als verloren (V-027)
Inspect.FOREIGN_PAUSE = 4    -- nach einer Anfrage eines anderen Addons bzw. von Blizzards Betrachten so lange keine Reihe

local IsSecret = Core.IsSecret
local Clock = Core.Uptime
local pending                -- { guid, unit, t, callbacks = { { fn, owner, unit } … } }
local lastRequest, lastForeign = -1000, -1000
local own = false            -- true, solange der Dienst selbst NotifyInspect ruft

-- Wert nur, wenn er nicht geheim ist (sonst nil); Fehler fallen still auf nil.
local Plain = Core.PlainCall

-- Blizzards Betrachten-Fenster offen?
function Inspect.WindowOpen()
    local frame = rawget(_G, "InspectFrame")
    return type(frame) == "table" and frame.IsShown ~= nil and frame:IsShown() == true
end

function Inspect.Check(unit)
    if Core.InCombat() then return "combat" end
    if Inspect.WindowOpen() then return "window" end
    if IsSecret(unit) or type(unit) ~= "string" then return "unknown" end
    if not Plain(UnitIsPlayer, unit) then return "notPlayer" end
    if Plain(UnitIsUnit, unit, "player") then return "self" end
    local guid = Plain(UnitGUID, unit)
    if type(guid) ~= "string" then return "unknown" end
    local connected = rawget(_G, "UnitIsConnected")
    if type(connected) == "function" and Plain(connected, unit) == false then return "offline" end
    if not Plain(CanInspect, unit) then return "range" end
    return nil, guid
end

-- Eine verlorene Antwort verfallen lassen.
local function Expire()
    if pending and Clock() - (pending.t or 0) >= Inspect.TIMEOUT then pending = nil end
end

function Inspect.Pending()
    Expire()
    return pending and pending.guid or nil
end

function Inspect.ForeignWait()
    return math.max(lastForeign + Inspect.FOREIGN_PAUSE - Clock(), 0)
end

-- höflich (nur die Reihe): auch die Pause nach einer fremden Anfrage abwarten. Die einzelne Anfrage des Tooltips
-- wartet sie nicht ab (Gegenprüfung I3: sonst fehlte die Spezialisierung, solange TacoTip oder GearScore betrachten).
function Inspect.Wait(polite)
    Expire()
    local now = Clock()
    local wait = math.max(lastRequest + Inspect.GAP - now, 0)
    if polite then wait = math.max(wait, Inspect.ForeignWait()) end
    if pending then wait = math.max(wait, pending.t + Inspect.TIMEOUT - now) end
    return wait
end

local function AddCallback(fn, owner, unit)
    if type(fn) ~= "function" then return end
    for _, cb in ipairs(pending.callbacks) do
        if cb.fn == fn then return end
    end
    pending.callbacks[#pending.callbacks + 1] = { fn = fn, owner = owner or Core.name, unit = unit }
end

-- Einheit eines Rückrufs bei der Antwort: seine eigene, wenn sie noch dieser Spieler ist, sonst über die GUID neu
-- gesucht (die Maus ist weitergezogen, die Gruppe umgestellt); nil, wenn der Spieler nicht zu finden ist.
local function UnitFor(unit, guid)
    if type(unit) == "string" and Plain(UnitGUID, unit) == guid then return unit end
    local token = Plain(rawget(_G, "UnitTokenFromGUID"), guid)
    if type(token) == "string" and token ~= "" then return token end
    return nil
end

function Inspect.Request(unit, fn, owner)
    local reason, guid = Inspect.Check(unit)
    if reason then return false, reason end
    Expire()
    if pending and pending.guid == guid then
        AddCallback(fn, owner, unit)
        return true
    end
    if pending then return false, "busy" end
    if Inspect.Wait() > 0 then return false, "wait" end
    local notify = rawget(_G, "NotifyInspect")
    if type(notify) ~= "function" then return false, "api" end
    own = true
    local ok = pcall(notify, unit)
    own = false
    if not ok then return false, "api" end
    lastRequest = Clock()
    pending = { guid = guid, unit = unit, t = lastRequest, callbacks = {} }
    AddCallback(fn, owner, unit)
    return true
end

function Inspect.OnReady(_, guid)
    if not pending or IsSecret(guid) or guid ~= pending.guid then return end
    local request = pending
    pending = nil
    for _, cb in ipairs(request.callbacks) do
        Core.Try(cb.owner, "Inspect", cb.fn, UnitFor(cb.unit or request.unit, guid), guid)
    end
    -- Daten des Clients freigeben – nicht, solange Blizzards Fenster sie zeigt oder ein anderes Addon danach gefragt hat
    if not Inspect.WindowOpen() and lastForeign < request.t then Core.Call(rawget(_G, "ClearInspectPlayer")) end
end
Core.RegisterEvent(Core.name, "INSPECT_READY", Inspect.OnReady)

-- Fremde Anfragen merken (andere Addons, Blizzards „Betrachten“): nur hooksecurefunc, nichts wird verändert.
function Inspect.NoteForeign()
    if not own then lastForeign = Clock() end
end
if type(rawget(_G, "NotifyInspect")) == "function" and type(hooksecurefunc) == "function" then
    hooksecurefunc("NotifyInspect", function() Inspect.NoteForeign() end)
end

-- Alle Mitglieder der Gruppe bzw. des Schlachtzugs samt dir, in Blizzards Reihenfolge; allein nur "player".
function Inspect.GroupUnits()
    local units = {}
    local count = Core.Num(Plain(rawget(_G, "GetNumGroupMembers"))) or 0
    if Plain(rawget(_G, "IsInRaid")) then
        for i = 1, math.min(count, 40) do units[#units + 1] = "raid" .. i end
        return units
    end
    units[1] = "player"
    for i = 1, math.min(math.max(count - 1, 0), 4) do units[#units + 1] = "party" .. i end
    return units
end

---------------------------------------------------------------------------
-- Reihe für viele Mitglieder (Ausrüstungs-Check der Gruppe)
--
--   local q = Core.Inspect.NewQueue({ owner = "ezGear", step = 2, read = fn(unit, guid) → daten | nil [, unvollständig],
--       onUpdate = fn(q, eintrag | nil), onDone = fn(q, grund) })
--   q:Start(einträge) → true | false, Grund ("combat", "window", "running", "empty")
--       einträge = { { unit = "raid3", guid = …, … eigene Felder }, … } – höchstens Inspect.QUEUE_MAX
--   q:Cancel(grund), q:IsRunning(), q:Counts() → fertig, gesamt; q.entries
--   q.waiting = "foreign", solange die Reihe auf die Pause nach einer fremden Anfrage wartet (sonst nil; onUpdate
--       mit eintrag = nil meldet den Wechsel)
--   Eintrag.state: "wait" → "asking" → "done" | "partial" | "range" | "offline" | "failed" | "gone" | "skip"
--   Grund bei onDone: "done", "combat", "window", "foreign" (ein anderes Addon betrachtet länger als
--       Inspect.QUEUE_FOREIGN_MAX ohne Pause), "closed" (vom Modul), "cancel"
--
-- Ein Mitglied je step Sekunden (mindestens Inspect.GAP), nie im Kampf (Abbruch beim Kampfbeginn), Abbruch, wenn
-- Blizzards Betrachten-Fenster aufgeht. Wer nicht in Reichweite ist, dessen Antwort verloren ist oder unvollständig
-- war (read gibt als zweiten Wert true: der Client kannte noch nicht alle Gegenstände; Zustand "partial", die Daten
-- bleiben), kommt am Ende noch einmal dran (höchstens Inspect.QUEUE_TRIES Versuche). read läuft in der Antwort,
-- solange der Client die Daten des Betrachteten hält.
---------------------------------------------------------------------------

Inspect.QUEUE_MAX = 40
Inspect.QUEUE_STEP = 2
Inspect.QUEUE_TRIES = 2
Inspect.QUEUE_TICK = 0.25
Inspect.QUEUE_FOREIGN_MAX = 30   -- so lange wartet eine Reihe ohne Unterbrechung auf fremde Anfragen, dann Abbruch

local queues = setmetatable({}, { __mode = "k" })   -- laufende Reihen (für den Abbruch bei Kampfbeginn)
local Queue = {}
Queue.__index = Queue

local REASON_STATE = { range = "range", offline = "offline", notPlayer = "skip", self = "skip", unknown = "gone",
    api = "failed" }
local RETRY = { range = true, failed = true, partial = true }

local function Notify(q, entry)
    if type(q.opts.onUpdate) == "function" then Core.Try(q.opts.owner, "Inspect queue", q.opts.onUpdate, q, entry) end
end

function Queue:IsRunning() return self.running == true end

function Queue:Counts()
    local done = 0
    for _, entry in ipairs(self.entries) do
        if entry.state ~= "wait" and entry.state ~= "asking" then done = done + 1 end
    end
    return done, #self.entries
end

function Queue:Finish(reason)
    if not self.running then return end
    self.running = false
    queues[self] = nil
    if self.ticker and self.ticker.Cancel then self.ticker:Cancel() end
    self.ticker = nil
    if self.current and self.current.state == "asking" then self.current.state = "wait" end
    self.current = nil
    self.waiting, self.waitSince = nil, nil
    self.reason = reason
    if type(self.opts.onDone) == "function" then Core.Try(self.opts.owner, "Inspect queue", self.opts.onDone, self, reason) end
end

function Queue:Cancel(reason) self:Finish(reason or "cancel") end

-- Die Einheit eines Eintrags passt noch zu seiner GUID? Sonst über die GUID neu suchen (Gruppe umgestellt).
local function Resolve(entry)
    if type(entry.guid) ~= "string" then return entry.unit end
    if Plain(UnitGUID, entry.unit) == entry.guid then return entry.unit end
    local token = Plain(rawget(_G, "UnitTokenFromGUID"), entry.guid)
    if type(token) == "string" and token ~= "" then
        entry.unit = token
        return token
    end
    return nil
end

local function NextEntry(q)
    for _, entry in ipairs(q.entries) do
        if entry.state == "wait" then return entry end
    end
    for _, entry in ipairs(q.entries) do
        if RETRY[entry.state] and (entry.tries or 0) < Inspect.QUEUE_TRIES then return entry end
    end
    return nil
end

function Queue:Answer(entry, unit, guid)
    if self.current ~= entry then return end
    self.current = nil
    if guid ~= entry.guid then
        entry.state = "gone"
    elseif unit == nil then
        -- Antwort für diesen Spieler, aber er ist gerade nicht zu finden: Fehlversuch, kommt noch einmal dran
        entry.state = "failed"
    else
        local ok, data, partial = Core.Try(self.opts.owner, "Inspect read", self.opts.read, unit, guid)
        if not ok then data, partial = nil, nil end
        if data ~= nil then
            entry.data = data
            entry.state = partial and "partial" or "done"
        else
            -- eine unvollständige Antwort eines früheren Versuchs bleibt, wenn der nächste gar nichts bringt
            entry.state = entry.data ~= nil and "partial" or "failed"
        end
    end
    Notify(self, entry)
end

function Queue:Step()
    if not self.running then return end
    if Core.InCombat() then return self:Finish("combat") end
    if Inspect.WindowOpen() then return self:Finish("window") end
    local now = Clock()
    if self.current then
        -- verlorene Antwort: zählt als Fehlversuch, kommt am Ende noch einmal dran
        if now - self.current.t < Inspect.TIMEOUT then return end
        self.current.state = "failed"
        Notify(self, self.current)
        self.current = nil
    end
    local entry = NextEntry(self)
    if not entry then return self:Finish("done") end
    if now - (self.last or -1000) < self.step then return end
    -- Rücksicht auf ein anderes Addon, das gerade betrachtet (Leitlinie 9) – sichtbar über q.waiting
    if Inspect.ForeignWait() > 0 then
        if self.waiting ~= "foreign" then
            self.waiting, self.waitSince = "foreign", now
            Notify(self, nil)
        elseif now - self.waitSince >= Inspect.QUEUE_FOREIGN_MAX then
            return self:Finish("foreign")
        end
        return
    end
    if self.waiting then
        self.waiting, self.waitSince = nil, nil
        Notify(self, nil)
    end
    if Inspect.Wait(true) > 0 then return end
    local unit = Resolve(entry)
    if not unit then
        entry.state = "gone"
        return Notify(self, entry)
    end
    local q = self
    local ok, reason = Inspect.Request(unit, function(u, g) q:Answer(entry, u, g) end, self.opts.owner)
    if ok then
        entry.tries = (entry.tries or 0) + 1
        entry.state, entry.t = "asking", now
        self.current, self.last = entry, now
        return Notify(self, entry)
    end
    if reason == "combat" or reason == "window" then return self:Finish(reason) end
    if reason == "busy" or reason == "wait" then return end
    entry.tries = (entry.tries or 0) + 1
    entry.state = REASON_STATE[reason] or "failed"
    Notify(self, entry)
end

function Queue:Start(list)
    if self.running then return false, "running" end
    if Core.InCombat() then return false, "combat" end
    if Inspect.WindowOpen() then return false, "window" end
    self.entries = {}
    for _, entry in ipairs(type(list) == "table" and list or {}) do
        if #self.entries >= Inspect.QUEUE_MAX then break end
        if type(entry) == "table" and type(entry.unit) == "string" then
            entry.state, entry.tries, entry.data = "wait", 0, nil
            if entry.guid == nil then entry.guid = Plain(UnitGUID, entry.unit) end
            self.entries[#self.entries + 1] = entry
        end
    end
    if #self.entries == 0 then return false, "empty" end
    self.running, self.reason, self.current, self.last = true, nil, nil, nil
    self.waiting, self.waitSince = nil, nil
    queues[self] = true
    local q = self
    local timer = rawget(_G, "C_Timer")
    if type(timer) == "table" and type(timer.NewTicker) == "function" then
        self.ticker = timer.NewTicker(Inspect.QUEUE_TICK, function() Core.Try(q.opts.owner, "Inspect queue", q.Step, q) end)
    end
    self:Step()
    return true
end

function Inspect.NewQueue(opts)
    opts = type(opts) == "table" and opts or {}
    local q = setmetatable({ opts = opts, entries = {}, running = false,
        step = math.max(Core.Num(opts.step) or Inspect.QUEUE_STEP, Inspect.GAP) }, Queue)
    return q
end

-- Kampfbeginn: jede laufende Reihe sofort abbrechen (nicht erst beim nächsten Takt).
Core.RegisterEvent(Core.name, "PLAYER_REGEN_DISABLED", function()
    local list = {}
    for q in pairs(queues) do list[#list + 1] = q end
    for _, q in ipairs(list) do q:Finish("combat") end
end)
