local _, ns = ...
local Core = ezCore
local Spells = Core.Spells
local Rotation = ns.Rotation
local State = ns.RotationState

-- Prüfungen der Rotation, die über die alten Bedingungen hinausgehen:
--   Rotation.CHECKS[schlüssel](wert, schritt, ctx)   weitere Bedingungen eines Schritts (need = { … }) und einer
--       Rotation (pick = { … }); schritt ist bei pick nil
--   Rotation.CONDITIONS.<when>                        die neuen Bedingungen enchant, pet, form, item, totemslot,
--       stealth, autorepeat, manual
-- Jede Prüfung liefert wahr / falsch / unbekannt (nil). Sperrbare Werte laufen vor jedem Vergleich über
-- ns.IsSecret bzw. ns.Num/ns.Plain – unbekannt heißt für den Motor: Schritt überspringen und nennen, nie raten.
-- Was der Client liefert, wird gefragt (ezCore.Spells, ezCore.Auras, Core.UnitRank …); hier stehen keine Daten.
local CHECKS = Rotation.CHECKS
local CONDITIONS = Rotation.CONDITIONS

-- Feste Reihenfolge der Prüfungen (billige und nie gesperrte zuerst – ein „falsch“ beendet die Prüfung).
Rotation.NEED_ORDER = { "combat", "target", "solo", "grouped", "leveling", "level", "known", "unknown", "seen",
    "aoe", "stealth", "pet", "form", "weapon", "item", "queued", "usable", "unusable", "moving", "inrange",
    "outrange", "enemy", "totem", "counter", "cp", "rage", "energy", "mana", "aura", "noaura" }

---------------------------------------------------------------------------
-- Helfer
---------------------------------------------------------------------------

-- Wert im Bereich { min, max }? nil bleibt nil (unbekannt).
local function InRange(value, range)
    if value == nil then return nil end
    if type(range) ~= "table" then return true end
    if range.min and value < range.min then return false end
    if range.max and value > range.max then return false end
    return true
end

local function Each(value, fn)
    if type(value) == "table" then
        for _, one in ipairs(value) do
            if not fn(one) then return false end
        end
        return true
    end
    return fn(value)
end

local function Contains(list, value)
    for _, one in ipairs(type(list) == "table" and list or {}) do
        if type(one) == "string" and type(value) == "string" and one:lower() == value:lower() then return true end
    end
    return false
end

local function Stealthed()
    local api = rawget(_G, "IsStealthed")
    if type(api) ~= "function" then return nil end
    local ok, value = pcall(api)
    if not ok or ns.IsSecret(value) then return nil end
    return value == true or value == 1
end

-- Begleiter da? wahr / falsch / unbekannt (gesperrt) – über Rotation.UnitPresent (Leitlinie 6).
local function HasPet()
    return Rotation.UnitPresent("pet")
end

-- Totem-Platz belegt? true / false, nil = gesperrt oder ohne Schnittstelle.
local function TotemUp(slot)
    if type(GetTotemInfo) ~= "function" or type(slot) ~= "number" then return nil end
    local ok, have = pcall(GetTotemInfo, slot)
    if not ok or ns.IsSecret(have) then return nil end
    return have == true
end

-- Name des höchsten gelernten Rangs bzw. die ID (für Abfragen, die einen Zauber brauchen).
local function SpellRef(id)
    return Spells.Highest(id) or id
end

---------------------------------------------------------------------------
-- need / pick
---------------------------------------------------------------------------

function CHECKS.combat(value, _, ctx)
    local combat = ctx and ctx.combat
    if combat == nil then combat = ns.InCombat() end
    return (combat and true or false) == (value and true or false)
end

-- Nur für „Vor dem Kampf“: ein angreifbares Ziel ist da.
function CHECKS.target(value)
    return Rotation.TargetAttackable() == (value and true or false)
end

function CHECKS.solo(value) return (not Core.InGroup()) == (value and true or false) end
function CHECKS.grouped(value) return Core.InGroup() == (value and true or false) end

-- Leveln = unter der Höchststufe des Clients.
function CHECKS.leveling(value)
    local level, maximum = Core.PlayerLevel(), Core.MaxLevel and Core.MaxLevel()
    if not (level and maximum) then return nil end
    return (level < maximum) == (value and true or false)
end

function CHECKS.level(value)
    return InRange(Core.PlayerLevel(), value)
