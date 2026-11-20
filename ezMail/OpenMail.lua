local _, ns = ...
local L = ns.L
local Menu = ezCore.Menu     -- Menüs an einer Stelle (Blizzards MenuUtil)

--[[
    Offener Brief:
    - Knopf „Alles nehmen“ links in Blizzards Knopfreihe ([Alles nehmen] [Antworten] [Zurück] [Schließen]).
      Er nimmt Gold und alle Anhänge auf einmal – über denselben Weg wie Blizzards Shift-Klick
      (AutoLootMailItem). Nachnahme wird nie automatisch bezahlt: Dann bleibt der Knopf gesperrt.
    - Pfeil rechts neben dem Betreff mit „Weiterleiten“ und „Text kopieren“.
      Weiterleiten nimmt Gold und Anhänge, füllt „Verschicken“ mit „WG: Betreff“ und dem Text und hängt
      genau die erhaltenen Gegenstände wieder an. Text kopieren macht Blizzards Brieftext markierbar.
]]

local SUBJECT_WIDTH = 225            -- Blizzards Breite des Betreffs im offenen Brief
local SUBJECT_WIDTH_MENU = 195       -- Platz für den Pfeil
local FORWARD_STEP = 0.2
local FORWARD_TIMEOUT = 60           -- auch Zeit für Blizzards Sicherheitsabfrage bei Gold von Fremden
local SETTLE_TIME = 0.4              -- danach sind die Taschen nach dem Nehmen zur Ruhe gekommen

local button, menuButton
local forward                        -- laufende Weiterleitung
local copyBox, copyIndex
local hiddenParts = {}

-- Wartet der Server noch auf die Antwort zu einem Post-Befehl? Eine Stelle in ezCore (Core.Mail.CommandPending, W-14).
local CommandPending = ezCore.Mail.CommandPending

---------------------------------------------------------------------------
-- Alles nehmen
---------------------------------------------------------------------------

local function Update()
    if not button then return end
    button:SetShown(ns.S.takeAllButton and true or false)
    local index = ns.OpenMailIndex()
    local h = index and ns.Header(index)
    button.cod = h ~= nil and h.cod > 0
    local hasContent = h ~= nil and (h.money > 0 or h.items > 0)
    button:SetEnabled(hasContent and not button.cod and not ns.Runner.IsBusy() and not forward)
end

local function CreateButton()
    if button or not OpenMailFrame then return end
    button = CreateFrame("Button", nil, OpenMailFrame, "UIPanelButtonTemplate")
    button:SetSize(80, 22)
    if OpenMailReplyButton then
        button:SetPoint("RIGHT", OpenMailReplyButton, "LEFT", 0, 0)
    else
        button:SetPoint("BOTTOMLEFT", OpenMailFrame, "BOTTOMLEFT", 6, 4)
    end
    button:SetText(L.TAKE_ALL)
    button:SetScript("OnClick", function()
        local index = ns.OpenMailIndex()
        local h = index and ns.Header(index)
        if not h or h.cod > 0 then return end
        AutoLootMailItem(index)
        button:Disable()   -- bis Blizzard den Brief neu zeichnet
    end)
    button:SetScript("OnEnter", function(self)
        local text = self.cod and L.TAKE_ALL_COD or L.TAKE_ALL_TIP
        -- gesperrt: der Tooltip nennt den Grund aus denselben Bedingungen wie Update (T9-7; Gegenprüfung 18.11.2026:
        -- auch Weiterleiten und leerer Brief). Nachnahme erklärt TAKE_ALL_COD schon.
        if not self.cod and not self:IsEnabled() then
            local index = ns.OpenMailIndex()
            local h = index and ns.Header(index)
            local why = (ns.Runner.IsBusy() and L.RUN_BUSY_TIP) or (forward and L.TAKE_ALL_FORWARDING)
                or ((h == nil or (h.money <= 0 and h.items <= 0)) and L.TAKE_ALL_EMPTY) or nil
            if why then text = text .. "\n\n" .. ezCore.Style.ColorText("bad", why) end
        end
        ns.ShowTip(self, L.TAKE_ALL, text, "ANCHOR_TOP")
    end)
    ezCore.Toolbar.ShowTipWhileDisabled(button)
    button:SetScript("OnLeave", GameTooltip_Hide)
    OpenMailFrame:HookScript("OnShow", Update)
    Update()
end

---------------------------------------------------------------------------
-- Weiterleiten
---------------------------------------------------------------------------

-- Taschen wie beim Anhängen (ezCores Liste "sell": Rucksack, Taschen und Reagenzientasche, ohne Schlüsselbund; EC-50):
-- genommene Reagenzien landen auf Forever in der Reagenzientasche und müssen mit weitergeleitet werden.
local FORWARD_BAGS = "sell"

local function Snapshot()
    local bags = {}
    ns.ForEachBagItem(function(bag, slot, info)
        bags[bag * 1000 + slot] = { id = info.itemID, count = info.stackCount or 1 }
    end, FORWARD_BAGS)
    return bags
