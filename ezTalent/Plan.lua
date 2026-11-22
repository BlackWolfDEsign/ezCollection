local _, ns = ...
local Core = ezCore
local L = ns.L
local Traits = ns.Traits
local Templates = ns.Templates

--[[
    Vorschau („Plan“) einer Vorlage in Blizzards Baum – Wunsch des Nutzers im Spieltest vom 14.11.2026 (Wortlaut):
    „ich wähle vorlage, die wird hier geladen --> ich kann übernehmen oder anpassen und abspeichern und dann liegt die
    vorlage direkt immer vor wenn ich fenster öffne --> lvl zu gering --> talente ausgegraut aber setzbar/lesbar“.

    Ein Klick auf eine eigene Vorlage oder eine Vorauswahl kopiert nichts mehr, sondern lädt sie als Plan:
      - An jedem Talent des Plans steht in Blizzards Baum eine kleine Zahl mit dem Zielrang (eigener Rahmen als Kind von
        Blizzards Talentknopf, den das Fenster über GetTalentButtonByNodeID nennt – Blizzard_SharedTalentFrame.lua,
        Zweig forever: TalentFrameBaseMixin:GetTalentButtonByNodeID. Das Vermächtnis-Fenster hat sie ebenfalls:
        Blizzard_LegacySystem/Blizzard_LegacyTree.xml, LegacyTreeTraitPanelTemplate erbt TalentFrameBaseTemplate –
        nachgelesen am 14.11.2026). Grün: erreicht. Gold: fehlt noch und ist jetzt setzbar. Grau: fehlt noch und
        ist jetzt nicht setzbar (Stufe, Punkte, Voraussetzung) – Blizzards Knopf bleibt dann ohnehin grau, die Zahl
        bleibt lesbar. Rot: im Baum steht mehr als im Plan. Orange: Wahl-Talent, im Baum steht die andere Wahl.
      - „Übernehmen“ (UI.Apply) setzt die Punkte des Plans gestaffelt in Blizzards Baum, soweit Stufe und Punkte
        reichen; gültig wird es wie bisher erst mit Blizzards eigenem Knopf.
      - „Anpassen“ schaltet das Planen ein: Dann nimmt der eigene Rahmen die Klicks an (Linksklick +1, Rechtsklick −1,
        bei Wahlknoten wechselt ein weiterer Linksklick die Wahl) – unabhängig von Stufe und freien Punkten, es wird
        nichts gekauft. Aus: Der Rahmen nimmt keine Maus an, Blizzards Knopf arbeitet wie immer.
      - „Speichern“ legt den Plan als eigene Vorlage ab.
      - Welcher Plan geladen ist, merkt sich ezTalent je Charakter und Baum (ezTalentDB.chars[…].plan[scope]) samt
        ungespeicherten Änderungen – beim nächsten Öffnen liegt er wieder vor.

    Taint: Blizzards Knöpfe werden nur gelesen (GetTalentButtonByNodeID, GetFrameLevel); der eigene Rahmen ist ein
    Kind des Knopfs und schreibt nichts in Blizzards Tabellen. Blizzards Knöpfe kommen aus einem Vorrat und wechseln
    den Knoten – deshalb gleicht Plan.Sync bei jeder Änderung neu ab (auch nach „TalentFrameBase.ButtonsUpdated“).
    Regeln (TL-10): Plan.Check prüft den Plan gegen Vorgänger und Schwellen des Baums (aus dem Client) und zählt die
    Gesamtpunkte; ein Talent, das so nicht geht, trägt eine violette Zahl, der Kopf sagt „nicht gültig: …“. Gesperrt
    wird nichts – geplant werden darf weiter alles; was gerade nicht setzbar ist, meldet „Übernehmen“ wie bisher.

      plan = { kind = "own" | "preset" | "new", key (Vorlagenname bzw. Schlüssel der Vorauswahl), name, scope,
               tpl = { nodes, choices, tree, primary, unmatched, matchTotal, order, orderFrom, orderEdited },
               found, total, missing, how, edited }

    Reihenfolge der Punkte (TL-01, VP-57): Beim „Anpassen“ merkt Plan.Adjust jeden Klick – ein Rang mehr hängt den
    Knoten an tpl.order an, ein Rang weniger nimmt seinen letzten Eintrag heraus. Plan.NextStep nennt daraus den
    ersten Schritt, der im Baum noch fehlt; beim Stufenaufstieg meldet ezTalent ihn im Chat („Nächster Talentpunkt:
    …“, Schalter nextPoint) – vergeben wird nichts. ezMerchant kann die Zeile über ezCore.API("ezTalent").NextPoint in
    seinen Block holen; meldet es das über API.ShowsNextPoint() == true, schweigt ezTalents eigene Zeile.
]]

local Plan = {}
ns.Plan = Plan

---------------------------------------------------------------------------
-- Plan anlegen
---------------------------------------------------------------------------

local function CopyMap(map)
    local out = {}
    for key, value in pairs(type(map) == "table" and map or {}) do out[key] = value end
    return out
end

local function CopyList(list)
    if type(list) ~= "table" then return nil end
    local out = {}
    for i, value in ipairs(list) do out[i] = value end
    return out
end

-- Aus einer eigenen Vorlage (Kopie – Änderungen am Plan ändern die Vorlage erst mit „Speichern“).
function Plan.FromTemplate(scope, name)
    local tpl = Templates.Get(scope, name)
    if not tpl then return nil end
    return { kind = "own", key = name, name = name, scope = scope,
        tpl = { nodes = CopyMap(tpl.nodes), choices = CopyMap(tpl.choices), tree = tpl.tree, primary = tpl.primary,
            unmatched = tpl.unmatched, matchTotal = tpl.matchTotal, order = CopyList(tpl.order),
            orderFrom = tpl.orderFrom, orderEdited = tpl.orderEdited } }
