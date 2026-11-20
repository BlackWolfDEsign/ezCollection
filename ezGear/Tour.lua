local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Rundgang mit Erklärblasen (ezCore.NewTour) beim ersten Öffnen des Charakterfensters – die fünf wichtigsten
    Funktionen: Itemlevel und Haltbarkeit am Platz, Vergleich im Tooltip, grüner Pfeil und Gold-Symbol, Knopf „Sets“,
    wo alles abschaltbar ist. Gesehene Blasen merkt ezGearDB.hints; „Erklärung → Erneut zeigen“ unter „Erweitert“
    setzt sie zurück. Die Blasen hängen am Charakterfenster und verschwinden mit ihm; der Taschen-Knopf
    (Bearbeitungsmodus) dient nur als Anker, er wird nicht verändert. Ein unsichtbares Ziel wird übersprungen.
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
    },
})
ns.Tour = tour

-- Erste noch nicht gesehene Blase zeigen (kurz nach dem Öffnen, wenn Blizzard die Plätze gesetzt hat)
function ns.StartTour()
    local parent = PaperDollFrame
    if not (parent and parent.IsVisible and parent:IsVisible()) then return nil end
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
