local _, ns = ...
local L = ns.L
local Core = ezCore
local Spells = Core.Spells

-- Rettungsfähigkeit im mittigen Symbol (Frage des Nutzers vom 24.11.2026, wörtlich: „werden mir auch fähigkeiten angezeigt
-- einzusetzen wenn ich fast tot bin mich zu retten …“; Auftrag im ROADMAP-Index). Unter derselben Grenze wie der Trank
-- (potionBelow, ab Werk 15 %) zeigt eine Ebene genau über der Mitte die erste gelernte, nutzbare und bereite
-- Rettungsfähigkeit der Klasse (ezCores Spells.RescueSpells). Steht sie bereit, rückt der Heiltrank als kleine Marke unten
-- links auf sie (Symbol-Lage "badge"); ohne bereite Rettung steht der Trank wie bisher in der Mitte.
-- Geheime Werte (Leitlinie 6): Das Leben liest ezCombat nie – die Deckkraft setzt Blizzards Kurve wie beim Trank
-- (Core.HealthBelowAlpha). Ob eine Fähigkeit bereit ist, sagen nur offene Antworten: gelernt (Zauberbuch), nutzbar
-- (C_Spell.IsSpellUsable, im Kampf offen) und Abklingzeit (ns.CooldownState: isActive bzw. letzte offene Lesung; „Mitzählen“
-- nur, wenn es eingeschaltet ist). Was unbekannt bleibt, wird nicht vorgeschlagen; dann gilt der nächste Eintrag.
-- Bereitgehalten wird sie nur im Kampf – die Kurve blendet sie ein, ezCombat weiß nicht, ob sie gerade zu sehen ist.
-- Neu gewählt wird bei Ereignissen und im leisen Takt (Rescue.TICK, nur im Kampf): „Abklingzeit vorbei“, „Ziel gestorben“
-- und „im Fahrzeug“ haben kein verlässliches eigenes Ereignis, und während der globalen Abklingzeit ist oft unbekannt, ob
-- die eigene läuft (isActive ohne isOnGCD) – dann fehlt der Eintrag, bis sie vorbei ist (Review 25.11.2026).
local Rescue = {}
ns.Rescue = Rescue

Rescue.KEY = "rescue"
Rescue.GLOW = "reactive"     -- Rahmen wie beim Trank (Gold, „jetzt nutzen“)
Rescue.TICK = 0.25           -- Sekunden

local layer
local picked                 -- { id, base, target, heal } der bereitgestellten Fähigkeit
local known                  -- gelernte Rettungszauber (Spells.RescueSpells), bis das Zauberbuch sich ändert
local inCombat = Core.InCombat()   -- PLAYER_REGEN_DISABLED kommt vor der Kampfsperre: eigener Merker
local demoUntil = 0

function Rescue.Known()
    if not known then known = Spells.RescueSpells() end
    return known
end

-- Wartet die Fähigkeit noch auf das Ende ihrer Wirkung (Schnelligkeit der Natur, Totstellen)? Blizzard meldet dann
-- isEnabled = false und noch keine laufende Abklingzeit. Nur die offene Antwort zählt.
local function Pending(id)
    local _, _, _, _, info = Spells.ReadCooldown(id)
    if info == nil then return false end
    local enabled = Core.Plain(Core.Peek(info, "isEnabled"))
    return enabled == false or enabled == 0
end

-- Geht diese Fähigkeit jetzt? true nur aus offenen Antworten (nutzbar, nicht in echter Abklingzeit, Ziel da); sonst false.
function Rescue.Ready(entry)
    if entry.target and not (ns.Rotation and ns.Rotation.TargetAttackable()) then return false end
    if Spells.UsableState(entry.id) ~= "ok" then return false end
    if Pending(entry.id) then return false end
    return ns.CooldownState(entry.id) == "ready"
end

-- Erste Fähigkeit, die jetzt geht, oder nil (tot, im Flug, im Fahrzeug: keine)
function Rescue.Pick()
    if ns.Rotation and ns.Rotation.PlayerUnable() then return nil end
    for _, entry in ipairs(Rescue.Known()) do
        if Rescue.Ready(entry) then return entry end
    end
    return nil
end

function Rescue.Layer()
    if not layer then layer = ns.Symbol.NewLayer(Rescue.KEY, "center", Rescue.GLOW) end
    return layer
end

