local ADDON, ns = ...
local L = ns.L

--[[
    ezAuction erweitert Blizzards eigenes Auktionshaus (Blizzard_AuctionHouseUI, Reiter Kaufen, Verkaufen,
    Auktionen) – ohne zusätzliche Reiter und ohne eigene Auktionshaus-Oberfläche (Wunsch des Nutzers, 13.11.2026).
      Kaufen     BuyTab.lua, Editor.lua, Search.lua, Lists.lua: Einkaufslisten in Blizzards Kategorienliste
      Verkaufen  SellTab.lua: Taschenliste neben dem Verkaufsbereich, Preisregel und „zuletzt“ am Preisfeld
      Auktionen  AuctionsTab.lua: „unterboten“, „Unterbotene abbrechen“, Summe der laufenden Auktionen
      Markt      Market.lua (Rechnung: Bewertung gegen den Median, Verfügbarkeit, Graph-Punkte, Beobachtung),
                 MarketPanel.lua (Seitenteil „Markt“ mit Pfeil-Knopf), Upgrade.lua (Pfeil „besser“ aus ezGear)
      Daneben    Beside.lua: was neben einem fremden Auktionshaus-Addon (Auctionator) bleibt und was weicht;
                 in dessen Reitern stehen ezAuctions Teile nicht (ns.ForeignView, AH_MODE "other")
      Rundgang   Tour.lua: Erklärblasen beim ersten Öffnen (Core.NewTour)
    Taint-sicher: nur hooksecurefunc/HookScript, keine Werte in Blizzards Tabellen; Einstellen, Kaufen und
    Abbrechen bleiben ein Klick des Spielers (Blizzard verlangt dafür einen Tastendruck).
    Preise aus dem Gedächtnis (Marktwert, Tooltip, Komplett-Scan) kommen aus ezCore.Prices, der Verlauf aus
    ezCore.History; Helfer wie Core.Call, Core.VendorPrice, ns.Enabled und ns.Throttle liefert ezCore (NewModule).
]]

-- Schalter der Einstellungsseite (Esc → Optionen → AddOns → ezCollection → ezAuction). Reine Auskünfte sind seit der
-- Einstellungs-Prüfung vom 19.11.2026 immer an und haben keinen Schalter mehr (Nr. 11 bis 18 und Abschnitt 4): Filter
-- und Höchstpreis der Einkaufslisten, Bestand beim Kaufen, Stückpreis und Verkäufer, Mittel im Kaufdialog, Verlauf in
-- Wochen, Netto-Zeile, Abstand der Unterbietung, Stapelpreis mit Umschalt, Hinweiszeile bei einer Erfassung. Gespeicherte
-- Werte listFilters, buyStock, unitPrice, buyDialogLine, marketWeeks, netLine, undercutDetail, tooltipStack und
-- captureBar bleiben unbeachtet liegen.
ns.DEFAULTS = {
    -- Kaufen
    shoppingLists = true,       -- Einkaufslisten oben in Blizzards Kategorienliste
    vendorMark = true,          -- „< Händler“ in der Ergebnisliste, wenn der Tiefstpreis unter dem Händlerpreis liegt
    marketCompare = true,       -- „−23 %“ gegenüber dem Marktwert in der Ergebnisliste (Preis-Wissen von ezCore)
    bargainPercent = 20,        -- ab so viel Prozent unter Marktwert (ab fünf Tagen: unter dem Median) ein Schnäppchen
    upgradeArrow = true,        -- Pfeil „besser“ aus ezGear an Blizzards Ergebniszeilen (Upgrade.lua; nur mit ezGear)
    upgradeOnly = false,        -- Filter „Nur Verbesserungen“: übrige Ergebniszeilen abblenden (nur Anzeige)
    -- Welle 12 (AH-08 bis AH-12; bis Welle 13 in Options.lua ergänzt)
    recentSearches = true,      -- Pfeil-Knopf rechts neben dem Suchfeld mit den letzten 20 Suchen (Search.lua)
    rowSearch = true,           -- Knopf „Suchen“ an jeder Zeile im Editor einer Liste
    listCost = true,            -- Kostenvoranschlag „heute ≈ …, im Mittel ≈ …“ unter der Liste und in ihrem Tooltip
    -- Welle 13 (AH-37): Erfassungen in Blizzards Ergebnisliste
    restoreView = true,         -- nach einer Erfassung die vorige Ansicht (Suche, Favoriten, Liste) wiederholen
    -- Welle 14 (AH-22 bis AH-24): Schnäppchen, Beobachtet, Kauf-Komfort – jede Stelle am Kaufbereich einzeln abschaltbar
    bargainList = true,         -- Eintrag „Schnäppchen (n)“ über Blizzards Kategorienliste (AH-22)
    watchList = true,           -- Eintrag „Beobachtet (n)“: Spiegel der Favoriten mit Zielpreis (AH-23)
    watchAlert = true,          -- Meldung „3 Beobachtete unter Zielpreis“ im Chat (nur bei offenem Auktionshaus)
    buyNeed = true,             -- „Bedarf: n“ neben Blizzards Mengenfeld im Warenkauf (AH-24)
    buySetQuantity = false,     -- Klick auf „Bedarf: n“ trägt n in Blizzards Mengenfeld ein (Tor T1, ab Werk aus)
    buyNextMark = true,         -- günstigste Zeile je Stück in Blizzards Einzelstück-Liste markieren
    buyNextSelect = false,      -- nach einem Kauf die nächstgünstige Zeile vorwählen (Tor T1, ab Werk aus)

    -- Markt (Market.lua, MarketPanel.lua; Fragen 36 und 39 der Vollprüfung – Empfehlung umgesetzt, Antwort offen)
    marketPanel = true,         -- Seitenteil „Markt“ mit Pfeil-Knopf am Auktionsfenster: Verlauf, Verfügbarkeit, Hinweis
    marketHint = true,          -- Kauf- und Verkaufshinweis gegen den Median der Tages-Tiefstpreise (ab fünf Tagen)
    salvageCompare = true,      -- „Entzaubern ≈ …“ in Taschenliste und Seitenteil, wenn es mehr bringt (AUC-19, Empfehlung umgesetzt)

    -- Rücksicht (AH-31, Welle 15)
    besideNotice = true,        -- einmalige Erklärblase am Zahnrad, solange ein fremdes Auktions-Addon übernimmt

    -- Preise (ezCore.Prices)
    tooltipPrice = true,        -- Tooltip-Zeile „Auktion: …“ (weicht neben Auctionator oder TSM: Scan.HoldBack)
    tooltipBeside = false,      -- die Tooltip-Zeile auch neben anderen Auktions-Addons zeigen
    tooltipStackHint = true,    -- graue Hinweiszeile „Umschalt: Stapelpreis“
    scanCoverage = true,        -- „Heute: 82 %“ unter „Preise erfassen“, rechts neben Pfeil und Zahnrad (Anteil der Taschen-Gegenstände mit Preis von heute, AH-16)
    scanOnOpen = false,         -- beim Öffnen des Auktionshauses erfassen (AH-17, ab Werk aus)
    scanOnOpenHours = 6,        -- … frühestens so viele Stunden nach der letzten Erfassung beim Öffnen

    -- Verkaufen
    sellList = true,            -- Taschenliste neben Blizzards Verkaufsbereich
    sellListSide = "auto",      -- auto | left | right
    priceRule = "undercut",     -- blizzard | undercut | percent
    undercutPercent = 5,        -- für priceRule = "percent" (1 bis ns.UNDERCUT_PERCENT_MAX)
    neverBelowVendor = true,    -- nach Abzug der Gebühr nie unter dem Händlerpreis
    floorTrend = false,         -- nie unter dem Tief der erfassten Tage (AUC-13, Frage 2: entschieden 13.11.2026, ab Werk aus)
    rememberPost = true,        -- letzten Preis, Dauer und Menge je Gegenstand merken und vorbelegen
    -- Welle 13 (AH-18 bis AH-20, AH-38; Tor T1 für den Verkaufsbereich ohne Ergebnis: ns.T1)
    suggestOnly = false,        -- Preisregel und „Zuletzt“ nur vorschlagen („Vorschlag: …“), nichts eintragen
    priceWarn = true,           -- Warnzeile am Preisfeld: weit unter dem Median (Market.Judge) oder Händler zahlt mehr
    nextItem = true,            -- „Als Nächstes: …“ und die nächste Zeile der Taschenliste hervorheben
    postNext = false,           -- nach dem Einstellen den nächsten einlegen (wirkt erst mit Tor T1 „geht“)
    postDefaults = true,        -- Standard-Menge und -Dauer je Gegenstand oder Kategorie (Menü an „Zuletzt“)
    bidPercent = 0,             -- Startgebot = so viel Prozent des Sofortkaufs (nur Einzelstücke; 0 = aus)
    -- Welle 15 (AH-28 bis AH-30): Auktionspost, Verkaufsempfehlung, Taschenliste ordnen – nur Anzeige
    auctionMail = true,         -- Rückläufer oben mit „zurück“, Zeile „Post: 2 Verkäufe, 3 Rückläufer“ im Seitenteil
    sellAdvice = true,          -- Verkaufsempfehlung: „4 von 6 verkauft“, üblicher Preis, Anzahlung gegen Gewinn
    sellHideLocked = true,      -- Gegenstände mit ezBags Schloss „nie verkaufen“ ausblenden (nur mit ezBag)
    sellPins = true,            -- Stern „oben halten“ je Zeile der Taschenliste
    sellOtherChars = false,     -- Abschnitt „Bei anderen Charakteren verkaufbar“ unter der Taschenliste

    -- Auktionen
    undercutCheck = true,       -- eigene Auktionen auf „unterboten“ prüfen
    cancelButton = true,        -- Knopf „Unterbotene abbrechen“
    auctionSum = true,          -- Summe der laufenden Auktionen
    historyTab = true,          -- Unter-Reiter „Verlauf“ (ezCore.History)
    rivalsButton = true,        -- Knopf „Konkurrenz ansehen“ neben „Unterbotene abbrechen“ (AH-25)
}

