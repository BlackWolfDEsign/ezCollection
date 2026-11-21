local ADDON, ns = ...
local Core = ezCore
local L = ns.L

--[[
    ezTalent – Vorlagen und Auswirkungen an Blizzards Talent- und Vermächtnis-Fenster.

      Traits.lua     Gemeinsamer Trait-Kern (C_Traits, jeder Aufruf geschützt): Klassentalente UND Vermächtnis
                     (Bäume aus Constants.LegacyConsts) – Knoten lesen, Verteilung als Momentaufnahme, gestaffelt anwenden
      Presets.lua    Vorauswahl typischer Bäume (Punkt 2): 43 Bäume aus der Recherche, je Eintrag Quelle mit Stand und
                     Lesedatum, Hotfix-Vermerke – nur Daten in eigener Form
      PresetIDs.lua  Sprachunabhängige Kennung der Talente der Vorauswahl (Zauber-ID, Lage im Baum) – im Spiel erhoben
      Templates.lua  Vorlagen speichern, umbenennen, löschen, als Text teilen und einfügen; Vorauswahl über Zauber-ID
                     bzw. Lage (Ersatz: Namen des Clients) zuordnen und kopieren; Erhebung der Kennungen; passende
                     Rotation (ezCombat)
      Plan.lua       Vorschau einer Vorlage in Blizzards Baum: Zielrang als Zahl an jedem Talent, Planen ohne Punkte
                     („Anpassen“), je Charakter und Baum gemerkt
      Effects.lua    Auswirkungen: gewählte Talente mit dem Text des aktuellen Rangs, nach verändertem Zauber gegliedert,
                     Vorschau „vorher → nachher“, Zeile „verändert durch“ im Zauber-Tooltip
      Computed.lua   Berechnete Talentverteilungen (Welle 21) – nur Daten, geschrieben von tools/talent_sim.lua
      Measure.lua    Messwerte für die Simulation: Grundwerte des Charakters und Talente mit den Zahlen jedes Rangs
      Roster.lua     Übersicht der eigenen Charaktere (ezCores Charakterliste + was ezTalent je Twink merkt) – als
                     Seitenteil „Twinks“ am Talentfenster (UI.lua), Rückfall Text
      UI.lua         Seitenreiter und Seitenteile an PlayerSpellsFrame.TalentsFrame und LegacySystemFrame
      Tour.lua       Rundgang mit Erklärblasen beim ersten Öffnen des Talentfensters (Core.NewTour)
      Options.lua    Einstellungsseite (ezCollection → ezTalent)

    Ablauf am Fenster (Spieltest 14.11.2026): Vorlage oder Vorauswahl in der Liste anklicken » sie liegt als Vorschau im
    Baum (nichts wird gesetzt oder kopiert) » „Übernehmen“ oder „Anpassen“ und „Speichern“.

    Taint: ezTalent schreibt nichts in Blizzards Tabellen und bestätigt nie selbst – „Übernehmen“ legt die Punkte nur
    als gestaffelte Änderung an (C_Traits.PurchaseRank/SetSelection), gültig wird sie mit Blizzards eigenem Knopf; auch
    „Zurücksetzen und übernehmen“ setzt nur gestaffelt zurück (C_Traits.ResetTreeByCurrency wie Blizzards Knopf, nach
    Rückfrage, nur wo der Client es erlaubt). Im Kampf ändert ezTalent nichts.
]]

