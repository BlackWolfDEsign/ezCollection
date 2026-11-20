local ADDON, ns = ...
local Core = ezCore

--[[
    Funkeln an Quest-Gegenständen im Beutefenster (Wunsch des Nutzers vom 15.11.2026). Aussehen, Regel und Schalter
    („Quest-Gegenstände im Beutefenster funkeln“) liegen an einer Stelle in ezQuest (ezQuest/Shine.lua,
    ezCore.API("ezQuest").QuestShine); ezLoot reicht nur den Platzknopf, den Gegenstand und Blizzards Angabe zum Platz
    (GetLootSlotInfo: isQuestItem, questID, isActive – dieselben Werte, mit denen Blizzard den Quest-Rand
    IconQuestTexture setzt) weiter. Gerufen aus Frames.DecorateLootElement bei jedem Füllen eines Elements; Blizzard
    verwendet die Elemente wieder, darum wird das Funkeln jedes Mal gesetzt oder gelöscht. Ohne ezQuest funkelt nichts.
]]

local failed = false   -- ein Fehler in ezQuest wird einmal gemeldet, danach ruft ezLoot nicht mehr

-- Blizzards Angabe zum Beuteplatz (nil bei gesperrten Werten oder ohne Platz)
function ns.LootQuestInfo(slot)
    if ns.IsSecret(slot) or type(slot) ~= "number" or type(GetLootSlotInfo) ~= "function" then return nil end
    local ok, texture, _, _, _, _, _, isQuestItem, questID, isActive = pcall(GetLootSlotInfo, slot)
    if not ok or ns.IsSecret(texture) or texture == nil then return nil end   -- leerer Platz
    if ns.IsSecret(isQuestItem) or ns.IsSecret(questID) or ns.IsSecret(isActive) then return nil end
    return { isQuestItem = isQuestItem == true, questID = Core.Num(questID), isActive = isActive == true }
end

-- → true, wenn der Knopf jetzt funkelt; link = nil löscht das Funkeln
function ns.QuestShine(button, slot, link)
    if failed or type(button) ~= "table" then return false end
    local api = Core.API("ezQuest")
    if not (type(api) == "table" and type(api.QuestShine) == "function") then return false end
    local itemID = link and Core.ItemID(link) or nil
    local ok, shown = pcall(api.QuestShine, button, "loot", itemID, link, itemID and ns.LootQuestInfo(slot) or nil)
    if not ok then
        failed = true
        Core.Error("ezQuest", shown, "QuestShine (" .. ADDON .. ")")
        return false
    end
    return shown == true
end

-- ezQuest meldet geänderte Quest-Gegenstände oder einen umgelegten Schalter: offenes Beutefenster neu zeichnen.
Core.Listen("EZQUEST_ITEMS_CHANGED", function()
    if ns.Frames and ns.Frames.RefreshLootFrame then ns.Frames.RefreshLootFrame() end
end, ADDON)
