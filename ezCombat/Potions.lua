local _, ns = ...
local Core = ezCore

-- Trank im mittigen Symbol (Wunsch des Nutzers vom 23.11.2026, wörtlich „nur die tränke mittig Symbol, beides ab
-- 15 %“; „Auch Restheilung weg“ – vom Restschaden-Plan bleibt nur das hier, Entscheidungen im ROADMAP-Index):
--   • Leben unter der Grenze → Gesundheitsstein (eigene Abklingzeit, zuerst) oder bester Heiltrank, als eigene Ebene
--     genau über der Mitte des Symbols (Symbol.NewLayer, Lage "center"). Sie deckt dort die Mitte ab – die nächste
--     Fähigkeit oder einen einzelnen, mittig gestellten Eintrag; deren Text darunter bleibt. Der Trank ist dann wichtiger.
--     Steht dort eine Rettungsfähigkeit bereit (Rescue.lua, 24.11.2026), liegt der Trank als kleine Marke unten links
--     auf ihr (Lage "badge", Potions.PlaceHealth) – beide unter derselben Grenze, beide zu sehen.
--   • Mana unter der Grenze → bester Manatrank, als Ebene über der Mitte (Lage "above", nur mit Mana).
--   Ein Regler für beides (potionBelow, ab Werk 15 %), Schalter potions. Nur im Kampf, nur mit einem Trank in der
--   Tasche (Core.BestItems: „potion“, „manaPotion“; Steine aus Core.Spells.CONJURED.healthstone).
-- Geheime Werte (Leitlinie 6): Dein Leben ist auf Forever für Addons gesperrt, ein „Leben < 15 %“ im Code gibt es nicht.
-- Die Deckkraft der Ebene setzt Blizzards Kurve (Core.HealthBelowAlpha bzw. Core.PowerBelowAlpha: UnitHealthPercent
-- bzw. UnitPowerPercent mit Stufenkurve, Ergebnis nur an SetAlpha) – ezCombat liest Leben und Mana dabei nie. Ob die
-- Ebene gerade zu sehen ist, weiß ezCombat deshalb nicht: Sie steht bereit (Symbol.Hold hält die Gruppe sichtbar), die
-- Kurve blendet sie ein. Abklingzeit des Tranks: offen gelesen → in der Abklingzeit keine Ebene (danach kommt sie von
-- selbst wieder); gesperrt → die Ebene bleibt und trägt Blizzards Spirale wie ein Aktionsknopf (Werte unbesehen an
-- SetCooldown). Wahl beim Leben: der Stein, außer seine Abklingzeit läuft (offen gelesen) – oder sie ist gesperrt und
-- ein Heiltrank ist offen gelesen bereit; sonst der Heiltrank. Gesperrt heißt dann: Stein mit Blizzards Spirale.
local Potions = {}
ns.Potions = Potions

Potions.KINDS = { "health", "mana" }
Potions.GCD = 1.5        -- Sekunden: kürzere Abklingzeit ist die globale, kein „Trank in Abklingzeit“

local layers, picked = {}, {}
local inCombat = Core.InCombat()   -- PLAYER_REGEN_DISABLED kommt vor der Kampfsperre: eigener Merker
local demoUntil = 0
local recheckAt, recheckToken = nil, 0

local function ManaType()
    local enum = rawget(_G, "Enum")
    local types = type(enum) == "table" and enum.PowerType or nil
    return type(types) == "table" and types.Mana or 0
end

local function HasMana()
    local max = Core.Num(Core.PlainCall(rawget(_G, "UnitPowerMax"), "player", ManaType()))
    return max ~= nil and max > 0
end

-- Die eine Grenze (Anteil 0…1) für Trank, Rettungsfähigkeit (Rescue.lua) und Leuchten am Spielerfenster (Danger.lua)
local function Share()
    return (Core.Num(ns.S and ns.S.potionBelow) or ns.DEFAULTS.potionBelow) / 100
end
Potions.Share = Share

