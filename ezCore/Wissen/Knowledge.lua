local _, ns = ...

--[[
    Knowledge – Wissen über Gegenstände: Was ist es, wofür ist es gut, für wen
    und ab welcher Stufe?

    Pro Gegenstand entsteht ein "facts"-Objekt, zwischengespeichert pro itemID
    (bei Zufallssuffixen "des Bären" pro Link-Variante). Quellen:
      * C_Item.GetItemInfo / GetItemInfoInstant (Art, Platz, Stufe, Preis, Bindung)
      * der Tooltip (C_TooltipInfo), höchstens einmal pro Gegenstand gelesen und
        mit Mustern aus Blizzards globalen Texten ausgewertet – nie mit fest
        eingetragenem deutschem oder englischem Text
      * statische Classic-Tabellen (KnowledgeData.lua, muss vorher geladen sein)
      * gelernte Berufsdaten (db), geteilt über alle Charaktere
    Liegt in ezCore (vorher ezBag), damit alle Module dasselbe Wissen nutzen (SSOT).
    db = ezCoreDB.knowledge, Twinks aus ezCoreDB.chars, ns.charKey aus ezCore.

    Nichts hier darf einen Fehler werfen: alle API-Aufrufe laufen über pcall,
    geheime Werte (issecretvalue) werden übersprungen.
]]

local K = {}
ns.Knowledge = K
ezCore.Knowledge = K   -- seit ezCore hier (vorher ezBag); gespeichert in ezCoreDB.knowledge

local lower, format, floor, max = string.lower, string.format, math.floor, math.max
local tconcat, tsort = table.concat, table.sort
local EMPTY = {}

---------------------------------------------------------------------------
-- Anzeigetexte: in ezCore.L (Kern/Locale.lua, Block „Item-Wissen“) – keine eigene Sprachtabelle (A78, SSOT).
-- K.L bleibt als Name für Aufrufer, die das Item-Wissen über ezCore.Knowledge.L lesen.
---------------------------------------------------------------------------

local LL = ezCore.L
K.L = LL

---------------------------------------------------------------------------
-- Grundhelfer
---------------------------------------------------------------------------

-- Geheime Werte: die Prüfung aus Util.lua (zuerst issecretvalue, dann nil), keine eigene Kopie.
local IsSecret, S, Num = ezCore.IsSecret, ezCore.Plain, ezCore.Num
local function Str(v)
    v = S(v)
    if type(v) == "string" and v ~= "" then return v end
    return nil
end

-- Gemeinsame Helfer aus Util.lua (vorher eigene Kopien hier)
local Call, Trim, Esc = ezCore.PCall, ezCore.Trim, ezCore.EscapePattern

-- Farb-, Link-, Textur- und Zeilenumbruch-Codes entfernen: Core.CleanText (Util.lua, V-029 – vorher eine Kopie hier).
local Clean = ezCore.CleanText

-- Blizzard-Formattext → verankertes Lua-Muster: Core.FormatToPattern (Util.lua, V-029 – die eine Fassung, vorher
-- eine zweite hier). "Benötigt Stufe %d" → "^Benötigt Stufe (%d+)$", "%c%s Ausdauer" → "^([%+%-])(.-) Ausdauer$".
-- Hier immer wie eine Tooltip-Zeile ("|n" → Leerzeichen, Rand ab), weil gegen gesäuberte Zeilen verglichen wird.
local function ToPattern(fmt)
    return ezCore.FormatToPattern(fmt, true)
end

-- "Benutzen:" → "^Benutzen:%s*(.-)$" (Rest der Zeile als Capture).
local function PrefixPattern(text)
    text = Str(text)
    if not text then return nil end
    text = Trim((text:gsub("|n", " "):gsub("%%%d?%$?s", "")))
    if text == "" then return nil end
    return "^" .. Esc(text) .. "%s*(.-)$"
end

---------------------------------------------------------------------------
-- Einrichtung (beim ersten Gebrauch: Daten, Namen, Muster)
---------------------------------------------------------------------------

local D = {}
local CLASSES, PROF_BY_KEY, PROF_BY_LINE, WEAPON_CLASSES = {}, {}, {}, {}
local CLASS_LABEL, CLASS_BY_NAME = {}, {}
local STAT_NAMES, STAT_LABEL, ITEM_MOD_KEYS = {}, {}, {}
local SLOT_BY_NAME, UNIT_WORDS = {}, {}
local P = {}
local FLAG_KEYS = { "startsQuest", "unique", "bop", "boe", "bou", "soulbound", "questbind", "conjured",
    "openable", "readable", "known", "set", "duration", "locked" }
local wellFedName, healthWord, manaWord
local isSetup = false
local RegisterEvents, eventsRegistered   -- unten bei den Ereignissen definiert

