local _, ns = ...
local L = ns.L

-- Kurzüberblick und Rundgang (ezCore/Tests/einfuehrung_funktionen_test.lua): je Zeile von L.INTRO_FEATURES der
-- Schritt (oder die Schritte) des Rundgangs, der sie zeigt; false = kein eigenes Ziel (Automatik, Tooltip, Daten oder
-- ein Fenster ohne Rundgang). Eine neue Zeile im Kurzüberblick braucht hier ihren Eintrag.
ns.FEATURE_STEPS = { "list", { "chatTab", "search" }, "alarms", "offline", false }
local Conv = ns.Conv

-- Gesprächsfenster im Stil des originalen WoW-Forever-UIs. Vorbild ist Blizzards
-- Communities-Fenster: links eine Liste mit einem Reiter pro Gesprächspartner
-- (bluemenu-Hintergrund, Ungelesen-Symbol), rechts der Verlauf aus Flüstern,
-- Briefen und Community wie im Communities-Chat, darunter das Chat-Eingabefeld.
-- Rahmen, Position, Esc, Kopfzeile und Suche kommen aus ezCores Layout-Grundlage (ezCore.NewWindow):
-- Kopfzeile „Neues Gespräch“, „Alarme“, Suche (Gespräche und gespeicherter Kanalverlauf) oben rechts,
-- „Einstellungen“ unten rechts. Über dem Verlauf: Name des Partners (Klick: Blizzards Spieler-Menü) und die Schalter
-- „Alarm“ und „Stumm“; darunter die Hinweiszeile (wartend, offline, „tippt …“, Ort laut ezChat). In der Liste steht
-- unten der Bereich „Gefiltert“ (Spam.lua), sobald der Spam-Filter etwas abgelegt hat.

local Window = {}
ns.Window = Window

local LAYOUT = ezCore.LAYOUT
local POSITION_KEY = "ezChat.window"   -- ezCoreDB.positions; die alte Lage aus ezChatDB.window wird einmal übernommen
local FOOT = LAYOUT.FOOTER_H + 4       -- Platz unten für den Knopf „Einstellungen“
local W, H = 640, 486 + FOOT
local CHAT_BOTTOM = 66 + FOOT          -- unter dem Verlauf: Hinweiszeile und Eingabefeld
local LIST_W = 196
local DOCK_GAP = 36                    -- angedockt: Platz für ezChats Seitenreiter rechts an der Freundesliste
local ROW_H = 38
local ICON = "Interface\\Icons\\INV_Letter_15"
local MENU_TEXTURE = "Interface\\Common\\bluemenu-main"
local ONLINE_ICON = FRIENDS_TEXTURE_ONLINE or "Interface\\FriendsFrame\\StatusIcon-Online"
local OFFLINE_ICON = FRIENDS_TEXTURE_OFFLINE or "Interface\\FriendsFrame\\StatusIcon-Offline"
local HISTORY_KEY = "#history"   -- Eintrag „Kanalverlauf“ in den Suchergebnissen
local FILTERED_KEY = ns.Spam.KEY  -- Bereich „Gefiltert“ (Spam-Filter)

-- Eintrag ohne Gespräch (Kanalverlauf, Gefiltert)?
local function Special(key) return key == HISTORY_KEY or key == FILTERED_KEY end

local frame, listInset, scrollBox, chatInset, messages, editBox, placeholder, searchBox
local headerText, hintText, emptyText, listEmptyText, alarmCheck, muteCheck, moreButton, sendButton, nameButton
local SEND_W = 84                      -- Knopf „Senden“ rechts neben dem Eingabefeld
local selected
local query          -- Suchbegriff (klein geschrieben) oder nil
local docked = false -- an Blizzards Freundesliste angedockt (FriendsDock.lua)?
local dirtyList, dirtyMessages = false, false

---------------------------------------------------------------------------
-- Darstellung
---------------------------------------------------------------------------

-- Farbe eines Chat-Typs: ns.WhisperColor (Core.lua) kennt Blizzards ChatTypeInfo und die Ersatzfarben.
local function TypeColor(chatType)
    if type(chatType) ~= "string" then return 1, 1, 1 end
    return ns.WhisperColor(chatType)
end

local function Selected()
    return selected and ns.C and ns.C.convos[selected] or nil
end

-- Eigene Klasse (für „Du“ in Klassenfarbe).
-- ezCore.PlayerClass: Klassen-Token, nil bei gesperrtem oder fehlendem Wert (V-179).
local function OwnClass()
    return ezCore.PlayerClass()
end

-- Name des Partners für Kopf und Verlauf: Battle.net blau, sonst in Klassenfarbe (immer, seit der Prüfung der
-- Einstellungen vom 19.11.2026, Nr. 23), sobald die Klasse bekannt ist.
function ns.PartnerName(convo)
    local name = Conv.Display(convo)
    if convo.bn then return ns.ColorText("bnet", name) end
    local class = Conv.ClassOf(convo)
    if class then return ezCore.ClassText(name, class) end
    return name
end

-- Nachrichtentext für die Anzeige: Internetadressen als Link, Suchbegriff markiert.
local function ShownText(text, mark)
    text = text or ""
    if ns.S.links and ns.Format then text = ns.Format.Linkify(text) end
    if mark and ns.Format then text = ns.Format.MarkQuery(text, mark) end
    return text
end

local function MessageLine(convo, msg, mark)
    local chatType
    if convo.bn then
        chatType = msg.o and "BN_WHISPER_INFORM" or "BN_WHISPER"
    else
        chatType = msg.o and "WHISPER_INFORM" or "WHISPER"
    end
    local r, g, b = TypeColor(chatType)
    local who
    if msg.o then
        who = L.YOU
        local class = OwnClass()
        if class then who = ezCore.ClassText(who, class) end
    else
        who = ns.PartnerName(convo)
    end
    local note = ""
    if msg.v == "p" then
        note = " " .. ezCore.Grey(L.VIA_MAIL)          -- Quelle der Nachricht: ezCores Grau (Design-System 2.5)
    elseif msg.v == "c" then
        note = " " .. ezCore.Grey(L.VIA_COMMUNITY)
    end
    if msg.a then note = note .. " " .. ezCore.Grey(L.AUTO_REPLY_MARK) end
    if msg.s == "q" then
        r, g, b = ns.RGB("grey")   -- wartend gedämpft in ezCores Grau, fehlgeschlagen dunkler (Rollen, Welle 23, A5)
        -- angehalten nach zu vielen Versuchen (Risiko 9 der Prüfung vom 17.11.2026): wartet sichtbar weiter
        note = note .. " " .. ezCore.Gold(msg.h and L.STATE_HELD or L.STATE_QUEUED)
    elseif msg.s == "x" then
        r, g, b = ns.RGB("gray")
        note = note .. " " .. ns.ColorText("bad", L.STATE_FAILED)   -- Blizzards Rot statt ff5050
    elseif msg.o and msg.d then
        note = note .. " " .. ezCore.Grey(L.STATE_DELIVERED:format(ns.TimeText(msg.d)))
    end
    return ("%s %s: %s%s"):format(ezCore.Grey(ns.TimeText(msg.t)), who, ShownText(msg.m, mark), note), r, g, b
end

---------------------------------------------------------------------------
-- Nachrichtenansicht: gemeinsam für das Gesprächsfenster und die Gesprächsansicht
-- im Chatfenster (ChatView.lua)
---------------------------------------------------------------------------

-- Graue Zeile im Verlauf (Tagestrenner, „noch nichts“, Hinweise): Blizzards GRAY_FONT_COLOR über die Rolle „gray“
-- (Welle 23, A5; vorher 0.5, 0.5, 0.5 – derselbe Ton).
local function GrayLine(view, text)
    local r, g, b = ns.RGB("gray")
    view:AddMessage(text, r, g, b)
end

-- mark: Suchbegriff – dann nur passende Nachrichten, der Begriff markiert.
local function FillMessages(view, convo, mark)
    view:Clear()
    if not convo then return end
    local lastDay, shown = nil, 0
    for _, msg in ipairs(convo.msgs) do
        if Conv.MessageMatches(msg, mark) then
            local day = date("%Y%m%d", msg.t)
            if day ~= lastDay then
                GrayLine(view, L.DAY_LINE:format(date(L.DATE_YEAR, msg.t)))
                lastDay = day
            end
            view:AddMessage(MessageLine(convo, msg, mark))
            shown = shown + 1
        end
    end
    if #convo.msgs == 0 then
        GrayLine(view, L.CONVO_EMPTY)
    elseif shown == 0 then
        GrayLine(view, L.SEARCH_NO_MESSAGES)
    end
    view:ScrollToBottom()
end

