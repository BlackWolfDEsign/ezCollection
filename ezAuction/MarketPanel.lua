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
        Hilfslinie Median, Händlerpreis gestrichelt; Tage ohne Erfassung überbrückt die Linie gestrichelt (seit 21.11.2026); Tooltip je Tag mit Quelle;
        Fußzeile „deine Erfassungen, 9 Tage“. Wenige Punkte oder Abwandlungen: ein Hinweis statt des Graphs.
        Rechts unter dem Graph die Knöpfe „Tage“ · „Wochen“ · „Monate“ (V1, Welle 23: „Wochen“/„Tage“; seit dem
        21.11.2026 drei Ansichten, Entscheidung des Nutzers „Beides bauen“): jede zeigt ein festes Fenster (14 Tage, bis
        26 Wochen, bis 24 Monate aus ezCores Wochen- und Monatspunkten), so wird der Graph nie gestaucht; gemerkt in
        ezAuctionDB.ui.marketWeeks bzw. marketView = "months". Oben in der Titelleiste neben dem Pfeil Blizzards Knopf
        „Vergrößern“/„Verkleinern“ (MaximizeMinimizeButtonFrameTemplate, wie an der Weltkarte): breiteres Feld, größerer
        Graph, gemerkt in ezAuctionDB.ui.marketBig.
      - Verfügbarkeit: „Gesehen an 9 von 12 erfassten Tagen“, übliche Menge (Market.Availability)
      - darunter Wochentag und Tageszeit (Entwurf 2b/2c, Frage 38) und „Entzaubern ≈ …“ (AUC-19, Schalter
        salvageCompare), Panel.MoreText
      - im Reiter Verkaufen darunter „Post: 2 Verkäufe, 3 Rückläufer“ (AH-28) und die Verkaufsempfehlung (AH-29,
        History.Advice), Panel.SellText – seit Welle 15
      - Hinweis gegen den Median mit Begründung und Quelle (Market.Judge, Market.SellAdvice; Schalter marketHint)
      - immer rechts (Panel.SIDE); die Taschenliste ist seit dem 21.11.2026 ein eigenes Seitenteil links (SellTab.lua)
      - oben rechts auf der Höhe der Überschrift (links angedockt gegenüber dem Pfeil, rechts angedockt links neben
        ihm) der Knopf „Als Text kopieren“ (V5, Welle 24): Tage, Wochen und eigene Auktionen des Gegenstands als
        Tabelle in ezCores Kopierfeld (Market.CopyRows, Core.CopyAsText); Namen von Käufern und Verkäufern nur mit dem
        Häkchen im Kopierfeld (Frage E6). Ohne ezCores Kopierfeld kein Knopf.
    Steht in Blizzards Reitern Kaufen, Verkaufen und Auktionen (seit dem 21.11.2026); in der Ansicht eines fremden Addons (ns.ModeName "other")
    verschwinden Feld und Pfeil. Nur Anzeige – nichts wird gekauft, eingestellt oder eingetragen.
]]

local Panel = {}
ns.MarketPanel = Panel

-- Breite wie alle Seitenteile (ns.PANEL_WIDTH, 460 – Entscheidung des Nutzers vom 21.11.2026 „Alle 460 wie ezTalent“;
-- vorher 260); bei weniger Platz rechts schmaler bis ns.PANEL_MIN (Panel.FitWidth). Der Graph füllt die Breite bis auf
-- 18 je Seite (4 Kasten + 14 Kopf-Einzug).
local LOOK = ns.LOOK
Panel.WIDTH = ns.PANEL_WIDTH
Panel.GRAPH_INSET = 18
-- GRAPH_W/GRAPH_W_BIG: Breite bei voller Wunschbreite (Ausgangswerte; gezeichnet wird nach der wirklichen Breite,
-- Panel.GraphSize)
Panel.GRAPH_W, Panel.GRAPH_H = Panel.WIDTH - 2 * Panel.GRAPH_INSET, 130
-- vergrößert (Knopf in der Titelleiste, 21.11.2026): breiter und höher (seit dem Wechsel auf 460 von 420 auf 640)
Panel.WIDTH_BIG = 640
Panel.GRAPH_W_BIG, Panel.GRAPH_H_BIG = Panel.WIDTH_BIG - 2 * Panel.GRAPH_INSET, 210
-- Seite des Felds: immer rechts, in allen Reitern (Entscheidung des Nutzers vom 21.11.2026, „Zwei Seitenteile“ – vorher
-- wählte ezAuction die Seite nach dem Platz, und das Feld sprang zwischen Kaufen und Verkaufen). „Aus der Tasche“ ist
-- seitdem ein eigenes Seitenteil links (SellTab.lua), nicht mehr ein Abschnitt in diesem Feld.
Panel.SIDE = "right"

