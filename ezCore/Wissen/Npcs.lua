local _, ns = ...
local Core = ezCore
local L = Core.L

--[[
    NPC-Ortswissen – EINE Quelle für „wo steht Lehrer oder Händler X“ (Vollprüfung V-136; vorher Lehrer in
    ezMapDB.trainers mit Koordinaten, Händler im Item-Wissen nur als „Name (Zone)“).

    ezCore merkt sich jeden Lehrer und Händler, dessen Fenster du öffnest (TRAINER_SHOW, MERCHANT_SHOW):
      ezCoreDB.npcs[npcID] = { name, title, trainer = "class" | "profession" | "pet" | "other", vendor = true, repair = true,
                               class (Klassenlehrer: Klassen-Kürzel), faction, map (uiMapID), x, y (0–1), zone, seen }
    Ein NPC kann beides sein. Keine mitgelieferten Daten, keine Kartensymbole – nur das, was besucht wurde.

      Npcs.Get(npcID)            → Kopie des Eintrags mit .id oder nil
      Npcs.List(filter)          → Kopien, sortiert nach Gebiet und Name. filter = { kind = "trainer" | "vendor",
                                   trainer = "class" | "profession" | "pet" | "other", repair = true, map = uiMapID,
                                   located = true (nur mit Koordinaten), fits = true (passt zu diesem Charakter) }
      Npcs.Find(name)            → Liste der Einträge mit diesem Namen (Groß/Klein egal)
      Npcs.Where(npcID | name)   → uiMapID, x, y, Eintrag (nil ohne gemerkte Koordinaten; bei mehreren der zuletzt gesehene)
      Npcs.Fits(eintrag)         → Klassenlehrer nur der eigenen Klasse, nur eigene Fraktion
      Npcs.Label(eintrag)        → „Name (Titel)“
      Npcs.KindLabel(eintrag)    → „Klassenlehrer“, „Berufslehrer“, „Lehrer“, „Händler“
      Npcs.Count(kind)           → Anzahl; Npcs.Forget(npcID | "trainer" | "vendor" | nil) → Anzahl vergessener
      Npcs.Learn(kind)           → merkt den NPC, mit dem gerade gesprochen wird (intern)
      Nachricht: NPCS_CHANGED (npcID, kind)

    Das Händler-Wissen (Knowledge.VendorSources) nennt über die NPC-ID dieselben Koordinaten.
    Einmalige Übernahme aus ezMapDB.trainers (die alten Daten bleiben liegen, migrated.ezMapTrainers).

    Mit Träger ezWorld und nach der Übernahme in die Entdecker-Datenbank (Discovery.Moved("npcs")) lesen und schreiben
    alle Funktionen dieselbe Form aus den Tabellen npc, spot und text (DiscoveryLegacy.lua); ezCoreDB.npcs bleibt
    liegen und wird nicht mehr geschrieben – auch MigrateTrainers und SortPetTrainers schreiben dann in die neuen
    Tabellen. Ohne Träger bleibt es bei ezCoreDB.npcs.

    Zerleger der Objekt-GUID neben Core.NpcID (Welle 23c, A29; vorher ezQuest Progress.ObjectIDFromGUID):
      Core.ObjectID(guid)        → objectID aus „GameObject-0-…-<id>-…“ (Feld 6) oder nil (gesperrt, keine Objekt-GUID)
]]

local Npcs = {}
Core.Npcs = Npcs

