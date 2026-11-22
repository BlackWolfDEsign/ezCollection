local _, ns = ...
local L = ns.L

-- Kurzüberblick und Rundgang (ezCore/Tests/einfuehrung_funktionen_test.lua): je Zeile von L.INTRO_FEATURES der
-- Schritt (oder die Schritte) des Rundgangs, der sie zeigt; false = kein eigenes Ziel (Automatik, Tooltip, Daten oder
-- ein Fenster ohne Rundgang). Eine neue Zeile im Kurzüberblick braucht hier ihren Eintrag.
ns.FEATURE_STEPS = { "arrow", "level", "compare", "sets", "groupCheck" }
local Core = ezCore

--[[
    Rundgang mit Erklärblasen (ezCore.NewTour) beim ersten Öffnen des Charakterfensters – die fünf wichtigsten
    Funktionen: Itemlevel und Haltbarkeit am Platz, Vergleich im Tooltip, grüner Pfeil und Gold-Symbol, Knopf „Sets“,
    wo alles abschaltbar ist. Dazu (22.11.2026) beim ersten Öffnen des Reiters „Schlachtzug“ die Blase am Pfeil des
    Ausrüstungs-Checks (groupCheck). Gesehene Blasen merkt ezGearDB.hints; „Erklärung → Erneut zeigen“ unter „Erweitert“
    setzt sie zurück. Die Blasen hängen am Charakterfenster und verschwinden mit ihm; der Taschen-Knopf
    (Bearbeitungsmodus) dient nur als Anker, er wird nicht verändert. Ein unsichtbares Ziel wird übersprungen.
    Jede Blase hängt fest an ihrem Fenster (step.parent: PaperDollFrame bzw. RaidFrame, Tour.SetParents) – sonst nähme
    ezCore das Fenster, das zuletzt gestartet hat, und eine Blase bliebe stehen, wenn das andere Fenster zugeht
    (Review vom 22.11.2026: Charakterfenster und Kontakte gleichzeitig offen).
]]

local function Arrow() return ns.Marks.ArrowIcon(16) end
local function Coin() return ns.Marks.CoinIcon(16) end

local tour = Core.NewTour({
    owner = ns, field = "hints",
    steps = {
        { key = "level", target = function() return CharacterHeadSlot end, text = L.TOUR_LEVEL, side = "right" },
        { key = "compare", target = function() return CharacterChestSlot end, text = L.TOUR_COMPARE, side = "right" },
        { key = "arrow", target = function() return MainMenuBarBackpackButton end,
            text = L.TOUR_ARROW:format(Arrow(), Coin()), side = "left" },
        { key = "sets", target = function() return ns.Sets.Button() end, text = L.TOUR_SETS, side = "above" },
        { key = "settings", target = function() return ns.Sets.Button() end, text = L.TOUR_SETTINGS:format(ezCore.SettingsPathText("ezGear")), side = "above" },
        -- Ausrüstungs-Check am Reiter „Schlachtzug“ (GroupPanel.lua): sein Pfeil, nur dort sichtbar (ns.StartGroupTour)
        { key = "groupCheck", target = function()
            local panel = ns.GroupPanel and ns.GroupPanel.Frame()
            return panel and panel.arrow
        end, text = L.TOUR_GROUP, side = "right" },
    },
})
ns.Tour = tour

-- Fenster je Schritt (RaidFrame lädt Blizzard erst mit dem Kontakte-Fenster; darum bei jedem Start neu)
local function SetParents()
    for _, step in ipairs(tour.steps or {}) do
        step.parent = rawget(_G, step.key == "groupCheck" and "RaidFrame" or "PaperDollFrame")
    end
end
ns.TourSetParents = SetParents

-- Erste noch nicht gesehene Blase zeigen (kurz nach dem Öffnen, wenn Blizzard die Plätze gesetzt hat)
function ns.StartTour()
    local parent = PaperDollFrame
    if not (parent and parent.IsVisible and parent:IsVisible()) then return nil end
    SetParents()
    return tour:Start(parent)
end

-- Dasselbe am Reiter „Schlachtzug“ (Kontakte-Fenster), wo der Ausrüstungs-Check andockt; GroupPanel.lua ruft es
-- beim Öffnen des Reiters. Die Blasen am Charakterfenster sind dort unsichtbar und werden übersprungen.
function ns.StartGroupTour()
    local parent = rawget(_G, "RaidFrame")
    if not (type(parent) == "table" and parent.IsVisible and parent:IsVisible()) or tour:Done() then return nil end
    SetParents()
    return tour:Start(parent)
end

ns.OnReady(function()
    local frame = PaperDollFrame
    if not (frame and frame.HookScript) then return end
    frame:HookScript("OnShow", function()
        if tour:Done() then return end
        C_Timer.After(0.3, function() ns.Try("Tour", ns.StartTour) end)
    end)
end)
