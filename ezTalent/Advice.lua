local _, ns = ...
local Core = ezCore
local L = ns.L
local Traits = ns.Traits
local Templates = ns.Templates
local Plan = ns.Plan
local Optimize = ns.Optimize

--[[
    Empfehlung (Entwurf docs/talent-empfehlung.md, Abschnitt 3) – Wunsch des Nutzers im Spieltest vom 20.11.2026
    (wörtlich): „Kann eztalent auch um eine Empfehlungs"engine" erweitert werden? Sowas wie: "wie willst du spielen?"
    Spilstil oder Auswahlfragen für die passende Talentbaum.“ Dazu „Bewerten“ statt „Prüfen“: der eigene Baum gegen das
    Beste des Modells mit genau denselben Punkten (ns.Optimize).

    Daten (Leitlinie 11): die Verteilungen der Klasse (Templates.Presets – recherchiert und berechnet) mit purpose,
    tree, style (geplant) und computed.weights; die Baumregeln und Talenttexte aus dem Client; aktive Fähigkeiten über
    C_Spell.IsSpellPassive. Nichts aus fremden Addons. Hier steht nur die Rechnung – die Oberfläche baut UI.lua
    (Reiter „Empfehlung“, UI.AdviceLines).

    Antworten je Charakter: ezTalentDB.chars[<Charakter>].advice = { content, role, tree, survival, buttons, ownPoints }.
]]

local Advice = {}
ns.Advice = Advice

-- Fragen in der Reihenfolge der Anzeige; options = "roles" | "trees": hängt von der Klasse ab (Advice.Options).
Advice.QUESTIONS = {
    { key = "content", options = { "leveling", "solo", "dungeon", "raid", "pvp" } },
    { key = "role", options = "roles" },
    { key = "tree", options = "trees" },
    { key = "survival", options = { "survival", "balanced", "damage" } },
    { key = "buttons", options = { "few", "any", "many" } },
}
Advice.ROLES = { "damage", "tank", "healer" }
-- verwandte Zwecke zählen halb (Leveln ≈ Solo, Dungeon ≈ Raid)
Advice.RELATED = { leveling = "solo", solo = "leveling", dungeon = "raid", raid = "dungeon" }
-- Punkte je Frage (Entwurf 3.2)
Advice.SCORE = { content = 3, related = 1, role = 4, tree = 3, survival = 2, buttons = 2 }
-- Werte aus den Talenttexten, die als Überleben zählen (Effects.STATS-Schlüssel; Prozent bzw. Prozentpunkte)
Advice.SURVIVAL_STATS = { "stamina", "health", "armor", "dodge", "parry", "block" }

local function Has(list, value)
    for _, v in ipairs(type(list) == "table" and list or {}) do if v == value then return true end end
    return false
end

---------------------------------------------------------------------------
-- Antworten
---------------------------------------------------------------------------

-- Gespeicherte Spielweise aus der Zeit vor Rechenmodell 3 (Review 20.11.2026): damals trennten Waffe, Gestalt oder
-- Begleiter auch die Grundverteilung ab („1|axe|battle||“). Passt eine solche Antwort zu keiner Verteilung der Klasse
-- mehr, gilt ihr Hauptbaum (die Zahl vorn) – sonst stünde die rohe Kennung im Fragebogen.
function Advice.FixStyleAnswer(store, class)
    local value = type(store) == "table" and store.tree
    if type(value) ~= "string" or not value:find("|", 1, true) then return end
    for _, p in ipairs(Templates.Presets(class)) do
        if Advice.StyleId(p) == value then return end
    end
    store.tree = value:match("^(%d+)|") or nil
end

local fixed = false     -- einmal je Sitzung (Advice.FixStyleAnswer)

function Advice.Answers()
    local store = ns.CharData("advice", false)
    -- erst, wenn Klasse und Verteilungen bekannt sind (sonst würde eine gültige Variante zum Hauptbaum – Review)
    local class = not fixed and store and Core.PlayerClass()
    if class and #Templates.Presets(class) > 0 then
        fixed = true
        Advice.FixStyleAnswer(store, class)
    end
    return store or {}
end

local function Question(key)
    for _, q in ipairs(Advice.QUESTIONS) do if q.key == key then return q end end
    return nil
end