function Core.ObjectID(guid)
    if Core.IsSecret(guid) or type(guid) ~= "string" then return nil end
    return tonumber(guid:match("^GameObject%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
end

local Now = Core.Now

local function Text(value)
    value = Core.Plain(value)
    if type(value) == "string" and value ~= "" then return value end
    return nil
end

-- Umgezogen in die Entdecker-Datenbank? (DiscoveryLegacy.lua)
local function Moved()
    local D = Core.Discovery
    return D ~= nil and D.Moved ~= nil and D.Moved("npcs")
end

local function Store(create)
    local db = Core.db
    if type(db) ~= "table" then return nil end
    if type(db.npcs) ~= "table" then
        if not create then return nil end
        db.npcs = {}
    end
    return db.npcs
end

-- Einträge zum Lesen: { [npcID] = Eintrag } aus ezCoreDB.npcs oder – umgezogen – aus der Entdecker-Datenbank
local function Entries()
    if Moved() then return Core.Discovery.NpcEntries() end
    return Store() or {}
end

---------------------------------------------------------------------------
-- Erfassen
---------------------------------------------------------------------------

-- Titel unter dem Namen („Magierlehrer“): Zeile 2 des Tooltips, wenn sie keine Stufe nennt.
local function Subtitle()
    if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then return nil end
    local ok, data = pcall(C_TooltipInfo.GetUnit, "npc")
    if not ok or Core.IsSecret(data) or type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
    local line = data.lines[2]
    local text = type(line) == "table" and Text(line.leftText) or nil
    if not text or text:find("%d") then return nil end
    return text
end
Npcs.Subtitle = Subtitle

local function ClassNames(class)
    local names = {}
    local male = type(LOCALIZED_CLASS_NAMES_MALE) == "table" and LOCALIZED_CLASS_NAMES_MALE[class]
    local female = type(LOCALIZED_CLASS_NAMES_FEMALE) == "table" and LOCALIZED_CLASS_NAMES_FEMALE[class]
    names[#names + 1] = Text(male) or (Core.ClassName and Text(Core.ClassName(class)))
    female = Text(female)
    if female and female ~= names[1] then names[#names + 1] = female end
    return names
end

-- Trägt der Titel das Wort für Tierausbilder (Sprache des Clients: „Tierausbilder“, „Tierausbilderin“, „Pet Trainer“)?
-- Bei ihnen lernen Jäger die Fähigkeiten ihres Tiers. Vorher erkannte ezMap sie selbst am Titel (Trainers.IsPetTitle).
function Npcs.IsPetTrainerTitle(title)
    if Core.IsSecret(title) or type(title) ~= "string" or title == "" then return false end
    local word = L.NPC_PET_TRAINER_TITLE
    if type(word) ~= "string" or word == "" or word == "NPC_PET_TRAINER_TITLE" then return false end
    return title:lower():find(word:lower(), 1, true) ~= nil
end

-- Art eines Lehrers: „profession“ (Beruf), „class“ (Titel nennt die eigene Klasse), „pet“ (Tierausbilder), sonst
-- „other“ (Reiten, Waffen …).
function Npcs.TrainerKind(title)
    if Core.Bool(Core.Call(rawget(_G, "IsTradeskillTrainer")), false) then return "profession" end
    if Core.IsSecret(title) then return "other" end
    local class = Core.PlayerClass()
    if type(title) == "string" and class then
        local lower = title:lower()
        for _, name in ipairs(ClassNames(class)) do
            if lower:find(name:lower(), 1, true) then return "class" end
        end
    end
    if Npcs.IsPetTrainerTitle(title) then return "pet" end
    return "other"
end

local function Faction()
    local me = Core.me
    return (me and Text(me.faction)) or Text((Core.Call(rawget(_G, "UnitFactionGroup"), "player")))
end

-- Fraktion des NPCs (nicht die des Spielers): "Alliance" | "Horde"; neutral (Beutebucht, Gadgetzan …) → false;
-- gesperrt oder unbekannt → nil (der gemerkte Wert bleibt)
local function NpcFaction()
    local raw = Core.Call(rawget(_G, "UnitFactionGroup"), "npc")
    if Core.IsSecret(raw) then return nil end
    if raw == "Alliance" or raw == "Horde" then return raw end
    return false
end

-- Merkt den NPC, mit dem gerade gesprochen wird. kind = "trainer" | "vendor". → npcID oder nil.
function Npcs.Learn(kind)
    if kind ~= "trainer" and kind ~= "vendor" then return nil end
    if Moved() then return Core.Discovery.LearnNpc(kind) end
    local id = Core.NpcID(Core.Call(rawget(_G, "UnitGUID"), "npc"))
    local name = Text((Core.Call(rawget(_G, "UnitName"), "npc")))
    if not (id and name) then return nil end
    local store = Store(true)
    if not store then return nil end
    local e = type(store[id]) == "table" and store[id] or {}
    store[id] = e
    e.name = name
    e.title = Subtitle() or e.title
    local faction = NpcFaction()
    if faction == false then e.faction = nil elseif faction then e.faction = faction end
    e.seen = Now()
    local mapID, x, y = Core.PlayerPosition()
    if mapID then e.map, e.x, e.y = mapID, x, y end   -- in Instanzen ohne Karte bleibt die letzte bekannte Lage
    e.zone = Text(Core.Call(rawget(_G, "GetRealZoneText"))) or e.zone
    if kind == "trainer" then
        e.trainer = Npcs.TrainerKind(e.title)
        e.class = e.trainer == "class" and Core.PlayerClass() or nil
    else
        e.vendor = true
        e.repair = Core.Bool(Core.Call(rawget(_G, "CanMerchantRepair")), false) or nil
    end
    Core.Fire("NPCS_CHANGED", id, kind)
    return id
end

---------------------------------------------------------------------------
-- Lesen
---------------------------------------------------------------------------

local function Copy(id, e)
    return { id = id, name = e.name, title = e.title, trainer = e.trainer, vendor = e.vendor, repair = e.repair,
        class = e.class, faction = e.faction, map = e.map, x = e.x, y = e.y, zone = e.zone, seen = e.seen,
        kind = e.trainer and "trainer" or (e.vendor and "vendor" or nil) }
end

local function Valid(e)
    return type(e) == "table" and type(e.name) == "string" and e.name ~= ""
end

function Npcs.Get(id)
    id = Core.Num(id)
    local e = id and Entries()[id]
    return Valid(e) and Copy(id, e) or nil
end

-- Passt der NPC zu diesem Charakter? Klassenlehrer nur der eigenen Klasse, nur die eigene Fraktion.
function Npcs.Fits(e)
    if type(e) ~= "table" then return false end
    if e.trainer == "class" and e.class and e.class ~= Core.PlayerClass() then return false end
    local mine = Faction()
    if e.faction and mine and e.faction ~= mine then return false end
    return true
end

local function Matches(e, filter)
    if not filter then return true end
    if filter.kind == "trainer" and not e.trainer then return false end
    if filter.kind == "vendor" and not e.vendor then return false end
    if filter.trainer and e.trainer ~= filter.trainer then return false end
    if filter.repair and not e.repair then return false end
    if filter.map and e.map ~= filter.map then return false end
    if filter.located and not (e.map and e.x and e.y) then return false end
    if filter.fits and not Npcs.Fits(e) then return false end
    return true
end

local function ZoneOf(e)
    if e.map and Core.MapName then return Core.MapName(e.map) end
    return e.zone or ""
end

function Npcs.List(filter)
    if type(filter) == "string" then filter = { kind = filter } end
    if type(filter) ~= "table" then filter = nil end
    local list = {}
    for id, e in pairs(Entries()) do
        if type(id) == "number" and Valid(e) and Matches(e, filter) then list[#list + 1] = Copy(id, e) end
    end
    table.sort(list, function(a, b)
        local za, zb = ZoneOf(a), ZoneOf(b)
        if za ~= zb then return za < zb end
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    return list
end

function Npcs.Find(name)
    local list = {}
    if Core.IsSecret(name) or type(name) ~= "string" or name == "" then return list end
    local wanted = name:lower()
    for id, e in pairs(Entries()) do
        if type(id) == "number" and Valid(e) and e.name:lower() == wanted then list[#list + 1] = Copy(id, e) end
    end
    table.sort(list, function(a, b)
        if (a.seen or 0) ~= (b.seen or 0) then return (a.seen or 0) > (b.seen or 0) end
        return a.id < b.id
    end)
    return list
end

function Npcs.Where(who)
    local e
    if type(who) == "number" then
        e = Npcs.Get(who)
    else
        for _, candidate in ipairs(Npcs.Find(who)) do
            if candidate.map and candidate.x and candidate.y then e = candidate break end
        end
    end
    if not (e and e.map and e.x and e.y) then return nil end
    return e.map, e.x, e.y, e
end

function Npcs.Label(e)
    if type(e) ~= "table" or type(e.name) ~= "string" then return nil end
    if e.title then return e.name .. " (" .. e.title .. ")" end
    return e.name
end

function Npcs.KindLabel(e)
    if type(e) ~= "table" then return nil end
    if e.trainer then return L["NPC_TRAINER_" .. e.trainer] end
    if e.vendor then return L.NPC_KIND_vendor end
    return nil
end

function Npcs.Count(kind)
    local n = 0
    for id, e in pairs(Entries()) do
        if type(id) == "number" and Valid(e) and Matches(e, kind and { kind = kind } or nil) then n = n + 1 end
    end
    return n
end

-- Vergessen: ein NPC (ID), alle Lehrer bzw. Händler ("trainer", "vendor") oder alles (nil). Ein NPC, der beides ist,
-- verliert bei "trainer"/"vendor" nur diese Eigenschaft. → Anzahl betroffener Einträge.
function Npcs.Forget(what)
    if Moved() then return Core.Discovery.ForgetNpc(what) end
    local store = Store()
    if not store then return 0 end
    local n = 0
    if type(what) == "number" then
        if store[what] ~= nil then store[what], n = nil, 1 end
    else
        for id, e in pairs(store) do
            if what == nil then
                store[id], n = nil, n + 1
            elseif not Valid(e) then
                -- kaputte Einträge bleiben für Forget() (alles) liegen; sie zählen nirgends mit
            elseif what == "trainer" and e.trainer then
                e.trainer, e.class, n = nil, nil, n + 1
                if not e.vendor then store[id] = nil end
            elseif what == "vendor" and e.vendor then
                e.vendor, e.repair, n = nil, nil, n + 1
                if not e.trainer then store[id] = nil end
            end
        end
    end
    if n > 0 then Core.Fire("NPCS_CHANGED", type(what) == "number" and what or nil, type(what) == "string" and what or nil) end
    return n
end

---------------------------------------------------------------------------
-- Einmalige Übernahme der Lehrer aus ezMap (ezMapDB.trainers bleibt liegen)
---------------------------------------------------------------------------

function Npcs.MigrateTrainers()
    local db = Core.db
    if type(db) ~= "table" then return 0 end
    if type(db.migrated) ~= "table" then db.migrated = {} end
    if db.migrated.ezMapTrainers then return 0 end
    local old = rawget(_G, "ezMapDB")
    if type(old) ~= "table" then return 0 end   -- ezMap (noch) nicht da: beim nächsten Anmelden wieder prüfen
    db.migrated.ezMapTrainers = true
    if type(old.trainers) ~= "table" then return 0 end
    if Moved() then return Core.DB.AsOwn(Npcs.MigrateTrainersToDB, old.trainers) end
    local store, n = Store(true), 0
    for id, t in pairs(old.trainers) do
        id = Core.Num(id)
        if id and type(t) == "table" and type(t.name) == "string" and t.name ~= "" then
            local e = type(store[id]) == "table" and store[id] or nil
            if not e then
                e = {}
                store[id] = e
                n = n + 1
            end
            -- was ezCore inzwischen selbst gesehen hat, ist neuer und gewinnt
            if (Core.Num(e.seen) or 0) < (Core.Num(t.seen) or 0) or e.name == nil then
                e.name = t.name
                e.title = type(t.title) == "string" and t.title or e.title
                e.faction = type(t.faction) == "string" and t.faction or e.faction
                if Core.Num(t.map) and Core.Num(t.x) and Core.Num(t.y) then e.map, e.x, e.y = t.map, t.x, t.y end
                e.seen = Core.Num(t.seen) or e.seen
            end
            if not e.trainer then
                e.trainer = (t.kind == "class" or t.kind == "profession") and t.kind
                    or (Npcs.IsPetTrainerTitle(e.title) and "pet") or "other"
                e.class = e.trainer == "class" and type(t.class) == "string" and t.class or nil
            end
        end
    end
    return n
end

-- Nach dem Umzug (ezCoreDB.npcs wird nicht mehr geschrieben): die Lehrer aus ezMap gehen in die Entdecker-Datenbank,
-- unter das, was sie schon weiß (Discovery.AdoptNpc). → Zahl neuer NPCs
function Npcs.MigrateTrainersToDB(trainers)
    local D, DB, n = Core.Discovery, Core.DB, 0
    for id, t in pairs(type(trainers) == "table" and trainers or {}) do
        id = Core.Num(id)
        if id and type(t) == "table" and type(t.name) == "string" and t.name ~= "" then
            local trainer = (t.kind == "class" or t.kind == "profession") and t.kind
                or (Npcs.IsPetTrainerTitle(t.title) and "pet") or "other"
            local e = { name = t.name, title = type(t.title) == "string" and t.title or nil, trainer = trainer,
                class = trainer == "class" and type(t.class) == "string" and t.class or nil,
                faction = type(t.faction) == "string" and t.faction or nil, seen = Core.Num(t.seen) }
            if Core.Num(t.map) and Core.Num(t.x) and Core.Num(t.y) then e.map, e.x, e.y = t.map, t.x, t.y end
            local had = DB.Get("npc", id) ~= nil
            if D.AdoptNpc(id, e, true) and not had then n = n + 1 end
        end
    end
    if n > 0 then Core.Fire("NPCS_CHANGED", nil, "trainer") end
    return n
end

-- Tierausbilder, die vor der Art „pet“ (oder aus ezMaps Übernahme) als „other“ gespeichert wurden, nachträglich
-- einsortieren – am Titel (Npcs.IsPetTrainerTitle, Sprache des Clients). Läuft bei jedem Anmelden und ändert nur
-- Einträge mit trainer = "other"; Titel in einer anderen Sprache bleiben, bis der Lehrer wieder angesprochen wird.
-- → Zahl umsortierter Einträge
function Npcs.SortPetTrainers()
    if Moved() then return Core.Discovery.SortPetTrainers() end
    local store, n = Store(false), 0
    for _, e in pairs(store or {}) do
        if type(e) == "table" and e.trainer == "other" and Npcs.IsPetTrainerTitle(e.title) then
            e.trainer = "pet"
            n = n + 1
        end
    end
    return n
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------

local function Safe(where, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then Core.Error(Core.name, err, where) end
end

Core.Listen("CHARS_READY", function()
    Safe("Npcs.MigrateTrainers", Npcs.MigrateTrainers)
    Safe("Npcs.SortPetTrainers", Npcs.SortPetTrainers)
end, "ezCore.Npcs")
ns.On("TRAINER_SHOW", function() Safe("Npcs.Learn", Npcs.Learn, "trainer") end)
ns.On("MERCHANT_SHOW", function() Safe("Npcs.Learn", Npcs.Learn, "vendor") end)
