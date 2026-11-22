local ADDON, ns = ...
local Core = ezCore

--[[
    Preis-Wissen (wie das Item-Wissen): Auktionspreise aus Blizzards eigenem Auktionshaus, eine Quelle für
    ezAuction (Preisvorschlag, Unterbieten, Schnäppchen, Tooltip-Zeile), ezCraft (Materialkosten), ezBag (Wert
    der Tasche) und ezMail (Wert der Anhänge). Ohne Auctionator.

    Gelernt wird aus allem, was das Auktionshaus ohnehin zeigt – der Spieler muss nichts extra tun:
      * Komplett-Scan (C_AuctionHouse.ReplicateItems, Blizzard erlaubt ihn alle 15 Minuten): Prices.Scan()
      * jede Suche nach Waren und Gegenständen (COMMODITY_/ITEM_SEARCH_RESULTS_UPDATED)
      * die Übersicht nach einer Suche (AUCTION_HOUSE_BROWSE_RESULTS_*: Tiefstpreis je Gegenstand)
    Gespeichert je Bereich (Realm + Seite, Keys.Market) im Träger ezMarket (ezMarketDB, DBMarket.lua; ohne Träger still
    in ezCoreDB.market), mit kurzem Verlauf als Zahlenreihe (ein Tag je sechs Werte, Spalten hcols). Den alten Speicher
    ezCoreDB.prices übernimmt beim ersten Anmelden ein Auftrag (Entwurf Frage S1, Variante b); bis dahin lesen die
    Preise neu über alt.

      Prices.Get(item)          → { min, market, quantity, seen, source, kind } oder nil   (item: itemID, Link oder
                                  itemKey); min = günstigster Stückpreis, market = Marktwert (Mittel der günstigsten
                                  25 % der angebotenen Menge), beides in Kupfer. W-51: source = "own" (nur eigene
                                  Erfassungen – eine fremde Preis-Auskunft gibt es nicht, DG-22), kind = Art der
                                  letzten Erfassung ("scan" Komplett-Scan, "browse" Übersicht, "search" Einzelsuche)
      Prices.SourceText(info)   → „laut deinen Erfassungen (Komplett-Scan, vor 2 Std.)“ oder nil
      Prices.Value(item, anzahl) → Marktwert × Anzahl oder nil (unverändert: Taschenwert, Materialkosten und der
                                  Wert der Anhänge rechnen weiter mit dem Marktwert)
      Prices.History(item, tage) → { { time, day, min, market, high, quantity, kinds } … } älteste zuerst (mit tage
                                  nur die letzten tage Kalendertage, ohne Angabe alle gemerkten, bis 30); time =
                                  Beginn des Tages (Sekunden, Serverzeit), high = höchster Tagespreis, quantity =
                                  größte gesehene Menge, kinds = { scan = true, browse = true, search = true }.
                                  Zweiter Rückgabewert (A21, Welle 23b): "variant", wenn item eine Abwandlung nennt (Link
                                  mit Zufallssuffix oder Bonus-IDs, itemKey mit itemSuffix) und sie eigene Tagespunkte hat
                                  (höchstens Prices.HISTORY_DAYS Tage), sonst "item" (allgemeiner Verlauf)
      Prices.Stats(item, tage)  → { median, low, high, daysSeen, daysCaptured, usualQuantity, points, source, mixed }
                                  oder nil – eine Rechnung über die letzten tage (Standard 14) Kalendertage: Median,
                                  Tief und Hoch der Tages-Tiefstpreise, Tage gesehen (Komplett-Scan oder Übersicht;
                                  Einzelsuchen zählen nicht), Tage erfasst (Protokoll), übliche Menge (Median),
                                  mixed = true, wenn Abwandlungen im allgemeinen Verlauf zusammenlaufen; quantityLow und
                                  quantityHigh (A18, Welle 23b) = unteres und oberes Viertel der Tagesmengen (nächster
                                  Rang) für „Üblich: 40 bis 120 Stück“. Die Tage erfasst zählt Prices.CapturedDays ohne
                                  Kopie des Protokolls, je Protokoll zwischengespeichert (A19)
      Prices.Captures(tage)     → Protokoll der Erfassungen dieses Auktionshauses { { day, hour, weekday, kind, n,
                                  count, time } … } – je Tag, Stunde (Serverzeit) und Art ein Eintrag (NEU-05); n = erfasste
                                  Gegenstände, count (A25, Welle 23b) = Zahl der Erfassungen im Eintrag (je Komplett-Scan
                                  bzw. Einzelsuche eine, bei der Übersicht je Ergebnispaket; Einträge von vorher: 1)
      Prices.CapturedDays(ab)   → Zahl der Tage ab Tag ab mit Komplett-Scan oder Übersicht im Protokoll (A19)
      Prices.Day(zeit)          → Tag (Serverzeit), Stunde, Wochentag (0 = Sonntag … 6 = Samstag)
      Prices.Weekday(tag)       → Wochentag eines Tags aus Prices.Day (A17, Welle 23b; eine Regel für alle)
      Prices.Each(fn, seit)     → Anzahl; fn(itemID, info) für jeden Preis dieses Auktionshauses, info in der Form von
                                  Prices.Get (allgemeiner Satz); seit = nur seit diesem Stempel der PC-Uhr erfasste; fn → true bricht
                                  ab (A20, Welle 23b)
      Prices.Today(fn)          → wie Each, nur die Preise von heute (Tagesgrenze wie Prices.Day); Prices.TodayStart() →
                                  Beginn des heutigen Server-Tags als Stempel der PC-Uhr (Core.Time.TodayStart)
      Prices.BagItems(taschen)  → { Link | itemID … } handelbare Taschen-Gegenstände (taschen wie Core.ForEachBagItem,
                                  z. B. "sell"); dieselbe Liste speist den Anbieter „ezCore.bags“ (A22, Welle 23b)
      Prices.FEATURES           Merkmale ohne eigenen Funktionsnamen für Core.Has (z. B. "Prices.FEATURES.queueClick")
      Prices.Watch(owner, fn)   fn(itemID) → true: „beobachtet“ – der Verlauf hält 30 statt 14 Tage (Frage 37);
                                  ezCore selbst beobachtet alles, was ein Twink besitzt (Inventory.OwnedSet). Der
                                  Marktwert rechnet trotzdem nur mit den letzten 14 Tagen (Taschenwert bleibt gleich)
      Prices.IsObserved(item, frisch) → beobachtet? Die Besitzmenge gilt bis zu Prices.OWNED_TIME Sekunden
      Prices.Size()             → { items, points, captures, houses, bytes, where } – Größe des Preis-Wissens in seiner
                                  Ablage (where: "carrier" = ezMarket, "core" = ezCoreDB.market, "memory")
      Prices.Scan()             → true, oder false und Grund ("closed", "wait", "busy", "unsupported")
                                  Schlägt Blizzards Aufruf fehl, gilt keine Wartezeit ("unsupported", gleich wieder
                                  versuchbar). Bleibt die Liste aus, endet das Warten nach Prices.SCAN_TIMEOUT Sekunden
                                  mit PRICES_SCAN_DONE (0, "timeout"); kommt sie danach doch noch, wird sie gelesen.
                                  Eine Liste ohne eigenen Scan (ein anderes Addon hat ihn ausgelöst) wird gelesen und
                                  mit Grund "other" gemeldet – höchstens eine je Sperrfrist (Blizzard meldet dieselbe
                                  Liste mehrmals).
      Prices.ScanReadyIn()      → Sekunden bis zum nächsten erlaubten Komplett-Scan (0 = jetzt); der Zeitpunkt gilt
                                  kontoweit (Blizzards Sperre gilt für das ganze Konto, nicht je Realm und Fraktion)
      Prices.IsScanning()       → läuft?, gelesen, gesamt
      Prices.IsOpen()           → Auktionshaus offen?
      Prices.Learn(item, { { preis, menge } … }) – für eigene Abfragen eines Moduls (selten nötig); item: itemID,
                                  Link oder itemKey – mit Abwandlung („des Bären“) bekommt die ihren eigenen Preis
      Prices.VariantOf(item)    → Schlüssel der Abwandlung oder nil in der alten Form („1200“, „b1,2“) – gebildet aus
                                  Keys.Variant (eine Form für Link und itemKey); gespeichert wird unter Keys.Variant
      Prices.Prune(maxAge)      → Anzahl entfernter Einträge; läuft beim Anmelden mit Prices.MAX_AGE (30 Tage)
      Prices.Count()            → Gegenstände mit Preis in diesem Auktionshaus
      Nachrichten: PRICES_CHANGED (itemID; nil = mehrere, aus der Übersicht gesammelt einmal je CHANGED_DELAY),
                   PRICES_SCAN_PROGRESS (gelesen, gesamt), PRICES_SCAN_DONE (Anzahl, Grund – nil, "timeout" oder "other"),
                   PRICES_QUEUE_CHANGED (Owner), PRICES_QUEUE_USER (info), PRICES_RULES_CHANGED (Regel)

    Welle 12 (Paket „Preise ohne fremde Quelle erfassen, eine Abfrage-Warteschlange“; AH-01, AH-03, AH-04, AH-06):
      Komplett-Scan (AH-01, führt EC-48 fort): je Zeile zusätzlich Link (GetReplicateItemLink) und hasAllInfo (18.
                                  Rückgabe, laut Probe X2 vorhanden); Abwandlungen lernen getrennt (Prices.VariantOf),
                                  der allgemeine Satz bleibt der Preis über alle Angebote. Zeilen ohne volle Daten werden
                                  einmal nachgefordert (C_Item.RequestLoadItemDataByID, nach Prices.SCAN_RETRY_DELAY
                                  Sekunden erneut gelesen), sonst ausgelassen und gezählt. Gelesen wird in Scheiben
                                  (Prices.SCAN_SLICE_ROWS je Bild) mit Zeitmessung; kostet eine Scheibe im Mittel mehr als
                                  Prices.SCAN_FRAME_MS, liest der Scan den Link nur noch für Waffen und Rüstung.
      Prices.ScanLinks(art)     → Art: "all" (Link je Zeile), "gear" (nur Waffen und Rüstung), "none"; ohne Angabe nur lesen
      Prices.ScanStats()        → { rows, slices, ms, max, avg, links, linkMode, variants, retried, skipped, auto } des
                                  letzten Scans oder nil; dieselbe Zahl steht in /ez debug („Scan: n Zeilen, x ms je Scheibe“)
      Prices.ScanYields()       → Name des Addons, das den Komplett-Scan schon nutzt (Rücksicht-Schlüssel auctionScan),
                                  sonst nil; Prices.Scan({ auto = true }) startet dann nicht ("other") – ein Klick schon
      Prices.ItemKey(item)      → Basis, voll: Blizzards ItemKey { itemID, itemLevel, itemSuffix, battlePetSpeciesID }
                                  (über C_AuctionHouse.MakeItemKey, sonst dieselbe Tabelle); Basis ohne Stufe und Suffix
      Herkunft je Tagespunkt (AH-04): scan (komplett), search (einzel), browse (Übersicht), category (Kategorie), bulk
                                  (Sammelabfrage). Marktwert (Mittel der günstigsten 25 %) nur aus scan und search;
                                  Prices.Get und Prices.Stats nennen marketFrom ("full" | "min"), fullKind und fullSeen,
                                  Prices.SourceText sagt es („Marktwert aus Tagestiefstpreisen“)
      Prices.Rules()            → Regeln des Hauses je Bereich (Kopie): copper, split, cooldown, cut, deposit[Dauer] –
                                  je { v, t, n }; gemessen bei offenem Haus (SupportsCopperValues, Antwort auf eine
                                  Warensuche, Abstand zweier angenommener eigener Scans als Obergrenze der Sperrzeit,
                                  Calculate*Deposit an bis zu Prices.DEPOSIT_SAMPLES Taschen-Gegenständen) und aus den
                                  eigenen Verkaufsabrechnungen (Anteil = Gebühr / Brutto, History „auction“ sale)
      Prices.Net(item, preis, dauer, menge) → { brutto, erloes, anteil, anzahlung, bekannt = { … }, stand = { … } }
                                  (AH-06): bei offenem Haus rechnet Blizzard die Anzahlung, sonst die gemerkten Verhältnisse
                                  (stand[teil] = { now = true } bzw. { at = Zeitpunkt }); unbekannt bleibt nil, nie
                                  geraten. erloes = brutto − anteil (die Anzahlung kommt beim Verkauf zurück)
      Prices.StandText(stand)   → „jetzt“ | „zuletzt gemessen am …“
      Prices.Coverage(menge)    → Anteil (0–1), mit Preis von heute, gesamt (menge: Liste von itemID, Link, itemKey)
      Prices.AddWatchProvider(schlüssel, fn, max)  fn() → { item … } (AH-03): Anbieter für „Beobachtetes“, je Anbieter
                                  höchstens max (Standard Prices.WATCH_MAX); ezCore meldet Taschen ("ezCore.bags") und
                                  eigene Auktionen und Verkäufe ("ezCore.auctions") selbst an
      Prices.WatchList(limit)   → { { item, itemID, from } … } ohne Doppelte; zählt für Prices.IsObserved mit
      Prices.Refresh(menge, grund) → true, Aufträge, Weg | false, Grund ("closed", "empty", "unsupported"): Preise
                                  gezielt auffrischen (ohne menge: Prices.WatchList). Weg "bulk": C_AuctionHouse.
                                  SearchForItemKeys in Stücken zu Prices.REFRESH_CHUNK (laut Probe X6 mit 1, 10 und 40
                                  Schlüsseln belegt); fehlt die Funktion oder stimmt die Antwortform nicht: "single", Suchen
                                  je Gegenstand, höchstens Prices.REFRESH_SINGLE_MAX je Aufruf. grund "click" → Rang
                                  "module", sonst "capture". Nur bei offenem Haus, immer über die Warteschlange.
      Prices.RefreshMode()      → "bulk" | "single"
      Prices.Queue              die EINE Warteschlange für alles, was Blizzards Ergebnisliste füllt (AH-03):
        Queue.Add(auftrag)      auftrag = { key|schluessel, rank|rang ("user"|"nutzer" vor "module"|"modul" vor
                                "capture"|"erfassung"), start(auftrag), cancel|abbruch(auftrag, grund), text, origin
                                (Herkunft der Ergebnisse: "browse", "category", "bulk", "search"), onResults(auftrag,
                                ergebnis, art), timeout } → Nummer oder nil, Grund. Gleicher Schlüssel: ersetzt den
                                wartenden. Eine Abfrage zur Zeit; Start erst, wenn IsThrottledMessageSystemReady (fehlt
                                sie: sofort) und das Haus offen ist.
        Queue.Done(nummer|schlüssel), Queue.Cancel(schlüssel), Queue.Owner() → { key, rank, text, origin } | { rank =
                                "user" } | nil, Queue.Pending() → Zahl wartender Aufträge
        Queue.Own(fn, …)        ruft fn so, dass die Haken auf Blizzards Suche es nicht für eine Suche des Spielers halten
        Queue.OnUserSearch(owner, fn)  fn(info): der Spieler sucht selbst (hooksecurefunc auf AuctionHouseFrame.
                                SendBrowseQuery, SendBrowseQueryInternal, QueryAll, QueryItem und RefreshSearchResults;
                                Aufrufe im selben Augenblick zählen als eine Suche) – eine laufende Erfassung ist angehalten
                                (info.paused, läuft nach Queue.USER_HOLD Sekunden neu an), eine Modul-Suche abgebrochen
                                (info.cancelled). Keine Suche des Spielers: QueryAll für die eigenen Auktionen und Gebote
                                (eigene Listen) und Blizzards Abfrage der Favoriten beim Öffnen (OnShow) – sie hält die
                                Warteschlange nur Queue.AUTO_HOLD Sekunden an (Queue.AutoQuery).
                                A23 (Welle 23b): Ein Auftrag aus einem Klick (Rang „user“/„nutzer“ oder Feld click = true;
                                Prices.Refresh mit grund "click" setzt es) wartet die Haltezeit nach einer eigenen Suche
                                (USER_HOLD) nicht ab und beendet sie; die nach Blizzards Favoriten-Abfrage (AUTO_HOLD)
                                wartet er ab, sonst bekäme er Blizzards Liste als eigene Antwort.
        Queue.Cancel(filter)    A24 (Welle 23b): statt eines Schlüssels auch { rank|rang, prefix|vorsilbe, owner } – alle
                                Aufträge, auf die jede Angabe passt (z. B. { prefix = "refresh:" }); → Anzahl
                                Ergebnisse der Übersicht und der Suchen werden weiter mitgelernt, aber nur dem laufenden
                                Auftrag zugerechnet (Herkunft und onResults); ohne Auftrag gelten sie als „Übersicht“.

    Tagespunkt (W-51): { Tag, Tiefst, Marktwert, Höchst, Menge, Arten }. Höchst ist der höchste Preis des Tages – bei
    vollständigen Listen der teuerste Preis innerhalb der günstigsten 25 % (die Spanne des Marktwerts), bei der
    Übersicht deren Tiefstpreis; Menge die größte gesehene Menge (je Art etwas anderes: Komplett-Scan und Suche
    zählen alle Angebote, die Übersicht die Summe ihrer Zeilen); Arten die Buchstaben s (Komplett-Scan),
    b (Übersicht), e (Einzelsuche). Ein vollständiger fremder Scan ist eine Replikat-Liste ohne eigenen Scan (Grund
    "other"); ein Scan über Suchen (wie der Standard-Scan von Auctionator) erscheint als Übersicht bzw. Suche.
    Tagesgrenze (Frage 37, Empfehlung umgesetzt, Antwort offen; seit dem Gesamtreview vom 18.11.2026 über Core.Time aus
    der Serveruhr, gespeicherte PC-Stempel umgerechnet – T16-NZ2): Serverzeit statt UTC (C_DateAndTime.
    GetServerTimeLocal; ohne sie UTC wie früher). Prices.Migrate() stellt beim Anmelden einmal um: Der jüngste
    Punkt jedes Gegenstands bekommt den Server-Tag seiner Erfassung (ältere behalten ihren Tag). Verlauf: 14
    Kalendertage, 30 für beobachtete Gegenstände (Prices.Watch); vorher begrenzte HISTORY_DAYS nur die Zahl der Punkte.

    Marktwert aus der Übersicht (sie nennt nur den Tiefstpreis je Gegenstand): der Marktwert einer vollständigen
    Liste (Suche, Komplett-Scan) gilt einen Tag ab ihrer Erfassung (Feld mt), danach der Median der Tages-
    Tiefstpreise aus dem Verlauf, nie unter dem heutigen Tiefstpreis. Ein Komplett-Scan, den ein anderes Addon
    auslöst, wird ebenfalls gelesen.

    Nur lesen: ezCore schreibt nichts in Blizzards Auktionshaus und kauft oder bietet nie.
]]

Core.Prices = Core.Prices or {}
local Prices = Core.Prices
-- Merkmale ohne eigenen Funktionsnamen (Welle 23b), damit Module sie über needs bzw. Core.Has prüfen können
Prices.FEATURES = { quantityRange = true, variantHistory = true, captureCount = true, queueClick = true, cancelFilter = true }

local SCAN_COOLDOWN = 15 * 60
-- Deckel des Verlaufs (Frage 37: 14 Kalendertage, 30 für beobachtete Gegenstände), der Punkte, des Protokolls, des
-- Alters und der Abwandlungen: Core.DB.LIMITS (DB.lua) – eine Stelle für alle Deckel. DBMarket.lua setzt daraus
-- Prices.HISTORY_DAYS, WATCH_DAYS, MAX_POINTS, MAX_CAPTURES, LOG_DAYS, MAX_AGE und MAX_VARIANTS.
Prices.OWNED_TIME = 60        -- so lange gilt die Besitzmenge für „beobachtet?“ (Sekunden Spielzeit)
Prices.SCAN_SLICE_ROWS = 1000   -- Einträge je Bild beim Lesen des Komplett-Scans (Obergrenze je Scheibe)
Prices.SCAN_FRAME_MS = 8         -- AH-01: kostet eine Scheibe im Mittel mehr, liest der Scan Links nur für Waffen und Rüstung
Prices.SCAN_RETRY_DELAY = 2      -- AH-01: so lange warten unvollständige Zeilen auf ihre Gegenstandsdaten (einmal)
local MARKET_SHARE = 0.25   -- Marktwert: Mittel der günstigsten 25 % der Menge
Prices.SCAN_TIMEOUT = 30    -- W-52: so lange wartet ein Komplett-Scan auf Blizzards Liste
Prices.CHANGED_DELAY = 0.3  -- W-55: Ergebnispakete der Übersicht werden so lange gesammelt, dann eine Nachricht

