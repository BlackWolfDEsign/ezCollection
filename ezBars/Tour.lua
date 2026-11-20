local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Rundgang mit Erklärblasen (Abschlussrunde „Tooltip-Guide“, Entscheidung des Nutzers 13.11.2026), gebaut mit
    ezCore (Core.NewTour). Fünf Blasen an der ersten sichtbaren ezBars-Leiste: was die Leiste ist, Anordnung,
    Verschieben, Tasten belegen, Aktionsplätze. Jede Blase hat „OK“ und ein X; danach kommt die nächste.

    Start: sobald eine Leiste zum ersten Mal zu sehen ist (nach dem Einloggen, wenn eine Leiste eingeschaltet wird,
    beim Öffnen der Einstellungsseite) – nie im Kampf, dann gleich danach (tour:StartSoon). Gesehene Blasen merkt ezBarsDB.tour;
    „Erweitert“ → „Erklärung: Erneut zeigen“ (page:TourButton) setzt sie zurück.

    Die Blasen sind gewöhnliche Rahmen (keine geschützten) unter UIParent, nur an der Leiste verankert: so bleiben sie
    sichtbar, auch wenn die erste Blase an Leiste 1 entstand und später Leiste 2 die erste sichtbare ist. An den
    Leisten ändern sie nichts.
]]

local Tour = {}
ns.Tour = Tour

-- Erste sichtbare ezBars-Leiste (Ziel der Blasen) oder nil.
function Tour.Bar()
    if not ns.Bars then return nil end
    for n = 1, ns.MAX_BARS do
        local bar = ns.Bars.Frame(n)
        if bar and bar:IsVisible() then return bar end
    end
    return nil
end

-- Erster Knopf dieser Leiste (für „Tasten belegen“), sonst die Leiste selbst.
function Tour.FirstButton()
    local bar = Tour.Bar()
    local button = bar and bar.buttons and bar.buttons[1]
    if button and button:IsVisible() then return button end
    return bar
end

-- Blasen zur Bildschirmmitte hin: Leiste rechts → Blase links daneben, sonst rechts.
function Tour.Side(bar)
    local x = bar and bar:GetCenter()
    local width = GetScreenWidth and GetScreenWidth()
    if x and width and x > width / 2 then return "left" end
    return "right"
end

Tour.STEPS = {
    -- Weg zur Seite über ezCore (Core.SettingsPathText, Gesamtreview T18-18)
    { key = "bar", target = Tour.Bar, text = L.TOUR_BAR:format(Core.SettingsPathText(ns.moduleName or "ezBars")) },
    { key = "layout", target = Tour.Bar, text = L.TOUR_LAYOUT },
    { key = "move", target = Tour.Bar, text = L.TOUR_MOVE },
    { key = "keys", target = Tour.FirstButton, text = L.TOUR_KEYS },
    { key = "slots", target = Tour.Bar, text = L.TOUR_SLOTS },
}

-- Speicher und Starter aus ezCore (V-035): owner = ns → gesehene Blasen in ezBarsDB.tour; tour:StartSoon bündelt
-- viele Aufrufe zu einem Start und wartet im Kampf über ezCores Reihe (Core.AfterCombat) auf das Kampfende.
if Core.NewTour then
    Tour.tour = Core.NewTour({ owner = ns, steps = Tour.STEPS })
    -- Seite der Blasen erst beim Zeigen festlegen (die Leiste kann inzwischen verschoben sein). Der Starter von
    -- ezCore ruft tour:Start – deshalb hier am eigenen Rundgang, nicht nur in Tour.Start.
    local start = Tour.tour.Start
    function Tour.tour:Start(parent)
        local bar = Tour.Bar()
        if bar then
            local side = Tour.Side(bar)
            for _, step in ipairs(self.steps) do step.side = side end
        end
        return start(self, parent)
    end
end

-- Zeigt die erste noch nicht gesehene Blase. Gibt ihren Schlüssel zurück oder nil (fertig, Kampf, keine Leiste).
function Tour.Start()
    local tour = Tour.tour
    if not tour or not ns.db or tour:Done() or ns.InCombat() then return nil end
    if not Tour.Bar() then return nil end
    return tour:Start(UIParent)
end

-- Etwas später starten (nach dem Ladebildschirm bzw. wenn die Leiste steht); mehrere Aufrufe bündeln. Im Kampf
-- startet ezCore gleich danach. Gibt true zurück, wenn ein Start vorgemerkt ist.
function Tour.Later(delay)
    if not Tour.tour or not ns.db then return false end
    return Tour.tour:StartSoon(UIParent, delay or 1) == true
end

function Tour.Done() return Tour.tour == nil or Tour.tour:Done() end

ns.OnReady(function() Tour.Later(3) end)
