local _, ns = ...
local L = ns.L
local Conv = ns.Conv

-- Gesprächsauswahl in der Reiterleiste des Chatfensters und Gesprächsansicht.
-- Rechtsbündig in der Reiterleiste sitzt ein Reiter im Stil der Chat-Reiter
-- (Texturen aus ChatTabArtTemplate, im gewählten Zustand in der Flüsterfarbe wie
-- Blizzards private Chats). Er listet die offenen Gespräche; die Liste bleibt über
-- Neustarts erhalten, anders als Blizzards „Zu privatem Chat umwandeln“.
-- Wer eines wählt, sieht im Chatfenster nur noch dieses Gespräch samt Verlauf, und
-- Blizzards Eingabezeile flüstert dem Partner (Flüstern „klebt“ dort, Chat.SetTellTarget). Ein Klick
-- auf einen Chat-Reiter führt zurück zum normalen Chat, die Eingabezeile zurück auf den Chattyp davor.
-- Eigene Frames: die Ansicht liegt über dem Chatfenster, der Reiter hängt an Blizzards
-- Reiterleiste. An Blizzards Chatfenster ändert ezChat nur die Durchsichtigkeit von Chattext
-- (FontStringContainer) und den Teilen der Bildlaufleiste, solange ein Gespräch gezeigt wird
-- (SetAlpha(0), der vorherige Wert wird gemerkt), und stellt sie beim Zurückschalten wieder her
-- (FadeChat/RestoreChat). Kein Schreiben in Blizzards Tabellen, sonst nur hooksecurefunc.

local View = {}
ns.ChatView = View

local TAB_MIN, TAB_MAX, TAB_PAD = 64, 170, 30
local HEADER_H = 16
local MENU_MAX = 30

local tab, overlay, messages, header
local active          -- Schlüssel des gezeigten Gesprächs
local dirty = false

local function Dock()
    return GENERAL_CHAT_DOCK or GeneralDockManager
end

function View.Enabled()
    return ns.S and ns.S.chatView and ChatFrame1 ~= nil and Dock() ~= nil
end

function View.Active()
    return active
end

local function WhisperColor(bn) return ns.WhisperColor(bn and true or false) end

---------------------------------------------------------------------------
-- Reiter
---------------------------------------------------------------------------

local function UpdateTab()
    if not tab then return end
    local enabled = View.Enabled()
    tab:SetShown(enabled and true or false)
    if not enabled then return end

    local convo = active and ns.C and ns.C.convos[active]
    local text, r, g, b
    if convo then
        text = Conv.Display(convo)
        r, g, b = WhisperColor(convo.bn)
    else
        text = L.VIEW_TAB
        r, g, b = ns.RGB("normal")   -- Rolle „normal“ (Blizzards NORMAL_FONT_COLOR) statt eigener Farbzahlen (A5)
    end
    local unread = 0
    for _, item in ipairs(Conv.Open()) do
        if item.key ~= active then unread = unread + (item.convo.unread or 0) end
    end
    if unread > 0 then text = text .. " (" .. unread .. ")" end

    tab.text:SetText(text)
    tab.text:SetTextColor(r, g, b)
    for _, texture in ipairs(tab.activeTextures) do
        texture:SetShown(convo ~= nil)
        texture:SetVertexColor(r, g, b)
    end
    for _, texture in ipairs(tab.highlightTextures) do texture:SetVertexColor(r, g, b) end
    tab.glow:SetShown(unread > 0)
    tab:SetWidth(math.max(TAB_MIN, math.min(TAB_MAX, (tab.text:GetStringWidth() or 0) + TAB_PAD)))
end

-- Rechtsbündig in der Reiterleiste, während Blizzards Reiter links beginnen
-- (bei zu vielen Reitern vor Blizzards Überlauf-Knopf).
local function Position()
    local dock = Dock()
    if not tab or not dock then return end
    tab:ClearAllPoints()
    local overflow = dock.overflowButton
    if overflow and overflow:IsShown() then
        tab:SetPoint("BOTTOMRIGHT", overflow, "BOTTOMLEFT", -2, 0)
    else
        tab:SetPoint("BOTTOMRIGHT", dock, "BOTTOMRIGHT", 0, 0)
    end
end

-- Gleiche Durchsichtigkeit wie Blizzards Reiter (die blenden mit dem Chat aus).
local function SelectedChatTab()
    local dock = Dock()
    local frame = dock and dock.selected
    local name = frame and frame.GetName and frame:GetName()
    return name and _G[name .. "Tab"]
