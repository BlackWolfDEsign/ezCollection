local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Reiter „Auktionen“:
      - „unterboten“: Für jeden eigenen Gegenstand fragt ezAuction die aktuellen Angebote ab (eine Suche je
        Gegenstand als Auftrag in ezCores Warteschlange – AH-37 –, nur in Blizzards Übersicht „Alle Auktionen“). Liegt ein fremdes
        Angebot unter dem eigenen Preis, bekommt die Zeile einen roten Hauch und einen roten Pfeil.
      - Knopf „Unterbotene abbrechen (n)“ neben Blizzards „Auktion abbrechen“: bricht je Klick EINE unterbotene
        Auktion ab (ohne Gebot; Blizzard verlangt einen Tastendruck je Abbruch).
      - Summe der laufenden Auktionen neben dem Goldbetrag unten links (und was schon verkauft ist).
    Eigene Auktionen von Waren (Commodities): buyoutAmount gilt je Stück; Einzelstücke: je Auktion.
]]

local Undercut = { results = {}, checked = {}, queue = {}, groups = {} }
ns.Undercut = Undercut

local cancelButton, rivalsButton, sumText, redecorate
local FRESH = 120          -- Sekunden: so lange gilt eine Prüfung je Gegenstand
local TIMEOUT = 10

local function AuctionsFrame() return AuctionHouseFrame and AuctionHouseFrame.AuctionsFrame end

-- Unter-Reiter „Verlauf“ (History.lua) offen: dann gehören Knopf und Summe nicht dorthin.
local function HistoryShown() return ns.History ~= nil and ns.History.IsShown() end

local function ActiveStatus() return Enum and Enum.AuctionStatus and Enum.AuctionStatus.Active or 0 end
local function SoldStatus() return Enum and Enum.AuctionStatus and Enum.AuctionStatus.Sold or 1 end

function Undercut.Owned()
    local owned = C_AuctionHouse.GetOwnedAuctions and Core.Call(C_AuctionHouse.GetOwnedAuctions)
    return type(owned) == "table" and owned or {}
end

local function IsCommodity(itemKey)
    local info = Core.Call(C_AuctionHouse.GetItemKeyInfo, itemKey)
    return type(info) == "table" and info.isCommodity == true
end

-- Preis einer eigenen Auktion, vergleichbar mit den Angeboten (Waren je Stück, Einzelstücke je Auktion).
function Undercut.UnitPrice(auction, commodity)
    local price = auction.buyoutAmount
    if type(price) ~= "number" or price <= 0 then return nil end
    if commodity then return price end
    return price / math.max(1, auction.quantity or 1)
end

