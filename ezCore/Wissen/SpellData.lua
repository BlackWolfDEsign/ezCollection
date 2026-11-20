local _, ns = ...
local Core = ezCore

-- Daten des Zauber-Wissens (SSOT, vorher ezMacro/Data/Spells.lua und ezCombat/Spells.lua).
-- Spells.lua nutzt sie; die Module fragen nur ezCore.Spells.

Core.Spells = Core.Spells or {}
local Spells = Core.Spells

-- Ersatznamen { "Deutsch", "English" }. Zuerst fragt ezCore immer den Client (C_Spell.GetSpellName,
-- liefert die Client-Sprache); diese Namen springen nur ein, wenn der Client eine ID nicht kennt.
-- IDs sind die klassischen Rang-1-IDs. Quelle der Fakten ID und Name von 676, 5019, 5487, 9634 (MACRO-17, Vorlagen
-- von ezMacro): Wowheads Forever-Tooltip nether.wowhead.com/forever/tooltip/spell/<ID>, geprüft am 14.11.2026.
-- 50769 (Wiederbeleben, Druide) fehlt bewusst: der Forever-Tooltip kennt die ID nicht, und die Client-Tabelle SpellName
-- des Produkts „wowf“ (Build 1.60.1.70938, wago.tools, nachgesehen am 15.11.2026) hat keine Zeile – es gibt ihn auf Forever nicht.
-- Welle 8 (EC-110, ST-16, CB-34, Übergabe aus ezMacro): dazu die acht IDs, die ezHeal bisher selbst führte (2050, 1152,
-- 7328, 2008, 8946, 1008, 604, 5697; Namen wie vorher in ezHeal/Templates.lua T.EXTRA_NAMES), die Widerstands-Auren und die
-- Aura der Heiligkeit des Paladins (19876, 19888, 19891, 20218), Schattengestalt (15473), Arkaner Schuss (3044),
-- Blutsauger (689) und die fünf IDs aus ezMacros Ein-Klick-Taste (6201, 693, 1804, 13262, 6991). Quelle: klassische
-- Rang-1-IDs aus Blizzards Client der klassischen Fassung; ob Forever sie kennt, meldet /ez test (Spells.Exists).
-- Welle 27 (Paket modul/ezmacro-reste, 17.11.2026; Vorlagen von ezMacro aus modul/ezmacro-faehigkeiten): je Klasse unter
-- „Welle 27“ die 18 Grund-IDs der neuen Vorlagen (348, 702, 704, 1714, 440892, 18265, 603, 1120, 2944, 14914, 15407,
-- 8050, 1978, 1513, 772, 2878, 20066, 5570). Quelle von ID und Name: Client-Tabelle SpellName des Produkts „wowf“
-- (enUS und deDE, Build 1.60.1.70938, wago.tools, nachgesehen am 17.11.2026); Liste der IDs im Kopf von
-- ezMacro/Data/Classes.lua.
-- Gesamtreview 18.11.2026 (Paket kern/wago-pruefung, T14-NH9, NH1): Namen an die Client-Tabelle SpellName des Produkts
-- „wowf“ (Build 1.60.1.70938, wago.tools) angeglichen – 16166 „Lightning Mastery“/„Blitzbeherrschung“ (deutsch laut
-- tools/daten/wago/talente.lua, SpellName deDE), 980 „Bane of Agony“/„Omen der Pein“ (deutsch wie in der Erhebung
-- ezTalent/Tests/erhebung_70938.lua: „Verbessertes Omen der Pein“), 16979 „Feral Charge (Bear)“ (deutsch ungeprüft:
-- die deDE-Namen der Klassenzauber liegen nicht in tools/daten/wago/). Wilder Biss und Heiliger Schock unter der
-- Grund-ID (Rang 1) wie in CLASS und HEALS. Der Ersatzname für Heiliger Schock Rang 2 (20473) entfiel im Paket
-- kern/einheit-rest (Gesamtreview 18.11.2026, D3; Leitlinie 8): kein Aufrufer in Modulen, Tests und XML, seit
-- paladin_favorshock die Grund-ID 1311606 nennt; Ränge löst die Laufzeit über den Namen auf.
Spells.FALLBACK = {
    -- Krieger
    [71] = { "Verteidigungshaltung", "Defensive Stance" },
    [72] = { "Schildhieb", "Shield Bash" },
    [78] = { "Heldenhafter Stoß", "Heroic Strike" },
    [100] = { "Sturmangriff", "Charge" },
    [355] = { "Spott", "Taunt" },
    [694] = { "Spöttischer Schlag", "Mocking Blow" },
    [845] = { "Spalten", "Cleave" },
    [871] = { "Schildwall", "Shield Wall" },
    [1719] = { "Tollkühnheit", "Recklessness" },
    [2457] = { "Kampfhaltung", "Battle Stance" },
    [2458] = { "Berserkerhaltung", "Berserker Stance" },
    [2687] = { "Blutrausch", "Bloodrage" },
    [6552] = { "Zuschlagen", "Pummel" },
    [6673] = { "Schlachtruf", "Battle Shout" },
    [7384] = { "Überwältigen", "Overpower" },
    [12292] = { "Weitreichende Stöße", "Sweeping Strikes" },
    [12328] = { "Todeswunsch", "Death Wish" },
    [12975] = { "Letztes Gefecht", "Last Stand" },
    [18499] = { "Berserkerwut", "Berserker Rage" },
    [20252] = { "Abfangen", "Intercept" },
    [676] = { "Entwaffnen", "Disarm" },
    [772] = { "Verwunden", "Rend" },                              -- Welle 27

    -- Paladin
    [633] = { "Handauflegung", "Lay on Hands" },
    [635] = { "Heiliges Licht", "Holy Light" },
    [642] = { "Gottesschild", "Divine Shield" },
    [853] = { "Hammer der Gerechtigkeit", "Hammer of Justice" },
    [1022] = { "Segen des Schutzes", "Blessing of Protection" },
    [1044] = { "Segen der Freiheit", "Blessing of Freedom" },
    [4987] = { "Reinigung des Glaubens", "Cleanse" },
    [19740] = { "Segen der Macht", "Blessing of Might" },
    [19742] = { "Segen der Weisheit", "Blessing of Wisdom" },
    [19750] = { "Lichtblitz", "Flash of Light" },
    [20216] = { "Göttliche Gunst", "Divine Favor" },
    [20217] = { "Segen der Könige", "Blessing of Kings" },
    [20271] = { "Richturteil", "Judgement" },
    [1311606] = { "Heiliger Schock", "Holy Shock" },          -- Grund-ID (Rang 1, Talent), HEALS
    [21084] = { "Siegel der Rechtschaffenheit", "Seal of Righteousness" },
    [1152] = { "Läutern", "Purify" },
    [7328] = { "Erlösung", "Redemption" },
    [19876] = { "Aura des Schattenwiderstands", "Shadow Resistance Aura" },
    [19888] = { "Aura des Frostwiderstands", "Frost Resistance Aura" },
    [19891] = { "Aura des Feuerwiderstands", "Fire Resistance Aura" },
    [20218] = { "Aura der Heiligkeit", "Sanctity Aura" },
    [2878] = { "Untote vertreiben", "Turn Undead" },              -- Welle 27
    [20066] = { "Buße", "Repentance" },                           -- Welle 27

    -- Jäger
    [75] = { "Automatischer Schuss", "Auto Shot" },
    [136] = { "Tier heilen", "Mend Pet" },
    [883] = { "Tier rufen", "Call Pet" },
    [982] = { "Tier wiederbeleben", "Revive Pet" },
    [1130] = { "Mal des Jägers", "Hunter's Mark" },
    [1495] = { "Mungobiss", "Mongoose Bite" },
    [1499] = { "Eiskältefalle", "Freezing Trap" },
    [2649] = { "Knurren", "Growl" },
    [2973] = { "Raptorstoß", "Raptor Strike" },
    [3045] = { "Schnellfeuer", "Rapid Fire" },
    [5118] = { "Aspekt des Geparden", "Aspect of the Cheetah" },
    [5384] = { "Totstellen", "Feign Death" },
    [13163] = { "Aspekt des Affen", "Aspect of the Monkey" },
    [13165] = { "Aspekt des Falken", "Aspect of the Hawk" },
    [19503] = { "Streuschuss", "Scatter Shot" },
    [19574] = { "Zorn des Wildtiers", "Bestial Wrath" },
    [19801] = { "Einlullender Schuss", "Tranquilizing Shot" },
    [3044] = { "Arkaner Schuss", "Arcane Shot" },
    [6991] = { "Tier füttern", "Feed Pet" },
    [1978] = { "Schlangenbiss", "Serpent Sting" },                -- Welle 27
    [1513] = { "Wildtier ängstigen", "Scare Beast" },             -- Welle 27

    -- Schurke
    [921] = { "Taschendiebstahl", "Pick Pocket" },
    [1725] = { "Ablenken", "Distract" },
    [1752] = { "Finsterer Stoß", "Sinister Strike" },
    [1766] = { "Tritt", "Kick" },
    [1776] = { "Solarplexus", "Gouge" },
    [1784] = { "Verstohlenheit", "Stealth" },
    [1833] = { "Fieser Trick", "Cheap Shot" },
    [1856] = { "Verschwinden", "Vanish" },
    [2094] = { "Blenden", "Blind" },
    [2098] = { "Ausweiden", "Eviscerate" },
    [6770] = { "Kopfnuss", "Sap" },
    [8676] = { "Hinterhalt", "Ambush" },
    [13750] = { "Adrenalinrausch", "Adrenaline Rush" },
    [13877] = { "Klingenwirbel", "Blade Flurry" },
    [14177] = { "Kaltblütigkeit", "Cold Blood" },
    [1804] = { "Schlossknacken", "Pick Lock" },

    -- Priester
    [17] = { "Machtwort: Schild", "Power Word: Shield" },
    [139] = { "Erneuerung", "Renew" },
    [527] = { "Magiebannung", "Dispel Magic" },
    [528] = { "Krankheit heilen", "Cure Disease" },
    [552] = { "Krankheit aufheben", "Abolish Disease" },
    [589] = { "Schattenwort: Schmerz", "Shadow Word: Pain" },
    [596] = { "Gebet der Heilung", "Prayer of Healing" },
    [2006] = { "Auferstehung", "Resurrection" },
    [2054] = { "Heilen", "Heal" },
    [2060] = { "Großes Heilen", "Greater Heal" },
    [2061] = { "Blitzheilung", "Flash Heal" },
    [6346] = { "Furchtzauberschutz", "Fear Ward" },
    [8092] = { "Gedankenschlag", "Mind Blast" },
    [8122] = { "Psychischer Schrei", "Psychic Scream" },
    [9484] = { "Untote fesseln", "Shackle Undead" },
    [13908] = { "Verzweifeltes Gebet", "Desperate Prayer" },
    [14751] = { "Innerer Fokus", "Inner Focus" },
    [2050] = { "Geringes Heilen", "Lesser Heal" },
    [15473] = { "Schattengestalt", "Shadowform" },
    [2944] = { "Verschlingende Seuche", "Devouring Plague" },     -- Welle 27
    [14914] = { "Heiliges Feuer", "Holy Fire" },                  -- Welle 27
    [15407] = { "Gedankenschinden", "Mind Flay" },                -- Welle 27

    -- Schamane
    [331] = { "Welle der Heilung", "Healing Wave" },
    [370] = { "Reinigen", "Purge" },
    [421] = { "Kettenblitzschlag", "Chain Lightning" },
    [526] = { "Vergiftung heilen", "Cure Poison" },
    [1064] = { "Kettenheilung", "Chain Heal" },
    [2645] = { "Geisterwolf", "Ghost Wolf" },
    [2870] = { "Krankheit heilen", "Cure Disease" },
    [3599] = { "Totem der Verbrennung", "Searing Totem" },
    [5394] = { "Totem des heilenden Flusses", "Healing Stream Totem" },
    [8004] = { "Geringe Welle der Heilung", "Lesser Healing Wave" },
    [8042] = { "Erdschock", "Earth Shock" },
    [8075] = { "Totem der Erdstärke", "Strength of Earth Totem" },
    [8512] = { "Totem des Windzorns", "Windfury Totem" },
    [16166] = { "Blitzbeherrschung", "Lightning Mastery" },   -- Name laut Client (T14-NH9)
    [16188] = { "Schnelligkeit der Natur", "Nature's Swiftness" },
    [2008] = { "Geist der Ahnen", "Ancestral Spirit" },
    [8050] = { "Flammenschock", "Flame Shock" },                  -- Welle 27

    -- Magier
    [10] = { "Blizzard", "Blizzard" },
    [118] = { "Verwandlung", "Polymorph" },
    [130] = { "Langsamer Fall", "Slow Fall" },
    [133] = { "Feuerball", "Fireball" },
    [475] = { "Geringen Fluch aufheben", "Remove Lesser Curse" },
    [587] = { "Essen herbeizaubern", "Conjure Food" },
    [1459] = { "Arkane Intelligenz", "Arcane Intellect" },
    [2120] = { "Flammenstoß", "Flamestrike" },
    [2139] = { "Gegenzauber", "Counterspell" },
    [5504] = { "Wasser herbeizaubern", "Conjure Water" },
    [11129] = { "Verbrennen", "Combustion" },
    [11366] = { "Pyroschlag", "Pyroblast" },
    [11958] = { "Eisblock", "Ice Block" },
    [12042] = { "Arkane Macht", "Arcane Power" },
    [12043] = { "Geistesgegenwart", "Presence of Mind" },
    [23028] = { "Arkane Brillanz", "Arcane Brilliance" },
    [1008] = { "Magie verstärken", "Amplify Magic" },
    [604] = { "Magie dämpfen", "Dampen Magic" },

    -- Hexenmeister
    [172] = { "Verderbnis", "Corruption" },
    [686] = { "Schattenblitz", "Shadow Bolt" },
    [688] = { "Wichtel beschwören", "Summon Imp" },
    [691] = { "Teufelsjäger beschwören", "Summon Felhunter" },
    [697] = { "Leerwandler beschwören", "Summon Voidwalker" },
    [710] = { "Verbannen", "Banish" },
    [712] = { "Sukkubus beschwören", "Summon Succubus" },
    [980] = { "Omen der Pein", "Bane of Agony" },              -- Name laut Client (T14-NH9)
    [5782] = { "Furcht", "Fear" },
    [6358] = { "Verführung", "Seduction" },
    [6789] = { "Todesmantel", "Death Coil" },
    [18223] = { "Fluch der Erschöpfung", "Curse of Exhaustion" },
    [18288] = { "Fluch verstärken", "Amplify Curse" },
    [18708] = { "Teufelsbeherrschung", "Fel Domination" },
    [19244] = { "Zaubersperre", "Spell Lock" },
    [5697] = { "Unendlicher Atem", "Unending Breath" },
    [689] = { "Blutsauger", "Drain Life" },
    [6201] = { "Gesundheitsstein herstellen", "Create Healthstone" },
    [693] = { "Seelenstein herstellen", "Create Soulstone" },
    [348] = { "Feuerbrand", "Immolate" },                         -- Welle 27
    [702] = { "Fluch der Schwäche", "Curse of Weakness" },        -- Welle 27
    [704] = { "Fluch der Tollkühnheit", "Curse of Recklessness" }, -- Welle 27
    [1714] = { "Fluch der Sprachen", "Curse of Tongues" },        -- Welle 27
    [440892] = { "Fluch der Elemente", "Curse of the Elements" }, -- Welle 27
    [18265] = { "Lebensentzug", "Siphon Life" },                  -- Welle 27
    [603] = { "Omen der Verdammnis", "Bane of Doom" },            -- Welle 27
    [1120] = { "Seelendieb", "Drain Soul" },                      -- Welle 27

    -- Druide
    [339] = { "Wucherwurzeln", "Entangling Roots" },
    [768] = { "Katzengestalt", "Cat Form" },
    [774] = { "Verjüngung", "Rejuvenation" },
    [783] = { "Reisegestalt", "Travel Form" },
    [1066] = { "Wassergestalt", "Aquatic Form" },
    [2637] = { "Winterschlaf", "Hibernate" },
    [2782] = { "Fluch aufheben", "Remove Curse" },
    [2893] = { "Vergiftung aufheben", "Abolish Poison" },
    [5185] = { "Heilende Berührung", "Healing Touch" },
    [5215] = { "Schleichen", "Prowl" },
    [6795] = { "Knurren", "Growl" },
    [8921] = { "Mondfeuer", "Moonfire" },
    [8936] = { "Nachwachsen", "Regrowth" },
    [9005] = { "Anspringen", "Pounce" },
    [17116] = { "Schnelligkeit der Natur", "Nature's Swiftness" },
    [20484] = { "Wiedergeburt", "Rebirth" },
    [29166] = { "Anregen", "Innervate" },
    [5487] = { "Bärengestalt", "Bear Form" },
    [9634] = { "Terrorbärengestalt", "Dire Bear Form" },
    [8946] = { "Vergiftung heilen", "Cure Poison" },
    [5570] = { "Insektenschwarm", "Insect Swarm" },               -- Welle 27

    -- Zauberstab (Priester, Magier, Hexenmeister)
    [5019] = { "Schießen", "Shoot" },

    -- Berufe (ezMacro, Ein-Klick-Taste „Entzaubern“; die Art steht in SalvageData.lua)
    [13262] = { "Entzaubern", "Disenchant" },

    -- Völker
    [2481] = { "Schatzsuche", "Find Treasure" },
    [7744] = { "Wille der Verlassenen", "Will of the Forsaken" },
    [20549] = { "Kriegsdonner", "War Stomp" },
    [20554] = { "Berserker", "Berserking" },
    [20572] = { "Kochendes Blut", "Blood Fury" },
    [20577] = { "Kannibalismus", "Cannibalize" },
    [20580] = { "Schattenmimik", "Shadowmeld" },
    [20589] = { "Entfesselungskünstler", "Escape Artist" },
    [20594] = { "Steingestalt", "Stoneform" },
    [20600] = { "Wahrnehmung", "Perception" },

    -- aus ezCombat
    [6572] = { "Rache", "Revenge" },
    [5308] = { "Hinrichten", "Execute" },
    [14251] = { "Riposte", "Riposte" },
    [19306] = { "Gegenangriff", "Counterattack" },
    [24275] = { "Hammer des Zorns", "Hammer of Wrath" },
    [15487] = { "Stille", "Silence" },
    [1328618] = { "Wilder Biss", "Ferocious Bite" },           -- Grund-ID (Rang 1; vorher 22568, Rang 2)
    [1079] = { "Zerfetzen", "Rip" },
    [16979] = { "Wilde Attacke", "Feral Charge (Bear)" },     -- englisch laut Client (T14-NH9)
    [6807] = { "Zermalmen", "Maul" },
    -- Buffs (Spells.BUFFS): Rang 1 und Gruppenfassungen
    [168] = { "Frostrüstung", "Frost Armor" },
    [7302] = { "Eisrüstung", "Ice Armor" },
    [6117] = { "Magische Rüstung", "Mage Armor" },
    [1243] = { "Machtwort: Seelenstärke", "Power Word: Fortitude" },
    [21562] = { "Gebet der Seelenstärke", "Prayer of Fortitude" },
    [14752] = { "Göttlicher Willen", "Divine Spirit" },
    [27681] = { "Gebet der Willenskraft", "Prayer of Spirit" },
    [976] = { "Schattenschutz", "Shadow Protection" },
    [27683] = { "Gebet des Schattenschutzes", "Prayer of Shadow Protection" },
    [588] = { "Inneres Feuer", "Inner Fire" },
    [1126] = { "Mal der Wildnis", "Mark of the Wild" },
    [21849] = { "Gabe der Wildnis", "Gift of the Wild" },
    [467] = { "Dornen", "Thorns" },
    [1038] = { "Segen der Rettung", "Blessing of Salvation" },
    [19977] = { "Segen des Lichts", "Blessing of Light" },
    [20911] = { "Segen des Refugiums", "Blessing of Sanctuary" },
    [25782] = { "Großer Segen der Macht", "Greater Blessing of Might" },
    [25894] = { "Großer Segen der Weisheit", "Greater Blessing of Wisdom" },
    [25898] = { "Großer Segen der Könige", "Greater Blessing of Kings" },
    [25895] = { "Großer Segen der Rettung", "Greater Blessing of Salvation" },
    [25890] = { "Großer Segen des Lichts", "Greater Blessing of Light" },
    [25899] = { "Großer Segen des Refugiums", "Greater Blessing of Sanctuary" },
    [687] = { "Dämonenhaut", "Demon Skin" },
    [706] = { "Dämonenrüstung", "Demon Armor" },
    [324] = { "Blitzschlagschild", "Lightning Shield" },
    [408510] = { "Wasserschild", "Water Shield" },
    [19705] = { "Satt", "Well Fed" },
    [7353] = { "Behagliches Feuer", "Cozy Fire" },
    [818] = { "Einfaches Lagerfeuer", "Basic Campfire" },
    -- Waffenzauber des Schamanen (Spells.WEAPON_IMBUES, Welle 23): Rang 1
    [8017] = { "Waffe des Felsbeißers", "Rockbiter Weapon" },
    [8024] = { "Waffe der Flammenzunge", "Flametongue Weapon" },
    [8033] = { "Waffe des Frostbrands", "Frostbrand Weapon" },
    [8232] = { "Waffe des Windzorns", "Windfury Weapon" },
}

