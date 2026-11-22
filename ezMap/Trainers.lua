local _, ns = ...
local L = ns.L
local Core = ezCore

-- Lehrer: ezCore merkt sich jeden Lehrer, dessen Fenster du öffnest (Core.Npcs: Name, Titel, Ort, Art – eine
-- Quelle für alle Module, seit Welle 2; vorher ezMapDB.trainers, von ezCore einmal übernommen). ezMap bietet sie
-- im Kartenmenü und im Menü „Aufspüren“ als Ziel für Blizzards Markierung an. Keine mitgelieferten Daten und keine
-- eigenen Kartensymbole: Questie zeigt alle Lehrer auf der Karte (Questie-Menü → Stadtbewohner).
-- Seit dem 22.11.2026 (Entscheidung des Nutzers: „Ja, Questie zuerst“, dazu „und noch waffenmeister“) kommen die
-- Lehrer deines Kontinents laut Questie dazu (Core.Npcs.List mit questie = Trainers.QuestieMaps(); nur zur Laufzeit,
-- nichts gespeichert; ein besuchter Lehrer geht vor). Waffenmeister bleiben Art „other“ mit weapon = true.
-- Der Schalter „trainers“ entscheidet nur noch, ob ezMap sie anbietet – gemerkt wird in ezCore immer.
local Trainers = {}
ns.Trainers = Trainers

local Npcs = Core.Npcs

-- NPC-ID aus der GUID („Creature-0-1465-0-2105-448-000043F59F“ → 448) über ezCore.
local NpcID = Core.NpcID
Trainers.NpcID = NpcID

-- Tierausbilder (Jäger lernen dort die Fähigkeiten ihres Tiers): ezCore vergibt die Art „pet“ selbst
-- (Npcs.TrainerKind, erkannt am Titel in der Sprache des Clients über Npcs.IsPetTrainerTitle). Beides hier ist nur
-- noch Weiterleitung (MAP-18); die eigene Erkennung samt Text TRAINER_PET_TITLE ist entfallen.
function Trainers.IsPetTitle(title)
    return Npcs.IsPetTrainerTitle(title) == true
end

-- Art eines Eintrags aus ezCore: „class“ | „profession“ | „pet“ | „other“ (Feld trainer dort, kind hier).
-- Lehrer, die ezCore gemerkt hat, bevor es „pet“ kannte, stehen dort noch als „other“: ezMap ordnet sie beim Laden
-- der Liste neu ein – mit derselben Regel wie Npcs.TrainerKind für Tierausbilder (Titel). TrainerKind selbst fragt
-- zuerst das gerade offene Lehrerfenster (IsTradeskillTrainer) und taugt deshalb nur für den NPC vor dir.
-- ezCores Speicher bleibt unberührt (er gehört ezCore).
function Trainers.KindOf(t)
    if type(t) ~= "table" then return nil end
    if t.trainer == "other" and Trainers.IsPetTitle(t.title) then return "pet" end
    return t.trainer
end

-- Fassade über Core.Npcs: Kopie mit kind = Art des Lehrers (wie vor der Umstellung).
local function Facade(t)
    t.kind = Trainers.KindOf(t)
    return t
end

-- Merken übernimmt ezCore bei TRAINER_SHOW selbst; der Aufruf bleibt als Weiterleitung (Leitlinie 8).
function Trainers.Learn()
    return Npcs.Learn("trainer")
end

