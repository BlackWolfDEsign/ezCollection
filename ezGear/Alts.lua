local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Bringt ein Gegenstand einem Twink etwas? (Nutzer am 24.11.2026, wörtlich: „ezgear: neue idee, wenn ich über ein item
    fahre und es mir sagt ob es einem twink etwas bringen würde einfach mit pfeil und dem namen oder so“; die Zeile baut
    Tooltip.lua, Schalter tooltipAlts.)

    Verglichen wird mit derselben Regel wie beim Spieler (Score.For → Score.Compare, Score.Verdict), nur mit dem, was der
    Twink beim letzten Anmelden hatte:
      Ausrüstung    Core.GearOf(charKey) – je Platz die Gegenstands-Kennung samt Zusatz und Bonus (ezCore/CharData.lua, ohne
                    Verzauberung wie beim Spieler); ältere Datensätze nur mit der itemID, dann zählt er ohne Zusatz
      Gewichtung    seine Wahl in ezGear (chars[charKey].scale), sonst die zuletzt geltende (chars[charKey].last: Rolle des
                    Talentbaums oder ezTalents Werte), sonst ezGears Standardwerte für das Leveln seiner Klasse
      Tragbar       aus ezCores Item-Wissen (facts.usefulForAlts: Klasse, Stufe, Rüstungs- und Waffenart der Klasse, Beruf).
                    Ob der Twink eine Waffenfertigkeit schon gelernt hat, weiß der Client nur für den Angemeldeten.
      Gegenstück    aus seinen Taschen: keines – ein Einhänder gegen seinen Zweihänder zählt allein (nie zu gut).
    Nur Twinks, denen Post gehen kann (Core.AltRecipient), und nur, was sich weitergeben lässt: nichts Seelengebundenes,
    nichts, das beim Aufheben bindet, keine Quest-Gegenstände.
    Wen die Zeile nennt, den lässt die Zeile „Twinks“ des Item-Wissens (wer es tragen kann) weg; alle anderen nennt sie weiter.
]]

local Alts = {}
ns.Alts = Alts

Alts.MAX = 3              -- so viele Namen nennt die Zeile, dann „… und n weitere“
Alts.KEEP = 200           -- so viele Antworten merkt sich Check (Blizzard baut manchen Tooltip jedes Bild neu)

---------------------------------------------------------------------------
-- Gewichtung eines Twinks
---------------------------------------------------------------------------

-- Die geltende Gewichtung des Angemeldeten merken (für seine Tooltips auf den anderen Charakteren). Standardwerte und
-- Pawn-Skalen nur als Schlüssel, ezTalents Werte als Kopie – sie gibt es nur, solange er angemeldet ist.
function Alts.Remember()
    if not (ns.db and ns.charKey) then return false end
    local weights, _, key = ns.Weights.Resolve(ns.Weights.Choice())     -- für Stufe 60; umgerechnet wird beim Vergleich
    if type(weights) ~= "table" or next(weights) == nil or type(key) ~= "string" then return false end
    -- Talente noch nicht lesbar: Die Leveling-Rolle ist nur ein Platzhalter (auch im Waffenschaden zu ezTalents Werten).
    -- Was „Automatisch“ zuletzt nahm, bleibt bis TALENTS_CHANGED; eine frühere feste Wahl gilt nicht mehr.
    local auto = ns.Weights.Choice() == "auto"
    local before = ns.Char().last
    if auto and ns.Weights.RoleUnknown() and type(before) == "table" and before.auto == true then return false end
    local last = { key = key, auto = auto or nil }
    last.tank, last.melee = ns.Weights.RoleOf(key)
    if key == "TALENT" then
        last.weights = {}
        for k, v in pairs(weights) do last.weights[k] = v end
    end
    ns.Char().last = last
    return true
end

local function Default(key)
    local weights = ns.Weights.DEFAULTS[key]
    if not weights then return nil end
    return (ns.Weights.WithWeapons(weights, key))
end

