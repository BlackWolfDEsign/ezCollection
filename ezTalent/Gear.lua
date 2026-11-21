local _, ns = ...
local Core = ezCore
local Traits = ns.Traits
local Templates = ns.Templates
local Advice = ns.Advice

--[[
    Ausrüstung zur Spielweise (Paket ezgear/talent-empfehlung; Wunsch des Nutzers vom 20.11.2026, wörtlich: „ganz zum
    schluss, anhand eztalent dem ausgewählten talentbaum/spielstil ausrüstung und waffen empfehlung geben? genau wie
    hier, bzw genau da mit einfließen lassen“ – „hier“ ist ezGears Vergleich im Tooltip).

    Welche Verteilung gilt (eine Stelle, ezGear fragt nur ab):
      1. Hat der Charakter den Fragebogen im Reiter „Empfehlung“ beantwortet und gehört dessen beste Empfehlung mit
         Ausrüstungswerten zu deinem jetzigen Hauptbaum (oder hast du noch keine Punkte): diese – reason "advice".
         Die Antworten gelten je Charakter, nicht je Spezialisierung; nach einem Wechsel der Spezialisierung zählen
         darum die Talente.
      2. Sonst die berechnete Verteilung, der deine übernommenen Talente am nächsten kommen – dieselbe Rechnung wie
         „Bewerten“ (Advice.Rate: gegen das Beste des Modells mit genau deinen Punkten, Hauptbaum, sonst alle) –
         reason "talents", pct = Übereinstimmung in Prozent.
    Die Werte selbst schreibt tools/talent_sim.lua in jede berechnete Verteilung (computed.gear: Gewichte je
    ezGear-Wert, bevorzugte Waffe, Waffen der Spielweise; Rechenmodell 3, Annahmen und Quellen in Sim.GEAR). Im Spiel
    wird nichts gerechnet, nur ausgewählt.

    Schnittstelle: ezCore.API("ezTalent").GearAdvice() → { weights, weapon, weapons, source, name, key, reason, pct },
    false (sicher keine: keine Punkte und kein Fragebogen, keine Verteilung mit Werten, Fehler beim Wählen – bis zur
    nächsten Änderung) oder nil (noch nicht lesbar: Baum beim Einloggen noch nicht geliefert; nichts gemerkt, die
    nächste Frage versucht es wieder). Dieselbe Tabelle bis zur nächsten Änderung (ezGears Zwischenspeicher vergleicht
    die Gewichte über die Tabelle) – nicht verändern. Ändert sich die Wahl (Talente, Antworten, Spezialisierung),
    meldet ezTalent EZTALENT_GEAR_CHANGED über ezCore; ezGear rechnet dann neu.
]]

local Gear = {}
ns.Gear = Gear

Gear.MESSAGE = "EZTALENT_GEAR_CHANGED"
Core.RegisterMessage(Gear.MESSAGE, "ezTalent",
    "Die Verteilung, deren Ausrüstungswerte für den Charakter gelten, kann sich geändert haben (Talente, Fragebogen, Spezialisierung; lesen über ezCore.API(\"ezTalent\").GearAdvice). Zuhörer: ezGear (Gewichtung „Automatisch“).")

local cache          -- Ergebnis (false = sicher nichts), gilt bis Gear.Changed
local cacheSet = false

-- Hat die Verteilung Ausrüstungswerte des Rechenmodells?
function Gear.Has(preset)
    local c = type(preset) == "table" and type(preset.computed) == "table" and preset.computed or nil
    local g = c and c.gear
    return type(g) == "table" and type(g.weights) == "table" and next(g.weights) ~= nil
end

-- Lage des eigenen Klassenbaums wie im Reiter (UI.Context ohne Fenster) → ctx oder nil
function Gear.Context()
    local configID = Traits.ClassConfigID and Traits.ClassConfigID()
    local treeID = configID and Traits.TreeOfConfig and Traits.TreeOfConfig(configID)
    if not (configID and treeID) then return nil end
    return { kind = "class", configID = configID, treeID = treeID, scope = Templates.ClassScope() }
end

