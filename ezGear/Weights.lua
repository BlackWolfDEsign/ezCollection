local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Gewichtung: wie viel ein Punkt jedes Werts für den Charakter wert ist.

    Standard je Klasse und Rolle (Schaden, Nahkampf, Zauberschaden, Tank, Heilung). „Automatisch“ wählt die Rolle
    aus der Spezialisierung (GetSpecializationInfo: Rolle und Hauptwert), sonst die Leveling-Rolle der Klasse.
    Werte für Treffer und kritische Treffer gelten je Prozentpunkt („+1 % Trefferchance“ wie auf Forever-Gegenständen).
    Eigene Werte: Pawn-Skalen als Text einfügen, z. B.
      ( Pawn: v1: "Verstärkung": Class=Shaman, Strength=1, Agility=0.6, Stamina=0.3, MeleeDps=4 )
    Pawn-Skalen gelten für alle Charaktere, gewählt wird je Charakter (ezGearDB.chars[charKey].scale).

    HERKUNFT der Standardwerte (Weights.DEFAULTS; Leitlinien 10 und 11, Gesamtreview 18.11.2026, T5-9): eigene,
    von Hand geschätzte Startwerte, angelegt mit dem Modulgerüst von ezGear (git log -S: 67554cb0, 13.11.2026) – keine
    Simulation und nicht aus Pawn oder einem anderen Addon übernommen. Im Spiel nennt Weights.Source() die Quelle der
    aktiven Gewichtung („ezGears Standardwerte“ bzw. die eingefügte Pawn-Skala; Texte WEIGHTS_SOURCE_DEFAULT und
    WEIGHTS_SOURCE_PAWN).
]]

local Weights = {}
ns.Weights = Weights

local EMPTY = {}

---------------------------------------------------------------------------
-- Standardwerte (Klasse → Profile; das erste ist die Leveling-Wahl ohne Spezialisierung)
---------------------------------------------------------------------------

local W = {}

W.WARRIOR_DPS = { STRENGTH = 1, AGILITY = 0.65, STAMINA = 0.3, AP = 0.5, CRIT = 10, HIT = 10, MELEEDPS = 4,
    RANGEDDPS = 0.5, ARMOR = 0.02, DEFENSE = 0.1, DODGE = 4, PARRY = 3, HP5 = 0.5, SPIRIT = 0.05 }
W.WARRIOR_TANK = { STAMINA = 1, STRENGTH = 0.5, AGILITY = 0.6, ARMOR = 0.1, DEFENSE = 1.5, DODGE = 12, PARRY = 10,
    BLOCK = 6, BLOCKVALUE = 0.4, HIT = 6, CRIT = 2, AP = 0.2, MELEEDPS = 1.5, RANGEDDPS = 0.2, HP5 = 0.5 }
W.PALADIN_DPS = { STRENGTH = 1, AGILITY = 0.5, INTELLECT = 0.35, STAMINA = 0.3, AP = 0.5, CRIT = 8, HIT = 8,
    SPELL = 0.3, MELEEDPS = 3.5, ARMOR = 0.02, MP5 = 0.5, SPIRIT = 0.1 }
W.PALADIN_HEAL = { INTELLECT = 1, HEAL = 0.6, SPELL = 0.6, MP5 = 1.5, SPELLCRIT = 8, SPIRIT = 0.2, STAMINA = 0.3,
    ARMOR = 0.005 }
W.PALADIN_TANK = { STAMINA = 1, STRENGTH = 0.5, AGILITY = 0.5, DEFENSE = 1.5, ARMOR = 0.1, DODGE = 12, PARRY = 10,
    BLOCK = 6, BLOCKVALUE = 0.4, SPELL = 0.4, INTELLECT = 0.3, HIT = 5, MELEEDPS = 1 }
W.HUNTER_DPS = { AGILITY = 1, RAP = 0.5, AP = 0.45, INTELLECT = 0.3, STAMINA = 0.3, CRIT = 10, HIT = 10,
    RANGEDDPS = 4, MELEEDPS = 0.4, STRENGTH = 0.05, SPIRIT = 0.05, MP5 = 0.5, ARMOR = 0.01 }
W.ROGUE_DPS = { AGILITY = 1, STRENGTH = 0.5, AP = 0.5, STAMINA = 0.3, CRIT = 10, HIT = 12, MELEEDPS = 4,
    RANGEDDPS = 0.3, ARMOR = 0.01, DODGE = 3 }