-- → Gewichte (für seine Stufe umgerechnet, Level.Adapt; Pawn-Skalen unverändert), Nahkämpfer oder Tank? | nil
function Alts.WeightsFor(key, class, level)
    local weights, tank, melee = Alts.BaseFor(key, class)
    if weights and tank ~= nil then weights = ns.Level.Adapt(weights, level, tank, class) end
    return weights, melee == true
end

-- → Gewichte für Stufe 60, Tank?, Nahkämpfer oder Tank? (Tank nil: Pawn-Skala) | nil
function Alts.BaseFor(key, class)
    local own = ns.db and ns.db.chars[key]
    own = type(own) == "table" and own or {}
    local last = type(own.last) == "table" and own.last or {}
    for _, choice in ipairs({ own.scale or false, last.key or false }) do
        if type(choice) == "string" then
            local kind, name = choice:match("^(%u+):(.+)$")
            local scale = kind == "PAWN" and type(ns.db.scales) == "table" and ns.db.scales[name] or nil
            if type(scale) == "table" and type(scale.weights) == "table" then return scale.weights, nil, nil end
            if kind == "DEF" and name:match("^(%u+)_") == class and Default(name) then
                return Default(name), ns.Weights.RoleOf(choice)
            end
            if choice == "TALENT" and type(last.weights) == "table" and next(last.weights) ~= nil then
                return last.weights, last.tank == true, last.melee == true
            end
        end
    end
    local profiles = ns.Weights.CLASS_PROFILES[class or ""]
    local name = profiles and class .. "_" .. profiles[1]
    if not name then return nil end
    return Default(name), ns.Weights.RoleOf("DEF:" .. name)
end

---------------------------------------------------------------------------
-- Twinks mit gemerkter Ausrüstung
---------------------------------------------------------------------------

local list
local answers, count = {}, 0      -- [Link] = { facts, useful, hits }: Antworten von Check

function Alts.Reset()
    list, answers, count = nil, {}, 0
end

local function Links(gear)
    local links = {}
    for slot, e in pairs(gear) do
        if type(e) == "table" then
            local id = ns.Num(e.i)
            links[slot] = type(e.s) == "string" and e.s or (id and "item:" .. id) or nil
        end
    end
    return links
end

-- → { { key, c, class, level, links = { [platz] = Link }, weights, cache }, … }
function Alts.List()
    if list then return list end
    list = {}
    for _, entry in ipairs(Core.CharacterList(function(_, key) return key ~= Core.charKey end)) do
        local c, gear = entry.c, Core.GearOf(entry.key)
        local level = ns.Num(c.level)
        local _, reachable = Core.AltRecipient(entry.key)
        if type(c.class) == "string" and level and reachable == true and type(gear) == "table" and next(gear) ~= nil then
            local weights, melee = Alts.WeightsFor(entry.key, c.class, level)
            if weights then
                list[#list + 1] = { key = entry.key, c = c, class = c.class, level = level, links = Links(gear),
                    weights = weights, melee = melee, cache = {} }
            end
        end
    end
    return list
end

---------------------------------------------------------------------------
-- Frage
---------------------------------------------------------------------------

-- Bewertet ezGear diesen Gegenstand für Twinks? (Ausrüstung an einem bewerteten Platz)
function Alts.Judges(facts)
    return type(facts) == "table" and facts.isEquipment == true and ns.Score.ScoredSlots(facts.equipLoc) ~= nil
        and #Alts.List() > 0
end

-- Lässt sich der Gegenstand weitergeben? facts: Item-Wissen (bindType 1 beim Aufheben, 4 Quest), data: Blizzards
-- Tooltip-Daten – nur dort steht, ob dieses Exemplar schon seelengebunden ist. Accountgebundenes darf an eigene Twinks.
function Alts.CanGive(facts, data)
    local bind = type(facts) == "table" and ns.Num(facts.bindType) or nil
    if bind == 1 or bind == 4 then return false end
    local P = Core.Prices
    return not P.TooltipBound(data, P.BOUND_SELF)
end

local KIND_ORDER = { better = 1, level = 2, learn = 2 }

