local _, ns = ...
local Core = ezCore

--[[
    Gewichte für die Stufe des Charakters, Rüstung aus der Formel des Clients und die eigene Rüstungsart (25.11.2026; Nutzer
    mit Fotos eines Paladins auf Stufe 18: „Ist die Bewertung von ezgear nicht irreführend?“, „Enterprise... Vorher vollständig
    überlegen... Nicht halb“, „Item Bewertung Paladin... Das ist doch käse... Rüstungsklasse beachten?“; gewählt „Rüstungsart
    zuerst (Empfohlen)“ und „Ganzer Charakter (Empfohlen)“). Herleitung, Beispiele und Grenzen: docs/ezgear-bewertung.md.

    Was vorher falsch war: Alle Gewichte galten für Stufe 60, und Rüstung zählte je nach Quelle 0,01 (ezTalent) oder 0,1
    (ezGears Tabelle) je Punkt – dieselben Handschuhe waren −74 % oder +48 %.

    Level.Adapt(gewichte, stufe, tank, klasse, kennt) → Gewichte für die Stufe (dieselbe Tabelle je Eingabe, Score.Of vergleicht sie):
      Punkt-Werte      Stärke, Ausdauer, Angriffskraft, Zaubermacht, Waffenschaden …: bleiben. Auf kleiner Stufe bringt ein
                       Punkt von allem mehr, untereinander bleibt das Verhältnis.
      Prozent-Werte    Treffer, Krit, Ausweichen, Verteidigung … (Level.PERCENT): geteilt durch Level.Factor – 1 % Krit ist auf
                       Stufe 18 genauso 1 %, ein Punkt Ausdauer aber sechsmal so viel wie auf 60.
      Rüstung          Ausdauer × Level.ArmorPerStamina: beides verlängert das Leben, also wird es über die Formel des Clients
                       verrechnet (erlittener Nahkampfschaden × K / (K + Rüstung), K = ExpectedStat.ArmorConstant). Beim Druiden
                       als Tank vervielfacht die Bärengestalt die Rüstung der Gegenstände (Level.FORM_ARMOR).
    Pawn-Skalen bleiben, wie der Spieler sie eingefügt hat. Ohne Client-Tabelle bleiben alle Gewichte, wie sie sind.

    Level.OwnArmor(wearer) → die eigene Rüstungsart (1 Stoff, 2 Leder, 3 Schwere Rüstung, 4 Platte) oder nil: die schwerste,
      deren Fertigkeit der Charakter hat (ezCore.Proficiency; ein Twink: laut Client-Tabellen auf seiner Stufe).
    Level.EffectOf(diff, melee) → was der Tausch (Summen der Werte, neu minus alt) beim Spieler ausmacht, aus Werten des Clients:
      { health, taken, dealt } in Prozent, jedes nil, wenn es nichts ändert oder nicht lesbar ist; nil, wenn alles fehlt.
]]

local Level = {}
ns.Level = Level

-- Werte, die in Prozentpunkten (bzw. Verteidigung: 0,04 % je Punkt) wirken – unabhängig von der Stufe
Level.PERCENT = { "HIT", "CRIT", "SPELLHIT", "SPELLCRIT", "HASTE", "EXPERTISE", "DODGE", "PARRY", "BLOCK", "DEFENSE" }

-- ANNAHMEN (docs/ezgear-bewertung.md): 1 % weniger erlittener Schaden zählt so viel wie 1,875 % mehr Gesundheit (Rechenmodell
-- von ezTalent, Tank: taken 1,5 gegen health 0,8 – weniger Schaden spart auch Heilung); 80 % des Schadens sind körperlich;
-- Gesundheit eines Tanks 1,35 × Erwartung des Clients; Rüstung als Anteil von K: Tank 0,55 (bis Stufe 20) bis 1,1 (Stufe 60),
-- alle anderen 0,35.
Level.TOP = 60
Level.TAKEN_PER_HEALTH = 1.875
Level.PHYSICAL = 0.8
Level.HEALTH_PER_STAMINA = 10        -- hppersta laut Client-Tabellen, auf jeder Stufe 10
Level.HEALTH_SHARE = { tank = 1.35, other = 1 }
Level.ARMOR_SHARE = { tank = { 0.55, 1.1 }, other = { 0.35, 0.35 } }
Level.ARMOR_FROM = 20                -- ab dieser Stufe wächst der Anteil bis Level.TOP
-- Gestalten, die die Rüstung der Gegenstände vervielfachen: Anteil dazu ab der Lernstufe (Client-Tabellen Build 1.60.1.71037,
-- SpellEffect Aura 142, Bear Form (Passive) 1178: +180 %, Dire Bear Form (Passive) 9635: +360 %; Abgleich mit dem Build:
-- tools/Tests/gewichtung_talente_test.lua). Höchste zuerst.
Level.FORM_ARMOR = { DRUID = {
    { from = 40, spell = 9634, passive = 9635, bonus = 3.6 },
    { from = 10, spell = 5487, passive = 1178, bonus = 1.8 },
} }

