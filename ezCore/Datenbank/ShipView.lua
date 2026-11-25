local Core = ezCore
local L = Core.L

--[[
    Anzeige der Beiträge anderer Spieler (Paket „Anzeige der Beiträge“, 25.11.2026; Empfehlung umgesetzt nach dem Auftrag
    des Nutzers vom 25.11.2026 „bei Fragen folgen der Empfehlung“, ROADMAP-Index, Eintrag „Mithelfen: anonymer Export“).
    Die Fach-Fassaden der Auslieferung (DB.Shipped, DBShip.lua) neben denen der eigenen Lage (DiscoveryView.lua).

    Regeln: Der Client und installierte Addons gehen vor (Leitlinie 11), „bei dir“ ebenso; aus Beiträgen kommt, was dort
    fehlt. Nie gemischt: jede Antwort trägt ihre Herkunft („aus Beiträgen (n Spieler), Stand Build x“). Fremde Zahlen
    gehen in keine Rechnung ein (Core.Drops.Worth, Core.Flights.Speed). Ausgeliefert sind nur Nummern: Ein Gegner,
    Händler oder Objekt ohne bekannten Namen (selbst gesehen oder laut Questie) wird nicht genannt, nur mitgezählt.

      Core.Ship.Name(art, id)        → Name ("npc" | "object") aus eigener Lage, Core.Npcs oder QuestieDB, sonst nil
      Core.Ship.Place(art, id)       → { map, zone, x, y } der häufigste ausgelieferte Ort ("npc" | "object") oder nil
      Core.Ship.Fits(npcID)          → false, wenn der NPC laut Beiträgen zur anderen Fraktion gehört
      Core.Ship.LootOf(npcID)        → { npc, items = { { id, chance | nil } … }, n, listed, label } oder nil – chance
                                       erst ab Drops.WORTH_MIN Vorgängen
      Core.Ship.ContentsOf(art, id)  → { kind, id, items = { { id, listed } … }, n, listed, label } ("item" | "object")
      Core.Ship.WhereFrom(itemID, opts) → wie Core.Sources.WhereFrom (drops, objects, containers, vendors), ohne das,
                                       was die eigene Datenbank schon nennt; dazu label
      Core.Ship.Offers(schlüssel, will) → { { npc, art, price, skill } … }, label, art – Lehrer deiner Fraktion, die
                                       Zauber bzw. Rezept (Schlüssel in offer.svc) laut Beiträgen anbieten;
                                       will(art, wer) wählt die Lehrer-Arten (Keys.OfferKind); label nil: nirgends
      Core.Flights.Shipped(von, nach, hops) → Weg, info wie Core.Flights.Time, aus der Auslieferung; info gehört zu diesem
                                       Weg; ohne hops der kürzeste (wer zuletzt flog, sagt nichts über andere)
      Core.Zones.Shipped(karte)      → lo, hi, info wie Core.Zones.Levels
      Core.Drops.SalvageShipped(itemID, spellID) → Zählblock, info wie Core.Drops.Salvage, ohne verschleierte Materialien
    Quelle „ship“ von Core.Sources (hinter QuestieDB): whereFrom, lootOf, contentsOf.
]]

local DB = Core.DB
local Keys = DB.Keys
local Num = Core.Num
local Sources = Core.Sources
local Drops = Core.Drops

local Ship = {}
Core.Ship = Ship

-- Aus einer langen Liste werden höchstens so viele Einträge nach einem Namen gefragt (die häufigsten zuerst)
Ship.TRY_MAX = 40

local mem = {}
local function Mem()
    local ver = DB.ShipVersion()
    if mem.ver ~= ver then mem = { ver = ver, places = {} } end
    return mem
end

local function ID(value)
    if Core.IsSecret(value) then return nil end
    if type(value) ~= "number" or value <= 0 or value ~= math.floor(value) then return nil end
    return value
end

-- Verschleierte Gegenstände sind Entdecker-Wissen (DG-18, dieselbe Regel wie bei QuestieDB)
local function Shows(itemID, opts)
    return Sources.ClientKnowsItem(itemID) or DB.Explorer() or (type(opts) == "table" and opts.explorer == true)
end

-- „aus Beiträgen (n Spieler), Stand Build x“ über mehrere Sätze: die meisten Spieler, der neueste Build
local function LabelOf(infos)
    local n, b = 0, nil
    for _, info in ipairs(infos) do
        n = math.max(n, Num(info.contributors) or 0)
        if Num(info.b) then b = math.max(b or 0, info.b) end
    end
    return L.DB_SHIP:format(n, tostring(b or "?"))
end

---------------------------------------------------------------------------
-- Namen und Orte
---------------------------------------------------------------------------

local QUESTIE_KIND = { npc = "Npc", object = "Object" }
local TEXT_KIND = { npc = "npc", object = "obj" }