local function AddPattern(key, pattern)
    -- Muster einmal testen: kaputte globale Texte dürfen später nichts sprengen.
    if pattern and pcall(string.match, "", pattern) then
        P[key] = P[key] or {}
        P[key][#P[key] + 1] = pattern
    end
end

local function FromGlobals(key, ...)
    for i = 1, select("#", ...) do AddPattern(key, ToPattern(_G[select(i, ...)])) end
end

-- Erstes Capture (oder die ganze Zeile) eines passenden Musters.
local function MatchP(key, text)
    local list = P[key]
    if not list or not text then return nil end
    for i = 1, #list do
        local a, b = text:match(list[i])
        if a then return a, b end
    end
    return nil
end

-- Zaubername: Core.SpellName (Spells.lua, lädt nach dieser Datei; V-029 – vorher eine Kopie hier).
local function SpellName(id)
    local fn = ezCore.SpellName
    return type(fn) == "function" and Str(fn(id)) or nil
end

local function Setup()
    if isSetup then return end
    isSetup = true
    if RegisterEvents then RegisterEvents() end
    D = ns.KnowledgeData or {}

    CLASSES = D.CLASSES or {}
    local names = D.CLASS_NAMES or EMPTY
    local fallback = names[ezCore.IsGerman() and "de" or "en"] or EMPTY
    local male, female = _G.LOCALIZED_CLASS_NAMES_MALE or EMPTY, _G.LOCALIZED_CLASS_NAMES_FEMALE or EMPTY
    for _, token in ipairs(CLASSES) do
        CLASS_LABEL[token] = Str(male[token]) or fallback[token] or token
        -- Feste Länge statt ipairs: einzelne Einträge können nil sein.
        local list = { Str(male[token]), Str(female[token]), (names.de or EMPTY)[token], (names.en or EMPTY)[token], token }
        for i = 1, 5 do
            if list[i] then CLASS_BY_NAME[lower(list[i])] = token end
        end
    end

    for _, p in ipairs(D.PROFESSIONS or EMPTY) do
        PROF_BY_KEY[p.key] = p
        if p.skillLine then PROF_BY_LINE[p.skillLine] = p.key end
    end

    for token, list in pairs(D.WEAPONS_BY_CLASS or EMPTY) do
        for _, sub in ipairs(list) do
            WEAPON_CLASSES[sub] = WEAPON_CLASSES[sub] or {}
            WEAPON_CLASSES[sub][token] = true
        end
    end

    -- Wertenamen: längste zuerst, damit "Distanzangriffskraft" vor "Angriffskraft" greift.
    local statFallback = (D.STAT_NAMES and D.STAT_NAMES[ezCore.IsGerman() and "de" or "en"]) or EMPTY
    for key, globals in pairs(D.STAT_GLOBALS or EMPTY) do
        for _, g in ipairs(globals) do
            local text = Str(_G[g])
            if text then
                STAT_LABEL[key] = STAT_LABEL[key] or text
                if g:find("^ITEM_MOD_") then ITEM_MOD_KEYS[g] = key end
                local name = Trim(lower((text:gsub("%%%d?%$?[sdc]", ""))))
                if #name >= 3 then STAT_NAMES[#STAT_NAMES + 1] = { key = key, name = name } end
            end
        end
        STAT_LABEL[key] = STAT_LABEL[key] or statFallback[key] or key
    end
    -- alle Schlüssel aus GetItemStats (auch Ausweichen, Tempo, Widerstände …); Anzeige aus Blizzards Text
    for g, key in pairs(D.ITEM_STAT_KEYS or EMPTY) do
        ITEM_MOD_KEYS[g] = ITEM_MOD_KEYS[g] or key
        if key ~= "DPS" and key ~= "ARMOR" then STAT_LABEL[key] = STAT_LABEL[key] or Str(_G[g]) end
    end
    for key, text in pairs(statFallback) do STAT_LABEL[key] = STAT_LABEL[key] or text end
    tsort(STAT_NAMES, function(a, b) return #a.name > #b.name end)

    for loc in pairs(D.SLOT_KEYS or EMPTY) do
        local name = Str(_G[loc])
        if name then SLOT_BY_NAME[name] = loc end
    end

    -- Zeiteinheiten ("sek", "min", "std" …) aus Dauer-Texten, um "für 15 Min." nicht als Wert zu lesen.
    for _, g in ipairs({ "INT_SPELL_DURATION_SEC", "INT_SPELL_DURATION_MIN", "INT_SPELL_DURATION_HOURS",
        "INT_SPELL_DURATION_DAYS", "SPELL_DURATION_SEC", "SPELL_DURATION_MIN", "D_SECONDS", "D_MINUTES",
        "D_HOURS", "D_DAYS", "SECONDS_ABBR", "MINUTES_ABBR", "HOURS_ABBR" }) do
        local text = Str(_G[g])
        if text then
            text = lower(text):gsub("|4([^:;]*):([^;]*);", " %1 %2 "):gsub("%%[%d%.%$]*[dsf]", " ")
            for word in text:gmatch("[^%s%d%p]+") do UNIT_WORDS[word] = true end
        end
    end

    healthWord = Str(_G.HEALTH) and lower(_G.HEALTH) or nil
    manaWord = Str(_G.MANA) and lower(_G.MANA) or nil

    FromGlobals("retrieving", "RETRIEVING_ITEM_INFO")
    FromGlobals("minLevel", "ITEM_MIN_LEVEL")
    FromGlobals("reqRep", "ITEM_REQ_REPUTATION")
    FromGlobals("reqSkill", "ITEM_REQ_SKILL")
    FromGlobals("classes", "ITEM_CLASSES_ALLOWED")
    FromGlobals("races", "ITEM_RACES_ALLOWED")
    FromGlobals("startsQuest", "ITEM_STARTS_QUEST")
    FromGlobals("unique", "ITEM_UNIQUE", "ITEM_UNIQUE_MULTIPLE", "ITEM_UNIQUE_EQUIPPABLE")
    FromGlobals("bop", "ITEM_BIND_ON_PICKUP")
    FromGlobals("boe", "ITEM_BIND_ON_EQUIP")
    FromGlobals("bou", "ITEM_BIND_ON_USE")
    FromGlobals("soulbound", "ITEM_SOULBOUND")
    FromGlobals("questbind", "ITEM_BIND_QUEST")
    FromGlobals("conjured", "ITEM_CONJURED")
    FromGlobals("openable", "ITEM_OPENABLE")
    if rawget(_G, "LOCKED") then FromGlobals("locked", "LOCKED") end   -- nicht jeder Client führt den Text
    FromGlobals("readable", "ITEM_READABLE")
    FromGlobals("known", "ITEM_SPELL_KNOWN")
    FromGlobals("set", "ITEM_SET_BONUS", "ITEM_SET_NAME")
    FromGlobals("duration", "ITEM_DURATION_DAYS", "ITEM_DURATION_HOURS", "ITEM_DURATION_MIN", "ITEM_DURATION_SEC")
    AddPattern("use", PrefixPattern(_G.ITEM_SPELL_TRIGGER_ONUSE))
    AddPattern("equipLine", PrefixPattern(_G.ITEM_SPELL_TRIGGER_ONEQUIP))
    AddPattern("reagents", PrefixPattern(_G.SPELL_REAGENTS))
    for key, g in pairs(D.STAT_LINE_GLOBALS or EMPTY) do FromGlobals("stat:" .. key, g) end
end

---------------------------------------------------------------------------
-- Namen: Berufe, Klassen, Werte, Plätze
---------------------------------------------------------------------------

local profNames, profByName = {}, nil

local function ProfessionName(key)
    if not key then return nil end
    if profNames[key] then return profNames[key] end
    local p = PROF_BY_KEY[key]
    if not p then return key end
    local name
    if C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName then
        local ok, n = pcall(C_TradeSkillUI.GetTradeSkillDisplayName, p.skillLine)
        if ok then name = Str(n) end
    end
    name = name or SpellName(p.spell) or (ezCore.IsGerman() and p.de) or p.en or key
    profNames[key] = name
    return name
end

local function ProfKeyFromName(name)
    name = Str(name)
    if not name then return nil end
    if not profByName then
        profByName = {}
        for key, p in pairs(PROF_BY_KEY) do
            profByName[lower(ProfessionName(key))] = key
            if p.de then profByName[lower(p.de)] = key end
            if p.en then profByName[lower(p.en)] = key end
        end
    end
    return profByName[lower(Trim(name))]
end

local function ClassLabel(token) return CLASS_LABEL[token] or token end
local function StatLabel(key) return STAT_LABEL[key] or key end

local function SlotLabel(loc)
    if not loc then return nil end
    local from = D.SLOT_LABEL_FROM and D.SLOT_LABEL_FROM[loc] or loc
    return Str(_G[from]) or Str(_G[loc]) or loc
end

local function SlotOrder(key)
    for i, k in ipairs(D.SLOT_ORDER or EMPTY) do
        if k == key then return i end
    end
    return 99
end

local function ClassList(set)
    local out = {}
    for _, token in ipairs(CLASSES) do
        if set[token] then out[#out + 1] = ClassLabel(token) end
    end
    return tconcat(out, ", ")
end

local function SortedStats(stats)
    local out = {}
    if not stats then return out end
    for _, key in ipairs(D.STAT_ORDER or EMPTY) do
        if stats[key] then out[#out + 1] = key end
    end
    return out
end

K.ProfessionName = ProfessionName
K.ClassName = ClassLabel
K.StatName = StatLabel

-- Schlüssel aus GetItemStats → eigener Wert-Schlüssel; Waffenschaden je nach Platz MELEEDPS oder RANGEDDPS.
function K.StatKey(blizzKey, equipLoc)
    local data = ns.KnowledgeData or EMPTY   -- auch vor der Einrichtung (Setup) gültig
    local key = type(blizzKey) == "string" and (ITEM_MOD_KEYS[blizzKey] or (data.ITEM_STAT_KEYS or EMPTY)[blizzKey]) or nil
    if key == "DPS" then key = (data.RANGED_LOCS or EMPTY)[equipLoc or ""] and "RANGEDDPS" or "MELEEDPS" end
    return key
end

-- Wert → Klassen-Menge (nil = gut für alle). Austauschbar für ein späteres Werte-Gewichtungs-Modul.
local statGoodFor = function(stat) return D.STAT_CLASSES and D.STAT_CLASSES[stat] end
function K.StatGoodFor(stat) return statGoodFor(stat) end

---------------------------------------------------------------------------
-- Zustand: Cache, gelernte Daten, Spieler
---------------------------------------------------------------------------

local cache, variants = {}, {}   -- [itemID] = facts; [itemID] = { [suffix] = facts }
local pending, requested, retries = {}, {}, {}
local kdb                        -- SavedVariables-Teil für gelerntes Wissen
local dynStamp = 1               -- steigt bei Stufenaufstieg, Berufsänderung usw.
local levelOverride

local readyFns, readyQueue, flushScheduled = {}, {}, false

local function Flush()
    flushScheduled = false
    local ids = readyQueue
    readyQueue = {}
    for id in pairs(ids) do
        for _, fn in ipairs(readyFns) do
            local ok, err = pcall(fn, id ~= 0 and id or nil)
            if not ok and geterrorhandler then geterrorhandler()(err) end
        end
    end
end

-- Meldungen sammeln und gebündelt ausliefern; id nil = "alles hat sich geändert".
local function QueueReady(id)
    readyQueue[id or 0] = true
    if flushScheduled then return end
    flushScheduled = true
    if C_Timer and C_Timer.After then C_Timer.After(0.1, Flush) else Flush() end
end

local function InvalidateAll(silent)
    wipe(cache)
    wipe(variants)
    dynStamp = dynStamp + 1
    if not silent then QueueReady(nil) end
end

function K.Invalidate() InvalidateAll(false) end

function K.SetStatGoodFor(fn)
    if type(fn) == "function" then
        statGoodFor = fn
        InvalidateAll(false)
    end
end

function K.Init(db)
    if type(db) ~= "table" then return end
    Setup()
    db.recipes = db.recipes or {}      -- [Rezept] = { n = Name, p = Beruf, o = Produkt-ID, r = { [Zutat-ID] = Anzahl } }
    db.reagents = db.reagents or {}    -- [Zutat-ID] = { [Rezept] = true }
    db.created = db.created or {}      -- [Produkt-ID] = Rezept
    db.names = db.names or {}          -- [name klein] = itemID (Zutaten und Produkte)
    db.items = db.items or {}          -- [itemID] = Name
    db.charProfs = db.charProfs or {}  -- ["Name-Realm"] = { [Beruf] = Rang }
    if kdb ~= db then
        kdb = db
        InvalidateAll(true)
    end
end

local function EnsureDB()
    if kdb then return kdb end
    if type(ns.db) == "table" then
        ns.db.knowledge = ns.db.knowledge or {}
        K.Init(ns.db.knowledge)
    end
    return kdb
end

local function PlayerClass()
    return ezCore.PlayerClass()
end

local function PlayerLevel()
    local level = ezCore.PlayerLevel()
    if levelOverride and (not level or levelOverride > level) then return levelOverride end
    return level
end

-- Entwurf 1.6 („Zustand verlässt den Wissens-Ast“, Welle 10): Berufe aus der Fertigkeitenliste stehen nicht mehr in
-- knowledge.charProfs, sondern als Liste in ezCoreDB.chars[charKey].profs – dieselbe Liste wie aus GetProfessions
-- (Professions.lua), die Einträge tragen zusätzlich key und src = "skill". Professions.Save überschreibt sie nur mit
-- einer echten Antwort von GetProfessions. knowledge.charProfs bleibt liegen und wird einmal übernommen
-- (K.MigrateCharProfs, nur wo chars[charKey].profs leer ist); gelesen wird es nur noch als Rückfall.
local SECONDARY_PROF = { cooking = true, firstaid = true, fishing = true, archaeology = true }

local function SkillProfList(map)
    local list = {}
    for key, rank in pairs(type(map) == "table" and map or EMPTY) do
        if type(key) == "string" then
            list[#list + 1] = { key = key, name = ProfessionName(key) or key, rank = Num(rank) or 0,
                primary = not SECONDARY_PROF[key], src = "skill" }
        end
    end
    table.sort(list, function(a, b)
        if a.primary ~= b.primary then return a.primary end
        return tostring(a.name) < tostring(b.name)
    end)
    return list
end
K.SkillProfList = SkillProfList

-- Schreibt Berufe aus der Fertigkeitenliste nach chars[charKey].profs; → true, sonst false (kein Satz in chars:
-- dann bleibt knowledge.charProfs der Schreiber, wie vorher)
local function WriteSkillProfs(charKey, map)
    local c = charKey and ezCore.Char and ezCore.Char(charKey)
    if type(c) ~= "table" then return false end
    for _, p in ipairs(type(c.profs) == "table" and c.profs or EMPTY) do
        if type(p) == "table" and p.src ~= "skill" then return true end   -- GetProfessions hat geantwortet: gilt
    end
    c.profs = SkillProfList(map)
    -- Alle Berufe verlernt: der Altspeicher ist sonst der Rückfall von CharProfMap und brächte sie zurück
    -- (Fund der Gegenprüfung). Er bleibt liegen (S6), nur dieser Charakter steht dort jetzt leer.
    local old = kdb and kdb.charProfs
    if #c.profs == 0 and type(old) == "table" and old[charKey] ~= nil then old[charKey] = {} end
    ezCore.Fire("PROFESSIONS_CHANGED", c.profs)
    return true
end

-- Einmalige Übernahme knowledge.charProfs » chars[charKey].profs (nur wo dort nichts steht). → Zahl übernommener
function K.MigrateCharProfs()
    local db = ezCore.db
    local old = kdb and kdb.charProfs
    if type(db) ~= "table" or type(old) ~= "table" then return 0 end
    db.migrated = db.migrated or {}
    if db.migrated.charProfs then return 0 end
    local n = 0
    for charKey, map in pairs(old) do
        local c = ezCore.Char and ezCore.Char(charKey)
        if type(c) == "table" and type(map) == "table" and next(map) ~= nil
            and (type(c.profs) ~= "table" or #c.profs == 0) then
            c.profs = SkillProfList(map)
            n = n + 1
        end
    end
    db.migrated.charProfs = time and time() or 1
    return n
end

-- Berufe eines Twinks als { [Beruf-Schlüssel] = Rang } – abgeleitet aus der EINEN Quelle ezCoreDB.chars[key].profs
-- (Core.Professions.Of, V-007; vorher zusätzlich in knowledge.charProfs gespeichert). charProfs ist der Rückfall,
-- wenn diese Liste fehlt ODER leer ist (Twinks ohne Satz in chars, Altbestand vor der Übernahme).
local function CharProfMap(charKey)
    if not charKey then return nil end
    Setup()
    local P = ezCore.Professions
    local list = P and P.Of and P.Of(charKey)
    if type(list) == "table" then
        local map = {}
        for _, p in ipairs(list) do
            if type(p) == "table" then
                local key = (type(p.key) == "string" and p.key) or PROF_BY_LINE[Num(p.line) or -1] or ProfKeyFromName(p.name)
                if key then map[key] = Num(p.rank) or 0 end
            end
        end
        if next(map) ~= nil then return map end
    end
    local old = kdb and kdb.charProfs[charKey]
    if type(old) == "table" then return old end
    return type(list) == "table" and {} or nil
end
K.CharProfs = CharProfMap

local function CharProfRank(charKey, prof)
    local profs = CharProfMap(charKey)
    if not profs or not prof then return nil, profs ~= nil end
    return profs[prof], true
end

-- Entwurf 1.7: Name » Gegenstand nach dem Umzug (Discovery.Moved("names")) im Index text[Sprache].itemByName der
-- Datenbank (DB.NoteItemName); bis dahin und ohne Träger wie vorher in knowledge.names. knowledge.items (Nummer »
-- Name) bleibt Rückfall von ItemNameByID.
local function NamesMoved()
    local D = ezCore.Discovery
    return D and D.Moved and D.Moved("names") or false
end

local function RememberName(name, itemID)
    if not kdb or not name or not itemID then return end
    if NamesMoved() and ezCore.DB.NoteItemName(name, itemID) then return end
    kdb.names[lower(name)] = itemID
    kdb.items[itemID] = name
end

local function ItemIDByName(name)
    if not name then return nil end
    local DB = ezCore.DB
    local id = DB and DB.ItemByName and DB.ItemByName(name)
    if id then return id end
    id = kdb and kdb.names[lower(name)]
    if id then return id end
    return Num((ezCore.ItemInstant(name))) or nil   -- eine Umhüllung von GetItemInfoInstant (T16-16)
end

K.ItemIDByName, K.RememberName = ItemIDByName, RememberName   -- Weiterleitung (Entwurf 1.7), auch für Prüfungen

-- Zuerst der gelernte Name (Rezept-Wissen), sonst Core.ItemNameByID (Util.lua, V-029 – vorher eine Kopie hier);
-- ohne Nachladen, das Item-Wissen fordert fehlende Daten selbst an.
local function ItemNameByID(itemID)
    if not itemID then return nil end
    if kdb and kdb.items[itemID] then return kdb.items[itemID] end
    return ezCore.ItemNameByID(itemID, true)
end

---------------------------------------------------------------------------
-- Gegenstandsdaten
---------------------------------------------------------------------------

local function ItemInfo(item)
    local ok, name, link, quality, ilvl, minLevel, itemType, itemSubType, stack, equipLoc, _, price,
        classID, subClassID, bindType, expacID, setID, isReagent = Call(C_Item and C_Item.GetItemInfo or GetItemInfo, item)
    if not ok or not Str(name) then return nil end
    return {
        name = Str(name), link = Str(link), quality = Num(quality), itemLevel = Num(ilvl), minLevel = Num(minLevel),
        className = Str(itemType), subClassName = Str(itemSubType), stackSize = Num(stack), equipLoc = Str(equipLoc),
        vendorPrice = Num(price), classID = Num(classID), subClassID = Num(subClassID), bindType = Num(bindType),
        setID = Num(setID), isCraftingReagent = S(isReagent) == true, expacID = Num(expacID),
    }
end

local function Resolve(item)
    item = S(item)
    if type(item) == "number" then
        if item > 0 then return item, nil end
        return nil
    end
    if type(item) ~= "string" or item == "" then return nil end
    local id = tonumber(item)
    if id then return id, nil end
    id = item:find("item:", 1, true) and ezCore.ItemID(item) or nil
    if id then return id, item end
    return Num((ezCore.ItemInstant(item))) or nil, nil
end

-- Zufallssuffix (7. Feld im Item-Link) – nur dann lohnt ein eigener Cache-Eintrag.
-- Abwandlung eines Gegenstands mit eigenen Werten: Zufallssuffix im 7. Feld des Links (Classic) oder – wie auf
-- Forever – als Bonus-ID („der Stärke“ steht z. B. in item:14167::::::::10:1490:::1:12732, Hinweis von ezGear).
-- Felder nach "item:": 1 itemID, 2 Verzauberung, 3–6 Sockel, 7 Suffix, 8 unique, 9 Stufe, 10 Spezialisierung,
-- 11 Modifizierer-Maske, 12 Kontext, 13 Anzahl Bonus-IDs, ab 14 die Bonus-IDs.
local function VariantKey(link)
    if type(link) ~= "string" then return nil end
    local body = link:match("item:([%-%d:]+)")
    if not body then return nil end
    local fields = {}
    for field in (body .. ":"):gmatch("([^:]*):") do fields[#fields + 1] = field end
    local suffix = fields[7]
    if suffix and suffix ~= "" and suffix ~= "0" then return suffix end
    local count = tonumber(fields[13] or "")
    if count and count > 0 then
        local ids = {}
        for i = 14, 13 + count do
            if fields[i] and fields[i] ~= "" then ids[#ids + 1] = fields[i] end
        end
        if #ids > 0 then return "b" .. table.concat(ids, ",") end
    end
    return nil
end
K.VariantKey = VariantKey

---------------------------------------------------------------------------
-- Tooltip lesen und auswerten
---------------------------------------------------------------------------

local function LineTexts(line)
    if type(line) ~= "table" then return nil end
    local left, right = line.leftText, line.rightText
    if left == nil and type(line.args) == "table" then
        for _, arg in ipairs(line.args) do
            if type(arg) == "table" then
                if arg.field == "leftText" then left = arg.stringVal
                elseif arg.field == "rightText" then right = arg.stringVal end
            end
        end
    end
    return Clean(left), Clean(right)
end

local function ReadTooltip(itemID, link)
    local api = C_TooltipInfo
    if not api then return nil end
    local ok, data = false, nil
    if link and api.GetHyperlink then ok, data = pcall(api.GetHyperlink, link) end
    if (not ok or type(data) ~= "table") and api.GetItemByID then ok, data = pcall(api.GetItemByID, itemID) end
    data = ok and S(data) or nil
    if type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
    local lines = {}
    for i = 1, #data.lines do
        local left, right = LineTexts(data.lines[i])
        if left or right then lines[#lines + 1] = { l = left, r = right } end
    end
    if #lines == 0 then return nil end
    return lines
end

--[[
    Eine Zeile "Benötigt …" (ITEM_REQ_SKILL) ist mehrdeutig:
      * "Lederverarbeitung (125)" vor der Benutzen-Zeile = Fertigkeitsanforderung
      * nach der Benutzen-Zeile eines Rezepts = Zutatenliste ("Leichtes Leder (6), Grober Faden")
    Bei Rezepten gehört alles nach der ersten Benutzen-Zeile zum hergestellten
    Gegenstand (Platz, Stufe, eigene Effekte); die letzte Zutaten-Zeile gewinnt.
]]
local function ParseTooltip(f, lines)
    local tip = { use = {}, equip = {}, createdUse = {}, flags = {}, lineStats = {} }
    local parts = {}
    local isRecipe = f.recipe ~= nil
    local seenUse, reagentLine, candidate = false, nil, nil
    local createdName = isRecipe and f.recipe.createdName and lower(f.recipe.createdName)
    for i, line in ipairs(lines) do
        local l, r = line.l, line.r
        if l then parts[#parts + 1] = l end
        if r then parts[#parts + 1] = r end
        if i == 1 then
            if MatchP("retrieving", l) then tip.incomplete = true end
        elseif l then
            local inCreated = isRecipe and seenUse
            local lvl = MatchP("minLevel", l)
            local rep = not lvl and MatchP("reqRep", l)
            local skill = not lvl and not rep and MatchP("reqSkill", l)
            local reag = MatchP("reagents", l)
            local use = MatchP("use", l)
            if lvl then
                if inCreated then tip.createdMinLevel = tonumber(lvl) else tip.minLevel = tonumber(lvl) end
            elseif rep then
                tip.reqRep = rep
            elseif reag then
                reagentLine = reag
            elseif skill then
                local pname, rank = skill:match("^(.-)%s*%((%d+)%)$")
                local pkey = pname and ProfKeyFromName(pname)
                -- Steht die Berufszeile erst nach "Benutzen:", zählt sie nur beim eigenen Beruf des Rezepts.
                local own = pkey ~= nil and isRecipe and pkey == f.recipe.profession and not tip.reqSkill
                if pname and (pkey or not seenUse) and (not inCreated or own) then
                    if not tip.reqSkill then tip.reqSkill = { name = pname, rank = tonumber(rank), profession = pkey } end
                elseif seenUse and not pkey then
                    candidate = skill
                end
            elseif use then
                if inCreated then tip.createdUse[#tip.createdUse + 1] = use else tip.use[#tip.use + 1] = use end
                seenUse = true
            elseif not inCreated then
                local eq = MatchP("equipLine", l)
                local classes = not eq and MatchP("classes", l)
                if eq then
                    tip.equip[#tip.equip + 1] = eq
                elseif classes then
                    tip.classes = classes
                elseif MatchP("races", l) then
                    tip.flags.raceRestricted = true
                else
                    for _, key in ipairs(FLAG_KEYS) do
                        if MatchP(key, l) then tip.flags[key] = true; break end
                    end
                    for key in pairs(D.STAT_LINE_GLOBALS or EMPTY) do
                        local sign, value = MatchP("stat:" .. key, l)
                        value = tonumber(value)
                        if sign and value then tip.lineStats[key] = (sign == "-" and -value or value) end
                    end
                end
            end
            if inCreated then
                if SLOT_BY_NAME[l] and not tip.createdSlot then
                    tip.createdSlot, tip.createdSubType = SLOT_BY_NAME[l], r
                end
                if createdName and lower(l) == createdName then tip.createdConfirmed = true end
            end
        end
    end
    tip.reagentText = reagentLine or candidate
    tip.text = lower(tconcat(parts, "\n"))
    return tip
end

-- "Leichtes Leder (6), Grober Faden" bzw. "6 Leichtes Leder, …" → Liste.
local function ParseReagents(text)
    local list = {}
    if not text then return list end
    text = text:gsub("|n", ",")
    for chunk in (text .. ","):gmatch("([^,]+),") do
        chunk = Trim(chunk)
        local name, count = chunk:match("^(.-)%s*%((%d+)%)$")
        if not name then count, name = chunk:match("^(%d+)%s*[xX]?%s+(.+)$") end
        name = Trim(name or chunk)
        if name ~= "" then
            list[#list + 1] = { name = name, count = tonumber(count) or 1, itemID = ItemIDByName(name) }
        end
    end
    return list
end

-- Steht hinter der Zahl an Position pos eine Zeiteinheit ("15 Min.")?
local function IsDurationAt(text, pos)
    local word = text:match("^%s*([^%s%d%p]+)", pos)
    return word ~= nil and UNIT_WORDS[word] == true
end

local function NumberBefore(text, s)
    local num = text:sub(max(1, s - 10), s - 1):match("(%d+)%s*$")
    return tonumber(num)
end

--[[
    Wertenamen im (kleingeschriebenen) Text finden und eine Zahl zuordnen:
      1. Zahl direkt davor ("12 ausdauer")
      2. Aufzählung ("12 ausdauer und willenskraft") übernimmt die Zahl des Vorgängers
      3. erste Zahl danach, die keine Dauer ist ("beweglichkeit 1 std. lang um 25" → 25)
    Ohne Zahl zählt nur das Vorkommen (Wert 0).
]]
local function ParseStats(text, out, onlyMissing)
    if not text or text == "" then return end
    local hits = {}
    for _, sn in ipairs(STAT_NAMES) do
        local init = 1
        while true do
            local s, e = text:find(sn.name, init, true)
            if not s then break end
            local covered = false
            for _, h in ipairs(hits) do
                if s >= h.s and e <= h.e then covered = true; break end
            end
            if not covered then hits[#hits + 1] = { s = s, e = e, key = sn.key } end
            init = e + 1
        end
    end
    tsort(hits, function(a, b) return a.s < b.s end)
    local prev
    for _, h in ipairs(hits) do
        local value = NumberBefore(text, h.s)
        if not value and prev and h.s - prev.e <= 8 then value = prev.value end
        if not value then
            local pos, limit = h.e + 1, h.e + 30
            while pos <= limit do
                local s, e, n = text:find("(%d+)", pos)
                if not s or s > limit then break end
                if not IsDurationAt(text, e + 1) then value = tonumber(n); break end
                pos = e + 1
            end
        end
        h.value = value or 0
        if not (onlyMissing and out[h.key]) then out[h.key] = max(out[h.key] or 0, h.value) end
        prev = h
    end
end

---------------------------------------------------------------------------
-- Bausteine der facts
---------------------------------------------------------------------------

local function BuildBase(f)
    if not f.classID then
        local _, _, _, equipLoc, _, classID, subClassID = ezCore.ItemInstant(f.itemID)
        f.classID, f.subClassID = Num(classID), Num(subClassID)
        f.equipLoc = f.equipLoc or Str(equipLoc)
    end
    f.isEquipment = ezCore.EquipSlots.IsEquipment(f.classID, f.equipLoc)   -- die eine Regel (EquipSlots.lua, V-177)
    local slotKey = f.equipLoc and D.SLOT_KEYS and D.SLOT_KEYS[f.equipLoc]
    if slotKey then
        f.slotKey, f.slotName = slotKey, SlotLabel(f.equipLoc)
    end
    if f.classID == 4 and D.ARMOR_KEYS then f.armorType = D.ARMOR_KEYS[f.subClassID] end
    if f.classID == 2 then f.weaponType, f.weaponSubClass = f.subClassName, f.subClassID end
    if f.classID == 9 then
        f.recipe = {
            profession = D.RECIPE_SUBCLASS and D.RECIPE_SUBCLASS[f.subClassID],
            createdName = f.name and f.name:match("^[^:]+:%s*(.+)$"),
            reagents = {},
        }
    end
    local ok, spellName, spellID = Call(C_Item and C_Item.GetItemSpell or GetItemSpell, f.itemID)
    if ok then
        f.useSpellID = Num(spellID)
        f.hasUseSpell = Str(spellName) ~= nil or f.useSpellID ~= nil
    end
end

local function LearnedRecipe(key)
    return kdb and key and kdb.recipes[key]
end

local function BuildRecipe(f, tip)
    local r = f.recipe
    if not r then return end
    local req = tip.reqSkill
    if req then
        r.skill = req.rank
        r.profession = r.profession or req.profession
    end
    r.professionName = ProfessionName(r.profession) or (req and req.name)
    r.createdMinLevel = tip.createdMinLevel
    r.createdUse = #tip.createdUse > 0 and tconcat(tip.createdUse, " ") or nil
    r.known = tip.flags.known or nil
    r.createdItemID = ItemIDByName(r.createdName)
    if tip.createdSlot then
        r.createdSlotKey = D.SLOT_KEYS and D.SLOT_KEYS[tip.createdSlot]
        r.createdSlot, r.createdSubType = SlotLabel(tip.createdSlot), tip.createdSubType
    elseif r.createdItemID then
        local _, _, subType, equipLoc = ezCore.ItemInstant(r.createdItemID)
        equipLoc = Str(equipLoc)
        if equipLoc and D.SLOT_KEYS and D.SLOT_KEYS[equipLoc] and not (D.NOT_EQUIPPABLE or EMPTY)[equipLoc] then
            r.createdSlotKey, r.createdSlot, r.createdSubType = D.SLOT_KEYS[equipLoc], SlotLabel(equipLoc), Str(subType)
        end
    end
    r.reagents = ParseReagents(tip.reagentText)
    -- Keine Zutaten im Tooltip, aber das Rezept ist gelernt bekannt → aus der db.
    local rec = r.createdItemID and kdb and LearnedRecipe(kdb.created[r.createdItemID])
    if #r.reagents == 0 and rec then
        for id, count in pairs(rec.r or EMPTY) do
            r.reagents[#r.reagents + 1] = { name = ItemNameByID(id) or ("#" .. id), count = count, itemID = id }
        end
        tsort(r.reagents, function(a, b) return a.name < b.name end)
    end
    r.createdNameConfirmed = tip.createdConfirmed or nil
end

-- Name des Buffs "Satt" (Zauberdaten können anfangs fehlen, daher erst beim Gebrauch).
local function WellFedName()
    if wellFedName then return wellFedName end
    for _, id in ipairs(D.WELL_FED_SPELLS or EMPTY) do   -- die eine Liste (auch Spells.BUFFS.wellFed, V-030)
        local name = SpellName(id)
        if name then wellFedName = lower(name); break end
    end
    return wellFedName
end

local function BuildConsumable(f, tip)
    if f.classID ~= 0 then return end
    local c = { kind = (D.CONSUMABLE_KIND and D.CONSUMABLE_KIND[f.subClassID]) or "other", stats = {} }
    local text = lower(tconcat(tip.use, " "))
    -- Bei Essen trennt das Wort "Satt" Wiederherstellung (davor) und Buff (danach).
    local before, after = text, nil
    local wellFedName = WellFedName()
    if wellFedName then
        local s, e = text:find(wellFedName, 1, true)
        if s then before, after, c.wellFed = text:sub(1, s - 1), text:sub(e + 1), true end
    end
    c.restoresHealth = healthWord ~= nil and before:find(healthWord, 1, true) ~= nil
    c.restoresMana = manaWord ~= nil and before:find(manaWord, 1, true) ~= nil
    ParseStats(after or text, c.stats)
    if after then
        local s = manaWord and after:find(manaWord, 1, true)
        if s and not c.stats.MP5 then c.stats.MP5 = NumberBefore(after, s) or 0 end
        s = healthWord and after:find(healthWord, 1, true)
        if s and not c.stats.HP5 then c.stats.HP5 = NumberBefore(after, s) or 0 end
    end
    if c.kind == "food" then
        if c.restoresMana and c.restoresHealth then c.kind = "foodDrink"
        elseif c.restoresMana then c.kind = "drink"
        elseif not c.restoresHealth and not c.wellFed and next(c.stats) == nil then c.restoresHealth = true end
    elseif c.kind == "bandage" then
        c.restoresHealth = true
    end
    c.buff = c.wellFed or next(c.stats) ~= nil or c.kind == "elixir" or c.kind == "flask" or c.kind == "scroll"
    -- Aura über den Zauber des Gegenstands (Fläschchen, Elixier, Rolle, Waffenverzauberung): Spells.FindAura findet
    -- sie damit auch ohne Namensvergleich; Quelle der Client (C_Item.GetItemSpell, oben in f.useSpellID)
    if c.buff or c.kind == "weaponEnchant" then c.auraSpell = f.useSpellID end
    f.consumable = c
end

local function BuildEquipStats(f, tip)
    if not f.isEquipment then return end
    local stats = {}
    local fn = (C_Item and C_Item.GetItemStats) or GetItemStats
    local ok, t = Call(fn, f.link)
    t = ok and S(t) or nil
    if type(t) == "table" then
        for k, v in pairs(t) do
            local key = K.StatKey(k, f.equipLoc)
            v = Num(v)
            if key and v and v ~= 0 then stats[key] = (stats[key] or 0) + v end
        end
    end
    if next(stats) == nil then
        for key, v in pairs(tip.lineStats) do stats[key] = v end
    end
    if #tip.equip > 0 then ParseStats(lower(tconcat(tip.equip, " ")), stats, true) end
    if next(stats) ~= nil then f.stats = stats end
end

local function ParseClassList(text)
    local set = {}
    for name in (text .. ","):gmatch("([^,]+),") do
        local token = CLASS_BY_NAME[lower(Trim(name))]
        if token then set[token] = true end
    end
    return set
end

-- Wer darf es tragen/benutzen? profLevel[Klasse] = ab welcher Stufe die Klasse die Art beherrscht.
local function BuildUsable(f, tip)
    local prof
    if f.isEquipment then
        if f.classID == 4 then
            local rule = D.ARMOR_PROF and D.ARMOR_PROF[f.subClassID]
            if rule then
                prof = {}
                for token, level in pairs(rule) do prof[token] = level end
            end
        elseif f.classID == 2 and not (D.WEAPONS_ALL or EMPTY)[f.subClassID] then
            local set = WEAPON_CLASSES[f.subClassID]
            if set then
                prof = {}
                for token in pairs(set) do prof[token] = 1 end
            end
        end
    end
    if not prof then
        prof = {}
        for _, token in ipairs(CLASSES) do prof[token] = 1 end
    end
    if tip.classes then
        local allowed = ParseClassList(tip.classes)
        if next(allowed) then
            f.classRestricted = true
            f.classLine = allowed          -- Klassen aus Blizzards Zeile „Klassen: …“ (steht so im Tooltip)
            for token in pairs(prof) do
                if not allowed[token] then prof[token] = nil end
            end
        end
    end
    f.profLevel = prof
    f.usableByClasses = {}
    for token in pairs(prof) do f.usableByClasses[token] = true end
    if (not f.minLevel or f.minLevel <= 1) and tip.minLevel then f.minLevel = tip.minLevel end
    if f.isEquipment then f.wearableFrom = f.minLevel end
    if tip.reqSkill and not f.recipe then f.reqSkill = tip.reqSkill end
end

-- Für wen lohnt es sich? Vereinigung der Klassen aller Werte, geschnitten mit "darf benutzen".
local function BuildGoodFor(f)
    local c = f.consumable
    local stats = (c and c.stats) or f.stats
    local wanted
    if stats then
        for stat in pairs(stats) do
            local set = statGoodFor(stat)
            if type(set) == "table" then
                wanted = wanted or {}
                for token in pairs(set) do wanted[token] = true end
            end
        end
    end
    if c and not wanted and c.restoresMana and not c.restoresHealth then wanted = D.MANA_CLASSES end
    if not (f.isEquipment or c or f.classRestricted) then return end
    local good, count = {}, 0
    for token in pairs(f.usableByClasses) do
        if not wanted or wanted[token] then good[token] = true; count = count + 1 end
    end
    if count == 0 then
        for token in pairs(f.usableByClasses) do good[token] = true; count = count + 1 end
    end
    f.goodFor = good
    f.goodForAll = count >= #CLASSES
    if c then c.goodFor = good end
end

local function BuildReagentFor(f)
    local profs, seen, recipes = {}, {}, {}
    local function add(key)
        if key and not seen[key] then seen[key] = true; profs[#profs + 1] = key end
    end
    local learned = kdb and kdb.reagents[f.itemID]
    local seenRecipes = learned ~= nil and next(learned) ~= nil
    if learned then
        for key in pairs(learned) do
            local rec = LearnedRecipe(key)
            if rec then
                add(rec.p)
                if rec.n then recipes[#recipes + 1] = rec.n end
            end
        end
    end
    if f.classID == 7 then
        local tg = D.TRADEGOODS and D.TRADEGOODS[f.subClassID]
        if tg then
            f.material = tg.mat
            for _, key in ipairs(tg.profs or EMPTY) do add(key) end
        end
    end
    if #profs > 0 or #recipes > 0 or f.isCraftingReagent then
        tsort(recipes)
        -- Quelle je Angabe (Leitlinie 11, BAG-16): Rezepte kennt ezCore nur aus gesehenen Berufefenstern
        f.reagentFor = { professions = profs, recipes = recipes, source = seenRecipes and "seen" or "client" }
    end
    -- Hergestellt mit: gesehenes Rezept, sonst die Zuordnung laut AtlasLoot aus dieser Sitzung (Quelle je Zeile, Leitlinie 11)
    local key, src = kdb and kdb.created[f.itemID], "seen"
    if not key and K.AtlasRecipeOf then key, src = K.AtlasRecipeOf(f.itemID), "atlasloot" end
    local rec = key and LearnedRecipe(key)
    if rec then f.craftedBy = { profession = rec.p, recipe = rec.n, source = src } end
end

local function BuildSpecial(f, tip)
    local list, keys = {}, {}
    local function add(key) keys[#keys + 1] = key; list[#list + 1] = LL["SP_" .. key] end
    local fl = tip.flags
    if fl.startsQuest then add("startsQuest") end
    if f.classID == 12 or f.bindType == 4 or fl.questbind then add("quest") end
    if fl.unique then add("unique") end
    if f.bindType == 1 or fl.bop then add("bop")
    elseif f.bindType == 2 or fl.boe then add("boe")
    elseif f.bindType == 3 or fl.bou then add("bou") end
    if (f.setID and f.setID > 0) or fl.set then add("set") end
    if fl.conjured then add("conjured") end
    if fl.openable then add("openable") end
    if fl.readable then add("readable") end
    if f.classRestricted then add("classRestricted") end
    if fl.raceRestricted then add("raceRestricted") end
    local price = f.vendorPrice
    if price == 0 and not fl.conjured and f.classID ~= 12 and f.bindType ~= 4 then
        add("noValue")
    elseif price and price >= ((f.quality or 0) <= 1 and (D.HIGH_VALUE_LOW_QUALITY or 10000) or (D.HIGH_VALUE_ANY or 50000)) then
        add("highValue")
    end
    if fl.duration then add("duration") end
    if f.recipe and f.recipe.known then add("known") end
    f.special, f.specialKeys = list, keys
    -- Öffenbar? und Questgegenstand als eigene Felder (DG-41; Abnehmer: ezMacro „Öffnen und Entzaubern“,
    -- „Questgegenstand“): openable = Blizzards Zeile „Rechtsklick zum Öffnen“, locked = „Verschlossen“ (Schließkassette)
    f.openable = (fl.openable or fl.locked) and true or nil
    f.locked = fl.locked and true or nil
    f.questItem = (f.classID == 12 or f.bindType == 4 or fl.questbind) and true or nil
    f.startsQuest = fl.startsQuest and true or nil
end

local function ProfessionsOf(f)
    if f._profs then return f._profs end
    local out, seen = {}, {}
    local function add(key)
        if key and not seen[key] then seen[key] = true; out[#out + 1] = key end
    end
    if f.recipe then add(f.recipe.profession) end
    if f.reqSkill then add(f.reqSkill.profession) end
    if f.reagentFor then
        for _, key in ipairs(f.reagentFor.professions) do add(key) end
    end
    if f.craftedBy then add(f.craftedBy.profession) end
    f._profs = out
    return out
end

-- Stufe für Suche/Gruppen: eigene Mindeststufe, bei Rezepten die des Produkts.
local function LevelOf(f)
    if f.minLevel and f.minLevel > 1 then return f.minLevel end
    local r = f.recipe
    if r and r.createdMinLevel and r.createdMinLevel > 1 then return r.createdMinLevel end
    return nil
end

local function BuildStaticTags(f)
    local tags, set = {}, {}
    local function add(key, label)
        if key and not set[key] then
            set[key] = true
            tags[#tags + 1] = { key = key, label = label or key }
        end
    end
    if f.classID and f.className then add("class:" .. f.classID, f.className) end
    if f.classID and f.subClassName then add("sub:" .. f.classID .. ":" .. (f.subClassID or 0), f.subClassName) end
    if f.isEquipment then add("equip", LL.T_equip) end
    if f.slotKey then add("slot:" .. f.slotKey, f.slotName) end
    if f.armorType then add("armor:" .. f.armorType, f.subClassName) end
    if f.classID == 2 then add("weapon:" .. (f.subClassID or 0), f.subClassName) end
    local r = f.recipe
    if r then
        add("recipe", LL.T_recipe)
        if r.createdSlotKey then add("crafts:slot:" .. r.createdSlotKey, format(LL.T_crafts, r.createdSlot or "?")) end
        if r.createdSubType then add("crafts:type:" .. lower(r.createdSubType), format(LL.T_crafts, r.createdSubType)) end
    end
    for _, key in ipairs(ProfessionsOf(f)) do add("prof:" .. key, ProfessionName(key)) end
    if f.reagentFor then add("reagent", LL.T_reagent) end
    if f.material then
        local fallback = D.MAT_NAMES and D.MAT_NAMES[ezCore.IsGerman() and "de" or "en"] or EMPTY
        add("mat:" .. f.material, (f.classID == 7 and f.subClassName) or fallback[f.material] or f.material)
    end
    local c = f.consumable
    if c then
        add("consumable", LL.T_consumable)
        if c.kind ~= "other" then add(c.kind, LL["KIND_" .. c.kind]) end
        if c.kind == "foodDrink" then add("food", LL.KIND_food); add("drink", LL.KIND_drink) end
        if c.buff then
            add("buff", LL.T_buff)
            if c.kind == "food" or c.kind == "drink" or c.kind == "foodDrink" then add("bufffood", LL.T_bufffood) end
        end
    end
    for _, stat in ipairs(SortedStats((c and c.stats) or f.stats)) do add("stat:" .. stat, StatLabel(stat)) end
    if f.goodFor and not f.goodForAll then
        for _, token in ipairs(CLASSES) do
            if f.goodFor[token] then add("for:" .. token, format(LL.T_for, ClassLabel(token))) end
        end
    end
    local level = LevelOf(f)
    if level then add("lvl:" .. level, format(LL.T_lvl, level)) end
    for _, key in ipairs(f.specialKeys) do
        if key == "bop" or key == "boe" or key == "bou" or key == "quest" then
            add(key, LL["T_" .. key])
        else
            add("special:" .. key, LL["SP_" .. key])
        end
    end
    f._staticTags = tags
end

local function Build(itemID, link)
    local f = ItemInfo(link or itemID)
    if not f then return nil end
    f.itemID = itemID
    if link then f.link = link end
    BuildBase(f)
    local lines = ReadTooltip(itemID, link)
    local tip = ParseTooltip(f, lines or EMPTY)
    f.text = tip.text
    BuildRecipe(f, tip)
    BuildConsumable(f, tip)
    BuildEquipStats(f, tip)
    BuildUsable(f, tip)
    BuildGoodFor(f)
    BuildReagentFor(f)
    BuildSpecial(f, tip)
    BuildStaticTags(f)
    -- Unvollständig: kein Tooltip, "Wird abgerufen …" oder Benutzen-Text fehlt noch (Zauberdaten laden nach).
    local needsUse = f.hasUseSpell and (f.classID == 0 or f.classID == 9)
    f._partial = lines == nil or tip.incomplete or (needsUse and #tip.use == 0) or nil
    if f._partial and f.useSpellID and C_Spell and C_Spell.RequestLoadSpellData then
        pcall(C_Spell.RequestLoadSpellData, f.useSpellID)
    end
    if f.reagentFor or f.craftedBy or f.classID == 7 then RememberName(f.name, itemID) end
    return f
end

---------------------------------------------------------------------------
-- Veränderliches: Spieler und Twinks (wird bei Stufenaufstieg neu berechnet)
---------------------------------------------------------------------------

local function HasUse(f)
    return f.isEquipment or f.consumable ~= nil or f.recipe ~= nil or f.classRestricted or f.hasUseSpell
        or (f.minLevel ~= nil and f.minLevel > 1)
end

-- Kann ein Charakter (Klasse, Stufe) es benutzen? → relevant, jetzt, ab
local function CanUse(f, class, level, charKey)
    local r = f.recipe
    if r and r.profession then
        local rank = CharProfRank(charKey, r.profession)
        if not rank then return false end
        return true, rank >= (r.skill or 0), r.skill or 1
    end
    local need = class and f.profLevel and f.profLevel[class]
    if not need then return false end
    local from = max(need, f.minLevel or 1)
    return true, (level or 0) >= from, from
end

local function AltsFor(f)
    local chars = type(ns.db) == "table" and ns.db.chars
    if type(chars) ~= "table" then return nil end
    local relevant = f.isEquipment or f.classRestricted or (f.recipe and f.recipe.profession)
        or (f.consumable and f.goodFor and not f.goodForAll)
    if not relevant then return nil end
    local out
    for key, c in pairs(chars) do
        if key ~= ns.charKey and type(c) == "table" and c.class then
            local ok, now, from = CanUse(f, c.class, Num(c.level), key)
            if ok and f.consumable and f.goodFor and not f.goodFor[c.class] then ok = false end
            if ok then
                out = out or {}
                out[#out + 1] = { key = key, name = c.name or key, class = c.class, level = c.level, now = now, from = from }
            end
        end
    end
    if out then
        tsort(out, function(a, b)
            if a.now ~= b.now then return a.now == true end
            return tostring(a.name) < tostring(b.name)
        end)
    end
    return out
end

-- Erweiterungen für veränderliches Wissen (Collections.lua: Sammlungen, Bücher): fn(f, add) mit add(key, label).
local dynamicProviders = {}
function K.AddDynamic(fn)
    if type(fn) == "function" then dynamicProviders[#dynamicProviders + 1] = fn end
end

-- Veränderliches neu berechnen (Stufe, Berufe, Sammlungen …) und die Module neu zeichnen lassen.
function K.RefreshDynamic()
    dynStamp = dynStamp + 1
    QueueReady(nil)
end

local function UpdateDynamic(f)
    if f._dyn == dynStamp then return end
    f._dyn = dynStamp
    local class, level = PlayerClass(), PlayerLevel()
    f.usableNow, f.usableFrom = nil, nil
    local r = f.recipe
    if r and r.profession then
        local rank, knownChar = CharProfRank(ns.charKey, r.profession)
        r.playerSkill, r.learnableNow = rank, nil
        if rank then
            r.learnableNow = not r.known and rank >= (r.skill or 0)
        elseif knownChar then
            r.learnableNow = false
        end
        f.usableNow = r.learnableNow
    elseif class then
        local ok, now, from = CanUse(f, class, level, ns.charKey)
        if ok then
            f.usableFrom, f.usableNow = from, now
            local req = f.reqSkill
            local rank, knownChar = CharProfRank(ns.charKey, req and req.profession)
            if req and req.profession and knownChar and (rank or 0) < (req.rank or 0) then f.usableNow = false end
        else
            f.usableNow = false
        end
    end
    local tags = {}
    for i, t in ipairs(f._staticTags or EMPTY) do tags[i] = t end
    local isProfRecipe = r ~= nil and r.profession ~= nil
    if HasUse(f) and f.usableNow ~= nil and not (r and r.known) then
        if f.usableNow then
            tags[#tags + 1] = { key = "usable", label = LL.T_usable }
        elseif f.usableFrom or (isProfRecipe and r.playerSkill) then
            tags[#tags + 1] = { key = "later", label = LL.T_later }
        else
            tags[#tags + 1] = { key = "unusable", label = isProfRecipe and LL.T_noprof or LL.T_unusable }
        end
    end
    local function add(key, label) tags[#tags + 1] = { key = key, label = label or key } end
    for _, fn in ipairs(dynamicProviders) do
        local ok, err = pcall(fn, f, add)
        if not ok then K.lastError = err end
    end
    f.tags = tags
    f._tagSet = nil
    f._hay = nil
    f.usefulForAlts = AltsFor(f)
end

---------------------------------------------------------------------------
-- Laden und Zwischenspeicher
---------------------------------------------------------------------------

local GetFacts

local function OnLoaded(itemID)
    if not itemID then return end
    local wasPending = pending[itemID]
    pending[itemID] = nil
    local f = cache[itemID]
    if wasPending or (f and f._partial) then
        cache[itemID], variants[itemID] = nil, nil
        QueueReady(itemID)
    end
end

-- requested[] drosselt (höchstens alle 10 s), pending[] merkt "Bescheid geben, wenn da".
local function RequestLoad(itemID)
    pending[itemID] = true
    local now = GetTime and GetTime() or 0
    if requested[itemID] and now - requested[itemID] < 10 then return end
    requested[itemID] = now
    local requestedOk = false
    if Item and Item.CreateFromItemID then
        local ok, item = pcall(Item.CreateFromItemID, Item, itemID)
        if ok and type(item) == "table" and item.ContinueOnItemLoad then
            requestedOk = pcall(item.ContinueOnItemLoad, item, function() OnLoaded(itemID) end)
        end
    end
    if not requestedOk and C_Item and C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, itemID)
    end
end

-- Unvollständige facts bis zu dreimal nachladen, dann melden.
local function ScheduleRetry(itemID, link, vkey)
    if not (C_Timer and C_Timer.After) then return end
    local key = vkey and (itemID .. ":" .. vkey) or itemID
    local tries = (retries[key] or 0) + 1
    if tries > 3 then return end
    retries[key] = tries
    C_Timer.After(1.5 * tries, function()
        local f = vkey and variants[itemID] and variants[itemID][vkey] or (not vkey and cache[itemID])
        if not f or not f._partial then return end
        if vkey then variants[itemID][vkey] = nil else cache[itemID] = nil end
        local ok, nf = pcall(GetFacts, link or itemID)
        if ok and nf and not nf._partial then QueueReady(itemID) end
    end)
end

GetFacts = function(item)
    Setup()
    EnsureDB()
    local itemID, link = Resolve(item)
    if not itemID then return nil end
    local vkey = VariantKey(link)
    local f
    if vkey then f = variants[itemID] and variants[itemID][vkey] else f = cache[itemID] end
    if not f then
        -- GetItemInfo liefert nil, solange der Gegenstand nicht im Client-Cache ist.
        f = Build(itemID, vkey and link or nil)
        if not f then RequestLoad(itemID); return nil end
        if vkey then
            variants[itemID] = variants[itemID] or {}
            variants[itemID][vkey] = f
        else
            cache[itemID] = f
        end
        if f._partial then ScheduleRetry(itemID, vkey and link, vkey) end
        -- Antwort des Clients in die Entdecker-Datenbank durchreichen (DG-09: mit Build, höchstens einmal je Sitzung)
        local DB = ezCore.DB
        if DB and DB.Client and not f._partial then pcall(DB.Client, "item", itemID) end
    end
    UpdateDynamic(f)
    return f
end

function K.Get(itemOrLink)
    local ok, f = pcall(GetFacts, itemOrLink)
    if ok then return f end
    K.lastError = f
    return nil
end

function K.OnReady(fn)
    if type(fn) == "function" then readyFns[#readyFns + 1] = fn end
end

function K.Tags(f)
    if type(f) ~= "table" then return EMPTY end
    ezCore.Try(nil, "Knowledge UpdateDynamic", UpdateDynamic, f)
    return f.tags or f._staticTags or EMPTY
end

local function HasTag(f, key)
    if not f._tagSet then
        f._tagSet = {}
        for _, t in ipairs(f.tags or EMPTY) do f._tagSet[t.key] = true end
    end
    return f._tagSet[key] == true
end

---------------------------------------------------------------------------
-- Verwandtschaft (Hover-Hervorhebung)
---------------------------------------------------------------------------

-- Pro facts einmal: welche itemIDs/Namen hängen damit zusammen, und warum.
local function RelSet(f)
    if f._rel then return f._rel end
    local ids, names = {}, {}
    local function addID(id, reason) if id and not ids[id] then ids[id] = reason end end
    local function addName(n, reason) if n and not names[lower(n)] then names[lower(n)] = reason end end
    local r = f.recipe
    if r then
        for _, rg in ipairs(r.reagents) do
            local reason = format(LL.REL_USES, rg.name)
            addID(rg.itemID, reason)
            addName(rg.name, reason)
        end
        if r.createdName then
            local reason = format(LL.REL_CREATES, r.createdName)
            addID(r.createdItemID, reason)
            addName(r.createdName, reason)
        end
    end
    if kdb then
        for key in pairs(kdb.reagents[f.itemID] or EMPTY) do
            local rec = LearnedRecipe(key)
            if rec then
                addID(rec.o, format(LL.REL_REAGENT_OF, rec.n or "?"))
                for other in pairs(rec.r or EMPTY) do
                    if other ~= f.itemID then addID(other, format(LL.REL_SHARED, rec.n or "?")) end
                end
            end
        end
        local product = f.itemID
        if r and r.createdItemID then product = r.createdItemID end
        local rec = LearnedRecipe(kdb.created[product])
        if rec then
            for other in pairs(rec.r or EMPTY) do addID(other, format(LL.REL_REAGENT_OF, rec.n or "?")) end
        end
    end
    f._rel = { ids = ids, names = names }
    return f._rel
end

local function RelatedOneWay(a, b)
    local rel = RelSet(a)
    local reason = (b.itemID and rel.ids[b.itemID]) or (b.name and rel.names[lower(b.name)])
    if reason then return reason end
    if a.recipe and a.text and b.name and #b.name >= 4 and a.text:find(lower(b.name), 1, true) then
        return LL.REL_TEXT
    end
    return nil
end

function K.Related(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    if a.itemID and a.itemID == b.itemID then return true, LL.REL_SAME end
    local ok, reason = pcall(RelatedOneWay, a, b)
    if ok and reason then return true, reason end
    ok, reason = pcall(RelatedOneWay, b, a)
    if ok and reason then return true, reason end
    return false
end

---------------------------------------------------------------------------
-- Suche
---------------------------------------------------------------------------

local function Hay(f)
    if f._hay then return f._hay end
    local parts = { lower(f.name or "") }
    for _, t in ipairs(f.tags or EMPTY) do
        parts[#parts + 1] = lower(t.label or "")
        parts[#parts + 1] = t.key
    end
    parts[#parts + 1] = f.text or ""
    f._hay = tconcat(parts, "\n")
    return f._hay
end

local function NumField(f, field)
    if field == "level" then return LevelOf(f)
    elseif field == "ilvl" then return f.itemLevel
    elseif field == "skill" then return (f.recipe and f.recipe.skill) or (f.reqSkill and f.reqSkill.rank)
    elseif field == "quality" then return f.quality
    elseif field == "value" then return f.vendorPrice and f.vendorPrice / 10000
    end
    return nil
end

local function Compare(v, op, n)
    if v == nil then return false end
    if op == "<" then return v < n
    elseif op == "<=" then return v <= n
    elseif op == ">" then return v > n
    elseif op == ">=" then return v >= n
    end
    return v == n
end

local function ClassFromWord(word)
    if CLASS_BY_NAME[word] then return CLASS_BY_NAME[word] end
    -- Präfix ab 4 Zeichen ("schu" ≠ "scha").
    if #word >= 4 then
        for name, token in pairs(CLASS_BY_NAME) do
            if name:sub(1, #word) == word then return token end
        end
    end
    return nil
end

-- "gut für" oder ausdrücklich auf die Klasse beschränkt.
local function ForClass(f, token)
    if f.goodFor and not f.goodForAll and f.goodFor[token] then return true end
    return f.classRestricted == true and f.usableByClasses[token] == true
end

local function TextField(f, field, v)
    if field == "profession" then
        for _, key in ipairs(ProfessionsOf(f)) do
            if key:find(v, 1, true) or lower(ProfessionName(key)):find(v, 1, true) then return true end
        end
        return false
    elseif field == "slot" then
        local r = f.recipe
        for _, s in ipairs({ f.slotKey or "", f.slotName or "", r and r.createdSlotKey or "", r and r.createdSlot or "" }) do
            if s ~= "" and lower(s):find(v, 1, true) then return true end
        end
        return false
    elseif field == "type" then
        return (lower(f.className or "") .. "\n" .. lower(f.subClassName or "") .. "\n" .. (f.armorType or "")):find(v, 1, true) ~= nil
    elseif field == "class" then
        local token = ClassFromWord(v)
        return token ~= nil and ForClass(f, token)
    elseif field == "tag" then
        for _, t in ipairs(f.tags or EMPTY) do
            if t.key:sub(1, #v) == v then return true end
        end
        return false
    elseif field == "name" then
        return lower(f.name or ""):find(v, 1, true) ~= nil
    elseif field == "mat" then
        return f.material ~= nil and ((f.material):find(v, 1, true) ~= nil or lower(f.subClassName or ""):find(v, 1, true) ~= nil)
    end
    return false
end

-- Ein Suchwort → Prädikat(f).
local function WordPredicate(w)
    local field, op, value = w:match("^([^<>=:!]+)([<>=:!]=?)(.+)$")
    if field then
        local numeric = D.SEARCH_NUMERIC and D.SEARCH_NUMERIC[field]
        local n = tonumber((value:gsub(",", ".")))
        if numeric and n then
            if op == ":" or op == "==" then op = "=" end
            if op == "!" or op == "!=" then
                return function(f) local v = NumField(f, numeric); return v ~= nil and v ~= n end
            end
            return function(f) return Compare(NumField(f, numeric), op, n) end
        end
        local textField = D.SEARCH_TEXT and D.SEARCH_TEXT[field]
        if textField and (op == ":" or op == "=") then
            return function(f) return TextField(f, textField, value) end
        end
    end
    local tag = D.SEARCH_KEYWORDS and D.SEARCH_KEYWORDS[w]
    if tag then return function(f) return HasTag(f, tag) end end
    local token = CLASS_BY_NAME[w]
    if token then
        return function(f) return ForClass(f, token) or Hay(f):find(w, 1, true) ~= nil end
    end
    return function(f) return Hay(f):find(w, 1, true) ~= nil end
end

local compiled, compiledCount = {}, 0

-- Suchtext → Liste von Prädikaten (alle müssen passen). "-wort" verneint, "a|b" = eins von beiden.
local function Compile(query)
    if compiled[query] then return compiled[query] end
    local words = {}
    for w in lower(query):gmatch("%S+") do words[#words + 1] = w end
    local preds = {}
    local i = 1
    while i <= #words do
        local w = words[i]
        local range = D.SEARCH_RANGE and D.SEARCH_RANGE[w]
        local nextNum = words[i + 1] and tonumber(words[i + 1])
        if range and nextNum then
            preds[#preds + 1] = function(f) return Compare(LevelOf(f), range, nextNum) end
            i = i + 2
        elseif D.SEARCH_NUMERIC and D.SEARCH_NUMERIC[w] == "level" and nextNum then
            preds[#preds + 1] = function(f) return LevelOf(f) == nextNum end
            i = i + 2
        else
            local negate = false
            local first = w:sub(1, 1)
            if #w > 1 and (first == "-" or first == "!") then negate, w = true, w:sub(2) end
            local alts = {}
            for alt in w:gmatch("[^|]+") do alts[#alts + 1] = WordPredicate(alt) end
            local pred
            if #alts == 1 then
                pred = alts[1]
            else
                pred = function(f)
                    for _, p in ipairs(alts) do
                        if p(f) then return true end
                    end
                    return false
                end
            end
            if negate then
                local inner = pred
                pred = function(f) return not inner(f) end
            end
            preds[#preds + 1] = pred
            i = i + 1
        end
    end
    if compiledCount > 30 then wipe(compiled); compiledCount = 0 end
    compiled[query] = preds
    compiledCount = compiledCount + 1
    return preds
end

local function Match(f, query)
    Setup()
    UpdateDynamic(f)
    for _, pred in ipairs(Compile(query)) do
        if not pred(f) then return false end
    end
    return true
end

function K.Match(f, query)
    if type(query) ~= "string" or IsSecret(query) or not query:find("%S") then return true end
    if type(f) ~= "table" then return false end
    local ok, result = pcall(Match, f, query)
    return ok and result == true
end

---------------------------------------------------------------------------
-- Sortieren und Untergruppen
---------------------------------------------------------------------------

K.SortModes = {
    { key = "quality", label = LL.S_quality },
    { key = "name", label = LL.S_name },
    { key = "level", label = LL.S_level },
    { key = "ilvl", label = LL.S_ilvl },
    { key = "type", label = LL.S_type },
    { key = "profession", label = LL.S_profession },
    { key = "value", label = LL.S_value },
    { key = "skill", label = LL.S_skill },
    { key = "expac", label = LL.S_expac },
}

local STRING_MODES = { name = true, type = true, profession = true }

-- Zahl oder Text, je Modus immer derselbe Typ (Text: "name", "type", "profession").
function K.SortValue(f, mode)
    if type(f) ~= "table" then return STRING_MODES[mode] and "" or 0 end
    if mode == "quality" then return f.quality or -1
    elseif mode == "name" then return lower(f.name or "")
    elseif mode == "level" then return LevelOf(f) or 0
    elseif mode == "ilvl" then return f.itemLevel or 0
    elseif mode == "type" then
        local slot = f.slotKey or (f.recipe and f.recipe.createdSlotKey)
        return format("%02d.%03d.%02d", f.classID or 99, f.subClassID or 999, slot and SlotOrder(slot) or 99)
    elseif mode == "profession" then
        local ok, list = pcall(ProfessionsOf, f)
        local key = ok and list[1]
        return key and lower(ProfessionName(key)) or "\255"
    elseif mode == "value" then return f.vendorPrice or 0
    elseif mode == "skill" then return (f.recipe and f.recipe.skill) or (f.reqSkill and f.reqSkill.rank) or 0
    elseif mode == "expac" then return f.expacID or -1
    end
    return 0
end

-- Fertiger Vergleich für table.sort: Modus, dann Name, dann itemID.
function K.Compare(a, b, mode, descending)
    local va, vb = K.SortValue(a, mode), K.SortValue(b, mode)
    if va ~= vb then
        if descending then return va > vb end
        return va < vb
    end
    local na, nb = K.SortValue(a, "name"), K.SortValue(b, "name")
    if na ~= nb then return na < nb end
    return ((type(a) == "table" and a.itemID) or 0) < ((type(b) == "table" and b.itemID) or 0)
end

local function Facet(key, label, fn)
    return {
        key = key, label = label,
        value = function(f)
            if type(f) ~= "table" then return "none", LL.F_NONE, "~" end
            local ok, subKey, subLabel, order = pcall(fn, f)
            if ok and subKey then return subKey, subLabel or subKey, order or subKey end
            return "none", LL.F_NONE, "~"
        end,
    }
end

-- value(facts) → subKey, subLabel, sortKey (sortKey optional zum Ordnen der Untergruppen).
K.Facets = {
    Facet("class", LL.F_class, function(f)
        if not f.classID then return nil end
        return "c" .. f.classID, f.className, format("%02d", f.classID)
    end),
    Facet("type", LL.F_type, function(f)
        if not f.classID then return nil end
        return "c" .. f.classID .. ":" .. (f.subClassID or 0), f.subClassName or f.className,
            format("%02d.%03d", f.classID, f.subClassID or 0)
    end),
    Facet("slot", LL.F_slot, function(f)
        local r = f.recipe
        local key = f.slotKey or (r and r.createdSlotKey)
        if not key then return nil end
        return "slot:" .. key, f.slotName or (r and r.createdSlot), format("%02d", SlotOrder(key))
    end),
    Facet("profession", LL.F_profession, function(f)
        local key = ProfessionsOf(f)[1]
        if not key then return nil end
        return "prof:" .. key, ProfessionName(key), lower(ProfessionName(key))
    end),
    Facet("level", LL.F_level, function(f)
        local level = LevelOf(f)
        if not level then return "lvl:none", LL.F_NOLEVEL, "00" end
        -- ab der Höchststufe des Clients eine Gruppe (Core.MaxLevel; Gesamtreview 18.11.2026, T16-14 – vorher fest 60)
        local top = ezCore.MaxLevel()
        if level >= top then return "lvl:" .. top, format(LL.F_MAX, top), format("%02d", top) end
        local lo = max(floor(level / 10) * 10, 1)
        local key = format("%02d", lo)
        return "lvl:" .. key, format(LL.F_RANGE, lo, floor(level / 10) * 10 + 9), key
    end),
    Facet("usefulFor", LL.F_usefulFor, function(f)
        if not f.goodFor then return nil end
        if f.goodForAll then return "all", LL.F_ALL, "~all" end
        local keys = {}
        for _, token in ipairs(CLASSES) do
            if f.goodFor[token] then keys[#keys + 1] = token end
        end
        if #keys == 0 then return nil end
        return "for:" .. tconcat(keys, "+"), ClassList(f.goodFor), tconcat(keys, "+")
    end),
    Facet("expac", LL.F_expac, function(f)
        if not f.expacID then return nil end
        return "x" .. f.expacID, Str(_G["EXPANSION_NAME" .. f.expacID]) or tostring(f.expacID), format("%02d", f.expacID)
    end),
    Facet("quality", LL.F_quality, function(f)
        if not f.quality then return nil end
        return "q" .. f.quality, ezCore.QualityName(f.quality),
            format("%d", 9 - f.quality)
    end),
}

---------------------------------------------------------------------------
-- Beschreibung für den Tooltip
---------------------------------------------------------------------------

-- Bindung zeigt Blizzard schon, Klassenbeschränkung steht als eigene Zeile.
local DESCRIBE_SKIP = { bop = true, boe = true, bou = true, classRestricted = true }

local function StatNames(stats)
    local out = {}
    for _, key in ipairs(SortedStats(stats)) do out[#out + 1] = StatLabel(key) end
    return tconcat(out, ", ")
end

-- Jede Zeile: Beschriftung (gold), Wert (weiß) und ein Ton: "ok" (grün, passt jetzt), "warn" (rot, passt nicht).
-- Zeilen, die ein Modul ausführlicher selbst zeigt (ezCraft: „Zutat für …“, „Rezept (Beruf): …“ samt Zutaten):
--   K.CoverLine(key, owner, fn(facts) → true)   fn nil hebt auf. key:
--     "recipes" (DL_RECIPES) | "crafted" (DL_CRAFTED)
--     "wear"    Zeile „Tragbar/Benutzbar ab Stufe“   | "class"  Zeile „Nicht für deine Klasse“
-- Liefert eins der fn true, lässt das Item-Wissen seine kurze Zeile weg (nichts doppelt im Tooltip).
--
-- Je Aussage eine Zeile, und nichts, was Blizzards Tooltip schon sagt (Spieltest 14.11.2026: „Benötigt Stufe 14“
-- rot, darunter „Tragbar ab Stufe: 14 (du: 10)“). Die Zeilen stehen unter Blizzards Gegenstands-Tooltip, deshalb:
--   - „Tragbar/Benutzbar ab Stufe“ nur, wenn die Klasse die Art erst später lernt als der Gegenstand verlangt
--     („40 (Schwere Rüstung erst ab Stufe 40)“, Kette für Jäger und Schamanen; Plattenteile verlangen selbst
--     Stufe 40) – die bloße Stufe des Gegenstands zeigt Blizzard als „Benötigt Stufe …“.
--   - „Nicht für deine Klasse (Leder)“ in EINER Zeile mit dem Grund; verbietet Blizzards Zeile „Klassen: …“ die
--     Klasse, steht dort schon alles (rot) – dann keine eigene Zeile.
--   - „Nur für: …“ entfällt: es wiederholt Blizzards „Klassen: …“.
-- K.DescribeLines(f, { full = true }) liefert weiter alle Zeilen (für Ansichten ohne Blizzards Tooltip).
local covers = {}
function K.CoverLine(key, owner, fn)
    if type(key) ~= "string" or owner == nil then return false end
    covers[key] = covers[key] or {}
    covers[key][owner] = type(fn) == "function" and fn or nil
    return true
end
local function Covered(key, f)
    local list = covers[key]
    if not list then return false end
    for _, fn in pairs(list) do
        local ok, yes = pcall(fn, f)
        if ok and yes == true then return true end
    end
    return false
end
K.Covered = Covered

local function Describe(f, full)
    UpdateDynamic(f)
    local out = {}
    -- key: welche Aussage (Knowledge.ShowsLine); source: woher sie stammt ("client" = Gegenstand und Blizzards
    -- Tooltip, "seen" = selbst gesehen, "atlasloot", "none" = noch nichts bekannt – BAG-16, Leitlinie 11)
    local function add(label, text, tone, key, source)
        if (label and label ~= "") or (text and text ~= "") then
            out[#out + 1] = { label = label, text = text, tone = tone, key = key, source = source or "client" }
        end
    end
    local class = PlayerClass()
    local function GoodForTone()
        if f.goodForAll or not f.goodFor or not class then return nil end
        return f.goodFor[class] and "ok" or nil
    end

    local c = f.consumable
    if c then
        local kind = LL["KIND_" .. c.kind]
        if c.buff then
            local head = kind
            if c.kind == "food" or c.kind == "foodDrink" then head = LL.D_BUFFFOOD
            elseif c.kind == "drink" then head = LL.D_BUFFDRINK end
            add(head, StatNames(c.stats), nil, "buff")
            if f.goodFor then add(LL.DL_GOOD, f.goodForAll and LL.D_ALL or ClassList(f.goodFor), GoodForTone(), "good") end
        elseif c.restoresHealth or c.restoresMana then
            local what = {}
            if c.restoresHealth then what[#what + 1] = Str(_G.HEALTH) or "Health" end
            if c.restoresMana then what[#what + 1] = Str(_G.MANA) or "Mana" end
            add(kind, format(LL.D_RESTORES, tconcat(what, LL.D_AND)), nil, "restores")
            if f.goodFor and not f.goodForAll then add(LL.DL_GOOD, ClassList(f.goodFor), GoodForTone(), "good") end
        end
    end

    local r = f.recipe
    local profRecipe = r ~= nil and r.profession ~= nil
    if r then
        local prof = Trim((r.professionName or "") .. (r.skill and (" " .. r.skill) or ""))
        local target = r.createdSlot and (r.createdSlot .. (r.createdSubType and (", " .. r.createdSubType) or "")) or r.createdName
        local text = prof
        if target then text = (text ~= "" and (text .. " – ") or "") .. target end
        add(LL.T_recipe, text, nil, "recipe")
        local names = {}
        for i, rg in ipairs(r.reagents) do
            if i > 5 then names[#names + 1] = "…"; break end
            names[#names + 1] = rg.name
        end
        if #names > 0 then add(LL.DL_NEEDS, tconcat(names, ", "), nil, "needs") end
        if r.playerSkill and r.skill and not r.known then
            local now = r.playerSkill >= r.skill
            add(LL.DL_LEARN, format(now and LL.DL_LEARN_NOW or LL.DL_LEARN_LATER, r.skill, r.playerSkill), now and "ok" or "warn", "learn")
        end
    end

    local rf = f.reagentFor
    if rf then
        local names = {}
        for _, key in ipairs(rf.professions) do names[#names + 1] = ProfessionName(key) end
        if #names > 0 then add(LL.DL_TRADEGOOD, tconcat(names, ", "), nil, "tradegood", rf.source) end
        local n = #rf.recipes
        if n > 0 and not Covered("recipes", f) then
            local list = {}
            for i = 1, math.min(n, 3) do list[i] = rf.recipes[i] end
            add(format(LL.DL_RECIPES, n), tconcat(list, ", ") .. (n > 3 and ", …" or ""), nil, "recipes", "seen")
        elseif n == 0 and f.classID == 7 and not Covered("recipes", f) then
            -- Handwerksware ohne ein gesehenes Rezept: sagen, warum nichts dasteht (BAG-16, „statt Schweigen“)
            add(LL.DL_RECIPES_ANY, LL.D_NOT_SEEN, nil, "recipes", "none")
        end
    end
    if f.craftedBy and f.craftedBy.profession and not Covered("crafted", f) then
        add(LL.DL_CRAFTED, ProfessionName(f.craftedBy.profession), nil, "crafted", f.craftedBy.source or "seen")
    end

    if not profRecipe and class and f.profLevel and not f.profLevel[class] and (f.isEquipment or f.classRestricted) then
        -- Grund: Blizzards Zeile „Klassen: …“ schließt die Klasse aus (steht rot im Tooltip) – sonst die Art
        local byClassLine = f.classRestricted and not (type(f.classLine) == "table" and f.classLine[class])
        if full then
            add(nil, LL.D_NOT_CLASS, "warn", "class")
            if f.classRestricted then add(LL.DL_ONLY, ClassList(f.usableByClasses), "warn", "only") end
        elseif not byClassLine and not Covered("class", f) then
            add(nil, f.subClassName and format(LL.D_NOT_CLASS_TYPE, f.subClassName) or LL.D_NOT_CLASS, "warn", "class")
        end
    else
        if not profRecipe and f.usableFrom and f.usableFrom > 1 then
            local later = f.usableFrom > (f.minLevel or 1)     -- die Klasse lernt die Art später als der Gegenstand verlangt
            if full or (later and not Covered("wear", f)) then
                local level = PlayerLevel()
                local text = tostring(f.usableFrom)
                local tone = nil
                if level and level < f.usableFrom then
                    text = text .. " " .. format(LL.D_YOU, level)
                    tone = "warn"
                end
                if later and f.subClassName then
                    text = text .. " " .. format(LL.D_PROF_AT, f.subClassName, f.usableFrom)
                end
                add(f.isEquipment and LL.DL_WEAR or LL.DL_USE, text, tone, "wear")
            end
        end
        if full and f.classRestricted then add(LL.DL_ONLY, ClassList(f.usableByClasses), "ok", "only") end
    end
    if f.isEquipment and f.goodFor and not f.goodForAll then
        add(LL.DL_GOOD, ClassList(f.goodFor), GoodForTone(), "good")
    end

    local special = {}
    for i, key in ipairs(f.specialKeys or EMPTY) do
        if not DESCRIBE_SKIP[key] then special[#special + 1] = f.special[i] end
    end
    if #special > 0 then add(LL.DL_SPECIAL, tconcat(special, ", "), nil, "special") end

    local alts = f.usefulForAlts
    if alts and #alts > 0 then
        local parts = {}
        for i, a in ipairs(alts) do
            if i > 5 then parts[#parts + 1] = "…"; break end
            parts[#parts + 1] = a.now and tostring(a.name) or format(LL.D_ALT_LATER, tostring(a.name), a.from or 0)
        end
        add(LL.DL_ALTS, tconcat(parts, ", "), nil, "alts", "seen")
    end
    return out
end

-- Strukturierte Zeilen { label, text, tone } für Tooltips, die selbst einfärben.
-- opts.full: auch die Zeilen, die Blizzards Tooltip schon zeigt (Stufe des Gegenstands, „Nur für: …“).
function K.DescribeLines(f, opts)
    if type(f) ~= "table" then return {} end
    local ok, lines = pcall(Describe, f, type(opts) == "table" and opts.full == true)
    return ok and lines or {}
end

-- Zeigt das Item-Wissen diese Aussage für den Gegenstand (FP-06)? key wie das Feld key der Zeilen: "wear" (Tragbar/
-- Benutzbar ab Stufe), "class" (Nicht für deine Klasse), "recipes", "crafted", "tradegood", "good", "special" …
-- Ohne aktiven Abschnitt „Item-Wissen“ (Schalter aus) zeigt es nichts. → true | false
function K.ShowsLine(item, key)
    if type(key) ~= "string" or IsSecret(item) or item == nil then return false end
    if K.SectionActive and not K.SectionActive() then return false end
    local f = K.Get(item)
    if type(f) ~= "table" then return false end
    for _, e in ipairs(K.DescribeLines(f)) do
        if e.key == key then return true end
    end
    return false
end

-- Text zur Quelle einer Zeile („bei dir gesehen“, „laut AtlasLoot“) oder nil für "client"/"none".
function K.SourceText(source)
    if source == "seen" then return LL.SRC_seen end
    if source == "atlasloot" then return LL.SRC_atlasloot end
    return nil
end

-- „Verschlossen“ frisch je Taschenplatz (Welle 23a, A53): Blizzards Tooltip des Platzes (C_TooltipInfo.GetBagItem)
-- statt des zwischengespeicherten Tooltips des Gegenstands – nach dem Schlossknacken sagt der Platz sofort „offen“.
-- → true/false; nil, wenn der Client den Tooltip nicht liefert (dann gilt das Item-Wissen).
local function FreshLocked(bag, slot)
    local api = C_TooltipInfo and C_TooltipInfo.GetBagItem
    if type(api) ~= "function" then return nil end
    local ok, data = pcall(api, bag, slot)
    data = ok and S(data) or nil
    if type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
    Setup()
    local word = rawget(_G, "LOCKED")   -- Blizzards Text „Verschlossen“ (nicht jeder Client führt ihn)
    word = type(word) == "string" and not IsSecret(word) and Clean(word) or nil
    for i = 1, #data.lines do
        local left = LineTexts(data.lines[i])
        if left and (MatchP("locked", left) or (word and left == word)) then return true end
    end
    return false
end
K.FreshLocked = FreshLocked

-- Öffenbar? → openable, locked (Schließkassette) – aus dem Item-Wissen, mit Platz zusätzlich aus Blizzards
-- ContainerItemInfo.hasLoot (DG-41); „verschlossen“ mit Platz frisch aus dessen Tooltip (FreshLocked)
function K.IsOpenable(item, bag, slot)
    if bag and slot and C_Container and C_Container.GetContainerItemInfo then
        local ok, info = Call(C_Container.GetContainerItemInfo, bag, slot)
        info = ok and S(info)
        if type(info) == "table" and S(info.hasLoot) == true then
            local fresh = FreshLocked(bag, slot)
            if fresh ~= nil then return true, fresh end
            local f = K.Get(info.hyperlink or info.itemID)
            return true, type(f) == "table" and f.locked == true or false
        end
    end
    local f = item ~= nil and K.Get(item)
    if type(f) ~= "table" then return false, false end
    return f.openable == true, f.locked == true
end

-- Questgegenstand? → questItem, startsQuest (DG-41)
function K.IsQuestItem(item)
    local f = item ~= nil and K.Get(item)
    if type(f) ~= "table" then return false, false end
    return f.questItem == true, f.startsQuest == true
end

-- Einfache Textzeilen „Beschriftung: Wert“ (opts wie K.DescribeLines).
function K.Describe(f, opts)
    local out = {}
    for _, e in ipairs(K.DescribeLines(f, opts)) do
        if e.label and e.text and e.text ~= "" then out[#out + 1] = e.label .. ": " .. e.text
        else out[#out + 1] = e.label or e.text end
    end
    return out
end

---------------------------------------------------------------------------
-- Berufe lernen (SSOT über alle Charaktere)
---------------------------------------------------------------------------

-- Berufe des aktuellen Charakters (Retail: GetProfessions, Classic: Fertigkeitenliste).
local function RefreshCharProfs()
    local db = EnsureDB()
    local charKey = ns.charKey
    if not db or not charKey then return end
    Setup()
    local profs, apiOk, fromApi = {}, false, false
    -- Berufe liest ezCore an einer Stelle (Professions.lua); hier nur der Schlüssel je Beruf.
    if GetProfessions and GetProfessionInfo and ezCore.Professions then
        apiOk = true
        for _, p in ipairs(ezCore.Professions.Read()) do
            local key = PROF_BY_LINE[p.line or -1] or ProfKeyFromName(p.name)
            if key then profs[key] = p.rank or 0 end
        end
        fromApi = next(profs) ~= nil
    end
    -- Rückfall Fertigkeitenliste (V-185): ezCore.SkillLines (Professions.lua; C_SkillInfo zuerst, laut Daten-Probe
    -- A2/A13 auf Forever vorhanden, sonst die Globalen wie früher). Gesperrte Werte gelten als unbekannt.
    local partial = false
    if next(profs) == nil and type(ezCore.SkillLines) == "function" then
        local lines, complete = ezCore.SkillLines(200)
        if lines and #lines > 0 then
            apiOk, partial = true, complete ~= true
            for _, line in ipairs(lines) do
                local key = not line.header and ProfKeyFromName(line.name)
                if key then profs[key] = line.rank or 0 end
            end
        end
    end
    if apiOk then
        -- Hat GetProfessions die Berufe geliefert, liegt der Stand schon in chars[key].profs (Professions.lua) – nicht
        -- zweimal speichern (V-007). Liefert es nichts (oder fehlt es), gilt wie bisher der Stand aus der
        -- Fertigkeitenliste – auch der leere, damit ein verlernter Beruf nicht stehen bleibt. Kann die Liste Lücken
        -- haben (eingeklappte Überschrift im Fertigkeitenfenster, gesperrte Zeile), kommen die gefundenen Berufe nur
        -- dazu: der gemerkte Stand wird nicht mit einer Lücke überschrieben (Fund der Gegenprüfung).
        if not fromApi then
            local result = profs
            if partial then
                result = {}
                for key, rank in pairs(CharProfMap(charKey) or EMPTY) do result[key] = rank end
                for key, rank in pairs(profs) do result[key] = rank end
            end
            -- Entwurf 1.6: nach chars[charKey].profs; ohne Satz in chars weiter der Altspeicher
            if not WriteSkillProfs(charKey, result) then db.charProfs[charKey] = result end
        end
        dynStamp = dynStamp + 1
    end
end

local function CurrentProfession()
    local key, rank, isOwn = nil, nil, true
    local api = C_TradeSkillUI
    if api then
        local ok, info = Call(api.GetBaseProfessionInfo)
        info = ok and S(info)
        if type(info) == "table" then
            key = PROF_BY_LINE[Num(info.professionID) or -1] or PROF_BY_LINE[Num(info.parentProfessionID) or -1]
                or ProfKeyFromName(info.professionName)
            rank = Num(info.skillLevel)
        end
        ok, info = Call(api.GetChildProfessionInfo)
        info = ok and S(info)
        if type(info) == "table" then
            key = key or PROF_BY_LINE[Num(info.parentProfessionID) or -1] or ProfKeyFromName(info.parentProfessionName)
            if Num(info.skillLevel) and info.skillLevel > 0 then rank = info.skillLevel end
        end
        if not key then
            local ok2, x, y, z = Call(api.GetTradeSkillLine)
            if ok2 and type(S(x)) == "number" then key, rank = PROF_BY_LINE[x] or ProfKeyFromName(y), Num(z)
            elseif ok2 and type(S(x)) == "string" then key, rank = ProfKeyFromName(x), Num(y) end
        end
        -- Fremd: verlinkt, Gilde, Gildenmitglied, NPC-Werkbank – EINE Stelle in Professions (V-026); Rückfall,
        -- solange Professions.lua (lädt nach diesem Teil) noch nicht da ist
        local P = ezCore.Professions
        if P and P.IsForeignTradeSkill then
            if P.IsForeignTradeSkill() then isOwn = false end
        else
            local okL, linked = Call(api.IsTradeSkillLinked)
            local okG, guild = Call(api.IsTradeSkillGuild)
            if (okL and S(linked)) or (okG and S(guild)) then isOwn = false end
        end
    end
    if not key and GetTradeSkillLine then
        local ok, name, r = pcall(GetTradeSkillLine)
        if ok then key, rank = ProfKeyFromName(name), Num(r) end
    end
    return key, rank, isOwn
end

local function SameRecipe(old, new)
    if not old or old.n ~= new.n or old.p ~= new.p or old.o ~= new.o then return false end
    for id, count in pairs(new.r) do
        if old.r == nil or old.r[id] ~= count then return false end
    end
    for id in pairs(old.r or EMPTY) do
        if new.r[id] == nil then return false end
    end
    return true
end

-- Ein Rezept speichern; true, wenn sich etwas geändert hat.
local function StoreRecipe(db, key, rec)
    -- Ein Produkt, das der Client einmal genannt hat, geht nicht verloren, wenn er es beim nächsten Lesen wieder nicht
    -- nennt. Zuordnungen laut AtlasLoot gehören nicht hierher (nur Sitzung, Recipes.lua).
    local old = db.recipes[key]
    if rec.o == nil and type(old) == "table" and old.o and old.os ~= "atlasloot" then rec.o, rec.os = old.o, old.os end
    if SameRecipe(old, rec) then return false end
    db.recipes[key] = rec
    for id in pairs(rec.r) do
        db.reagents[id] = db.reagents[id] or {}
        db.reagents[id][key] = true
        local name = ItemNameByID(id)
        if name then RememberName(name, id) end
    end
    if rec.o then
        db.created[rec.o] = key
        local name = ItemNameByID(rec.o)
        if name then RememberName(name, rec.o) end
    end
    return true
end

-- Grundzutat? (Enum.CraftingReagentType.Basic) Optionale und Veredelungs-Reagenzien zählen nicht.
function K.IsBasicReagentSlot(slot)
    if type(slot) ~= "table" or IsSecret(slot.required) or slot.required == false then return false end
    local basic = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
    local kind = S(slot.reagentType)
    if basic and kind ~= nil and kind ~= basic then return false end
    return true
end

-- Grundzutaten eines Rezept-Schemas (C_TradeSkillUI.GetRecipeSchematic): Karte { [itemID] = Anzahl } und
-- Liste { { itemID, count } } in der Reihenfolge des Rezepts. Ein Leser für Item-Wissen und ezCraft.
function K.BasicReagents(schem)
    local map, list = {}, {}
    schem = S(schem)
    local slots = type(schem) == "table" and S(schem.reagentSlotSchematics)
    for _, slot in ipairs(type(slots) == "table" and slots or EMPTY) do
        if K.IsBasicReagentSlot(slot) then
            local reagents = S(slot.reagents)
            local first = type(reagents) == "table" and S(reagents[1])
            local id = type(first) == "table" and Num(first.itemID)
            if id then
                local n = Num(slot.quantityRequired) or 1
                if map[id] then
                    map[id] = map[id] + n
                    for _, row in ipairs(list) do if row.itemID == id then row.count = row.count + n end end
                else
                    map[id] = n
                    list[#list + 1] = { itemID = id, count = n }
                end
            end
        end
    end
    return map, list
end

-- Produkt eines Rezepts (EC-102, DG-41; Spieltest 13.11.2026: 865 gelernte Rezepte, aber kein Rezept-Tooltip –
-- Verdacht: outputItemID fehlt auf Forever). Reihenfolge: outputItemID des Schemas, dann
-- C_TradeSkillUI.GetRecipeOutputItemData, dann der Gegenstands-Link des Rezepts (GetRecipeItemLink); AtlasLoot erst
-- danach (K.RecipeFor in Recipes.lua, über Core.Sources). Jede Antwort mit Formprüfung (Felder dürfen leer oder
-- gesperrt sein); ohne Antwort bleibt alles wie bisher (o = nil). → itemID, Quelle ("schematic" | "output" | "link")
-- DG-44 gemessen (Spieltest 15.11.2026, Build 70938, deDE): GetRecipeOutputItemData(2330) liefert bei offenem
-- Berufefenster nur { icon = … } – keine itemID, keinen Link. Auf Forever kommt das Produkt deshalb aus dem Schema
-- bzw. dem Rezept-Link; der Aufruf bleibt mit Formprüfung für andere Clients stehen (ohne Feld fällt er durch).
local function ItemFromLink(link)
    link = Str(link)
    return link and ezCore.ItemID(link) or nil   -- Core.ItemID statt eigenem Muster (T16-16)
end
K.ItemFromLink = ItemFromLink

function K.RecipeProduct(recipeID, schem)
    schem = S(schem)
    local id = type(schem) == "table" and Num(S(schem.outputItemID))
    if id and id > 0 then return id, "schematic" end
    local api = C_TradeSkillUI
    if not (api and recipeID) then return nil end
    local okO, out = Call(api.GetRecipeOutputItemData, recipeID)
    out = okO and S(out)
    if type(out) == "table" then
        id = Num(S(out.itemID))
        if id and id > 0 then return id, "output" end
        id = ItemFromLink(S(out.hyperlink))
        if id then return id, "output" end
    end
    local okL, link = Call(api.GetRecipeItemLink, recipeID)
    id = okL and ItemFromLink(S(link))
    if id then return id, "link" end
    return nil
end

local function LearnRetail(db, prof, isOwn, rank)
    local api = C_TradeSkillUI
    local ok, ids = Call(api and api.GetAllRecipeIDs)
    ids = ok and S(ids)
    if type(ids) ~= "table" then return 0, false end
    local count, changed = 0, false
    for _, recipeID in ipairs(ids) do
        recipeID = Num(recipeID)
        local okI, info = Call(api.GetRecipeInfo, recipeID)
        local okS, schem = Call(api.GetRecipeSchematic, recipeID, false)
        info, schem = okI and S(info), okS and S(schem)
        -- Wer kann es, Skill-Stufen, Quelle (Recipes.lua) – im selben Durchgang, kein zweites Lesen
        if recipeID and type(info) == "table" and K.NoteRecipe then
            local okN, err = pcall(K.NoteRecipe, recipeID, info, prof, isOwn, rank)
            if not okN then K.lastError = err end
        end
        if recipeID and type(schem) == "table" then
            local product, from = K.RecipeProduct(recipeID, schem)
            local rec = { n = Str(type(info) == "table" and info.name) or Str(schem.name), p = prof,
                o = product, os = from ~= "schematic" and from or nil, r = (K.BasicReagents(schem)) }
            if rec.n or rec.o then
                count = count + 1
                if StoreRecipe(db, recipeID, rec) then changed = true end
            end
        end
    end
    return count, changed
end

-- Alte Classic-Schnittstelle (GetNumTradeSkills …), falls der Client sie noch hat.
local function LearnLegacy(db, prof)
    local okN, n = Call(GetNumTradeSkills)
    n = okN and Num(n) or 0
    local count, changed = 0, false
    for i = 1, n do
        local ok, name, kind = Call(GetTradeSkillInfo, i)
        name, kind = ok and Str(name), ok and S(kind)
        if name and kind ~= "header" and kind ~= "subheader" then
            local okL, link = Call(GetTradeSkillItemLink, i)
            link = okL and Str(link)
            local rec = { n = name, p = prof, o = link and ezCore.ItemID(link) or nil, r = {} }
            local okR, nr = Call(GetTradeSkillNumReagents, i)
            for j = 1, (okR and Num(nr) or 0) do
                local okRL, rlink = Call(GetTradeSkillReagentItemLink, i, j)
                local okRI, _, _, rcount = Call(GetTradeSkillReagentInfo, i, j)
                rlink = okRL and Str(rlink)
                local id = rlink and ezCore.ItemID(rlink) or nil
                if id then rec.r[id] = (okRI and Num(rcount)) or 1 end
            end
            count = count + 1
            if StoreRecipe(db, "L:" .. (prof or "?") .. ":" .. name, rec) then changed = true end
        end
    end
    return count, changed
end

-- Rang aus dem Fenster, für den die Berufsliste schon einmal neu gelesen wurde (je Beruf): Liefert GetProfessionInfo
-- den Rang später als das Fenster, löst nicht jedes TRADE_SKILL_LIST_UPDATE erneut Save, PROFESSIONS_CHANGED und
-- QueueReady aus (Fund der Prüfung)
local syncedRank = {}

-- Liest den offenen Beruf; Rückgabe: Anzahl gelesener Rezepte.
function K.LearnFromTradeSkill()
    local ok, count = pcall(function()
        Setup()
        local db = EnsureDB()
        if not db then return 0 end
        local prof, rank, isOwn = CurrentProfession()
        local n, changed = LearnRetail(db, prof, isOwn, rank)
        if n > 0 and K.NoteRecipesDone then ezCore.Try(nil, "Knowledge NoteRecipesDone", K.NoteRecipesDone, prof, isOwn) end
        if n == 0 then n, changed = LearnLegacy(db, prof) end
        if prof and isOwn and rank and ns.charKey then
            -- Das offene Fenster kennt den Rang früher als die Liste: die EINE Quelle neu lesen lassen (V-007).
            local known = CharProfRank(ns.charKey, prof)
            if known ~= rank and syncedRank[prof] ~= rank then
                syncedRank[prof] = rank
                local P = ezCore.Professions
                if GetProfessions and GetProfessionInfo and P and P.Save then
                    ezCore.Try(nil, "Professions.Save", P.Save)
                    known = CharProfRank(ns.charKey, prof)
                end
                -- Stimmt der Rang auch danach nicht (GetProfessions fehlt oder liefert nichts), merkt sich der
                -- Rückfall den Rang aus dem Fenster – wie vor V-007.
                if known ~= rank then
                    local map = {}
                    for key, r in pairs(CharProfMap(ns.charKey) or EMPTY) do map[key] = r end
                    map[prof] = rank
                    if not WriteSkillProfs(ns.charKey, map) then
                        db.charProfs[ns.charKey] = db.charProfs[ns.charKey] or {}
                        db.charProfs[ns.charKey][prof] = rank
                    end
                end
                dynStamp = dynStamp + 1
                if not changed then QueueReady(nil) end
            end
        end
        if changed then InvalidateAll(false) end
        return n
    end)
    if ok then return count end
    K.lastError = count
    return 0
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------

local timers = {}
local function Debounce(key, delay, fn)
    if timers[key] then return end
    timers[key] = true
    -- Fehler nicht schlucken: in die Fehlerliste (Core.Error), falls Core.lua geladen ist (ezBags Wissenstest lädt ohne).
    local function run()
        timers[key] = nil
        local ok, err = pcall(fn)
        if not ok then
            local C = rawget(_G, "ezCore")
            if type(C) == "table" and type(C.Error) == "function" then C.Error(C.name or "ezCore", err, "Knowledge " .. tostring(key)) end
        end
    end
    if C_Timer and C_Timer.After then C_Timer.After(delay, run) else run() end
end

-- TRADE_SKILL_LIST_UPDATE kommt bei jedem Herstellen: dann höchstens alle 10 s neu lesen.
local lastLearn = 0
local function LearnSoon(force)
    local now = GetTime and GetTime() or 0
    if not force and now - lastLearn < 10 then return end
    Debounce("learn", 0.5, function()
        lastLearn = GetTime and GetTime() or 0
        K.LearnFromTradeSkill()
    end)
end

local function ItemArrived(_, itemID)
    itemID = Num(itemID)
    if itemID then OnLoaded(itemID) end
end

-- Über Core.lua (ns.On). Ist Core noch nicht geladen, holt Setup() das beim ersten Gebrauch nach.
RegisterEvents = function()
    if eventsRegistered or type(ns.On) ~= "function" then return end
    eventsRegistered = true
    local On = ns.On
    On("GET_ITEM_INFO_RECEIVED", ItemArrived)
    On("ITEM_DATA_LOAD_RESULT", ItemArrived)
    On("PLAYER_LEVEL_UP", function(_, level)
        levelOverride = Num(level)
        dynStamp = dynStamp + 1
        QueueReady(nil)
    end)
    On("PLAYER_LOGIN", function()
        wipe(profNames)
        profByName = nil
        EnsureDB()
        dynStamp = dynStamp + 1
        Debounce("profs", 3, RefreshCharProfs)
    end)
    On("SKILL_LINES_CHANGED", function() Debounce("profs", 1, RefreshCharProfs) end)
    -- Die Berufe-Quelle hat neu gelesen: veränderliche Aussagen („erlernbar“, „dein Beruf“) neu rechnen.
    if ezCore.Listen then
        ezCore.Listen("PROFESSIONS_CHANGED", function()
            dynStamp = dynStamp + 1
            QueueReady(nil)
        end, "ezCore.Knowledge")
    end
    On("TRADE_SKILL_SHOW", function() LearnSoon(true) end)
    On("TRADE_SKILL_DATA_SOURCE_CHANGED", function() LearnSoon(true) end)
    On("TRADE_SKILL_LIST_UPDATE", function() LearnSoon(false) end)
    On("NEW_RECIPE_LEARNED", function()
        -- "Bereits bekannt" steht im Tooltip: Rezept-facts neu bauen.
        InvalidateAll(false)
        LearnSoon(true)
    end)
end
RegisterEvents()

-- Entwurf 1.6: knowledge.charProfs einmal nach chars[charKey].profs übernehmen, sobald die Charaktere geladen sind
if ezCore.Listen then
    ezCore.Listen("CHARS_READY", function()
        EnsureDB()
        ezCore.Try(nil, "Knowledge.MigrateCharProfs", K.MigrateCharProfs)
    end, "ezCore.Knowledge")
end
