local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Seitenteil „Markt“ am Auktionsfenster (AUC-02, VP-69, AUC-03, VP-70, AUC-04, VP-72; Fragen 36 und 39 der
    Vollprüfung – Empfehlung umgesetzt, Antwort offen). Gebaut mit ezCores Baustein Core.NewSidePanel: ein Kind von
    Blizzards AuctionHouseFrame mit sichtbarem Pfeil-Knopf am Rand, Zustand gemerkt in ezAuctionDB.ui.marketOpen,
    Schalter marketPanel. Kein eigenes Fenster, kein Eintrag in FENSTER (tools/lint.lua).
    Inhalt für den gewählten Gegenstand – in „Kaufen“ die angeklickte Ergebniszeile, in „Verkaufen“ der Gegenstand im
    Verkaufsbereich (auch aus der Taschenliste):
      - Graph (Core.NewGraph): Linie der Tages-Tiefstpreise, blasses Band bis zum Höchst, Mengen-Balken am Fuß,
        Hilfslinie Median, Händlerpreis gestrichelt; Tage ohne Erfassung bleiben Lücke; Tooltip je Tag mit Quelle;
        Fußzeile „deine Erfassungen, 9 Tage“. Wenige Punkte oder Abwandlungen: ein Hinweis statt des Graphs.
        Rechts unter dem Graph der Knopf „Wochen“ / „Tage“ (V1, Welle 23; immer, seit der Einstellungs-Prüfung vom
        19.11.2026 ohne eigenen Schalter): der Langzeit-Verlauf
        in Kalenderwochen aus ezCores Wochenpunkten, gemerkt in ezAuctionDB.ui.marketWeeks.
      - Verfügbarkeit: „Gesehen an 9 von 12 erfassten Tagen“, übliche Menge (Market.Availability)
      - darunter Wochentag und Tageszeit (Entwurf 2b/2c, Frage 38) und „Entzaubern ≈ …“ (AUC-19, Schalter
        salvageCompare), Panel.MoreText
      - im Reiter Verkaufen darunter „Post: 2 Verkäufe, 3 Rückläufer“ (AH-28) und die Verkaufsempfehlung (AH-29,
        History.Advice), Panel.SellText – seit Welle 15
      - Hinweis gegen den Median mit Begründung und Quelle (Market.Judge, Market.SellAdvice; Schalter marketHint)
      - im Reiter Verkaufen darunter die Taschenliste als zweiter Abschnitt (SellTab.lua, Sell.PlacePanel)
      - oben rechts auf der Höhe der Überschrift (links angedockt gegenüber dem Pfeil, rechts angedockt links neben
        ihm) der Knopf „Als Text kopieren“ (V5, Welle 24): Tage, Wochen und eigene Auktionen des Gegenstands als
        Tabelle in ezCores Kopierfeld (Market.CopyRows, Core.CopyAsText); Namen von Käufern und Verkäufern nur mit dem
        Häkchen im Kopierfeld (Frage E6). Ohne ezCores Kopierfeld kein Knopf.
    Steht nur in Blizzards Reitern Kaufen und Verkaufen; in der Ansicht eines fremden Addons (ns.ModeName "other")
    verschwinden Feld und Pfeil. Nur Anzeige – nichts wird gekauft, eingestellt oder eingetragen.
]]

local Panel = {}
ns.MarketPanel = Panel

Panel.WIDTH = 260
Panel.GRAPH_W, Panel.GRAPH_H = 224, 100
Panel.BAG_TOP = 284     -- im Reiter Verkaufen beginnt hier die Taschenliste (zweiter Abschnitt), mindestens
Panel.TEXT_TOP = 54 + Panel.GRAPH_H + 4     -- Beginn der Fußzeile unter dem Graph (Build)
Panel.TEXT_GAPS = 6 + 6 + 6 + 8             -- Abstände Fußzeile/Zeilen/Weiteres/Hinweis und Rand vor der Taschenliste

local panel, graph, panelOpts
local current = {}      -- [Ansicht "buy" | "sell"] = { itemID, itemKey, name, quality, price, offered }

-- Gibt es ezCores Bausteine (Seitenteil und Linien) und Blizzards Auktionsfenster?
function Panel.Available()
    return type(Core.NewSidePanel) == "function" and type(Core.NewGraph) == "function" and AuctionHouseFrame ~= nil
end

