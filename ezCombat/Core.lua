local ADDON, ns = ...
local L = ns.L

-- TOC „## OptionalDeps: ClassicUIForever“ – Grund nach der Regel für OptionalDeps (docs/ezcore.md, „Gerüst-Dienste“;
-- Gesamtreview 18.11.2026, T4-8): Kandidat „nur Erkennung“. ClassicUIs Option „Combopunkte“ fragt ezCombat zur Laufzeit
-- (Combo.ClassicUITakesOver über ezCore.OtherAddOn); beim Laden braucht ezCombat nichts von ClassicUI. Welle 4 nannte
-- als möglichen Grund (b) die Rahmen, die ClassicUI beim Laden umbaut (Ziel- und Fokusrahmen mit ezCombats Auren) –
-- belegt ist das nicht. Der Eintrag entfällt erst nach der Spielprüfung, weil sich die Ladereihenfolge ändert
-- (docs/roadmap/ezCombat.md, „Im Spiel prüfen“).

-- Jede Funktion ist einzeln abschaltbar (Esc → Optionen → AddOns → ezCombat). Einstellungs-Prüfung vom 19.11.2026
-- (Entscheidung des Nutzers „Ja, alle umsetzen“): fest eingebaut statt Schalter sind „nicht auf der Leiste“, die drei
-- „noch nicht bereit“-Hinweise, eigene Zeile hervorheben, „Bericht in den Chat“ und die Erklärung im Rahmen-Tooltip;
-- der Reiter „Rotation“ folgt „Nächste Aktion vorschlagen“; berechnete Rotationen stehen immer in der Liste;
-- zusammengelegt sind „wieder bereit“ (nur noch die Auswahl showReady), „aus“ der nächsten Fähigkeit (nur noch
-- „Nächste Aktion vorschlagen“) und die Größen-Kästchen (Regler auf Blizzards Größe = aus). Gespeicherte Werte
-- übernimmt ns.MigrateSettings1911 einmal (unten); die alten Schlüssel stehen in ns.REMOVED_SETTINGS.
ns.DEFAULTS = {
    -- Fähigkeit wieder bereit
    readyMin = 5,           -- Sekunden: kürzere Abklingzeiten melden sich nicht (bis 1.6: 8)

    -- Anzeige über dem Charakter (Symbol.lua, CB-N1, Wunsch des Nutzers vom 14.11.2026 nach dem Probe-Lauf): drei
    -- Plätze – Mitte groß die nächste Fähigkeit der Rotation, links klein „läuft aus“ (DoT, HoT, Buff), rechts klein
    -- „wieder bereit“. Je Meldungsart, wo sie erscheint (ns.SHOW_VALUES): "both" (über dem Charakter und Leuchten am
    -- Aktionsknopf), "center" (nur über dem Charakter), "glow" (nur Leuchten am Knopf), "off". Bis 1.11 waren das
    -- je zwei Kästchen (readyPulse, symbolDots, buffPulse, dotButton, rotationSymbol, rotationGlow; einmal umgestellt
    -- in ns.OnLoad, die alten Werte bleiben im Speicher).
    showNext = "both",      -- Frage a) an den Nutzer: ab Werk „beides“ (Empfehlung umgesetzt, Antwort offen)
    showExpiring = "both",
    showReady = "both",
    -- Größen ab Werk wie Blizzards Aktionsknöpfe (Core.Style.ICON: action 45, small 30; vorher 52/36 – Entscheidung
    -- des Nutzers vom 16.11.2026, Nr. 7 der Liste im ROADMAP-Index, vorläufig nach Empfehlung). Wer den alten
    -- Standard gespeichert hatte, bekommt den neuen einmal (ns.OnLoad, Merker iconSizes45); eigene Größen bleiben.
    sizeNext = ezCore.Style.ICON.action,    -- Pixel: Mitte (45)
    sizeExpiring = ezCore.Style.ICON.small, -- Pixel: links (30)
    sizeReady = ezCore.Style.ICON.small,    -- Pixel: rechts (30)
    symbolHold = 2,         -- Sekunden: so lange steht „wieder bereit“
    symbolCenter = true,    -- ein seitliches Symbol allein rückt in die Mitte (Wunsch des Nutzers vom 15.11.2026)
    -- Text unter dem Symbol (Symbol.lua; Spielbefund des Nutzers vom 18.11.2026: „viel zu viel text... wenn berhaupt
    -- nötig...“, S-1811-Symboltext): "off" nur das Symbol (ab Werk), "name" eine Zeile mit dem Namen, "full" wie bis
    -- dahin („Als Nächstes: …“ und „wartet: …“). Bis 18.11.2026 gab es keine Wahl, alle sahen „ausführlich“; der
    -- Schlüssel ist neu, also bekommt jeder gespeicherte Stand beim Ergänzen der Standardwerte einmal „aus“ – eine
    -- eigene Wahl gibt es noch nicht, die bleiben müsste. Umkehrbar: dieser Wert.
    symbolText = "off",
    -- Trank im mittigen Symbol (Potions.lua; Wunsch des Nutzers vom 23.11.2026: „nur die tränke mittig Symbol, beides
    -- ab 15 %“): Gesundheitsstein bzw. Heiltrank unter der Grenze an Leben, Manatrank unter der Grenze an Mana – ein
    -- Regler für beides, Deckkraft über Blizzards Kurve (ezCombat liest Leben und Mana nie)
    potions = true,
    potionBelow = 15,       -- Prozent: Trank, Rettungsfähigkeit und Leuchten am Spielerfenster
    -- Fast tot oder vergiftet (Frage des Nutzers vom 24.11.2026, docs/roadmap/ezCombat.md): ab Werk an
    rescue = true,          -- Rettungsfähigkeit im mittigen Symbol (Rescue.lua)
    dangerGlow = true,      -- Blizzards Spielerfenster leuchtet (Danger.lua)
    dispelHint = true,      -- Bann-Zauber am Spielerfenster und an den klassischen Gruppenrahmen (Dispel.lua)

    -- Rotation (Rotation.lua, Daten in RotationData/<KLASSE>.lua)
    rotation = true,        -- nächste Aktion vorschlagen
    rotationChoice = "auto",-- Spiegel der Wahl dieses Charakters (gemerkt in ezCombatDB.rotations)
    rotationBlizzard = true,-- Blizzards Rotations-Assistent zuerst, wenn das Spiel ihn anbietet
    rotationPrep = true,    -- „Vor dem Kampf“: fehlende Dauer-Buffs, Begleiter, Stein, Gift am Symbolplatz
    rotationPrepRest = true,  -- … auch in Städten und Gasthäusern über dem Charakter (bis Welle 12 ab Werk aus:
                              -- Spieltest 15.11.2026, Befund 2 – in der Stadt stand nichts mehr in der Mitte)
    rotationOpener = true,  -- schon mit Ziel vor dem Kampf vorschlagen
    -- Blizzards Regeln (Prüfung 17.11.2026, V1; entschieden vom Nutzer am 17.11.2026: Grauzone, kein Verstoß – die
    -- Vorhersage im Kampf bleibt, „Mitzählen“ ab Werk aus und selbst einzuschalten): eigene Empfehlung im Kampf an,
    -- ab Werk nur aus offenen Werten (rotationEstimate aus); rotationInCombat aus = im Kampf nur Blizzards Assistent.
    rotationInCombat = true,  -- eigene Empfehlung auch im Kampf (aus: im Kampf nur Blizzards Rotations-Assistent)
    rotationCooldowns = "boss",   -- große Abklingzeiten: "always" | "boss" | "never" (Standard: Entscheidung des Nutzers 13.11.2026)
    rotationAoe = false,    -- Flächenmodus (ezCombat kann Gegner nicht zählen); auch über die Taste in Blizzards
                            -- Tastaturbelegung (ezCore.Keys „combatAoe“) und Klick auf das Symbol in der Mitte
    rotationSide = true,    -- Fähigkeiten ohne globale Abklingzeit leuchten nebenher
    rotationEstimate = false, -- mitzählen, wenn das Spiel Werte sperrt (Vorschlag trägt „gezählt“); ab Werk aus seit
                              -- der Prüfung auf Blizzards Regeln vom 17.11.2026 (V1, Risiko 1; vorher an; entschieden 17.11.)
    rotationWarn = 3,       -- Vorwarnung vor Ablauf: Sekunden, ab denen ein Schritt „gleich bereit“ zeigt (Welle 27, Paket
                            -- modul/ezcombat-abklingzeit; Empfehlung umgesetzt, Antwort offen)
    -- Werte abwägen (RotationValue.lua, Auftrag des Nutzers vom 23.11.2026; Entscheidungen vom 23.11.2026: Schalter
    -- „Ab Werk an (Empfohlen)“, Modell „Treffer zählen, Reserve 30 % (Empfohlen)“ – docs/roadmap/ezCombat.md)
    rotationValues = true,  -- Füller gegen Zauberstab nach Schaden je Sekunde und Mana abwägen
    -- Schadensvergleich Zauber gegen Zauberstab als Zeile unter dem Symbol, unabhängig von „Text unter dem Symbol“; ab
    -- Werk aus (Nutzer am 24.11.2026: „den text mit schaden von zauberstab vs schattenblitz ist nicht austellbar? gar
    -- sinnlos?“, auf den Vorschlag „Ja, umbauen“; bis dahin an, ns.MigrateSymbolText2411)
    rotationValuesText = false,
    rotationManaReserve = 30, -- Mana in Prozent, das nach einem teuren Füller bleiben soll (sonst der Stab)

    -- Hinweise am Aktionsknopf
    reactive = true,        -- Überwältigen, Rache, Gegenangriff, Hinrichten unter 20 % …
    interrupt = true,       -- Ziel wirkt etwas Unterbrechbares
    finisher = true,        -- volle Combo-Punkte

    -- Eigene DoTs/HoTs am Ziel
    -- große Symbole über dem Zielfenster; ab Werk aus seit der Entscheidung des Nutzers vom 23.11.2026 („Ja, ab Werk
    -- aus (Empfohlen)“, ns.MigrateDots2311) – Leuchten am Knopf und „läuft aus“ in der Mitte hängen nicht daran
    dots = false,
    dotWarn = 3,            -- Sekunden Restzeit (plus Zauberzeit) für „neu setzen“

    -- Eigene Buffs auf dir
    buffs = true,           -- Aktionsknopf leuchtet kurz vor dem Ablauf (und danach, bis neu gewirkt)
    buffWarn = 10,          -- Sekunden Restzeit (plus Zauberzeit)

    -- Combo-Punkte (Combo.lua; Entscheidung des Nutzers vom 23.11.2026, „Ziel aus, ein Regler“): die Leiste unter dem
    -- Spielerfenster zeigt sie, Blizzards Punkte am Zielporträt sind ab Werk aus, ein Regler gilt für beide.
    comboBar = true,        -- Reihe unter dem Spielerfenster wie im Original-Retail
    comboTarget = false,    -- Blizzards Punkte am Zielporträt zeigen (aus: ausgeblendet; auch für bisherige Nutzer)
    comboScale = 100,       -- Größe der Punkte in Prozent von Blizzards Größe (Vorlage 20 px) – Leiste und, wenn an, Ziel.
                            -- Bis 23.11.2026 nur das Ziel, in Prozent von Blizzards 60 % dort (Standard 150, 100 = aus);
                            -- umgestellt einmal über ns.MigrateCombo2311

    -- Schlagtimer des Spiels
    swingExtras = true,     -- Autoschuss-Fenster und vorgemerkter Schlag

    -- Kraftleiste
    energyTick = true,
    manaRule = true,        -- 5-Sekunden-Regel und Mana-Tick

    -- Klassen
    totems = true,
    totemWarn = 5,          -- Sekunden
    enchants = true,
    enchantWarn = 120,      -- Sekunden
    enchantSound = true,

    -- Blizzards Schadensanzeige (eigene Zeile hervorgehoben und „Bericht in den Chat“ im Zahnrad-Menü: fest)
    meterReportLines = 5,
    meterFramesDamage = true,  -- Schaden an Blizzards Gruppen- und Raidrahmen (MeterFrames.lua)
    meterFramesHealing = true, -- Heilung an Blizzards Gruppen- und Raidrahmen
    meterFramesNumbers = true, -- Zahlen neben dem klassischen Rahmen bzw. in der Mitte (aus: nur die Linien; 20.11.2026)
    meterFramesOwnRole = true, -- nur die Art der eigenen Rolle (Heiler: Heilung, sonst Schaden; Spieltest 20.11.2026)
    meterFramesHeight = 5,     -- Höhe eines Balkens unter dem klassischen Rahmen in px, höchstens halbe Manabalken-Höhe
                               -- (Spieltest 20.11.2026; 18. bis 20.11.2026: 2 px auf dem Manabalken)
    meterFramesSession = "current", -- Abschnitt der Balken: "current" | "overall" | "combat" (früherer Kampf; welcher:
                                    -- ezCombatDB.meterFramesSessionID, 0 = der neueste)
    -- Top-3-Ansicht und weitere Arten (Antwort des Nutzers vom 16.11.2026: „Ja, beides“; MeterTop.lua). Ab Werk wie
    -- bisher (Zeilen, nur Schaden und Heilung) – Empfehlung der Hauptsession, umkehrbar.
    meterFramesView = "rows",       -- Darstellung: "rows" Zeilen an jedem Rahmen | "top3" nur die ersten 3 | "both"
    meterFramesInterrupts = false,  -- Unterbrechungen als Marke (Blizzards Schadensanzeige)
    meterFramesDispels = false,     -- Bannungen als Marke
    meterFramesDeaths = false,      -- Tode als Marke mit der Zahl
    meterFramesThreat = false,      -- Aggro: Platz 1–3 der Bedrohung im Kampf (Blizzards Bedrohungs-Abfrage)
    meterSummary = false,      -- eine Chat-Zeile nach dem Kampf (MeterSummary.lua), Entscheidung: ab Werk aus
}

