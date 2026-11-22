local ADDON, ns = ...
local L = ns.L

--[[
    ezQuest – ergänzt Questie, ersetzt es nicht. Blizzards eigene Fenster werden erweitert:
      Levels.lua   Stufe „[12]“ vor den Quests in Gossip- und Begrüßungsliste der NPCs
                   (Questlog und Verfolgung zeigen sie auf Forever schon selbst)
      Tracker.lua  Blizzards Verfolgung nach Stufe sortieren, Knopf am Kopf „Quests“
      Auto.lua     annehmen und abgeben automatisch, Schalter im Quest- und Gossip-Fenster, Shift hält an
      Tint.lua     neue Forever-Quests türkis hinterlegt (Questfenster, Questlog, NPC-Listen)
      Items.lua    Quest-Gegenstände erkennen: ns.API.ItemQuest für ezBag
      DungeonQuests.lua  Dungeon-Quests: Dungeon, Stufenbereich und Eingang im Tooltip (ezCore.Dungeons)
      Entrance.lua       Knopf „Eingang auf der Karte“ in den Questlog-Details (Lage samt Quelle, ezMap-Markierung)
      QuestId.lua  Quest-ID im Tooltip des Questlogs; „Quest mit ID erledigt?“ in Blizzards Zahnrad-Menü am Questlog
      Progress.lua Quest-Fortschritt „<Quest>: <Ziel> 5/7“ im Tooltip von Spielobjekten, Gegnern und Gegenständen
      Shine.lua    Funkeln an Quest-Gegenständen (Blizzards Glanz neuer Gegenstände) – ezBag und ezLoot rufen QuestShine
      World.lua    Blizzards Symbole über Quest-Objekten, Kräutern und Erzen (Interaktions-CVars, Blizzards Werte gemerkt)
      Sparkle.lua  Quest-Objekte in der Welt funkeln: Blizzards Funkeln statt Umriss (Umriss-Modus der Grafik und
                   outlineModeShowLootEffectWhenDisabled, Blizzards Werte gemerkt; Rücksicht auf Forever Loot Sparkles)
      LevelRoute.lua  Leveling-Route: Reihenfolge der Quests im Log nach Weg und Erfahrung je Zeit (Zahnrad-Menü am
                   Questlog und ezMaps Kartenknopf, Blizzards Kartenmarkierung über ezMap; Idee des Nutzers vom 16.11.2026)
      Share.lua    angenommene Quests in der Gruppe über Blizzards Teilen anbieten (ab Werk aus, gedrosselt, nie im Kampf;
                   Haken im Zahnrad-Menü am Questlog; Wunsch des Nutzers vom 18.11.2026)
      XPPreview.lua  Quest-Erfahrung als Vorschau auf Blizzards Erfahrungsleiste: fertige Quests hell, alle blass, Tooltip
                   „nach Abgabe Stufe X, Y %“ (Feature I1 des Gesamtreviews vom 18.11.2026)
    Rücksicht: Erledigt Questie, Leatrix Plus, Forever Tweaks oder ein Tönungs-Addon dieselbe Sache, hält sich
    ezQuest zurück (ns.OtherHandles → ezCore.WhoHandles).
]]