-- Einstellungs-Prüfung vom 19.11.2026 (Entscheidung des Nutzers „Ja, alle umsetzen“): fest statt Schalter sind
-- „Vorlagen“ an Talent- und Vermächtnis-Fenster (Nr. 37, 39), „Verändert durch“ im Zauber-Tooltip (Nr. 40) und die
-- berechneten Verteilungen in der Liste (Nr. 38); „Vor dem Übernehmen zurücksetzen“ steht als Kästchen bei
-- „Übernehmen“ im Vermächtnis-Seitenteil (Abschnitt 3). Alte gespeicherte Werte fliegen einmal raus
-- (ns.REMOVED_SETTINGS, ns.MigrateSettings1911) – bei „immer an“ gilt der alte Wert nicht mehr.
ns.DEFAULTS = {
    legacyReset = true,     -- Vermächtnis: vor dem Anwenden den Baum zurücksetzen (wie Blizzards Knopf, gestaffelt);
                            -- Kästchen im Vermächtnis-Seitenteil „Vorlagen“ (UI.LegacyResetBox)
    effectsTab = true,      -- Seitenreiter „Auswirkungen“ an beiden Fenstern
    rosterTab = true,       -- Seitenreiter „Twinks“ am Talentfenster (TL-12)
    adviceTab = true,       -- Seitenreiter „Empfehlung“ am Talentfenster (Fragebogen und Bewerten, Spieltest 20.11.2026)
    makeRoom = true,        -- Talentfenster rücken bzw. verkleinern, wenn das Seitenteil rechts nicht passt (TL-13)
    nextPoint = true,       -- beim Stufenaufstieg „Nächster Talentpunkt“ aus der Reihenfolge der Vorlage melden (TL-01)
}
ns.REMOVED_SETTINGS = { "templatesTab", "legacyTab", "effectsTooltip", "computedPresets" }

-- Einmal beim Laden (Gerüst: opts.onLoad, nach dem Ergänzen der Standardwerte): die Schlüssel der fest eingebauten
-- Schalter aus dem Speicher nehmen (ezCores Core.MigrateOnce, Merker settings1911). Ihr alter Wert wird nicht gelesen.
function ns.MigrateSettings1911(db)
    return Core.MigrateOnce(db, "settings1911", function()
        for _, key in ipairs(ns.REMOVED_SETTINGS) do
            if type(db.settings) == "table" then db.settings[key] = nil end
        end
        return true
    end)
end

-- Farben (Design-System 2.5, Welle 22): eine Tabelle für alle Töne des Moduls – Blizzards Farbobjekte bzw. ezCores
-- Rollen statt der eigenen Farbcodes, die bis Welle 22 in UI.lua und Plan.lua von Hand standen (in Klammern).
--   good     Blizzards Grün (Rolle „good“)              (40ff40; Zahl am Talent 0.25, 1, 0.25)
--   bad      Blizzards Rot (Rolle „bad“)                (ff5050; Zahl am Talent 1, 0.3, 0.3)
--   gold     Gold (Rolle „normal“)                      (ffd100, gleicher Ton)
--   orange   Blizzards ORANGE_FONT_COLOR, sonst „warn“  (ff9933; Zahl am Talent 1, 0.6, 0.2)
--   hint     ezCores Grau wie jeder Hinweis (Core.Grey) (999999, aaaaaa)
--   detail   Weiß wie Fließtext (Rolle „highlight“)     (cccccc)
--   locked   Blizzards Grau, ausgegraut (Rolle „gray“)  (Zahl am Talent 0.7, 0.7, 0.7)
--   next     Blizzards LIGHTBLUE_FONT_COLOR, sonst Weiß (80c0ff)
--   invalid  Blizzards Lila der Qualität „episch“ (Core.QualityRGB(4)) – Blizzard hat keinen Ton für „ungültig“;
--            Lila bleibt, damit „ungültig“ sich vom Rot für „zu viel“ abhebt (cc80ff; Zahl am Talent 0.8, 0.5, 1)
-- Zurück zu einem eigenen Ton: hier je Ton { code = "|cffrrggbb", r = …, g = …, b = … } eintragen (ns.Tone liest es).
ns.TONES = {
    good = { role = "good" },
    bad = { role = "bad" },
    gold = { role = "normal" },
    orange = { object = "ORANGE_FONT_COLOR", role = "warn" },
    hint = { grey = true, role = "gray" },
    detail = { role = "highlight" },
    locked = { role = "gray" },
    next = { object = "LIGHTBLUE_FONT_COLOR", role = "highlight" },
    invalid = { quality = 4, role = "bad" },
}

local function ToneObject(info)
    local obj = info.object and rawget(_G, info.object)
    if type(obj) == "table" and type(obj.GetRGB) == "function" then return obj end
    return nil
end

