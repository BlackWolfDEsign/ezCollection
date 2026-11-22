local _, ns = ...
local L = ns.L

-- Kurzüberblick und Rundgang (ezCore/Tests/einfuehrung_funktionen_test.lua): je Zeile von L.INTRO_FEATURES der
-- Schritt (oder die Schritte) des Rundgangs, der sie zeigt; false = kein eigenes Ziel (Automatik, Tooltip, Daten oder
-- ein Fenster ohne Rundgang). Eine neue Zeile im Kurzüberblick braucht hier ihren Eintrag.
ns.FEATURE_STEPS = { "templates", "templates", { "preview", "apply" }, false, "hots" }
local Core = ezCore

--[[
    Rundgang mit Erklärblasen (Abschlussrunde „Tooltip-Guide“, Entscheidung des Nutzers 13.11.2026; UE-28): beim
    ersten Öffnen von Blizzards Fenster „Klick-Zauber“ die wichtigsten Funktionen von ezHeal – Knopf „Vorlagen“,
    Vorschau, Tasten wählen, Übernehmen und Zurück, HoT-Reihe. Gebaut mit Core.NewTour({ owner = ns }): Gesehenes
    steht in ezHealDB.tour, „Erklärung erneut zeigen“ unter „Erweitert“ (page:TourButton) zeigt alles wieder.
    Die Blasen hängen an Blizzards Fenster (Kind von ClickBindingFrame, kein Rahmen unter UIParent). Die Schritte
    zur Vorschau erscheinen erst, wenn sie offen ist (ein Ziel, das nicht sichtbar ist, wird übersprungen und nicht
    als gesehen gemerkt); darum startet auch das Öffnen der Vorschau den Rundgang.
]]

local Tour = {}
ns.Tour = Tour

local function BlizzButton() return ns.BlizzardButton and ns.BlizzardButton.button end
local function PreviewPart(field)
    local P = ns.Preview
    if not (P and P.frame and P.frame:IsShown()) then return nil end
    return P[field]
end

Tour.STEPS = {
    { key = "templates", target = BlizzButton, text = L.TOUR_TEMPLATES, side = "below" },
    { key = "preview", target = function()
        local box = PreviewPart("kindBox")
        return box and box.control
    end, text = L.TOUR_PREVIEW, side = "right" },
    { key = "keys", target = function()
        local rows = PreviewPart("rows")
        local row = rows and rows[1]
        return row and row.frame:IsShown() and row.mods and row.mods.control or nil
    end, text = L.TOUR_KEYS, side = "right" },
    { key = "apply", target = function() return PreviewPart("applyButton") end, text = L.TOUR_APPLY, side = "right" },
    { key = "hots", target = BlizzButton, text = L.TOUR_HOTS, side = "below" },
}

Tour.tour = Core.NewTour({ owner = ns, steps = Tour.STEPS })

-- Rundgang gebündelt starten (Blizzards Fenster oder die Vorschau wurde geöffnet); im Kampf erst danach
function Tour.Start()
    local parent = rawget(_G, "ClickBindingFrame")
    if type(parent) ~= "table" or not Tour.tour then return false end
    return Tour.tour:StartSoon(parent)
end