-- Soll das Seitenteil (samt Pfeil) jetzt dastehen? Nur in Blizzards Reitern Kaufen und Verkaufen.
function Panel.Wanted()
    if not (ns.ahReady and ns.Enabled("marketPanel") and Panel.Available() and ns.AuctionHouseShown()) then return false end
    local mode = ns.ModeName()
    return mode == "buy" or mode == "sell"
end

-- Das offene Seitenteil im Reiter Verkaufen: dort sitzt die Taschenliste als zweiter Abschnitt. Sonst nil.
function Panel.BagHost()
    if panel and panel:IsOpen() and Panel.Wanted() and ns.ModeName() == "sell" then return panel end
    return nil
end

-- Beginn der Taschenliste im Reiter Verkaufen: mindestens BAG_TOP; bei langem Text (Bewertung, „guter Zeitpunkt“,
-- Quelle, Notiz zum Überlappen) unter dessen letzter Zeile – sonst läge er über Titel und Filter der Liste.
-- Ohne messbare Texthöhe bleibt es bei BAG_TOP.
function Panel.BagTop()
    if not panel then return Panel.BAG_TOP end
    local used = Panel.TEXT_TOP + Panel.TEXT_GAPS
    for _, fs in ipairs({ panel.footer, panel.lines, panel.more, panel.hint }) do
        local height = fs.GetStringHeight and fs:GetStringHeight()
        if type(height) ~= "number" then return Panel.BAG_TOP end
        used = used + height
    end
    return math.max(Panel.BAG_TOP, math.ceil(used))
end

-- Zugeklappt dockt im Reiter Verkaufen die Taschenliste auf derselben Seite an Blizzards Fenster wie das Feld; der
-- Pfeil rückt dann an ihren äußeren Rand, sonst läge er auf ihrem Rahmen und Filterfeld. Gesetzt über ezCores
-- teil:SetArrowOffset (x = Abstand vom Fensterrand; platziert selbst neu, nur bei Änderung – Welle 23b, kam im selben
-- Zweig wie Prices.Weekday aus needs); vorher schrieb ezAuction panelOpts.arrow.x selbst.
function Panel.PlaceArrow()
    if not (panel and panelOpts) then return end
    local x = 0
    if not panel:IsOpen() and ns.Sell.Docked() and panel.side == ns.Sell.Side() then x = ns.Sell.PanelWidth() end
    panel:SetArrowOffset(x)
end

function Panel.Frame() return panel end
function Panel.Graph() return graph end
function Panel.Current() return current[ns.ModeName() or ""] end

-- Pfeil-Knopf, solange zu sehen (Ziel des Rundgangs).
function Panel.Arrow()
    local arrow = panel and panel.arrow
    return arrow ~= nil and arrow:IsVisible() and arrow or nil
end

---------------------------------------------------------------------------
-- Gewählter Gegenstand
---------------------------------------------------------------------------

local function ItemKeyInfo(itemKey)
    local api = C_AuctionHouse
    local info = api and api.GetItemKeyInfo and Core.Call(api.GetItemKeyInfo, itemKey)
    return type(info) == "table" and info or nil
end

-- Ergebniszeile angeklickt (Blizzards SelectBrowseResult) bzw. Zeile mit rowData aus der Ergebnisliste.
function Panel.SetBrowse(result)
    local itemKey = type(result) == "table" and result.itemKey
    local itemID = type(itemKey) == "table" and Core.Num(itemKey.itemID)
    if not itemID then return false end
    local info = ItemKeyInfo(itemKey)
    current.buy = { itemID = itemID, itemKey = itemKey, name = (info and Core.Plain(info.itemName)) or Core.ItemNameByID(itemID),
        quality = info and Core.Num(info.quality), price = Core.Num(result.minPrice), offered = Core.Num(result.totalQuantity) }
    Panel.Refresh()
    return true
end

-- Angebotene Menge einer Ware aus Blizzards geladenen Angeboten (fremde und eigene); nil bei Einzelstücken oder
-- solange Blizzard die Angebote noch lädt.
local function CommodityQuantity(itemID)
    local api = C_AuctionHouse
    if not (api and Core.Call(api.HasFullCommoditySearchResults, itemID) == true) then return nil end
    local total = 0
    for index = 1, Core.Call(api.GetNumCommoditySearchResults, itemID) or 0 do
        local result = Core.Call(api.GetCommoditySearchResultInfo, itemID, index)
        total = total + (type(result) == "table" and Core.Num(result.quantity) or 0)
    end
    return total
end

