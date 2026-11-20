local _, ns = ...
local L = ns.L
local Core = ezCore

-- Zusammenfassung nach dem Kampf (Entscheidung des Nutzers 13.11.2026 zu Welle 2b: „Ja, Schalter ab Werk aus
-- (Empfohlen)“): eine Zeile im Chat – nur für dich – mit eigenem Schaden und eigener Heilung, Wert pro Sekunde und
-- Platz in der Gruppe, dazu ein Eintrag im Verlauf von ezCore (Core.History, Art "combat").
--
-- Die Zahlen kommen nur aus Blizzards C_DamageMeter (Sitzung „Aktueller Kampf“, die nach Kampfende den eben
-- beendeten Kampf hält; Forever-Quelle DamageMeterDocumentation). Im Kampf und kurz danach sind sie gesperrt
-- (SecretWhenInCombat): ezCombat wartet nach PLAYER_REGEN_ENABLED, bis sie lesbar sind (Takt, Ereignisse des
-- Schadensmessers, Ende der Addon-Sperre), höchstens WAIT Sekunden. Jeder Wert geht zuerst durch Core.IsSecret:
--   • Rangliste offen (MeterFrames.Ranking) → Summe, Wert pro Sekunde und Platz von n;
--   • Liste gesperrt, eigene Summe offen (Einzelabfrage mit der eigenen GUID) → nur die Summe, pro Sekunde nur,
--     wenn auch die Dauer offen ist;
--   • alles gesperrt → bis WAIT weiter warten, dann ein kurzer Hinweis „Werte noch gesperrt“.
-- Ohne eigene Werte (kein Schaden, keine Heilung) kommt keine Zeile.
--
-- Rücksicht (Leitlinie 9, Empfehlung „mit Details zurückhaltend“): Läuft Details, bleibt die Chat-Zeile aus, der
-- Eintrag im Verlauf kommt trotzdem (er zeigt sich nirgends doppelt). Tooltip und /ezk status sagen es.
local MS = {}
ns.MeterSummary = MS

MS.WAIT = 20                      -- Sekunden: so lange nach Kampfende auf lesbare Werte warten
MS.STEP = 1                       -- Sekunden zwischen zwei Versuchen
MS.HISTORY_KIND = "combat"

local pending = nil               -- { since = GetTime(), token } solange auf Werte gewartet wird
local token = 0
local lastState = nil             -- "waiting" | "sent" | "locked" | "empty" | "details" (für /ezk status)

---------------------------------------------------------------------------
-- Werte lesen
---------------------------------------------------------------------------

local function MeterType(entry)
    local enum = Enum and Enum.DamageMeterType
    return enum and enum[entry.enumKey] or nil
end

-- Dauer des eben beendeten Kampfs (offen) oder nil.
local function Duration(ranking)
    if ranking and ranking.duration then return ranking.duration end
    local api = rawget(_G, "C_DamageMeter")
    if type(api) ~= "table" or type(api.GetSessionDurationSeconds) ~= "function" then return nil end
    local enum = Enum and Enum.DamageMeterSessionType
    local ok, value = pcall(api.GetSessionDurationSeconds, enum and enum.Current or 1)
    if not ok then return nil end
    return Core.Num(value)
end

-- Eigene Summe aus der Einzelabfrage (offen) oder nil.
local function OwnTotal(meterType)
    local guid = ns.playerGUID
    if type(guid) ~= "string" or Core.IsSecret(guid) then return nil end
    return Core.Num(ns.MeterFrames.LiveAmount(meterType, guid, ns.MeterFrames.CurrentSelector()))
end