-- Deckkraft aus Blizzards Kurve (1 unter der Grenze, sonst 0); ohne Kurve lieber nichts zeigen als raten
function Rescue.Apply()
    if not layer or not layer:IsShown() then return end
    if GetTime() < demoUntil then
        layer:SetAlpha(1)
        return
    end
    if not Core.HealthBelowAlpha(layer, "player", ns.Potions.Share(), false) then layer:SetAlpha(0) end
end

local function Show(entry)
    Rescue.Layer()
    layer.icon:SetTexture(Spells.Icon(entry.id) or Core.ICON_FALLBACK_ID)
    layer:Show()
end

-- Fähigkeit bereitstellen oder abbauen → true, wenn eine bereitsteht
function Rescue.Arm()
    local before = picked
    picked = inCombat and ns.Enabled("rescue") and Rescue.Pick() or nil
    if picked then
        Show(picked)
        ns.Symbol.Hold(Rescue.KEY, true)
        Rescue.Apply()
    elseif layer then
        layer:Hide()
        ns.Symbol.Hold(Rescue.KEY, false)
    end
    -- der Heiltrank rückt zur Seite bzw. zurück in die Mitte
    if (before ~= nil) ~= (picked ~= nil) then ns.Potions.PlaceHealth() end
    return picked ~= nil
end

function Rescue.Update()
    if GetTime() < demoUntil then return end
    ns.Try("Rescue", Rescue.Arm)
end

function Rescue.Picked() return picked end
-- Steht eine Rettungsfähigkeit in der Mitte (auch in der Vorschau)?
function Rescue.Shown() return layer ~= nil and layer:IsShown() end

-- SPELL_UPDATE_COOLDOWN und SPELL_UPDATE_USABLE kommen im Kampf oft: einmal prüfen
local UpdateSoon = ns.Throttle(Rescue.Update, 0.1)

-- Vorschau („Zeigen“): die erste gelernte Rettungsfähigkeit voll sichtbar; ohne gelernte oder ausgeschaltet nichts.
-- → true, wenn die Ebene zu sehen ist
function Rescue.Demo(seconds)
    if not ns.Enabled("rescue") then return false end
    local entry = Rescue.Known()[1]
    if not entry then return false end
    seconds = Core.Num(seconds) or 4
    local untilTime = GetTime() + seconds
    demoUntil = untilTime
    Show(entry)
    layer:SetAlpha(1)
    ns.Symbol.Hold("rescue_demo", true)
    ns.Potions.PlaceHealth()
    C_Timer.After(seconds, function()
        if demoUntil ~= untilTime then return end   -- eine neuere Vorschau läuft noch
        demoUntil = 0
        ns.Symbol.Hold("rescue_demo", false)
        Rescue.Update()
        ns.Potions.PlaceHealth()
    end)
    return true
end

-- Tooltip des Schalters mit den gelernten Fähigkeiten in ihrer Reihenfolge
function Rescue.Tip()
    local names = {}
    for _, entry in ipairs(Rescue.Known()) do names[#names + 1] = Spells.Name(entry.id) or ("#" .. entry.id) end
    local line = #names > 0 and L.RESCUE_KNOWN:format(table.concat(names, ", ")) or L.RESCUE_NONE
    return L.OPT_rescue_TIP .. "\n\n" .. line
end

---------------------------------------------------------------------------

local function Tick()
    if Rescue.ticker then Rescue.ticker:Update() end
end
ns.OnReady(function()
    Rescue.ticker = ns.Ticker(Rescue.TICK, Rescue.Update, function() return inCombat and ns.Enabled("rescue") end, "Rescue")
end)
ns.On("PLAYER_REGEN_DISABLED", function()
    inCombat = true
    Rescue.Update()
    Tick()
end)
ns.On("PLAYER_REGEN_ENABLED", function()
    inCombat = false
    Rescue.Update()
    Tick()
end)
for _, event in ipairs({ "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_USABLE", "PLAYER_TARGET_CHANGED" }) do
    ns.On(event, function() if inCombat then UpdateSoon() end end)
end
for _, event in ipairs({ "SPELLS_CHANGED", "PLAYER_LEVEL_UP" }) do
    ns.On(event, function()
        known = nil
        if inCombat then UpdateSoon() end
    end)
end
for _, event in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH" }) do
    ns.OnUnit(event, "player", function() Rescue.Apply() end)
end
ns.OnSettingChanged(function(key)
    if key == "rescue" or key == "potionBelow" then
        Rescue.Update()
        Tick()
    end
end)
