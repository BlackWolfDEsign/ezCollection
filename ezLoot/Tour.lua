local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Rundgang mit Erklärblasen (ezCore.NewTour; Abschlussrunde „Tooltip-Guide“, Entscheidung des Nutzers 13.11.2026).
    Ein Rundgang für Plündernfenster und Beute-Verlauf: Schritte, deren Ziel gerade nicht zu sehen ist, überspringt
    ezCore und zeigt sie beim nächsten Start. Gestartet wird
      - beim ersten Plündernfenster, kurz verzögert (plündert das Spiel automatisch, blitzt das Fenster nur auf),
      - beim ersten Öffnen des Beute-Verlaufs.
    Gesehene Blasen merkt ezLootDB.tour; „Erklärung – Erneut zeigen“ unter „Erweitert“ (page:TourButton).
    Die Blasen sind eigene Rahmen von ezCore, an Blizzards Plündernfenster hängt nur ein HookScript („OnShow“).
]]

ns.TOUR_DELAY = 0.5     -- Sekunden nach dem Öffnen des Plündernfensters

-- Erster Platz im Plündernfenster, auf dem Itemlevel oder „BoE“ steht (sonst nil: Schritt wartet).
function ns.MarkedLootButton()
    local scrollBox = LootFrame and LootFrame.ScrollBox
    if not (scrollBox and scrollBox.ForEachFrame) then return nil end
    local found
    scrollBox:ForEachFrame(function(element)
        local button = not found and type(element) == "table" and element.Item
        local o = button and ns.Frames.Overlay(button)
        if o and ((o.ilvl and o.ilvl:GetText() or "") ~= "" or (o.bind and o.bind:GetText() or "") ~= "") then
            found = button
        end
    end)
    return found
end

local function HistoryPart(key)
    return function()
        local frame = ns.LootHistory and ns.LootHistory.frame
        return frame and frame[key]
    end
end

-- Die wichtigsten Funktionen, in dieser Reihenfolge. window: das Fenster, an dem die Blase hängt (ezCore legt
-- jede Blase nur einmal an – sie muss vom ersten Mal an zum richtigen Fenster gehören).
ns.TOUR_STEPS = {
    { key = "fast", window = "loot", target = function() return ns.Frames.fastButton end, text = function() return L.TOUR_FAST:format(ns.SlashCmd()) end, side = "above" },
    { key = "history", window = "loot", target = function() return ns.Frames.historyButton end, text = function() return L.TOUR_HISTORY:format(ns.SlashCmd()) end, side = "above" },
    { key = "marks", window = "loot", target = ns.MarkedLootButton, text = L.TOUR_MARKS, side = "right" },
    { key = "quality", window = "history", target = HistoryPart("qualityButton"), text = L.TOUR_QUALITY, side = "below" },
    { key = "filters", window = "history", target = HistoryPart("allCheck"), text = L.TOUR_FILTERS, side = "below" },
    { key = "rolls", window = "history", target = HistoryPart("rollsButton"), text = function() return L.TOUR_ROLLS:format(ns.SlashCmd()) end, side = "below" },
}

local function AssignParents()
    local history = ns.LootHistory and ns.LootHistory.frame
    for _, step in ipairs(ns.TOUR_STEPS) do
        if step.window == "loot" then
            step.parent = LootFrame
        elseif step.window == "history" then
            step.parent = history
        end
    end
end

-- owner = ns: gemerkt wird in ns.db.tour (ezLootDB.tour), den Speicher stellt ezCore (ns.TourStore).
ns.Tour = Core.NewTour({ owner = ns, steps = ns.TOUR_STEPS })

-- Zeigt die erste noch nicht gesehene Blase, deren Ziel sichtbar ist (parent: Fenster, mit dem sie verschwindet).
function ns.StartTour(parent)
    if not ns.Tour then return nil end
    AssignParents()
    local ok, key = pcall(ns.Tour.Start, ns.Tour, parent)
    if not ok then
        Core.Error(ADDON, key, "Tour")
        return nil
    end
    return key
end

ns.OnReady(function()
    if not (LootFrame and LootFrame.HookScript) then return end
    LootFrame:HookScript("OnShow", function()
        if not (C_Timer and C_Timer.After) then return ns.StartTour(LootFrame) end
        C_Timer.After(ns.TOUR_DELAY, function()
            if LootFrame:IsShown() then ns.StartTour(LootFrame) end
        end)
    end)
end)