-- Günstigstes fremdes Angebot aus den geladenen Suchergebnissen; zweite Rückgabe: alle fremden Angebote als Liste
-- von Stückpreisen (je Zeile von Blizzards Liste eine – eine Zeile kann bei Waren mehrere Anbieter zum selben Preis
-- bündeln; AH-25 zählt darum Angebote, nicht Anbieter).
function Undercut.ForeignLowest(itemKey, commodity)
    local lowest, offers = nil, {}
    if commodity then
        local itemID = itemKey.itemID
        local count = Core.Call(C_AuctionHouse.GetNumCommoditySearchResults, itemID) or 0
        for index = 1, count do
            local result = Core.Call(C_AuctionHouse.GetCommoditySearchResultInfo, itemID, index)
            if result and type(result.unitPrice) == "number" and (result.numOwnerItems or 0) < (result.quantity or 0) then
                offers[#offers + 1] = result.unitPrice
                if not lowest or result.unitPrice < lowest then lowest = result.unitPrice end
            end
        end
    else
        local count = Core.Call(C_AuctionHouse.GetNumItemSearchResults, itemKey) or 0
        for index = 1, count do
            local result = Core.Call(C_AuctionHouse.GetItemSearchResultInfo, itemKey, index)
            if result and not result.containsOwnerItem and type(result.buyoutAmount) == "number" then
                local unit = result.buyoutAmount / math.max(1, result.quantity or 1)
                offers[#offers + 1] = unit
                if not lowest or unit < lowest then lowest = unit end
            end
        end
    end
    return lowest, offers
end

-- Abstand einer unterbotenen Auktion (AH-25): { diff = um so viel je Stück unterboten, below = so viele fremde Angebote
-- darunter, lowest } – nil, wenn sie nicht unterboten ist oder noch keine Prüfung vorliegt.
function Undercut.Detail(auction)
    if type(auction) ~= "table" or Undercut.results[auction.auctionID] ~= true then return nil end
    local key = type(auction.itemKey) == "table" and ns.KeyString(auction.itemKey)
    local checked = key and Undercut.checked[key]
    local group = key and Undercut.groups[key]
    if not (checked and checked.lowest) then return nil end
    local unit = Undercut.UnitPrice(auction, group and group.commodity or IsCommodity(auction.itemKey))
    if not unit then return nil end
    local below = 0
    for _, price in ipairs(checked.offers or {}) do
        if price < unit then below = below + 1 end
    end
    return { diff = math.max(0, math.floor(unit - checked.lowest + 0.5)), below = below, lowest = checked.lowest }
end

-- Zeile für den Tooltip: „Um 3 S unterboten, 2 Angebote darunter (günstigstes: 1 G 20 S je Stück).“
-- Immer an seit der Einstellungs-Prüfung vom 19.11.2026 (Nr. 17).
function Undercut.DetailText(auction)
    local detail = Undercut.Detail(auction)
    if not detail then return nil end
    return L.UNDERCUT_DETAIL:format(ns.Money(detail.diff),
        Core.Plural(detail.below, L.UNDERCUT_BELOW_ONE, L.UNDERCUT_BELOW_MANY), ns.Money(math.floor(detail.lowest + 0.5)))
end

---------------------------------------------------------------------------
-- Prüfen
---------------------------------------------------------------------------

-- Nachricht an andere Module (Welle 23; Wunsch aus ezPanel, Baustein „Auktionen“, AH-34): die eigenen Auktionen oder
-- die Unterbieten-Prüfung haben sich geändert – ezCore.API("ezAuction").Auctions(charKey) neu lesen. Gesammelt (0,3 s):
-- eine Prüfung über viele Gegenstände meldet sich nicht je Gegenstand.
Core.RegisterMessage("EZAUCTION_AUCTIONS_CHANGED", "ezAuction",
    "Die eigenen Auktionen oder ezAuctions Prüfung „unterboten“ haben sich geändert (lesen über ezCore.API(\"ezAuction\").Auctions(charKey)). Zuhörer: ezPanel (Baustein „Auktionen“).",
    "charKey")
Undercut.Notify = ns.Throttle(function() Core.Fire("EZAUCTION_AUCTIONS_CHANGED", ns.charKey) end, 0.3)

local function Changed()
    if redecorate then redecorate() end
    Undercut.UpdateButton()
    Undercut.Notify()
end

-- Prüfen darf ezAuction nur in Blizzards Übersicht „Alle Auktionen“ (dort zeigt Blizzard keine Suchergebnisse).
function Undercut.CanCheck()
    local frame = AuctionsFrame()
    return ns.Enabled("undercutCheck") and frame ~= nil and frame:IsShown() and frame.AllAuctionsList ~= nil
        and frame.AllAuctionsList:IsShown() and not (frame.IsDisplayingBids and frame:IsDisplayingBids())
end

function Undercut.Start()
    if not Undercut.CanCheck() then return Undercut.Stop() end
    local groups = {}
    for _, auction in ipairs(Undercut.Owned()) do
        if auction.status == ActiveStatus() and type(auction.itemKey) == "table" and auction.buyoutAmount then
            local key = ns.KeyString(auction.itemKey)
            local group = groups[key]
            if not group then
                group = { key = key, itemKey = auction.itemKey, auctions = {}, commodity = IsCommodity(auction.itemKey) }
                groups[key] = group
            end
            table.insert(group.auctions, auction)
        end
    end
    Undercut.groups = groups
    Undercut.queue = {}
    local now = GetTime()
    for key in pairs(groups) do
        local checked = Undercut.checked[key]
        if checked and now - checked.time < FRESH then
            Undercut.Apply(key, checked.lowest)
        elseif key ~= Undercut.current then
            table.insert(Undercut.queue, key)
        end
    end
    table.sort(Undercut.queue)
    Changed()
    Undercut.Pump()
end

function Undercut.Stop()
    Undercut.queue = {}
    Undercut.current = nil
    local job = Undercut.job
    Undercut.job = nil
    ns.DropJob(job)
    Undercut.UpdateButton()
end

function Undercut.Pump()
    if Undercut.current then return end
    local key = table.remove(Undercut.queue, 1)
    if not key then return Changed() end
    local group = Undercut.groups[key]
    if not group then return Undercut.Pump() end
    Undercut.current = key
    Undercut.UpdateButton()
    -- AH-37: als Auftrag in ezCores Warteschlange (Rang „modul“, Schlüssel „ezAuction.undercut“), ohne sie im eigenen
    -- Takt. Bricht ezCore ab (Suche des Spielers, keine Antwort, Haus zu), gilt die Prüfung dieses Gegenstands als
    -- gescheitert; der nächste kommt danach an die Reihe.
    local job = { name = "undercut", text = L.QUEUE_UNDERCUT, timeout = TIMEOUT + 2 }
    job.start = function()
        if Undercut.current ~= key then return ns.JobDone(job) end
        if not Undercut.CanCheck() then
            Undercut.Stop()
            return ns.JobDone(job)
        end
        local ok = pcall(C_AuctionHouse.SendSearchQuery, group.itemKey, ns.Sorts(), true)
        if not ok then return Undercut.Done(key, nil, true) end
        C_Timer.After(TIMEOUT, function()
            if Undercut.current == key and Undercut.job == job then Undercut.Done(key, nil, true) end
        end)
    end
    job.cancel = function(_, why)
        if Undercut.job ~= job or Undercut.current ~= key then return end
        if why == "closed" then return Undercut.Stop() end
        if why ~= "replaced" and why ~= "cancel" then Undercut.Done(key, nil, true) end
    end
    Undercut.job = job
    ns.Enqueue(job)
end

-- Ergebnis für einen Gegenstand übernehmen: jede eigene Auktion darüber gilt als unterboten.
function Undercut.Apply(key, lowest)
    local group = Undercut.groups[key]
    if not group then return end
    for _, auction in ipairs(group.auctions) do
        local unit = Undercut.UnitPrice(auction, group.commodity)
        Undercut.results[auction.auctionID] = (lowest ~= nil and unit ~= nil and lowest < unit) or nil
    end
end

function Undercut.Done(key, lowest, failed, offers)
    if Undercut.current ~= key then return end
    local job = Undercut.job
    Undercut.current = nil
    if not failed then
        Undercut.checked[key] = { time = GetTime(), lowest = lowest, offers = offers }
        Undercut.Apply(key, lowest)
    end
    Changed()
    -- erst den nächsten Gegenstand einreihen, dann die Liste freigeben (er folgt so vor wartenden Erfassungen)
    Undercut.Pump()
    ns.JobDone(job)
end

local function OnSearchResults(matches)
    local key = Undercut.current
    local group = key and Undercut.groups[key]
    if not (group and matches(group)) then return end
    local lowest, offers = Undercut.ForeignLowest(group.itemKey, group.commodity)
    Undercut.Done(key, lowest, false, offers)
end

ns.On("COMMODITY_SEARCH_RESULTS_UPDATED", function(_, itemID)
    OnSearchResults(function(group) return group.commodity and group.itemKey.itemID == itemID end)
end)
ns.On("ITEM_SEARCH_RESULTS_UPDATED", function(_, itemKey)
    OnSearchResults(function(group) return not group.commodity and ns.SameKey(group.itemKey, itemKey) end)
end)
ns.On("OWNED_AUCTIONS_UPDATED", function()
    if Undercut.CanCheck() then Undercut.Start() end
    Undercut.UpdateSum()
end)
ns.On("AUCTION_CANCELED", function(_, auctionID)
    if auctionID then Undercut.results[auctionID] = nil end
    Undercut.UpdateButton()
    Undercut.Notify()
end)

---------------------------------------------------------------------------
-- Abbrechen und Summe
---------------------------------------------------------------------------

-- Unterboten und noch aktiv?
local function IsUndercut(auction)
    return Undercut.results[auction.auctionID] == true and auction.status == ActiveStatus()
end

-- Lässt sich die Auktion abbrechen (kein Gebot, Blizzard erlaubt es)?
local function Cancellable(auction)
    return not auction.bidder and Core.Call(C_AuctionHouse.CanCancelAuction, auction.auctionID) ~= false
end

-- Nächste unterbotene Auktion, die sich ohne Gebot abbrechen lässt.
function Undercut.Next()
    for _, auction in ipairs(Undercut.Owned()) do
        if IsUndercut(auction) and Cancellable(auction) then return auction end
    end
    return nil
end

-- Unterbotene Auktionen: die der Knopf abbrechen kann, und die übrigen (mit Gebot bzw. von Blizzard gesperrt).
-- Der Knopf zählt nur die ersten – dieselbe Bedingung wie Undercut.Next (Vollprüfung V-160).
function Undercut.Count()
    local count, blocked = 0, 0
    for _, auction in ipairs(Undercut.Owned()) do
        if IsUndercut(auction) then
            if Cancellable(auction) then count = count + 1 else blocked = blocked + 1 end
        end
    end
    return count, blocked
end

-- Auktion, deren Konkurrenz „Konkurrenz ansehen“ zeigt (AH-25): die in Blizzards Liste gewählte (Blizzards Feld
-- selectedAuctionID, nur gelesen), sonst die erste unterbotene, sonst die erste laufende; nil ohne laufende.
function Undercut.RivalAuction()
    local selected = Core.Peek(AuctionsFrame(), "selectedAuctionID")
    local first, under
    for _, auction in ipairs(Undercut.Owned()) do
        if auction.status == ActiveStatus() and type(auction.itemKey) == "table" then
            if selected ~= nil and auction.auctionID == selected then return auction end
            first = first or auction
            if IsUndercut(auction) then under = under or auction end
        end
    end
    return under or first
end

local function AuctionName(auction)
    if auction.itemLink then return auction.itemLink end
    local info = Core.Call(C_AuctionHouse.GetItemKeyInfo, auction.itemKey)
    return type(info) == "table" and info.itemName or "?"
end

-- Ein Klick, eine Auktion (Blizzard verlangt einen Tastendruck je Abbruch).
function Undercut.CancelNext()
    local auction = Undercut.Next()
    if not auction then return false end
    if not pcall(C_AuctionHouse.CancelAuction, auction.auctionID) then return false end
    Undercut.results[auction.auctionID] = nil
    ns.Print(L.CANCELLED_MSG:format(AuctionName(auction)))
    Undercut.UpdateButton()
    return true
end

-- „Konkurrenz ansehen“: die Angebote zum Gegenstand der Auktion in Blizzards Ergebnisliste (Reiter Kaufen), über die
-- vorhandene Schnittstelle Search.Item (ein Klick des Spielers – ezCore hält Erfassungen dafür an). Rückgabe: true
-- und der Suchbegriff, oder false und der Grund ("none" ohne laufende Auktion, sonst der von Search.Item).
function Undercut.ShowRivals()
    local auction = Undercut.RivalAuction()
    if not auction then
        ns.Print(L.RIVALS_NONE)
        return false, "none"
    end
    local ok, why = ns.Search.Item(auction.itemLink or auction.itemKey.itemID)
    if not ok then
        local key = "RIVALS_FAIL_" .. tostring(why)
        ns.Print(L[key] ~= key and L[key] or L.RIVALS_FAIL)
    end
    return ok, why
end

function Undercut.UpdateRivals()
    if not rivalsButton then return end
    local frame = AuctionsFrame()
    local show = ns.Enabled("rivalsButton") and frame ~= nil and not (frame.IsDisplayingBids and frame:IsDisplayingBids())
        and not HistoryShown()
    rivalsButton:SetShown(show == true)
    if show then rivalsButton:SetEnabled(Undercut.RivalAuction() ~= nil) end
end

function Undercut.RivalsButton()
    return rivalsButton ~= nil and rivalsButton:IsVisible() and rivalsButton or nil
end

function Undercut.UpdateButton()
    Undercut.UpdateRivals()
    if not cancelButton then return end
    local frame = AuctionsFrame()
    local show = ns.Enabled("cancelButton") and frame ~= nil and not (frame.IsDisplayingBids and frame:IsDisplayingBids())
        and not HistoryShown()
    cancelButton:SetShown(show == true)
    if not show then return end
    local count = Undercut.Count()
    if Undercut.current or #Undercut.queue > 0 then
        local total, open = 0, #Undercut.queue + (Undercut.current and 1 or 0)
        for _ in pairs(Undercut.groups) do total = total + 1 end
        cancelButton:SetText(L.CHECKING:format(total - open, total))
    else
        cancelButton:SetText(L.CANCEL_UNDERCUT:format(count))
    end
    cancelButton:SetEnabled(Undercut.Next() ~= nil)
end

-- Laufende Auktionen: Anzahl und Wert; verkaufte (Geld kommt per Post) extra.
function Undercut.Sum()
    local count, value, sold = 0, 0, 0
    for _, auction in ipairs(Undercut.Owned()) do
        local commodity = IsCommodity(auction.itemKey)
        local price = auction.buyoutAmount or auction.bidAmount or 0
        local total = commodity and price * (auction.quantity or 1) or price
        if auction.status == SoldStatus() then
            sold = sold + total
        elseif auction.status == ActiveStatus() then
            count = count + 1
            value = value + total
        end
    end
    return count, value, sold
end

function Undercut.UpdateSum()
    if not sumText then return end
    local frame = AuctionsFrame()
    -- Bei „Gebote“ stehen dort Blizzards Gebot- und Sofortkauf-Felder.
    if not ns.Enabled("auctionSum") or (frame and frame.IsDisplayingBids and frame:IsDisplayingBids()) or HistoryShown() then
        return sumText:Hide()
    end
    local count, value, sold = Undercut.Sum()
    local text = L.SUM_TEXT:format(count, ns.Money(value))
    if sold > 0 then text = text .. L.SUM_SOLD:format(ns.Money(sold)) end
    sumText:SetText(text)
    sumText:Show()
end

local function MarkRow(_, data, overlay)
    local undercut = ns.Enabled("undercutCheck") and type(data) == "table" and data.auctionID ~= nil
        and Undercut.results[data.auctionID] == true
    overlay:SetWarning(undercut)
    local tip = undercut and L.UNDERCUT_ROW_TIP or nil
    local detail = undercut and Undercut.DetailText(data)
    if detail then tip = detail .. "\n" .. tip end
    overlay:SetTip(tip, 1, 0.3, 0.3)
end

-- Knopf „Unterbotene abbrechen“, solange zu sehen (Ziel des Rundgangs).
function Undercut.Button()
    return cancelButton ~= nil and cancelButton:IsVisible() and cancelButton or nil
end

---------------------------------------------------------------------------
-- AH-40: Taste „Nächste unterbotene abbrechen“ über ezCores fenstergebundenen Tasten-Dienst (Welle 15)
---------------------------------------------------------------------------
-- Die Taste klickt ezAuctions vorhandenen Knopf (globaler Name Undercut.BUTTON_NAME): ein Tastendruck, ein Klick, eine
-- Auktion. Gesetzt nur, solange Blizzards Auktionsfenster offen ist und außerhalb des Kampfes (ezCore löst sie bei
-- PLAYER_REGEN_DISABLED); ab Werk keine Taste, belegt auf der Einstellungsseite (Undercut.AskKey, mit ezCores Warnung
-- bei einer schon belegten Taste). Steht der Knopf nicht da (anderer Reiter, „Gebote“, „Verlauf“), tut die Taste
-- nichts. „Einstellen“ und „Überspringen“ kommen erst mit Tor T1 „geht“ für den Verkaufsbereich (ns.T1).
Undercut.KEY_ID = "ezAuction.cancelUndercut"
Undercut.BUTTON_NAME = "ezAuctionCancelUndercutButton"

function Undercut.Keys()
    local keys = Core.Keys
    if type(keys) ~= "table" or type(keys.AddWindowKey) ~= "function" then return nil end
    return keys
end

function Undercut.RegisterKey()
    local keys = Undercut.Keys()
    if not keys then return false end
    return keys.AddWindowKey(Undercut.KEY_ID, { frame = "AuctionHouseFrame", button = Undercut.BUTTON_NAME,
        text = L.KEY_CANCEL_UNDERCUT, owner = ADDON, addon = ns.BLIZZARD_ADDON }) == true
end

function Undercut.Key()
    local keys = Undercut.Keys()
    return keys and type(keys.WindowKey) == "function" and keys.WindowKey(Undercut.KEY_ID) or nil
end

-- Knopf auf der Einstellungsseite: Taste abfragen (ezCores Rückfrage samt Warnung bei Doppelbelegung).
function Undercut.AskKey()
    local keys = Undercut.Keys()
    if not (keys and type(keys.AskWindowKey) == "function") then return false end
    return keys.AskWindowKey(Undercut.KEY_ID) == true
end

-- Zeile für /eza status.
function Undercut.KeyLine()
    local key = Undercut.Key()
    return key and L.KEY_CANCEL_STATUS:format(key) or L.KEY_CANCEL_STATUS_NONE
end

-- Klick auf den Knopf – mit der Maus oder über die Taste. Nur, solange der Knopf zu sehen ist: eine Taste im Reiter
-- Verkaufen bricht nichts ab.
function Undercut.Click()
    if not (cancelButton and cancelButton:IsVisible()) then return false end
    return Undercut.CancelNext()
end

Undercut.RegisterKey()

local function Build()
    local frame = AuctionsFrame()
    if not frame then return end
    local blizzardCancel = frame.CancelAuctionButton
    cancelButton = CreateFrame("Button", Undercut.BUTTON_NAME, frame, "UIPanelButtonTemplate")
    cancelButton:SetSize(190, 22)
    if blizzardCancel then
        cancelButton:SetPoint("RIGHT", blizzardCancel, "LEFT", -6, 0)
    else
        cancelButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -170, -22)
    end
    cancelButton:SetMotionScriptsWhileDisabled(true)
    cancelButton:SetScript("OnClick", function() Undercut.Click() end)
    cancelButton:SetScript("OnEnter", function(self)
        local auction = Undercut.Next()
        local body
        if auction then
            local cost = Core.Call(C_AuctionHouse.GetCancelCost, auction.auctionID)
            body = L.CANCEL_UNDERCUT_TIP:format(AuctionName(auction), ns.Money(cost or 0))
        else
            body = L.CANCEL_NONE_TIP
        end
        local _, blocked = Undercut.Count()
        if blocked > 0 then body = body .. "\n" .. L.CANCEL_BLOCKED_TIP:format(blocked) end
        Core.ShowTip(self, L.CANCEL_UNDERCUT_TITLE, body)
    end)
    cancelButton:SetScript("OnLeave", GameTooltip_Hide)

    -- „Konkurrenz ansehen“ links neben „Unterbotene abbrechen“ (AH-25)
    rivalsButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    rivalsButton:SetSize(150, 22)
    rivalsButton:SetPoint("RIGHT", cancelButton, "LEFT", -6, 0)
    rivalsButton:SetText(L.RIVALS_BUTTON)
    rivalsButton:SetMotionScriptsWhileDisabled(true)
    rivalsButton:SetScript("OnClick", function() Undercut.ShowRivals() end)
    rivalsButton:SetScript("OnEnter", function(self)
        local auction = Undercut.RivalAuction()
        local body = auction and L.RIVALS_TIP:format(AuctionName(auction)) or L.RIVALS_NONE
        local detail = auction and Undercut.DetailText(auction)
        if detail then body = body .. "\n" .. detail end
        Core.ShowTip(self, L.RIVALS_BUTTON, body)
    end)
    rivalsButton:SetScript("OnLeave", GameTooltip_Hide)

    sumText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    local money = AuctionHouseFrame.MoneyFrameBorder
    if money then
        sumText:SetPoint("LEFT", money, "RIGHT", 10, 0)
    else
        sumText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 175, -18)
    end
    sumText:SetPoint("RIGHT", rivalsButton, "LEFT", -8, 0)
    sumText:SetJustifyH("LEFT")

    redecorate = ns.DecorateList(frame.AllAuctionsList, MarkRow)
    -- Blizzards Unteransicht wechselt (Alle, ein Gegenstand, Gebote): nur in „Alle“ prüfen.
    if frame.SetDisplayMode then
        hooksecurefunc(frame, "SetDisplayMode", function()
            if Undercut.CanCheck() then Undercut.Start() else Undercut.Stop() end
        end)
    end
    if frame.SetTab then hooksecurefunc(frame, "SetTab", function()
        Undercut.UpdateButton()
        Undercut.UpdateSum()
    end) end
    frame:HookScript("OnShow", function()
        Undercut.UpdateSum()
        if Undercut.CanCheck() then Undercut.Start() end
    end)
    frame:HookScript("OnHide", Undercut.Stop)
    Undercut.UpdateButton()
