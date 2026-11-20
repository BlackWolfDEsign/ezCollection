local ADDON, ns = ...
local L = ns.L
local Core = ezCore

-- Einstellungen unter Esc → Optionen → AddOns → ezCollection → ezAuction (Seite von ezCore):
-- „Allgemein“ → Kaufen → Markt → Verkaufen → Auktionen → Preise → Rücksicht auf fremde Addons → „Erweitert“
-- (Zurücksetzen, Erklärung, Status, ergänzende Addons).
-- Läuft beim Anmelden ein fremdes Auktionshaus-Addon (Auctionator), steht unter „Allgemein“ die Zeile „Neben
-- Auctionator“, und die Tooltips der Teile, die es dort noch einmal gibt, sagen, wie sie sich daneben verhalten
-- (Beside.lua; ns.Beside.Tip gibt nil ohne fremdes Addon – dann gilt der Text der Einstellung allein).
local page

-- Alle Standardwerte stehen in ns.DEFAULTS (Core.lua); die acht aus Welle 12 sind in Welle 13 dorthin umgezogen.

-- Zeile „Neben Auctionator“ auf der Seite target: der Knopf schreibt alle Sätze samt dem Stand der Tooltip-Zeile
-- in den Chat. Ihr Tooltip ist ein fester Text (Blizzards Seite legt ihn einmal an): Kopfzeile, je Teil ein Satz
-- und der Verweis auf den Knopf – der Stand der Schalter steht dort nicht, er wäre nach dem ersten Klick veraltet.
-- Nur wenn ein fremdes Auktionshaus-Addon läuft. Rückgabe: die Zeile oder nil.
function ns.BesideRow(target)
    local other = ns.Beside.Running()
    if not (target and other) then return nil end
    return target:Button(L.BESIDE_LABEL:format(other), L.OPT_STATUS_BUTTON, function() ns.Beside.Print() end,
        table.concat(ns.Beside.PartLines(), "\n") .. "\n\n" .. L.BESIDE_ROW_STATE:format(L.OPT_HEADER_PRICES, L.OPT_STATUS_BUTTON))
end

