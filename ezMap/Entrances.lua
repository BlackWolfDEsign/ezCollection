local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Dungeon- und Raideingänge: Liste im Kartenmenü und Symbole auf Blizzards Weltkarte.

    Datenquellen in der Reihenfolge des Nutzers (Regel „Datenquellen“, 13.11.2026) – nichts stammt aus einem
    fremden Addon, auch keine Tabelle:
      1. der Client: ezCore.Dungeons.Entrances(uiMapID) liest C_EncounterJournal.GetDungeonEntrancesForMap
      2. selbst Gesammeltes: Betrittst du einen Dungeon oder Schlachtzug zu Fuß, gilt deine letzte Lage draußen vor
         dem Ladebildschirm als Eingang. Nicht nach einer Beschwörung oder einem Teleport der Gruppensuche – dann
         stand man nicht am Eingang –, nicht im Schlachtfeld.
    Jede Angabe nennt ihre Quelle (Tooltip des Symbols, Zusatz im Menü).

    Seit Welle 10 (MAP-17, DG-06) liegen die selbst betretenen Eingänge in ezCores Entdecker-Datenbank (Tabellen
    „entrance“ und „spot“, Art „entrance“) – eine Quelle für alle Module (ezQuest, ezSocial über
    Core.Dungeons.Entrances(karte, { own = true }) und Core.Entrances). ezCore merkt den Eingang beim Betreten selbst
    (Discovery.OnWorld, mit denselben Ausnahmen); ezMap merkt ihn nur noch, wenn ezCore gerade nicht sammelt (Schalter
    „Datenbank: Erlebtes sammeln“ aus), und schreibt ihn dann als eigene Funktion in die Datenbank. Entrances.For ist
    die Fassade für Kartenmenü und Symbole; „Eingänge vergessen“, die Liste und die Chatzeile „Eingang gemerkt“
    wirken auf ezCore. Der alte Speicher ezMapDB.entrances[Instanz-ID] = { name, map, x, y, raid, n, seen } wird
    einmal übergeben und bleibt liegen (Discovery.lua); ohne gespeicherte Ablage spiegelt ezMap die Eingänge weiter
    hinein, ohne nutzbare Datenbank arbeitet ezMap wie früher allein damit. Die Namen der Instanzen führt ezCores
    Datenbank seit Welle 23c selbst (Art „instance“, Core.Discovery.InstanceName); ezMap schreibt einen Namen, den
    es beim Betreten liest, dorthin und übergibt die alten ezMapDB.entranceNames einmal (Welle 23, A9). Die alte
    Ablage bleibt liegen und ist nur noch Rückfall, solange die Datenbank nicht gespeichert wird.
    Die Eingänge aus Core.Dungeons.Entrances nimmt ezMap nur mit der Quelle „client“: die selbst betretenen stehen
    über Entrances.All mit Zählung, Art und Name schon in der Liste (Quelle „von dir betreten“, Leitlinie 11).

    Symbole: seit Welle 15 (SAM-22) über ezCores Punkteschicht Core.MapPins (Anbieter „ezMap.entrances“, ein Rahmen
    für alle Fundorte; vorher eigene Knöpfe auf einem eigenen Rahmen). Kein AddDataProvider, kein AcquirePin –
    Blizzards eigener Code läuft diese Listen ab (Taint-Risiko); in Blizzards Tabellen wird nichts geschrieben.
    Zeichnet ein anderes Addon die Eingänge schon (Core.WhoHandles("dungeonEntrances")), zeichnet ezMap nicht; die
    Liste im Kartenmenü bleibt als Ziel.
]]
local Entrances = {}
ns.Entrances = Entrances

Entrances.MAX_AGE = 180         -- Sekunden: so alt darf die letzte Lage draußen beim Betreten höchstens sein
Entrances.SKIP_AFTER_PORT = 180 -- Sekunden nach Beschwörung/Teleport, in denen nichts gelernt wird
Entrances.PIN_SIZE = 22