W.PRIEST_DPS = { SPELL = 1, INTELLECT = 0.8, SPIRIT = 0.8, STAMINA = 0.4, SPELLHIT = 10, SPELLCRIT = 6, MP5 = 1,
    HEAL = 0.1, RANGEDDPS = 1.5, ARMOR = 0.005 }
W.PRIEST_HEAL = { INTELLECT = 1, SPIRIT = 0.6, HEAL = 0.6, SPELL = 0.6, MP5 = 1.5, SPELLCRIT = 6, STAMINA = 0.3,
    RANGEDDPS = 0.5, ARMOR = 0.005 }
W.SHAMAN_MELEE = { STRENGTH = 1, AGILITY = 0.6, AP = 0.5, INTELLECT = 0.3, STAMINA = 0.3, CRIT = 9, HIT = 9,
    MELEEDPS = 4, SPELL = 0.2, MP5 = 0.3, ARMOR = 0.02 }
W.SHAMAN_CASTER = { SPELL = 1, INTELLECT = 1, SPELLCRIT = 8, SPELLHIT = 8, MP5 = 1.2, STAMINA = 0.3, SPIRIT = 0.2,
    HEAL = 0.2, ARMOR = 0.01 }
W.SHAMAN_HEAL = { INTELLECT = 1, HEAL = 0.6, SPELL = 0.6, MP5 = 1.5, SPELLCRIT = 6, SPIRIT = 0.2, STAMINA = 0.3,
    ARMOR = 0.01 }
W.MAGE_DPS = { SPELL = 1, INTELLECT = 0.9, SPELLHIT = 10, SPELLCRIT = 8, STAMINA = 0.4, SPIRIT = 0.3, MP5 = 0.8,
    RANGEDDPS = 1.5, ARMOR = 0.005 }
W.WARLOCK_DPS = { SPELL = 1, STAMINA = 0.6, INTELLECT = 0.6, SPELLHIT = 10, SPELLCRIT = 6, SPIRIT = 0.3, MP5 = 0.5,
    RANGEDDPS = 1.5, ARMOR = 0.005 }
W.DRUID_MELEE = { AGILITY = 1, STRENGTH = 0.9, AP = 0.45, STAMINA = 0.3, CRIT = 9, HIT = 9, ARMOR = 0.02,
    INTELLECT = 0.1 }
W.DRUID_TANK = { STAMINA = 1, AGILITY = 0.7, ARMOR = 0.12, STRENGTH = 0.5, DEFENSE = 1.2, DODGE = 12, HIT = 5,
    CRIT = 3, AP = 0.2 }
W.DRUID_CASTER = { SPELL = 1, INTELLECT = 0.9, SPELLCRIT = 8, SPELLHIT = 8, SPIRIT = 0.4, MP5 = 1, STAMINA = 0.3,
    HEAL = 0.2 }
W.DRUID_HEAL = { INTELLECT = 1, HEAL = 0.6, SPELL = 0.6, SPIRIT = 0.6, MP5 = 1.5, SPELLCRIT = 6, STAMINA = 0.3 }
Weights.DEFAULTS = W

-- Klasse → Profile (Rolle); das erste gilt beim Leveln ohne Spezialisierung.
Weights.CLASS_PROFILES = {
    WARRIOR = { "DPS", "TANK" },
    PALADIN = { "DPS", "HEAL", "TANK" },
    HUNTER = { "DPS" },
    ROGUE = { "DPS" },
    PRIEST = { "DPS", "HEAL" },
    SHAMAN = { "MELEE", "CASTER", "HEAL" },
    MAGE = { "DPS" },
    WARLOCK = { "DPS" },
    DRUID = { "MELEE", "CASTER", "TANK", "HEAL" },
}

local INTELLECT_STAT = (LE_UNIT_STAT_INTELLECT or 4)

---------------------------------------------------------------------------
-- „Gut für“ im Item-Wissen von ezCore (Knowledge.SetStatGoodFor): ein Wert ist gut für die Klassen, in deren
-- Standard-Gewichtung er zählt – mindestens GOOD_FOR_SHARE des höchsten Gewichts, das irgendeine Klasse ihm gibt
-- (die Schlüssel zählen je Punkt bzw. je Prozent, nur so sind sie vergleichbar). Zählt er für jede Klasse (Ausdauer,
-- Rüstung) oder für keine (Widerstände), ist er gut für alle (nil). Eingefügte Pawn-Skalen zählen hier nicht: sie
-- rechnen in Pawns eigenem Maßstab und gelten für einen Charakter, „Gut für“ für alle.
---------------------------------------------------------------------------

