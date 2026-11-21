local ADDON, ns = ...
local L = ns.L

-- ezMap erweitert Blizzards eigene Karte: /way setzt Blizzards Kartenmarkierung (Zielverfolgung nur mit Schalter),
-- Flugzeiten lernt es beim Fliegen, besuchte Lehrer (aus ezCores NPC-Wissen) bietet es als Wegpunkt-Ziel an. Keine eigenen Rare-,
-- Schatz- oder Questpunkte – das machen RareScanner, HandyNotes und Questie (docs/fremd-addons.md). Eigene Punkte nur
-- für Dungeoneingänge und seit Welle 14 für die eigenen Sammel-Fundorte (Gather.lua, Ablösung von GatherMate); seit
-- Welle 27 auf Wunsch (ab Werk aus) Gegner und Objekte laut Questie (QuestieSpawns.lua, Entscheidung F5 b vom 16.11.2026).
ns.DEFAULTS = {
    -- Wegpunkte
    waySlash = true,        -- /way belegen, wenn kein anderes Addon (TomTom) ihn hat; /ezway geht immer
    -- beim Setzen Blizzards Zielverfolgung einschalten (Pfeil und Entfernung): ab Werk aus seit Welle 29 (NACH-27;
    -- Grundsatz des Nutzers vom 17.11.2026, wörtlich „user muss auf sowas hingewiesen werden, er kann es nutzen muss
    -- es aber einschalten“) – stellt Blizzards Zustand ohne Klick um; einmal umgestellt in ns.MigrateOptIn29, Hinweis
    -- an der Weltkarte (Way.lua). Ohne den Schalter setzt ezMap nur die Markierung; den Pfeil schaltet der Klick auf
    -- Blizzards Markierung ein.
    wayTrack = false,
    mapButton = true,       -- Knopf neben Blizzards Pin-Knopf auf der Weltkarte
    -- ezMaps Abschnitt zusätzlich in Blizzards Kartenfilter (oben rechts an der Weltkarte): ab Werk aus seit dem
    -- Spielbefund vom 18.11.2026 („zur map, das muss ein button sein, sinnvoll aufgeteilt“) – der ezMap-Knopf ist der
    -- eine Ort (Gather.InFilter, MapButton.AddTree); ohne ezMap-Knopf steht der Abschnitt trotzdem dort
    -- (Gather.FilterWanted)
    -- Seit der Einstellungs-Prüfung vom 19.11.2026 (Nr. 80, 81) stellt die Seite beide als EINE Auswahl dar
    -- („ezMap an der Weltkarte: Knopf / Blizzards Kartenfilter / beides“, Options.MapPlace); gespeichert bleiben die
    -- zwei Werte, damit nichts umgestellt werden muss
    mapFilterSection = false,
    wayRecent = true,       -- zuletzt gesetzte Markierungen im Kartenmenü („Zuletzt“)
    wayAutoClear = true,    -- Markierung bei Ankunft entfernen (Arrive.lua, Wunsch des Nutzers vom 16.11.2026)
    wayAutoClearDelay = "5",    -- Wartezeit bis dahin: "3" oder "5" Sekunden (Text für Blizzards Auswahlfeld)
    -- (beide seit Nr. 82, 83 der Einstellungs-Prüfung auf der Seite EINE Auswahl „Aus / nach 3 s / nach 5 s“,
    -- Arrive.Choice; wayAutoClear bleibt der Schlüssel der Einführung, Werkzeuge/FirstStart.lua)

    -- Baum der Karte (Tree.lua, Wunsch des Nutzers vom 15.11.2026): Gruppen ergeben sich aus diesen Blättern. Die
    -- alten Gruppen-Schalter gatherPins und trainers hat der Baum abgelöst (Tree.RETIRED, Übernahme in Tree.Migrate).

    -- Karte
    entrancePins = true,    -- Symbole für Dungeon- und Raideingänge auf Blizzards Weltkarte (Client, sonst selbst betretene)
    entranceList = true,    -- Dungeoneingänge als Ziele im Kartenmenü und im Menü „Aufspüren“
    pinsRound = false,      -- Gegenstands- und Zaubersymbole der Kartenpunkte rund statt eckig (MapPins.SetRoundIcons; Spielbefund 18.11.2026)
    mapCoords = true,       -- deine Position und die Stelle unter dem Mauszeiger als Zeile auf Blizzards Weltkarte
    bookTargets = false,    -- fehlende Bibliotheksbücher der Zone mit Fundort im Kartenmenü (Entdecker-Wissen: ab Werk aus)
    bookPins = false,       -- dieselben Fundorte als Punkte auf der Weltkarte (SAM-22; Entdecker-Wissen: ab Werk aus)
    rarePins = false,       -- gemerkte Sichtungen seltener Gegner auf der Weltkarte (SAM-22; Entdecker-Wissen: ab Werk aus)
    recipeVendorPins = true,    -- Rezept-Händler als Punkte (Gruppe „Rezepte“, Welle 15b; Berufe ab Werk nur die eigenen)
    recipeTrainerPins = true,   -- Berufslehrer mit Rezepten als Punkte
    -- Gegner und Objekte laut Questie (QuestieSpawns.lua, Welle 27, F5 b): ab Werk aus, nur auf Wunsch
    questieNpcs = false,        -- Gegner der gezeigten Zone laut QuestieDB
    questieObjects = false,     -- Objekte der gezeigten Zone laut QuestieDB
    questieRares = false,       -- seltene Gegner laut QuestieDB (Entdecker-Wissen)
    questieRankNormal = true,   -- Filtergruppe „Nach Rang“: normale Gegner
    questieRankElite = true,    -- Elite und Bosse
    -- (der dritte Rang „Seltene“, questieRankRare, entfiel mit Nr. 85 der Einstellungs-Prüfung vom 19.11.2026: seltene
    -- Gegner regelt allein questieRares; Übernahme in ns.MigrateSettings1911)

    -- Sammeln (Gather.lua, SAM-10 bis SAM-16): eigene Fundorte aus ezCore auf Blizzards Weltkarte
    gatherHerb = true,      -- Kräuter
    gatherOre = true,       -- Erze
    gatherFish = true,      -- Angelplätze
    gatherChest = false,    -- Kisten (Entdecker-Wissen: ab Werk aus)
    -- (Wert je Ernte im Tooltip, gatherWorth, ist seit Nr. 44 der Einstellungs-Prüfung vom 19.11.2026 immer an)
    -- Nach Farbe (Teilwelle 15b, Wunsch des Nutzers vom 15.11.2026): Fundorte nach der Chance auf einen
    -- Fertigkeitspunkt sieben (Core.Gathering.SkillUp, berechnet); gilt für Weltkarte, Minikarte und Routen
    gatherColorOrange = true,   -- orange: Punkt sicher
    gatherColorYellow = true,   -- gelb: meist ein Punkt
    gatherColorGreen = true,    -- grün: selten ein Punkt
    gatherColorGray = true,     -- grau: nie ein Punkt
    -- rot: noch nicht abbaubar (Rang zu niedrig oder Beruf fehlt) – Nr. 88 der Einstellungs-Prüfung vom 19.11.2026,
    -- vorher der eigene Haken „Nur, was ich abbauen kann“ (gatherSkillOnly an = rot aus)
    gatherColorRed = true,
    gatherColorUnknown = true,  -- unbekannt: nötiger Wert oder eigene Fertigkeit noch nicht bekannt (Angelplätze
                                -- siebt der Farbfilter seit dem 19.11.2026 nicht mehr)
    gatherSize = 14,        -- Größe der Punkte in Bildpunkten (8 bis 32)
    gatherAlpha = 100,      -- Deckkraft in Prozent (20 bis 100)
    gatherDim = 5,          -- eben Geerntetes so viele Minuten abdunkeln (0 = aus)
    gatherOverride = false, -- trotzdem zeigen, obwohl GatherMate2 oder Gatherer Reforged läuft
    -- Minikarte (SAM-11): dieselben Fundorte in Reichweite; Modus je Art in ezCore (Fläche „minimap“)
    gatherMiniHerb = true,  -- Kräuter auf der Minikarte
    gatherMiniOre = true,   -- Erze auf der Minikarte
    gatherMiniFish = true,  -- Angelplätze auf der Minikarte (ezCores Modus ab Werk „nie“ stellt ezMap auf „mit
                            -- Beruf“, Gather.NormalizeModes – Nr. 99 der Einstellungs-Prüfung vom 19.11.2026)
    gatherMiniChest = false,    -- Kisten auf der Minikarte (Entdecker-Wissen: ab Werk aus)
    gatherMiniSize = 12,    -- Größe der Punkte auf der Minikarte in Bildpunkten (8 bis 24)
    gatherMiniAlpha = 100,  -- Deckkraft auf der Minikarte in Prozent (20 bis 100)
    -- Punkte in der Nähe auf der Minikarte ausblenden (Wunsch des Nutzers vom 18.11.2026, Gather.HideNear):
    -- Entfernung in Yards (10 bis 100, 0 = aus) – seit Nr. 89, 90 der Einstellungs-Prüfung vom 19.11.2026 ein
    -- Schieber ohne eigenen Haken (gatherHideNear; Übernahme in ns.MigrateSettings1911)
    gatherHideNearYards = 40,
    -- Routen (Route.lua, SAM-21): je Zone eine gemerkte Route in ezMapDB.routes
    routeLine = true,       -- Linie der Route auf der Weltkarte
    routeNumbers = false,   -- Nummern an allen Schritten der Routen (aus: nur am nächsten; Spieltest 19.11.2026)
    routeMini = true,       -- der nächste Punkt der Route auf der Minikarte (wenn Minikarten-Punkte laufen)

    -- Flugzeiten
    flightTimes = true,     -- Flugzeit im Tooltip der Flugpunkte
    flightBar = true,       -- Leiste mit Restzeit während des Flugs

    flightNearest = true,   -- nächster Flugmeister im Menü „Aufspüren“
    flightDest = true,      -- mit Markierung: Flugmeister am Ziel und gelernte Flugzeit dorthin (MAP-04)
    flightMissing = true,   -- Flugpunkte, die du bzw. deine Twinks noch nicht kennen (Kartenmenü, Tooltip am Flugpunkt;
                            -- Welle 26, F5: laut Client-Tabellen aus ezCore, bekannt laut Blizzards Flug- und Weltkarte)

    -- Lehrer und Händler (besuchte, ezCore merkt sie) als Ziele im Kartenmenü; Berufslehrer je Titel in ezMapDB.mapFilter
    trainerClass = true,    -- Klassenlehrer (eigene Klasse)
    trainerPet = true,      -- Tierausbilder
    trainerOther = true,    -- weitere Lehrer (Waffen, Reiten …)
    vendorTargets = true,   -- Händler der gezeigten Zone
    repairTargets = true,   -- Händler mit Reparatur der gezeigten Zone

    -- Seltene Gegner (Entdecker-Wissen: nur auf Wunsch, deshalb ab Werk aus)
    rareAlert = false,      -- Chatzeile, wenn ein seltener Gegner in Sicht kommt (Einheit oder Minikarten-Vignette)
    rareSound = true,       -- dazu ein Ton
    rareOverride = false,   -- trotzdem melden und zeichnen, obwohl ein Addon für seltene Gegner läuft (z. B. RareScanner)

    -- Schlachtfeld (Nachschlage-Wissen: nur Zeiten, die das Spiel selbst nennt)
    bgTimers = true,        -- Zeit bis zum Start und Restzeit je Punkt unter Blizzards Punkteanzeige

    -- Minikarte
    trackingMenu = true,        -- ezMap-Ziele unten in Blizzards Menü „Aufspüren“ der Minikarte
    trackingRemember = true,    -- Auswahl in Blizzards Menü „Aufspüren“ je Charakter merken und wiederherstellen
    -- gemerkte Such-Zauber (Kräuter-, Mineraliensuche) dabei selbst einschalten: ab Werk aus seit Welle 29 (NACH-27,
    -- Grundsatz wie wayTrack) – sonst nur per Klick im Menü „Aufspüren“; Haken auch dort (TrackingMemory.lua)
    trackingSpellAuto = false,
    trackingCouple = false,     -- Blizzards Aufspür-Haken und ezMaps passende Gruppe gemeinsam schalten (TrackingCouple.lua)
    -- nach so vielen Sekunden von selbst wieder ganz heraus (3 bis 60, 0 = aus, ab Werk aus) – seit Nr. 91, 92 der
    -- Einstellungs-Prüfung vom 19.11.2026 ein Schieber ohne eigenen Haken (minimapAutoZoom; Übernahme in
    -- ns.MigrateSettings1911); den Haken im Menü „Aufspüren“ gibt es weiter (MinimapZoom.SetOn)
    minimapAutoZoomDelay = 0,
    minimapSquare = false,      -- eckige Minikarte: die Ecken zeigen rund 27 % mehr Fläche
    -- Koordinaten ins Zonenkästchen, Lupe und Kalender auf den Ring, Minikarte nach oben (MinimapCompact.lua;
    -- Spieltest 20.11.2026) – stellt Blizzards Anzeige um, darum ab Werk aus
    minimapCompact = false,
}

