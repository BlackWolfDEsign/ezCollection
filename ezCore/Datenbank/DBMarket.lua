local _, ns = ...
local Core = ezCore

--[[
    Preis-Schicht der Datenbank: Ablage im Träger ezMarket (Entwurf docs/archiv/entwurf-entdecker-datenbank.md, Abschnitt 1.5;
    Frage F3 „Zwei Ordner“). Prices.lua bleibt die einzige Schnittstelle (Prices.* unverändert); hier stehen nur Ablage,
    Bereiche, Umzug und Trägerwechsel.

      ezMarketDB = { meta = { schema, id (Zufallszahl), project, created, tables = { price = { v } },
                              realms = { [n] = { id, native, core } }, areas = { [n] = { realm, side, pot } }, jobs },
                     area = { [n] = { scanAt, hcols, items = { [itemID] = Preis-Satz }, log = { … }, rules } } }
      rules (AH-04) = { copper, split, cooldown, cut = { v, t, n }, deposit = { [Dauer] = { v, t, n } } } – je Wert
                     mit Zeitpunkt t; geschrieben und gelesen nur über Prices.Rules (Prices.lua)
      Preis-Satz = { lo, mv, qty, auc, t, tf (Marktwert aus einer vollständigen Liste), fk (deren Art als Bit),
                     scan (Bit-Summe), keep, pt,
                     days = Reihe in den Spalten hcols ({ day, lo, mv, hi, qty, scan } je Tag; -1 = unbekannt),
                     var = { [Keys.Variant] = { lo, mv, qty, t, sfx, il, bon, d } } } – d (Welle 23b, A21): Tagespunkte
                     der Abwandlung in denselben Spalten wie days, höchstens Prices.HISTORY_DAYS Tage (fehlt bei
                     Sätzen von vorher, kommt mit der nächsten Erfassung; kein Umzug)
      Protokoll = { { day, hr, wd, scan, rows, t } … } – je Tag, Stunde und Art ein Eintrag

    Ablage: der Träger ezMarket, wenn er geladen ist; sonst still ezCoreDB.market (Rückfall in derselben Form –
    nichts geht verloren, bis die Verknüpfung da ist). Meldet der Client SAVED_VARIABLES_TOO_LARGE für ezMarket, gibt
    es für die Sitzung nur den Arbeitsspeicher (nie eine leere Tabelle über die Datei, nie ein Ausweichen nach
    ezCoreDB). Bereich = lokale Laufnummer aus Keys.Market (Realm + Seite, nur Zahlen; Namen in ezCoreDB.realms).

    Umzug (Fall „Freigabe kam nach Welle 7“, Entwurf Frage S1 Variante b – ein zusätzlicher Umzug): der alte Speicher
    ezCoreDB.prices["Realm-Fraktion"] wird beim ersten Anmelden in diesem Bereich als Auftrag (DB.Job, ohne Schatten)
    Satz für Satz in die Endform übertragen; bis dahin lesen die Preise „neu über alt“ (DB.Market.Entry). Der alte
    Speicher bleibt liegen und läuft nach der heutigen Regel aus (30 Tage ungesehen). Trägerwechsel: liegt im Rückfall
    ezCoreDB.market schon etwas, wenn ezMarket dazukommt, kopiert ein Auftrag es in den Träger (der neuere Stand
    gewinnt) und vermerkt meta.movedTo. Fällt die Ablage später noch einmal auf den Rückfall (ezMarket für eine Sitzung
    aus, Verknüpfung fehlt zeitweise), löscht Market.Root den Vermerk und zählt meta.gen hoch: der nächste Wechsel in
    den Träger kopiert dann erneut (Kennung des Auftrags aus meta.id und meta.gen). In einer solchen Sitzung zeigen die
    Preise den Stand des Rückfalls – was nur im Träger steht, ist ohne ezMarket nicht lesbar.

      Market.Root()            → Ablage, Ort ("carrier" | "core" | "memory")
      Market.Area(create)      → Bereich des eigenen Charakters, Laufnummer
      Market.Entry(bereich, id) → Preis-Satz (auch aus dem alten Speicher, solange der Umzug läuft) oder nil
      Market.Ensure(bereich, id) → Preis-Satz zum Schreiben (legt an; übernimmt dabei einen alten Satz)
      Market.FromOld(alt)      → Preis-Satz aus einem Eintrag des alten Speichers { n, m, q, t, mt, k, h, v }
      Market.Prepare()         → Umzug und Trägerwechsel anmelden (beim Anmelden)
      Market.Stats()           → { where, areas, items, adopting }
]]

local DB = Core.DB
local Keys = DB.Keys
local LIMITS = DB.LIMITS
local Num = Core.Num

local Market = {}
DB.Market = Market

