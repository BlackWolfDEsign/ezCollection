local ADDON, ns = ...
local L = ns.L

--[[
    ezMerchant – Händler und Lehrer im Originalstil.
      Merchant.lua  Blizzards Händlerfenster: breiter, Suche, Filter, Stapel kaufen, Bekanntes und Fehlendes markieren
      Repair.lua    automatisch reparieren (auch mit Gildengeld; vorher in ezPanel; ausgeführt von ezCore)
      Junk.lua      Plunder verkaufen: Knopf und Schalter im Menü „Filter“ (mit ezBag nach dessen Regeln, sonst Graues);
                    Zeile „im Auktionshaus mehr wert“ unter dem Händlerfenster mit „Trotzdem verkaufen“ (AH-27)
      Restock.lua   „Vorrat auffüllen (Kosten)“: Sollmengen je Charakter, kauft beim Händler nach
      VendorTip.lua Tooltip des Händlers: was dort für diesen Charakter wartet (Sortiment aus ezCores Datenbank)
      Trainer.lua   Lehrerfenster: „Alles lernen (Kosten)“; was beim Lehrer wartet
      LevelUp.lua   Chat-Block beim Stufenaufstieg: neue Ränge, Dungeons im Stufenbereich, jetzt tragbare Teile,
                    nächster Talentpunkt (ezTalent)
      PetTrainer.lua Tierausbilder des Jägers: Hinweis „Begleiter kann X noch nicht“, bekannte Ränge abgedunkelt,
                    Knopf „Wildtierausbildung“ (Core.SecureButton)
      Spellbook.lua Zauberbuch: Seitenreiter „Was kommt wann“ schlägt eine eigene Ansicht im Buch auf
                    (die Ansicht baut ezCore: Core.NewSpellbookView; hier nur Zeilen und Texte), mit ezMap
                    der Eintrag „Lehrer auf der Karte zeigen“
      Tour.lua      Rundgang mit Erklärblasen beim ersten Öffnen (Core.NewTour)
      Options.lua   Einstellungsseite unter „ezCollection“
    Lehrerdaten kommen aus dem Zauber-Wissen von ezCore (Core.Spells, lernt bei jedem Lehrerbesuch).
]]

ns.DEFAULTS = {
    -- Händlerfenster
    merchant = true,        -- Warenliste übernehmen (aus: Blizzards Original)
    columns = 4,            -- 2 = Blizzards Breite
    rows = 5,               -- 5 = Blizzards Höhe
    -- „Bekanntes markieren“ ist seit der Einstellungs-Prüfung vom 19.11.2026 (Nr. 7) immer an (kein Schalter mehr;
    -- ein gespeicherter Wert markKnown bleibt unbeachtet liegen)
    markMissing = true,     -- Stern: fehlt der Sammlung (Item-Wissen „Sammlungen“ von ezCore)
    markUpgrade = true,     -- Pfeil: besser als angelegt (Bewertung und Pfeil von ezGear; ohne ezGear ohne Wirkung)
    stackButton = true,
    vendorTip = true,       -- Tooltip des Händlers: Sortiment laut deinem letzten Besuch (VendorTip.lua, Vorschlag V3)
    -- Filter der Warenliste: nur im Menü am Knopf „Filter“ des Händlerfensters (seit der Einstellungs-Prüfung vom
    -- 19.11.2026 nicht mehr auf der Einstellungsseite); der Wert bleibt bis zum nächsten Umschalten
    filterUsable = false,
    filterKnown = false,
    filterAffordable = false,
    filterMissing = false,
    filterUpgrade = false,  -- nur Verbesserungen (ezGear)

    -- Reparatur (repairAuto, repairGuild, repairReport) und Plunder (autoSellJunk) sind seit der Einstellungs-Prüfung
    -- vom 19.11.2026 gemeinsame Schalter in ezCore (ns.SHARED unten) – ihre Standardwerte stehen dort (ab Werk aus)
    -- Auktionswert (Junk.lua, AH-27; Rechnung, Schwelle und Goldmünze kommen aus ezCore, Core.Prices.WorthMark)
    auctionWorth = true,    -- Zeile „n Gegenstände im Auktionshaus mehr wert“ unter dem offenen Händlerfenster
    keepAuctionWorth = true, -- Plunder-Verkauf lässt sie aus (skipAuctionWorth; Frage AH-13 (1): Empfehlung umgesetzt)

    -- Vorrat (Restock.lua)
    restock = true,         -- Knopf „Vorrat auffüllen (Kosten)“ und Sollmengen
    restockAuto = false,    -- beim Öffnen des Händlers von selbst auffüllen (ab Werk aus)

    -- Lehrer
    learnAll = true,        -- Knopf „Alles lernen (Kosten)“ im Lehrerfenster
    upcoming = true,        -- Seitenreiter „Was kommt wann“ am Zauberbuch
    levelHint = true,       -- beim Stufenaufstieg: neue Ränge beim Lehrer
    spellNames = true,      -- Meldungen „Neu beim Lehrer“ und „… gelernt“ nennen die Zauber (Wunsch vom 15.11.2026)
    levelDungeons = true,   -- beim Stufenaufstieg: Dungeons, die mit dieser Stufe in den Bereich kommen
    levelGear = true,       -- beim Stufenaufstieg: Ausrüstung aus Taschen und Bank, die jetzt tragbar ist
    levelTalent = true,     -- beim Stufenaufstieg: nächster Talentpunkt laut ezTalent (NEU-02)
    petHint = true,         -- Tierausbilder: „Begleiter kann X noch nicht“, bekannte Ränge abgedunkelt
    petTrain = true,        -- Tierausbilder: sicherer Knopf „Wildtierausbildung“ (öffnet Blizzards Fenster)
}

