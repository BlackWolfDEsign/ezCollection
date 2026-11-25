local _, ns = ...
local Core = ezCore

--[[
    Routen-Rechner (SAM-17, Welle 14; docs/archiv/abloesung-analyse.md Teil B, Erwartung „Routen“, Risiko 10): aus einer
    Menge von Punkten (Sammel-Fundorte) eine kurze Runde je Karte. Nur Rechnung – gezeichnet wird nichts (Linie auf
    Karte und Minikarte: ezMap, Welle 15; Sperrgebiete sind nicht eingeplant).

      Route.Build(punkte, optionen) → auftrag | ergebnis
          punkte   = { { x, y (0–1), map (Speicherkarte; fehlt sie: optionen.map) … } … } – weitere Felder bleiben am
                     Punkt (die Route nennt die Eingabepunkte, zusammengefasste als Gruppe)
          optionen = { merge = Yards (nahe Punkte zusammenfassen, Standard Route.MERGE; 0 = aus),
                       max = höchstens so viele Punkte je Karte nach dem Zusammenfassen (Standard Route.MAX; der Rest
                             fällt weg, ergebnis.maps[map].capped = Zahl),
                       closed = false (offener Weg statt Runde; Standard: Runde zurück zum Anfang),
                       start = { x, y } (Anfang: der Punkt, der dieser Stelle am nächsten liegt; Standard der erste),
                       yards = fn(map) → breite, höhe (Standard Core.Discovery.MapYards; ohne Größe wird in
                               Kartenanteilen gerechnet, ergebnis.maps[map].units = "map"),
                       slice = Rechenschritte je Bild (Standard Route.SLICE),
                       sync = true (alles sofort, Rückgabe ist das Ergebnis – für Prüfungen und kleine Mengen),
                       onProgress = fn(fertig, gesamt, karte) – fertige Karten, Karten gesamt, Karte in Arbeit; je
                                    Scheibe und nach jeder Karte, onDone = fn(ergebnis), owner = Modulname }
          ohne sync: Rechnung in Scheiben über mehrere Bilder (C_Timer.After(0)); Rückgabe ist ein Auftrag
          { Cancel(), Done() → bool, Result() → ergebnis | nil }
          ergebnis = { maps = { [map] = { points = { gruppe … } in Reihenfolge, length = Länge (Yards bzw.
                       Kartenanteile), input = Zahl der Eingabepunkte, merged = zusammengefasst, capped, units } },
                       order = { map … } (aufsteigend), length = Summe in Yards (Karten ohne Größe zählen nicht) }
          gruppe   = { x, y (Mittel), map, n (Zahl der Eingabepunkte), members = { punkt … } }
    Bausteine (reine Funktionen, auch einzeln geprüft):
      Route.Merge(punkte, radius, breite, höhe, takt) → gruppen   nächste Gruppe im Umkreis radius (Yards), gesucht
                                     über ein Raster mit Zellen von radius Yards (nur die 3 × 3 Nachbarzellen)
      Route.Nearest(gruppen, breite, höhe, anfang, takt) → reihenfolge (Indizes)   nächster Nachbar
      Route.TwoOpt(gruppen, reihenfolge, breite, höhe, runde, takt) → reihenfolge   2-opt bis keine Kürzung mehr
      Route.Length(gruppen, reihenfolge, breite, höhe, runde) → Länge
    takt (optional) ist eine Funktion, die je Rechenschritt gerufen wird – Route.Build hält dort die Scheiben an.
    Flugrouten (Welle 26, F5; unten): Route.FlightNodes, Route.FlightPath, Route.MissingFlightNodes – laut Client-Tabellen.
    Leveling-Route (Welle 27, ezQuest; unten): freiwillige Angaben opts für Nearest, TwoOpt und Length (dist, after bzw.
    allowed für den Vorrang, cost für die Bewertung, rounds), dazu Route.Valid, Route.Relocate, Route.Insert,
    Route.World und Route.WorldDistance (Weltkoordinaten in Yards). Ohne opts rechnet alles wie vorher.
]]

local Route = {}
Core.Route = Route

