local _, ns = ...
local L = ns.L

-- Kurzüberblick und Rundgang (ezCore/Tests/einfuehrung_funktionen_test.lua): je Zeile von L.INTRO_FEATURES der
-- Schritt (oder die Schritte) des Rundgangs, der sie zeigt; false = kein eigenes Ziel (Automatik, Tooltip, Daten oder
-- ein Fenster ohne Rundgang). Eine neue Zeile im Kurzüberblick braucht hier ihren Eintrag.
ns.FEATURE_STEPS = { "groups", false, { "search", "sort" }, "window", "sort" }

--[[
    Rundgang mit Erklärblasen (Abschlussrunde „Tooltip-Guide“): beim ersten Öffnen der Tasche zeigt ezBag
    nacheinander die wichtigsten Funktionen, jede mit „OK“ zur nächsten (ezCore.NewTour). Gesehenes merkt
    ezBagDB.hints; „Erklärung erneut zeigen“ unter „Erweitert“ setzt den Rundgang zurück.
    Ein Schritt, dessen Ziel gerade fehlt (z. B. die Tasche ohne Gruppen, ClassicUIs Taschen-Stil), wird
    übersprungen und kommt beim nächsten Öffnen.
]]

local Tour = {}
ns.Tour = Tour

local function Bar() return ns.Layout and ns.Layout.Toolbar and ns.Layout.Toolbar() end

-- Titel der ersten sichtbaren Gruppe in der Tasche.
local function FirstHeader()
    local view = ns.Layout and ns.Layout.View and ns.Layout.View()
    for _, box in ipairs(view and view.boxes or {}) do
        if box.IsShown and box:IsShown() and box.header and box.header:IsShown() then return box.header end
    end
end

local STEPS = {
    { key = "groups", target = FirstHeader, text = L.TOUR_GROUPS, side = "above" },
    { key = "search", target = function() local b = Bar() return b and b.search end, text = L.TOUR_SEARCH, side = "above" },
    { key = "sort", target = function() local b = Bar() return b and b.sort end, text = L.TOUR_SORT, side = "above" },
    { key = "focus", target = function() local b = Bar() return b and b.focus end, text = L.TOUR_FOCUS, side = "above" },
    { key = "grip", target = function() return ns.Layout and ns.Layout.Grip and ns.Layout.Grip() end, text = L.TOUR_GRIP, side = "left" },
    { key = "window", target = function() return ns.Window and ns.Window.BagButton and ns.Window.BagButton() end, text = L.TOUR_WINDOW, side = "above" },
}
Tour.STEPS = STEPS

-- Speicher über ezCores Gerüst: ezBagDB.hints (wie bisher, darum bleibt Gesehenes gesehen).
local tour = ezCore.NewTour({ owner = ns, field = "hints", okay = L.TOUR_OK, steps = STEPS })
Tour.tour = tour

-- Nächste noch nicht gesehene Blase an der Tasche (nichts, wenn alle gesehen oder die Gruppierung aus ist).
function Tour.Start()
    local bag = ns.Layout and ns.Layout.Frame and ns.Layout.Frame()
    if not (bag and bag:IsShown()) or not (ns.S and ns.S.grouping) or ns.ClassicUIBagsActive() then return nil end
    return tour:Start(bag)
end

function Tour.Reset() tour:Reset() end
function Tour.Done() return tour:Done() end

-- Beim Öffnen der Tasche, kurz nachdem ezBag sie angeordnet hat.
ns.OnReady(function()
    local bag = ns.Layout and ns.Layout.Frame and ns.Layout.Frame()
    if not bag then return end
    bag:HookScript("OnShow", function()
        if tour:Done() then return end
        C_Timer.After(0.5, Tour.Start)
    end)
end)
