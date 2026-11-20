local _, ns = ...
local L = ns.L
local Conv = ns.Conv

-- Dauerhafter Chatverlauf: Nachrichten der eingeschalteten Kanäle speichern und
-- beim Einloggen grau mit Zeitstempel im passenden Chatfenster wiederherstellen.
-- Flüstern und Battle.net kommen aus den Gesprächen (Conversations.lua).

local History = {}
ns.History = History

local CHANNEL_OF = {
    CHAT_MSG_GUILD = "guild",
    CHAT_MSG_OFFICER = "guild",
    CHAT_MSG_PARTY = "party",
    CHAT_MSG_PARTY_LEADER = "party",
    CHAT_MSG_RAID = "party",
    CHAT_MSG_RAID_LEADER = "party",
    CHAT_MSG_RAID_WARNING = "party",
    CHAT_MSG_INSTANCE_CHAT = "party",
    CHAT_MSG_INSTANCE_CHAT_LEADER = "party",
    CHAT_MSG_SAY = "say",
    CHAT_MSG_YELL = "say",
    CHAT_MSG_EMOTE = "say",
}

local SETTING_OF = {
    guild = "historyGuild",
    party = "historyParty",
    say = "historySay",
}

-- Nachrichtengruppe der Chatfenster-Einstellungen je Chat-Typ.
local GROUP_OF = {
    PARTY_LEADER = "PARTY",
    RAID_LEADER = "RAID",
    INSTANCE_CHAT_LEADER = "INSTANCE_CHAT",
    WHISPER_INFORM = "WHISPER",
    BN_WHISPER_INFORM = "BN_WHISPER",
}

local GREY = 0.6
local DIM = 0.45

---------------------------------------------------------------------------
-- Mitschreiben
---------------------------------------------------------------------------

local function Record(event, text, sender)
    local channel = CHANNEL_OF[event]
    if not channel or not ns.C or not ns.S[SETTING_OF[channel]] then return end
    if not ns.Usable(text, sender) or type(text) ~= "string" or text == "" then return end

    ns.NoteRaw(event:sub(10), sender)
    local list = ns.C.history[channel]
    if not list then
        list = {}
        ns.C.history[channel] = list
    end
    list[#list + 1] = {
        t = time(),
        e = event:sub(10),   -- "CHAT_MSG_GUILD" → "GUILD"
        n = type(sender) == "string" and sender or "",
        m = text,
    }
    local cap = ns.Number("keepCount")
    for _ = 1, #list - cap do table.remove(list, 1) end
end

for event in pairs(CHANNEL_OF) do ns.On(event, Record) end

-- Obergrenze sofort anwenden, wenn sie verkleinert wird.
ns.OnSettingChanged(function(key)
    if key ~= "keepCount" or not ns.C then return end
    local cap = ns.Number("keepCount")
    for _, list in pairs(ns.C.history) do
        for _ = 1, #list - cap do table.remove(list, 1) end
    end
end)

function History.ClearAll()
    if not ns.C then return end
    wipe(ns.C.history)
    Conv.ClearAll()
    ns.Print(L.CLEARED)
end

---------------------------------------------------------------------------
-- Wiederherstellen
---------------------------------------------------------------------------

-- Symbole ({rt1} …) wie im Chat, Internetadressen als ezChat-Link (ChatFormat.lua). own: Zeile für ezChats
-- eigenes Fenster; dort bleiben die Links, auch wenn ein fremdes Chat-Addon sie im Chatfenster übernimmt.
local function Icons(text, own)
    if C_ChatInfo and C_ChatInfo.ReplaceIconAndGroupExpressions then
        local ok, result = pcall(C_ChatInfo.ReplaceIconAndGroupExpressions, text)
        if ok and type(result) == "string" then text = result end
    end
    local links
    if own then links = ns.S.links else links = ns.Active("links") end
    if links and ns.Format then text = ns.Format.Linkify(text) end
    return text
end

local function NameLink(raw)
    if type(raw) ~= "string" or raw == "" then return "" end
    local full = ns.FullName(raw) or raw
    return ("|Hplayer:%s|h[%s]|h"):format(ns.LinkName(full), ns.Short(full))
end