-- Treffer im gespeicherten Kanalverlauf (Gilde, Gruppe, Sagen) wie im Chat.
local function FillHistory(view, mark)
    view:Clear()
    local lastDay
    for _, item in ipairs(ns.History.Search(mark)) do
        local day = date("%Y%m%d", item.t)
        if day ~= lastDay then
            GrayLine(view, L.DAY_LINE:format(date(L.DATE_YEAR, item.t)))
            lastDay = day
        end
        local r, g, b = TypeColor(item.chatType)
        view:AddMessage(("%s %s"):format(ezCore.Grey(ns.TimeText(item.t)), ezCore.Usable(item.line) and
            ns.Format.MarkQuery(item.line, mark) or item.line), r, g, b)
    end
    view:ScrollToBottom()
end

-- Bereich „Gefiltert“: die abgelegten Flüster-Nachrichten mit Absender und Grund, grau (Spam.lua).
local function FillFiltered(view)
    view:Clear()
    local list = ns.Spam.List()
    if #list == 0 then GrayLine(view, L.SPAM_EMPTY) end
    local lastDay
    local r, g, b = ns.RGB("grey")   -- gefilterte Nachricht in ezCores Grau (vorher 0.6)
    for _, entry in ipairs(list) do
        local day = date("%Y%m%d", entry.t)
        if day ~= lastDay then
            GrayLine(view, L.DAY_LINE:format(date(L.DATE_YEAR, entry.t)))
            lastDay = day
        end
        local reason = L["SPAM_REASON_" .. tostring(entry.r)] or ""
        view:AddMessage(("%s %s: %s %s"):format(ezCore.Grey(ns.TimeText(entry.t)), ns.Short(entry.n or "?"),
            ns.PlainText(entry.m or ""), ns.ColorText("gray", "(" .. reason .. ")")), r, g, b)
    end
    GrayLine(view, L.SPAM_VIEW_HINT)
    view:ScrollToBottom()
end

-- Link-Tooltip (I2, Gesamtreview 18.11.2026): Zeigt die Maus im Verlauf auf einen Link, erscheint Blizzards
-- GameTooltip dazu – immer (seit der Prüfung der Einstellungen vom 19.11.2026 kein Schalter mehr). Nur Linkarten, die GameTooltip:SetHyperlink kennt;
-- Internetadressen (ezChats eigene Links), Addon-Links und alles Unbekannte bleiben ohne Tooltip. Gilt nur für
-- ezChats eigene Verlaufsansicht (Gesprächsfenster und Gesprächsansicht) – Blizzards Chatfenster fasst ezChat nicht an.
-- Prat zeigt Link-Tooltips nur in Blizzards Chatfenstern (ns.HINT_BY: Hinweis im Tooltip der Überschrift
-- „Gesprächsfenster“ auf der Einstellungsseite, ezChat bleibt an).
ns.LINK_TOOLTIP_TYPES = { item = true, spell = true, enchant = true, quest = true, achievement = true, talent = true,
    currency = true }

-- Linkart eines Hyperlinks („item:19019:…“ → "item") oder nil (kein Text, geheim, unbekannte Art).
function ns.LinkTooltipType(link)
    if ns.IsSecret(link) or type(link) ~= "string" then return nil end
    local kind = link:match("^(%a+):")
    return kind and ns.LINK_TOOLTIP_TYPES[kind] and kind or nil
end

local function LinkEnter(view, link)
    if not ns.LinkTooltipType(link) then return end   -- immer (Prüfung der Einstellungen vom 19.11.2026, Nr. 24)
    local tip = rawget(_G, "GameTooltip")
    if not (tip and tip.SetOwner and tip.SetHyperlink) then return end
    tip:SetOwner(view, "ANCHOR_CURSOR")
    -- pcall: eine Linkart kann im Client fehlen oder der Link kaputt sein – dann eben kein Tooltip
    if pcall(tip.SetHyperlink, tip, link) then
        tip:Show()
    else
        tip:Hide()
    end
end

-- Nur den eigenen Tooltip schließen (auch wenn der Schalter inzwischen aus ist), nie einen fremden.
local function LinkLeave(view)
    local tip = rawget(_G, "GameTooltip")
    if tip and tip.IsOwned and tip:IsOwned(view) then tip:Hide() end
end

-- Verlauf eines Gesprächs als ScrollingMessageFrame mit Blizzards schmaler
-- Bildlaufleiste rechts daneben. view:Fill(convo) zeigt ein Gespräch.
function ns.CreateMessageView(parent)
    local view = CreateFrame("ScrollingMessageFrame", nil, parent)
    view:SetFontObject(ChatFontNormal)   -- Schrift wie Blizzards Chat (Nachbild, Design-System 2.4)
    view:SetJustifyH("LEFT")
    view:SetFading(false)
    view:SetMaxLines(1000)
    view:SetHyperlinksEnabled(true)
    if view.SetTextCopyable then view:SetTextCopyable(true) end
    if view.SetIndentedWordWrap then view:SetIndentedWordWrap(true) end
    view:SetScript("OnHyperlinkClick", function(_, link, text, button)
        if ns.Format and ns.Format.HandleLink(link, text) then return end   -- Internetadresse: zum Kopieren
        if type(SetItemRef) == "function" then pcall(SetItemRef, link, text, button, nil) end
    end)
    view:SetScript("OnHyperlinkEnter", function(self, link) LinkEnter(self, link) end)
    view:SetScript("OnHyperlinkLeave", function(self) LinkLeave(self) end)
    view:EnableMouseWheel(true)
    view:SetScript("OnMouseWheel", function(self, delta)
        if self.ScrollByAmount then
            self:ScrollByAmount(delta * 3)
        elseif delta > 0 then
            self:ScrollUp()
        else
            self:ScrollDown()
        end
    end)

    local bar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
    bar:SetPoint("TOPLEFT", view, "TOPRIGHT", 6, 0)
    bar:SetPoint("BOTTOMLEFT", view, "BOTTOMRIGHT", 6, 0)
    local ok, err = false, nil
    if ScrollUtil and ScrollUtil.InitScrollingMessageFrameWithScrollBar then
        ok, err = pcall(ScrollUtil.InitScrollingMessageFrameWithScrollBar, view, bar)
        if not ok then ns.Error(err) end
    end
    if not ok then bar:Hide() end

    view.Fill = FillMessages
    view.ScrollBarFrame = bar
    return view
end

-- Stufe, Klasse und Gebiet als Text in einer Farbe („Stufe 25 Magierin – Dunkelküste“). Der Klassenname trägt
-- auf Wunsch seine Klassenfarbe und beendet damit die Farbe davor – darum bekommt das Gebiet sie neu.
local function InfoText(info, color)
    local class = info.class or ""
    if info.classFile and class ~= "" then class = ezCore.ClassText(class, info.classFile) end
    local text = color .. ns.Trim(L.INFO_LEVEL_CLASS:format(info.level, class)) .. "|r"
    if type(info.zone) == "string" and info.zone ~= "" then
        text = text .. " " .. color .. L.INFO_ZONE:format(info.zone) .. "|r"
    end
    return text
end

-- Zuletzt bekannte Angaben eines Partners, der offline ist, und ihre Quelle (Leitlinie 11: jede Angabe nennt ihre
-- Quelle – offline kann sie alt sein). Die Daten liefert Delivery.LastKnown.
-- → Angabe („Stufe 25 Magierin – Dunkelküste“; Battle.net: „Bodo: Stufe 20 Krieger“),
--   Quelle („laut Gilde“, „laut Freundesliste“, „zuletzt gesehen am 12.11.2026 14:05“),
--   bei Gildenmitgliedern „zuletzt online vor 3 Tagen“ (laut Gildenliste; nur im Tooltip, der Kopf bleibt kurz) – oder nil
-- Offline-Angaben ausgegraut: Blizzards GRAY_FONT_COLOR (Rolle „gray“, Design-System 2.5)
local OFFLINE_INFO = ns.ColorCode("gray")
function ns.LastKnownText(convo)
    local info = ns.Delivery.LastKnown(convo)
    if not info then return nil end
    local text = InfoText(info, OFFLINE_INFO)
    if info.name then text = OFFLINE_INFO .. info.name .. ":|r " .. text end
    local source
    if info.source == "seen" then
        source = L.INFO_SEEN:format(ezCore.DateText(info.seen, "long"))
    else
        source = L.SOURCES_ACCORDING:format(L["INFO_SOURCE_" .. tostring(info.source)] or tostring(info.source))
    end
    return text, source, ns.LastOnlineText(info)
end

-- „laut Gildenliste zuletzt online vor …“. Blizzards Gildenliste kennt nur ganze Stunden: unter einer Stunde
-- (alle Teile 0) „vor weniger als einer Stunde“ wie Blizzards Gildenfenster, sonst ezCore.Ago (ezCores lastSeen
-- entsteht bei jedem Neubau der Liste neu und gäbe sonst „gerade eben“). nil ohne Angabe der Gildenliste.
function ns.LastOnlineText(info)
    if not (info and info.lastSeen) then return nil end
    local t = info.lastOnline
    if type(t) == "table" and (tonumber(t.years) or 0) == 0 and (tonumber(t.months) or 0) == 0
        and (tonumber(t.days) or 0) == 0 and (tonumber(t.hours) or 0) == 0 then
        return L.INFO_LAST_ONLINE:format(L.INFO_LAST_HOUR)
    end
    return L.INFO_LAST_ONLINE:format(ezCore.Ago(info.lastSeen))