Weights.GOOD_FOR_SHARE = 0.3

-- Werte, die das Item-Wissen anders schneidet als ezGear
local GOOD_FOR_ALIAS = { DPS = { "MELEEDPS", "RANGEDDPS" } }

local goodFor   -- [Wert] = { [Klasse] = true } oder false (gut für alle)

local function BuildGoodFor()
    local best, top, stats = {}, {}, {}
    for class, roles in pairs(Weights.CLASS_PROFILES) do
        best[class] = {}
        for _, role in ipairs(roles) do
            for stat, value in pairs(W[class .. "_" .. role] or EMPTY) do
                if type(value) == "number" and value > 0 then
                    stats[stat] = true
                    if value > (best[class][stat] or 0) then best[class][stat] = value end
                    if value > (top[stat] or 0) then top[stat] = value end
                end
            end
        end
    end
    local result = {}
    for stat in pairs(stats) do
        local set, all = {}, true
        for class in pairs(Weights.CLASS_PROFILES) do
            local value = best[class][stat]
            if not value then all = false end
            if value and value >= top[stat] * Weights.GOOD_FOR_SHARE then set[class] = true end
        end
        result[stat] = not all and set or false
    end
    return result
end

-- Klassen-Menge eines Werts (Schlüssel wie im Item-Wissen) oder nil = gut für alle
function Weights.GoodFor(stat)
    if type(stat) ~= "string" then return nil end
    goodFor = goodFor or BuildGoodFor()
    local alias = GOOD_FOR_ALIAS[stat]
    if alias then
        local union
        for _, key in ipairs(alias) do
            local set = goodFor[key]
            if set == false then return nil end
            if set then
                union = union or {}
                for class in pairs(set) do union[class] = true end
            end
        end
        return union
    end
    return goodFor[stat] or nil
end

do
    local K = Core.Knowledge
    if K and type(K.SetStatGoodFor) == "function" then K.SetStatGoodFor(Weights.GoodFor) end
end

---------------------------------------------------------------------------
-- Gewählte Gewichtung des Charakters
---------------------------------------------------------------------------

local function HasProfile(class, role)
    for _, r in ipairs(Weights.CLASS_PROFILES[class] or {}) do
        if r == role then return true end
    end
    return false
end

-- Spezialisierung → Rolle des Profils (nil ohne Spezialisierung)
function Weights.SpecRole(class)
    local index = ns.Plain(ns.Call(GetSpecialization))
    if type(index) ~= "number" or index < 1 then return nil end
    local _, specName, _, _, role, primaryStat = ns.Call(GetSpecializationInfo, index)
    role, primaryStat, specName = ns.Plain(role), ns.Plain(primaryStat), ns.Plain(specName)
    local wanted
    if role == "TANK" then
        wanted = "TANK"
    elseif role == "HEALER" then
        wanted = "HEAL"
    elseif role == "DAMAGER" then
        if primaryStat == INTELLECT_STAT then
            wanted = HasProfile(class, "CASTER") and "CASTER" or "DPS"
        else
            wanted = HasProfile(class, "MELEE") and "MELEE" or "DPS"
        end
    end
    if wanted and HasProfile(class, wanted) then return wanted, specName end
    return nil, specName
end

local function ClassOf()
    if ns.playerClass then return ns.playerClass end
    return Core.PlayerClass()
end

-- Schlüssel der gewählten Gewichtung: "auto", "DEF:WARRIOR_TANK" oder "PAWN:<Name>"
function Weights.Choice()
    local choice = ns.Char().scale
    if type(choice) ~= "string" or choice == "" then return "auto" end
    if choice:sub(1, 5) == "PAWN:" and not (ns.db and ns.db.scales[choice:sub(6)]) then return "auto" end
    if choice:sub(1, 4) == "DEF:" and not W[choice:sub(5)] then return "auto" end
    return choice
end

function Weights.SetChoice(choice)
    ns.Char().scale = (choice ~= "auto") and choice or nil
    ns.Changed()
end

