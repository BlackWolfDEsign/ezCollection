local ADDON, ns = ...
local Core = ezCore
local L = Core.L

--[[
    Gerüst-Dienste (Vollprüfung 13.11.2026: V-005, V-006, V-011, V-016, V-181, V-182). Was jedes Modul sonst selbst
    schreibt oder gar nicht hat, steht einmal hier:
      Core.MESSAGES                      Verzeichnis der Nachrichten (Name → wer sendet, was kommt mit)
      Core.CompareVersions, Core.Require, Core.Has    „welches ezCore braucht das Modul“ mit klarer Meldung
      Core.Deprecated, Core.DeprecatedCalls           abgelöste Funktionen: Weiterleitung, Zähler, Zeile in /ez status
      Core.Migrate, Core.SCHEMA, Core.MIGRATIONS      Schema-Version und Migrationskette für SavedVariables
      Core.ModuleScaffold                Datenbank, Login, Befehle, Status, Kurzbefehl – über opts von Core.NewModule
    Ereignisse und Nachrichten an- und abmelden sowie Core.AfterCombat stehen in Core.lua.
]]

---------------------------------------------------------------------------
-- Verzeichnis der Nachrichten (V-016): EINE Liste. Ein Test prüft, dass ezCore keine Nachricht sendet oder hört,
-- die hier fehlt. Module melden eigene Nachrichten über Core.RegisterMessage an.
--   from = wer sendet (Datei in ezCore oder Modul), args = was mitkommt, text = wann
---------------------------------------------------------------------------

