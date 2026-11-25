local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Gegner und Objekte laut Questie auf der Weltkarte (Welle 27, F5 b; Entscheidung des Nutzers vom 16.11.2026,
    wörtlich „f5 - b -> aber filterbar/anzeigbar?“, Wortlaut im ROADMAP-Index).

    Gruppe „Gegner und Objekte laut Questie“ im Baum der Karte (Tree.lua) – im ezMap-Knopf und in Blizzards Kartenfilter
    (Leitlinie 3), ab Werk aus und nur auf ausdrücklichen Wunsch (Tree.EXPLICIT: „Alles“ schaltet sie nicht mit ein):
      - Arten: Gegner (questieNpcs), Objekte (questieObjects), seltene Gegner (questieRares – Entdecker-Wissen nach
        Leitlinie 11, ein eigener Haken, der mit keiner Gruppe darüber angeht; ohne „Gegner“ zeigt er nur die seltenen)
      - Filtergruppe „Nach Rang“ (normale Gegner, Elite und Bosse): siebt die Gegner, zählt nicht zum Zustand. Den
        Rang „Seltene“ gibt es seit der Einstellungs-Prüfung vom 19.11.2026 nicht mehr (Nr. 84, 85): seltene Gegner
        erschienen nur mit beiden Haken – jetzt regelt sie allein questieRares (bzw. ezCores „Entdecker-Wissen“)
      - im Untermenü der Gruppe: Zahl auf dieser Karte, „Name suchen …“, „Nur für eine Quest“ (Quests im Questlog),
        „Nur für einen Gegenstand …“ (Name, Nummer oder Link), „Filter zurücksetzen“. Name, Quest und Gegenstand gelten
        nur bis zum Ausloggen (nichts gespeichert – ein vergessener Filter soll keine Punkte auf Dauer verstecken).
    Daten nur aus ezCore (Core.Sources.Questie.Spawns, QuestTargets, ItemTargets; SSOT), nur zur Laufzeit, nur solange
    QuestieDB antwortet; nichts wird kopiert oder gespeichert (Leitlinien 9 bis 11). Antwortet QuestieDB nicht (fehlt,
    falsche Form, ezCore ohne Leser), bleibt die Gruppe still weg; sind ihre Haken an, nennt der Baum am Ende den Grund,
    ebenso /ezmap status.
    Leistung: ezCore liest erst, wenn die Gruppe an ist und die Weltkarte eine Zone zeigt, in Scheiben und nur die
    gezeigte Karte; die Punkte einer Karte merkt sich ezMap, bis sich Filter oder Daten ändern (QS.cache), gezeichnet
    wird über ezCores Punkteschicht (Core.MapPins, ein Vorrat an Texturen). Höchstens QS.PIN_MAX Punkte je Karte.
    Tooltip am Punkt: Name, Art, Stufe und Rang, Zahl der Fundorte, „Quelle: laut Questie“; Klick setzt Blizzards
    Markierung.

    Paket „Fundorte“ (22.11.2026, Prüfung der Fundorte vom selben Tag):
      - Kräuter (questieHerbs) und Erze (questieOre) sind eigene Haken der Gruppe: Nachschlage-Wissen (Leitlinie 11),
        darum NICHT in Tree.EXPLICIT – der Haken der Gruppe schaltet sie mit. Ab Werk aus wie die ganze Gruppe
        (Entscheidung F5 b, Welle 27); ob sie ab Werk an sein sollen, ist eine offene Frage (docs/roadmap/ezMap.md).
        Welche Objekte Kräuter bzw. Erze sind, bestimmt ezCore (Core.Sources.Questie.Spawns mit kinds.herb/ore: eigene
        Beobachtung, Inhalt laut Questie mit der Gegenstandsart laut Client, gleicher Name); „Objekte“ zeigt den Rest
        (Kisten, Quest-Objekte, Unbekanntes) und bleibt ein Haken auf ausdrücklichen Wunsch. Symbol: das Kraut bzw. Erz
        laut Questie (Core.ItemIcon), sonst das Symbol der Art aus Gather.lua, etwas blasser als eigene Funde.
      - Keine Doppelpunkte: Ein Punkt laut Questie, der im Umkreis QS.TWIN_YARDS eines eigenen Funds DERSELBEN Art liegt,
        den ezMap gerade zeichnet (Gather.Shown), wird nicht gezeichnet; der Tooltip des eigenen Punkts nennt dann
        „auch laut Questie“ (QS.TwinOf). Gilt für alle Arten, die beide kennen (Kräuter, Erze, Kisten, Fischschwärme).
      - Nach dem code-reviewer: Wer „Objekte“ an hatte, behält Kräuter und Erze (ns.MigrateFundorte in Core.lua); eine
        Suche (Name, Quest, Gegenstand) mit „Objekte“ schließt Kräuter und Erze ein; zeichnet ein Sammel-Addon
        (gatherPins, Gather.Yields), weichen auch Kräuter und Erze laut Questie (Leitlinie 9).
]]
local QS = {}
ns.QuestieSpawns = QS

