local ADDON, ns = ...
local L = ns.L
local Core = ezCore

-- TOC „## OptionalDeps: ezBars“ – Grund nach der Regel für OptionalDeps (docs/ezcore.md, „Gerüst-Dienste“;
-- Gesamtreview 18.11.2026, T4-8): keiner der Gründe (a)–(c) belegt, Kandidat „nur Erkennung“. ezMacro meldet seine
-- Emote-Leisten erst im Bereit-Rückruf über ezCore.API("ezBars").RegisterBar an (EmoteBar.lua), und ezBars legt die
-- Unterseiten früher angemeldeter Leisten beim Bau seiner Einstellungsseite nach (ezBars/Options.lua) – die
-- Ladereihenfolge ist also nicht nötig. Der Eintrag entfällt erst nach der Spielprüfung, weil sich die Ladereihenfolge
-- ändert (docs/roadmap/ezMacro.md, „Im Spiel prüfen“).

ns.DEFAULTS = {
    pickupAfterImport = true,
    hideUnknown = false,
    scopeMode = "auto",        -- auto | char | account
    autoThank = false,
    autoSpit = false,
    autoStyle = "emote",       -- emote | text
    spitAnimation = false,     -- Spucken mit Ziel: erst Blizzards Spucken ohne Ziel (Animation), dann der Satz (Emote.lua)
    thankCooldown = 10,        -- Minuten pro Spieler
    spitCooldown = 5,          -- Minuten pro Spieler
    globalCooldown = 60,       -- Sekunden zwischen zwei automatischen Emotes
    openWorldOnly = true,
    thankAfterCombat = true,
    announce = false,
    barShown = true,           -- Emote-Leisten über ezBars (Emotes je Leiste: ezMacroDB.bars, Zahnrad an der Leiste)
    chatButton = true,         -- ezMacro-Knopf in Blizzards Knopfleiste am Chat
    backupOnLogout = true,     -- eigene Makros beim Ausloggen sichern (Werkzeug „Makros sichern“)
    profileMacros = true,      -- Leisten-Profile: fehlende Makros mit anlegen
    profileBindings = false,   -- Leisten-Profile: Tastenbelegung mit übernehmen
    profileClearEmpty = false, -- Leisten-Profile: Plätze leeren, die im Profil leer sind
    rankAuto = false,          -- Ränge nach dem Lernen automatisch aktualisieren (nach dem Kampf)
    rankGlow = true,           -- Aktionsknöpfe mit altem Rang leuchten (ezCore.ActionHighlight, Art „rank“: Orange)
    announceMode = "auto",     -- Ansagen: auto (Kanal beim Klick wählen) | fixed (Blizzards Befehl im Makro)
    announceBar = true,        -- Ansage-Leiste unter Blizzards Raid-Verwaltung (AnnounceBar.lua)
    announceMenu = true,       -- Eintrag „Ansage“ in Blizzards Rechtsklick-Menüs der Einheiten (AnnounceMenu.lua)
    oneClickUpdate = true,     -- Ein-Klick-Makros mit dem besten Gegenstand aktuell halten (OneClick.lua)
    fishingKey = false,        -- Angeln mit einer Taste: Interaktionstaste wirft aus (Fishing.lua)
    -- Helfer „Eine Taste“ (OneKey.lua, Reiter „Ein-Klick“): je Helfer aktuell halten
    oneKeyConjure = true,      -- Herbeizaubern oder benutzen (Magier, Hexenmeister)
    oneKeyQuest = true,        -- Questgegenstand
    oneKeyOpen = true,         -- Öffnen und Entzaubern (Entzaubern nur, was du angehakt hast)
    oneKeyPet = true,          -- Begleiter je Zustand (Hexenmeister, Jäger)
    petDemon = "imp",          -- Hexenmeister: Dämon der Begleiter-Taste (imp | voidwalker | succubus | felhunter)
    macroKinds = true,         -- Makros nach Art in Blizzards Makroverwaltung: Knopf „Art“, Abblenden, Tooltip (Kinds.lua)
    macroFromSpells = true,    -- Gruppe „Aus deinen Fähigkeiten“ im Reiter „Makros“ (SpellMacros.lua, Welle 27)
}