local outside                   -- { map, x, y, t } letzte Lage außerhalb einer Instanz
local skipUntil = 0
local names = {}                -- [Instanz-Schlüssel] = Name aus GetInstanceInfo (diese Sitzung)
local known                     -- [Instanz-Schlüssel] = true: schon gemeldet (Chatzeile nur beim ersten Mal)

-- Alter Speicher (ezMapDB.entrances): Quelle ohne nutzbare Datenbank, sonst Übergabe und Rückfall beim Ausloggen.
local function Store()
    local db = ns.db
    if type(db) ~= "table" then return nil end
    if type(db.entrances) ~= "table" then db.entrances = {} end
    return db.entrances
end

-- Alte Namen der Eingänge (ezMapDB.entranceNames[Instanz-Schlüssel]): vor Welle 23c führte ezCores Datenbank keine
-- Namen von Instanzen. Seitdem nur noch Rückfall (Ablage nicht gespeichert) und Quelle der einmaligen Übergabe.
local function SavedNames()
    local db = ns.db
    if type(db) ~= "table" then return nil end
    if type(db.entranceNames) ~= "table" then db.entranceNames = {} end
    return db.entranceNames
end

-- Name der Instanz aus ezCores Datenbank (Core.Discovery.InstanceName, Welle 23c) oder nil
local function CoreName(inst)
    local D = Core.Discovery
    if inst == nil or not (D and type(D.InstanceName) == "function") then return nil end
    local name = D.InstanceName(inst)
    if type(name) == "string" and name ~= "" then return name end
    return nil
end

-- Namen in ezCores Datenbank schreiben (als eigene Funktion von ezMap, auch bei ausgeschaltetem Sammeln) → true/false
local function StoreCoreName(inst, name)
    local DB = ns.Discovery.DB()
    if not (DB and type(DB.SetText) == "function") then return false end
    return ns.Discovery.Own(DB.SetText, "instance", inst, name) == true
end