-- „Prozent unter Tiefstpreis“: höchstens so viel (Einstellungs-Prüfung vom 19.11.2026, Abschnitt 4: bis 50 % war
-- fragwürdig). Ein gespeicherter höherer Wert wird einmal auf diese Grenze gesetzt (ns.MigrateSettings1911).
ns.UNDERCUT_PERCENT_MAX = 25

local Core = ezCore

-- Einmal je Speicher (Core.MigrateOnce, Merker settings1911): „Prozent unter Tiefstpreis“ in den neuen Bereich holen.
function ns.MigrateSettings1911(db)
    if type(db) ~= "table" or type(db.settings) ~= "table" then return nil end
    return Core.MigrateOnce(db, "settings1911", function()
        local value = tonumber(db.settings.undercutPercent)
        if value and value > ns.UNDERCUT_PERCENT_MAX then db.settings.undercutPercent = ns.UNDERCUT_PERCENT_MAX end
        return true
    end)
end
-- Print, Error, Try, On, Listen/Fire (modul-intern), OnReady, OnSettingChanged, SetSetting, Enabled, Throttle,
-- WhenAddOnLoaded … Dazu das Gerüst von ezCore (Core.ModuleScaffold, docs/ezcore.md „Gerüst-Dienste“):
--   db/tables  ezAuctionDB anlegen (auch nach einer beschädigten Datei), Einstellungen auffüllen, ns.db und ns.S
--              lists   Einkaufslisten, für alle Charaktere gleich
--              realms  [Schlüssel] = { posts = { [itemID] = {…} } } – eigene letzte Preise je Auktionshaus
--              ui      aufgeklappt, Taschenliste versteckt, Auswahl im Verlauf …
--              hints   gesehene Erklärblasen (Tour.lua)
--              watch   Spiegel der Favoriten mit Zielpreis, für das Konto (Lists.lua, ns.Watch; AH-23)
--   login      ns.charKey, ns.realm, ns.me setzen und ns.RunReady()
--   slash      /ezauction, dazu /eza aus Core.SLASH_ALIASES, solange kein anderes Addon ihn belegt (T18-2): „optionen“,
--              „status“, „hilfe“ kennt das Gerüst, die eigenen Wörter stehen in extra
--   core       ist ezCore älter, bleibt das Modul still und sagt es einmal im Chat und in /ez status
--   needs      was ezAuction ohne eigenen Ersatz von ezCore nimmt: Zeiträume und Texte des Verlaufs, das Addon-Fach
Core.NewModule(ADDON, ns, {
    title = "ezAuction",
    -- Core.NewGraph, Core.NewSidePanel, Prices.Stats und Prices.SourceText kamen nach ezCore 1.12.0 (Wellen 7 bis 13
    -- ohne neue Nummer); 1.13.0 ist die erste Nummer, die sie alle enthält. 1.14.0: Core.CopyAsText, ParseMoney,
    -- GoldDecimal und AuctionHouseOpen kamen in den Wellen 23 bis 29 ohne eigene Nummer.
    -- 1.15.0: Bausteine aus dem Gesamtreview vom 18.11.2026, u. a. Core.SlashCmd, Core.HelpLines, Core.TipTitle, Core.Tooltip.Gap
    -- (Liste je Modul in docs/roadmap/uebergreifend.md, P7)
    core = "1.15.0",
    needs = { "History.PERIODS", "History.PeriodLabel", "History.TypeLabel", "CompartmentHandlers", "Style.ColorText",
        -- Gesamtreview 18.11.2026, P19c (ohne neue Versionsnummer): Qualitätsname aus ezCore (T16-6)
        "QualityName",
        "Style.BUTTON", "Style.ICON",
        -- Welle 17: Helfer und Texte, die ezCore ohne neue Versionsnummer bekam (tools/texte.lua, Regel 4)
        "More", "L.ALL_CHARS",
        -- Welle 23 (Zweige kern/reste-23a und -23b, ohne neue Nummer): gemeinsame Helfer statt eigener Kopien
        "Median", "Hours", "ParseMoney", "MaxStack", "AuctionHouseOpen", "Prices.Weekday", "Prices.BagItems",
        "TOUR_FEATURES.single",
        -- Welle 26 (ezCore-Paket kern/ezcore-reste-24, ohne neue Nummer): Geld-Spalte „money“ (Core.GoldDecimal)
        "GoldDecimal",
        -- Gesamtreview 18.11.2026 (Paket kern/charakter-realm, ohne neue Nummer): Haus eines Twinks, erreichbarer
        -- Bestand, Einstell-Verlauf je Haus (T4-NR5, T4-NR6)
        "SameHouse", "Inventory.Reachable", "History.FEATURES.postStatsHouse",
        -- Gesamtreview 18.11.2026 (P13 D1, ohne neue Nummer): Bausteine der Oberflächen-Einheit
        "compartmentMain", "SlashCmd", "TipTitle", "TipLine", "TipDoubleLine", "SettingsPathText", "Menu.Settings",
        "Menu.Dropdown", "Toolbar.GearButton", "Toolbar.ArrowButton", "Toolbar.ShowTipWhileDisabled",
        -- Gesamtreview 18.11.2026 (D3, kern/einheit-rest; ohne neue Nummer): Texthelfer statt Kopien im Modul
        "CmdText", "Word",
    -- Gesamtreview 18.11.2026 (P19a, kern/ssot-helfer; ohne neue Nummer): gemeinsame Helfer statt Kopien
    "PlaySound", "ICON_FALLBACK",
    -- Einstellungs-Prüfung vom 19.11.2026: Einmal-Umstellung (Prozent unter Tiefstpreis)
    "MigrateOnce" },
    db = "ezAuctionDB",
    tables = { "lists", "realms", "ui", "hints", "watch" },
    -- ui.lastList schrieb ezAuction bis Welle 4, gelesen hat es nie jemand (AUC-11, Entscheidung C vom 13.11.2026):
    -- der gespeicherte Rest fällt beim Laden still weg.
    -- Seit der Einstellungs-Prüfung vom 19.11.2026 dazu die Einmal-Umstellung ns.MigrateSettings1911.
    onLoad = function(db)
        db.ui.lastList = nil
        ns.MigrateSettings1911(db)
    end,
    login = true,
    slash = {
        -- /eza kommt aus Core.SLASH_ALIASES (Belegt-Prüfung, T18-2); ohne Wort öffnet der Befehl die Einstellungen wie
        -- jeder Klick im Addon-Fach – ezAuction hat außerhalb des Auktionshauses kein Fenster (Entscheidung 5)
        extra = function(cmd)
            if cmd == "listen" or cmd == "lists" then
                ns.Lists.PrintAll()
                return true
            elseif cmd == "verlauf" or cmd == "history" then
                ns.History.PrintSummary()
                return true
            end
            return false
        end,
    },
})

-- ns.CmdText(text) (%s durch den geltenden Befehl: „/eza“, solange kein anderes Addon ihn belegt, sonst „/ezauction“;
-- T18-2) legt Core.NewModule an (Core.CmdText); Standardwörter auf Knöpfen (CLOSE, CANCEL, DELETE; T18-22) kommen über
-- Core.Word aus Blizzards Client.

-- Was ezAuction anderen Modulen anbietet (ezCore.API("ezAuction")); Lists.lua füllt die Einkaufslisten-Funktionen.
ns.API = {}

ns.BLIZZARD_ADDON = "Blizzard_AuctionHouseUI"
ns.AH_CUT = 0.05            -- Anteil, den das Auktionshaus vom Verkaufspreis einbehält

---------------------------------------------------------------------------
-- Datenbank (angelegt vom Gerüst, siehe oben)
---------------------------------------------------------------------------

-- Orange für Warnungen und Marken (Design-System 2.5, Welle 22): Blizzards ORANGE_FONT_COLOR, ohne das Objekt ezCores
-- Rolle „warn“. Ersetzt die eigenen Töne ff9933 (Marke „zurück“) und ff8020 („Achtung:“ vor Doppelkauf). Gehört nach
-- ezCore, sobald Core.Style.COLOR eine Rolle „orange“ führt (Wunsch in docs/roadmap/ezAuction.md).
function ns.Orange(text)
    if Core.IsSecret(text) then return text end
    local orange = rawget(_G, "ORANGE_FONT_COLOR")
    if type(orange) == "table" and type(orange.WrapTextInColorCode) == "function" then
        local ok, wrapped = pcall(orange.WrapTextInColorCode, orange, tostring(text))
        if ok and type(wrapped) == "string" then return wrapped end
    end
    return Core.Style.ColorText("warn", text)
