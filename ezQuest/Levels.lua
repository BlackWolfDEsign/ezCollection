local ADDON, ns = ...
local Core = ezCore

--[[
    Stufe vor den Quests in den NPC-Dialogen: „[12] Titel“. Questlog und Verfolgung zeigen sie auf Forever
    schon selbst (Blizzards Camelot-Override GetQuestTitlePrefix), in der Gossip- und Begrüßungsliste fehlt sie.
    Taint-sicher: hooksecurefunc nach Blizzards Setup, dann Blizzards eigene Funktion mit dem neuen Titel –
    so bleiben graue und ignorierte Quests so formatiert wie bei Blizzard. Nichts wird in Blizzards Tabellen
    geschrieben. Dazu die Tönung neuer Forever-Quests (Tint.Row).
]]

local Levels = {}
ns.Levels = Levels

local Plain = Core.Plain   -- geheime Werte → nil (eine Fassung in ezCore, V-133)

-- Gossip-Knopf (GossipAvailableQuestButtonMixin/GossipActiveQuestButtonMixin): questInfo aus C_GossipInfo.
function Levels.DecorateGossip(button, questInfo)
    if type(questInfo) ~= "table" then return end
    local questID = Core.Num(questInfo.questID)
    local title = Plain(questInfo.title)
    if ns.Enabled("levelInDialogs") and type(title) == "string" and type(button.UpdateTitleForQuest) == "function" then
        local prefix = ns.LevelPrefix(questInfo.questLevel, questID)
        if prefix then
            button:UpdateTitleForQuest(questID, prefix .. title, questInfo.isIgnored, questInfo.isTrivial)
        end
    end
    ns.Tint.Row(button, questID)
end

-- Hook auf die Mixins, bevor Blizzard die Knöpfe beim ersten Gespräch anlegt (Mixin kopiert die Funktion).
function Levels.HookGossip()
    local hooked = 0
    for _, name in ipairs({ "GossipAvailableQuestButtonMixin", "GossipActiveQuestButtonMixin" }) do
        local mixin = rawget(_G, name)
        if type(mixin) == "table" and type(mixin.Setup) == "function" then
            hooksecurefunc(mixin, "Setup", function(button, questInfo)
                ns.Try("Gossip", Levels.DecorateGossip, button, questInfo)
            end)
            hooked = hooked + 1
        end
    end
    return hooked
end

local Call = Core.Call   -- geschützt, verträgt fehlende Funktionen

-- Begrüßungsliste (QUEST_GREETING): Blizzard füllt die Knöpfe aus einem Pool; ezQuest setzt den Titel
-- jedes Mal aus Blizzards Daten neu – zweimal aufgerufen ergibt dasselbe.
function Levels.DecorateGreeting()
    local panel = rawget(_G, "QuestFrameGreetingPanel")
    local pool = panel and panel.titleButtonPool
    if not (pool and pool.EnumerateActive) then return end
    for button in pool:EnumerateActive() do
        local index = button:GetID()
        local title, level, questID
        if button.isActive == 1 then
            title = Call(rawget(_G, "GetActiveTitle"), index)
            level = Call(rawget(_G, "GetActiveLevel"), index)
            questID = Call(rawget(_G, "GetActiveQuestID"), index)
        else
            title = Call(rawget(_G, "GetAvailableTitle"), index)
            level = Call(rawget(_G, "GetAvailableLevel"), index)
            questID = select(5, Call(rawget(_G, "GetAvailableQuestInfo"), index))
        end
        title = Plain(title)
        if ns.Enabled("levelInDialogs") and type(title) == "string" then
            local prefix = ns.LevelPrefix(level, questID)
            if prefix then
                button:SetText(prefix .. title)
                local iconHeight = button.Icon and button.Icon:GetHeight() or 0
                button:SetHeight(math.max(button:GetTextHeight() + 2, iconHeight))
            end
        end
        ns.Tint.Row(button, questID)
    end
end

function Levels.HookGreeting()
    local function Run() ns.Try("Greeting", Levels.DecorateGreeting) end
    -- Die XML-Vorlage ruft die Funktion beim Zeigen direkt, QUEST_LOG_UPDATE über den globalen Namen.
    local panel = rawget(_G, "QuestFrameGreetingPanel")
    if type(panel) == "table" and panel.HookScript then panel:HookScript("OnShow", Run) end
    if type(rawget(_G, "QuestFrameGreetingPanel_OnShow")) == "function" then
        hooksecurefunc("QuestFrameGreetingPanel_OnShow", Run)
    end
end

-- Gleich beim Laden: Blizzards Gossip-Knöpfe entstehen erst beim ersten Gespräch.
ns.Try("Levels", function()
    if Levels.HookGossip() == 0 then ns.OnReady(Levels.HookGossip) end
end)
ns.OnReady(function() ns.Try("Levels", Levels.HookGreeting) end)