end

-- Was kam durch das Nehmen in die Taschen? Neue Stapel werden ganz angehängt, Mengen, die in
-- vorhandene Stapel geflossen sind, werden abgeteilt. Nie mehr, als im Brief war.
local function ReceivedEntries(before, expect)
    local entries = {}
    ns.ForEachBagItem(function(bag, slot, info)
        local want = expect[info.itemID]
        if not want or want <= 0 then return end
        local old = before[bag * 1000 + slot]
        local count = info.stackCount or 1
        local added = (old and old.id == info.itemID) and (count - old.count) or count
        if added <= 0 then return end
        local take = math.min(added, want)
        expect[info.itemID] = want - take
        if take == count then
            entries[#entries + 1] = { bag = bag, slot = slot, itemID = info.itemID, count = count }
        else
            entries[#entries + 1] = { bag = bag, slot = slot, itemID = info.itemID, split = take }
        end
    end, FORWARD_BAGS)
    return entries
end

local function ForwardSubject(subject)
    local prefix = L.FORWARD_PREFIX .. " "
    if subject:sub(1, #prefix) == prefix then return subject end
    return prefix .. subject
end

local function FillForward(job, money)
    local body = L.FORWARD_BODY:format(job.sender)
    if job.body ~= "" then body = body .. "\n" .. job.body end
    return ns.Send.FillForward(ForwardSubject(job.subject), body, money)
end

local function FinishForward(complete)
    local job = forward
    if not job then return end
    forward = nil
    if job.ticker then job.ticker:Cancel() end
    local gained = math.max(0, GetMoney() - job.moneyBefore)
    local entries = ReceivedEntries(job.before, job.expect)
    if not FillForward(job, math.min(job.wantMoney, gained)) then return Update() end
    if #entries > 0 then ns.Send.AttachEntries(entries) end
    if not complete then ns.Print(L.FORWARD_INCOMPLETE) end
    Update()
end

local function ForwardStep()
    local job = forward
    if not job then return end
    job.elapsed = job.elapsed + FORWARD_STEP
    local h = ns.Header(job.index)
    local gone = not h or ns.Signature(h) ~= job.sig              -- leerer Brief ohne Text wird gelöscht
    local taken = gone or (h.items == 0 and h.money == 0)
    if job.elapsed > FORWARD_TIMEOUT then return FinishForward(false) end
    if not taken or CommandPending() then return end
    job.settled = (job.settled or 0) + FORWARD_STEP
    if job.settled >= SETTLE_TIME then FinishForward(true) end
end

local function Forward()
    local index = ns.OpenMailIndex()
    local h = index and ns.Header(index)
    if not h or forward or ns.Runner.IsBusy() or ns.SendQueue.IsBusy() then return end
    local job = {
        index = index, sig = ns.Signature(h), subject = h.subject, sender = h.sender,
        body = GetInboxText(index) or "", expect = {}, stacks = 0, wantMoney = 0, elapsed = 0,
    }
    if h.cod > 0 then
        if h.items > 0 then ns.Print(L.FORWARD_COD) end
    else
        for attachment = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
            local _, itemID, _, count = GetInboxItem(index, attachment)
            if itemID then
                job.expect[itemID] = (job.expect[itemID] or 0) + (count or 1)
                job.stacks = job.stacks + 1
            end
        end
        job.wantMoney = h.money
    end
    if job.stacks == 0 and job.wantMoney == 0 then
        FillForward(job, 0)                                         -- nur Text
        return
    end
    if job.stacks > ns.FreeBagSlots() then
        ns.Print(L.FORWARD_NO_SPACE:format(job.stacks))
        return
    end
    job.before, job.moneyBefore = Snapshot(), GetMoney()
    forward = job
    AutoLootMailItem(index)
    job.ticker = C_Timer.NewTicker(FORWARD_STEP, ForwardStep)
    Update()
end

---------------------------------------------------------------------------
-- Text kopieren: Blizzards Brieftext wird für den Moment zu einem markierten Textfeld
---------------------------------------------------------------------------

local LETTER_PARTS = { "OpenMailBodyText", "OpenMailInvoiceFrame", "ConsortiumMailFrame" }

local function HideLetterParts()
    for _, name in ipairs(LETTER_PARTS) do
        local part = _G[name]
        if part and part:IsShown() then
            part:Hide()
            hiddenParts[#hiddenParts + 1] = part
        end
    end
end

local function StopCopy()
    if not copyIndex then return end
    copyIndex = nil
    if copyBox then copyBox:Hide() end
    for _, part in ipairs(hiddenParts) do part:Show() end
    wipe(hiddenParts)
end

local function CopyText(index)
    local h = ns.Header(index)
    local lines = { L.COPY_FROM:format(h.sender), L.COPY_SUBJECT:format(h.subject) }
    local body = GetInboxText(index) or ""
    if body ~= "" then
        lines[#lines + 1] = ""
        lines[#lines + 1] = body
    end
    return table.concat(lines, "\n")
end

local function CreateCopyBox()
    local parent = _G.OpenMailScrollChildFrame
    if copyBox or not parent then return end
    copyBox = CreateFrame("EditBox", nil, parent)
    copyBox:SetMultiLine(true)
    copyBox:SetAutoFocus(false)
    copyBox:SetFontObject(_G.MailTextFontNormal or GameFontHighlight)
    copyBox:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -10)
    copyBox:SetWidth(276)
    copyBox:SetScript("OnEscapePressed", StopCopy)
    copyBox:SetScript("OnEditFocusLost", StopCopy)
    -- Nur lesen: Tippen stellt den Text wieder her (Strg+C kopiert trotzdem).
    copyBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(self.copyText or "")
            self:HighlightText()
        end
        if ScrollingEdit_OnTextChanged and OpenMailScrollFrame then ScrollingEdit_OnTextChanged(self, OpenMailScrollFrame) end
    end)
    copyBox:SetScript("OnCursorChanged", function(self, x, y, w, h)
        if ScrollingEdit_OnCursorChanged then ScrollingEdit_OnCursorChanged(self, x, y - 10, w, h) end
    end)
    copyBox:SetScript("OnUpdate", function(self, elapsed)
        if ScrollingEdit_OnUpdate and OpenMailScrollFrame then ScrollingEdit_OnUpdate(self, elapsed, OpenMailScrollFrame) end
    end)
    copyBox:Hide()
end

local function StartCopy()
    local index = ns.OpenMailIndex()
    if not index then return end
    CreateCopyBox()
    if not copyBox then return end
    StopCopy()
    copyIndex = index
    copyBox.copyText = CopyText(index)
    HideLetterParts()
    copyBox:Show()
    copyBox:SetText(copyBox.copyText)
    copyBox:SetFocus()
    copyBox:HighlightText()
    ns.Print(L.COPY_HINT)
end

-- Blizzard zeichnet den Brief neu: anderer Brief → Kopieren beenden, sonst Text verdeckt lassen.
local function OnLetterUpdate()
    Update()
    if not copyIndex then return end
    if ns.OpenMailIndex() ~= copyIndex then return StopCopy() end
    HideLetterParts()
end

---------------------------------------------------------------------------
-- Pfeil mit „Weiterleiten“ und „Text kopieren“
---------------------------------------------------------------------------

local function ShowLetterMenu(owner)
    local opened = Menu.Open(owner, function(root)
        local h = ns.OpenMailIndex() and ns.Header(ns.OpenMailIndex())
        local forwardEntry = Menu.Button(root, L.FORWARD, Forward)
        if not h or forward or ns.Runner.IsBusy() or ns.SendQueue.IsBusy() then forwardEntry:SetEnabled(false) end
        Menu.Button(root, L.COPY_TEXT, StartCopy)
        -- Regel für den Absender dieses Briefs (Rules.lua): vertraut, auslassen, zurückschicken
        if h then
            Menu.Divider(root)
            ns.Rules.AddSenderMenu(root, h.sender)
        end
    end)
    if not opened then ns.Print(L.NO_MENU) end
end

local function UpdateMenuButton()
    if not menuButton then return end
    local on = ns.S.letterMenu and true or false
    menuButton:SetShown(on)
    if OpenMailSubject then OpenMailSubject:SetWidth(on and SUBJECT_WIDTH_MENU or SUBJECT_WIDTH) end
end

local function CreateMenuButton()
    if menuButton or not OpenMailFrame then return end
    menuButton = ezCore.Toolbar.ArrowButton(OpenMailFrame, function(self) ShowLetterMenu(self) end,
        L.LETTER_MENU_TITLE, L.LETTER_MENU_TIP)
    menuButton:SetSize(20, 20)
    menuButton:SetPoint("TOPRIGHT", OpenMailFrame, "TOPRIGHT", -10, -55)
    OpenMailFrame:HookScript("OnHide", StopCopy)
    UpdateMenuButton()
end

---------------------------------------------------------------------------
-- Einhängen
---------------------------------------------------------------------------

ns.WhenMailUI("Alles nehmen", function()
    CreateButton()
    ns.HookOpenMailUpdate(OnLetterUpdate)
end)
ns.WhenMailUI("Brief-Menü", CreateMenuButton)

ns.OnStatus(function()
    return L.STATUS_TAKE_ALL:format(button and L.YES or L.STATUS_MISSING_PART) .. " · "
        .. L.STATUS_LETTER_MENU:format(menuButton and L.YES or L.STATUS_MISSING_PART)
end)

ns.On("MAIL_INBOX_UPDATE", Update)
ns.On("MAIL_CLOSED", function()
    StopCopy()
    if forward then
        if forward.ticker then forward.ticker:Cancel() end
        forward = nil
    end
end)
ns.Listen("RUN_CHANGED", Update)
ns.Listen("QUEUE_CHANGED", Update)
ns.OnSettingChanged(function(key)
    if key == "takeAllButton" then Update() end
    if key == "letterMenu" then UpdateMenuButton() end
end)