end

-- Sichtbarkeit wie Blizzards Reiter (die blenden sich ein und aus); fünfmal je Sekunde reicht, gesetzt wird
-- nur, wenn sich etwas ändert.
local ALPHA_INTERVAL = 0.2
local function UpdateAlpha(self, elapsed)
    self.elapsed = (self.elapsed or 0) + elapsed
    if self.elapsed < ALPHA_INTERVAL then return end
    self.elapsed = 0
    local ref = SelectedChatTab()
    local alpha = ref and ref:GetAlpha() or 1
    if not active then alpha = alpha * 0.6 end   -- wie ein nicht gewählter Reiter
    if self.glow:IsShown() then alpha = math.max(alpha, 0.8) end
    if self:IsMouseOver() then alpha = 1 end
    if math.abs((self:GetAlpha() or 0) - alpha) > 0.01 then self:SetAlpha(alpha) end
end

local function FillMenu(root)
    root:CreateTitle(L.VIEW_TITLE)
    local open = Conv.Open()
    if #open == 0 then root:CreateTitle(ezCore.Grey(L.VIEW_NONE)) end
    for i = 1, math.min(#open, MENU_MAX) do
        local item = open[i]
        local label = Conv.MenuLabel(item.convo)
        local function Pick() View.Select(item.key, true) end
        ezCore.Menu.Radio(root, label, function() return active end, Pick, item.key)
    end
    root:CreateDivider()
    ns.PartnerMenu(root:CreateButton(L.NEW_CONVERSATION), ns.Chat.Start)
    if active then
        local key = active
        root:CreateButton(L.VIEW_BACK, View.Close)
        root:CreateButton(L.CHAT_DETACH, function()
            View.Close()
            ns.Window.Open(key)
        end)
        root:CreateButton(L.VIEW_REMOVE, function() View.Remove(key) end)
        ns.FlagEntries(root, key)   -- Alarm und Stumm für das gezeigte Gespräch
    else
        root:CreateButton(L.CHAT_OPEN_WINDOW, function() ns.Window.Open() end)
    end
end

local function ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local r, g, b = ns.RGB("highlight")   -- Farben aus ezCores Rollen (Welle 23, A5)
    GameTooltip:SetText(L.VIEW_TITLE, r, g, b)
    GameTooltip:AddLine(active and L.VIEW_TIP_ACTIVE or L.VIEW_TIP, nil, nil, nil, true)
    r, g, b = ns.RGB("grey")
    GameTooltip:AddLine(L.VIEW_TIP_CLICK, r, g, b, true)
    GameTooltip:Show()
end

local function CreateTab()
    local dock = Dock()
    if tab or not dock then return end
    tab = CreateFrame("Button", "ezChatViewTab", dock)
    tab:SetFrameStrata("MEDIUM")
    tab:SetSize(TAB_MIN, 32)
    tab:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local function Piece(layer, file, blend)
        local texture = tab:CreateTexture(nil, layer)
        texture:SetTexture(file)
        if blend then texture:SetBlendMode(blend) end
        return texture
    end
    local function Row(layer, prefix, blend)
        local left = Piece(layer, prefix .. "Left", blend)
        left:SetSize(16, 32)
        left:SetPoint("BOTTOMLEFT", -2, 0)
        local right = Piece(layer, prefix .. "Right", blend)
        right:SetSize(16, 32)
        right:SetPoint("BOTTOMRIGHT", 2, 0)
        local mid = Piece(layer, prefix .. "Mid", blend)
        mid:SetHeight(32)
        mid:SetPoint("LEFT", left, "RIGHT")
        mid:SetPoint("RIGHT", right, "LEFT")
        if mid.SetHorizTile then mid:SetHorizTile(true) end
        return { left, mid, right }
    end
    Row("BACKGROUND", "Interface\\ChatFrame\\ChatFrameTab-BG")
    tab.activeTextures = Row("BORDER", "Interface\\ChatFrame\\ChatFrameTab-Selected", "ADD")
    tab.highlightTextures = Row("HIGHLIGHT", "Interface\\ChatFrame\\ChatFrameTab-Highlight", "ADD")

    tab.glow = Piece("BORDER", "Interface\\ChatFrame\\ChatFrameTab-NewMessage", "ADD")
    tab.glow:SetHeight(32)
    tab.glow:SetPoint("BOTTOMLEFT", 8, 0)
    tab.glow:SetPoint("BOTTOMRIGHT", -8, 0)
    tab.glow:Hide()

    tab.text = tab:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    tab.text:SetPoint("LEFT", 12, -5)
    tab.text:SetPoint("RIGHT", -12, -5)
    tab.text:SetWordWrap(false)

    tab:SetScript("OnClick", function(self)
        GameTooltip:Hide()
        ezCore.PlaySound("U_CHAT_SCROLL_BUTTON")
        ns.OpenMenu(self, FillMenu)
    end)
    tab:SetScript("OnEnter", ShowTooltip)
    tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
    tab:SetScript("OnUpdate", UpdateAlpha)
end

---------------------------------------------------------------------------
-- Gesprächsansicht über dem Chatfenster
---------------------------------------------------------------------------

-- Das gerade sichtbare Chatfenster der Reiterleiste (alle angedockten liegen übereinander).
local function ShownChatFrame()
    local dock = Dock()
    return (dock and dock.selected) or ChatFrame1
end

local function Fill()
    dirty = false
    local convo = active and ns.C and ns.C.convos[active]
    if not convo then return View.Close() end
    Conv.MarkRead(convo)   -- Chat-Knopfleiste, Freundesliste und Schnittstelle erfahren es (Conv.OnRead)
    messages:Fill(convo)
    local status, hint = ns.ConvoStatus(convo, true)   -- kurz: eine Zeile über dem Chat, ohne die Angaben eines Offline-Partners
    if ns.MissingSurname(convo.name) then hint = L.NEED_SURNAME:format(convo.name) end
    ns.Chat.KeepTell(convo, ShownChatFrame())   -- neuer Name (Nachname ergänzt, zusammengelegt): Flüsterziel nachführen
    local tellTarget = hint == "" and ns.Chat.TellTarget()   -- die Zeile öffnet Enter, nicht ezChat (Chat.lua)
    if tellTarget then hint = L.VIEW_ENTER:format(tellTarget) end
    if hint ~= "" then status = status .. "  " .. ezCore.Grey(hint) end
    header:SetText(status)
    UpdateTab()
end

-- Blizzards Chattext und Bildlaufleiste des Fensters ausblenden, solange ein Gespräch
-- gezeigt wird – das Gespräch steht dann auf dem originalen Chat-Hintergrund. Nur die
-- Durchsichtigkeit ändert sich; beim Zurückschalten kommt alles wieder.
-- Die Bildlaufleiste selbst blendet Blizzard mit dem Chat ein und aus (UIFrameFadeIn/
-- -Out); darum werden nur ihre Teile ausgeblendet, und ezChats eigene Leiste liegt an
-- genau ihrer Stelle und übernimmt ihre Durchsichtigkeit.
local faded = {}   -- [Region] = vorherige Durchsichtigkeit
local fadedChat     -- das Chatfenster, dessen Text gerade ausgeblendet ist

local function RestoreChat()
    for region, alpha in pairs(faded) do region:SetAlpha(alpha) end
    wipe(faded)
    fadedChat = nil
end

local function Fade(region)
    if region and region.SetAlpha and faded[region] == nil then
        faded[region] = region:GetAlpha() or 1
        region:SetAlpha(0)
    end
end

-- Hat Blizzard einen ausgeblendeten Teil wieder sichtbar gemacht (Einblenden beim Überfahren, neues Layout)?
-- Dann erneut ausblenden; der gemerkte Ausgangswert bleibt. Rückgabe: Anzahl nachgezogener Teile (V-073).
local function KeepFaded()
    local again = 0
    for region in pairs(faded) do
        local alpha = region:GetAlpha()
        if not ns.IsSecret(alpha) and (alpha or 0) > 0 then
            region:SetAlpha(0)
            again = again + 1
        end
    end
    return again
end
View.KeepFaded = KeepFaded

local function FadeChat(chat)
    if fadedChat ~= chat then RestoreChat() end
    fadedChat = chat
    Fade(chat.FontStringContainer)
    local bar = chat.ScrollBar
    if bar then
        for _, child in ipairs({ bar:GetChildren() }) do Fade(child) end
        for _, region in ipairs({ bar:GetRegions() }) do Fade(region) end
    end
    return chat.FontStringContainer ~= nil
end

-- ezChats Bildlaufleiste an die Stelle von Blizzards Leiste (rechts außen am
-- Chatfenster) und so sichtbar wie diese.
local function FollowScrollBar(chat)
    local own, blizzard = messages.ScrollBarFrame, chat.ScrollBar
    if not own or not blizzard then return end
    if own.ezFollows ~= blizzard then
        own:ClearAllPoints()
        own:SetPoint("TOPLEFT", blizzard, "TOPLEFT")
        own:SetPoint("BOTTOMRIGHT", blizzard, "BOTTOMRIGHT")
        own.ezFollows = blizzard
    end
    own:SetShown(blizzard:IsShown())
    own:SetAlpha(blizzard:GetAlpha() or 1)
end

-- Über dem Chatfenster und allen seinen Teilen bleiben (Blizzard hebt Fenster beim
-- Anklicken an). Die Ebenen können wie die Schicht gesperrt sein (V-186): nur lesbare zählen (ezCore.Num); ist keine
-- lesbar, bleibt das Overlay, wo es ist.
local function KeepOnTop(chat)
    local level = ezCore.Num(chat:GetFrameLevel())
    for _, child in ipairs({ chat:GetChildren() }) do
        local childLevel = child.GetFrameLevel and ezCore.Num(child:GetFrameLevel()) or nil
        if childLevel ~= nil and (level == nil or childLevel > level) then level = childLevel end
    end
    if level == nil then return end
    local own = ezCore.Num(overlay:GetFrameLevel())
    if own == nil or own <= level then overlay:SetFrameLevel(level + 5) end
end

-- Schrift wie im Chatfenster. Nur wenn sich Blizzards Chattext nicht ausblenden lässt
-- (anderer Aufbau des Chatfensters), deckt ein Hintergrund in der Chatfarbe ihn ab.
local function ApplyLook(chat)
    local ok, font, size, flags = pcall(chat.GetFont, chat)
    if ok and font then messages:SetFont(font, size, flags) end
    -- Die Schicht kann seit Forever 1.60.1 gesperrt sein (V-186): nur ein lesbarer Wert, sonst „LOW“.
    overlay:SetFrameStrata(ezCore.Plain(chat:GetFrameStrata()) or "LOW")
    KeepOnTop(chat)
    local covered = FadeChat(chat)
    FollowScrollBar(chat)
    overlay.bg:SetShown(not covered)
    if not covered then
        local r, g, b = 0, 0, 0
        if GetChatWindowInfo then
            local okInfo, _, _, cr, cg, cb = pcall(GetChatWindowInfo, 1)
            if okInfo and cr then r, g, b = cr, cg, cb end
        end
        overlay.bg:SetVertexColor(r, g, b, 0.92)
    end
end

local function CreateOverlay()
    local chat = ChatFrame1
    if overlay or not chat then return end
    overlay = CreateFrame("Frame", "ezChatView", UIParent)
    overlay:SetPoint("TOPLEFT", chat, "TOPLEFT")
    overlay:SetPoint("BOTTOMRIGHT", chat, "BOTTOMRIGHT")

    overlay.bg = overlay:CreateTexture(nil, "BACKGROUND")
    overlay.bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    overlay.bg:SetAllPoints(chat.Background or chat)
    overlay.bg:Hide()

    header = overlay:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    header:SetPoint("TOPLEFT", chat, "TOPLEFT", 2, 0)
    header:SetPoint("TOPRIGHT", chat, "TOPRIGHT", -2, 0)
    header:SetHeight(HEADER_H)
    header:SetJustifyH("LEFT")
    header:SetWordWrap(false)

    -- Text über die volle Breite wie Blizzards Chattext; die Leiste sitzt rechts außen.
    messages = ns.CreateMessageView(overlay)
    messages:SetPoint("TOPLEFT", chat, "TOPLEFT", 0, -HEADER_H)
    messages:SetPoint("BOTTOMRIGHT", chat, "BOTTOMRIGHT", 0, 0)

    overlay:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = (self.elapsed or 0) + elapsed
        if self.elapsed < 0.1 then return end
        self.elapsed = 0
        local chat = ShownChatFrame()
        local ok, err
        if chat ~= fadedChat then
            ok, err = pcall(ApplyLook, chat)   -- Blizzard hat ein anderes Fenster gewählt
            local convo = ok and active and ns.C and ns.C.convos[active]
            if convo then ok, err = pcall(ns.Chat.KeepTell, convo, chat) end   -- Stil „IM“: dessen Eingabezeile
        else
            ok, err = pcall(KeepOnTop, chat)
            if ok then ok, err = pcall(KeepFaded) end
            if ok then ok, err = pcall(FollowScrollBar, chat) end
        end
        if ok and dirty then ok, err = pcall(Fill) end
        if not ok then ns.Error(err) end
    end)
    overlay:Hide()