function Ship.Name(kind, id)
    id = ID(id)
    if not (id and TEXT_KIND[kind]) then return nil end
    local name = DB.Text(TEXT_KIND[kind], id)
    if not name and kind == "npc" then
        local N = Core.Npcs
        local e = N and N.Get and N.Get(id)
        name = type(e) == "table" and e.name or nil
    end
    if not name then
        local Q = Sources.Questie
        name = Q and Q.Name and Q.Name(QUESTIE_KIND[kind], id) or nil
    end
    return type(name) == "string" and name ~= "" and name or nil
end

-- id » { map, xy, cnt } – der Ort mit den meisten Sichtungen; Instanzen ohne Karte (-instanceID) zählen nicht
local function BuildPlaces(kind, tick)
    local idx = {}
    DB.ShipEach(function(map, byKind)
        if type(map) ~= "number" or map <= 0 or type(byKind) ~= "table" then return end
        for id, list in pairs(type(byKind[kind]) == "table" and byKind[kind] or {}) do
            if tick then tick() end
            for _, el in ipairs(type(list) == "table" and list or {}) do
                local cnt = type(el) == "table" and Num(el.xy) and (Num(el.cnt) or 0)
                local best = idx[id]
                if cnt and (not best or cnt > best.cnt or (cnt == best.cnt and map < best.map)) then
                    idx[id] = { map = map, xy = el.xy, cnt = cnt }
                end
            end
        end
    end, "spot")
    return idx
end

local function PlaceIndex(kind)
    local m = Mem()
    m.places[kind] = m.places[kind] or BuildPlaces(kind)
    return m.places[kind]
end

function Ship.Place(kind, id)
    id = ID(id)
    if not (id and TEXT_KIND[kind]) then return nil end
    -- seltene Gegner sind Entdecker-Wissen (die Auslieferung führt ihre Orte nicht; was du als selten kennst, auch nicht)
    if kind == "npc" and not DB.Explorer() and DB.Get("rare", id) ~= nil then return nil end
    local p = PlaceIndex(kind)[id]
    if not p then return nil end
    local x, y = Keys.Unpack(p.xy)
    if not (Num(x) and Num(y) and x >= 0 and x <= 1 and y >= 0 and y <= 1) then x, y = nil, nil end
    return { map = p.map, zone = Sources.ZoneName(p.map), x = x, y = y }
end

local SIDE = { Alliance = "A", Horde = "H" }
function Ship.Fits(npcID)
    local row = DB.Shipped("npc", npcID)
    local side = type(row) == "table" and row.side or nil
    if side ~= "A" and side ~= "H" then return true end
    local mine = SIDE[Core.Plain((Core.Call(rawget(_G, "UnitFactionGroup"), "player"))) or ""]
    return mine == nil or mine == side
end

---------------------------------------------------------------------------
-- „Woher?“
---------------------------------------------------------------------------

-- item » liste » id » { id, f, pr, name (Tabelle), row } – einmal je Stand der Auslieferung, nur gelesen
local function BuildItems(tick)
    local idx = {}
    local function Add(item, list, id, f, name, row, pr)
        item, id = ID(item), ID(id)
        if not (item and id) then return end
        local byList = idx[item] or {}
        idx[item] = byList
        byList[list] = byList[list] or {}
        local e = byList[list][id]
        if not e then
            e = { id = id, f = 0, name = name, row = row, pr = pr }
            byList[list][id] = e
        end
        e.f = e.f + f
    end
    for kind, list in pairs(Sources.LOOT_LISTS) do
        DB.ShipEach(function(id, row)
            if tick then tick() end
            if type(row) ~= "table" then return end
            local function Block(b)
                for item, it in pairs(type(b) == "table" and type(b.items) == "table" and b.items or {}) do
                    if type(it) == "table" then Add(item, list, id, Num(it.f) or 0, "drops", row) end
                end
            end
            for _, b in pairs(type(row.diff) == "table" and row.diff or {}) do Block(b) end
            Block(row.old)
        end, "drops", kind)
    end
    DB.ShipEach(function(npc, row)
        if tick then tick() end
        for item, w in pairs(type(row) == "table" and type(row.w) == "table" and row.w or {}) do
            if type(w) == "table" then Add(item, "vendors", npc, 1, "vendor", row, Num(w.pr)) end
        end
    end, "vendor")
    return idx
end

local function ItemIndex()
    local m = Mem()
    m.items = m.items or BuildItems()
    return m.items
end

