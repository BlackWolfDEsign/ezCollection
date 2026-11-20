local _, ns = ...
local L = ns.L

--[[
    Regeneration (Titan Regen): Leben und Mana pro 5 Sekunden, Mana-Regeneration
    im Kampf (5-Sekunden-Regel) und wie viel Mana im letzten Kampf zurückkam.
    Verbesserungen: echte Raten aus GetManaRegen/GetHealthRegen statt der
    Differenz des letzten Ticks (Heiltränke zählen nicht als Regeneration),
    Optionen funktionieren auch nach dem Umschalten noch, keine überschriebenen
    Blizzard-Globals.
    Gesperrte Werte (Forever sperrt UnitHealth immer, UnitPower, sobald das Spiel die Kraft einschränkt): Die Zeilen
    „Leben“ und „Mana“ im Tooltip kommen fertig aus ezCore.UnitHealthText/UnitPowerText – der Text darf gesperrt sein
    und wird nur durchgereicht, nie geprüft, verglichen oder formatiert. Gezählt („Mana im letzten Kampf zurück“) wird
    nur mit freien Werten; war der Mana-Stand im Kampf gesperrt, sagt die Zeile das („im Kampf gesperrt“) statt einer
    stillen 0 (Vollprüfung 14.11.2026, W-03; Leitlinien 6 und 11).
    Raten (GetHealthRegen/GetManaRegen): Ob Forever sie sperrt, zeigt erst das Spiel. Ein gesperrter Wert wird zuerst
    mit IsSecret erkannt (nie über ns.Num, das ihn still zu nil machte): Tooltip-Zeile „gesperrt“, auf der Leiste
    „?“ statt einer fehlenden Angabe (Welle 23, Durchsicht A71).
]]

local Core = ezCore

local block = ns.RegisterBlock({
    id = "regen",
    command = "regen",
    name = L.REGEN_NAME,
    icon = "Interface\\Icons\\Spell_Nature_Rejuvenation",
    interval = 1,
    defaults = {
        enabled = false, zone = "left", order = 85, icon = false,
        hp = true, mp = true,
    },
})

local MANA = (Enum.PowerType and Enum.PowerType.Mana) or 0

-- Hat der Charakter Mana? Ein gesperrtes Maximum lässt sich nicht vergleichen (Leitlinie 6): dann gilt die letzte
-- freie Antwort – ein Krieger bekommt im Kampf kein „MP 0“, ein Magier behält seine Zeilen. Gab es noch keine freie
-- Antwort, die Zeilen zeigen statt still weglassen (Leitlinie 11) – den Text liefert ezCore auch für gesperrte Werte.
local knownMana   -- nil: noch keine freie Antwort; sonst true/false aus dem letzten freien Maximum
local function UsesMana()
    local max = UnitPowerMax("player", MANA)
    if ns.IsSecret(max) then return knownMana ~= false end
    knownMana = (ns.Num(max) or 0) > 0
    return knownMana
end

-- Rate zum Rechnen: die Zahl, false, wenn das Spiel sie sperrt (zuerst IsSecret, Leitlinie 6), sonst nil.
local LOCKED = false
local function Rate(value)
    if ns.IsSecret(value) then return LOCKED end
    return ns.Num(value)
end

-- → Grundrate, Rate beim Zaubern bzw. im Kampf: je Zahl, false (gesperrt) oder nil (fehlt)
local function ManaRegen()
    if not GetManaRegen then return nil end
    local ok, base, casting = pcall(GetManaRegen)
    if not ok then return nil end
    return Rate(base), Rate(casting)
end

local function HealthRegen()
    if not GetHealthRegen then return nil end
    local ok, base, combat = pcall(GetHealthRegen)
    if not ok then return nil end
    return Rate(base), Rate(combat)
end

-- Mana, das im Kampf zurückkam (nur positive Änderungen zählen). locked: Der Mana-Stand war in diesem Kampf
-- mindestens einmal gesperrt – dann fehlt ein Teil der Rechnung, und der Tooltip nennt statt einer zu kleinen Zahl
-- (oder einer stillen 0) den Grund. lastLocked gilt für den letzten beendeten Kampf.
local fight = { active = false, gained = 0, last = nil, lastFight = nil, locked = false, lastLocked = false }

-- Mana-Stand zum Rechnen: die Zahl, oder nil und true, wenn das Spiel ihn sperrt (nie vergleichen, Leitlinie 6).
local function ManaNow()
    local value = UnitPower("player", MANA)
    if ns.IsSecret(value) then return nil, true end
    return ns.Num(value), false
end