end

-- Gespräch im Chatfenster zeigen und Blizzards Eingabezeile auf Flüstern an den Partner stellen. fromUser: aus
-- einem Klick heraus (dann ein Hinweis, wenn ein Battle.net-Partner kein Freund mehr ist).
function View.Select(key, fromUser)
    local convo = key and ns.C and ns.C.convos[key]
    if not convo or not View.Enabled() then return end
    CreateOverlay()
    convo.closed = nil
    if active and active ~= key then ns.Delivery.Expect(active) end
    active = key
    ApplyLook(ShownChatFrame())
    overlay:Show()
    -- Blizzards Eingabezeile flüstert dem Partner, solange die Ansicht das Gespräch zeigt – auch nach Esc und beim
    -- Wechsel zu einem anderen Gespräch; View.Close stellt den Stand davor wieder her (Chat.SetTellTarget). Die Zeile
    -- öffnet der Spieler mit Enter; aus Addon-Code geöffnet blieben Blizzards Chat-Merker befleckt (Chat.lua).
    -- Ist ein Battle.net-Partner kein Freund mehr, sagt das ein Hinweis (wie Chat.Tell, ohne Blizzards Eingabe).
    -- Vor Fill, damit dessen Nachführen (Chat.KeepTell) schon das neue Gespräch vorfindet.
    local set = ns.Chat.SetTellTarget(convo, ShownChatFrame())
    if not set and fromUser and convo.bn and not select(3, ns.BNFind(convo.name)) then ns.Print(L.BN_NOT_FRIEND) end
    Fill()
    -- Solange die Ansicht das Gespräch zeigt: Flüstern an Offline-Partner in die Warteschlange.
    ns.Delivery.Expect(key, 86400)
