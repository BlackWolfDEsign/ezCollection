local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Plunder verkaufen am Händlerfenster (V-121, W-23, MER-02; Frage 14 – Empfehlung umgesetzt, Antwort offen):
    Knopf „Plunder jetzt verkaufen“ und Schalter „Plunder automatisch verkaufen“ im Menü am Knopf „Filter“.
      - Läuft ezBag, gelten dessen Regeln (Markierungen, Schlösser, ezCrafts Einkaufsliste): der Knopf ruft
        ezCore.API("ezBag").SellJunk(), der Schalter liest und setzt ezBags Schalter autoSell über AutoSell() und
        SetAutoSell(an) (BAG-07) – ezMerchant schreibt nicht in ezBags Einstellungen und verkauft dann nicht selbst.
      - Ohne ezBag verkauft ezMerchant nur Graues mit Händlerwert über ezCores Dienst (Core.Junk.Sell: gedrosselte
        Runden, Abbruch beim Schließen, eine Meldung mit Einzahl und Mehrzahl im Namen von ezMerchant). Automatik:
        eigene Einstellung autoSellJunk (ab Werk aus), Shift beim Ansprechen des Händlers hält sie an.
    Rücksicht (Leitlinie 9): Verkauft schon ein anderes Addon Plunder automatisch (ns.OtherFor("sellJunk"): Leatrix
    Plus, Tweaks Forever, Forever++), läuft ezMerchants Automatik nicht; Tooltip und /ezh status nennen das Addon. Der
    Knopf verkauft weiter (von Hand). Eigentümer des Schlüssels sellJunk ist in ezCore das erste geladene Modul aus
    Core.FEATURE_OWNERS.sellJunk (ezBag, sonst ezMerchant).

    Auktionswert beim Händler (AH-27, Welle 14; Grundlage ezCore AH-13): Ob ein Gegenstand im Auktionshaus mehr
    bringt, rechnet nur ezCore (Core.Prices.WorthMark/AuctionWorth: Erlös nach Gebühr über der Schwelle, Preis höchstens
    7 Tage alt, an mindestens 2 Tagen gesehen, nie gesperrt oder gebunden). Die Goldmünze am Taschenplatz und ihre
    Tooltip-Zeile zeichnet ezCore selbst (beim Händler rückt die Münze vor) – ezMerchant fügt keine zweite hinzu.
      - Zeile unter dem Händlerfenster (Einstellung auctionWorth, ab Werk an): „n Gegenstände im Auktionshaus mehr
        wert“, die Maus darauf listet sie mit „Auktion nach Gebühr ≈ …, Händler zahlt …“, Quelle und Alter und nennt
        Blizzards Rückkauf (der einzelne Rechtsklick-Verkauf lässt sich nicht aufhalten). Ohne Preis keine Zeile.
      - Plunder-Verkauf (Einstellung keepAuctionWorth, ab Werk an; Frage AH-13 (1) – Empfehlung umgesetzt, Antwort
        offen): ezMerchant ruft Core.Junk.Sell mit skipAuctionWorth. Was der Dienst auslässt, nennt danach dieselbe
        Zeile („… – behalten“) mit dem Knopf „Trotzdem verkaufen“ (Rückfrage) und einmal der Chat – nie verkauft der
        Dienst still weniger. Mit ezBag ruft der Knopf ezBags SellJunk wie bisher; nur wenn etwas zu behalten ist,
        verkauft ezMerchant direkt über ezCores Dienst (dort gilt ezBags angemeldete Regel, Core.Junk.Rule).
        ezBags eigene Automatik verkauft weiter nach ezBags Schalter (Schnittstelle KeepAuctionWorth/ShowKept für ezBag).
]]

local J = {}
ns.Junk = J

J.AUTO_DELAY = 0.2   -- Sekunden nach MERCHANT_SHOW (wie ezBag): der Händler-Rahmen ist dann offen

-- ezBags Schnittstelle, wenn ezBag läuft und „Plunder verkaufen“ anbietet; sonst nil.
function J.BagAPI()
    local bag = Core.API("ezBag")
    if type(bag) == "table" and type(bag.SellJunk) == "function" then return bag end
    return nil
end

-- ezBags Schnittstelle, wenn sich sein Schalter autoSell lesen und setzen lässt; sonst nil.
function J.BagToggle()
    local bag = J.BagAPI()
    if bag and type(bag.AutoSell) == "function" and type(bag.SetAutoSell) == "function" then return bag end
    return nil
