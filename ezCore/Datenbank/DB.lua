local ADDON, ns = ...
local Core = ezCore
local L = Core.L

--[[
    Entdecker-Datenbank: der Dienst (Welle 9, Zweig kern/entdecker-datenbank; Entwurf
    docs/archiv/entwurf-entdecker-datenbank.md, vom Nutzer am 14.11.2026 freigegeben). Das Gedächtnis von ezCollection für
    alles, was nur im Spiel zu erfahren ist, dazu die Antworten des Clients. Nur Nummern und Zahlen; Namen ohne
    Auflöser im Client stehen getrennt je Sprache (DB.Text). Nie gespeichert: Namen und GUIDs anderer Spieler und
    ihrer Begleiter, Charakter-, Gilden- und Realm-Namen, Chat- und Brieftexte, volle Links, Antworten fremder Addons.

    Ablage: das Träger-Addon ezWorld mit der SavedVariable ezWorldDB (Frage F3 „Zwei Ordner“); ezCoreDB bleibt für
    Zustand, Tagebücher und Einstellungen. Fehlt der Träger (Ordner fehlt, abgeschaltet, keine Verknüpfung), arbeitet
    die Datenbank nur im Arbeitsspeicher und sagt das in /ez status – sie weicht nie von selbst in ezCoreDB aus.

      ezWorldDB = { meta = { schema, id (Zufallszahl), project, created, updated, tables = { [name] = { v, rows } },
                             jobs, marks, skipped = { secret, nokey, notready }, builds = { lo, hi },
                             mapYards = { [uiMapID] = { breite, höhe } } (Welle 23c, DB.NoteMapSize) },
                    cache = { … }, held = { … }, seen = { … }, text = { [Sprache] = { [Art] = { [id] = Name } } } }

    Vertrag „bereit“: Vor DB_READY liefern Lesende nil mit info.reason = "notready"; Schreibende stauen in einer
    gedeckelten Warteschlange (DB.QUEUE_MAX), die bei DB_READY eingespielt wird. Im Kampf wird ebenso gestaut und
    nach PLAYER_REGEN_ENABLED übernommen.

    Anmelden und Lesen (Rückgaben sind Kopien):
      DB.Define(name, spec)          Tabelle anmelden: life ("cache" | "held" | "seen"), v (Version), depth (Zahl der
                                     Schlüssel-Ebenen oder fn(erster Schlüssel)), merge = { feld = Regel }, list
                                     (Tabelle aus Listen: { match, cap, shrink }), bytes (geschätzt je Satz), explorer.
                                     Feldnamen in merge müssen im Feldverzeichnis DB.FIELDS stehen.
      DB.Get(name, k1, k2 …)         → Kopie, info = { src, label, t, b, cnt, partial, stale } oder nil, { reason }
      DB.KeysOf(name, k1 …)          → sortierte Schlüssel einer Ebene
      DB.Client("item", id)          → Antwort des Clients (durchgeschrieben in cache.item, höchstens einmal je
                                       Sitzung und ID), sonst der gespeicherte Satz mit „Client, Stand Build x“ – nur,
                                       wenn der Gegenstand auf diesem Realm enthüllt ist (Schutz der Verschleierung)
      DB.Text(art, id, sprache)      → Name ohne Auflöser im Client, Sprache (fehlt die laufende: eine andere)
      DB.NoteItemName(name, itemID), DB.ItemByName(name) → Index Name » itemID je Sprache (text[Sprache].itemByName,
                                       Entwurf 1.7; Deckel LIMITS.NAME_INDEX_MAX)
      DB.Stats(), DB.Ready(), DB.Persistent(), DB.Measure(tabelle)

    Schreiben (nur Sammler in ezCore; Module später über angemeldete Wege):
      DB.Put(name, key, felder, ctx)      Client-Antwort: neuester Stand gewinnt
      DB.Observe(name, key, felder, ctx)  Beobachtung: zählen und zusammenführen (Regeln je Feld, DB.RULES)
      DB.Adopt(name, key, felder, ctx)    Übernahme aus einem Altspeicher: füllt nur, was fehlt (Neues gewinnt)
      DB.SetText(art, id, name)
      key: ein Schlüssel oder eine Liste { k1, k2 … }; ctx = { t, b, pt } (Zeitpunkt, Build, Bits der Teilansicht)
      Jeder Wert geht einzeln durch Core.IsSecret: Gesperrtes wird ausgelassen (Bit 4 in pt), ein gesperrter Schlüssel
      legt keinen Satz an (meta.skipped zählt). Felder außerhalb des Verzeichnisses und Antworten fremder Addons
      (DB.MarkForeign) werden abgewiesen. Stempel je Satz: t0, t (Serverzeit), b (Build), b0 (erster Build, DB-N1).
      DB.Forget(name, k1 …), DB.Prune(opts), DB.Reset(was)   nur über sichtbare Knöpfe mit Rückfrage
      DB.ForgetMany(name, { { k1 … } … }) dasselbe für viele Pfade mit einer Zählung am Ende (→ Anzahl, { [i] = true })
      DB.Index(name, index, wert)         Umkehr-Index im Arbeitsspeicher (spec.index): Liste der Schlüssel-Pfade,
                                          deren Satz den Wert nennt (Händler » Ware, Zutat » Rezepte); erst bei der
                                          ersten Frage gebaut, nie gespeichert, neue Sätze trägt der Dienst nach
      DB.Resolve(raum, notschlüssel, id)  Notschlüssel über alle Tabellen und Verweise des Raums auflösen: eindeutige
                                          Räume überführen (zusammenführen), mehrdeutige (npc, obj) nur verknüpfen (to)
      DB.Job(name, spec), DB.RunJobs()    großer Schritt in Scheiben (Entwurf, Abschnitt 5, Regel 10): sortierte
                                          Schlüsselliste, Merker = letzter erledigter Schlüssel, Ziel im Schatten,
                                          Nachzieh-Menge, Tausch in einem Bild außerhalb des Kampfes
      Versionen je Tabelle: spec.v und spec.steps = { [v] = fn(satz, schlüssel) } – kleine Tabellen synchron, große
      als Auftrag; erst der Tausch hebt die Version.
    Deckel und Schwellen: alle an einer Stelle, DB.LIMITS (Startwerte des Entwurfs, Abschnitt 10; sie gelten – die
    Messung der Sonderprobe X1 wurde am 19.11.2026 abgebrochen).
    Nachrichten: DB_READY (gespeichert ja/nein), DB_CHANGED (name; gesammelt je Bild), DB_JOB_PROGRESS (auftrag,
    fertig, gesamt), DB_JOB_DONE (auftrag, n, offen), DB_RESOLVED (raum, notschlüssel, id), DB_LIMIT (träger, byte),
    DB_CARRIER_LOST (träger).
]]

Core.DB = Core.DB or {}
local DB = Core.DB
local Keys = DB.Keys
local IsSecret, Num, Plain = Core.IsSecret, Core.Num, Core.Plain

DB.SCHEMA = 1
-- Träger » Addon (die SavedVariable heißt <Addon>DB) – die einzige Stelle, die sagt, welcher Träger welche Ablage hat:
-- world trägt Weltwissen (meta, cache, held, seen, text), market die Preise (DBMarket.lua).
DB.CARRIERS = { world = "ezWorld", market = "ezMarket" }

-- Alle Deckel und Schwellen der Datenbank und der Preis-Schicht (Entwurf, Abschnitt 10, Frage S2: vorsichtige
-- Startwerte; sie gelten, seit die Sonderprobe X1 am 19.11.2026 abgebrochen wurde – geändert wird nur hier).
DB.LIMITS = {
    QUEUE_MAX = 500,          -- Warteschlange vor DB_READY und im Kampf (Überlauf zählt meta.skipped.notready)
    CACHE_MAX = 10000,        -- Schicht „cache“: Sätze je Tabelle, Ältestes zuerst
    TEXT_MAX = 100,           -- Zeichen je gehaltenem Namen
    NAME_INDEX_MAX = 20000,   -- text[Sprache].itemByName (abgeleitet, kürzbar; reserviert)
    NODE_YARDS = 12,          -- SAM-02: Fundorte derselben Objekt-ID im Umkreis (Yards, über C_Map.GetMapWorldSize) sind einer
    VISIT_SECONDS = 300,      -- SAM-01: so lange zählt weitere Beute aus derselben Objekt-GUID zum Ertrag, nicht als Ernte
    PRUNE_DAYS = 180,         -- „Lange nicht Gesehenes entfernen“: Vorgabe in Tagen
    WARN_BYTES = 8 * 1024 * 1024,   -- Warnschwelle für ezWorldDB (geschätzt): DB_LIMIT, gesammelt wird weiter
    SIGHTINGS = 8,            -- Sichtungen je seltenem Gegner (Ring, die älteste weicht)
    OFFER_AT = 8,             -- Lehrer je Angebot (offer.at, die älteste Zuordnung weicht)
    SPOT = { object = 200, npc = 12, entrance = 8, book = 8, vignette = 12, fishing = 100 },   -- Orte je Karte und Ding
    SPOT_OTHER = 50,          -- Orte je Karte und Ding für Arten ohne eigenen Wert
    ROUTE_WAYS = 8,           -- Wege je Start und Ziel (der älteste weicht)
    UNKNOWN_ITEMS = 200,      -- Beute-Art unknown: Gegenstände je Karte und Gebiet, darüber der Sammelposten rest
    SESSION_MAX = 5000,       -- Merker „schon gezählt“ je Sitzung
    SYNC_ROWS = 2000,         -- Versionsschritt bis zu so vielen Sätzen synchron, darüber als Auftrag
    SLICE_MS = 2,             -- Scheibe eines Auftrags je Bild
    SLICE_ROWS = 200,         -- … bzw. Schlüssel je Scheibe ohne Uhr
    PRICE_DAYS = 14,          -- Preisverlauf in Kalendertagen …
    PRICE_WATCH_DAYS = 30,    -- … und für beobachtete Gegenstände
    PRICE_POINTS = 31,        -- Sicherung: Tage je Gegenstand
    PRICE_AGE_DAYS = 30,      -- Preis-Satz entfällt nach so vielen Tagen ungesehen
    PRICE_VARIANTS = 12,      -- Abwandlungen je Gegenstand
    PRICE_LOG_DAYS = 35,      -- Protokoll der Erfassungen in Tagen (nach Tagen gedeckelt, nicht nach Zahl) …
    PRICE_LOG_MAX = 2500,     -- … mit einer Sicherung je Bereich (35 Tage × 24 Stunden × 3 Arten)
}
local LIMITS = DB.LIMITS
-- Ältere Namen derselben Werte (gelesen wird DB.LIMITS)
DB.QUEUE_MAX, DB.CACHE_MAX, DB.TEXT_MAX, DB.PRUNE_DAYS = LIMITS.QUEUE_MAX, LIMITS.CACHE_MAX, LIMITS.TEXT_MAX, LIMITS.PRUNE_DAYS
DB.LIVES = { "cache", "held", "seen" }
local LIFE = { cache = true, held = true, seen = true }