end

-- Schlüssel der eigenen Verkäufe: derselbe wie im Preis-Wissen von ezCore („Realm-Fraktion“, Core.Prices.Key),
-- damit „zuletzt“ und Marktwert zum selben Auktionshaus gehören.
function ns.PostKey()
    return Core.Prices.Key()
end

-- Schlüssel bis ezAuction 1.0 (nur der Realm); RealmData übernimmt dessen Einträge einmal je Fraktion.
local function LegacyKey()
    return Core.RealmKey(ns.realm or Core.realm or "?")
end

-- Eigene Verkäufe je Auktionshaus (ns.PostKey): letzter Preis, Dauer und Menge je Gegenstand.
-- Einträge unter dem alten Realm-Schlüssel werden beim ersten Besuch je Fraktion übernommen.
function ns.RealmData()
    local realms = ns.db.realms
    local key = ns.PostKey()
    local data = realms[key]
    if type(data) ~= "table" then
        data = {}
        realms[key] = data
        local old = realms[LegacyKey()]
        if old ~= data and type(old) == "table" and type(old.posts) == "table" then
            -- RememberPost ersetzt Einträge nur, darum genügt eine flache Kopie.
            data.posts = {}
            for itemID, post in pairs(old.posts) do data.posts[itemID] = post end
        end
    end
    data.posts = type(data.posts) == "table" and data.posts or {}
    return data
end

function ns.LastPost(itemID)
    if not (ns.db and itemID) then return nil end
    return ns.RealmData().posts[itemID]
end