-- Gewichtung einer Wahl auflösen → weights, label, key
function Weights.Resolve(choice)
    local class = ClassOf()
    if choice:sub(1, 5) == "PAWN:" then
        local name = choice:sub(6)
        return ns.db.scales[name].weights, name, choice
    end
    if choice:sub(1, 4) == "DEF:" then
        local key = choice:sub(5)
        return W[key], Weights.ProfileLabel(key), choice
    end
    -- automatisch
    local profiles = Weights.CLASS_PROFILES[class or ""]
    if not profiles then return EMPTY, L.WEIGHTS_NONE, "auto" end
    local specRole, specName = Weights.SpecRole(class)
    local key = class .. "_" .. (specRole or profiles[1])
    local label = (specRole and specName and specName ~= "") and specName or Weights.ProfileLabel(key)
    return W[key] or EMPTY, label, "DEF:" .. key
end

-- Gewählte Gewichtung des Charakters → weights, label, key
function Weights.Active()
    return Weights.Resolve(Weights.Choice())
end

-- „Krieger: Tank“
function Weights.ProfileLabel(key)
    local class, role = key:match("^(%u+)_(%u+)$")
    if not class then return key end
    return ("%s: %s"):format(Core.ClassName(class) or class, L["ROLE_" .. role] or role)
end

-- Kurzer Name für Tooltip und Menüs („für Verstärkung“)
function Weights.Label()
    local _, label = Weights.Active()
    return label
end

-- Woher die aktive Gewichtung stammt (Regel „Datenquellen“ des Nutzers: jede Angabe nennt ihre Quelle)
-- → "pawn" (eingefügte Skala) | "default" (ezGears Standardwerte je Klasse und Rolle), Text für Status und Anzeigen
function Weights.Source()
    if Weights.Choice():sub(1, 5) == "PAWN:" then return "pawn", L.WEIGHTS_SOURCE_PAWN end
    return "default", L.WEIGHTS_SOURCE_DEFAULT
end

---------------------------------------------------------------------------
-- Pawn-Skalen
---------------------------------------------------------------------------

-- Pawn-Wertname → ezGear-Schlüssel (mehrere Ziele möglich)
Weights.FROM_PAWN = {
    Strength = { "STRENGTH" }, Agility = { "AGILITY" }, Stamina = { "STAMINA" }, Intellect = { "INTELLECT" },
    Spirit = { "SPIRIT" }, Armor = { "ARMOR" }, BonusArmor = { "ARMOR" },
    Dps = { "MELEEDPS", "RANGEDDPS" }, MeleeDps = { "MELEEDPS" }, RangedDps = { "RANGEDDPS" },
    Ap = { "AP" }, Rap = { "RAP" }, SpellPower = { "SPELL" }, SpellDamage = { "SPELL" }, Healing = { "HEAL" },
    Mp5 = { "MP5" }, Hp5 = { "HP5" }, HitRating = { "HIT" }, CritRating = { "CRIT" },
    SpellHitRating = { "SPELLHIT" }, SpellCritRating = { "SPELLCRIT" }, DefenseRating = { "DEFENSE" },
    DodgeRating = { "DODGE" }, ParryRating = { "PARRY" }, BlockRating = { "BLOCK" }, BlockValue = { "BLOCKVALUE" },
    HasteRating = { "HASTE" }, SpellHasteRating = { "HASTE" }, ExpertiseRating = { "EXPERTISE" },
    ArmorPenetration = { "ARMORPEN" }, SpellPenetration = { "SPELLPEN" }, MasteryRating = { "MASTERY" },
    Versatility = { "VERSATILITY" },
    FireResist = { "FIRERES" }, FrostResist = { "FROSTRES" }, NatureResist = { "NATURERES" },
    ShadowResist = { "SHADOWRES" }, ArcaneResist = { "ARCANERES" },
    AllResist = { "FIRERES", "FROSTRES", "NATURERES", "SHADOWRES", "ARCANERES" },
}

-- Pawn-Klassennamen (englisch, ohne Leerzeichen) → Klassen-Token
local PAWN_CLASS = {
    warrior = "WARRIOR", paladin = "PALADIN", hunter = "HUNTER", rogue = "ROGUE", priest = "PRIEST",
    shaman = "SHAMAN", mage = "MAGE", warlock = "WARLOCK", druid = "DRUID",
}

