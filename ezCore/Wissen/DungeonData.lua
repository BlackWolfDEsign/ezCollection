local _, ns = ...
local Core = ezCore

-- Daten der Dungeon-Tabelle, die der Client nicht liefert: Kürzel aus dem Chat (deutsch und englisch).
-- Name, Stufen und Spielerzahl liest Dungeons.lua zur Laufzeit aus Blizzards Gruppensuche (C_LFGList) –
-- die Werte hier springen nur ein, solange sie fehlt. Schlüssel ist die Instanz-ID (mapID aus
-- GetInstanceInfo bzw. GroupFinderActivityInfo.mapID). Neue Forever-Dungeons kommen allein aus der
-- Gruppensuche; ihre Kürzel bildet Dungeons.lua aus dem Kurznamen und den Anfangsbuchstaben.
--   kind  "dungeon" oder "raid"   de/en  Ersatzname   min/max  Ersatz-Stufenbereich   abbr  Kürzel (klein)
--
-- QUELLE und STAND (DG-53, Leitlinie 10; Herkunft nachgelesen mit git log -S, 15.11.2026): Die Tabelle entstand am
-- 13.11.2026 im Zweig der Dungeon-Tabelle (acd1ea3) und wurde am 13. und 14.11.2026 berichtigt (dfc0bdc, 825cc49) –
-- aus allgemeinem Wissen über die Classic-Dungeons in eigener Form geschrieben. Nichts stammt aus den Dateien eines
-- Addons (auch nicht aus einer Datentabelle eines Gruppensuch- oder Dungeon-Addons).
--   - Instanz-IDs (Schlüssel): Blizzards mapID; im Spiel bestätigt, sobald die Gruppensuche den Dungeon liefert
--     (Dungeons.lua legt dann Name und Stufen aus C_LFGList darüber).
--   - Ersatznamen de/en: die deutschen und englischen Namen des Clients (Classic), als Rückfall ohne Gruppensuche. Die
--     englischen Namen gleicht die wago-Prüfung mit der Client-Tabelle Map ab (MapName_lang, enUS; wago.tools, wowf
--     1.60.1.70938) – angeglichen am 18.11.2026 (Gesamtreview, T14-NH7): Deadmines, Stormwind Stockade, Sunken Temple,
--     Ahn'Qiraj Temple; die klassischen Namen bleiben als Kürzel (abbr). Die deutschen Namen liegen nicht in den Tabellen.
--   - Ersatz-Stufenbereiche min/max: UNGEPRÜFT – Richtwerte aus Classic, im Spiel gegen den Client zu bestätigen
--     (Forever kann andere Stufen haben; maßgeblich ist immer, was die Gruppensuche meldet).
--   - Kürzel (abbr) und Gebiet mit dem Eingang (ENTRANCES): eigene Sammlung aus dem Sprachgebrauch im Chat bzw. der
--     Lage der Eingänge in Classic; ungeprüft für Forever (ROADMAP ezCore, „Im Spiel prüfen“).

Core.Dungeons = Core.Dungeons or {}
local Dungeons = Core.Dungeons

-- Kennzeichen für Anzeigen und Prüfungen: die Ersatz-Stufenbereiche sind ungeprüft (siehe Kopf).
Dungeons.DATA_UNVERIFIED = { min = true, max = true, abbr = true, entrances = true }

