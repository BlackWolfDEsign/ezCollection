local _, ns = ...
local L = ns.L

--[[
    Gold über alle Charaktere.
    Verbesserungen gegenüber TitanGold: Sitzung übersteht /reload, Einnahmen und
    Ausgaben getrennt, Fraktion wird über den englischen Namen verglichen (geht
    in jeder Spielsprache), Realms werden nicht über normalisierte Namen verwechselt.
    Gold aller Charaktere aus ezCore.GoldList (eine Liste mit ezBag), Verlauf und Auktionshaus aus
    ezCore.History (Since für den Zeitraum, AuctionTotals – eine Rechnung mit ezAuction und ezMail).
    Die Sitzung (Beginn, Startgold, Einnahmen, Ausgaben) zählt ezCore (Core.Session, PANEL-03).
    „Als Text kopieren“ (V5, Bericht Welle 20): Menüeintrag „Gold-Verlauf als Text kopieren …“ – jede Buchung des
    gewählten Zeitraums (wie im Tooltip: 24 Stunden, 7 oder 30 Tage) mit Zeit, Quelle, Einnahme, Ausgabe und Gold
    danach, älteste zuerst, über ezCores Kopierfeld (ns.CopyAsText). Die Bilanz rechnet die Tabelle selbst (Summe der
    Spalten). Eine Gold-Buchung nennt keine anderen Spieler, also kein Häkchen „Namen mitnehmen“ (Frage E6).
]]

local block = ns.RegisterBlock({
    id = "gold",
    command = "gold",
    name = L.GOLD_NAME,
    label = L.GOLD_LABEL,
    icon = "Interface\\Icons\\INV_Misc_Coin_01",
    events = { "PLAYER_MONEY" },
    defaults = {
        enabled = true, zone = "left", order = 30, label = false,
        show = "char",        -- char | realm | all
        sessionOnBar = false,
        scope = "realm",      -- realm | all (Tooltip)
        faction = "all",      -- all | mine
        sort = "money",       -- money | name
        hidden = {},
        history = true,       -- Verlauf (woher, wohin; Auktionshaus) im Tooltip
        historyDays = 1,      -- 1 | 7 | 30
    },
    hints = { L.GOLD_HINT_LEFT },
})

---------------------------------------------------------------------------
-- Daten
---------------------------------------------------------------------------

-- Einnahmen und Ausgaben der Sitzung zählt ezCore (Core.Session, PANEL-03); ezPanel liest sie nur.
local Session = ezCore.Session

-- Gewinn der Sitzung: Gold jetzt minus Gold beim Beginn (ohne Sitzung 0).
local function SessionNet()
    local start = Session.StartMoney()
    return start and (GetMoney() - start) or 0
end

-- Kriegsmeute-Bank gibt es nur auf Clients, die sie wirklich haben.
local function WarbandMoney()
    if not (C_Bank and C_Bank.FetchDepositedMoney and Enum.BankType and Enum.BankType.Account) then return nil end
    if C_Bank.CanUseBank then
        local ok, can = pcall(C_Bank.CanUseBank, Enum.BankType.Account)
        if not ok or not can then return nil end
    end
    local ok, money = pcall(C_Bank.FetchDepositedMoney, Enum.BankType.Account)
    money = ok and ns.Num(money) or nil
    if money and money > 0 then return money end
    return nil
end

-- Gold der Charaktere (ezCore.GoldList): Liste reichste zuerst bzw. nach Name, Summe.
local function GoldList(scope, sort)
    local cfg = block.cfg
    return ezCore.GoldList({ realm = scope == "realm", faction = cfg.faction == "mine", hidden = cfg.hidden,
        sort = sort == "name" and "name" or nil })
end

local function Total(scope)
    local _, total = GoldList(scope)
    return total
end

---------------------------------------------------------------------------
-- Anzeige
---------------------------------------------------------------------------

function block:GetText()
    local cfg = self.cfg
    local value
    if cfg.show == "realm" then
        value = Total("realm")
    elseif cfg.show == "all" then
        value = Total("all")
    else
        value = GetMoney()
    end
    local text = ns.Money(value)
    if cfg.sessionOnBar then
        local net = SessionNet()
        if net ~= 0 then
            local sign = net > 0 and ns.GREEN .. "+" or ns.RED
            text = text .. " " .. sign .. ns.Money(net, nil, false) .. "|r"
        end
    end
    return text
end

---------------------------------------------------------------------------
-- Verlauf: Daten aus ezCore.History (gold, auction), ezPanel zeigt nur an
---------------------------------------------------------------------------

local SOURCES = { "loot", "quest", "merchant", "auction", "mail", "trade", "trainer", "taxi", "guildbank", "barber", "other" }
local KNOWN = {}
for _, src in ipairs(SOURCES) do KNOWN[src] = true end