Route.MERGE = 15      -- Yards: so nah gelten Punkte als eine Stelle (wie der Entdoppel-Umkreis der Datenbank)
Route.MAX = 400       -- Punkte je Karte nach dem Zusammenfassen (2-opt wächst quadratisch)
Route.SLICE = 4000    -- Rechenschritte je Bild
Route.TWO_OPT_ROUNDS = 50   -- höchstens so viele Durchgänge 2-opt je Karte

local Num = Core.Num

local function Dist(a, b, w, h)
    local dx, dy = (a.x - b.x) * w, (a.y - b.y) * h
    return math.sqrt(dx * dx + dy * dy)
end
Route.Distance = Dist

-- Zusammenfassen über ein Raster mit Zellen von radius Yards: eine Gruppe im Umkreis liegt mit ihrer Mitte höchstens
-- eine Zelle entfernt, also genügen die 3 × 3 Nachbarzellen (statt jedes Punkts gegen jede Gruppe)
local function Cell(x, y, cw, ch) return math.floor(x / cw), math.floor(y / ch) end

local function CellAdd(grid, cx, cy, g)
    local col = grid[cx]
    if not col then col = {} grid[cx] = col end
    local list = col[cy]
    if not list then list = {} col[cy] = list end
    list[#list + 1] = g
    g.cx, g.cy = cx, cy
end

local function CellRemove(grid, g)
    local list = grid[g.cx] and grid[g.cx][g.cy]
    for i = #(list or {}), 1, -1 do
        if list[i] == g then table.remove(list, i) return end
    end
end

function Route.Merge(points, radius, w, h, tick)
    w, h, radius = Num(w) or 1, Num(h) or 1, Num(radius) or 0
    local groups, grid = {}, {}
    local cw, ch = radius / w, radius / h
    for _, p in ipairs(type(points) == "table" and points or {}) do
        local x, y = Num(type(p) == "table" and p.x), Num(type(p) == "table" and p.y)
        if x and y then
            local into, best, looked = nil, nil, 0
            if radius > 0 then
                local px, py = Cell(x, y, cw, ch)
                for cx = px - 1, px + 1 do
                    local col = grid[cx]
                    if col then
                        for cy = py - 1, py + 1 do
                            for _, g in ipairs(col[cy] or {}) do
                                local dx, dy = (g.x - x) * w, (g.y - y) * h
                                local d = math.sqrt(dx * dx + dy * dy)
                                looked = looked + 1
                                if d <= radius and (not best or d < best or (d == best and g.i < into.i)) then
                                    into, best = g, d
                                end
                            end
                        end
                    end
                end
            end
            if into then
                into.n = into.n + 1
                into.sx, into.sy = into.sx + x, into.sy + y
                into.x, into.y = into.sx / into.n, into.sy / into.n
                into.members[#into.members + 1] = p
                local nx, ny = Cell(into.x, into.y, cw, ch)
                if nx ~= into.cx or ny ~= into.cy then
                    CellRemove(grid, into)
                    CellAdd(grid, nx, ny, into)
                end
            else
                local g = { x = x, y = y, sx = x, sy = y, n = 1, map = p.map, members = { p }, i = #groups + 1 }
                groups[#groups + 1] = g
                if radius > 0 then
                    local cx, cy = Cell(x, y, cw, ch)
                    CellAdd(grid, cx, cy, g)
                end
            end
            if tick then tick(1 + looked) end
        end
    end
    for _, g in ipairs(groups) do g.sx, g.sy, g.cx, g.cy, g.i = nil, nil, nil, nil, nil end
    return groups
end

-- Abstand zweier Gruppen: opts.dist (etwa Route.WorldDistance für Punkte in Weltkoordinaten), sonst innerhalb einer
-- Karte über breite × höhe (Welle 27; ohne opts wie vorher)
local function DistFn(w, h, opts)
    if type(opts) == "table" and type(opts.dist) == "function" then return opts.dist end
    return function(a, b) return Dist(a, b, w, h) end
end

function Route.Length(groups, order, w, h, closed, opts)
    w, h = Num(w) or 1, Num(h) or 1
    local D = DistFn(w, h, opts)
    local n, len = #order, 0
    for i = 2, n do len = len + D(groups[order[i - 1]], groups[order[i]]) end
    if closed ~= false and n > 2 then len = len + D(groups[order[n]], groups[order[1]]) end
    return len
end

---------------------------------------------------------------------------
-- Vorrang (Welle 27, Leveling-Route in ezQuest; Entscheidung 11 des Nutzers vom 17.11.2026): „Station b erst nach den
-- Stationen a1, a2 …“ als Tabelle opts.after = { [b] = { a1, a2 … } } (Indizes der Gruppen) – schnell geprüft über die
-- Stellung je Station – oder als Rückruf opts.allowed(reihenfolge, i) → darf die Station reihenfolge[i] an Stelle i
-- stehen, gegeben reihenfolge[1 … i-1]? (allgemein, je Stelle ein Durchgang über den Anfang).
---------------------------------------------------------------------------

-- Umkehrung von after: before[a] = { b … } (a muss vor jedem b stehen)
local function BeforeOf(after)
    local before = {}
    for b, list in pairs(after) do
        for _, a in ipairs(list) do
            local l = before[a]
            if not l then l = {} before[a] = l end
            l[#l + 1] = b
        end
    end
    return before
end

local function Positions(order)
    local pos = {}
    for i, idx in ipairs(order) do pos[idx] = i end
    return pos
end

-- Hält die Reihenfolge den Vorrang an den Stellen von bis bis ein? (ohne Angaben: ja)
function Route.Valid(order, opts, from, to)
    if type(opts) ~= "table" then return true end
    from, to = Num(from) or 1, Num(to) or #order
    local after, allowed = type(opts.after) == "table" and opts.after or nil, opts.allowed
    if after then
        local pos = Positions(order)
        for i = from, to do
            for _, a in ipairs(after[order[i]] or {}) do
                if pos[a] and pos[a] > i then return false end
            end
        end
    end
    if type(allowed) == "function" then
        for i = from, to do
            if not allowed(order, i) then return false end
        end
    end
    return true
end

-- Nächster Nachbar ab der Gruppe first. opts (Welle 27, freiwillig): dist, after bzw. allowed (nur Stationen, deren
-- Vorrang erfüllt ist; lässt er keine zu, die nächste ohne Vorrang – die Rechnung endet immer).
function Route.Nearest(groups, w, h, first, tick, opts)
    w, h = Num(w) or 1, Num(h) or 1
    local D = DistFn(w, h, opts)
    local after = type(opts) == "table" and type(opts.after) == "table" and opts.after or nil
    local allowed = type(opts) == "table" and type(opts.allowed) == "function" and opts.allowed or nil
    local n = #groups
    if n == 0 then return {} end
    local used, order = {}, {}
    local cur = math.max(1, math.min(n, Num(first) or 1))
    used[cur], order[1] = true, cur
    local function Ok(j)
        for _, a in ipairs(after and after[j] or {}) do
            if not used[a] then return false end
        end
        if allowed then
            order[#order + 1] = j
            local ok = allowed(order, #order) and true or false
            order[#order] = nil
            return ok
        end
        return true
    end
    for _ = 2, n do
        local best, bestD
        for j = 1, n do
            if not used[j] and ((not after and not allowed) or Ok(j)) then
                local d = D(groups[cur], groups[j])
                if not bestD or d < bestD then best, bestD = j, d end
            end
        end
        if not best then
            for j = 1, n do
                if not used[j] then
                    local d = D(groups[cur], groups[j])
                    if not bestD or d < bestD then best, bestD = j, d end
                end
            end
        end
        if tick then tick(n) end
        used[best] = true
        order[#order + 1] = best
        cur = best
    end
    return order
end

local function Reverse(order, lo, hi)
    while lo < hi do
        order[lo], order[hi] = order[hi], order[lo]
        lo, hi = lo + 1, hi - 1
    end
end

-- Vorrang nach dem Umdrehen von lo … hi: verletzt werden kann nur ein Paar, das ganz im Abschnitt liegt (die Mengen
-- davor und danach bleiben gleich). pos = Stellung je Station vor dem Umdrehen.
local function ReverseOk(order, lo, hi, opts, after, pos)
    if after then
        for k = lo, hi do
            for _, a in ipairs(after[order[k]] or {}) do
                local p = pos[a]
                if p and p >= lo and p <= hi then return false end
            end
        end
    end
    if type(opts) == "table" and type(opts.allowed) == "function" then
        Reverse(order, lo, hi)
        local ok = Route.Valid(order, { allowed = opts.allowed }, lo, hi)
        Reverse(order, lo, hi)
        return ok
    end
    return true
end

-- 2-opt: kehrt den Abschnitt i+1 … j um, solange das die Strecke kürzt (Runde: auch die Kante zurück zum Anfang).
-- Die erste Stelle bleibt immer, wo sie ist. opts (Welle 27, freiwillig; ohne sie wie vorher): dist, after bzw. allowed
-- (ein Zug, der den Vorrang verletzt, unterbleibt), cost(reihenfolge) → Bewertung statt der Länge (kleiner ist besser;
-- jeder Zug wird ganz bewertet), rounds = höchstens so viele Durchgänge (Standard Route.TWO_OPT_ROUNDS).
function Route.TwoOpt(groups, order, w, h, closed, tick, opts)
    w, h = Num(w) or 1, Num(h) or 1
    local n = #order
    local cost = type(opts) == "table" and type(opts.cost) == "function" and opts.cost or nil
    if n < 4 and not (cost and n >= 3) then return order end
    local D = DistFn(w, h, opts)
    local after = type(opts) == "table" and type(opts.after) == "table" and opts.after or nil
    local checks = after ~= nil or (type(opts) == "table" and type(opts.allowed) == "function")
    local maxRounds = type(opts) == "table" and Num(opts.rounds) or Route.TWO_OPT_ROUNDS
    local function P(i) return groups[order[i]] end
    local current = cost and cost(order) or nil
    local pos = checks and Positions(order) or nil
    local improved, rounds = true, 0
    while improved and rounds < maxRounds do
        improved, rounds = false, rounds + 1
        for i = 1, n - 2 do
            local a, b = P(i), P(i + 1)
            for j = i + 2, n do
                local lo, hi = i + 1, j
                if cost then
                    -- Bewertung: zuerst der Vorrang (billig), dann umdrehen, ganz bewerten, sonst zurück
                    if not checks or ReverseOk(order, lo, hi, opts, after, pos) then
                        Reverse(order, lo, hi)
                        local value = cost(order)
                        if value < current - 1e-9 then
                            current, improved = value, true
                            if pos then pos = Positions(order) end
                            a, b = P(i), P(i + 1)
                        else
                            Reverse(order, lo, hi)
                        end
                        if tick then tick(n) end
                    end
                else
                    local c = P(j)
                    local d
                    if j < n then d = P(j + 1) elseif closed ~= false then d = P(1) end
                    local gain
                    if d and not (closed ~= false and i == 1 and j == n) then
                        gain = D(a, b) + D(c, d) - (D(a, c) + D(b, d))
                    elseif not d and closed == false then
                        -- offener Weg: das Ende umdrehen, wenn das kürzt (Kante i » i+1 gegen i » n)
                        gain = D(a, b) - D(a, c)
                    end
                    if gain and gain > 1e-9 and (not checks or ReverseOk(order, lo, hi, opts, after, pos)) then
                        Reverse(order, lo, hi)
                        improved = true
                        if pos then pos = Positions(order) end
                        a, b = P(i), P(i + 1)
                    end
                end
                if tick then tick(1) end
            end
        end
    end
    return order
end

-- Verschieben einzelner Stationen (Welle 27): nimmt je Durchgang jede Station heraus und setzt sie an die Stelle, an der
-- die Bewertung am stärksten sinkt – nur, wenn der Vorrang hält. Ohne opts.cost zählt die Länge des offenen Wegs.
-- opts.fixed ~= false: die erste Stelle bleibt (Anfang). opts.rounds: höchstens so viele Durchgänge (Standard
-- Route.RELOCATE_ROUNDS). → reihenfolge (dieselbe Tabelle)
Route.RELOCATE_ROUNDS = 10
function Route.Relocate(groups, order, opts, tick)
    opts = type(opts) == "table" and opts or {}
    local n = #order
    local first = opts.fixed == false and 1 or 2
    if n - first < 1 then return order end
    local D = DistFn(1, 1, opts)
    local cost = type(opts.cost) == "function" and opts.cost or function(o)
        return Route.Length(groups, o, 1, 1, false, { dist = D })
    end
    local after = type(opts.after) == "table" and opts.after or nil
    local before = after and BeforeOf(after) or nil
    local current = cost(order)
    local maxRounds = Num(opts.rounds) or Route.RELOCATE_ROUNDS
    for _ = 1, maxRounds do
        local improved = false
        for p = first, n do
            local s = table.remove(order, p)
            local pos = Positions(order)
            local bestQ, bestValue
            for q = first, n do
                if q ~= p then
                    -- s an Stelle q (gezählt in der Reihenfolge ohne s): alle Vorgänger von s davor, alle Nachfolger danach
                    local ok = true
                    for _, a in ipairs(after and after[s] or {}) do
                        if pos[a] and pos[a] >= q then ok = false break end
                    end
                    if ok then
                        for _, b in ipairs(before and before[s] or {}) do
                            if pos[b] and pos[b] < q then ok = false break end
                        end
                    end
                    if ok then
                        table.insert(order, q, s)
                        if type(opts.allowed) == "function" then
                            ok = Route.Valid(order, { allowed = opts.allowed }, math.min(p, q), math.max(p, q))
                        end
                        if ok then
                            local value = cost(order)
                            if value < (bestValue or current) - 1e-9 then bestQ, bestValue = q, value end
                        end
                        table.remove(order, q)
                    end
                    if tick then tick(n) end
                end
            end
            table.insert(order, bestQ or p, s)
            if bestQ then current, improved = bestValue, true end
        end
        if not improved then break end
    end
    return order
end

-- Einfügen (Welle 27): die Stationen new (Liste von Indizes, in dieser Folge) je an die günstigste Stelle der
-- Reihenfolge, ohne die übrigen anzufassen; eine Station steht nie vor ihren Vorgängern (after). Bewertung opts.cost,
-- sonst der Umweg (Abstand davor + danach − direkt). opts.fixed wie bei Relocate. → reihenfolge (dieselbe Tabelle)
function Route.Insert(groups, order, new, opts)
    opts = type(opts) == "table" and opts or {}
    local D = DistFn(1, 1, opts)
    local after = type(opts.after) == "table" and opts.after or nil
    local before = after and BeforeOf(after) or nil
    local first = opts.fixed == false and 1 or 2
    for _, s in ipairs(type(new) == "table" and new or {}) do
        local pos = Positions(order)
        local lo, hi = math.min(first, #order + 1), #order + 1
        for _, a in ipairs(after and after[s] or {}) do
            if pos[a] then lo = math.max(lo, pos[a] + 1) end
        end
        for _, b in ipairs(before and before[s] or {}) do
            if pos[b] then hi = math.min(hi, pos[b]) end
        end
        local bestQ, bestValue
        for q = lo, math.max(lo, hi) do
            local value
            if type(opts.cost) == "function" then
                table.insert(order, q, s)
                local ok = type(opts.allowed) ~= "function" or Route.Valid(order, { allowed = opts.allowed }, q, #order)
                value = ok and opts.cost(order) or nil
                table.remove(order, q)
            else
                local prev, nextOne = order[q - 1], order[q]
                local g = groups[s]
                value = 0
                if prev then value = value + D(groups[prev], g) end
                if nextOne then value = value + D(g, groups[nextOne]) end
                if prev and nextOne then value = value - D(groups[prev], groups[nextOne]) end
            end
            if value and (not bestValue or value < bestValue - 1e-9) then bestQ, bestValue = q, value end
        end
        table.insert(order, bestQ or (#order + 1), s)
    end
    return order
end

---------------------------------------------------------------------------
-- Weltkoordinaten (Welle 27): Punkte über Kartengrenzen hinweg vergleichen. Blizzards Weltkoordinaten zählen in Yards
-- (dieselbe Einheit wie C_Map.GetMapWorldSize, die Discovery.MapYards als Yards nimmt; warcraft.wiki.gg, API
-- C_Map.GetMapWorldSize) – die Beschreibung von Core.Map.WorldPos in Kern/Util.lua nennt noch „Meter“.
--   Route.World(punkt) → true | false: setzt punkt.continent, punkt.wx, punkt.wy aus punkt.map, punkt.x, punkt.y
--   Route.WorldDistance(a, b) → Yards; math.huge auf verschiedenen Kontinenten oder ohne Weltlage
---------------------------------------------------------------------------

function Route.World(p)
    if type(p) ~= "table" then return false end
    local M = Core.Map
    if not (M and type(M.WorldPos) == "function") then return false end
    local continent, wx, wy = M.WorldPos(p.map, p.x, p.y)
    if not continent then return false end
    p.continent, p.wx, p.wy = continent, wx, wy
    return true
end

function Route.WorldDistance(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return math.huge end
    local ax, ay, bx, by = Num(a.wx), Num(a.wy), Num(b.wx), Num(b.wy)
    if not (ax and ay and bx and by) or a.continent == nil or a.continent ~= b.continent then return math.huge end
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

-- Anfang: Index der Gruppe, die der Stelle start am nächsten liegt
local function StartIndex(groups, start, w, h)
    local x, y = Num(type(start) == "table" and start.x), Num(type(start) == "table" and start.y)
    if not (x and y) then return 1 end
    local here = { x = x, y = y }
    local best, bestD = 1, nil
    for i, g in ipairs(groups) do
        local d = Dist(g, here, w, h)
        if not bestD or d < bestD then best, bestD = i, d end
    end
    return best
end

-- Die ganze Rechnung; tick(n) zählt Rechenschritte (in Scheiben: dort hält der Auftrag an)
local function Compute(points, opts, tick, progress)
    progress = progress or {}
    local byMap, maps = {}, {}
    for _, p in ipairs(type(points) == "table" and points or {}) do
        local map = type(p) == "table" and (p.map or opts.map) or nil
        if map ~= nil and Num(p.x) and Num(p.y) then
            local list = byMap[map]
            if not list then list = {} byMap[map] = list maps[#maps + 1] = map end
            list[#list + 1] = p
        end
    end
    table.sort(maps, function(a, b)
        if type(a) == type(b) then return a < b end
        return type(a) == "number"
    end)
    progress.total = #maps
    local yards = type(opts.yards) == "function" and opts.yards or function(map)
        local D = Core.Discovery
        if D and D.MapYards then return D.MapYards(map) end
        return nil
    end
    local result = { maps = {}, order = maps, length = 0 }
    local merge = Num(opts.merge) or Route.MERGE
    local max = Num(opts.max) or Route.MAX
    for index, map in ipairs(maps) do
        local list = byMap[map]
        progress.map, progress.done = map, index - 1
        local w, h = yards(map)
        w, h = Num(w), Num(h)
        local units = "yards"
        if not (w and h) or w <= 0 or h <= 0 then w, h, units = 1, 1, "map" end
        local groups = Route.Merge(list, units == "yards" and merge or 0, w, h, tick)
        local capped
        if #groups > max then
            capped = #groups - max
            for i = #groups, max + 1, -1 do groups[i] = nil end
        end
        for _, g in ipairs(groups) do g.map = map end
        local order = Route.Nearest(groups, w, h, StartIndex(groups, opts.start, w, h), tick)
        order = Route.TwoOpt(groups, order, w, h, opts.closed, tick)
        local sorted = {}
        for i, idx in ipairs(order) do sorted[i] = groups[idx] end
        local same = {}
        for i = 1, #sorted do same[i] = i end
        local len = Route.Length(sorted, same, w, h, opts.closed)
        result.maps[map] = { points = sorted, length = len, input = #list, merged = #list - #groups - (capped or 0),
            capped = capped, units = units }
        if units == "yards" then result.length = result.length + len end
        progress.done = index
        if opts.onProgress then Core.Try(opts.owner, "Route progress", opts.onProgress, index, #maps, map) end
    end
    return result
end

function Route.Build(points, opts)
    opts = type(opts) == "table" and opts or {}
    if opts.sync then
        local result = Compute(points, opts, nil)
        if opts.onDone then Core.Try(opts.owner, "Route done", opts.onDone, result) end
        return result
    end
    local job = { done = false, cancelled = false }
    local slice, spent, progress = Num(opts.slice) or Route.SLICE, 0, {}
    local co = coroutine.create(function()
        return Compute(points, opts, function(n)
            spent = spent + (n or 1)
            if spent >= slice then
                spent = 0
                -- Zwischenstand je Scheibe: fertige Karten, Karten gesamt, Karte in Arbeit
                if opts.onProgress then
                    Core.Try(opts.owner, "Route progress", opts.onProgress, progress.done or 0, progress.total or 0, progress.map)
                end
                coroutine.yield()
            end
        end, progress)
    end)
    local function Step()
        if job.cancelled or job.done then return end
        local ok, result = coroutine.resume(co)
        if not ok then
            job.done = true
            Core.Error(opts.owner or Core.name, result, "Route.Build")
            return
        end
        if coroutine.status(co) == "dead" then
            job.done, job.result = true, result
            if opts.onDone then Core.Try(opts.owner, "Route done", opts.onDone, result) end
            return
        end
        C_Timer.After(0, Step)
    end
    function job.Cancel() job.cancelled = true end
    function job.Done() return job.done end
    function job.Result() return job.result end
    Step()
    return job
end

---------------------------------------------------------------------------
-- Flugrouten (Welle 26, F5, Paket kern/wago-wissen): Flugpunkte und Strecken samt Kosten laut Client-Tabellen
-- (TaxiNodes, TaxiPath; ezCore.ClientData). Was ein Charakter kennt, sagt nur Blizzards Flugkarte (C_TaxiMap am
-- Flugmeister); der Preis dort (TaxiNodeCost) geht den Tabellen vor.
--   Route.FlightNodes(kontinent, fraktion) → { { id, continent, x, y, alliance, horde } … } (fraktion "Alliance" |
--       "Horde" | nil)
--   Route.FlightPath(von, nach, fraktion) → { nodes = { id … } (von bis nach), cost = Kupfer (Summe der Teilstrecken),
--       hops = Zahl der Strecken, source = "tables" } oder nil – günstigster Weg über die Strecken der Tabellen; mit
--       fraktion nur über Flugpunkte, an denen sie fliegt
--   Route.MissingFlightNodes(bekannt, kontinent, fraktion) → { Flugpunkt-ID … }: Flugpunkte, die nicht in bekannt
--       ({ [ID] = true }) stehen und zu denen eine Strecke führt – „welche Flugpunkte kennt der Twink noch nicht“
--       (ohne Nachtruhe 62/63 und den Seuchenwaldturm 84: von dort fliegt man nur weg; 24.11.2026)
---------------------------------------------------------------------------

local function FactionOK(node, faction)
    if not node then return false end
    if faction == "Alliance" then return node.alliance end
    if faction == "Horde" then return node.horde end
    return true
end

function Route.FlightNodes(continent, faction)
    local CD = Core.ClientData
    return CD and CD.TaxiNodes and CD.TaxiNodes(continent, faction) or {}
end

function Route.FlightPath(from, to, faction)
    local CD = Core.ClientData
    from, to = Num(from), Num(to)
    if not (CD and CD.TaxiNode and from and to) then return nil end
    if not (FactionOK(CD.TaxiNode(from), faction) and FactionOK(CD.TaxiNode(to), faction)) then return nil end
    if from == to then return { nodes = { from }, cost = 0, hops = 0, source = "tables" } end
    -- Dijkstra über wenige Knoten (rund 100): einfache Suche nach dem kleinsten offenen Wert
    local dist, prev, done = { [from] = 0 }, {}, {}
    while true do
        local cur, best
        for id, d in pairs(dist) do
            if not done[id] and (not best or d < best or (d == best and id < cur)) then cur, best = id, d end
        end
        if not cur or cur == to then break end
        done[cur] = true
        for _, p in ipairs(CD.TaxiPaths(cur)) do
            if not done[p.to] and FactionOK(CD.TaxiNode(p.to), faction) then
                local d = best + (p.cost or 0)
                if not dist[p.to] or d < dist[p.to] then dist[p.to], prev[p.to] = d, cur end
            end
        end
    end
    if not dist[to] then return nil end
    local nodes, id = {}, to
    while id do
        table.insert(nodes, 1, id)
        id = prev[id]
    end
    return { nodes = nodes, cost = dist[to], hops = #nodes - 1, source = "tables" }
end

function Route.MissingFlightNodes(known, continent, faction)
    local list = {}
    known = type(known) == "table" and known or {}
    local CD = Core.ClientData
    local arrivals = CD and CD.TaxiArrivals and CD.TaxiArrivals() or {}
    for _, node in ipairs(Route.FlightNodes(continent, faction)) do
        if not known[node.id] and arrivals[node.id] then list[#list + 1] = node.id end
    end
    return list
end