-- Was jede Klasse wofür hat (vorher ezCombat).
--   reactive   nur nach einem Ereignis nutzbar (Ausweichen, Parieren, Blocken) oder unter 20 % Leben
--   interrupt  unterbricht einen Zauber des Ziels
--   finisher   lohnt sich bei vollen Combo-Punkten
--   nextSwing  wird mit dem nächsten Nahkampfschlag ausgeführt (Schlagtimer)
Spells.CLASS = {
    WARRIOR = { reactive = { 7384, 6572, 5308 }, interrupt = { 6552, 72 }, nextSwing = { 78, 845 } },
    ROGUE = { reactive = { 14251 }, interrupt = { 1766 }, finisher = { 2098 } },
    HUNTER = { reactive = { 19306, 1495 }, nextSwing = { 2973 } },
    PALADIN = { reactive = { 24275 } },
    SHAMAN = { interrupt = { 8042 } },
    MAGE = { interrupt = { 2139 } },
    PRIEST = { interrupt = { 15487 } },
    DRUID = { interrupt = { 16979 }, finisher = { 1328618, 1079 }, nextSwing = { 6807 } },
    WARLOCK = {},
}

-- Nur unter 20 % Leben des Ziels nutzbar.
Spells.EXECUTE = { [5308] = true, [24275] = true }
Spells.EXECUTE_HEALTH = 0.2

