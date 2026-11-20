local _, ns = ...
local Core = ezCore

--[[
    Ausrüstungs-Check der Gruppe (Gesamtreview 18.11.2026, I3; Entscheidung des Nutzers vom 18.11.2026, Punkt 8):
    Itemlevel, fehlende Verzauberungen und leere Plätze jedes Mitglieds auf einen Blick – vor Raid und Dungeon,
    damit der Leiter nicht jeden einzeln fragen oder betrachten muss. Hier steht die Bewertung; das Seitenteil am
    Reiter „Schlachtzug“ baut GroupPanel.lua.

    Daten (Leitlinie 11): vom Client über „Betrachten“ (NotifyInspect, Antwort INSPECT_READY) – der Durchschnitt über
    ezCores eine Regel (Core.SlotText.AverageLevel, wie beim Betrachten und im Spieler-Tooltip), Verzauberungen über
    die eine Regel des Charakterfensters (Character.EnchantMissingFor, Liste ENCHANTABLE), leere Plätze über ezCores
    Platzliste (Core.EquipSlots.LIST). Keine Addon-Nachrichten. Die eigene Zeile liest ezGear direkt, ohne Betrachten.
    Abruf: ezCores Betrachten-Dienst (Core.Inspect.NewQueue) – nur auf Klick, nie im Kampf (Abbruch beim
    Kampfbeginn), ein Mitglied je STEP Sekunden, höchstens 40, Abbruch beim Schließen des Reiters und bei offenem
    Betrachten-Fenster; wer nicht in Reichweite ist, steht als „nicht in Reichweite“ in der Liste (docs/blizzard-
    regeln.md, Abschnitt 5). Ergebnisse gelten FRESH Sekunden; ein neuer Klick liest nur die übrigen – sind alle
    frisch, alle neu.

      GC.Evaluate(unit)  → { ilvl, missing = { Platz … }, empty = { Platz … }, unknown = n, read = n } | nil,
                           unvollständig (unknown > 0: die Reihe fragt noch einmal, die Zeile heißt „unvollständig“)
      GC.Start()         → true | false, Grund        GC.Cancel(grund)        GC.Running()
      GC.Waiting()       → "foreign", solange die Reihe auf ein anderes Addon wartet, das gerade betrachtet
      GC.LastReason()    → Grund des letzten Endes ("done", "alone" – niemand außer dir –, "combat", "window",
                           "foreign", "closed", "cancel") oder nil
      GC.Rows()          → Zeilen für die Anzeige (Mitglieder der Gruppe in Blizzards Reihenfolge)
      GC.Progress()      → fertig, gesamt
      GC.OnChange(fn)    fn(grund | nil) nach jeder Änderung (GroupPanel.lua zeichnet neu)
]]

local GC = {}
ns.GroupCheck = GC

GC.STEP = 2          -- Sekunden je Mitglied (Server-Last; ezCore hält zusätzlich 1,5 s für alle Aufrufer)
GC.FRESH = 300       -- so lange gilt ein gelesenes Ergebnis

-- Plätze, deren Leere kein Mangel ist: Distanz (nicht jede Klasse und Stufe füllt ihn; Im Spiel prüfen). Hemd und
-- Wappenrock zählen nie (Character.Skipped), die Schildhand nicht neben einem Zweihänder (unten).
local function EmptyIgnored(slot)
    local slots = Core.EquipSlots
    return slots ~= nil and slots.SLOT ~= nil and slot == slots.SLOT.RANGED
end
GC.EmptyIgnored = EmptyIgnored

local results = {}   -- [guid] = { state, data, t, name, class }
GC.results = results
local listeners = {}
local queue, lastReason

local function Changed(reason)
    for _, fn in ipairs(listeners) do ns.Try("GroupCheck", fn, reason) end
end

