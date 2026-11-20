local _, ns = ...
local L = ns.L
local Menu = ezCore.Menu     -- Menüs an einer Stelle (Blizzards MenuUtil)

--[[
    Gold überweisen (mit Voreinstellungen): Pfeil rechts neben Blizzards
    „Geld schicken:“ auf „Verschicken“. Das Menü zeigt die Voreinstellungen dieses Realms –
    feste Beträge („500 g an Bankchar“) oder „alles über X“ („alles über 1000 g an Bankchar“) –
    und merkt sich das ausgefüllte Formular als neue Voreinstellung.

    Verschickt wird über ezCores Versand-Warteschlange (MailQueue.SendMoney), sobald ezCore sie
    anbietet. Davor fragt ezMail einmal nach – abschaltbar mit dem Schalter „Vor dem Überweisen
    nachfragen“ (wireConfirm, ab Werk an; MAIL-01): Fragt das Spiel beim Gold selbst noch einmal nach
    (sichere Bestätigung), wäre die eigene Rückfrage doppelt. Ohne die Warteschlange trägt ezMail
    Empfänger, Betrag und Betreff in Blizzards Formular ein, und „Senden“ schickt ab.
    Daten: ezMailDB.wire[Realm] = { { to, copper, mode = "amount"|"above" } } (für alle Charaktere).
]]

local Wire = {}
ns.Wire = Wire

local MAX_PRESETS = 12
local button

local function Presets()
    local key = ns.RealmKey(ns.realm)
    ns.db.wire = ns.db.wire or {}
    ns.db.wire[key] = ns.db.wire[key] or {}
    return ns.db.wire[key]
end
Wire.Presets = Presets

-- Porto des Gold-Briefs: eine Stelle in ezCore (Mail.Postage, V-062) – dieselbe Rechnung wie die Warteschlange,
-- die ihn verschickt (Blizzards GetSendMailPrice, sonst das Grundporto).
local function Postage()
    return (ezCore.Mail.Postage())
end
Wire.Postage = Postage

-- Betrag einer Voreinstellung jetzt (0, wenn nichts zu schicken ist).
function Wire.Amount(preset)
    if preset.mode == "above" then
        return math.max(0, GetMoney() - preset.copper - Postage())
    end
    return preset.copper
end

function Wire.Label(preset)
    if preset.mode == "above" then
        return L.WIRE_ABOVE:format(ns.CoinText(preset.copper), preset.to)
    end
    return L.WIRE_AMOUNT:format(ns.CoinText(preset.copper), preset.to)
end

-- Neue Voreinstellung (gleiche ersetzt die alte). Rückgabe: true bei Erfolg.
function Wire.Add(to, copper, mode)
    to = ezCore.Trim(to or "")
    if to == "" or not copper or copper <= 0 then return false end
    to = to:gsub("^%l", string.upper)
    local list = Presets()
    for i = #list, 1, -1 do
        if list[i].to:lower() == to:lower() and list[i].mode == mode then table.remove(list, i) end
    end
    table.insert(list, 1, { to = to, copper = copper, mode = mode })
    while #list > MAX_PRESETS do table.remove(list) end
    ns.Print(L.WIRE_SAVED:format(Wire.Label(list[1])))
    return true
end

function Wire.Remove(index)
    local preset = table.remove(Presets(), index)
    if preset then ns.Print(L.WIRE_REMOVED:format(Wire.Label(preset))) end
end

---------------------------------------------------------------------------
-- Verschicken: Warteschlange (mit ezCore.MailQueue.SendMoney) oder Blizzards Formular
---------------------------------------------------------------------------

local function ShowSendTab()
    if not (SendMailFrame and SendMailFrame:IsVisible()) and MailFrameTab_OnClick then MailFrameTab_OnClick(nil, 2) end
    return SendMailFrame ~= nil and SendMailFrame:IsVisible()
end

-- Empfänger, Betrag und Betreff ins Formular; „Senden“ bleibt dem Spieler (Blizzard fragt bei Gold nach).
function Wire.Fill(to, copper)
    if not ShowSendTab() then return false end
    if SendMailCODButton and SendMailCODButton:GetChecked() then
        ns.Print(L.WIRE_COD)
        return false
    end
    SendMailNameEditBox:SetText(to)
    SendMailNameEditBox:ClearFocus()
    if MoneyInputFrame_SetCopper and SendMailMoney then MoneyInputFrame_SetCopper(SendMailMoney, copper) end
    if SendMailSubjectEditBox and SendMailSubjectEditBox:GetText() == "" then
        SendMailSubjectEditBox:SetText(ns.PlainMoney(copper))
    end
    ns.Print(L.WIRE_FILLED:format(ns.CoinText(copper), to))
    return true