end

-- Alle gelernt (Zauber oder Talent) / keiner gelernt.
function CHECKS.known(value)
    return Each(value, function(id) return Spells.IsKnown(id) end)
end
function CHECKS.unknown(value)
    return Each(value, function(id) return not Spells.IsKnown(id) end)
end

-- Diese Aura hatte der Charakter schon einmal (Ersatz, wenn ein Talent nicht abfragbar ist).
function CHECKS.seen(value, _, ctx)
    local function Seen(id) return State.Seen(id) end
    if Each(value, Seen) then return true end
    -- noch nicht gemerkt: die Buffs des Spielers jetzt lesen (merkt, was offen zu sehen ist)
    Rotation.UnitAuras(ctx or { now = GetTime() }, "player", "HELPFUL", false)
    return Each(value, Seen)
end

function CHECKS.aoe(value) return Rotation.Aoe() == (value and true or false) end

function CHECKS.stealth(value)
    local stealthed = Stealthed()
    if stealthed == nil then return nil end
    return stealthed == (value and true or false)
end

function CHECKS.pet(value)
    local has = HasPet()
    if has == nil then return nil end
    return has == (value and true or false)
end

function CHECKS.form(value)
    local active = Spells.FormActive(value)
    if active == nil then return nil end
    return active
end

-- { hand, type = { "dagger", … } }: Waffe dieser Art in der Hand.
function CHECKS.weapon(value)
    if type(value) ~= "table" then return false end
    local kind, isWeapon = Core.WeaponKind(value.hand or "main")
    if not kind or not isWeapon then return false end
    if type(value.type) ~= "table" then return true end
    return Contains(value.type, kind)
end

-- { id, min }: mindestens so viele im Gepäck (Standard 1).
function CHECKS.item(value)
    if type(value) ~= "table" then return false end
    local count = 0
    Each(value.id, function(id)
        count = count + Core.ItemCount(id)
        return true
    end)
    return count >= (value.min or 1)
end

-- Der Zauber des Schritts ist (nicht) schon eingereiht bzw. wird (nicht) gerade gewirkt.
function CHECKS.queued(value, step)
    if not step then return nil end
    local _, name = Rotation.StepSpell(step)
    return Spells.IsCurrent(name) == (value and true or false)
end

-- Ein anderer Zauber ist (nicht) nutzbar – z. B. die Hinrichtungsphase über Hinrichten. Gesperrt: unbekannt
-- (übersprungen und genannt). „Nur die Kraft fehlt“ ist nicht „unnutzbar“: In der Hinrichtungsphase mit wenig Wut
-- bleibt es die Hinrichtungsphase (sonst käme Verwunden auf das sterbende Ziel).
function CHECKS.usable(value)
    local usable, _, locked = Spells.Usable(ns.SpellName(value) or value)
    if locked then return nil end
    return usable == true
end
function CHECKS.unusable(value)
    local usable, noPower, locked = Spells.Usable(ns.SpellName(value) or value)
    if locked then return nil end
    return usable ~= true and noPower ~= true
end

function CHECKS.moving(value)
    return (Core.PlayerMoving() and true or false) == (value and true or false)
end

function CHECKS.inrange(value)
    return Spells.InRange(SpellRef(value), "target")
end
function CHECKS.outrange(value)
    local inRange = Spells.InRange(SpellRef(value), "target")
    if inRange == nil then return nil end
    return not inRange
end

-- { rank = { … }, norank = { … }, type = { … } }: Einstufung (nie gesperrt) und Kreaturentyp (sperrbar) des Ziels.
function CHECKS.enemy(value)
    if type(value) ~= "table" then return false end
    local unknown = false
    if value.rank or value.norank then
        local rank = Core.UnitRank("target")
        if rank == nil then
            unknown = true
        else
            if value.rank and not Contains(value.rank, rank) then return false end
            if value.norank and Contains(value.norank, rank) then return false end
        end
    end
    if value.type then
        local kind = Core.UnitCreatureKey("target")
        if kind == nil then
            unknown = true
        elseif not Contains(value.type, kind) then
            return false
        end
    end
    if unknown then return nil end
    return true
end

-- { slot, up }: Totem-Platz belegt (Standard) bzw. leer.
function CHECKS.totem(value)
    if type(value) ~= "table" then return false end
    local up = TotemUp(value.slot)
    if up == nil then return nil end
    return up == (value.up ~= false)
