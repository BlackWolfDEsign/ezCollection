local _, ns = ...
local L = ns.L

--[[
    Post-Aktionen nacheinander ausführen: Briefe öffnen (alles nehmen), zurückschicken oder löschen.
    Immer nur eine Aktion, dann eine kleine Pause und warten, bis der Server fertig ist –
    sonst drosselt er und Aktionen gehen verloren.

    Arten:
      "open" ohne Ziele  → gefiltertes „Alle öffnen“ (Filter aus den Einstellungen, Absender-Regeln)
      "auto"             → Einsammeln beim Öffnen des Briefkastens (Express.lua): Gold, AH-Verkäufe,
                           AH-Käufe, vertraute Absender – je nach Einstellung
      "open" mit Zielen  → ausgewählte Briefe öffnen
      "return" mit Zielen → ausgewählte Briefe zurückschicken
      "delete" mit Zielen → gelesene Briefe ohne Inhalt löschen (nie etwas mit Gold oder Gegenständen)
]]

local Runner = {}
ns.Runner = Runner

local STEP_DELAY = 0.3          -- Pause zwischen zwei Post-Aktionen
local PENDING_DELAY = 0.1       -- erneut prüfen, solange der Server noch arbeitet
local PENDING_TIMEOUT = 15      -- antwortet der Server so lange nicht, wird abgebrochen
local WAIT_MORE_TIMEOUT = 75    -- so lange auf nachgeladene Briefe warten (Server lädt höchstens alle 60 s nach)
local MAX_ATTEMPTS = 3          -- danach wird eine Aktion übersprungen
local REPORT_DELAY = 1          -- Geldänderungen kommen etwas nach der letzten Aktion an

local run                       -- laufender eigener Auftrag
local blizzRun                  -- Blizzards eigenes „Alle öffnen“ läuft
local mailOpen = false

-- Zähler für die Zeit am Briefkasten. Sie kommen aus ezCores Verlauf (HISTORY_ADDED, unten): ezCore erfasst
-- jede Entnahme, auch Blizzards eigene (Shift-Klick, „Alle öffnen“), damit die Zusammenfassung stimmt.
local session = { money = 0, items = 0, reported = 0 }
local counted = setmetatable({}, { __mode = "k" })   -- je Verlaufseintrag: gezähltes Gold und Gegenstände
local lastTakeTime = 0
local lastItem, lastEntry

local driver = CreateFrame("Frame")
driver:Hide()

-- Wartet der Server noch auf die Antwort zu einem Post-Befehl? Eine Stelle in ezCore (Core.Mail.CommandPending, W-14).
local CommandPending = ezCore.Mail.CommandPending

local NumMails = ns.NumMails