-- was die eigene Datenbank („bei dir“) schon nennt: liste » id » true
local function OwnIds(itemID)
    local out = {}
    local function Mark(list, id)
        out[list] = out[list] or {}
        out[list][id] = true
    end
    for _, src in ipairs(Drops.SourcesOf(itemID)) do
        local list = Sources.LOOT_LISTS[src.kind]
        if list and src.id ~= nil then Mark(list, src.id) end
    end
    for _, v in ipairs(Core.Vendors.Selling(itemID)) do
        if v.npc ~= nil then Mark("vendors", v.npc) end
    end
    return out
end

local function Entry(list, hit)
    local e
    if list == "containers" then
        -- auch der Behälter kann verschleiert sein (wie in SourcesQuestie.lua)
        if not Shows(hit.id) then return nil end
        e = { kind = "item", id = hit.id, name = Sources.ItemName(hit.id) }
    else
        local kind = list == "objects" and "object" or "npc"
        -- ein Händler der anderen Fraktion hilft nicht weiter (an ihm hängt auch die Kartenmarkierung)
        if list == "vendors" and not Ship.Fits(hit.id) then return nil end
        local name = Ship.Name(kind, hit.id)
        if not name then return nil end
        e = { kind = kind, id = hit.id, name = name }
        local p = Ship.Place(kind, hit.id)
        if p then e.map, e.zone, e.x, e.y = p.map, p.zone, p.x, p.y end
        if kind == "npc" then
            local row = DB.Shipped("npc", hit.id)
            local lv = type(row) == "table" and row.lvls or nil
            if type(lv) == "table" then e.lo, e.hi = Num(lv.lo), Num(lv.hi) end
        end
    end
    if list == "vendors" then e.price = hit.pr else e.cnt = hit.f end
    return e
end

