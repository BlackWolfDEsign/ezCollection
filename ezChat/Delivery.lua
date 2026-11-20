local _, ns = ...
local L = ns.L
local Conv = ns.Conv

-- Offline-Nachrichten: Warteschlange und Zustellung per Flüstern, sobald der
-- Empfänger online kommt. Briefe: Mail.lua, Zweier-Community: Community.lua.
--
-- Direktes Offline-Flüstern gibt es nicht: der Server lehnt mit "Spieler nicht
-- gefunden" ab. Diese Meldung wird erkannt und die Nachricht kommt in die Warteschlange.

local Delivery = {}
ns.Delivery = Delivery

local RECENT_WINDOW = 15     -- Sekunden zwischen Flüstern und "Spieler nicht gefunden"
local PENDING_TIMEOUT = 12   -- so lange auf die Bestätigung eines Zustellversuchs warten
local RETRY_INTERVAL = 300   -- Status unbekannt: so oft erneut versuchen
local TICK = 30
-- Obergrenzen je Nachricht (Prüfung auf Blizzards Regeln vom 17.11.2026, Risiko 9 – Richtlinie 3, keine Last für
-- Realm und Spieler): höchstens MAX_TRIES Zustellversuche oder MAX_SPAN Sekunden ab dem ersten Versuch, danach einmal
-- Bescheid, und die Nachricht wartet sichtbar ohne weitere Versuche (msg.h), bis der Spieler im Menü des Gesprächs
-- „Jetzt zustellen versuchen“ wählt (Delivery.Retry) oder dem Partner eine neue Nachricht schreibt (Delivery.Queue).
-- Zwischen zwei Versuchen an denselben Partner mindestens MIN_GAP Sekunden, auch wenn er als „online“ gilt (etwa weil
-- er ignoriert und nie bestätigt) – nach einer Bestätigung geht die nächste wartende Nachricht sofort. Gemerkt an der
-- Nachricht: n = Versuche, f = erster Versuch (time()), h = Zeitpunkt des Anhaltens (time()).
local MAX_TRIES = 12
local MAX_SPAN = 24 * 3600
local MIN_GAP = 120
Delivery.MAX_TRIES, Delivery.MAX_SPAN, Delivery.MIN_GAP = MAX_TRIES, MAX_SPAN, MIN_GAP

local recent = {}       -- [key] = { { m = Text, at = GetTime(), window = true|nil } }
local pending = {}      -- [key] = { msg = Nachricht, text = gesendeter Text, at = GetTime() }
local hideUntil = {}    -- [key] = GetTime(): Fehlermeldung eigener Zustellversuche ausblenden
local lastTry = {}      -- [key] = GetTime()
local lastRoster = 0
local expectUntil = {}  -- [key] = GetTime(): Gespräch über ezChat begonnen, Flüstern wie aus dem Fenster behandeln

local NOT_FOUND = ns.Pattern(ERR_CHAT_PLAYER_NOT_FOUND_S)
local FRIEND_ONLINE = ns.Pattern(ERR_FRIEND_ONLINE_SS)

---------------------------------------------------------------------------
-- Online-Status
---------------------------------------------------------------------------

-- Gilde und Battle.net-Freunde, die gerade einen Charakter in diesem Spiel spielen: ezCore.Contact, der eine
-- Kontaktspeicher für alle Module (gesammelt neu gelesen, online gewinnt; nur lesen). WoW-Freunde fragt
-- IsOnline/PartnerInfo zuerst direkt bei Blizzard, das ist immer aktuell.
local function Contact(convo)
    if not convo or convo.bn then return nil end
    return ezCore.Contact(convo.name)
end