-- „Allem zustimmen“ (ezCore, Werkzeuge/FirstStart.lua: Intro.Registered; Spieltest 20.11.2026): jeder Schalter oben,
-- der ab Werk aus ist und kein Ablauf ohne Klick (die stehen in Intro.CONSENT). "on": mit der Zustimmung gesetzt;
-- "risk": bleibt aus, riskiert Blizzards Regeln oder Schutz; "choice": Geschmack, Filter, Leitlinie 9 oder 11.
-- tools/Tests/agree_test.lua prüft, dass jeder neue Schalter mit false hier oder in Intro.CONSENT steht.
ns.AGREE = {
    meterFramesInterrupts = "on", meterFramesDispels = "on", meterFramesDeaths = "on", meterFramesThreat = "on",
    meterSummary = "choice", rotationAoe = "choice",   -- Zusammenfassung: auch bei „Allem zustimmen“ aus (Nutzer 23.11.2026)
    -- Blizzards Punkte am Zielporträt: ab Werk aus, weil die Combo-Leiste sie schon zeigt (Entscheidung 23.11.2026) –
    -- zusätzlich am Ziel ist Geschmack
    comboTarget = "choice",
    -- Große Symbole über dem Zielfenster: ab Werk aus, weil der Nutzer keinen Nutzen darin sieht (Entscheidung
    -- 23.11.2026); Leuchten am Knopf und „läuft aus“ in der Mitte zeigen dasselbe – zusätzlich ist Geschmack
    dots = "choice",
    -- Schadensvergleich unter dem Symbol: ab Werk aus, weil das Symbol schon sagt, was dran ist (Entscheidung 24.11.2026)
    rotationValuesText = "choice",
}

