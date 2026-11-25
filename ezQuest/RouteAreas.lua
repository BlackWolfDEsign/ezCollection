local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Leveling-Route: Ziele als Gebiet mit Rundgang (Entscheidung des Nutzers vom 22.11.2026, „Gebiet mit Rundgang
    (Empfohlen)“, Wortlaut im ROADMAP-Index; Spielbefund davor, wörtlich „eine quest kann verschiedene gebiete haben,
    d.h. ich renn zum questpunkt von questie und stelle fest die gebiete sind um mich herum verteilt“). Vorher nahm die
    Route je Teilziel einen Punkt: Blizzards Questpunkt für jedes Teilziel, sonst die größte Gruppe der Fundorte laut
    Questie (LR.BestPlace); die Zeit im Gebiet war nur Arbeit je Einheit (LR.WORK).

    Begriffe:
      Nest     Fundorte eines Teilziels laut Questie, die bis LR.MERGE Yards beieinander liegen (Core.Route.Merge); sein
               Ort ist der Fundort nahe der Mitte, nie die Mitte selbst; n = Zahl der Spawn-Punkte darin.
      Gebiet   Nester, die über Abstände bis LR.AREA_GAP Yards zusammenhängen; weiter getrennte sind eigene Gebiete.
               Nur Nester deiner Zone (Entscheidung 10: eigene Zone), sonst wie bisher Grund „andere Zone“ bzw.
               „anderer Kontinent“.
      Rundgang Nester eines Schritts in Laufrichtung: so viele, wie die Restzahl des Teilziels voraussichtlich braucht
               (Spawn-Punkte je Nest als Schätzung, beschriftet „laut Questie, geschätzt“; höchstens LR.TOUR_MAX je
               Teilziel), ab der Seite des vorigen Schritts (nächster Nachbar), geordnet über ezCores Rechner
               (Core.Route.Nearest und TwoOpt, kein zweiter Rechner) mit dem Austritt zum nächsten Schritt.

    Wahl des Gebiets (Leitlinie 11, der Client zuerst): Kennt der Client einen Punkt der Quest
    (C_QuestLog.GetQuestsOnMap), wählt er das Gebiet – das mit dem nächsten Nest zu Blizzards Punkt; liegt keines näher
    als LR.AREA_GAP, bleibt Blizzards Punkt allein (wie ohne Questie). Sonst gewinnt das Gebiet mit dem kleinsten Umweg
    samt Rundgang: beim Rechnen zwischen deinem Ort und der Abgabe, nach der Reihenfolge zwischen den Nachbarschritten
    (LR.Tours) – nicht das größte, aber die Größe zählt (Wunsch des Nutzers vom 24.11.2026, wörtlich „ezquest sollte für
    die leveling route die bereichsgröße beachten? wenn diese die gleiche beute geben?“): Hat ein Gebiet weniger
    Spawn-Punkte, als du noch Gegner brauchst, kommt die Wartezeit auf neue dazu (LR.AreaWait) – vorher wirkte ein kleines
    Gebiet wegen seines kurzen Rundgangs billig. Auch das Gebiet an Blizzards Punkt muss reichen; sonst stehen alle
    Gebiete der Zone zur Wahl (LR.unlocked: solange die Route besteht, sonst spränge sie mit sinkender Restzahl zurück).
    Ein gewähltes Gebiet bleibt, solange du darin bist und angefangen hast; sonst wechselt die Route erst ab
    LR.AREA_SWITCH Yards Vorteil (LR.PickArea). Ohne vollständige Fundorte (capped) zählt die Größe nicht.
    Die Zeit eines Schritts ist Rundgang / LR.SPEED plus Arbeit je Einheit.
    Überschneiden sich die geplanten Nester mehrerer Quests (bis LR.MERGE Yards), werden sie ein Schritt mit gemeinsamem
    Rundgang (LR.JoinAreas; innerhalb einer Quest schon beim Rechnen). Die Abgaben bleiben eigene Schritte danach.

    Navigation (Vorbild ezMaps Sammel-Route, ezMap/Route.lua): Blizzards Markierung zeigt das laufende Nest
    (LR.Spot). Bist du dort angekommen (LR.NEST_REACH), springt sie zum nächsten Nest – so siehst du schon, wohin es
    danach geht. Am letzten Nest bleibt sie; ist das Teilziel dann noch offen, wenn du weitergehst (LR.NEST_LEAVE),
    kommt das nächste noch nicht besuchte Nest des Gebiets dazu, sonst geht es von vorn (Respawn). Fertig ist der Schritt
    erst, wenn der Client das Teilziel als erfüllt meldet (LR.OnLogUpdate); wer früher fertig ist, überspringt den Rest.
    Geprüft wird dein Ort nur, solange die Markierung der Route auf einem Schritt mit Rundgang steht oder der Pfeil auf
    der Minikarte an ist (ezCores Takt, LR.NEST_EVERY). Karte: die übrigen Nester des laufenden Schritts als kleine Punkte und der Rundgang als dünne Linie
    über ezMap (ShowPath, Besitzer LR.OWNER_AREA), abschaltbar (routeArea). Knopf „Nächstes Nest markieren“ im Menü.

    Pfeil auf der Minikarte (Wunsch des Nutzers vom 24.11.2026, wörtlich „wäre es nicht sinnvoll wenn der pfeil auf der
    minimap zum nächsten ziel weiter springt wenn ich die questzone erreiche? und das sichtbar und verständlich?“, auf den
    Vorschlag „Ja, so bauen“; vorher sprang er nur mit gesetzter Markierung, sonst blieb er auf dem ersten Nest und
    verschwand dort): Er läuft die Nester des nächsten Schritts auch ohne Markierung ab. Jeder Sprung leuchtet auf
    (ezMap, pulse). Im Gebiet (bis LR.NEST_LEAVE Yards an einem Nest, nach dem ersten erreichten Nest bis LR.AREA_GAP)
    steht klein in der Minikarte das Teilziel mit Stand laut Client und „Stelle n von m“; kommt ein neuer Schritt, steht
    dort LR.NEXT_SHOW Sekunden lang „Weiter: …“ mit der Entfernung. Auf der Stelle (LR.HERE Yards) steht „Du bist da“, der
    Pfeil verblasst nur (near = "fade"). Schalter der Zeile: routeArrowText. Zum nächsten Schritt springt der Pfeil weiter
    erst, wenn der Client das Teilziel erfüllt meldet – nicht beim Betreten des Gebiets, das führte von der Quest weg.

    Grenzen (im Tooltip): Questie kennt Spawn-Punkte, nicht die Gegner, die gerade dort stehen (Respawn, andere
    Spieler). Den Umriss von Blizzards Questgebiet liest ezQuest nicht. Nichts davon wird gespeichert (Leitlinie 10);
    die Nester leben nur in der Route im Arbeitsspeicher.
    Schätzwerte (Vermutungen, im Spiel zu prüfen): LR.AREA_GAP, LR.TOUR_MAX, LR.NEST_REACH, LR.NEST_LEAVE.
]]

