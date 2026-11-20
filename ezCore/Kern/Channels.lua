local _, ns = ...
local Core = ezCore

--[[
    Chat und Kanäle: Chat-Sperre, Chatfilter, Gruppenkanal, senden, Emotes, Kanal-Namen und -Arten
    (Core.ChatLocked, Core.AddMessageEventFilter, Core.GroupChannel, Core.SendChat, Core.PerformEmote,
    Core.ZONE_CHANNELS, Core.CHANNEL_KINDS, Core.ChannelName, Core.ChannelKey, Core.ChannelKind, Core.EmoteCommand).
    Bis Welle 11 in Util.lua (EC-53, V-019); Namen unverändert.
    Welle 23a (A54, A55): Blizzards Emote-Tabellen (EMOTE<n>_TOKEN, EMOTE<n>_CMD<m>, hash_EmoteTokenList) liest nur noch
    ein Index an einer Stelle – Core.EmoteCommand(token) → erster Befehl, Core.EmoteCommands(token) → alle
    Schreibweisen (leer, wenn der Client das Emote nicht führt), Core.EmoteToken(befehl) → Emote zu „/danke“.
]]

---------------------------------------------------------------------------
-- Chat-Sperre und Chatfilter
---------------------------------------------------------------------------

-- Blizzards Chat-Sperre (z. B. in bestimmten Kämpfen): dann nichts senden.
function Core.ChatLocked()
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
        local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
        return ok and locked == true
    end
    return false
end

-- Chatfilter mit Forever-/Retail-Weiche.
function Core.AddMessageEventFilter(event, fn)
    if ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter then
        ChatFrameUtil.AddMessageEventFilter(event, fn)
    elseif ChatFrame_AddMessageEventFilter then
        ChatFrame_AddMessageEventFilter(event, fn)
    end
end

---------------------------------------------------------------------------
-- Chat (Gruppenkanal, senden, Emotes)
---------------------------------------------------------------------------

-- Chat-Art der eigenen Gruppe: "INSTANCE_CHAT", "RAID", "PARTY" oder nil (allein).
-- Die Instanzgruppe zuerst (MACRO-27): Auf Schlachtfeldern ist man zugleich „im Raid“ – die Ansage ginge sonst an
-- RAID statt an den Instanzkanal. Antworten des Spiels zuerst über Core.IsSecret, gesperrt zählt als „nein“.
function Core.GroupChannel()
    local inGroup, inRaid = rawget(_G, "IsInGroup"), rawget(_G, "IsInRaid")
    local instance = rawget(_G, "LE_PARTY_CATEGORY_INSTANCE")
    if instance ~= nil and Core.Bool(Core.Call(inGroup, instance), false) then return "INSTANCE_CHAT" end
    if Core.Bool(Core.Call(inRaid), false) then return "RAID" end
    if Core.Bool(Core.Call(inGroup), false) then return "PARTY" end
    return nil
end

-- Nachricht senden (Forever/Retail-Weiche), nie während Blizzards Chat-Sperre. chatType "GROUP" wählt
-- den Gruppenkanal. Rückgabe: true gesendet, false nicht gesendet (gesperrt, kein Kanal, Fehler).
function Core.SendChat(text, chatType, target)
    if type(text) ~= "string" or Core.IsSecret(text) or text == "" then return false end
    if chatType == "GROUP" then chatType = Core.GroupChannel() end
    if chatType == "GUILD" and not (IsInGuild and IsInGuild()) then return false end
    if not chatType or Core.ChatLocked() then return false end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or rawget(_G, "SendChatMessage")
    if type(send) ~= "function" then return false end
    return (pcall(send, text, chatType, nil, target))
end

-- Emote wie Blizzards Chat: ohne Ziel gilt es dem aktuellen Ziel, mit Namen wie „/danke Name“.
-- Rückgabe: true gesendet, false gesperrt oder fehlgeschlagen, nil ohne Blizzards Funktion.
function Core.PerformEmote(token, target)
    local perform = (C_ChatInfo and C_ChatInfo.PerformEmote) or rawget(_G, "DoEmote")
    if type(perform) ~= "function" or type(token) ~= "string" then return nil end
    if Core.ChatLocked() then return false end
    local ok, restricted = pcall(perform, token, target)
    return ok and not restricted
end

---------------------------------------------------------------------------
-- Chat-Kanäle (vorher je ein Leser in ezChat und ezSocial mit verschiedenem Ergebnis)
---------------------------------------------------------------------------

-- Blizzards feste Kanal-Nummern (zoneChannelID): 1 Allgemein, 2 Handel, 26 Suche nach Gruppe.
Core.ZONE_CHANNELS = { [1] = "general", [2] = "trade", [26] = "lfg" }
-- Kanal-Schlüssel (Core.ChannelKey) → Art, deutsch und englisch. „Welt“ ist ein selbst erstellter Kanal ohne feste Nummer.
Core.CHANNEL_KINDS = {
    general = "general", allgemein = "general",
    trade = "trade", handel = "trade",
    lookingforgroup = "lfg", suchenachgruppe = "lfg", lfg = "lfg",
    world = "world", welt = "world", global = "world",
}