-- Stufe, Klasse und Gebiet des Partners (wie WIM): aus Freundesliste, Battle.net oder Gilde.
-- Rückgabe { level, class, classFile, zone } oder nil, wenn nichts bekannt ist.
function Delivery.PartnerInfo(convo)
    if not convo then return nil end
    if convo.bn then
        local id = ns.BNFind(convo.name)
        local account = id and ezCore.BNInfoByID(id)
        local game = type(account) == "table" and account.gameAccountInfo
        if type(game) == "table" and ns.Usable(game.characterLevel, game.className, game.areaName) and game.characterLevel then
            return { level = game.characterLevel, class = game.className, classFile = ezCore.ClassOfGUID(game.playerGuid), zone = game.areaName }
        end
        return nil
    end
    if C_FriendList and C_FriendList.GetFriendInfo then
        local ok, info = pcall(C_FriendList.GetFriendInfo, ns.TellName(convo.name))
        if ok and type(info) == "table" and info.connected and ns.Usable(info.level, info.className, info.area) then
            return { level = info.level, class = info.className, classFile = ezCore.ClassOfGUID(info.guid), zone = info.area }
        end
    end
    local c = Contact(convo)
    if not (c and c.level) then return nil end
    return { level = c.level, class = c.class and ezCore.ClassName(c.class), classFile = c.class, zone = c.zone }
end

-- Blizzards Platzhalter „Unbekannt“ und leere Texte sind keine Angabe.
local function Known(text)
    if type(text) ~= "string" or text == "" or text == rawget(_G, "UNKNOWN") then return nil end
    return text
end

-- Zuletzt bekannte Angaben eines Partners, der offline ist – mit ihrer Quelle, weil sie alt sein können
-- (Leitlinie 11: jede Angabe nennt ihre Quelle):
--   WoW-Freund         Stufe und Klasse aus der Freundesliste, wenn sie eine Stufe nennt  source = "friend"
--   Gildenmitglied     Stufe, Klasse und letztes Gebiet aus ezCore.Contact                source = "guild", lastSeen
--                      (auch wenn er zugleich Freund ist: die Quelle ist die Liste, aus der die Stufe stammt –
--                      ezCores from.level, Welle 23c –, nie Gildendaten als „friend“; lastSeen = ungefähr zuletzt
--                      online laut Gildenliste, Blizzards GetGuildRosterLastOnline über ezCore)
--   Battle.net-Freund  der zuletzt gesehene Charakter aus ezCore.BNAlts (selbst gesehen)  source = "seen", seen, name
-- Rückgabe { level, class, classFile, zone, source, seen, lastSeen, lastOnline, name } oder nil (online, Status
-- unbekannt, nichts bekannt). lastOnline = ezCores { years, months, days, hours } der Gildenliste (nur lesen).
function Delivery.LastKnown(convo)
    if not convo or Delivery.IsOnline(convo) ~= false then return nil end
    if convo.bn then
        local alt = ezCore.BNAlts(convo.name)[1]
        local level = alt and tonumber(alt.level)
        if not (level and level > 0) then return nil end
        return { name = ezCore.ShortName(alt.name), level = level, classFile = alt.class,
            class = alt.class and ezCore.ClassName(alt.class) or nil, source = "seen", seen = alt.seen }
    end
    if C_FriendList and C_FriendList.GetFriendInfo then
        local ok, info = pcall(C_FriendList.GetFriendInfo, ns.TellName(convo.name))
        if ok and type(info) == "table" and ns.Usable(info.connected, info.level, info.className, info.area, info.guid)
            and info.connected == false and type(info.level) == "number" and info.level > 0 then
            return { level = info.level, class = Known(info.className), classFile = ezCore.ClassOfGUID(info.guid),
                zone = Known(info.area), source = "friend" }
        end
    end
    local c = Contact(convo)
    if not (c and type(c.level) == "number" and c.level > 0) then return nil end
    -- Freund und Gildenmitglied zugleich: ezCores Index nimmt Stufe 0 und „Unbekannt“ der Freundesliste nicht als
    -- Angabe und nennt je Angabe ihre Liste (Contacts.Known, from; Welle 23c, A49) – vorher las ezChat dafür die
    -- Zeile der Gilde selbst (GuildEntry)
    local source = type(c.from) == "table" and c.from.level or c.source
    local guild = source == "guild"
    return { level = c.level, class = c.class and ezCore.ClassName(c.class) or nil, classFile = c.class, zone = Known(c.zone),
        source = source, lastSeen = guild and tonumber(c.lastSeen) or nil,
        lastOnline = guild and type(c.lastOnline) == "table" and c.lastOnline or nil }
