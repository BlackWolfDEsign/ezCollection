local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Leveling-Route (Idee des Nutzers vom 16.11.2026, wörtlich „weitere idee, da es questie so nicht bietet: -->optimale
    route anhand von weg lvl und bester lvl/ep ratio --> hauptgedanke sollte immer ein roter faden sein, ein spielfluss,
    keine unnötigen wege und kein gefühl von zeitverust“, dazu „mit optionalen einplanen von verkaufsmöglichkeiten“ und
    „und ggf. kräutern und erzen“; Entwurf und Antworten des Nutzers vom 17.11.2026 in docs/roadmap/ezQuest.md,
    Abschnitt „Leveling-Route – Entwurf“). Aus den Quests im Log macht ezQuest eine Reihenfolge: Ziele bündeln,
    abgeben, ohne Doppelwege – bewertet nach Erfahrung je Zeit, nicht nach der kürzesten Strecke.

    Daten (Leitlinie 11, jede Angabe mit Quelle):
      Client      Quests im Log (C_QuestLog: GetInfo, GetQuestObjectives, IsComplete, GetQuestDifficultyLevel,
                  IsEliteQuest, IsQuestTrivial, GetTimeAllowed), EP je Quest (GetQuestLogRewardXP(questID) → totalXp,
                  baseXp; genommen wird totalXp – was du jetzt bekämst), Ort je Quest (C_QuestLog.GetQuestsOnMap der
                  eigenen Zone: bei fertigen Quests die Abgabe, sonst das Gebiet der Ziele), Stufe und Erfahrung
                  (UnitLevel, UnitXP, UnitXPMax), Farbgrenze „grau“ (UnitQuestTrivialLevelRange – Blizzards Forever-
                  Quelle, Blizzard_FrameXMLUtil/Mainline/DifficultyUtil.lua, GetRelativeDifficultyColor: grau, wenn
                  Spielerstufe − Queststufe größer ist als dieser Wert).
      Questie     nur zur Laufzeit über ezCore (Core.Sources.Questie.QuestPlaces, Leitlinie 10): Orte je Teilziel und
                  der Abgabe, Folgequest. Nichts davon wird gespeichert; die Route lebt nur im Arbeitsspeicher und ist
                  nach /reload weg (Entscheidung 12 des Nutzers: der Klick auf „Route berechnen“ ist der Wunsch nach den
                  Orten laut Questie – abgefragt wird nach diesem Klick, solange die Route besteht: beim Rechnen, beim
                  Einfügen einer neuen Quest und beim Neurechnen nach einem Abbruch oder einer geänderten Einstellung).
                  Seit dem Wunsch des Nutzers vom 18.11.2026 (wörtlich „sollte es nicht grundsätzlich erstmal nach dem
                  einschalten die route berechnen?“) gilt für das Rechnen auch der Schalter „Route automatisch
                  berechnen“ (routeAuto, ab Werk an) als dieser Wunsch – Nachschlage-Wissen (Leitlinie 11). Was
                  Blizzards Zustände umstellt, bleibt bei Klick bzw. Haken (unten „Ohne Klick an Blizzards Zuständen“).
                  Gespeichert wird nur, welche Quests die Route selbst in Blizzards Verfolgung aufgenommen hat
                  (ezQuestDB.routeWatched[charKey], nur IDs), damit sie nach /reload wieder herauskommen.
      bei dir     besuchte Händler (Core.Npcs), eigene Sammel-Stellen (Core.Gathering.Nodes, cnt ≥ 2).
    Rechnung: Stationen je offenem Teilziel (Ort der dichtesten Gruppe seiner Fundorte, nie die Mitte aller) und je
    Abgabe (erst nach allen Zielen der Quest – Vorrang); Weg in Weltkoordinaten (Core.Route.WorldDistance, Yards),
    Zeit = Weg / LR.SPEED + Arbeit am Ziel; Bewertung = Summe der EP mal Ankunftszeit der Abgaben (viel EP früh) plus
    eine große Strafe je Quest, die bis zu ihrer Abgabe grau würde (Stufe entlang des Wegs hochgerechnet). Die EP jeder
    Abgabe zählen mit dem Stufenabstand gewichtet (Spieltest vom 20.11.2026; LR.Weight): orange und rot laut Client bei
    der Stufe an dieser Stelle drängen weniger nach vorn, ebenso jetzt schon graue und – ohne Gruppe – Elite-, Gruppen-
    und Dungeonquests. Reihenfolge über ezCores Rechner (Core.Route.Nearest, TwoOpt, Relocate mit Vorrang und Bewertung
    – Entscheidung 11); der Anfang nach dem kürzesten Weg ist nur der Ausgang. Danach „wird grau“ und „lohnt nicht“ mit
    Grund aus der Route, zurückgestellte Quests als Block nach hinten (LR.PushBack, bei Gleichstand später), eine
    schwere Quest allein nicht als ersten Schritt (LR.HoldBack), Händlerhalt und Sammel-
    Abstecher eingefügt. Der Tooltip jedes Schritts sagt, warum er dort steht (LR.WhyHere).
    Weiterrücken (Entscheidung 8): erfülltes Teilziel bzw. Abgabe nimmt den Schritt weg, ohne neu zu rechnen; eine neue
    Quest wird eingefügt (Core.Route.Insert); neu gerechnet wird auf Klick und nach dem Abbrechen einer Quest.
    Automatisch (Wunsch des Nutzers vom 18.11.2026, Schalter routeAuto, ab Werk an; LR.AutoSchedule): ohne Route einmal
    kurz nach dem Einloggen (LR.AUTO_DELAY) und, solange keine Route besteht, wieder, sobald sich das Questlog ändert
    (angenommen; das Log stand beim Einloggen noch nicht bzw. dein Ort war unbekannt) – gebündelt (LR.AUTO_BUNDLE) und
    höchstens alle LR.AUTO_GAP Sekunden. Besteht eine Route, gilt weiter Antwort 8 (Weiterrücken und Einfügen ohne neu
    zu rechnen; Alternative c „bei jeder Änderung neu rechnen“ hatte der Nutzer nicht gewählt) – außer nach einem
    Zonenwechsel: dann rechnet auch eine bestehende Route neu (Entscheidung des Nutzers vom 18.11.2026, „ja“ auf „Soll
    eine schon berechnete Route beim Zonenwechsel neu rechnen?“; LR.OnNewPlace, nur mit routeAuto). Nie im Kampf (danach;
    eine Rechnung ohne Klick in Scheiben hält im Kampf an), ohne Chat-Ausgabe; im Menü steht dezent „Automatisch
    berechnet …“. Eine Route, die du verwirfst, kommt bis zum nächsten Klick auf „Route berechnen“ (bzw. /reload) nicht
    von selbst wieder. Markierung, Pfeil und Verfolgung setzt auch die automatische Rechnung nie von selbst.
    Anzeige (Entscheidung 3, Leitlinien 1 und 3): Blizzards Zahnrad-Menü am Questlog (QuestId.BuildMenu) und ezMaps
    Kartenknopf (Abschnitt „Reise“); Blizzards Kartenmarkierung über ezMap mit Besitzer (Arrive lässt sie stehen,
    nichts in „Zuletzt“), die Linie über ezMaps ShowPath. Kein eigenes Fenster. Questies Tracker hat keine
    dokumentierte Schnittstelle für fremde Einträge; darum kann die Route die Quest des nächsten Schritts in Blizzards
    Verfolgung aufnehmen (Entscheidung 3: „sonst in Blizzards Verfolgung“, Haken routeWatch) und nur ihre eigenen
    Aufnahmen wieder herausnehmen – über Blizzards API wie Tracker.lua, nur außerhalb des Kampfes.
    Ohne Klick an Blizzards Zuständen (Grundsatz des Nutzers vom 17.11.2026, wörtlich „user muss auf sowas hingewiesen
    werden, er kann es nutzen muss es aber einschalten“; Funde 1 und 2 des code-reviewers vor dem Merge): Der Klick auf
    „Nächstes Ziel markieren“ (bzw. einen Schritt, /ezq route weiter) setzt die Markierung, den Pfeil nur mit ezMaps
    Schalter „Zielverfolgung einschalten“ (wayTrack, ab Werk aus seit Welle 29; sonst sagt die Route einmal je Sitzung,
    wie er kommt); danach rückt die Markierung von selbst weiter (Antwort 8), der Pfeil folgt ihr nur mit wayTrack.
    Seit der Einstellungs-Prüfung vom 19.11.2026 (Nr. 94, Zustimmung des Nutzers „Ja, alle umsetzen“) gibt es dafür
    keinen eigenen Haken mehr („Pfeil beim Weiterrücken mitnehmen“, routeArrow – er wirkte allein nicht): ezMaps
    „Zielverfolgung einschalten“ gilt, ab Werk aus. Die Verfolgung (routeWatch) gibt es nur mit Haken, ab Werk aus und
    im Menü der Route sichtbar.
    Schätzwerte (Vermutungen, im Tooltip „geschätzt“): LR.SPEED, LR.WORK, LR.TURNIN, LR.VENDOR_TIME, LR.GATHER_TIME,
    LR.WORTH, die Hochrechnung der Stufe (je weitere Stufe so viele EP wie die jetzige) und LR.TRIVIAL_FALLBACK.
]]

local LR = {}
ns.LevelRoute = LR

LR.OWNER = "ezQuest.route"
LR.PATH_FAMILY = "gold"  -- Farbfamilie der Linie in ezMap (Gold bis Orange; die Sammel-Route ist blau, Spieltest 19.11.2026)
LR.SPEED = 7            -- Yards je Sekunde zu Fuß (Vermutung: warcraft.wiki.gg „Movement speed“, Classic)
LR.WORK = 20            -- Sekunden je Einheit eines Ziels (Gegner, Gegenstand, Objekt; Vermutung)
LR.WORK_MAX = 15        -- höchstens so viele Einheiten je Teilziel gezählt
LR.TURNIN = 10          -- Sekunden je Abgabe (Vermutung)
LR.VENDOR_TIME = 30     -- Sekunden je Händlerhalt (Vermutung)
LR.GATHER_TIME = 5      -- Sekunden je Ernte (Vermutung)
LR.MERGE = 60           -- Yards: Fundorte eines Teilziels, die so nah liegen, sind eine Gegend
LR.MAX_STATIONS = 80    -- höchstens so viele Stationen je Rechnung (der Rest steht mit Grund in der Liste)
LR.WORTH = 0.25         -- „lohnt nicht“ unter einem Viertel des mittleren EP-Ertrags je Zeit (Vermutung)
LR.HARD_LEVELS = 3      -- „schwer“: mehr als so viele Stufen über dir
LR.REPAIR_LOW = 0.25    -- Haltbarkeit am schlechtesten Platz, ab der ein Reparierer eingeplant wird (Antwort 4)
LR.SHOWN = 5            -- so viele Schritte stehen direkt im Menü
LR.GATHER_MIN_CNT = 2   -- Sammel-Stellen nur, wo du mindestens so oft geerntet hast
LR.GATHER_MAX = 10      -- höchstens so viele Sammel-Abstecher je Route
LR.REACH = 25           -- Yards: so nah an einer Sammel-Stelle gilt eine Ernte als dieser Schritt
LR.SAME_NPC = 15        -- Yards: Abgaben so nah beieinander beim selben Namen sind ein Schritt
LR.SAME_SPOT = 3        -- Yards: Abgaben ohne Namen (Ort laut Spiel) so nah beieinander sind ein Schritt
LR.SAME_PLACE = 0.0005  -- Kartenanteil: derselbe Ort eines Schritts in alter und neuer Route (wie ezMaps Way.lua)
LR.NAME_NEAR = 60       -- Yards: so nah an der Abgabe laut Spiel gilt die Abgabe laut Questie als derselbe NPC
LR.SYNC_MAX = 12        -- bis zu so vielen Stationen (höchstens: je Quest die Abgabe und jedes offene Teilziel) sofort
                        -- gerechnet, sonst in Scheiben – WoWs Lua 5.1 ohne JIT; Fund 4 des code-reviewers vor dem Merge
LR.SLICE = 20000        -- Rechenschritte je Bild beim Rechnen in Scheiben
LR.ROUNDS = 6           -- Durchgänge 2-opt bzw. Verschieben mit Bewertung
LR.AREA = 50            -- Yards: so nah beieinander gilt als dieselbe Gegend (kein Hin und Her, LR.Smooth)
LR.FLOW_GAIN = 5        -- Sekunden: so viel kürzer muss die Route ohne das Hin und Her mindestens werden (Vermutung)
LR.SMOOTH_ROUNDS = 20   -- höchstens so viele Verschiebungen gegen das Hin und Her je Rechnung
LR.NEXT_BONUS = 1.5     -- Gewicht der Abgabe einer Quest mit Folgequest (die Kette läuft dort gleich weiter)
LR.TIMED_BONUS = 3      -- Gewicht einer Quest mit Zeitlimit (kommt nach vorn)
LR.GREY_PENALTY = 1e12  -- Strafe je Quest, die bis zu ihrer Abgabe grau würde
LR.TRIVIAL_FALLBACK = Core.QUEST_TRIVIAL_FALLBACK or 5 -- Stufen unter dir, ab denen grau gilt ohne Client (Vermutung)
-- Stufenabstand (Spieltest vom 20.11.2026, wörtlich „optimiert wäre es an lvl stufe bzw lvl differenz von questlevel zu
-- meinem lvl und zeit ersparnis“): Gewicht der Abgabe je Farbe der Quest laut Client (Core.QuestDifficulty) bei der
-- Stufe, die du an dieser Stelle der Route voraussichtlich hast. Kleiner heißt: drängt weniger nach vorn (Vermutungen).
LR.LEVEL_WEIGHT = { impossible = 0.1, verydifficult = 0.3, difficult = 1, standard = 1, trivial = 0.3 }
LR.ALONE_WEIGHT = 0.3   -- Elite-, Gruppen- und Dungeonquests ohne Gruppe (Vermutung)
LR.REMOVED_WAIT = 0.5   -- Sekunden: so lange wartet „Quest abgebrochen?“ auf ein QUEST_TURNED_IN derselben Quest
LR.AUTO_DELAY = 3       -- Sekunden nach dem Einloggen bis zur ersten Rechnung ohne Klick (Questlog und Ort stehen dann)
LR.AUTO_BUNDLE = 1      -- Sekunden: Änderungen im Questlog so lange sammeln, dann einmal rechnen
LR.AUTO_GAP = 2.5       -- Sekunden: höchstens eine Rechnung ohne Klick je so viel Zeit
LR.AUTO_EMPTY_RETRY = 30    -- Sekunden: eine leere Route ohne Klick einmal je Sitzung so viel später neu (Orte bereit)