local function CountKeys(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

function Runner.IsRunning() return run ~= nil end
function Runner.IsBusy() return run ~= nil or blizzRun ~= nil end

function Runner.ButtonText()
    if run and run.waitLeft then return L.BTN_WAIT:format(run.waitLeft) end
    return L.BTN_STOP
end

---------------------------------------------------------------------------
-- Zusammenfassung
---------------------------------------------------------------------------

local function Notes(r)
    if r.bagsFull then ns.Print(L.NOTE_BAGS_FULL) end
    -- Beim Einsammeln am Briefkasten nur das Nötigste: Nachnahme und GM-Post sieht man in der Liste.
    if r.kind == "auto" then return end
    local cod, gm, blocked = CountKeys(r.skipCOD), CountKeys(r.skipGM), CountKeys(r.skipRule)
    if cod > 0 then ns.Print(L.NOTE_COD:format(cod)) end
    if gm > 0 then ns.Print(L.NOTE_GM:format(gm)) end
    if blocked > 0 then ns.Print(L.NOTE_RULES:format(blocked)) end
    if r.timedOut and r.moreLeft and r.moreLeft > 0 then ns.Print(L.NOTE_MORE:format(r.moreLeft)) end
end

local function Report(money, items, mails, quiet)
    money, items = math.max(0, money or 0), math.max(0, items or 0)
    session.reported = session.reported + money
    if not ns.S.summary then return end
    if money == 0 and items == 0 then
        if not quiet then ns.Print(L.SUMMARY_NOTHING) end
        return
    end
    local parts = {}
    if money > 0 then parts[#parts + 1] = ns.CoinText(money) end
    if items > 0 then parts[#parts + 1] = L.ITEMS:format(items) end
    local what = table.concat(parts, L.AND)
    if mails and mails > 0 then
        ns.Print(L.SUMMARY:format(what, mails))
    else
        ns.Print(L.SUMMARY_SHORT:format(what))
    end
end

---------------------------------------------------------------------------
-- Nächste Aktion finden
---------------------------------------------------------------------------

-- Was ist an diesem Brief als Nächstes zu tun? Nachnahme und GM-Post nie automatisch.
local function ContentAction(index, h, moneyOnly)
    local sig = ns.Signature(h)
    if h.cod > 0 then
        run.skipCOD[sig .. h.items] = true
        return nil
    end
    if h.gm then
        run.skipGM[sig] = true
        return nil
    end

    -- Schlüssel enthält den Inhalt: Klappt eine Aktion, ändert er sich und der Zähler beginnt neu.
    local base = index .. ":" .. sig .. ":" .. h.money .. ":" .. h.items .. ":"
    if h.money > 0 and (run.attempts[base .. "m"] or 0) < MAX_ATTEMPTS then
        return "money", nil, base .. "m"
    end
    if h.items > 0 and not moneyOnly then
        if ns.FreeBagSlots() <= (ns.S.keepFree or 0) then
            run.bagsFull = true
            return nil
        end
        for attachment = ATTACHMENTS_MAX_RECEIVE or 16, 1, -1 do
            if HasInboxItem(index, attachment) then
                local _, itemID = GetInboxItem(index, attachment)
                local key = base .. attachment
                if not (itemID and run.failed[itemID]) and (run.attempts[key] or 0) < MAX_ATTEMPTS then
                    return "item", attachment, key
                end
            end
        end
    end
    return nil
end

-- Gefiltertes „Alle öffnen“: Brief öffnen? Zweiter Wert: nur Gold nehmen.
-- Absender mit Regel „auslassen“ oder „zurückschicken“ bleiben liegen, vertraute auch ohne „Alle anderen“.
function Runner.WantedOpen(h)
    if ns.Rules.IsBlocked(h.sender) then return false, nil, true end
    local category = ns.MailCategory(h.subject)
    local wanted
    if category == "ahSold" then
        wanted = ns.S.openAHSold
    elseif category == "ahWon" then
        wanted = ns.S.openAHWon
    elseif category == "ahReturned" then
        wanted = ns.S.openAHReturned
    else
        wanted = ns.S.openOther or (ns.S.openTrusted and ns.Rules.IsTrusted(h.sender))
    end
    return wanted and true or false, ns.S.moneyOnly
end

-- Einsammeln beim Öffnen des Briefkastens (Auto-Express). Gegenstände nur aus AH-Käufen und von
-- vertrauten Absendern; Nachnahme, GM-Post und frei gehaltene Taschenplätze wie beim Öffnen.
function Runner.WantedAuto(h)
    if ns.Rules.IsBlocked(h.sender) then return false, nil, true end
    local category = ns.MailCategory(h.subject)
    if category == "ahWon" and ns.S.autoAHWon then return true, false end
    if category == "ahSold" then return ns.S.autoAHSold and h.money > 0, true end
    if category == "other" and ns.S.autoTrusted and ns.Rules.IsTrusted(h.sender) then return true, false end
    return ns.S.autoMoney and h.money > 0, true
end

-- Gefiltert: von hinten nach vorn, damit gelöschte Briefe die übrigen Plätze nicht verschieben.
local function NextFiltered()
    local n = NumMails()
    local pick = run.kind == "auto" and Runner.WantedAuto or Runner.WantedOpen
    for index = n, 1, -1 do
        local h = ns.Header(index)
        if h then
            local wanted, moneyOnly, blocked = pick(h)
            if blocked then run.skipRule[ns.Signature(h)] = true end
            if wanted then
                local action, attachment, key = ContentAction(index, h, moneyOnly)
                if action then return action, index, attachment, key, h end
            end
        end
    end
end

-- Ausgewählt: Ziele sind absteigend sortiert, jeder Brief wird ganz geleert, dann der nächste.
local function NextSelected()
    local n = NumMails()
    while run.pos <= #run.targets do
        local t = run.targets[run.pos]
        local h = t.index <= n and ns.Header(t.index) or nil
        -- Anderer Brief auf dem Platz (Original gelöscht) oder mehr Inhalt als vorher: erledigt.
        if not h or ns.Signature(h) ~= t.sig or h.money > t.money or h.items > t.items then
            run.pos = run.pos + 1
        else
            t.money, t.items = h.money, h.items
            local action, attachment, key = ContentAction(t.index, h, false)
            if action then return action, t.index, attachment, key, h end
            run.pos = run.pos + 1
        end
    end
end

local function NextReturn()
    local n = NumMails()
    while run.pos <= #run.targets do
        local t = run.targets[run.pos]
        run.pos = run.pos + 1
        local h = t.index <= n and ns.Header(t.index) or nil
        if h and ns.Signature(h) == t.sig then
            if InboxItemCanDelete(t.index) then
                run.notReturnable = run.notReturnable + 1   -- Systempost oder schon zurückgeschickt
            else
                return "return", t.index
            end
        end
    end
end

local function NextDelete()
    local n = NumMails()
    while run.pos <= #run.targets do
        local t = run.targets[run.pos]
        run.pos = run.pos + 1
        local h = t.index <= n and ns.Header(t.index) or nil
        -- Vor dem Löschen noch einmal prüfen: derselbe Brief und weiterhin ohne Inhalt.
        if h and ns.Signature(h) == t.sig and ns.IsEmptyRead(t.index, h) then
            return "delete", t.index
        end
    end
end

local function ReturnMail(index)
    -- Ist der Brief gerade offen, Blizzards eigenen Weg nehmen (schickt zurück und schließt das Fenster).
    local viaBlizzard = OpenMailFrame and OpenMailFrame:IsShown() and InboxFrame and InboxFrame.openMailID == index
        and ns.ReturnOpenMail()
    if not viaBlizzard then ReturnInboxItem(index) end
end

---------------------------------------------------------------------------
-- Ablauf
---------------------------------------------------------------------------

local function Step()
    local action, index, attachment, key, h
    if run.kind == "return" then
        action, index = NextReturn()
    elseif run.kind == "delete" then
        action, index = NextDelete()
    elseif run.targets then
        action, index, attachment, key, h = NextSelected()
    else
        action, index, attachment, key, h = NextFiltered()
    end

    if action then
        run.waitingSince, run.waitLeft = nil, nil
        run.acted = true
        if key then run.attempts[key] = (run.attempts[key] or 0) + 1 end
        if h then run.mails[ns.Signature(h) .. ":" .. floor(h.daysLeft * 1440)] = true end
        if action == "money" then
            TakeInboxMoney(index)
        elseif action == "item" then
            TakeInboxItem(index, attachment)
        elseif action == "return" then
            ReturnMail(index)
            run.returned = run.returned + 1
        elseif action == "delete" then
            DeleteInboxItem(index)
            run.deleted = run.deleted + 1
        end
        run.wait = STEP_DELAY
        return
    end

    -- Nichts mehr zu tun. Hat der Server noch Briefe, die Blizzard gleich nachlädt?
    local n, total = NumMails()
    -- Einsammeln beim Öffnen wartet nicht auf nachgeladene Briefe (dafür gibt es „Alle öffnen“).
    if run.kind == "open" and not run.targets and run.acted and total > n then
        run.waitingSince = run.waitingSince or ezCore.Uptime()
        local left = WAIT_MORE_TIMEOUT - (ezCore.Uptime() - run.waitingSince)
        if left > 0 then
            local shown = math.ceil(left)
            if shown ~= run.waitLeft then
                run.waitLeft = shown
                ns.Fire("RUN_CHANGED")
            end
            run.wait = 1
            return
        end
        run.timedOut = true
        run.moreLeft = total - n
    end
    Runner.Finish()
end

driver:SetScript("OnUpdate", function(self, elapsed)
    if not run then
        self:Hide()
        return
    end
    if not (MailFrame and MailFrame:IsShown()) then
        Runner.Finish(true)
        return
    end
    run.wait = run.wait - elapsed
    if run.wait > 0 then return end
    if CommandPending() then
        -- Antwortet der Server gar nicht mehr, lieber aufhören als ewig warten.
        run.pendingSince = run.pendingSince or ezCore.Uptime()
        if ezCore.Uptime() - run.pendingSince > PENDING_TIMEOUT then
            Runner.Finish(true)
            return
        end
        run.wait = PENDING_DELAY
        return
    end
    run.pendingSince = nil
    local ok, err = pcall(Step)
    if not ok then
        geterrorhandler()(err)
        Runner.Finish()
    end
end)

-- opts.auto: von ezMail selbst beim Öffnen des Briefkastens gestartet (Meldungen mit Hinweis darauf).
function Runner.Start(kind, targets, opts)
    if run or blizzRun then return false end
    if not (MailFrame and MailFrame:IsShown()) then
        if not (opts and opts.auto) then ns.Print(L.NEED_MAILBOX) end
        return false
    end
    if targets and #targets == 0 then return false end

    -- Ein offener Brief würde beim Schließen auf einen verschobenen Platz zeigen: vorher zu.
    -- Über ezCore (eine Stelle für Blizzards Fenster): im Kampf bleibt er still offen wie bisher.
    if OpenMailFrame and OpenMailFrame:IsShown() then ezCore.ClosePanel("openmail", nil, true) end

    run = {
        kind = kind,
        targets = targets,
        pos = 1,
        wait = 0,
        money = session.money,
        items = session.items,
        mails = {},
        attempts = {},
        failed = {},
        skipCOD = {},
        skipGM = {},
        skipRule = {},
        auto = opts and opts.auto or nil,
        returned = 0,
        notReturnable = 0,
        deleted = 0,
    }
    driver:Show()
    ns.Fire("RUN_CHANGED")
    return true
end

function Runner.Stop()
    if run then Runner.Finish(true) end
end

function Runner.Finish(stopped)
    local r = run
    if not r then return end
    run = nil
    driver:Hide()
    Runner.lastStopped = stopped and true or false   -- Express.lua: nach „Stopp“ nichts mehr automatisch

    if r.kind == "return" then
        ns.Print((r.auto and L.RETURN_DONE_RULES or L.RETURN_DONE):format(r.returned))
        if r.notReturnable > 0 then ns.Print(L.RETURN_SKIPPED:format(r.notReturnable)) end
    elseif r.kind == "delete" then
        ns.Print(L.DELETE_DONE:format(r.deleted))
    else
        if stopped then ns.Print(L.STOPPED) end
        -- Beim Anhalten sofort abrechnen (sonst zählte ein übernehmendes Blizzard-Öffnen mit),
        -- sonst kurz warten, bis das Gold der letzten Aktion angekommen ist.
        local function Done()
            Report(session.money - r.money, session.items - r.items, CountKeys(r.mails), r.kind == "auto")
            Notes(r)
        end
        if stopped then Done() else C_Timer.After(REPORT_DELAY, Done) end
    end
    if r.targets and ns.Inbox then ns.Inbox.ClearSelection() end
    ns.Fire("RUN_CHANGED")
end

---------------------------------------------------------------------------
-- Mitzählen (auch Blizzards eigene Aktionen) über ezCores Verlauf
---------------------------------------------------------------------------

-- ezCore erfasst jede Entnahme aus dem Posteingang einmal je Brief und Anhang (hooksecurefunc auf
-- TakeInboxMoney, TakeInboxItem, AutoLootMailItem) und meldet sie als HISTORY_ADDED ("mail", dir = "in").
-- Lehnt der Server einen Anhang ab (MAIL_FAILED), nimmt ezCore die Entnahme zurück: HISTORY_REMOVED, oder
-- es streicht nur die Anhänge, wenn Gold dabei war. Die Zusammenfassung folgt dem Verlauf in beiden Fällen.
-- ezMail hängt sich nicht mehr selbst an die Entnahmen.
local function ItemCount(entry)
    local count = 0
    if type(entry.items) == "table" then
        for _, item in ipairs(entry.items) do count = count + (ezCore.Num(item.c) or 1) end
    end
    return count
end

-- Zähler an einen Eintrag angleichen, den ezCore gekürzt (removed = nil) oder entfernt hat (removed = true).
function Runner.Recount(entry, removed)
    local c = type(entry) == "table" and counted[entry]
    if not c then return end
    local money = removed and 0 or (ezCore.Num(entry.money) or 0)
    local items = removed and 0 or ItemCount(entry)
    session.money = math.max(0, session.money - (c.money - money))
    session.items = math.max(0, session.items - (c.items - items))
    c.money, c.items = money, items
    if removed then counted[entry] = nil end
end

function Runner.OnHistoryAdded(kind, entry)
    if kind ~= "mail" or type(entry) ~= "table" or entry.dir ~= "in" or not mailOpen then return end
    lastTakeTime = ezCore.Uptime()
    local money, count = ezCore.Num(entry.money) or 0, ItemCount(entry)
    session.money = session.money + money
    session.items = session.items + count
    counted[entry] = { money = money, items = count }
    lastEntry = entry
    -- Einzelner Anhang: merken, damit ein eigener Durchlauf ihn nach MAIL_FAILED nicht noch einmal versucht
    local items = type(entry.items) == "table" and entry.items or {}
    lastItem = #items == 1 and { id = items[1].i } or nil
end
ezCore.Listen("HISTORY_ADDED", Runner.OnHistoryAdded, ns.moduleName)
ezCore.Listen("HISTORY_REMOVED", function(kind, entry)
    if kind == "mail" then Runner.Recount(entry, true) end
end, ns.moduleName)

-- Blizzards „Alle öffnen“ bekommt dieselbe Zusammenfassung. Klickt man ihn, während ezMail
-- gefiltert öffnet, übernimmt Blizzard und ezMail hört auf.
ns.WhenMailUI("Zusammenfassung für „Alle öffnen“", function()
    local button = _G.OpenAllMail
    if not (button and button.StartOpening and button.StopOpening) then return end
    -- Startwerte vor dem Klick merken: Ist nichts zu tun, stoppt Blizzard noch innerhalb von StartOpening.
    button:HookScript("PreClick", function()
        if run then Runner.Finish(true) end
        if not blizzRun then blizzRun = { money = session.money, items = session.items } end
    end)
    hooksecurefunc(button, "StartOpening", function(self)
        if self:IsEnabled() then
            blizzRun = nil          -- schon wieder fertig, StopOpening hat bereits gemeldet
        elseif not blizzRun then
            blizzRun = { money = session.money, items = session.items }
        end
        ns.Fire("RUN_CHANGED")
    end)
    hooksecurefunc(button, "StopOpening", function()
        local b = blizzRun
        if not b then return end
        blizzRun = nil
        local bagsFull = ns.FreeBagSlots() == 0
        C_Timer.After(REPORT_DELAY, function()
            Report(session.money - b.money, session.items - b.items)
            if bagsFull then ns.Print(L.NOTE_BAGS_FULL) end
        end)
        ns.Fire("RUN_CHANGED")
    end)
end)

ns.On("MAIL_FAILED", function(_, itemID)
    local recent = ezCore.Uptime() - lastTakeTime <= 3
    if run and recent and (itemID or lastItem) then run.failed[itemID or lastItem.id] = true end
    lastItem = nil
    -- Hat ezCore beim selben Ereignis nur die Anhänge gestrichen (Gold kam an), danach angleichen.
    local entry = recent and lastEntry
    if entry then C_Timer.After(0, function() Runner.Recount(entry) end) end
end)

ns.On("MAIL_SHOW", function()
    mailOpen = true
    session.money, session.items, session.reported = 0, 0, 0
    counted, lastItem, lastEntry = setmetatable({}, { __mode = "k" }), nil, nil
end)

ns.On("MAIL_CLOSED", function()
    if not mailOpen then return end
    mailOpen = false
    if run then Runner.Finish(true) end
    blizzRun = nil
    -- Gesamtsumme nur, wenn auch außerhalb der gemeldeten Durchläufe Gold kam.
    C_Timer.After(REPORT_DELAY + 0.5, function()
        if ns.S.summary and session.money > 0 and session.money > session.reported then
            ns.Print(L.SESSION_TOTAL:format(ns.CoinText(session.money)))
        end
    end)
end)