-- key: Frage oder "ownPoints"; value nil löscht die Antwort. → true, wenn gemerkt
function Advice.Set(key, value)
    if key ~= "ownPoints" and not Question(key) then return false end
    local store = ns.CharData("advice", value ~= nil)
    if not store then return value == nil end
    store[key] = value
    if ns.Gear then ns.Gear.Changed() end    -- die Empfehlung bestimmt ezGears Gewichtung mit (Gear.lua)
    return true
end

-- Alle Antworten weg (der Haken „Auf meine Punkte rechnen“ bleibt).
function Advice.Reset()
    local store = ns.CharData("advice", false)
    if not store then return end
    for _, q in ipairs(Advice.QUESTIONS) do store[q.key] = nil end
    if ns.Gear then ns.Gear.Changed() end
end

-- Ist mindestens eine Frage beantwortet?
function Advice.Answered(answers)
    for _, q in ipairs(Advice.QUESTIONS) do
        if (answers or {})[q.key] ~= nil then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Eigenschaften einer Verteilung
---------------------------------------------------------------------------

-- Rolle: style.role (geplant, docs/talent-empfehlung.md Abschnitt 5), sonst aus purpose („tank“, „healer“, sonst Schaden).
function Advice.Role(preset)
    local style = type(preset) == "table" and type(preset.style) == "table" and preset.style
    if style and Has(Advice.ROLES, style.role) then return style.role end
    if Has(preset and preset.purpose, "tank") then return "tank" end
    if Has(preset and preset.purpose, "healer") then return "healer" end
    return "damage"
end

-- Name eines Talentbaums aus dem Client (Traits.Groups), sonst „Baum n“.
function Advice.TreeName(ctx, tree)
    local groups = type(ctx) == "table" and ctx.configID and Traits.Groups(ctx.configID, ctx.treeID) or {}
    local g = groups[tonumber(tree) or 0]
    if g and g.name and g.name ~= "" then return g.name end
    return L.ADVICE_TREE_N:format(tonumber(tree) or 0)
end

-- Spielweise einer Verteilung als Schlüssel der Antwort. Rechenmodell 3 (gemergt 20.11.2026) gibt jeder Verteilung
-- style = { key, role, range, weapon, form, pet, label }; auch die Grundverteilung trägt weapon/form/pet (etwa
-- pet = "any", form = "battle"). Eine eigene Spielweise ist nur eine Variante mit key "weapon", "pet" oder "ranged"
-- (Advice.STYLE_KEYS) – Zwecke (raid, dungeon, solo, pvp) und „survival“ (Frage „Überleben oder Schaden“) gehören zur
-- Spielweise ihres Hauptbaums. Schlüssel: „2“ bzw. für eine Variante „3|pet|||succubus“ (Hauptbaum|key|Waffe|Gestalt|
-- Begleiter). STYLE_KEYS: die Spielstile mit anderen Annahmen aus tools/talent_sim.lua (M.STYLES ohne die Zwecke).
Advice.STYLE_KEYS = { weapon = true, pet = true, ranged = true, melee = true, lonewolf = true }

-- Legt style eine eigene Spielweise fest?
local function OwnStyle(style)
    return type(style) == "table" and Advice.STYLE_KEYS[style.key or ""] == true
end

function Advice.StyleId(preset)
    local style = type(preset.style) == "table" and preset.style or nil
    local id = tostring(tonumber(preset.tree) or 0)
    if OwnStyle(style) then
        id = id .. "|" .. tostring(style.key) .. "|" .. tostring(style.weapon or "") .. "|" .. tostring(style.form or "")
            .. "|" .. tostring(style.pet or "")
    end
    return id
end

-- Text der Spielweise einer Verteilung: bei einer Variante ihr Name ohne „(berechnet)“ („Treffsicherheit – mit Tier“;
-- style.label beschreibt den Unterschied, Advice.StyleTip), sonst der Name ihres Hauptbaums aus dem Client.
-- Beschreibung der Spielweise (style.label in der Sprache des Clients) oder nil – im Menü der Frage „Spielweise“ als
-- Tooltip, damit z. B. „Treffsicherheit“ verrät, dass die Grundverteilung ohne Tier rechnet (Review 20.11.2026).
function Advice.StyleTip(preset)
    local style = type(preset) == "table" and type(preset.style) == "table" and preset.style or nil
    local label = style and style.label
    if type(label) == "table" then label = Core.IsGerman() and label.de or label.en or label.de end
    return type(label) == "string" and label ~= "" and label or nil