local panel, graph, panelOpts
local current = {}      -- [Ansicht "buy" | "sell" | "auctions"] = { itemID, itemKey, name, quality, price, offered }

-- Gibt es ezCores Bausteine (Seitenteil und Linien) und Blizzards Auktionsfenster?
function Panel.Available()
    return type(Core.NewSidePanel) == "function" and type(Core.NewGraph) == "function" and AuctionHouseFrame ~= nil
end

-- Soll das Seitenteil (samt Pfeil) jetzt dastehen? In Blizzards Reitern Kaufen, Verkaufen und Auktionen.
function Panel.Wanted()
    if not (ns.ahReady and ns.Enabled("marketPanel") and Panel.Available() and ns.AuctionHouseShown()) then return false end
    local mode = ns.ModeName()
    -- in allen drei Reitern (zweiter Spieltest vom 21.11.2026: „sollte das markt fenster bei allen 3 reitern offen sein
    -- und die entsprechenden infos liefern … bei Auktionen tab ist es nicht da“)
    return mode == "buy" or mode == "sell" or mode == "auctions"
end

-- Steht die Taschenliste rechts (kein Platz links, oder Schalter „Seite der Taschenliste“) und ist das Feld zugeklappt,
-- dockt sie direkt an Blizzards Fenster; der Pfeil rückt dann an ihren äußeren Rand, sonst läge er auf ihrem Rahmen
-- und Filterfeld. Gesetzt über ezCores
-- teil:SetArrowOffset (x = Abstand vom Fensterrand; platziert selbst neu, nur bei Änderung – Welle 23b, kam im selben
-- Zweig wie Prices.Weekday aus needs); vorher schrieb ezAuction panelOpts.arrow.x selbst.
function Panel.PlaceArrow()
    if not (panel and panelOpts) then return end
    local x = 0
    if not panel:IsOpen() then
        -- zugeklappt: außen an einem Seitenteil derselben Seite (Taschenliste beim Verkaufen, Einkaufsliste beim Kaufen)
        if ns.Sell.Docked() and panel.side == ns.Sell.DockedSide() then x = ns.Sell.PanelWidth() + ns.PANEL_GAP end
        if ns.Editor and ns.Editor.IsShown() and panel.side == ns.Editor.DockedSide() then x = ns.Editor.Width() + ns.PANEL_GAP end
    end
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

-- Reiter „Auktionen“: die gewählte eigene Auktion bzw. das gewählte Gebot (Blizzards SetItemKey, SelectAuction und
-- OnBidsListSearchResultSelected – nur gehört, Shared/Blizzard_AuctionHouseAuctionsFrame.lua, Zweig forever). price:
-- Sofortkauf der Auktion (für den Hinweis gegen den Median), sonst nil.
function Panel.SetAuctions(itemKey, price)
    local itemID = type(itemKey) == "table" and Core.Num(itemKey.itemID)
    if not itemID then
        -- Blizzard hebt die Auswahl auf (SetItemKey(nil)): der Markt zeigt nicht weiter den vorigen Gegenstand
        if itemKey == nil and current.auctions then
            current.auctions = nil
            Panel.Refresh()
        end
        return false
    end
    local info = ItemKeyInfo(itemKey)
    current.auctions = { itemID = itemID, itemKey = itemKey, name = (info and Core.Plain(info.itemName)) or Core.ItemNameByID(itemID),
        quality = info and Core.Num(info.quality), price = Core.Num(price) }
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