ns.DEFAULTS = {
    levelInDialogs = true,  -- „[12]“ vor Quests in den NPC-Dialogen
    -- Blizzards Verfolgung: niedrigste Stufe zuerst – meldet Quests ohne Klick ab und wieder an, darum ab Werk aus seit
    -- Welle 29 (NACH-27; Grundsatz des Nutzers vom 17.11.2026, wörtlich „user muss auf sowas hingewiesen werden, er kann
    -- es nutzen muss es aber einschalten“); einmal umgestellt in ns.MigrateSortOptIn, Hinweis an der Questverfolgung
    sortTracker = false,
    sortSuperTrack = false, -- nach dem Sortieren Blizzards Zielverfolgung auf die verfolgte Quest zurücksetzen (Welle 29)
    autoQuest = false,      -- annehmen und abgeben automatisch (Schalter im Questfenster)
    autoTrivial = false,    -- auch graue (sehr niedrige) Quests automatisch annehmen
    autoRepeatable = false, -- auch wiederholbare Quests (Spenden, Ruf) automatisch annehmen und abgeben
    autoReward = false,     -- bei mehreren Belohnungen die von ezGear empfohlene nehmen
    tintNew = true,         -- neue Forever-Quests türkis hinterlegen
    -- (Quest-Gegenstände erkennen, questItems: seit Nr. 45 der Einstellungs-Prüfung vom 19.11.2026 immer an – Items.lua)
    dungeonQuests = true,   -- Dungeon-Quests: Dungeon und Stufenbereich im Tooltip (ezCore.Dungeons)
    entranceButton = true,  -- Knopf „Eingang auf der Karte“ in den Questlog-Details (Entrance.lua)
    -- questIdTip (Quest-ID im Tooltip des Questlogs) ist seit der Einstellungs-Prüfung vom 19.11.2026 ezCores
    -- gemeinsamer Schalter „IDs in Tooltips (NPC, Quest)“ (ns.SHARED unten)
    -- Funkeln und Hervorheben (Wunsch des Nutzers vom 15.11.2026). Funkeln und Symbole in der Welt stellen ohne Klick
    -- Blizzards Grafik- bzw. Barrierefreiheits-Einstellungen um: ab Werk aus, mit Hinweis an der Questverfolgung
    -- (Entscheidung des Nutzers vom 18.11.2026, wörtlich „Ab Werk aus, mit Hinweis“); einmal umgestellt in
    -- ns.MigrateWorldOptIn
    worldSparkle = false,   -- Quest-Objekte in der Welt funkeln statt Umriss (Wunsch vom 15.11.2026, Sparkle.lua)
    worldIcons = false,     -- Blizzards Symbole über Quest-Objekten, Kräutern und Erzen (CVars, World.lua)
    bagShine = true,        -- Quest-Gegenstände in Tasche und Bank funkeln (ezBag zeichnet über Shine.lua)
    lootShine = true,       -- Quest-Gegenstände im Beutefenster funkeln (ezLoot zeichnet über Shine.lua)
    progressTip = true,     -- „<Quest>: <Ziel> 5/7“ im Tooltip von Objekten, Gegnern und Gegenständen (Progress.lua)
    -- Leveling-Route (LevelRoute.lua; Idee des Nutzers vom 16.11.2026, ab Werk nach seinen Antworten vom 17.11.2026)
    levelRoute = true,      -- Eintrag „Leveling-Route“ am Questlog und in ezMaps Kartenknopf (Antwort 7)
    -- Route ohne Klick berechnen (Wunsch des Nutzers vom 18.11.2026, wörtlich „sollte es nicht grundsätzlich erstmal nach
    -- dem einschalten die route berechnen?“): nur Nachschlage-Wissen im Arbeitsspeicher, stellt an Blizzard nichts um
    routeAuto = true,
    routeVendor = true,     -- Händler am Weg einplanen (Antwort 4)
    routeVendorFree = 4,    -- … bei höchstens so vielen freien Plätzen in den Taschen (Antwort 4, Schieber 0–20)
    routeGather = true,     -- Kräuter und Erze am Weg, nur mit Beruf und reichendem Rang (Antwort 5)
    routeDetour = 60,       -- Grenze eines Abstechers in Yards (Antwort 6, Schieber 0–200)
    routeHard = true,       -- Elite-, Dungeon- und Quests über drei Stufen einplanen (Antwort 9; aus beim Leveln allein)
    routeLine = true,       -- Linie der Route auf der Weltkarte über ezMap (Antwort 3)
    routeMiniArrow = true,  -- Pfeil auf der Minikarte zum nächsten Schritt über ezMap (Spieltest 19.11.2026)
    routeMiniArrowSize = 24, -- seine Größe in Bildpunkten (Spieltest 20.11.2026: 16 war zu klein; Schieber 12–48)
    -- ohne Klick an Blizzards Zuständen: ab Werk aus, mit Hinweis im Menü (Grundsatz des Nutzers vom 17.11.2026, wörtlich
    -- „user muss auf sowas hingewiesen werden, er kann es nutzen muss es aber einschalten“). Den Pfeil beim
    -- Weiterrücken (routeArrow) gibt es seit Nr. 94 der Einstellungs-Prüfung vom 19.11.2026 nur über ezMaps wayTrack.
    routeWatch = false,     -- Quest des nächsten Schritts in Blizzards Verfolgung (Antwort 3: „sonst in Blizzards Verfolgung“)
    -- Quest-Erfahrung als Vorschau auf Blizzards Erfahrungsleiste (XPPreview.lua; Feature I1 des Gesamtreviews vom
    -- 18.11.2026): reine Anzeige, darum ab Werk an
    xpPreview = true,
    -- Blizzards Erholungs-Marke rückt um die fertigen Quests weiter (XPPreview.lua; Entscheidung des Nutzers vom
    -- 21.11.2026 „Ja, Marke mitwandern“): nur Lage, außerhalb des Kampfes, abschaltbar
    xpTickFollow = true,
    -- Angenommene Quests automatisch teilen (Share.lua; Wunsch des Nutzers vom 18.11.2026, wörtlich „feature: quest
    -- automatisch teilen“): sendet ohne Klick an die Mitspieler, darum ab Werk aus, mit Hinweis an der Questverfolgung
    -- (Grundsatz des Nutzers vom 17.11.2026, Entscheidung 2 vom 18.11.2026)
    autoShare = false,
}

