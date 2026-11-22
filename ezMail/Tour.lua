local _, ns = ...
local L = ns.L

-- Kurzüberblick und Rundgang (ezCore/Tests/einfuehrung_funktionen_test.lua): je Zeile von L.INTRO_FEATURES der
-- Schritt (oder die Schritte) des Rundgangs, der sie zeigt; false = kein eigenes Ziel (Automatik, Tooltip, Daten oder
-- ein Fenster ohne Rundgang). Eine neue Zeile im Kurzüberblick braucht hier ihren Eintrag.
ns.FEATURE_STEPS = { "select", "filter", { "book", "quick" }, false, "history" }

--[[
    Rundgang mit Erklärblasen (Abschlussrunde „Tooltip-Guide“, Entscheidung des Nutzers 13.11.2026):
    Beim ersten Öffnen des Postfensters zeigt ezMail nacheinander Blasen zu den wichtigsten Funktionen,
    über ezCore.NewTour. „OK“ oder das X führt zur nächsten; gemerkt wird je Blase in ezMailDB.hints.
    „Erneut zeigen“ unter „Erweitert“ (page:TourButton) setzt den Rundgang zurück.
    Blasen auf „Verschicken“ kommen, sobald dieser Reiter offen ist; ein Ziel, das gerade nicht zu sehen ist
    (Funktion aus, keine Stapel in den Taschen), überspringt ezCore, ohne es als gesehen zu merken.
]]

local Tour = {}
ns.Tour = Tour

local START_DELAY = 0.5   -- erst wenn Reiter und Leiste stehen und der Posteingang geladen ist

-- area: Blizzards Reiter, mit dem die Blase sich ausblendet (InboxFrame bzw. SendMailFrame).
local STEPS = {
    { key = "filter", area = "InboxFrame", side = "above", text = L.TOUR_FILTER,
        target = function() return ns.Inbox.FilterButton() end },
    { key = "select", area = "InboxFrame", side = "below", text = L.TOUR_SELECT,
        target = function() return ns.Inbox.Bar() end },
    { key = "overview", area = "InboxFrame", side = "right", text = L.TOUR_OVERVIEW,
        target = function() return ns.Overview.Tab() end },
    { key = "history", area = "InboxFrame", side = "right", text = L.TOUR_HISTORY,
        target = function() return ns.History.Tab() end },
    { key = "book", area = "SendMailFrame", side = "right", text = L.TOUR_BOOK,
        target = function() return ns.Send.BookButton() end },
    { key = "quick", area = "SendMailFrame", side = "right", text = L.TOUR_QUICK,
        target = function() return ns.QuickAttach.FirstTab() end },
    { key = "wire", area = "SendMailFrame", side = "above", text = L.TOUR_WIRE,
        target = function() return ns.Wire.Button() end },
}

-- Speicher (ezMailDB.hints) und der gebündelte Start kommen aus ezCore: viele Auslöser (MAIL_SHOW, Reiterwechsel)
-- ergeben einen Start nach START_DELAY, im Kampf erst danach, nichts, wenn alles gesehen ist.
local tour = ezCore.NewTour({ owner = ns, field = "hints", steps = STEPS })

function Tour.Object() return tour end

-- → true, wenn ein Start vorgemerkt ist. Ist das Postfenster dann schon wieder zu, sind die Ziele unsichtbar und
-- ezCore zeigt nichts (ohne die Schritte als gesehen zu merken).
function Tour.StartSoon()
    return tour:StartSoon(nil, START_DELAY)
end

ns.WhenMailUI("Rundgang", function()
    for _, step in ipairs(STEPS) do step.parent = _G[step.area] end
    -- Reiterwechsel im Postfenster: die Blasen des anderen Reiters
    for _, name in ipairs({ "InboxFrame", "SendMailFrame" }) do
        local frame = _G[name]
        if frame and frame.HookScript then frame:HookScript("OnShow", function() Tour.StartSoon() end) end
    end
end)

ns.On("MAIL_SHOW", function() Tour.StartSoon() end)
