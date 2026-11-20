local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Rundgang mit Erklärblasen (Abschlussrunde „Tooltip-Guide“, Entscheidung des Nutzers 13.11.2026): beim ersten
    Öffnen des Auktionshauses die wichtigsten Funktionen, jede dort, wo ihr Knopf steht. Ein Ziel, das gerade nicht
    zu sehen ist (anderer Reiter, noch kein Gegenstand im Verkaufsbereich), wartet, bis es erscheint. Gesehene Blasen
    stehen in ezAuctionDB.hints; „Erweitert“ → „Erklärung – Erneut zeigen“ setzt sie zurück (page:TourButton).
    Gebaut mit Core.NewTour({ owner = ns, field = "hints" }); die Blasen hängen an ihrem Ziel und verschwinden mit
    ihm. Gestartet wird über tour:StartSoon: viele Auslöser kurz nacheinander ergeben einen Start, im Kampf erst
    danach (Core.AfterCombat) und nur bei offenem Auktionshaus (enabled).
]]

local Tour = {}
ns.Tour = Tour

-- Rücksicht (AH-31, Welle 15): die erste Blase steht nur, solange ein fremdes Auktions-Addon einen Teil übernimmt
-- (ns.Yield.Other), und nur mit dem Schalter besideNotice – einmal; „OK“ oder das X merkt sie als gesehen. Sie zeigt
-- auf das Zahnrad: dort führen „Rücksicht“ und „Einstellungen“ zu dem, was ezAuction allein kann.
function Tour.BesideTarget()
    if not (ns.Enabled("besideNotice") and ns.Yield and ns.Yield.Other()) then return nil end
    return ns.Gear and ns.Gear.Button() or nil
end

Tour.STEPS = {
    { key = "beside", target = function() return Tour.BesideTarget() end, text = L.TOUR_BESIDE, side = "below" },
    -- rechts statt darunter: unter dem Knopf steht seit Welle 27 die Zeile mit dem Pfeil, den die Blase erklärt
    { key = "scan", target = function() return ns.Scan.Button() end, text = L.TOUR_SCAN, side = "right" },
    { key = "lists", target = function() return ns.Buy.HeaderButton() end, text = L.TOUR_LISTS, side = "right" },
    { key = "sellList", target = function() return ns.Sell.ToggleButton() end, text = L.TOUR_SELL_LIST, side = "below" },
    { key = "priceRule", target = function() return ns.Sell.RuleButton() end, text = L.TOUR_PRICE_RULE, side = "right" },
    { key = "undercut", target = function() return ns.Undercut.Button() end, text = L.TOUR_UNDERCUT, side = "above" },
    { key = "history", target = function() return ns.History.Tab() end, text = L.TOUR_HISTORY, side = "below" },
    -- Seitenteil „Markt“ (MarketPanel.lua): der Pfeil-Knopf am Rand des Auktionsfensters
    { key = "market", target = function() return ns.MarketPanel.Arrow() end, text = L.TOUR_MARKET, side = "below" },
}

function Tour.Get()
    if not Tour.tour and ns.db then
        -- Immer nur eine Blase (single): Zeigt der Rundgang die nächste (auch nach „OK“ an einer Blase), verschwinden
        -- die übrigen – sonst stünde nach einem Reiterwechsel die Blase eines früheren Schritts neben einer späteren.
        -- Seit Welle 23 übernimmt das ezCore (Core.NewTour mit single, dazu enabled und Kampf in tour:Next); die eigene
        -- Hülle um tour:Next ist weg.
        Tour.tour = Core.NewTour({ owner = ns, field = "hints", steps = Tour.STEPS, single = true,
            enabled = function() return ns.AuctionHouseShown() end })
    end
    return Tour.tour
end

-- Nächste noch nicht gesehene Blase zeigen, deren Ziel zu sehen ist; die übrigen ausblenden (immer nur eine).
-- Rückgabe: Schlüssel der gezeigten Blase oder nil.
function Tour.Continue()
    local tour = Tour.Get()
    if not (tour and ns.AuctionHouseShown()) then return nil end
    local key = tour:Next()
    -- Nichts mehr zu zeigen: auch eine stehengebliebene Blase geht (single blendet nur beim Zeigen einer neuen aus;
    -- die frühere Hülle um tour:Next tat beides).
    if key == nil then tour:HideAll() end
    return key
end

-- Kurz warten, bis Blizzard Reiter und Knöpfe umgestellt hat (tour:StartSoon bündelt und wartet das Kampfende ab).
-- Rückgabe: true, wenn ein Start vorgemerkt ist.
function Tour.Soon()
    local tour = Tour.Get()
    return tour ~= nil and tour:StartSoon(nil, 0.3)
end
for _, message in ipairs({ "AH_SHOW", "AH_MODE", "HISTORY_VIEW", "SELL_ITEM", "LISTS_CHANGED" }) do
    ns.Listen(message, function() Tour.Soon() end)
end