LR.ICONS = {
    route = { file = "Interface\\Icons\\Ability_Tracking" },
    obj = { atlas = "Waypoint-MapPin-Untracked", file = "Interface\\Icons\\INV_Misc_Map_01" },
    turnin = { file = "Interface\\GossipFrame\\ActiveQuestIcon" },
    vendor = { file = { "Interface\\Minimap\\Tracking\\Repair", "Interface\\Icons\\INV_Misc_Coin_01" } },
    mark = { atlas = "Waypoint-MapPin-Tracked", file = "Interface\\Icons\\INV_Misc_Map_01" },
    skip = { file = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up" },
    clear = { file = "Interface\\Buttons\\UI-GroupLoot-Pass-Up" },
    info = { file = "Interface\\Common\\help-i" },
}
-- Symbol eines Sammel-Abstechers auf der Weltkarte, wenn ezCore das Symbol des Berufs nicht nennt (Leitlinie 1:
-- Blizzards Symbole der Berufe)
LR.GATHER_FILE = { herb = "Interface\\Icons\\Trade_Herbalism", ore = "Interface\\Icons\\Trade_Mining" }

local Num, Plain, Bool, Call = Core.Num, Core.Plain, Core.Bool, Core.Call
local Menu = Core.Menu

local state        -- die berechnete Route (nur im Arbeitsspeicher)
local job          -- laufende Rechnung in Scheiben
local turnedIn = {}  -- [questID] = true nach QUEST_TURNED_IN (QUEST_REMOVED danach rechnet nicht neu)
local merchantOpen = false  -- Händlerfenster offen (MERCHANT_SHOW bis MERCHANT_CLOSED): kein neuer Händlerhalt
local watchedScratch = {}   -- Rückfall ohne ezQuestDB bzw. Charakter-Schlüssel (nur Arbeitsspeicher)
local autoPending = false   -- eine Rechnung ohne Klick ist vorgemerkt (C_Timer läuft)
local autoLast              -- GetTime der letzten Rechnung ohne Klick (Abstand LR.AUTO_GAP)
local autoRetry = false     -- die letzte Rechnung ohne Klick ging nicht (Questlog leer bzw. nicht bereit, Ort unbekannt)
local emptyRetried = false  -- die leere Route ohne Klick wurde in dieser Sitzung schon einmal zeitversetzt neu versucht

-- Abgegeben bzw. abgebrochen, während in Scheiben gerechnet wird: nach der Rechnung heraus (Fund 7). War die Quest erst
-- während der Rechnung angenommen, wird sie danach auch nicht mehr eingefügt – sonst bliebe ein Abgabe-Schritt für eine
-- Quest stehen, die es nicht mehr gibt (Fund der Gegenprüfung vom 17.11.2026). Eine danach wieder angenommene
-- (wiederholbare) Quest kommt über QUEST_ACCEPTED erneut in job.add.
local function JobDrop(questID)
    if not job then return end
    job.drop[#job.drop + 1] = questID
    for i = #job.add, 1, -1 do
        if job.add[i] == questID then table.remove(job.add, i) end
    end
end

-- Von der Route in Blizzards Verfolgung aufgenommene Quests dieses Charakters: [questID] = true, gespeichert in
-- ezQuestDB.routeWatched[charKey] (nur IDs). Vorher nur im Arbeitsspeicher – nach /reload blieben die Aufnahmen für
-- immer in Blizzards Verfolgung (Fund 3 des code-reviewers vor dem Merge). create = false: nil, solange es keine gibt.
local function Watching(create)
    local db, key = ns.db, ns.charKey or Core.charKey
    if type(db) ~= "table" or not key then return watchedScratch end
    if type(db.routeWatched) ~= "table" then db.routeWatched = {} end
    local mine = db.routeWatched[key]
    if type(mine) ~= "table" then
        if not create then return nil end
        mine = {}
        db.routeWatched[key] = mine
    end
    return mine
end

-- leere Liste eines Charakters wieder entfernen (nichts Leeres in ezQuestDB)
local function WatchingTidy()
    local db, key = ns.db, ns.charKey or Core.charKey
    local all = type(db) == "table" and key and db.routeWatched
    if type(all) == "table" and type(all[key]) == "table" and next(all[key]) == nil then all[key] = nil end
end

function LR.State() return state end
function LR.Running() return job ~= nil end

local function R() return Core.Route end

---------------------------------------------------------------------------
-- Lesen: Questlog laut Client
---------------------------------------------------------------------------

local function Log() return type(C_QuestLog) == "table" and C_QuestLog or nil end

-- Teilziele einer Quest laut Client → { { index, text, type, done, have, need } … }
function LR.Objectives(questID)
    local log = Log()
    local list = log and Call(log.GetQuestObjectives, questID)
    local out = {}
    if Core.IsSecret(list) or type(list) ~= "table" then return out end
    for k, o in ipairs(list) do
        if type(o) == "table" and not Core.IsSecret(o) then
            out[#out + 1] = { index = k, text = Plain(o.text), type = Plain(o.type), done = Bool(o.finished, false) == true,
                have = Num(o.numFulfilled), need = Num(o.numRequired) }
        end
    end
    return out
end

-- Eine Quest des Logs → { id, title, level, complete, elite, trivial, dungeon, timed, xp, xpSrc, objectives, order }
function LR.ReadQuest(questID, info, order)
    local log = Log()
    local q = { id = questID, order = order or 0 }
    q.title = Plain(type(info) == "table" and info.title) or Core.QuestTitle(questID) or ("#" .. questID)
    q.level = Num(Call(log.GetQuestDifficultyLevel, questID)) or Num(type(info) == "table" and info.difficultyLevel)
        or Num(type(info) == "table" and info.level)
    if q.level and q.level <= 0 then q.level = nil end
    q.elite = Bool(Call(log.IsEliteQuest, questID), false) == true
    -- Gruppenquest laut Client (C_QuestLog.GetSuggestedGroupSize, sonst suggestedGroup aus GetInfo; Spieltest 20.11.2026)
    q.groupSize = Num(Call(log.GetSuggestedGroupSize, questID)) or Num(type(info) == "table" and info.suggestedGroup)
    q.group = (q.groupSize or 0) > 1
    q.trivial = Bool(Call(log.IsQuestTrivial, questID), false) == true
    q.dungeon = ns.DungeonQuests ~= nil and ns.DungeonQuests.For(questID) ~= nil
    q.timed = (Num(Call(log.GetTimeAllowed, questID)) or 0) > 0
    q.objectives = LR.Objectives(questID)
    -- fertig und EP über ezCores gemeinsame Helfer (Feature I1 vom 18.11.2026: dieselbe Rechnung für die Vorschau auf
    -- der Erfahrungsleiste, XPPreview.lua; vorher stand beides nur hier)
    q.complete = Core.QuestReady(questID)
    q.xp, q.xpSrc = Core.QuestXP(questID)
    return q
end

-- Alle Quests des Logs (ohne Überschriften und verborgene) → Liste oder nil, "noQuestLog"
-- (derselbe Filter wie die Vorschau auf der Erfahrungsleiste: Core.QuestLogEntries, Gegenprüfung I1 vom 18.11.2026)
function LR.ReadLog()
    local entries = Core.QuestLogEntries()
    if not entries then return nil, "noQuestLog" end
    local quests = {}
    for _, entry in ipairs(entries) do quests[#quests + 1] = LR.ReadQuest(entry.id, entry.info, #quests + 1) end
    return quests
end

---------------------------------------------------------------------------
-- Orte: Client » Questie (eigene Daten für Quest-Orte: noch offen, docs/roadmap/ezQuest.md)
---------------------------------------------------------------------------

local function World(p)
    local Route = R()
    return Route and Route.World(p) or false
end

local function ZoneOf(map)
    local zone = Core.Map.Parent(map, "Zone")
    return zone or map
end

-- Orte der Log-Quests auf der Karte zone laut Client → { [questID] = { map, x, y } }
function LR.ClientPlaces(zone)
    local log = Log()
    local out = {}
    local list = zone and log and Call(log.GetQuestsOnMap, zone)
    if Core.IsSecret(list) or type(list) ~= "table" then return out end
    for _, e in ipairs(list) do
        if type(e) == "table" and not Core.IsSecret(e) then
            local id, x, y = Num(e.questID), Num(e.x), Num(e.y)
            if id and x and y and x > 0 and y > 0 and x < 1 and y < 1 then out[id] = { map = zone, x = x, y = y } end
        end
    end
    return out
end

local function Fold(text)
    if type(text) ~= "string" then return nil end
    local Q = Core.Sources and Core.Sources.Questie
    if Q and type(Q.Fold) == "function" then return Q.Fold(text) end
    return text:lower()
end

-- Teilziel des Clients ↔ Ziel laut Questie: zuerst über den Namen im Zieltext, sonst das k-te Ziel derselben Art
local KIND_OF_TYPE = { monster = "monster", killcredit = "monster", item = "item", object = "object" }
function LR.MatchObjective(o, qp, used)
    if type(qp) ~= "table" or type(qp.objectives) ~= "table" then return nil end
    local text = Fold(o.text)
    if text then
        for i, e in ipairs(qp.objectives) do
            local name = Fold(e.name)
            if not used[i] and name and #name >= 3 and text:find(name, 1, true) then
                used[i] = true
                return e
            end
        end
    end
    local want = KIND_OF_TYPE[o.type]
    if want then
        for i, e in ipairs(qp.objectives) do
            if not used[i] and KIND_OF_TYPE[e.type] == want then
                used[i] = true
                return e
            end
        end
    end
    return nil
end

-- Ort einer Station aus vielen Fundorten: die Gruppe mit den meisten Fundorten – in der eigenen Zone, wenn es dort eine
-- gibt, sonst auf dem eigenen Kontinent (Fund 11 des code-reviewers vor dem Merge: vorher gewann ohne Gruppe in der
-- eigenen Zone die größte Gruppe, auch auf einem anderen Kontinent) –, als Ort der Fundort nahe ihrer Mitte, nie die
-- Mitte aller. → ort, Zahl der Gruppen, in eigener Zone?
-- tick (freiwillig) zählt die Rechenschritte des Zusammenfassens (Rechnung in Scheiben)
function LR.BestPlace(places, ctx, tick)
    local Route = R()
    local pts = {}
    for _, p in ipairs(places or {}) do
        local w = { map = p.map, x = p.x, y = p.y, name = p.name }
        if w.map and World(w) then
            w.zone = ZoneOf(w.map)
            pts[#pts + 1] = { x = w.wx, y = w.wy, ref = w }
        end
    end
    if #pts == 0 then return nil, 0, false end
    -- Weltkoordinaten gelten je Kontinent (Route.WorldDistance: math.huge dazwischen): je Kontinent für sich
    -- zusammenfassen, sonst fielen zufällig gleich liegende Fundorte zweier Kontinente in eine Gruppe
    local byCont, conts = {}, {}
    for _, pt in ipairs(pts) do
        local c = pt.ref.continent or false
        if not byCont[c] then
            byCont[c] = {}
            conts[#conts + 1] = c
        end
        byCont[c][#byCont[c] + 1] = pt
    end
    local groups = {}
    for _, c in ipairs(conts) do
        for _, g in ipairs(Route.Merge(byCont[c], LR.MERGE, 1, 1, tick)) do groups[#groups + 1] = g end
    end
    local best, bestRank
    for _, g in ipairs(groups) do
        local rank = 0          -- 2: eigene Zone, 1: eigener Kontinent, 0: anderswo
        for _, m in ipairs(g.members) do
            if m.ref.continent == ctx.continent then
                rank = math.max(rank, m.ref.zone == ctx.zone and 2 or 1)
            end
        end
        if not best or rank > bestRank or (rank == bestRank and g.n > best.n) then best, bestRank = g, rank end
    end
    local bestHome = bestRank == 2
    local place, near
    for _, m in ipairs(best.members) do
        local d = (m.x - best.x) ^ 2 + (m.y - best.y) ^ 2
        if (not near or d < near) and (not bestHome or m.ref.zone == ctx.zone) then place, near = m.ref, d end
    end
    return place, #groups, bestHome
end

-- Orte einer Quest laut Questie (nil ohne QuestieDB); die Orte auf der Karte zone kommen zuerst, damit die Grenze je
-- Ziel (Questie.PLACES_PER_PART) deine Zone nicht abschneidet
local function QuestiePlaces(questID, zone)
    local Q = Core.Sources and Core.Sources.Questie
    if not (Q and type(Q.QuestPlaces) == "function") then return nil end
    local ok, places = pcall(Q.QuestPlaces, questID, zone and { map = zone } or nil)
    return ok and type(places) == "table" and places or nil
end

---------------------------------------------------------------------------
-- Stationen
---------------------------------------------------------------------------

-- Grenze „grau“ laut Client (UnitQuestTrivialLevelRange), sonst LR.TRIVIAL_FALLBACK (Vermutung) → Stufen, Quelle
function LR.TrivialRange()
    local range = Num(Call(rawget(_G, "UnitQuestTrivialLevelRange"), "player"))
    if range and range >= 0 then return range, "client" end
    return LR.TRIVIAL_FALLBACK, "estimate"
end

-- Was ezQuest zum Rechnen braucht: Ort des Spielers, Zone, Stufe, Erfahrung, Einstellungen → ctx oder nil, Grund
function LR.Context()
    local map, x, y = Core.PlayerPosition()
    if not map then return nil, "position" end
    local start = { kind = "start", map = map, x = x, y = y }
    if not World(start) then return nil, "position" end
    local level = Core.PlayerLevel() or 1
    local xp = Num(Call(rawget(_G, "UnitXP"), "player")) or 0
    local xpMax = Num(Call(rawget(_G, "UnitXPMax"), "player"))
    if not xpMax or xpMax <= 0 then xpMax = nil end
    local range, rangeSrc = LR.TrivialRange()
    return { start = start, zone = ZoneOf(map), continent = start.continent, level = level, xp = xp, xpMax = xpMax,
        range = range, rangeSrc = rangeSrc, hard = ns.Enabled("routeHard"), detour = Num(ns.S and ns.S.routeDetour) or 60,
        alone = not LR.InGroup() }
end

-- In einer Gruppe? (IsInGroup laut Client; gesperrt oder unbekannt heißt allein)
function LR.InGroup()
    return Core.Flag(Call(rawget(_G, "IsInGroup")), false) == true
end

-- Warum eine Quest gar nicht in die Route kommt (vor den Orten) → Grund oder nil
function LR.Excluded(q, ctx)
    if ctx.hard then return nil end
    if q.elite then return "elite" end
    if q.dungeon then return "dungeon" end
    if q.level and q.level > ctx.level + LR.HARD_LEVELS then return "high" end
    return nil
end

--[[
    Stufenabstand (Spieltest vom 20.11.2026: Stufe 22 bei Astranaar, die Route begann mit einer nahen Elite-Quest der
    Stufe 25, die nahen Quests der Stufen 18–21 standen dahinter). Bewertet wird die Farbe laut Client
    (Core.QuestDifficulty: rot, orange, gelb, grün, grau; ohne Antwort geschätzt nach Blizzards Grenzen):
      LR.Difficulty(stufe, spielerstufe, ctx) → Farbe, Quelle (je Rechnung zwischengespeichert in ctx.diff)
      LR.Weight(q, stufe, ctx)  → Gewicht der Abgabe in der Bewertung (LR.LEVEL_WEIGHT bei der Stufe an dieser Stelle der
                                  Route, mal LR.ALONE_WEIGHT für Elite, Gruppe, Dungeon ohne Gruppe). Grau zählt nur,
                                  wenn die Quest jetzt schon grau ist – was erst unterwegs grau würde, zieht LR.PullForward
                                  nach vorn.
      LR.Held(q, ctx)           → { key, src, high, grey, elite, group, dungeon, first, later } bei deiner Stufe jetzt:
                                  first = darf nicht der erste Schritt sein (orange, rot, Elite, Gruppe, Dungeon allein),
                                  later = dazu grau. LR.HoldBack, LR.Smooth und LR.Uncross halten das ein.
]]
local function Cached(ctx, name)
    local t = ctx[name]
    if not t then t = {} ctx[name] = t end
    return t
end

function LR.Difficulty(qlevel, plevel, ctx)
    qlevel, plevel = Num(qlevel), Num(plevel)
    if not (qlevel and plevel) then return nil end
    local cache = ctx and Cached(ctx, "diff")
    local k = qlevel * 1000 + plevel
    local e = cache and cache[k]
    if not e then
        local key, src = Core.QuestDifficulty(qlevel, plevel)
        e = { key or false, src }
        if cache then cache[k] = e end
    end
    return e[1] or nil, e[2]
end

function LR.Held(q, ctx)
    local cache = Cached(ctx, "held")
    local h = cache[q]
    if h then return h end
    h = {}
    if q.trivial then
        h.key, h.src = "trivial", "client"
    elseif q.level then
        h.key, h.src = LR.Difficulty(q.level, ctx.level, ctx)
    end
    h.high = h.key == "impossible" or h.key == "verydifficult"
    h.grey = h.key == "trivial"
    -- eine Quest mit Zeitlimit kommt nach vorn (LR.TIMED_BONUS) und wird nie zurückgestellt (Fund 5 des code-reviewers
    -- vom 20.11.2026); Stufe und Farbe nennt der Tooltip trotzdem
    if ctx.alone and not q.timed then h.elite, h.group, h.dungeon = q.elite == true, q.group == true, q.dungeon == true end
    h.first = not q.timed and (h.high or h.elite or h.group or h.dungeon) or false
    h.later = h.first or (h.grey and not q.timed) or false
    cache[q] = h
    return h
end

function LR.Weight(q, level, ctx)
    local byQuest = Cached(ctx, "weight")
    local known = byQuest[q]
    if not known then known = {} byQuest[q] = known end
    local w = known[level]
    if w then return w end
    w = 1
    if q.trivial or (q.level and LR.Held(q, ctx).grey) then
        w = LR.LEVEL_WEIGHT.trivial
    elseif q.level then
        local key = LR.Difficulty(q.level, level, ctx)
        if key and key ~= "trivial" then w = LR.LEVEL_WEIGHT[key] or 1 end
    end
    if ctx.alone and (q.elite or q.group or q.dungeon) then w = w * LR.ALONE_WEIGHT end
    known[level] = w
    return w
end

local function Work(o)
    local need, have = Num(o.need), Num(o.have) or 0
    local units = need and math.max(1, need - have) or 1
    return LR.WORK * math.min(units, LR.WORK_MAX)
end

local function Station(kind, q, place, src)
    return { kind = kind, quest = q, map = place.map, x = place.x, y = place.y, continent = place.continent,
        wx = place.wx, wy = place.wy, zone = place.zone, src = src, name = place.name }
end

-- Ziel-Station derselben Quest in derselben Gegend wie place (bis LR.MERGE Yards) → Station oder nil
function LR.SameArea(list, place)
    for _, s in ipairs(list) do
        if s.kind == "obj" and R().WorldDistance(s, place) <= LR.MERGE then return s end
    end
    return nil
end

-- Offene Teilziele eines Ziel-Schritts (mehrere, wenn Ziele derselben Quest in einer Gegend zusammengefasst sind)
function LR.ObjsOf(s)
    if s.objs then return s.objs end
    return s.obj and { s.obj } or {}
end

-- Mittel der EP laut Client über quests → Mittel oder nil (keine Quest mit EP laut Client)
function LR.MeanXP(quests)
    local known, sum = 0, 0
    for _, q in ipairs(quests) do
        if q.xp and q.xpSrc == "client" then known, sum = known + 1, sum + q.xp end
    end
    return known > 0 and sum / known or nil
end

--[[
    Stationen aller Quests → stationen (1 = Anfang), after (Vorrang), outside (nicht eingeplant, mit Grund).
    Eine Quest kommt in die Route, wenn der Ort ihrer Abgabe auf deinem Kontinent bekannt ist und jedes offene Teilziel
    einen Ort in deiner Zone hat (Entscheidung 10: eigene Zone und alle Abgaben). Gründe: "elite", "dungeon", "high"
    (nur mit „Schwere Quests einplanen“ aus), "zone" (Ziel in einer anderen Zone), "continent", "noplace" (Ziel ohne Ort),
    "noturnin" (Abgabe ohne Ort), "capped" (mehr als LR.MAX_STATIONS Stationen). tick (freiwillig) zählt Rechenschritte.
]]
function LR.Stations(quests, ctx, client, tick)
    local stations, after, outside = { ctx.start }, {}, {}
    ctx.start.i = 1
    local sources = {}
    local mean = LR.MeanXP(quests)
    for _, q in ipairs(quests) do
        -- ohne EP laut Client: das Mittel der bekannten (geschätzt). Nennt der Client für keine Quest EP, zählt 1 nur
        -- für die Reihenfolge (dann nach Weg und Zeit) und heißt überall „EP unbekannt“ – keine erfundene Zahl
        -- (Fund der Gegenprüfung vom 17.11.2026)
        if not q.xp then q.xp, q.xpSrc = mean or 1, mean and "mean" or "none" end
        local reason = LR.Excluded(q, ctx)
        local list = {}
        local qp
        if not reason then
            -- Ziele
            if not q.complete then
                local used = {}
                for _, o in ipairs(q.objectives) do
                    if not o.done and not reason then
                        local place, groups, home, src
                        local c = client[q.id]
                        if c then
                            place = { map = c.map, x = c.x, y = c.y }
                            if World(place) then place.zone, groups, home, src = ZoneOf(place.map), 1, true, "client" else place = nil end
                        end
                        if not place then
                            qp = qp or QuestiePlaces(q.id, ctx.zone) or false
                            local e = qp and LR.MatchObjective(o, qp, used)
                            if e then
                                place, groups, home = LR.BestPlace(e.places, ctx, tick)
                                src = "questie"
                                if place and not place.name then place.name = e.name end
                            end
                        end
                        if not place then
                            reason = "noplace"
                        elseif place.continent ~= ctx.continent then
                            reason = "continent"
                        elseif not home or place.zone ~= ctx.zone then
                            reason = "zone"
                        else
                            -- Ziele derselben Quest in derselben Gegend (bis LR.MERGE Yards; laut Spiel steht jede Quest
                            -- an einem Punkt) sind ein Schritt (Spielbefund vom 18.11.2026: „lvl route wirkt komisch“ –
                            -- vorher je Ziel ein Schritt am selben Ort, auf der Karte Knicke ohne eigenes Ziel)
                            local s = LR.SameArea(list, place)
                            if s then
                                s.objs = s.objs or { s.obj }
                                s.objs[#s.objs + 1] = o
                                s.work = s.work + Work(o)
                                s.groups = math.max(s.groups or 1, groups or 1)
                            else
                                s = Station("obj", q, place, src)
                                s.obj, s.work, s.groups = o, Work(o), groups
                                list[#list + 1] = s
                            end
                        end
                    end
                end
            end
            -- Abgabe: Ort laut Spiel (fertige Quest), sonst laut Questie. Name des NPC und Folgequest kommen laut Questie
            -- auch zum Ort laut Spiel – sonst bündelte die Route zwei Abgaben beim selben NPC nie und nennte ihn nicht
            -- (Fund der Gegenprüfung vom 17.11.2026)
            if not reason then
                local place, src, nameSrc
                local c = client[q.id]
                if q.complete and c then
                    place = { map = c.map, x = c.x, y = c.y }
                    if World(place) then place.zone, src = ZoneOf(place.map), "client" else place = nil end
                end
                if qp == nil then qp = QuestiePlaces(q.id, ctx.zone) or false end
                local finish = qp and type(qp.finish) == "table" and #qp.finish > 0 and LR.BestPlace(qp.finish, ctx, tick)
                    or nil
                if not place then
                    place, src = finish, finish and "questie" or nil
                elseif finish and finish.name and finish.continent == place.continent
                    and R().WorldDistance(place, finish) <= LR.NAME_NEAR then
                    place.name, nameSrc = finish.name, "questie"
                end
                if not place then
                    reason = "noturnin"
                elseif place.continent ~= ctx.continent then
                    reason = "continent"
                else
                    local s = Station("turnin", q, place, src)
                    s.work, s.xp, s.nameSrc = LR.TURNIN, q.xp, nameSrc
                    s.next = qp and qp.next or nil
                    list[#list + 1] = s
                end
            end
        end
        if tick then tick(1 + #q.objectives) end
        if not reason and #stations - 1 + #list > LR.MAX_STATIONS then reason = "capped" end
        if reason then
            outside[#outside + 1] = { quest = q, reason = reason }
        else
            local objIdx = {}
            for _, s in ipairs(list) do
                stations[#stations + 1] = s
                s.i = #stations
                sources[s.src] = (sources[s.src] or 0) + 1
                if s.kind == "obj" then objIdx[#objIdx + 1] = s.i else after[s.i] = objIdx end
            end
        end
    end
    return stations, after, outside, sources
end

---------------------------------------------------------------------------
-- Bewertung: Zeit, EP-gewichtete Ankunft, Stufe entlang des Wegs
---------------------------------------------------------------------------

-- Abstandstabelle (Yards) einmal je Rechnung → dist(a, b) über die Indizes der Stationen (tick: je Zeile)
function LR.DistanceTable(stations, tick)
    local D, dist = {}, R().WorldDistance
    for i = 1, #stations do
        D[i] = {}
        stations[i].i = i
    end
    for i = 1, #stations do
        for j = i, #stations do
            local d = i == j and 0 or dist(stations[i], stations[j])
            D[i][j], D[j][i] = d, d
        end
        if tick then tick(#stations - i + 1) end
    end
    return function(a, b) return D[a.i][b.i] end
end

-- Gang der Route (full: mit Ankunftszeiten und grauen Quests; sonst nur Bewertung und Zeit, ohne neue Tabellen – die
-- Bewertung läuft beim Verschieben tausendfach je Rechnung; Fund 4 des code-reviewers vor dem Merge)
local function Walk(stations, order, dist, ctx, full)
    local t, cost, gained = 0, 0, 0
    local level, need = ctx.level, ctx.xpMax and (ctx.xpMax - ctx.xp) or nil
    local times, grey
    if full then times, grey = {}, {} end
    local prev = stations[order[1]]
    for pos = 2, #order do
        local s = stations[order[pos]]
        local d = dist(prev, s)
        if d == math.huge then d = 0 end
        t = t + d / LR.SPEED + (s.work or 0)
        if full then times[pos] = t end
        prev = s
        if s.kind == "turnin" then
            local q = s.quest
            if q.level and not q.trivial and level - q.level > ctx.range then
                if full then grey[q.id] = level end
                cost = cost + LR.GREY_PENALTY
            end
            local weight = (s.next and LR.NEXT_BONUS or 1) * (q.timed and LR.TIMED_BONUS or 1) * LR.Weight(q, level, ctx)
            cost = cost + (s.xp or 0) * weight * t
            gained = gained + (s.xp or 0)
            if need then
                local got = s.xp or 0
                while need and got >= need do
                    got = got - need
                    level = level + 1
                    need = ctx.xpMax        -- je weitere Stufe so viele EP wie die jetzige (Vermutung)
                end
                need = need - got
            end
        end
    end
    if not full then return cost, t end
    return { times = times, total = t, xp = gained, cost = cost, grey = grey, level = level }
end

-- Gang der Route: je Station Ankunftszeit, Stufe bei der Abgabe, grau? → { t = { [pos] = Sek. }, total, xp, cost,
-- grey = { [questID] = Stufe } }
function LR.Walk(stations, order, dist, ctx) return Walk(stations, order, dist, ctx, true) end

-- Nur die Bewertung (und die Zeit) einer Reihenfolge → cost, Sekunden – dieselbe Rechnung wie LR.Walk ohne Tabellen
function LR.Cost(stations, order, dist, ctx) return Walk(stations, order, dist, ctx, false) end

-- Gehört ein Schritt zur Quest? Auch eine gebündelte Abgabe (s.quests; s.quest ist dort nur die erste Quest)
local function HasQuest(s, questID)
    for _, q in ipairs(LR.QuestsOf(s)) do
        if q.id == questID then return true end
    end
    return false
end

-- Alle Stationen einer Quest aus order nehmen (in ihrer Folge) → Block. Eine gebündelte Abgabe, an der die Quest
-- hängt, kommt mit: sie nach hinten zu legen bleibt gültig, die Ziele ihrer übrigen Quests stehen davor (Fund 1 des
-- code-reviewers vom 20.11.2026: vorher blieb sie stehen, und das Ziel landete hinter seiner eigenen Abgabe).
local function TakeBlock(stations, order, questID)
    local block = {}
    for pos = #order, 2, -1 do
        if HasQuest(stations[order[pos]], questID) then table.insert(block, 1, table.remove(order, pos)) end
    end
    return block
end

-- Vorrang einer Reihenfolge von Schritten bzw. Stationen: kein Ziel nach einer Abgabe derselben Quest → true | false
-- (für Reihenfolgen ohne Tabelle after, LR.Insert)
local function StepsValid(stations, order)
    local handed = {}
    for pos = 2, #order do
        local s = stations[order[pos]]
        if s.kind == "obj" and s.quest and handed[s.quest.id] then return false end
        if s.kind == "turnin" then
            for _, q in ipairs(LR.QuestsOf(s)) do handed[q.id] = true end
        end
    end
    return true
end

-- Günstigste Stelle für einen Block (ab Stelle from) nach LR.Cost; late: bei Gleichstand die spätere → Stelle, Bewertung
-- (Gleichstand bei late relativ zur Bewertung; sonst wie vorher in LR.PullForward fest 1e-9 – Hinweis des code-reviewers)
local function BestSpot(stations, order, block, dist, ctx, from, late, tick)
    local bestAt, bestCost
    for at = from, #order + 1 do
        for k, idx in ipairs(block) do table.insert(order, at + k - 1, idx) end
        local cost = LR.Cost(stations, order, dist, ctx)
        local tol = late and 1e-9 * math.max(1, math.abs(bestCost or 0)) or 1e-9
        if not bestCost or cost < bestCost - tol or (late and cost <= bestCost + tol) then bestAt, bestCost = at, cost end
        if tick then tick(#order) end
        for _ = 1, #block do table.remove(order, at) end
    end
    return bestAt or from, bestCost
end

local function PutBlock(order, block, at)
    for k, idx in ipairs(block) do table.insert(order, at + k - 1, idx) end
end

-- Quests, die bis zu ihrer Abgabe grau würden, als Block nach vorn ziehen (Antwort 2: „eine grüne quest nicht während
-- des ablaufen … grau wird“): Ziele und Abgabe der Quest zusammen an die Stelle, an der die Bewertung am kleinsten ist.
-- Einzelne Züge (2-opt, Verschieben) schaffen das nicht – das Ziel allein nach vorn bringt nichts, solange die Abgabe
-- hinten steht, und die Abgabe darf nicht vor ihr Ziel. tick (freiwillig): je Bewertung. → Zahl der verschobenen Quests
function LR.PullForward(stations, order, dist, ctx, tick)
    local moved = 0
    local walk = LR.Walk(stations, order, dist, ctx)
    for questID in pairs(walk.grey) do
        local block = TakeBlock(stations, order, questID)
        local bestAt, bestCost = BestSpot(stations, order, block, dist, ctx, 2, false, tick)
        PutBlock(order, block, bestAt)
        if bestCost and bestCost < walk.cost - 1e-9 then moved = moved + 1 end
        walk = LR.Walk(stations, order, dist, ctx)
    end
    return moved
end

--[[
    Zurückgestellte Quests als Block nach hinten (Spieltest vom 20.11.2026): je Quest mit LR.Held(…).later (orange, rot,
    grau, Elite/Gruppe/Dungeon allein) Ziele und Abgabe zusammen an die Stelle mit der kleinsten Bewertung, bei
    Gleichstand an die spätere – genommen nur, wenn die Bewertung dadurch nicht steigt. Einzelne Züge (2-opt,
    Verschieben) holen eine Quest, die der kürzeste Weg an den Anfang gelegt hat, nicht als Ganzes nach hinten; und wo
    der Weg gleich lang ist (zwei Ziele, eine Abgabe-Stelle), entscheidet so die Stufe. tick (freiwillig): je Bewertung.
    → Zahl der verschobenen Quests
]]
function LR.PushBack(stations, order, dist, ctx, tick)
    local moved, ids, seen = 0, {}, {}
    for pos = 2, #order do
        local q = stations[order[pos]].quest
        if q and not seen[q.id] and LR.Held(q, ctx).later then seen[q.id], ids[#ids + 1] = true, q.id end
    end
    for _, questID in ipairs(ids) do
        local before = {}
        for k, v in ipairs(order) do before[k] = v end
        local current = LR.Cost(stations, order, dist, ctx)
        local block = TakeBlock(stations, order, questID)
        local bestAt, bestCost = BestSpot(stations, order, block, dist, ctx, 2, true, tick)
        if bestCost and bestCost <= current + 1e-9 * math.max(1, math.abs(current)) then
            PutBlock(order, block, bestAt)
            for k, v in ipairs(order) do
                if before[k] ~= v then moved = moved + 1 break end
            end
        else
            for k, v in ipairs(before) do order[k] = v end
        end
    end
    return moved
end

-- Vorrang erfüllt (jedes Ziel vor seiner Abgabe; after wie bei LR.Stations, herausgenommene Quests zählen nicht)?
local function Valid(order, after)
    local pos = {}
    for p, idx in ipairs(order) do pos[idx] = p end
    for idx, objs in pairs(after or {}) do
        local tp = pos[idx]
        if tp then
            for _, o in ipairs(objs) do
                if pos[o] and pos[o] > tp then return false end
            end
        end
    end
    return true
end

-- Kopie von order, in der das Element an Stelle from an Stelle to steht
local function Moved(order, from, to)
    local out = {}
    for k, v in ipairs(order) do out[k] = v end
    table.insert(out, to, table.remove(out, from))
    return out
end

local function Greys(walk)
    local n = 0
    for _ in pairs(walk.grey) do n = n + 1 end
    return n
end

--[[
    Kein Hin und Her (Spielbefund vom 18.11.2026, „lvl route wirkt komisch“; Grundsatz des Nutzers vom 16.11.2026:
    „roter faden … keine unnötigen wege“). Die Bewertung nach EP je Ankunftszeit zieht Abgaben so weit nach vorn, dass
    die Route zwischen einem Zielgebiet und anderen Orten pendeln kann. Verlässt sie eine Gegend (Station i, die nächste
    liegt weiter als LR.AREA Yards weg) und kommt später dorthin zurück (Station j), wird der spätere Besuch vorgezogen
    (j direkt nach i) oder der frühere nach hinten gelegt (i direkt vor j) – nur, wenn der Vorrang bleibt (Ziele vor ihrer
    Abgabe), die Route dadurch mindestens LR.FLOW_GAIN Sekunden kürzer wird und keine Quest zusätzlich grau würde. Ein
    nötiger Rückweg (etwas holen, dann dort abgeben) bleibt so stehen. Die Abgabe einer Quest mit Zeitlimit kommt dabei
    nie später an als vorher: die Bewertung zieht sie mit LR.TIMED_BONUS bewusst nach vorn, und eine kürzere Route
    rechtfertigt kein abgelaufenes Zeitlimit (Fund der Gegenprüfung vom 18.11.2026). Je Versuch zuerst nur die Zeit
    (LR.Cost, ohne neue Tabellen), der volle Gang erst für einen Versuch, der genug kürzer ist. tick (freiwillig): je
    Versuch, mit seinem Aufwand → Zahl der Verschiebungen
]]

-- Ankunft je Abgabe einer Quest mit Zeitlimit: [Station] = Sekunden (aus einem vollen Gang)
local function TimedArrivals(stations, order, walk)
    local out = {}
    for pos = 2, #order do
        local s = stations[order[pos]]
        if s.kind == "turnin" and s.quest and s.quest.timed then out[order[pos]] = walk.times[pos] end
    end
    return out
end

-- Kommt in der Reihenfolge cand (voller Gang w) eine Abgabe mit Zeitlimit später an als in before?
local function TimedLater(cand, w, before)
    for pos = 2, #cand do
        local t0 = before[cand[pos]]
        if t0 and (w.times[pos] or 0) > t0 + 1e-9 then return true end
    end
    return false
end

--[[
    Zurückgestellte Quests beim Kürzen (LR.Smooth, LR.Uncross; Spieltest vom 20.11.2026, Funde 3 und 4 des
    code-reviewers): HeldState(order) → { counts = { [questID] = Stationen nicht zurückgestellter Quests vor ihrer ersten
    Station }, bad = der erste Quest-Schritt darf nicht zuerst kommen (LR.Held: first), obwohl eine andere Quest zuerst
    dürfte, cost = Bewertung }. HeldWorse(cand, w, before) sperrt einen kürzeren Weg, wenn er eine solche Quest an den
    Anfang bringt, oder wenn er eine zurückgestellte Quest vor passende holt und die Bewertung (die den Stufenabstand
    kennt, LR.Weight) dabei steigt. Ein Kürzen, das die Bewertung nicht verschlechtert, bleibt erlaubt – sonst blieben
    Kreuzungen und Hin und Her an jeder zurückgestellten Quest stehen.
]]
local function HeldState(stations, order, ctx, cost)
    local counts, easy, firstQ, anyMay = {}, 0, nil, false
    for pos = 2, #order do
        local q = stations[order[pos]].quest
        if q then
            local h = LR.Held(q, ctx)
            if firstQ == nil then firstQ = h end
            if not h.first then anyMay = true end
            if not h.later then
                easy = easy + 1
            elseif counts[q.id] == nil then
                counts[q.id] = easy
            end
        end
    end
    return { counts = counts, bad = firstQ ~= nil and firstQ.first and anyMay, cost = cost }
end

local function HeldWorse(stations, cand, ctx, before, candCost)
    local now = HeldState(stations, cand, ctx, candCost)
    if now.bad and not before.bad then return true end
    for id, n in pairs(now.counts) do
        if before.counts[id] and n < before.counts[id] then
            return candCost > before.cost + 1e-9 * math.max(1, math.abs(before.cost))
        end
    end
    return false
end

function LR.Smooth(stations, order, dist, ctx, after, tick)
    local moved, rounds = 0, 0
    local walk = LR.Walk(stations, order, dist, ctx)
    local grey = Greys(walk)
    local timed = TimedArrivals(stations, order, walk)
    local held = HeldState(stations, order, ctx, walk.cost)
    local changed = true
    while changed and rounds < LR.SMOOTH_ROUNDS do
        changed, rounds = false, rounds + 1
        for i = 2, #order - 2 do
            local si = stations[order[i]]
            if dist(si, stations[order[i + 1]]) > LR.AREA then
                for j = i + 2, #order do
                    if dist(si, stations[order[j]]) <= LR.AREA then
                        for which = 1, 2 do
                            local cand = which == 1 and Moved(order, j, i + 1) or Moved(order, i, j - 1)
                            if tick then tick(3 * #cand) end     -- Kopie, Vorrang, Zeit
                            if Valid(cand, after) then
                                local _, total = LR.Cost(stations, cand, dist, ctx)
                                if total <= walk.total - LR.FLOW_GAIN then
                                    local w = LR.Walk(stations, cand, dist, ctx)
                                    if Greys(w) <= grey and not TimedLater(cand, w, timed)
                                        and not HeldWorse(stations, cand, ctx, held, w.cost) then
                                        for k, v in ipairs(cand) do order[k] = v end
                                        walk, grey, moved, changed = w, Greys(w), moved + 1, true
                                        timed = TimedArrivals(stations, order, w)
                                        held = HeldState(stations, order, ctx, w.cost)
                                        break
                                    end
                                end
                            end
                        end
                    end
                    if changed then break end
                end
            end
            if changed then break end
        end
    end
    return moved
end

--[[
    Keine überkreuzten Strecken (Spielbefund vom 19.11.2026, Bilder 35–37: „ist die route wirklich optimiert?“). Die
    Bewertung nach EP je Ankunftszeit lässt Kreuzungen stehen, wenn das Umdrehen eines Stücks eine Abgabe mit viel EP
    etwas später brächte – auf der Karte sieht das wie ein Umweg aus. Kreuzen sich zwei Strecken (Lage in Weltkoordinaten,
    echter Schnitt, nicht nur Berührung), dreht LR.Uncross das Stück dazwischen um (2-opt); genommen wird es nur, wenn
    der Vorrang hält (jedes Ziel vor seiner Abgabe), keine Quest zusätzlich grau wird und keine Quest mit Zeitlimit
    später ankommt – dieselben Bedingungen wie LR.Smooth. Ein Umdrehen kürzt den Weg immer. Höchstens
    LR.UNCROSS_ROUNDS Züge je Rechnung; tick (freiwillig) zählt den Aufwand. → Zahl der Züge
]]
LR.UNCROSS_ROUNDS = 30

local function Orient(ax, ay, bx, by, cx, cy)
    local v = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
    if v > 1e-9 then return 1 elseif v < -1e-9 then return -1 end
    return 0
end

-- Schneiden sich die Strecken a–b und c–d echt (in Weltkoordinaten, gleicher Kontinent)? → true | false
function LR.Crosses(a, b, c, d)
    for _, p in ipairs({ a, b, c, d }) do
        if type(p) ~= "table" or type(p.wx) ~= "number" or type(p.wy) ~= "number" or p.continent == nil
            or p.continent ~= a.continent then return false end
    end
    local o1, o2 = Orient(a.wx, a.wy, b.wx, b.wy, c.wx, c.wy), Orient(a.wx, a.wy, b.wx, b.wy, d.wx, d.wy)
    local o3, o4 = Orient(c.wx, c.wy, d.wx, d.wy, a.wx, a.wy), Orient(c.wx, c.wy, d.wx, d.wy, b.wx, b.wy)
    return o1 ~= 0 and o2 ~= 0 and o3 ~= 0 and o4 ~= 0 and o1 ~= o2 and o3 ~= o4
end

-- Zahl der Kreuzungen einer Reihenfolge (für die Prüfungen)
function LR.Crossings(stations, order)
    local n = 0
    for i = 1, #order - 1 do
        for j = i + 2, #order - 1 do
            if LR.Crosses(stations[order[i]], stations[order[i + 1]], stations[order[j]], stations[order[j + 1]]) then
                n = n + 1
            end
        end
    end
    return n
end

function LR.Uncross(stations, order, dist, ctx, after, tick)
    local moved = 0
    local walk = LR.Walk(stations, order, dist, ctx)
    local grey = Greys(walk)
    local timed = TimedArrivals(stations, order, walk)
    local held = HeldState(stations, order, ctx, walk.cost)
    local tried = {}            -- [Strecken-Paar] = true: ging nicht (Vorrang, grau, Zeitlimit); gilt bis zum nächsten Zug
    local changed = true
    while changed and moved < LR.UNCROSS_ROUNDS do
        changed = false
        for i = 1, #order - 3 do
            for j = i + 2, #order - 1 do
                if tick then tick(1) end
                local key = order[i] .. ":" .. order[i + 1] .. ":" .. order[j] .. ":" .. order[j + 1]
                if not tried[key] and LR.Crosses(stations[order[i]], stations[order[i + 1]], stations[order[j]],
                    stations[order[j + 1]]) then
                    local cand = {}
                    for k, v in ipairs(order) do cand[k] = v end
                    local lo, hi = i + 1, j
                    while lo < hi do
                        cand[lo], cand[hi] = cand[hi], cand[lo]
                        lo, hi = lo + 1, hi - 1
                    end
                    if tick then tick(3 * #cand) end     -- Kopie, Vorrang, Zeit
                    local ok = Valid(cand, after)
                    local w = ok and LR.Walk(stations, cand, dist, ctx) or nil
                    if w and Greys(w) <= grey and not TimedLater(cand, w, timed)
                        and not HeldWorse(stations, cand, ctx, held, w.cost) then
                        for k, v in ipairs(cand) do order[k] = v end
                        walk, grey, moved, changed = w, Greys(w), moved + 1, true
                        timed = TimedArrivals(stations, order, w)
                        held = HeldState(stations, order, ctx, w.cost)
                        tried = {}      -- die Reihenfolge rundherum ist neu: gescheiterte Paare dürfen wieder
                        break
                    end
                    tried[key] = true
                end
            end
            if changed then break end
        end
    end
    return moved
end

--[[
    Allein nicht zuerst (Spieltest vom 20.11.2026): steht am Anfang der Route eine Quest, die nicht zuerst kommen soll
    (LR.Held: first – orange, rot, Elite, Gruppe, Dungeon ohne Gruppe), und gibt es eine andere, die zuerst kommen darf,
    kommt die Quest mit allen Stationen als Block an die günstigste Stelle hinter der ersten Station einer solchen Quest
    (Bewertung LR.Cost; der Vorrang bleibt, weil der Block alle Stationen der Quest in ihrer Folge enthält). Gilt auch
    für Händler- und Sammel-Schritte dazwischen (LR.Insert). only (freiwillig): nur diese Quest – beim Einfügen einer neu
    angenommenen Quest bleibt eine schon geplante, zu der du vielleicht gerade läufst, wo sie ist (Fund 2 des
    code-reviewers vom 20.11.2026). tick (freiwillig): je Bewertung → Zahl der Verschiebungen
]]
function LR.HoldBack(stations, order, dist, ctx, tick, only)
    local moved = 0
    local function FirstQuest(pred)
        for pos = 2, #order do
            local q = stations[order[pos]].quest
            if q and pred(q) then return pos, q end
        end
        return nil
    end
    local function Any() return true end
    local function May(q) return not LR.Held(q, ctx).first end
    for _ = 1, #order do
        local _, q = FirstQuest(Any)
        if not q or May(q) or (only and q.id ~= only) or not FirstQuest(May) then break end
        local block = TakeBlock(stations, order, q.id)
        PutBlock(order, block, (BestSpot(stations, order, block, dist, ctx, FirstQuest(May) + 1, false, tick)))
        moved = moved + 1
    end
    return moved
end

local function RemoveQuest(order, stations, questID)
    for pos = #order, 2, -1 do
        local s = stations[order[pos]]
        if s.quest and s.quest.id == questID then table.remove(order, pos) end
    end
end

-- „wird grau“ und „lohnt nicht“: Quests mit Grund aus der Reihenfolge nehmen (der Vorrang bleibt gültig); tick
-- (freiwillig): je Bewertung
function LR.Prune(stations, order, dist, ctx, outside, tick)
    local walk = LR.Walk(stations, order, dist, ctx)
    for questID, level in pairs(walk.grey) do
        for _, s in ipairs(stations) do
            if s.quest and s.quest.id == questID and s.kind == "turnin" then
                outside[#outside + 1] = { quest = s.quest, reason = "grey", level = level, rangeSrc = ctx.rangeSrc }
                break
            end
        end
        RemoveQuest(order, stations, questID)
    end
    walk = LR.Walk(stations, order, dist, ctx)
    if walk.total <= 0 or walk.xp <= 0 then return walk end
    local rate = walk.xp / walk.total
    local remove = {}
    for pos = 2, #order do
        local s = stations[order[pos]]
        if s.kind == "turnin" and s.quest.xpSrc ~= "none" then      -- ohne EP-Angabe kein Urteil „lohnt nicht“
            local without = {}
            for _, idx in ipairs(order) do
                local o = stations[idx]
                if not (o.quest and o.quest.id == s.quest.id) then without[#without + 1] = idx end
            end
            local extra = walk.total - select(2, LR.Cost(stations, without, dist, ctx))
            if tick then tick(#without) end
            if extra > 0 and (s.xp or 0) / extra < LR.WORTH * rate then
                remove[#remove + 1] = { quest = s.quest, extra = extra }
            end
        end
    end
    for _, e in ipairs(remove) do
        outside[#outside + 1] = { quest = e.quest, reason = "worth", extra = e.extra }
        RemoveQuest(order, stations, e.quest.id)
    end
    return LR.Walk(stations, order, dist, ctx)
end

---------------------------------------------------------------------------
-- Händlerhalt und Sammel-Abstecher
---------------------------------------------------------------------------

-- Braucht es einen Halt? → "bags" | "repair" | nil, freie Plätze, schlechteste Haltbarkeit (0–1)
function LR.VendorNeed()
    if not ns.Enabled("routeVendor") then return nil end
    local free, total = Core.BagSpace()
    free, total = Num(free), Num(total)
    local D = Core.Durability
    local low = D and type(D.Summary) == "function" and Num(D.Summary().low) or nil
    if low and low < LR.REPAIR_LOW then return "repair", free, low end
    local limit = Num(ns.S and ns.S.routeVendorFree) or 4
    if free and total and total > 0 and free <= limit then return "bags", free, low end
    return nil, free, low
end

-- Gesammelte Händler (bzw. Reparierer) mit Weltlage
function LR.Vendors(repair)
    local N = Core.Npcs
    if not (N and type(N.List) == "function") then return {} end
    local out = {}
    for _, e in ipairs(N.List({ kind = "vendor", located = true, fits = true, repair = repair or nil })) do
        local v = { kind = "vendor", map = e.map, x = e.x, y = e.y, name = e.name, repair = e.repair, src = "own",
            work = LR.VENDOR_TIME }
        if World(v) then out[#out + 1] = v end
    end
    return out
end

-- Halt vor der nächsten Ziel-Station einfügen (kleinster Umweg innerhalb routeDetour) → true, Händler, Umweg | false,
-- nächster Händler oder nil (keiner auf diesem Kontinent bzw. keiner bekannt), Umweg, Bedarf ("bags" | "repair": dann
-- gilt ein Hinweis, LR.VendorHint), Zahl der bekannten Händler überhaupt (auch auf anderen Kontinenten).
-- steps beginnt mit dem nächsten Schritt; from ist der Ort des Spielers.
function LR.AddVendor(steps, from, detourMax)
    local need = LR.VendorNeed()
    if not need then return false end
    for _, s in ipairs(steps) do if s.kind == "vendor" then return false end end   -- schon ein Halt: kein Hinweis
    local dist = R().WorldDistance
    local stop = #steps + 1
    for i, s in ipairs(steps) do
        if s.kind == "obj" then stop = i break end
    end
    local best, bestAt, bestD
    local known = LR.Vendors(need == "repair")
    for _, v in ipairs(known) do
        for at = 1, stop do
            local prev = at == 1 and from or steps[at - 1]
            local nxt = steps[at]
            local d = dist(prev, v) + (nxt and (dist(v, nxt) - dist(prev, nxt)) or 0)
            if d < math.huge and (not bestD or d < bestD) then best, bestAt, bestD = v, at, d end
        end
    end
    if best and bestD <= detourMax then
        best.need = need
        table.insert(steps, bestAt, best)
        return true, best, bestD
    end
    return false, best, bestD, need, #known
end

-- Hinweis statt eines Halts: der nächste Händler liegt zu weit weg, es ist noch keiner bekannt (Fund der Gegenprüfung
-- vom 17.11.2026: vorher blieb die Route dann stumm) oder nur auf anderen Kontinenten (known > 0; Fund 9 des
-- code-reviewers vor dem Merge: vorher hieß das fälschlich „noch kein Händler bekannt“) → Hinweis oder nil
function LR.VendorHint(vendor, detour, need, known)
    if not need then return nil end
    if not vendor and (Num(known) or 0) > 0 then return { need = need, elsewhere = true } end
    if not vendor then return { need = need, unknown = true } end
    return { name = vendor.name, yards = detour, need = need }
end

-- Sammelberufe des Charakters mit Rang samt Bonus → { { kind = "herb" | "ore", rank, prof } … } (Antwort 5: Haken und
-- Abstecher nur mit Beruf)
function LR.GatherKinds()
    local G = Core.Gathering
    local out = {}
    if not (G and type(G.OwnRank) == "function") then return out end
    for _, kind in ipairs({ "herb", "ore" }) do
        local rank = Num(G.OwnRank(kind, true))
        if rank then out[#out + 1] = { kind = kind, rank = rank, prof = G.PROFESSION_KEYS and G.PROFESSION_KEYS[kind] } end
    end
    return out
end

function LR.HasGather() return #LR.GatherKinds() > 0 end

-- Sammel-Abstecher zwischen zwei Schritten (je Abschnitt höchstens einer, insgesamt LR.GATHER_MAX) → Zahl
function LR.AddGather(steps, from, zone, detourMax)
    if not ns.Enabled("routeGather") then return 0 end
    local G = Core.Gathering
    local kinds = LR.GatherKinds()
    if #kinds == 0 or not (G and type(G.Nodes) == "function") then return 0 end
    local nodes = {}
    for _, k in ipairs(kinds) do
        for _, node in ipairs(G.Nodes(zone, { kind = k.kind, skill = k.rank }) or {}) do
            if (Num(node.cnt) or 0) >= LR.GATHER_MIN_CNT then
                local n = { kind = "gather", gather = k.kind, prof = k.prof, map = zone, x = node.x, y = node.y,
                    id = node.id, cnt = node.cnt, src = "own", work = LR.GATHER_TIME }
                -- Name des Objekts, wie ezCore ihn bei dir gemerkt hat (Core.DB.Text wie ezMaps Sammel-Fundorte);
                -- vorher fragte ezQuest ein Core.Discovery.ObjectName, das es nicht gibt (Fund der Gegenprüfung)
                local DB = Core.DB
                n.name = DB and type(DB.Text) == "function" and Plain((DB.Text("obj", node.id))) or nil
                if World(n) then nodes[#nodes + 1] = n end
            end
        end
    end
    if #nodes == 0 then return 0 end
    local dist = R().WorldDistance
    local inserts, used = {}, {}
    for at = 1, #steps do
        local prev, nxt = at == 1 and from or steps[at - 1], steps[at]
        if nxt.kind ~= "gather" and prev.kind ~= "gather" then
            local best, bestD
            for i, n in ipairs(nodes) do
                if not used[i] then
                    local d = dist(prev, n) + dist(n, nxt) - dist(prev, nxt)
                    if d < math.huge and d <= detourMax and (not bestD or d < bestD) then best, bestD = i, d end
                end
            end
            if best then
                used[best] = true
                inserts[#inserts + 1] = { at = at, node = nodes[best], detour = bestD }
            end
        end
    end
    table.sort(inserts, function(a, b) return a.detour < b.detour end)
    local chosen = {}
    for i = 1, math.min(#inserts, LR.GATHER_MAX) do chosen[#chosen + 1] = inserts[i] end
    table.sort(chosen, function(a, b) return a.at > b.at end)
    for _, e in ipairs(chosen) do
        e.node.detour = e.detour
        table.insert(steps, e.at, e.node)
    end
    return #chosen
end

---------------------------------------------------------------------------
-- Rechnen
---------------------------------------------------------------------------

-- Dieselbe Abgabe-Stelle? Beim selben Namen bis LR.SAME_NPC Yards; ohne Namen (Ort laut Spiel ohne Questie) nur am
-- selben Punkt (LR.SAME_SPOT) – zwei Namen ohne Angabe könnten verschiedene NPCs nebeneinander sein
local function SameStop(a, b)
    if a.name or b.name then return a.name ~= nil and a.name == b.name and R().WorldDistance(a, b) <= LR.SAME_NPC end
    return R().WorldDistance(a, b) <= LR.SAME_SPOT
end

-- Abgaben direkt hintereinander beim selben NPC werden ein Schritt – auch schon gebündelte Schritte, die nach einer
-- Änderung der Route (Einfügen, Abgabe, Überspringen) nebeneinander stehen (Fund 6 des code-reviewers vor dem Merge)
local function Bundle(steps)
    local out = {}
    for _, s in ipairs(steps) do
        if s.kind == "turnin" and not s.quests then s.quests = { s.quest } end
        local last = out[#out]
        if s.kind == "turnin" and last and last.kind == "turnin" and SameStop(last, s) then
            for _, q in ipairs(s.quests) do last.quests[#last.quests + 1] = q end
            last.xp = (last.xp or 0) + (s.xp or 0)
        else
            out[#out + 1] = s
        end
    end
    return out
end

-- Quests eines Schritts: alle einer gebündelten Abgabe, sonst die eine (Händler und Sammel-Stelle: keine)
function LR.QuestsOf(s)
    if s.quests then return s.quests end
    return s.quest and { s.quest } or {}
end

-- Zusammenfassung über die Schritte ab ctx.start: EP, Sekunden, Stufe danach, EP bekannt? (Händler und Sammel-
-- Abstecher zählen mit ihrer Zeit)
local function Totals(steps, ctx)
    local stations, order = { ctx.start }, { 1 }
    for i, s in ipairs(steps) do stations[i + 1], order[i + 1] = s, i + 1 end
    local walk = Walk(stations, order, R().WorldDistance, ctx, true)
    local known = true
    for _, s in ipairs(steps) do
        for _, q in ipairs(LR.QuestsOf(s)) do
            if q.xpSrc == "none" then known = false end
        end
    end
    return walk.xp, walk.total, walk.level, known
end

-- Schritte in anderen Zonen (Abgaben bei NPCs anderswo, Entscheidung 10) ans Ende (Entscheidung des Nutzers vom
-- 21.11.2026: „Ans Ende, als Randpfeil (Empfohlen)“ auf „klasse ezmap ignoriert nun die zonen? wtf“ – vorher konnte
-- Schritt 1 in Westfall liegen und 2 bis 7 in Elwynn). Am Ende stehen sie nach Zone beisammen, in der Folge des ersten
-- Auftretens (sonst Zickzack Westfall, Sturmwind, Westfall – auf der Karte wieder zwei Linien vom Rand), innerhalb einer
-- Zone in ihrer Folge von vorher. Bleiben, wo sie sind: Schritte ohne bekannte Zone, und die Abgabe einer Quest mit
-- Zeitlimit – sie käme sonst später an, und eine kürzere Route rechtfertigt kein abgelaufenes Zeitlimit (dieselbe Zusage
-- wie LR.Smooth und LR.Uncross; Review vom 21.11.2026). Bricht das den Vorrang (StepsValid), bleibt die Reihenfolge
-- davor. → Zahl verschobener Schritte
function LR.ZoneLast(stations, order, ctx)
    if not (ctx and ctx.zone) or #order < 3 then return 0 end
    local here, zones, byZone = { order[1] }, {}, {}
    for pos = 2, #order do
        local s = stations[order[pos]]
        local timed = false
        if s then
            for _, q in ipairs(LR.QuestsOf(s)) do if q.timed then timed = true end end
        end
        if s and s.zone and s.zone ~= ctx.zone and not timed then
            if not byZone[s.zone] then
                byZone[s.zone] = {}
                zones[#zones + 1] = s.zone
            end
            local list = byZone[s.zone]
            list[#list + 1] = order[pos]
        else
            here[#here + 1] = order[pos]
        end
    end
    if #zones == 0 then return 0 end
    local before = {}
    for k, v in ipairs(order) do before[k] = v end
    local n = 0
    for _, v in ipairs(here) do
        n = n + 1
        order[n] = v
    end
    for _, zone in ipairs(zones) do
        for _, v in ipairs(byZone[zone]) do
            n = n + 1
            order[n] = v
        end
    end
    if not StepsValid(stations, order) then
        for k = 1, #before do order[k] = before[k] end
        return 0
    end
    local moved = 0
    for k = 1, #order do if order[k] ~= before[k] then moved = moved + 1 end end
    return moved
end

-- Ergebnis aus Reihenfolge und Listen → state
local function Finish(stations, order, dist, ctx, outside, sources, tick, after)
    LR.Prune(stations, order, dist, ctx, outside, tick)
    LR.HoldBack(stations, order, dist, ctx, tick)
    LR.Smooth(stations, order, dist, ctx, after, tick)
    LR.Uncross(stations, order, dist, ctx, after, tick)
    LR.ZoneLast(stations, order, ctx)
    local steps = {}
    for pos = 2, #order do steps[#steps + 1] = stations[order[pos]] end
    steps = Bundle(steps)
    local result = { steps = steps, outside = outside, t = time(), sources = sources, ctx = ctx, following = false }
    local added, vendor, detour, need, known = LR.AddVendor(steps, ctx.start, ctx.detour)
    if not added then result.vendorHint = LR.VendorHint(vendor, detour, need, known) end
    result.gather = LR.AddGather(steps, ctx.start, ctx.zone, ctx.detour)
    result.xp, result.seconds, result.level, result.xpKnown = Totals(steps, ctx)
    table.sort(outside, function(a, b)
        local la, lb = a.quest.level or 0, b.quest.level or 0
        if la ~= lb then return la < lb end
        return a.quest.order < b.quest.order
    end)
    return result
end

-- Die Rechnung selbst (tick zählt Schritte; in Scheiben hält der Auftrag dort an)
function LR.Plan(quests, ctx, client, tick)
    local Route = R()
    local stations, after, outside, sources = LR.Stations(quests, ctx, client, tick)
    local dist = LR.DistanceTable(stations, tick)
    local opts = { dist = dist, after = after, rounds = LR.ROUNDS }
    opts.cost = function(order) return (LR.Cost(stations, order, dist, ctx)) end
    local order = Route.Nearest(stations, nil, nil, 1, tick, opts)
    if #order > 2 then
        Route.TwoOpt(stations, order, nil, nil, false, tick, opts)
        Route.Relocate(stations, order, opts, tick)
        LR.PullForward(stations, order, dist, ctx, tick)
        LR.PushBack(stations, order, dist, ctx, tick)
    end
    return Finish(stations, order, dist, ctx, outside, sources, tick, after)
end

-- Übersprungenes dieser Sitzung (LR.Skip): Quest-IDs bzw. Halte (Händler, Sammel-Stelle) samt Ort. Eine Rechnung ohne
-- Klick (auto: Öffnen der Karte nach dem Laufen, Zonenwechsel, geänderte Einstellung) lässt sie draußen, die Quest
-- steht weiter mit Grund „übersprungen“ unter „Nicht in der Route“; „Route berechnen“ per Klick und LR.Clear leeren
-- die Liste. Nur im Arbeitsspeicher.
LR.skipped, LR.skippedHalts = {}, {}

-- Übersprungene Halte aus den Schritten nehmen (nach der Rechnung; Händler und Sammel-Abstecher fügt sie neu ein) → Zahl
function LR.DropSkippedHalts(steps)
    local n = 0
    for i = #steps, 1, -1 do
        local s = steps[i]
        if s.kind == "vendor" or s.kind == "gather" then
            for _, h in ipairs(LR.skippedHalts) do
                if h.kind == s.kind and LR.SamePlace(h, s) then
                    table.remove(steps, i)
                    n = n + 1
                    break
                end
            end
        end
    end
    return n
end

-- Route berechnen (verbose: Ergebnis im Chat; auto: ohne Klick – eine Rechnung in Scheiben hält dann im Kampf an) →
-- true | false, Grund ("off", "position", "noQuestLog", "nocore", "running"). Die Route merkt sich Zeitpunkt (at,
-- Core.Now), Art (auto) und Rechenzeit (ms, debugprofilestop; bei Scheiben die Summe der Scheiben) – nur im
-- Arbeitsspeicher, für die Zeile „… berechnet“ im Menü und /ezq status.
function LR.Compute(verbose, auto)
    if not ns.Enabled("levelRoute") then return false, "off" end
    if verbose then LR.autoHeld = false end     -- der Klick holt das automatische Rechnen nach „Route verwerfen“ zurück
    -- ohne Klick keine Arbeit im Kampf, auch nicht auf dem sofortigen Weg (Neurechnen nach einem Abbruch bzw. einer
    -- geänderten Einstellung; Fund der Gegenprüfung vom 18.11.2026): nach dem Kampf nachholen, nur der letzte Wunsch
    if auto and Core.InCombat() then
        ns.AfterCombat(function() ns.Try("LevelRouteRecalc", LR.AfterFight) end, "levelRouteRecalc")
        return false, "combat"
    end
    local Route = R()
    if not (Route and type(Route.Relocate) == "function" and type(Route.WorldDistance) == "function") then
        if verbose then ns.Print(L.ROUTE_NOCORE) end
        return false, "nocore"
    end
    local ctx, why = LR.Context()
    if not ctx then
        if verbose then ns.Print(L.ROUTE_NO_POSITION) end
        return false, why
    end
    local quests, err = LR.ReadLog()
    if not quests then return false, err end
    if verbose then LR.skipped, LR.skippedHalts = {}, {} end     -- per Klick: Übersprungenes wieder hinein
    local held = {}
    if auto and next(LR.skipped) then
        local kept = {}
        for _, q in ipairs(quests) do
            if LR.skipped[q.id] then held[#held + 1] = { quest = q, reason = "skipped" } else kept[#kept + 1] = q end
        end
        quests = kept
    end
    local clock = rawget(_G, "debugprofilestop")
    local spentMs = 0
    local function Measure(t0) if t0 then spentMs = spentMs + math.max(0, clock() - t0) end end
    local t0 = type(clock) == "function" and clock() or nil
    local client = LR.ClientPlaces(ctx.zone)
    LR.Cancel()
    LR.zoneDirty = false        -- diese Rechnung liest deine jetzige Zone (ctx); ein Wechsel danach merkt LR.OnNewPlace
    local function Done(result, pending)
        local following = state and state.following
        local marked, chosen = state and state.marked, state and state.chosen
        state = result
        state.following = following or false
        state.at, state.auto, state.ms = Core.Now(), auto and true or false, t0 and spentMs or nil
        state.slices = pending and pending.steps or 0
        for _, e in ipairs(held) do state.outside[#state.outside + 1] = e end
        if auto and #LR.skippedHalts > 0 then LR.DropSkippedHalts(state.steps) end
        -- Fund des 2. Reviews der Leveling-Route (17.11.2026): Markierung und ein per Klick gewählter Schritt gehören
        -- einem Schritt der alten Route – ein Schritt der neuen am selben Ort übernimmt beide (LR.SamePlace); sonst
        -- rückte LR.Follow die Markierung nach dem Neurechnen auf Schritt 1, und der gewählte Schritt ginge verloren
        if marked then
            for _, s in ipairs(state.steps) do
                if LR.SamePlace(s, marked) then
                    state.marked, state.chosen = s, chosen
                    break
                end
            end
        end
        -- Rechnung in Scheiben: was sich seit dem Lesen des Questlogs getan hat, nachholen – abgegebene bzw. abgebrochene
        -- Quests heraus, neu angenommene einfügen, erfüllte Teilziele weg (Fund 7 des code-reviewers vor dem Merge;
        -- vorher landete eine neue Quest in der alten Route, und das Ergebnis ersetzte sie). Eingefügt wird nur, was
        -- noch im Questlog steht: sonst entstünde aus den Orten laut Questie ein Schritt für eine Quest, die schon wieder
        -- weg ist, und nichts nähme ihn heraus (Fund der Gegenprüfung vom 17.11.2026). Ohne Auskunft des Clients
        -- entscheidet JobDrop; so fällt auch ein Abbruch heraus, dessen QUEST_REMOVED erst nach der Rechnung entschieden
        -- würde (LR.REMOVED_WAIT).
        if pending then
            for _, id in ipairs(pending.drop) do LR.DropQuest(id) end
            for _, id in ipairs(pending.add) do
                if not (ns.QuestId and ns.QuestId.InLog(id) == false) then LR.Insert(id, true) end
            end
            LR.OnLogUpdate(true)
        end
        LR.Changed()
        if verbose then ns.Print(LR.Summary()) end
        if auto and #state.steps == 0 then LR.EmptyRetry() end
        -- Zonenwechsel während der Rechnung in Scheiben (LR.OnNewPlace hat ihn nur gemerkt): die Route gilt für die Zone
        -- beim Start; bist du jetzt woanders, einmal neu (Fund der Gegenprüfung vom 18.11.2026)
        if LR.zoneDirty then
            LR.zoneDirty = false
            if LR.AutoWanted() and LR.ZoneMoved() then LR.AutoSchedule(nil, true) end
        end
    end
    -- kleine Mengen sofort (das offene Menü zeigt das Ergebnis gleich), große in Scheiben; gezählt werden die Stationen
    -- höchstens (Abgabe und offene Teilziele je Quest), nicht die Quests samt erfüllter Ziele (Fund 4)
    local open = 0
    for _, q in ipairs(quests) do
        open = open + 1
        if not q.complete then
            for _, o in ipairs(q.objectives) do if not o.done then open = open + 1 end end
        end
    end
    if open <= LR.SYNC_MAX then
        local result = LR.Plan(quests, ctx, client)
        Measure(t0)
        Done(result)
        return true
    end
    Measure(t0)
    local current = { steps = 0, drop = {}, add = {}, auto = auto and true or false }
    job = current
    local spent = 0
    local co = coroutine.create(function()
        return LR.Plan(quests, ctx, client, function(n)
            spent = spent + (n or 1)
            if spent >= LR.SLICE then
                spent = 0
                current.steps = current.steps + 1
                coroutine.yield()
            end
        end)
    end)
    local function Step()
        if job ~= current then return end
        -- ohne Klick keine Arbeit im Kampf: die nächste Scheibe erst danach (ezCores Reihe, nur der letzte Wunsch)
        if current.auto and Core.InCombat() then
            ns.AfterCombat(function() C_Timer.After(0, Step) end, "levelRouteSlice")
            return
        end
        local s0 = t0 and clock() or nil
        local ok, result = coroutine.resume(co)
        Measure(s0)
        if not ok then
            job = nil
            Core.Error("ezQuest", result, "LevelRoute.Compute")
            return
        end
        if coroutine.status(co) == "dead" then
            job = nil
            Done(result, current)
            return
        end
        C_Timer.After(0, Step)
    end
    Step()
    -- „wird berechnet“ nur, wenn die erste Scheibe nicht schon gereicht hat (sonst stünde es direkt vor dem Ergebnis)
    if verbose and job == current then ns.Print(L.ROUTE_STARTED) end
    return true
end

function LR.Cancel()
    local had = job ~= nil
    job = nil
    return had
end

-- Knopf „Abbrechen“ im Menü: eine Rechnung ohne Klick abbrechen hält das automatische Rechnen an wie „Route
-- verwerfen“ – sonst startete die nächste angenommene Quest sie gleich wieder (Fund der Gegenprüfung vom 18.11.2026)
function LR.CancelClick()
    if job and job.auto then LR.autoHeld = true end
    return LR.Cancel()
end

-- Nach dem Kampf: das im Kampf aufgeschobene Neurechnen ohne Klick (LR.Compute) – nur, wenn die Route noch steht;
-- ohne Route entscheidet LR.AutoSchedule (Schalter, „Route verwerfen“)
function LR.AfterFight()
    if state then return LR.Compute(false, true) end
    return LR.AutoSchedule()
end

---------------------------------------------------------------------------
-- Ohne Klick rechnen (Wunsch des Nutzers vom 18.11.2026, Schalter routeAuto)
---------------------------------------------------------------------------

-- Rechnet ezQuest die Route gerade von selbst? Aus mit dem Haupt-Schalter, mit dem Schalter routeAuto und nach
-- „Route verwerfen“ (LR.autoHeld, bis zum nächsten Klick auf „Route berechnen“ bzw. /reload)
function LR.AutoWanted()
    return ns.Enabled("levelRoute") and ns.Enabled("routeAuto") and not LR.autoHeld
end

-- Bekommt der Charakter keine Erfahrung (Höchststufe, beim Lehrer ausgeschaltet, Stufengrenze eines Probe-Kontos;
-- Core.XPBlocked)? Dann rechnet die Route nicht von selbst – sie ordnet nach Erfahrung je Weg (Fund der Gegenprüfung
-- vom 18.11.2026). „unknown“ (Werte gesperrt bzw. noch nicht da) sperrt nicht: lieber eine Route als keine.
function LR.NoXP()
    if type(Core.XPBlocked) ~= "function" then return false end
    local blocked, why = Core.XPBlocked()
    return blocked == true and why ~= "unknown"
end

-- Eine Route ohne Klick ohne einen einzigen Schritt (alle Quests anderswo bzw. ihre Orte noch nicht bereit) gilt für
-- das automatische Rechnen als „keine Route“: sonst bliebe „Leveling-Route (0 Schritte)“ stehen und nichts rechnete
-- neu (Fund der Gegenprüfung vom 18.11.2026). Neu gerechnet wird beim Zonenwechsel, nach einem Ladebildschirm und
-- einmal je Sitzung LR.AUTO_EMPTY_RETRY Sekunden später – nicht bei jedem QUEST_LOG_UPDATE (das wäre Dauerarbeit).
function LR.EmptyAuto()
    return state ~= nil and state.auto == true and #state.steps == 0 and not job
end

function LR.EmptyRetry()
    if emptyRetried or not LR.AutoWanted() then return false end
    emptyRetried = true
    C_Timer.After(LR.AUTO_EMPTY_RETRY, function()
        if LR.EmptyAuto() then LR.AutoSchedule(0) end
    end)
    return true
end

-- Steht die Route für eine andere Zone, als du jetzt bist? (Zone beim Rechnen: state.ctx.zone; dein Ort unbekannt –
-- Instanz, Ladebildschirm –: nein, dann bleibt die Route stehen)
function LR.ZoneMoved()
    if not (state and state.ctx and state.ctx.zone) then return false end
    local map = Core.PlayerPosition()
    if not map then return false end
    return ZoneOf(map) ~= state.ctx.zone
end

-- Zonenwechsel bzw. Ladebildschirm: eine leere Route ohne Klick neu, sonst der Versuch, der am Ort scheiterte. Seit der
-- Entscheidung des Nutzers vom 18.11.2026 („ja“ auf „Soll eine schon berechnete Route beim Zonenwechsel neu rechnen?“)
-- rechnet auch eine bestehende Route neu, wenn du jetzt in einer anderen Zone bist als beim Rechnen – mit dem Schalter
-- „Route automatisch berechnen“ (routeAuto), gedrosselt wie jede Rechnung ohne Klick (LR.AUTO_BUNDLE, LR.AUTO_GAP),
-- nie im Kampf (danach über ns.AfterCombat), ohne Chat. Die Route gilt nur für ihre Zone (Entscheidung 10).
-- Läuft gerade eine Rechnung in Scheiben, merkt sich ezQuest den Wechsel und holt ihn an ihrem Ende nach (Done in
-- LR.Compute); auf einem Flug wird nicht für jede überflogene Zone gerechnet, sondern nach der Landung einmal
-- (LR.AfterTaxi; beides Funde der Gegenprüfung vom 18.11.2026).
function LR.OnNewPlace()
    if LR.OnTaxi() then
        LR.taxiWait = true
        return false
    end
    LR.taxiWait = false
    if job then LR.zoneDirty = true end
    if LR.EmptyAuto() then return LR.AutoSchedule() end
    if state and not job and LR.AutoWanted() and LR.ZoneMoved() then return LR.AutoSchedule(nil, true) end
    return LR.AutoNudge(true)
end

-- Sitzt du auf einem Flugtier (UnitOnTaxi)? Gesperrt oder unbekannt gilt als nein – lieber eine Route als keine
function LR.OnTaxi()
    local onTaxi = rawget(_G, "UnitOnTaxi")
    if type(onTaxi) ~= "function" then return false end
    local raw = onTaxi("player")
    if Core.IsSecret(raw) then return false end
    return Core.Bool(raw, false) == true
end

LR.TAXI_RETRY = 1           -- Sekunden: nach PLAYER_CONTROL_GAINED so oft nachsehen, ob der Flug vorbei ist
LR.TAXI_TRIES = 5           -- höchstens so oft (UnitOnTaxi meldet kurz nach der Landung noch „wahr“, siehe ezMap/Flights.lua)

-- Nach der Landung (PLAYER_CONTROL_GAINED): den auf dem Flug aufgeschobenen Zonenwechsel bzw. die Rechnung einmal
-- nachholen (LR.OnNewPlace) → true, wenn jetzt nachgeholt
function LR.AfterTaxi(tries)
    if not LR.taxiWait then return false end
    tries = tries or 0
    if LR.OnTaxi() then
        if tries < LR.TAXI_TRIES then
            C_Timer.After(LR.TAXI_RETRY, function() ns.Try("LevelRouteAuto", LR.AfterTaxi, tries + 1) end)
        end
        return false
    end
    LR.OnNewPlace()
    return true
end

-- Eine Rechnung ohne Klick vormerken: nur ohne Route (sonst gilt Antwort 8: weiterrücken und einfügen; Ausnahme
-- replace: Zonenwechsel, LR.OnNewPlace), gebündelt (delay, Standard LR.AUTO_BUNDLE) und frühestens LR.AUTO_GAP
-- Sekunden nach der letzten → true, wenn vorgemerkt
function LR.AutoSchedule(delay, replace)
    if autoPending or (state and not LR.EmptyAuto() and not replace) or job or not LR.AutoWanted() then return false end
    local wait = delay or LR.AUTO_BUNDLE
    local now = Num(GetTime and GetTime())
    if autoLast and now then wait = math.max(wait, autoLast + LR.AUTO_GAP - now) end
    autoPending = true
    C_Timer.After(math.max(0, wait), function()
        autoPending = false
        ns.Try("LevelRouteAuto", LR.AutoRun, replace)
    end)
    return true
end

-- Die vorgemerkte Rechnung: im Kampf erst danach, ohne Quest im Log keine (leere) Route, ohne Chat → true | false, Grund.
-- replace: eine bestehende Route ersetzen (Zonenwechsel) – nur, wenn du noch in einer anderen Zone bist als beim Rechnen
function LR.AutoRun(replace)
    if replace == "map" then
        if not (state and LR.MovedFromStart()) then replace = false end
    elseif replace and not (state and LR.ZoneMoved()) then
        replace = false
    end
    if (state and not LR.EmptyAuto() and not replace) or job or not LR.AutoWanted() then return false, "skip" end
    if LR.NoXP() then return false, "noxp" end
    -- auf einem Flug nicht für eine Durchgangszone rechnen: nach der Landung (LR.AfterTaxi, autoRetry für AutoNudge)
    if LR.OnTaxi() then
        LR.taxiWait, autoRetry = true, true
        return false, "taxi"
    end
    if Core.InCombat() then
        ns.AfterCombat(function() LR.AutoSchedule(nil, replace) end, "levelRouteAuto")
        return false, "combat"
    end
    autoLast = Num(GetTime and GetTime())
    -- ohne eigenen Ort (Instanz, Ladebildschirm) gar nicht erst das Questlog lesen: später wieder (PLAYER_ENTERING_WORLD)
    if not Core.PlayerPosition() then
        autoRetry = true
        return false, "position"
    end
    local entries = Core.QuestLogEntries()
    if not entries or #entries == 0 then
        autoRetry = true    -- Questlog noch nicht bereit bzw. leer: beim nächsten QUEST_LOG_UPDATE wieder
        return false, entries and "empty" or "noQuestLog"
    end
    local ok, why = LR.Compute(false, true)
    autoRetry = not ok and (why == "position" or why == "noQuestLog") or false
    return ok, why
end

-- Ein Ereignis ohne Route (Questlog geändert, nach einem Ladebildschirm): rechnen, wenn die letzte Rechnung ohne Klick
-- nicht ging (retryOnly) bzw. immer (eine neue Quest)
function LR.AutoNudge(retryOnly)
    if retryOnly and not autoRetry then return false end
    return LR.AutoSchedule()
end

--[[
    Beim Öffnen der Weltkarte neu rechnen (Spielbefund vom 19.11.2026, Bilder 35–37 und 42, wörtlich „aktualisiert es
    die route nicht auf der karte, nach dem ich mich bewegt habe, die aktualisierung muss beim karten öffnen erfolgen“;
    Auftrag freigegeben am 20.11.2026). Die Linie begann zwar an deinem Ort, die Reihenfolge stammte aber vom Ort beim
    Rechnen – du liefst los, und die Route führte zurück. Jetzt: stehst du beim Öffnen der Karte mehr als LR.MAP_MOVED
    Yards vom Ort der letzten Rechnung entfernt, rechnet die Route von deinem jetzigen Ort neu (wie eine Rechnung ohne
    Klick: Schalter „Route automatisch berechnen“, nie im Kampf, ohne Chat, gedrosselt mit LR.AUTO_GAP). Ohne Route
    rechnet das Öffnen wie nach dem Einloggen. Markierung und gewählter Schritt gehen auf den Schritt am selben Ort über
    (Done in LR.Compute). Hook: nur HookScript an Blizzards WorldMapFrame (LR.HookMap).
]]
LR.MAP_MOVED = 30           -- Yards vom Ort der letzten Rechnung, ab denen das Öffnen der Karte neu rechnet

-- Stehst du merklich woanders als beim Rechnen? (anderer Kontinent: ja; Ort unbekannt: nein)
function LR.MovedFromStart()
    local start = state and state.ctx and state.ctx.start
    if type(start) ~= "table" or start.wx == nil then return false end
    local map, x, y = Core.PlayerPosition()
    if not map then return false end
    local here = { map = map, x = x, y = y }
    if not World(here) then return false end
    return R().WorldDistance(start, here) >= LR.MAP_MOVED
end

-- Blizzards Weltkarte geht auf → true, wenn eine Rechnung vorgemerkt wurde
function LR.OnMapShown()
    if job or not LR.AutoWanted() then return false end
    if not state or LR.EmptyAuto() then return LR.AutoSchedule(0) end
    if LR.MovedFromStart() then return LR.AutoSchedule(0, "map") end
    return false
end

local mapHooked = false
function LR.HookMap()
    local map = rawget(_G, "WorldMapFrame")
    if mapHooked or type(map) ~= "table" or type(map.HookScript) ~= "function" then return false end
    mapHooked = true
    map:HookScript("OnShow", function() ns.Try("LevelRouteMap", LR.OnMapShown) end)
    return true
end

-- Zeile „Automatisch berechnet vor 3 Min.“ bzw. „Berechnet …“ (Menü und /ezq status) → Text oder nil ohne Route
function LR.LastText()
    if not (state and state.at) then return nil end
    local text = (state.auto and L.ROUTE_LAST_AUTO or L.ROUTE_LAST_CLICK):format(Core.Ago(state.at))
    if state.ms then text = text .. L.ROUTE_LAST_MS:format(math.floor(state.ms + 0.5)) end
    return text
end

---------------------------------------------------------------------------
-- Texte der Schritte
---------------------------------------------------------------------------

local SOURCE_TEXT = { client = "ROUTE_SRC_CLIENT", questie = "ROUTE_SRC_QUESTIE", own = "ROUTE_SRC_OWN" }

function LR.SourceText(src)
    return L[SOURCE_TEXT[src] or "ROUTE_SRC_CLIENT"]
end

local function Quests(s)
    local names = {}
    for _, q in ipairs(LR.QuestsOf(s)) do names[#names + 1] = q.title end
    return table.concat(names, ", ")
end

-- EP einer Abgabe zum Anzeigen: Summe der Quests mit EP-Angabe (laut Client oder geschätzt) → Zahl oder nil (unbekannt)
function LR.ShownXP(s)
    local sum, known = 0, false
    for _, q in ipairs(LR.QuestsOf(s)) do
        if q.xpSrc ~= "none" then sum, known = sum + (q.xp or 0), true end
    end
    return known and sum or nil
end

-- Zeile eines Schritts („1. Abgeben: Die Gnolle – Späher Thomas, 450 EP“)
function LR.StepText(s, n)
    local head = n and (n .. ". ") or ""
    if s.kind == "obj" then
        local texts = {}
        for _, o in ipairs(LR.ObjsOf(s)) do
            if not o.done and o.text then texts[#texts + 1] = o.text end
        end
        local what = #texts > 0 and table.concat(texts, ", ") or (s.obj and s.obj.text) or s.name or ""
        return head .. L.ROUTE_STEP_OBJ:format(s.quest.title, what)
    elseif s.kind == "turnin" then
        local who = s.name and (" – " .. s.name) or ""
        local xp = LR.ShownXP(s)
        if not xp then return head .. L.ROUTE_STEP_TURNIN_NOXP:format(Quests(s), who) end
        return head .. L.ROUTE_STEP_TURNIN:format(Quests(s), who, Core.FormatNumber(xp))
    elseif s.kind == "vendor" then
        return head .. L.ROUTE_STEP_VENDOR:format(s.name or "?")
    elseif s.kind == "gather" then
        local G = Core.Gathering
        local prof = G and type(G.SkillName) == "function" and G.SkillName(s.gather) or nil
        prof = type(prof) == "string" and prof or L["ROUTE_KIND_" .. (s.gather == "ore" and "ORE" or "HERB")]
        if s.name then return head .. L.ROUTE_STEP_GATHER:format(s.name, prof) end
        return head .. L.ROUTE_STEP_GATHER_PLACE:format(prof)
    end
    return head .. "?"
end

-- Warum ein Schritt an seiner Stelle steht (Auftrag aus dem Spieltest vom 20.11.2026: „Erklärbar“)
local COLOR_TEXT = { impossible = "ROUTE_COLOR_RED", verydifficult = "ROUTE_COLOR_ORANGE", difficult = "ROUTE_COLOR_YELLOW",
    standard = "ROUTE_COLOR_GREEN", trivial = "ROUTE_COLOR_GREY" }

-- „orange laut Spiel“ bzw. „orange, geschätzt nach Blizzards Farbgrenzen“
function LR.ColorText(key, src)
    local name = L[COLOR_TEXT[key] or "ROUTE_COLOR_YELLOW"]
    return name .. (src == "client" and L.ROUTE_COLOR_CLIENT or L.ROUTE_COLOR_GUESS)
end

-- Zeilen zu Stufe, Elite, Gruppe einer Quest bei deiner Stufe → Liste
function LR.LevelLines(q, ctx)
    local h, out = LR.Held(q, ctx), {}
    if h.high and q.timed then
        out[#out + 1] = L.ROUTE_HERE_HIGH_NOTE:format(q.level, q.level - ctx.level, LR.ColorText(h.key, h.src))
    elseif h.high then
        out[#out + 1] = L.ROUTE_HERE_HIGH:format(q.level, q.level - ctx.level, LR.ColorText(h.key, h.src))
    elseif h.grey then
        out[#out + 1] = L.ROUTE_HERE_GREY:format(q.level or "?", LR.ColorText(h.key, h.src))
    elseif h.key then
        out[#out + 1] = L.ROUTE_HERE_FIT:format(q.level, LR.ColorText(h.key, h.src))
    end
    if h.elite then out[#out + 1] = L.ROUTE_HERE_ELITE end
    if h.group then out[#out + 1] = L.ROUTE_HERE_GROUP:format(q.groupSize or "?") end
    if h.dungeon then out[#out + 1] = L.ROUTE_HERE_DUNGEON end
    return out
end

-- Kurzer Grund, warum eine Quest später kommt („Stufe 25, orange laut Spiel“) oder nil
function LR.LaterText(q, ctx)
    local h = LR.Held(q, ctx)
    if not h.later then return nil end
    if h.high then return L.ROUTE_HERE_SHORT_HIGH:format(q.level, LR.ColorText(h.key, h.src)) end
    if h.elite then return L.ROUTE_HERE_SHORT_ELITE end
    if h.group then return L.ROUTE_HERE_SHORT_GROUP end
    if h.dungeon then return L.ROUTE_HERE_SHORT_DUNGEON end
    if h.grey then return L.ROUTE_HERE_SHORT_GREY end
    return nil
end

-- Ist Schritt k (die Route ab Schritt n) jetzt dran? Eine Abgabe erst, wenn kein Ziel ihrer Quest davor offen steht.
local function OpenAt(steps, n, k)
    local t = steps[k]
    if t.kind ~= "turnin" then return true end
    for j = n, k - 1 do
        local o = steps[j]
        if o.kind == "obj" and HasQuest(t, o.quest.id) then return false end
    end
    return true
end

local function Yards(d) return math.floor(d + 0.5) end

-- Zeilen „Warum an dieser Stelle“ für einen Quest-Schritt der aktuellen Route (leer für Händler, Sammel-Stellen und
-- Schritte außerhalb der Route): Abstand zum vorigen Punkt (beim ersten: zu dir), ob ein offener Punkt näher läge und
-- warum der später kommt, Stufe und Farbe laut Client, Elite/Gruppe allein, Zeitlimit. Stufe und „allein“ gelten wie
-- zur Zeit der Rechnung (state.ctx) – so erklärt der Tooltip, was die Route entschieden hat; nach einem Stufenaufstieg
-- oder Gruppenwechsel rechnet „Route berechnen“ neu (Hinweis des code-reviewers vom 20.11.2026)
function LR.WhyHere(s)
    local lines = {}
    local ctx = state and state.ctx
    if not (ctx and (s.kind == "obj" or s.kind == "turnin")) then return lines end
    local steps, n = state.steps, nil
    for i, t in ipairs(steps) do
        if t == s then n = i break end
    end
    if not n then return lines end
    local prev = steps[n - 1]
    if not prev then
        local map, x, y = Core.PlayerPosition()
        local here = map and { map = map, x = x, y = y } or nil
        prev = here and World(here) and here or ctx.start
    end
    local dist = R().WorldDistance
    lines[#lines + 1] = L.ROUTE_HERE_HEAD
    local d = dist(prev, s)
    local nearK, nearD
    for k = n, #steps do
        local t = steps[k]
        if (t.kind == "obj" or t.kind == "turnin") and OpenAt(steps, n, k) then
            local dk = dist(prev, t)
            if dk < math.huge and (not nearD or dk < nearD - 1e-6) then nearK, nearD = k, dk end
        end
    end
    if d < math.huge then
        if not nearK or nearK == n or nearD >= d - 1e-6 then
            lines[#lines + 1] = L.ROUTE_HERE_NEAREST:format(Yards(d))
        else
            local later = LR.LaterText(steps[nearK].quest, ctx)
            local why = later and L.ROUTE_HERE_LATER:format(later) or L.ROUTE_HERE_ORDER
            lines[#lines + 1] = L.ROUTE_HERE_NEARER:format(nearK, Yards(nearD), Yards(d), why)
        end
    end
    local qs = LR.QuestsOf(s)
    for _, q in ipairs(qs) do
        for _, line in ipairs(LR.LevelLines(q, ctx)) do
            lines[#lines + 1] = #qs > 1 and (q.title .. ": " .. line) or line
        end
        if q.timed then lines[#lines + 1] = L.ROUTE_HERE_TIMED end
    end
    return lines
end

-- Tooltip eines Schritts: Zeilen
function LR.StepTip(s)
    local lines = {}
    if s.kind == "obj" or s.kind == "turnin" then
        local q = s.quest
        lines[#lines + 1] = L.ROUTE_TIP_QUEST:format(Quests(s), q.level or "?")
        if s.kind == "turnin" then
            local xp = LR.ShownXP(s)
            if xp then
                local src = q.xpSrc == "client" and L.ROUTE_XP_CLIENT or L.ROUTE_XP_MEAN
                lines[#lines + 1] = L.ROUTE_TIP_XP:format(Core.FormatNumber(xp), src)
            else
                lines[#lines + 1] = L.ROUTE_TIP_XP_NONE
            end
            -- Ort laut Spiel, Name des NPC laut Questie: beide Quellen nennen (Leitlinie 11)
            if s.name and s.nameSrc == "questie" then lines[#lines + 1] = L.ROUTE_TIP_NAME_QUESTIE:format(s.name) end
            if s.next then lines[#lines + 1] = L.ROUTE_TIP_NEXT end
        else
            for _, o in ipairs(LR.ObjsOf(s)) do
                if o.need and not o.done then lines[#lines + 1] = L.ROUTE_TIP_PROGRESS:format(o.have or 0, o.need) end
            end
            if (s.groups or 1) > 1 then lines[#lines + 1] = L.ROUTE_TIP_GROUPS:format(s.groups - 1) end
        end
    elseif s.kind == "vendor" then
        if s.need == "repair" then
            lines[#lines + 1] = L.ROUTE_TIP_REPAIR:format(Core.Percent(LR.REPAIR_LOW * 100))
        else
            lines[#lines + 1] = L.ROUTE_TIP_BAGS:format(Num(ns.S and ns.S.routeVendorFree) or 4)
        end
    elseif s.kind == "gather" then
        lines[#lines + 1] = L.ROUTE_TIP_GATHER:format(Num(s.cnt) or 0, math.floor((s.detour or 0) + 0.5))
    end
    for _, line in ipairs(LR.WhyHere(s)) do lines[#lines + 1] = line end
    lines[#lines + 1] = L.ROUTE_TIP_PLACE:format(Core.MapName and Core.MapName(s.map) or tostring(s.map),
        Core.Decimal((s.x or 0) * 100, 1), Core.Decimal((s.y or 0) * 100, 1))
    return table.concat(lines, "\n"), LR.SourceText(s.src)
end

local REASONS = { elite = "ROUTE_WHY_ELITE", dungeon = "ROUTE_WHY_DUNGEON", high = "ROUTE_WHY_HIGH",
    zone = "ROUTE_WHY_ZONE", continent = "ROUTE_WHY_CONTINENT", noplace = "ROUTE_WHY_NOPLACE",
    noturnin = "ROUTE_WHY_NOTURNIN", capped = "ROUTE_WHY_CAPPED", grey = "ROUTE_WHY_GREY", worth = "ROUTE_WHY_WORTH",
    skipped = "ROUTE_WHY_SKIPPED" }

-- „Die Gnolle [12]: andere Zone“
function LR.OutsideText(e)
    local why = L[REASONS[e.reason] or "ROUTE_WHY_NOPLACE"]
    if e.reason == "grey" then
        why = why:format(e.level or "?")
        -- Leitlinie 11: ohne Antwort des Clients ist die Grenze „grau“ geschätzt (LR.TRIVIAL_FALLBACK)
        if e.rangeSrc == "estimate" then why = why .. L.ROUTE_GREY_GUESS end
    elseif e.reason == "worth" then
        why = why:format(Core.Minutes(math.max(1, math.floor((e.extra or 0) / 60 + 0.5))), Core.FormatNumber(e.quest.xp or 0))
    end
    return ("%s [%s]: %s"):format(e.quest.title, e.quest.level or "?", why)
end

-- „Leveling-Route: 12 Schritte, ~25 Min., ~4.300 EP“
function LR.Summary()
    if not state then return L.ROUTE_NONE_YET end
    local minutes = math.max(1, math.floor((state.seconds or 0) / 60 + 0.5))
    local steps = Core.Plural(#state.steps, L.ROUTE_STEPS_ONE, L.ROUTE_STEPS_MANY)
    if state.xpKnown == false then return L.ROUTE_SUMMARY_NOXP:format(steps, Core.Minutes(minutes)) end
    return L.ROUTE_SUMMARY:format(steps, Core.Minutes(minutes), Core.FormatNumber(state.xp or 0))
end

---------------------------------------------------------------------------
-- Markierung, Linie, Weiterrücken
---------------------------------------------------------------------------

local function Map() return Core.API("ezMap") end

function LR.Title(s)
    return L.ROUTE_WAY_TITLE:format(LR.StepText(s))
end

-- Derselbe Ort (Karte und Lage bis LR.SAME_PLACE)? Für Markierung und gewählten Schritt nach dem Neurechnen (Done).
function LR.SamePlace(a, b)
    if type(a) ~= "table" or type(b) ~= "table" or a.map == nil or a.map ~= b.map then return false end
    local ax, ay, bx, by = Num(a.x), Num(a.y), Num(b.x), Num(b.y)
    if not (ax and ay and bx and by) then return false end
    return math.abs(ax - bx) < LR.SAME_PLACE and math.abs(ay - by) < LR.SAME_PLACE
end

-- Schaltet ezMap beim Setzen Blizzards Zielverfolgung (Pfeil) ein? true | false – ezMaps Schalter „Zielverfolgung
-- einschalten“ (wayTrack, ab Werk aus seit Welle 29); nil ohne ezMap bzw. ohne die Abfrage (ältere Fassung).
function LR.ArrowOn(api)
    api = api or Map()
    if not (api and type(api.WaypointTracking) == "function") then return nil end
    local ok, on = pcall(api.WaypointTracking)
    if not ok then return nil end
    return on == true
end

-- Ohne ezMaps Schalter kommt auch nach einem Klick kein Pfeil (Fund der Gegenprüfung vom 17.11.2026): nach einem Klick
-- einmal je Sitzung sagen, wie er kommt (Klick auf die Markierung bzw. ezMaps Schalter). → true, wenn gemeldet
function LR.SayNoArrow(api)
    if LR.noArrowSaid or LR.ArrowOn(api) ~= false then return false end
    LR.noArrowSaid = true
    ns.Print(L.ROUTE_NO_ARROW .. " " .. LR.ArrowPathText(api))
    return true
end

-- Weg zu ezMaps Schalter „Zielverfolgung einschalten“ in ezCores Form (T18-18); ezMap kennt Abschnitt und Namen
-- (API.WaypointTrackingPath), ohne diese Abfrage nur die Seite von ezMap.
function LR.ArrowPathText(api)
    api = api or Map()
    local fn = type(api) == "table" and api.WaypointTrackingPath
    if type(fn) == "function" then
        local ok, text = pcall(fn)
        if ok and type(text) == "string" and text ~= "" then return text end
    end
    return Core.SettingsPathText("ezMap")
end

-- Blizzards Markierung auf den Schritt n (Standard: der nächste) → true | false, Grund ("none", "nomap", "failed").
-- Nach einem Klick (verbose) schaltet ezMap auch Blizzards Zielverfolgung ein (Pfeil) – nur mit ezMaps Schalter
-- „Zielverfolgung einschalten“ (wayTrack, ab Werk aus); ohne ihn sagt LR.SayNoArrow einmal je Sitzung, wie der Pfeil
-- kommt. auto = true: Weiterrücken ohne Klick (LR.Follow) – der Pfeil folgt nur mit ezMaps wayTrack (ab Werk aus; seit
-- Nr. 94 der Einstellungs-Prüfung vom 19.11.2026 ohne eigenen Haken routeArrow), dann ohne wiederholte Meldung einer
-- Ablehnung (ezMap, opts.track = "auto"; Fund 2 des code-reviewers vor dem Merge).
function LR.Mark(n, verbose, auto)
    local s = state and state.steps[n or 1]
    if not s then return false, "none" end
    local api = Map()
    if not (api and type(api.SetWaypoint) == "function") then
        Core.OpenPanel("map", s.map)
        if verbose then ns.Print(L.ROUTE_NO_EZMAP) end
        return false, "nomap"
    end
    local opts = { owner = LR.OWNER, label = L.ROUTE_OWNER, quiet = true, noHistory = true }
    if auto and not LR.ArrowHeld() then opts.track = "auto" end   -- ezMap schaltet den Pfeil nur mit wayTrack ein
    local ok, err = api.SetWaypoint(s.map, s.x, s.y, LR.Title(s), opts)
    if not ok then
        if verbose and err then ns.Print(err) end
        return false, "failed"
    end
    state.following = true
    state.marked = s        -- der Schritt, auf dem die Markierung steht
    -- per Klick einen Schritt weiter hinten gewählt: er bleibt markiert, solange er besteht (Fund 10). „Nächstes Ziel
    -- markieren“, ein Klick auf Schritt 1 und das Weiterrücken folgen dagegen dem nächsten Schritt – auch einem Halt,
    -- der davor eingefügt wird (Fund der Gegenprüfung vom 17.11.2026)
    state.chosen = (verbose and not auto and (n or 1) > 1) and true or false
    if verbose and not auto then LR.SayNoArrow(api) end
    return true
end

-- Nach jeder Änderung: Markierung nachziehen (nur, wenn sie noch der Route gehört), Linie neu. Steht die Markierung
-- schon auf dem nächsten Schritt oder besteht ein per Klick gewählter Schritt weiter hinten noch, bleibt sie, wo sie
-- ist; sonst rückt sie auf den nächsten Schritt – ohne Klick, also ohne Pfeil (LR.Mark mit auto).
function LR.Follow()
    if not (state and state.following) then return end
    local api = Map()
    if not (api and type(api.WaypointOwner) == "function") then return end
    local owner = api.WaypointOwner()
    if owner == LR.OWNER then
        if #state.steps > 0 then
            if state.marked == state.steps[1] then return end
            if state.chosen then
                for _, s in ipairs(state.steps) do
                    if s == state.marked then return end
                end
            end
            LR.Mark(1, nil, true)
        else
            api.ClearWaypoint()
            state.following = false
        end
    elseif owner ~= nil then
        return                   -- eine andere Route hält die Markierung: warten, nichts überschreiben (LR.Paused)
    else
        state.following = false  -- eigene Markierung des Spielers oder entfernt: nicht mehr folgen
    end
end

function LR.Paused()
    if not (state and state.following) then return nil end
    local api = Map()
    if not (api and type(api.WaypointOwner) == "function") then return nil end
    local owner, label = api.WaypointOwner()
    if owner ~= nil and owner ~= LR.OWNER then return label or tostring(owner) end
    return nil
end

-- Symbol eines Sammel-Abstechers: das Symbol des Berufs laut ezCore (wie im Menü), sonst LR.GATHER_FILE
function LR.GatherIcon(s)
    local spec = Menu.ProfessionIcon(s.prof or "")
    if type(spec) == "function" then spec = spec() end
    local file = type(spec) == "table" and spec.file or nil
    if type(file) == "table" then file = file[1] end
    if type(file) == "string" or type(file) == "number" then return file end
    return LR.GATHER_FILE[s.gather] or LR.GATHER_FILE.herb
end

-- Linie der Route auf der Weltkarte (ezMap), von deinem Ort über alle Schritte; Sammel-Abstecher stehen dort mit dem
-- Symbol ihres Berufs (Antwort 5 des Nutzers: „deutlich erkennbar“ in Liste und Karte), Tooltip wie die Zeile im Menü.
-- Seit dem Spielbefund vom 18.11.2026 („pfad muss sich mit meiner position aktualisieren "auflösen"“, „pfade evtl mit
-- pfeilrichtung“, „lvl route wirkt komisch“): den Anfang an deinem Ort setzt ezMap selbst und zieht ihn bei offener
-- Karte nach (opts.fromPlayer – vorher stand er still, wo du beim letzten Weiterrücken warst); jeder Schritt trägt dort
-- seine Nummer wie im Menü, der nächste ist hervorgehoben, der Tooltip ist die Zeile des Menüs; Pfeile zeigen die
-- Laufrichtung. Erreichte Schritte fallen wie bisher weg (erfülltes Ziel, Abgabe, Händler, Ernte).
-- Spieltest des Nutzers vom 19.11.2026 (beide Routen zugleich, wörtlich „ich erkenne nicht welche route was ist und was
-- bringen dem spieler die punkte mit den zahlen?“): die Leveling-Route nimmt ezMaps Farbfamilie Gold (die Sammel-Route
-- ist blau), heißt im Tooltip „Leveling-Route (ezQuest)“, und neben der Marke des nächsten Schritts steht sein Ziel
-- (target: die Zeile ohne Nummer); Nummern an den übrigen Schritten nur mit ezMaps Schalter „Nummern an allen
-- Schritten der Route“.
-- Pfeil auf der Minikarte zum nächsten Schritt (Spieltest des Nutzers vom 19.11.2026, wörtlich „einen kleinen pfeil für
-- die leveling route anzeigen, aber so dass es gut sichtbar ist aber nicht stört“): ezMap zeichnet ihn an Blizzards
-- Minimap (ShowMiniArrow), der Schalter routeMiniArrow (ab Werk an, eine reine Anzeige) steht hier. Unabhängig von der
-- Linie auf der Weltkarte. → true, wenn gezeigt
function LR.DrawArrow()
    local api = Map()
    if not (api and type(api.ShowMiniArrow) == "function" and type(api.ClearMiniArrow) == "function") then return false end
    local s = state and state.steps[1]
    if not (s and ns.Enabled("levelRoute") and ns.Enabled("routeMiniArrow")) then
        api.ClearMiniArrow(LR.OWNER)
        return false
    end
    return api.ShowMiniArrow(LR.OWNER, { map = s.map, x = s.x, y = s.y },
        { family = LR.PATH_FAMILY, size = ns.S and ns.S.routeMiniArrowSize }) == true
end

function LR.DrawPath()
    local api = Map()
    ns.Try("LevelRouteArrow", LR.DrawArrow)
    if not (api and type(api.ShowPath) == "function") then return 0 end
    if not (state and ns.Enabled("routeLine") and #state.steps >= 1) then
        api.ClearPath(LR.OWNER)
        return 0
    end
    local pts = {}
    for n, s in ipairs(state.steps) do
        local p = { map = s.map, x = s.x, y = s.y, label = LR.StepText(s, n), target = LR.StepText(s) }
        if s.kind == "gather" then p.icon = LR.GatherIcon(s) end
        pts[#pts + 1] = p
    end
    return api.ShowPath(LR.OWNER, pts, { fromPlayer = true, next = 1, family = LR.PATH_FAMILY, name = L.ROUTE_OWNER,
        addon = "ezQuest" })
end

-- Verfolgt Blizzard die Quest? (C_QuestLog.GetQuestWatchType: nil = nicht verfolgt) → true | false | nil (unklar)
local function Watched(log, questID)
    local kind = Call(log.GetQuestWatchType, questID)
    if Core.IsSecret(kind) then return nil end
    return kind ~= nil
end

--[[
    Blizzards Verfolgung (Entscheidung 3 des Nutzers, Fund der Gegenprüfung vom 17.11.2026): die Quest(s) des nächsten
    Quest-Schritts in die Verfolgung aufnehmen, wenn Blizzard sie noch nicht verfolgt, und frühere Aufnahmen der Route
    wieder herausnehmen, sobald die Route weiterrückt, verworfen wird oder der Haken routeWatch aus ist. Was du selbst
    verfolgst, bleibt unberührt (umkehrbar ohne Verlust). Im Kampf nach dem Kampf (ezCores Reihe, nur der letzte Wunsch).
    Die eigenen Aufnahmen stehen je Charakter in ezQuestDB.routeWatched (Watching): nach /reload bzw. dem nächsten
    Einloggen gibt es keine Route mehr, und LR.Restore nimmt sie beim ersten QUEST_LOG_UPDATE wieder heraus.
    → Zahl der Änderungen
]]
function LR.Watch()
    local log = Log()
    if not (log and type(log.GetQuestWatchType) == "function" and type(log.AddQuestWatch) == "function"
        and type(log.RemoveQuestWatch) == "function") then return 0 end
    if Core.InCombat() then
        ns.AfterCombat(function() ns.Try("LevelRouteWatch", LR.Watch) end, "levelRouteWatch")
        return 0
    end
    local want = {}
    if state and ns.Enabled("levelRoute") and ns.Enabled("routeWatch") then
        for _, s in ipairs(state.steps) do
            if s.kind == "obj" or s.kind == "turnin" then
                for _, q in ipairs(LR.QuestsOf(s)) do want[q.id] = true end
                break
            end
        end
    end
    local n = 0
    local mine = Watching(false)
    for questID in pairs(mine or {}) do
        local id = Num(questID)
        if not (id and want[id]) then
            -- gestrichen wird erst, wenn Blizzard die Quest sicher nicht mehr verfolgt (false) bzw. nach RemoveQuestWatch;
            -- ist die Antwort unklar (nil, etwa gesperrt), bleibt der Eintrag für den nächsten Lauf – sonst bliebe die
            -- Aufnahme der Route für immer in Blizzards Verfolgung (Fund des 2. Reviews der Leveling-Route, 17.11.2026)
            local watched = id and Watched(log, id)
            if watched == true then
                Call(log.RemoveQuestWatch, id)
                mine[questID] = nil
                n = n + 1
            elseif not id or watched == false then
                mine[questID] = nil
            end
        end
    end
    for questID in pairs(want) do
        mine = Watching(false)
        if not (mine and mine[questID]) and Watched(log, questID) == false then
            Call(log.AddQuestWatch, questID)
            Watching(true)[questID] = true
            n = n + 1
        end
    end
    WatchingTidy()
    return n
end

function LR.WatchedByRoute()
    local out = {}
    for questID in pairs(Watching(false) or {}) do out[#out + 1] = questID end
    table.sort(out)
    return out
end

-- Ohne Route (nach /reload bzw. dem Einloggen, auch wenn die Route verworfen wurde, als der Haken schon aus war):
-- gespeicherte Aufnahmen der Route aus Blizzards Verfolgung nehmen – beim ersten QUEST_LOG_UPDATE, wenn das Questlog
-- steht; im Kampf danach (LR.Watch) → Zahl der Änderungen
function LR.Restore()
    if state or job then return 0 end
    local mine = Watching(false)
    if not (mine and next(mine) ~= nil) then return 0 end
    return LR.Watch()
end

-- Nach jeder Änderung der Schritte (Fund 6 des code-reviewers vor dem Merge): Abgaben beim selben NPC, die jetzt
-- hintereinander stehen, werden ein Schritt, und Zeit, EP und Stufe der Zusammenfassung gelten ab deinem Ort für die
-- übrigen Schritte – vorher blieben sie nach Abgaben, Einfügen und Überspringen auf dem Stand der Rechnung
function LR.Retotal()
    if not state then return end
    state.steps = Bundle(state.steps)
    local ctx = LR.Context() or state.ctx
    if not ctx then return end
    state.xp, state.seconds, state.level, state.xpKnown = Totals(state.steps, ctx)
end

function LR.Changed()
    ns.Try("LevelRouteTotals", LR.Retotal)
    ns.Try("LevelRouteFollow", LR.Follow)
    ns.Try("LevelRoutePath", LR.DrawPath)
    ns.Try("LevelRouteWatch", LR.Watch)
end

-- Schritt n entfernen (übersprungen: in die Liste „nicht in der Route“) → der Schritt oder nil
function LR.Skip(n)
    if not state then return nil end
    local s = table.remove(state.steps, n or 1)
    if not s then return nil end
    -- ohne diesen Schritt ist eine Quest nicht mehr ganz geplant: alle ihre Schritte heraus, bei einer gebündelten
    -- Abgabe jede Quest des Bündels, je mit Grund (Leitlinie 11; Fund der Gegenprüfung vom 17.11.2026)
    local quests = LR.QuestsOf(s)
    for _, q in ipairs(quests) do
        LR.DropQuest(q.id)
        state.outside[#state.outside + 1] = { quest = q, reason = "skipped" }
        if q.id then LR.skipped[q.id] = true end
    end
    -- Halt ohne Quest (Händler, Sammel-Stelle): Ort merken, damit eine Rechnung ohne Klick ihn nicht wieder einfügt
    if #quests == 0 and (s.kind == "vendor" or s.kind == "gather") then
        LR.skippedHalts[#LR.skippedHalts + 1] = { kind = s.kind, map = s.map, x = s.x, y = s.y }
    end
    LR.Changed()
    return s
end

function LR.Clear(verbose)
    LR.Cancel()
    local api = Map()
    if api and type(api.OwnsWaypoint) == "function" and api.OwnsWaypoint(LR.OWNER) then api.ClearWaypoint() end
    if api and type(api.ClearPath) == "function" then api.ClearPath(LR.OWNER) end
    if api and type(api.ClearMiniArrow) == "function" then api.ClearMiniArrow(LR.OWNER) end
    local had = state ~= nil
    state = nil
    LR.skipped, LR.skippedHalts = {}, {}
    -- verworfen per Klick bzw. /ezq route aus: nicht gleich wieder von selbst rechnen (bis zum nächsten „Route berechnen“)
    if verbose then LR.autoHeld = true end
    ns.Try("LevelRouteWatch", LR.Watch)     -- eigene Aufnahmen in Blizzards Verfolgung wieder heraus
    if verbose and had then ns.Print(L.ROUTE_CLEARED) end
    return had
end

-- Schritte einer Quest entfernen, für die f(schritt) wahr ist → Zahl
local function RemoveSteps(f)
    local n = 0
    for i = #state.steps, 1, -1 do
        if f(state.steps[i]) then
            table.remove(state.steps, i)
            n = n + 1
        end
    end
    return n
end

-- Questlog geändert: erfüllte Teilziele fallen weg (QUEST_LOG_UPDATE); quiet: ohne LR.Changed (Nachholen nach einer
-- Rechnung in Scheiben)
function LR.OnLogUpdate(quiet)
    if not state then return 0 end
    local cache = {}
    local n = RemoveSteps(function(s)
        if s.kind ~= "obj" then return false end
        local list = cache[s.quest.id]
        if not list then
            list = LR.Objectives(s.quest.id)
            cache[s.quest.id] = list
        end
        -- zusammengefasste Ziele (LR.ObjsOf): der Schritt fällt erst weg, wenn alle erfüllt sind
        local first
        for _, so in ipairs(LR.ObjsOf(s)) do
            local o = list[so.index]
            if o then so.have, so.done = o.have, o.done end
            if not so.done then first = first or so end
        end
        if first then s.obj = first end
        return first == nil
    end)
    if n > 0 and not quiet then LR.Changed() end
    return n
end

-- Alle Schritte einer Quest aus der Route; aus einer gebündelten Abgabe nur diese Quest – der Schritt bleibt, solange
-- dort eine andere abzugeben ist → Zahl der entfernten Einträge
function LR.DropQuest(questID)
    if not state then return 0 end
    local n = 0
    for i = #state.steps, 1, -1 do
        local s = state.steps[i]
        if s.kind == "turnin" and s.quests then
            -- gebündelte Abgabe: nur diese Quest heraus; der Schritt bleibt, solange eine andere dort abzugeben ist
            local xp = 0
            for k = #s.quests, 1, -1 do
                if s.quests[k].id == questID then
                    table.remove(s.quests, k)
                    n = n + 1
                else
                    xp = xp + (s.quests[k].xp or 0)
                end
            end
            if #s.quests == 0 then
                table.remove(state.steps, i)
            else
                s.quest, s.xp = s.quests[1], xp
            end
        elseif s.quest and s.quest.id == questID then
            table.remove(state.steps, i)
            n = n + 1
        end
    end
    return n
end

-- Abgegeben: Schritte der Quest weg, ohne neu zu rechnen (QUEST_TURNED_IN)
function LR.OnTurnedIn(questID)
    questID = Num(questID)
    if not questID then return 0 end
    -- während einer Rechnung in Scheiben: die Rechnung kennt die Quest noch, danach heraus (Fund 7)
    JobDrop(questID)
    if not (state or job) then return 0 end
    -- nur mit Route bzw. Rechnung merken: QUEST_REMOVED räumt den Eintrag weg (auch, wenn die Route inzwischen
    -- verworfen ist); sonst würde eine wiederholbare Quest später beim Abbrechen fälschlich als abgegeben gelten
    turnedIn[questID] = true
    if not state then return 0 end
    local n = LR.DropQuest(questID)
    if n > 0 then LR.Changed() end
    return n
end

-- Quest weg ohne Abgabe (abgebrochen): neu rechnen (QUEST_REMOVED)
function LR.OnRemoved(questID)
    questID = Num(questID)
    if not questID then return false end
    local done = turnedIn[questID]
    turnedIn[questID] = nil         -- auch ohne Route weg (Fund 8 des code-reviewers vor dem Merge)
    if done then return false end
    if job then
        JobDrop(questID)    -- abgebrochen, während gerechnet wird: danach heraus (Fund 7)
        return false
    end
    local inRoute = false
    for _, s in ipairs(state and state.steps or {}) do
        if HasQuest(s, questID) then inRoute = true end     -- auch die zweite Quest einer gebündelten Abgabe
    end
    if not inRoute then return false end
    LR.Compute(false, true)
    return true
end

-- Neue Quest: ihre Stationen an die günstigste Stelle, die übrige Reihenfolge bleibt (QUEST_ACCEPTED); eine Abgabe
-- beim selben NPC wie ein Schritt daneben wird mit ihm gebündelt (LR.Changed). quiet: ohne LR.Changed → Zahl der Stationen
function LR.Insert(questID, quiet)
    questID = Num(questID)
    if questID then LR.skipped[questID] = nil end   -- neu angenommen: nicht mehr übersprungen
    if not (state and questID) then return 0 end
    for _, s in ipairs(state.steps) do
        if HasQuest(s, questID) then return 0 end
    end
    local ctx = LR.Context()
    if not ctx then return 0 end
    local q = LR.ReadQuest(questID, nil, 0)
    if not q.xp then
        -- Mittel der Quests mit EP laut Client (Route und „Nicht in der Route“), wie beim Rechnen – nicht je Schritt
        -- (Ziel-, Händler- und Sammel-Schritte zählten sonst mit; Fund der Gegenprüfung vom 17.11.2026). Ohne eine
        -- solche Quest setzt LR.Stations „EP unbekannt“.
        local known = {}
        for _, s in ipairs(state.steps) do
            if s.kind == "turnin" then
                for _, o in ipairs(LR.QuestsOf(s)) do known[#known + 1] = o end
            end
        end
        for _, e in ipairs(state.outside) do known[#known + 1] = e.quest end
        local mean = LR.MeanXP(known)
        if mean then q.xp, q.xpSrc = mean, "mean" end
    end
    local stations, after, outside = LR.Stations({ q }, ctx, LR.ClientPlaces(ctx.zone))
    if #outside > 0 or #stations < 2 then
        for _, e in ipairs(outside) do state.outside[#state.outside + 1] = e end
        return 0
    end
    -- Gruppen: 1 = Spieler, dann die vorhandenen Schritte, dann die neuen Stationen
    local groups, order = { ctx.start }, { 1 }
    for _, s in ipairs(state.steps) do
        groups[#groups + 1] = s
        order[#order + 1] = #groups
    end
    local new, map = {}, {}
    for k = 2, #stations do
        groups[#groups + 1] = stations[k]
        map[k] = #groups
        new[#new + 1] = #groups
    end
    local deps = {}
    for b, list in pairs(after) do
        local l = {}
        for _, a in ipairs(list) do l[#l + 1] = map[a] end
        deps[map[b]] = l
    end
    R().Insert(groups, order, new, { dist = R().WorldDistance, after = deps })
    -- eine schwere neue Quest kommt allein nicht zuerst; bräche das den Vorrang, bleibt die Reihenfolge davor
    local placed = {}
    for k, v in ipairs(order) do placed[k] = v end
    LR.HoldBack(groups, order, R().WorldDistance, ctx, nil, questID)
    if not StepsValid(groups, order) then
        for k = #order, 1, -1 do order[k] = placed[k] end
    end
    -- auch eine neu aufgenommene Quest: Abgaben anderswo ans Ende (21.11.2026). „Eigene Zone“ ist bewusst die, in der
    -- du jetzt stehst (ctx aus LR.Context), nicht die, für die die Route gerechnet wurde: ohne „Route mitführen“ (routeAuto)
    -- kommt zuerst, was hier liegt; die Ziele der neuen Quest liegen ohnehin hier (LR.Stations, Grund „zone“). Bricht das
    -- den Vorrang, bleibt die Reihenfolge (StepsValid in LR.ZoneLast).
    LR.ZoneLast(groups, order, ctx)
    local steps = {}
    for pos = 2, #order do steps[#steps + 1] = groups[order[pos]] end
    state.steps = steps
    if quiet then
        state.steps = Bundle(state.steps)
    else
        LR.Changed()
    end
    return #new
end

-- Taschen voll bzw. Haltbarkeit niedrig unterwegs: Halt einfügen, ohne neu zu rechnen (BAG_UPDATE_DELAYED,
-- UPDATE_INVENTORY_DURABILITY). Gilt kein Bedarf mehr (Taschen frei, repariert, Haken aus), fallen Halt und Hinweis
-- weg; solange ein Händlerfenster offen ist, kommt kein neuer Halt dazu – sonst setzte jedes verkaufte Stück den Halt
-- beim Händler wieder ein, an dem du gerade stehst (Fund der Gegenprüfung vom 17.11.2026)
function LR.CheckVendor()
    if not state then return false end
    if not LR.VendorNeed() then
        local n = RemoveSteps(function(s) return s.kind == "vendor" end)
        state.vendorHint = nil
        if n > 0 then LR.Changed() end
        return false
    end
    if merchantOpen then return false end
    local ctx = LR.Context()
    if not ctx then return false end
    local added, vendor, detour, need, known = LR.AddVendor(state.steps, ctx.start, ctx.detour)
    if added then
        state.vendorHint = nil
        LR.Changed()
    elseif need then
        state.vendorHint = LR.VendorHint(vendor, detour, need, known)
    end
    return added
end

-- Händlerfenster offen: jeder Händlerhalt und der Hinweis sind erledigt (gleich, bei welchem Händler du stehst;
-- sind die Taschen nach dem Schließen noch voll, fügt das nächste BAG_UPDATE_DELAYED wieder einen Halt ein)
function LR.OnMerchant()
    merchantOpen = true
    if not state then return false end
    state.vendorHint = nil
    local n = RemoveSteps(function(s) return s.kind == "vendor" end)
    if n > 0 then LR.Changed() end
    return n > 0
end

function LR.OnMerchantClosed() merchantOpen = false end

-- Zeile des Hinweises: nächster Händler zu weit bzw. noch keiner bekannt (Taschen bzw. Reparatur)
function LR.VendorHintText(h)
    if h.unknown then return h.need == "repair" and L.ROUTE_VENDOR_NONE_REPAIR or L.ROUTE_VENDOR_NONE end
    if h.elsewhere then return h.need == "repair" and L.ROUTE_VENDOR_ELSEWHERE_REPAIR or L.ROUTE_VENDOR_ELSEWHERE end
    local text = h.need == "repair" and L.ROUTE_VENDOR_HINT_REPAIR or L.ROUTE_VENDOR_HINT
    return text:format(h.name or "?", math.floor((h.yards or 0) + 0.5))
end

-- Ernte in der Nähe des Sammel-Schritts: erledigt
function LR.OnHarvest()
    local s = state and state.steps[1]
    if not (s and s.kind == "gather") then return false end
    local map, x, y = Core.PlayerPosition()
    if not map then return false end
    local here = { map = map, x = x, y = y }
    if not World(here) or R().WorldDistance(here, s) > LR.REACH then return false end
    table.remove(state.steps, 1)
    LR.Changed()
    return true
end

---------------------------------------------------------------------------
-- Menü: Blizzards Zahnrad am Questlog und ezMaps Kartenknopf (Abschnitt „Reise“)
---------------------------------------------------------------------------

local function Tip(entry, title, text, source) return Menu.Tip(entry, title, text, source) end

local function StepIcon(s)
    if s.kind == "gather" then return Menu.ProfessionIcon(s.prof or "") or LR.ICONS.obj end
    return LR.ICONS[s.kind] or LR.ICONS.obj
end

local function AddStep(root, s, n)
    local text = LR.StepText(s, n)
    local tip, source = LR.StepTip(s)
    local entry = Menu.Button(root, text, function()
        LR.Mark(n, true)
        return Menu.Close()
    end)
    Tip(entry, text, tip .. "\n\n" .. L.ROUTE_STEP_CLICK, source)
    Menu.Icon(entry, StepIcon(s))
    return entry
end

-- Haken im Menü (Antwort 5: „Kräuter und Erze“ nur mit Beruf)
local function AddToggles(root)
    local function Toggle(key)
        Tip(Menu.Toggle(root, L["OPT_" .. key], function() return ns.Enabled(key) end, function(on)
            ns.SetSetting(key, on)
            return Menu.Refresh()
        end), L["OPT_" .. key], L["OPT_" .. key .. "_TIP"])
    end
    Toggle("routeAuto")
    Toggle("routeVendor")
    if LR.HasGather() then Toggle("routeGather") end
    Toggle("routeHard")
    Toggle("routeLine")
    Toggle("routeMiniArrow")
    -- ohne Klick an Blizzards Zuständen: ab Werk aus, hier sichtbar zum Einschalten (Grundsatz des Nutzers vom 17.11.2026);
    -- „Pfeil beim Weiterrücken mitnehmen“ entfiel mit Nr. 94 der Einstellungs-Prüfung (ezMaps wayTrack gilt)
    Toggle("routeWatch")
end

-- Eintrag „Leveling-Route“ mit Untermenü → der Eintrag oder nil (Haupt-Schalter aus)
function LR.AddMenu(root)
    if not ns.Enabled("levelRoute") then return nil end
    local label = state and L.ROUTE_MENU_HAS:format(Core.Plural(#state.steps, L.ROUTE_STEPS_ONE, L.ROUTE_STEPS_MANY))
        or L.ROUTE_MENU
    local sub = Tip(Menu.Button(root, label), label, L.ROUTE_MENU_TIP)
    Menu.Icon(sub, LR.ICONS.route)
    local box = Menu.IconRoot(sub, LR.ICONS.route, { titleIcon = LR.ICONS.info })
    if job then
        local text = L.ROUTE_RUNNING:format(job.steps or 0)
        Tip(Menu.Title(box, text), text, L.ROUTE_RUNNING_TIP)
        -- Blizzards Standardwort (T18-22) über Core.Word – den Rückfall hält ezCore
        local cancel = Core.Word("CANCEL")
        Menu.Icon(Tip(Menu.Button(box, cancel, function()
            LR.CancelClick()
            return Menu.Refresh()
        end), cancel, L.ROUTE_CANCEL_TIP), LR.ICONS.clear)
    else
        local text = state and L.ROUTE_REBUILD or L.ROUTE_BUILD
        Tip(Menu.Button(box, text, function()
            LR.Compute(true)
            return Menu.Refresh()
        end), text, L.ROUTE_BUILD_TIP)
    end
    if state then
        local summary = LR.Summary()
        local srcLines = {}
        for src, n in pairs(state.sources or {}) do srcLines[#srcLines + 1] = L.ROUTE_SRC_COUNT:format(LR.SourceText(src), n) end
        table.sort(srcLines)
        Tip(Menu.Title(box, summary), summary, L.ROUTE_SUMMARY_TIP .. (#srcLines > 0 and ("\n\n" .. table.concat(srcLines, "\n")) or ""))
        -- dezent: wann und wie zuletzt gerechnet (Wunsch des Nutzers vom 18.11.2026: automatisch, ohne Chat-Ausgabe)
        local last = LR.LastText()
        if last then Tip(Menu.Title(box, Core.Grey(last)), last, L.ROUTE_LAST_TIP) end
        local paused = LR.Paused()
        if paused then
            local p = L.ROUTE_PAUSED:format(paused)
            Tip(Menu.Title(box, p), p, L.ROUTE_PAUSED_TIP)
        end
        if #state.steps == 0 then
            Tip(Menu.Title(box, L.ROUTE_EMPTY), L.ROUTE_EMPTY, L.ROUTE_EMPTY_TIP)
        end
        for i = 1, math.min(LR.SHOWN, #state.steps) do AddStep(box, state.steps[i], i) end
        if #state.steps > LR.SHOWN then
            local more = L.ROUTE_MORE:format(#state.steps - LR.SHOWN)
            local list = Tip(Menu.Button(box, more), more, L.ROUTE_MORE_TIP)
            for i = LR.SHOWN + 1, #state.steps do AddStep(list, state.steps[i], i) end
        end
        if #state.steps > 0 then
            Menu.Icon(Tip(Menu.Button(box, L.ROUTE_MARK, function()
                LR.Mark(1, true)
                return Menu.Close()
            end), L.ROUTE_MARK, L.ROUTE_MARK_TIP), LR.ICONS.mark)
            Menu.Icon(Tip(Menu.Button(box, L.ROUTE_SKIP, function()
                LR.Skip(1)
                return Menu.Refresh()
            end), L.ROUTE_SKIP, L.ROUTE_SKIP_TIP), LR.ICONS.skip)
        end
        if state.vendorHint then
            local text = LR.VendorHintText(state.vendorHint)
            local h = state.vendorHint
            Tip(Menu.Title(box, text), text, h.unknown and L.ROUTE_VENDOR_NONE_TIP
                or h.elsewhere and L.ROUTE_VENDOR_ELSEWHERE_TIP or L.ROUTE_VENDOR_HINT_TIP)
        end
        if #state.outside > 0 then
            local text = L.ROUTE_OUTSIDE:format(#state.outside)
            local list = Tip(Menu.Button(box, text), text, L.ROUTE_OUTSIDE_TIP)
            for _, e in ipairs(state.outside) do
                local line = LR.OutsideText(e)
                Tip(Menu.Title(list, line), e.quest.title, line)
            end
        end
        Menu.Icon(Tip(Menu.Button(box, L.ROUTE_CLEAR, function()
            LR.Clear(true)
            return Menu.Refresh()
        end), L.ROUTE_CLEAR, L.ROUTE_CLEAR_TIP), LR.ICONS.clear)
    end
    if not state and not job and ns.Enabled("routeAuto") then
        -- ohne Route sagen, warum noch keine da ist: nach „Route verwerfen“ angehalten, keine Erfahrung bzw. wartet auf
        -- Quests und Ort
        local key = LR.autoHeld and "ROUTE_AUTO_HELD" or LR.NoXP() and "ROUTE_AUTO_NOXP" or "ROUTE_AUTO_WAIT"
        Tip(Menu.Title(box, Core.Grey(L[key])), L[key], L[key .. "_TIP"])
    elseif LR.EmptyAuto() and LR.AutoWanted() then
        Tip(Menu.Title(box, Core.Grey(L.ROUTE_AUTO_EMPTY)), L.ROUTE_AUTO_EMPTY, L.ROUTE_AUTO_EMPTY_TIP)
    end
    if not Map() then
        Tip(Menu.Title(box, L.ROUTE_NO_EZMAP), L.ROUTE_NO_EZMAP, L.ROUTE_NO_EZMAP_TIP)
    end
    Menu.Divider(sub)
    AddToggles(box)
    return sub
end

ns.API.AddLevelRouteMenu = function(root) return LR.AddMenu(root) end

---------------------------------------------------------------------------
-- Befehl, Status, Ereignisse
---------------------------------------------------------------------------

local WORDS_CLEAR = { aus = true, off = true, clear = true, verwerfen = true, discard = true }
local WORDS_NEXT = { weiter = true, next = true, markieren = true, mark = true }

-- /ezq route [weiter|aus] → true
function LR.Command(rest)
    rest = Core.Trim(rest or ""):lower()
    if WORDS_CLEAR[rest] then
        if not LR.Clear(true) then ns.Print(L.ROUTE_NONE_YET) end
        return true
    end
    if WORDS_NEXT[rest] then
        if not LR.Mark(1, true) then ns.Print(L.ROUTE_NONE_YET) end
        return true
    end
    if not ns.Enabled("levelRoute") then
        ns.Print(L.ROUTE_OFF .. " " .. Core.SettingsPathText("ezQuest", "OPT_HEADER_ROUTE", "OPT_levelRoute", L))
        return true
    end
    LR.Compute(true)
    if state and not job then
        for i = 1, math.min(LR.SHOWN, #state.steps) do ns.Print("  " .. LR.StepText(state.steps[i], i)) end
    end
    return true
end

-- Zeile für /ezq status: Stand der Route, ohne Route der Weg dorthin (Leitlinie 3: Zahnrad am Questlog,
-- Einstellungsseite, Befehl) bzw. warum noch keine automatisch berechnet ist
function LR.StatusLine()
    if not ns.Enabled("levelRoute") then return nil end
    if job then return L.ROUTE_RUNNING:format(job.steps or 0) end
    if state then
        local last = LR.LastText()
        return last and (LR.Summary() .. " – " .. last) or LR.Summary()
    end
    if ns.Enabled("routeAuto") and not LR.autoHeld then
        return (LR.NoXP() and L.ROUTE_STATUS_NOXP or L.ROUTE_STATUS_WAIT):format(ns.SlashCmd("route"))
    end
    return L.ROUTE_STATUS_NONE:format(ns.SlashCmd("route"))
end

ns.OnReady(function()
    local throttled = ns.Throttle(function() ns.Try("LevelRouteLog", LR.OnLogUpdate) end, 0.5)
    -- ohne Route: gespeicherte Aufnahmen der Route aus Blizzards Verfolgung nehmen (nach /reload, Fund 3)
    ns.On("QUEST_LOG_UPDATE", function()
        if state then
            throttled()
        elseif not job then
            ns.Try("LevelRouteRestore", LR.Restore)
            LR.AutoNudge(true)      -- ohne Klick: das Questlog stand beim letzten Versuch noch nicht
        end
    end)
    -- nach einem Ladebildschirm kennt das Spiel deinen Ort wieder (ohne Klick: der letzte Versuch kannte ihn nicht)
    ns.On("PLAYER_ENTERING_WORLD", function() ns.Try("LevelRouteAuto", LR.OnNewPlace) end)
    -- Zonenwechsel: eine leere Route ohne Klick rechnet neu, mit routeAuto auch eine Route für die alte Zone
    -- (Entscheidung des Nutzers vom 18.11.2026; LR.OnNewPlace); sonst rückt eine bestehende weiter (Antwort 8)
    ns.On("ZONE_CHANGED_NEW_AREA", function() ns.Try("LevelRouteAuto", LR.OnNewPlace) end)
    -- auf einem Flug aufgeschoben (LR.OnNewPlace): nach der Landung einmal nachholen
    ns.On("PLAYER_CONTROL_GAINED", function() ns.Try("LevelRouteAuto", LR.AfterTaxi) end)
    ns.On("QUEST_TURNED_IN", function(_, questID) ns.Try("LevelRouteTurnIn", LR.OnTurnedIn, questID) end)
    -- QUEST_REMOVED kann vor QUEST_TURNED_IN kommen: erst kurz danach entscheiden, ob die Quest abgebrochen wurde
    ns.On("QUEST_REMOVED", function(_, questID)
        if not (state or job) then
            -- ohne Route nichts zu entscheiden; ein Merker aus QUEST_TURNED_IN darf aber nicht stehen bleiben (Fund 8)
            local id = Num(questID)
            if id then turnedIn[id] = nil end
            return
        end
        C_Timer.After(LR.REMOVED_WAIT, function() ns.Try("LevelRouteRemoved", LR.OnRemoved, questID) end)
    end)
    ns.On("QUEST_ACCEPTED", function(_, a, b)
        -- Forever/Retail: QUEST_ACCEPTED(questID); ältere Clients: (logIndex, questID)
        local questID = Num(b) or Num(a)
        if questID and job then job.add[#job.add + 1] = questID end     -- nach der Rechnung einfügen (Fund 7)
        if state then ns.Try("LevelRouteInsert", LR.Insert, questID) else LR.AutoNudge(false) end
    end)
    ns.On("MERCHANT_SHOW", function() ns.Try("LevelRouteMerchant", LR.OnMerchant) end)
    ns.On("MERCHANT_CLOSED", function() LR.OnMerchantClosed() end)
    local bags = ns.Throttle(function() ns.Try("LevelRouteVendor", LR.CheckVendor) end, 1)
    ns.On("BAG_UPDATE_DELAYED", function() if state then bags() end end)
    -- Haltbarkeit fällt auch ohne Änderung der Taschen (Kampf, Tod): Reparierer ebenso unterwegs einplanen
    ns.On("UPDATE_INVENTORY_DURABILITY", function() if state then bags() end end)
    if type(Core.Listen) == "function" then
        Core.Listen("GATHERING_HARVEST", function() ns.Try("LevelRouteHarvest", LR.OnHarvest) end, "ezQuest.LevelRoute")
        -- ein vergessener Twink (Core.ForgetChar): seine gemerkten Aufnahmen streichen
        Core.Listen("CHAR_FORGOTTEN", function(key)
            if key ~= nil and type(ns.db) == "table" and type(ns.db.routeWatched) == "table" then ns.db.routeWatched[key] = nil end
        end, "ezQuest.LevelRoute")
    end
    -- Spielbefund vom 19.11.2026: beim Öffnen der Weltkarte von deinem jetzigen Ort neu (LR.OnMapShown)
    ns.WhenAddOnLoaded("Blizzard_WorldMap", function() ns.Try("LevelRouteMap", LR.HookMap) end)
    -- Wunsch des Nutzers vom 18.11.2026: nach dem Einloggen von selbst rechnen (kurz warten, bis Questlog und Ort stehen)
    LR.AutoSchedule(LR.AUTO_DELAY)
end)

ns.OnSettingChanged(function(key)
    if key == "levelRoute" and not ns.Enabled("levelRoute") then
        LR.Clear()
    elseif (key == "levelRoute" or key == "routeAuto") and ns.Enabled(key) then
        -- eingeschaltet: gleich rechnen, ohne Route (auch nach „Route verwerfen“ – das Einschalten ist der Wunsch)
        LR.autoHeld = false
        LR.AutoSchedule()
    elseif key == "routeLine" or key == "routeMiniArrow" then
        ns.Try("LevelRoutePath", LR.DrawPath)
    elseif key == "routeMiniArrowSize" then
        ns.Try("LevelRouteArrow", LR.DrawArrow)     -- nur der Pfeil, nicht die Linie auf der Weltkarte
    elseif key == "routeWatch" then
        ns.Try("LevelRouteWatch", LR.Watch)
    elseif state and (key == "routeVendor" or key == "routeGather" or key == "routeHard" or key == "routeDetour"
        or key == "routeVendorFree") then
        LR.Compute(false, true)     -- eine geänderte Einstellung gilt sofort für die gezeigte Route
    end
end)

-- Pfeil beim Weiterrücken für die beim Update Umgestellten (ns.MigrateSettings1911, Merker routeArrowOff1911Was):
-- angehalten, bis der Spieler am Hinweis der Weltkarte (ezCores Core.OptInHint) „Einschalten“ klickt.
function LR.ArrowHeld()
    return type(ns.db) == "table" and ns.db.routeArrowOff1911Was == true
end

function LR.RegisterArrowHint()
    local Hint = Core.OptInHint
    if not (Hint and Hint.Register) then return false end
    return Hint.Register("ezQuest.routeArrow", {
        owner = "ezQuest",
        window = "map",
        label = function() return L.OPTIN_LABEL_routeArrow end,
        what = function() return L.OPTIN_routeArrow end,
        isOn = function() return not LR.ArrowHeld() end,
        enable = function()
            if type(ns.db) == "table" then ns.db.routeArrowOff1911Was = nil end
            return not LR.ArrowHeld()
        end,
        applies = LR.ArrowHeld,
        switchedOff = LR.ArrowHeld,
    })
end
LR.RegisterArrowHint()
