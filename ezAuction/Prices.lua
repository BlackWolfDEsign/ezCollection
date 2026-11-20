local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Preise aus dem Gedächtnis – das Erfassen selbst macht ezCore (ezCore.Prices: Komplett-Scan, Mitlernen bei
    jeder Suche, Speicher je Realm und Fraktion). ezAuction zeigt nur an und bietet den Knopf:
      - Knopf „Preise erfassen“ oben links im Auktionsfenster (Reiter Kaufen und Verkaufen): startet den
        Komplett-Scan, zeigt Fortschritt bzw. Restzeit (Blizzard erlaubt ihn alle 15 Minuten)
      - Tooltip-Zeile „Auktion: 1 g 20 s (vor 2 Std.)“ über die Tooltip-Pipeline, bei Stapeln auch × Menge;
        weicht, solange ein anderes Addon Auktionspreise im Tooltip zeigt (Auctionator, TradeSkillMaster;
        Scan.HoldBack) – der Schalter „Auch neben anderen Auktions-Addons zeigen“ zeigt sie trotzdem
      - Welle 13: Pfeil am Knopf mit dem Menü „Komplett“, „Meine Preise“ (Prices.Refresh über alles Beobachtete),
        „Fehlende“ und – wenn ezCore Prices.ScanBrowse anbietet – „Kategorie …“ (AH-16); „Heute: 82 %“ daneben
        (Prices.Coverage der Taschen-Gegenstände); „Beim Öffnen erfassen“ (AH-17, Scan.Auto)
    Marktwert und Schnäppchen in der Ergebnisliste: BuyTab.lua; Marktwert als Ersatz in der Preisregel: SellTab.lua.
]]

local Scan = {}
ns.Scan = Scan

local button, ticker

-- Text und Zustand des Knopfs: text, klickbar?
function Scan.Label()
    local prices = ns.Prices()
    if not prices then return L.SCAN_BUTTON, false end
    local running, done, total = prices.IsScanning()
    if running then
        if total and total > 0 then return L.SCAN_RUNNING:format(math.floor((done or 0) / total * 100)), false end
        return L.SCAN_STARTING, false
    end
    local wait = Core.Call(prices.ScanReadyIn) or 0
    if wait > 0 then return L.SCAN_WAIT:format(Core.Clock(wait)), false end
    return L.SCAN_BUTTON, true
end

function Scan.Update()
    if not button then return end
    local mode = ns.ModeName()
    local show = ns.Prices() ~= nil and ns.AuctionHouseShown() and (mode == "buy" or mode == "sell")
    button:SetShown(show == true)
    if Scan.arrow then Scan.arrow:SetShown(show == true) end
    if not show then
        Scan.UpdateCoverage()
        return
    end
    local text, enabled = Scan.Label()
    button:SetText(text)
    button:SetEnabled(enabled)
end

-- Rückgabe wie ezCore.Prices.Scan(): true, oder false und Grund.
function Scan.Start()
    local prices = ns.Prices()
    if not prices then return false, "unsupported" end
    local ok, reason = prices.Scan()
    if not ok then
        if reason == "wait" then
            ns.Print(L.SCAN_FAIL_wait:format(Core.Clock(Core.Call(prices.ScanReadyIn) or 0)))
        else
            ns.Print(L["SCAN_FAIL_" .. tostring(reason)] ~= "SCAN_FAIL_" .. tostring(reason)
                and L["SCAN_FAIL_" .. tostring(reason)] or L.SCAN_FAIL_unsupported)
        end
    end
    Scan.Update()
    return ok, reason
end

-- Tooltip des Knopfs: was er tut – und neben einem fremden Auktionshaus-Addon, wie sich beide vertragen
-- (Beside.lua; Frage 35 der Vollprüfung).
function Scan.TipBody()
    local line = ns.Beside.PartLine("scan")
    return line and (L.SCAN_TIP .. "\n\n" .. line) or L.SCAN_TIP
end

---------------------------------------------------------------------------
-- Menü am Knopf (AH-16): Komplett, Meine Preise, Fehlende, Kategorie …; Abdeckung der Taschen-Gegenstände
---------------------------------------------------------------------------