-- „Allem zustimmen“ (ezCore, Werkzeuge/FirstStart.lua: Intro.Registered; Spieltest 20.11.2026): jeder Schalter oben,
-- der ab Werk aus ist und kein Ablauf ohne Klick (die stehen in Intro.CONSENT). "on": mit der Zustimmung gesetzt;
-- "risk": bleibt aus, riskiert Blizzards Regeln oder Schutz; "choice": Geschmack, Filter, Leitlinie 9 oder 11.
-- tools/Tests/agree_test.lua prüft, dass jeder neue Schalter mit false hier oder in Intro.CONSENT steht.
-- risk hier: Wiederholbare verbrauchen Gegenstände, die Belohnung wird ohne Klick gewählt
ns.AGREE = {
    autoRepeatable = "risk", autoReward = "risk", autoTrivial = "choice",
}

-- Schalter für /ezq <befehl> (deutsches Wort, englisches im Feld en – T10-1: „/ezq sort“ im englischen Client –,
-- sonst der Schlüssel klein geschrieben).
ns.TOGGLES = {
    { "autoQuest", "auto" },
    { "sortTracker", "sortieren", en = "sort" },
    { "levelInDialogs", "stufe", en = "level" },
    { "tintNew", "neu", en = "new" },
    { "dungeonQuests", "dungeon" },
}

local Core = ezCore

-- Welle 29 (NACH-27): „Verfolgung nach Stufe sortieren“ ist ab Werk aus. Einmal umstellen wie estimateOff17 in ezCombat,
-- MigrateMailOptIn in ezChat und MigrateAutoSellOptIn in ezBag – ezCores FillDefaults allein ließe ein gespeichertes
-- „an“ (den alten Standard) stehen. Alter Wert in db.sortOff29Was (Hinweis „beim Update ausgeschaltet“); der Merker
-- db.sortOff29 verhindert ein zweites Umstellen – wer es danach selbst einschaltet, behält es. → true, wenn umgestellt
-- Seit dem Gesamtreview vom 18.11.2026 (T4-7) über ezCores Core.OptInOnce – Merker und Verhalten wie vorher.
function ns.MigrateSortOptIn(db)
    return Core.OptInOnce(db, "sortOff29", { sortTracker = "sortOff29Was" }) ~= nil
end

