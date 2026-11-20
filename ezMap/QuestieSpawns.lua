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
]]
local QS = {}
ns.QuestieSpawns = QS

QS.PROVIDER = "ezMap.questie"
QS.PIN_SIZE = 10
QS.PIN_MAX = 1500          -- Deckel je Karte (ezCores Punkteschicht hat MAX für alle Anbieter zusammen)
QS.MIN_MAP_TYPE = 3        -- Zone und darunter; Welt und Kontinent zeigen keine Fundorte (zu viele Punkte)
QS.KEYS = { npc = "questieNpcs", object = "questieObjects" }
QS.RANK_KEYS = { normal = "questieRankNormal", elite = "questieRankElite" }   -- seltene: QS.Options (immer durch)
QS.TEXTURE = {
    normal = "Interface\\Common\\Indicator-Yellow",
    elite = "Interface\\Common\\Indicator-Red",
    object = "Interface\\Common\\Indicator-Green",
    rare = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",   -- Rückfall, wenn Blizzards Atlas fehlt
}
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
function QS.Wanted() return QS.KindWanted("npc") or QS.KindWanted("object") or ns.Enabled("questieRares") end

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
        kinds = { npc = QS.KindWanted("npc"), object = QS.KindWanted("object") },
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

local function Texture(e)
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

-- Punkte der gezeigten Karte für ezCores Punkteschicht
function QS.Points(mapID)
    if not QS.Wanted() then return {} end
    local zone, noZone = QS.Zone(mapID)
    if not zone then
        QS.last = { why = noZone or "zone" }
        return {}
    end
    local c, explorer = QS.cache, QS.Explorer()
    if c and c.map == zone and c.version == QS.version and c.explorer == explorer then return c.points end
    local r, why, done, total = QS.Ask(zone)
    if not r then
        QS.last = { map = zone, why = why, done = done, total = total }
        return {}
    end
    local count = QS.PointCount(r.list)
    local all = count.npc + count.object
    local quota = QS.Quota(count)
    local points, used = {}, { npc = 0, object = 0 }
    for _, e in ipairs(r.list) do
        local kind = e.kind == "object" and "object" or "npc"
        local look = Texture(e)
        for _, p in ipairs(e.points) do
            if used[kind] < quota[kind] then
                used[kind] = used[kind] + 1
                points[#points + 1] = { x = p.x, y = p.y, map = zone, size = e.rare and QS.PIN_SIZE + 4 or QS.PIN_SIZE,
                    texture = look.texture, atlas = look.atlas, questie = e }
            end
        end
    end
    QS.last = { map = zone, result = r, shown = #points, all = all }
    QS.cache = { map = zone, version = QS.version, explorer = explorer, points = points, result = r }
    return points
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
        Core.TipLine(tip, L.QSPAWN_PIN_OBJECT, "hint")
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
    local tip = L.QSPAWN_COUNT_TIP
    if r.hidden and r.hidden.rare > 0 then tip = tip .. "\n\n" .. L.QSPAWN_HIDDEN_RARE:format(r.hidden.rare) end
    local c = QS.cache
    if c and c.map == zone and QS.last and QS.last.all and QS.last.all > QS.last.shown then
        tip = tip .. "\n\n" .. L.QSPAWN_CAPPED:format(QS.last.shown, QS.last.all)
    end
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
    { key = "questieNpcs" }, { key = "questieObjects" }, { key = "questieRares" },
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
-- „Alle auswählen“ lässt sie aus, der Tooltip nennt es
ns.Tree.EXPLICIT.questieObjects = true
ns.Tree.GROUP_MENU.questie = QS.AddMenu
ns.Tree.ALL_MENU[#ns.Tree.ALL_MENU + 1] = QS.AddHiddenHint

local WATCH = { questieNpcs = true, questieObjects = true, questieRares = true, questieRankNormal = true,
    questieRankElite = true }

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

ns.AddStatusLine(function()
    if not QS.Wanted() then return L.STATUS_QSPAWN_OFF end
    local ok, why = QS.Available()
    if not ok then return L.STATUS_QSPAWN_MISSING:format(QS.ReasonText(why)) end
    local last = QS.last
    if last and last.result then
        local line = L.STATUS_QSPAWN_ON:format(ns.MapName(last.map), last.result.n.npc, last.result.n.object, last.shown)
        if last.result.capped or (last.all and last.all > last.shown) then line = line .. " " .. L.STATUS_QSPAWN_CAPPED end
        return line
    end
    return L.STATUS_QSPAWN_WAITING
end)
