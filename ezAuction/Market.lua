local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Markt: die Rechnung hinter dem Seitenteil „Markt“ (MarketPanel.lua), den Markierungen in Blizzards Ergebnisliste
    (BuyTab.lua) und der Preisregel (SellTab.lua). Alle Zahlen kommen aus ezCore.Prices (Stats, History, Get) – nur
    der eigene Verlauf, Auctionator ist keine Quelle (Entscheidung des Nutzers vom 14.11.2026, Ablösung). Jede
    Aussage nennt Quelle und Zahl der Erfassungen (Leitlinie 11); unter einer Mindestzahl steht „noch zu wenig Daten“.

      Market.Assess(preis, stats, schwelle)  → bewertung | nil, grund     reine Rechnung (ohne Spiel prüfbar)
      Market.Judge(item, preis, variante)    → bewertung | nil, grund     DIE Bewertung „günstig/teuer gegen den Median“
          bewertung = { verdict = "cheap" | "expensive" | "normal", percent, median, days, stats }
          grund     = "off" (Schalter marketHint aus) | "price" | "few" (weniger als Market.HINT_DAYS Tage)
                      | "variant" (Abwandlung am Schlüssel oder Stats.mixed: der Median mischt verschiedene Preise)
          Schwelle ist EIN Schalter: bargainPercent („Schnäppchen ab“); „teuer“ ab Market.EXPENSIVE % darüber.
          Abnehmer: Markierung „−23 %“ (BuyTab.lua), Seitenteil, Preisregel – und später AH-20 (Warnung bei
          Fehlpreis), AH-22 („Schnäppchen (n)“), AH-29 (Verkaufsempfehlung); auch über ezCore.API("ezAuction").Judge.
      Market.JudgeText(bewertung)            → „Günstig: 18 % unter dem Mittel der letzten 12 Tage (…)“
      Market.SellAdvice(item, preis, menge, variante) → { good = true, text } | nil, grund   „guter Zeitpunkt“ (Entwurf 3)
      Market.Availability(item)              → { Zeile … }    „Gesehen an 9 von 12 erfassten Tagen“, übliche Menge
      Market.GraphPoints(item, variante)     → punkte, opts, zustand, stats   für Core.NewGraph (Entwurf 1)
      Market.WeekPoints(item)                → punkte, opts, zustand, wochen  Langzeit-Verlauf in Wochen (V1, Welle 23)
      Market.WeeksAvailable(item, variante)  → true | false, grund ("off" | "none" | "variant" | "mixed" | "unwatched")
      Market.CopyColumns(), Market.CopyRows(item, variante, opts) → Spalten und Zeilen für „Als Text kopieren“ (V5,
                                             Welle 24): Tage, Wochen und eigene Auktionen des Gegenstands, je mit Quelle;
                                             dazu grund "variant", wenn Tage wegen Abwandlungen wegfallen
      Market.SourceLine(info, item)          → „Quelle: laut deinen Erfassungen (…), zuletzt vor 2 Std.“
      Market.Weekdays(verlauf, heute)        → wochentag | nil, grund     reine Rechnung (Entwurf 2b, Frage 38)
      Market.WeekdayLine(item)               → „Wochentag: montags meist 12 % günstiger als im Mittel (…)“ | nil
      Market.DayTimes(protokoll)             → tageszeit | nil, grund     reine Rechnung (Entwurf 2c, ganzer Markt)
      Market.DayTimeLine()                   → „Tageszeit (ganzer Markt): abends etwa 18 % mehr …“ | nil
          Grundlage: ezCores Tagespunkte (Prices.History, Tag in Serverzeit) und das Protokoll der Erfassungen
          (Prices.Captures: Tag, Stunde, Art, Zahl der Gegenstände je Erfassung). Unter der Mindestzahl steht
          „noch zu wenig Daten“ mit der Zahl der Erfassungen; jede Aussage nennt ihre Zahl.
      Market.Salvage(item, preis)            → vergleich | nil, grund     Entzaubern gegen den Auktionspreis (AUC-19)
      Market.SalvageLines(item, preis)       → { „Entzaubern ≈ 2 g – mehr als der Auktionspreis (1 g)“, Quelle } | {}
    Nie eine automatische Aktion: hier wird nur gerechnet und beschrieben.
]]

local Market = {}
ns.Market = Market

Market.HINT_DAYS = 5      -- Hinweis und Median-Bezug erst ab fünf Tagespunkten (Entwurf 3)
Market.GRAPH_DAYS = 3     -- Graph erst ab drei Tagespunkten, sonst „erst 2 Tage erfasst“ (Entwurf 1)
Market.AVAIL_DAYS = 3     -- „gesehen an x von y“ erst ab drei erfassten Tagen (Entwurf 2a)
Market.EXPENSIVE = 15     -- „teuer“ ab so viel Prozent über dem Median (fest, Entwurf 3)
Market.FRESH = 86400      -- eine Menge „heute“ gilt einen Tag ab ihrer Erfassung

local DAY = 86400

local function Prices() return ns.Prices() end

-- Zeitraum der Rechnung: ezCores Verlauf für alles (14 Kalendertage, Frage 37).
function Market.Days()
    local prices = Prices()
    return prices and Core.Num(prices.HISTORY_DAYS) or 14
end

-- Zahlen in den Tooltips der Einstellungen aus ihrer einen Stelle (hier und ezCore.Prices), nicht fest im Text
-- (Leitlinie 2); eingesetzt einmal beim Laden, vor dem Füllen der Einstellungsseite.
local function FillTip(key, ...)
    if type(L[key]) == "string" and L[key]:find("%d", 1, true) then L[key] = L[key]:format(...) end
end
FillTip("OPT_marketHint_TIP", Market.HINT_DAYS, Market.EXPENSIVE)
FillTip("OPT_floorTrend_TIP", Market.Days())

-- ezCore.Prices.Stats über den Zeitraum; nil ohne Preis-Wissen oder Verlauf.
function Market.Stats(item)
    local prices = Prices()
    if not (prices and item and type(prices.Stats) == "function") then return nil end
    local stats = Core.Call(prices.Stats, item, Market.Days())
    return type(stats) == "table" and stats or nil
