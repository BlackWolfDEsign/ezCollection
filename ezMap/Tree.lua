local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Einstellungen der Karte als Baum (Wunsch des Nutzers vom 15.11.2026 abends, Wortlaut im ROADMAP-Index:
    „das ezmap einstellungsmenü bei karte muss refaktoriert werden, granularer sein und möglichkeit bieten alles oder
    subgruppen (z.b. lehrer) ein und auszublenden“).

    Aufbau: oben „Alles“, darunter Gruppen, darunter die einzelnen Arten (Blätter). Ein Blatt ist entweder ein
    Schalter in ezMapDB.settings (Feld key, derselbe Schalter wie vorher – Einstellungsseite, Menüs und /ezmap
    status lesen ihn weiter über ns.Enabled) oder ein dynamisches Blatt (Berufslehrer je Titel) in ezMapDB.mapFilter.
    Gruppen haben keinen eigenen Wert: ihr Zustand ergibt sich aus den Blättern darunter – „on“ (alle an), „off“ (alle
    aus) oder „mixed“ (teilweise). Eine Gruppe schalten setzt alle Blätter darunter; war sie vorher gemischt, merkt
    ezMap die Mischung (ezMapDB.mapMemory[gruppe]) und „Teilweise“ stellt sie wieder her – jeder Schalter bleibt
    einzeln gemerkt.

      Tree.Node(id) → Knoten; Tree.Children(id) → Kinder (Gruppen und Blätter, auch dynamische)
      Tree.Leaves(id) → alle Blätter darunter ({ id, key | dyn, label })
      Tree.State(id) → "on" | "off" | "mixed", Zahl an, Zahl gesamt
      Tree.Any(id) → true, wenn mindestens ein Blatt darunter an ist (dynamische Gruppe ohne Blätter: ihr Standard)
      Tree.Leaf(id) → Wert eines Blatts; Tree.SetLeaf(id, an)
      Tree.Set(id, an) → schaltet alle Blätter darunter (Gruppe oder Blatt); Tree.Restore(id) → gemerkte Mischung
      Tree.Click(id), Tree.Checked(id) → Klick und Haken einer Gruppe im Menü (an/teilweise » aus » Stand davor)
      Tree.Label(id), Tree.Tip(id), Tree.LabelWithState(id) → Texte (Gruppen „… (teilweise)“)
      Tree.Migrate() → Übernahme der alten Gruppen-Schalter (gatherPins, trainers), einmal und geprüft
      Tree.AddMenu(root, id) → dieselbe Gliederung als Untermenüs (Blizzards Menü-API über Core.Menu)
      Tree.AddSettings(page) → Abschnitt der Einstellungsseite (Gruppen als Auswahl an/aus/teilweise, Blätter als Haken)
      Tree.Icon(id) → Symbol (Icons.DEF, sonst das der Gruppe darüber), Tree.Source(id) → Quelle (graue Zeile),
      Tree.AddAllToggle(eintrag, id) → Haken „Alle“ im Untermenü einer Gruppe (Welle 27; seit 21.11.2026 einer)
      Tree.AllToggleSkipped(id) → Namen der Blätter, die „Alle“ beim Einschalten dort auslässt (nur auf Wunsch)
      Tree.AddRestore(eintrag, id) → „Teilweise wiederherstellen“, solange die Gruppe eine Mischung gemerkt hat;
      Tree.GroupTip(id) → Erklärung einer Gruppe samt „teilweise x von y“ (beide auch für Gather.BuildSection)
    Andere Dateien hängen Blätter an (Tree.Add), damit jede Funktion ihren Schalter selbst nennt.
    Seit Welle 27: ein Knoten mit hidden = fn() steht nicht im Baum, solange fn() true liefert (Tree.Hidden(id); die
    Gruppe „laut Questie“ ohne QuestieDB), Tree.ALL_MENU = { fn(root, mapID) … } ergänzt das Ende des ganzen Baums,
    und Tree.EXPLICIT nimmt auch einzelne Blätter auf; Gruppen in Tree.EXPLICIT_OWN brauchen ihren eigenen Haken auch
    unter einem ausdrücklich angeklickten Thema (Antwort des Nutzers vom 17.11.2026: „laut Questie“).
    Filtergruppen (Feld filter = true, z. B. „Nach Farbe“ unter „Sammeln“, Gather.lua): ihre Blätter wählen nicht, WAS
    erscheint, sondern sieben die Punkte der Arten daneben. Sie zählen deshalb nicht zum Zustand der Gruppen darüber
    und werden von deren Klick nicht mitgeschaltet (sonst stünde „Sammeln“ nach „Kräuter aus, Erze aus“ noch auf
    „teilweise“, und „Alles aus, dann wieder an“ ließe sie aus). Für sich selbst verhalten sie sich wie jede Gruppe.
]]
local Tree = {}
ns.Tree = Tree

-- Gruppen; Blätter mit key sind Schalter in ezMapDB.settings (OPT_<key> und OPT_<key>_TIP).
-- Seit Welle 27 (Zweig modul/ezmap-menue, Wunsch des Nutzers vom 16.11.2026 „menüaufteilung und ggf. eine
-- refactorierung sinnvoll“) fünf Themen oben: „Dienste in der Stadt“ (town), „Sammeln“ (gather), „Entdecken“
-- (discover, Entdecker-Wissen nur auf Wunsch), „Reise“ (journey), „Eigene Wegpunkte und Kartenhilfen“ (own). Die
-- Gruppen darunter behalten ihre ids (gemerkte Mischungen in ezMapDB.mapMemory bleiben gültig), die Schalter ihre
-- Schlüssel. Symbol je Knoten: Icons.DEF (Icons.lua), sonst das der Gruppe darüber (Tree.Icon); Quelle je Thema:
-- der Text TREE_SRC_<id> (Tree.Source, graue Zeile im Tooltip).
Tree.ROOT = { id = "all", children = {
    { id = "town", children = {
        { id = "trainers", children = {
            { key = "trainerClass" }, { key = "trainerPet" },
            { id = "trainerProf", dyn = true },     -- Berufslehrer je Titel (dynamisch, aus Core.Npcs)
            { key = "trainerOther" },
        } },
        { id = "vendors", children = { { key = "vendorTargets" }, { key = "repairTargets" } } },
    } },
    { id = "gather", children = { { key = "gatherHerb" }, { key = "gatherOre" }, { key = "gatherFish" } } },
    { id = "discover", children = {
        { id = "explorer", children = { { key = "gatherChest" }, { key = "bookTargets" } } },
    } },
    { id = "journey", children = {
        -- „Leiste während des Flugs“ (flightBar) steht seit der Einstellungs-Prüfung vom 19.11.2026 im Abschnitt
        -- „Flugzeiten“ der Seite: sie erscheint nicht auf der Karte
        { id = "travel", children = { { key = "flightNearest" }, { key = "flightDest" }, { key = "flightTimes" } } },
        { id = "dungeons", children = { { key = "entrancePins" }, { key = "entranceList" } } },
    } },
    { id = "own", children = { { key = "wayRecent" }, { key = "mapCoords" } } },
} }