-- Neu seit v1.0.0-beta3 und ab Werk an; Einträge bleiben stehen (ezCore, Werkzeuge/ConsentNews.lua: Intro.NewsOnRows;
-- Nutzer am 24.11.2026): Die Blase „Neu seit dem Update“ nennt sie einmal mit gesetztem Häkchen. tools/Tests/agree_test.lua
-- ist rot, wenn ein neuer Schalter mit true hier fehlt.
ns.NEWS = { "potions", { "rotationValues", needs = "rotation" }, "rescue", "dangerGlow", "dispelHint" }

-- Grenzen der Regler { min, max, Schritt } und Werte der Auswahlfelder: EINE Stelle für die Einstellungsseite
-- (Options.lua) und die Prüfung importierter Profile (Profiles.lua, CB-44).
ns.LIMITS = {
    sizeNext = { 24, 96, 1 }, sizeExpiring = { 20, 64, 2 }, sizeReady = { 20, 64, 2 }, symbolHold = { 1, 5, 1 },
    readyMin = { 2, 60, 1 }, dotWarn = { 1, 10, 1 }, buffWarn = { 5, 60, 5 },
    -- comboScale: 60 % ist Blizzards Größe am Zielporträt, 150 % (30 px) hält den Bogen um das Porträt noch kürzer als
    -- einen Halbkreis; bis 23.11.2026 { 100, 200, 10 } in Prozent von Blizzards Größe am Ziel (= 60 bis 120 hier)
    comboScale = { 60, 150, 5 }, totemWarn = { 2, 15, 1 }, enchantWarn = { 30, 600, 30 },
    meterReportLines = { 3, 10, 1 }, meterFramesHeight = { 1, 5, 1 }, rotationWarn = { 0, 5, 1 },
    rotationManaReserve = { 0, 80, 5 },
    potionBelow = { 5, 50, 5 },
}

---------------------------------------------------------------------------
-- Helfer: die allgemeinen kommen aus ezCore (eine Umsetzung für alle Module)
---------------------------------------------------------------------------

local Core = ezCore
-- Gerüst von ezCore (EC-66): Print, Error, Try, On, OnUnit, OnReady, RunReady, OnSettingChanged, SettingChanged,
-- SetSetting, ns.Enabled(key), ns.Throttle(fn, delay), ns.WhenAddOnLoaded(name, fn), ns.AfterCombat(fn, key), die
-- Abkürzungen ns.IsSecret, ns.Plain (Wert nur, wenn er nicht geheim ist), ns.Num (Zahl, mit der sicher gerechnet
-- werden darf), ns.InCombat, ns.IsLoaded, ns.OtherFor, dazu ns.NoteSecret/ns.secretSeen und ns.AddStatusLine/
-- ns.StatusLines (Zeilen für /ezk status). Datenbank ezCombatDB samt Einstellungen und tour, Anmelden, Befehl
-- /ezcombat und der Kurzbefehl /ezk (nur, wenn ihn kein anderes Addon belegt: Core.AddSlashAlias, V-181).
-- ezCore 1.11.0 bringt ns.OtherFor und Core.Uptime, 1.12.0 Core.UnitPresent, Core.OnRestrictionChanged und Core.Menu.Tip.
Core.NewModule(ADDON, ns, {
    title = "ezCombat",
    -- 1.15.0: Bausteine aus dem Gesamtreview vom 18.11.2026, u. a. Core.SwitchCVar, Core.CombatNotice, Core.ClickText, Core.Tooltip.Gap
    -- (Liste je Modul in docs/roadmap/uebergreifend.md, P7)
    core = "1.15.0",
    -- Welle 23: Vorleistungen aus kern/reste-23a (Core.Has über den Funktionsnamen); Welle 26: More (Rest der
    -- fremden Zauber beim Einlesen einer eigenen Rotation); Welle 27: Style.SetTextColor (Medaillenfarben der Marken
    -- an den Gruppenrahmen, MeterTop.lua – kam ohne neue Versionsnummer nach 1.13.0), Buff-Wissen nur über ezCores
    -- Leseschnittstelle (F7)
    needs = { "NewSettingsProfiles", "Spells.LockedKind", "WeaponEnchantInfo", "ApplySetting", "GroupFrames.TooltipUnit",
        -- Einstellungs-Prüfung 19.11.2026: gespeicherte Werte einmal umstellen (Core.MigrateOnce), Tooltip am Symbol
        "MigrateOnce", "TipLine",
        -- Gesamtreview 18.11.2026, P19c (ohne neue Versionsnummer): Takt mit Griff (T7-3), Ersatzsymbol (T16-NM6)
        "Ticker", "ICON_FALLBACK_ID",
        "MeasureField", "Measure.Show", "Style.ICON", "More", "Style.SetTextColor", "Spells.IsBuff", "Spells.BuffField",
        -- Gesamtreview 18.11.2026 (P14): Schalter auf Klick ohne Umschalten im Kampf (ohne neue Versionsnummer)
        "SwitchCVar",
        -- Oberflächen-Einheit (Gesamtreview 18.11.2026, P13 D2): Addon-Fach und Befehl ohne Wort nach Entscheidung 5,
        -- Hilfe aus ezCore, Kampfsperre, Klick-Hinweise und Wege zu Einstellungen aus ezCore
        "compartmentMain", "slashMain", "CombatNotice", "SettingsPathText", "ClickText",
        -- Gesamtreview 18.11.2026 (D3, kern/einheit-rest; ohne neue Nummer): Texthelfer statt Kopien im Modul
        "CombatText", "Word", "CmdText",
    -- Gesamtreview 18.11.2026 (P19a, kern/ssot-helfer; ohne neue Nummer): gemeinsame Helfer statt Kopien
    "PlaySound", "Spells.CONJURED",
    -- Trank im mittigen Symbol (23.11.2026, ohne neue Nummer): Kurve für Leben und Mana, bester Trank, Anzahl
    "HealthBelowAlpha", "PowerBelowAlpha", "BestItems.Consumable", "ItemCount",
    -- Rettung, Bannen, Leuchten (24.11.2026, ohne neue Nummer)
    "Spells.RescueSpells", "Spells.DispelsBySpell", "AuraRows.DispelBorderStyle",
    -- Stufenkurve aus ezCore statt eigener Fassung (25.11.2026, ohne neue Nummer)
    "StepCurve",
    -- Talentbaum des Charakters und Rotation zu Talentvorlage, n:m (24.11.2026, ohne neue Nummer)
    "Talents.MainTree", "RotationBuilds.Builds",
    -- Rotation auf die Aktionsleisten 1 und 2 legen (24.11.2026, ohne neue Nummer)
    "ActionSlots.MainPage", "ActionSlots.BarShown", "BarProfiles.Rearrange", "BarProfiles.Restore", "BarProfiles.MacroNames",
    "BarProfiles.Movable", "BarProfiles.Exact", "DateText",
    -- Was sich ausschließt (24.11.2026, ohne neue Nummer)
    "Spells.FamilyInfo" },
    db = "ezCombatDB",
    tables = { "tour" },                  -- gesehene Erklärblasen (ezCore.NewTour)
    onLoad = function(db) ns.OnLoad(db) end,
    login = true,
    -- Kurzbefehl /ezk aus Core.SLASH_ALIASES (eine Liste, T18-14). „einstellungen“, „status“, „hilfe“ und
    -- „zuruecksetzen“ (fragt wie der Knopf, T18-20) versteht das Gerüst; ohne Wort führt „/ezcombat“ wie der Linksklick
    -- im Addon-Fach alle Hilfen vor (Entscheidung 5); die eigenen Wörter: ns.SlashExtra
    slash = {
        commands = { "/ezcombat" },
        extra = function(cmd, rest) return ns.SlashExtra(cmd, rest) end,
        main = function() ns.PreviewAll() end, mainText = L.MAIN_TEXT, reset = true,
    },
})