-- Nach dem Ende einer offen gelesenen Abklingzeit neu prüfen; ein früheres Ende ersetzt einen späteren Termin.
local function Recheck(left)
    left = Core.Num(left)
    if not left or left <= 0 or type(C_Timer) ~= "table" then return end
    local at = GetTime() + left
    if recheckAt and recheckAt <= at then return end
    recheckAt, recheckToken = at, recheckToken + 1
    local token = recheckToken
    C_Timer.After(left + 0.1, function()
        if token ~= recheckToken then return end
        recheckAt = nil
        Potions.Update()
    end)
end

-- Abklingzeit eines Gegenstands → true (läuft, offen gelesen), false (bereit), nil (gesperrt); dazu start und dauer
-- (roh, gegebenenfalls gesperrt – nur für die Spirale) und bei offener Abklingzeit die Restzeit
local function Cooldown(itemID)
    local api = rawget(_G, "C_Container")
    local fn = type(api) == "table" and api.GetItemCooldown or rawget(_G, "GetItemCooldown")
    if type(fn) ~= "function" then return false end
    local ok, start, duration = pcall(fn, itemID)
    if not ok then return false end
    if Core.IsSecret(start) or Core.IsSecret(duration) then return nil, start, duration end
    start, duration = Core.Num(start), Core.Num(duration)
    if not start or not duration or start <= 0 or duration <= Potions.GCD then return false end
    local left = start + duration - GetTime()
    if left > 0 then return true, start, duration, left end
    return false
end
Potions.Cooldown = Cooldown

-- Bester Trank der Art in der Tasche (itemID) oder nil
function Potions.Pick(kind)
    local best = Core.BestItems
    if kind == "health" then
        local potion = best and (best.Consumable("potion")) or nil
        local stones = Core.Spells and Core.Spells.CONJURED and Core.Spells.CONJURED.healthstone
        local lockedStone
        for _, id in ipairs(type(stones) == "table" and stones.items or {}) do
            if Core.ItemCount(id) > 0 then
                local running, _, _, left = Cooldown(id)
                if running == false then return id end
                if running == true then Recheck(left) else lockedStone = lockedStone or id end
            end
        end
        -- Abklingzeit des Steins gesperrt: der Trank nur, wenn er offen gelesen bereit ist, sonst der Stein mit Spirale
        if lockedStone and not (potion and Cooldown(potion) == false) then return lockedStone end
        return potion or lockedStone
    elseif kind == "mana" then
        if not HasMana() then return nil end   -- ohne Mana kein Manatrank
        return best and (best.Consumable("manaPotion")) or nil
    end
    return nil
end

-- Die Ebene einer Art (.icon, .cooldown) über ezCombats gemeinsame Ebenen (Symbol.NewLayer): Heiltrank "center",
-- Manatrank "above"; legt sie bei Bedarf an. Rahmen wie die Mitte: Leuchtrahmen der Art „reactive“ (Gold, „Reaktion:
-- jetzt nutzen“ – wie die nächste Fähigkeit; Spieltest 23.11.2026: „nur der rahmen fehlt“)
Potions.GLOW = "reactive"
function Potions.Layer(kind)
    if layers[kind] then return layers[kind] end
    layers[kind] = ns.Symbol.NewLayer("potion_" .. kind, kind == "health" and "center" or "above", Potions.GLOW)
    return layers[kind]
end

-- Lage des Heiltranks: neben der Rettungsfähigkeit als kleine Marke, sonst in der Mitte
function Potions.PlaceHealth()
    if not layers.health then return end
    ns.Symbol.MoveLayer("potion_health", ns.Rescue and ns.Rescue.Shown() and "badge" or "center")
end

-- Deckkraft aus Blizzards Kurve (1 unter der Grenze, sonst 0); ohne Kurve lieber nichts zeigen als raten
function Potions.Apply(kind)
    local layer = layers[kind]
    if not layer or not layer:IsShown() then return end
    if GetTime() < demoUntil then
        layer:SetAlpha(1)
        return
    end
    local ok
    if kind == "health" then
        ok = Core.HealthBelowAlpha(layer, "player", Share(), false)
    else
        ok = Core.PowerBelowAlpha(layer, "player", ManaType(), Share())
    end
    if not ok then layer:SetAlpha(0) end
end

local function Remove(kind, layer)
    layer:Hide()
    picked[kind] = nil
    ns.Symbol.Hold("potion_" .. kind, false)
end

