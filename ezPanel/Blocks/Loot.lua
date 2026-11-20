local _, ns = ...
local L = ns.L

--[[
    Beute (Titan LootType): Plündermethode und -schwelle der Gruppe, Würfeln,
    Würfelergebnisse der Gruppe, Instanzen zurücksetzen.
    Verbesserungen: Plündermeister wird mit der neuen API richtig erkannt
    (Enum 2, nicht 3), Würfelrunden verschwinden nicht bei jedem
    Ladebildschirm, Würfe außerhalb 1–100 werden markiert statt gezählt.
    Würfelergebnisse stehen im Tooltip – ohne zusätzliches Fenster.
    Den ganzen Beute-Verlauf (Fenster mit Suche) bietet ezLoot an: ezCore.API("ezLoot").ToggleHistory
    bzw. ShowHistory – Menüeintrag und Shift+Linksklick, nur wenn ezLoot es anbietet (abgestimmt 13.11.2026).
]]

-- Beute-Verlauf von ezLoot öffnen/schließen; nil, solange ezLoot ihn nicht anbietet.
local function LootHistoryFn()
    local api = ezCore.API("ezLoot")
    local fn = api and (api.ToggleHistory or api.ShowHistory)
    return type(fn) == "function" and fn or nil
end

local function OpenLootHistory()
    local fn = LootHistoryFn()
    if not fn then return false end
    local ok, err = pcall(fn)
    if not ok then geterrorhandler()(err) end
    return ok
end