Spells.AUTO_SHOT = 75

-- Zauber eines Berufs aus der EINEN Liste (KnowledgeData.lua, PROFESSIONS – dort stehen Kennung, Zauber und
-- Ersatznamen): Spells.ProfessionSpell("fishing") → 7620; nil für einen unbekannten Beruf oder einen ohne Zauber.
-- Spells.FISHING ist „Angeln“ (vorher als Zahl in ezMacro/Fishing.lua und ezGear/Swap.lua; MACRO-18, UE-12).
function Spells.ProfessionSpell(key)
    local data = ns.KnowledgeData
    for _, entry in ipairs(type(data) == "table" and data.PROFESSIONS or {}) do
        if entry.key == key then return entry.spell end
    end
    return nil
end
Spells.FISHING = Spells.ProfessionSpell("fishing")

-- Berufe mit Abklingzeit (Professions.lua). Neue Forever-Rezepte liest ezCore aus dem offenen Berufefenster.
-- Wert = Gruppe (Zauber mit geteilter Abklingzeit) oder true (eigene Abklingzeit, keine Gruppe). Laut Client-Tabellen
-- (wago.tools, wowf 1.60.1.70938; SpellCategories, SpellCooldowns) teilen Arkanit, die Elemente und Elementarfeuer die
-- Kategorie 310 „Transmute - Alchemy“ (die Kategorie-Abklingzeit setzt der gewirkte Zauber: Arkanit 47 h, Elemente
-- 23 h, Elementarfeuer 10 min); Eisen zu Gold und Mithril zu Echtsilber stehen in keiner Kategorie und haben je 1 h
-- eigene Abklingzeit (Gesamtreview 18.11.2026, T14-NH2 – vorher fälschlich in der Gruppe). Die wago-Prüfung
-- (tools/wago_pruefung.lua, Art „gruppe“) gleicht jede Gruppe mit den Kategorien des Clients ab.
Spells.PROF_COOLDOWNS = {
    [11479] = true, [11480] = true,                                                       -- Eisen zu Gold, Mithril zu Echtsilber
    [17187] = "transmute",                                                                -- Arkanit
    [17559] = "transmute", [17560] = "transmute", [17561] = "transmute", [17562] = "transmute",   -- Elemente
    [17563] = "transmute", [17564] = "transmute", [17565] = "transmute", [17566] = "transmute",
    [25146] = "transmute",                                                                -- Elementarfeuer
    [18560] = "mooncloth",                                                                -- Mondstoff
}
-- Gegenstände mit Berufs-Abklingzeit (Salzstreuer: Gereiftes Salz).
Spells.PROF_COOLDOWN_ITEMS = { [15846] = "salt" }

