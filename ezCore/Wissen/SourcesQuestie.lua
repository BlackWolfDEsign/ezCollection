local _, ns = ...
local Core = ezCore

--[[
    QuestieDB als Laufzeit-Quelle in Core.Sources (DG-14, EC-03, RM-08; Entscheidung des Nutzers 14.11.2026 „Ja, und
    Questie empfehlen“). QuestieDB ist ausdrücklich für fremde Addons gedacht: global LibQuestieDB mit
    RequireContract (Vertrag 1 bis 4 laut docs/datengrundlage.md 10.1) und je Art lesenden Abfragen
    (LibQuestieDB.Item/Npc/Object/Quest, je Feld eine Funktion mit der ID: Item.npcDrops(id) …).

    Leitlinie 10: nur zur Laufzeit, nur lesende Funktionen, alles per pcall, jede Antwort auf Form geprüft. Nichts
    wird kopiert oder in ezCoreDB bzw. ezWorldDB geschrieben (die Antworten tragen die Marke „fremd“,
    DB.MarkForeign). Zwischengespeichert wird nur für die Spawns je Karte (unten), nur im Arbeitsspeicher: ein Index
    Karte » IDs und die gelesenen Einträge der letzten Q.SPAWN_MAPS Karten. Nie benutzt: die schreibenden Teile
    (Korrekturen, Sprache, Zwischenspeicher leeren, InvalidateCache, BuildNameIndex) und die Stütztabellen mit
    Dropchancen. Name und Logo „Questie“ stehen nur als Quellenangabe da („laut Questie“).

    Weil die Prüfung im Spiel (DG-13) noch aussteht, nutzt die Quelle nur diese Lesefunktionen und prüft jede
    Antwort; stimmt die Form nicht, meldet sie „shape“ und liefert keine Zeile:
      Item:   name, npcDrops, objectDrops, itemDrops, vendors, questRewards      (Listen von IDs)
      Npc:    name, minLevel, maxLevel, rank, zoneID, spawns                    (spawns = { [Gebiets-ID] = { { x, y } … } },
      Object: name, zoneID, spawns                                               x und y in Prozent 0–100)
      Quest:  name, questLevel
    Nur für die Spawns je Karte (Welle 27) zusätzlich – fehlen sie, bleibt die übrige Quelle „ok“, nur der Teil meldet
    „shape“: Npc.GetAllIds, Object.GetAllIds (Q.Spawns) und Quest.objectives, startedBy, finishedBy (Q.QuestTargets).
    Ob die Koordinaten in den vier Zonen mit geänderter Karte schon umgerechnet sind, ist [unbestätigt] (DG-13):
    LibQuestieDB.EraToForever ist deshalb ab Werk nicht angewandt – Schalter Q.ERA_TO_FOREVER (false), eine Stelle
    Q.Forever für „Woher?“ und die Spawns.

      Core.Sources.Questie.Ready()        → true | false, "missing" | "shape" (wirft, wenn RequireContract wirft)
      Core.Sources.Questie.CONTRACT       Vertragsnummer, gegen die gebaut ist (4)
      Core.Sources.Questie.LOOT           lootOf (Beute je Gegner, ohne Chance) – ab Werk false (DG-16): eingeschaltet
                                          oder verworfen wird erst nach der Messung von Dauer und Speicher (DG-13).
                                          Gebaut als anlassbezogener Index (Empfehlung umgesetzt, Antwort offen): nur
                                          für den gefragten Gegner, nur über Gegenstände, die der Client dir schon
                                          gezeigt hat (cache.item, höchstens LOOT_SCAN), nichts gemerkt.
      Core.Sources.Questie.Register()     meldet die Quelle (neu) an – nach dem Umlegen von LOOT
      Core.Sources.Questie.Exists(art, id) → true | false | nil (Item, Npc, Object, Quest; nil = keine Antwort)
      Core.Sources.Questie.MapForArea(areaID) → uiMapID | nil   Zuordnung über den Namen laut Client (C_Map), nur im
                                          Arbeitsspeicher (QuestieDB gruppiert Fundorte nach Gebiets-ID)
    Erkennung: Core.OTHER_ADDONS.QuestieDB (Ordner „QuestieDB“; läuft auch ohne Questie), ezCore.toc nennt es nur
    unter OptionalDeps (jedes Modul läuft allein).
]]

local Sources = Core.Sources
local Q = {}
Sources.Questie = Q

Q.CONTRACT = 4
Q.LOOT = false
Q.LOOT_SCAN = 2000

local Field, Num = Core.Peek, Core.Num

local function ID(value)
    if Core.IsSecret(value) then return nil end
    if type(value) ~= "number" or value <= 0 or value ~= math.floor(value) then return nil end
    return value
end

local function Lib()
    local lib = rawget(_G, "LibQuestieDB")
    return type(lib) == "table" and lib or nil
end

local function Reader(lib, kind, field)
    local fn = Field(Field(lib, kind), field)
    return type(fn) == "function" and fn or nil
end

-- Lesefunktionen, die die Quelle braucht (am Quelltext belegt, docs/datengrundlage.md 10.1)
Q.NEEDED = {
    Item = { "name", "npcDrops", "objectDrops", "itemDrops", "vendors", "questRewards" },
    Npc = { "name", "minLevel", "maxLevel", "rank", "zoneID", "spawns" },
    Object = { "name", "zoneID", "spawns" },
    Quest = { "name", "questLevel" },
}

local confirmed   -- die Tabelle LibQuestieDB, deren Vertrag geprüft ist (ein neues Global wird neu geprüft)

function Q.Ready()
    local lib = Lib()
    if not lib then
        if Core.OtherAddOn and Core.OtherAddOn("QuestieDB") then return false, "shape" end
        return false, "missing"
    end
    if confirmed == lib then return true end
    local require = Field(lib, "RequireContract")
    if type(require) ~= "function" then return false, "shape" end
    local ok, yes = pcall(require, Q.CONTRACT)
    if not ok then error(yes, 0) end
    if yes ~= true then return false, "shape" end
    for kind, fields in pairs(Q.NEEDED) do
        for _, field in ipairs(fields) do
            if not Reader(lib, kind, field) then return false, "shape" end
        end
    end
    confirmed = lib
    return true
end