end

-- Kopfzeile eines Gesprächs: Name mit Online-Status und ein Hinweis
-- (Zweier-Community, wartende Nachrichten, offline).
-- short = true: ohne die Angaben eines Offline-Partners (enger Kopf, Gesprächsansicht im Chatfenster).
function ns.ConvoStatus(convo, short)
    local online = ns.Delivery.IsOnline(convo)
    local state
    if online == true then
        state = ns.ColorText("good", L.ONLINE)   -- Blizzards Grün statt 40ff40 (Design-System 2.5)
    elseif online == false then
        state = ezCore.Grey(L.OFFLINE)
    else
        state = ezCore.Grey(L.STATUS_UNKNOWN)
    end
    local name = ns.PartnerName(convo)
    -- Wer schreibt da? Stufe, Klasse und Gebiet, solange der Partner online ist.
    local info = online == true and ns.S.partnerInfo and ns.Delivery.PartnerInfo(convo)
    if info and type(info.level) == "number" and info.level > 0 then
        state = state .. "  " .. InfoText(info, ezCore.GREY)
    elseif online == false and ns.S.partnerInfo and not short then
        -- offline: die zuletzt bekannte Angabe, dunkler und mit ihrer Quelle
        local text, source = ns.LastKnownText(convo)
        if text then state = state .. "  " .. text .. " " .. OFFLINE_INFO .. "(" .. source .. ")|r" end
    end
    if convo.muted then state = state .. "  " .. ns.ColorText("orange", L.MUTED_MARK) end

    local hint = ""
    local queued = Conv.CountQueued(convo)
    local pair = not convo.bn and ns.Community and ns.S.community and ns.Community.FindFor(convo.name)
    if pair then
        hint = L.HINT_COMMUNITY:format(pair.name or "?")
    elseif queued > 0 then
        hint = L.HINT_QUEUED:format(queued, ns.Delivery.WaysText(convo))
    elseif online == false and ns.S.offlineQueue then
        hint = L.HINT_OFFLINE:format(ns.Delivery.WaysText(convo))
    end
    return name .. "  " .. state, hint
end

local function ShowMessages()
    dirtyMessages = false
    if not messages then return end
    if selected == HISTORY_KEY and query then
        emptyText:Hide()
        FillHistory(messages, query)
        return
    end
    if selected == FILTERED_KEY then
        emptyText:Hide()
        FillFiltered(messages)
        return
    end
    local convo = Selected()
    emptyText:SetShown(convo == nil)
    messages:Fill(convo, query)
end

local function SetEnabled(widget, enabled)
    if widget.SetEnabled then
        widget:SetEnabled(enabled)
    elseif enabled and widget.Enable then
        widget:Enable()
    elseif not enabled and widget.Disable then
        widget:Disable()
    end
end

local function UpdatePlaceholder()
    if placeholder then
        placeholder:SetShown(editBox:GetText() == "" and not editBox:HasFocus() and Selected() ~= nil)
    end
end