-- Welle 29 (Entscheidung des Nutzers vom 18.11.2026, wörtlich „Ab Werk aus, mit Hinweis“): „Quest-Objekte funkeln“ und
-- „Symbole über Quest-Objekten“ sind ab Werk aus. Einmal umstellen wie ns.MigrateSortOptIn: ein gespeichertes „an“ (der
-- alte Standard) wird aus, der alte Wert steht in db.worldSparkleOff29Was bzw. db.worldIconsOff29Was (Hinweis „beim
-- Update ausgeschaltet“); der Merker db.worldOff29 verhindert ein zweites Umstellen – wer es danach selbst einschaltet,
-- behält es. Blizzards Werte gibt danach das Anmelden zurück (World.Sync und Sparkle.Login in ns.OnReady wie beim
-- Ausschalten, nie im Kampf: sonst nach PLAYER_REGEN_ENABLED). → Liste der umgestellten Schlüssel oder nil
ns.WORLD_OPTIN = { worldSparkle = "worldSparkleOff29Was", worldIcons = "worldIconsOff29Was" }
-- Über Core.OptInOnce (T4-7), Reihenfolge wie vorher: erst Funkeln, dann Symbole.
function ns.MigrateWorldOptIn(db)
    return Core.OptInOnce(db, "worldOff29", { { "worldSparkle", ns.WORLD_OPTIN.worldSparkle },
        { "worldIcons", ns.WORLD_OPTIN.worldIcons } })
end

-- Einstellungs-Prüfung vom 19.11.2026 (Entscheidung des Nutzers „Ja, alle umsetzen“): entfallene Schalter einmal aus
-- ezQuestDB.settings nehmen (Merker db.settings1911, Core.MigrateOnce). Beide brauchen keine Übernahme:
--   questItems  Quest-Gegenstände erkennen – immer an (Nr. 45), ein gespeichertes „aus“ gilt nicht mehr
--   routeArrow  Pfeil beim Weiterrücken – ezMaps „Zielverfolgung einschalten“ gilt (Nr. 94; der Haken wirkte allein nicht)
-- → true beim ersten Mal, sonst nil
ns.RETIRED_1911 = { "questItems", "routeArrow" }
function ns.MigrateSettings1911(db)
    if type(db) ~= "table" or type(db.settings) ~= "table" then return nil end
    return Core.MigrateOnce(db, "settings1911", function()
        -- Wer routeArrow aus hatte (gespeichert, also kein Neuling), dem stellt ezQuest Blizzards Pfeil beim
        -- Weiterrücken weiter nicht um, bis er es am Hinweis der Weltkarte einschaltet (code-reviewer 20.11.2026: sonst
        -- galt eine Zustimmung zu ezMaps wayTrack, die nur der Sammel-Route galt, still auch für die Leveling-Route)
        if db.settings.routeArrow == false then db.routeArrowOff1911Was = true end
        for _, key in ipairs(ns.RETIRED_1911) do db.settings[key] = nil end
        return true
    end)
end

