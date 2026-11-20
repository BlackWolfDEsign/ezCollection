local _, ns = ...
local Core = ezCore

--[[
    Entdecker-Datenbank: Tabellen und Sammler (Welle 9; Entwurf docs/archiv/entwurf-entdecker-datenbank.md, Abschnitte 1.4
    und 6; Dienst DB.lua, Schlüssel DBKeys.lua, Leser und Abschnitt „Datenbank“ DiscoveryView.lua).

    Tabellen (Schicht „seen“, wenn nicht anders genannt):
      drops[Art][ID] bzw. drops[fishing|unknown][Karte][Gebiet]
                      = { diff = { [difficultyID] = Zählblock }, old = Zählblock (Altbestand aus dem Verlauf) }
                      Zählblock = { cnt (geöffnete Fenster; seit Welle 23c auch die in der Gruppe), party (davon in
                      der Gruppe; bis Welle 23c zählten Gruppenfenster nur hier, nicht in cnt), empty, deaths,
                      money = { sum, cnt }, items = { [itemID] = { f, s, lo, hi } },
                      tokens = { [currencyID] = { f, s } } } – f Vorgänge mit dem Gegenstand, s Summe, lo/hi kleinste
                      und größte Menge je Vorgang; ein Vorgang ist ein Fenster, an Spielobjekten seit Welle 14 ein Besuch
                      (alle Schläge derselben GUID, VisitStart/VisitRange; docs/ezcore.md „f, s, lo, hi je Art“)
      salvage[Zerlege-spellID][Ausgangs-itemID] = Zählblock (ohne party: Zerlegen zählt nur in cnt, auch in der Gruppe)
      npc[npcID]      = { lvls = { lo, hi }, tier, side, roles = { vendor|repair|trainer = zuletzt }, tr, tk, skill = { lo, hi,
                      req, cnt } (nötige Kürschner-Fertigkeit, Welle 27, F4 b – Form wie obj.skill) }
      obj[objectID]   = { kind (herb, mine, chest, pool, quest, container), cnt, quest (questID, nilbar), skill = { lo
                      (kleinster Rang bei Erfolg), hi (größter Rang bei Fehlschlag), req (laut Client-Meldung), cnt (eigene Beobachtungen,
                      Welle 27) } }; Name
                      je Sprache in text.obj (SAM-01, SAM-04; Arten seit Welle 13: Discovery.LootKind)
      spot[Speicherkarte][Art][ID] = { { xy, cnt, t, b, via, inst, pt } … }  Fundorte, eingerechnet über Keys.Cell;
                      Objekte und Angeln (Art fishing, ID = Gebiet) seit Welle 12 im Umkreis von DB.LIMITS.NODE_YARDS
                      (Yards über C_Map.GetMapWorldSize; ohne Größe weiter die Rasterzelle), Version 2 verdichtet einmal
                      die schon gesammelten Punkte (SAM-02)
      vendor[npcID]   = { tf, w = { [itemID] = { pr, per, lim, t, b } } }
      offer[Lehrer-Art] = { tf, svc = { [spellID oder Notschlüssel] = { rank, lvl, pr, tp, skill, ic, at, t, b } } }
      route[von][nach] = { { hops, sec, cnt, lo, hi, pr, t, b } … }   (Schreiber: Core.Flights.Note – ezMap, Welle 10)
      entrance[instanceID] = { raid, cnt }; Orte in spot Art „entrance“ (letzte Außenposition vor dem Betreten)
      rare[npcID]     = { cnt, sight = { { t, map, dead } … } }      Entdecker-Wissen
      vig[vignetteID] angemeldet, bleibt leer (Probe Frage 18 offen)
      reveal[itemID]  = { t0, how (1 Beute, 2 Händler), realms = { [Realm-Laufnummer] = { t0, how } } }   Entdecker-Wissen
      zoneLv[Speicherkarte] = { lo, hi, cnt, hist = { [Stufe] = Anzahl } }   gesehene feindliche NPC-Stufen
      book[itemID]    = { cnt, quest }; Orte in spot Art „book“ (beim Aufheben)   Entdecker-Wissen
      recipeObs[Rezept] = { stages = { [Farbe] = { lo, hi } }, item (Version 2: Gegenstand, der das Rezept lehrt) }
      item[itemID]    Schicht „cache“: Antworten des Clients mit Build (DB.Client)

    Sammler (nur bei OPT_dataCollect, nichts im Kampf direkt – der Dienst staut bis nach dem Kampf):
      LOOT_READY      Inhalt des Fensters beim Öffnen, alle Quellen je Platz (GetLootSourceInfo), jede Quell-GUID
                      einmal je Art und Sitzung; Art aus der Quelle und dem eigenen Zauber kurz davor (Kürschnern,
                      Kräuter, Bergbau, Taschendiebstahl, Zerlegen – gilt nur für das erste Fenster danach); in
                      Instanzen nur Zählung, keine Orte. Welle 12 (SAM-01, SAM-05): Zielname aus UNIT_SPELLCAST_SENT
                      (Name des Knotens je Sprache); je Objekt-GUID eine Ernte je Besuch (DB.LIMITS.VISIT_SECONDS) –
                      weitere Beute daraus zählt zum Ertrag; Sammelzauber ohne lesbare GUID: Notschlüssel Art plus
                      Hauptertrag (Keys.GatherFallback), beim ersten Fund mit GUID zusammengeführt; Angeln mit
                      Fang-Position (spot fishing) und Schwarm als Objekt (obj kind pool), wenn der Client ihn nennt
                      und dieselbe GUID zweimal Beute gibt (der Schwimmer entsteht je Wurf neu; seine Objekt-Nummer
                      35591 „Angelschwimmer“ ist zusätzlich ausgeschlossen – Quelle: Probe G13 rechnet mit ihr,
                      kleinhelfer_test.lua; im Spiel noch unbeantwortet); jedes Angel-Fenster ist ein eigener Fang;
                      Spielobjekt ohne Sammelzauber: Kiste (Entdecker-Wissen). Im selben Besuch zählt Beute nur nach
                      einem neuen Sammelzauber zum Ertrag (erneutes Öffnen ohne Zauber zählt nichts).
      UI_ERROR_MESSAGE  benötigte Fertigkeit eines Knotens (SAM-04): Meldung des Clients „Rang zu niedrig“ (Muster
                      aus den GlobalStrings, Discovery.SKILL_ERRORS, Positionsangaben wie %2$d erlaubt) – mit Zahl der
                      Rang laut Client, ohne Zahl der eigene Rang als Schranke nach unten; Erfolg mit dem eigenen Rang
                      ist die Schranke nach oben. Fehlschläge ohne diese Meldung lehren nichts. Welle 27 (F4 b): für
                      alle Sammel-Ressourcen – der Name des Berufs in der Meldung legt die Art fest (Core.Gathering.
                      KindOfSkillName); Kürschnern schreibt an den Gegner (npc.skill), Kisten an das Ziel von „Schloss
                      knacken“ (Discovery.LOCK_SPELLS) bzw. „Öffnen“; Erfolg mit dem eigenen Rang auch am Schwarm, beim
                      Kürschnern und nach „Schloss knacken“. Dieselbe Zeile im Tooltip von Spielobjekten und Gegnern wird
                      gelesen (Abschnitte „ezCore.skillRead“, ohne eigene Zeile), ebenso Blizzards „kürschnerbar“.
      PARTY_KILL      Tode (Nenner „bei m getöteten“)
      MERCHANT_*      Händler-Sortiment, TRAINER_*  Lehrer-Angebot (spellID aus dem Tooltip, sonst Notschlüssel)
      Plaketten, Ziel, Maus   Gegnerstufen je Karte, seltene Gegner
      Kartenwechsel   Eingänge (letzte Außenposition vor dem Betreten, auch bei PLAYER_LEAVING_WORLD) und Name der
                      Instanz je Sprache (text.instance, Discovery.InstanceName; Welle 23c)
    Übernahme „adopt1“ (einmal je Datenbank, nach dem Anmelden, außerhalb des Kampfes, ein Speicher je Bild):
      ezCoreDB.history.loot » drops[…].old (bis zur Fensternummer meta.marks.lootWindow; Würfe nicht),
      ezCoreDB.npcs » npc, spot, text; ezCoreDB.spells.trainer » offer; ezCoreDB.knowledge.bookMap » book.
      Die Altspeicher bleiben liegen und werden weiter geschrieben (ihre Leser lesen sie weiter, siehe docs/ezcore.md).
]]

local DB = Core.DB
local Keys = DB.Keys
local Num, Plain, IsSecret = Core.Num, Core.Plain, Core.IsSecret

local Discovery = {}
Core.Discovery = Discovery

local function G(name) return rawget(_G, name) end

---------------------------------------------------------------------------
-- Tabellen
---------------------------------------------------------------------------

local function DropsDepth(kind)
    local k = Keys.KINDS[kind]
    return k and (1 + (k.levels or 1)) or 2
end

-- Schlüsselräume der Beute: Art » ID (Raum der Art) bzw. Art » Speicherkarte » Gebiet (Angeln, unbekannt)
local function DropsKeys(path)
    local k = Keys.KINDS[path[1]]
    if k and (k.levels or 1) == 2 then return { "kind", "map", "area" } end
    return { "kind", k and k.space or "npc" }
end

-- Fundorte: Speicherkarte » Art » ID (Raum der Art)
local function SpotKeys(path)
    local k = Keys.KINDS[path[2]]
    return { "map", "kind", k and k.space or "npc" }
end

-- Fundorte: gleiche Rasterzelle = derselbe Ort; über dem Deckel wird die schwächste Stelle in die nächste
-- eingerechnet (die Zählung bleibt, nur der Ort wird gröber; Entwurf, Abschnitt 10). Deckel: DB.LIMITS.SPOT.
Discovery.SPOT_CAP = DB.LIMITS.SPOT

-- SAM-02: Größe einer Karte in Yards (C_Map.GetMapWorldSize), je Sitzung gemerkt; nil, wenn der Client sie nicht
-- nennt (dann gilt weiter die Rasterzelle).
local mapYards = {}
function Discovery.MapYards(map)
    map = Num(map)
    if not map or map <= 0 then return nil end
    local hit = mapYards[map]
    if hit ~= nil then
        if hit then return hit[1], hit[2] end
        return nil
    end
    local api = G("C_Map")
    local fn = type(api) == "table" and api.GetMapWorldSize
    local w, h
    if type(fn) == "function" then
        local ok, a, b = pcall(fn, map)
        if ok and not IsSecret(a) and not IsSecret(b) then w, h = Num(a), Num(b) end
    end
    if w and h and w > 0 and h > 0 then
        mapYards[map] = { w, h }
        -- Welle 23c (A66): im Kopf der Datenbank merken (tools/merge.lua legt Beiträge damit nach Yards zusammen)
        if DB.Collecting() then DB.NoteMapSize(map, w, h) end
        return w, h
    end
    mapYards[map] = false
    return nil
end
function Discovery.ForgetMapSizes() mapYards = {} end

-- Abstand zweier gepackter Positionen in Yards (nil ohne Kartengröße)
function Discovery.Yards(map, xyA, xyB)
    local w, h = Discovery.MapYards(map)
    if not w then return nil end
    local ax, ay = Keys.Unpack(xyA)
    local bx, by = Keys.Unpack(xyB)
    if not (ax and bx) then return nil end
    return math.sqrt(((ax - bx) * w) ^ 2 + ((ay - by) * h) ^ 2)
end

local NEAR_KINDS = { object = true, fishing = true }

local function SamePlace(a, b, keys)
    if a.xy and b.xy then
        if NEAR_KINDS[keys[2]] then
            local d = Discovery.Yards(keys[1], a.xy, b.xy)
            if d then return d <= DB.LIMITS.NODE_YARDS end
        end
        return Keys.Cell(a.xy, keys[2]) == Keys.Cell(b.xy, keys[2])
    end
    if not a.xy and not b.xy then return a.inst == b.inst end
    return false
end
Discovery.SamePlace = SamePlace

