local _, ns = ...
local Core = ezCore
local L = Core.L

--[[
    Entdecker-Datenbank: Leser (Fach-Fassaden), Abschnitt „Datenbank“ und /ez status (Welle 9; Entwurf
    docs/archiv/entwurf-entdecker-datenbank.md, Abschnitt 7). Die Fassaden rufen nur den Dienst DB; jede Antwort trägt eine
    Auskunft info = { src = "own", label = „bei dir“, t, b, cnt … } für die Quellenzeile (Leitlinie 11).
    Entdecker-Wissen (seltene Gegner, Buch-Fundorte, enthüllte Gegenstände, Vignetten) liefern die Fassaden nur mit
    dem Schalter OPT_explorer (ab Werk aus) oder opts.explorer = true; gesammelt wird es trotzdem.

      Core.Drops.Of(art, id | karte, gebiet) → Summe { cnt, party, empty, deaths, money, items, tokens, diff, old },
                                       info (+ info.old = Fenster aus dem alten Verlauf)
      Core.Drops.Denominator(summe)  → n, "deaths" | "loots" – Nenner je Herkunft: max(Tode, Fenster) der neuen
                                       Blöcke plus Fenster des Altbestands („bei m getöteten“ bzw. „bei m geöffneten“)
      Core.Drops.SourcesOf(itemID)   → { { kind, id, f, s, cnt } … } eigene Quellen, häufigste zuerst
      Core.Drops.Worth(art, …), Core.Drops.WorthLines(art, …) → Wert je Tötung bzw. je Ernte (V2, Welle 23d; unten);
      Core.Drops.WorthLinesOf(ergebnis), Core.Drops.WorthCount(ergebnis) – Zeilen bzw. Nenner aus einem Ergebnis (Welle 26)
      Core.Drops.Salvage(itemID, spellID) → Zählblock, info (Entzauber-Ergebnisse „bei dir n×“)
      Core.Places.Of(art, id, opts)  → { { map, xy, x, y, cnt, t, via, inst } … }; Core.Places.OnMap(karte, opts)
      Core.Finds.Of(itemID)          → { { mapID, count, points } … } eigene Sammel-Fundorte (Objekte, Angeln);
                                       count = Ernten, points = Punkte auf der Karte; Kisten nur mit OPT_explorer (SAM-05)
      Core.Finds.IsExplorerObject(id) → true für Kisten (obj kind chest): Entdecker-Wissen
      Core.Finds.ObjectKind(id)      → Art des Spielobjekts (herb, mine, chest, pool, quest, container) oder nil
      Core.Vendors.Of(npcID), Core.Vendors.Selling(itemID); Core.Trainers.Offers(art), Core.Trainers.For(npcID)
      Core.Flights.Time(von, nach, hops); Core.Entrances.Of(instanceID), Core.Entrances.OnMap(karte)
      Core.Rares.Of(npcID), Core.Rares.OnMap(karte); Core.Zones.Levels(karte); Core.Reveal.Has(itemID);
      Core.Books.Where(itemID)
    „nicht mehr gesehen“: Einträge mit t vor dem letzten vollständigen Blick (tf) tragen gone = true.
]]

local DB = Core.DB
local Keys = DB.Keys
local Discovery = Core.Discovery
local Num = Core.Num

local function Visible(kind, opts)
    local k = Keys.KINDS[kind]
    return not (k and k.explorer) or DB.Explorer() or (type(opts) == "table" and opts.explorer == true)
end

---------------------------------------------------------------------------
-- Beute
---------------------------------------------------------------------------

local Drops = {}
Core.Drops = Drops

local function AddBlock(into, b)
    if type(b) ~= "table" then return end
    for _, k in ipairs({ "cnt", "party", "empty", "deaths" }) do
        if Num(b[k]) then into[k] = (into[k] or 0) + b[k] end
    end
    if type(b.money) == "table" then
        into.money = into.money or { sum = 0, cnt = 0 }
        into.money.sum = into.money.sum + (Num(b.money.sum) or 0)
        into.money.cnt = into.money.cnt + (Num(b.money.cnt) or 0)
    end
    for id, it in pairs(type(b.items) == "table" and b.items or {}) do
        local d = into.items[id] or { f = 0, s = 0 }
        into.items[id] = d
        d.f, d.s = d.f + (Num(it.f) or 0), d.s + (Num(it.s) or 0)
        if Num(it.lo) then d.lo = math.min(d.lo or it.lo, it.lo) end
        if Num(it.hi) then d.hi = math.max(d.hi or it.hi, it.hi) end
    end
    for cur, it in pairs(type(b.tokens) == "table" and b.tokens or {}) do
        into.tokens = into.tokens or {}
        local d = into.tokens[cur] or { f = 0, s = 0 }
        into.tokens[cur] = d
        d.f, d.s = d.f + (Num(it.f) or 0), d.s + (Num(it.s) or 0)
    end
