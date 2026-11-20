local _, ns = ...

--[[
    Statische Tabellen für Knowledge.lua (Classic-Inhalte auf der Retail-Engine).
    Reine Daten. Die Namen hier sind nur Rückfall, falls der Client keinen
    lokalisierten Namen liefert – zum Auswerten von Tooltips werden sie nie benutzt.
    Muss in der TOC VOR Knowledge.lua stehen.

    QUELLE und STAND (DG-53, Leitlinie 10; Herkunft nachgelesen mit git log -S, 15.11.2026): Die Tabellen entstanden
    am 12.11.2026 mit dem Item-Wissen in ezBag (6d89fde) und zogen am 13.11.2026 nach ezCore (455c17b, 0d3b914).
    Geschrieben in eigener Form aus Blizzards Client-Daten bzw. allgemeinem Wissen über die Classic-Regeln (Patch 1.12).
    Nichts stammt aus den Dateien eines Addons. Je Abschnitt:
      - Klassen-Namen, Berufs-Namen, Material-Namen, Werte-Namen: nur Rückfall; angezeigt wird der Name des Clients
        (GetTradeSkillDisplayName, GetSpellInfo, die Globalen in STAT_GLOBALS bzw. STAT_LINE_GLOBALS).
      - SkillLine-IDs und Lehrlings-Zauber der Berufe, Unterklassen (Enum.ItemWeaponSubclass, Rezepte,
        Handwerkswaren, Verbrauchbares), Inventar-Werteschlüssel (GetItemStats): Blizzards Nummern; der Client
        bestätigt sie beim Lesen (unbekannte Nummern bleiben ohne Wirkung).
      - Satt-Zauber (WELL_FED_SPELLS): Zauber-IDs aus Classic; /ez test prüft jede gegen den Client (Spells.BUFFS).
      - Rüstung und Waffen je Klasse samt Stufe (ARMOR_PROF, WEAPONS_BY_CLASS) und die Grenzen „hoher Händlerwert“:
        UNGEPRÜFT – Classic-Regeln bzw. eigene Wahl, im Spiel gegen den Client zu bestätigen (Forever kann abweichen).
      - Suchwörter (SEARCH_*): eigene Wahl.
]]

local D = {}
ns.KnowledgeData = D
-- Kennzeichen für Prüfungen und Anzeigen: Tabellen mit ungeprüften Classic-Regeln (siehe Kopf).
D.UNVERIFIED = { ARMOR_PROF = true, WEAPONS_BY_CLASS = true, HIGH_VALUE_LOW_QUALITY = true, HIGH_VALUE_ANY = true }

local function Set(...)
    local t = {}
    for i = 1, select("#", ...) do t[select(i, ...)] = true end
    return t
end

---------------------------------------------------------------------------
-- Klassen
---------------------------------------------------------------------------

D.CLASSES = ezCore.CLASSES   -- eine Liste (Format.lua)

D.CLASS_NAMES = {
    de = {
        WARRIOR = "Krieger", PALADIN = "Paladin", HUNTER = "Jäger", ROGUE = "Schurke", PRIEST = "Priester",
        SHAMAN = "Schamane", MAGE = "Magier", WARLOCK = "Hexenmeister", DRUID = "Druide",
    },
    en = {
        WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
        SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
    },
}