Market.SCHEMA = 1
Market.VERSION = 1   -- Version der Tabelle price (meta.tables.price.v)
Market.HCOLS = { "day", "lo", "mv", "hi", "qty", "scan" }
Market.NCOL = #Market.HCOLS
-- Art der Erfassung als Bit: 1 Komplett-Scan, 2 Suche, 4 Übersicht (Entwurf: scan 1/2/3 – als Bits, weil ein Tag
-- mehrere Arten sammelt). AH-04 (Welle 12): 8 Durchlauf je Kategorie, 16 Sammelabfrage (Prices.Refresh) – neue Bits,
-- kein Umzug; Marktwert (Mittel der günstigsten 25 %) gibt es nur aus 1 und 2.
Market.SCAN = { scan = 1, search = 2, browse = 4, category = 8, bulk = 16 }
Market.KIND = { [1] = "scan", [2] = "search", [4] = "browse", [8] = "category", [16] = "bulk" }

-- Deckel der Preise stehen in DB.LIMITS; die alten Namen der Preis-Schicht zeigen darauf
local P = Core.Prices
if P then
    P.HISTORY_DAYS, P.WATCH_DAYS, P.MAX_POINTS = LIMITS.PRICE_DAYS, LIMITS.PRICE_WATCH_DAYS, LIMITS.PRICE_POINTS
    P.MAX_CAPTURES, P.MAX_AGE, P.MAX_VARIANTS = LIMITS.PRICE_LOG_MAX, LIMITS.PRICE_AGE_DAYS * 86400, LIMITS.PRICE_VARIANTS
    P.LOG_DAYS = LIMITS.PRICE_LOG_DAYS
end

local function G(name) return rawget(_G, name) end

local memory = {}          -- Rückfall nach SAVED_VARIABLES_TOO_LARGE: nur für diese Sitzung
local lastRoot

local function Init(r)
    local m = type(r.meta) == "table" and r.meta or nil
    if not m then
        m = { schema = Market.SCHEMA, id = math.random(1, 2147483646), created = DB.Stamp() }
        r.meta = m
    end
    if m.project == nil then m.project = Num(G("WOW_PROJECT_ID")) end
    m.tables = type(m.tables) == "table" and m.tables or {}
    m.tables.price = type(m.tables.price) == "table" and m.tables.price or { v = Market.VERSION }
    m.realms = type(m.realms) == "table" and m.realms or {}
    m.areas = type(m.areas) == "table" and m.areas or {}
    m.jobs = type(m.jobs) == "table" and m.jobs or {}
    r.area = type(r.area) == "table" and r.area or {}
end

function Market.Root()
    local where, r
    if DB.CarrierLost("market") then
        r, where = memory, "memory"
    else
        local name = DB.CARRIERS.market
        local t = Core.IsLoaded(name) and G(name .. "DB")
        if type(t) == "table" then
            r, where = t, "carrier"
        elseif type(Core.db) == "table" then
            if type(Core.db.market) ~= "table" then Core.db.market = {} end
            r, where = Core.db.market, "core"
        end
    end
    if not r then return nil end
    if r ~= lastRoot then
        Init(r)
        lastRoot = r
    end
    -- wieder im Rückfall nach einem Wechsel in den Träger: beim nächsten Wechsel erneut kopieren
    if where == "core" and r.meta.movedTo then
        r.meta.movedTo = nil
        r.meta.gen = (Num(r.meta.gen) or 0) + 1
    end
    return r, where
end

-- Ältere Fassung der Ablage als das Addon (Kopf-Schema oder Tabellen-Version): nur lesen (Entwurf, Regel 8)
function Market.Readonly(r)
    r = r or Market.Root()
    local m = type(r) == "table" and r.meta
    if not m then return false end
    local project = Num(G("WOW_PROJECT_ID"))
    return (Num(m.schema) or 0) > Market.SCHEMA or (Num(m.tables.price.v) or 0) > Market.VERSION
        or (project ~= nil and Num(m.project) ~= nil and m.project ~= project)
end

local function NewArea()
    local cols = {}
    for i, c in ipairs(Market.HCOLS) do cols[i] = c end
    return { scanAt = 0, hcols = cols, items = {}, log = {}, rules = {} }
end

function Market.Area(create)
    local r = Market.Root()
    if not r then return nil end
    local n = Keys.Market(r)
    if not n then return nil end
    local area = r.area[n]
    if type(area) ~= "table" then
        if not create or Market.Readonly(r) then return nil, n end
        area = NewArea()
        r.area[n] = area
    end
    return area, n
end

---------------------------------------------------------------------------
-- Alte Form (Welle 7) » Endform
---------------------------------------------------------------------------

local OLD_FLAG = { s = 1, e = 2, b = 4 }