-- Den Namen beim Betreten merken: in ezCores Datenbank; ezMapDB.entranceNames nur, wenn die Ablage nicht gespeichert
-- wird (sonst stünde nach dem Ausloggen bei Instanzen außerhalb der Dungeon-Tabelle nur „#Instanz-ID“).
local function RememberName(inst, name)
    if inst == nil or type(name) ~= "string" or name == "" then return end
    names[inst] = name
    local DB = ns.Discovery.DB()
    if StoreCoreName(inst, name) and DB and DB.Persistent and DB.Persistent() then return end
    local saved = SavedNames()
    if saved then saved[inst] = name end
end

-- Übergabe der alten Namen an ezCore (einmal je Ablage, Discovery.lua); was ezCore schon kennt, gewinnt. → Anzahl
function Entrances.ImportNames()
    local n = 0
    for inst, name in pairs(SavedNames() or {}) do
        if type(name) == "string" and name ~= "" and not CoreName(inst) and StoreCoreName(inst, name) then n = n + 1 end
    end
    return n
end
ns.Discovery.AddImport("entranceNames", Entrances.ImportNames)

-- Wie ein neues Anmelden: die Namen dieser Sitzung vergessen (für die Prüfungen, Discovery.NewSession).
function Entrances.NewSession() wipe(names) end

-- Arbeitet ezMap mit ezCores Datenbank? (sonst allein mit dem alten Speicher, wie vor Welle 10)
function Entrances.Service() return ns.Discovery.Usable() end

-- In einer Instanz? → true/false, Art ("party", "raid", "pvp" …) oder nil. Gesperrte Werte gelten als unbekannt.
function Entrances.Instance()
    local inside, kind = Core.InInstance()
    return inside == true, kind
end

---------------------------------------------------------------------------
-- Datenbank: Schlüssel, Namen, Lesen und Schreiben über ezCores Dienst
---------------------------------------------------------------------------

-- Speicherkarte der Datenbank (Zone bzw. Dungeon-Ebene) und Lage darauf; kann der Client nicht umrechnen, bleibt
-- die Karte, auf der die Lage gemessen wurde. → karte, x, y oder nil
local function StoreSpot(mapID, x, y)
    local DB = ns.Discovery.DB()
    mapID, x, y = ns.Num(mapID), ns.Num(x), ns.Num(y)
    if not (DB and mapID and x and y) then return nil end
    local store = DB.Keys.MapOf(mapID) or mapID
    if store ~= mapID then
        local sx, sy = Core.Map.PosOn(store, mapID, x, y)
        if sx and sy then return store, sx, sy end
        return mapID, x, y
    end
    return store, x, y
end
Entrances.StoreSpot = StoreSpot

-- Name eines Eingangs: wie ihn der Client beim Betreten nannte (diese Sitzung, sonst der alte Speicher, sonst ezCores
-- Datenbank, sonst ezMapDB.entranceNames), sonst aus ezCores Dungeon-Tabelle (Blizzards Gruppensuche), sonst aus dem
-- Notschlüssel; zuletzt „#Instanz-ID“.
function Entrances.NameOf(inst)
    if names[inst] then return names[inst] end
    local old = (Store() or {})[inst]
    if type(old) == "table" and type(old.name) == "string" and old.name ~= "" then return old.name end
    local fromCore = CoreName(inst)
    if fromCore then return fromCore end
    local saved = (SavedNames() or {})[inst]
    if type(saved) == "string" and saved ~= "" then return saved end
    local D = Core.Dungeons
    local entry = D and D.Get and type(inst) == "number" and D.Get(inst) or nil
    if type(entry) == "table" and type(entry.name) == "string" and entry.name ~= "" then return entry.name end
    local DB = ns.Discovery.DB()
    local parts
    if DB and DB.Keys.ParseFallback then parts = select(3, DB.Keys.ParseFallback(inst)) end
    if type(parts) == "table" and type(parts[#parts]) == "string" then return parts[#parts] end
    return "#" .. tostring(inst)
end

-- Eintrag aus ezCores Dungeon-Tabelle (Stufen für Farbe und Tooltip) oder nil.
local function EntryOf(inst, name)
    local D = Core.Dungeons
    if not (D and D.Get) then return nil end
    return (type(inst) == "number" and D.Get(inst)) or D.Get(name)
end

-- Alle selbst betretenen Eingänge mit Lage, nach Name sortiert:
-- { inst, name, map, x, y, raid, n, seen, entry } – aus der Datenbank, ohne sie aus dem alten Speicher.
-- Je Instanz zählt der Ort, an dem du am häufigsten hineingegangen bist (bei Gleichstand der jüngste).
function Entrances.All()
    local list = {}
    local DB = ns.Discovery.DB()
    if DB then
        local best = {}
        for _, map in ipairs(DB.KeysOf("spot")) do
            for _, inst in ipairs(DB.KeysOf("spot", map, "entrance")) do
                for _, p in ipairs(DB.Get("spot", map, "entrance", inst) or {}) do
                    local x, y = DB.Keys.Unpack(p.xy)
                    local b = best[inst]
                    local cnt, t = ns.Num(p.cnt) or 0, ns.Num(p.t) or 0
                    if x and y and (not b or cnt > b.cnt or (cnt == b.cnt and t > b.t)) then
                        best[inst] = { map = map, x = x, y = y, cnt = cnt, t = t }
                    end
                end
            end
        end
        for inst, p in pairs(best) do
            local row = DB.Get("entrance", inst)
            if row then
                local name = Entrances.NameOf(inst)
                list[#list + 1] = { inst = inst, name = name, map = p.map, x = p.x, y = p.y, raid = row.raid == true,
                    n = ns.Num(row.cnt) or 1, seen = ns.Num(row.t), entry = EntryOf(inst, name) }
            end
        end
    else
        for key, e in pairs(Store() or {}) do
            if type(e) == "table" and type(e.name) == "string" and ns.Num(e.map) and ns.Num(e.x) and ns.Num(e.y) then
                list[#list + 1] = { inst = key, name = e.name, map = e.map, x = e.x, y = e.y, raid = e.raid == true,
                    n = ns.Num(e.n) or 1, seen = ns.Num(e.seen), entry = EntryOf(key, e.name) }
            end
        end
    end
    table.sort(list, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return tostring(a.inst) < tostring(b.inst)
    end)
    return list
end

-- Einen Eingang als eigene Funktion in die Datenbank schreiben (wenn ezCore gerade nicht selbst sammelt).
-- → Instanz-Schlüssel oder nil
function Entrances.Note(instanceID, name, mapID, x, y, raid)
    local DB = ns.Discovery.DB()
    if not DB then return nil end
    local inst = DB.Keys.Instance(instanceID, name)
    local store, sx, sy = StoreSpot(mapID, x, y)
    local xy = store and DB.Keys.Pack(sx, sy)
    if not (inst and xy) then return nil end
    ns.Discovery.Own(DB.Observe, "entrance", inst, { cnt = 1, raid = raid == true })
    ns.Discovery.Own(DB.Observe, "spot", { store, "entrance", inst }, { xy = xy, cnt = 1, via = 1 })
    return inst
end

-- Übergabe des alten Speichers (einmal je Ablage, Discovery.lua). Was ezCore schon selbst kennt, gewinnt.
local function ImportOld()
    local DB = ns.Discovery.DB()
    if not DB then return 0 end
    local n = 0
    for key, e in pairs(Store() or {}) do
        if type(e) == "table" then
            local id = ns.Num(key)
            local name = type(e.name) == "string" and e.name ~= "" and e.name or (type(key) == "string" and key or nil)
            local inst = DB.Keys.Instance(id, name)
            local store, sx, sy = StoreSpot(e.map, e.x, e.y)
            local xy = store and DB.Keys.Pack(sx, sy)
            if inst and xy and not DB.Get("entrance", inst) then
                local ctx = ns.Discovery.OldContext(e.seen)
                local count = math.max(1, ns.Num(e.n) or 1)
                ns.Discovery.Own(DB.Adopt, "entrance", inst, { cnt = count, raid = e.raid == true }, ctx)
                ns.Discovery.Own(DB.Adopt, "spot", { store, "entrance", inst }, { xy = xy, cnt = count, via = 1 }, ctx)
                if name and not names[inst] then RememberName(inst, name) end
                n = n + 1
            end
        end
    end
    return n
end
Entrances.ImportOld = ImportOld
ns.Discovery.AddImport("entrances", ImportOld)

-- Ohne gespeicherte Ablage: die Eingänge der Datenbank in den alten Speicher spiegeln, damit beim Ausloggen nichts
-- verloren geht (beim nächsten Anmelden übergibt ezMap sie wieder). → Anzahl
function Entrances.SyncOld()
    if not Entrances.Service() or ns.Discovery.Moved("entrances") then return 0 end
    local store = Store()
    if not store then return 0 end
    local n = 0
    for _, e in ipairs(Entrances.All()) do
        store[ns.Num(e.inst) or e.name] = { name = e.name, map = e.map, x = e.x, y = e.y, raid = e.raid or nil,
            n = e.n, seen = e.seen }
        n = n + 1
    end
    if n > 0 then ns.Discovery.Dirty("entrances") end   -- die nächste gespeicherte Ablage übernimmt es
    return n
end

-- Chatzeile „Eingang gemerkt“ beim ersten Mal – gleich, ob ezCore oder ezMap ihn gemerkt hat. Der erste Aufruf (nach
-- der Übergabe bzw. einer neuen Ablage) merkt sich nur, was schon da ist. → Anzahl der Meldungen
function Entrances.Announce()
    if not Entrances.Service() then return 0 end
    local first = known == nil
    known = known or {}
    local n = 0
    for _, e in ipairs(Entrances.All()) do
        if not known[e.inst] then
            known[e.inst] = true
            if not first then
                ns.Print(L.ENTRANCE_LEARNED:format(e.name, ns.MapName(e.map), ns.CoordText(e.x, e.y)))
                n = n + 1
            end
        end
    end
    return n
end

-- reset = true: neue Ablage oder nach der Übergabe – still neu aufnehmen, was schon da ist.
function Entrances.Known(reset)
    if reset then known = nil end
    return Entrances.Announce()
end

-- ezCore meldet eine geänderte Tabelle „entrance“ (DB_CHANGED): melden, spiegeln, Symbole neu setzen.
function Entrances.OnChanged()
    Entrances.Announce()
    Entrances.SyncOld()
    Entrances.Refresh()
end

---------------------------------------------------------------------------
-- Lernen: letzte Lage draußen, dann Betreten
---------------------------------------------------------------------------

function Entrances.NoteOutside()
    if Entrances.Instance() then return false end
    local mapID, x, y = ns.PlayerPosition()
    if not mapID then return false end
    outside = { map = mapID, x = x, y = y, t = Core.Uptime() }
    return true
end

-- Nach einer Beschwörung oder einem Teleport stand man nicht am Eingang.
function Entrances.NotePort()
    skipUntil = Core.Uptime() + Entrances.SKIP_AFTER_PORT
    outside = nil
end

-- Beim Betreten der Welt: in einem Dungeon oder Schlachtzug und kurz vorher draußen gewesen → Eingang merken.
-- Sammelt ezCore selbst (Schalter „Datenbank: Erlebtes sammeln“ an), merkt ezCore ihn (die Chatzeile kommt dann über
-- DB_CHANGED); ezMap merkt sich nur den Namen. Rückgabe: Schlüssel des gemerkten Eingangs oder nil.
function Entrances.OnEnter()
    local inside, kind = Entrances.Instance()
    if not inside then
        Entrances.NoteOutside()
        return nil
    end
    local last = outside
    outside = nil
    if kind ~= "party" and kind ~= "raid" then return nil end
    if type(GetInstanceInfo) ~= "function" then return nil end
    local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
    name, instanceID = Core.Plain(name), ns.Num(instanceID)
    if type(name) ~= "string" or name == "" then return nil end
    local DB = ns.Discovery.DB()
    local inst = DB and DB.Keys.Instance(instanceID, name)
    if inst then RememberName(inst, name) end
    if DB and DB.Collecting() then
        Entrances.Announce()        -- hat ezCore schon gemerkt, kommt die Zeile jetzt, sonst mit DB_CHANGED
        return nil
    end
    local now = Core.Uptime()
    if not last or now - last.t > Entrances.MAX_AGE or now < skipUntil then return nil end
    if DB then
        local key = Entrances.Note(instanceID, name, last.map, last.x, last.y, kind == "raid")
        Entrances.OnChanged()
        return key
    end
    -- ohne nutzbare Datenbank: wie vor Welle 10 allein im alten Speicher
    local store = Store()
    if not store then return nil end
    local key = instanceID or name
    local old = type(store[key]) == "table" and store[key] or nil
    store[key] = { name = name, map = last.map, x = last.x, y = last.y, raid = kind == "raid" or nil,
        n = (old and ns.Num(old.n) or 0) + 1, seen = time() }
    ns.Discovery.Dirty("entrances")
    if not old then ns.Print(L.ENTRANCE_LEARNED:format(name, ns.MapName(last.map), ns.CoordText(last.x, last.y))) end
    Entrances.Refresh()
    return key
end

function Entrances.Count()
    return #Entrances.All()
end

-- Alle selbst betretenen Eingänge vergessen: in ezCores Datenbank (Satz und Orte) und im alten Speicher, damit sie
-- beim nächsten Anmelden nicht wiederkommen. Eingänge, die das Spiel selbst kennt, bleiben.
function Entrances.Forget()
    local DB = ns.Discovery.DB()
    if DB then
        for _, map in ipairs(DB.KeysOf("spot")) do
            for _, inst in ipairs(DB.KeysOf("spot", map, "entrance")) do DB.Forget("spot", map, "entrance", inst) end
        end
        for _, inst in ipairs(DB.KeysOf("entrance")) do DB.Forget("entrance", inst) end
        known = {}
    end
    local store = Store()
    if store then wipe(store) end
    wipe(names)
    local saved = SavedNames()
    if saved then wipe(saved) end
    ns.Print(L.ENTRANCE_FORGET_DONE)
    Entrances.Refresh()
end

function Entrances.PrintList()
    local rows = Entrances.All()
    if #rows == 0 then return ns.Print(L.ENTRANCE_LIST_EMPTY) end
    ns.Print(L.ENTRANCE_LIST:format(#rows))
    for _, e in ipairs(rows) do
        ns.Print(("  %s – %s %s"):format(e.name, ns.MapName(e.map), ns.CoordText(e.x, e.y)))
    end
end

---------------------------------------------------------------------------
-- Lesen: Client zuerst, dann selbst Gemerktes
---------------------------------------------------------------------------

-- Lage eines Kartenpunkts auf einer anderen Karte (x, y von 0 bis 1) oder nil, wenn er dort nicht liegt bzw. der
-- Client nicht umrechnen kann. Weiterleitung auf ezCore (Core.Map.PosOn, W-14).
function Entrances.PosOn(target, mapID, x, y) return Core.Map.PosOn(target, mapID, x, y) end

-- Eingänge für eine gezeigte Karte (auf einer Kontinentkarte auch die ihrer Zonen), nach Name sortiert:
-- { name, map, x, y (Lage auf der eigenen Karte, für die Markierung), sx, sy (Lage auf der gezeigten Karte oder nil),
--   entry (ezCore.Dungeons-Eintrag oder nil), source = "client" | "self", raid, n, inst }
-- Fassade (MAP-17): zuerst der Client über ezCore.Dungeons.Entrances, dann die selbst betretenen aus ezCores
-- Datenbank (Entrances.All) – kennt der Client einen Eingang, gilt seiner.
function Entrances.For(mapID)
    local list, client = {}, {}
    mapID = ns.Num(mapID)
    if not mapID then return list end
    local D = Core.Dungeons
    if D and D.Entrances then
        local maps = { mapID }
        local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
        local continent = Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2
        if info and info.mapType == continent and C_Map.GetMapChildrenInfo then
            for _, child in ipairs(C_Map.GetMapChildrenInfo(mapID) or {}) do maps[#maps + 1] = child.mapID end
        end
        for _, id in ipairs(maps) do
            for _, e in ipairs(D.Entrances(id)) do
                -- nur, was der Client liefert: die selbst betretenen Eingänge (Quelle „own“, sobald ezCore sie ab Werk
                -- mitliefert, ezCore A40) kommen unten aus Entrances.All mit Zählung und „von dir betreten“
                if e.source == nil or e.source == "client" then
                    local sx, sy = Entrances.PosOn(mapID, id, e.x, e.y)
                    list[#list + 1] = { name = e.name, map = id, x = e.x, y = e.y, sx = sx, sy = sy, entry = e.entry,
                        source = "client" }
                    client[e.name] = true
                end
            end
        end
    end
    for _, e in ipairs(Entrances.All()) do
        if not client[e.name] then
            local sx, sy = Entrances.PosOn(mapID, e.map, e.x, e.y)
            if sx then
                list[#list + 1] = { name = e.name, map = e.map, x = e.x, y = e.y, sx = sx, sy = sy, entry = e.entry,
                    source = "self", raid = e.raid, n = e.n, inst = e.inst }
            end
        end
    end
    table.sort(list, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.map < b.map
    end)
    return list
end

-- Quelle eines Eingangs. Selbst betreten: aus der Datenbank gilt der Ort, an dem du am häufigsten hineingegangen bist
-- (Entrances.All); der alte Speicher allein kennt nur die letzte Lage.
function Entrances.SourceText(e)
    if e.source == "self" then
        local text = Entrances.Service() and L.ENTRANCE_SOURCE_SELF or L.ENTRANCE_SOURCE_SELF_LAST
        return text:format(ns.Num(e.n) or 1)
    end
    return L.ENTRANCE_SOURCE_CLIENT
end

function Entrances.Go(e)
    return ns.Way.Set(e.map, e.x, e.y, e.name, true)
end

---------------------------------------------------------------------------
-- Symbole auf der Weltkarte: seit Welle 15 über ezCores Punkteschicht (SAM-22)
---------------------------------------------------------------------------
--[[
    Bis Welle 14 setzte ezMap eigene Knöpfe auf einem eigenen Rahmen über der Kartenfläche und hängte sich selbst an
    OnMapChanged und OnCanvasScaleChanged. Seit Welle 15 zeichnet Core.MapPins alle Fundorte auf EINEM Rahmen (Anbieter
    „ezMap.entrances“, wie die Sammel-Fundorte, seltenen Gegner und Bücher): Kartenwechsel baut neu, Zoomen passt nur die
    Größe an, ohne die Eingänge neu abzufragen (Fund 9 „Ruckeln beim Zoomen“). Verhalten und Schalter bleiben:
    entrancePins (Gruppe „Dungeon-Eingänge“ im Baum), Rücksicht über Core.WhoHandles("dungeonEntrances"), Tooltip mit
    Stufe, Art, Quelle und Klick-Hinweis, Linksklick setzt Blizzards Markierung. Die alten Funktionen leiten weiter
    und geben dieselbe Form zurück: Refresh() und Rescale() die Zahl der Symbole, Pins() die gesetzten Punkte (je mit
    .entrance – vorher Knöpfe mit .entrance), Overlay() den Rahmen der Punkteschicht.
]]
Entrances.PROVIDER = "ezMap.entrances"
Entrances.ICON = "Interface\\Icons\\INV_Misc_Key_03"    -- Rückfall, wenn der Client Blizzards Atlas nicht kennt

local laid, laidMap = {}, nil       -- Punkte der zuletzt gebauten Karte (Pins(), Rescale())

function Entrances.PinsWanted()
    return ns.Enabled("entrancePins") and not ns.EntrancesElsewhere()
end

local function Pins()
    local P = Core.MapPins
    if type(P) == "table" and type(P.AddProvider) == "function" then return P end
    return nil
end

local function ShownMap()
    local map = rawget(_G, "WorldMapFrame")
    if not (type(map) == "table" and map.IsShown and map:IsShown() and map.GetMapID) then return nil end
    return ns.Num(map:GetMapID())
end

-- Punkte der Karte mapID für Core.MapPins: Lage auf der gezeigten Karte, Symbol Blizzards Atlas „Dungeon“ bzw. „Raid“
function Entrances.Points(mapID)
    local out = {}
    for _, e in ipairs(Entrances.For(mapID)) do
        if e.sx and e.sy then
            local point = { x = e.sx, y = e.sy, size = Entrances.PIN_SIZE, entrance = e }
            local atlas = e.raid and "Raid" or "Dungeon"
            if Core.AtlasExists(atlas) then point.atlas = atlas else point.texture = Entrances.ICON end
            out[#out + 1] = point
        end
    end
    laid, laidMap = out, ns.Num(mapID)
    return out
end

-- Tooltip am Symbol (wie bisher): Name, Stufen in Blizzards Farbe, Art, Quelle, Klick-Hinweis
function Entrances.Tooltip(tip, point)
    local e = type(point) == "table" and point.entrance
    if not e then return end
    Core.TipTitle(tip, e.name)
    local entry = e.entry
    if entry and entry.minLevel and entry.maxLevel then
        local r, g, b = Core.Dungeons.Color(Core.Dungeons.DifficultyOf(entry))
        tip:AddLine(L.ENTRANCE_LEVELS:format(entry.minLevel, entry.maxLevel), r, g, b)
    end
    Core.TipLine(tip, e.raid and L.ENTRANCE_KIND_RAID or L.ENTRANCE_KIND_DUNGEON, "hint")
    Core.TipLine(tip, Entrances.SourceText(e), "hint", true)
    Core.TipClick(tip, L.ENTRANCE_PIN_HINT)
end

function Entrances.Click(point, button)
    local e = type(point) == "table" and point.entrance
    if not e or button == "RightButton" then return false end
    return Entrances.Go(e)
end

-- Symbole für die gezeigte Karte neu setzen (fragt die Eingänge neu ab). Rückgabe: Anzahl sichtbarer Symbole.
function Entrances.Refresh()
    laid, laidMap = {}, nil
    local P = Pins()
    if not P then return 0 end
    P.Refresh()
    if not (ShownMap() and Entrances.PinsWanted()) then return 0 end
    return #laid
end

-- Beim Zoomen: nur Größe (die Punkteschicht fragt die Eingänge nicht neu ab). Ist inzwischen eine andere Karte zu
-- sehen, neu setzen. Rückgabe: Anzahl.
function Entrances.Rescale()
    local P = Pins()
    local shown = ShownMap()
    if not (P and shown and Entrances.PinsWanted()) or laidMap ~= shown then return Entrances.Refresh() end
    P.Rescale()
    return #laid
end

function Entrances.Pins() return laid end
function Entrances.Overlay()
    local P = Pins()
    return P and P.Overlay() or nil
end

-- Kartenmenü: Schalter für die Symbole (zeichnet ein anderes Addon, steht dessen Name schon unter „Dungeoneingänge“).
function Entrances.AddMenuToggle(root)
    if ns.EntrancesElsewhere() then return false end
    ns.MapButton.Toggle(root, L.MENU_ENTRANCE_PINS, "entrancePins")    -- Erklärzeile wie auf der Einstellungsseite
    return true
end

function Entrances.Init()
    local P = Pins()
    if not P then return false end
    P.AddProvider(Entrances.PROVIDER, {
        owner = "ezMap",
        order = 40,         -- vor den Sammel-Fundorten (50) aufgebaut
        punkte = Entrances.Points,
        sichtbar = function() return Entrances.PinsWanted() end,
        tooltip = Entrances.Tooltip,
        klick = Entrances.Click,
    })
    return true
end

ns.OnReady(function()
    ns.Try("EntrancePins", Entrances.Init)
    Entrances.NoteOutside()
end)

ns.On("PLAYER_LEAVING_WORLD", function() ns.Try("Entrances", Entrances.NoteOutside) end)
for _, event in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }) do
    ns.On(event, function() ns.Try("Entrances", Entrances.NoteOutside) end)
end
ns.On("PLAYER_ENTERING_WORLD", function() ns.Try("Entrances", Entrances.OnEnter) end)

-- Beschwörung und Teleport der Gruppensuche: danach stand man nicht am Eingang.
if C_SummonInfo and type(C_SummonInfo.ConfirmSummon) == "function" then
    hooksecurefunc(C_SummonInfo, "ConfirmSummon", function() Entrances.NotePort() end)
end
if type(rawget(_G, "LFGTeleport")) == "function" then
    hooksecurefunc("LFGTeleport", function() Entrances.NotePort() end)
end

ns.OnSettingChanged(function(key)
    if key == "entrancePins" then Entrances.Refresh() end
end)

ns.AddStatusLine(function()
    local other = ns.EntrancesElsewhere()
    if other then return L.STATUS_ENTRANCES_OTHER:format(Entrances.Count(), other) end
    if ns.Enabled("entrancePins") then return L.STATUS_ENTRANCES_ON:format(Entrances.Count()) end
    return L.STATUS_ENTRANCES_OFF:format(Entrances.Count())
end)
