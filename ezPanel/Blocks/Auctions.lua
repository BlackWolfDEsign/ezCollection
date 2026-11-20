local _, ns = ...
local L = ns.L

--[[
    Auktionen (AH-34, Welle 15): Überblick ohne Auktionshaus – nur Auskünfte anderer Module, keine eigene Zählung
    und keine Preisrechnung (SSOT: ezAuction und ezCore).
      Laufende und unterbotene Auktionen: ezCore.API("ezAuction").Auctions(charKey) → { running, undercut, value,
        sold, checked, seen, live } oder nil (AH-25, ezAuction/AuctionsTab.lua). Stand des letzten Besuchs mit Alter;
        live = true bei offenem Auktionshaus. ezAuction merkt den Stand erst, wenn im Auktionshaus der Reiter
        „Auktionen“ offen war (Blizzard fragt die eigenen Auktionen nur dort ab) – ein Besuch ohne diesen Reiter
        ändert ihn nicht. checked = 0 heißt „Unterbieten nicht geprüft“. Ohne ezAuction entfällt dieser Teil mit
        Erklärung im Tooltip.
      Verkäufe und Rückläufer in der Post: ezCores Auskunft „Auktionspost“ Core.History.AuctionMail(charKey) →
        { seen, list = { { kind = "sale" | "expired" | "cancelled", item, n, price, taken, t } … } } – was beim letzten
        Briefkastenbesuch im Briefkasten lag (seen) und was in dieser Sitzung abgeholt wurde (taken). price ist beim
        Verkauf der Erlös, beim Rückläufer der letzte Stückpreis der Einstellung.
    Leiste: laufende Auktionen, dazu (abwählbar) unterbotene und Verkäufe bzw. Rückläufer im Briefkasten.
    Tooltip: beide Teile mit Summe, Stand und Quelle; ohne Daten ein erklärender Text.
    Klick öffnet nichts Geschütztes: Linksklick ezAuctions Einstellungen, Umschalt+Linksklick ezAuctions Verlauf im
    Chat (ezAuctions Befehl „/ezauction verlauf“); beides steht auch im Menü (Leitlinie 3).
]]

local Core = ezCore

local MAIL_LINES = 6     -- Einträge der Auktionspost im Tooltip

local block = ns.RegisterBlock({
    id = "auctions",
    command = "auktionen",
    name = L.AUCT_NAME,
    label = L.AUCT_LABEL,
    icon = "Interface\\Icons\\INV_Misc_Coin_03",
    fallbackIcon = "Interface\\Icons\\INV_Misc_Coin_01",
    events = { "PLAYER_ENTERING_WORLD", "AUCTION_HOUSE_CLOSED", "OWNED_AUCTIONS_UPDATED", "MAIL_CLOSED" },
    colorable = true,
    defaults = {
        enabled = false, zone = "right", order = 46,
        undercut = true,        -- unterbotene Auktionen auf der Leiste
        mail = true,            -- Verkäufe und Rückläufer im Briefkasten auf der Leiste
    },
})

---------------------------------------------------------------------------
-- Daten (nur lesen)
---------------------------------------------------------------------------

-- ezAuctions Schnittstelle oder nil (ezAuction läuft nicht oder ist zu alt).
local function AuctionAPI()
    local api = Core.API and Core.API("ezAuction")
    if type(api) ~= "table" or type(api.Auctions) ~= "function" then return nil end
    return api
end
block.AuctionAPI = AuctionAPI

-- Stand der eigenen Auktionen laut ezAuction oder nil.
local function State()
    local api = AuctionAPI()
    if not api then return nil end
    local ok, state = pcall(api.Auctions, ns.charKey)
    return ok and type(state) == "table" and state or nil
end
block.State = State

-- Auskunft „Auktionspost“ aus ezCore oder nil (älteres ezCore).
local function Mail()
    local history = Core.History
    if type(history) ~= "table" or type(history.AuctionMail) ~= "function" then return nil end
    local ok, mail = pcall(history.AuctionMail, ns.charKey)
    if not ok or type(mail) ~= "table" then return nil end
    if type(mail.list) ~= "table" then mail.list = {} end
    return mail
end
block.Mail = Mail

