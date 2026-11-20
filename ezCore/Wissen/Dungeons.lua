local ADDON, ns = ...
local Core = ezCore
local Dungeons = Core.Dungeons

--[[
    Dungeon- und Zonen-Tabelle: eine Quelle für ezSocial (Gruppensuche, Chat), ezMap (Zonenstufen, Eingänge)
    und ezQuest (Dungeon-Quests).

    Name, Kurzname, Stufen und Spielerzahl kommen aus Blizzards Gruppensuche (C_LFGList, Kategorien
    Dungeons und Schlachtzüge) – in der Sprache des Clients und mit allen Forever-Dungeons. DungeonData.lua
    ergänzt nur die Chat-Kürzel (de/en) und Ersatzwerte, solange die Gruppensuche nichts liefert.

      Dungeons.All(art)            → Liste { key, mapID, kind, name, minLevel, maxLevel, minAllowed, players,
                                     wings = { { activityID, name, short, minLevel, maxLevel, players } }, fromClient }
                                     nach Stufe; art "dungeon" oder "raid" (optional)
      Dungeons.Get(id oder Name)   → Eintrag (Instanz-ID, Name, Flügel-Name oder Kürzel)
      Dungeons.Match(text)         → Eintrag, Kürzel – längstes Kürzel, das als eigenes Wort im Text steht
      Dungeons.MatchAll(text)      → Liste der genannten Einträge (ohne Doppelte)
      Dungeons.ForLevel(stufe, art) → Einträge, deren empfohlener Bereich die Stufe enthält (ohne Stufe: die eigene;
                                     art "dungeon" oder "raid" grenzt ein)
      Dungeons.Current()           → Eintrag der Instanz, in der der Spieler gerade ist
      Dungeons.Difficulty(min, max, stufe) → "red" (zu schwer), "white" (passt), "grey" (zu leicht)
      Dungeons.DifficultyOf(eintrag, stufe), Dungeons.Color(schlüssel) → r, g, b
      Dungeons.ZoneLevels(uiMapID) → min, max (C_Map.GetMapLevels) oder nil, grund: "invalid" (keine Karten-ID),
                                     "noapi" (Client ohne die Abfrage), "nodata" (der Client liefert für die Karte
                                     nichts bzw. 0–0), "secret". Forever (Spieltest 14.11.2026, Wald von Elwynn):
                                     "nodata" – die Abfrage gibt es (Blizzards Forever-Quelle, MayReturnNothing),
                                     sie liefert für die Gebiete aber nichts. Einen Ersatz gibt es noch nicht.
      Dungeons.ZoneDifficulty(uiMapID, stufe) → Farbe oder nil (ohne Zonenstufen)
      Dungeons.Entrances(uiMapID, opts) → { { name, x, y, entry, source } } – was der Client liefert ("client");
                                     Forever liefert keine (Spieltest 14.11.2026: leere Liste) – mit opts.own = true
                                     dann die selbst betretenen Eingänge der Entdecker-Datenbank ("own", Welle 9;
                                     ab Werk aus, bis ezMap in Welle 10 umstellt); Ersatz für den Text:
                                     EntranceZone (Gebiet je Dungeon) und der Speicher von ezMap (bis Welle 10)
      Dungeons.EntranceZoneMap(id) → uiMapID, info – Karte des Gebiets mit dem Eingang (EntranceZone über
                                     Core.Map.ByName, Welle 23c), sonst nil
      Dungeons.EntranceMap(id)     → uiMapID, x, y, "own" – Eingang aus dem eigenen Fund, sonst nil
      Dungeons.EntranceLabel(id)   → „Westfall (bei dir)“, "own" | Gebiet aus der Tabelle, "data" | nil
      Dungeons.Refresh()           die Tabelle beim nächsten Zugriff neu aus der Gruppensuche lesen
      Nachricht DUNGEONS_CHANGED, sobald die Gruppensuche neue Daten geliefert hat.

    Name eines Dungeons mit mehreren Flügeln (Spieltest 14.11.2026: Düsterbruch hieß „Dungeons“ und bekam das
    Kürzel „dungeons“): Der Name der Aktivitätsgruppe (GetActivityGroupInfo) gilt nur, wenn er wirklich diesen
    Dungeon meint – nicht, wenn er der Name der Kategorie ist („Dungeons“, „Schlachtzüge“) oder wenn mehrere
    Instanzen ihn teilen. Sonst: der Ersatzname aus DungeonData.lua, dann der gemeinsame Anfang der Flügelnamen
    („Düsterbruch – Ost“/„– West“ → „Düsterbruch“; nicht, wenn nur ein Füllwort übrig bleibt), zuletzt der erste
    Flügel. Kürzel entstehen nie aus einem Kategorie- oder Gattungsnamen und nie aus einem bloßen Lagewort eines
    Flügel-Kurznamens („Ost“, „West“, „Upper“ – Dungeons.WINGWORDS); ein Gruppenname, den mehrere Instanzen teilen,
    wird nur als Name verworfen, nicht als Kürzel gesperrt.
]]

