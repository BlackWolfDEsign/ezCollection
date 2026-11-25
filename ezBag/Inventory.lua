local ADDON, ns = ...
local L = ns.L

--[[
    Zeigt an, was ezCore pro Charakter über Taschen, Bank, Post, angelegt und Gildenbank weiß:
    - die Offline-Ansicht im ezBag-Fenster (Window.lua)
    - die Anzeige der freien Plätze am Rucksack-Symbol
]]

local Core = ezCore

-- Das Erfassen (Taschen, Bank, Post, angelegt, Gildenbank, Post an Twinks) liegt seit 1.4 in ezCore
-- (ezCore/Charakter/Inventory.lua, ezCore/Charakter/Mail.lua). ezBag zeigt es an: Rucksack-Symbol und Fenster (den Tooltip zeigt ezCore).
-- ns.Inventory bietet weiter alles wie bisher (CarriedBags, BankBags, IsBankOpen, LOCATIONS …).
local Inventory = setmetatable({}, { __index = Core.Inventory })
ns.Inventory = Inventory

-- Empfängername → Datensatz eines eigenen Charakters (jetzt ezCore.FindChar).
function Inventory.FindChar(name)
    return Core.FindChar(name)
end

---------------------------------------------------------------------------
-- Anzeige am Rucksack-Symbol: freie Plätze
---------------------------------------------------------------------------

local bagText

-- Den Text der freien Plätze liefert ezCore (Core.FreeSpaceText – eine Fassung für Rucksack-Symbol, Suchzeile der
-- Bank, Menü der Werkzeugleisten und ezPanels Taschen-Block; Auftrag des Nutzers vom 23.11.2026).
-- Farbe für die freien Plätze: weiß, gold wenn es knapp wird, rot wenn alles voll ist (ezCores Rollen
-- highlight, normal, bad – Blizzards Farbobjekte; Welle 23, A3).
function ns.SpaceColor(free, total)
    if free == 0 then return ns.TipRGB("bad") end
    if free <= math.max(2, math.floor(total * 0.1)) then return ns.TipRGB("normal") end
    return ns.TipRGB("highlight")
end

function Inventory.UpdateBagButton()
    local button = _G.MainMenuBarBackpackButton
    if not button or not ns.S then return end
    local blizzCount = button.Count or _G.MainMenuBarBackpackButtonCount
    if not ns.S.bagCount then
        if bagText then bagText:Hide() end
        if blizzCount then blizzCount:SetAlpha(1) end
        return
    end
    if not bagText then
        bagText = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        bagText:SetDrawLayer("OVERLAY", 7)
        bagText:SetPoint("BOTTOM", button, "BOTTOM", 0, 2)
    end
    -- Nur normale Taschen zählen (Köcher und Berufstaschen fassen nicht alles). Core.BagSpaceOf prüft, ob der Stand
    -- brauchbar ist (PANEL-08): direkt nach dem Einloggen meldet der Client mitunter „0 von 0“ – dann der zuletzt
    -- gemerkte Stand; ist keiner brauchbar, bleibt Blizzards eigene Zahl stehen.
    local free, total = Core.BagSpaceOf()
    if not (free and total) then
        bagText:Hide()
        if blizzCount then blizzCount:SetAlpha(1) end
        return
    end
    bagText:SetText(Core.FreeSpaceText(free, true))
    bagText:SetTextColor(ns.SpaceColor(free, total))
    bagText:Show()
    if blizzCount then blizzCount:SetAlpha(0) end
end

---------------------------------------------------------------------------
-- Start und Nachrichten aus ezCore
---------------------------------------------------------------------------

ns.OnReady(function()
    -- Einmal sagen, nicht bei jedem Einloggen bis zum ersten Bankbesuch (V-057).
    local notices = ns.Notices()
    if not Core.me.bankSeen and notices and not notices.bankHint then
        notices.bankHint = true
        C_Timer.After(6, function() ns.Print(L.BANK_HINT) end)
    end
end)

Core.Listen("INVENTORY_CHANGED", function()
    Inventory.UpdateBagButton()
    if ns.Window then ns.Window.OnDataChanged() end
end, ADDON)
Core.Listen("GUILDBANK_CHANGED", function()
    if ns.Window then ns.Window.OnDataChanged() end
end, ADDON)
Core.Listen("BANK_OPENED", function()
    if ns.Window then ns.Window.OnBankOpened() end
end, ADDON)
Core.Listen("BANK_CLOSED", function()
    if ns.Window then ns.Window.OnBankClosed() end
end, ADDON)

ns.OnSettingChanged(function(key)
    if key == "bagCount" then Inventory.UpdateBagButton() end
end)

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------

-- Die Abschnitte „Anzahl bei Twinks“ und „Item-Wissen“ zeigt seit BAG-05 (V-048, Entscheidungsfrage 5 – Empfehlung
-- umgesetzt, Antwort offen) ezCore selbst (ezCore/Bausteine/ItemTooltip.lua, Schalter auf der Seite „ezCollection“ unter
-- „Tooltip“) – auch ohne ezBag. Vorher meldete ezBag hier "ezBag.counts" (10) und "ezBag.knowledge" (20) an; ezCore
-- übernimmt ezBags Werte tooltipCounts/itemInfo einmal (ItemTooltip.MigrateFromEzBag). ezBag behält nur, was an
-- Taschenplätzen hängt. Die alten Befehle /eb tooltip und /eb wissen schalten ezCores Schalter (ns.ToggleCoreTooltip).