end

-- Aus einer Vorauswahl: zur Laufzeit den Knoten des Clients zugeordnet (Templates.ResolvePreset).
function Plan.FromPreset(preset, ctx, index)
    if type(preset) ~= "table" or type(ctx) ~= "table" then return nil end
    local plan = { kind = "preset", key = preset.key, name = Templates.PresetName(preset), scope = ctx.scope, preset = preset }
    if type(preset.talents) == "table" then
        plan.tpl, plan.found, plan.total, plan.missing, plan.how =
            Templates.ResolvePreset(preset, ctx.configID, ctx.treeID, index)
    else    -- alte Form mit Knoten-IDs
        plan.tpl = { nodes = CopyMap(preset.nodes), choices = CopyMap(preset.choices), tree = ctx.treeID }
    end
    plan.tpl.primary = tonumber(preset.tree)
    return plan
end

-- Aus der Verteilung, wie sie gerade im Fenster steht (Ausgang für „Anpassen“ ohne gewählte Vorlage).
function Plan.FromCurrent(ctx)
    if not (type(ctx) == "table" and ctx.configID and ctx.treeID) then return nil end
    local snap = Traits.Snapshot(ctx.configID, ctx.treeID, false)
    return { kind = "new", name = L.PLAN_NEW_NAME, scope = ctx.scope,
        tpl = { nodes = snap.nodes, choices = snap.choices, tree = ctx.treeID } }
end

---------------------------------------------------------------------------
-- Auswertung
---------------------------------------------------------------------------

function Plan.Points(plan)
    return type(plan) == "table" and Traits.Points(plan.tpl) or 0
end

-- Plan ohne einen einzigen Punkt (Vorauswahl ohne jede Zuordnung im Client, leere Vorlage): Es gibt nichts zu
-- übernehmen – „Übernehmen“ und „Zurücksetzen und übernehmen“ sind dann gesperrt (UI.EmptyReason).
function Plan.IsEmpty(plan)
    return type(plan) == "table" and Plan.Points(plan) == 0
end

-- Punkte des Plans je Talentbaum ({ 35, 11, 5 }) – nur Klassentalente; sonst leere Liste.
function Plan.Split(plan, ctx)
    local split = {}
    if not (type(plan) == "table" and type(ctx) == "table" and ctx.kind == "class") then return split end
    local groups = Traits.Groups(ctx.configID, ctx.treeID)
    if #groups == 0 then return split end
    for i = 1, #groups do split[i] = 0 end
    local layout = Traits.Layout(ctx.configID, ctx.treeID, nil, groups)
    for nodeID, rank in pairs(plan.tpl.nodes) do
        local where = layout[tonumber(nodeID)]
        if where and split[where.tree] then split[where.tree] = split[where.tree] + (tonumber(rank) or 0) end
    end
    return split
end

-- Die Wahl, die der Plan an einem Wahlknoten will (nil: kein Wahlknoten oder keine Angabe).
local function WantedChoice(plan, node)
    local choices = type(plan) == "table" and node.choice and plan.tpl.choices
    return type(choices) == "table" and tonumber(choices[node.id] or choices[tostring(node.id)]) or nil
end

-- Zustand eines Knotens gegen den Plan: "done" erreicht · "open" fehlt, jetzt setzbar · "locked" fehlt, jetzt nicht
-- setzbar · "extra" im Baum steht mehr als im Plan · "other" Wahlknoten, Rang erreicht, aber im Baum steht die andere
-- Wahl („Übernehmen“ stellt sie nicht um, Traits.Apply meldet sie nur) · nil weder im Plan noch gesetzt.
-- Dazu der Zielrang.
function Plan.NodeState(plan, node)
    local want = type(plan) == "table" and tonumber(plan.tpl.nodes[node.id] or plan.tpl.nodes[tostring(node.id)]) or 0
    if want > 0 then
        if node.purchased > want then return "extra", want end
        if node.purchased == want then
            local choice = WantedChoice(plan, node)
            if choice and node.entry ~= choice then return "other", want end
            return "done", want
        end
        return node.canPurchase and "open" or "locked", want
    end
    -- Mehr als im Plan – aber nur gegen einen Plan mit Inhalt (eine Vorauswahl ohne jede Zuordnung ist leer)
    if type(plan) == "table" and node.purchased > 0 and next(plan.tpl.nodes) ~= nil then return "extra", 0 end
    return nil, 0
end

-- Fortschritt: { want = Punkte des Plans, have = davon schon im Baum, missing = want − have,
--                extra = Knoten mit mehr als im Plan, other = Wahlknoten auf der anderen Wahl (zählen nicht als
--                erreicht, kosten aber keinen Punkt mehr), need = Punkte, die noch zu setzen sind,
--                free = freie Punkte (nil, wenn der Client sie nicht nennt), short = nötig sind mehr als frei }
function Plan.Progress(plan, ctx)
    local p = { want = 0, have = 0, missing = 0, extra = 0, other = 0, need = 0 }
    if not (type(plan) == "table" and type(ctx) == "table") then return p end
    local seen = {}
    for _, node in ipairs(Traits.Nodes(ctx.configID, ctx.treeID)) do
        seen[node.id] = true
        local state, want = Plan.NodeState(plan, node)
        p.want = p.want + want
        if state == "other" then
            p.other = p.other + 1
        else
            p.have = p.have + math.min(node.purchased, want)
            p.need = p.need + math.max(0, want - node.purchased)
        end
        if state == "extra" then p.extra = p.extra + 1 end
    end
    for nodeID, rank in pairs(plan.tpl.nodes) do     -- Knoten, die es in diesem Baum nicht gibt, zählen als fehlend
        if not seen[tonumber(nodeID)] then
            p.want = p.want + (tonumber(rank) or 0)
            p.need = p.need + (tonumber(rank) or 0)
        end
    end
    p.missing = p.want - p.have
    p.free = Traits.Currency(ctx.configID, ctx.treeID)
    p.short = p.free ~= nil and p.need > p.free
    return p