local LR = ns.LevelRoute

LR.AREA_GAP = 250       -- Yards: Nester eines Teilziels, die über solche Abstände zusammenhängen, sind ein Gebiet (Vermutung)
LR.TOUR_MAX = 15        -- höchstens so viele Nester je Teilziel in einem Rundgang (wie LR.WORK_MAX Einheiten)
LR.NEST_REACH = 30      -- Yards: so nah am Nest gilt es als erreicht (ein Nest misst bis zu 2 × LR.MERGE; Vermutung)
LR.NEST_LEAVE = 60      -- Yards: am letzten Nest, Ziel noch offen und so weit weg – das nächste Nest kommt dazu
LR.NEST_EVERY = 1       -- Sekunden zwischen zwei Blicken auf deinen Ort (nur mit Markierung oder Pfeil)
LR.RESPAWN = 300        -- Sekunden, bis ein Gegner der Außenwelt wiederkommt (Vermutung: meist um 5 Minuten)
LR.LOOT_KILLS = 2       -- Gegner je Beutestück (Vermutung; die Beutechance kennt der Client nicht)
LR.AREA_SWITCH = 200    -- Yards: so viel günstiger muss ein anderes Gebiet sein, damit die Route das gewählte verlässt
LR.NEXT_SHOW = 8        -- Sekunden: so lange steht „Weiter: …“ in der Minikarte
LR.HERE = 25            -- Yards: „Du bist da“ (wie ezMaps MiniArrow.NEAR)
LR.OWNER_AREA = "ezQuest.routeArea"   -- Besitzer der dünnen Linie in ezMap (eigener Weg neben der Route)
LR.AREA_FAMILY = "goldThin"           -- Farbfamilie in ezMap: Gold, dünn, ohne Pfeile (ezMap/RouteDraw.lua)
-- Punkte der Nester auf der Weltkarte: Blizzards kleine runde Marken (wie ezMaps Spawn-Punkte laut Questie)
LR.NEST_ICON = { next = "Interface\\Common\\Indicator-Yellow", other = "Interface\\Common\\Indicator-Gray" }

local Num = Core.Num

local function R() return Core.Route end
local function WD(a, b) return R().WorldDistance(a, b) end
local function Map() return Core.API("ezMap") end

local function World(p)
    local Route = R()
    return Route and Route.World(p) or false
end

local function ZoneOf(map)
    return Core.Map.Parent(map, "Zone") or map
end

---------------------------------------------------------------------------
-- Nester und Gebiete
---------------------------------------------------------------------------