-- Feldverzeichnis: ein Name, eine Bedeutung über alle Tabellen (Entwurf, „Feldverzeichnis“; b0 und svc neu).
DB.FIELDS = {
    t0 = "zuerst gesehen", t = "zuletzt gesehen", tf = "zuletzt vollständig gesehen", b = "Build beim letzten Schreiben",
    b0 = "erster Build (DB-N1)", pt = "Teilansicht (Bits)", src = "Herkunft", to = "Kandidaten eines Notschlüssels",
    cnt = "Zahl der Vorgänge", sum = "Summe", lo = "kleinster Wert", hi = "größter Wert", empty = "Vorgänge ohne Beute",
    deaths = "gesehene Tode", party = "Vorgänge mit Gruppenbeute", money = "Geld { sum, cnt }", items = "itemID » Satz",
    tokens = "currencyID » { f, s }", rest = "Sammelposten", f = "Funde", s = "Summe der Menge", var = "Abwandlungen",
    diff = "je difficultyID", old = "Altbestand", item = "itemID", cur = "currencyID", spell = "spellID", npc = "npcID",
    obj = "objectID", quest = "questID", map = "Speicherkarte", inst = "instanceID", line = "skillLineID",
    vig = "vignetteID", qty = "Menge", pr = "Preis in Kupfer", tp = "Trainingspunkte", q = "Qualität", il = "Itemlevel",
    ml = "Mindeststufe", cl = "Klasse", sc = "Unterklasse", eq = "Platz", st = "Stapelgröße", sp = "Verkaufswert",
    bd = "Bindung", ex = "Erweiterung", set = "Set", fam = "Taschen-Familie", uq = "einzigartig", req = "Anforderungen",
    fx = "Effekte", base = "Grundzauber", rank = "Rang", lvl = "Stufe", cls = "Klasse (classID)", pas = "passiv",
    cost = "Kraftkosten", cat = "Kategorie", durBase = "Grunddauer", ranks = "Rang » spellID", parent = "Elternkarte",
    mapType = "Kartentyp", art = "uiMapArtID", cMin = "Stufe von laut Client", cMax = "Stufe bis laut Client",
    pk = "Berufs-Kürzel", lineSub = "Kind-Linie", out = "Produkt", qMin = "Ausbeute von", qMax = "Ausbeute bis",
    triv = "Schwelle grau", rg = "Zutaten", alt = "Ersatz-Zutaten", tools = "Werkzeuge", prev = "Vorgänger",
    next = "Nachfolger", cd = "Abklingzeit", hash = "Prüfwert", nodes = "Knoten", x = "Lage x", y = "Lage y",
    max = "höchster Rang", edges = "Kanten", entries = "Einträge", xy = "Position xi*10000+yi", via = "Messart",
    area = "areaID", dn = "Tag oder Nacht", side = "Fraktionsseite", re = "Reaktion je Seite", as = "gesehen als",
    rep = "Rufstufe", lvls = "Stufen { lo, hi }", tier = "Einstufung", ct = "Kreaturentyp", roles = "Rollen » zuletzt",
    tr = "Lehrer-Art (1 Klasse, 2 Beruf, 3 sonstige)", tk = "Verweis auf das Angebot", skin = "kürschnerbar",
    kind = "Unterart eines Objekts", skill = "Fertigkeitswert", w = "Waren je itemID", wcur = "Waren je currencyID",
    per = "Stück je Kauf", lim = "begrenzter Vorrat", ext = "Zusatzkosten", ic = "Symbol", at = "wo angeboten",
    svc = "Angebote eines Lehrers", hops = "Zwischenhalte", sec = "Flugdauer", raid = "Schlachtzug",
    sight = "Sichtungen", dead = "tot gesehen", vigType = "Art der Vignette", how = "Art der Enthüllung",
    realms = "je Realm-Laufnummer", hist = "Stufe » Anzahl", stages = "Farbgrenzen", yield = "Ausbeute",
    from = "Quelle als Verweis", dur = "gemessene Dauer", cast = "Zauberzeit", use = "Verwendungsart",
    stancePages = "Leistenseite je Haltung", sfx = "Zufallssuffix", bon = "Bonus-IDs", linkLvl = "Link-Stufe",
    stats = "Werte",
    -- Preis-Schicht (DBMarket.lua, Träger ezMarket)
    mv = "Marktwert", auc = "Zahl der Auktionen", scan = "Art der Erfassung als Bit-Summe (1 Komplett-Scan, 2 Suche, 4 Übersicht, 8 Kategorie, 16 Sammelabfrage)",
    fk = "Art der letzten vollständigen Erfassung als Bit (1 Komplett-Scan, 2 Suche)",
    keep = "Länge des Verlaufs in Tagen", days = "Verlaufs-Reihe (Spalten hcols)", scanAt = "letzter Komplett-Scan",
    hcols = "Spalten der Verlaufs-Reihe", log = "Protokoll der Erfassungen", rules = "Regeln des Hauses", wd = "Wochentag",
    rows = "Zahl der Zeilen bzw. Sätze", pot = "Topf (gemeinsames Auktionshaus)", realm = "Realm-Laufnummer",
    core = "Realm-Laufnummer in ezCoreDB.realms (Realm ohne Kennung des Clients)", native = "GetNativeRealmID", id = "Kennung",
    day = "Tag in Serverzeit (Tage seit 1970)", hr = "Stunde in Serverzeit", areas = "Preis-Bereiche (Realm + Seite)",
}

-- Regeln beim Zusammenführen (Vorgabe für alle Tabellen; eine Tabelle kann in spec.merge abweichen)
DB.RULES = { cnt = "sum", f = "sum", s = "sum", sum = "sum", empty = "sum", deaths = "sum", party = "sum",
    lo = "min", t0 = "min", b0 = "min", hi = "max", t = "max", tf = "max", sight = "ring" }
local RULE_OK = { sum = true, min = true, max = true, first = true, newest = true, ring = true }
local RING = LIMITS.SIGHTINGS

local specs, order = {}, {}
local root, persistent, frozen, ready = nil, false, nil, false
local readonly = {}
local queue = {}
local early = { secret = 0, nokey = 0, notready = 0 }   -- ausgelassen, bevor ein Träger da war
local foreign = setmetatable({}, { __mode = "k" })
local changed, flushing = {}, false
local EMPTY = {}

local function G(name) return rawget(_G, name) end

-- Bit-Summe ohne Bibliothek (WoW hat bit, die Tests nicht immer)
local function BOr(a, b)
    local lib = G("bit")
    if type(lib) == "table" and lib.bor then return lib.bor(a, b) end
    local r, v = 0, 1
    while a > 0 or b > 0 do
        local x, y = a % 2, b % 2
        if x == 1 or y == 1 then r = r + v end
        a, b, v = (a - x) / 2, (b - y) / 2, v * 2
    end
    return r
end
DB.BOr = BOr
local function BHas(a, bitValue) return math.floor((Num(a) or 0) / bitValue) % 2 == 1 end
DB.BHas = BHas

-- Stempel der Serveruhr: eine Abfrage für ganz ezCore (Core.Time.Now("server"), Kern/Util.lua – ohne GetServerTime die
-- PC-Uhr); hier nur weitergeleitet (Gesamtreview 18.11.2026, Gegenprüfung zur Zeitbasis: vorher eine zweite Kopie).
local function Stamp()
    return Core.Time.Now("server")
end
DB.Stamp = Stamp

local function InCombat() return Core.InCombat and Core.InCombat() == true end

local lost = {}   -- Träger verloren (SAVED_VARIABLES_TOO_LARGE; DB.CarrierLost, unten)
local own = 0     -- > 0: eine eigene Funktion schreibt (DB.AsOwn)
function DB.Collecting()
    return (own > 0 or Core.OwnSetting("discovery", "dataCollect") ~= false) and not lost.world
end

-- Eigene Funktionen, die es schon vor der Datenbank gab (Npcs.Learn, Spells.ScanTrainer, NoteAura, Rezepte, Händler
-- mit Rohstoffen): nach dem Umzug schreiben sie über die Datenbank und dürfen das auch bei ausgeschaltetem Schalter
-- „Datenbank: Erlebtes sammeln“ – sonst ginge, was sie früher in ezCoreDB merkten, still verloren. Der Schalter gilt
-- nur für die Entdecker-Sammler. Ein verlorener Träger bleibt zu. → Rückgaben von fn (höchstens zwei)
function DB.AsOwn(fn, ...)
    own = own + 1
    local ok, a, b = pcall(fn, ...)
    own = own - 1
    if not ok then error(a, 0) end
    return a, b
end

function DB.Explorer()
    return Core.OwnSetting("discovery", "explorer") == true
end
Core.OwnDefaults("discovery", { dataCollect = true, explorer = false })

---------------------------------------------------------------------------
-- Kopien und das Tor für gesperrte Werte
---------------------------------------------------------------------------