-- Hinweiszeile unter dem Verlauf: „tippt …“ und Ort laut ezChat (Typing.lua) vor dem Hinweis des Gesprächs.
local function HintFor(key, hint)
    local parts = {}
    if ns.Typing and ns.Typing.IsTyping(key) then parts[#parts + 1] = ezCore.Gold(L.TYPING_NOW) end
    local zone = ns.Typing and ns.Typing.Zone(key)
    if zone then parts[#parts + 1] = L.TYPING_ZONE:format(zone) end
    if hint and hint ~= "" then parts[#parts + 1] = hint end
    return table.concat(parts, "  ")
end
Window.HintFor = HintFor

local function UpdateHeader()
    local convo = Selected()
    SetEnabled(editBox, convo ~= nil)
    if sendButton then SetEnabled(sendButton, convo ~= nil) end
    UpdatePlaceholder()
    alarmCheck:SetShown(convo ~= nil and not convo.bn)   -- Battle.net-Freunde schreiben nicht in Kanälen
    muteCheck:SetShown(convo ~= nil)
    if moreButton then moreButton:SetShown(convo ~= nil or selected == FILTERED_KEY) end
    if nameButton then nameButton:SetShown(convo ~= nil) end
    if not convo then
        if selected == FILTERED_KEY then
            headerText:SetText(L.SPAM_HEADER:format(ns.Spam.Count()))
            hintText:SetText(L.SPAM_HINT)
            return
        end
        headerText:SetText(selected == HISTORY_KEY and query and L.SEARCH_HISTORY_HEADER:format(query) or "")
        hintText:SetText("")
        return
    end
    alarmCheck:SetChecked(convo.alarm == true)
    muteCheck:SetChecked(convo.muted == true)
    local header, hint = ns.ConvoStatus(convo)
    headerText:SetText(header)
    -- Kopf zu eng für die Angaben eines Offline-Partners (der Name endet links vor „Alarm“): kurze Fassung wie
    -- bisher; Angabe und Quelle stehen dann im Tooltip der Gesprächszeile (Window.AddInfoLines).
    if headerText.IsTruncated and headerText:IsTruncated() then
        headerText:SetText((ns.ConvoStatus(convo, true)))
    end
    hintText:SetText(HintFor(selected, hint))
end

-- „tippt …“ bzw. Ort hat sich geändert (Typing.lua): nur die Hinweiszeile des gewählten Gesprächs auffrischen.
function Window.RefreshHint(key)
    if frame and frame:IsShown() and key == selected and Selected() then UpdateHeader() end
end

---------------------------------------------------------------------------
-- Liste der Gespräche (Reiter)
---------------------------------------------------------------------------

-- Blizzards eigenes Spieler-Menü für den Partner (Leitlinie 1: das Original). Was es anbietet, entscheidet Blizzard:
-- Flüstern, Einladen, Ignorieren, Melden, Namen kopieren … (Menü „FRIEND“ wie ein Klick auf einen Namen im Chat).
-- Offline: Blizzards Menü für Offline-Freunde.
-- Nie das Menü der Einheit („PLAYER“/„PARTY“/„RAID_PLAYER“), auch nicht für einen Partner in Reichweite (Gesamtreview
-- 18.11.2026, T2-3, Leitlinie 5): Aus Addon-Code geöffnet, entsteht es mit Addon-Spuren. Blizzards Forever-Quelle
-- (Gethe/wow-ui-source, Zweig forever, Blizzard_UnitPopupShared/UnitPopupSharedMenus.lua und
-- UnitPopupSharedButtonMixins.lua) zeigt: „Ziel auswählen“ blendet sich dann selbst aus (CanShow prüft issecure),
-- „Fokus setzen“ (UnitPopupSetFocusButtonMixin, im Untermenü des Spieler-Menüs und im Raid-Menü) prüft es nicht und
-- ruft das geschützte FocusUnit – Blizzard blockiert es („Aktion durch AddOn blockiert“). Das Menü „FRIEND“ hat keinen
-- solchen Eintrag (sein „Ziel auswählen“ blendet sich aus); so öffnet es auch Blizzards Chat bei einem Klick auf einen
-- Namen. Betrachten und Handeln gehen über Blizzards Einheitenrahmen (Rechtsklick auf Ziel- bzw. Gruppenrahmen).
-- Battle.net: Blizzards Menü für Battle.net-Freunde („BN_FRIEND“, offline „BN_FRIEND_OFFLINE“) mit Blizzards
-- Kontonamen wie in der Freundesliste; Blizzards Funktion öffnet ohne Verbindung nur mit friendsList (Argument 6).
-- → Menü-Art oder nil, wenn Blizzards Funktion fehlt
function Window.PlayerMenu(convo)
    if not convo then return nil end
    local online = ns.Delivery.IsOnline(convo)
    if convo.bn then
        local show = rawget(_G, "FriendsFrame_ShowBNDropdown")
        local id, _, accountName = ns.BNFind(convo.name)
        if type(show) ~= "function" or not id then return nil end
        local connected = online ~= false
        local ok, err = pcall(show, accountName or Conv.Display(convo), connected, nil, "BN_WHISPER", nil,
            (not connected) and 1 or nil, id, nil, nil, nil, nil, convo.name)
        if not ok then ns.Error(err) end
        return ok and (connected and "BN_FRIEND" or "BN_FRIEND_OFFLINE") or nil
    end
    local open = rawget(_G, "UnitPopup_OpenMenu")
    local guid = Conv.guids[Conv.KeyOf(convo.name)]
    local name = ns.LinkName(convo.name)
    if online == false then
        if type(open) ~= "function" then return nil end
        local ok, err = pcall(open, "FRIEND_OFFLINE", { name = name, chatTarget = name, chatType = "WHISPER" })
        if not ok then ns.Error(err) end
        return ok and "FRIEND_OFFLINE" or nil
    end
    local show = rawget(_G, "FriendsFrame_ShowDropdown")
    if type(show) ~= "function" then return nil end
    local ok, err = pcall(show, name, true, nil, "WHISPER", nil, nil, nil, nil, nil, nil, guid)
    if not ok then ns.Error(err) end
    return ok and "FRIEND" or nil
end

-- Verlauf eines Gesprächs zum Kopieren (ezCores Textfenster; nichts wird in eine Datei geschrieben).
function Window.CopyHistory(convo)
    if not convo then return end
    ezCore.TextDialog({ owner = "ezChat", title = L.COPY_TITLE:format(Conv.Display(convo)), text = Conv.CopyText(convo),
        hint = L.COPY_HINT, select = true, accept = false })
end

-- Aufbewahrung je Partner: Standard (Einstellung), 7, 30, 90 Tage oder nie nach Tagen kürzen.
local KEEP_CHOICES = { 7, 30, 90, 0 }
local function KeepMenu(root, key, convo)
    local sub = root:CreateButton(L.MENU_KEEP:format(convo.keepDays and (convo.keepDays == 0 and L.KEEP_FOREVER
        or L.KEEP_DAYS:format(convo.keepDays)) or L.KEEP_DEFAULT))
    local function Get() return convo.keepDays or -1 end
    local function Pick(days)
        local removed = Conv.SetKeepDays(key, days >= 0 and days or nil)
        if removed > 0 then ns.Print(L.KEEP_REMOVED:format(removed)) end
    end
    ezCore.Menu.Radio(sub, L.KEEP_DEFAULT_LONG:format(ns.Number("keepDays") == 0 and L.KEEP_FOREVER
        or L.KEEP_DAYS:format(ns.Number("keepDays"))), Get, Pick, -1)
    for _, days in ipairs(KEEP_CHOICES) do
        ezCore.Menu.Radio(sub, days == 0 and L.KEEP_FOREVER or L.KEEP_DAYS:format(days), Get, Pick, days)
    end
end

-- Menü zu einem Gespräch: Rechtsklick auf die Zeile links oder der Pfeil oben rechts über dem Verlauf.
local function ConvoMenu(owner, key)
    local convo = key and ns.C.convos[key]
    if not convo then return end
    ns.OpenMenu(owner, function(root)
        root:CreateTitle(Conv.Display(convo))
        root:CreateButton(L.MENU_CHAT_WRITE, function() ns.Chat.Start(convo.name, convo.bn) end)
        root:CreateButton(L.MENU_PLAYER, function() Window.PlayerMenu(convo) end)
        if Conv.CountQueued(convo) > 0 then
            -- von Hand: auch eine angehaltene Nachricht, ohne Mindestabstand (Delivery.Retry)
            root:CreateButton(L.MENU_TRY_NOW, function() ns.Delivery.Retry(key) end)
            root:CreateButton(L.MENU_CANCEL_QUEUE, function()
                ns.Print(L.CANCELLED:format(Conv.Cancel(key)))
            end)
        end
        ns.FlagEntries(root, key)
        if ns.Spam.Allowed(key) then
            -- über „Doch zeigen“ freigegeben: Freigabe zurücknehmen (Spam.lua)
            root:CreateButton(L.MENU_SPAM_FORBID, function()
                if ns.Spam.Forbid(key) then ns.Print(L.SPAM_FORBIDDEN:format(Conv.Display(convo))) end
            end)
        end
        root:CreateDivider()
        root:CreateButton(L.MENU_COPY, function() Window.CopyHistory(convo) end)
        KeepMenu(root, key, convo)
        root:CreateButton(L.MENU_CLEAR_HISTORY, function()
            ns.Confirm(L.CONFIRM_CLEAR_HISTORY:format(Conv.Display(convo)), function()
                ns.Print(L.HISTORY_CLEARED:format(Conv.ClearHistory(key), Conv.Display(convo)))
            end)
        end)
        root:CreateButton(L.MENU_DELETE, function()
            ns.Confirm(L.CONFIRM_DELETE:format(Conv.Display(convo)), function()
                if selected == key then selected = nil end
                Conv.Delete(key)
                Window.Refresh()
            end)
        end)
    end)
end

-- Menü am Bereich „Gefiltert“: je Absender „Doch zeigen“ (das Gespräch geht dann auf), Stichwörter, verwerfen.
local function FilteredMenu(owner)
    ns.OpenMenu(owner, function(root) ns.Spam.FillMenu(root, function(key) Window.Select(key) end) end)
end
Window.FilteredMenu = FilteredMenu

local function RowMenu(row)
    if row.key == FILTERED_KEY then return FilteredMenu(row) end
    ConvoMenu(row, row.key)
end

-- Einträge „Alarm“ und „Stumm“ für ein Gespräch (Menüs im Gesprächsfenster und in der Gesprächsauswahl).
function ns.FlagEntries(menu, key)
    local convo = key and ns.C and ns.C.convos[key]
    if not convo then return end
    menu:CreateDivider()
    local function Entry(text, flag)
        local function Get() return convo[flag] == true end
        local function Set() Conv.SetFlag(key, flag, not convo[flag]) end
        ezCore.Menu.Toggle(menu, text, Get, Set)
    end
    if not convo.bn then Entry(L.PARTNER_ALARM, "alarm") end
    Entry(L.PARTNER_MUTE, "muted")
end

-- Aufbau wie Blizzards CommunitiesListEntryTemplate (Hintergrund, Auswahl, Hervorhebung).
local function MenuTexture(region, top, bottom)
    region:SetTexture(MENU_TEXTURE)
    region:SetTexCoord(0.00390625, 0.87890625, top, bottom)
end

-- Twinks eines Battle.net-Freundes (ezCore.BNAlts, zuletzt gesehen zuerst) als Zeilen im Tooltip; der gerade
-- gespielte Charakter bleibt weg. Rückgabe: Anzahl gezeigter Twinks.
local MAX_ALT_LINES = 6
function Window.AddAltLines(tooltip, convo)
    if not (convo and convo.bn) then return 0 end
    local id = ns.BNFind(convo.name)
    local playing = id and ezCore.BNCharacter(ezCore.BNInfoByID(id))
    local alts = ezCore.BNAlts(convo.name, playing)
    if #alts == 0 then return 0 end
    tooltip:AddLine(" ")
    local r, g, b = ns.RGB("normal")   -- Farben aus ezCores Rollen (Welle 23, A5)
    tooltip:AddLine(L.ROW_ALTS, r, g, b)
    local shown = math.min(#alts, MAX_ALT_LINES)
    local wr, wg, wb = ns.RGB("highlight")
    r, g, b = ns.RGB("grey")
    for i = 1, shown do
        local alt = alts[i]
        local name = ezCore.ShortName(alt.name) or alt.name
        if alt.class then name = ezCore.ClassText(name, alt.class) end
        local level = tonumber(alt.level)
        tooltip:AddDoubleLine(name, level and L.ALT_LEVEL:format(level) or "", wr, wg, wb, r, g, b)
    end
    if #alts > shown then tooltip:AddLine(ezCore.More(#alts - shown), r, g, b) end
    return shown
end

-- Stufe, Klasse und Gebiet des Partners als Zeilen im Tooltip der Gesprächszeile (Schalter „Stufe, Klasse und
-- Gebiet des Partners“): online eine Zeile, offline die zuletzt bekannte Angabe und darunter ihre Quelle
-- (ns.LastKnownText), bei Gildenmitgliedern dazu „zuletzt online vor …“. Rückgabe: Anzahl der Zeilen.
function Window.AddInfoLines(tooltip, convo)
    if not (convo and ns.S.partnerInfo) then return 0 end
    if ns.Delivery.IsOnline(convo) == true then
        local info = ns.Delivery.PartnerInfo(convo)
        if not (info and type(info.level) == "number" and info.level > 0) then return 0 end
        tooltip:AddLine(InfoText(info, ezCore.WHITE))
        return 1
    end
    local text, source, last = ns.LastKnownText(convo)
    if not text then return 0 end
    tooltip:AddLine(text)
    local r, g, b = ns.RGB("gray")
    tooltip:AddLine(source, r, g, b)
    if not last then return 2 end
    tooltip:AddLine(last, r, g, b)   -- Gildenmitglied: zuletzt online laut Gildenliste (Welle 23)
    return 3
end

local function SetupRow(row)
    row.ezSetup = true
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    row.background = row:CreateTexture(nil, "BACKGROUND")
    row.background:SetAllPoints()
    MenuTexture(row.background, 0.75195313, 0.83007813)

    row.selection = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.selection:SetAllPoints()
    MenuTexture(row.selection, 0.59179688, 0.66992188)
    row.selection:Hide()

    row:SetHighlightTexture(MENU_TEXTURE, "ADD")
    local highlight = row:GetHighlightTexture()
    if highlight then
        highlight:SetTexCoord(0.00390625, 0.87890625, 0.75195313, 0.83007813)
        highlight:SetAlpha(0.8)
    end

    row.status = row:CreateTexture(nil, "ARTWORK")
    -- Online-Punkt wie Blizzards Freundesliste (FriendsFrame.xml: status 16 × 16 = Core.Style.ICON.line); Mitte wie
    -- vorher (14 px an 6, -5)
    row.status:SetSize(ezCore.Style.ICON.line, ezCore.Style.ICON.line)
    row.status:SetPoint("TOPLEFT", row, "TOPLEFT", 5, -4)

    row.unread = row:CreateTexture(nil, "ARTWORK")
    -- Zeichen „ungelesen“ wie Blizzards Community-Liste (CommunitiesList.xml: UnreadNotificationIcon 17 × 17)
    row.unread:SetSize(17, 17)
    row.unread:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, -3)
    if row.unread.SetAtlas then row.unread:SetAtlas("communities-icon-notification") end
    row.unread:Hide()

    row.when = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    row.when:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -6)

    row.name = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 24, -5)
    row.name:SetPoint("TOPRIGHT", row, "TOPRIGHT", -44, -5)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.preview = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    row.preview:SetPoint("TOPLEFT", row, "TOPLEFT", 24, -22)
    row.preview:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -22)
    row.preview:SetJustifyH("LEFT")
    row.preview:SetWordWrap(false)

    row:SetScript("OnClick", function(self, button)
        if not self.key then return end
        if button == "RightButton" and self.key ~= HISTORY_KEY then
            RowMenu(self)
        else
            Window.Select(self.key)
        end
    end)
    -- Tooltip: was Klick und Rechtsklick tun
    row:SetScript("OnEnter", function(self)
        if not self.key then return end
        if self.key == HISTORY_KEY then return ezCore.ShowTip(self, L.SEARCH_HISTORY, L.ROW_HISTORY_TIP) end
        if self.key == FILTERED_KEY then return ezCore.ShowTip(self, L.SPAM_ROW, L.SPAM_ROW_TIP) end
        local convo = ns.C and ns.C.convos[self.key]
        if not convo then return end
        ezCore.ShowTip(self, Conv.Display(convo), L.ROW_TIP)
        local lines = Window.AddInfoLines(GameTooltip, convo) + Window.AddAltLines(GameTooltip, convo)
        if lines > 0 then GameTooltip:Show() end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function PlainPreview(text)
    return (ns.PlainText(text or ""):gsub("[\r\n]+", " "))
end

-- Eintrag „Kanalverlauf“ in den Suchergebnissen.
local function InitHistoryRow(row, item)
    row.name:SetText(L.SEARCH_HISTORY)
    row.name:SetFontObject(GameFontNormal)
    row.unread:Hide()
    row.status:Hide()
    row.when:SetText(item.hit and ns.DayText(item.hit.t) or "")
    row.preview:SetText(L.SEARCH_HITS:format(item.hits) .. (item.hit and (": " .. PlainPreview(item.hit.plain)) or ""))
end

-- Eintrag „Gefiltert“ unten in der Liste: Zahl der abgelegten Nachrichten, neue seit dem letzten Blick in Gold.
local function InitFilteredRow(row)
    local count, new = ns.Spam.Count(), ns.Spam.NewCount()
    row.name:SetText(L.SPAM_ROW)
    row.name:SetFontObject(GameFontNormal)
    row.unread:Hide()
    row.status:Hide()
    row.when:SetText("")
    row.preview:SetText(L.SPAM_ROW_COUNT:format(count) .. (new > 0 and (" " .. ezCore.Gold(L.SPAM_ROW_NEW:format(new))) or ""))
end

local function InitRow(row, item)
    if not row.ezSetup then SetupRow(row) end
    row.key = item.key
    row.selection:SetShown(item.key == selected)
    if item.history then return InitHistoryRow(row, item) end
    if item.filtered then return InitFilteredRow(row) end
    local convo = item.convo

    local name = Conv.Display(convo)
    if convo.bn then name = ns.ColorText("bnet", name) end
    if convo.muted then name = name .. " " .. ns.ColorText("orange", L.MUTED_MARK) end
    row.name:SetText(name)

    local unread = convo.unread or 0
    local last = convo.msgs[#convo.msgs]
    row.name:SetFontObject(unread > 0 and GameFontHighlight or GameFontNormal)
    row.unread:SetShown(unread > 0)
    row.when:SetText((unread == 0 and last) and ns.DayText(last.t) or "")

    local queued = Conv.CountQueued(convo)
    if item.hits then
        -- Suche: Zahl der Treffer und der neueste passende Text
        local text = item.hit and (": " .. PlainPreview(item.hit.m)) or ""
        row.preview:SetText(L.SEARCH_HITS:format(item.hits) .. text)
    elseif queued > 0 then
        row.preview:SetText(ezCore.Gold(L.ROW_QUEUED:format(queued)))
    elseif last then
        row.preview:SetText((last.o and (L.YOU .. ": ") or "") .. PlainPreview(last.m))
    else
        row.preview:SetText(L.ROW_EMPTY)
    end

    local online = ns.Delivery.IsOnline(convo)
    if online == true then
        row.status:SetTexture(ONLINE_ICON)
        row.status:Show()
    elseif online == false then
        row.status:SetTexture(OFFLINE_ICON)
        row.status:Show()
    else
        row.status:Hide()
    end
end

-- Einträge der Liste: alle Gespräche, bei einer Suche nur die passenden und der Kanalverlauf.
local function ListItems()
    local list = Conv.Sorted()
    if not query then
        if ns.Spam.Count() > 0 then list[#list + 1] = { key = FILTERED_KEY, filtered = true } end
        return list
    end
    local found = {}
    for _, item in ipairs(list) do
        local hits, hit, byName = Conv.Search(item.convo, query)
        if hits > 0 or byName then
            item.hits, item.hit = hits, hit
            found[#found + 1] = item
        end
    end
    local history = ns.History.Search(query)
    if #history > 0 then
        found[#found + 1] = { key = HISTORY_KEY, history = true, hits = #history, hit = history[#history] }
    end
    return found
end

local function Listed(list, key)
    for _, item in ipairs(list) do
        if item.key == key then return true end
    end
    return false
end

function Window.RefreshList()
    dirtyList = false
    if not frame or not scrollBox or not ns.C then return end
    local list = ListItems()
    -- Suche: Auswahl auf einen Treffer setzen, wenn die bisherige nicht mehr passt.
    if query and not Listed(list, selected) then selected = list[1] and list[1].key or nil end
    scrollBox:SetDataProvider(CreateDataProvider(list), true)
    listEmptyText:SetText(query and L.SEARCH_NONE or L.LIST_EMPTY)
    listEmptyText:SetShown(#list == 0)
end

-- Knopf „Andocken“/„Lösen“ in der Kopfzeile: nur, wenn Andocken an ist und Blizzards Freundesliste offen.
function Window.UpdateDockButton()
    local button = Window.dockButton
    if not button then return end
    local possible = ns.FriendsDock ~= nil and ns.FriendsDock.Active()
    button:SetShown(possible and true or false)
    if possible then button:SetText(docked and L.UNDOCK_BUTTON or L.DOCK_BUTTON) end
end

function Window.Refresh()
    Window.UpdateDockButton()
    if not frame or not frame:IsShown() then return end
    Conv.MarkRead(Selected())
    if selected == FILTERED_KEY then ns.Spam.MarkSeen() end
    Window.RefreshList()
    ShowMessages()
    UpdateHeader()
end

function Window.Select(key)
    selected = key
    Conv.MarkRead(Selected())
    Window.Refresh()
    if ns.Typing and Selected() then ns.Typing.AskZone(key) end   -- Ort teilen: nur, wenn beide es eingeschaltet haben
end

-- Bereich „Gefiltert“ zeigen (Knopf auf der Einstellungsseite, /ezchat gefiltert).
function Window.OpenFiltered()
    if query then Window.SetSearch("") end
    Window.Open(FILTERED_KEY)
end

-- Suche in Gesprächen und Kanalverlauf (Suchfeld oben, /ezchat suche).
function Window.SetSearch(text)
    text = ns.Trim(type(text) == "string" and text or "")
    local new = text ~= "" and text:lower() or nil
    if searchBox and searchBox:GetText() ~= text and new ~= query then searchBox:SetText(text) end
    if new == query then return end
    query = new
    if not query and selected == HISTORY_KEY then selected = nil end
    Window.Refresh()
end

function Window.Search() return query end

---------------------------------------------------------------------------
-- Senden
---------------------------------------------------------------------------

local function SendCurrent()
    local text = ns.Trim(editBox:GetText())
    if text == "" then
        editBox:ClearFocus()
        return
    end
    local convo = Selected()
    if not convo then return end
    if ns.Delivery.Send(convo, text) ~= false then
        editBox:AddHistoryLine(text)
        editBox:SetText("")
    end
end

-- Text aus dem Eingabefeld senden (Enter im Feld oder Knopf „Senden“). true, wenn etwas gesendet oder eingereiht wurde.
function Window.Send()
    if not editBox or not Selected() then return false end
    if ns.Trim(editBox:GetText()) == "" then
        editBox:SetFocus()   -- nichts getippt: der Klick führt ins Feld
        return false
    end
    SendCurrent()
    return editBox:GetText() == ""
end

-- Text ins Eingabefeld legen (z. B. eine vorbereitete Antwort aus einem anderen Modul).
function Window.SetDraft(text)
    if editBox and type(text) == "string" then
        editBox:SetText(text)
        editBox:SetFocus()
        UpdatePlaceholder()
    end
end

-- Shift-Klick auf Gegenstände fügt den Link auch ins eigene Eingabefeld ein.
local function OnInsertLink(link)
    if editBox and type(link) == "string" and editBox:IsVisible() and editBox:HasFocus() then
        editBox:Insert(link)
    end
end

---------------------------------------------------------------------------
-- Fenster
---------------------------------------------------------------------------

local function Inset(parent)
    local ok, inset = pcall(CreateFrame, "Frame", nil, parent, "InsetFrameTemplate")
    if ok and inset then return inset end
    return CreateFrame("Frame", nil, parent)
end

local function Report(ok, err)
    if not ok then ns.Error(err) end
    return ok
end

local function CreateList()
    listInset = Inset(frame)
    listInset:SetPoint("TOPLEFT", frame, "TOPLEFT", LAYOUT.EDGE, LAYOUT.CONTENT_TOP)
    listInset:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", LAYOUT.EDGE, LAYOUT.EDGE)
    listInset:SetWidth(LIST_W)

    scrollBox = CreateFrame("Frame", nil, listInset, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", listInset, "TOPLEFT", 4, -4)
    scrollBox:SetPoint("BOTTOMRIGHT", listInset, "BOTTOMRIGHT", -18, 4)

    local bar = CreateFrame("EventFrame", nil, listInset, "MinimalScrollBar")
    bar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, 0)
    bar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 0)

    local view = CreateScrollBoxListLinearView(0, 0, 0, 0)
    view:SetElementExtent(ROW_H)
    view:SetElementInitializer("Button", InitRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, bar, view)

    listEmptyText = listInset:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    listEmptyText:SetPoint("TOPLEFT", listInset, "TOPLEFT", 10, -12)
    listEmptyText:SetPoint("TOPRIGHT", listInset, "TOPRIGHT", -10, -12)
    listEmptyText:SetJustifyH("LEFT")
    listEmptyText:SetText(L.LIST_EMPTY)
end

local function CreateChat()
    chatInset = Inset(frame)
    -- Platz darüber für Name des Partners und die Schalter „Alarm“ und „Stumm“
    chatInset:SetPoint("TOPLEFT", listInset, "TOPRIGHT", 6, -26)
    chatInset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -LAYOUT.EDGE, CHAT_BOTTOM)
    if chatInset.Bg then chatInset.Bg:Hide() end   -- wie im Communities-Chat

    messages = ns.CreateMessageView(chatInset)
    messages:SetPoint("TOPLEFT", chatInset, "TOPLEFT", 8, -6)
    messages:SetPoint("BOTTOMRIGHT", chatInset, "BOTTOMRIGHT", -22, 6)

    emptyText = chatInset:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    emptyText:SetPoint("CENTER", chatInset, "CENTER", 0, 0)
    emptyText:SetWidth(300)
    emptyText:SetText(L.SELECT_CONVERSATION)

    hintText = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hintText:SetPoint("TOPLEFT", chatInset, "BOTTOMLEFT", 4, -5)
    hintText:SetPoint("TOPRIGHT", chatInset, "BOTTOMRIGHT", -4, -5)
    hintText:SetJustifyH("LEFT")
    hintText:SetWordWrap(false)
end

-- Häkchen mit Text im Blizzard-Stil (UICheckButtonTemplate) für das gewählte Gespräch.
local function FlagCheck(label, flag, tip)
    local check = ezCore.CreateCheck(frame, 22)
    local text = check.Text or check.text
    if type(text) ~= "table" then
        text = check:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        text:SetPoint("LEFT", check, "RIGHT", 0, 1)
    end
    text:SetFontObject(GameFontNormalSmall)
    text:SetText(label)
    check.label = text
    check:SetScript("OnClick", function(self)
        if selected and not Special(selected) then Conv.SetFlag(selected, flag, self:GetChecked() and true or false) end
    end)
    check:SetScript("OnEnter", ezCore.TipScript(label, tip))
    check:SetScript("OnLeave", function() GameTooltip:Hide() end)
    check:Hide()
    return check
end

-- Kopf über dem Verlauf, von rechts nach links: Pfeil „Mehr“, „Stumm“, „Alarm“, links davon der Name. Die Beschriftung
-- eines Häkchens steht rechts neben ihm; darum rückt jedes Häkchen um die Breite seines Textes nach links (der deutsche
-- und der englische Text sind verschieden lang) – sonst liegt „Stumm“ unter dem Pfeil.
-- Liefert: x der rechten Kante von „Stumm“ (ab TOPRIGHT des Verlaufs), Abstand „Alarm“ → „Stumm“, x des Namensendes.
local HEAD_CHECK, HEAD_GAP, HEAD_MORE_X = 22, 8, -2
function Window.HeaderLayout(muteW, alarmW)
    local muteX = HEAD_MORE_X - LAYOUT.BUTTON_H - HEAD_GAP - muteW
    local alarmGap = -(HEAD_GAP + alarmW)
    local nameX = muteX - HEAD_CHECK + alarmGap - HEAD_CHECK - HEAD_GAP
    return muteX, alarmGap, nameX
end

-- Breite der Beschriftung eines Häkchens samt Abstand zum Häkchen; ohne Messwert (Text noch nicht gesetzt) geschätzt.
local function LabelWidth(check)
    local label = check and check.label
    local width = label and label.GetStringWidth and label:GetStringWidth()
    if type(width) ~= "number" or width <= 0 then
        local text = label and label.GetText and label:GetText()
        width = 7 * (type(text) == "string" and #text or 6)
    end
    return math.ceil(width) + 4
end
Window.LabelWidth = LabelWidth

local function CreateHeader()
    muteCheck = FlagCheck(L.PARTNER_MUTE, "muted", L.PARTNER_MUTE_TIP)
    alarmCheck = FlagCheck(L.PARTNER_ALARM, "alarm", L.PARTNER_ALARM_TIP)
    local muteX, alarmGap, nameX = Window.HeaderLayout(LabelWidth(muteCheck), LabelWidth(alarmCheck))
    muteCheck:SetPoint("BOTTOMRIGHT", chatInset, "TOPRIGHT", muteX, 1)
    alarmCheck:SetPoint("RIGHT", muteCheck, "LEFT", alarmGap, 0)
    -- Pfeil: dieselben Punkte wie der Rechtsklick auf das Gespräch links (Leitlinie 3)
    moreButton = ezCore.Toolbar.ArrowButton(frame, function(self)
        if selected == FILTERED_KEY then return FilteredMenu(self) end
        if selected and not Special(selected) then ConvoMenu(self, selected) end
    end, L.CONVO_MORE, L.CONVO_MORE_TIP)
    moreButton:SetPoint("BOTTOMRIGHT", chatInset, "TOPRIGHT", HEAD_MORE_X, 0)
    moreButton:Hide()
    Window.moreButton = moreButton

    headerText = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    headerText:SetPoint("BOTTOMLEFT", chatInset, "TOPLEFT", 4, 6)
    headerText:SetPoint("BOTTOMRIGHT", chatInset, "TOPRIGHT", nameX, 6)
    headerText:SetJustifyH("LEFT")
    headerText:SetWordWrap(false)
    -- Klick auf den Namen: Blizzards Spieler-Menü (Window.PlayerMenu); der Knopf liegt über dem Namen und leuchtet beim
    -- Überfahren wie eine Chatzeile. Derselbe Punkt steht im Pfeil-Menü („Spieler-Menü (Blizzard)“).
    nameButton = CreateFrame("Button", nil, frame)
    nameButton:SetPoint("TOPLEFT", headerText, "TOPLEFT", -2, 3)
    nameButton:SetPoint("BOTTOMRIGHT", headerText, "BOTTOMRIGHT", 2, -3)
    nameButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    nameButton:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    nameButton:SetScript("OnClick", function() Window.PlayerMenu(Selected()) end)
    nameButton:SetScript("OnEnter", ezCore.TipScript(L.MENU_PLAYER, L.NAME_BUTTON_TIP))
    nameButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    nameButton:Hide()
    Window.muteCheck, Window.alarmCheck, Window.headerText, Window.nameButton = muteCheck, alarmCheck, headerText, nameButton
end

-- Eingabefeld mit Blizzards Chat-Eingaberahmen (wie CommunitiesChatEditBoxTemplate).
local function CreateEditBox()
    editBox = CreateFrame("EditBox", "ezChatEditBox", frame)
    editBox:SetHeight(32)
    editBox:SetPoint("BOTTOMLEFT", chatInset, "BOTTOMLEFT", 14, -56)
    editBox:SetPoint("BOTTOMRIGHT", chatInset, "BOTTOMRIGHT", -(14 + SEND_W + 14), -56)
    editBox:SetFontObject(ChatFontNormal)   -- wie Blizzards Eingabezeile (ChatFrameEditBox.xml)
    editBox:SetAutoFocus(false)
    editBox:SetMaxLetters(255)
    editBox:SetHistoryLines(20)

    -- Rahmen wie Blizzards Eingabezeile (Blizzard_ChatFrameBase/Mainline/ChatFrameEditBox.xml: Left/Right 32 × 32)
    local left = editBox:CreateTexture(nil, "BACKGROUND")
    left:SetTexture("Interface\\ChatFrame\\UI-ChatInputBorder-Left2")
    left:SetSize(32, 32)
    left:SetPoint("LEFT", editBox, "LEFT", -10, 0)
    local right = editBox:CreateTexture(nil, "BACKGROUND")
    right:SetTexture("Interface\\ChatFrame\\UI-ChatInputBorder-Right2")
    right:SetSize(32, 32)
    right:SetPoint("RIGHT", editBox, "RIGHT", 10, 0)
    local mid = editBox:CreateTexture(nil, "BACKGROUND")
    mid:SetTexture("Interface\\ChatFrame\\UI-ChatInputBorder-Mid2", "REPEAT", "CLAMP")
    if mid.SetHorizTile then mid:SetHorizTile(true) end
    mid:SetHeight(32)
    mid:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, 0)
    mid:SetPoint("TOPRIGHT", right, "TOPLEFT", 0, 0)

    placeholder = editBox:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    placeholder:SetPoint("LEFT", editBox, "LEFT", 2, 0)
    placeholder:SetText(L.EDIT_PLACEHOLDER)

    editBox:SetScript("OnEnterPressed", SendCurrent)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    editBox:SetScript("OnEditFocusGained", UpdatePlaceholder)
    editBox:SetScript("OnEditFocusLost", function(self)
        self:HighlightText(0, 0)
        UpdatePlaceholder()
    end)
    editBox:SetScript("OnTextChanged", function(self, userInput)
        UpdatePlaceholder()
        if userInput and ns.Typing and Selected() then ns.Typing.OnEdit(selected, self:GetText()) end
    end)

    -- Knopf „Senden“ (Leitlinie 3: Enter bleibt, der Knopf macht das Senden sichtbar)
    sendButton = CreateFrame("Button", "ezChatSendButton", frame, "UIPanelButtonTemplate")
    sendButton:SetSize(SEND_W, 22)
    sendButton:SetPoint("RIGHT", chatInset, "BOTTOMRIGHT", -2, -40)
    sendButton:SetText(L.SEND_BUTTON)
    sendButton:SetScript("OnClick", function() Window.Send() end)
    sendButton:SetScript("OnEnter", ezCore.TipScript(L.SEND_BUTTON, L.SEND_BUTTON_TIP))
    sendButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- ohne Gespräch gesperrt; der Tooltip kommt trotzdem (Gesamtreview 18.11.2026, T9-7)
    ezCore.Toolbar.ShowTipWhileDisabled(sendButton)
    Window.sendButton = sendButton
end

-- Suchfeld oben rechts (ezCore: Blizzards SearchBoxTemplate mit Lupe, Hinweistext, Knopf zum Leeren).
local function CreateSearch()
    local box = frame:Search(150, function(text) Window.SetSearch(text) end, L.SEARCH_TITLE, L.SEARCH_TIP)
    searchBox = box
    if type(box.Instructions) == "table" then box.Instructions:SetText(L.SEARCH_PLACEHOLDER) end
end

local function Create()
    if frame then return end

    -- alte Lage aus ezChatDB.window (bis 1.2) einmal nach ezCoreDB.positions übernehmen
    local old = ns.db.window
    frame = ezCore.NewWindow("ezChatFrame", {
        portrait = ICON, title = L.WINDOW_TITLE, width = W, height = H,
        positionKey = POSITION_KEY, import = old and old.point and old or nil,
        default = { "CENTER", "CENTER", 0, 60 }, escape = true,
    })
    -- Angedockt hängt das Fenster an der Freundesliste: Ziehen verschiebt es dann nicht und merkt keine Lage.
    frame:SetScript("OnDragStart", function(self) if not docked then self:StartMoving() end end)
    frame:SetScript("OnDragStop", function(self)
        if docked then return end
        self:StopMovingOrSizing()
        self:SavePosition()
    end)
    -- Angedockt mit dem X geschlossen (Freundesliste bleibt offen): beim nächsten Öffnen der Freundesliste zu
    -- lassen. Esc schließt beides zugleich, dann bleibt es beim gemerkten Stand.
    frame:HookScript("OnHide", function()
        if not docked then return end
        C_Timer.After(0, function()
            local friends = rawget(_G, "FriendsFrame")
            if docked and friends and friends:IsShown() and ns.db then ns.db.friendsDockOpen = false end
        end)
    end)
    frame:HookScript("OnShow", function()
        Window.Refresh()
        -- Erklärblasen beim ersten Öffnen (kurz warten, bis Liste und Kopfzeile stehen; im Kampf erst danach –
        -- tour:StartSoon aus ezCore bündelt und wartet über Core.AfterCombat)
        ns.Tour:StartSoon(frame, 0.2)
    end)
    frame:HookScript("OnHide", function() ns.Tour:Cancel() end)   -- vor dem Start wieder geschlossen: kein Start
    frame:SetScript("OnUpdate", function(self, elapsed)
        if not (dirtyList or dirtyMessages) then return end
        self.elapsed = (self.elapsed or 0) + elapsed
        if self.elapsed < 0.1 then return end
        self.elapsed = 0
        Conv.MarkRead(Selected())
        if dirtyMessages then
            ShowMessages()
            UpdateHeader()
        end
        if dirtyList then Window.RefreshList() end
    end)
    -- Kopfzeile (von links nach rechts) und Suche oben rechts
    Window.newButton = frame:HeaderButton(L.NEW_CONVERSATION, 124, function(self) Window.NewConversation(self) end,
        L.NEW_CONVERSATION, L.NEW_CONVERSATION_TIP .. "\n" .. L.TIP_COMMAND:format(L.CMD_TO))
    Window.alarmButton = frame:HeaderButton(L.ALARM_BUTTON, 90, function(self) ns.Alarms.OpenMenu(self) end,
        L.ALARM_BUTTON, L.ALARM_BUTTON_TIP)
    -- Andocken an die Freundesliste bzw. wieder lösen (nur zu sehen, solange die Freundesliste offen ist)
    Window.dockButton = frame:HeaderButton(L.DOCK_BUTTON, 96, function() Window.ToggleDock() end)
    Window.dockButton:SetScript("OnEnter", function(self)
        ezCore.ShowTip(self, docked and L.UNDOCK_BUTTON or L.DOCK_BUTTON, docked and L.UNDOCK_BUTTON_TIP or L.DOCK_BUTTON_TIP)
    end)
    Window.dockButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Window.dockButton:Hide()
    Report(pcall(CreateSearch))

    -- unten rechts: Einstellungsseite von ezChat
    Window.settingsButton = frame:SettingsButton(function()
        if not ns.OpenSettings() then ns.PrintHelp() end
    end)

    Report(pcall(CreateList))
    CreateChat()
    CreateHeader()
    CreateEditBox()

    if ChatFrameUtil and ChatFrameUtil.InsertLink then
        hooksecurefunc(ChatFrameUtil, "InsertLink", OnInsertLink)
    elseif type(ChatEdit_InsertLink) == "function" then
        hooksecurefunc("ChatEdit_InsertLink", OnInsertLink)
    end

    frame:Hide()
end

function Window.Open(key)
    if not ns.C then return end
    Create()
    -- Angedockt, aber die Freundesliste ist zu (z. B. über den Reiter „Gespräche“ geöffnet): frei zeigen.
    if docked and not (ns.FriendsDock and ns.FriendsDock.Active()) then Window.Undock() end
    if key then selected = key end
    if key and ns.Typing and Selected() then ns.Typing.AskZone(key) end   -- Ort teilen: nur, wenn beide es eingeschaltet haben
    if not Selected() and not Special(selected) then
        local first = Conv.Sorted()[1]
        selected = first and first.key or nil
    end
    if frame:IsShown() then
        Window.Refresh()
    else
        frame:Show()
    end
end

function Window.Toggle()
    if frame and frame:IsShown() then
        frame:Hide()
    else
        Window.Open()
    end
end

-- mode: "docked" (an der Freundesliste, falls sie offen ist), "free" (freies Fenster) oder nil (wie gerade).
function Window.OpenFor(name, bn, mode)
    local _, key = Conv.Get(name, bn, true)
    if not key then return end
    if query then Window.SetSearch("") end   -- ein gezielt geöffnetes Gespräch nie hinter der Suche verstecken
    if mode == "docked" then
        Window.OpenDocked(key)
    else
        if mode == "free" then Window.Undock() end
        Window.Open(key)
    end
    if editBox then editBox:SetFocus() end
end

---------------------------------------------------------------------------
-- An Blizzards Freundesliste angedockt (Entscheidung des Nutzers 13.11.2026; Seitenreiter: FriendsDock.lua)
---------------------------------------------------------------------------

function Window.IsDocked() return docked end
function Window.IsShown() return frame ~= nil and frame:IsShown() end
function Window.Close() if frame then frame:Hide() end end

-- Fenster rechts an der Freundesliste öffnen, so hoch wie sie (ezCore.Dock); key wie bei Window.Open.
-- Ohne Freundesliste öffnet es frei.
function Window.OpenDocked(key)
    local friends = rawget(_G, "FriendsFrame")
    if not (ns.C and friends and friends:IsShown()) then return Window.Open(key) end
    Create()
    docked = true
    ezCore.Dock(frame, friends, { gap = DOCK_GAP })
    Window.Open(key)
end

-- Zurück zum freien Fenster an der gemerkten Stelle und in voller Größe; hide = true schließt es dabei.
function Window.Undock(hide)
    if not docked then return end
    docked = false
    if not frame then return end
    if hide then frame:Hide() end
    frame:ClearAllPoints()
    frame:SetSize(W, H)
    frame:SetClampedToScreen(true)   -- ezCore.Dock hatte das für die Andock-Lage ausgeschaltet
    frame:RestorePosition()
    Window.UpdateDockButton()
end

-- Zwischen angedockt und frei wechseln (Knopf in der Kopfzeile). Das Fenster bleibt offen; ezChat merkt sich
-- die Wahl wie beim Seitenreiter (ezChatDB.friendsDockOpen). Rückgabe: angedockt?
function Window.ToggleDock()
    if not frame then return docked end
    if docked then
        if ns.db then ns.db.friendsDockOpen = false end
        Window.Undock()
    elseif ns.FriendsDock and ns.FriendsDock.Active() then
        if ns.db then ns.db.friendsDockOpen = true end
        Window.OpenDocked(selected)
    end
    Window.UpdateDockButton()
    if ns.FriendsDock then ns.FriendsDock.Refresh() end
    return docked
end

-- Menü „Alarme“ am Knopf im Fenster öffnen (auch von der Einstellungsseite aus).
function Window.OpenAlarms()
    Window.Open()
    if Window.alarmButton then ns.Alarms.OpenMenu(Window.alarmButton) end
end

-- Neues Gespräch: Freunde, Battle.net, Gilde, letzte Gespräche oder Name eingeben.
function Window.NewConversation(owner)
    local function Pick(target, bn) Window.OpenFor(target, bn) end
    if ns.OpenMenu(owner, function(root) ns.PartnerMenu(root, Pick) end) then return end
    ns.AskText(L.POPUP_NEW, "", function(text)
        local full = ns.TypedName(text)
        if full then Pick(full, false) end
    end)
end

-- Ein Gespräch hat einen neuen Schlüssel (voller Name ergänzt): Auswahl mitnehmen.
local incomingKey   -- im Kampf eingegangen: dieses Gespräch geht nach dem Kampf einmal auf (Window.OpenPending)

function Window.Renamed(oldKey, newKey)
    if selected == oldKey then selected = newKey end
    if incomingKey == oldKey then incomingKey = newKey end
end

-- Öffnet ezChat sein Fenster bei neuer Nachricht überhaupt? Nicht, wenn ein anderes Addon die Flüsterfenster
-- übernimmt (WIM; Funktion „openOnWhisper“ in ns.HANDLED_BY). Ob und wann, sagen die Auswahlen je Lage
-- (Situation.PopupMode; seit der Prüfung der Einstellungen vom 19.11.2026 ohne eigenen Hauptschalter).
function Window.PopupAllowed()
    return ns.Other("openOnWhisper") == nil
end

-- Nach dem Kampf: das zuletzt im Kampf eingegangene Gespräch einmal öffnen. Nichts passiert, wenn die Lage jetzt eine
-- eigene Lage mit „nicht öffnen“ ist (z. B. Dungeon), „Kampf: Fenster“ inzwischen nicht mehr öffnet, ein anderes Addon
-- die Flüsterfenster übernimmt (WIM), das Fenster schon offen ist oder das Gespräch inzwischen gelesen bzw. gelöscht
-- wurde. Ohne Lage (offene Welt) gilt die Wahl „nach dem Kampf“ selbst, nicht „Sonst“ (Gegenprüfung der Einstellungen
-- vom 19.11.2026: sonst ginge das Fenster mit „Sonst“ ab Werk nie auf). → true, wenn es aufging.
function Window.OpenPending()
    local key = incomingKey
    incomingKey = nil
    if not key or not Window.PopupAllowed() then return false end
    if frame and frame:IsShown() then return false end
    if ns.Situation then
        local combat = ns.Situation.Setting("combat", "sitPopup")
        if combat ~= "after" and combat ~= "yes" then return false end   -- „Kampf: Fenster“ inzwischen „nicht öffnen“
        local mode, sit = ns.Situation.PopupMode()
        if mode == "no" and sit then return false end   -- eigene Lage mit „nicht öffnen“, z. B. nach dem Kampf im Dungeon
    end
    local convo = ns.C and ns.C.convos[key]
    if not convo or (convo.unread or 0) == 0 then return false end
    Window.Open(key)
    return true
end

-- Neue eingehende Nachricht: Fenster auf Wunsch öffnen. Was je Lage gilt, sagt Situation.PopupMode (ab Werk überall
-- „nicht öffnen“): „nie“ lässt es zu, „nach dem Kampf“ holt es danach einmal nach (ns.AfterCombat mit einem
-- Schlüssel: nur ein Eintrag, das zuletzt eingegangene Gespräch gewinnt).
function Window.OnIncoming(key)
    if not Window.PopupAllowed() then return end
    if frame and frame:IsShown() then return end
    local mode = ns.Situation and ns.Situation.PopupMode() or "no"
    if mode == "no" then return end
    if mode == "after" then
        incomingKey = key
        ns.AfterCombat(Window.OpenPending, "openOnWhisper")
        return
    end
    Window.Open(key)
end

Conv.OnChange(function(key)
    if not frame or not frame:IsShown() then return end
    if key == nil or key == selected or query then dirtyMessages = true end
    dirtyList = true
end)

local function MarkStatus()
    if frame and frame:IsShown() then
        dirtyList = true
        dirtyMessages = true
    end
end
-- Online-Stand aus ezCore.Contact: erst nach dem gesammelten Neulesen (CONTACTS_CHANGED) auffrischen;
-- WoW-Freunde fragt ezChat direkt bei Blizzard, dort sofort.
ns.On("FRIENDLIST_UPDATE", MarkStatus)
ezCore.Listen("CONTACTS_CHANGED", MarkStatus, "ezChat")
ns.OnSettingChanged(function(key)
    if key == "links" then MarkStatus() end
end)

---------------------------------------------------------------------------
-- Erklärblasen (ezCore.NewTour): die wichtigsten Funktionen beim ersten Öffnen des Fensters; Reiter und
-- Symbole im Chat auch schon nach dem Einloggen. Was gerade nicht zu sehen ist, kommt später dran.
-- Gesehen: ezChatDB.hints; „Erneut zeigen“ unter Einstellungen → Erweitert (page:TourButton).
---------------------------------------------------------------------------

ns.Tour = ezCore.NewTour({
    owner = ns, field = "hints",   -- Speicher ezChatDB.hints über das Gerüst (ns.db)
    steps = {
        { key = "list", target = function() return listInset end, text = L.TOUR_STEP_LIST, side = "right" },
        { key = "offline", target = function() return editBox end, text = L.TOUR_STEP_OFFLINE, side = "above" },
        { key = "search", target = function() return searchBox end, text = L.TOUR_STEP_SEARCH, side = "below" },
        { key = "alarms", target = function() return Window.alarmButton end, text = L.TOUR_STEP_ALARMS, side = "below" },
        { key = "chatTab", target = function() return rawget(_G, "ezChatViewTab") end, text = L.TOUR_STEP_TAB, side = "above" },
        { key = "chatBar", target = function() return ezCore.ChatBar.Button("ezChat.new") end, text = L.TOUR_STEP_BAR, side = "right" },
    },
})

-- Nach dem Einloggen: Blasen an Reiter und Symbolen im Chat, solange das Fenster zu ist.
ns.OnReady(function()
    C_Timer.After(8, function()
        if not (frame and frame:IsShown()) then ns.Tour:StartSoon(nil, 0) end   -- im Kampf erst danach
    end)
end)