-- SAM-02: Punkte einer Liste im Umkreis zusammenlegen (einmal beim Umstieg auf Version 2 und für Prüfungen). Der
-- häufigste Punkt bleibt stehen, die Zählungen der anderen kommen dazu; gleiche Form wie vorher. → Liste, Zahl entfernt
function Discovery.CompactPlaces(list, map, kind)
    if type(list) ~= "table" or #list < 2 then return list, 0 end
    local order = {}
    for i, el in ipairs(list) do order[#order + 1] = { el = el, i = i } end
    table.sort(order, function(x, y)
        local cx, cy = Num(x.el.cnt) or 0, Num(y.el.cnt) or 0
        if cx ~= cy then return cx > cy end
        return x.i < y.i
    end)
    local kept, keys = {}, { map, kind or "object" }
    for _, o in ipairs(order) do
        local el, into = o.el, nil
        if type(el) == "table" then
            for _, k in ipairs(kept) do
                if SamePlace(k, el, keys) then into = k break end
            end
            if into then
                into.cnt = (Num(into.cnt) or 0) + (Num(el.cnt) or 0)
                into.t = math.max(Num(into.t) or 0, Num(el.t) or 0)
                if Num(el.t0) then into.t0 = math.min(Num(into.t0) or el.t0, el.t0) end
            else
                kept[#kept + 1] = el
            end
        end
    end
    local removed = #list - #kept
    for i = #list, 1, -1 do list[i] = nil end
    for i, el in ipairs(kept) do list[i] = el end
    return list, removed
end

local function CompactStep(list, path)
    if type(path) == "table" and NEAR_KINDS[path[2]] then Discovery.CompactPlaces(list, path[1], path[2]) end
    return list
end

local function Distance(a, b)
    local ax, ay = Keys.Unpack(a.xy)
    local bx, by = Keys.Unpack(b.xy)
    if not (ax and bx) then return math.huge end
    return (ax - bx) ^ 2 + (ay - by) ^ 2
end

local function ShrinkPlaces(list)
    local weak, wi
    for i, el in ipairs(list) do
        local c, wc = Num(el.cnt) or 0, weak and (Num(weak.cnt) or 0) or nil
        if not weak or c < wc or (c == wc and (Num(el.t) or 0) < (Num(weak.t) or 0)) then weak, wi = el, i end
    end
    if not weak then return end
    local near, nd
    for i, el in ipairs(list) do
        if i ~= wi then
            local d = Distance(weak, el)
            if not near or d < nd then near, nd = el, d end
        end
    end
    if near then
        near.cnt = (Num(near.cnt) or 0) + (Num(weak.cnt) or 0)
        near.t = math.max(Num(near.t) or 0, Num(weak.t) or 0)
    end
    table.remove(list, wi)
end

local function SameHops(a, b)
    local x, y = type(a.hops) == "table" and a.hops or {}, type(b.hops) == "table" and b.hops or {}
    if #x ~= #y then return false end
    for i = 1, #x do if x[i] ~= y[i] then return false end end
    return true
end

local function DropOldest(list)
    local oldest, oi
    for i, el in ipairs(list) do
        if not oldest or (Num(el.t) or 0) < (Num(oldest.t) or 0) then oldest, oi = el, i end
    end
    if oi then table.remove(list, oi) end
end

-- Zählblöcke eines Beute-Satzes: diff[difficultyID] und old
local function EachBlock(row, fn)
    for _, b in pairs(type(row.diff) == "table" and row.diff or {}) do
        if type(b) == "table" then fn(b) end
    end
    if type(row.old) == "table" then fn(row.old) end
end

-- Art unknown: höchstens DB.LIMITS.UNKNOWN_ITEMS Gegenstände je Karte und Gebiet; die seltensten zählen in den
-- Sammelposten rest { f, s } – die Zählung bleibt (Entwurf, Abschnitt 10).
local function TrimDrops(row, keys)
    if keys[1] ~= "unknown" then return end
    local max = DB.LIMITS.UNKNOWN_ITEMS
    EachBlock(row, function(b)
        if type(b.items) ~= "table" then return end
        local list = {}
        for id, it in pairs(b.items) do list[#list + 1] = { id, Num(it.f) or 0 } end
        if #list <= max then return end
        table.sort(list, function(x, y) if x[2] ~= y[2] then return x[2] < y[2] end return x[1] < y[1] end)
        b.rest = type(b.rest) == "table" and b.rest or { f = 0, s = 0 }
        for i = 1, #list - max do
            local it = b.items[list[i][1]]
            b.rest.f = (Num(b.rest.f) or 0) + (Num(it.f) or 0)
            b.rest.s = (Num(b.rest.s) or 0) + (Num(it.s) or 0)
            b.items[list[i][1]] = nil
        end
    end)
end
Discovery.TrimDrops = TrimDrops

-- Lehrer je Angebot: höchstens DB.LIMITS.OFFER_AT, die älteste Zuordnung weicht (Entwurf, Abschnitt 10)
local function TrimOffer(row)
    for _, s in pairs(type(row.svc) == "table" and row.svc or {}) do
        local at = type(s) == "table" and type(s.at) == "table" and s.at
        if at then
            local list = {}
            for npc, t in pairs(at) do list[#list + 1] = { npc, Num(t) or 0 } end
            if #list > DB.LIMITS.OFFER_AT then
                table.sort(list, function(x, y) if x[2] ~= y[2] then return x[2] < y[2] end return DB.KeyLess(x[1], y[1]) end)
                for i = 1, #list - DB.LIMITS.OFFER_AT do at[list[i][1]] = nil end
            end
        end
    end
end

-- Beute v2 (DB-N1, Beitragen): jeder Zählblock trägt seinen ersten Build b0. Übernahme vorhandener Sätze: der erste
-- Build des Satzes (Altbestand „old“: 0 = unbekannt). Ein Block, der b0 schon hat, bleibt unverändert.
local function DropsV2(row)
    local first = Num(row.b0) or 0
    for _, b in pairs(type(row.diff) == "table" and row.diff or {}) do
        if type(b) == "table" and b.b0 == nil then b.b0 = first end
    end
    if type(row.old) == "table" and row.old.b0 == nil then row.old.b0 = 0 end
end
Discovery.DropsV2 = DropsV2

-- Händler: Umkehr-Index Ware » Händler (DB.Index, nie gespeichert)
local function VendorWares(row)
    local out = {}
    for itemID in pairs(type(row.w) == "table" and row.w or {}) do out[#out + 1] = itemID end
    return out
end

-- Rezepte: Umkehr-Index Zutat » Rezepte und Produkt » Rezept
local function RecipeReagents(row)
    local out = {}
    for _, r in ipairs(type(row.rg) == "table" and row.rg or {}) do
        if type(r) == "table" and Num(r.item) then out[#out + 1] = r.item end
    end
    return out
end
local function RecipeProduct(row) return { Num(row.out) } end

-- Gebiete in ihrer Endform (Entwurf, Abschnitte 1.3 und 1.4): jede Tabelle ist angemeldet, auch wenn ihr Sammler
-- erst mit einem späteren Paket kommt (dann bleibt sie leer). keys = Schlüsselraum je Ebene, refs = verweisende
-- Felder, maps = Felder, deren Schlüssel in einem Raum liegen.
DB.Define("drops", { life = "seen", v = 2, depth = DropsDepth, keys = DropsKeys, bytes = 160, trim = TrimDrops,
    steps = { [2] = DropsV2 } })
DB.Define("salvage", { life = "seen", v = 1, depth = 2, keys = { "spell", "item" }, bytes = 120 })
DB.Define("npc", { life = "seen", v = 1, depth = 1, keys = { "npc" }, refs = { tk = "offer" }, bytes = 90 })
-- obj Version 2 (Welle 13): einmalige, geprüfte Nachbewertung der Kisten aus Welle 12 (ReclassObject, unten) – gleiche
-- Form, nur der Wert kind ändert sich (quest bzw. container statt chest)
DB.Define("obj", { life = "seen", v = 2, depth = 1, keys = { "obj" }, refs = { spell = "spell" }, bytes = 50,
    steps = { [2] = function(row, path) return Discovery.ReclassStep(row, path) end } })
DB.Define("spot", { life = "seen", v = 2, depth = 3, keys = SpotKeys, bytes = 70, refs = { inst = "instance", area = "area" },
    list = { match = SamePlace, cap = function(keys) return Discovery.SPOT_CAP[keys[2]] or DB.LIMITS.SPOT_OTHER end,
        shrink = ShrinkPlaces }, steps = { [2] = CompactStep } })
DB.Define("vendor", { life = "seen", v = 1, depth = 1, keys = { "npc" }, maps = { w = "item", wcur = "cur" }, bytes = 400,
    index = { item = VendorWares } })
DB.Define("offer", { life = "seen", v = 1, depth = 1, keys = { "offer" }, maps = { svc = "spell" }, bytes = 1500,
    trim = TrimOffer })
DB.Define("route", { life = "seen", v = 1, depth = 2, keys = { "taxi", "taxi" }, refs = { hops = "taxi" }, bytes = 80,
    merge = { sec = "newest" }, list = { match = SameHops, cap = DB.LIMITS.ROUTE_WAYS, shrink = DropOldest } })
DB.Define("entrance", { life = "seen", v = 1, depth = 1, keys = { "instance" }, bytes = 40 })
DB.Define("rare", { life = "seen", v = 1, depth = 1, keys = { "npc" }, refs = { vig = "vig" }, bytes = 200, explorer = true })
DB.Define("vig", { life = "seen", v = 1, depth = 1, keys = { "vig" }, refs = { npc = "npc", obj = "obj", quest = "quest" },
    bytes = 60, explorer = true })
DB.Define("reveal", { life = "seen", v = 1, depth = 1, keys = { "item" }, maps = { realms = "realm" }, bytes = 60,
    explorer = true, merge = { how = "first" } })
DB.Define("zoneLv", { life = "seen", v = 1, depth = 1, keys = { "map" }, bytes = 200, merge = { hist = "sum" } })
DB.Define("book", { life = "seen", v = 1, depth = 1, keys = { "item" }, refs = { quest = "quest", obj = "obj" }, bytes = 40,
    explorer = true })
-- recipeObs Version 2 (Welle 15b, Rezept-Fundorte): neues Feld item = Gegenstand, der das Rezept lehrt (beim Händler-
-- Besuch gemerkt, Knowledge.NoteRecipeItem); Umkehr-Index Gegenstand » Rezept. Nur ein neues Feld: kein Umzug
-- (DB.RunSteps hebt die Version ohne Schritt), Sätze der Version 1 (stages) bleiben unverändert gültig.
local function RecipeObsItem(row) return { Num(row.item) } end
DB.Define("recipeObs", { life = "seen", v = 2, depth = 1, keys = { "recipe" }, refs = { item = "item" }, bytes = 120,
    index = { item = RecipeObsItem } })
DB.Define("spellObs", { life = "seen", v = 1, depth = 1, keys = { "spell" }, bytes = 60 })
DB.Define("classObs", { life = "seen", v = 1, depth = 1, keys = { "class" }, bytes = 120 })
DB.Define("itemVar", { life = "seen", v = 1, depth = 2, keys = { "item", "variant" }, bytes = 90 })
-- Schicht „cache“ (Client-Antworten, verwerfbar) und „held“ (nur in einer bestimmten Lage zu haben, nie gekürzt)
DB.Define("item", { life = "cache", v = 1, depth = 1, keys = { "item" }, bytes = 70 })
DB.Define("spell", { life = "cache", v = 1, depth = 1, keys = { "spell" }, refs = { base = "spell" }, bytes = 60 })
DB.Define("spellFam", { life = "cache", v = 1, depth = 1, keys = { "spell" }, bytes = 60 })
DB.Define("map", { life = "cache", v = 1, depth = 1, keys = { "map" }, refs = { parent = "map" }, bytes = 50 })
DB.Define("recipe", { life = "held", v = 1, depth = 1, keys = { "recipe" }, refs = { out = "item", prev = "recipe",
    next = "recipe" }, bytes = 110, index = { reagent = RecipeReagents, product = RecipeProduct } })
DB.Define("taxiNode", { life = "held", v = 1, depth = 1, keys = { "taxi" }, refs = { map = "map", npc = "npc" }, bytes = 50 })
DB.Define("trait", { life = "held", v = 1, depth = 1, keys = { "tree" }, bytes = 2000 })

---------------------------------------------------------------------------
-- Gemeinsames
---------------------------------------------------------------------------

-- Ein angesprochener NPC (via 1) zählt je Sitzung einmal an seinem Ort: Händler- und Lehrerfenster melden sich
-- mehrfach (SHOW, UPDATE, Npcs.Learn), ein Besuch ist eine Beobachtung.
local placedNpc = {}
Core.Listen("DB_READY", function() placedNpc = {} end, "ezCore.Discovery")

local function Place(map, kind, id, via, extra)
    if not (map and id) then return end
    if kind == "npc" and via == 1 then
        if placedNpc[id] then return end
        placedNpc[id] = true
    end
    local inst = Keys.Instance8()
    local place = { cnt = 1, via = via }
    local _, xy = Keys.PlayerSpot()
    if inst then
        place.inst, place.pt = inst, 32
    elseif xy then
        place.xy = xy
    else
        place.pt = 32
    end
    for k, v in pairs(extra or {}) do place[k] = v end
    if NEAR_KINDS[kind] then
        -- SAM-18 (Welle 14): Schalter „Fundorte nicht mehr ändern“ – keine neue oder veränderte Stelle. Er gilt nur
        -- für Sammel-Fundorte (Angeln und Objekte der Arten in Gathering.KIND_PUBLIC; ohne Art gilt eine Stelle wie in
        -- Gathering als Kiste) – Quest-Objekte und Behälter werden weiter erfasst
        local Gath = Core.Gathering
        if Gath and Gath.Locked and Gath.Locked() then
            local gather = kind == "fishing"
            if not gather then
                local obj = DB.Get("obj", id)
                local objKind = type(obj) == "table" and obj.kind or nil
                gather = objKind == nil or (type(Gath.KIND_PUBLIC) == "table" and Gath.KIND_PUBLIC[objKind] ~= nil)
            end
            if gather then return nil, "locked" end
        end
        -- Fortschritt je Zone („zuletzt neu vor …“): ein neuer Punkt trägt t0 (zuerst gesehen); ein schon bekannter
        -- nicht – sonst bekäme ein alter Punkt ohne t0 beim nächsten Besuch das heutige Datum
        if place.xy then
            local known = false
            for _, el in ipairs(DB.Get("spot", map, kind, id) or {}) do
                if type(el) == "table" and SamePlace(el, place, { map, kind }) then
                    known = true
                    -- Stelle aus einer eingelesenen Sicherung (SAM-19, Welle 23d): mit der eigenen Ernte gilt sie als eigene
                    if el.src == "backup" then place.src = "own" end
                    break
                end
            end
            if not known then place.t0 = DB.Stamp() end
        end
    end
    return DB.Observe("spot", { map, kind, id }, place)
end
Discovery.Place = Place

local function NpcSide()
    local raw = Core.Call(G("UnitFactionGroup"), "npc")
    if IsSecret(raw) then return nil end
    if raw == "Alliance" then return "A" elseif raw == "Horde" then return "H" end
    return "N"
end

-- Ein NPC mit Rolle (Händler, Lehrer): Rollen mit Zeitpunkt, Seite, Ort, Name und Untertitel (nur mit Rolle).
local function NoteNpc(npcID, roles, extra)
    local now = DB.Stamp()
    local f = { roles = {} }
    for _, role in ipairs(roles) do f.roles[role] = now end
    local side = NpcSide()
    if side then f.side = side end
    for k, v in pairs(extra or {}) do f[k] = v end
    DB.Observe("npc", npcID, f)
    local map = Keys.PlayerSpot()
    Place(map, "npc", npcID, 1)
    DB.SetText("npc", npcID, Core.Call(G("UnitName"), "npc"))
    local N = Core.Npcs
    local title = N and N.Subtitle and N.Subtitle()
    if not title then
        local e = N and N.Get and N.Get(npcID)
        title = e and e.title
    end
    if title then DB.SetText("npcTitle", npcID, title) end
end
Discovery.NoteNpc = NoteNpc

local revealed = {}
local function Reveal(itemID, how)
    if not itemID or revealed[itemID] then return end
    local name = Core.ItemNameByID and Core.ItemNameByID(itemID, true)
    if not name then return end
    revealed[itemID] = true
    local f = { how = how }
    local realm = Keys.Realm()
    if realm then f.realms = { [realm] = { t0 = DB.Stamp(), how = how } } end
    DB.Observe("reveal", itemID, f)
end
Discovery.Reveal = Reveal
-- Eine andere Ablage (Träger nachgeladen): die Merker „schon enthüllt“ gelten für sie nicht
Core.Listen("DB_READY", function() revealed = {} end, "ezCore.Discovery")

---------------------------------------------------------------------------
-- Eigener Zauber kurz vor dem Beutefenster (Art der Beute ohne Kampflog)
---------------------------------------------------------------------------

Discovery.CONTEXT_SECONDS = 6
-- Grundzauber, deren Name (in der Sprache des Clients, jeder Rang) die Art festlegt – Nummern des Clients
-- (klassische Zauberbuch-Nummern, im Spiel über /ez test prüfbar): Kürschnern, Kräuterkunde, Bergbau, Taschendiebstahl.
-- Herkunft: aus der Probe J5 nicht gelesen (ohne Sammeln); abgeglichen werden sie über wago.tools (Produkt wowf, Tabelle
-- SpellName – Liste in docs/datengrundlage.md). open (Welle 13): „Öffnen“ 3365 – Kandidat aus klassischer Kenntnis, im
-- Spiel NICHT gelesen; greift nur, wenn der Client den Namen kennt (ein Name gilt für alle Öffnen-Zauber), sonst nie.
Discovery.CONTEXT_SPELLS = { skin = 8613, herb = 2366, mine = 2575, pick = 921, open = 3365 }

local recent
local baseNames, salvageSpells   -- einmal gebildet (Namen und Nummern ändern sich in der Sitzung nicht)

local function ContextOf(spellID)
    spellID = Num(spellID)
    if not spellID then return nil end
    if not salvageSpells then
        salvageSpells = {}
        local S = Core.Salvage
        for _, kind in ipairs(S and S.Kinds and S.Kinds(true) or {}) do
            if Num(kind.spell) then salvageSpells[kind.spell] = true end
        end
    end
    if salvageSpells[spellID] then return "salvage" end
    if not baseNames then
        baseNames = {}
        for kind, id in pairs(Discovery.CONTEXT_SPELLS) do
            local name = Core.SpellName and Core.SpellName(id)
            if type(name) == "string" and name ~= "" then baseNames[name] = kind end
        end
    end
    for kind, id in pairs(Discovery.CONTEXT_SPELLS) do
        if id == spellID then return kind end
    end
    local name = Core.SpellName and Core.SpellName(spellID)
    return type(name) == "string" and baseNames[name] or nil
end
Discovery.ContextOf = ContextOf

-- SAM-01: UNIT_SPELLCAST_SENT nennt das Ziel des eigenen Zaubers – beim Sammeln der Name des Knotens in der Sprache
-- des Clients. Gemerkt nur für Zauber mit Art (Sammeln, Kürschnern …), gesperrte Werte nie.
local sent

-- Welle 27 (F4 b): „Schloss knacken“ (Pick Lock 1804 – laut wago.tools, Produkt wowf: SkillLineAbility Linie 633
-- Schlossknacken). Gemerkt nur für die nötige Fertigkeit verschlossener Kisten; die Art der Beute ändert es nicht (das
-- Öffnen danach zählt wie bisher). Andere Ränge über den Namen des Zaubers (wie ContextOf).
Discovery.LOCK_SPELLS = { 1804 }
local lockSent, lockNames
local function IsLockSpell(spellID)
    spellID = Num(spellID)
    if not spellID then return false end
    for _, id in ipairs(Discovery.LOCK_SPELLS) do
        if id == spellID then return true end
    end
    if not lockNames then
        lockNames = {}
        for _, id in ipairs(Discovery.LOCK_SPELLS) do
            local name = Core.SpellName and Core.SpellName(id)
            if type(name) == "string" and name ~= "" then lockNames[name] = true end
        end
    end
    local name = Core.SpellName and Core.SpellName(spellID)
    return type(name) == "string" and lockNames[name] == true
end
Discovery.IsLockSpell = IsLockSpell

ns.OnUnit("UNIT_SPELLCAST_SENT", "player", function(_, _, target, castGUID, spellID)
    if IsSecret(spellID) then return end
    local kind = ContextOf(spellID)
    if not kind then
        if IsLockSpell(spellID) then
            local name = not IsSecret(target) and Plain(target) or nil
            lockSent = { at = Core.Uptime(), name = type(name) == "string" and name ~= "" and name or nil }
        end
        return
    end
    -- gesperrtes Ziel oder gesperrte Kennung: der Zauber zählt, nur ohne Namen bzw. ohne Abgleich über die Kennung
    local name = not IsSecret(target) and Plain(target) or nil
    sent = { kind = kind, spell = Num(spellID), cast = not IsSecret(castGUID) and Plain(castGUID) or nil, at = Core.Uptime(),
        name = type(name) == "string" and name ~= "" and name or nil }
end)

local function SentFor(castGUID, spellID)
    local s = sent
    if not s or Core.Uptime() - s.at > Discovery.CONTEXT_SECONDS then return nil end
    if s.cast and castGUID and not IsSecret(castGUID) and s.cast == Plain(castGUID) then return s end
    if s.spell == Num(spellID) then return s end
    return nil
end

ns.OnUnit("UNIT_SPELLCAST_SUCCEEDED", "player", function(_, _, castGUID, spellID)
    if IsSecret(spellID) then return end
    local kind = ContextOf(spellID)
    if not kind then
        if IsLockSpell(spellID) then Discovery.OnLockPicked() end
        return
    end
    local s = SentFor(castGUID, spellID)
    recent = { kind = kind, spell = Num(spellID), at = Core.Uptime(), name = s and s.name or nil }
end)

local CORPSE = { skin = "skin", herb = "herbCorpse", mine = "mineCorpse", pick = "pick" }

-- Der Zauber gilt nur für das erste Beutefenster danach: dieses Öffnen übernimmt ihn (LOOT_READY kommt bis zu dreimal
-- je Öffnen), LOOT_CLOSED gibt ihn auf. Sonst würde die Leiche, die man gleich nach dem Kürschnern plündert, als
-- Kürschnern gezählt (Gegenprüfung Welle 9).
local openCtx
local function TakeContext()
    if openCtx == nil then
        local fresh = recent and (Core.Uptime() - recent.at) <= Discovery.CONTEXT_SECONDS and recent or nil
        if fresh then recent = nil end
        openCtx = fresh or false
    end
    return openCtx or nil
end

---------------------------------------------------------------------------
-- Beute am geöffneten Fenster (DG-03, DG-07, DG-12, NEU-04; löst V-008 in der Zählung)
---------------------------------------------------------------------------

local LOOT_MONEY = Enum and Enum.LootSlotType and Enum.LootSlotType.Money or 2
local LOOT_CURRENCY = Enum and Enum.LootSlotType and Enum.LootSlotType.Currency or 3
Discovery.SESSION_MAX = DB.LIMITS.SESSION_MAX

-- Art|Quell-GUID → true: je Sitzung einmal (LOOT_READY kommt bis zu dreimal). Die Art gehört zum Schlüssel: dieselbe
-- Leiche wird erst geplündert und dann gekürschnert, ein Gegner erst bestohlen und dann geplündert.
local counted, countedN = {}, 0
local opening = {}                   -- dieses Öffnen (Fenster ohne GUID, z. B. Angeln)
-- SAM-01: Objekt-GUID » Zeitpunkt der Ernte (Core.Uptime) – weitere Beute daraus binnen DB.LIMITS.VISIT_SECONDS ist
-- derselbe Besuch (ein Erzvorkommen wird mehrfach abgebaut): sie zählt zum Ertrag, nicht als neue Ernte.
local visits, visitsN = {}, 0

local function Remember(set, n, key)
    if n >= DB.LIMITS.SESSION_MAX then
        for k in pairs(set) do set[k] = nil end
        n = 0
    end
    set[key] = true
    return n + 1
end

local function SourcesOf(slot)
    local fn = G("GetLootSourceInfo")
    if type(fn) ~= "function" then return {} end
    local res = { pcall(fn, slot) }
    if not res[1] then return {} end
    table.remove(res, 1)
    return res
end

-- Welle 23c (A64): ein Fenster in der Gruppe zählt im Nenner mit (cnt) und ist zusätzlich als Gruppenfenster gezählt
-- (party). Vorher stand es nur in party; ohne gezählte Tode war „k× bei n“ dann zu hoch (der Fund zählte, das Fenster
-- nicht). Mit Toden bleibt max(Tode, Fenster) der Nenner (Core.Drops.Denominator). Altbestand: party ohne cnt.
Core.FEATURES.dropsPartyCounted = true
local function Block(r, inGroup)
    local b = { items = {}, b0 = Keys.Build() }   -- erster Build am Zählblock (DB-N1)
    b.cnt = 1
    if inGroup then b.party = 1 end
    local any = false
    for id, qty in pairs(r.items) do
        b.items[id] = { f = 1, s = qty, lo = qty, hi = qty }
        any = true
    end
    for cur, qty in pairs(r.tokens) do
        b.tokens = b.tokens or {}
        b.tokens[cur] = { f = 1, s = qty }
        any = true
    end
    if r.hasMoney then
        b.money = { sum = r.money, cnt = 1 }
        any = true
    end
    if not any then b.empty = 1 end
    return b
end

-- Art eines geplünderten Spielobjekts (Welle 13, Gegenprüfung: Objekt 2907 „Wasserkrug“ ist ein Quest-Objekt, keine
-- Kiste – Befund des Nutzers vom 15.11.2026). Reihenfolge:
--   (a) Angeln » pool; Sammelzauber » herb bzw. mine (SAM-01); sonst Gegenstandsklasse der Beute (Handwerkswaren 7:
--       Kraut 9 » herb, Metall und Stein 7 » mine; C_Item.GetItemInfoInstant, 6./7. Rückgabe)
--   (b) alle Gegenstände der Klasse Quest (12) oder ein Platz, den der Client als Quest-Gegenstand nennt
--       (GetLootSlotInfo, 7. Rückgabe isQuestItem, 8. questID – Form laut Probe G10: 10 Rückgaben) » quest
--   (c) ein Öffnen-Zauber ging voraus, Geld oder Währung im Fenster, mindestens zwei verschiedene Gegenstände » chest;
--       sonst die neutrale Art container
-- Quest-Objekte und Behälter sind keine Sammelknoten (Core.Gathering.Nodes und Core.Finds.Of lassen sie aus).
-- info = { quest = bool, money = bool, tokens = bool, opened = bool }
Discovery.QUEST_CLASS = 12
function Discovery.LootKind(items, info)
    info = type(info) == "table" and info or {}
    local n, allQuest = 0, true
    for id in pairs(items or {}) do
        n = n + 1
        -- Klasse über ezCores eine Umhüllung (Core.ItemInstant: pcall, gesperrte Werte; Gesamtreview 18.11.2026, T16-16)
        local _, _, _, _, _, c, s = Core.ItemInstant(id, G("C_Item"))
        local classID, subclassID = Num(c), Num(s)
        if classID == 7 and subclassID == 9 then return "herb" end
        if classID == 7 and subclassID == 7 then return "mine" end
        if classID ~= Discovery.QUEST_CLASS then allQuest = false end
    end
    if info.quest or (n > 0 and allQuest) then return "quest" end
    if info.opened or info.money or info.tokens or n >= 2 then return "chest" end
    return "container"
end

local function ObjKind(ctx, items, fishing, info)
    if fishing then return "pool" end
    if ctx and ctx.kind == "herb" then return "herb" end
    if ctx and ctx.kind == "mine" then return "mine" end
    info = type(info) == "table" and info or {}
    if ctx and ctx.kind == "open" then info.opened = true end
    return Discovery.LootKind(items, info)
end
Discovery.ObjKind = ObjKind

-- Nachbewertung (obj Version 2): eine Kiste aus Welle 12 (ohne Wissen um Quest-Plätze und Öffnen-Zauber) wird aus
-- ihrer gespeicherten Beute neu bewertet – Geld, Währung oder gemischte Beute bleiben chest, nur Quest-Gegenstände
-- werden quest, ein einzelner gewöhnlicher Gegenstand container. Andere Arten bleiben unberührt.
function Discovery.ReclassObject(row, path)
    if type(row) ~= "table" or row.kind ~= "chest" then return row end
    local id = type(path) == "table" and path[1] or path
    local drops = id ~= nil and DB.Get("drops", "object", id) or nil
    if type(drops) ~= "table" then return row end
    local items, money, tokens = {}, false, false
    local function Take(b)
        if type(b) ~= "table" then return end
        for itemID in pairs(type(b.items) == "table" and b.items or {}) do items[itemID] = true end
        if type(b.money) == "table" then money = true end
        if type(b.tokens) == "table" and next(b.tokens) ~= nil then tokens = true end
    end
    for _, b in pairs(type(drops.diff) == "table" and drops.diff or {}) do Take(b) end
    Take(drops.old)
    if next(items) == nil and not money and not tokens then return row end
    row.kind = Discovery.LootKind(items, { money = money, tokens = tokens })
    if row.kind ~= "quest" then row.quest = nil end
    return row
end

-- Der Versionsschritt läuft bei kleinen Tabellen synchron in DB.Attach, also bevor die Datenbank bereit ist – dann
-- liefert DB.Get die Beute noch nicht (Gegenprüfung Welle 13). Die Kisten warten deshalb bis DB_READY und werden dort
-- einmal neu bewertet (DB.Change); läuft der Schritt als Auftrag (Datenbank bereit), wird sofort bewertet.
local pendingReclass = {}
function Discovery.ReclassStep(row, path)
    if DB.Ready() then return Discovery.ReclassObject(row, path) end
    local id = type(path) == "table" and path[1] or path
    if type(row) == "table" and row.kind == "chest" and id ~= nil then pendingReclass[#pendingReclass + 1] = id end
    return row
end
Core.Listen("DB_READY", function()
    local list = pendingReclass
    pendingReclass = {}
    for _, id in ipairs(list) do
        DB.Change("obj", { id }, function(row) Discovery.ReclassObject(row, id) end)
    end
end, "ezCore.Discovery")

-- Art aus mehreren Besuchen (Gegenprüfung Welle 13): die Beute eines einzelnen Besuchs entscheidet nicht allein.
-- Sammel-Arten (herb, mine, pool: Zauber oder Gegenstandsklasse) gelten vor den Beute-Arten; unter diesen gilt die
-- Rangfolge chest vor quest vor container – eine Kiste wird nie zum Behälter oder Quest-Objekt herabgestuft.
local LOOT_RANK = { container = 1, quest = 2, chest = 3 }
function Discovery.MergeKind(old, new)
    if old == nil then return new end
    if new == nil then return old end
    local ro, rn = LOOT_RANK[old], LOOT_RANK[new]
    if not rn then return new end          -- neue Sammel-Art: belegt durch Zauber oder Klasse
    if not ro then return old end          -- alte Sammel-Art bleibt vor einer Beute-Art
    return rn >= ro and new or old
end

-- Hauptertrag eines Funds: der Gegenstand mit der größten Menge, bei Gleichstand die kleinste itemID
local function MainItem(items)
    local best, bq
    for id, qty in pairs(items or {}) do
        if not best or qty > bq or (qty == bq and id < best) then best, bq = id, qty end
    end
    return best
end
Discovery.MainItem = MainItem

-- Rang des eigenen Berufs zu einer Sammel-Art (skillLine aus GetProfessionInfo, 7. Rückgabe: Kräuterkunde 182,
-- Bergbau 186 – Nummern des Clients, sprachfrei). Die Nummern und die Abfrage stehen an EINER Stelle:
-- Core.Gathering.PROFESSION_LINES bzw. SKILL_LINE_OF und Core.Gathering.OwnRank (live, sonst Rückfall aus der
-- Fertigkeitenliste). Welle 27 (F4 b): auch Kürschnerei (skin), Angeln (fish, pool) und Schlossknacken (chest;
-- Gathering.OwnRank liest es aus der Fertigkeitenliste)
Discovery.RANK_KINDS = { herb = true, mine = true, ore = true, skin = true, fish = true, pool = true, chest = true }
function Discovery.OwnRank(kind)
    if not Discovery.RANK_KINDS[kind] then return nil end
    local Ga = Core.Gathering
    local rank = Ga and Ga.OwnRank and Num(Ga.OwnRank(kind, true))   -- samt Bonus: dagegen prüft der Client
    if rank and rank > 0 then return rank end   -- ohne bekannten Rang keine Schranke
    return nil
end

-- Name eines Objekts » objectID (Arbeitsspeicher; aus DB.Text gebaut, eigene Namen trägt NoteObjName nach). nameDup
-- merkt Namen, die mehrere Objekte tragen (Welle 27: etwa gleichnamige Kisten mit verschiedenen Schlössern).
local byName, nameDup
local function NameIndex()
    if byName then return byName end
    byName, nameDup = {}, {}
    for _, id in ipairs(DB.Ready() and DB.KeysOf("obj") or {}) do
        local name = DB.Text("obj", id)
        if type(name) == "string" then
            if byName[name] == nil then byName[name] = id elseif byName[name] ~= id then nameDup[name] = true end
        end
    end
    return byName
end
function Discovery.ForgetNameIndex() byName, nameDup = nil, nil end
Core.Listen("DB_READY", Discovery.ForgetNameIndex, "ezCore.Discovery")
function Discovery.ObjectByName(name)
    if IsSecret(name) or type(name) ~= "string" or name == "" then return nil end
    return NameIndex()[name]
end
-- → objectID nur, wenn genau ein bekanntes Objekt diesen Namen trägt; sonst nil und als zweiten Wert true, wenn der
-- Name mehrdeutig ist (dann darf kein Wert an das erste Objekt dieses Namens geschrieben werden)
function Discovery.UniqueObjectByName(name)
    if IsSecret(name) or type(name) ~= "string" or name == "" then return nil end
    local id = NameIndex()[name]
    if id and nameDup[name] then return nil, true end
    return id
end

-- Welle 23c (A29): Namen der Gegenstände, die bei dir aus einer Quelle kamen (Core.Drops.Of(art, id …), etwa „object“
-- oder „loot“) » { [Name klein] = true } – für Quest-Ziele im Tooltip (vorher ezQuest Progress.LootNames). Namen aus
-- dem Client (Core.ItemNameByID); ein noch nicht geladener Gegenstand fehlt, bis der Client ihn kennt.
function Discovery.LootNames(kind, ...)
    local names = {}
    local drops = Core.Drops
    if select("#", ...) == 0 or (...) == nil or type(drops) ~= "table" or type(drops.Of) ~= "function" then return names end
    local total = Core.Call(drops.Of, kind, ...)
    for itemID in pairs(type(total) == "table" and type(total.items) == "table" and total.items or {}) do
        local itemName = Core.ItemNameByID(itemID, true)
        if type(itemName) == "string" and not IsSecret(itemName) then names[itemName:lower()] = true end
    end
    return names
end

-- SAM-04: Fertigkeit, die ein Knoten verlangt. Fehlschläge vor der ersten Ernte (Objekt noch unbekannt) warten im
-- Arbeitsspeicher unter dem Namen, bis das Objekt bekannt ist.
-- Welle 27 (F4 b): auch Erfolge (lo, „Schloss knacken“) und Tooltip-Werte warten so; skill.cnt zählt die eigenen
-- Beobachtungen (Erfolg, Fehlschlag mit Meldung) – ein Wert aus dem Tooltip zählt nicht mit. Höchstens
-- Discovery.PENDING_MAX Namen, dann beginnt die Liste neu.
local pendingSkill, pendingN = {}, 0
Discovery.PENDING_MAX = 100
-- Welle 27: zuletzt aus einem Tooltip gesehener Rang je „tbl:id“ (Arbeitsspeicher). Im Kampf staut DB.Observe in die
-- Warteschlange, die DB.Get nicht sieht – ohne diesen Merker hängte jeder weitere Tooltip denselben Wert an.
-- Höchstens Discovery.QUIET_MAX Einträge, dann beginnt die Liste neu; eine Beobachtung mit req löscht den Eintrag.
local quietReq, quietN = {}, 0
Discovery.QUIET_MAX = 200
local function ForgetQuiet(tbl, id, skill)
    if type(skill) == "table" and skill.req ~= nil then quietReq[tbl .. ":" .. tostring(id)] = nil end
end
local function NoteSkill(id, skill)
    if not id or type(skill) ~= "table" or next(skill) == nil then return end
    ForgetQuiet("obj", id, skill)
    DB.Observe("obj", id, { skill = skill })
end

-- Wert unter dem Namen vormerken, bis ein Objekt dieses Namens geerntet bzw. geplündert wird (NoteObjName). kind: Art der
-- Meldung (herb, ore, chest), wenn der Name nur vom Interaktionsziel stammt und dessen Art unbekannt ist – dann gilt die
-- Vormerkung nur einem Objekt passender Art (Discovery.SOFT_KINDS); ohne kind (Ziel des eigenen Zaubers derselben Art,
-- Erfolg von „Schloss knacken“) gilt sie jedem. Vormerkungen verschiedener Art unter einem Namen: kind = false, verworfen
-- (Nachprüfung kern/sammel-reste, 17.11.2026).
local function Pending(name, skill, kind)
    if type(name) ~= "string" or name == "" or type(skill) ~= "table" then return end
    local p = pendingSkill[name]
    if not p then
        if pendingN >= Discovery.PENDING_MAX then pendingSkill, pendingN = {}, 0 end
        p = { kind = kind }
        pendingSkill[name], pendingN = p, pendingN + 1
    elseif kind and p.kind ~= kind then
        if p.kind then p.kind = false elseif p.kind == nil then p.kind = kind end
    end
    if skill.req then p.req = skill.req end
    if skill.hi then p.hi = math.max(p.hi or skill.hi, skill.hi) end
    if skill.lo then p.lo = math.min(p.lo or skill.lo, skill.lo) end
    if skill.cnt then p.cnt = (p.cnt or 0) + skill.cnt end
end
Discovery.PendingSkill = function(name) return name and pendingSkill[name] or nil end

-- objKind: gespeicherte Art des eben geernteten bzw. geplünderten Objekts (herb, mine, chest …)
local function NoteObjName(id, name, objKind)
    if not (id and type(name) == "string" and name ~= "") then return end
    DB.SetText("obj", id, name)
    local idx = NameIndex()
    if idx[name] == nil then idx[name] = id elseif idx[name] ~= id then nameDup[name] = true end
    local p = pendingSkill[name]
    if p then
        pendingSkill[name], pendingN = nil, math.max(0, pendingN - 1)
        -- ein Name, den mehrere Objekte tragen: die Vormerkung kann einem anderen gelten (Kiste mit anderem Schloss) –
        -- verwerfen statt an das nächste geplünderte Objekt dieses Namens (Fund des code-reviewers vor dem Merge)
        if nameDup[name] then return end
        -- vorgemerkt nur über das Interaktionsziel: die Art der Meldung muss zur Art des Objekts passen, sonst trüge ein
        -- eben geerntetes Kraut einen Bergbau-Wert (Nachprüfung kern/sammel-reste)
        local kinds = p.kind ~= nil and Discovery.SOFT_KINDS[p.kind] or nil
        if p.kind ~= nil and not (kinds and objKind and kinds[objKind]) then return end
        NoteSkill(id, { req = p.req, hi = p.hi, lo = p.lo, cnt = p.cnt })
    end
end

-- Objekt hinter einem Namen, an das ein Wert geschrieben werden darf: zuerst das Objekt, auf das die Interaktion zielt
-- (gleicher Name, genaue Kennung – Core.Tooltip.SoftObjectID), sonst die Namensliste, aber nur bei genau einem Objekt
-- dieses Namens (Discovery.UniqueObjectByName). Mehrere Kisten teilen sich einen Namen; ohne Interaktion → nil, true
-- (mehrdeutig): der Wert wartet dann unter dem Namen bis zur Beute bzw. wird verworfen, nie dem ersten Objekt zugeschrieben.
local function TargetObject(name)
    local T = Core.Tooltip
    local id = T and T.SoftObjectID and Num(T.SoftObjectID(name))
    if id then return id end
    return Discovery.UniqueObjectByName(name)
end
Discovery.TargetObject = TargetObject

-- Notschlüssel Art + Hauptertrag in die echte Objekt-ID überführen (obj, drops, spot, Name); obj ist ein mehrdeutiger
-- Raum (DB.Resolve verknüpft dort nur) – hier wird bewusst zusammengeführt, wie der Entwurf es für Sammel-Funde sagt.
function Discovery.MergeGatherFallback(fb, id)
    if not (Keys.IsFallback(fb) and id and not Keys.IsFallback(id)) then return 0 end
    local n = 0
    local row = DB.Get("obj", fb)
    if row then
        DB.Observe("obj", id, { cnt = row.cnt, skill = row.skill })
        DB.Forget("obj", fb)
        n = n + 1
    end
    local drops = DB.Get("drops", "object", fb)
    if drops then
        DB.Observe("drops", { "object", id }, { diff = drops.diff, old = drops.old })
        DB.Forget("drops", "object", fb)
        n = n + 1
    end
    for _, map in ipairs(DB.KeysOf("spot")) do
        local list = DB.Get("spot", map, "object", fb)
        if list then
            for _, el in ipairs(list) do
                DB.Observe("spot", { map, "object", id }, { xy = el.xy, cnt = el.cnt, via = el.via, inst = el.inst, pt = el.pt })
            end
            DB.Forget("spot", map, "object", fb)
            n = n + 1
        end
    end
    local name = DB.Text("obj", fb)
    if name and not DB.Text("obj", id) then DB.SetText("obj", id, name) end
    if n > 0 then Core.Fire("DB_RESOLVED", "obj", fb, id) end
    return n
end

-- Muster der Client-Meldung „Benötigt <Beruf> <Rang>“ aus den GlobalStrings (nie fester Wortlaut). Positionsangaben
-- (%1$s, %2$d) werden zuerst entfernt; Texte mit Zahl (%d) liefern den Rang (die erste Zahl im Treffer), Texte ohne
-- Zahl erkennen nur „Rang zu niedrig“. Die Muster mit Zahl werden zuerst geprüft.
-- Welle 27 (F4 b): dazu SPELL_FAILED_MIN_SKILL („Fertigkeit zu niedrig. Benötigt %s (%d)“) und SPELL_FAILED_LOW_CASTLEVEL
-- („Fertigkeit nicht hoch genug“) – Namen aus Blizzards GlobalStrings der Retail-Fassung, auf Forever nicht gelesen
-- (Spieltest ezCore); fehlt ein Name im Client, wird er übersprungen.
Discovery.SKILL_ERRORS = { "ERR_USE_LOCKED_WITH_SPELL_KNOWN_SI", "ERR_USE_LOCKED_WITH_SPELL_SI", "SPELL_FAILED_REQUIRES_SKILL_SI",
    "SPELL_FAILED_MIN_SKILL", "SPELL_FAILED_LOW_CASTLEVEL" }
local skillPatterns
local function SkillPatterns()
    if skillPatterns then return skillPatterns end
    local withNum, plain = {}, {}
    for _, key in ipairs(Discovery.SKILL_ERRORS) do
        local text = G(key)
        if type(text) == "string" and not IsSecret(text) and text ~= "" then
            local pat = text:gsub("%%%d+%$", "%%")                      -- %1$s » %s, %2$d » %d
            local hasNum = pat:find("%%d") ~= nil
            pat = pat:gsub("([%(%)%.%[%]%*%+%-%?%^%$])", "%%%1")        -- Sonderzeichen wörtlich
            pat = pat:gsub("%%s", "(.-)"):gsub("%%d", "(%%d+)")
            local list = hasNum and withNum or plain
            list[#list + 1] = "^" .. pat .. "$"
        end
    end
    skillPatterns = { num = withNum, plain = plain }
    return skillPatterns
end
function Discovery.ForgetSkillPatterns() skillPatterns = nil end

-- → Rang (Zahl) laut Client-Meldung, true bei „Rang zu niedrig“ ohne Zahl, sonst nil; als zweiten Wert (Welle 27) den
-- Namen aus der Meldung (der Teil an %s, etwa „Kräuterkunde“), sonst nil
function Discovery.SkillErrorOf(message)
    if IsSecret(message) or type(message) ~= "string" then return nil end
    local pats = SkillPatterns()
    for _, pat in ipairs(pats.num) do
        local caps = { message:match(pat) }
        local rank, name
        for _, c in ipairs(caps) do
            local n = tonumber(c)
            if n and not rank then rank = n elseif not n and not name then name = c end
        end
        if rank then return rank, name end
    end
    for _, pat in ipairs(pats.plain) do
        local caps = { message:match(pat) }
        if caps[1] ~= nil then
            -- ohne Platz für den Namen liefert match den ganzen Text – dann kein Name
            return true, pat:find("%(%.%-%)") and caps[1] or nil
        end
    end
    return nil
end

-- → Rang aus einer Client-Meldung oder nil
function Discovery.SkillFromMessage(message)
    local res = Discovery.SkillErrorOf(message)
    return type(res) == "number" and res or nil
end

-- Art des eigenen Zaubers (UNIT_SPELLCAST_SENT) » Art der Fertigkeit (Welle 27: Kürschnern dazu). Öffnen fehlt
-- bewusst: eine Kiste kann auch einen Schlüssel oder einen anderen Beruf verlangen („Benötigt Schlüssel“) – Kisten
-- zählen nur, wenn die Meldung Schlossknacken nennt.
Discovery.SENT_SKILL = { herb = "herb", mine = "ore", skin = "skin" }

local function Recent(s)
    return s and Core.Uptime() - s.at <= Discovery.CONTEXT_SECONDS and s or nil
end

-- Gegner, den der eigene Zauber traf: eine Einheit mit demselben Namen unter Ziel, Maus und Interaktion → npcID
-- (gesperrte Namen und GUIDs zählen nicht, Leitlinie 6)
function Discovery.CorpseNpc(name)
    if type(name) ~= "string" or name == "" then return nil end
    for _, unit in ipairs({ "target", "mouseover", "softinteract" }) do
        local uname = Core.Call(G("UnitName"), unit)
        if not IsSecret(uname) and Plain(uname) == name then
            local id = Core.NpcID(Plain(Core.Call(G("UnitGUID"), unit)))
            if id then return id end
        end
    end
    return nil
end

-- Name des Interaktionsziels („softinteract“), wenn es ein Spielobjekt ist → Name oder nil; als zweiten Wert true, wenn
-- Name oder Kennung gesperrt sind (dann weder vergleichen noch schreiben, Leitlinie 6). Ein Gegner oder Spieler als
-- Interaktionsziel kann kein Vorkommen und keine Kiste sein: dann nil, false und als dritten Wert true (es gibt ein
-- Interaktionsziel, aber keines, dem die Meldung gelten kann – Gegenprüfung kern/sammel-reste).
function Discovery.SoftName()
    local name = Core.Call(G("UnitName"), "softinteract")
    if IsSecret(name) then return nil, true end
    name = Plain(name)
    if type(name) ~= "string" or name == "" then return nil end
    local guid = Core.Call(G("UnitGUID"), "softinteract")
    if IsSecret(guid) then return nil, true end
    if Keys.Guid(guid) ~= "GameObject" then return nil, false, true end
    return name
end

-- Passt das Interaktionsziel name zur Art einer Meldung kind (Discovery.SOFT_KINDS)? → true (gespeicherte Art passt),
-- false (gespeicherte Art passt nicht – etwa eine Erzader oder Kiste bei „Benötigt Kräuterkunde“), nil (Objekt ohne
-- gespeicherte Art oder ohne lesbare Kennung, etwa ein Briefkasten); als zweiten Wert die Objekt-ID
function Discovery.SoftFits(name, kind)
    local kinds = Discovery.SOFT_KINDS[kind]
    if type(kinds) ~= "table" then return false end
    local T = Core.Tooltip
    local id = T and T.SoftObjectID and Num(T.SoftObjectID(name))
    if not id then return nil end
    local row = DB.Get("obj", id)
    local objKind = type(row) == "table" and row.kind or nil
    if objKind == nil then return nil, id end
    return kinds[objKind] == true, id
end

-- Rest c aus dem Review zu kern/sammel-fertigkeit: ist das Ziel von „Schloss knacken“ eine Schließkassette (ein
-- Gegenstand in der Tasche) statt einer Kiste? Zuerst die Namen der Gegenstände, die ezCore kennt (DB.ItemByName,
-- wie bisher OnLockPicked), sonst der Client (GetItemInfoInstant kennt Gegenstände in Taschen und Zwischenspeicher
-- auch über den Namen), dann aber nur mit einem Schloss für Schlossknacken laut Client-Tabellen (Gathering.RequiredItem)
function Discovery.IsLockbox(name)
    if IsSecret(name) or type(name) ~= "string" or name == "" then return false end
    if DB.ItemByName and DB.ItemByName(name) then return true end
    local itemID = Num((Core.ItemInstant(name, G("C_Item"))))   -- ezCores Umhüllung (T16-16)
    local Ga = Core.Gathering
    return itemID ~= nil and type(Ga) == "table" and type(Ga.RequiredItem) == "function" and Ga.RequiredItem(itemID) ~= nil
end

-- Welle 27 (F4 b): nötige Kürschner-Fertigkeit je Gegner (npc[npcID].skill, Form wie obj.skill)
function Discovery.NoteNpcSkill(npc, skill)
    npc = Num(npc)
    if not npc or type(skill) ~= "table" or next(skill) == nil then return end
    ForgetQuiet("npc", npc, skill)
    DB.Observe("npc", npc, { skill = skill })
end

-- Fehlschlag beim Sammeln, den der Client als „Rang zu niedrig“ meldet: die Zahl laut Meldung, ohne Zahl der eigene
-- Rang als obere Schranke des Nicht-Könnens. Andere Fehlschläge (Bewegung, Reichweite, Knoten belegt) lehren nichts.
-- Welle 27 (F4 b): Kürschnern schreibt an den Gegner, Kisten an das Ziel von „Schloss knacken“ bzw. „Öffnen“.
-- Rangfolge der Quellen (Funde des code-reviewers vor dem Merge von kern/sammel-reste, 17.11.2026; Doku:
-- docs/datengrundlage.md, „Fehlschlag beim Sammeln“):
--   1. Art: der Name des Berufs in der Meldung (Core.Gathering.KindOfSkillName). Nennt sie einen Namen, der keine
--      Sammel-Art ist („Benötigt Schlüssel“, „Benötigt Ingenieurskunst (150)“), lehrt sie nichts. Ohne Namen gilt die
--      Art des jüngsten eigenen Zaubers: „Schloss knacken“ jünger als der letzte Sammel-Zauber ergibt die Kiste.
--   2. Ziel des eigenen Zaubers (UNIT_SPELLCAST_SENT, höchstens Discovery.CONTEXT_SECONDS alt), aber nur eines Zaubers
--      derselben Art (Discovery.SpellTarget): Kräuterkunde nur nach „Kräuter sammeln“, Bergbau nur nach „Bergbau“,
--      Schlossknacken nach „Schloss knacken“ oder „Öffnen“ – bei beiden der jüngere. Sonst landete „Benötigt Bergbau“
--      am eben geernteten Kraut und ein altes „Schloss knacken“ an der vorigen Kiste.
--   3. Ist der Zauber höchstens Discovery.FRESH_SECONDS alt, gilt sein Ziel – das Interaktionsziel wird nicht befragt,
--      auch ein gesperrtes nicht. Ein frischer Zauber ist der Klick, auf den der Client antwortet (während eines Zaubers
--      meldet er „beschäftigt“).
--   4. Sonst: gesperrter Name oder gesperrte Kennung des Interaktionsziels (Discovery.SoftName): nichts (Leitlinie 6).
--   5. Sonst das Interaktionsziel („softinteract“), denn ob vor der Meldung überhaupt UNIT_SPELLCAST_SENT kommt, ist
--      ungeprüft (Rest a): fehlt es oder trägt es denselben Namen, das Ziel des Zaubers; ein Gegner oder Spieler:
--      niemand; ein anderer Name: das Interaktionsziel, wenn seine gespeicherte Art zur Meldung passt
--      (Discovery.SoftFits: Kräuter zu herb, Erz zu mine, Kisten zu chest oder container), nur unter seinem Namen
--      vorgemerkt, wenn es keine gespeicherte Art hat (mit der Art der Meldung: er gilt erst bei Ernte bzw. Beute eines
--      Objekts passender Art, NoteObjName – ein Briefkasten bekommt so nie einen Wert), niemand bei unpassender Art.
--   6. Schließkassetten (Gegenstände in der Tasche) zählen nie (Discovery.IsLockbox, Rest c).
Discovery.SOFT_KINDS = { herb = { herb = true }, ore = { mine = true }, chest = { chest = true, container = true } }
Discovery.FRESH_SECONDS = 1

-- Rangfolge 2: gemerkter Zauber derselben Art wie die Meldung kind → Zauber oder nil (s: Sammel-Zauber, lk: „Schloss
-- knacken“, beide schon auf Discovery.CONTEXT_SECONDS geprüft)
function Discovery.SpellTarget(kind, s, lk)
    if kind == "chest" then
        local open = s and s.kind == "open" and s or nil
        if lk and open then return open.at > lk.at and open or lk end
        return lk or open
    end
    return s and Discovery.SENT_SKILL[s.kind] == kind and s or nil
end

local function GatherFailed(rankFromClient, named, hasName)
    if not DB.Collecting() then return end
    if hasName and not named then return end
    local s, lk = Recent(sent), Recent(lockSent)
    local kind = named
    if not kind then
        local sk = s and Discovery.SENT_SKILL[s.kind] or nil
        if lk and (not sk or lk.at >= s.at) then
            kind = "chest"                          -- Meldung ohne Namen direkt nach „Schloss knacken“
        else
            kind = sk
        end
    end
    if not kind then return end
    local skill
    if rankFromClient then
        skill = { req = rankFromClient, cnt = 1 }
    else
        local rank = Discovery.OwnRank(kind)
        if not rank then return end
        skill = { hi = rank, cnt = 1 }
    end
    if kind == "skin" then
        local npc = s and s.kind == "skin" and Discovery.CorpseNpc(s.name)
        if npc then Discovery.NoteNpcSkill(npc, skill) end
        return
    end
    local target = Discovery.SpellTarget(kind, s, lk)
    local fresh = target and Core.Uptime() - target.at <= Discovery.FRESH_SECONDS
    if not fresh then
        local soft, locked, other = Discovery.SoftName()
        if locked or other then return end
        if soft and not (target and target.name == soft) then
            local fits = Discovery.SoftFits(soft, kind)
            if not fits then
                -- unbekannte Art: nur unter dem Namen vormerken; unpassende Art: niemandem
                if fits == nil and Discovery.SOFT_KINDS[kind] and not (kind == "chest" and Discovery.IsLockbox(soft)) then
                    Pending(soft, skill, kind)
                end
                return
            end
            target = { name = soft }
        end
    end
    if not (target and target.name) then return end
    if kind == "chest" and Discovery.IsLockbox(target.name) then return end
    -- mehrdeutiger Name ohne Interaktionsziel: verwerfen (eine Kiste, deren Schloss scheitert, wird nicht geplündert –
    -- die Vormerkung träfe eine andere Kiste gleichen Namens); unbekannter Name: wartet bis zur Beute (NoteObjName)
    local id, dup = TargetObject(target.name)
    if id then NoteSkill(id, skill) elseif not dup then Pending(target.name, skill) end
end

-- Erfolg von „Schloss knacken“: der eigene Rang reicht (Schranke nach oben, wie eine Ernte). Ziel ist ein Spielobjekt;
-- eine Schließkassette (Gegenstand gleichen Namens) steht in den Client-Tabellen (Gathering.RequiredItem) und zählt
-- nicht – dieselbe Sperre wie bei einem Fehlschlag (Discovery.IsLockbox).
function Discovery.OnLockPicked()
    local lk = Recent(lockSent)
    if not (lk and lk.name and DB.Collecting()) then return end
    if Discovery.IsLockbox(lk.name) then return end
    local rank = Discovery.OwnRank("chest")
    if not rank then return end
    local skill = { lo = rank, cnt = 1 }
    local id, dup = TargetObject(lk.name)
    if id then NoteSkill(id, skill) elseif not dup then Pending(lk.name, skill) end   -- mehrdeutig: verwerfen
end

-- Nur die Meldung des Clients zählt (UNIT_SPELLCAST_FAILED nennt keinen Grund; Gegenprüfung Welle 12)
ns.On("UI_ERROR_MESSAGE", function(_, _, message)
    local res, name = Discovery.SkillErrorOf(message)
    if res == nil then return end
    local Ga = Core.Gathering
    local named = name and Ga and Ga.KindOfSkillName and Ga.KindOfSkillName(name) or nil
    if res == true then GatherFailed(nil, named, name ~= nil) else GatherFailed(res, named, name ~= nil) end
end)

-- Welle 27 (F4 b): dieselbe Zeile „Benötigt <Beruf> (<Rang>)“ im Tooltip eines Spielobjekts bzw. eines Gegners – nur
-- gelesen, der Tooltip bleibt unverändert. Ein Wert aus dem Tooltip zählt nicht als Beobachtung (cnt bleibt) und wird nur
-- geschrieben, wenn er sich ändert. Gesperrte Zeilen zählen nicht (Leitlinie 6).
Discovery.TOOLTIP_LINES = 12
local function LineTexts(tooltip, data)
    local out = {}
    local lines = type(data) == "table" and not IsSecret(data) and data.lines or nil
    if type(lines) == "table" and not IsSecret(lines) then
        for i = 2, math.min(#lines, Discovery.TOOLTIP_LINES) do
            local l = lines[i]
            local text = type(l) == "table" and not IsSecret(l) and Plain(l.leftText) or nil
            if type(text) == "string" and text ~= "" then out[#out + 1] = text end
        end
        return out
    end
    local frame = type(tooltip) == "table" and tooltip.GetName and Plain(tooltip:GetName()) or nil
    for i = 2, Discovery.TOOLTIP_LINES do
        local fs = type(frame) == "string" and G(frame .. "TextLeft" .. i) or nil
        local text = type(fs) == "table" and fs.GetText and Plain(fs:GetText()) or nil
        if type(text) == "string" and text ~= "" then out[#out + 1] = text end
    end
    return out
end
Discovery.TooltipTexts = LineTexts

-- → Rang, Art (herb, ore, fish, skin, chest) aus der ersten Zeile mit Zahl und bekanntem Beruf, sonst nil
function Discovery.SkillFromTooltip(tooltip, data)
    local Ga = Core.Gathering
    for _, text in ipairs(LineTexts(tooltip, data)) do
        local rank, name = Discovery.SkillErrorOf(text)
        local kind = type(rank) == "number" and name and Ga and Ga.KindOfSkillName and Ga.KindOfSkillName(name)
        if kind then return rank, kind end
    end
    return nil
end

local function NoteQuiet(tbl, id, req)
    local key = tbl .. ":" .. tostring(id)
    if quietReq[key] == req then return false end
    local row = DB.Get(tbl, id)
    local old = type(row) == "table" and type(row.skill) == "table" and Num(row.skill.req) or nil
    if quietN >= Discovery.QUIET_MAX then quietReq, quietN = {}, 0 end
    if quietReq[key] == nil then quietN = quietN + 1 end
    quietReq[key] = req
    if old == req then return false end
    DB.Observe(tbl, id, { skill = { req = req } })
    return true
end

-- objectID aus Core.Tooltip.ObjectID fällt auf das erste Objekt des Namens zurück; geschrieben wird nur an eine sichere
-- Kennung (Interaktion oder einziges Objekt des Namens, TargetObject). Mehrdeutig: nichts; unbekannt: wartet unter dem Namen.
function Discovery.OnObjectTooltip(tooltip, name, data, objectID)
    if not DB.Collecting() then return end
    local rank, kind = Discovery.SkillFromTooltip(tooltip, data)
    if not rank or kind == "skin" then return end
    local id, dup = TargetObject(name)
    if id then NoteQuiet("obj", id, rank) elseif not dup then Pending(name, { req = rank }) end
end

function Discovery.OnUnitTooltip(tooltip, unit, data)
    if not DB.Collecting() or IsSecret(unit) or type(unit) ~= "string" then return end
    local guid = type(data) == "table" and not IsSecret(data) and Plain(data.guid) or nil
    local npc = Core.NpcID(guid or Plain(Core.Call(G("UnitGUID"), unit)))
    if not npc then return end
    local leather = G("UNIT_SKINNABLE_LEATHER")
    local Ga = Core.Gathering
    for _, text in ipairs(LineTexts(tooltip, data)) do
        if type(leather) == "string" and not IsSecret(leather) and text == leather and Ga and Ga.NoteSkinnable then
            Ga.NoteSkinnable(npc)
        end
        local rank, name = Discovery.SkillErrorOf(text)
        if type(rank) == "number" and name and Ga and Ga.KindOfSkillName and Ga.KindOfSkillName(name) == "skin" then
            NoteQuiet("npc", npc, rank)
        end
    end
end

if Core.Tooltip and Core.Tooltip.AddObjectSection then
    Core.Tooltip.AddObjectSection("ezCore.skillRead", 1, function(...) Discovery.OnObjectTooltip(...) end, "ezCore")
end
if Core.Tooltip and Core.Tooltip.AddUnitSection then
    Core.Tooltip.AddUnitSection("ezCore.skillRead", 1, function(...) Discovery.OnUnitTooltip(...) end, "ezCore")
end

local function TargetLevel(guid)
    for _, unit in ipairs({ "target", "mouseover" }) do
        if Plain(Core.Call(G("UnitGUID"), unit)) == guid then
            return Num(Core.Call(G("UnitLevel"), unit)), unit
        end
    end
end

local function SourceOf(r, where, ctx, fishing)
    local kind, id = Keys.Source(r.guid, { fishing = fishing, corpse = ctx and CORPSE[ctx.kind], map = where.map,
        spell = ctx and ctx.spell, name = ctx and ctx.name })
    -- SAM-01: Sammelzauber ohne lesbare GameObject-GUID » Notschlüssel Art + Hauptertrag (gekennzeichnet)
    if kind == "unknown" and not fishing and not r.guid and ctx and (ctx.kind == "herb" or ctx.kind == "mine") then
        local fb = Keys.GatherFallback(ctx.kind, MainItem(r.items))
        if fb then return "object", fb end
    end
    return kind, id
end

-- SAM-05: Schwarm beim Angeln. Ein Schwarm ist ein fester Spawn: dieselbe GameObject-GUID liefert mehrere Fänge. Der
-- Schwimmer entsteht dagegen je Wurf neu (neue GUID) – nennt der Client ihn als Beutequelle (Probe G13 rechnet damit),
-- wird er so nie zum Schwarm, auch ein Spielzeug-Schwimmer mit anderer Objekt-Nummer nicht. Die Nummer des
-- gewöhnlichen Schwimmers (Discovery.FISHING_BOBBERS) ist zusätzlich ausgeschlossen. Erst der zweite Fang aus
-- derselben GUID zählt den Schwarm, dann gleich mit beiden Fängen. → objectID, Zählung, Angel-Rang beim ersten Fang
-- oder nil. rank: eigener Angel-Rang bei diesem Fang; der des ersten Fangs wird bis zum zweiten gemerkt (Rest d aus dem
-- Review zu kern/sammel-fertigkeit: skill.cnt zählte erst ab dem zweiten Fang – „bei dir 1×“ nach zwei Fängen)
Discovery.FISHING_BOBBERS = { [35591] = true }
local poolSeen, poolSeenN = {}, 0
local function PoolOf(guid, rank)
    local gk, gid = Keys.Guid(guid)
    if not (gk == "GameObject" and gid and gid > 0) or Discovery.FISHING_BOBBERS[gid] then return nil end
    local seen = poolSeen[guid]
    if seen == "pool" then return gid, 1 end
    if seen then
        poolSeen[guid] = "pool"
        return gid, 2, type(seen) == "number" and seen or nil
    end
    if poolSeenN >= DB.LIMITS.SESSION_MAX then poolSeen, poolSeenN = {}, 0 end
    poolSeen[guid], poolSeenN = Num(rank) or true, poolSeenN + 1
    return nil
end

-- Kleinste und größte Menge je BESUCH (Welle 14, Spielbefund vom 15.11.2026: eine Ader in zwei Schlägen geleert
-- ergab f = 3, s = 4, aber hi = 1 – lo/hi galten je Beutefenster). Beim ersten Fenster eines Besuchs merkt sich
-- Discovery die bisherigen lo/hi des Zählblocks (visitYield); jeder weitere Schlag schreibt lo/hi des Zählblocks aus
-- diesen Werten und der Summe des Besuchs neu (DB.Change): lo = min(vorher, Summe), hi = max(vorher, Summe). Bestehende
-- Sätze bleiben gültig (gleiche Felder, keine neue Datenversion). Grenze: Wartet das erste Fenster noch in der
-- Warteschlange der Datenbank (Ernte im Kampf), bleibt es bei lo/hi je Fenster.
local visitYield, visitYieldN = {}, 0

function Discovery.VisitStart(guid, id, diff, items)
    if type(guid) ~= "string" or id == nil then return nil end
    if visitYieldN >= DB.LIMITS.SESSION_MAX then visitYield, visitYieldN = {}, 0 end
    local before = {}
    local row = DB.Get("drops", "object", id)
    local block = type(row) == "table" and type(row.diff) == "table" and row.diff[diff]
    for itemID, it in pairs(type(block) == "table" and type(block.items) == "table" and block.items or {}) do
        if type(it) == "table" then before[itemID] = { lo = Num(it.lo), hi = Num(it.hi) } end
    end
    local totals = {}
    for itemID, qty in pairs(items or {}) do totals[itemID] = qty end
    if not visitYield[guid] then visitYieldN = visitYieldN + 1 end
    visitYield[guid] = { id = id, diff = diff, before = before, items = totals }
    return visitYield[guid]
end

-- lo/hi des Zählblocks aus dem Besuch v neu schreiben → true, wenn der Satz da war
function Discovery.VisitRange(v)
    if type(v) ~= "table" then return false end
    return DB.Change("drops", { "object", v.id }, function(row)
        local block = type(row.diff) == "table" and row.diff[v.diff]
        local items = type(block) == "table" and block.items
        if type(items) ~= "table" then return end
        for itemID, total in pairs(v.items) do
            local it, old = items[itemID], v.before[itemID]
            if type(it) == "table" then
                it.lo = (old and old.lo) and math.min(old.lo, total) or total
                it.hi = (old and old.hi) and math.max(old.hi, total) or total
            end
        end
    end)
end

-- Weitere Beute aus derselben Objekt-GUID im selben Besuch: nur Ertrag (Summe je Gegenstand), keine neue Ernte; ein
-- Gegenstand, der erst in diesem Schlag fällt, zählt als Fund (f) dieses Besuchs
local function AddYield(r, id, where)
    local items = {}
    local v = r.guid and visitYield[r.guid]
    if v and v.id ~= id then v = nil end
    for itemID, qty in pairs(r.items) do
        items[itemID] = { s = qty }
        if v then
            local prev = v.items[itemID] or 0
            if prev == 0 then items[itemID].f = 1 end
            v.items[itemID] = prev + qty
        end
    end
    if next(items) == nil then return end
    local _, queued = DB.Observe("drops", { "object", id }, { diff = { [where.diff] = { items = items } } })
    if v and queued ~= "queued" then Discovery.VisitRange(v) end
    local row = DB.Get("obj", id)
    Discovery.Harvested(id, type(row) == "table" and row.kind, where, r.items, false)
end

-- SAM-09 (Welle 13): jede eigene Ernte an Core.Gathering melden (Sitzungsliste „eben geerntet“, Sammel-Zähler an
-- Core.Session). harvest = false: weiterer Ertrag aus demselben Besuch, keine neue Ernte. Nur Sammel-Arten.
local HARVEST_KINDS = { herb = true, mine = true, pool = true, fishing = true }
function Discovery.Harvested(id, objKind, where, items, harvest)
    if not HARVEST_KINDS[objKind] then return end
    local copy = {}
    for itemID, qty in pairs(items or {}) do copy[itemID] = qty end
    Core.Fire("GATHERING_HARVEST", { id = id, kind = objKind == "fishing" and "fish" or objKind,
        map = where and where.map, inst = where and where.inst, items = copy, harvest = harvest ~= false })
end

local function CountSource(r, kind, id, where, ctx, fishing, inGroup)
    if not kind then return end   -- Spieler und Begleiter hinterlassen nichts
    if kind == "container" and ctx and ctx.kind == "salvage" then
        -- Zerlegen zählt ohne party: das Ergebnis hängt nicht an der Gruppe, und ezCraft (Sal.Own) rechnet
        -- „so oft zerlegt“ als cnt + party – mit cnt und party zugleich zählte ein Zerlegen in der Gruppe doppelt
        -- (Gegenprüfung Welle 23c zu A64).
        DB.Observe("salvage", { ctx.spell, id }, Block(r, false))
        return
    end
    local block = Block(r, inGroup)
    local keys
    if kind == "fishing" or kind == "unknown" then
        keys = { kind, where.map or 0, Keys.Area() }
    elseif id then
        keys = { kind, id }
    else
        return
    end
    DB.Observe("drops", keys, { diff = { [where.diff] = block } })
    if kind == "object" then
        local objKind = ObjKind(ctx, r.items, fishing, { quest = r.quest, money = r.hasMoney,
            tokens = next(r.tokens) ~= nil })
        local before = DB.Get("obj", id)
        objKind = Discovery.MergeKind(type(before) == "table" and before.kind or nil, objKind)
        local f = { kind = objKind, cnt = 1 }
        if objKind == "quest" and r.questID then f.quest = r.questID end
        if objKind ~= "quest" and type(before) == "table" and before.quest ~= nil then
            DB.Change("obj", { id }, function(row) row.quest = nil end)
        end
        -- SAM-04: Erfolg mit dem eigenen Rang ist eine Schranke nach oben (kleinster Rang, mit dem es ging); cnt zählt
        -- die Beobachtung (Welle 27). Kisten: nur nach „Schloss knacken“ (Discovery.OnLockPicked) – Öffnen allein sagt nichts.
        local rank = (objKind == "herb" or objKind == "mine") and Discovery.OwnRank(objKind)
        if rank then f.skill = { lo = rank, cnt = 1 } end
        DB.Observe("obj", id, f)
        if not where.inst then Place(where.map, "object", id, 2) end
        if ctx and ctx.name then NoteObjName(id, ctx.name, objKind) end
        if not Keys.IsFallback(id) and (objKind == "herb" or objKind == "mine") then
            local fb = Keys.GatherFallback(objKind, MainItem(r.items))
            if fb and DB.Get("obj", fb) then Discovery.MergeGatherFallback(fb, id) end
        end
        Discovery.Harvested(id, objKind, where, r.items, true)
    elseif kind == "fishing" then
        -- SAM-05: Fang-Position je Gebiet; nennt die Beutequelle einen Schwarm (Spielobjekt), zählt er als Objekt
        if not where.inst then Place(where.map, "fishing", keys[3], 2) end
        Discovery.Harvested(keys[3], "fishing", where, r.items, true)
        -- Welle 27 (F4 b): ein Fang am Schwarm mit dem eigenen Angel-Rang ist eine Schranke nach oben. Sobald der zweite
        -- Fang den Schwarm belegt, zählt der erste mit: skill.cnt wie cnt (je Fang mit bekanntem Rang), lo der kleinere
        -- Rang beider Fänge
        local rank = Discovery.OwnRank("fish")
        local pool, n, firstRank = PoolOf(r.guid, rank)
        if pool then
            local lo = rank and firstRank and math.min(rank, firstRank) or rank or firstRank
            local seen = (rank and 1 or 0) + (firstRank and 1 or 0)
            DB.Observe("obj", pool, { kind = "pool", cnt = n, skill = lo and { lo = lo, cnt = seen } or nil })
            if not where.inst then Place(where.map, "object", pool, 2) end
        end
    elseif kind == "skin" then
        -- Welle 27 (F4 b): Kürschnern gelang mit dem eigenen Rang – Schranke nach oben je Gegner (npc.skill)
        local rank = Discovery.OwnRank("skin")
        if rank then Discovery.NoteNpcSkill(id, { lo = rank, cnt = 1 }) end
    elseif kind == "loot" then
        local level, unit = TargetLevel(r.guid)
        if level and level > 0 then DB.Observe("npc", id, { lvls = { lo = level, hi = level } }) end
        if unit then DB.SetText("npc", id, Core.Call(G("UnitName"), unit)) end
        if not where.inst then Place(where.map, "npc", id, 2) end
    end
end

function Discovery.OnLootReady()
    if not DB.Collecting() then return end
    local n = Num(Core.Call(G("GetNumLootItems"))) or 0
    local fishing = Core.Bool(Core.Call(G("IsFishingLoot")), false) == true
    local ctx = TakeContext()
    local map = Keys.PlayerSpot()
    local where = { map = map, inst = Keys.Instance8(), diff = Keys.Difficulty() }
    local recs, list = {}, {}
    local function Rec(guid)
        local key = guid or "~"
        local r = recs[key]
        if not r then
            r = { guid = guid, items = {}, tokens = {}, money = 0, hasMoney = false, quest = false }
            recs[key] = r
            list[#list + 1] = r
        end
        return r
    end
    for slot = 1, n do
        local slotType = Num(Core.Call(G("GetLootSlotType"), slot))
        local _, _, quantity, currencyID, _, _, isQuestItem, questID = Core.Call(G("GetLootSlotInfo"), slot)
        isQuestItem = Core.Bool(isQuestItem, false) == true
        questID = Num(questID)
        if questID and questID <= 0 then questID = nil end
        quantity = Num(quantity)
        local itemID, cur
        if slotType == LOOT_CURRENCY then
            cur = Num(currencyID)
        elseif slotType ~= LOOT_MONEY then
            itemID = Core.ItemID(Plain(Core.Call(G("GetLootSlotLink"), slot)))
        end
        local src = SourcesOf(slot)
        if #src == 0 then src = { false, quantity } end
        for i = 1, #src, 2 do
            local guid = Plain(src[i])
            if type(guid) ~= "string" or guid == "" then guid = nil end
            local qty = Num(src[i + 1]) or quantity or 1
            local r = Rec(guid)
            if slotType == LOOT_MONEY then
                r.money, r.hasMoney = r.money + qty, true
            elseif cur then
                r.tokens[cur] = (r.tokens[cur] or 0) + qty
            elseif itemID then
                r.items[itemID] = (r.items[itemID] or 0) + math.max(1, qty)
                if isQuestItem or questID then r.quest = true end
                if questID then r.questID = questID end
            end
        end
    end
    -- Ein Fenster mit 0 Plätzen bei bekanntem, totem Ziel: „leer“ (Probe: nie allein aus UNIT_LOOT ableiten)
    if n == 0 and Core.Bool(Core.Call(G("UnitIsDead"), "target"), false) == true then
        local guid = Plain(Core.Call(G("UnitGUID"), "target"))
        if type(guid) == "string" then Rec(guid) end
    end
    local inGroup = Core.Bool(Core.Call(G("IsInGroup")), false) == true
    local now = Core.Uptime()
    local gathered = ctx and (ctx.kind == "herb" or ctx.kind == "mine")
    for _, r in ipairs(list) do
        local key = r.guid or "~open"
        local kind, id = SourceOf(r, where, ctx, fishing)
        -- Angeln: jedes Fenster ist ein eigener Fang, auch aus demselben Schwarm (LOOT_READY-Wiederholungen fängt opening ab)
        local once = r.guid and kind ~= "fishing" and ((kind or "-") .. "|" .. r.guid)
        local visit = kind == "object" and r.guid and visits[r.guid]
        if not opening[key] and visit and now - visit <= DB.LIMITS.VISIT_SECONDS then
            -- SAM-01: derselbe Besuch – keine neue Ernte. Ertrag nur nach einem neuen Sammelzauber (ein Erzvorkommen
            -- wird mehrfach abgebaut); ein erneut geöffnetes Fenster ohne neuen Zauber zählt dieselbe Beute nicht noch einmal.
            opening[key] = true
            if gathered then AddYield(r, id, where) end
        elseif not opening[key] and not (once and counted[once] and not visit) then
            opening[key] = true
            if kind == "object" and r.guid then
                if visitsN >= DB.LIMITS.SESSION_MAX then visits, visitsN = {}, 0 end
                if not visits[r.guid] then visitsN = visitsN + 1 end
                visits[r.guid] = now
                -- vor dem ersten Schreiben: bisherige lo/hi merken (Menge je Besuch, Welle 14)
                if id ~= nil then Discovery.VisitStart(r.guid, id, where.diff, r.items) end
            end
            if once then countedN = Remember(counted, countedN, once) end
            CountSource(r, kind, id, where, ctx, fishing, inGroup)
            for itemID in pairs(r.items) do
                Reveal(itemID, 1)
                local books = Core.Collections and Core.Collections.BOOK_ITEMS
                if books and books[itemID] then
                    DB.Observe("book", itemID, { cnt = 1 })
                    Place(map, "book", itemID, 2)
                end
            end
        end
    end
end

ns.On("LOOT_READY", function() Core.Try(nil, "Discovery.Loot", Discovery.OnLootReady) end)
ns.On("LOOT_CLOSED", function() opening, openCtx = {}, nil end)

-- Tode: eigene Kills und die der Gruppe (nicht UNIT_DIED: das zählt fremde Tode in der Nähe mit)
local killed, killedN = {}, 0
function Discovery.OnPartyKill(_, _, targetGUID)
    if not DB.Collecting() or IsSecret(targetGUID) or type(targetGUID) ~= "string" or killed[targetGUID] then return end
    local kind, id = Keys.Guid(targetGUID)
    if not ((kind == "Creature" or kind == "Vehicle") and id) then return end
    killedN = Remember(killed, killedN, targetGUID)
    DB.Observe("drops", { "loot", id }, { diff = { [Keys.Difficulty()] = { deaths = 1 } } })
end
ns.On("PARTY_KILL", function(...) Core.Try(nil, "Discovery.Kill", Discovery.OnPartyKill, ...) end)

---------------------------------------------------------------------------
-- Händler und Lehrer (DG-05)
---------------------------------------------------------------------------

local function MerchantFilterAll()
    local fn = G("GetMerchantFilter")
    if type(fn) ~= "function" then return true end
    local ok, f = pcall(fn)
    local all = G("LE_LOOT_FILTER_ALL")
    return ok and all ~= nil and f == all
end

function Discovery.ScanVendor()
    if not DB.Collecting() then return false end
    local npc = Keys.Npc("npc")
    if not npc then return false end
    local num = Num(Core.Call(G("GetMerchantNumItems"))) or 0
    if num <= 0 then return false end
    local now, build = DB.Stamp(), Keys.Build()
    local w, complete = {}, true
    local MF = G("C_MerchantFrame")
    for i = 1, num do
        local itemID = Num(Core.Call(G("GetMerchantItemID"), i))
        local price, stack, avail
        if type(MF) == "table" and type(MF.GetItemInfo) == "function" then
            local ok, info = pcall(MF.GetItemInfo, i)
            if ok and type(info) == "table" and not IsSecret(info) then
                price, stack, avail = Num(info.price), Num(info.stackCount), Num(info.numAvailable)
            end
        elseif type(G("GetMerchantItemInfo")) == "function" then
            local _, _, p, q, a = Core.Call(G("GetMerchantItemInfo"), i)
            price, stack, avail = Num(p), Num(q), Num(a)
        end
        if itemID and price then
            w[itemID] = { pr = price, per = stack or 1, lim = (avail and avail >= 0) and avail or false, t = now, b = build }
            Reveal(itemID, 2)
        else
            complete = false
        end
    end
    local fields = { w = w }
    if complete and MerchantFilterAll() then fields.tf = now end
    DB.Observe("vendor", npc, fields)
    local roles = { "vendor" }
    if Core.Bool(Core.Call(G("CanMerchantRepair")), false) == true then roles[2] = "repair" end
    NoteNpc(npc, roles)
    return true
end

local TRAINER_TYPE = { class = 1, profession = 2, pet = 3, other = 3 }
Discovery.TRAINER_TYPE = TRAINER_TYPE

-- Tierausbilder laut Client (C_Trainer.GetTrainerType() == Enum.TrainerType.Pet; wie Spells.lua)
function Discovery.IsPetTrainer()
    local api = G("C_Trainer")
    local pet = Enum and Enum.TrainerType and Enum.TrainerType.Pet
    if pet == nil or type(api) ~= "table" or type(api.GetTrainerType) ~= "function" then return false end
    local ok, kind = pcall(api.GetTrainerType)
    return ok and not IsSecret(kind) and kind == pet
end

-- spellID eines Eintrags im offenen Lehrerfenster (C_TooltipInfo.GetTrainerService) oder nil. Seit Welle 23c (A45)
-- öffentlich als Core.TrainerSpellID(index) – gilt auch ohne Entdecker-Datenbank (Discovery.lua lädt immer).
local function TrainerSpellID(index)
    local api = G("C_TooltipInfo")
    index = Num(index)
    if not (index and type(api) == "table" and type(api.GetTrainerService) == "function") then return nil end
    local ok, data = pcall(api.GetTrainerService, index)
    if not ok or IsSecret(data) or type(data) ~= "table" then return nil end
    local spellType = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Spell or 1
    if Num(data.type) == spellType then return Num(data.id) end
    return nil
end
Discovery.TrainerSpellID = TrainerSpellID
Core.TrainerSpellID = TrainerSpellID

local function TrainerFilterAll()
    local fn = G("GetTrainerServiceTypeFilter")
    if type(fn) ~= "function" then return false end
    for _, kind in ipairs({ "available", "unavailable", "used" }) do
        local ok, on = pcall(fn, kind)
        if not ok or not on or IsSecret(on) then return false end
    end
    return true
end

function Discovery.ScanTrainer()
    if not DB.Collecting() then return false end
    local npc = Keys.Npc("npc")
    local num = Num(Core.Call(G("GetNumTrainerServices"))) or 0
    if not npc or num <= 0 then return false end
    local e = Core.Npcs and Core.Npcs.Get and Core.Npcs.Get(npc)
    local N = Core.Npcs
    local kind = N and N.TrainerKind and N.TrainerKind((N.Subtitle and N.Subtitle()) or (e and e.title)) or "other"
    if kind ~= "profession" and Discovery.IsPetTrainer() then kind = "pet" end
    local who
    if kind == "class" or kind == "pet" then who = Core.PlayerClass() elseif kind == "profession" then who = 0 end
    local art = Keys.Offer(kind, who)
    if not art then return false end
    local now, build = DB.Stamp(), Keys.Build()
    local svc, found = {}, 0
    for i = 1, num do
        local name, serviceType, icon, reqLevel, subText = Core.Call(G("GetTrainerServiceInfo"), i)
        name, serviceType = Plain(name), Plain(serviceType)
        if type(name) == "string" and name ~= "" and serviceType and serviceType ~= "header" then
            local rank = Core.Spells and Core.Spells.ParseRank and Core.Spells.ParseRank(subText) or 0
            local _, key = Keys.Offer(kind, who, TrainerSpellID(i), name, rank)
            if key then
                local money, talent = Core.Call(G("GetTrainerServiceCost"), i)
                local _, skill = Core.Call(G("GetTrainerServiceSkillReq"), i)
                local s = { rank = Num(rank) or 0, lvl = Num(reqLevel), pr = Num(money), at = { [npc] = now }, t = now, b = build }
                if (Num(talent) or 0) > 0 then s.tp = talent end
                if (Num(skill) or 0) > 0 then s.skill = skill end
                if Num(icon) then s.ic = icon end
                svc[key] = s
                found = found + 1
            end
        end
    end
    if found == 0 then return false end
    local fields = { svc = svc }
    if TrainerFilterAll() then fields.tf = now end
    DB.Observe("offer", art, fields)
    NoteNpc(npc, { "trainer" }, { tr = TRAINER_TYPE[kind] or 3, tk = art })
    return true
end

local scanVendor = Core.Throttle(function() Discovery.ScanVendor() end, 0.3, "ezCore")
local scanTrainer = Core.Throttle(function() Discovery.ScanTrainer() end, 0.3, "ezCore")
ns.On("MERCHANT_SHOW", scanVendor)
ns.On("MERCHANT_UPDATE", scanVendor)
ns.On("TRAINER_SHOW", scanTrainer)
ns.On("TRAINER_UPDATE", scanTrainer)

---------------------------------------------------------------------------
-- Einheiten: Gegnerstufen je Karte, seltene Gegner (DG-08, Gebiet „Gegner-Stufen“)
---------------------------------------------------------------------------

local seenUnits, seenN = {}, 0
local RARE = { rare = true, rareelite = true }

function Discovery.OnUnit(unit)
    if not DB.Collecting() or type(unit) ~= "string" then return end
    local guid = Plain(Core.Call(G("UnitGUID"), unit))
    if type(guid) ~= "string" or seenUnits[guid] then return end
    local npc = Keys.Npc(unit)
    if not npc then return end
    seenN = Remember(seenUnits, seenN, guid)
    local level = Num(Core.Call(G("UnitLevel"), unit))
    local class = Plain(Core.Call(G("UnitClassification"), unit))
    local hostile = Core.Bool(Core.Call(G("UnitCanAttack"), "player", unit), false) == true
    local map = Keys.PlayerSpot()
    if level and level > 0 then
        DB.Observe("npc", npc, { lvls = { lo = level, hi = level } })
        if hostile and map and map > 0 then
            DB.Observe("zoneLv", map, { lo = level, hi = level, cnt = 1, hist = { [level] = 1 } })
        end
    end
    if type(class) == "string" and RARE[class] then
        local dead = Core.Bool(Core.Call(G("UnitIsDead"), unit), false) == true
        DB.Observe("rare", npc, { cnt = 1, sight = { { t = DB.Stamp(), map = map, dead = dead or nil } } })
        DB.Observe("npc", npc, { tier = class })
        Place(map, "npc", npc, 4)
        DB.SetText("npc", npc, Core.Call(G("UnitName"), unit))
    end
end

ns.On("NAME_PLATE_UNIT_ADDED", function(_, unit) Core.Try(nil, "Discovery.Unit", Discovery.OnUnit, unit) end)
ns.On("PLAYER_TARGET_CHANGED", function() Core.Try(nil, "Discovery.Unit", Discovery.OnUnit, "target") end)
ns.On("UPDATE_MOUSEOVER_UNIT", function() Core.Try(nil, "Discovery.Unit", Discovery.OnUnit, "mouseover") end)

---------------------------------------------------------------------------
-- Eingänge: letzte Außenposition vor dem Betreten (Probe: beim Kartenwechsel sind Karte und Position schon nil)
---------------------------------------------------------------------------

Discovery.OUTSIDE_SECONDS = 90
-- Nach einer Beschwörungs-Anfrage (sie gilt zwei Minuten) wird kein Eingang gelernt: man stünde sonst am Ort vor der
-- Beschwörung. Abgelehnt (CANCEL_SUMMON): die Sperre fällt weg.
Discovery.SUMMON_SECONDS = 120
local outside, lastInstance, summonAt

function Discovery.NoteOutside()
    if Keys.Instance8() then return end
    local map, xy = Keys.PlayerSpot()
    if map and map > 0 and xy then outside = { map = map, xy = xy, at = Core.Uptime() } end
end

-- Über die Gruppensuche hingebracht? Dann war die Außenposition nicht der Eingang.
local function ViaGroupFinder()
    for _, name in ipairs({ "IsInLFGDungeon", "IsPartyLFG" }) do
        if Core.Bool(Core.Call(G(name)), false) == true then return true end
    end
    return false
end

-- Passt die Außenkarte zum Gebiet mit dem Eingang (Dungeons.EntranceZone)? Verglichen wird mit der Karte und ihren
-- Elternkarten; ohne Gebiet in der Tabelle oder ohne Kartennamen gilt sie als passend (nichts zu prüfen).
local function OutsideFits(inst, map)
    local D = Core.Dungeons
    local zone = D and D.EntranceZone and D.EntranceZone(inst)
    if type(zone) ~= "string" or zone == "" or not (Core.Map and Core.Map.Info) then return true end
    zone = zone:lower()
    local known, id = false, map
    for _ = 1, 8 do
        local info = Core.Map.Info(id)
        if type(info) ~= "table" then break end
        local name = Plain(info.name)
        if type(name) == "string" and name ~= "" then
            known = true
            name = name:lower()
            if name:find(zone, 1, true) or zone:find(name, 1, true) then return true end
        end
        id = Num(info.parentMapID)
        if not id or id <= 0 then break end
    end
    return not known
end
Discovery.OutsideFits = OutsideFits

-- Welle 23c (A39): Name der Instanz je Sprache (GetInstanceInfo, erster Wert) in text.instance – vorher merkte ezMap
-- ihn selbst (ezMapDB.entranceNames). Discovery.InstanceName(instanceID) → Name, Sprache oder nil.
function Discovery.NoteInstanceName(inst)
    inst = Num(inst)
    if not inst or inst <= 0 then return false end
    local name = Plain(Core.Call(G("GetInstanceInfo")))
    if type(name) ~= "string" or name == "" then return false end
    return DB.SetText("instance", inst, name)
end

function Discovery.InstanceName(inst)
    inst = Num(inst)
    if not inst then return nil end
    return DB.Text("instance", inst)
end

function Discovery.OnWorld()
    local inst, kind = Keys.Instance8()
    if not inst then
        lastInstance = nil
        Discovery.NoteOutside()
        return
    end
    if inst ~= lastInstance then Discovery.NoteInstanceName(inst) end
    if inst == lastInstance then return end
    lastInstance = inst
    local summoned = summonAt and Core.Uptime() - summonAt <= Discovery.SUMMON_SECONDS
    summonAt = nil
    if not DB.Collecting() or not (kind == "party" or kind == "raid") then return end
    if not (outside and Core.Uptime() - outside.at <= Discovery.OUTSIDE_SECONDS) then return end
    if summoned or ViaGroupFinder() or not OutsideFits(inst, outside.map) then
        outside = nil
        return
    end
    DB.Observe("entrance", inst, { cnt = 1, raid = kind == "raid" })
    DB.Observe("spot", { outside.map, "entrance", inst }, { xy = outside.xy, cnt = 1, via = 1 })
    outside = nil
end

ns.On("CONFIRM_SUMMON", function() summonAt = Core.Uptime() end)
ns.On("CANCEL_SUMMON", function() summonAt = nil end)
-- PLAYER_LEAVING_WORLD (Welle 23c, A41): direkt vor dem Ladebildschirm – wer ohne anzuhalten durch das Portal läuft,
-- bekommt sonst eine Lage bis zu 3 Sekunden Laufweg vor dem Eingang (im Kampf auch ältere).
for _, event in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "PLAYER_STOPPED_MOVING", "PLAYER_LEAVING_WORLD" }) do
    ns.On(event, function() Core.Try(nil, "Discovery.Outside", Discovery.NoteOutside) end)
end
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_MAP_CHANGED" }) do
    ns.On(event, function() Core.Try(nil, "Discovery.World", Discovery.OnWorld) end)
end
-- Der Takt alle 3 s: Griff gemerkt (Discovery.outsideTicker) und der ganze Rückruf in Core.Try wie bei den Ereignissen
-- oben – ein Fehler steht in ezCores Fehlerliste, nicht bei jedem Takt in Blizzards Fehleranzeige (Gesamtreview
-- 18.11.2026, T7-3).
function Discovery.OutsideTick()
    if not Core.InCombat() then Discovery.NoteOutside() end
end
ns.On("PLAYER_LOGIN", function()
    local timer = G("C_Timer")
    if Discovery.outsideTicker or type(timer) ~= "table" or type(timer.NewTicker) ~= "function" then return end
    Discovery.outsideTicker = timer.NewTicker(3, function()
        Core.Try(nil, "Discovery.Outside", Discovery.OutsideTick)
    end)
end)

---------------------------------------------------------------------------
-- Flugzeiten: Schreiber für ezMap (Welle 10 übergibt Messung und Altdaten), Wege statt Endpunkte
---------------------------------------------------------------------------

Core.Flights = Core.Flights or {}
-- Core.Flights.Note(von, nach, hops, sekunden, preis) – von, nach, hops sind nodeIDs (Notschlüssel für Altbestand)
function Core.Flights.Note(from, to, hops, sec, price)
    sec = Num(sec)
    if not (from and to and sec and sec > 0) then return nil, "nokey" end
    local way = { hops = type(hops) == "table" and hops or {}, sec = sec, cnt = 1, lo = sec, hi = sec }
    if Num(price) then way.pr = price end
    return DB.Observe("route", { from, to }, way)
end

---------------------------------------------------------------------------
-- Übernahme der Altspeicher (adopt1)
---------------------------------------------------------------------------

Discovery.ADOPT = { "loot", "npcs", "trainer", "books", "vendors", "recipes", "durations", "stages", "sources", "names" }
local adopters = {}

local function MapKey(e)
    local map = Num(e.map)
    if map and map > 0 then return Keys.MapOf(map) or map end
    local inst = Num(e.inst)
    return inst and -inst or 0
end

-- Beute-Verlauf: je Fenster einrechnen (Fensternummer w, ohne sie die 3-Sekunden-Regel), nur bis zur Marke.
function adopters.loot(meta)
    local H = Core.History
    local list = H and H.List and Core.db and Core.db.history and Core.db.history.loot or {}
    local mark = Num(meta.marks.lootWindow) or 0
    local acc, order, state = {}, {}, {}
    local open = 0
    for _, e in ipairs(list) do
        local src = e.src
        if type(src) == "table" and src.type ~= "roll" and (not Num(e.w) or e.w <= mark) then
            local keys
            if src.type == "fishing" then
                keys = { "fishing", MapKey(e), 0 }
            elseif (src.type == "Creature" or src.type == "Vehicle") and Num(src.npc) then
                keys = { "loot", src.npc }
            else
                keys = { "unknown", MapKey(e), 0 }
                open = open + 1
            end
            local id = table.concat(keys, ":")
            local a = acc[id]
            if not a then
                a = { keys = keys, wins = {}, itemWins = {}, perWin = {}, block = { cnt = 0, items = {}, b0 = 0 }, name = nil }
                acc[id] = a
                order[#order + 1] = a
            end
            local win = H.LootWindowOf and H.LootWindowOf(e, state) or tostring(e.t)
            if not a.wins[win] then
                a.wins[win] = true
                a.block.cnt = a.block.cnt + 1
            end
            if type(src.name) == "string" and keys[1] == "loot" then a.name = src.name end
            if Num(e.money) then
                local m = a.block.money or { sum = 0, cnt = 0 }
                a.block.money = m
                m.sum = m.sum + e.money
                local mk = "m#" .. win
                if not a.itemWins[mk] then a.itemWins[mk] = true; m.cnt = m.cnt + 1 end
            elseif Num(e.id) then
                local n = Num(e.n) or 1
                local pk = e.id .. "#" .. win
                a.perWin[pk] = (a.perWin[pk] or 0) + n
                local it = a.block.items[e.id] or { f = 0, s = 0 }
                a.block.items[e.id] = it
                it.s = it.s + n
                if not a.itemWins[pk] then a.itemWins[pk] = true; it.f = it.f + 1 end
            end
        end
    end
    local now = DB.Stamp()
    for _, a in ipairs(order) do
        for pk, total in pairs(a.perWin) do
            local id = tonumber(pk:match("^(%d+)#"))
            local it = id and a.block.items[id]
            if it then
                it.lo = math.min(it.lo or total, total)
                it.hi = math.max(it.hi or total, total)
            end
        end
        DB.Adopt("drops", a.keys, { old = a.block }, { t = now, b = 0, pt = 8 })
        if a.name then DB.SetText("npc", a.keys[2], a.name) end
    end
    return #order, open
end

-- Ein NPC in alter Form (ezCoreDB.npcs bzw. ezMapDB.trainers) » npc, spot (Art npc), text. under = true: Namen
-- nur, wo die laufende Sprache noch keinen hat (was die Datenbank schon weiß, gewinnt). → true, wenn übernommen
local TextUnder
function Discovery.AdoptNpc(id, e, under)
    id = Num(id)
    if not (id and type(e) == "table") then return false end
    local seen = Num(e.seen) or 0
    local f = { roles = {} }
    if e.trainer then f.roles.trainer = seen end
    if e.vendor then f.roles.vendor = seen end
    if e.repair then f.roles.repair = seen end
    if e.trainer then
        f.tr = TRAINER_TYPE[e.trainer] or 3
        if e.trainer == "class" and e.class then f.tk = Keys.Offer("class", e.class)
        elseif e.trainer == "profession" then f.tk = Keys.Offer("profession", 0)
        elseif e.trainer == "pet" then f.tk = Keys.Offer("pet", "HUNTER")   -- Tierausbilder lehren Jäger
        else f.tk = Keys.Offer("other") end
    end
    if e.faction == "Alliance" then f.side = "A" elseif e.faction == "Horde" then f.side = "H" end
    DB.Adopt("npc", id, f, { t = seen, b = 0, pt = 8 })
    local x, y = Num(e.x), Num(e.y)
    local map = Keys.MapOf(e.map)
    local Text = under and TextUnder or DB.SetText
    if map and x and y then
        DB.Observe("spot", { map, "npc", id }, { xy = Keys.Pack(x, y), cnt = 1, via = 1, t = seen, pt = 8 },
            { t = seen })
    elseif type(e.zone) == "string" then
        Text("where", id, e.zone)
    end
    if type(e.name) == "string" then Text("npc", id, e.name) end
    if type(e.title) == "string" then Text("npcTitle", id, e.title) end
    return true
end

function adopters.npcs()
    local store = Core.db and Core.db.npcs
    local n = 0
    for id, e in pairs(type(store) == "table" and store or {}) do
        if Discovery.AdoptNpc(id, e) then n = n + 1 end
    end
    return n, 0
end

function adopters.trainer()
    local all = Core.db and Core.db.spells and Core.db.spells.trainer
    local n = 0
    for locale, byKind in pairs(type(all) == "table" and all or {}) do
        for kind, store in pairs(type(byKind) == "table" and byKind or {}) do
            local class, suffix = tostring(kind):match("^(%u+)(.*)$")
            local pet = suffix == ":PET"
            local art = class and (suffix == "" or pet) and Keys.Offer(pet and "pet" or "class", class) or nil
            if art and type(locale) == "string" and type(store) == "table" and type(store.list) == "table" then
                local svc = {}
                for _, raw in pairs(store.list) do
                    local key = type(raw) == "table" and type(raw.n) == "string"
                        and Keys.FallbackIn(locale, "spell", art, raw.n .. "#" .. tostring(Num(raw.r) or 0)) or nil
                    if key then
                        local s = { rank = Num(raw.r) or 0, lvl = Num(raw.l), t = Num(raw.t), pt = 8 }
                        -- c war auch beim Tierausbilder der Geldpreis (erster Wert von GetTrainerServiceCost)
                        s.pr = Num(raw.c)
                        if Num(raw.i) then s.ic = raw.i end
                        svc[key] = s
                        n = n + 1
                    end
                end
                DB.Adopt("offer", art, { svc = svc, tf = Num(store.seen) }, { t = Num(store.seen), b = 0, pt = 8 })
            end
        end
    end
    return n, 0
end

function adopters.books()
    local map = Core.db and Core.db.knowledge and Core.db.knowledge.bookMap
    local n = 0
    for itemID, questID in pairs(type(map) == "table" and map or {}) do
        if Num(itemID) and Num(questID) then
            DB.Adopt("book", itemID, { quest = questID }, { b = 0, pt = 8 })
            n = n + 1
        end
    end
    return n, 0
end

-- Gehaltener Name: nur, wo die laufende Sprache noch keinen hat (was die Datenbank schon weiß, gewinnt)
function TextUnder(kind, id, text)
    if DB.Text(kind, id, Keys.Locale()) == nil then DB.SetText(kind, id, text) end
end

-- Rohstoff-Händler: ezCoreDB.knowledge.vendors[itemID][npcID oder Name] = { name, zone, price, stack, limited, seen }
-- » vendor[npcID oder Notschlüssel aus Gebiet und Name].w[itemID] = { pr, per, lim, t }; Name und Gebiet nach text.
-- Der alte Deckel „5 Händler je Gegenstand“ entfällt. Verlust: bei begrenztem Vorrat ist die Zahl unbekannt (lim
-- bleibt nil, bis der Händler wieder besucht wird); „unbegrenzt“ wird lim = false.
function adopters.vendors()
    local all = Core.db and Core.db.knowledge and Core.db.knowledge.vendors
    local byKey, order, n, open = {}, {}, 0, 0
    for itemID, list in pairs(type(all) == "table" and all or {}) do
        itemID = Num(itemID)
        for key, e in pairs(itemID and type(list) == "table" and list or {}) do
            local price = type(e) == "table" and Num(e.price)
            if price then
                local npc = Num(key)
                local name = type(e.name) == "string" and e.name ~= "" and e.name or (type(key) == "string" and key or nil)
                local zone = type(e.zone) == "string" and e.zone ~= "" and e.zone or nil
                local vk = npc or (name and Keys.Fallback("npc", zone or 0, name))
                if vk then
                    local v = byKey[vk]
                    if not v then
                        v = { w = {}, t = 0, name = name, zone = zone }
                        byKey[vk] = v
                        order[#order + 1] = vk
                        if not npc then open = open + 1 end
                    end
                    local seen = Num(e.seen) or 0
                    local ware = { pr = price, per = Num(e.stack) or 1, t = seen, b = 0 }
                    if e.limited ~= true then ware.lim = false end
                    v.w[itemID] = ware
                    v.t = math.max(v.t, seen)
                    n = n + 1
                end
            end
        end
    end
    for _, vk in ipairs(order) do
        local v = byKey[vk]
        DB.Adopt("vendor", vk, { w = v.w }, { t = v.t, b = 0, pt = 8 })
        if v.name then TextUnder("npc", vk, v.name) end
        if v.zone and not Num(vk) then TextUnder("where", vk, v.zone) end
        if Num(vk) then DB.Adopt("npc", vk, { roles = { vendor = v.t } }, { t = v.t, b = 0, pt = 8 }) end
    end
    return n, open
end

-- Rezept alter Form { n, p, o, os, r = { [Zutat] = Anzahl } } » Satz in held.recipe { pk, out, rg = geordnete Liste
-- { item, qty } } – Bit 16 in pt: das Produkt ist erschlossen (Link oder Ausgabe statt Schema). Der Name geht nach
-- text.recipe. Rückweg: Discovery.RecipeOld.
function Discovery.RecipeRow(rec)
    if type(rec) ~= "table" then return nil end
    local rg, ids = {}, {}
    for id in pairs(type(rec.r) == "table" and rec.r or {}) do
        if Num(id) then ids[#ids + 1] = id end
    end
    table.sort(ids)
    for _, id in ipairs(ids) do rg[#rg + 1] = { item = id, qty = Num(rec.r[id]) or 1 } end
    local row = { pk = type(rec.p) == "string" and rec.p or nil, out = Num(rec.o), rg = rg }
    if rec.os ~= nil and rec.os ~= "atlasloot" then row.pt = 16 end
    return row
end

function Discovery.RecipeOld(row, key)
    if type(row) ~= "table" then return nil end
    local r = {}
    for _, e in ipairs(type(row.rg) == "table" and row.rg or {}) do
        if type(e) == "table" and Num(e.item) then r[e.item] = (r[e.item] or 0) + (Num(e.qty) or 1) end
    end
    local name = DB.Text("recipe", key)
    if not name and Num(key) and Core.SpellName then name = Core.SpellName(key) end
    return { n = name, p = row.pk, o = Num(row.out), os = DB.BHas(row.pt, 16) and "output" or nil, r = r }
end

-- Rezepte: ezCoreDB.knowledge.recipes » held.recipe (Zahlenschlüssel direkt, „L:Beruf:Name“ » Notschlüssel über
-- Keys.Recipe). reagents und created werden nicht übernommen – den Umkehr-Index baut DB.Index im Arbeitsspeicher.
function adopters.recipes()
    local all = Core.db and Core.db.knowledge and Core.db.knowledge.recipes
    local n, open = 0, 0
    for key, rec in pairs(type(all) == "table" and all or {}) do
        local k = Keys.Recipe(key)
        local row = k and Discovery.RecipeRow(rec)
        if row then
            DB.Adopt("recipe", k, row, { b = 0, pt = 8 })
            if type(rec.n) == "string" and rec.n ~= "" then TextUnder("recipe", k, rec.n) end
            n = n + 1
            if Keys.IsFallback(k) then open = open + 1 end
        end
    end
    return n, open
end

-- Gemessene Dauern: ezCoreDB.spells.durations[spellID] = Sekunden » spellObs[spellID].dur = { sum, cnt }. Text-
-- Schlüssel (Buff-Kürzel) werden über SpellData auf ihre Ränge abgebildet (Entwurf, Tabelle der Umzüge): Spells.NoteAura
-- schrieb sie immer zusammen mit der Zauber-ID des Rangs, ihre Dauer ist also schon über einen Rang übernommen und
-- wird über die Ränge des Buffs gelesen. Offen bleibt nur ein Kürzel, für dessen Ränge keine Zahl vorliegt – es bleibt
-- im Altspeicher lesbar.
function adopters.durations()
    local all = Core.db and Core.db.spells and Core.db.spells.durations
    local n, open = 0, 0
    local buffs = Core.Spells and Core.Spells.BUFFS or {}
    for id, sec in pairs(type(all) == "table" and all or {}) do
        sec = Num(sec)
        if Num(id) and sec and sec > 0 then
            DB.Adopt("spellObs", id, { dur = { sum = sec, cnt = 1 } }, { b = 0, pt = 8 })
            n = n + 1
        elseif type(id) == "string" then
            local covered = false
            local d = buffs[id]
            for _, spell in ipairs(type(d) == "table" and type(d.spells) == "table" and d.spells or {}) do
                if Num(all[spell]) then covered = true break end
            end
            if not covered then open = open + 1 end
        end
    end
    return n, open
end

-- Namen » Gegenstand: ezCoreDB.knowledge.names[name klein] = itemID » text[Umzugssprache].itemByName (Entwurf 1.7,
-- „mit Sprach-Kennung des Umzugstags“). knowledge.items bleibt liegen (Rückweg Nummer » Name kennt der Client).
-- Leser und Schreiber danach: Knowledge.lua (ItemIDByName, RememberName).
function adopters.names()
    local all = Core.db and Core.db.knowledge and Core.db.knowledge.names
    local n = 0
    for name, id in pairs(type(all) == "table" and all or {}) do
        if type(name) == "string" and Num(id) and DB.ItemByName(name) == nil and DB.NoteItemName(name, id) then n = n + 1 end
    end
    return n, 0
end

-- Farbgrenzen: ezCoreDB.knowledge.stages[recipeID] = { [farbe] = { min, max } } » recipeObs[Rezept].stages (dieselbe
-- Form, Entwurf 1.6 und Tabelle der Umzüge). Leser und Schreiber danach: Recipes.lua (K.SkillStages, K.NoteRecipe).
function adopters.stages()
    local all = Core.db and Core.db.knowledge and Core.db.knowledge.stages
    local n, open = 0, 0
    for key, st in pairs(type(all) == "table" and all or {}) do
        local k = Keys.Recipe(key)
        if k and type(st) == "table" and next(st) ~= nil then
            DB.Adopt("recipeObs", k, { stages = st }, { b = 0, pt = 8 })
            n = n + 1
            if Keys.IsFallback(k) then open = open + 1 end
        end
    end
    return n, open
end

-- Quelltexte: ezCoreDB.knowledge.sources[recipeID] = Text » text[Umzugssprache].recipeSrc. Der Alttext bleibt Text,
-- bis ein neuer Fund einen Verweis (recipeObs.from) liefert. Leser danach: K.RecipeSource (Recipes.lua).
function adopters.sources()
    local all = Core.db and Core.db.knowledge and Core.db.knowledge.sources
    local n = 0
    for key, text in pairs(type(all) == "table" and all or {}) do
        local k = Keys.Recipe(key)
        if k and type(text) == "string" and text ~= "" then
            TextUnder("recipeSrc", k, text)
            n = n + 1
        end
    end
    return n, 0
end

-- Ist ein Altspeicher umgezogen? Nur mit Träger (gespeichert) und nach seinem Erledigt-Merker; ohne Träger bleiben
-- die Altspeicher in ezCoreDB Schreiber und Quelle (nichts geht verloren, bis die Verknüpfung da ist).
function Discovery.Moved(store)
    -- eingefroren (Ablage einer neueren Fassung oder eines anderen Spiels): die Datenbank nimmt nichts an, also
    -- bleibt ezCoreDB für diese Sitzung Schreiber und Quelle (sonst merkten die alten Schnittstellen nichts)
    if not DB.Persistent() or DB.Frozen() then return false end
    local meta = DB.Meta()
    local job = meta and type(meta.jobs) == "table" and meta.jobs.adopt1
    local done = type(job) == "table" and type(job.done) == "table" and Num(job.done[store]) or nil
    return done ~= nil and done > 0
end

-- Fenster-Marke der Übernahme: gesetzt, sobald die Datenbank bereit ist – vor der ersten Zählung am offenen Fenster.
-- Später gesetzt (erst im ersten Schritt, der im Kampf oder bei ausgeschaltetem Sammeln wartet), lägen live
-- gezählte Fenster unter der Marke und kämen ein zweites Mal in den Eimer „old“ (Gegenprüfung Welle 9).
local function MarkLootWindow()
    local meta = DB.Meta()
    if meta and Core.db and type(meta.marks) == "table" and meta.marks.lootWindow == nil then
        meta.marks.lootWindow = Num(Core.db.historyWindow) or 0
    end
end
Core.Listen("DB_READY", MarkLootWindow, "ezCore.Discovery")

-- Ein Speicher je Schritt; der Erledigt-Merker liegt im Träger (nicht in ezCoreDB.migrated).
function Discovery.AdoptStep()
    local meta = DB.Meta()
    if not (meta and Core.db) or Core.InCombat() or not DB.Collecting() or DB.Frozen() then return false end
    meta.jobs.adopt1 = type(meta.jobs.adopt1) == "table" and meta.jobs.adopt1 or { done = {} }
    local job = meta.jobs.adopt1
    job.done = type(job.done) == "table" and job.done or {}
    MarkLootWindow()
    for _, store in ipairs(Discovery.ADOPT) do
        if not job.done[store] then
            local ok, cnt, open = pcall(adopters[store], meta)
            if not ok then
                Core.Error("ezCore", cnt, "Discovery.Adopt " .. store)
                job.done[store] = -1
                return true
            end
            job.done[store] = DB.Stamp()
            job.cnt = (Num(job.cnt) or 0) + (Num(cnt) or 0)
            job.open = (Num(job.open) or 0) + (Num(open) or 0)
            Core.Fire("DB_JOB_DONE", "adopt1:" .. store, Num(cnt) or 0, Num(open) or 0)
            return true
        end
    end
    return false
end

-- Stand der Übernahme: fertig (true/false), Liste der offenen Speicher
function Discovery.AdoptState()
    local meta = DB.Meta()
    local done = meta and meta.jobs and meta.jobs.adopt1 and meta.jobs.adopt1.done or {}
    local open = {}
    for _, store in ipairs(Discovery.ADOPT) do
        if not done[store] then open[#open + 1] = store end
    end
    return #open == 0, open
end

local adoptRunning = false
local function RunAdopt()
    if adoptRunning then return end
    adoptRunning = true
    local timer = G("C_Timer")
    local function Next()
        if Discovery.AdoptStep() and type(timer) == "table" and timer.After then
            timer.After(0.2, Next)
        else
            adoptRunning = false
        end
    end
    if type(timer) == "table" and timer.After then timer.After(1, Next) else Next() end
end
Discovery.RunAdopt = RunAdopt

ns.On("PLAYER_LOGIN", function() RunAdopt() end)
ns.On("PLAYER_REGEN_ENABLED", function() if not Discovery.AdoptState() then RunAdopt() end end)

Core.RegisterMessage("DB_JOB_DONE", "Discovery.lua", "Ein Auftrag der Datenbank ist fertig (Übernahme eines Altspeichers).", "auftrag, anzahl, offen")