end

-- Zurück zum normalen Chat.
function View.Close()
    if active then ns.Delivery.Expect(active) end   -- noch zehn Minuten wie nach Gesprächsbeginn
    ns.Chat.RestoreTell()   -- Eingabezeile zurück auf den Chattyp vor dem Gespräch
    active = nil
    dirty = false
    RestoreChat()
    if overlay then overlay:Hide() end
    UpdateTab()
end

-- Gespräch aus der Auswahl nehmen (Verlauf bleibt; die nächste Nachricht holt es zurück).
function View.Remove(key)
    local convo = key and ns.C and ns.C.convos[key]
    if convo then convo.closed = true end
    if active == key then View.Close() else UpdateTab() end
end

function View.Renamed(oldKey, newKey)
    if active == oldKey then active = newKey end
end

---------------------------------------------------------------------------
-- Einhängen
---------------------------------------------------------------------------

local function Init()
    if not Dock() or not ChatFrame1 then return end
    CreateTab()
    Position()
    UpdateTab()
    if type(FCFDock_UpdateTabs) == "function" then
        hooksecurefunc("FCFDock_UpdateTabs", function(dock)
            if dock ~= Dock() then return end
            ns.Seen("FCFDock_UpdateTabs")
            local ok, err = pcall(Position)
            if not ok then ns.Error(err) end
        end)
    end
    -- Klick auf einen Chat-Reiter (auch den schon gewählten): zurück zum normalen Chat.
    if type(FCF_Tab_OnClick) == "function" then
        hooksecurefunc("FCF_Tab_OnClick", function(_, button)
            ns.Seen("FCF_Tab_OnClick")
            if button == "LeftButton" and active then View.Close() end
        end)
    end
end

View.Init = Init

ns.OnReady(function()
    local ok, err = pcall(Init)
    if not ok then ns.Error(err) end
end)

ns.On("PLAYER_ENTERING_WORLD", function()
    C_Timer.After(0, function()
        local ok, err = pcall(Position)
        if not ok then ns.Error(err) end
    end)
end)

-- Reiter gesammelt neu beschriften: viele Nachrichten hintereinander lösen das nur einmal aus.
local UpdateTabSoon = ns.Throttle(function() UpdateTab() end, 0.2)
Conv.OnChange(function(key)
    if active and (key == nil or key == active) then dirty = true end
    UpdateTabSoon()
end)
Conv.OnRead(function() UpdateTabSoon() end)

ns.OnSettingChanged(function(key)
    if key ~= "chatView" then return end
    if not ns.S.chatView then View.Close() end
    UpdateTab()
end)