-- Hergestellte Gegenstände der Klassen (Gesamtreview 18.11.2026, T16-9; vorher in ezMacro/OneKey.lua und sechsmal je
-- Rotation in ezCombat/RotationData/WARLOCK.lua, mit widersprüchlicher Herkunftsangabe). Je Art: Klasse, Zauber,
-- braucht einen Seelensplitter (shard), Gegenstände vom schwächsten zum besten Rang (ezMacro benutzt den besten, den
-- die Tasche hat). Prüfstand: jede ID gleicht die wago-Prüfung in sh tools/test.sh mit den Client-Tabellen ab (Item,
-- ItemSparse; wago.tools, Produkt „wowf“, Build 1.60.1.70938 – tools/wago_pruefung.lua, M.ITEM_SOURCES); Namen und
-- Ränge dazu am 15.11.2026 an Wowheads Forever-Tooltip (nether.wowhead.com/forever/tooltip/item/<ID>) nachgesehen:
--   5504 Wasser herbeizaubern » 5350, 2288, 2136, 3772, 8077, 8078, 8079 (Herbeigezaubertes, frisches, gereinigtes,
--        Quell-, Mineral-, Sprudel-, Kristallwasser)
--   587  Essen herbeizaubern » 5349, 1113, 1114, 1487, 8075, 8076, 22895 (Muffin bis Zimtschnecke)
--   6201 Gesundheitsstein herstellen » schwach bis erheblich (5512, 5511, 5509, 5510, 9421), je zwei verbesserte
--        Fassungen 19004–19013
--   693  Seelenstein herstellen » 5232, 16892, 16893, 16895, 16896
-- Spells.SOUL_SHARD: der Seelensplitter (6265), den Gesundheits- und Seelenstein verbrauchen.
Spells.CONJURED = {
    conjureWater = { class = "MAGE", spell = 5504, items = { 5350, 2288, 2136, 3772, 8077, 8078, 8079 } },
    conjureFood = { class = "MAGE", spell = 587, items = { 5349, 1113, 1114, 1487, 8075, 8076, 22895 } },
    healthstone = { class = "WARLOCK", spell = 6201, shard = true,
        items = { 5512, 19004, 19005, 5511, 19006, 19007, 5509, 19008, 19009, 5510, 19010, 19011, 9421, 19012, 19013 } },
    soulstone = { class = "WARLOCK", spell = 693, shard = true, items = { 5232, 16892, 16893, 16895, 16896 } },
}
Spells.SOUL_SHARD = 6265