ns.LIMITS = { columns = { 2, 5 }, rows = { 5, 7 } }

---------------------------------------------------------------------------
-- Helfer: die allgemeinen kommen aus ezCore (eine Umsetzung für alle Module)
---------------------------------------------------------------------------

local Core = ezCore

-- Befehle über die Standard-Befehle des Gerüsts hinaus (Optionen, Status, Hilfe): „/ezh reparieren“, „/ezh vorrat“.
local REPAIR_WORDS = { reparieren = true, repair = true, reparatur = true }
local RESTOCK_WORDS = { vorrat = true, restock = true, sollmengen = true }
local function ExtraCommand(cmd)
    if RESTOCK_WORDS[cmd] and ns.Restock then
        ns.Restock.PrintList()
        return true
    end
    if not REPAIR_WORDS[cmd] then return false end
    ns.API.RepairNow()
    return true
end

-- Gerüst aus ezCore (Core.ModuleScaffold): Datenbank ezMerchantDB mit den Tabellen „migrated“ (einmalige
-- Übernahmen, Repair.lua), „hints“ (gesehene Erklärblasen, Tour.lua) und „restock“ (Sollmengen je Charakter,
-- Restock.lua), Login (ns.charKey, ns.realm, ns.me,
-- ns.RunReady), Befehl /ezmerchant mit den Kurzbefehlen /ezh bzw. /ezvendor (nur, wenn frei) und der Status
-- (ns.AddStatusLine, ns.StatusLines, ns.PrintStatus).
-- ezCore 1.12.0 bringt die Reparatur (Core.Durability.RepairAll, MER-01), den Plunder-Verkauf (Core.Junk.Sell,
-- MER-02) und Core.Menu.Tip.
Core.NewModule(ADDON, ns, {
    -- 1.15.0: Bausteine aus dem Gesamtreview vom 18.11.2026, u. a. Core.AtlasTexCoord, Core.Durability.ReportText, Core.ItemIconText, Core.SlashCmd
    -- (Liste je Modul in docs/roadmap/uebergreifend.md, P7)
    title = "ezMerchant", core = "1.15.0", needs = { "scaffold", "scaffoldHelpers", "ItemCount", "SecureButton", "AddSelfTest", "UnitPresent",
        "Durability.RepairAll", "Junk.Sell", "Menu.Tip", "Plural", "Style.SetStrata",
        -- Gesamtreview 18.11.2026, P19c (ohne neue Versionsnummer): Reparatur-Meldung aus ezCore (T16-12)
        "Durability.ReportText",
        -- Welle 17: Helfer und Texte, die ezCore ohne neue Versionsnummer bekam (tools/texte.lua, Regel 4)
        "More",
        -- Welle 23 (ezCore 1.13.0 ohne neue Versionsnummer): Liste „kommt später“ mit Stufen laut Client (A44),
        -- spellID eines Lehrer-Eintrags (A45)
        "Spells.BookEntries", "TrainerSpellID",
        -- Welle 26 (ezCore 1.13.0 ohne neue Versionsnummer): Lernstufen und Ränge laut Client-Tabellen (wago F3)
        "Spells.ClientComing", "ClientData.SourceText",
        -- Welle 27 (ezCore 1.13.0 ohne neue Versionsnummer): offene Einträge der Client-Tabellen aus einer Rechnung
        "Spells.OpenTableEntries",
        -- Oberflächen-Einheit (Gesamtreview 18.11.2026, P13 D2; ezCore ohne neue Versionsnummer): Addon-Fach und Befehl
        -- nach Entscheidung 5, Zurücksetzen mit Rückfrage, Menüeintrag „Einstellungen …“, Tooltip-Rollen, Weg zur
        -- Einstellung, Tooltip am gesperrten Knopf
        "compartmentMain", "slashMain", "SlashCmd", "Menu.Settings", "TipLine", "TipTitle", "TipText", "TipDoubleLine",
        "SettingsPathText", "Toolbar.ShowTipWhileDisabled",
        -- Gesamtreview 18.11.2026 (D3, kern/einheit-rest; ohne neue Nummer): Texthelfer statt Kopien im Modul,
        -- Kampfsatz über ezCore (Plunder im Kampf, Gegenprüfung D3), Zauberbuch-Zeilen { text, rolle } („Was kommt wann“)
        "Word", "CombatNotice", "spellbookTipRoles",
    -- Gesamtreview 18.11.2026 (P19a, kern/ssot-helfer; ohne neue Nummer): gemeinsame Helfer statt Kopien
    "PlaySound", "AtlasTexCoord",
    -- Einstellungs-Prüfung 19.11.2026 (ezCore ohne neue Versionsnummer): gemeinsame Schalter mehrerer Module
    "ShareSettings", "AdoptModuleShared", "SharedOn", "Junk.AdoptPanelRepair" },
    db = "ezMerchantDB", tables = { "migrated", "hints", "restock" }, login = true,
    -- alte Werte der gemeinsamen Schalter einmal an ezCore (ns.SHARED unten; ein „an“ bleibt an)
    onLoad = function(db) Core.AdoptModuleShared(ns, db) end,
    -- Kurzbefehle /ezh bzw. /ezvendor (nur, wenn frei) aus Core.SLASH_ALIASES; ohne Wort repariert der Befehl wie der
    -- Linksklick im Addon-Fach (Entscheidung 5 vom 18.11.2026), „zuruecksetzen“ fragt wie der Knopf (T9-3)
    slash = { extra = ExtraCommand, main = function() ns.API.RepairNow() end, mainText = L.COMPARTMENT_MAIN,
        reset = true },
})

