local _, ns = ...
local L = ns.L

--[[
    Erfahrung (Titan XP): Fortschritt, Ruhe-XP, XP pro Stunde, Zeit und Kills
    bis zur nächsten Stufe.
    Verbesserungen: Sitzung übersteht /reload, der erste Gewinn nach einem
    Stufenaufstieg geht nicht verloren, Kills bis Aufstieg rechnen den Ruhebonus
    richtig ein (Kills mit Bonus bringen doppelt), keine Division durch null.
    Neue Ränge beim Lehrer („3 neue Ränge, 1 g 20 s“): ezCore.Spells.Waiting – eine Rechnung mit
    ezMerchant (nach dem Lehrerbesuch aus seinen Daten mit Kosten, vorher aus dem Zauberbuch ohne
    Kosten). Die Meldung beim Stufenaufstieg und das Lernen selbst gehören zu ezMerchant.
    Stufe, Erfahrung und Ruhe-XP schreibt ezCore in den Charakter-Datensatz; der Baustein rechnet
    nur die Sitzung (XP pro Stunde, Kills).
    Weg zum Lehrer (MAP-21, V-135): Läuft ezMap, setzt der Menüeintrag „Zum nächsten Lehrer“ Blizzards
    Kartenmarkierung auf den nächsten gemerkten Lehrer deiner Klasse (ezCore.API("ezMap").NearestTrainer("class")
    und SetWaypoint); der Tooltip nennt ihn, sobald neue Ränge warten. Ohne ezMap fehlt der Eintrag.
]]

local block = ns.RegisterBlock({
    id = "xp",
    command = "xp",
    name = L.XP_NAME,
    label = L.XP_LABEL,
    icon = "Interface\\Icons\\XP_Icon",
    fallbackIcon = "Interface\\Icons\\INV_Misc_Book_09",
    events = { "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION", "PLAYER_UPDATE_RESTING" },
    interval = 5,
    colorable = true,
    defaults = {
        enabled = true, zone = "left", order = 20,
        show = "percent",      -- percent | remaining | rate | kills
        rested = true,
        hideMax = true,
        trainer = true,        -- neue Ränge beim Lehrer auf der Leiste
    },
})

---------------------------------------------------------------------------
-- Daten sammeln
---------------------------------------------------------------------------

local lastXP, lastMax, lastLevel
local kills = {}         -- letzte Kill-XP ohne Ruhebonus
local lastGain

-- Eigene Stufe aus ezCore (Core.PlayerLevel, V-179); 1, solange der Client sie nicht kennt.
local function PlayerLevel() return ezCore.PlayerLevel() or 1 end

-- Bekommt der Charakter keine Erfahrung (ausgeschaltet, Höchststufe, Stufengrenze eines Probe-Kontos, unbekannt)? Eine
-- Regel mit ezQuests Vorschau auf der Erfahrungsleiste: ezCore.XPBlocked (Gesamtreview 18.11.2026, Nachlauf P19a –
-- vorher eine eigene Fassung hier ohne die Stufengrenze des Probe-Kontos). Unbekannte Werte (Grund "unknown": Stufe oder
-- Erfahrung noch nicht da oder gesperrt) zählen nicht als Höchststufe – der Baustein zeigt dann wie vorher „?“
-- (Gegenprüfung P19a).
local function AtMax()
    local blocked, why = ezCore.XPBlocked()
    return blocked == true and why ~= "unknown"
end

local function Session()
    local s = ns.session
    if s.xp == nil then s.xp = 0 end
    return s
end

local function OnXP()
    if not ns.session then return end
    local xp, max = ns.Num(UnitXP("player")), ns.Num(UnitXPMax("player"))
    local level = PlayerLevel()
    if not xp or not max then return end
    if lastXP then
        local gain
        if level ~= lastLevel or xp < lastXP then
            -- Stufenaufstieg (am Stufenwechsel erkannt, nicht nur an kleinerer XP):
            -- Rest der alten Stufe plus Fortschritt in der neuen.
            gain = (lastMax or 0) - lastXP + xp
        else
            gain = xp - lastXP
        end
        if gain > 0 then
            local s = Session()
            s.xp = s.xp + gain
            lastGain = gain
        end
    end
    lastXP, lastMax, lastLevel = xp, max, level
end

ns.OnReady(function()
    lastXP, lastMax, lastLevel = ns.Num(UnitXP("player")), ns.Num(UnitXPMax("player")), PlayerLevel()
    Session()
end)
ns.On("PLAYER_XP_UPDATE", OnXP)
ns.On("PLAYER_LEVEL_UP", function() C_Timer.After(0.2, OnXP) end)