-- „Allem zustimmen“ (ezCore, Werkzeuge/FirstStart.lua: Intro.Registered; Spieltest 20.11.2026): jeder Schalter oben,
-- der ab Werk aus ist und kein Ablauf ohne Klick (die stehen in Intro.CONSENT). "on": mit der Zustimmung gesetzt;
-- "risk": bleibt aus, riskiert Blizzards Regeln oder Schutz; "choice": Geschmack, Filter, Leitlinie 9 oder 11.
-- tools/Tests/agree_test.lua prüft, dass jeder neue Schalter mit false hier oder in Intro.CONSENT steht.
-- choice hier (Spieltest 20.11.2026, Knopf mit „o fehlt“, wörtlich „mh was soll das sein“): runde Symbole der Punkte und Nummern an allen Schritten der Route ändern nur
-- die Optik. Die kompakte Minikarte bleibt "on": ausdrücklicher Wunsch des Nutzers vom 20.11.2026 („"allem zustimmen"
-- muss auch die kompakte minikarte aktivieren“)
ns.AGREE = {
    minimapCompact = "on", pinsRound = "choice", routeNumbers = "choice", rareAlert = "on", minimapSquare = "choice",
    mapFilterSection = { "choice", text = "mapPlace" }, bookTargets = "choice", bookPins = "choice", rarePins = "choice",
    questieNpcs = "choice", questieObjects = "choice", questieRares = "choice", gatherChest = "choice",
    gatherMiniChest = "choice", gatherOverride = "choice", rareOverride = "choice",
    -- „Nur, was ich abbauen kann“: Rot im Kartenfilter abgewählt heißt zugestimmt (vorher Intro.ALSO in ezCore)
    gatherColorRed = { "on", on = false, label = "INTRO_LABEL_gatherOnly", what = "INTRO_ON_gatherOnly" },
}

