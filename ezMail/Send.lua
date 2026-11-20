local _, ns = ...
local L = ns.L
local Menu = ezCore.Menu     -- Menüs an einer Stelle (Blizzards MenuUtil)

--[[
    Verschicken: Adressbuch am Empfängerfeld, zuletzt benutzte Empfänger, Betreff bei
    reinem Gold, Alt-Klick auf einen Taschengegenstand hängt alle davon an, und was nicht mehr
    in einen Brief passt, folgt nach dem Senden in weiteren Briefen (Nachsenden).
    Blizzards Namensvervollständigung und Rechtsklick-Anhängen bleiben unberührt.
]]

local Send = {}
ns.Send = Send

local MAX_RECENT = 15

local pendingRecipient     -- an SendMail übergeben, Erfolg steht noch aus
local bookButton

---------------------------------------------------------------------------
-- Zuletzt benutzte Empfänger (pro Realm, für alle Charaktere)
---------------------------------------------------------------------------

local function RecentList()
    local key = ns.RealmKey(ns.realm)
    ns.db.recent[key] = ns.db.recent[key] or {}
    return ns.db.recent[key]
end

function Send.Remember(name)
    name = strtrim(name or "")
    if name == "" then return end
    name = name:gsub("^%l", string.upper)
    local list = RecentList()
    local lower = name:lower()
    for i = #list, 1, -1 do
        if list[i]:lower() == lower then table.remove(list, i) end
    end
    table.insert(list, 1, name)
    while #list > MAX_RECENT do table.remove(list) end
end

function Send.ClearRecent()
    wipe(RecentList())
end

---------------------------------------------------------------------------
-- Einträge fürs Adressbuch
---------------------------------------------------------------------------

