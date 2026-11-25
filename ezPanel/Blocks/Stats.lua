local _, ns = ...
local L = ns.L

--[[
    Werte (Titan AttributesMulti): ein frei wählbarer Wert auf der Leiste,
    alle wichtigen Werte im Tooltip – ein Baustein statt zwanzig.
    Verbesserungen: ein Ereignis-/2-Sekunden-Takt statt vieler OnUpdate-Skripte,
    keine globalen Variablen, keine Secret Values in Rechnungen.
]]

local block = ns.RegisterBlock({
    id = "stats",
    command = "werte",
    name = L.STATS_NAME,
    icon = "Interface\\Icons\\INV_Misc_Book_11",
    events = { "UNIT_STATS", "UNIT_ATTACK_POWER", "UNIT_RANGED_ATTACK_POWER", "COMBAT_RATING_UPDATE",
        "PLAYER_EQUIPMENT_CHANGED", "UNIT_RESISTANCES", "PLAYER_DAMAGE_DONE_MODS" },
    interval = 2,
    defaults = {
        enabled = false, zone = "left", order = 95, icon = false,
        stat = "auto",
    },
    hints = { L.STATS_HINT_LEFT },
})

local Call = ezCore.Call   -- geschützter Aufruf, verträgt fehlende Funktionen (eine Fassung für alle Module)

local function Pct(v) return v and ezCore.Percent(v, 2) or nil end

-- Fertigkeitszeilen { name, header, rank, mod, max }: leitet auf ezCore.SkillLines weiter (ein Helfer für ezCore und
-- ezPanel; C_SkillInfo zuerst, die alten Globalen nur als Rückfall, gesperrte Werte unbekannt – EC-85, V-185).
-- Steht in needs (Core.lua); ohne Fertigkeitenliste im Client: keine Zeilen.
local function SkillLines()
    return ezCore.SkillLines() or {}
end

local WEAPON_CATEGORY = 6     -- Client-Tabelle SkillLineCategory, Zeile „Weapon Skills“ (Build 1.60.1.71037, laut wago.tools)