end

local function ViaQueue()
    return type(ezCore.MailQueue.SendMoney) == "function"
end
Wire.ViaQueue = ViaQueue

-- Grund aus ezCore.MailQueue ("money", "closed", "timeout", "blocked", "error" oder Blizzards Fehlermeldung) als Text.
local REASONS = { money = true, closed = true, timeout = true, blocked = true, error = true }
function Wire.Reason(reason)
    if REASONS[reason] then return L["WIRE_FAIL_" .. reason] end
    return tostring(reason or "?")
end

local function QueueSend(to, copper)
    ezCore.MailQueue.SendMoney(to, copper, ns.PlainMoney(copper), "", function(ok, reason)
        if ok then
            ns.Send.Remember(to)
            ns.Print(L.WIRE_SENT:format(ns.CoinText(copper), to))
        else
            ns.Print(L.WIRE_FAILED:format(to, Wire.Reason(reason)))
        end
    end)
end

-- Fragt ezMail vor dem Abschicken über die Warteschlange nach? Nur ein ausdrücklich abgeschalteter Schalter lässt
-- die Rückfrage weg (fehlt der Wert, wird gefragt – im Zweifel geht kein Gold ohne Bestätigung raus).
local function AsksFirst()
    return not (ns.S and ns.S.wireConfirm == false)
end
Wire.AsksFirst = AsksFirst

function Wire.Send(preset)
    if not (MailFrame and MailFrame:IsShown()) then return ns.Print(L.NEED_MAILBOX) end
    local copper = Wire.Amount(preset)
    if copper <= 0 then return ns.Print(L.WIRE_NOTHING:format(ns.CoinText(preset.copper))) end
    if copper + Postage() > GetMoney() then return ns.Print(L.WIRE_NOT_ENOUGH:format(ns.CoinText(copper))) end
    if not ViaQueue() then return Wire.Fill(preset.to, copper) end
    if not AsksFirst() then return QueueSend(preset.to, copper) end
    ezCore.Confirm(L.WIRE_CONFIRM:format(ns.CoinText(copper), preset.to), function()
        -- Seit der Abfrage kann sich das Gold geändert haben: Betrag neu rechnen.
        local now = Wire.Amount(preset)
        if now <= 0 or now + Postage() > GetMoney() then return ns.Print(L.WIRE_NOT_ENOUGH:format(ns.CoinText(now))) end
        QueueSend(preset.to, now)
    end)
end

---------------------------------------------------------------------------
-- Menü am Pfeil neben „Geld schicken:“
---------------------------------------------------------------------------

local function FormValues()
    local to = SendMailNameEditBox and ezCore.Trim(SendMailNameEditBox:GetText() or "") or ""
    local copper = (MoneyInputFrame_GetCopper and SendMailMoney) and MoneyInputFrame_GetCopper(SendMailMoney) or 0
    return to, copper or 0
end

-- Das Menü nach dem Umschalten der Rückfrage neu öffnen (wie Verlauf und Übersicht): Blizzards Häkchen lässt das Menü
-- sonst offen und zeichnet nur die vorhandenen Zeilen neu – der Hinweis unten bliebe beim alten Text stehen.
local function Reopen(owner)
    C_Timer.After(0, function()
        if SendMailFrame and SendMailFrame:IsVisible() then Wire.ShowMenu(owner) end
    end)
end

-- Gesperrter Menüeintrag mit Grund im Tooltip (Gesamtreview 18.11.2026, T9-7; design-system 2.7): Blizzards Menü
-- zeigt den Tooltip auch am gesperrten Eintrag (SetMotionScriptsWhileDisabled im ButtonInitializer der Forever-Quelle).
local function Off(entry, reason)
    entry:SetEnabled(false)
    if reason then Menu.Tip(entry, L.WIRE_OFF_TITLE, reason) end
    return entry
end

-- Warum lässt sich diese Voreinstellung gerade nicht schicken? → Text oder nil (geht)
function Wire.OffReason(copper)
    if ns.SendQueue.IsBusy() then return L.WIRE_OFF_BUSY end
    if copper <= 0 then return L.WIRE_OFF_ZERO end
    if copper + Postage() > GetMoney() then return L.WIRE_OFF_MONEY end
    return nil
end