local texts = {}   -- Zeilen in voller Breite (Panel.Layout passt sie beim Vergrößern an)
local function Text(template, point, rel, relPoint, x, y)
    local fs = panel:CreateFontString(nil, "OVERLAY", template)
    fs:SetPoint(point, rel, relPoint, x, y)
    fs:SetWidth(Panel.TextWidth())
    texts[#texts + 1] = fs
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
    panelOpts = { name = "ezAuctionMarket", width = Panel.FitWidth(), store = ns.db.ui, key = "marketOpen", open = true,
        side = Panel.SIDE, gap = ns.PANEL_GAP, owner = ADDON, arrow = { x = 0 }, template = "ButtonFrameTemplate", tip = L.MARKET_ARROW, tipBody = Panel.ArrowTip(),
        onToggle = function()
            Panel.Refresh()
            Panel.RedockLeft()
        end,
        onPlaced = function()
            -- auch ezCores eigenes Neu-Andocken (Auktionshaus erscheint, wird verschoben oder größer) rechnet die Breite
            -- neu (Befund des Reviews); bei Änderung dockt SetPanelWidth an und ruft dies hier noch einmal
            if panel and Panel.FitWidth() ~= panel.fitWidth then
                local _, changed = Panel.ApplyWidth()
                if changed then return end
            end
            Panel.Layout()
            Panel.Refresh()
            -- Taschenliste und Einkaufsliste docken außen am Markt, wenn sie auf derselben Seite stehen: mitziehen,
            -- wenn der Markt die Seite wechselt (kein Platz rechts) oder neu angedockt wird
            Panel.RedockLeft()
        end }
    panel = Core.NewSidePanel(AuctionHouseFrame, panelOpts)
    if not panel then return end
    panel.fitWidth = panelOpts.width
    -- derselbe Rahmen wie „Aus der Tasche“ (zweiter Spieltest vom 21.11.2026, Entscheidung „Wie „Aus der Tasche““):
    -- Titel in Blizzards Titelleiste, der Pfeil sitzt in ihrer Ecke statt eines X
    ns.PanelLook(panel, L.MARKET_TITLE)
    -- Kopf wie ezTalent: der Name ab ns.PANEL_TOP, LOOK.headLeft vom Rand; darunter Blizzards innerer Kasten bis über
    -- „Als Text kopieren“ (ns.PanelInset – ein zweizeiliger Name schiebt den Kasten mit, statt über seine Kante zu laufen)
    panel.name = Text("GameFontHighlight", "TOPLEFT", panel, "TOPLEFT", LOOK.headLeft, -ns.PANEL_TOP)
    panel.name:SetWidth(Panel.TextWidth())
    panel.inset = ns.PanelInset(panel, panel.name, LOOK.headLeft, ns.BUTTON_Y + ns.TEXT_BUTTON_H + LOOK.buttonGap + 2)
    local graphW, graphH = Panel.GraphSize()
    graph = Core.NewGraph(panel, { width = graphW, height = graphH, owner = ADDON,
        tooltip = function(point)
            if type(point) == "table" and point.month then return ns.Market.MonthTip(point) end
            if type(point) == "table" and point.week then return ns.Market.WeekTip(point) end
            return ns.Market.PointTip(point)
        end })
    if panel.inset then
        graph.frame:SetPoint("TOPLEFT", panel.inset, "TOPLEFT", Panel.GRAPH_INSET - 4, -LOOK.headGap)
    else
        graph.frame:SetPoint("TOPLEFT", panel, "TOPLEFT", Panel.GRAPH_INSET, -54)
    end
    local back = graph.frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    back:SetAllPoints(graph.frame)
    back:SetColorTexture(0, 0, 0, 0.25)
    panel.empty = Text("GameFontDisable", "CENTER", graph.frame, "CENTER", 0, 0)
    panel.empty:SetWidth(graphW - 8)
    panel.empty:SetJustifyH("CENTER")
    panel.footer = Text("GameFontDisableSmall", "TOPLEFT", graph.frame, "BOTTOMLEFT", -6, -4)
    -- Ansichten Tage · Wochen · Monate (V1; seit 21.11.2026 drei Knöpfe): rechts unter dem Graph auf der Höhe der
    -- Fußzeile, die gezeigte weiß; grau mit Grund im Tooltip, wenn es für den Gegenstand keine gibt (Leitlinie 3 und 11)
    local labels = { days = L.MARKET_DAYS_BUTTON, weeks = L.MARKET_WEEKS_BUTTON, months = L.MARKET_MONTHS_BUTTON }
    local right = nil
    for _, view in ipairs({ "months", "weeks", "days" }) do
        local button = ns.TextButton(panel)
        if right then
            button:SetPoint("TOPRIGHT", right, "TOPLEFT", -8, 0)
        else
            button:SetPoint("TOPRIGHT", graph.frame, "BOTTOMRIGHT", 6, -3)
        end
        button:SetLabel(labels[view])
        button.view = view
        button:SetMotionScriptsWhileDisabled(true)
        button:SetScript("OnClick", function() Panel.SetView(view) end)
        button:SetScript("OnEnter", function(self) Core.ShowTip(self, labels[view], Panel.ViewTip(view)) end)
        button:Hide()
        panel[view] = button
        right = button
    end
    -- die Fußzeile endet vor den Knöpfen und darf umbrechen (oben rechts angehängt, nicht „RIGHT“: das legte auch die
    -- Höhe fest und schnitte die zweite Zeile ab – Befund des Reviews)
    panel.footer:SetPoint("TOPRIGHT", panel.days, "TOPLEFT", -6, -1)
    if panel.footer.SetWordWrap then panel.footer:SetWordWrap(true) end
    -- Vergrößern/Verkleinern: Blizzards Vorlage der Weltkarte (MaximizeMinimizeButtonFrameTemplate); links neben dem
    -- Pfeil in der Titelleiste, Lage in Panel.Layout. Fehlt die Vorlage im Client, gibt es den Knopf nicht.
    local ok, maxMin = pcall(CreateFrame, "Frame", nil, panel, "MaximizeMinimizeButtonFrameTemplate")
    if ok and maxMin and maxMin.SetOnMaximizedCallback and maxMin.SetOnMinimizedCallback then
        panel.size = maxMin
        maxMin:SetFrameLevel((panel:GetFrameLevel() or 1) + Core.SIDEPANEL_ARROW_LEVEL)
        -- Blizzards Wörter: „Maximize“ = groß machen; der Knopf zeigt, was ein Klick tut (wie an der Weltkarte)
        maxMin:SetOnMaximizedCallback(function() Panel.SetBig(true) end)
        maxMin:SetOnMinimizedCallback(function() Panel.SetBig(false) end)
        if Panel.IsBig() then maxMin:Maximize(true, true) else maxMin:Minimize(true, true) end
        for key, tip in pairs({ MaximizeButton = { L.MARKET_BIG_TIP, L.MARKET_BIG_TIP_TEXT },
            MinimizeButton = { L.MARKET_SMALL_TIP, L.MARKET_BIG_TIP_TEXT } }) do
            local button = maxMin[key]
            if button and button.HookScript then
                button:HookScript("OnEnter", function(self) Core.ShowTip(self, tip[1], tip[2]) end)
                button:HookScript("OnLeave", GameTooltip_Hide)
            end
        end
    end
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

-- Seit dem zweiten Spieltest vom 21.11.2026 steht der Titel in Blizzards Titelleiste und der Pfeil in ihrer Ecke: der
-- Name darunter nutzt die volle Breite auf beiden Seiten, „Als Text kopieren“ sitzt unten rechts im Feld (vorher oben
-- neben dem Pfeil, auf der Höhe der eigenen Überschrift).
function Panel.Layout()
    if not panel then return end
    for _, fs in ipairs(texts) do
        if fs ~= panel.footer then fs:SetWidth(Panel.TextWidth()) end   -- die Fußzeile hat zwei Anker
    end
    local graphW, graphH = Panel.GraphSize()
    if graph then
        if graph.SetSize then graph:SetSize(graphW, graphH) else graph.frame:SetSize(graphW, graphH) end
    end
    if panel.empty then panel.empty:SetWidth(graphW - 8) end
    if panel.size then
        -- neben dem Pfeil (Core.NewSidePanel: offen in der äußeren oberen Ecke, 24 breit, 4 vom Rand)
        local left = panel.side == "left"
        local corner = left and "TOPLEFT" or "TOPRIGHT"
        panel.size:ClearAllPoints()
        panel.size:SetPoint(corner, panel, corner, left and 28 or -28, -4)
    end
    if panel.copy then
        panel.copy:ClearAllPoints()
        -- Textknopf rechts unten: 12 vom Rand (schmaler Textknopf, nicht der 14er-Rand der Knopfreihe), Höhe wie die
        -- Knöpfe der Seitenteile (ns.BUTTON_Y aus ezCore) – der Kasten darüber rechnet mit demselben Wert
        panel.copy:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -12, ns.BUTTON_Y)
    end
