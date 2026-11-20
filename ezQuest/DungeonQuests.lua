local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Dungeon-Quests mit der Dungeon-Tabelle aus ezCore verknüpfen (ezCore.Dungeons, eine Quelle für ezSocial,
    ezMap und ezQuest): Fährt die Maus über eine Dungeon-Quest im Questlog oder in Blizzards Verfolgung, steht im
    Tooltip „Dungeon: Die Todesminen (17–26)“, gefärbt nach deiner Stufe (rot zu schwer, weiß passt, grau leicht),
    darunter „Eingang: Westfall“ bzw. „Eingang: Westfall (bei dir)“, wenn du ihn selbst betreten hast
    (ezCore.Dungeons.EntranceLabel; fehlt bei Dungeons ohne Eintrag).
    Welcher Dungeon: die Kopfzeile im Questlog (Blizzard sortiert Dungeon-Quests unter den Dungeon-Namen), sonst
    bei Quests mit dem Typ „Dungeon“ der Dungeon, den der Titel nennt.
    Quelle der Angaben ist ezCores Dungeon-Liste (Client, ergänzt um ezCores eigene Tabelle). Lässt sich eine Quest
    vom Typ „Dungeon“ keinem Eintrag zuordnen (neuer Forever-Dungeon, Zonen-Kopf statt Dungeon-Kopf, andere
    Schreibweise im Titel), sagt der Tooltip das neutral, statt zu schweigen (Regel „Datenquellen“ vom 13.11.2026:
    kein leerer Tooltip ohne Erklärung).
    Taint-sicher: HookScript an Blizzards Zeilen, EventRegistry-Rückruf der Verfolgung; nichts in Blizzards Tabellen.
]]

local DungeonQuests = {}
ns.DungeonQuests = DungeonQuests

local DUNGEON_TAG = 81   -- Constants.QuestConsts.QUEST_INFO_DUNGEON_ID
local hookedRows = setmetatable({}, { __mode = "k" })

local Call = Core.Call   -- geschützt, verträgt fehlende Funktionen

-- Kopfzeile, unter der die Quest im Questlog steht (Zone oder Dungeon).
local function HeaderOf(questID)
    local log = C_QuestLog
    if not log then return nil end
    local index = Core.Num(Call(log.GetHeaderIndexForQuest, questID))
    local info = index and Call(log.GetInfo, index)
    return type(info) == "table" and Core.Plain(info.title) or nil
end

local function DungeonTagged(questID)
    local info = C_QuestLog and Call(C_QuestLog.GetQuestTagInfo, questID)
    local tagID = type(info) == "table" and Core.Num(info.tagID) or nil
    local consts = rawget(_G, "Constants")
    local want = type(consts) == "table" and type(consts.QuestConsts) == "table"
        and consts.QuestConsts.QUEST_INFO_DUNGEON_ID or DUNGEON_TAG
    return tagID ~= nil and tagID == want
end

-- Eintrag der Dungeon-Tabelle zu einer Quest, sonst nil.
function DungeonQuests.For(questID)
    questID = Core.Num(questID)
    local D = Core.Dungeons
    if not questID or type(D) ~= "table" or type(D.Get) ~= "function" then return nil end
    local header = HeaderOf(questID)
    local entry = header and D.Get(header) or nil
    if not entry and DungeonTagged(questID) and type(D.Match) == "function" then
        local title = Core.Plain(Call(C_QuestLog.GetTitleForQuestID, questID))
        entry = type(title) == "string" and D.Match(title) or nil
    end
    return entry
end

-- Text und Farbe der Tooltip-Zeile („Dungeon: Die Todesminen (17–26)“ in der Schwierigkeitsfarbe); nil ohne
-- Eintrag. Name, Stufenbereich und Farbe liefert ezCore (Dungeons.Label), ezQuest setzt nur „Dungeon:“ davor.
function DungeonQuests.Line(entry, level)
    local D = Core.Dungeons
    if type(D) ~= "table" or type(D.Label) ~= "function" then return nil end
    local _, plain, r, g, b = D.Label(entry, level, { range = true })
    if type(plain) ~= "string" then return nil end
    return L.DUNGEON_LINE:format(plain), r, g, b
end

-- „Eingang: Westfall (bei dir)“ bzw. „Eingang: Westfall“ in der Spielsprache; nil, wenn ezCore den Eingang nicht
-- kennt. Text und Quelle legt ezCore für alle Nutzer fest (Dungeons.EntranceLabel, QUEST-03): "own" – selbst
-- betreten, der Zusatz „(bei dir)“ steht schon im Text; "data" – das Gebiet aus ezCores Dungeon-Tabelle (Quelle im
-- Kopf von ezCore/DungeonData.lua). Ältere ezCore ohne EntranceLabel: das Gebiet aus EntranceZone.
-- → Zeile, Quelle ("own" | "data") oder nil
function DungeonQuests.EntranceLine(entry)
    local D = Core.Dungeons
    if type(entry) ~= "table" or type(D) ~= "table" then return nil end
    local text, source
    if type(D.EntranceLabel) == "function" then
        text, source = Call(D.EntranceLabel, entry)
    elseif type(D.EntranceZone) == "function" then
        text, source = Call(D.EntranceZone, entry), "data"
    end
    text = Core.Plain(text)
    if type(text) ~= "string" or text == "" then return nil end
    return L.DUNGEON_ENTRANCE:format(text), source == "own" and "own" or "data"
