local _, ns = ...
local L = ns.L
local Conv = ns.Conv

-- ezChat-Symbole in Blizzards Knopfleiste des Chatfensters, zwischen dem Sprachchat-
-- Knopf oben und dem Chat-Menü (Sprechblase) unten. Aussehen wie die Sprachchat-Knöpfe
-- (VoiceToggleButtonTemplate: 27×26, chatframe-button-*, Symbol 15×15).
-- Die Knöpfe, ihr Platz und das Mitwandern beim Reiterwechsel kommen aus ezCores gemeinsamer
-- Chat-Knopfleiste (ezCore/ChatBar.lua), in die sich auch ezMacro einträgt. ezChat stapelt
-- von unten nach oben und hat Vorrang.

local Bar = {}
ns.ChatBar = Bar
local CoreBar = ezCore.ChatBar

---------------------------------------------------------------------------
-- Inhalte der Knöpfe
---------------------------------------------------------------------------

local UnreadTotal = Conv.UnreadTotal   -- Conversations.lua (auch für Freundesliste und Schnittstelle)
local QueuedTotal = Conv.QueuedTotal

local OpenMenu = ns.OpenMenu   -- ezCore.Menu

local DEFS = {
    {
        key = "new",
        file = "Interface\\Icons\\UI_Chat",
        title = function() return L.NEW_CONVERSATION end,
        lines = function() return { L.BAR_NEW_TIP } end,
        command = function() return L.CMD_TO end,
        onClick = function(self)
            OpenMenu(self, function(root) ns.PartnerMenu(root, ns.Chat.Start) end)
        end,
    },
    {
        key = "window",
        file = "Interface\\Icons\\INV_Letter_15",
        title = function() return L.CHAT_OPEN_WINDOW end,
        lines = function()
            local unread = UnreadTotal()
            local lines = { L.BAR_WINDOW_TIP }
            if unread > 0 then lines[#lines + 1] = ezCore.Gold(L.BAR_UNREAD:format(unread)) end
            return lines
        end,
        onClick = function() ns.Window.Toggle() end,
        command = function() return L.CMD_WINDOW end,
    },
    {
        key = "queue",
        atlas = "communities-icon-invitemail",
        file = "Interface\\Icons\\INV_Letter_03",
        title = function() return L.BAR_QUEUE end,
        lines = function()
            local queued = QueuedTotal()
            return { L.BAR_QUEUE_TIP, queued > 0 and ezCore.Gold(L.BAR_QUEUED:format(queued)) or L.CMD_QUEUE_EMPTY }
        end,
        onClick = function() ns.ListQueue() end,
        command = function() return L.CMD_QUEUE end,
    },
    {
        -- /ezchat post als Knopf (Leitlinie 3): nur am offenen Briefkasten, Zahl = wartende Briefe
        key = "post",
        file = "Interface\\Icons\\INV_Letter_17",
        title = function() return L.BAR_POST end,
        lines = function()
            local letters = ns.Mail.CountLetters()
            return { L.BAR_POST_TIP, letters > 0 and ezCore.Gold(L.BAR_POST_COUNT:format(letters)) or L.MAIL_NOTHING }
        end,
        onClick = function() ns.Mail.SendNow() end,
        command = function() return L.CMD_POST end,
        shown = function() return ezCore.Mail.IsOpen() end,
    },
}

---------------------------------------------------------------------------
-- Knöpfe in ezCores Chat-Knopfleiste
---------------------------------------------------------------------------

local function Shown() return ns.S and ns.S.chatButtons end

local function Tooltip(button)
    local def = button.def.ezChat
    local r, g, b = ns.RGB("highlight")   -- Farben aus ezCores Rollen (Welle 23, A5)
    GameTooltip:SetText(def.title(), r, g, b)
    for _, line in ipairs(def.lines()) do GameTooltip:AddLine(line, nil, nil, nil, true) end
    r, g, b = ns.RGB("grey")
    if def.command then GameTooltip:AddLine(L.TIP_COMMAND:format(def.command()), r, g, b, true) end
    GameTooltip:AddLine(L.BAR_RIGHT_CLICK, r, g, b, true)
end

local function Click(button, mouse)
    if mouse == "RightButton" then
        OpenMenu(button, function(root) ns.Chat.FillMenu(root, nil) end)
    else
        button.def.ezChat.onClick(button)
    end
end

-- Zähler und Punkte: ungelesene Gespräche, wartende Nachrichten.
local function RefreshButton(button)
    local key = button.def.ezChat.key
    if key == "window" then
        button.Dot:SetShown(UnreadTotal() > 0)
    elseif key == "queue" then
        local queued = QueuedTotal()
        button.Count:SetText(queued > 0 and queued or "")
        button.dim = queued == 0
        button.Icon:SetDesaturated(queued == 0)
    elseif key == "post" then
        local letters = ezCore.Mail.IsOpen() and ns.Mail.CountLetters() or 0
        button.Count:SetText(letters > 0 and letters or "")
        button.dim = letters == 0
        button.Icon:SetDesaturated(letters == 0)
    end
end

-- Zähler und Punkte auf den neuesten Stand bringen.
function Bar.Refresh()
    CoreBar.Refresh()
end

-- So viele Symbole zeigen, wie zwischen Sprachchat oben und Chat-Menü unten Platz haben.
function Bar.Layout()
    CoreBar.Layout()
end

ns.OnReady(function()
    for index, def in ipairs(DEFS) do
        local shown = Shown
        if def.shown then shown = function() return Shown() and def.shown() end end
        CoreBar.Add({
            key = "ezChat." .. def.key, owner = "ezChat", side = "bottom", order = index,
            atlas = def.atlas, file = def.file, sound = "IG_CHAT_EMOTE_BUTTON",
            shown = shown, tooltip = Tooltip, onClick = Click, refresh = RefreshButton,
            ezChat = def,
        })
    end
end)

ns.OnSettingChanged(function(key)
    if key == "chatButtons" then CoreBar.Layout() end
end)

-- Knopf „Als Brief senden“ erscheint am Briefkasten und verschwindet danach.
local function MailboxChanged()
    CoreBar.LayoutSoon()
    Bar.Refresh()   -- Zahl der Briefe; danach hält Conv.OnChange sie aktuell
end
ns.On("MAIL_SHOW", MailboxChanged)
ns.On("MAIL_CLOSED", MailboxChanged)

Conv.OnChange(function()
    local ok, err = pcall(Bar.Refresh)
    if not ok then ns.Error(err) end
end)
Conv.OnRead(function() Bar.Refresh() end)   -- Gespräch gelesen: Punkt am Gesprächsfenster-Symbol aktualisieren
