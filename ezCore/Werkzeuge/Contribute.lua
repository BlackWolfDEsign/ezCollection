local ADDON, ns = ...
local Core = ezCore
local L = Core.L

--[[
    Beitragen: Spieler » Projekt (DB-N1; Entscheidung des Nutzers 14.11.2026 zu F6 „ja ok“, Nachtrag „folgendes
    sollte auch für spieler nach der veröffentlichung gelten, darauf hingewiesen werden“, Übermittlungsweg
    „GitHub-Issue“). Wer mag, schickt die Datei des Trägers ezWorld an das Projekt; das Projekt prüft die Beiträge,
    führt sie zusammen und liefert das Ergebnis mit aus. Der Weg Spieler » Spieler bleibt zu (Entscheidung 13.11.2026).
    Versandt wird nie von selbst: ezCollection kann keine Datei verschicken, es erklärt nur den Weg.

      Core.PROJECT_URL                   Projektseite (eine Stelle)
      Core.Contribute.ISSUE_URL          Adresse für ein neues GitHub-Issue im Projekt (eine Stelle)
      Core.Contribute.VALUES_URL         Adresse der Vorlage „Werte messen“ (werte.yml) für /ezt werte und /ezk werte;
                                           Core.Measure.Show nimmt sie ab Werk (T11-1)
      Core.Contribute.HelpText()         → Text „Mithelfen“: drei Schritte, Pfad der Datei, Inhalt, Weg (Issue mit
                                           Anhang als .zip oder .txt – GitHub nimmt .lua nicht an), Daten-Probe nur
                                           als Zusatz für Freiwillige
      Core.Contribute.ShowHelp()         zeigt ihn (Knopf „Mithelfen“, /ez mithelfen)
      Core.Contribute.Prepare()          Knopf „Beitrag vorbereiten“ (/ez beitrag): erklärt den Inhalt, nennt den
                                           Pfad und holt die Einwilligung (Rechteeinräumung nach Abschnitt 3 b der
                                           ezCollection License 1.0, Datei LICENSE); vermerkt sie im Kopf der Datei
                                           (ezWorldDB.meta.consent = { t, b, lic })
      Core.Contribute.Consent()          → Vermerk oder nil; ein Vermerk unter einer früheren Lizenz (lic ≠ LICENSE,
                                           etwa „GPL-3.0“ bis 15.11.2026) gilt nicht weiter – „Beitrag vorbereiten“
                                           fragt dann neu und überschreibt ihn. Heute gibt es nur „ezCollection
                                           License 1.0“, darum reicht der Vergleich lic == LICENSE. Bei einer
                                           neuen Lizenzfassung (etwa 1.1) gilt eine 1.0-Einwilligung weiter, weil
                                           Abschnitt 3 b auch spätere Lizenzen von ezCollection deckt: dann nur die
                                           GPL-Vermerke ausschließen, nicht auf Gleichheit prüfen – zusammen mit
                                           tools/merge.lua (M.Combine) und den Prüfungen in beitrag10_test.lua
      Core.Contribute.TryHint()          → true, wenn der einmalige Hinweis jetzt erschien
    Der Hinweis erscheint einmal: frühestens nach AFTER_SESSIONS Anmeldungen, nie im Kampf, nie in einer Instanz, über
    ezCores Meldeweg (Blizzards Rückfrage-Fenster) mit den Knöpfen „Mithelfen“ und „Nicht mehr zeigen“; abschaltbar
    über den gemeinsamen Schalter „Hinweise und Angebote zeigen“ (OPT_optInHints, Seite „ezCollection“ » Erweitert).
    Gemerkt in ezCoreDB.contribute = { sessions, shown, never }.
      Core.Contribute.ResetHint()        → true, wenn er schon kam oder abgelehnt war (Core.ResetAllTours)
    Die Daten-Probe (/ez probe auto) bleibt Entwicklerwerkzeug und wird hier nie eingeschaltet.
]]

local Contribute = {}
Core.Contribute = Contribute