-- r, g, b eines Tons (für SetTextColor); unbekannter Ton: nil.
function ns.ToneRGB(tone)
    local info = type(tone) == "string" and ns.TONES[tone]
    if not info then return nil end
    if info.r then return info.r, info.g, info.b end
    if info.quality and type(Core.QualityRGB) == "function" then
        local r, g, b = Core.QualityRGB(info.quality)
        if type(r) == "number" then return r, g, b end
    end
    local obj = ToneObject(info)
    if obj then
        local ok, r, g, b = pcall(obj.GetRGB, obj)
        if ok and type(r) == "number" and type(g) == "number" and type(b) == "number" then return r, g, b end
    end
    local r, g, b = Core.Style.Color(info.role)
    return r, g, b
end

-- text im Ton (Farbcode davor, |r dahinter); unbekannter Ton oder kein Text: unverändert. Gesperrte Texte bleiben
-- unangetastet (Leitlinie 6).
function ns.Tone(tone, text)
    if Core.IsSecret(text) then return text end
    local info = type(tone) == "string" and ns.TONES[tone]
    if not info or text == nil then return text end
    text = tostring(text)
    if info.code then return info.code .. text .. "|r" end
    if info.grey then return Core.Grey(text) end
    if info.quality and type(Core.QualityHex) == "function" then return Core.QualityHex(info.quality) .. text .. "|r" end
    local obj = ToneObject(info)
    if obj and type(obj.WrapTextInColorCode) == "function" then
        local ok, wrapped = pcall(obj.WrapTextInColorCode, obj, text)
        if ok and type(wrapped) == "string" then return wrapped end
    end
    return Core.Style.ColorText(info.role, text)
end

-- Schalter für /eztalent <wort> (Gerüst: ns.TOGGLES); en: das englische Wort für den englischen Client (T10-1)
-- (Einstellungs-Prüfung 19.11.2026: vorlagen, vermaechtnis, tooltip und berechnet sind fest und haben kein Wort mehr)
ns.TOGGLES = {
    { "effectsTab", "auswirkungen", en = "effects" },
    { "nextPoint", "punkt", en = "point" },
}

Core.NewModule(ADDON, ns, {
    title = "ezTalent",
    -- 1.15.0: Bausteine aus dem Gesamtreview vom 18.11.2026, u. a. Core.CombatNotice, Core.CombatText, Core.SettingsPathText
    -- (Liste je Modul in docs/roadmap/uebergreifend.md, P7)
    core = "1.15.0",
    needs = { "scaffold", "scaffoldHelpers", "sideTabStack", "tourOwner", "AddCompanion", "DockRoom", "TipAnchor",
        "Style.Color", "Style.ColorText", "QualityHex", "QualityRGB",
        -- Einstellungs-Prüfung 19.11.2026: gespeicherte Werte einmal umstellen (Core.MigrateOnce)
        "MigrateOnce",
        -- Welle 17: Helfer und Texte, die ezCore ohne neue Versionsnummer bekam (tools/texte.lua, Regel 4)
        "More",
        -- Welle 23b: Rundgang mit opts.single und geprüftem tour:Next (Tour.lua)
        "TOUR_FEATURES.single", "TOUR_FEATURES.guardNext",
        -- Welle 23a: gemeinsamer Ablauf der Messungen (Measure.lua)
        "MeasureField", "Measure.Show",
        -- Welle 27 (modul/eztalent-menue): Symbole, Abschnitte und Quelle im Menü zur Wahl (ohne neue Nummer)
        -- (Menu.IconMarkup nicht: ezTalent ruft es nicht selbst auf, Menu.Icon nutzt es intern – Fund des code-reviewers)
        "Menu.Tip", "Menu.Icon", "Menu.Section",
        "Menu.ICON_ALL_OFF",
        -- Oberflächen-Einheit (Gesamtreview 18.11.2026, P13 D2): Addon-Fach und Befehl ohne Wort nach Entscheidung 5,
        -- Hilfe aus ezCore, Kampfsperre, Wege zu Einstellungen, „Nein“ der Rückfrage, Tooltip am gesperrten Knopf
        "compartmentMain", "slashMain", "confirmCancel", "CombatNotice", "SettingsPathText",
        "Toolbar.ShowTipWhileDisabled",
        -- Tooltip-Zeilen mit Rollen statt Farbzahlen (T9-6)
        "TipLine",
        -- Gesamtreview 18.11.2026 (D3, kern/einheit-rest; ohne neue Nummer): Texthelfer statt Kopien im Modul
        "CombatText", "Word", "CmdText" },
    db = "ezTalentDB",
    -- ui: was sich die Oberfläche merkt (offenes Seitenteil je Fenster); hints: gesehene Erklärblasen (Tour.lua);
    -- measure: Grundwerte je Klasse, Volk und Stufe aus „Werte für die Simulation messen“ (Measure.lua, ohne Namen)
    tables = { "templates", "chars", "ui", "hints", "measure" },
    onLoad = function(db) ns.MigrateSettings1911(db) end,
    login = true,
    -- Kurzbefehl /ezt aus Core.SLASH_ALIASES (eine Liste, T18-14); main: „/eztalent“ ohne Wort öffnet wie der Linksklick
    -- im Addon-Fach das Talentfenster (Entscheidung 5); reset: „zuruecksetzen“ fragt wie der Knopf (T18-20)
    slash = { commands = { "/eztalent" }, main = function() ns.OpenTalents() end, mainText = L.MAIN_TEXT, reset = true,
        extra = function(cmd)
        if cmd == "twinks" or cmd == "chars" or cmd == "roster" then
            ns.Roster.Show()
            return true
        end
        if cmd == "erheben" or cmd == "survey" then
            ns.Templates.ShowSurvey()
            return true
        end
        if cmd == "werte" or cmd == "values" or cmd == "measure" then     -- englisch „values“ wie ezCombats /ezk values
            ns.Measure.Show()
            return true
        end
        return false
    end },
})