-- Tiefe Kopie über Core.CopyTable (Gesamtreview 18.11.2026, T16-7): wie bisher fällt ab Tiefe 12 alles weg (nil), dazu
-- übersteht sie jetzt Zyklen. Der Name DB.Copy bleibt.
local COPY_DEPTH = 12
local function Copy(v) return Core.CopyTable(v, COPY_DEPTH) end
DB.Copy = Copy

-- Kopie ohne gesperrte Werte, Funktionen und Rahmen. → Kopie, ob etwas ausgelassen wurde
local function Clean(v, depth)
    if IsSecret(v) then return nil, true end
    local tv = type(v)
    if tv == "number" then
        if v ~= v then return nil, false end
        return v, false
    end
    if tv == "string" or tv == "boolean" then return v, false end
    if tv ~= "table" or depth > 8 then return nil, false end
    local secretTable = G("issecrettable")
    if type(secretTable) == "function" then
        local ok, yes = pcall(secretTable, v)
        if ok and yes == true then return nil, true end
    end
    if type(rawget(v, 0)) == "userdata" then return nil, false end   -- Rahmen und Regionen
    local out, any = {}, false
    for k, x in pairs(v) do
        if IsSecret(k) then
            any = true
        elseif type(k) == "number" or type(k) == "string" then
            local c, s = Clean(x, depth + 1)
            if s then any = true end
            if c ~= nil then out[k] = c end
        end
    end
    return out, any
end

local function IsForeign(t, depth)
    if type(t) ~= "table" then return false end
    if foreign[t] then return true end
    if (depth or 0) > 4 then return false end
    for _, v in pairs(t) do
        if type(v) == "table" and IsForeign(v, (depth or 0) + 1) then return true end
    end
    return false
end

-- Antworten fremder Addons tragen diese Marke (Sources.lua); DB.Put und DB.Observe weisen sie ab (Leitlinie 10).
function DB.MarkForeign(t, from)
    if type(t) == "table" then foreign[t] = from or true end
    return t
end

---------------------------------------------------------------------------
-- Kopf und Tabellen
---------------------------------------------------------------------------

local function Skip(reason)
    local m = root and root.meta
    local s = m and m.skipped or early
    s[reason] = (Num(s[reason]) or 0) + 1
end

local function InitMeta(t)
    local m = type(t.meta) == "table" and t.meta or nil
    if not m then
        m = { schema = DB.SCHEMA, id = math.random(1, 2147483646), created = Stamp() }
        t.meta = m
    end
    m.tables = type(m.tables) == "table" and m.tables or {}
    m.jobs = type(m.jobs) == "table" and m.jobs or {}
    m.marks = type(m.marks) == "table" and m.marks or {}
    m.skipped = type(m.skipped) == "table" and m.skipped or {}
    m.builds = type(m.builds) == "table" and m.builds or {}
    for k, v in pairs(early) do m.skipped[k] = (Num(m.skipped[k]) or 0) + v; early[k] = 0 end
    local project = Num(G("WOW_PROJECT_ID"))
    if m.project == nil then m.project = project end
    if (Num(m.schema) or 0) > DB.SCHEMA then
        frozen = "newer"
    elseif project and Num(m.project) and m.project ~= project then
        frozen = "project"
    end
    return m
end

local function Depth(spec, first)
    local d = spec.depth
    if type(d) == "function" then return Num(d(first)) or 1 end
    return Num(d) or 1
end

local function Tbl(name, create)
    local spec = specs[name]
    if not (spec and root) then return nil, spec end
    local layer = root[spec.life]
    if type(layer) ~= "table" then
        if not create then return nil, spec end
        layer = {}
        root[spec.life] = layer
    end
    local t = layer[name]
    if type(t) ~= "table" then
        if not create then return nil, spec end
        t = {}
        layer[name] = t
    end
    return t, spec
end