-- Kanalname ohne Nummer und Gebiet: „2. Handel - Stadt“ → „Handel“. nil bei geheimem oder leerem Text
-- und für Community-Kanäle („Community:…“, die haben keinen lesbaren Namen).
function Core.ChannelName(text)
    if Core.IsSecret(text) or type(text) ~= "string" or text:find("Community:", 1, true) then return nil end
    local name = text:gsub("^%s*%d+%.%s*", "")              -- „2. Handel - Stadt“
    name = Core.Trim(name:match("^(.-)%s+%-%s+") or name)   -- „Handel - Stadt“
    if name == "" then return nil end
    return name
end

-- Ein Schlüssel je Kanal für Einstellungen und Alarme: Name klein und ohne Leerzeichen
-- („2. Suche nach Gruppe“ → „suchenachgruppe“), sonst nil wie Core.ChannelName.
function Core.ChannelKey(text)
    local name = Core.ChannelName(text)
    if not name then return nil end
    return (name:gsub("%s", "")):lower()
end

-- Art eines Kanals: "general", "trade", "lfg", "world" oder nil. Zuerst Blizzards feste Nummer
-- (zoneChannelID aus CHAT_MSG_CHANNEL), dann der Basisname, dann der angezeigte Name (de/en).
function Core.ChannelKind(zoneChannelID, baseName, channelName)
    local id = Core.Num(zoneChannelID)
    if id and Core.ZONE_CHANNELS[id] then return Core.ZONE_CHANNELS[id] end
    local key = Core.ChannelKey(baseName)
    if key and Core.CHANNEL_KINDS[key] then return Core.CHANNEL_KINDS[key] end
    key = Core.ChannelKey(channelName)
    return key and Core.CHANNEL_KINDS[key] or nil
end

-- Index der Emotes aus Blizzards Tabellen, einmal gebaut: byToken[TOKEN] = { "/befehl", … } (Schreibweise des
-- Clients, ohne Doppel ohne Rücksicht auf Groß-/Kleinschreibung), byCommand["/befehl" klein] = TOKEN (zuerst aus
-- EMOTE<n>_CMD<m>, dann aus hash_EmoteTokenList, Blizzards Nachschlage-Tabelle von ChatFrame).
local emoteIndex
local function EmoteIndex()
    if emoteIndex then return emoteIndex end
    local byToken, byCommand = {}, {}
    for i = 1, (tonumber(rawget(_G, "MAXEMOTEINDEX")) or 1000) do
        local token = rawget(_G, "EMOTE" .. i .. "_TOKEN")
        if type(token) == "string" and token ~= "" then
            local list = byToken[token]
            if not list then list = {}; byToken[token] = list end
            for m = 1, 10 do
                local cmd = rawget(_G, "EMOTE" .. i .. "_CMD" .. m)
                if type(cmd) ~= "string" then break end
                local low = cmd:lower()
                if cmd:sub(1, 1) == "/" and byCommand[low] == nil then
                    byCommand[low] = token
                    list[#list + 1] = cmd
                elseif cmd:sub(1, 1) == "/" and byCommand[low] ~= token then
                    list[#list + 1] = cmd   -- derselbe Befehl bei zwei Emotes: der erste gewinnt beim Rückweg
                end
            end
        end
    end
    local hash = rawget(_G, "hash_EmoteTokenList")
    if type(hash) == "table" then
        for key, token in pairs(hash) do
            if type(key) == "string" and type(token) == "string" and byCommand[key:lower()] == nil then
                byCommand[key:lower()] = token
            end
        end
    end
    emoteIndex = { byToken = byToken, byCommand = byCommand }
    return emoteIndex
end

-- Slash-Befehl eines Emotes („THANK“ → „/danke“ bzw. „/thank“) aus Blizzards Tabellen.
local EMOTE_FALLBACK = { FOLLOW = "/followme", HELPME = "/helpme", HEALME = "/healme", APOLOGIZE = "/apologize" }
function Core.EmoteCommand(token)
    if Core.IsSecret(token) or type(token) ~= "string" or token == "" then return nil end
    local list = EmoteIndex().byToken[token]
    return (list and list[1]) or EMOTE_FALLBACK[token] or ("/" .. token:lower())
end

-- Alle Schreibweisen eines Emotes, wie der Client sie führt („SPIT“ → { "/spucken", "/spit" } im deutschen Client) –
-- als Kopie; leer, wenn der Client das Emote nicht führt (dann gilt es als unbekannt, kein Rückfall).
function Core.EmoteCommands(token)
    local out = {}
    if Core.IsSecret(token) or type(token) ~= "string" or token == "" then return out end
    for i, cmd in ipairs(EmoteIndex().byToken[token] or {}) do out[i] = cmd end
    return out
end

-- Emote zu einem Befehl („/danke“, „danke“, „/THANK Bob“ → "THANK"); nil, wenn der Client den Befehl nicht kennt.
function Core.EmoteToken(command)
    if type(command) ~= "string" or Core.IsSecret(command) then return nil end
    local word = command:match("^%s*(%S+)")
    if not word then return nil end
    if word:sub(1, 1) ~= "/" then word = "/" .. word end
    return EmoteIndex().byCommand[word:lower()]
end