Core.MESSAGES = {
    CORE_LOADED = { from = "Core.lua", text = "ezCoreDB ist geladen (im ADDON_LOADED von ezCore). Module laden erst danach und können sie nicht hören – nur für Dateien in ezCore; Module nutzen ns.OnReady." },
    DEPRECATED_CALL = { from = "Framework.lua", args = "alt, neu, addon", text = "Ein Addon ruft zum ersten Mal eine abgelöste Funktion (Core.Deprecated); neu ist der Ersatz oder nil. Je Name und Addon einmal." },
    ERRORS_CHANGED = { from = "Core.lua", text = "Die Fehlerliste hat sich geändert (neuer Eintrag, Wiederholung höchstens einmal je Sekunde, geleert)." },
    CHARS_READY = { from = "Characters.lua", args = "me", text = "Beim Anmelden: Charakterdaten sind zusammengeführt, Core.me steht." },
    CHAR_FORGOTTEN = { from = "Characters.lua", args = "charKey", text = "Ein Twink wurde vergessen (Core.ForgetChar); Module streichen ihre Daten zu diesem Schlüssel." },
    CONTACTS_CHANGED = { from = "Contacts.lua", text = "Der Kontakt-Index (Freunde, Battle.net, Gilde) wurde neu gebaut – nur, wenn jemand zuhört, spätestens 0,5 s nach dem Ereignis." },
    INVENTORY_CHANGED = { from = "Inventory.lua", text = "Taschen, Bank, Post oder Angelegtes des gespielten Charakters wurden neu gezählt." },
    BANK_OPENED = { from = "Inventory.lua", text = "Die Bank ist offen." },
    BANK_CLOSED = { from = "Inventory.lua", text = "Die Bank ist zu." },
    GUILDBANK_CHANGED = { from = "Inventory.lua", text = "Ein Fach der Gildenbank wurde neu gelesen." },
    MAIL_SENT = { from = "Inventory.lua", args = "{ to, subject, money, cod, items }", text = "Ein Brief ging raus (für den Verlauf)." },
    MAILBOX_OPENED = { from = "Mail.lua", text = "Der Briefkasten ist offen. Noch ohne Zuhörer im Paket." },
    MAILBOX_CLOSED = { from = "Mail.lua", text = "Der Briefkasten ist zu." },
    MAILBOX_SCANNED = { from = "Mail.lua", args = "me.mailbox", text = "Der Posteingang wurde erfasst." },
    MAILBOX_FORGOTTEN = { from = "Mail.lua", args = "charKey", text = "Der gemerkte Briefkasten-Stand eines Twinks wurde gelöscht (Mail.ForgetMailbox)." },
    MAIL_WARN_DAYS_CHANGED = { from = "Mail.lua", args = "tage", text = "Der gemeinsame Grenzwert „Post läuft ab in …“ wurde geändert." },
    MAIL_QUEUE_CHANGED = { from = "MailQueue.lua", text = "Die Versand-Warteschlange hat sich geändert (neu, gesendet, gestoppt)." },
    MOVER_MOVED = { from = "Mover.lua", args = "key, pos", text = "Ein angemeldetes Teil wurde verschoben oder zurückgesetzt. Zuhörer: Core.Dock mit follow (Widgets.lua) prüft mitlaufende Seitenteile neu; Module nutzen onMove." },
    FRAME_MOVED = { from = "MoveFrames.lua", args = "name | nil, pos | nil", text = "Ein Blizzard-Fenster wurde am Griff verschoben oder an seine gemerkte Lage gesetzt (name, pos), oder Blizzard hat seine Fenster neu angeordnet (ohne name, auch bei ausgeschaltetem „Blizzard-Fenster verschieben“). Zuhörer: Core.Dock mit follow (Widgets.lua)." },
    MOVER_SHOWING = { from = "Mover.lua", args = "aktiv, owner", text = "Die Auswahl zum Verschieben erscheint oder verschwindet (Bearbeitungsmodus oder Knopf „Verschieben“)." },
    HISTORY_ADDED = { from = "History.lua", args = "art, eintrag", text = "Ein Eintrag kam in den Verlauf (loot, gold, mail, auction)." },
    HISTORY_REMOVED = { from = "History.lua", args = "art, eintrag", text = "Ein Eintrag wurde aus dem Verlauf genommen (z. B. abgelehnter Anhang)." },
    HISTORY_CLEARED = { from = "History.lua", args = "art | nil", text = "Der Verlauf einer Art oder (nil) der ganze Verlauf wurde geleert (History.Clear, History.ClearAll)." },
    SESSION_RESET = { from = "History.lua", args = "sitzung", text = "Die Sitzung (Core.Session) wurde zurückgesetzt; Module leeren ihre Anzeige der Sitzungszähler." },
    OTHER_ADDONS_CHANGED = { from = "OtherAddOns.lua", args = "addon, ereignis", text = "Ein fremdes Addon meldet später, was es übernimmt (heute Forever++ nach READY, MODULE_TOGGLED, OPTION_CHANGED, PROFILE_CHANGED). Wer bei PLAYER_LOGIN nach Core.WhoHandles entschieden hat, wendet neu an. Zuhörer: MoveFrames.lua." },
    PRICES_CHANGED = { from = "Prices.lua", args = "itemID | nil", text = "Preis-Wissen geändert: ein Gegenstand oder (nil) viele." },
    PRICES_SCAN_PROGRESS = { from = "Prices.lua", args = "gelesen, gesamt", text = "Fortschritt des Komplett-Scans im Auktionshaus." },
    PRICES_SCAN_DONE = { from = "Prices.lua", args = "anzahl, grund (nil | \"timeout\" | \"other\")", text = "Der Komplett-Scan ist fertig – oder nach Prices.SCAN_TIMEOUT ohne Liste beendet (\"timeout\"), oder ein anderes Addon hat ihn ausgelöst (\"other\")." },
    LOCKOUTS_CHANGED = { from = "Lockouts.lua", args = "charKey", text = "Die Instanz- und Raidsperren des gespielten Charakters haben sich geändert." },
    INSTANCES_CHANGED = { from = "Lockouts.lua", args = "anzahl", text = "Eine Instanz wurde betreten: „Instanzen der letzten Stunde“ ist gewachsen." },
    GEAR_CHANGED = { from = "CharData.lua", args = "charKey", text = "Gegenstandsstufe oder ein angelegter Platz des gespielten Charakters hat sich geändert." },
    CURRENCIES_CHANGED = { from = "CharData.lua", args = "charKey", text = "Eine Währung des gespielten Charakters hat sich geändert." },
    FACTION_CHANGED = { from = "CharData.lua", args = "factionID, differenz", text = "Der Ruf bei einer Fraktion hat sich geändert (die mit der größten Änderung)." },
    NPCS_CHANGED = { from = "Npcs.lua", args = "npcID | nil, art | nil", text = "Ein Lehrer oder Händler wurde gemerkt oder vergessen (NPC-Ortswissen)." },
    PROFESSIONS_CHANGED = { from = "Professions.lua", args = "berufe", text = "Die Berufe des gespielten Charakters wurden neu gelesen." },
    PROF_COOLDOWNS_CHANGED = { from = "Professions.lua", text = "Berufs-Abklingzeiten haben sich geändert." },
    RECIPES_CHANGED = { from = "Recipes.lua", args = "beruf", text = "Rezept-Wissen wurde aus einem offenen Berufefenster gelernt." },
    SPELLS_KNOWN_CHANGED = { from = "Spells.lua", text = "Das Zauberbuch wurde neu gelesen (neuer Zauber oder Rang)." },
    SPELLS_TRAINER_CHANGED = { from = "Spells.lua", args = "art", text = "Bei einem Lehrer wurde Neues gelernt (Liste je Klasse bzw. Tierausbilder)." },
    BOOKS_CHANGED = { from = "Collections.lua", text = "Bibliotheksbücher: abgegeben oder neu erkannt." },
    DUNGEONS_CHANGED = { from = "Dungeons.lua", text = "Die Dungeon-Tabelle kommt jetzt aus dem Client (Gruppensuche geladen)." },
    DURABILITY_CHANGED = { from = "Durability.lua", args = "summary", text = "Haltbarkeit der Ausrüstung hat sich geändert." },
    JUNK_SOLD = { from = "Junk.lua", args = "verkauft, kupfer, geschützt, owner", text = "Ein Plunder-Verkauf (Core.Junk.Sell) ist fertig oder beim Schließen des Händlers abgebrochen." },
    GLOW_MARKS_CHANGED = { from = "Glow.lua", args = "an", text = "Der Schalter „Zeichen am Leuchten“ (Farbenblind-Hilfe) wurde umgelegt; Marken der Module neu zeichnen (Core.MarkSign, Core.GlowMarkText)." },
    RESTRICTION_CHANGED = { from = "Util.lua", args = "art, aktiv, zustand", text = "Eine Addon-Sperre des Spiels beginnt oder endet (ADDON_RESTRICTION_STATE_CHANGED): art = \"combat\" | \"encounter\" | \"challenge\" | \"pvp\" | \"map\" | \"chat\", zustand = \"inactive\" | \"activating\" | \"active\". Zuhören über Core.OnRestrictionChanged." },
    -- Nachrichten der Module (senden über Core.Fire, damit andere Module zuhören können)
    GEAR_SCORES_CHANGED = { from = "ezGear", text = "Die Bewertung von Ausrüstung hat sich geändert (Gewichte, Profil)." },
    EZCRAFT_SHOPPING_CHANGED = { from = "ezCraft", text = "Die Einkaufsliste hat sich geändert." },
    EZQUEST_ITEMS_CHANGED = { from = "ezQuest", text = "Die Liste der Questgegenstände hat sich geändert." },
}

