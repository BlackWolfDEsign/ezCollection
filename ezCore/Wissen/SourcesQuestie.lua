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
    Ob die Koordinaten in den vier Zonen mit geänderter Karte schon umgerechnet sind, war [unbestätigt] (DG-13):
    LibQuestieDB.EraToForever ist deshalb ab Werk nicht angewandt – Schalter Q.ERA_TO_FOREVER (false), eine Stelle
    Q.Forever für „Woher?“ und die Spawns. Spieltest vom 22.11.2026 in Sturmwind bestätigt das: neben „Auktionator
    Jaxon“ (15659) stand der Spieler bei 62,4 / 70,3, QuestieDB nennt 61,2 / 70,7, EraToForever ergäbe 67,0 / 79,1 –
    QuestieDB liefert dort schon Forever-Koordinaten.

      Core.Sources.Questie.Ready()        → true | false, "missing" | "shape" (wirft, wenn RequireContract wirft)
      Core.Sources.Questie.CONTRACT       Vertragsnummer, gegen die gebaut ist (4)
      Core.Sources.Questie.LOOT           lootOf (Beute je Gegner, ohne Chance) – ab Werk false (DG-16): eingeschaltet
                                          oder verworfen wird erst nach der Messung von Dauer und Speicher (DG-13).
                                          Gebaut als anlassbezogener Index (Empfehlung umgesetzt, Antwort offen): nur
                                          für den gefragten Gegner, nur über Gegenstände, die der Client dir schon
                                          gezeigt hat (cache.item, höchstens LOOT_SCAN), nichts gemerkt.
      Core.Sources.Questie.Register()     meldet die Quelle (neu) an – nach dem Umlegen von LOOT
      Core.Sources.Questie.Contents(art, id) → Inhalt eines Behälters bzw. einer Kiste (Umkehr-Index, unten)
      Core.Sources.Questie.ClassQuests(klasse) → Quests nur dieser Klasse (unten)
      Core.Sources.Questie.Exists(art, id) → true | false | nil (Item, Npc, Object, Quest; nil = keine Antwort)
      Core.Sources.Questie.MapForArea(areaID) → uiMapID | nil[, später]   Zuordnung über den Namen laut Client (C_Map),
                                          passt kein Name: QuestieDBs Zuordnung (LibQuestieDB.Support, als Text
                                          gelesen, nicht ausgeführt), dann Questies ZoneDB:GetUiMapIdByAreaId (seit
                                          22.11.2026, Sturmwind; nur Zonen); nur im Arbeitsspeicher (QuestieDB gruppiert
                                          Fundorte nach Gebiets-ID). später = true: Questie noch nicht bereit, nicht
                                          merken. Die Indizes (Spawns, Stadtbewohner) baut ezCore einmal je Sitzung: was
                                          beim Bau „später“ war, fehlt dort bis /reload bzw. ForgetSpawns/ForgetTownsfolk.
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

-- Karte im Client eine Zone? (wie BuildMaps; Dungeon-, Kontinent- und Kleinkarten nicht)
local function IsZoneMap(map)
    local info = Core.Call(Field(rawget(_G, "C_Map"), "GetMapInfo"), map)
    local mapType = type(info) == "table" and not Core.IsSecret(info) and Num(Field(info, "mapType")) or nil
    return mapType == 3                                      -- 3 = Enum.UIMapType.Zone
end

-- Zweite Quelle, wenn die Namen nicht passen (Leitlinie 11: zuerst der Client, dann die Datenbank eines installierten
-- Addons zur Laufzeit). Spielbefund vom 22.11.2026: Gebiet 1519 heißt im deutschen Client „Sturmwind“, die neue Karte
-- 1453 von WoW Forever aber „Stormwind“ – ohne diese Quelle fehlten alle Stadtbewohner Sturmwinds laut Questie.
-- Questies eigene Zuordnung: ZoneDB:GetUiMapIdByAreaId (Questie/Database/Zones/zoneDB.lua, gelesen nach Questies
-- LICENSE.md; nur aufgerufen, nichts kopiert). Nur, wenn Questie geladen ist – QuestieLoader:ImportModule legte sonst ein
-- leeres Modul in Questies Tabelle an. Die Karte muss im Client eine Zone sein (mapType 3, wie BuildMaps): Questies
-- Forever-Daten ordnen Dungeon-Gebiete Dungeon-Karten zu, deren Koordinaten laut QuestieDB nicht zu diesen Karten
-- gehören (Fund des code-reviewers vom 22.11.2026). Questie schreibt bei jedem Fehlschlag eine Debug-Zeile – im Chat nur
-- mit Questies eigener Debug-Ausgabe. Wirft Questie (Tabelle noch nicht geladen, Start fehlgeschlagen), fragt ezCore
-- Q.ZONE_RETRY Sekunden nicht erneut (sonst je Spawn im Index ein pcall); Q.ForgetSpawns/ForgetTownsfolk setzen das zurück.
-- → Karte | nil, später (true: Questie noch nicht bereit – das Ergebnis nicht merken)
Q.ZONE_MODULE = "ZoneDB"
Q.ZONE_RETRY = 5
local zoneLaterUntil = 0               -- Core.Uptime(): bis dahin Questies Zuordnung nicht fragen
local function QuestieZoneMap(areaID)
    if Core.Uptime() < zoneLaterUntil then return nil, true end
    local loader = rawget(_G, "QuestieLoader")
    if type(loader) ~= "table" or Core.IsSecret(loader) or type(loader.ImportModule) ~= "function" then return nil end
    if not Core.IsLoaded("Questie") then return nil end
    local ok, zoneDB = pcall(loader.ImportModule, loader, Q.ZONE_MODULE)
    local fn = ok and Field(zoneDB, "GetUiMapIdByAreaId") or nil
    if type(fn) ~= "function" then return nil end
    local okMap, map = pcall(fn, zoneDB, areaID)
    if not okMap then                                -- Questies Tabelle noch nicht geladen (Initialize steht aus)
        zoneLaterUntil = Core.Uptime() + Q.ZONE_RETRY
        return nil, true
    end
    map = ID(map)
    if not map or not IsZoneMap(map) then return nil end
    return map
end

-- Zweite Quelle auch ohne das Addon Questie (Auftrag des Nutzers vom 22.11.2026: „ok dann schließe die lücke noch“):
-- QuestieDB veröffentlicht dieselbe Zuordnung für Verbraucher über sein öffentliches Feld LibQuestieDB.Support
-- (Types/LibQuestieDB.t.lua „Support table Whole-table support data“; src/support/data.lua:
-- Support.Get("ZoneDB").private.areaIdToUiMapId und …Override, gelesen nach QuestieDBs LICENSE.md). Die Werte sind
-- Text der Form „return { [Gebiet] = Karte, … }“. ezCore führt ihn nicht aus (wie Serialize.lua: kein loadstring),
-- sondern liest nur die Paare „[Zahl] = Zahl“, Kommentare entfernt; erst die Grundtabelle, dann die Überschreibungen
-- (0 = bei Questie unterdrückt). Jede Karte prüft danach der Client (nur Zonen). Einmal je Sitzung gelesen, nur im
-- Arbeitsspeicher; Q.ForgetSpawns/ForgetTownsfolk lesen neu.
local supportZones                     -- [Gebiet] = Karte | false (nicht lesbar) | nil (noch nicht gelesen)