-- Buff-Gruppen (ezBuff; Buff-Funktionen in Spells.lua). Je Gruppe die Ränge mit der Stufe, ab der man sie lernt.
--   class    Klasse, die den Buff gibt (fehlt bei Essen und Lagerfeuer)
--   target   "any" = auf andere wirkbar, "self" = nur auf sich (Rüstungen, Schilde, Rufe)
--   kind     Gruppen mit gleichem kind schließen sich aus (eine Rüstung, ein Segen je Paladin)
--   spells   Rang-IDs (klassisch), levels dieselbe Reihenfolge
--   group    Gruppenfassungen (Arkane Brillanz, Gebete, Gaben, Große Segen): zählen als derselbe Buff, werden aber nicht vorgeschlagen
--   cast     Zauber, der den Buff erzeugt (Lagerfeuer), reagent der verbrauchte Gegenstand
--   replaces Buff derselben Klasse und desselben kind, den dieser ablöst, sobald er gelernt ist (Spells.ChooseBuff)
--   keepChoice true: die Ablösung (replaces) gilt nur ohne gemerkte Wahl – wer den abgelösten Buff selbst wirkt,
--            behält ihn (Wasserschild/Blitzschlagschild; Entscheidung des Nutzers vom 13.11.2026: „Gemerkte Wahl gewinnt“)
--   missing  "forever": kein Zauber der Gruppe steht im Forever-Client (Welle 23, A72; Belege am Eintrag). Nur ein
--            Kennzeichen – die Daten bleiben, Spells.ClassBuffs reicht es weiter, und kennt der Client einen der Zauber
--            (Spells.Exists, etwa nach einem Patch), gilt der Buff wieder (Spells.BuffMissing → false).
--   manual   true: nur als gemerkte Wahl, nie automatisch vorgeschlagen (Segen der Weisheit, Rettung, Licht, Refugium –
--            welcher davon passt, hängt am Ziel). Ohne Wahl gilt so der letzte gelernte übrige Segen: Macht bis
--            Stufe 20, ab Segen der Könige dieser (Entscheidung des Nutzers vom 13.11.2026, „Alle nach Empfehlung“).
--   fallback { minutes = n[, groupMinutes = m] }: Dauer NUR als Rückfall (groupMinutes: eigene Dauer der Gruppenfassungen,
--            Gesamtreview 18.11.2026, T14-NH8; permanent = true statt minutes: hält ohne Dauer, T14-2). Zuerst zählt die Dauer der laufenden Aura, die der Client
--            liefert (Spells.NoteAura → Spells.BuffMinutes). Einzige Stelle für feste Dauern. Kennzeichen je Zeile:
--            [B] = belegt für Forever (Zauber-Tooltip einer Forever-Datenbank mit ID, oder im Spiel gelesen),
--            [V] = vermutet (Tooltip der klassischen Fassung oder abgeleitet; für Forever im Spiel zu prüfen).
--            [B] wago = belegt aus den Client-Tabellen des Produkts „wowf“ (Build 1.60.1.70938) auf wago.tools,
--            nachgesehen von der Hauptsession am 15.11.2026 (SpellMisc.DurationIndex » SpellDuration); Zeilen mit
--            Adresse in tools/gegenpruefung_liste.txt.
--   groupLevels  Lernstufe der Gruppenfassungen, dieselbe Reihenfolge wie group – [B] wago: SpellLevels.BaseLevel
--            (= SpellLevel) je Kennung, nachgesehen am 15.11.2026 (tools/gegenpruefung_liste.txt). Die Stufen in
--            levels wurden dort ebenso abgeglichen: 1459 (1), 6673 (1), 324 (8), 706 (20), 7302 (30), 6117 (34)
--            stimmen. Zur Laufzeit gilt zuerst der Client (Spells.LevelLearned); groupLevels ist nur Rückfall.
-- Quellen der Dauern und Forever-IDs, abgerufen am 13.11.2026: Zauber-Tooltips unter
-- nether.wowhead.com/forever/tooltip/spell/<ID> und db.icy-veins.com/wow-forever/spells/<ID>, dazu die Klassen-Guides
-- für Forever unter icy-veins.com/wow-forever und wowhead.com/forever/guide/classes. Nichts stammt aus einem Addon.
-- Klassische IDs; ein Ziel nimmt einen Rang an, wenn seine Stufe mindestens Rangstufe − 10 ist.
Spells.BUFFS = {
    int = { class = "MAGE", target = "any", spells = { 1459, 1460, 1461, 10156, 10157 }, levels = { 1, 14, 28, 42, 56 },
        group = { 23028 }, groupLevels = { 56 },
        fallback = { minutes = 60 } },   -- [B] wago: 1459 und 23028 DurationIndex 42 = 3600000 ms (vorher 30 Min., [V] klassisch)
    frostArmor = { class = "MAGE", target = "self", kind = "armor", spells = { 168, 7300, 7301 }, levels = { 1, 10, 20 },
        fallback = { minutes = 30 } },                                                       -- [V] Tooltip klassisch
    iceArmor = { class = "MAGE", target = "self", kind = "armor", spells = { 7302, 7320, 10219, 10220 }, levels = { 30, 40, 50, 60 },
        replaces = "frostArmor", fallback = { minutes = 30 } },                              -- [V] Tooltip klassisch
    mageArmor = { class = "MAGE", target = "self", kind = "armor", spells = { 6117, 22782, 22783 }, levels = { 34, 46, 58 },
        fallback = { minutes = 30 } },                                                       -- [V] Tooltip klassisch
    fort = { class = "PRIEST", target = "any", spells = { 1243, 1244, 1245, 2791, 10937, 10938 }, levels = { 1, 12, 24, 36, 48, 60 },
        group = { 21562, 21564 }, groupLevels = { 48, 60 }, fallback = { minutes = 60 } },  -- [B] Forever-Tooltip 1243
    spirit = { class = "PRIEST", target = "any", spells = { 14752, 14818, 14819, 27841 }, levels = { 30, 40, 50, 60 }, group = { 27681 },
        groupLevels = { 60 }, fallback = { minutes = 60 } },                                                       -- [B] Forever-Tooltip 14752
    shadowProt = { class = "PRIEST", target = "any", spells = { 976, 10957, 10958 }, levels = { 30, 42, 56 }, group = { 27683 },
        groupLevels = { 56 }, fallback = { minutes = 10, groupMinutes = 20 } },  -- [B] wago: 976 600000 ms, 27683 1200000 ms
    innerFire = { class = "PRIEST", target = "self", spells = { 588, 7128, 602, 1006, 10951, 10952 }, levels = { 12, 20, 30, 40, 50, 60 },
        fallback = { minutes = 10 } },                                                       -- [B] Forever-Tooltip 588
    motw = { class = "DRUID", target = "any", spells = { 1126, 5232, 6756, 5234, 8907, 9884, 9885 }, levels = { 1, 10, 20, 30, 40, 50, 60 },
        group = { 21849, 21850 }, groupLevels = { 50, 60 }, fallback = { minutes = 60 } },  -- [B] Forever-Tooltip 1126
    thorns = { class = "DRUID", target = "any", spells = { 467, 782, 1075, 8914, 9756, 9910 }, levels = { 6, 14, 24, 34, 44, 54 },
        fallback = { minutes = 10 } },                                                       -- [B] Forever-Tooltip 467
    might = { class = "PALADIN", target = "any", kind = "blessing", spells = { 19740, 19834, 19835, 19836, 19837, 19838, 25291 },
        levels = { 4, 12, 22, 32, 42, 52, 60 }, group = { 25782, 25916 }, groupLevels = { 52, 60 },
        fallback = { minutes = 60 } },   -- [B] Forever-Tooltip 19740
    wisdom = { class = "PALADIN", target = "any", kind = "blessing", spells = { 19742, 19850, 19852, 19853, 19854, 25290 },
        levels = { 14, 24, 34, 44, 54, 60 }, group = { 25894, 25918 }, groupLevels = { 54, 60 },
        manual = true, fallback = { minutes = 60 } },      -- [B] Forever-Tooltip 19742
    kings = { class = "PALADIN", target = "any", kind = "blessing", spells = { 20217 }, levels = { 20 }, group = { 25898 },
        groupLevels = { 60 }, fallback = { minutes = 60 } },                                                       -- [B] Forever-Tooltip 20217
    -- Rettung, Licht und Refugium: fehlen im Forever-Client laut Selbsttest des Nutzers vom 15.11.2026 (/ez test,
    -- Client 1.60.1 (70938), deDE: 1038, 25895, 19977–19979, 25890, 20911–20914, 25899 „fehlt (Rückfall vorhanden)“);
    -- dazu kennt Wowhead Forever 1038, 19977 und 20911 nicht (wowhead.com/forever/spell=<ID>: 404, abgerufen 15.11.2026).
    -- Bestätigt durch die Client-Tabelle SpellName des Produkts „wowf“ (Build 1.60.1.70938, wago.tools, nachgesehen am
    -- 15.11.2026): 1038, 19977, 20911 und 25895 haben dort keine Zeile (tools/gegenpruefung_liste.txt).
    -- Die Einträge bleiben (Leitlinie 8) und tragen das Kennzeichen missing = "forever" (Welle 23, A72); ezBuff
    -- erwartet einen Buff nur, wenn der Client einen seiner Zauber kennt (ezBuff/Buffs.lua, Buffs.InClient; in ezCore
    -- Spells.BuffMissing) – kommt einer mit einem Patch dazu, gilt er von selbst wieder.
    salvation = { class = "PALADIN", target = "any", kind = "blessing", spells = { 1038 }, levels = { 26 }, group = { 25895 },
        manual = true, missing = "forever", fallback = { minutes = 60 } },   -- [V] wie die anderen Segen; fehlt im Forever-Client
    light = { class = "PALADIN", target = "any", kind = "blessing", spells = { 19977, 19978, 19979 }, levels = { 40, 50, 60 }, group = { 25890 },
        manual = true, missing = "forever", fallback = { minutes = 60 } },   -- [V] wie die anderen Segen; fehlt im Forever-Client
    sanctuary = { class = "PALADIN", target = "any", kind = "blessing", spells = { 20911, 20912, 20913, 20914 }, levels = { 30, 40, 50, 60 },
        group = { 25899 }, manual = true, missing = "forever", fallback = { minutes = 60 } },  -- [V] wie oben; fehlt im Forever-Client
    battleShout = { class = "WARRIOR", target = "self", spells = { 6673, 5242, 6192, 11549, 11550, 11551, 25289 },
        levels = { 1, 12, 22, 32, 42, 52, 60 },
        fallback = { minutes = 3 } },    -- [B] wago: 6673 DurationIndex 25 = 180000 ms (vorher 2 Min., [V] klassisch)
    demonSkin = { class = "WARLOCK", target = "self", kind = "armor", spells = { 687, 696 }, levels = { 1, 10 },
        fallback = { minutes = 30 } },                                 -- [B] im Spiel gelesen: Rang 2 läuft 1800 s
    demonArmor = { class = "WARLOCK", target = "self", kind = "armor", spells = { 706, 1086, 11733, 11734, 11735 }, levels = { 20, 30, 40, 50, 60 },
        replaces = "demonSkin", fallback = { minutes = 30 } },                               -- [V] Tooltip klassisch
    lightningShield = { class = "SHAMAN", target = "self", kind = "shield", spells = { 324, 325, 905, 945, 8134, 10431, 10432 },
        levels = { 8, 16, 24, 32, 40, 48, 56 }, fallback = { minutes = 10 } },               -- [V] Tooltip klassisch
    -- Wasserschild (Forever, ab Stufe 20) löst das Blitzschlagschild ab; ID und Dauer 10 min laut Forever-Tooltip
    waterShield = { class = "SHAMAN", target = "self", kind = "shield", spells = { 408510 }, levels = { 20 },
        replaces = "lightningShield", keepChoice = true, fallback = { minutes = 10 } },      -- [B] Forever-Tooltip 408510
    -- Essen: „Satt“ hat viele IDs; ezCore erkennt die Aura auch über den Namen
    -- EINE Liste (V-030): KnowledgeData.WELL_FED_SPELLS (lädt vorher) – dieselbe Tabelle fürs Item-Wissen und für ezBuff.
    wellFed = { spells = (ns.KnowledgeData and ns.KnowledgeData.WELL_FED_SPELLS) or {} },
    cozyFire = { spells = { 7353 }, cast = 818, reagent = 4470 },
    -- Gesamtreview 18.11.2026 (Paket kern/wago-pruefung, T14-2): lange Selbst-Buffs, die ezCombat als „longbuff“ führt.
    -- Sie stehen NICHT in BUFF_ORDER (der Reihe der Klassen-Buffs für andere): ezBuff mahnt sie seit der Entscheidung des
    -- Nutzers vom 19.11.2026 („Ja, anmahnen (Empfohlen)“) über seine eigene Reihe der Selbst-Buffs an (ezBuff/Buffs.lua,
    -- Buffs.LONG_SELF); hier liegt das Wissen für Spells.BuffKey, AuraIDs und die Dauer (ezBuff, ezCombat, Anzeigen).
    -- Stufen [B] wago laut ClassSpells bzw. SpellLevels, Dauern laut SpellDuration (wowf 1.60.1.70938).
    righteousFury = { class = "PALADIN", target = "self", spells = { 25780 }, levels = { 10 },
        fallback = { minutes = 30 } },                                 -- [B] wago: 25780 SpellDuration 1800000 ms
    trueshotAura = { class = "HUNTER", target = "self", spells = { 1299346, 1299348, 19506, 20905, 20906 },
        levels = { 25, 32, 40, 50, 60 }, fallback = { minutes = 30 } },  -- [B] wago: 1800000 ms; Rang 1 ist das Talent
    -- Seelenverbindung (Talent, nur mit Begleiter): SpellDuration nennt keine Dauer – sie hält, solange der Begleiter lebt
    soulLink = { class = "WARLOCK", target = "self", spells = { 19028 }, fallback = { permanent = true } },   -- [B] wago
}
-- Reagenzien der Gruppenfassungen (Zauber-ID der Gruppenfassung → Gegenstand, den sie verbraucht), für ezBuff und den
-- Hinweis „Reagenz fehlt“: Arkanes Pulver 17020, Heilige Kerze 17028, Hochheilige Kerze 17029, Wilde Beeren 17021,
-- Wilder Dornwurz 17026, Symbol der Könige 21177. [B] laut Client-Tabellen (wago.tools, wowf 1.60.1.70938;
-- SpellReagents): jede Gruppenfassung, die der Client kennt, verbraucht genau diesen Gegenstand (ausgeliefert in
-- Wissen/Client/Reagents.lua). Zur Laufzeit gilt zuerst die Client-Tabelle (Spells.ReagentNeeds über Spells.Reagents, schon vor T14-NH6);
-- diese Liste ist der Rückfall ohne Tabelle und für die Großen Segen der Rettung, des Lichts und des Refugiums (25895,
-- 25890, 25899 – fehlen auf Forever, bleiben für Clients, die sie haben). Die wago-Prüfung gleicht jede Zeile mit
-- SpellReagents ab (Gesamtreview 18.11.2026, T14-NH6).
Spells.GROUP_REAGENTS = {
    [23028] = 17020,                                     -- Arkane Brillanz
    [21562] = 17028, [21564] = 17029,                    -- Gebet der Seelenstärke, Rang 1 und 2
    [27681] = 17029, [27683] = 17029,                    -- Gebet der Willenskraft, Gebet des Schattenschutzes
    [21849] = 17021, [21850] = 17026,                    -- Gabe der Wildnis, Rang 1 und 2
    [25782] = 21177, [25916] = 21177, [25894] = 21177, [25918] = 21177, [25898] = 21177,
    [25895] = 21177, [25890] = 21177, [25899] = 21177,   -- Große Segen
}

