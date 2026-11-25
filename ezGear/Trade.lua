local _, ns = ...

--[[
    Handelsfenster zwischen zwei Spielern (Blizzards TradeFrame): derselbe Pfeil wie in der Tasche auf den sechs
    Plätzen beider Seiten (Nutzer am 24.11.2026: „ezgear zeigt keinen pfeil im handelsfenster“). Bei deinem Gegenüber
    sagt er, ob dich ein Teil verbessert; auf deiner Seite steht er, weil dasselbe Teil ihn in der Tasche trägt – so
    gibst du nichts Besseres aus Versehen weg. Der siebte Platz („Wird nicht gehandelt“) bekommt keinen: Was dort
    liegt, bleibt bei seinem Besitzer.

    Schalter und Rücksicht wie an den Taschenplätzen (bagArrows): Zeigt Pawn bzw. Forever++ dort seine Pfeile, hält
    sich ezGear auch hier zurück – sonst stünden in Tasche und Handelsfenster zwei verschiedene Bewertungen.

    Blizzard zeichnet jeden Platz mit TradeFrame_UpdatePlayerItem(id) bzw. TradeFrame_UpdateTargetItem(id): beim Öffnen
    (TRADE_SHOW), bei jedem Wechsel (TRADE_PLAYER_ITEM_CHANGED, TRADE_TARGET_ITEM_CHANGED) und wenn Gegenstandsdaten
    nachkommen (GET_ITEM_INFO_RECEIVED) – Forever-Quelle 1.60.1.71091, Blizzard_UIPanels_Game/Mainline/TradeFrame.lua.
    ezGear hängt sich dahinter, liest nur den Link des Platzes und legt eigene Texturen an (Marks.lua). Halb geladene
    Werte zieht Marks.SetUpgrade selbst nach. Geht das Fenster zu, ist alles leer.
]]

local Trade = {}
ns.Trade = Trade

-- Seite → Name von Blizzards Platzknopf (TradeItemTemplate) und Blizzards Link zum Platz
Trade.SIDES = {
    player = { button = "TradePlayerItem%dItemButton", link = "GetTradePlayerItemLink" },
    target = { button = "TradeRecipientItem%dItemButton", link = "GetTradeTargetItemLink" },
}

-- Zahl der Plätze, die übergeben werden (Blizzards MAX_TRADABLE_ITEMS; darüber liegt nur der siebte)
function Trade.Slots()
    return ns.Num(MAX_TRADABLE_ITEMS) or 6
end

local function IsOpen()
    return TradeFrame ~= nil and TradeFrame:IsShown() == true
end

-- Einen Platz zeichnen: Pfeil nach ezGears Bewertung; leer, wenn nichts darin liegt, der Schalter aus ist oder ein
-- anderes Addon die Pfeile zeigt. Bei geschlossenem Fenster ist nichts zu tun (geleert hat schon Trade.Clear).
function Trade.Update(side, id)
    local spec = Trade.SIDES[side]
    id = ns.Num(id)
    if not (spec and id) or id < 1 or id > Trade.Slots() or not IsOpen() then return end
    local link = ns.Active("bagArrows") and ns.Plain(ns.Call(_G[spec.link], id)) or nil
    ns.Marks.SetUpgrade(_G[spec.button:format(id)], link)
end

local function EachSlot(fn)
    for side, spec in pairs(Trade.SIDES) do
        for id = 1, Trade.Slots() do fn(side, id, spec) end
    end
end

-- Alle Plätze beider Seiten neu zeichnen
function Trade.Refresh()
    if IsOpen() then EachSlot(Trade.Update) end
end

-- Fenster zu: alle Pfeile weg, auch was noch auf Daten wartet
function Trade.Clear()
    EachSlot(function(_, id, spec) ns.Marks.SetUpgrade(_G[spec.button:format(id)], nil) end)
end

local function Install()
    if type(TradeFrame_UpdatePlayerItem) ~= "function" or type(TradeFrame_UpdateTargetItem) ~= "function"
        or type(TradeFrame) ~= "table" then return false end
    hooksecurefunc("TradeFrame_UpdatePlayerItem", function(id) ns.Try("Trade", Trade.Update, "player", id) end)
    hooksecurefunc("TradeFrame_UpdateTargetItem", function(id) ns.Try("Trade", Trade.Update, "target", id) end)
    TradeFrame:HookScript("OnHide", function() ns.Try("Trade", Trade.Clear) end)
    return true
end

ns.OnReady(function()
    if not Install() then ns.WhenAddOnLoaded("Blizzard_UIPanels_Game", Install) end
    ns.Listen("SCORES_CHANGED", Trade.Refresh)
    -- Zeichen an den Pfeilen (Farbenblind-Hilfe) bzw. Forever++ umgelegt: sofort nachziehen (Pawn meldet sein Umschalten
    -- nicht; es gilt ab dem nächsten Zeichnen des Platzes)
    ezCore.Listen("GLOW_MARKS_CHANGED", Trade.Refresh, "ezGear")
    ezCore.Listen("OTHER_ADDONS_CHANGED", Trade.Refresh, "ezGear")
    ns.OnSettingChanged(function(key)
        if key == "bagArrows" then Trade.Refresh() end
    end)
end)