-- Klassen mit Mana (für Getränke und Manatränke).
D.MANA_CLASSES = Set("PALADIN", "HUNTER", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID")

---------------------------------------------------------------------------
-- Berufe: SkillLine-ID (C_TradeSkillUI), Lehrlings-Zauber (liefert den
-- lokalisierten Namen), Rückfall-Namen. Reihenfolge = Anzeige-Reihenfolge.
---------------------------------------------------------------------------

D.PROFESSIONS = {
    { key = "alchemy", skillLine = 171, spell = 2259, de = "Alchemie", en = "Alchemy" },
    { key = "blacksmithing", skillLine = 164, spell = 2018, de = "Schmiedekunst", en = "Blacksmithing" },
    { key = "enchanting", skillLine = 333, spell = 7411, de = "Verzauberkunst", en = "Enchanting" },
    { key = "engineering", skillLine = 202, spell = 4036, de = "Ingenieurskunst", en = "Engineering" },
    { key = "leatherworking", skillLine = 165, spell = 2108, de = "Lederverarbeitung", en = "Leatherworking" },
    { key = "tailoring", skillLine = 197, spell = 3908, de = "Schneiderei", en = "Tailoring" },
    { key = "cooking", skillLine = 185, spell = 2550, de = "Kochkunst", en = "Cooking" },
    { key = "firstaid", skillLine = 129, spell = 3273, de = "Erste Hilfe", en = "First Aid" },
    { key = "mining", skillLine = 186, spell = 2575, de = "Bergbau", en = "Mining" },
    -- Kein Zauber: "Kräutersammeln" heißt anders als der Beruf.
    { key = "herbalism", skillLine = 182, de = "Kräuterkunde", en = "Herbalism" },
    { key = "skinning", skillLine = 393, spell = 8613, de = "Kürschnerei", en = "Skinning" },
    { key = "fishing", skillLine = 356, spell = 7620, de = "Angeln", en = "Fishing" },
}
-- Juwelierskunst (Fertigkeitslinie 755, Zauber 25229) und Inschriftenkunde (Linie 773, Zauber 45357) gibt es auf
-- Forever nicht – weder als Zauber noch als Fertigkeitslinie (wago-Prüfung gegen die Client-Tabellen wowf 1.60.1.70938,
-- docs/wago-tools.md). Gestrichen im Gesamtreview vom 18.11.2026 (T14-3) samt Rezept-Unterklassen 10 und 11, Handwerkswaren
-- 4 und 16 und ihren Materialnamen; Herkunft 455c17b8 bzw. 6d89fdea (ezBag 1.3.0). Kein Leser hängt an den Schlüsseln
-- (Suche über alle Module, Tests und tools/).

-- Rezepte (Gegenstandsklasse 9): Unterklasse → Beruf. 0 = Buch (kein Beruf).
D.RECIPE_SUBCLASS = {
    [1] = "leatherworking", [2] = "tailoring", [3] = "engineering", [4] = "blacksmithing",
    [5] = "cooking", [6] = "alchemy", [7] = "firstaid", [8] = "enchanting", [9] = "fishing",
}

-- Handwerkswaren (Gegenstandsklasse 7): Unterklasse → Material und Berufe, die es verarbeiten.
D.TRADEGOODS = {
    [1] = { mat = "parts", profs = { "engineering" } },
    [2] = { mat = "explosives", profs = { "engineering" } },
    [3] = { mat = "devices", profs = { "engineering" } },
    [5] = { mat = "cloth", profs = { "tailoring", "firstaid" } },
    [6] = { mat = "leather", profs = { "leatherworking" } },
    [7] = { mat = "metal", profs = { "blacksmithing", "engineering", "mining" } },
    [8] = { mat = "meat", profs = { "cooking" } },
    [9] = { mat = "herb", profs = { "alchemy" } },
    [10] = { mat = "elemental", profs = { "alchemy", "blacksmithing", "leatherworking", "tailoring", "engineering", "enchanting" } },
    [11] = { mat = "other" },
    [12] = { mat = "enchanting", profs = { "enchanting" } },
}

D.MAT_NAMES = {
    de = {
        parts = "Teile", explosives = "Sprengstoff", devices = "Geräte", cloth = "Stoff",
        leather = "Leder", metal = "Metall & Stein", meat = "Fleisch", herb = "Kräuter", elemental = "Elementar",
        other = "Sonstiges", enchanting = "Verzauberkunst",
    },
    en = {
        parts = "Parts", explosives = "Explosives", devices = "Devices", cloth = "Cloth",
        leather = "Leather", metal = "Metal & Stone", meat = "Meat", herb = "Herb", elemental = "Elemental",
        other = "Other", enchanting = "Enchanting",
    },
}

-- Verbrauchbar (Klasse 0): Unterklasse → Art. Essen/Trinken (5) wird per Tooltip verfeinert.
D.CONSUMABLE_KIND = {
    [0] = "other", [1] = "potion", [2] = "elixir", [3] = "flask", [4] = "scroll",
    [5] = "food", [6] = "weaponEnchant", [7] = "bandage", [8] = "other",
}

-- Zauber "Satt" (Well Fed) – EINE Liste (V-030; vorher eine zweite, abweichende in SpellData.lua). Das Item-Wissen
-- braucht nur den lokalisierten Namen, ezBuff erkennt daran die Aura: Spells.BUFFS.wellFed.spells ist dieselbe Tabelle.
D.WELL_FED_SPELLS = { 19705, 19706, 19708, 19709, 19710, 19711, 24799, 25694, 22730, 25661, 18191, 18192, 18193, 18194,
    18222, 18125, 18141 }

---------------------------------------------------------------------------
-- Rüstung und Waffen (Classic-Regeln)
---------------------------------------------------------------------------

D.ARMOR_KEYS = {
    [0] = "misc", [1] = "cloth", [2] = "leather", [3] = "mail", [4] = "plate", [5] = "cosmetic",
    [6] = "shield", [7] = "libram", [8] = "idol", [9] = "totem", [10] = "sigil", [11] = "relic",
}

-- Rüstungs-Unterklasse → { Klasse = ab Stufe }. Fehlt ein Eintrag, dürfen es alle tragen.
D.ARMOR_PROF = {
    [2] = { WARRIOR = 1, PALADIN = 1, HUNTER = 1, ROGUE = 1, SHAMAN = 1, DRUID = 1 },
    [3] = { WARRIOR = 1, PALADIN = 1, HUNTER = 40, SHAMAN = 40 },
    [4] = { WARRIOR = 40, PALADIN = 40 },
    [6] = { WARRIOR = 1, PALADIN = 1, SHAMAN = 1 },
    [7] = { PALADIN = 1 },
    [8] = { DRUID = 1 },
    [9] = { SHAMAN = 1 },
    [10] = {},
}

-- Waffen-Unterklassen (Enum.ItemWeaponSubclass): 0 Axt 1H, 1 Axt 2H, 2 Bogen, 3 Schusswaffe,
-- 4 Streitkolben 1H, 5 Streitkolben 2H, 6 Stangenwaffe, 7 Schwert 1H, 8 Schwert 2H, 10 Stab,
-- 13 Faustwaffe, 14 Verschiedenes, 15 Dolch, 16 Wurfwaffe, 18 Armbrust, 19 Zauberstab, 20 Angel.
D.WEAPONS_BY_CLASS = {
    WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 },
    PALADIN = { 0, 1, 4, 5, 6, 7, 8 },
    HUNTER = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 },
    ROGUE = { 2, 3, 4, 7, 13, 15, 16, 18 },
    PRIEST = { 4, 10, 15, 19 },
    SHAMAN = { 0, 1, 4, 5, 10, 13, 15 },
    MAGE = { 7, 10, 15, 19 },
    WARLOCK = { 7, 10, 15, 19 },
    DRUID = { 4, 5, 10, 13, 15 },
}
D.WEAPONS_ALL = { [14] = true, [20] = true }

