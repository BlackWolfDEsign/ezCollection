local _, ns = ...
local Core = ezCore

--[[
    Gruppen-Nachrichten aus dem Chat: LFG („suche Gruppe“) und LFM („suchen noch Heiler“) aus Handel,
    Suche nach Gruppe, Welt und auf Wunsch Allgemein. Je Absender bleibt die neueste Nachricht, ältere als
    „chatMaxAge“ Minuten fallen weg. Gespeichert in ezSocialDB.chat (übersteht /reload).
    Dazu merkt sich ezSocialDB.chat.seenAt, wann der Reiter „Aus dem Chat“ zuletzt offen war: Was danach kam und
    einen Dungeon für die eigene Stufe nennt, zählt als „neu“ (Chat.Unseen) – für ezPanels Meldungen und den
    Baustein „Gruppen-Nachrichten“ (Panel.lua). Zeigt der Reiter mit einem Filter nur einen Teil der Liste, gilt
    nur dieser Teil als gesehen (Vermerk v an der Nachricht, Chat.MarkShown).
    Dungeons erkennt ezCore.Dungeons (MatchAll, Kürzel deutsch und englisch) – ezSocial hat keine eigene Liste.
    Die Kanäle erkennt ezCore ebenso (Core.ChannelKind).
    Geheime Werte (Chat-Sperre in bestimmten Kämpfen) werden übersprungen.
]]

local Chat = {}
ns.Chat = Chat

Chat.MAX_ENTRIES = 100

---------------------------------------------------------------------------
-- Kanäle
---------------------------------------------------------------------------

-- Welcher Kanal was ist, weiß ezCore an einer Stelle (Core.ChannelKind: Blizzards feste Nummern
-- Core.ZONE_CHANNELS, Namen deutsch und englisch Core.CHANNEL_KINDS). ezSocial bildet die Art nur auf
-- seine Einstellungen ab.
Chat.SETTING_OF_KIND = { general = "chatGeneral", trade = "chatTrade", lfg = "chatLFG", world = "chatWorld" }

-- Einstellungs-Schlüssel des Kanals (chatTrade, chatLFG, chatWorld, chatGeneral) oder nil.
function Chat.ChannelKey(zoneChannelID, baseName, channelName)
    local kind = Core.ChannelKind(zoneChannelID, baseName, channelName)
    return kind and Chat.SETTING_OF_KIND[kind] or nil
end

---------------------------------------------------------------------------
-- Erkennen: LFG oder LFM? (deutsch und englisch, Wortgrenzen mit %f)
---------------------------------------------------------------------------

local ROLE_WORDS = {
    tank = "tank", tanks = "tank",
    heal = "healer", heals = "healer", healer = "healer", heiler = "healer", heala = "healer",
    dps = "dps", dd = "dps", damage = "dps", schaden = "dps",
}

local EXCLUDE = {
    "%f[%w]gilde", "%f[%w]guild", "recruit", "rekrut",
    "%f[%w]wt[sbt]%f[%W]", "%f[%w]verkaufe", "%f[%w]kaufe%f[%W]",
    "%f[%w]lf%s+work", "%f[%w]lf%s+ench", "%f[%w]lf%s+craft", "%f[%w]lf%s+summon", "%f[%w]boost",
}

local LFM = {
    "%f[%w]lf%d*m%f[%W]",                    -- lfm, lf1m, lf2m
    "%f[%w]lf%s*%d+%s*m%f[%W]",              -- lf 2m, lf 2 m
    "%f[%w]lf%s*%d*%s*more%f[%W]",           -- lf more, lf1 more
    "%f[%w]looking%s+for%s+more%f[%W]",
    "%f[%w]suchen%s+noch%f[%W]", "%f[%w]sucht%s+noch%f[%W]", "%f[%w]brauchen%s+noch%f[%W]",
}
local LFM_ROLE = {                           -- mit einer Rolle dahinter („need heal“, „suche tank“)
    "%f[%w]need%s+%d*%s*", "%f[%w]lf%s+%d*%s*", "%f[%w]suchen?%s+%d*%s*", "%f[%w]suchen?%s+noch%s+%d*%s*",
    "%f[%w]brauchen?%s+%d*%s*", "%f[%w]brauchen?%s+noch%s+%d*%s*",
}
local LFG = {
    "%f[%w]lfg%f[%W]",
    "%f[%w]looking%s+for%s+a?%s*group%f[%W]",
    "%f[%w]lf%s+gro?u?p%f[%W]",
    "%f[%w]suche%s+eine?%s+gruppe", "%f[%w]suche%s+gruppe", "%f[%w]suche%s+grp%f[%W]", "%f[%w]sucht%s+gruppe",
}

