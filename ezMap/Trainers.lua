local _, ns = ...
local L = ns.L
local Core = ezCore

-- Lehrer: ezCore merkt sich jeden Lehrer, dessen Fenster du öffnest (Core.Npcs: Name, Titel, Ort, Art – eine
-- Quelle für alle Module, seit Welle 2; vorher ezMapDB.trainers, von ezCore einmal übernommen). ezMap bietet sie
-- im Kartenmenü und im Menü „Aufspüren“ als Ziel für Blizzards Markierung an. Keine mitgelieferten Daten und keine
-- eigenen Kartensymbole: Questie zeigt alle Lehrer auf der Karte (Questie-Menü → Stadtbewohner).
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

-- Gemerkte Lehrer mit Koordinaten, die zu diesem Charakter passen (Kopien), sortiert nach Zone und Name.
-- kind = "class" (eigene Klasse) | "profession" | "pet" (Tierausbilder) | "other" | nil (alle).
function Trainers.List(kind)
    local list = {}
    for _, t in ipairs(Npcs.List({ kind = "trainer", located = true, fits = true })) do
        Facade(t)
        if kind == nil or t.kind == kind then list[#list + 1] = t end
    end
    return list
end

local function WorldPos(mapID, x, y) return ns.WorldPos(mapID, x, y) end

-- Nächster gemerkter Lehrer auf demselben Kontinent (Kopie mit .distance in Metern) oder nil.
function Trainers.Nearest(kind)
    local mapID, x, y = ns.PlayerPosition()
    if not mapID then return nil end
    local continent, px, py = WorldPos(mapID, x, y)
    if not continent then return nil end
    local best
    for _, t in ipairs(Trainers.List(kind)) do
        local c, tx, ty = WorldPos(t.map, t.x, t.y)
        if c == continent then
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

function Trainers.PrintList()
    local list = Trainers.List()
    if #list == 0 then return ns.Print(L.TRAINER_LIST_EMPTY) end
    ns.Print(L.TRAINER_LIST:format(#list))
    for _, t in ipairs(list) do
        ns.Print(("  %s – %s %s"):format(Trainers.Label(t), ns.MapName(t.map), ns.CoordText(t.x, t.y)))
    end
end

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