-- Klasse und eigene GUID vor allen übrigen OnReady-Aufgaben (vorher im eigenen PLAYER_LOGIN).
ns.OnReady(function()
    ns.playerClass = Core.PlayerClass()
    ns.playerGUID = ns.Plain(UnitGUID and UnitGUID("player"))
end)

-- Einmalige Chatzeile nach der Einstellungs-Prüfung vom 19.11.2026 (siehe ns.NeedsNotice1911). → true, wenn gemeldet.
function ns.Notice1911()
    local db = ns.db
    if not (type(db) == "table" and db.notice1911) then return false end
    db.notice1911 = nil
    ns.Print(L.NOTICE_NEXT_OFF_1911)
    return true
end
ns.OnReady(function() ns.Notice1911() end)

ns.Bool = Core.Bool                 -- Wahrheitswert, der geheim sein kann: dann (oder bei nil) gilt fallback
ns.CVar = Core.CVar
ns.AtlasExists = Core.AtlasExists
ns.FirstAtlas = Core.FirstAtlas

-- Gibt es die Einheit gerade ("target", "pettarget" …)? true / false / nil = unbekannt (Rückgabe gesperrt).
-- Die eine Stelle für UnitExists ist ezCore (Core.UnitPresent, V-184: zuerst IsSecret, nie als Wahrheitswert);
-- die Aufrufer entscheiden, was „unbekannt“ heißt. Rotation.UnitPresent leitet hierher weiter.
function ns.UnitPresent(unit)
    return Core.UnitPresent(unit)
end

-- Wo eine Meldungsart erscheint (CB-N1): kind "next" | "expiring" | "ready", place "center" (Anzeige über dem
-- Charakter) | "glow" (Leuchten am Aktionsknopf) → true/false. Ein unbekannter Wert gilt wie der Standard.
ns.SHOW_KEYS = { next = "showNext", expiring = "showExpiring", ready = "showReady" }
ns.SHOW_VALUES = { "both", "center", "glow", "off" }
-- Werte der Auswahlfelder (ohne rotationChoice: deren Werte hängen an der Klasse, Rotation.ChoiceValues).
-- Die nächste Fähigkeit hat kein „Aus“ (Einstellungs-Prüfung 19.11.2026, Nr. 69): ausgeschaltet wird sie nur über
-- „Nächste Aktion vorschlagen“ (rotation) – vorher gab es zwei Ausschalter, und man sah nicht, welcher galt.
ns.NEXT_VALUES = { "both", "center", "glow" }
ns.CHOICES = {
    showNext = ns.NEXT_VALUES, showExpiring = ns.SHOW_VALUES, showReady = ns.SHOW_VALUES,
    rotationCooldowns = { "always", "boss", "never" },
    symbolText = { "off", "name", "full" },
    meterFramesSession = { "current", "overall", "combat" },
    meterFramesView = { "rows", "top3", "both" },
}
local SHOW_PLACES = { both = { center = true, glow = true }, center = { center = true }, glow = { glow = true }, off = {} }

function ns.ShowAt(kind, place)
    local key = ns.SHOW_KEYS[kind]
    if not key then return false end
    local places = SHOW_PLACES[ns.S and ns.S[key]] or SHOW_PLACES[ns.DEFAULTS[key]]
    return places[place] == true
end

-- Erscheint die Meldungsart überhaupt (Mitte oder Leuchten)?
function ns.ShowAny(kind)
    return ns.ShowAt(kind, "center") or ns.ShowAt(kind, "glow")
end

-- Wert der Auswahl aus den zwei Orten (für die Umstellung alter Kästchen): "both" | "center" | "glow" | "off".
function ns.ShowValue(center, glow)
    if center and glow then return "both" end
    if center then return "center" end
    if glow then return "glow" end
    return "off"
end

-- Blizzards Bearbeitungsmodus: Teile an Blizzards Fenstern (Schlagtimer-Extras) hören auf
-- ns.Listen("EDIT_MODE", fn(active)).
Core.EditMode.OnChange(function(active) ns.Fire("EDIT_MODE", active) end, ADDON)

-- Beispiel-Symbole beim Verschieben: Solange ezCores Auswahl offen ist – im Bearbeitungsmodus wie bei
-- „Teile verschieben“ in den Einstellungen (Nachricht MOVER_SHOWING) –, zeigen Bereit-Symbol, DoT-Reihe und
-- Combo-Leiste ein Beispiel. Die Teile hören auf ns.Listen("PARTS_SHOWING", fn(active)).
local partsShowing = false

function ns.PartsShowing()
    return partsShowing or Core.EditMode.IsActive()
end

-- Vorschau läuft (Knopf „Zeigen“ bis untilTime) oder die Auswahl zum Verschieben ist offen.
function ns.Previewing(untilTime)
    return GetTime() < (untilTime or 0) or ns.PartsShowing()
end

if Core.Mover then
    Core.Listen("MOVER_SHOWING", function(active)
        partsShowing = active == true
        ns.Fire("PARTS_SHOWING", ns.PartsShowing())
    end, ADDON)
else
    Core.EditMode.OnChange(function(active) ns.Fire("PARTS_SHOWING", active) end, ADDON)
end

-- Eigene Teile verschiebbar machen (ezCore.Mover): Auswahl im Bearbeitungsmodus und über „Teile verschieben“
-- in den Einstellungen; ezCombat baut dafür nichts selbst. Ohne gespeicherte Position bleibt der Standardanker
-- an Blizzards Fenster – das Teil wandert mit, wenn man Ziel- oder Spielerfenster verschiebt.
-- protected: Teil hängt an einem geschützten Fenster – Position nur außerhalb des Kampfs setzen.
function ns.Movable(frame, key, label, anchor, protected)
    if not (Core.Mover and type(frame) == "table") then return nil end
    local ok, part = pcall(Core.Mover.Register, frame, { key = ADDON .. "." .. key, label = label, owner = ADDON,
        anchor = anchor, protected = protected })
    if not ok then
        ns.Error(part, "Mover " .. key)
        return nil
    end
    return part
end

-- Die gespeicherte Lage eines Teils (ns.Movable) um die Hälfte einer Größenänderung nachführen, damit seine Mitte
-- stehen bleibt. ezCore merkt sich nach dem Ziehen eine Ecke (Core.QuadrantPos: BOTTOMLEFT, TOPRIGHT …), keine Mitte;
-- ohne Ausgleich wüchse das Teil von dieser Ecke weg. Ohne gespeicherte Lage (Standardanker) ist nichts zu tun.
-- dw, dh: Änderung von Breite und Höhe. Eine Stelle für das Bereit-Symbol (Symbol.KeepCenter) und die Combo-Leiste.
-- → true, wenn die Lage gerückt wurde.
function ns.KeepCenter(part, dw, dh)
    dw, dh = ns.Num(dw) or 0, ns.Num(dh) or 0
    if (dw == 0 and dh == 0) or type(part) ~= "table" or type(part.Position) ~= "function" then return false end
    local pos = part:Position()
    local point = type(pos) == "table" and pos.point or nil
    if type(point) ~= "string" then return false end
    local x, y = ns.Num(pos.x) or 0, ns.Num(pos.y) or 0
    if point:find("LEFT", 1, true) then x = x - dw / 2 elseif point:find("RIGHT", 1, true) then x = x + dw / 2 end
    if point:find("TOP", 1, true) then y = y + dh / 2 elseif point:find("BOTTOM", 1, true) then y = y - dh / 2 end
    if x == pos.x and y == pos.y then return false end
    Core.StorePosition(part.key, { point = point, relPoint = pos.relPoint or point, x = x, y = y })
    part:Apply()
    return true
end

---------------------------------------------------------------------------
-- Eigene Helfer von ezCombat
---------------------------------------------------------------------------