-- Print, Error, Try, On, OnReady, RunReady, OnSettingChanged, SettingChanged, SetSetting,
-- Enabled(key), Throttle(fn, delay), WhenAddOnLoaded, AfterCombat … (ezCore gibt sie jedem Modul).
-- Das Gerüst (ezCore, Core.ModuleScaffold) übernimmt, was vorher hier stand:
--   db/tables   ezQuestDB anlegen (auch bei beschädigter Datei), Standardwerte aus ns.DEFAULTS, ns.db und ns.S;
--               ezQuestDB.hints = gesehene Erklärblasen (Tour.lua)
--   login       ns.charKey, ns.realm, ns.me setzen und ns.RunReady() beim PLAYER_LOGIN
--   slash       /ezquest mit „optionen“, „status“, „hilfe“ und den Schaltern aus ns.TOGGLES → ns.HandleSlash,
--               ns.PrintHelp; Kurzbefehl /ezq nur, wenn ihn kein anderes Addon belegt (→ ns.slashAlias);
--               eigene Befehle über ns.SlashExtra (unten): /ezq id 1234
--   Status      ns.PrintStatus (Kopf ns.StatusHeader(), Zeilen aus ns.StatusLines unten)
-- Ist ezCore zu alt dafür, meldet es das einmal im Chat und in /ez status; ezQuest bleibt dann still.
Core.NewModule(ADDON, ns, {
    title = "ezQuest",
    -- 1.15.0: Bausteine aus dem Gesamtreview vom 18.11.2026, u. a. Core.QuestLogEntries, Core.XPLevelCap, Core.AtlasTexCoord, Core.SlashCmd
    -- (Liste je Modul in docs/roadmap/uebergreifend.md, P7)
    core = "1.15.0",   -- Dungeons.EntranceLabel/EntranceMap prüft das Modul selbst (Rückfall auf EntranceZone)
    needs = { "scaffold", "scaffoldHelpers", "AfterCombat", "TogglePanel", "tourOwner", "AskText", "Menu.Toggle", "UnitIs",
        "Style.ColorText", "Style.BUTTON", "MigrateOnce",   -- Umzug der Einstellungs-Prüfung vom 19.11.2026
        -- Welle 23 (ezCore 23c ohne neue Versionsnummer): Menü-Tooltip, Quest-Abfrage, Spielobjekte, Karte nach Namen
        "Menu.Tip", "QuestTitle", "QuestDone", "ObjectID", "Tooltip.AddObjectSection", "Tooltip.ObjectName",
        "Tooltip.ObjectID", "Discovery.LootNames", "Map.ByName", "Map.NameKey",
        -- Welle 27 (Leveling-Route; ezCore ohne neue Versionsnummer): Menü-Symbole aus PR 473
        "Menu.Icon", "Menu.IconRoot", "Menu.ProfessionIcon",
        -- Gesamtreview 18.11.2026, Feature I1 (ezCore ohne neue Versionsnummer): Quest-Erfahrung und Stufe danach
        "QuestXP", "QuestReady", "QuestLogXP", "LevelAfterXP", "XPBlocked",
        -- Leveling-Route nach Stufenabstand (Zweig ezquest/route-stufe; ezCore ohne neue Versionsnummer)
        "QuestDifficulty",
        -- Gegenprüfung I1: ein Filter fürs Questlog, Stufengrenze eines Probe-Kontos, Ausschnitt eines Atlas
        "QuestLogEntries", "XPLevelCap", "AtlasTexCoord",
        -- Quests teilen (Share.lua, 18.11.2026; ezCore ohne neue Versionsnummer)
        "Flag", "Uptime",
        -- Oberflächen-Einheit (Gesamtreview 18.11.2026, P13 D2; ezCore ohne neue Versionsnummer): Hilfe, Addon-Fach,
        -- Kampfsperre, Wege zur Einstellung, Tooltip-Rollen
        "compartmentMain", "SlashCmd", "HelpLines", "CombatNotice", "SettingsPathText", "TipLine", "TipTitle", "TipClick",
        -- Gesamtreview 18.11.2026 (D3, kern/einheit-rest; ohne neue Nummer): Texthelfer statt Kopien im Modul
        "Word",
    -- Gesamtreview 18.11.2026 (P19a, kern/ssot-helfer; ohne neue Nummer): gemeinsame Helfer statt Kopien
    "OptInOnce",
    -- Einstellungs-Prüfung 19.11.2026 (ezCore ohne neue Versionsnummer): gemeinsame Schalter mehrerer Module
    "ShareSettings", "AdoptModuleShared", "SharedOn" },
    db = "ezQuestDB",
    -- worldSaved: Blizzards Werte der Interaktions-CVars (World.lua); sparkleSaved: Umriss-Modus und Funkeln (Sparkle.lua);
    -- routeWatched: [charKey] = { [questID] = true } – von der Leveling-Route in Blizzards Verfolgung aufgenommene Quests
    -- (nur IDs, LevelRoute.lua), damit sie nach /reload bzw. dem nächsten Einloggen wieder herauskommen
    -- sortOff29 / sortOff29Was: Merker der einmaligen Umstellung von Welle 29 (ns.MigrateSortOptIn) bzw. „war vorher an“
    tables = { "hints", "worldSaved", "sparkleSaved", "routeWatched" },
    -- worldOff29 / worldSparkleOff29Was / worldIconsOff29Was: dasselbe für Funkeln und Symbole (ns.MigrateWorldOptIn);
    -- ns.worldSwitched: in dieser Sitzung umgestellt (Sparkle.Login sagt dann einmal, dass es nach dem Neustart wirkt)
    onLoad = function(db)
        ns.MigrateSortOptIn(db)
        ns.worldSwitched = ns.MigrateWorldOptIn(db)
        ns.MigrateSettings1911(db)      -- Einstellungs-Prüfung vom 19.11.2026
        -- alter Wert von questIdTip einmal an ezCores „IDs in Tooltips“ (ns.SHARED unten; ein „an“ bleibt an)
        Core.AdoptModuleShared(ns, db)
    end,
    login = true,
    -- Kurzbefehl /ezq (nur, wenn frei) aus Core.SLASH_ALIASES; Hilfe aus ezCore (Core.HelpLines mit L.CMD_HELP_OWN)
    slash = { extra = function(cmd, rest) return ns.SlashExtra(cmd, rest) end },
})