-- Schnittstelle für andere Module (ezCore.API("ezTalent")); Inhalt setzen Templates.lua und Effects.lua.
ns.API = {}

---------------------------------------------------------------------------
-- Rücksicht auf fremde Addons (Punkt 10): Wer was übernimmt, weiß ezCore (Core.OTHER_ADDONS, docs/fremd-addons.md).
-- ezTalent fragt nur. Den Schlüssel „talentTemplates“ führt ezCore seit Welle 5 (Forever++ TalentPlanner, OneForAll –
-- Forever, Talented Forever; Eigentümer ezTalent in FirstStart.lua), „legacyPlanner“ nicht: Für Forever ist kein
-- Vermächtnis-Planer mit belegtem Ordnernamen bekannt. Läuft keines, zeigt ezTalent alles; der Status nennt, welche
-- Addons ezCore kennt (TL-20).
---------------------------------------------------------------------------

-- Weiterleitung auf ns.OtherFor aus dem Gerüst (Core.WhoHandles ist innen gesichert, die pcall-Hülle entfällt; W-14).
function ns.OtherHandles(feature)
    return (ns.OtherFor(feature))
end

-- Kennt ezCore die Funktion schon (ein Eintrag in Core.OTHER_ADDONS mit diesem Schlüssel)? Sonst nennt der Status
-- „für Forever ist keines bekannt“ (TL-20), statt still „kein fremdes Addon“ anzunehmen.
function ns.OtherKnown(feature)
    for _, entry in pairs(type(Core.OTHER_ADDONS) == "table" and Core.OTHER_ADDONS or {}) do
        if type(entry) == "table" and type(entry.features) == "table" and entry.features[feature] ~= nil then return true end
    end
    return false
end