-- Alte Gruppen-Schalter, die der Baum ablöst: Schalter » Gruppe (Tree.Migrate)
Tree.RETIRED = { gatherPins = "gather", trainers = "trainers" }
-- Blätter anderer Gruppen, die ein abgelöster Schalter ebenfalls verbarg: gatherPins aus hieß auch „keine Kisten“,
-- Kisten stehen im Baum aber unter „Entdecker-Wissen“ (Tree.Migrate merkt sie in der Mischung dieser Gruppe)
Tree.RETIRED_ALSO = { gatherPins = { group = "explorer", leaves = { "gatherChest", "gatherMiniChest" } } }

local index = {}       -- id » Knoten
local parentOf = {}    -- id » Eltern-id

local function NodeID(node) return node.id or node.key end

local function Register(node, parent)
    local id = NodeID(node)
    index[id] = node
    parentOf[id] = parent
    for _, child in ipairs(node.children or {}) do Register(child, id) end
end

local function Reindex()
    index, parentOf = {}, {}
    Register(Tree.ROOT, nil)
end
Reindex()

-- Blatt oder Gruppe anhängen: Tree.Add("gather", { key = "gatherMiniHerb" }, vor) – vor = id, vor der es steht
function Tree.Add(parent, node, before)
    local p = index[parent]
    if not (p and p.children and type(node) == "table") then return false end
    if index[NodeID(node)] then return false end
    local at = #p.children + 1
    for i, child in ipairs(p.children) do
        if before and NodeID(child) == before then at = i break end
    end
    table.insert(p.children, at, node)
    Reindex()
    return true
end

function Tree.Node(id) return index[id] end
function Tree.Parent(id) return parentOf[id] end

local function Filter()
    local db = ns.db
    if type(db) ~= "table" then return {} end
    if type(db.mapFilter) ~= "table" then db.mapFilter = {} end
    return db.mapFilter
end

local function Memory()
    local db = ns.db
    if type(db) ~= "table" then return {} end
    if type(db.mapMemory) ~= "table" then db.mapMemory = {} end
    return db.mapMemory
end

---------------------------------------------------------------------------
-- Dynamische Blätter: Berufslehrer je Titel (Core.Npcs über ns.Trainers)
---------------------------------------------------------------------------

