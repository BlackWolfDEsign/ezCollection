local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Quests automatisch annehmen und abgeben, sichtbarer Schalter oben rechts im
    Questfenster und im Gossip-Fenster, Shift beim Ansprechen hält an.
    Nie automatisch: Quests, die Gold kosten, von Spielern geteilte Quests, graue Quests (außer „auch graue
    Quests“ ist an), wiederholbare Quests (außer „auch wiederholbare Quests“ ist an – sie verbrauchen bei jedem
    Ansprechen Gegenstände und versperren sonst die übrigen Optionen des NPCs). Bei mehreren Belohnungen wählt der Spieler – außer „Belohnung automatisch wählen“ ist an:
    dann nimmt ezQuest, was ezGear empfiehlt (besser, sonst höchster Verkaufswert; dieselbe Bewertung, die ezGear
    als Pfeil und Gold-Symbol zeigt). Ohne ezGear oder solange dessen Daten laden, bleibt die Wahl beim Spieler.
    Nimmt Questie bzw. Leatrix Plus schon automatisch an oder gibt ab, hält sich ezQuest bei diesem Teil zurück;
    der Schalter zeigt das im Tooltip. Wahrheitswerte der API laufen über Core.Bool (nie geheim vergleichen).
]]

local Auto = {}
ns.Auto = Auto

local switches = {}   -- eigene Häkchen im Quest- und Gossip-Fenster

local Call = Core.Call   -- geschützt, verträgt fehlende Funktionen
local function G(name) return rawget(_G, name) end
local function Yes(value) return Core.Bool(value, false) end

function Auto.Paused()
    return Yes(Call(G("IsShiftKeyDown")))
end

-- part: "questAccept" oder "questTurnIn" (Funktionen wie in ezCore.WhoHandles). Rückgabe: aktiv?
function Auto.On(part)
    return ns.Enabled("autoQuest") and not ns.OtherHandles(part) and not Auto.Paused()
end

-- Von einem Spieler geteilt? Dann entscheidet der Spieler selbst. Core.UnitIs: existiert und ist Spieler;
-- gesperrt oder unbekannt (nil) heißt wie bisher nein (EC-84).
local function FromPlayer()
    return Core.UnitIs("questnpc") == true
end

local function Trivial(questID)
    if not Core.Num(questID) or not (C_QuestLog and C_QuestLog.IsQuestTrivial) then return false end
    return Yes(Call(C_QuestLog.IsQuestTrivial, questID))
end

-- Belohnung, die ezGear empfiehlt: besser, sonst höchster Verkaufswert. nil = keine Empfehlung (oder lädt noch).
function Auto.RecommendedReward()
    if not ns.Enabled("autoReward") then return nil end
    local gear = Core.API("ezGear")
    if not (gear and type(gear.BestRewardIndex) == "function") then return nil end
    local upgrade, value, pending = Call(gear.BestRewardIndex)
    if pending then return nil end
    return Core.Num(upgrade) or Core.Num(value)
end

-- Wiederholbare Quest (Spenden, Ruf)? Nur mit „auch wiederholbare Quests“ automatisch. flag: Angabe aus der
-- Liste des NPCs (Gossip `repeatable`, Begrüßung dritte Rückgabe von GetAvailableQuestInfo), sonst fragt die
-- Quest-ID Blizzards Questlog.
function Auto.SkipRepeatable(flag, questID)
    if ns.Enabled("autoRepeatable") then return false end
    if Yes(flag) then return true end
    if not Core.Num(questID) or not (C_QuestLog and C_QuestLog.IsRepeatableQuest) then return false end
    return Yes(Call(C_QuestLog.IsRepeatableQuest, questID))
end

local function CostsMoney()
    local money = Core.Num(Call(G("GetQuestMoneyToGet")))
    return money ~= nil and money > 0
end

---------------------------------------------------------------------------
-- Questfenster
---------------------------------------------------------------------------

function Auto.OnDetail()
    if not Auto.On("questAccept") or FromPlayer() then return end
    if Yes(Call(G("QuestGetAutoAccept"))) then return end         -- schon angenommen (Blizzard zeigt es an)
    local questID = Call(G("GetQuestID"))
    if not ns.Enabled("autoTrivial") and Trivial(questID) then return end
    if Auto.SkipRepeatable(nil, questID) then return end
    Call(G("AcceptQuest"))
end

function Auto.OnProgress()
    if not Auto.On("questTurnIn") or CostsMoney() then return end
    if Auto.SkipRepeatable(nil, Call(G("GetQuestID"))) then return end
    if Yes(Call(G("IsQuestCompletable"))) then Call(G("CompleteQuest")) end
end

function Auto.OnComplete()
    if not Auto.On("questTurnIn") or CostsMoney() then return end
    if Auto.SkipRepeatable(nil, Call(G("GetQuestID"))) then return end
    local choices = Core.Num(Call(G("GetNumQuestChoices"))) or 0
    if choices > 1 then
        local index = Auto.RecommendedReward()
        if index and index >= 1 and index <= choices then Call(G("GetQuestReward"), index) end
        return                                                    -- sonst wählt der Spieler selbst
    end
    Call(G("GetQuestReward"), choices == 1 and 1 or 0)
end