QS.PROVIDER = "ezMap.questie"
QS.PIN_SIZE = 10
QS.PIN_MAX = 1500          -- Deckel je Karte (ezCores Punkteschicht hat MAX für alle Anbieter zusammen)
QS.MIN_MAP_TYPE = 3        -- Zone und darunter; Welt und Kontinent zeigen keine Fundorte (zu viele Punkte)
QS.KEYS = { npc = "questieNpcs", object = "questieObjects", herb = "questieHerbs", ore = "questieOre" }
QS.GATHER = { herb = true, ore = true }   -- Arten, die ezCore aus den Objekten heraustrennt (Paket „Fundorte“)
QS.RANK_KEYS = { normal = "questieRankNormal", elite = "questieRankElite" }   -- seltene: QS.Options (immer durch)
QS.TEXTURE = {
    normal = "Interface\\Common\\Indicator-Yellow",
    elite = "Interface\\Common\\Indicator-Red",
    object = "Interface\\Common\\Indicator-Green",
    rare = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",   -- Rückfall, wenn Blizzards Atlas fehlt
}
QS.GATHER_SIZE = 12        -- Kräuter und Erze laut Questie: Symbol des Rohstoffs, etwas kleiner …
QS.GATHER_ALPHA = 0.8      -- … und blasser als eigene Funde (Gather.lua), die Quelle nennt der Tooltip
QS.TWIN_YARDS = 15         -- so nah an einem eigenen Fund derselben Art gilt ein Punkt laut Questie als derselbe (wie
                           -- ezCores Umkreis „eben geerntet“ und der Standard beim Zusammenlegen naher Dubletten)
QS.RARE_ATLAS = "VignetteKill"
QS.RANK_TEXT = { [1] = "QSPAWN_RANK_ELITE", [2] = "QSPAWN_RANK_RAREELITE", [3] = "QSPAWN_RANK_BOSS", [4] = "QSPAWN_RANK_RARE" }

-- Filter bis zum Ausloggen: name (Teil des Namens), quest = { id, title, targets }, item = { id, name, targets }
QS.filter = {}
QS.cache = nil             -- { map, version, points, result }
QS.version = 0

local function Reader()
    local S = Core.Sources
    local Q = S and S.Questie
    if type(Q) == "table" and type(Q.Spawns) == "function" and type(Q.SpawnsReady) == "function" then return Q end
    return nil
end

-- Antwortet QuestieDB über ezCore? → true | false, Grund ("missing" | "shape" | "error" | "core")
function QS.Available()
    local Q = Reader()
    if not Q then return false, "core" end
    local ok, yes, why = pcall(Q.SpawnsReady)
    if not ok then return false, "error" end
    return yes == true, why
end

function QS.Hidden() return not QS.Available() end

function QS.KindWanted(kind) return ns.Enabled(QS.KEYS[kind] or "") end
-- „Seltene Gegner“ allein zeigt nur die seltenen (der Haken soll nicht wirkungslos bleiben)
function QS.RaresOnly() return ns.Enabled("questieRares") and not QS.KindWanted("npc") end
function QS.GatherWanted() return QS.KindWanted("herb") or QS.KindWanted("ore") end
-- Weicht ezMap bei Sammel-Fundorten einem anderen Addon? (Gather.Yields) → Name oder nil
function QS.GatherYields()
    local G = ns.Gather
    return G and type(G.Yields) == "function" and G.Yields() or nil
end
function QS.Wanted()
    return QS.KindWanted("npc") or QS.KindWanted("object") or QS.GatherWanted() or ns.Enabled("questieRares")
end

-- ezCores Schalter „Entdecker-Wissen zeigen“ (zeigt seltene Gegner ebenso; gehört zum Schlüssel der gemerkten Punkte)
function QS.Explorer()
    local DB = Core.DB
    return type(DB) == "table" and type(DB.Explorer) == "function" and DB.Explorer() == true or false
end

-- Gebiet, unter dem ezCore Fundorte führt (eine Kleinkarte zählt zu ihrer Zone) → uiMapID oder nil, Grund ("zone" |
-- "instance": Dungeonkarten führt Questie nicht – Fund des code-reviewers vor dem Merge, 16.11.2026)
QS.INSTANCE_MAP_TYPE = 4   -- Enum.UIMapType.Dungeon
function QS.Zone(mapID)
    mapID = ns.Num(mapID)
    local info = mapID and Core.Map.Info(mapID)
    local mapType = type(info) == "table" and ns.Num(info.mapType) or nil
    if mapType == QS.INSTANCE_MAP_TYPE then return nil, "instance" end
    if not (mapType and mapType >= QS.MIN_MAP_TYPE) then return nil, "zone" end
    local Keys = Core.DB and Core.DB.Keys
    local zone = Keys and Keys.MapOf and Keys.MapOf(mapID)
    return ns.Num(zone) or mapID
end

