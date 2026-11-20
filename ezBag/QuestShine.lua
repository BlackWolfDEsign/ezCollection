local ADDON, ns = ...

--[[
    Funkeln an Quest-Gegenständen (Wunsch des Nutzers vom 15.11.2026). Aussehen, Regel und Schalter („Quest-Gegenstände
    in der Tasche funkeln“) liegen an einer Stelle in ezQuest (ezQuest/Shine.lua, ezCore.API("ezQuest").QuestShine);
    ezBag reicht nur Knopf, Gegenstand und Blizzards Angabe zum Platz weiter. Gerufen aus ns.SetItemMarks (Layout.lua)
    – also in Tasche, Bank, Gildenbank und ezBag-Fenster, bei jedem Neuzeichnen der Marken (EZQUEST_ITEMS_CHANGED in
    Marks.lua zeichnet nach, auch wenn ezQuests Schalter umgelegt wird). Ohne ezQuest funkelt nichts.
    Das Funkeln sitzt unter ezBags Marken (Quest-Symbol, Münze „im Auktionshaus mehr wert“, Schloss) und verdeckt sie
    nicht (Ebene OVERLAY 0, die Marken liegen auf OVERLAY 1).
]]

local failed = false   -- ein Fehler in ezQuest wird einmal gemeldet, danach ruft ezBag nicht mehr

-- Blizzards Angabe zum Platz (nil ohne Platz oder bei gesperrten Werten)
local function SlotQuestInfo(bag, slot)
    if type(bag) ~= "number" or type(slot) ~= "number" then return nil end
    local get = C_Container and C_Container.GetContainerItemQuestInfo
    if type(get) ~= "function" then return nil end
    local ok, info = pcall(get, bag, slot)
    if not ok or ezCore.IsSecret(info) or type(info) ~= "table" then return nil end
    return info
end

-- → true, wenn der Knopf jetzt funkelt
function ns.QuestShine(button, itemID, link, bag, slot)
    if failed or not button then return false end
    local api = ezCore.API("ezQuest")
    if not (type(api) == "table" and type(api.QuestShine) == "function") then return false end
    itemID = ns.PlainID(itemID)
    local ok, shown = pcall(api.QuestShine, button, "bag", itemID, link, itemID and SlotQuestInfo(bag, slot) or nil)
    if not ok then
        failed = true
        ezCore.Error("ezQuest", shown, "QuestShine (" .. ADDON .. ")")
        return false
    end
    return shown == true
end