local floor, max, tsort = math.floor, math.max, table.sort
local isOpen, scanning = false, nil
local readAt, lateOwn = 0, false   -- zuletzt eine Liste angefangen zu lesen; eigener Scan nach der Frist noch offen

local Now = Core.Now
local DAY = 86400

---------------------------------------------------------------------------
-- Tagesgrenze in Serverzeit (Frage 37) und Protokoll der Erfassungen (NEU-05)
---------------------------------------------------------------------------

-- Abstand der Serverzeit zu UTC in Sekunden (auf Viertelstunden gerundet, höchstens 14 Stunden), aus
-- C_DateAndTime.GetServerTimeLocal; ohne sie 0 (UTC wie früher). Höchstens einmal je Minute neu gefragt;
-- fresh = true fragt sofort. Seit dem Gesamtreview (18.11.2026, T16-NZ2) rechnet das Core.Time.Zone – eine Stelle.
function Prices.DayOffset(fresh)
    return Core.Time.Zone(fresh)
end

-- Tag (Serverzeit), Stunde und Wochentag einer Uhrzeit (Standard: jetzt). Wochentag 0 = Sonntag (der 1.1.1970,
-- Tag 0, war ein Donnerstag). at ist ein Stempel der PC-Uhr (Core.Now, wie entry.t und log.t); Core.Time.Day rechnet
-- ihn mit dem Abstand der Uhren (Core.Time.Skew) auf die Serveruhr um, ohne at gilt die Serveruhr selbst
-- (T16-NZ2: vorher PC-Uhr plus Server-Zeitzone – bei falsch gehender PC-Uhr falsche Tage, Stunden, Wochentage).
function Prices.Day(at)
    local day, hour = Core.Time.Day(at, "server")
    return day, hour, Prices.Weekday(day)
end

-- A17 (Welle 23b): Wochentag eines Tags aus Prices.Day (0 = Sonntag … 6 = Samstag) – eine Regel für ezCore und die
-- Module (vorher wiederholte ezAuction sie in Market.WeekdayOf). nil ohne Zahl.
function Prices.Weekday(day)
    day = Core.Num(day)
    if not day then return nil end
    return (floor(day) + 4) % 7
end

local function Market() return Core.DB and Core.DB.Market end
local function BOr(a, b) return Core.DB.BOr(a, b) end
local function BHas(a, b) return Core.DB.BHas(a, b) end

-- Art der Erfassung als Bit (DBMarket.lua): 1 Komplett-Scan, 2 Suche, 4 Übersicht
local function ScanBit(kind) local M = Market() return M and M.SCAN[kind] end

local function KindsOfBits(bits)
    local kinds = {}
    bits = Core.Num(bits)
    if bits and bits > 0 then
        for bit, kind in pairs(Market().KIND) do if BHas(bits, bit) then kinds[kind] = true end end
    end
    return kinds
end