-- Alles, was die Antwort siebt (für ezCore) – ohne den Namen nur, wenn er leer ist
function QS.Options()
    local f = QS.filter
    local opts = {
        kinds = { npc = QS.KindWanted("npc"), object = QS.KindWanted("object"), herb = QS.KindWanted("herb"),
            ore = QS.KindWanted("ore") },
        explorer = ns.Enabled("questieRares"),
        ranks = {},
        name = f.name,
    }
    for class, key in pairs(QS.RANK_KEYS) do opts.ranks[class] = ns.Enabled(key) end
    -- seltene Gegner siebt kein Rang-Haken mehr (Nr. 85): ob sie erscheinen, entscheidet das Entdecker-Wissen
    -- (explorer oben bzw. ezCores Schalter)
    opts.ranks.rare = true
    if QS.RaresOnly() then
        opts.kinds.npc = true
        opts.ranks = { normal = false, elite = false, rare = true }
    end
    -- Paket „Fundorte“: Sucht der Spieler ausdrücklich (Name, Quest, Gegenstand) und ist „Objekte“ an, gehören Kräuter
    -- und Erze dazu – sonst fände „Nur für einen Gegenstand: Kupfererz“ mit „Objekte“ allein die Adern nicht mehr
    if opts.kinds.object and QS.Filtered() then opts.kinds.herb, opts.kinds.ore = true, true end
    -- Rücksicht (Leitlinie 9): Zeichnet ein Sammel-Addon die Fundorte (GatherMate2, Gatherer Reforged – derselbe
    -- Schlüssel gatherPins wie ezMaps eigene Funde, „Trotzdem zeigen“ gatherOverride hebt beides auf), hält sich ezMap
    -- auch mit Kräutern und Erzen laut Questie zurück; die Zeile der Gruppe nennt das Addon
    if QS.GatherYields() then opts.kinds.herb, opts.kinds.ore = false, false end
    local targets = (f.quest and f.quest.targets) or (f.item and f.item.targets)
    if targets then
        opts.ids = { npc = targets.npc or {}, object = targets.object or {} }
        -- Quest und Gegenstand zusammen: nur, was zu beiden passt
        if f.quest and f.item then
            local both = { npc = {}, object = {} }
            for _, kind in ipairs({ "npc", "object" }) do
                for id in pairs(f.quest.targets[kind] or {}) do
                    if f.item.targets[kind] and f.item.targets[kind][id] then both[kind][id] = true end
                end
            end
            opts.ids = both
        end
    end
    return opts
end

-- Filter geändert: Punkte neu (einmal)
function QS.Changed()
    QS.version = QS.version + 1
    QS.cache = nil
    QS.twins = {}
    local P = Core.MapPins
    if type(P) == "table" and type(P.Refresh) == "function" then P.Refresh() end
end

-- Antwort für die Zone (über ezCore) → antwort | nil, grund[, fertig, gesamt]
function QS.Ask(zone)
    local Q = Reader()
    if not Q then return nil, "core" end
    local ok, r, why, done, total = pcall(Q.Spawns, zone, QS.Options())
    if not ok then return nil, "error" end
    return r, why, done, total
end

-- Kraut oder Erz laut ezCore? → "herb" | "ore" | nil
local function GatherKind(e)
    return e.kind == "object" and QS.GATHER[e.gather] and e.gather or nil
end
QS.GatherKind = GatherKind

local function Texture(e)
    local gather = GatherKind(e)
    if gather then
        local icon = e.gatherItem and Core.ItemIcon(e.gatherItem)
        local G = ns.Gather
        return { texture = icon or (G and G.KIND_ICON and G.KIND_ICON[gather]) or QS.TEXTURE.object, gather = true }
    end
    if e.kind == "object" then return { texture = QS.TEXTURE.object } end
    if e.rare then
        if Core.AtlasExists(QS.RARE_ATLAS) then return { atlas = QS.RARE_ATLAS } end
        return { texture = QS.TEXTURE.rare }
    end
    return { texture = e.elite and QS.TEXTURE.elite or QS.TEXTURE.normal }
end

-- Punkte je Art in einer Antwort → { npc, object }
function QS.PointCount(list)
    local count = { npc = 0, object = 0 }
    for _, e in ipairs(list or {}) do
        local kind = e.kind == "object" and "object" or "npc"
        count[kind] = count[kind] + #e.points
    end
    return count
end

-- Deckel QS.PIN_MAX über die Arten verteilt: jede Art bekommt mindestens die Hälfte, was eine nicht braucht, die
-- andere (sonst verdrängten viele Gegner alle Objekte) → { npc, object }
function QS.Quota(count)
    local max = QS.PIN_MAX
    if count.npc + count.object <= max then return { npc = count.npc, object = count.object } end
    local half = math.floor(max / 2)
    local npc = math.min(count.npc, math.max(half, max - count.object))
    return { npc = npc, object = math.min(count.object, max - npc) }
end

---------------------------------------------------------------------------
-- Keine Doppelpunkte mit eigenen Funden (Paket „Fundorte“, 22.11.2026)
---------------------------------------------------------------------------

QS.twins = {}              -- [QS.TwinKey(eigener Fundort)] = Eintrag laut Questie (zuletzt gezeichnete Karte)

-- Schlüssel eines eigenen Fundorts: Art, Speicherkarte, Objekt und Lage auf der Speicherkarte (Core.Gathering.Nodes
-- liefert je Aufruf Kopien – die Tabelle selbst taugt nicht als Schlüssel)
function QS.TwinKey(node)
    if type(node) ~= "table" then return nil end
    local sx, sy = ns.Num(node.sx), ns.Num(node.sy)
    if not (sx and sy) then sx, sy = ns.Num(node.x), ns.Num(node.y) end
    if not (sx and sy) then return nil end
    return ("%s:%s:%s:%.4f:%.4f"):format(tostring(node.kind), tostring(node.map), tostring(node.id), sx, sy)
end

