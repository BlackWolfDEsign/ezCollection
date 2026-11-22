local _, ns = ...
local L = ns.L

-- Kurzüberblick und Rundgang (ezCore/Tests/einfuehrung_funktionen_test.lua): je Zeile von L.INTRO_FEATURES der
-- Schritt (oder die Schritte) des Rundgangs, der sie zeigt; false = kein eigenes Ziel (Automatik, Tooltip, Daten oder
-- ein Fenster ohne Rundgang). Eine neue Zeile im Kurzüberblick braucht hier ihren Eintrag.
ns.FEATURE_STEPS = { { "search", "filter" }, "stack", "learnAll", "upcoming", "repair" }
local Core = ezCore

--[[
    Rundgang mit Erklärblasen (Abschlussrunde „Tooltip-Guide“, Core.NewTour): beim ersten Öffnen des Händlerfensters
    Suche, Filter, „Mehrere kaufen“ und Auto-Reparatur, beim ersten Lehrer „Alles lernen“, am Zauberbuch „Was kommt
    wann“. „OK“ oder das X führt zur nächsten Blase. Ein Schritt, dessen Knopf gerade nicht zu sehen ist (Händler ohne
    Reparatur, keine stapelbare Ware, Tierausbilder, ein anderes Addon lernt schon alles), kommt beim nächsten Mal.
    Gesehen wird für den ganzen Account gemerkt (ezMerchantDB.hints); „Erklärung erneut zeigen“ unter „Erweitert“
    (page:TourButton) setzt zurück.
]]

-- Das erste sichtbare Plus „Mehrere kaufen“ auf der aktuellen Seite.
local function FirstPlus()
    local merchant = ns.Merchant
    for _, f in ipairs(merchant and merchant.frames or {}) do
        if f.plus and f.plus:IsVisible() then return f.plus end
    end
    return nil
end

-- Blasen im Händlerfenster gehören zu ihm (schließen mit ihm); die übrigen hängen an ihrem Knopf.
local merchant = MerchantFrame

ns.tour = Core.NewTour({
    owner = ns, field = "hints",       -- Speicher: ezMerchantDB.hints (Gerüst von ezCore)
    steps = {
        { key = "search", target = function() return ns.Merchant.ui.search end, text = L.TOUR_SEARCH, side = "below",
          parent = merchant },
        { key = "filter", target = function() return ns.Merchant.ui.filter end, text = L.TOUR_FILTER, side = "below",
          parent = merchant },
        { key = "stack", target = FirstPlus, text = L.TOUR_STACK, side = "right", parent = merchant },
        { key = "repair", target = function() return ns.Repair.checks.repairAuto end, text = L.TOUR_REPAIR,
          side = "below", parent = merchant },
        { key = "learnAll", target = function() return ns.Trainer.button end, text = L.TOUR_LEARN, side = "above" },
        { key = "upcoming", target = function() return ns.Upcoming.tab end, text = L.TOUR_UPCOMING, side = "right" },
    },
})

-- Zeigt die Blase zum ersten noch nicht gesehenen Knopf, der gerade zu sehen ist. Jede andere Blase des Rundgangs
-- wird ausgeblendet (ihr Knopf ist verschwunden, etwa auf dem Reiter „Rückkauf“) und kommt später wieder.
-- → Schlüssel der gezeigten Blase oder nil
function ns.ShowTour()
    local tour = ns.tour
    if not tour or tour:Done() then return nil end
    local key = tour:Start()
    for _, step in ipairs(tour.steps) do
        if step.key ~= key then tour.hints.Hide(step.key) end
    end
    return key
end

-- Kurz warten, bis Blizzards Fenster und ezMerchants Knöpfe fertig aufgebaut sind.
local ShowSoon = ns.Throttle(function() ns.ShowTour() end, 0.3)

ns.OnReady(function()
    ns.Listen("MERCHANT_LAYOUT", function() ShowSoon() end)
    ns.WhenAddOnLoaded("Blizzard_TrainerUI", function()
        if ClassTrainerFrame then ClassTrainerFrame:HookScript("OnShow", function() ShowSoon() end) end
    end)
    ns.WhenAddOnLoaded("Blizzard_PlayerSpells", function()
        if not PlayerSpellsFrame then return end
        PlayerSpellsFrame:HookScript("OnShow", function() ShowSoon() end)
        local book = PlayerSpellsFrame.SpellBookFrame
        if book then book:HookScript("OnShow", function() ShowSoon() end) end
    end)
end)