local DUNGEON_CATEGORY, RAID_CATEGORY = 2, 114   -- Blizzards Gruppensuche im Classic-Stil (LFGVanilla_Constants.lua)
local STOP, WINGWORD = Dungeons.STOPWORDS, Dungeons.WINGWORDS

local entries, byKey, dirty = {}, {}, true
local RETRY = 10    -- ohne Gruppensuche frühestens nach so vielen Sekunden erneut versuchen
local retryAt

local function Lower(text)
    text = string.lower(text)
    return (text:gsub("Ä", "ä"):gsub("Ö", "ö"):gsub("Ü", "ü"))
end
Dungeons.Lower = Lower

-- Namen, die nie Kürzel werden: Kategorien der Gruppensuche und Gruppennamen, die eine Kategorie oder Gattung
-- nennen (klein geschrieben; je Aufbau der Tabelle neu gefüllt). Ein echter Dungeonname, den mehrere Instanzen
-- als Gruppe teilen, steht NICHT hier – er taugt nur nicht als Name jeder einzelnen, bleibt aber ein Kürzel.
local blocked = {}

local function AddAbbr(entry, text)
    text = Core.Plain(text)
    if type(text) ~= "string" then return end
    text = Lower(Core.Trim(text))
    if text ~= "" and not STOP[text] and not WINGWORD[text] and not blocked[text] then entry.abbr[text] = true end
end