-- Gegenstand im Verkaufsbereich übernehmen (nach SetItem und nach jeder Preiswahl Blizzards).
function Panel.FromSellFrame()
    local frame = ns.Sell.ActiveFrame()
    local location = frame and frame.GetItem and frame:GetItem()
    local itemID = location and Core.Call(C_Item.GetItemID, location)
    if not itemID then return false end
    local itemKey = Core.Call(C_AuctionHouse.GetItemKeyFromItem, location)
    local goods = AuctionHouseFrame and AuctionHouseFrame.CommoditiesSellFrame
    current.sell = { itemID = itemID, itemKey = itemKey, name = Core.ItemNameByID(itemID),
        link = Core.Call(C_Item.GetItemLink, location),
        quality = Core.Num(Core.Call(C_Item.GetItemQuality, location)), price = (ns.Sell.Lowest(frame)),
        offered = frame == goods and CommodityQuantity(itemID) or nil }
    return true
end

---------------------------------------------------------------------------
-- Aufbau
---------------------------------------------------------------------------

local function Text(template, point, rel, relPoint, x, y)
    local fs = panel:CreateFontString(nil, "OVERLAY", template)
    fs:SetPoint(point, rel, relPoint, x, y)
    fs:SetWidth(Panel.WIDTH - 24)
    fs:SetJustifyH("LEFT")
    if fs.SetWordWrap then fs:SetWordWrap(true) end
    return fs
end

-- Tooltip des Pfeils: was das Seitenteil zeigt, dazu der Weg zur Einstellung in der einen Form (Core.SettingsPathText,
-- T18-18; vorher „Einstellungen » ezAuction » Markt“ von Hand).
function Panel.ArrowTip()
    return L.MARKET_ARROW_TIP:format(Core.SettingsPathText("ezAuction", "OPT_HEADER_MARKET", "OPT_marketPanel", L))
end

local function Build()
    panelOpts = { name = "ezAuctionMarket", width = Panel.WIDTH, store = ns.db.ui, key = "marketOpen", open = true,
        side = ns.Sell.Side(), owner = ADDON, arrow = { x = 0 }, tip = L.MARKET_ARROW, tipBody = Panel.ArrowTip(),
        onToggle = function()
            Panel.Refresh()
            ns.Sell.UpdatePanel()
        end,
        onPlaced = function()
            Panel.Layout()
            Panel.Refresh()
        end }
    panel = Core.NewSidePanel(AuctionHouseFrame, panelOpts)
    if not panel then return end
    local room = Core.SIDEPANEL_ARROW_ROOM or 30
    panel.title = Text("GameFontNormal", "TOPLEFT", panel, "TOPLEFT", 12, -10)
    panel.title:SetWidth(Panel.WIDTH - 24 - room)
    panel.title:SetText(L.MARKET_TITLE)
    panel.name = Text("GameFontHighlight", "TOPLEFT", panel.title, "BOTTOMLEFT", 0, -6)
    graph = Core.NewGraph(panel, { width = Panel.GRAPH_W, height = Panel.GRAPH_H, owner = ADDON,
        tooltip = function(point)
            if type(point) == "table" and point.week then return ns.Market.WeekTip(point) end
            return ns.Market.PointTip(point)
        end })
    graph.frame:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -54)
    local back = graph.frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    back:SetAllPoints(graph.frame)
    back:SetColorTexture(0, 0, 0, 0.25)
    panel.empty = Text("GameFontDisable", "CENTER", graph.frame, "CENTER", 0, 0)
    panel.empty:SetWidth(Panel.GRAPH_W - 8)
    panel.empty:SetJustifyH("CENTER")
    panel.footer = Text("GameFontDisableSmall", "TOPLEFT", graph.frame, "BOTTOMLEFT", -6, -4)
    -- Umschalter Tage/Wochen (V1): rechts unter dem Graph auf der Höhe der Fußzeile; grau mit Grund im Tooltip, wenn es
    -- für den Gegenstand keine Wochen gibt (Leitlinie 3 und 11)
    panel.weeks = ns.TextButton(panel)
    panel.weeks:SetPoint("TOPRIGHT", graph.frame, "BOTTOMRIGHT", 6, -3)
    panel.weeks:SetMotionScriptsWhileDisabled(true)
    panel.weeks:SetScript("OnClick", function() Panel.ToggleWeeks() end)
    panel.weeks:SetScript("OnEnter", function(self) Core.ShowTip(self, self:GetText() or "", Panel.WeeksTip()) end)
    panel.weeks:Hide()
    panel.lines = Text("GameFontHighlightSmall", "TOPLEFT", panel.footer, "BOTTOMLEFT", 0, -6)
    -- Wochentag, Tageszeit (Entwurf 2b/2c) und „Entzaubern ≈ …“ (AUC-19) unter der Verfügbarkeit
    panel.more = Text("GameFontHighlightSmall", "TOPLEFT", panel.lines, "BOTTOMLEFT", 0, -6)
    panel.hint = Text("GameFontNormalSmall", "TOPLEFT", panel.more, "BOTTOMLEFT", 0, -6)
    -- Abschnitt „Beobachtet“ (AH-23, nur im Reiter Kaufen): Zielpreis am eigenen Eintrag des Favoriten-Spiegels
    panel.watch = Text("GameFontHighlightSmall", "TOPLEFT", panel.hint, "BOTTOMLEFT", 0, -8)
    panel.target = ns.TextButton(panel)
    panel.target:SetPoint("TOPLEFT", panel.watch, "BOTTOMLEFT", 0, -2)
    panel.target:SetLabel(L.WATCH_TARGET_BUTTON)
    panel.target:SetScript("OnClick", function() Panel.AskTarget() end)
    panel.target:SetScript("OnEnter", function(self) Core.ShowTip(self, L.WATCH_TARGET_BUTTON, L.WATCH_TARGET_BUTTON_TIP) end)
    panel.target:Hide()
    -- „Als Text kopieren“ (V5): Textknopf wie „Wochen“, Lage in Panel.Layout; grau mit Grund, wenn es nichts gibt
    panel.copy = ns.TextButton(panel)
    panel.copy:SetLabel(Core.L.COPYTEXT_TITLE)
    panel.copy:SetMotionScriptsWhileDisabled(true)
    panel.copy:SetScript("OnClick", function() Panel.Copy() end)
    panel.copy:SetScript("OnEnter", function(self) Core.ShowTip(self, Core.L.COPYTEXT_TITLE, Panel.CopyTip()) end)
    panel.copy:Hide()
