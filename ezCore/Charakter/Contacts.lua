local _, ns = ...
local Core = ezCore

--[[
    Kontakte und Twinks der Battle.net-Freunde – vorher je ein eigener Speicher in ezChat (Delivery.lua)
    und ezSocial (Core.lua, Friends.lua).

    Kontakt-Index über Core.ForEachContact (Freunde, Battle.net-Freunde in diesem Spiel, Gilde):
      Core.Contact(name)        → { full, online, source, sources, bnLabel, class, level, zone, from, lastOnline,
                                    lastSeen } oder nil (nur lesen)
      Core.ContactSource(name)  → "friend" | "bnet" | "guild" oder nil
    Steht ein Name in mehreren Listen, gilt die erste Quelle (Freund vor Battle.net vor Gilde), alle stehen in
    sources; online gewinnt: ist er in einer Liste online, ist er online, Stufe, Klasse und Gebiet kommen dann
    von dort. Welle 23c (A49): Stufe 0 und ein leeres oder „Unbekannt“ genanntes Gebiet (Blizzards UNKNOWN – so meldet
    die Freundesliste einen Freund, der offline ist) gelten als unbekannt; dann füllt die nächste Liste (meist die
    Gilde) die Angabe. from = { class, level, zone } nennt je Angabe die Liste, aus der sie stammt ("friend" | "bnet" |
    "guild"). Welle 23c (A48): Gildenmitglieder, die offline sind, tragen lastOnline = { years, months, days, hours }
    (GetGuildRosterLastOnline, Zeit seit dem letzten Login) und lastSeen = ungefährer Zeitpunkt (Core.Now() minus
    diese Zeit; Monat = Contacts.MONTH_DAYS Tage, Jahr = 365 Tage). Kontakt-Ereignisse markieren den Index als veraltet. Neu gebaut wird beim nächsten Zugriff,
    höchstens alle 0,5 s; hört ein Modul auf CONTACTS_CHANGED, baut ezCore spätestens 0,5 s nach dem Ereignis
    neu und meldet danach CONTACTS_CHANGED (ohne Werte).

    Twinks der Battle.net-Freunde: jeder Charakter, mit dem ein Freund in diesem Spiel online war, in
    ezCoreDB.bnAlts[BattleTag][voller Name] = { c = Klasse, l = Stufe, t = zuletzt gesehen } (für alle eigenen
    Charaktere), höchstens 12 je Freund, nach 180 Tagen ohne Sichtung weg. Erfasst beim Anmelden und bei
    Battle.net-Änderungen; einmalige Übernahme aus ezSocialDB.alts (die alten Daten bleiben liegen).
      Core.BNAlts(tag, except)  → { { name, class, level, seen } … } zuletzt gesehen zuerst
      Core.ForgetBNAlts(tag)    → true, wenn etwas vergessen wurde (ohne tag: alle)
]]

local Contacts = {}
Core.Contacts = Contacts

Contacts.INTERVAL = 0.5    -- Sekunden zwischen zwei Neubauten
Contacts.EVENTS = { "FRIENDLIST_UPDATE", "GUILD_ROSTER_UPDATE", "BN_FRIEND_LIST_SIZE_CHANGED", "BN_FRIEND_INFO_CHANGED",
    "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE", "PLAYER_GUILD_UPDATE" }
Contacts.MAX_ALTS = 12
Contacts.ALT_DAYS = 180

local DAY = 86400
local MESSAGE = "CONTACTS_CHANGED"
Contacts.MONTH_DAYS = 30
-- Erweiterungen des Eintrags (Welle 23c), prüfbar über needs bzw. Core.Has
Core.FEATURES.contactFrom = true        -- from = { class, level, zone } und Stufe 0/„Unbekannt“ als unbekannt (A49)
Core.FEATURES.contactLastOnline = true  -- lastOnline, lastSeen für Gildenmitglieder (A48)

local Now = Core.Uptime      -- Laufzeit der Sitzung (Fristen), nicht die Uhrzeit

---------------------------------------------------------------------------
-- Kontakt-Index
---------------------------------------------------------------------------

local index = {}            -- [voller Name klein] = Eintrag
local stale = true          -- veraltet: beim nächsten Zugriff neu bauen
local lastBuild             -- GetTime() des letzten Neubaus (nil = noch nie, oder nach dem Anmelden)
local unannounced = false   -- neu gebaut, CONTACTS_CHANGED steht noch aus
local builds = 0
local Settle

