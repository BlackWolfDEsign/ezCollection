local _, ns = ...
local L = ns.L
local Menu = ezCore.Menu     -- Menüs an einer Stelle (Blizzards MenuUtil)

--[[
    Posteingang: Häkchen zum Auswählen mehrerer Briefe, Leiste mit „Alle“, Öffnen und Zurück,
    Strg-Klick zum Zurückschicken, Ablauf hervorheben, alle Anhänge im Tooltip,
    Filter für „Alle öffnen“ und Aufräumen (leere Briefe löschen) per Rechtsklick auf Blizzards Knopf.
    Blizzards Code wird nur mit hooksecurefunc/HookScript ergänzt, nie ersetzt.
]]

local Inbox = {}
ns.Inbox = Inbox
local Rules = ns.Rules

local ROWS = INBOXITEMS_TO_DISPLAY or 7
local SUBJECT_WIDTH = 248          -- Blizzards Breite der Betreffzeile
local SUBJECT_WIDTH_CHECK = 226    -- Platz für das Häkchen rechts unten
local BUTTON_WIDTH = 64            -- Öffnen / Zurück
local DELETE_ICON = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:12:12|t"
-- Restzeit unter der Warngrenze: Blizzards ORANGE_FONT_COLOR (Design-System 2.5: Blizzards Farbobjekte statt des
-- eigenen Codes ff8000); fehlt es im Client, die Rolle „warn“ (Blizzards Gelb).
local function WarnText(text)
    local orange = rawget(_G, "ORANGE_FONT_COLOR")
    if type(orange) == "table" and type(orange.WrapTextInColorCode) == "function" then
        local ok, wrapped = pcall(orange.WrapTextInColorCode, orange, text)
        if ok and type(wrapped) == "string" then return wrapped end
    end
    return ezCore.Style.ColorText("warn", text)
end

local selected = {}    -- [Platz im Posteingang] = Signatur des Briefs
local lastClicked
local checks = {}      -- unsere Häkchen je Zeile
local bar, allCheck, allLabel, info, infoText, openButton, returnButton

local NumMails = ns.NumMails

local function SignatureAt(index)
    local h = ns.Header(index)
    return h and ns.Signature(h) or nil
end

local function RowIndex(row)
    local button = _G["MailItem" .. row .. "Button"]
    if button and button:IsShown() and button.index then return button.index end
    return nil
end

---------------------------------------------------------------------------
-- Auswahl
---------------------------------------------------------------------------

function Inbox.Count()
    local n = 0
    for _ in pairs(selected) do n = n + 1 end
    return n
end

function Inbox.SetSelected(index, on)
    if on then
        selected[index] = SignatureAt(index)
    else
        selected[index] = nil
    end
end

function Inbox.IsSelected(index)
    local sig = selected[index]
    return sig ~= nil and sig == SignatureAt(index)
end

-- Ersetzt die Auswahl durch diese Plätze ({ [Platz] = true }, z. B. Suchtreffer der Übersicht).
function Inbox.SelectIndexes(set)
    wipe(selected)
    lastClicked = nil
    local count = 0
    for index in pairs(set) do
        local sig = SignatureAt(index)
        if sig then
            selected[index] = sig
            count = count + 1
        end
    end
    Inbox.Refresh()
    return count
end

function Inbox.ClearSelection()
    wipe(selected)
    lastClicked = nil
    Inbox.Refresh()
end

-- Briefe einer Art (test(h) → true), nie Nachnahme oder GM-Post. Auswahl nach Art.
local function EachWhere(test, fn)
    local count = 0
    for index = 1, (NumMails()) do
        local h = ns.Header(index)
        if h and h.cod == 0 and not h.gm and test(h) then
            count = count + 1
            if fn then fn(index, h) end
        end
    end
    return count
end

function Inbox.CountWhere(test) return EachWhere(test) end

-- Ersetzt die Auswahl durch alle Briefe dieser Art. Rückgabe: Anzahl.
function Inbox.SelectWhere(test)
    wipe(selected)
    lastClicked = nil
    local count = EachWhere(test, function(index, h) selected[index] = ns.Signature(h) end)
    Inbox.Refresh()
    return count
end

-- Gold im Posteingang ohne Nachnahme: gesamt und davon in der Auswahl (vor dem Einsammeln).
function Inbox.MoneyTotals()
    local total, chosen = 0, 0
    for index = 1, (NumMails()) do
        local h = ns.Header(index)
        if h and h.cod == 0 and h.money > 0 then
            total = total + h.money
            if selected[index] and selected[index] == ns.Signature(h) then chosen = chosen + h.money end
        end
    end
    return total, chosen
end

-- MAIL-08: Quelle und Alter mehrerer Preise zu einer Angabe für ezCores Satz (Core.Prices.SourceText)
-- zusammenfassen. info aus Prices.Get oder eine frühere Zusammenfassung; acc = bisherige Zusammenfassung oder nil.
-- Es zählt das älteste Alter (seen); die Art der Erfassung (kind) nur, solange alle Preise dieselbe haben.
function Inbox.MergeSource(acc, info)
    if type(info) ~= "table" or type(info.source) ~= "string" then return acc end
    local seen = ezCore.Num(info.seen)
    if not acc then
        return { source = info.source, seen = seen, kind = info.kind, mixed = info.mixed }
    end
    if seen and (not acc.seen or seen < acc.seen) then acc.seen = seen end
    if info.mixed or acc.kind ~= info.kind then acc.kind, acc.mixed = nil, true end
    return acc
end

-- Satz zur Zusammenfassung: „laut deinen Erfassungen (Komplett-Scan, vor 3 Tagen)“ – der Text kommt aus ezCore,
-- damit ezAuction, ezBag und ezMail dasselbe sagen. nil ohne Angabe oder bei einem ezCore ohne den Helfer.
function Inbox.SourceText(source)
    local prices = ezCore.Prices
    if type(source) ~= "table" or not (prices and prices.SourceText) then return nil end
    local ok, text = pcall(prices.SourceText, source)
    if ok and type(text) == "string" and text ~= "" then return text end
    return nil
end

-- Wert der Anhänge eines Briefs aus ezCores Preis-Wissen (ezCore.Prices, Marktwert × Anzahl).
-- Immer an seit der Einstellungs-Prüfung vom 19.11.2026 (Abschnitt 4: reine Auskunft).
-- Rückgabe: Kupfer (nil, wenn kein Anhang einen Preis hat), Anhänge ohne Preis,
-- Quelle und Alter der Preise (Inbox.MergeSource, für Inbox.SourceText; nil ohne Preis).
function Inbox.Value(index)
    local prices = ezCore.Prices
    if not (prices and prices.Value) then return nil, 0 end
    local h = ns.Header(index)
    if not h or h.items == 0 then return nil, 0 end
    local sum, unknown, any, source = 0, 0, false, nil
    for attachment = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
        local name, itemID, _, count = GetInboxItem(index, attachment)
        if name then
            local value = itemID and prices.Value(itemID, count or 1)
            if value then
                sum, any = sum + value, true
                if prices.Get then source = Inbox.MergeSource(source, prices.Get(itemID)) end
            else
                unknown = unknown + 1
            end
        end
    end
    return any and sum or nil, unknown, any and source or nil