end

-- true = online, false = offline, nil = unbekannt (weder Freund noch Gilde)
function Delivery.IsOnline(convo)
    if not convo then return nil end
    if convo.bn then
        local id, online = ns.BNFind(convo.name)
        if id then return online, "bnet" end
        return nil
    end
    if C_FriendList and C_FriendList.GetFriendInfo then
        local ok, info = pcall(C_FriendList.GetFriendInfo, ns.TellName(convo.name))
        if ok and type(info) == "table" and ns.Usable(info.connected) then
            return info.connected == true, "friend"
        end
    end
    -- Battle.net-Freund, der gerade mit diesem Charakter spielt, sonst Gilde
    local c = Contact(convo)
    if c then return c.online, c.source end
    return nil
end

---------------------------------------------------------------------------
-- Zustellung per Flüstern
---------------------------------------------------------------------------

local function Same(a, b)
    if type(a) ~= "string" or type(b) ~= "string" then return false end
    return (ns.Trim(a):gsub("%s+", " ")) == (ns.Trim(b):gsub("%s+", " "))
end

function Delivery.IsPending(msg)
    for _, p in pairs(pending) do
        if p.msg == msg then return true end
    end
    return false
end

-- Ältere Nachrichten bekommen die Schreibzeit vorangestellt, z. B. "(19:42) ...".
local function OutgoingText(msg)
    if time() - (msg.t or time()) < 300 then return msg.m end
    local text = L.LATE_PREFIX:format(ns.TimeText(msg.t)) .. msg.m
    if #text > 255 then return msg.m end
    return text
end

-- Ein Zustellversuch beginnt oder läuft ab: Briefe am Briefkasten (Chat-Knopfleiste) zählen laufende
-- Versuche nicht mit, darum dort neu zählen.
local function PendingChanged()
    if ns.ChatBar then ns.ChatBar.Refresh() end
end

-- Hat die Nachricht ihre Versuche verbraucht (MAX_TRIES oder MAX_SPAN ab dem ersten Versuch)?
local function UsedUp(msg)
    local tries, first = tonumber(msg.n) or 0, tonumber(msg.f)
    return tries >= MAX_TRIES or (first ~= nil and time() - first >= MAX_SPAN)
end
Delivery.UsedUp = UsedUp

-- Anhalten: die Nachricht wartet sichtbar weiter, einmal Bescheid im Gespräch bzw. im Chat.
local function Hold(key, convo, msg)
    msg.h = time()
    Conv.Changed(key)
    local text = L.QUEUE_HELD:format(Conv.Display(convo), tonumber(msg.n) or 0)
    if ns.Chat then ns.Chat.Note(key, text) else ns.Print(text) end
end

-- Älteste wartende Nachricht an key senden. Klappt es, folgen die übrigen nacheinander.
-- manual: aus dem Klick des Spielers (Delivery.Retry) – ohne Mindestabstand und auch für eine angehaltene Nachricht.
function Delivery.Try(key, manual)
    local convo = key and ns.C and ns.C.convos[key]
    if not convo then return end
    local p = pending[key]
    if p and GetTime() - p.at < PENDING_TIMEOUT then return end
    pending[key] = nil
    local msg = Conv.FirstQueued(convo)
    if not msg or ns.InLockdown() then return end
    if ns.Mail and ns.Mail.IsInFlight(msg) then return end   -- geht gerade als Brief raus
    if not manual then
        -- „Offline-Nachrichten“ aus: was schon wartet, geht nur noch auf den Klick hinaus (code-reviewer 20.11.2026)
        if not ns.S.offlineQueue then return end
        if msg.h then return end                                         -- angehalten: keine Versuche mehr
        if lastTry[key] and GetTime() - lastTry[key] < MIN_GAP then return end
        if UsedUp(msg) then return Hold(key, convo, msg) end
    end

    local text = OutgoingText(msg)
    local sent
    if convo.bn then
        local id, online = ns.BNFind(convo.name)
        if not id or not online then return end
        sent = ns.SendBNWhisper(id, text)
    else
        hideUntil[key] = GetTime() + 8
        sent = ns.SendWhisper(ns.TellName(convo.name), text)
    end
    lastTry[key] = GetTime()
    if sent then
        msg.n = (tonumber(msg.n) or 0) + 1
        msg.f = tonumber(msg.f) or time()
        pending[key] = { msg = msg, text = text, at = GetTime() }
        PendingChanged()
    end