---------------------------------------------------------------------------
-- Werte
---------------------------------------------------------------------------

D.STAT_ORDER = {
    "STAMINA", "STRENGTH", "AGILITY", "INTELLECT", "SPIRIT", "MP5", "HP5", "AP", "RAP",
    "SPELL", "HEAL", "HIT", "CRIT", "SPELLHIT", "SPELLCRIT", "HASTE", "EXPERTISE", "ARMORPEN", "SPELLPEN",
    "MASTERY", "VERSATILITY", "DEFENSE", "DODGE", "PARRY", "BLOCK", "BLOCKVALUE", "ARMOR", "MELEEDPS", "RANGEDDPS",
    "FIRERES", "FROSTRES", "NATURERES", "SHADOWRES", "ARCANERES", "HOLYRES",
}

-- Globale Texte, aus denen die lokalisierten Wertenamen gelesen werden (erster gefundener = Anzeige).
D.STAT_GLOBALS = {
    STRENGTH = { "SPELL_STAT1_NAME", "ITEM_MOD_STRENGTH_SHORT" },
    AGILITY = { "SPELL_STAT2_NAME", "ITEM_MOD_AGILITY_SHORT" },
    STAMINA = { "SPELL_STAT3_NAME", "ITEM_MOD_STAMINA_SHORT" },
    INTELLECT = { "SPELL_STAT4_NAME", "ITEM_MOD_INTELLECT_SHORT" },
    SPIRIT = { "SPELL_STAT5_NAME", "ITEM_MOD_SPIRIT_SHORT" },
    MP5 = { "ITEM_MOD_MANA_REGENERATION_SHORT" },
    HP5 = { "ITEM_MOD_HEALTH_REGENERATION_SHORT", "ITEM_MOD_HEALTH_REGEN_SHORT" },
    AP = { "ITEM_MOD_ATTACK_POWER_SHORT" },
    RAP = { "ITEM_MOD_RANGED_ATTACK_POWER_SHORT" },
    SPELL = { "ITEM_MOD_SPELL_POWER_SHORT", "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT" },
    HEAL = { "ITEM_MOD_SPELL_HEALING_DONE_SHORT" },
    HIT = { "ITEM_MOD_HIT_RATING_SHORT" },
    CRIT = { "ITEM_MOD_CRIT_RATING_SHORT" },
    SPELLHIT = { "ITEM_MOD_HIT_SPELL_RATING_SHORT" },
    SPELLCRIT = { "ITEM_MOD_CRIT_SPELL_RATING_SHORT" },
    DEFENSE = { "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT" },
    ARMOR = { "RESISTANCE0_NAME" },
}