end

-- „Quelle: laut deinen Erfassungen (Übersicht, an 9 Tagen gesehen)“ aus ezCores Prices.SourceText (Leitlinie 11).
-- Bei Prices.Stats nennt ezCore die Zahl der Tage, nicht das Alter: mit item dazu „zuletzt vor 2 Std.“ aus der
-- letzten eigenen Erfassung (AUC-01: Quelle und Alter überall).
function Market.SourceLine(info, item)
    local prices = Prices()
    local text = prices and type(prices.SourceText) == "function" and Core.Call(prices.SourceText, info)
    if type(text) ~= "string" or text == "" then return nil end
    local last = item and type(info) == "table" and not Core.Num(info.seen) and ns.PriceInfo(item)
    local seen = type(last) == "table" and Core.Num(last.seen)
    if seen and Core.Ago then return L.MARKET_SOURCE_LAST:format(text, Core.Ago(seen)) end
    return L.MARKET_SOURCE:format(text)
end

---------------------------------------------------------------------------
-- Die eine Bewertung „günstig/teuer gegen den Median“
---------------------------------------------------------------------------

function Market.Assess(price, stats, bargain)
    price = Core.Num(price)
    if not (price and price > 0) then return nil, "price" end
    local median = type(stats) == "table" and Core.Num(stats.median)
    local days = type(stats) == "table" and Core.Num(stats.points) or 0
    if not (median and median > 0) or days < Market.HINT_DAYS then return nil, "few" end
    -- Abwandlungen laufen im Verlauf zusammen: gegen diesen Median gibt es kein Urteil (wie kein Graph)
    if stats.mixed then return nil, "variant" end
    local percent = Core.Round((price - median) / median * 100)
    bargain = Core.Num(bargain) or 20
    local verdict = "normal"
    if percent <= -bargain then
        verdict = "cheap"
    elseif percent >= Market.EXPENSIVE then
        verdict = "expensive"
    end
    return { verdict = verdict, percent = percent, median = median, days = days, stats = stats }
end

function Market.Judge(item, price, variant)
    if not ns.Enabled("marketHint") then return nil, "off" end
    if variant then return nil, "variant" end
    return Market.Assess(price, Market.Stats(item), ns.S and ns.S.bargainPercent)
end

-- Begründung in einem Satz, ohne Quelle (die steht darunter: Market.SourceLine(bewertung.stats)).
function Market.JudgeText(judgement)
    if type(judgement) ~= "table" then return nil end
    local percent, days = judgement.percent or 0, Core.Plural(judgement.days or 0, L.MARKET_DAYS_ONE, L.MARKET_DAYS_MANY)
    local money = ns.Money(judgement.median)
    local amount = Core.Percent(math.abs(percent))
    if judgement.verdict == "cheap" then return L.MARKET_CHEAP:format(amount, days, money) end
    if judgement.verdict == "expensive" then return L.MARKET_EXPENSIVE:format(amount, days, money) end
    if percent < 0 then return L.MARKET_UNDER:format(amount, days, money) end
    if percent > 0 then return L.MARKET_OVER:format(amount, days, money) end
    return L.MARKET_AT:format(days, money)
end

---------------------------------------------------------------------------
-- Menge heute, Verfügbarkeit, Verkaufshinweis
---------------------------------------------------------------------------

-- Angebotene Menge aus der letzten Erfassung, wenn sie höchstens einen Tag alt ist; sonst nil.
function Market.TodayQuantity(item)
    local info = ns.PriceInfo(item)
    local seen, qty = info and Core.Num(info.seen), info and Core.Num(info.quantity)
    if not (seen and qty) or time() - seen > Market.FRESH then return nil end
    return qty
end