-- Inhalt der Seite, in der Reihenfolge der Anzeige. Eigene Funktion, damit eine Prüfung ihn mit laufendem
-- Auctionator auf eine zweite Seite legen kann (im Testlauf wie im Spiel wird die Seite sonst nur einmal beim
-- Anmelden gefüllt).
function ns.FillSettings(target)
    ns.BesideRow(target)

    target:Header(L.OPT_HEADER_BUY)
    target:Checkbox("shoppingLists", ns.Beside.Tip("shoppingLists"))
    target:Checkbox("vendorMark")
    target:Checkbox("marketCompare")
    target:Checkbox("upgradeArrow")
    -- „Nur Verbesserungen“ steht seit der Einstellungs-Prüfung vom 19.11.2026 nur als Häkchen am Auktionsfenster
    -- (Upgrade.lua); Filter und Höchstpreis der Listen, Bestand und Stückpreis sind immer an
    target:Checkbox("recentSearches")
    target:Checkbox("rowSearch")
    target:Checkbox("listCost")
    -- Welle 14 (AH-22 bis AH-24): Schnäppchen, Beobachtet, Kaufbereich – jede Stelle einzeln abschaltbar
    target:Checkbox("bargainList")
    target:Checkbox("watchList")
    target:Checkbox("watchAlert", nil, { parent = "watchList" })   -- Lists.lua: nur mit Beobachtungsliste (Querschnitt „Unterschalter ausgrauen“, Einstellungs-Prüfung 19.11.2026)
    target:Checkbox("buyNeed")
    target:Checkbox("buySetQuantity")
    target:Checkbox("buyNextMark")
    target:Checkbox("buyNextSelect")

    target:Header(L.OPT_HEADER_MARKET)
    target:Checkbox("marketPanel")
    target:Checkbox("marketHint")
    -- „Schnäppchen ab“ wirkt beim Kaufen und beim Verkaufen (Warnung am Preisfeld) – darum neben dem Kauf- und
    -- Verkaufshinweis (Einstellungs-Prüfung vom 19.11.2026; vorher unter „Kaufen“)
    target:Slider("bargainPercent", 5, 60, 5, function(value) return Core.Percent(value) end)
    target:Checkbox("salvageCompare")

    target:Header(L.OPT_HEADER_SELL)
    target:Checkbox("sellList", ns.Beside.Tip("sellList"))
    target:Dropdown("sellListSide", { { "auto", L.SIDE_auto }, { "left", L.SIDE_left }, { "right", L.SIDE_right } })
    target:Dropdown("priceRule", { { "blizzard", L.RULE_blizzard }, { "undercut", L.RULE_undercut },
        { "percent", L.RULE_PERCENT_OPTION } })
    -- nur bei der Preisregel „Prozent“, Bereich 1 bis 25 % (Einstellungs-Prüfung vom 19.11.2026, Abschnitt 4)
    local _, percentRow = target:Slider("undercutPercent", 1, ns.UNDERCUT_PERCENT_MAX, 1,
        function(value) return Core.Percent(value) end)
    if percentRow and percentRow.AddShownPredicate then
        percentRow:AddShownPredicate(function() return ns.S ~= nil and ns.S.priceRule == "percent" end)
    end
    target:Checkbox("neverBelowVendor")
    target:Checkbox("floorTrend")
    target:Checkbox("rememberPost")
    -- Welle 13 (AH-18 bis AH-20, AH-38). „Nur vorschlagen“ und „den nächsten einlegen“ wirken erst, wenn Blizzard das
    -- Eintragen erlaubt (Tor T1 „geht“, ns.SellSetsValues) – erst dann stehen sie auf der Seite (Einstellungs-Prüfung
    -- vom 19.11.2026, Abschnitt 4); die Netto-Zeile ist immer an
    target:Checkbox("suggestOnly", nil, { shown = ns.SellSetsValues })
    target:Checkbox("priceWarn")
    target:Checkbox("nextItem")
    target:Checkbox("postNext", nil, { shown = ns.SellSetsValues })
    target:Checkbox("postDefaults")
    target:Slider("bidPercent", 0, 95, 5, function(value)
        return value > 0 and Core.Percent(value) or L.OPT_bidPercent_OFF
    end)
    -- Welle 15 (AH-28 bis AH-30): Auktionspost, Verkaufsempfehlung, Taschenliste ordnen
    target:Checkbox("auctionMail")
    target:Checkbox("sellAdvice")
    -- „Gesperrtes ausblenden“ schaltet der Schloss-Knopf an der Taschenliste (SellTab.lua; Einstellungs-Prüfung vom
    -- 19.11.2026: von der Seite genommen)
    target:Checkbox("sellPins")
    target:Checkbox("sellOtherChars")

    target:Header(L.OPT_HEADER_AUCTIONS)
    target:Checkbox("undercutCheck")
    target:Checkbox("cancelButton", ns.Beside.Tip("cancelButton"))
    target:Checkbox("auctionSum")
    target:Checkbox("rivalsButton")
    target:Checkbox("historyTab")
    -- AH-40: Taste „Nächste unterbotene abbrechen“ (ezCores Tasten-Dienst; ab Werk keine)
    target:Button(L.KEY_CANCEL_UNDERCUT, L.KEY_WINDOW_BUTTON, function() ns.Undercut.AskKey() end, L.OPT_KEY_CANCEL_TIP)

    target:Header(L.OPT_HEADER_PRICES)
    target:Checkbox("tooltipPrice")
    -- nur, solange ein anderes Addon Auktionspreise in den Tooltip schreibt (Einstellungs-Prüfung vom 19.11.2026,
    -- Nr. 61: der eine Weg, den Knopf „Trotzdem zeigen“ gibt es nicht mehr); Stapelpreis mit Umschalt ist immer an
    target:Checkbox("tooltipBeside", nil, { shown = function() return ns.Yield.OtherFor("tooltip") ~= nil end })
    target:Checkbox("tooltipStackHint")
    -- Welle 13 (AH-16, AH-17, AH-37): Erfassen
    target:Checkbox("scanCoverage")
    target:Checkbox("scanOnOpen")
    target:Slider("scanOnOpenHours", 1, 24, 1, function(value) return Core.Hours(value) end, nil,
        { parent = "scanOnOpen" })   -- Prices.lua: Abstand nur für das Erfassen beim Öffnen (Querschnitt „Unterschalter ausgrauen“, Einstellungs-Prüfung 19.11.2026)
    target:Checkbox("restoreView")
    target:Button(L.OPT_SCAN, L.OPT_SCAN_BUTTON, function() ns.Scan.Start() end,
        ns.Beside.Tip("scan", L.OPT_SCAN_TIP) or L.OPT_SCAN_TIP)

    -- Rücksicht je Teil (AH-31): je Teil mit eigener Handlung (force) ein Knopf („Trotzdem erfassen“); die Tooltip-Zeile
    -- hat dafür das Häkchen „Auch neben anderen Auktions-Addons zeigen“ oben. Wie oft und welchem Addon ein Teil
    -- gewichen ist, nennt der Knopf „Stand“ (die Zeilen von /eza status) – Blizzards Seite legt Texte nur einmal an, ein
    -- Zähler darin wäre sofort veraltet.
    target:Header(L.OPT_HEADER_YIELD, L.OPT_HEADER_YIELD_TIP)
    target:Checkbox("besideNotice")
    for _, part in ipairs(ns.Yield.PARTS) do
        local key = part.key
        if type(part.force) == "function" then
            target:Button(L["YIELD_PART_" .. key], L["YIELD_FORCE_" .. key], function() ns.Yield.Force(key) end,
                L["YIELD_PART_" .. key .. "_TIP"] .. "\n\n" .. L.YIELD_ROW_STATE:format(L.OPT_STATUS_BUTTON))
        end
    end
    target:Button(L.YIELD_STATUS_LABEL, L.OPT_STATUS_BUTTON, function() ns.Yield.Print() end, L.YIELD_STATUS_TIP)

    target:Advanced()
    target:Button(L.OPT_FORGET, L.OPT_FORGET_BUTTON, function()
        Core.Confirm(L.OPT_FORGET_CONFIRM, function()
            ns.ForgetPosts()
            ns.Print(L.OPT_FORGET_DONE)
        end)
    end, L.OPT_FORGET_TIP)
    target:ResetButton({ tip = L.OPT_RESET_TIP })
    target:TourButton(ns.Tour.Get(), L.OPT_TOUR_TIP)
    target:StatusButton(L.OPT_STATUS_TIP)
    -- Sichtbarer Weg zu „/eza listen“ und „/eza verlauf“ (Leitlinie 3, Vollprüfung V-166)
    target:Button(L.OPT_LISTS_PRINT, L.OPT_STATUS_BUTTON, function() ns.Lists.PrintAll() end, L.OPT_LISTS_PRINT_TIP)
    target:Button(L.OPT_HISTORY_PRINT, L.OPT_STATUS_BUTTON, function() ns.History.PrintSummary() end, L.OPT_HISTORY_PRINT_TIP)
    target:Companions()
