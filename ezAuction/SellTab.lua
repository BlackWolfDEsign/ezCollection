local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Reiter „Verkaufen“:
      - Taschenliste: alle Gegenstände der Tasche, die ins Auktionshaus dürfen, als angedockter Bereich neben
        Blizzards Fenster (Blizzard stellt das Auktionshaus an den linken Rand; „auto“ dockt links, wenn Platz
        ist, sonst rechts außen am Markt). Klick legt den Gegenstand in Blizzards Verkaufsbereich (AuctionHouseFrame:SetPostItem) –
        erst mit Tor T1 „geht“; bis dahin hebt er die Zeile hervor und nennt Blizzards Weg (Rechtsklick in der Tasche).
        Seit dem 21.11.2026 ein eigenes Seitenteil in voller Höhe links, der Markt steht rechts (Sell.PlacePanel).
      - Schalter „Nie unter dem Tief der erfassten Tage“ (floorTrend, ab Werk aus): hebt den Regelpreis auf das Tief
        aus Scan.Trend an, der Tooltip der Regel nennt den Grund.
      - Am Preisfeld: „Zuletzt: …“ (eigener letzter Preis) und „Regel: …“ (Menü: Blizzards Vorschlag, knapp
        unterbieten, x % unter Tiefstpreis, nie unter Händlerpreis). Die Regel greift von selbst, sobald Blizzard
        die aktuellen Angebote geladen hat, und nur, solange der Spieler den Preis nicht selbst geändert hat.
      - Menge und Dauer vom letzten Mal vorbelegen; gemerkt wird beim Einstellen (C_AuctionHouse.PostItem/PostCommodity).
    Einstellen bleibt Blizzards Knopf „Auktion erstellen“ (ein Tastendruck je Auktion).

    Welle 13 (Abschnitt „Einstellen: Vorschlag, Netto, Warnung, Nächster, Standardwerte“ unten):
      - „Nur vorschlagen, nichts eintragen“ (suggestOnly, AH-38): Preisregel und „Zuletzt“ schreiben nichts in Blizzards
        Felder, sondern zeigen „Vorschlag: …“ daneben
      - Netto-Zeile und Warnung bei Fehlpreis (AH-20), frei verankert unter Blizzards Einstellen-Knopf
      - „Als Nächstes“ (AH-18; golden in der Taschenliste – die Zeile „Nächster: …“ entfiel am 21.11.2026) und Standard-Menge, -Dauer und Startgebot (AH-19, Menü am Pfeil neben „Zuletzt“) –
        Tor T1 für den Verkaufsbereich hat kein Ergebnis (ns.T1): beides nur als Hinweis bzw. Vorschlag; mit „geht“
        legen sie über Blizzards SetPostItem, SetQuantity, SetDuration selbst ein
    Welle 15 (nur Anzeige, nie eine automatische Aktion):
      - Rückläufer (AH-28): was abgelaufen bzw. abgebrochen zurückkam und abgeholt ist (ezCores Auskunft „Auktionspost“,
        ns.History.Mail), steht oben mit „zurück“ und dem Vorschlag „zuletzt …, Regel …“; mit Tor T1 „geht“ zwei
        Knöpfe, die einlegen und den Preis setzen (Sell.PickReturn)
      - Erfolgsquote „4/6 verkauft“ in der Zeile, die ganze Verkaufsempfehlung im Tooltip (AH-29, ns.History.Advice)
      - Gesperrtes ausblenden (ezBags Schloss, nur gelesen) mit Umschalter neben dem Filter, Stern „oben halten“ je
        Zeile, Abschnitt „Bei anderen Charakteren verkaufbar“ (AH-30)
    Nie PostItem, PostCommodity oder ConfirmPost* rufen – nur zuhören (hooksecurefunc).
]]

local Sell = {}
ns.Sell = Sell

local panel
local state = setmetatable({}, { __mode = "k" })   -- [Verkaufsbereich] = { auto = true|nil, applied = Preis }
local priceButtons = setmetatable({}, { __mode = "k" })
local PANEL_WIDTH = ns.LEFT_PANEL_WIDTH   -- Wunschbreite wie alle Seitenteile (Core.lua; schmaler bei wenig Platz)
local LOOK = ns.LOOK                      -- Maße und Schriften der Listen wie ezTalent (ezCores Core.PANEL_LIST)
local ROW_HEIGHT = 30

local function SellFrames()
    local frame = AuctionHouseFrame
    return frame and frame.ItemSellFrame, frame and frame.CommoditiesSellFrame
end

-- Der gerade sichtbare Verkaufsbereich (Einzelstücke oder Waren).
function Sell.ActiveFrame()
    local items, goods = SellFrames()
    if goods and goods:IsShown() then return goods end
    if items and items:IsShown() then return items end
    return nil
end

local function ItemIDAt(location)
    if not location then return nil end
    if location.IsValid and not Core.Call(location.IsValid, location) then return nil end
    return Core.Call(C_Item.GetItemID, location)
end

---------------------------------------------------------------------------
-- Taschenliste
---------------------------------------------------------------------------

-- ezBags Urteil „Plunder“ je Taschenplatz (ezCore.API("ezBag").IsJunk(bag, slot)); nil, solange ezBag nicht läuft.
function Sell.JunkCheck()
    local api = Core.API("ezBag")
    local fn = type(api) == "table" and api.IsJunk
    return type(fn) == "function" and fn or nil
end

-- ezBags Schloss „nie verkaufen“ je Taschenplatz (ezCore.API("ezBag").IsLocked(bag, slot), AH-30) – nur gelesen, keine
-- zweite Liste; nil, solange ezBag nicht läuft (dann bleibt alles sichtbar).
function Sell.LockCheck()
    local api = Core.API("ezBag")
    local fn = type(api) == "table" and api.IsLocked
    return type(fn) == "function" and fn or nil
end

-- Stern „oben halten“ (AH-30): ezAuctions eigene Reihenfolge der Taschenliste, gespeichert je Gegenstand für das Konto
-- (ezAuctionDB.ui.sellPins = { [itemID] = true }). Kein Bezug zu Blizzards Favoriten.
local function Pins()
    local ui = ns.db and ns.db.ui
    if not ui then return {} end
    if type(ui.sellPins) ~= "table" then ui.sellPins = {} end
    return ui.sellPins
end

function Sell.IsPinned(itemID)
    itemID = Core.Num(itemID)
    return itemID ~= nil and ns.Enabled("sellPins") and Pins()[itemID] == true
end

function Sell.SetPinned(itemID, on)
    itemID = Core.Num(itemID)
    if not itemID then return false end
    Pins()[itemID] = on and true or nil
    Sell.Refresh()
    return true
end

-- Rang in der Taschenliste: mit Stern zuerst, dann zurückgekommene Gegenstände (AH-28), dann der Rest; Plunder (ezBag)
-- am Ende – außer er trägt den Stern (der Spieler will ihn ausdrücklich oben).
local function Rank(group)
    if group.pinned then return 0 end
    if group.junk then return 3 end
    if group.back then return 1 end
    return 2
end
Sell.Rank = Rank