-- Gemeinsame Schalter (Einstellungs-Prüfung 19.11.2026; Entscheidung des Nutzers „Ja, alle umsetzen“): „Plunder beim
-- Händler verkaufen“ ist EIN Schalter mit ezBag (Nr. 59/60), „Automatisch reparieren“ samt Gildengeld und Meldung EIN
-- Schaltersatz mit ezPanel (Nr. 62) – beide in ezCore (Gruppe vendor), ab Werk aus. ns.Enabled/ns.SetSetting, die
-- Kästchen der Seite (Spiegel), die Häkchen am Händlerfenster und das Menü „Filter“ führen dorthin. old = ezMerchants
-- früherer Standard: ein gespeicherter Wert gleich old ist keine Wahl und wird nicht übernommen.
ns.SHARED = Core.ShareSettings(ns, {
    autoSellJunk = { "vendor", "autoSell", old = false },
    repairAuto = { "vendor", "repairAuto", old = false },
    repairGuild = { "vendor", "repairGuild", old = false },
    repairReport = { "vendor", "repairReport", mode = "first", old = true },
})

ns.Money = Core.Money
-- ns.Enabled(key), ns.Throttle(fn, delay), ns.WhenAddOnLoaded(addon, fn) und die Abkürzungen ns.IsSecret, ns.Num,
-- ns.InCombat, ns.OtherFor(funktion) kommen aus Core.NewModule (scaffoldHelpers).

