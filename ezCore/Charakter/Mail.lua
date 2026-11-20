local _, ns = ...
local Core = ezCore

--[[
    Briefkasten (vorher verteilt auf ezMail, ezChat, ezBag und ezPanel):
      - Kopfdaten, Erkennen von Briefen und Auktionshaus-Post (ezMail)
      - Weiche zwischen Blizzards Postfenster auf WoW Forever (Mixins) und Retail (Globale) (ezMail)
      - offen? seit wann? Formular frei? (ezChat)
      - EIN Erfassen des Posteingangs je Besuch: Anzahl je Gegenstand (vorher ezBag), Stand des
        Briefkastens (vorher ezPanel) und Ablaufzeiten (vorher ezMail) – alles in Core.me
    Nachricht MAILBOX_SCANNED nach jedem Erfassen.

    Ablaufende Post (eine Rechnung für ezMail und ezPanel, vorher zwei mit zwei Grenzwerten):
      Mail.WarnDays() → Tage (Standard 3)          Mail.SetWarnDays(tage)   (ein Grenzwert für alle Module)
      Mail.Expiring(key, tage, alle) → { count, first, deleting, expired, seen, more } oder nil ohne Daten
            nur Briefe mit Inhalt; tage nil = WarnDays(); alle = true: alle noch nicht abgelaufenen
      Mail.ExpiringAll(tage, alle) → { { key, … wie oben } … } nach dem frühesten Ablauf, nur mit count > 0
      Mail.ForgetExpired(key) → Anzahl   abgelaufene Einträge vergessen (sind zurück beim Absender oder gelöscht)
    Module schreiben nicht selbst in mailbox.list.
]]

local Mail = {}
Core.Mail = Mail

---------------------------------------------------------------------------
-- Kopfdaten
---------------------------------------------------------------------------

-- Wartet der Server noch auf die Antwort zu einem Post-Befehl (C_Mail.IsCommandPending)? Solange darf kein weiterer
-- Befehl folgen. EINE Stelle (W-14; vorher wortgleich in MailQueue.lua und zweimal in ezMail). Gesperrte oder
-- fehlende Antwort: false.
function Mail.CommandPending()
    local api = rawget(_G, "C_Mail")
    if type(api) ~= "table" then return false end
    return Core.Bool(Core.Call(api.IsCommandPending), false)
end

-- Anzahl der Briefe im Posteingang und auf dem Server.
function Mail.NumMails()
    if not GetInboxNumItems then return 0, 0 end
    local n, total = GetInboxNumItems()
    return n or 0, total or n or 0
end

-- Kopfdaten eines Briefs als Tabelle (nil, wenn der Platz leer ist).
function Mail.Header(index)
    if not index or not GetInboxHeaderInfo then return nil end
    local _, _, sender, subject, money, cod, daysLeft, itemCount, wasRead, wasReturned, _, _, isGM = GetInboxHeaderInfo(index)
    if daysLeft == nil then return nil end
    return {
        sender = sender or UNKNOWN or "?",
        subject = subject or "",
        money = money or 0,
        cod = cod or 0,
        daysLeft = daysLeft or 0,
        items = itemCount or 0,
        read = wasRead,
        returned = wasReturned,
        gm = isGM,
    }
end

-- Erkennt einen Brief wieder, auch wenn sich sein Platz im Posteingang verschiebt.
-- Inhalt (Gold, Anhänge) gehört absichtlich nicht dazu – der ändert sich beim Öffnen.
function Mail.Signature(h)
    return h.sender .. "\031" .. h.subject .. "\031" .. (h.returned and "r" or "") .. (h.cod > 0 and "c" or "")
end

-- Auktionshaus-Post anhand von Blizzards Betreffzeilen erkennen – EINE Stelle (V-028; vorher je eine Mustertabelle
-- hier und in History.lua).
--   Mail.AuctionKind(betreff) → Art, Gegenstand: "sale" | "buy" | "expired" | "cancelled" | "outbid", sonst nil
--   Mail.Category(betreff)    → "ahSold" | "ahWon" | "ahReturned" | "other" (die drei Gruppen des Posteingangs)
Mail.AUCTION_SUBJECTS = {
    { "AUCTION_SOLD_MAIL_SUBJECT", "sale" },
    { "AUCTION_WON_MAIL_SUBJECT", "buy" },
    { "AUCTION_EXPIRED_MAIL_SUBJECT", "expired" },
    { "AUCTION_REMOVED_MAIL_SUBJECT", "cancelled" },
    { "AUCTION_OUTBID_MAIL_SUBJECT", "outbid" },
}
Mail.AUCTION_CATEGORY = { sale = "ahSold", buy = "ahWon", expired = "ahReturned", cancelled = "ahReturned", outbid = "ahReturned" }

