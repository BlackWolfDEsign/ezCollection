local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Routen durch eine Zone (SAM-21, Welle 15; docs/archiv/abloesung-analyse.md Teil B, Erwartung „Routen“).

    Menüeintrag „Route durch diese Zone“ im ezMap-Kartenmenü und in der Gruppe „Sammeln“ (Blizzards Kartenfilter bzw.
    Untermenü „Sammel-Fundorte“): Arten wählen (gemerkt), „Route berechnen“. Gerechnet wird mit ezCores Routen-Rechner
    (Core.Route.Build: nahe Punkte zusammenfassen, nächster Nachbar, 2-opt) in Scheiben über mehrere Bilder; solange er
    rechnet, steht im Menü „Route wird berechnet …“ mit der Zahl der Schritte und „Abbrechen“, am Anfang und am Ende
    eine Chatzeile. Die Punkte sind die eigenen Fundorte der gezeigten Zone (Core.Gathering.Nodes, dieselben Filter wie
    auf der Karte: Haken je Art egal, Rang, Kisten nur auf Wunsch, ausgeblendete Vorkommen nicht).

    Je Zone eine gemerkte Route: ezMapDB.routes[uiMapID] = { pts = { { x, y, n } … } in Reihenfolge, kinds, len, units,
    t, at (nächster Punkt), following (Markierung folgt der Route), merged, capped, input }; die Auswahl der Arten in
    ezMapDB.routes._kinds.

    Gezeichnet:
      - Weltkarte: eigene Linien (CreateLine) auf einem Rahmen als Kind von Blizzards Kartenfläche, eine Ebene unter
        ezCores Punkteschicht – nur auf der Karte der Route, Dicke bei jeder Zoomstufe gleich. Haken routeLine.
        Rahmenstufe seit dem Spielbefund vom 18.11.2026 (Linien unsichtbar): über Blizzards Flächen (Erkundung, Nebel,
        Quest-Flächen ab Stufe 2000, Core.MapPins.LayerLevel), nicht mehr nur Kartenfläche + 9 – darunter deckte vermutlich
        das Kartenbild der erkundeten Gebiete die Linien zu. /ezmap status nennt die gezeichneten Strecken oder den Grund.
        Seit dem Spielbefund vom 18.11.2026 über ns.RouteDraw (RouteDraw.lua, dieselbe Zeichnung wie die Leveling-Route):
        Pfeile in Laufrichtung, Nummern an den Punkten (bis 19.11.2026), und stehst du auf der Karte, beginnt
        die Linie bei dir und folgt dir bei offener Karte; das abgelaufene Stück zum nächsten Punkt entfällt
        (Route.LineSeq).
        Seit dem Spieltest vom 19.11.2026 („ich erkenne nicht welche route was ist und was bringen dem spieler die
        punkte mit den zahlen?“): eigene Farbfamilie Blau, gestrichelt, mit Verlauf vom nächsten Punkt (kräftig) zum
        Ende (blass); ab Werk nur am nächsten Punkt eine Marke mit Nummer und Rohstoff (Schalter routeNumbers: alle);
        der Tooltip über Marke und Linie nennt „Sammel-Route (ezMap)“, den Punkt mit seinen Vorkommen und die Entfernung.
        Die Vorkommen je Punkt merkt Finish (Feld what, höchstens Route.WHAT_MAX); ältere Routen ohne what nennen nur
        „Route: Punkt n von m“.
      - Minikarte: nur der nächste Punkt der Route als runder, halb durchsichtiger Kreis in der Farbe der Route über
        ezCores Punkteschicht (Anbieter „ezMap.route“, Feld minikarte), solange er im Sichtbereich liegt. Spieltest vom
        19.11.2026, wörtlich „siehe minimap - was soll das?!“: vorher stand dort die ganze Runde als Punktreihe alle 10
        Yards (sah aus wie eine Linie quer über die Minikarte bis zum Rand) und der nächste Punkt als gelbes Quadrat
        (WHITE8X8). Die Richtung zu einem Punkt außerhalb zeigt Blizzards eigener Pfeil zur Markierung, wenn sie verfolgt
        wird (Schalter wayTrack oder Klick auf die Markierung) – kein eigener Pfeil, nichts an den Rand geklemmt. Nur, wenn
        Minikarten-Punkte laufen (Gather.MiniActive) und der Haken routeMini an ist.
    „Nächster Punkt“ setzt Blizzards Markierung (ns.Way.Set); erntest du in der Nähe des nächsten (oder übernächsten)
    Punkts (Route.REACH Yards, Nachricht GATHERING_HARVEST), rückt sie weiter – ohne Klick nur die Markierung, Blizzards
    Zielverfolgung (Pfeil) nur mit ezMaps Schalter wayTrack (ab Werk aus; Welle 29, NACH-27, Risiko 20 der Prüfung auf
    Blizzards Regeln vom 17.11.2026). „Route löschen“ vergisst die Route der
    Zone und nimmt die eigene Markierung weg. Keine Sperrgebiete, kein Flugmeister-Routenplaner (MAP-04 bleibt).
    Taint: nur hooksecurefunc/HookScript an der Weltkarte, nichts in Blizzards Tabellen; kein Fenster unter UIParent.
]]
local Route = {}
ns.Route = Route

Route.PROVIDER = "ezMap.route"
Route.PATHS_PROVIDER = "ezMap.paths"   -- Symbole an Wegen anderer Module (ShowPath, unten)
Route.PATH_PIN_SIZE = 16    -- Bildpunkte: Symbol eines Wegpunkts mit eigenem Symbol (etwa ein Sammel-Abstecher)
Route.PATH_ORDER = 25       -- Platz bei ezCores Punkteschicht: vor der Sammel-Route (30) und allen Fundorten
Route.REACH = 25            -- Yards: so nah am nächsten Punkt rückt eine Ernte weiter
Route.REACH_MAP = 0.02      -- dasselbe in Kartenanteilen, wenn die Karte keine Größe hat
Route.ORDER = 30            -- Platz bei ezCores Punkteschicht: vor Eingängen (40), Büchern (45), Fundorten (50)
Route.NEXT_SIZE = 16        -- Bildpunkte: Kreis des nächsten Punkts auf der Minikarte (etwas größer als ein Fundort)
Route.MINI_ALPHA = 0.6      -- seine Deckkraft: das Symbol des Fundorts darunter bleibt zu sehen
Route.LEVEL = 9             -- Rahmenebene über der Kartenfläche (ezCores Punkteschicht: 10)
Route.AREA_GAP = 1          -- mindestens so viele Stufen über Blizzards Flächen (ezCores Punkteschicht: 2, darüber)
Route.FAMILY = "blue"       -- Farbfamilie der Sammel-Route (ns.RouteDraw.FAMILY; Spieltest 19.11.2026)
Route.PATH_FAMILY = "gold"  -- Farbfamilie der Wege anderer Module ohne eigene Angabe (ezQuests Leveling-Route)
Route.TEXTURE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"     -- runder Kreis (wie die Marken der Weltkarte)
Route.WHAT_MAX = 3          -- so viele Vorkommen merkt sich ein Punkt der Route für Tooltip und Ziel
Route.DEFAULT_KINDS = { herb = true, ore = true }

local job                   -- laufende Rechnung { map, steps, task, kinds }
local layer                 -- Rahmen der Sammel-Route über Blizzards Kartenfläche
local drawnMap

local function Store()
    local db = ns.db
    if type(db) ~= "table" then return {} end
    if type(db.routes) ~= "table" then db.routes = {} end
    return db.routes
end

local function Pins()
    local P = Core.MapPins
    if type(P) == "table" and type(P.AddProvider) == "function" then return P end
    return nil
