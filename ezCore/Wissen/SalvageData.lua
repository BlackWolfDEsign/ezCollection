local _, ns = ...
local Core = ezCore

--[[
    Daten zum „Zerlegen“ (Entzaubern; Sondieren und Mahlen später) – reine Tabellen für Salvage.lua.
    Muss in der TOC VOR Salvage.lua stehen.

    QUELLE und STAND (ehrlich): aus dem Gedächtnis übertragen, nach der öffentlichen Classic-Entzaubertabelle
    (Patch 1.12, nach Itemlevel und Qualität) des Warcraft-Wikis (Seite „Disenchanting tables“, Abschnitt Classic).
    Weder gegen diese Seite noch gegen WoW Forever geprüft. Die Zahlen stehen in eigener Form (eigene Gliederung nach
    Qualität, Itemlevel-Band und Rüstung/Waffe): UNGEPRÜFT – IM SPIEL ABGLEICHEN (ROADMAP ezCore, „Im Spiel prüfen“).
    Darum trägt jede Art `unverified = true`; Salvage.For gibt das Kennzeichen weiter, und jedes Fenster, das die
    Zahlen zeigt, muss es mit anzeigen (Text SALVAGE_UNVERIFIED).
    Nichts aus den Dateien eines Addons (Leitlinie 10): kein fremdes Addon ist Daten- oder Codequelle dieser Zahlen.
    Forever kann eigene Itemlevel-Grenzen und eigene Materialien haben – dann nur diese Datei ändern.

    Neue Art ergänzen: Eintrag in KINDS (Zauber-ID aus dem Client, Reihenfolge) und eine Tabelle, aus der
    Salvage.lua die Materialien liest. Solange der Zauber im Client fehlt, bleibt die Art unsichtbar
    (Salvage.Kinds() nennt sie nicht).
]]

local D = {}
ns.SalvageData = D

-- Arten. spell = Zauber-ID (Client), label = Text in Locale.lua, data = Name der Tabelle unten (nil = noch keine Daten).
D.KINDS = {
    disenchant = { order = 1, spell = 13262, label = "SALVAGE_disenchant", data = "DISENCHANT", unverified = true },
    prospect = { order = 2, spell = 31252, label = "SALVAGE_prospect", unverified = true },   -- Juwelenschleifen (ab BC): keine Daten
    mill = { order = 3, spell = 51005, label = "SALVAGE_mill", unverified = true },           -- Inschriftenkunde (ab WotLK): keine Daten
}

-- Materialien (itemID)
local DUST = { strange = 10940, soul = 11083, vision = 11137, dream = 11176, illusion = 16204 }
local ESSENCE = { lesserMagic = 10938, greaterMagic = 10939, lesserAstral = 10998, greaterAstral = 11082,
    lesserMystic = 11134, greaterMystic = 11135, lesserNether = 11174, greaterNether = 11175,
    lesserEternal = 16202, greaterEternal = 16203 }
local SHARD = { smallGlimmering = 10978, largeGlimmering = 11084, smallGlowing = 11138, largeGlowing = 11139,
    smallRadiant = 11177, largeRadiant = 11178, smallBrilliant = 14343, largeBrilliant = 14344 }
local NEXUS = 20725
D.MATERIALS = { dust = DUST, essence = ESSENCE, shard = SHARD, crystal = { nexus = NEXUS } }

--[[
    Selten (grün), Qualität 2. Zeile: { von, bis, { Staub, min, max }, { Essenz, min, max }, Splitter, Splitter-Anteil }
    Rüstung: überwiegend Staub (Staub 75 %, Essenz 20 %, Splitter 5 %), Waffen umgekehrt (Essenz 75 %, Staub 20 %,
    Splitter 5 %). Ohne Splitter (5–15): 80 % / 20 %. Bei 21–25 ist der Splitter häufiger (10 %), dafür 15 % für
    den selteneren Stoff.
]]
D.UNCOMMON = {
    { 5, 15, { DUST.strange, 1, 2 }, { ESSENCE.lesserMagic, 1, 2 } },
    { 16, 20, { DUST.strange, 2, 3 }, { ESSENCE.greaterMagic, 1, 2 }, SHARD.smallGlimmering, 0.05 },
    { 21, 25, { DUST.strange, 4, 6 }, { ESSENCE.lesserAstral, 1, 2 }, SHARD.smallGlimmering, 0.10 },
    { 26, 30, { DUST.soul, 1, 2 }, { ESSENCE.greaterAstral, 1, 2 }, SHARD.largeGlimmering, 0.05 },
    { 31, 35, { DUST.soul, 2, 5 }, { ESSENCE.lesserMystic, 1, 2 }, SHARD.smallGlowing, 0.05 },
    { 36, 40, { DUST.vision, 1, 2 }, { ESSENCE.greaterMystic, 1, 2 }, SHARD.largeGlowing, 0.05 },
    { 41, 45, { DUST.vision, 2, 5 }, { ESSENCE.lesserNether, 1, 2 }, SHARD.smallRadiant, 0.05 },
    { 46, 50, { DUST.dream, 1, 2 }, { ESSENCE.greaterNether, 1, 2 }, SHARD.largeRadiant, 0.05 },
    { 51, 55, { DUST.dream, 2, 5 }, { ESSENCE.lesserEternal, 1, 2 }, SHARD.smallBrilliant, 0.05 },
    { 56, 60, { DUST.illusion, 1, 2 }, { ESSENCE.greaterEternal, 1, 2 }, SHARD.largeBrilliant, 0.05 },
    { 61, 65, { DUST.illusion, 2, 5 }, { ESSENCE.greaterEternal, 2, 3 }, SHARD.largeBrilliant, 0.05 },
}
D.UNCOMMON_MAJOR = 0.75        -- Anteil des häufigen Stoffs (Rüstung: Staub, Waffe: Essenz), wenn es einen Splitter gibt
D.UNCOMMON_MAJOR_ALONE = 0.80  -- … ohne Splitter

-- Rar (blau), Qualität 3 – für Rüstung und Waffen gleich. Zeile: { von, bis, { { Material, Anteil, min, max } … } }
D.RARE = {
    { 11, 25, { { SHARD.smallGlimmering, 1, 1, 1 } } },
    { 26, 30, { { SHARD.largeGlimmering, 1, 1, 1 } } },
    { 31, 35, { { SHARD.smallGlowing, 1, 1, 1 } } },
    { 36, 40, { { SHARD.largeGlowing, 1, 1, 1 } } },
    { 41, 45, { { SHARD.smallRadiant, 1, 1, 1 } } },
    { 46, 50, { { SHARD.largeRadiant, 1, 1, 1 } } },
    { 51, 55, { { SHARD.smallBrilliant, 1, 1, 1 } } },
    { 56, 65, { { SHARD.largeBrilliant, 0.995, 1, 1 }, { NEXUS, 0.005, 1, 1 } } },
}

-- Episch (violett), Qualität 4 – für Rüstung und Waffen gleich.
D.EPIC = {
    { 40, 45, { { SHARD.smallRadiant, 1, 2, 4 } } },
    { 46, 50, { { SHARD.largeRadiant, 1, 2, 4 } } },
    { 51, 55, { { SHARD.smallBrilliant, 1, 2, 4 } } },
    { 56, 60, { { NEXUS, 1, 1, 1 } } },
    { 61, 88, { { NEXUS, 1, 1, 2 } } },
}

-- Qualität → Tabelle (Entzaubern)
D.DISENCHANT = { [2] = "UNCOMMON", [3] = "RARE", [4] = "EPIC" }