end

-- Quest vom Typ „Dungeon“ ohne zuordenbaren Eintrag in ezCores Liste? Dann erklärt der Tooltip die Lücke. Ob der
-- Dungeon in der Liste fehlt oder nur Kopfzeile und Titel nicht passen, lässt sich hier nicht unterscheiden.
function DungeonQuests.Unknown(questID)
    questID = Core.Num(questID)
    if not questID then return false end
    return DungeonTagged(questID) and DungeonQuests.For(questID) == nil
end

-- Dungeon- und Eingangszeile anhängen (ohne Show). true, wenn etwas dazukam. questID: für den Hinweis bei einer
-- Dungeon-Quest ohne Eintrag in der Liste.
local function AddLines(tooltip, entry, questID)
    local text, r, g, b = DungeonQuests.Line(entry)
    if not text then
        if not DungeonQuests.Unknown(questID) then return false end
        -- Farben aus ezCores Rollen statt eigener Grautöne (T9-6, Gegenprüfung D2): Hinweis grau, Eingang als Angabe weiß
        Core.TipLine(tooltip, L.DUNGEON_UNKNOWN, "hint", true)
        return true
    end
    tooltip:AddLine(text, r, g, b)
    local entrance = DungeonQuests.EntranceLine(entry)
    if entrance then Core.TipLine(tooltip, entrance, "highlight") end
    return true
end

-- Zeilen an den Tooltip hängen. true, wenn welche dazukamen.
function DungeonQuests.AddToTooltip(tooltip, questID)
    if not ns.Enabled("dungeonQuests") then return false end
    if not AddLines(tooltip, DungeonQuests.For(questID), questID) then return false end
    tooltip:Show()
    return true
end

---------------------------------------------------------------------------
-- Questlog: Zeilen der Liste (Blizzard zeigt beim Überfahren schon einen Tooltip, ezQuest hängt die Zeile an)
---------------------------------------------------------------------------

-- Ein Haken je Zeile für alles, was ezQuest an Blizzards Tooltip hängt: die Dungeon-Zeilen und darunter die
-- Quest-ID (QuestId.lua).
local function OnRowEnter(button)
    if not GameTooltip:IsOwned(button) then return end
    ns.Try("Dungeon Tooltip", DungeonQuests.AddToTooltip, GameTooltip, button.questID)
    if ns.QuestId then ns.Try("QuestId Tooltip", ns.QuestId.AddToTooltip, GameTooltip, button.questID) end
end

function DungeonQuests.HookRows()
    local pool = QuestScrollFrame and QuestScrollFrame.titleFramePool
    if not (pool and pool.EnumerateActive) then return end
    for button in pool:EnumerateActive() do
        if not hookedRows[button] and button.HookScript then
            hookedRows[button] = true
            button:HookScript("OnEnter", OnRowEnter)
        end
    end
end

---------------------------------------------------------------------------
-- Verfolgung: Blizzard meldet das Überfahren eines Quest-Kopfs über EventRegistry. In der Gruppe zeigt Blizzard
-- selbst einen Tooltip (Fortschritt der Gruppe), allein keinen – dann zeigt ezQuest einen eigenen.
---------------------------------------------------------------------------

local function OnTrackerHeaderEnter(_, block, questID, inGroup)
    if not ns.Enabled("dungeonQuests") or type(block) ~= "table" then return end
    local entry = DungeonQuests.For(questID)
    local text = DungeonQuests.Line(entry)
    if not text then
        if not DungeonQuests.Unknown(questID) then return end
        text = L.DUNGEON_UNKNOWN
    end
    if not (inGroup and GameTooltip:IsOwned(block)) then
        GameTooltip:SetOwner(block, "ANCHOR_LEFT")
        Core.TipTitle(GameTooltip, Core.Plain(Call(C_QuestLog.GetTitleForQuestID, questID)) or text)
    end
    AddLines(GameTooltip, entry, questID)
    GameTooltip:Show()
end

ns.OnReady(function()
    if type(rawget(_G, "QuestLogQuests_Update")) == "function" then
        hooksecurefunc("QuestLogQuests_Update", function() ns.Try("Dungeon Rows", DungeonQuests.HookRows) end)
    end
    local registry = rawget(_G, "EventRegistry")
    if type(registry) == "table" and type(registry.RegisterCallback) == "function" then
        registry:RegisterCallback("OnQuestBlockHeader.OnEnter", function(...)
            ns.Try("Dungeon Tracker", OnTrackerHeaderEnter, ...)
        end, ns)
    end
end)
