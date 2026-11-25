local _, ns = ...
local Traits = ns.Traits      -- nur für Optimize.FromClient (im Spiel)

--[[
    Beste Verteilung im Spiel (Entwurf docs/talent-empfehlung.md, Abschnitt 2). Wunsch des Nutzers im Spieltest vom
    20.11.2026 zu „Prüfen“: Ein Teilbaum mit 3 Punkten gegen eine Verteilung mit 51 Punkten ist sinnlos – verglichen
    wird jetzt mit dem Besten, was das Rechenmodell mit genau so vielen Punkten setzen würde.

    Grundlage (Leitlinie 11): die Baumregeln aus dem Client (Knoten, Höchstrang, Wahl, Schwelle „benötigt n Punkte in
    den Reihen darüber“, Vorgänger – Traits.Nodes, Traits.Layout, Traits.Incoming, Traits.Thresholds; der Client nennt
    nur den Rest bis zur Schwelle, Traits.Thresholds macht daraus die feste Zahl – Spieltest 23.11.2026) und die Werte je
    Talent und Rang, die tools/talent_sim.lua in jede berechnete Verteilung schreibt (computed.weights, kumuliert). Im
    Spiel wird nur gesucht, nicht neu bewertet: dieselben Werte, dieselben Regeln wie im Werkzeug
    (docs/talent-simulation.md, „Optimierung über die Baumregeln“). Tests/empfehlung.lua prüft das gegen die Bäume
    laut wago.tools: mit 51 Punkten trifft die Suche den Wert jeder berechneten Verteilung (computed.value).

    Form eines Baums (Optimize.FromClient bzw. in den Tests aus den Client-Tabellen):
      tree = { trees = Zahl der Talentbäume,
               nodes = { { id, tree, row, max, need (Punkte in den Reihen darüber),
                           req = { Knoten, die voll sein müssen }, any = { einer davon voll },
                           options = { { entry, spell } … } (Wahlknoten: mehrere) } } }
    Ergebnis von Optimize.Best:
      { value, points, split = { Punkte je Baum }, ranks = { [Knoten] = Rang }, entries = { [Knoten] = Eintrag },
        spells = { [Zauber-ID] = Rang } }

    Auch für das Werkzeug (SSOT, abgesprochen mit der Session „Rechenmodell 3“ am 20.11.2026): Optimize.Worth,
    Optimize.Value, Optimize.Best, Optimize.RulesFor, Optimize.BestOn und Optimize.Template brauchen weder WoW-API noch
    ezCore – nur Daten
    rein, Verteilung raus; unter LuaJIT laden mit
        local ns = {} ; loadfile("ezTalent/Optimize.lua")(nil, ns) ; local Optimize = ns.Optimize
    Nur Optimize.FromClient liest den Client (ns.Traits). Diese Trennung bitte halten.

    Suche: je Talentbaum eine exakte dynamische Programmierung über die Reihen (Zustand: ausgegebene Punkte und welche
    Vorgänger voll sind), dann die beste Aufteilung auf die Bäume (Hauptbaum: mindestens mainMin Punkte und – mit
    mainMost – nicht weniger als jeder andere Baum). Höchstens points Punkte. Talente ohne Wert setzt die Suche nur als
    Füllung (Schwelle, Vorgänger, Mindestzahl im Hauptbaum); bei gleichem Wert gewinnt die Belegung mit weniger Punkten,
    dann die mit mehr Punkten in den vorderen Bäumen – fest, unabhängig von der Reihenfolge von pairs (Review 20.11.2026).
    Ein Vorgänger, den der Baum nicht kennt (unsichtbar, anderer Baum), gilt als nicht erfüllt.
]]

local Optimize = {}
ns.Optimize = Optimize

Optimize.MAIN_MIN = 31      -- wie das Werkzeug (tools/talent_sim.lua, M.MAIN_MIN): Hauptbaum bis zur letzten Reihe
local EPS = 1e-9