-- Eigene Nachricht eines Moduls ins Verzeichnis eintragen. → false, wenn der Name schon jemand anderem gehört.
function Core.RegisterMessage(name, from, text, args)
    if type(name) ~= "string" or name == "" then return false end
    local known = Core.MESSAGES[name]
    if known and known.from ~= from then return false end
    Core.MESSAGES[name] = { from = from, text = text, args = args }
    return true
end

-- Eintrag des Verzeichnisses oder nil (unbekannter Name).
function Core.MessageInfo(name)
    return Core.MESSAGES[name]
end

-- Alle Namen, sortiert (für /dump und Tests).
function Core.MessageNames()
    local list = {}
    for name in pairs(Core.MESSAGES) do list[#list + 1] = name end
    table.sort(list)
    return list
end

---------------------------------------------------------------------------
-- Versionen und Fähigkeiten (V-006, V-182)
---------------------------------------------------------------------------

-- "1.10.2" → { 1, 10, 2 }; nil, wenn kein Teil eine Zahl ist („?“).
function Core.ParseVersion(text)
    if type(text) == "number" then text = tostring(text) end
    if type(text) ~= "string" then return nil end
    local parts = {}
    for digits in text:gmatch("(%d+)") do parts[#parts + 1] = tonumber(digits) end
    return #parts > 0 and parts or nil
end

-- → -1 (a älter), 0 (gleich), 1 (a neuer); nil, wenn eine der beiden keine Version ist. „1.9“ gleich „1.9.0“.
function Core.CompareVersions(a, b)
    local pa, pb = Core.ParseVersion(a), Core.ParseVersion(b)
    if not (pa and pb) then return nil end
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x < y and -1 or 1 end
    end
    return 0
end

-- Fähigkeiten, die keine Funktion mit eigenem Namen sind. Alles andere findet Core.Has über den Namen.
Core.FEATURES = {
    scaffold = true,       -- Core.NewModule mit opts.db/login/slash (dieses Gerüst)
    unitEvents = true,     -- Einheiten-Filter in Core.RegisterEvent
    sideTabStack = true,   -- Core.CreateSideTab(parent, { order = … }) ordnet sich selbst
    tourOwner = true,      -- Core.NewTour({ owner = ns }) mit StartSoon
    scaffoldHelpers = true, -- Core.NewModule setzt ns.IsSecret/Num/Plain/InCombat/IsLoaded, ns.OtherFor, ns.NoteSecret,
                            -- ns.SecretLine, ns.StatusHeader (Welle 3)
    proxyDropdown = true,  -- page:ProxyDropdown(key, werte, get, set, opts)
    -- Oberflächen-Einheit (Gesamtreview 18.11.2026, P13 Teil D1): neue Angaben an bestehenden Helfern
    compartmentMain = true, -- Core.CompartmentHandlers({ ns, main, mainText, extraLines }): Linksklick Fenster, Rechtsklick
                            -- Einstellungen, Tooltip von ezCore (Entscheidung 5 vom 18.11.2026)
    confirmCancel = true,  -- Core.Confirm(…, { onCancel = fn(grund) }) und Core.CancelConfirm
    slashMain = true,      -- Core.NewModule(…, { slash = { main = fn, reset = true | fn } }) und L.CMD_HELP_OWN
    keyPlus = true,        -- Core.Keys.NormalizeKey: „+“ als letztes Zeichen ist die Plus-Taste (Gesamtreview 18.11.2026, D3)
    spellbookTipRoles = true, -- Zauberbuch-Ansicht (AddTipLines): Tooltip-Zeilen { text, rolle, umbrechen } mit einer
                              -- Rolle von Core.TipLine (Gesamtreview 18.11.2026, D3; älteres ezCore nahm die Rolle als
                              -- Rotwert für AddLine)
    -- Gemeinsame Texte: Core.L füllt sich erst beim Lesen, Core.Has fände sie nicht über den Namen (Welle 17)
    ["L.ALL_CHARS"] = true, -- „Alle Charaktere“ (Verläufe von ezAuction, ezBag, ezLoot, ezMail)
}

-- Kann dieses ezCore das? Name einer Fähigkeit (Core.FEATURES) oder einer Funktion bzw. Tabelle von ezCore,
-- auch mit Punkt: Core.Has("AfterCombat"), Core.Has("Glow.Set").
function Core.Has(feature)
    if type(feature) ~= "string" or feature == "" then return false end
    if Core.FEATURES[feature] ~= nil then return Core.FEATURES[feature] == true end
    local node = Core
    for part in feature:gmatch("[^%.]+") do
        if type(node) ~= "table" then return false end
        node = rawget(node, part)
    end
    return node ~= nil
end

local requirements = {}     -- Modul → { need, have, missing = { … }, ok, text }
local notices, loggedIn = {}, false

local function Notice(text)
    if loggedIn or (IsLoggedIn and IsLoggedIn()) then
        Core.Print(Core.TITLE, text)
    else
        notices[#notices + 1] = text   -- vor dem Einloggen geht Chat-Text leicht verloren: beim Login zeigen
    end
end

--[[
    Core.Require(modul, "1.9.0", needs) → true | false, Meldung
      Prüft die Version von ezCore (aus der TOC) und optional Fähigkeiten (Text oder Liste für Core.Has).
      Fehlt etwas, erscheint einmal je Modul „ezCore ist zu alt für ezX …“ im Chat und als Zeile in /ez status –
      statt eines nil-Fehlers irgendwo im Modul. Kennt der Client die Version nicht („?“), gilt sie als ausreichend.
      Über Core.NewModule: opts.core / opts.needs (dann läuft RunReady des Moduls nicht).
]]
function Core.Require(name, version, needs)
    name = tostring(name)
    local have = Core.Version(ADDON)
    local cmp = version ~= nil and Core.CompareVersions(have, version) or nil
    local tooOld = cmp ~= nil and cmp < 0
    local missing = {}
    if type(needs) == "string" then needs = { needs } end
    for _, need in ipairs(type(needs) == "table" and needs or {}) do
        if not Core.Has(need) then missing[#missing + 1] = tostring(need) end
    end
    local ok = not tooOld and #missing == 0
    local text
    if tooOld then
        text = L.REQUIRE_OLD:format(name, tostring(version), tostring(have))
    elseif #missing > 0 then
        text = L.REQUIRE_MISSING:format(name, table.concat(missing, ", "))
    end
    local before = requirements[name]
    requirements[name] = { need = version, have = have, missing = missing, ok = ok, text = text }
    if text and not (before and before.text == text) then Notice(text) end
    return ok, text
end

-- Ergebnis der letzten Prüfung eines Moduls ({ need, have, missing, ok, text }) oder nil; ohne Name: alle.
function Core.Requirement(name)
    if name == nil then return requirements end
    return requirements[name]
end

---------------------------------------------------------------------------
-- Abgelöste Funktionen (EC-30, VP-42; Stabilitätsregel in docs/ezcore.md, „Stabile Namen“)
---------------------------------------------------------------------------

--[[
    Core.Deprecated(alt, neu, fn) → Weiterleitung
      alt  Name der alten Schnittstelle ("Core.ActionHighlight.ShowSlots"), neu der Ersatz ("Core.Glow.Set") oder nil
      fn   die Funktion, die die Arbeit tut; die Weiterleitung ruft sie mit allen Argumenten und gibt alles zurück
    Jeder Aufruf zählt je Name und rufendem Addon (aus debugstack: Ordner unter Interface\AddOns, sonst „?“). Der
    erste Aufruf eines Addons meldet sich einmal über die Nachricht DEPRECATED_CALL(alt, neu, addon) – kein Chat,
    kein Fehler. /ez status nennt die gezählten Aufrufe in einer Zeile („Abgelöste Aufrufe: …“).
      Core.DeprecatedCalls() → { { old, new, n, owners = { { name, n } … } } … } nach Namen sortiert
      Core.DeprecatedStatusLine() → Zeile für /ez status oder nil (kein Aufruf)
    Ein falscher Aufruf (fn keine Funktion, alt kein Text) gibt fn unverändert zurück – nie ein Fehler beim Laden.
]]

local deprecated, deprecatedOrder = {}, {}

-- Ordnername des rufenden Addons: die erste Zeile des Aufrufstapels außerhalb dieser Datei (die Weiterleitung steht hier).
local function CallerAddon()
    local stack = rawget(_G, "debugstack")
    if type(stack) ~= "function" then return "?" end
    local ok, text = pcall(stack, 1, 8, 0)
    if not ok or type(text) ~= "string" then return "?" end
    for line in text:gmatch("[^\n]+") do
        if not line:find("Framework.lua", 1, true) then
            local name = line:match("AddOns[/\\]([^/\\]+)[/\\]")
            if name then return name end
        end
    end
    return "?"
end

function Core.Deprecated(old, new, fn)
    if type(fn) ~= "function" or type(old) ~= "string" or old == "" then return fn end
    local entry = deprecated[old]
    if not entry then
        entry = { old = old, new = type(new) == "string" and new or nil, n = 0, owners = {} }
        deprecated[old] = entry
        deprecatedOrder[#deprecatedOrder + 1] = old
    end
    return function(...)
        local owner = CallerAddon()
        entry.n = entry.n + 1
        local first = entry.owners[owner] == nil
        entry.owners[owner] = (entry.owners[owner] or 0) + 1
        if first and Core.Fire then pcall(Core.Fire, "DEPRECATED_CALL", entry.old, entry.new, owner) end
        return fn(...)
    end
end

function Core.DeprecatedCalls()
    local list = {}
    for _, old in ipairs(deprecatedOrder) do
        local e = deprecated[old]
        if e.n > 0 then
            local owners = {}
            for name, n in pairs(e.owners) do owners[#owners + 1] = { name = name, n = n } end
            table.sort(owners, function(a, b) return a.name < b.name end)
            list[#list + 1] = { old = e.old, new = e.new, n = e.n, owners = owners }
        end
    end
    table.sort(list, function(a, b) return a.old < b.old end)
    return list
end

function Core.DeprecatedStatusLine()
    local list = Core.DeprecatedCalls()
    if #list == 0 then return nil end
    local L = Core.L
    local parts = {}
    for _, e in ipairs(list) do
        local who = {}
        for _, o in ipairs(e.owners) do who[#who + 1] = o.name end
        local text = L.STATUS_DEPRECATED_ENTRY:format(e.old, e.n, table.concat(who, ", "))
        if e.new then text = text .. " " .. L.STATUS_DEPRECATED_NEW:format(e.new) end
        parts[#parts + 1] = text
    end
    return L.STATUS_DEPRECATED:format(table.concat(parts, "; "))
end

---------------------------------------------------------------------------
-- Schema-Version und Migrationskette für SavedVariables (V-005)
---------------------------------------------------------------------------

--[[
    Core.Migrate(db, version, schritte, opts) → Version danach, Anzahl gelaufener Schritte, Grund
      db[opts.field or "schema"] ist die Schema-Version der Tabelle (fehlt sie: 0 – ein alter oder neuer Speicher).
      schritte[n](db, n) hebt von n−1 auf n; gelaufen werden alle von der gespeicherten Version+1 bis version, der
      Reihe nach. Ein Schritt ohne Funktion zählt nur hoch. Schritte müssen auch mit einem leeren Speicher klarkommen.
      Fehler in einem Schritt: Die Kette hält an, die Version bleibt beim letzten gelungenen Schritt (beim nächsten
      Laden noch einmal), der Fehler steht in der Fehlerliste von opts.owner. Grund "error".
      Ist der Speicher neuer als version (älteres Addon nach einem Rückschritt): nichts anfassen, Grund "newer".
]]
function Core.Migrate(db, version, steps, opts)
    if type(db) ~= "table" then return nil, 0, "db" end
    opts = opts or {}
    local field = opts.field or "schema"
    version = math.floor(tonumber(version) or 0)
    local current = math.floor(tonumber(db[field]) or 0)
    if current > version then return current, 0, "newer" end
    local ran = 0
    for v = current + 1, version do
        local step = type(steps) == "table" and steps[v] or nil
        if type(step) == "function" then
            local ok, err = pcall(step, db, v)
            if not ok then
                Core.Error(opts.owner or ADDON, err, "Migrate " .. v)
                return v - 1, ran, "error"
            end
            ran = ran + 1
        end
        db[field] = v
    end
    return version, ran
end

-- ezCoreDB: Stand der Tabelle. Neue Schritte hinten anhängen und Core.SCHEMA erhöhen.
-- Nicht gemeint sind die einmaligen Übernahmen aus den Speichern der Module (ezBagDB.chars, ezSocialDB.alts …):
-- die laufen erst beim Anmelden, wenn die Module geladen sind, und merken sich in db.migrated (bleibt gültig).
Core.SCHEMA = 1
Core.MIGRATIONS = {
    -- 1: Stand vor der Schema-Version. Nur aufräumen: ein Feld, das eine Tabelle sein muss und keine ist
    --    (beschädigte Datei), wird geleert und danach neu angelegt. Tabellen bleiben unberührt.
    [1] = function(db)
        for _, key in ipairs({ "settings", "chars", "guilds", "knowledge", "migrated", "bnAlts", "errors",
            "positions", "comfort", "tooltip" }) do
            if db[key] ~= nil and type(db[key]) ~= "table" then db[key] = nil end
        end
    end,
}

---------------------------------------------------------------------------
-- Modul-Gerüst (V-011, V-181): freiwillige Angaben in Core.NewModule(name, ns, opts)
---------------------------------------------------------------------------

-- Befehle, die jedes Modul gleich versteht (opts.slash).
Core.STANDARD_COMMANDS = {
    options = { "", "optionen", "options", "einstellungen", "config" },
    status = { "status" },
    help = { "hilfe", "help" },
}
local commandKind = {}
for kind, words in pairs(Core.STANDARD_COMMANDS) do
    for _, word in ipairs(words) do commandKind[word] = kind end
end

-- "options" | "status" | "help" | nil für ein Befehlswort (über Core.SlashWord: groß, klein, Umlaute – T18-16).
-- „zuruecksetzen“ zählt hier nicht: es ist nur für Module mit opts.slash.reset ein Standardbefehl (Core.IsResetCommand).
function Core.StandardCommand(cmd)
    return commandKind[Core.SlashWord(cmd)]
end

local aliases = {}   -- Modul → gesetzter Kurzbefehl

-- Kurzbefehle, die über das Gerüst gesetzt wurden: { [Modul] = "/ezq" } (für /ez status).
function Core.SlashAliases()
    return aliases
end

local function EnsureTable(db, key, defaults)
    if type(db[key]) ~= "table" then db[key] = {} end
    if type(defaults) == "table" then Core.FillDefaults(db[key], defaults) end
    return db[key]
end

--[[
    opts (alle freiwillig; ohne sie tut das Gerüst nichts außer den Status- und Rundgang-Helfern):
      db = "ezQuestDB"       SavedVariables-Tabelle beim ADDON_LOADED des Moduls anlegen; setzt ns.db und ns.S
      defaults = { … }       Standardwerte für db.settings (Standard: ns.DEFAULTS zum Ladezeitpunkt)
      strict = false         Werte falschen Typs NICHT ersetzen (Standard: ersetzen, wie FillDefaults(…, true))
      tables = { "hints", tour = {}, stats = { n = 0 } }   weitere Tabellen in db (Name oder Name = Standardwerte)
      schema = 2, migrations = { [2] = fn(db) }            Core.Migrate vor dem Auffüllen der Standardwerte
      onLoad = fn(db)        danach (Fehler landen in der Fehlerliste)
      login = true           beim PLAYER_LOGIN ns.charKey/ns.realm/ns.me setzen und ns.RunReady() rufen
      slash = true | { key = "EZQUEST", commands = { "/ezquest" }, alias = "/ezq" | { "/ezq", "/eq" },
                       extra = fn(cmd, rest, input) → true, wenn erledigt, help = { Zeilen } | fn,
                       main = fn(), mainText = Text, reset = true | fn() }
                             Befehle „optionen“, „status“, „hilfe“ und die Schalter aus ns.TOGGLES; der Kurzbefehl
                             kommt beim Einloggen über Core.AddSlashAlias (nur, wenn er frei ist) → ns.slashAlias;
                             ohne alias gilt Core.SLASH_ALIASES[Modul] (Slash.lua, eine Liste für alle Module).
                             Seit dem Gesamtreview vom 18.11.2026 (P13, Entscheidung 5): main = was der Befehl ohne Wort
                             tut (dasselbe wie der Linksklick im Addon-Fach; ohne main: Einstellungen), mainText sagt es in
                             der Hilfe („/x – <mainText>“, darunter „/x einstellungen“); reset = „zuruecksetzen“
                             und „reset“ setzen die Einstellungen nach Rückfrage zurück (Core.SlashReset: wie der Knopf
                             page:ResetButton samt dessen ask und onReset; fn: eigenes Zurücksetzen). Ein Kandidat aus
                             SLASH_ALIASES, den commands schon fest setzt, entfällt. Hilfe: help, sonst Core.HelpLines mit L.CMD_HELP_OWN (nur die eigenen Wörter,
                             %s = geltender Befehl), sonst wie bisher das eigene L.CMD_HELP, sonst ezCores Standardhilfe.
                             Dazu ns.slashCommand (erster Befehl), ns.slashReset, ns.slashMain und ns.SlashCmd(rest) (Core.SlashCmd).
      statusHead = Text | fn Kopfzeile von ns.PrintStatus (Standard: ns.StatusHeader(); ein eigener Text
                             L.STATUS_HEAD gilt seit Welle 17 nicht mehr – Frage 8, ezCores Standard für alle)
    Immer (wenn das Modul sie nicht selbst setzt): ns.AddStatusLine(text | fn → Text | Liste), ns.StatusLines(),
    ns.PrintStatus(), ns.TourStore(feld) → db[feld or "tour"], dazu
      ns.StatusHeader()   → „Version x – Status:“ (ns.Print setzt den Modulnamen davor: „ezBuff: Version 1.2.0 –
                            Status:“) – EINE Kopfzeile für alle Module statt je einem eigenen STATUS_HEAD
      ns.SecretLine()     → „Zuletzt gesperrte Daten: Auren (vor 5 Sek.)“ aus ns.NoteSecret (Core.NewModule), nil,
                            solange nichts gesperrt war. Die Art heißt ns.L["SECRET_<art>"], sonst ihr Schlüssel.
                            ns.StatusLines() hängt die Zeile von selbst an.
]]
function Core.ModuleScaffold(mod, mns, opts)
    opts = opts or {}
    local name = mod.name

    -- Status: Zeilen sammeln und ausgeben
    local statusLines = {}
    mod.statusLines = statusLines
    if mns.StatusHeader == nil then
        mns.StatusHeader = function()
            return L.MODULE_STATUS_HEAD:format(Core.Version(name))
        end
    end
    if mns.SecretLine == nil then
        mns.SecretLine = function()
            local seen, now = {}, Core.Uptime()
            for what, when in pairs(type(mns.secretSeen) == "table" and mns.secretSeen or {}) do
                local key = "SECRET_" .. tostring(what)
                local label = mns.L and mns.L[key]
                if type(label) ~= "string" or label == key then label = tostring(what) end
                local age = math.max(0, now - (Core.Num(when) or now))
                seen[#seen + 1] = ("%s (%s)"):format(label, L.AGO:format(Core.Duration(age, true)))
            end
            if #seen == 0 then return nil end
            table.sort(seen)
            return L.STATUS_SECRET:format(table.concat(seen, ", "))
        end
    end
    if mns.AddStatusLine == nil then
        mns.AddStatusLine = function(line)
            if line ~= nil then statusLines[#statusLines + 1] = line end
        end
    end
    if mns.StatusLines == nil then
        mns.StatusLines = function()
            local lines = {}
            for i = 1, #statusLines do
                local line = statusLines[i]
                if type(line) == "function" then
                    local ok, result = pcall(line)
                    if ok then line = result else Core.Error(name, result, "Status") line = nil end
                end
                if type(line) == "table" then
                    for _, text in ipairs(line) do lines[#lines + 1] = tostring(text) end
                elseif line ~= nil and line ~= false then
                    lines[#lines + 1] = tostring(line)
                end
            end
            local okSecret, secret = pcall(mns.SecretLine)
            if okSecret and type(secret) == "string" then lines[#lines + 1] = secret end
            return lines
        end
    end
    if mns.PrintStatus == nil then
        mns.PrintStatus = function()
            local head = opts.statusHead
            if type(head) == "function" then
                local ok, result = pcall(head)
                head = ok and result or nil
            end
            mns.Print(head or mns.StatusHeader())
            local ok, lines = pcall(mns.StatusLines)
            if not ok then
                Core.Error(name, lines, "Status")
                lines = {}
            end
            for _, line in ipairs(type(lines) == "table" and lines or {}) do mns.Print(line) end
            local req = requirements[name]
            if req and req.text then mns.Print(req.text) end
        end
    end

    -- Speicher für Rundgänge (Core.NewTour({ owner = ns }))
    if mns.TourStore == nil then
        mns.TourStore = function(field)
            local db = mns.db
            if type(db) ~= "table" then return nil end
            return EnsureTable(db, field or "tour")
        end
    end

    -- Datenbank
    if type(opts.db) == "string" and opts.db ~= "" then
        local function Load(_, loaded)
            if loaded ~= name then return end
            Core.UnregisterEvent(name, "ADDON_LOADED", Load)
            local db = rawget(_G, opts.db)
            if type(db) ~= "table" then
                db = {}
                _G[opts.db] = db
            end
            if type(db.settings) ~= "table" then db.settings = {} end
            if opts.schema then Core.Migrate(db, opts.schema, opts.migrations, { owner = name }) end
            local defaults = opts.defaults or mns.DEFAULTS
            if type(defaults) == "table" then Core.FillDefaults(db.settings, defaults, opts.strict ~= false) end
            for key, value in pairs(type(opts.tables) == "table" and opts.tables or {}) do
                if type(key) == "number" then EnsureTable(db, value) else EnsureTable(db, key, value) end
            end
            mns.db, mns.S = db, db.settings
            -- gesperrtes Modul (ezCore zu alt): kein onLoad (T4-3) – es liefe gegen fehlende Helfer
            if type(opts.onLoad) == "function" and not mod.blocked then mns.Try("onLoad", opts.onLoad, db) end
        end
        Core.RegisterEvent(name, "ADDON_LOADED", Load)
    end

    -- Login
    if opts.login then
        Core.RegisterEvent(name, "PLAYER_LOGIN", function()
            mns.charKey, mns.realm, mns.me = Core.charKey, Core.realm, Core.me
            mns.RunReady()
        end)
    end

    -- Befehle
    local slash = opts.slash
    if slash == true then slash = {} end
    if type(slash) == "table" then
        local key = slash.key or name:upper()
        local commands = slash.commands or { "/" .. name:lower() }
        if type(commands) == "string" then commands = { commands } end
        mns.slashCommand = commands[1]
        mns.slashReset = slash.reset ~= nil and slash.reset ~= false or nil
        -- für die Hilfe (Core.HelpLines): Text der Hauptfunktion bzw. true
        mns.slashMain = type(slash.main) == "function" and (type(slash.mainText) == "string" and slash.mainText or true) or nil
        if mns.SlashCmd == nil then mns.SlashCmd = function(rest) return Core.SlashCmd(mns, rest) end end
        if mns.CmdText == nil then mns.CmdText = function(text) return Core.CmdText(mns, text) end end

        local function Help()
            local lines = slash.help
            if type(lines) == "function" then return mns.Try("Slash", lines) end
            if type(lines) ~= "table" and mns.L and type(mns.L.CMD_HELP_OWN) == "table" then
                lines = Core.HelpLines(mns, mns.L.CMD_HELP_OWN)
            end
            if type(lines) ~= "table" and mns.L and type(mns.L.CMD_HELP) == "table" and mns.L.CMD_HELP ~= L.CMD_HELP then
                lines = mns.L.CMD_HELP
            end
            if type(lines) ~= "table" then lines = Core.HelpLines(mns, {}) end
            for _, line in ipairs(lines) do mns.Print(line) end
        end

        local function Run(input)
            local cmd, rest = Core.ParseSlash(input)
            if type(slash.extra) == "function" and slash.extra(cmd, rest, input) then return end
            local kind = commandKind[Core.SlashWord(cmd)]
            if mns.slashReset and Core.IsResetCommand(cmd) then
                Core.SlashReset(mns, type(slash.reset) == "function" and slash.reset or nil)
            elseif kind == "options" and cmd == "" and type(slash.main) == "function" then
                slash.main()
            elseif kind == "options" then
                -- im Kampf vorgemerkt (ST-04): dann kein Hilfetext, der Hinweis kam schon
                if not Core.OpenedOrDeferred(function() return mns.OpenSettings and mns.OpenSettings() end) then Help() end
            elseif kind == "status" then
                mns.PrintStatus()
            elseif kind == "help" then
                Help()
            elseif not (mns.TOGGLES and mns.S and Core.HandleToggle(mns, cmd)) then
                Help()
            end
        end
        -- gesperrtes Modul (ezCore zu alt): der Befehl nennt nur den Grund (T4-3), statt gegen fehlende Helfer zu laufen
        local function Handle(input)
            if mod.blocked then
                local req = Core.Requirement and Core.Requirement(name)
                mns.Print(type(req) == "table" and req.text or L.REQUIRE_MISSING:format(name, "?"))
                return
            end
            mns.Try("Slash", Run, input)
        end

        if mns.HandleSlash == nil then mns.HandleSlash = Handle end
        mns.PrintHelp = mns.PrintHelp or Help
        for i, command in ipairs(commands) do _G["SLASH_" .. key .. i] = command end
        SlashCmdList[key] = Handle

        local candidates = slash.alias
        if candidates == nil then candidates = Core.SLASH_ALIASES and Core.SLASH_ALIASES[name] end
        if type(candidates) == "string" then candidates = { candidates } end
        if type(candidates) == "table" then
            -- Ein Kurzbefehl, den das Modul schon fest setzt, ist kein zweites Mal Kandidat (Gegenprüfung D1: ezMail trägt
            -- /ezm noch fest – sonst hinge Core.SlashCmd davon ab, ob Blizzard die Befehlsliste schon eingelesen hat)
            local fixed, left = {}, {}
            for _, command in ipairs(commands) do fixed[tostring(command):lower()] = true end
            for _, command in ipairs(candidates) do
                if type(command) == "string" and not fixed[command:lower()] then left[#left + 1] = command end
            end
            candidates = left
        end
        if type(candidates) == "table" and #candidates > 0 then
            local function SetAlias()
                local alias = Core.AddSlashAlias(key, #commands + 1, candidates, Handle)
                mns.slashAlias = alias
                aliases[name] = alias
            end
            if IsLoggedIn and IsLoggedIn() then
                SetAlias()
            else
                -- Erst, wenn alle Addons geladen sind: dann steht fest, welche Befehle belegt sind.
                Core.RegisterEvent(name, "PLAYER_LOGIN", function() C_Timer.After(0, SetAlias) end)
            end
        end
    end
end

ns.On("PLAYER_LOGIN", function()
    loggedIn = true
    for _, text in ipairs(notices) do Core.Print(Core.TITLE, text) end
    wipe(notices)
end)