local function Expected(level)
    local CD = Core.ClientData
    return CD and type(CD.Expected) == "function" and CD.Expected(level) or nil
end

-- Stufe des Spielers oder nil
function Level.Player()
    local level = ns.Num(ns.Call(UnitLevel, "player"))
    return level and level > 0 and level or nil
end

-- Wie viel mehr ein Punkt Ausdauer (und jeder Punkt-Wert) auf dieser Stufe bewirkt als auf Stufe 60 – Verhältnis der erwarteten
-- Gesundheit laut Client → Zahl ≥ 1 oder nil
function Level.Factor(level)
    local now, top = Expected(level), Expected(Level.TOP)
    if not (now and top) or now.health <= 0 then return nil end
    return math.max(1, top.health / now.health)
end

-- Anteil, um den die Tank-Gestalt dieser Klasse auf dieser Stufe die Rüstung der Gegenstände erhöht (0 ohne). known(form)
-- → gelernt? (der Spieler: Level.KnownForm); ohne known zählt die Stufe allein (Twinks: nur ihre Stufe ist bekannt)
function Level.FormBonus(class, level, known)
    for _, form in ipairs(Level.FORM_ARMOR[class or ""] or {}) do
        if level and level >= form.from and (known == nil or known(form)) then return form.bonus end
    end
    return 0
end

-- Hat der Spieler diese Gestalt gelernt? Ohne Auskunft des Zauberbuchs zählt die Stufe (wie bei Twinks)
function Level.KnownForm(form)
    local S = Core.Spells
    if not (S and type(S.Known) == "function") then return true end
    return S.Known(form.spell) ~= nil
end

-- Wert eines Punkts Rüstung in Punkten Ausdauer auf dieser Stufe → Zahl oder nil
function Level.ArmorPerStamina(level, tank, class, known)
    local e = Expected(level)
    if not e or e.armor <= 0 then return nil end
    local role = tank and "tank" or "other"
    -- Bär: Lederrüstung wie alle anderen, vervielfacht
    local times = 1 + (tank and Level.FormBonus(class, e.level, known) or 0)
    local share = Level.ARMOR_SHARE[times > 1 and "other" or role]
    local part = math.max(0, math.min(1, (e.level - Level.ARMOR_FROM) / (Level.TOP - Level.ARMOR_FROM)))
    local armor = e.armor * (share[1] + (share[2] - share[1]) * part) * times
    local health = e.health * Level.HEALTH_SHARE[role]
    return Level.TAKEN_PER_HEALTH * Level.PHYSICAL * health * times / (Level.HEALTH_PER_STAMINA * (e.armor + armor))
end

local adapted = setmetatable({}, { __mode = "k" })      -- [weights] = { ["18/tank"] = Tabelle }

function Level.Adapt(weights, level, tank, class, known)
    if type(weights) ~= "table" then return weights end
    level = ns.Num(level)
    local factor = level and Level.Factor(level)
    if not factor then return weights end
    level = math.max(1, math.min(Level.TOP, math.floor(level)))
    local bonus = tank and Level.FormBonus(class, level, known) or 0
    local id = level .. (tank and "/tank" or "") .. (bonus > 0 and "/" .. bonus or "")
    local per = adapted[weights]
    if not per then
        per = {}
        adapted[weights] = per
    end
    if per[id] then return per[id] end
    local out = {}
    for k, v in pairs(weights) do out[k] = v end
    for _, k in ipairs(Level.PERCENT) do
        if out[k] then out[k] = Core.Round(out[k] / factor, 4) end
    end
    local stamina = ns.Num(out.STAMINA)
    local ratio = Level.ArmorPerStamina(level, tank, class, known)
    if stamina and stamina > 0 and ratio then out.ARMOR = Core.Round(stamina * ratio, 4) end
    per[id] = out
    return out