-- „X stirbt, Ihr bekommt 45 Erfahrung. (+22 Erholungsbonus)“ – Muster aus Blizzards eigenem Text.
local killPattern
local function KillPattern()
    if killPattern ~= nil then return killPattern end
    -- Eine Fassung für alle Module: ezCore.FormatToPattern. Der Bonus-Text („(+22 Erholungsbonus)“) hängt
    -- hinten an, deshalb ohne den End-Anker.
    local pattern = ezCore.FormatToPattern(COMBATLOG_XPGAIN_FIRSTPERSON)
    killPattern = pattern and (pattern:gsub("%$$", "")) or false
    return killPattern
end

ns.On("CHAT_MSG_COMBAT_XP_GAIN", function(_, msg)
    if not ns.session or type(msg) ~= "string" or ns.IsSecret(msg) then return end
    local pattern = KillPattern()
    if not pattern then return end
    local _, total = msg:match(pattern)
    total = tonumber(total)
    if not total then return end
    -- Bonus in Klammern (Ruhe- oder Gruppenbonus) abziehen.
    local bonus = tonumber(msg:match("%(%+?(%d+)")) or 0
    local base = math.max(1, total - bonus)
    table.insert(kills, base)
    if #kills > 10 then table.remove(kills, 1) end
    local s = Session()
    s.kills = (s.kills or 0) + 1
end)

---------------------------------------------------------------------------
-- Berechnungen
---------------------------------------------------------------------------

local function AverageKill()
    if #kills == 0 then return nil end
    local sum = 0
    for _, v in ipairs(kills) do sum = sum + v end
    return sum / #kills
end

-- Kills bis Aufstieg: Solange Ruhe-XP da ist, bringt ein Kill doppelt.
local function KillsToLevel(remaining, rested, base)
    if not base or base <= 0 then return nil end
    local restedKills = math.min(rested / base, remaining / (2 * base))
    local left = remaining - restedKills * 2 * base
    return math.ceil(restedKills + left / base)
end

local function SessionRate()
    local s = ns.session
    local elapsed = time() - ns.SessionStart()
    if elapsed < 60 or not s.xp or s.xp <= 0 then return nil end
    return s.xp / elapsed * 3600
end

local function LevelRate()
    local me = ns.me
    if not me.playedLevel or not me.playedAt or me.playedLevelAt ~= me.level then return nil end
    local seconds = me.playedLevel + (time() - me.playedAt)
    local xp = ns.Num(UnitXP("player"))
    if seconds < 60 or not xp or xp <= 0 then return nil end
    return xp / seconds * 3600
end

ns.On("TIME_PLAYED_MSG", function()
    if ns.me then ns.me.playedLevelAt = PlayerLevel() end
end)

---------------------------------------------------------------------------
-- Neue Ränge beim Lehrer (Daten: ezCore.Spells)
---------------------------------------------------------------------------

-- Anzahl, Kosten, Liste aus ezCore.Spells.Waiting (eine Rechnung mit ezMerchant). Vor dem ersten
-- Lehrerbesuch zählt das Zauberbuch: Kosten und Liste nil. nil, wenn es nichts zu sagen gibt
-- (ohne Zauber-Wissen oder vor dem Lehrerbesuch ohne lernbaren Rang).
local function TrainerRanks()
    local spells = ezCore.Spells
    if type(spells) ~= "table" or type(spells.Waiting) ~= "function" then return nil end
    local ok, n, cost, source, list = pcall(spells.Waiting, PlayerLevel())
    n = ok and ns.Num(n) or nil
    if not n or (source ~= "trainer" and n == 0) then return nil end
    return n, cost, type(list) == "table" and list or nil
end

---------------------------------------------------------------------------
-- Weg zum nächsten Lehrer (ezMap, MAP-21)
---------------------------------------------------------------------------

local function MapAPI()
    local api = ezCore.API("ezMap")
    if type(api) == "table" and type(api.NearestTrainer) == "function" and type(api.SetWaypoint) == "function" then
        return api
    end
    return nil
end

-- Nächster gemerkter Lehrer der eigenen Klasse auf diesem Kontinent (Kopie aus ezMap) oder nil.
local function NearestTrainer()
    local api = MapAPI()
    if not api then return nil end
    local ok, t = pcall(api.NearestTrainer, "class")
    if not ok or type(t) ~= "table" or not (ns.Num(t.map) and ns.Num(t.x) and ns.Num(t.y)) then return nil end
    return t
end

local function TrainerName(t)
    local label = ezCore.Npcs and ezCore.Npcs.Label and ezCore.Npcs.Label(t)
    return type(label) == "string" and label or (type(t.name) == "string" and t.name) or "?"
end

local function TrainerPlace(t)
    local name = ezCore.MapName(t.map)
    return type(name) == "string" and name or ("#" .. tostring(t.map))
