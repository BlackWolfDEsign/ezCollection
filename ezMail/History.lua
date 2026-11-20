local _, ns = ...
local L = ns.L
local Menu = ezCore.Menu     -- Menüs an einer Stelle (Blizzards MenuUtil)

--[[
    Verlauf und Statistik: Seitenreiter (Schriftrolle) rechts am Posteingang, unter der Lupe. Rechts auf
    „Verschicken“ stehen schon die Reiter fürs Schnellanhängen.
    Die Daten zeichnet ezCore auf (ezCore.History, Arten „mail“ und „auction“). ezMail zeigt sie nur an;
    ezPanel und ezAuction lesen dieselbe Quelle.
    Das Menü zeigt:
      * Zeitraum (heute, 7 Tage, 30 Tage, gesamt) und Charaktere (dieser oder alle) zur Auswahl,
      * die Summen: per Post erhalten (davon Auktionshaus) und verschickt, verkauft netto mit Gebühren,
        gekauft, zurückgekommen,
      * die letzten Einträge je Liste: Eingang, Ausgang, Auktionen.
    /ezm statistik schreibt die Summen in den Chat.
]]

local History = {}
ns.History = History

-- Zeiträume und ihre Namen: eine Liste in ezCore für ezMail, ezAuction und ezPanel (V-061)
History.PERIODS = ezCore.History.PERIODS
History.LIMIT = 40          -- Einträge je Liste im Menü

local tab

local function Source()
    local H = ezCore.History
    return type(H) == "table" and type(H.List) == "function" and H or nil
end

local function Num(v) return ezCore.Num(v) or 0 end

function History.Period()
    local key = ns.db and ns.db.historyPeriod
    for _, k in ipairs(History.PERIODS) do if k == key then return key end end
    return "week"
end

function History.SetPeriod(key) ns.db.historyPeriod = key end
function History.AllChars() return ns.db ~= nil and ns.db.historyAll == true end
function History.SetAllChars(on) ns.db.historyAll = on and true or nil end

-- Beginn des Zeitraums (time()), nil für „gesamt“ – gerechnet von ezCore (eine Regel für alle Module).
function History.Since(period)
    local H = Source()
    return H and H.Since and H.Since(period or History.Period()) or nil
end

local function Filter(since, limit)
    return { char = not History.AllChars() and ns.charKey or nil, since = since, limit = limit }
end

-- Gibt es für diese Auswahl der Charaktere überhaupt schon Einträge?
function History.Any()
    local H = Source()
    if not H then return false end
    return #H.List("mail", Filter(nil, 1)) > 0 or #H.List("auction", Filter(nil, 1)) > 0
end