end

-- Verkauft schon ein anderes Addon Plunder automatisch? Dann dessen Name, sonst nil.
function J.Other()
    return (ns.OtherFor("sellJunk"))
end

-- Ist die Automatik an? Mit ezBag dessen Schalter, sonst die Einstellung autoSellJunk.
function J.AutoOn()
    local bag = J.BagToggle()
    if bag then
        local ok, on = pcall(bag.AutoSell)
        return ok and on == true
    end
    return ns.Enabled("autoSellJunk") == true
end

-- Automatik schalten: mit ezBag dessen Schalter (über seine Schnittstelle), sonst autoSellJunk. → neuer Wert
function J.SetAuto(on)
    local bag = J.BagToggle()
    if bag then
        local ok, now = pcall(bag.SetAutoSell, on and true or false)
        if not ok then
            ns.Error(now, "SetAutoSell (ezBag)")
            return J.AutoOn()
        end
        return now == true
    end
    ns.SetSetting("autoSellJunk", on and true or false)
    return ns.Enabled("autoSellJunk") == true
end

-- Plunder jetzt verkaufen (Knopf). → true, wenn der Verkauf beginnt
-- Mit und ohne ezBag dieselben Hinweise: ohne Händler SELL_JUNK_NEED_MERCHANT, ohne Plunder SELL_JUNK_NONE bzw.
-- SELL_JUNK_NONE_BAG. ezBags SellJunk schweigt in beiden Fällen (seine Meldung kommt nur, wenn etwas verkauft oder
-- geschützt wurde); die Vorschau liest deshalb Core.Junk.Collect – mit ezBag gilt dort dessen Regel.
function J.SellNow()
    local S = Core.Junk
    local bag = J.BagAPI()
    if not (type(S) == "table" and type(S.Sell) == "function") then
        if not bag then
            ns.Print(L.SELL_JUNK_UNAVAILABLE)
            return false
        end
        S = nil   -- ezCore ohne Dienst: nur ezBags SellJunk, ohne Vorschau
    end
    if S and not S.AtMerchant() then
        ns.Print(L.SELL_JUNK_NEED_MERCHANT)
        return false
    end
    if S and S.Selling() then return false end
    -- Im Kampf verkauft ezCore nichts (Prüfung auf Blizzards Regeln vom 17.11.2026, Risiko 11): der Klick bekommt
    -- ezCores Antwort im Chat statt Stille (Fund des code-reviewers, Welle 28); Satz über Core.CombatNotice (T18-1)
    if Core.InCombat() then
        Core.CombatNotice(ns, Core.L.JUNK_WHAT)
        return false
    end
    -- AH-27: mit keepAuctionWorth fragt die Vorschau nach dem, was der Dienst auslassen würde (kept)
    local preview = J.Keep() and { skipAuctionWorth = true } or nil
    if bag then
        if S and type(S.Collect) == "function" then
            local list, protected, kept = S.Collect(preview)
            local nKept = type(kept) == "table" and #kept or 0
            if type(list) == "table" and #list == 0 and (tonumber(protected) or 0) == 0 then
                if nKept > 0 then return J.KeptOnly(kept) end
                ns.Print(L.SELL_JUNK_NONE_BAG)
                return false
            end
            -- ezBags SellJunk kennt das Auslassen nicht: dann ezCores Dienst direkt (es gilt ezBags Regel)
            if nKept > 0 then return J.Start(S) end
        end
        local ok, started = pcall(bag.SellJunk)
        if not ok then
            ns.Error(started, "SellJunk (ezBag)")
            return false
        end
        return started == true
    end
    local list, _, kept = S.Collect(preview)
    if type(list) ~= "table" or #list == 0 then
        if type(kept) == "table" and #kept > 0 then return J.KeptOnly(kept) end
        ns.Print(L.SELL_JUNK_NONE)
        return false
    end
    return J.Start(S)
end

-- Automatisch beim Ansprechen des Händlers – nur ohne ezBag (sonst verkauft ezBag nach seinem Schalter), mit
-- autoSellJunk und ohne anderes Addon, das das schon tut. → true, wenn der Verkauf beginnt
function J.Auto()
    if J.BagAPI() or not ns.Enabled("autoSellJunk") or J.Other() then return false end
    local S = Core.Junk
    if not (type(S) == "table" and type(S.Sell) == "function") then return false end
    return J.Start(S)