end

---------------------------------------------------------------------------
-- Rüstungsart
---------------------------------------------------------------------------

Level.ARMOR_CLASS = 4               -- Gegenstandsklasse „Rüstung“ (Enum.ItemClass.Armor)
-- Plätze mit Rüstungsart: Kopf, Schultern, Brust, Taille, Beine, Füße, Handgelenke, Hände
Level.ARMOR_SLOTS = { [1] = true, [3] = true, [5] = true, [6] = true, [7] = true, [8] = true, [9] = true, [10] = true }

-- Rüstungsart eines Gegenstands (1 bis 4) oder nil (keine Rüstung mit Art: Schild, Umhang, Schmuck)
function Level.ArmorOf(facts)
    if type(facts) ~= "table" or facts.classID ~= Level.ARMOR_CLASS then return nil end
    local sub = ns.Num(facts.subClassID)
    return sub and sub >= 1 and sub <= 4 and sub or nil
end

local own                           -- eigene Rüstungsart des Spielers (false: unbekannt), bis ns.Changed

function Level.Forget() own = nil end

local function Newest(class, level, test)
    for sub = 4, 1, -1 do
        if test(sub, class, level) then return sub end
    end
    return nil
end

local function ByTable(sub, class, level)
    local P = Core.Proficiency
    local levels = P and type(P.ClassLevels) == "function" and P.ClassLevels(Level.ARMOR_CLASS, sub) or nil
    local from = levels and levels[class or ""]
    return from ~= nil and level ~= nil and from <= level
end

function Level.OwnArmor(wearer)
    if wearer then return Newest(wearer.class, wearer.level, ByTable) end
    if own ~= nil then return own or nil end
    local P = Core.Proficiency
    own = P and type(P.ForItem) == "function" and Newest(nil, nil, function(sub)
        return (P.ForItem(Level.ARMOR_CLASS, sub)) == "known"
    end) or false
    return own or nil
end

-- Name einer Rüstungsart, wie der Client sie nennt („Schwere Rüstung“)
function Level.ArmorName(sub)
    return Core.ItemClassName(Level.ARMOR_CLASS, sub) or ns.L["ARMOR_" .. tostring(sub)]
end

--[[
    Level.ArmorRule(sub, wornSub, wearer) → Regel „Rüstungsart zuerst“ für Tanks und Nahkämpfer:
      "own"      der Gegenstand ist von der eigenen Rüstungsart, das Angelegte leichter – nie rot
      "lighter"  der Gegenstand ist leichter, das Angelegte von der eigenen Rüstungsart – nie grün
      nil        keine Aussage (gleiche Art, beide leichter, Art unbekannt)
]]
function Level.ArmorRule(sub, worn, wearer)
    if not (sub and worn) or sub == worn then return nil end
    local mine = Level.OwnArmor(wearer)
    if not mine then return nil end
    if sub == mine and worn < mine then return "own", mine end
    if worn == mine and sub < mine then return "lighter", mine end
    return nil
end

---------------------------------------------------------------------------
-- Wirkung auf den Spieler
---------------------------------------------------------------------------

local seen = {}                     -- zuletzt lesbare Werte (im Kampf und in Instanzen kann der Client sie sperren)

local function Read(key, value)
    value = ns.Num(value)           -- gesperrt oder keine Zahl: nil
    if value and value > 0 then seen[key] = value end
    return seen[key]
end