-- Schlüssel aus GetItemStats → eigener Wert-Schlüssel (alle Werte, auch die ohne Tooltip-Erkennung).
-- Eine Liste für Item-Wissen und ezGear (vorher ezGear Stats.FROM_BLIZZARD). DPS wird je nach Platz
-- MELEEDPS oder RANGEDDPS (K.StatKey).
D.ITEM_STAT_KEYS = {
    ITEM_MOD_STAMINA_SHORT = "STAMINA", ITEM_MOD_STRENGTH_SHORT = "STRENGTH", ITEM_MOD_AGILITY_SHORT = "AGILITY",
    ITEM_MOD_INTELLECT_SHORT = "INTELLECT", ITEM_MOD_SPIRIT_SHORT = "SPIRIT",
    ITEM_MOD_MANA_REGENERATION_SHORT = "MP5",
    ITEM_MOD_HEALTH_REGEN_SHORT = "HP5", ITEM_MOD_HEALTH_REGENERATION_SHORT = "HP5",
    ITEM_MOD_ATTACK_POWER_SHORT = "AP", ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "RAP",
    ITEM_MOD_SPELL_POWER_SHORT = "SPELL", ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "SPELL",
    ITEM_MOD_SPELL_HEALING_DONE_SHORT = "HEAL",
    ITEM_MOD_HIT_RATING_SHORT = "HIT", ITEM_MOD_CRIT_RATING_SHORT = "CRIT",
    ITEM_MOD_HIT_SPELL_RATING_SHORT = "SPELLHIT", ITEM_MOD_CRIT_SPELL_RATING_SHORT = "SPELLCRIT",
    ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "DEFENSE",
    ITEM_MOD_DODGE_RATING_SHORT = "DODGE", ITEM_MOD_PARRY_RATING_SHORT = "PARRY",
    ITEM_MOD_BLOCK_RATING_SHORT = "BLOCK", ITEM_MOD_BLOCK_VALUE_SHORT = "BLOCKVALUE",
    ITEM_MOD_HASTE_RATING_SHORT = "HASTE", ITEM_MOD_EXPERTISE_RATING_SHORT = "EXPERTISE",
    ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT = "ARMORPEN", ITEM_MOD_SPELL_PENETRATION_SHORT = "SPELLPEN",
    ITEM_MOD_MASTERY_RATING_SHORT = "MASTERY", ITEM_MOD_VERSATILITY = "VERSATILITY",
    RESISTANCE0_NAME = "ARMOR",
    RESISTANCE1_NAME = "HOLYRES", RESISTANCE2_NAME = "FIRERES", RESISTANCE3_NAME = "NATURERES",
    RESISTANCE4_NAME = "FROSTRES", RESISTANCE5_NAME = "SHADOWRES", RESISTANCE6_NAME = "ARCANERES",
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "DPS",
}

-- Distanzplätze: Waffenschaden zählt dort als RANGEDDPS
D.RANGED_LOCS = ezCore.EquipSlots.RANGED_LOCS   -- eine Tabelle für alle: EquipSlots.lua (V-178)

-- Format-Texte der Werte-Zeilen auf Ausrüstung ("%c%s Ausdauer"), Rückfall ohne GetItemStats.
D.STAT_LINE_GLOBALS = {
    STRENGTH = "ITEM_MOD_STRENGTH", AGILITY = "ITEM_MOD_AGILITY", STAMINA = "ITEM_MOD_STAMINA",
    INTELLECT = "ITEM_MOD_INTELLECT", SPIRIT = "ITEM_MOD_SPIRIT",
}