-- Vorrang je Wahlgruppe und Klasse für Spells.ChooseBuff (CB-34): der erste gelernte Eintrag, den kein anderer
-- ablöst und der nicht nur als gemerkte Wahl gilt (manual), gewinnt. Die Reihen geben die bisherige Regel („der
-- letzte gelernte in BUFF_ORDER“) als Daten wieder: Segen der Könige vor Macht, Magische Rüstung vor Eis- und
-- Frostrüstung, Dämonenrüstung vor Dämonenhaut, Wasserschild vor Blitzschlagschild. Eine gemerkte Wahl
-- (opts.prefer) gewinnt weiter; opts.priority ersetzt die Reihe für einen Aufruf.
Spells.BUFF_PRIORITY = {
    blessing = { PALADIN = { "kings", "might" } },
    armor = { MAGE = { "mageArmor", "iceArmor", "frostArmor" }, WARLOCK = { "demonArmor", "demonSkin" } },
    shield = { SHAMAN = { "waterShield", "lightningShield" } },
}

-- Heilen, Bannen, Wiederbeleben je Klasse (EC-110, ST-16; vorher ezHeal/Templates.lua T.CLASSES). Nur Zauber-IDs
-- (Rang 1) und ihre Rolle; Namen, Ränge und „gelernt“ kommen vom Client (Spells.Name, Spells.Highest). Eine Liste
-- nennt Ersatz in Reihenfolge: die erste gelernte gilt (Spells.BestKnown). Quelle: klassische Rang-1-IDs aus Blizzards
-- Client (wie FALLBACK), für Forever über /ez test geprüft.
--   HEALS[Klasse][Rolle]       fast (schnell), big (groß), hot (über Zeit), shield (Schild), group (Gruppe),
--                              emergency (Notfall)
--   DISPELS[Klasse][Art]       magic, curse, poison, disease (Art wie Blizzards dispelName in Kleinbuchstaben)
--   RESURRECTS[Klasse]         Liste; combat = true: auch im Kampf (Wiedergeburt)
Spells.HEALS = {
    PRIEST = { fast = { 2061, 2050 }, big = { 2060, 2054, 2050 }, hot = { 139 }, shield = { 17 }, group = { 596 } },
    DRUID = { fast = { 8936, 5185 }, big = { 5185 }, hot = { 774 } },
    SHAMAN = { fast = { 8004, 331 }, big = { 331 }, group = { 1064 } },
    PALADIN = { fast = { 19750, 635 }, big = { 635 }, hot = { 1311606 }, emergency = { 633 } },
}
Spells.DISPELS = {
    PRIEST = { magic = { 527 }, disease = { 552, 528 } },
    DRUID = { curse = { 2782 }, poison = { 2893, 8946 } },
    SHAMAN = { poison = { 526 }, disease = { 2870 } },
    PALADIN = { magic = { 4987 }, poison = { 4987, 1152 }, disease = { 4987, 1152 } },
    MAGE = { curse = { 475 } },
}
Spells.RESURRECTS = {
    PRIEST = { 2006 }, PALADIN = { 7328 }, SHAMAN = { 2008 }, DRUID = { 20484, combat = true },
}
-- Weitere Zauber auf Mitspieler (ezHeals Plätze extra bzw. Buffs, die nicht in BUFFS stehen).
-- Abgleich für Forever (Welle 14, ezHeal-Paket „Heil-Vorlagen je Klasse“, 15.11.2026): jede ID in HEALS, DISPELS,
-- RESURRECTS und HELPERS einzeln im Forever-Tooltip nachgesehen (nether.wowhead.com/forever/tooltip/spell/<ID>) –
-- alle vorhanden, Lernstufen wie in der klassischen Fassung. Neu nach dieser Prüfung: Wasseratmung 131 (Stufe 22) und
-- Wasserwandeln 546 (28) des Schamanen, Segen der Opferung 6940 (46) des Paladins, Unsichtbarkeit entdecken 132 (26)
-- des Hexenmeisters. Der Forever-Tooltip kennt NICHT: 1038, 19977, 20911, 25895 (Segen der Rettung, des Lichts, des
-- Refugiums, Großer Segen der Rettung – deckt sich mit dem Selbsttest des Nutzers vom 15.11.2026), 50769 (Wiederbeleben,
-- Druide) und 3411 (Einschreiten, Krieger) – sie stehen in keiner Gruppe dieses Abschnitts. Die Client-Tabellen des
-- Produkts „wowf“ (Build 1.60.1.70938, wago.tools, SpellName je Kennung, nachgesehen am 15.11.2026) bestätigen beides:
-- keine Zeile für 1038, 19977, 20911, 25895, 50769 und 3411; Zeilen für 131 (Water Breathing), 546 (Water Walking),
-- 6940 (Blessing of Sacrifice) und 132 (Detect Invisibility) – Adressen in tools/gegenpruefung_liste.txt. Krieger, Schurke und Jäger
-- haben keine Zauber auf Mitspieler (Tier heilen 136 wirkt nur auf das eigene Tier: Spells.MACRO_LOGIC.HUNTER).
Spells.HELPERS = {
    PRIEST = { 6346 }, DRUID = { 29166 }, PALADIN = { 1022, 1044, 6940 }, MAGE = { 1008, 604, 130 }, WARLOCK = { 5697, 132 },
    SHAMAN = { 131, 546 },
}
-- Ersatznamen der neuen Hilfszauber (nur, wenn der Client die ID nicht nennt; Quelle wie oben)
for id, pair in pairs({
    [131] = { "Wasseratmung", "Water Breathing" },
    [546] = { "Wasserwandeln", "Water Walking" },
    [6940] = { "Segen der Opferung", "Blessing of Sacrifice" },
    [132] = { "Unsichtbarkeit entdecken", "Detect Invisibility" },
}) do
    Spells.FALLBACK[id] = Spells.FALLBACK[id] or pair