end

function Drops.Of(kind, ...)
    local row, info = DB.Get("drops", kind, ...)
    if not row then return nil, info end
    local total = { items = {} }
    for _, b in pairs(type(row.diff) == "table" and row.diff or {}) do AddBlock(total, b) end
    AddBlock(total, row.old)
    total.diff, total.old = row.diff, row.old
    info.old = type(row.old) == "table" and Num(row.old.cnt) or 0
    return total, info
end

-- Nenner je Herkunft: Tode gibt es erst seit Welle 9 (PARTY_KILL), im Eimer „old“ nur geöffnete Fenster. Darum zählt
-- für die neuen Blöcke max(Tode, Fenster) und für den Altbestand dessen Fenster – sonst stünde nach der Übernahme
-- „50× bei 1 getöteten“ da. "deaths" nur, wenn die Tode die neuen Fenster abdecken (Gegenprüfung Welle 9).
function Drops.Denominator(total)
    if type(total) ~= "table" then return 0, nil end
    local deaths, cnt, old = 0, 0, 0
    if type(total.diff) == "table" or type(total.old) == "table" then
        for _, b in pairs(type(total.diff) == "table" and total.diff or {}) do
            if type(b) == "table" then
                deaths, cnt = deaths + (Num(b.deaths) or 0), cnt + (Num(b.cnt) or 0)
            end
        end
        old = type(total.old) == "table" and Num(total.old.cnt) or 0
    else
        deaths, cnt = Num(total.deaths) or 0, Num(total.cnt) or 0   -- ein einzelner Zählblock
    end
    local what = (deaths > 0 and deaths >= cnt) and "deaths" or "loots"
    return math.max(deaths, cnt) + old, what
end

-- V2 (Welle 23d; Bericht Welle 20, docs/archiv/eroerterung-datenbank.md, vom Nutzer freigegeben „zuerst V1–V5“): Wert je
-- Tötung bzw. je Ernte aus der eigenen Beute (Zählblöcke von Drops.Of) und eigenen Preisen.
--   Drops.Worth(art, id | karte, gebiet) → Ergebnis oder nil, Grund ("secret" | "none" | "few" | "noprice"), n
--     Ergebnis = { value = Kupfer je Vorgang, per = "kill" | "pick" | "harvest" | "open" | "catch" (Drops.WorthPer), n = Nenner, what = "deaths" | "loots",
--                  money = Geld je Vorgang, items = { { item, part, price, how = "auction" | "vendor" } … } (größter
--                  Anteil zuerst), auction = Zahl der Gegenstände mit Auktionspreis, vendor = mit Händlerpreis,
--                  unpriced = ohne Preis, age = Alter des ältesten Auktionspreises in Sekunden (oder nil) }
--     Preis je Gegenstand: Marktwert aus den eigenen Auktionshaus-Erfassungen (Prices.Get), sonst der Händlerpreis laut
--     Client (Core.VendorPrice) – als solcher benannt. Unter Drops.WORTH_MIN Vorgängen: nil, "few", n (die Zeile
--     erschiene sonst mit einer Zufallszahl). Gesperrte Schlüssel (Leitlinie 6): nil, "secret".
--   Drops.WorthLines(art, …) → { Wert-Zeile, Quellen-Zeile, value = …, basis = …, price = … } (Leitlinie 11:
--     Grundlage und Preisquelle stehen dabei) oder {} – für den Tooltip des Gegners (ezLoot) und der Fundort-Punkte
--     (ezMap). Drops.WorthLinesOf(ergebnis) baut dieselben Zeilen aus einem schon gerechneten Ergebnis von Drops.Worth.
--     Welle 26 (Paket kern/ezcore-reste-24): Gegner („kill“) mit dem Wortlaut des Plans „Wert je Tötung: … (aus deiner
--     Beute, n Tötungen)“ (bzw. „n Mal geplündert“); übrige Arten „≈ … je Ernte“, „je Fang“ usw. Die Felder:
--       value = die Wert-Zeile (wie [1]); basis = Nenner als Text („bei dir getötet: 40“); price = nur der Preis-Teil,
--       groß beginnend („Preise aus deinen Auktionshaus-Erfassungen …; sonst Händlerpreis laut Client“) – für eine
--       Zeile, die den Nenner schon nennt (ezLoot mit Shift); [2] bleibt „Grundlage: <basis>; <Preise>“.
--   Drops.WorthCount(ergebnis) → „40 Tötungen“ bzw. „12 Mal geplündert“ (Nenner eines Gegners, Einzahl/Mehrzahl)
Drops.WORTH_MIN = 5
-- alle übrigen Arten: "harvest" (Sammelknoten, Kürschnern, Kräuter und Erz an Leichen …). Gegenprüfung 23d:
-- Taschendiebstahl je Vorgang ("pick"), Kisten in der Welt (Spielobjekt mit kind = "chest") je Öffnen. Welle 26:
-- Angeln je Fang ("catch": Angel-Gebiete und Fischschwärme, Spielobjekt mit kind = "pool").
Drops.WORTH_PER = { loot = "kill", pick = "pick", container = "open", fishing = "catch" }
Drops.WORTH_PER_OBJECT = { chest = "open", pool = "catch" }
function Drops.WorthPer(kind, id)
    if kind == "object" then
        local row = id ~= nil and DB.Get("obj", id) or nil
        local per = type(row) == "table" and Drops.WORTH_PER_OBJECT[row.kind]
        if per then return per end
    end
    return Drops.WORTH_PER[kind] or "harvest"