Core.PROJECT_URL = "https://github.com/BlackWolfDEsign/ezCollection"
Contribute.ISSUE_URL = Core.PROJECT_URL .. "/issues/new?template=beitrag.yml"   -- Vorlage .github/ISSUE_TEMPLATE/beitrag.yml
-- Werte-Messungen (/ezt werte, /ezk werte) haben eine eigene Vorlage (Gesamtreview 18.11.2026, T11-1: bis dahin führte
-- ihr Link auf beitrag.yml)
Contribute.VALUES_URL = Core.PROJECT_URL .. "/issues/new?template=werte.yml"    -- Vorlage .github/ISSUE_TEMPLATE/werte.yml
Contribute.AFTER_SESSIONS = 5
Contribute.LICENSE = "ezCollection License 1.0"   -- Datei LICENSE; bis 15.11.2026 „GPL-3.0“
Contribute.CARRIER = Core.DB.CARRIERS.world   -- Datei des Trägers (Name nur im Datenbank-Teil, Lint-Regel 10)

local function Store()
    local db = Core.db
    if type(db) ~= "table" then return nil end
    if type(db.contribute) ~= "table" then db.contribute = {} end
    return db.contribute
end

-- Einstellungs-Prüfung 19.11.2026 (Nr. 54; Entscheidung des Nutzers „Ja, alle umsetzen“): kein eigenes Kästchen mehr
-- (OPT_contributeHint, Gruppe discovery) – der Hinweis folgt dem gemeinsamen Schalter „Hinweise und Angebote zeigen“
-- (Core.OptInHint.Enabled) und hat seinen Knopf „Nicht mehr zeigen“ (ezCoreDB.contribute.never). Ein gespeichertes
-- „aus“ wird einmal zu „nicht mehr zeigen“ (Merker ezCoreDB.migrated.contributeHint19). → true, wenn übernommen
function Contribute.MigrateHintSwitch(db)
    if type(db) ~= "table" then return false end
    if type(db.migrated) ~= "table" then db.migrated = {} end
    return Core.MigrateOnce(db.migrated, "contributeHint19", function()
        local disc = db.discovery
        if type(disc) ~= "table" or disc.contributeHint == nil then return false end
        local off = disc.contributeHint == false
        disc.contributeHint = nil
        if off then
            if type(db.contribute) ~= "table" then db.contribute = {} end
            db.contribute.never = true
        end
        return off
    end) == true
end
Core.Listen("CORE_LOADED", function() Contribute.MigrateHintSwitch(Core.db) end, "ezCore.Contribute")

-- Hinweis wieder erlauben (Knopf „Alle Hinweise und Erklärblasen erneut zeigen“, Core.ResetAllTours). → true, wenn er
-- schon kam oder abgelehnt war
function Contribute.ResetHint()
    local store = Store()
    if not store then return false end
    local was = store.shown ~= nil or store.never == true
    store.shown, store.never = nil, nil
    return was
end

-- Pfad der Datei des Trägers, ohne den Kontonamen (den sieht nur der Spieler auf seinem Rechner)
function Contribute.FilePath(addon)
    return L.CONTRIB_PATH:format(addon or Contribute.CARRIER)
end

function Contribute.HelpText()
    local lines = {
        L.CONTRIB_HELP_HEAD,
        "",
        L.CONTRIB_STEP1,
        L.CONTRIB_STEP2,
        L.CONTRIB_STEP3:format(Contribute.FilePath()),
        "  " .. Contribute.ISSUE_URL,
        "",
        L.CONTRIB_CONTENT,
        L.CONTRIB_NOT_CONTENT,
        L.CONTRIB_ATTACH,
        L.CONTRIB_LICENSE:format(Contribute.LICENSE),
        "",
        L.CONTRIB_PROBE:format(Contribute.FilePath("ezCore")),
    }
    local DB = Core.DB
    if DB and DB.Persistent and not DB.Persistent() then
        table.insert(lines, 2, L.CONTRIB_NOT_SAVED)
    end
    return table.concat(lines, "\n")
end

function Contribute.ShowHelp()
    if not Core.TextDialog then
        for line in Contribute.HelpText():gmatch("[^\n]+") do ns.Print(line) end
        return nil
    end
    return Core.TextDialog({ anchor = rawget(_G, "SettingsPanel"), title = L.CONTRIB_TITLE, text = Contribute.HelpText(),
        readOnly = true, maxLetters = 0, owner = ADDON })
end

function Contribute.Consent()
    local DB = Core.DB
    local meta = DB and DB.Meta and DB.Meta()
    local c = type(meta) == "table" and meta.consent
    -- nur eine Einwilligung unter der heutigen Lizenz zählt (frühere Vermerke bleiben stehen, bis neu gefragt wird)
    return type(c) == "table" and c.lic == Contribute.LICENSE and c or nil
end