-- Eine Lesefunktion rufen: wirft sie, wirft die Auskunft (Core.Sources meldet „error“); ein gesperrter Wert ist
-- falsche Form.
local SHAPE = {}
local function Read(kind, field, id)
    local fn = Reader(Lib(), kind, field)
    if not fn then error(SHAPE, 0) end
    local ok, value = pcall(fn, id)
    if not ok then error(value, 0) end
    if Core.IsSecret(value) then error(SHAPE, 0) end
    return value
end

local function IdList(value)
    if value == nil then return {} end
    if type(value) ~= "table" then error(SHAPE, 0) end
    local out = {}
    for i = 1, #value do
        local id = ID(Field(value, i))
        if not id then error(SHAPE, 0) end
        out[i] = id
    end
    return out
end

local function Text(value)
    if value == nil then return nil end
    if type(value) ~= "string" then error(SHAPE, 0) end
    return value ~= "" and value or nil
end

local function Number(value)
    if value == nil then return nil end
    if type(value) ~= "number" then error(SHAPE, 0) end
    return value
end

---------------------------------------------------------------------------
-- Gebiets-ID » Karte und Name (aus dem Client, nur im Arbeitsspeicher)
---------------------------------------------------------------------------

local mapByName

local function AreaName(areaID)
    local fn = Field(rawget(_G, "C_Map"), "GetAreaInfo")
    if not ID(areaID) or type(fn) ~= "function" then return nil end
    local ok, name = pcall(fn, areaID)
    if ok and type(name) == "string" and not Core.IsSecret(name) and name ~= "" then return name end
    return nil
end

local function BuildMaps()
    mapByName = {}
    local api = rawget(_G, "C_Map")
    local children = Field(api, "GetMapChildrenInfo")
    if type(children) ~= "function" then return end
    for _, root in ipairs({ 946, 947 }) do
        local ok, list = pcall(children, root, 3, true)          -- 3 = Enum.UIMapType.Zone
        if ok and type(list) == "table" then
            for _, info in ipairs(list) do
                local name, mapID = Field(info, "name"), ID(Field(info, "mapID"))
                if mapID and type(name) == "string" and not Core.IsSecret(name) and not mapByName[name] then
                    mapByName[name] = mapID
                end
            end
        end
    end
end

function Q.MapForArea(areaID)
    local name = AreaName(areaID)
    if not name then return nil end
    if not mapByName then BuildMaps() end
    return mapByName[name]
end

-- Koordinaten der vier Zonen mit geänderter Karte (Sturmwind, Mulgore, Rotkammgebirge, Östliche Pestländer): ob
-- QuestieDB sie schon umgerechnet liefert, ist unbestätigt (DG-13, ezCore „Im Spiel prüfen“ Punkt 58 a). Deshalb ab
-- Werk aus; zeigt der Spieltest verschobene Punkte, schaltet Q.ERA_TO_FOREVER = true die Umrechnung über
-- LibQuestieDB.EraToForever ein (eine Stelle für „Woher?“ und die Spawns je Karte). Prozent rein, Prozent raus.
Q.ERA_TO_FOREVER = false

function Q.Forever(area, x, y)
    if not Q.ERA_TO_FOREVER then return x, y end
    local fn = Field(Lib(), "EraToForever")
    if type(fn) ~= "function" then return x, y end
    local ok, nx, ny = pcall(fn, area, x, y)
    nx, ny = ok and Num(nx), ok and Num(ny)
    if nx and ny and nx >= 0 and ny >= 0 and nx <= 100 and ny <= 100 then return nx, ny end
    return x, y
end

-- Häufigster Fundort: die Gebiets-ID mit den meisten Punkten, deren erster Punkt (0–1)
local function Spot(spawns)
    if spawns == nil then return nil end
    if type(spawns) ~= "table" then error(SHAPE, 0) end
    local bestArea, bestList, bestN
    for area, list in pairs(spawns) do
        if not ID(area) or type(list) ~= "table" then error(SHAPE, 0) end
        local n = #list
        if n > 0 and (not bestN or n > bestN or (n == bestN and area < bestArea)) then
            bestArea, bestList, bestN = area, list, n
        end
    end
    if not bestList then return nil end
    local p = bestList[1]
    local x, y = Num(Field(p, 1)), Num(Field(p, 2))
    if not (x and y) then error(SHAPE, 0) end
    if x < 0 or y < 0 then return bestArea end                   -- (-1, -1): Ort unbekannt
    if x > 100 or y > 100 then error(SHAPE, 0) end
    x, y = Q.Forever(bestArea, x, y)
    return bestArea, x / 100, y / 100
end

local function Place(e, kind, id)
    local area, x, y = Spot(Read(kind, "spawns", id))
    area = area or ID(Number(Read(kind, "zoneID", id)))
    if area then
        e.area, e.zone, e.map = area, AreaName(area), Q.MapForArea(area)
        e.x, e.y = x, y
    end
end

---------------------------------------------------------------------------
-- Auskünfte
---------------------------------------------------------------------------

local function Explorer()
    local DB = Core.DB
    return DB and DB.Explorer and DB.Explorer() == true
end

local function Npc(id)
    local e = { kind = "npc", id = id, name = Text(Read("Npc", "name", id)) }
    e.lo, e.hi = Number(Read("Npc", "minLevel", id)), Number(Read("Npc", "maxLevel", id))
    e.rank = Number(Read("Npc", "rank", id))
    Place(e, "Npc", id)
    return e
end

local function Object(id)
    local e = { kind = "object", id = id, name = Text(Read("Object", "name", id)) }
    Place(e, "Object", id)
    return e
end

local function Container(id)
    local e = { kind = "item", id = id }
    -- auch der Behälter kann verschleiert sein: seinen Namen nur, wenn der Client ihn kennt (oder Entdecker-Wissen)
    if Sources.ClientKnowsItem(id) or Explorer() then e.name = Text(Read("Item", "name", id)) end
    return e
end

local function Quest(id)
    return { kind = "quest", id = id, name = Text(Read("Quest", "name", id)), lo = Number(Read("Quest", "questLevel", id)) }
end

local LISTS = {
    { "drops", "npcDrops", Npc }, { "objects", "objectDrops", Object }, { "containers", "itemDrops", Container },
    { "vendors", "vendors", Npc }, { "quests", "questRewards", Quest },
}

