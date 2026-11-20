local _, ns = ...
local Conv = ns.Conv

-- Zweier-Community: Blizzards Communities (C_Club) speichern Chat auf dem Server,
-- auch wenn der Empfänger offline ist. Gibt es eine Charakter-Community, in der nur
-- du und dein Gesprächspartner Mitglied seid, gehen Offline-Nachrichten aus dem
-- Gesprächsfenster dort hin, und ihre Nachrichten erscheinen im Gespräch.
-- Anlegen: Blizzards Communities-Fenster → Community erstellen → nur den Partner einladen.

local Community = {}
ns.Community = Community

local echo = {}         -- [Text] = GetTime() eigener Sendungen (Echo nicht doppelt aufnehmen)
local requested = {}    -- [clubId] = true: Verlauf schon angefordert
local cache, cacheAt = nil, 0

function Community.Available()
    return C_Club ~= nil and type(C_Club.GetSubscribedClubs) == "function" and type(C_Club.SendMessage) == "function"
        and Enum ~= nil and Enum.ClubType ~= nil
end

-- Aufruf mit pcall aus ezCore (nil bei Fehler oder fehlender Funktion); vorher eine eigene Kopie (V-072).
local Call = ezCore.Call

local function Members(clubId)
    local members = {}
    local ids = Call(C_Club.GetClubMembers, clubId)
    if type(ids) ~= "table" then return members end
    for _, memberId in ipairs(ids) do
        local info = Call(C_Club.GetMemberInfo, clubId, memberId)
        if type(info) == "table" and type(info.name) == "string" and ns.Usable(info.name) then
            members[#members + 1] = { full = ns.FullName(info.name), self = info.isSelf == true }
        end
    end
    return members
end

local function DefaultStream(clubId)
    local streams = Call(C_Club.GetStreams, clubId)
    if type(streams) ~= "table" then return nil end
    local general = Enum.ClubStreamType and Enum.ClubStreamType.General
    for _, stream in ipairs(streams) do
        if general ~= nil and stream.streamType == general then return stream.streamId end
    end
    return streams[1] and streams[1].streamId
end

-- Alle Zweier-Communities: { clubId, streamId, partner = "Name-Realm", name }
function Community.Pairs()
    if cache and GetTime() - cacheAt < 10 then return cache end
    local list = {}
    if Community.Available() and ns.C then
        local clubs = Call(C_Club.GetSubscribedClubs)
        if type(clubs) == "table" then
            for _, club in ipairs(clubs) do
                if club.clubType == Enum.ClubType.Character and (club.memberCount == nil or club.memberCount == 2) then
                    local members = Members(club.clubId)
                    if #members == 2 then
                        local partner
                        for _, member in ipairs(members) do
                            if not member.self and member.full then partner = member.full end
                        end
                        local streamId = partner and DefaultStream(club.clubId)
                        if streamId then
                            list[#list + 1] = { clubId = club.clubId, streamId = streamId, partner = partner, name = club.name }
                        end
                    end
                end
            end
        end
    end
    cache, cacheAt = list, GetTime()
    return list
end

function Community.FindFor(full)
    local key = Conv.KeyOf(full)
    if not key then return nil end
    for _, pair in ipairs(Community.Pairs()) do
        if Conv.KeyOf(pair.partner) == key then return pair end
    end
    return nil
end

-- Der Merker vergleicht mit messageId.epoch (Serveruhr in Mikrosekunden): darum die Serveruhr (ezCore.Time).
local function MarkSeen(clubId)
    local key = tostring(clubId)
    local now = ezCore.Time.Now("server") + 2
    ns.C.clubs[key] = math.max(ns.C.clubs[key] or 0, now * 1000000)
end

-- Nur aus einer Eingabe des Spielers heraus aufrufen.
function Community.TrySend(convo, msg)
    if not (ns.S.community and Community.Available()) or convo.bn or not msg then return false end
    local pair = Community.FindFor(convo.name)
    if not pair then return false end
    local ok = pcall(C_Club.SendMessage, pair.clubId, pair.streamId, msg.m)
    if not ok then return false end
    echo[msg.m] = GetTime()
    MarkSeen(pair.clubId)
    msg.s, msg.v, msg.d = nil, "c", time()
    Conv.Changed(Conv.KeyOf(convo.name))
    return true
end

---------------------------------------------------------------------------
-- Live-Nachrichten
---------------------------------------------------------------------------

ns.On("CHAT_MSG_COMMUNITIES_CHANNEL", function(_, text, sender, _, channelName)
    if not (ns.C and ns.S.community) or not ns.Usable(text, sender, channelName) then return end
    if type(text) ~= "string" or type(channelName) ~= "string" then return end
    ns.NoteRaw("community", sender)
    ns.NoteRaw("channel", channelName)
    local clubText = channelName:match("^Community:([^:]+):")
    if not clubText then return end
    local pair
    for _, candidate in ipairs(Community.Pairs()) do
        if tostring(candidate.clubId) == clubText then pair = candidate end
    end
    if not pair then return end
    MarkSeen(pair.clubId)

    local full = ns.FullName(sender)
    if full and ns.IsSelf(full) then
        if echo[text] and GetTime() - echo[text] < 30 then
            echo[text] = nil
            return
        end
        Conv.Add(pair.partner, false, { m = text, o = true, v = "c" })
    else
        Conv.Add(pair.partner, false, { m = text, v = "c" })
    end
end)

---------------------------------------------------------------------------
-- Nachholen, was während du offline warst geschrieben wurde
---------------------------------------------------------------------------

function Community.CatchUp()
    if not (ns.C and ns.S.community and Community.Available()) then return end
    cache = nil
    for _, pair in ipairs(Community.Pairs()) do
        local key = tostring(pair.clubId)
        local last = ns.C.clubs[key] or 0
        local ranges = Call(C_Club.GetMessageRanges, pair.clubId, pair.streamId)
        local range = type(ranges) == "table" and ranges[#ranges] or nil
        if type(range) == "table" and range.oldestMessageId and range.newestMessageId then
            local msgs = Call(C_Club.GetMessagesInRange, pair.clubId, pair.streamId, range.oldestMessageId, range.newestMessageId)
            local newest = last
            if type(msgs) == "table" then
                for _, m in ipairs(msgs) do
                    local epoch = type(m.messageId) == "table" and tonumber(m.messageId.epoch) or 0
                    if epoch > last and not m.destroyed and type(m.content) == "string" and ns.Usable(m.content) then
                        local mine = type(m.author) == "table" and m.author.isSelf == true
                        Conv.Add(pair.partner, false, {
                            -- Serverstempel auf die PC-Uhr umrechnen, mit der alle anderen Einträge (Conv.Add:
                            -- time()) sortiert, gekürzt und in Tage geteilt werden (T16-NZ4, Gesamtreview 18.11.2026)
                            t = math.floor(ezCore.Time.FromServer(math.floor(epoch / 1000000))),
                            m = m.content,
                            o = mine or nil,
                            v = "c",
                            quiet = (last == 0) or nil,   -- Erstübernahme nicht als ungelesen zählen
                        })
                    end
                    if epoch > newest then newest = epoch end
                end
            end
            ns.C.clubs[key] = newest
        elseif not requested[key] then
            requested[key] = true
            Call(C_Club.RequestMoreMessagesBefore, pair.clubId, pair.streamId, nil, 50)
        end
    end
end

-- Nachrichten nachholen, gesammelt: Blizzard meldet nachgeladene Verläufe oft mehrmals hintereinander.
local CatchUpSoon = ns.Throttle(function() Community.CatchUp() end, 2)

ns.On("CLUB_MESSAGE_HISTORY_RECEIVED", function() CatchUpSoon() end)
ns.On("INITIAL_CLUBS_LOADED", function() CatchUpSoon() end)
ns.On("CLUB_MEMBER_ADDED", function() cache = nil end)
ns.On("CLUB_MEMBER_REMOVED", function() cache = nil end)
ns.On("CLUB_ADDED", function() cache = nil end)
ns.On("CLUB_REMOVED", function() cache = nil end)

ns.OnReady(function()
    C_Timer.After(8, CatchUpSoon)   -- nach dem Einloggen etwas Zeit für Blizzards Community-Liste
end)
