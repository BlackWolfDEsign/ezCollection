local _, ns = ...
local L = ns.L
local Conv = ns.Conv

-- Alarme: Ton und Blinken des Spielsymbols in der Taskleiste (FlashClientIcon),
-- wenn in einem gewählten Kanal geschrieben wird, ein bestimmter Partner irgendwo schreibt oder der
-- eigene Name bzw. ein Stichwort fällt. Dazu Töne für Briefe und Community-Nachrichten und „Stumm“ für
-- einzelne Gesprächspartner.
-- Flüstern hat schon Blizzards eigenen Ton und lässt das Spielsymbol von selbst blinken
-- (Blizzard_ChatFrameBase/Mainline/ChatFrameOverrides.lua) – dafür baut ezChat nichts nach.

local Alarms = {}
ns.Alarms = Alarms

local THROTTLE = 3   -- höchstens ein Ton alle drei Sekunden
local lastRing = -THROTTLE

-- Chat-Ereignis → Schalter. CHAT_MSG_CHANNEL: je Kanal (ns.db.alarmChannels).
local GROUP_OF = {
    CHAT_MSG_GUILD = "alarmGuild",
    CHAT_MSG_OFFICER = "alarmOfficer",
    CHAT_MSG_PARTY = "alarmParty",
    CHAT_MSG_PARTY_LEADER = "alarmParty",
    CHAT_MSG_RAID = "alarmRaid",
    CHAT_MSG_RAID_LEADER = "alarmRaid",
    CHAT_MSG_RAID_WARNING = "alarmRaid",
    CHAT_MSG_INSTANCE_CHAT = "alarmInstance",
    CHAT_MSG_INSTANCE_CHAT_LEADER = "alarmInstance",
    CHAT_MSG_SAY = "alarmSay",
    CHAT_MSG_YELL = "alarmSay",
    CHAT_MSG_COMMUNITIES_CHANNEL = "alarmCommunity",
    CHAT_MSG_CHANNEL = false,
}

-- Reihenfolge im Menü und auf der Einstellungsseite.
Alarms.GROUPS = { "alarmGuild", "alarmOfficer", "alarmParty", "alarmRaid", "alarmInstance", "alarmSay", "alarmCommunity" }

---------------------------------------------------------------------------
-- Ton und Blinken
---------------------------------------------------------------------------

function Alarms.Play(tone)
    -- Core.PlaySound (T16-NM4): unbekannter Ton » MAP_PING, ohne PlaySound oder SOUNDKIT still. Kanal „Master“,
    -- hörbar auch ohne Soundeffekte (docs/design-system.md, „Warntöne“; T16-NM5)
    if not ezCore.PlaySound(tone or "", "Master") then ezCore.PlaySound("MAP_PING", "Master") end
end

-- Ton und Blinken; true, wenn ausgelöst (nicht gedrosselt). In einer Lage, in der ezChats Alarme schweigen sollen
-- (Situation.lua, sitAlarm<Lage>), klingelt nichts – außer force (der Ton bei Flüstern, nur abwesend: Situation.Incoming).
function Alarms.Ring(tone, force)
    if not force and ns.Situation and not ns.Situation.AlarmsAllowed() then return false end
    local now = GetTime()
    if now - lastRing < THROTTLE then return false end
    lastRing = now
    Alarms.Play(tone or ns.S.alarmTone)
    if ns.S.alarmFlash and type(FlashClientIcon) == "function" then pcall(FlashClientIcon) end
    return true
end

-- Neue Nachricht im Gespräch (aus Conv.Add): Briefe und Community-Nachrichten klingen wie Flüstern.
-- Flüstern: in manchen Lagen zusätzlich ezChats Ton (Situation.Incoming).
function Alarms.Incoming(convo, entry)
    if ns.Situation then ns.Situation.Incoming(convo, entry) end
    if not ns.S.soundLetters or not convo or convo.muted then return end
    if entry.v ~= "p" and entry.v ~= "c" then return end
    Alarms.Ring("TELL_MESSAGE")
end

---------------------------------------------------------------------------
-- Kanäle und Partner
---------------------------------------------------------------------------

local function ConvoOfSender(sender)
    local full = ns.FullName(sender)
    if not full then return nil end
    return ns.C.convos[Conv.KeyOf(ns.CompleteName(full))]
end

-- Warum klingelt es? "channel", "partner", "highlight" oder nil.
function Alarms.Reason(event, text, sender, channelName)
    local group = GROUP_OF[event]
    if group and ns.S[group] then return "channel" end
    if event == "CHAT_MSG_CHANNEL" then
        local key = ezCore.ChannelKey(channelName)
        if key and ns.db.alarmChannels[key] then return "channel" end
    end
    local convo = ConvoOfSender(sender)
    if convo and convo.alarm and not convo.muted then return "partner" end
    if ns.Active("highlight") and ns.Active("highlightSound") and ns.Format.Matches(text) then return "highlight" end
    return nil
end

-- Argument 9 ist bei Kanälen der Kanalname ohne Nummer („Handel - Stadt“).
local function OnMessage(event, text, sender, _, _, _, _, _, _, channelName)
    if not (ns.C and ns.Format) or type(text) ~= "string" or type(sender) ~= "string" then return end
    if not ns.Usable(text, sender, channelName) or ns.Format.FromSelf(sender) then return end
    if Alarms.Reason(event, text, sender, channelName) then Alarms.Ring() end
end

for event in pairs(GROUP_OF) do ns.On(event, OnMessage) end

