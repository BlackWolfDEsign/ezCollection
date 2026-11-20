local _, ns = ...
local L = ns.L
local Conv = ns.Conv

-- Spam-Filter für Flüstern (Wunsch des Nutzers vom 15.11.2026: „Ja, einplanen“; eigener Code, Leitlinie 10).
-- Gefiltertes geht nie verloren: es steht still im Bereich „Gefiltert“ der Gesprächsliste
-- (ns.C.filtered, höchstens 100 Nachrichten), mit Zähler und „Doch zeigen“.
--
-- Geprüft wird nur Flüstern von Fremden. Nie gefiltert: Freunde, Battle.net, Gilde (ezCore.ContactSource), die
-- eigene Gruppe, Partner, denen du selbst schon geschrieben hast, und wen du über „Doch zeigen“ freigegeben hast.
-- Regeln (je eine Einstellung, ns.S):
--   spamWords  Stichwörter und Muster: jedes Stichwort zählt einen Punkt, eine Internetadresse zwei; ab zwei
--              Punkten gilt die Nachricht als Spam (ein „gold“ allein filtert nichts)
--   spamLevel  Stufe des Absenders höchstens so hoch (0 = aus) – nur, wenn die Stufe offen lesbar ist (Absender
--              in Reichweite, Leitlinie 6: zuerst ezCore.IsSecret); sonst greift die Regel nicht
--   spamBusy   in Dungeon, Schlachtzug und Kampf nur Freunde, Gilde und Gruppe
-- Ausgeblendet wird über Blizzards Nachrichtenfilter (ezCore.AddMessageEventFilter) – keine Werte in Blizzards
-- Tabellen. Läuft WIM, übernimmt es das Filtern (ns.HANDLED_BY.spamFilter): ezChat filtert dann nicht.

local Spam = {}
ns.Spam = Spam