-- Zeilen „Gesehen an 9 von 12 erfassten Tagen“ und „Üblich: 40 bis 120 Stück (aus 9 Tagen), heute 15“ – die Spanne
-- aus ezCores quantityLow/quantityHigh (unteres und oberes Viertel der Tagesmengen, Welle 23b), ohne Spanne oder bei
-- gleichen Grenzen „etwa 80“ (usualQuantity); unter
-- Market.AVAIL_DAYS erfassten Tagen „Noch zu wenig Daten …“ (quiet: dann nichts – für den knappen Tooltip einer
-- Ergebniszeile). Leer ohne Verlauf. today = Menge heute (sonst die letzte Erfassung des Tages).
function Market.Availability(item, stats, today, quiet)
    stats = stats or Market.Stats(item)
    if type(stats) ~= "table" then return {} end
    local captured, seen = Core.Num(stats.daysCaptured) or 0, Core.Num(stats.daysSeen) or 0
    if captured < Market.AVAIL_DAYS then
        if quiet then return {} end
        return { Core.Plural(captured, L.MARKET_FEW_DATA_ONE, L.MARKET_FEW_DATA_MANY) }
    end
    local lines = { L.MARKET_SEEN:format(seen, captured) }
    local usual = Core.Num(stats.usualQuantity)
    if usual and usual > 0 then
        local from = Core.Plural(seen, L.MARKET_FROM_ONE, L.MARKET_FROM_MANY)
        today = Core.Num(today) or Market.TodayQuantity(item)
        local low, high = Core.Num(stats.quantityLow), Core.Num(stats.quantityHigh)
        if low and high and low > 0 and high > low then
            if today then
                lines[#lines + 1] = L.MARKET_USUAL_SPAN_TODAY:format(low, high, from, today)
            else
                lines[#lines + 1] = L.MARKET_USUAL_SPAN:format(low, high, from)
            end
        elseif today then
            lines[#lines + 1] = L.MARKET_USUAL_TODAY:format(usual, from, today)
        else
            lines[#lines + 1] = L.MARKET_USUAL:format(usual, from)
        end
    end
    return lines
end

-- „Guter Zeitpunkt“ zum Verkaufen: der Preis liegt am oder über dem Median und heute wird weniger als üblich
-- angeboten (Entwurf 3). Zurückhaltend: sonst nichts (nil und Grund "off" | "few" | "price" |
-- "variant" | "quantity" | "no").
function Market.SellAdvice(item, price, offered, variant)
    if not ns.Enabled("marketHint") then return nil, "off" end
    if variant then return nil, "variant" end
    local stats = Market.Stats(item)
    local judgement, why = Market.Assess(price, stats, ns.S and ns.S.bargainPercent)
    if not judgement then return nil, why end
    local usual = Core.Num(stats.usualQuantity)
    offered = Core.Num(offered) or Market.TodayQuantity(item)
    if not (usual and usual > 0 and offered) then return nil, "quantity" end
    if judgement.percent < 0 or offered >= usual then return nil, "no" end
    local days = Core.Plural(judgement.days, L.MARKET_DAYS_ONE, L.MARKET_DAYS_MANY)
    return { good = true, judgement = judgement, offered = offered, usual = usual,
        text = L.MARKET_SELL_GOOD:format(days, ns.Money(judgement.median), offered, usual) }
end

---------------------------------------------------------------------------
-- Wochentag und Tageszeit (Entwurf 2b/2c, Frage 38 – Empfehlung umgesetzt, Antwort offen: zunächst nur „Wochentag“
-- je Gegenstand und eine marktweite Aussage zur Tageszeit, je mit der Zahl der Erfassungen)
---------------------------------------------------------------------------

Market.WEEK_DAYS = 28     -- Wochentag erst ab vier Wochen Verlauf (erster Tagespunkt mindestens 28 Kalendertage alt)
Market.WEEK_MIN = 3       -- je Wochentag mindestens drei Tagespunkte, sonst zählt der Tag nicht mit
Market.WEEK_COUNTED = 2   -- eine Aussage erst, wenn mindestens zwei Wochentage so zählen (sonst fehlt der Vergleich)
Market.WEEK_PERCENT = 5   -- eine Aussage „günstiger“ bzw. „mehr“ erst ab 5 % Abstand
Market.TIME_SCANS = 8     -- Tageszeit erst ab acht Komplett-Scans …
Market.TIME_SLOT_MIN = 2  -- … davon je mindestens zwei in zwei der vier Tageszeiten
-- Tageszeiten in Serverzeit (Stunde aus ezCores Protokoll): von, bis (ausschließlich), Schlüssel des Texts
Market.SLOTS = { { 0, 6, "night" }, { 6, 12, "morning" }, { 12, 18, "afternoon" }, { 18, 24, "evening" } }
FillTip("OPT_marketPanel_TIP", Market.WEEK_DAYS)

-- Median einer Liste: ezCores Core.Median (sortiert, Mitte, bei gerader Zahl der gerundete Mittelwert; Welle 23 statt
-- der eigenen Rechnung MedianOf, Leitlinie 2).
local MedianOf = Core.Median

-- Wochentag eines Tags aus ezCores Verlauf: 0 = Sonntag … 6 = Samstag. Die Regel steht einmal in ezCore
-- (Prices.Weekday, Welle 23b); der Name bleibt für die Aufrufer hier, im Seitenteil und in den Prüfungen.
function Market.WeekdayOf(day)
    local prices = Prices()
    if not (prices and type(prices.Weekday) == "function") then return nil end
    return prices.Weekday(day)
end

-- Reine Rechnung über Tagespunkte { { day, min } … }: Median der Tages-Tiefstpreise je Wochentag gegen den Median
-- aller Tage. → { span, points, median, best = { weekday, percent, count, median }, worst = {…}, counted } oder nil
-- und Grund "none" (kein Punkt), "few" (Verlauf kürzer als WEEK_DAYS) bzw. "sparse" (vier Wochen da, aber weniger
-- als WEEK_COUNTED Wochentage mit je WEEK_MIN Punkten); zweite Rückgabe dann der Grund, dritte die Zahl der
-- Kalendertage seit dem ersten Punkt, vierte die Punkte.
function Market.Weekdays(history, today)
    today = Core.Num(today)
    local all, byDay, first, points = {}, {}, nil, 0
    for _, p in ipairs(type(history) == "table" and history or {}) do
        local day, low = type(p) == "table" and Core.Num(p.day), type(p) == "table" and Core.Num(p.min)
        if day and low and low > 0 and (not today or day <= today) then
            points = points + 1
            all[#all + 1] = low
            local w = Market.WeekdayOf(day)
            byDay[w] = byDay[w] or {}
            table.insert(byDay[w], low)
            if not first or day < first then first = day end
        end
    end
    if points == 0 then return nil, "none", 0, 0 end
    local span = (today or first) - first + 1
    if span < Market.WEEK_DAYS then return nil, "few", span, points end
    local median = MedianOf(all)
    local best, worst, counted = nil, nil, 0
    for w = 0, 6 do
        local list = byDay[w]
        if list and #list >= Market.WEEK_MIN and median and median > 0 then
            counted = counted + 1
            local count = #list
            local m = MedianOf(list)
            local entry = { weekday = w, count = count, median = m, percent = Core.Round((m - median) / median * 100) }
            if not best or entry.percent < best.percent then best = entry end
            if not worst or entry.percent > worst.percent then worst = entry end
        end
    end
    if counted < Market.WEEK_COUNTED then return nil, "sparse", span, points end
    return { span = span, points = points, median = median, best = best, worst = worst, counted = counted }
end

-- Zeile für das Seitenteil. Ohne Verlauf nil; bei Abwandlungen (variant) nil – ihr Median mischt verschiedene Preise.
-- Unter vier Wochen „noch zu wenig Daten“; ist der Gegenstand nicht beobachtet, sagt die Zeile, warum er sie nie
-- erreicht (ezCore hält 30 Tage Verlauf nur für beobachtete Gegenstände, sonst 14 – Frage 37).
function Market.WeekdayLine(item, variant)
    local prices = Prices()
    if variant or not (prices and item and type(prices.History) == "function") then return nil end
    local history = Core.Call(prices.History, item)
    local today = Core.Call(prices.Day) or math.floor(time() / DAY)
    local week, why, span, points = Market.Weekdays(history, today)
    if not week then
        if why == "none" then return nil end
        local keep = Core.Num(prices.HISTORY_DAYS) or 14
        local observed = type(prices.IsObserved) == "function" and Core.Call(prices.IsObserved, item)
        if keep < Market.WEEK_DAYS and observed == false then
            return L.MARKET_WEEK_UNWATCHED:format(Market.WEEK_DAYS, Core.Num(prices.WATCH_DAYS) or 30, keep)
        end
        local captured = Core.Plural(points or 0, L.MARKET_CAPTURES_ONE, L.MARKET_CAPTURES_MANY)
        local since = Core.Plural(span or 0, L.MARKET_SINCE_ONE, L.MARKET_SINCE_MANY)
        if why == "sparse" then
            return L.MARKET_WEEK_SPARSE:format(captured, since, Market.WEEK_MIN, Market.WEEK_COUNTED)
        end
        return L.MARKET_WEEK_FEW:format(captured, since, Market.WEEK_DAYS)
    end
    local best = week.best
    local since = Core.Plural(week.span, L.MARKET_SINCE_ONE, L.MARKET_SINCE_MANY)
    if best.percent <= -Market.WEEK_PERCENT then
        return L.MARKET_WEEK_CHEAP:format(L["WEEKDAY_" .. best.weekday], Core.Percent(-best.percent),
            Core.Plural(best.count, L.MARKET_WEEK_COUNT_ONE, L.MARKET_WEEK_COUNT_MANY), since)
    end
    return L.MARKET_WEEK_EVEN:format(Core.Plural(week.points, L.MARKET_CAPTURES_ONE, L.MARKET_CAPTURES_MANY), since)
end

-- Reine Rechnung über das Protokoll { { hour, kind, n } … }: nur Komplett-Scans (sie zählen alle Gegenstände im
-- Angebot und sind darum vergleichbar), Median der Zahl verschiedener Gegenstände je Tageszeit.
-- → { scans, most = { slot, median, count }, least = {…}, percent } oder nil, "few", Zahl der Komplett-Scans.
-- Grenze: Zwei Scans in derselben Stunde zählt ezCore als einen Eintrag mit beiden Zahlen – der Median fängt das
-- meist auf (docs/roadmap/ezAuction.md, „Offen“).
function Market.DayTimes(captures)
    local bySlot, scans = {}, 0
    for _, c in ipairs(type(captures) == "table" and captures or {}) do
        local hour, n = type(c) == "table" and Core.Num(c.hour), type(c) == "table" and Core.Num(c.n)
        if hour and n and n > 0 and c.kind == "scan" then
            for index, slot in ipairs(Market.SLOTS) do
                if hour >= slot[1] and hour < slot[2] then
                    scans = scans + 1
                    bySlot[index] = bySlot[index] or {}
                    table.insert(bySlot[index], n)
                end
            end
        end
    end
    local most, least, slots = nil, nil, 0
    for index = 1, #Market.SLOTS do
        local list = bySlot[index]
        if list and #list >= Market.TIME_SLOT_MIN then
            slots = slots + 1
            local entry = { slot = Market.SLOTS[index][3], count = #list, median = MedianOf(list) }
            if not most or entry.median > most.median then most = entry end
            if not least or entry.median < least.median then least = entry end
        end
    end
    if scans < Market.TIME_SCANS or slots < 2 then return nil, "few", scans end
    local percent = least.median > 0 and Core.Round((most.median - least.median) / least.median * 100) or 0
    return { scans = scans, most = most, least = least, percent = percent, slots = slots }
end

-- Zeile für das Seitenteil (ganzer Markt dieses Auktionshauses, nicht je Gegenstand); nil ohne ezCores Protokoll
-- und ohne einen einzigen Komplett-Scan (dann gibt es nichts zu sagen, und die Zeile schöbe im Reiter Verkaufen die
-- Taschenliste nur nach unten).
function Market.DayTimeLine()
    local prices = Prices()
    if not (prices and type(prices.Captures) == "function") then return nil end
    local times, _, scans = Market.DayTimes(Core.Call(prices.Captures))
    if not times then
        if not (scans and scans > 0) then return nil end
        return L.MARKET_TIME_FEW:format(Core.Plural(scans, L.MARKET_SCANS_ONE, L.MARKET_SCANS_MANY), Market.TIME_SCANS,
            Market.TIME_SLOT_MIN)
    end
    local count = Core.Plural(times.scans, L.MARKET_SCANS_ONE, L.MARKET_SCANS_MANY)
    if times.percent < Market.WEEK_PERCENT then return L.MARKET_TIME_EVEN:format(count) end
    return L.MARKET_TIME_MORE:format(L["DAYTIME_" .. times.most.slot], Core.Percent(times.percent),
        L["DAYTIME_" .. times.least.slot], count)
end

---------------------------------------------------------------------------
-- Entzaubern gegen den Auktionspreis (AUC-19 – Empfehlung umgesetzt, Antwort offen): nur als Vergleichszeile in
-- Taschenliste und Seitenteil, nie im Item-Tooltip (dort zeigt ezCraft den Wert, Abschnitt „Zerlegen“)
---------------------------------------------------------------------------

-- → { value, price, label, unverified, missing, known } oder nil und Grund: "off" (Schalter salvageCompare aus),
-- "none" (nicht zerlegbar oder ohne ezCores Rechnung), "price" (kein Auktionspreis zum Vergleich), "lower" (der
-- Auktionspreis ist höher). price = Auktionspreis je Stück; ohne Angabe der Marktwert, sonst der Tiefstpreis.
function Market.Salvage(item, price)
    if not ns.Enabled("salvageCompare") then return nil, "off" end
    local S = Core.Salvage
    if not (item and type(S) == "table" and type(S.Value) == "function") then return nil, "none" end
    local value, detail = Core.Call(S.Value, item, 1)
    value = Core.Num(value)
    if not (value and value > 0 and type(detail) == "table") then return nil, "none" end
    price = Core.Num(price)
    if not (price and price > 0) then
        local info = ns.PriceInfo(item)
        price = info and (Core.Num(info.market) or Core.Num(info.min))
    end
    if not (price and price > 0) then return nil, "price" end
    if value <= price then return nil, "lower" end
    local result = type(detail.result) == "table" and detail.result or {}
    local label = type(S.Label) == "function" and Core.Call(S.Label, result.kind or "disenchant")
    return { value = value, price = price, label = type(label) == "string" and label or L.SALVAGE_LABEL,
        unverified = result.unverified == true, missing = Core.Num(detail.missing) or 0, known = result.known }
end

-- Zeile „Entzaubern ≈ 2 g 10 s – mehr als der Auktionspreis (1 g 50 s)“ und die Quelle darunter (ezCores
-- Entzauber-Tabelle mit deinen erfassten Preisen; „ungeprüft“ in ezCores Wortlaut, solange die Tabelle es ist).
function Market.SalvageLines(item, price)
    local s = Market.Salvage(item, price)
    if not s then return {} end
    local parts = { L.SALVAGE_SOURCE }
    if s.missing > 0 then parts[#parts + 1] = Core.Plural(s.missing, L.SALVAGE_MISSING_ONE, L.SALVAGE_MISSING_MANY) end
    if s.known == false then parts[#parts + 1] = L.SALVAGE_NOT_KNOWN end
    if s.unverified then parts[#parts + 1] = Core.L.SALVAGE_UNVERIFIED or "" end
    return { L.SALVAGE_MORE:format(s.label, ns.Money(s.value), ns.Money(s.price)), table.concat(parts, "; ") }
end

---------------------------------------------------------------------------
-- Punkte für den Graph (Core.NewGraph)
---------------------------------------------------------------------------

-- Abwandlung (Zufallssuffix) eines Schlüssels aus Blizzards Ergebnissen bzw. Verkaufsbereich.
function Market.HasVariant(itemKey)
    local suffix = type(itemKey) == "table" and itemKey.itemSuffix
    return not Core.IsSecret(suffix) and type(suffix) == "number" and suffix ~= 0
end

-- Tagesname eines Tages aus ezCores Verlauf (Tag in Serverzeit: Mittag des Tages, als UTC geschrieben).
function Market.DayLabel(day)
    day = Core.Num(day)
    if not day then return "?" end
    local prices = Prices()
    local today = prices and type(prices.Day) == "function" and Core.Call(prices.Day)
    if today == day then return L.MARKET_TODAY end
    return date("!" .. (Core.L.DATE_DAY or "%d.%m."), day * DAY + DAY / 2)
end

-- punkte: je Kalendertag des Zeitraums einer ({ x = Tag, y = Tiefstpreis | nil (Lücke), high, bar = Menge,
-- point = Tagespunkt aus Prices.History }); opts für graph:SetData (Achse über den ganzen Zeitraum, Median als
-- Hilfslinie, Händlerpreis gestrichelt, wenn er ins Bild passt); zustand: "ok" | "none" (kein Verlauf) | "few"
-- (weniger als Market.GRAPH_DAYS Tage) | "variant" (Abwandlungen laufen zusammen: Hinweis statt Graph).
-- Abwandlung (variant): item nennt sie (itemKey mit itemSuffix oder Link); ezCore führt seit Welle 23b eigene
-- Tagespunkte je Abwandlung (Prices.History → zweiter Wert "variant", Prices.Stats wählt dieselben Punkte). Dann zeigt
-- der Graph deren Verlauf; nur ohne eigene Punkte bleibt der Hinweis.
function Market.GraphPoints(item, variant)
    local prices = Prices()
    if not (prices and item and type(prices.History) == "function") then return {}, {}, "none", nil end
    local days = Market.Days()
    local history, which = Core.Call(prices.History, item, days)
    local stats = Market.Stats(item)
    local today = Core.Call(prices.Day) or math.floor(time() / DAY)
    local first = today - days + 1
    local byDay, count = {}, 0
    for _, p in ipairs(type(history) == "table" and history or {}) do
        local day, low = type(p) == "table" and Core.Num(p.day), type(p) == "table" and Core.Num(p.min)
        if day and low and low > 0 and day >= first and day <= today then
            if not byDay[day] then count = count + 1 end
            byDay[day] = p
        end
    end
    if count == 0 then return {}, {}, "none", stats end
    if (variant and which ~= "variant") or (stats and stats.mixed) then return {}, {}, "variant", stats end
    local points = {}
    for day = first, today do
        local p = byDay[day]
        points[#points + 1] = { x = day, y = p and p.min or nil, high = p and Core.Num(p.high) or nil,
            bar = p and Core.Num(p.quantity) or nil, point = p, day = day }
    end
    local opts = { xMin = first, xMax = today, guides = {}, dashed = {} }
    local median = stats and Core.Num(stats.median)
    if median then opts.guides[1] = median end
    local vendor = Core.VendorPrice(Core.ItemID(item) or item)
    local low = stats and Core.Num(stats.low)
    if vendor and vendor > 0 and (not low or vendor >= low / 4) then opts.dashed[1] = vendor end
    return points, opts, count < Market.GRAPH_DAYS and "few" or "ok", stats, count
end

-- Tooltip eines Tagespunkts: Titel, Zeilen (Tiefstpreis, Höchst, Menge, Quelle mit Art der Erfassung).
function Market.PointTip(entry)
    local p = type(entry) == "table" and entry.point
    if type(p) ~= "table" then return nil end
    local lines = { L.MARKET_TIP_LOW:format(ns.Money(p.min)) }
    if Core.Num(p.high) and p.high > p.min then lines[#lines + 1] = L.MARKET_TIP_HIGH:format(ns.Money(p.high)) end
    if Core.Num(p.quantity) then lines[#lines + 1] = L.MARKET_TIP_QTY:format(p.quantity) end
    lines[#lines + 1] = L.MARKET_SOURCE:format(Market.DaySource(p))
    return Market.DayLabel(entry.day), lines[1], lines[2], lines[3], lines[4]
end

-- Quelle eines Tagespunkts: „deine Erfassungen (Komplett-Scan, Suche)“ – für den Tooltip und „Als Text kopieren“.
function Market.DaySource(p)
    local kinds = {}
    for _, kind in ipairs({ "scan", "browse", "search" }) do
        if type(p) == "table" and type(p.kinds) == "table" and p.kinds[kind] then kinds[#kinds + 1] = Core.L["PRICES_KIND_" .. kind] end
    end
    local source = Core.L.PRICES_SOURCE_OWN or ""
    if #kinds > 0 then source = source .. " (" .. table.concat(kinds, ", ") .. ")" end
    return source
end

---------------------------------------------------------------------------
-- Langzeit-Verlauf in Wochen (V1 aus docs/archiv/eroerterung-datenbank.md, vom Nutzer am 16.11.2026 freigegeben; Welle 23)
---------------------------------------------------------------------------
-- ezCore verdichtet die älteren Tage beobachteter Gegenstände zu Wochenpunkten (Prices.Weeks, bis Prices.WeeksMax()
-- Wochen, ab Werk 26) – bis Welle 23 zeigte sie niemand. Der Graph im Seitenteil schaltet zwischen Tagen und Wochen um
-- (Knopf „Wochen“/„Tage“ unter dem Graph; seit der Einstellungs-Prüfung vom 19.11.2026 ohne eigenen Schalter – ob es
-- Wochen gibt, regelt ezCores „Preisverlauf“).

Market.GRAPH_WEEKS = 3    -- Wochen-Graph erst ab drei Wochen mit Punkten

-- Woche eines Tags wie ezCore sie zählt (Prices.WeekOf: Wochen beginnen am Montag; die Regel steht nur dort –
-- ohne Prices.WeekOf gibt es keine Wochenansicht, Market.WeeksAvailable meldet "off")
local function WeekOf(prices, day)
    return prices.WeekOf(day)
end

-- Gibt es für diesen Gegenstand einen Wochen-Verlauf? → true | false, Grund: "off" (ezCores Schalter „Preisverlauf:
-- ältere Wochen behalten“ aus oder Prices.Weeks/WeekOf fehlt), "none" (Schalter an, aber ezCores Auswahl
-- „Preisverlauf: Wochen behalten“ steht auf 0 – Prices.WeeksMaxSetting), "variant" (Wochen führt ezCore je Gegenstand, nicht je
-- Abwandlung), "mixed" (Welle 26 – Empfehlung umgesetzt, Antwort offen: Abwandlungen laufen im allgemeinen Verlauf
-- zusammen, Stats.mixed – die Wochen mischten dann dieselben Preise, deretwegen die Tage wegfallen; eigener Grund,
-- weil es dann auch keinen Graph in Tagen gibt, auf den der Tooltip zu "variant" verweist),
-- "unwatched" (nicht beobachtet und noch keine Woche – ezCore verdichtet nur Beobachtetes,
-- Prices.IsObserved). Leitlinie 11: der Knopf bleibt sichtbar und sein Tooltip sagt den Grund.
function Market.WeeksAvailable(item, variant)
    local prices = Prices()
    if not (prices and item and type(prices.Weeks) == "function" and type(prices.WeeksMax) == "function"
        and type(prices.WeekOf) == "function") then
        return false, "off"
    end
    if (Core.Num(Core.Call(prices.WeeksMax)) or 0) <= 0 then
        local setting = type(prices.WeeksMaxSetting) == "function" and Core.Num(Core.Call(prices.WeeksMaxSetting))
        if setting == 0 then return false, "none" end
        return false, "off"
    end
    if variant then return false, "variant" end
    local stats = Market.Stats(item)
    if stats and stats.mixed then return false, "mixed" end
    local weeks = Core.Call(prices.Weeks, item)
    if type(weeks) == "table" and #weeks > 0 then return true end
    local observed = type(prices.IsObserved) == "function" and Core.Call(prices.IsObserved, item)
    if observed == false then return false, "unwatched" end
    return true
end

-- Punkte je Kalenderwoche: die älteren aus ezCores Wochenpunkten (Prices.Weeks: Tief, Hoch, Median der Tagestiefst,
-- Menge, Tage), die jüngeren aus den Tagespunkten (Prices.History) zur Woche zusammengefasst – so reicht die Linie bis
-- heute. Die angefangene Woche aus ezCore (open) und Tage derselben Woche gehen zusammen: ihr Median zählt so oft, wie
-- sie Tage hat (eine Näherung – ezCore hält von ihr nur den Median).
-- → punkte ({ x = Woche, y = Median der Tagestiefst | nil (Lücke), high, bar = Menge, week = { … } }), opts für
-- graph:SetData (Median aller Wochen als Hilfslinie), zustand ("ok" | "none" | "few"), Zahl der Wochen mit Punkten.
function Market.WeekPoints(item)
    local prices = Prices()
    if not (prices and item and type(prices.Weeks) == "function" and type(prices.WeekOf) == "function") then
        return {}, {}, "none", 0
    end
    local byWeek, open = {}, {}
    for _, w in ipairs(Core.Call(prices.Weeks, item) or {}) do
        local n, median = type(w) == "table" and Core.Num(w.week), type(w) == "table" and Core.Num(w.median)
        if n and median then
            local entry = { week = n, low = Core.Num(w.low) or median, high = Core.Num(w.high) or median, median = median,
                quantity = Core.Num(w.quantity) or 0, days = Core.Num(w.days) or 0 }
            byWeek[n] = entry
            if w.open then
                entry.lows = {}
                for _ = 1, math.max(1, entry.days) do entry.lows[#entry.lows + 1] = median end
                open[n] = entry
            end
        end
    end
    for _, p in ipairs(type(prices.History) == "function" and Core.Call(prices.History, item) or {}) do
        local day, low = type(p) == "table" and Core.Num(p.day), type(p) == "table" and Core.Num(p.min)
        if day and low and low > 0 then
            local n = WeekOf(prices, day)
            local entry = byWeek[n]
            if not entry then
                entry = { week = n, lows = {}, quantity = 0, days = 0 }
                byWeek[n], open[n] = entry, entry
            end
            if open[n] then
                local high = math.max(Core.Num(p.high) or low, low)
                entry.lows[#entry.lows + 1] = low
                entry.low = math.min(entry.low or low, low)
                entry.high = math.max(entry.high or high, high)
                entry.quantity = math.max(entry.quantity or 0, Core.Num(p.quantity) or 0)
                entry.days = entry.days + 1
            end
        end
    end
    local first, last, count, medians = nil, nil, 0, {}
    for n, entry in pairs(byWeek) do
        if entry.lows then
            entry.median = MedianOf(entry.lows)
            entry.lows = nil
        end
        count = count + 1
        if not first or n < first then first = n end
        if not last or n > last then last = n end
        medians[#medians + 1] = entry.median
    end
    if count == 0 then return {}, {}, "none", 0 end
    local today = Core.Num(Core.Call(prices.Day)) or math.floor(time() / DAY)
    last = math.max(last, WeekOf(prices, today))
    local points = {}
    for n = first, last do
        local entry = byWeek[n]
        points[#points + 1] = { x = n, y = entry and entry.median or nil, high = entry and entry.high or nil,
            bar = entry and entry.quantity or nil, week = entry, day = n * 7 - 3 }
    end
    local opts = { xMin = first, xMax = last, guides = {}, dashed = {} }
    local median = MedianOf(medians)
    if median then opts.guides[1] = median end
    return points, opts, count < Market.GRAPH_WEEKS and "few" or "ok", count
end

-- Tooltip eines Wochenpunkts: „Woche ab 3.11.“, Median der Tagestiefst, Tief und Hoch, Menge, Zahl der Tage, Quelle.
function Market.WeekTip(entry)
    local w = type(entry) == "table" and entry.week
    if type(w) ~= "table" then return nil end
    local lines = { L.MARKET_WEEK_TIP_MEDIAN:format(ns.Money(w.median)) }
    if Core.Num(w.low) and Core.Num(w.high) then
        lines[#lines + 1] = L.MARKET_WEEK_TIP_RANGE:format(ns.Money(w.low), ns.Money(w.high))
    end
    if (Core.Num(w.quantity) or 0) > 0 then lines[#lines + 1] = L.MARKET_TIP_QTY:format(w.quantity) end
    lines[#lines + 1] = L.MARKET_SOURCE:format(Market.WeekSource(w))
    -- Montag der Woche als Datum (wie Market.DayLabel, aber nie „heute“)
    local monday = date("!" .. (Core.L.DATE_DAY or "%d.%m."), (Core.Num(entry.day) or 0) * DAY + DAY / 2)
    return L.MARKET_WEEK_TIP_TITLE:format(monday), lines[1], lines[2], lines[3], lines[4]
end

-- Quelle eines Wochenpunkts: „deine Erfassungen, aus 7 Tagen“ – für den Tooltip und „Als Text kopieren“.
function Market.WeekSource(w)
    local days = type(w) == "table" and Core.Num(w.days) or 0
    return (Core.L.PRICES_SOURCE_OWN or "") .. ", " .. Core.Plural(days, L.MARKET_FROM_ONE, L.MARKET_FROM_MANY)
end

---------------------------------------------------------------------------
-- „Als Text kopieren“ (V5 aus docs/archiv/eroerterung-datenbank.md, vom Nutzer am 16.11.2026 freigegeben; Welle 24)
---------------------------------------------------------------------------
-- Die Zahlen des Seitenteils „Markt“ als EINE Tabelle für ezCores Kopierfeld (Core.TableText/Core.CopyAsText aus Welle
-- 23d) – keine eigene Ausgabe (Leitlinie 2). Je Zeile eine Art, jede Gruppe älteste zuerst:
--   Tag     ezCores Tagespunkte (Prices.History, alle gemerkten Tage; für Abwandlungen dieselbe Regel wie der Graph)
--   Woche   der Langzeit-Verlauf (Market.WeekPoints, V1), solange es für den Gegenstand Wochen gibt
--   Verkauft, Gekauft, …  deine Auktionen mit diesem Gegenstand (ezCore.History("auction"), alle Charaktere)
-- Jede Zeile nennt ihre Quelle (Spalte „Quelle“, Leitlinie 11); Beträge in Gold (Spalte „money“), Datum als
-- Jahr-Monat-Tag, das jede Tabellenkalkulation liest. „Käufer/Verkäufer“ ist eine Namens-Spalte (personal): ab Werk nicht
-- im Text, das Häkchen „Namen mitnehmen“ im Kopierfeld nimmt sie auf (Frage E6 des Berichts, vom
-- Nutzer am 16.11.2026 nach Empfehlung entschieden).

-- Tag aus ezCores Verlauf (Tag in Serverzeit, als UTC geschrieben) als „2026-11-14“
function Market.CopyDay(day)
    day = Core.Num(day)
    if not day then return nil end
    return date("!%Y-%m-%d", day * DAY + DAY / 2)
end

function Market.CopyColumns()
    local money = "money"   -- Gold mit vier Stellen (ezCores Spalte, Core.GoldDecimal)
    return {
        { key = "kind", title = L.COPY_COL_KIND },
        { key = "date", title = L.COPY_COL_DATE },
        { key = "low", title = L.COPY_COL_LOW, format = money },
        { key = "high", title = L.COPY_COL_HIGH, format = money },
        { key = "median", title = L.COPY_COL_MEDIAN, format = money },
        { key = "quantity", title = L.COPY_COL_QTY },
        { key = "amount", title = L.COPY_COL_AMOUNT, format = money },
        { key = "who", title = L.HISTORY_COL_WHO, personal = true },
        { key = "source", title = L.COPY_COL_SOURCE },
    }
end

-- Gehört ein Eintrag des Auktionsverlaufs zu diesem Gegenstand? Über den Link, sonst über einen der Namen (Verkäufe
-- kommen aus der Post nur mit Namen).
function Market.SameItem(e, itemID, names)
    if type(e) ~= "table" or Core.IsSecret(e.item) then return false end
    if type(e.link) == "string" and e.link ~= "" then return Core.ItemID(e.link) == itemID end
    if type(e.item) ~= "string" or e.item == "" then return false end
    for _, name in ipairs(type(names) == "table" and names or {}) do
        if e.item == name then return true end
    end
    return false
end

-- Zeilen zum Gegenstand. item = Nummer oder Schlüssel (mit Suffix bei Abwandlungen), variant wie bei GraphPoints,
-- opts.name = angezeigter Name (findet Verkäufe ohne Link), opts.any = true: nur prüfen, ob es etwas gibt (hört nach dem
-- ersten Abschnitt mit Zeilen auf – für den Zustand des Knopfs bei jedem Neuzeichnen). → Liste der Zeilen (leer ohne
-- Zahlen), grund: "variant", wenn erfasste Tage nach der Regel des Graphen wegfallen (Abwandlungen laufen zusammen)
function Market.CopyRows(item, variant, opts)
    opts = type(opts) == "table" and opts or {}
    local rows, reason = {}, nil
    local itemID = Core.ItemID(item) or Core.Num(item)
    local prices = Prices()
    if prices and item and type(prices.History) == "function" then
        local history, which = Core.Call(prices.History, item)
        local stats = Market.Stats(item)
        local days = {}
        for _, p in ipairs(type(history) == "table" and history or {}) do
            local day, low = type(p) == "table" and Core.Num(p.day), type(p) == "table" and Core.Num(p.min)
            if day and low and low > 0 then days[#days + 1] = p end
        end
        if (variant and which ~= "variant") or (stats and stats.mixed) then
            -- erfasst, aber wie beim Graph nicht gezeigt: der Tooltip des grauen Knopfs nennt diesen Grund
            if days[1] then reason = "variant" end
        else
            table.sort(days, function(a, b) return a.day < b.day end)
            for _, p in ipairs(days) do
                rows[#rows + 1] = { kind = L.COPY_KIND_DAY, date = Market.CopyDay(p.day), low = p.min, high = Core.Num(p.high),
                    quantity = Core.Num(p.quantity), source = Market.DaySource(p) }
            end
        end
    end
    if opts.any and rows[1] then return rows, reason end
    if itemID and not variant and Market.WeeksAvailable(itemID, false) then
        for _, point in ipairs((Market.WeekPoints(itemID))) do
            local w = point.week
            if type(w) == "table" then
                rows[#rows + 1] = { kind = L.COPY_KIND_WEEK, date = Market.CopyDay(point.day), low = w.low, high = w.high,
                    median = w.median, quantity = (Core.Num(w.quantity) or 0) > 0 and w.quantity or nil,
                    source = Market.WeekSource(w) }
            end
        end
    end
    if opts.any and rows[1] then return rows, reason end
    local source, History = Core.History, ns.History
    if itemID and History and type(source) == "table" and type(source.List) == "function" then
        local names = {}
        for _, name in ipairs({ opts.name or false, Core.ItemNameByID(itemID) or false }) do
            if type(name) == "string" and name ~= "" then names[#names + 1] = name end
        end
        local list = Core.Call(source.List, "auction", { match = function(e) return Market.SameItem(e, itemID, names) end,
            limit = opts.any and 1 or nil })
        list = type(list) == "table" and list or {}
        for i = #list, 1, -1 do   -- ezCore liefert die neuesten zuerst
            local e = list[i]
            rows[#rows + 1] = { kind = History.TypeName(e), date = History.CopyTime(e), quantity = Core.Num(e.n),
                amount = History.Amount(e), who = History.WhoText(e), source = L.COPY_SOURCE_HISTORY }
        end
    end
    return rows, reason
end

---------------------------------------------------------------------------
-- Beobachten (Frage 37): Einkaufslisten und eigene Verkäufe halten 30 statt 14 Tage Verlauf
---------------------------------------------------------------------------

Market.WATCH_TIME = 60    -- die Menge der beobachteten Gegenstände höchstens einmal je Minute neu bilden
local watchSet, watchAt

-- { [itemID] = true }: Einträge aller Einkaufslisten mit Gegenstand, die gemerkten eigenen Verkäufe dieses
-- Auktionshauses und – bei offenem Auktionshaus – die eigenen Auktionen. ezCore fragt beim Kürzen des Verlaufs
-- für tausende Gegenstände in einem Bild: darum nur Nachschlagen in einer vorberechneten Menge.
function Market.WatchSet(fresh)
    local up = Core.Uptime and Core.Uptime() or time()
    if fresh or not watchSet or not watchAt or up < watchAt or up - watchAt >= Market.WATCH_TIME then
        local set = {}
        for _, list in ipairs(ns.db and ns.db.lists or {}) do
            for _, entry in ipairs(type(list) == "table" and list.items or {}) do
                local id = type(entry) == "table" and Core.Num(entry.itemID)
                if id then set[id] = true end
            end
        end
        if ns.db then
            for itemID in pairs(ns.RealmData().posts) do
                if Core.Num(itemID) then set[itemID] = true end
            end
        end
        if ns.Undercut and ns.AuctionHouseShown() then
            for _, auction in ipairs(ns.Undercut.Owned()) do
                local id = type(auction) == "table" and type(auction.itemKey) == "table" and Core.Num(auction.itemKey.itemID)
                if id then set[id] = true end
            end
        end
        watchSet, watchAt = set, up
    end
    return watchSet
end

function Market.IsWatched(itemID)
    return Market.WatchSet()[itemID] == true
end

local prices = ns.Prices()
if prices and type(prices.Watch) == "function" then prices.Watch(ADDON, Market.IsWatched) end
ns.Listen("LISTS_CHANGED", function() watchAt = nil end)
ns.On("OWNED_AUCTIONS_UPDATED", function() watchAt = nil end)

-- Für andere Module und spätere Pakete (AH-20, AH-22, AH-29): dieselbe Bewertung über ezCore.API("ezAuction").
ns.API.Judge = function(item, price)
    local judgement = Market.Judge(item, price)
    if not judgement then return nil end
    return judgement.verdict, judgement.percent, judgement.median, judgement.days
end