end

---------------------------------------------------------------------------
-- Schnittstelle Auctions (AH-25, Welle 14) – für ezPanels Baustein „Auktionen“ (Welle 15)
---------------------------------------------------------------------------
--[[
    ezCore.API("ezAuction").Auctions(charKey) → { running, undercut, value, sold, checked, seen, live } oder nil
      running   laufende Auktionen, value ihr Wert (Sofortkauf, sonst Gebot), sold schon verkauft (Geld in der Post)
      undercut  unterbotene (auch die mit Gebot); checked = so viele Gegenstände wurden geprüft – 0 heißt „nicht
                geprüft“ (geprüft wird nur im Reiter Auktionen, Übersicht „Alle“)
      seen      Zeitpunkt des Stands: bei offenem Auktionshaus jetzt (live = true), sonst der letzte Besuch
    Ohne charKey der angemeldete Charakter. Gemerkt beim Schließen des Auktionshauses und nach jeder Änderung der
    eigenen Auktionen in ezAuctionDB.ui.auctions[charKey]. Nie bekannt, wenn der Charakter das Haus noch nie öffnete.
    Blizzard fragt die eigenen Auktionen nur im Reiter Auktionen ab (AuctionHouseAuctionsFrameMixin, QueryOwnedAuctions;
    Zweig forever) – erst nach OWNED_AUCTIONS_UPDATED stimmt GetOwnedAuctions. Ein Besuch ohne diesen Reiter überschreibt
    darum nichts, und Auctions() nennt bis dahin den gemerkten Stand (live = false).
]]