-- „Allem zustimmen“ (ezCore, Werkzeuge/FirstStart.lua: Intro.Registered; Spieltest 20.11.2026): jeder Schalter oben,
-- der ab Werk aus ist und kein Ablauf ohne Klick (die stehen in Intro.CONSENT). "on": mit der Zustimmung gesetzt;
-- "risk": bleibt aus, riskiert Blizzards Regeln oder Schutz; "choice": Geschmack, Filter, Leitlinie 9 oder 11.
-- tools/Tests/agree_test.lua prüft, dass jeder neue Schalter mit false hier oder in Intro.CONSENT steht.
-- risk hier: „Animation + Text“ sendet beim automatischen Spucken (autoSpit) ein zweites Emote ohne Klick
ns.AGREE = {
    spitAnimation = "risk", announce = "on", fishingKey = "choice", hideUnknown = "choice", profileBindings = "choice",
    profileClearEmpty = "choice",
}

-- Kategorien der Einträge (Feld category; gemerkte Anpassungen und Auswahl hängen daran).
-- „custom“: eigene Vorlagen (Custom.lua), „tools“: Werkzeuge wie Sichern und Leisten-Profile (Tools.lua),
-- „announce“: Ansagen für Anführer (Data\Announce.lua, Announce.lua) mit den Gruppen Dungeon, Raid und PvP.
-- „oneclick“: Ein-Klick-Makros (Data\OneClick.lua, OneClick.lua) – Essen, Trinken, Verband, Heiltrank, Reittier,
-- Ruhestein und die Helfer „Eine Taste“.
-- „spells“: Makros aus deinen Fähigkeiten (SpellMacros.lua, Welle 27) – erzeugt je Charakter, Gruppe = Klasse, nur in
-- „Für mich“ (eigene Gruppe hinter den Vorlagen), nicht in ns.MACROS.
-- „general“ hat zwei Gruppen: „general“ (die Einträge aus Data\General.lua, ohne eigenes Feld group) und „clickheal“
-- (Heilen und Buffen per Klick, ClickCast.lua). „heal“: ezHeals Heil-Makros (HealMacros.lua, nur mit ezHeal).
ns.CATEGORIES = { "class", "race", "general", "oneclick", "emote", "announce", "custom", "tools" }
ns.GENERAL_GROUPS = { "general", "clickheal" }
ns.ANNOUNCE_GROUPS = { "dungeon", "raid", "pvp" }

-- Reiter nach Entwurf A (Frage 14, entschieden 16.11.2026: „Frage 1: Entwurf A“): vier Reiter nach Zweck, jeder zeigt
-- über seine Auswahl oben eine oder mehrere Kategorien.
--   macros    ein Makro holen: „Für mich“ (eigene Klasse, eigenes Volk, Allgemein, Eigene), Klasse, Volk, Allgemein,
--             Heilen und Buffen per Klick, nur Eigene, ezHeals Heil-Makros (nur mit ezHeal); dazu die Auswahl „Art“
--   oneclick  eine Taste, die das Richtige tut: Ein-Klick-Makros, Helfer „Eine Taste“, Angeln mit einer Taste
--   chat      im Chat etwas sagen: Emotes, Ansagen Dungeon, Raid, PvP
--   tools     aufräumen: Ränge, Sichern, ohne Leiste, lange Makros, Leisten-Profile, Kleine Helfer
ns.TABS = { "macros", "oneclick", "chat", "tools" }
ns.TAB_INDEX = {}
for index, tab in ipairs(ns.TABS) do ns.TAB_INDEX[tab] = index end
ns.TAB_VIEWS = {
    macros = { "mine", "class", "race", "general", "clickheal", "custom", "heal" },
    chat = { "emote", "dungeon", "raid", "pvp" },
}
-- Kategorie » Reiter, der sie zeigt
ns.CATEGORY_TAB = { class = "macros", race = "macros", general = "macros", custom = "macros", heal = "macros",
    oneclick = "oneclick", emote = "chat", announce = "chat", tools = "tools" }
-- Kategorie » Nummer ihres Reiters (bis Welle 23 die Stelle in ns.CATEGORIES, als es je Kategorie einen Reiter gab)
ns.CATEGORY_INDEX = {}
for category, tab in pairs(ns.CATEGORY_TAB) do ns.CATEGORY_INDEX[category] = ns.TAB_INDEX[tab] end

ns.CLASSES = Core.CLASSES
ns.RACES = Core.RACES

