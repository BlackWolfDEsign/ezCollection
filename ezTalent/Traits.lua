local _, ns = ...
local Core = ezCore

--[[
    Gemeinsamer Trait-Kern für Klassentalente UND Vermächtnis (Leitlinie 2: ein Kern, zwei Baumarten).
    Quelle: Blizzards Forever-Oberfläche (Gethe/wow-ui-source, Zweig forever) – Blizzard_PlayerSpells/Camelot/ClassTalents
    (Konfiguration je Spezialisierungsgruppe über C_SpecializationInfo.GetCombatConfigIDForSpecGroup, Bäume als Gruppen
    mit eigener Punktzahl über C_Traits.GetGroupDisplayInfoByTreeID/GetGroupCurrencyInfo) und Blizzard_LegacySystem
    (Bäume aus Constants.LegacyConsts, Konfiguration über C_Traits.GetConfigIDByTreeID, Punkte über GetTreeCurrencyInfo).

    Jeder Aufruf an den Client läuft geschützt (Core.Call): fehlt C_Traits oder eine Funktion, liefert der Kern leere
    Listen bzw. nil. Gelesen wird nur; geschrieben wird ausschließlich gestaffelt (PurchaseRank, SetSelection,
    ResetTree) – bestätigt wird mit Blizzards eigenem Knopf, nie von ezTalent (Leitlinie 1 und 5).

      Traits.Available()                   → C_Traits da?
      Traits.ClassConfigID()               → Konfiguration der aktiven Spezialisierung
      Traits.TreeOfConfig(configID)        → erster Baum der Konfiguration
      Traits.LegacyTrees()                 → { { key, treeID } } (nur, was Constants.LegacyConsts nennt)
      Traits.LegacyConfigID(treeID)
      Traits.Node(configID, nodeID)        → schlichte Kopie: { id, purchased, current, active, max, entry, entries,
                                             choice, x, y, canPurchase, groups, conditions, edges }
      Traits.Condition(configID, condID)   → Bedingung als Kopie (Schwelle, Stufe, Text des Clients)
      Traits.Incoming(nodes)               → { [Knoten] = { { from, kind, active } } } – Vorgänger je Knoten
      Traits.Requirements(configID, treeID, node) → was dem Knoten im Client gerade fehlt (für „fehlt“)
      Traits.Needs(configID, treeID, node) → seine Schwellen mit Stand (für die Auswirkungen)
      Traits.Nodes(configID, treeID)       → Liste dieser Kopien, von oben nach unten
      Traits.Snapshot(configID, treeID, committed) → { nodes = { [nodeID] = Ränge }, choices = { [nodeID] = entryID } }
      Traits.Groups(configID, treeID)      → { { id, name, icon, spent } } (Talentbäume 1–3 einer Klasse)
      Traits.PrimaryTree(groups)           → Nummer des Baums mit den meisten Punkten (nil ohne Punkte)
      Traits.Currency(configID, treeID)    → frei, ausgegeben, gesamt
      Traits.HasStaged(configID)
      Traits.Entry(configID, entryID, rank) → { name, text, spellID, overridden, icon } – Texte aus dem Client
      Traits.EntryName(configID, entryID)  → nur der Name (zwischengespeichert; für die Zuordnung der Vorauswahl)
      Traits.EntrySpell(configID, entryID) → Zauber-ID der Definition (zwischengespeichert) – sprachunabhängig
      Traits.Layout(configID, treeID)      → { [nodeID] = { tree, row, col, aside } } – Lage im Baum, sprachunabhängig
                                             (aside = true: Knoten liegt weit abseits des Baums)
      Traits.Grid(values)                  → Rasterzahl je Lage und welche Lagen abseits liegen (für Layout und
                                             Tests/survey2ids.lua)
      Traits.CanReset(configID, treeID)    → true oder false, Grund ("combat", "noapi", "noconfig", "norefund")
      Traits.Committing(frame)             → läuft an Blizzards Talentfenster gerade die Bestätigung (CommitConfig)?
      Traits.Reset(configID, treeID, byCurrency) → gestaffelt zurücksetzen (wie Blizzards Knopf), true bei Erfolg;
                                             false, "partial", wenn nur ein Teil der Währungen zurückgesetzt wurde
      Traits.OrderSteps(tpl)               → Schritte der Reihenfolge einer Vorlage { { id, rank } } (Zielrang je Schritt)
      Traits.ByPosition(a, b)              → Sortierung „von oben nach unten, dann von links“ (wie Traits.Apply setzt)
      Traits.Apply(configID, treeID, tpl, opts) → Ergebnis { bought, missing, extra, unknown, reset } oder nil, Grund
]]

local Traits = {}
ns.Traits = Traits

local function Api() return rawget(_G, "C_Traits") end

local function Call(name, ...)
    local api = Api()
    if type(api) ~= "table" then return nil end
    return Core.Call(api[name], ...)
end

local function Num(v) return Core.Num(v) end

function Traits.Available()
    local api = Api()
    return type(api) == "table" and type(api.GetNodeInfo) == "function" and type(api.GetTreeNodes) == "function"
end

---------------------------------------------------------------------------
-- Konfigurationen und Bäume
---------------------------------------------------------------------------

-- Aktive Spezialisierungsgruppe (1 oder 2).
function Traits.ActiveSpecGroup()
    local spec = rawget(_G, "C_SpecializationInfo")
    local group = spec and Num(Core.Call(spec.GetActiveSpecGroup))
    if not group then group = Num(Core.Call(rawget(_G, "GetActiveTalentGroup"))) end
    return group or 1
end

function Traits.ClassConfigID()
    local spec = rawget(_G, "C_SpecializationInfo")
    local id = spec and Num(Core.Call(spec.GetCombatConfigIDForSpecGroup, Traits.ActiveSpecGroup()))
    if id then return id end
    local talents = rawget(_G, "C_ClassTalents")
    return talents and Num(Core.Call(talents.GetActiveConfigID)) or nil
end