end

-- Der Pfeil sitzt in der äußeren oberen Ecke des offenen Felds (Core.NewSidePanel): links angedockt rückt die
-- Überschrift um Core.SIDEPANEL_ARROW_ROOM nach rechts, rechts angedockt endet sie davor.
function Panel.Layout()
    if not panel then return end
    local room = Core.SIDEPANEL_ARROW_ROOM or 30
    local left = panel.side == "left"
    panel.title:ClearAllPoints()
    panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", left and (12 + room) or 12, -10)
    -- der Name hängt unter der Überschrift: links angedockt um die Pfeil-Ecke schmaler, sonst ragte er über den
    -- rechten Rand des Felds auf Blizzards Fenster
    panel.name:SetWidth(Panel.WIDTH - 24 - (left and room or 0))
    -- „Als Text kopieren“ oben rechts auf der Höhe der Überschrift: links angedockt gegenüber dem Pfeil, rechts
    -- angedockt links neben ihm (oben links steht dann die Überschrift)
    if panel.copy then
        panel.copy:ClearAllPoints()
        panel.copy:SetPoint("TOPRIGHT", panel, "TOPRIGHT", left and -12 or -(12 + room), -10)
    end
end

---------------------------------------------------------------------------
-- Füllen
---------------------------------------------------------------------------

local function StatusText(status, count, weekly)
    if weekly and status == "few" then
        return Core.Plural(count or 0, L.MARKET_FEW_WEEKS_ONE, L.MARKET_FEW_WEEKS_MANY, ns.Market.GRAPH_WEEKS)
    end
    if status == "variant" then return L.MARKET_VARIANT end
    if status == "few" then return Core.Plural(count or 0, L.MARKET_FEW_ONE, L.MARKET_FEW_MANY, ns.Market.GRAPH_DAYS) end
    return L.MARKET_NONE
end