end

-- { name, min, max, oldest = { min } }: Zähler der Rotation im Bereich; oldest.min: der älteste Eintrag läuft noch
-- mindestens so viele Sekunden. Ein gezählter (nicht gelesener) Wert kennzeichnet den Vorschlag als „gezählt“.
function CHECKS.counter(value, _, ctx)
    if type(value) ~= "table" then return false end
    local count, source = State.Counter(value.name, ctx)
    if count == nil then return nil end
    if source == "counted" and ctx then ctx.counted = true end
    local result = InRange(count, value)
    if result ~= true then return result end
    if type(value.oldest) == "table" and value.oldest.min then
        local left = State.Oldest(value.name, ctx)
        if left == nil then
            if count > 0 then return nil end
            return true
        end
        if ctx then ctx.counted = true end
        return left >= value.oldest.min
    end
    return true
end

function CHECKS.cp(value) return InRange(Rotation.ComboPoints(), value) end
function CHECKS.rage(value) return InRange(Rotation.Power("Rage"), value) end
function CHECKS.energy(value) return InRange(Rotation.Power("Energy"), value) end
function CHECKS.mana(value) return InRange(Rotation.ManaPercent(), value) end

-- Aura für need.aura / need.noaura: { id, unit, mine, filter, … } → Aura, Zahl der unbekannten Auren, Einheit.
-- unit: "player" (Standard), "target", "pet", "pettarget"; filter: HELPFUL beim Spieler und Begleiter, HARMFUL bei
-- Zielen; mine: Standard true bei Zielen, false beim Spieler.
local function NeedAura(value, ctx)
    local unit = value.unit or "player"
    local onTarget = unit == "target" or unit == "pettarget"
    local filter = value.filter or (onTarget and "HARMFUL" or "HELPFUL")
    local mine = value.mine
    if mine == nil then mine = onTarget end
    local list, unknown = Rotation.UnitAuras(ctx, unit, filter, mine)
    return Rotation.FindAura(list, value.id), unknown, unit
end

-- Nachgeführter Zustand einer Aura für need.aura/noaura, wenn das Spiel sie sperrt: { state, left } oder nil (keine
-- Nachführung für diese Einheit oder Aura – nur, was ein Schritt der Rotation selbst setzt; Restzeit nur durch
-- Mitzählen zu erfahren und „Mitzählen“ aus). Der Spieler und das Ziel; "pettarget" nur, wenn der Begleiter das Ziel
-- des Spielers angreift (State.PetOnTarget). mine = false: auch Debuffs anderer Quellen aus der letzten offenen Lesung.
local function TrackedState(value, unit, ctx)
    local which = unit == "player" and "player" or ((unit == "target" or unit == "pettarget") and "target") or nil
    if not which or type(Rotation.Tracked) ~= "function" then return nil end
    if unit == "pettarget" and not State.PetOnTarget() then return nil end
    if not Rotation.Trackable(value.id, ctx) then return nil end      -- Proc, fremder Buff: bleibt unbekannt
    local auraID = type(value.id) == "number" and value.id or nil
    local mine = value.mine
    if mine == nil then mine = which == "target" end
    local state, left = Rotation.Tracked(which, value.id, nil, auraID, ctx, which == "target" and mine == false)
    if state == nil then return nil end
    return { state = state, left = left }
end

-- need.aura/noaura auf "pettarget": Hat der Begleiter kein Ziel, gibt es dort nichts zu prüfen – falsch (nicht
-- fällig), gesperrt unbekannt; sonst wahr.
local function UnitReady(value)
    if value.unit ~= "pettarget" then return true end
    return Rotation.UnitPresent("pettarget")
end