-- Welle 23c (A49): Stufe 0 und ein leeres bzw. „Unbekannt“ genanntes Gebiet sind keine Angabe.
function Contacts.Known(level, zone)
    level = Core.Num(level)
    if level and level <= 0 then level = nil end
    zone = Core.Plain(zone)
    if type(zone) ~= "string" or zone == "" then
        zone = nil
    else
        local unknown = Core.Plain(rawget(_G, "UNKNOWN"))
        if (type(unknown) == "string" and zone == unknown) or zone == "Unknown" or zone == "Unbekannt" then zone = nil end
    end
    return level, zone
end

-- Angabe übernehmen und ihre Liste merken: force = die Liste, in der er online ist, gewinnt
local function Take(e, field, value, source, force)
    if value == nil then return end
    if force or e[field] == nil then
        e[field] = value
        e.from[field] = source
    end
end

-- Welle 23c (A48): „zuletzt online“ der Gildenmitglieder, die offline sind (GetGuildRosterLastOnline je Zeile).
local function GuildLastOnline(fresh)
    local inGuild = Core.Bool(Core.Call(rawget(_G, "IsInGuild")), false)
    local lastOnline = rawget(_G, "GetGuildRosterLastOnline")
    if not inGuild or type(lastOnline) ~= "function" then return end
    local now = Core.Now()
    for i = 1, Core.Num(Core.Call(rawget(_G, "GetNumGuildMembers"))) or 0 do
        local name, _, _, _, _, _, _, _, isOnline = Core.Call(rawget(_G, "GetGuildRosterInfo"), i)
        local full = type(name) == "string" and Core.Usable(name, isOnline) and Core.FullName(name) or nil
        local e = full and fresh[full:lower()]
        if e and not e.online and Core.Bool(isOnline, false) == false then
            local years, months, days, hours = Core.Call(lastOnline, i)
            years, months, days, hours = Core.Num(years), Core.Num(months), Core.Num(days), Core.Num(hours)
            if years or months or days or hours then
                e.lastOnline = { years = years or 0, months = months or 0, days = days or 0, hours = hours or 0 }
                local ago = ((years or 0) * 365 + (months or 0) * Contacts.MONTH_DAYS + (days or 0)) * DAY
                    + (hours or 0) * 3600
                if now > 0 then e.lastSeen = now - ago end
            end
        end
    end
end

-- Alle Kontakte neu lesen (intern; Module fragen Core.Contact).
function Contacts.Rebuild()
    local fresh = {}
    Core.ForEachContact(function(full, online, source, bnLabel, class, level, zone)
        local key = full:lower()
        local e = fresh[key]
        level, zone = Contacts.Known(level, zone)
        if not e then
            e = { full = full, online = online == true, source = source, sources = { [source] = true },
                bnLabel = bnLabel, from = {} }
            fresh[key] = e
            Take(e, "class", class, source)
            Take(e, "level", level, source)
            Take(e, "zone", zone, source)
            return
        end
        e.sources[source] = true
        e.bnLabel = e.bnLabel or bnLabel
        if online == true and not e.online then
            -- online gewinnt (Gilde und Battle.net zugleich): die Angaben der Liste, in der er online ist
            e.online, e.full = true, full
            Take(e, "class", class, source, true)
            Take(e, "level", level, source, true)
            Take(e, "zone", zone, source, true)
        else
            Take(e, "class", class, source)
            Take(e, "level", level, source)
            Take(e, "zone", zone, source)
        end
    end)
    GuildLastOnline(fresh)
    index, stale, lastBuild = fresh, false, Now()
    builds = builds + 1
    unannounced = true
    return fresh
end

-- Ist der letzte Neubau mindestens INTERVAL her?
local function MayBuild()
    return lastBuild == nil or Now() - lastBuild >= Contacts.INTERVAL
end

local function Index()
    if stale and MayBuild() then
        Contacts.Rebuild()
        Settle()   -- CONTACTS_CHANGED kommt gesammelt nach, nie mitten im Zugriff
    end
    return index
end