-- Steht an diesem eigenen Fundort auch ein Punkt laut Questie, den ezMap deshalb nicht zeichnet? mapID: die Karte des
-- Tooltips – nur für die zuletzt gezeichnete Weltkarte (bzw. dieselbe Karte auf der Minikarte) → Eintrag oder nil
function QS.TwinOf(node, mapID)
    local key = QS.TwinKey(node)
    local e = key and QS.twins[key]
    if not e then return nil end
    if mapID ~= nil and QS.twinsMap ~= nil and ns.Num(mapID) ~= QS.twinsMap then return nil end
    -- nur, solange ezMap seine Art laut Questie fragt (Haken bzw. Suche; sonst fragt ezCores Punkteschicht QS.Points
    -- nicht mehr und die Zeile wäre veraltet)
    if not QS.Available() then return nil end
    local opts = QS.Options()
    if opts.kinds[GatherKind(e) or "object"] ~= true then return nil end
    return e
end

-- Eigene Funde, die ezMap gerade auf der Weltkarte mapID zeichnet (aus Gather.Points im selben Neuaufbau, sonst
-- Gather.Shown; seit ezData auch die Punkte aus Beiträgen anderer Spieler – kein Doppelpunkt neben ihnen, ihr Tooltip
-- nennt dann „auch laut Questie“), umgerechnet auf die Zone der Punkte laut Questie, in Zellen von QS.TWIN_YARDS (ohne Kartengröße 1 %
-- der Karte, wie Gather.Close) → Raster oder nil
local function OwnGrid(mapID, zone)
    local G = ns.Gather
    if not (G and type(G.Active) == "function" and type(G.Shown) == "function" and G.Active(mapID)) then return nil end
    local last = G.lastShown
    local nodes = (type(last) == "table" and last.map == mapID and type(last.nodes) == "table") and last.nodes
        or G.Shown(mapID)
    if #nodes == 0 then return nil end
    local D = Core.Discovery
    local w, h
    if D and type(D.MapYards) == "function" then w, h = D.MapYards(zone) end
    local cx, cy = 0.01, 0.01
    if w and h and w > 0 and h > 0 then cx, cy = QS.TWIN_YARDS / w, QS.TWIN_YARDS / h end
    local grid = { cx = cx, cy = cy, cells = {} }
    for _, node in ipairs(nodes) do
        local x, y = ns.Num(node.x), ns.Num(node.y)
        -- Teilkarte gezeigt: die (wenigen) eigenen Funde auf die Zone umrechnen statt jeden Punkt laut Questie
        if x and y and zone ~= mapID then x, y = Core.Map.PosOn(zone, mapID, x, y) end
        if x and y then
            local key = math.floor(x / cx) .. ":" .. math.floor(y / cy)
            local cell = grid.cells[key] or {}
            grid.cells[key] = cell
            cell[#cell + 1] = { node = node, x = x, y = y }
        end
    end
    return grid
end

-- Eigener Fund derselben Art im Umkreis (alles auf der Zone)? → Knoten oder nil
local function NearOwn(grid, zone, kind, x, y)
    local gx, gy = math.floor(x / grid.cx), math.floor(y / grid.cy)
    for dx = -1, 1 do
        for dy = -1, 1 do
            for _, own in ipairs(grid.cells[(gx + dx) .. ":" .. (gy + dy)] or {}) do
                if own.node.kind == kind and ns.Gather.Close(zone, x, y, own.x, own.y, QS.TWIN_YARDS) then
                    return own.node
                end
            end
        end
    end
    return nil
end

-- Punkte ohne die Zwillinge eigener Funde → Liste, Zahl der ausgelassenen. Merkt die Zwillinge für den Tooltip.
function QS.WithoutTwins(points, mapID, zone)
    QS.twins, QS.twinsMap = {}, mapID
    local G = ns.Gather
    if not (G and type(G.Close) == "function") then return points, 0 end
    local own = {}
    for _, kind in ipairs(G.KINDS or {}) do own[kind] = true end
    local out, grid, n = {}, nil, 0
    for _, p in ipairs(points) do
        local e = p.questie
        local kind = type(e) == "table" and e.kind == "object" and e.gather or nil
        local twin
        if kind and own[kind] then
            if grid == nil then grid = OwnGrid(mapID, zone) or false end
            if grid then twin = NearOwn(grid, zone, kind, p.x, p.y) end
        end
        if twin then
            local key = QS.TwinKey(twin)
            if key then QS.twins[key] = e end
            n = n + 1
        else
            out[#out + 1] = p
        end
    end
    if n == 0 then return points, 0 end        -- nichts ausgelassen: die gemerkte Liste selbst (kein neuer Aufbau)
    return out, n
end

-- Punkte der gezeigten Karte für ezCores Punkteschicht. Gemerkt (QS.cache) werden die Punkte laut Questie; die
-- Zwillinge eigener Funde rechnet jeder Aufruf neu (eigene Funde, Filter und Haken von „Sammeln“ ändern sich ohne
-- Nachricht an diese Datei – Gather.Refresh zeichnet beide Anbieter neu).
function QS.Points(mapID)
    QS.twins = {}
    if not QS.Wanted() then return {} end
    local zone, noZone = QS.Zone(mapID)
    if not zone then
        QS.last = { why = noZone or "zone" }
        return {}
    end
    local c, explorer = QS.cache, QS.Explorer()
    local yields = QS.GatherYields() and true or false      -- Sammel-Addon zeichnet: Kräuter und Erze weichen
    if not (c and c.map == zone and c.version == QS.version and c.explorer == explorer and c.yields == yields) then
        local r, why, done, total = QS.Ask(zone)
        if not r then
            QS.last = { map = zone, why = why, done = done, total = total }
            return {}
        end
        local count = QS.PointCount(r.list)
        local quota = QS.Quota(count)
        local points, used = {}, { npc = 0, object = 0 }
        for _, e in ipairs(r.list) do
            local kind = e.kind == "object" and "object" or "npc"
            local look = Texture(e)
            local size = e.rare and QS.PIN_SIZE + 4 or look.gather and QS.GATHER_SIZE or QS.PIN_SIZE
            for _, p in ipairs(e.points) do
                if used[kind] < quota[kind] then
                    used[kind] = used[kind] + 1
                    points[#points + 1] = { x = p.x, y = p.y, map = zone, size = size, texture = look.texture,
                        atlas = look.atlas, a = look.gather and QS.GATHER_ALPHA or nil, questie = e }
                end
            end
        end
        c = { map = zone, version = QS.version, explorer = explorer, yields = yields, points = points, result = r,
            all = count.npc + count.object }
        QS.cache = c
    end
    local shown, twins = QS.WithoutTwins(c.points, ns.Num(mapID) or zone, zone)
    -- shown: nach dem Deckel (für „Gezeigt: n von m“), twins: wegen eines eigenen Funds nicht gezeichnet
    QS.last = { map = zone, result = c.result, shown = #c.points, all = c.all, twins = twins }
    return shown
end

local function LevelText(e)
    if not e.lo then return nil end
    if e.hi and e.hi ~= e.lo then return L.QSPAWN_LEVELS:format(e.lo, e.hi) end
    return tostring(e.lo)
end

function QS.PinTooltip(tip, point)
    local e = type(point) == "table" and point.questie
    if not e then return end
    Core.TipTitle(tip, e.name or ("#" .. tostring(e.id)))
    if e.kind == "npc" then
        local parts = { L.QSPAWN_PIN_NPC }
        local level = LevelText(e)
        if level then parts[#parts + 1] = L.QSPAWN_PIN_LEVEL:format(level) end
        local rank = QS.RANK_TEXT[e.rank]
        if rank then parts[#parts + 1] = L[rank] end
        Core.TipLine(tip, table.concat(parts, ", "), "hint")
    else
        -- Art laut ezCore (Paket „Fundorte“): Kräuter- bzw. Erzvorkommen, Kiste, Quest-Objekt …; ohne Art „Objekt“
        local art = e.gather and L["QSPAWN_PIN_KIND_" .. e.gather]
        Core.TipLine(tip, type(art) == "string" and art ~= "QSPAWN_PIN_KIND_" .. e.gather and art or L.QSPAWN_PIN_OBJECT, "hint")
        if e.gatherItem then
            local item = Core.ItemNameByID(e.gatherItem) or ("#" .. tostring(e.gatherItem))
            Core.TipLine(tip, L.QSPAWN_PIN_YIELD:format(item), "highlight", true)
        end
        if e.gather and e.gatherHow then
            local how = L["QSPAWN_PIN_HOW_" .. e.gatherHow]
            if type(how) == "string" and how ~= "QSPAWN_PIN_HOW_" .. e.gatherHow then Core.TipLine(tip, how, "hint", true) end
        end
    end
    -- mehr als ezCore je Eintrag liest (Q.SPAWN_PER_ID): „mindestens n“ statt einer zu kleinen Zahl
    local spots = e.capped and L.QSPAWN_PIN_SPOTS_MORE or L.QSPAWN_PIN_SPOTS
    Core.TipLine(tip, spots:format(#e.points), "hint")
    if e.rare then Core.TipLine(tip, L.QSPAWN_PIN_EXPLORER, "hint", true) end
    local S = Core.Sources
    local label = S and S.Label and S.Label({ source = "Questie", sourceKey = "QuestieDB" })
        or Core.L.SOURCES_ACCORDING:format("Questie")
    Core.TipLine(tip, L.QSPAWN_PIN_SOURCE:format(label), "hint", true)
    Core.TipClick(tip, L.QSPAWN_PIN_HINT)
end

function QS.PinClick(point, button)
    local e = type(point) == "table" and point.questie
    if not e or button == "RightButton" then return false end
    return ns.Way.Set(point.map, point.x, point.y, e.name, true)
end

function QS.InitPins()
    local P = Core.MapPins
    if not (type(P) == "table" and type(P.AddProvider) == "function") then return false end
    P.AddProvider(QS.PROVIDER, {
        owner = "ezMap",
        order = 70,             -- nach den eigenen Daten: die Obergrenze der Schicht trifft zuerst Questies Punkte
        punkte = QS.Points,
        sichtbar = function() return QS.Wanted() and QS.Available() end,
        tooltip = QS.PinTooltip,
        klick = QS.PinClick,
    })
    return true
end

---------------------------------------------------------------------------
-- Filter: Name, Quest, Gegenstand
---------------------------------------------------------------------------

function QS.SetName(text)
    text = type(text) == "string" and text:match("^%s*(.-)%s*$") or ""
    QS.filter.name = text ~= "" and text or nil
    QS.Changed()
    return QS.filter.name
end

-- Quests im Questlog des Charakters (Blizzards C_QuestLog) → { { id, title } … }
function QS.LogQuests()
    local out = {}
    local api = rawget(_G, "C_QuestLog")
    if type(api) ~= "table" or type(api.GetNumQuestLogEntries) ~= "function" or type(api.GetInfo) ~= "function" then
        return out
    end
    local okN, n = pcall(api.GetNumQuestLogEntries)
    n = okN and ns.Num(n) or 0
    for i = 1, n do
        local ok, info = pcall(api.GetInfo, i)
        if ok and type(info) == "table" and not ns.IsSecret(info) and info.isHeader ~= true and info.isHidden ~= true then
            local id, title = ns.Num(info.questID), Core.Plain(info.title)
            if id and id > 0 and type(title) == "string" and title ~= "" then out[#out + 1] = { id = id, title = title } end
        end
    end
    return out
end

-- Quest wählen (nil: kein Quest-Filter) → true | false, Grund
function QS.SetQuest(id, title)
    if id == nil then
        QS.filter.quest = nil
        QS.Changed()
        return true
    end
    local Q = Reader()
    local targets, why
    if Q and type(Q.QuestTargets) == "function" then targets, why = Q.QuestTargets(id) else why = "core" end
    if not targets then
        ns.Print(L.QSPAWN_QUEST_FAILED:format(title or ("#" .. tostring(id))))
        return false, why
    end
    -- eine Quest, die QuestieDB nicht kennt (etwa eigene Quests von Forever), liefert leere Mengen: sonst bliebe die
    -- Karte ohne Meldung leer
    if not (next(targets.npc or {}) or next(targets.object or {})) then
        ns.Print(L.QSPAWN_QUEST_NOTHING:format(title or targets.name or ("#" .. tostring(id))))
        return false, "none"
    end
    QS.filter.quest = { id = id, title = title or targets.name or ("#" .. tostring(id)), targets = targets }
    QS.Changed()
    return true
end

-- Eingabe „Name, Nummer oder Link“ » Gegenstands-ID
function QS.ItemID(text)
    if type(text) ~= "string" then return nil end
    local id = tonumber(text:match("item:(%d+)") or text:match("^%s*(%d+)%s*$"))
    if id then return id end
    local name = text:match("^%s*%[?(.-)%]?%s*$")
    local K = Core.Knowledge
    if name and name ~= "" and K and type(K.ItemIDByName) == "function" then return ns.Num(K.ItemIDByName(name)) end
    return nil
end

-- Gegenstand wählen (leer: kein Gegenstands-Filter) → true | false, Grund
function QS.SetItem(text)
    if type(text) ~= "string" or text:match("^%s*$") then
        QS.filter.item = nil
        QS.Changed()
        return true
    end
    local id = QS.ItemID(text)
    if not id then
        ns.Print(L.QSPAWN_ITEM_UNKNOWN:format(text))
        return false, "unknown"
    end
    local Q = Reader()
    local targets, why
    if Q and type(Q.ItemTargets) == "function" then targets, why = Q.ItemTargets(id) else why = "core" end
    local name = (targets and targets.name) or Core.ItemNameByID(id) or ("#" .. id)
    if why == "explorer" then
        ns.Print(L.QSPAWN_ITEM_EXPLORER:format(name))
        return false, why
    end
    if not targets then
        ns.Print(L.QSPAWN_ITEM_FAILED:format(name))
        return false, why
    end
    if not (next(targets.npc) or next(targets.object)) then
        ns.Print(L.QSPAWN_ITEM_NOTHING:format(name))
        return false, "none"
    end
    QS.filter.item = { id = id, name = name, targets = targets }
    QS.Changed()
    return true
end

function QS.Filtered()
    local f = QS.filter
    return f.name ~= nil or f.quest ~= nil or f.item ~= nil
end

function QS.ResetFilter()
    QS.filter = {}
    QS.Changed()
end

---------------------------------------------------------------------------
-- Menü der Gruppe (ezMap-Knopf und Blizzards Kartenfilter)
---------------------------------------------------------------------------

local Menu = Core.Menu
local function Tip(entry, title, text) return ns.MapButton.Tip(entry, title, text) end

-- Zeile „was gerade auf der Karte steht“ → Text, Erklärung
function QS.StateText(mapID)
    if not QS.Wanted() then return L.QSPAWN_STATE_OFF, L.QSPAWN_STATE_OFF_TIP end
    local zone, noZone = QS.Zone(mapID)
    if not zone then
        if noZone == "instance" then return L.QSPAWN_INSTANCE, L.QSPAWN_INSTANCE_TIP end
        return L.QSPAWN_NOZONE, L.QSPAWN_NOZONE_TIP
    end
    local r, why, done, total = QS.Ask(zone)
    if not r then
        if why == "building" then
            local pct = (ns.Num(total) and total > 0) and math.floor((ns.Num(done) or 0) * 100 / total) or 0
            return L.QSPAWN_BUILDING:format(Core.Percent(pct)), L.QSPAWN_BUILDING_TIP
        end
        return QS.ReasonText(why), L.QSPAWN_MISSING_TIP
    end
    local text = L.QSPAWN_COUNT:format(r.n.npc, r.n.object)
    -- Kräuter und Erze (Paket „Fundorte“): eigene Zahlen, nur wenn einer der beiden Haken an ist
    if QS.GatherWanted() then text = text .. ", " .. L.QSPAWN_COUNT_GATHER:format(r.n.herb or 0, r.n.ore or 0) end
    local tip = L.QSPAWN_COUNT_TIP
    if r.hidden and r.hidden.rare > 0 then tip = tip .. "\n\n" .. L.QSPAWN_HIDDEN_RARE:format(r.hidden.rare) end
    local c = QS.cache
    if c and c.map == zone and QS.last and QS.last.all and QS.last.all > QS.last.shown then
        tip = tip .. "\n\n" .. L.QSPAWN_CAPPED:format(QS.last.shown, QS.last.all)
    end
    if c and c.map == zone and QS.last and (QS.last.twins or 0) > 0 then
        tip = tip .. "\n\n" .. L.QSPAWN_TWINS:format(QS.last.twins)
    end
    if r.sorting and QS.GatherWanted() then tip = tip .. "\n\n" .. L.QSPAWN_SORTING end
    local other = QS.GatherWanted() and QS.GatherYields()
    if other then tip = tip .. "\n\n" .. L.QSPAWN_GATHER_OTHER:format(other) end
    if r.capped then tip = tip .. "\n\n" .. L.QSPAWN_READ_CAPPED end
    return text, tip
end

function QS.ReasonText(why)
    if why == "missing" then return L.QSPAWN_MISSING end
    if why == "core" then return L.QSPAWN_CORE end
    return L.QSPAWN_BROKEN
end

function QS.AddMenu(entry, mapID)
    Menu.Divider(entry)
    local text, tip = QS.StateText(mapID)
    Tip(Menu.Title(entry, text), text, tip)
    -- Name
    local nameText = QS.filter.name and L.QSPAWN_NAME_ACTIVE:format(QS.filter.name) or L.QSPAWN_NAME
    Tip(Menu.Button(entry, nameText, function()
        Core.AskText(L.QSPAWN_NAME_PROMPT, QS.filter.name or "", function(input) QS.SetName(input) end, 60)
    end), nameText, L.QSPAWN_NAME_TIP)
    -- Quest
    local quest = QS.filter.quest
    local questText = quest and L.QSPAWN_QUEST_ACTIVE:format(quest.title) or L.QSPAWN_QUEST
    local sub = Tip(Menu.Button(entry, questText), questText, L.QSPAWN_QUEST_TIP)
    local current = function() return QS.filter.quest and QS.filter.quest.id or 0 end
    Tip(Menu.Radio(sub, L.QSPAWN_QUEST_ALL, current, function() QS.SetQuest(nil) end, 0), L.QSPAWN_QUEST_ALL,
        L.QSPAWN_QUEST_ALL_TIP)
    local list = QS.LogQuests()
    if #list == 0 then Menu.Title(sub, L.QSPAWN_QUEST_NONE) end
    for _, q in ipairs(list) do
        Tip(Menu.Radio(sub, q.title, current, function() QS.SetQuest(q.id, q.title) end, q.id), q.title,
            L.QSPAWN_QUEST_ENTRY_TIP)
    end
    -- Gegenstand
    local item = QS.filter.item
    local itemText = item and L.QSPAWN_ITEM_ACTIVE:format(item.name) or L.QSPAWN_ITEM
    Tip(Menu.Button(entry, itemText, function()
        Core.AskText(L.QSPAWN_ITEM_PROMPT, item and item.name or "", function(input) QS.SetItem(input) end, 80)
    end), itemText, L.QSPAWN_ITEM_TIP)
    if QS.Filtered() then
        Tip(Menu.Button(entry, L.QSPAWN_RESET, function() QS.ResetFilter() end), L.QSPAWN_RESET, L.QSPAWN_RESET_TIP)
    end
end

-- QuestieDB noch einmal fragen (nach „antwortet nicht wie erwartet“ bzw. einem Fehler): ezCore verwirft Index und
-- Karten, der nächste Blick auf eine Zone baut neu (Fund des code-reviewers vor dem Merge: sonst erst nach /reload)
function QS.Retry()
    local Q = Reader()
    if not (Q and type(Q.ForgetSpawns) == "function") then return false end
    Q.ForgetSpawns()
    QS.Changed()
    return true
end

-- Verborgene Gruppe: am Ende des Baums der Grund, solange ihre Haken an sind (sonst still); bei falscher Form oder
-- Fehler dazu der Knopf „Neu lesen“ (Leitlinie 3)
function QS.AddHiddenHint(root)
    local ok, why = QS.Available()
    if ok or not QS.Wanted() then return false end
    local text = QS.ReasonText(why)
    Tip(Menu.Title(root, text), text, L.QSPAWN_MISSING_TIP)
    if why == "shape" or why == "error" then
        Tip(Menu.Button(root, L.QSPAWN_RETRY, function() QS.Retry() end), L.QSPAWN_RETRY, L.QSPAWN_RETRY_TIP)
    end
    return true
end

---------------------------------------------------------------------------
-- Anmeldung im Baum, Punkte neu, Status
---------------------------------------------------------------------------

-- Seit Welle 27 unter „Entdecken“ (neben Entdecker-Wissen), vorher eigene Gruppe oben
ns.Tree.Add("discover", { id = "questie", hidden = QS.Hidden, children = {
    { key = "questieNpcs" }, { key = "questieHerbs" }, { key = "questieOre" }, { key = "questieObjects" },
    { key = "questieRares" },
    { id = "questieRank", filter = true, children = { { key = "questieRankNormal" }, { key = "questieRankElite" } } },
} })
ns.Tree.EXPLICIT.questie = true          -- „Alles“ schaltet die Gruppe nicht mit ein (Leistung, fremdes Wissen)
-- … und auch nicht der Klick auf „Entdecken“ oder dessen „Alle auswählen“ (frühere Regel, wiederhergestellt nach
-- Fund 3 des code-reviewers vom 17.11.2026, seit Welle 27 steht die Gruppe unter „Entdecken“; Empfehlung umgesetzt,
-- Antwort offen, Frage in docs/roadmap/ezMap.md)
ns.Tree.EXPLICIT_OWN.questie = true
ns.Tree.EXPLICIT.questieRares = true     -- seltene Gegner nur auf ausdrücklichen Wunsch (Leitlinie 11)
-- Objekte wie seltene Gegner nur mit eigenem Haken: Questie trennt Schätze nicht von anderen Objekten, sie wären
-- Entdecker-Wissen (Antwort des Nutzers vom 17.11.2026, wörtlich „Eigener Haken nötig (Empfohlen)“, Leitlinie 11);
-- „Alle auswählen“ lässt sie aus, der Tooltip nennt es. Seit dem Paket „Fundorte“ (22.11.2026) stehen Kräuter und
-- Erze getrennt (questieHerbs, questieOre – Nachschlage-Wissen, nicht hier); unter „Objekte“ bleiben Kisten,
-- Quest-Objekte und alles, was ezCore keiner Art zuordnet – darum bleibt der eigene Haken.
ns.Tree.EXPLICIT.questieObjects = true
ns.Tree.GROUP_MENU.questie = QS.AddMenu
ns.Tree.ALL_MENU[#ns.Tree.ALL_MENU + 1] = QS.AddHiddenHint

local WATCH = { questieNpcs = true, questieObjects = true, questieRares = true, questieRankNormal = true,
    questieRankElite = true, questieHerbs = true, questieOre = true }

ns.OnReady(function() ns.Try("QuestiePins", QS.InitPins) end)
ns.OnSettingChanged(function(key)
    if WATCH[key] then QS.Changed() end
end)

-- Daten fertig (ezCore liest in Scheiben): neu zeichnen, wenn die gezeigte Karte betroffen ist
local function WorldMapShown()
    local map = rawget(_G, "WorldMapFrame")
    if type(map) ~= "table" or type(map.IsShown) ~= "function" then return false end
    local ok, shown = pcall(map.IsShown, map)
    return ok and shown == true
end

function QS.OnSpawns(map, state)
    if not QS.Wanted() then return end
    if state == "ready" and QS.cache and QS.cache.map == map then return end
    QS.cache = nil
    local P = Core.MapPins
    if WorldMapShown() and type(P) == "table" and type(P.Refresh) == "function" then P.Refresh() end
end
if type(Core.Listen) == "function" then
    Core.Listen("QUESTIE_SPAWNS", function(map, state) ns.Try("QuestieSpawns", QS.OnSpawns, map, state) end, "ezMap")
end

-- Art der Objekte (Paket „Fundorte“): eigene Funde bzw. der fertige Inhalt laut Questie ändern, was ezCore erkennt –
-- die gemerkten Punkte verwerfen. Nach eigenen Funden zeichnet Gather.Refresh beide Anbieter neu, nach dem Inhalt
-- laut Questie diese Datei (nur bei offener Weltkarte).
local function ForgetPoints() QS.cache = nil end
function QS.OnContents(_, state)
    -- auch ohne „Kräuter“/„Erze“: erkannte Kräuter und Erze stehen dann nicht mehr unter „Objekte“
    if state ~= "index" or not QS.Wanted() then return end
    ForgetPoints()
    local P = Core.MapPins
    if WorldMapShown() and type(P) == "table" and type(P.Refresh) == "function" then P.Refresh() end
end
if type(Core.Listen) == "function" then
    Core.Listen("GATHERING_CHANGED", function() ns.Try("QuestieSpawns", ForgetPoints) end, "ezMap.QuestieSpawns")
    Core.Listen("QUESTIE_CONTENTS", function(map, state) ns.Try("QuestieSpawns", QS.OnContents, map, state) end,
        "ezMap.QuestieSpawns")
end

ns.AddStatusLine(function()
    if not QS.Wanted() then return L.STATUS_QSPAWN_OFF end
    local ok, why = QS.Available()
    if not ok then return L.STATUS_QSPAWN_MISSING:format(QS.ReasonText(why)) end
    local last = QS.last
    if last and last.result then
        local drawn = last.shown - (last.twins or 0)
        local line = L.STATUS_QSPAWN_ON:format(ns.MapName(last.map), last.result.n.npc, last.result.n.object, drawn)
        if QS.GatherWanted() then
            line = line .. " " .. L.STATUS_QSPAWN_GATHER:format(last.result.n.herb or 0, last.result.n.ore or 0)
        end
        if (last.twins or 0) > 0 then line = line .. " " .. L.STATUS_QSPAWN_TWINS:format(last.twins) end
        if last.result.capped or (last.all and last.all > last.shown) then line = line .. " " .. L.STATUS_QSPAWN_CAPPED end
        return line
    end
    return L.STATUS_QSPAWN_WAITING
end)