end

---------------------------------------------------------------------------
-- Regeln des Baums gegen den Plan (TL-10): Vorgänger, Schwellen, Gesamtpunkte
-- Die Regeln kommen aus dem Client (Traits.Node: Bedingungen und Kanten). Liefert er keine, findet die Prüfung
-- nichts – der Plan gilt dann wie bisher, und „Übernehmen“ meldet, was nicht geht.
-- Annahmen, im Spiel zu bestätigen (Spielprüfung 59): Ein Vorgänger (Kante „erforderlich“ bzw. „genügt“) zählt, wenn
-- er im Plan samt geschenkter Ränge den Höchstrang hat oder seine Kante im Baum schon aktiv ist und der Plan ihm
-- nichts wegnimmt (auch ein nur geschenkter Vorgänger ohne gekaufte Ränge, der in keinem Plan steht). Eine
-- Schwelle („benötigt 10 Punkte“) zählt bei Klassentalenten die Punkte des Plans im selben Talentbaum in den Zeilen
-- darüber (wie die klassischen Bäume), beim Vermächtnis alle übrigen Punkte des Plans im Baum.
---------------------------------------------------------------------------

Plan.CLASS_POINTS = 51      -- Klassentalente auf Stufe 60 (Höchststufe von Forever; jede Vorauswahl hat 51 Punkte)

-- Höchstzahl der Punkte für den Plan: Klassentalente Plan.CLASS_POINTS, Vermächtnis die Gesamtzahl des Clients.
function Plan.MaxPoints(ctx)
    if type(ctx) ~= "table" then return nil end
    if ctx.kind == "class" then return Plan.CLASS_POINTS end
    local _, _, total = Traits.Currency(ctx.configID, ctx.treeID)
    return total
end

local function Want(plan, id)
    local nodes = plan.tpl.nodes
    return tonumber(nodes[id] or nodes[tostring(id)]) or 0
end

-- Ist der Vorgänger einer Kante im Plan erfüllt? Geschenkte Ränge (Rang im Client über den gekauften, Bedingung
-- „Granted“) stehen in keinem Plan – Pläne entstehen aus den gekauften Rängen (Traits.Snapshot) – und zählen mit.
local function EdgeMet(plan, source, edge)
    if not source then return false end
    local want, purchased = Want(plan, source.id), source.purchased or 0
    local granted = math.max(0, (source.current or 0) - purchased)
    if want + granted >= (source.max or 1) then return true end
    return edge.active == true and want >= purchased and (want > 0 or purchased == 0)
end