local Core = ezCore

-- Einstellungs-Prüfung vom 19.11.2026 (Entscheidung des Nutzers „Ja, alle umsetzen“): zusammengelegte und feste
-- Schalter einmal übernehmen (Merker db.settings1911, Core.MigrateOnce; Schritt verträgt einen leeren Speicher):
--   gatherSkillOnly an        → „Rot – noch nicht abbaubar“ (gatherColorRed) aus             (Nr. 88)
--   gatherHideNear aus        → gatherHideNearYards = 0                                      (Nr. 89, 90)
--   minimapAutoZoom aus       → minimapAutoZoomDelay = 0, die alte Zeit in db.minimapAutoZoomLast für den Haken im
--                               Menü „Aufspüren“                                              (Nr. 91, 92)
--   questieRankRare aus       → questieRares aus (Seltene erschienen nur mit beiden)          (Nr. 84, 85)
--   gatherWorth               → immer an, der alte Wert gilt nicht mehr                       (Nr. 44)
-- Die alten Schlüssel (ns.RETIRED_1911) verschwinden aus ezMapDB.settings. → true beim ersten Mal, sonst nil
ns.RETIRED_1911 = { "gatherSkillOnly", "gatherHideNear", "minimapAutoZoom", "questieRankRare", "gatherWorth" }
function ns.MigrateSettings1911(db)
    if type(db) ~= "table" or type(db.settings) ~= "table" then return nil end
    return Core.MigrateOnce(db, "settings1911", function()
        local s = db.settings
        if s.gatherSkillOnly == true then s.gatherColorRed = false end
        if s.gatherHideNear == false then s.gatherHideNearYards = 0 end
        if s.minimapAutoZoom ~= nil and s.minimapAutoZoom ~= true then
            local delay = tonumber(s.minimapAutoZoomDelay)
            if delay and delay > 0 then db.minimapAutoZoomLast = delay end
            s.minimapAutoZoomDelay = 0
        end
        if s.questieRankRare == false then s.questieRares = false end
        for _, key in ipairs(ns.RETIRED_1911) do s[key] = nil end
        return true
    end)