end

function Drops.Worth(kind, ...)
    if Core.IsSecret(kind) then return nil, "secret" end   -- zuerst prüfen, nie mit nil vergleichen (Leitlinie 6)
    if kind == nil then return nil, "none", 0 end
    for i = 1, select("#", ...) do
        if Core.IsSecret((select(i, ...))) then return nil, "secret" end
    end
    local total = Drops.Of(kind, ...)
    if not total then return nil, "none", 0 end
    local n, what = Drops.Denominator(total)
    if n <= 0 then return nil, "none", 0 end
    if n < Drops.WORTH_MIN then return nil, "few", n end
    local P = Core.Prices
    local now = time and time() or 0
    local res = { per = Drops.WorthPer(kind, (...)), n = n, what = what, items = {}, auction = 0, vendor = 0,
        unpriced = 0, value = 0 }
    for itemID, it in pairs(total.items or {}) do
        local s = Num(it.s) or 0
        if Num(itemID) and s > 0 then
            local info = P and P.Get and P.Get(itemID)
            local price, how = type(info) == "table" and Num(info.market), "auction"
            if price then
                res.auction = res.auction + 1
                local seen = Num(info.seen)
                if seen then res.age = math.max(res.age or 0, math.max(0, now - seen)) end
            else
                price, how = Core.VendorPrice and Num(Core.VendorPrice(itemID)), "vendor"
                if price and price > 0 then res.vendor = res.vendor + 1 else price = nil end
            end
            if price then
                local part = price * s / n
                res.items[#res.items + 1] = { item = itemID, part = part, price = price, how = how }
                res.value = res.value + part
            else
                res.unpriced = res.unpriced + 1
            end
        end
    end
    local money = type(total.money) == "table" and Num(total.money.sum) or 0
    res.money = money / n
    res.value = res.value + res.money
    if #res.items == 0 and money <= 0 then return nil, "noprice", n end
    table.sort(res.items, function(a, b) return a.part > b.part end)
    res.value = math.floor(res.value + 0.5)
    return res
end

local WORTH_PERS = { kill = true, pick = true, harvest = true, open = true, catch = true }

function Drops.WorthCount(w)
    local n = type(w) == "table" and Num(w.n) or 0
    local what = type(w) == "table" and w.what == "deaths" and "deaths" or "loots"
    return Core.Plural(n, L["DROPS_WORTH_COUNT_" .. what .. "_ONE"], L["DROPS_WORTH_COUNT_" .. what .. "_MANY"])
end

function Drops.WorthLinesOf(w)
    if type(w) ~= "table" or Core.IsSecret(w) or not Num(w.value) or not Num(w.n) then return {} end
    local per = WORTH_PERS[w.per] and w.per or "harvest"
    local basis
    if per == "kill" then basis = L["DROPS_WORTH_BASIS_" .. (w.what == "deaths" and "deaths" or "loots")]
    else basis = L["DROPS_WORTH_BASIS_" .. per] end
    basis = basis:format(Num(w.n))
    local prices = {}
    if (Num(w.auction) or 0) > 0 then
        local age = Num(w.age)
        prices[#prices + 1] = age and L.DROPS_WORTH_AUCTION_AGE:format(Core.Duration(age, true)) or L.DROPS_WORTH_AUCTION
    end
    if (Num(w.vendor) or 0) > 0 then prices[#prices + 1] = L.DROPS_WORTH_VENDOR end
    if (Num(w.unpriced) or 0) > 0 then prices[#prices + 1] = L.DROPS_WORTH_UNPRICED:format(Num(w.unpriced)) end
    if #prices == 0 then prices[1] = L.DROPS_WORTH_MONEY_ONLY end   -- nur Geld erbeutet (Gegenprüfung 23d)
    local price = table.concat(prices, "; ")
    local value
    if per == "kill" then value = L.DROPS_WORTH_KILL:format(Core.CoinText(Num(w.value)), Drops.WorthCount(w))
    else value = L["DROPS_WORTH_PER_" .. per]:format(Core.CoinText(Num(w.value))) end
    return { value, L.DROPS_WORTH_SOURCE:format(basis, price), value = value, basis = basis,
        price = (price:gsub("^%l", string.upper)) }
end

function Drops.WorthLines(kind, ...)
    return Drops.WorthLinesOf((Drops.Worth(kind, ...)))
end

--[[
    Umkehr-Index „welche Quellen hat ein Gegenstand?“ für Drops.SourcesOf (Gesamtreview 18.11.2026, T8-2): vorher baute
    jeder Gegenstands-Tooltip nach einer Beute den GANZEN Index neu (jede Beute hebt DB.Version("drops")). Jetzt wird
    er schrittweise geführt wie DB.Index: DB.OnApply("drops") meldet jeden geschriebenen Satz, und beim nächsten Lesen
    trägt Drops.SourcesOf nur diese Sätze nach (alte Einträge des Satzes raus, neue rein). Nur wenn sich die Tabelle auf
    einem anderen Weg geändert hat (Version höher als die gemeldeten Schreibvorgänge: Aufräumen, Übernahme, Löschen),
    baut sie ihn ganz neu. Drops.RebuildSources() baut sofort neu; Drops.SourcesStats() → { full, partial } für die
    Prüfungen.
]]
local sourceIndex, sourceVersion
local keyItems = {}              -- [Satz-Schlüssel] = { [itemID] = true }: wo stehen die Einträge eines Satzes
local dirty, dirtyWrites = {}, 0 -- gemeldete Sätze seit dem letzten Stand des Index
local sourceStats = { full = 0, partial = 0 }
Core.Listen("DB_READY", function() sourceIndex = nil end, "ezCore.Discovery")

-- Einträge eines Satzes in den Index (idx[itemID][key]) und in keyItems[key]
local function IndexRow(idx, row, keys)
    local total = { items = {} }
    for _, b in pairs(type(row.diff) == "table" and row.diff or {}) do AddBlock(total, b) end
    AddBlock(total, row.old)
    local key = table.concat(keys, ":")
    local items = {}
    for itemID, it in pairs(total.items) do
        local list = idx[itemID] or {}
        idx[itemID] = list
        list[key] = { kind = keys[1], id = keys[2], area = keys[3], f = it.f, s = it.s, cnt = Num(total.cnt) or 0 }
        items[itemID] = true
    end
    keyItems[key] = next(items) and items or nil
end

local function BuildIndex()
    local idx = {}
    keyItems = {}
    DB.Scan("drops", function(row, _, _, keys) IndexRow(idx, row, keys) end)
    return idx
end

function Drops.RebuildSources()
    sourceIndex, sourceVersion = BuildIndex(), DB.Version("drops")
    dirty, dirtyWrites = {}, 0
    sourceStats.full = sourceStats.full + 1
    return sourceIndex
end

DB.OnApply("drops", function(keys)
    if not sourceIndex then return end
    dirty[table.concat(keys, ":")] = keys
    dirtyWrites = dirtyWrites + 1
end)

-- Nur die gemeldeten Sätze nachtragen; passt die Zahl der Änderungen nicht, ganz neu bauen
local function UpdateIndex()
    local version = DB.Version("drops")
    if not sourceIndex or sourceVersion + dirtyWrites ~= version then return Drops.RebuildSources() end
    for key, keys in pairs(dirty) do
        for itemID in pairs(keyItems[key] or {}) do
            local list = sourceIndex[itemID]
            if list then
                list[key] = nil
                if next(list) == nil then sourceIndex[itemID] = nil end
            end
        end
        keyItems[key] = nil
        local row = DB.Get("drops", unpack(keys))
        if type(row) == "table" then IndexRow(sourceIndex, row, keys) end
    end
    sourceVersion, dirty, dirtyWrites = version, {}, 0
    sourceStats.partial = sourceStats.partial + 1
    return sourceIndex
end

function Drops.SourcesStats() return { full = sourceStats.full, partial = sourceStats.partial } end

function Drops.SourcesOf(itemID)
    itemID = Num(itemID)
    if not (itemID and DB.Ready()) then return {} end
    if not sourceIndex or sourceVersion ~= DB.Version("drops") then UpdateIndex() end
    local out = {}
    for _, e in pairs(sourceIndex[itemID] or {}) do
        out[#out + 1] = { kind = e.kind, id = e.id, area = e.area, f = e.f, s = e.s, cnt = e.cnt }
    end
    table.sort(out, function(a, b) return a.f > b.f end)
    return out
end

function Drops.Salvage(itemID, spellID)
    itemID = Num(itemID)
    if not itemID then return nil, { reason = "nokey" } end
    if spellID then return DB.Get("salvage", spellID, itemID) end
    for _, spell in ipairs(DB.KeysOf("salvage")) do
        local row, info = DB.Get("salvage", spell, itemID)
        if row then return row, info end
    end
    return nil, { reason = "none" }
end

---------------------------------------------------------------------------
-- Orte
---------------------------------------------------------------------------

local Places = {}
Core.Places = Places

local function Expand(map, el)
    local x, y = Keys.Unpack(el.xy)
    return { map = map, xy = el.xy, x = x, y = y, cnt = el.cnt, t = el.t, b = el.b, via = el.via, inst = el.inst, pt = el.pt }
end

-- Orte eines seltenen Gegners sind Entdecker-Wissen (Leitlinie 11), auch wenn sie unter der Art „npc“ liegen
-- (Sichtung, Beute): ohne Schalter liefern die Ort-Leser sie nicht (Gegenprüfung Welle 9).
local function HiddenRare(kind, id, opts)
    return kind == "npc" and not Visible("vignette", opts) and DB.Get("rare", id) ~= nil
end

function Places.Of(kind, id, opts)
    local out = {}
    if not Visible(kind, opts) or HiddenRare(kind, id, opts) then return out end
    for _, map in ipairs(DB.KeysOf("spot")) do
        local list = DB.Get("spot", map, kind, id)
        for _, el in ipairs(list or {}) do out[#out + 1] = Expand(map, el) end
    end
    table.sort(out, function(a, b) return (a.cnt or 0) > (b.cnt or 0) end)
    return out
end

function Places.OnMap(mapID, opts)
    local out = {}
    mapID = Num(mapID)
    if not mapID then return out end
    for _, kind in ipairs(DB.KeysOf("spot", mapID)) do
        if Visible(kind, opts) and not (type(opts) == "table" and opts.kind and opts.kind ~= kind) then
            out[kind] = {}
            for _, id in ipairs(DB.KeysOf("spot", mapID, kind)) do
                if not HiddenRare(kind, id, opts) then
                    local list = {}
                    for _, el in ipairs(DB.Get("spot", mapID, kind, id) or {}) do list[#list + 1] = Expand(mapID, el) end
                    out[kind][id] = list
                end
            end
        end
    end
    return out
end

-- Eigene Sammel-Fundorte eines Materials (Spielobjekte mit Ort, Angeln je Karte) – Quelle „bei dir“ in
-- Core.Gathering.Sources (DG-12). Gezählt wird, wie oft du dort geerntet hast.
local Finds = {}
Core.Finds = Finds

-- SAM-05: Kisten (Beute aus einem Spielobjekt ohne Sammelzauber) sind Entdecker-Wissen
function Finds.IsExplorerObject(id)
    local row = DB.Get("obj", id)
    return type(row) == "table" and row.kind == "chest"
end

-- Art eines geplünderten Spielobjekts (obj kind: herb, mine, chest, pool, quest, container) oder nil – für den Inhalt
-- von Kisten im Objekt-Tooltip (ezLoot, Contents.lua; 22.11.2026). Gesperrte oder fehlende ID: nil.
function Finds.ObjectKind(id)
    if Core.IsSecret(id) then return nil end
    id = Num(id)
    if not id or id <= 0 then return nil end
    local row = DB.Get("obj", id)
    local kind = type(row) == "table" and row.kind or nil
    return type(kind) == "string" and kind or nil
end

-- Welle 13: Sammel-Fundorte nennen nur Sammelknoten (Kraut, Erz, Schwarm) und mit Entdecker-Wissen Kisten – nie
-- Quest-Objekte (Nachschlage-Wissen für Quests) und neutrale Behälter (Discovery.LootKind)
Finds.GATHER_KINDS = { herb = true, mine = true, pool = true }
function Finds.IsGatherObject(id, explorer)
    local row = DB.Get("obj", id)
    local kind = type(row) == "table" and row.kind or nil
    if kind == nil then return true end   -- ohne Satz wie bisher (Altbestand)
    if Finds.GATHER_KINDS[kind] then return true end
    return kind == "chest" and explorer == true
end

-- Punkte beim Angeln: nur die Fang-Positionen der Gebiete, in denen dieser Gegenstand gefangen wurde (spot fishing
-- je Gebiet), nicht alle Angel-Stellen der Karte (Gegenprüfung Welle 12)
function Finds.Of(itemID)
    local out, byMap, points, areas = {}, {}, {}, {}
    local explorer = DB.Explorer()
    for _, src in ipairs(Drops.SourcesOf(itemID)) do
        if src.kind == "object" then
            if Finds.IsGatherObject(src.id, explorer) then
                for _, p in ipairs(Places.Of("object", src.id)) do
                    if p.map and p.map > 0 then
                        byMap[p.map] = (byMap[p.map] or 0) + (p.cnt or 1)
                        points[p.map] = (points[p.map] or 0) + 1
                    end
                end
            end
        elseif src.kind == "fishing" and Num(src.id) and src.id > 0 then
            byMap[src.id] = (byMap[src.id] or 0) + src.f
            local done = areas[src.id] or {}
            areas[src.id] = done
            points[src.id] = points[src.id] or 0
            if src.area ~= nil and not done[src.area] then
                done[src.area] = true
                local list = DB.Get("spot", src.id, "fishing", src.area)
                points[src.id] = points[src.id] + (type(list) == "table" and #list or 0)
            end
        end
    end
    for map, count in pairs(byMap) do out[#out + 1] = { mapID = map, count = count, points = points[map] or 0 } end
    table.sort(out, function(a, b) return a.count > b.count end)
    return out
end

function Finds.Any()
    return DB.Ready() and (#DB.KeysOf("drops", "object") > 0 or #DB.KeysOf("drops", "fishing") > 0)
end

if Core.Gathering and Core.Gathering.AddProvider then
    Core.Gathering.AddProvider("ezCore", L.DB_OWN, function(itemID) return Finds.Of(itemID) end,
        { first = true, active = Finds.Any })
end

---------------------------------------------------------------------------
-- Händler, Lehrer, Flüge, Eingänge, Seltenes, Zonen, Enthülltes, Bücher
---------------------------------------------------------------------------

local function MarkGone(map, tf)
    tf = Num(tf)
    if not tf then return end
    for _, e in pairs(type(map) == "table" and map or {}) do
        if type(e) == "table" and (Num(e.t) or 0) < tf then e.gone = true end
    end
end

local Vendors = {}
Core.Vendors = Vendors

function Vendors.Of(npcID)
    local row, info = DB.Get("vendor", npcID)
    if row then MarkGone(row.w, row.tf) end
    return row, info
end

function Vendors.Selling(itemID)
    itemID = Num(itemID)
    local out = {}
    if not itemID then return out end
    DB.Scan("vendor", function(row, _, npc)
        local w = type(row.w) == "table" and row.w[itemID]
        if type(w) == "table" then
            out[#out + 1] = { npc = npc, pr = w.pr, per = w.per, lim = w.lim, t = w.t,
                gone = Num(row.tf) and (Num(w.t) or 0) < row.tf or nil }
        end
    end)
    table.sort(out, function(a, b) return (a.pr or 0) < (b.pr or 0) end)
    return out
end

local Trainers = {}
Core.Trainers = Trainers

function Trainers.Offers(art)
    local row, info = DB.Get("offer", art)
    if row then MarkGone(row.svc, row.tf) end
    return row, info
end

function Trainers.For(npcID)
    local npc = DB.Get("npc", npcID)
    if not (npc and npc.tk) then return nil, { reason = "none" } end
    return Trainers.Offers(npc.tk)
end

-- Flugzeit: mit hops genau dieser Weg, sonst der zuletzt geflogene; info.ways nennt die Zahl der Wege.
function Core.Flights.Time(from, to, hops)
    local list, info = DB.Get("route", from, to)
    if not list then return nil, info end
    info.ways = #list
    local best
    for _, way in ipairs(list) do
        local same = true
        if type(hops) == "table" then
            local h = type(way.hops) == "table" and way.hops or {}
            same = #h == #hops
            for i = 1, #hops do if h[i] ~= hops[i] then same = false end end
            if same then return way, info end
        elseif not best or (Num(way.t) or 0) > (Num(best.t) or 0) then
            best = way
        end
    end
    if type(hops) == "table" then return nil, info end
    return best, info
end

local Entrances = {}
Core.Entrances = Entrances

function Entrances.Of(instanceID)
    local row, info = DB.Get("entrance", instanceID)
    if not row then return nil, info end
    row.places = Places.Of("entrance", instanceID)
    return row, info
end

function Entrances.OnMap(mapID)
    local out = {}
    local on = Places.OnMap(mapID, { kind = "entrance" })
    for inst, list in pairs(on.entrance or {}) do
        for _, p in ipairs(list) do
            if p.x and p.y then out[#out + 1] = { inst = inst, x = p.x, y = p.y, cnt = p.cnt, t = p.t } end
        end
    end
    return out
end

local Rares = {}
Core.Rares = Rares

function Rares.Of(npcID, opts)
    if not Visible("vignette", opts) then return nil, { reason = "explorer" } end
    return DB.Get("rare", npcID)
end

function Rares.OnMap(mapID, opts)
    local out = {}
    if not Visible("vignette", opts) then return out end
    local on = Places.OnMap(mapID, { kind = "npc", explorer = true })   -- der Schalter ist oben geprüft
    for npc, list in pairs(on.npc or {}) do
        if DB.Get("rare", npc) then out[#out + 1] = { npc = npc, places = list } end
    end
    return out
end

Core.Zones = Core.Zones or {}
function Core.Zones.Levels(mapID)
    local row, info = DB.Get("zoneLv", Keys.MapOf(mapID) or mapID)
    if not row then return nil, nil, info end
    return Num(row.lo), Num(row.hi), info
end

Core.Reveal = Core.Reveal or {}
function Core.Reveal.Has(itemID) return DB.Revealed(Num(itemID)) end

Core.Books = Core.Books or {}
function Core.Books.Where(itemID, opts)
    return Places.Of("book", Num(itemID), opts)
end

---------------------------------------------------------------------------
-- /ez status und Abschnitt „Datenbank“ (Esc » Optionen » AddOns » ezCollection » Erweitert)
---------------------------------------------------------------------------

local function SizeText(bytes)
    bytes = Num(bytes) or 0
    local text
    if bytes >= 1024 * 1024 then text = L.DB_MB:format(Core.Decimal(bytes / (1024 * 1024), 1))
    else text = L.DB_KB:format(string.format("%.0f", math.max(1, bytes / 1024))) end
    if Core.IsGerman() then text = text:gsub("(%d)%.(%d)", "%1,%2") end
    return text
end
Discovery.SizeText = SizeText

function Discovery.StatusLines(full)
    local st = DB.Stats()
    if not st.ready then return { L.DB_STATUS_WAIT } end
    local where = st.frozen and L.DB_FROZEN or (st.persistent and L.DB_SAVED or L.DB_NOT_SAVED)
    local lines = { L.DB_STATUS_LINE:format(st.rows, SizeText(st.bytes), where) }
    local done, open = Discovery.AdoptState()
    lines[#lines + 1] = done and L.DB_ADOPT_DONE or L.DB_ADOPT_OPEN:format(table.concat(open, ", "))
    local bytes, cut = DB.Measure(Core.db)
    lines[#lines + 1] = L.DB_CORE_SIZE:format(SizeText(bytes) .. (cut and "+" or ""))
    local M = DB.Market
    if M then
        local ms = M.Stats()
        local where = ms.where == "carrier" and L.DB_MARKET_CARRIER or (ms.where == "memory" and L.DB_MARKET_MEMORY or L.DB_MARKET_CORE)
        if ms.adopting then where = where .. ", " .. L.DB_MARKET_ADOPTING end
        lines[#lines + 1] = L.DB_MARKET_LINE:format(ms.items, ms.areas, where)
    end
    if full then
        for _, t in ipairs(st.tables) do
            if t.rows > 0 then lines[#lines + 1] = L.DB_TABLE_LINE:format(t.name, t.rows, SizeText(t.bytes)) end
        end
        local s = st.skipped or {}
        if (Num(s.secret) or 0) + (Num(s.nokey) or 0) + (Num(s.notready) or 0) > 0 then
            lines[#lines + 1] = L.DB_SKIPPED:format(Num(s.secret) or 0, Num(s.nokey) or 0, Num(s.notready) or 0)
        end
    end
    return lines
end

function Discovery.PrintStatus()
    for _, line in ipairs(Discovery.StatusLines(true)) do ns.Print(line) end
end

function Discovery.AskPrune()
    local n = DB.Prune({ dry = true })
    if n == 0 then
        ns.Print(L.DB_PRUNE_NONE:format(DB.LIMITS.PRUNE_DAYS))
        return nil
    end
    return Core.Confirm(L.DB_PRUNE_ASK:format(n, DB.LIMITS.PRUNE_DAYS), function()
        ns.Print(L.DB_PRUNE_DONE:format(DB.Prune()))
    end, { alert = true })
end

function Discovery.AskResetCache()
    return Core.Confirm(L.DB_CACHE_ASK, function()
        ns.Print(L.DB_CACHE_DONE:format(DB.Reset("cache")))
    end)
end

function Discovery.AskResetDrops()
    return Core.Confirm(L.DB_DROPS_ASK, function()
        ns.Print(L.DB_DROPS_DONE:format(DB.Reset("drops")))
    end, { alert = true })
end

-- Einstellungs-Prüfung 19.11.2026 (Abschnitt 3): die beiden Spielerschalter stehen nicht mehr zwischen den
-- Entwicklerwerkzeugen unter „Erweitert“ – „Erlebtes in der Datenbank sammeln“ im Abschnitt „Daten“
-- (Discovery.AddCollectSetting, Collection.lua), „Entdecker-Wissen zeigen (Spoiler)“ im Abschnitt „Sammeln“
-- (Discovery.AddExplorerSetting, Gathering.AddCare). Ihre Schlüssel bleiben (discovery.dataCollect, discovery.explorer).
function Discovery.AddCollectSetting(page)
    if type(page) ~= "table" or type(page.OwnCheckbox) ~= "function" then return false end
    page:OwnCheckbox("discovery", "dataCollect")
    return true
end

function Discovery.AddExplorerSetting(page)
    if type(page) ~= "table" or type(page.OwnCheckbox) ~= "function" then return false end
    page:OwnCheckbox("discovery", "explorer")
    return true
end

function Discovery.AddSettings(page)
    if type(page) ~= "table" or type(page.Button) ~= "function" then return false end
    page:Button(L.DB_STATUS_LABEL, L.DB_STATUS_BUTTON, function() Discovery.PrintStatus() end, L.DB_STATUS_TIP)
    page:Button(L.DB_PRUNE_LABEL, L.DB_PRUNE_BUTTON, function() Discovery.AskPrune() end, L.DB_PRUNE_TIP:format(DB.LIMITS.PRUNE_DAYS))
    page:Button(L.DB_CACHE_LABEL, L.DB_CACHE_BUTTON, function() Discovery.AskResetCache() end, L.DB_CACHE_TIP)
    page:Button(L.DB_DROPS_LABEL, L.DB_DROPS_BUTTON, function() Discovery.AskResetDrops() end, L.DB_DROPS_TIP)
    -- Beitragen (DB-N1): fester Eintrag „Mithelfen“, Knopf „Beitrag vorbereiten“, Schalter für den Hinweis
    if Core.Contribute and Core.Contribute.AddSettings then Core.Contribute.AddSettings(page) end
    return true
end

-- Warnschwelle und verlorener Träger: eine deutliche Meldung im Chat (Entwurf 9.1 und 10)
Core.Listen("DB_LIMIT", function(_, bytes) ns.Print(L.DB_LIMIT_WARN:format(SizeText(bytes))) end, "ezCore.Discovery")
Core.Listen("DB_CARRIER_LOST", function(name) ns.Print(L.DB_CARRIER_LOST_WARN:format(tostring(name), tostring(name))) end,
    "ezCore.Discovery")