-- Karten, für die Questie Lehrer und Händler liefern soll: deine Zone zuerst, dann die Zonen deines Kontinents
-- (Core.Map.Zones). map = statt deines Standorts diese Karte (ezMap-Knopf der Weltkarte: die gezeigte Karte; eine
-- Kontinentkarte bringt ihre Zonen, die Weltkarte fällt auf deinen Standort zurück).
-- → Liste der Karten oder nil (Position bzw. Karte unbekannt)
function Trainers.QuestieMaps(map)
    local mapID = ns.Num(map)
    -- Weltkarte (und darüber): kein Kontinent gezeigt – wie bisher dein Standort
    local info = mapID and Core.Map.Info(mapID)
    local mapType = type(info) == "table" and ns.Num(info.mapType) or nil
    if mapID and mapType and mapType < 2 then mapID = nil end
    mapID = mapID or ns.PlayerPosition()
    if not mapID then return nil end
    local maps = {}
    info = Core.Map.Info(mapID)
    mapType = type(info) == "table" and ns.Num(info.mapType) or nil
    local zone = (mapType == nil or mapType >= 3) and Core.Map.Parent(mapID, "Zone") or nil
    if zone then maps[1] = zone end
    local continent = Core.Map.Parent(mapID, "Continent")
    for _, z in ipairs(continent and Core.Map.Zones(continent) or {}) do maps[#maps + 1] = z.map end
    return maps
end

-- Lehrer mit Koordinaten, die zu diesem Charakter passen (Kopien), sortiert nach Zone und Name: besuchte (alle
-- Kontinente) und laut Questie (dein Kontinent). kind = "class" (eigene Klasse) | "profession" | "pet"
-- (Tierausbilder) | "other" | "weapon" (Waffenmeister, Art „other“) | nil (alle). opts.visited = nur besuchte (Liste
-- im Chat, Blätter des Baums – sonst wechselten sie mit Kontinent und Questie); opts.map = laut Questie für den
-- Kontinent dieser Karte statt deines Standorts (ezMap-Knopf der Weltkarte).
-- → Liste, wartet (true, solange Questie noch liest)
function Trainers.List(kind, opts)
    local list = {}
    local maps = not (opts and opts.visited) and Trainers.QuestieMaps(opts and opts.map) or nil
    local all, pending = Npcs.List({ kind = "trainer", located = true, fits = true, questie = maps })
    for _, t in ipairs(all) do
        Facade(t)
        if kind == nil or t.kind == kind or (kind == "weapon" and t.weapon) then list[#list + 1] = t end
    end
    return list, pending == true
end

-- Quelle eines Eintrags für die graue Zeile im Tooltip: „laut Questie“ bzw. „von dir besucht“ (ezCore)
function Trainers.Source(t)
    return Npcs.SourceLabel(t)
end

local function WorldPos(mapID, x, y) return ns.WorldPos(mapID, x, y) end

-- Nächster Lehrer auf demselben Kontinent (Kopie mit .distance in Metern) oder nil. list = schon gelesene Liste
-- (Trainers.List(); das Menü liest sie sonst je „Nächster …“ neu – Fund des code-reviewers vom 22.11.2026).
function Trainers.Nearest(kind, list)
    -- ohne Kontinent (Instanz) nicht erst lesen, wie vor dem Umbau (Fund des code-reviewers vom 22.11.2026)
    if not Trainers.PositionKnown() then return nil end
    if not list then return Trainers.NearestOf((Trainers.List(kind))) end
    local wanted = {}
    for _, t in ipairs(list) do
        if kind == nil or t.kind == kind or (kind == "weapon" and t.weapon) then wanted[#wanted + 1] = t end
    end
    return Trainers.NearestOf(wanted)
end

-- Nächster Eintrag einer Liste auf deinem Kontinent (der Eintrag bekommt .distance in Metern) oder nil – für die
-- Lehrer und die weiteren Stadtbewohner im Menü „Aufspüren“ (Gastwirt …, MapButton.FillRole; 22.11.2026)
function Trainers.NearestOf(list)
    local mapID, x, y = ns.PlayerPosition()
    if not mapID or type(list) ~= "table" then return nil end
    local continent, px, py = WorldPos(mapID, x, y)
    if not continent then return nil end
    local best
    for _, t in ipairs(list) do
        local c, tx, ty = WorldPos(t.map, t.x, t.y)
        if c and c == continent then
            local d = math.sqrt((tx - px) ^ 2 + (ty - py) ^ 2)
            if not best or d < best.distance then
                best = t
                best.distance = d
            end
        end
    end
    return best
end

-- „Name (Titel)“ aus ezCore.
function Trainers.Label(t)
    return Npcs.Label(t) or "?"
end

function Trainers.Go(t)
    return ns.Way.Set(t.map, t.x, t.y, Trainers.Label(t), true)
end

-- Kennt das Spiel die eigene Position samt Kontinent? Ohne sie (Instanz, gesperrter Wert) findet Trainers.Nearest
-- keinen Lehrer – das heißt dann nicht, dass keiner gemerkt ist.
function Trainers.PositionKnown()
    local mapID, x, y = ns.PlayerPosition()
    return mapID ~= nil and WorldPos(mapID, x, y) ~= nil
end

-- Kartenmarkierung auf den nächsten gemerkten Lehrer setzen, ohne Chatzeile (Welle 23, A3: eine Stelle für ezPanels
-- XP-Baustein und ezMerchants „Was kommt wann“, die ihre eigenen Texte behalten; vorher baute jedes Modul das selbst).
-- Auch im Kampf still (Way.Set mit quiet): die Zielverfolgung holt ezMap danach nach. Nur wenn Blizzard die
-- Zielverfolgung außerhalb des Kampfes ablehnt, nennt Way.Track den Weg von Hand.
-- kind wie Trainers.Nearest. → true, Name („Name (Titel)“), Ort (Kartenname), Eintrag | false, Grund: "none" (keiner
-- gemerkt bzw. keiner auf diesem Kontinent), "nopos" (eigene Position unbekannt), "failed" (Blizzard lehnt die
-- Markierung ab; dritter Wert: Text dazu)
function Trainers.GoNearest(kind)
    local t = Trainers.Nearest(kind)
    if not t then return false, Trainers.PositionKnown() and "none" or "nopos" end
    local name = Trainers.Label(t)
    local ok, err = ns.Way.Set(t.map, t.x, t.y, name, nil, true)
    if not ok then return false, "failed", err end
    return true, name, ns.MapName(t.map), t
end

-- Anzahl aller gemerkten Lehrer (auch die anderer Klassen und Fraktionen).
function Trainers.Count()
    return Npcs.Count("trainer")
end

-- Nur besuchte (der Chat ist keine Liste für alle Lehrer des Kontinents laut Questie)
function Trainers.PrintList()
    local list = Trainers.List(nil, { visited = true })
    if #list == 0 then return ns.Print(L.TRAINER_LIST_EMPTY) end
    ns.Print(L.TRAINER_LIST:format(#list))
    for _, t in ipairs(list) do
        ns.Print(("  %s – %s %s"):format(Trainers.Label(t), ns.MapName(t.map), ns.CoordText(t.x, t.y)))
    end
end

-- Nach dem Anmelden einmal anstoßen, damit Questie seinen Index schon gelesen hat, wenn du das Menü öffnest (in
-- Scheiben, außerhalb des Kampfes; ohne QuestieDB antwortet ezCore sofort mit „missing“).
Trainers.WARM_DELAY = 15
ns.OnReady(function()
    local timer = rawget(_G, "C_Timer")
    if type(timer) ~= "table" or type(timer.After) ~= "function" then return end
    timer.After(Trainers.WARM_DELAY, function()
        if ns.Tree and ns.Tree.Any and ns.Tree.Any("trainers") then ns.Try("TrainersWarm", Trainers.List) end
    end)
end)

-- Vergisst alle Lehrer in ezCores NPC-Wissen (ein NPC, der auch Händler ist, bleibt als Händler).
function Trainers.Forget()
    Npcs.Forget("trainer")
    ns.Print(L.TRAINER_FORGET_DONE)
end

ns.AddStatusLine(function()
    local other = ns.TrainersElsewhere()
    if other then return L.STATUS_TRAINERS_OTHER:format(Trainers.Count(), other) end
    return L.STATUS_TRAINERS:format(Trainers.Count())
end)
