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
    symbolCenter = true,    -- ein einzelnes Symbol steht in der Mitte (Wunsch des Nutzers vom 15.11.2026)
    -- Text unter dem Symbol (Symbol.lua; Spielbefund des Nutzers vom 18.11.2026: „viel zu viel text... wenn berhaupt
    -- nötig...“, S-1811-Symboltext): "off" nur das Symbol (ab Werk), "name" eine Zeile mit dem Namen, "full" wie bis
    -- dahin („Als Nächstes: …“ und „wartet: …“). Bis 18.11.2026 gab es keine Wahl, alle sahen „ausführlich“; der
    -- Schlüssel ist neu, also bekommt jeder gespeicherte Stand beim Ergänzen der Standardwerte einmal „aus“ – eine
    -- eigene Wahl gibt es noch nicht, die bleiben müsste. Umkehrbar: dieser Wert.
    symbolText = "off",

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

    -- Hinweise am Aktionsknopf
    reactive = true,        -- Überwältigen, Rache, Gegenangriff, Hinrichten unter 20 % …
    interrupt = true,       -- Ziel wirkt etwas Unterbrechbares
    finisher = true,        -- volle Combo-Punkte

    -- Eigene DoTs/HoTs am Ziel
    dots = true,            -- große Symbole über dem Zielfenster
    dotWarn = 3,            -- Sekunden Restzeit (plus Zauberzeit) für „neu setzen“
    bigAuraSize = 26,       -- eigene Auren in Blizzards Zielfenster; 21 = Blizzards Größe (aus)

    -- Eigene Buffs auf dir
    buffs = true,           -- Aktionsknopf leuchtet kurz vor dem Ablauf (und danach, bis neu gewirkt)
    buffWarn = 10,          -- Sekunden Restzeit (plus Zauberzeit)

    -- Combo-Punkte
    comboScale = 150,       -- Blizzards Punkte am Zielporträt in Prozent; 100 = Blizzards Größe (aus)
    comboBar = true,        -- Reihe unter dem Spielerfenster wie im Original-Retail

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
    meterFramesHeight = 2,     -- Dicke einer Linie auf dem Manabalken der klassischen Rahmen in px (Spielbefund 18.11.2026)
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

-- Grenzen der Regler { min, max, Schritt } und Werte der Auswahlfelder: EINE Stelle für die Einstellungsseite
-- (Options.lua) und die Prüfung importierter Profile (Profiles.lua, CB-44).
ns.LIMITS = {
    sizeNext = { 24, 96, 1 }, sizeExpiring = { 20, 64, 2 }, sizeReady = { 20, 64, 2 }, symbolHold = { 1, 5, 1 },
    readyMin = { 2, 60, 1 }, dotWarn = { 1, 10, 1 }, bigAuraSize = { 21, 34, 1 }, buffWarn = { 5, 60, 5 },
    comboScale = { 100, 200, 10 }, totemWarn = { 2, 15, 1 }, enchantWarn = { 30, 600, 30 },
    meterReportLines = { 3, 10, 1 }, meterFramesHeight = { 1, 3, 1 }, rotationWarn = { 0, 5, 1 },
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
    needs = { "Spells.LockedKind", "WeaponEnchantInfo", "ApplySetting", "GroupFrames.TooltipUnit",
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
    "PlaySound", "Spells.CONJURED" },
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

---------------------------------------------------------------------------
-- Eigene Helfer von ezCombat
---------------------------------------------------------------------------

-- Waffenverzauberung auf Zeit (Gift, Wetzstein, Waffenzauber) beider Hände: true, hasMain, mainMs, hasOff, offMs wie
-- Blizzards GetWeaponEnchantInfo, sonst false. Seit Welle 23 (A2) der gemeinsame Leser von ezCore
-- (Core.WeaponEnchantInfo: das Globale zuerst, dann C_Item.GetWeaponEnchantInfo je Hand; eine gesperrte Art kommt als
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
    "meterHighlight", "meterReport", "meterFramesTooltip", "ready", "bigAuras", "combo" }

-- Einstellungs-Prüfung vom 19.11.2026 (Entscheidung des Nutzers „Ja, alle umsetzen“): gespeicherte Werte der
-- zusammengelegten Schalter einmal übernehmen – in den Einstellungen und in jedem gesicherten Profil (ezCores
-- Core.MigrateOnce, Merker settings1911). Fest eingebaute Schalter („immer an“) werden nicht gelesen, ihr alter Wert
-- gilt nicht mehr.
--   showNext "off"          → rotation aus (der eine Ausschalter), showNext zurück auf den Standard (Nr. 69)
--   ready false             → showReady "off" (Nr. 70/71)
--   bigAuras false          → bigAuraSize 21 = Blizzards Größe (Nr. 72)
--   combo false             → comboScale 100 = Blizzards Größe (Nr. 73)
-- Danach fliegen die alten Schlüssel aus Einstellungen und Profilen (ns.REMOVED_SETTINGS), dazu der Merker der
-- früher gemerkten Zauberbuch-Seite (rotationBookOpen; das Buch öffnet immer auf Blizzards Reiter).
function ns.AdoptSettings1911(settings)
    if type(settings) ~= "table" then return end
    if settings.showNext == "off" then
        settings.rotation = false
        settings.showNext = ns.DEFAULTS.showNext
    end
    if settings.ready == false then settings.showReady = "off" end
    if settings.bigAuras == false then settings.bigAuraSize = ns.LIMITS.bigAuraSize[1] end
    if settings.combo == false then settings.comboScale = ns.LIMITS.comboScale[1] end
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
    -- Entscheidung des Nutzers, 14.11.2026 („Funktion entfernen“): „Spielerfenster durchscheinend“ gibt es nicht
    -- mehr (auf Forever blendete es nie aus, weil das Leben immer gesperrt ist). Gespeicherte Schalter von früher
    -- still verwerfen – sie hätten sonst keinen Leser mehr. Vorher die Einstellungs-Prüfung vom 19.11.2026 (liest die
    -- zusammengelegten Schalter einmal aus, bevor sie fliegen).
    ns.MigrateSettings1911(db)
    for _, key in ipairs(ns.REMOVED_SETTINGS) do db.settings[key] = nil end
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