end

-- Kennt das Spiel gerade die eigene Position samt Kontinent? Ohne sie (Instanz, gesperrter Wert) findet ezMap keinen
-- Lehrer – das heißt dann nicht, dass keiner gemerkt ist.
local function PositionKnown()
    local mapID, x, y = ezCore.PlayerPosition()
    if not mapID then return false end
    local map = ezCore.Map
    if type(map) ~= "table" or type(map.WorldPos) ~= "function" then return true end
    return map.WorldPos(mapID, x, y) ~= nil
end

-- Blizzards Kartenmarkierung auf den nächsten Lehrer setzen und im Chat sagen, wohin (oder warum nicht).
local function GoToTrainer()
    local api = MapAPI()
    if not api then return false end
    local t = NearestTrainer()
    if not t then
        ns.Print(PositionKnown() and L.XP_TRAINER_WAY_NONE or L.XP_TRAINER_WAY_NOPOS)
        return false
    end
    local name = TrainerName(t)
    local ok, done, err = pcall(api.SetWaypoint, t.map, t.x, t.y, name)
    if ok and done then
        ns.Print(L.XP_TRAINER_WAY_SET:format(name, TrainerPlace(t)))
        return true
    end
    ns.Print(L.XP_TRAINER_WAY_FAILED:format(tostring(ok and err or done or "?")))
    return false
end
block.GoToTrainer = GoToTrainer

block.actions = function()
    if not MapAPI() then return {} end
    return { { text = L.XP_TRAINER_WAY, fn = GoToTrainer } }
end