-- Hauptbaum der übernommenen Talente → Nummer, Punkte gesamt (0: noch keine Punkte) | nil (nicht lesbar: der Client
-- hat den Baum noch nicht geliefert – Advice.Tree merkt sich nur Erfolge)
local function MainTree(ctx)
    if not Advice.Tree(ctx) then return nil end
    local snap = Traits.Snapshot(ctx.configID, ctx.treeID, true)
    if type(snap) ~= "table" then return nil end
    local _, split = ns.Plan.SpellRanks({ tpl = snap }, ctx)
    local main, most, points = nil, 0, 0
    for i, n in ipairs(split or {}) do
        n = tonumber(n) or 0
        points = points + n
        if n > most then main, most = i, n end
    end
    return main, points, snap
end

-- Welche Verteilung gilt? → preset, reason ("advice" | "talents"), pct | nil, "notready" | nil
function Gear.Build(class, ctx)
    class = class or Core.PlayerClass()
    ctx = ctx or Gear.Context()
    if not (class and ctx) then return nil, "notready" end
    local main, points, snap = MainTree(ctx)
    if not snap then return nil, "notready" end
    local answers = Advice.Answers()
    if Advice.Answered(answers) then
        local list = Advice.Recommend(ctx, class, answers)
        for _, c in ipairs(type(list) == "table" and list or {}) do
            if Gear.Has(c.preset) then
                if points == 0 or tonumber(c.preset.tree) == main then return c.preset, "advice" end
                break     -- Empfehlung für einen anderen Hauptbaum (Spezialisierung gewechselt): die Talente zählen
            end
        end
    end
    if points == 0 then return nil end
    local rating, why = Advice.Rate(ctx, { tpl = snap }, nil, 0)
    if why == "tree" then return nil, "notready" end
    if type(rating) ~= "table" then return nil end
    local best = Gear.Has(rating.ref and rating.ref.preset) and rating.ref or nil
    if not best then
        for _, r in ipairs(rating.results or {}) do
            if Gear.Has(r.preset) and (not best or r.pct > best.pct) then best = r end
        end
    end
    if not best then return nil end
    return best.preset, "talents", best.pct
end

-- → { weights, weapon, weapons, source, name, key, reason, pct } | false (sicher keine) | nil (noch nicht lesbar);
-- zwischengespeichert bis Gear.Changed
function Gear.Advice()
    if cacheSet then return cache end
    -- ein Fehler landet in ezCores Fehlerliste unter ezTalent (Core.Try) und gilt bis zur nächsten Änderung als
    -- „keine“ – sonst rechnete jeder Tooltip neu und meldete den Fehler wieder (Review vor dem Merge)
    local ok, preset, reason, pct = Core.Try("ezTalent", "GearAdvice", Gear.Build)
    if ok and reason == "notready" then return nil end
    local out = false
    if preset then
        local g = preset.computed.gear
        local weapons
        if type(g.weapons) == "table" then
            weapons = {}
            for i, w in ipairs(g.weapons) do weapons[i] = w end
        end
        local weights = {}
        for k, v in pairs(g.weights) do weights[k] = v end
        out = { weights = weights, weapon = type(g.weapon) == "string" and g.weapon or nil, weapons = weapons,
            source = g.source or preset.computed.model, name = Templates.PresetName(preset), key = preset.key,
            reason = reason, pct = pct }
    end
    cache, cacheSet = out, true
    return out
end

-- Die Wahl kann sich geändert haben: vergessen und ezGear Bescheid geben
function Gear.Changed()
    cache, cacheSet = nil, false
    Core.Fire(Gear.MESSAGE)
end

-- Ereignisse wie im Reiter (UI.lua, Effects.lua); ein im Client unbekanntes Ereignis ist harmlos (Core.RegisterEvent)
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "TRAIT_CONFIG_UPDATED", "TRAIT_CONFIG_LIST_UPDATED",
    "TRAIT_TREE_CHANGED", "ACTIVE_COMBAT_CONFIG_CHANGED", "PLAYER_TALENT_UPDATE", "PLAYER_SPECIALIZATION_CHANGED",
    "CHARACTER_POINTS_CHANGED" }) do
    ns.On(event, Gear.Changed)
end

ns.API.GearAdvice = function() return Gear.Advice() end