-- Werte des eben beendeten Kampfs → { duration, parts = { damage = {…}, healing = {…} } } | nil, Grund
-- ("secret": alles gesperrt, "empty": keine eigenen Werte, "missing": kein Schadensmesser).
function MS.Read()
    local MF = ns.MeterFrames
    if not MF or not MF.Available() then return nil, "missing" end
    local sel = MF.CurrentSelector()
    local result = { parts = {} }
    local locked, any = 0, false
    for _, entry in ipairs(MF.TYPES) do
        local meterType = MeterType(entry)
        if meterType ~= nil then
            local ranking, why = MF.Ranking(meterType, sel)
            local part
            if ranking then
                result.duration = result.duration or ranking.duration
                local mine = ranking.mine
                if mine and mine.total > 0 then
                    part = { total = mine.total, rate = mine.rate, rank = mine.rank, count = ranking.count }
                end
            elseif why == "secret" then
                local total = OwnTotal(meterType)
                if total and total > 0 then
                    part = { total = total }
                elseif not total then
                    locked = locked + 1
                end
            end
            if part then
                result.parts[entry.key] = part
                any = true
            end
        end
    end
    if not any then return nil, locked > 0 and "secret" or "empty" end
    result.duration = result.duration or Duration(nil)
    -- pro Sekunde selbst nur aus offenen Zahlen (Summe und Dauer), wenn Blizzard keinen Wert lieferte
    for _, part in pairs(result.parts) do
        if not part.rate and result.duration and result.duration > 0 then part.rate = part.total / result.duration end
    end
    return result
end

---------------------------------------------------------------------------
-- Zeile und Verlauf
---------------------------------------------------------------------------

local LABELS = { damage = "METER_SUMMARY_DAMAGE", healing = "METER_SUMMARY_HEALING" }