-- price je Stück (Waren) bzw. je Auktion (Einzelstücke), duration 1–3 wie Blizzards Auswahl.
-- AUC-20: die vorigen Einstellpreise bleiben im Feld earlier (jüngster zuerst), zusammen höchstens ns.POST_PRICES –
-- der Tooltip von „Zuletzt“ nennt sie. Derselbe Preis wie zuletzt schiebt nichts nach (wer zehnmal zum selben
-- Preis einstellt, behält trotzdem die Preise davor). Einträge von früher ohne earlier gelten als „nur der letzte“.
ns.POST_PRICES = 3
function ns.RememberPost(itemID, price, duration, quantity)
    if not (ns.db and itemID and price and price > 0) then return end
    local posts = ns.RealmData().posts
    local old = posts[itemID]
    local earlier = {}
    if type(old) == "table" then
        local before = type(old.earlier) == "table" and old.earlier or {}
        if old.price ~= price and Core.Num(old.price) then
            earlier[1] = { price = old.price, duration = old.duration, qty = old.qty, time = old.time }
        end
        for _, post in ipairs(before) do
            if #earlier >= ns.POST_PRICES - 1 then break end
            if type(post) == "table" and Core.Num(post.price) then earlier[#earlier + 1] = post end
        end
    end
    posts[itemID] = { price = price, duration = duration, qty = quantity, time = time(), earlier = earlier[1] and earlier or nil }
end

-- Die letzten Einstellpreise eines Gegenstands, jüngster zuerst: { { price, duration, qty, time } … } (höchstens
-- ns.POST_PRICES); leer ohne gemerkten Preis.
function ns.PostPrices(itemID)
    local last = ns.LastPost(itemID)
    if type(last) ~= "table" then return {} end
    local out = { last }
    for _, post in ipairs(type(last.earlier) == "table" and last.earlier or {}) do
        if #out >= ns.POST_PRICES then break end
        if type(post) == "table" and Core.Num(post.price) then out[#out + 1] = post end
    end
    return out
end

-- Einen gemerkten Stand zurücksetzen (post = der vorige Eintrag oder nil = keiner), z. B. nach einem
-- abgelehnten Einstellen (SellTab.lua, Sell.PostFailed).
function ns.RestorePost(itemID, post)
    if not (ns.db and itemID) then return end
    ns.RealmData().posts[itemID] = type(post) == "table" and post or nil
end

function ns.ForgetPosts()
    for _, data in pairs(ns.db.realms) do
        if type(data) == "table" then data.posts = {} end
    end
end

---------------------------------------------------------------------------
-- Preise: Schritte, Händlerpreis, Preisregel (ohne Spielaufrufe prüfbar)
---------------------------------------------------------------------------

-- Kleinster Preisschritt: 1 Kupfer, wenn das Auktionshaus Kupfer annimmt, sonst 1 Silber.
function ns.Step()
    local api = C_AuctionHouse
    local copper = api and Core.Call(api.SupportsCopperValues)
    return copper and 1 or 100
end

function ns.RoundDown(price, step) return math.floor(price / step) * step end
function ns.RoundUp(price, step) return math.ceil(price / step) * step end

-- Mindestpreis, damit nach Abzug der Gebühr nicht weniger bleibt als beim Händler.
function ns.VendorFloor(vendorPrice, step)
    if not vendorPrice or vendorPrice <= 0 then return 0 end
    return ns.RoundUp(vendorPrice / (1 - ns.AH_CUT), step or 100)
end

--[[
    Preisvorschlag nach der Regel des Spielers. opts:
      rule          "undercut" (ein Schritt unter dem Tiefstpreis) | "percent" | "match" (= Tiefstpreis)
      percent       für "percent"
      lowest        günstigstes Angebot (je Stück bzw. je Auktion), nil wenn es keins gibt
      mineIsLowest  das günstigste Angebot ist das eigene: dann nicht sich selbst unterbieten
      last          eigener letzter Preis (Ersatz, wenn es kein Angebot gibt)
      market        Marktwert aus dem Preis-Wissen (Ersatz, wenn es weder Angebot noch letzten Preis gibt)
      vendor, floor Händlerpreis und „nie darunter“
      trendLow      Tief der erfassten Tage (Schalter floorTrend, AUC-13): nie darunter; nil = keine Grenze
      step          Preisschritt (ns.Step())
    Rückgabe: Preis oder nil (dann bleibt Blizzards Vorschlag); zweite Rückgabe "trend", wenn das Tief der
    erfassten Tage den Preis angehoben hat (der Tooltip der Regel nennt dann den Grund).
]]
function ns.RulePrice(opts)
    local step = opts.step or 100
    local price
    local lowest = opts.lowest
    if lowest and lowest > 0 then
        if opts.mineIsLowest or opts.rule == "match" then
            price = lowest
        elseif opts.rule == "percent" then
            price = ns.RoundDown(lowest * (100 - (opts.percent or 0)) / 100, step)
        else
            price = ns.RoundDown(lowest - 1, step)
        end
    elseif opts.last and opts.last > 0 then
        price = opts.last
    elseif opts.market and opts.market > 0 then
        price = ns.RoundDown(opts.market, step)
    else
        return nil
    end
    local raised
    local trendLow = Core.Num(opts.trendLow)
    if trendLow and trendLow > 0 and price < trendLow then
        price, raised = ns.RoundUp(trendLow, step), "trend"
    end
    if opts.floor and opts.vendor then
        local minimum = ns.VendorFloor(opts.vendor, step)
        if price < minimum then price, raised = minimum, nil end
    end
    if price < step then price = step end
    return price, raised
end

---------------------------------------------------------------------------
-- Blizzards Auktionshaus: Laden, Ansicht, Suchen im Takt des Servers
---------------------------------------------------------------------------

-- fn läuft einmal, sobald Blizzard_AuctionHouseUI geladen ist (lädt erst beim ersten Besuch).
ns.ahHooks = {}
function ns.OnAuctionHouse(fn)
    table.insert(ns.ahHooks, fn)
    if ns.ahReady then ns.Try("AuctionHouse", fn) end
end

-- Blizzards Reiter unten im Auktionsfenster: Kaufen, Verkaufen, Auktionen (BuyTab, SellTab, AuctionsTab in
-- Blizzard_AuctionHouseFrame.xml, Zweig forever). Ein gewählter Reiter dahinter gehört einem fremden Addon.
ns.BLIZZARD_TABS = 3

-- Zeigt das offene Auktionsfenster gerade die Ansicht eines fremden Addons (z. B. einen Reiter von Auctionator)?
-- Erkannt nur an Blizzards eigenem Fenster – kein Blick in fremde Rahmen oder fremden Quelltext, nichts wird
-- geschrieben (Leitlinien 5 und 10):
--   1. der gewählte Reiter liegt hinter Blizzards drei (PanelTemplates_GetSelectedTab),
--   2. die Anzeigeart ist keine aus Blizzards Tabelle AuctionHouseFrameDisplayMode,
--   3. keine von Blizzards Flächen (die Namen aus derselben Tabelle) ist eingeblendet.
-- Zweite Rückgabe: welches Zeichen griff ("tab" | "mode" | "surfaces"). Fehlt etwas davon auf dem Client, gilt das
-- Zeichen nicht – dann bleibt es beim Verhalten ohne Erkennung.
function ns.ForeignView()
    local frame, modes = AuctionHouseFrame, AuctionHouseFrameDisplayMode
    if not (frame and type(modes) == "table") then return false end
    local tab = Core.Call(PanelTemplates_GetSelectedTab, frame)
    if type(tab) == "number" and not Core.IsSecret(tab) and tab > ns.BLIZZARD_TABS then return true, "tab" end
    local mode = frame.GetDisplayMode and frame:GetDisplayMode()
    local known, found, shown = mode == nil, false, false
    for _, surfaces in pairs(modes) do
        if surfaces == mode then known = true end
        for _, name in ipairs(type(surfaces) == "table" and surfaces or {}) do
            local surface = frame[name]
            if type(surface) == "table" and surface.IsShown then
                found = true
                if surface:IsShown() then shown = true end
            end
        end
    end
    if not known then return true, "mode" end
    if found and not shown then return true, "surfaces" end
    return false
end

-- "buy" | "sell" | "auctions" | "other" (nil, solange das Fenster fehlt); zweite Rückgabe: Blizzards Ergebnisliste
-- sichtbar. "other": die Ansicht eines fremden Addons (ns.ForeignView) – dort stehen ezAuctions Teile nicht.
function ns.ModeName()
    local frame, modes = AuctionHouseFrame, AuctionHouseFrameDisplayMode
    if not (frame and modes and frame.GetDisplayMode) then return nil end
    local mode = frame:GetDisplayMode()
    if mode == nil then return nil end
    if ns.ForeignView() then return "other" end
    if mode == modes.Buy then return "buy", true end
    if mode == modes.ItemBuy or mode == modes.CommoditiesBuy or mode == modes.WoWTokenBuy then return "buy", false end
    if mode == modes.ItemSell or mode == modes.CommoditiesSell or mode == modes.WoWTokenSell then return "sell" end
    if mode == modes.Auctions then return "auctions" end
    return nil
end

-- Auktionshaus offen? Eine Antwort für alle Module: ezCores Core.AuctionHouseOpen (Blizzards Fenster, sonst der Stand
-- aus AUCTION_HOUSE_SHOW/_CLOSED; Welle 23a). Der Name bleibt für die Aufrufer in ezAuction.
function ns.AuctionHouseShown()
    return Core.AuctionHouseOpen() == true
end

-- Zeigt Blizzards Ergebnisliste (z. B. aus der Ansicht eines Gegenstands zurück), wie Blizzards Zurück-Knopf.
function ns.ShowBrowseResults()
    local frame, modes = AuctionHouseFrame, AuctionHouseFrameDisplayMode
    if not (frame and modes and frame.SetDisplayMode) then return end
    local _, browsing = ns.ModeName()
    if not browsing then frame:SetDisplayMode(modes.Buy) end
end

-- Die Ansicht melden: AH_MODE mit "buy" | "sell" | "auctions" | "other" (oder nil). Gemerkt wird, was zuletzt
-- gemeldet wurde, damit ns.CheckMode nur bei einem Wechsel meldet.
local lastMode, lastBrowsing
local function FireMode()
    local mode, browsing = ns.ModeName()
    lastMode, lastBrowsing = mode, browsing
    ns.Fire("AH_MODE", mode)
end

-- Hat sich die Ansicht geändert, ohne dass Blizzards SetDisplayMode lief? Ein fremdes Addon kann seinen Reiter
-- zeigen, indem es nur Blizzards Flächen ausblendet oder einen Reiter wählt – dann meldet ezAuction "other" nach,
-- und auf dem Weg zurück wieder Blizzards Ansicht. Rückgabe: true, wenn gemeldet wurde.
function ns.CheckMode()
    if not ns.ahReady then return false end
    local mode, browsing = ns.ModeName()
    if mode == lastMode and browsing == lastBrowsing then return false end
    FireMode()
    return true
end

-- Nur zuhören (hooksecurefunc/HookScript): Blizzards Reiterwahl und das Ein- und Ausblenden von Blizzards Flächen.
-- Geprüft wird gesammelt im nächsten Bild – mitten in Blizzards SetDisplayMode sind kurz alle Flächen aus.
local function WatchForeignView(frame)
    local later = ns.Throttle(ns.CheckMode, 0)
    if type(PanelTemplates_SetTab) == "function" then
        hooksecurefunc("PanelTemplates_SetTab", function(owner)
            if owner == frame then later() end
        end)
    end
    local seen = {}
    for _, surfaces in pairs(type(AuctionHouseFrameDisplayMode) == "table" and AuctionHouseFrameDisplayMode or {}) do
        for _, name in ipairs(type(surfaces) == "table" and surfaces or {}) do
            local surface = frame[name]
            if not seen[name] and type(surface) == "table" and surface.HookScript then
                seen[name] = true
                surface:HookScript("OnShow", later)
                surface:HookScript("OnHide", later)
            end
        end
    end
end

ns.OnReady(function()
    ns.WhenAddOnLoaded(ns.BLIZZARD_ADDON, function()
        if ns.ahReady or not AuctionHouseFrame then return end
        ns.ahReady = true
        hooksecurefunc(AuctionHouseFrame, "SetDisplayMode", FireMode)
        AuctionHouseFrame:HookScript("OnShow", function() ns.Fire("AH_SHOW") end)
        AuctionHouseFrame:HookScript("OnHide", function() ns.Fire("AH_HIDE") end)
        ns.Try("ForeignView", WatchForeignView, AuctionHouseFrame)
        for _, fn in ipairs(ns.ahHooks) do ns.Try("AuctionHouse", fn) end
        FireMode()
    end)
end)

-- Sortierung für eigene Suchen: Preis, dann Name (Blizzards Standard in der Ergebnisliste).
function ns.Sorts()
    local order = Enum and Enum.AuctionHouseSortOrder
    if not order then return {} end
    return { { sortOrder = order.Price, reverseSort = false }, { sortOrder = order.Name, reverseSort = false } }
end

function ns.KeyString(itemKey)
    if type(itemKey) ~= "table" then return tostring(itemKey) end
    return ("%s:%s:%s:%s"):format(itemKey.itemID or 0, itemKey.itemLevel or 0, itemKey.itemSuffix or 0,
        itemKey.battlePetSpeciesID or 0)
end

function ns.SameKey(a, b)
    return type(a) == "table" and type(b) == "table" and ns.KeyString(a) == ns.KeyString(b)
end

-- Suchanfragen drosselt der Server: fn läuft, sobald Blizzard wieder eine Anfrage annimmt (der Reihe nach).
local throttleQueue = {}
local pumping = false
local function ThrottleReady()
    local api = C_AuctionHouse
    if not (api and api.IsThrottledMessageSystemReady) then return true end
    return Core.Call(api.IsThrottledMessageSystemReady) == true
end

local function PumpThrottle()
    while #throttleQueue > 0 and ThrottleReady() do
        local fn = table.remove(throttleQueue, 1)
        ns.Try("Throttle", fn)
    end
    -- Ereignis AUCTION_HOUSE_THROTTLED_SYSTEM_READY verpasst? Dann nachsehen.
    if #throttleQueue > 0 and not pumping then
        pumping = true
        C_Timer.After(0.5, function()
            pumping = false
            PumpThrottle()
        end)
    end
end

function ns.WhenThrottleReady(fn)
    table.insert(throttleQueue, fn)
    PumpThrottle()
end

function ns.ClearThrottleQueue()
    throttleQueue = {}
end

ns.On("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", PumpThrottle)
ns.On("AUCTION_HOUSE_CLOSED", function()
    ns.ClearThrottleQueue()
    ns.Fire("AH_CLOSED")
end)

---------------------------------------------------------------------------
-- ezCores Abfrage-Warteschlange (AH-37, Welle 13)
---------------------------------------------------------------------------
--[[
    Alles, was Blizzards Ergebnisliste füllt oder das gedrosselte Nachrichtensystem nutzt, reiht sich in ezCores
    Prices.Queue ein (Rang „modul“, Schlüssel „ezAuction.<name>“) – nie zwei Abfragen zugleich, eine Suche des Spielers
    hält Erfassungen an und bricht Modul-Suchen ab. Ein Auftrag: { name, text, start(job), cancel(job, grund),
    timeout }. Fehlt die Warteschlange oder meldet ezCore das Haus noch nicht offen (Prices.IsOpen), läuft der Auftrag
    wie vor Welle 13 im eigenen Takt (ns.WhenThrottleReady) – Rückfall auf das bisherige Verhalten (Grundsatz 5).
]]
ns.QUEUE_PREFIX = "ezAuction."

-- ezCores Warteschlange, wenn es sie gibt und ezCore das Haus offen weiß; sonst nil.
function ns.Queue()
    local prices = Core.Prices
    local queue = type(prices) == "table" and prices.Queue
    if type(queue) ~= "table" or type(queue.Add) ~= "function" or type(queue.Done) ~= "function"
        or type(queue.Cancel) ~= "function" then
        return nil
    end
    if type(prices.IsOpen) == "function" and not Core.Call(prices.IsOpen) then return nil end
    return queue
end

-- Einreihen. Rückgabe: "queue" (ezCores Warteschlange) oder "takt" (eigener Takt).
function ns.Enqueue(job)
    job.key = ns.QUEUE_PREFIX .. tostring(job.name or "job")
    job.owner, job.rank = ADDON, job.rank or "module"
    job.dropped, job.id = nil, nil
    local queue = ns.Queue()
    if queue and queue.Add(job) then return "queue" end
    job.id = nil
    ns.WhenThrottleReady(function()
        if not job.dropped then ns.Try("Queue", job.start, job) end
    end)
    return "takt"
end

-- Fertig (die Antwort ist da): ezCores Warteschlange gibt die Liste dem nächsten Auftrag.
function ns.JobDone(job)
    local queue = type(job) == "table" and job.id and ns.Queue()
    if queue then return queue.Done(job.id) end
    return false
end

-- Nicht mehr gebraucht (eigener Abbruch): wartet er noch, startet er nicht mehr; läuft er, gibt er die Liste frei.
function ns.DropJob(job)
    if type(job) ~= "table" then return end
    job.dropped = true
    local queue = job.id and ns.Queue()
    if queue then queue.Cancel(job.key) end
end

-- Ein Klick des Spielers in ezAuctions Oberfläche (Suchverlauf, „ד der Filterzeile, Suche für ein anderes Modul) ist
-- seine eigene Suche: ezCore hält Erfassungen an wie bei Blizzards Suchfeld. Danach geht die Abfrage im eigenen Takt
-- hinaus (sie folgt dem Klick, sonst stünde Blizzards Antwort bis zum Ende der Wartezeit in der Liste).
function ns.UserQuery()
    local queue = ns.Queue()
    if queue and type(queue.UserSearched) == "function" then Core.Call(queue.UserSearched, "ezAuction") end
end

---------------------------------------------------------------------------
-- Tor T1 (AH-41): Taint-Spieltest am Verkaufs- und Kaufbereich
---------------------------------------------------------------------------
-- Antwort und Nachtrag des Nutzers am 15.11.2026 (Wortlaut in docs/roadmap/ezAuction.md und im ROADMAP-Index) gelten
-- nur dem Kaufbereich (Probe X7: Menge im Warenkauf): kein Taint-Block; der Fehler „kann nicht mehr gekauft werden“
-- ließ sich nicht wiederholen, ein Kauf nach dem Setzen der Menge ging durch. Für den Verkaufsbereich (Teile a
-- und b des Tors) gibt es kein Ergebnis – darum bauen AH-18 und AH-19 die Anzeige-Fassung. Ein Ergebnis „geht“ setzt
-- ns.T1.sell = "geht": dann legen „Nächster“ und die Standardwerte selbst ein (Blizzards SetPostItem, SetQuantity,
-- SetDuration). Bei „blockiert“: ns.T1.sell = "blockiert", und „Nur vorschlagen“ ist ab Werk an (ns.SuggestDefault).
ns.T1 = { sell = "offen", buy = "kein Block, Fehler nicht wiederholbar" }

function ns.SellSetsValues() return ns.T1.sell == "geht" end

-- Stand von T1 für Texte in der Spielsprache (Leitlinie 7): die Werte oben bleiben die Schlüssel für den Code.
ns.T1_TEXT = { offen = "T1_STATE_OPEN", blockiert = "T1_STATE_BLOCKED", geht = "T1_STATE_WORKS",
    ["kein Block, Fehler nicht wiederholbar"] = "T1_STATE_NOBLOCK" }
function ns.T1Text(area)
    local value = ns.T1[area]
    local key = ns.T1_TEXT[value]
    return key and L[key] or tostring(value)
end

-- Standard des Schalters „Nur vorschlagen, nichts eintragen“ (AH-38): an nur bei „blockiert“.
function ns.SuggestDefault() return ns.T1.sell == "blockiert" end
ns.DEFAULTS.suggestOnly = ns.SuggestDefault()

-- Kaufbereich (AH-24, Welle 14): Darf ezAuction dort überhaupt etwas setzen (Menge im Warenkauf, Auswahl der nächsten
-- Zeile)? Nur, solange T1 für den Kaufbereich weder „blockiert“ noch „offen“ ist. Auch dann setzt es nur mit dem
-- jeweiligen Schalter (buySetQuantity, buyNextSelect – ab Werk aus, weil der Fehler „kann nicht mehr gekauft werden“
-- einmal kam und sich nicht wiederholen ließ); sonst die Anzeige-Fassung (Text und Markierung).
function ns.BuyMaySet() return ns.T1.buy ~= "blockiert" and ns.T1.buy ~= "offen" end

---------------------------------------------------------------------------
-- Rücksicht je Teil (AH-31, Welle 15)
---------------------------------------------------------------------------
--[[
    Welche Teile von ezAuction einem fremden Addon weichen, ob sie es gerade tun, wie oft sie in dieser Sitzung gewichen
    sind und welchem – für „/eza status“, die Einstellungsseite (Knopf „Trotzdem erfassen“), den Eintrag
    „Rücksicht“ im Zahnrad-Menü und die Erklärblase am Zahnrad (Tour.lua). Der Zähler ist ezCores Core.WhoHandles
    (gezählt unter ezAuction, je Sitzung): bei jedem Besuch des Auktionshauses einmal je Teil, der gerade weicht
    (Yield.Note), dazu, wenn ezAuction bei der Arbeit selbst fragt (ns.OtherFor in Scan.HoldBack). Die übrigen Teile –
    Einkaufslisten, Taschenliste, „Unterbotene abbrechen“ – weichen nie (Beside.lua, Frage 35).
      key      "tooltip" | "scan" (Texte YIELD_PART_<key>, YIELD_NOW_<key>, YIELD_FORCE_<key>)
      feature  Rücksicht-Schlüssel in ezCore (Core.OTHER_ADDONS)
      setting  Schalter, ohne den der Teil ohnehin nichts täte (dann zählt ein Besuch nicht als „gewichen“)
      yields() Name des Addons, dem der Teil gerade weicht – ohne zu zählen (Core.WhoHandlesInfo); sonst nil
      forced() Name des Addons, neben dem der Teil trotzdem läuft (nur die Tooltip-Zeile), sonst nil
      force()  optional: Knopf auf der Einstellungsseite („Trotzdem erfassen“) → true, wenn etwas geschah
]]
local Yield = {}
ns.Yield = Yield

local function Taker(feature)
    if type(Core.WhoHandlesInfo) ~= "function" then return nil end
    return (Core.WhoHandlesInfo(feature))
end

Yield.PARTS = {
    {
        key = "tooltip", feature = "auctionTooltip", setting = "tooltipPrice",
        yields = function()
            if ns.Enabled("tooltipBeside") then return nil end
            return ns.Beside.Running() or Taker("auctionTooltip")
        end,
        forced = function()
            if not ns.Enabled("tooltipBeside") then return nil end
            return ns.Beside.Running() or Taker("auctionTooltip")
        end,
        -- kein Knopf „Trotzdem zeigen“ mehr (Einstellungs-Prüfung vom 19.11.2026, Nr. 61): er setzte denselben Wert wie
        -- das Häkchen „Auch neben anderen Auktions-Addons zeigen“, aber ohne Weg zurück – das Häkchen bleibt der eine Weg
    },
    {
        key = "scan", feature = "auctionScan", setting = "scanOnOpen",
        yields = function() return Taker("auctionScan") end,
        forced = function() return nil end,
        -- Erfassen ist ein Klick: „Trotzdem erfassen“ startet es jetzt (bei geschlossenem Haus sagt Scan.Start, warum nicht)
        force = function() return ns.Scan.Start() == true end,
    },
}

function Yield.Part(key)
    for _, part in ipairs(Yield.PARTS) do
        if part.key == key then return part end
    end
    return nil
end

-- Wie oft ist der Teil in dieser Sitzung gewichen (Einträge unter ezAuction), und welchem Addon? → Anzahl, Name.
function Yield.Count(part)
    if type(Core.YieldCounts) ~= "function" or type(part) ~= "table" then return 0, nil end
    -- „zuletzt“: der Eintrag mit dem jüngsten Weichen (YieldCounts ist nach Anzahl sortiert, nicht nach Zeit).
    local n, label, latest = 0, nil, nil
    for _, e in ipairs(Core.YieldCounts(part.feature)) do
        if e.module == ADDON then
            n = n + (Core.Num(e.n) or 0)
            local last = Core.Num(e.last) or 0
            if label == nil or last > latest then label, latest = e.label, last end
        end
    end
    return n, label
end

-- Ein Besuch des Auktionshauses: je Teil, der gerade weicht (und dessen Schalter an ist), einmal zählen.
-- Rückgabe: Anzahl der gezählten Teile.
function Yield.Note()
    if type(Core.WhoHandles) ~= "function" then return 0 end
    local counted = 0
    for _, part in ipairs(Yield.PARTS) do
        if ns.Enabled(part.setting) and part.yields() and Core.WhoHandles(part.feature, ADDON) then counted = counted + 1 end
    end
    return counted
end

-- Satz je Teil: „Tooltip-Zeile „Auktion“: weicht Auctionator (in dieser Sitzung 3× gewichen)“.
function Yield.Line(part)
    local now, forced = part.yields(), part.forced()
    local state
    -- Schalter des Teils aus (etwa „Beim Öffnen erfassen“, ab Werk aus): dann weicht ezAuction niemandem
    if not ns.Enabled(part.setting) then
        state = L.YIELD_STATE_OFF:format(L["OPT_" .. part.setting] or part.setting)
    elseif now then
        state = L["YIELD_NOW_" .. part.key]:format(now)
    elseif forced then
        state = L.YIELD_STATE_FORCED:format(forced)
    else
        state = L.YIELD_STATE_FREE
    end
    local n, label = Yield.Count(part)
    if n > 0 then state = state .. " " .. L.YIELD_STATE_COUNT:format(n, label or "?") end
    return L.YIELD_LINE:format(L["YIELD_PART_" .. part.key], state)
end

function Yield.Lines()
    local lines = { L.YIELD_HEAD }
    for _, part in ipairs(Yield.PARTS) do lines[#lines + 1] = Yield.Line(part) end
    return lines
end

function Yield.Print()
    for _, line in ipairs(Yield.Lines()) do ns.Print(line) end
end

-- Name eines fremden Auktions-Addons, dem ezAuction gerade in irgendeinem Teil weicht (für die Erklärblase), sonst nil.
function Yield.Other()
    for _, part in ipairs(Yield.PARTS) do
        local who = part.yields()
        if who then return who end
    end
    return nil
end

-- Knopf je Teil auf der Einstellungsseite („Trotzdem erfassen“); ein Teil ohne force hat keinen Knopf.
function Yield.Force(key)
    local part = Yield.Part(key)
    if not (part and type(part.force) == "function") then return false end
    return part.force() == true
end

-- Name des fremden Addons, neben dem der Teil weicht oder trotzdem läuft, sonst nil – für die Zeile „Auch neben
-- anderen Auktions-Addons zeigen“, die nur dann erscheint (Einstellungs-Prüfung vom 19.11.2026, Nr. 61).
function Yield.OtherFor(key)
    local part = Yield.Part(key)
    if not part then return nil end
    return part.yields() or part.forced()
end

ns.Listen("AH_SHOW", function() ns.Try("Yield", Yield.Note) end)

---------------------------------------------------------------------------
-- Lage der eigenen Teile an Blizzards Auktionshaus (Spielbefund 16.11.2026: Knopf „Preise erfassen“, Pfeil, Zahnrad
-- und „Heute: …“ lagen über Blizzards Favoriten-Stern und dem Suchfeld, der Pfeil „Letzte Suchen“ im Suchfeld).
-- Ein Ort für die Maße: die Bau-Funktionen (Prices.lua, Options.lua, Search.lua, History.lua) lesen sie hier, und
-- Layout.Rects rechnet daraus die Rechtecke, die Tests/lage.lua gegen Blizzards Teile auf Überlappung prüft.
-- Koordinaten: ab der linken oberen Ecke von AuctionHouseFrame, x nach rechts, y nach oben (also negativ nach unten).
---------------------------------------------------------------------------

local Layout = {}
ns.Layout = Layout

-- Blizzards Maße (Gethe/wow-ui-source, Zweig forever): Fenster 800 × 538 und Lage der Suchleiste
-- (Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseFrame.xml: SearchBar TOPRIGHT −12/−29, CategoriesList TOP
-- = SearchBar BOTTOM −4, ItemSellFrame TOP −69); Suchleiste 618 × 40 mit Favoriten-Knopf links, Suchfeld 9 daneben,
-- „Suchen“ rechts und „Filter“ 10 links davon (Shared/Blizzard_AuctionHouseSearchBar.xml, Suchfeld 241 × 22,
-- „Suchen“ 132 × 22); Favoriten-Knopf SquareIconButtonTemplate 32 × 32 (Blizzard_SharedXML/Shared/Button/
-- IconButtonTemplate.xml); Filter WowStyle1FilterDropdownTemplate 135 × 18 (Blizzard_Menu/Mainline/MenuTemplates.xml);
-- Bildnis 62 × 62 bei −5/+7 (Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml, PortraitContainer).
Layout.BLIZZARD = {
    frameWidth = 800,
    portrait = { x = -5, y = 7, w = 62, h = 62 },
    searchBar = { right = -12, top = -29, w = 618, h = 40 },
    favorites = { w = 32, h = 32 },
    searchBox = { gap = 9, w = 241, h = 22 },
    searchButton = { w = 132, h = 22 },
    filterButton = { gap = 10, w = 135, h = 18 },
    categoriesGap = 4,
    sellTop = -69,
    -- Reiter Auktionen (Mainline/Blizzard_AuctionHouseAuctionsFrame.xml): „Auktionen“ TOPLEFT 47/−1, obere Reiter
    -- 32 hoch (PanelTabButtonTemplate); SummaryList TOP = Reiter BOTTOM +2, AllAuctionsList TOP = SummaryList TOP −1
    auctions = { tabTop = -1, tabHeight = 32, listRise = 1 },
}

-- Eigene Maße. Erste Zeile rechts neben dem Bildnis: Knopf „Preise erfassen“ (Blizzards Textknopf, Breite für
-- „Preise erfassen“/„Wieder in 13:00“). Zweite Zeile darunter: Pfeil mit dem Menü, Zahnrad und „Heute: …“ – rechts
-- begrenzt durch Blizzards Favoriten-Knopf (ab x = 170, COVERAGE_RIGHT davor), damit nichts in die Suchleiste ragt.
-- Gegenprüfung vom 17.11.2026: „Heute: 100 %“ ist in GameFontDisableSmall bei UI-Skalierung 1,0 rund 67 breit
-- (ausgemessen am Bildschirmfoto des Spielbefunds); bis zur Kante des Knopfs blieben nur 64 – deshalb rückt der Text
-- mit kleineren Abständen bis kurz vor den Favoriten-Knopf (70).
-- (Core.Style gibt es seit ezCore 1.13.0, needs nennt Style.ColorText; ohne es die Werte von dort, damit das Laden
-- mit einem älteren ezCore nicht abbricht und ezCore den Grund nennen kann)
local BUTTON = Core.Style and Core.Style.BUTTON or { close = 24, small = 16 }
Layout.SCAN = { x = 62, y = -26, w = 104, h = 22 }
Layout.ROW_GAP = 3                          -- Abstand der zweiten Zeile unter dem Knopf
Layout.SMALL = BUTTON.small                 -- Pfeil und Zahnrad: kleiner Knopf (16, Design-System 2.2)
Layout.GAP = 2                              -- zwischen Pfeil und Zahnrad
Layout.TEXT_GAP = 2                         -- zwischen Zahnrad und „Heute: …“
Layout.COVERAGE_RIGHT = 2                   -- Abstand von „Heute: …“ zu Blizzards Favoriten-Knopf
Layout.TEXT_HEIGHT = 12                     -- Zeilenhöhe von GameFontDisableSmall (nur für die Prüfung der Rechtecke)
-- „Letzte Suchen“: rechts neben dem Suchfeld wie der Knopf an Blizzards Auswahlfeld (UIDropDownMenuTemplate: Button
-- 24 × 24 mit UI-ChatIcon-ScrollDown, Blizzard_SharedXML/Mainline/UIDropDownMenuTemplates.xml)
Layout.RECENT = { gap = 2, size = BUTTON.close }
-- Reiter „Verlauf“: Abstand wie PanelTemplates_AnchorTabs (3); Zahnrad im Reiter Auktionen 10 rechts davon, auf der
-- Höhe der Schrift eines nicht gewählten oberen Reiters (PanelTemplates_DeselectTab: Mitte −8) – 2 höher, damit es
-- über der Liste bleibt, die 1 Pixel über der Unterkante der Reiter beginnt
Layout.TAB_GAP = 3
Layout.TAB_GEAR = { x = 10, y = -6 }
-- Marken in der Preisspalte: Symbol (Pfeil aus ezGear, Warnzeichen) links, Text mit festem Abstand daneben.
-- sign: Platz für ezGears Zeichen neben dem Pfeil („+“ in NumberFontNormal, Schalter „Zeichen am Leuchten“), solange
-- der Pfeil noch lädt und nicht gemessen werden kann. right: rückt ein Symbol den Text nach rechts, endet er spätestens
-- hier und kürzt mit „…“ – ein Silberpreis beginnt im Bildschirmfoto des Spielbefunds 83 vom linken Rand der Zeile
-- (Gegenprüfung vom 17.11.2026); ohne Symbol bleibt der Text, wie er immer war.
Layout.MARK = { x = 2, gap = 4, text = 6, sign = 8, right = 80 }

local function Rect(l, t, w, h) return { l = l, t = t, r = l + w, b = t - h } end
Layout.Rect = Rect

-- Überlappen sich zwei Rechtecke (gemeinsame Kante zählt nicht)?
function Layout.Overlap(a, b)
    return a.l < b.r and b.l < a.r and a.b < b.t and b.b < a.t
end

-- Linke Kante von Blizzards Favoriten-Knopf (linker Rand der Suchleiste).
function Layout.SearchBarLeft()
    local B = Layout.BLIZZARD
    return B.frameWidth + B.searchBar.right - B.searchBar.w
end

-- Abstand von „Heute: …“ zur rechten Kante des Pfeils und die Breite, die bis kurz vor den Favoriten-Knopf bleibt.
function Layout.CoverageOffset()
    return Layout.GAP + Layout.SMALL + Layout.TEXT_GAP
end
function Layout.CoverageWidth()
    local left = Layout.SCAN.x + Layout.SMALL + Layout.CoverageOffset()
    return Layout.SearchBarLeft() - Layout.COVERAGE_RIGHT - left
end

-- Volle Breite eines Textes, auch wenn die Schrift-Zeile eine feste Breite hat und kürzt (GetUnboundedStringWidth;
-- ohne sie GetStringWidth); 0, wenn nichts zu messen ist.
function Layout.TextWidth(fontString)
    if type(fontString) ~= "table" then return 0 end
    local measure = fontString.GetUnboundedStringWidth or fontString.GetStringWidth
    if type(measure) ~= "function" then return 0 end
    return Core.Num(measure(fontString)) or 0
end

-- Rechtecke: Blizzards Teile (1. Rückgabe) und ezAuctions Teile (2.) in den Reitern Kaufen und Verkaufen.
function Layout.Rects()
    local B, S = Layout.BLIZZARD, Layout.SCAN
    local barLeft = Layout.SearchBarLeft()
    local barRight = B.frameWidth + B.searchBar.right
    local barMid = B.searchBar.top - B.searchBar.h / 2
    local function Centered(l, w, h) return Rect(l, barMid + h / 2, w, h) end
    local blizzard = {}
    blizzard.portrait = Rect(B.portrait.x, B.portrait.y, B.portrait.w, B.portrait.h)
    blizzard.favorites = Centered(barLeft, B.favorites.w, B.favorites.h)
    blizzard.searchBox = Centered(blizzard.favorites.r + B.searchBox.gap, B.searchBox.w, B.searchBox.h)
    blizzard.searchButton = Centered(barRight - B.searchButton.w, B.searchButton.w, B.searchButton.h)
    blizzard.filterButton = Centered(blizzard.searchButton.l - B.filterButton.gap - B.filterButton.w,
        B.filterButton.w, B.filterButton.h)
    -- Kategorienliste (Kaufen) und Verkaufsbereich (Verkaufen): es zählt die Oberkante
    blizzard.categories = Rect(4, B.searchBar.top - B.searchBar.h - B.categoriesGap, barLeft - 4, 400)
    blizzard.sell = Rect(4, B.sellTop, B.frameWidth - 8, 400)

    local own = {}
    own.scan = Rect(S.x, S.y, S.w, S.h)
    local rowTop = own.scan.b - Layout.ROW_GAP
    own.scanMenu = Rect(S.x, rowTop, Layout.SMALL, Layout.SMALL)
    own.gear = Rect(own.scanMenu.r + Layout.GAP, rowTop, Layout.SMALL, Layout.SMALL)
    own.coverage = Rect(own.scanMenu.r + Layout.CoverageOffset(), rowTop - (Layout.SMALL - Layout.TEXT_HEIGHT) / 2,
        Layout.CoverageWidth(), Layout.TEXT_HEIGHT)
    own.recent = Centered(blizzard.searchBox.r + Layout.RECENT.gap, Layout.RECENT.size, Layout.RECENT.size)
    return blizzard, own
end

-- Reiter Auktionen, nur senkrecht (x ist dort die Breite der Reiter-Schrift): Oberkante der Liste unter den Reitern und
-- das Zahnrad neben „Verlauf“, je als Rechteck über die ganze Breite. Rückgabe: Liste, Zahnrad.
function Layout.AuctionsRects()
    local A = Layout.BLIZZARD.auctions
    local tabMid = A.tabTop - A.tabHeight / 2
    local list = Rect(0, A.tabTop - A.tabHeight + A.listRise, 1000, 400)
    local gearMid = tabMid + Layout.TAB_GEAR.y
    local gear = Rect(0, gearMid + Layout.SMALL / 2, 1000, Layout.SMALL)
    return list, gear
end

-- Linker Abstand des Texts einer Zeilen-Marke: ohne Symbol MARK.text, mit Symbol (Breite gemessen) rechts daneben.
function Layout.MarkTextOffset(width)
    local M = Layout.MARK
    width = tonumber(width) or 0
    if width <= 0 then return M.text end
    return math.max(M.text, M.x + width + M.gap)
end

-- Breite der gezeigten Symbole auf einem Halter (ezGears Pfeil samt Zeichen für Farbenblinde): breitestes Bild plus
-- gezeigte Schrift daneben. Nur gelesen; die Bilder legt ezGear selbst auf ezAuctions Halter.
function Layout.MarkWidth(holder)
    if type(holder) ~= "table" or type(holder.GetRegions) ~= "function" then return 0 end
    local image, text = 0, 0
    for _, region in ipairs({ holder:GetRegions() }) do
        if type(region) == "table" and region.IsShown and region:IsShown() then
            if region.GetStringWidth then
                text = text + (Core.Num(region:GetStringWidth()) or 0)
            else
                image = math.max(image, Core.Num(region:GetWidth()) or 0)
            end
        end
    end
    return image + text
end

---------------------------------------------------------------------------
-- Zeilen in Blizzards Listen markieren (Ergebnisse, eigene Auktionen)
---------------------------------------------------------------------------

-- Eine Auflage je Zeile, in einer eigenen Tabelle gemerkt (nie als Feld in Blizzards Zeile).
local overlays = setmetatable({}, { __mode = "k" })

function ns.RowOverlay(row)
    local overlay = overlays[row]
    if overlay then return overlay end
    overlay = CreateFrame("Frame", nil, row)
    overlay:SetAllPoints(row)
    overlay:SetFrameLevel((row:GetFrameLevel() or 1) + 5)
    if overlay.EnableMouse then overlay:EnableMouse(false) end
    overlay.label = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    overlay.label:SetPoint("LEFT", overlay, "LEFT", Layout.MARK.text, 0)
    -- Halter für ezGears Pfeil (Upgrade.lua): links in der Zeile, senkrecht mittig; der Text rückt rechts daneben
    overlay.marks = CreateFrame("Frame", nil, overlay)
    overlay.marks:SetSize(Core.Style.ICON.line, Core.Style.ICON.line)
    overlay.marks:SetPoint("LEFT", overlay, "LEFT", Layout.MARK.x, 0)
    overlay.tint = overlay:CreateTexture(nil, "BACKGROUND")
    overlay.tint:SetAllPoints(overlay)
    overlay.tint:SetColorTexture(1, 0.1, 0.1, 0.12)
    overlay.tint:Hide()
    overlay.icon = overlay:CreateTexture(nil, "OVERLAY")
    overlay.icon:SetSize(Core.Style.ICON.line, Core.Style.ICON.line)   -- Design-System 2.3 (bis Welle 22 14)
    overlay.icon:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", 2, 1)
    overlay.icon:SetTexture("Interface\\Buttons\\UI-MicroStream-Red")
    overlay.icon:Hide()
    -- Text rechts neben den gezeigten Symbolen (Spielbefund 16.11.2026: „−5 %“ und „Händler“ lagen unter dem Pfeil).
    -- markSlot: Platz für ezGears Pfeil freihalten, solange er noch lädt (Upgrade.Mark setzt ihn nur dann; steht der
    -- Pfeil, wird er gemessen, und ohne Pfeil bleibt der Text am Rand – Gegenprüfung vom 17.11.2026).
    function overlay:PlaceLabel()
        local M = Layout.MARK
        local width = Layout.MarkWidth(self.marks)
        if self.markSlot then
            local sign = type(Core.MarksOn) == "function" and Core.MarksOn() == true and M.sign or 0
            width = math.max(width, Core.Style.ICON.line + sign)
        end
        if self.icon:IsShown() then width = math.max(width, Core.Style.ICON.line) end
        self.labelX = Layout.MarkTextOffset(width)
        self.label:ClearAllPoints()
        self.label:SetPoint("LEFT", self, "LEFT", self.labelX, 0)
        -- nach rechts gerückt: Breite begrenzen, damit der Text nicht in Blizzards Preisanzeige läuft
        if self.labelX > M.text then
            self.label:SetWidth(M.right - self.labelX)
            self.label:SetWordWrap(false)
            self.label:SetJustifyH("LEFT")
        else
            self.label:SetWidth(0)
        end
        return self.labelX
    end
    function overlay:SetLabel(text, r, g, b)
        self.label:SetText(text or "")
        if text then self.label:SetTextColor(r or 0.1, g or 1, b or 0.1) end
        self.label:SetShown(text ~= nil)
        self:PlaceLabel()
    end
    -- Farbiger Hauch über der Zeile (nil = keiner).
    function overlay:SetTint(r, g, b)
        if r then self.tint:SetColorTexture(r, g, b, 0.12) end
        self.tint:SetShown(r ~= nil)
    end
    function overlay:SetWarning(shown)
        if shown then self:SetTint(1, 0.1, 0.1) else self:SetTint(nil) end
        self.icon:SetShown(shown == true)
        self:PlaceLabel()
    end
    -- Abgeblendet (Filter „Nur Verbesserungen“, Upgrade.lua): ein dunkler Schleier über der Zeile – Blizzards Zeile
    -- und ihre Daten bleiben, wie sie sind.
    function overlay:SetDim(shown)
        if shown and not self.dim then
            self.dim = self:CreateTexture(nil, "ARTWORK")
            self.dim:SetAllPoints(self)
            self.dim:SetColorTexture(0, 0, 0, 0.6)
        end
        if self.dim then self.dim:SetShown(shown == true) end
    end
    -- Erklärung der Markierung, als Zeile im Tooltip der Zeile (nil = keine).
    function overlay:SetTip(text, r, g, b)
        self.tip = text
        self.tipColor = text and { r or 1, g or 0.82, b or 0 } or nil
    end
    overlays[row] = overlay
    return overlay
end

-- Nach Blizzards Tooltip einer Zeile (OnEnterListLine): erklärt die Markierung (roter Pfeil, „< Händler“, „−23 %“).
-- Hat Blizzard keinen Tooltip gezeigt, steht die Erklärung allein da.
function ns.RowTip(row)
    local overlay = overlays[row]
    local tip = overlay and overlay.tip
    if type(tip) ~= "string" then return false end
    local color = overlay.tipColor or { 1, 0.82, 0 }
    if GameTooltip:IsShown() and GameTooltip:GetOwner() ~= nil then
        GameTooltip:AddLine(tip, color[1], color[2], color[3], true)
    else
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:SetText(tip, color[1], color[2], color[3], 1, true)
    end
    GameTooltip:Show()
    return true
end

-- fn(row, rowData, overlay) für jede sichtbare Zeile einer Blizzard-Liste (AuctionHouseItemListTemplate).
function ns.DecorateNow(itemList, fn)
    local box = itemList and itemList.ScrollBox
    if not (box and box.ForEachFrame) then return end
    box:ForEachFrame(function(row)
        ns.Try("Decorate", fn, row, row.rowData, ns.RowOverlay(row))
    end)
end

-- Hängt fn an eine Blizzard-Liste: nach jedem Neuaufbau und jeder neu gefüllten Zeile (Blättern).
-- Rückgabe: Funktion, die alle sichtbaren Zeilen sofort neu markiert (z. B. nach einer Prüfung).
local decorateOwner = {}
function ns.DecorateList(itemList, fn)
    if not (itemList and itemList.ScrollBox) then return nil end
    local function Pass() ns.DecorateNow(itemList, fn) end
    local later = ns.Throttle(Pass, 0)
    if itemList.RefreshScrollFrame then hooksecurefunc(itemList, "RefreshScrollFrame", later) end
    if ScrollUtil and ScrollUtil.AddInitializedFrameCallback then
        pcall(ScrollUtil.AddInitializedFrameCallback, itemList.ScrollBox, later, decorateOwner, false)
    end
    if itemList.OnEnterListLine then
        hooksecurefunc(itemList, "OnEnterListLine", function(_, line) ns.Try("RowTip", ns.RowTip, line) end)
    end
    return Pass
end

---------------------------------------------------------------------------
-- Kleine Bausteine im Blizzard-Stil
---------------------------------------------------------------------------

-- Liste mit Blizzards ScrollBox und Rollbalken. init(row, data) baut bzw. füllt eine Zeile (Button).
function ns.NewScrollList(parent, rowHeight, init)
    local box = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
    local bar
    for _, template in ipairs({ "MinimalScrollBar", "WowClassicScrollBar", "WowTrimScrollBar" }) do
        local ok, frame = pcall(CreateFrame, "EventFrame", nil, parent, template)
        if ok and frame then bar = frame break end
    end
    local view = CreateScrollBoxListLinearView()
    if view.SetElementExtent then view:SetElementExtent(rowHeight) end
    view:SetElementInitializer("Button", function(row, data)
        row:SetHeight(rowHeight)
        ns.Try("ListRow", init, row, data)
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
    local list = { box = box, bar = bar }
    function list:SetPoints(topLeftX, topLeftY, bottomRightX, bottomRightY)
        box:ClearAllPoints()
        box:SetPoint("TOPLEFT", parent, "TOPLEFT", topLeftX, topLeftY)
        box:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", bottomRightX - (bar and 14 or 0), bottomRightY)
        if bar then
            bar:ClearAllPoints()
            bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 4, 0)
            bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 4, 0)
        end
    end
    function list:SetData(items)
        local retain = ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition
        box:SetDataProvider(CreateDataProvider(items), retain)
    end
    return list
end

-- Textknopf ohne Rahmen (klein, gold, beim Überfahren weiß, abgeschaltet grau) – für „Zuletzt“ und „Regel“ am
-- Preisfeld, „Wochen“ und „Als Text kopieren“ im Seitenteil „Markt“ (ohne eigene Schrift bliebe ein abgeschalteter
-- Knopf gold).
function ns.TextButton(parent)
    local button = CreateFrame("Button", nil, parent)
    button:SetHeight(14)
    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.text:SetPoint("LEFT")
    button:SetFontString(button.text)
    if button.SetNormalFontObject then button:SetNormalFontObject("GameFontNormalSmall") end
    if button.SetHighlightFontObject then button:SetHighlightFontObject("GameFontHighlightSmall") end
    if button.SetDisabledFontObject then button:SetDisabledFontObject("GameFontDisableSmall") end
    function button:SetLabel(text)
        self:SetText(text)
        self:SetWidth(math.max(20, (self.text:GetStringWidth() or 60) + 4))
    end
    button:SetScript("OnLeave", GameTooltip_Hide)
    return button
end

-- Name eines Gegenstands in seiner Qualitätsfarbe (ohne Qualität ungefärbt).
function ns.ColoredName(name, quality)
    if quality == nil then return name or "?" end
    return Core.QualityHex(quality) .. (name or "?") .. "|r"
end

function ns.Money(copper) return Core.Money(copper) end

-- Betrag in Kupfer als Gold-Zahl für „Als Text kopieren“ (V5): Weiterleitung an ezCores Core.GoldDecimal (Welle 26,
-- eine Stelle für ezLoot, ezPanel und ezAuction): 1 g 23 s 45 k → „1,2345“, immer vier Nachkommastellen; die Spalten
-- nehmen format = "money" von Core.TableText. Gesperrte Werte bleiben unverändert (das Kopierfeld schreibt „?“), fehlende nil.
function ns.GoldNumber(copper)
    if Core.IsSecret(copper) then return copper end
    return Core.GoldDecimal(copper)
end

---------------------------------------------------------------------------
-- Status und Slash-Befehle
---------------------------------------------------------------------------

-- Preis-Wissen von ezCore (nil, solange es fehlt): Get, Scan, ScanReadyIn, IsScanning …
function ns.Prices()
    local prices = Core.Prices
    return type(prices) == "table" and type(prices.Get) == "function" and prices or nil
end

-- Marktwert und Tiefstpreis eines Gegenstands aus dem Preis-Wissen: info = { min, market, quantity, seen } oder nil.
function ns.PriceInfo(item)
    local prices = ns.Prices()
    local info = prices and item and Core.Call(prices.Get, item)
    return type(info) == "table" and info or nil
end

-- Zeilen von „/eza status“ und vom Knopf „Status“ (ns.PrintStatus kommt vom Gerüst: Kopf ns.StatusHeader(), diese
-- Zeilen, eine Meldung von Core.Require). Die Befehle selbst (ns.HandleSlash, ns.PrintHelp, „/ezauction“, „/eza“)
-- setzt das Gerüst aus opts.slash oben.
ns.AddStatusLine(function()
    local lines = { L.STATUS_LISTS:format(#(ns.db and ns.db.lists or {})) }
    local posts = 0
    if ns.db then
        for _ in pairs(ns.RealmData().posts) do posts = posts + 1 end
    end
    lines[#lines + 1] = L.STATUS_POSTS:format(posts)
    lines[#lines + 1] = ns.ahReady and L.STATUS_AH_READY or L.STATUS_AH_WAIT
    lines[#lines + 1] = L.STATUS_PRICES:format(ns.Prices() and L.STATUS_PRICES_OK or L.STATUS_PRICES_MISSING)
    -- Neben einem fremden Auktionshaus-Addon: je Teil eine Zeile, dazu die Tooltip-Zeile (Beside.lua)
    for _, line in ipairs(ns.Beside.Lines()) do lines[#lines + 1] = line end
    -- Rücksicht je Teil mit Zähler (AH-31) und die Taste „Nächste unterbotene abbrechen“ (AH-40)
    for _, line in ipairs(Yield.Lines()) do lines[#lines + 1] = line end
    if ns.Undercut and ns.Undercut.KeyLine then lines[#lines + 1] = ns.Undercut.KeyLine() end
    local source = ns.History and ns.History.Source()
    if source then
        lines[#lines + 1] = L.STATUS_HISTORY:format(#source.List("auction"))
    else
        lines[#lines + 1] = L.STATUS_HISTORY_MISSING
    end
    return lines
end)
