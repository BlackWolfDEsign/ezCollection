local ADDON, ns = ...
local L = ns.L
local Conv = ns.Conv

-- Briefe: wartende Nachrichten beim Besuch am Briefkasten als reinen Textbrief
-- senden (kommt sofort an) und eingehende [ezChat]-Briefe ins Gespräch übernehmen.

local Mail = {}
ns.Mail = Mail

local MAX_BODY = 480        -- Brieftext höchstens 500 Zeichen, etwas Reserve
local SUBJECT_TEXT = 40     -- Vorschau im Betreff (Bytes)
local LETTER_DAYS = 30      -- Laufzeit eines Briefs ohne Anhang

---------------------------------------------------------------------------
-- Briefversand: ezCores gemeinsame Versand-Warteschlange (ezCore/MailQueue.lua)
--
-- Gesendet wird nur bei offenem Postfenster und leerem Senden-Formular (kein Betreff, Text,
-- Anhang oder Geld), nacheinander mit Pause und nie während ezMail nachsendet. Ein nur
-- vorbelegter Empfänger stört nicht mehr: ezCore trägt ihn nach dem Senden wieder ein.
---------------------------------------------------------------------------

local MailQueue, CoreMail = ezCore.MailQueue, ezCore.Mail

-- SendLetter(to, subject, body, callback): callback(ok, reason); reason = Fehlermeldung des Spiels
-- oder "closed", "money", "timeout", "blocked", "error".
local SendLetter = MailQueue.SendLetter
local MailboxOpen = CoreMail.IsOpen
local MailboxOpenSince = CoreMail.OpenSince
local function FormIdle() return CoreMail.FormIdle(true) end

---------------------------------------------------------------------------
-- Offline-Nachrichten als Brief
---------------------------------------------------------------------------

local inFlight = {}     -- [Nachricht] = true: steckt gerade in der Briefwarteschlange
local warned = {}       -- einmalige Hinweise je Besuch am Briefkasten
local stopped = false   -- für diesen Besuch nicht mehr automatisch senden

local FATAL = {}
for _, name in ipairs({ "ERR_MAIL_TARGET_NOT_FOUND", "ERR_MAIL_TO_SELF", "ERR_PLAYER_WRONG_FACTION", "ERR_MAIL_WRONG_FACTION" }) do
    if type(_G[name]) == "string" then FATAL[_G[name]] = true end
end

function Mail.IsInFlight(msg)
    return inFlight[msg] == true
end

local function Line(msg)
    return ("[%s] %s"):format(ns.TimeText(msg.t), ns.PlainText(msg.m))
end

