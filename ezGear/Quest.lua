local _, ns = ...

--[[
    Questbelohnung (Questgeber und Questlog): grüner Pfeil auf jeder Belohnung, die „besser“ ist (roter Pfeil nach
    unten, wenn tragbar und schlechter; Schalter downArrows), und das Gold-Symbol
    auf der Wahl-Belohnung mit dem höchsten Verkaufswert.

    Hook hinter QuestInfo_Display, nicht hinter QuestInfo_ShowRewards: Blizzards Vorlagen (QUEST_TEMPLATE_*) halten
    die ursprüngliche Funktion fest, ein Hook am globalen Namen käme dort nie an. Die Knöpfe sind Blizzards
    rewardsFrame.RewardButtons; ezGear liest nur ihre Felder type/objectType/GetID und legt eigene Texturen an.
    ezQuest fragt dieselbe Bewertung über ezCore.API("ezGear").BestRewardIndex().
]]

local Quest = {}
ns.Quest = Quest

local generation = 0
local MAX_TRIES = 5

local function RewardButtons()
    local frame = QuestInfoFrame and QuestInfoFrame.rewardsFrame
    return frame and frame.RewardButtons
end

local function IsQuestLog()
    return QuestInfoFrame and QuestInfoFrame.questLog and true or false
end

local function LinkAndCount(button)
    local kind = button.type
    local id = ns.Call(button.GetID, button)
    if not (kind and id) then return nil end
    local link, count
    if IsQuestLog() then
        link = ns.Call(GetQuestLogItemLink, kind, id)
        local fn = kind == "choice" and GetQuestLogChoiceInfo or GetQuestLogRewardInfo
        local _, _, c = ns.Call(fn, id)
        count = c
    else
        link = ns.Call(GetQuestItemLink, kind, id)
        local _, _, c = ns.Call(GetQuestItemInfo, kind, id)
        count = c
    end
    link, count = ns.Plain(link), ns.Plain(count)
    if type(link) ~= "string" then link = nil end
    return link, tonumber(count) or 1
end

function Quest.Update(tries, gen)
    if gen and gen ~= generation then return end   -- inzwischen eine andere Quest
    local buttons = RewardButtons()
    if type(buttons) ~= "table" then return end
    -- Ein gemeinsamer Index n für alle drei Listen: fehlt einer Wahl der Link (Daten noch nicht da), bleibt in
    -- choices eine Lücke, statt dass die Listen gegeneinander verrutschen (BestOf verträgt Lücken).
    local choices, counts, choiceButtons, n = {}, {}, {}, 0
    local waiting, missing = false, false
    for _, button in ipairs(buttons) do
        ns.Marks.SetUpgrade(button, nil)      -- leert auch, was am wiederverwendeten Knopf noch auf Daten wartet
        ns.Marks.SetValue(button, false)
        local shown = button.IsShown and button:IsShown()
        if shown and button.objectType == "item" and (button.type == "choice" or button.type == "reward") then
            local link, count = LinkAndCount(button)
            if ns.Active("questArrows") and link then
                if ns.Marks.SetUpgrade(button, link, button.Icon) == nil then waiting = true end
            end
            if not link then waiting = true end   -- Link kommt nach: später erneut versuchen
            if button.type == "choice" then
                n = n + 1
                choices[n], counts[n], choiceButtons[n] = link, count, button
                if not link then missing = true end
            end
        end
    end
    if ns.Active("questCoin") and n >= 2 then
        local _, valueIndex, pending = ns.Score.BestOf(choices, counts, n)
        -- solange eine Wahl noch keinen Link hat, steht das wertvollste nicht fest: kein Gold-Symbol
        local button = valueIndex and not missing and choiceButtons[valueIndex]
        if button then ns.Marks.SetValue(button, true, button.Icon) end
        if pending then waiting = true end
    end
    tries = tries or 0
    if waiting and tries < MAX_TRIES then
        local g = generation
        C_Timer.After(0.5, function() ns.Try("Quest", Quest.Update, tries + 1, g) end)
    end
end

local function OnDisplay()
    generation = generation + 1
    Quest.Update(0, generation)
end

local function Install()
    if type(QuestInfo_Display) ~= "function" then return false end
    hooksecurefunc("QuestInfo_Display", function() ns.Try("Quest", OnDisplay) end)
    return true
end

ns.OnReady(function()
    if not Install() then ns.WhenAddOnLoaded("Blizzard_UIPanels_Game", Install) end
    local function Refresh()
        if QuestInfoFrame and QuestInfoFrame.IsVisible and QuestInfoFrame:IsVisible() then OnDisplay() end
    end
    ns.Listen("SCORES_CHANGED", Refresh)
    ezCore.Listen("GLOW_MARKS_CHANGED", Refresh, "ezGear")
    ns.OnSettingChanged(function(key)
        if key == "questArrows" or key == "questCoin" then Refresh() end
    end)
end)