-- Anfangsbuchstaben bei mindestens zwei Wörtern: „Barrow Deeps“ → „bd“ (für neue Dungeons ohne Kürzel).
local function Initials(name)
    local letters = {}
    for word in Lower(name):gmatch("[^%s%-%(%):,]+") do
        if not STOP[word] then letters[#letters + 1] = word:match("^[%z\1-\127\194-\244][\128-\191]*") end
    end
    return #letters >= 2 and table.concat(letters) or nil
end

local function NewEntry(mapID)
    local static = Dungeons.DATA[mapID]
    local entry = {
        key = mapID, mapID = mapID, kind = static and static.kind or "dungeon",
        name = static and (Core.IsGerman() and static.de or static.en) or nil,
        minLevel = static and static.min, maxLevel = static and static.max,
        players = static and (static.kind == "raid" and 40 or 5) or nil,
        abbr = {}, wings = {}, fromClient = false,
    }
    if static then
        for _, text in ipairs(static.abbr or {}) do AddAbbr(entry, text) end
        AddAbbr(entry, static.de)
        AddAbbr(entry, static.en)
    end
    return entry
end

local function GroupName(groupID)
    if not (groupID and groupID > 0 and C_LFGList and C_LFGList.GetActivityGroupInfo) then return nil end
    local ok, name = pcall(C_LFGList.GetActivityGroupInfo, groupID)
    name = ok and Core.Plain(name)
    return type(name) == "string" and name ~= "" and name or nil
end

-- Name einer Kategorie der Gruppensuche („Dungeons“, „Schlachtzüge“) – kein Dungeonname.
local function CategoryName(category)
    local api = C_LFGList and C_LFGList.GetLfgCategoryInfo
    if type(api) ~= "function" then return nil end
    local ok, info = pcall(api, category)
    if not ok then return nil end
    local name = info
    if not Core.IsSecret(info) and type(info) == "table" then name = Core.Peek(info, "name") end
    name = Core.Plain(name)
    return type(name) == "string" and name ~= "" and name or nil
end

-- Gemeinsamer Anfang der Flügelnamen, an einer Wortgrenze: „Düsterbruch – Ost“, „Düsterbruch – West“ →
-- „Düsterbruch“; nil, wenn weniger als drei Zeichen oder nur Füllwörter übrig bleiben („Der Obere Schlund“,
-- „Der Untere Schlund“ → „Der“ ist kein Name).
local function IsNameByte(c)
    return c ~= "" and (c:find("^[%w']") ~= nil or c:byte() >= 128)
end

local function CommonPrefix(wings)
    local first = wings[1] and wings[1].name
    if type(first) ~= "string" then return nil end
    local len = #first
    for i = 2, #wings do
        local name = wings[i].name
        if type(name) ~= "string" then return nil end
        local n = 0
        while n < len and n < #name and first:byte(n + 1) == name:byte(n + 1) do n = n + 1 end
        len = n
    end
    -- endet der gemeinsame Teil mitten in einem Wort, zurück bis hinter das letzte ganze Wort
    local cutsWord = false
    for _, wing in ipairs(wings) do
        if IsNameByte(wing.name:sub(len + 1, len + 1)) then cutsWord = true end
    end
    if cutsWord then
        while len > 0 and IsNameByte(first:sub(len, len)) do len = len - 1 end
    end
    local prefix = first:sub(1, len)
    -- Trenner am Ende weg: Leerraum, Bindestrich, Doppelpunkt, Klammer, Komma, Halbgeviert- und Geviertstrich
    local changed = true
    while changed do
        changed = false
        local trimmed = prefix:gsub("[%s%-:%(,/]+$", "")
        for _, dash in ipairs({ "–", "—" }) do
            if trimmed:sub(-#dash) == dash then trimmed = trimmed:sub(1, -#dash - 1) end
        end
        if trimmed ~= prefix then prefix, changed = trimmed, true end
    end
    if #prefix < 3 then return nil end
    local named = false
    for word in Lower(prefix):gmatch("[^%s%-%(%):,/]+") do
        if not STOP[word] and not WINGWORD[word] then named = true end
    end
    if not named then return nil end
    return prefix
end

-- Aus der Gruppensuche lesen; false, wenn sie (noch) nichts liefert.
-- Stufen einer Aktivität der Gruppensuche – eine Regel für die Dungeon-Tabelle und ezSocial:
-- empfohlen (Suggestion), sonst erlaubt (minLevel/maxLevel). activity: ID oder Info-Tabelle.
-- → min, max, minAllowed (fehlende Werte nil) oder nil.
function Dungeons.ActivityLevels(activity)
    local info = activity
    if type(activity) ~= "table" then
        local LFG = C_LFGList
        if not (LFG and LFG.GetActivityInfoTable) or activity == nil then return nil end
        local ok, result = pcall(LFG.GetActivityInfoTable, activity)
        info = ok and result or nil
    end
    if type(info) ~= "table" then return nil end
    local function Pos(v) v = Core.Num(v) return v and v > 0 and v or nil end
    local low, high = Pos(info.minLevelSuggestion), Pos(info.maxLevelSuggestion)
    if not (low or high) then low, high = Pos(info.minLevel), Pos(info.maxLevel) end
    if not (low or high) then return nil end
    return low, high, Pos(info.minLevel)
end

local function ReadClient(into)
    local LFG = C_LFGList
    if not (LFG and LFG.GetAvailableActivities and LFG.GetActivityInfoTable) then return false end
    local found = false
    for _, category in ipairs({ DUNGEON_CATEGORY, RAID_CATEGORY }) do
        local ok, ids = pcall(LFG.GetAvailableActivities, category)
        for _, activityID in ipairs(ok and type(ids) == "table" and ids or {}) do
            local okInfo, info = pcall(LFG.GetActivityInfoTable, activityID)
            local mapID = okInfo and type(info) == "table" and Core.Num(info.mapID)
            local name = mapID and Core.Plain(info.fullName)
            if mapID and mapID > 0 and type(name) == "string" and name ~= "" then
                found = true
                local entry = into[mapID]
                if not entry then
                    entry = NewEntry(mapID)
                    into[mapID] = entry
                end
                entry.fromClient = true
                if category == RAID_CATEGORY then entry.kind = "raid" end
                local minLevel, maxLevel, minAllowed = Dungeons.ActivityLevels(info)
                entry.wings[#entry.wings + 1] = {
                    activityID = activityID, name = name, short = Core.Plain(info.shortName),
                    minLevel = minLevel, maxLevel = maxLevel, minAllowed = minAllowed,
                    players = Core.Num(info.maxNumPlayers), groupID = Core.Num(info.groupFinderActivityGroupID),
                }
            end
        end
    end
    return found
end

-- Werte des Eintrags aus seinen Flügeln (ein Flügel: dessen Name; mehrere: Name der Gruppe, wenn er diesen Dungeon
-- meint – entry.groupName setzt Build nur dann –, sonst Ersatzname, gemeinsamer Anfang, erster Flügel).
local function Summarize(entry)
    local wings = entry.wings
    if #wings == 0 then return end
    local lo, hi, allowed, players
    for _, wing in ipairs(wings) do
        if wing.minLevel and (not lo or wing.minLevel < lo) then lo = wing.minLevel end
        if wing.maxLevel and (not hi or wing.maxLevel > hi) then hi = wing.maxLevel end
        if wing.minAllowed and (not allowed or wing.minAllowed < allowed) then allowed = wing.minAllowed end
        if wing.players and (not players or wing.players > players) then players = wing.players end
        AddAbbr(entry, wing.name)
        AddAbbr(entry, wing.short)
    end
    entry.minLevel, entry.maxLevel = lo or entry.minLevel, hi or entry.maxLevel
    entry.minAllowed, entry.players = allowed, players or entry.players
    if players and players > 5 then entry.kind = "raid" end
    if #wings == 1 then
        entry.name = wings[1].name
    else
        entry.name = entry.groupName or entry.name or CommonPrefix(wings) or wings[1].name
    end
    if not Dungeons.DATA[entry.mapID] then
        local initials = Initials(entry.name or "")
        if initials and #initials >= 2 then AddAbbr(entry, initials) end
    end
    AddAbbr(entry, entry.name)
end

-- Gruppennamen prüfen: Kategorie-Namen und Namen, die mehrere Instanzen teilen, sind kein Dungeonname.
-- Setzt entry.groupName für die echten und füllt „blocked“ mit den Kategorie- und Gattungsnamen (nie Kürzel).
-- Ein von mehreren Instanzen geteilter Gruppenname wird nur als Name verworfen: Heißt eine davon wirklich so
-- (Ersatzname, Flügelname), bleibt ihr Name als Kürzel erhalten.
local function ResolveGroupNames(map)
    blocked = {}
    for _, category in ipairs({ DUNGEON_CATEGORY, RAID_CATEGORY }) do
        local name = CategoryName(category)
        if name then blocked[Lower(name)] = true end
    end
    local names, users = {}, {}      -- [mapID] = Gruppenname; [name klein] = Zahl der Instanzen
    for mapID, entry in pairs(map) do
        local first = #entry.wings > 1 and entry.wings[1]
        local name = first and GroupName(first.groupID)
        if name then
            names[mapID] = name
            local low = Lower(name)
            users[low] = (users[low] or 0) + 1
        end
    end
    for mapID, name in pairs(names) do
        local low = Lower(name)
        if blocked[low] or STOP[low] then
            blocked[low] = true
        elseif users[low] == 1 then
            map[mapID].groupName = name
        end
    end
end

local function Build()
    local map = {}
    blocked = {}
    local fromClient = ReadClient(map)
    if not fromClient then
        for mapID in pairs(Dungeons.DATA) do map[mapID] = NewEntry(mapID) end
    else
        ResolveGroupNames(map)
        -- Kürzel aus den Ersatzdaten, die schon in NewEntry entstanden sind, gegen die Sperrliste prüfen
        for _, entry in pairs(map) do
            for abbr in pairs(entry.abbr) do
                if blocked[abbr] then entry.abbr[abbr] = nil end
            end
        end
    end
    local list = {}
    for _, entry in pairs(map) do
        Summarize(entry)
        if entry.name then list[#list + 1] = entry end
    end
    table.sort(list, function(a, b)
        if (a.minLevel or 0) ~= (b.minLevel or 0) then return (a.minLevel or 0) < (b.minLevel or 0) end
        return a.name < b.name
    end)
    entries, byKey = list, map
    -- Ohne Gruppensuche die Ersatzwerte behalten und frühestens nach RETRY Sekunden erneut lesen
    -- (vorher bei jedem Aufruf); die Ereignisse unten lösen sofort ein neues Lesen aus.
    dirty = false
    retryAt = not fromClient and ((GetTime and GetTime() or 0) + RETRY) or nil
    return fromClient
end

local function Ensure()
    if not dirty and retryAt and GetTime and GetTime() >= retryAt then dirty = true end
    if dirty then
        local hadClient = #entries > 0 and entries[1].fromClient
        local fromClient = Build()
        if fromClient and not hadClient then Core.Fire("DUNGEONS_CHANGED") end
    end
    return entries
end

-- Beim nächsten Zugriff neu aus der Gruppensuche lesen (sonst liest die Tabelle nur, bis der Client Daten hat).
function Dungeons.Refresh()
    dirty = true
end

function Dungeons.All(kind)
    local out = {}
    for _, entry in ipairs(Ensure()) do
        if not kind or entry.kind == kind then out[#out + 1] = entry end
    end
    return out
end

function Dungeons.Get(id)
    Ensure()
    if type(id) == "number" then return byKey[id] end
    if type(id) ~= "string" or Core.IsSecret(id) or id == "" then return nil end
    local low = Lower(Core.Trim(id))
    for _, entry in ipairs(entries) do
        if entry.name and Lower(entry.name) == low then return entry end
        for _, wing in ipairs(entry.wings) do
            if Lower(wing.name) == low or (wing.short and Lower(wing.short) == low) then return entry end
        end
    end
    for _, entry in ipairs(entries) do
        if entry.abbr[low] then return entry end
    end
    return nil
end

local function IsWordByte(c)
    if c == "" then return false end
    return c:find("^[%w']") ~= nil or c:byte() >= 128
end

local function FindWord(low, abbr)
    local init = 1
    while true do
        local s, e = low:find(abbr, init, true)
        if not s then return false end
        if not IsWordByte(low:sub(s - 1, s - 1)) and not IsWordByte(low:sub(e + 1, e + 1)) then return true end
        init = s + 1
    end
end

-- Längstes Kürzel, das als eigenes Wort im Text steht („dm e“ schlägt „dm“).
function Dungeons.Match(text)
    if type(text) ~= "string" or Core.IsSecret(text) then return nil end
    local low = Lower(text)
    local best, bestAbbr
    for _, entry in ipairs(Ensure()) do
        for abbr in pairs(entry.abbr) do
            if (not bestAbbr or #abbr > #bestAbbr) and FindWord(low, abbr) then best, bestAbbr = entry, abbr end
        end
    end
    return best, bestAbbr
end

function Dungeons.MatchAll(text)
    if type(text) ~= "string" or Core.IsSecret(text) then return {} end
    local low = Lower(text)
    local hits = {}
    for _, entry in ipairs(Ensure()) do
        local longest
        for abbr in pairs(entry.abbr) do
            if (not longest or #abbr > #longest) and FindWord(low, abbr) then longest = abbr end
        end
        if longest then hits[#hits + 1] = { entry = entry, abbr = longest } end
    end
    -- „dm“ (Todesminen) zählt nicht, wenn es Teil eines längeren Treffers ist („dm e“ = Düsterbruch).
    local out = {}
    for _, hit in ipairs(hits) do
        local inside = false
        for _, other in ipairs(hits) do
            if other ~= hit and #other.abbr > #hit.abbr and other.abbr:find(hit.abbr, 1, true) then inside = true end
        end
        if not inside then out[#out + 1] = hit.entry end
    end
    return out
end

-- Einträge, deren empfohlener Bereich die Stufe enthält (ohne Stufe: die eigene), nach Stufe sortiert wie All().
-- kind = "dungeon" | "raid" grenzt ein. Die Namen sind die von All() (nie der Kategoriename der Gruppensuche –
-- der Fund aus dem Spieltest ist in Build behoben); ein Eintrag ohne brauchbaren Namen bleibt weg. Eine gesperrte
-- Stufe zählt wie keine Angabe.
function Dungeons.ForLevel(level, kind)
    if Core.IsSecret(level) then level = nil end
    level = Core.Num(level) or tonumber(level) or Core.PlayerLevel() or 1
    local out = {}
    for _, entry in ipairs(Ensure()) do
        if (kind == nil or entry.kind == kind) and type(entry.name) == "string" and entry.name ~= ""
            and entry.minLevel and entry.maxLevel and level >= entry.minLevel and level <= entry.maxLevel then
            out[#out + 1] = entry
        end
    end
    return out
end

function Dungeons.Current()
    if not GetInstanceInfo or Core.InInstance() == false then return nil end
    local ok, _, instanceType, _, _, _, _, _, instanceID = pcall(GetInstanceInfo)
    instanceType, instanceID = ok and Core.Plain(instanceType), ok and Core.Num(instanceID)
    if not instanceID or instanceType == "none" then return nil end
    return Dungeons.Get(instanceID)
end

---------------------------------------------------------------------------
-- Stufen und Farben
---------------------------------------------------------------------------

local COLORS = { red = { 1, 0.25, 0.25 }, white = { 1, 1, 1 }, grey = { 0.55, 0.55, 0.55 } }

function Dungeons.Difficulty(minLevel, maxLevel, level)
    level = tonumber(level) or (UnitLevel and Core.Num(UnitLevel("player"))) or 1
    if not (minLevel and maxLevel) then return nil end
    if level < minLevel then return "red" end
    if level > maxLevel then return "grey" end
    return "white"
end

function Dungeons.DifficultyOf(entry, level)
    if type(entry) ~= "table" then return nil end
    return Dungeons.Difficulty(entry.minLevel, entry.maxLevel, level)
end

-- „Die Todesminen (17–26)“ in der Farbe der Schwierigkeit für die Stufe (Standard: die eigene) – eine
-- Beschriftung für ezQuest, ezMap und ezSocial. → farbiger Text, Klartext, r, g, b; nil ohne Namen.
-- opts.range = false lässt die Stufen weg.
function Dungeons.Label(entry, level, opts)
    if type(entry) ~= "table" or type(entry.name) ~= "string" then return nil end
    local plain = entry.name
    local lo, hi = Core.Num(entry.minLevel), Core.Num(entry.maxLevel)
    if lo and hi and not (opts and opts.range == false) then plain = plain .. (" (%d–%d)"):format(lo, hi) end
    local r, g, b = 1, 0.82, 0
    local key = Dungeons.DifficultyOf(entry, level)
    if key then r, g, b = Dungeons.Color(key) end
    return Core.ColorCode(r, g, b) .. plain .. "|r", plain, r, g, b
end

function Dungeons.Color(key)
    local c = COLORS[key] or COLORS.white
    return c[1], c[2], c[3]
end

-- Stufenbereich eines Gebiets aus dem Client. → min, max oder nil, grund ("invalid", "noapi", "nodata", "secret").
-- Forever liefert für die Gebiete nichts ("nodata", Spieltest 14.11.2026) – wer die Stufen zeigt, sagt das dazu
-- (Leitlinie 11: nie stumm) oder lässt die Angabe weg.
function Dungeons.ZoneLevels(uiMapID)
    if Core.IsSecret(uiMapID) then return nil, "secret" end
    uiMapID = tonumber(uiMapID)
    if not uiMapID then return nil, "invalid" end
    if not (C_Map and C_Map.GetMapLevels) then return nil, "noapi" end
    local ok, lo, hi = pcall(C_Map.GetMapLevels, uiMapID)
    if not ok then return nil, "nodata" end
    if Core.IsSecret(lo) or Core.IsSecret(hi) then return nil, "secret" end
    lo, hi = Core.Num(lo), Core.Num(hi)
    if not (lo and hi) or (lo <= 0 and hi <= 0) then return nil, "nodata" end
    return lo, hi
end

function Dungeons.ZoneDifficulty(uiMapID, level)
    local lo, hi = Dungeons.ZoneLevels(uiMapID)
    if not lo then return nil end
    return Dungeons.Difficulty(lo, hi, level)
end

-- Gebiet mit dem Eingang eines Dungeons (Instanz-ID, Name, Kürzel oder Eintrag) in der Spielsprache, sonst nil.
function Dungeons.EntranceZone(id)
    local entry = type(id) == "table" and id or Dungeons.Get(id)
    local key = type(entry) == "table" and (entry.id or entry.mapID or entry.key) or (type(id) == "number" and id or nil)
    local pair = key and Dungeons.ENTRANCES and Dungeons.ENTRANCES[key]
    if not pair then return nil end
    return Core.IsGerman() and pair[1] or pair[2]
end

-- Karte des Gebiets mit dem Eingang (Welle 23c, A30): Dungeons.ENTRANCES führt nur den Namen; die uiMapID kommt aus
-- Blizzards Kartenbaum (Core.Map.ByName, Zone vor gleichnamigen Karten). → uiMapID, info oder nil
function Dungeons.EntranceZoneMap(id)
    local zone = Dungeons.EntranceZone(id)
    if not zone then return nil end
    return Core.Map.ByName(zone, "Zone")
end

-- Eingänge auf einer Karte, falls der Client sie kennt (C_EncounterJournal.GetDungeonEntrancesForMap). Forever kennt
-- die Abfrage, liefert aber eine leere Liste (Spieltest 14.11.2026, Wald von Elwynn) – die Rückgabe ist dann {}.
-- Nur ezCore-intern; öffentlich ist Dungeons.Entrances unten (Gesamtreview 18.11.2026, T16-17: vorher zweimal unter
-- demselben Namen definiert, die zweite Fassung umhüllte die erste).
local function ClientEntrances(uiMapID)
    local out = {}
    uiMapID = tonumber(uiMapID)
    local EJ = C_EncounterJournal
    if not (uiMapID and EJ and EJ.GetDungeonEntrancesForMap) then return out end
    local ok, list = pcall(EJ.GetDungeonEntrancesForMap, uiMapID)
    for _, info in ipairs(ok and type(list) == "table" and list or {}) do
        local name = Core.Plain(info.name)
        local x, y = Core.Map.XY(info.position)
        if type(name) == "string" and x and y then
            out[#out + 1] = { name = name, x = x, y = y, entry = Dungeons.Get(name), source = "client" }
        end
    end
    return out
end

-- Eingänge auf einer Karte: was der Client liefert; mit opts.own = true als Rückfall die selbst betretenen Eingänge
-- der Entdecker-Datenbank (Welle 9; Quelle je Zeile in source = "client" | "own"). Ab Werk ohne Rückfall, weil ezMap
-- bis zu seinem Paket (Welle 10) eigene Eingänge daneben zeigt – sonst stünde derselbe Eingang doppelt da.
function Dungeons.Entrances(uiMapID, opts)
    local out = ClientEntrances(uiMapID)
    local own = type(opts) == "table" and opts.own == true
    if #out > 0 or not own or not (Core.Entrances and Core.Entrances.OnMap) then return out end
    for _, e in ipairs(Core.Entrances.OnMap(tonumber(uiMapID))) do
        local entry = Dungeons.Get(e.inst)
        out[#out + 1] = { name = entry and entry.name or ("#" .. tostring(e.inst)), x = e.x, y = e.y, entry = entry,
            source = "own", cnt = e.cnt }
    end
    return out
end

-- Wo liegt der Eingang eines Dungeons? → uiMapID, x, y, Quelle ("own") – nur aus selbst betretenen Eingängen
-- (das Journal liefert auf Forever keine, Probe 14.11.2026). Ohne eigenen Fund: nil.
function Dungeons.EntranceMap(id)
    local entry = type(id) == "table" and id or Dungeons.Get(id)
    local inst = type(entry) == "table" and (entry.id or entry.mapID) or (type(id) == "number" and id or nil)
    local row = inst and Core.Entrances and Core.Entrances.Of(inst)
    local best
    for _, p in ipairs(row and row.places or {}) do
        if p.x and p.y and (not best or (p.cnt or 0) > (best.cnt or 0)) then best = p end
    end
    if not best then return nil end
    return best.map, best.x, best.y, "own"
end

-- Text zum Eingang mit Quelle: „Westfall (bei dir)“ aus dem eigenen Fund, sonst das Gebiet aus der Tabelle
-- (EntranceZone). → Text, Quelle ("own" | "data") oder nil
function Dungeons.EntranceLabel(id)
    local map = Dungeons.EntranceMap(id)
    if map then
        local info = Core.Map.Info(map)
        local name = type(info) == "table" and Core.Plain(info.name) or nil
        if type(name) == "string" and name ~= "" then return Core.L.DB_ENTRANCE_OWN:format(name), "own" end
    end
    local zone = Dungeons.EntranceZone(id)
    if zone then return zone, "data" end
    return nil
end

---------------------------------------------------------------------------
-- Ereignisse: neu lesen, sobald die Gruppensuche Daten hat
---------------------------------------------------------------------------

for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "LFG_LIST_AVAILABILITY_UPDATE" }) do
    ns.On(event, function()
        if not (#entries > 0 and entries[1].fromClient) then dirty = true end
    end)
end