function Ship.WhereFrom(itemID, opts)
    itemID = ID(itemID)
    if not itemID or not Shows(itemID, opts) then return nil end
    local byList = ItemIndex()[itemID]
    if not byList then return nil end
    local own = OwnIds(itemID)
    local out, infos, any = { item = itemID, n = {} }, {}, false
    for _, list in ipairs(Sources.WHERE_LISTS) do
        local hits = {}
        for id, hit in pairs(byList[list] or {}) do
            if not (own[list] and own[list][id]) then hits[#hits + 1] = hit end
        end
        table.sort(hits, function(a, b)
            if a.f ~= b.f then return a.f > b.f end
            return a.id < b.id
        end)
        local entries = {}
        for i = 1, math.min(#hits, Ship.TRY_MAX) do
            if #entries >= Sources.WHERE_MAX then break end
            local e = Entry(list, hits[i])
            if e then
                entries[#entries + 1] = e
                infos[#infos + 1] = DB.ShipInfoOf(hits[i].name, hits[i].row)
            end
        end
        if #entries > 0 then
            out[list], out.n[list], any = entries, #hits, true
        end
    end
    if not any then return nil end
    out.label = LabelOf(infos)
    return out
end

---------------------------------------------------------------------------
-- Beute eines Gegners, Inhalt eines Behälters
---------------------------------------------------------------------------

-- Gegenstände eines Zählblocks, häufigste zuerst; nur, was der Client kennt (DG-18)
local function Items(total)
    local list = {}
    for item, it in pairs(total.items) do
        local f = Num(it.f) or 0
        if ID(item) and f > 0 and Shows(item) then list[#list + 1] = { id = item, f = f } end
    end
    table.sort(list, function(a, b)
        if a.f ~= b.f then return a.f > b.f end
        return a.id < b.id
    end)
    return list
end

function Ship.LootOf(npcID)
    npcID = ID(npcID)
    if not npcID then return nil end
    local row, info = DB.Shipped("drops", "loot", npcID)
    local total = row and Drops.Total(row)
    if not total then return nil end
    local n = Drops.Denominator(total)
    local items = {}
    for i, e in ipairs(Items(total)) do
        -- unter Drops.WORTH_MIN Vorgängen und bei mehr Funden als Vorgängen (Altbestand) keine Chance, nur „kann“
        items[i] = { id = e.id, chance = n >= Drops.WORTH_MIN and e.f <= n and e.f / n or nil }
    end
    if #items == 0 then return nil end
    return { npc = npcID, items = items, n = n, listed = n < Drops.WORTH_MIN or nil, label = info.label }
end

local CONTENT_KIND = { item = "container", object = "object" }
function Ship.ContentsOf(kind, id)
    id = ID(id)
    local from = id and CONTENT_KIND[kind]
    if not from then return nil end
    local row, info = DB.Shipped("drops", from, id)
    local total = row and Drops.Total(row)
    if not total then return nil end
    local items = {}
    for i, e in ipairs(Items(total)) do items[i] = { id = e.id, listed = true } end
    if #items == 0 then return nil end
    return { kind = kind, id = id, items = items, n = #items, listed = true, label = info.label }
end

-- ready: Es ist Beute oder ein Händler ausgeliefert (sonst wie ein fehlendes Addon).
Sources.Register("ship", {
    label = L.GATHER_SOURCE_SHIP,
    ship = true,
    silent = true,
    ready = function()
        if #DB.ShippedKeys("drops") > 0 or #DB.ShippedKeys("vendor") > 0 then return true end
        return false, "missing"
    end,
    whereFrom = function(itemID, opts) return Ship.WhereFrom(itemID, opts) end,
    lootOf = function(npcID) return Ship.LootOf(npcID) end,
    contentsOf = function(id, kind) return Ship.ContentsOf(kind, id) end,
})

---------------------------------------------------------------------------
-- Lehrer, Flüge, Gebietsstufen, Entzaubern
---------------------------------------------------------------------------

function Ship.Offers(key, wants)
    local out, infos, seen, hits = {}, {}, {}, {}
    if Core.IsSecret(key) or key == nil then return out, nil end
    -- ohne Kopie: ein Satz der Berufslehrer hat Hunderte Angebote, gefragt wird je Rezept
    DB.ShipEach(function(offer, row)
        local kind, who = Keys.OfferKind(offer)
        if not kind or not (wants == nil or wants(kind, who)) then return end
        local s = type(row) == "table" and type(row.svc) == "table" and row.svc[key] or nil
        if type(s) ~= "table" then return end
        hits[#hits + 1] = { offer = offer, kind = kind, s = s, info = DB.ShipInfoOf("offer", row) }
    end, "offer")
    if #hits == 0 then return out, nil end
    table.sort(hits, function(a, b) return a.offer < b.offer end)
    for _, h in ipairs(hits) do
        infos[#infos + 1] = h.info
        for npc in pairs(type(h.s.at) == "table" and h.s.at or {}) do
            if ID(npc) and not seen[npc] and Ship.Fits(npc) then
                seen[npc] = true
                out[#out + 1] = { npc = npc, art = h.kind, price = Num(h.s.pr), skill = Num(h.s.skill) }
            end
        end
    end
    table.sort(out, function(a, b) return a.npc < b.npc end)
    return out, LabelOf(infos), hits[1].kind
end

function Core.Flights.Shipped(from, to, hops)
    local list, info = DB.Shipped("route", from, to)
    if not list then return nil, info end
    local way
    if type(hops) == "table" then
        way = Core.Flights.Pick(list, hops)
    else
        for _, w in ipairs(list) do
            local sec = type(w) == "table" and Num(w.sec)
            if sec and sec > 0 and (not way or sec < way.sec) then way = w end
        end
    end
    -- Spieler und Build dieses Wegs, nicht die der ganzen Liste
    return way, way and DB.ShipInfoOf("route", way) or info
end

function Core.Zones.Shipped(mapID)
    local row, info = DB.Shipped("zoneLv", Keys.MapOf(mapID) or mapID)
    if not row then return nil, nil, info end
    return Num(row.lo), Num(row.hi), info
end

local function SalvageRow(spellID, itemID)
    local row, info = DB.Shipped("salvage", spellID, itemID)
    if not row then return nil, info end
    local any = false
    for item in pairs(type(row.items) == "table" and row.items or {}) do
        if ID(item) and Shows(item) then any = true else row.items[item] = nil end
    end
    if not any then return nil, { reason = "none" } end
    return row, info
end

function Drops.SalvageShipped(itemID, spellID)
    itemID = Num(itemID)
    if not itemID then return nil, { reason = "nokey" } end
    if spellID then return SalvageRow(spellID, itemID) end
    for _, spell in ipairs(DB.ShippedKeys("salvage")) do
        local row, info = SalvageRow(spell, itemID)
        if row then return row, info end
    end
    return nil, { reason = "none" }
end

-- Nach dem Laden von ezData: die Umkehr-Indizes in Scheiben vorbauen (nie im Kampf, Core.Sliced) – sonst entstünden sie
-- bei der ersten Frage in einem Zug; gemerkte Wege zu Lehrern (Core.Proficiency) neu, wenn Angebote dabei sind
function Ship.Prepare()
    local ver = DB.ShipVersion()
    return Core.Sliced(function(tick)
        return { items = BuildItems(tick), npc = BuildPlaces("npc", tick), object = BuildPlaces("object", tick) }
    end, { owner = Core.name, where = "ShipView", onDone = function(built)
        local m = Mem()
        if m.ver ~= ver or type(built) ~= "table" then return end
        m.items = m.items or built.items
        m.places.npc, m.places.object = m.places.npc or built.npc, m.places.object or built.object
    end })
end

Core.Listen("DB_SHIP_READY", function()
    if Sources.Status("ship") == "ok" then Ship.Prepare() end
    local P = Core.Proficiency
    if P and P.Recheck and #DB.ShippedKeys("offer") > 0 then P.Recheck(true) end
end, "ezCore.Ship")