end

-- Vergrößert? (ezAuctionDB.ui.marketBig, gemerkt für das Konto)
function Panel.IsBig()
    return ns.db ~= nil and ns.db.ui.marketBig == true
end

-- Wunschbreite des Felds, je nachdem, ob vergrößert
function Panel.Width()
    return Panel.IsBig() and Panel.WIDTH_BIG or Panel.WIDTH
end

-- Breite nach dem Platz rechts neben dem Auktionshaus (ns.FitWidth: die Wunschbreite, sonst schmaler bis
-- ns.PANEL_MIN; reicht es rechts nicht einmal dafür, zählt der Platz links – dorthin weicht ezCores Core.Dock aus).
function Panel.FitWidth()
    local wish = Panel.Width()
    if not (panel and Core.DockRoom and AuctionHouseFrame) then return wish end
    local room = Core.DockRoom(panel, AuctionHouseFrame, "right", ns.PANEL_GAP)
    if room and room < ns.PANEL_MIN then
        local left = Core.DockRoom(panel, AuctionHouseFrame, "left", ns.PANEL_GAP)
        if left and left > room then room = left end
    end
    return ns.FitWidth(room, wish)
end

-- Breite gerade (nach dem Platz) und Breite der Zeilen (der Kopf-Einzug links und rechts)
function Panel.CurrentWidth()
    return panel and panel.fitWidth or Panel.Width()