-- Waffenverzauberung auf Zeit (Gift, Wetzstein, Waffenzauber) beider Hände: true, hasMain, mainMs, hasOff, offMs wie
-- Blizzards GetWeaponEnchantInfo, sonst false. Seit Welle 23 (A2) der gemeinsame Leser von ezCore
-- (Core.WeaponEnchantInfo: C_PaperDollInfo je Platz, dann C_Item, zuletzt das Globale; eine gesperrte Art kommt als
-- „verzaubert?“ zurück, der Aufrufer behält dann den gemerkten Stand – Leitlinie 6). Der Name bleibt als
-- Weiterleitung (Leitlinie 8).
ns.WeaponEnchantInfo = Core.WeaponEnchantInfo

-- Die Daten im Kampf können geheim sein (Midnight-Sperren in WoW Forever). Jede Funktion merkt sich,
-- wenn sie deshalb nichts tun konnte; /ezcombat status zeigt es an.
-- Regeln (Leitlinie 6, Vollprüfung W-03):
--   • Gesperrt heißt unbekannt – nie 0, nie „abgelaufen“, nie ein geratener Ersatzwert. Die Hilfe ruht, vermerkt es
--     hier (ns.NoteSecret) und sagt es in /ezk status und im Tooltip ihres Schalters, statt still auszufallen:
--     Kraft ("power": Energie-Tick, 5-Sekunden-Regel, Zahlen-Bedingungen der Rotation), Combo-Punkte ("combo":
--     Finisher-Hinweis, Combo-Leiste), Restzeit der Waffenverzauberung ("enchants").
--   • Dauerzustand statt Störung (ns.SECRET_NORMAL): Das Leben gibt Forever Addons nie heraus, auch nicht für die
--     eigene Einheit und außerhalb des Kampfes. /ezk status führt es deshalb nicht unter „Zuletzt gesperrte Daten“,
--     sondern als eigene, ruhige Zeile (Hints.lua: Hinrichten folgt allein der Prüfung des Spiels).
--   • Wo ezCombat einen Wert nur anzeigt (Text „Leben: …“, Kraft als Zahl), nimmt es ezCore.UnitHealthText,
--     ezCore.UnitPowerText bzw. ezCore.FormatSecret (docs/ezcore.md „Gesperrte Werte anzeigen“) – der Client setzt
--     den gesperrten Wert dann selbst ein. Heute hat ezCombat keine solche reine Anzeige.
-- ns.NoteSecret(feature) und ns.secretSeen kommen aus dem Gerüst (Core.NewModule); ns.SecretLine (unten) kennt
-- den Dauerzustand.
ns.SECRET_NORMAL = { health = true }

-- Ist eine Addon-Sperre des Spiels gerade aktiv? true/false, nil = unbekannt (ohne C_RestrictedActions).
-- Weiterleitung an ezCore (Core.RestrictionActive, CB-22): ezCore merkt sich den Zustand aus dem Ereignis, weil
-- Blizzards Abfrage währenddessen „nein“ antwortet. Die Namen bleiben Blizzards (Enum.AddOnRestrictionType) – sie
-- benennen die Zeilen in /ezk status (RESTRICTION_<Name>).
ns.RESTRICTIONS = { "Combat", "Encounter", "ChallengeMode", "PvPMatch", "Map", "Chat" }
local RESTRICTION_KEY = { Combat = "combat", Encounter = "encounter", ChallengeMode = "challenge", PvPMatch = "pvp",
    Map = "map", Chat = "chat" }
function ns.RestrictionActive(name)
    local key = RESTRICTION_KEY[name]
    if not key or type(Core.RestrictionActive) ~= "function" then return nil end
    return Core.RestrictionActive(key)
end

-- Zuhören, wenn eine Addon-Sperre beginnt oder endet: eine Stelle für Auras, Buffs, MeterFrames und MeterSummary.
-- Über ezCore (Core.OnRestrictionChanged, ab ezCore 1.12.0). Fehlt der Helfer (zu altes ezCore: Core.NewModule
-- sperrt das Modul dann nur und meldet die Mindestversion, die Dateien laden trotzdem), bricht das Laden nicht ab –
-- dann hört ezCombat wie früher selbst auf Blizzards Ereignis. fn bekommt keine Werte (die Aufrufer lesen neu).
function ns.OnRestrictionChanged(fn)
    local handler = function() fn() end
    if type(Core.OnRestrictionChanged) == "function" then return Core.OnRestrictionChanged(handler, ADDON) end
    return ns.On("ADDON_RESTRICTION_STATE_CHANGED", handler)
end

-- Schalter des Spiels (CVars) für Blizzards eigene Anzeigen: Schlagtimer, Zahlen auf Abklingzeiten,
-- Schadensanzeige. Die CVar ist die einzige Quelle; ezCombat speichert den Wert nicht noch einmal.
function ns.CVarOn(name)
    local value = ns.CVar(name)
    return value == "1" or value == 1 or value == true
end

-- Schaltet eine CVar um und meldet das Ergebnis im Chat. onText/offText: Meldung danach. Im Kampf schaltet der
-- Knopf nichts und sagt es (Core.SwitchCVar, T2-5 Gesamtreview 18.11.2026 – wie der Schlagtimer).
function ns.ToggleCVar(name, onText, offText, failText)
    local on = not ns.CVarOn(name)
    local ok, why = Core.SwitchCVar(name, on and "1" or "0")
    if not ok then
        if why == "combat" then
            Core.CombatNotice(ns, Core.L.CVAR_WHAT)   -- ezCores Satz zur Kampfsperre (T18-1)
        else
            ns.Print(failText or L.CVAR_FAILED)
        end
        return false
    end
    ns.Print(on and onText or offText)
    return true
end

---------------------------------------------------------------------------
-- Datenbank
---------------------------------------------------------------------------

-- Schalter entfernter Funktionen: Beim Laden fliegen sie aus den gespeicherten Einstellungen. Ab der Einstellungs-Prüfung
-- vom 19.11.2026 auch die fest eingebauten bzw. zusammengelegten (ns.MigrateSettings1911 liest die zusammengelegten
-- vorher einmal aus).
ns.REMOVED_SETTINGS = { "fadeFrames", "fadeAlpha",
    "rotationOffBar", "symbolWaitCooldown", "symbolWaitPower", "symbolWaitRange", "rotationBook", "rotationComputed",
    "meterHighlight", "meterReport", "meterFramesTooltip", "ready", "bigAuras", "combo",
    "bigAuraSize" }   -- Auren-Größe im Zielfenster entfernt am 22.11.2026 (Taint, Entscheidung „Ganz entfernen“)

-- Einstellungs-Prüfung vom 19.11.2026 (Entscheidung des Nutzers „Ja, alle umsetzen“): gespeicherte Werte der
-- zusammengelegten Schalter einmal übernehmen – in den Einstellungen und in jedem gesicherten Profil (ezCores
-- Core.MigrateOnce, Merker settings1911). Fest eingebaute Schalter („immer an“) werden nicht gelesen, ihr alter Wert
-- gilt nicht mehr.
--   showNext "off"          → rotation aus (der eine Ausschalter), showNext zurück auf den Standard (Nr. 69)
--   ready false             → showReady "off" (Nr. 70/71)
--   combo false             → comboScale 100 = Blizzards Größe (Nr. 73; Bedeutung vor dem 23.11.2026, danach stellt
--                             ns.AdoptCombo2311 den Wert um)
-- Danach fliegen die alten Schlüssel aus Einstellungen und Profilen (ns.REMOVED_SETTINGS), dazu der Merker der
-- früher gemerkten Zauberbuch-Seite (rotationBookOpen; das Buch öffnet immer auf Blizzards Reiter).
function ns.AdoptSettings1911(settings)
    if type(settings) ~= "table" then return end
    if settings.showNext == "off" then
        settings.rotation = false
        settings.showNext = ns.DEFAULTS.showNext
    end
    if settings.ready == false then settings.showReady = "off" end
    if settings.combo == false then settings.comboScale = ns.COMBO_SCALE_1911.off end
    for _, key in ipairs(ns.REMOVED_SETTINGS) do settings[key] = nil end