-- Gemeinsamer Schalter (Einstellungs-Prüfung 19.11.2026, Nr. 93; Entscheidung des Nutzers „Ja, alle umsetzen“): die
-- Quest-ID im Questlog und ezCores NPC-ID im Tooltip schaltet EIN Wert in ezCore (tooltip.ids, ab Werk aus).
-- ns.Enabled("questIdTip"), ns.SetSetting, das Kästchen der Seite (Spiegel) und der Haken im Zahnrad-Menü führen dorthin.
-- old = true: die Quest-ID war ab Werk an und dieser Standard bei jedem Spieler gespeichert – er ist keine Wahl und
-- schaltet die NPC-ID nicht ungefragt ein (Gegenprüfung 19.11.2026). Wer die Quest-ID weiter sehen will, schaltet
-- „IDs in Tooltips (NPC, Quest)“ ein; der Standard des gemeinsamen Schalters (aus) wartet auf die Entscheidung des Nutzers.
ns.SHARED = Core.ShareSettings(ns, { questIdTip = { "tooltip", "ids", old = true } })

-- Der geltende Befehl ns.SlashCmd(rest) kommt seit dem Gesamtreview (P13 D2, T18-2) aus ezCores Gerüst
-- (Core.SlashCmd: der Kurzbefehl /ezq nur, wenn ezCore ihn setzen durfte, sonst /ezquest) – ezQuests eigene Fassung
-- (Welle 23, A3) ist darin aufgegangen.

-- Hilfe-Zeilen mit dem geltenden Befehl: Kopf und Standardzeilen aus ezCore, dann L.CMD_HELP_OWN (T18-20).
function ns.HelpLines()
    return Core.HelpLines(ns)
end

-- Befehle neben den Schaltern: /ezq id 1234 fragt den Client, ob die Quest mit dieser ID erledigt ist; ohne Zahl
-- öffnet sich der Eingabedialog (QuestId.lua). true, wenn der Befehl hier erledigt wurde.
function ns.SlashExtra(cmd, rest)
    -- /ezq route [weiter|aus]: Leveling-Route berechnen, nächstes Ziel markieren, verwerfen (LevelRoute.lua)
    if cmd == "route" and ns.LevelRoute then return ns.LevelRoute.Command(rest) end
    if cmd ~= "id" or not ns.QuestId then return false end
    if rest ~= nil and rest ~= "" then ns.QuestId.Check(rest) else ns.QuestId.Ask() end
    return true
end

-- Schnittstelle für andere Module (ezCore.API("ezQuest")); Items.lua trägt ItemQuest und UseItems (Gegenstände zum
-- Benutzen mit Verfolgung und Gebiet, für ezMacro) ein, QuestId.lua QuestState und AskQuestId, Shine.lua QuestShine
-- (Funkeln für ezBag und ezLoot).
ns.API = {}