---------------------------------------------------------------------------
-- Helfer: die allgemeinen kommen aus ezCore (eine Umsetzung für alle Module)
---------------------------------------------------------------------------

-- Print, Error, Try, On, OnReady, OnSettingChanged, SettingChanged, SetSetting … und das Gerüst aus ezCore
-- (Core.ModuleScaffold): Datenbank ezMacroDB mit ihren Tabellen, Befehl /ezmacro samt Kurzform, Statuszeilen.
--   edits     [macroId] = { name = "...", body = "..." }
--   window    Position und letzte Auswahl
--   custom, backups, profiles, long, rankKeep: eigene Vorlagen, Sicherungen, Leisten-Profile, lange Makros,
--             Rang-Ausnahmen (je Charakter); hints: gesehene Erklärungen
--   oneClick  [charKey][macroId] = { name, index, body }: Ein-Klick-Makros, die ezMacro auf Klick angelegt hat und
--             deshalb aktuell halten darf (OneClick.lua); allgemeine (Konto-)Makros kontoweit unter dem Schlüssel
--             „account“ statt des Charakters
--   oneKey    [charKey] = { disenchant = { [itemID] = true }, petFood = { [itemID] = true } }: angehakte Gegenstände
--             der Helfer „Öffnen und Entzaubern“ und „Begleiter“ (OneKey.lua), je Charakter
--   macroKind [charKey | "account"][Makroname] = Art: eigene Zuordnung der Makros nach Art (Kinds.lua); allgemeine
--             Makros kontoweit, Charakter-Makros je Charakter
-- Kurzform /ezmc (Gesamtreview 18.11.2026, T18-14; vorher /em, das im Client Blizzards Emote-Befehl ist und darum
-- nie frei war; /ezm gehört ezMail): Ist /ezmc schon ein Chat-Befehl, Emote oder Befehl eines anderen Addons, bleibt
-- es bei /ezmacro (Prüfung in ezCore, Core.SlashTaken – erst beim Login, wenn alle Addons geladen sind).
-- Mindestversion von ezCore (Core.Require über das Gerüst; ist ezCore zu alt, meldet es das einmal und
-- ns.RunReady läuft nicht): Gerüst mit Tabellen und Kurzform, Einheiten-Ereignisse (ns.OnUnit), Rundgang mit
-- owner = ns, AfterCombat, OpenPanel, TextDialog, FadeTo und Glow.Set kamen mit ezCore 1.10.0 (Welle 1); 1.10.1
-- besserte zwei davon nach: ezCores Textdialog folgt dem Cursor wie zuvor ezMacros eigener Dialog, und AfterCombat
-- mit Schlüssel (so plant ezMacro Ränge und Danke) ersetzt einen späteren Eintrag auch beim Abarbeiten. Confirm ist
-- älter, steht aber mit in der Liste, weil ezMacro ohne ihn nicht fragen kann. Die Kleinhelfer aus Welle 3 kamen
-- nach 1.11.0 ohne neue Nummer dazu; deshalb nennt die Liste sie als Fähigkeit: die Abkürzungen des Gerüsts
-- (scaffoldHelpers: ns.OtherFor …), Core.InInstance, Core.Now/Uptime, Core.UnitIs/UnitPresent, Core.Pack/Unpack,
-- Core.UniqueName, Spells.FISHING und die Tastentexte der Klick-Zauber (ClickBindings.KeyText/Describe, EC-109,
-- MACRO-20). Sichere Knöpfe (SecureButton, SecureButtons) und WeaponKind standen vorher
-- als Einzelprüfung in Long.lua, Fishing.lua und AnnounceBar.lua (EC-67) – jetzt hier. FadeTo brauchten nur die
-- eigenen Emote-Leisten (Hintergrund im Takt des Chats); seit ezBars sie zeichnet (Welle 5), steht es nicht mehr darin.
-- Welle 7 (Helfer „Eine Taste“, OneKey.lua): ezCore 1.12.0, dazu Knowledge.IsOpenable (DG-41), Salvage.For/Known
-- und Menu.Tip, die nach 1.12.0 ohne neue Nummer kamen; ebenso opts.shown für page:Button (Options.lua) – das
-- lässt sich nicht als Fähigkeit abfragen, ein älteres ezCore zeigt dann nur alle Leisten-Knöpfe.
-- Welle 9 (UE-26): die Makro-Logik je Klasse (Spells.MacroLogic, Spells.MacroCondition), nach 1.12.0 ohne neue
-- Nummer; Data\Classes.lua baut daraus die /cast-Zeilen der umgestellten Vorlagen.
-- Welle 15: ezCores gemeinsamer Dienst „Makro anlegen“ (Core.Macro, nach 1.12.0 ohne neue Nummer); Import.lua
-- schreibt und zählt die Makros darüber.
-- 1.15.0: Bausteine aus dem Gesamtreview vom 18.11.2026, u. a. Core.RunsCode, Core.CleanImportName, Core.HelpLines,
-- Core.CombatNotice (Liste je Modul in docs/roadmap/uebergreifend.md, P7)
ns.CORE_VERSION = "1.15.0"
ns.CORE_NEEDS = { "scaffold", "unitEvents", "tourOwner", "AfterCombat", "OpenPanel", "TextDialog",
    "Glow.Set", "Confirm", "scaffoldHelpers", "SecureButton", "SecureButtons", "WeaponKind", "UniqueName", "Pack",
    "Unpack", "InInstance", "Now", "Uptime", "UnitIs", "UnitPresent", "Spells.FISHING",
    "ClickBindings.KeyText", "ClickBindings.Describe", "Knowledge.IsOpenable", "Salvage.For", "Salvage.Known",
    "Menu.Tip", "Spells.MacroLogic", "Spells.MacroCondition", "Macro.Write",
    -- Design-System (Welle 22): Werte und Helfer aus Core.Style, „Alle auswählen / Alle abwählen“ im Menü
    "Style.SetStrata", "Style.ColorText", "Style.IconSize", "Style.AllText", "Menu.AllToggle", "CreateCheck",
    -- Welle 17: Helfer und Texte, die ezCore ohne neue Versionsnummer bekam (tools/texte.lua, Regel 4)
    "More",
    -- Welle 23 (Reste vor der Doku-Welle; ezCore aus kern/reste-23a, ohne neue Nummer): Spieler-Menüs, Zauber-Teil
    -- der Makro-Logik, Emote-Index (alle Schreibweisen, Befehl zu Emote), Wahrheitswert mit nil als „nein“
    "Menu.PlayerMenus", "Spells.MacroCast", "EmoteCommands", "EmoteToken", "Flag",
    -- Welle 26 (ezCore-Paket kern/ezcore-reste-24, ohne neue Nummer): „Was fehlt für diesen Zauber?“ aus ezCore
    "Spells.MissingReagents", "Spells.ReagentList", "Spells.ReagentText", "Spells.ReagentSource",
    -- Welle 27 (Paket modul/ezmacro-faehigkeiten, ohne neue Nummer): Art eines Zaubers (Client, sonst Client-Tabellen)
    "SpellKinds.Of", "SpellKinds.Base", "SpellKinds.SourceText",
    -- Gesamtreview 18.11.2026 (P13 Teil D2, P19; ohne neue Nummer): Addon-Fach, Befehl ohne Wort, Zurücksetzen,
    -- Kampfsperre, Wege, Auswahlfeld, Zahnrad-Symbol, Tasten aus fremdem Text, Code-Befehle, Namen aus fremdem Text
    "compartmentMain", "slashMain", "HelpLines", "TipTitle", "CombatNotice", "SettingsPathText", "ClickText", "TipClick", "Menu.Dropdown",
    "Menu.ResolveIcon", "Menu.ICON_SETTINGS", "Keys.NormalizeKey", "RunsCode", "CleanImportName",
    -- Tooltip auch am gesperrten Knopf (ns.UI.Button, T9-7)
    "Toolbar.ShowTipWhileDisabled",
    -- Rollen statt Farbzahlen in Tooltips (T9-6)
    "TipLine", "TipText",
        -- Gesamtreview 18.11.2026 (D3, kern/einheit-rest; ohne neue Nummer): Texthelfer statt Kopien im Modul
        "CombatText", "Word", "keyPlus",
        -- Gesamtreview 18.11.2026 (P19a, kern/ssot-helfer; ohne neue Nummer): hergestellte Gegenstände aus ezCore
        "Spells.CONJURED", "Spells.SOUL_SHARD",
    -- Gesamtreview 18.11.2026 (P19a, kern/ssot-helfer; ohne neue Nummer): gemeinsame Helfer statt Kopien
    "QualityName", "CopyList", "PlaySound",
    -- Paket ezmacro/gifte-waffenzauber (ohne neue Nummer): bestes Gift aus ezCore, Makro „Gegenstand auf die Waffe“,
    -- Plätze der Hände, gewählter Waffenzauber
    "BestItems.WeaponEnchant", "Macro.WeaponItem", "HAND_SLOTS", "Spells.ChooseImbue", "WeaponEnchantable",
    -- Paket ezcore/klinge-wucht (ohne neue Nummer): WeaponEnchant mit Hand – nur, was die Waffe dieser Hand annimmt
    "BestItems.PickWeaponEnchant",
    -- Paket ezmacro/ssot-doppelungen (ohne neue Nummer): Rückfall-Haltungen; MacroFallbackForms steht zugleich für das
    -- leere Kettenglied „any“ in Spells.MacroCondition (kam im selben Paket, lässt sich nicht einzeln abfragen)
    "Spells.MacroFallbackForms", "Spells.BEAR_FORM",
    -- Paket ezmacro/ssot-doppelungen: Regel „bestes Essen, Getränk, Verband, Heiltrank“ aus ezCore
    "BestItems.Consumable", "BestItems.CONSUMABLE_KINDS" }