end

ns.On("MERCHANT_SHOW", function()
    if J.BagAPI() or not ns.Enabled("autoSellJunk") or J.Other() then return end
    if IsShiftKeyDown() then return end   -- Shift beim Ansprechen hält an (wie in ezBag)
    C_Timer.After(J.AUTO_DELAY, function() ns.Try("AutoSellJunk", J.Auto) end)
end)

-- Hinweis am Händler (ezCores Hinweis-Helfer, einmal je Account; Antwort des Nutzers vom 17.11.2026: was ohne Klick
-- verkauft, ist ab Werk aus und bekommt einen Hinweis mit Knopf „Einschalten“). autoSellJunk war schon aus. Mit ezBag
-- schaltet ezMerchants Schalter ezBags autoSell – dann gilt ezBags Hinweis, dieser nur ohne ezBag; verkauft schon ein
-- anderes Addon Plunder, auch nicht. Mehrere Funktionen am Händler fasst ezCore in eine Blase.
function J.RegisterOptInHint()
    local Hint = Core.OptInHint
    if not (Hint and Hint.Register) then return false end
    return Hint.Register("ezMerchant.autoSellJunk", {
        owner = ADDON,
        window = "merchant",
        label = function() return L.OPT_autoSellJunk end,
        what = function() return L.OPTIN_autoSellJunk end,
        isOn = function() return ns.Enabled("autoSellJunk") == true end,
        enable = function()
            ns.SetSetting("autoSellJunk", true)
            return ns.Enabled("autoSellJunk") == true
        end,
        applies = function() return J.BagAPI() == nil and J.Other() == nil end,
    })
end
J.RegisterOptInHint()

---------------------------------------------------------------------------
-- Auktionswert beim Händler (AH-27): Zeile, Liste, „Trotzdem verkaufen“
---------------------------------------------------------------------------

J.LIST_MAX = 10         -- so viele Gegenstände nennt der Tooltip der Zeile, der Rest als „… und n weitere“
J.BAR_H = 22
J.BUTTON_W = 130
J.TEXT_MIN = 90         -- schmaler als das: nur der Knopf (sein Tooltip nennt die Zeile)
J.TABS_W = 200          -- Breite von Blizzards Reitern unter dem Fenster, wenn sie sich nicht messen lässt
J.UPDATE_DELAY = 0.3

local kept              -- nach einem Verkauf behaltene Gegenstände { { bag, slot, itemID, count } } oder nil
local worth = {}        -- Taschen-Gegenstände mit ezCores Goldmünze (für die Zeile vor dem Verkauf)
local bar
local visit = 0         -- Händlerbesuch: J.Clear zählt hoch, Ergebnisse älterer Besuche verfallen (J.Start/J.Done)

-- ezCores Rechnung (AH-13), wenn sie da ist; sonst nil (älteres ezCore: keine Zeile, kein Auslassen)
local function Prices()
    local P = Core.Prices
    if type(P) == "table" and type(P.AuctionWorth) == "function" and type(P.WorthMark) == "function" then return P end
    return nil
end
function J.WorthReady() return Prices() ~= nil end

-- Lässt ezMerchants Plunder-Verkauf Gegenstände mit der Goldmünze aus? (Einstellung keepAuctionWorth)
function J.Keep()
    return ns.Enabled("keepAuctionWorth") == true and Prices() ~= nil
end

-- Behaltene Gegenstände (Kopie der Liste, leer, wenn nichts behalten ist)
function J.Kept()
    local out = {}
    for i, e in ipairs(kept or {}) do out[i] = e end
    return out
end

local function Plural(n, one, many) return Core.Plural(n, one, many) end
local function KeptLine(n) return Plural(n, L.KEPT_LINE_ONE, L.KEPT_LINE_MANY) end