-- Taschen-Gegenstände, die ins Auktionshaus dürfen (nicht gebunden): Links bzw. itemIDs für Prices.Coverage. Die Liste
-- baut ezCore (Prices.BagItems, Welle 23b – dieselbe speist dessen Anbieter „ezCore.bags“); hier nur die Taschenart
-- „sell“ (Blizzards Taschen für den Verkauf). Der Name bleibt für Scan.Coverage und die Prüfungen.
function Scan.BagItems()
    local prices = ns.Prices()
    if not (prices and type(prices.BagItems) == "function") then return {} end
    local list = Core.Call(prices.BagItems, "sell")
    return type(list) == "table" and list or {}
end

-- Abdeckung: Anteil (0–1), mit Preis von heute, gesamt – oder nil, solange ezCore Prices.Coverage nicht anbietet.
function Scan.Coverage()
    local prices = ns.Prices()
    if not (prices and type(prices.Coverage) == "function") then return nil end
    local share, fresh, total = Core.Call(prices.Coverage, Scan.BagItems())
    if not Core.Num(share) then return nil end
    return share, Core.Num(fresh) or 0, Core.Num(total) or 0
end

-- Zeile „Preise von heute für 82 % deiner Taschen-Gegenstände“ (nil ohne Gegenstände oder ohne ezCores Rechnung).
function Scan.CoverageLine()
    local share, fresh, total = Scan.Coverage()
    if not share or total == 0 then return nil end
    return L.SCAN_COVERAGE:format(Core.Percent(Core.Round(share * 100)), fresh, total)
end