-- Spätestens INTERVAL nach einem Ereignis: neu bauen, wenn jemand zuhört, und CONTACTS_CHANGED melden.
Settle = Core.Throttle(function()
    if stale and Core.Listening(MESSAGE) then
        if not MayBuild() then
            Settle()   -- der letzte Neubau ist zu frisch: noch einmal warten
            return
        end
        Contacts.Rebuild()
    end
    if unannounced then
        unannounced = false
        Core.Fire(MESSAGE)
    end
end, Contacts.INTERVAL, Core.name)

-- Kontakt-Ereignis: Index veraltet (intern; ezCore hört selbst auf Contacts.EVENTS).
function Contacts.Invalidate()
    stale = true
    Settle()
end

-- Veraltet?, Anzahl der Neubauten, Zeitpunkt des letzten. ezSocial nutzt das im Betrieb (verlangt es über needs);
-- dazu Tests und /dump.
function Contacts.State()
    return stale, builds, lastBuild
end

-- Bekannter Spieler (Freund, Battle.net-Freund in diesem Spiel, Gilde) oder nil; Groß/Klein egal.
-- Der Eintrag gehört ezCore: nur lesen.
function Core.Contact(name)
    local full = Core.FullName(name)
    if not full then return nil end
    return Index()[full:lower()]
end

-- Quelle eines bekannten Spielers: "friend", "bnet" oder "guild", sonst nil.
function Core.ContactSource(name)
    local contact = Core.Contact(name)
    return contact and contact.source or nil
end

--[[
    Namens-Ergänzung „Vorname → voller Name“ (Vollprüfung V-069; vorher ns.CompleteName in ezChat/Core.lua).
    Forever: Fehlt der Nachname („Testa“), wird er ergänzt, wenn GENAU EIN bekannter Charakter diesen Vornamen
    trägt – bekannt sind die Kontakte (Freunde, Battle.net-Freunde in diesem Spiel, Gilde) und alles aus extra.

      Core.CompleteName(name, extra) → voller Name, ergänzt? (true/false)
        extra = Liste von Namen, Menge { [Name] = true } oder fn(consider), die consider(name) je Kandidat ruft
                (z. B. ezChats Gespräche). Kein oder mehrere Treffer: der Name bleibt, wie er war.
      Core.FirstName(full)           → Vorname eines vollen Namens (ohne Nachnamen-Trennzeichen: der Name selbst)
    Ohne Forever-Namen (Core.uniqueNames aus) und bei gesperrten Namen kommt der Name unverändert zurück.
]]
function Core.FirstName(full)
    if Core.IsSecret(full) or type(full) ~= "string" then return nil end
    local at = full:find(Core.surnameSep or " ", 1, true)
    if not at or at <= 1 then return full end
    return full:sub(1, at - 1)
end

-- Vornamen-Verzeichnis der Kontakte: einmal je Neubau des Index, nicht je Aufruf (V-071: je Freundeszeile gefragt).
local firstNames, firstNamesBuild
local function FirstNames()
    local contacts = Index()
    if firstNames and firstNamesBuild == builds then return firstNames end
    firstNames, firstNamesBuild = {}, builds
    for _, e in pairs(contacts) do
        local full = type(e) == "table" and e.full
        if type(full) == "string" and not Core.MissingSurname(full) then
            local first = Core.FirstName(full):lower()
            firstNames[first] = firstNames[first] or {}
            firstNames[first][full:lower()] = full
        end
    end
    return firstNames
end

function Core.CompleteName(full, extra)
    if Core.IsSecret(full) or not Core.MissingSurname(full) then return full, false, 0 end
    local wanted = full:lower()
    local matches = {}
    local function Consider(candidate)
        if Core.IsSecret(candidate) or type(candidate) ~= "string" or Core.MissingSurname(candidate) then return end
        if Core.FirstName(candidate):lower() == wanted then
            local key = candidate:lower()
            matches[key] = matches[key] or candidate   -- derselbe Name in anderer Schreibweise ist ein Treffer
        end
    end
    for key, candidate in pairs(FirstNames()[wanted] or {}) do matches[key] = candidate end
    if type(extra) == "function" then
        local ok, err = pcall(extra, Consider)
        if not ok then Core.Error(Core.name, err, "CompleteName") end
    elseif type(extra) == "table" then
        for key, value in pairs(extra) do
            Consider(type(key) == "string" and key or value)
        end
    end
    local only, count = nil, 0
    for _, candidate in pairs(matches) do only, count = candidate, count + 1 end
    if count == 1 then return only, true, 1 end
    return full, false, count