end

-- Zähler aller wartenden Nachrichten des Gesprächs zurück, auch angehaltene (ein neuer Klick des Spielers).
-- Rückgabe: Zahl der wartenden Nachrichten, Zahl der Nachrichten, an denen sich etwas geändert hat.
local function ResetTries(convo)
    local count, changed = 0, 0
    for _, msg in ipairs(convo.msgs) do
        if msg.o and msg.s == "q" then
            if msg.n ~= nil or msg.f ~= nil or msg.h ~= nil then changed = changed + 1 end
            msg.n, msg.f, msg.h = nil, nil, nil
            count = count + 1
        end
    end
    return count, changed
end

-- „Jetzt zustellen versuchen“ (Menü des Gesprächs): Zähler aller wartenden Nachrichten an key zurück, auch angehaltene,
-- und sofort ein Versuch. Rückgabe: Zahl der wartenden Nachrichten.
function Delivery.Retry(key)
    local convo = key and ns.C and ns.C.convos[key]
    if not convo then return 0 end
    local count = ResetTries(convo)
    if count > 0 then
        Conv.Changed(key)
        Delivery.Try(key, true)
    end
    return count
end

-- Der Partner ist sicher online (hat geflüstert oder kam online).
function Delivery.Online(key)
    local convo = key and ns.C and ns.C.convos[key]
    if convo and Conv.FirstQueued(convo) then
        C_Timer.After(0.5, function() Delivery.Try(key) end)
    end
end

local function TakeRecent(key, text)
    local list = key and recent[key]
    if not list then return false end
    for i, item in ipairs(list) do
        if Same(item.m, text) then
            table.remove(list, i)
            return true
        end
    end
    return false
end

-- Bestätigung "An X: ..." – war das ein eigener Zustellversuch? Dann true.
function Delivery.OnInform(key, text)
    local p = key and pending[key]
    if not p then
        TakeRecent(key, text)
        return false
    end
    local mine = Same(p.text, text) or Same(p.msg.m, text)
    if not mine and TakeRecent(key, text) then return false end   -- eine neue Nachricht von dir
    pending[key] = nil
    lastTry[key] = nil   -- bestätigt: die nächste wartende Nachricht geht ohne Mindestabstand
    local convo = ns.C.convos[key]
    p.msg.s = nil
    p.msg.n, p.msg.f, p.msg.h = nil, nil, nil
    p.msg.v = (convo and convo.bn) and "b" or "w"
    p.msg.d = time()
    Conv.Changed(key)
    C_Timer.After(0.6, function() Delivery.Try(key) end)
    return true
end

---------------------------------------------------------------------------
-- Senden und Warteschlange
---------------------------------------------------------------------------