end

local function Yards(map)
    local D = Core.Discovery
    if D and type(D.MapYards) == "function" then return D.MapYards(map) end
    return nil
end

-- gemerkte Route der Karte oder nil
function Route.Get(map)
    map = ns.Num(map)
    local r = map and Store()[map]
    if type(r) == "table" and type(r.pts) == "table" and #r.pts > 0 then return r end
    return nil
end

function Route.Running() return job end

---------------------------------------------------------------------------
-- Auswahl der Arten
---------------------------------------------------------------------------

local function KindSet()
    local store = Store()
    if type(store._kinds) ~= "table" then
        store._kinds = {}
        for k, v in pairs(Route.DEFAULT_KINDS) do store._kinds[k] = v end
    end
    return store._kinds
end

function Route.KindWanted(kind) return KindSet()[kind] == true end
function Route.SetKind(kind, on) KindSet()[kind] = on and true or nil end

-- Arten der Auswahl, die es gibt (Kisten nur auf Wunsch: Entdecker-Wissen)
function Route.Kinds()
    local out = {}
    for _, kind in ipairs(ns.Gather.KINDS) do
        if KindSet()[kind] and (kind ~= "chest" or ns.Gather.ChestsWanted()) then out[#out + 1] = kind end
    end
    return out
end

---------------------------------------------------------------------------
-- Rechnen
---------------------------------------------------------------------------

-- Eigene Fundorte der Karte zu den Arten → { { x, y, map, node } … }; der Filter „Nach Farbe“ (Teilwelle 15b) gilt
-- auch hier – eine Route nur durch orange und gelbe Vorkommen führt zu den Fertigkeitspunkten
function Route.Collect(map, kinds)
    local G = Core.Gathering
    map = ns.Num(map)
    if not (map and type(G) == "table" and type(G.Nodes) == "function") then return {} end
    local out = {}
    local ranks = not ns.Gather.AllColors() and ns.Gather.Ranks() or nil
    for _, kind in ipairs(kinds or Route.Kinds()) do
        -- „Rot – noch nicht abbaubar“ abgewählt und ohne den Beruf: keine dieser Stellen (wie auf der Karte)
        local blocked = ns.Gather.SkillBlockedKind and ns.Gather.SkillBlockedKind(kind)
        for _, node in ipairs(not blocked and G.Nodes(map, ns.Gather.FilterFor(kind)) or {}) do
            if not ns.Gather.IsHidden(node) and ns.Num(node.x) and ns.Num(node.y)
                and (ranks == nil or ns.Gather.ColorPass(node, ranks)) then
                out[#out + 1] = { x = node.x, y = node.y, map = map, node = node }
            end
        end
    end
    return out
end

--[[
    Filter der Route (Spielbefund vom 19.11.2026, Bild 37, wörtlich „der haken "nur, was ich abbauen kann" hat keine
    wirkung auf die anzeige der route“; Auftrag freigegeben am 20.11.2026): Route.Collect nahm den Filter schon beim
    Rechnen, eine gemerkte Route blieb aber nach dem Umschalten, wie sie war. Jede Route merkt sich den Stand der Filter
    beim Rechnen (Feld sig, Route.FilterSig: „Rot – noch nicht abbaubar“ und die Farben „Nach Farbe“);
    weicht er ab, rechnet Route.Refilter sie still neu – beim Umschalten für die gezeigte Karte bzw. deine Zone und beim
    Öffnen der Karte für die gezeigte. Bleiben weniger als zwei Stellen, verschwindet die Route (eine Zeile im Chat).
    Routen ohne sig (vor diesem Stand) gelten als „ohne Filter“.
]]
Route.SIG_NONE = "all"
-- Schlüssel der Farben „Nach Farbe“ (Gather.COLOR_KEY): ändert sich einer, rechnet Route.Refilter nach
Route.COLOR_KEYS = {}
for _, key in pairs(ns.Gather.COLOR_KEY) do Route.COLOR_KEYS[key] = true end
function Route.FilterSig()
    local parts = {}
    -- ohne deine Ränge: sonst rechnete jeder Fertigkeitspunkt die Route neu und nähme ihr den Fortschritt (Fund des
    -- code-reviewers vom 20.11.2026); neue Ränge gelten beim nächsten Klick auf „Route berechnen“
    if ns.Gather.SkillOnly() then parts[#parts + 1] = "skill" end
    for _, color in ipairs(ns.Gather.COLORS) do
        if not ns.Enabled(ns.Gather.COLOR_KEY[color]) then parts[#parts + 1] = "-" .. color end
    end
    return #parts > 0 and table.concat(parts, ",") or Route.SIG_NONE
end

-- Arten einer gemerkten Route als Liste (für ein Neurechnen mit derselben Auswahl)
local function KindList(r)
    local out = {}
    for _, kind in ipairs(ns.Gather.KINDS) do
        if type(r.kinds) == "table" and r.kinds[kind] then out[#out + 1] = kind end
    end
    return out
end

-- Gemerkte Route der Karte map nach geänderten Filtern still neu → true, wenn neu gerechnet bzw. entfernt
function Route.Refilter(map)
    map = ns.Num(map)
    local r = map and Route.Get(map)
    if not r or job then return false end
    if (r.sig or Route.SIG_NONE) == Route.FilterSig() then return false end
    local kinds = KindList(r)
    if #kinds == 0 then return false end
    local ok, why = Route.Start(map, kinds, true)
    if not ok and why == "few" then
        Route.Forget(map)
        ns.Print(L.ROUTE_TOO_FEW:format(ns.MapName(map)))
        return true
    end
    return ok == true
end

-- Vorkommen eines Punkts der Route (Mitglieder der Gruppe aus Core.Route.Build: Punkte aus Route.Collect) → Liste
-- { id, stored, map, kind } ohne Doppelte, höchstens Route.WHAT_MAX, oder nil. Genug für Gather.Facts (Name) und den
-- Namen der Art; gespeichert in ezMapDB.routes (Spieltest 19.11.2026: Tooltip und Ziel nennen den Rohstoff).
function Route.What(members)
    if type(members) ~= "table" then return nil end
    local out, seen = {}, {}
    for _, p in ipairs(members) do
        local node = type(p) == "table" and p.node
        if type(node) == "table" and node.id ~= nil then
            local key = tostring(node.stored) .. "|" .. tostring(node.id)
            if not seen[key] and #out < Route.WHAT_MAX then
                seen[key] = true
                out[#out + 1] = { id = node.id, stored = node.stored, map = node.map, kind = node.kind }
            end
        end
    end
    return #out > 0 and out or nil
end

-- Namen der Vorkommen eines Punkts der Route („Silberblatt, Friedensblume“) oder nil (ältere Route ohne what)
function Route.WhatText(p)
    if type(p) ~= "table" or type(p.what) ~= "table" then return nil end
    local names, seen = {}, {}
    for _, ref in ipairs(p.what) do
        local ok, facts = pcall(ns.Gather.Facts, ref)
        local name = ok and type(facts) == "table" and facts.name or nil
        if ns.IsSecret(name) or type(name) ~= "string" or name == "" then name = ns.Gather.KindLabel(ref.kind) end
        if not seen[name] then
            seen[name] = true
            names[#names + 1] = name
        end
    end
    return #names > 0 and table.concat(names, ", ") or nil
end

-- Lage des Spielers auf der Karte map oder nil
local function PlayerOn(map)
    local where, x, y = Core.PlayerPosition(map)
    if where == map and x and y then return x, y end
    return nil
end

local function Finish(current, result)
    if job ~= current then return end      -- abgebrochen
    job = nil
    local m = type(result) == "table" and type(result.maps) == "table" and result.maps[current.map] or nil
    if not (m and type(m.points) == "table" and #m.points > 0) then
        if current.quiet then
            -- still neu gerechnet und nichts übrig: die alte Route nicht stehen lassen (sonst rechnete jedes Öffnen der
            -- Karte erneut; Fund des code-reviewers vom 20.11.2026)
            if Route.Forget(current.map) then ns.Print(L.ROUTE_TOO_FEW:format(ns.MapName(current.map))) end
            return
        end
        ns.Print(L.ROUTE_NONE)
        Route.Changed()
        return
    end
    local pts = {}
    for i, g in ipairs(m.points) do pts[i] = { x = g.x, y = g.y, n = ns.Num(g.n) or 1, what = Route.What(g.members) } end
    Store()[current.map] = { pts = pts, kinds = current.kinds, len = ns.Num(m.length) or 0, units = m.units,
        t = time(), at = 1, merged = m.merged, capped = m.capped, input = m.input, sig = current.sig }
    if not current.quiet then
        ns.Print(L.ROUTE_DONE:format(ns.MapName(current.map), #pts, Route.LengthText(Store()[current.map])))
    end
    Route.Changed()
end

-- Route für die Karte map rechnen (kinds: Liste der Arten, sonst die Auswahl) → true oder false, Grund
-- ("map" keine Zonenkarte | "kinds" keine Art gewählt | "few" weniger als zwei Fundorte | "nocore"). quiet: ohne
-- Chatzeilen (Neurechnen nach geänderten Filtern, Route.Refilter)
function Route.Start(map, kinds, quiet)
    map = ns.Num(map)
    local CR = Core.Route
    if not (type(CR) == "table" and type(CR.Build) == "function") then return false, "nocore" end
    if not (map and ns.Gather.MapAllowed(map)) then return false, "map" end
    kinds = kinds or Route.Kinds()
    if #kinds == 0 then
        if not quiet then ns.Print(L.ROUTE_NO_KINDS) end
        return false, "kinds"
    end
    local points = Route.Collect(map, kinds)
    if #points < 2 then
        if not quiet then ns.Print(L.ROUTE_TOO_FEW:format(ns.MapName(map))) end
        return false, "few"
    end
    Route.Cancel()
    local chosen = {}
    for _, kind in ipairs(kinds) do chosen[kind] = true end
    local current = { map = map, steps = 0, kinds = chosen, input = #points, quiet = quiet == true, sig = Route.FilterSig() }
    job = current
    local px, py = PlayerOn(map)
    if not quiet then ns.Print(L.ROUTE_STARTED:format(ns.MapName(map), #points)) end
    local task = CR.Build(points, { map = map, start = px and { x = px, y = py } or nil, owner = "ezMap",
        onProgress = function()
            current.steps = current.steps + 1
        end,
        onDone = function(result) Finish(current, result) end })
    if job == current then current.task = task end
    Route.Changed()
    return true
end

function Route.Cancel()
    local current = job
    job = nil
    if current and current.task and type(current.task.Cancel) == "function" then current.task.Cancel() end
    return current ~= nil
end

-- „1.840 Yards“ bzw. ohne Kartengröße nur die Zahl der Punkte
function Route.LengthText(r)
    if type(r) ~= "table" then return "" end
    if r.units == "map" then return L.ROUTE_LEN_UNKNOWN end
    return L.ROUTE_LEN:format(math.floor((ns.Num(r.len) or 0) + 0.5))
end

---------------------------------------------------------------------------
-- Nächster Punkt, weiterrücken, löschen
---------------------------------------------------------------------------

local function Title(r, at) return L.ROUTE_POINT:format(at, #r.pts) end

-- Zeile eines Punkts für Tooltips: „Route: Punkt 3 von 12 – Silberblatt“ (ohne gemerkte Vorkommen nur der Titel)
function Route.StepLabel(r, at)
    local what = Route.WhatText(r.pts[at])
    if what then return L.ROUTE_POINT_WHAT:format(Title(r, at), what) end
    return Title(r, at)
end

-- Arten der Route („Kräuter, Erze“) – Ziel neben dem nächsten Punkt einer älteren Route ohne gemerkte Vorkommen
function Route.KindsText(r)
    if type(r) ~= "table" or type(r.kinds) ~= "table" then return nil end
    local out = {}
    for _, kind in ipairs(ns.Gather.KINDS) do
        if r.kinds[kind] then out[#out + 1] = ns.Gather.KindLabel(kind) end
    end
    return #out > 0 and table.concat(out, ", ") or nil
end

-- Name der Sammel-Route in Tooltips der Karten: „Sammel-Route (ezMap)“
function Route.Name() return L.ROUTE_NAME_GATHER end

-- Ist die gesetzte Markierung die der Route? (Titel „Route: Punkt n von m“ auf dieser Karte)
local function OwnWaypoint(map, r)
    local m, _, _, title = ns.Way.Get()
    if m ~= map or type(title) ~= "string" then return false end
    for i = 1, #r.pts do
        if title == Title(r, i) then return true end
    end
    return false
end

-- Markierung auf einen Punkt der Route setzen, ohne Eintrag in „Zuletzt gesetzte Markierungen“: ns.Way.Set merkt
-- jede Markierung im Verlauf (höchstens 15); wer einer Route folgt, verlöre sonst nach 15 Ernten seine eigenen Ziele.
-- Der Verlauf wird vorher abgeschrieben und danach unverändert zurückgelegt. quiet: beim Weiterrücken nach einer Ernte
-- keine Chatzeile „Zielverfolgung nach dem Kampf“ (Welle 23, A2; der Pfeil wird trotzdem nachgeholt).
-- Seit Welle 27 über Way.Set mit noHistory (statt den Verlauf abzuschreiben und zurückzulegen) und mit dem Besitzer
-- Route.PROVIDER: hält die Leveling-Route in ezQuest die Markierung, wartet die Sammel-Route (Route.Paused).
-- auto (Welle 29, NACH-27; Grundsatz des Nutzers vom 17.11.2026, wörtlich „user muss auf sowas hingewiesen werden, er
-- kann es nutzen muss es aber einschalten“): Weiterrücken ohne Klick setzt nur die Markierung (track = false, auch ein
-- wartender Pfeil-Wunsch verfällt); den Pfeil nimmt es nur mit dem Schalter wayTrack mit (track = "auto", eine Ablehnung
-- höchstens einmal je Sitzung). Ein Klick auf „Nächster Punkt“ setzt den Pfeil wie jede Markierung, wenn wayTrack an ist.
local function SetPoint(map, r, at, verbose, quiet, auto)
    local p = r.pts[at]
    local opts = { owner = Route.PROVIDER, label = L.ROUTE_OWNER, noHistory = true }
    if auto then opts.track = ns.Enabled("wayTrack") and "auto" or false end
    return ns.Way.Set(map, p.x, p.y, Title(r, at), verbose, quiet, opts)
end

-- Hält ein anderer Besitzer die Markierung (Welle 27, etwa ezQuests Leveling-Route)? → sein Name für Texte oder nil.
-- Dann rückt die Sammel-Route nicht weiter und überschreibt nichts; sie folgt weiter und meldet „pausiert“ im Menü.
function Route.Paused()
    local owner, label = ns.Way.Owner()
    if owner == nil or owner == Route.PROVIDER then return nil end
    return label or tostring(owner)
end

-- Gehört die gesetzte Markierung einer Route, der der Spieler gerade folgt? Dann lässt Arrive.lua sie bei Ankunft
-- stehen: die Route rückt nach der Ernte selbst weiter (Route.OnHarvest), ein vorzeitiges Entfernen beendete das Folgen.
function Route.OwnsWaypoint()
    local m = ns.Way.Get()
    local r = m and Route.Get(m)
    return r ~= nil and r.following == true and OwnWaypoint(m, r)
end

function Route.Next(map, verbose)
    map = ns.Num(map)
    local r = Route.Get(map)
    if not r then return false, "none" end
    local at = math.max(1, math.min(#r.pts, ns.Num(r.at) or 1))
    r.at, r.following = at, true
    local ok, err = SetPoint(map, r, at, verbose)
    Route.Changed()
    return ok, err
end

function Route.Advance(map)
    local r = Route.Get(map)
    if not r then return nil end
    r.at = (ns.Num(r.at) or 1) % #r.pts + 1
    if r.following then SetPoint(map, r, r.at, nil, true, true) end
    Route.Changed()
    return r.at
end

local function Dist(map, ax, ay, bx, by)
    local w, h = Yards(map)
    if w and h then return math.sqrt(((ax - bx) * w) ^ 2 + ((ay - by) * h) ^ 2), "yards" end
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2), "map"
end

-- Route am Ort des Spielers → Karte, Route oder nil. Zuerst die Karte, auf der er steht (eine Route lässt sich auch
-- auf einer Kleinkarte wie einer Mine oder Höhle berechnen), dann die Zone darüber.
function Route.PlayerRoute()
    local where = Core.PlayerPosition()
    if not where then return nil end
    local r = Route.Get(where)
    if r then return where, r end
    local zone = Core.Map.Parent(where, "Zone")
    r = zone and zone ~= where and Route.Get(zone) or nil
    if r then return zone, r end
    return nil
end

-- Nach einer Ernte: steht der Spieler am nächsten (oder übernächsten) Punkt der Route seiner Karte bzw. Zone, rückt
-- sie weiter → neuer Index oder nil
function Route.OnHarvest()
    local zone, r = Route.PlayerRoute()
    if not (r and r.following) then return nil end
    -- hat der Spieler inzwischen eine eigene Markierung gesetzt, folgt sie der Route nicht mehr (nichts überschreiben);
    -- gehört die Markierung einem anderen Besitzer (Leveling-Route), wartet sie nur (Welle 27)
    if not OwnWaypoint(zone, r) then
        if Route.Paused() then return nil end
        r.following = nil
        return nil
    end
    local px, py = PlayerOn(zone)
    if not px then return nil end
    local n = #r.pts
    local at = ns.Num(r.at) or 1
    for step = 0, math.min(1, n - 1) do
        local i = (at - 1 + step) % n + 1
        local p = r.pts[i]
        local d, units = Dist(zone, px, py, p.x, p.y)
        if d <= (units == "yards" and Route.REACH or Route.REACH_MAP) then
            r.at = i
            return Route.Advance(zone)
        end
    end
    return nil
end

function Route.Clear(map)
    if not Route.Forget(map) then return false end
    ns.Print(L.ROUTE_CLEARED:format(ns.MapName(map)))
    return true
end

-- Route der Karte ohne Chatzeile vergessen (Route.Clear, Route.Refilter) → true, wenn es eine gab
function Route.Forget(map)
    map = ns.Num(map)
    local r = Route.Get(map)
    if not r then return false end
    if OwnWaypoint(map, r) then ns.Way.Clear() end
    Store()[map] = nil
    Route.Changed()
    return true
end

---------------------------------------------------------------------------
-- Weltkarte: Linien
---------------------------------------------------------------------------

local function Canvas()
    local map = rawget(_G, "WorldMapFrame")
    if type(map) ~= "table" then return nil end
    if type(map.GetCanvas) == "function" then
        local ok, canvas = pcall(map.GetCanvas, map)
        if ok and type(canvas) == "table" then return canvas end
    end
    return map.ScrollContainer and map.ScrollContainer.Child or nil
end

-- Stand der letzten Zeichnung bei offener Karte (für /ezmap status): je Art { n, reason, map, extra }; reason nil =
-- gezeichnet, sonst "never" | "none" | "off" | "canvas" | "size" | "line" | "offmap"; dazu die Rahmenstufe der Linien
-- und die oberste Stufe von Blizzards Flächen
local diag = { line = { reason = "never", n = 0 }, path = { reason = "never", n = 0 } }

-- Ergebnis merken und zurückgeben; bei geschlossener Karte bleibt der Stand der letzten offenen Karte stehen
local function Note(kind, n, reason, map, extra)
    if reason ~= "closed" then
        local s = diag[kind]
        s.n, s.reason, s.map, s.extra = n, reason, map, extra
    end
    return n
end

-- Rahmenstufe eines Linien-Rahmens: über Blizzards Flächen und eine unter ezCores Punkteschicht (Core.MapPins)
local function ApplyLevel(frame, canvas)
    if not frame.SetFrameLevel then return end
    local P = Core.MapPins
    local level, area
    if type(P) == "table" and type(P.LayerLevel) == "function" then
        level, area = P.LayerLevel(canvas, Route.LEVEL, Route.AREA_GAP)
    elseif canvas.GetFrameLevel then
        local base = ns.Num(canvas:GetFrameLevel())
        level = base and base + Route.LEVEL or nil
    end
    if level then frame:SetFrameLevel(level) end
    diag.level, diag.area = level, area
end

function Route.Diagnose() return diag end

--[[
    Reihenfolge der Linie (Spielbefund vom 18.11.2026: „pfad muss sich mit meiner position aktualisieren "auflösen"“)
    → seq (Schritte ab dem nächsten Punkt, mit Nummer und Tooltip), start (dein Ort auf dieser Karte oder nil), at.
    Stehst du auf der Karte der Route, beginnt die Linie bei dir und läuft über den nächsten Punkt einmal die Runde bis
    zum Punkt davor – das Stück vom vorigen zum nächsten Punkt ist abgelaufen und entfällt (an seiner Stelle der Strich
    von deinem Ort). Sonst der ganze Ring ab dem nächsten Punkt und zurück zu ihm.
]]
function Route.LineSeq(map, r)
    local n = #r.pts
    local at = math.max(1, math.min(n, ns.Num(r.at) or 1))
    local seq = {}
    local kinds = Route.KindsText(r)
    for k = 0, n - 1 do
        local i = (at - 1 + k) % n + 1
        local p = r.pts[i]
        seq[#seq + 1] = { x = p.x, y = p.y, n = i, label = Route.StepLabel(r, i), target = Route.WhatText(p) or kinds }
    end
    local px, py = ns.RouteDraw.PlayerOn(map)
    if px then return seq, { px, py }, at end
    local p = r.pts[at]
    seq[#seq + 1] = { x = p.x, y = p.y, n = at, noMark = true }      -- Schluss des Rings: keine zweite Marke
    return seq, nil, at
end

local painter               -- Zeichner der Sammel-Route (ns.RouteDraw, eine Zeichnung für beide Linien)

-- Steht die Maus über dem sichtbaren Teil der Weltkarte (Blizzards ScrollContainer)? Die Kartenfläche reicht beim
-- Zoomen über den sichtbaren Ausschnitt hinaus; ohne diese Abfrage käme der Tooltip der Linie auch über dem Questlog.
-- Seit der Gegenprüfung vom 19.11.2026 zusätzlich: IsMouseOver ist nur eine Lageprüfung – liegt ein Menü (etwa „Route
-- durch diese Zone“), eine Rückfrage oder ein anderes Fenster über der Karte, gehört die Maus diesem Rahmen. Darum muss
-- der oberste Rahmen unter der Maus (GetMouseFoci, ältere Clients GetMouseFocus) der ScrollContainer oder ein Kind
-- davon sein.
local FOCUS_DEPTH = 30      -- so viele Eltern-Stufen höchstens bis zum ScrollContainer

local function MouseFocus()
    local foci = rawget(_G, "GetMouseFoci")
    if type(foci) == "function" then
        local list = foci()
        return true, type(list) == "table" and list[1] or nil
    end
    local focus = rawget(_G, "GetMouseFocus")
    if type(focus) == "function" then return true, focus() end
    return false
end

-- Ist frame der Rahmen box oder ein Kind (auch Enkel …) davon? Rahmen, die Fehler werfen (verbotene Rahmen), zählen nicht.
function Route.Within(frame, box)
    for _ = 1, FOCUS_DEPTH do
        if frame == nil then return false end
        if frame == box then return true end
        if type(frame) ~= "table" or type(frame.GetParent) ~= "function" then return false end
        local ok, parent = pcall(frame.GetParent, frame)
        if not ok then return false end
        frame = parent
    end
    return false
end

function Route.MouseOverMap()
    local map = rawget(_G, "WorldMapFrame")
    local box = type(map) == "table" and map.ScrollContainer or nil
    if type(box) == "table" and type(box.IsMouseOver) == "function" then
        if box:IsMouseOver() ~= true then return false end
        local known, focus = MouseFocus()
        return not known or Route.Within(focus, box)
    end
    if type(map) == "table" and type(map.IsMouseOver) == "function" then return map:IsMouseOver() == true end
    return false
end

-- Sichtbarer Ausschnitt der Karte (Blizzards ScrollContainer) in Bildpunkten der Kartenfläche layer → x0, y0, x1, y1
-- (von oben links) oder nil. Nur dort zeichnet RouteDraw die Striche der gestrichelten Linie (Gegenprüfung vom
-- 19.11.2026: vorher verbrauchten Abschnitte außerhalb das Budget).
function Route.ViewRect(layer)
    local map = rawget(_G, "WorldMapFrame")
    local box = type(map) == "table" and map.ScrollContainer or nil
    if not (type(box) == "table" and box.GetLeft and box.GetEffectiveScale and type(layer) == "table" and layer.GetLeft
        and layer.GetEffectiveScale) then
        return nil
    end
    local bs, ls = ns.Num(box:GetEffectiveScale()), ns.Num(layer:GetEffectiveScale())
    local bl, br, bt, bb = ns.Num(box:GetLeft()), ns.Num(box:GetRight()), ns.Num(box:GetTop()), ns.Num(box:GetBottom())
    local ll, lt = ns.Num(layer:GetLeft()), ns.Num(layer:GetTop())
    if not (bs and ls and bl and br and bt and bb and ll and lt) or ls <= 0 then return nil end
    return (bl * bs - ll * ls) / ls, (lt * ls - bt * bs) / ls, (br * bs - ll * ls) / ls, (lt * ls - bb * bs) / ls
end

-- Linie der Route auf der gezeigten Karte zeichnen (mit Pfeilen in Laufrichtung, Nummern an den Punkten, der nächste
-- hervorgehoben; ns.RouteDraw) → Zahl der Strecken (0: nichts zu zeichnen). Der Tooltip über der Linie bleibt dabei
-- stehen (Clear(true), danach AfterDraw – Gegenprüfung vom 19.11.2026: vorher flackerte er bei jedem Neuzeichnen).
local DrawLine
function Route.Redraw()
    local n = DrawLine()
    if painter then painter:AfterDraw() end
    return n
end

DrawLine = function()
    drawnMap = nil
    if painter then painter:Clear(true) end
    local map = rawget(_G, "WorldMapFrame")
    if not (type(map) == "table" and map.IsShown and map:IsShown() and map.GetMapID) then return Note("line", 0, "closed") end
    local shown = ns.Num(map:GetMapID())
    local r = shown and Route.Get(shown)
    if not (r and #r.pts >= 2) then return Note("line", 0, "none", shown) end
    if not ns.Enabled("routeLine") then return Note("line", 0, "off", shown) end
    local canvas = Canvas()
    if not canvas then return Note("line", 0, "canvas", shown) end
    local w, h = ns.Num(canvas:GetWidth()), ns.Num(canvas:GetHeight())
    local scale = ns.Num(canvas.GetScale and canvas:GetScale()) or 1
    if not (w and h) or w <= 0 or h <= 0 or scale <= 0 then return Note("line", 0, "size", shown) end
    if not layer then
        layer = CreateFrame("Frame", "ezMapRouteLines", canvas)
        layer:SetAllPoints(canvas)
        if layer.EnableMouse then layer:EnableMouse(false) end
    end
    if not painter then
        painter = ns.RouteDraw.Painter(layer)
        painter.hoverArea = Route.MouseOverMap
        painter.viewArea = Route.ViewRect
        painter:StartFollowing(function() ns.Try("RouteLines", Route.Redraw) end)
    end
    ApplyLevel(layer, canvas)
    layer:Show()
    painter:Begin(w, h, scale, shown)
    local seq, start, at = Route.LineSeq(shown, r)
    painter:Follow(shown, start and start[1], start and start[2])
    local drawn = painter:Path(seq, { start = start, family = Route.FAMILY, name = Route.Name(), nextN = at })
    if drawn == 0 and painter.failed then return Note("line", 0, "line", shown) end
    drawnMap = shown
    return Note("line", drawn, nil, shown)
end

-- Zoom: neu zeichnen – Dicke, Abstand der Pfeile und Größe der Nummern gelten in Bildpunkten auf dem Bildschirm (vorher
-- nur die Dicke). Ist für die gezeigte Karte noch nichts gezeichnet (etwa weil die Kartenfläche beim Öffnen noch keine
-- Größe hatte), ebenso.
function Route.Rescale()
    local map = rawget(_G, "WorldMapFrame")
    local shown = type(map) == "table" and map.GetMapID and ns.Num(map:GetMapID()) or nil
    if drawnMap == nil and not Route.Get(shown) then return 0 end
    return Route.Redraw()
end

-- Blizzards OnCanvasScaleChanged meldet sich während der Zoom-Bewegung fast jedes Bild; neu gezeichnet werden beide
-- Linien (mit Marken und Pfeilen) gebündelt höchstens alle Route.ZOOM_WAIT Sekunden, die letzte Meldung immer mit
-- (Fund der Gegenprüfung vom 18.11.2026). Dazwischen bleiben die Striche an ihrem Ort (sie hängen an der Kartenfläche).
-- → true, wenn jetzt vorgemerkt
Route.ZOOM_WAIT = 0.1
local zoomPending = false
function Route.Zoomed()
    if zoomPending then return false end
    zoomPending = true
    C_Timer.After(Route.ZOOM_WAIT, function()
        zoomPending = false
        ns.Try("RouteLines", Route.Rescale)
        ns.Try("PathLines", Route.RedrawPaths)
    end)
    return true
end

function Route.Lines()
    return painter and painter:Shown() or {}
end

-- Zeichner der Sammel-Route (Prüfungen: Marken, Pfeile)
function Route.Painter() return painter end

---------------------------------------------------------------------------
-- Weltkarte: Wege anderer Module (Welle 27, Schnittstelle ShowPath/ClearPath für ezQuests Leveling-Route; Leitlinie 2:
-- eine Zeichnung in ezMap statt einer zweiten in ezQuest). Je Besitzer ein Weg aus Punkten beliebiger Karten; gezeichnet
-- wird auf der gezeigten Karte (Core.Map.PosOn), Abschnitte mit einem Ende außerhalb der Karte fallen weg. Eigene
-- Linien auf einem eigenen Rahmen als Kind von Blizzards Kartenfläche (wie die Sammel-Route), nur hooksecurefunc.
-- Ein Punkt mit icon (Datei bzw. Datei-ID) oder atlas steht zusätzlich als Symbol auf der Karte, label ist sein Tooltip
-- (Fund der Gegenprüfung vom 17.11.2026 zu Antwort 5 des Nutzers: Sammel-Abstecher „in Liste und Karte deutlich
-- gekennzeichnet“). Die Symbole setzt ezCores Punkteschicht (Core.MapPins, Anbieter Route.PATHS_PROVIDER) – eine
-- Zeichnung für alle Punkte, Größe und Umrechnung wie dort.
---------------------------------------------------------------------------

-- Seit dem Spielbefund vom 18.11.2026 (ns.RouteDraw): Pfeile in Laufrichtung, und mit opts.fromPlayer beginnt der Weg an
-- deinem Ort und folgt dir bei offener Karte. Seit dem Spieltest vom 19.11.2026: Farbfamilie mit Verlauf, ab Werk nur am
-- nächsten Schritt eine Nummer mit Ziel (alle mit dem Schalter routeNumbers), Tooltip label.

local paths = {}            -- [Besitzer] = { pts = { { map, x, y, icon, atlas, label } … }, color, fromPlayer, nextN, marks }
local pathLayer, pathPainter

-- Wege auf der gezeigten Karte zeichnen → Zahl der Strecken
-- (Tooltip über der Linie wie bei Route.Redraw: Clear(true), danach AfterDraw)
local DrawPaths
function Route.RedrawPaths()
    local n = DrawPaths()
    if pathPainter then pathPainter:AfterDraw() end
    return n
end

DrawPaths = function()
    if pathPainter then pathPainter:Clear(true) end
    local map = rawget(_G, "WorldMapFrame")
    if not (type(map) == "table" and map.IsShown and map:IsShown() and map.GetMapID) then return Note("path", 0, "closed") end
    local shown = ns.Num(map:GetMapID())
    if not shown or next(paths) == nil then return Note("path", 0, "none", shown) end
    local canvas = Canvas()
    if not canvas then return Note("path", 0, "canvas", shown) end
    local w, h = ns.Num(canvas:GetWidth()), ns.Num(canvas:GetHeight())
    local scale = ns.Num(canvas.GetScale and canvas:GetScale()) or 1
    if not (w and h) or w <= 0 or h <= 0 or scale <= 0 then return Note("path", 0, "size", shown) end
    if not pathLayer then
        pathLayer = CreateFrame("Frame", "ezMapPathLines", canvas)
        pathLayer:SetAllPoints(canvas)
        if pathLayer.EnableMouse then pathLayer:EnableMouse(false) end
    end
    if not pathPainter then
        pathPainter = ns.RouteDraw.Painter(pathLayer)
        pathPainter.hoverArea = Route.MouseOverMap
        pathPainter.viewArea = Route.ViewRect
        pathPainter:StartFollowing(function() ns.Try("PathLines", Route.RedrawPaths) end)
    end
    ApplyLevel(pathLayer, canvas)
    pathLayer:Show()
    pathPainter:Begin(w, h, scale, shown)
    local drawn, total = 0, 0
    local follow, fx, fy = false, nil, nil
    local keys = {}
    for owner in pairs(paths) do keys[#keys + 1] = owner end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, owner in ipairs(keys) do
        local path = paths[owner]
        local seq = {}
        for i, p in ipairs(path.pts) do
            total = total + 1
            local x, y = Core.Map.PosOn(shown, p.map, p.x, p.y)
            -- Nummer neben dem Punkt (RouteDraw.MARK_OFFSET), Ziel neben der Marke des nächsten
            seq[i] = { x = x, y = y, n = i, label = p.label, target = p.target }
            -- neben der gezeigten Karte (etwa eine Abgabe in der Nachbarzone): Lage außerhalb der Fläche, die Linie
            -- läuft bis zum Kartenrand weiter statt abzubrechen (Spielbefund vom 19.11.2026, RouteDraw: Painter:Path)
            if not x then
                local ox, oy = Core.Map.PosOn(shown, p.map, p.x, p.y, true)
                if ox and oy then seq[i] = { x = ox, y = oy, n = i, label = p.label, target = p.target, off = true } end
            end
        end
        local start
        if path.fromPlayer then
            follow = true
            fx, fy = ns.RouteDraw.PlayerOn(shown)
            start = fx and { fx, fy } or nil
        end
        drawn = drawn + pathPainter:Path(seq, { start = start, family = path.family, color = path.color,
            name = path.name, nextN = path.nextN, marks = path.marks })
    end
    pathPainter:Follow(follow and shown or nil, fx, fy)
    if drawn > 0 then return Note("path", drawn, nil, shown) end
    return Note("path", 0, pathPainter.failed and "line" or "offmap", shown, total)
end

-- Symbole der Wege auf der Karte neu setzen lassen (ezCores Punkteschicht)
local function PathPinsChanged()
    local P = Pins()
    if P and type(P.Refresh) == "function" then ns.Try("PathPins", P.Refresh) end
end

local function Text(v)
    if ns.IsSecret(v) or type(v) ~= "string" or v == "" then return nil end
    return v
end

-- Weg eines Besitzers zeigen (ersetzt seinen vorigen) → Zahl der übernommenen Punkte (unter zwei: kein Weg; mit
-- opts.fromPlayer reicht einer). opts (freiwillig): family = Farbfamilie aus ns.RouteDraw.FAMILY (Standard
-- Route.PATH_FAMILY, Gold bis Orange; Spieltest 19.11.2026) oder color = { r, g, b, a } (eine Farbe, nur zum Ende
-- blasser); name und addon: Name des Wegs für Tooltips („Leveling-Route (ezQuest)“); fromPlayer = true: der Weg beginnt
-- an deinem Ort und folgt dir (Spielbefund vom 18.11.2026); next = Nummer des nächsten Punkts (hervorgehoben,
-- Standard 1); marks = false: ohne Nummern an den Punkten. Ein Punkt mit target (kurzer Text) zeigt ihn als Ziel neben
-- der Marke, wenn er der nächste ist.
function Route.ShowPath(owner, points, opts)
    if owner == nil then return 0 end
    local pts = {}
    for _, p in ipairs(type(points) == "table" and points or {}) do
        if type(p) == "table" then
            local m, x, y = ns.Num(p.map), ns.Num(p.x), ns.Num(p.y)
            if m and x and y then
                local icon = Text(p.icon) or ns.Num(p.icon)
                pts[#pts + 1] = { map = m, x = x, y = y, icon = icon, atlas = Text(p.atlas), label = Text(p.label),
                    target = Text(p.target) }
            end
        end
    end
    opts = type(opts) == "table" and opts or {}
    local color = type(opts.color) == "table" and opts.color or nil
    local family = type(opts.family) == "string" and ns.RouteDraw.FAMILY[opts.family] and opts.family or nil
    if not (family or color) then family = Route.PATH_FAMILY end
    local name = Text(opts.name)        -- ohne Namen: Tooltip wie bisher nur mit der Zeile des Schritts
    local addon = Text(opts.addon)
    if name then name = name:gsub("^%l", string.upper) end      -- „levelling route“ als Titel: „Levelling route“
    if name and addon then name = L.ROUTE_NAME:format(name, addon) end
    local fromPlayer = opts.fromPlayer == true
    local need = fromPlayer and 1 or 2
    if #pts < need then
        paths[owner] = nil
    else
        paths[owner] = { pts = pts, color = color, family = family, name = name, fromPlayer = fromPlayer,
            nextN = ns.Num(opts.next) or 1, marks = opts.marks ~= false }
    end
    ns.Try("PathLines", Route.RedrawPaths)
    PathPinsChanged()
    return #pts >= need and #pts or 0
end

function Route.ClearPath(owner)
    if owner ~= nil then paths[owner] = nil end
    ns.Try("PathLines", Route.RedrawPaths)
    PathPinsChanged()
    return true
end

-- Punkte mit eigenem Symbol aller Wege (Anbieter für ezCores Punkteschicht; die Karte rechnet sie um)
function Route.PathPins()
    local out = {}
    local keys = {}
    for owner in pairs(paths) do keys[#keys + 1] = owner end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, owner in ipairs(keys) do
        for _, p in ipairs(paths[owner].pts) do
            if p.icon or p.atlas then
                out[#out + 1] = { map = p.map, x = p.x, y = p.y, texture = p.icon, atlas = p.atlas,
                    size = Route.PATH_PIN_SIZE, label = p.label, path = owner }
            end
        end
    end
    return out
end

function Route.PathPinTooltip(tip, point)
    if type(point) ~= "table" or not point.label then return end
    Core.TipTitle(tip, point.label)
end

function Route.PathLines()
    return pathPainter and pathPainter:Shown() or {}
end

-- Zeichner der Wege anderer Module (Prüfungen: Marken, Pfeile)
function Route.PathPainter() return pathPainter end

---------------------------------------------------------------------------
-- Minikarte: nur der nächste Punkt der Route (über ezCores Punkteschicht; Spieltest 19.11.2026)
---------------------------------------------------------------------------

function Route.MiniWanted()
    return ns.Enabled("routeMini") and (ns.Gather.MiniActive()) == true
end

-- Punkte der Route auf der Karte map (Speicherkarte des Spielers) für die Minikarte: nur der nächste Punkt, als runder,
-- halb durchsichtiger Kreis in der Anfangsfarbe der Route (Spieltest 19.11.2026, wörtlich „siehe minimap - was soll
-- das?!“ – vorher die ganze Runde als Punktreihe alle 10 Yards, die wie eine Linie quer über die Minikarte bis zum Rand
-- lief, und der nächste Punkt als gelbes Quadrat). ezCores Punkteschicht setzt ihn nur, solange er im Sichtbereich liegt
-- (nie an den Rand geklemmt); in der Nähe blendet gatherHideNear ihn wie die Fundorte aus. Seit Welle 23 (A7) kommt die
-- Route vor den Sammel-Fundorten dran (order 30): so fällt er auch bei voller Obergrenze (MapPins.MAX) nicht weg.
function Route.MiniPoints(map)
    map = ns.Num(map)
    local r = map and Route.Get(map)
    if not r then return {} end
    local at = math.max(1, math.min(#r.pts, ns.Num(r.at) or 1))
    local p = r.pts[at]
    if not p then return {} end
    local c = ns.RouteDraw.Family(Route.FAMILY).from
    return { { x = p.x, y = p.y, map = map, size = Route.NEXT_SIZE, texture = Route.TEXTURE, crop = false,
        r = c[1], g = c[2], b = c[3], a = Route.MINI_ALPHA, route = true, next = at, total = #r.pts,
        label = Route.StepLabel(r, at) } }
end

-- Tooltip des nächsten Punkts auf der Minikarte: Name der Route, Punkt mit Vorkommen, Hinweis, Entfernung
function Route.MiniTooltip(tip, point, mapID)
    if type(point) ~= "table" or not point.route then return end
    if point.next then
        ns.RouteDraw.FillTip(tip, Route.Name(), { point.label or L.ROUTE_POINT:format(point.next, point.total) }, nil,
            ns.Num(mapID), point.x, point.y)
        Core.TipLine(tip, L.ROUTE_NEXT_TIP_LINE, "hint", true)
    else
        Core.TipTitle(tip, L.ROUTE_MENU)
    end
end

---------------------------------------------------------------------------
-- Menü „Route durch diese Zone“
---------------------------------------------------------------------------

local function Tip(entry, title, text) return ns.MapButton.Tip(entry, title, text) end

function Route.Label(map)
    local r = Route.Get(map)
    if job and job.map == ns.Num(map) then return L.ROUTE_MENU_RUNNING end
    if r then return L.ROUTE_MENU_HAS:format(#r.pts) end
    return L.ROUTE_MENU
end

-- Untermenü für die Karte mapID → der Eintrag oder nil (Welt- oder Kontinentkarte: nur eine erklärende Zeile)
function Route.AddMenu(root, mapID)
    local Menu = Core.Menu
    mapID = ns.Num(mapID)
    if not mapID then return nil end
    -- eigenes Symbol, auch dort, wo eine Hülle das von „Sammeln“ vorgibt (Fund des code-reviewers vom 17.11.2026)
    if not ns.Gather.MapAllowed(mapID) then
        ns.Icons.Apply(Tip(Menu.Title(root, L.ROUTE_NOZONE), L.ROUTE_NOZONE, L.ROUTE_NOZONE_TIP), "route")
        return nil
    end
    local label = Route.Label(mapID)
    local sub = ns.Icons.Apply(Tip(Menu.Button(root, label), label, L.ROUTE_MENU_TIP), "route")
    -- jeder Eintrag mit Symbol, auch im Untermenü (Fund der Nachprüfung vom 17.11.2026): Überschrift und Knöpfe mit dem
    -- Symbol der Route, die Arten mit dem ihres Blatts, Hilfszeilen mit dem „i“, „Alle auswählen/abwählen“ mit ezCores
    -- Häkchen und Kreuz
    local Apply = ns.Icons.Apply
    Apply(Tip(Menu.Title(sub, L.ROUTE_KINDS), L.ROUTE_KINDS, L.ROUTE_KINDS_TIP), "route")
    local kinds = {}
    for _, kind in ipairs(ns.Gather.KINDS) do
        if kind ~= "chest" or ns.Gather.ChestsWanted() then kinds[#kinds + 1] = kind end
    end
    -- Design-System 2.11: ein Haken „Alle“ über den Arten der Route (ab drei; gemerkt wie jeder Haken)
    if #kinds >= 3 then
        Menu.AllToggle(sub, kinds, Route.KindWanted, Route.SetKind)
    end
    for _, kind in ipairs(kinds) do
        do
            local k = kind
            local text = ns.Gather.KindLabel(kind)
            Apply(Tip(Menu.Toggle(sub, text, function() return Route.KindWanted(k) end, function(on) Route.SetKind(k, on) end),
                text, L.ROUTE_KIND_TIP), ns.Tree.Icon(ns.Gather.KEY[k]))
        end
    end
    Menu.Divider(sub)
    if job and job.map == mapID then
        local text = L.ROUTE_RUNNING:format(job.steps or 0)
        Apply(Tip(Menu.Title(sub, text), text, L.ROUTE_RUNNING_TIP), "info")
        Apply(Tip(Menu.Button(sub, L.ROUTE_CANCEL, function()
            if Route.Cancel() then ns.Print(L.ROUTE_CANCELLED) end
            Route.Changed()
        end), L.ROUTE_CANCEL, L.ROUTE_CANCEL_TIP), "menuClear")
    else
        local text = Route.Get(mapID) and L.ROUTE_REBUILD or L.ROUTE_BUILD
        Apply(Tip(Menu.Button(sub, text, function() Route.Start(mapID) end), text, L.ROUTE_BUILD_TIP), "route")
    end
    local r = Route.Get(mapID)
    if r then
        local info = L.ROUTE_INFO:format(#r.pts, Route.LengthText(r), Core.Ago(r.t))
        Apply(Tip(Menu.Title(sub, info), info, L.ROUTE_INFO_TIP), "info")
        local paused = r.following and Route.Paused()
        if paused then
            local text = L.ROUTE_PAUSED:format(paused)
            Apply(Tip(Menu.Title(sub, text), text, L.ROUTE_PAUSED_TIP), "info")
        end
        local at = math.max(1, math.min(#r.pts, ns.Num(r.at) or 1))
        local nextText = L.ROUTE_NEXT:format(at, #r.pts)
        Apply(Tip(Menu.Button(sub, nextText, function() Route.Next(mapID, true) end), nextText, L.ROUTE_NEXT_TIP), "route")
        Apply(Tip(Menu.Button(sub, L.ROUTE_CLEAR, function() Route.Clear(mapID) end), L.ROUTE_CLEAR, L.ROUTE_CLEAR_TIP),
            "menuClear")
    end
    -- Nummern an allen Schritten (Spieltest 19.11.2026; derselbe Haken auf der Einstellungsseite unter „Karte“)
    Menu.Divider(sub)
    Apply(Tip(Menu.Toggle(sub, L.OPT_routeNumbers, function() return ns.Enabled("routeNumbers") end,
        function(on) ns.SetSetting("routeNumbers", on and true or false) end), L.OPT_routeNumbers, L.OPT_routeNumbers_TIP),
        "route")
    return sub
end

---------------------------------------------------------------------------
-- Neuaufbau, Anmeldung, Status
---------------------------------------------------------------------------

-- Nach jeder Änderung: Linie neu, Minikarten-Punkte neu
function Route.Changed()
    ns.Try("RouteLines", Route.Redraw)
    local P = Pins()
    if P and type(P.MinimapRefresh) == "function" then ns.Try("RouteMini", P.MinimapRefresh) end
end

local hooked = false
local function Hook()
    local map = rawget(_G, "WorldMapFrame")
    if hooked or type(map) ~= "table" then return end
    hooked = true
    local function Later()
        -- gemerkte Route der gezeigten Karte mit geänderten Filtern still neu (Route.Refilter)
        ns.Try("RouteRefilter", Route.Refilter, ns.Num(map.GetMapID and map:GetMapID()))
        ns.Try("RouteLines", Route.Redraw)
        ns.Try("PathLines", Route.RedrawPaths)
    end
    local function Zoomed() Route.Zoomed() end
    if map.HookScript then map:HookScript("OnShow", Later) end
    if type(map.OnMapChanged) == "function" then hooksecurefunc(map, "OnMapChanged", Later) end
    if type(map.OnCanvasScaleChanged) == "function" then hooksecurefunc(map, "OnCanvasScaleChanged", Zoomed) end
    Later()
end

function Route.Init()
    local P = Pins()
    if P then
        P.AddProvider(Route.PROVIDER, {
            owner = "ezMap",
            order = Route.ORDER,                   -- vor allen Fundorten (Welle 23, A7; Route.MiniPoints)
            punkte = function() return {} end,     -- auf der Weltkarte zeichnen die Linien (oben)
            minikarte = Route.MiniPoints,
            -- wie die Fundorte: in der Nähe auf der Minikarte auslassen (gatherHideNear, Wunsch vom 18.11.2026) – seit dem
            -- Spieltest vom 19.11.2026 steht dort nur noch der nächste Punkt der Route (Route.MiniPoints)
            hideNear = function() return ns.Gather.HideNear() end,
            sichtbar = function(_, surface) return surface == "minimap" and Route.MiniWanted() end,
            tooltip = Route.MiniTooltip,
        })
        -- Symbole an Wegen anderer Module (ShowPath mit icon bzw. atlas), nur auf der Weltkarte
        P.AddProvider(Route.PATHS_PROVIDER, {
            owner = "ezMap",
            order = Route.PATH_ORDER,
            punkte = Route.PathPins,
            tooltip = Route.PathPinTooltip,
        })
    end
    ns.WhenAddOnLoaded("Blizzard_WorldMap", function() ns.Try("RouteHook", Hook) end)
    Core.Listen("GATHERING_HARVEST", function() ns.Try("RouteHarvest", Route.OnHarvest) end, "ezMap.Route")
    return true
end

-- Haken unter „Sammeln“ im Baum: Linie auf der Weltkarte, der nächste Punkt auf der Minikarte. „Nummern an allen
-- Schritten“ (routeNumbers, Spieltest 19.11.2026) ist kein Blatt: er zeigt nichts Neues, sondern ändert, wie beide
-- Linien aussehen (wie „Symbole rund“) – Haken auf der Einstellungsseite unter „Karte“ und im Untermenü der Route; als
-- Blatt stünde „Sammeln“ ab Werk auf „Teilweise“, und „Alle auswählen“ schaltete ihn mit ein.
ns.Tree.Add("gather", { id = "route", children = { { key = "routeLine" }, { key = "routeMini" } } })

ns.OnReady(function() ns.Try("Route", Route.Init) end)

ns.OnSettingChanged(function(key)
    if key == "routeLine" or key == "routeMini" then Route.Changed() end
    -- „Rot – noch nicht abbaubar“ und die Farben „Nach Farbe“ gelten auch für die gemerkte Route (Route.Refilter): die
    -- gezeigte Karte und deine Zone
    if key == "gatherColorRed" or Route.COLOR_KEYS[key] then
        local wm = rawget(_G, "WorldMapFrame")
        local shown = type(wm) == "table" and wm.IsShown and wm:IsShown() and wm.GetMapID and ns.Num(wm:GetMapID()) or nil
        if shown then ns.Try("RouteRefilter", Route.Refilter, shown) end
        local zone = Route.PlayerRoute()
        if zone and zone ~= shown then ns.Try("RouteRefilter", Route.Refilter, zone) end
    end
    -- Nummern gelten für beide Linien: die Sammel-Route und die Wege anderer Module (ezQuests Leveling-Route)
    if key == "routeNumbers" then
        ns.Try("RouteLines", Route.Redraw)
        ns.Try("PathLines", Route.RedrawPaths)
    end
end)

-- /ezmap status: Route der eigenen Zone
ns.AddStatusLine(function()
    local zone, r = Route.PlayerRoute()
    if not r then return nil end
    return L.STATUS_ROUTE:format(ns.MapName(zone), #r.pts, Route.LengthText(r), ns.Num(r.at) or 1)
end)

-- /ezmap status: Linien auf der Weltkarte (Spielbefund vom 18.11.2026) – je Art die Zahl der gezeichneten Strecken
-- bei der letzten offenen Karte oder der Grund, warum nichts gezeichnet wurde, dazu die Rahmenstufen
local REASON = { canvas = "LINES_CANVAS", size = "LINES_SIZE", line = "LINES_LINE", off = "LINES_OFF" }

local function DiagPart(s, kind)
    if s.reason == "never" then return L.LINES_NEVER end
    local name = s.map and ns.MapName(s.map) or "?"
    if s.reason == nil then return L.LINES_DRAWN:format(s.n or 0, name) end
    if s.reason == "none" then return kind == "line" and L.LINES_NO_ROUTE:format(name) or L.LINES_NO_PATH end
    if s.reason == "offmap" then return L.LINES_OFFMAP:format(s.extra or 0, name) end
    return L[REASON[s.reason] or "LINES_LINE"]
end

function Route.StatusText()
    return L.STATUS_LINES:format(DiagPart(diag.line, "line"), DiagPart(diag.path, "path"),
        diag.level and tostring(diag.level) or L.LINES_UNKNOWN, diag.area and tostring(diag.area) or L.LINES_UNKNOWN)
end

ns.AddStatusLine(function() return Route.StatusText() end)