-- Kanäle, denen du gerade angehörst, und solche mit Alarm: { key, label }.
function Alarms.Channels()
    local list, seen = {}, {}
    if type(GetChannelList) == "function" then
        local data = { GetChannelList() }
        for i = 1, #data, 3 do
            local name = data[i + 1]
            local key = ezCore.ChannelKey(name)
            if key and not seen[key] then
                seen[key] = true
                list[#list + 1] = { key = key, label = ezCore.ChannelName(name) or name }
            end
        end
    end
    for key in pairs(ns.db.alarmChannels) do
        if not seen[key] then
            seen[key] = true
            list[#list + 1] = { key = key, label = key }
        end
    end
    table.sort(list, function(a, b) return a.key < b.key end)
    return list
end

function Alarms.ToggleChannel(key)
    if not key then return end
    ns.db.alarmChannels[key] = (not ns.db.alarmChannels[key]) or nil
end

---------------------------------------------------------------------------
-- Stumm: Flüstern eines stummen Partners nicht im Chatfenster zeigen
---------------------------------------------------------------------------

-- Verworfene Zeilen bringen auch Blizzards Flüster-Ton und das Blinken nicht; ezChat schreibt das
-- Flüstern trotzdem still ins Gespräch (eigenes Ereignis, unabhängig vom Chatfenster).
-- Argument 13 ist bei Battle.net die Konto-ID des Absenders.
function Alarms.MuteFilter(_, event, msg, sender, ...)
    if not ns.C or type(msg) ~= "string" or not ns.Usable(msg, sender) then return false end
    local key
    if event == "CHAT_MSG_BN_WHISPER" then
        local tag = ns.BNTagOf((select(11, ...)))
        key = tag and Conv.KeyOf(tag, true)
    elseif type(sender) == "string" then
        local full = ns.FullName(sender)
        key = full and Conv.KeyOf(ns.CompleteName(full))
    end
    local convo = key and ns.C.convos[key]
    return convo ~= nil and convo.muted == true
end

ns.OnReady(function()
    ns.AddMessageEventFilter("CHAT_MSG_WHISPER", Alarms.MuteFilter)
    ns.AddMessageEventFilter("CHAT_MSG_BN_WHISPER", Alarms.MuteFilter)
end)

---------------------------------------------------------------------------
-- Menü „Alarme“ (Knopf im Gesprächsfenster, ezChat-Menü am Chat-Reiter, Einstellungsseite)
---------------------------------------------------------------------------

local Check = ezCore.Menu.Toggle   -- Häkchen; set schaltet selbst um

local function Toggle(key)
    return function() return ns.S[key] == true end, function() ns.SetSetting(key, not ns.S[key]) end
end

function Alarms.FillMenu(root)
    root:CreateTitle(L.ALARM_MENU_TITLE)
    for _, key in ipairs(Alarms.GROUPS) do Check(root, L["OPT_" .. key], Toggle(key)) end

    local channels = Alarms.Channels()
    if #channels > 0 then
        root:CreateDivider()
        root:CreateTitle(L.ALARM_CHANNELS)
        -- Design-System 2.11 (Welle 22): ab drei Kanälen ein Haken „Alle“ vor den Haken (seit 21.11.2026 einer)
        if #channels >= 3 and ezCore.Style then
            ezCore.Menu.AllToggle(root, channels, function(channel) return ns.db.alarmChannels[channel.key] == true end,
                function(channel, on) ns.db.alarmChannels[channel.key] = on or nil end)
        end
        for _, channel in ipairs(channels) do
            Check(root, channel.label, function() return ns.db.alarmChannels[channel.key] == true end,
                function() Alarms.ToggleChannel(channel.key) end)
        end
    end

    -- Partner mit Alarm: hier sichtbar und abschaltbar (eingeschaltet wird im Gespräch).
    local partners = {}
    for _, item in ipairs(Conv.Sorted()) do
        if item.convo.alarm then partners[#partners + 1] = item end
    end
    if #partners > 0 then
        root:CreateDivider()
        root:CreateTitle(L.ALARM_PARTNERS)
        -- Design-System 2.11: eingeschaltet wird im Gespräch, darum schaltet der Haken „Alle“ hier ab drei Partnern
        -- nur aus (on = false; angehakt, solange alle gezeigten Partner Alarm haben)
        if #partners >= 3 and ezCore.Style then
            ezCore.Menu.AllToggle(root, partners, function(item) return item.convo.alarm == true end,
                function(item, on) Conv.SetFlag(item.key, "alarm", on) end,
                { on = false })
        end
        for _, item in ipairs(partners) do
            Check(root, Conv.Display(item.convo), function() return item.convo.alarm == true end,
                function() Conv.SetFlag(item.key, "alarm", not item.convo.alarm) end)
        end
    end

    root:CreateDivider()
    local other = ns.Other("highlightSound")
    Check(root, other and (L.OPT_highlightSound .. " " .. ezCore.Grey("(" .. L.OTHER_SHORT:format(other) .. ")"))
        or L.OPT_highlightSound, Toggle("highlightSound"))
    Check(root, L.OPT_alarmFlash, Toggle("alarmFlash"))
    local tone = root:CreateButton(L.ALARM_TONE_MENU:format(L["TONE_" .. tostring(ns.S.alarmTone)] or "?"))
    for _, name in ipairs(ns.TONES) do
        local function Pick()
            ns.SetSetting("alarmTone", name)
            Alarms.Play(name)
            return ezCore.Menu.Refresh()   -- Menü bleibt offen: Töne nacheinander anhören
        end
        ezCore.Menu.Radio(tone, L["TONE_" .. name], function() return ns.S.alarmTone end, Pick, name)
    end
end

-- Menü an einem Knopf öffnen.
function Alarms.OpenMenu(owner)
    return ns.OpenMenu(owner, Alarms.FillMenu)
end