-- Wartende Nachrichten je Empfänger, aufgeteilt in Briefe mit höchstens MAX_BODY Zeichen.
local function Batches()
    local list = {}
    if not ns.C then return list end
    for key, convo in pairs(ns.C.convos) do
        if not convo.bn then
            local chunk, length = {}, 0
            for _, msg in ipairs(convo.msgs) do
                if msg.o and msg.s == "q" and not inFlight[msg] and not ns.Delivery.IsPending(msg) then
                    local size = #Line(msg) + 1
                    if #chunk > 0 and length + size > MAX_BODY then
                        list[#list + 1] = { key = key, convo = convo, msgs = chunk }
                        chunk, length = {}, 0
                    end
                    chunk[#chunk + 1] = msg
                    length = length + size
                end
            end
            if #chunk > 0 then list[#list + 1] = { key = key, convo = convo, msgs = chunk } end
        end
    end
    return list
end

function Mail.CountLetters()
    return #Batches()
end

local function Compose(msgs)
    if #msgs == 1 then
        local text = ns.PlainText(msgs[1].m)
        local preview = ns.Truncate((text:gsub("[\r\n]+", " ")), SUBJECT_TEXT)
        if ns.Trim(preview) == "" then preview = L.MAIL_SUBJECT_ONE end
        return ns.TAG .. " " .. preview, text
    end
    local lines = {}
    for i, msg in ipairs(msgs) do lines[i] = Line(msg) end
    return ns.TAG .. " " .. L.MAIL_SUBJECT_MANY:format(#msgs), table.concat(lines, "\n")
end

local function WarnOnce(reason, text)
    if warned[reason] then return end
    warned[reason] = true
    ns.Print(text)
end

local function OnLetterDone(batch, ok, reason)
    local changed = false
    for _, msg in ipairs(batch.msgs) do
        inFlight[msg] = nil
        if msg.s == "q" then
            if ok then
                msg.s, msg.v, msg.d = nil, "p", time()
                changed = true
            elseif reason and FATAL[reason] then
                msg.s = "x"   -- Empfänger gibt es nicht o. Ä.: nicht zustellbar
                changed = true
            end
        end
    end
    if changed then Conv.Changed(batch.key) end

    local name = ns.Short(batch.convo.name)
    if ok then
        ns.Print(L.MAIL_SENT:format(#batch.msgs, name))
    elseif reason == "closed" then
        return   -- beim nächsten Besuch weiter
    elseif reason == "money" then
        stopped = true
        WarnOnce(reason, L.MAIL_NO_MONEY)
    elseif reason == "blocked" then
        stopped = true
        WarnOnce(reason, L.MAIL_BLOCKED)
    elseif reason == "timeout" then
        stopped = true
        WarnOnce(reason, L.MAIL_FAILED:format(name, L.MAIL_TIMEOUT))
    else
        ns.Print(L.MAIL_FAILED:format(name, reason or "?"))
    end
end

local function Submit(manual)
    if not (ns.C and MailboxOpen()) then return end
    -- ohne „Offline-Nachrichten“ kein Brief von selbst, auch für schon Wartendes (code-reviewer 20.11.2026)
    if not manual and (stopped or not ns.S.mailDelivery or not ns.S.offlineQueue) then return end
    for _, batch in ipairs(Batches()) do
        -- Forever: ohne Nachnamen kommt kein Brief an, lieber warten, bis er bekannt ist.
        if not ns.MissingSurname(batch.convo.name) then
            for _, msg in ipairs(batch.msgs) do inFlight[msg] = true end
            local subject, body = Compose(batch.msgs)
            SendLetter(ns.TellName(batch.convo.name), subject, body, function(ok, reason)
                OnLetterDone(batch, ok, reason)
            end)
        end
    end
end

-- Gesammelt senden: Postfenster öffnen und neue Nachrichten lösen Submit nur einmal aus.
local SubmitSoon = ns.Throttle(function() Submit() end, 1.5)

-- /ezchat post: von Hand anstoßen (z. B. wenn automatisches Senden blockiert wurde).
function Mail.SendNow()
    if not MailboxOpen() then return ns.Print(L.MAIL_NOT_OPEN) end
    if Mail.CountLetters() == 0 then return ns.Print(L.MAIL_NOTHING) end
    if not FormIdle() then ns.Print(L.MAIL_FORM_BUSY) end
    stopped = false
    wipe(warned)
    Submit(true)
end

ns.On("MAIL_SHOW", function()
    stopped = false
    wipe(warned)
    SubmitSoon()
end)

-- Hinweis am Briefkasten, solange „Als Brief am Briefkasten senden“ aus ist (ezCores Hinweis-Helfer, einmal je
-- Account; Antwort des Nutzers vom 17.11.2026: ab Werk aus, mit Hinweis und Knopf „Einschalten“). Gilt nur mit
-- eingeschalteter Warteschlange für Offline-Nachrichten. Für die beim Update umgestellten (ns.MigrateMailOptIn) sagt
-- der Hinweis das dazu.
function Mail.RegisterOptInHint()
    local Hint = ezCore.OptInHint
    if not (Hint and Hint.Register) then return false end
    return Hint.Register("ezChat.mailDelivery", {
        owner = ADDON,
        window = "mail",
        label = function() return L.OPT_mailDelivery end,
        what = function() return L.OPTIN_mailDelivery end,
        isOn = function() return ns.S ~= nil and ns.S.mailDelivery == true end,
        enable = function()
            ns.SetSetting("mailDelivery", true)
            return ns.S.mailDelivery == true
        end,
        applies = function() return ns.S ~= nil and ns.S.offlineQueue == true end,
        switchedOff = function()
            return type(ns.db) == "table" and type(ns.db.migrated) == "table" and ns.db.migrated.mailOff28Was == true
        end,
    })
end
Mail.RegisterOptInHint()

-- Neue wartende Nachricht, während das Postfenster offen ist.
Conv.OnChange(function()
    if MailboxOpen() and not stopped and ns.S.mailDelivery and ns.S.offlineQueue then SubmitSoon() end
end)

---------------------------------------------------------------------------
-- Eingehende [ezChat]-Briefe
---------------------------------------------------------------------------

local function ImportInbox()
    if not (ns.C and ns.S.mailImport and MailboxOpen() and GetInboxNumItems and GetInboxText) then return end
    local shown, total = GetInboxNumItems()
    shown = shown or 0
    local seen = ns.C.mailSeen
    local found, imported = {}, 0
    local now = time()

    for i = 1, shown do
        -- Kopfdaten aus ezCore; solange Blizzard den Absender noch nicht kennt, steht dort UNKNOWN: auslassen.
        local h = ezCore.Mail.Header(i)
        local sender, subject, daysLeft = h and h.sender, h and h.subject, h and h.daysLeft
        if h and ns.Usable(subject, sender) and sender ~= (UNKNOWN or "?") and subject:sub(1, #ns.TAG) == ns.TAG
            and h.items == 0 and h.money == 0 and h.cod == 0 then
            local body = GetInboxText(i)
            if type(body) == "string" and ns.Usable(body) then
                local id = sender .. "\031" .. subject .. "\031" .. body
                found[id] = (found[id] or 0) + 1
                local entry = seen[id]
                if not entry or found[id] > (entry.n or 0) then
                    ns.NoteRaw("mail", sender)
                    local full = ns.FullName(sender)
                    if full then
                        full = ns.CompleteName(full)
                        local age = math.floor((LETTER_DAYS - (tonumber(daysLeft) or LETTER_DAYS)) * 86400)
                        Conv.Add(full, false, { t = now - math.max(0, age), m = body, v = "p" })
                        imported = imported + 1
                    end
                    seen[id] = { n = found[id], t = now }
                else
                    entry.t = now
                end
            end
        end
    end

    -- Gelöschte Briefe vergessen, aber nur wenn das ganze Postfach sichtbar und geladen ist.
    if (MailboxOpenSince() or 0) > 3 and (total or shown) <= shown then
        for id in pairs(seen) do
            if not found[id] then seen[id] = nil end
        end
    end
    if imported > 0 then ns.Print(L.MAIL_IMPORTED:format(imported)) end
end

local ImportSoon = ns.Throttle(function() ImportInbox() end, 0.5)
ns.On("MAIL_INBOX_UPDATE", function() ImportSoon() end)

ns.OnReady(function()
    -- Einträge zu Briefen, die längst abgelaufen sein müssen, aufräumen.
    local limit = time() - (LETTER_DAYS + 5) * 86400
    for id, entry in pairs(ns.C.mailSeen) do
        if (entry.t or 0) < limit then ns.C.mailSeen[id] = nil end
    end
end)