end

-- Wie viele Kontakte (Freunde, Battle.net, Gilde) tragen diesen Vornamen? 0 = keiner, 1 = eindeutig, mehr =
-- mehrdeutig (SOCIAL-03: Core.CompleteName sagte nicht, warum es nichts ergänzt; ezSocial zählte selbst nach).
-- Groß- und Kleinschreibung egal; ein Name mit Nachnamen zählt über seinen Vornamen. extra wie bei Core.CompleteName.
function Contacts.FirstNameCount(first, extra)
    if Core.IsSecret(first) or type(first) ~= "string" or first == "" then return 0 end
    local _, _, count = Core.CompleteName(Core.FirstName(first), extra)
    return count or 0
end

for _, event in ipairs(Contacts.EVENTS) do
    ns.On(event, Contacts.Invalidate)
end

-- Erst nach dem Anmelden stimmen die vollen Namen (Core.InitIdentity in Characters.lua läuft vorher).
ns.On("PLAYER_LOGIN", function()
    lastBuild = nil
    Contacts.Invalidate()
end)

---------------------------------------------------------------------------
-- Twinks der Battle.net-Freunde
---------------------------------------------------------------------------

local function AltStore()
    local db = Core.db
    if type(db) ~= "table" then return nil end
    if type(db.bnAlts) ~= "table" then db.bnAlts = {} end
    return db.bnAlts
end

-- Schlüssel desselben Charakters (Groß/Klein egal) oder nil.
local function SameKey(alts, name)
    if alts[name] ~= nil then return name end
    local lower = name:lower()
    for key in pairs(alts) do
        if type(key) == "string" and key:lower() == lower then return key end
    end
    return nil
end

-- Eintrag unter name ablegen bzw. mit dem vorhandenen zusammenführen: die neuere Sichtung gewinnt,
-- fehlende Klasse oder Stufe kommt aus der älteren.
local function Put(alts, name, class, level, seen)
    local key = SameKey(alts, name)
    local e = key and alts[key]
    if key then alts[key] = nil end
    if type(e) ~= "table" then
        e = { c = class, l = level, t = seen }
    elseif (seen or 0) >= (tonumber(e.t) or 0) then
        e.c, e.l, e.t = class or e.c, level or e.l, seen
    else
        e.c, e.l = e.c or class, e.l or level
    end
    alts[name] = e
end

-- Forever: ezSocial merkte Twinks mit dem Namen aus Blizzards Freundesliste, womöglich nur dem Vornamen.
-- Kommt derselbe Charakter mit vollem Namen, ersetzt dieser den alten Eintrag (sonst stünde er doppelt da).
local function AdoptFirstName(alts, full)
    if not Core.uniqueNames then return end
    local first = full:match("^(.-)" .. Core.EscapePattern(Core.surnameSep or " "))
    if not first or first == "" then return end
    local key = SameKey(alts, first)
    if not key then return end
    local old = alts[key]
    alts[key] = nil
    if type(old) == "table" then Put(alts, full, old.c, old.l, tonumber(old.t)) end
end

