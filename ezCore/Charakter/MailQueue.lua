local _, ns = ...
local Core = ezCore
local L = Core.L

--[[
    Eine Versand-Warteschlange für alle Module (vorher ezMail/SendQueue.lua und der Briefversand in
    ezChat/Mail.lua). Immer nur eine Aktion, dann warten, bis der Server fertig ist – so kommen sich
    Nachsenden (ezMail) und Offline-Briefe (ezChat) nie in die Quere.

    Anhänge (vorher ezMail):
      Queue.Attach(entries, done)                  hängt an, bis die Plätze voll sind;
                                                   done(übrig, stats { attached, failed, missing })
      Queue.Add(to, subject, body, entries, callback, owner)
                                                   verschickt alles in Briefen zu je 12 Stapeln;
                                                   callback(ok, verschickteBriefe, übrigeStapel)
      Einträge: { bag, slot, itemID, count = nil|n (nur genau so große Stapel), split = nil|n (erst abteilen) }
      Queue.IsBusy(), Queue.IsAttaching(), Queue.Progress(), Queue.Stop(), Queue.SendSlotsEmpty()

    Textbriefe (vorher ezChat):
      Queue.SendLetter(to, subject, body, callback)  reiht einen reinen Textbrief ein.
      Queue.SendMoney(to, copper, subject, body, callback)  dasselbe mit Gold (ohne eigene Rückfrage:
                                                   die stellt das aufrufende Modul, z. B. ezMail).
      callback(ok, reason): ok = true nach MAIL_SEND_SUCCESS. Sonst ist reason die Fehlermeldung des
      Spiels oder "closed", "money", "timeout", "blocked", "error".
      Sperre (ADDON_ACTION_BLOCKED/FORBIDDEN für SendMail): Textbriefe UND die Anhang-Schlange hören sofort auf
      (Grund "BLOCKED"; Prüfung auf Blizzards Regeln vom 17.11.2026, Risiko 10) – vorher wartete die Anhang-Schlange
      bis SEND_TIMEOUT (90 s).
      Gesendet wird nur bei offenem Postfenster, leerem Senden-Formular und ruhender Anhang-Warteschlange.
      Ein nur vorbelegter Empfänger (z. B. ezMails „letzten Empfänger eintragen“) stört nicht: er wird
      gemerkt und nach dem Senden wieder eingetragen.

    Nachricht MAIL_QUEUE_CHANGED bei jeder Änderung. owner: Modul-ns, dessen Print die Meldungen
    bekommt (Standard ezCore).
]]

local Queue = {}
Core.MailQueue = Queue

local ATTACH_DELAY = 0.15      -- Pause zwischen zwei Anhänge-Schritten
local LOCK_WAIT = 3            -- so lange auf einen gesperrten Gegenstand warten (nach dem Abteilen)
local CURSOR_WAIT = 3          -- hält der Spieler etwas am Mauszeiger, so lange warten
local LETTER_DELAY = 1         -- Pause zwischen zwei Briefen
local SEND_TIMEOUT = 90        -- Antwort des Servers (oder Bestätigung der Sicherheitsabfrage)
local TEXT_PAUSE = 2           -- Pause zwischen zwei Textbriefen
local TEXT_TIMEOUT = 15        -- Textbrief ohne Antwort: lieber nicht doppelt senden

local function Changed() Core.Fire("MAIL_QUEUE_CHANGED") end

local function MaxSend() return ATTACHMENTS_MAX_SEND or 12 end

-- Wartet der Server noch auf einen Post-Befehl? EINE Stelle: Core.Mail.CommandPending (Mail.lua)
local CommandPending = Core.Mail.CommandPending

local function SendFrameShown()
    return SendMailFrame ~= nil and SendMailFrame:IsVisible()
end