-- Protokoll der Erfassungen je Bereich: je Tag, Stunde und Art ein Eintrag { day, hr, wd, scan, rows, t }, die Zahl
-- der erfassten Gegenstände zählt hoch. So liegen früh Daten für Wochentag und Tageszeit vor (Entwurf 2b/2c).
local function LogCapture(store, kind, count, now)
    local bit = ScanBit(kind)
    if not (store and bit) then return end
    local log = type(store.log) == "table" and store.log or {}
    store.log = log
    local day, hour, weekday = Prices.Day(now)
    -- Übersicht und Einzelsuche wechseln sich ab (suchen, Ware anklicken, neu suchen): den Eintrag derselben Art
    -- unter allen Einträgen dieses Tags und dieser Stunde suchen, nicht nur im letzten
    for i = #log, 1, -1 do
        local e = log[i]
        if type(e) ~= "table" or e.day ~= day or e.hr ~= hour then break end
        if e.scan == bit then
            e.rows = (Core.Num(e.rows) or 0) + (count or 1)
            -- A25 (Welle 23b): Zahl der Erfassungen im Eintrag (zwei Komplett-Scans in einer Stunde = 2); Einträge
            -- von vorher ohne Feld zählen als eine
            e.cnt = (Core.Num(e.cnt) or 1) + 1
            return
        end
    end
    log[#log + 1] = { day = day, hr = hour, wd = weekday, scan = bit, rows = count or 1, cnt = 1, t = now }
    local first = day - (Prices.LOG_DAYS or Prices.WATCH_DAYS) + 1
    while #log > 0 and (#log > Prices.MAX_CAPTURES or type(log[1]) ~= "table" or (Core.Num(log[1].day) or 0) < first) do
        table.remove(log, 1)
    end
end

-- Schlüssel des Auktionshauses: Realm und Fraktion („Realm-Alliance“). Eine Stelle für das Preis-Wissen
-- und ezAuctions eigene Verkäufe; gebildet von Core.HouseKey (Names.lua), der einen Stelle für diesen Schlüssel
-- (Gesamtreview 18.11.2026, T4-NR7).
function Prices.Key()
    return Core.HouseKey()
end

-- Bereich des eigenen Charakters (Realm + Seite) in der Ablage der Preise (DBMarket.lua). → Bereich, Laufnummer
local function Store(create)
    local M = Market()
    if not M then return nil end
    return M.Area(create)
end

local ItemID = Core.ItemID

-- Marktwert aus { { preis, menge } … }: Mittel der günstigsten 25 % der Menge (mindestens ein Stück).
function Prices.MarketValue(list)
    local offers = {}
    local total = 0
    for _, offer in ipairs(list or {}) do
        local price, qty = Core.Num(offer[1]), Core.Num(offer[2]) or 1
        if price and price > 0 and qty > 0 then
            offers[#offers + 1] = { price, qty }
            total = total + qty
        end
    end
    if #offers == 0 then return nil, nil, 0 end
    tsort(offers, function(a, b) return a[1] < b[1] end)
    local want = max(1, floor(total * MARKET_SHARE + 0.5))
    local taken, sum, top = 0, 0, offers[1][1]
    for _, offer in ipairs(offers) do
        local take = math.min(offer[2], want - taken)
        sum = sum + take * offer[1]
        taken = taken + take
        top = offer[1]
        if taken >= want then break end
    end
    -- vierter Wert (W-51): teuerster Preis innerhalb der günstigsten 25 % – das Höchst des Tagespunkts
    return offers[1][1], floor(sum / taken + 0.5), total, top
end

-- Beobachtete Gegenstände (Frage 37): ihr Verlauf hält Prices.WATCH_DAYS Tage. Eine Anmeldung je owner
-- (ezAuction: eigene Auktionen und Einkaufslisten, ezCraft: Material – in ihren Paketen).
local watchers = {}

function Prices.Watch(owner, fn)
    if type(owner) ~= "string" or owner == "" then return false end
    watchers[owner] = type(fn) == "function" and fn or nil
    return true
end

-- Besitzmenge aller Charaktere und Gildenbanken, höchstens einmal je Prices.OWNED_TIME Sekunden berechnet: Trim
-- fragt „beobachtet?“ bei jedem neuen Tagespunkt eines Gegenstands mit vollem Verlauf, im Komplett-Scan also für
-- tausende Gegenstände in einem Bild; eine Zählung je Gegenstand (Inventory.CountAll) wäre dafür zu teuer.
local ownedAt, ownedSet = nil, nil

local function Owned(fresh)
    local up = Core.Uptime()
    if fresh or not ownedSet or not ownedAt or up < ownedAt or up - ownedAt >= Prices.OWNED_TIME then
        local Inv = Core.Inventory
        local ok, set = false, nil
        if Inv and Inv.OwnedSet then ok, set = pcall(Inv.OwnedSet) end
        ownedSet, ownedAt = (ok and type(set) == "table") and set or {}, up
    end
    return ownedSet
end

function Prices.IsObserved(item, fresh)
    local itemID = ItemID(item)
    if not itemID then return false end
    for owner, fn in pairs(watchers) do
        local ok, yes = Core.Try(owner, "Prices.Watch", fn, itemID)
        if ok and yes == true then return true end
    end
    -- AH-03: was ein Anbieter für „Beobachtetes“ meldet (Prices.AddWatchProvider), zählt ebenso
    if Prices.WatchSet and Prices.WatchSet(fresh)[itemID] then return true end
    return Owned(fresh)[itemID] == true
end

-- Verlauf als Zahlenreihe: je Tag NCOL Werte in der Reihenfolge der Spalten (day, lo, mv, hi, qty, scan)
local NCOL = 6

local function DropFirstDay(d)
    for _ = 1, NCOL do table.remove(d, 1) end
end

-- Tage außerhalb der Frist entfernen: 14 Kalendertage, beobachtete 30. „Beobachtet?“ wird bei jedem neuen
-- Tag gefragt, sobald der älteste älter als 14 Tage ist, also täglich für jeden regelmäßig erfassten
-- Gegenstand; darum schlägt IsObserved nur in der vorberechneten Besitzmenge nach. keep merkt die Frist am Satz.
local Fold, TrimWeeks   -- Wochenpunkte (AH-05, unten)
local CapturedDays      -- Tage erfasst ohne Kopie des Protokolls (A19, bei Prices.Captures)

local function Trim(entry, itemID, today)
    local d = entry.days
    local keepAll = today - Prices.WATCH_DAYS + 1
    -- AH-05: Tage des Beobachteten, die aus der 30-Tage-Frist fallen, werden zu Wochenpunkten verdichtet (nur bei
    -- eingeschalteten Wochenpunkten; „beobachtet?“ wird höchstens einmal je neuem Tag gefragt)
    local folding
    while #d >= NCOL and ((Core.Num(d[1]) or 0) < keepAll or #d / NCOL > Prices.MAX_POINTS) do
        if folding == nil then folding = Prices.WeeksMax() > 0 and Prices.IsObserved(itemID) or false end
        if folding then Fold(entry, d) end
        DropFirstDay(d)
    end
    if folding then TrimWeeks(entry, today) end
    local keep = today - Prices.HISTORY_DAYS + 1
    if #d >= NCOL and (Core.Num(d[1]) or 0) < keep then
        if Prices.IsObserved(itemID) then
            entry.keep = Prices.WATCH_DAYS
        else
            entry.keep = Prices.HISTORY_DAYS
            while #d >= NCOL and (Core.Num(d[1]) or 0) < keep do DropFirstDay(d) end
        end
    end
end

-- Einen Tagespunkt in eine Reihe d (Spalten hcols) eintragen: derselbe Tag wie der letzte Punkt wird zusammengeführt
-- (Tiefst = Minimum, Marktwert = der neue, Höchst und Menge = Maximum, Arten als Bit-Summe), sonst angehängt.
-- → true, wenn ein neuer Tag dazukam. Eine Stelle für den allgemeinen Verlauf und die Abwandlungen (A21, Welle 23b).
local function AddDay(d, day, min, market, top, qty, bit)
    local high = math.max(Core.Num(top) or min, min)
    local at = #d - NCOL + 1
    if at >= 1 and d[at] == day then
        if min < (Core.Num(d[at + 1]) or math.huge) or (Core.Num(d[at + 1]) or -1) < 0 then d[at + 1] = min end
        d[at + 2] = market
        local hi = Core.Num(d[at + 3]) or -1
        d[at + 3] = math.max(hi >= 0 and hi or d[at + 1], high)
        d[at + 4] = math.max(Core.Num(d[at + 4]) or 0, Core.Num(qty) or 0)
        local bits = Core.Num(d[at + 5]) or -1
        d[at + 5] = bit and BOr(bits > 0 and bits or 0, bit) or bits
        return false
    end
    d[#d + 1], d[#d + 2], d[#d + 3] = day, min, market
    d[#d + 1], d[#d + 2], d[#d + 3] = high, Core.Num(qty) or 0, bit or -1
    return true
end

-- full: der Marktwert stammt aus einer vollständigen Liste (Suche, Komplett-Scan) – dann merkt tf, wann.
-- kind: "scan", "browse" oder "search" (Herkunft im Tag und im Satz), top: Höchst dieser Erfassung.
local function Remember(store, itemID, min, market, qty, now, full, kind, top, n)
    local entry = Market().Ensure(store, itemID, n)
    entry.days = type(entry.days) == "table" and entry.days or {}
    entry.lo, entry.mv, entry.qty, entry.t = min, market or entry.mv or min, qty, now
    entry.pt = nil
    local bit = ScanBit(kind)
    if full then entry.tf, entry.fk = now, bit end
    if bit then entry.scan = bit end
    local day = Prices.Day(now)
    if AddDay(entry.days, day, min, entry.mv, top, qty, bit) then Trim(entry, itemID, day) end
end

-- V-032: Abwandlung eines Gegenstands („des Bären“, „des Adlers“) – eigener Preis statt eines gemischten.
-- Schlüssel aus Keys.Variant (Link: Zufallssuffix oder Bonus-IDs; itemKey: itemSuffix); hier in der alten Form
-- („1200“, „b1,2“), wie Prices.Get sie als variant nennt. Ohne Abwandlung nil.
function Prices.VariantOf(item)
    if Core.IsSecret(item) then return nil end
    local Keys = Core.DB and Core.DB.Keys
    if not Keys then return nil end
    local key, parts = Keys.Variant(item)
    if not key then return nil end
    if parts.sfx then return tostring(parts.sfx) end
    if parts.bon then return "b" .. table.concat(parts.bon, ",") end
    return nil
end

-- Abwandlung merken: entry.var[Keys.Variant] = { lo, mv, qty, t, sfx, il, bon } – die Bestandteile stehen als Felder
-- am Satz (Entwurf 1.5). Der allgemeine Satz nennt danach die günstigste Abwandlung, die am selben Tag gesehen wurde
-- (so bleibt Prices.Get(itemID) der Tiefstpreis über alle). onlyVariant: nur entry.var schreiben – der Komplett-Scan
-- schreibt den allgemeinen Satz danach selbst aus allen Angeboten (sonst bliebe der Höchstwert der Abwandlung als
-- Tageshöchstwert stehen; Gegenprüfung Welle 12).
-- A21 (Welle 23b): Jede Abwandlung führt dazu eigene Tagespunkte (Feld d, dieselben Spalten wie entry.days), höchstens
-- Prices.HISTORY_DAYS Kalendertage – Prices.History(Link oder itemKey mit Abwandlung) liest sie. Sätze von vorher ohne d
-- bekommen sie ab der nächsten Erfassung.
local function TrimVariantDays(d, today)
    local keep = today - Prices.HISTORY_DAYS + 1
    while #d >= NCOL and ((Core.Num(d[1]) or 0) < keep or #d / NCOL > Prices.HISTORY_DAYS) do DropFirstDay(d) end
end

local function RememberVariant(store, itemID, item, min, market, qty, now, kind, top, n, onlyVariant)
    local key, parts = Core.DB.Keys.Variant(item)
    local entry = Market().Ensure(store, itemID, n)
    entry.var = type(entry.var) == "table" and entry.var or {}
    local before = entry.var[key]
    local d = type(before) == "table" and type(before.d) == "table" and before.d or {}
    local day = Prices.Day(now)
    AddDay(d, day, min, market or min, top, qty, ScanBit(kind))
    TrimVariantDays(d, day)
    entry.var[key] = { lo = min, mv = market or min, qty = qty, t = now, sfx = parts.sfx, il = parts.il, bon = parts.bon, d = d }
    local count, oldestKey, oldestAt = 0, nil, nil
    for k, v in pairs(entry.var) do
        count = count + 1
        if k ~= key and (not oldestAt or (v.t or 0) < oldestAt) then oldestKey, oldestAt = k, v.t or 0 end
    end
    if count > Prices.MAX_VARIANTS and oldestKey then entry.var[oldestKey] = nil end
    if onlyVariant then return end
    local best, total = nil, 0
    for _, v in pairs(entry.var) do
        if now - (v.t or 0) < 86400 then
            total = total + (v.qty or 0)
            if not best or v.lo < best.lo then best = v end
        end
    end
    best = best or entry.var[key]
    Remember(store, itemID, best.lo, best.mv, total, now, true, kind, best == entry.var[key] and top or nil, n)
end

-- kind (W-51): Art der Erfassung für Tagespunkt und Protokoll; ohne Angabe "search" (eine Suche bzw. die eigene
-- Abfrage eines Moduls).
function Prices.Learn(item, list, quiet, kind)
    local itemID = ItemID(item)
    local store, n
    if itemID then store, n = Store(true) end
    if not store then return false end
    local min, market, qty, top = Prices.MarketValue(list)
    if not min then return false end
    kind = ScanBit(kind) and kind or "search"
    local now = Now()
    if Core.DB.Keys.Variant(item) then
        RememberVariant(store, itemID, item, min, market, qty, now, kind, top, n)
    else
        Remember(store, itemID, min, market, qty, now, true, kind, top, n)
    end
    LogCapture(store, kind, 1, now)
    if not quiet then Core.Fire("PRICES_CHANGED", itemID) end
    return true
end

-- V-032: Aufräumen. Entfernt Sätze (und Abwandlungen), die länger als maxAge Sekunden nicht gesehen wurden – in allen
-- Bereichen der Ablage, im alten Speicher ezCoreDB.prices (er läuft so nach der heutigen Regel aus) und in einem
-- abgelösten Rückfall ezCoreDB.market. Rückgabe: Anzahl entfernter Gegenstände.
local function PruneItems(items, limit, newForm)
    local drop, removed = {}, 0
    for itemID, entry in pairs(items) do
        if type(entry) ~= "table" or (Core.Num(entry.t) or 0) < limit then
            drop[#drop + 1] = itemID
        else
            local vars = newForm and entry.var or entry.v
            if type(vars) == "table" then
                local old = {}
                for key, v in pairs(vars) do
                    if type(v) ~= "table" or (Core.Num(v.t) or 0) < limit then old[#old + 1] = key end
                end
                for _, key in ipairs(old) do vars[key] = nil end
                if next(vars) == nil then if newForm then entry.var = nil else entry.v = nil end end
            end
        end
    end
    for _, itemID in ipairs(drop) do items[itemID] = nil end
    removed = removed + #drop
    -- Frage 37: Tage älter als 30 gehen auch aus dem Verlauf. Die 14-Tage-Grenze für nicht beobachtete Gegenstände
    -- gilt beim nächsten Erfassen (die Frage „beobachtet?“ ist für alle auf einmal zu teuer).
    local first = Prices.Day(Now()) - Prices.WATCH_DAYS + 1
    local today = Prices.Day(Now())
    for _, entry in pairs(items) do
        if newForm then
            local d = type(entry) == "table" and entry.days
            if type(d) == "table" then
                while #d >= NCOL and (Core.Num(d[1]) or 0) < first do DropFirstDay(d) end
            end
            for _, v in pairs(type(entry) == "table" and type(entry.var) == "table" and entry.var or {}) do
                if type(v) == "table" and type(v.d) == "table" then TrimVariantDays(v.d, today) end
            end
        else
            local h = type(entry) == "table" and entry.h
            if type(h) == "table" then
                while #h > 0 and (type(h[1]) ~= "table" or (Core.Num(h[1][1]) or 0) < first) do table.remove(h, 1) end
            end
        end
    end
    return removed
end

local function PruneLog(log, newForm)
    if type(log) ~= "table" then return end
    local first = Prices.Day(Now()) - (Prices.LOG_DAYS or Prices.WATCH_DAYS) + 1
    local field = newForm and "day" or "d"
    while #log > 0 and (type(log[1]) ~= "table" or (Core.Num(log[1][field]) or 0) < first) do table.remove(log, 1) end
end

function Prices.Prune(maxAge)
    maxAge = Core.Num(maxAge) or Prices.MAX_AGE
    local limit, removed = Now() - maxAge, 0
    local M = Market()
    local root = M and M.Root()
    local roots = { root }
    local db = Core.db
    if type(db) == "table" and type(db.market) == "table" and db.market ~= root then roots[#roots + 1] = db.market end
    for _, r in ipairs(roots) do
        if type(r) == "table" and type(r.area) == "table" and not M.Readonly(r) then
            for _, area in pairs(r.area) do
                if type(area) == "table" and type(area.items) == "table" then
                    removed = removed + PruneItems(area.items, limit, true)
                    PruneLog(area.log, true)
                end
            end
        end
    end
    for _, store in pairs(type(db) == "table" and type(db.prices) == "table" and db.prices or {}) do
        if type(store) == "table" and type(store.items) == "table" then
            removed = removed + PruneItems(store.items, limit, false)
            PruneLog(store.log, false)
        end
    end
    if removed > 0 then Core.Fire("PRICES_CHANGED", nil) end
    return removed
end

-- Frage 37 (Empfehlung umgesetzt, Antwort offen): Tagesgrenze von UTC auf Serverzeit umstellen – einmal je
-- Auktionshaus (store.dayBase = "server"). Der jüngste Punkt jedes Gegenstands bekommt den Server-Tag seiner
-- Erfassung (entry.t); fällt er dabei auf den Tag des vorigen Punkts, laufen beide zusammen. Ältere Punkte behalten
-- ihren Tag (ihre Uhrzeit ist nicht bekannt; ein UTC-Tag deckt sich bei bis zu 12 Stunden Abstand überwiegend mit
-- demselben Server-Tag). Zurücknehmen: Core.Time.Zone 0 liefern lassen (Prices.Day rechnet seit dem Gesamtreview vom
-- 18.11.2026 über Core.Time.Day; Prices.DayOffset leitet nur weiter) – dann gilt wieder UTC, nichts geht verloren.
-- → Anzahl umgestellter Auktionshäuser
function Prices.Migrate()
    local db = Core.db
    if type(db) ~= "table" or type(db.prices) ~= "table" then return 0 end
    local n = 0
    for _, store in pairs(db.prices) do
        if type(store) == "table" and type(store.items) == "table" and store.dayBase ~= "server" then
            for _, entry in pairs(store.items) do
                local h = type(entry) == "table" and type(entry.h) == "table" and entry.h
                local last = h and h[#h]
                local at = h and Core.Num(entry.t)
                if type(last) == "table" and at and last[1] == floor(at / DAY) then
                    local day = Prices.Day(at)
                    local prev = h[#h - 1]
                    if type(prev) == "table" and prev[1] == day then
                        prev[2] = math.min(Core.Num(prev[2]) or last[2], Core.Num(last[2]) or prev[2])
                        prev[3] = last[3]
                        h[#h] = nil
                    else
                        last[1] = day
                    end
                end
            end
            store.dayBase, store.dayOffset = "server", Prices.DayOffset()
            n = n + 1
        end
    end
    return n
end

-- Größe des Preis-Wissens (W-51: „vorher messen“; im Spiel /dump ezCore.Prices.Size()). bytes ist die Länge des
-- Texts aus Core.Serialize – ungefähr so viel steht davon in der Datei der Ablage (where). old = derselbe Zähler für
-- den alten Speicher ezCoreDB.prices, solange er liegt.
local function SizeOf(stores, newForm)
    local out = { items = 0, points = 0, captures = 0, bytes = 0, houses = 0 }
    for _, store in pairs(stores) do
        local items = type(store) == "table" and store.items
        if type(items) == "table" then
            out.houses = out.houses + 1
            for _, entry in pairs(items) do
                out.items = out.items + 1
                if newForm then
                    out.points = out.points + (type(entry) == "table" and type(entry.days) == "table" and math.floor(#entry.days / NCOL) or 0)
                else
                    out.points = out.points + (type(entry) == "table" and type(entry.h) == "table" and #entry.h or 0)
                end
            end
            out.captures = out.captures + (type(store.log) == "table" and #store.log or 0)
        end
    end
    if Core.Serialize then
        local ok, text = pcall(Core.Serialize, stores)
        if ok and type(text) == "string" then out.bytes = #text end
    end
    return out
end

function Prices.Size()
    local M = Market()
    local root, where = M and M.Root()
    local out = SizeOf(type(root) == "table" and type(root.area) == "table" and root.area or {}, true)
    out.where = where
    local db = Core.db
    if type(db) == "table" and type(db.prices) == "table" then out.old = SizeOf(db.prices, false) end
    return out
end

function Prices.Count()
    local store, n = Store(false)
    local count = 0
    if not store then return 0 end
    for id, e in pairs(store.items) do
        if type(e) ~= "table" then count = count + 1 end   -- kaputte Sätze zählen mit, bis Prune sie entfernt
    end
    Market().Each(store, n, function() count = count + 1 end)
    return count
end

ns.On("PLAYER_LOGIN", function()
    Prices.DayOffset(true)
    Prices.Migrate()
    local M = Market()
    if M then Core.Try(nil, "Prices.Prepare", M.Prepare) end
    Prices.Prune()
end)

-- Median einer Zahlenliste (sortiert die Liste), nil ohne Werte – eine Fassung für alle: Core.Median (Util.lua, Welle 15)
local Median = Core.Median

-- Median der Tages-Tiefstpreise aus dem Verlauf, der heutige Tag mit dem neuen Tiefstpreis. Nur die letzten
-- Prices.HISTORY_DAYS Kalendertage zählen, auch bei beobachteten Gegenständen mit 30 Tagen Verlauf – sonst änderten
-- sich Taschenwert und Materialkosten still (VP-61).
local function DailyMinMedian(entry, min, now)
    local today, mins, hasToday = Prices.Day(now), {}, false
    local first = today - Prices.HISTORY_DAYS + 1
    local d = type(entry) == "table" and type(entry.days) == "table" and entry.days or {}
    for i = 1, #d - NCOL + 1, NCOL do
        local low = (Core.Num(d[i]) or 0) >= first and Core.Num(d[i + 1])
        if low and low >= 0 then
            if d[i] == today then
                low, hasToday = math.min(low, min), true
            end
            mins[#mins + 1] = low
        end
    end
    if not hasToday then mins[#mins + 1] = min end
    return Median(mins)
end

-- Nur der Tiefstpreis (Übersicht). W-53: Der Marktwert einer vollständigen Liste gilt einen Tag ab ihrer Erfassung
-- (entry.mt – nicht ab dem letzten Besuch, sonst hielte ihn die tägliche Übersicht ewig fest), danach der Median der
-- Tages-Tiefstpreise. Nie unter dem heutigen Tiefstpreis; so folgt der Wert fallenden Preisen statt nur zu steigen.
local function LearnMin(itemID, min, qty, kind)
    local store, n = Store(true)
    if not (store and itemID and Core.Num(min) and min > 0) then return end
    local entry = Market().Entry(store, itemID, n)
    local now = Now()
    local fullAt = entry and Core.Num(entry.tf)
    local market
    if entry and Core.Num(entry.mv) and fullAt and (now - fullAt) < 86400 then
        market = entry.mv
    else
        market = DailyMinMedian(entry, min, now) or min
    end
    if market < min then market = min end
    Remember(store, itemID, min, market, Core.Num(qty) or (entry and entry.qty) or 0, now, false, kind or "browse", min, n)
end

-- Preis-Satz eines Gegenstands im eigenen Bereich (auch aus dem alten Speicher, solange der Umzug läuft)
local function EntryOf(item)
    local itemID = ItemID(item)
    if not itemID then return nil end
    local store, n = Store(false)
    return store and Market().Entry(store, itemID, n), store
end

-- AH-04: Marktwert aus einer vollständigen Liste (Komplett-Scan, Einzelsuche) oder aus Tages-Tiefstpreisen? Eine
-- vollständige Liste prägt den Wert, solange danach nur Übersichten kamen und sie keinen Tag alt ist (LearnMin).
local function MarketFrom(entry)
    local tf = Core.Num(entry.tf)
    if not tf then return "min" end
    local last = Core.Num(entry.t) or tf
    if last <= tf or last - tf < DAY then return "full", Market().KIND[Core.Num(entry.fk) or 0], tf end
    return "min", Market().KIND[Core.Num(entry.fk) or 0], tf
end

-- Antwort in der Form von Prices.Get aus einem allgemeinen Satz (eine Stelle für Get, Each und Today)
local function InfoOf(entry, kind)
    local from, fullKind, fullSeen = MarketFrom(entry)
    return { min = entry.lo, market = entry.mv, quantity = entry.qty, seen = entry.t, source = "own",
        kind = kind or Market().KIND[Core.Num(entry.scan) or 0], marketFrom = from, fullKind = fullKind, fullSeen = fullSeen }
end

function Prices.Get(item)
    local entry = EntryOf(item)
    if not entry then return nil end
    -- Abwandlung gefragt und bekannt: ihr eigener Preis (Feld variant nennt den Schlüssel in der alten Form)
    local key = type(entry.var) == "table" and Core.DB.Keys.Variant(item)
    local v = key and entry.var[key]
    local kind = Market().KIND[Core.Num(entry.scan) or 0]
    if type(v) == "table" then
        return { min = v.lo, market = v.mv, quantity = v.qty, seen = v.t, variant = Prices.VariantOf(item), source = "own",
            kind = kind, marketFrom = "full", fullSeen = v.t }
    end
    return InfoOf(entry, kind)
end

-- A20 (Welle 23b): alle Preise dieses Auktionshauses aufzählen, ohne die Ablage-Schicht (DB.Market.Each) zu kennen.
-- fn(itemID, info) mit info in der Form von Prices.Get (allgemeiner Satz, ohne Abwandlung); gibt fn true zurück, endet
-- die Aufzählung. since: nur Sätze, die seit diesem Zeitpunkt (time()) erfasst wurden. → Anzahl der Aufrufe
function Prices.Each(fn, since)
    if type(fn) ~= "function" then return 0 end
    local store, n = Store(false)
    if not store then return 0 end
    since = Core.Num(since)
    local count, stop = 0, false
    Market().Each(store, n, function(itemID, entry)
        if stop or (since and (Core.Num(entry.t) or 0) < since) then return end
        count = count + 1
        local ok, done = pcall(fn, itemID, InfoOf(entry))
        if not ok then
            Core.Error(Core.name, done, "Prices.Each")
            stop = true
        elseif done == true then
            stop = true
        end
    end)
    return count
end

-- Beginn des heutigen Tags (Serverzeit wie Prices.Day) als Stempel der PC-Uhr (vergleichbar mit entry.t)
function Prices.TodayStart()
    return Core.Time.TodayStart("server")
end

-- A20: nur die Preise von heute (Tagesgrenze wie Prices.Day) – etwa für Schnäppchen nach einem Komplett-Scan
function Prices.Today(fn)
    return Prices.Each(fn, Prices.TodayStart())
end

-- Quelle als Text (Leitlinie 11): „laut deinen Erfassungen (Komplett-Scan, vor 2 Std.)“ bzw. mit Prices.Stats
-- „… (an 9 Tagen gesehen)“. info aus Prices.Get oder Prices.Stats; nil ohne Angabe.
function Prices.SourceText(info)
    if type(info) ~= "table" or info.source ~= "own" then return nil end
    local L = Core.L
    local parts = {}
    local kindText = info.kind and L["PRICES_KIND_" .. info.kind]
    if kindText then parts[#parts + 1] = kindText end
    if Core.Num(info.daysSeen) then
        parts[#parts + 1] = Core.Plural(info.daysSeen, L.PRICES_DAYS_ONE, L.PRICES_DAYS_MANY)
    elseif Core.Num(info.seen) and Core.Ago then
        parts[#parts + 1] = Core.Ago(info.seen)
    end
    -- AH-04: Marktwert nur aus Komplett-Scan und Einzelsuche – sonst sagt die Zeile, woraus er stammt
    if info.marketFrom == "min" then
        parts[#parts + 1] = L.PRICES_MARKET_MIN
    elseif info.marketFrom == "full" and info.fullKind and info.fullKind ~= info.kind and L["PRICES_KIND_" .. info.fullKind] then
        parts[#parts + 1] = L.PRICES_MARKET_FULL:format(L["PRICES_KIND_" .. info.fullKind])
    end
    if #parts == 0 then return L.PRICES_SOURCE_OWN end
    return L.PRICES_SOURCE_OWN .. " (" .. table.concat(parts, ", ") .. ")"
end

function Prices.Value(item, count)
    local info = Prices.Get(item)
    if not (info and info.market) then return nil end
    return info.market * (tonumber(count) or 1)
end

-- Wert einer Spalte der Reihe; -1 heißt „unbekannt“ (nil)
local function Col(v)
    v = Core.Num(v)
    if v and v >= 0 then return v end
    return nil
end

-- A21 (Welle 23b): Nennt item eine Abwandlung (Link mit Zufallssuffix oder Bonus-IDs, itemKey mit itemSuffix) und hat
-- sie eigene Tagespunkte, liefert History deren Verlauf; zweiter Rückgabewert "variant" bzw. "item" (allgemeiner
-- Verlauf über alle Abwandlungen).
-- Tagespunkte zu item: die der Abwandlung, wenn item eine mit eigenen Punkten nennt, sonst der allgemeine Verlauf.
-- → Zahlenreihe (oder nil), "variant" | "item". Eine Wahl für History und Stats (Gegenprüfung Welle 23b).
local function DaysOf(entry, item)
    local d = type(entry) == "table" and type(entry.days) == "table" and entry.days or nil
    local key = type(entry) == "table" and type(entry.var) == "table" and Core.DB.Keys.Variant(item)
    local v = key and entry.var[key]
    if type(v) == "table" and type(v.d) == "table" and #v.d >= NCOL then return v.d, "variant" end
    return d, "item"
end

function Prices.History(item, days)
    local entry = EntryOf(item)
    local out = {}
    days = Core.Num(days)
    local first = days and (Prices.Day(Now()) - math.max(1, floor(days)) + 1) or nil
    local d, which = DaysOf(entry, item)
    d = d or {}
    for i = 1, #d - NCOL + 1, NCOL do
        local day, min, market = Core.Num(d[i]), Col(d[i + 1]), Col(d[i + 2])
        if day and (not first or day >= first) then
            out[#out + 1] = { time = day * DAY, day = day, min = min, market = market,
                high = Col(d[i + 3]) or math.max(min or 0, market or 0), quantity = Col(d[i + 4]),
                kinds = KindsOfBits(d[i + 5]) }
        end
    end
    return out, which
end

---------------------------------------------------------------------------
-- Wochenpunkte des Beobachteten (AH-05, Welle 13)
---------------------------------------------------------------------------
-- Was Prices.IsObserved nennt (Prices.Watch, Anbieter, Besitz), behält 30 Tage als Tagespunkte (EC-23); ältere Tage
-- werden zu Wochenpunkten verdichtet statt verworfen – höchstens Prices.WeeksMax() Wochen (ab Werk 26, Schalter
-- „Preisverlauf: ältere Wochen behalten“; 0 = aus, vorhandene Wochen bleiben dann liegen und werden nicht gezeigt).
-- Ablage am Satz: entry.wk = Zahlenreihe mit NCOLW Werten je Woche (woche, tief, hoch, median, menge, tage), entry.wp =
-- die angefangene Woche { w, lows = { Tagestiefst … }, hi, qty } (höchstens 7 Zahlen, damit der Median genau bleibt).
-- Woche = floor((Tag + 3) / 7): Wochen beginnen am Montag (Tag 0, der 1.1.1970, war ein Donnerstag). Ein Satz ohne
-- wk liest sich wie bisher – die Tagespunkte (Spalten hcols) ändern sich nicht. Gepackte Ablage der Tagespunkte
-- (Datenmodell 5) erst nach der Messung aus Welle 7 (liegt nicht vor; Abbruchkriterium: Welle 14).
local NCOLW = 6
Prices.WEEKS_MAX = 26
-- worthMerchant/worthBag: Münze je Ort (Welle 23d, Entscheidung Nr. 13). Einstellungs-Prüfung 19.11.2026 (Entscheidung
-- des Nutzers „Ja, alle umsetzen“): der alte Gesamtschalter worth (Nr. 1, ohne Zeile – stand er durch eine eingespielte
-- Sicherung auf aus, verschwand die Münze unsichtbar überall), worthGross (Nr. 4, jetzt fest: ohne gemessene Gebühr
-- rechnet die Marke brutto und sagt es) und weeks (Nr. 51, „0 Wochen“ in der Auswahl heißt aus) sind weg; ihre alten
-- Werte übernimmt Prices.MigrateWorthPlaces einmal. worthBag gilt auch an ezBags Plätzen (Nr. 50/58: ein Schalter).
-- monthsMax: Monatspunkte (Entscheidung des Nutzers vom 21.11.2026, „Beides bauen“ – Monatsansicht und Vergrößern-Pfeil
-- im Seitenteil „Markt“; unten bei den Monatspunkten).
Prices.MONTHS_MAX = 24
Core.OwnDefaults("priceOpts", { weeksMax = Prices.WEEKS_MAX, monthsMax = Prices.MONTHS_MAX, worthPct = 20,
    worthMerchant = true, worthBag = false })

Prices.WEEKS_STEPS = { 0, 4, 8, 13, 26 }
-- eingestellte Wochenzahl (Auswahl in den Einstellungen; 0 = keine Wochenpunkte). Seit dem Wegfall des Schalters
-- „weeks“ (Einstellungs-Prüfung 19.11.2026, Nr. 51) liefert sie denselben Wert wie Prices.WeeksMax; beide lesen die
-- Auswahl selbst (Aufrufer wie ezAuctions Markt unterscheiden weiter „aus“ und „Auswahl auf 0“).
function Prices.WeeksMaxSetting()
    local n = Core.Num(Core.OwnSetting("priceOpts", "weeksMax")) or Prices.WEEKS_MAX
    return math.max(0, math.min(Prices.WEEKS_MAX, floor(n)))
end

function Prices.WeeksMax()
    local n = Core.Num(Core.OwnSetting("priceOpts", "weeksMax")) or Prices.WEEKS_MAX
    return math.max(0, math.min(Prices.WEEKS_MAX, floor(n)))
end

local function WeekOf(day) return floor((day + 3) / 7) end
Prices.WeekOf = WeekOf

local function FinishWeek(entry)
    local p = entry.wp
    entry.wp = nil
    if type(p) ~= "table" or not Core.Num(p.w) or type(p.lows) ~= "table" or #p.lows == 0 then return end
    local lo = math.huge
    for _, v in ipairs(p.lows) do if v < lo then lo = v end end
    local wk = type(entry.wk) == "table" and entry.wk or {}
    entry.wk = wk
    wk[#wk + 1], wk[#wk + 2], wk[#wk + 3] = p.w, lo, math.max(Core.Num(p.hi) or lo, lo)
    wk[#wk + 1], wk[#wk + 2], wk[#wk + 3] = Median(p.lows), Core.Num(p.qty) or 0, #p.lows
end

-- den ältesten Tagespunkt (d[1] …) in die Woche übernehmen, bevor er fällt
Fold = function(entry, d)
    local day = Core.Num(d[1])
    if not day then return end
    local lo, hi, qty = Col(d[2]), Col(d[4]), Col(d[5])
    local w = WeekOf(day)
    if type(entry.wp) == "table" and entry.wp.w ~= w then FinishWeek(entry) end
    local p = type(entry.wp) == "table" and entry.wp or { w = w, lows = {}, qty = 0 }
    entry.wp = p
    if lo then
        p.lows[#p.lows + 1] = lo
        p.hi = math.max(Core.Num(p.hi) or lo, hi or lo)
    end
    if qty and qty > (Core.Num(p.qty) or 0) then p.qty = qty end
end

local FoldWeek, TrimMonths   -- Monatspunkte (unten)

-- Wochen vor der Grenze verwerfen (die angefangene zählt mit) – mit Monatspunkten (Prices.MonthsMax() > 0) werden sie
-- vorher zu ihrem Monat verdichtet. Die angefangene Woche wird dafür erst abgeschlossen, sobald sie keine Tage mehr
-- bekommt (der älteste verbliebene Tagespunkt liegt in einer späteren Woche); bis dahin bleibt sie offen und
-- Prices.Weeks zeigt sie nicht (Befund des Reviews: bei wenigen behaltenen Wochen – Stufe 4 – fiel sonst jede Woche
-- tageweise in Bruchstücken in ihren Monat).
TrimWeeks = function(entry, today)
    local first = WeekOf(today) - Prices.WeeksMax() + 1
    local months = Prices.MonthsMax() > 0
    if type(entry.wp) == "table" and (Core.Num(entry.wp.w) or 0) < first then
        if not months then
            entry.wp = nil
        else
            local d = entry.days
            local oldest = type(d) == "table" and Core.Num(d[1])
            if not oldest or WeekOf(oldest) ~= entry.wp.w then FinishWeek(entry) end
        end
    end
    local wk = entry.wk
    if type(wk) == "table" then
        while #wk >= NCOLW and (Core.Num(wk[1]) or 0) < first do
            if months then FoldWeek(entry, wk) end
            for _ = 1, NCOLW do table.remove(wk, 1) end
        end
        if #wk == 0 then entry.wk = nil end
    end
    if months then TrimMonths(entry, today) end
end

-- → { { week, day, time, low, high, median, quantity, days, open } … } älteste zuerst; open = angefangene Woche.
function Prices.Weeks(item)
    local entry = EntryOf(item)
    local out = {}
    if type(entry) ~= "table" or Prices.WeeksMax() == 0 then return out end
    local wk = type(entry.wk) == "table" and entry.wk or {}
    local function Add(w, lo, hi, med, qty, n, open)
        local day = w * 7 - 3
        out[#out + 1] = { week = w, day = day, time = day * DAY, low = lo, high = hi, median = med, quantity = qty,
            days = n, open = open or nil }
    end
    for i = 1, #wk - NCOLW + 1, NCOLW do
        local w = Core.Num(wk[i])
        if w then Add(w, Col(wk[i + 1]), Col(wk[i + 2]), Col(wk[i + 3]), Col(wk[i + 4]), Core.Num(wk[i + 5]) or 0) end
    end
    local p = entry.wp
    -- eine angefangene Woche vor der Grenze (für die Monate offen gehalten, TrimWeeks) zeigt sie nicht
    local first = WeekOf((Prices.Day(Now()))) - Prices.WeeksMax() + 1
    if type(p) == "table" and Core.Num(p.w) and p.w >= first and type(p.lows) == "table" and #p.lows > 0 then
        local lo = math.huge
        for _, v in ipairs(p.lows) do if v < lo then lo = v end end
        Add(p.w, lo, Core.Num(p.hi) or lo, Median(p.lows), Core.Num(p.qty) or 0, #p.lows, true)
    end
    return out
end

---------------------------------------------------------------------------
-- Monatspunkte des Beobachteten (Entscheidung des Nutzers vom 21.11.2026: „Beides bauen“ – auf die Frage „wird der
-- markt graph über wochen monate und gar jahre nicht zu sehr gestaucht? … vergrößern pfeil wie bei der karte?“)
---------------------------------------------------------------------------
-- Wochen, die aus Prices.WeeksMax() fallen, werden zu Kalendermonaten verdichtet statt verworfen – höchstens
-- Prices.MonthsMax() Monate (ab Werk 24, Auswahl „Preisverlauf: Monate behalten“; 0 = aus, die Wochen fallen dann wie
-- bisher weg). So zeigt jede Ansicht (Tage, Wochen, Monate) ein festes Fenster, und der Graph wird nie gestaucht.
-- Ablage am Satz: entry.mo = Zahlenreihe mit NCOLM Werten je Monat (monat, tief, hoch, median, menge, tage), entry.mp =
-- der angefangene Monat { m, meds = { Wochen-Median … }, lo, hi, qty, n = Tage } (höchstens 6 Wochen; eine Woche kommt
-- erst abgeschlossen hinein, TrimWeeks). Der Median
-- eines Monats ist der Median seiner Wochen-Mediane (eine Näherung – von einer Woche hält ezCore nur den Median).
-- Monat = Jahr * 12 + Monat - 1 (Prices.MonthOf); eine Woche gehört zum Monat ihres Donnerstags (wie die
-- Kalenderwoche zu ihrem Jahr). Ein Satz ohne mo liest sich wie bisher.
local NCOLM = 6
-- Prices.MONTHS_MAX (24) steht oben bei den Vorgaben von priceOpts
Prices.MONTHS_STEPS = { 0, 6, 12, 24 }

function Prices.MonthsMax()
    local n = Core.Num(Core.OwnSetting("priceOpts", "monthsMax")) or Prices.MONTHS_MAX
    return math.max(0, math.min(Prices.MONTHS_MAX, floor(n)))
end

-- Kalendermonat eines Tags (Tag 0 = 1.1.1970, wie Prices.Day) ohne date(): Umrechnung Tage → Jahr/Monat nach dem
-- gregorianischen Kalender. → monat (Jahr * 12 + Monat - 1), jahr, monat (1–12); nil ohne Zahl.
function Prices.MonthOf(day)
    day = Core.Num(day)
    if not day then return nil end
    local z = floor(day) + 719468
    local era = floor(z / 146097)
    local doe = z - era * 146097
    local yoe = floor((doe - floor(doe / 1460) + floor(doe / 36524) - floor(doe / 146096)) / 365)
    local doy = doe - (365 * yoe + floor(yoe / 4) - floor(yoe / 100))
    local mp = floor((5 * doy + 2) / 153)
    local m = mp < 10 and mp + 3 or mp - 9
    local y = yoe + era * 400 + (m <= 2 and 1 or 0)
    return y * 12 + m - 1, y, m
end

-- Monat einer Woche aus Prices.WeekOf: der Monat ihres Donnerstags (wie die Kalenderwoche zu ihrem Jahr). Die Regel
-- steht nur hier (Leitlinie 2; ezAuctions Monatsansicht fragt sie ab). nil ohne Zahl.
function Prices.MonthOfWeek(week)
    week = Core.Num(week)
    if not week then return nil end
    return (Prices.MonthOf(floor(week) * 7))
end

-- erster Tag eines Monats aus Prices.MonthOf (Umkehrung). nil ohne Zahl.
function Prices.MonthStart(month)
    month = Core.Num(month)
    if not month then return nil end
    month = floor(month)
    local y, m = floor(month / 12), month % 12 + 1
    if m <= 2 then y = y - 1 end
    local era = floor(y / 400)
    local yoe = y - era * 400
    local doy = floor((153 * ((m + 9) % 12) + 2) / 5)
    local doe = yoe * 365 + floor(yoe / 4) - floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

local function FinishMonth(entry)
    local p = entry.mp
    entry.mp = nil
    if type(p) ~= "table" or not Core.Num(p.m) or type(p.meds) ~= "table" or #p.meds == 0 then return end
    local mo = type(entry.mo) == "table" and entry.mo or {}
    entry.mo = mo
    local lo = Core.Num(p.lo) or Median(p.meds)
    mo[#mo + 1], mo[#mo + 2], mo[#mo + 3] = p.m, lo, math.max(Core.Num(p.hi) or lo, lo)
    mo[#mo + 1], mo[#mo + 2], mo[#mo + 3] = Median(p.meds), Core.Num(p.qty) or 0, Core.Num(p.n) or 0
end

-- die älteste Woche (wk[1] …) in ihren Monat übernehmen, bevor sie fällt
FoldWeek = function(entry, wk)
    local w, med = Core.Num(wk[1]), Col(wk[4])
    if not (w and med) then return end
    local m = Prices.MonthOfWeek(w)
    if type(entry.mp) == "table" and entry.mp.m ~= m then FinishMonth(entry) end
    local p = type(entry.mp) == "table" and entry.mp or { m = m, meds = {}, qty = 0, n = 0 }
    entry.mp = p
    local lo, hi = Col(wk[2]) or med, Col(wk[3]) or med
    p.meds[#p.meds + 1] = med
    p.lo = math.min(Core.Num(p.lo) or lo, lo)
    p.hi = math.max(Core.Num(p.hi) or hi, hi)
    local qty = Col(wk[5])
    if qty and qty > (Core.Num(p.qty) or 0) then p.qty = qty end
    p.n = (Core.Num(p.n) or 0) + (Core.Num(wk[6]) or 0)
end

-- Monate vor der Grenze verwerfen (der angefangene zählt mit)
TrimMonths = function(entry, today)
    local first = Prices.MonthOf(today) - Prices.MonthsMax() + 1
    local mo = entry.mo
    if type(mo) == "table" then
        while #mo >= NCOLM and (Core.Num(mo[1]) or 0) < first do
            for _ = 1, NCOLM do table.remove(mo, 1) end
        end
        if #mo == 0 then entry.mo = nil end
    end
    if type(entry.mp) == "table" and (Core.Num(entry.mp.m) or 0) < first then entry.mp = nil end
end

-- → { { month, year, monthOfYear, day (erster Tag), time, low, high, median, quantity, days, weeks, open } … } älteste
-- zuerst; open = angefangener Monat (weeks = so viele Wochen stecken darin). Leer bei Prices.MonthsMax() == 0.
function Prices.Months(item)
    local entry = EntryOf(item)
    local out = {}
    if type(entry) ~= "table" or Prices.MonthsMax() == 0 then return out end
    local mo = type(entry.mo) == "table" and entry.mo or {}
    local function Add(m, lo, hi, med, qty, n, weeks, open)
        local day = Prices.MonthStart(m)
        out[#out + 1] = { month = m, year = floor(m / 12), monthOfYear = m % 12 + 1, day = day, time = day * DAY,
            low = lo, high = hi, median = med, quantity = qty, days = n, weeks = weeks, open = open or nil }
    end
    for i = 1, #mo - NCOLM + 1, NCOLM do
        local m = Core.Num(mo[i])
        if m then Add(m, Col(mo[i + 1]), Col(mo[i + 2]), Col(mo[i + 3]), Col(mo[i + 4]), Core.Num(mo[i + 5]) or 0) end
    end
    local p = entry.mp
    if type(p) == "table" and Core.Num(p.m) and type(p.meds) == "table" and #p.meds > 0 then
        local med = Median(p.meds)
        Add(p.m, Core.Num(p.lo) or med, Core.Num(p.hi) or med, med, Core.Num(p.qty) or 0, Core.Num(p.n) or 0, #p.meds, true)
    end
    return out
end

-- Protokoll der Erfassungen dieses Auktionshauses, die letzten tage Tage (ohne Angabe: alle gemerkten).
function Prices.Captures(days)
    local store = Store(false)
    local out = {}
    local first = Core.Num(days) and (Prices.Day(Now()) - days + 1) or nil
    local list = store and type(store.log) == "table" and store.log or {}
    -- solange der Umzug läuft: das Protokoll des alten Speichers dazu (umgewandelt)
    local M = Market()
    if M and M.Adopting() then
        local key = Prices.Key()
        local old = Core.db and type(Core.db.prices) == "table" and Core.db.prices[key]
        if type(old) == "table" and type(old.log) == "table" and #old.log > 0 then
            local merged = {}
            for _, c in ipairs(old.log) do merged[#merged + 1] = M.LogFromOld(c) end
            for _, c in ipairs(list) do merged[#merged + 1] = c end
            list = merged
        end
    end
    for _, c in ipairs(list) do
        if type(c) == "table" and (not first or (Core.Num(c.day) or 0) >= first) then
            out[#out + 1] = { day = c.day, hour = c.hr, weekday = c.wd, kind = M.KIND[Core.Num(c.scan) or 0], n = c.rows,
                count = Core.Num(c.cnt) or 1, time = c.t }
        end
    end
    return out
end

-- A19 (Welle 23b): Zahl der Tage mit Komplett-Scan oder Übersicht seit first – ohne Kopie des Protokolls (vorher rief
-- Prices.Stats je Aufruf Prices.Captures, das eine neue Liste baut; „Schnäppchen“ fragt das je Zeile). Zwischengespeichert
-- je Protokoll: gilt, solange first, Länge und letzter Eintrag gleich sind (neue Einträge hängen hinten an; vorn gekürzt
-- wird nur zusammen mit einem neuen Eintrag). Während des Umzugs zählt das alte Protokoll ohne Zwischenspeicher mit.
local capturedCache = setmetatable({}, { __mode = "k" })
local SEEN_LOG_BITS = { [1] = true, [4] = true }   -- Komplett-Scan, Übersicht

CapturedDays = function(first)
    local store = Store(false)
    local list = store and type(store.log) == "table" and store.log or nil
    local M = Market()
    local old
    if M and M.Adopting() then
        local o = Core.db and type(Core.db.prices) == "table" and Core.db.prices[Prices.Key()]
        if type(o) == "table" and type(o.log) == "table" and #o.log > 0 then old = o.log end
    end
    local cache = list and not old and capturedCache[list]
    if cache and cache.first == first and cache.n == #list and cache.last == list[#list] then return cache.count end
    local days, count = {}, 0
    local function Count(c)
        local cd = type(c) == "table" and Core.Num(c.day)
        if cd and cd >= first and SEEN_LOG_BITS[Core.Num(c.scan) or 0] and not days[cd] then
            days[cd] = true
            count = count + 1
        end
    end
    for _, c in ipairs(old or {}) do Count(M.LogFromOld(c)) end
    for _, c in ipairs(list or {}) do Count(c) end
    if list and not old then capturedCache[list] = { first = first, n = #list, last = list[#list], count = count } end
    return count
end
Prices.CapturedDays = CapturedDays

-- W-51: eine Rechnung für Graph, Hinweise und Tooltip (ezAuctions Scan.Trend bleibt als Hülle). Gezählt werden
-- Tagespunkte der letzten tage Kalendertage; nil ohne Punkt. Nennt item eine Abwandlung mit eigenen Tagespunkten,
-- rechnet Stats wie History über deren Punkte (variant = true, nicht mixed) – Graph und Kennzahlen passen zusammen.
function Prices.Stats(item, days)
    local entry = EntryOf(item)
    if type(entry) ~= "table" then return nil end
    local d, which = DaysOf(entry, item)
    if type(d) ~= "table" then return nil end
    days = math.max(1, floor(Core.Num(days) or Prices.HISTORY_DAYS))
    local first = Prices.Day(Now()) - days + 1
    local mins, qtys, low, high, seen, points = {}, {}, nil, nil, 0, 0
    for i = 1, #d - NCOL + 1, NCOL do
        local min = (Core.Num(d[i]) or 0) >= first and Col(d[i + 1])
        if min then
            points = points + 1
            mins[#mins + 1] = min
            local top = Col(d[i + 3]) or math.max(min, Col(d[i + 2]) or min)
            if not low or min < low then low = min end
            if not high or top > high then high = top end
            -- Einzelsuchen zählen nicht als „gesehen“ (Entwurf 2a); Tage ohne Arten (von vor W-51) schon, Kategorie
            -- und Sammelabfrage (AH-04) wie die Übersicht
            local bits = Core.Num(d[i + 5]) or -1
            if bits <= 0 or BHas(bits, 1) or BHas(bits, 4) or BHas(bits, 8) or BHas(bits, 16) then
                seen = seen + 1
                local qty = Col(d[i + 4])
                if qty and qty > 0 then qtys[#qtys + 1] = qty end
            end
        end
    end
    if points == 0 then return nil end
    local nCaptured = CapturedDays(first)
    -- A18 (Welle 23b): übliche Spanne der Menge – unteres und oberes Viertel der Tagesmengen (nächster Rang; Median
    -- sortiert die Liste vorher)
    local usual = Median(qtys)
    local qn = #qtys
    local qLow = qn > 0 and qtys[math.max(1, math.ceil(qn * 0.25))] or nil
    local qHigh = qn > 0 and qtys[math.max(1, math.ceil(qn * 0.75))] or nil
    -- Tage erfasst nie unter Tage gesehen (Tage von vor dem Protokoll)
    local from, fullKind, fullSeen = MarketFrom(entry)
    return { median = Median(mins), low = low, high = high, daysSeen = seen, daysCaptured = math.max(nCaptured, seen),
        usualQuantity = usual, quantityLow = qLow, quantityHigh = qHigh, points = points, days = days, source = "own",
        kind = Market().KIND[Core.Num(entry.scan) or 0],
        variant = which == "variant" or nil,
        mixed = (which ~= "variant" and type(entry.var) == "table" and next(entry.var) ~= nil) or nil,
        marketFrom = from, fullKind = fullKind,
        fullSeen = fullSeen }
end

function Prices.IsOpen() return isOpen end

-- W-52: Zeitpunkt des letzten Komplett-Scans kontoweit (ezCoreDB.pricesScanAt). Das frühere Feld scanAt je Realm
-- und Fraktion bleibt im Speicher liegen, wird aber nicht mehr gelesen (es hielt nach einem Fehlschlag 15 Minuten fest).
local function ScanAt()
    local db = Core.db
    return type(db) == "table" and Core.Num(db.pricesScanAt) or 0
end

local function SetScanAt(at)
    if type(Core.db) == "table" then Core.db.pricesScanAt = at end
end

function Prices.ScanReadyIn()
    return max(0, ScanAt() + SCAN_COOLDOWN - Now())
end

function Prices.IsScanning()
    if not scanning then return false end
    return true, scanning.done or 0, scanning.total or 0
end

---------------------------------------------------------------------------
-- Komplett-Scan
---------------------------------------------------------------------------

-- AH-01: Zeitmessung je Scheibe (debugprofilestop; ohne ihn GetTime) und der Schalter für das Link-Lesen.
local function SliceClock()
    local fn = rawget(_G, "debugprofilestop")
    if type(fn) == "function" then return Core.Num(fn()) or 0 end
    return (Core.Num(GetTime and GetTime()) or 0) * 1000
end

local LINK_MODES = { all = true, gear = true, none = true }
local GEAR_CLASS = { [2] = true, [4] = true }   -- Waffe, Rüstung (Enum.ItemClass): nur sie haben Abwandlungen
local linkMode, linkAuto = "all", false
local lastScan                                   -- Messung des letzten Scans (Prices.ScanStats)

function Prices.ScanLinks(mode)
    if mode ~= nil then
        if not LINK_MODES[mode] then return linkMode, linkAuto end
        linkMode, linkAuto = mode, false
    end
    return linkMode, linkAuto
end

function Prices.ScanStats()
    if not lastScan then return nil end
    local out = {}
    for k, v in pairs(lastScan) do out[k] = v end
    out.avg = out.slices > 0 and out.ms / out.slices or 0
    return out
end

local function ItemClass(itemID)
    return (Core.ItemClass(itemID))   -- eine Umhüllung von GetItemInfoInstant (Core.ItemInstant, T16-16)
end

local function WantLink(s, itemID)
    if s.links == "all" then return true end
    if s.links ~= "gear" then return false end
    local c = s.classes[itemID]
    if c == nil then
        c = ItemClass(itemID) or false
        s.classes[itemID] = c
    end
    return GEAR_CLASS[c] == true
end

local function RequestItem(s, itemID)
    if s.requested[itemID] then return end
    s.requested[itemID] = true
    local api = rawget(_G, "C_Item")
    if type(api) == "table" and type(api.RequestLoadItemDataByID) == "function" then pcall(api.RequestLoadItemDataByID, itemID) end
end

-- Eine Zeile des Komplett-Scans (Rückgaben laut Probe X2: 3 Anzahl, 10 Sofortkauf, 17 itemID, 18 hasAllInfo). Ohne
-- volle Daten einmal nachgefordert (retry), beim zweiten Mal ausgelassen und gezählt. Fehlt die 18. Rückgabe
-- (ältere Clients), gilt die Zeile als vollständig – so liest der Scan wie vorher.
local function ReadRow(s, AH, index, retry)
    local ok, _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID, hasAll = pcall(AH.GetReplicateItemInfo, index)
    if not ok then return end
    count, buyout, itemID = Core.Num(count), Core.Num(buyout), Core.Num(itemID)
    if not (itemID and buyout and buyout > 0 and count and count > 0) then return end
    if not Core.IsSecret(hasAll) and hasAll == false then
        if not retry then
            s.retry[#s.retry + 1] = index
            RequestItem(s, itemID)
        else
            s.skipped = s.skipped + 1
        end
        return
    end
    local offer = { buyout / count, count }
    local list = s.offers[itemID]
    if not list then
        list = {}
        s.offers[itemID] = list
    end
    list[#list + 1] = offer
    if type(AH.GetReplicateItemLink) ~= "function" or not WantLink(s, itemID) then return end
    local okL, link = pcall(AH.GetReplicateItemLink, index)
    link = okL and Core.Plain(link) or nil
    if type(link) ~= "string" then return end
    s.linksRead = s.linksRead + 1
    local key = Core.DB.Keys.Variant(link)
    if not key then return end
    local byItem = s.vars[itemID]
    if not byItem then
        byItem = {}
        s.vars[itemID] = byItem
    end
    local v = byItem[key]
    if not v then
        v = { link = link, list = {} }
        byItem[key] = v
    end
    v.list[#v.list + 1] = offer
end

local function NoteSlice(s, rows, ms)
    s.slices, s.ms = s.slices + 1, s.ms + ms
    if ms > s.max then s.max = ms end
    s.rows = s.rows + rows
    -- zu teuer: ab der dritten Scheibe im Mittel über dem Richtwert – dann nur noch Waffen und Rüstung (für die Sitzung)
    if s.links == "all" and s.slices >= 3 and s.ms / s.slices > Prices.SCAN_FRAME_MS then
        s.links, s.auto = "gear", true
        linkMode, linkAuto = "gear", true
    end
end

local function FinishScan()
    local store, n = Store(true)
    local count, now, variants = 0, Now(), 0
    for itemID, offers in pairs(store and scanning.offers or {}) do
        -- AH-01: Abwandlungen getrennt (wie die Einzelsuche); der allgemeine Satz danach mit allen Angeboten, so bleibt
        -- Prices.Get(itemID) der Tiefstpreis über alle
        for _, v in pairs(scanning.vars[itemID] or {}) do
            local vmin, vmarket, vqty, vtop = Prices.MarketValue(v.list)
            if vmin then
                RememberVariant(store, itemID, v.link, vmin, vmarket, vqty, now, "scan", vtop, n, true)
                variants = variants + 1
            end
        end
        local min, market, qty, top = Prices.MarketValue(offers)
        if min then
            Remember(store, itemID, min, market, qty, now, true, "scan", top, n)
            count = count + 1
        end
    end
    if count > 0 then LogCapture(store, "scan", count, now) end
    local s = scanning
    lastScan = { rows = s.rows, slices = s.slices, ms = s.ms, max = s.max, links = s.linksRead, linkMode = s.links,
        variants = variants, retried = #s.retry, skipped = s.skipped, auto = s.auto or false, items = count, t = now }
    local reason = s.reason
    scanning = nil
    Core.Fire("PRICES_SCAN_DONE", count, reason)
end

-- Unvollständige Zeilen ein zweites Mal lesen (in Scheiben wie der erste Durchgang), danach fertig
local function RetryBatch()
    local s = scanning
    if not s then return end
    local AH = C_AuctionHouse
    local t0 = SliceClock()
    local last = math.min(s.retryAt + Prices.SCAN_SLICE_ROWS - 1, #s.retry)
    for i = s.retryAt, last do ReadRow(s, AH, s.retry[i], true) end
    NoteSlice(s, last - s.retryAt + 1, SliceClock() - t0)
    s.retryAt = last + 1
    if s.retryAt > #s.retry then FinishScan() else C_Timer.After(0, RetryBatch) end
end

local function ReadBatch()
    local s = scanning
    if not s then return end
    local AH = C_AuctionHouse
    local t0 = SliceClock()
    local last = math.min(s.done + Prices.SCAN_SLICE_ROWS, s.total)
    for index = s.done, last - 1 do ReadRow(s, AH, index, false) end
    NoteSlice(s, last - s.done, SliceClock() - t0)
    s.done = last
    Core.Fire("PRICES_SCAN_PROGRESS", s.done, s.total)
    if s.done < s.total then
        C_Timer.After(0, ReadBatch)
    elseif #s.retry > 0 then
        s.retryAt = 1
        C_Timer.After(Prices.SCAN_RETRY_DELAY, RetryBatch)
    else
        FinishScan()
    end
end

local function NewRun(total, waiting, reason)
    return { offers = {}, vars = {}, classes = {}, requested = {}, retry = {}, done = 0, total = total or 0,
        waiting = waiting, reason = reason, links = linkMode, linksRead = 0, skipped = 0, rows = 0, slices = 0, ms = 0,
        max = 0 }
end

-- Rücksicht (AH-03, Schlüssel auctionScan): ein anderes Addon nutzt den Komplett-Scan und damit dieselbe kontoweite
-- Sperrzeit – ezCore startet dann keinen Scan von selbst (seine Liste wird trotzdem mitgelesen, Grund "other").
function Prices.ScanYields()
    return Core.WhoHandles and Core.WhoHandles("auctionScan") or nil
end

-- Rückgabe: true – oder false, Grund und bei "unsupported" die genaue Ursache (Spielbefund vom 21.11.2026: ezAuction
-- meldete „lehnt dieser Client ab“, obwohl Forevers Client alle Aufrufe hat – Gethe/wow-ui-source, Zweig forever,
-- AuctionHouseDocumentation.lua): "api" (Aufruf fehlt), "db"/"realm"/"readonly"/"store" (keine beschreibbare
-- Preisablage: ezCore fehlt die Ablage, Realm oder Fraktion unbekannt, Ablage einer neueren Fassung, sonst), "call" und
-- Blizzards Fehlertext als vierter Wert.
function Prices.Scan(opts)
    local AH = C_AuctionHouse
    if not (AH and AH.ReplicateItems and AH.GetNumReplicateItems and AH.GetReplicateItemInfo) then return false, "unsupported", "api" end
    if not isOpen then return false, "closed" end
    if scanning then return false, "busy" end
    -- Rücksicht vor der Sperrzeit: läuft ein anderes Addon, startet ezCore von selbst nie – auch nicht nach der Sperrzeit
    if type(opts) == "table" and opts.auto and Prices.ScanYields() then return false, "other" end
    if Prices.ScanReadyIn() > 0 then return false, "wait" end
    local store, area = Store(true)
    if not store then
        local M = Market()
        local why = ((not M or not Core.Call(M.Root)) and "db") or (area == nil and "realm") or (M.Readonly and Core.Call(M.Readonly) == true and "readonly") or "store"
        -- Grund "realm": was der Client liefert, als vierter Wert (Spielbefund vom 21.11.2026; Keys.MarketWhy)
        local Keys = Core.DB and Core.DB.Keys
        local detail = why == "realm" and Keys and Keys.MarketWhy and Core.Call(Keys.MarketWhy) or nil
        return false, "unsupported", why, detail
    end
    local run = NewRun(0, true)
    scanning = run
    local ok, err = pcall(AH.ReplicateItems)
    if not ok then
        -- W-52: kein Zeitpunkt gemerkt – Blizzard hat nichts angenommen, also auch nichts zu warten
        scanning = nil
        return false, "unsupported", "call", tostring(err)
    end
    SetScanAt(Now())
    -- W-52: Bleibt Blizzards Liste aus, hängt „Erfasse …“ sonst bis zum Schließen. Kommt sie später doch,
    -- liest REPLICATE_ITEM_LIST_UPDATE sie trotzdem.
    C_Timer.After(Prices.SCAN_TIMEOUT, function()
        if scanning == run and run.waiting then
            scanning, lateOwn = nil, true
            Core.Fire("PRICES_SCAN_DONE", 0, "timeout")
        end
    end)
    return true
end

-- Blizzards Liste ist da: der eigene Scan, ein später (nach der Frist) oder einer, den ein anderes Addon ausgelöst
-- hat (Grund "other") – gelesen, solange nicht schon eine gelesen wird. Ein fremder Scan startet Blizzards Sperre
-- ebenso. Blizzard meldet dieselbe Liste mehrmals (nachgeladene Gegenstandsdaten, erneuter Aufruf eines anderen
-- Addons): ohne eigenen wartenden Scan wird höchstens eine Liste je Sperrfrist gelesen.
ns.On("REPLICATE_ITEM_LIST_UPDATE", function()
    if scanning and not scanning.waiting then return end
    local AH = C_AuctionHouse
    if not (AH and AH.GetNumReplicateItems and AH.GetReplicateItemInfo) then return end
    local ok, count = pcall(AH.GetNumReplicateItems)
    local total = ok and Core.Num(count) or 0
    if scanning then
        scanning.waiting = false
        scanning.total = total
        Prices.NoteOwnScan()
    else
        if total <= 0 then return end
        if not lateOwn and Now() - readAt < SCAN_COOLDOWN then return end
        if Prices.ScanReadyIn() <= 0 then SetScanAt(Now()) end
        scanning = NewRun(total, false, not lateOwn and "other" or nil)
    end
    lateOwn, readAt = false, Now()
    ReadBatch()
end)

---------------------------------------------------------------------------
-- Gegenstands-Schlüssel (AH-04)
---------------------------------------------------------------------------

local function KeyTable(itemID, level, suffix, species)
    local AH = rawget(_G, "C_AuctionHouse")
    if type(AH) == "table" and type(AH.MakeItemKey) == "function" then
        local ok, key = pcall(AH.MakeItemKey, itemID, level, suffix, species)
        if ok and type(key) == "table" and not Core.IsSecret(key) then return key end
    end
    return { itemID = itemID, itemLevel = level, itemSuffix = suffix, battlePetSpeciesID = species }
end

-- Basis- und volle Form aus Blizzards ItemKey (itemID, itemLevel, itemSuffix, battlePetSpeciesID). Aus einem Link
-- kommen Suffix (Keys.Variant) und Begleiter-Art; die Stufe nur, wenn der Client sie für den Link nennt
-- (C_Item.GetDetailedItemLevelInfo), sonst 0. Aus einer itemID sind beide Formen gleich. → basis, voll oder nil
function Prices.ItemKey(item)
    if Core.IsSecret(item) then return nil end
    local itemID, level, suffix, species = nil, 0, 0, 0
    if type(item) == "table" then
        if Core.IsSecret(item.itemID) or Core.IsSecret(item.itemLevel) or Core.IsSecret(item.itemSuffix)
            or Core.IsSecret(item.battlePetSpeciesID) then return nil end
        itemID = Core.Num(item.itemID)
        level, suffix = Core.Num(item.itemLevel) or 0, Core.Num(item.itemSuffix) or 0
        species = Core.Num(item.battlePetSpeciesID) or 0
    elseif type(item) == "string" then
        species = tonumber(item:match("battlepet:(%d+)") or "") or 0
        itemID = species > 0 and 82800 or ItemID(item)   -- Begleiter im Käfig: Blizzards Käfig-Gegenstand
        local _, parts = Core.DB.Keys.Variant(item)
        suffix = parts and parts.sfx or 0
        local api = rawget(_G, "C_Item")
        if species == 0 and type(api) == "table" and type(api.GetDetailedItemLevelInfo) == "function" then
            local ok, lvl = pcall(api.GetDetailedItemLevelInfo, item)
            if ok and not Core.IsSecret(lvl) then level = Core.Num(lvl) or 0 end
        end
    else
        itemID = Core.Num(item)
    end
    if not itemID or itemID <= 0 then return nil end
    return KeyTable(itemID, 0, 0, species), KeyTable(itemID, level, suffix, species)
end

local function KeyText(key)
    return table.concat({ tostring(key.itemID), tostring(key.itemLevel or 0), tostring(key.itemSuffix or 0),
        tostring(key.battlePetSpeciesID or 0) }, ":")
end

---------------------------------------------------------------------------
-- Regeln des Hauses je Bereich (AH-04) und Netto-Erlös (AH-06)
---------------------------------------------------------------------------

Prices.DEPOSIT_SAMPLES = 5      -- so viele Taschen-Gegenstände mit Händlerpreis misst ezCore bei offenem Haus
Prices.DURATIONS = { 1, 2, 3 }  -- Blizzards drei Laufzeiten (12, 24, 48 Stunden)

local function Rules(create)
    local store = Store(create)
    if not store then return nil end
    if type(store.rules) ~= "table" then
        if not create then return nil end
        store.rules = {}
    end
    return store.rules
end

local function SetRule(name, value, extra)
    local rules = Rules(true)
    if not rules or Core.IsSecret(value) or value == nil then return false end
    local old = type(rules[name]) == "table" and rules[name] or nil
    local e = { v = value, t = Now(), n = ((old and Core.Num(old.n)) or 0) + 1 }
    for k, v in pairs(extra or {}) do e[k] = v end
    rules[name] = e
    Core.Fire("PRICES_RULES_CHANGED", name)
    return true
end
Prices.SetRule = SetRule   -- nur ezCore-intern und für die Prüfungen

-- Tiefe Kopie über Core.CopyTable (Gesamtreview 18.11.2026, T16-7; vorher eine eigene ohne Grenze)
local function CopyDeep(v) return Core.CopyTable(v) end

function Prices.Rules()
    return CopyDeep(Rules(false) or {})
end

-- Gemessene Sperrzeit: kürzester Abstand zweier eigener Scans, die beide eine Liste bekamen – eine Obergrenze (laut
-- Probe X2 kam auch ein zweiter Aufruf direkt danach durch; die Sperrfrist ist nicht belegt).
local lastOwnList
function Prices.NoteOwnScan(at)
    at = Core.Num(at) or Now()
    if lastOwnList and at > lastOwnList then
        local gap = at - lastOwnList
        local old = (Rules(false) or {}).cooldown
        if not (type(old) == "table" and Core.Num(old.v) and old.v <= gap) then SetRule("cooldown", gap, { upper = true }) end
    end
    lastOwnList = at
end

-- Händlerpreis eines Gegenstands (11. Rückgabe von GetItemInfo), nil ohne Angabe
local function VendorPrice(item)
    local api = rawget(_G, "C_Item")
    local fn = type(api) == "table" and api.GetItemInfo or rawget(_G, "GetItemInfo")
    if type(fn) ~= "function" then return nil end
    local ok, _, _, _, _, _, _, _, _, _, _, sell = pcall(fn, item)
    sell = ok and Core.Num(sell) or nil
    return sell and sell > 0 and sell or nil
end

local function IsCommodity(location)
    local AH = rawget(_G, "C_AuctionHouse")
    if type(AH) ~= "table" or type(AH.GetItemCommodityStatus) ~= "function" then return nil end
    local ok, status = pcall(AH.GetItemCommodityStatus, location)
    status = ok and Core.Num(status) or nil
    local enum = Enum and Enum.ItemCommodityStatus
    local commodity = enum and Core.Num(enum.Commodity) or 2
    local single = enum and Core.Num(enum.Item) or 1
    if status == commodity then return true end
    if status == single then return false end
    return nil
end

local function BagLocation(bag, slot)
    local IL = rawget(_G, "ItemLocation")
    if type(IL) == "table" and type(IL.CreateFromBagAndSlot) == "function" then
        local ok, loc = pcall(IL.CreateFromBagAndSlot, IL, bag, slot)
        if ok and loc then return loc end
    end
    return { bagID = bag, slotIndex = slot }
end

-- Blizzards Anzahlung für eine Menge eines Gegenstands und eine Dauer – nur bei offenem Haus. → Kupfer oder nil
local function BlizzardDeposit(itemID, location, commodity, duration, qty)
    local AH = rawget(_G, "C_AuctionHouse")
    if not (isOpen and type(AH) == "table") then return nil end
    local ok, v
    if commodity and type(AH.CalculateCommodityDeposit) == "function" then
        ok, v = pcall(AH.CalculateCommodityDeposit, itemID, duration, qty)
    elseif location and type(AH.CalculateItemDeposit) == "function" then
        ok, v = pcall(AH.CalculateItemDeposit, location, duration, qty)
    end
    v = ok and Core.Num(v) or nil
    return v and v >= 0 and v or nil
end

-- Taschenplatz eines Gegenstands (für CalculateItemDeposit) und ob er eine Ware ist
local function FindInBags(itemID)
    local found
    if Core.ForEachBagItem then
        Core.ForEachBagItem(function(bag, slot, info)
            if not found and Core.Num(info.itemID) == itemID then found = { bag = bag, slot = slot } end
        end)
    end
    if not found then return nil end
    local loc = BagLocation(found.bag, found.slot)
    return loc, IsCommodity(loc)
end

-- Verhältnis Anzahlung zu Händlerpreis je Dauer messen: bis zu DEPOSIT_SAMPLES Taschen-Gegenstände mit Händlerpreis,
-- je Dauer der Mittelwert. → Zahl der gemessenen Gegenstände
function Prices.MeasureDeposits()
    if not isOpen then return 0 end
    local samples, seen = {}, {}
    if Core.ForEachBagItem then
        Core.ForEachBagItem(function(bag, slot, info)
            local id = Core.Num(info.itemID)
            if #samples >= Prices.DEPOSIT_SAMPLES or not id or seen[id] or Core.Bool(info.isBound, false) == true then return end
            local sell = VendorPrice(id)
            if not sell then return end
            seen[id] = true
            local loc = BagLocation(bag, slot)
            samples[#samples + 1] = { id = id, sell = sell, loc = loc, commodity = IsCommodity(loc) }
        end)
    end
    if #samples == 0 then return 0 end
    for _, sample in ipairs(samples) do
        if sample.commodity ~= nil then SetRule("split", true) break end
    end
    for _, duration in ipairs(Prices.DURATIONS) do
        local sum, n = 0, 0
        for _, sample in ipairs(samples) do
            local dep = BlizzardDeposit(sample.id, sample.loc, sample.commodity, duration, 1)
            if dep then sum, n = sum + dep / sample.sell, n + 1 end
        end
        if n > 0 then
            local rules = Rules(true)
            rules.deposit = type(rules.deposit) == "table" and rules.deposit or {}
            rules.deposit[duration] = { v = math.floor(sum / n * 10000 + 0.5) / 10000, t = Now(), n = n }
        end
    end
    Core.Fire("PRICES_RULES_CHANGED", "deposit")
    return #samples
end

-- Anteil des Hauses aus einer eigenen Verkaufsabrechnung (History „auction“, type "sale": gross Brutto, fee Gebühr)
local function NoteSale(kind, e)
    if kind ~= "auction" or type(e) ~= "table" or e.type ~= "sale" then return end
    local gross, fee = Core.Num(e.gross), Core.Num(e.fee)
    if not (gross and fee and gross > 0 and fee >= 0 and fee <= gross) then return end
    SetRule("cut", math.floor(fee / gross * 10000 + 0.5) / 10000)
end
Core.Listen("HISTORY_ADDED", NoteSale, "ezCore.Prices")

local function Stand(t, now)
    if now then return { now = true } end
    return { at = t }
end

function Prices.StandText(stand)
    if type(stand) ~= "table" then return nil end
    if stand.now then return Core.L.PRICES_STAND_NOW end
    if Core.Num(stand.at) then return Core.L.PRICES_STAND_AT:format(Core.DateText(stand.at, "day")) end
    return nil
end

-- Netto-Erlös (AH-06): preis = Stückpreis in Kupfer, dauer 1–3 (Standard 2), menge (Standard 1). Unbekanntes bleibt nil.
function Prices.Net(item, price, duration, qty)
    price, qty = Core.Num(price), math.max(1, math.floor(Core.Num(qty) or 1))
    duration = Core.Num(duration) or 2
    if not price or price < 0 then return nil end
    local itemID = ItemID(item)
    local rules = Rules(false) or {}
    local out = { brutto = math.floor(price * qty + 0.5), bekannt = { erloes = false, anteil = false, anzahlung = false },
        stand = {} }
    local cut = type(rules.cut) == "table" and Core.Num(rules.cut.v)
    if cut then
        out.anteil = math.floor(out.brutto * cut + 0.5)
        out.bekannt.anteil, out.stand.anteil = true, Stand(rules.cut.t)
        out.erloes = out.brutto - out.anteil
        out.bekannt.erloes, out.stand.erloes = true, out.stand.anteil
    end
    if itemID and isOpen then
        local loc, commodity = FindInBags(itemID)
        local dep = BlizzardDeposit(itemID, loc, commodity ~= false and (commodity or not loc), duration, qty)
        if dep then out.anzahlung, out.bekannt.anzahlung, out.stand.anzahlung = dep, true, Stand(nil, true) end
    end
    if not out.bekannt.anzahlung and itemID then
        local d = type(rules.deposit) == "table" and rules.deposit[duration]
        local ratio = type(d) == "table" and Core.Num(d.v)
        local sell = ratio and VendorPrice(itemID)
        if sell then
            out.anzahlung = math.floor(ratio * sell * qty + 0.5)
            out.bekannt.anzahlung, out.stand.anzahlung = true, Stand(d.t)
        end
    end
    return out
end

-- Abdeckung: Anteil der Gegenstände mit einem Preis von heute (Serverzeit). → Anteil 0–1, mit Preis von heute, gesamt
function Prices.Coverage(items)
    local today, total, fresh, seen = Prices.Day(Now()), 0, 0, {}
    for _, item in ipairs(type(items) == "table" and items or {}) do
        local id = ItemID(item)
        local key = id and (tostring(id) .. ":" .. tostring(Prices.VariantOf(item) or ""))
        if key and not seen[key] then
            seen[key] = true
            total = total + 1
            local info = Prices.Get(item)
            if info and Core.Num(info.seen) and Prices.Day(info.seen) == today then fresh = fresh + 1 end
        end
    end
    return total > 0 and fresh / total or 0, fresh, total
end

---------------------------------------------------------------------------
-- Beobachtetes: Anbieter-Register (AH-03)
---------------------------------------------------------------------------

Prices.WATCH_MAX = 200
local watchProviders, watchOrder = {}, {}
local watchSetAt, watchSet

function Prices.AddWatchProvider(key, fn, maxItems)
    if type(key) ~= "string" or key == "" then return false end
    if watchProviders[key] == nil then watchOrder[#watchOrder + 1] = key end
    watchProviders[key] = type(fn) == "function" and { fn = fn, max = Core.Num(maxItems) or Prices.WATCH_MAX } or false
    watchSet = nil
    return true
end

function Prices.WatchList(limit)
    limit = Core.Num(limit)
    local out, seen = {}, {}
    for _, key in ipairs(watchOrder) do
        local p = watchProviders[key]
        if p then
            local ok, list = Core.Try(key, "Prices.WatchList", p.fn)
            local taken = 0
            for _, item in ipairs(ok and type(list) == "table" and list or {}) do
                if taken >= p.max then break end
                local id = not Core.IsSecret(item) and ItemID(item)
                local dedupe = id and (tostring(id) .. ":" .. tostring(Prices.VariantOf(item) or ""))
                if dedupe and not seen[dedupe] then
                    seen[dedupe] = true
                    taken = taken + 1
                    out[#out + 1] = { item = item, itemID = id, from = key }
                    if limit and #out >= limit then return out end
                end
            end
        end
    end
    return out
end

-- „beobachtet?“ (Prices.IsObserved) fragt die Anbieter höchstens einmal je Prices.OWNED_TIME Sekunden
function Prices.WatchSet(fresh)
    local up = Core.Uptime()
    if fresh or not watchSet or not watchSetAt or up < watchSetAt or up - watchSetAt >= Prices.OWNED_TIME then
        watchSet, watchSetAt = {}, up
        for _, e in ipairs(Prices.WatchList()) do watchSet[e.itemID] = true end
    end
    return watchSet
end

-- A22 (Welle 23b): handelbare (nicht gebundene) Taschen-Gegenstände als Link bzw. itemID – eine Fassung für den
-- Anbieter „ezCore.bags“ und die Module (vorher eine Kopie in ezAuction, Scan.BagItems). bags wie bei
-- Core.ForEachBagItem: Art ("carried", "sell", "bank") oder Liste; ohne Angabe die normalen Taschen.
function Prices.BagItems(bags)
    local out = {}
    if Core.ForEachBagItem then
        Core.ForEachBagItem(function(_, _, info)
            if Core.Bool(info.isBound, false) ~= true then out[#out + 1] = Core.Plain(info.hyperlink) or Core.Num(info.itemID) end
        end, bags)
    end
    return out
end

-- ezCore selbst: Taschen (handelbare Gegenstände) und eigene Auktionen bzw. Verkäufe der letzten 30 Tage
Prices.AddWatchProvider("ezCore.bags", function() return Prices.BagItems() end)

Prices.AddWatchProvider("ezCore.auctions", function()
    local out = {}
    local AH = rawget(_G, "C_AuctionHouse")
    if isOpen and type(AH) == "table" and type(AH.GetNumOwnedAuctions) == "function" and type(AH.GetOwnedAuctionInfo) == "function" then
        local ok, n = pcall(AH.GetNumOwnedAuctions)
        for i = 1, ok and Core.Num(n) or 0 do
            local okI, info = pcall(AH.GetOwnedAuctionInfo, i)
            if okI and type(info) == "table" and type(info.itemKey) == "table" then out[#out + 1] = info.itemKey end
        end
    end
    local H = Core.History
    if H and H.List and H.Since then
        for _, e in ipairs(H.List("auction", { since = H.Since(30), limit = 200 })) do
            if (e.type == "sale" or e.type == "expired" or e.type == "cancelled") and type(e.link) == "string" then
                out[#out + 1] = e.link
            end
        end
    end
    return out
end)

---------------------------------------------------------------------------
-- Die eine Abfrage-Warteschlange (AH-03)
---------------------------------------------------------------------------

local Queue = {}
Prices.Queue = Queue
Queue.RANKS = { user = 1, module = 2, capture = 3 }
Queue.ALIASES = { nutzer = "user", modul = "module", erfassung = "capture" }
Queue.TIMEOUT = 15       -- Sekunden, die ein Auftrag auf seine Antwort warten darf
Queue.USER_HOLD = 10     -- so lange nach einer eigenen Suche des Spielers startet kein Auftrag
Queue.AUTO_SECONDS = 1   -- so kurz nach dem Öffnen gilt Blizzards Abfrage der Favoriten als automatisch (OnShow)
Queue.AUTO_HOLD = 2      -- so lange startet danach kein Auftrag (die Liste gehört Blizzards Anzeige)
Queue.RETRY = 0.5        -- erneut versuchen, wenn das Nachrichtensystem gerade drosselt

local waiting, current, nextID = {}, nil, 0
local userUntil, ownDepth, pumpPlanned = 0, 0, false
-- Ende der Haltezeit nach Blizzards Favoriten-Abfrage (AUTO_HOLD), getrennt von userUntil (USER_HOLD): Ein Klick
-- beendet nur die Haltezeit nach einer eigenen Suche, Blizzards Liste bleibt ihrer Anzeige (Gegenprüfung Welle 23b).
local autoUntil, autoPlanned = 0, false
local clickPlanned = false   -- eigener Wiederholungs-Zeitgeber für einen Klick-Auftrag bei gedrosseltem Nachrichtensystem
local userListeners = {}

-- Läuft gerade eine Haltezeit (eigene Suche oder Blizzards Favoriten-Abfrage)?
local function Held() return Core.Uptime() < userUntil or Core.Uptime() < autoUntil end

local function Ready()
    local AH = rawget(_G, "C_AuctionHouse")
    local fn = type(AH) == "table" and AH.IsThrottledMessageSystemReady
    if type(fn) ~= "function" then return true end
    local ok, yes = pcall(fn)
    return not ok or Core.Bool(yes, true) ~= false
end

function Queue.Own(fn, ...)
    ownDepth = ownDepth + 1
    local res = { pcall(fn, ...) }
    ownDepth = ownDepth - 1
    return unpack(res)
end

local function OwnerInfo(job)
    return { key = job.key, rank = job.rank, text = job.text, origin = job.origin, id = job.id }
end

function Queue.Owner()
    if current then return OwnerInfo(current) end
    if Held() then return { rank = "user" } end
    return nil
end

function Queue.Pending() return #waiting end

local function Changed() Core.Fire("PRICES_QUEUE_CHANGED", Queue.Owner()) end

local Pump

local function Plan(delay)
    if pumpPlanned then return end
    pumpPlanned = true
    C_Timer.After(delay or Queue.RETRY, function()
        pumpPlanned = false
        Pump()
    end)
end

local function Insert(job, front)
    local at = #waiting + 1
    for i, other in ipairs(waiting) do
        local before = Queue.RANKS[job.rank] < Queue.RANKS[other.rank]
            or (front and Queue.RANKS[job.rank] == Queue.RANKS[other.rank])
        if before then at = i break end
    end
    table.insert(waiting, at, job)
end

-- Auftrag beenden: why "done" (fertig), sonst Grund für cancel ("timeout", "user", "closed", "cancel", "replaced")
local function Finish(job, why)
    if current == job then current = nil end
    if why ~= "done" and job.cancel then Core.Try(job.owner, "Prices.Queue cancel", job.cancel, job, why) end
    Changed()
end

-- A23 (Welle 23b): Auftrag aus einem Klick des Spielers? (Rang „user“ bzw. „nutzer“ oder Feld click = true)
local function FromClick(job) return job.rank == "user" or job.click == true end

Pump = function()
    if current or #waiting == 0 then return end
    if not isOpen then return end
    -- Blizzards Favoriten-Abfrage: auch ein Klick wartet, sonst bekäme er Blizzards Liste als eigene Antwort
    -- (eigener Zeitgeber: ein schon geplanter Lauf zum Ende von USER_HOLD käme für einen Klick zu spät)
    local autoWait = autoUntil - Core.Uptime()
    if autoWait > 0 then
        if not autoPlanned then
            autoPlanned = true
            C_Timer.After(autoWait, function()
                autoPlanned = false
                Pump()
            end)
        end
        return
    end
    local at = 1
    local wait = userUntil - Core.Uptime()
    if wait > 0 then
        -- Ein Klick wartet die Haltezeit nach einer eigenen Suche nicht ab: Der Spieler hat sich gerade für diesen
        -- Auftrag entschieden. Die Haltezeit endet damit (sonst bekäme der Auftrag seine Antwort nicht, Running).
        at = nil
        for i, job in ipairs(waiting) do
            if FromClick(job) then at = i break end
        end
        if not at then Plan(wait) return end
    end
    if not Ready() then
        -- Ein Klick innerhalb der Haltezeit: der schon geplante Lauf käme erst an ihrem Ende (Plan ist dann belegt);
        -- eigener Zeitgeber im Takt von RETRY (Befund des Reviews vom 21.11.2026, wie autoPlanned oben)
        if wait > 0 then
            if not clickPlanned then
                clickPlanned = true
                C_Timer.After(Queue.RETRY, function()
                    clickPlanned = false
                    Pump()
                end)
            end
        else
            Plan()
        end
        return
    end
    if wait > 0 then userUntil = Core.Uptime() end
    local job = table.remove(waiting, at)
    current, job.token, job.startedAt = job, (job.token or 0) + 1, Core.Uptime()
    Changed()
    local ok = Queue.Own(job.start, job)
    if not ok and current == job then Finish(job, "error") Pump() return end
    Queue.Arm(job, true)
end

-- Frist des laufenden Auftrags (neu) stellen: ein Auftrag, der weitere Seiten anfordert (RequestMoreBrowseResults),
-- bekommt je Seite die volle Frist – sonst zählte job.timeout bzw. Queue.TIMEOUT für alle Seiten zusammen
-- (Gegenprüfung Welle 13). → true, wenn job der laufende Auftrag ist
function Queue.Arm(job, first)
    if current ~= job or type(job) ~= "table" then return false end
    if not first then job.token, job.startedAt = (job.token or 0) + 1, Core.Uptime() end
    local token = job.token
    C_Timer.After(job.timeout or Queue.TIMEOUT, function()
        if current == job and job.token == token then
            Finish(job, "timeout")
            Pump()
        end
    end)
    return true
end

function Queue.Add(job)
    if type(job) ~= "table" then return nil, "job" end
    job.key = job.key or job.schluessel
    job.rank = Queue.ALIASES[job.rank or job.rang] or job.rank or job.rang or "module"
    job.cancel = job.cancel or job.abbruch
    if type(job.key) ~= "string" or job.key == "" or type(job.start) ~= "function" or not Queue.RANKS[job.rank] then
        return nil, "job"
    end
    for i = #waiting, 1, -1 do
        if waiting[i].key == job.key then
            local old = table.remove(waiting, i)
            if old.cancel then Core.Try(old.owner, "Prices.Queue cancel", old.cancel, old, "replaced") end
        end
    end
    nextID = nextID + 1
    job.id = nextID
    Insert(job)
    Pump()
    return job.id
end

function Queue.Done(which)
    if current and (current.id == which or current.key == which) then
        Finish(current, "done")
        Pump()
        return true
    end
    return false
end

-- A24 (Welle 23b): Queue.Cancel(schlüssel) wie bisher, oder Queue.Cancel({ rank|rang, prefix|vorsilbe, owner }) – alle
-- Aufträge, auf die jede genannte Angabe passt (z. B. { prefix = "refresh:" } oder { rank = "capture" }). Ein leerer
-- Filter passt auf nichts.
local function Matcher(which)
    if type(which) ~= "table" then return function(job) return job.key == which end end
    local rank = which.rank or which.rang
    rank = Queue.ALIASES[rank] or rank
    local prefix = which.prefix or which.vorsilbe
    local owner = which.owner
    if rank == nil and prefix == nil and owner == nil then return function() return false end end
    return function(job)
        if rank ~= nil and job.rank ~= rank then return false end
        if prefix ~= nil and (type(job.key) ~= "string" or job.key:sub(1, #tostring(prefix)) ~= tostring(prefix)) then
            return false
        end
        if owner ~= nil and job.owner ~= owner then return false end
        return true
    end
end

function Queue.Cancel(key)
    local n = 0
    local match = Matcher(key)
    for i = #waiting, 1, -1 do
        if match(waiting[i]) then
            local job = table.remove(waiting, i)
            if job.cancel then Core.Try(job.owner, "Prices.Queue cancel", job.cancel, job, "cancel") end
            n = n + 1
        end
    end
    if current and match(current) then
        Finish(current, "cancel")
        n = n + 1
        Pump()
    end
    return n
end

function Queue.OnUserSearch(owner, fn)
    if type(fn) ~= "function" then return false end
    userListeners[#userListeners + 1] = { owner = owner, fn = fn }
    return true
end

-- Der Spieler sucht selbst: Erfassung anhalten (sie läuft nach USER_HOLD neu an), Modul-Suche abbrechen
function Queue.UserSearched(how)
    if ownDepth > 0 then return false end
    userUntil = Core.Uptime() + Queue.USER_HOLD
    local info = { how = how }
    local job = current
    if job then
        current = nil
        if job.rank == "capture" then
            info.paused = job.key
            if job.pause then Core.Try(job.owner, "Prices.Queue pause", job.pause, job) end
            Insert(job, true)
        else
            info.cancelled = job.key
            if job.cancel then Core.Try(job.owner, "Prices.Queue cancel", job.cancel, job, "user") end
        end
    end
    for _, l in ipairs(userListeners) do Core.Try(l.owner, "Prices.Queue.OnUserSearch", l.fn, info) end
    Core.Fire("PRICES_QUEUE_USER", info)
    Changed()
    Plan(Queue.USER_HOLD)
    return true
end

-- Blizzard fragt selbst (Favoriten beim Öffnen): nur kurz anhalten, ohne Meldung und ohne Abbruch
function Queue.AutoQuery()
    if ownDepth > 0 then return false end
    local untilAt = Core.Uptime() + Queue.AUTO_HOLD
    if untilAt > autoUntil then autoUntil = untilAt end
    Plan(Queue.AUTO_HOLD)
    return true
end

-- Wem gehört die gerade kommende Antwort? Der laufende Auftrag (nicht während einer eigenen Suche des Spielers)
local function Running()
    if current and not Held() then return current end
    return nil
end
Queue.Running = Running

local function Deliver(results, how)
    local job = Running()
    if job and job.onResults then Core.Try(job.owner, "Prices.Queue onResults", job.onResults, job, results, how) end
end

-- Haken auf Blizzards Suche (sobald Blizzard_AuctionHouseUI geladen ist; nur hooksecurefunc, Leitlinie 5). Laut
-- Blizzards Quelle (wow-ui-source, Zweig forever, Blizzard_AuctionHouseFrame.lua): SendBrowseQuery ruft
-- SendBrowseQueryInternal (auch beim Sortieren), die Gegenstandssuche läuft über QueryItem bzw. RefreshSearchResults
-- (Klick auf eine Ergebniszeile, Verkaufen), QueryAll fragt Favoriten, eigene Auktionen oder Gebote ab. OnShow fragt bei
-- vorhandenen Favoriten selbst QueryAll(AllFavorites), ADDON_LOADED QueryAll(AllBids).
Queue.USER_METHODS = { "SendBrowseQuery", "SendBrowseQueryInternal", "QueryAll", "QueryItem", "RefreshSearchResults" }
local hookedFrame, lastUserAt, openedAt
local function OnBlizzardQuery(method, searchContext)
    if ownDepth > 0 then return end
    local now = Core.Uptime()
    local C = rawget(_G, "AuctionHouseSearchContext")
    if method == "QueryAll" and type(C) == "table" and searchContext ~= nil then
        if searchContext == C.AllAuctions or searchContext == C.AllBids then return end   -- eigene Listen, keine Suche
        if searchContext == C.AllFavorites and (not isOpen or (openedAt and now - openedAt <= Queue.AUTO_SECONDS)) then
            Queue.AutoQuery()
            return
        end
    end
    if lastUserAt == now then return end   -- RefreshSearchResults » QueryItem, SendBrowseQuery » …Internal: eine Suche
    lastUserAt = now
    Queue.UserSearched(method)
end
local function HookUserSearch()
    local frame = rawget(_G, "AuctionHouseFrame")
    if type(frame) ~= "table" or hookedFrame == frame or type(hooksecurefunc) ~= "function" then return end
    hookedFrame = frame
    for _, method in ipairs(Queue.USER_METHODS) do
        if type(frame[method]) == "function" then
            hooksecurefunc(frame, method, function(_, searchContext) OnBlizzardQuery(method, searchContext) end)
        end
    end
end
Prices.HookUserSearch = HookUserSearch

ns.On("ADDON_LOADED", function(_, name) if name == "Blizzard_AuctionHouseUI" then HookUserSearch() end end)

---------------------------------------------------------------------------
-- Gezielte Auffrischung (AH-03)
---------------------------------------------------------------------------

Prices.REFRESH_CHUNK = 40         -- Schlüssel je Sammelabfrage (laut Probe X6 mit 1, 10 und 40 belegt)
Prices.REFRESH_SINGLE_MAX = 20    -- Rückfall: Suchen je Gegenstand höchstens so viele je Aufruf
Prices.REFRESH_MORE = 5           -- so oft fragt eine Sammelabfrage weitere Zeilen nach (RequestMoreBrowseResults)
local refreshMode                 -- nil: unbekannt (erst Sammelabfrage), "single" nach falscher Antwortform

function Prices.RefreshMode()
    local AH = rawget(_G, "C_AuctionHouse")
    if refreshMode then return refreshMode end
    return (type(AH) == "table" and type(AH.SearchForItemKeys) == "function") and "bulk" or "single"
end
function Prices.ResetRefreshMode() refreshMode = nil end

local function Sorts()
    local enum = Enum and Enum.AuctionHouseSortOrder
    return { { sortOrder = enum and Core.Num(enum.Price) or 0, reverseSort = false } }
end

-- Antwortform der Übersicht: Liste von Zeilen mit itemKey (Tabelle) und minPrice (Zahl); leer ist erlaubt
local function BrowseShapeOK(results)
    if type(results) ~= "table" or Core.IsSecret(results) then return false end
    local first = results[1]
    if first == nil then return true end
    return type(first) == "table" and type(first.itemKey) == "table" and Core.Num(first.minPrice) ~= nil
end
Prices.BrowseShapeOK = BrowseShapeOK

local QueueSingles

local function QueueBulk(keys, rank, click)
    local n = 0
    for i = 1, #keys, Prices.REFRESH_CHUNK do
        local chunk = {}
        for j = i, math.min(i + Prices.REFRESH_CHUNK - 1, #keys) do chunk[#chunk + 1] = keys[j] end
        local job = { key = "refresh:bulk:" .. KeyText(chunk[1]), rank = rank, origin = "bulk", owner = "ezCore",
            text = Core.L.PRICES_QUEUE_REFRESH, keys = chunk, more = 0, click = click }
        job.start = function(self)
            local AH = rawget(_G, "C_AuctionHouse")
            if type(AH) ~= "table" or type(AH.SearchForItemKeys) ~= "function" then error("SearchForItemKeys fehlt") end
            AH.SearchForItemKeys(self.keys, Sorts())
        end
        job.onResults = function(self, results, how)
            if how ~= "browse" then return end
            self.answered = true
            if not BrowseShapeOK(results) then
                refreshMode = "single"
                Queue.Done(self.id)
                QueueSingles(self.keys, self.rank, self.click)
                return
            end
            local AH = rawget(_G, "C_AuctionHouse")
            local full = true
            if type(AH.HasFullBrowseResults) == "function" then
                local okF, yes = pcall(AH.HasFullBrowseResults)
                full = not okF or Core.Bool(yes, true) ~= false
            end
            if not full and self.more < Prices.REFRESH_MORE and type(AH.RequestMoreBrowseResults) == "function" then
                self.more = self.more + 1
                Queue.Own(AH.RequestMoreBrowseResults)
                return
            end
            Queue.Done(self.id)
        end
        job.cancel = function(self, why)
            -- keine Antwort (oder Fehler beim Aufruf): Rückfall auf Suchen je Gegenstand
            if (why == "timeout" or why == "error") and not self.answered then
                refreshMode = "single"
                QueueSingles(self.keys, self.rank, self.click)
            end
        end
        if Queue.Add(job) then n = n + 1 end
    end
    return n
end

QueueSingles = function(keys, rank, click)
    local n = 0
    for i = 1, math.min(#keys, Prices.REFRESH_SINGLE_MAX) do
        local key = keys[i]
        local job = { key = "refresh:one:" .. KeyText(key), rank = rank, origin = "search", owner = "ezCore",
            text = Core.L.PRICES_QUEUE_REFRESH, itemKey = key, click = click }
        job.start = function(self)
            local AH = rawget(_G, "C_AuctionHouse")
            if type(AH) ~= "table" or type(AH.SendSearchQuery) ~= "function" then error("SendSearchQuery fehlt") end
            AH.SendSearchQuery(self.itemKey, Sorts(), true)
        end
        job.onResults = function(self, what, how)
            if how == "search" and ItemID(what) == Core.Num(self.itemKey.itemID) then Queue.Done(self.id) end
        end
        if Queue.Add(job) then n = n + 1 end
    end
    return n
end

function Prices.Refresh(items, reason)
    if not isOpen then return false, "closed" end
    local AH = rawget(_G, "C_AuctionHouse")
    if type(AH) ~= "table" then return false, "unsupported" end
    local list = type(items) == "table" and items or nil
    if not list then
        list = {}
        for _, e in ipairs(Prices.WatchList()) do list[#list + 1] = e.item end
    end
    local keys, seen = {}, {}
    for _, item in ipairs(list) do
        local base, full = Prices.ItemKey(item)
        local key = type(item) == "table" and full or base   -- ein itemKey bleibt, wie er ist; sonst die Basis
        local text = key and KeyText(key)
        if text and not seen[text] then
            seen[text] = true
            keys[#keys + 1] = key
        end
    end
    if #keys == 0 then return false, "empty" end
    -- A23 (Welle 23b): ein Klick wartet die Haltezeit nach einer eigenen Suche nicht ab (Feld click)
    local click = reason == "click" or reason == "klick"
    local rank = click and "module" or "capture"
    local mode = Prices.RefreshMode()
    if mode == "bulk" then return true, QueueBulk(keys, rank, click), mode end
    if type(AH.SendSearchQuery) ~= "function" then return false, "unsupported" end
    return true, QueueSingles(keys, rank, click), mode
end

---------------------------------------------------------------------------
-- Mitlernen bei Suche und Übersicht
---------------------------------------------------------------------------

ns.On("COMMODITY_SEARCH_RESULTS_UPDATED", function(_, itemID)
    local AH = C_AuctionHouse
    itemID = Core.Num(itemID)
    if not (itemID and AH and AH.GetNumCommoditySearchResults and AH.GetCommoditySearchResultInfo) then return end
    local list = {}
    for index = 1, Core.Num(AH.GetNumCommoditySearchResults(itemID)) or 0 do
        local result = AH.GetCommoditySearchResultInfo(itemID, index)
        if type(result) == "table" then list[#list + 1] = { result.unitPrice, result.quantity } end
    end
    Prices.Learn(itemID, list, nil, "search")
    -- AH-04: Waren laufen getrennt von Einzelstücken (dieses Haus antwortet auf eine Warensuche)
    local rules = Rules(false)
    if not (rules and type(rules.split) == "table" and rules.split.v == true) then SetRule("split", true) end
    Deliver(itemID, "search")
end)

ns.On("ITEM_SEARCH_RESULTS_UPDATED", function(_, itemKey)
    local AH = C_AuctionHouse
    local itemID = ItemID(itemKey)
    if not (itemID and AH and AH.GetNumItemSearchResults and AH.GetItemSearchResultInfo) then return end
    local list = {}
    for index = 1, Core.Num(AH.GetNumItemSearchResults(itemKey)) or 0 do
        local result = AH.GetItemSearchResultInfo(itemKey, index)
        local buyout = type(result) == "table" and Core.Num(result.buyoutAmount)
        if buyout then
            local qty = Core.Num(result.quantity) or 1
            list[#list + 1] = { buyout / max(qty, 1), qty }
        end
    end
    Prices.Learn(itemKey, list, nil, "search")   -- mit itemKey: eine Abwandlung (itemSuffix) bekommt ihren eigenen Preis (V-032)
    Deliver(itemKey, "search")
end)

-- W-55: Die Übersicht kommt in vielen Paketen; die Nachricht geht gesammelt einmal hinaus.
local changedSoon = Core.Throttle(function() Core.Fire("PRICES_CHANGED", nil) end, Prices.CHANGED_DELAY, "ezCore")

-- Herkunft der Übersicht: die des laufenden Auftrags (Sammelabfrage, Kategorie), sonst „Übersicht“
local function BrowseKind()
    local job = Running()
    local origin = job and job.origin
    if origin and origin ~= "search" and ScanBit(origin) then return origin end
    return "browse"
end

-- W-54: Menge aller Zeilen desselben Gegenstands zusammenzählen, den Tiefstpreis getrennt als Minimum – so hängt
-- keins von beiden von der Reihenfolge der Zeilen ab.
local function LearnBrowse(results)
    local kind = BrowseKind()
    local seen = {}
    for _, result in ipairs(type(results) == "table" and results or {}) do
        local itemID = type(result) == "table" and ItemID(result.itemKey)
        local min = itemID and Core.Num(result.minPrice)
        if min then
            local info = seen[itemID]
            if not info then
                info = { min = min, qty = 0 }
                seen[itemID] = info
            elseif min < info.min then
                info.min = min
            end
            info.qty = info.qty + (Core.Num(result.totalQuantity) or 0)
        end
    end
    local n = 0
    for itemID, info in pairs(seen) do
        LearnMin(itemID, info.min, info.qty, kind)
        n = n + 1
    end
    if n > 0 then
        LogCapture(Store(true), kind, n, Now())
        changedSoon()
    end
end

ns.On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function()
    if not (C_AuctionHouse and C_AuctionHouse.GetBrowseResults) then return end
    local results = C_AuctionHouse.GetBrowseResults()
    LearnBrowse(results)
    Deliver(results, "browse")
end)
ns.On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", function(_, added)
    LearnBrowse(added)
    Deliver(added, "browse")
end)

ns.On("AUCTION_HOUSE_SHOW", function()
    isOpen, openedAt = true, Core.Uptime()
    HookUserSearch()
    -- AH-04: Regeln des Hauses, die der Client bei offenem Haus nennt
    local AH = rawget(_G, "C_AuctionHouse")
    if type(AH) == "table" and type(AH.SupportsCopperValues) == "function" then
        local ok, yes = pcall(AH.SupportsCopperValues)
        if ok and not Core.IsSecret(yes) and type(yes) == "boolean" then SetRule("copper", yes) end
    end
    C_Timer.After(1, function() if isOpen then Core.Try(nil, "Prices.MeasureDeposits", Prices.MeasureDeposits) end end)
    Pump()
end)
ns.On("AUCTION_HOUSE_CLOSED", function()
    isOpen = false
    if scanning and scanning.waiting then scanning = nil end   -- ohne Liste kein Scan; gelesene Teile laufen zu Ende
    lateOwn = false
    -- Warteschlange leeren: was wartet oder läuft, braucht das offene Haus
    local list = waiting
    waiting = {}
    for _, job in ipairs(list) do
        if job.cancel then Core.Try(job.owner, "Prices.Queue cancel", job.cancel, job, "closed") end
    end
    if current then Finish(current, "closed") end
    userUntil, autoUntil = 0, 0
end)

---------------------------------------------------------------------------
-- Durchlauf je Kategorie über Blizzards Übersichtssuche (AH-02, Welle 13)
---------------------------------------------------------------------------
--[[
    Ausweichweg, falls der Forever-Server den Komplett-Scan nicht bedient (laut Probe X2 bedient er ihn; der Weg bleibt
    für die Sperrfrist und für Häuser ohne ReplicateItems). Empfehlung umgesetzt, Antwort offen (AH-02).
      Prices.ScanBrowse(kategorien, grund) → true, Zahl der Kategorien | false, Grund ("click" – nur aus einem Klick
          des Spielers, grund = "click"; "closed", "busy", "unsupported", "empty")
          kategorien: Liste von { name, filters = { { classID, subClassID, inventoryType } … } } oder Zahlen (classID);
          ohne Angabe Blizzards Kategorien des Auktionshauses (AuctionCategories, nur gelesen), sonst die
          Gegenstandsklassen Prices.BROWSE_CLASSES
      Prices.ScanBrowseStop()  → Zahl abgebrochener Aufträge;  Prices.ScanBrowseState() → { total, done, rows, current,
          paused, stopped, skipped, finished } oder nil
      Nachricht PRICES_BROWSE_PROGRESS (stand) beim Start jeder Kategorie, danach, bei Pause und am Ende (finished)
    Je Kategorie ein Auftrag der Warteschlange mit Rang „erfassung“ (capture) und Herkunft „category“: SendBrowseQuery
    (laut Blizzards AuctionHouseDocumentation, Zweig forever: { searchString, sorts, filters?, itemClassFilters? }),
    weitere Seiten mit RequestMoreBrowseResults, bis HasFullBrowseResults (höchstens Prices.BROWSE_MORE je Kategorie).
    Sucht der Spieler selbst, hält die Warteschlange den Durchlauf an (Queue.USER_HOLD) und setzt ihn danach mit
    derselben Kategorie fort. Gelernt werden Tiefstpreis und Menge je Gegenstand (LearnBrowse, Herkunft „category“),
    kein Marktwert. Keine Einzelsuchen in Schleife: SendSearchQuery und SendSellSearchQuery bleiben Listensuche und
    Unterboten-Prüfung vorbehalten (Blizzards Doku verbietet, damit das ganze Haus abzufragen).
]]
Prices.BROWSE_MORE = 20
Prices.BROWSE_CLASSES = { 0, 1, 2, 4, 5, 6, 7, 9, 11, 12, 15 }   -- Enum.ItemClass (Rückfall ohne AuctionCategories)
local browseRun

local function BrowseCategories(list)
    local out = {}
    if type(list) == "table" then
        for _, c in ipairs(list) do
            if Core.Num(c) then
                out[#out + 1] = { name = "#" .. c, filters = { { classID = Core.Num(c) } } }
            elseif type(c) == "table" and type(c.filters) == "table" and #c.filters > 0 then
                out[#out + 1] = { name = c.name, filters = c.filters }
            end
        end
        return out
    end
    local cats = rawget(_G, "AuctionCategories")
    for i, c in ipairs(type(cats) == "table" and cats or {}) do
        if type(c) == "table" and type(c.filters) == "table" and #c.filters > 0 then
            out[#out + 1] = { name = type(c.name) == "string" and c.name or ("#" .. i), filters = c.filters }
        end
    end
    if #out == 0 then
        for _, classID in ipairs(Prices.BROWSE_CLASSES) do
            out[#out + 1] = { name = "#" .. classID, filters = { { classID = classID } } }
        end
    end
    return out
end

function Prices.ScanBrowseState()
    local r = browseRun
    if not r then return nil end
    return { total = r.total, done = r.done, rows = r.rows, current = r.current, paused = r.paused or nil,
        stopped = r.stopped, skipped = r.skipped, finished = r.finished or nil }
end

local function BrowseProgress()
    Core.Fire("PRICES_BROWSE_PROGRESS", Prices.ScanBrowseState())
end

local function BrowseEnd(r, why)
    if browseRun ~= r or r.finished then return end
    r.finished, r.stopped, r.current = true, why, nil
    BrowseProgress()
end

local function BrowseStep(r)
    r.done = r.done + 1
    BrowseProgress()
    if r.done >= r.total then BrowseEnd(r, nil) end
end

function Prices.ScanBrowse(categories, reason)
    if reason ~= "click" and reason ~= "klick" then return false, "click" end
    if not isOpen then return false, "closed" end
    local AH = rawget(_G, "C_AuctionHouse")
    if type(AH) ~= "table" or type(AH.SendBrowseQuery) ~= "function" then return false, "unsupported" end
    if browseRun and not browseRun.finished then return false, "busy" end
    local list = BrowseCategories(categories)
    if #list == 0 then return false, "empty" end
    local r = { total = #list, done = 0, rows = 0 }
    browseRun = r
    for i, cat in ipairs(list) do
        local job = { key = "browse:cat:" .. i, rank = "capture", origin = "category", owner = "ezCore",
            text = Core.L.PRICES_QUEUE_BROWSE:format(cat.name or ("#" .. i)), cat = cat, more = 0 }
        job.start = function(self)
            local api = rawget(_G, "C_AuctionHouse")
            if type(api) ~= "table" or type(api.SendBrowseQuery) ~= "function" then error("SendBrowseQuery fehlt") end
            self.more = 0
            r.current, r.paused = self.cat.name, nil
            BrowseProgress()
            api.SendBrowseQuery({ searchString = "", sorts = Sorts(), itemClassFilters = self.cat.filters })
        end
        job.onResults = function(self, results, how)
            if how ~= "browse" or browseRun ~= r or r.finished then return end
            r.rows = r.rows + (type(results) == "table" and #results or 0)
            local api = rawget(_G, "C_AuctionHouse")
            local full = true
            if type(api.HasFullBrowseResults) == "function" then
                local okF, yes = pcall(api.HasFullBrowseResults)
                full = not okF or Core.Bool(yes, true) ~= false
            end
            if not full and self.more < Prices.BROWSE_MORE and type(api.RequestMoreBrowseResults) == "function" then
                self.more = self.more + 1
                Queue.Arm(self)   -- volle Frist für die nächste Seite
                Queue.Own(api.RequestMoreBrowseResults)
                return
            end
            Queue.Done(self.id)
            BrowseStep(r)
        end
        job.pause = function()
            r.paused = true
            BrowseProgress()
        end
        job.cancel = function(_, why)
            if browseRun ~= r or r.finished then return end
            if why == "timeout" or why == "error" then
                r.skipped = (r.skipped or 0) + 1   -- diese Kategorie bleibt ohne Antwort; der Durchlauf geht weiter
                BrowseStep(r)
            else
                BrowseEnd(r, why)
            end
        end
        Queue.Add(job)
    end
    return true, #list
end

function Prices.ScanBrowseStop()
    local r = browseRun
    if not r or r.finished then return 0 end
    BrowseEnd(r, "cancel")
    local n = 0
    for i = 1, r.total do n = n + Queue.Cancel("browse:cat:" .. i) end
    return n
end

Core.Listen("PRICES_BROWSE_PROGRESS", function(state)
    if type(state) == "table" and state.finished then
        local L = Core.L
        local text = state.stopped and L.PRICES_BROWSE_STOPPED:format(state.done, state.total)
            or L.PRICES_BROWSE_DONE:format(state.total, state.rows)
        local skipped = Core.Num(state.skipped) or 0
        if skipped > 0 then text = text .. " " .. L.PRICES_BROWSE_SKIPPED:format(skipped) end
        Core.Print(Core.name, text)
    end
end, "ezCore.Prices")

---------------------------------------------------------------------------
-- Marke „im Auktionshaus mehr wert“ (AH-13, Welle 13)
---------------------------------------------------------------------------
--[[
    Prices.AuctionWorth(item) → { value, vendor, price, gross, ratio, days, seen, kind } oder nil, Grund – ein
        Gegenstand ist im Auktionshaus mehr wert, wenn der Erlös nach Gebühr (Prices.Net auf dem Median der
        Tagestiefstpreise der letzten Prices.WORTH_DAYS Tage – ein alter Ausreißer zählt nicht) um Prices.WorthPercent()
        (ab Werk 20 %) über dem Händlerpreis liegt; der Preis ist höchstens WORTH_DAYS Tage alt und an mindestens
        Prices.WORTH_MIN_DAYS Tagen gesehen (Prices.Stats). Ohne gemessene Gebühr (Regel cut erst nach einer
        Verkaufsabrechnung) gilt der Brutto-Preis mit dem Hinweis „Gebühr noch unbekannt“ (gross = true; fest seit der
        Einstellungs-Prüfung vom 19.11.2026, Nr. 4 – vorher Schalter OPT_auctionWorthGross).
        Gründe ohne Marke: "item", "vendor" (kein Händlerpreis), "old", "days", "below".
    Prices.WorthMark(itemID, link, bag, slot) → true, wenn die Marke an diesem Platz stünde (Schalter des Orts, Schloss,
        gebunden)
    Münze je Ort (Welle 23d; Entscheidung des Nutzers vom 16.11.2026, Nr. 13 „den Empfehlungen folgen“): ein Schalter je
    Ort – priceOpts.worthMerchant „beim Händler“ (solange ein Händlerfenster offen ist; ab Werk an) und
    priceOpts.worthBag „in der Tasche“ (sonst; ab Werk aus – derselbe Schalter gilt an ezBags Plätzen, ezBag liest ihn;
    Einstellungs-Prüfung 19.11.2026, Nr. 50/58: bis dahin hatte ezBag einen eigenen Schalter auctionWorth, dessen „an“
    ezBag einmal übernimmt). Der alte Schalter priceOpts.worth gibt beim ersten Laden seinen Wert an den Ort „beim
    Händler“ weiter, „in der Tasche“ steht danach aus (Prices.MigrateWorthPlaces; B18, Entscheidung des Nutzers vom
    16.11.2026: Speicher, die schon beide Orte übernommen hatten, bekommen einmalig „Tasche aus“ – Merker
    ezCoreDB.migrated.worthBagOff). Danach entfällt worth (Nr. 1). Prices.WorthPlace() → "merchant" | "bag";
    Prices.WorthShownAt(ort) → Schalter an?
    Die Tooltip-Zeile erscheint, solange die Münze an mindestens einem Ort an ist.
    Prices.WorthLines(item)  → Tooltip-Zeilen (Begründung, Quelle und Alter), sonst {}
    Platzmarke ezCore.auctionWorth über Core.SlotMarks (höchstens zwei je Platz): order 70 – hinter Quest (20),
    Sammeln (30), „besser“ und Schloss (60), sie weicht als erste; solange ein Händlerfenster offen ist, order 25 (dort
    ist sie die wichtige Auskunft). Nie an gesperrten Gegenständen (ezBags Schloss, API(ezBag).IsLocked) und nie an
    gebundenen. Verkaufs-Dienst: Core.Junk.Sell({ skipAuctionWorth = true }) lässt solche Gegenstände aus (ab Werk aus;
    eingeschaltet erst von ezMerchant in Welle 14, AH-27).
]]
Prices.WORTH_DAYS = 7
Prices.WORTH_MIN_DAYS = 2
Prices.WORTH_ORDER = 70
Prices.WORTH_ORDER_MERCHANT = 25
Prices.WORTH_TEXTURE = "Interface\\MoneyFrame\\UI-GoldIcon"

Prices.WORTH_PCT_STEPS = { 10, 20, 30, 50, 75, 100, 150, 200 }
-- eingefügte Texte (Core.ImportAll, Gegenprüfung zu T6-2): Anteil und Wochen nur im Bereich der Auswahl
Core.OwnRules("priceOpts", { limits = {
    worthPct = { Prices.WORTH_PCT_STEPS[1], Prices.WORTH_PCT_STEPS[#Prices.WORTH_PCT_STEPS] },
    weeksMax = { 0, Prices.WEEKS_MAX }, monthsMax = { 0, Prices.MONTHS_MAX } } })
function Prices.WorthPercent()
    local pct = Core.Num(Core.OwnSetting("priceOpts", "worthPct")) or 20
    return math.max(0, math.min(1000, pct))
end

local worthCache, worthAt = {}, 0
function Prices.ForgetWorth() worthCache = {} end
Core.Listen("PRICES_CHANGED", function() worthCache = {} end, "ezCore.Prices")
Core.Listen("PRICES_RULES_CHANGED", function() worthCache = {} end, "ezCore.Prices")

local function Worth(item)
    local itemID = ItemID(item)
    if not itemID then return nil, "item" end
    local vendor = VendorPrice(itemID)
    if not vendor or vendor <= 0 then return nil, "vendor" end
    local info = Prices.Get(item)
    if not (info and Core.Num(info.seen)) or Now() - info.seen > Prices.WORTH_DAYS * DAY then return nil, "old" end
    local st = Prices.Stats(item, Prices.WORTH_DAYS)
    if not (st and Core.Num(st.median)) or (st.daysSeen or 0) < Prices.WORTH_MIN_DAYS then return nil, "days" end
    local price = st.median
    local net = Prices.Net(itemID, price, 2, 1)
    local value, gross = net and Core.Num(net.erloes), false
    if not value then value, gross = price, true end
    if value < vendor * (1 + Prices.WorthPercent() / 100) then return nil, "below" end
    return { value = value, vendor = vendor, price = price, gross = gross, ratio = value / vendor, days = st.daysSeen,
        seen = info.seen, kind = info.kind }
end

function Prices.AuctionWorth(item)
    if Core.IsSecret(item) or item == nil then return nil, "item" end
    local up = Core.Uptime()
    if up - worthAt > 5 then worthCache, worthAt = {}, up end
    local key = tostring(item)
    local hit = worthCache[key]
    if hit then return hit[1] or nil, hit[2] end
    local res, why = Worth(item)
    worthCache[key] = { res or false, why }
    return res, why
end

local function Bound(bag, slot)
    if not (bag and slot and C_Container and C_Container.GetContainerItemInfo) then return false end
    local info = Core.Call(C_Container.GetContainerItemInfo, bag, slot)
    return type(info) == "table" and Core.Bool(info.isBound, false) == true
end

local function LockedByBag(bag, slot)
    if not (bag and slot) then return false end
    local api = Core.API and Core.API("ezBag")
    local fn = type(api) == "table" and api.IsLocked
    if type(fn) ~= "function" then return false end
    local ok, yes = pcall(fn, bag, slot)
    return ok and yes == true
end

-- Bindungsart (14. Rückgabe von GetItemInfo: 0 keine, 1 beim Aufheben, 2 beim Anlegen, 3 beim Benutzen, 4 Quest)
local function BindType(item)
    local api = rawget(_G, "C_Item")
    local fn = type(api) == "table" and api.GetItemInfo or rawget(_G, "GetItemInfo")
    if type(fn) ~= "function" or item == nil then return nil end
    local ok, _, _, _, _, _, _, _, _, _, _, _, _, _, bind = pcall(fn, item)
    return ok and Core.Num(bind) or nil
end

local merchantOpen = false

-- Münze je Ort (Welle 23d, Nr. 13). Beim ersten Laden mit den neuen Schaltern übernimmt der Ort „beim Händler“ den Wert
-- des alten Schalters worth, „in der Tasche“ steht aus (ab Werk), worth steht danach wieder auf an (er ist nur noch
-- Weiterleitung). B18 (Entscheidung des Nutzers vom 16.11.2026, Fragerunde „ja alles außer …“; Nr. 13: Händler an,
-- Tasche aus): Bis Welle 27 gab der alte Schalter seinen Wert an beide Orte weiter. Solche Speicher bekommen einmalig
-- „in der Tasche“ aus – auch eine bewusste Wahl „Tasche an“ seit Welle 23d (Kästchen OPT_auctionWorthBag), denn die
-- lässt sich vom übernommenen Wert nicht unterscheiden (Review vor dem Merge, 16.11.2026); der Merker db.migrated.worthBagOff hält fest,
-- dass die Umstellung lief, danach bleibt jede eigene Wahl stehen. Der Merker wird auch für neue Speicher gesetzt.
-- db = ezCoreDB (roh, vor den Standardwerten gelesen: Core.OwnSettings füllt fehlende Schlüssel auf).
-- Umkehrbar: das Kästchen „in der Tasche“ (OPT_auctionWorthBag) wieder einschalten.
-- Einstellungs-Prüfung 19.11.2026: danach entfallen die Schlüssel worth (Nr. 1: ohne Zeile, stand ein „aus“ aus einer
-- alten Sicherung darin, verschwand die Münze überall), worthGross (Nr. 4: fest an) und weeks (Nr. 51: ein gespeichertes
-- „aus“ wird zu „0 Wochen“ in der Auswahl weeksMax – dasselbe Ergebnis wie vorher). Läuft bei jedem Laden; ohne diese
-- Schlüssel tut sie nichts.
-- → true, wenn ein Wert geändert wurde
function Prices.MigrateWorthPlaces(db)
    if type(db) ~= "table" then return false end
    local migrated = type(db.migrated) == "table" and db.migrated or {}
    local t, changed = db.priceOpts, false
    if type(t) == "table" then
        if type(t.worth) == "boolean" and t.worthMerchant == nil and t.worthBag == nil then
            t.worthMerchant, t.worthBag = t.worth, false
            changed = true
        elseif not migrated.worthBagOff and t.worthBag == true then
            t.worthBag = false
            changed = true
        end
        if t.weeks == false then t.weeksMax, changed = 0, true end
        for _, gone in ipairs({ "worth", "worthGross", "weeks" }) do
            if t[gone] ~= nil then t[gone], changed = nil, true end
        end
    end
    migrated.worthBagOff = true
    db.migrated = migrated
    return changed
end
Core.Listen("CORE_LOADED", function() Prices.MigrateWorthPlaces(Core.db) end, "ezCore.Prices")

Prices.WORTH_PLACE_KEY = { merchant = "worthMerchant", bag = "worthBag" }
function Prices.WorthPlace() return merchantOpen and "merchant" or "bag" end
-- Ein Schalter je Ort, auch an ezBags Plätzen (Nr. 50/58): ezBag fragt die Marke nur, wenn worthBag an ist (bzw. beim
-- Händler mit ezMerchant, ezBag/Marks.lua AuctionWorthShown) – mit ezBag ist „in der Tasche“ darum hier durchgelassen.
function Prices.WorthShownAt(place)
    place = place or Prices.WorthPlace()
    local SM = Core.SlotMarks
    if place == "bag" and SM and SM.ViaEzBag and SM.ViaEzBag() then return true end
    local key = Prices.WORTH_PLACE_KEY[place]
    return key ~= nil and Core.OwnSetting("priceOpts", key) == true
end
-- Tooltip-Zeile: nur, solange die Münze an einem Ort wirklich erscheinen kann (Gegenprüfung 23d: nicht das pauschale
-- „ezBag entscheidet“ aus WorthShownAt, sondern der Schalter des Orts).
local function WorthAnywhere()
    return Core.OwnSetting("priceOpts", "worthMerchant") == true or Core.OwnSetting("priceOpts", "worthBag") == true
end

-- Ohne Taschenplatz (ezBag offline, Gildenbank: nur Anzeige) ist nicht prüfbar, ob dieses Exemplar gebunden ist
-- (Gegenprüfung Welle 13). Dann nur Gegenstände, die nie binden (Bindungsart 0 bzw. ohne Angabe).
function Prices.WorthMark(itemID, link, bag, slot)
    if not Prices.WorthShownAt() then return false end
    if bag == nil or slot == nil then
        local bind = BindType(link or itemID)
        if bind and bind ~= 0 then return false end
    elseif LockedByBag(bag, slot) or Bound(bag, slot) then
        return false
    end
    return Prices.AuctionWorth(link or itemID) ~= nil
end

local function WorthMarkFn(itemID, link, bag, slot)
    if not Prices.WorthMark(itemID, link, bag, slot) then return nil end
    return { texture = Prices.WORTH_TEXTURE }
end

function Prices.AddWorthMark()
    local S = Core.SlotMarks
    if not (S and S.Add) then return false end
    return S.Add("ezCore.auctionWorth", { order = merchantOpen and Prices.WORTH_ORDER_MERCHANT or Prices.WORTH_ORDER,
        owner = "ezCore", fn = WorthMarkFn })
end
Prices.AddWorthMark()
ns.On("MERCHANT_SHOW", function() merchantOpen = true Prices.AddWorthMark() end)
ns.On("MERCHANT_CLOSED", function() merchantOpen = false Prices.AddWorthMark() end)

function Prices.WorthLines(item)
    local w = WorthAnywhere() and Prices.AuctionWorth(item)
    if not w then return {} end
    local L = Core.L
    local lines = { L.WORTH_LINE:format(Core.CoinText(w.value), Core.CoinText(w.vendor),
        math.floor((w.ratio - 1) * 100 + 0.5)) }
    lines[#lines + 1] = L.WORTH_SOURCE:format(Core.Plural(w.days, L.PRICES_DAYS_ONE, L.PRICES_DAYS_MANY),
        L.AGO:format(Core.Duration and Core.Duration(math.max(0, Now() - w.seen)) or "?"))
    if w.gross then lines[#lines + 1] = L.WORTH_FEE_UNKNOWN end
    return lines
end

-- Zeigt der Tooltip ein gebundenes Exemplar? Gelesen aus den Zeilen der Tooltip-Daten (data.lines[i].leftText) gegen
-- Blizzards Texte „Seelengebunden“, „Accountgebunden“, „Questgegenstand“ … (Gegenprüfung Welle 13: die Zeile
-- „Im Auktionshaus mehr wert“ erschien auch an gebundenen Exemplaren). → true, wenn gebunden
Prices.BOUND_TEXTS = { "ITEM_SOULBOUND", "ITEM_ACCOUNTBOUND", "ITEM_BNETACCOUNTBOUND", "ITEM_BIND_TO_ACCOUNT",
    "ITEM_BIND_TO_BNETACCOUNT", "ITEM_BIND_QUEST", "ITEM_BIND_ON_PICKUP" }
function Prices.TooltipBound(data)
    local lines = type(data) == "table" and not Core.IsSecret(data) and data.lines
    if type(lines) ~= "table" then return false end
    local bound = {}
    for _, name in ipairs(Prices.BOUND_TEXTS) do
        local text = rawget(_G, name)
        if type(text) == "string" and text ~= "" then bound[text] = true end
    end
    for _, line in ipairs(lines) do
        local text = type(line) == "table" and line.leftText
        if type(text) == "string" and not Core.IsSecret(text) and bound[text] then return true end
    end
    return false
end

-- Abstand (Spielbefund 18.11.2026 „auch hier fehlender abstand“, S-1811-Tooltipabstand): eine Leerzeile davor über
-- ezCores Trenner, Gruppe Prices.TOOLTIP_GROUP – direkt unter ezAuctions Preiszeile (Platz price) keine, beide gehören
-- zum Auktionshaus.
Prices.TOOLTIP_GROUP = "price"
if Core.Tooltip and Core.Tooltip.AddItemSection then
    Core.Tooltip.AddItemSection("ezCore.auctionWorth", 41, function(tooltip, itemID, data)
        if Prices.TooltipBound(data) then return end
        local lines = Prices.WorthLines(itemID)
        if #lines > 0 and Core.Tooltip.Gap then Core.Tooltip.Gap(tooltip, Prices.TOOLTIP_GROUP) end
        for i, line in ipairs(lines) do
            if i == 1 then Core.TipLine(tooltip, line, "normal") else Core.TipLine(tooltip, line, "hint", true) end
        end
    end, "ezCore")
end

-- Einstellungen unter „ezCollection“ (Collection.lua): Abschnitt „Auktionshaus“
function Prices.AddSettings(page)
    if type(page) ~= "table" or type(page.OwnCheckbox) ~= "function" then return false end
    local L = Core.L
    page:Header(L.PRICES_SETTINGS_HEADER, L.PRICES_SETTINGS_HEADER_TIP)
    local function Changed()
        worthCache = {}
        if Core.SlotMarks then Core.SlotMarks.Refresh() end
    end
    -- Münze je Ort (Welle 23d, Nr. 13): beim Händler (ab Werk an), in der Tasche (ab Werk aus)
    page:OwnCheckbox("priceOpts", "worthMerchant", { text = "auctionWorthMerchant", onChange = Changed,
        tip = L.OPT_auctionWorthMerchant_TIP:format(Prices.WorthPercent(), Prices.WORTH_DAYS, Prices.WORTH_MIN_DAYS) })
    page:OwnCheckbox("priceOpts", "worthBag", { text = "auctionWorthBag", onChange = Changed })
    -- Schwelle der Marke (AH-13: „ab Werk 20 %, einstellbar“; Leitlinie 3: sichtbare Auswahl). Auswahlfeld auf
    -- ezCoreDB.priceOpts (Proxy wie ProxyDropdown), Stufen in Prices.WORTH_PCT_STEPS.
    if type(page.ProxyDropdown) == "function" then
        page:ProxyDropdown("auctionWorthPct", function()
            local list = {}
            for _, v in ipairs(Prices.WORTH_PCT_STEPS) do list[#list + 1] = { v, L.WORTH_PCT_VALUE:format(v) } end
            return list
        end, function() return Prices.WorthPercent() end, function(v)
            local t, n = Core.OwnSettings("priceOpts"), Core.Num(v)
            if t and n then t.worthPct = n Changed() end
        end, { default = 20, varType = Settings and Settings.VarType and Settings.VarType.Number })
    end
    -- „0“ heißt keine Wochenpunkte (Nr. 51: vorher zusätzlich ein Kästchen „ältere Wochen behalten“ für dasselbe)
    if type(page.ProxyDropdown) == "function" then
        page:ProxyDropdown("priceWeeksMax", function()
            local list = {}
            for _, v in ipairs(Prices.WEEKS_STEPS) do
                if v <= Prices.WEEKS_MAX then list[#list + 1] = { v, tostring(v) } end
            end
            return list
        end, function() return Prices.WeeksMaxSetting() end, function(v)
            local t, n = Core.OwnSettings("priceOpts"), Core.Num(v)
            if t and n then t.weeksMax = math.max(0, math.min(Prices.WEEKS_MAX, n)) end
        end, { default = Prices.WEEKS_MAX, varType = Settings and Settings.VarType and Settings.VarType.Number,
            tooltip = L.OPT_priceWeeksMax_TIP:format(Prices.WATCH_DAYS or 30, Prices.WEEKS_MAX) })
        -- Monatspunkte (21.11.2026): „0“ heißt keine – ältere Wochen fallen dann wie bisher weg
        page:ProxyDropdown("priceMonthsMax", function()
            local list = {}
            for _, v in ipairs(Prices.MONTHS_STEPS) do
                if v <= Prices.MONTHS_MAX then list[#list + 1] = { v, tostring(v) } end
            end
            return list
        end, function() return Prices.MonthsMax() end, function(v)
            local t, n = Core.OwnSettings("priceOpts"), Core.Num(v)
            if t and n then t.monthsMax = math.max(0, math.min(Prices.MONTHS_MAX, n)) end
        end, { default = Prices.MONTHS_MAX, varType = Settings and Settings.VarType and Settings.VarType.Number,
            tooltip = L.OPT_priceMonthsMax_TIP:format(Prices.MONTHS_MAX) })
    end
    if type(page.Button) == "function" then
        page:Button(L.PRICES_BROWSE_LABEL, L.PRICES_BROWSE_BUTTON, function()
            local ok, why = Prices.ScanBrowse(nil, "click")
            if not ok then Core.Print(Core.name, L["PRICES_BROWSE_NO_" .. tostring(why)] or L.PRICES_BROWSE_NO_closed) end
        end, L.PRICES_BROWSE_TIP)
        page:Button(L.PRICES_BROWSE_STOP_LABEL, L.PRICES_BROWSE_STOP_BUTTON, function() Prices.ScanBrowseStop() end,
            L.PRICES_BROWSE_STOP_TIP)
    end
    return true
end

---------------------------------------------------------------------------
-- Messung in /ez debug (AH-01) und Nachrichten
---------------------------------------------------------------------------

function Prices.ScanDebugLine()
    local st = Prices.ScanStats()
    if not st then return nil end
    local L = Core.L
    return L.PRICES_SCAN_DEBUG:format(st.rows, st.avg, st.slices, st.max, L["PRICES_LINKS_" .. st.linkMode] or st.linkMode,
        st.variants, st.retried, st.skipped)
end

-- Der Bericht von /ez debug (Diagnose.lua) bekommt die Zeile „Scan: …“ – als Hülle um Debug.Lines, weil der
-- Mitschnitt nur Zuhörer misst und das Lesen des Scans in C_Timer-Scheiben läuft.
ns.On("PLAYER_LOGIN", function()
    local D = Core.Debug
    if type(D) ~= "table" or type(D.Lines) ~= "function" or D.pricesScanLine then return end
    local lines = D.Lines
    D.pricesScanLine = true
    D.Lines = function(...)
        local out = lines(...)
        local line = Prices.ScanDebugLine()
        if line and type(out) == "table" then table.insert(out, math.min(2, #out + 1), line) end
        return out
    end
end)

Core.RegisterMessage("PRICES_QUEUE_CHANGED", "Prices.lua", "Die Abfrage-Warteschlange des Auktionshauses hat einen neuen Besitzer (Auftrag gestartet, fertig, abgebrochen).", "owner | nil")
Core.RegisterMessage("PRICES_QUEUE_USER", "Prices.lua", "Der Spieler sucht selbst im Auktionshaus: eine Erfassung ist angehalten (paused), eine Modul-Suche abgebrochen (cancelled).", "{ how, paused, cancelled }")
Core.RegisterMessage("PRICES_BROWSE_PROGRESS", "Prices.lua", "Stand des Durchlaufs je Kategorie (AH-02): nach jeder Kategorie, bei Pause und am Ende (finished).", "{ total, done, rows, current, paused, stopped, finished }")
Core.RegisterMessage("PRICES_RULES_CHANGED", "Prices.lua", "Eine Regel des Hauses wurde neu gemessen (copper, split, cooldown, cut, deposit).", "regel")