local function SupportPairs(value, into)
    if type(value) == "table" and not Core.IsSecret(value) then         -- schon entschlüsselt (künftige Fassung)
        local found = false
        for area, map in pairs(value) do
            local a = ID(area)
            if a then
                into[a] = ID(map) or false
                found = true
            end
        end
        return found
    end
    if type(value) ~= "string" or Core.IsSecret(value) then return false end
    -- Kommentare weg: erst Blockkommentare (--[[ … ]], --[=[ … ]=]), dann bis Zeilenende; ein „--“ in einem Text kann
    -- so nur Paare kosten, nie falsche erzeugen (Fund des code-reviewers vom 22.11.2026)
    local text = value:gsub("%-%-%[(=*)%[.-%]%1%]", ""):gsub("%-%-[^\n]*", "") .. "\n"
    local found = false
    -- nur ganze Zahlen mit Wortende dahinter (kein 0x…, 1453.5 oder verschachtelte Tabelle als Teilwert)
    for area, map in text:gmatch("%[%s*(%d+)%s*%]%s*=%s*(%d+)%s*[,}\n]") do
        local a = ID(tonumber(area))
        if a then
            into[a] = ID(tonumber(map)) or false
            found = true
        end
    end
    return found
end

local function SupportZones()
    if supportZones ~= nil then return supportZones end
    local support = Field(Lib(), "Support")
    local get = Field(support, "Get")
    if type(get) ~= "function" then return nil end          -- QuestieDB (noch) nicht da: beim nächsten Mal wieder
    local ok, zone = pcall(get, "ZoneDB")
    local private = ok and Field(zone, "private") or nil
    local out = {}
    if not SupportPairs(Field(private, "areaIdToUiMapId"), out) then
        supportZones = false
        return false
    end
    SupportPairs(Field(private, "areaIdToUiMapIdOverride"), out)
    supportZones = out
    return out
end

-- Reihenfolge (Leitlinie 11): Name laut Client, dann QuestieDBs Zuordnung, zuletzt Questies ZoneDB.
-- → Karte | nil, später (true: noch nicht merken – Questies Zuordnung war noch nicht bereit)
function Q.MapForArea(areaID)
    local name = AreaName(areaID)
    if name then
        if not mapByName then BuildMaps() end
        if mapByName[name] then return mapByName[name] end
    end
    if not ID(areaID) then return nil end
    local zones = SupportZones()
    local map = zones and zones[areaID] or nil
    if map and IsZoneMap(map) then return map end
    return QuestieZoneMap(areaID)
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

