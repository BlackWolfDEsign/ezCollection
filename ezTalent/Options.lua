local _, ns = ...
local L = ns.L

-- Einstellungen unter Esc → Optionen → AddOns → ezCollection → ezTalent (Seite von ezCore):
-- Allgemein (Talentfenster öffnen) → Vorlagen → Vermächtnis → Auswirkungen → Charaktere →
-- Erweitert (Talente erheben, Werte für die Simulation messen, gemerkte Grundwerte zeigen, Status, Erklärung erneut zeigen, Einstellungen zurücksetzen, ergänzende Addons).
local page

local function Register()
    if page then return end
    page = ezCore.NewSettingsPage(ns)
    if not page then return end

    page:Button(L.OPT_OPEN, L.OPT_OPEN_BUTTON, function() ns.OpenTalents() end, L.OPT_OPEN_TIP)

    -- Einstellungs-Prüfung 19.11.2026: „Vorlagen“ an beiden Fenstern, berechnete Verteilungen und „Verändert durch“ sind
    -- fest (Nr. 37–40); „Vor dem Übernehmen zurücksetzen“ steht als Kästchen bei „Übernehmen“ im Vermächtnis (Abschnitt 3).
    page:Header(L.OPT_HEADER_TEMPLATES)
    page:Checkbox("makeRoom")
    page:Checkbox("nextPoint")

    page:Header(L.OPT_HEADER_LEGACY)
    page:Button(L.OPT_OPEN_LEGACY, L.OPT_OPEN_LEGACY_BUTTON, function() ns.OpenLegacy() end, L.OPT_OPEN_LEGACY_TIP)

    page:Header(L.OPT_HEADER_EFFECTS)
    page:Checkbox("effectsTab")

    page:Header(L.OPT_HEADER_ROSTER)
    page:Checkbox("rosterTab")
    page:Button(L.OPT_ROSTER, L.OPT_ROSTER_BUTTON, function() ns.Roster.Show() end, L.OPT_ROSTER_TIP)

    page:Advanced()
    page:Button(L.OPT_SURVEY, L.OPT_SURVEY_BUTTON, function() ns.Templates.ShowSurvey() end, L.OPT_SURVEY_TIP)
    page:Button(L.OPT_MEASURE, L.OPT_MEASURE_BUTTON, function() ns.Measure.Show() end, L.OPT_MEASURE_TIP)
    page:Button(L.OPT_MEASURE_SAVED, L.OPT_MEASURE_SAVED_BUTTON, function() ns.Measure.ShowSaved() end, L.OPT_MEASURE_SAVED_TIP)
    page:StatusButton()
    page:TourButton(ns.Tour.tour, L.OPT_TOUR_TIP)   -- Erklärblasen am Talentfenster wieder von vorn (Tour.lua)
    page:ResetButton()   -- „Einstellungen zurücksetzen“ (ezCore); Vorlagen bleiben
    page:Companions()

    page:Register()
end

ns.OnReady(function() ns.Try("Settings", Register) end)

function ns.OpenSettings()
    return page ~= nil and page:Open()
end