-- Einwilligung im Kopf der Datei vermerken (nur mit gespeichertem Träger; ohne ihn gibt es keine Datei)
local function NoteConsent()
    local DB = Core.DB
    local meta = DB and DB.Persistent and DB.Persistent() and DB.Meta and DB.Meta()
    if type(meta) ~= "table" then return false end
    meta.consent = { t = time and time() or 0, b = DB.Keys and DB.Keys.Build() or 0, lic = Contribute.LICENSE }
    return true
end

function Contribute.Prepare()
    local DB = Core.DB
    if DB and DB.Persistent and not DB.Persistent() then
        ns.Print(L.CONTRIB_NOT_SAVED)
        return nil
    end
    local text = L.CONTRIB_ASK:format(Contribute.FilePath(), Contribute.LICENSE)
    return Core.Confirm(text, function()
        NoteConsent()
        ns.Print(L.CONTRIB_READY:format(Contribute.FilePath()))
        Contribute.ShowHelp()
    end, { accept = L.CONTRIB_AGREE })
end

---------------------------------------------------------------------------
-- Einmaliger Hinweis „Mithelfen“
---------------------------------------------------------------------------

local function HintEnabled()
    local store = Store()
    if store and store.never == true then return false end
    local hint = Core.OptInHint
    return not (hint and hint.Enabled) or hint.Enabled()
end

local function InInstance()
    local fn = rawget(_G, "IsInInstance")
    if type(fn) ~= "function" then return false end
    local ok, inside = pcall(fn)
    return ok and inside == true
end

StaticPopupDialogs.EZCORE_CONTRIBUTE = {
    text = "%s",
    button1 = L.CONTRIB_BUTTON_HELP,
    button2 = L.CONTRIB_BUTTON_NEVER,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    noCancelOnEscape = true,   -- Esc schließt nur; „Nicht mehr zeigen“ ist allein der zweite Knopf
    preferredIndex = 3,
    OnAccept = function() Core.Try(ADDON, "Contribute", Contribute.ShowHelp) end,
    OnCancel = function(_, _, reason)
        -- „Nicht mehr zeigen“: gemerkt (wieder erlaubt nur über „Alle Hinweise und Erklärblasen erneut zeigen“)
        if reason == "clicked" then
            local store = Store()
            if store then store.never = true end
        end
    end,
}

function Contribute.TryHint()
    local store = Store()
    if not store or store.shown or not HintEnabled() then return false end
    if (Core.Num(store.sessions) or 0) < Contribute.AFTER_SESSIONS then return false end
    if Core.InCombat() or InInstance() then return false end
    store.shown = time and time() or 0
    StaticPopup_Show("EZCORE_CONTRIBUTE", L.CONTRIB_HINT)
    return true
end

-- Gezählt werden echte Anmeldungen: PLAYER_LOGIN feuert auch nach /reload, PLAYER_ENTERING_WORLD meldet die
-- erste Anmeldung mit isInitialLogin = true (Fund der Gegenprüfung).
ns.On("PLAYER_ENTERING_WORLD", function(_, isInitialLogin)
    if isInitialLogin ~= true then return end
    local store = Store()
    if store then store.sessions = (Core.Num(store.sessions) or 0) + 1 end
end)
ns.On("PLAYER_LOGIN", function()
    C_Timer.After(20, function() Core.Try(ADDON, "Contribute", Contribute.TryHint) end)
end)
-- im Kampf oder in einer Instanz verschoben: beim nächsten Zonenwechsel bzw. nach dem Kampf noch einmal
ns.On("PLAYER_REGEN_ENABLED", function() Core.Try(ADDON, "Contribute", Contribute.TryHint) end)
ns.On("ZONE_CHANGED_NEW_AREA", function() Core.Try(ADDON, "Contribute", Contribute.TryHint) end)

---------------------------------------------------------------------------
-- Abschnitt „Datenbank“ (Erweitert): fester Eintrag „Mithelfen“, Knopf „Beitrag vorbereiten“, Schalter
---------------------------------------------------------------------------

function Contribute.AddSettings(page)
    if type(page) ~= "table" or type(page.Button) ~= "function" then return false end
    page:Button(L.CONTRIB_HELP_LABEL, L.CONTRIB_HELP_BUTTON, function() Contribute.ShowHelp() end, L.CONTRIB_HELP_TIP)
    page:Button(L.CONTRIB_PREPARE_LABEL, L.CONTRIB_PREPARE_BUTTON, function() Contribute.Prepare() end,
        L.CONTRIB_PREPARE_TIP:format(Contribute.FilePath()))
    return true
end