Core.NewModule(ADDON, ns, {
    core = ns.CORE_VERSION, needs = ns.CORE_NEEDS,
    db = "ezMacroDB",
    tables = { "hints", "edits", "window", "custom", "backups", "profiles", "long", "rankKeep", "oneClick", "oneKey", "macroKind" },
    -- main: ohne Wort die Makroverwaltung wie der Linksklick im Addon-Fach (Entscheidung 5); reset: „/ezmacro
    -- zuruecksetzen“ fragt wie der Knopf (Core.SlashReset über page:AskReset); die Hilfe baut ezCore aus CMD_HELP_OWN
    -- (Gesamtreview T18-3, T18-20, T9-4)
    slash = {
        commands = "/ezmacro", alias = "/ezmc",
        extra = function(cmd, rest) return ns.SlashExtra(cmd, rest) end,
        main = function() ns.Browser.Toggle() end,
        mainText = L.MAIN_TEXT,
        reset = true,
    },
})

-- ns.IsSecret, ns.Plain (Wert nur, wenn er nicht geheim ist), ns.InCombat, ns.OtherFor und ns.Throttle kommen aus
-- dem Gerüst (Abkürzungen, W-14).
ns.ClassName = Core.ClassName
ns.ClassColor = Core.ClassRGB       -- r, g, b
ns.RaceName = Core.RaceName
ns.Truncate = Core.TruncateChars    -- UTF-8-sicher auf Zeichen kürzen (Makronamen)
-- Hängt child seitlich an parent an und lässt es mitwandern (opts: side, gap, y, matchHeight).
ns.Dock = Core.Dock
-- Blizzards Chat-Sperre (z. B. in bestimmten Kämpfen): dann sendet ezMacro nichts.
ns.ChatLocked = Core.ChatLocked
-- Emotes: Leisten, Makro und automatische Emotes gehen über ns.Emote.Perform (Emote.lua, dort ezCores
-- Core.PerformEmote; Spucken mit Ziel wird ein Text-Emote) – keine eigene Durchreiche hier.