end

-- Reihenfolge je Klasse (wie im Zauberbuch: erst der Gruppen-Buff, dann die Selbst-Buffs).
Spells.BUFF_ORDER = { "int", "frostArmor", "iceArmor", "mageArmor", "fort", "spirit", "shadowProt", "innerFire", "motw", "thorns",
    "might", "wisdom", "kings", "salvation", "light", "sanctuary", "battleShout", "demonSkin", "demonArmor", "lightningShield", "waterShield" }

-- Familien: kurze Auren und Zustände einer Klasse, die sich gegenseitig ausschließen (ein Siegel, ein Aspekt, eine
-- Haltung, ein Fluch je Ziel). Sie stehen NICHT in BUFFS, damit ezBuff sie nicht anmahnt; eine ID steht entweder
-- in BUFFS oder hier (Test). Abfragen: Spells.Family, FamilyOf, AuraIDs, FindAura, FormActive (Spells.lua).
--   unit     wo die Aura liegt ("player" oder "target")
--   form     true: kein Aura-Vergleich, sondern Zustand der Gestaltleiste (Spells.FormActive); für die Paladin-Auren
--            vermutet [V] – stehen sie im Spiel nicht auf der Leiste, wird die Familie auf unit = "player" umgestellt
--   spells   Zauber-IDs (Rang 1 bzw. die Forever-ID), nur was die Klassen-Guides für Forever nennen (Quellen oben bei BUFFS)
Spells.FAMILIES = {
    seal = { class = "PALADIN", unit = "player", spells = { 20154, 21082, 20375, 20166, 20165, 1311649 } },
    -- Andacht, Vergeltung, Konzentration, die drei Widerstands-Auren und die Aura der Heiligkeit (CB-34; die vier neuen
    -- IDs [V] wie FALLBACK oben)
    aura = { class = "PALADIN", form = true, spells = { 465, 7294, 19746, 19876, 19888, 19891, 20218 } },
    aspect = { class = "HUNTER", unit = "player", spells = { 13165, 13163, 5118, 13161, 13159 } },
    stance = { class = "WARRIOR", form = true, spells = { 2457, 71, 2458 } },
    form = { class = "DRUID", form = true, spells = { 5487, 9634, 768, 24858 } },
    bane = { class = "WARLOCK", unit = "target", spells = { 980, 603, 1225228 } },
    curse = { class = "WARLOCK", unit = "target", spells = { 440892, 704, 1714, 702 } },   -- 440892 [V]
    sting = { class = "HUNTER", unit = "target", spells = { 1978, 3043, 3034 } },
}