block.hints = function()
    local list = { L.XP_HINT_LEFT }
    if MapAPI() then list[#list + 1] = L.XP_TRAINER_HINT_WAY end
    return list
end

local function OnSpellsChanged() ns.QueueUpdate(block) end
ezCore.Listen("SPELLS_KNOWN_CHANGED", OnSpellsChanged, "ezPanel")
ezCore.Listen("SPELLS_TRAINER_CHANGED", OnSpellsChanged, "ezPanel")

---------------------------------------------------------------------------
-- Anzeige
---------------------------------------------------------------------------

function block:GetText()
    local cfg = self.cfg
    if AtMax() then
        if cfg.hideMax then return nil end
        return L.XP_MAX
    end
    local xp, max = ns.Num(UnitXP("player")), ns.Num(UnitXPMax("player"))
    if not xp or not max or max <= 0 then return "?" end
    local rested = ns.Num(GetXPExhaustion()) or 0
    local remaining = max - xp
    local text
    if cfg.show == "remaining" then
        text = ns.Short(remaining)
    elseif cfg.show == "rate" then
        local rate = SessionRate()
        if rate then
            text = L.XP_RATE_SHORT:format(ns.Short(rate), ns.Duration(remaining / rate * 3600, true))
        else
            text = ns.Grey(L.XP_RATE_WAIT)
        end
    elseif cfg.show == "kills" then
        local k = KillsToLevel(remaining, rested, AverageKill())
        text = k and L.XP_KILLS_SHORT:format(ns.Number(k)) or ns.Grey(L.XP_KILLS_WAIT)
    else
        text = ezCore.Percent(xp / max * 100, 1)
    end
    if cfg.rested and rested > 0 then
        text = text .. " " .. ns.BlueCode() .. L.XP_RESTED_SHORT:format(ns.Round(rested / max * 100)) .. "|r"
    end
    if cfg.trainer then
        local n = TrainerRanks()
        if n and n > 0 then text = text .. " " .. ns.GOLD .. L.XP_TRAINER_SHORT:format(n) .. "|r" end
    end
    return text
end

-- Nächster gemerkter Lehrer (laut ezMap), wenn neue Ränge warten – der Text nennt die Quelle (Leitlinie 11).
local function AddNearest(tooltip)
    local t = NearestTrainer()
    if t then ns.TipDoubleLine(tooltip, L.XP_TRAINER_NEAREST, TrainerName(t) .. ", " .. TrainerPlace(t), "normal", "highlight") end
end

local function AddTrainer(tooltip)
    local n, cost, list = TrainerRanks()
    if not n then return end   -- ohne Zauber-Wissen oder ohne lernbaren Rang vor dem Lehrerbesuch: kein Hinweis
    tooltip:AddLine(" ")
    if n == 0 then
        ns.TipDoubleLine(tooltip, L.XP_TRAINER, L.XP_TRAINER_NONE, "normal", "hint")
        return
    end
    if not cost then   -- Lehrer noch nicht besucht: Zahl aus dem Zauberbuch, Kosten unbekannt
        ns.TipDoubleLine(tooltip, L.XP_TRAINER, L.XP_TRAINER_RANKS_NOCOST:format(n), "normal", "highlight")
        AddNearest(tooltip)
        return
    end
    ns.TipDoubleLine(tooltip, L.XP_TRAINER, L.XP_TRAINER_RANKS:format(n, ns.Money(cost)), "normal", "highlight")
    for i, entry in ipairs(list or {}) do
        if i > 8 then
            ns.TipLine(tooltip, ezCore.More(n - 8), "hint")
            break
        end
        local name = entry.rank and entry.rank > 0 and L.XP_TRAINER_RANK:format(entry.name, entry.rank) or entry.name
        ns.TipDoubleLine(tooltip, "  " .. name, ns.Money(entry.cost or 0), "highlight", "highlight")
    end
    AddNearest(tooltip)
end

function block:OnTooltip(tooltip)
    local level = PlayerLevel()
    if AtMax() then
        ns.TipLine(tooltip, L.XP_MAX_TIP, "highlight")
        AddTrainer(tooltip)
        return
    end
    local xp, max = ns.Num(UnitXP("player")) or 0, ns.Num(UnitXPMax("player")) or 1
    local rested = ns.Num(GetXPExhaustion()) or 0
    local remaining = max - xp
    local function Row(left, right) ns.TipDoubleLine(tooltip, left, right, "normal", "highlight") end

    Row(L.LEVEL, level)
    Row(L.XP_CURRENT, ("%s / %s (%s)"):format(ns.Number(xp), ns.Number(max), ezCore.Percent(xp / max * 100, 1)))
    Row(L.XP_REMAINING, ("%s (%s)"):format(ns.Number(remaining), ezCore.Percent(remaining / max * 100, 1)))
    if rested > 0 then
        local state = IsResting() and L.XP_RESTING_NOW or ""
        Row(L.XP_RESTED, ns.BlueCode() .. ("%s (%s)|r %s"):format(ns.Number(rested), ezCore.Percent(rested / max * 100), state))
    else
        Row(L.XP_RESTED, IsResting() and L.XP_RESTING_NOW or "0")
    end

    tooltip:AddLine(" ")
    local s = ns.session
    local elapsed = time() - ns.SessionStart()
    Row(L.SESSION, ns.Duration(elapsed, true))
    Row(L.XP_GAINED, ns.Number(s.xp or 0))
    local rate = SessionRate()
    if rate then
        Row(L.XP_PER_HOUR, ns.Number(rate))
        Row(L.XP_TIME_TO_LEVEL, ns.Duration(remaining / rate * 3600, true))
    end
    local levelRate = LevelRate()
    if levelRate then
        Row(L.XP_PER_HOUR_LEVEL, ns.Number(levelRate))
        Row(L.XP_TIME_TO_LEVEL_LEVEL, ns.Duration(remaining / levelRate * 3600, true))
    end
    local avg = AverageKill()
    if avg then
        Row(L.XP_KILL_AVG, ns.Number(avg))
        Row(L.XP_KILLS_TO_LEVEL, ns.Number(KillsToLevel(remaining, rested, avg)))
    end
    if lastGain and lastGain > 0 then
        Row(L.XP_GAINS_TO_LEVEL, ns.Number(math.ceil(remaining / lastGain)))
    end
    AddTrainer(tooltip)
end

local ORDER = { percent = "remaining", remaining = "rate", rate = "kills", kills = "percent" }

function block:OnClick(button)
    if button == "LeftButton" then self.cfg.show = ORDER[self.cfg.show] or "percent" end
end

function block:OnMenu(root)
    local cfg = self.cfg
    local bar = root:CreateButton(L.MENU_BAR_SHOWS)
    ns.MenuRadio(bar, L.XP_SHOW_PERCENT, cfg, "show", "percent", self)
    ns.MenuRadio(bar, L.XP_SHOW_REMAINING, cfg, "show", "remaining", self)
    ns.MenuRadio(bar, L.XP_SHOW_RATE, cfg, "show", "rate", self)
    ns.MenuRadio(bar, L.XP_SHOW_KILLS, cfg, "show", "kills", self)
    ns.MenuCheck(root, L.XP_SHOW_RESTED, cfg, "rested", self)
    ns.MenuCheck(root, L.XP_HIDE_MAX, cfg, "hideMax", self)
    ns.MenuCheck(root, L.XP_SHOW_TRAINER, cfg, "trainer", self)
    if RequestTimePlayed then
        root:CreateButton(L.MENU_REQUEST_PLAYED, function() RequestTimePlayed() end)
    end
    root:CreateButton(L.MENU_RESET_SESSION, function()
        ns.NewSession()
        wipe(kills)
        ns.UpdateAllBlocks()
        ns.Print(L.SESSION_RESET)
    end)
end
