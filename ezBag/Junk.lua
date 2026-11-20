local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Plunder beim Händler automatisch verkaufen.
    Seltene und bessere Gegenstände werden nie automatisch verkauft.
    Als Plunder markieren: Alt+Rechtsklick auf einen Gegenstand (siehe Groups.lua).

    Ausgeführt wird der Verkauf von ezCore (Core.Junk.Sell: gedrosselte Runden, Abbruch beim Schließen des Händlers –
    eine Fassung für ezBag, ezMerchant und ezPanel; BAG-06, V-049, Frage 14 – Empfehlung umgesetzt, Antwort offen).
    Mit ezMerchants Schalter „Im Auktionshaus Wertvolles behalten“ bleiben Gegenstände mit ezCores Goldmünze liegen
    (skipAuctionWorth, Welle 23); ezMerchant nennt sie danach (ShowKept).
    ezBag meldet nur seine Regel an (Junk.Rule über Core.Junk.SetRule: Gruppen, Schlösser „nie verkaufen“,
    Markierungen, Material für ezCrafts Einkaufsliste) und behält seine Meldungen (SOLD, SOLD_PROTECTED) und den
    Schalter autoSell. Die Schnittstellen IsJunk und SellJunk bleiben und leiten weiter.
]]

local Junk = {}
ns.Junk = Junk

-- ezBags Regel, was als Plunder gilt – in der Form von Core.Junk.SetRule: fn(info, bag, slot, opts) → verkaufen,
-- markiert, geschützt. Grau und keiner anderen Gruppe zugewiesen (sonst Schloss „nie verkaufen“) oder als Plunder
-- markiert. Nie, was ezCrafts Einkaufsliste braucht (CRAFT-14) – auch nicht, wenn es als Plunder markiert ist.
-- Seltenes und den Händlerwert prüft ezCore danach (Core.Junk.Check) – eine Stelle für alle Regeln.
function Junk.Rule(info)
    local itemID = ns.ItemIDOf(info)
    if not itemID or info.hasNoValue then return false, false, false end
    local isJunk, marked = ns.IsJunk(info)
    if not isJunk then return false, false, false end
    if ns.CraftNeed and ns.CraftNeed(itemID) then return false, marked, false end
    return true, marked, false
end

-- Eine Stelle für „würde ezBag das als Plunder verkaufen?“ (Schnittstelle IsJunk, „Platz schaffen“): ezBags Regel,
-- dazu dieselben Grenzen wie in ezCore (Core.Junk.Check): Seltenes und Besseres nie, nur mit Händlerwert.
-- → verkaufen, markiert, geschützt (ein als Plunder markierter seltener Gegenstand)
local function Sellable(info)
    local sell, marked = Junk.Rule(info)
    if not sell then return false, marked, false end
    if (ns.PlainID(info.quality) or 0) >= 3 then return false, marked, true end
    local price = Core.VendorPrice(info.hyperlink or info.itemID)
    return (price or 0) > 0, marked, false
end
Junk.Sellable = Sellable

-- „Im Auktionshaus Wertvolles behalten“ (AH-27, Welle 23): ezMerchants Schalter keepAuctionWorth gilt auch für ezBags
-- Automatik und SellJunk. ezMerchant sagt über ezCore.API("ezMerchant").KeepAuctionWorth(), ob Gegenstände mit ezCores
-- Goldmünze liegen bleiben; ohne ezMerchant (oder ohne die Auskunft) verkauft ezBag wie bisher. Was liegen bleibt,
-- nennt ezMerchant über ShowKept(liste) – Chatzeile und Zeile unter dem Händlerfenster mit „Trotzdem verkaufen“; nie
-- still weniger verkaufen. → die Schnittstelle von ezMerchant oder nil
-- Frage und Weitergabe stehen seit dem 20.11.2026 in ezCore (Core.Junk.MerchantKeeps/ShowKept), damit ezPanels
-- „Graue verkaufen“ denselben Weg nimmt; die beiden Felder hier bleiben als Weiterleitung.
local function MerchantKeeps()
    return Core.Junk.MerchantKeeps()
end
Junk.MerchantKeeps = MerchantKeeps

-- Behaltene Gegenstände an ezMerchant reichen (nur bei offenem Händler: ezCore meldet das Ende verzögert).
local function ShowKept(list)
    if not ns.AtMerchant() then return false end
    return Core.Junk.ShowKept(list, "ezBag")
end
Junk.ShowKept = ShowKept

-- Ergebnis eines Verkaufs aus ezCore (onDone): ezBags eigene Meldungen, wie vor der Umstellung; behaltene
-- Gegenstände (nur mit skipAuctionWorth) nennt ezMerchant.
local function Report(sold, gained, protected, kept)
    sold, gained, protected = tonumber(sold) or 0, tonumber(gained) or 0, tonumber(protected) or 0
    if sold > 0 and gained > 0 then ns.Print(L.SOLD:format(ns.CountWord("ITEM", sold), ns.CoinText(gained))) end
    if protected > 0 then ns.Print(ns.CountText("SOLD_PROTECTED", protected)) end
    ShowKept(kept)
end
Junk.Report = Report