Dungeons.DATA = {
    [389] = { kind = "dungeon", de = "Flammenschlund", en = "Ragefire Chasm", min = 13, max = 18,
        abbr = { "rfc", "ragefire", "flammenschlund" } },
    [36] = { kind = "dungeon", de = "Die Todesminen", en = "Deadmines", min = 17, max = 26,
        abbr = { "dm", "vc", "deadmines", "the deadmines", "todesminen" } },
    [43] = { kind = "dungeon", de = "Die Höhlen des Wehklagens", en = "Wailing Caverns", min = 17, max = 24,
        abbr = { "wc", "wailing", "hdw", "höhlen des wehklagens", "wehklagen" } },
    [33] = { kind = "dungeon", de = "Burg Schattenfang", en = "Shadowfang Keep", min = 22, max = 30,
        abbr = { "sfk", "shadowfang", "bsf", "schattenfang" } },
    [48] = { kind = "dungeon", de = "Tiefschwarze Grotte", en = "Blackfathom Deeps", min = 24, max = 32,
        abbr = { "bfd", "blackfathom", "tsg", "tiefschwarze grotte" } },
    [34] = { kind = "dungeon", de = "Das Verlies", en = "Stormwind Stockade", min = 24, max = 32,
        abbr = { "stocks", "stockade", "stockades", "the stockade", "verlies" } },
    [90] = { kind = "dungeon", de = "Gnomeregan", en = "Gnomeregan", min = 29, max = 38,
        abbr = { "gnomer", "gnomeregan" } },
    [47] = { kind = "dungeon", de = "Kral von Razorfen", en = "Razorfen Kraul", min = 29, max = 38,
        abbr = { "rfk", "kraul", "kral", "kvr", "kral von razorfen" } },
    [189] = { kind = "dungeon", de = "Das Scharlachrote Kloster", en = "Scarlet Monastery", min = 26, max = 45,
        abbr = { "sm", "scarlet", "graveyard", "library", "armory", "armoury", "cathedral", "sm gy", "sm lib", "sm arm", "sm cath",
                 "kloster", "friedhof", "bibliothek", "bibli", "waffenkammer", "kathedrale", "kathe" } },
    [129] = { kind = "dungeon", de = "Hügel von Razorfen", en = "Razorfen Downs", min = 37, max = 46,
        abbr = { "rfd", "downs", "hvr", "hügel von razorfen" } },
    [70] = { kind = "dungeon", de = "Uldaman", en = "Uldaman", min = 41, max = 51,
        abbr = { "ulda", "uldaman", "uld" } },
    [209] = { kind = "dungeon", de = "Zul'Farrak", en = "Zul'Farrak", min = 44, max = 54,
        abbr = { "zf", "zul'farrak", "zulfarrak", "zul farrak" } },
    [349] = { kind = "dungeon", de = "Maraudon", en = "Maraudon", min = 46, max = 55,
        abbr = { "mara", "maraudon" } },
    [109] = { kind = "dungeon", de = "Der Tempel von Atal'Hakkar", en = "Sunken Temple", min = 50, max = 60,
        abbr = { "st", "the temple of atal'hakkar", "temple of atal'hakkar", "atal'hakkar", "versunkener tempel", "vt" } },
    [230] = { kind = "dungeon", de = "Schwarzfelstiefen", en = "Blackrock Depths", min = 52, max = 60,
        abbr = { "brd", "blackrock depths", "brt", "schwarzfelstiefen" } },
    [229] = { kind = "dungeon", de = "Schwarzfelsspitze", en = "Blackrock Spire", min = 55, max = 60,
        abbr = { "lbrs", "ubrs", "brs", "blackrock spire", "usfs", "osfs", "schwarzfelsspitze" } },
    [429] = { kind = "dungeon", de = "Düsterbruch", en = "Dire Maul", min = 55, max = 60,
        abbr = { "dire maul", "dme", "dmw", "dmn", "dm e", "dm w", "dm n", "dm east", "dm west", "dm north", "dm tribute",
                 "düsterbruch", "db", "dbo", "dbw", "dbn" } },
    [289] = { kind = "dungeon", de = "Scholomance", en = "Scholomance", min = 58, max = 60,
        abbr = { "scholo", "scholomance" } },
    [329] = { kind = "dungeon", de = "Stratholme", en = "Stratholme", min = 58, max = 60,
        abbr = { "strat", "strath", "stratholme" } },
    -- Schlachtzüge
    [409] = { kind = "raid", de = "Geschmolzener Kern", en = "Molten Core", min = 60, max = 60,
        abbr = { "mc", "molten core", "gk", "geschmolzener kern" } },
    [249] = { kind = "raid", de = "Onyxias Hort", en = "Onyxia's Lair", min = 60, max = 60,
        abbr = { "ony", "onyxia" } },
    [309] = { kind = "raid", de = "Zul'Gurub", en = "Zul'Gurub", min = 60, max = 60,
        abbr = { "zg", "zul'gurub", "zulgurub" } },
    [509] = { kind = "raid", de = "Ruinen von Ahn'Qiraj", en = "Ruins of Ahn'Qiraj", min = 60, max = 60,
        abbr = { "aq20", "ruins of ahn'qiraj", "ruinen von ahn'qiraj" } },
    [469] = { kind = "raid", de = "Pechschwingenhort", en = "Blackwing Lair", min = 60, max = 60,
        abbr = { "bwl", "blackwing", "psh", "pechschwingenhort" } },
    [531] = { kind = "raid", de = "Tempel von Ahn'Qiraj", en = "Ahn'Qiraj Temple", min = 60, max = 60,
        abbr = { "aq40", "aq", "temple of ahn'qiraj", "tempel von ahn'qiraj" } },
    [533] = { kind = "raid", de = "Naxxramas", en = "Naxxramas", min = 60, max = 60,
        abbr = { "naxx", "naxxramas" } },
}