end

function Advice.StyleLabel(ctx, preset)
    if OwnStyle(preset.style) then
        local name = Templates.PresetName(preset):gsub("%s*%([^%)]*%)%s*$", "")
        if name ~= "" then return name end
    end
    return Advice.TreeName(ctx, preset.tree)
end

-- Antworten einer Frage für diese Klasse: { { value, text } }. Rollen und Spielweisen nur, was die Verteilungen hergeben
-- (Spielweise: die der gewählten Rolle).
function Advice.Options(key, ctx, class, answers)
    local q = Question(key)
    if not q then return {} end
    local out = {}
    if q.options == "roles" then
        local have = {}
        for _, p in ipairs(Templates.Presets(class)) do have[Advice.Role(p)] = true end
        for _, role in ipairs(Advice.ROLES) do
            if have[role] then out[#out + 1] = { value = role, text = L["ADVICE_role_" .. role] } end
        end
    elseif q.options == "trees" then
        local seen = {}
        local role = (answers or {}).role
        for i, p in ipairs(Templates.Presets(class)) do
            local id = Advice.StyleId(p)
            if tonumber(p.tree) and not seen[id] and (not role or Advice.Role(p) == role) then
                seen[id] = true
                out[#out + 1] = { value = id, text = Advice.StyleLabel(ctx, p), tip = Advice.StyleTip(p),
                    tree = tonumber(p.tree), order = i }
            end
        end
        table.sort(out, function(a, b)
            if a.tree ~= b.tree then return a.tree < b.tree end
            return a.order < b.order
        end)
        out[#out + 1] = { value = "any", text = L.ADVICE_tree_any }
    else
        for _, value in ipairs(q.options) do out[#out + 1] = { value = value, text = L["ADVICE_" .. key .. "_" .. value] } end
    end
    return out
end

-- Text einer Antwort (nil: unbeantwortet).
function Advice.AnswerText(key, value, ctx, class)
    if value == nil then return nil end
    for _, o in ipairs(Advice.Options(key, ctx, class, Advice.Answers())) do
        if o.value == value then return o.text end
    end
    return tostring(value)
end

local facts = {}        -- [configID:treeID:Schlüssel] = Eigenschaften aus dem Client (Advice.Facts)

-- Was die Talente einer Verteilung im Client bedeuten: Überleben laut Talenttext und aktive Fähigkeiten.
-- → { survival (Summe der Prozent bzw. Prozentpunkte aus SURVIVAL_STATS; mit computed.parts: Anteil der Überlebens-Werte
--     in %), survivalParts = { { key, value, percent } } (die zwei größten, für die Begründung), buttons (Zahl der aktiven
--     Fähigkeiten oder nil, wenn der Client das nicht sagt), found, total }
function Advice.Facts(preset, ctx)
    if type(preset) ~= "table" or type(ctx) ~= "table" or not ctx.configID then return {} end
    local id = ctx.configID .. ":" .. tostring(ctx.treeID) .. ":" .. tostring(preset.key)
    if facts[id] then return facts[id] end
    local plan = Plan.FromPreset(preset, ctx) or { tpl = { nodes = {}, choices = {} } }
    local out = { survival = 0, survivalParts = {}, found = plan.found, total = plan.total }
    local Effects = ns.Effects
    local totals = Effects.StatTotals(Effects.PlanItems(ctx.configID, ctx.treeID, plan))
    for _, key in ipairs(Advice.SURVIVAL_STATS) do
        local value = Effects.TotalOf(totals, key, true)
        if value > 0 then
            out.survival = out.survival + value
            out.survivalParts[#out.survivalParts + 1] = { key = key, value = value, percent = true }
        end
    end
    table.sort(out.survivalParts, function(a, b) return a.value > b.value end)
    for i = #out.survivalParts, 3, -1 do out.survivalParts[i] = nil end
    -- geplant: Werte getrennt nach Art (computed.parts) – dann zählt ihr Anteil an Überleben
    local parts = type(preset.computed) == "table" and type(preset.computed.parts) == "table" and preset.computed.parts
    if parts and type(parts.survival) == "table" and (preset.computed.value or 0) > 0 then
        local sum = 0
        for _, t in ipairs(preset.talents or {}) do sum = sum + Optimize.Worth(parts.survival, t.spell, t[2]) end
        out.survival, out.fromParts = sum / preset.computed.value * 100, true
    end
    -- aktive Fähigkeiten: Talente, deren Zauber der Client nicht als passiv kennt
    local spellAPI = rawget(_G, "C_Spell")
    local passive = spellAPI and spellAPI.IsSpellPassive
    if type(passive) == "function" then
        local n, answered = 0, false
        for _, node in ipairs(Traits.Nodes(ctx.configID, ctx.treeID)) do
            local rank = tonumber(plan.tpl.nodes[node.id] or plan.tpl.nodes[tostring(node.id)]) or 0
            local entry = rank > 0 and Plan.EntryOf(plan, node)
            local spell = entry and Traits.EntrySpell(ctx.configID, entry)
            if spell then
                local isPassive = Core.Call(passive, spell)
                if isPassive == false then n = n + 1 end
                if isPassive == true or isPassive == false then answered = true end
            end
        end
        if answered then out.buttons = n end     -- sagt der Client zu keinem Zauber etwas: unbekannt (nil), nicht 0
    end
    facts[id] = out
    return out
end

function Advice.Forget()
    facts = {}
    Advice.ForgetBest()
end

---------------------------------------------------------------------------
-- Empfehlung
---------------------------------------------------------------------------

-- Rang 0 … 1 eines Werts unter allen (kleinster 0, größter 1; alle gleich: 0,5).
local function Norm(value, low, high)
    if not value or not low or high - low < 1e-9 then return 0.5 end
    return (value - low) / (high - low)
end

-- Passt eine Verteilung zur gewählten Spielweise? Genau dieselbe Spielweise (Advice.StyleId), bei einer Antwort nur
-- mit dem Hauptbaum („2“) jede Verteilung dieses Baums. "any" bzw. keine Antwort: jede.
function Advice.StyleMatches(preset, answer)
    if answer == nil or answer == "any" then return true end
    answer = tostring(answer)
    if Advice.StyleId(preset) == answer then return true end
    local n = tonumber(answer)
    return n ~= nil and not answer:find("|", 1, true) and tonumber(preset.tree) == n
end

-- Text einer Antwort zur Spielweise – aus der Antwort, nicht aus der empfohlenen Verteilung (Review 20.11.2026): die
-- Verteilung mit genau dieser Spielweise, bei einer Antwort nur mit dem Hauptbaum dessen Name.
function Advice.StyleAnswerLabel(ctx, class, answer)
    if answer == nil or answer == "any" then return nil end
    answer = tostring(answer)
    for _, p in ipairs(Templates.Presets(class)) do
        if Advice.StyleId(p) == answer then return Advice.StyleLabel(ctx, p) end
    end
    local n = not answer:find("|", 1, true) and tonumber(answer)
    if n then return Advice.TreeName(ctx, n) end
    return nil
end

-- → Kandidaten { { preset, score, reasons = { Text }, facts } }, beste zuerst; leer ohne Antworten oder Verteilungen.
-- Rolle und Spielweise sind feste Bedingungen (Spielbefund vom 20.11.2026: „Kampf“ gewählt, „Meucheln – PvP“
-- empfohlen, weil es für Kampf keine PvP-Verteilung gibt – Nutzer: „macht das sinn?“): Die Liste enthält nur
-- Verteilungen der gewählten Rolle und Spielweise (solange es welche gibt). Dazu
--   list.missing      = { content, style, role, styleNone } – keine davon ist für den gewählten Zweck gedacht (die
--                       erste ist die nächstbeste dieser Spielweise); styleNone: zur gewählten Spielweise gibt es in
--                       der Rolle gar keine Verteilung, die Liste nimmt alle Spielweisen; role: Rolle beantwortet und
--                       vorhanden,
--   list.alternatives = { Kandidaten anderer Spielweisen derselben Rolle, die für den Zweck gedacht sind }.
function Advice.Recommend(ctx, class, answers)
    answers = answers or Advice.Answers()
    local list = {}
    if not Advice.Answered(answers) then return list end
    local presets = Templates.Presets(class)
    -- Rolle schließt aus, solange es eine passende gibt
    local anyRole = false
    for _, p in ipairs(presets) do if answers.role and Advice.Role(p) == answers.role then anyRole = true end end
    local pool = {}
    for i, p in ipairs(presets) do
        if not (anyRole and Advice.Role(p) ~= answers.role) then
            pool[#pool + 1] = { preset = p, score = 0, reasons = {}, order = i }
        end
    end
    local S = Advice.SCORE
    local lowS, highS, lowB, highB
    for _, c in ipairs(pool) do
        local p = c.preset
        if answers.content then
            if Has(p.purpose, answers.content) then
                c.score = c.score + S.content
                c.reasons[#c.reasons + 1] = L.ADVICE_WHY_CONTENT:format(L["ADVICE_content_" .. answers.content])
            elseif Advice.RELATED[answers.content] and Has(p.purpose, Advice.RELATED[answers.content]) then
                c.score = c.score + S.related
                c.reasons[#c.reasons + 1] = L.ADVICE_WHY_RELATED:format(L["ADVICE_content_" .. Advice.RELATED[answers.content]])
            end
        end
        if answers.role and Advice.Role(p) == answers.role then
            c.score = c.score + S.role
            c.reasons[#c.reasons + 1] = L.ADVICE_WHY_ROLE:format(L["ADVICE_role_" .. answers.role])
        end
        if answers.tree and answers.tree ~= "any" and Advice.StyleMatches(p, answers.tree) then
            c.score = c.score + S.tree
            c.reasons[#c.reasons + 1] = L.ADVICE_WHY_TREE:format(Advice.StyleLabel(ctx, p))
        end
        if (answers.survival and answers.survival ~= "balanced") or (answers.buttons and answers.buttons ~= "any") then
            c.facts = Advice.Facts(p, ctx)
            local s, b = c.facts.survival, c.facts.buttons
            if s then lowS, highS = math.min(lowS or s, s), math.max(highS or s, s) end
            if b then lowB, highB = math.min(lowB or b, b), math.max(highB or b, b) end
        end
    end
    for _, c in ipairs(pool) do
        local f = c.facts
        -- Variante „Überleben“ des Rechenmodells (style.key = "survival") gilt als die mit dem meisten Überleben –
        -- statt der Wertung aus dem Text, nicht zusätzlich (Review 20.11.2026: sonst mehr als der Zweck)
        local sk = type(c.preset.style) == "table" and c.preset.style.key
        if f and answers.survival and answers.survival ~= "balanced" then
            local n = sk == "survival" and 1 or Norm(f.survival, lowS, highS)
            c.score = c.score + S.survival * (answers.survival == "survival" and n or (1 - n))
            if #f.survivalParts > 0 then
                local parts = {}
                for _, part in ipairs(f.survivalParts) do
                    parts[#parts + 1] = (L["STAT_" .. part.key] or part.key) .. " " .. ns.Effects.StatValue(part.value, part.percent)
                end
                c.reasons[#c.reasons + 1] = L.ADVICE_WHY_SURVIVAL:format(table.concat(parts, ", "))
            elseif answers.survival == "damage" then
                -- keine Talente mit Ausdauer, Rüstung o. Ä.: für „mehr Schaden“ ein Grund, sonst keiner (Spielbefund
                -- 20.11.2026: „kein Überlebenswert im Talenttext“ verstand niemand)
                c.reasons[#c.reasons + 1] = L.ADVICE_WHY_DAMAGE_ONLY
            end
        end
        if sk == "survival" and answers.survival == "survival" then
            c.reasons[#c.reasons + 1] = L.ADVICE_WHY_SURVIVAL_VARIANT
        end
        if f and answers.buttons and answers.buttons ~= "any" and f.buttons then
            local n = Norm(f.buttons, lowB, highB)
            c.score = c.score + S.buttons * (answers.buttons == "many" and n or (1 - n))
            c.reasons[#c.reasons + 1] = Core.Plural(f.buttons, L.ADVICE_WHY_BUTTONS_ONE, L.ADVICE_WHY_BUTTONS_MANY)
        end
    end
    table.sort(pool, function(a, b)
        if math.abs(a.score - b.score) > 1e-9 then return a.score > b.score end
        local ra, rb = Templates.IsComputed(a.preset) and 1 or 0, Templates.IsComputed(b.preset) and 1 or 0
        if ra ~= rb then return ra < rb end          -- recherchiert vor berechnet
        return a.order < b.order
    end)
    -- Spielweise als feste Bedingung: die anderen höchstens als Alternative (nur solche für den gewählten Zweck)
    local anyStyle = false
    for _, c in ipairs(pool) do if Advice.StyleMatches(c.preset, answers.tree) then anyStyle = true end end
    list.alternatives = {}
    for _, c in ipairs(pool) do
        if not anyStyle or Advice.StyleMatches(c.preset, answers.tree) then
            list[#list + 1] = c
        elseif answers.content and Has(c.preset.purpose, answers.content) then
            list.alternatives[#list.alternatives + 1] = c
        end
    end
    -- Gibt es für den Zweck in dieser Spielweise nichts (oder die Spielweise gar nicht), sagt die Empfehlung es
    local style = Advice.StyleAnswerLabel(ctx, class, answers.tree)
    if #list > 0 and answers.tree ~= nil and answers.tree ~= "any" and not anyStyle then
        list.missing = { style = style or tostring(answers.tree), styleNone = true }
    elseif answers.content and #list > 0 then
        local found = false
        for _, c in ipairs(list) do if Has(c.preset.purpose, answers.content) then found = true end end
        if not found then
            list.missing = { content = answers.content, style = style, role = (answers.role and anyRole) or nil }
        end
    end
    return list
end

---------------------------------------------------------------------------
-- Bestes mit n Punkten (ns.Optimize) und Bewerten
---------------------------------------------------------------------------

local trees, bests = {}, {}

function Advice.ForgetBest()
    trees, bests = {}, {}
end

-- Baum aus dem Client, je Konfiguration und Baum gemerkt, bis sich Punkte ändern: Knoten und Pfeile ändern sich im
-- Spiel nicht, die festen Schwellen rechnet Traits.Thresholds aber aus dem Rest, den der Client zum jetzigen Stand nennt
-- (Spieltest 23.11.2026) – darum neu lesen nach TRAIT_NODE_CHANGED und TRAIT_CONFIG_UPDATED (unten).
function Advice.Tree(ctx)
    if type(ctx) ~= "table" or not ctx.configID then return nil end
    local id = ctx.configID .. ":" .. tostring(ctx.treeID)
    if trees[id] then return trees[id] end
    -- nur Erfolge merken: beim ersten Zeichnen kann der Client den Baum noch nicht liefern (Review 20.11.2026); ebenso
    -- nicht, solange ab Reihe 2 Schwellen fehlen (Optimize.FromClient: unsure) – sonst bliebe die Reihen-Sperre offen
    local tree = Optimize.FromClient(ctx)
    if tree and not tree.unsure then trees[id] = tree end
    return tree
end

-- Schon vergebene Punkte als Mindestränge für die Suche (Optimize.Best, opts.base): die gekauften Ränge samt
-- gestaffelten, wie Plan.Progress sie zählt (Traits.Snapshot). → { ranks, entries, points } oder nil (nichts vergeben)
function Advice.Base(ctx)
    if type(ctx) ~= "table" or not ctx.configID then return nil end
    local snap = Traits.Snapshot(ctx.configID, ctx.treeID, false)
    local points = Traits.Points(snap)
    if points <= 0 then return nil end
    return { ranks = snap.nodes, entries = snap.choices, points = points }
end

-- Vergebene Punkte für die Suche „auf denselben Punkten“ (Advice.BestPlan mit keep, Advice.Rate): base (Advice.Base) und
-- die Ränge an Knoten, die die Suche nicht kennt (unsichtbar, ohne Lage) – sie bleiben im Plan, zählen aber nicht für
-- die Suche. → base oder nil, outside = { [Knoten] = Rang }, outsidePoints
local function KeepBase(ctx, tree)
    local base = tree and Advice.Base(ctx) or nil
    local outside, outsidePoints = {}, 0
    if base then
        local known = {}
        for _, n in ipairs(tree.nodes) do known[n.id] = true end
        for id, rank in pairs(base.ranks) do
            if not known[id] then outside[id], outsidePoints = rank, outsidePoints + (tonumber(rank) or 0) end
        end
    end
    return base, outside, outsidePoints
end

-- Enthält der Plan alle vergebenen Ränge samt Wahl?
local function HasBase(plan, base)
    local nodes, choices = plan.tpl.nodes or {}, plan.tpl.choices or {}
    for id, rank in pairs(base.ranks) do
        if (tonumber(nodes[id] or nodes[tostring(id)]) or 0) < rank then return false end
        local entry = base.entries and base.entries[id]
        local chosen = tonumber(choices[id] or choices[tostring(id)])
        if entry and chosen and chosen ~= entry then return false end
    end
    return true
end

-- Schlüssel der Mindestränge fürs Merken der Suche ("" ohne).
local function BaseKey(base)
    if not base then return "" end
    local parts = {}
    for id, rank in pairs(base.ranks or {}) do
        parts[#parts + 1] = tostring(id) .. "=" .. tostring(rank) .. "/" .. tostring(base.entries and base.entries[id] or "")
    end
    table.sort(parts)
    return table.concat(parts, ",")
end

-- Bestes des Modells einer berechneten Verteilung mit points Punkten (gemerkt). base (freiwillig, Advice.Base): die
-- vergebenen Punkte bleiben, gesucht wird nur der Rest (Optimize.BestOn). → Ergebnis von Optimize.Best oder nil
function Advice.Best(ctx, preset, points, base)
    local c = type(preset) == "table" and type(preset.computed) == "table" and preset.computed
    if not (c and type(c.weights) == "table") then return nil end
    local tree = Advice.Tree(ctx)
    if not tree then return nil end
    local id = ctx.configID .. ":" .. tostring(ctx.treeID) .. ":" .. tostring(preset.key) .. ":" .. tostring(points)
        .. ":" .. BaseKey(base)
    if bests[id] == nil then
        bests[id] = Optimize.BestOn(tree, c.weights, points, tonumber(preset.tree), base) or false
    end
    return bests[id] or nil
end

-- Punkte, die der Charakter jetzt hat (frei + ausgegeben, Client).
function Advice.OwnPoints(ctx)
    local free, spent = Traits.Currency(ctx.configID, ctx.treeID)
    if not free then return nil end
    return free + (spent or 0)
end

-- Vorschau „Bestes mit n Punkten“ einer berechneten Verteilung: ein neuer Plan (kind "new", wie „Anpassen“ ohne Vorlage).
-- keep = true („Auf meine Punkte rechnen“, Spieltest 23.11.2026): baut auf den schon vergebenen Punkten auf
-- (Advice.Base) – „Übernehmen“ setzt dann nur die freien Punkte, keine Zahl im Baum wird rot; der Plan merkt das als
-- plan.keep (Advice.Rate bewertet ihn gegen das Beste auf denselben Punkten). Ohne vergebene Punkte das Beste von Grund
-- auf. Beides hält die Reihen-Sperre des Clients (Traits.Thresholds).
-- → Plan oder nil, Grund ("points": keine Punkte, "flat": mit so wenigen Punkten bringt nichts etwas – das Beste wäre
-- leer, "none": keine Werte oder keine Suche möglich)
function Advice.BestPlan(ctx, preset, points, keep)
    if not points or points <= 0 then return nil, "points" end
    local tree = Advice.Tree(ctx)
    local base, outside, outsidePoints = nil, {}, 0
    if keep then base, outside, outsidePoints = KeepBase(ctx, tree) end
    local result = Advice.Best(ctx, preset, points - outsidePoints, base)
    if not result then return nil, "none" end
    if result.points + outsidePoints == 0 then return nil, "flat" end
    local tpl = Optimize.Template(result, tree)
    for id, rank in pairs(outside) do
        tpl.nodes[id] = rank
        if base.entries[id] then tpl.choices[id] = base.entries[id] end
    end
    tpl.tree, tpl.primary = ctx.treeID, tonumber(preset.tree)
    -- from: Herkunft – die Zeile dieser Verteilung bleibt in „Vorlagen“ und „Empfehlung“ markiert (UI.PresetLoaded)
    return { kind = "new", scope = ctx.scope, tpl = tpl, from = preset.key, keep = base ~= nil or nil,
        name = L.ADVICE_BEST_NAME:format(points, Templates.PresetName(preset)) }
end

-- Bewerten: ein Plan (nil: der Baum, wie er steht – mit vorgemerkten Punkten) gegen das Beste des Modells mit genau
-- seinen Punkten. prefer: Schlüssel der Verteilung, die als Bezug gilt (die Empfehlung), sonst die deines Hauptbaums
-- mit dem besten Ergebnis. Bewertet werden die Verteilungen deines Hauptbaums und die gewünschte; all = true (die
-- Einzelheiten) alle der Klasse – jede Suche kostet im Spiel einige Millisekunden, darum nur auf Wunsch. Gibt es im
-- Hauptbaum keine berechnete Verteilung, zählen alle.
-- → { points, split, results (Templates.Rate), ref (eine davon), changes = { bis zu limit Zeilen, größter Wert zuerst } }
--   oder nil, Grund ("empty" | "none" | "tree")
function Advice.Rate(ctx, plan, prefer, limit, all)
    if not Advice.Tree(ctx) then return nil, "tree" end
    local source = plan or { tpl = Traits.Snapshot(ctx.configID, ctx.treeID, false) }
    local ranks, split = Plan.SpellRanks(source, ctx)
    -- ein Plan, der auf den vergebenen Punkten aufbaut (Advice.BestPlan mit keep), zählt gegen das Beste auf denselben
    -- Punkten – sonst hieße „Bestes mit n Punkten“ in der Bewertung weniger als 100 %; der Baum selbst und jeder andere
    -- Plan gegen das Beste von Grund auf (Spieltest 23.11.2026). Stehen inzwischen andere Punkte im Baum, als der Plan
    -- enthält, zählt auch er von Grund auf (sonst ginge die Bewertung über 100 %; code-reviewer 23.11.2026).
    local base, outsidePoints = nil, 0
    if type(plan) == "table" and plan.keep then
        local b, _, op = KeepBase(ctx, Advice.Tree(ctx))
        if b and HasBase(plan, b) then base, outsidePoints = b, op end
    end
    local opts = { all = all or nil, keep = function(preset) return prefer ~= nil and preset.key == prefer end,
        best = function(preset, points)
            return (base and Advice.Best(ctx, preset, points - outsidePoints, base)) or Advice.Best(ctx, preset, points)
        end }
    local results, why = Templates.Rate(ranks, split, Core.PlayerClass(), 99, opts)
    if not results and why == "none" and not all then
        opts.all = true
        results, why = Templates.Rate(ranks, split, Core.PlayerClass(), 99, opts)
    end
    if not results then return nil, why end
    local points, main, most = 0, nil, -1
    for i, n in ipairs(split) do
        points = points + n
        if n > most then main, most = i, n end
    end
    local ref
    for _, r in ipairs(results) do if prefer and r.preset.key == prefer then ref = r end end
    if not ref then
        for _, r in ipairs(results) do
            if tonumber(r.preset.tree) == main and (not ref or r.pct > ref.pct) then ref = r end
        end
    end
    ref = ref or results[1]
    local changes = {}
    for _, row in ipairs(ref.more) do changes[#changes + 1] = row end
    for _, row in ipairs(ref.less) do changes[#changes + 1] = row end
    for _, row in ipairs(changes) do row.gain = row.theirs > row.mine end
    table.sort(changes, function(a, b)
        if math.abs(a.delta - b.delta) > 1e-9 then return a.delta > b.delta end
        return a.spell < b.spell
    end)
    for i = #changes, (limit or 3) + 1, -1 do changes[i] = nil end
    return { points = points, split = split, results = results, ref = ref, changes = changes }
end

-- Ampel einer Bewertung: "good" ab 95 %, "gold" ab 80 %, sonst "bad".
function Advice.Tone(pct)
    if (pct or 0) >= 95 then return "good" end
    if (pct or 0) >= 80 then return "gold" end
    return "bad"
end

-- Neue Welt bzw. andere Spezialisierung: Baum, Suchen und Eigenschaften neu lesen (Review 20.11.2026: sonst blieben
-- sie bis /reload). Knoten, Pfeile und die Werte je Talent ändern sich dazwischen nicht (die Schwellen: unten).
ns.On("PLAYER_ENTERING_WORLD", function() Advice.Forget() end)
ns.On("TRAIT_TREE_CHANGED", function() Advice.Forget() end)
-- Punkte geändert (gesetzt, vorgemerkt, übernommen, zurückgesetzt): die festen Schwellen hängen am Rest, den der Client
-- jetzt nennt, die Mindestränge an den vergebenen Punkten – Baum und Suchen neu (Advice.Tree; code-reviewer 23.11.2026)
ns.On("TRAIT_NODE_CHANGED", function() Advice.ForgetBest() end)
ns.On("TRAIT_CONFIG_UPDATED", function() Advice.ForgetBest() end)