end

function Panel.TextWidth()
    return Panel.CurrentWidth() - 2 * LOOK.headLeft
end

-- Größe des Graphs: die Breite des Felds bis auf Panel.GRAPH_INSET je Seite, die Höhe je nachdem, ob vergrößert
function Panel.GraphSize()
    local width = Panel.CurrentWidth() - 2 * Panel.GRAPH_INSET
    return width, Panel.IsBig() and Panel.GRAPH_H_BIG or Panel.GRAPH_H
end

-- Breite nach dem Platz setzen (ezCores panel:SetPanelWidth dockt bei Änderung neu an). → die Breite, geändert?
function Panel.ApplyWidth()
    if not panel then return Panel.Width(), false end
    local width = Panel.FitWidth()
    panel.fitWidth = width
    if panel.SetPanelWidth then return width, panel:SetPanelWidth(width) end
    local changed = panel:GetWidth() ~= width
    panel:SetWidth(width)
    return width, changed
end

-- Vergrößern/Verkleinern (Blizzards Knopf in der Titelleiste): neue Breite samt Platzprüfung und Andocken (ezCores
-- panel:SetPanelWidth; die Seitenteile links docken über onPlaced neu an), Graph und Zeilen in der neuen Größe.
-- → true, wenn geändert
function Panel.SetBig(big)
    if not ns.db then return false end
    big = big and true or false
    if Panel.IsBig() == big then return false end
    ns.db.ui.marketBig = big or nil
    if panel then
        Panel.ApplyWidth()
        if panel.size then
            if big then panel.size:Maximize(true, true) else panel.size:Minimize(true, true) end
        end
        Panel.Layout()
        Panel.Refresh()
        Panel.RedockLeft()
    end
    return true
end

---------------------------------------------------------------------------
-- Füllen
---------------------------------------------------------------------------

local function StatusText(status, count, weekly)
    if weekly == "months" and status == "few" then
        return Core.Plural(count or 0, L.MARKET_FEW_MONTHS_ONE, L.MARKET_FEW_MONTHS_MANY, ns.Market.GRAPH_MONTHS)
    end
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

-- Tage, Wochen oder Monate (V1, Welle 23; Monate seit 21.11.2026): die Wahl des Spielers, gemerkt für das Konto
-- (ezAuctionDB.ui.marketWeeks = Wochen wie bisher, marketView = "months" für Monate). → "days" | "weeks" | "months"
function Panel.View()
    if not ns.db then return "days" end
    if ns.db.ui.marketView == "months" then return "months" end
    return ns.db.ui.marketWeeks == true and "weeks" or "days"
end