---------------------------------------------------------------------------
-- Makro-Katalog (gefüllt von Data\*.lua)
---------------------------------------------------------------------------
-- Felder eines Eintrags:
--   id      eindeutiger, fester Schlüssel (für gespeicherte Anpassungen)
--   name    { "Deutsch", "English" }, höchstens 16 Zeichen
--   desc    { "Deutsch", "English" }
--   body    Vorlage mit {s:SpellID}, {e:EMOTE} und {t:TEXT}
--   icon    optional: Symbolname aus Interface\Icons (sonst dynamisches Fragezeichen)
--   need    optional: Spell-ID für „gelernt?“ (Standard: erster Zauber), false = nie prüfen
--   class   optional: nur für diese Klasse (bei Volks-Makros)
--   logic   optional: Schlüssel der Makro-Logik in ezCores Klassen-Wissen (Spells.MacroLogic), aus der body gebaut
--           ist (ns.LogicBody in Data\Classes.lua); fehlt sie in ezCore, fällt die Vorlage weg statt halb zu stehen

ns.MACROS = {}
ns.MACRO_BY_ID = {}

-- Kein Durchrutschen auf das Ziel (Spieltest des Nutzers vom 15.11.2026): Steht die Maus auf einem Mitglied der
-- Gruppe, wirkt ein Makro für Mitspieler auf genau dieses oder gar nicht. Die Regel steht in ezCore
-- (Spells.MacroGroupFirst setzt „[@mouseover,party][@mouseover,raid]“ vor jedes Maus-Glied für Mitspieler); ezMacro
-- wendet sie an einer Stelle auf jede Vorlage an (AddMacros), dazu auf die Klick-Vorlagen und den Baukasten.
-- Ohne die Funktion (ezCore zu alt) bleibt der Text, wie er ist.
function ns.GroupFirst(body)
    local fn = Core.Spells and Core.Spells.MacroGroupFirst
    if type(body) ~= "string" or type(fn) ~= "function" then return body end
    return fn(body)