-- Merkt sich die behaltenen Gegenstände und zeigt die Zeile; der Chat nennt sie einmal je neuer Liste (quiet: nicht).
-- → true, wenn die Liste etwas enthielt
function J.SetKept(list, quiet)
    if type(list) ~= "table" or #list == 0 then
        kept = nil
        J.UpdateBar()
        return false
    end
    local fresh = kept == nil
    kept = list
    if fresh and not quiet then ns.Print(L.KEPT_CHAT:format(KeptLine(#list))) end
    J.UpdateBar()
    return true
end

-- Nichts zu verkaufen außer Behaltenem: kein stiller Klick, sondern Hinweis und Zeile mit „Trotzdem verkaufen“.
function J.KeptOnly(list)
    ns.Print(Plural(#list, L.KEPT_ONLY_ONE, L.KEPT_ONLY_MANY):format(#list))
    J.SetKept(list, true)
    return false
end

-- Ergebnis eines Verkaufs aus ezCore (onDone): die behaltenen Gegenstände (frisch gezählt, falls inzwischen etwas
-- einzeln verkauft wurde). ezCore meldet erst Junk.REPORT_DELAY nach dem Ende, auch wenn der Händler inzwischen zu
-- ist; dann ist das Behaltene schon vergessen (J.Clear) – keine zweite Chatzeile, keine Zeile beim nächsten Händler.
function J.Done(_, _, _, list)
    if not (MerchantFrame and MerchantFrame:IsShown()) then return end
    if type(list) == "table" then
        J.SetKept(list)
        J.RefreshKept()
        J.UpdateBar()
    end
end

-- Verkauf über ezCores Dienst im Namen von ezMerchant; mit keepAuctionWorth lässt er Wertvolles aus (skipAuctionWorth).
-- → true, wenn der Verkauf beginnt
function J.Start(S)
    S = S or Core.Junk
    local mine = visit
    local opts = { owner = ADDON, onDone = function(...) if mine == visit then return J.Done(...) end end }
    if J.Keep() then opts.skipAuctionWorth = true end
    local started, list = S.Sell(opts)
    if started and type(list) == "table" then J.SetKept(list) end
    return started == true
end

-- Behaltenes neu zählen (nach Taschenänderungen): was noch da ist und weiter als wertvoll gilt
function J.RefreshKept()
    if not kept then return end
    local S = Core.Junk
    if not (type(S) == "table" and type(S.Collect) == "function") or (S.Selling and S.Selling()) then return end
    local _, _, now = S.Collect({ skipAuctionWorth = true })
    if type(now) ~= "table" or #now == 0 then
        kept = nil
    else
        kept = now
    end
end

-- Taschen-Gegenstände mit ezCores Goldmünze (Einstellung auctionWorth; ezCores Schalter der Münze gilt mit)
function J.ScanWorth()
    worth = {}
    local P = Prices()
    if not (P and ns.Enabled("auctionWorth")) then return worth end
    Core.ForEachBagItem(function(bag, slot, info)
        local ok, yes = pcall(P.WorthMark, info.itemID, info.hyperlink, bag, slot)
        if ok and yes == true then
            worth[#worth + 1] = { bag = bag, slot = slot, itemID = info.itemID, count = ns.Num(info.stackCount) or 1 }
        end
    end, "sell")
    return worth
end

-- Was die Zeile zeigt: "kept" (nach dem Verkauf behalten), "worth" (Warnung vor dem Verkauf) oder nil, dazu die Liste
function J.BarState()
    if kept and #kept > 0 then return "kept", kept end
    if #worth > 0 then return "worth", worth end
    return nil, {}
end

-- Einträge für Tooltip und Rückfrage: Name bzw. Link, Anzahl, Werte des ganzen Stapels; der größte Verlust zuerst.
function J.Entries(list)
    local out = {}
    local P = Prices()
    for _, e in ipairs(list or {}) do
        local info = C_Container and Core.Call(C_Container.GetContainerItemInfo, e.bag, e.slot)
        if type(info) == "table" and not ns.IsSecret(info.itemID) and info.itemID == e.itemID then
            local link = info.hyperlink
            local count = ns.Num(info.stackCount) or ns.Num(e.count) or 1
            local w = P and P.AuctionWorth(link or e.itemID) or nil
            local vendor = w and w.vendor or Core.VendorPrice(link or e.itemID) or 0
            out[#out + 1] = { link = link or ("item:" .. e.itemID), itemID = e.itemID, count = count, worth = w,
                vendor = vendor * count, value = w and w.value * count or nil }
        end
    end
    table.sort(out, function(a, b)
        local la, lb = (a.value or a.vendor) - a.vendor, (b.value or b.vendor) - b.vendor
        if la ~= lb then return la > lb end
        return a.itemID < b.itemID
    end)
    return out
end

-- Zeile eines Eintrags: „Auktion nach Gebühr ≈ …, Händler zahlt … (an n Tagen gesehen, zuletzt vor …)“
function J.Detail(entry)
    local w = entry.worth
    if not w then return L.WORTH_DETAIL_VENDOR:format(Core.CoinText(entry.vendor)) end
    local days = Plural(ns.Num(w.days) or 0, L.WORTH_DAYS_ONE, L.WORTH_DAYS_MANY)
    return (w.gross and L.WORTH_DETAIL_GROSS or L.WORTH_DETAIL):format(Core.CoinText(entry.value),
        Core.CoinText(entry.vendor), days, Core.Ago(w.seen))
end

function J.SourceLine()
    local P = Prices()
    local pct = P and P.WorthPercent and P.WorthPercent() or 20
    return L.JUNK_WORTH_SOURCE:format(P and P.WORTH_DAYS or 7, P and P.WORTH_MIN_DAYS or 2, pct)
end

-- Tooltip der Zeile und des Knopfs (Leitlinie 11: Quelle und Alter je Angabe)
function J.FillTooltip(tip)
    local state, list = J.BarState()
    if not state then return false end
    local n = #list
    -- Rollen statt Farbzahlen (T9-6): Titel weiß, Gegenstände weiß, Angaben gold, Quelle und Hinweise grau
    Core.TipTitle(tip, state == "kept" and KeptLine(n) or Plural(n, L.WORTH_LINE_ONE, L.WORTH_LINE_MANY))
    if state == "kept" then Core.TipLine(tip, L.KEPT_TIP, "highlight", true) end
    local entries = J.Entries(list)
    for i, entry in ipairs(entries) do
        if i > J.LIST_MAX then
            Core.TipLine(tip, Core.More(#entries - J.LIST_MAX), "hint")
            break
        end
        Core.TipLine(tip, L.WORTH_ITEM:format(entry.link, entry.count), "highlight")
        Core.TipText(tip, J.Detail(entry))
    end
    Core.TipLine(tip, J.SourceLine(), "hint", true)
    Core.TipLine(tip, L.WORTH_BUYBACK, "hint", true)
    if state == "kept" then Core.TipLine(tip, L.KEPT_SELL_ANYWAY_TIP, "hint", true) end
    return true
end

local function ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    if J.FillTooltip(GameTooltip) then GameTooltip:Show() else GameTooltip:Hide() end
end

-- Rechte Kante von Blizzards Reitern unter dem Fenster, gemessen ab dessen linkem Rand
local function TabsWidth()
    local left = MerchantFrame.GetLeft and ns.Num(MerchantFrame:GetLeft())
    local right
    for i = 1, 4 do
        local tab = rawget(_G, "MerchantFrameTab" .. i)
        if type(tab) == "table" and tab.IsShown and tab:IsShown() and tab.GetRight then
            local r = ns.Num(tab:GetRight())
            if r and (not right or r > right) then right = r end
        end
    end
    if left and right and right > left then return right - left end
    return J.TABS_W
end

function J.CreateBar()
    if bar or not MerchantFrame then return bar end
    -- Ein Streifen unter Blizzards Händlerfenster rechts neben den Reitern, als Kind des Fensters (wandert mit,
    -- schließt mit ihm); eigene Texturen gibt es keine, nur Blizzards Schrift und Knopf-Vorlage.
    bar = CreateFrame("Frame", "ezMerchantWorthBar", MerchantFrame)
    bar:SetHeight(J.BAR_H)
    bar:EnableMouse(true)
    bar.text = bar:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    bar.text:SetJustifyH("RIGHT")
    bar.text:SetWordWrap(false)
    local ok, button = pcall(CreateFrame, "Button", "ezMerchantSellAnywayButton", bar, "UIPanelButtonTemplate")
    if ok and button then
        bar.button = button
        button:SetSize(J.BUTTON_W, J.BAR_H)
        button:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
        button:SetText(L.KEPT_SELL_ANYWAY)
        button:SetScript("OnClick", function() ns.Try("SellAnyway", J.AskSellAnyway) end)
        button:SetScript("OnEnter", ShowTooltip)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    bar:SetScript("OnEnter", ShowTooltip)
    bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
    bar:Hide()
    J.bar = bar
    return bar
end

-- Zeile zeigen oder verstecken (ohne Liste keine leere Zeile)
function J.UpdateBar()
    if not bar then return end
    local state, list = J.BarState()
    if not (state and MerchantFrame and MerchantFrame:IsShown()) then
        bar:Hide()
        return
    end
    local width = ns.Num(MerchantFrame:GetWidth()) or 336
    local room = math.max(J.BUTTON_W, width - TabsWidth() - 12)
    bar:ClearAllPoints()
    bar:SetPoint("TOPRIGHT", MerchantFrame, "BOTTOMRIGHT", -4, -2)
    bar:SetWidth(room)
    local withButton = state == "kept" and bar.button ~= nil
    if bar.button then bar.button:SetShown(withButton) end
    local textRoom = withButton and room - J.BUTTON_W - 6 or room
    bar.text:ClearAllPoints()
    bar.text:SetPoint("LEFT", bar, "LEFT", 0, 0)
    bar.text:SetPoint("RIGHT", bar, "RIGHT", withButton and -(J.BUTTON_W + 6) or 0, 0)
    bar.text:SetText(state == "kept" and KeptLine(#list) or Plural(#list, L.WORTH_LINE_ONE, L.WORTH_LINE_MANY))
    -- schmales Fenster (2 Spalten): kurzer Text statt abgeschnittenem, der Tooltip nennt den langen
    local wide = bar.text.GetStringWidth and ns.Num(bar.text:GetStringWidth()) or 0
    if wide > textRoom then
        bar.text:SetText((state == "kept" and L.KEPT_SHORT or L.WORTH_SHORT):format(#list))
    end
    bar.text:SetShown(textRoom >= J.TEXT_MIN)
    bar:Show()
end

-- Zählen und zeigen (gedrosselt: Taschen und Preise ändern sich beim Händler oft)
-- Händler zu: Behaltenes und Warnung vergessen (beim nächsten Händler wird neu gezählt)
function J.Clear()
    visit = visit + 1
    kept = nil
    worth = {}
    if bar then bar:Hide() end
end

function J.Refresh()
    if not (MerchantFrame and MerchantFrame:IsShown()) then return J.Clear() end
    J.RefreshKept()
    J.ScanWorth()
    J.UpdateBar()
end
local RefreshSoon = ns.Throttle(function() ns.Try("AuctionWorth", J.Refresh) end, J.UPDATE_DELAY)
J.RefreshSoon = RefreshSoon

-- „Trotzdem verkaufen“: Rückfrage mit Zahl, Händlerpreis und Auktionswert; erst „Ja“ verkauft.
function J.AskSellAnyway()
    J.Refresh()
    if not kept then
        ns.Print(L.KEPT_NONE)
        return false
    end
    local vendor, value = 0, 0
    for _, entry in ipairs(J.Entries(kept)) do
        vendor = vendor + entry.vendor
        value = value + (entry.value or entry.vendor)
    end
    Core.Confirm(Plural(#kept, L.KEPT_CONFIRM_ONE, L.KEPT_CONFIRM_MANY):format(#kept,
        Core.CoinText(vendor), Core.CoinText(value)), function() ns.Try("SellAnyway", J.SellAnyway) end)
    return true
end

-- Nach „Ja“: Plunder ohne Auslassen verkaufen (ezCores Dienst; mit ezBag gilt dessen Regel). → true, wenn er beginnt
function J.SellAnyway()
    local S = Core.Junk
    if not (type(S) == "table" and type(S.Sell) == "function") then
        ns.Print(L.SELL_JUNK_UNAVAILABLE)
        return false
    end
    if not S.AtMerchant() then
        ns.Print(L.SELL_JUNK_NEED_MERCHANT)
        return false
    end
    if S.Selling() then return false end
    -- Im Kampf verkauft ezCore nichts (Risiko 11): Meldung wie bei J.SellNow, und das Behaltene bleibt samt Zeile und
    -- Knopf stehen – darum vor „kept = nil“ (Gegenprüfung der Funde, Welle 28)
    if Core.InCombat() then
        Core.CombatNotice(ns, Core.L.JUNK_WHAT)
        return false
    end
    kept = nil
    J.UpdateBar()
    return S.Sell({ owner = ADDON, onDone = function() RefreshSoon() end }) == true
end

ns.API.KeepAuctionWorth = function() return J.Keep() end
ns.API.ShowKept = function(list) return J.SetKept(list) end

ns.OnReady(function()
    ns.Try("AuctionWorth", J.CreateBar)
    -- nach einem automatischen Verkauf (J.AUTO_DELAY) zählen
    ns.On("MERCHANT_SHOW", function() C_Timer.After(J.AUTO_DELAY + 0.1, function() RefreshSoon() end) end)
    ns.On("MERCHANT_CLOSED", function() J.Clear() end)
    ns.On("BAG_UPDATE_DELAYED", function() if MerchantFrame and MerchantFrame:IsShown() then RefreshSoon() end end)
    ns.Listen("MERCHANT_LAYOUT", function() J.UpdateBar() end)
    Core.Listen("PRICES_CHANGED", function() if bar and MerchantFrame:IsShown() then RefreshSoon() end end, ADDON)
end)

local WORTH_KEYS = { auctionWorth = true, keepAuctionWorth = true, columns = true }
ns.OnSettingChanged(function(key) if WORTH_KEYS[key] then RefreshSoon() end end)

---------------------------------------------------------------------------
-- Menü am Knopf „Filter“ (Merchant.lua ruft J.BuildMenu) und Status
---------------------------------------------------------------------------

-- Was der Knopf verkauft – und nach wessen Regeln (Leitlinie 11: jede Angabe nennt ihre Quelle).
function J.SellTip()
    return J.BagAPI() and L.SELL_JUNK_TIP_BAG or L.SELL_JUNK_TIP_GREY
end

function J.AutoTip()
    local text = J.BagToggle() and L.AUTO_SELL_TIP_BAG or L.OPT_autoSellJunk_TIP
    local other = J.Other()
    if other then
        text = text .. "\n\n" .. (J.BagToggle() and L.SELL_JUNK_OTHER_BAG or L.SELL_JUNK_OTHER):format(other)
    end
    return text
end

function J.BuildMenu(root)
    local Menu = Core.Menu
    Menu.Title(root, L.MENU_JUNK)
    Menu.Tip(Menu.Button(root, L.MENU_SELL_JUNK, function() ns.Try("SellJunk", J.SellNow) end), L.MENU_SELL_JUNK, J.SellTip())
    -- Ein ezBag ohne lesbaren Schalter: kein Schalter hier (sonst verkauften ezBag und ezMerchant beide)
    if not (J.BagAPI() and not J.BagToggle()) then
        Menu.Tip(Menu.Toggle(root, L.MENU_AUTO_SELL, J.AutoOn, function(value) J.SetAuto(value) end), L.MENU_AUTO_SELL, J.AutoTip())
    end
    -- AH-27: Auslassen beim Verkauf (dieselbe Einstellung wie auf der Einstellungsseite) und, solange etwas behalten
    -- ist, „Trotzdem verkaufen“ (auch als Knopf unter dem Händlerfenster)
    if J.WorthReady() then
        Menu.Tip(Menu.Toggle(root, L.MENU_KEEP_WORTH, function() return ns.Enabled("keepAuctionWorth") end,
            function(value) ns.SetSetting("keepAuctionWorth", value and true or false) end),
            L.MENU_KEEP_WORTH, L.OPT_keepAuctionWorth_TIP)
    end
    local kept = J.Kept()
    if #kept > 0 then
        Menu.Tip(Menu.Button(root, L.KEPT_SELL_ANYWAY, function() ns.Try("SellAnyway", J.AskSellAnyway) end),
            L.KEPT_SELL_ANYWAY, L.KEPT_SELL_ANYWAY_TIP)
    end
end

ns.AddStatusLine(function()
    if J.BagAPI() then
        -- ezBag ohne lesbaren Schalter: über dessen Automatik nichts behaupten (J.AutoOn läse sonst autoSellJunk)
        if not J.BagToggle() then return L.STATUS_JUNK_BAG_RULES end
        return J.AutoOn() and L.STATUS_JUNK_BAG_ON or L.STATUS_JUNK_BAG_OFF
    end
    if not ns.Enabled("autoSellJunk") then return L.STATUS_JUNK_OFF end
    local other = J.Other()
    if other then return L.SELL_JUNK_OTHER:format(other) end
    return L.STATUS_JUNK_ON
end)

ns.AddStatusLine(function()
    if not J.WorthReady() then return L.STATUS_WORTH_NONE end
    return L.STATUS_WORTH:format(ns.Enabled("auctionWorth") and L.ON or L.OFF,
        ns.Enabled("keepAuctionWorth") and L.STATUS_KEEP_ON or L.STATUS_KEEP_OFF)
end)