-- Alts.Check(link, facts) → { { key, c, kind, percent (gemessen an allem, was er trägt), empty, from }, … } (jetzt besser zuerst, dann nach Gewinn), laden
-- noch Daten?
function Alts.Check(link, facts)
    if ns.IsSecret(link) or type(link) ~= "string" or type(facts) ~= "table" then return {}, false end
    local known = answers[link]
    -- das Item-Wissen baut die Liste der Twinks neu, sobald sich Stufen oder Berufe ändern
    if known and known.facts == facts and known.useful == facts.usefulForAlts then return known.hits, false end
    local out, pending, useful = {}, false, {}
    for _, a in ipairs(facts.usefulForAlts or {}) do useful[a.key] = a end
    for _, who in ipairs(Alts.List()) do
        local a = useful[who.key]
        if a then
            who.from = not a.now and ns.Num(a.from) or nil
            local kind, info = ns.Score.For(who, link)
            if kind == "pending" or (info and info.provisional) then pending = true end
            if KIND_ORDER[kind] then
                out[#out + 1] = { key = who.key, c = who.c, kind = kind, percent = info.share, empty = info.empty,
                    from = info.usableFrom }
            end
        end
    end
    table.sort(out, function(a, b)
        if KIND_ORDER[a.kind] ~= KIND_ORDER[b.kind] then return KIND_ORDER[a.kind] < KIND_ORDER[b.kind] end
        if a.percent ~= b.percent then return a.percent > b.percent end
        return a.key < b.key
    end)
    if not pending then
        if count >= Alts.KEEP then answers, count = {}, 0 end
        if not answers[link] then count = count + 1 end
        answers[link] = { facts = facts, useful = facts.usefulForAlts, hits = out }
    end
    return out, pending
end

-- Wem bringt der Gegenstand in diesem Tooltip etwas? → Liste wie Check oder nil (Schalter aus, nicht bewertet, nicht
-- weiterzugeben), laden noch Daten?
function Alts.For(link, facts, data)
    if not ns.Enabled("tooltipAlts") or not Alts.Judges(facts) or not Alts.CanGive(facts, data) then return nil, false end
    return Alts.Check(link, facts)
end

-- Die Namen, die die Zeile in diesem Tooltip nennt: { [charKey] = true } oder nil
function Alts.Named(facts, tip)
    if type(tip) ~= "table" then return nil end
    local hits = Alts.For(tip.link, facts, tip.data)
    if not hits then return nil end
    local keys = {}
    for i = 1, math.min(#hits, Alts.MAX) do keys[hits[i].key] = true end
    return keys
end

-- Zeile „Für Twinks: ↑ Mira +18 %, ↑ Torben +5 % (ab Stufe 24)“ oder nil
function Alts.Text(hits)
    if #hits == 0 then return nil end
    local parts = {}
    for i = 1, math.min(#hits, Alts.MAX) do
        local hit = hits[i]
        local icon = ns.Score.LATER[hit.kind] and ns.Marks.LearnIcon() or ns.Marks.ArrowIcon()
        local gain = hit.empty and L.ALTS_EMPTY or ns.Score.Signed(hit.percent)
        if hit.from then gain = L.ALTS_LATER:format(gain, L.TIP_FROM_LEVEL:format(hit.from)) end
        parts[i] = icon .. " " .. Core.CharName(hit.c, hit.key) .. " " .. gain
    end
    if #hits > Alts.MAX then parts[#parts + 1] = Core.More(#hits - Alts.MAX, true) end
    return L.TIP_ALTS:format(table.concat(parts, ", "))
end

---------------------------------------------------------------------------
-- Anbinden
---------------------------------------------------------------------------

ns.OnReady(function()
    Alts.Remember()
    local K = Core.Knowledge
    if K and type(K.CoverLine) == "function" then K.CoverLine("alts", ADDON, Alts.Named) end
end)
Core.Listen("GEAR_SCORES_CHANGED", function() Alts.Remember() end, "ezGear.Alts")