-- → { points, max, over (mehr Punkte als möglich), bad = { [nodeID] = { kind = "max" | "edge" | "spent", from, need,
--     have, text, max } }, list = { nodeID … } von oben nach unten }
-- kind = "max": mehr Ränge als der Höchstrang des Knotens (eingefügter Text oder Vorauswahl; T7-NT5, Gesamtreview
-- 18.11.2026 – vorher übernahm die Vorschau „5“ an einem Talent mit Höchstrang 3 ohne Hinweis).
function Plan.Check(plan, ctx)
    local check = { points = Plan.Points(plan), bad = {}, list = {} }
    check.max = Plan.MaxPoints(ctx)
    check.over = check.max ~= nil and check.points > check.max
    if not (type(plan) == "table" and type(ctx) == "table" and ctx.configID and ctx.treeID) then return check end
    local nodes = Traits.Nodes(ctx.configID, ctx.treeID)
    local byID, incoming = {}, Traits.Incoming(nodes)
    for _, node in ipairs(nodes) do byID[node.id] = node end
    local layout = ctx.kind == "class" and Traits.Layout(ctx.configID, ctx.treeID, nodes) or {}
    -- Punkte des Plans, die für eine Schwelle am Knoten zählen
    local function Counted(node)
        local here, sum = layout[node.id], 0
        for _, other in ipairs(nodes) do
            if other.id ~= node.id then
                local w = Want(plan, other.id)
                if w > 0 then
                    if ctx.kind ~= "class" then
                        sum = sum + w
                    else
                        local there = layout[other.id]
                        if here and there then
                            if there.tree == here.tree and (there.row or 0) < (here.row or 0) then sum = sum + w end
                        elseif other.y < node.y then
                            sum = sum + w
                        end
                    end
                end
            end
        end
        return sum
    end
    for _, node in ipairs(nodes) do
        local want = Want(plan, node.id)
        if want > 0 then
            local bad
            if type(node.max) == "number" and node.max > 0 and want > node.max then
                bad = { kind = "max", max = node.max, have = want }
            end
            local sufficient, sufficientMet = nil, false
            for _, e in ipairs(incoming[node.id] or {}) do
                local met = EdgeMet(plan, byID[e.from], e)
                if e.kind == Traits.EDGE.required and not met and not bad then
                    bad = { kind = "edge", from = e.from }
                elseif e.kind == Traits.EDGE.sufficient then
                    sufficient = sufficient or e.from
                    if met then sufficientMet = true end
                end
            end
            if not bad and sufficient and not sufficientMet then bad = { kind = "edge", from = sufficient } end
            if not bad then
                for _, condID in ipairs(node.conditions or {}) do
                    local cond = Traits.Condition(ctx.configID, condID)
                    if Traits.Restricts(cond) and cond.spent then
                        local have = Counted(node)
                        if have < cond.spent then
                            bad = { kind = "spent", need = cond.spent, have = have, text = cond.text }
                            break
                        end
                    end
                end
            end
            if bad then
                check.bad[node.id] = bad
                check.list[#check.list + 1] = node.id
            end
        end
    end
    return check
end

-- Ein Regelverstoß als Text: „braucht zuerst <Talent> (voll)“ bzw. „benötigt 10 Punkte darüber (im Plan: 5)“.
function Plan.BadText(ctx, bad)
    if type(bad) ~= "table" then return "" end
    if bad.kind == "max" then return L.PLAN_BAD_MAX:format(bad.max or 0, bad.have or 0) end
    if bad.kind == "edge" then return L.PLAN_BAD_EDGE:format(Traits.NodeName(ctx.configID, bad.from)) end
    local key = type(ctx) == "table" and ctx.kind == "class" and "PLAN_BAD_SPENT" or "PLAN_BAD_SPENT_TREE"
    return L[key]:format(bad.need or 0, bad.have or 0)
end

-- Ist der Plan nach den Regeln gültig (keine Regelverletzung, nicht zu viele Punkte)?
function Plan.Valid(check)
    return type(check) == "table" and not check.over and #check.list == 0
end

---------------------------------------------------------------------------
-- Anpassen (Planen): ändert nur den Plan, kauft nichts
---------------------------------------------------------------------------

-- delta +1/−1. Wahlknoten: der erste Punkt nimmt die Wahl, die im Baum steht (sonst die erste); ein weiterer
-- Linksklick auf den vollen Knoten wechselt zur nächsten Wahl. → neuer Zielrang oder nil (nichts geändert)
function Plan.Adjust(plan, node, delta)
    if not (type(plan) == "table" and type(node) == "table" and node.id) then return nil end
    local nodes, choices = plan.tpl.nodes, plan.tpl.choices
    local want = tonumber(nodes[node.id] or nodes[tostring(node.id)]) or 0
    local new = math.max(0, math.min(node.max or 1, want + (delta or 0)))
    local changed = new ~= want
    nodes[tostring(node.id)] = nil
    nodes[node.id] = new > 0 and new or nil
    if node.choice then
        local current = tonumber(choices[node.id] or choices[tostring(node.id)])
        choices[tostring(node.id)] = nil
        if new == 0 then
            choices[node.id] = nil
        elseif not current then
            choices[node.id] = (node.purchased > 0 and node.entry) or node.entries[1]
            changed = true
        elseif not changed and (delta or 0) > 0 then
            local at = 1
            for i, entry in ipairs(node.entries) do if entry == current then at = i end end
            choices[node.id] = node.entries[at % #node.entries + 1]
            changed = choices[node.id] ~= current
        else
            choices[node.id] = current
        end
    end
    if not changed then return nil end
    plan.edited = true
    if new ~= want then Plan.NoteClick(plan, node.id, new > want) end
    return new
end

-- Reihenfolge der Klicks merken (TL-01): ein Rang mehr hängt den Knoten an, ein Rang weniger nimmt seinen letzten
-- Eintrag heraus. War die Reihenfolge aus einer Quelle, gilt sie danach als „von dir angepasst“.
function Plan.NoteClick(plan, nodeID, added)
    local tpl = plan.tpl
    tpl.order = type(tpl.order) == "table" and tpl.order or {}
    local order = tpl.order
    local changed = false
    if added then
        if #order < Templates.MAX_ORDER then
            order[#order + 1] = nodeID
            changed = true
        end
    else
        for i = #order, 1, -1 do
            if tonumber(order[i]) == nodeID then
                table.remove(order, i)
                changed = true
                break
            end
        end
    end
    if not changed then return end
    if tpl.orderFrom == nil then
        tpl.orderFrom = "clicks"
    elseif tpl.orderFrom ~= "clicks" then
        tpl.orderEdited = true
    end
end

---------------------------------------------------------------------------
-- Reihenfolge der Punkte (TL-01, VP-57): nächster Schritt, Quelle, Meldung beim Stufenaufstieg
---------------------------------------------------------------------------

Plan.NEXT_DELAY = 2     -- Sekunden nach PLAYER_LEVEL_UP (der Client zählt den neuen Punkt kurz danach)

-- Der erste Schritt der Reihenfolge, der im Baum noch fehlt (gezählt werden gekaufte Ränge; Knoten, die es in diesem
-- Baum nicht gibt, zählen nicht). Die Reihenfolge nennt nur die Ränge, die nach dem Ausgang dazukamen: Stand beim
-- „Anpassen“ ein Knoten schon auf Rang 1, ist sein erster Eintrag Rang 2 (Grundrang = Zielrang im Plan − Zahl seiner
-- Einträge). → { node, rank (Zielrang dieses Schritts), entry, name, step, total } oder nil,
-- Grund ("none" keine Reihenfolge, "done" alle Schritte gesetzt)
function Plan.NextStep(plan, ctx)
    local order = type(plan) == "table" and type(plan.tpl) == "table" and plan.tpl.order
    if type(order) ~= "table" or #order == 0 then return nil, "none" end
    if not (type(ctx) == "table" and ctx.configID) then return nil, "none" end
    -- Schritte samt Zielrang aus Traits.OrderSteps – dieselbe Rechnung, nach der „Übernehmen“ setzt
    for _, s in ipairs(Traits.OrderSteps(plan.tpl)) do
        local node = Traits.Node(ctx.configID, s.id)
        if node and (node.purchased or 0) < s.rank then
            local entryID = Plan.EntryOf(plan, node)
            local entry = entryID and Traits.Entry(ctx.configID, entryID, s.rank)
            return { node = s.id, rank = s.rank, entry = entryID, step = s.step, total = #order,
                canPurchase = node.canPurchase == true,
                name = entry and entry.name ~= "" and entry.name or Traits.NodeName(ctx.configID, s.id) }
        end
    end
    return nil, "done"
end

-- Eintrag, den der Plan an einem Knoten setzt: die Wahl des Plans (Wahlknoten), sonst der Eintrag des Knotens.
function Plan.EntryOf(plan, node)
    local choices = type(plan) == "table" and type(plan.tpl) == "table" and plan.tpl.choices
    return tonumber(type(choices) == "table" and (choices[node.id] or choices[tostring(node.id)]) or nil) or node.entry
end

-- Ränge je Zauber-ID und Punkte je Baum eines Plans bzw. einer Momentaufnahme ({ tpl = { nodes, choices } }) im
-- geöffneten Baum – für „Prüfen“ (Templates.Rate, Spieltest 20.11.2026). Eintrag je Knoten wie die Vorschau
-- (Plan.EntryOf), Schlüssel als Zahl oder Text. → { [Zauber-ID] = Rang }, { Punkte je Baum } (Plan.Split)
function Plan.SpellRanks(plan, ctx)
    local ranks = {}
    local split = Plan.Split(plan, ctx)
    local nodes = type(plan) == "table" and type(plan.tpl) == "table" and plan.tpl.nodes
    if type(nodes) ~= "table" or not (type(ctx) == "table" and ctx.configID) then return ranks, split end
    for _, node in ipairs(Traits.Nodes(ctx.configID, ctx.treeID)) do
        local rank = tonumber(nodes[node.id] or nodes[tostring(node.id)]) or 0
        if rank > 0 then
            local entry = Plan.EntryOf(plan, node)
            local spell = entry and Traits.EntrySpell(ctx.configID, entry)
            if spell then ranks[spell] = (ranks[spell] or 0) + rank end
        end
    end
    return ranks, split
end

-- Was „Übernehmen“ als Erstes setzt (Spieltest 15.11.2026: „ich dachte, das wählt automatisch die richtigen aus“ –
-- der Kopf sagt es in einem Satz). Dieselbe Regel wie Traits.Apply: mit Reihenfolge zuerst ihr Ausgang
-- (Traits.BaseRanks) von oben nach unten, dann der erste fehlende Schritt; geht er nicht und reichen die freien Punkte
-- nicht (Traits.Short), setzt „Übernehmen“ nichts außer der Reihe. Sonst das erste fehlende Talent von oben nach unten,
-- das der Client gerade nimmt. → { name, node, order = true|nil } oder nil, Grund ("done" nichts fehlt, "blocked"
-- nichts setzbar – mit dem nächsten Schritt der Reihenfolge als drittem Wert, falls es einen gibt)
function Plan.FirstApply(plan, ctx)
    if not (type(plan) == "table" and type(ctx) == "table" and ctx.configID) then return nil, "done" end
    -- Erstes Talent von oben nach unten, dem bis zu want(node) noch Ränge fehlen und das der Client gerade nimmt
    local function FirstOpen(want)
        local open, missing = {}, false
        for _, node in ipairs(Traits.Nodes(ctx.configID, ctx.treeID)) do
            if node.purchased < want(node) then
                missing = true
                if node.canPurchase then open[#open + 1] = node end
            end
        end
        if #open == 0 then return nil, missing end
        table.sort(open, Traits.ByPosition)
        local node = open[1]
        local entryID = Plan.EntryOf(plan, node)
        local entry = entryID and Traits.Entry(ctx.configID, entryID, node.purchased + 1)
        return { node = node.id, name = entry and entry.name ~= "" and entry.name or Traits.NodeName(ctx.configID, node.id) }
    end
    local step = Plan.NextStep(plan, ctx)
    if step then
        local base = Traits.BaseRanks(plan.tpl)
        local first = FirstOpen(function(node) return base[node.id] or 0 end)
        if first then return first end
        if step.canPurchase then return { name = step.name, node = step.node, order = true } end
        if Traits.Short(ctx.configID, ctx.treeID, plan.tpl) then return nil, "blocked", step end
    end
    local nodes = plan.tpl.nodes
    local first, missing = FirstOpen(function(node) return tonumber(nodes[node.id] or nodes[tostring(node.id)]) or 0 end)
    if first then return first end
    if step then return nil, "blocked", step end
    return nil, missing and "blocked" or "done"
end

-- Woher die Reihenfolge stammt, als Text (Leitlinie 11).
function Plan.OrderSource(tpl)
    local from = type(tpl) == "table" and tpl.orderFrom
    if not from or from == "clicks" then return L.ORDER_FROM_CLICKS end
    local site = ns.PRESET_SITES and ns.PRESET_SITES[from]
    local name = site and site.name or tostring(from)
    return (tpl.orderEdited and L.ORDER_FROM_SITE_EDITED or L.ORDER_FROM_SITE):format(name)
end

-- Kontext der Klassentalente ohne Fenster (für den Stufenaufstieg und die Schnittstelle).
function Plan.ClassContext()
    local configID = Traits.ClassConfigID()
    local treeID = configID and Traits.TreeOfConfig(configID)
    if not (configID and treeID) then return nil end
    return { kind = "class", configID = configID, treeID = treeID, scope = Templates.ClassScope() }
end

-- Der Plan, dem der Charakter folgt: die Vorschau am offenen Talentfenster, sonst die gemerkte Vorschau dieses Baums,
-- sonst die zuletzt übernommene eigene Vorlage – diese nur in der Talentgruppe, in der sie übernommen wurde (nach
-- einem Wechsel der Gruppe stimmten die Ränge sonst nicht). → plan oder nil
function Plan.Followed(ctx)
    if not (type(ctx) == "table" and ctx.scope) then return nil end
    local host = ns.UI and ns.UI.hosts and ns.UI.hosts.class
    if host and host.plan and host.plan.scope == ctx.scope then return host.plan end
    local plan = Plan.Recall(ctx)
    if plan then return plan end
    local key = ns.charKey or Core.charKey
    local c = key and ns.db and type(ns.db.chars) == "table" and ns.db.chars[key]
    local applied = type(c) == "table" and type(c.applied) == "table" and c.applied[ctx.scope]
    if not applied then return nil end
    local where = type(c.appliedConfig) == "table" and tonumber(c.appliedConfig[ctx.scope])
    if where and where ~= ctx.configID then return nil end      -- ohne Angabe (ältere Daten): wie bisher
    return Plan.FromTemplate(ctx.scope, applied)
end

-- Nächster Punkt für die Klassentalente. → Talentname, Name der Vorlage, Quelle (Text), { step, total, node } –
-- oder nil, wenn keine Vorlage mit Reihenfolge vorliegt oder alle Schritte gesetzt sind.
function Plan.Next(ctx)
    ctx = ctx or Plan.ClassContext()
    local plan = ctx and Plan.Followed(ctx)
    local step = plan and Plan.NextStep(plan, ctx)
    if not step then return nil end
    return step.name, plan.name or "?", Plan.OrderSource(plan.tpl), { step = step.step, total = step.total, node = step.node }
end

-- Übernimmt ezMerchant die Zeile in seinem Block beim Stufenaufstieg? (Welle 8, NEU-02: API.ShowsNextPoint)
function Plan.MerchantShowsNext()
    local api = Core.API("ezMerchant")
    if not (api and type(api.ShowsNextPoint) == "function") then return false end
    local ok, shows = pcall(api.ShowsNextPoint)
    return ok and shows == true
end

-- Nächster Punkt nur, wenn ein Klassen-Talentpunkt frei ist (eine Prüfung für die eigene Chatzeile und die
-- Schnittstelle NextPoint – Welle 23, A1). Nennt der Client die freien Punkte nicht (nil), gilt wie bisher: melden.
-- → wie Plan.Next oder nil
function Plan.NextIfFree(ctx)
    ctx = ctx or Plan.ClassContext()
    if not ctx then return nil end
    local free = Traits.Currency(ctx.configID, ctx.treeID)
    if free ~= nil and free <= 0 then return nil end        -- kein freier Punkt: nichts zu melden
    return Plan.Next(ctx)
end

-- Meldung beim Stufenaufstieg. → true, wenn eine Zeile im Chat steht
function Plan.ReportNext()
    if not ns.Enabled("nextPoint") or Plan.MerchantShowsNext() then return false end
    local name, template, source = Plan.NextIfFree()
    if not name then return false end
    ns.Print(L.NEXT_POINT:format(name, template, source))
    return true
end

-- Eigene Vorlagen mit Kennzeichen „unvollständig zugeordnet“ beim Laden einmal neu zuordnen (Templates.RemapOwn;
-- Spieltest 15.11.2026). Der Client liefert die Talentdaten erst kurz nach dem Betreten der Welt – sonst holt es das
-- Seitenteil „Vorlagen“ beim ersten Zeichnen nach.
Plan.REMAP_DELAY = 3

function Plan.RemapNow()
    local ctx = Plan.ClassContext()
    if not ctx then return nil end
    local out = Templates.RemapOwn(ctx.scope, ctx.configID, ctx.treeID)
    if out then Templates.ReportRemap(out) end
    return out
end

ns.On("PLAYER_ENTERING_WORLD", function()
    C_Timer.After(Plan.REMAP_DELAY, function() ns.Try("Plan", Plan.RemapNow) end)
end)

ns.On("PLAYER_LEVEL_UP", function()
    if not ns.Enabled("nextPoint") then return end
    C_Timer.After(Plan.NEXT_DELAY, function() ns.Try("Plan", Plan.ReportNext) end)
end)

-- Schnittstelle für andere Module (ezMerchants Block beim Stufenaufstieg, NEU-02):
-- NextPoint() → Talentname, Name der Vorlage, Quelle oder nil (auch nil, wenn der Schalter nextPoint aus ist: wer die
-- Meldung abschaltet, will sie in keinem Block – und nil ohne freien Klassen-Talentpunkt, wie die eigene Chatzeile)
function ns.API.NextPoint()
    if not ns.Enabled("nextPoint") then return nil end
    local ok, name, template, source = pcall(Plan.NextIfFree)
    if not ok or not name then return nil end
    return name, template, source
end

-- Zusage an ezMerchant (LevelUp.lua, LU.TalentAPI): NextPoint prüft die freien Punkte selbst (Welle 23, A1). Ohne
-- diese Zusage zeigt ezMerchant die Zeile „Nächster Talentpunkt“ nicht.
ns.API.NextPointChecksFree = true

---------------------------------------------------------------------------
-- Merken je Charakter und Baum
---------------------------------------------------------------------------

local function Store(create)
    return ns.CharData("plan", create)      -- ezTalentDB.chars[<Charakter>].plan (Core.lua, eine Quelle)
end

-- plan = nil: vergessen („Aktuelle Verteilung“ gewählt). Ein geänderter Plan wird samt seinen Rängen gemerkt – die
-- Tabellen bleiben dieselben, spätere Änderungen stehen also ohne weiteres Zutun in den SavedVariables.
function Plan.Remember(scope, plan)
    if not scope then return end
    local store = Store(plan ~= nil)
    if not store then return end
    if type(plan) ~= "table" then
        store[scope] = nil
        return
    end
    store[scope] = Plan.Record(plan)
end

-- Merkbare Form eines Plans ({ kind, key, name } und bei geänderten bzw. neuen Plänen die Ränge samt Reihenfolge) –
-- für die gemerkte Vorschau je Baum (Plan.Remember) und die Vormerkung der inaktiven Spezialisierung (UI.ToggleQueue).
-- copy = true: eigene Tabellen statt derselben wie im Plan. → rec oder nil
function Plan.Record(plan, copy)
    if type(plan) ~= "table" then return nil end
    -- fresh: ein neuer Plan, nie geändert (etwa „Bestes mit n Punkten“) – gilt nach /reload nicht als geändert
    local rec = { kind = plan.kind, key = plan.key, name = plan.name, from = plan.from,
        fresh = (plan.kind == "new" and not plan.edited) or nil }
    if plan.edited or plan.kind == "new" then
        local tpl = plan.tpl
        rec.edited, rec.primary, rec.orderFrom, rec.orderEdited = true, tpl.primary, tpl.orderFrom, tpl.orderEdited
        if copy then
            rec.nodes, rec.choices, rec.order = CopyMap(tpl.nodes), CopyMap(tpl.choices), CopyList(tpl.order)
        else
            rec.nodes, rec.choices, rec.order = tpl.nodes, tpl.choices, tpl.order
        end
    end
    return rec
end

-- Den gemerkten Plan dieses Baums wieder aufbauen; gibt es die Vorlage bzw. Vorauswahl nicht mehr, nil.
function Plan.Recall(ctx)
    local store = type(ctx) == "table" and ctx.scope and Store(false)
    local rec = store and store[ctx.scope]
    if type(rec) ~= "table" then return nil end
    local plan = Plan.FromRecord(rec, ctx)
    if not plan then
        store[ctx.scope] = nil
        return nil
    end
    if rec.edited then
        rec.nodes, rec.choices = plan.tpl.nodes, plan.tpl.choices      -- weiter dieselben Tabellen merken
        rec.order, rec.orderFrom, rec.orderEdited = plan.tpl.order, plan.tpl.orderFrom, plan.tpl.orderEdited
    end
    return plan
end

-- Einen Plan aus seiner merkbaren Form (Plan.Record) für diesen Baum neu aufbauen: eigene Vorlage aus ihrer Datei,
-- Vorauswahl neu zugeordnet, geänderte Ränge darüber. Gibt es die Vorlage bzw. Vorauswahl nicht mehr, nil.
function Plan.FromRecord(rec, ctx)
    if type(rec) ~= "table" or type(ctx) ~= "table" or not ctx.scope then return nil end
    local plan
    if rec.kind == "own" then
        plan = Plan.FromTemplate(ctx.scope, rec.key)
    elseif rec.kind == "preset" then
        local preset = ctx.kind == "class" and Templates.PresetByKey(rec.key) or nil
        if preset then plan = Plan.FromPreset(preset, ctx) end
    elseif rec.kind == "new" and rec.edited then
        plan = { kind = "new", name = type(rec.name) == "string" and rec.name or L.PLAN_NEW_NAME, scope = ctx.scope,
            from = type(rec.from) == "string" and rec.from or nil, tpl = { nodes = {}, choices = {}, tree = ctx.treeID } }
    end
    if not plan then return nil end
    if rec.edited then
        local clean = Templates.Clean({ nodes = rec.nodes, choices = rec.choices, order = rec.order,
            orderFrom = rec.orderFrom, orderEdited = rec.orderEdited })
        plan.tpl.nodes, plan.tpl.choices, plan.edited = clean.nodes, clean.choices, true
        plan.tpl.order, plan.tpl.orderFrom, plan.tpl.orderEdited = clean.order, clean.orderFrom, clean.orderEdited
        if rec.fresh and plan.kind == "new" then plan.edited = nil end
    end
    return plan
end

---------------------------------------------------------------------------
-- Anzeige in Blizzards Baum
---------------------------------------------------------------------------

-- Ton der Zahl je Zustand (ns.TONES in Core.lua; Design-System 2.5, Welle 22 – bis dahin eigene Zahlen in
-- Plan.COLORS: done 0.25, 1, 0.25; open 1, 0.82, 0; locked 0.7; extra 1, 0.3, 0.3; other 1, 0.6, 0.2; invalid 0.8, 0.5, 1)
-- next: der nächste Punkt der Reihenfolge (Welle 23, A2 – Rest von TL-01) in Blizzards Hellblau wie die Zeile
-- „Nächster Punkt“ im Kopf
Plan.TONE = { done = "good", open = "gold", locked = "locked", extra = "bad", other = "orange", invalid = "invalid",
    next = "next" }
Plan.OVERLAY_LEVEL = 10      -- über Blizzards Talentknopf

local function Read(frame, method)
    if type(frame) ~= "table" or type(frame[method]) ~= "function" then return nil end
    return Core.Call(frame[method], frame)
end

-- Kann dieses Fenster den Plan im Baum zeigen? (Blizzards Trait-Rahmen nennt seine Knöpfe je Knoten.)
function Plan.CanShow(frame)
    return type(frame) == "table" and type(frame.GetTalentButtonByNodeID) == "function"
end

-- Tooltip im Planen-Modus (der eigene Rahmen nimmt dann die Maus an, Blizzards Tooltip käme nicht): Name und Text des
-- Zielrangs aus dem Client, darunter Plan, Stand im Baum und die Bedienung.
function Plan.TipText(plan, ctx, node)
    local state, want = Plan.NodeState(plan, node)
    local bad = type(plan) == "table" and Plan.Check(plan, ctx).bad[node.id] or nil
    local entryID = tonumber(type(plan) == "table" and plan.tpl.choices[node.id]) or node.entry
    local entry = entryID and Traits.Entry(ctx.configID, entryID, math.max(want, 1))
    local lines = {}
    if entry and entry.text ~= "" then lines[#lines + 1] = entry.text end
    lines[#lines + 1] = L.PLAN_TIP_RANKS:format(want, node.max, node.purchased)
    local step = type(plan) == "table" and Plan.NextStep(plan, ctx)
    if step and step.node == node.id then lines[#lines + 1] = ns.Tone("next", L.PLAN_TIP_NEXT:format(step.step, step.total)) end
    if state == "other" then lines[#lines + 1] = L.PLAN_TIP_OTHER end
    if bad then lines[#lines + 1] = ns.Tone("invalid", L.PLAN_TIP_INVALID:format(Plan.BadText(ctx, bad))) end
    lines[#lines + 1] = node.choice and L.PLAN_TIP_EDIT_CHOICE or L.PLAN_TIP_EDIT
    return (entry and entry.name) or ("#" .. tostring(node.id)), table.concat(lines, "\n\n")
end

local function NewOverlay(host, button)
    local overlay = CreateFrame("Button", nil, button)
    overlay:SetAllPoints(button)
    overlay.back = overlay:CreateTexture(nil, "ARTWORK")
    overlay.back:SetSize(16, 14)
    overlay.back:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", 5, 5)
    overlay.back:SetColorTexture(0, 0, 0, 0.85)
    overlay.text = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    overlay.text:SetPoint("CENTER", overlay.back, "CENTER", 0, 0)
    overlay:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    overlay:SetScript("OnClick", function(self, mouseButton)
        if self.onAdjust then ns.Try("Plan", self.onAdjust, self.nodeID, mouseButton == "RightButton" and -1 or 1) end
    end)
    overlay:SetScript("OnEnter", function(self)
        if self.tipFn then
            local title, body = self.tipFn(self.nodeID)
            if title then Core.ShowTip(self, title, body) end
        end
    end)
    overlay:SetScript("OnLeave", GameTooltip_Hide)
    overlay:EnableMouse(false)
    host.overlays[button] = overlay
    return overlay
end

-- Plan in Blizzards Baum zeigen bzw. abgleichen. opts.editing: Planen an (Rahmen nehmen Klicks an);
-- opts.onAdjust(nodeID, delta), opts.tipFn(nodeID) → Titel, Text. → Zahl der gezeigten Zahlen
function Plan.Sync(host, ctx, plan, opts)
    opts = opts or {}
    host.overlays = host.overlays or {}
    local frame = host.source()
    local shown, used = 0, {}
    if Plan.CanShow(frame) and type(ctx) == "table" and ctx.configID and ctx.treeID and (plan or opts.editing) then
        local bad = plan and Plan.Check(plan, ctx).bad or {}
        local nextStep = plan and Plan.NextStep(plan, ctx)
        local nextNode = nextStep and nextStep.node
        for _, node in ipairs(Traits.Nodes(ctx.configID, ctx.treeID)) do
            local button = Core.Call(frame.GetTalentButtonByNodeID, frame, node.id)
            local state, want = Plan.NodeState(plan, node)
            -- so nicht gültig (Vorgänger, Schwelle): eigene Farbe – „zu viel“ bleibt rot
            if state and state ~= "extra" and bad[node.id] then state = "invalid" end
            -- Kennzeichen des nächsten Punkts der Reihenfolge (Welle 23, A2): eigene Farbe, solange er fehlt
            if node.id == nextNode and (state == "open" or state == "locked") then state = "next" end
            if type(button) == "table" and (state or opts.editing) then
                local overlay = host.overlays[button] or NewOverlay(host, button)
                used[overlay] = true
                overlay.nodeID, overlay.state, overlay.want = node.id, state, want
                overlay.onAdjust, overlay.tipFn = opts.onAdjust, opts.tipFn
                local level = Core.Num(Read(button, "GetFrameLevel"))
                if level then overlay:SetFrameLevel(level + Plan.OVERLAY_LEVEL) end
                local r, g, b = ns.ToneRGB(Plan.TONE[state])
                overlay.text:SetText(state and tostring(want) or "")
                if r then overlay.text:SetTextColor(r, g, b) end
                overlay.back:SetShown(state ~= nil)
                overlay:EnableMouse(opts.editing == true)
                overlay.editing = opts.editing == true
                overlay:Show()
                if state then shown = shown + 1 end
            end
        end
    end
    for _, overlay in pairs(host.overlays) do
        if not used[overlay] then
            overlay.nodeID, overlay.state = nil, nil
            overlay:Hide()
        end
    end
    return shown
end