function Panel.ShowsWeeks()
    return Panel.View() == "weeks"
end

-- Ansicht wählen (Knöpfe „Tage“ · „Wochen“ · „Monate“). → true, wenn gewählt (gibt es sie nicht: nichts)
function Panel.SetView(view)
    if not ns.db or (view ~= "days" and view ~= "weeks" and view ~= "months") then return false end
    local button = panel and panel[view]
    if view ~= "days" and button and button.why then return false end
    ns.db.ui.marketWeeks = view == "weeks" or nil
    ns.db.ui.marketView = view == "months" and "months" or nil
    Panel.Refresh()
    return true
end

-- Tage ↔ Wochen umschalten (V1, Welle 23; bleibt für Aufrufer und Prüfungen). → true, wenn umgeschaltet
function Panel.ToggleWeeks()
    if not ns.db then return false end
    return Panel.SetView(Panel.ShowsWeeks() and "days" or "weeks")
end

-- Grund ohne Wochen bzw. Monate als Satz (eine Stelle für beide Knöpfe); nil ohne bekannten Grund
function Panel.WhyTip(why)
    if why == "off" then return L.MARKET_WEEKS_OFF:format(Core.L.OPT_priceWeeks or "?") end
    if why == "none" then return L.MARKET_WEEKS_NONE:format(Core.L.OPT_priceWeeksMax or "?") end
    if why == "variant" then return L.MARKET_WEEKS_VARIANT end
    if why == "mixed" then return L.MARKET_WEEKS_MIXED end
    if why == "unwatched" then return L.MARKET_WEEKS_UNWATCHED end
    if why == "nomonths" then return L.MARKET_MONTHS_NONE:format(Core.L.OPT_priceMonthsMax or "?") end
    return nil
end

-- Tooltip eines Ansichts-Knopfs: was er zeigt bzw. warum es sie nicht gibt (Leitlinie 11)
function Panel.ViewTip(view)
    local shown = Panel.View() == view and ("\n" .. Core.Grey(L.MARKET_VIEW_SHOWN)) or ""
    if view == "days" then return L.MARKET_VIEW_DAYS_TIP:format(ns.Market.Days()) .. shown end
    if view == "weeks" then
        local why = panel and panel.weeks and panel.weeks.why
        return why and (Panel.WhyTip(why) or "") or (Panel.WeeksTip() .. shown)
    end
    local why = panel and panel.months and panel.months.why
    if why == "nomonths" then return Panel.WhyTip(why) or "" end
    -- von den Wochen geerbte Gründe: erst der Satz, dass Monate aus Wochen entstehen (Befund des Reviews)
    if why then return L.MARKET_MONTHS_FROM_WEEKS .. " " .. (Panel.WhyTip(why) or "") end
    local prices = ns.Prices()
    local max = prices and type(prices.MonthsMax) == "function" and Core.Num(Core.Call(prices.MonthsMax))
        or (prices and Core.Num(prices.MONTHS_MAX)) or 0
    return L.MARKET_MONTHS_TIP:format(max) .. shown
end

-- Tooltip des Knopfs „Wochen“: was er zeigt bzw. warum es keine Wochen gibt (Leitlinie 11). Seit es drei Knöpfe gibt
-- (21.11.2026), sagt er immer, was die Wochen zeigen – zurück zu den Tagen führt der Knopf „Tage“.
function Panel.WeeksTip()
    local button = panel and panel.weeks
    local why = button and button.why
    local reason = why and Panel.WhyTip(why)
    if reason then return reason end
    local prices = ns.Prices()
    local max = prices and type(prices.WeeksMax) == "function" and Core.Num(Core.Call(prices.WeeksMax)) or 26
    return L.MARKET_WEEKS_TIP:format(max)
end