-- Höchstens MAX_ALTS je Freund, nichts älter als ALT_DAYS; leere Freunde fallen weg.
local function PruneTag(store, tag, now)
    local alts = store[tag]
    if type(alts) ~= "table" then
        store[tag] = nil
        return
    end
    local limit = now - Contacts.ALT_DAYS * DAY
    local names = {}
    for name, e in pairs(alts) do
        if type(name) ~= "string" or type(e) ~= "table" or (tonumber(e.t) or 0) < limit then
            alts[name] = nil
        else
            names[#names + 1] = name
        end
    end
    if #names > Contacts.MAX_ALTS then
        table.sort(names, function(a, b)
            local ta, tb = tonumber(alts[a].t) or 0, tonumber(alts[b].t) or 0
            if ta ~= tb then return ta > tb end
            return a < b
        end)
        for i = Contacts.MAX_ALTS + 1, #names do alts[names[i]] = nil end
    end
    if next(alts) == nil then store[tag] = nil end
end

-- Alle Freunde aufräumen (intern: beim Anmelden).
function Contacts.PruneAlts(now)
    local store = AltStore()
    if not store then return end
    now = now or time()
    local tags = {}
    for tag in pairs(store) do tags[#tags + 1] = tag end
    for _, tag in ipairs(tags) do PruneTag(store, tag, now) end
end

-- Online-Charaktere aller Battle.net-Freunde merken (intern). Rückgabe: Anzahl gemerkter Charaktere.
function Contacts.RememberAlts(now)
    local store = AltStore()
    if not store then return 0 end
    now = now or time()
    local count = 0
    for _, friend in ipairs(Core.BNFriends()) do
        local full = friend.character
        if full and friend.tag then
            local game = type(friend.info) == "table" and Core.Plain(friend.info.gameAccountInfo)
            if type(game) ~= "table" then game = {} end
            local class = Core.ClassOfGUID(game.playerGuid) or Core.ClassToken(game.className)
            local alts = store[friend.tag] or {}
            store[friend.tag] = alts
            AdoptFirstName(alts, full)
            Put(alts, full, class, Core.Num(game.characterLevel), now)
            PruneTag(store, friend.tag, now)
            count = count + 1
        end
    end
    return count
end

-- Einmalige Übernahme aus ezSocialDB.alts[BattleTag][Name] = { c, l, t } (intern; die alten Daten bleiben).
-- Rückgabe: Anzahl übernommener Einträge.
function Contacts.MigrateAlts()
    local db = Core.db
    local done = type(db) == "table" and db.migrated
    local social = rawget(_G, "ezSocialDB")
    if type(done) ~= "table" or done.ezSocialAlts or type(social) ~= "table" or type(social.alts) ~= "table" then
        return 0
    end
    local store = AltStore()
    local count = 0
    for tag, list in pairs(social.alts) do
        if type(tag) == "string" and tag ~= "" and type(list) == "table" then
            local alts = store[tag] or {}
            store[tag] = alts
            for name, e in pairs(list) do
                local full = type(e) == "table" and Core.FullName(name)
                if full then
                    Put(alts, full, Core.Plain(e.c), Core.Num(e.l), Core.Num(e.t))
                    count = count + 1
                end
            end
            if next(alts) == nil then store[tag] = nil end
        end
    end
    done.ezSocialAlts = true
    return count
end

-- Twinks eines Battle.net-Freundes (BattleTag), zuletzt gesehene zuerst: { { name, class, level, seen } … }.
-- except (voller Name, z. B. Core.BNCharacter(info)) lässt den gerade gespielten weg.
function Core.BNAlts(tag, except)
    local list = {}
    if Core.IsSecret(tag) or type(tag) ~= "string" then return list end
    local store = AltStore()
    local alts = store and store[tag]
    if type(alts) ~= "table" then return list end
    local skip = Core.FullName(except)
    skip = skip and skip:lower()
    local limit = time() - Contacts.ALT_DAYS * DAY
    for name, e in pairs(alts) do
        local seen = type(e) == "table" and tonumber(e.t)
        if type(name) == "string" and seen and seen >= limit and name:lower() ~= skip then
            list[#list + 1] = { name = name, class = e.c, level = e.l, seen = seen }
        end
    end
    table.sort(list, function(a, b)
        if a.seen ~= b.seen then return a.seen > b.seen end
        return a.name < b.name
    end)
    return list
end

-- Gemerkte Twinks vergessen: eines Freundes (BattleTag) oder ohne tag alle. true, wenn etwas wegfiel.
function Core.ForgetBNAlts(tag)
    if Core.IsSecret(tag) then return false end
    local store = AltStore()
    if not store then return false end
    if tag == nil then
        local had = next(store) ~= nil
        wipe(store)
        return had
    end
    if store[tag] == nil then return false end
    store[tag] = nil
    return true
end

local RememberSoon = Core.Throttle(function() Contacts.RememberAlts() end, 1, Core.name)

ns.On("PLAYER_LOGIN", function()
    Contacts.MigrateAlts()
    Contacts.PruneAlts()
    RememberSoon()
end)

for _, event in ipairs({ "BN_FRIEND_INFO_CHANGED", "BN_FRIEND_ACCOUNT_ONLINE", "BN_CONNECTED" }) do
    ns.On(event, RememberSoon)
end