-- Alle verkaufbaren Gegenstände der Tasche, zusammengefasst je Gegenstand (Ausrüstung je Gegenstandsstufe).
-- Was ezBag beim Händler verkaufen würde (Plunder, markierte Plätze), steht am Ende (group.junk). Seit Welle 15:
-- Gegenstände mit ezBags Schloss fehlen, solange „Gesperrtes ausblenden“ an ist (zweite Rückgabe: wie viele Zeilen
-- deshalb fehlen); group.pinned (Stern) und group.back (zurückgekommen, aus ezCores Auktionspost) ordnen nach Rank.
function Sell.Collect(filter)
    local groups, order = {}, {}
    filter = filter and Core.Trim(filter):lower() or ""
    local isJunk = Sell.JunkCheck()
    local isLocked = ns.Enabled("sellHideLocked") and Sell.LockCheck() or nil
    local hidden = {}
    local returned = ns.History and ns.History.Mail().returned or {}
    Core.ForEachBagItem(function(bag, slot, info)
        local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
        if not Core.Call(C_AuctionHouse.IsSellItemValid, location, false) then return end
        if isLocked and Core.Call(isLocked, bag, slot) == true then
            hidden[info.itemID] = true
            return
        end
        local junk = isJunk ~= nil and Core.Call(isJunk, bag, slot) == true
        local itemKey = Core.Call(C_AuctionHouse.GetItemKeyFromItem, location)
        local key = itemKey and ns.KeyString(itemKey) or tostring(info.itemID)
        local group = groups[key]
        if not group then
            local link = info.hyperlink
            local name = Core.ItemName(link) or Core.ItemNameByID(info.itemID)
            group = { key = key, itemID = info.itemID, name = name or ("#" .. info.itemID), link = link,
                icon = info.iconFileID, quality = info.quality or 1, count = 0, location = location,
                pinned = Sell.IsPinned(info.itemID), back = returned[info.itemID] }
            groups[key] = group
            order[#order + 1] = group
            group.junk = junk
        end
        -- Plunder ist eine Gruppe nur, wenn ezBag jeden ihrer Plätze verkaufen würde.
        group.junk = group.junk and junk
        group.count = group.count + (info.stackCount or 1)
    end, "sell")   -- Core.BagList("sell"): Taschen samt Reagenzientasche, ohne Schlüsselbund
    local result = {}
    for _, group in ipairs(order) do
        if filter == "" or group.name:lower():find(filter, 1, true) then result[#result + 1] = group end
    end
    table.sort(result, function(a, b)
        local ra, rb = Rank(a), Rank(b)
        if ra ~= rb then return ra < rb end
        if a.quality ~= b.quality then return a.quality > b.quality end
        return a.name < b.name
    end)
    local count = 0
    for _ in pairs(hidden) do count = count + 1 end
    Sell.hiddenLocked = count
    return result, count
end

---------------------------------------------------------------------------
-- Rückläufer (AH-28): Vorschläge „zum letzten Preis“ und „Regel neu“
---------------------------------------------------------------------------

-- Werte der beiden Vorschläge für einen zurückgekommenen Gegenstand: { last = Preis | nil, rule = Preis | nil }.
-- „Zum letzten Preis“: der eigene letzte Preis dieses Auktionshauses, sonst der aus ezCores Einstell-Verlauf.
-- „Regel neu“: die vorhandene Preisregel (bei „Blizzards Vorschlag“ knapp unterbieten) auf den zuletzt erfassten
-- Tiefstpreis – im Verkaufsbereich rechnet sie danach mit den geladenen Angeboten neu.
function Sell.ReturnSuggest(group)
    if type(group) ~= "table" or not group.itemID then return {} end
    local s = ns.S
    local last = ns.Enabled("rememberPost") and ns.LastPost(group.itemID)
    local out = { last = type(last) == "table" and Core.Num(last.price) or (type(group.back) == "table" and group.back.price) or nil }
    local info = ns.PriceInfo(group.itemID)
    out.rule = ns.RulePrice({ rule = s.priceRule ~= "blizzard" and s.priceRule or "undercut", percent = s.undercutPercent,
        lowest = info and Core.Num(info.min), market = info and Core.Num(info.market), vendor = Core.VendorPrice(group.itemID),
        floor = s.neverBelowVendor, trendLow = (Sell.TrendFloor(group.itemID)), step = ns.Step() })
    return out
end

-- „Vorschlag: zuletzt 1 G 20 S, Regel 1 G 10 S“ (die Anzeige-Fassung, solange Tor T1 nicht „geht“); nil ohne Wert.
function Sell.ReturnText(group)
    local s = Sell.ReturnSuggest(group)
    local parts = {}
    if s.last then parts[#parts + 1] = L.SELL_BACK_LAST:format(ns.Money(s.last)) end
    if s.rule then parts[#parts + 1] = L.SELL_BACK_RULE:format(ns.Money(s.rule)) end
    if #parts == 0 then return nil end
    return L.SUGGEST:format(table.concat(parts, ", "))
end

-- Die zwei Knöpfe der Fassung „geht“ stehen nur mit Tor T1 „geht“ und ohne „Nur vorschlagen“.
function Sell.ReturnButtons() return ns.SellSetsValues() and not Sell.Suggesting() end

-- Knopf „zum letzten Preis“ bzw. „Regel neu“ (Fassung „geht“): legt ein und setzt den Preis. how = "last" | "rule".
-- Rückgabe: true, wenn eingelegt und gesetzt; false in der Anzeige-Fassung oder ohne Wert.
function Sell.PickReturn(group, how)
    if not Sell.ReturnButtons() then return false end
    local price = Sell.ReturnSuggest(group)[how]
    if not price then return false end
    Sell.Pick(group)
    local frame = Sell.ActiveFrame()
    if not (frame and ItemIDAt(frame:GetItem()) == group.itemID) then return false end
    Sell.SetPriceFor(frame, price)
    local st = Sell.State(frame)
    -- „zum letzten Preis“ bleibt stehen; „Regel neu“ darf mit den geladenen Angeboten nachrechnen
    if st and how == "last" then st.auto = false end
    return true
end

-- Zweite Zeile in der Taschenliste: eigener letzter Preis, sonst Marktwert, sonst Händlerpreis.
local function BasePriceHint(group)
    local last = ns.Enabled("rememberPost") and ns.LastPost(group.itemID)
    if last then return L.SELL_LAST:format(ns.Money(last.price)) end
    local info = ns.PriceInfo(group.itemID)
    if info and info.market then return L.SELL_MARKET:format(ns.Money(info.market)) end
    local vendor = Core.VendorPrice(group.itemID)
    if vendor and vendor > 0 then return L.SELL_VENDOR:format(ns.Money(vendor)) end
    return ""
end

-- Seit Welle 15: zurückgekommen (AH-28) – Marke „zurück“ und die Vorschläge (in der Fassung „geht“ stehen sie als
-- Knöpfe daneben, dann nur die Marke); dazu die Erfolgsquote „4/6 verkauft“ (AH-29), sobald sie zählt.
local function PriceHint(group)
    local text
    if group.back then
        text = ns.Orange(L.SELL_BACK_MARK)   -- Marke „zurück“ in Blizzards Orange (Design-System 2.5; bis Welle 22 ff9933)
        local suggest = not Sell.ReturnButtons() and Sell.ReturnText(group)
        if suggest then text = text .. " " .. suggest end
        return text
    end
    text = BasePriceHint(group)
    local advice = Sell.CachedAdvice(group.itemID)
    if advice and advice.short then text = text ~= "" and (text .. " · " .. advice.short) or advice.short end
    return text
end
Sell.PriceHint = PriceHint

-- Alle bekannten Preise eines Gegenstands als Tooltip-Zeilen, mit Quelle der erfassten Preise. Ist gar kein Preis
-- bekannt, sagt eine Zeile, woher er käme – kein leerer Tooltip ohne Erklärung (Regel „Datenquellen“, 13.11.2026).
-- Rückgabe: Anzahl der Preiszeilen (0 = nur die Erklärung).
function Sell.AddPriceLines(itemID)
    local shown = 0
    local last = ns.Enabled("rememberPost") and ns.LastPost(itemID)
    if last then
        Core.TipDoubleLine(GameTooltip, L.PRICE_LAST_TITLE, ns.Money(last.price), "normal", "highlight")
        shown = shown + 1
    end
    local info = ns.PriceInfo(itemID)
    if info and (info.market or info.min) then shown = shown + 1 end
    if info and info.market then Core.TipDoubleLine(GameTooltip, L.TIP_MARKET, ns.Money(info.market), "normal", "highlight") end
    if info and info.min then Core.TipDoubleLine(GameTooltip, L.TIP_LOWEST, ns.Money(info.min), "normal", "highlight") end
    local low, high, days = ns.Scan.Trend(itemID)
    if low then
        Core.TipDoubleLine(GameTooltip, L.TIP_TREND:format(days), L.TIP_TREND_RANGE:format(ns.Money(low), ns.Money(high)),
            "normal", "highlight")
    end
    -- Verfügbarkeit (AUC-03): „Gesehen an 9 von 12 erfassten Tagen“, übliche Menge – aus ezCore.Prices.Stats
    for _, line in ipairs(ns.Market and ns.Market.Availability(itemID) or {}) do
        Core.TipLine(GameTooltip, line, "highlight", true)
    end
    local source = info and (info.market or info.min) and ns.Scan.SourceText(info)
    if source then Core.TipLine(GameTooltip, source, "hint", true) end
    local vendor = Core.VendorPrice(itemID)
    if vendor and vendor > 0 then
        Core.TipDoubleLine(GameTooltip, L.TIP_VENDOR, ns.Money(vendor), "normal", "highlight")
        shown = shown + 1
    end
    if shown == 0 then Core.TipLine(GameTooltip, L.SELL_NO_PRICE, "hint", true) end
    return shown
end
local AddPriceLines = Sell.AddPriceLines

local function BuildRow(row)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(24, 24)
    -- Formatierung wie ezTalents Listen (21.11.2026): Eintrag eingerückt, Name in LOOK.fonts.entry, eine Unterzeile in
    -- LOOK.fonts.sub
    row.icon:SetPoint("LEFT", row, "LEFT", LOOK.entryIndent, 0)
    row.count = row:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    row.count:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 1, 0)
    row.name = row:CreateFontString(nil, "OVERLAY", LOOK.fonts.entry)
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -1)
    row.name:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.name:SetJustifyH("LEFT")
    row.hint = row:CreateFontString(nil, "OVERLAY", LOOK.fonts.sub)
    row.hint:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 1)
    row.hint:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.hint:SetJustifyH("LEFT")
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    -- AH-18: die nächste Zeile („Als Nächstes“) golden hinterlegt – der eine Auswahl-Hintergrund aller Seitenteile
    -- (Gold mit LOOK.selectAlpha wie ezTalents gewählte Zeile; vorher 0,18)
    row.nextMark = row:CreateTexture(nil, "BACKGROUND")
    row.nextMark:SetAllPoints(row)
    row.nextMark:SetColorTexture(1, 0.82, 0, LOOK.selectAlpha)
    row.nextMark:Hide()
    -- AH-30: Stern „oben halten“ oben rechts (ezAuctions eigene Reihenfolge; Blizzards Zielmarke „Stern“, nicht
    -- Blizzards Favoriten-Stern des Auktionshauses – der Tooltip sagt es)
    row.pin = CreateFrame("Button", nil, row)
    row.pin:SetSize(Core.Style.BUTTON.small, Core.Style.BUTTON.small)   -- Design-System 2.3 (bis Welle 22 14)
    row.pin:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -2)
    row.pin.icon = row.pin:CreateTexture(nil, "ARTWORK")
    row.pin.icon:SetAllPoints(row.pin)
    row.pin.icon:SetTexture(Sell.PIN_TEXTURE)
    row.pin:SetScript("OnClick", function(self)
        local group = self:GetParent().group
        if group and group.itemID then Sell.SetPinned(group.itemID, not group.pinned) end
    end)
    row.pin:SetScript("OnEnter", function(self)
        local group = self:GetParent().group
        Core.ShowTip(self, L.SELL_PIN_TITLE, group and group.pinned and L.SELL_PIN_TIP_ON or L.SELL_PIN_TIP)
    end)
    row.pin:SetScript("OnLeave", GameTooltip_Hide)
    row.name:SetPoint("RIGHT", row.pin, "LEFT", -2, 0)
    -- AH-28, Fassung „geht“ (Tor T1): zwei Knöpfe rechts in der zweiten Zeile
    row.backLast = ns.TextButton(row)
    row.backRule = ns.TextButton(row)
    row.backRule:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 2)
    row.backLast:SetPoint("RIGHT", row.backRule, "LEFT", -6, 0)
    for _, part in ipairs({ { row.backLast, "last", "SELL_BACK_LAST_TIP" }, { row.backRule, "rule", "SELL_BACK_RULE_TIP" } }) do
        local button, how, tip = part[1], part[2], part[3]
        button:SetScript("OnClick", function(self) Sell.PickReturn(self:GetParent().group, how) end)
        button:SetScript("OnEnter", function(self) Core.ShowTip(self, self:GetText(), L[tip]) end)
        button:Hide()
    end
    row:SetScript("OnClick", function(self)
        if self.group and self.group.other then return Sell.OtherClick(self.group) end
        if self.group and not self.group.header then Sell.Pick(self.group) end
    end)
    row:SetScript("OnEnter", function(self)
        local group = self.group
        if not group or group.header then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(ns.ColoredName(group.name, group.quality))
        if group.other then return Sell.OtherTip(group) end
        AddPriceLines(group.itemID)
        -- AUC-19: „Entzaubern ≈ …“, nur wenn es mehr bringt als der Auktionspreis (der Link zählt mit seiner Stufe)
        local salvage = ns.Market and ns.Market.SalvageLines(group.link or group.itemID) or {}
        if salvage[1] then Core.TipLine(GameTooltip, salvage[1], "good", true) end
        if salvage[2] then Core.TipLine(GameTooltip, salvage[2], "hint", true) end
        Sell.AddRowLines(group)
        if group.junk then Core.TipLine(GameTooltip, L.SELL_JUNK_TIP, "hint", true) end
        if Sell.nextKey == group.key then Core.TipLine(GameTooltip, L.SELL_NEXT_ROW_TIP, "normal", true) end
        Core.TipLine(GameTooltip, ns.SellSetsValues() and L.SELL_ROW_TIP or L.SELL_ROW_TIP_T1, "blue", true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row.built = true
end

Sell.PIN_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"

-- Zeilen im Tooltip einer Zeile der Taschenliste (Welle 15): zurückgekommen mit den Vorschlägen (AH-28),
-- Verkaufsempfehlung (AH-29), Stern (AH-30). Rückgabe: Anzahl der Zeilen.
function Sell.AddRowLines(group)
    local n = 0
    -- Zeile in einer Rolle von Core.TipLine statt Farbzahlen (Gesamtreview 18.11.2026, T9-6)
    local function Add(text, role)
        Core.TipLine(GameTooltip, text, role, true)
        n = n + 1
    end
    local back = group.back
    if type(back) == "table" then
        local kind = L["SELL_BACK_KIND_" .. tostring(back.kind)] or tostring(back.kind)
        Add(L.SELL_BACK_TIP:format(kind, back.t and back.t > 0 and Core.Ago(back.t) or "?"), "orange")
        local suggest = Sell.ReturnText(group)
        if suggest then Add(suggest, "highlight") end
        Add(Sell.ReturnButtons() and L.SELL_BACK_SET_TIP or L.SELL_BACK_T1_TIP, "hint")
    end
    local advice = ns.History and ns.History.Advice(group.itemID)
    if advice and advice.lines[1] then
        Add(L.ADVICE_HEAD, "normal")
        for _, line in ipairs(advice.lines) do Add(line, "highlight") end
    end
    if group.pinned then Add(L.SELL_PIN_ROW_TIP, "hint") end
    return n
end

local function InitRow(row, group)
    if not row.built then BuildRow(row) end
    row.group = group
    if group.header then
        -- Überschrift des Abschnitts „Bei anderen Charakteren verkaufbar“ (AH-30)
        row.icon:SetTexture(nil)
        row.count:SetText("")
        row.name:SetText(Core.GOLD .. group.header .. "|r")
        row.hint:SetText(group.hint or "")
        row.nextMark:Hide()
        row.pin:Hide()
        row.backLast:Hide()
        row.backRule:Hide()
        return
    end
    row.icon:SetTexture(group.icon)
    row.count:SetText(group.count > 1 and group.count or "")
    row.name:SetText(group.junk and Core.Grey(group.name) or ns.ColoredName(group.name, group.quality))
    row.hint:SetText(group.other and (group.hint or "") or PriceHint(group))
    row.nextMark:SetShown(not group.other and Sell.nextKey ~= nil and Sell.nextKey == group.key)
    -- Stern: gold mit Stern, sonst blass
    local pins = not group.other and ns.Enabled("sellPins")
    row.pin:SetShown(pins == true)
    if pins then
        row.pin.icon:SetDesaturated(not group.pinned)
        row.pin.icon:SetAlpha(group.pinned and 1 or 0.35)
    end
    -- Rückläufer, Fassung „geht“: zwei Knöpfe; die zweite Zeile endet davor
    local s = not group.other and group.back and Sell.ReturnButtons() and Sell.ReturnSuggest(group) or nil
    row.backLast:SetShown(s ~= nil and s.last ~= nil)
    row.backRule:SetShown(s ~= nil and s.rule ~= nil)
    if s and s.last then row.backLast:SetLabel(L.SELL_BACK_LAST_BUTTON:format(ns.Money(s.last))) end
    if s and s.rule then row.backRule:SetLabel(L.SELL_BACK_RULE_BUTTON:format(ns.Money(s.rule))) end
end
Sell.InitRow = InitRow

---------------------------------------------------------------------------
-- AH-30: Abschnitt „Bei anderen Charakteren verkaufbar“ (Schalter sellOtherChars, ab Werk aus) – nur Anzeige
---------------------------------------------------------------------------
-- Aus ezCores Bestand je Charakter (Core.Chars: Taschen, Bank, Post; nicht Angelegtes): Gegenstände, die das eigene
-- Preis-Wissen im Auktionshaus gesehen hat (also handelbar sind), am meisten wert zuerst, höchstens Sell.OTHER_MAX.
-- Rückgabe: { { other = true, itemID, name, quality, icon, count, value, where = { { key, c, loc, n } … }, hint } … }
-- filter: derselbe Suchtext wie in Sell.Collect (Teil des Namens); er wirkt vor der Preisabfrage, damit ein Tastendruck
-- im Filter nicht für jeden fremden Gegenstand das Preis-Wissen fragt.
-- Nur Twinks am selben Auktionshaus (ezCore.SameHouse: gleicher Realm und gleiche Fraktion; Gesamtreview 18.11.2026,
-- T4-NR5) – der Wert stammt aus dem Preis-Wissen dieses Hauses, für Twinks anderer Häuser gälte er nicht.
Sell.OTHER_MAX = 30
Sell.OTHER_LOCATIONS = { "bags", "bank", "mail" }

-- prices (freiwillig): Zwischenspeicher der Preise je Gegenstand für einen Aufbau (Sell.Refresh, T8-10)
local function PriceOf(itemID, prices)
    if not prices then return ns.PriceInfo(itemID) end
    local info = prices[itemID]
    if info == nil then
        info = ns.PriceInfo(itemID) or false
        prices[itemID] = info
    end
    return info or nil
end

function Sell.OtherChars(filter, prices)
    if not ns.Enabled("sellOtherChars") or type(Core.Chars) ~= "function" then return {} end
    filter = filter and Core.Trim(filter):lower() or ""
    local byItem, list = {}, {}
    for key, c in pairs(Core.Chars()) do
        if type(c) == "table" and key ~= Core.charKey and Core.SameHouse(key) then
            for _, loc in ipairs(Sell.OTHER_LOCATIONS) do
                for itemID, n in pairs(type(c[loc]) == "table" and c[loc] or {}) do
                    n = Core.Num(n) or 0
                    itemID = Core.Num(itemID)
                    if itemID and n > 0 then
                        local entry = byItem[itemID]
                        if entry == nil and filter ~= "" then
                            local name = Core.ItemNameByID(itemID) or ("#" .. itemID)
                            if not name:lower():find(filter, 1, true) then entry, byItem[itemID] = false, false end
                        end
                        if entry == nil then
                            local info = PriceOf(itemID, prices)
                            local price = info and (Core.Num(info.market) or Core.Num(info.min))
                            entry = price and { other = true, itemID = itemID, price = price, count = 0, where = {} } or false
                            byItem[itemID] = entry
                            if entry then list[#list + 1] = entry end
                        end
                        if entry then
                            entry.count = entry.count + n
                            entry.where[#entry.where + 1] = { key = key, c = c, loc = loc, n = n }
                        end
                    end
                end
            end
        end
    end
    for _, entry in ipairs(list) do
        entry.value = entry.price * entry.count
        entry.name = Core.ItemNameByID(entry.itemID) or ("#" .. entry.itemID)
        entry.quality = Core.Num(Core.Call(C_Item.GetItemQualityByID, entry.itemID)) or 1
        entry.icon = Core.Call(C_Item.GetItemIconByID, entry.itemID)
        entry.key = "other:" .. entry.itemID
        table.sort(entry.where, function(a, b)
            if a.n ~= b.n then return a.n > b.n end
            return tostring(a.key) < tostring(b.key)
        end)
        local first = entry.where[1]
        entry.hint = L.SELL_OTHER_HINT:format(entry.count, Core.CharName(first.c, first.key, nil, true),
            L["SELL_OTHER_LOC_" .. first.loc])
    end
    table.sort(list, function(a, b)
        if a.value ~= b.value then return a.value > b.value end
        return a.name < b.name
    end)
    while #list > Sell.OTHER_MAX do table.remove(list) end
    return list
end

-- Tooltip einer Zeile des Abschnitts: wo es liegt (je Charakter und Ort), Wert und Quelle; Klick tut nichts.
function Sell.OtherTip(entry)
    for _, w in ipairs(entry.where) do
        Core.TipDoubleLine(GameTooltip, Core.CharName(w.c, w.key), L.SELL_OTHER_WHERE:format(w.n, L["SELL_OTHER_LOC_" .. w.loc]),
            "highlight", "highlight")
    end
    Core.TipDoubleLine(GameTooltip, L.SELL_OTHER_VALUE, ns.Money(entry.value), "normal", "highlight")
    local source = ns.Scan.SourceText(ns.PriceInfo(entry.itemID))
    if source then Core.TipLine(GameTooltip, source, "hint", true) end
    Core.TipLine(GameTooltip, L.SELL_OTHER_TIP, "blue", true)
    GameTooltip:Show()
end

function Sell.OtherClick(entry)
    local first = entry and entry.where and entry.where[1]
    if first then ns.Print(L.SELL_OTHER_CLICK:format(entry.name, Core.CharName(first.c, first.key, nil, true))) end
    return false
end

-- Klick in der Taschenliste: in Blizzards Verkaufsbereich legen (dort stellt der Spieler selbst ein).
-- Dasselbe Tor wie SellFromBag und postNext (Prüfung auf Blizzards Regeln vom 17.11.2026, Risiko 18): solange Tor T1
-- für den Verkaufsbereich nicht „geht“ meldet, ruft ezAuction SetPostItem nicht – die Zeile wird hervorgehoben, und der
-- Hinweis nennt Blizzards eigenen Weg (Rechtsklick auf den Gegenstand in der Tasche, ContainerFrameItemButton_OnClick).
-- Rückgabe: true, wenn eingelegt.
function Sell.Pick(group)
    if not (group and AuctionHouseFrame and AuctionHouseFrame.SetPostItem) then return false end
    local location = group.location
    if not (location and Core.Call(location.IsValid, location)) or ItemIDAt(location) ~= group.itemID then
        Sell.Refresh()
        return false
    end
    if not ns.SellSetsValues() then
        Sell.askedKey = group.key
        Sell.Refresh()
        ns.Print(L.SELL_PICK_T1:format(ns.ColoredName(group.name, group.quality)))
        return false
    end
    AuctionHouseFrame:SetPostItem(location)
    return true
end

-- Zwischenspeicher je Aufbau (Gesamtreview 18.11.2026, T8-10; vorher rechnete jeder Tastendruck im Filter die Taschen,
-- je Zeile den Einstell-Verlauf und die Bestände aller Charaktere samt Preisen neu): built = { groups = alle Zeilen
-- ohne Filter (Sell.Collect), hidden, advice = { [itemID] = Rat | false }, prices = { [itemID] = Preis | false } }.
-- Ein Aufbau entsteht bei jedem Sell.Refresh() (Taschen, Preise, Öffnen); der Filter ruft Sell.Refresh(true) und
-- filtert nur die fertige Liste. Sell.Invalidate() verwirft ihn.
local built
function Sell.Invalidate() built = nil end
function Sell.Built() return built end

-- Rat aus dem Einstell-Verlauf (History.Advice, eine Runde über bis zu 1000 Einträge) je Gegenstand einmal je Aufbau
function Sell.CachedAdvice(itemID)
    if not ns.History then return nil end
    if not built then return ns.History.Advice(itemID, nil, true) end
    local advice = built.advice[itemID]
    if advice == nil then
        advice = ns.History.Advice(itemID, nil, true) or false
        built.advice[itemID] = advice
    end
    return advice or nil
end

-- Zeilen, deren Name den Filter enthält (dieselbe Regel wie in Sell.Collect), Reihenfolge bleibt
local function FilterGroups(list, filter)
    filter = filter and Core.Trim(filter):lower() or ""
    if filter == "" then
        local out = {}
        for i, group in ipairs(list) do out[i] = group end
        return out
    end
    local out = {}
    for _, group in ipairs(list) do
        if group.name:lower():find(filter, 1, true) then out[#out + 1] = group end
    end
    return out
end
Sell.FilterGroups = FilterGroups

-- Mit offener Liste rechnet auch „Als Nächstes“ (Sell.UpdateNext) mit der gefilterten fertigen Liste – dieselben Zeilen
-- wie Sell.Collect(filter); vorher sammelte UpdateNext bei jedem Tastendruck die Taschen doch wieder neu (Gegenprüfung
-- P19a zu T8-10). Ohne offene Liste wie vorher: UpdateNext sammelt selbst.
function Sell.Refresh(filterOnly)
    local open = panel and panel:IsShown()
    local text, groups
    if open then
        text = panel.filter and panel.filter:GetText()
        if filterOnly ~= true or not built then
            local all, hidden = Sell.Collect(nil)
            built = { groups = all, hidden = hidden, advice = {}, prices = {} }
        end
        groups = FilterGroups(built.groups, text)
    end
    Sell.UpdateNext(groups)
    local frame = Sell.ActiveFrame()
    if frame then Sell.UpdateExtras(frame) end
    if not open then return end
    Sell.hiddenLocked = built.hidden
    -- AH-30: Abschnitt „Bei anderen Charakteren verkaufbar“ darunter (nur Anzeige, Schalter ab Werk aus)
    local others = Sell.OtherChars(text, built.prices)
    if others[1] then
        groups[#groups + 1] = { header = L.SELL_OTHER_HEAD, hint = Core.Grey(L.SELL_OTHER_HEAD_HINT), key = "other:head" }
        for _, entry in ipairs(others) do groups[#groups + 1] = entry end
    end
    panel.list:SetData(groups)
    -- Leertext nur bei ganz leerer Liste: er sitzt auf der ersten Zeile und läge sonst über der Überschrift des Abschnitts
    panel.empty:SetShown(#groups == 0)
    Sell.UpdateLockToggle()
end

-- Umschalter „Gesperrtes zeigen“ (AH-30) neben dem Filter: nur mit ezBag; der Tooltip nennt, wie viele Zeilen gerade
-- fehlen. Klick schaltet sellHideLocked um.
function Sell.UpdateLockToggle()
    local button = panel and panel.lockToggle
    if not button then return end
    local has = Sell.LockCheck() ~= nil
    button:SetShown(has)
    if not has then return end
    local hiding = ns.Enabled("sellHideLocked")
    button.icon:SetDesaturated(not hiding)
    button.icon:SetAlpha(hiding and 1 or 0.5)
end

function Sell.LockToggleTip()
    if not ns.Enabled("sellHideLocked") then return L.SELL_LOCK_TIP_SHOWING end
    return Core.Plural(Sell.hiddenLocked or 0, L.SELL_LOCK_TIP_ONE, L.SELL_LOCK_TIP_MANY)
end

function Sell.LockToggleButton()
    local button = panel and panel.lockToggle
    return button ~= nil and button:IsVisible() and button or nil
end

-- Seite der Taschenliste: wie alle Seitenteile links (ns.LeftPanelSide in Core.lua).
function Sell.Side()
    return ns.LeftPanelSide(panel, PANEL_WIDTH)
end

local function BuildPanel()
    local ok, f = pcall(CreateFrame, "Frame", "ezAuctionSellList", AuctionHouseFrame, "ButtonFrameTemplate")
    if not ok or not f then f = CreateFrame("Frame", "ezAuctionSellList", AuctionHouseFrame) end
    panel = f
    f:SetWidth(PANEL_WIDTH)
    f:Hide()
    -- Blizzards Fensterrahmen wie der Markt (ns.PanelLook), ohne eigenes „X“: ein- und ausblenden über den Knopf
    -- „Taschenliste“ oben rechts im Reiter (Entscheidung vom 21.11.2026, „ohne Titel-X“)
    ns.PanelLook(f, L.SELL_LIST_TITLE)
    local ok2, filter = pcall(CreateFrame, "EditBox", "ezAuctionSellListFilter", f, "SearchBoxTemplate")
    if not ok2 or not filter then filter = CreateFrame("EditBox", "ezAuctionSellListFilter", f, "InputBoxTemplate") end
    -- Kopf wie ezTalent ab ns.PANEL_TOP, LOOK.headLeft vom Rand (Blizzards Suchfeld zeichnet 4 links vor seinem Feld);
    -- rechts Platz für das Schloss – die Breite folgt dem Seitenteil
    -- beide Anker oben (wie ezTalent, Befund des Reviews: „RIGHT“ am Seitenteil legte die Mitte des Felds auf dessen
    -- Mitte – der Kasten darunter hätte erst in der unteren Hälfte begonnen)
    filter:SetHeight(20)
    filter:SetPoint("TOPLEFT", f, "TOPLEFT", LOOK.headLeft + 4, -ns.PANEL_TOP)
    filter:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(LOOK.headLeft + Core.Style.BUTTON.small + 4), -ns.PANEL_TOP)
    filter:SetAutoFocus(false)
    -- nur die fertige Liste filtern (Zwischenspeicher je Aufbau, T8-10)
    filter:HookScript("OnTextChanged", function() Sell.Refresh(true) end)
    if filter.Instructions then filter.Instructions:SetText(L.SELL_FILTER) end
    -- neben Auctionator: wohin die Liste gehört (Beside.SellListLine; vorher am Knopf „Taschenliste“)
    filter:HookScript("OnEnter", function(self)
        local line = ns.Beside.SellListLine()
        Core.ShowTip(self, L.SELL_FILTER, line and (L.SELL_FILTER_TIP .. "\n\n" .. line) or L.SELL_FILTER_TIP)
    end)
    filter:HookScript("OnLeave", GameTooltip_Hide)
    f.filter = filter
    -- AH-30: Umschalter „Gesperrtes zeigen“ rechts neben dem Filter (Schloss; nur mit ezBag zu sehen)
    local lock = CreateFrame("Button", nil, f)
    lock:SetSize(Core.Style.BUTTON.small, Core.Style.BUTTON.small)   -- Design-System 2.3 (bis Welle 22 18)
    lock:SetPoint("LEFT", filter, "RIGHT", 4, 0)
    lock.icon = lock:CreateTexture(nil, "ARTWORK")
    lock.icon:SetAllPoints(lock)
    lock.icon:SetTexture("Interface\\PetBattles\\PetBattle-LockIcon")
    lock:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    lock:SetScript("OnClick", function() ns.SetSetting("sellHideLocked", not ns.Enabled("sellHideLocked")) end)
    lock:SetScript("OnEnter", function(self) Core.ShowTip(self, L.SELL_LOCK_TITLE, Sell.LockToggleTip()) end)
    lock:SetScript("OnLeave", GameTooltip_Hide)
    lock:Hide()
    f.lockToggle = lock

    -- die Liste in Blizzards innerem Kasten zwischen Kopf und Unterkante (wie ezTalent; ohne Kasten im Client wie vorher)
    f.list = ns.NewScrollList(f, ROW_HEIGHT, InitRow, LOOK.entryGap)
    f.inset = ns.PanelInset(f, filter, LOOK.headLeft + 4, ns.BUTTON_Y)
    if f.inset then f.list:SetInside(f.inset) else f.list:SetPoints(10, -58, -8, 10) end
    f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    if f.inset then
        f.empty:SetPoint("TOPLEFT", f.inset, "TOPLEFT", LOOK.insetLeft + LOOK.entryIndent, -(LOOK.insetTop + 6))
        f.empty:SetPoint("TOPRIGHT", f.inset, "TOPRIGHT", -LOOK.insetLeft, -(LOOK.insetTop + 6))
    else
        f.empty:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -70)
        f.empty:SetPoint("RIGHT", f, "RIGHT", -16, 0)
    end
    f.empty:SetText(L.SELL_LIST_EMPTY)
    f:SetScript("OnShow", function() Sell.Refresh() end)
end

-- „Aus der Tasche“ steht beim Verkaufen immer (zweiter Spieltest vom 21.11.2026: „der Taschenliste button kann auch weg
-- wen sich aus der tasche immer automatisch öffnet bzw immer angezeigt wird beim verkaufen wie markt fenster“) – der
-- Knopf „Taschenliste“ zum Ein- und Ausblenden entfiel; abschalten geht über den Schalter sellList. Das Seitenteil,
-- solange zu sehen (Ziel des Rundgangs).
function Sell.PanelFrame()
    return panel ~= nil and panel:IsVisible() and panel or nil
end

-- Regel am Preisfeld, solange zu sehen (Ziel des Rundgangs).
function Sell.RuleButton()
    for _, parts in pairs(priceButtons) do
        if parts.rule:IsVisible() then return parts.rule end
    end
    return nil
end

-- Wo die Taschenliste sitzt: als eigenes Seitenteil in voller Höhe, angedockt wie alle Seitenteile links
-- (ns.PlaceLeftPanel in Core.lua). Rückgabe: Seite.
function Sell.PlacePanel()
    return ns.PlaceLeftPanel(panel, PANEL_WIDTH)
end

-- Seite, an der die Taschenliste zuletzt angedockt hat (nach der Platzprüfung; Sell.Side ist der Wunsch), oder nil.
function Sell.DockedSide()
    return panel ~= nil and panel.dockSide or nil
end

-- Taschenliste zu sehen? Und ihre Breite.
function Sell.Docked() return panel ~= nil and panel:IsShown() end
function Sell.PanelWidth() return panel and panel.fitWidth or PANEL_WIDTH end   -- nach dem Platz (ns.PlaceLeftPanel)

function Sell.UpdatePanel()
    local inSell = ns.ModeName() == "sell" and ns.AuctionHouseShown()
    local wanted = inSell and ns.Enabled("sellList")
    if not wanted then
        if panel then panel:Hide() end
    else
        if not panel then BuildPanel() end
        panel:Show()
        Sell.PlacePanel()
        Sell.Refresh()
    end
    -- der Pfeil des zugeklappten Seitenteils weicht der angedockten Liste aus (und kehrt zurück, wenn sie geht)
    if ns.MarketPanel then ns.MarketPanel.PlaceArrow() end
end

---------------------------------------------------------------------------
-- Preisfeld: Regel und letzter Preis
---------------------------------------------------------------------------

-- Günstigstes Angebot aus Blizzards geladenen Angeboten: Preis (je Stück bzw. je Auktion), eigenes?
function Sell.Lowest(frame)
    local location = frame and frame:GetItem()
    local itemID = ItemIDAt(location)
    if not itemID then return nil end
    local _, goods = SellFrames()
    if frame == goods then
        local count = Core.Call(C_AuctionHouse.GetNumCommoditySearchResults, itemID) or 0
        for index = 1, count do
            local result = Core.Call(C_AuctionHouse.GetCommoditySearchResultInfo, itemID, index)
            if result and result.unitPrice then
                local mine = (result.numOwnerItems or 0) >= (result.quantity or 0) and (result.quantity or 0) > 0
                if not mine then return result.unitPrice, false end
                if index == 1 then return result.unitPrice, true end
            end
        end
        return nil
    end
    -- Einzelstücke: Blizzards eigene Wahl des günstigsten passenden Angebots (gleiche Gegenstandsstufe).
    local best = frame.GetBestEntry and Core.Call(frame.GetBestEntry, frame)
    if type(best) == "table" and type(best.buyoutAmount) == "number" and best.buyoutAmount > 0 then
        return best.buyoutAmount, best.containsOwnerItem == true
    end
    return nil
end

-- Untergrenze „Nie unter dem Tief der erfassten Tage“ (Schalter floorTrend, AUC-13): Tief und Zahl der Tage aus
-- Scan.Trend (ezCore.Prices.History, 14 Kalendertage); nil, solange der Schalter aus ist oder es keinen Verlauf
-- über mindestens zwei Tage gibt.
function Sell.TrendFloor(itemID)
    if not (ns.S.floorTrend and itemID) then return nil end
    local low, _, days = ns.Scan.Trend(itemID)
    return low, days
end

-- Preis nach der Regel; zweite Rückgabe "trend", wenn das Tief der erfassten Tage ihn angehoben hat.
function Sell.RulePriceFor(frame, rule)
    local itemID = ItemIDAt(frame:GetItem())
    if not itemID then return nil end
    local s = ns.S
    local lowest, mine = Sell.Lowest(frame)
    local last = s.rememberPost and ns.LastPost(itemID)
    local info = ns.PriceInfo(itemID)
    return ns.RulePrice({ rule = rule or s.priceRule, percent = s.undercutPercent, lowest = lowest, mineIsLowest = mine,
        last = last and last.price, market = info and info.market, vendor = Core.VendorPrice(itemID),
        floor = s.neverBelowVendor, trendLow = (Sell.TrendFloor(itemID)), step = ns.Step() })
end

-- Tooltip der Regel am Preisfeld: was sie tut, der Preis jetzt (mit Grund, wenn das Tief ihn angehoben hat), Tief
-- bis Hoch, der Hinweis gegen den Median und die Quelle der erfassten Preise (Leitlinie 11, AUC-01, AUC-04).
function Sell.RuleTip(frame)
    local itemID = ItemIDAt(frame:GetItem())
    local price, raised = Sell.RulePriceFor(frame, ns.S.priceRule ~= "blizzard" and ns.S.priceRule or "undercut")
    local body = L.PRICE_RULE_TIP
    if price then body = body .. "\n" .. L.PRICE_RULE_NOW:format(ns.Money(price)) end
    local low, high, days = ns.Scan.Trend(itemID)
    if raised == "trend" then body = body .. "\n" .. L.PRICE_RULE_RAISED:format(days or 0) end
    local note = ns.S.neverBelowVendor and itemID and (Core.VendorPrice(itemID) or 0) > 0 and Core.Prices.FeeNote()
    if note then body = body .. "\n" .. L.PRICE_RULE_FLOOR:format(note) end
    if low then
        body = body .. "\n" .. L.TIP_TREND:format(days) .. ": " .. L.TIP_TREND_RANGE:format(ns.Money(low), ns.Money(high))
    end
    local Market = ns.Market
    local lowest = Sell.Lowest(frame)
    -- Abwandlung (Zufallssuffix): ihr Median mischt verschiedene Preise, also kein Urteil (wie im Seitenteil)
    local variant = Market and itemID and Market.HasVariant(Core.Call(C_AuctionHouse.GetItemKeyFromItem, frame:GetItem()))
    local judgement = Market and lowest and Market.Judge(itemID, lowest, variant)
    if judgement then body = body .. "\n" .. Market.JudgeText(judgement) end
    local advice = Market and lowest and Market.SellAdvice(itemID, lowest, nil, variant)
    if advice then body = body .. "\n" .. advice.text end
    local info = ns.PriceInfo(itemID)
    local source = info and (info.market or info.min) and ns.Scan.SourceText(info)
    if source then body = body .. "\n" .. source end
    return body
end

-- Trägt den Preis ein. Läuft im Hook auf Blizzards UpdatePriceSelection: Meldet sich das Preisfeld beim Setzen
-- zurück (und Blizzard wählt daraufhin erneut), darf das keinen zweiten Durchlauf auslösen – darum die Sperre,
-- und gesetzt wird nur, wenn sich der Betrag ändert (Vollprüfung V-155).
local applying = false
local function WritePrice(frame, price)
    frame.PriceInput:SetAmount(price)
    if frame.UpdatePostState then frame:UpdatePostState() end
end

-- „Nur vorschlagen, nichts eintragen“ (AH-38): dann bleibt Blizzards Feld, wie es ist, und „Vorschlag: …“ steht daneben.
-- Ebenso, solange Tor T1 für den Verkaufsbereich nicht „geht“ meldet (Prüfung auf Blizzards Regeln vom 17.11.2026,
-- Risiko 15): Preisregel, „Zuletzt“, Menge und Dauer schreiben erst nach dem Spieltest in Blizzards Felder.
local function Suggesting() return ns.Enabled("suggestOnly") or not ns.SellSetsValues() end
Sell.Suggesting = Suggesting

local function SetPrice(frame, price)
    if applying or not (price and frame.PriceInput) then return end
    local st = state[frame] or {}
    state[frame] = st
    if Suggesting() then
        st.suggestPrice = price
        if Sell.UpdateExtras then Sell.UpdateExtras(frame) end
        return
    end
    st.applied = price
    if frame.PriceInput:GetAmount() == price then return end
    applying = true
    ns.Try("SetPrice", WritePrice, frame, price)
    applying = false
end

function Sell.IsApplying() return applying end
Sell.SetPriceFor = SetPrice   -- für die Knöpfe der Rückläufer (AH-28, Fassung „geht“)

function Sell.ApplyRule(frame)
    local rule = ns.S.priceRule
    if rule == "blizzard" then return false end
    local price = Sell.RulePriceFor(frame, rule)
    if not price then return false end
    SetPrice(frame, price)
    return true
end

function Sell.ApplyLast(frame)
    local last = ns.LastPost(ItemIDAt(frame:GetItem()))
    if last then SetPrice(frame, last.price) end
end

-- Stand eines Verkaufsbereichs (für die Vorschläge in Sell.UpdateExtras und für Prüfungen).
function Sell.State(frame) return state[frame] end

-- Hat der Spieler den Preis selbst geändert (getippt oder ein Angebot angeklickt)? Dann greift die Regel
-- nicht mehr von selbst. Vor der ersten Regel gilt Blizzards eigene Wahl (Standard bzw. günstigstes Angebot)
-- als unberührt, danach nur noch der von ezAuction eingetragene Preis.
local function Untouched(frame)
    local st = state[frame]
    if not st or st.auto == false then return false end
    local amount = frame.PriceInput and frame.PriceInput:GetAmount()
    if amount == nil or amount == 0 then return true end
    if st.applied then return amount == st.applied end
    if frame.GetDefaultPrice and amount == Core.Call(frame.GetDefaultPrice, frame) then return true end
    if frame.GetSearchResultPrice and amount == Core.Call(frame.GetSearchResultPrice, frame) then return true end
    return false
end

-- Hat Blizzard die Angebote dieses Gegenstands vollständig geladen (auch: es gibt keine)?
function Sell.OffersLoaded(frame)
    local location = frame:GetItem()
    local itemID = ItemIDAt(location)
    if not itemID then return false end
    local _, goods = SellFrames()
    if frame == goods then
        return Core.Call(C_AuctionHouse.HasFullCommoditySearchResults, itemID) == true
    end
    local itemKey = Core.Call(C_AuctionHouse.GetItemKeyFromItem, location)
    return itemKey ~= nil and Core.Call(C_AuctionHouse.HasFullItemSearchResults, itemKey) == true
end

-- Nach Blizzards eigener Preiswahl (Angebote geladen oder aufgefrischt): Regel anwenden, solange der
-- Spieler den Preis nicht selbst geändert hat – so zählt auch ein frischeres Angebot nach dem Zwischenspeicher.
function Sell.AfterPriceSelection(frame)
    if applying then return end
    local st = state[frame]
    if st and frame:GetItem() and Untouched(frame) and (Sell.Lowest(frame) or Sell.OffersLoaded(frame)) then
        Sell.ApplyRule(frame)
    end
    Sell.UpdatePriceButtons(frame)
end

local RULES = { "blizzard", "undercut", "percent" }

local function RuleLabel(rule)
    if rule == "percent" then return L.RULE_percent:format(ns.S.undercutPercent) end
    return L["RULE_" .. rule] or rule
end

local function RuleMenu(owner, frame)
    local function Set(key, value)
        ns.SetSetting(key, value)
        Sell.ApplyRule(frame)
        Sell.UpdatePriceButtons(frame)
    end
    local Menu = Core.Menu
    local opened = Menu.Open(owner, function(root)
        Menu.Title(root, L.RULE_MENU_TITLE)
        for _, rule in ipairs(RULES) do
            Menu.Radio(root, RuleLabel(rule), function() return ns.S.priceRule end,
                function(value) Set("priceRule", value) end, rule)
        end
        Menu.Toggle(root, L.OPT_neverBelowVendor, function() return ns.S.neverBelowVendor end,
            function(value) Set("neverBelowVendor", value) end)
        Menu.Toggle(root, L.OPT_floorTrend, function() return ns.S.floorTrend end,
            function(value) Set("floorTrend", value) end)
        Menu.Divider(root)
        Menu.Settings(root, ns)   -- „Einstellungen …“ aus ezCore (T18-8)
    end)
    if opened then return end
    -- Ohne Menü: Regel weiterschalten und anwenden.
    local index = 1
    for i, rule in ipairs(RULES) do if rule == ns.S.priceRule then index = i end end
    Set("priceRule", RULES[index % #RULES + 1])
end

local function DurationText(duration)
    local word = ({ "ONE", "TWO", "THREE" })[duration or 0]
    return word and _G["AUCTION_DURATION_" .. word] or "?"
end

-- Tooltip von „Zuletzt“: der letzte Preis mit Zeit, Menge und Dauer, darunter die Preise davor (AUC-20, VP-75 –
-- die letzten ns.POST_PRICES Einstellpreise, aus den eigenen Verkäufen dieses Auktionshauses). nil ohne Preis.
function Sell.LastTip(itemID)
    local posts = ns.PostPrices(itemID)
    local last = posts[1]
    if not last then return nil end
    local lines = { L.PRICE_LAST_TIP:format(Core.Ago(last.time), last.qty or 1, DurationText(last.duration)) }
    if posts[2] then
        lines[#lines + 1] = L.PRICE_EARLIER_HEAD
        for i = 2, #posts do
            local post = posts[i]
            lines[#lines + 1] = L.PRICE_EARLIER:format(ns.Money(post.price), Core.Ago(post.time), post.qty or 1)
        end
    end
    return table.concat(lines, "\n")
end

local function BuildPriceButtons(frame)
    local input = frame.PriceInput
    if not input then return nil end
    local anchor = input.MoneyInputFrame or input
    local parts = {}
    parts.last = ns.TextButton(input)
    parts.last:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 2, 3)
    parts.last:SetScript("OnClick", function() Sell.ApplyLast(frame) end)
    parts.last:SetScript("OnEnter", function(self)
        local body = Sell.LastTip(ItemIDAt(frame:GetItem()))
        if body then Core.ShowTip(self, L.PRICE_LAST_TITLE, body) end
    end)
    parts.rule = ns.TextButton(input)
    parts.rule:SetScript("OnClick", function(self) RuleMenu(self, frame) end)
    parts.rule:SetScript("OnEnter", function(self) Core.ShowTip(self, L.PRICE_RULE_TITLE, Sell.RuleTip(frame)) end)
    priceButtons[frame] = parts
    return parts
end

function Sell.UpdatePriceButtons(frame)
    if not frame then return end
    local parts = priceButtons[frame] or BuildPriceButtons(frame)
    if not parts then return end
    local itemID = ItemIDAt(frame:GetItem())
    local last = itemID and ns.Enabled("rememberPost") and ns.LastPost(itemID)
    parts.last:SetShown(last ~= nil and last ~= false)
    if last then parts.last:SetLabel(L.PRICE_LAST_BUTTON:format(ns.Money(last.price))) end
    -- Pfeil an „Zuletzt“ (AH-19: Standardwerte, Startgebot) – steht auch ohne gemerkten Preis an dessen Platz
    local x = Sell.Extras(frame)
    local menu = x and itemID ~= nil and ns.Enabled("postDefaults") and x.menu or nil
    if x then
        x.menu:ClearAllPoints()
        if last then
            x.menu:SetPoint("LEFT", parts.last, "RIGHT", 2, 0)
        else
            x.menu:SetPoint("TOPLEFT", parts.last, "TOPLEFT", 0, 0)
        end
        x.menu:SetShown(menu ~= nil)
    end
    parts.rule:ClearAllPoints()
    if menu then
        parts.rule:SetPoint("LEFT", menu, "RIGHT", 8, 0)
    elseif last then
        parts.rule:SetPoint("LEFT", parts.last, "RIGHT", 10, 0)
    else
        parts.rule:SetPoint("TOPLEFT", parts.last, "TOPLEFT", 0, 0)
    end
    parts.rule:SetLabel(L.PRICE_RULE_BUTTON:format(RuleLabel(ns.S.priceRule)))
    parts.rule:SetShown(itemID ~= nil)
    Sell.UpdateExtras(frame)
end

-- Neuer Gegenstand im Verkaufsbereich: Menge und Dauer vom letzten Mal, Regel wieder scharf.
-- Dauer bzw. Menge in Blizzards Feld setzen (über Blizzards eigene SetDuration bzw. SetQuantity des Feldes).
local function WriteDuration(frame, duration)
    if duration and frame.Duration and frame.Duration.SetDuration and frame.Duration:GetDuration() ~= duration then
        frame.Duration:SetDuration(duration)
    end
end

local function WriteQuantity(frame, qty)
    local quantity = frame.QuantityInput
    if qty and quantity and quantity:IsShown() and frame.GetMaxQuantity then
        local maximum = Core.Call(frame.GetMaxQuantity, frame) or qty
        quantity:SetQuantity(math.max(1, math.min(qty, maximum)))
        if frame.UpdatePostState then frame:UpdatePostState() end
    end
end

function Sell.AfterSetItem(frame, location)
    local st = { auto = location ~= nil }
    state[frame] = st
    local itemID = ItemIDAt(location)
    local last = itemID and ns.Enabled("rememberPost") and ns.LastPost(itemID)
    if last then
        if Suggesting() then
            st.suggestDuration, st.suggestQty = last.duration, last.qty
        else
            WriteDuration(frame, last.duration)
            WriteQuantity(frame, last.qty)
        end
    end
    -- AH-19: Standard je Gegenstand bzw. Kategorie – eingetragen nur mit Tor T1 „geht“, sonst als Vorschlag
    local default = itemID and Sell.DefaultFor(itemID)
    if default then
        if ns.SellSetsValues() and not Suggesting() then
            WriteDuration(frame, default.duration)
            WriteQuantity(frame, default.qty)
        else
            st.suggestDuration = default.duration or st.suggestDuration
            st.suggestQty = default.qty or st.suggestQty
        end
    end
    if location then Sell.lastKey = nil end
    Sell.UpdateNext()
    -- Angebote schon geladen (Gegenstand erneut gewählt)? Dann gleich.
    if location then Sell.AfterPriceSelection(frame) else Sell.UpdatePriceButtons(frame) end
    ns.Fire("SELL_ITEM", itemID)
end

-- Eingestellt: Preis, Dauer und Menge für das nächste Mal merken. Der Hook läuft schon beim Aufruf von
-- PostItem/PostCommodity – ob der Server die Auktion annimmt, steht da noch nicht fest (Vollprüfung V-159).
-- Darum bleibt der vorige Stand in Sell.pending, bis AUCTION_HOUSE_AUCTION_CREATED bestätigt; meldet das
-- Auktionshaus vorher einen Fehler (AUCTION_HOUSE_SHOW_ERROR), kommt der vorige Stand zurück.
-- Nicht jeder Fehler gilt dem Einstellen (Nachbesserung, Fund 7): Fehler beim Bieten (Sell.BID_ERRORS) nehmen
-- nichts zurück, und die Antwort zählt nur binnen Sell.PENDING_WINDOW Sekunden nach dem Aufruf. Kommt
-- AUCTION_HOUSE_AUCTION_CREATED auf einem Client nicht, verfällt die Vormerkung danach – der gemerkte Stand gilt.
Sell.PENDING_WINDOW = 10
-- Namen in Blizzards Enum.AuctionHouseError, die nur beim Bieten vorkommen: die eine Liste steht seit Welle 14 in
-- ezCore (History.BID_ERRORS, AH-21); Sell.BID_ERRORS bleibt als Name und verweist darauf (Welle 15).
Sell.BID_ERRORS = Core.History and Core.History.BID_ERRORS or {}

-- Vormerkung, solange die Antwort des Servers noch zählt; eine verfallene wird verworfen (nil).
function Sell.Pending()
    local pending = Sell.pending
    if pending and (GetTime() - (pending.at or 0)) > Sell.PENDING_WINDOW then
        Sell.pending = nil
        return nil
    end
    return pending
end

-- Gilt dieser Fehlercode dem Bieten (nicht dem Einstellen)? Weiterleitung auf ezCores History.IsBidError (Übergabe
-- aus Welle 14: dieselbe Prüfung stand vorher hier ein zweites Mal); fehlt sie, gilt kein Code als Gebotsfehler.
function Sell.IsBidError(code)
    local history = Core.History
    if type(history) ~= "table" or type(history.IsBidError) ~= "function" then return false end
    return history.IsBidError(code) == true
end

function Sell.Remember(location, duration, quantity, price)
    if not ns.Enabled("rememberPost") then return end
    local itemID = ItemIDAt(location)
    if itemID and type(price) == "number" and price > 0 then
        local pending = Sell.Pending()
        local previous = ns.LastPost(itemID) or false
        -- Zweiter Versuch desselben Gegenstands vor der Antwort: der Stand vor dem ersten gilt weiter als „vorher“.
        if pending and pending.itemID == itemID and pending.key == ns.PostKey() then previous = pending.previous end
        ns.RememberPost(itemID, price, duration, quantity)
        Sell.pending = { itemID = itemID, previous = previous, key = ns.PostKey(), at = GetTime() }
        Sell.Refresh()
    end
end

-- Der Server hat die Auktion angelegt: der gemerkte Stand gilt.
function Sell.PostConfirmed()
    Sell.pending = nil
    Sell.AfterPost()
end

-- Das Auktionshaus hat einen Fehler gemeldet, bevor die Auktion bestätigt war: vorigen Stand zurückholen.
-- code: Fehlercode aus AUCTION_HOUSE_SHOW_ERROR (Fehler beim Bieten nehmen nichts zurück).
-- Rückgabe: true, wenn etwas zurückgenommen wurde.
function Sell.PostFailed(code)
    if Sell.IsBidError(code) then return false end
    local pending = Sell.Pending()
    if not pending then return false end
    Sell.pending = nil
    if pending.key == ns.PostKey() then
        ns.RestorePost(pending.itemID, pending.previous or nil)
        Sell.Refresh()
        local frame = Sell.ActiveFrame()
        if frame then Sell.UpdatePriceButtons(frame) end
    end
    return true
end

---------------------------------------------------------------------------
-- Einstellen: Vorschlag, Netto, Warnung, Nächster, Standardwerte (Welle 13)
---------------------------------------------------------------------------
--[[
    Alles hier ist Anzeige in eigenen, frei verankerten Teilen (nie als Layout-Kind in Blizzards Verkaufsbereich
    eingehängt): Vorschläge rechts unter dem jeweiligen Feld, die Warnmarke „!“ am Preisfeld, darunter im freien Raum
    unter Blizzards Einstellen-Knopf die Warnzeile und die Netto-Zeile („Nächster: …“ entfiel am 21.11.2026). Werte setzt ezAuction nur, wo
    es das vor Welle 13 schon tat (Preisregel, „Zuletzt“ – abschaltbar mit suggestOnly) und, sobald Tor T1 für den
    Verkaufsbereich „geht“ meldet (ns.SellSetsValues), für den nächsten Gegenstand (postNext), Standard-Menge und -Dauer und das Startgebot.
]]

local extras = setmetatable({}, { __mode = "k" })   -- [Verkaufsbereich] = eigene Teile

local function Line(parent, template)
    local line = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormalSmall")
    line:SetJustifyH("LEFT")
    line:Hide()
    return line
end

local function IsGoods(frame)
    local _, goods = SellFrames()
    return goods ~= nil and frame == goods
end

-- Werte im Verkaufsbereich: itemID, Preis (Waren je Stück, Einzelstücke je Auktion), Dauer 1–3, Menge.
function Sell.PostValues(frame)
    local itemID = frame and ItemIDAt(frame:GetItem())
    local price = frame and frame.PriceInput and Core.Num(frame.PriceInput:GetAmount())
    local quantity = frame and frame.QuantityInput
    local qty = quantity and quantity:IsShown() and Core.Num(quantity:GetQuantity()) or 1
    local duration = frame and frame.Duration and frame.Duration.GetDuration and Core.Num(frame.Duration:GetDuration()) or 2
    return itemID, price, duration, math.max(1, qty)
end

-- Die Netto-Zeile „Erlös ≈ … · Anzahlung …“ unter „Auktion erstellen“ (AH-20, Sell.NetText) entfiel im Spieltest vom
-- 21.11.2026 („das rechteck ist doppelt und kann weg“): Blizzards „Einzahlen“ und „Gesamtpreis“ stehen direkt darüber.

-- AH-20: Warnung bei Fehlpreis – weit unter dem Median (die EINE Bewertung aus AUC-04, Market.Judge mit dem einen
-- Schwellen-Schalter bargainPercent; keine zweite Schwelle) oder der Händler zahlt mehr als der Erlös nach Gebühr
-- (Prices.Proceeds; ohne gemessene Gebühr mehr als der volle Preis).
-- Rückgabe: Liste der Sätze oder nil. Nur Hinweis – Blizzards Einstellen-Knopf bleibt frei.
function Sell.Warning(frame)
    if not ns.Enabled("priceWarn") then return nil end
    local itemID, price = Sell.PostValues(frame)
    if not (itemID and price and price > 0) then return nil end
    local lines = {}
    local Market = ns.Market
    if Market then
        local variant = Market.HasVariant(Core.Call(C_AuctionHouse.GetItemKeyFromItem, frame:GetItem()))
        local judgement = Market.Judge(itemID, price, variant)
        if judgement and judgement.verdict == "cheap" then
            lines[#lines + 1] = L.SELL_WARN_CHEAP:format(Market.JudgeText(judgement))
        end
    end
    local vendor = Core.VendorPrice(itemID)
    if vendor and vendor > 0 then
        -- ohne gemessene Gebühr gegen den vollen Preis: Der Satz stimmt dann erst recht
        local after = Core.Prices.Proceeds(price, 1)
        if after and vendor > after then lines[#lines + 1] = L.SELL_WARN_VENDOR:format(ns.Money(vendor)) end
    end
    return #lines > 0 and lines or nil
end

---------------------------------------------------------------------------
-- AH-18: der nächste Gegenstand der Taschenliste
---------------------------------------------------------------------------

-- Die Zeile nach currentKey; ist der Gegenstand nicht mehr da (ganz eingestellt), die Zeile, die an seine Stelle rückt.
function Sell.NextGroup(groups, currentKey)
    if type(groups) ~= "table" or #groups == 0 then return nil end
    for index, group in ipairs(groups) do
        if group.key == currentKey then
            Sell.currentIndex = index
            return groups[index + 1]
        end
    end
    if not currentKey then return nil end
    return groups[math.min(Sell.currentIndex or 1, #groups)]
end

-- Rechnet „Als Nächstes“ neu (groups = die gezeigte Taschenliste, sonst neu gesammelt). Rückgabe: die Zeile oder nil.
-- Eine Anfrage über die Schnittstelle Sell (Sell.askedKey) geht „Als Nächstes“ vor. Sie ist erledigt, sobald der
-- angefragte Gegenstand im Verkaufsbereich liegt, und verfällt beim Schließen des Auktionshauses.
function Sell.UpdateNext(groups)
    local frame = Sell.ActiveFrame()
    local nextGroup
    local location = frame and frame:GetItem()
    local itemKey = location and Core.Call(C_AuctionHouse.GetItemKeyFromItem, location)
    local current = itemKey and ns.KeyString(itemKey) or nil
    if current and current == Sell.askedKey then Sell.askedKey = nil end
    if frame and ns.Enabled("nextItem") then
        local key = current or Sell.lastKey
        if key then
            Sell.lastKey = key
            groups = groups or Sell.Collect(panel and panel:IsShown() and panel.filter and panel.filter:GetText() or nil)
            if Sell.askedKey then
                for _, group in ipairs(groups) do
                    if group.key == Sell.askedKey then nextGroup = group break end
                end
            end
            nextGroup = nextGroup or Sell.NextGroup(groups, key)
        end
    end
    if nextGroup and nextGroup.key == Sell.lastKey then nextGroup = nil end
    Sell.nextGroup = nextGroup
    Sell.nextKey = Sell.askedKey or (nextGroup and nextGroup.key)
    return nextGroup
end

-- Die Zeile „Nächster: …“ unter Blizzards Einstellen-Knopf (samt Sell.NextClick und Sell.NextTip) entfiel im vierten
-- Spieltest vom 21.11.2026 („die info "Nächster: Leinenstoffballen" ist auch überflüssig“): der nächste steht golden
-- in der Taschenliste, ein Klick auf die Zeile legt ihn ein, postNext legt ihn nach dem Einstellen ein.

-- Nach dem Einstellen (AUCTION_HOUSE_AUCTION_CREATED): mit postNext und Tor T1 „geht“ den nächsten einlegen.
-- Rückgabe: true, wenn das Einlegen vorgemerkt ist.
Sell.NEXT_DELAY = 0.5
function Sell.AfterPost()
    if not (ns.Enabled("postNext") and ns.SellSetsValues()) then return false end
    local group = Sell.nextGroup
    if not group then return false end
    C_Timer.After(Sell.NEXT_DELAY, function()
        if ns.ModeName() == "sell" and Sell.nextGroup == group then Sell.Pick(group) end
    end)
    return true
end

-- ezCore.API("ezAuction").Sell(tasche, platz) → true | false, Grund: "closed" (Auktionshaus zu), "other" (Ansicht
-- eines fremden Addons), "item" (nichts Verkaufbares dort), "missing" (Client ohne SetPostItem), "t1" (Tor T1 für den
-- Verkaufsbereich hat kein Ergebnis „geht“: die Zeile wird in der Taschenliste nur hervorgehoben).
function Sell.SellFromBag(bag, slot)
    if not ns.AuctionHouseShown() then return false, "closed" end
    if ns.ModeName() == "other" then return false, "other" end
    bag, slot = Core.Num(bag), Core.Num(slot)
    if not (bag and slot and ItemLocation and ItemLocation.CreateFromBagAndSlot) then return false, "item" end
    local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
    if not (location and Core.Call(location.IsValid, location)) or not Core.Call(C_AuctionHouse.IsSellItemValid, location, false) then
        return false, "item"
    end
    if not ns.SellSetsValues() then
        local itemKey = Core.Call(C_AuctionHouse.GetItemKeyFromItem, location)
        Sell.askedKey = itemKey and ns.KeyString(itemKey) or nil
        Sell.Refresh()
        return false, "t1"
    end
    if not (AuctionHouseFrame and AuctionHouseFrame.SetPostItem) then return false, "missing" end
    Sell.askedKey = nil
    AuctionHouseFrame:SetPostItem(location)
    return true
end
ns.API.Sell = Sell.SellFromBag

-- Stehen abgeholte Rückläufer beim nächsten Besuch oben in der Taschenliste (AH-28)? true, wenn die Taschenliste an
-- (sie steht seit dem 21.11.2026 immer) und der Schalter auctionMail an ist – für ezMail (AH-33: dessen Tooltip nennt den Satz zur
-- Taschenliste nur dann). Nur Auskunft, ohne offenes Auktionshaus gültig (Schalter gelten für jeden Besuch).
function Sell.ReturnsListed()
    if not (ns.db and ns.S) then return false end
    return ns.Enabled("sellList") == true and ns.Enabled("auctionMail") == true
end
-- ezCore.API("ezAuction").ReturnsListed() → true | false (Welle 23; ezMail fragt sie seit Welle 15 ab)
ns.API.ReturnsListed = Sell.ReturnsListed

---------------------------------------------------------------------------
-- AH-19: Standard-Menge und -Dauer je Gegenstand oder Kategorie, Startgebot als Anteil am Sofortkauf
---------------------------------------------------------------------------
-- ezAuctionDB.ui.postDefaults = { items = { [itemID] = { qty, duration } }, classes = { [classID] = { … } } } – für den
-- Account gleich (Menge und Dauer hängen nicht am Auktionshaus); beim Lesen geprüft.

Sell.MAX_QTY = 10000

local function DefaultsStore()
    local ui = ns.db and ns.db.ui
    if not ui then return { items = {}, classes = {} } end
    local store = type(ui.postDefaults) == "table" and ui.postDefaults or {}
    ui.postDefaults = store
    store.items = type(store.items) == "table" and store.items or {}
    store.classes = type(store.classes) == "table" and store.classes or {}
    return store
end

-- Ein gespeicherter Standard, geprüft: { qty, duration } oder nil (kaputt bzw. leer).
function Sell.CleanDefault(value)
    if type(value) ~= "table" then return nil end
    local qty = Core.Num(value.qty)
    qty = qty and qty >= 1 and math.min(math.floor(qty), Sell.MAX_QTY) or nil
    local duration = Core.Num(value.duration)
    duration = duration and (duration == 1 or duration == 2 or duration == 3) and duration or nil
    if not (qty or duration) then return nil end
    return { qty = qty, duration = duration }
end

-- Standard für einen Gegenstand: der eigene, sonst der seiner Kategorie (Blizzards Gegenstandsart). Rückgabe:
-- { qty, duration, scope = "item" | "class", classID } oder nil (auch mit ausgeschaltetem postDefaults).
function Sell.DefaultFor(itemID)
    itemID = Core.Num(itemID)
    if not (itemID and ns.Enabled("postDefaults")) then return nil end
    local store = DefaultsStore()
    local own = Sell.CleanDefault(store.items[itemID])
    if own then
        own.scope = "item"
        return own
    end
    local classID = Core.ItemClass(itemID)
    local class = classID and Sell.CleanDefault(store.classes[classID])
    if class then
        class.scope, class.classID = "class", classID
        return class
    end
    return nil
end

-- Standard setzen (qty und duration nil = entfernen). scope "item" (id = itemID) oder "class" (id = classID).
function Sell.SetDefault(scope, id, qty, duration)
    id = Core.Num(id)
    local store = DefaultsStore()
    local tbl = scope == "class" and store.classes or scope == "item" and store.items
    if not (tbl and id) then return false end
    tbl[id] = Sell.CleanDefault({ qty = qty, duration = duration })
    local frame = Sell.ActiveFrame()
    if frame then
        local st = state[frame]
        local default = Sell.DefaultFor(ItemIDAt(frame:GetItem()))
        if st then st.suggestQty, st.suggestDuration = default and default.qty, default and default.duration end
        Sell.UpdatePriceButtons(frame)
    end
    return true
end

-- Startgebot nach der Regel „Anteil am Sofortkauf“ (bidPercent, nur Einzelstücke); nil, wenn sie nicht gilt.
function Sell.BidFor(frame)
    local percent = Core.Num(ns.S and ns.S.bidPercent) or 0
    if percent <= 0 or IsGoods(frame) then return nil end
    local _, price = Sell.PostValues(frame)
    if not (price and price > 0) then return nil end
    local step = ns.Step()
    local bid = ns.RoundDown(price * percent / 100, step)
    if bid < step or bid >= price then return nil end
    return bid
end

-- Einträge des Menüs am Pfeil neben „Zuletzt“ (auch für Prüfungen): { text, fn } bzw. { choice = … }.
function Sell.DefaultsEntries(frame)
    local itemID, _, duration, qty = Sell.PostValues(frame)
    if not itemID then return {} end
    local entries = {}
    local now = L.SELL_DEFAULT_VALUES:format(qty, DurationText(duration))
    local name = Core.ItemNameByID(itemID) or ("#" .. itemID)
    local store = DefaultsStore()
    entries[#entries + 1] = { text = L.SELL_DEFAULT_ITEM:format(name, now),
        fn = function() return Sell.SetDefault("item", itemID, qty, duration) end }
    local classID = Core.ItemClass(itemID)
    local className = classID and (Core.ItemClassName(classID) or ("#" .. classID))
    if classID then
        entries[#entries + 1] = { text = L.SELL_DEFAULT_CLASS:format(className, now),
            fn = function() return Sell.SetDefault("class", classID, qty, duration) end }
    end
    if Sell.CleanDefault(store.items[itemID]) then
        entries[#entries + 1] = { text = L.SELL_DEFAULT_ITEM_CLEAR:format(name),
            fn = function() return Sell.SetDefault("item", itemID, nil, nil) end }
    end
    if classID and Sell.CleanDefault(store.classes[classID]) then
        entries[#entries + 1] = { text = L.SELL_DEFAULT_CLASS_CLEAR:format(className),
            fn = function() return Sell.SetDefault("class", classID, nil, nil) end }
    end
    if not IsGoods(frame) then
        local options = { { 0, L.OPT_bidPercent_OFF } }
        for _, percent in ipairs({ 50, 70, 80, 90 }) do options[#options + 1] = { percent, Core.Percent(percent) } end
        entries[#entries + 1] = { choice = options, text = L.OPT_bidPercent }
    end
    if ns.Enabled("rememberPost") and ns.LastPost(itemID) then
        entries[#entries + 1] = { text = L.SELL_DEFAULT_LAST, fn = function() Sell.ApplyLast(frame) end }
    end
    return entries
end

function Sell.DefaultsMenu(owner, frame)
    local entries = Sell.DefaultsEntries(frame)
    if #entries == 0 then return false end
    local Menu = Core.Menu
    local opened = Menu.Open(owner, function(root)
        Menu.Title(root, L.SELL_DEFAULT_TITLE)
        for _, entry in ipairs(entries) do
            if entry.choice then
                Menu.Choice(root, entry.text, entry.choice, function() return ns.S.bidPercent end, function(value)
                    ns.SetSetting("bidPercent", value)
                    Sell.UpdatePriceButtons(frame)
                end)
            else
                Menu.Button(root, entry.text, entry.fn)
            end
        end
    end)
    if not opened then ns.Print(L.SELL_DEFAULT_NO_MENU) end
    return opened
end

local function BuildExtras(frame)
    local input = frame.PriceInput
    local x = {}
    local function Under(line, field)
        line:SetPoint("TOPRIGHT", field, "BOTTOMRIGHT", 0, 3)
        return line
    end
    x.suggestPrice = Under(Line(input, "GameFontHighlightSmall"), input.MoneyInputFrame or input)
    x.suggestQty = frame.QuantityInput and Under(Line(frame.QuantityInput, "GameFontHighlightSmall"), frame.QuantityInput)
    x.suggestDuration = frame.Duration and Under(Line(frame.Duration, "GameFontHighlightSmall"), frame.Duration)
    local bidInput = Core.Peek(frame, "SecondaryPriceInput")
    if type(bidInput) == "table" and bidInput.CreateFontString then
        x.bidInput = bidInput
        x.suggestBid = Under(Line(bidInput, "GameFontHighlightSmall"), Core.Peek(bidInput, "MoneyInputFrame") or bidInput)
    else
        x.suggestBid = Line(input, "GameFontHighlightSmall")
        x.suggestBid:SetPoint("TOPRIGHT", x.suggestPrice, "BOTTOMRIGHT", 0, -1)
    end
    -- Warnmarke am Preisfeld (der Tooltip nennt den Grund)
    x.warnMark = ns.TextButton(input)
    x.warnMark:SetLabel(Core.Style.ColorText("bad", "!"))   -- Blizzards Rot (Design-System 2.5; bis Welle 22 ff4040)
    x.warnMark:SetPoint("LEFT", input.MoneyInputFrame or input, "RIGHT", 4, 0)
    x.warnMark:SetScript("OnEnter", function(self) Core.ShowTip(self, L.SELL_WARN_TITLE, x.warnText or "") end)
    x.warnMark:Hide()
    -- Zeilen im freien Raum unter Blizzards Einstellen-Knopf
    x.warn = Line(frame, "GameFontRedSmall")
    x.warn:SetWidth(320)
    -- Pfeil an „Zuletzt“: Standard-Menge, -Dauer und Startgebot (AH-19)
    -- Pfeil aus ezCore (Core.Toolbar.ArrowButton, T18-13), Design-System 2.3 (bis Welle 22 14)
    x.menu = Core.Toolbar.ArrowButton(input, function(self) Sell.DefaultsMenu(self, frame) end, L.SELL_DEFAULT_TITLE,
        L.SELL_DEFAULT_TIP, { size = Core.Style.BUTTON.small })
    x.menu:Hide()
    extras[frame] = x
    return x
end

function Sell.Extras(frame)
    return frame and (extras[frame] or (frame.PriceInput and BuildExtras(frame))) or nil
end

local function SetText(line, text)
    if not line then return end
    line:SetText(text or "")
    line:SetShown(text ~= nil)
end

-- Die Zeilen unter Blizzards Einstellen-Knopf untereinander, ohne Lücke für ausgeblendete. Jede rückt um ihre wirkliche
-- Höhe weiter (Spielbefund vom 21.11.2026: eine umgebrochene Zeile hat zwei). Seit dem 21.11.2026 steht dort nur noch
-- die Warnung (Erlös und „Nächster“ entfielen); die Liste bleibt, damit eine weitere Zeile wieder richtig rückt.
Sell.STACK_LINE = 14
local function LineHeight(line)
    local h = line.GetStringHeight and Core.Num(Core.Call(line.GetStringHeight, line))
    if not h or h <= 0 then h = Core.Num(Core.Call(line.GetHeight, line)) end
    return math.max(Sell.STACK_LINE, (h or 0) + 2)
end
local function Stack(frame, x)
    local anchor = Core.Peek(frame, "PostButton")
    local y = -4
    for _, line in ipairs({ x.warn }) do
        if line:IsShown() then
            line:ClearAllPoints()
            if type(anchor) == "table" then
                line:SetPoint("TOP", anchor, "BOTTOM", 0, y)
            else
                line:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 8, y)
            end
            y = y - LineHeight(line)
        end
    end
end

local writingBid = false

-- Alle eigenen Teile des Verkaufsbereichs neu (nach Blizzards UpdatePostState, nach Regel und „Zuletzt“).
function Sell.UpdateExtras(frame)
    if not (frame and priceButtons[frame]) then return end
    local x = Sell.Extras(frame)
    if not x then return end
    local itemID, price, duration, qty = Sell.PostValues(frame)
    local st = state[frame] or {}
    local has = itemID ~= nil
    -- Vorschläge (AH-38, AH-19): nur, wo das Feld etwas anderes zeigt
    SetText(x.suggestPrice, has and st.suggestPrice and st.suggestPrice ~= price and L.SUGGEST:format(ns.Money(st.suggestPrice)) or nil)
    local quantityShown = frame.QuantityInput and frame.QuantityInput:IsShown()
    SetText(x.suggestQty, has and quantityShown and st.suggestQty and st.suggestQty ~= qty
        and L.SUGGEST:format(L.SUGGEST_QTY:format(st.suggestQty)) or nil)
    SetText(x.suggestDuration, has and st.suggestDuration and st.suggestDuration ~= duration
        and L.SUGGEST:format(DurationText(st.suggestDuration)) or nil)
    local bid = has and Sell.BidFor(frame)
    local bidShown = bid and x.bidInput and Core.Num(Core.Call(x.bidInput.GetAmount, x.bidInput))
    if bid and ns.SellSetsValues() and not Suggesting() and x.bidInput and type(x.bidInput.SetAmount) == "function" then
        if bidShown ~= bid and not writingBid then
            writingBid = true
            ns.Try("SetBid", x.bidInput.SetAmount, x.bidInput, bid)
            writingBid = false
        end
        SetText(x.suggestBid, nil)
    else
        SetText(x.suggestBid, bid and bidShown ~= bid and L.SUGGEST_BID:format(ns.Money(bid)) or nil)
    end
    -- Warnung (AH-20)
    local warning = has and Sell.Warning(frame)
    x.warnText = warning and table.concat(warning, "\n") or nil
    SetText(x.warn, warning and warning[1] or nil)
    x.warnMark:SetShown(warning ~= nil and warning ~= false)
    Stack(frame, x)
end

---------------------------------------------------------------------------

ns.OnAuctionHouse(function()
    local items, goods = SellFrames()
    for _, frame in ipairs({ items, goods }) do
        if frame then
            if frame.SetItem then
                hooksecurefunc(frame, "SetItem", function(self, location) Sell.AfterSetItem(self, location) end)
            end
            if frame.UpdatePriceSelection then
                hooksecurefunc(frame, "UpdatePriceSelection", function(self) Sell.AfterPriceSelection(self) end)
            end
            -- Blizzard meldet jede Änderung an Preis, Menge und Dauer hierüber: Vorschläge, Netto, Warnung neu
            if frame.UpdatePostState then
                hooksecurefunc(frame, "UpdatePostState", function(self) ns.Try("SellExtras", Sell.UpdateExtras, self) end)
            end
        end
    end
    if C_AuctionHouse.PostItem then
        hooksecurefunc(C_AuctionHouse, "PostItem", function(location, duration, quantity, bid, buyout)
            Sell.Remember(location, duration, quantity, buyout or bid)
        end)
    end
    if C_AuctionHouse.PostCommodity then
        hooksecurefunc(C_AuctionHouse, "PostCommodity", function(location, duration, quantity, unitPrice)
            Sell.Remember(location, duration, quantity, unitPrice)
        end)
    end
end)

ns.On("AUCTION_HOUSE_AUCTION_CREATED", function() Sell.PostConfirmed() end)
ns.On("AUCTION_HOUSE_SHOW_ERROR", function(_, code) Sell.PostFailed(code) end)
ns.Listen("AH_CLOSED", function() Sell.pending = nil end)
ns.Listen("AH_MODE", function() Sell.UpdatePanel() end)
ns.Listen("PRICES_UPDATED", function() Sell.Refresh() end)
ns.Listen("AH_SHOW", function() Sell.UpdatePanel() end)
ns.Listen("AH_HIDE", function()
    Sell.askedKey = nil
    if panel then panel:Hide() end
end)
ns.On("BAG_UPDATE_DELAYED", ns.Throttle(function() Sell.Refresh() end, 0.2))
-- ezCore trägt Auktionspost und Einstellungen ein: Marke „zurück“ und Erfolgsquote folgen (Welle 15)
local refreshLater = ns.Throttle(function() Sell.Refresh() end, 0.2)
Core.Listen("HISTORY_ADDED", function(kind)
    if kind == "auction" or kind == "posting" then refreshLater() end
end, "ezAuction")
ns.OnSettingChanged(function(key)
    if key == "sellList" or key == "sellListSide" or key == "marketPanel" then Sell.UpdatePanel() end
    if key == "priceRule" or key == "undercutPercent" or key == "rememberPost" or key == "floorTrend"
        or key == "suggestOnly" or key == "priceWarn" or key == "nextItem" or key == "postDefaults"
        or key == "bidPercent" or key == "auctionMail" or key == "sellAdvice" or key == "sellHideLocked"
        or key == "sellPins" or key == "sellOtherChars" then
        local frame = Sell.ActiveFrame()
        if frame then Sell.UpdatePriceButtons(frame) end
        Sell.Refresh()
    end
end)
