local ADDON, ns = ...
local L = ns.L
local Core = ezCore

-- Einstellungen unter Esc → Optionen → AddOns → ezCollection → ezCombat (Seite von ezCore). Jede Gruppe
-- hat einen Knopf „Zeigen“, der vorführt, wie die Funktion im Spiel aussieht.
local page

---------------------------------------------------------------------------
-- Leuchtfarben: Farbe und Text kommen aus ezCore (Core.GlowColor, Core.GlowLabel) – ezCombat legt keine fest
---------------------------------------------------------------------------

-- Die Arten, in denen ezCombat leuchtet (Reihenfolge der Erklärung).
ns.GLOW_KINDS_USED = { "reactive", "interrupt", "finisher", "dot", "totem", "missing", "ready", "next" }

-- Eine Zeile „Farbe (Gruppe): Bedeutung“ in der Farbe der Art, sonst nil.
function ns.GlowLine(kind)
    local label = kind and Core.GlowLabel and Core.GlowLabel(kind)
    if not label then return nil end
    return Core.ColorCode(Core.GlowColor(kind)) .. label .. "|r"
end

-- Tooltip einer Einstellung, darunter die Farbe, in der sie leuchtet.
local function GlowTip(key, kind)
    local tip, line = L["OPT_" .. key .. "_TIP"], ns.GlowLine(kind)
    return line and (tip .. "\n\n" .. line) or tip
end

-- Tooltip mit dem Hinweis, was bei gesperrten Werten geschieht (feature wie bei ns.NoteSecret: "power", "combo",
-- "enchants") – die Hilfe ruht dann sichtbar statt still; /ezk status nennt es, sobald es wirklich vorkam.
local function LockTip(tip, feature)
    return tip .. "\n\n" .. L["LOCKED_TIP_" .. feature]
end