-- Beobachtetes ohne Preis von heute (Prices.WatchList: Taschen, eigene Auktionen, Einkaufslisten, Material …).
function Scan.Missing()
    local prices = ns.Prices()
    if not (prices and type(prices.WatchList) == "function" and type(prices.Day) == "function") then return {} end
    local today, out = Core.Call(prices.Day), {}
    for _, e in ipairs(Core.Call(prices.WatchList) or {}) do
        local info = type(e) == "table" and ns.PriceInfo(e.item)
        local seen = info and Core.Num(info.seen)
        if not (seen and Core.Call(prices.Day, seen) == today) then out[#out + 1] = e.item end
    end
    return out
end

-- Gezielte Auffrischung über ezCore (Prices.Refresh: Sammelabfrage, Rückfall je Gegenstand). items nil = alles
-- Beobachtete; reason "click" = nach einem Klick (Rang „modul“), sonst Rang „erfassung“. Rückgabe wie Prices.Refresh.
function Scan.Refresh(items, reason)
    local prices = ns.Prices()
    if not (prices and type(prices.Refresh) == "function") then return false, "unsupported" end
    local ok, a, b = Core.Call(prices.Refresh, items, reason)
    return ok == true, a, b
end

local function RefreshClick(items, emptyText)
    if items and #items == 0 then
        ns.Print(emptyText)
        return false
    end
    local ok, count = Scan.Refresh(items, "click")
    if ok then
        ns.Print(L.SCAN_REFRESH_STARTED:format(Core.Num(count) or 0))
    elseif count == "empty" then
        ns.Print(emptyText)
    else
        ns.Print(L["SCAN_FAIL_" .. tostring(count)] ~= "SCAN_FAIL_" .. tostring(count) and L["SCAN_FAIL_" .. tostring(count)]
            or L.SCAN_FAIL_unsupported)
    end
    return ok
end

-- Bietet ezCore den Durchlauf je Kategorie an (Prices.ScanBrowse, AH-02 – kommt im ezCore-Paket derselben Welle)?
function Scan.CanBrowse()
    local prices = ns.Prices()
    return prices ~= nil and type(prices.ScanBrowse) == "function"
end

-- Ist der Komplett-Scan gerade gesperrt oder hat er zuletzt nicht geantwortet? Dann steht „Kategorie …“ vorn.
function Scan.FullBlocked()
    local prices = ns.Prices()
    if not prices then return true end
    if Scan.lastTimeout then return true, "timeout" end
    local wait = Core.Num(Core.Call(prices.ScanReadyIn)) or 0
    if wait > 0 then return true, "wait" end
    return false
end

-- Blizzards oberste Kategorien (AuctionCategories, nur gelesen): { { index, name } … }, ohne WoW-Marke.
function Scan.Categories()
    local out = {}
    for index, node in ipairs(type(rawget(_G, "AuctionCategories")) == "table" and AuctionCategories or {}) do
        local token = type(node) == "table" and type(node.HasFlag) == "function" and Core.Call(node.HasFlag, node, "WOW_TOKEN_FLAG")
        if type(node) == "table" and type(node.name) == "string" and not token then out[#out + 1] = { index, node.name } end
    end
    return out
end

-- Durchlauf über eine Kategorie (über ezCore). Rückgabe wie Prices.ScanBrowse, false und "unsupported" ohne ihn.
function Scan.Browse(index)
    local prices = ns.Prices()
    if not Scan.CanBrowse() then return false, "unsupported" end
    local ok, a, b = Core.Call(prices.ScanBrowse, { index })
    if ok then ns.Print(L.SCAN_BROWSE_STARTED) else ns.Print(L.SCAN_BROWSE_FAIL:format(tostring(a or "?"))) end
    return ok == true, a, b
end

-- Einträge des Menüs (auch für Prüfungen): { key, text, fn, highlight } bzw. für „Kategorie …“ dazu sub = { … }.
function Scan.MenuEntries()
    local _, enabled = Scan.Label()
    local entries = {
        { key = "full", text = enabled and L.SCAN_MENU_FULL or (L.SCAN_MENU_FULL .. " (" .. Scan.Label() .. ")"),
            fn = function() Scan.Start() end },
        { key = "mine", text = L.SCAN_MENU_MINE, fn = function() return RefreshClick(nil, L.SCAN_MINE_EMPTY) end },
        { key = "missing", text = L.SCAN_MENU_MISSING, fn = function() return RefreshClick(Scan.Missing(), L.SCAN_MISSING_NONE) end },
    }
    if Scan.CanBrowse() then
        local blocked = Scan.FullBlocked()
        local sub = {}
        for _, cat in ipairs(Scan.Categories()) do
            local index = cat[1]
            sub[#sub + 1] = { key = "category" .. index, text = cat[2], fn = function() return Scan.Browse(index) end }
        end
        entries[#entries + 1] = { key = "category", highlight = blocked == true, sub = sub,
            text = blocked and (Core.Style.ColorText("good", L.SCAN_MENU_CATEGORY) .. " " .. L.SCAN_MENU_CATEGORY_HINT) or L.SCAN_MENU_CATEGORY }
    end
    return entries
end

function Scan.Menu(owner)
    local entries = Scan.MenuEntries()
    local Menu = Core.Menu
    local opened = Menu.Open(owner, function(root)
        Menu.Title(root, L.SCAN_TITLE)
        for _, entry in ipairs(entries) do
            if entry.sub then
                local sub = root:CreateButton(entry.text)
                for _, child in ipairs(entry.sub) do Menu.Button(sub, child.text, child.fn) end
            else
                Menu.Button(root, entry.text, entry.fn)
            end
        end
        local line = Scan.CoverageLine()
        if line then
            Menu.Divider(root)
            Menu.Title(root, line)
        end
    end)
    if not opened then entries[1].fn() end
    return opened
end

-- Tooltip am Knopf: was er tut, Abdeckung, Sperrzeit und Herkunft der Preise.
function Scan.ButtonTip()
    local parts = { Scan.TipBody() }
    local line = Scan.CoverageLine()
    if line then parts[#parts + 1] = line end
    local prices = ns.Prices()
    local wait = prices and Core.Num(Core.Call(prices.ScanReadyIn)) or 0
    parts[#parts + 1] = wait > 0 and L.SCAN_TIP_WAIT:format(Core.Clock(wait)) or L.SCAN_TIP_READY
    parts[#parts + 1] = L.SCAN_TIP_MENU
    return table.concat(parts, "\n\n")
end

local arrowButton, coverageText

function Scan.ArrowButton() return arrowButton ~= nil and arrowButton:IsVisible() and arrowButton or nil end
function Scan.CoverageText() return coverageText end

-- „Heute: 82 %“ rechts neben dem Zahnrad unter dem Knopf (der ganze Satz im Tooltip); leer ohne Taschen-Gegenstände.
-- Passt der Satz nicht in die feste Breite (andere Schrift, Rundung bei kleiner UI-Skalierung), steht nur der Wert da:
-- Blizzard kürzte sonst am Ende, mitten in der Zahl („Heute: 10…“ liest sich als falscher Wert; Review vom 17.11.2026).
function Scan.UpdateCoverage()
    if not coverageText then return end
    local share, _, total = nil, nil, 0
    if ns.Enabled("scanCoverage") and button and button:IsShown() then share, _, total = Scan.Coverage() end
    if share and total > 0 then
        local value = Core.Percent(Core.Round(share * 100))
        coverageText:SetText(L.SCAN_COVERAGE_SHORT:format(value))
        if ns.Layout.TextWidth(coverageText) > ns.Layout.CoverageWidth() then coverageText:SetText(value) end
        coverageText:Show()
    else
        coverageText:Hide()
    end
end

local function Build()
    local Layout, S = ns.Layout, ns.Layout.SCAN
    button = CreateFrame("Button", "ezAuctionScanButton", AuctionHouseFrame, "UIPanelButtonTemplate")
    button:SetSize(S.w, S.h)
    -- Rechts neben dem Porträt, links von Blizzards Suchleiste (Favoriten-Knopf ab x = 170) bzw. über dem
    -- Verkaufsbereich; Maße in ns.Layout (Core.lua), geprüft in Tests/lage.lua
    button:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPLEFT", S.x, S.y)
    button:SetMotionScriptsWhileDisabled(true)
    button:SetScript("OnClick", function() Scan.Start() end)
    button:SetScript("OnEnter", function(self) Core.ShowTip(self, L.SCAN_TITLE, Scan.ButtonTip()) end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    button:Hide()
    -- Pfeil mit dem Menü (AH-16): ein Knopf statt drei; das Zahnrad (Options.lua) rückt rechts daneben. Beide stehen
    -- in einer zweiten Zeile unter dem Knopf: rechts vom Knopf beginnt Blizzards Favoriten-Knopf (Spielbefund
    -- 16.11.2026: Pfeil und Zahnrad lagen darüber, „Heute: …“ über dem Suchfeld)
    -- Pfeil aus ezCore (Core.Toolbar.ArrowButton, T18-13), kleiner Knopf (Design-System 2.3; bis Welle 22 18); der Name
    -- bleibt als globaler Verweis für das Zahnrad daneben (Options.lua) und die Lage-Prüfungen
    arrowButton = Core.Toolbar.ArrowButton(AuctionHouseFrame, function(self) Scan.Menu(self) end, L.SCAN_MENU_TITLE,
        L.SCAN_MENU_TIP, { size = Layout.SMALL })
    _G.ezAuctionScanMenuButton = arrowButton
    arrowButton:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -Layout.ROW_GAP)
    arrowButton:Hide()
    Scan.arrow = arrowButton
    coverageText = AuctionHouseFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    coverageText:SetPoint("LEFT", arrowButton, "RIGHT", Layout.CoverageOffset(), 0)
    -- feste Breite bis kurz vor Blizzards Favoriten-Knopf (Platz für „Heute: 100 %“), damit nichts in die Suchleiste
    -- ragt; ist der Satz breiter, zeigt Scan.UpdateCoverage nur den Wert
    coverageText:SetWidth(Layout.CoverageWidth())
    coverageText:SetJustifyH("LEFT")
    coverageText:SetWordWrap(false)
    coverageText:Hide()
end

-- Preisverlauf aus dem Preis-Wissen (ezCore.Prices.History: ein Punkt je Tag): tiefster und höchster Tiefstpreis
-- und die Zahl der Tage mit Daten; nil, solange es weniger als zwei Tage gibt (Vollprüfung V-162). Gezählt werden
-- nur die letzten Prices.HISTORY_DAYS (14) Kalendertage – für beobachtete und besessene Gegenstände hält ezCore
-- seit Welle 7 bis zu 30 Tage (Fund 6). Die übrigen Kennzahlen (Median, Tage gesehen) rechnet Prices.Stats.
function Scan.Trend(item)
    local prices = ns.Prices()
    if not (prices and item and type(prices.History) == "function") then return nil end
    local points = Core.Call(prices.History, item, Core.Num(prices.HISTORY_DAYS) or 14)
    if type(points) ~= "table" then return nil end
    local low, high, days = nil, nil, 0
    for _, point in ipairs(points) do
        local price = type(point) == "table" and (Core.Num(point.min) or Core.Num(point.market))
        if price and price > 0 then
            days = days + 1
            if not low or price < low then low = price end
            if not high or price > high then high = price end
        end
    end
    if days < 2 then return nil end
    return low, high, days
end

-- Knopf „Preise erfassen“, solange zu sehen (Ziel des Rundgangs).
function Scan.Button()
    return button ~= nil and button:IsVisible() and button or nil
end

---------------------------------------------------------------------------
-- Tooltip-Zeile
---------------------------------------------------------------------------

-- Läuft ein fremdes Addon, das Auktionspreise im Tooltip zeigt (Auctionator, TradeSkillMaster), gibt es keine
-- zweite Zeile – außer der Spieler will sie mit dem Schalter „Auch neben anderen Auktions-Addons zeigen“ trotzdem.
-- Gefragt wird nur „läuft es?“ (Core.WhoHandles, Core.OtherAddOn): ob das fremde Addon seine Tooltip-Preise gerade
-- zeigt, steht in dessen internen Einstellungen, und die liest ezAuction nicht (Entscheidung „Nur öffentliche API“,
-- 14.11.2026).
-- ns.OtherFor (Core.WhoHandles) deckt weitere Addons ab, die ezCore für „auctionTooltip“ kennt. Rückgabe: Name des Addons.
function Scan.HoldBack()
    if ns.Enabled("tooltipBeside") then return nil end
    -- Seit Welle 5 führt ezCore Auctionator unter „auctionTooltip“, ohne dessen Einstellungen zu lesen: die eine Frage
    -- über ns.OtherFor genügt und zählt das Weichen mit (Core.WhoHandles). Bis Welle 23 fragte Beside.Running zuerst –
    -- neben Auctionator zählte ezCore die Tooltip-Zeile darum nicht mit.
    return (ns.OtherFor("auctionTooltip"))
end

-- Woher ein Preis aus dem Preis-Wissen stammt (Regel „Datenquellen“ des Nutzers, 13.11.2026: jede Angabe nennt
-- ihre Quelle): selbst erfasst – Komplett-Scan, Übersicht oder Einzelsuche – und wann. Den Wortlaut liefert ezCore
-- (Prices.SourceText: „laut deinen Erfassungen (Komplett-Scan, vor 2 Std.)“); Auctionator ist keine Quelle
-- (AUC-01, Entscheidung vom 14.11.2026). Ohne Kennzeichen der Quelle der frühere Satz. nil ohne Preis.
function Scan.SourceText(info)
    if type(info) ~= "table" then return nil end
    local prices = ns.Prices()
    local text = prices and info.source and type(prices.SourceText) == "function" and Core.Call(prices.SourceText, info)
    if type(text) == "string" and text ~= "" then return L.PRICE_SOURCE_OF:format(text) end
    if info.seen then return L.PRICE_SOURCE_SEEN:format(Core.Ago(info.seen)) end
    return L.PRICE_SOURCE
end

-- Menge des gezeigten Stapels (Taschenplatz), nil wenn unbekannt.
local function StackCount(data)
    local guid = type(data) == "table" and data.guid
    if not guid or Core.IsSecret(guid) or not (C_Item and C_Item.GetItemLocation and C_Item.GetStackCount) then return nil end
    local location = Core.Call(C_Item.GetItemLocation, guid)
    if not (location and Core.Call(location.IsValid, location)) then return nil end
    local count = Core.Call(C_Item.GetStackCount, location)
    if Core.IsSecret(count) then return nil end
    return type(count) == "number" and count or nil
end

-- Größter Stapel eines Gegenstands; nil unbekannt. Gelesen über ezCores Core.MaxStack (Blizzards
-- C_Item.GetItemMaxStackSizeByID, sonst GetItemInfo; Welle 23a) – nur was der Client nennt zählt, kein Rückfall auf 1.
function Scan.MaxStack(itemID)
    itemID = Core.Num(itemID)
    if not itemID then return nil end
    local size, known = Core.MaxStack(itemID)
    return known == true and size or nil
end

local function ShiftDown()
    return type(IsShiftKeyDown) == "function" and IsShiftKeyDown() == true
end

-- Zeile „Auktion“, bei Taschenstapeln „Auktion (20 Stück)“. Mit gehaltener Umschalt-Taste dazu der Preis eines
-- vollen Stapels – auch außerhalb der Tasche (AH-11; seit der Einstellungs-Prüfung vom 19.11.2026 ohne Schalter, es
-- wirkt nur, solange man die Taste hält); ohne Umschalt-Taste die graue
-- Hinweiszeile „Umschalt: Stapelpreis“ (Leitlinie 3: die Funktion ist sichtbar; Schalter tooltipStackHint).
function Scan.TooltipLines(tooltip, itemID, data)
    if not ns.Enabled("tooltipPrice") or Scan.HoldBack() then return end
    local info = ns.PriceInfo(itemID)
    local price = info and (info.market or info.min)
    if not price or price <= 0 then return end
    local right = ns.Money(price)
    -- Quelle grau in Klammern hinter dem Wert (Design-System 2.5 und 2.7: Quellen in ezCores Grau; bis Welle 22 808080)
    if info.seen then right = right .. " " .. Core.Grey("(" .. L.TIP_SEEN:format(Core.Ago(info.seen)) .. ")") end
    -- Abstand (Spielbefund 18.11.2026 „auch hier fehlender abstand“): ezCores einer Trenner (Core.Tooltip.Gap), Gruppe
    -- wie ezCores Zeile „Im Auktionshaus mehr wert“ (Core.Prices.TOOLTIP_GROUP) – die schließt ohne Leerzeile an
    if Core.Tooltip and Core.Tooltip.Gap then
        Core.Tooltip.Gap(tooltip, Core.Prices and Core.Prices.TOOLTIP_GROUP or "price")
    end
    Core.TipDoubleLine(tooltip, L.TIP_AUCTION, right, "normal", "highlight")
    local count = StackCount(data)
    if count and count > 1 then
        Core.TipDoubleLine(tooltip, L.TIP_AUCTION_STACK:format(count), ns.Money(price * count), "normal", "highlight")
    end
    local full = Scan.MaxStack(itemID)
    if not full or full <= 1 or full == count then return end
    if ShiftDown() then
        Core.TipDoubleLine(tooltip, L.TIP_AUCTION_FULL_STACK:format(full), ns.Money(price * full), "normal", "highlight")
    elseif ns.Enabled("tooltipStackHint") and type(tooltip.AddLine) == "function" then
        Core.TipLine(tooltip, L.TIP_STACK_HINT, "hint")
    end
end

-- Zeigt die Tooltip-Zeile gerade einen Preis zu diesem Gegenstand? (Tooltip.ClaimLine „price“: dann lässt ein
-- anderes Modul, z. B. ezCraft, seine eigene Preiszeile weg – eine Aussage je Zeile, FP-06.)
function Scan.ShowsPrice(itemID)
    if not ns.Enabled("tooltipPrice") or Scan.HoldBack() then return false end
    local info = ns.PriceInfo(itemID)
    local price = info and (info.market or info.min)
    return price ~= nil and price > 0
end

if Core.Tooltip and Core.Tooltip.AddItemSection then
    Core.Tooltip.AddItemSection("ezAuction.price", 40, Scan.TooltipLines, ADDON)
end
if Core.Tooltip and type(Core.Tooltip.ClaimLine) == "function" then
    Core.Tooltip.ClaimLine("price", ADDON, function(itemID) return Scan.ShowsPrice(itemID) end)
end

---------------------------------------------------------------------------

ns.OnAuctionHouse(Build)
ns.Listen("AH_MODE", Scan.Update)
ns.Listen("AH_SHOW", function()
    Scan.Update()
    Scan.UpdateCoverage()
    if ticker then ticker:Cancel() end
    -- Jede Sekunde: Restzeit am Knopf – und nachsehen, ob ein fremdes Addon seine Ansicht auf einem Weg gezeigt
    -- hat, den keiner der Zuhörer in Core.lua bemerkt (ns.CheckMode meldet dann AH_MODE "other").
    ticker = C_Timer.NewTicker(1, function()
        ns.CheckMode()
        Scan.Update()
    end)
end)
ns.Listen("AH_HIDE", function()
    if ticker then ticker:Cancel() end
    ticker = nil
end)
Core.Listen("PRICES_SCAN_PROGRESS", function() Scan.Update() end, ADDON)
-- Meldung zum Ende eines Komplett-Scans (Grund aus ezCore, Welle 5): Blizzard hat nicht geliefert ("timeout"), ein
-- anderes Addon hat erfasst und ezCore hat mitgelernt ("other"), sonst die Zahl der Gegenstände.
function Scan.DoneText(count, reason)
    if reason == "timeout" then
        -- die Wartezeit hat ihre eine Stelle in ezCore (Prices.SCAN_TIMEOUT)
        local prices = ns.Prices()
        return L.SCAN_TIMEOUT:format(prices and Core.Num(prices.SCAN_TIMEOUT) or 30)
    end
    if reason == "other" then return L.SCAN_DONE_OTHER:format(count or 0) end
    return L.SCAN_DONE:format(count or 0)
end

Core.Listen("PRICES_SCAN_DONE", function(count, reason)
    -- hat der Komplett-Scan nicht geantwortet, steht „Kategorie …“ im Menü vorn (AH-16)
    Scan.lastTimeout = reason == "timeout" or nil
    ns.Print(Scan.DoneText(count, reason))
    Scan.Update()
    Scan.UpdateCoverage()
end, ADDON)
-- Neue Preise: Markierungen und Taschenliste auffrischen (gesammelt).
Core.Listen("PRICES_CHANGED", ns.Throttle(function() ns.Fire("PRICES_UPDATED") end, 0.3), ADDON)

-- Abdeckung am Knopf neu rechnen, wenn sich Preise oder Taschen ändern (gesammelt).
local coverageSoon = ns.Throttle(function() Scan.UpdateCoverage() end, 0.5)
ns.Listen("PRICES_UPDATED", coverageSoon)
ns.On("BAG_UPDATE_DELAYED", coverageSoon)
ns.Listen("AH_MODE", coverageSoon)
ns.OnSettingChanged(function(key) if key == "scanCoverage" then Scan.UpdateCoverage() end end)

---------------------------------------------------------------------------
-- Beobachtetes für „Meine Preise“ (AH-16): ezAuction meldet die Gegenstände seiner Einkaufslisten bei ezCore an
-- (Prices.AddWatchProvider). Der Spiegel der Favoriten (AH-23) kommt in Welle 14 dazu.
---------------------------------------------------------------------------

function Scan.WatchedListItems()
    local out, seen = {}, {}
    for _, list in ipairs(ns.db and ns.db.lists or {}) do
        for _, entry in ipairs(type(list) == "table" and type(list.items) == "table" and list.items or {}) do
            local id = type(entry) == "table" and Core.Num(entry.itemID)
            if id and not seen[id] then
                seen[id] = true
                out[#out + 1] = id
            end
        end
    end
    return out
end

do
    local prices = ns.Prices()
    if prices and type(prices.AddWatchProvider) == "function" then
        prices.AddWatchProvider("ezAuction.lists", Scan.WatchedListItems)
    end
end

---------------------------------------------------------------------------
-- Beim Öffnen erfassen (AH-17): Schalter scanOnOpen (ab Werk aus), Mindestabstand scanOnOpenHours
---------------------------------------------------------------------------
--[[
    Beim Öffnen fragt Blizzard selbst die Favoriten ab, wenn es welche gibt (AuctionHouseFrameMixin:OnShow,
    C_AuctionHouse.HasFavorites, Zweig forever). ezAuction wartet deren Antwort ab (höchstens Auto.MAX_WAIT Sekunden),
    sonst Auto.WAIT Sekunden, und erfasst dann: den Komplett-Scan, wenn er erlaubt ist, sonst „Meine Preise“ (Rang
    „erfassung“ – danach kommt die vorige Ansicht wieder, AH-37). Läuft ein Addon mit dem Rücksicht-Schlüssel
    auctionScan (gemeinsame kontoweite Sperrzeit), erfasst ezAuction nicht und sagt, welches. Der Zeitpunkt der letzten
    Erfassung beim Öffnen steht je Auktionshaus in ezAuctionDB.ui.autoScan.
]]
local Auto = {}
Scan.Auto = Auto
Auto.WAIT = 3
Auto.MAX_WAIT = 10

local function AutoStore()
    local ui = ns.db and ns.db.ui
    if not ui then return {} end
    if type(ui.autoScan) ~= "table" then ui.autoScan = {} end
    return ui.autoScan
end

function Auto.Last()
    return Core.Num(AutoStore()[ns.PostKey()])
end

-- Steht eine Erfassung an? Rückgabe: true, oder false und Grund ("off", "other" mit Name, "recent" mit Restsekunden).
function Auto.Due(now)
    if not ns.Enabled("scanOnOpen") then return false, "off" end
    local prices = ns.Prices()
    if not prices then return false, "unsupported" end
    local other = type(prices.ScanYields) == "function" and Core.Call(prices.ScanYields)
    if other then return false, "other", other end
    local last, hours = Auto.Last(), Core.Num(ns.S.scanOnOpenHours) or 6
    now = now or time()
    if last and now >= last and now - last < hours * 3600 then return false, "recent", hours * 3600 - (now - last) end
    return true
end

function Auto.OnShow()
    Auto.pending = nil
    local due, why, other = Auto.Due(time())
    if not due then
        if why == "other" then ns.Print(L.SCAN_AUTO_OTHER:format(tostring(other))) end
        return false, why
    end
    local favorites = C_AuctionHouse and C_AuctionHouse.HasFavorites and Core.Call(C_AuctionHouse.HasFavorites) == true
    local p = { favorites = favorites, answered = false }
    Auto.pending = p
    C_Timer.After(Auto.WAIT, function() Auto.Check(p, false) end)
    C_Timer.After(Auto.MAX_WAIT, function() Auto.Check(p, true) end)
    return true
end

-- Blizzards Favoritensuche ist beantwortet (die erste Antwort der Übersicht nach dem Öffnen).
function Auto.OnBrowseAnswer()
    local p = Auto.pending
    if p and p.favorites and not p.answered then
        p.answered = true
        C_Timer.After(0.2, function() Auto.Check(p, false) end)
    end
end

function Auto.Check(p, final)
    if Auto.pending ~= p or p.done then return false end
    if not ns.AuctionHouseShown() then
        Auto.pending = nil
        return false
    end
    if p.favorites and not p.answered and not final then return false end
    p.done, Auto.pending = true, nil
    return Auto.Run()
end

-- Erfassen: Komplett-Scan, wenn erlaubt, sonst „Meine Preise“. Rückgabe: "scan" | "refresh" | nil.
function Auto.Run()
    local prices = ns.Prices()
    if not prices then return nil end
    local how
    local ok, reason = Core.Call(prices.Scan, { auto = true })
    if ok then
        how = "scan"
    elseif reason == "other" then
        ns.Print(L.SCAN_AUTO_OTHER:format(tostring(Core.Call(prices.ScanYields) or "?")))
        return nil
    elseif Scan.Refresh(nil, nil) then
        how = "refresh"
    end
    if how then
        AutoStore()[ns.PostKey()] = time()
        ns.Print(L["SCAN_AUTO_" .. how])
    end
    Scan.Update()
    return how
end

ns.Listen("AH_SHOW", function() ns.Try("ScanOnOpen", Auto.OnShow) end)
ns.Listen("AH_HIDE", function() Auto.pending = nil end)
ns.On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function() Auto.OnBrowseAnswer() end)