local function Bits(flags)
    local bits = 0
    for f in tostring(flags or ""):gmatch(".") do
        local b = OLD_FLAG[f]
        if b and not DB.BHas(bits, b) then bits = bits + b end
    end
    return bits
end

local function V(x) return Num(x) or -1 end

function Market.FromOld(old)
    if type(old) ~= "table" then return nil end
    local e = { lo = Num(old.n), mv = Num(old.m), qty = Num(old.q), t = Num(old.t), tf = Num(old.mt),
        scan = OLD_FLAG[old.k], days = {}, pt = 8 }
    local d = e.days
    for _, p in ipairs(type(old.h) == "table" and old.h or {}) do
        if type(p) == "table" and Num(p[1]) then
            local bits = Bits(p[6])
            d[#d + 1], d[#d + 2], d[#d + 3] = p[1], V(p[2]), V(p[3])
            d[#d + 1], d[#d + 2], d[#d + 3] = V(p[4]), V(p[5]), bits > 0 and bits or -1
        end
    end
    if type(old.v) == "table" then
        for vk, v in pairs(old.v) do
            local key, parts = Keys.VariantFromOld(vk)
            if key and type(v) == "table" then
                e.var = e.var or {}
                e.var[key] = { lo = Num(v.n), mv = Num(v.m), qty = Num(v.q), t = Num(v.t), sfx = parts.sfx, bon = parts.bon }
            end
        end
    end
    return e
end

function Market.LogFromOld(c)
    if type(c) ~= "table" or not Num(c.d) then return nil end
    return { day = c.d, hr = Num(c.h) or 0, wd = Num(c.w), scan = Market.SCAN[c.k], rows = Num(c.n) or 1, t = Num(c.t) }
end

---------------------------------------------------------------------------
-- Lesen „neu über alt“ während des Umzugs
---------------------------------------------------------------------------

local function JobName(n) return "prices:adopt:" .. tostring(n) end

-- Alter Speicher eines Bereichs, solange sein Umzug läuft (sonst nil)
local function PendingOld(n)
    local r = Market.Root()
    local st = r and n and r.meta.jobs[JobName(n)]
    if type(st) ~= "table" or st.done then return nil end
    local old = Core.db and type(Core.db.prices) == "table" and Core.db.prices[st.sig]
    return type(old) == "table" and type(old.items) == "table" and old or nil
end

local converted = setmetatable({}, { __mode = "k" })   -- je alter Satz eine Umwandlung je Sitzung

function Market.Entry(area, itemID, n)
    if type(area) ~= "table" or itemID == nil then return nil end
    local e = area.items[itemID]
    if type(e) == "table" then return e end
    if e ~= nil then return nil end
    if n == nil then n = select(2, Market.Area(false)) end
    local old = PendingOld(n)
    local oe = old and old.items[itemID]
    if type(oe) ~= "table" then return nil end
    local c = converted[oe]
    if not c then
        c = Market.FromOld(oe)
        converted[oe] = c
    end
    return c
end

function Market.Ensure(area, itemID, n)
    local e = area.items[itemID]
    if type(e) == "table" then return e end
    e = Market.Entry(area, itemID, n)
    if e then
        local old = PendingOld(n or select(2, Market.Area(false)))
        if old and old.items[itemID] then converted[old.items[itemID]] = nil end
    else
        e = { days = {} }
    end
    area.items[itemID] = e
    return e
end

-- Alle Gegenstände eines Bereichs (auch die noch nicht übernommenen alten): fn(itemID, satz)
function Market.Each(area, n, fn)
    if type(area) ~= "table" then return end
    for id, e in pairs(area.items) do
        if type(e) == "table" then fn(id, e) end
    end
    local old = PendingOld(n)
    for id in pairs(old and old.items or {}) do
        if area.items[id] == nil then
            local e = Market.Entry(area, id, n)
            if e then fn(id, e) end
        end
    end
end

---------------------------------------------------------------------------
-- Umzug und Trägerwechsel (Aufträge)
---------------------------------------------------------------------------

local function MergeLog(into, list)
    for _, c in ipairs(list) do
        if type(c) == "table" then
            local hit
            for _, have in ipairs(into) do
                if have.day == c.day and have.hr == c.hr and have.scan == c.scan then hit = have break end
            end
            if hit then hit.rows = math.max(Num(hit.rows) or 0, Num(c.rows) or 0) else into[#into + 1] = c end
        end
    end
    table.sort(into, function(a, b) return (Num(a.t) or 0) < (Num(b.t) or 0) end)
end

-- Umzug des alten Speichers dieses Realms und dieser Fraktion (einmal je Bereich)
local function AdoptOld(r, n, area)
    local key = Core.Prices and Core.Prices.Key and Core.Prices.Key()
    local old = key and Core.db and type(Core.db.prices) == "table" and Core.db.prices[key]
    local name = JobName(n)
    local st = r.meta.jobs[name]
    if type(st) == "table" and st.sig ~= key then return end   -- schon ein anderer Speicher für diesen Bereich
    if type(old) ~= "table" or type(old.items) ~= "table" then return end
    DB.Job(name, {
        root = function() return Market.Root() == r and r or nil end,
        sig = key, shadow = false,
        list = function()
            local ids = {}
            for id in pairs(old.items) do ids[#ids + 1] = id end
            return ids
        end,
        step = function(id)
            if area.items[id] == nil and type(old.items[id]) == "table" then
                area.items[id] = converted[old.items[id]] or Market.FromOld(old.items[id])
                converted[old.items[id]] = nil
            end
        end,
        swap = function()
            local logs = {}
            for _, c in ipairs(type(old.log) == "table" and old.log or {}) do logs[#logs + 1] = Market.LogFromOld(c) end
            area.log = type(area.log) == "table" and area.log or {}
            MergeLog(area.log, logs)
            area.scanAt = math.max(Num(area.scanAt) or 0, Num(old.scanAt) or 0)
            local cnt = 0
            for _ in pairs(old.items) do cnt = cnt + 1 end
            return cnt, 0
        end,
    })
end

-- Rückfall ezCoreDB.market » Träger ezMarket (einmal je Wechsel; der neuere Stand gewinnt)
local function MoveFallback(carrier)
    local fb = Core.db and Core.db.market
    if type(fb) ~= "table" or type(fb.meta) ~= "table" or fb.meta.movedTo or type(fb.area) ~= "table" then return end
    if next(fb.area) == nil then return end
    DB.Job("prices:carrier", {
        root = function() return Market.Root() == carrier and carrier or nil end,
        sig = tostring(fb.meta.id) .. ":" .. tostring(Num(fb.meta.gen) or 0), shadow = false,
        list = function()
            local paths = {}
            for n, area in pairs(fb.area) do
                for id in pairs(type(area) == "table" and type(area.items) == "table" and area.items or {}) do
                    paths[#paths + 1] = { n, id }
                end
            end
            return paths
        end,
        step = function(path)
            local a = fb.meta.areas[path[1]]
            local realm = type(a) == "table" and fb.meta.realms[a.realm]
            local to = type(realm) == "table" and Keys.MarketArea(carrier, realm.core, a.side)
            local src = fb.area[path[1]] and fb.area[path[1]].items[path[2]]
            if not (to and type(src) == "table") then return end
            carrier.area[to] = type(carrier.area[to]) == "table" and carrier.area[to] or NewArea()
            local have = carrier.area[to].items[path[2]]
            if type(have) ~= "table" or (Num(have.t) or 0) < (Num(src.t) or 0) then carrier.area[to].items[path[2]] = src end
        end,
        swap = function()
            for n, area in pairs(fb.area) do
                local a = fb.meta.areas[n]
                local realm = type(a) == "table" and fb.meta.realms[a.realm]
                local to = type(realm) == "table" and Keys.MarketArea(carrier, realm.core, a.side)
                if to and type(area) == "table" and carrier.area[to] then
                    carrier.area[to].log = type(carrier.area[to].log) == "table" and carrier.area[to].log or {}
                    MergeLog(carrier.area[to].log, type(area.log) == "table" and area.log or {})
                    carrier.area[to].scanAt = math.max(Num(carrier.area[to].scanAt) or 0, Num(area.scanAt) or 0)
                end
            end
            fb.meta.movedTo = DB.CARRIERS.market
            return 0, 0
        end,
    })
end

function Market.Prepare()
    local r, where = Market.Root()
    if not r or Market.Readonly(r) then return false end
    if where == "carrier" then MoveFallback(r) end
    local area, n = Market.Area(true)
    if area then AdoptOld(r, n, area) end
    return true
end

-- Läuft der Umzug des eigenen Bereichs noch?
function Market.Adopting()
    local _, n = Market.Area(false)
    return PendingOld(n) ~= nil
end

function Market.Stats()
    local r, where = Market.Root()
    local out = { where = where, areas = 0, items = 0, adopting = Market.Adopting() }
    for _, area in pairs(r and r.area or {}) do
        out.areas = out.areas + 1
        for _ in pairs(type(area) == "table" and type(area.items) == "table" and area.items or {}) do out.items = out.items + 1 end
    end
    return out
end

ns.On("ADDON_LOADED", function(_, name)
    if name == DB.CARRIERS.market then lastRoot = nil end
end)
Core.Listen("DB_CARRIER_LOST", function(name)
    if name == DB.CARRIERS.market then lastRoot = nil end
end, "ezCore.DBMarket")