-- Alle Farben, in denen ezCombat leuchtet, mit Überschrift (Erklärblase).
function ns.GlowLegend()
    local lines = { L.TOUR_COLORS }
    for _, kind in ipairs(ns.GLOW_KINDS_USED) do lines[#lines + 1] = ns.GlowLine(kind) end
    return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Erklärblasen (ezCore.NewTour): beim ersten Öffnen der Einstellungen bzw. beim ersten Zeigen der Teile
-- (Bearbeitungsmodus, „Teile verschieben“). Unsichtbare Ziele überspringt ezCore, ohne sie als gesehen zu merken.
---------------------------------------------------------------------------

local tour

local function FirstVisibleActionButton()
    for _, button in ipairs(ns.Glow.Buttons()) do
        if button:IsVisible() then return button end
    end
    return nil
end

function ns.Tour()
    if tour or not Core.NewTour then return tour end
    tour = Core.NewTour({
        store = function() return ns.db and ns.db.tour end,
        module = ADDON,   -- die Einführung erledigt die Blasen mit der Seite von ezCombat (Core.ModuleTours)
        steps = {
            { key = "settings", target = function() return rawget(_G, "SettingsPanel") end, text = L.TOUR_SETTINGS,
                side = "left" },
            { key = "pulse", target = function() return ns.Ready.PulseFrame() end, text = L.TOUR_PULSE, side = "right" },
            { key = "dots", target = function() return ns.Auras.TourTarget() end, text = L.TOUR_DOTS,
                side = "above" },
            { key = "combo", target = function() return rawget(_G, "ezCombatComboBar") end, text = L.TOUR_COMBO,
                side = "below" },
            -- Am Aktionsknopf nur angedockt (eigener Rahmen unter UIParent, Blizzards Knopf bleibt unberührt).
            { key = "colors", target = FirstVisibleActionButton, text = ns.GlowLegend(), side = "above",
                parent = UIParent },
            -- Reiter „Rotation“ am Zauberbuch: erscheint beim ersten Öffnen des Buchs (ns.ShowTourStep)
            { key = "rotationTab", target = function() return ns.RotationBook and ns.RotationBook.Tab() end,
                text = L.TOUR_ROTATION, side = "right" },
            -- Auf der aufgeschlagenen Seite: am Knopf „Zurück zur Vorlage“ – erklärt Kästchen und Pfeile je Schritt
            { key = "rotationEdit",
                target = function() return ns.RotationBook and ns.RotationBook.ActionButton("reset") end,
                text = L.TOUR_ROTATION_EDIT, side = "right" },
        },
    })
    return tour
end

-- parent: Fenster, mit dem die Blasen verschwinden (Einstellungen); ohne Angabe hängt jede Blase an ihrem Teil.
-- Nur außerhalb des Kampfs (eine Blase am Aktionsknopf soll nie im Kampf entstehen).
function ns.StartTour(parent)
    if ns.InCombat() then return nil end
    local t = ns.Tour()
    if not t then return nil end
    t.parent = parent
    return t:Start(parent)
end

-- Nur eine Blase des Rundgangs zeigen (z. B. am Reiter „Rotation“, sobald das Zauberbuch aufgeht), nicht den ganzen.
-- → Blase oder nil (schon gesehen, Ziel unsichtbar, im Kampf)
function ns.ShowTourStep(key)
    if ns.InCombat() then return nil end
    local t = ns.Tour()
    if not t or t.hints.Seen(key) then return nil end
    for _, step in ipairs(t.steps) do
        if step.key == key then
            local ok, target = pcall(step.target)
            if ok and type(target) == "table" and target:IsVisible() then
                return t.hints.Show(key, step.parent or target, target, step.text, step.side)
            end
        end
    end
    return nil
end

ns.Listen("PARTS_SHOWING", function(active)
    if active then C_Timer.After(0.3, function() ns.Try("Tour", ns.StartTour) end) end
end)

---------------------------------------------------------------------------
-- Ergänzende Addons (ezCore.AddCompanion): was ezCombat sinnvoll ergänzt. Pflicht ist nur ezCore.
-- Nicht hier: Addons, für die sich ezCombat nur zurückhält (ClassicUIForever).
---------------------------------------------------------------------------

-- Name, Ordner und Adresse stehen EINMAL am Eintrag in ezCore (Core.OTHER_ADDONS.DeadlyBossMods, wie MAP-20 für
-- Tweaks Forever); hier nur key und why.
if Core.AddCompanion then
    Core.AddCompanion(ADDON, { key = "DeadlyBossMods", why = L.COMPANION_WHY_DBM })
end

---------------------------------------------------------------------------
-- Seite
---------------------------------------------------------------------------

local function Register()
    if page then return end
    page = Core.NewSettingsPage(ns)
    if not page then return end

    -- Jedes Steuerelement ist in ezCore einzeln abgesichert: eines darf scheitern, ohne die Seite zu verhindern.

    -- Schalter für Blizzards eigene Anzeigen: Kästchen auf die CVar (ezCore, die CVar ist die einzige Quelle;
    -- im Kampf gilt der Wert ab Kampfende). Ohne Proxy-Einstellungen des Spiels ein Knopf „Ein/Aus“.
    local function CVarCheckbox(key, cvar, toggle)
        if Settings.RegisterProxySetting then
            page:CVarCheckbox(key, cvar)
        else
            page:Button(L["OPT_" .. key], L.OPT_TOGGLE_BUTTON, toggle, L["OPT_" .. key .. "_TIP"])
        end
    end

    local function Show(key)
        return function()
            if ns.Preview(key) == 0 then ns.Print(L.PREVIEW_NOTHING) end
        end
    end

    -- Zeiten, Pixel aus ezCore („8 Sek.“, „2 Min. 30 Sek.“, „26 px“), sonst Einheiten der Seite.
    local function Seconds(value) return Core.Duration(value) end
    local function Percent(value) return Core.Percent(value) end
    local Pixels = Core.Pixels
    -- Regler mit den Grenzen aus ns.LIMITS (Core.lua; dieselben gelten für importierte Profile).
    local function Slider(key, formatter, opts)
        local limit = ns.LIMITS[key]
        page:Slider(key, limit[1], limit[2], limit[3], formatter, nil, opts)
    end
    -- Einträge eines Auswahlfelds aus ns.CHOICES (Core.lua): { { Wert, Text } … }
    local function Choices(key, label)
        local list = {}
        for _, value in ipairs(ns.CHOICES[key]) do list[#list + 1] = { value, label(value) } end
        return list
    end

    -- Allgemein: alles auf einmal vorführen
    page:Button(L.OPT_PREVIEW_ALL, L.OPT_PREVIEW_BUTTON, Show(nil), L.OPT_PREVIEW_ALL_TIP)
    -- Bereit-Symbol, DoT-Reihe und Combo-Leiste verschieben (ezCore.Mover)
    page:MoverButton()

    -- Anzeige über dem Charakter (Symbol.lua, CB-N1): je Meldungsart, wo sie erscheint (über dem Charakter,
    -- Leuchten am Aktionsknopf, beides, aus), dazu die Größe ihres Platzes; wie lange Kurzes steht; Lage über
    -- „Teile verschieben“ (oben) bzw. Blizzards Bearbeitungsmodus.
    page:Header(L.OPT_HEADER_SYMBOL)
    local places = {}
    for _, value in ipairs(ns.SHOW_VALUES) do places[#places + 1] = { value, L["OPT_SHOW_" .. value] } end
    -- Die nächste Fähigkeit ohne „Aus“ (Einstellungs-Prüfung 19.11.2026, Nr. 69): aus nur über „Nächste Aktion vorschlagen“.
    -- „Nicht auf der Leiste“ und „noch nicht bereit“ sind fest eingebaut (Nr. 29–32), „wieder bereit“ hat nur noch die
    -- Auswahl (Nr. 70/71).
    page:Dropdown("showNext", Choices("showNext", function(value) return L["OPT_SHOW_" .. value] end),
        GlowTip("showNext", "next"))
    Slider("sizeNext", Pixels)
    page:Dropdown("showExpiring", places, GlowTip("showExpiring", "dot"))
    Slider("sizeExpiring", Pixels)
    page:Dropdown("showReady", places, GlowTip("showReady", "ready"))
    Slider("sizeReady", Pixels)
    Slider("symbolHold", Seconds)
    page:Checkbox("symbolCenter")
    -- Text unter dem Symbol (S-1811-Symboltext): aus (ab Werk), nur Name, ausführlich
    page:Dropdown("symbolText", Choices("symbolText", function(value) return L["OPT_symbolText_" .. value] end))
    page:Button(L.OPT_PREVIEW, L.OPT_PREVIEW_BUTTON, function() ns.Symbol.Demo() end, L.OPT_PREVIEW_SYMBOL_TIP)

    -- Ob „wieder bereit“ erscheint, sagt nur noch die Auswahl oben (Einstellungs-Prüfung 19.11.2026, Nr. 70/71);
    -- „Zahlen auf Abklingzeiten“ steht nur noch in Blizzards Optionen (Abschnitt 4), /ezk status nennt Stand und Ort.
    page:Header(L.OPT_HEADER_READY)
    Slider("readyMin", Seconds)
    page:Button(L.OPT_PREVIEW, L.OPT_PREVIEW_BUTTON, Show("ready"), L.OPT_PREVIEW_READY_TIP)

    page:Header(L.OPT_HEADER_HINTS)
    page:Checkbox("reactive", GlowTip("reactive", "reactive"))
    page:Checkbox("interrupt", GlowTip("interrupt", "interrupt"))
    page:Checkbox("finisher", LockTip(GlowTip("finisher", "finisher"), "combo"))
    page:Button(L.OPT_PREVIEW, L.OPT_PREVIEW_BUTTON, Show("hints"), L.OPT_PREVIEW_HINTS_TIP)

    page:Header(L.OPT_HEADER_DOTS)
    page:Checkbox("dots", GlowTip("dots", "dot"))
    Slider("dotWarn", Seconds)
    -- Nur der Regler: ganz links ist Blizzards Größe, also aus (Einstellungs-Prüfung 19.11.2026, Nr. 72)
    Slider("bigAuraSize", Pixels)
    page:Button(L.OPT_PREVIEW, L.OPT_PREVIEW_BUTTON, Show("dots"), L.OPT_PREVIEW_DOTS_TIP)

    page:Header(L.OPT_HEADER_BUFFS)
    page:Checkbox("buffs", GlowTip("buffs", "missing"))
    Slider("buffWarn", Seconds)
    page:Button(L.OPT_PREVIEW, L.OPT_PREVIEW_BUTTON, Show("buffs"), L.OPT_PREVIEW_BUFFS_TIP)

    -- Rotation (Rotation.lua): nächste Aktion vorschlagen, Wahl je Charakter, Leuchten, Blizzards Assistent zuerst;
    -- „Vor dem Kampf“ (Dauer-Buffs, Begleiter, Stein, Gift), Abklingzeiten, Flächenmodus, zurück zur Vorlage.
    page:Header(L.OPT_HEADER_ROTATION)
    page:Checkbox("rotation")
    -- alles zur Rotation grau, solange „Nächste Aktion vorschlagen“ aus ist (Rotation.lua: ohne „rotation“ kein
    -- Vorschlag) (Querschnitt „Unterschalter ausgrauen“, Einstellungs-Prüfung 19.11.2026)
    local function rot() return { parent = "rotation" } end
    page:Dropdown("rotationChoice", ns.Rotation.ChoiceValues(), nil, rot())
    page:Checkbox("rotationPrep", GlowTip("rotationPrep", "missing"), rot())
    page:Checkbox("rotationPrepRest", nil, { parent = "rotationPrep",   -- ShowPrep: nur mit „rotation“ und „Vor dem Kampf“
        enabledWhen = function() return ns.Enabled("rotation") and ns.Enabled("rotationPrep") end })
    page:Checkbox("rotationOpener", nil, rot())
    -- Blizzards Regeln (Prüfung 17.11.2026, V1): eigene Empfehlung im Kampf (ab Werk an; aus: nur Blizzards Assistent)
    page:Checkbox("rotationInCombat", nil, rot())
    page:Dropdown("rotationCooldowns", Choices("rotationCooldowns", function(value)
        return L["OPT_rotationCooldowns_" .. value]
    end), nil, rot())
    -- Flächenmodus: auch per Taste (ezCore.Keys „combatAoe“) und Klick auf das Symbol in der Mitte; das Kästchen
    -- bleibt als Spiegel (Einstellungs-Prüfung 19.11.2026, Nr. 100)
    page:Checkbox("rotationAoe", nil, rot())
    page:Checkbox("rotationSide", GlowTip("rotationSide", "next"), rot())
    -- Welle 27: Vorwarnung vor Ablauf einer Abklingzeit (0 = aus)
    Slider("rotationWarn", Seconds, rot())
    -- Blizzards Assistent nur, wenn das Spiel ihn anbietet (auf Forever am 15.11.2026 gemessen: IsAvailable → false):
    -- sonst ist der Schalter ausgegraut, der Tooltip nennt den Grund.
    local _, blizzardRow = page:Checkbox("rotationBlizzard", ns.Rotation.BlizzardTip)
    if type(blizzardRow) == "table" and blizzardRow.AddModifyPredicate then
        blizzardRow:AddModifyPredicate(function() return ns.Rotation.BlizzardAvailable() end)
    end
    -- Reiter „Rotation“ folgt „Nächste Aktion vorschlagen“, berechnete Rotationen stehen immer in der Liste
    -- (Einstellungs-Prüfung 19.11.2026, Nr. 33 und 34)
    -- Anpassungen der gewählten Rotation (aus/an, Reihenfolge) verwerfen – derselbe Knopf steht im Zauberbuch.
    page:Button(L.OPT_rotationReset, L.ROTATION_BOOK_RESET, function()
        local rotation = ns.Rotation.Selected()
        local name = ns.Rotation.Name(rotation)
        if rotation and ns.Rotation.ResetEdits(rotation) then
            ns.Print(L.ROTATION_RESET_DONE:format(name))
        else
            ns.Print(L.ROTATION_RESET_NOTHING:format(name))
        end
    end, L.OPT_rotationReset_TIP)
    page:Button(L.OPT_PREVIEW, L.OPT_PREVIEW_BUTTON, Show("rotation"), L.OPT_PREVIEW_ROTATION_TIP)

    page:Header(L.OPT_HEADER_COMBO)
    -- Nur der Regler: 100 % ist Blizzards Größe, also aus (Einstellungs-Prüfung 19.11.2026, Nr. 73)
    Slider("comboScale", Percent)
    page:Checkbox("comboBar", LockTip(L.OPT_comboBar_TIP, "combo"))
    page:Button(L.OPT_PREVIEW, L.OPT_PREVIEW_BUTTON, Show("combo"), L.OPT_PREVIEW_COMBO_TIP)

    page:Header(L.OPT_HEADER_SWING)
    CVarCheckbox("SWING_GAME", ns.Swing.CVAR, function()
        ns.Swing.SetGameTimer(not ns.Swing.GameTimerOn())
    end)
    page:Checkbox("swingExtras")
    page:Button(L.OPT_PREVIEW, L.OPT_PREVIEW_BUTTON, Show("swing"), L.OPT_PREVIEW_SWING_TIP)

    page:Header(L.OPT_HEADER_POWER)
    page:Checkbox("energyTick", LockTip(L.OPT_energyTick_TIP, "power"))
    page:Checkbox("manaRule", LockTip(L.OPT_manaRule_TIP, "power"))
    page:Button(L.OPT_PREVIEW, L.OPT_PREVIEW_BUTTON, Show("ticks"), L.OPT_PREVIEW_TICKS_TIP)

    page:Header(L.OPT_HEADER_CLASS)
    page:Checkbox("totems", GlowTip("totems", "totem"))
    Slider("totemWarn", Seconds)
    page:Checkbox("enchants", LockTip(L.OPT_enchants_TIP, "enchants"))
    -- Vorwarnung und Ton nur mit „enchants“ (Enchants.lua) (Querschnitt „Unterschalter ausgrauen“, Einstellungs-Prüfung 19.11.2026)
    Slider("enchantWarn", Seconds, { parent = "enchants" })
    page:Checkbox("enchantSound", nil, { parent = "enchants" })
    page:Button(L.OPT_PREVIEW, L.OPT_PREVIEW_BUTTON, function()
        if ns.Preview("totems") + ns.Preview("enchants") == 0 then ns.Print(L.PREVIEW_NOTHING) end
    end, L.OPT_PREVIEW_CLASS_TIP)

    page:Header(L.OPT_HEADER_METER)
    CVarCheckbox("METER_GAME", ns.Meter.CVAR, ns.Meter.ToggleGameMeter)
    -- Eigene Zeile hervorheben und „Bericht in den Chat“ im Zahnrad-Menü sind fest (Einstellungs-Prüfung 19.11.2026,
    -- Abschnitt 4 und Nr. 35); der Regler bestimmt die Zeilen des Berichts.
    Slider("meterReportLines", function(value) return L.UNIT_LINES:format(value) end)
    page:Button(L.OPT_METER_REPORT, L.OPT_METER_REPORT_BUTTON, function() ns.Meter.Report(nil, "SELF") end,
        L.OPT_METER_REPORT_TIP)
    -- Stufe 3 (MeterFrames.lua): Schaden und Heilung an Blizzards Gruppen- und Raidrahmen, je Art ein Schalter;
    -- der Tooltip nennt Details bzw. einen Rahmen-Ersatz, wenn sie laufen.
    page:Checkbox("meterFramesDamage", ns.MeterFrames.Tooltip("meterFramesDamage"))
    page:Checkbox("meterFramesHealing", ns.MeterFrames.Tooltip("meterFramesHealing"))
    -- Zahlen neben den Linien (Spieltest 20.11.2026: rechts neben dem klassischen Rahmen, mit Tooltip); aus: nur Linien
    page:Checkbox("meterFramesNumbers", ns.MeterFrames.Tooltip("meterFramesNumbers"))
    -- Nur die Art der eigenen Rolle (Spieltest 20.11.2026: „angezeigt wird am rahmen nur, was den spieler betrifft“)
    page:Checkbox("meterFramesOwnRole", ns.MeterFrames.Tooltip("meterFramesOwnRole"))
    -- Top-3-Ansicht und weitere Arten (MeterTop.lua, Antwort des Nutzers vom 16.11.2026: „Ja, beides“): Darstellung
    -- (Zeilen, nur die ersten 3, beides) und je weitere Art ein Schalter – dieselben wie im Zahnrad-Menü.
    page:Dropdown("meterFramesView", Choices("meterFramesView", ns.MeterFrames.ViewLabel))
    page:Checkbox("meterFramesInterrupts", ns.MeterFrames.Tooltip("meterFramesInterrupts"))
    page:Checkbox("meterFramesDispels", ns.MeterFrames.Tooltip("meterFramesDispels"))
    page:Checkbox("meterFramesDeaths", ns.MeterFrames.Tooltip("meterFramesDeaths"))
    page:Checkbox("meterFramesThreat", ns.MeterFrames.Tooltip("meterFramesThreat"))
    -- Höhe der Zeilen unter den klassischen Gruppenrahmen (Spieltest 15.11.2026); die Erklärung im Tooltip der Rahmen
    -- ist fest an, solange eine Art an ist (Einstellungs-Prüfung 19.11.2026, Nr. 36).
    Slider("meterFramesHeight", Pixels)
    -- Abschnitt der Balken: aktueller Kampf, gesamt oder ein früherer Kampf (welcher: Zahnrad-Menü der Anzeige).
    page:Dropdown("meterFramesSession", Choices("meterFramesSession", ns.MeterFrames.SessionLabel))
    page:Button(L.OPT_PREVIEW, L.OPT_PREVIEW_BUTTON, Show("meterFrames"), L.OPT_PREVIEW_METER_FRAMES_TIP)
    -- Zusammenfassung nach dem Kampf (MeterSummary.lua): eine Chat-Zeile nur für dich und ein Verlaufseintrag.
    page:Checkbox("meterSummary", ns.MeterSummary.Tooltip())
    page:Button(L.OPT_PREVIEW_METER_SUMMARY, L.OPT_PREVIEW_BUTTON, Show("meterSummary"),
        L.OPT_PREVIEW_METER_SUMMARY_TIP)

    -- Profile (Profiles.lua, CB-44): je Charakter, für die Klasse, je Spezialisierung oder gemeinsam („Standard“);
    -- Auswahl, Kästchen und Knöpfe baut ezCore (page:Profiles) – vor „Erweitert“ (Gesamtreview T9-5).
    if ns.Profiles and ns.Profiles.P then ns.Profiles.section = page:Profiles(ns.Profiles.P, { texts = L }) end

    page:Advanced()
    -- Rotation: Ladungen und Restzeiten aus den eigenen Zaubern mitzählen, wenn das Spiel die Werte sperrt (ab Werk aus:
    -- geht über das hinaus, was Blizzard Addons zeigt – Prüfung auf Blizzards Regeln vom 17.11.2026).
    page:Checkbox("rotationEstimate")
    -- Welle 21: Zauberwerte für die Rotations-Simulation messen (RotationMeasure.lua; auch /ezk werte)
    page:Button(L.OPT_SIM_MEASURE, L.OPT_SIM_MEASURE_BUTTON, function() ns.RotationMeasure.Show() end, L.OPT_SIM_MEASURE_TIP)
    -- „Einstellungen zurücksetzen“ (ezCore): alle Schalter und Regler auf Standard; Blizzards CVars, Lagen der
    -- Teile und gespeicherte Daten bleiben.
    page:ResetButton()
    page:MoverResetButton()
    -- „Erklärung erneut zeigen“: die Erklärblasen beim nächsten Öffnen wieder von vorn.
    if ns.Tour() then page:TourButton(ns.Tour()) end
    page:StatusButton(L.OPT_STATUS_TIP)   -- Beschriftung von ezCore (Gesamtreview T9-2)
    -- „Ergänzende Addons“ mit Knopf zum Kopieren des CurseForge-Links (ezCore), immer zuletzt.
    page:Companions()

    page:Register()
end

ns.OnReady(function() ns.Try("Settings", Register) end)

function ns.OpenSettings()
    local opened = page ~= nil and page:Open()
    -- Erste Erklärblase an den Einstellungen (verschwindet mit ihnen).
    if opened then
        C_Timer.After(0.3, function() ns.Try("Tour", ns.StartTour, rawget(_G, "SettingsPanel")) end)
    end
    return opened
end