local function WhereFrom(itemID, opts)
    -- Verschleierte Gegenstände sind Entdecker-Wissen (DG-18, Empfehlung umgesetzt, Antwort offen)
    if not Sources.ClientKnowsItem(itemID) and not Explorer() and not (opts and opts.explorer == true) then return nil end
    local ok, result = pcall(function()
        local out, any = { item = itemID, n = {} }, false
        for _, def in ipairs(LISTS) do
            local ids = IdList(Read("Item", def[2], itemID))
            if #ids > 0 then
                out.n[def[1]] = #ids
                local list = {}
                for i = 1, math.min(#ids, Sources.WHERE_MAX) do list[i] = def[3](ids[i]) end
                out[def[1]] = list
                any = true
            end
        end
        return any and out or nil
    end)
    if not ok then
        if result == SHAPE then return nil, "shape" end
        error(result, 0)
    end
    return result
end

-- DG-16 (vorbereitet, ab Werk aus): „Kann fallen lassen (laut Questie, ohne Chance)“
local function LootOf(npcID)
    local DB = Core.DB
    local candidates = DB and DB.KeysOf and DB.KeysOf("item") or {}
    local ok, result = pcall(function()
        local items = {}
        for i = 1, math.min(#candidates, Q.LOOT_SCAN) do
            local itemID = candidates[i]
            if Sources.ClientKnowsItem(itemID) or Explorer() then
                for _, npc in ipairs(IdList(Read("Item", "npcDrops", itemID))) do
                    if npc == npcID then
                        items[#items + 1] = { id = itemID, listed = true }
                        break
                    end
                end
            end
        end
        if #items == 0 then return nil end
        return { npc = npcID, items = items, measured = false, estimated = false, listed = true }
    end)
    if not ok then
        if result == SHAPE then return nil, "shape" end
        error(result, 0)
    end
    return result
end
Q.LootOf = LootOf

-- Kennt QuestieDB diese ID? (Exists – nur lesend; für den Selbsttest der Bücher-IDs, DG-20) → true | false | nil
-- (nil: QuestieDB läuft nicht oder antwortet nicht in der erwarteten Form)
function Q.Exists(kind, id)
    if not (Q.NEEDED[kind] and ID(id)) then return nil end
    local okReady, ready = pcall(Q.Ready)
    if not (okReady and ready == true) then return nil end
    local fn = Reader(Lib(), kind, "Exists")
    if not fn then return nil end
    local ok, yes = pcall(fn, id)
    if not ok or Core.IsSecret(yes) or type(yes) ~= "boolean" then return nil end
    return yes
end

---------------------------------------------------------------------------
-- Spawns je Karte (Welle 27, F5 b – Entscheidung des Nutzers vom 16.11.2026: „aber filterbar/anzeigbar?“; die
-- Gruppe „laut Questie“ und ihre Filter baut ezMap, ezMap/QuestieSpawns.lua)
---------------------------------------------------------------------------
--[[
    QuestieDB gruppiert Fundorte nach Gebiets-ID und kennt keine Abfrage „alles auf dieser Karte“. Deshalb entsteht
    beim ersten Aufruf EIN Index Karte » IDs: alle NPC- und Objekt-IDs (GetAllIds), je ID spawns gelesen, jede
    Gebiets-ID über Q.MapForArea (Name laut Client) ihrer Zone zugeordnet. Danach liest ezCore je gefragter Karte die
    Einträge (Name, Rang, Stufe, Punkte). Beides in Scheiben (Q.SPAWN_SLICE bzw. Q.SPAWN_MAP_SLICE IDs, höchstens
    Q.SPAWN_BUDGET Millisekunden je Bild), im Kampf pausiert. ezCore merkt sich nur IDs und die letzten Q.SPAWN_MAPS
    Karten, nur im Arbeitsspeicher – nichts in ezCoreDB, nichts kopiert (Leitlinie 10). Es wird nur gelesen, wenn ein
    Modul fragt (ezMap: erst, wenn die Gruppe an ist und eine Zone gezeigt wird).
    Speicher in QuestieDB: QuestieDB legt je berührtem Eintrag selbst eine Zeile in seinem Zwischenspeicher an (am
    Quelltext belegt, src/read/shared.lua) und liefert jedes spawns als frische Kopie. Nach dem ersten Index hält
    QuestieDB also Zeilen für alle NPCs und Objekte, auch nach Q.ForgetSpawns – leeren könnte das nur InvalidateCache,
    das ezCore nicht ruft (schreibender Teil). Die Kopien sind Müll für den Garbage Collector. Wie viel das im Spiel
    ausmacht, misst ezMap Punkt 66 b (DG-13). Ist es zu viel, hilft ein Index über zoneID nicht (berührt ebenso jeden
    Eintrag); dann bräuchte es eine Abfrage je Zone in QuestieDB oder den Verzicht auf den Index.

      Q.Spawns(mapID, opts) → antwort | nil, grund[, fertig, gesamt]
          grund: "missing" | "shape" (QuestieDB fehlt bzw. antwortet anders – auch ohne GetAllIds) | "error" |
                 "map" (keine Karten-ID) | "building" (Index bzw. Karte wird gelesen; Fertig-Meldung über die
                 Nachricht QUESTIE_SPAWNS)
          antwort = { map, list = { eintrag … }, n = { npc, object }, points, total (Einträge vor dem Filter),
                      capped (Deckel Q.SPAWN_MAX bei einer Art erreicht – die Filter sehen nur die gelesenen
                      Einträge), cappedKinds = { npc = true | nil, object = … }, hidden = { rare = n }, source = "Questie",
                      sourceKey = "QuestieDB" } – Core.Sources.Label(antwort) → „laut Questie“
          eintrag = { kind = "npc" | "object", id, name, rank, lo, hi, rare, elite, capped,
                      points = { { x, y } … } (0–1 auf map, höchstens Q.SPAWN_PER_ID) } – nur lesen, nicht ändern
          opts = { kinds = { npc = bool, object = bool } (Standard beide), name = Teil des Namens (ohne Groß- und
                   Kleinschreibung), ids = { npc = { [id] = true }, object = { … } } (nur diese – für eine Quest
                   bzw. einen Gegenstand), ranks = { normal = bool, elite = bool, rare = bool } (Gegner nach
                   Q.RankClass; fehlt das Feld, alle – Objekte haben keinen Rang), explorer = true (seltene Gegner) }
          Seltene Gegner (Rang 2 und 4) sind Entdecker-Wissen (Leitlinie 11): nur mit opts.explorer oder ezCores
          Schalter „Entdecker-Wissen zeigen“; sonst zählt hidden.rare sie.
      Q.SpawnsReady() → true | false, grund – könnte Q.Spawns antworten? (liest nichts, baut keinen Index)
      Q.RankClass(eintrag) → "rare" | "elite" | "normal" | nil (Objekt)
      Q.SpawnState() → "idle" | "index" | "ready" | "missing" | "shape" | "error", fertig, gesamt, karte (in Arbeit)
      Q.SpawnsFinish() – alle ausstehenden Scheiben sofort (Prüfungen; im Spiel für /run mit debugprofilestop)
      Q.ForgetSpawns() – Index und Karten verwerfen (der nächste Aufruf baut neu; in ezMap der Knopf „Neu lesen“)
      Einzelne fehlerhafte Einträge (wirft, gesperrt) werden übersprungen und gezählt; erst ab Q.SPAWN_FAIL_MIN
      Fehlschlägen, die mindestens die Hälfte ausmachen, meldet der Teil "shape" bzw. "error". GetAllIds muss eine
      Liste von IDs liefern (eine Menge oder zusammen 0 IDs: "shape").
      Q.QuestTargets(questID) → { quest, name, npc = { [id] = true }, object = { … } } | nil, grund – Gegner und
          Objekte einer Quest laut QuestieDB: Ziele (Gegner, Objekte, Kill-Credit), Gegenstände der Ziele (fällt von,
          liegt in), Start und Abgabe. Braucht die Lesefunktionen Quest.objectives/startedBy/finishedBy (sonst "shape").
      Q.ItemTargets(itemID, opts) → { item, name, npc = { … }, object = { … } } | nil, grund – Quellen eines
          Gegenstands (fällt von, verkauft von, liegt in); verschleierte nur mit Entdecker-Wissen ("explorer", DG-18)
    Nachricht QUESTIE_SPAWNS (karte | nil, zustand): "ready" mit Karte, wenn ihre Einträge gelesen sind; ohne Karte
    "index" (Index fertig) bzw. "shape" | "error".
    Leistung und Speicher im Spiel sind ungeprüft (DG-13; ezMap „Im Spiel prüfen“ Punkt 66).
]]

Q.SPAWN_SLICE = 250        -- IDs je Bild beim Aufbau des Index (je ID nur spawns)
Q.SPAWN_MAP_SLICE = 60     -- IDs je Bild beim Lesen einer Karte (Name, Rang, Stufe, spawns)
Q.SPAWN_BUDGET = 4         -- höchstens so viele Millisekunden je Bild (debugprofilestop), sonst weiter im nächsten
Q.SPAWN_PER_ID = 100       -- Punkte je Gegner bzw. Objekt und Karte
Q.SPAWN_MAX = 6000         -- Deckel je Karte und Art: so viele Punkte Gegner bzw. Objekte (danach capped, cappedKinds)
Q.SPAWN_MAPS = 3           -- so viele gelesene Karten bleiben im Arbeitsspeicher
-- Rang laut QuestieDB (Feld rank, Zählung von cmangos): 0 normal, 1 Elite, 2 seltene Elite, 3 Boss, 4 selten
Q.RARE_RANKS = { [2] = true, [4] = true }
Q.ELITE_RANKS = { [1] = true, [2] = true, [3] = true }
Q.SPAWN_KINDS = { "npc", "object" }
local KIND_OF = { npc = "Npc", object = "Object" }

if Core.RegisterMessage then
    Core.RegisterMessage("QUESTIE_SPAWNS", "SourcesQuestie.lua", "Spawns laut Questie: die Einträge einer Karte "
        .. "sind gelesen (karte, \"ready\"), der Index ist fertig (nil, \"index\") oder QuestieDB antwortet nicht "
        .. "wie erwartet (nil, \"shape\" | \"error\").", "karte | nil, zustand")
end

local spawn = { state = "idle" }       -- Index (nur IDs) und laufende Arbeit
local spawnMaps, spawnOrder = {}, {}   -- [Karte] = gelesene Einträge; Reihenfolge (neueste hinten)
local areaMaps = {}                    -- [Gebiets-ID] = Karte | false
local wanted                           -- zuletzt gefragte Karte

local function MapOfArea(area)
    local map = areaMaps[area]
    if map == nil then
        map = Q.MapForArea(area) or false
        areaMaps[area] = map
    end
    return map or nil
end

local function SliceMillis()
    local fn = rawget(_G, "debugprofilestop")
    if type(fn) ~= "function" then return nil end
    local ok, t = pcall(fn)
    return ok and Num(t) or nil
end

-- Zeitbudget nach jeder ID (debugprofilestop ist billig; ein einzelner spawns-Aufruf kann teuer sein – Fund des
-- code-reviewers vor dem Merge, 16.11.2026)
local function Over(start, n, slice)
    if n >= slice then return true end
    if not start then return false end
    local now = SliceMillis()
    return now ~= nil and now - start >= Q.SPAWN_BUDGET
end

-- Ein einzelner fehlerhafter Eintrag (wirft oder liefert einen gesperrten Wert) wird übersprungen und gezählt; erst
-- wenn viele scheitern (mindestens Q.SPAWN_FAIL_MIN und mindestens die Hälfte), gilt die ganze Quelle als kaputt –
-- sonst schaltete ein einziger Eintrag die Funktion bis zum /reload ab (Fund des code-reviewers vor dem Merge).
Q.SPAWN_FAIL_MIN = 50
local function Broken(work, seen, err)
    work.failed = (work.failed or 0) + 1
    work.skipped = (work.skipped or 0) + 1
    if work.failed >= Q.SPAWN_FAIL_MIN and work.failed * 2 >= seen then error(err, 0) end
end

local function Fire(map, state) Core.Fire("QUESTIE_SPAWNS", map, state) end

local function Fail(reason, err)
    spawn = { state = reason, lib = spawn.lib }
    if reason == "error" then Core.Error(Core.name, err, "Questie.Spawns") end
    Fire(nil, reason)
end

local function AllIds(lib, kind)
    local fn = Reader(lib, KIND_OF[kind], "GetAllIds")
    if not fn then error(SHAPE, 0) end
    local ok, list = pcall(fn)
    if not ok then error(list, 0) end
    if Core.IsSecret(list) or type(list) ~= "table" then error(SHAPE, 0) end
    -- Erwartet ist eine Liste von IDs: eine Menge { [id] = true } oder eine Liste mit anderem Inhalt ist falsche Form
    -- (sonst endete der Index sofort und jede Zone zeigte still „0 Gegner, 0 Objekte“ – Fund des code-reviewers)
    local n = #list
    if n == 0 then
        if next(list) ~= nil then error(SHAPE, 0) end
    elseif not ID(Field(list, 1)) then
        error(SHAPE, 0)
    end
    return list, n
end

-- Eine Scheibe des Index. → true, wenn fertig. Löcher und ungültige IDs in der Liste werden übersprungen (gezählt),
-- das Ende ist die Länge der Liste.
local function IndexSlice()
    local idx, start, n = spawn, SliceMillis(), 0
    while true do
        if idx.pos > idx.len[idx.kind] then
            if idx.kind ~= "npc" then return true end
            idx.kind, idx.pos = "object", 1
        else
            local id = ID(Field(idx.lists[idx.kind], idx.pos))
            idx.pos, idx.done, n = idx.pos + 1, idx.done + 1, n + 1
            local okRead, spawns = true, nil
            if id then okRead, spawns = pcall(Read, KIND_OF[idx.kind], "spawns", id) end
            if not okRead then
                Broken(idx, idx.done, spawns)
            elseif type(spawns) == "table" then
                for area, points in pairs(spawns) do
                    if not ID(area) or type(points) ~= "table" then
                        idx.skipped = idx.skipped + 1          -- Gebiets-ID oder Punktliste in falscher Form
                    else
                        local map = MapOfArea(area)        -- nil: Instanz oder Gebiet ohne Zone laut Client
                        local at = map and idx.byMap[map]
                        if map and not at then
                            at = { npc = {}, object = {}, last = {} }
                            idx.byMap[map] = at
                        end
                        if at and at.last[idx.kind] ~= id then
                            local list = at[idx.kind]
                            list[#list + 1] = id
                            at.last[idx.kind] = id
                        end
                    end
                end
            elseif spawns ~= nil or not id then
                idx.skipped = idx.skipped + 1
            end
            if Over(start, n, Q.SPAWN_SLICE) then return false end
        end
    end
end

-- Ein Eintrag der Karte map (nil: ohne Punkt auf dieser Karte oder in falscher Form)
local function ReadEntry(kind, id, map)
    local K = KIND_OF[kind]
    local name = Read(K, "name", id)
    if name ~= nil and type(name) ~= "string" then return nil end
    local e = { kind = kind, id = id, name = name ~= "" and name or nil, rank = 0 }
    if kind == "npc" then
        e.rank = Num(Read("Npc", "rank", id)) or 0
        e.lo, e.hi = Num(Read("Npc", "minLevel", id)), Num(Read("Npc", "maxLevel", id))
        e.rare, e.elite = Q.RARE_RANKS[e.rank] == true, Q.ELITE_RANKS[e.rank] == true
    end
    local spawns = Read(K, "spawns", id)
    if type(spawns) ~= "table" then return nil end
    local points = {}
    for area, list in pairs(spawns) do
        if ID(area) and type(list) == "table" and MapOfArea(area) == map then
            for i = 1, #list do
                if #points >= Q.SPAWN_PER_ID then
                    e.capped = true
                    break
                end
                local p = list[i]
                local x, y = Num(Field(p, 1)), Num(Field(p, 2))
                if x and y and x >= 0 and y >= 0 and x <= 100 and y <= 100 then   -- (-1, -1): Ort unbekannt
                    x, y = Q.Forever(area, x, y)
                    points[#points + 1] = { x = x / 100, y = y / 100 }
                end
            end
        end
    end
    if #points == 0 then return nil end
    e.points = points
    return e
end

-- Zuletzt benutzte Karte nach hinten (die Q.SPAWN_MAPS zuletzt benutzten bleiben, nicht die zuerst gelesenen)
local function Touch(map)
    for i = #spawnOrder, 1, -1 do
        if spawnOrder[i] == map then
            table.remove(spawnOrder, i)
            break
        end
    end
    spawnOrder[#spawnOrder + 1] = map
end

local function Store(result)
    local map = result.map
    Touch(map)
    spawnMaps[map] = result
    while #spawnOrder > Q.SPAWN_MAPS do
        spawnMaps[table.remove(spawnOrder, 1)] = nil
    end
end

-- Eine Scheibe der laufenden Karte. → true, wenn fertig. Der Deckel gilt je Art: erreichen die Gegner ihn, werden
-- die Objekte trotzdem gelesen (sonst fehlten sie in dichten Zonen ganz).
local function MapSlice(job)
    local start, n, result = SliceMillis(), 0, job.result
    while job.pos <= #job.ids do
        local ref = job.ids[job.pos]
        job.pos = job.pos + 1
        if not result.cappedKinds[ref.kind] then
            n = n + 1
            local okEntry, e = pcall(ReadEntry, ref.kind, ref.id, job.map)
            if not okEntry then
                Broken(result, job.pos - 1, e)
            elseif e then
                result.list[#result.list + 1] = e
                result.n[e.kind] = result.n[e.kind] + 1
                result.points = result.points + #e.points
                result.pointsOf[e.kind] = result.pointsOf[e.kind] + #e.points
                if result.pointsOf[e.kind] >= Q.SPAWN_MAX then
                    result.capped, result.cappedKinds[e.kind] = true, true
                end
            end
            if Over(start, n, Q.SPAWN_MAP_SLICE) then return false end
        end
    end
    return true
end

local function StartMap(map)
    local at = spawn.byMap and spawn.byMap[map]
    local ids = {}
    for _, kind in ipairs(Q.SPAWN_KINDS) do
        for _, id in ipairs(at and at[kind] or {}) do ids[#ids + 1] = { kind = kind, id = id } end
    end
    local result = { map = map, list = {}, n = { npc = 0, object = 0 }, points = 0, pointsOf = { npc = 0, object = 0 },
        cappedKinds = {}, skipped = 0, failed = 0 }
    if #ids == 0 then
        spawn.job = nil
        Store(result)
        return
    end
    spawn.job = { map = map, ids = ids, pos = 1, result = result }
end

-- Eine Scheibe Arbeit. → true, wenn noch etwas aussteht
local function Work()
    if spawn.state ~= "index" and not spawn.job then return false end
    local ok, done = pcall(function()
        if spawn.state == "index" then
            if not IndexSlice() then return nil end
            spawn.state, spawn.lists = "ready", nil
            return "index"
        end
        if not MapSlice(spawn.job) then return nil end
        local result = spawn.job.result
        spawn.job = nil
        Store(result)
        return result.map
    end)
    if not ok then
        if done == SHAPE then Fail("shape") else Fail("error", done) end
        return false
    end
    if done == "index" then
        if wanted then StartMap(wanted) end
        Fire(nil, "index")
        if wanted and spawnMaps[wanted] then Fire(wanted, "ready") end
    elseif done then
        Fire(done, "ready")
    end
    return spawn.state == "index" or spawn.job ~= nil
end

local planned = false
local Step
local function Plan(seconds)
    if planned then return end
    local T = rawget(_G, "C_Timer")
    if type(T) ~= "table" or type(T.After) ~= "function" then return end    -- ohne Zeitgeber: Q.SpawnsFinish
    planned = true
    T.After(seconds or 0, Step)
end

Step = function()
    planned = false
    if Core.InCombat() then return Plan(1) end
    if Work() then Plan(0) end
end

function Q.SpawnsFinish()
    while Work() do end
end

function Q.ForgetSpawns()
    spawn, spawnMaps, spawnOrder, areaMaps, wanted = { state = "idle" }, {}, {}, {}, nil
end

function Q.SpawnState()
    local job = spawn.job
    if job then return spawn.state, job.pos - 1, #job.ids, job.map end
    return spawn.state, spawn.done, spawn.total
end

local function StartIndex(lib)
    local ok, err = pcall(function()
        local npcs, nNpcs = AllIds(lib, "npc")
        local objects, nObjects = AllIds(lib, "object")
        if nNpcs + nObjects == 0 then error(SHAPE, 0) end          -- keine einzige ID: falsche Form, nicht „leer“
        spawn = { state = "index", lib = lib, lists = { npc = npcs, object = objects },
            len = { npc = nNpcs, object = nObjects }, kind = "npc", pos = 1,
            done = 0, total = nNpcs + nObjects, skipped = 0, failed = 0, byMap = {} }
    end)
    if not ok then
        spawn.lib = lib
        if err == SHAPE then Fail("shape") else Fail("error", err) end
        return
    end
    Plan(0)
end

-- Kleinschreibung auch für Umlaute und Akzente (string.lower wirkt in Lua 5.1 nur auf ASCII; QuestieDB liefert die
-- Namen in der Sprache des Clients): Latin-1 in UTF-8 (À–Þ ohne ×) und Kyrillisch (А–Я, Ё). Q.Fold(text) → text
local function FoldLatin(c)
    local b = c:byte()
    if b == 0x97 then return nil end                                 -- × bleibt
    return "\195" .. string.char(b + 32)
end
local function FoldCyrillic(c)
    local b = c:byte()
    if b < 0xA0 then return "\208" .. string.char(b + 32) end       -- А–П » а–п
    return "\209" .. string.char(b - 32)                             -- Р–Я » р–я
end
function Q.Fold(text)
    if type(text) ~= "string" then return text end
    text = text:lower():gsub("\195([\128-\158])", FoldLatin):gsub("\208([\144-\175])", FoldCyrillic)
    return (text:gsub("\208\129", "\209\145"))                       -- Ё » ё
end

local function Filtered(raw, opts)
    opts = type(opts) == "table" and opts or {}
    local kinds = type(opts.kinds) == "table" and opts.kinds or { npc = true, object = true }
    local explorer = opts.explorer == true or Explorer()
    local needle = type(opts.name) == "string" and not Core.IsSecret(opts.name) and opts.name ~= ""
        and Q.Fold(opts.name) or nil
    local out = { map = raw.map, list = {}, n = { npc = 0, object = 0 }, points = 0, total = #raw.list,
        capped = false, cappedKinds = {}, hidden = { rare = 0 }, source = "Questie", sourceKey = "QuestieDB" }
    -- capped nur, wenn eine gefragte Art gedeckelt ist (bei „nur Objekte“ kein Hinweis wegen der Gegner)
    for kind in pairs(raw.cappedKinds or {}) do
        out.cappedKinds[kind] = true
        if kinds[kind] == true then out.capped = true end
    end
    for _, e in ipairs(raw.list) do
        local keep = kinds[e.kind] == true
        if keep and e.rare and not explorer then
            keep = false
            out.hidden.rare = out.hidden.rare + 1
        end
        if keep and type(opts.ids) == "table" then
            local set = opts.ids[e.kind]
            keep = type(set) == "table" and set[e.id] == true
        end
        if keep and type(opts.ranks) == "table" and e.kind == "npc" then keep = opts.ranks[Q.RankClass(e)] == true end
        if keep and needle then keep = e.name ~= nil and Q.Fold(e.name):find(needle, 1, true) ~= nil end
        if keep then
            out.list[#out.list + 1] = e
            out.n[e.kind] = out.n[e.kind] + 1
            out.points = out.points + #e.points
        end
    end
    return out
end

function Q.RankClass(e)
    if type(e) ~= "table" or e.kind ~= "npc" then return nil end
    if e.rare then return "rare" end
    if e.elite then return "elite" end
    return "normal"
end

function Q.SpawnsReady()
    local okReady, ready, why = pcall(Q.Ready)
    if not okReady then return false, "error" end
    if ready ~= true then return false, why or "shape" end
    local lib = Lib()
    if not (Reader(lib, "Npc", "GetAllIds") and Reader(lib, "Object", "GetAllIds")) then return false, "shape" end
    if spawn.lib == lib and (spawn.state == "shape" or spawn.state == "error") then return false, spawn.state end
    return true
end

function Q.Spawns(mapID, opts)
    mapID = ID(mapID)
    if not mapID then return nil, "map" end
    local lib = Lib()
    if lib and spawn.lib ~= nil and spawn.lib ~= lib then Q.ForgetSpawns() end   -- neues Global: neu aufbauen
    local ok, why = Q.SpawnsReady()
    if not ok then return nil, why end
    wanted = mapID
    local raw = spawnMaps[mapID]
    if raw then
        Touch(mapID)
        return Filtered(raw, opts)
    end
    if spawn.state == "idle" then StartIndex(lib) end
    if spawn.state == "index" then return nil, "building", spawn.done, spawn.total end
    if spawn.state ~= "ready" then return nil, spawn.state end
    if not (spawn.job and spawn.job.map == mapID) then StartMap(mapID) end
    raw = spawnMaps[mapID]
    if raw then return Filtered(raw, opts) end
    Plan(0)
    return nil, "building", spawn.job.pos - 1, #spawn.job.ids
end

-- Gegner und Objekte einer Quest bzw. eines Gegenstands (für die Filter „nur für eine Quest“, „nur für einen
-- Gegenstand“ in ezMap)
Q.QUEST_FIELDS = { "objectives", "startedBy", "finishedBy" }

local function AddIds(set, list)
    if type(list) ~= "table" then return end
    for i = 1, #list do
        local id = ID(Field(list, i))
        if id then set[id] = true end
    end
end

local function Part(t, i)
    local v = Field(t, i)
    return type(v) == "table" and v or {}
end

local function Targets(fn, ...)
    local okReady, ready, why = pcall(Q.Ready)
    if not okReady then return nil, "error" end
    if ready ~= true then return nil, why or "shape" end
    local ok, out, reason = pcall(fn, ...)
    if not ok then
        if out == SHAPE then return nil, "shape" end
        Core.Error(Core.name, out, "Questie.Targets")
        return nil, "error"
    end
    return out, reason
end

local function ItemSources(t, itemID)
    AddIds(t.npc, Read("Item", "npcDrops", itemID))
    AddIds(t.npc, Read("Item", "vendors", itemID))
    AddIds(t.object, Read("Item", "objectDrops", itemID))
end

function Q.QuestTargets(questID)
    questID = ID(questID)
    if not questID then return nil, "args" end
    return Targets(function()
        local lib = Lib()
        for _, field in ipairs(Q.QUEST_FIELDS) do
            if not Reader(lib, "Quest", field) then return nil, "shape" end
        end
        local t = { quest = questID, name = Text(Read("Quest", "name", questID)), npc = {}, object = {} }
        local obj = Read("Quest", "objectives", questID)
        for _, o in ipairs(Part(obj, 1)) do AddIds(t.npc, { Field(o, 1) }) end            -- Gegner
        for _, o in ipairs(Part(obj, 2)) do AddIds(t.object, { Field(o, 1) }) end         -- Objekte
        for _, o in ipairs(Part(obj, 3)) do                                               -- Gegenstände
            local item = ID(Field(o, 1))
            if item and (Sources.ClientKnowsItem(item) or Explorer()) then
                AddIds(t.npc, Read("Item", "npcDrops", item))
                AddIds(t.object, Read("Item", "objectDrops", item))
            end
        end
        for _, o in ipairs(Part(obj, 5)) do                                               -- Kill-Credit
            AddIds(t.npc, Field(o, 1))
            AddIds(t.npc, { Field(o, 2) })
        end
        for _, field in ipairs({ "startedBy", "finishedBy" }) do
            local by = Read("Quest", field, questID)
            AddIds(t.npc, Part(by, 1))
            AddIds(t.object, Part(by, 2))
        end
        return t
    end)
end

function Q.ItemTargets(itemID, opts)
    itemID = ID(itemID)
    if not itemID then return nil, "args" end
    if not Sources.ClientKnowsItem(itemID) and not Explorer() and not (type(opts) == "table" and opts.explorer == true) then
        return nil, "explorer"
    end
    return Targets(function()
        local t = { item = itemID, name = Text(Read("Item", "name", itemID)), npc = {}, object = {} }
        ItemSources(t, itemID)
        return t
    end)
end

---------------------------------------------------------------------------
-- Orte einer Quest getrennt nach Start, Zielen und Abgabe (Welle 27, Zweig modul/ezquest-levelroute: Leveling-Route in
-- ezQuest; Entwurf in docs/roadmap/ezQuest.md, Abschnitt „Leveling-Route – Entwurf“). QuestTargets legt alles zu einer
-- Menge zusammen (ezMaps Filter „nur für eine Quest“) und bleibt so.
--   Q.QuestPlaces(questID[, opts]) → { quest, name, level, next, start = { ort … }, finish = { ort … },
--       objectives = { { type = "monster" | "object" | "item" | "killcredit", id, name, places = { ort … }, capped,
--                        hidden = "explorer" | "rare" | nil } … } } | nil, grund
--   ort = { kind = "npc" | "object", id, name, area, map (uiMapID über MapForArea, sonst nil), x, y (0–1) }
--   Je Ziel höchstens Q.PLACES_PER_PART Orte (danach capped), je Start bzw. Abgabe höchstens Q.PLACES_PER_END.
--   Reihenfolge der Ziele wie in QuestieDB (Gegner, Objekte, Gegenstände, Kill-Credit); Gebiete aufsteigend.
--   opts.map (uiMapID, freiwillig; Fund der Gegenprüfung vom 17.11.2026): zuerst alle Orte auf dieser Karte (Gebiete,
--   deren Zonenkarte sie ist oder in ihr liegt), dann die übrigen – so schneidet die Grenze je Ziel die Zone des
--   Spielers nicht ab, auch wenn ein Gebiet mit kleinerer ID schon 60 Orte hat. Ohne opts wie vorher.
--   Gegenstände der Ziele nur, wenn der Client sie kennt oder mit Entdecker-Wissen (wie QuestTargets; sonst ohne Orte,
--   hidden = "explorer"); seltene Gegner (Rang 2 und 4) nur mit Entdecker-Wissen (hidden = "rare").
--   next aus Quest.nextQuestInChain und level aus Quest.questLevel, nur wenn QuestieDB die Lesefunktion hat.
--   Nichts gemerkt, nichts gespeichert (Leitlinie 10); braucht Quest.objectives/startedBy/finishedBy (sonst "shape").
---------------------------------------------------------------------------

Q.PLACES_PER_PART = 60
Q.PLACES_PER_END = 8

-- Liegt das Gebiet auf der Wunschkarte prefer (seine Zonenkarte ist sie oder liegt in ihr)?
local function OnPrefer(area, prefer)
    local map = MapOfArea(area)
    if not map then return false end
    if map == prefer then return true end
    local M = Core.Map
    return M ~= nil and type(M.Parent) == "function" and M.Parent(map, "Zone") == prefer
end

-- Orte eines Gegners bzw. Objekts in out (höchstens max) → true, wenn gedeckelt; "rare" für einen verborgenen Gegner.
-- Mit prefer nur die Gebiete auf der Wunschkarte (home = true) bzw. nur die übrigen (home = false).
local function SpawnPlaces(kind, id, out, max, prefer, home)
    local K = KIND_OF[kind]
    if kind == "npc" and not Explorer() and Q.RARE_RANKS[Num(Read("Npc", "rank", id)) or 0] then return false, "rare" end
    local spawns = Read(K, "spawns", id)
    if type(spawns) ~= "table" then return false end
    local name = Read(K, "name", id)
    name = type(name) == "string" and name ~= "" and name or nil
    local areas = {}
    for area, list in pairs(spawns) do
        if ID(area) and type(list) == "table" then areas[#areas + 1] = area end
    end
    table.sort(areas)
    for _, area in ipairs(areas) do
        if prefer == nil or OnPrefer(area, prefer) == home then
            local list = spawns[area]
            for i = 1, #list do
                if #out >= max then return true end
                local p = list[i]
                local x, y = Num(Field(p, 1)), Num(Field(p, 2))
                if x and y and x >= 0 and y >= 0 and x <= 100 and y <= 100 then     -- (-1, -1): Ort unbekannt
                    x, y = Q.Forever(area, x, y)
                    out[#out + 1] = { kind = kind, id = id, name = name, area = area, map = MapOfArea(area),
                        x = x / 100, y = y / 100 }
                end
            end
        end
    end
    return false
end

-- Orte mehrerer Gegner bzw. Objekte ({ { art, id } … }) in out bis max; mit prefer zuerst die Orte aller auf der
-- Wunschkarte, dann die übrigen → gedeckelt?, Grund eines verborgenen Gegners
local function PlacesOf(list, out, max, prefer)
    local hidden
    for pass = 1, prefer and 2 or 1 do
        for _, e in ipairs(list) do
            local c, why = SpawnPlaces(e[1], e[2], out, max, prefer, pass == 1)
            if why then hidden = why end
            if c then return true, hidden end
        end
    end
    return false, hidden
end

-- Orte einer Liste von Gegnern und Objekten ({ { npcIDs }, { objectIDs } } wie startedBy/finishedBy)
local function EndPlaces(by, prefer)
    local list = {}
    for _, id in ipairs(Part(by, 1)) do
        if ID(id) then list[#list + 1] = { "npc", id } end
    end
    for _, id in ipairs(Part(by, 2)) do
        if ID(id) then list[#list + 1] = { "object", id } end
    end
    local out = {}
    PlacesOf(list, out, Q.PLACES_PER_END, prefer)
    return out
end

local function Label(name, text)
    if type(name) == "string" and name ~= "" then return name end
    return type(text) == "string" and text ~= "" and text or nil
end

local function Optional(field, questID)
    if not Reader(Lib(), "Quest", field) then return nil end
    local ok, value = pcall(Read, "Quest", field, questID)
    return ok and value or nil
end

function Q.QuestPlaces(questID, opts)
    questID = ID(questID)
    if not questID then return nil, "args" end
    local prefer = type(opts) == "table" and ID(Num(opts.map)) or nil
    return Targets(function()
        local lib = Lib()
        for _, field in ipairs(Q.QUEST_FIELDS) do
            if not Reader(lib, "Quest", field) then return nil, "shape" end
        end
        local t = { quest = questID, name = Text(Read("Quest", "name", questID)), objectives = {} }
        t.level = ID(Num(Optional("questLevel", questID)))
        t.next = ID(Num(Optional("nextQuestInChain", questID)))
        local obj = Read("Quest", "objectives", questID)
        local function Add(entry, ids, kind)
            local list = {}
            for _, id in ipairs(ids) do list[#list + 1] = { kind, id } end
            local places = {}
            local capped, hidden = PlacesOf(list, places, Q.PLACES_PER_PART, prefer)
            entry.places, entry.capped = places, capped or nil
            if #places == 0 then entry.hidden = hidden end
            t.objectives[#t.objectives + 1] = entry
        end
        for _, o in ipairs(Part(obj, 1)) do                                               -- Gegner
            local id = ID(Field(o, 1))
            if id then
                local name = Read("Npc", "name", id)
                Add({ type = "monster", id = id, name = Label(name, Field(o, 2)) }, { id }, "npc")
            end
        end
        for _, o in ipairs(Part(obj, 2)) do                                               -- Objekte
            local id = ID(Field(o, 1))
            if id then
                local name = Read("Object", "name", id)
                Add({ type = "object", id = id, name = Label(name, Field(o, 2)) }, { id }, "object")
            end
        end
        for _, o in ipairs(Part(obj, 3)) do                                               -- Gegenstände
            local item = ID(Field(o, 1))
            if item then
                local entry = { type = "item", id = item }
                if Sources.ClientKnowsItem(item) or Explorer() then
                    local name = Read("Item", "name", item)
                    entry.name = type(name) == "string" and name or nil
                    local list = {}
                    for _, pair in ipairs({ { "npcDrops", "npc" }, { "objectDrops", "object" } }) do
                        local ids = Read("Item", pair[1], item)
                        for _, id in ipairs(type(ids) == "table" and ids or {}) do
                            if ID(id) then list[#list + 1] = { pair[2], id } end
                        end
                    end
                    local places = {}
                    local capped = PlacesOf(list, places, Q.PLACES_PER_PART, prefer)
                    entry.places, entry.capped = places, capped or nil
                else
                    entry.places, entry.hidden = {}, "explorer"
                end
                t.objectives[#t.objectives + 1] = entry
            end
        end
        for _, o in ipairs(Part(obj, 5)) do                                               -- Kill-Credit
            local ids = {}
            for _, id in ipairs(Part(o, 1)) do if ID(id) then ids[#ids + 1] = id end end
            local root = ID(Field(o, 2))
            if root then table.insert(ids, 1, root) end
            if #ids > 0 then
                local text = Field(o, 3)
                Add({ type = "killcredit", id = ids[1], name = type(text) == "string" and text or nil }, ids, "npc")
            end
        end
        t.start = EndPlaces(Read("Quest", "startedBy", questID), prefer)
        t.finish = EndPlaces(Read("Quest", "finishedBy", questID), prefer)
        return t
    end)
end

function Q.Register()
    return Sources.Register("QuestieDB", {
        label = "Questie",
        ready = Q.Ready,
        whereFrom = WhereFrom,
        lootOf = Q.LOOT and LootOf or nil,
    })
end
Q.Register()