---------------------------------------------------------------------------
-- Neue Forever-Quests: Das ursprüngliche Classic endet bei Quest-ID 9665; alle Quests, die Forever neu
-- gebracht hat, liegen weit darüber (Questies Forever-Spuren: ab 65000). Eine Grenze statt einer Liste.
---------------------------------------------------------------------------

ns.FIRST_FOREVER_QUEST = 10000

function ns.IsForeverQuest(questID)
    questID = Core.Num(questID)
    return questID ~= nil and questID >= ns.FIRST_FOREVER_QUEST
end
ns.API.IsForeverQuest = ns.IsForeverQuest

-- Quest-Stufe als Präfix wie in Blizzards Questlog: „[12] “, Elite „[12+] “. nil ohne Stufe.
function ns.LevelPrefix(level, questID)
    level = Core.Num(level)
    if not level or level <= 0 then return nil end
    local elite = ""
    if Core.Num(questID) and Core.Bool(Core.Call(C_QuestLog and C_QuestLog.IsEliteQuest, questID), false) then
        elite = "+"
    end
    return "[" .. level .. elite .. "] "
end

---------------------------------------------------------------------------
-- Rücksicht auf andere Addons: Erledigt eines dieselbe Sache, hält sich ezQuest zurück.
-- Wer was übernimmt, weiß ezCore (Liste Core.OTHER_ADDONS, docs/fremd-addons.md); ezQuest fragt nur:
--   questAccept       annehmen automatisch        (Questie, Leatrix Plus)
--   questTurnIn       abgeben automatisch         (Questie, Leatrix Plus)
--   questTracker      eigener Tracker statt Blizzards Verfolgung (Questie)
--   questSort         Blizzards Verfolgung sortieren (Forever Tweaks)
--   questItemTooltip  Quest-Zeile im Item-Tooltip (Questie)
--   questTint         neue Forever-Quests markieren (Forever Quest Tint, Forever Quests, Forever++)
--   questSparkle      Quest-Objekte in der Welt funkeln lassen (Forever Loot Sparkles; Sparkle.lua)
--   questShare        angenommene Quests automatisch teilen (Stand 18.11.2026 keines bekannt; Share.lua)
---------------------------------------------------------------------------

-- Rückgabe: Name des Addons, das die Funktion übernimmt, sonst nil. Weiterleitung auf ns.OtherFor aus dem Gerüst
-- (Core.WhoHandles ist innen gesichert, die pcall-Hülle entfällt; W-14). Der Name bleibt für Auto.lua, Tint.lua,
-- Tracker.lua und die Statuszeilen.
function ns.OtherHandles(feature)
    return (ns.OtherFor(feature))
end

---------------------------------------------------------------------------
-- Ergänzende Addons (Einstellungen → „Erweitert“, README). Pflicht ist nur ezCore.
---------------------------------------------------------------------------

-- Name, Ordner und Link stehen einmal in ezCore (Core.OTHER_ADDONS.Questie, V-138); ezQuest nennt nur key und why.
Core.AddCompanion(ADDON, { key = "Questie", role = "optional", why = L.COMPANION_WHY_QUESTIE })
-- Attune (Entscheidung Nr. 33 vom 16.11.2026; W-40, QUEST-02): Zugangs- und Dungeon-Questketten baut ezQuest nicht nach,
-- es nennt Attune. Ordner und Beleg stehen in ezCore (Core.OTHER_ADDONS.Attune, Welle 27). Attune hat keine
-- dokumentierte Schnittstelle und steht unter „All Rights Reserved“ – ezQuest liest darum nichts von ihm und speichert
-- nichts; „installiert“ zeigt die Liste der ergänzenden Addons. Ohne den Eintrag in ezCore (ältere Fassung) legt
-- AddCompanion nichts an.
Core.AddCompanion(ADDON, { key = "Attune", role = "optional", why = L.COMPANION_WHY_ATTUNE })

---------------------------------------------------------------------------
-- Status (Datenbank, Login und Befehle kommen aus dem Gerüst, siehe Core.NewModule oben)
---------------------------------------------------------------------------

local function OnOff(key) return ns.Enabled(key) and L.ON or L.OFF end