-- Auktionspost zusammengefasst: { box = { sales, returns, sum }, taken = { sales, returns, sum } }.
-- Gezählt werden Briefe der Auskunft, summiert die Erlöse, die ezCore nennt (keine eigene Preisrechnung).
local function MailSummary(mail)
    local out = { box = { sales = 0, returns = 0, sum = 0 }, taken = { sales = 0, returns = 0, sum = 0 } }
    for _, e in ipairs(mail and mail.list or {}) do
        local part = e.taken and out.taken or out.box
        if e.kind == "sale" then
            part.sales = part.sales + 1
            part.sum = part.sum + (ns.Num(e.price) or 0)
        else
            part.returns = part.returns + 1
        end
    end
    return out
end
block.MailSummary = MailSummary

---------------------------------------------------------------------------
-- Anzeige
---------------------------------------------------------------------------

function block:GetText()
    local cfg = self.cfg
    local state = State()
    local parts = {}
    if state then
        parts[1] = tostring(ns.Num(state.running) or 0)
        local undercut, checked = ns.Num(state.undercut) or 0, ns.Num(state.checked) or 0
        if cfg.undercut and checked > 0 and undercut > 0 then
            local text = L.AUCT_UNDERCUT_SHORT:format(undercut)
            parts[#parts + 1] = cfg.colored and (ns.RED .. text .. "|r") or text
        end
    end
    if cfg.mail then
        local box = MailSummary(Mail()).box
        if box.sales + box.returns > 0 then parts[#parts + 1] = L.AUCT_MAIL_SHORT:format(box.sales + box.returns) end
    end
    if #parts == 0 then return ns.Grey(AuctionAPI() and L.AUCT_NONE_SHORT or L.AUCT_NO_EZAUCTION_SHORT) end
    return table.concat(parts, ns.Grey(" · "))
end

local function Line(tooltip, left, right)
    ns.TipDoubleLine(tooltip, left, right, "normal", "highlight")
end

-- Teil 1: laufende Auktionen laut ezAuction (oder die Erklärung, warum hier nichts steht).
local function AddAuctions(tooltip)
    ns.TipLine(tooltip, L.AUCT_RUNNING_HEAD, "normal")
    if not AuctionAPI() then
        ns.TipLine(tooltip, L.AUCT_NO_EZAUCTION, "highlight", true)
        return
    end
    local state = State()
    if not state then
        ns.TipLine(tooltip, L.AUCT_NEVER, "highlight", true)
        return
    end
    Line(tooltip, L.AUCT_RUNNING, ns.Number(ns.Num(state.running) or 0))
    local value = ns.Num(state.value)
    if value and value > 0 then Line(tooltip, L.AUCT_VALUE, ns.Money(value)) end
    if (ns.Num(state.checked) or 0) > 0 then
        local undercut = ns.Num(state.undercut) or 0
        Line(tooltip, L.AUCT_UNDERCUT, undercut > 0 and (ns.RED .. ns.Number(undercut) .. "|r") or "0")
    else
        Line(tooltip, L.AUCT_UNDERCUT, ns.Grey(L.AUCT_NOT_CHECKED))
    end
    local sold = ns.Num(state.sold) or 0
    if sold > 0 then Line(tooltip, L.AUCT_SOLD, ns.Number(sold)) end
    local stand = state.live and L.AUCT_STAND_LIVE or L.AUCT_STAND:format(ns.Ago(state.seen))
    ns.TipLine(tooltip, stand, "hint", true)
    if (ns.Num(state.checked) or 0) == 0 then ns.TipLine(tooltip, L.AUCT_CHECK_HOW, "hint", true) end
end

local function KindText(kind)
    if kind == "sale" then return L.AUCT_KIND_SALE end
    if kind == "cancelled" then return L.AUCT_KIND_CANCELLED end
    return L.AUCT_KIND_EXPIRED
end

-- Teil 2: Auktionspost laut ezCore.
local function AddMail(tooltip)
    ns.TipLine(tooltip, L.AUCT_MAIL_HEAD, "normal")
    local mail = Mail()
    if not mail then
        ns.TipLine(tooltip, L.AUCT_MAIL_NO_CORE, "highlight", true)
        return
    end
    local sum = MailSummary(mail)
    if #mail.list == 0 then
        ns.TipLine(tooltip, ns.Num(mail.seen) and L.AUCT_MAIL_EMPTY or L.AUCT_MAIL_NEVER, "highlight", true)
    else
        local box, taken = sum.box, sum.taken
        if box.sales > 0 then Line(tooltip, L.AUCT_MAIL_SALES:format(box.sales), ns.Money(box.sum)) end
        if box.returns > 0 then Line(tooltip, L.AUCT_MAIL_RETURNS, ns.Number(box.returns)) end
        if taken.sales > 0 then Line(tooltip, L.AUCT_TAKEN_SALES:format(taken.sales), ns.Money(taken.sum)) end
        if taken.returns > 0 then Line(tooltip, L.AUCT_TAKEN_RETURNS, ns.Number(taken.returns)) end
        for i = 1, math.min(#mail.list, MAIL_LINES) do
            local e = mail.list[i]
            local name = Core.ItemNameByID and Core.ItemNameByID(e.item) or nil
            local n = ns.Num(e.n)
            local left = "  " .. (name or L.UNKNOWN) .. ((n and n > 1) and (" ×" .. n) or "")
            local right = KindText(e.kind)
            if e.kind == "sale" and ns.Num(e.price) then right = right .. "  " .. ns.Money(e.price) end
            ns.TipDoubleLine(tooltip, left, right, "highlight", "hint")
        end
        if #mail.list > MAIL_LINES then
            ns.TipLine(tooltip, "  " .. ezCore.More(#mail.list - MAIL_LINES), "hint")
        end
    end
    if ns.Num(mail.seen) then ns.TipLine(tooltip, L.AUCT_MAIL_STAND:format(ns.Ago(mail.seen)), "hint", true) end
    ns.TipLine(tooltip, L.AUCT_MAIL_SOURCE, "hint", true)
end

function block:OnTooltip(tooltip)
    AddAuctions(tooltip)
    tooltip:AddLine(" ")
    AddMail(tooltip)
end

---------------------------------------------------------------------------
-- Klicks und Menü: nur ezAuctions Einstellungen und sein Verlauf im Chat (nichts Geschütztes)
---------------------------------------------------------------------------

local function OpenSettings()
    if not ns.IsLoaded("ezAuction") then return ns.Print(L.AUCT_NO_EZAUCTION) end
    if Core.OpenModuleSettings and Core.OpenModuleSettings("ezAuction") then return true end
    ns.Print(L.AUCT_NO_SETTINGS)
    return false
end
block.OpenSettings = OpenSettings

-- ezAuctions Verlauf im Chat über dessen Befehl („/ezauction verlauf“, englisch „history“).
local function PrintHistory()
    if not ns.IsLoaded("ezAuction") then return ns.Print(L.AUCT_NO_EZAUCTION) end
    local handler = ns.SlashHandler and ns.SlashHandler("/ezauction")
    if not handler then
        ns.Print(L.AUCT_NO_HISTORY)
        return false
    end
    local ok, err = pcall(handler, "verlauf")
    if not ok then ns.Error(err, "PrintHistory") end
    return ok
end
block.PrintHistory = PrintHistory

block.hints = function()
    if not ns.IsLoaded("ezAuction") then return {} end
    return { L.AUCT_HINT_LEFT, Core.ClickText("left", "SHIFT", L.AUCT_HINT_SHIFT) }   -- Klick-Hinweis über ezCore (T18-9)
end

block.actions = function()
    if not ns.IsLoaded("ezAuction") then return {} end
    return {
        -- „ezAuction: Einstellungen …“ – ezCores Menütext mit dem Namen des Moduls (T18-8)
        { text = L.AUCT_OPEN_SETTINGS:format(Core.L.MENU_OWN_SETTINGS), fn = OpenSettings },
        { text = L.AUCT_PRINT_HISTORY, fn = PrintHistory },
    }
end

function block:OnClick(button)
    if button ~= "LeftButton" or not ns.IsLoaded("ezAuction") then return end
    if IsShiftKeyDown and IsShiftKeyDown() then PrintHistory() else OpenSettings() end
end

function block:OnMenu(root)
    local cfg = self.cfg
    local bar = root:CreateButton(L.MENU_BAR_SHOWS)
    ns.MenuCheck(bar, L.AUCT_SHOW_UNDERCUT, cfg, "undercut", self)
    ns.MenuCheck(bar, L.AUCT_SHOW_MAIL, cfg, "mail", self)
end

-- Neue Auktionspost (Briefkasten gelesen, Brief abgeholt) und Ende eines Besuchs im Auktionshaus: neu zeichnen.
local function Refresh() ns.QueueUpdate(block) end
Core.Listen("MAILBOX_SCANNED", Refresh, "ezPanel")
Core.Listen("HISTORY_ADDED", function(kind) if kind == "auction" then Refresh() end end, "ezPanel")
Core.Listen("HISTORY_CLEARED", function(kind) if kind == nil or kind == "auction" then Refresh() end end, "ezPanel")