-- Titel der besuchten Berufslehrer, die zu diesem Charakter passen → { { id, label } … } nach Titel. Nur besuchte
-- (seit 22.11.2026 bewusst): mit Questie wechselten die Blätter sonst mit Kontinent und Lesestand; Berufslehrer laut
-- Questie mit einem Titel ohne Blatt folgen der Gruppe „Berufslehrer“ (Tree.Leaf eines dynamischen Blatts).
function Tree.ProfessionTitles()
    local seen, out = {}, {}
    local T = ns.Trainers
    for _, t in ipairs(T and T.List and T.List("profession", { visited = true }) or {}) do
        local title = type(t.title) == "string" and t.title ~= "" and t.title or L.TREE_PROF_UNTITLED
        if not seen[title] then
            seen[title] = true
            out[#out + 1] = { id = "prof:" .. title, label = title, dynOf = "trainerProf" }
        end
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out
end

-- Weitere dynamische Gruppen hängen sich hier an (Welle 15b: Rezepte je Beruf, Recipes.lua):
--   Tree.DYN[gruppe] = { prefix = "rprof:", leaves = fn() → { { id, label, dynOf } … }, default = fn(id) → bool,
--                        tip = Text-Schlüssel des Blatt-Tooltips }
Tree.DYN = { trainerProf = { prefix = "prof:", leaves = function() return Tree.ProfessionTitles() end,
    tip = "TREE_PROF_LEAF_TIP",
    -- Symbol des Berufs, wenn der Titel den Namen eines bekannten Berufs enthält (Welle 27), sonst das der Gruppe
    icon = function(id) return ns.Icons and ns.Icons.ProfessionOfTitle(id:sub(6)) or nil end } }

local function DynLeaves(node)
    local d = Tree.DYN[NodeID(node)]
    if d and d.leaves then return d.leaves() end
    return {}
end

-- Gruppe eines dynamischen Blatts nach seinem Präfix („prof:Kräuterkundelehrer“ » trainerProf) oder nil
local function DynGroupOf(id)
    if type(id) ~= "string" then return nil end
    for group, d in pairs(Tree.DYN) do
        if d.prefix and id:sub(1, #d.prefix) == d.prefix then return group end
    end
    return nil
end
Tree.DynGroupOf = DynGroupOf

-- Standard eines dynamischen Blatts: was die Gruppe zuletzt für alle gesetzt hat, sonst der eigene Standard der Gruppe
-- (Rezepte: nur eigene Berufe), sonst an
local function DynDefault(group, id)
    local v = Filter()[group .. "*"]
    if v == nil then
        local d = Tree.DYN[group]
        if d and d.default and id then return d.default(id) == true end
        return true
    end
    return v == true
end

---------------------------------------------------------------------------
-- Lesen und Schreiben
---------------------------------------------------------------------------

-- Knoten mit Feld hidden = fn() → true stehen gerade nicht im Baum (Welle 27: Gruppe „laut Questie“, solange
-- QuestieDB nicht antwortet) – nicht in den Kartenmenüs, nicht im Zustand der Gruppen darüber, nicht in deren Klick.
-- Die Einstellungsseite zeigt sie trotzdem (jede Einstellung bleibt erreichbar; der Tooltip nennt die Bedingung).
local function Hidden(node)
    if type(node) ~= "table" or type(node.hidden) ~= "function" then return false end
    local ok, yes = pcall(node.hidden)
    return ok and yes == true
end
Tree.Hidden = function(id) return Hidden(index[id]) end

function Tree.Children(id)
    local node = index[id]
    if not node then return {} end
    if node.dyn then return DynLeaves(node) end
    local out = {}
    for _, child in ipairs(node.children or {}) do
        if not Hidden(child) then out[#out + 1] = child end
    end
    return out
end

local function IsGroup(node) return node ~= nil and (node.children ~= nil or node.dyn == true) end
Tree.IsGroup = function(id) return IsGroup(index[id]) end

-- Alle Blätter unter id (die id selbst, wenn sie ein Blatt ist)
function Tree.Leaves(id, out)
    out = out or {}
    local node = index[id]
    if not node then return out end
    if not IsGroup(node) then
        out[#out + 1] = node
        return out
    end
    for _, child in ipairs(Tree.Children(id)) do
        if child.dynOf then
            out[#out + 1] = child
        elseif IsGroup(child) then
            -- Filtergruppen zählen nur für sich selbst (siehe Kopf)
            if not child.filter then Tree.Leaves(NodeID(child), out) end
        else
            out[#out + 1] = child
        end
    end
    return out
end

local function LeafValue(leaf)
    if leaf.key then return ns.Enabled(leaf.key) end
    local v = Filter()[leaf.id]
    if v == nil then return DynDefault(leaf.dynOf or "", leaf.id) end
    return v == true
end

local function SetLeafValue(leaf, on)
    on = on and true or false
    if leaf.key then
        if ns.S and ns.S[leaf.key] ~= on then ns.SetSetting(leaf.key, on) end
    else
        Filter()[leaf.id] = on
    end
end

-- Wert eines Blatts (auch dynamisch: „prof:<Titel>“; unbekannte Titel folgen dem Standard ihrer Gruppe)
function Tree.Leaf(id)
    local node = index[id]
    if node and not IsGroup(node) then return LeafValue(node) end
    local group = DynGroupOf(id)
    if group then return LeafValue({ id = id, dynOf = group }) end
    return false
end

function Tree.SetLeaf(id, on)
    local node = index[id]
    if node and not IsGroup(node) then
        SetLeafValue(node, on)
    elseif DynGroupOf(id) then
        SetLeafValue({ id = id, dynOf = DynGroupOf(id) }, on)
    else
        return false
    end
    Tree.Changed(id)
    return true
end

-- Zustand: "on" | "off" | "mixed", Zahl an, Zahl gesamt. Dynamische Gruppen ohne Blätter folgen ihrem Standard.
function Tree.State(id)
    local node = index[id]
    if not node then return "off", 0, 0 end
    if not IsGroup(node) then
        local on = LeafValue(node)
        return on and "on" or "off", on and 1 or 0, 1
    end
    local leaves = Tree.Leaves(id)
    local on, total = 0, #leaves
    for _, leaf in ipairs(leaves) do
        if LeafValue(leaf) then on = on + 1 end
    end
    if total == 0 then
        local def = node.dyn and DynDefault(id) or false
        return def and "on" or "off", 0, 0
    end
    if on == total then return "on", on, total end
    if on == 0 then return "off", on, total end
    return "mixed", on, total
end

function Tree.Any(id)
    return Tree.State(id) ~= "off"
end

-- Standard der dynamischen Gruppen unter id (auch id selbst) → { [Gruppe] = true | false | "default" } („default“: noch
-- nie für alle gesetzt, es gilt der eigene Standard der Gruppe)
local function DynDefaultsOf(id, out)
    out = out or {}
    local node = index[id]
    if not node then return out end
    if node.dyn then
        local v = Filter()[id .. "*"]
        if v == nil then out[id] = "default" else out[id] = v == true end
    end
    for _, child in ipairs(node.children or {}) do DynDefaultsOf(NodeID(child), out) end
    return out
end

-- Mischung merken: { [Blatt] = Wert } für jede Gruppe auf dem Weg, dazu unter ["*"] der Standard der dynamischen
-- Gruppen darunter – eine dynamische Gruppe ohne Blätter (noch kein Berufslehrer besucht) hat nur ihn; ohne ihn bliebe
-- sie nach Aus und „Teilweise wiederherstellen“ aus (Fund der Nachprüfung vom 17.11.2026)
local function Remember(id)
    local leaves = Tree.Leaves(id)
    local mix = {}
    for _, leaf in ipairs(leaves) do mix[NodeID(leaf)] = LeafValue(leaf) end
    mix["*"] = DynDefaultsOf(id)
    Memory()[id] = mix
end

local function SetDynDefaults(id, on)
    local node = index[id]
    if not node then return end
    if node.dyn then Filter()[id .. "*"] = on and true or false end
    for _, child in ipairs(node.children or {}) do SetDynDefaults(NodeID(child), on) end
end

-- Gruppen, die nur auf ausdrücklichen Wunsch angehen (Leitlinie 11, Entscheidung „Entdecker-Wissen nur auf Wunsch“):
-- Tree.Click auf eine Gruppe darüber schaltet sie nicht mit ein, außer sie war vorher an. Seit Welle 27 auch einzelne
-- Blätter (questieRares: seltene Gegner laut Questie) – dann geht das Blatt mit keiner Gruppe darüber an.
-- Seit Welle 27 auch das Thema „Entdecken“ (discover): „Alles“ schaltet es nicht mit ein. Wer „Entdecken“ selbst
-- anklickt, wünscht es ausdrücklich: dann gehen die Gruppen direkt darunter mit an (Entdecker-Wissen) – außer denen aus
-- Tree.EXPLICIT_OWN und einzelnen Blättern aus Tree.EXPLICIT, die immer ihren eigenen Haken brauchen.
Tree.EXPLICIT = { explorer = true, discover = true }
-- Gruppen, die auch der Klick auf ein ausdrückliches Thema darüber nicht mitschaltet: die Gruppe „laut Questie“ geht
-- nicht mit „Entdecken“ oder dessen „Alle auswählen“ an (frühere Regel aus QuestieSpawns.lua – Leistung und fremdes
-- Wissen –, wiederhergestellt nach Fund 3 des code-reviewers vom 17.11.2026; Empfehlung umgesetzt, Antwort offen, Frage
-- in docs/roadmap/ezMap.md). QuestieSpawns.lua trägt ein.
Tree.EXPLICIT_OWN = {}

-- Liegt das Blatt unter einer Gruppe aus Tree.EXPLICIT, die selbst unterhalb von top steht (oder ist es selbst so
-- ein Blatt)? Eine solche Gruppe direkt unter einem top, das selbst in Tree.EXPLICIT steht, zählt nicht (siehe oben) –
-- außer sie steht in Tree.EXPLICIT_OWN.
local function UnderExplicit(leafID, top)
    if leafID ~= top and Tree.EXPLICIT[leafID] then return true end
    local p = parentOf[leafID]
    while p and p ~= top do
        if Tree.EXPLICIT[p] and (Tree.EXPLICIT_OWN[p] or not (Tree.EXPLICIT[top] and parentOf[p] == top)) then
            return true
        end
        p = parentOf[p]
    end
    return false
end
Tree.UnderExplicit = UnderExplicit

-- Zustand für das Auswahlfeld der Seite: „Alle an“ lässt die Blätter aus Tree.EXPLICIT aus (Tree.Set mit keepExplicit),
-- also zählen sie hier nur, wenn sie an sind (code-reviewer 20.11.2026: sonst sprang „Alles“ nach „Alle an“ sofort
-- auf „Teilweise“, solange Kisten und Bücher aus waren). → "on" | "off" | "mixed"
function Tree.ChoiceState(id)
    local node = index[id]
    if not (node and IsGroup(node)) then return (Tree.State(id)) end
    local plain, plainOn, explicitOn = 0, 0, false
    for _, leaf in ipairs(Tree.Leaves(id)) do
        local on = LeafValue(leaf)
        if UnderExplicit(NodeID(leaf), id) then
            if on then explicitOn = true end
        else
            plain = plain + 1
            if on then plainOn = plainOn + 1 end
        end
    end
    if plain == 0 then return (Tree.State(id)) end
    if plainOn == plain then return "on" end
    if plainOn == 0 and not explicitOn then return "off" end
    return "mixed"
end

-- Viele Schalter in einem Griff: jeder Schalter meldet seine Änderung (OnSettingChanged), und die Zuhörer bauen
-- ezCores Punkteschicht neu (Core.MapPins.Refresh holt bei offener Karte alle Anbieter sofort ab). Solange fn läuft,
-- merkt sich ezMap nur, dass neu gebaut werden soll, und baut danach genau einmal (bzw. nur die Minikarte). Die beiden
-- Felder werden nur für die Dauer dieses einen Aufrufs ersetzt und danach in jedem Fall zurückgelegt.
local batching = false
local function Batched(fn, ...)
    local P = Core.MapPins
    if batching or type(P) ~= "table" or type(P.Refresh) ~= "function" then return fn(...) end
    batching = true
    local refresh, miniRefresh = P.Refresh, P.MinimapRefresh
    local want = {}
    P.Refresh = function() want.full = true return 0 end
    if type(miniRefresh) == "function" then P.MinimapRefresh = function() want.mini = true end end
    local ok, result = pcall(fn, ...)
    P.Refresh, P.MinimapRefresh = refresh, miniRefresh
    batching = false
    if want.full then
        ns.Try("TreeRefresh", refresh)
    elseif want.mini and miniRefresh then
        ns.Try("TreeRefresh", miniRefresh)
    end
    if not ok then error(result, 0) end
    return result
end
Tree.Batched = Batched

-- Gruppe (oder Blatt) schalten: alle Blätter darunter; eine gemischte Gruppe merkt sich ihre Mischung vorher.
-- keepExplicit: beim Einschalten die Gruppen aus Tree.EXPLICIT darunter auslassen. Neu gebaut wird einmal (Batched).
local function SetNow(id, on, keepExplicit)
    local node = index[id]
    if not node then return false end
    if IsGroup(node) and Tree.State(id) == "mixed" then Remember(id) end
    for _, leaf in ipairs(Tree.Leaves(id)) do
        if not (on and keepExplicit and UnderExplicit(NodeID(leaf), id)) then SetLeafValue(leaf, on) end
    end
    SetDynDefaults(id, on)
    Tree.Changed(id)
    return true
end
function Tree.Set(id, on, keepExplicit) return Batched(SetNow, id, on, keepExplicit) end

-- Gemerkte Mischung wiederherstellen → true, wenn es eine gab. Eine Mischung von vor dem 17.11.2026 hat noch kein
-- ["*"]: dann bleibt der Standard der dynamischen Gruppen, wie er ist (das alte Verhalten), bis die Gruppe ihre nächste
-- Mischung merkt (Fund 5 des zweiten Reviews, nur vermerkt).
local function RestoreNow(id)
    local mix = Memory()[id]
    if type(mix) ~= "table" then return false end
    for _, leaf in ipairs(Tree.Leaves(id)) do
        local v = mix[NodeID(leaf)]
        if v ~= nil then SetLeafValue(leaf, v) end
    end
    if type(mix["*"]) == "table" then
        for group, v in pairs(mix["*"]) do
            local node = index[group]
            if node and node.dyn then
                if v == "default" then Filter()[group .. "*"] = nil else Filter()[group .. "*"] = v == true end
            end
        end
    end
    Tree.Changed(id)
    return true
end
function Tree.Restore(id) return Batched(RestoreNow, id) end

function Tree.HasMemory(id) return type(Memory()[id]) == "table" end

-- Klick auf eine Gruppe im Menü (Haken gesetzt, solange etwas darunter an ist): an oder teilweise » alle aus (eine
-- Mischung wird gemerkt); aus » der Zustand davor – alle an, die gemerkte Mischung oder, ohne beides, alle an außer den
-- Gruppen aus Tree.EXPLICIT. Zweimal klicken ändert also nichts, und Entdecker-Wissen geht nie ungefragt an.
-- „Alle an“ merkt sich, welche Blätter dabei waren (_wasOn[id] = { [Blatt] = true }): beim Wiedereinschalten gehen
-- Blätter aus Tree.EXPLICIT nur an, wenn sie damals dabei waren – eine Gruppe, die erst danach sichtbar wurde (Questie
-- geladen), bleibt aus (Fund des code-reviewers vor dem Merge, 16.11.2026). Ein alter Wert true (vor Welle 27) zählt
-- wie eine leere Liste: nichts aus Tree.EXPLICIT geht mit an.
local function WasOnNow(id, was)
    SetNow(id, true, true)
    if type(was) ~= "table" then return true end
    for _, leaf in ipairs(Tree.Leaves(id)) do
        local leafID = NodeID(leaf)
        if was[leafID] and UnderExplicit(leafID, id) then SetLeafValue(leaf, true) end
    end
    Tree.Changed(id)
    return true
end

-- Vor dem Ausschalten einer Gruppe merken, was der nächste Klick auf sie zurückbringt: ganz an » _wasOn[id] (welche
-- Blätter dabei waren), gemischt » die Mischung (Remember; ein alter _wasOn-Rest fällt weg). Gemeinsam für Tree.Click
-- und „Alle abwählen“ (Fund der Gegenprüfung vor dem Merge, 17.11.2026: „Alle abwählen“ vergaß die Mischung).
local function NoteBeforeOff(id)
    local mem = Memory()
    if type(mem._wasOn) ~= "table" then mem._wasOn = {} end
    local state = Tree.State(id)
    if state == "off" then return state end
    local was = nil
    if state == "on" then
        was = {}
        for _, leaf in ipairs(Tree.Leaves(id)) do was[NodeID(leaf)] = true end
    elseif IsGroup(index[id]) then
        Remember(id)
    end
    mem._wasOn[id] = was
    return state
end

function Tree.Click(id)
    if not index[id] then return false end
    local mem = Memory()
    if type(mem._wasOn) ~= "table" then mem._wasOn = {} end
    if NoteBeforeOff(id) ~= "off" then return Tree.Set(id, false) end
    local was = mem._wasOn[id]
    if was then
        mem._wasOn[id] = nil
        return Batched(WasOnNow, id, was)
    end
    if Tree.HasMemory(id) then return Tree.Restore(id) end
    return Tree.Set(id, true, true)
end

-- Haken einer Gruppe im Menü: gesetzt, solange mindestens ein Blatt darunter an ist
function Tree.Checked(id) return Tree.State(id) ~= "off" end

-- Zuhörer: fn(id) nach jeder Änderung über den Baum (für Menüs und Neuaufbau, die nicht über OnSettingChanged laufen)
local listeners = {}
function Tree.OnChanged(fn) listeners[#listeners + 1] = fn end
function Tree.Changed(id)
    for _, fn in ipairs(listeners) do ns.Try("Tree", fn, id) end
end

---------------------------------------------------------------------------
-- Texte
---------------------------------------------------------------------------

function Tree.Label(id)
    local node = index[id]
    if node and node.key then return L["OPT_" .. node.key] or node.key end
    if node and node.label then return node.label end
    local group = DynGroupOf(id)
    if group then
        local d = Tree.DYN[group]
        if d.label then return d.label(id) end
        return id:sub(#d.prefix + 1)
    end
    return L["OPT_tree_" .. tostring(id)] or tostring(id)
end

function Tree.Tip(id)
    local node = index[id]
    if node and node.key then return L["OPT_" .. node.key .. "_TIP"] end
    local group = DynGroupOf(id)
    if group then return L[Tree.DYN[group].tip or "TREE_PROF_LEAF_TIP"] end
    return L["OPT_tree_" .. tostring(id) .. "_TIP"]
end

-- Symbol eines Knotens (Welle 27): Icons.DEF[id], bei dynamischen Blättern die Angabe ihrer Gruppe (Tree.DYN[g].icon
-- = fn(id) → Angabe, z. B. das Symbol des Berufs), sonst das Symbol der nächsten Gruppe darüber, zuletzt das von
-- „Alles“ – nie leer. → Angabe für Core.Menu.IconMarkup
function Tree.Icon(id)
    local Icons = ns.Icons
    if not Icons then return nil end
    local group = DynGroupOf(id)
    if group and not index[id] then
        local d = Tree.DYN[group]
        if d and type(d.icon) == "function" then
            local ok, spec = pcall(d.icon, id)
            if ok and spec then return spec end
        end
        id = group
    end
    local cur = id
    while cur do
        local spec = Icons.For(cur)
        if spec then return spec end
        cur = parentOf[cur]
    end
    return Icons.For("all")
end

-- Quelle eines Knotens als graue Zeile (Design-System 2.7): Text TREE_SRC_<id>, sonst die der Gruppe darüber
function Tree.Source(id)
    local group = DynGroupOf(id)
    local cur = (group and not index[id]) and group or id
    while cur do
        local key = "TREE_SRC_" .. tostring(cur)
        local text = L[key]         -- ezCores Texte geben für einen fehlenden Schlüssel den Schlüssel zurück
        if type(text) == "string" and text ~= "" and text ~= key then return text end
        cur = parentOf[cur]
    end
    return nil
end

-- „Lehrer (teilweise: 3 von 5)“ für gemischte Gruppen, sonst der Name
function Tree.LabelWithState(id)
    local label = Tree.Label(id)
    if not Tree.IsGroup(id) then return label end
    local state, on, total = Tree.State(id)
    if state == "mixed" then return L.TREE_MIXED_LABEL:format(label, on, total) end
    return label
end

---------------------------------------------------------------------------
-- Übernahme der alten Gruppen-Schalter (geprüft, nichts geht verloren)
---------------------------------------------------------------------------

--[[
    Bis Welle 14 gab es zwei Gruppen-Schalter mit eigenem Wert: gatherPins (alle Sammel-Fundorte auf der Karte) und
    trainers (Lehrer im Kartenmenü). Im Baum ergibt sich eine Gruppe aus ihren Blättern. War ein alter Schalter aus,
    waren alle Arten darunter unsichtbar – die Übernahme schaltet deshalb die Blätter der Gruppe aus und merkt sich
    vorher deren Werte als Mischung der Gruppe (Auswahl „Teilweise“ stellt sie wieder her); ebenso die Blätter anderer
    Gruppen, die der Schalter mit verbarg (Tree.RETIRED_ALSO: Kisten unter „Entdecker-Wissen“). Der alte Wert bleibt in
    ezMapDB.settings liegen und steht zusätzlich in ezMapDB.mapMemory._migrated[schalter]; je Schalter genau einmal.
    → Liste der übernommenen Schalter
]]
function Tree.Migrate()
    local S = ns.S
    if type(S) ~= "table" then return {} end
    local mem = Memory()
    if type(mem._migrated) ~= "table" then mem._migrated = {} end
    local done = {}
    for key, group in pairs(Tree.RETIRED) do
        if mem._migrated[key] == nil then
            local old = S[key]
            mem._migrated[key] = old == false and "off" or "on"
            if old == false then
                Remember(group)
                for _, leaf in ipairs(Tree.Leaves(group)) do SetLeafValue(leaf, false) end
                SetDynDefaults(group, false)
                local also = Tree.RETIRED_ALSO[key]
                local on = {}
                for _, id in ipairs(also and also.leaves or {}) do
                    local leaf = index[id]
                    if leaf and not IsGroup(leaf) and LeafValue(leaf) then on[#on + 1] = leaf end
                end
                if #on > 0 then
                    Remember(also.group)
                    for _, leaf in ipairs(on) do SetLeafValue(leaf, false) end
                end
            end
            done[#done + 1] = key
        end
    end
    table.sort(done)
    return done
end

---------------------------------------------------------------------------
-- Menü: dieselbe Gliederung als Untermenüs (Blizzards Menü-API über Core.Menu)
---------------------------------------------------------------------------

local function Tip(entry, title, text, source) return ns.MapButton.Tip(entry, title, text, source) end
local function WithIcon(entry, id) return ns.Icons.Apply(entry, Tree.Icon(id)) end
-- Ergänzungen an einer Gruppe (GROUP_BEFORE, GROUP_MENU) und am Ende des Baums (ALL_MENU) bekommen ihr Symbol über eine
-- Hülle: jeder Eintrag das der Gruppe, Hilfszeilen das Hinweis-Symbol – ein eigenes Symbol der Ergänzung gilt davor
-- (Fund des code-reviewers vom 17.11.2026: jeder Eintrag mit Symbol)
local function IconRoot(root, id) return ns.Icons.Root(root, Tree.Icon(id)) end

-- Ergänzungen im Menü: Tree.LEAF_MENU[blatt] = fn(root, mapID) baut den Eintrag eines Blatts selbst (z. B. die
-- Sammel-Arten mit „Wann zeigen“); Tree.GROUP_BEFORE[gruppe] bzw. Tree.GROUP_MENU[gruppe] = fn(eintrag, mapID) hängt
-- vor bzw. nach den Blättern etwas an das Untermenü einer Gruppe
Tree.LEAF_MENU = {}
Tree.GROUP_BEFORE = {}
Tree.GROUP_MENU = {}

local function GroupTip(id)
    local tip = Tree.Tip(id) or ""
    local state, on, total = Tree.State(id)
    if state == "mixed" then tip = tip .. "\n\n" .. L.TREE_MIXED_TIP:format(on, total) end
    return tip
end
-- auch für den Abschnitt „Sammel-Fundorte“ im ezMap-Knopf (Gather.BuildSection; Gegenprüfung vom 18.11.2026)
Tree.GroupTip = GroupTip

-- „Teilweise wiederherstellen“ einer Gruppe, solange sie sich eine Mischung gemerkt hat → Eintrag oder nil
function Tree.AddRestore(entry, id)
    if not Tree.HasMemory(id) then return nil end
    return ns.Icons.Apply(Tip(Core.Menu.Button(entry, L.TREE_RESTORE, function() Tree.Restore(id) end), L.TREE_RESTORE,
        L.TREE_RESTORE_TIP), "menuRestore")
end

-- Haken „Alle“ im Untermenü einer Gruppe (Design-System 2.11: ab drei Einträgen derselben Art, direkt unter dem Kopf
-- der Gruppe, vor den einzelnen Haken; Welle 27, seit dem 21.11.2026 ein Haken statt „Alle auswählen / Alle
-- abwählen“). Schaltet die Blätter darunter wie der Klick auf die Gruppe: Einschalten lässt aus, was nur auf ausdrücklichen Wunsch angeht (UnderExplicit – unter einem
-- Thema aus Tree.EXPLICIT wie „Entdecken“ gehen dessen Gruppen mit an, nicht aber Gruppen aus Tree.EXPLICIT_OWN („laut
-- Questie“) und Blätter wie „Objekte“ und „seltene Gegner laut Questie“; der Tooltip nennt sie, Fund der Gegenprüfung
-- 17.11.2026 und Antwort des Nutzers vom selben Tag), Filtergruppen zählen nicht mit; die Punkteschicht
-- baut einmal neu (Batched). Wie beim Klick merkt sich die Gruppe vor dem Schalten ihre Mischung (bzw. vor dem
-- Ausschalten, welche Blätter an waren): ein Klick auf die Gruppe selbst bringt den Stand davor zurück. Die Auswahl
-- bleibt gemerkt (dieselben Schalter in ezMapDB.settings bzw. ezMapDB.mapFilter, Design-System 2.12).
-- → der Haken (zweimal, wie Core.Menu.AllToggle) oder nil (weniger als drei Blätter)
Tree.ALL_TOGGLE_MIN = 3

-- Namen der Blätter, die „Alle“ beim Einschalten in dieser Gruppe auslässt → Liste (leer, wenn keins). Liegt ein Blatt unter
-- einer Gruppe aus Tree.EXPLICIT_OWN, steht deren Name einmal da („Gegner und Objekte laut Questie“ statt jedes Blatts).
function Tree.AllToggleSkipped(id)
    local out, seen = {}, {}
    for _, leaf in ipairs(Tree.Leaves(id)) do
        local leafID = NodeID(leaf)
        if UnderExplicit(leafID, id) then
            local name = Tree.Label(leafID)
            local p = parentOf[leafID]
            while p and p ~= id do
                if Tree.EXPLICIT_OWN[p] then name = Tree.Label(p) end
                p = parentOf[p]
            end
            if not seen[name] then
                seen[name] = true
                out[#out + 1] = name
            end
        end
    end
    return out
end

function Tree.AddAllToggle(entry, id)
    local Menu = Core.Menu
    if type(Menu.AllToggle) ~= "function" or not index[id] then return nil end
    if #Tree.Leaves(id) < Tree.ALL_TOGGLE_MIN then return nil end
    local function List() return Tree.Leaves(id) end
    -- Tree.Changed läuft innerhalb von Batched: ein Zuhörer, der selbst neu zeichnet (Rezepte), zählt in denselben einen
    -- Neuaufbau (Fund des code-reviewers vom 17.11.2026; vorher zweimal).
    -- Neue Berufe (dynamische Blätter, die erst später erscheinen) folgen der letzten Wahl, wie beim Klick auf die Gruppe:
    -- der Standard wird VOR Tree.Changed gesetzt, und ein geänderter Standard meldet auch dann, wenn kein Blatt
    -- umschaltet (Fund 1 des zweiten Reviews vom 17.11.2026: vorher setzte ezCores opts.after ihn erst nach der
    -- Meldung – gekoppelt sah Blizzards „Berufsausbilder“ bei Berufslehrern ohne Blätter noch den alten Stand).
    local function Wrap(on)
        return function(fn)
            if on then
                if IsGroup(index[id]) and Tree.State(id) == "mixed" then Remember(id) end
            else
                NoteBeforeOff(id)
            end
            return Batched(function()
                local before = DynDefaultsOf(id)
                for group in pairs(before) do before[group] = DynDefault(group) end
                local n = fn()
                SetDynDefaults(id, on)
                local changed = n and n > 0
                for group, was in pairs(before) do
                    if DynDefault(group) ~= was then changed = true end
                end
                if changed then Tree.Changed(id) end
                return n
            end)
        end
    end
    local skipped = Tree.AllToggleSkipped(id)
    local tip = #skipped > 0 and L.TREE_ALL_TIP_SKIP:format(table.concat(skipped, ", ")) or L.TREE_ALL_TIP
    -- ein Haken „Alle“ (seit 21.11.2026; vorher zwei Einträge mit Häkchen und Kreuz): Einschalten lässt die Blätter aus,
    -- die nur mit eigenem Haken angehen (onSkip), Ausschalten nimmt alle heraus
    local on, off = Menu.AllToggle(entry, List, LeafValue, SetLeafValue,
        { tip = tip, onWrap = Wrap(true), offWrap = Wrap(false),
          onSkip = function(leaf) return UnderExplicit(NodeID(leaf), id) end })
    return on, off
end

function Tree.AddMenu(root, id, mapID)
    local Menu = Core.Menu
    local node = index[id]
    if not node then return nil end
    if not IsGroup(node) then
        local leafID = NodeID(node)
        local label = Tree.Label(leafID)
        local build = Tree.LEAF_MENU[leafID]
        if build then return WithIcon(build(root, mapID), leafID) end
        return WithIcon(Tip(Menu.Toggle(root, label, function() return Tree.Leaf(leafID) end,
            function(on) Tree.SetLeaf(leafID, on) end), label, Tree.Tip(leafID), Tree.Source(leafID)), leafID)
    end
    local label = Tree.LabelWithState(id)
    -- Klick auf die Gruppe: Tree.Click (an oder teilweise » aus; aus » der Zustand davor)
    local entry = Menu.Toggle(root, label, function() return Tree.Checked(id) end, function() Tree.Click(id) end)
    Tip(entry, label, GroupTip(id), Tree.Source(id))
    WithIcon(entry, id)
    Tree.AddRestore(entry, id)
    local before = Tree.GROUP_BEFORE[id]
    if before then before(IconRoot(entry, id), mapID) end
    Tree.AddAllToggle(entry, id)
    local children = Tree.Children(id)
    if node.dyn and #children == 0 then
        ns.Icons.Apply(Tip(Menu.Title(entry, L.TREE_DYN_NONE), L.TREE_DYN_NONE, L.TREE_DYN_NONE_TIP), "info")
    end
    for _, child in ipairs(children) do
        if child.dynOf then
            local cid = child.id
            WithIcon(Tip(Menu.Toggle(entry, child.label, function() return Tree.Leaf(cid) end,
                function(on) Tree.SetLeaf(cid, on) end), child.label, Tree.Tip(cid) or L.TREE_PROF_LEAF_TIP,
                Tree.Source(cid)), cid)
        else
            Tree.AddMenu(entry, NodeID(child), mapID)
        end
    end
    local extra = Tree.GROUP_MENU[id]
    if extra then extra(IconRoot(entry, id), mapID) end
    return entry
end

-- Ganzer Baum in einem Menü (Blizzards Kartenfilter bzw. ezMap-Knopf): „Alles“ und die Gruppen darunter
-- Aufbau seit Welle 27: „Alles“, darunter die fünf Themen als Untermenüs (Symbol und Quelle je Eintrag), dann die
-- Ergänzungen (Tree.ALL_MENU) und am Ende „Einstellungen“ – außer mit opts.noSettings (der Baum als Untermenü des
-- ezMap-Knopfs, dessen Menü „Einstellungen“ schon selbst am Ende hat; Fund der Gegenprüfung 17.11.2026).
function Tree.AddAll(root, mapID, opts)
    local Menu = Core.Menu
    local label = Tree.LabelWithState("all")
    WithIcon(Tip(Menu.Toggle(root, label, function() return Tree.Checked("all") end, function() Tree.Click("all") end),
        label, GroupTip("all")), "all")
    if Tree.HasMemory("all") then
        ns.Icons.Apply(Tip(Menu.Button(root, L.TREE_RESTORE_ALL, function() Tree.Restore("all") end), L.TREE_RESTORE_ALL,
            L.TREE_RESTORE_TIP), "menuRestore")
    end
    -- opts.skip = { [Gruppe] = true }: Gruppen, die das Menü an anderer Stelle schon hat (ezMap-Knopf: „Sammeln“)
    local skip = type(opts) == "table" and type(opts.skip) == "table" and opts.skip or nil
    for _, child in ipairs(Tree.Children("all")) do
        local id = NodeID(child)
        if not (skip and skip[id]) then Tree.AddMenu(root, id, mapID) end
    end
    for _, fn in ipairs(Tree.ALL_MENU) do ns.Try("TreeMenu", fn, ns.Icons.Root(root, "info"), mapID) end
    if type(opts) == "table" and opts.noSettings then return end
    Menu.Divider(root)
    ns.MapButton.AddSettings(root)
end

-- Ergänzungen am Ende des ganzen Baums: fn(root, mapID) – z. B. der Hinweis, warum eine verborgene Gruppe fehlt
Tree.ALL_MENU = {}

---------------------------------------------------------------------------
-- Einstellungsseite: Gruppen als Auswahl (an, aus, teilweise), Blätter als Haken, eingerückt unter ihrer Gruppe
---------------------------------------------------------------------------

local STATES = { "on", "off", "mixed" }

local function Indent(row, parentRow)
    if type(row) == "table" and type(parentRow) == "table" and type(row.SetParentInitializer) == "function" then
        pcall(row.SetParentInitializer, row, parentRow, function() return true end)
    end
end

local function AddSettingsNode(page, id, parentRow)
    local node = index[id]
    if not node then return end
    if not IsGroup(node) then
        if node.key then
            local _, row = page:Checkbox(node.key)
            Indent(row, parentRow)
        end
        return
    end
    local values = {}
    -- Das Auswahlfeld zeigt den ZUSTAND der Gruppe, keine Handlung: „Alle an“, „Alle aus“, „Teilweise“ (Texte
    -- TREE_STATE_on, _off, _mixed). Vorher standen hier die Handlungswörter „Alle auswählen“/„Alle abwählen“ – eine ganz eingeschaltete Gruppe zeigte
    -- dann „Alle abwählen“, und Auswahl und Kästchen darunter passten nicht zusammen (Spielbefund des Nutzers vom
    -- 19.11.2026, Bild „Karte: was zeigen“). Die Handlungswörter bleiben den Einträgen „Alle auswählen / Alle abwählen“
    -- im Menü (Tree.AddAllToggle, Design-System 2.11).
    for _, state in ipairs(STATES) do
        values[#values + 1] = { state, L["TREE_STATE_" .. state] }
    end
    local _, row = page:ProxyDropdown("tree", values, function() return Tree.ChoiceState(id) end,
        function(state)
            -- „Alle auswählen“ lässt Gruppen und Blätter aus Tree.EXPLICIT darunter aus (wie der Klick im Menü; Fund
            -- des code-reviewers vor dem Merge) – sie haben eigene Zeilen auf der Seite
            if state == "mixed" then Tree.Restore(id) else Tree.Set(id, state == "on", true) end
        end, { label = Tree.Label(id), tooltip = Tree.Tip(id), id = id })
    Indent(row, parentRow)
    if node.dyn then return end
    for _, child in ipairs(node.children or {}) do AddSettingsNode(page, NodeID(child), row) end
end

function Tree.AddSettings(page)
    page:Header(L.OPT_HEADER_TREE, L.OPT_HEADER_TREE_TIP)
    AddSettingsNode(page, "all", nil)
end

-- /ezmap status: welche Gruppen aus bzw. teilweise sind (nichts, wenn alles an ist). Seit Welle 27 mit Themen: ein
-- Thema, das nur Gruppen enthält („Dienste in der Stadt“, „Entdecken“, „Reise“) und teilweise an ist, nennt die
-- Gruppen darunter – wie vorher „Lehrer aus“ statt „Dienste in der Stadt teilweise“.
local function OnlyGroups(id)
    local children = Tree.Children(id)
    if #children == 0 or index[id].dyn then return false end
    for _, child in ipairs(children) do
        if child.dynOf or not IsGroup(child) then return false end
    end
    return true
end

function Tree.StatusLine()
    local off, mixed = {}, {}
    local function Walk(id)
        for _, child in ipairs(Tree.Children(id)) do
            local cid = NodeID(child)
            if IsGroup(child) and not child.filter and not child.dynOf then
                local state = Tree.State(cid)
                if state == "off" then
                    off[#off + 1] = Tree.Label(cid)
                elseif state == "mixed" then
                    if OnlyGroups(cid) then Walk(cid) else mixed[#mixed + 1] = Tree.Label(cid) end
                end
            end
        end
    end
    Walk("all")
    if #off == 0 and #mixed == 0 then return nil end
    return L.STATUS_TREE:format(#off > 0 and table.concat(off, ", ") or L.STATUS_TREE_NONE,
        #mixed > 0 and table.concat(mixed, ", ") or L.STATUS_TREE_NONE)
end
ns.AddStatusLine(function() return Tree.StatusLine() end)

ns.OnReady(function()
    local done = Batched(Tree.Migrate)
    if #done > 0 then ns.Try("TreeMigrate", Tree.Changed, "all") end
end)