end

-- Wer nur die nächste Fähigkeit aus hatte, verliert mit dem einen Ausschalter auch „Vor dem Kampf“ und den Reiter
-- „Rotation“ – das meldet ezCombat einmal im Chat (db.notice1911, ns.Notice1911; Gegenprüfung 19.11.2026).
function ns.NeedsNotice1911(settings)
    return type(settings) == "table" and settings.showNext == "off" and settings.rotation ~= false
        and settings.rotationPrep ~= false or false
end

function ns.MigrateSettings1911(db)
    return Core.MigrateOnce(db, "settings1911", function()
        if ns.NeedsNotice1911(db.settings) then db.notice1911 = true end
        ns.AdoptSettings1911(db.settings)
        for _, profile in pairs(type(db.profiles) == "table" and db.profiles or {}) do
            ns.AdoptSettings1911(type(profile) == "table" and profile.settings or nil)
        end
        db.rotationBookOpen = nil
        return true
    end)
end

-- Combo-Punkte, Entscheidung des Nutzers vom 23.11.2026 („Ziel aus, ein Regler“): comboScale meinte bis dahin nur
-- Blizzards Punkte am Zielporträt, in Prozent von Blizzards Größe dort (pointScale 0,6 der Vorlage; Standard 150,
-- 100 = Blizzards Größe, also aus). Seitdem: Prozent der Vorlage (20 px) für die Leiste und, wenn an, das Ziel.
--   eigene Größe 110 … 200  → dieselbe Größe am Ziel, jetzt für beide (alter Wert × 0,6, auf den Schritt des Reglers
--                             gerundet: höchstens 0,4 px Unterschied)
--   alter Standard 150      → neuer Standard 100 (ezCore schreibt Standardwerte in den Speicher – 150 heißt fast immer
--                             „nie verstellt“); die Leiste bleibt so groß wie bisher
--   100 und darunter („aus“) → neuer Standard 100: Wer die Vergrößerung am Ziel aus hatte, behält die Leiste in
--                             Blizzards Größe (die exakte Größe am Ziel wären 60 %, die Leiste schrumpfte dann auf 12 px)
-- comboTarget („Blizzards Punkte am Zielporträt“) ist danach für alle aus – auch für bisherige Nutzer (die Entscheidung).
ns.COMBO_SCALE_1911 = { default = 150, off = 100, base = 0.6 }

function ns.ComboScaleFrom1911(old)
    local default, limit, was = ns.DEFAULTS.comboScale, ns.LIMITS.comboScale, ns.COMBO_SCALE_1911
    if type(old) ~= "number" or old ~= old or old == math.huge then return default end
    if old <= was.off or old == was.default then return default end
    local value = math.floor(old * was.base / limit[3] + 0.5) * limit[3]
    return math.max(limit[1], math.min(limit[2], value))
end

-- Eine Einstellungs-Tabelle (Einstellungen, gesichertes Profil, Export) umstellen. Erkennungszeichen der neuen
-- Bedeutung ist comboTarget: Jeder Export und jedes Profil nach dem 23.11.2026 trägt ihn (Profiles.Snapshot und ezCores
-- „Alles sichern“ nehmen alle Schlüssel aus ns.DEFAULTS mit). force: trotzdem umstellen – für ezCombatDB.settings, wo
-- ezCore die Standardwerte (also auch comboTarget) schon vor ns.OnLoad ergänzt. Ohne comboScale ist nichts umzustellen
-- (ein Text bekommt dann auch kein comboTarget – sonst wäre ein Import ohne einen gültigen Wert brauchbar; beim
-- Übernehmen gilt der Standard „aus“). → true, wenn umgestellt.
function ns.AdoptCombo2311(settings, force)
    if type(settings) ~= "table" or type(settings.comboScale) ~= "number" then return false end
    if settings.comboTarget ~= nil and not force then return false end
    settings.comboScale = ns.ComboScaleFrom1911(settings.comboScale)
    settings.comboTarget = false
    return true
end

-- Einmal beim Laden (Merker combo2311): Einstellungen und jedes gesicherte Profil. Alte Exporte und Sicherungen stellt
-- ns.Profiles.Adopted beim Einfügen um (dieselbe Funktion für ezCores „Alles übernehmen“, ns.ImportLegacy).
-- db.comboBarShift: Die Leiste war bis dahin immer 100 % groß – Combo.TakeShift führt die gespeicherte Lage einer
-- verschobenen Leiste einmal nach, sobald sie angemeldet ist.
function ns.MigrateCombo2311(db)
    return Core.MigrateOnce(db, "combo2311", function()
        ns.AdoptCombo2311(db.settings, true)
        db.comboBarShift = true
        for _, profile in pairs(type(db.profiles) == "table" and db.profiles or {}) do
            ns.AdoptCombo2311(type(profile) == "table" and profile.settings or nil)
        end
        return true
    end)
end

-- Große Symbole über dem Zielfenster ab Werk aus (Entscheidung des Nutzers vom 23.11.2026, wörtlich: „ist das hier
-- neu? wenn ja dann standardmäßig aus, sehe keinen nutzen drin“, auf die Rückfrage „Ja, ab Werk aus (Empfohlen)“).
-- Einmal (Merker dots2311): Einstellungen und jedes gesicherte Profil mit dem alten Standard (an) bekommen den neuen.
-- ezCore speichert Standardwerte mit – „nie geändert“ und „selbst eingeschaltet“ sind nicht zu unterscheiden; wer die
-- Reihe will, schaltet sie danach wieder ein (die Wahl bleibt, der Merker verhindert ein zweites Umstellen).
function ns.MigrateDots2311(db)
    return Core.MigrateOnce(db, "dots2311", function()
        local function Adopt(settings)
            if type(settings) == "table" and settings.dots == true then settings.dots = false end
        end
        Adopt(db.settings)
        for _, profile in pairs(type(db.profiles) == "table" and db.profiles or {}) do
            Adopt(type(profile) == "table" and profile.settings or nil)
        end
        return true
    end)
end

-- Schadensvergleich unter dem Symbol ab Werk aus (Entscheidung des Nutzers vom 24.11.2026, „Ja, umbauen“). Einmal (Merker
-- symbolText2411), wie MigrateDots2311: Der alte Standard (an) ist von „selbst eingeschaltet“ nicht zu unterscheiden.
function ns.MigrateSymbolText2411(db)
    return Core.MigrateOnce(db, "symbolText2411", function()
        local function Adopt(settings)
            if type(settings) == "table" and settings.rotationValuesText == true then settings.rotationValuesText = false end
        end
        Adopt(db.settings)
        for _, profile in pairs(type(db.profiles) == "table" and db.profiles or {}) do
            Adopt(type(profile) == "table" and profile.settings or nil)
        end
        return true
    end)
end