ns.On("PLAYER_REGEN_DISABLED", function()
    fight.active, fight.gained = true, 0
    fight.last, fight.locked = ManaNow()
end)
ns.On("PLAYER_REGEN_ENABLED", function()
    if fight.active then fight.lastFight, fight.lastLocked = fight.gained, fight.locked end
    fight.active = false
end)
-- Nur für den Spieler (ns.OnUnit: Blizzard weckt den Zuhörer nur für ihn, V-042). Gesperrte Werte werden nie
-- verglichen (Leitlinie 6): Eine gesperrte Einheit zählt als der Spieler, eine gesperrte Kraftart als Mana – gezählt
-- wird ohnehin nur der Mana-Stand selbst. Ein gesperrter Stand wird nicht gerechnet, sondern vermerkt (fight.locked).
ns.OnUnit("UNIT_POWER_UPDATE", "player", function(_, unit, kind)
    if not fight.active then return end
    if not (ns.IsSecret(unit) or unit == "player") then return end
    if not (ns.IsSecret(kind) or kind == "MANA") then return end
    local now, locked = ManaNow()
    if locked then fight.locked = true return end
    if now and fight.last and now > fight.last then fight.gained = fight.gained + (now - fight.last) end
    fight.last = now or fight.last
end)

local function Per5(value)
    return value and ("%.0f"):format(value * 5) or "–"
end

-- Leistenteil „LP 12“; gesperrt „LP ?“ (grau) statt still weggelassen; fehlt die Rate ganz, kein Teil.
local function BarPart(color, label, v)
    if v == LOCKED then return color .. label .. "|r " .. ns.Grey("?") end
    if v then return color .. label .. "|r " .. Per5(v) end
    return nil
end

-- Tooltip-Zeile „… pro 5 Sek.“; gesperrt „gesperrt“; fehlt die Rate ganz, keine Zeile.
local function RateLine(tooltip, label, v)
    if v == LOCKED then
        ns.TipDoubleLine(tooltip, label, L.REGEN_RATE_LOCKED, "normal", "normal")
    elseif v then
        ns.TipDoubleLine(tooltip, label, Per5(v) .. " " .. L.REGEN_PER5, "normal", "highlight")
    end
end

function block:GetText()
    local cfg = self.cfg
    local parts = {}
    local inCombat = ns.InCombat()
    if cfg.hp then
        local base, combat = HealthRegen()
        local v = base
        if inCombat and combat ~= nil then v = combat end
        parts[#parts + 1] = BarPart(ns.GREEN, L.REGEN_HP, v)
    end
    if cfg.mp and UsesMana() then
        local base, casting = ManaRegen()
        local v = base
        if inCombat and casting ~= nil then v = casting end
        parts[#parts + 1] = BarPart(ns.BlueCode(), L.REGEN_MP, v)
    end
    if #parts == 0 then return "" end
    return table.concat(parts, "  ")
end

function block:OnTooltip(tooltip)
    -- „aktuell / maximal (Anteil)“ fertig aus ezCore; der Text kann gesperrt sein: nur durchreichen.
    local okHealth, healthText = Core.UnitHealthText("player")
    if okHealth then ns.TipDoubleLine(tooltip, L.REGEN_HEALTH, healthText, "normal", "highlight") end
    local hb, hc = HealthRegen()
    RateLine(tooltip, L.REGEN_HP_OOC, hb)
    RateLine(tooltip, L.REGEN_HP_COMBAT, hc)
    if UsesMana() then
        tooltip:AddLine(" ")
        local okMana, manaText = Core.UnitPowerText("player", MANA)
        if okMana then ns.TipDoubleLine(tooltip, L.REGEN_MANA, manaText, "normal", "highlight") end
        local base, casting = ManaRegen()
        RateLine(tooltip, L.REGEN_MP_OOC, base)
        RateLine(tooltip, L.REGEN_MP_CASTING, casting)
        if fight.lastLocked then
            -- Der Stand war im Kampf gesperrt: nichts Gerechnetes zeigen, sondern den Grund (nie eine stille 0).
            ns.TipDoubleLine(tooltip, L.REGEN_LAST_FIGHT, L.REGEN_LOCKED, "normal", "normal")
            ns.TipLine(tooltip, L.REGEN_LOCKED_TIP, "hint", true)
        elseif fight.lastFight then
            ns.TipDoubleLine(tooltip, L.REGEN_LAST_FIGHT, ns.Number(fight.lastFight), "normal", "highlight")
        end
        ns.TipLine(tooltip, L.REGEN_FIVE_SECOND, "hint", true)
    end
end

function block:OnMenu(root)
    ns.MenuCheck(root, L.REGEN_SHOW_HP, self.cfg, "hp", self)
    ns.MenuCheck(root, L.REGEN_SHOW_MP, self.cfg, "mp", self)
end