Undercut.ownedLoaded = false    -- in diesem Besuch OWNED_AUCTIONS_UPDATED gesehen (beim Schließen zurück)

function Undercut.State()
    local count, value, sold = Undercut.Sum()
    local undercut, blocked = Undercut.Count()
    local checked = 0
    for _ in pairs(Undercut.checked) do checked = checked + 1 end
    return { running = count, undercut = undercut + blocked, value = value, sold = sold, checked = checked,
        seen = time(), live = true }
end

local function StateStore()
    local ui = ns.db and ns.db.ui
    if not ui then return nil end
    if type(ui.auctions) ~= "table" then ui.auctions = {} end
    return ui.auctions
end

-- Stand des angemeldeten Charakters merken (nur bei offenem Auktionshaus – sonst kennt der Client die Auktionen nicht;
-- closing: aus dem Schließen heraus, dann meldet Blizzards Fenster sich schon als verborgen).
function Undercut.Remember(closing)
    local store = StateStore()
    if not (store and ns.charKey and Undercut.ownedLoaded and (closing or ns.AuctionHouseShown())) then return nil end
    local state = Undercut.State()
    state.live = nil
    store[ns.charKey] = state
    Undercut.Notify()
    return state
end

-- Vergisst ezCore einen Twink (Core.ForgetChar, Nachricht CHAR_FORGOTTEN), geht sein gemerkter Auktionsstand mit
-- (ezAuctionDB.ui.auctions[key]; Gesamtreview 18.11.2026, T4-2). → true, wenn etwas gemerkt war.
function Undercut.Forget(key)
    local ui = ns.db and ns.db.ui
    if type(key) ~= "string" or key == ns.charKey or type(ui) ~= "table" or type(ui.auctions) ~= "table" then
        return false
    end
    if ui.auctions[key] == nil then return false end
    ui.auctions[key] = nil
    return true