function Delivery.Log(key, text, fromWindow)
    if not key then return end
    local list = recent[key]
    if not list then
        list = {}
        recent[key] = list
    end
    list[#list + 1] = { m = text, at = GetTime(), window = fromWindow or nil }
end

function Delivery.WaysText(convo)
    if convo.bn then return L.WAY_BNET end
    if ns.S.mailDelivery then return L.WAY_WHISPER .. L.WAY_MAIL end
    return L.WAY_WHISPER
end

local function Notice(convo)
    local text = L.QUEUED_NOTICE:format(Conv.Display(convo), Delivery.WaysText(convo))
    if ns.Chat then
        ns.Chat.Note(Conv.KeyOf(convo.name, convo.bn), text)
    else
        ns.Print(text)
    end
end

-- Über ezChat (Chat-Menü, Freundesliste) begonnenes Gespräch: zehn Minuten lang
-- landen Flüster an diese Person auch ohne „Auch Flüstern aus dem normalen Chat“
-- in der Warteschlange, wenn sie offline ist.
-- seconds: wie lange (Standard zehn Minuten; die Gesprächsansicht im Chatfenster
-- verlängert, solange sie das Gespräch zeigt).
function Delivery.Expect(key, seconds)
    if key then expectUntil[key] = GetTime() + (seconds or 600) end
end

-- fromUser: aus einer Eingabe des Spielers heraus, nur dann wird die Community direkt genutzt.
-- Jede neue Nachricht kommt von einer Eingabe des Spielers (Gesprächsfenster, /ezchat an, Flüstern aus dem Chat, das
-- „Spieler nicht gefunden“ bekam) und gilt als neuer Klick: Zähler und Anhalten der schon wartenden Nachrichten an
-- denselben Partner werden zurückgesetzt wie bei „Jetzt zustellen versuchen“ (ResetTries). Sonst stünde die neue
-- hinter einer angehaltenen (Conv.FirstQueued), und es würde nie mehr versucht – auch nicht, wenn der Partner online
-- kommt (Fund des code-reviewers, Welle 28). Der Mindestabstand MIN_GAP bleibt.
function Delivery.Queue(full, text, bn, fromUser)
    local convo, key, msg = Conv.Add(full, bn, { m = text, o = true, s = "q" })
    if not convo then return nil end
    local _, changed = ResetTries(convo)
    if changed > 0 then Conv.Changed(key) end
    if fromUser and not bn and ns.Community then ns.Community.TrySend(convo, msg) end
    return convo, key, msg
end

-- Nachricht aus dem Gesprächsfenster oder per /ezchat an senden.
-- Rückgabe false: nichts passiert, der Text bleibt im Eingabefeld.
function Delivery.Send(convo, text)
    text = ns.Trim(text)
    if not convo or text == "" then return false end
    local locked = ns.InLockdown()

    if convo.bn then
        local id, online = ns.BNFind(convo.name)
        if not id then
            ns.Print(L.BN_NOT_FRIEND)
            return false
        end
        if online and not locked then
            Delivery.Log(Conv.KeyOf(convo.name, true), text, true)
            return ns.SendBNWhisper(id, text)
        end
        if not ns.S.offlineQueue then
            ns.Print(locked and L.LOCKDOWN or L.OFFLINE_NO_QUEUE:format(Conv.Display(convo)))
            return false
        end
        Delivery.Queue(convo.name, text, true, false)
        if locked then ns.Print(L.QUEUED_LOCKDOWN) else Notice(convo) end
        return true
    end

    local online = Delivery.IsOnline(convo)
    if ns.S.offlineQueue and (online == false or locked) then
        local _, _, msg = Delivery.Queue(convo.name, text, false, not locked)
        if msg and msg.v == "c" then
            ns.Print(L.SENT_COMMUNITY:format(Conv.Display(convo)))
        elseif locked then
            ns.Print(L.QUEUED_LOCKDOWN)
        else
            Notice(convo)
        end
        return true
    end
    if locked then
        ns.Print(L.LOCKDOWN)
        return false
    end
    Delivery.Log(Conv.KeyOf(convo.name), text, true)
    return ns.SendWhisper(ns.TellName(convo.name), text)
end

---------------------------------------------------------------------------
-- Normales Flüstern aus dem Chat beobachten (nur lesen, nichts ändern)
---------------------------------------------------------------------------

local function OnChatSend(text, chatType, _, target)
    if chatType ~= "WHISPER" or not ns.C or ns.OwnSend() or not ns.Usable(text, target) then return end
    if type(text) ~= "string" or type(target) ~= "string" then return end
    local full = ns.FullName(target)
    if full then Delivery.Log(Conv.KeyOf(full), text, false) end
end

local function SafeOnChatSend(...)
    local ok, err = pcall(OnChatSend, ...)
    if not ok then ns.Error(err) end
end

if C_ChatInfo and type(C_ChatInfo.SendChatMessage) == "function" then
    hooksecurefunc(C_ChatInfo, "SendChatMessage", SafeOnChatSend)
elseif type(SendChatMessage) == "function" then
    hooksecurefunc("SendChatMessage", SafeOnChatSend)
end

local function OnBNSend(accountID, text)
    if not ns.C or not ns.Usable(accountID, text) or type(text) ~= "string" then return end
    local tag = ns.BNTagOf(accountID)
    if tag then Delivery.Log(Conv.KeyOf(tag, true), text, false) end
end

local function SafeOnBNSend(...)
    local ok, err = pcall(OnBNSend, ...)
    if not ok then ns.Error(err) end
end

if C_BattleNet and type(C_BattleNet.SendWhisper) == "function" then
    hooksecurefunc(C_BattleNet, "SendWhisper", SafeOnBNSend)
elseif type(BNSendWhisper) == "function" then
    hooksecurefunc("BNSendWhisper", SafeOnBNSend)
end

---------------------------------------------------------------------------
-- Systemmeldungen: "Spieler nicht gefunden" und "ist jetzt online"
---------------------------------------------------------------------------

-- Empfänger nicht erreichbar: zuletzt gesendete Flüster an ihn in die Warteschlange.
local function Unreachable(key, target, bn)
    if pending[key] then
        pending[key] = nil   -- ein laufender Zustellversuch ist gescheitert: die Nachricht wartet weiter
        PendingChanged()
    end
    local list = recent[key]
    recent[key] = nil
    if not list or not ns.S.offlineQueue then return end
    local now, convo, skipped = GetTime(), nil, false
    local expected = expectUntil[key] ~= nil and expectUntil[key] > now
    for _, item in ipairs(list) do
        if now - item.at <= RECENT_WINDOW then
            if item.window or expected or ns.S.catchChatWhispers then
                convo = Delivery.Queue(target, item.m, bn, false)
            else
                skipped = true
            end
        end
    end
    if convo then Notice(convo) end
    -- Eine Zeile aus dem normalen Chat wartet nur wegen des ausgeschalteten Nachsendens nicht: genau jetzt den Hinweis
    -- dazu am Chatfenster zeigen (Gegenprüfung P17) – an einen Offline-Spieler kommt kein CHAT_MSG_WHISPER_INFORM, auf
    -- das ezCores Fenster „chat“ sonst hört. ezCore zeigt ihn nur einmal je Account, nie im Kampf.
    if skipped then Delivery.HintSkipped() end
end

-- → true, wenn ezCores Hinweis am Chatfenster vorgemerkt ist
function Delivery.HintSkipped()
    local Hint = ezCore.OptInHint
    if ns.S.catchChatWhispers or not (Hint and Hint.ShowSoon) then return false end
    return Hint.ShowSoon("chat") == true
end

function Delivery.NotFound(name)
    ns.NoteRaw("notfound", name)
    local full = ns.FullName(name)
    if full then Unreachable(Conv.KeyOf(full), full, false) end
end

-- Battle.net: Blizzard meldet einen offline Freund mit eigenem Ereignis (Konto-ID in Argument 13).
ns.On("CHAT_MSG_BN_WHISPER_PLAYER_OFFLINE", function(_, _, _, _, _, _, _, _, _, _, _, _, _, bnSenderID)
    if not ns.C then return end
    local tag = ns.BNTagOf(bnSenderID)
    if tag then Unreachable(Conv.KeyOf(tag, true), tag, true) end
end)

ns.On("CHAT_MSG_SYSTEM", function(_, text)
    if not ns.C or not ns.Usable(text) or type(text) ~= "string" then return end
    if NOT_FOUND then
        local name = text:match(NOT_FOUND)
        if name then
            Delivery.NotFound(name)
            return
        end
    end
    if FRIEND_ONLINE then
        local name = text:match(FRIEND_ONLINE)
        local full = name and ns.FullName(name)
        if full then Delivery.Online(Conv.KeyOf(full)) end
    end
end)

-- Fehlermeldungen der eigenen, automatischen Zustellversuche nicht anzeigen.
local function SystemFilter(_, _, text, ...)
    if not NOT_FOUND or not ns.Usable(text) or type(text) ~= "string" then return false end
    local name = text:match(NOT_FOUND)
    local full = name and ns.FullName(name)
    local key = full and Conv.KeyOf(full)
    if key and hideUntil[key] and GetTime() < hideUntil[key] then return true end
    return false
end

---------------------------------------------------------------------------
-- Freundesliste, Gilde, Battle.net
---------------------------------------------------------------------------

-- Wartende Nachrichten an Charaktere zustellen, die jetzt online sind.
local function DeliverOnline()
    if not ns.C then return end
    for _, key in ipairs(Conv.QueuedKeys()) do
        local convo = ns.C.convos[key]
        if convo and not convo.bn and Delivery.IsOnline(convo) == true then Delivery.Try(key) end
    end
end

-- Gilde, Battle.net und Freundesliste: ezCore liest die Kontakte gesammelt neu (höchstens alle 0,5 s, auch
-- wenn Blizzard GUILD_ROSTER_UPDATE mehrmals je Sekunde meldet) und meldet danach CONTACTS_CHANGED.
ezCore.Listen("CONTACTS_CHANGED", function() DeliverOnline() end, "ezChat")
-- WoW-Freunde fragt IsOnline direkt bei Blizzard: hier ohne Umweg sofort zustellen.
ns.On("FRIENDLIST_UPDATE", DeliverOnline)

ns.On("BN_FRIEND_ACCOUNT_ONLINE", function(_, accountID)
    local tag = ns.BNTagOf(accountID)
    if tag then Delivery.Online(Conv.KeyOf(tag, true)) end
end)

local function RequestRoster()
    if not (IsInGuild and IsInGuild()) then return end
    lastRoster = GetTime()
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    elseif GuildRoster then
        GuildRoster()
    end
end

local function Tick()
    if not ns.C then return end
    local now = GetTime()
    local expired = false
    for key, p in pairs(pending) do
        if now - p.at > PENDING_TIMEOUT then
            pending[key] = nil
            expired = true
        end
    end
    if expired then PendingChanged() end
    for key, list in pairs(recent) do
        for i = #list, 1, -1 do
            if now - list[i].at > RECENT_WINDOW then table.remove(list, i) end
        end
        if #list == 0 then recent[key] = nil end
    end

    local keys = Conv.QueuedKeys()
    if #keys == 0 then return end
    if now - lastRoster > 120 then RequestRoster() end
    for _, key in ipairs(keys) do
        local convo = ns.C.convos[key]
        local online = Delivery.IsOnline(convo)
        if online == true then
            Delivery.Try(key)
        elseif online == nil and not convo.bn and ns.S.retryWhisper
            and now - (lastTry[key] or 0) >= RETRY_INTERVAL then
            Delivery.Try(key)
        end
    end
end

-- Hinweis am Chatfenster beim Flüstern an andere (ezCores Hinweis-Helfer, einmal je Account; Gesamtreview 18.11.2026,
-- T1-4 und T1-3, Entscheidungen 2 und 3 des Nutzers): „Auch Flüstern aus dem normalen Chat“ schickt ohne Klick nach und
-- ist darum ab Werk aus. Gilt nur mit eingeschalteter Warteschlange; für die beim Update umgestellten
-- (ns.MigrateWhisperOptIn) sagt der Hinweis das dazu. Das Nachsenden aus dem Gesprächsfenster bleibt an: dort wählt der
-- Spieler das Senden an einen Offline-Partner selbst.
function Delivery.RegisterOptInHint()
    local Hint = ezCore.OptInHint
    if not (Hint and Hint.RegisterSetting) then return false end
    return Hint.RegisterSetting("ezChat", ns, "catchChatWhispers", {
        window = "chat",
        applies = function() return ns.S ~= nil and ns.S.offlineQueue == true end,
        switchedOff = function()
            return type(ns.db) == "table" and type(ns.db.migrated) == "table" and ns.db.migrated.whisperOffP17Was == true
        end,
    })
end
Delivery.RegisterOptInHint()

ns.OnReady(function()
    ns.AddMessageEventFilter("CHAT_MSG_SYSTEM", SystemFilter)
    RequestRoster()
    -- Takt mit Griff, Fehler mit Stapel und Ort in ezChats Fehlerliste (ezCores Ticker-Helfer, Gesamtreview 18.11.2026,
    -- T7-3; vorher eigener pcall ohne Stapel)
    Delivery.ticker = ns.Ticker(TICK, Tick, nil, "Delivery.Tick")
end)