-- manual = von Hand ausgelöst (Menü der Plunder-Gruppe, ezPanels Knopf): verkauft auch graue
-- Gegenstände, wenn Leatrix Plus das sonst übernimmt. → true, wenn der Verkauf beginnt
-- Im Kampf verkauft ezCore nichts; von Hand sagt es das im Chat (byHand: ezCores Kampfsatz mit JUNK_WHAT, Fund des
-- code-reviewers, Welle 28), die Automatik bleibt still. Hört ein Verkauf wegen des Kampfes auf, meldet ezCore das nach der Summe.
function Junk.SellNow(manual)
    local J = Core.Junk
    if not (J and J.Sell) or not ns.AtMerchant() then return false end
    if ns.ClearCraftNeeds then ns.ClearCraftNeeds() end   -- die Einkaufsliste frisch lesen
    local opts = { owner = ADDON, quiet = true, onDone = Report, byHand = manual == true,
        onlyMarked = not manual and ns.OtherSellsJunk() ~= nil }
    if MerchantKeeps() then opts.skipAuctionWorth = true end
    local started, kept = J.Sell(opts)
    if started == true then ShowKept(kept) end
    return started == true
end

-- Läuft gerade ein Verkauf (egal wer ihn ausgelöst hat)?
function Junk.Selling()
    return Core.Junk ~= nil and Core.Junk.Selling() == true
end

-- Die Regel bei ezCore anmelden: ezMerchants Knopf und ezPanels „Grau verkaufen“ verkaufen damit dasselbe.
if Core.Junk and Core.Junk.SetRule then Core.Junk.SetRule(ADDON, Junk.Rule) end

---------------------------------------------------------------------------
-- Schnittstelle für andere Module (ezCore.API("ezBag"), siehe README): ezPanels Knopf „Grau verkaufen“
-- und ezMerchants Schalter nutzen ezBags Regeln (Schlösser, Markierungen), wenn ezBag läuft.
---------------------------------------------------------------------------

ns.API = ns.API or {}

-- IsJunk(bag, slot) → verkauft, markiert, geschützt: würde ezBag diesen Platz beim Händler verkaufen? (markiert =
-- von Hand als Plunder markiert, geschützt = markiert, aber selten oder besser). Leerer Platz, geheime Werte,
-- Seltenes und Besseres, ohne Händlerwert, Material für ezCrafts Einkaufsliste → false.
function ns.API.IsJunk(bag, slot)
    if type(bag) ~= "number" or type(slot) ~= "number" then return false, false, false end
    return Sellable(C_Container.GetContainerItemInfo(bag, slot))
end

-- SellJunk() → true, wenn der Verkauf beginnt (Händler offen, nicht schon dabei). Verkauft in Runden wie
-- beim Ansprechen des Händlers (über Core.Junk.Sell) und meldet das Ergebnis im Chat.
function ns.API.SellJunk()
    return Junk.SellNow(true)
end

-- AutoSell() → true/false: verkauft ezBag beim Ansprechen des Händlers von selbst (Schalter autoSell)?
-- Für ezMerchants Schalter am Händlerfenster (BAG-07, V-121) – lesen ohne in ezBags Einstellungen zu greifen.
-- Seit der Einstellungs-Prüfung vom 19.11.2026 (Nr. 59/60) ist es ezCores gemeinsamer Schalter (ns.SHARED, Core.lua).
function ns.API.AutoSell()
    return ns.Enabled("autoSell") == true
end

-- SetAutoSell(an) → neuer Wert: setzt den Schalter über ns.SetSetting (führt auf ezCores gemeinsamen Schalter), damit
-- beide Einstellungsseiten und die Zuhörer mitziehen. Vor dem Laden der Einstellungen → nil.
function ns.API.SetAutoSell(on)
    if not ns.S then return nil end
    ns.SetSetting("autoSell", on and true or false)
    return ns.Enabled("autoSell") == true
end

-- Hinweis am Händler, solange „Plunder beim Händler verkaufen“ aus ist (ezCores Hinweis-Helfer, einmal je Account;
-- Antwort des Nutzers vom 17.11.2026: ab Werk aus, mit Hinweis und Knopf „Einschalten“). ezMerchants Schalter
-- „Plunder automatisch verkaufen“ ist mit ezBag derselbe (er schaltet ezBags), darum meldet ezMerchant seinen nur ohne
-- ezBag an. Für die beim Update umgestellten (ns.MigrateAutoSellOptIn) sagt der Hinweis das dazu.
function Junk.RegisterOptInHint()
    local Hint = Core.OptInHint
    if not (Hint and Hint.Register) then return false end
    return Hint.Register("ezBag.autoSell", {
        owner = ADDON,
        window = "merchant",
        label = function() return L.OPT_autoSell end,
        what = function() return L.OPTIN_autoSell end,
        isOn = function() return ns.API.AutoSell() end,
        enable = function() return ns.API.SetAutoSell(true) == true end,
        switchedOff = function() return type(ns.db) == "table" and ns.db.autoSellOff28Was == true end,
    })
end
Junk.RegisterOptInHint()

ns.On("MERCHANT_SHOW", function()
    if not ns.Enabled("autoSell") or IsShiftKeyDown() then return end
    -- Kurz warten, bis der Händler-Rahmen offen ist.
    C_Timer.After(0.2, function() Junk.SellNow(false) end)
end)