Spam.KEY = "#filtered"   -- Eintrag „Gefiltert“ in der Gesprächsliste
local MAX_KEPT = 100
local URL_POINTS, LIMIT = 2, 2
-- Internetadressen ohne „http“ und „www.“ (Spam schreibt oft nur „seite.com“); die übrigen kennt ns.Format.HasUrl.
-- Nach der Endung muss das Wort enden (%f[^%w]), sonst wäre „hey.coming“ oder „ok.ruf mich an“ eine Adresse.
local DOMAINS = {}
for _, ending in ipairs({ "com", "net", "org", "ru", "cn", "shop", "store", "top", "xyz" }) do
    DOMAINS[#DOMAINS + 1] = "%w%." .. ending .. "%f[^%w]"
end

---------------------------------------------------------------------------
-- Regeln
---------------------------------------------------------------------------

-- Stichwörter aus der Einstellung, klein geschrieben (Komma oder Semikolon trennt).
function Spam.Words()
    local list = {}
    for word in tostring(ns.S and ns.S.spamWords or ""):gmatch("[^,;]+") do
        word = ns.Trim(word):lower()
        if word ~= "" then list[#list + 1] = word end
    end
    return list
end

-- Enthält der Text eine Internetadresse?
function Spam.HasUrl(plain)
    if ns.Format and ns.Format.HasUrl(plain) then return true end
    for _, pattern in ipairs(DOMAINS) do
        if plain:find(pattern) then return true end
    end
    return false
end

-- Punkte eines Textes: Internetadresse 2, jedes vorkommende Stichwort 1. → Punkte
function Spam.Score(text)
    if type(text) ~= "string" or not ns.Usable(text) then return 0 end
    local plain = ns.PlainText(text):lower()
    local points = Spam.HasUrl(plain) and URL_POINTS or 0
    for _, word in ipairs(Spam.Words()) do
        if plain:find(word, 1, true) then points = points + 1 end
    end
    return points
end

-- Steht der Absender in der eigenen Gruppe?
local function InGroup(full)
    if not ezCore.InGroup() then return false end
    local raid = ezCore.Bool(ezCore.Call(rawget(_G, "IsInRaid")), false)
    local count = ezCore.Num(ezCore.Call(rawget(_G, "GetNumGroupMembers"))) or 0
    local lower = full:lower()
    for i = 1, math.min(count, 40) do
        local name = ezCore.UnitFullName((raid and "raid" or "party") .. i)
        if name and name:lower() == lower then return true end
    end
    return false
end

-- Bekannt: Freund, Battle.net, Gilde, Gruppe, ein Gespräch mit eigener Nachricht oder freigegeben. Die eigene
-- automatische Antwort (msg.a, Situation.lua) zählt nicht: sie hat niemand selbst geschrieben.
function Spam.Known(full)
    if type(full) ~= "string" then return false end
    if ezCore.ContactSource(full) then return true end
    local key = Conv.KeyOf(full)
    if ns.C and ns.C.spamAllow and ns.C.spamAllow[key] then return true end
    local convo = ns.C and ns.C.convos[key]
    if convo then
        for _, msg in ipairs(convo.msgs) do
            if msg.o and not msg.a then return true end
        end
    end
    return InGroup(full)
end

-- Gerade beschäftigt (Kampf, Dungeon, Schlachtzug, Szenario, Schlachtfeld, Arena)? Dieselbe Antwort wie die Lagen
-- „Kampf“ und „Dungeon/Schlachtzug“ (Situation.Current, eine Liste der Instanzarten).
function Spam.Busy()
    local sit = ns.Situation.Current()
    return sit == "combat" or sit == "instance"
end

-- Stufe des Absenders, wenn sie offen lesbar ist (Absender in Reichweite: Ziel, Gruppe, Namensplakette), sonst nil.
function Spam.LevelOf(guid)
    if ns.IsSecret(guid) or type(guid) ~= "string" or guid == "" then return nil end
    local token = ezCore.Call(rawget(_G, "UnitTokenFromGUID"), guid)
    if ns.IsSecret(token) or type(token) ~= "string" or token == "" then return nil end
    local level = ezCore.Call(rawget(_G, "UnitLevel"), token)
    if ns.IsSecret(level) then return nil end
    level = tonumber(level)
    if not level or level <= 0 then return nil end
    return level
end

-- Warum ist dieses Flüstern Spam? "words", "level", "busy" oder nil (kein Spam, Filter aus, Absender bekannt).
-- Dieselbe Antwort für Blizzards Chatfenster (Filter) und für ezChats Mitschrift (Conversations.lua).
-- flags (Argument 6 des Ereignisses): Flüstern von Blizzard-Mitarbeitern („GM“, „DEV“) wird nie gefiltert.
local STAFF = { GM = true, DEV = true }
function Spam.Check(text, sender, guid, flags)
    if not (ns.C and ns.Active("spamFilter")) then return nil end
    if type(text) ~= "string" or type(sender) ~= "string" or not ns.Usable(text, sender) then return nil end
    if not ns.IsSecret(flags) and STAFF[flags] then return nil end
    local full = ns.FullName(sender)
    if not full or ns.IsSelf(full) then return nil end
    full = ns.CompleteName(full)
    if Spam.Known(full) then return nil end
    if ns.S.spamBusy and Spam.Busy() then return "busy" end
    local limit = ns.Number("spamLevel")
    local level = limit > 0 and Spam.LevelOf(guid)
    if level and level <= limit then return "level" end
    if Spam.Score(text) >= LIMIT then return "words" end
    return nil
end

---------------------------------------------------------------------------
-- Bereich „Gefiltert“
---------------------------------------------------------------------------

local function List()
    if not ns.C then return {} end
    ns.C.filtered = ns.C.filtered or {}
    return ns.C.filtered
end
Spam.List = List

-- Gefilterte Nachricht ablegen (still: kein Ton, nicht ungelesen). entry = { t, n = voller Name, m, r = Grund }
function Spam.Keep(full, text, reason)
    local list = List()
    list[#list + 1] = { t = time(), n = full, m = text, r = reason }
    while #list > MAX_KEPT do table.remove(list, 1) end
    ns.C.filteredNew = (ns.C.filteredNew or 0) + 1
    Conv.Changed(Spam.KEY)
end

function Spam.Count() return #List() end
function Spam.NewCount() return ns.C and ns.C.filteredNew or 0 end
function Spam.MarkSeen()
    if ns.C and (ns.C.filteredNew or 0) > 0 then ns.C.filteredNew = 0 end
end

-- Absender mit gefilterten Nachrichten, neueste zuerst: { { name, count, last } … }
function Spam.Senders()
    local byName, order = {}, {}
    for _, entry in ipairs(List()) do
        local item = byName[entry.n]
        if not item then
            item = { name = entry.n, count = 0, last = 0 }
            byName[entry.n] = item
            order[#order + 1] = item
        end
        item.count = item.count + 1
        item.last = math.max(item.last, entry.t or 0)
    end
    table.sort(order, function(a, b) return a.last > b.last end)
    return order
end

-- „Doch zeigen“: die Nachrichten dieses Absenders ins Gespräch holen (ungelesen) und ihn freigeben – künftig wird
-- er nicht mehr gefiltert. → Schlüssel des Gesprächs, Anzahl
function Spam.Release(full)
    if type(full) ~= "string" or not ns.C then return nil, 0 end
    local list, kept, moved = List(), {}, {}
    for _, entry in ipairs(list) do
        if entry.n == full then moved[#moved + 1] = entry else kept[#kept + 1] = entry end
    end
    if #moved == 0 then return nil, 0 end
    wipe(list)
    for i, entry in ipairs(kept) do list[i] = entry end
    ns.C.spamAllow = ns.C.spamAllow or {}
    local key = Conv.KeyOf(full)
    ns.C.spamAllow[key] = true
    for _, entry in ipairs(moved) do Conv.Add(full, false, { m = entry.m, t = entry.t }) end
    Conv.Changed(Spam.KEY)
    return key, #moved
end

-- Aufbewahrung nach Tagen (Einstellung keepDays, 0 = nie) auch für den Bereich „Gefiltert“. → Anzahl entfernter
function Spam.Expire(now)
    local days = ns.C and math.max(0, ns.Number("keepDays")) or 0
    if days == 0 then return 0 end
    local list, cutoff, kept = List(), (now or time()) - days * 86400, {}
    for _, entry in ipairs(list) do
        if (entry.t or cutoff) >= cutoff then kept[#kept + 1] = entry end
    end
    local removed = #list - #kept
    if removed == 0 then return 0 end
    wipe(list)
    for i, entry in ipairs(kept) do list[i] = entry end
    if (ns.C.filteredNew or 0) > #kept then ns.C.filteredNew = #kept end
    Conv.Changed(Spam.KEY)
    return removed
end

-- Alle gefilterten Nachrichten verwerfen (mit Rückfrage über den Aufrufer; auch „Verlauf löschen“ und das
-- Ausloggen bei „Flüstern speichern: aus“, Conversations.lua).
function Spam.Clear()
    wipe(List())
    if ns.C then ns.C.filteredNew = 0 end
    Conv.Changed(Spam.KEY)
end

-- Freigegeben über „Doch zeigen“?
function Spam.Allowed(key)
    return key ~= nil and ns.C ~= nil and ns.C.spamAllow ~= nil and ns.C.spamAllow[key] == true
end

-- Freigabe zurücknehmen (Eintrag „Wieder filtern“ im Menü des Gesprächs, Window.lua): der Absender wird wieder
-- geprüft. → true, wenn er freigegeben war
function Spam.Forbid(key)
    if not Spam.Allowed(key) then return false end
    ns.C.spamAllow[key] = nil
    return true
end

---------------------------------------------------------------------------
-- Blizzards Chatfenster: Spam nicht zeigen
---------------------------------------------------------------------------

-- Argument 6 der Flüster-Ereignisse sind die Kennzeichen („GM“), Argument 12 die GUID des Absenders (für die Stufe).
function Spam.Filter(_, _, msg, sender, ...)
    return Spam.Check(msg, sender, (select(10, ...)), (select(4, ...))) ~= nil
end

ns.OnReady(function()
    ns.AddMessageEventFilter("CHAT_MSG_WHISPER", Spam.Filter)
end)

-- Stichwörter bearbeiten (Knopf auf der Einstellungsseite und im Menü des Bereichs „Gefiltert“).
function Spam.EditWords()
    ns.AskText(L.SPAM_WORDS_PROMPT, ns.S.spamWords or "", function(text)
        ns.SetSetting("spamWords", text or "")
        ns.Print(L.SPAM_WORDS_SET:format(#Spam.Words()))
    end)
end

-- Menü am Bereich „Gefiltert“ (Rechtsklick auf die Zeile, Pfeil über dem Verlauf): je Absender „Doch zeigen“,
-- Stichwörter, alles verwerfen.
function Spam.FillMenu(root, onRelease)
    root:CreateTitle(L.SPAM_TITLE)
    local senders = Spam.Senders()
    if #senders == 0 then
        root:CreateButton(L.SPAM_EMPTY, function() end)
    end
    for _, item in ipairs(senders) do
        root:CreateButton(L.SPAM_RELEASE:format(ns.Short(item.name), item.count), function()
            local key, count = Spam.Release(item.name)
            if key then
                ns.Print(L.SPAM_RELEASED:format(ns.Short(item.name), count))
                if onRelease then onRelease(key) end
            end
        end)
    end
    root:CreateDivider()
    root:CreateButton(L.OPT_SPAM_WORDS, Spam.EditWords)
    if #senders > 0 then
        root:CreateButton(L.SPAM_CLEAR, function()
            ns.Confirm(L.CONFIRM_SPAM_CLEAR:format(Spam.Count()), Spam.Clear)
        end)
    end
end