function Wire.ShowMenu(owner)
    local opened = Menu.Open(owner, function(root)
        Menu.Title(root, L.WIRE_TITLE)
        local list = Presets()
        if #list == 0 then Menu.Title(root, L.WIRE_EMPTY) end
        for _, preset in ipairs(list) do
            local copper = Wire.Amount(preset)
            local text = Wire.Label(preset)
            if preset.mode == "above" then text = text .. " – " .. ns.CoinText(copper) end
            local entry = Menu.Button(root, text, function() Wire.Send(preset) end)
            local why = Wire.OffReason(copper)
            if why then Off(entry, why) end
        end

        -- Mit der Warteschlange schickt ein Klick ab; ins Formular eintragen (etwa für Text oder Anhänge) bleibt.
        if ViaQueue() and #list > 0 then
            local fill = Menu.Button(root, L.WIRE_FILL_MENU)
            for _, preset in ipairs(list) do
                local amount = Wire.Amount(preset)
                local entry = Menu.Button(fill, Wire.Label(preset), function() Wire.Fill(preset.to, Wire.Amount(preset)) end)
                if amount <= 0 then Off(entry, L.WIRE_OFF_ZERO) end
            end
        end
        -- Die Rückfrage dort schaltbar, wo sie wirkt (derselbe Schalter wie auf der Einstellungsseite). Der Hinweis
        -- unten sagt, was ein Klick tut, und muss dem Schalter folgen: Menü schließen (Menu.Close) und neu öffnen.
        if ViaQueue() then
            Menu.Toggle(root, L.OPT_wireConfirm, AsksFirst, function(on)
                ns.SetSetting("wireConfirm", on and true or false)
                Reopen(owner)
                return Menu.Close()
            end)
        end

        Menu.Divider(root)
        local to, copper = FormValues()
        local ready = to ~= "" and copper > 0
        local shown = ready and to or "…"
        local saveAmount = Menu.Button(root, L.WIRE_SAVE_AMOUNT:format(ready and ns.CoinText(copper) or "…", shown),
            function() Wire.Add(to, copper, "amount") end)
        local saveAbove = Menu.Button(root, L.WIRE_SAVE_ABOVE:format(ready and ns.CoinText(copper) or "…", shown),
            function() Wire.Add(to, copper, "above") end)
        if not ready then
            Off(saveAmount, L.WIRE_OFF_FORM)
            Off(saveAbove, L.WIRE_OFF_FORM)
        end
        if #list > 0 then
            local remove = Menu.Button(root, L.WIRE_REMOVE)
            for i, preset in ipairs(list) do
                Menu.Button(remove, Wire.Label(preset), function() Wire.Remove(i) end)
            end
        end
        Menu.Title(root, ViaQueue() and (AsksFirst() and L.WIRE_NOTE_QUEUE or L.WIRE_NOTE_QUEUE_DIRECT) or L.WIRE_NOTE_FORM)
    end)
    if not opened then ns.Print(L.NO_MENU) end
end

local function UpdateButton()
    if button then button:SetShown(ns.S.wire and true or false) end
end

local function CreateButton()
    if button or not SendMailFrame then return end
    button = ezCore.Toolbar.ArrowButton(SendMailFrame, function(self) Wire.ShowMenu(self) end)
    button:SetSize(ezCore.Style.BUTTON.small, ezCore.Style.BUTTON.small)   -- kleiner Knopf (Design-System 2.2; bisher 18)
    local label = _G.SendMailMoneyText
    if label then
        button:SetPoint("LEFT", label, "RIGHT", 2, 0)
    else
        button:SetPoint("BOTTOMLEFT", SendMailFrame, "BOTTOMLEFT", 110, 62)
    end
    -- Tooltip hängt davon ab, ob ezCore Gold verschicken kann und ob ezMail vorher nachfragt
    button:SetScript("OnEnter", function(self)
        ns.ShowTip(self, L.WIRE_TITLE, Wire.TipText(), "ANCHOR_TOP")
    end)
    UpdateButton()
end

function Wire.Button() return button end

function Wire.TipText()
    if not ViaQueue() then return L.WIRE_TIP_FORM end
    return AsksFirst() and L.WIRE_TIP_QUEUE or L.WIRE_TIP_QUEUE_DIRECT
end

ns.WhenMailUI("Gold überweisen", CreateButton)

ns.OnStatus(function()
    return L.STATUS_WIRE:format(button and (button:IsShown() and L.YES or L.STATUS_HIDDEN) or L.STATUS_MISSING_PART,
        #Presets(), ViaQueue() and L.YES or L.NO, AsksFirst() and L.YES or L.NO)
end)

ns.OnSettingChanged(function(key)
    if key == "wire" then UpdateButton() end
end)