-- Text vereinfachen: Links und Farben weg, klein, einfache Leerzeichen.
function Chat.Normalize(text)
    if type(text) ~= "string" then return "" end
    text = Core.PlainText(text):lower():gsub("%s+", " ")
    return " " .. text .. " "
end

local function AnyMatch(text, patterns, suffix)
    for _, pattern in ipairs(patterns) do
        if text:find(pattern .. (suffix or "")) then return true end
    end
    return false
end

-- Schneller Vorfilter: Handel ist voll Plauderei, nur Zeilen mit einem dieser Wortteile werden genau geprüft.
local HINTS = { "lf", "such", "need", "brauch", "looking" }

local function MayBeGroup(t)
    for _, hint in ipairs(HINTS) do
        if t:find(hint, 1, true) then return true end
    end
    return false
end

-- "lfm", "lfg" oder nil.
function Chat.Classify(text)
    if type(text) ~= "string" or Core.IsSecret(text) then return nil end
    local t = Chat.Normalize(text)
    if not MayBeGroup(t) or AnyMatch(t, EXCLUDE) then return nil end
    if AnyMatch(t, LFM) then return "lfm" end
    for word in pairs(ROLE_WORDS) do
        if AnyMatch(t, LFM_ROLE, word .. "%f[%W]") then return "lfm" end
    end
    if AnyMatch(t, LFG) then return "lfg" end
    return nil
end

-- Genannte Rollen: { tank = true, healer = true, dps = true } (bei LFM gesucht, bei LFG angeboten).
function Chat.Roles(text)
    local roles = {}
    if type(text) ~= "string" or Core.IsSecret(text) then return roles end
    local t = Chat.Normalize(text)
    for word, role in pairs(ROLE_WORDS) do
        if t:find("%f[%w]" .. word .. "%f[%W]") then roles[role] = true end
    end
    return roles
end

---------------------------------------------------------------------------
-- Dungeons (aus ezCore.Dungeons; ezCore ist Pflicht, die Tabelle ist immer da)
---------------------------------------------------------------------------