-- Wörter, die nie allein als Kürzel zählen (zu häufig im Chat).
Dungeons.STOPWORDS = { ["der"] = true, ["die"] = true, ["das"] = true, ["the"] = true, ["von"] = true, ["of"] = true,
    ["und"] = true, ["and"] = true, ["lfg"] = true, ["lfm"] = true, ["lf"] = true,
    -- Gattungswörter (auch Namen der Kategorien in der Gruppensuche): meinen nie einen bestimmten Dungeon
    ["dungeon"] = true, ["dungeons"] = true, ["raid"] = true, ["raids"] = true, ["instanz"] = true, ["instanzen"] = true,
    ["schlachtzug"] = true, ["schlachtzüge"] = true }

-- Lagewörter: als Kurzname eines Flügels („Ost“, „West“, „Nord“, „Upper“) allein kein Kürzel – im Chat stehen sie
-- ständig in anderem Sinn („wer geht nach ost“). Mit dem Dungeon davor bleiben sie Kürzel („dm east“, oben je Dungeon).
-- Für die Anfangsbuchstaben neuer Dungeons zählen sie weiter mit (anders als STOPWORDS).
Dungeons.WINGWORDS = { ["ost"] = true, ["west"] = true, ["nord"] = true, ["süd"] = true,
    ["osten"] = true, ["westen"] = true, ["norden"] = true, ["süden"] = true,
    ["east"] = true, ["north"] = true, ["south"] = true,
    ["oben"] = true, ["unten"] = true, ["obere"] = true, ["untere"] = true, ["oberer"] = true, ["unterer"] = true,
    ["oberes"] = true, ["unteres"] = true, ["upper"] = true, ["lower"] = true }

-- Gebiet mit dem Eingang (Ersatz, solange der Client keine Eingänge je Dungeon liefert; für ezQuest „Eingang: …“).
-- Schlüssel wie oben (Instanz-ID); neue Forever-Dungeons haben keinen Eintrag.
Dungeons.ENTRANCES = {
    [389] = { "Orgrimmar", "Orgrimmar" }, [36] = { "Westfall", "Westfall" }, [43] = { "Brachland", "The Barrens" },
    [33] = { "Silberwald", "Silverpine Forest" }, [48] = { "Eschental", "Ashenvale" }, [34] = { "Sturmwind", "Stormwind City" },
    [90] = { "Dun Morogh", "Dun Morogh" }, [47] = { "Brachland", "The Barrens" }, [189] = { "Tirisfal", "Tirisfal Glades" },
    [129] = { "Brachland", "The Barrens" }, [70] = { "Ödland", "Badlands" }, [209] = { "Tanaris", "Tanaris" },
    [349] = { "Desolace", "Desolace" }, [109] = { "Sümpfe des Elends", "Swamp of Sorrows" },
    [230] = { "Schwarzfels", "Blackrock Mountain" }, [229] = { "Schwarzfels", "Blackrock Mountain" },
    [429] = { "Feralas", "Feralas" }, [289] = { "Westliche Pestländer", "Western Plaguelands" },
    [329] = { "Östliche Pestländer", "Eastern Plaguelands" }, [409] = { "Schwarzfels", "Blackrock Mountain" },
    [249] = { "Düstermarschen", "Dustwallow Marsh" }, [309] = { "Schlingendorntal", "Stranglethorn Vale" },
    [509] = { "Silithus", "Silithus" }, [469] = { "Schwarzfels", "Blackrock Mountain" }, [531] = { "Silithus", "Silithus" },
    [533] = { "Östliche Pestländer", "Eastern Plaguelands" },
}