end

-- Hilfe (T18-20/T18-2): ezCores Kopf und Standardzeilen, davor bei den eigenen Wörtern der Wegpunkt-Befehl, der
-- wirklich gilt – /way nur, wenn ezMap ihn beim Einloggen bekam (Way.lua: nicht, wenn TomTom ihn hat oder waySlash aus ist)
function ns.HelpLines()
    local way = ns.Way and ns.Way.slash or "/ezway"
    local commands = way ~= "/ezway" and L.HELP_WAY_OR:format(way, "/ezway") or "/ezway"
    local own = { L.HELP_WAY:format(commands, ns.SlashCmd()) }
    for _, line in ipairs(L.CMD_HELP_OWN) do own[#own + 1] = line end
    return Core.HelpLines(ns, own)
end

-- Eigene Befehle neben denen des Gerüsts („optionen“, „status“, „hilfe“): true, wenn erledigt.
local function SlashExtra(cmd, rest)
    if cmd == "way" or cmd == "weg" then
        ns.Way.Command(rest)
    elseif cmd == "flug" or cmd == "flight" or cmd == "flights" or cmd == "flugzeiten" then
        ns.Flights.PrintList()
    elseif cmd == "lehrer" or cmd == "trainer" or cmd == "trainers" then
        ns.Trainers.PrintList()
    elseif cmd == "selten" or cmd == "rare" or cmd == "rares" then
        ns.Rares.GoLast(true)
    elseif cmd == "eingang" or cmd == "eingänge" or cmd == "entrance" or cmd == "entrances" then
        ns.Entrances.PrintList()
    elseif cmd == "bg" or cmd == "schlachtfeld" or cmd == "battleground" then
        ns.Battleground.Diagnose()
    else
        return false
    end
    return true
end

-- Gerüst aus ezCore (Core.ModuleScaffold): Datenbank ezMapDB (accountweit – Flugzeiten gelten für jeden Twink) mit
-- settings und den Tabellen unten, Login (ns.me, ns.RunReady), Befehl /ezmap, Statuszeilen (ns.AddStatusLine,
-- ns.PrintStatus). /way bzw. /ezway bleibt ein eigener Befehl (Way.lua).
--   way          { current, history }      flights      [Route] = Sekunden bei normaler Fluggeschwindigkeit
--   flightNames  [Route] = "Start – Ziel"   hints        gesehene Erklärblasen (Guide.lua)
--   entrances    [Instanz-ID] = { name, map, x, y, raid, n, seen } – selbst betretene Eingänge (Entrances.lua)
--   migrated     [Gebiet] = Kennung der Ablage, in die ezMap den alten Speicher übergeben hat (Discovery.lua)
--   entranceNames [Instanz-Schlüssel] = Name beim Betreten – alt: seit Welle 23 in ezCores Datenbank (Art „instance“),
--                hier nur noch Rückfall ohne gespeicherte Ablage (Entrances.lua)
--   gatherHidden [Art:ID] = true – auf der Karte ausgeblendete Vorkommen (Gather.lua); ezCore erfasst sie weiter
--   mapFilter    [Blatt] = true/false – dynamische Blätter des Baums (Berufslehrer je Titel, Tree.lua)
--   mapMemory    [Gruppe] = { [Blatt] = Wert, ["*"] = { [dyn. Gruppe] = Standard } } – gemerkte Mischung einer Gruppe;
--                _migrated = übernommene alte Schalter
--   routes       [Karte] = { kinds, pts, at, len, t } – je Zone eine gemerkte Route (Route.lua)
--   tracking     [charKey] = { on, order, n, last, at } – Auswahl im Menü „Aufspüren“ je Charakter (TrackingMemory.lua)
--   trackingBlock { at, func, lifted } – Blizzard hat das Einschalten eines Such-Zaubers blockiert (für alle
--                Charaktere, Welle 28; lifted: der Spieler hat „Such-Zauber selbst einschalten“ danach wieder angehakt)
--   settings1911 – Merker der Einstellungs-Prüfung vom 19.11.2026 (ns.MigrateSettings1911);
--                minimapAutoZoomLast = letzte Zeit des Herauszoomens (Haken „Aufspüren“)
--   wayTrackOff29, trackSpellOff29 – Merker der einmaligen Umstellung von Welle 29 (ns.MigrateOptIn29);
--                wayTrackOff29Was, trackSpellOff29Was = true – das war vorher an (Hinweis „beim Update ausgeschaltet“)
--   taxiKnown    [charKey] = { nodes = { [Flugpunkt-ID] = true }, seen = { [Kontinent] = Zeit }, at, src, faction } –
--                bekannte Flugpunkte je Charakter und die Kontinente, auf denen sie erfasst sind, gelesen aus Blizzards
--                Flug- und Weltkarte (FlightNodes.lua, Welle 26)
-- Lehrer stehen seit Welle 2 in ezCore (Core.Npcs); ezMapDB.trainers bleibt liegen, ezCore hat es einmal übernommen.
-- Flugzeiten und selbst betretene Eingänge stehen seit Welle 10 in ezCores Entdecker-Datenbank (ezCore/Datenbank/Discovery.lua);
-- flights, flightNames und entrances bleiben liegen und sind nur noch Rückfall.
-- Welle 29 (NACH-27; Grundsatz des Nutzers vom 17.11.2026, wörtlich „user muss auf sowas hingewiesen werden, er kann
-- es nutzen muss es aber einschalten“): Blizzards Zielverfolgung beim Setzen (wayTrack) und Such-Zauber beim
-- Wiederherstellen des Aufspürens (trackingSpellAuto) sind ab Werk aus. Einmal umstellen wie estimateOff17 in ezCombat,
-- MigrateMailOptIn in ezChat und MigrateAutoSellOptIn in ezBag – ezCores FillDefaults allein ließe ein gespeichertes
-- „an“ stehen:
--   wayTrack: ein gespeichertes „an“ (der alte Standard) wird aus, gemerkt in db.wayTrackOff29Was.
--   Such-Zauber: bisher ohne eigenen Schalter an, solange „Auswahl merken“ an war und Blizzard nicht blockiert hatte –
--     dann db.trackSpellOff29Was (wenn ein Such-Zauber gemerkt war). Hat der Spieler nach einer Sperre „Such-Zauber
--     selbst einschalten“ wieder angehakt (trackingBlock.lifted), hat er es ausdrücklich eingeschaltet: bleibt an.
-- Die Merker wayTrackOff29 und trackSpellOff29 verhindern ein zweites Umstellen; wer danach selbst einschaltet, behält
-- es. → true, wenn etwas umgestellt wurde
local function HadSpell(db)
    for _, rec in pairs(type(db.tracking) == "table" and db.tracking or {}) do
        for key, on in pairs(type(rec) == "table" and type(rec.on) == "table" and rec.on or {}) do
            if on == true and type(key) == "string" and key:sub(1, 1) == "s" then return true end
        end
    end
    return false
end
function ns.MigrateOptIn29(db)
    if type(db) ~= "table" or type(db.settings) ~= "table" then return false end
    -- Seit dem Gesamtreview vom 18.11.2026 (T4-7) über ezCores Core.OptInOnce bzw. Core.MigrateOnce – Merker und
    -- Verhalten wie vorher
    local changed = Core.OptInOnce(db, "wayTrackOff29", { wayTrack = "wayTrackOff29Was" }) ~= nil
    local spell = Core.MigrateOnce(db, "trackSpellOff29", function()
        local block = type(db.trackingBlock) == "table" and db.trackingBlock or nil
        if block and block.lifted == true then
            db.settings.trackingSpellAuto = true
        elseif not block and db.settings.trackingRemember ~= false and HadSpell(db) then
            db.settings.trackingSpellAuto = false
            db.trackSpellOff29Was = true
            return true
        end
    end)
    return changed or spell == true
end

Core.NewModule(ADDON, ns, {
    title = "ezMap",
    -- core: ezCore-Fassung beim Start der Welle 5 (Npcs.IsPetTrainerTitle für Tierausbilder, MAP-18; Menu.Tip für die
    -- Erklärzeilen der Menüs, MAP-19); die Kleinhelfer (W-14) kamen ohne neue Nummer, deshalb stehen sie und die
    -- neuen Helfer zusätzlich in needs.
    -- Entdecker-Datenbank (Welle 9) ebenfalls ohne neue Nummer: DB.AsOwn, Flights.Note/Time, Zones.Levels; Bücher
    -- (Welle 9/10, MAP-07): Books.Where, Books.From, Collections.Books.
    -- 1.15.0: Bausteine aus dem Gesamtreview vom 18.11.2026, u. a. Core.NewTimerBar, Core.OptInOnce, Core.MigrateOnce, Core.TipClick
    -- (Liste je Modul in docs/roadmap/uebergreifend.md, P7)
    core = "1.15.0", needs = { "AfterCombat", "Npcs", "OpenChatWith", "scaffoldHelpers", "Map.XY", "Map.Parent",
        -- Gesamtreview 18.11.2026, P19c (ohne neue Versionsnummer): Ton-Helfer aus ezCore (T16-NM4)
        "PlaySound",
        "Map.WorldPos", "Map.PosOn", "Map.Info", "InInstance", "Uptime", "UnitRank", "Npcs.IsPetTrainerTitle",
        "Menu.Tip", "DB.AsOwn", "DB.Keys.Taxi", "Flights.Note", "Flights.Time", "Zones.Levels",
        "Books.Where", "Books.From", "Collections.Books",
        -- Welle 15 (SAM-11, SAM-21 bis SAM-23): Punkteschicht samt Minikarte, Routen-Rechner, Fortschritt, Sichtungen
        "MapPins.AddProvider", "MapPins.MinimapState", "Route.Build", "Gathering.ProgressLines", "Rares.OnMap",
        -- Welle 16: Baustein „Alle auswählen / Alle abwählen“ für das Menü „Aufspüren“ (TrackingMemory.lua)
        "Menu.SetAll", "Menu.AllToggle",
        -- Welle 22: Wortlaut „Alle auswählen / Alle abwählen“ aus dem Design-System (Gather, Route, Tree)
        "Style.AllText",
        -- Welle 17: Helfer und Texte, die ezCore ohne neue Versionsnummer bekam (tools/texte.lua, Regel 4)
        "More",
        -- Welle 23 (ezCore 23c): eine Stelle vergessen, Abdunkeln mit maxAge, Angelplätze im Filter item, Rohstoffe
        -- der eigenen Ernten (Gather.lua)
        "gatherForgetSpot", "gatherJustMaxAge", "gatherNodesFish", "Gathering.Items", "Gathering.FishAreasFor",
        -- Welle 23 (ezCore 23c): Namen der Instanzen in der Datenbank (Entrances.lua)
        "Discovery.InstanceName",
        -- Welle 27 (modul/ezmap-menue): Symbole und Abschnitte im Menü, Quelle im Tooltip (ohne neue Nummer)
        "Menu.Icon", "Menu.IconMarkup", "Menu.Section",
        -- Funde des code-reviewers und Antwort des Nutzers vom 17.11.2026: Hülle mit Symbol, Berufssymbol, Einfügen
        -- unter Blizzards Eintrag (Menu.IconText braucht ezMap seitdem nicht mehr)
        "Menu.IconRoot", "Menu.ProfessionIcon", "Menu.ProfessionIconOfTitle", "Menu.InsertRoot",
        -- Gesamtreview 18.11.2026 (P13 D2; ezCore ohne neue Versionsnummer): Weg zu einer Einstellung in ezCores Form,
        -- Addon-Fach nach Entscheidung 5, Hilfe, Menüeintrag „Einstellungen …“, Kampfsperre, Zeitbalken, Tooltip-Rollen
        "SettingsPathText", "compartmentMain", "HelpLines", "Menu.Settings", "CombatNotice", "NewTimerBar", "TipLine",
        "TipTitle", "TipText", "TipClick", "TipDoubleLine",
        -- Gesamtreview 18.11.2026 (D3, kern/einheit-rest; ohne neue Nummer): Texthelfer statt Kopien im Modul
        "Word",
    -- Gesamtreview 18.11.2026 (P19a, kern/ssot-helfer; ohne neue Nummer): gemeinsame Helfer statt Kopien
    "MigrateOnce", "OptInOnce", "ICON_FALLBACK" },
    db = "ezMapDB",
    tables = { "way", "flights", "flightNames", "hints", "entrances", "migrated", "entranceNames", "gatherHidden",
        "mapFilter", "mapMemory", "routes", "tracking", "taxiKnown" },
    onLoad = function(db)
        if type(db.way.history) ~= "table" then db.way.history = {} end
        ns.MigrateOptIn29(db)
        ns.MigrateSettings1911(db)      -- Einstellungs-Prüfung vom 19.11.2026
    end,
    login = true,
    -- eine Hilfe-Funktion gibt selbst aus (Framework: slash.help)
    slash = { extra = SlashExtra, help = function() for _, line in ipairs(ns.HelpLines()) do ns.Print(line) end end },
})

-- ns.Enabled(key), ns.Throttle, ns.WhenAddOnLoaded(addon, fn), ns.AfterCombat(fn, key) sowie die Abkürzungen
-- ns.IsSecret, ns.Num, ns.Plain, ns.InCombat und ns.OtherFor(funktion) kommen aus Core.NewModule.

-- Uhr-Schreibweise für Flugzeiten (2:05, 1:02:05; Blizzards Flugkarte zeigt keine Zeiten) aus ezCore.
ns.Clock = Core.Clock

---------------------------------------------------------------------------
-- Karte und Position
---------------------------------------------------------------------------

-- Eigene Position (uiMapID, x, y von 0 bis 1 oder nil) und Kartenname („#id“, wenn unbekannt) kommen aus
-- ezCore (ezCore/Kern/Util.lua), gemeinsam mit ezPanel.
ns.PlayerPosition = Core.PlayerPosition
ns.MapName = Core.MapName

-- Weltposition (Kontinent, x, y in Metern) zu einem Kartenpunkt – für Entfernungen über Zonengrenzen hinweg
-- (nächster Lehrer, nächster Flugmeister). nil, wenn der Client sie nicht liefert. Weiterleitung auf ezCore
-- (Core.Map.WorldPos, W-14); der Name bleibt für Trainers.lua, Flights.lua und Entrances.lua.
function ns.WorldPos(mapID, x, y) return Core.Map.WorldPos(mapID, x, y) end

-- „45.3, 32.1“ wie auf Blizzards Karte und bei /way (x, y von 0 bis 1; eine Nachkommastelle) aus ezCore.
function ns.CoordText(x, y) return Core.CoordText(x, y, 1) end

---------------------------------------------------------------------------
-- Rücksicht auf fremde Addons (Liste in docs/fremd-addons.md)
---------------------------------------------------------------------------

-- Erkannt wird über ezCore (ezCore/Wissen/OtherAddOns.lua, gefragt über ns.OtherFor aus dem Gerüst): Name des Addons, das die
-- Funktion übernimmt, sonst nil.
-- Neue Erkennungen gehören dorthin, nicht hierher.

-- Zeigt ein anderes Addon die Flugzeiten schon (Leatrix Plus „Show flight times“, InFlight)? Dann lernt
-- ezMap nur still mit und zeichnet nichts.
function ns.FlightTimesElsewhere() return ns.OtherFor("flightTimes") end

-- Questie zeigt alle Lehrer auf der Karte (Questie-Menü → Stadtbewohner); ezMap bietet sie nur als Ziel an.
function ns.TrainersElsewhere() return ns.OtherFor("mapTrainers") end

-- Zeichnet ein anderes Addon Dungeoneingänge auf die Karte (Forever Tweaks)? Dann zeichnet ezMap keine eigenen
-- Symbole (Entrances.lua), bietet die Eingänge aber weiter als Ziel im Kartenmenü an und nennt das andere Addon dort.
function ns.EntrancesElsewhere() return ns.OtherFor("dungeonEntrances") end

-- Wer /way schon belegt (TomTom) – nur für die Meldung; ob /way frei ist, prüft Core.AddSlashAlias selbst.
function ns.WayElsewhere() return ns.OtherFor("way") end

-- Was andere Addons auf der Karte zeichnen, wofür ezMap dann keine eigenen Symbole setzt (für /ezmap status):
-- Flugpunkte (Forever Tweaks), Dungeoneingänge (Forever Tweaks). Koordinaten gehören nicht mehr dazu: Die zeigt
-- ezMap seit dem Umzug aus ezPanel selbst (MapCoords.lua, eigene Statuszeile samt Rücksicht „mapCoords“).
ns.MAP_FEATURES = { "flightPoints", "dungeonEntrances" }

function ns.MapFeaturesElsewhere()
    local list = {}
    for _, feature in ipairs(ns.MAP_FEATURES) do
        local who = ns.OtherFor(feature)
        if who then list[#list + 1] = { feature = feature, who = who } end
    end
    return list
end

---------------------------------------------------------------------------
-- Login: Klasse und Fraktion
---------------------------------------------------------------------------

-- Klasse und Fraktion erfasst ezCore beim Einloggen (Core.me, vor den Modulen); das Gerüst setzt ns.me und ruft
-- ns.RunReady. Dieser Zuhörer ist der erste des Moduls (Core.lua lädt nach Locale.lua zuerst): Flugmeister und
-- Lehrer richten sich nach Klasse und Fraktion.
ns.OnReady(function()
    ns.me = ns.me or Core.me
    ns.playerClass = ns.me and ns.me.class or Core.PlayerClass()
    ns.faction = ns.me and ns.me.faction or nil
end)

-- Statuszeilen (ns.AddStatusLine, ns.PrintStatus mit der Kopfzeile ns.StatusHeader()) und der Befehl /ezmap
-- (ns.HandleSlash; /way bzw. /ezway stehen in Way.lua) kommen aus dem Gerüst.

---------------------------------------------------------------------------
-- Schnittstelle für andere Module: ezCore.API("ezMap") (README, Abschnitt ezMap)
---------------------------------------------------------------------------

ns.API = {
    -- Blizzards Kartenmarkierung setzen; x, y von 0 bis 1 wie bei Blizzard. Rückgabe: true oder false, Fehlertext.
    -- opts (Welle 27, für ezQuests Leveling-Route; freiwillig): { owner = Kennung, label = Name des Besitzers für Texte,
    -- quiet = true (im Kampf keine Chatzeile; der Pfeil kommt nach dem Kampf), noHistory = true (kein Eintrag in
    -- „Zuletzt“), track = false (nur die Markierung, Blizzards Zielverfolgung unberührt – für ein Weiterrücken ohne Klick;
    -- auch ein im Kampf wartender Pfeil-Wunsch verfällt) bzw. "auto" (Zielverfolgung einschalten, eine Ablehnung aber
    -- höchstens einmal je Sitzung melden) }. Die Zielverfolgung gibt es in jedem Fall nur mit ezMaps Schalter
    -- „Zielverfolgung einschalten“ (wayTrack, ab Werk aus seit Welle 29). Eine Markierung
    -- mit Besitzer lässt die Ankunft stehen (Arrive.lua), und ezMaps Sammel-Route rückt nicht weiter, solange sie einem
    -- anderen gehört. Ohne opts wie vorher.
    SetWaypoint = function(uiMapID, x, y, title, opts)
        if type(opts) == "table" then return ns.Way.Set(uiMapID, x, y, title, nil, opts.quiet, opts) end
        return ns.Way.Set(uiMapID, x, y, title)
    end,
    -- Schaltet ezMap beim Setzen Blizzards Zielverfolgung (Pfeil) ein? true | false – ezMaps Schalter „Zielverfolgung
    -- einschalten“ (wayTrack, ab Werk aus seit Welle 29). Für Texte nach einem Klick in anderen Modulen (ezQuests
    -- Leveling-Route sagt dann, wie der Pfeil kommt; Fund der Gegenprüfung vom 17.11.2026).
    WaypointTracking = function() return ns.Enabled("wayTrack") end,
    -- Weg zu diesem Schalter in ezCores Form (Core.SettingsPathText, Gesamtreview T18-18) – für Texte in anderen
    -- Modulen, die auf ihn verweisen (ezQuests Leveling-Route); Abschnitt und Name aus ezMaps eigenen Texten.
    WaypointTrackingPath = function() return Core.SettingsPathText("ezMap", "OPT_HEADER_WAY", "OPT_wayTrack", L) end,
    ClearWaypoint = function() return ns.Way.Clear() end,
    -- uiMapID, x, y, title der aktuellen Markierung oder nil
    GetWaypoint = function() return ns.Way.Get() end,
    -- Gehört die gesetzte Markierung diesem Besitzer (aus SetWaypoint mit opts.owner)? true | false (Welle 27)
    OwnsWaypoint = function(owner) return ns.Way.OwnedBy(owner) end,
    -- Besitzer und Name der gesetzten Markierung oder nil (Welle 27)
    WaypointOwner = function() return ns.Way.Owner() end,
    -- Linie eines Wegs auf Blizzards Weltkarte (Welle 27, für ezQuests Leveling-Route): points = { { map, x, y } … } in
    -- Reihenfolge (jede Karte; gezeichnet wird auf der gezeigten Karte, umgerechnet über Core.Map.PosOn), opts =
    -- { color = { r, g, b, a } }. Je Besitzer ein Weg; ClearPath nimmt ihn weg. Rückgabe: Zahl der Punkte bzw. true.
    -- Ein Punkt mit icon (Datei oder Datei-ID) bzw. atlas steht zusätzlich als Symbol auf der Weltkarte, label ist
    -- sein Tooltip (etwa ein Sammel-Abstecher mit dem Symbol des Berufs). Seit dem Spielbefund vom 18.11.2026 trägt jeder
    -- Punkt seine Nummer (Tooltip label), Pfeile zeigen die Laufrichtung; weitere opts: fromPlayer = true (der Weg
    -- beginnt an deinem Ort und folgt dir bei offener Karte, dann reicht ein Punkt), next = Nummer des hervorgehobenen
    -- Punkts (Standard 1), marks = false (ohne Nummern). Seit dem Spieltest vom 19.11.2026: family = Farbfamilie
    -- ("gold" ab Werk, "blue" ist die Sammel-Route), name und addon für den Tooltip („Leveling-Route (ezQuest)“), je Punkt
    -- target (Ziel neben der Marke des nächsten Schritts); Nummern an den übrigen Schritten nur mit ezMaps Schalter
    -- routeNumbers.
    ShowPath = function(owner, points, opts) return ns.Route.ShowPath(owner, points, opts) end,
    ClearPath = function(owner) return ns.Route.ClearPath(owner) end,
    -- Kleiner Pfeil auf der Minikarte zum nächsten Schritt (Spieltest 19.11.2026, für ezQuests Leveling-Route):
    -- point = { map, x, y }, opts = { family } (Farbfamilie wie bei ShowPath, ab Werk "gold"); je Besitzer ein Ziel,
    -- ClearMiniArrow nimmt es weg (ns.MiniArrow, MiniArrow.lua). Den Schalter führt das Modul der Route.
    ShowMiniArrow = function(owner, point, opts) return ns.MiniArrow.Show(owner, point, opts) end,
    ClearMiniArrow = function(owner) return ns.MiniArrow.Clear(owner) end,
    -- Gemerkte Lehrer (Kopien): kind = "class" (eigene Klasse) | "profession" | "pet" (Tierausbilder) | "other" | nil (alle)
    Trainers = function(kind) return ns.Trainers.List(kind) end,
    -- Nächster gemerkter Lehrer auf demselben Kontinent oder nil
    NearestTrainer = function(kind) return ns.Trainers.Nearest(kind) end,
    -- Markierung auf den nächsten gemerkten Lehrer setzen, still, auch im Kampf (Welle 23; ezPanel und ezMerchant
    -- behalten ihre Texte). Nur eine Ablehnung der Zielverfolgung durch Blizzard nennt ezMap im Chat.
    -- Rückgabe: true, Name, Ort, Eintrag | false, "none" | "nopos" | "failed" (dritter Wert: Fehlertext)
    GoToNearestTrainer = function(kind) return ns.Trainers.GoNearest(kind) end,
    -- Koordinaten auf der Weltkarte (deine Position und der Mauszeiger, MapCoords.lua). Gibt es diese Funktion, bietet
    -- ezMap die Zeile an – ezPanel zeigt seine eigene dann nicht mehr. Rückgabe: true (ezMap zeichnet) |
    -- false, "off" (Schalter aus) | false, "other", Name (ein anderes Addon zeigt sie, z. B. Leatrix Maps).
    MapCoords = function() return ns.MapCoords.State() end,
    -- Schalter „Koordinaten auf der Weltkarte“ setzen (ezPanel reicht seinen Menüpunkt weiter und übergibt seine
    -- Einstellung einmal). Rückgabe wie MapCoords().
    SetMapCoords = function(on) return ns.MapCoords.Set(on) end,
    -- Sammel-Fundorte zeigen (SAM-14; für ezCraft und ezPanel): öffnet die Weltkarte der besten Zone mit gesetztem
    -- Filter und markiert den nächsten Punkt. opts = { gegenstand | item = itemID oder Link, art | kind = "herb" |
    -- "ore" | "fish" | "chest", karte | map = uiMapID (sonst deine Zone bzw. die mit den meisten eigenen Fundorten) }.
    -- Ein Gegenstand findet Spielobjekte und Angelplätze (über die Fang-Gebiete); Kisten nur, wenn der Spieler sie
    -- will (ezMaps Haken „Kisten“ oder ezCores „Entdecker-Wissen“). Eine Welt- oder Kontinentkarte als karte heißt:
    -- die Zone darunter mit den meisten Fundorten.
    -- Rückgabe: true, { map, x, y, name, count, other (zeichnet ein Sammel-Addon), later (im Kampf: Karte danach),
    -- marked (Markierung gesetzt; false auf Karten ohne Markierung), markError (Text dazu) }
    -- oder false, Grund ("args" nichts gesucht | "kind" unbekannte Art | "explorer" Kisten nicht gewünscht |
    -- "none" kein eigener Fundort bekannt | "nomap" Weltkarte nicht zu öffnen | "nocore" ezCore ohne Fundort-Dienst).
    ShowGather = function(opts) return ns.Gather.Show(opts) end,
}

-- Addon-Fach an der Minikarte (EC-87: alle drei Compartment-Zeilen in jeder TOC). Entscheidung 5 vom 18.11.2026
-- (T18-3): ezMap hat kein eigenes Fenster (es erweitert Blizzards Karte) – jeder Klick öffnet die Einstellungsseite
-- (sonst die Hilfe im Chat); Tooltip und Befehlszeile mit dem geltenden Befehl baut ezCore.
ezMap_OnAddonCompartmentClick, ezMap_OnAddonCompartmentEnter, ezMap_OnAddonCompartmentLeave =
    Core.CompartmentHandlers({ ns = ns, title = ADDON, owner = ADDON })
