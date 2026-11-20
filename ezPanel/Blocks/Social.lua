local _, ns = ...
local L = ns.L

--[[
    Freunde und Gilde online (Titan: „Friends“/„Guild“): Anzahl der Freunde (WoW und
    Battle.net in diesem Spiel) und der Gildenmitglieder online, im Tooltip die Namen.
    Die Liste kommt aus ezCore.ForEachContact (eine Quelle für alle Module), Namen in Klassenfarbe.
    Zwei Klickzonen auf der Leiste: Linksklick auf „Freunde n“ öffnet Blizzards Freundesliste, auf „Gilde n“
    das Gildenfenster; Shift+Linksklick öffnet das jeweils andere. Steht nur ein Teil auf der Leiste, öffnet
    der Linksklick dessen Fenster.
    Ungelesene Nachrichten (PANEL-13): Läuft ezChat, nennt der Tooltip die Zahl aus ezCore.API("ezChat").Totals()
    (ungelesene und wartende Nachrichten über alle Gespräche, nicht die Zahl der Gespräche) mit Quelle; auf Wunsch
    steht „Nachrichten n“ als dritter Teil auf der Leiste (nur, solange
    etwas ungelesen ist) – ein Linksklick darauf öffnet ezChats Gesprächsfenster, ebenso der Menüeintrag
    „Gesprächsfenster öffnen“. Neu gezeichnet wird bei ezChats Nachricht EZCHAT_CONVERSATIONS_CHANGED.
]]

local MAX_LINES = 25

local block = ns.RegisterBlock({
    id = "social",
    command = "freunde",
    name = L.SOCIAL_NAME,
    icon = "Interface\\Icons\\INV_Misc_GroupNeedMore",
    fallbackIcon = ezCore.ICON_FALLBACK,   -- ezCores Ersatzsymbol (Gesamtreview 18.11.2026, T16-NM6)
    events = { "FRIENDLIST_UPDATE", "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE", "BN_FRIEND_INFO_CHANGED",
        "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE" },
    defaults = {
        enabled = false, zone = "right", order = 55, label = false,
        friends = true,     -- Freunde auf der Leiste
        guild = true,       -- Gilde auf der Leiste
        unread = false,     -- ungelesene Nachrichten (ezChat) auf der Leiste
    },
})

local SEPARATOR = "  "

local function InGuild() return IsInGuild and IsInGuild() and true or false end

---------------------------------------------------------------------------
-- ezChat (optional): ungelesene Nachrichten
---------------------------------------------------------------------------

local CHAT_CHANGED = "EZCHAT_CONVERSATIONS_CHANGED"   -- nur Ersatz; vorrangig ezCore.API("ezChat").CHANGED (T4-4)

local function ChatAPI()
    local api = ezCore.API("ezChat")
    if type(api) == "table" and type(api.Totals) == "function" then return api end
    return nil
end

-- Nachrichten ungelesen, wartend (über alle Gespräche) aus ezChat – nil ohne ezChat (oder wenn die Abfrage scheitert).
local function ChatTotals()
    local api = ChatAPI()
    if not api then return nil end
    local ok, unread, queued = pcall(api.Totals)
    if not ok then return nil end
    return ns.Num(unread) or 0, ns.Num(queued) or 0
end
block.ChatTotals = ChatTotals

-- ezChats Gesprächsfenster öffnen bzw. schließen: über eine Schnittstellen-Funktion, falls ezChat sie anbietet,
-- sonst über ezChats eigenen Befehl /ezchat ohne Wort (er schaltet das Gesprächsfenster). → true, wenn es ging.
local function OpenChat()
    local api = ChatAPI()
    if not api then return false end
    for _, name in ipairs({ "ToggleWindow", "OpenWindow" }) do
        if type(api[name]) == "function" then
            local ok = pcall(api[name])
            return ok
        end
    end
    local handler = ns.SlashHandler and ns.SlashHandler("/ezchat")
    if not handler then return false end
    local ok, err = pcall(handler, "")
    if not ok then ns.Error(err, "OpenChat") end
    return ok
end
block.OpenChat = OpenChat