-- Wert eines Talents bis zu einem Rang (kumuliert); mehr Ränge als die Liste zählen wie der höchste.
function Optimize.Worth(weights, spell, rank)
    local list = type(weights) == "table" and spell and weights[spell]
    if type(list) ~= "table" or not rank or rank <= 0 or #list == 0 then return 0 end
    return tonumber(list[math.min(rank, #list)]) or 0
end

-- Summe der Werte einer Belegung { [Zauber-ID] = Rang } (Plan.SpellRanks).
function Optimize.Value(weights, spells)
    local sum = 0
    for spell, rank in pairs(spells or {}) do sum = sum + Optimize.Worth(weights, spell, rank) end
    return sum
end

-- Bit-Masken ohne Bibliothek (Lua 5.1): Zahl als Summe von Zweierpotenzen. Eigene Fassung neben Core.HasBit: Die Werkzeuge
-- laden diese Datei ohne ezCore (tools/talent_sim.lua, LoadOptimize).
local function HasBit(mask, b) return math.floor(mask / b) % 2 == 1 end
local function AddBit(mask, b) if HasBit(mask, b) then return mask end return mask + b end

-- Beste Belegung eines Talentbaums je Punktzahl: best[s] = { v, path } für s = 0 … cap (path: verkettete Liste
-- { id, rank, entry, spell, prev }). base (freiwillig): Mindestränge { ranks = { [Knoten] = Rang }, entries = { [Knoten] =
-- Eintrag } } – schon vergebene Punkte, die bleiben (Optimize.Best, opts.base).
local function TreeBest(nodes, weights, cap, base)
    local byID, bitOf, nextBit = {}, {}, 1
    for _, n in ipairs(nodes) do byID[n.id] = n end
    for _, n in ipairs(nodes) do
        for _, list in ipairs({ n.req or {}, n.any or {} }) do
            for _, id in ipairs(list) do
                if byID[id] and not bitOf[id] then bitOf[id] = nextBit nextBit = nextBit * 2 end
            end
        end
    end
    local rows, order = {}, {}
    for _, n in ipairs(nodes) do
        local r = tonumber(n.row) or 0
        if not rows[r] then rows[r] = {} order[#order + 1] = r end
        table.insert(rows[r], n)
    end
    table.sort(order)
    -- Innerhalb einer Reihe kommt ein Vorgänger vor seinem Nachfolger (Pfeil zur Seite, etwa „Improved Mind Flay“ neben
    -- „Mind Flay“ – laut wago.tools in derselben Reihe); sonst bleibt die Reihenfolge des Baums.
    for _, r in ipairs(order) do
        local list, placed, out = rows[r], {}, {}
        local inRow = {}
        for _, n in ipairs(list) do inRow[n.id] = true end
        for _ = 1, #list do
            for _, n in ipairs(list) do
                if not placed[n.id] then
                    local ready = true
                    for _, l in ipairs({ n.req or {}, n.any or {} }) do
                        for _, id in ipairs(l) do if inRow[id] and not placed[id] and id ~= n.id then ready = false end end
                    end
                    if ready then placed[n.id] = true out[#out + 1] = n end
                end
            end
        end
        for _, n in ipairs(list) do if not placed[n.id] then out[#out + 1] = n end end   -- Kreis: wie gelesen
        rows[r] = out
    end
    -- Nach der letzten Reihe, die einen Vorgänger braucht, zählt sein Bit nicht mehr: weg damit, damit gleiche Zustände
    -- zusammenfallen (sonst wächst die Zahl der Zustände mit jedem Vorgänger)
    local lastUse = {}
    for _, n in ipairs(nodes) do
        for _, list in ipairs({ n.req or {}, n.any or {} }) do
            for _, id in ipairs(list) do
                if bitOf[id] then lastUse[id] = math.max(lastUse[id] or 0, tonumber(n.row) or 0) end
            end
        end
    end
    -- Optionen je Knoten: je Eintrag und Rang der Wert. Auch Ränge ohne Wert zählen: sie füllen Schwellen und Vorgänger
    -- (der Weg zu einem wertvollen Talent); bei gleichem Wert gewinnt die Belegung mit weniger Punkten.
    -- Ein Knoten mit Mindestrang (base) bleibt mindestens so hoch und behält seine Wahl; er ist im Spiel schon gesetzt,
    -- Schwelle und Vorgänger gelten für ihn als erfüllt.
    local options, kept = {}, {}      -- je Knoten einmal (nicht je Zustand)
    for _, n in ipairs(nodes) do
        local out = {}
        local keep = math.min(tonumber(base and base.ranks and base.ranks[n.id]) or 0, n.max or 1)
        local keepEntry = keep > 0 and base.entries and base.entries[n.id] or nil
        for pass = 1, 2 do
            for _, opt in ipairs(n.options or {}) do
                if pass == 2 or not keepEntry or opt.entry == keepEntry then
                    for r = math.max(1, keep), n.max or 1 do
                        out[#out + 1] = { rank = r, v = Optimize.Worth(weights, opt.spell, r), entry = opt.entry, spell = opt.spell }
                    end
                end
            end
            if #out > 0 or not keepEntry then break end      -- Wahl des Mindestrangs unbekannt: jede Wahl
        end
        options[n], kept[n] = out, keep > 0
    end
    -- Bits je Vorgänger: ein Zustand ist (Punkte, Maske); die Maske bleibt unter nextBit
    local function Key(st) return st.spent * nextBit + st.mask end
    local layer = { { spent = 0, mask = 0, v = 0 } }
    for _, r in ipairs(order) do
        local done = 0      -- Bits, die nach dieser Reihe niemand mehr braucht
        for id, b in pairs(bitOf) do if (lastUse[id] or 0) <= r then done = done + b end end
        local index, list = {}, {}
        local function Keep(st)
            if done > 0 then
                local mask = st.mask
                for id, b in pairs(bitOf) do
                    if (lastUse[id] or 0) <= r and HasBit(mask, b) then mask = mask - b end
                end
                st.mask = mask
            end
            local key = Key(st)
            local at = index[key]
            if not at then list[#list + 1] = st index[key] = #list
            elseif st.v > list[at].v + EPS then list[at] = st end
        end
        for _, start in ipairs(layer) do
            local inner = { start }
            for _, n in ipairs(rows[r]) do
                local opts, keep = options[n], kept[n]
                if keep and #opts == 0 then
                    inner = {}      -- Mindestrang an einem Knoten ohne Eintrag: nicht still verlieren, sondern unerfüllbar
                elseif #opts > 0 and (keep or start.spent >= (n.need or 0)) then
                    local grown, index = {}, {}
                    local function Put(st)
                        local key = Key(st)
                        local at = index[key]
                        if not at then grown[#grown + 1] = st index[key] = #grown
                        elseif st.v > grown[at].v + EPS then grown[at] = st end
                    end
                    for _, c in ipairs(inner) do
                        if not keep then Put(c) end         -- ein Mindestrang darf nicht wegfallen
                        local ok = true
                        for _, id in ipairs(keep and {} or n.req or {}) do
                            if not (bitOf[id] and HasBit(c.mask, bitOf[id])) then ok = false break end
                        end
                        if ok and not keep and n.any and #n.any > 0 then
                            local one = false
                            for _, id in ipairs(n.any) do
                                if bitOf[id] and HasBit(c.mask, bitOf[id]) then one = true break end
                            end
                            ok = one
                        end
                        if ok then
                            for _, o in ipairs(opts) do
                                if c.spent + o.rank <= cap then
                                    local mask = c.mask
                                    if bitOf[n.id] and o.rank == (n.max or 1) then mask = AddBit(mask, bitOf[n.id]) end
                                    Put({ spent = c.spent + o.rank, mask = mask, v = c.v + o.v,
                                        path = { id = n.id, rank = o.rank, entry = o.entry, spell = o.spell, prev = c.path } })
                                end
                            end
                        end
                    end
                    inner = grown
                end
            end
            for _, st in ipairs(inner) do Keep(st) end
        end
        layer = list
    end
    local best = {}
    for _, st in ipairs(layer) do
        local cur = best[st.spent]
        if not cur or st.v > cur.v + EPS then best[st.spent] = st end
    end
    return best
end

-- Beste Verteilung. opts = { points (Pflicht), main (Hauptbaum, freiwillig), mainMin, mainMost (Hauptbaum nicht
-- weniger als jeder andere), full (möglichst alle Punkte setzen: zuerst die höchste erreichbare Punktzahl, dann der
-- Wert – wie eine ausgelieferte Verteilung; für das Werkzeug tools/talent_sim.lua, 20.11.2026), base (freiwillig:
-- Mindestränge { ranks = { [Knoten] = Rang }, entries = { [Knoten] = Eintrag } } – die schon vergebenen Punkte bleiben,
-- die Suche verteilt nur den Rest; Spieltest 23.11.2026, „Auf meine Punkte rechnen“) }.
-- → Ergebnis (Kopf der Datei) oder nil, Grund ("tree" | "points" | "none")
function Optimize.Best(tree, weights, opts)
    opts = opts or {}
    local cap = tonumber(opts.points)
    if type(tree) ~= "table" or type(tree.nodes) ~= "table" or #tree.nodes == 0 then return nil, "tree" end
    if not cap or cap < 0 then return nil, "points" end
    local count = tree.trees or 0
    local byTree = {}
    for _, n in ipairs(tree.nodes) do
        local t = tonumber(n.tree) or 1
        if t > count then count = t end
        byTree[t] = byTree[t] or {}
        table.insert(byTree[t], n)
    end
    local bests = {}
    local base = type(opts.base) == "table" and opts.base or nil
    for t = 1, count do bests[t] = TreeBest(byTree[t] or {}, weights, cap, base) end
    local main = tonumber(opts.main)
    if main and not bests[main] then main = nil end
    local mainMin = main and (tonumber(opts.mainMin) or 0) or 0
    -- Die anderen Bäume zusammen, jeder höchstens limit Punkte: acc[Summe] = { v, parts } – Zähl-Schleifen statt pairs,
    -- damit bei gleichem Wert immer dieselbe Aufteilung gewinnt (die erste: mehr Punkte in den vorderen Bäumen)
    local function Others(limit)
        local acc = { [0] = { v = 0, parts = {} } }
        for t = 1, count do
            if t ~= main then
                local nextAcc = {}
                for total = cap, 0, -1 do       -- absteigend: bei Gleichstand mehr Punkte in den vorderen Bäumen
                    local a = acc[total]
                    for s = 0, math.min(limit, cap - total) do
                        local b = a and bests[t][s]
                        if b then
                            local v = a.v + b.v
                            local cur = nextAcc[total + s]
                            if not cur or v > cur.v + EPS then
                                local parts = {}
                                for k, p in pairs(a.parts) do parts[k] = p end
                                parts[t] = b
                                nextAcc[total + s] = { v = v, parts = parts }
                            end
                        end
                    end
                end
                acc = nextAcc
            end
        end
        return acc
    end
    local result
    -- bei gleichem Wert: weniger Punkte, dann die Aufteilung mit mehr Punkten in den vorderen Bäumen
    local function Order(parts)
        local n, key = 0, 0
        for t = 1, count do
            local s = parts[t] and parts[t].spent or 0
            n, key = n + s, key * 64 + s
        end
        return n, key
    end
    local function Consider(v, parts)
        if opts.full and result then
            -- zuerst die Punktzahl, dann der Wert
            local n1, n2 = Order(parts), Order(result.parts)
            if n1 > n2 then result = { v = v, parts = parts } return end
            if n1 < n2 then return end
        end
        if not result or v > result.v + EPS then result = { v = v, parts = parts } return end
        if math.abs(v - result.v) <= EPS then
            local n1, k1 = Order(parts)
            local n2, k2 = Order(result.parts)
            if n1 < n2 or (n1 == n2 and k1 > k2) then result = { v = v, parts = parts } end
        end
    end
    if main then
        local shared = not opts.mainMost and Others(cap) or nil
        for m = mainMin, cap do
            local b = bests[main][m]
            if b then
                local acc = shared or Others(m)
                for total = 0, cap - m do
                    local a = acc[total]
                    if a then
                        local parts = {}
                        for k, p in pairs(a.parts) do parts[k] = p end
                        parts[main] = b
                        Consider(a.v + b.v, parts)
                    end
                end
            end
        end
    else
        local acc = Others(cap)
        for total = 0, cap do if acc[total] then Consider(acc[total].v, acc[total].parts) end end
    end
    if not result then return nil, "none" end
    local out = { value = result.v, points = 0, split = {}, ranks = {}, entries = {}, spells = {} }
    for t = 1, count do
        out.split[t] = 0
        local part = result.parts[t]
        local step = part and part.path
        while step do
            out.ranks[step.id] = step.rank
            out.entries[step.id] = step.entry
            if step.spell then out.spells[step.spell] = (out.spells[step.spell] or 0) + step.rank end
            out.split[t] = out.split[t] + step.rank
            step = step.prev
        end
        out.points = out.points + out.split[t]
    end
    return out
end

-- Regeln für eine Punktzahl, wie Bewerten und Empfehlung sie anlegen (Entwurf, Abschnitt 2): ab 31 Punkten mindestens
-- 31 im Hauptbaum (wie das Werkzeug), darunter nur „der Hauptbaum hat die meisten Punkte“.
function Optimize.RulesFor(points, main)
    points = tonumber(points) or 0
    return { points = points, main = main, mainMin = points >= Optimize.MAIN_MIN and Optimize.MAIN_MIN or 0,
        mainMost = true }
end

-- Bestes mit points Punkten nach Optimize.RulesFor, auf Mindesträngen base (freiwillig, opts.base von Optimize.Best –
-- die schon vergebenen Punkte; Spieltest 23.11.2026, „Auf meine Punkte rechnen“). Lässt sich die Regel mit den
-- vergebenen Punkten nicht erfüllen (die meisten stehen in einem anderen Baum als main, es reicht nicht für die
-- Mindestzahl im Hauptbaum), gibt die Suche schrittweise nach: erst die Mindestzahl (Hauptbaum hat weiter die meisten
-- Punkte), dann „die meisten Punkte“ (mit Mindestzahl), zuletzt beides – die vergebenen Punkte bleiben in jedem Fall
-- (im Spiel nimmt nur ein Zurücksetzen sie weg). → Ergebnis von Optimize.Best oder nil, Grund
function Optimize.BestOn(tree, weights, points, main, base)
    local rules = Optimize.RulesFor(points, main)
    rules.base = base
    local result, why = Optimize.Best(tree, weights, rules)
    if result or not base then return result, why end
    local min, tried = rules.mainMin, { [tostring(rules.mainMin) .. ":true"] = true }
    for _, step in ipairs({ { 0, true }, { min, nil }, { 0, nil } }) do
        local key = tostring(step[1]) .. ":" .. tostring(step[2])
        if not tried[key] then      -- unter 31 Punkten ist die Mindestzahl ohnehin 0: nicht zweimal suchen
            tried[key] = true
            rules.mainMin, rules.mainMost = step[1], step[2]
            result, why = Optimize.Best(tree, weights, rules)
            if result then return result end
        end
    end
    return nil, why
end

---------------------------------------------------------------------------
-- Baum aus dem Client (nur Klassentalente: drei Bäume mit Reihen, Traits.Layout)
---------------------------------------------------------------------------

-- ctx (UI.Context bzw. Plan.ClassContext). → tree (Kopf der Datei) oder nil
function Optimize.FromClient(ctx)
    if not (type(ctx) == "table" and ctx.configID and ctx.treeID and ctx.kind == "class") then return nil end
    local nodes = Traits.Nodes(ctx.configID, ctx.treeID)
    if #nodes == 0 then return nil end
    local groups = Traits.Groups(ctx.configID, ctx.treeID)
    local layout = Traits.Layout(ctx.configID, ctx.treeID, nodes, groups)
    local incoming = Traits.Incoming(nodes)
    if #groups == 0 then return nil end     -- Bäume noch nicht geliefert: nicht alles in Baum 1 werfen
    -- feste Schwelle je Knoten: der Client nennt nur den Rest bis dahin (Spieltest 23.11.2026, Traits.Thresholds)
    local thresholds = Traits.Thresholds(ctx.configID, ctx.treeID, nodes, layout, true)
    -- unsure: ein Knoten ab Reihe 2 ohne Schwelle – in den Klassenbäumen von Forever hat jede Reihe ab der zweiten eine
    -- (Client-Tabellen 71037); fehlt sie, hat der Client die Bedingungen noch nicht geliefert (Advice.Tree merkt dann nichts)
    local tree = { trees = #groups, nodes = {}, unsure = nil }
    for _, node in ipairs(nodes) do
        local where = layout[node.id]
        if where and node.visible ~= false then
            local n = { id = node.id, tree = where.tree, row = where.row or 0, max = node.max or 1,
                need = thresholds[node.id] or 0, req = {}, any = {}, options = {} }
            if n.row > 1 and n.need <= 0 and not where.aside then tree.unsure = true end
            for _, e in ipairs(incoming[node.id] or {}) do
                if e.kind == Traits.EDGE.required then n.req[#n.req + 1] = e.from
                elseif e.kind == Traits.EDGE.sufficient then n.any[#n.any + 1] = e.from end
            end
            for _, entry in ipairs(node.entries or {}) do
                n.options[#n.options + 1] = { entry = entry, spell = Traits.EntrySpell(ctx.configID, entry) }
            end
            tree.nodes[#tree.nodes + 1] = n
        end
    end
    return tree
end

-- Ergebnis von Optimize.Best als Plan-Vorlage { nodes, choices } (für Plan und die Vorschau).
function Optimize.Template(result, tree)
    local tpl = { nodes = {}, choices = {} }
    if type(result) ~= "table" then return tpl end
    local choiceNode = {}
    for _, n in ipairs(type(tree) == "table" and tree.nodes or {}) do
        if #(n.options or {}) > 1 then choiceNode[n.id] = true end
    end
    for id, rank in pairs(result.ranks) do
        tpl.nodes[id] = rank
        if choiceNode[id] and result.entries[id] then tpl.choices[id] = result.entries[id] end
    end
    return tpl
end