--[[
    Weights.ParsePawn(text) → name, weights, class, unknown, invalid | nil, Fehlertext
      text: '( Pawn: v1: "Name": Stat=Wert, … )'; Class und Spec werden gelesen bzw. übersprungen,
      unbekannte Werte landen in unknown (Liste), „X“ (bei Pawn: nicht tragbar) wird übersprungen.
      Gesamtreview 18.11.2026: Der Name kommt ohne „|“-Codes und Steuerzeichen, auf PAWN_NAME_MAX Zeichen gekürzt
      (Core.CleanImportName, T6-5); ein Gewicht muss endlich sein und zwischen -PAWN_MAX_WEIGHT und PAWN_MAX_WEIGHT
      liegen (Core.FiniteNumber, T6-8: „1e999“ wurde sonst unendlich, jede Bewertung inf, Vergleiche NaN) – sonst
      landet der Wert in invalid (Liste „Stat=Wert“).
]]
Weights.PAWN_NAME_MAX = 60
Weights.PAWN_MAX_WEIGHT = 1000

function Weights.ParsePawn(text)
    if type(text) ~= "string" or Core.IsSecret(text) then return nil, L.PAWN_BAD end
    local version, name, values = text:match("^%s*%(%s*[Pp]awn%s*:%s*v(%d+)%s*:%s*\"([^\"]+)\"%s*:%s*(.-)%s*%)%s*$")
    if not version then return nil, L.PAWN_BAD end
    name = Core.CleanImportName(name, Weights.PAWN_NAME_MAX)
    if not name then return nil, L.PAWN_BAD end
    local weights, unknown, invalid, class, count = {}, {}, {}, nil, 0
    for pair in (values .. ","):gmatch("([^,]*),") do
        local stat, value = pair:match("^%s*([%a%d_]+)%s*=%s*([^%s]+)%s*$")
        if stat then
            if stat == "Class" then
                class = PAWN_CLASS[value:lower()]
            elseif stat == "Spec" then
                -- Pawn-Spezialisierung: für ezGear ohne Bedeutung
            else
                local number = tonumber(value)
                local targets = Weights.FROM_PAWN[stat]
                local valid = Core.FiniteNumber(number, -Weights.PAWN_MAX_WEIGHT, Weights.PAWN_MAX_WEIGHT)
                if number and targets and not valid then
                    invalid[#invalid + 1] = stat .. "=" .. Core.Literal(value)
                elseif number and targets then
                    for _, key in ipairs(targets) do weights[key] = valid end
                    count = count + 1
                elseif number then
                    unknown[#unknown + 1] = stat
                end
            end
        end
    end
    if count == 0 then return nil, #invalid > 0 and L.PAWN_INVALID:format(table.concat(invalid, ", ")) or L.PAWN_EMPTY end
    return name, weights, class, unknown, invalid
end

-- Skala speichern; ohne Klasse in der Skala gilt die des aktuellen Charakters. Danach für ihn gewählt.
-- Eine Skala gleichen Namens wird ersetzt – die Rückfrage dazu stellt ns.ImportPawnScale.
-- → name, unknown, invalid | nil, Fehlertext
function Weights.AddPawn(text)
    local name, weights, class, unknown, invalid = Weights.ParsePawn(text)
    if not name then return nil, weights end
    ns.db.scales[name] = { class = class or ClassOf(), weights = weights }
    Weights.SetChoice("PAWN:" .. name)
    return name, unknown, invalid
end

function Weights.RemovePawn(name)
    if not (ns.db and ns.db.scales[name]) then return false end
    ns.db.scales[name] = nil
    for _, c in pairs(ns.db.chars) do
        if type(c) == "table" and c.scale == "PAWN:" .. name then c.scale = nil end
    end
    ns.Changed()
    return true
end

-- Pawn-Skalen sortiert; eigene Klasse zuerst
function Weights.PawnList()
    local class = ClassOf()
    local list = {}
    for name, scale in pairs(ns.db and ns.db.scales or {}) do
        list[#list + 1] = { name = name, class = scale.class, own = scale.class == class }
    end
    table.sort(list, function(a, b)
        if a.own ~= b.own then return a.own end
        return a.name < b.name
    end)
    return list
end

-- Mit Rückmeldung im Chat (Knopf, Slash-Befehl). Gibt es schon eine Skala dieses Namens, wird sie erst nach einer
-- Rückfrage ersetzt (Gesamtreview 18.11.2026: Vorschau vor dem Überschreiben). → false bei einem ungültigen Text.
function ns.ImportPawnScale(text)
    local name, info = Weights.ParsePawn(text)
    if not name then
        ns.Print(info or L.PAWN_BAD)
        return false
    end
    local function Add()
        local added, unknown, invalid = Weights.AddPawn(text)
        if not added then return ns.Print(unknown or L.PAWN_BAD) end
        ns.Print(L.PAWN_ADDED:format(added))
        if type(unknown) == "table" and #unknown > 0 then ns.Print(L.PAWN_UNKNOWN:format(table.concat(unknown, ", "))) end
        if type(invalid) == "table" and #invalid > 0 then ns.Print(L.PAWN_INVALID:format(table.concat(invalid, ", "))) end
    end
    if ns.db and type(ns.db.scales) == "table" and ns.db.scales[name] ~= nil then
        Core.Confirm(L.PAWN_REPLACE_ASK:format(name), Add)
    else
        Add()
    end
    return true
end

function ns.AskPawnScale()
    Core.AskText(L.PAWN_ASK, "", function(text) ns.ImportPawnScale(text) end, 2000)
end

---------------------------------------------------------------------------
-- Menü „Gewichtung“ (Knopf in den Einstellungen, im Menü „Sets“ am Charakterfenster, Rechtsklick am Addon-Knopf)
---------------------------------------------------------------------------

function ns.AddWeightMenu(root)
    local Menu = Core.Menu
    local class = ClassOf()
    local function Radio(text, key, tip)
        return ns.MenuTip(Menu.Radio(root, text, Weights.Choice, Weights.SetChoice, key), text, tip)
    end
    local _, autoLabel = Weights.Resolve("auto")
    Radio(L.WEIGHTS_AUTO:format(autoLabel), "auto", L.MTIP_WEIGHTS_AUTO)
    for _, role in ipairs(Weights.CLASS_PROFILES[class or ""] or {}) do
        local key = class .. "_" .. role
        Radio(Weights.ProfileLabel(key), "DEF:" .. key, L.MTIP_WEIGHTS_ROLE)
    end
    local pawns = Weights.PawnList()
    if #pawns > 0 then
        Menu.Divider(root)
        Menu.Title(root, L.WEIGHTS_PAWN_TITLE)
        for _, entry in ipairs(pawns) do
            local text = entry.name
            if not entry.own and entry.class then text = ("%s (%s)"):format(text, Core.ClassName(entry.class) or entry.class) end
            Radio(text, "PAWN:" .. entry.name, L.MTIP_WEIGHTS_PAWN)
        end
    end
    Menu.Divider(root)
    ns.MenuTip(Menu.Button(root, L.WEIGHTS_COMPARE, function() ns.PrintCompare() end), L.WEIGHTS_COMPARE, L.MTIP_WEIGHTS_COMPARE)
    ns.MenuTip(Menu.Button(root, L.WEIGHTS_PAWN_ADD, function() ns.AskPawnScale() end), L.WEIGHTS_PAWN_ADD, L.MTIP_PAWN_ADD)
    if #pawns > 0 then
        local remove = ns.MenuTip(Menu.Button(root, L.WEIGHTS_PAWN_REMOVE), L.WEIGHTS_PAWN_REMOVE, L.MTIP_PAWN_REMOVE)
        for _, entry in ipairs(pawns) do
            if remove and remove.CreateButton then
                ns.MenuTip(Menu.Button(remove, entry.name, function()
                    Core.Confirm(L.WEIGHTS_PAWN_REMOVE_ASK:format(entry.name), function() Weights.RemovePawn(entry.name) end)
                end), entry.name, L.MTIP_PAWN_REMOVE_ONE)
            end
        end
    end
end

function ns.OpenWeightMenu(owner)
    return Core.Menu.Open(owner or UIParent, function(root)
        Core.Menu.Title(root, L.WEIGHTS_TITLE)
        ns.AddWeightMenu(root)
    end)
end

ns.AddStatusLine(function()
    local weights, label = Weights.Active()
    local parts = {}
    for _, key in ipairs(ns.Stats.ORDER) do
        if weights[key] and weights[key] ~= 0 then
            parts[#parts + 1] = ("%s %s"):format(ns.Stats.Name(key), Core.Round and Core.Round(weights[key], 2) or weights[key])
        end
    end
    local _, source = Weights.Source()
    return { L.STATUS_WEIGHTS:format(label, table.concat(parts, ", ")), source }
end)
