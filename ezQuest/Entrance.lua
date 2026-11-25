local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Knopf „Eingang auf der Karte“ in Blizzards Questlog-Details (V-134, QUEST-01, ST-09, VP-86; Platz entschieden
    am 13.11.2026: in den Questlog-Details neben Blizzards Knöpfen – oben in Blizzards Leiste rechts neben „Zurück“).
    Sichtbar nur bei Dungeon-Quests (DungeonQuests.For), deren Eingang sich auf einer Karte zeigen lässt.

    Woher die Lage kommt (Leitlinie 11, Reihenfolge der Quellen; der Tooltip und die Chatzeile nennen sie):
      "client"  das Spiel kennt den Eingang auf der Karte des Gebiets (Dungeons.Entrances, nur Client-Antwort) –
                Forever liefert keine (Spieltest 14.11.2026), der Weg bleibt für einen späteren Client
      "own"     von dir betreten (Dungeons.EntranceMap, Entdecker-Datenbank von ezCore)
      "tables"  laut Client-Tabellen (Dungeons.EntranceMap » TableEntrance, seit 24.11.2026)
      "zone"    nur das Gebiet ist bekannt (Dungeons.EntranceZone aus ezCores Dungeon-Tabelle); die Karte des
                Gebiets sucht ezCore in Blizzards Kartenbaum nach dem Namen (Core.Map.ByName; Welle 23, A6 – vorher
                eine eigene Suche hier, eine zweite steht in ezMap/Way.lua)
    Klick: mit Lage und ezMap setzt ezMap Blizzards Markierung (ezCore.API("ezMap").SetWaypoint), dann zeigt die
    Karte das Gebiet (Core.OpenPanel("map", uiMapID)); ohne ezMap oder ohne Lage nur die Karte. Im Kampf zeigt ezCore
    seinen Hinweis und es geschieht nichts.
    Taint-sicher: eigener Knopf als Kind von Blizzards Leiste, hooksecurefunc auf QuestMapFrame_ShowQuestDetails;
    nichts in Blizzards Tabellen.
]]

local Entrance = {}
ns.Entrance = Entrance

local Call = Core.Call

-- Vergleichsschlüssel eines Gebietsnamens: klein geschrieben, ohne führenden Artikel (ezCores Tabelle führt
-- „Schwarzfels“, der deutsche Client nennt die Karte „Der Schwarzfels“). Weiterleitung auf Core.Map.NameKey.
function Entrance.NameKey(name)
    return Core.Map.NameKey(name)
end

-- uiMapID eines Gebiets nach seinem Namen (Spielsprache, ohne Artikel); ein Gebiet (Zone) hat Vorrang vor
-- gleichnamigen Karten. Weiterleitung auf Core.Map.ByName: einmal je Name gesucht, unter der Karte des Spielers und
-- unter Blizzards Weltkarte, „nicht gefunden“ nur nach dem ganzen Kartenbaum gemerkt. nil, wenn er ihn nicht kennt.
function Entrance.ZoneMap(name)
    return (Core.Map.ByName(name, "Zone"))
end