-- Rückfall für Spells.FormActive, wenn die Gestaltleiste die Zauber-ID nicht nennt: Zauber-ID → Nummer aus
-- GetShapeshiftFormID(). Quelle ist der Client: Blizzards Konstanten (Forever-Quelle 1.60.1.70938,
-- Blizzard_FrameXMLBase/Constants.lua und Camelot/Constants.lua: DRUID_CAT_FORM 1, DRUID_TRAVEL_FORM 3,
-- DRUID_ACQUATIC_FORM 4, DRUID_BEAR_FORM 8 in der Forever-Fassung, DRUID_MOONKIN_FORM_1 31, SHAMAN_GHOST_WOLF_FORM 16,
-- PRIEST_SHADOWFORM 28), gelesen beim Laden; die Zahl dahinter gilt nur, wenn der Client die Konstante nicht kennt.
-- Bär und Terrorbär teilen sich Blizzards eine Nummer – „Bär oder Terrorbär“ ist damit eine Gestalt (CB-34).
local function FormNumber(name, fallback)
    local value = rawget(_G, name)
    if type(value) == "number" then return value end
    return fallback
end
Spells.FORM_IDS = {
    [768] = FormNumber("DRUID_CAT_FORM", 1),
    [5487] = FormNumber("DRUID_BEAR_FORM", 8), [9634] = FormNumber("DRUID_BEAR_FORM", 8),
    [783] = FormNumber("DRUID_TRAVEL_FORM", 3), [1066] = FormNumber("DRUID_ACQUATIC_FORM", 4),
    [24858] = FormNumber("DRUID_MOONKIN_FORM_1", 31),
    [2645] = FormNumber("SHAMAN_GHOST_WOLF_FORM", 16),
    [15473] = FormNumber("PRIEST_SHADOWFORM", 28),
}

-- Waffenzauber des Schamanen (Welle 23, A74; Rest von BF-17 in ezBuff): je Waffe ein Zauber, kein Gegenstand und
-- keine Aura auf dem Spieler – darum weder in BUFFS (ezBuff mahnt dort Auren an) noch in FAMILIES (Aura-Vergleich).
-- Die liegende Verzauberung liest Core.WeaponEnchantInfo; welcher Zauber das war, verrät der Client dort nicht.
-- Abfragen: Spells.WeaponImbues(klasse) → Liste, Spells.BestImbueRank(schlüssel) → höchster gelernter Rang.
--   spells   Rang-IDs, levels dieselbe Reihenfolge (Lernstufe; zur Laufzeit gilt zuerst der Client, Spells.LevelLearned)
-- Quelle: [B] laut Client-Tabellen (wago.tools, wowf 1.60.1.70938; ClassSpells: Grund-ID, Rang und Lernstufe) – alle
-- 22 Ränge und Stufen stimmen; die wago-Prüfung gleicht Kennung, Klasse und Stufe in sh tools/test.sh ab (Gesamtreview
-- 18.11.2026, T14-NH6). Zur Laufzeit nennt Spells.WeaponImbues die Stufe laut ausgelieferter Tabelle
-- (ClientData.ClassSpell); levels hier ist der Rückfall ohne Tabelle.
Spells.WEAPON_IMBUES = {
    SHAMAN = {
        { key = "rockbiter", spells = { 8017, 8018, 8019, 10399, 16314, 16315, 16316 }, levels = { 1, 8, 16, 24, 34, 44, 54 } },
        { key = "flametongue", spells = { 8024, 8027, 8030, 16339, 16341, 16342 }, levels = { 10, 18, 26, 36, 46, 56 } },
        { key = "frostbrand", spells = { 8033, 8038, 10456, 16355, 16356 }, levels = { 20, 28, 38, 48, 58 } },
        { key = "windfury", spells = { 8232, 8235, 10486, 16362 }, levels = { 30, 40, 50, 60 } },
    },
}

-- Schwellen (eine Stelle): ab so vielen Minuten gilt ein Buff als Dauer-Buff („vor dem Kampf“); so viele Sekunden
-- Rest gelten als „läuft bald aus“ (Spells.BuffState), solange der Aufrufer nichts anderes nennt.
Spells.LONG_BUFF_MINUTES = 10
Spells.PREP_LEFT = 120