-- Fundorte → Nester je Kontinent: { map, x, y, continent, wx, wy, zone, name, n } (tick: Rechenschritte)
function LR.Nests(places, tick)
    local byCont, conts = {}, {}
    for _, p in ipairs(places or {}) do
        local w = type(p) == "table" and { map = p.map, x = p.x, y = p.y, name = p.name } or nil
        if w and w.map and World(w) then
            w.zone = ZoneOf(w.map)
            local c = w.continent
            if not byCont[c] then
                byCont[c] = {}
                conts[#conts + 1] = c
            end
            byCont[c][#byCont[c] + 1] = { x = w.wx, y = w.wy, ref = w }
        end
    end
    local nests = {}
    for _, c in ipairs(conts) do
        for _, g in ipairs(R().Merge(byCont[c], LR.MERGE, 1, 1, tick)) do
            local rep, near
            for _, m in ipairs(g.members) do
                local d = (m.x - g.x) ^ 2 + (m.y - g.y) ^ 2
                if not near or d < near then rep, near = m.ref, d end
            end
            nests[#nests + 1] = { map = rep.map, x = rep.x, y = rep.y, continent = rep.continent, wx = rep.wx,
                wy = rep.wy, zone = rep.zone, name = rep.name, n = g.n }
        end
    end
    return nests
end

-- Nester → Gebiete (zusammenhängend über Abstände bis LR.AREA_GAP): { { nests = { … }, n = Spawn-Punkte } … }
function LR.Link(nests, tick)
    local areas, seen = {}, {}
    for _, start in ipairs(nests) do
        if not seen[start] then
            seen[start] = true
            local area = { nests = { start }, n = start.n or 1 }
            local k = 1
            while k <= #area.nests do
                local a = area.nests[k]
                for _, b in ipairs(nests) do
                    if not seen[b] and WD(a, b) <= LR.AREA_GAP then
                        seen[b] = true
                        area.nests[#area.nests + 1] = b
                        area.n = area.n + (b.n or 1)
                    end
                end
                if tick then tick(#nests) end
                k = k + 1
            end
            areas[#areas + 1] = area
        end
    end
    return areas
end

-- Gebiete eines Teilziels aus seinen Fundorten → Gebiete des besten Rangs, Rang (2: deine Zone, 1: dein Kontinent,
-- 0: anderswo), Zahl aller Gebiete. Im Rang 2 zählen nur die Nester deiner Zone (Entscheidung 10).
function LR.Areas(places, ctx, tick)
    local nests = LR.Nests(places, tick)
    if #nests == 0 then return {}, nil, 0 end
    local total = #LR.Link(nests, tick)
    local home, cont = {}, {}
    for _, nest in ipairs(nests) do
        if nest.continent == ctx.continent then
            cont[#cont + 1] = nest
            if nest.zone == ctx.zone then home[#home + 1] = nest end
        end
    end
    if #home > 0 then return LR.Link(home, tick), 2, total end
    if #cont > 0 then return LR.Link(cont, tick), 1, total end
    return LR.Link(nests, tick), 0, total
end

---------------------------------------------------------------------------
-- Rundgang
---------------------------------------------------------------------------

-- Restzahl eines Teilziels (offene Einheiten laut Client, mindestens 1)
function LR.PartLeft(part)
    return LR.Units(part.obj)
end

-- Besuchte Nester dieser Sitzung je Teilziel (nur Arbeitsspeicher; Review vom 22.11.2026): eine Neurechnung – etwa
-- beim Öffnen der Karte nach ein paar Schritten (LR.OnMapShown) – plant gerade geleerte Nester zuletzt ein, statt sie
-- wieder vor die unbesuchten zu legen. [Schlüssel des Teilziels] = { { map, x, y, continent, wx, wy } … }
LR.visited = {}
-- Teilziele, deren Gebiet an Blizzards Punkt zu klein war: in dieser Sitzung wählt Blizzards Punkt nicht mehr allein
LR.unlocked = {}
LR.VISITED_NEAR = 5     -- Yards: so nah gilt ein Nest einer neuen Rechnung als dasselbe (Questies Lagen sind fest)

function LR.PartKey(part)
    return tostring(part.quest and part.quest.id) .. "/" .. tostring(part.obj and part.obj.index)
end

local function Visited(list, nest)
    for _, v in ipairs(list or {}) do
        if WD(v, nest) <= LR.VISITED_NEAR then return true end
    end
    return false
end

-- Das Nest als besucht merken – für jedes offene Teilziel des Schritts s, zu dessen Gebiet es gehört
function LR.Visit(s, nest)
    for _, part in ipairs(s.parts or {}) do
        if part.area and not part.obj.done then
            local mine = false
            for _, n in ipairs(part.area.nests) do
                if n == nest then mine = true break end
            end
            local key = LR.PartKey(part)
            local list = LR.visited[key]
            if mine and not Visited(list, nest) then
                list = list or {}
                list[#list + 1] = { map = nest.map, x = nest.x, y = nest.y, continent = nest.continent, wx = nest.wx,
                    wy = nest.wy }
                LR.visited[key] = list
            end
        end
    end
end

-- So viele Nester des Gebiets, wie units voraussichtlich braucht: nächster Nachbar ab from, bis die Spawn-Punkte
-- reichen (höchstens LR.TOUR_MAX); in dieser Sitzung schon besuchte Nester (visited) erst, wenn die übrigen nicht
-- reichen. tick (freiwillig): Rechenschritte → Nester, geschätzte Spawn-Punkte
function LR.PickNests(area, units, from, tick, visited)
    local picked, used, cur, est = {}, {}, from, 0
    local left = Num(units) or 1
    local nests = area and area.nests or {}
    while left > 0 and #picked < LR.TOUR_MAX do
        local best, bestD, bestSeen
        for _, nest in ipairs(nests) do
            if not used[nest] then
                local seen = visited ~= nil and Visited(visited, nest)
                local d = cur and WD(cur, nest) or 0
                if d == math.huge then d = 1e9 end
                if not bestD or (bestSeen and not seen) or (seen == bestSeen and d < bestD) then
                    best, bestD, bestSeen = nest, d, seen
                end
            end
        end
        if tick then tick(#nests) end
        if not best then break end
        used[best] = true
        picked[#picked + 1] = best
        est = est + (best.n or 1)
        left = left - (best.n or 1)
        cur = best
    end
    return picked, est
end

-- Länge eines Rundgangs ab der Stelle at (Yards zwischen den Nestern)
function LR.TourLength(tour, at)
    local len = 0
    for k = (at or 1) + 1, #(tour or {}) do
        local d = WD(tour[k - 1], tour[k])
        if d < math.huge then len = len + d end
    end
    return len
end

-- Reihenfolge der Nester ab from, mit dem Austritt zu to (freiwillig): ezCores Rechner, nächster Nachbar plus 2-opt;
-- to steht über den Vorrang immer am Ende (Core.Route: opts.after); tick (freiwillig) geht an ezCores Rechner →
-- Rundgang, Länge in Yards
function LR.TourOf(nests, from, to, tick)
    if #nests <= 1 then return { nests[1] }, 0 end
    local Route = R()
    local groups, all = { from }, {}
    for _, nest in ipairs(nests) do
        groups[#groups + 1] = nest
        all[#all + 1] = #groups
    end
    local opts = { dist = function(a, b)
        local d = WD(a, b)
        return d == math.huge and 1e9 or d
    end }
    if to then
        groups[#groups + 1] = to
        opts.after = { [#groups] = all }
    end
    local order = Route.Nearest(groups, nil, nil, 1, tick, opts)
    Route.TwoOpt(groups, order, nil, nil, false, tick, opts)
    local tour = {}
    for _, idx in ipairs(order) do
        if idx ~= 1 and not (to and idx == #groups) then tour[#tour + 1] = groups[idx] end
    end
    return tour, LR.TourLength(tour)
end

-- So viele Gegner bzw. Objekte braucht ein Teil voraussichtlich noch: Beute von Gegnern (part.loot) LR.LOOT_KILLS je Stück,
-- außer ein einziges Stück (Boss) → Zahl oder nil (Fundorte abgeschnitten: die Größe ist unbekannt)
function LR.PartKills(part)
    if part.capped then return nil end
    local units = LR.PartLeft(part)
    return units * (part.loot and units > 1 and LR.LOOT_KILLS or 1)
end

-- Wartezeit in einem Gebiet, dessen Spawn-Punkte nicht für kills reichen (Sekunden): je weiterer Runde LR.RESPAWN, abzüglich
-- der Zeit, die eine Runde selbst dauert (len: Länge des Rundgangs in Yards); kills nil: keine
function LR.AreaWait(area, kills, len)
    if not kills then return 0 end
    local n = math.max(1, area and area.n or 1)
    local rounds = math.ceil(kills / n) - 1
    if rounds <= 0 then return 0 end
    return rounds * math.max(0, LR.RESPAWN - n * LR.WORK - (len or 0) / LR.SPEED)
end

-- Umweg eines Gebiets zwischen from und to samt Rundgang und Wartezeit (Yards; kills: LR.PartKills, nil: ohne Wartezeit) →
-- Umweg, Rundgang, Länge
function LR.AreaCost(area, units, from, to, tick, kills)
    local picked = LR.PickNests(area, units, from, tick)
    local tour, len = LR.TourOf(picked, from, to, tick)
    if #tour == 0 then return math.huge, tour, 0 end
    local d1 = WD(from, tour[1])
    if d1 == math.huge then d1 = 0 end
    local d2, base = 0, 0
    if to then
        d2, base = WD(tour[#tour], to), WD(from, to)
        if d2 == math.huge or base == math.huge then d2, base = 0, 0 end
    end
    return d1 + len + d2 - base + LR.AreaWait(area, kills, len) * LR.SPEED, tour, len
end

-- Das günstigste Gebiet nach Umweg samt Rundgang (bei Gleichstand das mit mehr Spawn-Punkten) → Gebiet, Umweg
function LR.CheapestArea(areas, units, from, to, tick, kills)
    local best, bestCost
    for _, area in ipairs(areas) do
        local cost = LR.AreaCost(area, units, from, to, tick, kills)
        if not bestCost or cost < bestCost - 1e-6 or (math.abs(cost - bestCost) <= 1e-6 and area.n > best.n) then
            best, bestCost = area, cost
        end
    end
    return best, bestCost
end

-- Das Gebiet mit dem nächsten Nest zu Blizzards Punkt (höchstens LR.AREA_GAP weit) → Gebiet oder nil
function LR.AreaNear(areas, point)
    local best, bestD
    for _, area in ipairs(areas) do
        for _, nest in ipairs(area.nests) do
            local d = WD(point, nest)
            if not bestD or d < bestD then best, bestD = area, d end
        end
    end
    if bestD and bestD <= LR.AREA_GAP then return best end
    return nil
end

-- Zuletzt gewähltes Gebiet je Teilziel (ein Nest davon), solange die Route besteht: [Schlüssel] = { map, x, y, … }
LR.areaMark = {}

-- Die gewählten Gebiete der jetzigen Schritte merken (LR.Changed)
function LR.MarkAreas()
    local state = LR.State()
    for _, s in ipairs(state and state.steps or {}) do
        for _, part in ipairs(s.parts or {}) do
            if part.area then LR.areaMark[LR.PartKey(part)] = part.area.nests[1] end
        end
    end
end

-- Gebiet eines Teils: das günstigste, aber das bisher gewählte bleibt, solange du darin angefangen hast und noch dort bist,
-- sonst bis ein anderes um LR.AREA_SWITCH Yards günstiger ist (sonst spränge die Route, sobald die Restzahl eine Schwelle
-- unterschreitet; Review vom 24.11.2026) → Gebiet
function LR.PickArea(part, from, to, tick)
    local units, kills = LR.PartLeft(part), LR.PartKills(part)
    local best, cost = LR.CheapestArea(part.areas, units, from, to, tick, kills)
    local key = LR.PartKey(part)
    local mark = LR.areaMark[key]
    if not mark then return best end
    local here = LR.Here()
    for _, area in ipairs(part.areas) do
        if area ~= best and Visited(area.nests, mark) then
            if here then
                for _, nest in ipairs(area.nests) do
                    if WD(here, nest) <= LR.AREA_GAP and Visited(LR.visited[key], nest) then return area end
                end
            end
            if LR.AreaCost(area, units, from, to, tick, kills) <= cost + LR.AREA_SWITCH then return area end
        end
    end
    return best
end

-- Fehlen Fundorte deiner Zone? Sie stehen vorn (Q.QuestPlaces, opts.map): endet die abgeschnittene Liste noch in ihr, ja
local function Cut(places, ctx)
    local last = places and places[#places]
    return type(last) == "table" and last.map ~= nil and ZoneOf(last.map) == ctx.zone or nil
end

-- Stammen die Fundorte von Gegnern (nicht von Objekten)?
local function FromNpc(places)
    for _, p in ipairs(places or {}) do
        if type(p) == "table" and p.kind == "object" then return false end
    end
    return true
end

--[[
    Teil eines Ziel-Schritts aus den Fundorten laut Questie (e aus LR.MatchObjective) → part oder nil, Grund.
    part = { quest, obj, src = "questie", area, areas, byClient, clientArea, anchor, groups, name }. client: Blizzards Punkt der
    Quest (mit Weltlage) oder nil; to: Ort der Abgabe oder nil. Gründe: "noplace" (keine Fundorte mit Weltlage), "zone",
    "continent", "client" (Blizzards Punkt liegt bei keinem Gebiet – der Aufrufer nimmt dann Blizzards Punkt allein).
]]
function LR.AreaPart(q, o, e, ctx, to, client, tick)
    local areas, rank = LR.Areas(e.places, ctx, tick)
    if #areas == 0 then return nil, "noplace" end
    if client and rank ~= 2 then return nil, "client" end
    if rank == 1 then return nil, "zone" end
    if rank == 0 then return nil, "continent" end
    -- groups: nur die Gebiete, die zur Wahl standen (deine Zone; Review vom 22.11.2026 – vorher zählten auch die anderer
    -- Zonen und Kontinente mit)
    local part = { quest = q, obj = o, src = "questie", areas = areas, groups = #areas, name = e.name,
        capped = e.capped and Cut(e.places, ctx) or nil, loot = o.type == "item" and FromNpc(e.places) or nil }
    if client then
        part.clientArea = LR.AreaNear(areas, client)
        if not part.clientArea then return nil, "client" end
        local key = LR.PartKey(part)
        if #areas > 1 and LR.AreaWait(part.clientArea, LR.PartKills(part)) > 0 then LR.unlocked[key] = true end
        if not LR.unlocked[key] then
            part.area, part.byClient, part.anchor = part.clientArea, true, client
            return part
        end
    end
    part.area = LR.PickArea(part, ctx.start, to, tick)
    part.anchor = ctx.start
    return part
end

-- Arbeit eines Teils (Sekunden): LR.WORK je offener Einheit, höchstens LR.WORK_MAX
local function PartWork(part)
    return LR.WORK * math.min(LR.PartLeft(part), LR.WORK_MAX)
end

-- Hat der Schritt Nester (Gebiet laut Questie)?
function LR.HasArea(s)
    if type(s) ~= "table" or not s.parts then return false end
    for _, part in ipairs(s.parts) do
        if part.area then return true end
    end
    return false
end

-- Rundgang eintragen: der Ort des Schritts ist sein erstes Nest
local function SetTour(s, tour, len)
    local first = tour[1]
    s.tour, s.tourLen = tour, len
    s.map, s.x, s.y, s.continent, s.wx, s.wy, s.zone = first.map, first.x, first.y, first.continent, first.wx, first.wy,
        first.zone
end

-- Arbeit an den offenen Teilen eines Schritts (Sekunden)
local function OpenWork(s)
    local work = 0
    for _, part in ipairs(s.parts or {}) do
        if not part.obj.done then work = work + PartWork(part) end
    end
    return work
end

-- Rundgang eines Ziel-Schritts neu: je offenem Teil die nötigen Nester ab from (besuchte zuletzt, LR.visited),
-- zusammen geordnet bis zum Austritt zu to; der Ort des Schritts ist das erste Nest, die Zeit Rundgang plus Arbeit.
-- tick (freiwillig): Rechenschritte → true, wenn ein Rundgang besteht
function LR.BuildTour(s, from, to, tick)
    local all, seen, work = {}, {}, 0
    for _, part in ipairs(s.parts or {}) do
        if not part.obj.done then
            work = work + PartWork(part)
            if part.area then
                local visited = LR.visited[LR.PartKey(part)]
                for _, nest in ipairs((LR.PickNests(part.area, LR.PartLeft(part), from, tick, visited))) do
                    if not seen[nest] then
                        seen[nest] = true
                        all[#all + 1] = nest
                    end
                end
            end
        end
    end
    if #all == 0 then
        -- kein offenes Teilziel mit Nestern mehr (übrig nur Blizzards Punkt): ohne Rundgang am bisherigen Ort
        if s.tour then s.tour, s.at, s.tourLen, s.arrived, s.work = nil, nil, nil, nil, work end
        return false
    end
    local tour, len = LR.TourOf(all, from, to, tick)
    s.at, s.arrived = 1, nil
    SetTour(s, tour, len)
    s.work = len / LR.SPEED + work
    return true
end

-- Ausgang eines Schritts (letztes Nest des Rundgangs, sonst sein Ort) und laufender Punkt (Nest, auf dem die
-- Markierung steht bzw. stehen soll, sonst sein Ort)
function LR.Exit(s)
    return s and s.tour and s.tour[#s.tour] or s
end

function LR.Spot(s)
    return s and s.tour and s.tour[s.at or 1] or s
end

-- Abstand von a nach b auf der Route: vom Ausgang von a zum Ort von b (Yards; nicht symmetrisch, sobald a einen
-- Rundgang hat)
function LR.LegDist(a, b)
    return WD(LR.Exit(a), b)
end

---------------------------------------------------------------------------
-- Teile, Überschneidung, gemeinsamer Rundgang
---------------------------------------------------------------------------

-- Ziel-Schritt aus seinen Teilen nachführen: Teilziele (s.objs, s.obj), Quests (s.quest, s.quests ab zwei Quests)
function LR.SyncParts(s)
    local objs, quests, seen = {}, {}, {}
    local first
    for _, part in ipairs(s.parts) do
        objs[#objs + 1] = part.obj
        if not part.obj.done then first = first or part.obj end
        if not seen[part.quest] then
            seen[part.quest] = true
            quests[#quests + 1] = part.quest
        end
    end
    s.objs = #objs > 1 and objs or nil
    s.obj = first or objs[1]
    s.quest = quests[1]
    s.quests = #quests > 1 and quests or nil
    if s.quests then s.joined = true end
end

-- Teile von t in den Schritt s (Nester für weitere Vergleiche dazu; den Rundgang ordnet LR.BuildTour neu)
function LR.AddParts(s, t)
    for _, part in ipairs(t.parts or {}) do s.parts[#s.parts + 1] = part end
    local seen = {}
    for _, nest in ipairs(s.tour or {}) do seen[nest] = true end
    for _, nest in ipairs(t.tour or {}) do
        if not seen[nest] then
            s.tour[#s.tour + 1] = nest
            seen[nest] = true
        end
    end
    s.groups = math.max(s.groups or 1, t.groups or 1)
    LR.SyncParts(s)
end

-- Überschneiden sich die geplanten Nester zweier Schritte (bis LR.MERGE Yards)? tick (freiwillig): Rechenschritte
function LR.Overlap(s, t, tick)
    local a, b = s.tour or {}, t.tour or {}
    if tick then tick(#a * #b) end
    for _, p in ipairs(a) do
        for _, q in ipairs(b) do
            if WD(p, q) <= LR.MERGE then return true end
        end
    end
    return false
end

-- Ziel-Schritte mehrerer Quests, deren Nester sich überschneiden, werden ein Schritt mit gemeinsamem Rundgang: der
-- spätere rückt zum früheren (ein Ziel nach vorn verletzt keinen Vorrang – seine Abgabe steht ohnehin dahinter).
-- Eine zurückgestellte Quest (LR.Held: orange, rot, grau, Elite/Gruppe/Dungeon allein) bleibt für sich – ihr Schritt
-- würde sonst eine passende Quest nach hinten ziehen oder selbst nach vorn kommen –, und ein Schritt, dessen Rundgang
-- schon läuft (walked), bleibt, wie er ist (Review vom 22.11.2026: sonst gingen Stand und Markierung verloren). tick
-- (freiwillig): Rechenschritte → Zahl der zusammengelegten Schritte
function LR.JoinAreas(steps, ctx, tick)
    local function Alone(st)
        if st.walked then return true end
        if ctx then
            for _, q in ipairs(LR.QuestsOf(st)) do
                if LR.Held(q, ctx).later then return true end
            end
        end
        return false
    end
    local n, i = 0, 1
    while i <= #steps do
        local s = steps[i]
        if s.kind == "obj" and s.tour and not Alone(s) then
            local j = i + 1
            while j <= #steps do
                local t = steps[j]
                if t.kind == "obj" and t.tour and not Alone(t) and LR.Overlap(s, t, tick) then
                    table.remove(steps, j)
                    LR.AddParts(s, t)
                    n = n + 1
                    j = i + 1       -- s ist gewachsen: die übrigen noch einmal vergleichen
                else
                    j = j + 1
                end
            end
        end
        i = i + 1
    end
    return n
end

-- Rundgänge aller Ziel-Schritte mit ihren Nachbarn: Eintritt von der Seite des vorigen Schritts (beim ersten: start),
-- Austritt zum nächsten. Ein Teil ohne Blizzards Punkt wählt dabei sein Gebiet neu nach Umweg samt Rundgang zwischen
-- den Nachbarn. Schritte, deren Rundgang schon läuft (walked), bleiben. Zwei Durchgänge: im ersten zielt ein Austritt
-- noch auf den alten Ort des nächsten Schritts, der danach selbst neu geplant wird (Review vom 22.11.2026). tick
-- (freiwillig): Rechenschritte → Zahl der Rundgänge im letzten Durchgang
function LR.Tours(steps, start, tick)
    local n = 0
    for _ = 1, 2 do
        n = 0
        for i, s in ipairs(steps) do
            if s.kind == "obj" and LR.HasArea(s) and not s.walked then
                local from = i == 1 and start or LR.Exit(steps[i - 1])
                local to = steps[i + 1]
                local part = #s.parts == 1 and s.parts[1] or nil
                if part and part.area and not part.byClient and part.areas and #part.areas > 1 and from then
                    part.area = LR.PickArea(part, from, to, tick)
                end
                if from and LR.BuildTour(s, from, to, tick) then n = n + 1 end
            end
        end
    end
    return n
end

-- Der laufende Schritt: der markierte, solange er besteht, sonst der erste
function LR.Current()
    local state = LR.State()
    if not state then return nil end
    if state.marked then
        for _, s in ipairs(state.steps) do
            if s == state.marked then return s end
        end
    end
    return state.steps[1]
end

-- Dein Ort mit Weltlage oder nil
local function Here()
    local map, x, y = Core.PlayerPosition()
    if not map then return nil end
    local here = { map = map, x = x, y = y }
    return World(here) and here or nil
end
LR.Here = Here

-- Einen begonnenen Rundgang beim Neuplanen fortsetzen (Review vom 24.11.2026: Karte öffnen im Gebiet rechnet neu, und der
-- Rundgang begann an deinem Ort – der Pfeil sprang zurück auf das Nest, an dem du stehst, und gleich wieder vor).
-- old = der bisherige Stand { tour, at, arrived, walked }, s = der neu geplante Schritt: Besuchtes bleibt davor, das
-- laufende Nest bleibt das laufende, der Rest ordnet sich von dort aus bis zum Austritt zu to. Bist du nicht mehr im
-- Gebiet, gilt der neue Plan ab deinem Ort → true, wenn fortgesetzt
function LR.KeepWalk(s, old, to)
    if not (old.walked and old.tour and s.tour) then return false end
    local here = Here()
    if here and not LR.InArea(old, here) then return false end
    local at, used, tour, open, run = old.at or 1, {}, {}, {}, nil
    for k, nest in ipairs(old.tour) do
        for _, n in ipairs(s.tour) do
            if not used[n] and WD(n, nest) <= LR.VISITED_NEAR then
                used[n] = true
                if k < at then tour[#tour + 1] = n elseif k == at then run = n else open[#open + 1] = n end
                break
            end
        end
    end
    if next(used) == nil then return false end      -- ein anderes Gebiet
    for _, n in ipairs(s.tour) do
        if not used[n] then open[#open + 1] = n end
    end
    local cur = #tour + 1
    if run then tour[cur] = run end
    if #open > 0 then
        for _, n in ipairs((LR.TourOf(open, run or here or LR.Spot(old), to))) do tour[#tour + 1] = n end
    end
    s.walked, s.at = true, cur <= #tour and cur or 1
    s.arrived = run and old.arrived == at and s.at or nil
    SetTour(s, tour, LR.TourLength(tour))
    s.work = LR.TourLength(tour, s.at) / LR.SPEED + OpenWork(s)
    return true
end

-- Nach einer neuen Rechnung: begonnene Rundgänge der alten Schritte auf die neuen mit einem gemeinsamen Teilziel
-- übertragen (LR.Compute) → Zahl
function LR.KeepWalks(old, steps)
    local n = 0
    for _, o in ipairs(old or {}) do
        if o.kind == "obj" and o.walked and o.tour then
            local keys = {}
            for _, part in ipairs(o.parts or {}) do keys[LR.PartKey(part)] = true end
            for i, s in ipairs(steps) do
                local mine = false
                if s.kind == "obj" and s.tour and not s.walked then
                    for _, part in ipairs(s.parts or {}) do
                        if keys[LR.PartKey(part)] then mine = true end
                    end
                end
                if mine then
                    if LR.KeepWalk(s, o, steps[i + 1]) then n = n + 1 end
                    break
                end
            end
        end
    end
    return n
end

-- Rundgang eines Schritts ab deinem Ort neu – ein Teilziel ist erfüllt, seine übrigen Nester fallen weg (LR.OnLogUpdate);
-- die Markierung zieht mit, wenn sie auf ihm steht → true, wenn neu
function LR.RetourStep(s)
    local state = LR.State()
    if not (state and LR.HasArea(s)) then return false end
    local n
    for i, t in ipairs(state.steps) do
        if t == s then n = i end
    end
    if not n then return false end
    local from = Here() or LR.Spot(s)
    local old = { tour = s.tour, at = s.at, arrived = s.arrived, walked = s.walked }
    if not LR.BuildTour(s, from, state.steps[n + 1]) then return false end
    LR.KeepWalk(s, old, state.steps[n + 1])
    -- die Markierung nur nachziehen, solange sie der Route gehört und die Route ihr folgt – eine eigene Markierung
    -- bzw. die einer anderen Route bleibt (Review vom 22.11.2026; wie LR.Follow und LR.Paused)
    if state.marked == s and LR.OwnsMark() then LR.SetMark(s, true) end
    return true
end

-- Folgt die Route ihrer Markierung, und gehört sie ihr laut ezMap? → true | false
function LR.OwnsMark()
    local state = LR.State()
    local api = Map()
    return state ~= nil and state.following == true and api ~= nil and type(api.OwnsWaypoint) == "function"
        and api.OwnsWaypoint(LR.OWNER) == true
end

-- Den laufenden Schritt (den ersten bzw. einen per Klick gewählten späteren, LR.Current) von deinem Ort aus neu planen,
-- solange du keines seiner Nester erreicht hast (nach jeder Änderung der Route, LR.Changed) → true, wenn neu
function LR.Retour()
    local state = LR.State()
    local s = LR.Current()
    if not (s and s.kind == "obj" and LR.HasArea(s) and not s.walked) then return false end
    local from = Here() or (state.ctx and state.ctx.start)
    if not from then return false end
    local nxt
    for i, t in ipairs(state.steps) do
        if t == s then nxt = state.steps[i + 1] end
    end
    return LR.BuildTour(s, from, nxt)
end

---------------------------------------------------------------------------
-- Navigation: von Nest zu Nest
---------------------------------------------------------------------------

-- Nächstes noch nicht geplantes Nest der offenen Teile, nah an from; in dieser Sitzung schon besuchte zuletzt
-- (LR.visited) → Nest oder nil
function LR.MoreNest(s, from)
    local inTour = {}
    for _, nest in ipairs(s.tour or {}) do inTour[nest] = true end
    local best, bestD, bestSeen
    for _, part in ipairs(s.parts or {}) do
        if part.area and not part.obj.done then
            local visited = LR.visited[LR.PartKey(part)]
            for _, nest in ipairs(part.area.nests) do
                if not inTour[nest] then
                    local seen = Visited(visited, nest)
                    local d = WD(from, nest)
                    if not bestD or (bestSeen and not seen) or (seen == bestSeen and d < bestD) then
                        best, bestD, bestSeen = nest, d, seen
                    end
                end
            end
        end
    end
    return best
end

-- Markierung auf das nächste Nest des Schritts s; nach dem letzten das nächste nicht geplante Nest des Gebiets, sonst
-- wieder das erste (Respawn). auto: ohne Klick (Pfeil nur mit ezMaps wayTrack) → Index des Nests
function LR.NextNest(s, auto)
    if not (s and s.tour and #s.tour > 0) then return nil end
    local at = (s.at or 1) + 1
    if at > #s.tour then
        local extra = LR.MoreNest(s, s.tour[#s.tour])
        if extra then
            s.tour[#s.tour + 1] = extra
            s.tourLen = LR.TourLength(s.tour)       -- der Tooltip nennt die Länge des ganzen Rundgangs
        else
            at = 1
        end
    end
    s.at, s.arrived = at, nil
    s.work = LR.TourLength(s.tour, at) / LR.SPEED + OpenWork(s)
    local state = LR.State()
    if state and state.marked == s and LR.OwnsMark() then LR.SetMark(s, auto) end
    ns.Try("LevelRoutePath", LR.DrawPath)
    return at
end

-- Schritte, deren Nester dein Ort abläuft: der markierte (solange die Markierung der Route gehört) und der nächste, zu
-- dem der Pfeil auf der Minikarte zeigt → Liste
function LR.Walked()
    local state, list = LR.State(), {}
    if not (state and ns.Enabled("levelRoute")) then return list end
    local function Add(s)
        if s and s.tour and #s.tour > 0 and list[1] ~= s then list[#list + 1] = s end
    end
    if LR.OwnsMark() then Add(state.marked) end
    if LR.ArrowWanted() then Add(state.steps[1]) end
    return list
end

-- Einen Schritt an deinem Ort ablaufen: am laufenden Nest angekommen → zum nächsten; am letzten Nest, Ziel offen und
-- weitergegangen → das nächste Nest dazu bzw. von vorn → true, wenn es weiterging
local function WalkNests(s, here)
    local at = s.at or 1
    local d = WD(here, s.tour[at])
    if d <= LR.NEST_REACH then
        s.walked = true
        LR.Visit(s, s.tour[at])     -- eine Neurechnung plant es zuletzt ein
        if at < #s.tour then
            LR.NextNest(s, true)
            return true
        end
        s.arrived = at          -- letztes Nest: bleiben, bis das Ziel erfüllt ist oder du weitergehst
        return false
    end
    if s.arrived == at and d > LR.NEST_LEAVE then
        LR.NextNest(s, true)
        return true
    end
    return false
end

-- Im Flug und als Geist gilt kein Nest als besucht (Review vom 24.11.2026: der Takt läuft für den Pfeil immer)
local function OnFoot()
    return not (LR.OnTaxi() or LR.PlayerFlag("UnitIsDeadOrGhost"))
end

-- Ein Blick auf deinen Ort (ezCores Takt): Nester ablaufen, Zeile in der Minikarte nachziehen → true, wenn Markierung
-- oder Pfeil gesprungen sind
function LR.CheckNest()
    if not LR.NestWanted() then
        -- etwa eine eigene Markierung des Spielers ohne Änderung der Route: der Takt hält an
        LR.UpdateNestTicker()
        return false
    end
    local here, moved = Here(), false
    if here and OnFoot() then
        for _, s in ipairs(LR.Walked()) do
            if WalkNests(s, here) then moved = true end
        end
    end
    ns.Try("LevelRouteArrow", LR.UpdateArrowText)
    return moved
end

-- Läuft der Blick auf deinen Ort? Mit Markierung bzw. Pfeil auf einem Schritt mit Rundgang, oder für die Zeile am Pfeil
function LR.NestWanted()
    return #LR.Walked() > 0 or (ns.Enabled("routeArrowText") and LR.ArrowWanted())
end

function LR.UpdateNestTicker()
    if not LR.nestTicker then
        LR.nestTicker = ns.Ticker(LR.NEST_EVERY, LR.CheckNest, LR.NestWanted, "LevelRouteNest")
        return LR.nestTicker:Running()
    end
    return LR.nestTicker:Update()
end

-- Knopf „Nächstes Nest markieren“ (Leitlinie 3): Markierung auf das nächste Nest des laufenden Schritts → true | false
function LR.NestClick()
    local state = LR.State()
    local s = LR.Current()
    if not (state and s and s.tour and #s.tour > 1) then return false end
    -- neu markieren, auch wenn die Route ihrer Markierung nicht mehr folgt (eigene Markierung, andere Route): sonst
    -- liefe weder der Takt noch rückte die Markierung nach dem Erfüllen weiter (Review vom 22.11.2026)
    if state.marked ~= s or not LR.OwnsMark() then
        local n
        for i, t in ipairs(state.steps) do if t == s then n = i end end
        if not (n and LR.Mark(n, true)) then return false end
    end
    s.walked = true
    LR.Visit(s, LR.Spot(s))     -- weiter von Hand: dieses Nest gilt als besucht
    LR.NextNest(s, false)
    LR.UpdateNestTicker()
    return true
end

---------------------------------------------------------------------------
-- Pfeil auf der Minikarte: Sprung und Zeile (Wunsch vom 24.11.2026; gezeichnet wird er von ezMap, LR.DrawArrow)
---------------------------------------------------------------------------

-- Soll der Pfeil jetzt zu sehen sein (Route mit Schritten, beide Schalter an, ezMap kann ihn zeichnen)?
function LR.ArrowWanted()
    local state, api = LR.State(), Map()
    return state ~= nil and state.steps[1] ~= nil and ns.Enabled("levelRoute") and ns.Enabled("routeMiniArrow")
        and api ~= nil and type(api.ShowMiniArrow) == "function" and type(api.ClearMiniArrow) == "function"
end

function LR.ForgetArrow()
    LR.arrowSpot, LR.arrowStep, LR.arrowMark, LR.arrowText, LR.nextUntil = nil, nil, nil, nil, nil
end

-- Woran ein Schritt nach dem Neurechnen (neue Tabellen) wiederzuerkennen ist: alle Teilziele bzw. Quests, sonst der Ort.
-- Nicht am ersten davon: Quest und laufendes Teilziel eines Schritts wandern, sobald eines erfüllt ist (Review vom
-- 24.11.2026)
local function StepMark(s)
    local keys = {}
    if s.parts then
        for _, part in ipairs(s.parts) do keys[LR.PartKey(part)] = true end
    else
        for _, q in ipairs(LR.QuestsOf(s)) do keys[tostring(q.id)] = true end
    end
    return { kind = s.kind, keys = keys, map = s.map, x = s.x, y = s.y }
end

local function SameStep(a, b)
    if a.kind ~= b.kind then return false end
    for k in pairs(a.keys) do
        if b.keys[k] then return true end
    end
    return next(a.keys) == nil and next(b.keys) == nil and LR.SamePlace(a, b)
end

-- Merken, wohin der Pfeil zeigt. → true, wenn er gegenüber vorher gesprungen ist (Aufleuchten); ein neuer Schritt zeigt
-- „Weiter: …“. Der erste Pfeil einer Route ist kein Sprung.
function LR.NoteJump(s, spot)
    local before, step, mark = LR.arrowSpot, LR.arrowStep, LR.arrowMark
    LR.arrowSpot, LR.arrowStep, LR.arrowMark = { map = spot.map, x = spot.x, y = spot.y }, s, StepMark(s)
    if not before then return false end
    local changed = s ~= step and not SameStep(LR.arrowMark, mark)
    if changed then LR.nextUntil = Core.Uptime() + LR.NEXT_SHOW end
    return changed or not LR.SamePlace(before, spot)
end

-- Bist du im Gebiet des Schritts? → true | false, Entfernung zum laufenden Nest bzw. Ort (Yards)
function LR.InArea(s, here)
    local d = WD(here, LR.Spot(s))
    if d <= LR.NEST_LEAVE then return true, d end
    for _, nest in ipairs(s.tour or {}) do
        if WD(here, nest) <= LR.NEST_LEAVE then return true, d end
    end
    return s.walked == true and d <= LR.AREA_GAP, d
end

-- Kurzer Name eines Schritts für „Weiter: …“
function LR.ShortStep(s)
    if s.kind == "turnin" then
        if s.name then return L.ROUTE_ARROW_TURNIN:format(s.name) end
        return L.ROUTE_ARROW_TURNIN_QUEST:format(s.quest and s.quest.title or "?")
    end
    if s.kind == "obj" then
        local quest = s.quest
        -- gemeinsamer Rundgang: die Quest des offenen Teilziels
        for _, part in ipairs(s.parts or {}) do
            if part.obj == s.obj then quest = part.quest end
        end
        return quest and quest.title or "?"
    end
    if s.kind == "vendor" then return L.ROUTE_STEP_VENDOR:format(s.name or "?") end
    return LR.StepText(s)
end

-- Offene Teilziele eines Schritts mit dem Stand laut Client („Eber getötet: 3/6“), mehrere: „… (+2)“ → Text oder nil
function LR.Progress(s)
    local first, more, lists = nil, 0, {}
    for _, so in ipairs(LR.ObjsOf(s)) do
        if not so.done then
            local qid = so.qid or (s.quest and s.quest.id)
            lists[qid] = lists[qid] or LR.Objectives(qid)
            local o = lists[qid][so.index]
            if first == nil then first = (o and o.text) or so.text or "" else more = more + 1 end
        end
    end
    if not first or first == "" then return nil end
    return more > 0 and ("%s (+%d)"):format(first, more) or first
end

-- Die Zeile am Pfeil oder nil (Schalter aus, unterwegs, Ort unbekannt)
function LR.ArrowText()
    if not (ns.Enabled("routeArrowText") and LR.ArrowWanted()) then return nil end
    local s, here = LR.State().steps[1], Here()
    if LR.nextUntil and Core.Uptime() < LR.nextUntil then
        local d = here and WD(here, LR.Spot(s)) or math.huge
        if d >= 10 and d < math.huge then
            return L.ROUTE_ARROW_NEXT_YARDS:format(LR.ShortStep(s), math.floor(d / 10 + 0.5) * 10)
        end
        return L.ROUTE_ARROW_NEXT:format(LR.ShortStep(s))
    end
    if not here then return nil end
    local inside, d = LR.InArea(s, here)
    local lines = {}
    if s.kind == "obj" then
        if not inside then return nil end
        lines[1] = LR.Progress(s) or LR.ShortStep(s)
        if s.tour and #s.tour > 1 then
            lines[2] = L.ROUTE_ARROW_SPOT:format(s.at or 1, #s.tour)
        elseif d <= LR.HERE then
            lines[2] = L.ROUTE_ARROW_HERE
        end
    else
        if d > LR.HERE then return nil end
        lines[1], lines[2] = LR.ShortStep(s), L.ROUTE_ARROW_HERE
    end
    return table.concat(lines, "\n")
end

-- Zeile nachziehen, ohne den Pfeil neu zu setzen → Text oder nil
function LR.UpdateArrowText()
    local api = Map()
    if not (api and type(api.MiniArrowText) == "function") then return nil end
    local text = LR.ArrowText()
    if text ~= LR.arrowText then
        LR.arrowText = text
        api.MiniArrowText(LR.OWNER, text)
    end
    return text
end

---------------------------------------------------------------------------
-- Anzeige: Karte und Tooltip
---------------------------------------------------------------------------

-- Nester des laufenden Schritts als kleine Punkte und der Rundgang als dünne Linie (ezMap, abschaltbar: routeArea)
-- → Zahl der gezeigten Nester
function LR.DrawArea()
    local api = Map()
    if not (api and type(api.ShowPath) == "function" and type(api.ClearPath) == "function") then return 0 end
    local s = LR.Current()
    local at = s and s.at or 1
    if not (s and s.tour and #s.tour - at + 1 >= 2 and ns.Enabled("levelRoute") and ns.Enabled("routeArea")) then
        api.ClearPath(LR.OWNER_AREA)
        return 0
    end
    local pts = {}
    for k = at, #s.tour do
        local nest = s.tour[k]
        local label = L.ROUTE_NEST_LABEL:format(k, #s.tour, nest.name or LR.StepText(s),
            Core.Plural(nest.n or 1, L.ROUTE_SPAWNS_ONE, L.ROUTE_SPAWNS_MANY))
        pts[#pts + 1] = { map = nest.map, x = nest.x, y = nest.y, label = label,
            icon = k == at and LR.NEST_ICON.next or LR.NEST_ICON.other }
    end
    return api.ShowPath(LR.OWNER_AREA, pts, { family = LR.AREA_FAMILY, marks = false, name = L.ROUTE_AREA_NAME,
        addon = "ezQuest" })
end

-- Zeilen zum Gebiet eines Ziel-Schritts für den Tooltip (Leitlinie 11: Quelle und „geschätzt“; Grenzen nennen)
function LR.AreaLines(s)
    local lines = {}
    if not LR.HasArea(s) then return lines end
    local spawns = 0
    for _, nest in ipairs(s.tour or {}) do spawns = spawns + (nest.n or 1) end
    lines[#lines + 1] = L.ROUTE_TIP_AREA:format(Core.Plural(#(s.tour or {}), L.ROUTE_NESTS_ONE, L.ROUTE_NESTS_MANY),
        Core.Plural(spawns, L.ROUTE_SPAWNS_ONE, L.ROUTE_SPAWNS_MANY), math.floor((s.tourLen or 0) + 0.5))
    local byClient, other = false, false
    for _, part in ipairs(s.parts) do
        local text
        if part.byClient then
            byClient, text = true, L.ROUTE_TIP_AREA_CLIENT
        elseif part.area and part.clientArea then
            other = true
            if part.area == part.clientArea then
                text = L.ROUTE_TIP_AREA_SAME
            else
                text = LR.AreaWait(part.clientArea, LR.PartKills(part)) > 0 and L.ROUTE_TIP_AREA_BIGGER or L.ROUTE_TIP_AREA_KEPT
            end
        end
        if text and not lines[text] then
            lines[#lines + 1], lines[text] = text, true
        end
    end
    for _, part in ipairs(s.parts) do
        if part.area and not part.obj.done and LR.AreaWait(part.area, LR.PartKills(part), s.tourLen) > 0 then
            lines[#lines + 1] = L.ROUTE_TIP_AREA_FEW:format(Core.Plural(part.area.n, L.ROUTE_SPAWNS_ONE, L.ROUTE_SPAWNS_MANY))
        end
    end
    -- weitere Gebiete: gewählt nach Umweg – oder von Blizzards Punkt (dann ohne „kleinster Umweg“; Review vom 22.11.2026)
    if (s.groups or 1) > 1 then
        lines[#lines + 1] = ((byClient or other) and L.ROUTE_TIP_GROUPS_CLIENT or L.ROUTE_TIP_GROUPS):format(s.groups - 1)
    end
    if s.quests then lines[#lines + 1] = L.ROUTE_TIP_AREA_JOINED end
    lines[#lines + 1] = L.ROUTE_TIP_LIMITS
    return lines
end