-- Zeilen für Tooltip-Tabellen, die ezCores Zauberbuch-Ansicht zeichnet: { text, rolle } – die Farbe setzt ezCore über
-- Core.TipLine („hint“ = Quelle und Hinweis in ezCores Grau), nie eine Zahl im Modul (Gesamtreview 18.11.2026, T9-6;
-- vorher der Rekorder ns.TipRow).

-- Zahl einer Einstellung, in ihre Grenzen gezwungen (alte oder von Hand geänderte Werte).
function ns.Setting(key)
    local value = ns.S and tonumber(ns.S[key]) or ns.DEFAULTS[key]
    local limits = ns.LIMITS[key]
    if limits then value = math.max(limits[1], math.min(limits[2], math.floor(value))) end
    return value
end

---------------------------------------------------------------------------
-- Schnittstelle für andere Module: ezCore.API("ezMerchant")
---------------------------------------------------------------------------

--[[
    AutoRepair()        → an, mitGildengeld, anderes (drei Booleans; anderes = true: ein anderes Addon repariert),
                          dazu als vierter Wert dessen Name (sonst nil)
    RepairNow(useGuild) → true, wenn repariert wurde (useGuild nil: Einstellung von ezMerchant)
    RepairBy()          → Name des Addons, das automatisch repariert (ns.OtherFor("repair")), sonst nil
    Leatrix()           → früherer Name: true, wenn ein anderes Addon repariert (dann repariert ezMerchant nicht)
    OpenSettings()      → öffnet die Einstellungsseite
    KeepAuctionWorth()  → true, solange ezMerchants Plunder-Verkauf Gegenstände mit ezCores Goldmünze „im Auktionshaus
                          mehr wert“ auslässt (Einstellung keepAuctionWorth) – für ezBags eigene Automatik (AH-27)
    ShowKept(liste)     → zeigt behaltene Gegenstände ({ { bag, slot, itemID, count } } wie Core.Junk.Sell sie
                          zurückgibt) in ezMerchants Zeile mit „Trotzdem verkaufen“; → true, wenn die Liste etwas enthielt
    ShowsNextPoint()    → true, solange ezMerchants Block beim Stufenaufstieg die Zeile „Nächster Talentpunkt“ zeigt
                          (Einstellung levelTalent und ezTalents Zusage API.NextPointChecksFree); dann schweigt
                          ezTalents eigene Zeile (NEU-02, LevelUp.lua)
    Die Funktionen setzt Repair.lua bzw. Options.lua; ezPanel zeigt damit an und repariert nicht doppelt.
]]
ns.API = {}

---------------------------------------------------------------------------
-- Status und Slash-Befehle: aus dem Gerüst von ezCore (siehe Core.NewModule oben)
---------------------------------------------------------------------------
-- ns.AddStatusLine(fn → Text oder nil): Teile tragen Zeilen für /ezh status ein; ns.StatusLines() → Liste;
-- ns.PrintStatus() schreibt Kopf (ns.StatusHeader()) und Zeilen in den Chat. ns.HandleSlash(input) versteht ohne Wort
-- „jetzt reparieren“ (slash.main), „optionen“, „status“, „hilfe“, „zuruecksetzen“ und über ExtraCommand „reparieren“
-- und „vorrat“; ns.PrintHelp() zeigt ezCores Kopf und L.CMD_HELP_OWN (Core.HelpLines).

---------------------------------------------------------------------------
-- Addon-Fach an der Minikarte (TOC: AddonCompartmentFunc …; Tooltip und Klick über ezCore.CompartmentHandlers)
---------------------------------------------------------------------------

-- Entscheidung 5 vom 18.11.2026 (T18-3, T16-10): Linksklick = Hauptfunktion – beim offenen Händler jetzt reparieren
-- (vorher Rechtsklick, V-124) –, Rechtsklick = Einstellungen. Tooltip und Befehlszeile baut ezCore.
ezMerchant_OnAddonCompartmentClick, ezMerchant_OnAddonCompartmentEnter, ezMerchant_OnAddonCompartmentLeave =
    Core.CompartmentHandlers({
        ns = ns, title = L.TITLE, main = function() ns.API.RepairNow() end, mainText = L.COMPARTMENT_MAIN,
        owner = ADDON,
    })
-- früherer Name des Klicks (Prüfungen): dieselbe Belegung wie das Addon-Fach
function ns.CompartmentClick(button) return ezMerchant_OnAddonCompartmentClick(nil, button) end