-- Hinweis unter der Verfügbarkeit: Bewertung gegen den Median (Kaufen) bzw. dazu „guter Zeitpunkt“ (Verkaufen),
-- je mit Quelle; unter fünf Tagen nur der Satz, ab wann es einen Hinweis gibt; bei Abwandlungen (Suffix am Schlüssel
-- oder Stats.mixed) kein Urteil gegen den gemischten Median, sondern der Satz, warum nicht.
function Panel.HintText(entry, mode, stats)
    local Market = ns.Market
    if type(entry) ~= "table" or not ns.Enabled("marketHint") then return "" end
    local price = entry.price
    if not price then
        local info = ns.PriceInfo(entry.itemID)
        price = info and info.min
    end
    local variant = Market.HasVariant(entry.itemKey) or (type(stats) == "table" and stats.mixed and true) or false
    local judgement, why = Market.Judge(entry.itemID, price, variant)
    if not judgement then
        if why == "variant" then return Core.Grey(L.MARKET_HINT_VARIANT) end
        if why == "few" then return Core.Grey(L.MARKET_HINT_FEW:format(Market.HINT_DAYS)) end
        return ""
    end
    local lines = { Market.JudgeText(judgement) }
    if mode == "sell" then
        local advice = Market.SellAdvice(entry.itemID, price, entry.offered, variant)
        if advice then lines[#lines + 1] = Core.GREEN .. advice.text .. "|r" end
    end
    local source = Market.SourceLine(stats or judgement.stats, entry.itemID)
    if source then lines[#lines + 1] = Core.Grey(source) end
    return table.concat(lines, "\n")
end

-- Weitere Aussagen unter der Verfügbarkeit: Wochentag des Gegenstands (nicht bei Abwandlungen), Tageszeit des ganzen
-- Markts (Frage 38 – Empfehlung umgesetzt, Antwort offen) und „Entzaubern ≈ …“, wenn es mehr bringt als der
-- Auktionspreis (AUC-19; im Reiter Verkaufen mit dem Link, also der Stufe des Gegenstands im Verkaufsbereich).
function Panel.MoreText(entry, stats)
    local Market = ns.Market
    if type(entry) ~= "table" then return "" end
    local variant = Market.HasVariant(entry.itemKey) or (type(stats) == "table" and stats.mixed and true) or false
    local lines = {}
    local week = Market.WeekdayLine(entry.itemID, variant)
    if week then lines[#lines + 1] = week end
    local daytime = Market.DayTimeLine()
    if daytime then lines[#lines + 1] = daytime end
    local salvage = Market.SalvageLines(entry.link or entry.itemID, entry.price)
    if salvage[1] then lines[#lines + 1] = Core.GREEN .. salvage[1] .. "|r" end
    if salvage[2] then lines[#lines + 1] = Core.Grey(salvage[2]) end
    return table.concat(lines, "\n")
end

-- Reiter Verkaufen (Welle 15): die Zeile „Post: 2 Verkäufe, 3 Rückläufer“ aus ezCores Auskunft „Auktionspost“ (AH-28,
-- auch ohne Gegenstand im Verkaufsbereich) und die Verkaufsempfehlung zum Gegenstand dort (AH-29: Erfolgsquote,
-- üblicher Preis, Anzahlung – jeweils mit der Zahl der Erfassungen; Grundlage der Anzahlung ist der Preis im Feld).
-- Leer in anderen Reitern und mit beiden Schaltern aus. Nur Anzeige.
function Panel.SellText(entry, mode)
    if mode ~= "sell" or not ns.History then return "" end
    local lines = {}
    local mail = ns.History.MailLine()
    if mail then lines[#lines + 1] = mail end
    if type(entry) == "table" and entry.itemID then
        local frame, price = ns.Sell.ActiveFrame(), nil
        if frame then price = select(2, ns.Sell.PostValues(frame)) end
        local advice = ns.History.Advice(entry.itemID, price)
        if advice.lines[1] then
            lines[#lines + 1] = Core.GOLD .. L.ADVICE_HEAD .. "|r"
            for _, line in ipairs(advice.lines) do lines[#lines + 1] = line end
        end
    end
    return table.concat(lines, "\n")
end

-- Abschnitt „Beobachtet“ (AH-23): Text und ob der Knopf „Zielpreis …“ steht. Nur im Reiter Kaufen (im Reiter
-- Verkaufen liegt darunter die Taschenliste); ohne Schalter watchList leer.
function Panel.WatchText(entry, mode)
    if type(entry) ~= "table" or mode ~= "buy" or not ns.Enabled("watchList") then return "", false end
    local watched = ns.Watch.Of(entry.itemKey or { itemID = entry.itemID })
    if not watched then return Core.Grey(L.WATCH_PANEL_NOT), false end
    return L.WATCH_PANEL_HEAD .. "\n" .. ns.Watch.TargetText(watched, entry.price), true
end

-- Knopf „Zielpreis …“: Betrag wie im Höchstpreis-Dialog („5“ = 5 Gold, „5g 20s“); leer oder 0 entfernt ihn.
function Panel.AskTarget()
    local entry = Panel.Current()
    local watched = entry and ns.Watch.Of(entry.itemKey or { itemID = entry.itemID })
    if not watched then return false end
    local current = Core.Num(watched.target) and Core.PlainMoney(watched.target) or ""
    Core.AskText(L.WATCH_TARGET_PROMPT:format(ns.Watch.Name(watched)), current, function(text)
        Panel.SetTarget(watched, text)
    end)
    return true
end

-- Eingabe übernehmen. Rückgabe: true, wenn gesetzt oder entfernt; false bei unlesbarem Betrag (Hinweis im Chat).
function Panel.SetTarget(watched, text)
    if type(text) == "string" and (Core.Trim(text) == "" or Core.Trim(text) == "0") then
        ns.Watch.SetTarget(watched, nil)
        ns.Print(L.WATCH_TARGET_CLEARED:format(ns.Watch.Name(watched)))
        return true
    end
    local copper = ns.Lists.ParseMoney(text)
    if not copper then
        ns.Print(L.WATCH_TARGET_BAD)
        return false
    end
    ns.Watch.SetTarget(watched, copper)
    ns.Print(L.WATCH_TARGET_SET:format(ns.Watch.Name(watched), ns.Money(copper)))
    return true
end

-- Bei Abwandlungen ohne eigene Tagespunkte (vor Welle 23b erfasst, oder nur einmal gesehen) steht statt des Graphs ein
-- Hinweis; die Zeile darunter nennt den letzten eigenen Preis der Abwandlung (Prices.Get mit dem Schlüssel samt Suffix).
function Panel.VariantLine(entry)
    local info = type(entry) == "table" and entry.itemKey and ns.PriceInfo(entry.itemKey)
    if not (info and info.variant and Core.Num(info.min)) then return nil end
    local ago = Core.Num(info.seen) and Core.Ago and Core.Ago(info.seen) or "?"
    return L.MARKET_VARIANT_LAST:format(ns.Money(info.min), ago)
end

-- Tage oder Wochen (V1, Welle 23): die Wahl des Spielers, gemerkt für das Konto (ezAuctionDB.ui.marketWeeks).
function Panel.ShowsWeeks()
    return ns.db ~= nil and ns.db.ui.marketWeeks == true
end

-- Knopf „Wochen“ / „Tage“: umschalten. → true, wenn umgeschaltet (keine Wochen: nichts)
function Panel.ToggleWeeks()
    if not ns.db then return false end
    local button = panel and panel.weeks
    if not Panel.ShowsWeeks() and button and button.why then return false end
    ns.db.ui.marketWeeks = not Panel.ShowsWeeks() or nil
    Panel.Refresh()
    return true
end

-- Tooltip des Knopfs: was er zeigt bzw. warum es keine Wochen gibt (Leitlinie 11)
function Panel.WeeksTip()
    local button = panel and panel.weeks
    local why = button and button.why
    if Panel.ShowsWeeks() and not why then return L.MARKET_DAYS_TIP:format(ns.Market.Days()) end
    if why == "off" then return L.MARKET_WEEKS_OFF:format(Core.L.OPT_priceWeeks or "?") end
    if why == "none" then return L.MARKET_WEEKS_NONE:format(Core.L.OPT_priceWeeksMax or "?") end
    if why == "variant" then return L.MARKET_WEEKS_VARIANT end
    if why == "mixed" then return L.MARKET_WEEKS_MIXED end
    if why == "unwatched" then return L.MARKET_WEEKS_UNWATCHED end
    local prices = ns.Prices()
    local max = prices and type(prices.WeeksMax) == "function" and Core.Num(Core.Call(prices.WeeksMax)) or 26
    return L.MARKET_WEEKS_TIP:format(max)
end

-- Knopf zum gewählten Gegenstand einrichten. → true, wenn der Graph Wochen zeigen soll.
function Panel.UpdateWeeks(entry, hasVariant)
    local button = panel and panel.weeks
    if not button then return false end
    local ok, why = ns.Market.WeeksAvailable(entry.itemID, hasVariant)
    button.why = not ok and why or nil
    local weekly = ok and Panel.ShowsWeeks()
    button:SetLabel(weekly and L.MARKET_DAYS_BUTTON or L.MARKET_WEEKS_BUTTON)
    button:SetEnabled(ok)
    button:Show()
    return weekly
end

function Panel.Refresh()
    if not (panel and panel:IsShown()) then return end
    local Market = ns.Market
    local mode = ns.ModeName()
    local entry = current[mode or ""]
    -- Verkaufen: nur der Gegenstand, der gerade im Verkaufsbereich liegt
    if mode == "sell" then entry = Panel.FromSellFrame() and current.sell or nil end
    local note = panel.mode == "overlap" and Core.Grey(L.MARKET_OVERLAP) or nil
    if not entry then
        panel.name:SetText("")
        graph:Clear()
        panel.empty:SetText(mode == "sell" and L.MARKET_PICK_SELL or L.MARKET_PICK_BUY)
        panel.empty:Show()
        panel.footer:SetText("")
        panel.lines:SetText("")
        panel.more:SetText(Panel.SellText(nil, mode))
        panel.hint:SetText(note or "")
        panel.watch:SetText("")
        panel.target:Hide()
        panel.weeks:Hide()
        Panel.UpdateCopy(nil)
        Panel.Reflow()
        return
    end
    panel.name:SetText(ns.ColoredName(entry.name or ("#" .. entry.itemID), entry.quality))
    -- Abwandlung: mit dem Schlüssel samt Suffix fragen – dann Verlauf und Kennzahlen dieser Abwandlung (Welle 23)
    local hasVariant = Market.HasVariant(entry.itemKey)
    local weekly = Panel.UpdateWeeks(entry, hasVariant)
    local points, opts, status, stats, count
    if weekly then
        points, opts, status, count = Market.WeekPoints(entry.itemID)
        stats = Market.Stats(entry.itemID)
    else
        points, opts, status, stats, count = Market.GraphPoints(hasVariant and entry.itemKey or entry.itemID, hasVariant)
    end
    if status == "ok" then
        graph:SetData(points, opts)
        panel.empty:Hide()
    else
        graph:Clear()
        local text = StatusText(status, count, weekly)
        local variant = status == "variant" and Panel.VariantLine(entry)
        panel.empty:SetText(variant and (text .. "\n" .. variant) or text)
        panel.empty:Show()
    end
    if count and count > 0 and weekly then
        panel.footer:SetText(Core.Plural(count, L.MARKET_FOOTER_WEEKS_ONE, L.MARKET_FOOTER_WEEKS_MANY))
    elseif count and count > 0 then
        panel.footer:SetText(Core.Plural(count, L.MARKET_FOOTER_ONE, L.MARKET_FOOTER_MANY))
    else
        panel.footer:SetText("")
    end
    panel.lines:SetText(table.concat(Market.Availability(entry.itemID, stats, entry.offered), "\n"))
    local more, sell = Panel.MoreText(entry, stats), Panel.SellText(entry, mode)
    if sell ~= "" then more = more ~= "" and (more .. "\n" .. sell) or sell end
    panel.more:SetText(more)
    local hint = Panel.HintText(entry, mode, stats)
    if note then hint = hint ~= "" and (hint .. "\n" .. note) or note end
    panel.hint:SetText(hint)
    local watchText, canTarget = Panel.WatchText(entry, mode)
    panel.watch:SetText(watchText)
    panel.target:SetShown(canTarget)
    Panel.UpdateCopy(entry, hasVariant)
    Panel.Reflow()
end

---------------------------------------------------------------------------
-- „Als Text kopieren“ (V5 aus docs/archiv/eroerterung-datenbank.md, vom Nutzer am 16.11.2026 freigegeben; Welle 24)
---------------------------------------------------------------------------

-- Gibt es ezCores Kopierfeld (Welle 23d)? Ohne ihn steht kein Knopf da (defensiv, ezAuction verlangt ihn nicht in needs).
function Panel.CanCopy()
    return type(Core.CopyAsText) == "function" and type(Core.TableText) == "function"
end

-- Zeilen zum Gegenstand (Market.CopyRows): mit dem Schlüssel samt Suffix bei Abwandlungen, wie der Graph.
-- any = true: nur prüfen, ob es etwas gibt. → zeilen, grund (wie Market.CopyRows)
function Panel.CopyRows(entry, hasVariant, any)
    if type(entry) ~= "table" or not entry.itemID then return {} end
    if hasVariant == nil then hasVariant = ns.Market.HasVariant(entry.itemKey) end
    return ns.Market.CopyRows(hasVariant and entry.itemKey or entry.itemID, hasVariant, { name = entry.name, any = any })
end

-- Knopf zum gewählten Gegenstand: verborgen ohne Gegenstand oder Kopierfeld, grau ohne Zahlen.
function Panel.UpdateCopy(entry, hasVariant)
    local button = panel and panel.copy
    if not button then return end
    if not (entry and Panel.CanCopy()) then
        button:Hide()
        return
    end
    local rows, reason = Panel.CopyRows(entry, hasVariant, true)
    button.empty = #rows == 0
    button.reason = button.empty and reason or nil
    button:SetEnabled(not button.empty)
    button:Show()
end

function Panel.CopyTip()
    local button = panel and panel.copy
    if button and button.empty then
        -- Preise erfasst, aber wie beim Graph nicht gezeigt: das ist der Grund, nicht „nichts erfasst“
        return Core.Grey(button.reason == "variant" and L.MARKET_COPY_VARIANT or L.MARKET_COPY_EMPTY)
    end
    return L.MARKET_COPY_TIP:format(Core.L.COPYTEXT_NAMES or "?")
end

-- Klick: Kopierfeld mit der Tabelle des gewählten Gegenstands, am Seitenteil. → der Dialog | nil (nichts zu kopieren)
function Panel.Copy()
    local entry = Panel.Current()
    if not (entry and Panel.CanCopy()) then return nil end
    local rows = Panel.CopyRows(entry)
    if #rows == 0 then return nil end
    return Core.CopyAsText({ title = L.MARKET_COPY_TITLE:format(entry.name or ("#" .. entry.itemID)),
        columns = ns.Market.CopyColumns(), rows = rows, anchor = panel, owner = ADDON })
end

-- Nach jedem neuen Text: rückt die eingebettete Taschenliste nach, wenn sich der Beginn (Panel.BagTop) geändert hat.
function Panel.Reflow()
    local top = Panel.BagTop()
    if top == panel.bagTop then return end
    panel.bagTop = top
    if ns.Sell.Reflow then ns.Sell.Reflow() end
end

-- Seitenteil und Pfeil nach Ansicht und Schalter zeigen oder verbergen; danach sitzt die Taschenliste richtig.
function Panel.Update()
    if not Panel.Wanted() then
        if panel then
            panel:Hide()
            panel.arrow:Hide()
        end
        if ns.Sell then ns.Sell.UpdatePanel() end
        return
    end
    if not panel then Build() end
    if not panel then return end
    panelOpts.side = ns.Sell.Side()
    panel.arrow:Show()
    panel:SetShown(panel:IsOpen())
    panel:Place()
    Panel.Layout()
    Panel.Refresh()
    ns.Sell.UpdatePanel()
end

---------------------------------------------------------------------------

ns.OnAuctionHouse(function()
    local frame = AuctionHouseFrame
    if type(frame.SelectBrowseResult) == "function" then
        hooksecurefunc(frame, "SelectBrowseResult", function(_, result) ns.Try("Market", Panel.SetBrowse, result) end)
    end
    local later = ns.Throttle(function() Panel.Refresh() end, 0.1)
    for _, sell in ipairs({ frame.ItemSellFrame, frame.CommoditiesSellFrame }) do
        if sell and sell.UpdatePriceSelection then hooksecurefunc(sell, "UpdatePriceSelection", later) end
    end
    Panel.Update()
end)
ns.Listen("AH_MODE", Panel.Update)
ns.Listen("AH_SHOW", Panel.Update)
ns.Listen("AH_HIDE", function() if panel then panel:Hide() panel.arrow:Hide() end end)
ns.Listen("SELL_ITEM", function() Panel.Refresh() end)
ns.Listen("PRICES_UPDATED", function() Panel.Refresh() end)
ns.Listen("WATCH_CHANGED", function() Panel.Refresh() end)
-- ezCore trägt Auktionspost und Einstellungen ein (AH-28, AH-29): Zeile „Post: …“ und Empfehlung folgen
Core.Listen("HISTORY_ADDED", function(kind)
    if kind == "auction" or kind == "posting" then Panel.Refresh() end
end, ADDON)
ns.OnSettingChanged(function(key)
    if key == "marketPanel" or key == "sellListSide" then Panel.Update() end
    if key == "marketHint" or key == "bargainPercent" or key == "salvageCompare" or key == "watchList"
        or key == "auctionMail" or key == "sellAdvice" then
        Panel.Refresh()
    end
end)