D.STAT_NAMES = {
    de = {
        STAMINA = "Ausdauer", STRENGTH = "Stärke", AGILITY = "Beweglichkeit", INTELLECT = "Intelligenz",
        SPIRIT = "Willenskraft", MP5 = "Mana alle 5 Sek.", HP5 = "Gesundheit alle 5 Sek.", AP = "Angriffskraft",
        RAP = "Distanzangriffskraft", SPELL = "Zaubermacht", HEAL = "Heilung", HIT = "Trefferchance",
        CRIT = "Kritische Treffer", SPELLHIT = "Zaubertreffer", SPELLCRIT = "Kritische Zaubertreffer",
        DEFENSE = "Verteidigung", ARMOR = "Rüstung",
        DODGE = "Ausweichen", PARRY = "Parieren", BLOCK = "Blocken", BLOCKVALUE = "Blockwert", HASTE = "Tempo",
        EXPERTISE = "Waffenkunde", ARMORPEN = "Rüstungsdurchschlag", SPELLPEN = "Zauberdurchschlag",
        MASTERY = "Meisterschaft", VERSATILITY = "Vielseitigkeit",
        MELEEDPS = "Schaden pro Sekunde", RANGEDDPS = "Distanzschaden pro Sekunde",
        HOLYRES = "Heiligwiderstand", FIRERES = "Feuerwiderstand", NATURERES = "Naturwiderstand",
        FROSTRES = "Frostwiderstand", SHADOWRES = "Schattenwiderstand", ARCANERES = "Arkanwiderstand",
    },
    en = {
        STAMINA = "Stamina", STRENGTH = "Strength", AGILITY = "Agility", INTELLECT = "Intellect",
        SPIRIT = "Spirit", MP5 = "Mana per 5 sec.", HP5 = "Health per 5 sec.", AP = "Attack Power",
        RAP = "Ranged Attack Power", SPELL = "Spell Power", HEAL = "Healing", HIT = "Hit",
        CRIT = "Critical Strike", SPELLHIT = "Spell Hit", SPELLCRIT = "Spell Critical Strike",
        DEFENSE = "Defense", ARMOR = "Armor",
        DODGE = "Dodge", PARRY = "Parry", BLOCK = "Block", BLOCKVALUE = "Block Value", HASTE = "Haste",
        EXPERTISE = "Expertise", ARMORPEN = "Armor Penetration", SPELLPEN = "Spell Penetration",
        MASTERY = "Mastery", VERSATILITY = "Versatility",
        MELEEDPS = "Damage per Second", RANGEDDPS = "Ranged Damage per Second",
        HOLYRES = "Holy Resistance", FIRERES = "Fire Resistance", NATURERES = "Nature Resistance",
        FROSTRES = "Frost Resistance", SHADOWRES = "Shadow Resistance", ARCANERES = "Arcane Resistance",
    },
}

--[[
    Wert → Klassen, für die er gut ist (Classic). Fehlt ein Wert (Ausdauer,
    Rüstung), ist er für alle gut. Später durch ein Werte-Gewichtungs-Modul
    ersetzbar: K.SetStatGoodFor(function(stat) return set_or_nil end).
]]
D.STAT_CLASSES = {
    STRENGTH = Set("WARRIOR", "PALADIN", "SHAMAN", "DRUID"),
    AGILITY = Set("ROGUE", "HUNTER", "DRUID", "WARRIOR"),
    INTELLECT = Set("MAGE", "PRIEST", "WARLOCK", "DRUID", "SHAMAN", "PALADIN"),
    SPIRIT = Set("PRIEST", "MAGE", "WARLOCK", "DRUID"),
    MP5 = Set("PRIEST", "PALADIN", "SHAMAN", "DRUID"),
    HP5 = Set("WARRIOR", "ROGUE", "DRUID", "PALADIN"),
    AP = Set("WARRIOR", "ROGUE", "HUNTER", "PALADIN", "SHAMAN", "DRUID"),
    RAP = Set("HUNTER"),
    SPELL = Set("MAGE", "WARLOCK", "PRIEST", "SHAMAN", "DRUID"),
    HEAL = Set("PRIEST", "PALADIN", "SHAMAN", "DRUID"),
    HIT = Set("WARRIOR", "ROGUE", "HUNTER", "PALADIN", "SHAMAN"),
    CRIT = Set("WARRIOR", "ROGUE", "HUNTER", "PALADIN", "SHAMAN", "DRUID"),
    SPELLHIT = Set("MAGE", "WARLOCK", "PRIEST", "SHAMAN", "DRUID"),
    SPELLCRIT = Set("MAGE", "WARLOCK", "PRIEST", "SHAMAN", "DRUID"),
    DEFENSE = Set("WARRIOR", "PALADIN", "DRUID"),
}

