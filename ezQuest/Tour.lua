local ADDON, ns = ...
local L = ns.L

-- Kurzüberblick und Rundgang (ezCore/Tests/einfuehrung_funktionen_test.lua): je Zeile von L.INTRO_FEATURES der
-- Schritt (oder die Schritte) des Rundgangs, der sie zeigt; false = kein eigenes Ziel (Automatik, Tooltip, Daten oder
-- ein Fenster ohne Rundgang). Eine neue Zeile im Kurzüberblick braucht hier ihren Eintrag.
-- Der Rundgang von Nest zu Nest (Leveling-Route, 22.11.2026) steht in der Blase am Questlog (HINT_LOG_ROUTE).
ns.FEATURE_STEPS = { { "level", "levelGossip" }, { "auto", "autoGossip" }, "log", "log", false, "log" }
local Core = ezCore

--[[
    Rundgang mit Erklärblasen (ezCore.NewTour, Abschlussrunde „Tooltip-Guide“): Beim ersten NPC-Dialog mit Quests
    bzw. beim ersten Öffnen des Questlogs erklären Blasen die vier wichtigsten Funktionen:
      auto / autoGossip    Häkchen „Automatisch“ im Questfenster bzw. im Gossip-Fenster
      level / levelGossip  Stufe vor den Quests in der Begrüßungs- bzw. Gossip-Liste (und die Tönung)
      log                  Questlog: Tönung und Dungeon-Tooltip
      sort                 Pfeil-Knopf am Kopf „Quests“ der Verfolgung
    Jede Blase hängt an ihrem Ziel und verschwindet mit ihm; „OK“ führt zur nächsten sichtbaren, Ziele, die gerade
    nicht zu sehen sind, kommen später. Questfenster und Gossip-Fenster haben je eine eigene Blase (ezCore behält
    den Rahmen, an dem eine Blase zuerst hing); wer eine davon bestätigt, hat beide gesehen (Tour.Sync).
    Gemerkt in ezQuestDB.hints; „Erklärung – Erneut zeigen“ unter „Erweitert“ zeigt alles wieder
    (page:TourButton). Eigene Rahmen, nichts in Blizzards Tabellen.
]]

local Tour = {}
ns.Tour = Tour

local function Visible(frame)
    if type(frame) == "table" and frame.IsVisible and frame:IsVisible() then return frame end
    return nil
end

-- Gossip-Fenster mit Quests (bei Händlern und Fluglehrern ohne Quests keine Blasen).
local function GossipWithQuests()
    local frame = Visible(rawget(_G, "GossipFrame"))
    local gossip = C_GossipInfo
    if not (frame and type(gossip) == "table") then return nil end
    local available, active = Core.Call(gossip.GetAvailableQuests), Core.Call(gossip.GetActiveQuests)
    local count = (type(available) == "table" and #available or 0) + (type(active) == "table" and #active or 0)
    return count > 0 and frame or nil
end

-- Häkchen „Automatisch“ in einem sichtbaren Fenster.
local function SwitchIn(frame)
    if not frame then return nil end
    for _, check in ipairs(ns.Auto and ns.Auto.Switches() or {}) do
        if check:GetParent() == frame and Visible(check) then return check end
    end
    return nil
end

function Tour.QuestSwitchTarget() return SwitchIn(Visible(rawget(_G, "QuestFrame"))) end
function Tour.GossipSwitchTarget() return SwitchIn(GossipWithQuests()) end

-- Liste der Quests eines NPCs, sobald ezQuest dort die Stufe zeigt.
function Tour.GreetingTarget()
    return ns.Enabled("levelInDialogs") and Visible(rawget(_G, "QuestFrameGreetingPanel")) or nil
end

function Tour.GossipTarget()
    return ns.Enabled("levelInDialogs") and GossipWithQuests() or nil
end

function Tour.LogTarget()
    return Visible(rawget(_G, "QuestMapFrame"))
end

function Tour.SortTarget()
    return Visible(ns.Tracker and ns.Tracker.Button())
end

Tour.tour = Core.NewTour({
    owner = ns, field = "hints",   -- Speicher ezQuestDB.hints (ezCore legt ihn beim ersten Zugriff an)
    steps = {
        { key = "auto", target = Tour.QuestSwitchTarget, text = L.HINT_AUTO, side = "right" },
        { key = "autoGossip", target = Tour.GossipSwitchTarget, text = L.HINT_AUTO, side = "right" },
        { key = "level", target = Tour.GreetingTarget, text = L.HINT_LEVEL, side = "right" },
        { key = "levelGossip", target = Tour.GossipTarget, text = L.HINT_LEVEL, side = "right" },
        -- mit der Leveling-Route nennt die Blase auch sie (Zahnrad-Menü; eigener Schritt am Zahnrad: Rahmenname in
        -- Forever ungeprüft, und die Prüfungen begrenzen den Rundgang auf sechs Blasen)
        { key = "log", target = Tour.LogTarget, side = "left", text = function()
            return ns.Enabled("levelRoute") and (L.HINT_LOG .. " " .. L.HINT_LOG_ROUTE) or L.HINT_LOG
        end },
        { key = "sort", target = Tour.SortTarget, text = function() return L.HINT_SORT:format(ns.SlashCmd(L.CMD_SORT)) end, side = "left" },
    },
})

-- Dieselbe Erklärung in zwei Fenstern: wer eine bestätigt hat, hat beide gesehen.
local PAIRS = { auto = "autoGossip", autoGossip = "auto", level = "levelGossip", levelGossip = "level" }

function Tour.Sync()
    local seen = ns.db and ns.db.hints
    if type(seen) ~= "table" then return end
    for key, other in pairs(PAIRS) do
        if seen[key] then seen[other] = true end
    end
end

-- Erste noch nicht gesehene Blase mit sichtbarem Ziel; nil, wenn keine passt oder alles gesehen ist.
function Tour.Start()
    if not ns.db then return nil end
    Tour.Sync()
    if Tour.tour:Done() then return nil end
    return Tour.tour:Start()
end

ns.OnReady(function()
    for _, name in ipairs({ "QuestFrame", "QuestFrameGreetingPanel", "GossipFrame", "QuestMapFrame" }) do
        local frame = rawget(_G, name)
        if type(frame) == "table" and frame.HookScript then
            frame:HookScript("OnShow", function() ns.Try("Tour", Tour.Start) end)
        end
    end
end)