function GC.OnChange(fn)
    if type(fn) == "function" then listeners[#listeners + 1] = fn end
end

-- Wert nur, wenn er nicht geheim ist (sonst nil): ezCores eine Regel
local Plain = Core.PlainCall

function GC.Evaluate(unit)
    local slots = Core.EquipSlots
    local Char = ns.Character
    if not (slots and slots.LIST and Char) or ns.IsSecret(unit) or type(unit) ~= "string" then return nil end
    local result = { missing = {}, empty = {}, unknown = 0, read = 0 }
    local mainLink, mainUnknown
    for _, entry in ipairs(slots.LIST) do
        local slot = entry.slot
        if not Char.Skipped(slot) then
            local link = ns.Plain(ns.Call(GetInventoryItemLink, unit, slot))
            if type(link) ~= "string" or link == "" then link = nil end
            local id = ns.Num(ns.Call(rawget(_G, "GetInventoryItemID"), unit, slot))
            if link then
                result.read = result.read + 1
                if slot == slots.SLOT.MAINHAND then mainLink = link end
                if Char.EnchantMissingFor(unit, slot, link) then result.missing[#result.missing + 1] = slot end
            elseif id and id > 0 then
                -- Der Client kennt den Gegenstand, aber noch keinen Link: nicht leer, nur unbekannt
                result.unknown = result.unknown + 1
                if slot == slots.SLOT.MAINHAND then mainUnknown = true end
            elseif not EmptyIgnored(slot) then
                result.empty[#result.empty + 1] = slot
            end
        end
    end
    -- Schildhand neben einem Zweihänder ist nicht leer; ist die Waffe noch unbekannt, lässt sich das nicht sagen
    -- (dann zählt die Schildhand als unbekannt statt als leer)
    if (mainLink and slots.IsTwoHand(mainLink)) or mainUnknown then
        for i = #result.empty, 1, -1 do
            if result.empty[i] == slots.SLOT.OFFHAND then
                table.remove(result.empty, i)
                if not mainLink then result.unknown = result.unknown + 1 end
            end
        end
    end
    -- Nichts lesbar: die Antwort kam ohne Daten (gilt als „keine Antwort“, nicht als nackter Spieler)
    if result.read == 0 and result.unknown == 0 then return nil end
    result.ilvl = Char.Average(unit)
    -- Unbekannte Plätze: unvollständig (Gegenprüfung I3 – sonst stand „0 fehlt, 0 leer“ grün da, obwohl nichts geprüft
    -- war); die Reihe fragt noch einmal (Core.Inspect, Zustand "partial")
    return result, result.unknown > 0
end

-- Mitglieder in Blizzards Reihenfolge: { unit, guid, name, class, self } – die eigene Zeile mit unit "player" (im
-- Schlachtzug ist man auch „raidN“; gelesen wird dann ohne Betrachten wie am Charakterfenster)
function GC.Members()
    local list = {}
    local inspect = Core.Inspect
    for _, unit in ipairs(inspect and inspect.GroupUnits() or { "player" }) do
        local guid = Plain(UnitGUID, unit)
        if type(guid) == "string" then
            local name = Plain(UnitName, unit)
            local self = unit == "player" or Core.UnitIs(unit, "player") == true
            list[#list + 1] = { unit = self and "player" or unit, guid = guid, name = type(name) == "string" and name or "?",
                class = Core.ClassOfGUID(guid), self = self }
        end
    end
    return list
end

local function Store(entry, state, data)
    local old = results[entry.guid]
    local keep = state ~= "done" and old and old.state == "done" and old.data   -- altes Ergebnis bleibt sichtbar
    results[entry.guid] = { state = state, data = data or keep or nil, t = data and Core.Uptime() or (old and old.t),
        name = entry.name, class = entry.class }
end

local function Fresh(guid)
    local r = results[guid]
    return r ~= nil and r.state == "done" and r.t ~= nil and Core.Uptime() - r.t < GC.FRESH
end

function GC.Running() return queue ~= nil and queue:IsRunning() end
function GC.Waiting() return GC.Running() and queue.waiting or nil end
function GC.LastReason() return lastReason end

function GC.Progress()
    if not queue then return 0, 0 end
    return queue:Counts()
end

local function Queue()
    if queue then return queue end
    local inspect = Core.Inspect
    if not (inspect and inspect.NewQueue) then return nil end
    queue = inspect.NewQueue({ owner = "ezGear", step = GC.STEP, read = GC.Evaluate,
        onUpdate = function(_, entry)
            if entry then Store(entry, entry.state, entry.data) end
            Changed(nil)
        end,
        onDone = function(q, reason)
            lastReason = reason
            -- nach einem Abbruch: wer noch wartete, gilt als „nicht geprüft“ (ein altes Ergebnis bleibt sichtbar)
            for _, entry in ipairs(q.entries) do
                if entry.state == "wait" then Store(entry, "none") end
            end
            Changed(reason)
        end })
    return queue
end

function GC.Start()
    if not ns.Enabled("groupCheck") then return false, "off" end
    if ns.InCombat() then return false, "combat" end
    local q = Queue()
    if not q then return false, "api" end
    if q:IsRunning() then return false, "running" end
    local members, todo = GC.Members(), {}
    for _, m in ipairs(members) do
        if m.self then
            m.state = "done"
            Store(m, "done", GC.Evaluate(m.unit))
        elseif not Fresh(m.guid) then
            todo[#todo + 1] = m
        end
    end
    -- alle frisch: dann alle neu (ein Klick soll immer etwas tun)
    if #todo == 0 then
        for _, m in ipairs(members) do
            if not m.self then todo[#todo + 1] = m end
        end
    end
    lastReason = nil
    if #todo == 0 then
        -- niemand außer dir: eigener Grund (die Zählung der letzten Reihe gilt nicht mehr; Gegenprüfung I3)
        lastReason = "alone"
        Changed("alone")
        return true
    end
    -- Erst starten, dann „wartet“ merken: eine abgewiesene Reihe (Betrachten-Fenster offen) lässt keine Zeile auf
    -- „wartet“ stehen (Gegenprüfung I3). Den ersten Eintrag hat die Reihe beim Start schon gefragt.
    local ok, reason = q:Start(todo)
    if ok then
        for _, m in ipairs(todo) do
            if m.state == "wait" then Store(m, "wait") end
        end
    else
        lastReason = reason
    end
    Changed(ok and nil or reason)
    return ok, reason
end

function GC.Cancel(reason)
    if queue and queue:IsRunning() then queue:Cancel(reason or "cancel") end
end

-- Zeilen für die Anzeige: { unit, guid, name, class, self, state, data, age }
function GC.Rows()
    local rows = {}
    local now = Core.Uptime()
    for _, m in ipairs(GC.Members()) do
        local r = results[m.guid]
        if m.self and not (r and r.state == "done") then
            r = { state = "done", data = GC.Evaluate(m.unit), t = now }
            results[m.guid] = r
        end
        m.state = r and r.state or "none"
        m.data = r and r.data or nil
        m.age = r and r.t and math.max(now - r.t, 0) or nil
        rows[#rows + 1] = m
    end
    return rows
end

-- Eigene Ausrüstung geändert: die eigene Zeile neu lesen
ns.OnReady(function()
    ns.On("PLAYER_EQUIPMENT_CHANGED", function()
        local guid = Plain(UnitGUID, "player")
        if type(guid) == "string" and results[guid] then
            results[guid] = nil
            Changed(nil)
        end
    end)
end)