-- Eine Zeile im Stil des Blizzard-Chats, z. B. "[Gilde] [Elara]: Hallo".
local function Format(chatType, sender, text, isBN, own)
    local name = isBN and ("[" .. sender .. "]") or NameLink(sender)
    local fmt = _G["CHAT_" .. chatType .. "_GET"]
    if type(fmt) == "string" and fmt:find("%%s") then
        local ok, prefix = pcall(string.format, fmt, name)
        if ok then return prefix .. Icons(text, own) end
    end
    return "[" .. chatType .. "] " .. name .. ": " .. Icons(text, own)
end

-- Gespeicherter Kanalverlauf (Gilde, Gruppe, Sagen), der zur Suche passt – Text oder Absender,
-- query klein geschrieben. Älteste zuerst: { t, line, chatType, plain }.
function History.Search(query)
    local found = {}
    if not (ns.C and type(query) == "string" and query ~= "") then return found end
    for _, list in pairs(ns.C.history) do
        for _, e in ipairs(list) do
            if type(e.m) == "string" then
                local plain = ns.PlainText(e.m)
                local who = ""
                if type(e.n) == "string" and e.n ~= "" then who = ns.Short(ns.FullName(e.n) or e.n) or e.n end
                if plain:lower():find(query, 1, true) or who:lower():find(query, 1, true) then
                    found[#found + 1] = { t = e.t or 0, line = Format(e.e, e.n, e.m, false, true), chatType = e.e, plain = plain }
                end
            end
        end
    end
    table.sort(found, function(a, b) return a.t < b.t end)
    return found
end

local function IsWhisper(msg)
    return msg.s == nil and (msg.v == nil or msg.v == "w" or msg.v == "b")
end

-- Eine Gesprächsnachricht als Chatzeile wie Blizzards Flüstern, mit Hinweis auf
-- Brief, Community und Warteschlange. Gemeinsame Zeilenform für Chat und Verlauf.
function History.ConvoLine(convo, msg)
    local chatType, line
    if convo.bn then
        chatType = msg.o and "BN_WHISPER_INFORM" or "BN_WHISPER"
        line = Format(chatType, Conv.Display(convo), msg.m, true)
    else
        chatType = msg.o and "WHISPER_INFORM" or "WHISPER"
        line = Format(chatType, convo.name, msg.m, false)
    end
    if msg.v == "p" then
        line = line .. " " .. L.VIA_MAIL
    elseif msg.v == "c" then
        line = line .. " " .. L.VIA_COMMUNITY
    end
    if msg.s == "q" then
        line = line .. " " .. (msg.h and L.STATE_HELD or L.STATE_QUEUED)
    elseif msg.s == "x" then
        line = line .. " " .. L.STATE_FAILED
    end
    return line, chatType
end

-- Was in welchem Chatfenster schon als Verlauf steht: [Fenster][Gesprächsschlüssel] = true.
-- Nachrichten dieser Sitzung stehen ohnehin im Chat; der Verlauf zeigt nur ältere,
-- und das je Fenster nur einmal – sonst erscheint alles doppelt.
local printed = setmetatable({}, { __mode = "k" })

local function MarkPrinted(frame, key)
    printed[frame] = printed[frame] or {}
    printed[frame][key] = true
end

-- Die letzten limit Nachrichten eines Gesprächs von vor dieser Sitzung grau mit
-- Zeitstempel in ein Chatfenster, einmal je Fenster.
function History.PrintConvo(frame, convo, limit)
    local key = Conv.KeyOf(convo.name, convo.bn)
    if not frame or not key or (printed[frame] and printed[frame][key]) then return false end
    local before = ns.loginTime or time()
    local old = {}
    for _, msg in ipairs(convo.msgs) do
        if (msg.t or 0) < before then old[#old + 1] = msg end
    end
    MarkPrinted(frame, key)
    if #old == 0 then return false end
    local first = math.max(1, #old - math.max(1, limit) + 1)
    frame:AddMessage(L.CHAT_HISTORY_HEADER:format(Conv.Display(convo), #old - first + 1), DIM, DIM, DIM)
    for i = first, #old do
        local msg = old[i]
        frame:AddMessage(("[%s] %s"):format(ns.TimeText(msg.t), (History.ConvoLine(convo, msg))), GREY, GREY, GREY)
    end
    frame:AddMessage(L.RESTORE_FOOTER, DIM, DIM, DIM)
    return true
end

local function Collect(cutoff)
    local items, seq = {}, 0
    local function Add(t, chatType, line, key)
        seq = seq + 1
        items[#items + 1] = { t = t, seq = seq, group = GROUP_OF[chatType] or chatType, line = line, key = key }
    end

    for channel, list in pairs(ns.C.history) do
        if ns.S[SETTING_OF[channel]] then
            for _, e in ipairs(list) do
                if (e.t or 0) < cutoff then Add(e.t, e.e, Format(e.e, e.n, e.m)) end
            end
        end
    end

    for key, convo in pairs(ns.C.convos) do
        local allowed
        if convo.bn then allowed = ns.S.historyBN else allowed = ns.S.historyWhisper end
        if allowed then
            for _, msg in ipairs(convo.msgs) do
                if (msg.t or 0) < cutoff and IsWhisper(msg) then
                    local line, chatType = History.ConvoLine(convo, msg)
                    Add(msg.t, chatType, line, key)
                end
            end
        end
    end

    table.sort(items, function(a, b)
        if a.t ~= b.t then return a.t < b.t end
        return a.seq < b.seq
    end)
    return items
end

local function ActiveFrames()
    local frames = {}
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local frame = _G["ChatFrame" .. i]
        if frame and i ~= 2 then   -- 2 = Kampflog
            local active
            if FCF_IsChatWindowIndexActive then
                active = FCF_IsChatWindowIndexActive(i)
            elseif GetChatWindowInfo then
                local _, _, _, _, _, _, shown, _, docked = GetChatWindowInfo(i)
                active = shown or docked
            end
            if active then frames[#frames + 1] = frame end
        end
    end
    return frames
end

function History.FrameShows(frame, group)
    if type(frame.ContainsMessageGroup) == "function" then
        local ok, result = pcall(frame.ContainsMessageGroup, frame, group)
        if ok and result ~= nil then return result == true end
    end
    if type(ChatFrame_ContainsMessageGroup) == "function" then
        local ok, result = pcall(ChatFrame_ContainsMessageGroup, frame, group)
        if ok and result ~= nil then return result == true end
    end
    local list = frame.messageTypeList
    if type(list) == "table" then
        for _, value in pairs(list) do
            if value == group then return true end
        end
    end
    return false
end

-- Ohne eigene Kopf- und Endzeile (Entscheidung des Nutzers vom 20.11.2026): grau mit Zeitstempel genügt.
local function PrintBlock(frame, list, limit)
    local first = math.max(1, #list - limit + 1)
    for i = first, #list do
        local item = list[i]
        frame:AddMessage(("[%s] %s"):format(ns.TimeText(item.t), item.line), GREY, GREY, GREY)
        if item.key then MarkPrinted(frame, item.key) end   -- Gesprächsbeginn zeigt das nicht noch einmal
    end
end

function History.Restore()
    if not (ns.C and ns.Active("restore")) then return end
    local items = Collect(ns.loginTime or time())
    if #items == 0 then return end
    local limit = math.max(1, ns.Number("restoreCount"))

    local placed = false
    for _, frame in ipairs(ActiveFrames()) do
        local mine = {}
        for _, item in ipairs(items) do
            if History.FrameShows(frame, item.group) then mine[#mine + 1] = item end
        end
        if #mine > 0 then
            PrintBlock(frame, mine, limit)
            placed = true
        end
    end
    -- Konnte kein Fenster zugeordnet werden (andere Chat-API), alles ins Hauptfenster.
    if not placed and DEFAULT_CHAT_FRAME then PrintBlock(DEFAULT_CHAT_FRAME, items, limit) end
end

local restored = false
ns.On("PLAYER_ENTERING_WORLD", function()
    if restored then return end
    restored = true
    -- kurz warten, damit die Chatfenster eingerichtet sind
    C_Timer.After(1.5, function()
        local ok, err = pcall(History.Restore)
        if not ok then ns.Error(err) end
    end)
end)
