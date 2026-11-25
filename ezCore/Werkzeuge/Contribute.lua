local ADDON, ns = ...
local Core = ezCore
local L = Core.L

--[[
    Beitragen: Spieler » Projekt (DB-N1; Entscheidung des Nutzers 14.11.2026 zu F6 „ja ok“, Nachtrag „folgendes
    sollte auch für spieler nach der veröffentlichung gelten, darauf hingewiesen werden“, Übermittlungsweg
    „GitHub-Issue“). Wer mag, schickt seine Datenbank als anonymen Text an das Projekt; das Projekt prüft die Beiträge,
    führt sie zusammen und liefert das Ergebnis mit aus. Der Weg Spieler » Spieler bleibt zu (Entscheidung 13.11.2026).
    Versandt wird nie von selbst: ezCollection zeigt nur den Text zum Kopieren.
    Anonym seit 24.11.2026 (Nutzer, wörtlich „Natürlich anonymer Export“): bis dahin hingen Helfer die Rohdatei des
    Trägers an, bereinigt wurde erst beim Projekt. Jetzt bereinigt das Spiel (Datenbank/DBAnon.lua, dieselben Regeln wie
    tools/merge.lua), bevor es etwas zu kopieren gibt.

      Core.PROJECT_URL                   Projektseite (eine Stelle)
      Core.Contribute.ISSUE_URL          Adresse für ein neues GitHub-Issue im Projekt (eine Stelle)
      Core.Contribute.VALUES_URL         Adresse der Vorlage „Werte messen“ (werte.yml) für /ezt werte und /ezk werte;
                                           Core.Measure.Show nimmt sie ab Werk (T11-1)
      Core.Contribute.HelpText()         → Text „Mithelfen“: drei Schritte, Inhalt, Zufallskennung, Weg (Text in ein
                                           Issue einfügen oder als beitrag.txt anhängen), was GitHub zeigt, Daten-Probe
                                           nur als Zusatz für Freiwillige
      Core.Contribute.ShowHelp()         zeigt ihn (Knopf „Mithelfen“, /ez mithelfen)
      Core.Contribute.Prepare()          Knopf „Beitrag vorbereiten“ (/ez beitrag): erklärt den Inhalt und holt die
                                           Einwilligung (Rechteeinräumung nach Abschnitt 3 b der ezCollection License
                                           1.0, Datei LICENSE); vermerkt sie im Kopf der Datenbank
                                           (ezWorldDB.meta.consent = { t, b, lic }) und zeigt danach den Text
      Core.Contribute.Export(onDone)     → Auftrag (Core.Sliced); onDone({ rows, text, plain, packed, id }) – gepackt
                                           über C_EncodingUtil (zlib, Base64; zurückgelesen und verglichen), sonst der
                                           reine Datentext. rows = 0: nichts zu schicken
      Core.Contribute.ShowExport(ergebnis)  zeigt den Text zum Kopieren; „Lesbar zeigen“ den Inhalt
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
Contribute.PASTE_MAX = 60000                  -- Zeichen: so viel fasst ein Issue als Text, darüber als beitrag.txt
Contribute.TEXT_MAX = 4 * 1024 * 1024         -- Zeichen im Kopierfeld
Contribute.VIEW_MAX = 100000                  -- Zeichen unter „Lesbar zeigen“

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

-- Zufallskennung der Datenbank (ezWorldDB.meta.id), nil ohne Datenbank
function Contribute.ID()
    local meta = Core.DB and Core.DB.Meta and Core.DB.Meta()
    local id = type(meta) == "table" and Core.Num(meta.id)
    return id and ("%d"):format(id) or nil
end

function Contribute.HelpText()
    local lines = {
        L.CONTRIB_HELP_HEAD,
        "",
        L.CONTRIB_STEP1,
        L.CONTRIB_STEP2,
        L.CONTRIB_STEP3,
        "  " .. Contribute.ISSUE_URL,
        "",
        L.CONTRIB_CONTENT,
        L.CONTRIB_NOT_CONTENT,
        L.CONTRIB_ID:format(Contribute.ID() or "?"),
        L.CONTRIB_ATTACH,
        L.CONTRIB_GITHUB,
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

-- Schema der Datenbank für Anon.Export (tools/merge.lua liest dasselbe aus den Dateien)
local function Schema()
    local DB = Core.DB
    local tables = {}
    for _, name in ipairs(DB.Tables()) do
        local spec = DB.Spec(name)
        tables[name] = { life = spec.life, explorer = spec.explorer == true, v = spec.v }
    end
    local objKinds, G = {}, Core.Gathering or {}
    for kind, pub in pairs(G.KIND_PUBLIC or {}) do objKinds[kind] = G.KNOWLEDGE and G.KNOWLEDGE[pub] end
    return { tables = tables, fields = DB.FIELDS, kinds = DB.Keys.KINDS, objKinds = objKinds,
        rareTiers = Core.Discovery and Core.Discovery.RARE or {} }
end

-- Gepackter Text (Base64 eines zlib-Stroms) oder nil, wenn der Client nicht packt oder der Rückweg nicht stimmt
local function Packed(plain, tick)
    local util, enum = rawget(_G, "C_EncodingUtil"), rawget(_G, "Enum")
    local method = type(enum) == "table" and type(enum.CompressionMethod) == "table" and enum.CompressionMethod.Zlib or nil
    if type(util) ~= "table" or method == nil then return nil end
    local bytes = Core.PlainCall(util.CompressString, plain, method)
    if type(bytes) ~= "string" or #bytes < 6 or bytes:byte(1) % 16 ~= 8 then return nil end
    tick(true)
    if Core.PlainCall(util.DecompressString, bytes, method) ~= plain then return nil end
    tick(true)
    local text = Core.PlainCall(util.EncodeBase64, bytes)
    if type(text) ~= "string" or text == "" or text:find("[^%w%+/=]") then return nil end
    return text
end

local job
function Contribute.Export(onDone)
    local DB = Core.DB
    local root = DB and DB.Root and DB.Root()
    if type(root) ~= "table" or not DB.Anon then return nil end
    if job then job.Cancel() end
    local Anon, schema = DB.Anon, Schema()
    job = Core.Sliced(function(tick)
        local data = Anon.Export(root, schema, tick)
        local rows = Anon.Rows(data)
        if rows == 0 then return { rows = 0 } end
        local plain = Anon.Text(data, tick)
        tick(true)
        local packed = Packed(plain, tick)
        local id = Contribute.ID() or "?"
        local text = Anon.Wrap(packed and "zlib" or "text", packed or plain,
            { id = id, build = DB.Keys.Build(), size = #plain })
        return { rows = rows, text = text, plain = plain, packed = packed ~= nil, id = id }
    end, { owner = ADDON, where = "Contribute", onDone = onDone, onError = function() ns.Print(L.CONTRIB_FAILED) end })
    return job
end

function Contribute.ShowExport(result)
    if type(result) ~= "table" or (result.rows or 0) == 0 then
        ns.Print(L.CONTRIB_EMPTY)
        return nil
    end
    local size = #result.text
    if size > Contribute.TEXT_MAX or not Core.TextDialog then
        ns.Print(L.CONTRIB_TOO_BIG)
        return nil
    end
    local function View(on)
        local frame = Core.TextDialogFrame and Core.TextDialogFrame()
        if not frame then return end
        local text = result.text
        if on then
            -- ein Satz je Zeile; gekürzt wird nur die Ansicht
            local plain, cut = result.plain, ""
            if #plain > Contribute.VIEW_MAX then
                cut = "\n\n" .. L.CONTRIB_VIEW_CUT:format(Contribute.VIEW_MAX, #plain)
                plain = plain:sub(1, Contribute.VIEW_MAX)
            end
            text = L.CONTRIB_VIEW_HEAD .. "\n\n" .. plain:gsub("},", "},\n") .. cut
        end
        frame:SetText(text)
    end
    local hint = size <= Contribute.PASTE_MAX and L.CONTRIB_EXPORT_HINT_PASTE or L.CONTRIB_EXPORT_HINT_FILE
    return Core.TextDialog({ anchor = rawget(_G, "SettingsPanel"), title = L.CONTRIB_EXPORT_TITLE,
        hint = hint:format(result.rows, size), text = result.text, readOnly = true, select = true, maxLetters = 0,
        owner = ADDON, accept = L.CONTRIB_EXPORT_NEXT, onAccept = function() Contribute.ShowHelp() end,
        option = { text = L.CONTRIB_VIEW, tip = L.CONTRIB_VIEW_TIP, checked = false, onChange = View } })
end

function Contribute.Prepare()
    local DB = Core.DB
    if DB and DB.Persistent and not DB.Persistent() then
        ns.Print(L.CONTRIB_NOT_SAVED)
        return nil
    end
    if Core.InCombat() then
        Core.CombatNotice(ns, L.CONTRIB_PREPARE_LABEL)
        return nil
    end
    return Core.Confirm(L.CONTRIB_ASK:format(Contribute.LICENSE), function()
        NoteConsent()
        ns.Print(L.CONTRIB_WORKING)
        Contribute.Export(function(result) Contribute.ShowExport(result) end)
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
        L.CONTRIB_PREPARE_TIP)
    return true
end