-- Werte des Spielers: Gesundheit, Gesundheit je Ausdauer, Rüstung, Waffenschaden je Sekunde der Waffenhand (je nil möglich)
function Level.Values()
    local _, armor = ns.Call(UnitArmor, "player")
    local low, high = ns.Call(UnitDamage, "player")
    local speed = ns.Num((ns.Call(UnitAttackSpeed, "player")))
    low, high = ns.Num(low), ns.Num(high)
    local dps = low and high and speed and speed > 0 and (low + high) / 2 / speed or nil
    return {
        health = Read("health", ns.Call(_G.UnitHealthMax, "player")),
        perStamina = Read("perStamina", ns.Call(_G.UnitHPPerStamina, "player")) or Level.HEALTH_PER_STAMINA,
        armor = Read("armor", armor),
        dps = Read("dps", dps),
    }
end

-- Anteil des Nahkampfschadens, den Rüstung abhält (0 bis 1) – der Client selbst, sonst seine Formel → Zahl oder nil
local function Mitigation(armor, level)
    local api = rawget(_G, "C_PaperDollInfo")
    local share = type(api) == "table" and ns.Num((ns.Call(api.GetArmorEffectiveness, armor, level))) or nil
    if share then return share end
    local e = Expected(level)
    return e and armor / (armor + e.armor) or nil
end

-- Wievielfach die Rüstung eines Gegenstands gerade zählt: in Bären- bzw. Terrorbärengestalt mehr, sonst 1 (auch unbekannt)
-- Bär und Terrorbär teilen sich Blizzards eine Gestalt-Nummer (ezCore Spells.FORM_IDS): ob überhaupt eine Bärengestalt an
-- ist, sagt jede der beiden; welche, sagen Stufe und Zauberbuch (Review 25.11.2026: unter 40 hieß es sonst Terrorbär)
local function FormTimes()
    local forms = Level.FORM_ARMOR[ns.playerClass or ""]
    local S = Core.Spells
    if not forms or not (S and type(S.FormActive) == "function") then return 1 end
    for _, form in ipairs(forms) do
        if S.FormActive(form.spell) == true then
            return 1 + Level.FormBonus(ns.playerClass, Level.Player(), Level.KnownForm)
        end
    end
    return 1
end

-- Angriffskraft aus Stärke (1) bzw. Beweglichkeit (2) laut Client, als Unterschied vom jetzigen Wert aus (Blizzards Formel
-- muss nicht durch 0 gehen: Stärke zählt etwa erst ab einem Sockel; Review 25.11.2026) – 0, wenn nicht lesbar
Level.STAT_FALLBACK = 100           -- jetziger Wert, wenn UnitStat gesperrt ist
local function AttackPower(stat, diff)
    if diff == 0 then return 0 end
    local _, now = ns.Call(_G.UnitStat, "player", stat)
    now = ns.Num(now) or Level.STAT_FALLBACK
    local function For(value) return ns.Num((ns.Call(_G.GetAttackPowerForStat, stat, math.max(0, value)))) end
    local before, after = For(now), For(now + diff)
    return before and after and after - before or 0
end

Level.AP_PER_DPS = 14               -- Blizzard: ATTACK_POWER_MAGIC_NUMBER
Level.EFFECT_MIN = 0.05             -- darunter nichts zu sagen

-- diff: { [Wert] = neu − alt }; melee: eigener Nahkampfschaden zählt (Nahkämpfer, Tank) – nicht bei Waffen
function Level.EffectOf(diff, melee)
    local now = Level.Values()
    local level = Level.Player()
    local out = {}
    local function Put(key, value)
        if value and math.abs(value) >= Level.EFFECT_MIN then out[key] = Core.Round(value, 1) end
    end
    if now.health and (diff.STAMINA or 0) ~= 0 then Put("health", diff.STAMINA * now.perStamina / now.health * 100) end
    if now.armor and level and (diff.ARMOR or 0) ~= 0 then
        local before, after = Mitigation(now.armor, level), Mitigation(math.max(0, now.armor + diff.ARMOR * FormTimes()), level)
        if before and after and before < 1 then Put("taken", ((1 - after) / (1 - before) - 1) * 100) end
    end
    if melee and now.dps then
        local ap = (diff.AP or 0) + AttackPower(1, diff.STRENGTH or 0) + AttackPower(2, diff.AGILITY or 0)
        Put("dealt", ap / Level.AP_PER_DPS / now.dps * 100)
    end
    return next(out) ~= nil and out or nil
end