local function SameDungeon(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    if a == b then return true end
    local ka, kb = a.key or a.id or a.mapID, b.key or b.id or b.mapID
    return ka ~= nil and ka == kb
end

local function MapName(mapID)
    local info = Core.Map.Info(mapID)
    local name = type(info) == "table" and Core.Plain(info.name) or nil
    return type(name) == "string" and name ~= "" and name or nil
end

-- Wohin zeigt der Knopf? → { map, x, y, source = "client" | "own" | "tables" | "zone", zone } oder nil (keine Karte bekannt).
function Entrance.Target(entry)
    local D = Core.Dungeons
    if type(entry) ~= "table" or type(D) ~= "table" then return nil end
    local zone = type(D.EntranceZone) == "function" and Core.Plain(Call(D.EntranceZone, entry)) or nil
    if type(zone) ~= "string" or zone == "" then zone = nil end
    local zoneMap = zone and Entrance.ZoneMap(zone)
    -- 1. das Spiel (nur die Client-Antwort, ohne den eigenen Rückfall und die Client-Tabellen: 2.)
    if zoneMap and type(D.Entrances) == "function" then
        local list = Call(D.Entrances, zoneMap, { tables = false })
        for _, e in ipairs(type(list) == "table" and list or {}) do
            if type(e) == "table" and (e.source == nil or e.source == "client") and SameDungeon(e.entry, entry)
                and Core.Num(e.x) and Core.Num(e.y) then
                return { map = zoneMap, x = Core.Num(e.x), y = Core.Num(e.y), source = "client", zone = zone }
            end
        end
    end
    -- 2. von dir betreten, sonst laut Client-Tabellen
    if type(D.EntranceMap) == "function" then
        local map, x, y, source = Call(D.EntranceMap, entry)
        map, x, y = Core.Num(map), Core.Num(x), Core.Num(y)
        if map and x and y then
            return { map = map, x = x, y = y, source = source == "tables" and "tables" or "own", zone = MapName(map) or zone }
        end
    end
    -- 3. nur das Gebiet
    if zoneMap then return { map = zoneMap, source = "zone", zone = zone } end
    return nil
end

local function WaypointApi()
    local api = Core.API and Core.API("ezMap")
    return type(api) == "table" and type(api.SetWaypoint) == "function" and api or nil
end
Entrance.WaypointApi = WaypointApi

-- Ort des Eingangs samt Quelle: „Westfall (bei dir)“ mit ezCores Wortlaut für selbst betretene Eingänge (derselbe
-- Text wie in der Zeile „Eingang: …“ der Questliste, Dungeons.EntranceLabel), „Westfall (laut Client-Tabellen)“ und
-- „Westfall (laut dem Spiel)“ für die Antwort des Clients – der Name ist der der Karte, auf der die Markierung sitzt.
local function PlaceText(target, zone)
    if target.source == "own" or target.source == "tables" then
        local fmt = Core.L and (target.source == "own" and Core.L.DB_ENTRANCE_OWN or Core.L.DB_ENTRANCE_TABLES)
        return type(fmt) == "string" and fmt:format(zone) or zone
    end
    return L.ENTRANCE_PLACE_CLIENT:format(zone)
end
Entrance.PlaceText = PlaceText

-- Knopf gedrückt: Markierung (mit Lage und ezMap) und Karte. → true, wenn die Karte aufging; dazu, ob eine
-- Markierung gesetzt wurde. Im Kampf: false, "combat" (Hinweis von ezCore).
function Entrance.Go(entry)
    local target = Entrance.Target(entry)
    if not target then
        ns.Print(L.ENTRANCE_NONE)
        return false, "none"
    end
    if Core.InCombat() then
        Core.OpenPanel("map", target.map)   -- zeigt ezCores Hinweis „Im Kampf …“
        return false, "combat"
    end
    local name = type(entry.name) == "string" and entry.name or "?"
    local zone = target.zone or MapName(target.map) or "?"
    local waypoint = false
    local api = target.x and WaypointApi()
    if api then waypoint = Call(api.SetWaypoint, target.map, target.x, target.y, name) == true end
    local opened = Core.OpenPanel("map", target.map)
    local message
    if waypoint then
        message = L.ENTRANCE_DONE_WAY:format(name, PlaceText(target, zone))
    elseif target.x then
        message = L.ENTRANCE_DONE_MAP:format(name, PlaceText(target, zone))
            .. " " .. (api and L.ENTRANCE_WAY_FAILED or L.ENTRANCE_NO_EZMAP)
    else
        message = L.ENTRANCE_DONE_ZONE:format(name, zone)
    end
    if opened or waypoint then ns.Print(message) end
    return opened == true, waypoint
end

---------------------------------------------------------------------------
-- Knopf in Blizzards Leiste der Questlog-Details
---------------------------------------------------------------------------

local button

-- Tooltip: Dungeon, Lage mit Quelle, was der Klick tut.
function Entrance.FillTooltip(tooltip, entry)
    local target = Entrance.Target(entry)
    Core.TipTitle(tooltip, L.ENTRANCE_BUTTON)
    local line, r, g, b = ns.DungeonQuests.Line(entry)
    if line then tooltip:AddLine(line, r, g, b) end
    if not target then
        Core.TipLine(tooltip, L.ENTRANCE_NONE, "hint", true)
        return target
    end
    local zone = target.zone or MapName(target.map) or "?"
    if target.source == "zone" then
        Core.TipLine(tooltip, L.ENTRANCE_TIP_ZONE:format(zone), "hint", true)
        Core.TipClick(tooltip, L.ENTRANCE_CLICK_MAP:format(zone))
    else
        Core.TipLine(tooltip, L.DUNGEON_ENTRANCE:format(PlaceText(target, zone)), "hint", true)
        if WaypointApi() then
            Core.TipClick(tooltip, L.ENTRANCE_CLICK_WAY)
        else
            Core.TipClick(tooltip, L.ENTRANCE_CLICK_MAP:format(zone) .. " " .. L.ENTRANCE_NO_EZMAP)
        end
    end
    return target
end

local function OnEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    ns.Try("Entrance Tooltip", Entrance.FillTooltip, GameTooltip, self.entry)
    GameTooltip:Show()
end

local function OnLeave() GameTooltip:Hide() end

local function OnClick(self)
    ns.Try("Entrance Click", Entrance.Go, self.entry)
end

-- Maße aus Blizzards Forever-Quelle (Mainline/QuestMapFrame.xml, QuestFrameTemplates.xml): die Leiste BackFrame ist
-- 307 breit, „Zurück“ sitzt bei x = 11 und ist 90 breit; der Hinweis AccountCompletedNotice („vom Konto erledigt“)
-- hängt oben rechts bei x = -13, so breit wie sein Text, das Warband-Symbol steht links davor.
local GAP, NOTICE_ICON, NOTICE_RIGHT = 4, 18, 13
local BAR_WIDTH, BACK_LEFT, BACK_WIDTH = 307, 11, 90
local MIN_WIDTH, MAX_WIDTH, PAD = 110, 180, 24
local SHORT_MIN = 56          -- schmaler als „Eingang“ samt Rand: unter „Zurück“ statt daneben

local function Num(frame, method)
    return type(frame) == "table" and Core.Num(Call(frame[method], frame)) or nil
end

local function TextWidth(b, fallback)
    local fs = b.GetFontString and b:GetFontString()
    return (fs and Core.Num(Call(fs.GetStringWidth, fs))) or fallback
end

-- Platz zwischen „Zurück“ und Blizzards Hinweis „vom Konto erledigt“ (samt Symbol). Bildschirmlage, sobald Blizzard
-- die Leiste angeordnet hat, sonst aus den Maßen der Vorlage.
local function FreeBeforeNotice(bar, back, notice)
    local left, right = Num(notice, "GetLeft"), Num(back, "GetRight")
    if left and right then return left - NOTICE_ICON - right - 2 * GAP end
    local backRight = BACK_LEFT + (Num(back, "GetWidth") or BACK_WIDTH)
    return (Num(bar, "GetWidth") or BAR_WIDTH) - NOTICE_RIGHT - (Num(notice, "GetWidth") or 50) - NOTICE_ICON
        - backRight - 2 * GAP
end
Entrance.FreeBeforeNotice = FreeBeforeNotice

-- Lage und Aufschrift: rechts neben „Zurück“ mit voller Aufschrift. Zeigt Blizzard in derselben Leiste den Hinweis
-- „vom Konto erledigt“, bleibt der Knopf links davon – mit kurzer Aufschrift „Eingang“, wenn die volle nicht passt,
-- und unter „Zurück“, wenn auch die kurze nicht passt. Ohne Blizzards Leiste oben rechts in den Details.
-- → "full" | "short" | "below" | "details"
function Entrance.Layout(b)
    b = b or button
    if not b then return nil end
    local details = QuestMapFrame and QuestMapFrame.DetailsFrame
    local bar = type(details) == "table" and type(details.BackFrame) == "table" and details.BackFrame or nil
    local back = bar and type(bar.BackButton) == "table" and bar.BackButton or nil
    local notice = bar and type(bar.AccountCompletedNotice) == "table" and bar.AccountCompletedNotice or nil
    b:ClearAllPoints()
    b:SetText(L.ENTRANCE_BUTTON)
    local full = math.min(MAX_WIDTH, math.max(MIN_WIDTH, TextWidth(b, 126) + PAD))
    if not back then
        b:SetSize(full, 22)
        b:SetPoint("TOPRIGHT", details, "TOPRIGHT", -12, -12)
        return "details"
    end
    local free = notice and notice:IsShown() and FreeBeforeNotice(bar, back, notice) or nil
    if not free or free >= full then
        b:SetSize(full, 22)
        b:SetPoint("LEFT", back, "RIGHT", GAP, 0)
        return "full"
    end
    b:SetText(L.ENTRANCE_BUTTON_SHORT)
    local short = TextWidth(b, 52) + PAD
    if free >= SHORT_MIN then
        b:SetSize(math.min(short, free), 22)
        b:SetPoint("LEFT", back, "RIGHT", GAP, 0)
        return "short"
    end
    b:SetSize(math.max(short, Num(back, "GetWidth") or BACK_WIDTH), 22)
    b:SetPoint("TOPLEFT", back, "BOTTOMLEFT", 0, -2)
    return "below"
end

-- Der Knopf (einmal angelegt): in Blizzards Leiste oben (BackFrame) rechts neben „Zurück“ (Lage: Entrance.Layout);
-- ohne diese Leiste oben rechts in den Details.
function Entrance.Button()
    if button then return button end
    local details = QuestMapFrame and QuestMapFrame.DetailsFrame
    if type(details) ~= "table" then return nil end
    local bar = type(details.BackFrame) == "table" and details.BackFrame or nil
    button = CreateFrame("Button", nil, bar or details, "UIPanelButtonTemplate")
    button:SetScript("OnEnter", OnEnter)
    button:SetScript("OnLeave", OnLeave)
    button:SetScript("OnClick", OnClick)
    button:Hide()
    Entrance.Layout(button)
    -- Blendet Blizzard den Hinweis „vom Konto erledigt“ ein oder aus, rückt der Knopf nach (HookScript, Leitlinie 5).
    local notice = bar and bar.AccountCompletedNotice
    if type(notice) == "table" and notice.HookScript then
        local function Relayout() if button:IsShown() then ns.Try("Entrance Layout", Entrance.Layout, button) end end
        notice:HookScript("OnShow", Relayout)
        notice:HookScript("OnHide", Relayout)
    end
    return button
end

-- Zeigen oder verbergen für die Quest der Details. → true, wenn der Knopf zu sehen ist.
function Entrance.Update(questID)
    local b = Entrance.Button()
    if not b then return false end
    local entry = ns.Enabled("dungeonQuests") and ns.Enabled("entranceButton") and ns.DungeonQuests.For(questID) or nil
    local show = entry ~= nil and Entrance.Target(entry) ~= nil
    b.entry = show and entry or nil
    if show then Entrance.Layout(b) end
    b:SetShown(show)
    return show
end

local function CurrentQuest()
    local details = QuestMapFrame and QuestMapFrame.DetailsFrame
    return type(details) == "table" and Core.Plain(details.questID) or nil
end

ns.OnReady(function()
    if type(rawget(_G, "QuestMapFrame_ShowQuestDetails")) == "function" then
        hooksecurefunc("QuestMapFrame_ShowQuestDetails", function(questID)
            ns.Try("Entrance", Entrance.Update, questID)
        end)
    end
end)

ns.OnSettingChanged(function(key)
    if key == "entranceButton" or key == "dungeonQuests" then
        if button then ns.Try("Entrance", Entrance.Update, CurrentQuest()) end
    end
end)