-- Eigene Charaktere aus der gemeinsamen Charakterliste (ezCore). Empfänger und „kann Post bekommen“
-- rechnet ezCore.AltRecipient (eine Regel für ezMail und ezCraft, auf WoW Forever dieselbe Erreichbarkeit wie für
-- Kontakte: ezCore.MailReachable). Twinks der anderen Fraktion auf einem erreichbaren Realm stehen grau mit Fraktion
-- dabei, ebenso Twinks mit noch unbekannter Fraktion (Gesamtreview 18.11.2026, T4-NR8); nicht erreichbare Realms fehlen.
local function Alts()
    local seen, list = {}, {}
    for key, data in pairs(ns.Chars()) do
        local recipient, canMail, why = nil, false, nil
        if type(data) == "table" and key ~= ns.charKey then recipient, canMail, why = ezCore.AltRecipient(key) end
        if recipient and (canMail or why == "faction" or why == "unknown") then
            seen[key:lower()] = true
            local text = ns.ClassColored(recipient, data.class)
            if not canMail then
                local factionName = why == "unknown" and L.BOOK_FACTION_UNKNOWN
                    or data.faction == "Horde" and FACTION_HORDE or data.faction == "Alliance" and FACTION_ALLIANCE or data.faction
                text = ezCore.Style.ColorText("gray", recipient .. " (" .. factionName .. ")")   -- nicht erreichbar: ausgegraut
            end
            list[#list + 1] = { name = recipient, text = text, sort = (canMail and "0" or "1") .. recipient:lower() }
        end
    end
    table.sort(list, function(a, b) return a.sort < b.sort end)
    return list, seen
end

-- Freunde (WoW und Battle.net) und Gilde aus ezCores einer Kontaktliste (ezCore.ForEachContact).
-- Empfänger wie Blizzards Post sie schreibt (Ambiguate „mail“): eigener Realm ohne Zusatz, andere mit
-- „-Realm“; auf WoW Forever der volle Name aus Vor- und Nachname (ezCore.ShortName).
-- Battle.net-Name in Blizzards BATTLENET_FONT_COLOR (Design-System 2.5; bisher derselbe Ton 82c5ff als Farbcode)
local function BattleNetText(text)
    local bn = rawget(_G, "BATTLENET_FONT_COLOR")
    if type(bn) == "table" and type(bn.WrapTextInColorCode) == "function" then
        local ok, wrapped = pcall(bn.WrapTextInColorCode, bn, text)
        if ok and type(wrapped) == "string" then return wrapped end
    end
    return text
end

-- Erreichbarkeit wie bei eigenen Twinks: eine Regel in ezCore (ezCore.MailReachable, T4-NR8).
local function Mailable(full)
    return ezCore.MailReachable(full:match("%-(.+)$"))
end

function Send.Contacts()
    local friends, guild, seen = {}, {}, { friend = {}, guild = {} }
    ezCore.ForEachContact(function(full, online, source, bnLabel, classFile)
        if ezCore.IsSelf(full) or not Mailable(full) then return end
        local name = ezCore.ShortName(full)
        local group = source == "guild" and "guild" or "friend"
        local key = name:lower()
        if seen[group][key] then return end
        seen[group][key] = true
        local text = name
        if online and classFile then
            text = ns.ClassColored(name, classFile)
        elseif not online then
            text = ezCore.Style.ColorText("gray", name)   -- offline: ausgegraut (Design-System 2.5)
        end
        if bnLabel then text = text .. " " .. BattleNetText("(" .. bnLabel .. ")") end
        local list = group == "guild" and guild or friends
        list[#list + 1] = { name = name, text = text }
    end)
    local function ByName(a, b) return a.name:lower() < b.name:lower() end
    table.sort(friends, ByName)
    table.sort(guild, ByName)
    return friends, guild
end

---------------------------------------------------------------------------
-- Adressbuch-Menü
---------------------------------------------------------------------------

local function SetRecipient(name)
    local box = SendMailNameEditBox
    if not box then return end
    box:SetText(name)
    box:ClearFocus()
    if SendMailSubjectEditBox and SendMailSubjectEditBox:GetText() == "" then
        SendMailSubjectEditBox:SetFocus()
    end
end

local function AddEntries(parent, entries)
    for _, entry in ipairs(entries) do
        local name = entry.name
        Menu.Button(parent, entry.text, function() SetRecipient(name) end)
    end
end

local function ShowBook(owner)
    -- Gildenliste auffrischen (der Server antwortet nur gedrosselt).
    if IsInGuild and IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end

    local opened = Menu.Open(owner, function(root)
        local any = false
        -- Das aktuelle Ziel, wenn es ein anderer Spieler ist (Adressbuch)
        -- ezCore prüft Einheit und Antworten (Core.UnitIs: gesperrt → nil, dann kein Eintrag; V-184)
        local target = ezCore.UnitIs("target") == true and ezCore.UnitIs("target", "player") == false
            and ezCore.Plain(GetUnitName("target", true))
        local targetFull = type(target) == "string" and ezCore.FullName(target)
        if targetFull then
            local name = ezCore.ShortName(targetFull)
            Menu.Title(root, L.BOOK_TARGET)
            AddEntries(root, { { name = name, text = ns.ClassColored(name, ezCore.Plain((select(2, UnitClass("target"))))) } })
            any = true
        end
        local alts, altSet = Alts()
        if #alts > 0 then
            if any then Menu.Divider(root) end
            Menu.Title(root, L.BOOK_ALTS)
            AddEntries(root, alts)
            any = true
        end

        local recent = {}
        for _, name in ipairs(RecentList()) do
            local key = name:find("-", 1, true) and name or (name .. "-" .. ns.realm)
            if not altSet[key:lower()] then recent[#recent + 1] = { name = name, text = name } end
        end
        if #recent > 0 then
            if any then Menu.Divider(root) end
            Menu.Title(root, L.BOOK_RECENT)
            AddEntries(root, recent)
            any = true
        end

        local friends, guild = Send.Contacts()
        if #friends > 0 or #guild > 0 then
            if any then Menu.Divider(root) end
            if #friends > 0 then
                local sub = Menu.Button(root, L.BOOK_FRIENDS:format(#friends))
                if sub.SetScrollMode and #friends > 20 then sub:SetScrollMode(20 * 20) end
                AddEntries(sub, friends)
            end
            if #guild > 0 then
                local sub = Menu.Button(root, L.BOOK_GUILD:format(#guild))
                if sub.SetScrollMode and #guild > 20 then sub:SetScrollMode(20 * 20) end
                AddEntries(sub, guild)
            end
            any = true
        end

        if not any then Menu.Title(root, L.BOOK_EMPTY) end
        if #RecentList() > 0 then
            Menu.Divider(root)
            Menu.Button(root, L.BOOK_CLEAR, function()
                Send.ClearRecent()
                ns.Print(L.BOOK_CLEARED)
            end)
        end
    end)
    if not opened then ns.Print(L.NO_MENU) end
end

local function UpdateBookButton()
    if not bookButton then return end
    local on = ns.S.addressBook
    bookButton:SetShown(on)
    SendMailNameEditBox:SetTextInsets(0, on and 16 or 0, 0, 0)
end

-- Kleiner Pfeil im rechten Ende des Empfängerfelds, wie bei einem Auswahlfeld.
local function CreateBookButton()
    local box = SendMailNameEditBox
    if not box or bookButton then return end
    bookButton = ezCore.Toolbar.ArrowButton(box, function(self) ShowBook(self) end)
    -- Tooltip mit dem geltenden Befehl, erst beim Zeigen eingesetzt (T18-2)
    bookButton:SetScript("OnEnter", function(self) ns.ShowTip(self, L.BOOK_TITLE, ns.CmdText(L.BOOK_TIP), "ANCHOR_TOP") end)
    bookButton:SetSize(ezCore.Style.BUTTON.small, ezCore.Style.BUTTON.small)   -- kleiner Knopf (16; bisher 18)
    bookButton:SetPoint("RIGHT", box, "RIGHT", 0, 0)
    UpdateBookButton()
end

---------------------------------------------------------------------------
-- Letzten Empfänger eintragen
---------------------------------------------------------------------------

local function FillLastRecipient()
    if not ns.S.lastRecipient then return end
    local box = SendMailNameEditBox
    if not box or box:GetText() ~= "" then return end
    -- Direkt nach dem Senden steht der neue Name noch nicht in der Liste.
    local name = pendingRecipient or RecentList()[1]
    if not name or name == "" then return end
    box:SetText(name)
    box:HighlightText()
end

---------------------------------------------------------------------------
-- Betreff bei reinem Gold (Blizzard verlangt einen Betreff, füllt ihn aber nur bei Gegenständen)
---------------------------------------------------------------------------

local autoSubject
local settingSubject = false

local function HasAttachment()
    for i = 1, ATTACHMENTS_MAX_SEND or 12 do
        if HasSendMailItem(i) then return true end
    end
    return false
end

-- Immer an seit der Einstellungs-Prüfung vom 19.11.2026 (Nr. 10): füllt nur das Pflichtfeld, man kann überschreiben.
local function AutoSubject()
    if settingSubject then return end
    local box = SendMailSubjectEditBox
    if not (box and SendMailMoney and MoneyInputFrame_GetCopper) then return end
    local subject = box:GetText()
    local mine = autoSubject ~= nil and subject == autoSubject
    if subject ~= "" and not mine then return end            -- eigener Betreff des Spielers
    if HasAttachment() then return end                        -- Blizzard nimmt den Gegenstandsnamen
    if SendMailCODButton and SendMailCODButton:GetChecked() then return end

    local money = MoneyInputFrame_GetCopper(SendMailMoney) or 0
    local wanted = money > 0 and ns.PlainMoney(money) or ""
    if wanted == subject then return end
    settingSubject = true
    box:SetText(wanted)
    settingSubject = false
    autoSubject = wanted ~= "" and wanted or nil
end


---------------------------------------------------------------------------
-- Anhängen (Alt-Klick, Schnellanhängen, Weiterleiten) und Nachsenden
---------------------------------------------------------------------------

-- Was nicht mehr in den Brief passt, folgt nach Blizzards „Senden“ in weiteren Briefen
-- an denselben Empfänger. Die Briefe verschickt die Versand-Warteschlange (SendQueue.lua).
local followUp   -- { list = { Einträge }, ids = { [itemID] = true }, seen = { [Platz] = true } }
local armed      -- { to, subject } des gerade verschickten Briefs, wenn danach nachgesendet wird
local queueStarted = false   -- die Warteschlange schickt gerade unseren Rest (der erste Brief ist schon raus)
local followTab              -- Seitenreiter unten rechts am Postfenster: zeigt den Rest, Klick bricht ab

local function Letters(stacks)
    return math.ceil(stacks / (ATTACHMENTS_MAX_SEND or 12))
end

-- Blizzards Senden-Knopf zeigt, was noch folgt: „Senden +1“, während des Nachsendens „Brief 2/3“
-- (der Brief des Spielers zählt als erster mit). Der Reiter daneben macht es sichtbar und abbrechbar.
local function UpdateSendButton()
    local button = SendMailMailButton
    if not button then return end
    local current, total = ns.SendQueue.Progress()
    if not current then queueStarted = false end
    local first = queueStarted and 1 or 0
    if current then
        button:SetText(L.SEND_PROGRESS:format(current + first, total + first))
        button:Disable()
    elseif followUp then
        button:SetText(L.SEND_MORE:format(Letters(#followUp.list)))
    else
        button:SetText(SEND_LABEL or L.SEND)
    end
    if followTab then
        followTab:SetShown(current ~= nil or followUp ~= nil)
        if current then
            followTab.Count:SetText((current + first) .. "/" .. (total + first))
        elseif followUp then
            followTab.Count:SetText("+" .. #followUp.list)
        end
    end
end

function Send.ClearFollowUp(silent)
    if not followUp then return end
    followUp, armed = nil, nil
    if not silent then ns.Print(L.FOLLOW_UP_CLEARED) end
    UpdateSendButton()
end

-- left: was nicht mehr passte; all: der ganze Auftrag. Nachgesendet wird, wenn der verschickte Brief
-- irgendeinen Gegenstand aus dem Auftrag enthält (bei gemischten Kräutern etwa nur andere Sorten).
local function AddFollowUp(left, all)
    followUp = followUp or { list = {}, ids = {}, seen = {} }
    for _, entry in ipairs(all) do followUp.ids[entry.itemID] = true end
    for _, entry in ipairs(left) do
        local key = entry.bag * 1000 + entry.slot
        if not followUp.seen[key] then
            followUp.seen[key] = true
            followUp.list[#followUp.list + 1] = entry
        end
    end
    ns.Print(L.FOLLOW_UP:format(#followUp.list, Letters(#followUp.list)))
    UpdateSendButton()
end

-- Hängt die Stapel an freie Plätze. Was nicht passt, folgt nach dem Senden (Einstellung „Nachsenden“).
function Send.AttachEntries(entries)
    if not entries or #entries == 0 then return false end
    if ns.SendQueue.IsBusy() or ns.SendQueue.IsAttaching() then
        ns.Print(L.ATTACH_BUSY)
        return false
    end
    return ns.SendQueue.Attach(entries, function(left, stats)
        if stats.failed > 0 then ns.Print(L.ATTACH_FAILED) end
        if #left == 0 then return end
        if ns.S.followUp then
            AddFollowUp(left, entries)
        elseif stats.attached == 0 then
            ns.Print(L.ATTACH_FULL)
        else
            ns.Print(L.ATTACH_LEFT:format(#left))
        end
    end)
end

-- Alt-Klick: alle Stapel desselben Gegenstands (gleich gebunden), der geklickte zuerst.
local function SameItems(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not (info and info.itemID) then return nil end
    local bound = info.isBound and true or false
    local list = { { bag = bag, slot = slot, itemID = info.itemID } }
    -- Taschenliste "sell" aus ezCore (mit Reagenzientasche, ohne Schlüsselbund) – wie das Schnellanhängen (MAIL-07)
    ns.ForEachBagItem(function(b, s, other)
        if (b ~= bag or s ~= slot) and other.itemID == info.itemID and not other.isLocked
            and (other.isBound and true or false) == bound then
            list[#list + 1] = { bag = b, slot = s, itemID = other.itemID }
        end
    end, "sell")
    return list
end

-- Lässt sich aus diesem Behälter verschicken? Eine Regel für Alt-Klick und Schnellanhängen: ezCores Taschenliste
-- "sell" (Rucksack, Taschen, Reagenzientasche – nicht Schlüsselbund, nicht Bank). Vorher zählte hier die Zahl der
-- normalen Taschen, die Reagenzientasche fiel heraus (MAIL-07).
function Send.IsSendBag(bag)
    if type(bag) ~= "number" then return false end
    for _, id in ipairs(ezCore.BagList("sell")) do
        if id == bag then return true end
    end
    return false
end

function Send.AttachAll(bag, slot)
    if CursorHasItem() then return end
    local list = SameItems(bag, slot)
    if list then Send.AttachEntries(list) end
end

-- Verschicken-Fenster für eine Weiterleitung füllen; der Empfänger bleibt dem Spieler.
function Send.FillForward(subject, body, money)
    if not (SendMailFrame and SendMailFrame:IsVisible()) and MailFrameTab_OnClick then MailFrameTab_OnClick(nil, 2) end
    if not (SendMailFrame and SendMailFrame:IsVisible()) then return false end
    SendMailSubjectEditBox:SetText(subject)
    if SendMailBodyEditBox then SendMailBodyEditBox:SetText(body) end
    if money and money > 0 and MoneyInputFrame_SetCopper and SendMailMoney then
        MoneyInputFrame_SetCopper(SendMailMoney, money)
    end
    SendMailNameEditBox:SetFocus()
    return true
end

local function OnModifiedItemClick(_, itemLocation)
    if not ns.S.altAttach then return end
    if not IsAltKeyDown() or IsShiftKeyDown() or IsControlKeyDown() then return end
    if GetMouseButtonClicked and GetMouseButtonClicked() ~= "LeftButton" then return end
    if not (MailFrame and MailFrame:IsShown()) then return end
    if not (itemLocation and itemLocation.IsBagAndSlot and itemLocation:IsBagAndSlot()) then return end
    local bag, slot = itemLocation:GetBagAndSlot()
    if not Send.IsSendBag(bag) then return end
    -- Im Posteingang zuerst auf „Verschicken“ wechseln.
    if not SendMailFrame:IsVisible() and MailFrameTab_OnClick then MailFrameTab_OnClick(nil, 2) end
    if SendMailFrame:IsVisible() then Send.AttachAll(bag, slot) end
end

-- Blizzards SendMail: Empfänger merken und prüfen, ob danach nachgesendet wird.
local function OnSendMail(recipient, subject)
    -- Textbriefe aus ezCores Warteschlange (z. B. ezChats Offline-Nachrichten) sind keine Briefe des
    -- Spielers: nicht als letzten Empfänger merken, nichts nachsenden.
    if ns.SendQueue.IsSendingText and ns.SendQueue.IsSendingText() then return end
    pendingRecipient = recipient
    if ns.SendQueue.IsBusy() then return end        -- ein Brief der Warteschlange selbst
    armed = nil
    if not followUp then return end
    local cod = GetSendMailCOD and GetSendMailCOD() or 0
    if cod > 0 then
        ns.Print(L.FOLLOW_UP_COD)
        return
    end
    -- Nur nachsenden, wenn dieser Brief wirklich die angehängten Gegenstände enthält.
    for i = 1, ATTACHMENTS_MAX_SEND or 12 do
        local _, itemID = GetSendMailItem(i)
        if itemID and followUp.ids[itemID] then
            armed = { to = recipient, subject = subject }
            return
        end
    end
end

-- Nachsenden anhalten bzw. abbrechen (Reiter, Rechtsklick auf „Senden“, /ezm stopp).
local function CancelFollowUp()
    if ns.SendQueue.IsBusy() then
        ns.SendQueue.Stop()
    elseif followUp then
        Send.ClearFollowUp()
    end
end

local function ShowFollowUpTip(self, anchor)
    if ns.SendQueue.IsBusy() then
        ns.ShowTip(self, L.SEND_PROGRESS_TIP_TITLE, ns.CmdText(L.SEND_PROGRESS_TIP), anchor)
    elseif followUp then
        ns.ShowTip(self, L.FOLLOW_UP_TIP_TITLE,
            L.FOLLOW_UP_TIP:format(#followUp.list, Letters(#followUp.list)), anchor)
    end
end

local function CreateFollowTab()
    if followTab or not SendMailFrame then return end
    -- Stapel „Brief schreiben“ von unten (vereinbart: Nachsenden 10, ezCraft 20, erster 40 über der Unterkante)
    followTab = ns.CreateSideTab(SendMailFrame, { key = "ezMail.followUp", order = 10, from = "bottom", start = 40,
        owner = "ezMail" })
    followTab.Icon:SetTexture("Interface\\Icons\\INV_Letter_15")
    followTab:SetScript("OnClick", ns.SideTabClick(CancelFollowUp))
    followTab:SetScript("OnEnter", function(self) ShowFollowUpTip(self) end)
    followTab:Hide()
end

local function HookSendButton()
    CreateFollowTab()
    local button = SendMailMailButton
    if not button then return end
    if button.SetMotionScriptsWhileDisabled then button:SetMotionScriptsWhileDisabled(true) end
    button:HookScript("OnMouseUp", function(_, mouse)
        if mouse == "RightButton" then CancelFollowUp() end
    end)
    button:HookScript("OnEnter", function(self) ShowFollowUpTip(self, "ANCHOR_TOP") end)
    button:HookScript("OnLeave", GameTooltip_Hide)
    -- Während des Nachsendens bleibt „Senden“ gesperrt, sonst ginge ein halb gefüllter Brief raus.
    if type(SendMailFrame_CanSend) == "function" then
        hooksecurefunc("SendMailFrame_CanSend", function()
            if ns.SendQueue.IsBusy() then button:Disable() end
        end)
    end
end

---------------------------------------------------------------------------
-- Einhängen
---------------------------------------------------------------------------

ns.WhenMailUI("Adressbuch", CreateBookButton)
ns.WhenMailUI("Betreff bei Gold", function()
    if type(SendMailFrame_CanSend) == "function" then hooksecurefunc("SendMailFrame_CanSend", AutoSubject) end
end)
ns.WhenMailUI("Letzter Empfänger", function()
    if type(MailFrameTab_OnClick) == "function" then
        hooksecurefunc("MailFrameTab_OnClick", function(self, tabID)
            tabID = tabID or (self and self.GetID and self:GetID())
            if tabID == 2 then FillLastRecipient() end
        end)
    end
    if type(SendMailFrame_Reset) == "function" then hooksecurefunc("SendMailFrame_Reset", FillLastRecipient) end
end)
ns.WhenMailUI("Nachsenden", HookSendButton)

ns.OnStatus(function()
    return L.STATUS_SEND:format(bookButton and (bookButton:IsShown() and L.YES or L.STATUS_HIDDEN) or L.STATUS_MISSING_PART)
end)

ns.OnReady(function()
    if type(SendMail) == "function" then hooksecurefunc("SendMail", OnSendMail) end
    if type(HandleModifiedItemClick) == "function" then
        hooksecurefunc("HandleModifiedItemClick", OnModifiedItemClick)
    end
end)

ns.On("MAIL_SEND_SUCCESS", function()
    if pendingRecipient then Send.Remember(pendingRecipient) end
    pendingRecipient = nil
    if armed and followUp then
        local target, list = armed, followUp.list
        followUp, armed = nil, nil
        queueStarted = ns.SendQueue.Add(target.to, target.subject, "", list)
        if not queueStarted then ns.Print(L.ATTACH_LEFT:format(#list)) end
    end
    UpdateSendButton()
end)
ns.On("MAIL_FAILED", function() armed = nil end)
ns.On("MAIL_CLOSED", function()
    pendingRecipient = nil
    Send.ClearFollowUp(true)
end)
ns.Listen("QUEUE_CHANGED", UpdateSendButton)

ns.OnSettingChanged(function(key)
    if key == "addressBook" then UpdateBookButton() end
    if key == "followUp" and not ns.S.followUp then Send.ClearFollowUp() end
end)