-- Alle Sätze einer Tabelle: fn(satz, eltern, schlüssel, schlüsselliste). Erst gesammelt, dann gerufen (darf löschen).
local function EachRow(name, fn)
    local tbl, spec = Tbl(name, false)
    if not tbl then return end
    local found = {}
    local function Rec(t, level, maxLevel, path)
        for k, v in pairs(t) do
            if type(v) == "table" then
                local p = {}
                for i = 1, #path do p[i] = path[i] end
                p[#p + 1] = k
                local ml = maxLevel or Depth(spec, k)
                if level >= ml then found[#found + 1] = { v, t, k, p } else Rec(v, level + 1, ml, p) end
            end
        end
    end
    Rec(tbl, 1, nil, {})
    for _, e in ipairs(found) do fn(e[1], e[2], e[3], e[4]) end
end
DB.Scan = EachRow   -- nur ezCore-intern (Fassaden, Übernahme): die Sätze nie verändern

-- Zuhörer für geschriebene Sätze einer Tabelle (nur ezCore-intern; Gesamtreview 18.11.2026, T8-2): fn(keys) nach jedem
-- Schreiben über Put/Observe/Adopt (auch nachgeholt aus der Warteschlange), damit ein abgeleiteter Index (Drops.SourcesOf)
-- nur den einen Satz nachträgt, statt alles neu zu bauen. keys ist eine Kopie. Ein Fehler im Zuhörer bleibt still in
-- der Fehlerliste. → true
local applyHooks = {}
function DB.OnApply(name, fn)
    if type(name) ~= "string" or type(fn) ~= "function" then return false end
    applyHooks[name] = applyHooks[name] or {}
    table.insert(applyHooks[name], fn)
    return true
end
local function RunApplyHooks(name, keys)
    local list = applyHooks[name]
    if not list then return end
    for _, fn in ipairs(list) do
        local copy = {}
        for i, k in ipairs(keys) do copy[i] = k end
        Core.Try("ezCore", "DB.OnApply " .. name, fn, copy)
    end
end

local function Recount(name)
    local n = 0
    EachRow(name, function() n = n + 1 end)
    local m = root and root.meta
    if m and m.tables[name] then m.tables[name].rows = n end
    return n
end

local RunSteps   -- Versionsschritte einer Tabelle (unten, bei den Aufträgen)

local function EnsureTable(name)
    local spec = specs[name]
    local _ = Tbl(name, true)
    local m = root.meta
    local entry = type(m.tables[name]) == "table" and m.tables[name] or nil
    if not entry then
        entry = { v = spec.v, rows = 0 }
        m.tables[name] = entry
        Recount(name)
    end
    local v = Num(entry.v) or 1
    if v > spec.v then
        readonly[name] = "newer"     -- neuerer Speicher als das Addon: für die Sitzung nur lesen (Regel 8)
    elseif v < spec.v then
        RunSteps(name, spec, entry)  -- erst der letzte Schritt (bzw. der Tausch eines Auftrags) hebt entry.v
    end
end

local versions = {}
-- Zähler der Änderungen je Tabelle (sofort, nicht erst im nächsten Bild): Zwischenspeicher der Fassaden prüfen ihn.
function DB.Version(name) return versions[name] or 0 end

local indexes = {}       -- [Tabelle] = { [Index] = { by = { [Wert] = { [Pfad-Text] = Pfad } }, of = { [Pfad-Text] = Werte } } }
local Reindex, MarkDirty -- Umkehr-Index nachtragen, Nachzieh-Menge laufender Aufträge (unten)

-- Geschätzte Größe des Weltwissens aus den mitlaufenden Zählern (kein Durchlauf) – für DB_LIMIT und /ez status.
local function EstimatedBytes()
    local m, bytes = root and root.meta, 0
    if not m then return 0 end
    for _, name in ipairs(order) do
        bytes = bytes + (Num(m.tables[name] and m.tables[name].rows) or 0) * specs[name].bytes
    end
    return bytes
end
DB.EstimatedBytes = EstimatedBytes

-- Warnschwelle (Entwurf, Abschnitt 10, Frage S2): einmal je Sitzung DB_LIMIT mit dem Angebot zum Aufräumen;
-- gesammelt wird weiter, gesperrt wird nichts.
local limitWarned = false
local function CheckLimit()
    if limitWarned or not (ready and persistent) then return end
    local bytes = EstimatedBytes()
    if bytes >= LIMITS.WARN_BYTES then
        limitWarned = true
        Core.Fire("DB_LIMIT", DB.CARRIERS.world, bytes)
    end
end
DB.CheckLimit = CheckLimit

local function Changed(name)
    versions[name] = (versions[name] or 0) + 1
    changed[name] = true
    if flushing then return end
    flushing = true
    local function Flush()
        flushing = false
        local names = Core.SortedKeys(changed)
        changed = {}
        for _, n in ipairs(names) do Core.Fire("DB_CHANGED", n) end
        CheckLimit()
    end
    local timer = G("C_Timer")
    if type(timer) == "table" and timer.After then timer.After(0, Flush) else Flush() end
end

local function Touch(name, now, build)
    local m = root.meta
    m.updated = now
    if build and build > 0 then
        m.builds.lo = math.min(Num(m.builds.lo) or build, build)
        m.builds.hi = math.max(Num(m.builds.hi) or build, build)
    end
    Changed(name)
end

local function Row(name, keys, create)
    local t, spec = Tbl(name, create)
    if not t then return nil end
    for i = 1, #keys - 1 do
        local sub = t[keys[i]]
        if type(sub) ~= "table" then
            if not create then return nil end
            sub = {}
            t[keys[i]] = sub
        end
        t = sub
    end
    local last = keys[#keys]
    local row = t[last]
    local new = false
    if type(row) ~= "table" then
        if not create then return nil end
        row = {}
        t[last] = row
        new = true
    end
    return row, new, t, last, spec
end

---------------------------------------------------------------------------
-- Zusammenführen
---------------------------------------------------------------------------

local function MergeInto(dst, src, rules, inherited)
    for k, v in pairs(src) do
        local rule = inherited or rules[k] or DB.RULES[k]
        local old = dst[k]
        if rule == "first" and old ~= nil then
            -- der erste Wert bleibt
        elseif rule == "ring" and type(v) == "table" then
            local list = type(old) == "table" and old or {}
            for _, e in ipairs(v) do list[#list + 1] = e end
            while #list > RING do table.remove(list, 1) end
            dst[k] = list
        elseif type(v) == "table" then
            if type(old) == "table" then
                local pass = (rule == "sum" or rule == "min" or rule == "max") and rule or nil
                MergeInto(old, v, rules, pass)
            else
                dst[k] = v
            end
        elseif type(v) == "number" and type(old) == "number" then
            if rule == "sum" then dst[k] = old + v
            elseif rule == "min" then dst[k] = math.min(old, v)
            elseif rule == "max" then dst[k] = math.max(old, v)
            else dst[k] = v end
        else
            dst[k] = v
        end
    end
end
DB.MergeInto = MergeInto

-- Übernahme: Bekanntes gewinnt, nur Fehlendes wird ergänzt (Entwurf, Abschnitt 6, Schritt 4).
local function MergeUnder(dst, src)
    for k, v in pairs(src) do
        local old = dst[k]
        if old == nil then
            dst[k] = v
        elseif type(old) == "table" and type(v) == "table" then
            MergeUnder(old, v)
        end
    end
end

---------------------------------------------------------------------------
-- Schreiben
---------------------------------------------------------------------------

local function Stamps(row, spec, mode, now, build, ctx)
    if mode == "under" then
        local b = ctx and Num(ctx.b) or 0
        row.b = row.b or b
        if spec.life == "seen" then row.b0 = row.b0 or b end
    else
        row.b = build
        if spec.life == "seen" then row.b0 = row.b0 or build end
    end
    row.t = math.max(Num(row.t) or now, now)
    row.t0 = math.min(Num(row.t0) or now, now)
end

local function TrimCache(name)
    local m = root.meta.tables[name]
    if not m or (Num(m.rows) or 0) <= LIMITS.CACHE_MAX then return end
    local all = {}
    EachRow(name, function(row, parent, key) all[#all + 1] = { Num(row.t) or 0, parent, key } end)
    table.sort(all, function(a, b) return a[1] < b[1] end)
    local cut = #all - math.floor(LIMITS.CACHE_MAX * 0.9)
    for i = 1, math.max(0, cut) do all[i][2][all[i][3]] = nil end
    Recount(name)
end

local function ApplyList(name, keys, item, ctx, now, build)
    local holder, new, _, _, spec = Row(name, keys, true)
    local opts = spec.list
    for _, el in ipairs(holder) do
        if type(el) == "table" and opts.match(el, item, keys) then
            MergeInto(el, item, spec.merge or EMPTY)
            el.t = math.max(Num(el.t) or now, now)
            el.b = build
            return true, new
        end
    end
    item.t = Num(item.t) or now
    item.b = build
    holder[#holder + 1] = item
    local cap = type(opts.cap) == "function" and opts.cap(keys) or opts.cap
    if cap and #holder > cap and opts.shrink then opts.shrink(holder, keys) end
    return true, new
end

local function Apply(mode, name, keys, clean, ctx, secret)
    local spec = specs[name]
    if frozen or readonly[name] then return nil, "readonly" end
    local now = ctx and Num(ctx.t) or Stamp()
    local build = Keys.Build()
    local ok, new
    if spec.list then
        local pt = ctx and Num(ctx.pt) or 0
        if secret then pt = BOr(pt, 4) end
        if pt > 0 then clean.pt = BOr(Num(clean.pt) or 0, pt) end
        ok, new = ApplyList(name, keys, clean, ctx, now, build)
    else
        local row
        row, new = Row(name, keys, true)
        if mode == "put" then
            for k, v in pairs(clean) do row[k] = v end
        elseif mode == "under" then
            MergeUnder(row, clean)
        else
            MergeInto(row, clean, spec.merge or EMPTY)
        end
        Stamps(row, spec, mode, now, build, ctx)
        local pt = ctx and Num(ctx.pt) or 0
        if secret then pt = BOr(pt, 4) end
        if pt > 0 then row.pt = BOr(Num(row.pt) or 0, pt) end
        ok = true
    end
    -- Deckel innerhalb eines Satzes (offer.at, Sammelposten der Art unknown): spec.trim aus der Anmeldung
    if spec.trim then
        local row = Row(name, keys, false)
        if row then spec.trim(row, keys) end
    end
    if new then
        local entry = root.meta.tables[name]
        entry.rows = (Num(entry.rows) or 0) + 1
        if spec.life == "cache" then TrimCache(name) end
    end
    Reindex(name, keys)
    MarkDirty(name, keys)
    RunApplyHooks(name, keys)
    Touch(name, now, build)
    return ok
end

local function ValidKey(k)
    if IsSecret(k) then return false, "secret" end
    if type(k) == "number" then return k == k end
    if type(k) == "string" then return k ~= "" end
    return false, "nokey"
end

local function Write(mode, name, key, fields, ctx)
    local spec = specs[name]
    if not spec then return nil, "unknown" end
    if type(fields) ~= "table" or IsSecret(fields) then return nil, "fields" end
    if IsForeign(fields) then return nil, "foreign" end
    if not DB.Collecting() then return nil, "off" end
    local keys = type(key) == "table" and key or { key }
    if #keys == 0 then Skip("nokey") return nil, "nokey" end
    local list = {}
    for i = 1, #keys do
        local ok, why = ValidKey(keys[i])
        if not ok then
            Skip(why or "nokey")
            return nil, why or "nokey"
        end
        list[i] = keys[i]
    end
    for k in pairs(fields) do
        if type(k) ~= "string" or not DB.FIELDS[k] then return nil, "field" end
    end
    local clean, secret = Clean(fields, 0)
    if not ready or InCombat() then
        if #queue >= LIMITS.QUEUE_MAX then
            Skip("notready")
            return nil, "full"
        end
        queue[#queue + 1] = { mode, name, list, clean, ctx and Copy(ctx), secret }
        return true, "queued"
    end
    return Apply(mode, name, list, clean, ctx, secret)
end

function DB.Put(name, key, fields, ctx) return Write("put", name, key, fields, ctx) end
function DB.Observe(name, key, fields, ctx) return Write("observe", name, key, fields, ctx) end
function DB.Adopt(name, key, fields, ctx) return Write("under", name, key, fields, ctx) end

local function Replay()
    if not ready or InCombat() then return end
    local q = queue
    queue = {}
    for _, e in ipairs(q) do
        if e[1] == "text" then
            DB.SetText(e[2], e[3], e[4], e[5])
        else
            Apply(e[1], e[2], e[3], e[4], e[5], e[6])
        end
    end
end

---------------------------------------------------------------------------
-- Texte ohne Auflöser im Client (Entwurf 1.7: gehalten, nie automatisch gekürzt)
---------------------------------------------------------------------------

-- instance (Welle 23c, A39): Name einer Instanz je Sprache, Schlüssel instanceID (Discovery.NoteInstanceName)
DB.TEXT_KINDS = { npc = true, npcTitle = true, obj = true, vig = true, recipe = true, taxi = true, tool = true,
    where = true, recipeSrc = true, instance = true }

function DB.SetText(kind, id, text, locale)
    if not DB.TEXT_KINDS[kind] or not ValidKey(id) or not DB.Collecting() then return false end
    text = Plain(text)
    if type(text) ~= "string" or text == "" then return false end
    text = text:gsub("|", ""):sub(1, LIMITS.TEXT_MAX)
    locale = locale or Keys.Locale()
    if not ready or InCombat() then
        if #queue >= LIMITS.QUEUE_MAX then return false end
        queue[#queue + 1] = { "text", kind, id, text, locale }
        return true
    end
    if frozen then return false end
    root.text = type(root.text) == "table" and root.text or {}
    local byLoc = root.text[locale] or {}
    root.text[locale] = byLoc
    byLoc[kind] = byLoc[kind] or {}
    if byLoc[kind][id] ~= text then
        byLoc[kind][id] = text
        Changed("text")
    end
    return true
end

function DB.Text(kind, id, locale)
    if not (ready and type(root.text) == "table") or not ValidKey(id) then return nil end
    locale = locale or Keys.Locale()
    local own = root.text[locale] and root.text[locale][kind]
    if own and own[id] then return own[id], locale end
    for loc, byLoc in pairs(root.text) do
        if type(byLoc) == "table" and type(byLoc[kind]) == "table" and byLoc[kind][id] then return byLoc[kind][id], loc end
    end
    return nil
end

-- Entwurf 1.7: text[Sprache].itemByName[name klein] = itemID – die eine benannte Ausnahme (abgeleitet, gespeichert,
-- je Sprache getrennt), weil der Client keinen Weg vom Namen zur Nummer hat (Knowledge.ItemIDByName). Harter Deckel
-- LIMITS.NAME_INDEX_MAX je Sprache; darüber fällt ein Zehntel weg (Abweichung vom Entwurf: in der Reihenfolge der
-- Tabelle statt „Ältestes zuerst“ – ein Zeitstempel je Name verdoppelte den Platz, der Deckel wird kaum erreicht).
local nameCount = {}   -- [Sprache] = Zahl der Namen (im Arbeitsspeicher mitgezählt)

local function NameIndex(locale, create)
    if not (ready and type(root.text) == "table") then return nil end
    local byLoc = root.text[locale]
    if not byLoc then
        if not create then return nil end
        byLoc = {}
        root.text[locale] = byLoc
    end
    if type(byLoc.itemByName) ~= "table" then
        if not create then return nil end
        byLoc.itemByName = {}
    end
    return byLoc.itemByName
end

function DB.NoteItemName(name, itemID, locale)
    if IsSecret(name) or IsSecret(itemID) then return false end
    name, itemID = Plain(name), Num(itemID)
    if type(name) ~= "string" or name == "" or not itemID or itemID <= 0 or frozen then return false end
    locale = locale or Keys.Locale()
    local index = NameIndex(locale, true)
    if not index then return false end
    local key = name:lower():sub(1, LIMITS.TEXT_MAX)
    if index[key] == itemID then return true end
    if index[key] == nil then
        if not nameCount[locale] then
            local n = 0
            for _ in pairs(index) do n = n + 1 end
            nameCount[locale] = n
        end
        nameCount[locale] = nameCount[locale] + 1
        if nameCount[locale] > LIMITS.NAME_INDEX_MAX then
            local drop = math.max(1, math.floor(LIMITS.NAME_INDEX_MAX / 10))
            for k in pairs(index) do
                if drop <= 0 then break end
                index[k], drop = nil, drop - 1
                nameCount[locale] = nameCount[locale] - 1
            end
        end
    end
    index[key] = itemID
    Changed("text")
    return true
end

function DB.ItemByName(name, locale)
    if IsSecret(name) then return nil end
    name = Plain(name)
    if type(name) ~= "string" or name == "" then return nil end
    local index = NameIndex(locale or Keys.Locale(), false)
    local id = index and index[name:lower():sub(1, LIMITS.TEXT_MAX)]
    return Num(id)
end

---------------------------------------------------------------------------
-- Lesen
---------------------------------------------------------------------------

local function Info(spec, row)
    local own = spec.life == "seen"
    local b = Num(row.b)
    return { src = own and "own" or "client", label = own and L.DB_OWN or L.DB_CLIENT_BUILD:format(b or 0),
        t = Num(row.t), b = b, cnt = Num(row.cnt), partial = BHas(row.pt, 1) or BHas(row.pt, 2) or BHas(row.pt, 4),
        stale = not own and b ~= Keys.Build() or nil }
end
DB.InfoOf = function(name, row) return specs[name] and type(row) == "table" and Info(specs[name], row) or nil end

function DB.Get(name, ...)
    if not ready then return nil, { reason = "notready" } end
    if not specs[name] then return nil, { reason = "unknown" } end
    local keys = { ... }
    if #keys == 0 then return nil, { reason = "nokey" } end
    for i = 1, #keys do
        if not ValidKey(keys[i]) then return nil, { reason = "nokey" } end
    end
    local row = Row(name, keys, false)
    if not row then return nil, { reason = "none" } end
    return Copy(row), Info(specs[name], row)
end

function DB.KeysOf(name, ...)
    if not ready then return {} end
    local t = Tbl(name, false)
    for i = 1, select("#", ...) do
        if type(t) ~= "table" then return {} end
        t = t[select(i, ...)]
    end
    return type(t) == "table" and Core.SortedKeys(t) or {}
end

-- Gilt die Enthüllung eines Gegenstands auf dem laufenden Realm? (reveal ohne realms: überall)
function DB.Revealed(itemID)
    local row = ready and Row("reveal", { itemID }, false)
    if not row then return false end
    if type(row.realms) ~= "table" then return true end
    local realm = Keys.Realm()
    return realm ~= nil and row.realms[realm] ~= nil
end

local clientChecked = {}

local function ItemFacts(id)
    local api = G("C_Item")
    local fn = G("GetItemInfo") or (type(api) == "table" and api.GetItemInfo)
    if type(fn) ~= "function" then return nil end
    local ok, name, _, q, il, ml, _, _, st, _, _, sp, cl, sc, bd, ex, set = pcall(fn, id)
    if not ok or IsSecret(name) or type(name) ~= "string" or name == "" then return nil end
    local facts = { q = Num(q), il = Num(il), ml = Num(ml), st = Num(st), sp = Num(sp), cl = Num(cl), sc = Num(sc),
        bd = Num(bd), ex = Num(ex), set = Num(set) }
    local inv = type(api) == "table" and api.GetItemInventoryTypeByID
    if type(inv) == "function" then
        local okInv, eq = pcall(inv, id)
        if okInv then facts.eq = Num(eq) end
    end
    return facts
end

function DB.Client(kind, id)
    if kind ~= "item" then return nil, { reason = "kind" } end
    id = Num(id)
    if not id or id <= 0 then return nil, { reason = "nokey" } end
    local facts = ItemFacts(id)
    if facts then
        if ready and not clientChecked[id] and specs.item then
            clientChecked[id] = true
            local row = Row("item", { id }, false)
            local differs = not row or row.b ~= Keys.Build()
            if row and not differs then
                for k, v in pairs(facts) do if row[k] ~= v then differs = true break end end
            end
            if differs then DB.Put("item", id, facts) end
        end
        return facts, { src = "client", label = L.DB_CLIENT, b = Keys.Build() }
    end
    if not ready then return nil, { reason = "notready" } end
    local row = Row("item", { id }, false)
    if not row then return nil, { reason = "none" } end
    if not DB.Revealed(id) then return nil, { reason = "hidden" } end
    return Copy(row), Info(specs.item, row)
end

---------------------------------------------------------------------------
-- Vergessen, Aufräumen, Zurücksetzen (nur über sichtbare Knöpfe mit Rückfrage)
---------------------------------------------------------------------------

function DB.Forget(name, ...)
    -- readonly[name]: Tabelle aus einem neueren Speicher – für die Sitzung nur lesen (Regel 8), wie DB.Change
    if not ready or frozen or not specs[name] or readonly[name] then return 0 end
    local keys = { ... }
    if #keys == 0 then return 0 end
    local _, _, parent, last = Row(name, keys, false)
    if not parent or parent[last] == nil then return 0 end
    local before = Num(root.meta.tables[name].rows) or 0
    parent[last] = nil
    indexes[name] = nil
    local after = Recount(name)
    Changed(name)
    return math.max(1, before - after)
end

-- Viele Schlüssel-Pfade einer Tabelle auf einmal vergessen (Welle 15; Fund 8 der Gegenprüfung von Welle 14: „Art
-- löschen“ und „Zone löschen“ zählten je Stelle die ganze Tabelle neu). Eine Zählung (Recount) und eine Nachricht
-- DB_CHANGED am Ende. pfade = { { k1, k2 … } … } → Zahl entfernter Sätze (wie DB.Forget: je Pfad mindestens 1),
-- { [i] = true für jeden Pfad, den es gab }
function DB.ForgetMany(name, paths)
    if not ready or frozen or not specs[name] or readonly[name] or type(paths) ~= "table" then return 0, {} end
    local removed, hit = 0, {}
    local before = Num(root.meta.tables[name].rows) or 0
    for i, keys in ipairs(paths) do
        if type(keys) == "table" and #keys > 0 then
            local _, _, parent, last = Row(name, keys, false)
            if parent and parent[last] ~= nil then
                parent[last] = nil
                hit[i] = true
                removed = removed + 1
            end
        end
    end
    if removed == 0 then return 0, hit end
    indexes[name] = nil
    local after = Recount(name)
    Changed(name)
    return math.max(removed, before - after), hit
end

-- Einen Satz im Dienst ändern (nur ezCore-intern, für Weiterleitungen wie Npcs.Forget): fn(satz) darf Felder
-- entfernen; gibt fn "delete" zurück, fällt der Satz weg. → true, wenn es den Satz gab
function DB.Change(name, keys, fn)
    if not ready or frozen or not specs[name] or readonly[name] or type(keys) ~= "table" or type(fn) ~= "function" then
        return false
    end
    local row, _, parent, last = Row(name, keys, false)
    if not row then return false end
    if fn(row) == "delete" then
        parent[last] = nil
        Recount(name)
    end
    MarkDirty(name, keys)
    indexes[name] = nil
    Changed(name)
    return true
end

-- Lange nicht Gesehenes entfernen: Sätze (und Orte in Listen) mit t vor opts.before (Standard DB.PRUNE_DAYS Tage).
-- opts.dry = true: nur zählen (Vorschau für die Rückfrage). → Anzahl
function DB.Prune(opts)
    opts = type(opts) == "table" and opts or {}
    if not ready or (frozen and not opts.dry) then return 0 end
    local before = Num(opts.before) or (Stamp() - LIMITS.PRUNE_DAYS * 86400)
    local removed = 0
    for _, name in ipairs(order) do
        local spec = specs[name]
        if (spec.life == "seen" or spec.life == "cache") and (opts.only == nil or opts.only == name) and not readonly[name] then
            local hit = false
            EachRow(name, function(row, parent, key)
                if spec.list then
                    for i = #row, 1, -1 do
                        local el = row[i]
                        if type(el) == "table" and (Num(el.t) or 0) < before then
                            removed, hit = removed + 1, true
                            if not opts.dry then table.remove(row, i) end
                        end
                    end
                    if not opts.dry and #row == 0 then parent[key] = nil end
                elseif (Num(row.t) or 0) < before then
                    removed, hit = removed + 1, true
                    if not opts.dry then parent[key] = nil end
                end
            end)
            if hit and not opts.dry then
                indexes[name] = nil
                Recount(name)
                Changed(name)
            end
        end
    end
    return removed
end

-- Zurücksetzen: eine Schicht ("cache", "held", "seen") oder eine Tabelle. → Zahl der Sätze vorher
function DB.Reset(what)
    if not ready or frozen then return 0 end
    local n = 0
    -- Der Zwischenspeicher füllt sich bei der nächsten Abfrage neu: die Merker „diese Sitzung schon geschrieben“ fallen
    if what == "cache" or (specs[what] and specs[what].life == "cache") then clientChecked = {} end
    for _, name in ipairs(order) do
        local spec = specs[name]
        if (what == spec.life or what == name) and not readonly[name] then
            n = n + (Num(root.meta.tables[name].rows) or 0)
            root[spec.life][name] = {}
            root.meta.tables[name].rows = 0
            indexes[name] = nil
            Changed(name)
        end
    end
    return n
end

---------------------------------------------------------------------------
-- Größe und Stand
---------------------------------------------------------------------------

local function SizeOf(v)
    local tv = type(v)
    if tv == "string" then return #v + 3 end
    if tv == "number" then return 6 end
    if tv == "boolean" then return 5 end
    return 2
end

-- Ungefähre Größe einer Tabelle in Byte, so wie sie in der SavedVariables-Datei stünde. limit begrenzt die Arbeit
-- (Standard 500 000 Einträge). → Byte, abgebrochen ja/nein
function DB.Measure(t, limit)
    if type(t) ~= "table" or IsSecret(t) then return 0, false end
    limit = Num(limit) or 500000
    local bytes, nodes, seen, stack = 0, 0, {}, { t }
    while #stack > 0 do
        local cur = table.remove(stack)
        if not seen[cur] then
            seen[cur] = true
            bytes = bytes + 4
            for k, v in pairs(cur) do
                nodes = nodes + 1
                if nodes > limit then return bytes, true end
                bytes = bytes + SizeOf(k) + 3
                if type(v) == "table" then stack[#stack + 1] = v else bytes = bytes + SizeOf(v) end
            end
        end
    end
    return bytes, false
end

function DB.Ready() return ready, persistent end
function DB.Persistent() return ready and persistent end
function DB.Frozen() return frozen end

-- Einträge und geschätzte Größe je Tabelle (für /ez status und den Abschnitt „Datenbank“).
function DB.Stats()
    local out = { ready = ready, persistent = persistent, frozen = frozen, queued = #queue, tables = {}, rows = 0, bytes = 0 }
    if not ready then return out end
    local m = root.meta
    for _, name in ipairs(order) do
        local spec = specs[name]
        local rows = Num(m.tables[name] and m.tables[name].rows) or 0
        local bytes = rows * spec.bytes
        out.tables[#out.tables + 1] = { name = name, life = spec.life, rows = rows, bytes = bytes, readonly = readonly[name] }
        out.rows, out.bytes = out.rows + rows, out.bytes + bytes
    end
    out.skipped = Copy(m.skipped)
    out.jobs = Copy(m.jobs)
    out.id, out.builds = m.id, Copy(m.builds)
    return out
end

-- Kopf der Datenbank (nur ezCore-intern: Übernahme, Merker)
function DB.Meta() return ready and root.meta or nil end

-- Welle 23c (A66): Größe einer Karte in Yards (C_Map.GetMapWorldSize, Discovery.MapYards) im Kopf, auf ganze Yards
-- gerundet: meta.mapYards[uiMapID] = { breite, höhe }. Damit legt tools/merge.lua Fundorte verschiedener Beiträge nach
-- Abstand in Yards zusammen (DB.LIMITS.NODE_YARDS) statt nach der Rasterzelle. Keine private Angabe – die Größe einer
-- Karte, kein Ort. Höchstens DB.MAP_YARDS_MAX Karten. → true, wenn neu oder geändert
DB.MAP_YARDS_MAX = 2000
function DB.NoteMapSize(map, w, h)
    map, w, h = Num(map), Num(w), Num(h)
    if not (ready and not frozen and map and map > 0 and w and h and w > 0 and h > 0) then return false end
    local m = root.meta
    m.mapYards = type(m.mapYards) == "table" and m.mapYards or {}
    w, h = math.floor(w + 0.5), math.floor(h + 0.5)
    local old = m.mapYards[map]
    if type(old) == "table" and old[1] == w and old[2] == h then return false end
    if old == nil then
        local n = 0
        for _ in pairs(m.mapYards) do n = n + 1 end
        if n >= DB.MAP_YARDS_MAX then return false end
    end
    m.mapYards[map] = { w, h }
    return true
end

-- Gemerkte Kartengrößen (Kopie): { [uiMapID] = { breite, höhe } }
function DB.MapSizes()
    return ready and type(root.meta.mapYards) == "table" and Copy(root.meta.mapYards) or {}
end

---------------------------------------------------------------------------
-- Schlüsselräume (Entwurf, Abschnitt 2): derselbe Schlüssel steht in mehreren Tabellen. Die Anmeldung nennt je
-- Ebene (spec.keys) und je verweisendem Feld (spec.refs) den Raum; DB.Resolve kennt damit jede Stelle.
---------------------------------------------------------------------------

-- Raum » "one" (eindeutig: ein Notschlüssel wird in den ID-Satz überführt) | "many" (mehrdeutig: nur verknüpft)
DB.SPACES = { npc = "many", obj = "many", recipe = "one", taxi = "one", instance = "one", spell = "one", area = "one",
    item = "one", map = "one", vig = "one", quest = "one", realm = "one", kind = "one", cur = "one", class = "one",
    offer = "one", tree = "one", variant = "one" }
-- Raum der Namen je Text-Art (text[Sprache][Art][Schlüssel])
DB.TEXT_SPACE = { npc = "npc", npcTitle = "npc", where = "npc", obj = "obj", vig = "vig", recipe = "recipe",
    recipeSrc = "recipe", tool = "recipe", taxi = "taxi" }

local function SpaceAt(spec, path, level)
    local keys = spec.keys
    if type(keys) == "function" then keys = keys(path) end
    return type(keys) == "table" and keys[level] or nil
end
DB.SpaceAt = function(name, path, level) return specs[name] and SpaceAt(specs[name], path or {}, level) end

-- Pfad als Text (Zahl und gleichlautender Text bleiben verschieden) – nur für Merker im Arbeitsspeicher
local function PathText(keys)
    if type(keys) ~= "table" then keys = { keys } end
    local parts = {}
    for i, k in ipairs(keys) do parts[i] = (type(k) == "number" and "#" or "$") .. tostring(k) end
    return table.concat(parts, "\31")
end

-- Zwei Sätze desselben Dings zusammenführen: der neuere Stand gewinnt, Zähler addieren sich, Bekanntes wird nie
-- durch nil ersetzt (DB.Merge – Umzug und Auflösen von Notschlüsseln).
local function MergeRows(dst, src, rules)
    if (Num(src.t) or 0) >= (Num(dst.t) or 0) then
        MergeInto(dst, src, rules)
    else
        local base = Copy(src)
        MergeInto(base, dst, rules)
        for k in pairs(dst) do dst[k] = nil end
        for k, v in pairs(base) do dst[k] = v end
    end
    return dst
end

function DB.Merge(name, dst, src)
    local spec = specs[name]
    if not (spec and type(dst) == "table" and type(src) == "table") then return dst end
    return MergeRows(dst, Copy(src), spec.merge or EMPTY)
end

local function MergeLeaf(spec, dst, src, path)
    if spec.list then
        for _, el in ipairs(src) do
            local hit
            for _, have in ipairs(dst) do
                if type(have) == "table" and type(el) == "table" and spec.list.match(have, el, path) then hit = have break end
            end
            if hit then MergeInto(hit, el, spec.merge or EMPTY) else dst[#dst + 1] = el end
        end
        local cap = type(spec.list.cap) == "function" and spec.list.cap(path) or spec.list.cap
        while cap and #dst > cap and spec.list.shrink do
            local before = #dst
            spec.list.shrink(dst, path)
            if #dst >= before then break end
        end
    else
        MergeRows(dst, src, spec.merge or EMPTY)
    end
end

local function MergeTree(spec, dst, src, level, depth, path)
    for k, v in pairs(src) do
        if dst[k] == nil then
            dst[k] = v
        elseif type(v) == "table" and type(dst[k]) == "table" then
            local p = {}
            for i = 1, #path do p[i] = path[i] end
            p[#p + 1] = k
            if level >= depth then MergeLeaf(spec, dst[k], v, p) else MergeTree(spec, dst[k], v, level + 1, depth, p) end
        end
    end
end

local function ReplaceRefs(spec, row, space, fb, id)
    local hit = false
    -- Felder, deren Schlüssel im Raum liegen (spec.maps: vendor.w » item, offer.svc » spell): zusammenführen
    for field, sp in pairs(spec.maps or EMPTY) do
        local m = row[field]
        if sp == space and type(m) == "table" and m[fb] ~= nil then
            if type(m[id]) == "table" and type(m[fb]) == "table" then MergeRows(m[id], m[fb], spec.merge or EMPTY)
            elseif m[id] == nil then m[id] = m[fb] end
            m[fb], hit = nil, true
        end
    end
    for field, sp in pairs(spec.refs or EMPTY) do
        if sp == space then
            local v = row[field]
            if v == fb then
                row[field], hit = id, true
            elseif type(v) == "table" then
                for i = 1, #v do if v[i] == fb then v[i], hit = id, true end end
            end
        end
    end
    return hit
end

-- Notschlüssel auflösen: über alle Tabellen und Verweise des Raums. → Zahl der überführten bzw. verknüpften Stellen
function DB.Resolve(space, fb, id)
    if not ready or frozen or not DB.SPACES[space] or not Keys.IsFallback(fb) then return 0 end
    if not ValidKey(id) or Keys.IsFallback(id) then return 0 end
    local one = DB.SPACES[space] == "one"
    local n = 0
    for _, name in ipairs(order) do
        local spec = specs[name]
        local tbl = not readonly[name] and Tbl(name, false)
        if tbl then
            local touched = false
            local function Walk(t, level, path)
                local depth = Depth(spec, path[1] or fb)
                if SpaceAt(spec, path, level) == space and t[fb] ~= nil then
                    local src = t[fb]
                    if one then
                        local p = {}
                        for i = 1, #path do p[i] = path[i] end
                        p[#p + 1] = id
                        if type(t[id]) ~= "table" then
                            t[id] = src
                        elseif level >= depth then
                            MergeLeaf(spec, t[id], src, p)
                        else
                            MergeTree(spec, t[id], src, level + 1, depth, p)
                        end
                        t[fb] = nil
                        n, touched = n + 1, true
                    elseif level >= depth and type(src) == "table" then
                        local to = type(src.to) == "table" and src.to or {}
                        local known = false
                        for _, x in ipairs(to) do if x == id then known = true end end
                        if not known then to[#to + 1] = id end
                        src.to = to
                        n, touched = n + 1, true
                    end
                end
                for k, v in pairs(t) do
                    if type(v) == "table" then
                        local p = {}
                        for i = 1, #path do p[i] = path[i] end
                        p[#p + 1] = k
                        if level < Depth(spec, p[1]) then
                            Walk(v, level + 1, p)
                        elseif one and (spec.refs or spec.maps) then
                            if spec.list then
                                for _, el in ipairs(v) do
                                    if type(el) == "table" and ReplaceRefs(spec, el, space, fb, id) then n, touched = n + 1, true end
                                end
                            elseif ReplaceRefs(spec, v, space, fb, id) then
                                n, touched = n + 1, true
                            end
                        end
                    end
                end
            end
            Walk(tbl, 1, {})
            if touched then
                indexes[name] = nil
                Recount(name)
                Changed(name)
            end
        end
    end
    -- gehaltene Namen ziehen mit (mehrdeutig: der Notschlüssel-Satz behält seinen Namen)
    if one and type(root.text) == "table" then
        for _, byLoc in pairs(root.text) do
            for kind, list in pairs(type(byLoc) == "table" and byLoc or EMPTY) do
                if DB.TEXT_SPACE[kind] == space and type(list) == "table" and list[fb] ~= nil then
                    if list[id] == nil then list[id] = list[fb] end
                    list[fb] = nil
                    n = n + 1
                end
            end
        end
    end
    if n > 0 then Core.Fire("DB_RESOLVED", space, fb, id) end
    return n
end

---------------------------------------------------------------------------
-- Umkehr-Index im Arbeitsspeicher (Entwurf, Abschnitt 7): spec.index = { [Index] = fn(satz, pfad) » Liste der Werte }
---------------------------------------------------------------------------

local function IndexRow(I, fn, row, path)
    local pt = PathText(path)
    for _, value in ipairs(I.of[pt] or EMPTY) do
        local set = I.by[value]
        if set then set[pt] = nil end
    end
    I.of[pt] = nil
    if type(row) ~= "table" then return end
    local ok, values = pcall(fn, row, path)
    if not ok or type(values) ~= "table" then return end
    local list = {}
    for _, value in ipairs(values) do
        if not IsSecret(value) and value ~= nil then
            local set = I.by[value] or {}
            I.by[value] = set
            set[pt] = path
            list[#list + 1] = value
        end
    end
    I.of[pt] = list
end

local function BuildIndex(name, idx, fn)
    local I = { by = {}, of = {} }
    EachRow(name, function(row, _, _, path) IndexRow(I, fn, row, path) end)
    indexes[name] = indexes[name] or {}
    indexes[name][idx] = I
    return I
end

Reindex = function(name, keys)
    local built = indexes[name]
    local spec = specs[name]
    if not (built and spec and spec.index) then return end
    local row = Row(name, keys, false)
    local path = {}
    for i, k in ipairs(keys) do path[i] = k end
    for idx, I in pairs(built) do
        local fn = spec.index[idx]
        if fn then IndexRow(I, fn, row, path) end
    end
end

-- → sortierte Liste der Schlüssel-Pfade (Kopien), deren Satz den Wert nennt
function DB.Index(name, idx, value)
    local spec = specs[name]
    local fn = spec and type(spec.index) == "table" and spec.index[idx]
    if IsSecret(value) or not (ready and fn) or value == nil then return {} end
    local I = indexes[name] and indexes[name][idx] or BuildIndex(name, idx, fn)
    local out = {}
    for _, path in pairs(I.by[value] or EMPTY) do
        local copy = {}
        for i, k in ipairs(path) do copy[i] = k end
        out[#out + 1] = copy
    end
    table.sort(out, function(a, b) return PathText(a) < PathText(b) end)
    return out
end

---------------------------------------------------------------------------
-- Aufträge (Entwurf, Abschnitt 5, Regel 10) und Versionsschritte je Tabelle
---------------------------------------------------------------------------
--   DB.Job(name, spec): spec = {
--     list   = fn() » Schlüssel (Zahlen, Texte oder Pfade { k1, k2 … }); einmal je Sitzung gezogen und sortiert
--     step   = fn(schlüssel, schatten) – überträgt einen Schlüssel; eine reine Funktion der Quelle
--     swap   = fn(schatten) » anzahl, offen – Tausch in einem Bild außerhalb des Kampfes
--     sig    = Kennung der Quelle; passt sie nicht zum gespeicherten Stand, wird der Schatten verworfen
--     root   = fn() » Ablage mit meta (Standard: der Weltwissen-Träger) – dort liegen Merker und Schatten
--     shadow = false: ohne Schatten (step schreibt Satz für Satz ins Ziel; die Leser lesen „neu über alt“)
--   }
--   Stand in <Ablage>.meta.jobs[name] = { sig, last (letzter erledigter Schlüssel), n, total, shadow, dirty, done }.
--   Nach /reload geht es hinter last weiter; doppelt gezählt wird nie, weil der Schatten nie mit der alten Form
--   gemischt wird. Schreibt jemand während des Auftrags (DB.JobDirty), wird der Schlüssel vor dem Tausch neu
--   übertragen (ersetzen, nicht addieren).

local jobs, jobOrder, runtime, tableJobs = {}, {}, {}, {}

local function KeyLess(a, b)
    if type(a) == "table" or type(b) == "table" then
        local x, y = type(a) == "table" and a or { a }, type(b) == "table" and b or { b }
        for i = 1, math.max(#x, #y) do
            if x[i] == nil then return true end
            if y[i] == nil then return false end
            if x[i] ~= y[i] then return KeyLess(x[i], y[i]) end
        end
        return false
    end
    local ta, tb = type(a), type(b)
    if ta ~= tb then return ta == "number" end
    if ta == "number" or ta == "string" then return a < b end
    return tostring(a) < tostring(b)
end
DB.KeyLess = KeyLess

local function JobState(spec, create)
    local r = spec.root and spec.root() or root
    if type(r) ~= "table" or type(r.meta) ~= "table" then return nil end
    r.meta.jobs = type(r.meta.jobs) == "table" and r.meta.jobs or {}
    local st = r.meta.jobs[spec.name]
    if type(st) ~= "table" then
        if not create then return nil end
        st = { sig = spec.sig }
        r.meta.jobs[spec.name] = st
    end
    return st
end

function DB.JobState(name)
    local spec = jobs[name]
    local st = spec and JobState(spec, false)
    if not st then return nil end
    return { sig = st.sig, done = st.done, n = st.n, total = st.total, last = Copy(st.last) }
end

function DB.JobDirty(name, key)
    local spec = jobs[name]
    local st = spec and JobState(spec, false)
    if not st or st.done or st.last == nil then return false end   -- noch nicht begonnen: der Schritt sieht den neuen Stand
    st.dirty = type(st.dirty) == "table" and st.dirty or {}
    st.dirty[PathText(key)] = Copy(key)
    return true
end

MarkDirty = function(name, keys)
    local job = tableJobs[name]
    if job then DB.JobDirty(job, keys) end
end

local function Slice(spec, sync)
    local st = JobState(spec, false)
    if not st or st.done then return false end
    local rt = runtime[spec.name]
    if not rt then
        local ok, list = pcall(spec.list)
        list = ok and type(list) == "table" and list or {}
        table.sort(list, KeyLess)
        local pos = 1
        if st.last ~= nil then
            local lo, hi = 1, #list + 1
            while lo < hi do
                local mid = math.floor((lo + hi) / 2)
                if KeyLess(st.last, list[mid]) then hi = mid else lo = mid + 1 end
            end
            pos = lo
        end
        rt = { list = list, pos = pos }
        runtime[spec.name] = rt
        st.total = #list
        if spec.shadow ~= false then st.shadow = type(st.shadow) == "table" and st.shadow or {} end
    end
    local clock = G("debugprofilestop")
    local t0 = type(clock) == "function" and clock() or nil
    local count = 0
    while rt.pos <= #rt.list do
        local key = rt.list[rt.pos]
        local ok, err = pcall(spec.step, key, st.shadow)
        if not ok then
            Core.Error(Core.name or "ezCore", err, "DB.Job " .. spec.name)
            runtime[spec.name] = nil
            return false
        end
        st.last, st.n = key, (Num(st.n) or 0) + 1
        rt.pos, count = rt.pos + 1, count + 1
        if not sync then
            if t0 then
                if clock() - t0 >= LIMITS.SLICE_MS then break end
            elseif count >= LIMITS.SLICE_ROWS then
                break
            end
        end
    end
    Core.Fire("DB_JOB_PROGRESS", spec.name, rt.pos - 1, #rt.list)
    if rt.pos <= #rt.list then return true end
    if InCombat() then return true end   -- getauscht wird nur außerhalb des Kampfes
    for _, key in pairs(type(st.dirty) == "table" and st.dirty or EMPTY) do pcall(spec.step, key, st.shadow) end
    local cnt, open = st.n, 0
    if spec.swap then
        local ok, a, b = pcall(spec.swap, st.shadow)
        if not ok then
            Core.Error(Core.name or "ezCore", a, "DB.Job " .. spec.name .. " (Tausch)")
            runtime[spec.name] = nil
            return false
        end
        cnt, open = Num(a) or cnt, Num(b) or 0
    end
    st.shadow, st.dirty, st.last, runtime[spec.name] = nil, nil, nil, nil
    st.done = Stamp()
    Core.Fire("DB_JOB_DONE", spec.name, Num(cnt) or 0, Num(open) or 0)
    return false
end

local function Pending()
    for _, name in ipairs(jobOrder) do
        local spec = jobs[name]
        local st = spec and JobState(spec, false)
        if st and not st.done then return spec end
    end
    return nil
end

local jobsRunning = false
-- Aufträge abarbeiten: eine Scheibe je Bild, nie im Kampf. sync = true: alles sofort (Tests, kleine Mengen).
function DB.RunJobs(sync)
    if sync then
        local guard = 0
        local spec = Pending()
        while spec and not InCombat() and guard < 100000 do
            guard = guard + 1
            if not Slice(spec, true) then
                local nextSpec = Pending()
                if nextSpec == spec then break end   -- Fehler im Auftrag: nicht endlos wiederholen
                spec = nextSpec
            end
        end
        return Pending() == nil
    end
    if jobsRunning then return true end
    local timer = G("C_Timer")
    if not (type(timer) == "table" and timer.After) then return DB.RunJobs(true) end
    jobsRunning = true
    local function Tick()
        local spec = Pending()
        if not spec then jobsRunning = false return end
        if InCombat() then timer.After(1, Tick) return end
        if not Slice(spec, false) and Pending() == spec then jobsRunning = false return end
        timer.After(0, Tick)
    end
    timer.After(0, Tick)
    return true
end

function DB.Job(name, spec)
    assert(type(name) == "string" and name ~= "" and type(spec) == "table", "DB.Job: Name und Angaben fehlen")
    assert(type(spec.list) == "function" and type(spec.step) == "function", "DB.Job " .. name .. ": list und step fehlen")
    spec.name = name
    if not jobs[name] then jobOrder[#jobOrder + 1] = name end
    jobs[name] = spec
    runtime[name] = nil
    local st = JobState(spec, true)
    if not st then return nil, "noroot" end
    if st.sig ~= spec.sig then
        for k in pairs(st) do st[k] = nil end   -- Quelle passt nicht mehr: Schatten verwerfen, neu beginnen
        st.sig = spec.sig
    end
    if st.done then return "done" end
    DB.RunJobs()
    return "queued"
end

-- Versionsschritte: spec.steps[v] = fn(satz, pfad) » neuer Satz oder nil (geändert an Ort und Stelle). Ein Schritt
-- muss einen schon neuen Satz unverändert lassen (während eines Auftrags schreiben die Sammler weiter).
RunSteps = function(name, spec, entry)
    local from = Num(entry.v) or 1
    local steps = type(spec.steps) == "table" and spec.steps or EMPTY
    local need = false
    for v = from + 1, spec.v do if steps[v] then need = true end end
    if not need then
        entry.v = spec.v   -- nur neue Felder: kein Umzug (Regel 2)
        return
    end
    local target = spec.v
    local function Convert(row, path)
        for v = from + 1, target do
            if steps[v] then
                local r = steps[v](row, path)
                if type(r) == "table" then row = r end
            end
        end
        return row
    end
    if (Num(entry.rows) or Recount(name)) <= LIMITS.SYNC_ROWS then
        EachRow(name, function(row, parent, key, path) parent[key] = Convert(row, path) end)
        entry.v = target
        indexes[name] = nil
        return
    end
    local jobName = "table:" .. name .. ":v" .. target
    tableJobs[name] = jobName
    DB.Job(jobName, {
        sig = from .. ">" .. target,
        list = function()
            local paths = {}
            EachRow(name, function(_, _, _, path) paths[#paths + 1] = path end)
            return paths
        end,
        step = function(path, shadow)
            local row = Row(name, path, false)
            shadow[PathText(path)] = row and { path = path, row = Convert(Copy(row), path) } or false
        end,
        swap = function(shadow)
            for _, e in pairs(shadow) do
                if type(e) == "table" then
                    -- nur, wo der Satz noch steht: während des Auftrags Vergessenes bleibt vergessen
                    local row, _, parent, last = Row(name, e.path, false)
                    if row ~= nil and parent then parent[last] = e.row end
                end
            end
            entry.v = target
            tableJobs[name] = nil
            indexes[name] = nil
            Changed(name)
            return Num(entry.rows) or 0, 0
        end,
    })
end

---------------------------------------------------------------------------
-- Anmelden der Tabellen und des Trägers
---------------------------------------------------------------------------

function DB.Define(name, spec)
    assert(type(name) == "string" and name ~= "" and not specs[name], "DB.Define: Name fehlt oder ist vergeben: " .. tostring(name))
    assert(type(spec) == "table" and LIFE[spec.life], "DB.Define " .. name .. ": life muss cache, held oder seen sein")
    for field, rule in pairs(spec.merge or EMPTY) do
        assert(DB.FIELDS[field], "DB.Define " .. name .. ": Feld " .. tostring(field) .. " steht nicht im Feldverzeichnis")
        assert(RULE_OK[rule], "DB.Define " .. name .. ": unbekannte Regel " .. tostring(rule))
    end
    for _, group in ipairs({ spec.refs or EMPTY, spec.maps or EMPTY }) do
        for field, space in pairs(group) do
            assert(DB.FIELDS[field], "DB.Define " .. name .. ": Verweis " .. tostring(field) .. " steht nicht im Feldverzeichnis")
            assert(DB.SPACES[space], "DB.Define " .. name .. ": unbekannter Schlüsselraum " .. tostring(space))
        end
    end
    if type(spec.keys) == "table" then
        for _, space in ipairs(spec.keys) do
            assert(DB.SPACES[space], "DB.Define " .. name .. ": unbekannter Schlüsselraum " .. tostring(space))
        end
    else
        assert(spec.keys == nil or type(spec.keys) == "function", "DB.Define " .. name .. ": keys muss Liste oder Funktion sein")
    end
    for v, step in pairs(spec.steps or EMPTY) do
        assert(Num(v) and type(step) == "function", "DB.Define " .. name .. ": steps[v] muss eine Funktion sein")
    end
    for idx, fn in pairs(spec.index or EMPTY) do
        assert(type(idx) == "string" and type(fn) == "function", "DB.Define " .. name .. ": index braucht Namen und Funktion")
    end
    if spec.list then
        assert(type(spec.list.match) == "function", "DB.Define " .. name .. ": list.match fehlt")
    end
    spec.name, spec.v, spec.carrier = name, Num(spec.v) or 1, spec.carrier or "world"
    assert(DB.CARRIERS[spec.carrier], "DB.Define " .. name .. ": unbekannter Träger " .. tostring(spec.carrier))
    spec.bytes = Num(spec.bytes) or 80
    specs[name] = spec
    order[#order + 1] = name
    if ready then EnsureTable(name) end
    return true
end

function DB.Defined(name) return specs[name] ~= nil end
function DB.Tables() local list = {} for i, n in ipairs(order) do list[i] = n end return list end
-- Anmeldung einer Tabelle (nur ezCore-intern und für die Prüfungen: Schicht, Räume, Deckel; nie ändern)
function DB.Spec(name) return specs[name] end

-- Träger anhängen (intern: beim Laden und in den Tests). t = die SavedVariable des Trägers bzw. {} im Arbeitsspeicher.
function DB.Attach(t, isPersistent)
    if type(t) ~= "table" then return false end
    root, persistent, frozen, readonly = t, isPersistent == true, nil, {}
    indexes, runtime, tableJobs, limitWarned = {}, {}, {}, false
    nameCount = {}
    for _, life in ipairs(DB.LIVES) do
        if type(root[life]) ~= "table" then root[life] = {} end
    end
    if type(root.text) ~= "table" then root.text = {} end
    InitMeta(root)
    for _, name in ipairs(order) do EnsureTable(name) end
    ready = true
    Replay()
    Core.Fire("DB_READY", persistent)
    return true
end

-- Zurück in „nicht bereit“ (nur für die Tests: verzögerter und fehlender Träger)
function DB.Detach()
    root, ready, persistent, frozen, readonly, queue = nil, false, false, nil, {}, {}
    clientChecked, indexes, runtime, tableJobs = {}, {}, {}, {}
    for k in pairs(lost) do lost[k] = nil end
end

function DB.Queued() return #queue end

-- Träger verloren (SAVED_VARIABLES_TOO_LARGE, Entwurf 9.1): kein Auslöser zum Kürzen. Für diesen Träger wird nichts
-- angelegt und nichts geschrieben, seine Sammler sind für die Sitzung aus; DB_CARRIER_LOST meldet es deutlich.
-- (die Tabelle lost steht oben bei DB.Collecting)
function DB.CarrierLost(key) return lost[key] == true end

-- Die Träger laden vor ezCore: ihr SAVED_VARIABLES_TOO_LARGE hört ezCore nicht selbst. Der Träger setzt dann den
-- Merker <Addon>TooLarge (global, nicht gespeichert); er wird beim Laden von ezCore und beim Anmelden gelesen.
local function NoteTooLarge()
    for _, name in pairs(DB.CARRIERS) do
        if G(name .. "TooLarge") == true then DB.OnTooLarge(name) end
    end
end

local function TryCarrier()
    NoteTooLarge()
    if ready or lost.world then return end
    local addon = DB.CARRIERS.world
    if not Core.IsLoaded(addon) then return end
    local t = G(addon .. "DB")
    if type(t) == "table" then DB.Attach(t, true) end
end

function DB.OnTooLarge(addon)
    for key, name in pairs(DB.CARRIERS) do
        if addon == name and not lost[key] then
            lost[key] = true
            local t = G(name .. "DB")
            if key == "world" and ready and persistent and root == t then DB.Attach({}, false) end
            if t ~= nil then rawset(_G, name .. "DB", nil) end   -- nie eine leere Tabelle über die Datei schreiben
            Core.Fire("DB_CARRIER_LOST", name)
        end
    end
end

ns.On("SAVED_VARIABLES_TOO_LARGE", function(_, addon) DB.OnTooLarge(addon) end)
ns.On("ADDON_LOADED", function(_, name)
    if name == ADDON or name == DB.CARRIERS.world then TryCarrier() end
end)
ns.On("PLAYER_LOGIN", function()
    TryCarrier()
    if not ready then DB.Attach({}, false) end   -- ohne Träger: nur im Arbeitsspeicher, /ez status sagt es
end)
ns.On("PLAYER_REGEN_ENABLED", function()
    if #queue > 0 then Replay() end
    if Pending() then DB.RunJobs() end
end)

Core.RegisterMessage("DB_READY", "DB.lua", "Die Entdecker-Datenbank ist bereit (Träger ezWorld oder nur Arbeitsspeicher).", "gespeichert")
Core.RegisterMessage("DB_CHANGED", "DB.lua", "Eine Tabelle der Entdecker-Datenbank hat sich geändert (gesammelt höchstens einmal je Bild).", "name")
Core.RegisterMessage("DB_JOB_PROGRESS", "DB.lua", "Ein Auftrag der Datenbank ist eine Scheibe weiter.", "auftrag, fertig, gesamt")
Core.RegisterMessage("DB_RESOLVED", "DB.lua", "Ein Notschlüssel ist über den ganzen Schlüsselraum aufgelöst bzw. verknüpft.", "raum, notschlüssel, id")
Core.RegisterMessage("DB_LIMIT", "DB.lua", "Das Weltwissen hat die Warnschwelle erreicht (gesammelt wird weiter; Angebot zum Aufräumen).", "träger, byte")
Core.RegisterMessage("DB_CARRIER_LOST", "DB.lua", "Ein Träger konnte nicht geladen werden (SAVED_VARIABLES_TOO_LARGE): nichts wird für ihn geschrieben.", "träger")
