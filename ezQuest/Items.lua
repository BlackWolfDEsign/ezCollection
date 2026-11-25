local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Quest-Gegenstände erkennen – ezQuest erkennt, ezBag zeigt (Symbol am Platz, Gruppe „Quest“):
      ezCore.API("ezQuest").ItemQuest(itemID, link) → info | nil
        info = { questID, questName, starts, needed, have, done }
        questID/questName: Quest im Log, die den Gegenstand braucht (nil, wenn unbekannt)
        starts: Gegenstand startet eine Quest; needed/have: Ziel „x/y“; done: Ziel erfüllt
      ezCore.Fire("EZQUEST_ITEMS_CHANGED"), sobald sich etwas daran ändert (Questlog, nachgeladene Gegenstände).
      ezCore.API("ezQuest").UseItems() → list | nil, "noQuestLog" (Welle 23, A2; für ezMacros eine Taste
        „Questgegenstand“, OneKey.QuestItems): alle Gegenstände zum Benutzen aus dem Questlog, beste zuerst –
        list = { { itemID, questID, title, order, header, super, watched, onMap, rank } … }
        super: Blizzards Hervorhebung (Zielverfolgung, C_SuperTrack); watched: in der Verfolgung; onMap: Quest im
        jetzigen Gebiet (Blizzards isOnMap oder Kopfzeile = Gebietsname); rank 3/2/1/0 in dieser Reihenfolge,
        gleich gut: Reihenfolge im Log (order). Frisch gelesen bei jedem Aufruf (Verfolgung und Gebiet wechseln ohne
        Questlog-Ereignis); ob der Gegenstand in den Taschen liegt oder angelegt wird, prüft der Aufrufer.
    Erkannt werden: Ziele aktiver Quests (auch normale Waren wie Leinenstoff, Abgleich über den Namen im
    Zieltext), Gegenstände zum Benutzen aus dem Questlog, Questgegenstände und Quest-Starter (aus dem
    Item-Wissen in ezCore). Ergebnis je itemID zwischengespeichert: ezBag fragt beim Einsortieren jeden Platz.
    Tooltip-Zeile „Quest: … (3/10)“ mit Schalter progressTip, außer die Quest steht schon im Tooltip (Blizzard, Questie;
    Textvergleich in Progress.lua).
]]

local Items = {}
ns.Items = Items

local objectives = {}    -- [Name klein] = { questID, questName, needed, have, done }
local special = {}       -- [itemID] = { questID, questName } (Gegenstand zum Benutzen)
local quests = {}        -- { { questID, title, complete, objectives = { { name, kind, have, need, done } } } } (Progress.lua)
local cache = {}         -- [itemID] = info | false
local unresolved = {}    -- [itemID] = true: Name oder Item-Wissen fehlte noch
local signature, objectiveCount = "", 0

local Plain, Call = Core.Plain, Core.Call

Items.Changed = ns.Throttle(function() Core.Fire("EZQUEST_ITEMS_CHANGED") end, 0.3)

-- „Leinenstoff: 3/10“ (Classic) oder „3/10 Leinenstoff“ (Retail) → „Leinenstoff“.
function Items.ObjectiveName(text)
    text = Plain(text)
    if type(text) ~= "string" then return nil end
    local name = text:gsub("^%s*%d+%s*/%s*%d+%s*", ""):gsub("%s*:%s*%d+%s*/%s*%d+%s*$", "")
    name = Core.Trim(name)
    if name == "" then return nil end
    return name
end

---------------------------------------------------------------------------
-- Questlog lesen
---------------------------------------------------------------------------