-- Knöpfe zum gewählten Gegenstand einrichten. → true, wenn der Graph Wochen zeigen soll (wie bisher); zweiter Wert:
-- die Ansicht, die der Graph zeigt ("days" | "weeks" | "months"; fehlt die gewählte, gelten die Tage).
function Panel.UpdateWeeks(entry, hasVariant)
    local button = panel and panel.weeks
    if not button then return false, "days" end
    local Market = ns.Market
    local okW, whyW = Market.WeeksAvailable(entry.itemID, hasVariant)
    local okM, whyM = Market.MonthsAvailable(entry.itemID, hasVariant)
    button.why = not okW and whyW or nil
    panel.months.why = not okM and whyM or nil
    local view = Panel.View()
    if (view == "weeks" and not okW) or (view == "months" and not okM) then view = "days" end
    for _, key in ipairs({ "days", "weeks", "months" }) do
        local b = panel[key]
        b:SetEnabled(key == "days" or (key == "weeks" and okW) or (key == "months" and okM))
        -- die gezeigte Ansicht weiß, die übrigen in Blizzards Gelb
        if b.SetNormalFontObject then b:SetNormalFontObject(key == view and "GameFontHighlightSmall" or "GameFontNormalSmall") end
        b.shown = key == view
        b:Show()
    end
    return view == "weeks", view
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
        panel.empty:SetText(mode == "sell" and L.MARKET_PICK_SELL or mode == "auctions" and L.MARKET_PICK_AUCTIONS or L.MARKET_PICK_BUY)
        panel.empty:Show()
        panel.footer:SetText("")
        panel.lines:SetText("")
        panel.more:SetText(Panel.SellText(nil, mode))
        panel.hint:SetText(note or "")
        panel.watch:SetText("")
        panel.target:Hide()
        panel.days:Hide()
        panel.weeks:Hide()
        panel.months:Hide()
        Panel.UpdateCopy(nil)
        return
    end
    panel.name:SetText(ns.ColoredName(entry.name or ("#" .. entry.itemID), entry.quality))
    -- Abwandlung: mit dem Schlüssel samt Suffix fragen – dann Verlauf und Kennzahlen dieser Abwandlung (Welle 23)
    local hasVariant = Market.HasVariant(entry.itemKey)
    local _, view = Panel.UpdateWeeks(entry, hasVariant)
    local weekly = view ~= "days" and view or nil
    local points, opts, status, stats, count
    if view == "months" then
        points, opts, status, count = Market.MonthPoints(entry.itemID)
        stats = Market.Stats(entry.itemID)
    elseif view == "weeks" then
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
    if count and count > 0 and view == "months" then
        panel.footer:SetText(Core.Plural(count, L.MARKET_FOOTER_MONTHS_ONE, L.MARKET_FOOTER_MONTHS_MANY))
    elseif count and count > 0 and weekly then
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

-- Seitenteil und Pfeil nach Ansicht und Schalter zeigen oder verbergen; danach dockt die Taschenliste neu an.
function Panel.Update()
    if not Panel.Wanted() then
        if panel then
            panel:Hide()
            panel.arrow:Hide()
        end
        Panel.RedockLeft()
        return
    end
    if not panel then Build() end
    if not panel then return end
    panelOpts.side = Panel.SIDE
    panel.arrow:Show()
    panel:SetShown(panel:IsOpen())
    Panel.ApplyWidth()
    panel:Place()
    Panel.Layout()
    Panel.Refresh()
    Panel.RedockLeft()
end

-- Die linken Seitenteile (Taschenliste, Einkaufsliste) neu andocken: sie stehen außen am Markt, wenn kein Platz links ist.
function Panel.RedockLeft()
    if ns.Sell then ns.Sell.UpdatePanel() end
    if ns.Editor and ns.Editor.Place then ns.Editor.Place() end
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
    -- Reiter „Auktionen“: Zeile der Übersicht (SetItemKey), eigene Auktion (SelectAuction), Gebot
    local auctions = frame.AuctionsFrame
    if type(auctions) == "table" then
        if type(auctions.SetItemKey) == "function" then
            hooksecurefunc(auctions, "SetItemKey", function(_, itemKey) ns.Try("Market", Panel.SetAuctions, itemKey) end)
        end
        if type(auctions.SelectAuction) == "function" then
            hooksecurefunc(auctions, "SelectAuction", function(_, result)
                if type(result) == "table" then ns.Try("Market", Panel.SetAuctions, result.itemKey, result.buyoutAmount) end
            end)
        end
        if type(auctions.OnBidsListSearchResultSelected) == "function" then
            hooksecurefunc(auctions, "OnBidsListSearchResultSelected", function(_, bid)
                if type(bid) == "table" then ns.Try("Market", Panel.SetAuctions, bid.itemKey, bid.buyoutAmount) end
            end)
        end
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