function ns.StatusLines()
    local lines = {}
    local function Line(label, key, other)
        local text = label .. ": " .. OnOff(key)
        if other and ns.Enabled(key) then text = text .. " – " .. L.QUEST_STATUS_OTHER:format(other) end
        lines[#lines + 1] = text
    end
    Line(L.OPT_levelInDialogs, "levelInDialogs")
    Line(L.OPT_sortTracker, "sortTracker", ns.Tracker and ns.Tracker.Other())
    Line(L.OPT_sortSuperTrack, "sortSuperTrack")
    if ns.Tracker and ns.Tracker.waiting and ns.Enabled("sortTracker") then lines[#lines + 1] = L.TRACKER_WAITING end
    Line(L.OPT_autoQuest, "autoQuest", ns.OtherHandles("questAccept") or ns.OtherHandles("questTurnIn"))
    Line(L.OPT_autoShare, "autoShare", ns.Share and ns.Share.Other())
    if ns.Share then
        for _, line in ipairs(ns.Share.StatusLines()) do lines[#lines + 1] = line end
    end
    Line(L.OPT_tintNew, "tintNew", ns.OtherHandles("questTint"))
    Line(L.OPT_dungeonQuests, "dungeonQuests")
    Line(L.OPT_entranceButton, "entranceButton")
    Line(L.OPT_questIdTip, "questIdTip")
    Line(L.OPT_worldSparkle, "worldSparkle", ns.Sparkle and ns.Sparkle.Other())
    if ns.Sparkle and ns.Enabled("worldSparkle") then
        local state = ns.Sparkle.StatusLine()
        if state then lines[#lines + 1] = state end
    end
    -- World.Other liefert Name und Fassung; die Statuszeile nennt beides wie Tooltip und Chat
    local worldOther, worldVersion
    if ns.World then worldOther, worldVersion = ns.World.Other() end
    if worldOther and worldVersion then worldOther = worldOther .. " " .. worldVersion end
    Line(L.OPT_worldIcons, "worldIcons", worldOther)
    if ns.World and ns.Enabled("worldIcons") then
        local hint = ns.World.StatusLine()
        if hint then lines[#lines + 1] = hint end
    end
    Line(L.OPT_bagShine, "bagShine")
    Line(L.OPT_lootShine, "lootShine")
    Line(L.OPT_progressTip, "progressTip")
    Line(L.OPT_levelRoute, "levelRoute")
    local route = ns.LevelRoute and ns.LevelRoute.StatusLine()
    if route then lines[#lines + 1] = route end
    -- Steht ezQuests Abschnitt im Zahnrad-Menü am Questlog? (Untersuchung „zeigt es mir nicht an“, 18.11.2026)
    local menu = ns.QuestId and ns.QuestId.StatusLine and ns.QuestId.StatusLine()
    if menu then lines[#lines + 1] = menu end
    Line(L.OPT_xpPreview, "xpPreview")
    Line(L.OPT_xpTickFollow, "xpTickFollow")
    local bar = ns.XPPreview and ns.XPPreview.StatusLine()
    if bar then lines[#lines + 1] = bar end
    if ns.Items and ns.Items.Count then lines[#lines + 1] = L.STATUS_ITEMS:format(ns.Items.Count()) end
    return lines
end

---------------------------------------------------------------------------
-- Addon-Knopf an der Minikarte (Addon-Fach)
---------------------------------------------------------------------------

-- Entscheidung 5 vom 18.11.2026 (T18-3, T16-10): ezQuest hat kein eigenes Fenster – jeder Klick öffnet die
-- Einstellungen (vorher schaltete der Rechtsklick „Automatisch“ um; das tun das Häkchen oben rechts im Quest- und
-- Gossip-Fenster, die Einstellung und „/ezq auto“). Klick, Tooltip und Befehlszeile baut ezCore.
ezQuest_OnAddonCompartmentClick, ezQuest_OnAddonCompartmentEnter, ezQuest_OnAddonCompartmentLeave =
    Core.CompartmentHandlers({ ns = ns, title = L.TITLE, owner = ADDON })