-- { id, unit, mine, filter, min, max, left = { min, max } }: Aura liegt; min/max Stapel, left Restzeit (Sekunden).
function CHECKS.aura(value, step, ctx)
    if type(value) ~= "table" then value = { id = value } end
    local ready = UnitReady(value)
    if ready ~= true then return ready end
    ctx = ctx or { now = GetTime() }
    local aura, unknown, unit = NeedAura(value, ctx)
    if not aura then
        if unknown == 0 then return false end
        -- Gesperrt: die Nachführung fragen (Spieltest 15.11.2026, Befund 1). Ohne Wissen über Stapel und Rest bleibt
        -- es unbekannt; „nie gewirkt, nie gesehen“ heißt: liegt nicht.
        local tracked = TrackedState(value, unit, ctx)
        if tracked == nil then return nil end
        local state, left = tracked.state, tracked.left
        if state == "missing" then return false end
        if value.min or value.max then return nil end
        if type(value.left) == "table" then
            if left == nil then return nil end
            return InRange(left, value.left)
        end
        return true
    end
    if value.min or value.max then
        if aura.secret then return nil end
        local stacks = InRange(math.max(aura.count or 0, 1), value)
        if stacks ~= true then return stacks end
    end
    if type(value.left) == "table" then
        -- Ersatzuhr bei gesperrter Aura: Zeitpunkt des Zaubers, der die Aura legt (value.id), nicht des Schritts –
        -- sonst rechnete der Wilde Biss die Restzeit von Zerfetzen ab dem letzten Biss.
        local name
        if type(value.id) == "number" then
            name = ns.SpellName(value.id)
        elseif step then
            name = select(2, Rotation.StepSpell(step))
        end
        local auraID = type(value.id) == "number" and value.id or (step and step.id)
        local left = Rotation.Remaining(aura, name, auraID, unit, ctx)
        if left == nil then return nil end
        return InRange(left, value.left)
    end
    return true
end

-- wie aura, ohne Stapel und Rest: Aura liegt nicht.
function CHECKS.noaura(value, _, ctx)
    if type(value) ~= "table" then value = { id = value } end
    local ready = UnitReady(value)
    if ready ~= true then return ready end
    ctx = ctx or { now = GetTime() }
    local aura, unknown, unit = NeedAura(value, ctx)
    if aura then return false end
    if unknown == 0 then return true end
    local tracked = TrackedState(value, unit, ctx)
    if tracked == nil then return nil end
    return tracked.state == "missing"
end

---------------------------------------------------------------------------
-- Neue Bedingungen (when)
---------------------------------------------------------------------------

-- Die Hand trägt eine Waffe ohne Waffenverzauberung (Gift, Stein, Waffenzauber). Schild, Nebenhand-Gegenstand
-- oder leerer Platz: nicht dran. GetWeaponEnchantInfo ist laut Forever-Quelle nie gesperrt; geprüft wird trotzdem.
function CONDITIONS.enchant(step)
    local hand = step.hand == "off" and "off" or "main"
    local _, isWeapon = Core.WeaponKind(hand)
    if not isWeapon then return false end
    local readable, hasMain, _, hasOff = Core.WeaponEnchantInfo()   -- V-185: global oder C_Item (ezCore, Welle 23)
    if not readable then return nil end
    local has = hasMain
    if hand == "off" then has = hasOff end
    if ns.IsSecret(has) then return nil end
    return not (has == true or has == 1)
end

-- Kein Begleiter da (gesperrt: unbekannt).
function CONDITIONS.pet()
    local has = HasPet()
    if has == nil then return nil end
    return not has
end

-- Die Gestalt oder Haltung des Schritts ist nicht aktiv (Gestaltleiste, ezCore.Spells.FormActive).
function CONDITIONS.form(step)
    local active = Spells.FormActive(step.id)
    if active == nil then return nil end
    return not active
end

-- Weniger als min (Standard 1) Stück von item (ID oder Liste) im Gepäck.
function CONDITIONS.item(step)
    local count = 0
    Each(step.item, function(id)
        count = count + Core.ItemCount(id)
        return true
    end)
    return count < (step.min or 1)
end

-- Der Totem-Platz slot (1 Feuer, 2 Erde, 3 Wasser, 4 Luft) ist leer – jedes Totem des Elements zählt.
function CONDITIONS.totemslot(step)
    local up = TotemUp(step.slot)
    if up == nil then return nil end
    return not up
end

-- Nicht verstohlen.
function CONDITIONS.stealth()
    local stealthed = Stealthed()
    if stealthed == nil then return nil end
    return not stealthed
end

-- Der automatische Schuss bzw. Zauberstab läuft nicht (Ereignisse START/STOP_AUTOREPEAT_SPELL; solange noch
-- keines kam, gilt: läuft nicht).
function CONDITIONS.autorepeat()
    return State.Autorepeat() ~= true
end

-- Nach Lage: nie vorgeschlagen, steht nur mit seinem Text in der Liste.
function CONDITIONS.manual() return false end