end

local function Register()
    if page then return end
    page = Core.NewSettingsPage(ns)
    if not page then return end
    ns.FillSettings(page)
    page:Register()
end

ns.OnReady(function() ns.Try("Settings", Register) end)

-- Einstellungsseite öffnen – über ezCores Fenster-Dienst (Core.OpenPanel("settings", Kategorie)): im Kampf
-- erscheint dessen Hinweis statt eines gesperrten Aufrufs. Rückgabe: true, wenn geöffnet oder der Hinweis
-- gezeigt wurde; false, wenn es die Seite nicht gibt (dann zeigt der Aufrufer die Hilfe).
function ns.OpenSettings()
    if page == nil then return false end
    if type(Core.OpenPanel) == "function" and page.category then
        local ok, reason = Core.OpenPanel("settings", page.category)
        if ok or reason == "combat" then return true end
    end
    return page:Open()
end

-- Eintrag im Addon-Fach an der Minikarte (## AddonCompartmentFunc, …OnEnter, …OnLeave in der .toc). Entscheidung 5
-- vom 18.11.2026 (T18-3, T16-10): ezAuction hat außerhalb des Auktionshauses kein Fenster, darum ohne Hauptfunktion –
-- jeder Klick öffnet die Einstellungen (ohne Seite die Hilfe). Tooltip und Befehlszeile baut ezCore; ein Fehler im
-- Klick landet in /ez fehler.
ezAuction_OnAddonCompartmentClick, ezAuction_OnAddonCompartmentEnter, ezAuction_OnAddonCompartmentLeave =
    Core.CompartmentHandlers({ ns = ns, title = L.TITLE, owner = ADDON })
-- früherer Name des Klicks: dieselbe Belegung wie das Addon-Fach
function ns.CompartmentClick(button) return ezAuction_OnAddonCompartmentClick(nil, button) end

---------------------------------------------------------------------------
-- Zahnrad im Auktionsfenster: der sichtbare Weg zu Einstellungen, Listen, Verlauf und Status
-- (Vollprüfung V-164, V-166). Steht unter „Preise erfassen“ rechts neben dessen Pfeil in den Reitern Kaufen und
-- Verkaufen; seit Welle 14 dasselbe Zahnrad auch im Reiter Auktionen rechts neben den Unter-Reitern (AUC-14). Lage
-- nach dem Spielbefund vom 16.11.2026 in ns.Layout (Core.lua).
---------------------------------------------------------------------------

local Gear = {}
ns.Gear = Gear
local gear, auctionsGear

-- Einträge des Menüs: { Text, Funktion } – eine Liste für das Menü und für Prüfungen. Der erste ist „Einstellungen …“
-- aus ezCore (settings = true: im Menü Core.Menu.Settings mit Zahnrad und Tooltip; T18-8).
function Gear.Entries()
    return {
        { Core.L.MENU_OWN_SETTINGS, function() if not ns.OpenSettings() then ns.PrintHelp() end end, settings = true },
        { L.OPT_LISTS_PRINT, function() ns.Lists.PrintAll() end },
        { L.OPT_HISTORY_PRINT, function() ns.History.PrintSummary() end },
        { L.GEAR_STATUS, function() ns.PrintStatus() end },
        -- AH-12: die gezeigten Ergebnisse als kopierbarer Text (BuyTab.lua)
        { L.GEAR_RESULTS_TEXT, function() ns.Buy.ShowResultsText() end },
        -- AH-31: Rücksicht je Teil (wem ezAuction weicht, wie oft) – Ziel der Erklärblase am Zahnrad
        { L.GEAR_YIELDS, function() ns.Yield.Print() end },
    }
end

function Gear.Click(owner)
    local entries = Gear.Entries()
    local opened = Core.Menu.Open(owner, function(root)
        Core.Menu.Title(root, L.TITLE)
        for _, entry in ipairs(entries) do
            if entry.settings then Core.Menu.Settings(root, ns) else Core.Menu.Button(root, entry[1], entry[2]) end
        end
    end)
    -- Ohne Menü: gleich die Einstellungen.
    if not opened then entries[1][2]() end
end

function Gear.Update()
    local mode = ns.ModeName()
    if gear then gear:SetShown(ns.AuctionHouseShown() and (mode == "buy" or mode == "sell")) end
    if auctionsGear then auctionsGear:SetShown(ns.AuctionHouseShown() and mode == "auctions") end
end

-- Zahnrad, solange zu sehen (für Prüfungen).
function Gear.Button()
    return gear ~= nil and gear:IsVisible() and gear or nil
end

-- Zahnrad im Reiter Auktionen (AUC-14), solange zu sehen.
function Gear.AuctionsButton()
    return auctionsGear ~= nil and auctionsGear:IsVisible() and auctionsGear or nil
end

-- Lage im Reiter Auktionen: rechts neben dem Unter-Reiter „Verlauf“, solange er zu sehen ist (History.lua baut ihn mit
-- dem Schalter historyTab, auch erst später, an die Stelle rechts neben Blizzards „Gebote“), sonst neben „Gebote“.
-- Rückgabe: der Anker (für Prüfungen) oder nil.
function Gear.AnchorAuctions()
    if not auctionsGear then return nil end
    local auctions = AuctionHouseFrame and AuctionHouseFrame.AuctionsFrame
    local history = _G.ezAuctionHistoryTab
    local anchor = (history and history:IsShown() and history) or (auctions and auctions.BidsTab) or nil
    auctionsGear:ClearAllPoints()
    if anchor then
        -- Abstand und Höhe aus ns.Layout.TAB_GEAR: auf der Höhe der Reiter-Schrift statt dicht am Reiter (Spielbefund
        -- 16.11.2026)
        local G = ns.Layout.TAB_GEAR
        auctionsGear:SetPoint("LEFT", anchor, "RIGHT", G.x, G.y)
    else
        auctionsGear:SetPoint("TOPRIGHT", auctions or AuctionHouseFrame, "TOPRIGHT", -8, -4)
    end
    return anchor
end

-- Ein Zahnrad aus ezCore (Core.Toolbar.GearButton: Symbol aus einer Quelle, Core.Menu.ICON_SETTINGS; T9-9), gleiches
-- Menü und gleicher Tooltip. Kleiner Knopf wie der Pfeil daneben (Design-System 2.2; bis Welle 27 20). Der Name bleibt
-- als globaler Verweis (_G[name]) für die Lage-Prüfungen und andere Teile, die ihn suchen.
local function NewGear(name, parent)
    local button = Core.Toolbar.GearButton(parent, function(self) Gear.Click(self) end, L.GEAR_TITLE, L.GEAR_TIP,
        { size = ns.Layout.SMALL })
    _G[name] = button
    button:Hide()
    return button
end

ns.OnAuctionHouse(function()
    gear = NewGear("ezAuctionGearButton", AuctionHouseFrame)
    -- rechts neben dem Pfeil unter dem Knopf „Preise erfassen“ (AH-16; Lage seit dem Spielbefund vom 16.11.2026 in
    -- ns.Layout); ohne Pfeil an derselben Stelle (bis Welle 27 bei x = 170 – über Blizzards Favoriten-Knopf)
    local Layout = ns.Layout
    local scan = _G.ezAuctionScanMenuButton
    if scan then
        gear:SetPoint("LEFT", scan, "RIGHT", Layout.GAP, 0)
    else
        local S = Layout.SCAN
        gear:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPLEFT", S.x + Layout.SMALL + Layout.GAP, S.y - S.h - Layout.ROW_GAP)
    end
    -- Reiter Auktionen: rechts neben dem Unter-Reiter „Verlauf“ (History.lua), ohne ihn neben Blizzards „Gebote“
    local auctions = AuctionHouseFrame.AuctionsFrame
    if auctions then
        auctionsGear = NewGear("ezAuctionAuctionsGearButton", auctions)
        Gear.AnchorAuctions()
    end
    Gear.Update()
end)
ns.Listen("AH_MODE", Gear.Update)
ns.Listen("AH_SHOW", Gear.Update)
-- „Verlauf“ an oder aus (History.lua lädt vorher und baut bzw. verbirgt den Reiter zuerst): das Zahnrad rückt nach
ns.OnSettingChanged(function(key) if key == "historyTab" then Gear.AnchorAuctions() end end)