function Items.Rebuild()
    local newObjectives, newSpecial, newQuests, parts = {}, {}, {}, {}
    local log = C_QuestLog
    local num = log and log.GetNumQuestLogEntries and Core.Num((Call(log.GetNumQuestLogEntries))) or 0
    for index = 1, num do
        local info = Call(log.GetInfo, index)
        local questID = type(info) == "table" and not Core.Bool(info.isHeader, false) and Core.Num(info.questID) or nil
        if questID then
            local title = Plain(info.title)
            local quest = { questID = questID, title = title, objectives = {} }
            local open = 0
            for _, o in ipairs(Call(log.GetQuestObjectives, questID) or {}) do
                -- Alle Ziele für den Fortschritt im Tooltip (Progress.lua), nur lesen
                local oName = type(o) == "table" and Items.ObjectiveName(o.text) or nil
                if oName then
                    local entry = { name = oName, kind = Plain(o.type), have = Core.Num(o.numFulfilled),
                        need = Core.Num(o.numRequired), done = Core.Bool(o.finished, false) }
                    quest.objectives[#quest.objectives + 1] = entry
                    if not entry.done then open = open + 1 end
                end
                if type(o) == "table" and Plain(o.type) == "item" then
                    local name = Items.ObjectiveName(o.text)
                    if name then
                        local key = name:lower()
                        local entry = { questID = questID, questName = title, needed = Core.Num(o.numRequired),
                            have = Core.Num(o.numFulfilled), done = Core.Bool(o.finished, false) }
                        local old = newObjectives[key]
                        -- Brauchen zwei Quests denselben Gegenstand, zählt die noch offene.
                        if not old or (old.done and not entry.done) then newObjectives[key] = entry end
                        parts[#parts + 1] = key .. "=" .. questID .. ":" .. tostring(entry.have) .. "/"
                            .. tostring(entry.needed) .. (entry.done and "+" or "")
                    end
                end
            end
            -- Fertig: der Client sagt es, oder alle Ziele sind erfüllt
            quest.complete = Core.Bool(Call(log.IsComplete, questID), false)
                or (#quest.objectives > 0 and open == 0)
            if title then newQuests[#newQuests + 1] = quest end
            local itemID = Core.ItemID((Call(rawget(_G, "GetQuestLogSpecialItemInfo"), index)))
            if itemID then
                newSpecial[itemID] = { questID = questID, questName = title }
                parts[#parts + 1] = "use" .. itemID .. "=" .. questID
            end
        end
    end
    objectives, special, quests = newObjectives, newSpecial, newQuests
    objectiveCount = 0
    for _ in pairs(objectives) do objectiveCount = objectiveCount + 1 end
    table.sort(parts)
    local sig = table.concat(parts, ";")
    if sig ~= signature then
        signature = sig
        wipe(cache)
        wipe(unresolved)
        Items.Changed()
    end
end

Items.Request = ns.Throttle(function() Items.Rebuild() end, 0.5)

---------------------------------------------------------------------------
-- Gegenstände zum Benutzen mit Verfolgung, Hervorhebung und Gebiet (ezCore.API("ezQuest").UseItems, Welle 23, A2)
---------------------------------------------------------------------------

-- Gelesen wird in ezCore (Core.Inventory.QuestUseItems, Durchsicht 24.11.2026 – vorher hier und gleich in ezMacro)
Items.UseItems = Core.Inventory.QuestUseItems
Items.Watched, Items.InZone = Core.Inventory.QuestWatched, Core.Inventory.QuestInZone    -- für ShareJoin.lua
ns.API.UseItems = Items.UseItems

function Items.Count() return objectiveCount end

-- Die Quests im Log mit allen Zielen (zuletzt gelesen; nur lesen) – für den Fortschritt im Tooltip (Progress.lua).
function Items.Quests() return quests end

---------------------------------------------------------------------------
-- Ein Gegenstand
---------------------------------------------------------------------------

-- info oder nil, dazu known (Name bekannt: Ergebnis darf in den Zwischenspeicher) und complete (auch das
-- Item-Wissen ist vollständig; sonst bewertet OnKnowledge den Gegenstand neu, sobald ezCore ihn nachgeladen hat).
local function Build(itemID, link)
    local name = Core.ItemNameByID(itemID)   -- fehlt der Name, lädt ezCore ihn nach (ITEM_DATA_LOAD_RESULT)
    local objective = name and objectives[name:lower()]
    local use = special[itemID]
    local facts = Core.Knowledge and Core.Knowledge.Get(link or itemID)
    local starts, questItem = false, false
    if type(facts) == "table" then
        for _, key in ipairs(facts.specialKeys or {}) do
            if key == "startsQuest" then starts = true elseif key == "quest" then questItem = true end
        end
    end
    local known = name ~= nil
    local complete = known and type(facts) == "table" and not facts._partial
    if not (objective or use or starts or questItem) then return nil, known, complete end
    local source = objective or use
    return {
        questID = source and source.questID or nil,
        questName = source and source.questName or nil,
        starts = starts,
        needed = objective and objective.needed or nil,
        have = objective and objective.have or nil,
        done = objective ~= nil and objective.done == true,
    }, known, complete
end

-- Erkennt immer: der Schalter „Quest-Gegenstände erkennen“ (questItems) entfiel mit Nr. 45 der Einstellungs-Prüfung
-- vom 19.11.2026 – er schaltete die Grundlage ab, während die Schalter der Anzeigen (Symbol in ezBag, Funkeln,
-- Fortschritt im Tooltip) auf „an“ standen und nicht wirkten
function Items.Get(itemID, link)
    itemID = Core.ItemID(itemID) or Core.ItemID(link)
    if not itemID then return nil end
    local cached = cache[itemID]
    if cached ~= nil then return cached or nil end
    local info, known, complete = Build(itemID, link)
    if known then cache[itemID] = info or false end
    unresolved[itemID] = not complete or nil
    return info
end
ns.API.ItemQuest = Items.Get

-- Item-Wissen hat einen Gegenstand nachgeladen: neu bewerten; ist er ein Quest-Gegenstand, Bescheid geben.
local function OnKnowledge(itemID)
    if itemID == nil then
        wipe(cache)
        Items.Changed()
    elseif unresolved[itemID] then
        unresolved[itemID] = nil
        cache[itemID] = nil
        if Items.Get(itemID) then Items.Changed() end
    end
end

---------------------------------------------------------------------------
-- Tooltip: Zeile „Quest: …“, außer Blizzard oder ein anderes Addon (Questie) nennt sie schon (Progress.lua vergleicht
-- den Text; die bloße Anwesenheit von Questie reicht nicht – Wunsch des Nutzers vom 15.11.2026)
---------------------------------------------------------------------------

function Items.TooltipLine(info)
    if type(info) ~= "table" then return nil end
    if info.questName then
        local text = L.TIP_QUEST:format(info.questName)
        if info.needed and info.have then text = text .. (" (%d/%d)"):format(info.have, info.needed) end
        return text, info.done
    elseif info.starts then
        return L.TIP_STARTS, false
    end
    return nil
end

local function OnTooltip(tooltip, itemID, data)
    if not ns.Enabled("progressTip") then return end
    local info = Items.Get(itemID, Core.Tooltip.ItemLink(tooltip, data))
    local text, done = Items.TooltipLine(info)
    if not text then return end
    -- Woran „schon da“ zu erkennen ist: der Titel der Quest, „3/10“ samt Gegenstand oder Blizzards „startet eine Quest“
    local entry = { text = text, done = done }
    if info.questName then
        entry.text = text .. " " .. L.PROGRESS_SOURCE
        entry.a = info.questName
        if info.have and info.needed then
            entry.alt = { Core.ItemNameByID(itemID, true), info.have .. "/" .. info.needed }
        end
    else
        entry.a = Plain(rawget(_G, "ITEM_STARTS_QUEST")) or L.TIP_STARTS
    end
    ns.Progress.Add(tooltip, { entry })
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------

ns.OnReady(function()
    for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN" }) do
        ns.On(event, Items.Request)
    end
    if Core.Knowledge and Core.Knowledge.OnReady then
        Core.Knowledge.OnReady(function(itemID) ns.Try("Items", OnKnowledge, itemID) end)
    end
    -- Name nachgeladen (Core.ItemNameByID hat ihn angefordert): Gegenstand neu bewerten.
    ns.On("ITEM_DATA_LOAD_RESULT", function(_, itemID)
        itemID = Core.Num(itemID)
        if itemID then ns.Try("Items", OnKnowledge, itemID) end
    end)
    if Core.Tooltip and Core.Tooltip.AddItemSection then
        Core.Tooltip.AddItemSection("ezQuest", 70, OnTooltip, ADDON)
    end
    Items.Rebuild()
end)

ns.OnSettingChanged(function(key)
    -- Funkeln in Tasche und Beutefenster (Shine.lua): ezBag und ezLoot zeichnen auf dieselbe Nachricht neu
    if key ~= "bagShine" and key ~= "lootShine" then return end
    wipe(cache)
    wipe(unresolved)
    Items.Changed()
end)