function Traits.TreeOfConfig(configID)
    if not configID then return nil end
    local info = Call("GetConfigInfo", configID)
    local trees = type(info) == "table" and info.treeIDs
    return type(trees) == "table" and Num(trees[1]) or nil
end

-- Vermächtnis-Bäume in Blizzards Reihenfolge (Blizzard_LegacySystemConstants: Berufe, Abenteuer, Einfallsreichtum).
Traits.LEGACY = {
    { key = "professions", const = "LEGACY_TREE_PROFESSIONS_ID" },
    { key = "adventure", const = "LEGACY_TREE_ADVENTURE_ID" },
    { key = "progression", const = "LEGACY_TREE_PROGRESSION_ID" },
}

local function LegacyConsts()
    local constants = rawget(_G, "Constants")
    local legacy = type(constants) == "table" and rawget(constants, "LegacyConsts")
    return type(legacy) == "table" and legacy or nil
end

function Traits.LegacyTrees()
    local list, consts = {}, LegacyConsts()
    if not consts then return list end
    for _, tree in ipairs(Traits.LEGACY) do
        local id = Num(consts[tree.const])
        if id then list[#list + 1] = { key = tree.key, treeID = id } end
    end
    return list
end

-- Schlüssel ("adventure" …) zu einer Baum-ID, sonst nil – sagt auch: Ist das ein Vermächtnis-Baum?
function Traits.LegacyKey(treeID)
    for _, tree in ipairs(Traits.LegacyTrees()) do
        if tree.treeID == treeID then return tree.key end
    end
    return nil
end

function Traits.LegacyConfigID(treeID)
    return treeID and Num(Call("GetConfigIDByTreeID", treeID)) or nil
end

---------------------------------------------------------------------------
-- Knoten
---------------------------------------------------------------------------

function Traits.NodeIDs(treeID)
    local ids = treeID and Call("GetTreeNodes", treeID)
    local list = {}
    if type(ids) ~= "table" then return list end
    for _, id in ipairs(ids) do
        id = Num(id)
        if id then list[#list + 1] = id end
    end
    return list
end

-- Schlichte Kopie der Knotendaten (nie Blizzards Tabelle weiterreichen). purchased = gekaufte Ränge samt gestaffelten,
-- current = Rang in der Vorschau, active = bestätigter Rang.
function Traits.Node(configID, nodeID)
    local info = configID and nodeID and Call("GetNodeInfo", configID, nodeID)
    if type(info) ~= "table" or Num(info.ID) == 0 then return nil end
    local entries = {}
    if type(info.entryIDs) == "table" then
        for _, e in ipairs(info.entryIDs) do
            e = Num(e)
            if e then entries[#entries + 1] = e end
        end
    end
    local groups = {}
    if type(info.groupIDs) == "table" then      -- Talentbäume (Gruppen), zu denen der Knoten gehört
        for _, g in ipairs(info.groupIDs) do
            g = Num(g)
            if g then groups[#groups + 1] = g end
        end
    end
    local active = type(info.activeEntry) == "table" and Num(info.activeEntry.entryID) or nil
    local current = Num(info.currentRank) or 0
    local conditions = {}
    if type(info.conditionIDs) == "table" then  -- Bedingungen (Schwellen, Stufe …), gelesen über Traits.Condition
        for _, c in ipairs(info.conditionIDs) do
            c = Num(c)
            if c then conditions[#conditions + 1] = c end
        end
    end
    local edges = {}
    if type(info.visibleEdges) == "table" then  -- Kanten zum Nachfolger (Voraussetzung „erst dieses Talent“)
        for _, e in ipairs(info.visibleEdges) do
            local target = type(e) == "table" and Num(e.targetNode)
            if target then edges[#edges + 1] = { target = target, kind = Num(e.type), active = Core.Plain(e.isActive) == true } end
        end
    end
    return {
        id = nodeID,
        purchased = Num(info.ranksPurchased) or current,
        current = current,
        active = Num(info.activeRank) or current,
        max = Num(info.maxRanks) or 1,
        entry = active or entries[1],
        entries = entries,
        choice = #entries > 1,
        x = Num(info.posX) or 0,
        y = Num(info.posY) or 0,
        canPurchase = info.canPurchaseRank == true,
        visible = info.isVisible ~= false,
        groups = groups,
        conditions = conditions,
        edges = edges,
    }
end

---------------------------------------------------------------------------
-- Bedingungen und Kanten (TL-09, TL-10): Schwellen („benötigt 10 Punkte im Baum“), Stufe, Vorgänger
-- Quelle: Blizzards Forever-Oberfläche (Gethe/wow-ui-source, Zweig forever), nachgelesen am 15.11.2026:
--   Blizzard_APIDocumentationGenerated/SharedTraitsDocumentation.lua – TraitNodeInfo.conditionIDs/visibleEdges,
--   C_Traits.GetConditionInfo(configID, condID) → TraitCondInfo (isMet, isAlwaysMet, isGate, isSufficient, type,
--   playerLevel, traitCurrencyID, spentAmountRequired …); TraitOutEdgeInfo { targetNode, type, isActive }
--   TraitConstantsDocumentation.lua – Enum.TraitEdgeType (SufficientForAvailability 2, RequiredForAvailability 3),
--   Enum.TraitConditionType (Available 0, Visible 1, Granted 2, Increased 3, DisplayError 4, RanksAllowed 5)
--   Blizzard_SharedTalentUI/Blizzard_SharedTalentFrame.lua – GetAndCacheCondInfo reicht ignoreFontColor und den
--   Baumnamen an GetConditionInfo weiter, AddConditionsToTooltip zeigt condInfo.tooltipText ungedeckter Bedingungen
-- Gelesen wird nur; alles als schlichte Kopie. Liefert der Client nichts, bleiben die Listen leer und ezTalent sagt
-- weiter nur „Voraussetzung, Stufe oder zu wenig Punkte“.
---------------------------------------------------------------------------

local function EnumValue(enumName, key, fallback)
    local enum = rawget(_G, "Enum")
    local list = type(enum) == "table" and rawget(enum, enumName)
    return type(list) == "table" and Num(list[key]) or fallback
end

Traits.EDGE = {
    sufficient = EnumValue("TraitEdgeType", "SufficientForAvailability", 2),
    required = EnumValue("TraitEdgeType", "RequiredForAvailability", 3),
}
Traits.COND = {
    available = EnumValue("TraitConditionType", "Available", 0),
    ranksAllowed = EnumValue("TraitConditionType", "RanksAllowed", 5),
}

-- Bedingung als schlichte Kopie: { id, met, always, gate, sufficient, kind, level, currency, spent, text } oder nil.
-- text: Blizzards eigener Text der Bedingung ohne Farbe (wie im Talent-Tooltip), sonst nil.
function Traits.Condition(configID, condID)
    local info = configID and condID and Call("GetConditionInfo", configID, condID, true)
    if type(info) ~= "table" then return nil end
    local text = Core.Plain(info.tooltipText)
    text = type(text) == "string" and Core.PlainText(text) or nil
    if text == "" then text = nil end
    local spent = Num(info.spentAmountRequired)
    return {
        id = condID,
        met = Core.Plain(info.isMet) == true,
        always = Core.Plain(info.isAlwaysMet) == true,
        gate = Core.Plain(info.isGate) == true,
        sufficient = Core.Plain(info.isSufficient) == true,
        kind = Num(info.type),
        level = Num(info.playerLevel),
        currency = Num(info.traitCurrencyID),
        spent = (spent and spent > 0) and spent or nil,
        text = text,
    }
end

-- Zählt die Bedingung für „darf ich das setzen?“ (nicht Sichtbarkeit, geschenkte oder erhöhte Ränge)?
local function Restricts(cond)
    if not cond or cond.always then return false end
    return cond.kind == nil or cond.kind == Traits.COND.available or cond.kind == Traits.COND.ranksAllowed
end
Traits.Restricts = Restricts

-- Eingehende Kanten je Knoten aus den Kanten der Vorgänger: { [Ziel] = { { from, kind, active } } }.
function Traits.Incoming(nodes)
    local incoming = {}
    for _, node in ipairs(nodes or {}) do
        for _, e in ipairs(node.edges or {}) do
            incoming[e.target] = incoming[e.target] or {}
            table.insert(incoming[e.target], { from = node.id, kind = e.kind, active = e.active })
        end
    end
    return incoming
end

-- Ausgegebene Punkte in dem Talentbaum (Gruppe), zu dem der Knoten gehört; ohne Gruppe im ganzen Baum.
local function SpentFor(configID, treeID, node)
    for _, g in ipairs(Traits.Groups(configID, treeID)) do
        for _, id in ipairs(node.groups or {}) do
            if id == g.id then return g.spent end
        end
    end
    local _, spent = Traits.Currency(configID, treeID)
    return spent
end

-- Was einem Knoten im Client gerade fehlt: { { kind = "spent" | "level" | "edge" | "other", need, have, from, text } }
-- (ungedeckte Bedingungen und Vorgänger, deren Kante nicht aktiv ist). incoming (freiwillig): Traits.Incoming.
function Traits.Requirements(configID, treeID, node, incoming)
    local out = {}
    if type(node) ~= "table" then return out end
    for _, condID in ipairs(node.conditions or {}) do
        local cond = Traits.Condition(configID, condID)
        if Restricts(cond) and not cond.met then
            if cond.spent then
                out[#out + 1] = { kind = "spent", need = cond.spent, have = SpentFor(configID, treeID, node), text = cond.text }
            elseif cond.level then
                out[#out + 1] = { kind = "level", need = cond.level, text = cond.text }
            elseif cond.text then
                out[#out + 1] = { kind = "other", text = cond.text }
            end
        end
    end
    if incoming == nil then incoming = Traits.Incoming(Traits.Nodes(configID, treeID)) end
    local sufficient, sufficientMet = nil, false
    for _, e in ipairs(incoming[node.id] or {}) do
        if e.kind == Traits.EDGE.required and not e.active then
            out[#out + 1] = { kind = "edge", from = e.from }
        elseif e.kind == Traits.EDGE.sufficient then
            sufficient = sufficient or e.from
            if e.active then sufficientMet = true end
        end
    end
    if sufficient and not sufficientMet then out[#out + 1] = { kind = "edge", from = sufficient } end
    return out
end

-- Alle einschränkenden Bedingungen eines Knotens mit Stand (für die Auswirkungen): { { text, met } }; Text wie
-- Traits.RequirementText.
function Traits.Needs(configID, treeID, node)
    local out = {}
    for _, condID in ipairs(type(node) == "table" and node.conditions or {}) do
        local cond = Traits.Condition(configID, condID)
        if Restricts(cond) and (cond.spent or cond.level or cond.text) then
            local req = { kind = cond.spent and "spent" or cond.level and "level" or "other", need = cond.spent or cond.level,
                text = cond.text }
            if cond.spent and not cond.met then req.have = SpentFor(configID, treeID, node) end
            out[#out + 1] = { text = Traits.RequirementText(configID, req), met = cond.met }
        end
    end
    return out
end

-- Eine Voraussetzung als Text: Blizzards eigener Text, sonst „benötigt n Punkte im Baum (hat k)“, „ab Stufe n“,
-- „benötigt zuerst <Talent>“.
function Traits.RequirementText(configID, req)
    local L = ns.L
    if type(req) ~= "table" then return "" end
    if req.kind == "edge" then return L.REQ_EDGE:format(Traits.NodeName(configID, req.from)) end
    local text = req.text
    if not text then
        if req.kind == "spent" then text = L.REQ_SPENT:format(req.need or 0)
        elseif req.kind == "level" then text = L.REQ_LEVEL:format(req.need or 0)
        else text = L.REQ_OTHER end
    end
    if req.kind == "spent" and req.have then text = text .. " " .. L.REQ_HAVE:format(req.have) end
    return text
end

local function ByPosition(a, b)
    if a.y ~= b.y then return a.y < b.y end
    if a.x ~= b.x then return a.x < b.x end
    return a.id < b.id
end
Traits.ByPosition = ByPosition

function Traits.Nodes(configID, treeID)
    local list = {}
    for _, id in ipairs(Traits.NodeIDs(treeID)) do
        local node = Traits.Node(configID, id)
        if node then list[#list + 1] = node end
    end
    table.sort(list, ByPosition)
    return list
end

-- Verteilung als Momentaufnahme. committed = true: nur Bestätigtes (ohne Vorschau).
function Traits.Snapshot(configID, treeID, committed)
    local snap = { nodes = {}, choices = {}, tree = treeID }
    for _, node in ipairs(Traits.Nodes(configID, treeID)) do
        local rank = committed and node.active or node.purchased
        if rank > 0 then
            snap.nodes[node.id] = rank
            if node.choice and node.entry then snap.choices[node.id] = node.entry end
        end
    end
    return snap
end

-- Summe der Ränge einer Momentaufnahme bzw. Vorlage.
function Traits.Points(snap)
    local n = 0
    for _, rank in pairs(type(snap) == "table" and snap.nodes or {}) do n = n + (tonumber(rank) or 0) end
    return n
end

---------------------------------------------------------------------------
-- Lage im Baum (sprachunabhängig): Talentbaum, Zeile, Spalte
-- Blizzards posX/posY sind Lagen auf der Zeichenfläche (Blizzard_SharedTalentFrame.lua, Zweig forever:
-- UpdateTalentButtonPosition → TalentButtonUtil.ApplyPosition(button, frame, nodeInfo.posX, nodeInfo.posY)), keine
-- Rasterzahlen. Zeile und Spalte zählt ezTalent deshalb selbst, je Talentbaum aus den Lagen des Clients (Traits.Grid);
-- oben links steht (1, 1), eine leere Zeile oder Spalte bleibt eine Lücke in der Zählung.
-- Erhebung des Nutzers vom 15.11.2026 (deutscher Client, Build 70938): Der Client legt nicht jeden Knoten genau aufs
-- Raster. Beim Hexenmeister (Gebrechen) liegen Knoten derselben Zeile um ein Sechzigstel eines Rasterschritts
-- versetzt; der kleinste Abstand zweier Lagen war damit kein Rasterschritt mehr, und die Zählung ergab Zeilen wie 62,
-- 121, 122, 182. Dazu stehen in manchen Bäumen einzelne Knoten weit abseits (Jäger: Überleben Spalte 157, Treffsicherheit
-- Zeile 63; Priester: Heilig Zeile 33, Spalte 8), zum Teil als zweiter Knoten mit derselben Zauber-ID wie ein Talent im
-- Baum. Deshalb: fast gleiche Lagen zählen als eine Zeile (Spalte), der Rasterschritt ist der kleinste Abstand der so
-- gebildeten Zeilen, und was durch mehr als zwei leere Schritte vom übrigen Baum getrennt liegt, ist „abseits“.
---------------------------------------------------------------------------

Traits.GRID_EMPTY = 2       -- so viele leere Zeilen (Spalten) darf ein Baum am Stück haben; ein größerer Abstand: abseits

-- Lagen (je Knoten ein Wert, Wiederholung erlaubt) → { [Wert] = Rasterzahl }, { [Wert] = true, wenn abseits }.
-- Ohne Bezug auf feste Zahlen des Clients: (1) Zwei benachbarte Lagen gehören zu derselben Zeile, wenn ihr Abstand
-- kleiner als ein Drittel des Abstands im oberen Viertel der Abstände im Kern ist (Kern: ohne Lagen hinter einer
-- Lücke, die größer ist als die ganze schwerere Seite; ein Versatz ist winzig gegen einen Rasterschritt; leere Zeilen
-- machen Abstände nur größer). (2) Rasterschritt = kleinster Abstand zweier Zeilen (Lage
-- einer Zeile: Mittel ihrer Werte). (3) Zeilen, die mehr als GRID_EMPTY leere Schritte vom Rest trennen, bilden einen
-- eigenen Block; der Block mit den meisten Knoten ist der Baum, die übrigen sind abseits. Gezählt wird ab der ersten
-- Zeile des Baums; ein Wert abseits bekommt seine Zahl im selben Raster (auch kleiner als 1, wenn er darüber liegt).
function Traits.Grid(values)
    local sorted, count = {}, {}
    for _, v in ipairs(values or {}) do
        if type(v) == "number" then
            if not count[v] then sorted[#sorted + 1] = v end
            count[v] = (count[v] or 0) + 1
        end
    end
    table.sort(sorted)
    local index, outside = {}, {}
    if #sorted == 0 then return index, outside end
    local gaps = {}
    for i = 2, #sorted do gaps[#gaps + 1] = sorted[i] - sorted[i - 1] end
    -- Kern für die Schwelle: Lücken zu Lagen abseits zählen nicht mit, sonst bestimmt bei wenigen Zeilen eine einzige
    -- große Lücke das obere Viertel, und alle echten Rasterschritte gälten als Versatz. Abgetrennt wird die leichtere
    -- Seite (weniger Knoten), solange eine Lücke größer ist als die ganze schwerere Seite – auf einen Rasterschritt folgt
    -- im Baum nie eine Lücke, die größer ist als alles davor oder danach zusammen. Nur für die Schwelle; gezählt wird
    -- danach über alle Lagen.
    local lo, hi = 1, #sorted
    while hi > lo do
        local total = 0
        for i = lo, hi do total = total + count[sorted[i]] end
        local cut, cutGap, keepUpper
        local upper = 0
        for i = lo + 1, hi do
            upper = upper + count[sorted[i - 1]]
            local lower = total - upper
            local gap = sorted[i] - sorted[i - 1]
            local extent = upper > lower and (sorted[i - 1] - sorted[lo]) or (sorted[hi] - sorted[i])
            if upper ~= lower and gap > extent and (not cutGap or gap > cutGap) then
                cut, cutGap, keepUpper = i, gap, upper > lower
            end
        end
        if not cut then break end
        if keepUpper then hi = cut - 1 else lo = cut end
    end
    local ordered = {}
    for i = lo + 1, hi do ordered[#ordered + 1] = sorted[i] - sorted[i - 1] end
    table.sort(ordered)
    local near = #ordered > 0 and ordered[math.max(1, math.ceil(#ordered * 0.75))] / 3 or 0
    local lines = { { values = { sorted[1] }, n = count[sorted[1]] } }
    for i = 2, #sorted do
        local line = lines[#lines]
        if gaps[i - 1] < near then
            line.values[#line.values + 1] = sorted[i]
            line.n = line.n + count[sorted[i]]
        else
            lines[#lines + 1] = { values = { sorted[i] }, n = count[sorted[i]] }
        end
    end
    for _, line in ipairs(lines) do
        local sum = 0
        for _, v in ipairs(line.values) do sum = sum + v end
        line.at = sum / #line.values
    end
    local step
    for i = 2, #lines do
        local gap = lines[i].at - lines[i - 1].at
        if not step or gap < step then step = gap end
    end
    -- Blöcke und der Baum selbst (meiste Knoten; bei Gleichstand der obere)
    local block, blocks = 1, { { first = 1, n = 0 } }
    for i, line in ipairs(lines) do
        if i > 1 and line.at - lines[i - 1].at > (Traits.GRID_EMPTY + 1.5) * step then
            block = block + 1
            blocks[block] = { first = i, n = 0 }
        end
        line.block = block
        blocks[block].n = blocks[block].n + line.n
    end
    local main = 1
    for i, b in ipairs(blocks) do if b.n > blocks[main].n then main = i end end
    local base = lines[blocks[main].first].at
    for _, line in ipairs(lines) do
        local number = step and (math.floor((line.at - base) / step + 0.5) + 1) or 1
        for _, v in ipairs(line.values) do
            index[v] = number
            if line.block ~= main then outside[v] = true end
        end
    end
    return index, outside
end

-- nodes, groups (freiwillig): schon gelesene Traits.Nodes/Traits.Groups, sonst liest Layout sie selbst.
function Traits.Layout(configID, treeID, nodes, groups)
    local layout = {}
    local treeOfGroup = {}
    for i, g in ipairs(groups or Traits.Groups(configID, treeID)) do treeOfGroup[g.id] = i end
    local byTree = {}
    for _, node in ipairs(nodes or Traits.Nodes(configID, treeID)) do
        local tree = 1
        for _, g in ipairs(node.groups) do
            if treeOfGroup[g] then
                tree = treeOfGroup[g]
                break
            end
        end
        byTree[tree] = byTree[tree] or {}
        table.insert(byTree[tree], node)
    end
    for tree, nodes in pairs(byTree) do
        local xs, ys = {}, {}
        for i, node in ipairs(nodes) do xs[i], ys[i] = node.x, node.y end
        local cols, colsAside = Traits.Grid(xs)
        local rows, rowsAside = Traits.Grid(ys)
        for _, node in ipairs(nodes) do
            layout[node.id] = { tree = tree, row = rows[node.y], col = cols[node.x],
                aside = (rowsAside[node.y] or colsAside[node.x]) and true or nil }
        end
    end
    return layout
end

---------------------------------------------------------------------------
-- Gruppen (Talentbäume einer Klasse) und Punkte
---------------------------------------------------------------------------

function Traits.Groups(configID, treeID)
    local list = {}
    local displays = treeID and Call("GetGroupDisplayInfoByTreeID", treeID)
    if type(displays) ~= "table" then return list end
    local ids = {}
    for _, d in ipairs(displays) do
        local id = type(d) == "table" and Num(d.groupID)
        if id then
            ids[#ids + 1] = id
            list[#list + 1] = { id = id, name = Core.Plain(d.displayName) or "", icon = Core.Plain(d.icon), spent = 0 }
        end
    end
    local infos = configID and #ids > 0 and Call("GetGroupCurrencyInfo", configID, ids)
    if type(infos) == "table" then
        for _, info in ipairs(infos) do
            local gid = type(info) == "table" and Num(info.traitNodeGroupID)
            local currency = gid and type(info.currencyInfos) == "table" and info.currencyInfos[1]
            local spent = type(currency) == "table" and Num(currency.spent)
            if spent then
                for _, g in ipairs(list) do
                    if g.id == gid then g.spent = spent end
                end
            end
        end
    end
    return list
end

-- Nummer (1–3) des Baums mit den meisten Punkten; bei Gleichstand der erste, ohne Punkte nil.
function Traits.PrimaryTree(groups)
    local best, bestSpent = nil, 0
    for i, g in ipairs(groups or {}) do
        if (g.spent or 0) > bestSpent then best, bestSpent = i, g.spent end
    end
    return best
end

-- „12 / 31 / 8“ aus den Gruppen.
function Traits.GroupText(groups)
    local parts = {}
    for i, g in ipairs(groups or {}) do parts[i] = tostring(g.spent or 0) end
    return table.concat(parts, " / ")
end

-- Punkte eines Baums: frei, ausgegeben, gesamt (nil, wenn der Client nichts liefert).
function Traits.Currency(configID, treeID)
    local infos = configID and treeID and Call("GetTreeCurrencyInfo", configID, treeID, false)
    local info = type(infos) == "table" and infos[1]
    if type(info) ~= "table" then return nil end
    local free, spent = Num(info.quantity) or 0, Num(info.spent) or 0
    local total = Num(info.maxQuantity)
    if not total or total <= 0 then total = free + spent end
    return free, spent, total
end

function Traits.HasStaged(configID)
    return configID ~= nil and Call("ConfigHasStagedChanges", configID) == true
end

---------------------------------------------------------------------------
-- Texte eines Eintrags (aus dem Client; ezTalent rechnet nichts)
---------------------------------------------------------------------------

local function Definition(configID, entryID)
    local entry = configID and entryID and Call("GetEntryInfo", configID, entryID)
    local defID = type(entry) == "table" and Num(entry.definitionID)
    local def = defID and Call("GetDefinitionInfo", defID)
    return type(def) == "table" and def or nil
end

local function DefinitionName(def)
    local name = Core.Plain(def.overrideName)
    if type(name) ~= "string" or name == "" then name = Core.SpellName(Num(def.spellID)) end
    return type(name) == "string" and name ~= "" and name or nil
end

-- Name und Zauber-ID eines Eintrags (für die Zuordnung der Vorauswahl), ohne Beschreibung und Symbol;
-- zwischengespeichert – beides ändert sich in einer Sitzung nicht. Ohne Namen (Zauberdaten noch nicht geladen) bleibt
-- der Name offen und wird beim nächsten Mal neu gefragt; die Zauber-ID gilt sofort.
local entryNames, entrySpells = {}, {}
local function EntryFacts(configID, entryID)
    if not entryID then return nil, nil end
    if entryNames[entryID] and entrySpells[entryID] ~= nil then return entryNames[entryID], entrySpells[entryID] or nil end
    local def = Definition(configID, entryID)
    if not def then return entryNames[entryID], entrySpells[entryID] or nil end
    local name, spell = DefinitionName(def), Num(def.spellID)
    if name then entryNames[entryID] = name end
    entrySpells[entryID] = (spell and spell > 0) and spell or false    -- false: gefragt, die Definition nennt keinen Zauber
    return name, entrySpells[entryID] or nil
end

function Traits.EntryName(configID, entryID)
    return (EntryFacts(configID, entryID))
end

-- Zauber-ID der Definition eines Eintrags (C_Traits.GetDefinitionInfo(…).spellID) – dieselbe in jeder Sprache.
function Traits.EntrySpell(configID, entryID)
    local _, spell = EntryFacts(configID, entryID)
    return spell
end

function Traits.Entry(configID, entryID, rank)
    local def = Definition(configID, entryID)
    if not def then return nil end
    local spellID = Num(def.spellID)
    local spell = rawget(_G, "C_Spell")
    local out = { entryID = entryID, spellID = spellID, overridden = Num(def.overriddenSpellID) }
    out.name = DefinitionName(def)
    -- Text des Rangs: GetTraitDescription(entryID, rank) wie Blizzards Talent-Tooltip, sonst die Beschreibung
    local text
    if rank and rank > 0 then text = Core.Plain(Call("GetTraitDescription", entryID, rank)) end
    if type(text) ~= "string" or text == "" then text = Core.Plain(def.overrideDescription) end
    if (type(text) ~= "string" or text == "") and spellID and spell then
        text = Core.Plain(Core.Call(spell.GetSpellDescription, spellID))
    end
    out.text = type(text) == "string" and text or ""
    if spellID and spell then out.icon = Core.Plain(Core.Call(spell.GetSpellTexture, spellID)) end
    if type(def.overrideIcon) == "number" then out.icon = def.overrideIcon end
    return out
end

---------------------------------------------------------------------------
-- Zurücksetzen (gestaffelt, wie Blizzards eigener Knopf)
-- Quelle (Gethe/wow-ui-source, Zweig forever): Blizzard_PlayerSpells/ClassTalents/Blizzard_ClassTalentsFrame.lua –
-- ResetClassTalents/ResetSpecTalents setzen je Währung des Baums über C_Traits.ResetTreeByCurrency zurück; der Knopf
-- ist verborgen, wenn C_Traits.GetTreeInfo(...).cannotRefund gilt, und gesperrt, solange eine Bestätigung läuft
-- (IsCommitInProgress, Blizzard_SharedTalentUI/Blizzard_SharedTalentFrame.lua). Gesperrt ist der Baum über den Rahmen
-- (IsLocked): in Mainline über C_ClassTalents.CanEditTalents(), in Forever überschreibt der Camelot-Rahmen
-- (Blizzard_PlayerSpells/Camelot/ClassTalents/Blizzard_ClassTalentsFrame.lua) IsLocked mit „nicht der Reiter der
-- aktiven Spezialisierung“ – ohne CanEditTalents (T7-NT10, Gesamtreview 18.11.2026). Darum fragt ezTalent die Sperre
-- nur am Rahmen ab (UI.Context: ctx.locked, ctx.committing) und hier nicht noch einmal CanEditTalents – sonst sperrte
-- „Zurücksetzen und übernehmen“, wo Blizzards Knopf geht. Das Verlernen beim Lehrer (CONFIRM_TALENT_WIPE →
-- ConfirmTalentWipe, kostet Gold) ist Blizzards eigener Weg – ezTalent ruft es nie auf.
---------------------------------------------------------------------------

function Traits.CanReset(configID, treeID)
    if Core.InCombat() then return false, "combat" end
    local api = Api()
    if not (Traits.Available() and (type(api.ResetTreeByCurrency) == "function" or type(api.ResetTree) == "function")) then
        return false, "noapi"
    end
    if not (configID and treeID) then return false, "noconfig" end
    local info = Call("GetTreeInfo", configID, treeID)
    if type(info) == "table" and Core.Plain(info.cannotRefund) == true then return false, "norefund" end
    return true
end

-- Läuft an Blizzards Talentfenster gerade die Bestätigung („Übernehmen“ wirkt als Zauber mit Wirkzeit)? Dann nimmt
-- ezTalent nichts vor, wie Blizzards eigene Knöpfe (TalentFrameBaseMixin:IsCommitInProgress; T7-NT1). Nur gelesen.
function Traits.Committing(frame)
    if type(frame) ~= "table" or type(frame.IsCommitInProgress) ~= "function" then return false end
    return Core.Plain(Core.Call(frame.IsCommitInProgress, frame)) == true
end

-- Ein schreibender Aufruf hat geklappt, wenn er ohne Lua-Fehler lief und nicht ausdrücklich false meldete.
-- (Core.Call gäbe bei einem Fehler nil zurück – das darf nicht als Erfolg zählen.)
local function Done(name, ...)
    local api = Api()
    local ok, result = Core.PCall(type(api) == "table" and api[name] or nil, ...)
    return ok and result ~= false
end

-- byCurrency = true: je Währung des Baums (Blizzards Weg für Klassentalente), sonst den ganzen Baum (Vermächtnis).
-- Erfolg nur, wenn jede Währung zurückgesetzt wurde (T7-NT6, Gesamtreview 18.11.2026: vorher genügte eine); sonst
-- ResetTree als Rückfall. Geht auch der nicht, nachdem ein Teil der Währungen zurückgesetzt wurde: false, "partial".
function Traits.Reset(configID, treeID, byCurrency)
    local api = Api()
    if type(api) ~= "table" or not (configID and treeID) then return false end
    local partial = false
    if byCurrency and type(api.ResetTreeByCurrency) == "function" then
        local infos = Call("GetTreeCurrencyInfo", configID, treeID, false)
        local tried, failed = 0, 0
        for _, info in ipairs(type(infos) == "table" and infos or {}) do
            local currency = type(info) == "table" and Num(info.traitCurrencyID)
            if currency then
                tried = tried + 1
                if not Done("ResetTreeByCurrency", configID, treeID, currency) then failed = failed + 1 end
            end
        end
        if tried > 0 and failed == 0 then return true end
        partial = failed < tried
    end
    if type(api.ResetTree) == "function" and Done("ResetTree", configID, treeID) then return true end
    if partial then return false, "partial" end
    return false
end

---------------------------------------------------------------------------
-- Anwenden: gestaffelt, mehrere Durchgänge (Voraussetzungen werden erst frei, wenn darüber Punkte stehen)
---------------------------------------------------------------------------

Traits.MAX_PASSES = 60

-- Schritte der Reihenfolge einer Vorlage (TL-01): je Eintrag von tpl.order der Zielrang, den der Knoten mit diesem
-- Schritt erreicht. Die Reihenfolge nennt nur die Ränge, die nach dem Ausgang dazukamen: Stand beim „Anpassen“ ein
-- Knoten schon auf Rang 1, ist sein erster Eintrag Rang 2 (Grundrang = Zielrang in der Vorlage − Zahl seiner Einträge).
-- Eine Quelle für Plan.NextStep (Kopf, „Nächster Punkt“) und Traits.Apply. → { { id, rank, step } … } (leer ohne order)
function Traits.OrderSteps(tpl)
    local steps = {}
    local order = type(tpl) == "table" and tpl.order
    if type(order) ~= "table" then return steps end
    local base, counts = Traits.BaseRanks(tpl), {}
    for i, raw in ipairs(order) do
        local id = tonumber(raw)
        if id then
            counts[id] = (counts[id] or 0) + 1
            steps[#steps + 1] = { id = id, rank = (base[id] or 0) + counts[id], step = i }
        end
    end
    return steps
end

-- Grundränge einer Vorlage: je Knoten der Rang, der vor der Reihenfolge steht (Zielrang − Zahl seiner Einträge in
-- tpl.order; ohne Eintrag der ganze Zielrang). Die Reihenfolge setzt auf diesem Ausgang auf – „Übernehmen“ setzt ihn
-- deshalb zuerst (Gegenprüfung Welle 13: eine Reihenfolge, die nach „Anpassen“ nur einen Punkt nennt, ging sonst
-- nie, weil ihr Vorgänger im Ausgang steht). → { [nodeID] = Rang } (nur Knoten mit Rang > 0)
function Traits.BaseRanks(tpl)
    local base = {}
    local nodes = type(tpl) == "table" and type(tpl.nodes) == "table" and tpl.nodes
    if not nodes then return base end
    local total = {}
    for _, raw in ipairs(type(tpl.order) == "table" and tpl.order or {}) do
        local id = tonumber(raw)
        if id then total[id] = (total[id] or 0) + 1 end
    end
    for nodeID, rank in pairs(nodes) do
        local id = tonumber(nodeID)
        local r = id and math.max(0, (tonumber(rank) or 0) - (total[id] or 0))
        if r and r > 0 then base[id] = r end
    end
    return base
end

-- Reichen die freien Punkte nicht für das, was von der Vorlage im Baum noch fehlt? Nennt der Client die freien Punkte
-- nicht, gilt „reicht“ (wie vor der Reihenfolge). Eine Regel für Traits.Apply und Plan.FirstApply. → bool
function Traits.Short(configID, treeID, tpl)
    local free = Traits.Currency(configID, treeID)
    if free == nil then return false end
    local need = 0
    for nodeID, rank in pairs(type(tpl) == "table" and type(tpl.nodes) == "table" and tpl.nodes or {}) do
        local node = tonumber(nodeID) and Traits.Node(configID, tonumber(nodeID))
        if node then need = need + math.max(0, (tonumber(rank) or 0) - (node.purchased or 0)) end
    end
    return need > free
end

-- Einen Rang eines Knotens gestaffelt setzen (Wahlknoten: die Wahl der Vorlage). → true, wenn der Client ihn nahm
local function Buy(configID, node, choices)
    local choice = tonumber(choices[node.id] or choices[tostring(node.id)])
    if node.choice and choice and (node.purchased == 0 or node.entry ~= choice) then
        return Call("SetSelection", configID, node.id, choice) and true or false
    end
    return Call("PurchaseRank", configID, node.id) and true or false
end

-- tpl = { nodes = { [nodeID] = Ränge }, choices = { [nodeID] = entryID }, order = { nodeID … } (freiwillig) }
-- Reihenfolge (Spieltest 15.11.2026: mit zu wenig Punkten sollen genau die nächsten Punkte der Vorlage vorgemerkt
-- werden): Hat die Vorlage eine Reihenfolge, setzt Apply zuerst ihren Ausgang (Traits.BaseRanks: die Ränge, die die
-- Reihenfolge nicht nennt) von oben nach unten, dann die Schritte der Reihenfolge einzeln. Geht ein Schritt nicht und
-- reichen die freien Punkte nicht für den Rest, ist Schluss – dann wird nichts außer der Reihe gesetzt. Reichen sie
-- (oder nennt der Client sie nicht), folgt wie ohne Reihenfolge der ganze Plan in Durchgängen von oben nach unten, dann
-- von links (Traits.ByPosition), je Durchgang ein Rang je Talent – so wie vor der Reihenfolge (Gegenprüfung Welle 13).
-- opts.reset = true: vorher den Baum zurücksetzen (gestaffelt, wie Blizzards Knopf „Zurücksetzen“);
-- opts.byCurrency = true: dabei je Währung wie Blizzards Talentfenster (Traits.Reset);
-- opts.frame: Blizzards Trait-Rahmen – läuft dort gerade die Bestätigung, ändert Apply nichts ("commit", T7-NT1)
-- Rückgabe: { bought = Anzahl, missing = { nodeID… }, extra = { nodeID… }, unknown = { nodeID… },
--             otherChoice = { nodeID… } (Wahlknoten steht auf einer anderen Wahl als die Vorlage; nur gemeldet),
--             reset = bool (geklappt), resetTried = true (wenn opts.reset),
--             resetPartial = true (nur ein Teil der Währungen zurückgesetzt, Traits.Reset) }
--           oder nil, "combat" | "commit" | "noapi" | "noconfig"
function Traits.Apply(configID, treeID, tpl, opts)
    opts = opts or {}
    if Core.InCombat() then return nil, "combat" end
    if Traits.Committing(opts.frame) then return nil, "commit" end
    if not Traits.Available() then return nil, "noapi" end
    if not (configID and treeID and type(tpl) == "table" and type(tpl.nodes) == "table") then return nil, "noconfig" end
    local result = { bought = 0, missing = {}, extra = {}, unknown = {}, otherChoice = {}, reset = false }
    if opts.reset then
        result.resetTried = true
        local ok, why = Traits.Reset(configID, treeID, opts.byCurrency)
        result.reset = ok == true
        result.resetPartial = why == "partial" or nil
    end

    local inTree = {}
    for _, id in ipairs(Traits.NodeIDs(treeID)) do inTree[id] = true end
    local wanted = {}
    for nodeID, rank in pairs(tpl.nodes) do
        nodeID, rank = tonumber(nodeID), tonumber(rank)
        if nodeID and rank and rank > 0 then
            if inTree[nodeID] then wanted[#wanted + 1] = { id = nodeID, rank = rank }
            else result.unknown[#result.unknown + 1] = nodeID end
        end
    end
    local choices = type(tpl.choices) == "table" and tpl.choices or {}

    -- Ränge bis zum Ziel je Talent, in Durchgängen von oben nach unten (Voraussetzungen werden erst frei, wenn darüber
    -- Punkte stehen); targets = { { id, rank } … }
    local function Passes(targets)
        for _ = 1, Traits.MAX_PASSES do
            local progress = false
            local nodes = {}
            for _, w in ipairs(targets) do
                local node = Traits.Node(configID, w.id)
                if node and node.purchased < w.rank then nodes[#nodes + 1] = node end
            end
            if #nodes == 0 then break end
            table.sort(nodes, ByPosition)
            for _, node in ipairs(nodes) do
                if Buy(configID, node, choices) then
                    result.bought = result.bought + 1
                    progress = true
                end
            end
            if not progress then break end
        end
    end

    local steps = Traits.OrderSteps(tpl)
    -- 1. Ausgang der Reihenfolge (nur mit Reihenfolge; ohne ist der Ausgang der ganze Plan und folgt unter 3.)
    if #steps > 0 then
        local base, targets = Traits.BaseRanks(tpl), {}
        for _, w in ipairs(wanted) do
            if base[w.id] then targets[#targets + 1] = { id = w.id, rank = base[w.id] } end
        end
        Passes(targets)
    end

    -- 2. Reihenfolge der Vorlage, Schritt für Schritt (ein Schritt kann mehrere Ränge brauchen, wenn der Grundrang des
    --    Knotens noch nicht steht); beim ersten Schritt, der nicht geht, endet die Reihenfolge
    local ordered = true
    for _, step in ipairs(steps) do
        local node = inTree[step.id] and Traits.Node(configID, step.id)
        local guard = 0
        while node and node.purchased < step.rank and guard < 20 do
            guard = guard + 1
            if not Buy(configID, node, choices) then
                ordered = false
                break
            end
            result.bought = result.bought + 1
            node = Traits.Node(configID, step.id)
        end
        if not ordered or (node and node.purchased < step.rank) then
            ordered = false
            break
        end
    end

    -- 3. Rest des Plans von oben nach unten (ohne Reihenfolge: alles) – wenn die Reihenfolge ganz steht oder die freien
    --    Punkte für alles reichen, was noch fehlt
    if ordered or not Traits.Short(configID, treeID, tpl) then Passes(wanted) end

    for _, w in ipairs(wanted) do
        local node = Traits.Node(configID, w.id)
        if not node or node.purchased < w.rank then
            result.missing[#result.missing + 1] = w.id
        else
            -- Rang erreicht, aber ein Wahlknoten steht auf einer anderen Wahl (schon vorher gekauft): nur melden
            local choice = tonumber(choices[w.id] or choices[tostring(w.id)])
            if node.choice and choice and node.entry ~= choice then result.otherChoice[#result.otherChoice + 1] = w.id end
        end
    end
    -- Mehr gesetzt als die Vorlage will (nur melden; ezTalent nimmt nie Punkte zurück)
    for _, node in ipairs(Traits.Nodes(configID, treeID)) do
        local want = tonumber(tpl.nodes[node.id] or tpl.nodes[tostring(node.id)]) or 0
        if node.purchased > want then result.extra[#result.extra + 1] = node.id end
    end
    table.sort(result.missing)
    table.sort(result.extra)
    table.sort(result.otherChoice)
    table.sort(result.unknown)
    return result
end

-- Name eines Knotens (für Meldungen „fehlt: …“): Name des ersten Eintrags, sonst „#nodeID“.
function Traits.NodeName(configID, nodeID)
    local node = Traits.Node(configID, nodeID)
    local entry = node and node.entry and Traits.Entry(configID, node.entry, 0)
    return entry and entry.name or ("#" .. tostring(nodeID))
end