-- Beim Laden (Gerüst: opts.onLoad, nach dem Ergänzen der Standardwerte). Die Umstellungen unten laufen je einmal
-- (eigene Merker in ezCombatDB); für einen neuen Speicher ergeben sie dieselben Werte wie die Standardwerte.
function ns.OnLoad(db)
    -- 1.7 (Spieltest: „ezcombat symbol kommt viel zu selten“): „wieder bereit“ ab 5 s statt 8 s – nur, wer noch
    -- den alten Standard hatte; eine eigene Wahl bleibt.
    if not db.readyMin17 then
        if db.settings.readyMin == 8 then db.settings.readyMin = 5 end
        db.readyMin17 = true
    end
    -- CB-N1 (Wunsch des Nutzers vom 14.11.2026 nach dem Probe-Lauf, ersetzt die Umstellung „Als Nächstes ab Werk aus“
    -- vom selben Tag, Merker nextSymbolOff): Je Meldungsart eine Auswahl statt zweier Kästchen. Einmal aus den alten
    -- Kästchen übernehmen – nur, wenn es sie im Speicher gibt (ein neuer Speicher behält die Standardwerte); die alten
    -- Werte bleiben stehen (umkehrbar). „Läuft aus“: Mitte, wenn DoT oder Buff dort standen, Leuchten wie das Kästchen
    -- „Passender Aktionsknopf leuchtet mit“. „Wieder bereit“ leuchtete immer. Die nächste Fähigkeit steht nach dem
    -- Wunsch groß in der Mitte; wer das Leuchten am Knopf abgeschaltet hatte, behält es aus.
    if not db.centralDisplay then
        local s = db.settings
        if s.symbolDots ~= nil or s.buffPulse ~= nil or s.dotButton ~= nil then
            s.showExpiring = ns.ShowValue(s.symbolDots ~= false or s.buffPulse ~= false, s.dotButton ~= false)
        end
        if s.readyPulse ~= nil then s.showReady = ns.ShowValue(s.readyPulse ~= false, true) end
        if s.rotationGlow ~= nil then s.showNext = ns.ShowValue(true, s.rotationGlow ~= false) end
        db.centralDisplay = true
    end
    -- Spieltest 15.11.2026, Befund 2 („dämonenhaut oder wichtel werden nicht mehr durch ezcombat in der mitte
    -- angezeigt“): „Vor dem Kampf“ stand in Städten und Gasthäusern nur als Leuchten am Knopf, weil
    -- rotationPrepRest ab Werk aus war – der Nutzer hatte nichts umgestellt. Neuer Standard: an. Einmal übernehmen:
    -- Wer den alten Standard (aus) hat, bekommt den neuen – in den Einstellungen und in jedem gesicherten Profil.
    if not db.prepRestDefault then
        if db.settings.rotationPrepRest == false then db.settings.rotationPrepRest = true end
        for _, profile in pairs(type(db.profiles) == "table" and db.profiles or {}) do
            local settings = type(profile) == "table" and profile.settings
            if type(settings) == "table" and settings.rotationPrepRest == false then settings.rotationPrepRest = true end
        end
        db.prepRestDefault = true
    end
    -- Entscheidung des Nutzers vom 16.11.2026 (Nr. 7, vorläufig nach Empfehlung): Symbolgrößen ab Werk wie Blizzards
    -- Aktionsknöpfe (45 Mitte, 30 links und rechts) statt 52/36. Einmal übernehmen: Wer genau den alten Standard
    -- gespeichert hat, bekommt den neuen – in den Einstellungen und in jedem gesicherten Profil; jede andere, eigene
    -- Größe bleibt. Umkehrbar: die drei Zeilen in ns.DEFAULTS (der Merker verhindert nur ein zweites Umstellen).
    if not db.iconSizes45 then
        local OLD = { sizeNext = 52, sizeExpiring = 36, sizeReady = 36 }
        -- Die Mitte soll dabei stehen bleiben (wie beim Ziehen des Reglers): ezCore merkt sich eine Ecke des
        -- Rahmens, also rückt die gespeicherte Lage einmal um die Hälfte nach (Symbol.TakeShift, sobald der Rahmen
        -- mit seiner Lage angemeldet ist). Lagen und Einstellungen gelten für alle Charaktere – einmal genügt.
        if db.settings.sizeNext == OLD.sizeNext then db.iconSizes45Shift = ns.DEFAULTS.sizeNext - OLD.sizeNext end
        local function Adopt(settings)
            if type(settings) ~= "table" then return end
            for key, old in pairs(OLD) do
                if settings[key] == old then settings[key] = ns.DEFAULTS[key] end
            end
        end
        Adopt(db.settings)
        for _, profile in pairs(type(db.profiles) == "table" and db.profiles or {}) do
            Adopt(type(profile) == "table" and profile.settings or nil)
        end
        db.iconSizes45 = true
        if ns.Symbol and ns.Symbol.TakeShift then ns.Symbol.TakeShift() end
    end
    -- Prüfung auf Blizzards Regeln vom 17.11.2026 (V1, Risiko 1; entschieden vom Nutzer am 17.11.2026): „Mitzählen,
    -- wenn das Spiel Werte sperrt“ ist ab Werk aus. Einmal übernehmen: Wer den alten Standard (an) gespeichert hat,
    -- bekommt den neuen – in den Einstellungen und in jedem gesicherten Profil. Umkehrbar ohne Verlust: Der Schalter
    -- steht unter „Erweitert“; welche Stellen umgestellt wurden, merkt db.estimateOff17Was ({ settings = true,
    -- profiles = { [Name] = true } }) – so ließe sich genau das zurückstellen, wenn es je wieder an sein soll. Der Merker
    -- estimateOff17 verhindert ein zweites Umstellen.
    if not db.estimateOff17 then
        local was = { profiles = {} }
        if db.settings.rotationEstimate == true then
            db.settings.rotationEstimate = false
            was.settings = true
        end
        for name, profile in pairs(type(db.profiles) == "table" and db.profiles or {}) do
            local settings = type(profile) == "table" and profile.settings
            if type(settings) == "table" and settings.rotationEstimate == true then
                settings.rotationEstimate = false
                was.profiles[name] = true
            end
        end
        if was.settings or next(was.profiles) then db.estimateOff17Was = was end
        db.estimateOff17 = true
    end
    -- Spielbefund vom 18.11.2026 (S-1811-Gruppenrahmen): Die Linien der Kampfanzeige liegen auf Blizzards 7 px hohem
    -- Manabalken, „Höhe der Balken“ ab Werk 2 px statt 5 px (Regler 1–3 px). ezCore schreibt alle Standardwerte in
    -- den Speicher – jeder bisherige Nutzer hätte also 5 gespeichert (gekappt 3 px, der ganze Manabalken verdeckt).
    -- Einmal übernehmen (Gegenprüfung vom 18.11.2026): Wer genau den alten Standard 5 hat, bekommt den neuen – in den
    -- Einstellungen und in jedem gesicherten Profil; jeder andere, eigene Wert bleibt (und wird wie bisher gekappt).
    -- Seit dem 20.11.2026 ist der Standard wieder 5 – der Schritt schreibt dann nur noch 5 über 5 und setzt die Marke;
    -- das Zurück auf 5 für alle mit 2 macht der folgende Schritt (meterHeight20).
    if not db.meterHeight18 then
        local OLD = 5
        if db.settings.meterFramesHeight == OLD then db.settings.meterFramesHeight = ns.DEFAULTS.meterFramesHeight end
        for _, profile in pairs(type(db.profiles) == "table" and db.profiles or {}) do
            local settings = type(profile) == "table" and profile.settings
            if type(settings) == "table" and settings.meterFramesHeight == OLD then
                settings.meterFramesHeight = ns.DEFAULTS.meterFramesHeight
            end
        end
        db.meterHeight18 = true
    end
    -- Spieltest vom 20.11.2026 („der balken ist kaum sichtbar ... halb so hoch wie die mana ... wieder am rahmen unten“):
    -- Balken wieder unter dem Rahmen, ab Werk 5 px (gekappt auf halbe Manabalken-Höhe). Wer genau den Standard 2 der
    -- Fassung vom 18.11.2026 gespeichert hat (ezCore schreibt Standardwerte in den Speicher), bekommt einmal den neuen –
    -- in den Einstellungen und in jedem gesicherten Profil; jeder andere Wert bleibt.
    if not db.meterHeight20 then
        local OLD = 2
        if db.settings.meterFramesHeight == OLD then db.settings.meterFramesHeight = ns.DEFAULTS.meterFramesHeight end
        for _, profile in pairs(type(db.profiles) == "table" and db.profiles or {}) do
            local settings = type(profile) == "table" and profile.settings
            if type(settings) == "table" and settings.meterFramesHeight == OLD then
                settings.meterFramesHeight = ns.DEFAULTS.meterFramesHeight
            end
        end
        db.meterHeight20 = true
    end
    -- Entscheidung des Nutzers, 14.11.2026 („Funktion entfernen“): „Spielerfenster durchscheinend“ gibt es nicht
    -- mehr (auf Forever blendete es nie aus, weil das Leben immer gesperrt ist). Gespeicherte Schalter von früher
    -- still verwerfen – sie hätten sonst keinen Leser mehr. Vorher die Einstellungs-Prüfung vom 19.11.2026 (liest die
    -- zusammengelegten Schalter einmal aus, bevor sie fliegen).
    ns.MigrateSettings1911(db)
    -- Combo-Punkte (Entscheidung 23.11.2026): ein Regler für Leiste und Ziel, Blizzards Punkte am Ziel ab Werk aus –
    -- nach der Prüfung vom 19.11.2026, die comboScale noch in der alten Bedeutung setzt
    ns.MigrateCombo2311(db)
    -- Große Symbole über dem Zielfenster ab Werk aus (Entscheidung 23.11.2026)
    ns.MigrateDots2311(db)
    -- Schadensvergleich unter dem Symbol ab Werk aus (Entscheidung 24.11.2026)
    ns.MigrateSymbolText2411(db)
    -- auch in jedem gesicherten Profil: Die Einmal-Umstellung oben lief bei den meisten schon (Merker settings1911),
    -- später entfernte Schlüssel (bigAuraSize, 22.11.2026) blieben sonst dort liegen (Befund des code-reviewers)
    for _, key in ipairs(ns.REMOVED_SETTINGS) do db.settings[key] = nil end
    for _, profile in pairs(type(db.profiles) == "table" and db.profiles or {}) do
        local saved = type(profile) == "table" and profile.settings
        if type(saved) == "table" then
            for _, key in ipairs(ns.REMOVED_SETTINGS) do saved[key] = nil end
        end
    end