-- Die Teile auf der Leiste in ihrer Reihenfolge: "friends", "guild" und – auf Wunsch, nur solange in ezChat etwas
-- ungelesen ist – "chat"; keiner, einer oder mehrere.
local function BarParts(cfg)
    local parts = {}
    if cfg.friends then parts[#parts + 1] = "friends" end
    if cfg.guild and InGuild() then parts[#parts + 1] = "guild" end
    if cfg.unread then
        local unread = ChatTotals()
        if unread and unread > 0 then parts[#parts + 1] = "chat" end
    end
    return parts
end

-- Die Teile ohne "chat" und ob "chat" auf der Leiste steht.
local function SplitParts(cfg)
    local parts, chat = {}, false
    for _, part in ipairs(BarParts(cfg)) do
        if part == "chat" then chat = true else parts[#parts + 1] = part end
    end
    return parts, chat
end

-- Hinweise passend zu dem, was auf der Leiste steht (der Tooltip nennt immer beide Fenster). Steht der Teil
-- „Nachrichten“ dabei, nennt jeder Linksklick-Hinweis seinen Teil; steht er allein dort, öffnet Shift+Linksklick die
-- Freundesliste (OnClick). Klick-Hinweise mit Umschalt über ezCore (Core.ClickText, T18-9).
local function Shift(text) return ezCore.ClickText("left", "SHIFT", text) end
block.hints = function(self)
    local parts, chat = SplitParts(self.cfg)
    local hints
    if #parts == 2 then
        hints = { L.SOCIAL_HINT_PART_FRIENDS, L.SOCIAL_HINT_PART_GUILD, Shift(L.SOCIAL_HINT_SHIFT_OTHER) }
    elseif parts[1] == "guild" then
        hints = { chat and L.SOCIAL_HINT_PART_GUILD or L.SOCIAL_HINT_LEFT_GUILD, Shift(L.SOCIAL_HINT_SHIFT_FRIENDS) }
    elseif parts[1] == "friends" or not chat then
        hints = { chat and L.SOCIAL_HINT_PART_FRIENDS or L.SOCIAL_HINT_LEFT, Shift(L.SOCIAL_HINT_SHIFT) }
    else
        hints = { Shift(L.SOCIAL_HINT_SHIFT_FRIENDS) }
    end
    if chat then table.insert(hints, 1, L.SOCIAL_HINT_PART_CHAT) end
    return hints
end

local function RequestGuild()
    if IsInGuild and IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
end

local function RequestFriends()
    if C_FriendList and C_FriendList.ShowFriends then pcall(C_FriendList.ShowFriends) end
end

-- Online: { friend = { {name, label} }, bnet = …, guild = … } und die Zahl der Gildenmitglieder.
local function Online()
    local lists = { friend = {}, bnet = {}, guild = {} }
    local seen = {}
    ezCore.ForEachContact(function(full, online, source, label, class)
        if not online or ezCore.IsSelf(full) then return end
        local list = lists[source]
        if not list or seen[source .. full] then return end
        seen[source .. full] = true
        list[#list + 1] = { name = full, label = label, class = class }
    end)
    for _, list in pairs(lists) do
        table.sort(list, function(a, b) return a.name < b.name end)
    end
    local total = IsInGuild and IsInGuild() and GetNumGuildMembers and ns.Num((GetNumGuildMembers())) or nil
    return lists, total
end

function block:GetText()
    local cfg = self.cfg
    local lists = Online()
    local parts = {}
    for _, part in ipairs(BarParts(cfg)) do
        if part == "friends" then
            parts[#parts + 1] = L.SOCIAL_FRIENDS_SHORT:format(#lists.friend + #lists.bnet)
        elseif part == "guild" then
            parts[#parts + 1] = L.SOCIAL_GUILD_SHORT:format(#lists.guild)
        else
            parts[#parts + 1] = ns.GOLD .. L.SOCIAL_CHAT_SHORT:format((ChatTotals())) .. "|r"
        end
    end
    self.partTexts = parts      -- Texte der Teile: Grenzen der Klickzonen (PartAt)
    self.firstPart = parts[1]
    return table.concat(parts, SEPARATOR)
end

-- Breite eines Textes in der Schrift der Leiste (unsichtbare Messzeile am Baustein).
local function TextWidth(frame, text)
    local m = frame.socialMeasure
    if not m then
        m = frame:CreateFontString(nil, "OVERLAY")
        m:SetFontObject(ns.font)
        m:SetWordWrap(false)
        m:SetAlpha(0)
        m:SetPoint("LEFT", frame, "LEFT", 0, 0)
        frame.socialMeasure = m
    end
    m:SetText(text)
    local width = m.GetUnboundedStringWidth and m:GetUnboundedStringWidth() or m:GetStringWidth()
    return ns.Num(width)
end

-- Welcher Teil liegt unter dem Mauszeiger? → "friends" | "guild" | "chat". Zwischen zwei Teilen trennt die Mitte
-- der Lücke (etwa zwischen „Freunde n“ und „Gilde n“); steht nur ein Teil da, gilt er (ohne Teil: Freunde).
function block:PartAt(frame)
    local parts = BarParts(self.cfg)
    if #parts < 2 then return parts[1] or "friends" end
    local texts = self.partTexts
    local x = GetCursorPosition and ns.Num((GetCursorPosition()))
    local left = frame and frame.text and frame.text.GetLeft and ns.Num(frame.text:GetLeft())
    local scale = frame and frame.GetEffectiveScale and ns.Num(frame:GetEffectiveScale())
    if not (type(texts) == "table" and #texts == #parts and x and left and scale and scale > 0) then return parts[1] end
    local pos = x / scale - left
    local prefix = ""
    for i = 1, #parts - 1 do
        prefix = prefix .. (i > 1 and SEPARATOR or "") .. texts[i]
        local w1, w2 = TextWidth(frame, prefix), TextWidth(frame, prefix .. SEPARATOR)
        if not (w1 and w2) then return parts[1] end
        if pos <= (w1 + w2) / 2 then return parts[i] end
    end
    return parts[#parts]
end

local function AddList(tooltip, title, list, right)
    tooltip:AddLine(" ")
    ns.TipDoubleLine(tooltip, title, right or tostring(#list), "normal", "highlight")
    -- Leertext (PANEL-17): eine leere Liste sagt, dass gerade niemand da ist
    if #list == 0 then ns.TipLine(tooltip, "  " .. L.SOCIAL_NOBODY, "hint") end
    for i, e in ipairs(list) do
        if i > MAX_LINES then
            ns.TipLine(tooltip, ezCore.More(#list - MAX_LINES), "hint")
            break
        end
        ns.TipDoubleLine(tooltip, "  " .. ezCore.ClassText(ezCore.ShortName(e.name), e.class), e.label and ns.Grey(e.label) or "", "highlight", "highlight")
    end
end

function block:OnTooltip(tooltip)
    local lists, total = Online()
    AddList(tooltip, L.SOCIAL_FRIENDS, lists.friend)
    if #lists.bnet > 0 then AddList(tooltip, L.SOCIAL_BNET, lists.bnet) end
    if IsInGuild and IsInGuild() then
        local name = GetGuildInfo and ezCore.Plain((GetGuildInfo("player")))
        AddList(tooltip, type(name) == "string" and name or L.SOCIAL_GUILD, lists.guild,
            total and L.SOCIAL_OF:format(#lists.guild, total) or nil)
    end
    local unread, queued = ChatTotals()
    if unread then
        tooltip:AddLine(" ")
        ns.TipDoubleLine(tooltip, L.SOCIAL_CHAT_UNREAD, tostring(unread), "normal", "highlight")
        if queued > 0 then ns.TipDoubleLine(tooltip, L.SOCIAL_CHAT_QUEUED, tostring(queued), "normal", "highlight") end
    end
end

local function OpenFriends() return ezCore.TogglePanel("friends") end
local function OpenGuild() return ezCore.TogglePanel("guild") end

block.actions = function()
    local list = { { text = L.SOCIAL_OPEN_FRIENDS, fn = OpenFriends } }
    if IsInGuild and IsInGuild() then list[#list + 1] = { text = L.SOCIAL_OPEN_GUILD, fn = OpenGuild } end
    if ChatAPI() then list[#list + 1] = { text = L.SOCIAL_OPEN_CHAT, fn = OpenChat } end
    return list
end

function block:OnClick(button, frame)
    if button ~= "LeftButton" then return end
    local part = self:PartAt(frame)
    if part == "chat" and not IsShiftKeyDown() then
        OpenChat()
        return
    end
    -- Shift+Linksklick auf „Nachrichten“ wirkt wie auf den ersten anderen Teil; steht keiner da: Freundesliste
    if part == "chat" then
        part = SplitParts(self.cfg)[1]
        if not part then return OpenFriends() end
    end
    if IsShiftKeyDown() then part = part == "guild" and "friends" or "guild" end
    if part == "guild" then OpenGuild() else OpenFriends() end
end

function block:OnMenu(root)
    local bar = root:CreateButton(L.MENU_BAR_SHOWS)
    ns.MenuCheck(bar, L.SOCIAL_FRIENDS, self.cfg, "friends", self)
    ns.MenuCheck(bar, L.SOCIAL_GUILD, self.cfg, "guild", self)
    if ChatAPI() then ns.MenuCheck(bar, L.SOCIAL_CHAT, self.cfg, "unread", self) end
end

-- ezChat meldet Änderungen (neue, gelesene, wartende Nachrichten): Zahl und Tooltip nachziehen. Der Name kommt aus
-- ezChats Schnittstelle (API.CHANGED, Gesamtreview 18.11.2026, T4-4); beim Laden der Datei ist ezChat vielleicht noch
-- nicht da, deshalb zuerst der Ersatzname und nach dem Anmelden noch einmal (wie ezSocial/Talk.lua).
local listening = {}
local function OnChatChanged() ns.QueueUpdate(block) end

function ns.ListenChatChanged()
    local api = ChatAPI()
    local message = api and api.CHANGED
    if ezCore.IsSecret(message) or type(message) ~= "string" or message == "" then message = CHAT_CHANGED end
    if not listening[message] then
        listening[message] = true
        ezCore.Listen(message, OnChatChanged, "ezPanel")
    end
    return message
end

ns.ListenChatChanged()
ns.OnReady(ns.ListenChatChanged)

-- Die Gildenliste schickt der Server nur auf Nachfrage: solange der Baustein an ist, jede Minute.
local ticker

function block:OnEnable()
    RequestFriends()
    RequestGuild()
    if not ticker then ticker = C_Timer.NewTicker(60, RequestGuild) end
end

function block:OnDisable()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
end
