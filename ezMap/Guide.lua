local _, ns = ...
local L = ns.L
local Core = ezCore

-- Rundgang mit Erklärblasen (Abschlussrunde, Core.NewTour): beim ersten Öffnen der Weltkarte der ezMap-Knopf,
-- Blizzards Markierung, die Lehrer, die Sammel-Fundorte (am ezMap-Knopf; mit mapFilterSection oder ohne
-- ezMap-Knopf an Blizzards Kartenfilter, Gather.InFilter) und das Menü
-- „Aufspüren“ der Minikarte, beim ersten Flug die Flugleiste. Jede Blase hängt an ihrem Ziel und
-- verschwindet mit ihm; ein unsichtbares Ziel (Knopf abgeschaltet, Leiste bei Leatrix Plus/InFlight) wird
-- übersprungen und kommt beim nächsten Mal dran. „Erklärung erneut zeigen“ steht unter „Erweitert“.
-- Ergänzende Addons (README und Einstellungsseite): nur die, mit denen ezMap zusammenarbeitet.
local Guide = {}
ns.Guide = Guide

local function MapButton() return ns.MapButton.Get() end
local function PinButton() return WorldMapFrame and WorldMapFrame.WorldMapTrackingPinButton end
local function FlightBar() return ns.Flights.Bar() end
local function TrackingButton() return MinimapCluster and MinimapCluster.Tracking end
local function GatherButton() return ns.Gather.InFilter() or ns.MapButton.Get() end

Guide.tour = Core.NewTour({
    owner = ns, field = "hints",      -- gespeichert in ezMapDB.hints (wie bisher)
    steps = {
        { key = "mapButton", target = MapButton, text = L.TOUR_MAP_BUTTON, side = "below" },
        { key = "pin", target = PinButton, text = L.TOUR_PIN, side = "below" },
        { key = "trainers", target = MapButton, text = L.TOUR_TRAINERS, side = "right" },
        { key = "flightBar", target = FlightBar, text = L.TOUR_FLIGHT_BAR, side = "below" },
        { key = "tracking", target = TrackingButton, text = L.TOUR_TRACKING, side = "left" },
        { key = "gather", target = GatherButton, text = L.TOUR_GATHER, side = "below" },
    },
})

-- Nächste noch nicht gesehene Blase, deren Ziel gerade sichtbar ist (Weltkarte geöffnet, Flug begonnen).
function Guide.Start()
    return Guide.tour:Start()
end

-- Steht gerade eine Blase dieses Rundgangs? Dann wartet ezCores Hinweis auf Abläufe ohne Klick an der Weltkarte (Welle
-- 29, Way.lua und TrackingMemory.lua) bis zum nächsten Öffnen – nie zwei Blasen am selben Knopf.
function Guide.Showing()
    local hints = Guide.tour and Guide.tour.hints
    if not (hints and hints.Box) then return false end
    for _, step in ipairs(Guide.tour.steps or {}) do
        local box = hints.Box(step.key)
        if box and box.IsShown and box:IsShown() then return true end
    end
    return false
end

-- Questie zeigt alle Lehrer und Stadtbewohner auf der Karte; ezMap bietet die besuchten als Ziel an und
-- verweist im Kartenmenü darauf. Name, Ordner und Link stehen einmal in ezCore (Core.OTHER_ADDONS.Questie, V-138).
Core.AddCompanion("ezMap", { key = "Questie", why = L.COMPANION_WHY_QUESTIE })