-- Name eines NPC bzw. Objekts laut QuestieDB ("Npc" | "Object") oder nil – für Beiträge anderer Spieler, die nur Nummern
-- führen (ShipView.lua); nur zur Laufzeit gelesen, nichts wird gespeichert
function Q.Name(kind, id)
    if not (Q.NEEDED[kind] and ID(id)) then return nil end
    local okReady, ready = pcall(Q.Ready)
    if not (okReady and ready == true) then return nil end
    local ok, name = pcall(Read, kind, "name", id)
    if not ok or type(name) ~= "string" or name == "" then return nil end
    return name
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
                      Mit opts.kinds.herb bzw. .ore (Paket „Fundorte“, 22.11.2026) trägt jedes Objekt dazu gather (Art:
                      "herb" | "ore" | "chest" | "fish" | "quest" | "container" | nil), gatherHow ("own" | "contents" |
                      "name") und gatherItem (ein Kraut bzw. Erz des Inhalts laut Questie oder nil) – bei jedem Aufruf
                      neu bestimmt (Abschnitt „Art der Objekte“ unten); n zählt dann auch herb und ore
          opts = { kinds = { npc = bool, object = bool, herb = bool, ore = bool } (Standard npc und object; nennt ein
                   Aufrufer herb oder ore, zählen Kräuter- und Erzvorkommen nicht mehr unter object, sondern unter
                   ihrer Art – ohne die beiden Felder bleiben sie Objekte wie vor dem Paket), name = Teil des Namens (ohne Groß- und
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
local KIND_OF = { npc = "Npc", object = "Object", item = "Item",   -- item: Inhalt von Behältern (Q.Contents)
    quest = "Quest" }                                              -- quest: Klassenquests (Q.ClassQuests)

if Core.RegisterMessage then
    Core.RegisterMessage("QUESTIE_SPAWNS", "SourcesQuestie.lua", "Spawns laut Questie: die Einträge einer Karte "
        .. "sind gelesen (karte, \"ready\"), der Index ist fertig (nil, \"index\") oder QuestieDB antwortet nicht "
        .. "wie erwartet (nil, \"shape\" | \"error\").", "karte | nil, zustand")
end

local spawn = { state = "idle" }       -- Index (nur IDs) und laufende Arbeit
local spawnMaps, spawnOrder = {}, {}   -- [Karte] = gelesene Einträge; Reihenfolge (neueste hinten)
local areaMaps = {}                    -- [Gebiets-ID] = Karte | false
local wanted                           -- zuletzt gefragte Karte
local gatherSources = {}               -- [Gegenstand] = Fundorte je Karte laut Questie (Q.GatherSources)
local gatherItemKinds = {}             -- [Gegenstand] = "herb" | "ore" | false (Klasse laut Client, ItemGather unten)
local ClassifyObjects, GatherIndex     -- Art der Objekte (Abschnitt „Art der Objekte“, nach dem Inhalt von Behältern)

local function MapOfArea(area)
    local map = areaMaps[area]
    if map == nil then
        local later
        map, later = Q.MapForArea(area)
        map = map or false
        if map or not later then areaMaps[area] = map end    -- „nicht gefunden“ erst merken, wenn Questie antwortet
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

-- Eine Scheibe Arbeit der Spawns. → true, wenn noch etwas aussteht
local function SpawnWork()
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

-- Erst die Spawns (Weltkarte), dann die Stadtbewohner (unten, TownWork) – ein Takt für beide, je Bild nur eine der
-- beiden Arbeiten (sonst bis zu zweimal SPAWN_BUDGET in einem Bild; Fund des code-reviewers vom 22.11.2026)
-- Danach der Index „Inhalt von Behältern“ (Q.Contents, 22.11.2026) und die Klassenquests (Q.ClassQuests, 24.11.2026) –
-- weiter nur eine Arbeit je Bild.
local TownWork, TownPending, ContentsWork, ContentsPending, ClassWork, ClassPending
local function ClassLeft() return ClassPending ~= nil and ClassPending() or false end
local function ContentsLeft() return ContentsPending ~= nil and ContentsPending() or ClassLeft() end
local function Work()
    if spawn.state == "index" or spawn.job then
        local more = SpawnWork()
        return more or (TownPending ~= nil and TownPending()) or ContentsLeft()
    end
    if TownPending ~= nil and TownPending() then
        local more = TownWork()
        return more or ContentsLeft()
    end
    if ContentsPending ~= nil and ContentsPending() then
        local more = ContentsWork()
        return more or ClassLeft()
    end
    return ClassWork ~= nil and ClassWork() or false
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
    zoneLaterUntil, supportZones = 0, nil
    gatherSources, gatherItemKinds = {}, {}
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
    -- Paket „Fundorte“: nennt der Aufrufer herb oder ore, trennt ezCore Kräuter- und Erzvorkommen von den Objekten
    local split = kinds.herb ~= nil or kinds.ore ~= nil
    if split then
        out.n.herb, out.n.ore = 0, 0
        -- nur, wenn überhaupt Objekte gefragt sind (für „nur Gegner“ keine Arbeit je Objekt)
        if kinds.object or kinds.herb or kinds.ore then
            out.sorting = ClassifyObjects(raw)   -- true: der Inhalt laut Questie wird noch gelesen (Index)
        end
    end
    -- capped nur, wenn eine gefragte Art gedeckelt ist (bei „nur Objekte“ kein Hinweis wegen der Gegner)
    for kind in pairs(raw.cappedKinds or {}) do
        out.cappedKinds[kind] = true
        if kinds[kind] == true or (kind == "object" and split and (kinds.herb or kinds.ore)) then out.capped = true end
    end
    for _, e in ipairs(raw.list) do
        local class = e.kind
        if split and class == "object" and (e.gather == "herb" or e.gather == "ore") then class = e.gather end
        local keep = kinds[class] == true
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
            out.n[class] = out.n[class] + 1
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
    -- Getrennt gefragt (herb bzw. ore genannt) und Objekte, Kräuter oder Erze gewünscht: den Inhalt laut Questie lesen
    -- lassen (Art der Objekte; einmal je Sitzung) – auch für „nur Objekte“, sonst hinge vom Zufall ab, welche Kräuter
    -- dort noch stehen (Fund des code-reviewers vom 22.11.2026)
    local kinds = type(opts) == "table" and type(opts.kinds) == "table" and opts.kinds or nil
    if kinds and (kinds.herb ~= nil or kinds.ore ~= nil) and (kinds.herb or kinds.ore or kinds.object) then
        GatherIndex()
    end
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

---------------------------------------------------------------------------
-- Stadtbewohner laut Questie: Lehrer, Händler, Reparierer (22.11.2026)
---------------------------------------------------------------------------
--[[
    Entscheidung des Nutzers vom 22.11.2026 auf „Lehrer- und Händlerlisten zur Laufzeit aus Questie füllen?“: „Ja,
    Questie zuerst“ (dazu: „und noch waffenmeister“). Die Lehrer- und Händlerlisten (Core.Npcs, ezMap) füllen sich vor
    dem ersten Besuch – laut Questie, nur zur Laufzeit, nichts gespeichert (Leitlinien 10, 11).

    Belegt an QuestieDBs öffentlichen Typen (Types/Npc.t.lua: subName, npcFlags „NPC flag bitmask“, friendlyToFaction
    "A" | "H" | "AH"; Types/LibQuestieDB.t.lua: Enum „Shared constants exposed to consumers“; gelesen am 22.11.2026 nach
    LICENSE.md). Die Bits der Rollen kommen zur Laufzeit aus LibQuestieDB.Enum.npcFlags (passend zur Spielversion,
    Namen in Q.TOWN_ROLES) – ezCore führt keine eigene Tabelle.

    Index: einmal über Npc.GetAllIds in Scheiben (derselbe Takt wie die Spawns, nach ihnen; je ID nur npcFlags, bei
    einer der Rollen dazu spawns); er merkt nur IDs mit einer der Rollen, je Karte. Lesen je Karte: name, subName,
    friendlyToFaction und der erste Punkt auf dieser Karte; die letzten Q.TOWN_MAPS Karten bleiben im Arbeitsspeicher.

      Q.TownsfolkReady() → true | false, grund ("missing" | "shape" | "error") – liest nichts, baut keinen Index
      Q.Townsfolk(mapID) → antwort | nil, grund[, fertig, gesamt]
          grund wie bei Q.Spawns ("building": die Nachricht QUESTIE_TOWNSFOLK (karte | nil, zustand) meldet das Ende)
          antwort = { map, list = { eintrag … }, source = "Questie", sourceKey = "QuestieDB" } – nur lesen
          eintrag = { id, name, title (subName oder nil), trainer, vendor, repair, innkeeper, banker, auctioneer,
                      stablemaster, battlemaster (true | nil; die weiteren nur, wenn das Enum sie kennt), faction ("Alliance" |
                      "Horde" | nil = beide), hostile (true: friendlyToFaction fehlt – laut Typ keiner Spielerfraktion
                      freundlich; Core.Npcs.Fits lässt ihn weg), map, x, y (0–1) }
      Q.ForgetTownsfolk() – Index und Karten verwerfen; Q.SpawnsFinish() erledigt auch diese Arbeit (Prüfungen)
    Fehlen die Lesefunktionen oder das Enum, meldet nur dieser Teil "shape"; die übrige Quelle bleibt „ok“.
]]
Q.TOWN_ROLES = { trainer = "TRAINER", vendor = "VENDOR", repair = "REPAIR" }
-- Weitere Rollen für die Pfeile an Blizzards Haken im Menü „Aufspüren“ (Entscheidung des Nutzers vom 22.11.2026:
-- „ok“ auf Gastwirt, Stallmeister, Auktionator, Bankier, Kampfmeister). Wahlweise: fehlt eine im Enum oder ist sie keine
-- Zweierpotenz, fehlt nur diese Rolle – der Teil bleibt „ok“.
Q.TOWN_EXTRA_ROLES = { innkeeper = "INNKEEPER", banker = "BANKER", auctioneer = "AUCTIONEER",
    stablemaster = "STABLEMASTER", battlemaster = "BATTLEMASTER" }
Q.TOWN_SLICE = 500         -- IDs je Bild beim Aufbau des Index (je ID nur npcFlags)
Q.TOWN_MAP_SLICE = 60      -- IDs je Bild beim Lesen einer Karte
Q.TOWN_MAPS = 60           -- so viele gelesene Karten bleiben im Arbeitsspeicher: alle Zonen von zwei Kontinenten
                           -- (ezMap fragt je Menü alle Zonen deines Kontinents; weniger hieße: immer neu lesen)
Q.TOWN_FIELDS = { "GetAllIds", "npcFlags", "spawns", "name", "subName", "friendlyToFaction" }

if Core.RegisterMessage then
    Core.RegisterMessage("QUESTIE_TOWNSFOLK", "SourcesQuestie.lua", "Lehrer und Händler laut Questie: die Einträge "
        .. "einer Karte sind gelesen (karte, \"ready\"), der Index ist fertig (nil, \"index\") oder QuestieDB antwortet "
        .. "nicht wie erwartet (nil, \"shape\" | \"error\").", "karte | nil, zustand")
end

local town = { state = "idle" }
local townMaps, townOrder = {}, {}
local townWanted = {}                  -- gefragte Karten, die nach dem Index der Reihe nach gelesen werden

-- Bits der Rollen aus QuestieDBs Enum: jede eine Zweierpotenz, sonst falsche Form. → { trainer = bit, … } oder nil
local function PowerOfTwo(v)
    if not v then return false end
    local p = 1
    while p < v do p = p * 2 end
    return p == v
end

local function TownBits(lib)
    local enum = Field(Field(lib, "Enum"), "npcFlags")
    if type(enum) ~= "table" or Core.IsSecret(enum) then return nil end
    local bits = {}
    for role, name in pairs(Q.TOWN_ROLES) do
        local v = ID(Field(enum, name))
        if not PowerOfTwo(v) then return nil end
        bits[role] = v
    end
    for role, name in pairs(Q.TOWN_EXTRA_ROLES) do
        local v = ID(Field(enum, name))
        if PowerOfTwo(v) then bits[role] = v end
    end
    return bits
end

local HasBit = Core.HasBit

function Q.TownsfolkReady()
    local okReady, ready, why = pcall(Q.Ready)
    if not okReady then return false, "error" end
    if ready ~= true then return false, why or "shape" end
    local lib = Lib()
    for _, field in ipairs(Q.TOWN_FIELDS) do
        if not Reader(lib, "Npc", field) then return false, "shape" end
    end
    if not TownBits(lib) then return false, "shape" end
    if town.lib == lib and (town.state == "shape" or town.state == "error") then return false, town.state end
    return true
end

local function TownFire(map, state) Core.Fire("QUESTIE_TOWNSFOLK", map, state) end

local function TownFail(reason, err)
    town = { state = reason, lib = town.lib }
    townWanted = {}
    if reason == "error" then Core.Error(Core.name, err, "Questie.Townsfolk") end
    TownFire(nil, reason)
end

function Q.ForgetTownsfolk()
    town, townMaps, townOrder, townWanted = { state = "idle" }, {}, {}, {}
    zoneLaterUntil, supportZones = 0, nil
end

local function TownIndexSlice()
    local idx, start, n = town, SliceMillis(), 0
    while idx.pos <= idx.len do
        local id = ID(Field(idx.list, idx.pos))
        idx.pos, idx.done, n = idx.pos + 1, idx.done + 1, n + 1
        local okRead, flags = true, nil
        if id then okRead, flags = pcall(Read, "Npc", "npcFlags", id) end
        if not okRead then
            Broken(idx, idx.done, flags)
        elseif type(flags) == "number" and flags > 0 then
            local roles
            for role, bit in pairs(idx.bits) do
                if HasBit(flags, bit) then
                    roles = roles or {}
                    roles[role] = true
                end
            end
            if roles then
                local okSpawns, spawns = pcall(Read, "Npc", "spawns", id)
                if not okSpawns then
                    Broken(idx, idx.done, spawns)
                elseif type(spawns) == "table" then
                    idx.roles[id] = roles
                    for area, points in pairs(spawns) do
                        local map = ID(area) and type(points) == "table" and MapOfArea(area) or nil
                        if map then
                            local at = idx.byMap[map]
                            if not at then
                                at = {}
                                idx.byMap[map] = at
                            end
                            if at[#at] ~= id then at[#at + 1] = id end
                        end
                    end
                end
            end
        elseif flags ~= nil and type(flags) ~= "number" then
            idx.skipped = idx.skipped + 1
        end
        if Over(start, n, Q.TOWN_SLICE) then return false end
    end
    return true
end

local FACTION = { A = "Alliance", H = "Horde" }

-- Ein Eintrag der Karte map (nil: ohne Namen oder ohne Punkt auf dieser Karte)
local function TownEntry(id, map, roles)
    local name = Text(Read("Npc", "name", id))
    if not name then return nil end
    local spawns = Read("Npc", "spawns", id)
    if type(spawns) ~= "table" then return nil end
    local x, y
    for area, list in pairs(spawns) do
        if ID(area) and type(list) == "table" and MapOfArea(area) == map then
            for i = 1, #list do
                local p = list[i]
                local px, py = Num(Field(p, 1)), Num(Field(p, 2))
                if px and py and px >= 0 and py >= 0 and px <= 100 and py <= 100 then   -- (-1, -1): Ort unbekannt
                    px, py = Q.Forever(area, px, py)
                    x, y = px / 100, py / 100
                    break
                end
            end
        end
        if x then break end
    end
    if not x then return nil end
    local friendly = Read("Npc", "friendlyToFaction", id)
    local e = { id = id, name = name, title = Text(Read("Npc", "subName", id)), faction = FACTION[friendly],
        hostile = friendly == nil or nil, map = map, x = x, y = y }
    for role in pairs(roles) do e[role] = true end       -- trainer, vendor, repair und die weiteren Rollen
    return e
end

-- Zuletzt benutzte Karte nach hinten (verdrängt wird die am längsten nicht gefragte, nicht die zuerst gelesene)
local function TownTouch(map)
    for i = #townOrder, 1, -1 do
        if townOrder[i] == map then
            table.remove(townOrder, i)
            break
        end
    end
    townOrder[#townOrder + 1] = map
end

local function TownStore(result)
    local map = result.map
    TownTouch(map)
    townMaps[map] = result
    while #townOrder > Q.TOWN_MAPS do
        townMaps[table.remove(townOrder, 1)] = nil
    end
end

-- Karte in Arbeit nehmen → true, wenn Einträge zu lesen sind (ohne IDs ist sie sofort fertig und leer)
local function TownStartMap(map)
    local ids = town.byMap and town.byMap[map] or {}
    local result = { map = map, list = {}, source = "Questie", sourceKey = "QuestieDB", skipped = 0, failed = 0 }
    if #ids == 0 then
        TownStore(result)
        return false
    end
    town.job = { map = map, ids = ids, pos = 1, result = result }
    return true
end

local function TownMapSlice(job)
    local start, n, result = SliceMillis(), 0, job.result
    while job.pos <= #job.ids do
        local id = job.ids[job.pos]
        job.pos, n = job.pos + 1, n + 1
        local okEntry, e = pcall(TownEntry, id, job.map, town.roles[id] or {})
        if not okEntry then
            Broken(result, job.pos - 1, e)
        elseif e then
            result.list[#result.list + 1] = e
        end
        if Over(start, n, Q.TOWN_MAP_SLICE) and job.pos <= #job.ids then return false end
    end
    table.sort(result.list, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    return true
end

-- Die nächste gefragte Karte, die noch fehlt, in Arbeit nehmen → true, wenn eine läuft
local function TownNext()
    if town.job then return true end      -- ein Empfänger von QUESTIE_TOWNSFOLK hat schon eine Karte angestoßen
    while #townWanted > 0 do
        local map = table.remove(townWanted, 1)
        if not townMaps[map] and TownStartMap(map) then return true end
        if townMaps[map] then TownFire(map, "ready") end
    end
    return false
end

TownPending = function() return town.state == "index" or town.job ~= nil end

TownWork = function()
    if not TownPending() then return false end
    local ok, done = pcall(function()
        if town.state == "index" then
            if not TownIndexSlice() then return nil end
            town.state, town.list = "ready", nil
            return "index"
        end
        if not TownMapSlice(town.job) then return nil end
        local result = town.job.result
        town.job = nil
        TownStore(result)
        return result.map
    end)
    if not ok then
        if done == SHAPE then TownFail("shape") else TownFail("error", done) end
        return false
    end
    if done == "index" then
        TownFire(nil, "index")
        TownNext()
    elseif done then
        TownFire(done, "ready")
        TownNext()
    end
    return town.state == "index" or town.job ~= nil
end

local function TownStartIndex(lib)
    local ok, err = pcall(function()
        local list, n = AllIds(lib, "npc")
        if n == 0 then error(SHAPE, 0) end
        town = { state = "index", lib = lib, list = list, len = n, pos = 1, done = 0, total = n, skipped = 0,
            failed = 0, byMap = {}, roles = {}, bits = TownBits(lib) }
    end)
    if not ok then
        town.lib = lib
        if err == SHAPE then TownFail("shape") else TownFail("error", err) end
        return
    end
    Plan(0)
end

function Q.Townsfolk(mapID)
    mapID = ID(mapID)
    if not mapID then return nil, "map" end
    local lib = Lib()
    if lib and town.lib ~= nil and town.lib ~= lib then Q.ForgetTownsfolk() end   -- neues Global: neu aufbauen
    local ok, why = Q.TownsfolkReady()
    if not ok then return nil, why end
    local raw = townMaps[mapID]
    if raw then
        TownTouch(mapID)
        return raw
    end
    if town.state == "idle" then TownStartIndex(lib) end
    if town.state ~= "index" and town.state ~= "ready" then return nil, town.state end
    local queued = town.job ~= nil and town.job.map == mapID
    for _, m in ipairs(townWanted) do
        if m == mapID then queued = true end
    end
    if not queued then townWanted[#townWanted + 1] = mapID end
    if town.state == "ready" and not town.job then TownNext() end
    raw = townMaps[mapID]
    if raw then return raw end
    Plan(0)
    if town.state == "index" then return nil, "building", town.done, town.total end
    if town.job and town.job.map == mapID then return nil, "building", town.job.pos - 1, #town.job.ids end
    return nil, "building"          -- wartet hinter einer anderen Karte (kein Fortschritt dieser Karte bekannt)
end

--[[
    Inhalt von Behältern und Kisten laut Questie (Entscheidung des Nutzers vom 22.11.2026, wörtlich: „zusätzlich „laut
    Questie““; Anzeige in ezLoot, Contents.lua). QuestieDB kennt nur die Richtung Gegenstand » Quelle (Types/Item.t.lua:
    itemDrops „Items that contain this item“, objectDrops „Objects that drop this item“, GetAllIds; gelesen am
    22.11.2026 nach LICENSE.md). Die Umkehr Quelle » Inhalt baut ezCore einmal als Index im Arbeitsspeicher: über
    Item.GetAllIds in Scheiben (derselbe Takt wie Spawns und Stadtbewohner, nach ihnen; je ID nur itemDrops und
    objectDrops). Gemerkt werden nur IDs (Behälter bzw. Objekt » Gegenstände), nichts gespeichert, nichts kopiert
    (Leitlinie 10). QuestieDB führt vor allem Quest-Gegenstände – die Liste ist nie vollständig und nennt keine Chance.

      Q.ContentsReady() → true | false, grund ("missing" | "shape" | "error") – liest nichts, baut keinen Index
      Q.Contents(kind, id) → antwort | nil, grund[, fertig, gesamt]
          kind = "item" (Behälter in der Tasche) | "object" (Kiste in der Welt); grund "building" (Index läuft; die
          Nachricht QUESTIE_CONTENTS (nil, zustand) meldet das Ende), "missing", "shape", "error", "none"
          antwort = { kind, id, items = { { id, listed = true } … } (höchstens Q.CONTENTS_MAX), n (alle sichtbaren,
          ohne verschleierte), listed = true, source = "Questie", sourceKey = "QuestieDB" } – nur lesen
          Verschleierte Gegenstände (der Client kennt sie nicht, nicht enthüllt) nur mit Entdecker-Wissen (DG-18)
      Q.ContentsState() → zustand, fertig, gesamt
      Q.ForgetContents() – Index verwerfen; Q.SpawnsFinish() erledigt auch diese Arbeit (Prüfungen)
    Fehlen die Lesefunktionen, meldet nur dieser Teil "shape"; die übrige Quelle bleibt „ok“.
]]
Q.CONTENTS_SLICE = 500     -- IDs je Bild beim Aufbau des Index (je ID itemDrops und objectDrops)
Q.CONTENTS_MAX = 40        -- höchstens so viele Gegenstände je Antwort
Q.CONTENTS_FIELDS = { "GetAllIds", "itemDrops", "objectDrops" }
local BOX_LISTS = { item = "byItem", object = "byObject" }

if Core.RegisterMessage then
    Core.RegisterMessage("QUESTIE_CONTENTS", "SourcesQuestie.lua", "Inhalt von Behältern und Kisten laut Questie: der "
        .. "Index ist fertig (nil, \"index\") oder QuestieDB antwortet nicht wie erwartet (nil, \"shape\" | \"error\").",
        "nil, zustand")
end

local box = { state = "idle" }

function Q.ContentsReady()
    local okReady, ready, why = pcall(Q.Ready)
    if not okReady then return false, "error" end
    if ready ~= true then return false, why or "shape" end
    local lib = Lib()
    for _, field in ipairs(Q.CONTENTS_FIELDS) do
        if not Reader(lib, "Item", field) then return false, "shape" end
    end
    if box.lib == lib and (box.state == "shape" or box.state == "error") then return false, box.state end
    return true
end

local function BoxFire(state) Core.Fire("QUESTIE_CONTENTS", nil, state) end

local function BoxFail(reason, err)
    box = { state = reason, lib = box.lib }
    if reason == "error" then Core.Error(Core.name, err, "Questie.Contents") end
    BoxFire(reason)
end

function Q.ForgetContents() box = { state = "idle" } end

-- Quellen einer Liste (itemDrops bzw. objectDrops eines Gegenstands) in den Index: Quelle » Gegenstand. Ein
-- unbrauchbarer Eintrag wird übersprungen und gezählt.
local function BoxAdd(idx, value, map, itemID)
    if value == nil then return end
    if type(value) ~= "table" then
        idx.skipped = idx.skipped + 1
        return
    end
    for i = 1, #value do
        local src = ID(Field(value, i))
        if src then
            local list = map[src]
            if not list then
                list = {}
                map[src] = list
            end
            if list[#list] ~= itemID then list[#list + 1] = itemID end
        else
            idx.skipped = idx.skipped + 1
        end
    end
end

local function BoxIndexSlice()
    local idx, start, n = box, SliceMillis(), 0
    while idx.pos <= idx.len do
        local id = ID(Field(idx.list, idx.pos))
        idx.pos, idx.done, n = idx.pos + 1, idx.done + 1, n + 1
        if not id then
            idx.skipped = idx.skipped + 1          -- Loch oder ungültige ID in der Liste (wie bei den Spawns)
        else
            local okItems, items = pcall(Read, "Item", "itemDrops", id)
            local okObjects, objects = pcall(Read, "Item", "objectDrops", id)
            if not okItems then
                Broken(idx, idx.done, items)
            elseif not okObjects then
                Broken(idx, idx.done, objects)
            else
                BoxAdd(idx, items, idx.byItem, id)
                BoxAdd(idx, objects, idx.byObject, id)
            end
        end
        if Over(start, n, Q.CONTENTS_SLICE) then return false end
    end
    return true
end

ContentsPending = function() return box.state == "index" end

ContentsWork = function()
    if not ContentsPending() then return false end
    local ok, done = pcall(BoxIndexSlice)
    if not ok then
        if done == SHAPE then BoxFail("shape") else BoxFail("error", done) end
        return false
    end
    if not done then return true end
    box.state, box.list = "ready", nil
    BoxFire("index")
    return false
end

local function BoxStartIndex(lib)
    local ok, err = pcall(function()
        local list, n = AllIds(lib, "item")
        if n == 0 then error(SHAPE, 0) end
        box = { state = "index", lib = lib, list = list, len = n, pos = 1, done = 0, total = n, skipped = 0,
            failed = 0, byItem = {}, byObject = {} }
    end)
    if not ok then
        box.lib = lib
        if err == SHAPE then BoxFail("shape") else BoxFail("error", err) end
        return
    end
    Plan(0)
end

function Q.ContentsState() return box.state, box.done, box.total end

function Q.Contents(kind, id)
    local field = BOX_LISTS[kind]
    id = ID(id)
    if not (field and id) then return nil, "none" end
    local lib = Lib()
    if lib and box.lib ~= nil and box.lib ~= lib then Q.ForgetContents() end   -- neues Global: neu aufbauen
    local ok, why = Q.ContentsReady()
    if not ok then return nil, why end
    if box.state == "idle" then BoxStartIndex(lib) end
    if box.state == "index" then
        Plan(0)
        return nil, "building", box.done, box.total
    end
    if box.state ~= "ready" then return nil, box.state end
    local ids = box[field][id]
    if not ids then return nil, "none" end
    -- n zählt nur sichtbare Gegenstände: die Zahl verschleierter wäre schon Entdecker-Wissen (Gegenprüfung 22.11.2026)
    local items, explorer, visible = {}, Explorer(), 0
    for i = 1, #ids do
        local itemID = ids[i]
        if explorer or Sources.ClientKnowsItem(itemID) then
            visible = visible + 1
            if #items < Q.CONTENTS_MAX then items[#items + 1] = { id = itemID, listed = true } end
        end
    end
    if #items == 0 then return nil, "none" end
    return { kind = kind, id = id, items = items, n = visible, listed = true, source = "Questie", sourceKey = "QuestieDB" }
end

--[[
    Art der Objekte laut Questie (Paket „Fundorte“, 22.11.2026; Prüfung der Fundorte vom selben Tag): QuestieDB trennt
    Kräuter, Erzadern, Kisten und Quest-Objekte nicht (Types/Object.t.lua kennt kein Feld für die Art; der Client nennt
    das Schloss eines Objekts nicht – „welches Spielobjekt welches Schloss hat, weiß nur der Server“, Client/Locks.lua).
    ezCore bestimmt die Art je Objekt einer Karte, der Reihe nach:
      "own"       deine Beobachtung desselben Objekts (Core.Gathering.ObjectKind: Sammelzauber bzw. Klasse der Beute
                  laut Client, Entdecker-Datenbank)
      "contents"  der Inhalt laut Questie (Umkehr-Index von Q.Contents: Gegenstände, die das Objekt fallen lässt) mit der
                  Klasse laut Client (Core.Gathering.ItemKind): nur Kräuter » herb, nur Erz und Stein » ore; beides
                  zugleich oder keins: keine Art (andere Gegenstände – Edelsteine, Quest-Gegenstände – zählen nicht)
      "name"      derselbe Name wie ein schon erkanntes Objekt dieser Karte (QuestieDB führt ein Vorkommen oft unter
                  mehreren IDs; die Namen kommen in der Sprache des Clients) – nur, wenn alle erkannten mit diesem Namen
                  dieselbe Art haben
    Ohne Art bleibt ein Objekt „Objekt“ (Kisten, Quest-Objekte, Unbekanntes). Den Index liest ezCore erst, wenn ein Modul
    getrennt fragt (herb bzw. ore genannt) und Objekte, Kräuter oder Erze will (GatherIndex aus Q.Spawns); bis er fertig
    ist, erkennt nur "own" (und "name"), die Antwort trägt sorting = true und die Nachricht QUESTIE_CONTENTS meldet das
    Ende. Die Felder gather, gatherHow, gatherItem setzt ezCore selbst an seinen gemerkten Einträgen (bei jedem
    getrennten Aufruf neu); Aufrufer lesen sie nur.
]]
-- Klasse laut Client je Gegenstand (ändert sich im Spiel nicht; gemerkt bis Q.ForgetSpawns)
local function ItemGather(itemID)
    local k = gatherItemKinds[itemID]
    if k == nil then
        local G = Core.Gathering
        k = G and type(G.ItemKind) == "function" and G.ItemKind(itemID) or false
        gatherItemKinds[itemID] = k
    end
    return k or nil
end

-- Art aus dem Inhalt laut Questie → "herb" | "ore" | nil, ein Gegenstand dieser Art
local function ContentsGather(id)
    if box.state ~= "ready" or box.lib ~= Lib() then return nil end
    local items = box.byObject and box.byObject[id]
    if not items then return nil end
    local kind, item
    for i = 1, #items do
        local k = ItemGather(items[i])
        if k then
            if kind and kind ~= k then return nil end
            kind, item = k, item or items[i]
        end
    end
    return kind, item
end

-- Leser der eigenen Beobachtung (Core.Gathering.ObjectKinds: Datenbank einmal je Durchgang) → fn(id) → Art | nil
local function OwnKinds()
    local G = Core.Gathering
    if G and type(G.ObjectKinds) == "function" then return G.ObjectKinds() end
    return function() return nil end
end

local function KindOf(id, own)
    local kind, item = ContentsGather(id)
    local seen = own(id)
    if seen then return seen, "own", kind == seen and item or nil end
    if kind then return kind, "contents", item end
    return nil
end

-- Art eines Objekts → Art, Herkunft ("own" | "contents"), Gegenstand | nil
function Q.ObjectKind(id)
    id = ID(id)
    if not id then return nil end
    return KindOf(id, OwnKinds())
end

ClassifyObjects = function(raw)
    local byName, own = {}, OwnKinds()
    for _, e in ipairs(raw.list) do
        if e.kind == "object" then
            e.gather, e.gatherHow, e.gatherItem = KindOf(e.id, own)
            if e.gather and e.name then
                local key = Q.Fold(e.name)
                local seen = byName[key]
                if seen == nil then
                    byName[key] = { kind = e.gather, item = e.gatherItem }
                elseif seen and seen.kind ~= e.gather then
                    byName[key] = false          -- derselbe Name, verschiedene Arten: nicht übertragen
                elseif seen and not seen.item then
                    seen.item = e.gatherItem
                end
            end
        end
    end
    for _, e in ipairs(raw.list) do
        if e.kind == "object" and not e.gather and e.name then
            local seen = byName[Q.Fold(e.name)]
            if seen then e.gather, e.gatherHow, e.gatherItem = seen.kind, "name", seen.item end
        end
    end
    return box.state == "index"
end

-- Den Inhalt laut Questie einmal je Sitzung lesen lassen (derselbe Index wie Q.Contents) → true, wenn er läuft oder fertig ist
GatherIndex = function()
    local lib = Lib()
    if lib and box.lib ~= nil and box.lib ~= lib then Q.ForgetContents() end
    if box.state == "idle" then
        if not Q.ContentsReady() then return false end
        BoxStartIndex(lib)
    end
    return box.state == "index" or box.state == "ready"
end

--[[
    Fundorte eines Krauts bzw. Erzes laut Questie für die Tooltip-Zeile „Fundorte“ (Core.Gathering.Sources und Line;
    Paket „Fundorte“, 22.11.2026): die Objekte, die den Gegenstand fallen lassen (Item.objectDrops, höchstens
    Q.GATHER_OBJECTS), deren spawns je Zone gezählt (Gebiet » Karte über Q.MapForArea, Punkte ohne Ort zählen nicht).
    Nur für Kräuter und Erze laut Client (Core.Gathering.ItemKind). Im Tooltip immer „laut Questie“, nie „bei dir“
    (Core.Gathering.Line nennt jede Quelle außer der eigenen „laut <Name>“). Gemerkt wird nur die Zahl je Karte, im
    Arbeitsspeicher bis Q.ForgetSpawns; war Questie beim Lesen noch nicht bereit (Gebiet „später“), nicht gemerkt.
      Q.GatherSources(itemID) → { { mapID, count } … }, meiste zuerst (leer ohne QuestieDB bzw. für andere Gegenstände)
]]
Q.GATHER_OBJECTS = 40

function Q.GatherSources(itemID)
    itemID = ID(itemID)
    if not (itemID and ItemGather(itemID)) then return {} end
    local hit = gatherSources[itemID]
    if hit and hit.lib == Lib() then return hit.list end
    local okReady, ready = pcall(Q.Ready)
    if not (okReady and ready == true) then return {} end
    local okList, objects = pcall(function() return IdList(Read("Item", "objectDrops", itemID)) end)
    if not okList then return {} end
    local byMap, later = {}, false
    for i = 1, math.min(#objects, Q.GATHER_OBJECTS) do
        local okSpawns, spawns = pcall(Read, "Object", "spawns", objects[i])
        if okSpawns and type(spawns) == "table" then
            for area, list in pairs(spawns) do
                if ID(area) and type(list) == "table" then
                    local map = MapOfArea(area)
                    if not map and areaMaps[area] == nil then later = true end   -- Questie noch nicht bereit
                    if map then
                        local n = 0
                        for k = 1, #list do
                            local p = list[k]
                            local x, y = Num(Field(p, 1)), Num(Field(p, 2))
                            if x and y and x >= 0 and y >= 0 and x <= 100 and y <= 100 then n = n + 1 end
                        end
                        if n > 0 then byMap[map] = (byMap[map] or 0) + n end
                    end
                end
            end
        end
    end
    local out = {}
    for map, count in pairs(byMap) do out[#out + 1] = { mapID = map, count = count } end
    table.sort(out, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.mapID < b.mapID
    end)
    if not later then gatherSources[itemID] = { lib = Lib(), list = out } end
    return out
end

if Core.Gathering and type(Core.Gathering.AddProvider) == "function" then
    Core.Gathering.AddProvider("QuestieDB", "Questie", Q.GatherSources, { active = function()
        local ok, yes = pcall(Q.Ready)
        return ok and yes == true
    end })
end

-- Auskunft für Core.Sources (contentsOf(id, kind)): läuft der Index noch oder ist nur dieser Teil kaputt (fehlende
-- Lesefunktion, viele Fehler – steht schon in der Fehlerliste), hat die Quelle nicht nachgesehen ("skip"). Nie
-- "shape": das kippte den Stand der ganzen Quelle in /ez status und Sources.Hint (Gegenprüfung 22.11.2026).
local function ContentsOf(id, kind)
    local result, why = Q.Contents(kind, id)
    if result then return result end
    if why == "none" then return nil end
    return nil, "skip"
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
--   Je Ziel höchstens Q.PLACES_PER_PART Orte (danach capped; opts.places: eigene Grenze), je Start bzw. Abgabe höchstens Q.PLACES_PER_END.
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
    local perPart = type(opts) == "table" and ID(Num(opts.places)) or Q.PLACES_PER_PART
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
            local capped, hidden = PlacesOf(list, places, perPart, prefer)
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
                    local capped = PlacesOf(list, places, perPart, prefer)
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

--[[
    Klassenquests (24.11.2026, „Wo kommt was“ – Klassenquests, die eine Fähigkeit bringen): alle Quests, die laut
    QuestieDB nur eine Klasse annehmen darf (requiredClasses = genau deren Bit laut Enum.classKeys). Der Index entsteht
    beim ersten Aufruf in Scheiben (derselbe Takt, nach den anderen Arbeiten); gemerkt werden nur im Arbeitsspeicher
    Kennung, Stufe, Volksmaske und Anfang der Treffer. Ob die Quest eine Fähigkeit bringt, weiß QuestieDB nicht – das sagt
    der Client bzw. die Faktenliste (Core.SpellSources, Core.QuestSpells); dafür der englische Grundname (Quest.GetRaw, laut
    Types/Quest.t.lua „base data without Corrections or localization“; wahlweise).
      Q.ClassQuests(klasse) → antwort | nil, grund[, fertig, gesamt]   klasse = Token ("MAGE" …)
          grund wie bei Q.Spawns („building“: die Nachricht QUESTIE_CLASSQUESTS (klasse, zustand) meldet das Ende) oder
          "class" (QuestieDB nennt kein Bit dieser Klasse)
          antwort = { class, list = { { id, name, level (nötige Stufe oder nil), base (Grundname oder nil) } … }, source = "Questie", sourceKey =
                      "QuestieDB" } – nach Stufe, dann Name; ohne Quests anderer Völker (Enum.raceMaskById) und ohne
                      solche, deren Geber laut friendlyToFaction alle nur zur anderen Fraktion gehören; nur lesen
      Q.QuestStart(questID, { map }) → Orte, an denen die Quest beginnt, wie QuestPlaces(…).start (ohne die Ziele zu lesen)
      Q.ForgetClassQuests() – Index verwerfen; Q.SpawnsFinish() erledigt auch diese Arbeit (Prüfungen)
    Fehlen die Lesefunktionen, meldet nur dieser Teil "shape"; die übrige Quelle bleibt „ok“.
]]
Q.CLASS_SLICE = 500        -- IDs je Bild beim Aufbau des Index (je ID nur requiredClasses)
Q.CLASS_FIELDS = { "GetAllIds", "requiredClasses", "requiredRaces", "requiredLevel", "startedBy", "name" }

if Core.RegisterMessage then
    Core.RegisterMessage("QUESTIE_CLASSQUESTS", "SourcesQuestie.lua", "Klassenquests laut Questie: der Index einer "
        .. "Klasse ist fertig (klasse, \"ready\") oder QuestieDB antwortet nicht wie erwartet (klasse, \"shape\" | "
        .. "\"error\").", "klasse, zustand")
end

local klass = { state = "idle" }

-- Bit einer Klasse laut QuestieDBs Enum (Schlüssel in beliebiger Schreibung) → Zweierpotenz oder nil
local function ClassBit(lib, class)
    local enum = Field(Field(lib, "Enum"), "classKeys")
    if type(enum) ~= "table" or Core.IsSecret(enum) then return nil end
    for key, value in pairs(enum) do
        if type(key) == "string" and key:upper() == class then
            local v = ID(value)
            if PowerOfTwo(v) then return v end
        end
    end
    return nil
end

local function ClassFire(state) Core.Fire("QUESTIE_CLASSQUESTS", klass.class, state) end

local function ClassFail(reason, err)
    klass = { state = reason, lib = klass.lib, class = klass.class }
    if reason == "error" then Core.Error(Core.name, err, "Questie.ClassQuests") end
    ClassFire(reason)
end

function Q.ForgetClassQuests() klass = { state = "idle" } end

-- Grundname der Quest ohne Übersetzung (wahlweise; QuestieDB ohne GetRaw, falsche Form oder gesperrt: nil – die Quest
-- bleibt). GetRaw liest laut Questie ohne Korrekturen: Quests, die nur dort stehen, haben keinen.
local function BaseName(lib, id)
    local fn = Reader(lib, "Quest", "GetRaw")
    if not fn then return nil end
    local ok, value = pcall(fn, id, "name")
    if not ok or Core.IsSecret(value) or type(value) ~= "string" or value == "" then return nil end
    return value
end

local function ClassIndexSlice()
    local idx, start, n = klass, SliceMillis(), 0
    while idx.pos <= idx.len do
        local id = ID(Field(idx.ids, idx.pos))
        idx.pos, idx.done, n = idx.pos + 1, idx.done + 1, n + 1
        if not id then
            idx.skipped = idx.skipped + 1
        else
            local okMask, mask = pcall(Read, "Quest", "requiredClasses", id)
            if not okMask then
                Broken(idx, idx.done, mask)
            elseif mask == idx.bit then
                local ok, e = pcall(function()
                    local e = { id = id, name = Text(Read("Quest", "name", id)), level = ID(Read("Quest", "requiredLevel", id)),
                        races = Num(Read("Quest", "requiredRaces", id)) or 0, starts = {}, base = BaseName(idx.lib, id) }
                    local by = Read("Quest", "startedBy", id)
                    for _, npc in ipairs(Part(by, 1)) do
                        if ID(npc) then e.starts[#e.starts + 1] = npc end
                    end
                    e.other = #Part(by, 2) > 0 or #Part(by, 3) > 0      -- beginnt auch an einem Objekt bzw. Gegenstand
                    return e
                end)
                if not ok then
                    Broken(idx, idx.done, e)
                elseif e.name then
                    idx.found[#idx.found + 1] = e
                end
            end
        end
        if Over(start, n, Q.CLASS_SLICE) then return false end
    end
    return true
end

ClassPending = function() return klass.state == "index" end

ClassWork = function()
    if not ClassPending() then return false end
    local ok, done = pcall(ClassIndexSlice)
    if not ok then
        if done == SHAPE then ClassFail("shape") else ClassFail("error", done) end
        return false
    end
    if not done then return true end
    klass.state, klass.ids = "ready", nil
    table.sort(klass.found, function(a, b)
        if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    ClassFire("ready")
    return false
end

local function ClassStart(lib, class, bitValue)
    klass = { state = "idle", lib = lib, class = class }
    local ok, err = pcall(function()
        local list, n = AllIds(lib, "quest")
        if n == 0 then error(SHAPE, 0) end
        klass = { state = "index", lib = lib, class = class, bit = bitValue, ids = list, len = n, pos = 1, done = 0,
            total = n, skipped = 0, failed = 0, found = {} }
    end)
    if not ok then
        if err == SHAPE then ClassFail("shape") else ClassFail("error", err) end
        return
    end
    Plan(0)
end

-- Darf das Volk des Spielers die Quest annehmen? Ohne Maske, ohne Volk oder ohne Auskunft des Enums: ja.
local function RaceMayTake(lib, races)
    if races == 0 then return true end
    local CD = Core.ClientData
    local race = CD and CD.PlayerRace and CD.PlayerRace() or nil
    local mask = race and Num(Field(Field(Field(lib, "Enum"), "raceMaskById"), race)) or nil
    if not (mask and PowerOfTwo(ID(mask))) then return true end
    return HasBit(races, mask)
end

-- Gehört wenigstens ein Geber zur Fraktion des Spielers? Geber ohne Angabe, Objekte und Gegenstände zählen als möglich.
local function StartFits(starts, other)
    if other or #starts == 0 then return true end
    local mine = Core.Plain(Core.Call(rawget(_G, "UnitFactionGroup"), "player"))
    if mine ~= "Alliance" and mine ~= "Horde" then return true end
    for _, npc in ipairs(starts) do
        local ok, friendly = pcall(Read, "Npc", "friendlyToFaction", npc)
        local faction = ok and friendly ~= nil and FACTION[friendly] or nil
        if faction == nil or faction == mine then return true end
    end
    return false
end

function Q.ClassQuestsReady()
    local okReady, ready, why = pcall(Q.Ready)
    if not okReady then return false, "error" end
    if ready ~= true then return false, why or "shape" end
    local lib = Lib()
    for _, field in ipairs(Q.CLASS_FIELDS) do
        if not Reader(lib, "Quest", field) then return false, "shape" end
    end
    if klass.lib == lib and (klass.state == "shape" or klass.state == "error") then return false, klass.state end
    return true
end

function Q.ClassQuests(class)
    if type(class) ~= "string" or class == "" then return nil, "args" end
    local ok, why = Q.ClassQuestsReady()
    if not ok then return nil, why end
    local lib = Lib()
    if klass.state == "idle" or klass.lib ~= lib or klass.class ~= class then
        local bitValue = ClassBit(lib, class)
        if not bitValue then return nil, "class" end
        ClassStart(lib, class, bitValue)
    end
    if klass.state == "index" then
        Plan(0)
        return nil, "building", klass.done, klass.total
    end
    if klass.state ~= "ready" then return nil, klass.state end
    local list = {}
    for _, e in ipairs(klass.found) do
        if RaceMayTake(lib, e.races) and StartFits(e.starts, e.other) then
            list[#list + 1] = { id = e.id, name = e.name, level = e.level, base = e.base }
        end
    end
    return { class = class, list = list, source = "Questie", sourceKey = "QuestieDB" }
end

function Q.QuestStart(questID, opts)
    questID = ID(questID)
    if not questID then return nil, "args" end
    local prefer = type(opts) == "table" and ID(Num(opts.map)) or nil
    return Targets(function()
        if not Reader(Lib(), "Quest", "startedBy") then return nil, "shape" end
        return EndPlaces(Read("Quest", "startedBy", questID), prefer)
    end)
end

function Q.Register()
    return Sources.Register("QuestieDB", {
        label = "Questie",
        ready = Q.Ready,
        whereFrom = WhereFrom,
        lootOf = Q.LOOT and LootOf or nil,
        contentsOf = ContentsOf,
    })
end
Q.Register()