local block = ns.RegisterBlock({
    id = "loot",
    command = "beute",
    name = L.LOOT_NAME,
    label = L.LOOT_LABEL,
    icon = "Interface\\Icons\\INV_Misc_Bag_10_Blue",
    events = { "GROUP_ROSTER_UPDATE", "PARTY_LOOT_METHOD_CHANGED", "PARTY_LEADER_CHANGED", "PLAYER_ENTERING_WORLD" },
    colorable = true,
    defaults = {
        history = true,       -- zuletzt geplündert (Daten: ezCore.History)
        enabled = false, zone = "right", order = 40,
        hideSolo = false,
    },
    hints = function()
        local list = { L.LOOT_HINT_LEFT }
        if LootHistoryFn() then list[#list + 1] = ezCore.ClickText("left", "SHIFT", L.LOOT_HINT_SHIFT) end   -- T18-9
        return list
    end,
})

-- Neue API (Zahl) und alte (Text) auf einen Schlüssel abbilden.
local BY_NUMBER = { [0] = "freeforall", [1] = "roundrobin", [2] = "master", [3] = "group", [4] = "needbeforegreed", [5] = "personalloot" }
local NUMBER_OF = { freeforall = 0, roundrobin = 1, master = 2, group = 3, needbeforegreed = 4, personalloot = 5 }
local METHOD_TEXT = {
    freeforall = LOOT_FREE_FOR_ALL, roundrobin = LOOT_ROUND_ROBIN, master = LOOT_MASTER_LOOTER,
    group = LOOT_GROUP_LOOT, needbeforegreed = LOOT_NEED_BEFORE_GREED, personalloot = LOOT_PERSONAL_LOOT,
}

local function Method()
    if C_PartyInfo and C_PartyInfo.GetLootMethod then
        local ok, method, partyMaster, raidMaster = pcall(C_PartyInfo.GetLootMethod)
        if ok and method ~= nil then
            if type(method) == "number" then method = BY_NUMBER[method] end
            return method, partyMaster, raidMaster
        end
    end
    if GetLootMethod then return GetLootMethod() end
    return nil
end

local function MethodText(method)
    return (method and (METHOD_TEXT[method] or L["LOOT_" .. method])) or "?"
end

local function Threshold()
    local q = GetLootThreshold and GetLootThreshold()
    return ns.Num(q)
end

local function QualityText(q)
    if not q then return "?" end
    return ezCore.QualityText(q)   -- Name und Farbe aus ezCore (Gesamtreview 18.11.2026, T16-6)
end

local function IsLeader()
    return UnitIsGroupLeader and UnitIsGroupLeader("player")
end

---------------------------------------------------------------------------
-- Würfeln
---------------------------------------------------------------------------

local rolls = {}          -- { name, roll, low, high, time }
local ROUND_GAP = 60

local rollPattern
local function RollPattern()
    if rollPattern ~= nil then return rollPattern end
    -- Eine Fassung für alle Module: ezCore.FormatToPattern (versteht auch Platznummern wie %1$s).
    rollPattern = ezCore.FormatToPattern(RANDOM_ROLL_RESULT) or false
    return rollPattern
end

ns.On("CHAT_MSG_SYSTEM", function(_, msg)
    if type(msg) ~= "string" or ns.IsSecret(msg) then return end
    local pattern = RollPattern()
    if not pattern then return end
    local name, roll, low, high = msg:match(pattern)
    roll, low, high = tonumber(roll), tonumber(low), tonumber(high)
    if not name or name == "" or not roll then return end
    local now = GetTime()
    local last = rolls[#rolls]
    if last and now - last.time > ROUND_GAP then wipe(rolls) end
    for _, r in ipairs(rolls) do
        if r.name == name then
            r.rerolls = (r.rerolls or 0) + 1     -- nur der erste Wurf zählt
            return ns.QueueUpdate(block)
        end
    end
    table.insert(rolls, { name = name, roll = roll, low = low, high = high, time = now })
    ns.QueueUpdate(block)
end)

local function SortedRolls()
    local list = {}
    for _, r in ipairs(rolls) do list[#list + 1] = r end
    table.sort(list, function(a, b)
        local fa, fb = a.low == 1 and a.high == 100, b.low == 1 and b.high == 100
        if fa ~= fb then return fa end
        if a.roll ~= b.roll then return a.roll > b.roll end
        return a.time < b.time
    end)
    return list
end

---------------------------------------------------------------------------
-- Anzeige
---------------------------------------------------------------------------

function block:GetText()
    if not IsInGroup() then
        if self.cfg.hideSolo then return nil end
        return ns.Grey(L.LOOT_SOLO)
    end
    local method = Method()
    local q = Threshold()
    local text = MethodText(method)
    if q then text = ezCore.QualityHex(q) .. text .. "|r" end
    return text
end

function block:OnTooltip(tooltip)
    if IsInGroup() then
        local method, partyMaster, raidMaster = Method()
        ns.TipDoubleLine(tooltip, L.LOOT_METHOD, MethodText(method), "normal", "highlight")
        tooltip:AddDoubleLine(L.LOOT_THRESHOLD, QualityText(Threshold()))
        if method == "master" then
            local unit = raidMaster and ("raid" .. raidMaster) or (partyMaster == 0 and "player") or (partyMaster and "party" .. partyMaster)
            local name = unit and ezCore.Plain((UnitName(unit)))   -- gesperrter Name: keine Zeile (V-184)
            if type(name) == "string" and name ~= "" then ns.TipDoubleLine(tooltip, L.LOOT_MASTER, name, "normal", "highlight") end
        end
    else
        ns.TipLine(tooltip, L.LOOT_SOLO_TIP, "highlight", true)
    end

    if self.cfg.history then self:AddHistory(tooltip) end

    local list = SortedRolls()
    if #list == 0 and IsInGroup() then
        tooltip:AddLine(" ")
        ns.TipLine(tooltip, L.LOOT_ROLLS, "normal")
        ns.TipLine(tooltip, L.LOOT_ROLLS_NONE, "hint", true)
    end
    if #list > 0 then
        tooltip:AddLine(" ")
        ns.TipLine(tooltip, L.LOOT_ROLLS, "normal")
        for i, r in ipairs(list) do
            local fair = r.low == 1 and r.high == 100
            local name = r.name
            if r.rerolls then name = name .. ns.Grey(" [" .. r.rerolls + 1 .. "]") end
            local right = fair and tostring(r.roll) or (ns.RED .. r.roll .. " (" .. r.low .. "-" .. r.high .. ")|r")
            if i == 1 and fair then
                tooltip:AddDoubleLine(ns.GREEN .. name .. "|r", ns.GREEN .. right .. "|r")
            else
                ns.TipDoubleLine(tooltip, name, right, "highlight", "highlight")
            end
        end
    end
end

function block:OnClick(button)
    if button ~= "LeftButton" then return end
    if IsShiftKeyDown() and OpenLootHistory() then return end
    if RandomRoll then
        RandomRoll(1, 100)
    elseif C_RandomRoll and C_RandomRoll.RandomRoll then
        C_RandomRoll.RandomRoll(1, 100)
    end
end

local function SetMethod(method)
    if C_PartyInfo and C_PartyInfo.SetLootMethod then
        local ok = pcall(C_PartyInfo.SetLootMethod, NUMBER_OF[method], method == "master" and UnitName("player") or nil)
        if ok then return end
    end
    if SetLootMethod then SetLootMethod(method, method == "master" and UnitName("player") or nil) end
end

-- Instanzen zurücksetzen nach Rückfrage (Dialog von ezCore, mit Warnsymbol).
local function AskResetInstances()
    ezCore.Confirm(L.LOOT_RESET_CONFIRM, function() ResetInstances() end, { alert = true })
end

local function AnnounceWinner()
    local list = SortedRolls()
    local best = list[1]
    if not best or not (best.low == 1 and best.high == 100) then return end
    -- Gruppenkanal (Schlachtzug, Instanz, Gruppe) und Chat-Sperre prüft ezCore
    ezCore.SendChat(L.LOOT_WINNER:format(best.name, best.roll), "GROUP")
end

-- Zuletzt geplündert und Münzen der letzten 24 Stunden (ezCore erfasst, ezPanel zeigt an).
function block:AddHistory(tooltip)
    local history = ezCore.History
    if not (history and type(history.List) == "function") then return end
    local list = history.List("loot", { char = ns.charKey, limit = 8, match = function(e) return type(e.link) == "string" end })
    local money = history.Sum("loot", "money", { char = ns.charKey, since = history.Since("day") })
    tooltip:AddLine(" ")
    ns.TipLine(tooltip, L.LOOT_HISTORY, "normal")
    if #list == 0 and money <= 0 then
        ns.TipLine(tooltip, L.LOOT_HISTORY_NONE, "hint", true)   -- Leertext mit Erklärung (PANEL-17)
        return
    end
    for _, e in ipairs(list) do
        local n = ns.Num(e.n) or 1
        local left = e.link .. (n > 1 and (" x" .. n) or "")
        -- Symbol des Gegenstands davor (ezCores Helfer, Wunsch vom 18.11.2026 „mit den item icons“)
        if type(ezCore.ItemIconText) == "function" then left = ezCore.ItemIconText(e.link, left) end
        local src = e.roll and L.LOOT_HISTORY_ROLL or (type(e.src) == "table" and type(e.src.name) == "string" and e.src.name) or nil
        ns.TipDoubleLine(tooltip, left, ns.Grey(src or ns.Ago(e.t)), "highlight", "highlight")
    end
    if money > 0 then ns.TipDoubleLine(tooltip, L.LOOT_HISTORY_MONEY, ns.Money(money), "normal", "highlight") end
end

ezCore.Listen("HISTORY_ADDED", function(kind)
    if kind == "loot" then ns.QueueUpdate(block) end
end, "ezPanel")

function block:OnMenu(root)
    local cfg = self.cfg
    if IsInGroup() and IsLeader() then
        local current = Method()
        local m = root:CreateButton(L.LOOT_METHOD)
        for _, method in ipairs({ "group", "needbeforegreed", "freeforall", "roundrobin", "master" }) do
            m:CreateRadio(MethodText(method), function() return current == method end, function()
                SetMethod(method)
                C_Timer.After(0.3, function() ns.QueueUpdate(self) end)
            end, method)
        end
        local t = root:CreateButton(L.LOOT_THRESHOLD)
        local q = Threshold()
        for quality = 2, 5 do
            t:CreateRadio(QualityText(quality), function() return q == quality end, function()
                if SetLootThreshold then SetLootThreshold(quality) end
                C_Timer.After(0.3, function() ns.QueueUpdate(self) end)
            end, quality)
        end
    end
    if #rolls > 0 then
        root:CreateButton(L.LOOT_ANNOUNCE, AnnounceWinner)
        root:CreateButton(L.LOOT_CLEAR, function()
            wipe(rolls)
            ns.QueueUpdate(self)
        end)
    end
    if ResetInstances and (not IsInGroup() or IsLeader()) then
        -- ezCores Dialog statt Blizzards CONFIRM_RESET_INSTANCES: so bleibt dessen Popup unberührt (kein Taint).
        root:CreateButton(L.LOOT_RESET_INSTANCES, AskResetInstances)
    end
    ns.MenuCheck(root, L.LOOT_HIDE_SOLO, cfg, "hideSolo", self)
    ns.MenuCheck(root, L.LOOT_SHOW_HISTORY, cfg, "history", self)
    if LootHistoryFn() then root:CreateButton(L.LOOT_OPEN_HISTORY, OpenLootHistory) end
end