-- Summen eines Zeitraums und die Listen dazu (neueste zuerst): stats, eingang, ausgang, auktionen.
function History.Stats(period)
    local s = { mailIn = 0, inCount = 0, mailOut = 0, letters = 0, ahIn = 0,
        sold = 0, net = 0, fees = 0, bought = 0, spent = 0, back = 0 }
    local ins, outs, auctions = {}, {}, {}
    local H = Source()
    if not H then return s, ins, outs, auctions end
    local since = History.Since(period)
    for _, e in ipairs(H.List("mail", Filter(since))) do
        if e.dir == "out" then
            outs[#outs + 1] = e
            s.mailOut = s.mailOut + Num(e.money)
            s.letters = s.letters + 1
        else
            ins[#ins + 1] = e
            s.mailIn = s.mailIn + Num(e.money)
            s.inCount = s.inCount + 1
        end
    end
    auctions = H.List("auction", Filter(since))
    -- Summen der Auktionen rechnet ezCore (eine Rechnung für ezAuction, ezMail und ezPanel); ahIn = Gold aus
    -- dem Auktionshaus, das per Post kommt (Verkäufe netto und überbotene Gebote).
    local t = H.AuctionTotals(Filter(since))
    s.sold, s.net, s.fees = Num(t.sale), Num(t.income), Num(t.fees)
    s.bought, s.spent, s.back, s.ahIn = Num(t.buy), Num(t.spent), Num(t.back), Num(t.ahIn)
    return s, ins, outs, auctions
end

-- Summen als Textzeilen (Menü, Tooltip, Chat), dazu was Stats liefert.
function History.StatLines(period)
    local s, ins, outs, auctions = History.Stats(period)
    local lines = {}
    if s.ahIn > 0 then
        lines[1] = L.HIST_IN_AH:format(ns.CoinText(s.mailIn), ns.CoinText(s.ahIn))
    else
        lines[1] = L.HIST_IN:format(ns.CoinText(s.mailIn))
    end
    lines[#lines + 1] = L.HIST_OUT:format(ns.CoinText(s.mailOut), s.letters)
    lines[#lines + 1] = L.HIST_SOLD:format(s.sold, ns.CoinText(s.net), ns.CoinText(s.fees))
    lines[#lines + 1] = L.HIST_BOUGHT:format(s.bought, ns.CoinText(s.spent))
    if s.back > 0 then lines[#lines + 1] = L.HIST_BACK_COUNT:format(s.back) end
    return lines, s, ins, outs, auctions
end

---------------------------------------------------------------------------
-- Einträge als Text
---------------------------------------------------------------------------

-- Name aus dem Link, sonst aus der ID (ezCore lädt fehlende Daten nach)
local function ItemName(item)
    return ezCore.ItemName(item.l) or ezCore.ItemNameByID(item.i) or ("#" .. tostring(item.i or "?"))
end

local function ItemsText(items)
    local first = type(items) == "table" and items[1]
    if not first then return nil end
    local text = ItemName(first) .. (Num(first.c) > 1 and (" x" .. first.c) or "")
    if #items > 1 then text = text .. " +" .. (#items - 1) end
    return ezCore.Style.ColorText("highlight", "[" .. text .. "]")   -- Design-System 2.5: Rolle statt Farbcode
end

-- Wann (und bei „alle Charaktere“: wer)
local function Prefix(e)
    local text = ezCore.Ago(e.t)
    if History.AllChars() and e.c then text = text .. " · " .. ezCore.CharName(ezCore.Char(e.c), e.c) end
    return text
end

function History.MailText(e)
    local who = e.who or "?"
    local head = e.dir == "out" and L.HIST_TO:format(who) or who
    if type(e.subj) == "string" and e.subj ~= "" then head = head .. " – " .. e.subj end
    local parts = { Prefix(e), head }
    local items = ItemsText(e.items)
    if items then parts[#parts + 1] = items end
    if Num(e.money) > 0 then parts[#parts + 1] = ns.CoinText(e.money) end
    if Num(e.cod) > 0 then parts[#parts + 1] = L.HIST_COD:format(ns.CoinText(e.cod)) end
    return table.concat(parts, " · ")
end

function History.AuctionText(e)
    local item = e.item or ezCore.ItemName(e.link) or "?"
    if Num(e.n) > 1 then item = item .. " x" .. e.n end
    local kind = ezCore.History.TypeLabel(e.type) or tostring(e.type)
    local parts = { Prefix(e), kind .. ": " .. ezCore.Style.ColorText("highlight", item) }
    if e.type == "sale" then
        parts[#parts + 1] = ns.CoinText(Num(e.net))
        if Num(e.fee) > 0 then parts[#parts + 1] = L.HIST_FEE:format(ns.CoinText(e.fee)) end
    elseif e.type == "buy" and Num(e.gross) > 0 then
        parts[#parts + 1] = ns.CoinText(e.gross)
    elseif e.type == "outbid" and Num(e.net) > 0 then
        parts[#parts + 1] = L.HIST_REFUND:format(ns.CoinText(e.net))
    end
    return table.concat(parts, " · ")
end

local function PeriodName(period) return ezCore.History.PeriodLabel(period) or tostring(period) end
History.PeriodName = PeriodName
local function ScopeName(all) return all and L.ALL_CHARS or L.HIST_SCOPE_char end

---------------------------------------------------------------------------
-- Menü
---------------------------------------------------------------------------

local function Reopen(owner)
    C_Timer.After(0, function()
        if InboxFrame and InboxFrame:IsVisible() then History.ShowMenu(owner) end
    end)
end

local function AddList(root, title, list, toText)
    local sub = Menu.Button(root, title:format(#list))
    if #list == 0 then
        -- gesperrt mit Grund im Tooltip (T9-7): Blizzards Menü zeigt den Tooltip auch am gesperrten Eintrag
        sub:SetEnabled(false)
        Menu.Tip(sub, title:format(0), L.HIST_LIST_EMPTY_TIP)
        return
    end
    local shown = math.min(#list, History.LIMIT)
    if sub.SetScrollMode and shown > 20 then sub:SetScrollMode(20 * 20) end
    for i = 1, shown do Menu.Title(sub, toText(list[i])) end
    if #list > shown then Menu.Title(sub, L.HIST_MORE:format(#list - shown)) end
end

function History.ShowMenu(owner)
    local period = History.Period()
    local opened = Menu.Open(owner, function(root)
        Menu.Title(root, L.HIST_TITLE)
        if not Source() then
            Menu.Title(root, L.HIST_MISSING)
            return
        end
        -- Zeitraum und Charaktere ändern die Zahlen darunter: Menü schließen (Menu.Close) und neu öffnen.
        local periodMenu = Menu.Button(root, L.HIST_PERIOD:format(PeriodName(period)))
        local function SetPeriod(key)
            History.SetPeriod(key)
            Reopen(owner)
            return Menu.Close()
        end
        for _, key in ipairs(History.PERIODS) do Menu.Radio(periodMenu, PeriodName(key), History.Period, SetPeriod, key) end
        local scopeMenu = Menu.Button(root, L.HIST_SCOPE:format(ScopeName(History.AllChars())))
        local function SetScope(all)
            History.SetAllChars(all)
            Reopen(owner)
            return Menu.Close()
        end
        for _, all in ipairs({ false, true }) do Menu.Radio(scopeMenu, ScopeName(all), History.AllChars, SetScope, all) end

        Menu.Divider(root)
        local lines, _, ins, outs, auctions = History.StatLines(period)
        if #ins + #outs + #auctions == 0 then
            Menu.Title(root, History.Any() and L.HIST_NONE or L.HIST_EMPTY)
        else
            for _, line in ipairs(lines) do Menu.Title(root, line) end
        end

        Menu.Divider(root)
        AddList(root, L.HIST_LIST_IN, ins, History.MailText)
        AddList(root, L.HIST_LIST_OUT, outs, History.MailText)
        AddList(root, L.HIST_LIST_AH, auctions, History.AuctionText)
    end)
    if not opened then ns.Print(L.NO_MENU) end
end

---------------------------------------------------------------------------
-- Chat: /ezm statistik [heute|woche|monat|gesamt]
---------------------------------------------------------------------------

local PERIOD_WORDS = {
    heute = "today", today = "today", woche = "week", week = "week", ["7"] = "week",
    monat = "month", month = "month", ["30"] = "month", gesamt = "all", all = "all", alles = "all",
}

function History.PrintStats(word)
    if not Source() then return ns.Print(L.HIST_MISSING) end
    local period = PERIOD_WORDS[ezCore.Trim(word or ""):lower()]
    if period then History.SetPeriod(period) end
    period = History.Period()
    ns.Print(L.HIST_STATS_HEADER:format(PeriodName(period), ScopeName(History.AllChars())))
    local lines, _, ins, outs, auctions = History.StatLines(period)
    if #ins + #outs + #auctions == 0 then
        ns.Print("  " .. (History.Any() and L.HIST_NONE or L.HIST_EMPTY))
        return
    end
    for _, line in ipairs(lines) do ns.Print("  " .. line) end
end

---------------------------------------------------------------------------
-- Seitenreiter rechts am Posteingang, unter der Lupe
---------------------------------------------------------------------------

local function UpdateTab()
    if tab then tab:SetShown(ns.S.history and true or false) end
end
History.UpdateTab = UpdateTab

local function CreateTab()
    if tab or not InboxFrame then return end
    -- Unter der Lupe: ezCores Seitenreiter-Stapel am Postfenster (Übersicht 10, Verlauf 20, erster bei -48).
    -- Ist die Übersicht aus, rückt der Verlauf an ihren Platz.
    tab = ns.CreateSideTab(InboxFrame, { key = "ezMail.history", order = 20, anchor = MailFrame or InboxFrame,
        start = -48, owner = "ezMail" })
    tab.Icon:SetTexture("Interface\\Icons\\INV_Scroll_03")
    tab:SetScript("OnClick", ns.SideTabClick(function(self) History.ShowMenu(self) end))
    tab:SetScript("OnEnter", function(self)
        local text = ns.CmdText(L.HIST_TAB_TIP)
        if Source() then
            local period = History.Period()
            local lines = History.StatLines(period)
            text = text .. "\n\n" .. L.HIST_STATS_HEADER:format(PeriodName(period), ScopeName(History.AllChars()))
                .. "\n" .. table.concat(lines, "\n")
        end
        ns.ShowTip(self, L.HIST_TITLE, text)
    end)
    UpdateTab()
end

function History.Tab() return tab end

ns.WhenMailUI("Verlauf", CreateTab)
ns.OnSettingChanged(function(key)
    if key == "history" then UpdateTab() end
end)
ns.OnStatus(function()
    local H = Source()
    local mails = H and #H.List("mail") or 0
    local auctions = H and #H.List("auction") or 0
    return L.STATUS_HISTORY:format(tab and (tab:IsShown() and L.YES or L.STATUS_HIDDEN) or L.STATUS_MISSING_PART,
        mails, auctions)
end)