end

function ns.AddMacros(category, group, list)
    for _, entry in ipairs(list) do
        if ns.MACRO_BY_ID[entry.id] then
            geterrorhandler()("ezMacro: doppelte Makro-ID " .. tostring(entry.id))
        elseif entry.logic and type(entry.body) ~= "string" then
            -- ezCore ohne diese Makro-Logik (zu alt: Core.Require meldet es über ns.CORE_NEEDS) – keine Vorlage
        else
            entry.category, entry.group = category, group
            entry.body = ns.GroupFirst(entry.body)
            table.insert(ns.MACROS, entry)
            ns.MACRO_BY_ID[entry.id] = entry
        end
    end
end

---------------------------------------------------------------------------
-- Datenbank: legt das Gerüst an (oben, opts.db und opts.tables); hier nur der Login
---------------------------------------------------------------------------

ns.On("PLAYER_LOGIN", function()
    local _, raceToken = UnitRace("player")
    ns.playerClass, ns.playerRace = Core.PlayerClass(), raceToken
    ns.playerGUID = UnitGUID("player")
    ns.charKey = Core.charKey

    ns.RunReady()
end)

-- Beim Ausloggen (und vor /reload): Sicherung der eigenen Makros u. a. (ns.OnLogout).
ns.On("PLAYER_LOGOUT", function()
    if ns.db then ns.RunLogout() end
end)

---------------------------------------------------------------------------
-- Slash-Befehle
---------------------------------------------------------------------------

-- Gesetzte Kurzform („/ezmc“) oder nil; das Gerüst trägt sie beim Login in ns.slashAlias ein.
function ns.ShortAlias() return ns.slashAlias end

-- Hilfe im Chat: Kopf und Standardzeilen von ezCore, dann CMD_HELP_OWN (Core.HelpLines über das Gerüst, T18-20).
-- Bleibt als Weiterleitung für „?“ und den Rückfall des Addon-Fachs.
function ns.Help()
    if type(ns.PrintHelp) == "function" and ns.PrintHelp ~= ns.Help then return ns.PrintHelp() end
    for _, line in ipairs(Core.HelpLines(ns)) do ns.Print(line) end
end
local Help = ns.Help

-- Kampfsperre (Gesamtreview T18-1): ezCores Satz „Makros anlegen oder ändern geht im Kampf nicht – …“ statt eines
-- eigenen Wortlauts. ns.CombatText() liefert ihn (Hinweiszeilen, Meldung in der Mitte), ns.CombatNotice() schreibt
-- ihn in den Chat.
function ns.CombatText() return Core.CombatText(L.MACRO_COMBAT_WHAT) end
function ns.CombatNotice() return Core.CombatNotice(ns, L.MACRO_COMBAT_WHAT) end

-- Schalter per Befehl (ezCore.HandleToggle): je Schalter der deutsche Befehl und im Feld en der englische (T10-1).
ns.TOGGLES = {
    { "autoThank", "danke", en = "thank" },
    { "autoSpit", "spucken", en = "spit" },
    { "barShown", "leiste", en = "bar" },
}

