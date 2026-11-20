local _, ns = ...
local L = ns.L

--[[
    Post (Titan Post): neue Post mit Absendern, Briefkasten-Stand vom letzten
    Besuch und ablaufende Post auf allen Charakteren.
    Verbesserungen: „neue Post“ funktioniert (UPDATE_PENDING_MAIL wird wirklich
    ausgewertet, Absender über GetLatestThreeSenders), Briefkasten über
    MAIL_SHOW/MAIL_CLOSED statt Hooks auf Blizzard-Funktionen, kein Timer, der
    sich selbst neu plant; zählt auch Post über dem 50er-Limit des Posteingangs.
    Den Posteingang erfasst ezCore (Core.me.mailbox) – dieselben Daten nutzen ezMail und ezBag.
    Ablaufende Post rechnet ezCore (Mail.Expiring, ExpiringAll) mit einem Grenzwert für alle Module
    (Mail.WarnDays; das Menü „Warnen ab“ stellt ihn über Mail.SetWarnDays ein).
]]

local block = ns.RegisterBlock({
    id = "mail",
    command = "post",
    name = L.MAIL_NAME,
    label = L.MAIL_LABEL,
    icon = "Interface\\Icons\\INV_Letter_15",
    events = { "UPDATE_PENDING_MAIL", "MAIL_INBOX_UPDATE", "MAIL_CLOSED", "PLAYER_ENTERING_WORLD" },
    interval = 60,
    colorable = true,
    defaults = {
        enabled = true, zone = "left", order = 55, label = false,
        hideEmpty = true,
        history = true,        -- Post-Verlauf im Tooltip (Daten: ezCore.History)
    },
})

local function NewMail()
    return HasNewMail and HasNewMail() and true or false
end

-- Den Posteingang erfasst ezCore einmal für alle Module (Core.me.mailbox: seen, count, unread,
-- money, cod, expires, list, more). Der Baustein zeigt es nur an.
ezCore.Listen("MAILBOX_SCANNED", function()
    ns.UpdateBlock(block)
end, "ezPanel")

local Mail = ezCore.Mail   -- Expiring, ExpiringAll, WarnDays, SetWarnDays

local function DaysColor(days)
    if days < 2 then return ns.RED elseif days < 7 then return ns.YELLOW end
    return ns.GREEN
end