end
Core.Listen("CHAR_FORGOTTEN", function(key) Undercut.Forget(key) end, ADDON)

function ns.API.Auctions(charKey)
    charKey = charKey or ns.charKey
    if charKey == ns.charKey and ns.AuctionHouseShown() and Undercut.ownedLoaded then return Undercut.State() end
    local store = StateStore()
    local saved = store and charKey and store[charKey]
    if type(saved) ~= "table" then return nil end
    local copy = {}
    for key, value in pairs(saved) do copy[key] = value end
    copy.live = false
    return copy
end

ns.OnAuctionHouse(Build)
ns.Listen("HISTORY_VIEW", function()
    Undercut.UpdateButton()
    Undercut.UpdateSum()
end)
ns.Listen("AH_HIDE", function()
    Undercut.Remember(true)
    Undercut.ownedLoaded = false
    Undercut.Stop()
    Undercut.checked = {}
end)
ns.On("OWNED_AUCTIONS_UPDATED", function()
    Undercut.ownedLoaded = true
    Undercut.Remember()
end)
ns.OnSettingChanged(function(key)
    if key == "undercutCheck" then
        if Undercut.CanCheck() then Undercut.Start() else Undercut.Stop() end
        Changed()
    elseif key == "cancelButton" or key == "rivalsButton" then
        Undercut.UpdateButton()
    elseif key == "auctionSum" then
        Undercut.UpdateSum()
    end
end)