-- Kennungen (key) aller Dungeons, die eine Zeile nennt – über ezCore.Dungeons.MatchAll (Kürzel de/en).
function Chat.MatchDungeons(text)
    local ok, list = pcall(Core.Dungeons.MatchAll, text)
    if not ok or type(list) ~= "table" then return nil end
    local keys = {}
    for _, d in ipairs(list) do
        local key = type(d) == "table" and d.key or d
        if key ~= nil then keys[#keys + 1] = key end
    end
    return #keys > 0 and keys or nil
end

-- Eintrag der Dungeon-Tabelle ({ key, name, minLevel, maxLevel, … }) zu einer Kennung, sonst nil.
function Chat.DungeonInfo(key)
    if key == nil then return nil end
    local ok, d = pcall(Core.Dungeons.Get, key)
    if ok and type(d) == "table" then return d end
    return nil
end

-- Dungeons einer Nachricht; nach DUNGEONS_CHANGED (Tabelle neu gelesen) werden sie beim Lesen neu zugeordnet.
function Chat.DungeonsOf(entry)
    if entry.d == nil then entry.d = Chat.MatchDungeons(entry.m) or false end
    return entry.d or nil
end

---------------------------------------------------------------------------
-- Sammeln
---------------------------------------------------------------------------

local function List()
    if not ns.db then return {} end
    ns.db.chat.entries = type(ns.db.chat.entries) == "table" and ns.db.chat.entries or {}
    return ns.db.chat.entries
end
Chat.List = List

local function Changed() ns.Fire("LFG_CHAT_CHANGED") end

-- Zu alte Einträge entfernen. Rückgabe: Anzahl entfernter.
function Chat.Prune(now)
    local list = List()
    local maxAge = (Core.Num(ns.S and ns.S.chatMaxAge) or 15) * 60
    now = now or time()
    local removed = 0
    for i = #list, 1, -1 do
        local t = Core.Num(list[i].t)
        if not t or now - t > maxAge then
            table.remove(list, i)
            removed = removed + 1
        end
    end
    return removed
end

-- Neue Nachricht prüfen und aufnehmen. Rückgabe: der Eintrag oder nil.
function Chat.Add(sender, text, guid, channelKey, now)
    if not ns.Enabled("chatTab") then return nil end
    if not Core.Usable(sender, text, guid) or type(text) ~= "string" then return nil end
    if channelKey and not ns.Enabled(channelKey) then return nil end
    local full = Core.FullName(sender)
    if not full or Core.IsSelf(full) then return nil end
    local kind = Chat.Classify(text)
    if not kind then return nil end

    local list = List()
    for i = #list, 1, -1 do
        if list[i].s == full then table.remove(list, i) end
    end
    local plain = Core.Trim(Core.PlainText(text))
    local entry = {
        t = now or time(), s = full, c = Core.ClassOfGUID(guid), m = plain, k = kind,
        r = Chat.Roles(text), ch = channelKey, d = Chat.MatchDungeons(plain),
    }
    table.insert(list, 1, entry)
    for i = #list, Chat.MAX_ENTRIES + 1, -1 do list[i] = nil end
    Chat.Prune(now)
    Changed()
    return entry
end

function Chat.Clear()
    wipe(List())
    Changed()
end

-- Kopien für andere Module, neueste zuerst.
function Chat.Entries()
    local out = {}
    for _, e in ipairs(List()) do
        local roles = {}
        for k, v in pairs(e.r or {}) do roles[k] = v end
        local dungeons = {}
        for _, key in ipairs(Chat.DungeonsOf(e) or {}) do dungeons[#dungeons + 1] = key end
        out[#out + 1] = { time = e.t, sender = e.s, class = e.c, text = e.m, kind = e.k, roles = roles,
            dungeons = dungeons, channel = e.ch }
    end
    return out
end

---------------------------------------------------------------------------
-- Neu seit dem letzten Öffnen des Reiters, passend zur Stufe (für ezPanel, Panel.lua)
---------------------------------------------------------------------------

-- Zeitpunkt, bis zu dem der Spieler die Liste gesehen hat (0: der Reiter war noch nie offen).
function Chat.SeenAt()
    return ns.db and Core.Num(ns.db.chat.seenAt) or 0
end

-- Passt die Nachricht zur Stufe? Ja, wenn sie einen Dungeon nennt, dessen empfohlener Bereich die Stufe enthält
-- (dieselbe Regel wie die weiße Farbe: Core.Dungeons.DifficultyOf). Ohne erkannten Dungeon lässt sich das nicht
-- sagen – solche Nachrichten zählen nicht.
function Chat.FitsLevel(entry, level)
    for _, key in ipairs(Chat.DungeonsOf(entry) or {}) do
        local d = Chat.DungeonInfo(key)
        if d and Core.Dungeons.DifficultyOf(d, level) == "white" then return true end
    end
    return false
end

-- Nachrichten, die seit dem letzten Öffnen des Reiters kamen, noch nicht zu alt sind und zur Stufe passen
-- (Standard: die eigene); neueste zuerst. Nur lesen – entfernt wird hier nichts.
function Chat.Unseen(level, now)
    local out = {}
    now = now or time()
    local seenAt = Chat.SeenAt()
    local maxAge = (Core.Num(ns.S and ns.S.chatMaxAge) or 15) * 60
    level = level or Core.PlayerLevel() or 1     -- eigene Stufe aus ezCore; 1, solange der Client sie nicht kennt
    for _, e in ipairs(List()) do
        local t = Core.Num(e.t)
        if t and t > seenAt and not e.v and now - t <= maxAge and Chat.FitsLevel(e, level) then out[#out + 1] = e end
    end
    return out
end

-- Der Spieler hat die ganze Liste gesehen (Reiter ohne Filter geöffnet, offen oder geschlossen). Gab es
-- Ungesehenes, erfahren es die Zuhörer von LFG_SEEN_CHANGED (Panel.lua). → true, wenn es Ungesehenes gab.
function Chat.MarkSeen(now)
    if not ns.db then return false end
    now = now or time()
    local seenAt, had = Chat.SeenAt(), false
    for _, e in ipairs(List()) do
        local t = Core.Num(e.t)
        if t and t > seenAt and not e.v then had = true break end
    end
    ns.db.chat.seenAt = now
    if had then ns.Fire("LFG_SEEN_CHANGED") end
    return had
end

-- Der Spieler hat nur diese Nachrichten gesehen (der Reiter zeigt mit dem Filter „Zeigen“ oder einem Suchtext
-- einen Teil der Liste): Jede bekommt den Vermerk „gesehen“ (Feld v), der Zeitpunkt seenAt bleibt – was der
-- Filter ausblendet, zählt weiter als neu. → true, wenn Ungesehenes dabei war (dann LFG_SEEN_CHANGED).
function Chat.MarkShown(entries)
    if not ns.db then return false end
    local seenAt, had = Chat.SeenAt(), false
    for _, e in ipairs(type(entries) == "table" and entries or {}) do
        local t = type(e) == "table" and Core.Num(e.t) or nil
        if t and t > seenAt and not e.v then
            e.v = true
            had = true
        end
    end
    if had then ns.Fire("LFG_SEEN_CHANGED") end
    return had
end

---------------------------------------------------------------------------
-- Anzeige-Hilfen für den Reiter: filtern und nach Dungeon gruppieren
---------------------------------------------------------------------------

-- kind: nil (alle), "lfm" oder "lfg"; search: Text in Absender, Nachricht oder Dungeon-Namen.
function Chat.Filter(kind, search)
    local out = {}
    search = type(search) == "string" and Core.Trim(search):lower() or ""
    for _, e in ipairs(List()) do
        local keep = kind == nil or e.k == kind
        if keep and search ~= "" then
            keep = (e.m or ""):lower():find(search, 1, true) ~= nil or (e.s or ""):lower():find(search, 1, true) ~= nil
            if not keep then
                for _, key in ipairs(Chat.DungeonsOf(e) or {}) do
                    local d = Chat.DungeonInfo(key)
                    if d and type(d.name) == "string" and d.name:lower():find(search, 1, true) then keep = true break end
                end
            end
        end
        if keep then out[#out + 1] = e end
    end
    return out
end

-- Gruppen { key, name, minLevel, maxLevel, entries }: Dungeons nach Stufe, „Sonstige“ (key false) zuletzt.
-- Eine Nachricht mit zwei Dungeons steht in beiden Gruppen.
function Chat.Group(entries)
    local groups, byKey = {}, {}
    local function GroupFor(key)
        local g = byKey[key]
        if g then return g end
        local d = key and Chat.DungeonInfo(key) or nil
        g = { key = key, name = d and d.name or nil, minLevel = d and Core.Num(d.minLevel) or nil,
            maxLevel = d and Core.Num(d.maxLevel) or nil, entries = {} }
        byKey[key] = g
        groups[#groups + 1] = g
        return g
    end
    for _, e in ipairs(entries) do
        local keys = Chat.DungeonsOf(e)
        if keys and #keys > 0 then
            for _, key in ipairs(keys) do table.insert(GroupFor(key).entries, e) end
        else
            table.insert(GroupFor(false).entries, e)
        end
    end
    table.sort(groups, function(a, b)
        if (a.key == false) ~= (b.key == false) then return b.key == false end
        local la, lb = a.minLevel or 999, b.minLevel or 999
        if la ~= lb then return la < lb end
        return tostring(a.name or a.key) < tostring(b.name or b.key)
    end)
    return groups
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------

ns.On("CHAT_MSG_CHANNEL", function(_, text, sender, _, channelName, _, _, zoneChannelID, _, baseName, _, _, guid)
    if not ns.Enabled("chatTab") then return end
    if not Core.Usable(text, sender, channelName, zoneChannelID, baseName) then return end
    local key = Chat.ChannelKey(zoneChannelID, baseName, channelName)
    if not key then return end
    Chat.Add(sender, text, guid, key)
end)

ns.OnReady(function()
    if Chat.Prune() > 0 then Changed() end
end)

-- Hat die Gruppensuche neue Dungeons geliefert (Namen in Client-Sprache, neue Forever-Dungeons),
-- werden die gesammelten Nachrichten beim nächsten Lesen neu zugeordnet.
Core.Listen("DUNGEONS_CHANGED", function()
    for _, e in ipairs(List()) do e.d = nil end
    Changed()
end, "ezSocial")

ns.OnSettingChanged(function(key)
    if key == "chatMaxAge" then
        Chat.Prune()
        Changed()
    elseif key == "chatTab" and not ns.Enabled("chatTab") then
        Chat.Clear()
    end
end)