local subjectPatterns, subjectsComplete

local function BuildPatterns()
    subjectPatterns = {}
    for _, entry in ipairs(Mail.AUCTION_SUBJECTS) do
        local pattern = Core.FormatToPattern(rawget(_G, entry[1]))
        if pattern then subjectPatterns[#subjectPatterns + 1] = { pattern, entry[2] } end
    end
    -- Fehlt ein Text noch (Blizzards Auktions-Texte laden spät), beim nächsten Mal neu bauen.
    subjectsComplete = #subjectPatterns == #Mail.AUCTION_SUBJECTS
end

function Mail.AuctionKind(subject)
    if Core.IsSecret(subject) or type(subject) ~= "string" then return nil end
    if not subjectsComplete then BuildPatterns() end
    for _, entry in ipairs(subjectPatterns) do
        local item = subject:match(entry[1])
        if item then return entry[2], item end
    end
    return nil
end

function Mail.Category(subject)
    local kind = Mail.AuctionKind(subject)
    return kind and Mail.AUCTION_CATEGORY[kind] or "other"
end

-- Porto für den Brief, der gerade im Formular steht – EINE Stelle (V-062; vorher fest 30 Kupfer in ezMail).
-- Blizzards GetSendMailPrice kennt Anhänge und Sonderregeln des Servers (zweiter Wert true); kann der Client es
-- nicht sagen, gilt das Grundporto Mail.BASE_POSTAGE je Anhang, mindestens einmal (zweiter Wert false).
Mail.BASE_POSTAGE = 30
function Mail.Postage(attachments)
    local price = Core.Num(Core.Call(rawget(_G, "GetSendMailPrice")))
    if price and price > 0 then return price, true end
    local n = Core.Num(attachments) or 0
    return Mail.BASE_POSTAGE * math.max(1, n), false
end

-- Gelesener Brief ohne Gold, Gegenstände und Nachnahme, den Blizzard löschen lässt.
function Mail.IsEmptyRead(index, h)
    h = h or Mail.Header(index)
    if not h or not h.read or h.gm then return false end
    if h.money > 0 or h.items > 0 or h.cod > 0 then return false end
    return InboxItemCanDelete(index) and true or false
end

---------------------------------------------------------------------------
-- Blizzards Postfenster in zwei Fassungen: WoW Forever nutzt Mixins (InboxFrame:Update,
-- OpenMailDeleteButton:Delete), älteres Retail globale Funktionen (InboxFrame_Update, OpenMail_Delete).
-- Diese Weiche ist die einzige Stelle, die den Unterschied kennt.
---------------------------------------------------------------------------

function Mail.HasInboxMethod()
    return _G.InboxFrame ~= nil and type(_G.InboxFrame.Update) == "function"
end

function Mail.UpdateInbox()
    if Mail.HasInboxMethod() then
        InboxFrame:Update()
    elseif type(InboxFrame_Update) == "function" then
        InboxFrame_Update()
    end
end

function Mail.HookInboxUpdate(fn)
    if Mail.HasInboxMethod() then
        hooksecurefunc(InboxFrame, "Update", fn)
    else
        hooksecurefunc("InboxFrame_Update", fn)
    end
end

function Mail.HookOpenMailUpdate(fn)
    if OpenMailFrame and type(OpenMailFrame.Update) == "function" then
        hooksecurefunc(OpenMailFrame, "Update", fn)
    elseif type(OpenMail_Update) == "function" then
        hooksecurefunc("OpenMail_Update", fn)
    end
end

-- Platz des gerade geöffneten Briefs (nil, wenn keiner offen ist).
function Mail.OpenMailIndex()
    local index = InboxFrame and InboxFrame.openMailID
    if index and index > 0 and index <= (Mail.NumMails()) then return index end
    return nil
end

-- Den gerade geöffneten Brief auf Blizzards eigenem Weg zurückschicken: Blizzard schickt ihn zurück
-- und schließt das Fenster, ohne dass der Brief beim Schließen versehentlich gelöscht wird.
function Mail.ReturnOpenMail()
    if OpenMailDeleteButton and type(OpenMailDeleteButton.Delete) == "function" then
        OpenMailDeleteButton:Delete()
        return true
    end
    if type(OpenMail_Delete) == "function" then
        OpenMail_Delete()
        return true
    end
    return false
end

-- Fehlende Teile des Postfensters (leer = alles da).
Mail.UI_PARTS = { "MailFrame", "InboxFrame", "SendMailFrame" }

function Mail.UIMissing()
    local missing = {}
    for _, name in ipairs(Mail.UI_PARTS) do
        if _G[name] == nil then missing[#missing + 1] = name end
    end
    if _G.InboxFrame and not Mail.HasInboxMethod() and type(_G.InboxFrame_Update) ~= "function" then
        missing[#missing + 1] = "InboxFrame:Update"
    end
    return missing
end

---------------------------------------------------------------------------
-- Briefkasten offen? Formular frei? (vorher ezChat)
---------------------------------------------------------------------------

local isOpen, openedAt = false, 0

function Mail.IsOpen() return isOpen end

-- Sekunden seit dem Öffnen des Postfensters, nil wenn es zu ist.
function Mail.OpenSince()
    if isOpen then return GetTime() - openedAt end
    return nil
end

local function FieldText(box)
    if not box then return "" end
    for _, method in ipairs({ "GetInputText", "GetText" }) do
        if type(box[method]) == "function" then
            local ok, text = pcall(box[method], box)
            if ok and type(text) == "string" then return text end
        end
    end
    return ""
end
Mail.FieldText = FieldText

-- Nichts anfassen, woran der Spieler gerade schreibt oder was er anhängen will.
-- ignoreName: ein nur vorbelegter Empfänger (Feld ohne Fokus) zählt nicht als Arbeit des Spielers.
function Mail.FormIdle(ignoreName)
    local nameBox = _G.SendMailNameEditBox
    if FieldText(nameBox) ~= "" then
        local focused = nameBox and nameBox.HasFocus and nameBox:HasFocus()
        if not ignoreName or focused then return false end
    end
    if FieldText(_G.SendMailSubjectEditBox) ~= "" then return false end
    if FieldText(_G.SendMailBodyEditBox) ~= "" or FieldText(_G.MailEditBox) ~= "" then return false end
    for i = 1, (ATTACHMENTS_MAX_SEND or 12) do
        if HasSendMailItem then
            if HasSendMailItem(i) then return false end
        elseif GetSendMailItem and GetSendMailItem(i) then
            return false
        end
    end
    if GetSendMailMoney and (GetSendMailMoney() or 0) > 0 then return false end
    if GetSendMailCOD and (GetSendMailCOD() or 0) > 0 then return false end
    return true
end

---------------------------------------------------------------------------
-- Posteingang erfassen: einmal je Aktualisierung für alle Module
---------------------------------------------------------------------------

local scanPending = false

function Mail.Scan()
    local me = Core.me
    if not me or not isOpen or not GetInboxNumItems then return end
    local shown, total = Mail.NumMails()
    local now = time()
    local counts, items = {}, {}
    local unread, money, cod, minDays = 0, 0, 0, nil
    local list = {}
    for index = 1, shown do
        local h = Mail.Header(index)
        if h then
            if not h.read then unread = unread + 1 end
            money = money + (Core.Num(h.money) or 0)
            cod = cod + (Core.Num(h.cod) or 0)
            local days = Core.Num(h.daysLeft)
            if days and (not minDays or days < minDays) then minDays = days end
            -- Ablauf von Briefen mit Inhalt (Gold oder Gegenstände): wird gelöscht statt zurückgeschickt?
            if days and (h.money > 0 or h.items > 0) then
                list[#list + 1] = { e = now + floor(days * 86400), d = InboxItemCanDelete(index) and true or nil }
            end
        end
        for attachment = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
            local _, itemID, _, count, quality = GetInboxItem(index, attachment)
            if itemID and not Core.IsSecret(itemID) then
                count = count or 1
                counts[itemID] = (counts[itemID] or 0) + count
                items[#items + 1] = { i = itemID, l = GetInboxItemLink(index, attachment), c = count, q = quality }
            end
        end
    end
    table.sort(list, function(a, b) return a.e < b.e end)
    me.items = me.items or {}
    me.mail, me.items.mail = counts, items
    me.mailSeen = now
    me.mailbox = {
        seen = now, count = math.max(shown, total), unread = unread, money = money, cod = cod,
        expires = minDays and (now + minDays * 86400) or nil,
        list = list, more = math.max(0, total - shown),
    }
    Core.Fire("MAILBOX_SCANNED", me.mailbox)
end

---------------------------------------------------------------------------
-- Ablaufende Post
---------------------------------------------------------------------------

local DEFAULT_WARN_DAYS = 3

function Mail.WarnDays()
    local db = Core.db
    local days = type(db) == "table" and type(db.mail) == "table" and Core.Num(db.mail.warnDays)
    return days and days >= 1 and days or DEFAULT_WARN_DAYS
end

function Mail.SetWarnDays(days)
    days = Core.Num(days)
    if not days or type(Core.db) ~= "table" then return end
    days = math.max(1, math.min(30, floor(days + 0.5)))
    Core.db.mail = Core.db.mail or {}
    Core.db.mail.warnDays = days
    Core.Fire("MAIL_WARN_DAYS_CHANGED", days)
end

local function Mailbox(key)
    local chars = Core.Chars and Core.Chars()
    local c = type(chars) == "table" and chars[key]
    local box = type(c) == "table" and c.mailbox
    return type(box) == "table" and type(box.list) == "table" and box or nil
end

function Mail.Expiring(key, days, all)
    local box = Mailbox(key)
    if not box then return nil end
    local now = time()
    local window = (Core.Num(days) or Mail.WarnDays()) * 86400
    local out = { count = 0, deleting = 0, expired = 0, seen = box.seen, more = box.more }
    for _, entry in ipairs(box.list) do
        local e = Core.Num(entry.e)
        if e and e <= now then
            out.expired = out.expired + 1
        elseif e and (all or e - now < window) then
            out.count = out.count + 1
            out.first = out.first and math.min(out.first, e) or e
            if entry.d and e - now < window then out.deleting = out.deleting + 1 end
        end
    end
    return out
end

function Mail.ExpiringAll(days, all)
    local rows = {}
    for key in pairs(Core.Chars and Core.Chars() or {}) do
        local info = Mail.Expiring(key, days, all)
        if info and (info.count > 0 or info.expired > 0) then
            info.key = key
            rows[#rows + 1] = info
        end
    end
    table.sort(rows, function(a, b)
        if (a.first ~= nil) ~= (b.first ~= nil) then return a.first ~= nil end
        if a.first and b.first and a.first ~= b.first then return a.first < b.first end
        return tostring(a.key) < tostring(b.key)
    end)
    return rows
end

function Mail.ForgetExpired(key)
    local box = Mailbox(key)
    if not box then return 0 end
    local now, keep, n = time(), {}, 0
    for _, entry in ipairs(box.list) do
        local e = Core.Num(entry.e)
        if e and e <= now then n = n + 1 else keep[#keep + 1] = entry end
    end
    if n > 0 then box.list = keep end
    return n
end

-- Briefkasten-Stand eines Charakters vergessen (Kopfdaten und Ablaufzeiten, chars[key].mailbox). Der Charakter
-- und seine gezählten Gegenstände in der Post bleiben. Rückgabe: true, wenn ein Stand da war.
-- Nachricht MAILBOX_FORGOTTEN (key).
function Mail.ForgetMailbox(key)
    local chars = Core.Chars and Core.Chars()
    local c = type(key) == "string" and type(chars) == "table" and chars[key]
    if type(c) ~= "table" or c.mailbox == nil then return false end
    c.mailbox = nil
    Core.Fire("MAILBOX_FORGOTTEN", key)
    return true
end

local function ScheduleScan(delay)
    if scanPending then return end
    scanPending = true
    C_Timer.After(delay or 0.5, function()
        scanPending = false
        local ok, err = pcall(Mail.Scan)
        if not ok then Core.Error(Core.name, err, "Mail.Scan") end
    end)
end

-- Erst nach MAIL_INBOX_UPDATE erfassen: beim Öffnen ist der Posteingang oft noch leer.
local inboxLoaded = false

ns.On("MAIL_SHOW", function()
    isOpen, openedAt, inboxLoaded = true, GetTime(), false
    Core.Fire("MAILBOX_OPENED")
end)

ns.On("MAIL_INBOX_UPDATE", function()
    if not isOpen then return end
    inboxLoaded = true
    ScheduleScan(0.5)
end)

ns.On("MAIL_CLOSED", function()
    if isOpen and inboxLoaded then
        local ok, err = pcall(Mail.Scan)   -- letzter Stand, solange die Daten noch da sind
        if not ok then Core.Error(Core.name, err, "Mail.Scan") end
    end
    isOpen, inboxLoaded = false, false
    Core.Fire("MAILBOX_CLOSED")
end)