-- „Schaden 12,3k (150/s, Platz 2 von 5)“
local function PartText(key, part)
    local extra = {}
    if part.rate and part.rate > 0 then extra[#extra + 1] = L.METER_SUMMARY_RATE:format(Core.ShortNumber(part.rate)) end
    if part.rank and part.count and part.count > 1 then
        extra[#extra + 1] = L.METER_SUMMARY_RANK:format(part.rank, part.count)
    end
    local text = L.METER_SUMMARY_PART:format(L[LABELS[key]], Core.ShortNumber(part.total))
    if #extra > 0 then text = text .. " (" .. table.concat(extra, ", ") .. ")" end
    return text
end

-- Die Zeile zu den gelesenen Werten (ohne Präfix des Moduls).
function MS.Line(result)
    local parts = {}
    for _, entry in ipairs(ns.MeterFrames.TYPES) do
        local part = result.parts[entry.key]
        if part then parts[#parts + 1] = PartText(entry.key, part) end
    end
    local head = result.duration and result.duration > 0
        and L.METER_SUMMARY_HEAD:format(Core.Duration(result.duration, true)) or L.METER_SUMMARY_HEAD_NOTIME
    return head .. " " .. table.concat(parts, " · ")
end

-- Eintrag im Verlauf (Core.History, Art "combat"): dur, dmg, dps, dmgRank, heal, hps, healRank, size, zone.
-- Fehlt der Dienst, bleibt es bei der Zeile (wartet auf ezCore: Art „combat“ in History.MAX und TypeLabel).
function MS.Record(result)
    local history = Core.History
    if type(history) ~= "table" or type(history.Add) ~= "function" then return nil end
    local entry = { dur = result.duration }
    local damage, healing = result.parts.damage, result.parts.healing
    if damage then entry.dmg, entry.dps, entry.dmgRank = damage.total, damage.rate, damage.rank end
    if healing then entry.heal, entry.hps, entry.healRank = healing.total, healing.rate, healing.rank end
    local size = math.max(damage and damage.count or 0, healing and healing.count or 0)
    if size > 0 then entry.size = size end
    local zone = type(GetRealZoneText) == "function" and Core.Plain(GetRealZoneText()) or nil
    if type(zone) == "string" and zone ~= "" then entry.zone = zone end
    local ok, added = pcall(history.Add, MS.HISTORY_KIND, entry)
    return ok and added or nil
end

---------------------------------------------------------------------------
-- Ablauf nach dem Kampf
---------------------------------------------------------------------------

local function Finish(state)
    pending, lastState = nil, state
end

-- Ein Versuch: → true, wenn erledigt (Zeile, Hinweis oder nichts zu sagen).
function MS.Try()
    if not pending then return true end
    if ns.InCombat() then return false end
    local result, why = MS.Read()
    if result then
        MS.Record(result)
        local other = ns.MeterFrames.OtherMeter()
        if other then
            Finish("details")
        else
            ns.Print(MS.Line(result))
            Finish("sent")
        end
        return true
    end
    if why == "secret" and GetTime() - pending.since < MS.WAIT then return false end
    if why == "secret" then
        ns.Print(L.METER_SUMMARY_LOCKED)
        Finish("locked")
    else
        Finish("empty")
    end
    return true
end

local function Schedule(id)
    C_Timer.After(MS.STEP, function()
        if not pending or pending.token ~= id then return end
        local done = false
        ns.Try("MeterSummary", function() done = MS.Try() end)
        if not done and pending and pending.token == id then Schedule(id) end
    end)
end

-- Nach Kampfende starten (nur mit Schalter).
function MS.Start()
    if not ns.Enabled("meterSummary") then return false end
    token = token + 1
    pending = { since = GetTime(), token = token }
    lastState = "waiting"
    local done = false
    ns.Try("MeterSummary", function() done = MS.Try() end)
    if not done then Schedule(token) end
    return true
end

function MS.Pending() return pending ~= nil end
function MS.State() return lastState end

-- Schnittstelle (ezCore.API("ezCombat"), Auftrag aus ezPanel zu CB-17): Schreibt ezCombat nach dem Kampf einen
-- Eintrag der Verlaufsart „combat“? true, wenn „Zusammenfassung nach dem Kampf“ an ist (und ezCombat läuft), sonst
-- false. Der Baustein „Kampf“ von ezPanel nennt den Schalter dann nur, wenn er wirklich fehlt.
ns.API = ns.API or {}
function ns.API.SummaryEnabled() return ns.Enabled("meterSummary") == true end

---------------------------------------------------------------------------
-- Tooltip, Vorschau, Status
---------------------------------------------------------------------------

function MS.Tooltip()
    local tip = L.OPT_meterSummary_TIP
    local other = ns.MeterFrames and ns.MeterFrames.OtherMeter()
    if other then tip = tip .. "\n\n" .. L.METER_SUMMARY_DETAILS:format(other) end
    return tip
end

-- „Zeigen“: eine Beispielzeile mit erkennbar erfundenen Werten.
function MS.Preview()
    local sample = { duration = 83, parts = {
        damage = { total = 12345, rate = 148, rank = 2, count = 5 },
        healing = { total = 2345, rate = 28, rank = 4, count = 5 },
    } }
    ns.Print(L.METER_SUMMARY_SAMPLE:format(MS.Line(sample)))
    return true
end

function MS.StatusLine()
    if not ns.Enabled("meterSummary") then return nil end
    local key = "STATUS_METER_SUMMARY_" .. string.upper(lastState or "ready")
    local text = L[key] or L.STATUS_METER_SUMMARY_READY
    if lastState == "details" then text = text:format(ns.MeterFrames.OtherMeter() or "Details") end
    return L.STATUS_METER_SUMMARY:format(text)
end

---------------------------------------------------------------------------

ns.On("PLAYER_REGEN_ENABLED", function() MS.Start() end)
ns.On("PLAYER_REGEN_DISABLED", function()
    -- neuer Kampf: die Sitzung „Aktuell“ gehört jetzt zu ihm – nicht mehr auf den vorigen warten
    if pending then Finish("locked") end
end)
local function TryPending()
    if pending then ns.Try("MeterSummary", MS.Try) end
end
for _, event in ipairs({ "DAMAGE_METER_COMBAT_SESSION_UPDATED", "DAMAGE_METER_CURRENT_SESSION_UPDATED" }) do
    ns.On(event, TryPending)
end
-- Addon-Sperre des Spiels endet (oder beginnt): erneut versuchen (ezCore meldet es, CB-22).
ns.OnRestrictionChanged(TryPending)
ns.OnSettingChanged(function(key)
    if key == "meterSummary" and not ns.Enabled("meterSummary") then pending = nil end
end)

ns.AddPreview("meterSummary", 96, MS.Preview)
ns.AddStatusLine(MS.StatusLine)