---------------------------------------------------------------------------
-- Ausrüstungsplätze
---------------------------------------------------------------------------

-- equipLoc → normalisierter Schlüssel (gleicher Platz = gleicher Schlüssel).
-- Eine Tabelle für alle Module: EquipSlots.lua (V-178); hier nur noch Verweise unter den alten Namen.
D.SLOT_KEYS = ezCore.EquipSlots.KEYS

-- Anzeige-Name: gleiche Plätze mit anderem equipLoc nehmen den Namen des Hauptplatzes.
D.SLOT_LABEL_FROM = ezCore.EquipSlots.LABEL_FROM

D.SLOT_ORDER = {
    "head", "neck", "shoulder", "back", "chest", "shirt", "tabard", "wrist", "hands", "waist", "legs", "feet",
    "finger", "trinket", "onehand", "mainhand", "twohand", "offhand", "shield", "holdable", "ranged", "relic",
    "ammo", "bag", "quiver",
}

D.NOT_EQUIPPABLE = ezCore.EquipSlots.NOT_EQUIPPABLE

---------------------------------------------------------------------------
-- Händlerwert: "hoch" ab diesen Kupferwerten (grau/weiß bzw. jede Qualität).
---------------------------------------------------------------------------

D.HIGH_VALUE_LOW_QUALITY = 10000   -- 1 Gold für graue und weiße Gegenstände
D.HIGH_VALUE_ANY = 50000           -- 5 Gold für alles andere

---------------------------------------------------------------------------
-- Suche (deutsche und englische Wörter, klein geschrieben)
---------------------------------------------------------------------------

-- Zahlenfelder: "lvl<20", "stufe>=30", "ilvl>50", "wert>1" (Gold).
D.SEARCH_NUMERIC = {
    lvl = "level", level = "level", stufe = "level", req = "level",
    ilvl = "ilvl", itemlevel = "ilvl", gs = "ilvl", gegenstandsstufe = "ilvl",
    skill = "skill", fertigkeit = "skill", rang = "skill",
    q = "quality", quality = "quality", ["qualität"] = "quality",
    wert = "value", value = "value", preis = "value", price = "value",
}

-- Textfelder: "beruf:schneiderei", "slot:hände", "für:magier", "tag:bufffood".
D.SEARCH_TEXT = {
    beruf = "profession", prof = "profession", profession = "profession",
    slot = "slot", platz = "slot",
    typ = "type", type = "type", art = "type",
    ["für"] = "class", fuer = "class", ["for"] = "class", klasse = "class", class = "class",
    tag = "tag", name = "name", mat = "mat", material = "mat",
}

-- "ab 25" / "bis 30"
D.SEARCH_RANGE = { ab = ">=", from = ">=", bis = "<=", to = "<=", upto = "<=" }

-- Einzelwörter mit fester Bedeutung → Tag.
D.SEARCH_KEYWORDS = {
    buff = "buff", bufffood = "bufffood", buffessen = "bufffood", ["buff-essen"] = "bufffood",
    essen = "food", food = "food", trinken = "drink", ["getränk"] = "drink", drink = "drink",
    rezept = "recipe", rezepte = "recipe", recipe = "recipe",
    quest = "quest", boe = "boe", bop = "bop", set = "special:set",
    einzigartig = "special:unique", unique = "special:unique",
    reagenz = "reagent", handwerkswaren = "reagent", handwerksware = "reagent", mats = "reagent", reagent = "reagent",
    nutzbar = "usable", usable = "usable", ["später"] = "later", later = "later",
    ["ausrüstung"] = "equip", equipment = "equip", verbrauchbar = "consumable", consumable = "consumable",
    trank = "potion", potion = "potion", elixier = "elixir", elixir = "elixir",
    verband = "bandage", bandage = "bandage", ["fläschchen"] = "flask", flask = "flask",
}