end

-- Wert der Anhänge im ganzen Posteingang und davon in der Auswahl (nil, wenn nichts einen Preis hat),
-- dazu Quelle und Alter aller Preise (das älteste Alter, MAIL-08).
function Inbox.ValueTotals()
    local total, chosen, any, source = 0, 0, false, nil
    for index = 1, (NumMails()) do
        local value, _, letterSource = Inbox.Value(index)
        if value then
            any = true
            total = total + value
            source = Inbox.MergeSource(source, letterSource)
            local h = ns.Header(index)
            if selected[index] and h and selected[index] == ns.Signature(h) then chosen = chosen + value end
        end
    end
    if not any then return nil, 0 end
    return total, chosen, source
end

-- Ein Ziel für den Runner („open“ und „return“ mit Zielen): Platz, Signatur und Inhalt beim Start.
local function Target(index, h, sig)
    return { index = index, sig = sig or ns.Signature(h), money = h.money, items = h.items }
end

local function ByIndexDown(a, b) return a.index > b.index end

-- Ziele für den Runner, absteigend sortiert (hintere Briefe zuerst, dann verschiebt sich nichts).
function Inbox.Targets()
    local list = {}
    for index, sig in pairs(selected) do
        local h = ns.Header(index)
        if h and ns.Signature(h) == sig then list[#list + 1] = Target(index, h, sig) end
    end
    table.sort(list, ByIndexDown)
    return list
end

-- Nach Änderungen im Posteingang (neue Post oben, Brief gelöscht) die Auswahl nachführen.
local function Remap()
    if not next(selected) then return end
    local n = NumMails()
    local old = selected
    selected = {}
    local claimed = {}
    for index, sig in pairs(old) do
        local found
        for distance = 0, 5 do
            local a, b = index + distance, index - distance
            if a <= n and not claimed[a] and SignatureAt(a) == sig then
                found = a
            elseif distance > 0 and b >= 1 and not claimed[b] and SignatureAt(b) == sig then
                found = b
            end
            if found then break end
        end
        if found then
            claimed[found] = true
            selected[found] = sig
        end
    end
end

---------------------------------------------------------------------------
-- Zeilen: Häkchen und Ablauf
---------------------------------------------------------------------------

-- Farbenblind-Hilfe (EC-47): Mit ezCores Schalter „Zeichen am Leuchten“ steht vor der gefärbten Restzeit zusätzlich
-- das Zeichen der Farbe aus ezCores Ampel („o“ orange, „!“ rot). Leitet seit ezCore 1.12.0 auf ezCore.MarkSign weiter
-- (Schalter und Zeichen an einem Ort); ein älteres ezCore ohne den Helfer: kein Zeichen.
local function ColorMark(color)
    local mark = type(ezCore.MarkSign) == "function" and ezCore.MarkSign(color)
    return type(mark) == "string" and mark ~= "" and (mark .. " ") or ""
end
Inbox.ColorMark = ColorMark

-- Immer an seit der Einstellungs-Prüfung vom 19.11.2026 (Nr. 9: warnt vor Verlust, ohne Nachteil).
local function DecorateExpiry(row, index)
    local expire = _G["MailItem" .. row .. "ExpireTime"]
    local h = ns.Header(index)
    -- Grenzwert aus ezCore: derselbe wie in ezPanel
    if not (expire and h) or h.daysLeft >= ezCore.Mail.WarnDays() then return end

    -- Text immer neu bauen (Refresh läuft auch ohne Blizzards Neuzeichnen, sonst doppelte Symbole).
    local text
    if h.daysLeft >= 1 then
        text = WarnText(ColorMark("orange") .. format(DAYS_ABBR, floor(h.daysLeft)) .. " ")
    else
        -- unter einem Tag: wie Blizzard rot mit Stunden/Minuten
        text = RED_FONT_COLOR_CODE .. ColorMark("red") .. ezCore.TimeLeft(h.daysLeft * 24 * 60 * 60)   -- Core.TimeLeft: geschützt, gesperrter Wert „?“ (T16-15)
            .. FONT_COLOR_CODE_CLOSE
    end
    -- Wird beim Ablauf gelöscht statt zurückgeschickt – mit Inhalt ist das ein echter Verlust.
    if InboxItemCanDelete(index) and (h.money > 0 or h.items > 0) then
        text = DELETE_ICON .. " " .. text
    end
    expire:SetText(text)
end

local function UpdateRows()
    local show = ns.S.selectBoxes
    local busy = ns.Runner.IsBusy()
    for row = 1, ROWS do
        local index = RowIndex(row)
        local check = checks[row]
        if check then
            check:SetShown(show and index ~= nil)
            check:SetChecked(index ~= nil and selected[index] ~= nil)
            check:SetEnabled(not busy)
        end
        local subject = _G["MailItem" .. row .. "Subject"]
        if subject then subject:SetWidth(show and SUBJECT_WIDTH_CHECK or SUBJECT_WIDTH) end
        if index then DecorateExpiry(row, index) end
    end
end

local function OnRowCheck(check)
    local index = RowIndex(check.row)
    if not index then
        check:SetChecked(false)
        return
    end
    local on = check:GetChecked() and true or false
    if IsShiftKeyDown() and lastClicked and lastClicked ~= index then
        local n = NumMails()
        for k = math.min(lastClicked, index), math.min(math.max(lastClicked, index), n) do
            Inbox.SetSelected(k, on)
        end
    else
        Inbox.SetSelected(index, on)
    end
    lastClicked = index
    ezCore.PlaySound(on and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
    Inbox.Refresh()
end

-- Grund, warum ein Knopf der Leiste gesperrt ist – aus denselben Bedingungen wie Inbox.Refresh (T9-7; Gegenprüfung
-- 18.11.2026: vorher nannte nur ein laufender Lauf einen Grund, leerer Posteingang und „nichts angehakt“ keinen).
local function DisabledReason(self)
    if ns.Runner.IsBusy() then return L.RUN_BUSY_TIP end
    if self == allCheck and NumMails() == 0 then return L.SELECT_NO_MAIL end
    if (self == openButton or self == returnButton) and Inbox.Count() == 0 then return L.SELECT_FIRST end
end

-- Tooltip eines Knopfs der Leiste: der Text erst beim Zeigen, mit dem geltenden Befehl (%s, T18-2); ist der Knopf
-- gesperrt, nennt die letzte Zeile den Grund (T9-7).
local function ButtonTip(title, body)
    return function(self)
        local text = ns.CmdText(body)
        local why = self.IsEnabled and not self:IsEnabled() and DisabledReason(self)
        if why then text = text .. "\n\n" .. ezCore.Style.ColorText("bad", why) end
        ns.ShowTip(self, title, text, "ANCHOR_TOP")
    end
end

local function CreateRowChecks()
    local showTip = ButtonTip(L.SELECT_TIP_TITLE, L.SELECT_TIP)
    for row = 1, ROWS do
        local parent = _G["MailItem" .. row]
        if parent then
            local check = ns.CreateCheck(parent, 22)
            check:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 1)
            check.row = row
            check:SetScript("OnClick", OnRowCheck)
            check:SetScript("OnEnter", showTip)
            check:SetScript("OnLeave", GameTooltip_Hide)
            ezCore.Toolbar.ShowTipWhileDisabled(check)   -- gesperrt während eines Laufs: Tooltip mit Grund (T9-7)
            check:Hide()
            checks[row] = check
        end
    end
end

---------------------------------------------------------------------------
-- Leiste über der Liste
---------------------------------------------------------------------------

function Inbox.Refresh()
    UpdateRows()
    Inbox.UpdateAuctionLine()     -- eigene Zeile unter der Leiste, auch ohne Häkchen sichtbar (AH-33)
    if not bar then return end
    local show = ns.S.selectBoxes
    bar:SetShown(show)
    if not show then return end

    local n, total = NumMails()
    local count = Inbox.Count()
    local busy = ns.Runner.IsBusy()
    local mine = ns.Runner.IsRunning()

    allCheck:SetChecked(n > 0 and count >= n)
    allCheck:SetEnabled(n > 0 and not busy)

    local text = count > 0 and L.SELECTED:format(count) or L.MAIL_COUNT:format(n)
    info.overflow = total > n and (total - n) or nil
    if info.overflow then
        text = text .. " " .. RED_FONT_COLOR_CODE .. L.MORE_ON_SERVER:format(info.overflow) .. FONT_COLOR_CODE_CLOSE
        -- Blizzards roter Hinweis läge genau unter der Leiste – die Leiste zeigt ihn mit an.
        if InboxTooMuchMail and InboxTooMuchMail:IsShown() then InboxTooMuchMail:Hide() end
    end
    infoText:SetText(text)

    openButton:SetText(mine and ns.Runner.ButtonText() or L.BTN_OPEN)
    openButton:SetEnabled(mine or (count > 0 and not busy))
    returnButton:SetEnabled(count > 0 and not busy)
end

-- Leiste über der Liste (Ziel einer Erklärblase, Tour.lua)
function Inbox.Bar() return bar end
-- Knöpfe der Leiste und Häkchen der Zeilen (für die Prüfungen: Tooltip am gesperrten Knopf, T9-7)
function Inbox.Buttons()
    return { open = openButton, back = returnButton, all = allCheck, checks = checks }   -- „Auktionspost“: Inbox.AuctionButton()
end
-- „N Briefe“ in der Leiste (Tooltip mit Gold und Wert der Anhänge; für die Prüfungen)
function Inbox.Info() return info end

local function CreateBar()
    bar = CreateFrame("Frame", nil, InboxFrame)
    bar:SetPoint("TOPLEFT", MailFrame, "TOPLEFT", 64, -29)
    bar:SetPoint("TOPRIGHT", MailFrame, "TOPRIGHT", -10, -29)
    bar:SetHeight(26)

    allCheck = ns.CreateCheck(bar, 24)
    allCheck:SetPoint("LEFT", 0, 0)
    allLabel = allCheck:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    allLabel:SetPoint("LEFT", allCheck, "RIGHT", 0, 1)
    allLabel:SetText(ezCore.Style.AllText(true) or L.SELECT_ALL)   -- Wortlaut wie Blizzard (Design-System 2.11)
    allCheck:SetHitRectInsets(0, -(allLabel:GetStringWidth() + 4), 0, 0)
    allCheck:SetScript("OnClick", function(self)
        if self:GetChecked() then
            for index = 1, (NumMails()) do Inbox.SetSelected(index, true) end
        else
            wipe(selected)
        end
        lastClicked = nil
        ezCore.PlaySound(self:GetChecked() and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
        Inbox.Refresh()
    end)
    allCheck:SetScript("OnEnter", ButtonTip(L.SELECT_ALL_TIP_TITLE, L.SELECT_ALL_TIP))
    allCheck:SetScript("OnLeave", GameTooltip_Hide)
    ezCore.Toolbar.ShowTipWhileDisabled(allCheck)

    -- Von „Alle auswählen“ bis vor „Öffnen“ (rechter Anker unten, nach dem Knopf): bei vielen Briefen oder langem
    -- Wortlaut des Hakens wird gekürzt statt in die Knöpfe zu laufen.
    info = CreateFrame("Frame", nil, bar)
    info:SetHeight(20)
    info:SetPoint("LEFT", allLabel, "RIGHT", 6, 0)
    infoText = info:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    infoText:SetAllPoints()
    infoText:SetJustifyH("LEFT")
    infoText:SetWordWrap(false)
    -- Tooltip: Briefe auf dem Server (Blizzards Hinweis) und das Gold im Posteingang.
    info:SetScript("OnEnter", function(self)
        local total, chosen = Inbox.MoneyTotals()
        local lines = {}
        if self.overflow and INBOX_TOO_MUCH_MAIL_TOOLTIP then lines[#lines + 1] = INBOX_TOO_MUCH_MAIL_TOOLTIP end
        if total > 0 then
            lines[#lines + 1] = L.MAIL_GOLD_TOTAL:format(ns.CoinText(total))
            if chosen > 0 then lines[#lines + 1] = L.MAIL_GOLD_SELECTED:format(ns.CoinText(chosen)) end
        end
        local worth, worthChosen, worthSource = Inbox.ValueTotals()
        if worth then
            lines[#lines + 1] = L.VALUE_TOTAL:format(ns.CoinText(worth))
            if worthChosen > 0 then lines[#lines + 1] = L.VALUE_SELECTED:format(ns.CoinText(worthChosen)) end
            -- MAIL-08: Quelle und ältestes Alter der Preise (ezCores Satz)
            local sourceText = Inbox.SourceText(worthSource)
            if sourceText then lines[#lines + 1] = L.VALUE_SOURCE:format(sourceText) end
        end
        if #lines == 0 and not self.overflow then return end
        local title = self.overflow and L.MORE_ON_SERVER_TIP:format(self.overflow) or L.MAIL_GOLD_TITLE
        ns.ShowTip(self, title, table.concat(lines, "\n"), "ANCHOR_BOTTOM")
    end)
    info:SetScript("OnLeave", GameTooltip_Hide)

    returnButton = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    returnButton:SetSize(BUTTON_WIDTH, 22)
    returnButton:SetPoint("RIGHT", 0, 0)
    returnButton:SetText(L.BTN_RETURN)
    returnButton:SetScript("OnClick", function()
        ns.Runner.Start("return", Inbox.Targets())
    end)
    returnButton:SetScript("OnEnter", ButtonTip(L.BTN_RETURN_TIP_TITLE, L.BTN_RETURN_TIP))
    returnButton:SetScript("OnLeave", GameTooltip_Hide)
    ezCore.Toolbar.ShowTipWhileDisabled(returnButton)

    openButton = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    openButton:SetSize(BUTTON_WIDTH, 22)
    openButton:SetPoint("RIGHT", returnButton, "LEFT", -2, 0)
    openButton:SetText(L.BTN_OPEN)
    openButton:SetScript("OnClick", function()
        if ns.Runner.IsRunning() then
            ns.Runner.Stop()
        else
            ns.Runner.Start("open", Inbox.Targets())
        end
    end)
    openButton:SetScript("OnEnter", ButtonTip(L.BTN_OPEN_TIP_TITLE, L.BTN_OPEN_TIP))
    ezCore.Toolbar.ShowTipWhileDisabled(openButton)
    openButton:SetScript("OnLeave", GameTooltip_Hide)

    info:SetPoint("RIGHT", openButton, "LEFT", -4, 0)
end

---------------------------------------------------------------------------
-- Strg-Klick: zurückschicken
---------------------------------------------------------------------------

local function OnMailButtonClick(self)
    if not ns.S.ctrlReturn or not IsControlKeyDown() or IsShiftKeyDown() or IsAltKeyDown() then return end
    -- Liegt Blizzards „alles nehmen“ auf Strg, hat das Vorrang.
    if IsModifiedClick("MAILAUTOLOOTTOGGLE") then return end
    local index = self.index
    if not index or ns.Runner.IsBusy() then return end
    local h = ns.Header(index)
    if not h then return end
    if InboxItemCanDelete(index) then
        ns.Print(L.CANNOT_RETURN)
        return
    end
    -- Blizzard hat den Brief durch den Klick gerade geöffnet: dann über Blizzards eigenen
    -- Zurück-Knopf-Weg, der schickt zurück und schließt das Fenster sauber.
    local viaBlizzard = OpenMailFrame and OpenMailFrame:IsShown() and InboxFrame.openMailID == index and ns.ReturnOpenMail()
    if not viaBlizzard then ReturnInboxItem(index) end
    ns.Print(L.RETURNED:format(h.sender))
end

---------------------------------------------------------------------------
-- Alle Anhänge im Tooltip (Blizzard zeigt bei mehreren nur die Anzahl)
---------------------------------------------------------------------------

-- Rücksicht auf ein fremdes Addon, das die Anhänge im Post-Tooltip selbst auflisten kann (Auctionator). Erkennung an
-- einer Stelle: ezCore/OtherAddOns.lua, Schlüssel "mailTooltip". ezMail fragt nur, WER läuft – ob dessen Post-Tooltip
-- an ist, liest es nicht (Entscheidung des Nutzers vom 14.11.2026: „Nur öffentliche API“). Deshalb weicht ezMail nicht
-- mehr von selbst: Anhang-Liste und Wert bleiben, bis der Spieler sie mit dem eigenen Schalter „attachYield“ (ab Werk
-- aus) neben dem fremden Addon abschaltet (MAIL-11).
function Inbox.OtherTooltip()
    return (ns.OtherFor("mailTooltip"))     -- Gerüst: Core.WhoHandles, innen gesichert
end

function Inbox.YieldsTooltip()
    return ns.S.attachYield == true and Inbox.OtherTooltip() ~= nil
end

-- Wer zeigt eine Zeile im Tooltip der Briefliste (key = "attachTooltip" oder "attachValue")?
-- "own" = ezMail, "yield" = weggelassen neben dem fremden Addon. Für /ezm status und Tests. Seit der
-- Einstellungs-Prüfung vom 19.11.2026 haben beide Zeilen keinen eigenen Schalter mehr (vorher auch "off").
function Inbox.TooltipSource(key)
    return Inbox.YieldsTooltip() and "yield" or "own"
end

-- Regel des Absenders (vertraut, auslassen, zurückschicken; eigener Charakter) im Tooltip der Zeile.
local function AddRuleLine(self)
    if not self.index then return end
    local h = ns.Header(self.index)
    local text = h and Rules.Describe(h.sender)
    if not text then return end
    ezCore.TipLine(GameTooltip, L.RULE_TOOLTIP:format(text), "blue")   -- Rolle statt Farbzahlen (T9-6)
    GameTooltip:Show()
end

-- Wert der Anhänge (ezCore-Preis-Wissen). Neben Auctionator nur auf Wunsch weggelassen (Schalter „attachYield“).
local function AddValueLine(self)
    if not self.index or Inbox.YieldsTooltip() then return end
    local value, unknown, source = Inbox.Value(self.index)
    if not value then
        -- Anhänge, aber kein einziger Preis: nicht schweigen, sondern sagen, woher der Wert käme
        -- (Regel „Datenquellen“ des Nutzers, 13.11.2026: jede Angabe nennt ihre Quelle, kein leerer Tooltip).
        if unknown > 0 then
            ezCore.TipLine(GameTooltip, L.VALUE_NONE, "hint", true)
            GameTooltip:Show()
        end
        return
    end
    local text = L.VALUE_TOOLTIP:format(ns.CoinText(value))
    if unknown > 0 then text = text .. " (" .. L.VALUE_UNKNOWN:format(unknown) .. ")" end
    ezCore.TipLine(GameTooltip, text, "highlight")
    -- MAIL-08: woher der Preis stammt und wie alt er ist (bei mehreren Anhängen das älteste Alter)
    local sourceText = Inbox.SourceText(source)
    if sourceText then ezCore.TipLine(GameTooltip, L.VALUE_SOURCE:format(sourceText), "hint", true) end
    GameTooltip:Show()
end

-- Immer an seit der Einstellungs-Prüfung vom 19.11.2026 (Nr. 8); Rücksicht auf Auctionator über „attachYield“.
local function AddAttachmentLines(self)
    if not self.index then return end
    if not (self.itemCount and self.itemCount > 1) then return end
    if Inbox.YieldsTooltip() then return end
    for attachment = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
        local name, _, texture, count = GetInboxItem(self.index, attachment)
        if name then
            local link = GetInboxItemLink(self.index, attachment)
            -- Symbol im Text in Schriftgröße (Größe 0, Design-System 2.3), Anzahl in der Rolle „highlight“
            local line = (texture and ("|T" .. texture .. ":0|t ") or "") .. (link or name)
            if count and count > 1 then line = line .. " " .. ezCore.Style.ColorText("highlight", "x" .. count) end
            GameTooltip:AddLine(line)
        end
    end
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Aufräumen: gelesene Briefe ohne Inhalt löschen (ausgewählte, sonst alle)
---------------------------------------------------------------------------

function Inbox.EmptyTargets()
    local list, unread = {}, 0
    local fromSelection = next(selected) ~= nil
    for index = 1, (NumMails()) do
        local h = ns.Header(index)
        local sig = h and ns.Signature(h)
        if h and (not fromSelection or selected[index] == sig) then
            if ns.IsEmptyRead(index, h) then
                list[#list + 1] = { index = index, sig = sig }
            elseif not h.read and h.money == 0 and h.items == 0 then
                unread = unread + 1
            end
        end
    end
    table.sort(list, function(a, b) return a.index > b.index end)
    return list, unread, fromSelection
end

function Inbox.DeleteEmpty()
    if not (MailFrame and MailFrame:IsShown()) then
        ns.Print(L.NEED_MAILBOX)
        return
    end
    if ns.Runner.IsBusy() then return end
    local targets, unread = Inbox.EmptyTargets()
    if #targets == 0 then
        ns.Print(unread > 0 and L.DELETE_NONE_UNREAD:format(unread) or L.DELETE_NONE)
        return
    end
    if unread > 0 then ns.Print(L.DELETE_UNREAD_KEPT:format(unread)) end
    -- Rückfrage mit Warnsymbol und „Löschen“ aus ezCore (ein Dialog für alle Module)
    ezCore.Confirm(L.DELETE_CONFIRM:format(#targets), function() ns.Runner.Start("delete", targets) end,
        { alert = true, accept = ezCore.Word("DELETE") })
end

---------------------------------------------------------------------------
-- Auktionspost (AH-33): Verkäufe und Rückläufer im Überblick, abholen über den vorhandenen Lauf
---------------------------------------------------------------------------
-- Die Angaben kommen aus ezCores Auskunft „Auktionspost“ (History.AuctionMail, Welle 14): was beim letzten Erfassen
-- im Briefkasten lag (ezCore erfasst nach jeder Änderung des Posteingangs) und was seit dem Einloggen abgeholt wurde.
-- ezMail rechnet nur zusammen und zeigt es: Zeile unter der Leiste und in der Übersicht (Overview.lua).

Inbox.AUCTION_KINDS = { sale = true, expired = true, cancelled = true }   -- dieselben Arten wie ezCores Auskunft
Inbox.AUCTION_TIP_MAX = 12          -- so viele Gegenstände je Liste im Tooltip, dann „… und n weitere“
local AHLINE_BUTTON_WIDTH = 72
Inbox.AHLINE_TOP = -55              -- Unterkante der Leiste (bei -29, 26 hoch)
Inbox.AHLINE_HEIGHT = 15            -- bis -70, wo Blizzards MailItem1 beginnt (Forever-Quelle, MailFrame.xml)

local ahLine, ahInfo, ahText, ahButton

-- Filter des Abhol-Laufs: Brief des Auktionshauses mit Verkauf oder Rückläufer (abgelaufen, abgebrochen) – erkannt an
-- Blizzards Betreffzeile über ezCore (Mail.AuctionKind). Käufe und überbotene Gebote gehören nicht dazu.
function Inbox.IsAuctionMail(h)
    if type(h) ~= "table" then return false end
    local kind = ezCore.Mail.AuctionKind(h.subject)
    return kind ~= nil and Inbox.AUCTION_KINDS[kind] == true
end

-- Ziele des Abhol-Laufs: alle Briefe mit Auktionspost, ohne Nachnahme und GM-Post (wie „Auswählen nach Art“).
function Inbox.AuctionTargets()
    local list = {}
    EachWhere(Inbox.IsAuctionMail, function(index, h) list[#list + 1] = Target(index, h) end)
    table.sort(list, ByIndexDown)
    return list
end

-- Gold, das in den Verkaufsbriefen liegt (Verkaufspreis minus Gebühr plus Anzahlung), aus Blizzards Kopfzeilen –
-- dieselbe Zahl, die die Leiste („Gold im Posteingang“) und nach dem Abholen „Eingesammelt“ nennen (Regel
-- „Datenquellen“: der Client zuerst). ezCores Auskunft führt je Verkauf den Verkaufspreis der Rechnung vor der Gebühr;
-- der steht im Tooltip bei „verkauft zu …“.
function Inbox.AuctionSaleGold()
    local gold = 0
    EachWhere(function(h) return ezCore.Mail.AuctionKind(h.subject) == "sale" end, function(_, h)
        gold = gold + (ezCore.Num(h.money) or 0)
    end)
    return gold
end

-- Häkchen, die vor dem Abholen gesetzt waren (Signaturen): Jeder Lauf mit Zielen hebt am Ende die Auswahl auf, weil
-- sie seine Ziele war (Runner.Finish). Der Auktionspost-Lauf hat mit der Auswahl nichts zu tun – nach ihm kommen die
-- Häkchen der Briefe zurück, die noch da sind (über die Signatur, die Plätze haben sich verschoben).
local keepAfterRun

local function RestoreSelection()
    local keep = keepAfterRun
    keepAfterRun = nil
    if not keep then return end
    local want = {}
    for _, sig in ipairs(keep) do want[sig] = (want[sig] or 0) + 1 end
    for index = 1, (NumMails()) do
        local sig = SignatureAt(index)
        if sig and (want[sig] or 0) > 0 then
            want[sig] = want[sig] - 1
            selected[index] = sig
        end
    end
end

-- Knopf „Auktionspost abholen“: kein eigener Lauf, sondern derselbe wie „Öffnen“ für ausgewählte Briefe
-- (Runner „open“ mit Zielen) – gleiche Drosselung, Nachnahme und GM-Post bleiben liegen, frei gehaltene Taschenplätze
-- zählen, die Zusammenfassung kommt wie immer; gesetzte Häkchen bleiben. Rückgabe: true, wenn der Lauf begonnen hat.
function Inbox.TakeAuctionMail()
    if ns.Runner.IsBusy() then return false end
    local targets = Inbox.AuctionTargets()
    if #targets == 0 then
        ns.Print(L.AHMAIL_NONE)
        return false
    end
    local keep = {}
    for index, sig in pairs(selected) do
        if sig == SignatureAt(index) then keep[#keep + 1] = sig end
    end
    keepAfterRun = #keep > 0 and keep or nil
    local started = ns.Runner.Start("open", targets)
    if not started then keepAfterRun = nil end
    return started
end

-- Läuft ezAuction? Dann stehen Rückläufer beim nächsten Besuch im Auktionshaus oben in dessen Taschenliste (AH-28).
-- Bietet ezAuction die Auskunft ReturnsListed() an (zeigt es Rückläufer gerade oben, etwa mit eingeschaltetem
-- Schalter?), zählt deren Antwort; ohne sie genügt, dass ezAuction läuft (Auftrag AH-33).
function Inbox.AuctionRuns()
    local api = ezCore.API("ezAuction")
    if not api then return false end
    if type(api.ReturnsListed) == "function" then return ezCore.Call(api.ReturnsListed) == true end
    return true
end

-- Auskunft „Auktionspost“ zusammengefasst: { sales, returns, gold, waiting = { Einträge im Briefkasten },
-- taken = { seit dem Einloggen abgeholt }, anyReturn, seen } – nil, wenn ezCore die Auskunft nicht hat.
function Inbox.AuctionMail()
    local H = ezCore.History
    if not (H and type(H.AuctionMail) == "function") then return nil end
    local info = ezCore.Call(H.AuctionMail)
    if type(info) ~= "table" then return nil end
    local out = { sales = 0, returns = 0, gold = 0, waiting = {}, taken = {}, seen = ezCore.Num(info.seen) }
    for _, e in ipairs(type(info.list) == "table" and info.list or {}) do
        if type(e) == "table" and Inbox.AUCTION_KINDS[e.kind] then
            if e.kind ~= "sale" then out.anyReturn = true end
            if e.taken then
                out.taken[#out.taken + 1] = e
            else
                out.waiting[#out.waiting + 1] = e
                if e.kind == "sale" then
                    out.sales = out.sales + 1
                else
                    out.returns = out.returns + 1
                end
            end
        end
    end
    if out.sales > 0 then out.gold = Inbox.AuctionSaleGold() end
    return out
end

-- „Auktionspost: 2 Verkäufe (12 G), 3 Rückläufer“ – nil, wenn nichts im Briefkasten liegt. short: ohne „Auktionspost:“
-- (für die Zeile über der Briefliste, wenn sie zu schmal ist; der Tooltip trägt den Titel).
function Inbox.AuctionLineText(info, short)
    if type(info) ~= "table" or (info.sales + info.returns) == 0 then return nil end
    local parts = {}
    if info.sales > 0 then
        local gold = info.gold > 0 and L.AHMAIL_GOLD:format(ezCore.Money(info.gold, info.gold >= 10000 and "gold" or "coins")) or ""
        parts[#parts + 1] = L.AHMAIL_SALES:format(info.sales) .. gold
    end
    if info.returns > 0 then parts[#parts + 1] = L.AHMAIL_RETURNS:format(info.returns) end
    if short then return table.concat(parts, ", ") end
    return L.AHMAIL_LINE:format(table.concat(parts, ", "))
end

-- Eine Zeile je Gegenstand: „Leinenstoff x20: verkauft zu …“, „…: abgelaufen · zuletzt eingestellt zu … je Stück“.
function Inbox.AuctionEntryText(e)
    local item = ezCore.Num(e.item)
    local name = (item and ezCore.ItemNameByID(item)) or (item and L.AHMAIL_ITEM:format(item)) or L.AHMAIL_ITEM_UNKNOWN
    local n = ezCore.Num(e.n)
    if n and n > 1 then name = name .. " x" .. n end
    local price = ezCore.Num(e.price)
    if e.kind == "sale" then
        return price and L.AHMAIL_SOLD:format(name, ns.CoinText(price)) or L.AHMAIL_SOLD_NOPRICE:format(name)
    end
    local text = (e.kind == "expired" and L.AHMAIL_EXPIRED or L.AHMAIL_CANCELLED):format(name)
    if price then text = text .. " · " .. L.AHMAIL_LAST:format(ns.CoinText(price)) end
    return text
end

-- Tooltip: Liste je Gegenstand (im Briefkasten, dann seit dem Einloggen abgeholt) und die Hinweise darunter – Quelle
-- (Regel „Datenquellen“: jede Angabe nennt sie) und, nur wenn ezAuction läuft, wo die Rückläufer wieder auftauchen.
-- Rückgabe: Zeilen, Hinweise.
function Inbox.AuctionTipLines(info)
    local lines, notes = {}, {}
    if type(info) ~= "table" then return lines, notes end
    local function List(entries)
        for i, e in ipairs(entries) do
            if i > Inbox.AUCTION_TIP_MAX then
                lines[#lines + 1] = ezCore.More(#entries - Inbox.AUCTION_TIP_MAX)
                break
            end
            lines[#lines + 1] = Inbox.AuctionEntryText(e)
        end
    end
    List(info.waiting)
    if #info.taken > 0 then
        lines[#lines + 1] = L.AHMAIL_TAKEN_HEAD
        List(info.taken)
    end
    notes[#notes + 1] = L.AHMAIL_SOURCE
    if info.anyReturn and Inbox.AuctionRuns() then notes[#notes + 1] = L.AHMAIL_RETURNS_HINT end
    return lines, notes
end

-- Ganzer Tooltip als ein Text (für Menü-Einträge der Übersicht, Menu.Tip nimmt Titel und einen Text).
function Inbox.AuctionTipText(info)
    local lines, notes = Inbox.AuctionTipLines(info)
    for _, note in ipairs(notes) do lines[#lines + 1] = note end
    return table.concat(lines, "\n")
end

-- Zeile unter der Leiste (für die Prüfungen und Erklärblasen)
function Inbox.AuctionLine() return ahLine end
function Inbox.AuctionButton() return ahButton end
function Inbox.AuctionInfo() return ahInfo end
function Inbox.AuctionText() return ahText end

function Inbox.UpdateAuctionLine()
    if not ahLine then return end
    local info = ns.S.auctionMail and Inbox.AuctionMail() or nil
    local text = Inbox.AuctionLineText(info)
    ahLine:SetShown(text ~= nil)
    if not text then return end
    ahText:SetText(text)
    -- Passt der Text nicht neben den Knopf (große Beträge, lange Zahlen), ohne „Auktionspost:“ – sonst schnitte „…“
    -- gerade die Rückläufer am Ende ab. Breite 0 heißt: noch nicht ausgelegt, dann bleibt der volle Text.
    local width = ahInfo:GetWidth() or 0
    if width > 0 and ahText:GetStringWidth() > width then ahText:SetText(Inbox.AuctionLineText(info, true)) end
    local mine = ns.Runner.IsRunning()
    ahButton:SetText(mine and ns.Runner.ButtonText() or L.AHMAIL_TAKE_SHORT)
    ahButton:SetEnabled(mine or not ns.Runner.IsBusy())
end

-- Zwischen der Leiste und dem ersten Brief (Blizzards Forever-Quelle: MailItem1 bei y = -70, die Leiste endet bei -55;
-- dort liegt sonst nur Blizzards Hinweis „zu viel Post“, den die Leiste selbst anzeigt): genau Inbox.AHLINE_HEIGHT hoch,
-- damit nichts in den ersten Brief ragt. Eigener Rahmen am Posteingang, nicht an der Leiste: die Zeile bleibt, auch wenn
-- die Häkchen aus sind.
local function CreateAuctionLine()
    ahLine = CreateFrame("Frame", nil, InboxFrame)
    ahLine:SetPoint("TOPLEFT", MailFrame, "TOPLEFT", 64, Inbox.AHLINE_TOP)
    ahLine:SetPoint("TOPRIGHT", MailFrame, "TOPRIGHT", -10, Inbox.AHLINE_TOP)
    ahLine:SetHeight(Inbox.AHLINE_HEIGHT)
    ahLine:Hide()

    ahButton = CreateFrame("Button", nil, ahLine, "UIPanelButtonTemplate")
    ahButton:SetSize(AHLINE_BUTTON_WIDTH, Inbox.AHLINE_HEIGHT)
    ahButton:SetPoint("RIGHT", 0, 0)
    ahButton:SetText(L.AHMAIL_TAKE_SHORT)
    ahButton:SetScript("OnClick", function()
        if ns.Runner.IsRunning() then
            ns.Runner.Stop()
        else
            Inbox.TakeAuctionMail()
        end
    end)
    ahButton:SetScript("OnEnter", ButtonTip(L.AHMAIL_TAKE, L.AHMAIL_TAKE_TIP))
    ahButton:SetScript("OnLeave", GameTooltip_Hide)
    ezCore.Toolbar.ShowTipWhileDisabled(ahButton)

    ahInfo = CreateFrame("Frame", nil, ahLine)
    ahInfo:SetPoint("LEFT", 2, 0)
    ahInfo:SetPoint("RIGHT", ahButton, "LEFT", -4, 0)
    ahInfo:SetHeight(Inbox.AHLINE_HEIGHT)
    ahText = ahInfo:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    ahText:SetAllPoints()
    ahText:SetJustifyH("LEFT")
    ahText:SetWordWrap(false)
    ahInfo:SetScript("OnEnter", function(self)
        local info = Inbox.AuctionMail()
        if not info then return end
        local lines, notes = Inbox.AuctionTipLines(info)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        ezCore.TipTitle(GameTooltip, L.AHMAIL_TITLE)
        for _, line in ipairs(lines) do ezCore.TipLine(GameTooltip, line, "highlight") end
        for _, note in ipairs(notes) do ezCore.TipLine(GameTooltip, note, "hint", true) end
        GameTooltip:Show()
    end)
    ahInfo:SetScript("OnLeave", GameTooltip_Hide)
    Inbox.UpdateAuctionLine()
end

---------------------------------------------------------------------------
-- Rechtsklick auf Blizzards „Alle öffnen“: Filter und Aufräumen
---------------------------------------------------------------------------

-- Auswahl im Menü „Taschenplätze frei lassen“: bis ns.KEEP_FREE_MAX wie der Regler der Einstellungsseite; ein dort
-- gewählter Zwischenwert kommt dazu (Einstellungs-Prüfung vom 19.11.2026).
local KEEP_FREE_CHOICES = { 0, 1, 2, 3, 5, 10, 15, 20 }
function Inbox.KeepFreeChoices()
    local list, has = {}, {}
    local current = tonumber(ns.S and ns.S.keepFree)
    for _, count in ipairs(KEEP_FREE_CHOICES) do
        if count <= ns.KEEP_FREE_MAX then list[#list + 1], has[count] = count, true end
    end
    if current and current >= 0 and current <= ns.KEEP_FREE_MAX and not has[current] then
        list[#list + 1] = current
        table.sort(list)
    end
    return list
end

-- „Auswählen“ im Menü: Arten wie beim gefilterten Öffnen, dazu Gold und Gegenstände.
local function OfCategory(category)
    return function(h) return ns.MailCategory(h.subject) == category end
end
local SELECT_KINDS = {
    { text = function() return L.OPT_openAHSold end, test = OfCategory("ahSold") },
    { text = function() return L.OPT_openAHWon end, test = OfCategory("ahWon") },
    { text = function() return L.OPT_openAHReturned end, test = OfCategory("ahReturned") },
    { text = function() return L.SELECT_MONEY end, test = function(h) return h.money > 0 end },
    { text = function() return L.SELECT_ITEMS end, test = function(h) return h.items > 0 end },
    { text = function() return L.SELECT_BLOCKED end, test = function(h) return ns.Rules.IsBlocked(h.sender) end },
}

local function ShowFilterMenu(owner)
    local opened = Menu.Open(owner, function(root)
        Menu.Title(root, L.FILTER_TITLE)
        if ns.Runner.IsRunning() then
            Menu.Button(root, L.FILTER_STOP, function() ns.Runner.Stop() end)
        else
            Menu.Button(root, L.FILTER_START, function() ns.Runner.Start("open") end)
        end
        Menu.Divider(root)
        for _, key in ipairs(ns.FILTERS) do
            Menu.Toggle(root, L["OPT_" .. key], function() return ns.S[key] end, function(on) ns.SetSetting(key, on) end)
        end
        local keep = Menu.Button(root, L.FILTER_KEEP)
        for _, count in ipairs(Inbox.KeepFreeChoices()) do
            Menu.Radio(keep, tostring(count), function() return ns.S.keepFree end,
                function(value) ns.SetSetting("keepFree", value) end, count)
        end
        Menu.Title(root, L.FILTER_NOTE)
        -- Beim Öffnen des Briefkastens einsammeln (Express.lua) und Absender-Regeln (Rules.lua)
        local auto = Menu.Button(root, L.AUTO_MENU)
        Menu.Toggle(auto, L.OPT_autoExpress, function() return ns.S.autoExpress end,
            function(on) ns.SetSetting("autoExpress", on) end)
        Menu.Divider(auto)
        for _, key in ipairs(ns.AUTO_KINDS) do
            Menu.Toggle(auto, L["OPT_" .. key], function() return ns.S[key] end, function(on) ns.SetSetting(key, on) end)
        end
        Rules.AddManageMenu(root)

        -- Auswahl nach Art (nur mit den Häkchen der Leiste sinnvoll), danach „Öffnen“ oder „Zurück“.
        Menu.Divider(root)
        Menu.Title(root, L.SELECT_TITLE)
        for _, kind in ipairs(SELECT_KINDS) do
            local count = Inbox.CountWhere(kind.test)
            local entry = Menu.Button(root, ("%s (%d)"):format(kind.text(), count), function() Inbox.SelectWhere(kind.test) end)
            if count == 0 or not ns.S.selectBoxes or ns.Runner.IsBusy() then entry:SetEnabled(false) end
        end

        Menu.Divider(root)
        Menu.Title(root, L.CLEAN_TITLE)
        local targets, _, fromSelection = Inbox.EmptyTargets()
        local text = (fromSelection and L.DELETE_EMPTY_SELECTED or L.DELETE_EMPTY):format(#targets)
        local entry = Menu.Button(root, text, Inbox.DeleteEmpty)
        if #targets == 0 or ns.Runner.IsBusy() then entry:SetEnabled(false) end
    end)
    if not opened then ns.Print(L.NO_MENU) end
end

-- Sichtbarer Pfeil direkt rechts neben Blizzards „Alle öffnen“ (wie das Adressbuch am Feld „An:“).
-- Ein Rechtsklick auf den Knopf öffnet dasselbe Menü – als Zugabe, nicht als einziger Weg.
local filterButton
function Inbox.FilterButton() return filterButton end

local function HookOpenAll()
    local button = _G.OpenAllMail
    if not button then return end
    -- Pfeil (Menü) aus ezCores Werkzeugleiste: derselbe Knopf wie in den anderen Modulen
    filterButton = ezCore.Toolbar.ArrowButton(button:GetParent() or InboxFrame, function(self) ShowFilterMenu(self) end)
    -- Tooltip mit dem geltenden Befehl, erst beim Zeigen eingesetzt (T18-2)
    filterButton:SetScript("OnEnter", function(self)
        ns.ShowTip(self, L.FILTER_BUTTON_TITLE, ns.CmdText(L.FILTER_BUTTON_TIP), "ANCHOR_TOP")
    end)
    filterButton:SetPoint("LEFT", button, "RIGHT", 1, 0)

    button:HookScript("OnMouseUp", function(self, mouse)
        if mouse == "RightButton" and self:IsVisible() then ShowFilterMenu(self) end
    end)
end

---------------------------------------------------------------------------
-- Einhängen
---------------------------------------------------------------------------

-- Jeder Teil für sich: Scheitert einer auf einem Client, laufen die anderen trotzdem.
ns.WhenMailUI("Häkchen", CreateRowChecks)
ns.WhenMailUI("Leiste", CreateBar)
ns.WhenMailUI("Filter an „Alle öffnen“", HookOpenAll)
ns.WhenMailUI("Auktionspost", CreateAuctionLine)
ns.WhenMailUI("Liste", function()
    ns.HookInboxUpdate(Inbox.Refresh)
    Inbox.Refresh()
end)
ns.WhenMailUI("Anhänge im Tooltip", function()
    if type(InboxFrameItem_OnEnter) == "function" then
        hooksecurefunc("InboxFrameItem_OnEnter", AddAttachmentLines)
        hooksecurefunc("InboxFrameItem_OnEnter", AddValueLine)
        hooksecurefunc("InboxFrameItem_OnEnter", AddRuleLine)
    end
end)
ns.WhenMailUI("Strg-Klick", function()
    for row = 1, ROWS do
        local button = _G["MailItem" .. row .. "Button"]
        if button then button:HookScript("OnClick", OnMailButtonClick) end
    end
end)

ns.OnStatus(function()
    local state = not bar and L.STATUS_MISSING_PART or (bar:IsVisible() and L.YES or L.STATUS_HIDDEN)
    local count, visible = 0, 0
    for _, check in pairs(checks) do
        count = count + 1
        if check:IsVisible() then visible = visible + 1 end
    end
    local line = L.STATUS_INBOX:format(state, count, visible, tostring(ns.S.selectBoxes))
    -- Lage und Ebene der Leiste im Vergleich zum Postfach (liegt sie verdeckt oder außerhalb?)
    if bar and MailFrame then
        local function Pos(frame)
            local x, y = frame:GetLeft(), frame:GetTop()
            return (x and y) and format("%.0f/%.0f", x, y) or "?"
        end
        line = line .. "\n" .. L.STATUS_BAR_POS:format(Pos(bar), Pos(MailFrame),
            tostring(bar:GetFrameLevel()), tostring(MailFrame:GetFrameLevel()),
            -- die Schicht kann seit 1.60.1 gesperrt sein (V-186): nur offen gelesen, sonst „?“
            tostring(ezCore.Plain(bar:GetFrameStrata()) or "?"), tostring(ezCore.Plain(MailFrame:GetFrameStrata()) or "?"))
    end
    return line
end)

-- Wer zeigt Anhang-Liste und Wert im Tooltip der Briefliste, und läuft daneben ein Addon mit eigenem Post-Tooltip?
local TOOLTIP_SOURCE_TEXT = { own = "STATUS_TIP_OWN", yield = "STATUS_TIP_YIELD" }
ns.OnStatus(function()
    return L.STATUS_TOOLTIP:format(L[TOOLTIP_SOURCE_TEXT[Inbox.TooltipSource("attachTooltip")]],
        L[TOOLTIP_SOURCE_TEXT[Inbox.TooltipSource("attachValue")]], Inbox.OtherTooltip() or L.STATUS_TIP_NOBODY)
end)

-- Auktionspost (AH-33): Schalter und was im Briefkasten liegt
ns.OnStatus(function()
    local info = Inbox.AuctionMail()
    if not info then return L.STATUS_AHMAIL_OLD end
    return L.STATUS_AHMAIL:format(ns.S.auctionMail and L.YES or L.NO, info.sales, info.returns, #info.taken)
end)

ns.Listen("RUN_CHANGED", function()
    -- Der Auktionspost-Lauf ist zu Ende (Runner.Finish hat die Auswahl eben aufgehoben): Häkchen zurück
    if keepAfterRun and not ns.Runner.IsBusy() then RestoreSelection() end
    Inbox.Refresh()
end)

-- ezCore hat den Posteingang erfasst (0,5 s nach jeder Änderung) und dabei die Auktionspost neu gemerkt: Zeile
-- nachziehen. Einen Schritt später, damit ezCores eigener Zuhörer (History.ScanAuctionMail) sicher vorher lief.
ezCore.Listen("MAILBOX_SCANNED", function()
    C_Timer.After(0, function() ns.Try("Auktionspost", Inbox.UpdateAuctionLine) end)
end, "ezMail")

ns.On("MAIL_INBOX_UPDATE", function()
    Remap()
    Inbox.Refresh()
end)
ns.On("MAIL_SHOW", function() Inbox.ClearSelection() end)
ns.On("MAIL_CLOSED", function() Inbox.ClearSelection() end)

-- „Zeichen am Leuchten“ umgelegt (ezCore 1.12.0): Zeichen vor der Restzeit sofort nachziehen
ezCore.Listen("GLOW_MARKS_CHANGED", function()
    if MailFrame and MailFrame:IsShown() then ns.UpdateInbox() end
end, "ezMail")

ns.OnSettingChanged(function(key)
    if key == "auctionMail" then return Inbox.UpdateAuctionLine() end
    if key ~= "selectBoxes" and key ~= "warnDays" then return end
    if key == "selectBoxes" and not ns.S.selectBoxes then wipe(selected) end
    -- Blizzard zeichnet die Liste neu (Ablaufzeiten, Hinweis „zu viel Post“), danach wir.
    if MailFrame and MailFrame:IsShown() then
        ns.UpdateInbox()
    else
        Inbox.Refresh()
    end
end)