-- Begrüßungsliste: zuerst fertige Quests abgeben, dann neue annehmen.
function Auto.OnGreeting()
    if Auto.On("questTurnIn") then
        for i = 1, Core.Num(Call(G("GetNumActiveQuests"))) or 0 do
            local _, isComplete = Call(G("GetActiveTitle"), i)
            if Yes(isComplete) then Call(G("SelectActiveQuest"), i) return end
        end
    end
    if Auto.On("questAccept") then
        for i = 1, Core.Num(Call(G("GetNumAvailableQuests"))) or 0 do
            local isTrivial, _, isRepeatable, _, questID = Call(G("GetAvailableQuestInfo"), i)
            if (ns.Enabled("autoTrivial") or not Yes(isTrivial)) and not Auto.SkipRepeatable(isRepeatable, questID) then
                Call(G("SelectAvailableQuest"), i)
                return
            end
        end
    end
end

-- Gossip: dasselbe über C_GossipInfo.
function Auto.OnGossip()
    local gossip = C_GossipInfo
    if type(gossip) ~= "table" then return end
    if Auto.On("questTurnIn") then
        for _, quest in ipairs(Call(gossip.GetActiveQuests) or {}) do
            local questID = Core.Num(quest.questID)
            if Yes(quest.isComplete) and questID then Call(gossip.SelectActiveQuest, questID) return end
        end
    end
    if Auto.On("questAccept") then
        for _, quest in ipairs(Call(gossip.GetAvailableQuests) or {}) do
            local questID = Core.Num(quest.questID)
            if questID and not Yes(quest.isIgnored) and (ns.Enabled("autoTrivial") or not Yes(quest.isTrivial))
                and not Auto.SkipRepeatable(quest.repeatable, questID) then
                Call(gossip.SelectAvailableQuest, questID)
                return
            end
        end
    end
end

---------------------------------------------------------------------------
-- Sichtbarer Schalter: Häkchen „Automatisch“ oben rechts im Quest- und Gossip-Fenster
---------------------------------------------------------------------------

local function ShowSwitchTip(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    Core.TipTitle(GameTooltip, L.OPT_autoQuest)
    GameTooltip:AddLine(L.OPT_autoQuest_TIP, nil, nil, nil, true)
    local accept, turnIn = ns.OtherHandles("questAccept"), ns.OtherHandles("questTurnIn")
    if accept and accept == turnIn then
        Core.TipLine(GameTooltip, L.AUTO_OTHER_BOTH:format(accept, accept), "orange", true)
    else
        if accept then Core.TipLine(GameTooltip, L.AUTO_OTHER_ACCEPT:format(accept), "orange", true) end
        if turnIn then Core.TipLine(GameTooltip, L.AUTO_OTHER_TURNIN:format(turnIn), "orange", true) end
    end
    Core.TipLine(GameTooltip, L.AUTO_ALSO, "hint", true)
    Core.TipClick(GameTooltip, L.TIP_COMMAND:format(ns.SlashCmd("auto")))
    GameTooltip:Show()
end

function Auto.UpdateSwitches()
    local blocked = ns.OtherHandles("questAccept") and ns.OtherHandles("questTurnIn")
    for _, check in ipairs(switches) do
        check:SetChecked(ns.Enabled("autoQuest"))
        check.label:SetTextColor(blocked and 0.5 or 1, blocked and 0.5 or 0.82, blocked and 0.5 or 0)
    end
end

function Auto.CreateSwitch(parent)
    if type(parent) ~= "table" then return nil end
    local check = Core.CreateCheck(parent, 22)
    check:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, -28)
    check:SetFrameLevel((parent:GetFrameLevel() or 1) + 5)
    check.label = check:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    check.label:SetPoint("RIGHT", check, "LEFT", -1, 0)
    check.label:SetText(L.AUTO_SWITCH)
    check:SetScript("OnClick", function(self)
        ns.SetSetting("autoQuest", self:GetChecked() and true or false)
        ShowSwitchTip(self)
    end)
    check:SetScript("OnEnter", ShowSwitchTip)
    check:SetScript("OnLeave", function() GameTooltip:Hide() end)
    check:SetScript("OnShow", Auto.UpdateSwitches)
    switches[#switches + 1] = check
    Auto.UpdateSwitches()
    return check
end

function Auto.Switches() return switches end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------

ns.OnReady(function()
    ns.Try("Auto", function()
        Auto.CreateSwitch(rawget(_G, "QuestFrame"))
        Auto.CreateSwitch(rawget(_G, "GossipFrame"))
    end)
    ns.On("QUEST_DETAIL", Auto.OnDetail)
    ns.On("QUEST_PROGRESS", Auto.OnProgress)
    ns.On("QUEST_COMPLETE", Auto.OnComplete)
    ns.On("QUEST_GREETING", Auto.OnGreeting)
    ns.On("GOSSIP_SHOW", Auto.OnGossip)
end)

ns.OnSettingChanged(function(key)
    if key == "autoQuest" then Auto.UpdateSwitches() end
end)

-- Hinweis am Questfenster (ezCores Hinweis-Helfer, einmal je Account; Gegenprüfung des Pakets P17 zu T1-3, Entscheidung 2
-- des Nutzers vom 18.11.2026: Hinweis auch für Abläufe ohne Klick, die nie ab Werk an waren, sofern sie senden):
-- „Automatisch annehmen und abgeben“ schickt Annehmen und Abgeben ohne Klick an den Server. Nicht, solange andere Addons
-- beides schon erledigen (Questie, Leatrix Plus); der Pfeil zeigt auf das Häkchen „Automatisch“ oben rechts.
function Auto.RegisterOptInHint()
    local Hint = Core.OptInHint
    if not (Hint and Hint.RegisterSetting) then return false end
    return Hint.RegisterSetting(ADDON, ns, "autoQuest", {
        window = "quest",
        applies = function() return not (ns.OtherHandles("questAccept") and ns.OtherHandles("questTurnIn")) end,
        target = function() return switches[1] end,
    })
end
Auto.RegisterOptInHint()