-- Ebene der Art bereitstellen oder abbauen → true, wenn sie bereitsteht
function Potions.Arm(kind)
    local layer = Potions.Layer(kind)
    if kind == "health" then Potions.PlaceHealth() end
    local id = inCombat and ns.Enabled("potions") and Potions.Pick(kind) or nil
    local running, start, duration, left
    if id then running, start, duration, left = Cooldown(id) end
    if not id or running == true then
        Remove(kind, layer)
        if running == true then Recheck(left) end
        return false
    end
    picked[kind] = id
    layer.icon:SetTexture(Core.ItemIcon(id) or Core.ICON_FALLBACK_ID)
    local cd = layer.cooldown
    if running == nil and Core.IsSecret(start) and pcall(cd.SetCooldown, cd, start, duration) then
        cd:Show()
    else
        if cd.Clear then cd:Clear() end
        cd:Hide()
    end
    layer:Show()
    -- Abklingzeit gesperrt (Spirale): kein goldener Rahmen „jetzt nutzen“ – der Trank klingt vielleicht noch ab
    if cd:IsShown() then ns.Glow.Hide(layer) else ns.Glow.Show(layer, false, Potions.GLOW) end
    ns.Symbol.Hold("potion_" .. kind, true)
    Potions.Apply(kind)
    return true
end

function Potions.Update()
    if GetTime() < demoUntil then return end
    -- je Art einzeln abgesichert: scheitert der Heiltrank, wird der Manatrank trotzdem auf- bzw. abgebaut
    for _, kind in ipairs(Potions.KINDS) do ns.Try("Potions", Potions.Arm, kind) end
end

-- viele Taschen-Ereignisse in einem Bild (BAG_UPDATE_COOLDOWN kommt im Kampf oft): einmal prüfen
local UpdateSoon = ns.Throttle(Potions.Update, 0.2)

function Potions.Picked(kind) return picked[kind] end
function Potions.InCombat() return inCombat end

-- Vorschau („Zeigen“ der Anzeige über dem Charakter, Symbol.Demo): die Ebenen voll sichtbar, danach wie vorher;
-- mit ausgeschaltetem Schalter keine, ohne Mana keine Manatrank-Ebene. → true, wenn eine Ebene zu sehen ist
function Potions.Demo(seconds)
    if not ns.Enabled("potions") then return false end
    seconds = Core.Num(seconds) or 4
    local untilTime = GetTime() + seconds
    demoUntil = untilTime
    local shown = false
    for _, kind in ipairs(Potions.KINDS) do
        local layer = Potions.Layer(kind)
        if kind == "mana" and not HasMana() then
            Remove(kind, layer)
        else
            local id = Potions.Pick(kind)
            layer.icon:SetTexture(id and Core.ItemIcon(id) or Core.ICON_FALLBACK_ID)
            layer.cooldown:Hide()
            layer:Show()
            layer:SetAlpha(1)
            shown = true
        end
    end
    ns.Symbol.Hold("potion_demo", true)
    C_Timer.After(seconds, function()
        if demoUntil ~= untilTime then return end   -- eine neuere Vorschau läuft noch
        demoUntil = 0
        ns.Symbol.Hold("potion_demo", false)
        Potions.Update()
    end)
    return shown
end

---------------------------------------------------------------------------

ns.On("PLAYER_REGEN_DISABLED", function()
    inCombat = true
    Potions.Update()
end)
ns.On("PLAYER_REGEN_ENABLED", function()
    inCombat = false
    Potions.Update()
end)
for _, event in ipairs({ "BAG_UPDATE_DELAYED", "BAG_UPDATE_COOLDOWN" }) do
    ns.On(event, function() if inCombat then UpdateSoon() end end)
end
for _, event in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH" }) do
    ns.OnUnit(event, "player", function() Potions.Apply("health") end)
end
for _, event in ipairs({ "UNIT_POWER_UPDATE", "UNIT_MAXPOWER" }) do
    ns.OnUnit(event, "player", function(_, _, token)
        if Core.IsSecret(token) or token == nil or token == "MANA" then Potions.Apply("mana") end
    end)
end
ns.OnSettingChanged(function(key)
    if key == "potions" or key == "potionBelow" then Potions.Update() end
end)