-- Charaktere mit Post, die innerhalb des gemeinsamen Grenzwerts abläuft: { { key, c, days } }, früheste zuerst.
local function Expiring()
    local list, now = {}, time()
    for _, info in ipairs(Mail.ExpiringAll()) do
        local c = ezCore.Char(info.key)
        if c and info.count > 0 and info.first then
            list[#list + 1] = { key = info.key, c = c, days = (info.first - now) / 86400 }
        end
    end
    return list
end

ezCore.Listen("MAIL_WARN_DAYS_CHANGED", function()
    ns.QueueUpdate(block)
    ns.QueueUpdate("alerts")
end, "ezPanel")

-- Früher hatte der Baustein einen eigenen Grenzwert: einmal an ezCore übergeben, solange dort noch der Standard gilt.
function block:HandOverWarnDays()
    local cfg = self.cfg
    local own = cfg and ns.Num(cfg.warnDays)
    if own and own ~= Mail.WarnDays() and Mail.WarnDays() == 3 then Mail.SetWarnDays(own) end
    if cfg then cfg.warnDays = nil end
end
ns.OnReady(function() block:HandOverWarnDays() end)

function block:GetText()
    local parts = {}
    if NewMail() then parts[#parts + 1] = ns.GREEN .. L.MAIL_NEW .. "|r" end
    local expiring = #Expiring()
    if expiring > 0 then parts[#parts + 1] = ns.RED .. L.MAIL_EXPIRING_SHORT:format(expiring) .. "|r" end
    if #parts == 0 then
        if self.cfg.hideEmpty then return nil end
        local m = ns.me.mailbox
        return ns.Grey(m and tostring(m.count or 0) or "–")
    end
    return table.concat(parts, " ")
end

-- Für den Baustein „Meldungen“: ablaufende Post auf allen Charakteren.
function block:Warnings()
    local list = {}
    for _, x in ipairs(Expiring()) do
        list[#list + 1] = L.ALERT_MAIL:format(ns.CharName(x.c, x.key), ns.Duration(x.days * 86400, true))
    end
    return list
end

function block:OnTooltip(tooltip)
    if NewMail() then
        ns.TipLine(tooltip, L.MAIL_NEW_TIP, "good")
        if GetLatestThreeSenders then
            local senders = { GetLatestThreeSenders() }
            for _, name in ipairs(senders) do
                if type(name) == "string" and not ns.IsSecret(name) then ns.TipLine(tooltip, "  " .. name, "highlight") end
            end
        end
        tooltip:AddLine(" ")
    end
    local m = ns.me.mailbox
    if m then
        ns.TipDoubleLine(tooltip, L.MAIL_LAST_VISIT, ns.Ago(m.seen), "normal", "highlight")
        ns.TipDoubleLine(tooltip, L.MAIL_COUNT, ("%d (%d %s)"):format(m.count or 0, m.unread or 0, L.MAIL_UNREAD), "normal", "highlight")
        if (m.money or 0) > 0 then ns.TipDoubleLine(tooltip, L.MAIL_MONEY, ns.Money(m.money), "normal", "highlight") end
        if (m.cod or 0) > 0 then ns.TipDoubleLine(tooltip, L.MAIL_COD, ns.Money(m.cod), "normal", "highlight") end
    else
        ns.TipLine(tooltip, L.MAIL_NEVER, "highlight", true)
    end

    -- Ablauf je Charakter: früheste Post mit Inhalt (alle, nicht nur innerhalb des Grenzwerts)
    local first, now = true, time()
    for _, e in ipairs(ns.Characters()) do
        local info = Mail.Expiring(e.key, nil, true)
        if info and (info.first or info.expired > 0) then
            if first then
                tooltip:AddLine(" ")
                ns.TipLine(tooltip, L.MAIL_EXPIRY, "normal")
                first = false
            end
            local text
            if info.first then
                local days = (info.first - now) / 86400
                text = DaysColor(days) .. L.MAIL_DAYS:format(ezCore.Decimal(days, 1)) .. "|r"
            else
                text = ns.RED .. L.MAIL_EXPIRED .. "|r"
            end
            local count = e.c.mailbox and e.c.mailbox.count or info.count
            -- Twinks: Stand des Briefkastens (letzter Besuch), für den gespielten Charakter steht er oben
            local stand = e.isMe and "" or ns.AltStand(e.c, e.c.mailbox and e.c.mailbox.seen)
            ns.TipDoubleLine(tooltip, ns.CharName(e.c, e.key), ("%d · %s"):format(count or 0, text) .. stand, "highlight", "highlight")
        end
    end
    if self.cfg.history then self:AddHistory(tooltip) end
end

-- Gesendete und abgeholte Post dieses Charakters (ezCore erfasst, ezPanel zeigt an).
function block:AddHistory(tooltip)
    local history = ezCore.History
    if not (history and type(history.List) == "function") then return end
    local list = history.List("mail", { char = ns.charKey, limit = 6 })
    if #list == 0 then return end
    tooltip:AddLine(" ")
    ns.TipLine(tooltip, L.MAIL_HISTORY, "normal")
    for _, e in ipairs(list) do
        local arrow = e.dir == "out" and L.MAIL_HISTORY_OUT or L.MAIL_HISTORY_IN
        local who = type(e.who) == "string" and ezCore.ShortName(e.who) or "?"
        local subj = type(e.subj) == "string" and e.subj ~= "" and ("  " .. ns.Grey(ezCore.TruncateChars(e.subj, 28))) or ""
        local money = ns.Num(e.money) or 0
        local items = type(e.items) == "table" and #e.items or 0
        local right = money > 0 and ns.Money(money) or (items > 0 and L.MAIL_HISTORY_ITEMS:format(items)) or ns.Ago(e.t)
        ns.TipDoubleLine(tooltip, arrow .. " " .. who .. subj, right, "highlight", "highlight")
    end
end

ezCore.Listen("HISTORY_ADDED", function(kind)
    if kind == "mail" then ns.QueueUpdate(block) end
end, "ezPanel")

function block:OnMenu(root)
    local cfg = self.cfg
    ns.MenuCheck(root, L.MAIL_HIDE_EMPTY, cfg, "hideEmpty", self)
    ns.MenuCheck(root, L.MAIL_SHOW_HISTORY, cfg, "history", self)
    -- ein Grenzwert für alle Module (ezCore), auch ezMail liest ihn
    local warn = root:CreateButton(L.MAIL_WARN_DAYS)
    for _, n in ipairs({ 1, 2, 3, 5, 7 }) do
        ezCore.Menu.Radio(warn, L.MAIL_WARN_N:format(n), Mail.WarnDays, Mail.SetWarnDays, n)
    end
end