local function AddHistory(tooltip, days)
    local history = ezCore.History
    if not (history and type(history.List) == "function") then return end
    local since = history.Since(days)
    local plus, minus, total = {}, {}, 0
    local entries = history.List("gold", { char = ns.charKey, since = since })
    for _, e in ipairs(entries) do
        local d = ns.Num(e.d) or 0
        local src = KNOWN[e.src] and e.src or "other"
        if d > 0 then plus[src] = (plus[src] or 0) + d elseif d < 0 then minus[src] = (minus[src] or 0) - d end
        total = total + d
    end
    local ah = history.AuctionTotals({ char = ns.charKey, since = since })
    if #entries == 0 and ah.sale == 0 and ah.buy == 0 then return end

    tooltip:AddLine(" ")
    ns.TipLine(tooltip, L.GOLD_HISTORY:format(L["GOLD_DAYS_" .. days] or tostring(days)), "normal")
    for _, src in ipairs(SOURCES) do
        local p, m = plus[src], minus[src]
        if p or m then
            local parts = {}
            if p then parts[#parts + 1] = ns.GREEN .. "+|r" .. ns.Money(p) end
            if m then parts[#parts + 1] = ns.RED .. "-|r" .. ns.Money(m) end
            ns.TipDoubleLine(tooltip, "  " .. L["GOLD_SRC_" .. src], table.concat(parts, "  "), "highlight", "highlight")
        end
    end
    if #entries > 0 then ns.TipDoubleLine(tooltip, L.GOLD_NET, ns.Money(total, nil, true), "normal", "highlight") end
    if ah.sale > 0 or ah.buy > 0 then
        ns.TipDoubleLine(tooltip, L.GOLD_AH, L.GOLD_AH_TEXT:format(ah.sale, ns.Money(ah.income), ah.buy, ns.Money(ah.spent)), "normal", "highlight")
    end
end

-- Als Text kopieren (V5): Spalten und Zeilen; Beträge als Gold mit vier Stellen (ezCores Spalte „money“, Welle 26).
local COPY_COLUMNS = {
    { key = "t", title = L.COPY_COL_TIME, format = function(t) return ezCore.DateText(t, "long") end },
    { key = "src", title = L.GOLD_COPY_SOURCE },
    { key = "plus", title = L.GOLD_COPY_IN, format = "money" },
    { key = "minus", title = L.GOLD_COPY_OUT, format = "money" },
    { key = "m", title = L.GOLD_COPY_AFTER, format = "money" },
}
block.COPY_COLUMNS = COPY_COLUMNS

-- Buchungen dieses Charakters im Zeitraum, älteste zuerst.
local function CopyRows(days)
    local history = ezCore.History
    if not (history and type(history.List) == "function") then return {} end
    local entries = history.List("gold", { char = ns.charKey, since = history.Since(days) })
    local rows = {}
    for i = #entries, 1, -1 do
        local e = entries[i]
        local d = ns.Num(e.d)
        local src = KNOWN[e.src] and e.src or "other"
        rows[#rows + 1] = { t = e.t, src = L["GOLD_SRC_" .. src], m = e.m,
            plus = d and d > 0 and d or nil, minus = d and d < 0 and -d or nil }
    end
    return rows
end
block.CopyRows = CopyRows

local function CopyHistory(def)
    local days = def.cfg.historyDays or 1
    return ns.CopyAsText({ title = L.GOLD_COPY_TITLE:format(L["GOLD_DAYS_" .. days] or tostring(days)),
        columns = COPY_COLUMNS, rows = CopyRows(days) })
end
block.CopyHistory = CopyHistory

-- Menüeintrag nur mit ezCores Kopierfeld (Welle 23d); ohne Buchungen sagt der Klick es im Chat.
block.actions = function()
    if not ns.CanCopyText() then return {} end
    return { { text = L.GOLD_COPY, fn = CopyHistory } }
end

ezCore.Listen("HISTORY_ADDED", function(kind)
    if kind == "gold" or kind == "auction" then ns.QueueUpdate(block) end
end, "ezPanel")

local FACTION_ICON = {
    Alliance = "|TInterface\\FriendsFrame\\PlusManz-Alliance:14:14|t",
    Horde = "|TInterface\\FriendsFrame\\PlusManz-Horde:14:14|t",
}

function block:OnTooltip(tooltip)
    local cfg = self.cfg
    local list, total = GoldList(cfg.scope, cfg.sort)

    local scopeText = cfg.scope == "realm" and ns.realm or L.ALL_REALMS
    ns.TipLine(tooltip, scopeText, "normal")
    local showFaction = cfg.faction == "all"
    for _, entry in ipairs(list) do
        local c = entry.c
        local name = ns.CharName(c, entry.key)
        if entry.key == ns.charKey then name = name .. " " .. ns.Grey(L.YOU) end
        if showFaction and FACTION_ICON[c.faction] and c.faction ~= ns.me.faction then
            name = FACTION_ICON[c.faction] .. " " .. name
        end
        -- Twinks: Stand des Goldes ist ihr letzter Login (Regel „Datenquellen“, PANEL-17)
        local stand = entry.key == ns.charKey and "" or ns.AltStand(c)
        ns.TipDoubleLine(tooltip, name, ns.Money(entry.money) .. stand, "highlight", "highlight")
    end
    local warband = WarbandMoney()
    if warband then
        ns.TipDoubleLine(tooltip, L.GOLD_WARBAND, ns.Money(warband), "highlight", "highlight")
        total = total + warband
    end
    ns.TipDoubleLine(tooltip, L.TOTAL, ns.Money(total), "normal", "highlight")

    if Session.Get() then
        local elapsed = math.max(1, time() - ns.SessionStart())
        local net = SessionNet()
        tooltip:AddLine(" ")
        ns.TipDoubleLine(tooltip, L.SESSION, ns.Duration(elapsed, true), "normal", "highlight")
        ns.TipDoubleLine(tooltip, L.GOLD_EARNED, ns.Money(Session.Earned()), "highlight", "good")
        ns.TipDoubleLine(tooltip, L.GOLD_SPENT, ns.Money(Session.Spent()), "highlight", "bad")
        ns.TipDoubleLine(tooltip, L.GOLD_NET, ns.Money(net), "highlight", net >= 0 and "good" or "bad")
        if elapsed >= 300 then
            ns.TipDoubleLine(tooltip, L.PER_HOUR, ns.Money(net / elapsed * 3600), "highlight", "highlight")
        end
    end
    if cfg.history then AddHistory(tooltip, cfg.historyDays or 1) end
end

function block:OnClick(button)
    if button == "LeftButton" then
        local order = { char = "realm", realm = "all", all = "char" }
        self.cfg.show = order[self.cfg.show] or "char"
    end
end

function block:OnMenu(root)
    local cfg = self.cfg
    local bar = root:CreateButton(L.MENU_BAR_SHOWS)
    ns.MenuRadio(bar, L.GOLD_SHOW_CHAR, cfg, "show", "char", self)
    ns.MenuRadio(bar, L.GOLD_SHOW_REALM, cfg, "show", "realm", self)
    ns.MenuRadio(bar, L.GOLD_SHOW_ALL, cfg, "show", "all", self)
    bar:CreateDivider()
    ns.MenuCheck(bar, L.GOLD_SESSION_ON_BAR, cfg, "sessionOnBar", self)

    local tip = root:CreateButton(L.MENU_TOOLTIP)
    ns.MenuRadio(tip, L.SCOPE_REALM, cfg, "scope", "realm", self)
    ns.MenuRadio(tip, L.SCOPE_ALL, cfg, "scope", "all", self)
    tip:CreateDivider()
    ns.MenuRadio(tip, L.FACTION_ALL, cfg, "faction", "all", self)
    ns.MenuRadio(tip, L.FACTION_MINE, cfg, "faction", "mine", self)
    tip:CreateDivider()
    ns.MenuRadio(tip, L.SORT_MONEY, cfg, "sort", "money", self)
    ns.MenuRadio(tip, L.SORT_NAME, cfg, "sort", "name", self)
    tip:CreateDivider()
    ns.MenuCheck(tip, L.GOLD_SHOW_HISTORY, cfg, "history", self)
    for _, days in ipairs({ 1, 7, 30 }) do
        ns.MenuRadio(tip, L.GOLD_HISTORY:format(L["GOLD_DAYS_" .. days]), cfg, "historyDays", days, self)
    end

    local coins = root:CreateButton(L.MENU_MONEY_STYLE)
    for _, style in ipairs({ "coins", "gold", "text" }) do
        coins:CreateRadio(L["MONEY_" .. style], function() return ns.S.moneyStyle == style end, function()
            ns.SetSetting("moneyStyle", style)
            return MenuResponse and MenuResponse.Refresh
        end, style)
    end

    local chars = root:CreateButton(L.MENU_CHARACTERS)
    -- „Alle auswählen / Alle abwählen“ über den Charakteren (Design-System 2.11; gemerkt in cfg.hidden)
    ns.MenuAllToggle(chars, ns.Characters(), function(entry) return not cfg.hidden[entry.key] end,
        function(entry, on) cfg.hidden[entry.key] = (not on) or nil end, function() ns.QueueUpdate(self) end)
    for _, entry in ipairs(ns.Characters()) do
        local key = entry.key
        chars:CreateCheckbox(ns.CharName(entry.c, key), function() return not cfg.hidden[key] end, function()
            cfg.hidden[key] = not cfg.hidden[key] or nil
            ns.QueueUpdate(self)
            return MenuResponse and MenuResponse.Refresh
        end)
    end

    root:CreateButton(L.MENU_RESET_SESSION, function()
        ns.NewSession()   -- ezCores Sitzung (für alle Module)
        ns.UpdateAllBlocks()
        ns.Print(L.SESSION_RESET)
    end)
end