-- Waffenfertigkeiten unter Blizzards Überschrift: an ihrer Kennung (wie Blizzards SkillsFrame, in jeder Sprache), ohne
-- Kennung (alte Globale) am Text STAT_CATEGORY_WEAPON_SKILLS: { { Name, Wert mit Bonus, Höchstwert }, … }
function ns.WeaponSkills()
    local weapons, inWeapons = {}, false
    local title = _G.STAT_CATEGORY_WEAPON_SKILLS or L.STATS_WEAPONS
    for _, line in ipairs(SkillLines()) do
        if line.header then
            if line.id then inWeapons = line.id == WEAPON_CATEGORY else inWeapons = line.name == title end
        elseif inWeapons and type(line.name) == "string" and line.rank then
            weapons[#weapons + 1] = { line.name, line.rank + (line.mod or 0), line.max }
        end
    end
    return weapons
end
local function Int(v) return v and ns.Number(v) or nil end

local function Stat(i)
    local _, value = Call(UnitStat, "player", i)
    return ns.Num(value)
end

local function AttackPower()
    local base, pos, neg = Call(UnitAttackPower, "player")
    base, pos, neg = ns.Num(base), ns.Num(pos) or 0, ns.Num(neg) or 0
    return base and (base + pos + neg) or nil
end

local function RangedAttackPower()
    local base, pos, neg = Call(UnitRangedAttackPower, "player")
    base, pos, neg = ns.Num(base), ns.Num(pos) or 0, ns.Num(neg) or 0
    return base and (base + pos + neg) or nil
end

local function SpellPower()
    local best
    for school = 2, 7 do
        local v = ns.Num(Call(GetSpellBonusDamage, school))
        if v and (not best or v > best) then best = v end
    end
    return best
end

local function SpellCrit()
    local best
    for school = 2, 7 do
        local v = ns.Num(Call(GetSpellCritChance, school))
        if v and (not best or v > best) then best = v end
    end
    return best
end

local function Armor()
    local _, effective = Call(UnitArmor, "player")
    return ns.Num(effective)
end

local function Speed()
    local _, run = Call(GetUnitSpeed, "player")
    run = ns.Num(run)
    return run and run / (BASE_MOVEMENT_SPEED or 7) * 100 or nil
end

local function Defense()
    local base, mod = Call(UnitDefenseSkill, "player")     -- Forever hat nur diese Fassung (Charakterfenster: PaperDollFrame.lua)
    base = ns.Num(base)
    return base and base + (ns.Num(mod) or 0) or nil
end

local function ItemLevel()
    local v = ns.ItemLevel()
    return v and ezCore.Decimal(v, 1) or nil   -- Dezimalzeichen der Spielsprache (T16-2)
end

-- id, Name, Wert als Text
local STATS = {
    { "str", function() return _G.SPELL_STAT1_NAME end, function() return Int(Stat(1)) end },
    { "agi", function() return _G.SPELL_STAT2_NAME end, function() return Int(Stat(2)) end },
    { "sta", function() return _G.SPELL_STAT3_NAME end, function() return Int(Stat(3)) end },
    { "int", function() return _G.SPELL_STAT4_NAME end, function() return Int(Stat(4)) end },
    { "spi", function() return _G.SPELL_STAT5_NAME end, function() return Int(Stat(5)) end },
    { "armor", function() return _G.ARMOR or L.STATS_ARMOR end, function() return Int(Armor()) end },
    { "ap", function() return L.STATS_AP end, function() return Int(AttackPower()) end },
    { "rap", function() return L.STATS_RAP end, function() return Int(RangedAttackPower()) end },
    { "crit", function() return L.STATS_CRIT end, function() return Pct(ns.Num(Call(GetCritChance))) end },
    { "rcrit", function() return L.STATS_RCRIT end, function() return Pct(ns.Num(Call(GetRangedCritChance))) end },
    { "sp", function() return L.STATS_SP end, function() return Int(SpellPower()) end },
    { "heal", function() return L.STATS_HEAL end, function() return Int(ns.Num(Call(GetSpellBonusHealing))) end },
    { "scrit", function() return L.STATS_SCRIT end, function() return Pct(SpellCrit()) end },
    { "hit", function() return L.STATS_HIT end, function() return Pct(ns.Num(Call(GetHitModifier))) end },
    { "shit", function() return L.STATS_SHIT end, function() return Pct(ns.Num(Call(GetSpellHitModifier))) end },
    { "haste", function() return L.STATS_HASTE end, function() return Pct(ns.Num(Call(GetHaste))) end },
    { "defense", function() return L.STATS_DEFENSE end, function() return Int(Defense()) end },
    { "dodge", function() return L.STATS_DODGE end, function() return Pct(ns.Num(Call(GetDodgeChance))) end },
    { "parry", function() return L.STATS_PARRY end, function() return Pct(ns.Num(Call(GetParryChance))) end },
    { "block", function() return L.STATS_BLOCK end, function() return Pct(ns.Num(Call(GetBlockChance))) end },
    { "speed", function() return L.STATS_SPEED end, function() local v = Speed(); return v and ezCore.Percent(v) end },
    { "ilvl", function() return L.STATS_ILVL end, ItemLevel },
}

local BY_ID = {}
for _, s in ipairs(STATS) do BY_ID[s[1]] = s end

-- Passender Standardwert je Klasse.
local AUTO = {
    WARRIOR = "ap", ROGUE = "ap", HUNTER = "rap", PALADIN = "ap", SHAMAN = "sp", DRUID = "sp",
    MAGE = "sp", WARLOCK = "sp", PRIEST = "heal", DEATHKNIGHT = "ap", MONK = "ap",
}

local function Chosen()
    local id = block.cfg.stat
    if id == "auto" then id = AUTO[ezCore.PlayerClass() or ""] or "ap" end   -- Klasse aus ezCore (V-179)
    return BY_ID[id] or BY_ID.ap
end

-- Beschriftung = Name des gewählten Werts (abschaltbar wie bei jedem Baustein).
block.label = function()
    local s = Chosen()
    return s[2]() or s[1]
end

function block:GetText()
    return Chosen()[3]() or "–"
end

local GROUPS = {
    { "STATS_GROUP_BASE", { "str", "agi", "sta", "int", "spi", "armor" } },
    { "STATS_GROUP_MELEE", { "ap", "crit", "hit", "haste", "rap", "rcrit" } },
    { "STATS_GROUP_SPELL", { "sp", "heal", "scrit", "shit" } },
    { "STATS_GROUP_DEFENSE", { "defense", "dodge", "parry", "block" } },
    { "STATS_GROUP_OTHER", { "speed", "ilvl" } },
}

function block:OnTooltip(tooltip)
    local shown = 0
    for i, group in ipairs(GROUPS) do
        local lines = {}
        for _, id in ipairs(group[2]) do
            local s = BY_ID[id]
            local value = s and s[3]()
            if value then lines[#lines + 1] = { s[2]() or id, value } end
        end
        if #lines > 0 then
            if shown > 0 then tooltip:AddLine(" ") end
            shown = shown + #lines
            ns.TipLine(tooltip, L[group[1]], "normal")
            for _, line in ipairs(lines) do ns.TipDoubleLine(tooltip, line[1], line[2], "highlight", "highlight") end
        end
    end
    -- Widerstände
    local res = {}
    for school = 2, 6 do
        local _, total = Call(UnitResistance, "player", school)
        total = ns.Num(total)
        local name = _G["RESISTANCE" .. school .. "_NAME"]
        if total and total > 0 and name then res[#res + 1] = { name, total } end
    end
    if #res > 0 then
        shown = shown + #res
        tooltip:AddLine(" ")
        ns.TipLine(tooltip, L.STATS_GROUP_RESIST, "normal")
        for _, r in ipairs(res) do ns.TipDoubleLine(tooltip, r[1], r[2], "highlight", "highlight") end
    end
    -- Waffenfertigkeiten (Classic-Inhalt), falls der Client sie liefert.
    local weapons = ns.WeaponSkills()
    if #weapons > 0 then
        shown = shown + #weapons
        tooltip:AddLine(" ")
        ns.TipLine(tooltip, L.STATS_WEAPONS, "normal")
        for _, w in ipairs(weapons) do ns.TipDoubleLine(tooltip, w[1], ("%d / %d"):format(w[2], w[3] or w[2]), "highlight", "highlight") end
    end
    -- Leertext (PANEL-17): liefert das Spiel gerade keinen Wert, sagt der Tooltip das
    if shown == 0 then ns.TipLine(tooltip, L.STATS_NONE, "highlight", true) end
end

function block:OnClick(button)
    if button ~= "LeftButton" then return end
    ezCore.TogglePanel("character", "PaperDollFrame")
end

function block:OnMenu(root)
    local cfg = self.cfg
    local menu = root:CreateButton(L.MENU_BAR_SHOWS)
    ns.MenuRadio(menu, L.STATS_AUTO, cfg, "stat", "auto", self)
    menu:CreateDivider()
    for _, s in ipairs(STATS) do
        if s[3]() then ns.MenuRadio(menu, s[2]() or s[1], cfg, "stat", s[1], self) end
    end
end