end

---------------------------------------------------------------------------
-- Vorschau: jede Funktion zeigt auf Knopfdruck, wie sie aussieht (Einstellungen, /ezcombat test)
---------------------------------------------------------------------------

ns.previews = {}
-- order bestimmt die Reihenfolge, fn() zeigt die Vorschau und liefert true, wenn etwas zu sehen war.
function ns.AddPreview(key, order, fn)
    table.insert(ns.previews, { key = key, order = order, fn = fn })
    table.sort(ns.previews, function(a, b) return a.order < b.order end)
end

function ns.Preview(key)
    local shown = 0
    for _, preview in ipairs(ns.previews) do
        if key == nil or preview.key == key then
            local ok, result = pcall(preview.fn)
            if not ok then
                ns.Error(result, "Preview " .. preview.key)
            elseif result then
                shown = shown + 1
            end
        end
    end
    return shown
end

---------------------------------------------------------------------------
-- Slash-Befehle
---------------------------------------------------------------------------

-- Gesperrte Daten (Gerüst: ns.SecretLine → „Zuletzt gesperrte Daten: …“ oder nil). Was auf Forever immer gesperrt
-- ist (Leben, ns.SECRET_NORMAL), zählt nicht als Störung – es steht als eigene Zeile in ns.PrintStatus.
function ns.SecretLine()
    local seen = {}
    for feature, when in pairs(ns.secretSeen) do
        if not ns.SECRET_NORMAL[feature] then
            local name = L["FEATURE_" .. feature] or feature
            table.insert(seen, ("%s (%s)"):format(name, L.STATUS_AGO:format(Core.Duration(Core.Uptime() - when, true))))
        end
    end
    if #seen == 0 then return nil end
    table.sort(seen)
    return L.STATUS_SECRET:format(table.concat(seen, ", "))
end

function ns.PrintStatus()
    ns.Print(ns.StatusHeader())
    local active = {}
    for _, name in ipairs(ns.RESTRICTIONS) do
        local state = ns.RestrictionActive(name)
        if state == nil then
            active = nil
            break
        end
        if state then table.insert(active, L["RESTRICTION_" .. name] or name) end
    end
    if active == nil then
        ns.Print(L.STATUS_NO_API)
    elseif #active == 0 then
        ns.Print(L.STATUS_FREE)
    else
        ns.Print(L.STATUS_LOCKED:format(table.concat(active, ", ")))
    end
    -- Was auf Forever immer gesperrt ist (Leben), zählt nicht als Störung: eigene Zeile statt „Zuletzt gesperrt“.
    local normal = {}
    for feature in pairs(ns.secretSeen) do
        if ns.SECRET_NORMAL[feature] then
            table.insert(normal, (L["FEATURE_" .. feature] or feature) .. ": " .. L["STATUS_NORMAL_" .. feature])
        end
    end
    table.sort(normal)
    -- Zeilen der Teile (ns.AddStatusLine aus dem Gerüst, z. B. Verträglichkeit mit ClassicUIForever). Das Gerüst
    -- hängt ns.SecretLine ans Ende: Die wird hier abgenommen und oben gezeigt, ohne zwei Texte zu vergleichen (beide
    -- nennen „vor N Sek.“ zu zwei Zeitpunkten und können sich um eine Sekunde unterscheiden).
    local statusLines = ns.StatusLines()
    local secret = nil
    if ns.SecretLine() ~= nil then secret = table.remove(statusLines) end
    if secret then
        ns.Print(secret)
    else
        ns.Print(#normal > 0 and L.STATUS_NO_OTHER_SECRET or L.STATUS_NO_SECRET)
    end
    for _, line in ipairs(normal) do ns.Print(line) end
    for _, line in ipairs(statusLines) do ns.Print(line) end
end

-- Eigene Befehlswörter für das Gerüst (opts.slash.extra): true, wenn ezCombat den Befehl erledigt hat.
-- Alle Hilfen nacheinander vorführen; zeigt keine etwas, sagt der Chat es (Hauptfunktion nach Entscheidung 5)
function ns.PreviewAll()
    if ns.Preview() == 0 then ns.Print(L.PREVIEW_NOTHING) end
end

-- Weg zu einer Einstellung auf ezCombats Seite (Core.SettingsPathText, T18-18): Abschnitt und Option als Schlüssel
function ns.PathText(section, option)
    return Core.SettingsPathText(ADDON, section, option, L)
end

-- Klick-Hinweis „Klick: …“ in ezCores Form (Core.ClickText, T18-9); button („left“, „right“) nur, wenn derselbe
-- Tooltip auch eine andere Taste nennt – dann „Linksklick:“ statt „Klick:“
function ns.ClickText(text, button)
    return Core.ClickText(button, nil, text)
end

function ns.SlashExtra(cmd, rest)
    if cmd == "test" or cmd == "vorschau" or cmd == "preview" then
        ns.PreviewAll()
        return true
    elseif cmd == "werte" or cmd == "values" or cmd == "measure" then
        ns.RotationMeasure.Show()
        return true
    elseif cmd == "bericht" or cmd == "report" then
        local where = Core.ParseSlash(rest)
        local target = ({ gruppe = "GROUP", group = "GROUP", gilde = "GUILD", guild = "GUILD" })[where] or "SELF"
        ns.Meter.Report(nil, target)
        return true
    end
    return false
end

---------------------------------------------------------------------------
-- Addon-Knopf an der Minikarte
---------------------------------------------------------------------------

-- Entscheidung 5 vom 18.11.2026 (Gesamtreview T18-3, T16-10): Linksklick führt alle Hilfen vor (vorher Rechtsklick),
-- Rechtsklick öffnet die Einstellungen; Tooltip und Befehlszeile von ezCore.
ezCombat_OnAddonCompartmentClick, ezCombat_OnAddonCompartmentEnter, ezCombat_OnAddonCompartmentLeave =
    Core.CompartmentHandlers({ ns = ns, title = L.TITLE, main = function() ns.PreviewAll() end, mainText = L.MAIN_TEXT })