local function FreeSendSlots()
    local free = {}
    for i = 1, MaxSend() do
        if not HasSendMailItem(i) then free[#free + 1] = i end
    end
    return free
end

function Queue.SendSlotsEmpty()
    for i = 1, MaxSend() do
        if HasSendMailItem(i) then return false end
    end
    return true
end

-- Freier Platz in einer normalen Tasche (Berufstaschen nehmen nicht alles).
local function EmptyBagSlot(used)
    for bag = 0, Core.NumBagSlots() do
        local free, family = C_Container.GetContainerNumFreeSlots(bag)
        if (free or 0) > 0 and (family or 0) == 0 then
            for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
                if not used[bag * 1000 + slot] and not C_Container.GetContainerItemInfo(bag, slot) then
                    return bag, slot
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Anhängen
---------------------------------------------------------------------------

local attachJob

function Queue.IsAttaching() return attachJob ~= nil end

local function FinishAttach()
    local job = attachJob
    if not job then return end
    attachJob = nil
    if job.ticker then job.ticker:Cancel() end
    local left = {}
    for i = job.pos, #job.list do left[#left + 1] = job.list[i] end
    if job.done then ns.Try("Anhängen", job.done, left, job.stats) end
    Changed()
end

local function Skip(job, kind)
    job.stats[kind] = job.stats[kind] + 1
    job.pos = job.pos + 1
end

local function AttachStep()
    local job = attachJob
    if not job then return end
    if not SendFrameShown() then return FinishAttach() end
    if CursorHasItem() then
        job.cursorWait = job.cursorWait + ATTACH_DELAY
        if job.cursorWait > CURSOR_WAIT then FinishAttach() end
        return
    end
    job.cursorWait = 0

    local entry = job.list[job.pos]
    if not entry then return FinishAttach() end
    if job.unmailable[entry.itemID] then return Skip(job, "failed") end

    local info = C_Container.GetContainerItemInfo(entry.bag, entry.slot)
    if not (info and info.itemID == entry.itemID) then return Skip(job, "missing") end
    if info.isLocked then
        entry.waited = (entry.waited or 0) + ATTACH_DELAY
        if entry.waited > LOCK_WAIT then Skip(job, "missing") end
        return
    end

    if entry.split and entry.split >= (info.stackCount or 0) then
        entry.split = nil                 -- teilen nicht nötig: der Stapel ist schon klein genug
    end
    if entry.split then
        local bag, slot = EmptyBagSlot(job.used)
        if not bag then return Skip(job, "missing") end
        C_Container.SplitContainerItem(entry.bag, entry.slot, entry.split)
        C_Container.PickupContainerItem(bag, slot)
        if CursorHasItem() then
            ClearCursor()
            return Skip(job, "missing")
        end
        job.used[bag * 1000 + slot] = true
        entry.bag, entry.slot, entry.count, entry.split, entry.waited = bag, slot, entry.split, nil, 0
        return                            -- nächster Schritt hängt den neuen Stapel an, sobald er frei ist
    end
    if entry.count and info.stackCount ~= entry.count then return Skip(job, "missing") end

    local target = table.remove(job.free, 1)
    while target and HasSendMailItem(target) do target = table.remove(job.free, 1) end
    if not target then return FinishAttach() end   -- Plätze voll: Rest bleibt übrig

    C_Container.PickupContainerItem(entry.bag, entry.slot)
    if CursorHasItem() then
        ClickSendMailItemButton(target)
        if CursorHasItem() then
            ClearCursor()                  -- lässt sich nicht verschicken (z. B. gebunden): zurück in die Tasche
            table.insert(job.free, 1, target)
            job.unmailable[entry.itemID] = true
            return Skip(job, "failed")
        end
        job.stats.attached = job.stats.attached + 1
    end
    job.pos = job.pos + 1
end

-- Freie Anhangplätze werden zu Beginn reserviert: so wird nie ein belegter Platz getauscht.
function Queue.Attach(entries, done)
    if attachJob then return false end
    attachJob = {
        list = entries, pos = 1, done = done, free = FreeSendSlots(), used = {}, unmailable = {},
        cursorWait = 0, stats = { attached = 0, failed = 0, missing = 0 },
    }
    if #attachJob.free == 0 then
        FinishAttach()
        return true
    end
    Changed()
    AttachStep()
    if attachJob then attachJob.ticker = C_Timer.NewTicker(ATTACH_DELAY, AttachStep) end
    return true
end

---------------------------------------------------------------------------
-- Briefe mit Anhängen verschicken
---------------------------------------------------------------------------

local queue
local driver = CreateFrame("Frame")
driver:Hide()

function Queue.IsBusy() return queue ~= nil end

-- Laufender Brief und Gesamtzahl (für den Senden-Knopf).
function Queue.Progress()
    if not queue then return nil end
    return queue.sent + 1, queue.sent + math.ceil((#queue.list + queue.inLetter) / MaxSend())
end

-- Empfänger des laufenden Nachsendens (für Statuszeilen).
function Queue.Recipient()
    return queue and queue.to or nil
end

local PumpLetters

-- Grund für QUEUE_STOPPED: L.QUEUE_REASON_<Grund> (Kern/Locale.lua, deutsch und englisch; „BLOCKED“ = Sperre von
-- SendMail, Prüfung auf Blizzards Regeln vom 17.11.2026, Risiko 10), sonst der Grund selbst – etwa die Fehlermeldung
-- des Spiels.
local function ReasonText(reason)
    local key = "QUEUE_REASON_" .. tostring(reason)
    local text = L[key]
    if text == nil or text == key then text = tostring(reason) end
    return text
end

local function Finish(ok, reason)
    local q = queue
    if not q then return end
    queue = nil
    driver:Hide()
    if attachJob then
        attachJob.done = nil
        FinishAttach()
    end
    local left = #q.list
    local owner = q.owner or ns
    if ok then
        owner.Print(L.QUEUE_DONE:format(q.sent, q.to))
    else
        owner.Print(L.QUEUE_STOPPED:format(ReasonText(reason), q.sent, left + q.inLetter))
    end
    if q.skipped > 0 then owner.Print(L.QUEUE_SKIPPED:format(q.skipped)) end
    if q.callback then ns.Try("Nachsenden", q.callback, ok, q.sent, left) end
    Changed()
    PumpLetters(LETTER_DELAY)
end

local function NextLetter(q)
    if #q.list == 0 then return Finish(true) end
    if not SendFrameShown() and MailFrameTab_OnClick then MailFrameTab_OnClick(nil, 2) end
    if not SendFrameShown() then return Finish(false, "CLOSED") end
    -- Liegt schon etwas in den Anhangplätzen, käme es ungewollt mit: lieber anhalten.
    if not Queue.SendSlotsEmpty() then return Finish(false, "SLOTS") end

    local letter = {}
    while #letter < MaxSend() and #q.list > 0 do letter[#letter + 1] = table.remove(q.list, 1) end
    q.inLetter = #letter
    q.state = "attaching"
    Queue.Attach(letter, function(left, stats)
        if queue ~= q then return end
        -- Was nicht mehr passte, kommt in den nächsten Brief.
        for i = #left, 1, -1 do table.insert(q.list, 1, left[i]) end
        q.skipped = q.skipped + stats.failed + stats.missing
        q.inLetter = stats.attached
        if stats.attached > 0 then
            q.state = "send"
        elseif #left < #letter then
            q.state = "next"     -- diese Stapel waren weg oder nicht verschickbar: mit dem Rest weiter
        else
            Finish(false, "ATTACH")
        end
    end)
    Changed()
end

local textCurrent   -- Textbrief, auf dessen Antwort gerade gewartet wird

driver:SetScript("OnUpdate", function(_, elapsed)
    local q = queue
    if not q then return driver:Hide() end
    if not (MailFrame and MailFrame:IsShown()) then return Finish(false, "CLOSED") end
    q.wait = q.wait - elapsed
    if q.wait > 0 then return end

    if q.state == "next" then
        if CommandPending() or textCurrent then q.wait = 0.1 return end
        NextLetter(q)
    elseif q.state == "send" then
        if CommandPending() or CursorHasItem() then q.wait = 0.1 return end
        if SetSendMailCOD then SetSendMailCOD(0) end
        if SetSendMailMoney then SetSendMailMoney(0) end
        q.state = "waiting"
        q.since = GetTime()
        SendMail(q.to, q.subject, q.body)
        Changed()
    elseif q.state == "waiting" then
        if GetTime() - q.since > SEND_TIMEOUT then Finish(false, "TIMEOUT") end
        q.wait = 0.2
    end
end)

function Queue.Add(to, subject, body, entries, callback, owner)
    if queue or attachJob or not entries or #entries == 0 then return false end
    if not (MailFrame and MailFrame:IsShown()) then
        (owner or ns).Print(L.NEED_MAILBOX)
        return false
    end
    queue = {
        to = to, subject = subject, body = body or "", list = entries, callback = callback, owner = owner,
        sent = 0, inLetter = 0, skipped = 0, state = "next", wait = LETTER_DELAY,
    }
    driver:Show()
    Changed()
    return true
end

function Queue.Stop()
    if queue then Finish(false, "STOPPED") end
end

---------------------------------------------------------------------------
-- Textbriefe (vorher ezChat): nacheinander mit Pause, nur bei freiem Formular
---------------------------------------------------------------------------

local letters = {}          -- wartende Textbriefe { to, subject, body, callback }
local lastError
local busyUntil = 0
local pumpScheduled = false
local restoreName           -- vorbelegter Empfänger, der nach dem Senden zurück ins Feld kommt

function Queue.LettersWaiting() return #letters + (textCurrent and 1 or 0) end

-- Geht der gerade gesendete Brief auf einen Textbrief der Warteschlange zurück (nicht auf den Spieler)?
function Queue.IsSendingText() return textCurrent ~= nil end

local function Done(letter, ok, reason)
    if letter and type(letter.callback) == "function" then
        ns.Try("SendLetter", letter.callback, ok, reason)
    end
end

-- Alle wartenden Textbriefe mit Grund abbrechen (Postfenster zu, kein Geld, blockiert …).
-- V-025: Ein Goldbrief, der nicht hinausging, darf seinen Betrag nicht im Formular lassen – sonst meldet
-- Mail.FormIdle „belegt“ und die Textbriefe dahinter warten für immer.
local function ClearLetterMoney(letter)
    if letter and letter.money and type(SetSendMailMoney) == "function" then pcall(SetSendMailMoney, 0) end
end

local function FailAll(reason)
    local list, letter = letters, textCurrent
    letters, textCurrent = {}, nil
    ClearLetterMoney(letter)
    if letter then Done(letter, false, reason) end
    for _, item in ipairs(list) do Done(item, false, reason) end
    if letter or #list > 0 then Changed() end
end

local function RestoreName()
    local name = restoreName
    restoreName = nil
    local box = _G.SendMailNameEditBox
    if name and box and Core.Mail.FieldText(box) == "" and not (box.HasFocus and box:HasFocus()) then
        box:SetText(name)
    end
end

local function Pump()
    if not Core.Mail.IsOpen() or textCurrent or #letters == 0 then return end
    local wait = busyUntil - GetTime()
    if wait > 0 then return PumpLetters(wait + 0.1) end
    -- Nachsenden mit Anhängen hat Vorrang.
    if queue or attachJob or CommandPending() then return PumpLetters(1) end
    if not Core.Mail.FormIdle(true) then return PumpLetters(3) end
    local price = Core.Mail.Postage()   -- eine Stelle fürs Porto (V-062)
    local nextMoney = letters[1].money or 0
    if GetMoney() < price + nextMoney then
        if nextMoney > 0 then
            -- nur dieser Goldbrief scheitert; Textbriefe danach laufen weiter
            Done(table.remove(letters, 1), false, "money")
            Changed()
            return PumpLetters(0.1)
        end
        return FailAll("money")
    end

    local letter = table.remove(letters, 1)
    if letter.money then
        local okMoney, set = pcall(SetSendMailMoney, letter.money)
        if not okMoney or set == false then
            pcall(SetSendMailMoney, 0)
            Done(letter, false, "money")
            Changed()
            return PumpLetters(0.1)
        end
    end
    textCurrent, lastError = letter, nil
    local nameText = Core.Mail.FieldText(_G.SendMailNameEditBox)
    restoreName = nameText ~= "" and nameText or nil
    local ok, err = pcall(SendMail, letter.to, letter.subject, letter.body)
    if not ok then
        if letter.money then pcall(SetSendMailMoney, 0) end
        textCurrent = nil
        restoreName = nil
        ns.Error(err, "SendLetter")
        Done(letter, false, "error")
        busyUntil = GetTime() + TEXT_PAUSE
        return PumpLetters(TEXT_PAUSE + 0.1)
    end
    Changed()
    -- Keine Antwort vom Server: lieber nicht doppelt senden, für diesen Besuch aufhören.
    C_Timer.After(TEXT_TIMEOUT, function()
        if textCurrent == letter then FailAll("timeout") end
    end)
end

PumpLetters = function(delay)
    if pumpScheduled or #letters == 0 then return end
    pumpScheduled = true
    C_Timer.After(delay or 0.5, function()
        pumpScheduled = false
        local ok, err = pcall(Pump)
        if not ok then ns.Error(err, "SendLetter") end
    end)
end

function Queue.SendLetter(to, subject, body, callback, money)
    if not Core.Mail.IsOpen() or type(SendMail) ~= "function" then
        Done({ callback = callback }, false, "closed")
        return
    end
    letters[#letters + 1] = { to = to, subject = subject, body = body, callback = callback, money = money }
    Changed()
    PumpLetters(0.1)
end

-- Gold verschicken (Kupfer, ganze Zahl > 0). Die Rückfrage stellt das aufrufende Modul vorher selbst.
function Queue.SendMoney(to, copper, subject, body, callback)
    copper = Core.Num(copper)
    if not copper or copper <= 0 or copper ~= math.floor(copper) or type(SetSendMailMoney) ~= "function" then
        Done({ callback = callback }, false, "money")
        return
    end
    Queue.SendLetter(to, subject or "", body or "", callback, copper)
end

---------------------------------------------------------------------------
-- Antworten des Servers: erst das Nachsenden, dann die Textbriefe
---------------------------------------------------------------------------

ns.On("MAIL_SEND_SUCCESS", function()
    local q = queue
    if q and q.state == "waiting" then
        q.sent = q.sent + 1
        q.inLetter = 0
        q.state = "next"
        q.wait = LETTER_DELAY
        Changed()
        return
    end
    if textCurrent then
        local letter = textCurrent
        textCurrent = nil
        busyUntil = GetTime() + TEXT_PAUSE
        C_Timer.After(0, RestoreName)   -- Blizzard leert das Formular nach dem Senden
        Done(letter, true)
        Changed()
        PumpLetters(TEXT_PAUSE + 0.1)
    end
end)

ns.On("MAIL_FAILED", function()
    if queue and queue.state == "waiting" then return Finish(false, "FAILED") end
    if textCurrent then
        local letter = textCurrent
        textCurrent = nil
        ClearLetterMoney(letter)
        busyUntil = GetTime() + TEXT_PAUSE
        C_Timer.After(0, RestoreName)
        Done(letter, false, lastError or "error")
        Changed()
        PumpLetters(TEXT_PAUSE + 0.1)
    end
end)

ns.On("UI_ERROR_MESSAGE", function(_, _, message)
    if textCurrent and type(message) == "string" and Core.Usable(message) then lastError = message end
end)

Core.Listen("MAILBOX_CLOSED", function()
    if queue then Finish(false, "CLOSED") end
    if attachJob then FinishAttach() end
    restoreName = nil
    FailAll("closed")
end)

-- Blockiert das Spiel SendMail für ein Addon, warten dessen Textbriefe auf einen Tastendruck. Die Anhang-Schlange hört
-- ebenso sofort auf (Risiko 10 der Prüfung vom 17.11.2026; damit auch ezCrafts „Alle verschicken“, Risiko 23): kein
-- weiterer Brief ohne neuen Klick, Meldung mit dem Grund L.QUEUE_REASON_BLOCKED (Kern/Locale.lua).
local function OnBlocked(_, addon, func)
    if addon ~= Core.name then return end
    if func and not tostring(func):find("SendMail", 1, true) then return end
    if queue then Finish(false, "BLOCKED") end
    if textCurrent or #letters > 0 then FailAll("blocked") end
end
ns.On("ADDON_ACTION_BLOCKED", OnBlocked)
ns.On("ADDON_ACTION_FORBIDDEN", OnBlocked)

-- Eine Statuszeile (z. B. für /ezm status).
function Queue.StatusLine()
    if queue then
        local current, total = Queue.Progress()
        return L.STATUS_QUEUE:format(L.STATUS_QUEUE_RUNNING:format(current, total, queue.to))
    end
    local text = attachJob and L.STATUS_QUEUE_ATTACHING or L.STATUS_QUEUE_IDLE
    if Queue.LettersWaiting() > 0 then text = text .. ", " .. L.STATUS_QUEUE_LETTERS:format(Queue.LettersWaiting()) end
    return L.STATUS_QUEUE:format(text)
end