-- Automatisches Danke bzw. Spucken einmal ausprobieren (Befehl „test“, Knöpfe unter „Erweitert“), ohne Drosselung.
-- Ohne Namen gilt es dem Spieler im Ziel. Rückgabe: true gesendet.
function ns.TestEmote(kind, who)
    if who == nil or who == "" then
        -- Leitlinie 6: die Antworten des Clients zuerst über IsSecret (Core.Bool) – gesperrt zählt als „kein Spieler“
        who = Core.UnitIs("target") == true and Core.UnitFullName("target") or nil
    end
    if not who then
        ns.Print(L.CMD_TEST_NO_TARGET)
        return false
    end
    return ns.Auto.Fire(kind, who, true)
end

local TEST_KINDS = { danke = "thank", thank = "thank", spucken = "spit", spit = "spit" }

-- Die eigenen Befehle; das Gerüst erledigt danach optionen, status, hilfe und die Schalter (ns.TOGGLES: danke,
-- spucken, leiste). Rückgabe true: erledigt.
function ns.SlashExtra(cmd, rest)
    if cmd == "?" then
        Help()
    elseif cmd == "pruefen" or cmd == "prüfen" or cmd == "check" then
        ns.CheckSpells()
    elseif cmd == "sichern" or cmd == "backup" then
        ns.Backup.Save()
    elseif cmd == "werkzeuge" or cmd == "tools" then
        ns.Browser.ShowCategory("tools")
    elseif cmd == "raenge" or cmd == "ränge" or cmd == "ranks" then
        ns.Ranks.Update()
    elseif cmd == "ansage" or cmd == "announce" then
        -- „/ezmacro ansage [warn|gruppe] Text“: so stehen die Ansagen in den Makros (Kanal wählt sich beim Klick)
        ns.Announce.Slash(rest)
    elseif cmd == "ansagen" or cmd == "announcements" then
        ns.Browser.ShowCategory("announce")
    elseif cmd == "einklick" or cmd == "oneclick" then
        ns.Browser.ShowCategory("oneclick")
    elseif cmd == "angeln" or cmd == "fishing" then
        -- „/ezmacro angeln status“: Diagnose für den Spieltest (wie der Knopf „Status im Chat“ der Werkzeug-Seite)
        if tostring(rest or ""):lower():match("^%s*status%s*$") then
            ns.Fishing.PrintStatus()
        else
            ns.Fishing.Toggle()
        end
    elseif cmd == "einetaste" or cmd == "onekey" then
        -- Helfer „Eine Taste“ (OneKey.lua): stehen im Reiter „Ein-Klick“
        ns.Browser.ShowCategory("oneclick")
    elseif cmd == "entzaubern" or cmd == "disenchant" then
        ns.Browser.ShowEntry(ns.Tools.Get("onekeyOpen"))
    elseif cmd == "begleiter" or cmd == "pet" then
        ns.Browser.ShowEntry(ns.Tools.Get("onekeyPet"))
    elseif cmd == "foto" or cmd == "screenshot" then
        -- Werkzeug „Kleine Helfer“ (InfoTools.lua): Bildschirmfoto ohne Oberfläche
        ns.InfoTools.Shot.Take()
    elseif cmd == "npc" or cmd == "npcid" then
        ns.InfoTools.PrintNpc()
    elseif cmd == "emote" then
        -- „/ezmacro emote SPIT“: so steht Spucken im Makro (mit Ziel ein Text-Emote mit dem Namen, Emote.lua)
        ns.Emote.Slash(rest)
    elseif cmd == "test" then
        local what, who = tostring(rest or ""):match("^(%S+)%s*(.-)$")
        local kind = TEST_KINDS[(what or ""):lower()]
        if kind then
            ns.TestEmote(kind, who)
        else
            ns.Print(L.CMD_TEST_USAGE)
        end
    else
        return false
    end
    return true
end

---------------------------------------------------------------------------
-- Addon-Compartment (Minikarten-Knopf „Addons“): die drei Funktionen der TOC baut ezCore.
---------------------------------------------------------------------------

-- Entscheidung 5 (Gesamtreview T18-3, T16-10): Linksklick Makroverwaltung, Rechtsklick Einstellungen (sonst die Hilfe);
-- Zeilen und Befehl baut ezCore.
ezMacro_OnAddonCompartmentClick, ezMacro_OnAddonCompartmentEnter, ezMacro_OnAddonCompartmentLeave =
    Core.CompartmentHandlers({ ns = ns, title = L.TITLE, owner = ADDON, main = function() ns.Browser.Toggle() end,
        mainText = L.MAIN_TEXT })