-- Anzeigenamen der Addons, die ezCore für diese Funktion kennt (sortiert; leer, wenn keines eingetragen ist).
function ns.OtherLabels(feature)
    local labels = {}
    for key, entry in pairs(type(Core.OTHER_ADDONS) == "table" and Core.OTHER_ADDONS or {}) do
        if type(entry) == "table" and type(entry.features) == "table" and entry.features[feature] ~= nil then
            labels[#labels + 1] = type(entry.label) == "string" and entry.label or tostring(key)
        end
    end
    table.sort(labels)
    return labels
end

-- Hinweistext für einen Bereich, wenn ein anderes Addon ihn übernimmt, sonst nil.
function ns.OtherHint(feature)
    local who = ns.OtherHandles(feature)
    if who then return L.OTHER_HANDLES:format(who) end
    return nil
end

---------------------------------------------------------------------------
-- Ergänzende Addons (Einstellungen » Erweitert » „Ergänzende Addons“; Core.AddCompanion). Pflicht ist nur ezCore.
---------------------------------------------------------------------------

-- Tweaks Forever: lässt unverteilte Talentpunkte aufleuchten – das hat ezTalent nicht. Name, Ordner und Adresse kommen
-- aus ezCores Erkennung (Core.OTHER_ADDONS.TweaksForever, Feld url am Eintrag – MAP-20/V-138: ein Ort für den Link);
-- ezTalent nennt es nur als Ergänzung.
ns.COMPANIONS = {
    { key = "TweaksForever", role = "optional", why = L.COMPANION_WHY_TWEAKS },
}
for _, entry in ipairs(ns.COMPANIONS) do Core.AddCompanion(ADDON, entry) end

---------------------------------------------------------------------------
-- Ein Twink wird vergessen (/ez vergessen): was ezTalent über ihn weiß, auch.
---------------------------------------------------------------------------

Core.Listen("CHAR_FORGOTTEN", function(key)
    if ns.db and key and type(ns.db.chars) == "table" then ns.db.chars[key] = nil end
end, ADDON)

-- Untertabelle des eigenen Charakters: ezTalentDB.chars[<Charakter>][field] (Vorschau „plan“, Empfehlung „advice“).
-- create = true legt fehlende Tabellen an. → Tabelle oder nil
function ns.CharData(field, create)
    local key = ns.charKey or Core.charKey
    if not (ns.db and key and type(ns.db.chars) == "table") then return nil end
    local c = ns.db.chars[key]
    if type(c) ~= "table" then
        if not create then return nil end
        c = {}
        ns.db.chars[key] = c
    end
    if type(c[field]) ~= "table" then
        if not create then return nil end
        c[field] = {}
    end
    return c[field]
end

---------------------------------------------------------------------------
-- Status
---------------------------------------------------------------------------

local function OnOff(key) return ns.Enabled(key) and L.ON or L.OFF end

function ns.StatusLines()
    local lines = {}
    for _, key in ipairs({ "effectsTab", "rosterTab", "makeRoom", "nextPoint" }) do
        lines[#lines + 1] = L["OPT_" .. key] .. ": " .. OnOff(key)
    end
    lines[#lines + 1] = L.STATUS_TRAITS:format(ns.Traits.Available() and L.ON or L.STATUS_MISSING)
    local legacy = #ns.Traits.LegacyTrees()
    lines[#lines + 1] = L.STATUS_LEGACY:format(legacy)
    lines[#lines + 1] = L.STATUS_TEMPLATES:format(ns.Templates.Count())
    local with, total = ns.Templates.PresetIDCoverage()
    if total > 0 then lines[#lines + 1] = L.STATUS_IDS:format(with, total) end
    -- Berechnete Verteilungen (Welle 21): wie viele für die eigene Klasse, sonst worauf sie warten
    local computed = ns.COMPUTED and ns.COMPUTED[Core.PlayerClass() or ""]
    if type(computed) == "table" and #computed > 0 then
        local meta = type(ns.COMPUTED_META) == "table" and ns.COMPUTED_META or {}
        lines[#lines + 1] = L.STATUS_COMPUTED:format(#computed, tostring(meta.date or "?"))
        -- vorläufige (aus den Client-Tabellen, Grundwerte geschätzt – Welle 24, Paket modul/computed-ausliefern)
        local provisional = 0
        for _, p in ipairs(computed) do
            if type(p) == "table" and type(p.computed) == "table" and p.computed.provisional then provisional = provisional + 1 end
        end
        if provisional > 0 then lines[#lines + 1] = L.STATUS_COMPUTED_PROVISIONAL:format(provisional) end
    else
        lines[#lines + 1] = L.STATUS_COMPUTED_NONE
    end
    -- Zeile „verändert durch“ (TL-21): seit ezCore 1.12 angemeldet; der Warte-Text bleibt für ein älteres ezCore
    lines[#lines + 1] = ns.Effects.TooltipReady() and L.STATUS_TOOLTIP_READY or L.STATUS_TOOLTIP_WAITING
    -- Rücksicht auf fremde Planer (TL-20): läuft eines, sein Hinweis; sonst, welche ezCore kennt bzw. dass es keine gibt
    for _, feature in ipairs({ "talentTemplates", "legacyPlanner" }) do
        local area = L["STATUS_AREA_" .. feature]
        local hint = ns.OtherHint(feature)
        if hint then
            lines[#lines + 1] = hint
        elseif ns.OtherKnown(feature) then
            lines[#lines + 1] = L.STATUS_OTHER_NONE_RUNNING:format(area, table.concat(ns.OtherLabels(feature), ", "))
        else
            lines[#lines + 1] = L.STATUS_OTHER_UNKNOWN:format(area)
        end
    end
    -- Nächster Talentpunkt aus der Reihenfolge der Vorlage (TL-01)
    local nextName = ns.Plan.Next()
    if nextName then lines[#lines + 1] = L.STATUS_NEXT_POINT:format(nextName) end
    return lines
end

---------------------------------------------------------------------------
-- Talentfenster öffnen (Blizzards eigene Wege; ezCore kennt sie unter „talents“)
---------------------------------------------------------------------------

function ns.OpenTalents()
    if Core.TogglePanel and Core.Call(Core.TogglePanel, "talents") == true then return true end
    local util = rawget(_G, "PlayerSpellsUtil")
    if util and util.ToggleClassTalentFrame then return Core.Call(util.ToggleClassTalentFrame) ~= false end
    return false
end

-- Vermächtnis-Fenster: Blizzards eigener Umschalter (lädt Blizzard_LegacySystem bei Bedarf).
function ns.OpenLegacy()
    local toggle = rawget(_G, "ToggleLegacySystemUI")
    if type(toggle) ~= "function" then
        ns.Print(L.LEGACY_UNAVAILABLE)
        return false
    end
    Core.Call(toggle)
    return true
end

-- Weg zu einer Einstellung auf ezTalents Seite (Core.SettingsPathText, T18-18): Abschnitt und Option als Schlüssel.
function ns.PathText(section, option)
    return Core.SettingsPathText(ADDON, section, option, L)
end

-- Weg zu „Talente erheben“ (in PRESET_SURVEY_HINT, PRESET_SURVEY_SHORT und RESET_NO_unmatched), die lange Abhilfe
-- und die kurze für den Chat – der Weg kommt immer aus Core.SettingsPathText (T18-18)
function ns.SurveyPath() return ns.PathText("SETTINGS_ADVANCED", "OPT_SURVEY") end
function ns.SurveyHint() return L.PRESET_SURVEY_HINT:format(ns.SurveyPath()) end
function ns.SurveyShort() return L.PRESET_SURVEY_SHORT:format(ns.SurveyPath()) end

-- Kampfsperre in ezCores Wortlaut (T18-1): Text bzw. Meldung im Chat; what = L.*_COMBAT_WHAT
function ns.CombatText(what) return Core.CombatText(what or L.TALENTS_COMBAT_WHAT) end

---------------------------------------------------------------------------
-- Addon-Knopf an der Minikarte nach Entscheidung 5 vom 18.11.2026 (Gesamtreview T18-3, T16-10): Linksklick
-- Talentfenster, Rechtsklick Einstellungen; Tooltip und Befehlszeile von ezCore
---------------------------------------------------------------------------

local compartmentClick, compartmentEnter, compartmentLeave = Core.CompartmentHandlers({
    ns = ns, title = L.TITLE, main = function() ns.OpenTalents() end, mainText = L.MAIN_TEXT,
})

ezTalent_OnAddonCompartmentClick = compartmentClick
ezTalent_OnAddonCompartmentEnter = compartmentEnter
ezTalent_OnAddonCompartmentLeave = compartmentLeave
