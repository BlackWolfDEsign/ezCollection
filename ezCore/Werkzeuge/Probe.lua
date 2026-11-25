local ADDON, ns = ...
local Core = ezCore
local L = Core.L

--[[
    Daten-Probe – /ez probe (Core.Probe). Bauauftrag: docs/datenprobe.md, Fragen: docs/datenkatalog-client.md
    („Offene Fragen an den Client“). Hält fest, was der laufende Client auf eine Abfrage WIRKLICH antwortet, damit
    der Entwurf der Entdecker-Datenbank nicht auf Annahmen steht. Drittes Werkzeug der Diagnose neben /ez debug und
    /ez test (Diagnose.lua); die Stationen und ihre Abfragen stehen in ProbeStations.lua.

    Regeln (Leitlinien 5 und 6):
      nur lesen        keine geschützten Aufrufe, nichts in Blizzards Tabellen, eigener Rahmen für Ereignisse
      jede Abfrage     einzeln in pcall, mit allen Rückgaben; fehlt die Funktion, heißt das Ergebnis „fehlt“
      geheime Werte    zuerst Core.IsSecret (Tabellen: issecrettable/canaccesstable) – festgehalten wird nur
                       { k = "secret" }, nie der Wert, nie sein Typ; nie verglichen, gerechnet, weitergereicht
      privat           Namen von Charakteren, Gilde, Freunden, Konto und Realm stehen nie im Klartext in der Ablage
                       (Probe.Private, Probe.MaskText); Chat-, Brief-, Notiz- und Makrotexte nur als Länge. Die Regel
                       hängt an der Abfrage (run:With, FIELD_RULE) – nicht daran, ob ein Name schon angemeldet ist;
                       wo beides stehen kann (Tooltip unter der Maus, Ziel eines Zaubers, Name neben einer GUID),
                       bleibt Text nur, wenn er nachweislich einem NPC oder Objekt gehört. Vom Realm bleibt die Nummer.
      im Kampf         nur die Kampf-Station und das Beutefenster; alles andere wartet (Core.AfterCombat); ein Lauf
                       im Kampf bleibt im Arbeitsspeicher und kommt nach dem Kampf in die Ablage
      in Portionen     alles, was die Probe selbst rechnet (Läufe, Mitschrift der Dokumentation, Tempo), teilt sich EIN
                       Budget je Bild (Probe.Takt: Probe.SLICE_MS Millisekunden, Probe.SLICE_CALLS Abfragen – eine
                       festgehaltene zählt Probe.ENTRY_COST-fach). Ein Schritt pausiert zwischen zwei Abfragen
                       (Koroutine) und macht im nächsten Bild weiter; nie rechnen zwei Aufträge je ihr eigenes Budget
                       im selben Bild. Deshalb: run:Q, run:Note, run:Call … nie innerhalb von pcall aufrufen
      Mitschnitt       je Ereignis nur wenige Beispiele (höchstens eines je Probe.SAMPLE_GAP Sekunden); sind sie voll und
                       löst das Ereignis keine Abfrage mehr aus, wird es nur noch gezählt (ein Zähler, sonst nichts) –
                       die Zahl bleibt genau. Abgemeldet wird ein solches Ereignis erst, wenn die Automatik alle Arten
                       der Stationen erfasst hat (Record.Narrow; Ablage: muted – die Zahl ist ab da eine Untergrenze)

    Ablage ezCoreDB.probe (kommt nicht in die Sicherung der Einstellungen – Backup.lua nimmt nur Einstellungen):
      { v = 1, meta = { version, build, date, iface, project, locale, realm, started },
        runs = { { st = "B", t = Serverzeit, b = Build, loc = Sprache, proj = Projekt-ID, s = Sitzung, ev = Auslöser,
                   ctx = { map, inst, itype, combat, restr = { … }, group, class, level, side, win },
                   kind = "F:npc" (Zielart, nur Station Ziel), auto = true (von der Automatik gestartet),
                   calls = { { id = "B2", fn = "C_MerchantFrame.GetItemInfo", arg = "1", ok = true, n = 1,
                               r = { Beschreibung je Rückgabe } }, { id, fn, ok = false, err = "fehlt" } … } } … },
        events = { { t, gt, e = "LOOT_READY", n = 1, a = { Beschreibung je Wert }, b, loc, proj, s } … },
        counts = { EREIGNIS = Anzahl }, muted = { EREIGNIS = true } (abgemeldet, seit die Automatik fertig ist: die Zahl
        ist ab da eine Untergrenze),
        tempo = { Messungen }, doc = { Dokumentation des Clients },
        done = { Station = Läufe }, kinds = { ["F:npc"] = Läufe je Zielart, ["ev:EREIGNIS"] = Abfragen der Automatik },
        auto = { on, quiet, noTempo, fullSaid, complete } (Zustand der Automatik), sessions = Zahl der Sitzungen (Pseudonyme gelten je Sitzung: <Spieler:3> aus s = 1
        ist ein anderer als aus s = 2), entries = Zahl der Einträge, bytes = Größe in der Datei (Probe.SizeOf),
        install = Zufalls-Kennung dieser Ablage (kein Name, kein Realm, kein Konto; bleibt beim Leeren über den Knopf),
        rev = Fassung der Probe (Probe.REV), chars = { [Schlüssel] = Nummer des Charakters } (16 Bit eines Prüfwerts aus
        install und der eigenen GUID, Probe.CharKey – die GUID steht nie da und lässt sich nicht zurückrechnen), per = { ["Art|Bereich|Charakter"] = Läufe },
        tot = { ["Art|Bereich"] = Läufe über alle Charaktere } (Grenzen der Automatik je Charakter und Lage),
        hint = { recipe, salvage } (Rezept-Nummern für die Proben ohne offenes Fenster) }
      Lauf zusätzlich: ch = Nummer des Charakters, lg = Lage ("w" Freiland, "i" Instanz, dazu "g" Gruppe, "b" Boss),
        pv = Probe.REV, ins = install, also = { weitere Arten, für die der Lauf zählt }, k = Schlüssel der Station
        ("W", "G10" … – st ist nur der Kennbuchstabe), dup = Abfragen mit gleicher Antwort (nicht abgelegt),
        dk = { [Probe] = davon je Probe }, spare = true (lief bei voller Ablage, weil die Art hier neu war)
      Abfrage zusätzlich: h = Prüfwert der Antwort. Eine gleiche Antwort später bekommt keinen Eintrag: probe.same[h] =
        { n = weitere Male, t = zuletzt gesehen } (Fassung 2026-11-14-nachprobe: ein Verweis { id, fn, arg, tag, ok, n,
        same = h } je Abfrage – bleibt lesbar)
      Ablage zusätzlich: same = { [Prüfwert] = { n, t } }, full = { t, s } (wann der Deckel erreicht war)
      Ereignis zusätzlich: lg = Lage (die Beispiele des Mitschnitts gelten je Lage)
    Beschreibung: { k = "nil" } | { k = "boolean" | "number", v } | { k = "string", len, v, leer, cut } |
      { k = "table", n = Schlüssel, len = Listenlänge, l = { die ersten Elemente }, f = { Feld = Beschreibung },
        nk = Zahlenschlüssel, m = { [Zahl] = Beschreibung }, fn = Funktionen, more = weggelassene Felder } |
      { k = "secret" } | { k = "function" | "userdata" | "frame" … }

      Probe.Describe(wert, opts)        → Beschreibung       opts: fields = { feld = "player" | "unit" | true }, text, maxFields
      Probe.Private(name, art)          → Pseudonym („<Spieler:3>“; art: player, guild, rank, friend, account, realm)
      Probe.MaskText(text)              → Text ohne bekannte Namen (als ganzes Wort), Spieler-GUIDs, Spieler-Links, BattleTags
      Probe.Run(station, opts)          → true | false, Grund ("unknown" | "combat" | "full")
      Probe.Full(), Probe.Hard()        Deckel erreicht (nur noch zählen und Neues) | auch die Reserve (nur noch zählen)
      Probe.SayFull(auto)               „voll“ melden – höchstens einmal je Sitzung
      Probe.Here()                      → Stationen, die gerade passen (Probe.Detect), der Reihe nach
      Probe.Auto.Enable/Disable/Toggle/Enabled()    Automatik: Stationen starten von selbst, jede Art nur wenige Male
      Probe.Record.Start/Stop/Toggle/Running()      Mitschnitt der Ereignisse (samt Abfragen bei Beute, Quest …)
      Probe.Record.Quiet(e), Muted(e)               nur noch gezählt? abgemeldet?
      Probe.Record.Narrow(), Narrowed(), Rearm()    nur noch Ereignisse, an denen etwas fehlt (Automatik fertig); alle wieder
      Probe.Record.Unseen()                         Ereignisse, die noch nie eingetreten sind
      Probe.Record.Forget()                         Arbeitsspeicher des Mitschnitts verwerfen (Leeren der Probe)
      Probe.Takt.Want(auftrag), Waiting(), Left()   das eine Budget je Bild (auftrag:Slice() rechnet eine Portion)
      Probe.Tempo.Start/Stop/Running()  Stichprobe Gegenstände und Zauber: sofort / nachgeladen / ohne Antwort
      Probe.Doc.Start/Running()         Blizzard_APIDocumentation des laufenden Clients mitschreiben
      Probe.Status(), StatusText()      Zahlen der Ablage       Probe.Lines(), Probe.Show()   Bericht zum Kopieren
      Probe.Clear(opts), Probe.AskClear()   Ablage leeren (AskClear behält Automatik und Kennung)          Probe.Command(rest)           /ez probe …
      Probe.AddSettings(page)           Knöpfe unter „Erweitert“ (Collection.lua)
]]

local Probe = {}
Core.Probe = Probe
Probe.VERSION = 1
-- Fassung der Probe: steht an jedem Lauf (pv) und in der Ablage (rev), damit der Bericht mehrerer Helfer weiß, welche
-- Stationen und Grenzen galten. Ändert sich mit jeder Änderung an Stationen, Grenzen oder Zählung.
Probe.REV = "2026-11-23-rest3"   -- Sonderprobe X10 entfernt (Restschaden entfällt); davor 2026-11-22-rest2 (X10), 2026-11-22-rest (Station R, X9)
-- gleiche Antwort ein weiteres Mal: kein Eintrag, nur Zähler und „zuletzt gesehen“ je Prüfwert (probe.same); die
-- Beschreibung steht beim ersten Mal (Fassung 2026-11-14-nachprobe: noch ein Verweis { …, same = Prüfwert } je Abfrage)
Probe.SAME = true
-- Deckel: Die Station „allein“ hält im Spiel allein mehrere hundert Abfragen fest und läuft mehrfach (Freiland,
-- Stadt, zweiter Charakter); 4000 Einträge aus dem Bauauftrag wären nach wenigen Stationen erreicht. Der Deckel gilt
-- hart (Probe.Hard: nur noch zählen); die letzte Reserve darunter bleibt dem Neuen (Probe.Full: ab hier nur noch zählen
-- und Neues festhalten, Probe.IsNew). Der Deckel ist nicht angehoben – die Sonderprobe X1 (Frage 12) wurde am 19.11.2026 abgebrochen.
Probe.MAX_ENTRIES = 12000         -- Abfragen und Ereignisse zusammen
Probe.MAX_BYTES = 3 * 1024 * 1024 -- Läufe und Ereignisse, gerechnet wie in der SavedVariables-Datei (Probe.SizeOf)
Probe.RESERVE_ENTRIES = 600       -- unter dem Deckel nur noch für Neues
Probe.RESERVE_BYTES = 256 * 1024
Probe.MAX_EVENTS = 500            -- festgehaltene Ereignisse je Mitschnitt (gezählt wird weiter)
Probe.EVENT_TOTAL = 24            -- Beispiele je Ereignisname über alle Lagen (mit der Automatik: über alle Sitzungen)
Probe.EVENT_TOTAL_DISTINCT = 80   -- … bei Ereignissen mit Unterscheidungswert (Record.DISTINCT: Zauber, Art des Fensters)
Probe.EVENT_SAMPLES = 8           -- je Ereignisname und Mitschnitt
Probe.SAMPLE_GAP = 0.2            -- Sekunden zwischen zwei Beispielen desselben Ereignisses (Drossel: dazwischen nur zählen)
Probe.DISTINCT_SAMPLES = 2        -- je Ereignis UND Unterscheidungswert (Zauber, Art des Fensters – Record.DISTINCT)
Probe.DISTINCT_MAX = 40           -- so viele verschiedene Werte je Ereignisname, danach zählt nur noch der Name
Probe.REPORT_EVENTS = 40          -- so viele Ereignisse zeigt der Bericht mit Nutzlast
Probe.MAX_TEXT = 120
Probe.MAX_FIELDS = 60
Probe.MAX_DEPTH = 3
Probe.LIST_SAMPLES = 2
Probe.MAX_RETURNS = 40
Probe.WAIT = 5                    -- Sekunden auf die Antwort einer Server-Anfrage
Probe.SLICE_MS = 2                -- Rechenzeit je Bild für alles zusammen (Läufe, Mitschrift, Tempo) – Probe.Takt
Probe.SLICE_CALLS = 120           -- Abfragen je Bild (greift auch, wenn der Client keine feine Uhr hat)
Probe.ENTRY_COST = 4              -- eine festgehaltene Abfrage (beschreiben, maskieren, Größe) zählt wie so viele bloße
Probe.SLICE_NOW_MS = 6            -- erste Portion eines Laufs an einem Ereignis (Beute, Questfenster: gleich wieder zu)
Probe.SLICE_NOW_CALLS = 600
Probe.MIN_NAME = 2
Probe.NAMES_EVERY = 10            -- Sekunden: so oft höchstens sammelt ein Lauf die Namen gründlich (Gilde, Freunde …)
Probe.NAMES_EVERY_EVENT = 60      -- … und so oft ein Beispiel des Mitschnitts (Ziel, Maus und Gruppe jedes Mal)
Probe.probes = {}                 -- Kennung → fn(run)          (ProbeStations.lua)
Probe.stations = {}               -- Schlüssel → { key, words, probes, when, combat }
Probe.stationOrder = {}
Probe.autoProbes = {}             -- Ereignis → { station, ids } (läuft, solange der Mitschnitt an ist)
Probe.KindOf = {}                 -- Station → fn() → Art bzw. Liste der Spielarten des jetzigen Anlasses (ProbeStations.lua)

---------------------------------------------------------------------------
-- Helfer: Namen auflösen, sichere Werte, Zeit
---------------------------------------------------------------------------

local function RawField(t, key) return t[key] end
local function IsSecret(value) return Core.IsSecret(value) end

-- „C_Item.GetItemInfo“ → Wert (nil, wenn ein Teil fehlt). Nur lesen, Felder geschützt.
local function Resolve(path)
    if type(path) ~= "string" or path == "" then return nil end
    local value = _G
    for part in path:gmatch("[^%.]+") do
        if type(value) ~= "table" then return nil end
        local ok, nextValue
        if value == _G then
            ok, nextValue = true, rawget(_G, part)
        else
            ok, nextValue = pcall(RawField, value, part)
        end
        if not ok or IsSecret(nextValue) or nextValue == nil then return nil end
        value = nextValue
    end
    return value
end
Probe.Resolve = Resolve

-- Geheime oder gesperrte Tabelle? (vor jedem Durchlaufen)
local function SecretTable(t)
    local check = rawget(_G, "issecrettable")
    if type(check) == "function" then
        local ok, secret = pcall(check, t)
        if ok and secret == true then return true end
    end
    local access = rawget(_G, "canaccesstable")
    if type(access) == "function" then
        local ok, can = pcall(access, t)
        if ok and can == false then return true end
    end
    return false
end

function Probe.Num(value) return Core.Num(value) end
function Probe.Str(value)
    if IsSecret(value) or type(value) ~= "string" then return nil end
    return value
end
function Probe.Tab(value)
    if IsSecret(value) or type(value) ~= "table" or SecretTable(value) then return nil end
    return value
end
-- Feld einer Tabelle, nur wenn Tabelle und Wert lesbar sind.
function Probe.Field(t, key)
    t = Probe.Tab(t)
    if not t then return nil end
    local ok, value = pcall(RawField, t, key)
    if not ok or IsSecret(value) then return nil end
    return value
end

local GameTime = Core.Uptime

local function ServerTime()
    local fn = rawget(_G, "GetServerTime")
    if type(fn) == "function" then
        local ok, t = pcall(fn)
        if ok and Core.Num(t) then return t end
    end
    return time and time() or 0
end

local function ClockMs()
    if type(debugprofilestop) == "function" then return debugprofilestop() end
    return GameTime() * 1000
end

local function Pack(ok, ...) return ok, select("#", ...), { ... } end

---------------------------------------------------------------------------
-- Privates maskieren: Pseudonyme je Sitzung (die Zuordnung liegt nur im Arbeitsspeicher)
---------------------------------------------------------------------------

local LABEL = { player = "Spieler", guild = "Gilde", rank = "Rang", friend = "Freund", account = "Konto", realm = "Realm",
    twink = "Twink" }
local pseudo, pseudoList, pseudoCount, pseudoSorted = {}, {}, {}, true

local function AddPseudo(name, text)
    if pseudo[name] then return end
    pseudo[name] = text
    pseudoList[#pseudoList + 1] = name
    pseudoSorted = false
end

-- Namen als privat anmelden. → Pseudonym (nil: kein brauchbarer Name). label: fester Text statt laufender Nummer.
function Probe.Private(name, kind, label)
    if IsSecret(name) or type(name) ~= "string" then return nil end
    name = Core.Trim(name)
    -- reine Zahlen sind kein Name (und träfen die Marken des Filters)
    if #name < Probe.MIN_NAME or not name:find("%D") then return nil end
    local known = pseudo[name]
    if known then return known end
    kind = LABEL[kind] and kind or "player"
    local text = label
    if not text then
        pseudoCount[kind] = (pseudoCount[kind] or 0) + 1
        text = "<" .. LABEL[kind] .. ":" .. pseudoCount[kind] .. ">"
    end
    AddPseudo(name, text)
    -- „Name-Realm“: der Name allein ist derselbe Spieler
    if kind ~= "realm" and kind ~= "guild" and kind ~= "account" then
        local short = name:match("^([^%-]+)%-.+$")
        if short and #short >= Probe.MIN_NAME then AddPseudo(short, text) end
    end
    return text
end

-- Pseudonym eines schon angemeldeten Namens (nil: unbekannt) – meldet nichts an.
function Probe.Known(name)
    if IsSecret(name) or type(name) ~= "string" then return nil end
    return pseudo[name]
end

local function IsWordByte(b)
    return b ~= nil and (b >= 128 or (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122))
end

-- Alle Vorkommen eines Namens ersetzen – nur als ganzes Wort (davor und danach kein Buchstabe, keine Ziffer). Mitten im
-- Wort bleibt der Text, wie ihn der Client geliefert hat: ein Gildenmitglied „Kupfer“ macht aus „Kupfererz“ kein
-- Pseudonym (das verfälschte die Antwort und ließe den Namen aus der Nummer daneben zurückrechnen). Ein angehängtes
-- Genitiv-s zählt mit („Fremdlings Begleiter“), außer bei sehr kurzen Namen.
local function ReplaceName(text, name, repl)
    local genitive = #name > 3
    local out, from, pos = nil, 1, 1
    while true do
        local s, e = text:find(name, pos, true)
        if not s then break end
        local after = text:byte(e + 1)
        local wordEnd = not IsWordByte(after) or (genitive and after == 115 and not IsWordByte(text:byte(e + 2)))
        if wordEnd and not IsWordByte(text:byte(s - 1)) then
            out = out or {}
            out[#out + 1] = text:sub(from, s - 1)
            out[#out + 1] = repl
            from = e + 1
        end
        pos = e + 1
    end
    if not out then return text end
    out[#out + 1] = text:sub(from)
    return table.concat(out)
end

-- Blizzards Texte, die einen Spielernamen einsetzen (Tooltip-Zeilen „<Hergestellt von …>“, „Geschenk von …“,
-- „Geschrieben von …“): der eingesetzte Name wird als Spieler angemeldet, auch wenn ihn sonst niemand kennt.
local NAME_FORMATS = { "ITEM_CREATED_BY", "ITEM_WRAPPED_BY", "ITEM_WRITTEN_BY" }
local namePatterns = {}

local function NamedPlayers(text)
    local clean
    for i = 1, #NAME_FORMATS do
        local fmt = rawget(_G, NAME_FORMATS[i])
        if type(fmt) == "string" and fmt ~= "" then
            local pattern = namePatterns[fmt]
            if pattern == nil then
                pattern = Core.FormatToPattern(Core.StripColors(fmt)) or false
                namePatterns[fmt] = pattern
            end
            if pattern then
                clean = clean or Core.Trim(Core.StripColors(text))
                local name = clean:match(pattern)
                if name and name ~= "" then Probe.Private(name, "player") end
            end
        end
    end
end

local function MarkToPseudo(index) return pseudo[pseudoList[tonumber(index)]] end
local function PlayerLink(kind) return "|H" .. kind .. ":<Spieler>|h[<Spieler>]|h" end
local function PlayerGuid(a, b) return ("Player-<%d>-<%d>"):format(#a, #b) end

-- Text ohne Privates: Spieler-Links, Spieler-GUIDs (der Aufbau bleibt: Art, Zahl und Länge der Felder),
-- alle angemeldeten Namen (längste zuerst), BattleTags.
function Probe.MaskText(text)
    if IsSecret(text) or type(text) ~= "string" or #text < 2 then return text end
    if text:find("|H", 1, true) then
        text = text:gsub("|H(B?N?player):[^|]*|h[^|]*|h", PlayerLink)
    end
    if text:find("Player-", 1, true) then
        text = text:gsub("Player%-(%w+)%-(%w+)", PlayerGuid)
    end
    if #text <= 200 and text:find(" ", 1, true) then NamedPlayers(text) end
    if #pseudoList > 0 then
        if not pseudoSorted then
            table.sort(pseudoList, function(a, b)
                if #a ~= #b then return #a > #b end
                return a < b
            end)
            pseudoSorted = true
        end
        -- erst Marken setzen, am Ende die Pseudonyme: ein kurzer Name („Ich“, „Text“) träfe sonst ein eben
        -- eingesetztes Pseudonym
        local marked = false
        for i = 1, #pseudoList do
            local name = pseudoList[i]
            if text:find(name, 1, true) then
                text = ReplaceName(text, name, "\1" .. i .. "\2")
                marked = true
            end
        end
        if marked then text = text:gsub("\1(%d+)\2", MarkToPseudo) end
    end
    if text:find("#", 1, true) then
        text = text:gsub("[^%s|:%[%]<>]+#%d%d%d%d+", "<Konto>")
    end
    return text
end

-- Felder, die überall privat sind (Feldname klein geschrieben): Art des Pseudonyms oder true = nur die Länge.
local FIELD_RULE = {
    playername = "player", playername2 = "player", sender = "player", sendername = "player", owner = "player",
    owners = "player", ownername = "player", bidder = "player", biddername = "player", highbidder = "player",
    charactername = "player", charname = "player", invitedby = "player", invitername = "player", author = "player",
    creator = "player", winner = "player", playerguid = true, ownerfullname = "player", bidderfullname = "player",
    -- "unit": Name einer Einheit neben ihrer GUID – bleibt nur, wenn die GUID daneben einem NPC oder Objekt gehört
    sourcename = "unit", destname = "unit", castername = "unit", unitname = "unit", targetname = "unit", killername = "unit",
    accountname = "account", battletag = "account",
    guildname = "guild", guild = "guild", guildrank = "rank", rankname = "rank",
    realmname = "realm", realmdisplayname = "realm", realm = "realm",
    note = true, notes = true, membernote = true, officernote = true, custommessage = true, richpresence = true,
    motd = true, messagetext = true, body = true, bodytext = true, broadcasttext = true, comment = true,
}

---------------------------------------------------------------------------
-- Beschreiber: Form und EIN Beispielwert je Feld – nie ein geheimer Wert
---------------------------------------------------------------------------

local secretsSeen = 0   -- wie oft „geheim“ vermerkt wurde (für die Zählung eines Laufs)
local Describe

local function Secret()
    secretsSeen = secretsSeen + 1
    return { k = "secret" }
end

local function FieldRule(key, opts)
    local rule = opts and opts.fields and opts.fields[key]
    if rule == nil and type(key) == "string" then rule = FIELD_RULE[key:lower()] end
    return rule
end

-- forced: Regel, die die Tabelle um den Text herum schon entschieden hat ("player", true; false = keine Regel)
local function DescribeText(value, key, opts, forced)
    local d = { k = "string", len = #value }
    if #value == 0 then
        d.leer, d.v = true, ""
        return d
    end
    local rule
    if opts and opts.text then
        rule = true
    elseif forced ~= nil then
        rule = forced or nil
    elseif key ~= nil then
        rule = FieldRule(key, opts)
        -- ohne Tabelle daneben (Rückgabe an fester Stelle) lässt sich „kein Spieler“ nicht belegen
        if rule == "unit" then rule = "player" end
    end
    if rule == true then
        d.v = "<Text>"
    elseif type(rule) == "string" then
        d.v = Probe.Private(value, rule) or "<Text>"
    elseif value:find("[%z\1-\8\11\12\14-\31]") then
        d.v = "<binär>"
    else
        local shown = Probe.MaskText(value)
        if #shown > Probe.MAX_TEXT then
            shown = Core.TruncateBytes(shown, Probe.MAX_TEXT)
            d.cut = true
        end
        d.v = shown
    end
    return d
end

local function KeyLess(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then return ta == "number" end
    return a < b
end

-- GUID-Arten, die sicher kein Spieler und kein Begleiter eines Spielers sind
local NPC_GUID = { Creature = true, Vehicle = true, GameObject = true }
Probe.NPC_GUID = NPC_GUID

-- Regel "unit" für das Feld key: Steht in derselben Tabelle die GUID dazu (sourceName » sourceGUID; name » guid bzw.
-- jedes Feld …GUID) und gehört sie lesbar einem NPC oder Objekt, bleibt der Name. Sonst – Spieler, Begleiter, GUID
-- gesperrt oder gar keine GUID – ist er privat.
local function UnitNameIsNpc(value, names, key)
    local prefix = key:lower():gsub("name$", "")
    local exact, any = {}, {}
    for i = 1, #names do
        local lower = names[i]:lower()
        if lower:sub(-4) == "guid" then
            any[#any + 1] = names[i]
            if lower == prefix .. "guid" then exact[#exact + 1] = names[i] end
        end
    end
    local list = #exact > 0 and exact or any
    if #list == 0 then return false end
    for i = 1, #list do
        local ok, guid = pcall(RawField, value, list[i])
        guid = ok and Probe.Str(guid) or nil
        if not (guid and NPC_GUID[guid:match("^([^%-]+)") or ""]) then return false end
    end
    return true
end

local function DescribeTable(value, depth, key, opts, forced)
    if SecretTable(value) then return Secret() end
    local okZero, zero = pcall(rawget, value, 0)
    if okZero and not IsSecret(zero) and type(zero) == "userdata" then return { k = "frame" } end
    local names, numbers, n, secretKeys, functions = {}, {}, 0, 0, 0
    local okLen, len = pcall(function() return #value end)
    len = okLen and Core.Num(len) or 0
    local okPairs = pcall(function()
        for k, v in pairs(value) do
            n = n + 1
            if IsSecret(k) then
                secretKeys = secretKeys + 1
            elseif not IsSecret(v) and type(v) == "function" then
                functions = functions + 1
            elseif type(k) == "string" then
                if #names < 2000 then names[#names + 1] = k end
            elseif type(k) == "number" then
                if not (k >= 1 and k <= len and k == math.floor(k)) and #numbers < 2000 then numbers[#numbers + 1] = k end
            end
        end
    end)
    local d = { k = "table", n = n }
    if not okPairs then d.err = "pairs" end
    if secretKeys > 0 then d.sk = secretKeys end
    if functions > 0 then d.fn = functions end
    if len > 0 then d.len = len end
    if depth >= Probe.MAX_DEPTH then return d end
    local child = depth + 1
    local samples = opts and opts.samples or Probe.LIST_SAMPLES
    if len > 0 then
        d.l = {}
        for i = 1, math.min(len, samples) do
            local ok, v = pcall(RawField, value, i)
            d.l[i] = ok and Describe(v, child, key, opts, forced) or { k = "error" }
        end
    end
    if #numbers > 0 then
        table.sort(numbers)
        d.nk, d.m = #numbers, {}
        for i = 1, math.min(#numbers, samples) do
            local ok, v = pcall(RawField, value, numbers[i])
            d.m[numbers[i]] = ok and Describe(v, child, key, opts, forced) or { k = "error" }
        end
    end
    if #names > 0 then
        table.sort(names, KeyLess)
        local maxFields = opts and opts.maxFields or Probe.MAX_FIELDS
        d.f = {}
        for i = 1, math.min(#names, maxFields) do
            local name = names[i]
            local ok, v = pcall(RawField, value, name)
            local decided
            if FieldRule(name, opts) == "unit" then decided = not UnitNameIsNpc(value, names, name) and "player" end
            d.f[name] = ok and Describe(v, child, name, opts, decided) or { k = "error" }
        end
        if #names > maxFields then d.more = #names - maxFields end
    end
    return d
end

function Describe(value, depth, key, opts, forced)
    if IsSecret(value) then return Secret() end
    local kind = type(value)
    if kind == "nil" then
        return { k = "nil" }
    elseif kind == "boolean" then
        return { k = "boolean", v = value }
    elseif kind == "number" then
        -- NaN und Unendlich stehen als Text da (die SavedVariables-Datei wäre sonst nicht mehr lesbar)
        if value ~= value or value == math.huge or value == -math.huge then return { k = "number", v = tostring(value) } end
        return { k = "number", v = value }
    elseif kind == "string" then
        return DescribeText(value, key, opts, forced)
    elseif kind == "table" then
        return DescribeTable(value, depth, key, opts, forced)
    end
    return { k = kind }
end

function Probe.Describe(value, opts) return Describe(value, 0, nil, opts) end
function Probe.SecretsSeen() return secretsSeen end

-- Größe eines eigenen Eintrags, wie ihn der Client in die SavedVariables-Datei schreibt (Bytes): je Feld eine Zeile
-- mit Einrückung (ein Tab je Tiefe), „["schlüssel"] = “ bzw. bei Listenplätzen „, -- [n]“, Komma und Zeilenende; je
-- Tabelle zwei Zeilen für die Klammern. depth: Tiefe, in der der Eintrag in der Datei steht (ein Aufruf eines Laufs:
-- Probe.DEPTH_CALL, ein Ereignis: Probe.DEPTH_EVENT).
local function SizeOf(value, depth)
    local kind = type(value)
    if kind == "string" then return #value + 2 end
    if kind == "number" then return #tostring(value) end
    if kind == "boolean" then return value and 4 or 5 end
    if kind ~= "table" then return 0 end
    depth = depth or 0
    local inner = depth + 1
    local size = 3 + depth + 1
    for k, v in pairs(value) do
        size = size + inner + (type(k) == "string" and #k + 7 or 9) + SizeOf(v, inner) + 3
    end
    return size
end
Probe.SizeOf = SizeOf
Probe.DEPTH_RUN = 3       -- ezCoreDB » probe » runs » Lauf
Probe.DEPTH_CALL = 5      -- … » Lauf » calls » Aufruf
Probe.DEPTH_EVENT = 3     -- ezCoreDB » probe » events » Ereignis
Probe.DEPTH_DOC = 4       -- ezCoreDB » probe » doc » s » System

-- Prüfwert eines Texts: Länge und zwei Summen über alle Bytes (je modulo einer Primzahl unter 2^31 – reine Arithmetik,
-- Lua 5.1 ohne bit). → Text wie "1f4.3a2b…" (kurz, gleich für gleiche Texte; zwei verschiedene Texte treffen sich
-- praktisch nie). Für die Verweise auf gleiche Antworten (same) und den Prüfwert des Charakters (chars).
function Probe.Hash(text)
    text = tostring(text)
    local h1, h2, byte = 5381, 52711, string.byte
    for i = 1, #text do
        local b = byte(text, i)
        h1 = (h1 * 33 + b) % 2147483629
        h2 = (h2 * 131 + b) % 2147483587
    end
    return ("%x.%x.%x"):format(#text, h1, h2)
end

-- Eindeutiger Text einer Beschreibung (Schlüssel sortiert) – nur für den Prüfwert, nie gespeichert.
function Probe.Canon(value, out)
    local kind = type(value)
    if kind == "table" then
        local keys = {}
        for key in pairs(value) do keys[#keys + 1] = key end
        table.sort(keys, KeyLess)
        out[#out + 1] = "{"
        for i = 1, #keys do
            local key = keys[i]
            out[#out + 1] = tostring(key)
            out[#out + 1] = "="
            Probe.Canon(value[key], out)
            out[#out + 1] = ";"
        end
        out[#out + 1] = "}"
    elseif kind == "string" then
        out[#out + 1] = ("%q"):format(value)
    else
        out[#out + 1] = tostring(value)
    end
    return out
end

---------------------------------------------------------------------------
-- Ablage
---------------------------------------------------------------------------

local memory                                   -- Ablage ohne ezCoreDB (sehr früher Aufruf)
local pendingEntries, pendingBytes = 0, 0      -- Läufe, die im Kampf noch im Arbeitsspeicher warten
local stamp

local function Stamp()
    if stamp then return stamp end
    local version, build, buildDate, iface = "?", "?", "?", 0
    local info = rawget(_G, "GetBuildInfo")
    if type(info) == "function" then
        local ok, a, b, c, d = pcall(info)
        if ok then
            version = Probe.Str(a) or version
            build = Probe.Str(b) or (Core.Num(b) and tostring(b)) or build
            buildDate = Probe.Str(c) or buildDate
            iface = Core.Num(d) or iface
        end
    end
    local realm
    local realmID = rawget(_G, "GetRealmID")
    if type(realmID) == "function" then
        local ok, id = pcall(realmID)
        if ok then realm = Core.Num(id) end
    end
    stamp = { version = version, build = build, date = buildDate, iface = iface,
        project = Core.Num(rawget(_G, "WOW_PROJECT_ID")), locale = GetLocale and GetLocale() or "?", realm = realm }
    return stamp
end
Probe.Stamp = Stamp

local STORE_TABLES = { "runs", "events", "counts", "tempo", "done", "kinds", "per", "tot", "same" }

-- Bereich der Zählung „je Build und Sprache“ (Station „allein“: ihre Antworten ändern sich erst mit dem Build oder
-- der Sprache) – „b70938.deDE“
function Probe.BuildScope(build, locale)
    return "b" .. tostring(build or Stamp().build) .. "." .. tostring(locale or Stamp().locale)
end

-- Schlüssel der Station eines Laufs: k (ab Fassung 2026-11-15-klein); ältere Läufe tragen nur den Kennbuchstaben st –
-- „allein“ und „Karte“ teilen ihn (A), erkennbar an Probe A1, die nur „allein“ fragt; „Beute“ (G10) an G10/G13/G10O.
function Probe.RunKey(run)
    if type(run) ~= "table" then return nil end
    if type(run.k) == "string" then return run.k end
    local st = run.st
    if st ~= "A" and st ~= "G" then return st end
    local calls = type(run.calls) == "table" and run.calls or {}
    for i = 1, #calls do
        local id = type(calls[i]) == "table" and calls[i].id
        if st == "A" and id == "A1" then return "A" end
        if st == "G" and id ~= nil and id ~= "G10" and id ~= "G13" and id ~= "G10O" then return "G" end
    end
    return st == "A" and "W" or "G10"
end

-- Ablage einer älteren Fassung: Zähler der Automatik, die es dort noch nicht gab, aus den Läufen nachtragen – sonst
-- liefe eine Station nach dem Wechsel der Fassung noch einmal ganz (so geschehen im Lauf vom 15.11.2026: „allein“ in
-- Sitzung 6 mit 1171 Abfragen, weil die Zähler „je Charakter“ neu waren). Gezählt werden die Läufe der Automatik
-- (auto) mit Charakter (ch, ab Fassung 2026-11-14-nachprobe) für jede Art, die sie trugen (Station, kind, also), im
-- Bereich ihrer Art – nicht „je Kontinent“ (den trägt kein Lauf); Abfragen am Ereignis des Mitschnitts sind keine
-- Station und zählen hier nicht. Ein Zähler wird nur angehoben, nie gesenkt (max): Was schon da ist, zählt nicht
-- doppelt. → Zahl der angehobenen Zähler
function Probe.Upgrade(p)
    local scopes = {}
    for _, entry in ipairs(Probe.Auto and Probe.Auto.KINDS or {}) do scopes[entry[1]] = entry.scope end
    local per, tot = {}, {}
    local runs = type(p.runs) == "table" and p.runs or {}
    for i = 1, #runs do
        local run = runs[i]
        local ch = type(run) == "table" and run.auto == true and Core.Num(run.ch)
        if ch then
            local key = Probe.RunKey(run)
            local kinds = { key }
            if type(run.kind) == "string" and run.kind ~= key then kinds[#kinds + 1] = run.kind end
            for _, kind in ipairs(type(run.also) == "table" and run.also or {}) do kinds[#kinds + 1] = kind end
            local lg = type(run.lg) == "string" and run.lg or "w"
            for _, kind in ipairs(kinds) do
                local scope, where = scopes[kind], nil
                if scope == "char" then where = "-"
                elseif scope == "lage" then where = lg
                elseif scope == "where" then where = lg:sub(1, 1)
                elseif scope == "build" and run.b ~= nil then where = Probe.BuildScope(run.b, run.loc) end
                if where then
                    local t = kind .. "|" .. where
                    local c = t .. "|" .. tostring(ch)
                    tot[t] = (tot[t] or 0) + 1
                    per[c] = (per[c] or 0) + 1
                    if scope == "build" then   -- dazu über alle Builds (Auto.AllKey)
                        tot[kind .. "|*"] = (tot[kind .. "|*"] or 0) + 1
                        per[kind .. "|*|" .. tostring(ch)] = (per[kind .. "|*|" .. tostring(ch)] or 0) + 1
                    end
                end
            end
        end
    end
    local raised = 0
    for _, pair in ipairs({ { per, p.per }, { tot, p.tot } }) do
        for k, n in pairs(pair[1]) do
            if n > (Core.Num(pair[2][k]) or 0) then
                pair[2][k] = n
                raised = raised + 1
            end
        end
    end
    return raised
end

-- Zufalls-Kennung der Ablage (8 Hex-Zeichen): trennt im Bericht mehrerer Helfer die Installationen, ohne Namen,
-- Realm oder Konto zu nennen. Bleibt bei „Probe leeren“ (Knopf und Befehl), neu nur nach Probe.Clear() ohne opts.
function Probe.NewInstall()
    local random = math.random
    return ("%04x%04x"):format(random(0, 65535), random(0, 65535))
end

local function Store()
    local holder = type(Core.db) == "table" and Core.db or nil
    local p
    if holder then p = holder.probe else p = memory end
    if type(p) ~= "table" or p.v ~= Probe.VERSION then
        p = { v = Probe.VERSION }
        if holder then holder.probe = p else memory = p end
    end
    for i = 1, #STORE_TABLES do
        local key = STORE_TABLES[i]
        if type(p[key]) ~= "table" then p[key] = {} end
    end
    p.entries = Core.Num(p.entries) or 0
    p.bytes = Core.Num(p.bytes) or 0
    if type(p.install) ~= "string" or p.install == "" then p.install = Probe.NewInstall() end
    if p.rev ~= Probe.REV then
        Probe.Upgrade(p)
        p.rev = Probe.REV
    end
    if type(p.meta) ~= "table" or p.meta.build ~= Stamp().build then
        local s = Stamp()
        p.meta = { version = s.version, build = s.build, date = s.date, iface = s.iface, project = s.project,
            locale = s.locale, realm = s.realm, started = ServerTime() }
    end
    return p
end

-- Laufende Nummer dieser Sitzung in der Ablage (zählt bei jedem Spielstart bzw. /reload, sobald etwas festgehalten
-- wird). Jeder Lauf und jedes Ereignis trägt sie: Pseudonyme sind nur innerhalb einer Sitzung dieselbe Person.
local session
function Probe.Session()
    if session then return session end
    local p = Store()
    p.sessions = (Core.Num(p.sessions) or 0) + 1
    session = p.sessions
    return session
end

-- Die Ablage, ohne sie anzulegen (nil, solange nichts festgehalten wurde).
function Probe.Data()
    local holder = type(Core.db) == "table" and Core.db or nil
    local p
    if holder then p = holder.probe else p = memory end
    return type(p) == "table" and p or nil
end

-- Voll? hard: der Deckel selbst (Probe.Hard); sonst der Deckel abzüglich der Reserve für Neues (Probe.Full).
-- extraEntries, extraBytes: ein Lauf, der noch nicht in der Ablage steht.
function Probe.Over(hard, extraEntries, extraBytes)
    local p = Probe.Data()
    local entries = (p and Core.Num(p.entries) or 0) + pendingEntries + (extraEntries or 0)
    local bytes = (p and Core.Num(p.bytes) or 0) + pendingBytes + (extraBytes or 0)
    local e, b = Probe.MAX_ENTRIES, Probe.MAX_BYTES
    if not hard then e, b = e - Probe.RESERVE_ENTRIES, b - Probe.RESERVE_BYTES end
    return entries >= e or bytes >= b
end

-- Voll: Die Ablage hat ihren Deckel bis auf die Reserve erreicht – ab jetzt wird nur noch gezählt und Neues
-- festgehalten (eine Art, die in diesem Bereich noch keinen Lauf hat; ein Ereignis ohne Beispiel in dieser Lage), bis
-- auch die Reserve voll ist (Probe.Hard: der Deckel selbst, nur noch zählen). Die Automatik bleibt an.
function Probe.Full() return Probe.Over(false) end
function Probe.Hard() return Probe.Over(true) end

-- „Die Daten-Probe ist voll …“ – höchstens einmal je Sitzung (auto: die Zeile der Automatik); ist auch die Reserve
-- voll (Probe.Hard), noch einmal „ganz voll“: ab da wird nichts mehr festgehalten. Vermerkt in der Ablage, wann der
-- Deckel erreicht war (full = { t, s }). → true, wenn die Zeile jetzt kam
do
    local said = false   -- false | "full" | "hard"
    function Probe.SayFull(auto)
        local p = Probe.Data()
        if p and type(p.full) ~= "table" then p.full = { t = ServerTime(), s = Core.Num(p.sessions) } end
        local hard = Probe.Hard()
        if said == "hard" or (said == "full" and not hard) then return false end
        said = hard and "hard" or "full"
        local text
        if hard then text = auto and L.PROBE_AUTO_HARD or L.PROBE_HARD else text = auto and L.PROBE_AUTO_FULL or L.PROBE_FULL end
        ns.Print(text:format(Probe.SizeText(Core.Num(p and p.bytes) or 0)))
        return true
    end
    -- neue Sitzung bzw. geleerte Ablage: die Meldung darf wieder einmal kommen
    function Probe.ForgetFull() said = false end
end

-- Nummern, die eine Probe für eine spätere braucht (ein Rezept des eigenen Berufs für A13 ohne offenes Fenster, ein
-- Zerlege-Rezept für GetSalvagableItemIDs) – nur Zahlen des Spiels, nichts Privates. Probe.Hint() → Tabelle (ohne
-- Ablage: {}), Probe.Hint(schlüssel, zahl) merkt eine.
function Probe.Hint(key, value)
    if key == nil then
        local p = Probe.Data()
        return p and type(p.hint) == "table" and p.hint or {}
    end
    local p = Store()
    if type(p.hint) ~= "table" then p.hint = {} end
    p.hint[key] = Core.Num(value)
    return p.hint
end

local statusChanged   -- Statuszeile der Einstellungsseite nachziehen (unten gesetzt)

-- kind: Art des Laufs für die Zählung der Automatik – der Schlüssel der Station oder, beim Ziel, die Zielart ("F:npc");
-- tally: { { kind, per, tot } … } – alle Arten, für die der Lauf zählt, mit ihren Schlüsseln je Charakter und Lage
-- (Probe.Auto.Tally, beim Start des Laufs bestimmt)
local function Commit(data, bytes, key, kind, tally)
    local p = Store()
    p.runs[#p.runs + 1] = data
    p.entries = p.entries + #data.calls
    p.bytes = p.bytes + bytes
    if key then p.done[key] = (Core.Num(p.done[key]) or 0) + 1 end
    for i = 1, tally and #tally or 0 do
        local t = tally[i]
        if t.kind ~= key then p.kinds[t.kind] = (Core.Num(p.kinds[t.kind]) or 0) + 1 end
        p.per[t.per] = (Core.Num(p.per[t.per]) or 0) + 1
        p.tot[t.tot] = (Core.Num(p.tot[t.tot]) or 0) + 1
        if t.aper then   -- Bereich „je Build“: dazu über alle Builds (Auto.BUILD_LIMIT, Auto.BUILD_TOTAL)
            p.per[t.aper] = (Core.Num(p.per[t.aper]) or 0) + 1
            p.tot[t.atot] = (Core.Num(p.tot[t.atot]) or 0) + 1
        end
    end
    if not tally and kind and kind ~= key then p.kinds[kind] = (Core.Num(p.kinds[kind]) or 0) + 1 end
    if data.auto and Probe.Auto then Probe.Auto.Committed(tally) end
    if statusChanged then statusChanged() end
end

-- opts.keepAuto = true (Knopf und Befehl „Probe leeren“, Befund 15.11.2026): die Einstellung der Automatik (an/aus,
-- leise, ohne Tempo) und die Zufalls-Kennung der Installation bleiben, die Automatik läuft weiter, wenn sie an war.
-- Ohne opts wird alles zurückgesetzt (Prüfungen).
function Probe.Clear(opts)
    local had = Probe.Status().entries
    local keep
    if type(opts) == "table" and opts.keepAuto then
        local old = Probe.Data()
        local a = type(old) == "table" and type(old.auto) == "table" and old.auto or nil
        keep = { install = type(old) == "table" and type(old.install) == "string" and old.install or nil,
            auto = a and { on = a.on == true or nil, quiet = a.quiet == true or nil, noTempo = a.noTempo == true or nil } or nil }
    end
    if Probe.Auto then Probe.Auto.Forget() end   -- der Arbeitsspeicher der Automatik gehört zur alten Ablage
    if type(Core.db) == "table" then Core.db.probe = nil end
    if Probe.ForgetKeys then Probe.ForgetKeys() end   -- Nummer des Charakters, Prüfwerte gleicher Antworten
    memory, session = nil, nil
    Probe.ForgetFull()
    pendingEntries, pendingBytes = 0, 0
    if Probe.Record then Probe.Record.Forget() end   -- Zähler und Beispiele im Arbeitsspeicher gehören zur alten Ablage
    if keep and (keep.install or (keep.auto and next(keep.auto))) then
        local p = Store()
        if keep.install then p.install = keep.install end
        if keep.auto and next(keep.auto) then p.auto = keep.auto end
        if keep.auto and keep.auto.on and Probe.Auto and Probe.Auto.Restart then Probe.Auto.Restart() end
    end
    if statusChanged then statusChanged() end
    return had
end

function Probe.Status()
    local p = Probe.Data()
    local s = { runs = 0, calls = 0, events = 0, entries = 0, bytes = 0, tempo = 0, docSystems = 0, docBytes = 0,
        fileBytes = 0, pending = pendingEntries, full = Probe.Full(), hard = Probe.Hard() }
    if not p then return s end
    s.runs = type(p.runs) == "table" and #p.runs or 0
    s.events = type(p.events) == "table" and #p.events or 0
    s.entries = Core.Num(p.entries) or 0
    s.calls = math.max(0, s.entries - s.events)
    s.bytes = Core.Num(p.bytes) or 0
    s.tempo = type(p.tempo) == "table" and #p.tempo or 0
    if type(p.doc) == "table" then
        s.docSystems = type(p.doc.s) == "table" and #p.doc.s or 0
        s.docBytes = Core.Num(p.doc.bytes) or 0
    end
    s.fileBytes = s.bytes + s.docBytes   -- so viel legt die Probe zusammen in die SavedVariables-Datei
    return s
end

local function SizeText(bytes)
    bytes = Core.Num(bytes) or 0
    if bytes >= 1024 * 1024 then return L.PROBE_SIZE_MB:format(bytes / (1024 * 1024)) end
    return L.PROBE_SIZE_KB:format(math.ceil(bytes / 1024))
end
Probe.SizeText = SizeText

function Probe.StatusText()
    local s = Probe.Status()
    local text = L.PROBE_STATUS:format(s.entries, s.runs, s.events, SizeText(s.bytes))
    if s.docSystems > 0 then text = text .. L.PROBE_STATUS_DOC:format(s.docSystems, SizeText(s.docBytes)) end
    if s.tempo > 0 then text = text .. L.PROBE_STATUS_TEMPO:format(s.tempo) end
    if s.docSystems > 0 then text = text .. L.PROBE_STATUS_SUM:format(SizeText(s.fileBytes)) end
    if Probe.Auto and Probe.Auto.Enabled() then
        local done = Probe.Auto.Completed() and #Probe.Auto.Open() == 0
        text = text .. (done and L.PROBE_STATUS_AUTO_DONE or L.PROBE_STATUS_AUTO)
    end
    if s.hard then
        text = text .. L.PROBE_STATUS_HARD
    elseif s.full then
        text = text .. L.PROBE_STATUS_FULL
    end
    return text
end

---------------------------------------------------------------------------
-- Bekannte Namen einsammeln (vor jedem Lauf und vor jedem mitgeschnittenen Ereignis)
---------------------------------------------------------------------------

local function Invoke(path, ...)
    local fn = type(path) == "function" and path or Resolve(path)
    if type(fn) ~= "function" then return { ok = false, n = 0, missing = true } end
    local ok, n, values = Pack(pcall(fn, ...))
    if not ok then return { ok = false, n = 0, err = values[1] } end
    values.ok, values.n = true, n
    return values
end

local lastNames

local function UnitNames(unit, kind)
    local r = Invoke("UnitName", unit)
    if not r.ok then return end
    Probe.Private(r[1], kind)
    Probe.Private(r[2], "realm")
end

local function PlayerUnit(unit)
    local exists = Invoke("UnitExists", unit)
    if not exists.ok or IsSecret(exists[1]) or not exists[1] then return false end
    local isPlayer = Invoke("UnitIsPlayer", unit)
    return isPlayer.ok and not IsSecret(isPlayer[1]) and isPlayer[1] == true
end

local function CollectGroup()
    for i = 1, 4 do UnitNames("party" .. i, "player") end
    local raid = Invoke("IsInRaid")
    if raid.ok and not IsSecret(raid[1]) and raid[1] then
        for i = 1, 40 do UnitNames("raid" .. i, "player") end
    end
end

-- Schnell: Ziel, Maus, Fokus, Gesprächspartner (samt Gilde und Rang) und die Gruppe – vor jedem Lauf und jedem
-- festgehaltenen Ereignis, damit ein eben dazugekommenes Gruppenmitglied nie unbekannt ist.
function Probe.CollectUnitNames()
    for _, unit in ipairs({ "target", "mouseover", "focus", "npc", "questnpc" }) do
        if PlayerUnit(unit) then
            UnitNames(unit, "player")
            local guild = Invoke("GetGuildInfo", unit)
            if guild.ok then
                Probe.Private(guild[1], "guild")
                Probe.Private(guild[2], "rank")
                Probe.Private(guild[4], "realm")
            end
        end
    end
    CollectGroup()
end

-- Ist die gründliche Sammlung fällig (älter als maxAge Sekunden, Standard Probe.NAMES_EVERY)?
function Probe.NamesStale(maxAge)
    local now = GameTime()
    return not (lastNames and now - lastNames < (maxAge or Probe.NAMES_EVERY) and now >= lastNames)
end

local namesPause   -- unten gesetzt (Breathe): zählt eine Abfrage aufs Budget und pausiert den Schritt, wenn es verbraucht ist

-- Gründlich: eigener Charakter, Twinks, Realm, Gilde, Freunde, Battle.net – höchstens alle maxAge Sekunden (Standard
-- Probe.NAMES_EVERY; force: sofort); Ziel, Maus und Gruppe jedes Mal. Die Gildenliste kostet je Mitglied eine Abfrage:
-- deshalb fragt der Mitschnitt seltener gründlich als ein Lauf.
-- run: der Lauf, dessen erster Schritt gerade sammelt – dann in Portionen (Pause je Eintrag der Gildenliste, der Freunde
-- und der Battle.net-Freunde; bis zu 900 Abfragen liefen sonst in einem Bild). „Gesammelt“ gilt erst am Ende: wer
-- währenddessen selbst sammeln muss (ein Beispiel des Mitschnitts), sammelt gründlich in einem Stück.
function Probe.CollectNames(force, maxAge, run)
    local now = GameTime()
    if not force and not Probe.NamesStale(maxAge) then
        Probe.CollectUnitNames()
        return #pseudoList
    end
    local pause = run and namesPause or nil
    if not pause then lastNames = now end
    -- eigener Charakter: der volle Name, Vor- und Nachname mit festen Marken (die Frage „welcher Wert ist der
    -- Nachname“ bleibt beantwortbar)
    local own = Invoke("UnitName", "player")
    if own.ok then
        local first, last = Probe.Str(own[1]), Probe.Str(own[2])
        if first and last and last ~= "" and not first:find(last, 1, true) then
            Probe.Private(first .. " " .. last, "player", "<Ich>")
        end
        if first and first:find(" ", 1, true) then
            Probe.Private(first, "player", "<Ich>")
            for word in first:gmatch("%S+") do Probe.Private(word, "player", "<Ich:Namensteil>") end
        end
        Probe.Private(first, "player", "<Ich:Vorname>")
        Probe.Private(last, "player", "<Ich:Nachname>")
    end
    for _, path in ipairs({ "UnitFullName", "UnitNameUnmodified" }) do
        local r = Invoke(path, "player")
        if r.ok then
            Probe.Private(r[1], "player", "<Ich>")
            Probe.Private(r[2], "realm")
        end
    end
    for _, path in ipairs({ "GetRealmName", "GetNormalizedRealmName" }) do
        local r = Invoke(path)
        if r.ok then Probe.Private(r[1], "realm") end
    end
    -- Twinks aus den Charakterdaten
    local chars = Core.Chars and Core.Chars() or {}
    for key, c in pairs(chars) do
        if type(c) == "table" and key ~= Core.charKey then
            local text = Probe.Private(c.name, "twink")
            if text and type(c.name) == "string" then
                for word in c.name:gmatch("%S+") do
                    if #word >= 3 then AddPseudo(word, text) end
                end
            end
            Probe.Private(c.realm, "realm")
        end
    end
    -- Gilde
    local guild = Invoke("GetGuildInfo", "player")
    if guild.ok then
        Probe.Private(guild[1], "guild")
        Probe.Private(guild[2], "rank")
        Probe.Private(guild[4], "realm")
    end
    local members = Invoke("GetNumGuildMembers")
    for i = 1, math.min(members.ok and Core.Num(members[1]) or 0, 500) do
        if pause then pause(run) end
        local m = Invoke("GetGuildRosterInfo", i)
        if m.ok then
            Probe.Private(m[1], "player")
            Probe.Private(m[2], "rank")
        end
    end
    -- Freunde und Battle.net
    local friends = Invoke("C_FriendList.GetNumFriends")
    for i = 1, math.min(friends.ok and Core.Num(friends[1]) or 0, 200) do
        if pause then pause(run) end
        local info = Invoke("C_FriendList.GetFriendInfoByIndex", i)
        if info.ok then Probe.Private(Probe.Field(info[1], "name"), "friend") end
    end
    local bn = Invoke("BNGetNumFriends")
    for i = 1, math.min(bn.ok and Core.Num(bn[1]) or 0, 200) do
        if pause then pause(run) end
        local info = Invoke("C_BattleNet.GetFriendAccountInfo", i)
        if info.ok then
            Probe.Private(Probe.Field(info[1], "accountName"), "account")
            Probe.Private(Probe.Field(info[1], "battleTag"), "account")
            local game = Probe.Field(info[1], "gameAccountInfo")
            Probe.Private(Probe.Field(game, "characterName"), "friend")
            Probe.Private(Probe.Field(game, "realmName"), "realm")
        end
    end
    local me = Invoke("BNGetInfo")
    if me.ok then Probe.Private(me[2], "account") end
    Probe.CollectUnitNames()   -- Ziel, Maus, Fokus, Gesprächspartner, Gruppe
    if pause then lastNames = GameTime() end
    return #pseudoList
end

---------------------------------------------------------------------------
-- Zusammenhang eines Laufs
---------------------------------------------------------------------------

local WINDOWS = {   -- Blizzards Fenster, nur gelesen (IsShown)
    { "merchant", "MerchantFrame" }, { "trainer", "ClassTrainerFrame" }, { "mail", "MailFrame" },
    { "auction", "AuctionHouseFrame" }, { "bank", "BankFrame" }, { "profession", "ProfessionsFrame" },
    { "profession", "TradeSkillFrame" }, { "taxi", "TaxiFrame" }, { "taxi", "FlightMapFrame" },
    { "gossip", "GossipFrame" }, { "quest", "QuestFrame" }, { "loot", "LootFrame" }, { "map", "WorldMapFrame" },
    { "inspect", "InspectFrame" },
}

-- → Menge { merchant = true … }, Liste der Schlüssel
function Probe.OpenWindows()
    local set, list = {}, {}
    for _, entry in ipairs(WINDOWS) do
        local frame = rawget(_G, entry[2])
        local isShown = Core.Peek(frame, "IsShown")
        if type(isShown) == "function" then
            local ok, shown = pcall(isShown, frame)
            if ok and not IsSecret(shown) and shown and not set[entry[1]] then
                set[entry[1]] = true
                list[#list + 1] = entry[1]
            end
        end
    end
    return set, list
end

local function Simple(path, ...)
    local r = Invoke(path, ...)
    if not r.ok then return nil end
    local value = r[1]
    if IsSecret(value) then return "secret" end
    local kind = type(value)
    if kind == "number" or kind == "string" or kind == "boolean" then return value end
    return nil
end

function Probe.Context()
    local ctx = { combat = Core.InCombat() and true or false }
    ctx.map = Simple("C_Map.GetBestMapForUnit", "player")
    local inst = Invoke("GetInstanceInfo")
    if inst.ok then
        ctx.itype = Probe.Str(inst[2])
        ctx.inst = Core.Num(inst[8])
    end
    ctx.restr = {}
    for i = 0, 5 do
        local state = Simple("C_RestrictedActions.GetAddOnRestrictionState", i)
        ctx.restr[i + 1] = state == nil and "?" or state
    end
    ctx.group = Simple("GetNumGroupMembers")
    local class = Invoke("UnitClass", "player")
    if class.ok then ctx.class = Probe.Str(class[2]) end
    ctx.level = Simple("UnitLevel", "player")
    ctx.side = Simple("UnitFactionGroup", "player")
    ctx.dead = Simple("UnitIsDeadOrGhost", "player") == true or nil
    local _, list = Probe.OpenWindows()
    if #list > 0 then ctx.win = table.concat(list, ",") end
    return ctx
end

---------------------------------------------------------------------------
-- Charakter, Lage, gleiche Antworten (Nachprobe 14.11.2026: Grenzen je Charakter und Lage, Ablage klein halten)
---------------------------------------------------------------------------

--[[
      Probe.CharIndex(anlegen)   → Nummer des Charakters in dieser Ablage (1, 2 …; 0 = unbekannt). Gemerkt wird nur ein
                                   Schlüssel aus der Zufalls-Kennung der Ablage und der eigenen GUID (probe.chars,
                                   Probe.CharKey: 16 Bit, nicht umkehrbar), nie die GUID oder ein Name. Ohne anlegen
                                   wird nichts geschrieben (vorläufige Nummer).
      Probe.CharKey(install, guid) → "c1a2b" (Schlüssel in probe.chars)
      Probe.Lage()               → "w" Freiland | "i" Instanz, dazu "g" in einer Gruppe, "b" im Bosskampf („ig“, „ib“ …)
      Probe.Continent()          → uiMapID des Kontinents, auf dem der Charakter steht (nil: unbekannt)
      Probe.Same(eintrag)        → derselbe Eintrag (neu, mit h) oder ein kurzer Verweis { …, same = h } auf eine gleiche
                                   Antwort, die schon in der Ablage oder in dieser Sitzung steht
      Probe.ForgetKeys()         → Arbeitsspeicher zurücksetzen (Leeren der Probe)
      Probe.ForgetLage()         → Lage und Kontinent beim nächsten Fragen neu bestimmen
    Alle drei Werte gelten je Bild (GetTime) – mehrfaches Fragen im selben Bild kostet nichts.
]]
do
    Probe.CHAR_BITS = 16
    local charIndex, charAt
    local lageText, lageAt
    local continentID, continentAt
    local dupIndex   -- Prüfwert → true (Ablage und diese Sitzung); nil = noch nicht aufgebaut

    -- Schlüssel des Charakters in probe.chars: nur Probe.CHAR_BITS (16) Bit des Prüfwerts aus Zufalls-Kennung und GUID.
    -- So lässt sich die GUID (und mit ihr der Realm) aus der Datei nicht zurückrechnen: Zu einem Schlüssel passen je
    -- Server rund 65 000 GUIDs. Zwei Charaktere einer Installation teilen ihn nur selten (bei zehn etwa 1 : 1400) – dann
    -- zählen sie als einer.
    function Probe.CharKey(install, guid)
        local h2 = tostring(Probe.Hash(tostring(install) .. "|" .. tostring(guid))):match("([%x]+)$") or "0"
        return ("c%04x"):format((tonumber(h2, 16) or 0) % (2 ^ Probe.CHAR_BITS))
    end

    function Probe.CharIndex(create)
        -- gemerkt: für immer, sobald sie in der Ablage steht (charAt = true); eine vorläufige Nummer für dieses Bild
        if charIndex and (charAt == true or (not create and charAt == GameTime())) then return charIndex end
        local guid = Invoke("UnitGUID", "player")
        local text = guid.ok and Probe.Str(guid[1]) or nil
        if not text or text == "" then return 0 end
        local p = create and Store() or Probe.Data()
        if not p then   -- noch keine Ablage: der erste Charakter
            charIndex, charAt = 1, GameTime()
            return 1
        end
        local chars = type(p.chars) == "table" and p.chars or nil
        local key = Probe.CharKey(p.install, text)
        local n = chars and Core.Num(chars[key])
        if n then
            charIndex, charAt = n, true
            return n
        end
        local count = 0
        for _ in pairs(chars or {}) do count = count + 1 end
        n = count + 1
        if create then
            if not chars then
                chars = {}
                p.chars = chars
            end
            chars[key] = n
            charIndex, charAt = n, true
        else
            charIndex, charAt = n, GameTime()
        end
        return n
    end

    function Probe.Lage(fresh)
        local now = GameTime()
        if not fresh and lageText and lageAt == now then return lageText end
        local inside = Core.InInstance and Core.InInstance()
        local text = inside and "i" or "w"
        if Core.InGroup and Core.InGroup() then text = text .. "g" end
        local enc = Invoke("IsEncounterInProgress")
        if enc.missing then enc = Invoke("C_InstanceEncounter.IsEncounterInProgress") end
        if enc.ok and not IsSecret(enc[1]) and enc[1] == true then text = text .. "b" end
        lageText, lageAt = text, now
        return text
    end

    function Probe.Continent(fresh)
        local now = GameTime()
        if not fresh and continentAt == now then return continentID end
        local found
        local continent = Resolve("Enum.UIMapType.Continent") or 2
        local map = Simple("C_Map.GetBestMapForUnit", "player")
        for _ = 1, 10 do
            if type(map) ~= "number" or map <= 0 then break end
            local info = Invoke("C_Map.GetMapInfo", map)
            local t = info.ok and Probe.Tab(info[1]) or nil
            if not t then break end
            if Core.Num(Probe.Field(t, "mapType")) == continent then
                found = map
                break
            end
            map = Core.Num(Probe.Field(t, "parentMapID"))
        end
        continentID, continentAt = found, now
        return found
    end

    -- Prüfwerte der Antworten, die schon in der Ablage stehen: h an den Einträgen, Verweise der Fassung
    -- 2026-11-14-nachprobe (same) und probe.same
    local function DupIndex()
        if dupIndex then return dupIndex end
        dupIndex = {}
        local p = Probe.Data()
        local runs = p and type(p.runs) == "table" and p.runs or {}
        for i = 1, #runs do
            local calls = type(runs[i]) == "table" and runs[i].calls
            for j = 1, type(calls) == "table" and #calls or 0 do
                local call = calls[j]
                local h = type(call) == "table" and (call.h or call.same)
                if type(h) == "string" then dupIndex[h] = true end
            end
        end
        for h in pairs(p and type(p.same) == "table" and p.same or {}) do dupIndex[h] = true end
        return dupIndex
    end

    -- Größe eines neuen Zählers in probe.same (Schlüssel, zwei Zahlen, Klammern – Tiefe 3 wie ein Ereignis)
    Probe.SAME_BYTES = 80

    -- Eintrag ablegen oder nur zählen? → derselbe Eintrag (neu, mit h) | nil: die gleiche Antwort steht schon in der
    -- Ablage oder in dieser Sitzung – dann zählt nur probe.same[h] (n = weitere Male, t = zuletzt gesehen), die
    -- Beschreibung steht beim ersten Mal. Ohne Rückgaben zählt die Art des Ergebnisses (fehlt, Fehler, leer).
    function Probe.Same(entry)
        if not Probe.SAME then return entry end
        local parts = { tostring(entry.id), tostring(entry.fn), tostring(entry.arg), tostring(entry.tag), tostring(entry.n),
            tostring(entry.ok), tostring(entry.err), tostring(entry.has) }
        if entry.r ~= nil then Probe.Canon(entry.r, parts) end
        local h = Probe.Hash(table.concat(parts, "\1"))
        local index = DupIndex()
        if index[h] then
            local p = Store()
            local seen = p.same[h]
            if type(seen) ~= "table" then
                seen = { n = 0 }
                p.same[h] = seen
                p.bytes = p.bytes + Probe.SAME_BYTES
            end
            seen.n = (Core.Num(seen.n) or 0) + 1
            seen.t = ServerTime()
            return nil
        end
        index[h] = true
        entry.h = h
        return entry
    end

    function Probe.ForgetKeys()
        charIndex, charAt, lageText, lageAt, continentID, continentAt, dupIndex = nil, nil, nil, nil, nil, nil, nil
        stamp = nil   -- Build und Sprache beim nächsten Fragen neu (im Spiel wechselt der Build nur mit einem Neustart)
    end
    -- Lage und Kontinent beim nächsten Fragen neu bestimmen (Auto.LageChanged ohne Automatik und Mitschnitt)
    function Probe.ForgetLage()
        lageText, lageAt, continentID, continentAt = nil, nil, nil, nil
    end
end

---------------------------------------------------------------------------
-- Takt: EIN Budget je Bild für alles, was die Probe in Portionen rechnet (Läufe, Mitschrift, Tempo)
---------------------------------------------------------------------------

--[[
    Vorher hatte jede Kette ihr eigenes Budget (ein Lauf 8 ms je Bild, daneben Läufe an Ereignissen, die Mitschrift und
    die Tempo-Messung), und geprüft wurde es nur zwischen ganzen Schritten – ein Schritt mit hunderten Abfragen lief
    in einem Bild durch (Spieltest 14.11.2026: „nur ständiges Ruckeln“). Jetzt:
      ein Budget je Bild      Probe.SLICE_MS Millisekunden und Probe.SLICE_CALLS Abfragen, für alle Aufträge zusammen
      ein Zeitgeber           höchstens ein C_Timer.After(0) steht aus; er arbeitet die Aufträge der Reihe nach ab,
                              eilige (Lauf an einem Ereignis, Kampf, Tempo) zuerst, solange das Budget reicht
      Auftrag                 Tabelle mit :Slice() – rechnet eine Portion und meldet sich mit Takt.Want(auftrag) neu an,
                              wenn noch etwas übrig ist; urgent = true: eilig
      Sofort-Budget           ein Lauf an einem Ereignis rechnet seine erste Portion gleich (das Fenster ist danach wieder
                              zu): das Bild bekommt dafür EINMAL Probe.SLICE_NOW_MS und Probe.SLICE_NOW_CALLS – abzüglich
                              dessen, was in diesem Bild schon gerechnet wurde. Ein zweites Ereignis im selben Bild rechnet
                              nur mit dem Rest; ist keiner da, geht sein Lauf eilig in den Takt. Der Takt selbst rechnet
                              in einem solchen Bild nichts mehr.
    Ein Bild erkennt die Probe an GetTime() (ändert sich je Bild einmal). Gezählt wird die Zeit, die die Probe selbst
    gerechnet hat (Abschnitte zwischen Begin und End) – nicht die Zeit, die im Bild sonst vergeht.
]]
local Takt = {}
Probe.Takt = Takt
-- at: Bild (GetTime); cap: Millisekunden dieses Bilds; used: schon gerechnete; since: Beginn des laufenden Abschnitts;
-- left: Abfragen; now: das Sofort-Budget ist in diesem Bild vergeben
local frame = { at = nil, cap = 0, used = 0, since = nil, left = 0, now = false }
local jobs, armed = {}, false

local function Fresh()
    local now = GameTime()
    if frame.at ~= now then
        frame.at, frame.cap, frame.used, frame.since, frame.left, frame.now = now, Probe.SLICE_MS, 0, nil, Probe.SLICE_CALLS, false
    end
end
local function Spent()
    if frame.left <= 0 then return true end
    local since = frame.since
    return frame.used + (since and (ClockMs() - since) or 0) >= frame.cap
end
local function Use(n) frame.left = frame.left - (n or 1) end
-- Budget dieses Bilds für den Takt (neu, sobald ein neues Bild begonnen hat). → ist noch etwas übrig?
local function Budget()
    Fresh()
    return not frame.now and not Spent()
end
-- Sofort-Budget für die erste Portion eines Laufs an einem Ereignis: je Bild einmal. → ist (noch) etwas davon übrig?
local function Grant()
    Fresh()
    if not frame.now then
        frame.now = true
        frame.cap = Probe.SLICE_NOW_MS
        frame.left = frame.left + Probe.SLICE_NOW_CALLS - Probe.SLICE_CALLS
    end
    return not Spent()
end
-- Abschnitt, in dem die Probe rechnet: seine Dauer zählt zum Budget des Bilds. → true: dieser Aufruf hat ihn begonnen
local function Begin()
    Fresh()
    if frame.since then return false end
    frame.since = ClockMs()
    return true
end
local function End(own)
    if own and frame.since then
        frame.used = frame.used + (ClockMs() - frame.since)
        frame.since = nil
    end
end

local function TaktTick()
    armed = false
    local own = Begin()
    local list = jobs
    jobs = {}
    for i = 1, #list do
        local job = list[i]
        job.wanted = nil
        if not Budget() then
            Takt.Want(job)   -- im nächsten Bild; die Reihenfolge bleibt
        else
            local ok, err = pcall(job.Slice, job)
            if not ok then Core.Error(ADDON, err, "Probe.Takt") end
        end
    end
    End(own)
end

-- Auftrag für das nächste Bild anmelden (jeder höchstens einmal).
function Takt.Want(job)
    if job.wanted then return false end
    job.wanted = true
    local at = #jobs + 1
    if job.urgent then
        at = 1
        while jobs[at] and jobs[at].urgent do at = at + 1 end
    end
    table.insert(jobs, at, job)
    if not armed then
        armed = true
        C_Timer.After(0, TaktTick)
    end
    return true
end

function Takt.Waiting() return #jobs end
-- Rest des Budgets in diesem Bild: Abfragen, Millisekunden
function Takt.Left()
    if frame.at ~= GameTime() then return Probe.SLICE_CALLS, Probe.SLICE_MS end
    local running = frame.since and (ClockMs() - frame.since) or 0
    return math.max(0, frame.left), math.max(0, frame.cap - frame.used - running)
end

---------------------------------------------------------------------------
-- Lauf: Schritte in Portionen, Abfragen einzeln in pcall, warten auf Antworten
---------------------------------------------------------------------------

local Result = {}
Result.__index = Result
function Result:Num(i) return Core.Num(self[i or 1]) end
function Result:Str(i) return Probe.Str(self[i or 1]) end
function Result:Tab(i) return Probe.Tab(self[i or 1]) end
function Result:Field(key, i) return Probe.Field(self[i or 1], key) end
function Result:True(i)
    local value = self[i or 1]
    if IsSecret(value) then return false end
    return value == true
end

local function ArgText(n, args)
    if not n or n == 0 then return nil end
    local parts = {}
    for i = 1, n do
        local value = args[i]
        local kind = type(value)
        if IsSecret(value) then
            parts[i] = "<secret>"
        elseif kind == "string" then
            if #value > 60 or value:find("[%z\1-\31]") then
                parts[i] = ("<Text %d>"):format(#value)
            else
                parts[i] = '"' .. Probe.MaskText(value) .. '"'
            end
        elseif kind == "number" or kind == "boolean" or kind == "nil" then
            parts[i] = tostring(value)
        else
            parts[i] = "<" .. kind .. ">"
        end
    end
    return table.concat(parts, ", ")
end
Probe.ArgText = ArgText

local function ErrText(err)
    if IsSecret(err) then return "secret" end
    return Core.TruncateBytes(Probe.MaskText(tostring(err)), 200)
end

local Run = {}
Run.__index = Run
Probe.RunClass = Run

local current                 -- der laufende Lauf
local runQueue = {}           -- wartende Läufe

-- Ist mit diesem Lauf der Deckel erreicht? Ein Lauf bei voller Ablage (spare: seine Art ist hier neu) darf die Reserve
-- nutzen, bis zum Deckel selbst (Probe.Hard).
function Run:Full()
    return Probe.Over(self.spare == true, #self.calls, self.bytes)
end

-- Zwischen zwei Abfragen: Ist das Budget dieses Bilds verbraucht, pausiert der Schritt hier und macht im nächsten
-- Bild weiter (Run:Advance). Nur im eigenen Schritt des Laufs – eine Antwort, die ein Zeitgeber oder ein Ereignis
-- bringt (Run:Hold), und Abfragen ohne Lauf (Probe.RunClass.Call(nil, …)) pausieren nie.
local function Breathe(run, cost)
    Use(cost)
    local co = run.co
    if co == nil or run.hold > 0 or coroutine.running() ~= co then return end
    if Spent() then coroutine.yield() end
end
namesPause = function(run) Breathe(run, 1) end

-- Abschnitt ohne Pause: fn(run) läuft in einem Stück, auch wenn das Budget des Bilds dabei ausgeht – für Abfragen mit
-- Nebenwirkung, die im selben Bild zurückgestellt werden muss (Sonderproben X3, X4: umstellen, lesen, zurückstellen).
-- undo(run) läuft danach in jedem Fall, auch nach einem Fehler in fn, und ebenfalls ohne Pause; der Fehler wird danach
-- weitergereicht. Weil nichts pausiert, kann weder ein Kampfbeginn noch die volle Ablage dazwischenkommen (beides
-- prüft Run:Advance erst zwischen zwei Portionen).
function Run:Atomic(fn, undo)
    self.hold = self.hold + 1
    local ok, err = pcall(fn, self)
    local okUndo, errUndo = true, nil
    if undo then okUndo, errUndo = pcall(undo, self) end
    self.hold = self.hold - 1
    if not ok then error(err, 0) end
    if not okUndo then error(errUndo, 0) end
end

function Run:Add(entry)
    self.calls[#self.calls + 1] = entry
    -- der Eintrag samt seiner Zeile in der Liste („{ … }, -- [n]“)
    self.bytes = self.bytes + SizeOf(entry, Probe.DEPTH_CALL) + Probe.DEPTH_CALL + 12
    Breathe(self, Probe.ENTRY_COST)
    return entry
end

-- Einmalige Angaben für die nächste Abfrage: Marke (z. B. der Name hinter einer Zahl) und Regeln fürs Maskieren:
-- opts.ret = { [1] = "player", [3] = true }   Rückgabe 1 ist ein Spielername, Rückgabe 3 nur als Länge
-- opts.fields = { name = "friend" }           Feld „name“ ist ein Freundesname (in jeder Tiefe)
-- opts.fields = { name = "unit" }             Feld „name“ gehört zu einer Einheit: lesbar nur neben der GUID eines NPC
-- opts.text = true                            jeder Text dieser Antwort nur als Länge
-- opts.maxFields, opts.samples                mehr Felder bzw. Listen-Beispiele als üblich
function Run:Tag(text)
    self.tag = text
    return self
end
function Run:With(opts)
    if type(opts) == "table" and type(opts.ret) == "table" then
        opts.fields = opts.fields or {}
        for index, rule in pairs(opts.ret) do opts.fields["#" .. index] = rule end
    end
    self.opts = opts
    return self
end

-- Abfrage ohne Eintrag (für Werte, die nur den Weg bestimmen). → Result
-- Auch ohne Lauf brauchbar: Probe.RunClass.Call(nil, "UnitExists", "target").
function Run:Call(path, ...)
    if self ~= nil and self.co ~= nil then Breathe(self, 1) end
    return setmetatable(Invoke(path, ...), Result)
end

function Run:Record(id, name, argText, result)
    local entry = { id = id, fn = name, arg = argText }
    local opts = self.opts
    entry.tag, self.tag, self.opts = self.tag, nil, nil
    if result.missing then
        entry.ok, entry.err = false, "fehlt"
        self.missing = self.missing + 1
    elseif not result.ok then
        entry.ok, entry.err = false, ErrText(result.err)
        self.errors = self.errors + 1
    else
        entry.ok, entry.n = true, result.n
        if result.n > 0 then
            local before = secretsSeen
            entry.r = {}
            for i = 1, math.min(result.n, Probe.MAX_RETURNS) do
                entry.r[i] = Describe(result[i], 0, "#" .. i, opts)
            end
            self.secrets = self.secrets + (secretsSeen - before)
        end
    end
    -- eine gleiche Antwort steht schon da (diese oder eine frühere Sitzung): kein Eintrag, nur der Zähler
    return self:Keep(entry)
end

-- Eintrag ablegen, wenn seine Antwort neu ist (Probe.Same); sonst nur zählen (dup, dk je Probe). → der Eintrag (auch
-- der nicht abgelegte – Run:Val und Run:Note setzen danach noch eine Marke, die dann nirgends steht)
function Run:Keep(entry)
    local kept = Probe.Same(entry)
    if kept then return self:Add(kept) end
    self.dup = self.dup + 1
    local id = tostring(entry.id)
    self.dk[id] = (self.dk[id] or 0) + 1
    Breathe(self, 1)
    return entry
end

-- Abfrage mit Eintrag. → Result (die Rückgaben roh: vor jeder Verwendung über :Num, :Str, :Tab, :Field prüfen)
function Run:Q(id, path, ...)
    local n = select("#", ...)
    local result = setmetatable(Invoke(path, ...), Result)   -- die Pause kommt nach dem Eintrag (Run:Add)
    self:Record(id, type(path) == "string" and path or "<function>", ArgText(n, { ... }), result)
    return result
end

-- Globaler Wert (Enum, Konstante, Text). → der Wert (nil: fehlt)
function Run:Val(id, path)
    local value = Resolve(path)
    if value == nil then
        self:Record(id, path, nil, { ok = false, missing = true })
        return nil
    end
    local entry = self:Record(id, path, nil, { ok = true, n = 1, value })
    entry.g = true
    return value
end

-- Nur: gibt es den Namen, und welcher Art ist er?
function Run:Has(id, path)
    local kind = type(Resolve(path))
    self.tag, self.opts = nil, nil
    if kind == "nil" then self.missing = self.missing + 1 end
    return self:Keep({ id = id, fn = path, has = kind })
end

-- Selbst ermittelte Werte (Zählungen, Aufbau) als Eintrag.
function Run:Note(id, label, ...)
    local n = select("#", ...)
    local values = { ... }
    values.ok, values.n = true, n
    local entry = self:Record(id, label, nil, values)
    entry.note = true
    return entry
end

-- Schritt anhängen: aus einem laufenden Schritt heraus direkt danach, sonst hinten.
function Run:Step(fn)
    if self.insertAt then
        table.insert(self.queue, self.insertAt, fn)
        self.insertAt = self.insertAt + 1
    else
        self.queue[#self.queue + 1] = fn
    end
end

-- Schritt ganz nach vorn (Antwort einer Wartestelle): läuft als Nächstes; was der laufende Schritt danach anhängt,
-- bleibt in seiner Reihenfolge.
function Run:Front(fn)
    table.insert(self.queue, 1, fn)
    if self.insertAt then self.insertAt = self.insertAt + 1 end
end

local function Unwait(run, hold)
    for i = #run.waiting, 1, -1 do
        if run.waiting[i] == hold then table.remove(run.waiting, i) end
    end
end

-- Auf eine Antwort warten: → release(...) hält die Werte fest, cancel(grund) vermerkt den Grund. Nach
-- timeout Sekunden ohne Antwort steht „keine Antwort“ da. onDone(run, beantwortet, ...) läuft als nächster Schritt.
function Run:Hold(id, label, timeout, onDone)
    local run = self
    local hold = { id = id, label = label }
    run.waiting[#run.waiting + 1] = hold
    local function Finish(answered, reason, n, values)
        if hold.done or run.done then return end
        hold.done = true
        Unwait(run, hold)
        -- Die Antwort kann mitten in einem Schritt kommen (Rückruf im selben Bild, womöglich innerhalb von pcall):
        -- ihr Eintrag pausiert nie.
        run.hold = run.hold + 1
        if answered then
            values.ok, values.n = true, n
            run:Record(id, label, nil, values)
        else
            run:Add({ id = id, fn = label, ok = false, err = reason })
            run.silent = run.silent + 1
        end
        run.hold = run.hold - 1
        if onDone then
            run:Front(function(r) onDone(r, answered, unpack(values or {}, 1, n or 0)) end)
        end
        run:Schedule()
    end
    C_Timer.After(timeout or Probe.WAIT, function() Finish(false, "keine Antwort") end)
    return function(...) Finish(true, nil, select("#", ...), { ... }) end, function(reason) Finish(false, reason or "fehlt") end
end

-- Pause: fn(run) läuft nach seconds als nächster Schritt.
function Run:After(seconds, fn)
    local run = self
    local hold = {}
    run.waiting[#run.waiting + 1] = hold
    C_Timer.After(seconds, function()
        if hold.done or run.done then return end
        hold.done = true
        Unwait(run, hold)
        run:Front(fn)
        run:Schedule()
    end)
end

local waitFrame
local waiters = {}   -- Ereignis → { release … }

-- Auf ein Ereignis warten (höchstens timeout Sekunden); die Nutzlast steht als Eintrag „EVENT <Name>“ da.
-- match(...) → true, wenn dieses Ereignis die erwartete Antwort ist (z. B. die Nummer des angefragten Gegenstands);
-- ohne match gilt das erste Ereignis dieses Namens. Die Werte können geheim sein: in match nur über Core.Num/Probe.Str.
function Run:Wait(id, event, onDone, timeout, match)
    local release, cancel = self:Hold(id, "EVENT " .. event, timeout, onDone)
    if not waitFrame then
        waitFrame = CreateFrame("Frame")
        waitFrame:SetScript("OnEvent", function(_, name, ...)
            local list, keep, now = waiters[name], {}, GameTime()
            for i = 1, list and #list or 0 do
                local waiter = list[i]
                local ok, yes = true, true
                if waiter.match then ok, yes = pcall(waiter.match, ...) end
                if not ok or yes then
                    waiter.release(...)
                elseif now < waiter.expires then
                    keep[#keep + 1] = waiter   -- wartet weiter auf seine eigene Antwort
                end
            end
            if #keep > 0 then
                waiters[name] = keep
            else
                waiters[name] = nil
                pcall(waitFrame.UnregisterEvent, waitFrame, name)
            end
        end)
    end
    if not pcall(waitFrame.RegisterEvent, waitFrame, event) then
        cancel("fehlt")
        return false
    end
    waiters[event] = waiters[event] or {}
    table.insert(waiters[event], { release = release, match = match, expires = GameTime() + (timeout or Probe.WAIT) })
    return true
end

local StartNext

-- Erster Schritt eines Laufs, wenn die gründliche Namenssammlung fällig ist: in Portionen (pausiert je Eintrag der
-- Gildenliste, der Freunde und der Battle.net-Freunde), fertig vor der ersten Abfrage des Laufs.
local function NamesStep(run) Probe.CollectNames(false, nil, run) end

function Run:Finish(reason)
    if self.done then return end
    self.done = true
    self.queue, self.waiting, self.co, self.insertAt = {}, {}, nil, nil
    local s = Stamp()
    local count = #self.calls
    -- gefragt: festgehalten oder nur gezählt (gleiche Antwort) – ein Lauf ganz aus gleichen Antworten steht mit seinem
    -- Kopf in der Ablage und zählt für die Grenzen der Automatik (sonst liefe er bei jedem Anlass wieder)
    local asked = count + self.dup
    local also
    for i = 2, self.tally and #self.tally or 0 do
        also = also or {}
        also[#also + 1] = self.tally[i].kind
    end
    local data = { st = self.st, t = self.t, b = s.build, loc = s.locale, proj = s.project, ev = self.ev, ctx = self.ctx,
        s = asked > 0 and Probe.Session() or nil, full = reason == "full" or nil,
        kind = self.kind ~= self.key and self.kind or nil, auto = self.auto and true or nil, also = also,
        ch = asked > 0 and Probe.CharIndex(true) or nil, lg = self.lg, pv = Probe.REV,
        ins = asked > 0 and Store().install or nil, k = self.key ~= nil and self.key ~= self.st and self.key or nil,
        dup = self.dup > 0 and self.dup or nil, dk = self.dup > 0 and self.dk or nil, spare = self.spare or nil }
    -- Kopf des Laufs (ohne die Aufrufe) samt der Zeilen um die Liste „calls“
    local bytes, key, kind, tally = self.bytes + SizeOf(data, Probe.DEPTH_RUN) + 40, self.key, self.kind, self.tally
    data.calls = self.calls
    if asked > 0 then
        pendingEntries, pendingBytes = pendingEntries + count, pendingBytes + bytes
        -- im Kampf bleibt der Lauf im Arbeitsspeicher und kommt bei PLAYER_REGEN_ENABLED in die Ablage
        Core.AfterCombat(function()
            pendingEntries, pendingBytes = math.max(0, pendingEntries - count), math.max(0, pendingBytes - bytes)
            Commit(data, bytes, key, kind, tally)
        end, nil, ADDON)
    end
    self.result = { calls = count, asked = asked, dup = self.dup, errors = self.errors, missing = self.missing,
        secrets = self.secrets, silent = self.silent, full = reason == "full" }
    if not self.quiet then
        ns.Print(L.PROBE_DONE:format(self.title, count, self.errors, self.missing, self.secrets, Probe.StatusText()))
        if self.dup > 0 then ns.Print(L.PROBE_DONE_SAME:format(self.dup)) end
        if reason == "full" then Probe.SayFull() end
        ns.Print(L.PROBE_SAVE_HINT)
    end
    if self.onFinish then pcall(self.onFinish, self) end
    if current == self then current = nil end
    StartNext()
end

-- Eine Portion rechnen: Schritte der Reihe nach, bis das Budget dieses Bilds verbraucht ist. Jeder Schritt läuft als
-- Koroutine und pausiert zwischen zwei Abfragen (Breathe) – so kostet auch ein Schritt mit hunderten Abfragen je Bild
-- nur das Budget. instant: erste Portion eines Laufs an einem Ereignis – das Sofort-Budget des Bilds (Grant), der Rest
-- des Bilds gehört danach dem Spiel.
function Run:Advance(instant)
    if self.done or self.advancing then return end
    if not self.combat and Core.InCombat() then
        -- Station für außerhalb des Kampfes: wartet, statt im Kampf weiterzufragen
        local run = self
        Core.AfterCombat(function() run:Schedule() end, "ezCore.probe.run." .. self.serial, ADDON)
        return
    end
    if instant then
        -- je Bild EIN Sofort-Budget: ein zweites Ereignis im selben Bild rechnet mit dem Rest oder geht eilig in den Takt
        if not Grant() then return self:Schedule() end
    elseif not Budget() then
        return self:Schedule()   -- in diesem Bild hat schon jemand gerechnet
    end
    if not self.t and self:Full() then
        -- schon vor der ersten Abfrage voll (ein Lauf ohne Probe.Run, etwa „nach dem Kampf“ oder am Ereignis):
        -- nichts fragen, nichts ablegen
        return self:Finish("full")
    end
    local own = Begin()
    self.advancing = true
    if not self.t then
        -- Beginn des Laufs: Zeit, Zusammenhang, bekannte Namen. Ziel, Maus und Gruppe sofort; die gründliche Sammlung
        -- (Gilde, Freunde, Battle.net – je Eintrag eine Abfrage) als erster Schritt in Portionen, vor der ersten
        -- Abfrage des Laufs. An einem Ereignis und im Kampf nur Ziel, Maus, Gruppe.
        self.t = ServerTime()
        self.ctx = Probe.Context()
        self.lg = self.lg or Probe.Lage()
        Probe.CollectUnitNames()
        if not self.urgent and Probe.NamesStale() then table.insert(self.queue, 1, NamesStep) end
        Use(4)
    end
    while true do
        local co = self.co
        if not co then
            local step = table.remove(self.queue, 1)
            if not step then break end
            co = coroutine.create(step)
            self.co, self.insertAt = co, 1
            Use(1)
        end
        local ok, err = coroutine.resume(co, self)
        local paused = coroutine.status(co) == "suspended"
        if not paused then
            self.co, self.insertAt = nil, nil
            if not ok then
                self:Add({ id = self.cur or "?", fn = "Schritt", ok = false, err = ErrText(err) })
                self.errors = self.errors + 1
            end
        end
        if self:Full() then
            self.advancing = false
            End(own)
            return self:Finish("full")
        end
        if paused or Spent() then break end
    end
    self.advancing = false
    End(own)
    if not self.co and #self.queue == 0 and #self.waiting == 0 then return self:Finish() end
    if self.co or #self.queue > 0 then self:Schedule() end
end

-- Die nächste Portion im nächsten Bild – über den Takt: höchstens ein Zeitgeber, ein Budget für alle. Auch
-- beantwortete Wartestellen (Hold, After) gehen hier durch: sonst liefe je Antwort eine weitere Kette (Ruckeln).
function Run:Schedule()
    if self.done then return end
    Takt.Want(self)
end
function Run:Slice() self:Advance() end

function StartNext()
    if current then return end
    local run = table.remove(runQueue, 1)
    if not run then
        if Probe.Auto then Probe.Auto.Idle() end   -- nichts läuft mehr: die Automatik darf ihre nächste Station starten
        return
    end
    current = run
    run:Advance()   -- sofort, wenn dieses Bild noch Budget hat; sonst im nächsten
end

function Probe.Running() return current ~= nil, #runQueue end

local runSerial = 0

-- Lauf mit den Proben ids anlegen. opts: quiet, ev (Auslöser), combat (darf im Kampf fragen), title, key, onFinish,
-- now (sofort starten statt einreihen – Abfragen an einem Ereignis; Kampf-Läufe im Kampf starten auch gleich),
-- kind (Art für die Zählung, z. B. die Zielart), auto (von der Automatik gestartet)
function Probe.RunProbes(st, ids, opts)
    opts = opts or {}
    runSerial = runSerial + 1
    local run = setmetatable({ st = st, key = opts.key, title = opts.title or st, calls = {}, queue = {}, waiting = {}, bytes = 0,
        errors = 0, missing = 0, secrets = 0, silent = 0, hold = 0, quiet = opts.quiet, ev = opts.ev, combat = opts.combat,
        onFinish = opts.onFinish, serial = runSerial, kind = opts.kind, auto = opts.auto, tally = opts.tally, lg = opts.lg,
        dup = 0, dk = {}, spare = opts.spare and true or nil }, Run)
    for _, id in ipairs(ids) do
        local fn = Probe.probes[id]
        if type(fn) == "function" then
            run.queue[#run.queue + 1] = function(r)
                r.cur = id
                fn(r)
            end
        end
    end
    if opts.now or (opts.combat and Core.InCombat()) then
        -- eilig: nicht hinter den wartenden Läufen, und im Takt vor ihnen. An einem Ereignis (now) rechnet die erste
        -- Portion sofort mit dem Sofort-Budget des Bilds (je Bild eines); die Kampf-Station teilt sich das Budget des Bilds.
        run.urgent = true
        run:Advance(opts.now and true or false)
        return run
    end
    runQueue[#runQueue + 1] = run
    StartNext()
    return run
end

---------------------------------------------------------------------------
-- Stationen
---------------------------------------------------------------------------

-- def: { st = "B" (Kennbuchstabe in der Ablage), words = { "händler", "merchant" … }, probes = { "B1", … },
--        when = fn(offeneFenster) → passt gerade?, combat = true (darf im Kampf laufen) }
function Probe.AddStation(key, def)
    def.key = key
    def.st = def.st or key
    if not Probe.stations[key] then Probe.stationOrder[#Probe.stationOrder + 1] = key end
    Probe.stations[key] = def
    return def
end

function Probe.StationTitle(key)
    local text = L["PROBE_ST_" .. key]
    if text == "PROBE_ST_" .. key then return key end
    return text
end

-- Wort („händler“, „merchant“, „B“) → Schlüssel
function Probe.FindStation(word)
    word = Core.Trim(word or ""):lower()
    if word == "" then return nil end
    for _, key in ipairs(Probe.stationOrder) do
        if key:lower() == word then return key end
        for _, w in ipairs(Probe.stations[key].words or {}) do
            if w == word then return key end
        end
    end
    return nil
end

-- Welche Stationen passen gerade? Im Kampf nur die Kampf-Station; ohne Fenster, Ziel und Gruppe „allein“.
function Probe.Detect()
    if Core.InCombat() then return { "G" } end
    local open = Probe.OpenWindows()
    local list, main = {}, 0
    for _, key in ipairs(Probe.stationOrder) do
        local station = Probe.stations[key]
        if type(station.when) == "function" then
            local ok, yes = pcall(station.when, open)
            if ok and yes then
                list[#list + 1] = key
                if not station.extra then main = main + 1 end
            end
        end
    end
    -- „allein“, wenn sonst nichts passt – eine Station für Spielarten (extra: Spielobjekt, Vignette) verdrängt sie nicht
    if main == 0 then table.insert(list, 1, "A") end
    return list
end

-- Eine Station laufen lassen. → true | false, Grund
function Probe.Run(key, opts)
    local station = Probe.stations[key]
    if not station then return false, "unknown" end
    opts = opts or {}
    -- Arten des Laufs: beim Ziel die Zielart (Probe.TargetKind), sonst die Station samt ihren Spielarten (Probe.KindOf:
    -- Händler mit begrenztem Vorrat, Klassenlehrer, Beute aus einem Objekt …) – so zählt auch ein Lauf von Hand für
    -- die Automatik, je Charakter und Lage (Probe.Auto.Tally)
    local kinds = opts.kinds
    if kinds == nil and Probe.Auto then kinds = Probe.Auto.KindsNow(key) end
    -- volle Ablage: nur noch, was hier neu ist (eine Art ohne Lauf in diesem Bereich), und nur bis zur Reserve
    local spare = nil
    if Probe.Full() then
        local hard = Probe.Hard()
        if hard or not (Probe.Auto and Probe.Auto.IsNew(kinds)) then
            -- von Hand (Befehl, Knopf): immer eine Antwort, auch wenn die Meldung „voll“ in dieser Sitzung schon kam
            if not Probe.SayFull(opts.auto) and not opts.auto and not opts.quiet then
                ns.Print((hard and L.PROBE_HARD_SKIP or L.PROBE_FULL_SKIP):format(Probe.StationTitle(key)))
            end
            return false, "full"
        end
        spare = true
    end
    if Core.InCombat() and not station.combat then
        ns.Print(L.PROBE_COMBAT_LATER:format(Probe.StationTitle(key)))
        Core.AfterCombat(function() Probe.Run(key, opts) end, "ezCore.probe.station." .. key, ADDON)
        return false, "combat"
    end
    if not opts.quiet then ns.Print(L.PROBE_START:format(Probe.StationTitle(key))) end
    local kind = opts.kind or (kinds and kinds[1])
    local tally = opts.tally or (Probe.Auto and kinds and Probe.Auto.Tally(kinds)) or nil
    if Probe.Auto then Probe.Auto.Ran(key) end   -- derselbe Anlass (dasselbe offene Fenster) löst die Station nicht noch einmal aus
    local after, done = station.after, opts.done
    Probe.RunProbes(station.st, station.probes, { key = key, kind = kind or key, auto = opts.auto, title = Probe.StationTitle(key),
        tally = tally, lg = Probe.Lage(), spare = spare,
        combat = station.combat, quiet = opts.quiet, ev = opts.ev, onFinish = (after or done) and function(run)
            if after then pcall(after, run) end
            if done then
                local ok, err = pcall(done, run)
                if not ok then Core.Error(ADDON, err, "Probe.Auto") end
            end
        end or nil })
    return true
end

-- Knopf „Probe an dieser Stelle“: alle Stationen, die gerade passen. → Liste der Schlüssel
function Probe.Here()
    local list = Probe.Detect()
    for _, key in ipairs(list) do Probe.Run(key) end
    return list
end

---------------------------------------------------------------------------
-- Mitschnitt: Ereignisse mit der Form ihrer Nutzlast
---------------------------------------------------------------------------

local Record = {}
Probe.Record = Record

-- Ereignisse der Stationen (docs/datenprobe.md). Unbekannte Namen überspringt der Client (pcall).
Record.EVENTS = {
    "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT",
    "MERCHANT_SHOW", "MERCHANT_UPDATE", "MERCHANT_FILTER_ITEM_UPDATE", "MERCHANT_CLOSED",
    "TRAINER_SHOW", "TRAINER_UPDATE", "TRAINER_SERVICE_INFO_NAME_UPDATE", "LEARNED_SPELL_IN_SKILL_LINE", "SPELLS_CHANGED",
    "NEW_RECIPE_LEARNED", "CONFIRM_TALENT_WIPE",
    "MAIL_SHOW", "MAIL_INBOX_UPDATE", "BANKFRAME_OPENED", "BANKFRAME_CLOSED",
    "AUCTION_HOUSE_AUCTION_CREATED", "AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", "AUCTION_HOUSE_SHOW_NOTIFICATION",
    "AUCTION_HOUSE_PURCHASE_COMPLETED", "ITEM_PURCHASED", "COMMODITY_PURCHASED", "AUCTION_CANCELED",
    "AUCTION_HOUSE_ITEM_DELIVERY_DELAY_UPDATE", "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED", "AUCTION_HOUSE_SCRIPT_DEPRECATED",
    "NAME_PLATE_UNIT_ADDED", "ADDON_RESTRICTION_STATE_CHANGED", "SPELL_UPDATE_COOLDOWN",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "LOOT_READY", "LOOT_OPENED", "LOOT_SLOT_CLEARED", "LOOT_CLOSED",
    "UNIT_DIED", "PARTY_KILL", "UNIT_LOOT", "PLAYER_TARGET_DIED", "CHAT_MSG_COMBAT_XP_GAIN", "CHAT_MSG_LOOT", "CHAT_MSG_MONEY",
    "CHAT_MSG_SKILL", "ITEM_PUSH", "PLAYER_MONEY", "CURRENCY_DISPLAY_UPDATE",
    "GROUP_JOINED", "START_LOOT_ROLL", "LOOT_ITEM_ROLL_WON", "ENCOUNTER_LOOT_RECEIVED", "LOOT_HISTORY_UPDATE_ENCOUNTER",
    "TRADE_SKILL_SHOW", "TRADE_SKILL_CRAFT_BEGIN", "TRADE_SKILL_ITEM_CRAFTED_RESULT", "SKILL_LINES_CHANGED", "ITEM_LOCKED",
    "PLAYER_SOFT_INTERACT_CHANGED", "OBJECT_ENTERED_AOI", "OBJECT_LEFT_AOI",
    "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_LOOT_RECEIVED",
    "QUEST_REMOVED", "UPDATE_FACTION", "FACTION_STANDING_CHANGED", "GOSSIP_SHOW", "QUEST_GREETING", "QUESTLINE_UPDATE",
    "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "DYNAMIC_GOSSIP_POI_UPDATED",
    "TAXIMAP_OPENED", "TAXIMAP_CLOSED", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED",
    "PLAYER_MAP_CHANGED", "ZONE_CHANGED_NEW_AREA", "ENCOUNTER_START", "ENCOUNTER_END", "BOSS_KILL",
    "VIGNETTE_MINIMAP_UPDATED", "VIGNETTES_UPDATED", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
    "CALENDAR_UPDATE_EVENT_LIST", "UPDATE_INSTANCE_INFO", "INSPECT_READY", "SAVED_VARIABLES_TOO_LARGE",
}
-- Zauber-Ereignisse nur für den eigenen Charakter und das Ziel
Record.UNIT_EVENTS = {
    "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_INTERRUPTIBLE",
    -- Ende des Kanalisierens (Welle 23a, A3): Angeln endet so – Fang, Abbruch oder Ablauf (Paket 14e)
    "UNIT_SPELLCAST_CHANNEL_STOP",
}
-- nur zählen (Flut-Gefahr)
Record.COUNT_ONLY = { OBJECT_ENTERED_AOI = true, OBJECT_LEFT_AOI = true }
-- Chat-Ereignisse, deren Text eine Meldung des Spiels ist (kein Spieler-Chat): Text bleibt, Namen maskiert
Record.SYSTEM_TEXT = { CHAT_MSG_LOOT = true, CHAT_MSG_MONEY = true, CHAT_MSG_COMBAT_XP_GAIN = true, CHAT_MSG_SKILL = true }
-- Ereignisse, die an fester Stelle einen Spielernamen tragen: Ereignis → Stellen
Record.NAME_ARGS = { ENCOUNTER_LOOT_RECEIVED = { 5 } }
-- Ereignisse, die an fester Stelle den Namen des Ziels tragen (Spieler, NPC oder Objekt): bleibt nur lesbar, wenn er
-- nachweislich kein Spieler ist (Record.KnownNonPlayer)
Record.TARGET_ARGS = { UNIT_SPELLCAST_SENT = 2 }
-- Ereignisse, bei denen ein Wert der Nutzlast das Beispiel unterscheidet (Zauber, Art des Fensters): Stelle des Werts.
-- Davon je Wert Probe.DISTINCT_SAMPLES Beispiele – sonst verdrängten acht Zauber im Kampf das Sammeln und Herstellen.
Record.DISTINCT = { UNIT_SPELLCAST_SENT = 4, UNIT_SPELLCAST_START = 3, UNIT_SPELLCAST_SUCCEEDED = 3, UNIT_SPELLCAST_FAILED = 3,
    UNIT_SPELLCAST_INTERRUPTED = 3, UNIT_SPELLCAST_CHANNEL_START = 3, UNIT_SPELLCAST_CHANNEL_STOP = 3,
    PLAYER_INTERACTION_MANAGER_FRAME_SHOW = 1,
    PLAYER_INTERACTION_MANAGER_FRAME_HIDE = 1 }

local recFrame
local recording, recStarted = false, 0
-- Die drei Zähler der Beispiele gelten je Lage (Probe.Lage: Freiland, Instanz, Gruppe, Boss) – recLage[lage] hält sie,
-- recSeen, recValues, recDistinct zeigen auf die der jetzigen Lage (Record.SetLage). So bekommt ein Dungeon, eine
-- Gruppe im Kampf oder ein Boss eigene Beispiele, auch wenn das Freiland sie schon voll hat – mindestens eines auch dann,
-- wenn der Deckel über alle Lagen erreicht ist (Record.Capped).
local recLage = { now = "w", total = {} }
local recSeen = {}        -- Ereignis → festgehaltene Beispiele unter dem Namen (in diesem Mitschnitt bzw. der Ablage)
local recValues = {}      -- Ereignis → { Unterscheidungswert → festgehaltene Beispiele } (Record.DISTINCT)
local recDistinct = {}    -- Ereignis → Zahl der verschiedenen Werte in diesem Mitschnitt
local recLast = {}        -- Ereignis → Zeit des letzten Beispiels unter dem Namen (Drossel, Probe.SAMPLE_GAP)
-- recLage.total: Ereignis → festgehaltene Beispiele über alle Lagen (mit der Automatik samt denen in der Ablage –
-- Deckel je Art: Probe.EVENT_TOTAL bzw. Probe.EVENT_TOTAL_DISTINCT, danach nur gezählt)
local recQuiet = {}       -- Ereignis → true: nur noch gezählt (Beispiele voll, löst nichts aus)
local recMuted = {}       -- Ereignis → true: in diesem Mitschnitt abgemeldet
local recNarrow = false   -- die Automatik ist fertig: nur noch Ereignisse, an denen etwas fehlt, bleiben angemeldet
local recMutedNew = {}    -- abgemeldet, in der Ablage noch nicht vermerkt
local recCapSaid = false  -- „ab jetzt wird nur noch gezählt“ schon gemeldet
local recAuto = {}        -- Ereignis → ausgelöste Abfrage-Läufe in diesem Mitschnitt
local recBuffer = {}      -- im Kampf gesammelte Einträge
local recCounts = {}      -- noch nicht in der Ablage: Ereignis → Anzahl (im Kampf, oder solange die Ablage fehlt)
local liveCounts          -- probe.counts der Ablage – das zählende Ereignis schreibt außerhalb des Kampfes direkt hinein
local recStats = { events = 0, kept = 0, runs = 0, muted = 0 }
local recMissing = {}
local recUnit = {}        -- Ereignis → true: mit RegisterUnitEvent angemeldet (Record.UNIT_EVENTS)
for _, event in ipairs(Record.UNIT_EVENTS) do recUnit[event] = true end

function Record.Running() return recording, recording and (GameTime() - recStarted) or 0 end
-- Hat dieses Ereignis seinen Deckel über alle Lagen erreicht? → true: nur noch zählen
function Record.TotalFull(event)
    local cap = Record.DISTINCT[event] and Probe.EVENT_TOTAL_DISTINCT or Probe.EVENT_TOTAL
    return (recLage.total[event] or 0) >= cap
end
-- Hat dieses Ereignis in der jetzigen Lage schon ein Beispiel (unter dem Namen oder einem Unterscheidungswert)?
function Record.LageHas(event)
    if (recSeen[event] or 0) > 0 then return true end
    local values = recValues[event]
    if values then
        for _, n in pairs(values) do
            if n > 0 then return true end
        end
    end
    return false
end
-- Deckel über alle Lagen – das erste Beispiel einer Lage zählt nicht dagegen: Ein Dungeon, eine Gruppe im Kampf oder ein
-- Boss bekommt so immer eines, auch wenn Freiland und Stadt den Deckel schon gefüllt haben (bei 6 Lagen höchstens 6 mehr).
function Record.Capped(event) return Record.TotalFull(event) and Record.LageHas(event) end
function Record.Total(event) return recLage.total[event] or 0 end
function Record.Stats() return recStats end
-- Wird das Ereignis nur noch gezählt? Ist es abgemeldet? Hört der Mitschnitt nur noch auf Offenes (Record.Narrow)?
function Record.Quiet(event) return recQuiet[event] == true end
function Record.Muted(event) return recMuted[event] == true end
function Record.Narrowed() return recording and recNarrow end

-- Zähler der Beispiele einer Lage (angelegt, wenn es sie noch nicht gibt), und die Lage, deren Zähler gerade gelten.
function Record.LageSet(lg)
    local sets = recLage.sets
    if not sets then
        sets = {}
        recLage.sets = sets
    end
    local set = sets[lg]
    if not set then
        set = { seen = {}, values = {}, distinct = {} }
        sets[lg] = set
    end
    return set
end
function Record.UseLage(lg)
    recLage.now = lg
    local set = Record.LageSet(lg)
    recSeen, recValues, recDistinct = set.seen, set.values, set.distinct
end
function Record.Lage() return recLage.now end

-- Die Lage hat sich geändert (Instanz betreten, Gruppe, Bosskampf): ab jetzt zählen die Beispiele der neuen Lage.
-- Was dort noch fehlt, wird wieder festgehalten – auch ein Ereignis, das bisher nur noch gezählt oder abgemeldet war
-- (Record.Rearm; die Automatik meldet danach ab, was auch in dieser Lage nichts mehr bringt). → true, wenn sie wechselte
function Record.SetLage(lg)
    if type(lg) ~= "string" or lg == recLage.now then return false end
    Record.UseLage(lg)
    if recording then
        if recNarrow then Record.Rearm() else recQuiet = {} end
    end
    return true
end

-- Gesammeltes in die Ablage: Zähler, Beispiele, Abmeldungen. Legt nichts neu an (keine Tabelle je Ereignis).
local function FlushEvents()
    local kept = #recBuffer
    if kept == 0 and next(recCounts) == nil and #recMutedNew == 0 then return end
    local p = Store()
    for event, n in pairs(recCounts) do
        p.counts[event] = (Core.Num(p.counts[event]) or 0) + n
        recCounts[event] = nil
    end
    for i = 1, kept do
        local item = recBuffer[i]
        recBuffer[i] = nil
        p.events[#p.events + 1] = item
        p.entries = p.entries + 1
        p.bytes = p.bytes + SizeOf(item, Probe.DEPTH_EVENT) + Probe.DEPTH_EVENT + 12
    end
    pendingEntries = math.max(0, pendingEntries - kept)
    if #recMutedNew > 0 then
        if type(p.muted) ~= "table" then p.muted = {} end
        for i = #recMutedNew, 1, -1 do
            p.muted[recMutedNew[i]] = true
            recMutedNew[i] = nil
        end
    end
    liveCounts = p.counts
    if kept > 0 and statusChanged then statusChanged() end
end

-- Ist name nachweislich kein Spieler? Ja, wenn eine Einheit so heißt, die weder Spieler noch von einem Spieler
-- gesteuert ist (freundlicher NPC, Gegner), oder wenn unter der Maus ein Objekt mit diesem Namen liegt (Erzader, Kraut,
-- Truhe – Blizzards Tooltip nennt die Art). Alles andere gilt als Spieler: lieber „Kupferader“ verloren als ein Name da.
local PROOF_UNITS = { "target", "mouseover", "softinteract", "softenemy", "softfriend", "npc", "focus" }
function Record.KnownNonPlayer(name)
    for _, unit in ipairs(PROOF_UNITS) do
        local unitName = Invoke("UnitName", unit)
        if unitName.ok and Probe.Str(unitName[1]) == name then
            local isPlayer, controlled = Invoke("UnitIsPlayer", unit), Invoke("UnitPlayerControlled", unit)
            if isPlayer.ok and not IsSecret(isPlayer[1]) and isPlayer[1] == false
                and controlled.ok and not IsSecret(controlled[1]) and controlled[1] == false then
                return true
            end
        end
    end
    local objectType = Resolve("Enum.TooltipDataType.Object")
    local tip = Invoke("C_TooltipInfo.GetWorldCursor")
    local data = tip.ok and Probe.Tab(tip[1]) or nil
    if data and objectType ~= nil and Core.Num(Probe.Field(data, "type")) == objectType then
        local first = Probe.Field(Probe.Field(data, "lines"), 1)
        if Probe.Str(Probe.Field(first, "leftText")) == name then return true end
    end
    return false
end

-- Nutzlast beschreiben. Chat-Ereignisse: Namen (Werte 2 und 5) als Pseudonym, Spieler-Chat nie als Text.
local function DescribeEvent(event, n, args)
    local list = {}
    local chat = event:find("^CHAT_MSG_") ~= nil
    local keep = Record.SYSTEM_TEXT[event]
    local target = Record.TARGET_ARGS[event]
    local named = {}
    if chat then named[2], named[5] = true, true end
    for _, index in ipairs(Record.NAME_ARGS[event] or {}) do named[index] = true end
    -- zuerst alle Namen anmelden (der Reihe nach: „Name-Realm“ vor „Name“ ergibt dasselbe Pseudonym), dann beschreiben
    for index = 1, math.min(n, Probe.MAX_RETURNS) do
        if named[index] then Probe.Private(args[index], "player") end
    end
    for i = 1, math.min(n, Probe.MAX_RETURNS) do
        local value = args[i]
        if named[i] and not IsSecret(value) and type(value) == "string" and value ~= "" then
            list[i] = { k = "string", len = #value, v = Probe.Private(value, "player") or "<Text>" }
        elseif target == i and not IsSecret(value) and type(value) == "string" and value ~= "" then
            -- Name des Ziels: bekannter Spieler » Pseudonym; nachweislich NPC oder Objekt » bleibt; sonst nur die Länge
            -- (nicht anmelden: wäre es doch eine „Kupferader“, träfe das Pseudonym danach jeden Text mit diesem Wort)
            local known = Probe.Known(value)
            if known then
                list[i] = { k = "string", len = #value, v = known }
            elseif Record.KnownNonPlayer(value) then
                list[i] = Describe(value, 0, nil, nil)
            else
                list[i] = { k = "string", len = #value, v = "<Name>" }
            end
        elseif chat and not IsSecret(value) and type(value) == "string" and value ~= "" then
            if keep and i == 1 then
                list[i] = Describe(value, 0, nil, nil)
            elseif i == 12 then
                list[i] = Describe(value, 0, nil, nil)       -- GUID: der Filter lässt nur den Aufbau stehen
            else
                list[i] = { k = "string", len = #value, v = "<Text>" }
            end
        else
            list[i] = Describe(value, 0, nil, nil)
        end
    end
    return list
end

-- Wo zählen die Beispiele dieses Ereignisses, und wie viele darf es davon geben? → Zähltabelle, Schlüssel, Grenze
-- (je Unterscheidungswert eine eigene Tabelle je Ereignis – kein zusammengesetzter Text je Ereignis)
local function SampleSlot(event, ...)
    local index = Record.DISTINCT[event]
    if index then
        local value = select(index, ...)
        local mark
        if IsSecret(value) then
            mark = "secret"
        elseif type(value) == "number" or type(value) == "string" then
            mark = value
        end
        if mark ~= nil then
            local values = recValues[event]
            if not values then
                values = {}
                recValues[event] = values
            end
            if values[mark] ~= nil then return values, mark, Probe.DISTINCT_SAMPLES end
            local distinct = recDistinct[event] or 0
            if distinct < Probe.DISTINCT_MAX then
                recDistinct[event] = distinct + 1
                values[mark] = 0
                return values, mark, Probe.DISTINCT_SAMPLES
            end
        end
    end
    return recSeen, event, Probe.EVENT_SAMPLES
end

-- Kann dieses Ereignis noch eine Abfrage auslösen (Probe.autoProbes)? Mit der Automatik gilt deren Grenze je Ereignis.
local function AutoOpen(event)
    local auto = Probe.autoProbes[event]
    if not auto then return false end
    if auto.max ~= nil and (recAuto[event] or 0) >= auto.max then return false end
    if Probe.Auto and Probe.Auto.Active() then return Probe.Auto.EventOpen(event) end
    return true
end

-- Sind die Beispiele dieses Ereignisses voll, und löst es nichts mehr aus? Dann gibt es an ihm nichts mehr zu tun.
local function Settled(event)
    if AutoOpen(event) then return false end
    if recStats.kept >= Probe.MAX_EVENTS or Record.COUNT_ONLY[event] then return true end
    if Record.Capped(event) then return true end
    if (recSeen[event] or 0) < Probe.EVENT_SAMPLES then return false end
    return not Record.DISTINCT[event] or (recDistinct[event] or 0) >= Probe.DISTINCT_MAX
end

local function Register(event)
    if recUnit[event] and type(recFrame.RegisterUnitEvent) == "function"
        and pcall(recFrame.RegisterUnitEvent, recFrame, event, "player", "target") then
        return true
    end
    return (pcall(recFrame.RegisterEvent, recFrame, event))
end

-- Ereignis abmelden (nur, wenn der Mitschnitt nur noch auf Offenes hört – Record.Narrow): Beispiele voll, löst nichts
-- mehr aus. Die Zahl in counts ist ab hier eine Untergrenze (Ablage: muted; der Aufrufer schreibt sie mit FlushEvents).
local function Mute(event)
    recQuiet[event] = nil
    recMuted[event] = true
    recMutedNew[#recMutedNew + 1] = event
    recStats.muted = recStats.muted + 1
    if recFrame then pcall(recFrame.UnregisterEvent, recFrame, event) end
end

-- Beispiele der Ablage auf die Grenzen anrechnen (CarrySamples, unten) – recLage.carried: schon geschehen (die Automatik
-- beim Start; ein Mitschnitt von Hand, sobald die Ablage voll ist, sonst legte er je Sitzung wieder erste Beispiele ab)
local CarrySamples

local function OnRecordEvent(_, event, ...)
    if not recording then return end
    recStats.events = recStats.events + 1
    if recQuiet[event] then
        -- Beispiele voll, löst nichts mehr aus: nur zählen (kein Beschreiben, kein Maskieren, keine neue Tabelle) –
        -- außerhalb des Kampfes direkt in der Ablage, sonst im Arbeitsspeicher
        local db = Core.db
        local p = type(db) == "table" and db.probe or nil
        local counts = type(p) == "table" and p.counts or nil
        if counts ~= nil and counts == liveCounts and not Core.InCombat() then
            local n = counts[event]
            counts[event] = (type(n) == "number" and n or 0) + 1
        else
            recCounts[event] = (recCounts[event] or 0) + 1
        end
        return
    end
    local inCombat = Core.InCombat()
    recCounts[event] = (recCounts[event] or 0) + 1
    -- volle Ablage: der Mitschnitt läuft weiter (die Automatik auch) – er zählt, und festgehalten wird nur noch Neues:
    -- ein Beispiel eines Ereignisses, das in dieser Lage noch keines hat, eine Abfrage am Ereignis, deren Art hier noch
    -- nie lief (Auto.AllowEvent). Ist auch die Reserve voll (Probe.Hard), nur noch zählen.
    local full = Probe.Full()
    local hard = full and Probe.Hard()
    if full then
        Probe.SayFull(Probe.Auto and Probe.Auto.Active())
        if not recLage.carried then
            recLage.carried = true
            pcall(CarrySamples)
        end
    end
    -- Abfragen, die an diesem Ereignis hängen (Beute, Questfenster …): sofort, das Fenster ist gleich wieder zu
    local auto = Probe.autoProbes[event]
    local autoOn = Probe.Auto and Probe.Auto.Active()
    -- Mit der Automatik: nicht doppelt zu ihrer Station und je Ereignis höchstens Auto.LIMIT.event Läufe über alle Sitzungen
    if auto and not hard and (not full or autoOn) and (auto.combat or not inCombat)
        and (auto.max == nil or (recAuto[event] or 0) < auto.max)
        and (not autoOn or Probe.Auto.AllowEvent(event)) then
        recAuto[event] = (recAuto[event] or 0) + 1
        recStats.runs = recStats.runs + 1
        local station = Probe.stations[auto.station]
        Probe.RunProbes(station and station.st or auto.station, auto.ids, { quiet = true, ev = event, combat = auto.combat,
            now = true, title = Probe.StationTitle(auto.station), spare = full or nil })
    end
    if not Record.COUNT_ONLY[event] then
        local seen, key, limit = SampleSlot(event, ...)
        local n = seen[key] or 0
        local now = GameTime()
        if full and (hard or n > 0) then limit = 0 end   -- voll: nur ein erstes Beispiel je Lage, und nur bis zur Reserve
        if n >= limit or Record.Capped(event) then
            -- voll: nur gezählt
        elseif recStats.kept >= Probe.MAX_EVENTS then
            -- Deckel dieses Mitschnitts: einmal sagen, weiter zählen
            if not recCapSaid then
                recCapSaid = true
                ns.Print(L.PROBE_RECORD_CAP:format(Probe.MAX_EVENTS))
            end
        elseif seen == recSeen and recLast[event] ~= nil and now >= recLast[event] and now - recLast[event] < Probe.SAMPLE_GAP then
            -- Drossel: ein häufiges Ereignis liefert höchstens ein Beispiel je Probe.SAMPLE_GAP Sekunden, dazwischen
            -- wird es nur gezählt (die Beispiele verteilen sich so auch über die Zeit statt über einen Schwall)
        else
            seen[key] = n + 1
            recLage.total[event] = (recLage.total[event] or 0) + 1
            if seen == recSeen then recLast[event] = now end
            Probe.CollectNames(false, Probe.NAMES_EVERY_EVENT)   -- gründlich selten; Ziel, Maus und Gruppe jedes Mal
            local count = select("#", ...)
            local ok, described = pcall(DescribeEvent, event, count, { ... })
            local s = Stamp()
            local entry = { t = ServerTime(), gt = math.floor(now * 1000 + 0.5) / 1000, e = event, n = count,
                a = ok and described or nil, c = inCombat and true or nil, err = not ok and ErrText(described) or nil,
                b = s.build, loc = s.locale, proj = s.project, s = Probe.Session(), lg = recLage.now }
            recBuffer[#recBuffer + 1] = entry
            pendingEntries = pendingEntries + 1
            recStats.kept = recStats.kept + 1
        end
    end
    -- An diesem Ereignis gibt es nichts mehr zu holen: ab dem nächsten Mal nur noch der Zähler (die Zahl bleibt genau).
    -- Hört der Mitschnitt nur noch auf Offenes (die Automatik ist fertig), wird es stattdessen abgemeldet.
    -- Bei voller Ablage nur noch zählen, sobald das Ereignis hier ein Beispiel hat (mehr kommt nicht dazu) – nicht
    -- abmelden: Die Zahl bleibt genau.
    if recording and Settled(event) then
        if recNarrow then Mute(event) else recQuiet[event] = true end
    elseif recording and full and not AutoOpen(event) and (recSeen[event] or 0) > 0 then
        recQuiet[event] = true
    end
    if not inCombat then FlushEvents() end
end

-- Beispiele, die schon in der Ablage stehen, auf die Grenzen des neuen Mitschnitts anrechnen (Automatik: die Grenze
-- je Ereignis gilt dann über alle Sitzungen, sonst liefe die Probe mit jedem Spielstart weiter voll). Bei voller Ablage
-- auch für einen Mitschnitt von Hand (OnRecordEvent).
function CarrySamples()
    local p = Probe.Data()
    local events = p and type(p.events) == "table" and p.events or {}
    local now = recLage.now
    for i = 1, #events do
        local e = events[i]
        local name = type(e) == "table" and e.e
        if type(name) == "string" then
            -- je Lage (Beispiele ohne Lage stammen aus der Fassung vor der Nachprobe: Freiland)
            Record.UseLage(type(e.lg) == "string" and e.lg or "w")
            local index = Record.DISTINCT[name]
            local d = index and type(e.a) == "table" and e.a[index] or nil
            local mark
            if type(d) == "table" then
                if d.k == "secret" then
                    mark = "secret"
                elseif (d.k == "number" or d.k == "string") and d.v ~= nil then
                    mark = d.v
                end
            end
            recLage.total[name] = (recLage.total[name] or 0) + 1
            if mark ~= nil then
                local values = recValues[name]
                if not values then
                    values = {}
                    recValues[name] = values
                end
                if values[mark] == nil then recDistinct[name] = (recDistinct[name] or 0) + 1 end
                values[mark] = (values[mark] or 0) + 1
            else
                recSeen[name] = (recSeen[name] or 0) + 1
            end
        end
    end
    Record.UseLage(now)
end

-- opts (Automatik): quiet = keine Chatzeile, carry = schon Festgehaltenes zählt für die Grenzen je Ereignis mit,
-- narrow = nur Ereignisse anmelden, an denen noch etwas fehlt (die Automatik ist fertig – Record.Narrow)
function Record.Start(opts)
    opts = type(opts) == "table" and opts or {}
    if recording then return false end
    -- volle Ablage: der Mitschnitt läuft trotzdem – er zählt und hält nur Neues fest (OnRecordEvent)
    if Probe.Full() then Probe.SayFull(opts.carry == true) end
    if not recFrame then
        recFrame = CreateFrame("Frame")
        recFrame:SetScript("OnEvent", OnRecordEvent)
    end
    recording, recStarted, recAuto, recCapSaid = true, GameTime(), {}, false
    recLast, recQuiet, recMuted = {}, {}, {}
    recLage.sets, recLage.total = {}, {}
    Record.UseLage(Probe.Lage(true))
    recStats.events, recStats.kept, recStats.runs, recStats.muted = 0, 0, 0, 0
    Record.auto = opts.carry == true   -- von der Automatik gestartet (sie schaltet nur ihren eigenen Mitschnitt wieder aus)
    recNarrow = opts.narrow == true
    local muted
    recLage.carried = opts.carry == true
    if opts.carry then
        pcall(CarrySamples)
        recCapSaid = true              -- die Automatik meldet den Deckel eines Mitschnitts nicht
        local p = Probe.Data()
        muted = p and type(p.muted) == "table" and p.muted or nil
    end
    recMissing = {}
    local registered = 0
    for _, list in ipairs({ Record.EVENTS, Record.UNIT_EVENTS }) do
        for _, event in ipairs(list) do
            if recNarrow and Settled(event) then
                -- die Automatik ist fertig und an diesem Ereignis fehlt nichts mehr: gar nicht erst anmelden
                recMuted[event] = true
                recStats.muted = recStats.muted + 1
                if not (muted and muted[event] == true) then recMutedNew[#recMutedNew + 1] = event end
            elseif Register(event) then
                registered = registered + 1
            else
                recMissing[#recMissing + 1] = event
            end
        end
    end
    Probe.CollectNames(true)
    -- Ereignisse, die dieser Client nicht kennt: als Antwort festhalten
    if #recMissing > 0 then
        Core.AfterCombat(function() Store().noEvent = recMissing end, nil, ADDON)
    end
    if #recMutedNew > 0 then Core.AfterCombat(FlushEvents, nil, ADDON) end
    if not opts.quiet then ns.Print(L.PROBE_RECORD_ON:format(registered)) end
    if statusChanged then statusChanged() end
    return true
end

-- Die Automatik hat alle Arten der Stationen erfasst: Der Mitschnitt hört ab jetzt nur noch auf Ereignisse, an denen
-- etwas fehlt – Beispiele (ein Ereignis, das noch nie eintrat, hat keines) oder eine Abfrage, die es noch auslösen
-- darf (Probe.autoProbes: Bosskampf, Würfeln …). Alles andere wird abgemeldet, sofort und später, sobald es so weit ist.
-- Ein Ereignis, das nicht eintritt, kostet nichts. → true, wenn der Mitschnitt läuft
function Record.Narrow()
    if not recording or not recFrame then return false end
    recNarrow = true
    for _, list in ipairs({ Record.EVENTS, Record.UNIT_EVENTS }) do
        for _, event in ipairs(list) do
            if not recMuted[event] and Settled(event) then Mute(event) end
        end
    end
    Core.AfterCombat(FlushEvents, nil, ADDON)
    if statusChanged then statusChanged() end
    return true
end

-- Alle abgemeldeten Ereignisse wieder anmelden und neu einstufen – wenn sich ändert, was ein Ereignis auslösen darf
-- (die Automatik ist aus: ihre Grenze je Ereignis gilt für einen Mitschnitt von Hand nicht mehr). → true, wenn er läuft
function Record.Rearm()
    if not recording or not recFrame then return false end
    for event in pairs(recMuted) do Register(event) end
    recMuted, recQuiet, recNarrow = {}, {}, false
    return true
end

-- Ereignisse des Mitschnitts, die noch nie eingetreten sind (in keiner Sitzung gezählt) – ohne die, die dieser Client
-- nicht kennt. → Liste der Namen (sortiert), davon die mit eigener Abfrage (Probe.autoProbes)
function Record.Unseen()
    local p = Probe.Data()
    local counts = p and type(p.counts) == "table" and p.counts or {}
    local unknown = {}
    for _, event in ipairs(recMissing) do unknown[event] = true end
    for _, event in ipairs(p and type(p.noEvent) == "table" and p.noEvent or {}) do unknown[event] = true end
    local list, probes = {}, {}
    for _, source in ipairs({ Record.EVENTS, Record.UNIT_EVENTS }) do
        for _, event in ipairs(source) do
            if not unknown[event] and (Core.Num(counts[event]) or 0) == 0 and (recCounts[event] or 0) == 0 then
                list[#list + 1] = event
                if Probe.autoProbes[event] then probes[#probes + 1] = event end
            end
        end
    end
    table.sort(list)
    table.sort(probes)
    return list, probes
end

-- full: die Ablage ist voll (sagt es höchstens einmal je Sitzung; seit Fassung 2026-11-15-klein hält der Mitschnitt
-- dafür nicht mehr von selbst an); quiet: ohne Chatzeilen (Automatik)
function Record.Stop(full, quiet)
    if not recording then return false end
    recording, Record.auto, recNarrow = false, false, false
    if recFrame then pcall(recFrame.UnregisterAllEvents, recFrame) end
    recQuiet = {}
    Core.AfterCombat(FlushEvents, nil, ADDON)
    if not quiet then
        ns.Print(L.PROBE_RECORD_OFF:format(recStats.events, recStats.kept, recStats.runs, Probe.StatusText()))
        if full then Probe.SayFull() end
        ns.Print(L.PROBE_SAVE_HINT)
    end
    if statusChanged then statusChanged() end
    return true
end

-- Die Ablage wird geleert: was noch im Arbeitsspeicher wartet, verwerfen. Ein laufender Mitschnitt beginnt von vorn –
-- seine Beispiele sind mit der Ablage weg, also hört er wieder auf alles.
function Record.Forget()
    for event in pairs(recCounts) do recCounts[event] = nil end
    for i = #recBuffer, 1, -1 do recBuffer[i] = nil end
    for i = #recMutedNew, 1, -1 do recMutedNew[i] = nil end
    liveCounts = nil
    if recording then
        recLast, recAuto = {}, {}
        recLage.sets, recLage.total = {}, {}
        recLage.carried = false
        Record.UseLage(recLage.now)
        recStats.kept = 0
        Record.Rearm()
    end
end

function Record.Toggle()
    if recording then
        Record.Stop()
        return "stopped"
    end
    return Record.Start() and "started" or "full"
end

-- Nach dem Kampf und vor dem Schreiben der Datei (Abmelden, /reload): Gesammeltes in die Ablage
Core.RegisterEvent(ADDON, "PLAYER_REGEN_ENABLED", function() FlushEvents() end)
Core.RegisterEvent(ADDON, "PLAYER_LOGOUT", function() FlushEvents() end)

---------------------------------------------------------------------------
-- Tempo-Messung (Nachtrag 2): wie schnell beantwortet der Client Gegenstände und Zauber?
---------------------------------------------------------------------------

local Tempo = {}
Probe.Tempo = Tempo
Tempo.SAMPLE = 300          -- Nummern je Art, gleichmäßig über den Bereich verteilt (keine gezielte Suche)
Tempo.PORTION = 10          -- neue Anfragen je Bild (höchstens; das Budget des Bilds gilt auch hier – Probe.Takt)
Tempo.COST = 4              -- so viele Abfragen des Budgets kostet eine Nummer
Tempo.WINDOW = 20           -- höchstens so viele unbeantwortete Anfragen zugleich
Tempo.TIMEOUT = 5           -- Sekunden bis „ohne Antwort“
Tempo.MAX_KEPT = 20         -- gemerkte Messungen
-- Bereich der Nummern: Gegenstände und Zauber der klassischen Welt (Forever); bewusst kein Durchlauf aller Nummern.
Tempo.RANGE = { item = { 1, 24000 }, spell = { 1, 30000 } }
Tempo.KINDS = { "item", "spell" }

local tempo        -- laufende Messung
local tempoFrame

-- n Nummern gleichmäßig über [lo, hi]
function Tempo.Sample(lo, hi, n)
    local ids, span = {}, hi - lo + 1
    n = math.min(n, span)
    for i = 1, n do ids[i] = lo + math.floor((i - 0.5) * span / n) end
    return ids
end

function Tempo.Running() return tempo ~= nil, tempo ~= nil and tempo.paused == true end

local function NewKind() return { n = 0, absent = 0, instant = 0, loaded = 0, failed = 0, none = 0, secret = 0, hist = {},
    latSum = 0, latN = 0 } end

local function Active(now) return now - tempo.started - tempo.pausedSec end

local function Answered(res, now)
    local bucket = math.floor(Active(now)) + 1
    if bucket >= 1 and bucket <= 300 then res.hist[bucket] = (res.hist[bucket] or 0) + 1 end
end

local function Plain(result) return result.ok and not IsSecret(result[1]) end

local function AskItem(id, res, now)
    local exists = Invoke("C_Item.DoesItemExistByID", id)
    if Plain(exists) and exists[1] == false then
        res.absent = res.absent + 1
        return
    end
    local instant = Invoke("C_Item.GetItemInfoInstant", id)
    if exists.missing and Plain(instant) and instant[1] == nil then
        res.absent = res.absent + 1
        return
    end
    -- sofort da? Zuerst der Zwischenspeicher (fragt nichts an); fehlt die Auskunft, zeigt es GetItemInfo
    local cached = Invoke("C_Item.IsItemDataCachedByID", id)
    local have
    if cached.ok and IsSecret(cached[1]) then
        res.secret = res.secret + 1
        return
    elseif cached.ok then
        have = cached[1] == true
    else
        local info = Invoke("C_Item.GetItemInfo", id)
        if info.ok and IsSecret(info[1]) then
            res.secret = res.secret + 1
            return
        end
        have = info.ok and info[1] ~= nil
    end
    if have then
        res.instant = res.instant + 1
        Answered(res, now)
    else
        tempo.pending[id] = now
        tempo.open = tempo.open + 1
        Invoke("C_Item.RequestLoadItemDataByID", id)
    end
end

local function AskSpell(id, res, now)
    local exists = Invoke("C_Spell.DoesSpellExist", id)
    if Plain(exists) and exists[1] == false then
        res.absent = res.absent + 1
        return
    end
    local name = Invoke("C_Spell.GetSpellName", id)
    if exists.missing and Plain(name) and name[1] == nil then
        res.absent = res.absent + 1
        return
    end
    local cached = Invoke("C_Spell.IsSpellDataCached", id)
    if cached.ok and IsSecret(cached[1]) then
        res.secret = res.secret + 1
    elseif (Plain(cached) and cached[1] == true) or (cached.missing and Plain(name) and name[1] ~= nil) then
        res.instant = res.instant + 1
        Answered(res, now)
    else
        tempo.pending[id] = now
        tempo.open = tempo.open + 1
        Invoke("C_Spell.RequestLoadSpellData", id)
    end
end

local TEMPO_EVENTS = { GET_ITEM_INFO_RECEIVED = "item", ITEM_DATA_LOAD_RESULT = "item", SPELL_DATA_LOAD_RESULT = "spell",
    SPELL_TEXT_UPDATE = "spell" }

local function OnTempoEvent(_, event, id, success)
    if not tempo or TEMPO_EVENTS[event] ~= tempo.kind then return end
    id = Core.Num(id)
    local sent = id and tempo.pending[id]
    if not sent then return end
    local now = GameTime()
    local res = tempo.res[tempo.kind]
    tempo.pending[id] = nil
    tempo.open = tempo.open - 1
    res.via = res.via or {}
    res.via[event] = (res.via[event] or 0) + 1
    -- SPELL_TEXT_UPDATE nennt keinen Erfolg; sonst zählt nur ein ausdrückliches false als Fehlschlag
    if not IsSecret(success) and success == false then
        res.failed = res.failed + 1
    else
        res.loaded = res.loaded + 1
        local latency = (now - sent) * 1000
        res.latSum, res.latN = res.latSum + latency, res.latN + 1
        if not res.latMin or latency < res.latMin then res.latMin = latency end
        if not res.latMax or latency > res.latMax then res.latMax = latency end
    end
    Answered(res, now)
end

local function RoundTo(value, digits)
    local factor = 10 ^ (digits or 0)
    return math.floor(value * factor + 0.5) / factor
end

local function KindResult(res, seconds)
    local answers = res.instant + res.loaded + res.failed
    local hist = {}
    local last = 0
    for bucket in pairs(res.hist) do if bucket > last then last = bucket end end
    for i = 1, last do hist[i] = res.hist[i] or 0 end
    return { n = res.n, absent = res.absent, instant = res.instant, loaded = res.loaded, failed = res.failed, none = res.none,
        secret = res.secret, sec = RoundTo(seconds, 2), perSec = seconds > 0 and RoundTo(answers / seconds, 1) or 0,
        latMs = res.latN > 0 and { min = RoundTo(res.latMin, 0), avg = RoundTo(res.latSum / res.latN, 0), max = RoundTo(res.latMax, 0) } or nil,
        via = res.via, hist = hist }
end

local function TempoFinish(abort)
    local t = tempo
    if not t then return nil end
    tempo = nil
    if tempoFrame then pcall(tempoFrame.UnregisterAllEvents, tempoFrame) end
    local now = GameTime()
    if t.kindStart then t.sec[t.kind] = now - t.kindStart - (t.pausedSec - t.kindPaused) end
    local s = Stamp()
    local result = { t = ServerTime(), b = s.build, loc = s.locale, abort = abort and true or nil, paused = RoundTo(t.pausedSec, 1),
        pauses = t.pauses, sample = Tempo.SAMPLE, portion = Tempo.PORTION, window = Tempo.WINDOW, timeout = Tempo.TIMEOUT }
    for _, kind in ipairs(Tempo.KINDS) do
        if t.res[kind].n > 0 then
            result[kind] = KindResult(t.res[kind], t.sec[kind] or 0)
            result[kind].range = Tempo.RANGE[kind]
        end
    end
    Core.AfterCombat(function()
        local p = Store()
        p.tempo[#p.tempo + 1] = result
        while #p.tempo > Tempo.MAX_KEPT do table.remove(p.tempo, 1) end
        if statusChanged then statusChanged() end
    end, nil, ADDON)
    Tempo.last = result
    if not t.quiet then
        for _, kind in ipairs(Tempo.KINDS) do
            local r = result[kind]
            if r then
                ns.Print(L["PROBE_TEMPO_" .. kind]:format(r.n, r.instant, r.loaded, r.failed + r.none, r.absent, r.perSec, r.sec))
            end
        end
        ns.Print((abort and L.PROBE_TEMPO_ABORTED or L.PROBE_TEMPO_DONE) .. " " .. L.PROBE_SAVE_HINT)
    end
    if t.onDone then
        local ok, err = pcall(t.onDone, result)
        if not ok then Core.Error(ADDON, err, "Probe.Tempo") end
    end
    return result
end

local TempoTick
local tempoJob = { urgent = true }   -- Auftrag im Takt: eine Portion Anfragen je Bild
function tempoJob:Slice() TempoTick() end

local function NextKind(now)
    if tempo.kindStart then tempo.sec[tempo.kind] = now - tempo.kindStart - (tempo.pausedSec - tempo.kindPaused) end
    tempo.index = tempo.index + 1
    local kind = Tempo.KINDS[tempo.index]
    if not kind then return false end
    local range = Tempo.RANGE[kind]
    tempo.kind, tempo.ids, tempo.pos = kind, Tempo.Sample(range[1], range[2], Tempo.SAMPLE), 1
    tempo.pending, tempo.open = {}, 0
    tempo.kindStart, tempo.kindPaused = now, tempo.pausedSec
    return true
end

function TempoTick()
    local t = tempo
    if not t then return end
    local now = GameTime()
    if Core.InCombat() then
        -- im Kampf keine Anfragen: Pause bis PLAYER_REGEN_ENABLED, die Pause zählt nicht zur Dauer
        if not t.paused then
            t.paused, t.pauseAt, t.pauses = true, now, t.pauses + 1
            if not t.quiet then ns.Print(L.PROBE_TEMPO_PAUSED) end
        end
        Core.AfterCombat(function() Takt.Want(tempoJob) end, "ezCore.probe.tempo", ADDON)
        return
    end
    if t.paused then
        local gap = now - t.pauseAt
        t.paused, t.pausedSec = false, t.pausedSec + gap
        for id, sent in pairs(t.pending) do t.pending[id] = sent + gap end
        if not t.quiet then ns.Print(L.PROBE_TEMPO_RESUMED) end
    end
    local res = t.res[t.kind]
    for id, sent in pairs(t.pending) do
        if now - sent >= Tempo.TIMEOUT then
            t.pending[id] = nil
            t.open = t.open - 1
            res.none = res.none + 1
        end
    end
    local ask = t.kind == "item" and AskItem or AskSpell
    local sent = 0
    while sent < Tempo.PORTION and t.open < Tempo.WINDOW and t.pos <= #t.ids and (sent == 0 or not Spent()) do
        res.n = res.n + 1
        ask(t.ids[t.pos], res, now)
        t.pos, sent = t.pos + 1, sent + 1
        Use(Tempo.COST)
    end
    if t.pos > #t.ids and t.open <= 0 and not NextKind(now) then
        TempoFinish(false)
        return
    end
    Takt.Want(tempoJob)
end

-- → true | false, Grund ("running" | "combat"). opts (Automatik): quiet = ohne Chatzeilen, onDone(ergebnis) am Ende
function Tempo.Start(opts)
    opts = type(opts) == "table" and opts or {}
    if tempo then return false, "running" end
    if Core.InCombat() then
        if not opts.quiet then ns.Print(L.PROBE_TEMPO_COMBAT) end
        return false, "combat"
    end
    if not tempoFrame then
        tempoFrame = CreateFrame("Frame")
        tempoFrame:SetScript("OnEvent", OnTempoEvent)
    end
    for event in pairs(TEMPO_EVENTS) do pcall(tempoFrame.RegisterEvent, tempoFrame, event) end
    local now = GameTime()
    tempo = { started = now, pausedSec = 0, pauses = 0, index = 0, res = { item = NewKind(), spell = NewKind() }, sec = {},
        pending = {}, open = 0, quiet = opts.quiet, onDone = opts.onDone }
    NextKind(now)
    if not opts.quiet then ns.Print(L.PROBE_TEMPO_START:format(Tempo.SAMPLE, Tempo.SAMPLE)) end
    Takt.Want(tempoJob)
    return true
end

-- Abbrechen: das bisher Gemessene wird festgehalten (abort = true). → Ergebnis oder nil
function Tempo.Stop()
    if not tempo then return nil end
    Core.CancelAfterCombat("ezCore.probe.tempo")
    return TempoFinish(true)
end

function Tempo.Toggle()
    if tempo then
        Tempo.Stop()
        return "stopped"
    end
    return Tempo.Start() and "started" or "combat"
end

---------------------------------------------------------------------------
-- Dokumentation des laufenden Clients (Nachtrag 1): Blizzard_APIDocumentation kompakt mitschreiben
---------------------------------------------------------------------------

local Doc = {}
Probe.Doc = Doc
Doc.MAX_BYTES = 4 * 1024 * 1024
Doc.SLICE = 4               -- Systeme je Bild (höchstens; das Budget des Bilds gilt auch hier – Probe.Takt)
Doc.LOOSE_SLICE = 20        -- Tabellen ohne System je Bild
Doc.ADDONS = { "Blizzard_APIDocumentation", "Blizzard_APIDocumentationGenerated" }

local FIELD_SKIP = { Name = true, Type = true, Nilable = true, InnerType = true, Default = true, Documentation = true,
    Function = true, Table = true, Event = true, EnumValue = true, Mixin = true, StrideIndex = true, Value = true }
local FUNC_SKIP = { Name = true, Type = true, Arguments = true, Returns = true, Documentation = true, System = true }
local EVENT_SKIP = { Name = true, Type = true, LiteralName = true, Payload = true, Documentation = true, System = true }
local TABLE_SKIP = { Name = true, Type = true, Fields = true, Values = true, Arguments = true, Returns = true,
    Documentation = true, System = true }
local SYSTEM_SKIP = { Name = true, Type = true, Namespace = true, Functions = true, Events = true, Tables = true,
    Documentation = true }

-- Übrige einfache Angaben (SecretArguments, MayReturnNothing, Environment …) als „ [A;B=wert]“
local function Flags(info, skip)
    local parts = {}
    for k, v in pairs(info) do
        if type(k) == "string" and not skip[k] then
            local kind = type(v)
            if kind == "boolean" then
                if v then parts[#parts + 1] = k end
            elseif kind == "number" or kind == "string" then
                parts[#parts + 1] = k .. "=" .. tostring(v)
            end
        end
    end
    if #parts == 0 then return "" end
    table.sort(parts)
    return " [" .. table.concat(parts, ";") .. "]"
end

-- „name:typ<inner>?=standard“
function Doc.FieldText(field)
    if type(field) ~= "table" then return "?" end
    local text = tostring(field.Name or "?")
    if field.EnumValue ~= nil then return text .. "=" .. tostring(field.EnumValue) end
    text = text .. ":" .. tostring(field.Type or "?")
    if field.InnerType ~= nil then text = text .. "<" .. tostring(field.InnerType) .. ">" end
    if field.Nilable then text = text .. "?" end
    if field.Default ~= nil then text = text .. "=" .. tostring(field.Default) end
    if field.Value ~= nil then text = text .. "=" .. tostring(field.Value) end
    if field.Mixin ~= nil then text = text .. "@" .. tostring(field.Mixin) end
    if field.StrideIndex ~= nil then text = text .. "#" .. tostring(field.StrideIndex) end
    return text .. Flags(field, FIELD_SKIP)
end

local function FieldList(list)
    if type(list) ~= "table" then return "" end
    local parts = {}
    for i = 1, #list do parts[i] = Doc.FieldText(list[i]) end
    return table.concat(parts, ", ")
end

-- „Name(arg:typ?, …) -> wert:typ, … [Angaben]“
function Doc.FunctionText(info)
    local text = tostring(info.Name or "?") .. "(" .. FieldList(info.Arguments) .. ")"
    local returns = FieldList(info.Returns)
    if returns ~= "" then text = text .. " -> " .. returns end
    return text .. Flags(info, FUNC_SKIP)
end

-- „EREIGNIS_NAME(wert:typ, …) [Angaben]“
function Doc.EventText(info)
    return tostring(info.LiteralName or info.Name or "?") .. "(" .. FieldList(info.Payload) .. ")" .. Flags(info, EVENT_SKIP)
end

-- „E Name{A=0, B=1}“ (Aufzählung), „S Name{feld:typ?}“ (Struktur), „C Name{A:number=5}“ (Konstanten),
-- „F Name(arg) -> wert“ (Rückruf-Typ), sonst „? Art Name“
function Doc.TableText(info)
    local kind, name = info.Type, tostring(info.Name or "?")
    local text
    if kind == "Enumeration" then
        text = "E " .. name .. "{" .. FieldList(info.Fields) .. "}"
    elseif kind == "Structure" then
        text = "S " .. name .. "{" .. FieldList(info.Fields) .. "}"
    elseif kind == "Constants" then
        text = "C " .. name .. "{" .. FieldList(info.Values) .. "}"
    elseif kind == "CallbackType" then
        text = "F " .. name .. "(" .. FieldList(info.Arguments) .. ")"
        local returns = FieldList(info.Returns)
        if returns ~= "" then text = text .. " -> " .. returns end
    else
        text = "? " .. tostring(kind) .. " " .. name
    end
    return text .. Flags(info, TABLE_SKIP)
end

local function TextList(list, fn)
    if type(list) ~= "table" or #list == 0 then return nil, 0 end
    local out = {}
    for i = 1, #list do
        local ok, text = pcall(fn, list[i])
        out[i] = ok and text or "!Fehler"
    end
    return out, #out
end

-- Ein System kompakt: { n = Name, ns = Namensraum, x = Angaben, f = { Funktionen }, e = { Ereignisse }, t = { Tabellen } }
function Doc.System(info)
    local entry = { n = info.Name, ns = info.Namespace }
    local x = Flags(info, SYSTEM_SKIP)
    if x ~= "" then entry.x = x end
    local nf, ne, nt
    entry.f, nf = TextList(info.Functions, Doc.FunctionText)
    entry.e, ne = TextList(info.Events, Doc.EventText)
    entry.t, nt = TextList(info.Tables, Doc.TableText)
    -- Größe wie in der Datei (ezCoreDB » probe » doc » s » System), samt der Zeile in der Liste
    return entry, nf, ne, nt, SizeOf(entry, Probe.DEPTH_DOC) + Probe.DEPTH_DOC + 12
end

-- Blizzards Dokumentation (Tabelle APIDocumentation mit .systems), nur gelesen.
function Doc.Available()
    local api = rawget(_G, "APIDocumentation")
    if type(api) ~= "table" or type(api.systems) ~= "table" or #api.systems == 0 then return nil end
    return api
end

-- Das Dokumentations-Addon nachladen (nur außerhalb des Kampfes). → APIDocumentation oder nil
function Doc.Load()
    local api = Doc.Available()
    if api then return api end
    if Core.InCombat() then return nil end
    for _, name in ipairs(Doc.ADDONS) do pcall(Core.LoadAddOn, name) end
    return Doc.Available()
end

local doc   -- laufende Mitschrift
function Doc.Running() return doc ~= nil end

local function DocFinish()
    local d = doc
    doc = nil
    if not d then return end
    local out = d.out
    out.bytes = d.bytes
    Store().doc = out
    if statusChanged then statusChanged() end
    if not d.quiet then
        ns.Print(L.PROBE_DOC_DONE:format(out.count.systems, out.count.functions, out.count.events, out.count.tables, SizeText(out.bytes))
            .. (out.cut and (" " .. L.PROBE_DOC_CUT) or ""))
        ns.Print(L.PROBE_SAVE_HINT)
    end
    if d.onDone then
        local ok, err = pcall(d.onDone, out)
        if not ok then Core.Error(ADDON, err, "Probe.Doc") end
    end
end

local docJob = {}   -- Auftrag im Takt: eine Portion Systeme je Bild

local function DocTick()
    local d = doc
    if not d then return end
    if Core.InCombat() then
        Core.AfterCombat(function() Takt.Want(docJob) end, "ezCore.probe.doc", ADDON)
        return
    end
    local systems = d.api.systems
    local cost = math.ceil(Probe.SLICE_CALLS / Doc.SLICE)
    local n = 0
    -- mindestens ein System je Bild, höchstens Doc.SLICE und nur, solange das Budget des Bilds reicht
    while d.pos <= #systems and (n == 0 or (n < Doc.SLICE and not Spent())) do
        local ok, entry, nf, ne, nt, bytes = pcall(Doc.System, systems[d.pos])
        if ok then
            d.out.s[#d.out.s + 1] = entry
            d.out.count.functions = d.out.count.functions + nf
            d.out.count.events = d.out.count.events + ne
            d.out.count.tables = d.out.count.tables + nt
            d.bytes = d.bytes + bytes
        else
            d.out.s[#d.out.s + 1] = { n = "!Fehler", x = ErrText(entry) }
        end
        d.out.count.systems = d.out.count.systems + 1
        d.pos, n = d.pos + 1, n + 1
        Use(cost)
        if d.bytes >= Doc.MAX_BYTES then
            d.out.cut = true
            return DocFinish()
        end
    end
    if d.pos <= #systems then return Takt.Want(docJob) end
    -- Tabellen ohne System (Aufzählungen und Konstanten aus eigenen Dateien): einmal einsammeln, dann in Portionen
    if not d.loose then
        d.loose, d.looseText, d.loosePos = {}, {}, 1
        if type(d.api.tables) == "table" then
            for i = 1, #d.api.tables do
                local info = d.api.tables[i]
                if type(info) == "table" and info.System == nil then d.loose[#d.loose + 1] = info end
            end
        end
        if n > 0 and #d.loose > 0 then return Takt.Want(docJob) end
    end
    local m = 0
    while d.loosePos <= #d.loose and (m == 0 or (m < Doc.LOOSE_SLICE and not Spent())) do
        local ok, text = pcall(Doc.TableText, d.loose[d.loosePos])
        d.looseText[d.loosePos] = ok and text or "!Fehler"
        d.loosePos, m = d.loosePos + 1, m + 1
        Use(1)
    end
    if d.loosePos <= #d.loose then return Takt.Want(docJob) end
    if #d.loose > 0 then
        local entry = { n = "", t = d.looseText }
        d.out.s[#d.out.s + 1] = entry
        d.out.count.tables = d.out.count.tables + #d.looseText
        d.bytes = d.bytes + SizeOf(entry, Probe.DEPTH_DOC) + Probe.DEPTH_DOC + 12
    end
    DocFinish()
end
function docJob:Slice() DocTick() end

-- → true | false, Grund ("running" | "combat" | "missing"). opts (Automatik): quiet = ohne Chatzeilen, onDone(mitschrift)
function Doc.Start(opts)
    opts = type(opts) == "table" and opts or {}
    if doc then return false, "running" end
    if Core.InCombat() then
        if not opts.quiet then ns.Print(L.PROBE_DOC_COMBAT) end
        Core.AfterCombat(function() Doc.Start(opts) end, "ezCore.probe.docStart", ADDON)
        return false, "combat"
    end
    local api = Doc.Load()
    local s = Stamp()
    if not api then
        Store().doc = { v = 1, t = ServerTime(), b = s.build, err = "fehlt", count = { systems = 0, functions = 0, events = 0, tables = 0 }, s = {} }
        if not opts.quiet then ns.Print(L.PROBE_DOC_MISSING) end
        return false, "missing"
    end
    doc = { api = api, pos = 1, bytes = 0, quiet = opts.quiet, onDone = opts.onDone,
        out = { v = 1, t = ServerTime(), b = s.build, version = s.version, loc = s.locale,
            count = { systems = 0, functions = 0, events = 0, tables = 0 }, s = {} } }
    if not opts.quiet then ns.Print(L.PROBE_DOC_START:format(#api.systems)) end
    Takt.Want(docJob)
    return true
end

---------------------------------------------------------------------------
-- Automatik: die passende Station startet von selbst, sobald ihr Anlass eintritt (/ez probe auto)
---------------------------------------------------------------------------

--[[
    Der Nutzer (oder ein Helfer, gern einen Monat lang) schaltet die Automatik einmal ein und spielt normal weiter. Sie
      schaltet den Mitschnitt ein (Record.Start mit carry: die Grenzen je Ereignis gelten über alle Sitzungen, die
      Beispiele je Lage); sind alle Arten erfasst, die in der jetzigen Lage zählen, sagt sie es, und er hört nur noch auf
      Ereignisse, an denen etwas fehlt (Complete, „Fertig“ unten) – bis die Lage wechselt (Instanz, Gruppe, Bosskampf,
      anderer Kontinent) oder ein anderer Charakter einloggt: dann ist wieder offen, was dort noch fehlt,
      schreibt einmal die Dokumentation mit und misst einmal das Tempo (nacheinander, nie im Kampf, das Tempo erst,
      wenn der Charakter steht, spätestens nach Auto.TEMPO_TRIES Versuchen),
      und startet danach die Stationen, die Probe.Detect() gerade erkennt – ausgelöst über Ereignisse (Auto.EVENTS),
      das Öffnen der Weltkarte (HookScript „OnShow“; dafür gibt es kein Ereignis) und den Wechsel der Lage
      (Auto.LAGE_EVENTS). Kein OnUpdate.
    Arten (Auto.KINDS): { Art, Station, Grenze, scope = Bereich, req = Lagen }.
      Bereich der Zählung   "char" je Charakter | "lage" je Charakter und Lage (Probe.Lage) | "where" je Charakter und
                            Freiland/Instanz | "cont" je Charakter und Kontinent (Flugmeister) | "build" je Charakter,
                            Build und Sprache (allein: Probe.BuildScope, „b70938.deDE“)
      Grenzen               Auto.LIMIT[Grenze]: Läufe je Bereich und Charakter; Auto.TOTAL[Grenze]: je Bereich über alle
                            Charaktere dieser Ablage – danach läuft die Art nicht mehr (die Ablage bleibt klein, der
                            Mitschnitt zählt weiter)
      req                   Lagen, in denen die Art erfasst sein muss, bevor „alles erfasst“ gilt: "w" Freiland allein,
                            "o" Freiland allein oder in einer Gruppe (die Fenster und der Tod: Wer mit Freunden spielt,
                            öffnet Briefkasten und Bank auch in der Gruppe), "G" in einer Gruppe, "I" in einer Instanz,
                            "B" im Bosskampf (alle außer "B" ohne Bosskampf). Nur in diesen Lagen hört die Automatik auf
                            die Ereignisse der Art (Prune). Ohne req ist die Art eine
                            Spielart (begrenzter Vorrat, Klassenlehrer, Beute aus einem Objekt, Vignette …): Sie läuft,
                            wenn sie vorkommt, und hält „alles erfasst“ nicht auf.
    Ein Lauf zählt für alle Arten, die gerade passen (Auto.KindsNow: die Station selbst und Probe.KindOf[Station]) – der
    Händler mit begrenztem Vorrat für „Händler“ und „Händler mit begrenztem Vorrat“; er läuft, wenn eine davon offen
    ist. Gezählt wird in der Ablage (per, tot; dazu wie bisher done je Station und kinds je Art über alle Charaktere) –
    über /reload und Neuanmeldung hinweg; Läufe von Hand zählen mit. Nie zwei Stationen zugleich: eine eigene
    Warteschlange, die nächste Station startet erst, wenn kein Lauf mehr läuft; vor dem Start wird neu geprüft, ob der
    Anlass noch besteht (Fenster noch offen, Ziel noch da). Im Kampf wartet alles außer Kampf und Beute
    (Core.AfterCombat). Abfragen, Maskierung und Portionen sind die der Stationen – die Automatik fragt selbst nur, was
    sie zur Erkennung braucht, und löst nie eine Sonderprobe aus (sie kennt nur die Schlüssel aus Auto.KINDS).
    Fertig: Sind alle Arten erfasst, die in dieser Lage zählen, startet die Automatik keine Station dieser Arten mehr
    (ihre Ereignisse sind abgemeldet, solange keine Spielart der Station offen ist) und ihr Mitschnitt hört nur noch auf
    Ereignisse, an denen etwas fehlt (Record.Narrow) – ein Bosskampf oder ein Würfeln kann lange nach dem letzten
    Händler kommen. Sie bleibt dafür an, bis der Nutzer sie ausschaltet oder die Probe voll ist.
    Zustand in der Ablage: probe.auto = { on, quiet, noTempo, fullSaid, complete = Zeichen der Lage, said = { Zeichen } }.

      Auto.Enable(), Disable(grund), Toggle()   → true | false, Grund       Auto.Enabled(), Auto.Active()
      Auto.SetQuiet(bool), Auto.Quiet()         eine Chatzeile je Station oder keine
      Auto.Count(art), Limit(art)               Läufe hier (Charakter, Lage), Grenze je Charakter
      Auto.Total(art), TotalLimit(art)          Läufe hier über alle Charaktere, Grenze dafür
      Auto.Open(), OpenExtra(), Here()          offene Arten, die hier zählen; offene Spielarten; alle, die hier zählen
      Auto.KindsNow(station), Key(art), Tally(arten)   Arten des jetzigen Anlasses; Zählschlüssel je Charakter und Lage
      Auto.OpenText(max), Auto.StatusLine()     „noch offen (17): …“, Zeile der Übersicht
      Auto.Completed(), Auto.WaitingText()      alle Arten hier erfasst (und gemeldet)? worauf der Mitschnitt noch wartet
      Auto.Resume()                             nach dem Einloggen: aus dem gespeicherten Zustand weitermachen
      Auto.LageChanged(ereignis)                Instanz, Gruppe, Boss, Kontinent gewechselt (Auto.LAGE_EVENTS)
      Auto.EventOpen(ereignis)                  darf der Mitschnitt an diesem Ereignis noch eine Abfrage auslösen?
      Auto.Listening(ereignis)                  hört sie noch darauf? (abgemeldet, sobald die Station nichts mehr offen hat)
      Auto.Forget()                             Arbeitsspeicher zurücksetzen (Leeren der Probe, Prüfungen)
      Auto.Restart()                            nach „Probe leeren“ wieder anlaufen, wenn sie an ist (still)
]]
local Auto = {}
Probe.Auto = Auto
Auto.LIMIT = { window = 2, target = 1, combat = 2, loot = 3, once = 1, event = 3, inst = 2, extra = 1 }
Auto.TOTAL = { window = 4, target = 3, combat = 6, loot = 6, once = 3, event = 6, inst = 6, extra = 3 }
-- Bereich „je Build“ („allein“): je Build einmal je Charakter (Auto.LIMIT.once), dazu über alle Builds höchstens
-- Auto.BUILD_LIMIT Builds je Charakter und Auto.BUILD_TOTAL Läufe in der Ablage – ein Lauf „allein“ kostet beim ersten
-- Mal rund 0,8 MB (Probe 15.11.2026), danach je Charakter und Build ein gutes Drittel bis die Hälfte (Taschen, Tooltips,
-- Quests, Berufe ändern sich); ohne diese Grenze füllten wöchentliche Builds die Ablage in einem Monat.
Auto.BUILD_LIMIT = 2
Auto.BUILD_TOTAL = 4
-- Arten in der Reihenfolge der Übersicht: { Art, Station, Grenze aus Auto.LIMIT, scope = Bereich, req = Lagen }
Auto.KINDS = {
    -- „allein“: einmal je Build, Sprache und Charakter (die Antworten ändern sich nur mit dem Build oder der Sprache)
    { "A", "A", "once", scope = "build", req = { "o" } },
    { "W", "W", "window", scope = "char", req = { "o" } },
    { "B", "B", "window", scope = "char", req = { "o" } },
    { "C", "C", "window", scope = "char", req = { "o" } },
    { "D", "D", "window", scope = "char", req = { "o" } },
    { "E", "E", "window", scope = "char", req = { "o" } },
    { "I", "I", "window", scope = "char", req = { "o" } },
    { "J", "J", "window", scope = "char", req = { "o" } },
    { "K", "K", "window", scope = "char", req = { "o" } },
    { "L", "L", "window", scope = "cont", req = { "o" } },
    { "F:npc", "F", "target", scope = "lage", req = { "w" } },
    { "F:enemy", "F", "target", scope = "lage", req = { "w", "G", "I" } },
    { "F:elite", "F", "target", scope = "lage", req = { "w", "I", "B" } },
    { "F:player", "F", "target", scope = "lage", req = { "w" } },
    { "F:pet", "F", "target", scope = "lage", req = { "w" } },
    { "F:corpse", "F", "target", scope = "lage", req = { "w", "I" } },
    { "G", "G", "combat", scope = "lage", req = { "w", "G", "I", "B" } },
    { "G10", "G10", "loot", scope = "lage", req = { "w", "I" } },
    { "H", "H", "once", scope = "char", req = { "G" } },
    { "M", "M", "inst", scope = "where", req = { "I" } },
    { "N", "N", "once", scope = "where", req = { "o", "I" } },
    -- Spielarten: laufen, wenn sie vorkommen (Probe.KindOf in ProbeStations.lua), und halten „alles erfasst“ nicht auf
    { "B:limited", "B", "extra", scope = "char" }, { "B:cost", "B", "extra", scope = "char" },
    { "C:class", "C", "extra", scope = "char" }, { "C:prof", "C", "extra", scope = "char" },
    { "C:pet", "C", "extra", scope = "char" }, { "C:all", "C", "extra", scope = "char" },
    { "E:browse", "E", "extra", scope = "char" }, { "E:result", "E", "extra", scope = "char" },
    { "J:unlearned", "J", "extra", scope = "char" },
    { "G10:object", "G10", "extra", scope = "lage" }, { "G10:item", "G10", "extra", scope = "lage" },
    { "G10:fish", "G10", "extra", scope = "lage" },
    { "O:object", "O", "extra", scope = "lage" }, { "O:vignette", "O", "extra", scope = "lage" },
}
-- Anlässe: Ereignis → Station, die es vor allem meint. Gestartet wird, was Probe.Detect() danach erkennt (am Händler
-- also auch dessen Zielart). Namen wie in Blizzards Fenstern (MerchantFrame, ClassTrainerFrame, MailFrame,
-- AuctionHouseFrame, BankFrame, TaxiFrame/FlightMap, ProfessionsFrame, QuestFrame, GossipFrame, LootFrame);
-- angemeldet in pcall – ein Name, den dieser Client nicht kennt, fehlt dann einfach.
Auto.EVENTS = {
    MERCHANT_SHOW = "B", TRAINER_SHOW = "C", MAIL_SHOW = "D", AUCTION_HOUSE_SHOW = "E", BANKFRAME_OPENED = "I",
    TRADE_SKILL_SHOW = "J", TAXIMAP_OPENED = "L",
    QUEST_DETAIL = "K", QUEST_PROGRESS = "K", QUEST_COMPLETE = "K", QUEST_GREETING = "K", GOSSIP_SHOW = "K",
    PLAYER_TARGET_CHANGED = "F", GROUP_JOINED = "H", PLAYER_ENTERING_WORLD = "M", PLAYER_DEAD = "N",
    LOOT_READY = "G10", PLAYER_REGEN_DISABLED = "G",
    -- Nachprobe: Auktionssuche und ihre Ergebniszeilen, Spielobjekt in Reichweite, Vignetten
    AUCTION_HOUSE_BROWSE_RESULTS_UPDATED = "E", ITEM_SEARCH_RESULTS_UPDATED = "E", COMMODITY_SEARCH_RESULTS_UPDATED = "E",
    PLAYER_SOFT_INTERACT_CHANGED = "O", VIGNETTES_UPDATED = "O", VIGNETTE_MINIMAP_UPDATED = "O",
}
-- Wechsel der Lage (Instanz, Gruppe, Bosskampf, Kontinent): danach ist wieder offen, was dort noch fehlt
Auto.LAGE_EVENTS = { "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "GROUP_JOINED", "GROUP_LEFT", "ENCOUNTER_START",
    "ENCOUNTER_END", "ZONE_CHANGED_NEW_AREA", "PLAYER_MAP_CHANGED" }
Auto.INSTANT = { LOOT_READY = true }   -- sofort am Ereignis (das Beutefenster ist gleich wieder zu)
Auto.DELAY = 0.3          -- Sekunden vom Ereignis bis zur Erkennung (Blizzards Fenster zeigt sich erst im selben Bild)
Auto.COMBAT_DELAY = 1     -- Sekunden nach Kampfbeginn bis zur Kampf-Station
Auto.BOSS_DELAY = 3       -- … nach Beginn eines Bosskampfs (der Kampf-Lauf vom Kampfbeginn ist dann fertig)
Auto.INSTANCE_LATER = 20  -- Sekunden nach dem Betreten einer Instanz: Station „Dungeon“ noch einmal (Position nach dem Laden)
Auto.START_DELAY = 1      -- nach dem Einschalten
Auto.LOGIN_DELAY = 5      -- nach dem Einloggen bzw. /reload
Auto.TEMPO_RETRY = 2      -- Sekunden zwischen zwei Blicken, ob der Charakter steht
Auto.TEMPO_TRIES = 10     -- danach startet die Tempo-Messung auch im Laufen
Auto.OPEN_SHOWN = 4       -- so viele offene Arten nennt die Chatzeile

do
    local active, busy = false, false     -- eingeschaltet (Ereignisse angemeldet); eine eigene Station läuft
    local ready = false                   -- die Wartezeit nach dem Einschalten bzw. Einloggen ist um
    local prep                            -- nil | "doc" | "wait" (auf Stillstand) | "tempo"
    local queue, queued = {}, {}          -- wartende Stationen: { key, ev }; Schlüssel → true
    local inflight = {}                   -- Zählschlüssel (per, tot) → gestartete, noch nicht in der Ablage gezählte Läufe
    local lastHit = {}                    -- Ereignis → Zeit, zu der die Automatik daran sofort gestartet hat
    local held = {}                       -- Station → lief schon zu diesem Anlass (bis das Fenster zu war oder neu aufgeht)
    local frame, mapHooked = nil, false
    local pruned = {}                     -- Ereignis → true: abgemeldet, seine Station hat nichts mehr offen
    local scanWaiting, pumpWaiting = false, false
    local tempoTries, tempoTried, docTried, stopping = 0, false, false, false
    local lastSig                         -- Zeichen der Lage beim letzten Blick (Auto.LageChanged)
    local kindInfo = {}
    for _, entry in ipairs(Auto.KINDS) do kindInfo[entry[1]] = entry end
    local Pump, Prepare, Deactivate, Complete
    local evKeys = {}                     -- Ereignis → "ev:EREIGNIS" (Zähler in probe.kinds), einmal zusammengesetzt
    local function EventKey(event)
        local key = evKeys[event]
        if not key then
            key = "ev:" .. event
            evKeys[event] = key
        end
        return key
    end

    -- Zustand in der Ablage (create: anlegen, wenn es ihn noch nicht gibt). → probe.auto, probe
    local function State(create)
        local p
        if create then p = Store() else p = Probe.Data() end
        if type(p) ~= "table" then return nil end
        if type(p.auto) ~= "table" then
            if not create then return nil end
            p.auto = {}
        end
        return p.auto, p
    end

    function Auto.Active() return active end
    function Auto.Enabled()
        local a = State()
        return a ~= nil and a.on == true
    end
    function Auto.Quiet()
        local a = State()
        return a ~= nil and a.quiet == true
    end
    local function Say(text)
        if not Auto.Quiet() then ns.Print(text) end
    end

    -- Bereich, in dem die Art gerade zählt: "-" (je Charakter), die Lage, "w"/"i" oder "k<Kontinent>"
    local function ScopeOf(entry)
        local scope = entry.scope
        if scope == "lage" then return Probe.Lage() end
        if scope == "where" then return (Probe.Lage():sub(1, 1)) end
        if scope == "cont" then return "k" .. tostring(Probe.Continent() or "?") end
        if scope == "build" then return Probe.BuildScope() end
        return "-"
    end

    -- Zählschlüssel der Art hier: je Charakter („F:enemy|ig|2“) und über alle Charaktere („F:enemy|ig“)
    function Auto.Key(kind)
        local entry = kindInfo[kind]
        if not entry then return nil end
        local tot = kind .. "|" .. ScopeOf(entry)
        return tot .. "|" .. tostring(Probe.CharIndex()), tot
    end

    -- Arten → { { kind, per, tot } … } (beim Start eines Laufs bestimmt; Commit zählt damit)
    -- Bereich „je Build“: Zählschlüssel über alle Builds („A|*|2“, „A|*“) – nil für alle anderen Bereiche
    function Auto.AllKey(kind)
        local entry = kindInfo[kind]
        if not entry or entry.scope ~= "build" then return nil end
        return kind .. "|*|" .. tostring(Probe.CharIndex()), kind .. "|*"
    end

    function Auto.Tally(kinds)
        local list = {}
        for _, kind in ipairs(kinds or {}) do
            local per, tot = Auto.Key(kind)
            local aper, atot = Auto.AllKey(kind)
            if per then list[#list + 1] = { kind = kind, per = per, tot = tot, aper = aper, atot = atot } end
        end
        return list
    end

    local function Stored(field, key)
        local p = Probe.Data()
        local t = p and type(p[field]) == "table" and p[field] or nil
        return (t and Core.Num(t[key]) or 0) + (inflight[key] or 0)
    end

    function Auto.Limit(kind)
        local info = kindInfo[kind]
        return info and Core.Num(Auto.LIMIT[info[3]]) or 0
    end
    function Auto.TotalLimit(kind)
        local info = kindInfo[kind]
        return info and Core.Num(Auto.TOTAL[info[3]]) or 0
    end

    -- Wie oft ist die Art hier erfasst – von diesem Charakter (Count) bzw. von allen Charakteren der Ablage (Total)?
    function Auto.Count(kind)
        local per = Auto.Key(kind)
        return per and Stored("per", per) or 0
    end
    function Auto.Total(kind)
        local _, tot = Auto.Key(kind)
        return tot and Stored("tot", tot) or 0
    end

    local function IsOpen(kind)
        if not (Auto.Count(kind) < Auto.Limit(kind) and Auto.Total(kind) < Auto.TotalLimit(kind)) then return false end
        local aper, atot = Auto.AllKey(kind)
        return aper == nil or (Stored("per", aper) < Auto.BUILD_LIMIT and Stored("tot", atot) < Auto.BUILD_TOTAL)
    end
    Auto.IsOpen = IsOpen

    -- Neu: die Art hat in diesem Bereich (Lage, Kontinent, Build …) über alle Charaktere noch keinen Lauf in der Ablage
    -- (ohne die gerade gestarteten – der Lauf, nach dem gefragt wird, ist schon als gestartet gezählt).
    function Auto.IsNew(kinds)
        local p = Probe.Data()
        local t = p and type(p.tot) == "table" and p.tot or {}
        for i = 1, kinds and #kinds or 0 do
            local _, tot = Auto.Key(kinds[i])
            if tot and (Core.Num(t[tot]) or 0) == 0 then return true end
        end
        return false
    end

    -- Soll die Art jetzt laufen? Offen und – bei voller Ablage – neu (dann bis zur Reserve, Probe.Hard).
    -- (kein local: der Block der Automatik liegt an LuaJITs Grenze von 200 lokalen Namen)
    function Auto.Wanted(kind)
        if not IsOpen(kind) then return false end
        if not Probe.Full() then return true end
        return not Probe.Hard() and Auto.Total(kind) == 0
    end

    local function Eligible(kinds)
        for i = 1, kinds and #kinds or 0 do
            if Auto.Wanted(kinds[i]) then return true end
        end
        return false
    end

    -- Gehört die Lage zur Klasse? "w" Freiland allein, "o" Freiland allein oder in einer Gruppe, "G" Gruppe,
    -- "I" Instanz, "B" Bosskampf (o, G und I ohne Boss)
    local function LageIs(lage, class)
        local boss = lage:find("b", 1, true) ~= nil
        if class == "w" then return lage == "w" end
        if class == "B" then return boss end
        if boss then return false end
        if class == "o" then return lage:sub(1, 1) == "w" end
        if class == "G" then return lage:find("g", 1, true) ~= nil end
        if class == "I" then return lage:sub(1, 1) == "i" end
        return false
    end
    local function Required(entry, lage)
        local req = entry.req
        for i = 1, req and #req or 0 do
            if LageIs(lage, req[i]) then return true end
        end
        return false
    end

    -- Arten, die hier zählen (Here), davon offen (Open); offene Spielarten (OpenExtra)
    function Auto.Here()
        local lage, list = Probe.Lage(), {}
        for _, entry in ipairs(Auto.KINDS) do
            if Required(entry, lage) then list[#list + 1] = entry[1] end
        end
        return list
    end
    function Auto.Open()
        local lage, list = Probe.Lage(), {}
        for _, entry in ipairs(Auto.KINDS) do
            if Required(entry, lage) and IsOpen(entry[1]) then list[#list + 1] = entry[1] end
        end
        return list
    end
    function Auto.OpenExtra()
        local list = {}
        for _, entry in ipairs(Auto.KINDS) do
            if entry.req == nil and IsOpen(entry[1]) then list[#list + 1] = entry[1] end
        end
        return list
    end

    -- Arten des jetzigen Anlasses einer Station: die Station selbst (wenn sie eine Art ist) und, was Probe.KindOf[Station]
    -- erkennt (beim Ziel die Zielart; Spielarten wie begrenzter Vorrat oder Klassenlehrer). → Liste (leer: zählt nicht)
    function Auto.KindsNow(key)
        local list = {}
        if kindInfo[key] then list[1] = key end
        local fn = Probe.KindOf[key]
        if type(fn) == "function" then
            local ok, found = pcall(fn)
            if ok then
                if type(found) == "string" then found = { found } end
                for _, kind in ipairs(type(found) == "table" and found or {}) do
                    if kindInfo[kind] and kind ~= key then list[#list + 1] = kind end
                end
            end
        end
        return list
    end

    function Auto.KindTitle(kind)
        if type(kind) ~= "string" then return tostring(kind) end
        local st, sub = kind:match("^([^:]+):(.+)$")
        if st == "F" then return L.PROBE_KIND_TITLE:format(L["PROBE_KIND_" .. sub]) end
        if st then return L["PROBE_KIND_" .. st .. "_" .. sub] end
        return Probe.StationTitle(kind)
    end

    -- „noch offen (17): Händler, Lehrer …“ bzw. „alles erfasst …“; max: so viele Arten nennen
    function Auto.OpenText(max)
        local open = Auto.Open()
        local text
        if #open == 0 then
            text = L.PROBE_AUTO_ALL
        else
            local names = {}
            for i = 1, math.min(#open, max or #open) do names[i] = Auto.KindTitle(open[i]) end
            text = L.PROBE_AUTO_OPEN:format(#open, table.concat(names, ", ") .. (#open > #names and L.PROBE_AUTO_MORE or ""))
        end
        return text .. Auto.SpecialsText(max)
    end

    -- Zusatz zu „noch offen“: Sonderproben laufen nur auf Befehl – je offene mit ihrem Befehl. "" ohne offene.
    function Auto.SpecialsText(max)
        local list = Probe.OpenSpecials and Probe.OpenSpecials() or {}
        if #list == 0 then return "" end
        local parts = {}
        for i = 1, math.min(#list, max or #list) do parts[i] = L.PROBE_AUTO_SPECIAL:format(list[i].id, list[i].cmd) end
        return " " .. L.PROBE_AUTO_SPECIALS:format(table.concat(parts, ", ") .. (#list > #parts and L.PROBE_AUTO_MORE or ""))
    end

    -- Chatzeile nach einem eigenen Lauf (Spieltest 15.11.2026: zweimal hintereinander „Berufefenster festgehalten“):
    -- sie nennt alle Arten des Laufs; derselbe Titel noch einmal mit weniger Offenem heißt „2. Lauf“, ohne Änderung am
    -- Offenen wird sie nicht wiederholt. → Text oder nil (nichts zu melden)
    -- (Merker am Auto-Tisch statt eines lokalen Werts: Probe.lua liegt an LuaJITs Grenze von 200 lokalen Variablen)
    function Auto.DoneText(kinds, openN)
        local titles, seen = {}, {}
        for _, kind in ipairs(type(kinds) == "table" and kinds or {}) do
            local title = Auto.KindTitle(kind)
            if title and not seen[title] then
                seen[title] = true
                titles[#titles + 1] = title
            end
        end
        if #titles == 0 then return nil end
        local title = table.concat(titles, ", ")
        local last = Auto.lastDone
        if last and last.title == title and last.open == openN then return nil end
        local again = (last and last.title == title) and last.n + 1 or 1
        Auto.lastDone = { title = title, open = openN, n = again }
        if again > 1 then title = L.PROBE_AUTO_AGAIN:format(title, again) end
        return L.PROBE_AUTO_DONE:format(title, Auto.OpenText(Auto.OPEN_SHOWN))
    end
    function Auto.ResetDoneText() Auto.lastDone = nil end

    -- Zeichen der Lage: Charakter, Lage, Kontinent – „alles erfasst“ gilt je Zeichen
    local function Signature()
        return tostring(Probe.CharIndex()) .. "|" .. Probe.Lage() .. "|" .. tostring(Probe.Continent())
    end

    -- Alle Arten, die hier zählen, sind erfasst, und die Automatik hat es gemeldet.
    function Auto.Completed()
        local a = State()
        return a ~= nil and a.complete ~= nil and a.complete == Signature() and #Auto.Open() == 0
    end

    -- Worauf wartet der Mitschnitt noch, wenn alle Arten der Stationen erfasst sind? „Noch nie eingetreten: 23
    -- Ereignisse, darunter mit eigener Abfrage: ENCOUNTER_END …“ – "", solange ihr Mitschnitt nicht nur noch auf Offenes
    -- hört (Record.Narrowed; ein Mitschnitt von Hand hört auf alles) oder nichts mehr offen ist.
    function Auto.WaitingText()
        if not Record.Narrowed() then return "" end
        local unseen, probes = Record.Unseen()
        if #unseen == 0 then return "" end
        if #probes == 0 then return L.PROBE_AUTO_WAITING:format(#unseen) end
        local names = {}
        for i = 1, math.min(#probes, Auto.OPEN_SHOWN) do names[i] = probes[i] end
        return L.PROBE_AUTO_WAITING_PROBES:format(#unseen, table.concat(names, ", ") .. (#probes > #names and L.PROBE_AUTO_MORE or ""))
    end

    function Auto.StatusLine()
        local state = L.PROBE_AUTO_STATE_OFF
        if Auto.Enabled() then state = Auto.Quiet() and L.PROBE_AUTO_STATE_QUIET or L.PROBE_AUTO_STATE_ON end
        local here, open = #Auto.Here(), #Auto.Open()
        local line = L.PROBE_AUTO_HEAD:format(state, here - open, here, Auto.OpenText())
        line = line .. " " .. L.PROBE_AUTO_WHERE:format(Probe.CharIndex(), L["PROBE_LAGE_" .. Probe.Lage()])
        local waiting = active and open == 0 and Auto.WaitingText() or ""
        if waiting ~= "" then line = line .. " " .. waiting end
        return line
    end

    -- Besteht der Anlass der Station gerade? (dieselbe Erkennung wie Probe.Detect)
    local function Fits(key)
        local station = Probe.stations[key]
        if not station then return false end
        if key == "G" then return Core.InCombat() end
        if key == "A" then return Probe.Detect()[1] == "A" end
        if type(station.when) ~= "function" then return false end
        local ok, yes = pcall(station.when, (Probe.OpenWindows()))
        return ok and yes and true or false
    end

    local function PumpSoon()
        if pumpWaiting or not active then return end
        pumpWaiting = true
        C_Timer.After(0, function()
            pumpWaiting = false
            Pump()
        end)
    end

    local function Hold(tally, by)
        for i = 1, tally and #tally or 0 do
            local t = tally[i]
            for _, key in ipairs({ t.per, t.tot, t.aper or false, t.atot or false }) do
                if key then inflight[key] = math.max(0, (inflight[key] or 0) + by) end
            end
        end
    end

    -- Ein eigener Lauf ist zu Ende: eine Chatzeile, dann die nächste wartende Station.
    local function Finished(run, kinds, tally)
        busy = false
        -- nichts gefragt: zählt nicht (ein Lauf nur aus gleichen Antworten zählt – er steht mit dem Kopf in der Ablage)
        local calls = run and run.result and (run.result.asked or run.result.calls) or 0
        if calls == 0 then Hold(tally, -1) end
        if not active then return end
        -- volle Ablage: die Automatik bleibt an und startet nur noch, was hier neu ist (Eligible)
        if Probe.Full() then Probe.SayFull(true) end
        if calls > 0 then
            local text = Auto.DoneText(kinds, #Auto.Open())
            if text then Say(text) end
        end
        if #Auto.Open() == 0 then return Complete() end
        PumpSoon()
    end

    -- Der Lauf steht in der Ablage (Probe.lua, Commit): ab jetzt zählt die Ablage, nicht mehr der Arbeitsspeicher.
    function Auto.Committed(tally) Hold(tally, -1) end

    local function Start(key, kinds, ev)
        busy = true
        local tally = Auto.Tally(kinds)
        Hold(tally, 1)
        local ok = Probe.Run(key, { quiet = true, ev = ev, kind = kinds[1], kinds = kinds, tally = tally, auto = true,
            done = function(run) Finished(run, kinds, tally) end })
        if not ok then
            busy = false
            Hold(tally, -1)
        end
        return ok
    end

    -- Die nächste wartende Station starten – nur, wenn nichts läuft; vor dem Start neu prüfen, ob sie noch passt.
    function Pump()
        if not active or busy or #queue == 0 then return end
        if Probe.Hard() then
            queue, queued = {}, {}
            return
        end
        if prep == "doc" or prep == "tempo" then return end   -- danach ruft Prepare wieder
        if Core.InCombat() then
            Core.AfterCombat(PumpSoon, "ezCore.probe.auto.pump", ADDON)
            return
        end
        if Probe.Running() then return end                    -- danach ruft Auto.Idle
        while #queue > 0 do
            local request = table.remove(queue, 1)
            queued[request.key] = nil
            local kinds = Fits(request.key) and Auto.KindsNow(request.key) or nil
            if kinds and Eligible(kinds) and Start(request.key, kinds, request.ev) then return end
        end
    end

    -- Kein Lauf läuft mehr (Probe.lua, StartNext).
    function Auto.Idle()
        if active and not busy and #queue > 0 then PumpSoon() end
    end

    -- Eine Station ist gestartet (Probe.Run, auch von Hand): Solange ihr Anlass derselbe bleibt – das Fenster offen, die
    -- Karte offen –, startet die Automatik sie nicht noch einmal; sonst verbrauchte ein Händlerbesuch beide Läufe.
    function Auto.Ran(key) held[key] = true end

    local function Request(key, ev)
        if queued[key] or held[key] then return false end
        if not Eligible(Auto.KindsNow(key)) then return false end
        queue[#queue + 1] = { key = key, ev = ev }
        queued[key] = true
        return true
    end

    -- Weltkarte: kein Ereignis – einmal an Blizzards Rahmen einhaken (HookScript läuft nach Blizzards eigenem Skript
    -- und schreibt nichts in dessen Tabellen).
    local function HookMap()
        if mapHooked then return end
        local map = rawget(_G, "WorldMapFrame")
        local hook = Core.Peek(map, "HookScript")
        if type(hook) ~= "function" then return end
        mapHooked = true
        pcall(hook, map, "OnShow", function()
            if not active then return end
            held.W = nil
            Auto.ScanSoon("WORLD_MAP_SHOW")
        end)
    end

    -- Ereignisse an- bzw. abmelden: Jede Station mit einer Art, die hier offen ist (oder einer offenen Spielart), behält
    -- ihr Ereignis; der Rest löste nur noch die Erkennung aus, die dann nichts startet. Wechselt die Lage, kommt ein
    -- abgemeldetes Ereignis wieder dazu, wenn seine Station dort etwas offen hat.
    local function Prune()
        if not active or not frame then return end
        local open, lage = {}, Probe.Lage()
        for _, entry in ipairs(Auto.KINDS) do
            if not open[entry[2]] and (entry.req == nil or Required(entry, lage)) and Auto.Wanted(entry[1]) then open[entry[2]] = true end
        end
        for event, key in pairs(Auto.EVENTS) do
            if open[key] then
                if pruned[event] then
                    pruned[event] = nil
                    pcall(frame.RegisterEvent, frame, event)
                end
            elseif not pruned[event] then
                pruned[event] = true
                pcall(frame.UnregisterEvent, frame, event)
            end
        end
    end
    -- Hört die Automatik noch auf dieses Ereignis?
    function Auto.Listening(event) return active and Auto.EVENTS[event] ~= nil and not pruned[event] end

    -- Was passt gerade? Jede erkannte Station, deren Art noch offen ist, in die Warteschlange.
    local function Scan(ev)
        if not active or not ready then return end
        if Core.InCombat() then
            -- im Kampf Geöffnetes wartet: nach dem Kampf neu erkennen (das Fenster kann dann schon wieder zu sein)
            Core.AfterCombat(function() Auto.ScanSoon(ev) end, "ezCore.probe.auto.scan", ADDON)
            return
        end
        HookMap()
        if #Auto.Open() > 0 or #Auto.OpenExtra() > 0 then   -- alles erfasst: nichts mehr zu erkennen
            local list, fits = Probe.Detect(), {}
            for i = 1, #list do fits[list[i]] = true end
            for key in pairs(held) do
                if not fits[key] then held[key] = nil end   -- der Anlass ist vorbei (Fenster zu)
            end
            for i = 1, #list do Request(list[i], ev) end
        end
        Prune()
        Pump()
    end

    -- Erkennung kurz nach dem Ereignis; mehrere Ereignisse in dieser Zeit lösen sie nur einmal aus.
    function Auto.ScanSoon(ev, delay)
        if not active then return end
        if delay == nil then
            if scanWaiting then return end
            scanWaiting = true
        end
        C_Timer.After(delay or Auto.DELAY, function()
            if delay == nil then scanWaiting = false end
            Scan(ev)
        end)
    end

    -- Darf die Station jetzt sofort starten (Beute am Ereignis, Kampf kurz nach Kampfbeginn)? → Arten oder false
    local function CanInstant(key)
        if not active or not ready or busy or prep == "doc" or prep == "tempo" or Probe.Hard() then return false end
        local station = Probe.stations[key]
        if not station then return false end
        if Core.InCombat() then
            if not station.combat then return false end
        elseif Probe.Running() then
            return false
        end
        local kinds = Fits(key) and Auto.KindsNow(key) or nil
        return kinds ~= nil and Eligible(kinds) and kinds or false
    end

    -- Übernimmt die Automatik an diesem Ereignis die Station, zu der die Abfrage des Mitschnitts gehört?
    function Auto.Covers(event)
        if not active then return false end
        if lastHit[event] ~= nil and lastHit[event] == GameTime() then return true end
        local key, auto = Auto.EVENTS[event], Probe.autoProbes[event]
        if not key or not auto or auto.station ~= key then return false end
        if Auto.INSTANT[event] then return CanInstant(key) ~= false end
        if not ready or busy or prep == "doc" or prep == "tempo" then return false end   -- die Station käme zu spät
        local station = Probe.stations[key]
        if not station or (Core.InCombat() and not station.combat) then return false end
        return Eligible(Auto.KindsNow(key))
    end

    -- Zählschlüssel einer Abfrage des Mitschnitts an einem Ereignis: je Charakter und Lage, je Lage über alle Charaktere
    local function EventKeys(event)
        local tot = EventKey(event) .. "|" .. Probe.Lage()
        return tot .. "|" .. tostring(Probe.CharIndex()), tot
    end

    -- Abfrage des Mitschnitts an einem Ereignis (Probe.autoProbes), solange die Automatik läuft: nicht doppelt zur
    -- Station der Automatik, und je Ereignis höchstens Auto.LIMIT.event-mal je Charakter und Lage (Auto.TOTAL.event je
    -- Lage über alle Charaktere). → darf laufen
    function Auto.AllowEvent(event)
        if Auto.Covers(event) then return false end
        if not Auto.EventOpen(event) then return false end
        local per, tot = EventKeys(event)
        if Probe.Full() and (Probe.Hard() or Stored("tot", tot) > 0) then return false end   -- voll: nur, was hier neu ist
        local p = Store()
        local key = EventKey(event)
        p.per[per] = (Core.Num(p.per[per]) or 0) + 1
        p.tot[tot] = (Core.Num(p.tot[tot]) or 0) + 1
        p.kinds[key] = (Core.Num(p.kinds[key]) or 0) + 1   -- über alle Charaktere und Lagen (Übersicht, Lese-Werkzeug)
        return true
    end

    -- Ist die Grenze je Ereignis hier noch nicht erreicht? Zählt nichts – der Mitschnitt fragt so, ob er das Ereignis
    -- noch braucht.
    function Auto.EventOpen(event)
        local per, tot = EventKeys(event)
        return Stored("per", per) < (Core.Num(Auto.LIMIT.event) or 0) and Stored("tot", tot) < (Core.Num(Auto.TOTAL.event) or 0)
    end

    -- Nur der Name des Ereignisses zählt; seine Werte (sie können geheim sein) fasst die Automatik nicht an.
    local function OnEvent(_, event)
        if not active then return end
        if Probe.Hard() then return end   -- nichts mehr festzuhalten (Eligible prüft „neu“ bei voller Ablage)
        if Auto.EVENTS[event] then held[Auto.EVENTS[event]] = nil end   -- das Ereignis der Station selbst: ein neuer Anlass
        if event == "PLAYER_REGEN_DISABLED" then
            C_Timer.After(Auto.COMBAT_DELAY, function()
                local kinds = CanInstant("G")
                if kinds then Start("G", kinds, event) end
            end)
        elseif Auto.INSTANT[event] then
            local key = Auto.EVENTS[event]
            local kinds = CanInstant(key)
            if kinds then
                lastHit[event] = GameTime()
                Start(key, kinds, event)
            end
        else
            Auto.ScanSoon(event)
        end
    end

    local function Standing()
        local speed = Invoke("GetUnitSpeed", "player")
        if not speed.ok then return true end
        if IsSecret(speed[1]) then return false end
        return (Core.Num(speed[1]) or 0) == 0
    end

    -- Gibt es schon eine vollständige Tempo-Messung (oder hat der Nutzer die der Automatik abgebrochen)?
    local function HasTempo(a, p)
        if a.noTempo then return true end
        local list = type(p.tempo) == "table" and p.tempo or {}
        for i = 1, #list do
            if type(list[i]) == "table" and not list[i].abort then return true end
        end
        return false
    end

    local function TempoWhenStill()
        if not active or prep ~= "wait" then return end
        if Core.InCombat() then
            Core.AfterCombat(TempoWhenStill, "ezCore.probe.auto.tempo", ADDON)
            return
        end
        tempoTries = tempoTries + 1
        local ready = (Standing() or tempoTries > Auto.TEMPO_TRIES) and not busy and not Probe.Running() and not Tempo.Running()
        if ready or tempoTries > Auto.TEMPO_TRIES * 3 then
            tempoTried, prep = true, nil
            if ready and not Probe.Full() then
                prep = "tempo"
                local ok = Tempo.Start({ quiet = true, onDone = function(result)
                    prep = nil
                    if stopping then return end
                    if type(result) == "table" and result.abort then
                        -- vom Nutzer abgebrochen (/ez probe tempo): die Automatik misst nicht von selbst noch einmal
                        local a = State(true)
                        a.noTempo = true
                    else
                        Say(L.PROBE_AUTO_TEMPO)
                    end
                    Prepare()
                end })
                if ok then
                    Say(L.PROBE_AUTO_TEMPO_START)
                    return
                end
                prep = nil
            end
            return Prepare()
        end
        C_Timer.After(Auto.TEMPO_RETRY, TempoWhenStill)
    end

    -- Einmalige Vorarbeit nach dem Einschalten: Dokumentation, dann Tempo, dann die Stationen. Nie im Kampf.
    function Prepare()
        if not active or prep then return end
        if Core.InCombat() then
            Core.AfterCombat(Prepare, "ezCore.probe.auto.prep", ADDON)
            return
        end
        ready = true
        local a, p = State(true)
        -- volle Ablage: keine Dokumentation, kein Tempo – nur noch Stationen, deren Art hier neu ist
        local full = Probe.Full()
        if full then Probe.SayFull(true) end
        if not full and type(p.doc) ~= "table" and not docTried and not Doc.Running() then
            docTried, prep = true, "doc"
            local ok = Doc.Start({ quiet = true, onDone = function(out)
                prep = nil
                local systems = type(out) == "table" and type(out.count) == "table" and out.count.systems or 0
                Say(L.PROBE_AUTO_DOC:format(systems))
                Prepare()
            end })
            if ok then return end
            prep = nil   -- lässt sich nicht laden: steht als „fehlt“ in der Ablage, weiter mit dem Tempo
        end
        if not full and not HasTempo(a, p) and not tempoTried and not Tempo.Running() then
            prep, tempoTries = "wait", 0
            return TempoWhenStill()
        end
        if #Auto.Open() == 0 then return Complete() end
        Auto.ScanSoon("AUTO_START", 0)
        PumpSoon()
    end

    local function Activate(delay)
        active, ready = true, false
        if not frame then
            frame = CreateFrame("Frame")
            frame:SetScript("OnEvent", OnEvent)
        end
        pruned = {}
        for event in pairs(Auto.EVENTS) do pcall(frame.RegisterEvent, frame, event) end
        lastSig = Signature()
        Prune()
        HookMap()
        -- der eigene Mitschnitt: solange Arten offen sind, hört er auf alles; danach nur noch auf Ereignisse, an denen
        -- etwas fehlt
        if not Record.Running() then
            Record.Start({ quiet = true, carry = true, narrow = #Auto.Open() == 0 })
        end
        tempoTried, docTried = false, false
        C_Timer.After(delay or Auto.START_DELAY, Prepare)
        if statusChanged then statusChanged() end
    end

    function Deactivate()
        local was = active
        active, ready = false, false
        if frame then pcall(frame.UnregisterAllEvents, frame) end
        queue, queued = {}, {}
        for _, key in ipairs({ "scan", "pump", "prep", "tempo" }) do Core.CancelAfterCombat("ezCore.probe.auto." .. key) end
        if prep == "tempo" and Tempo.Running() then
            stopping = true
            Tempo.Stop()   -- das bisher Gemessene bleibt (abort = true); beim nächsten Einschalten misst sie neu
            stopping = false
        end
        if prep ~= "doc" then prep = nil end   -- eine laufende Mitschrift schreibt zu Ende und räumt selbst auf
        if Record.Running() then
            -- der eigene Mitschnitt geht mit aus; einer von Hand läuft weiter – ohne die Grenze der Automatik je Ereignis
            if Record.auto then Record.Stop(false, true) else Record.Rearm() end
        end
        return was
    end

    -- Alle Arten, die hier zählen, sind erfasst: Die Automatik startet keine Station dieser Arten mehr – ihre Ereignisse
    -- sind abgemeldet (Prune), nichts wartet mehr. Ihr Mitschnitt bleibt, hört aber nur noch auf Ereignisse, an denen
    -- etwas fehlt (Record.Narrow): Proben, die nur an einem Ereignis hängen (Bosskampf, Würfeln, Herstellen), kämen sonst
    -- nie mehr von selbst. Sie sagt es einmal je Charakter, Lage und Kontinent und nennt, was noch nie eingetreten ist:
    -- das erste Mal seit dem Einschalten auch, wenn sie leise ist, danach (eine weitere Lage, ein weiterer Charakter) nur
    -- laut – sonst käme dieselbe Zeile über einen Monat mit mehreren Charakteren dutzendfach. Ein Mitschnitt von Hand
    -- bleibt, wie er ist.
    function Complete()
        local a = State(true)
        local sig = Signature()
        if type(a.said) ~= "table" then a.said = {} end
        local first, before = not a.said[sig], next(a.said) ~= nil
        a.complete, a.said[sig] = sig, true
        queue, queued = {}, {}
        Prune()
        if Record.Running() and Record.auto and not Record.Narrowed() then Record.Narrow() end
        if first then
            local waiting = Auto.WaitingText()
            local where = L.PROBE_AUTO_WHERE:format(Probe.CharIndex(), L["PROBE_LAGE_" .. Probe.Lage()])
            local text = L.PROBE_AUTO_COMPLETE:format(where, waiting ~= "" and (waiting .. " ") or "", Probe.StatusText())
            if before then Say(text) else ns.Print(text) end
        end
        if statusChanged then statusChanged() end
    end

    -- Lage gewechselt (Auto.LAGE_EVENTS: Instanz betreten oder verlassen, Gruppe, Bosskampf, anderer Kontinent): Die
    -- Beispiele des Mitschnitts zählen ab jetzt für die neue Lage (Record.SetLage), und was dort noch fehlt, ist wieder
    -- offen – Ereignisse kommen wieder dazu, der Mitschnitt hört wieder auf alles. Nach dem Betreten einer Instanz läuft
    -- „Dungeon“ nach Auto.INSTANCE_LATER Sekunden noch einmal (Position und Karte nach dem Laden).
    function Auto.LageChanged(event)
        -- ohne Automatik und Mitschnitt braucht niemand die Lage: nichts fragen (die Ereignisse kommen bei jedem Nutzer,
        -- im Schlachtzug GROUP_ROSTER_UPDATE in Schüben); der Zwischenspeicher gilt danach nicht mehr
        if not active and not Record.Running() then return Probe.ForgetLage() end
        local lage = Probe.Lage(true)
        Probe.Continent(true)
        if Record.Running() then Record.SetLage(lage) end
        if not active then return end
        -- Bosskampf: die Kampf-Station kurz danach in der neuen Lage (der Lauf vom Kampfbeginn ist dann fertig). Hier und
        -- nicht über Auto.EVENTS – dort wäre das Ereignis abgemeldet, solange außerhalb des Bosskampfs nichts offen ist.
        if event == "ENCOUNTER_START" then
            C_Timer.After(Auto.BOSS_DELAY, function()
                local kinds = CanInstant("G")
                if kinds then Start("G", kinds, event) end
            end)
        end
        if event == "PLAYER_ENTERING_WORLD" and lage:sub(1, 1) == "i" then
            C_Timer.After(Auto.INSTANCE_LATER, function()
                if not active then return end
                held.M = nil
                Auto.ScanSoon("INSTANCE_LATER", 0)
            end)
        end
        local sig = Signature()
        if sig == lastSig then return end
        lastSig = sig
        Prune()
        if #Auto.Open() > 0 then
            if Record.Running() and Record.auto and Record.Narrowed() then Record.Rearm() end
            Auto.ScanSoon(event or "LAGE")
        elseif ready then
            Complete()
        end
        if statusChanged then statusChanged() end
    end

    -- → true | false, Grund ("on"). Auch bei voller Ablage: Sie zählt dann und hält nur Neues fest (am Deckel selbst nur
    -- noch zählen) – sie sagt es einmal je Sitzung.
    function Auto.Enable()
        local a = State(true)
        if a.on == true and active then
            ns.Print(L.PROBE_AUTO_ALREADY:format(Auto.OpenText(Auto.OPEN_SHOWN)))
            return false, "on"
        end
        a.on, a.fullSaid, a.complete, a.said = true, nil, nil, nil
        Activate(Auto.START_DELAY)
        ns.Print(L.PROBE_AUTO_ON:format(Auto.OpenText(Auto.OPEN_SHOWN)))
        if Probe.Full() then Probe.SayFull(true) end
        return true
    end

    -- reason: nil (der Nutzer), "full" (die Probe ist voll – einmal sagen). → true, wenn sie an war
    function Auto.Disable(reason)
        local a = State()
        local was = active or (a ~= nil and a.on == true)
        if a then a.on = false end
        Deactivate()
        if reason == "full" then
            Probe.SayFull(true)
        elseif was then
            ns.Print(L.PROBE_AUTO_OFF:format(Probe.StatusText()) .. " " .. L.PROBE_SAVE_HINT)
        else
            ns.Print(L.PROBE_AUTO_NOT_ON)
        end
        if statusChanged then statusChanged() end
        return was
    end

    function Auto.Toggle()
        if Auto.Enabled() and active then
            Auto.Disable()
            return "off"
        end
        return Auto.Enable() and "on" or "full"
    end

    function Auto.SetQuiet(quiet)
        local a = State(true)
        a.quiet = quiet and true or false
        ns.Print(a.quiet and L.PROBE_AUTO_QUIET_ON or L.PROBE_AUTO_QUIET_OFF)
        return a.quiet
    end

    -- Nach dem Einloggen bzw. /reload: war die Automatik an, macht sie weiter (PLAYER_LOGIN). → true, wenn sie läuft
    function Auto.Resume()
        local a = State()
        if not a or a.on ~= true or active then return active end
        -- volle Ablage: sie macht trotzdem weiter (zählen, Neues festhalten) und sagt es einmal je Sitzung
        Activate(Auto.LOGIN_DELAY)
        local waiting = #Auto.Open() == 0 and Auto.WaitingText() or ""
        Say(L.PROBE_AUTO_RESUMED:format(Auto.OpenText(Auto.OPEN_SHOWN)) .. (waiting ~= "" and (" " .. waiting) or ""))
        return true
    end

    -- Nach „Probe leeren“ mit behaltener Einstellung: wieder anlaufen, wenn sie an ist – ohne eigene Meldung (den Satz
    -- „Daten-Probe geleert – Automatik bleibt an.“ sagt Probe.AskClear).
    function Auto.Restart()
        if not Auto.Enabled() or active then return false end
        Activate(Auto.START_DELAY)
        return true
    end

    -- Arbeitsspeicher der Automatik zurücksetzen, ohne die Ablage anzufassen (Leeren der Probe; Prüfungen: „Neuladen“).
    function Auto.Forget()
        Deactivate()
        inflight, lastHit, held = {}, {}, {}
        busy, scanWaiting, pumpWaiting, lastSig = false, false, false, nil
    end

    -- „/ez probe auto [an | aus | leise | laut | status]“ – ohne Wort: umschalten
    function Auto.Command(rest)
        local word = Core.ParseSlash(rest or "")
        if word == "" then
            Auto.Toggle()
        elseif word == "an" or word == "on" then
            Auto.Enable()
        elseif word == "aus" or word == "off" then
            Auto.Disable()
        elseif word == "leise" or word == "quiet" then
            Auto.SetQuiet(not Auto.Quiet())
        elseif word == "laut" or word == "loud" then
            Auto.SetQuiet(false)
        else
            ns.Print(Auto.StatusLine())
        end
    end

    Core.RegisterEvent(ADDON, "PLAYER_LOGIN", function() Auto.Resume() end)
    for _, event in ipairs(Auto.LAGE_EVENTS) do
        Core.RegisterEvent(ADDON, event, function() Auto.LageChanged(event) end)
    end
end

---------------------------------------------------------------------------
-- Bericht zum Kopieren (dieselben Zeilen wie später das Lese-Werkzeug)
---------------------------------------------------------------------------

-- Eine Beschreibung in einer Zeile. Felder einer Tabelle mit ihrem Beispielwert (Texte, Zahlen, Wahrheitswerte),
-- tiefere Tabellen nur mit ihrer Art.
local function Short(d, nested)
    if type(d) ~= "table" then return "?" end
    local k = d.k
    if k == "string" then
        return ('"%s"%s'):format(tostring(d.v), d.cut and "…" or "")
    elseif k == "number" or k == "boolean" then
        return tostring(d.v)
    elseif k == "table" then
        local names = {}
        for name, field in pairs(type(d.f) == "table" and d.f or {}) do
            local simple = not nested and type(field) == "table" and (field.k == "string" or field.k == "number" or field.k == "boolean")
            names[#names + 1] = simple and (name .. "=" .. Short(field, true)) or (name .. ":" .. tostring(type(field) == "table" and field.k))
        end
        table.sort(names)
        local text = "{" .. tostring(d.n)
        if d.len then text = text .. " #" .. d.len end
        if #names > 0 then text = text .. " " .. table.concat(names, " ", 1, math.min(#names, 12)) end
        if #names > 12 then text = text .. " …" end
        return text .. "}"
    end
    return tostring(k)
end

local function CallLine(st, call)
    local head = ("%s %s %s"):format(st or "?", call.id or "?", tostring(call.fn))
    if call.arg then head = head .. "(" .. call.arg .. ")" end
    if call.tag then head = head .. " [" .. call.tag .. "]" end
    if call.has then return head .. " = " .. call.has end
    if call.ok == false then return head .. " – " .. tostring(call.err) end
    if call.same then return ("%s » %d: %s"):format(head, call.n or 0, L.PROBE_SAME) end
    local parts = {}
    for i = 1, type(call.r) == "table" and #call.r or 0 do parts[i] = Short(call.r[i]) end
    return ("%s » %d: %s"):format(head, call.n or 0, table.concat(parts, ", "))
end

-- Zeilen des Berichts: Kopf, je Abfrage eine Zeile (die letzten maxLines), Ereignisse gezählt, Tempo, Dokumentation.
function Probe.Lines(maxLines)
    maxLines = maxLines or 400
    local s = Stamp()
    local lines = { L.PROBE_REPORT_HEAD:format(Core.Version and Core.Version(ADDON) or "?", s.version, s.build, s.locale),
        Probe.StatusText() }
    if not Core.InCombat() then FlushEvents() end   -- Zähler, die noch im Arbeitsspeicher warten
    local p = Probe.Data()
    if not p or Probe.Status().entries == 0 and not p.doc and #(p.tempo or {}) == 0 then
        lines[#lines + 1] = L.PROBE_EMPTY
        return lines
    end
    local calls = {}
    for _, run in ipairs(p.runs or {}) do
        for _, call in ipairs(run.calls or {}) do calls[#calls + 1] = CallLine(run.st, call) end
    end
    if #calls > maxLines then
        lines[#lines + 1] = L.PROBE_REPORT_TAIL:format(maxLines, #calls)
    end
    for i = math.max(1, #calls - maxLines + 1), #calls do lines[#lines + 1] = calls[i] end
    local names = {}
    for event in pairs(p.counts or {}) do names[#names + 1] = event end
    if #names > 0 then
        table.sort(names)
        lines[#lines + 1] = ""
        lines[#lines + 1] = L.PROBE_REPORT_EVENTS
        for _, event in ipairs(names) do lines[#lines + 1] = ("  %s ×%d"):format(event, p.counts[event]) end
    end
    -- die letzten Ereignisse mit ihrer Nutzlast
    local events = type(p.events) == "table" and p.events or {}
    if #events > 0 then
        local shown = math.min(#events, Probe.REPORT_EVENTS)
        lines[#lines + 1] = ""
        lines[#lines + 1] = L.PROBE_REPORT_PAYLOADS:format(shown, #events)
        for i = #events - shown + 1, #events do
            local e = events[i]
            local parts = {}
            for j = 1, type(e.a) == "table" and #e.a or 0 do parts[j] = Short(e.a[j]) end
            lines[#lines + 1] = ("  %s%s » %d: %s"):format(tostring(e.e), e.c and " [Kampf]" or "", e.n or 0, table.concat(parts, ", "))
        end
    end
    for _, t in ipairs(p.tempo or {}) do
        for _, kind in ipairs(Tempo.KINDS) do
            local r = t[kind]
            if type(r) == "table" then
                lines[#lines + 1] = L["PROBE_TEMPO_" .. kind]:format(r.n or 0, r.instant or 0, r.loaded or 0,
                    (r.failed or 0) + (r.none or 0), r.absent or 0, r.perSec or 0, r.sec or 0)
            end
        end
    end
    if type(p.doc) == "table" and type(p.doc.count) == "table" then
        local c = p.doc.count
        lines[#lines + 1] = L.PROBE_DOC_DONE:format(c.systems or 0, c.functions or 0, c.events or 0, c.tables or 0, SizeText(p.doc.bytes))
    end
    return lines
end

function Probe.Text() return table.concat(Probe.Lines(), "\n") end

function Probe.Show()
    return Core.TextDialog({ anchor = rawget(_G, "SettingsPanel"), title = L.PROBE_TITLE, hint = L.PROBE_HINT, text = Probe.Text(), readOnly = true, select = true,
        maxLetters = 0, owner = ADDON })
end

---------------------------------------------------------------------------
-- Leeren, Übersicht, Befehl
---------------------------------------------------------------------------

function Probe.AskClear()
    local s = Probe.Status()
    if s.entries == 0 and s.docSystems == 0 and s.tempo == 0 then
        ns.Print(L.PROBE_EMPTY)
        return nil
    end
    return Core.Confirm(L.PROBE_CLEAR_ASK:format(s.entries, SizeText(s.fileBytes)), function()
        Probe.Clear({ keepAuto = true })
        ns.Print(Probe.Auto.Enabled() and L.PROBE_CLEARED_AUTO_ON or L.PROBE_CLEARED_AUTO_OFF)
    end, { alert = true })
end

-- Übersicht: welche Stationen gibt es, welche liefen schon?
function Probe.Overview()
    local p = Probe.Data()
    local lines = { L.PROBE_STATIONS_HEAD }
    for _, key in ipairs(Probe.stationOrder) do
        local station = Probe.stations[key]
        local done = p and type(p.done) == "table" and Core.Num(p.done[key]) or 0
        lines[#lines + 1] = L.PROBE_STATION_LINE:format(station.words and station.words[1] or key:lower(), Probe.StationTitle(key),
            done > 0 and L.PROBE_STATION_DONE:format(done) or L.PROBE_STATION_OPEN)
    end
    -- Zielarten (jede zählt für die Automatik einzeln) und der Stand der Automatik: was erfasst ist, was noch fehlt
    local kinds = {}
    for _, entry in ipairs(Probe.Auto.KINDS) do
        local sub = entry[1]:match("^F:(.+)$")
        if sub then
            local n = Probe.Auto.Count(entry[1])
            kinds[#kinds + 1] = L.PROBE_KIND_ITEM:format(L["PROBE_KIND_" .. sub], n > 0 and L.PROBE_STATION_DONE:format(n) or L.PROBE_STATION_OPEN)
        end
    end
    lines[#lines + 1] = L.PROBE_KINDS_LINE:format(table.concat(kinds, ", "))
    lines[#lines + 1] = Probe.Auto.StatusLine()
    lines[#lines + 1] = Probe.StatusText()
    return lines
end

-- Hinweis für Helfer (ein Satz): welche Datei zu schicken ist und dass das Lese-Werkzeug Namen maskiert – samt der
-- Zufalls-Kennung dieser Ablage (noch keine Ablage: „neu“), damit der Helfer seinen Beitrag im Bericht wiederfindet.
function Probe.HelperText()
    local p = Probe.Data()
    local id = p and type(p.install) == "string" and p.install or L.PROBE_HELPER_NEW
    return L.PROBE_HELPER:format(id)
end

local SPECIAL = {}   -- Wort → fn (Sonderproben, ProbeStations.lua)
function Probe.AddSpecial(words, fn)
    for _, word in ipairs(words) do SPECIAL[word] = fn end
end

-- „/ez probe [hier | <Station> | auto [an | aus | leise] | an | aus | tempo | doku | status | zeigen | leeren | hilfe]“
function Probe.Command(rest)
    local word, more = Core.ParseSlash(rest or "")
    if word == "" then
        for _, line in ipairs(Probe.Overview()) do ns.Print(line) end
        ns.Print(L.PROBE_HELP_HINT)
    elseif word == "hier" or word == "here" or word == "station" then
        Probe.Here()
    elseif word == "auto" or word == "automatik" or word == "automatic" then
        Probe.Auto.Command(more)
    elseif word == "an" or word == "on" then
        if not Record.Start() and Record.Running() then ns.Print(L.PROBE_RECORD_RUNNING) end
    elseif word == "aus" or word == "off" then
        if not Record.Stop() then ns.Print(L.PROBE_RECORD_NOT_RUNNING) end
    elseif word == "mitschnitt" or word == "record" then
        Record.Toggle()
    elseif word == "tempo" then
        Tempo.Toggle()
    elseif word == "doku" or word == "doc" or word == "docs" then
        if not Doc.Start() and Doc.Running() then ns.Print(L.PROBE_DOC_RUNNING) end
    elseif word == "status" then
        ns.Print(Probe.StatusText())
    elseif word == "zeigen" or word == "show" then
        Probe.Show()
    elseif word == "leeren" or word == "clear" then
        Probe.AskClear()
    elseif word == "hilfe" or word == "help" then
        for _, line in ipairs(L.PROBE_HELP) do ns.Print(line) end
        ns.Print(Probe.HelperText())
    elseif word == "helfer" or word == "helper" then
        ns.Print(Probe.HelperText())
    elseif SPECIAL[word] then
        SPECIAL[word](more)
    else
        local key = Probe.FindStation(word)
        if key then
            Probe.Run(key)
        else
            ns.Print(L.PROBE_UNKNOWN:format(word))
            for _, line in ipairs(L.PROBE_HELP) do ns.Print(line) end
        end
    end
end

---------------------------------------------------------------------------
-- Einstellungsseite „ezCollection“ » „Erweitert“ (Leitlinie 3)
---------------------------------------------------------------------------

local statusRow, statusFrame

statusChanged = function()
    if not statusFrame then return end
    local text = Core.Peek(statusFrame, "Text")
    if type(text) == "table" and type(text.SetText) == "function" then pcall(text.SetText, text, Probe.StatusLabel()) end
end

-- Beschriftung der Statuszeile: „Daten-Probe: 412 Einträge (…), 96 KB“
function Probe.StatusLabel()
    return L.OPT_probeStatus .. ": " .. Probe.StatusText()
end

-- Blizzards Zeile zeigt den Text, mit dem sie angelegt wurde; nach jedem Aufbau der Zeile den aktuellen Stand setzen.
-- Nur hooksecurefunc und ein Aufruf an der Beschriftung (wie Core.WrapSettingsLabel).
do
    local mixin = rawget(_G, "SettingsListElementMixin")
    if type(mixin) == "table" and type(mixin.Init) == "function" and hooksecurefunc then
        hooksecurefunc(mixin, "Init", function(frame, initializer)
            if statusRow and initializer == statusRow then
                statusFrame = frame
                pcall(statusChanged)
            elseif frame == statusFrame then
                statusFrame = nil
            end
        end)
    end
end

function Probe.AddSettings(page)
    if type(page) ~= "table" or type(page.Button) ~= "function" then return false end
    -- Automatik und „leise“ als Kästchen (Einstellungs-Prüfung 19.11.2026, Abschnitt 4: ein Dauerzustand braucht eine
    -- sichtbare Anzeige; vorher Knöpfe „An / Aus“ ohne Stand). Der Stand bleibt im Speicher der Probe (Proxy), „leise“
    -- ist grau, solange die Automatik aus ist.
    if type(page.ProxyCheckbox) == "function" then
        page:ProxyCheckbox("probeAuto", function() return Probe.Auto.Enabled() end, function(on)
            if on then Probe.Auto.Enable() elseif Probe.Auto.Enabled() then Probe.Auto.Disable() end
        end, { default = false })
        page:ProxyCheckbox("probeAutoQuiet", function() return Probe.Auto.Quiet() end, function(on)
            if on ~= Probe.Auto.Quiet() then Probe.Auto.SetQuiet(on) end
        end, { default = false, parent = "probeAuto" })
    else
        page:Button(L.OPT_probeAuto, L.PROBE_AUTO_BUTTON, function() Probe.Auto.Toggle() end, L.OPT_probeAuto_TIP)
        page:Button(L.OPT_probeAutoQuiet, L.PROBE_AUTO_BUTTON, function() Probe.Auto.SetQuiet(not Probe.Auto.Quiet()) end,
            L.OPT_probeAutoQuiet_TIP)
    end
    page:Button(L.OPT_probeHelper, L.PROBE_HELPER_BUTTON, function() ns.Print(Probe.HelperText()) end, L.OPT_probeHelper_TIP)
    page:Button(L.OPT_probeHere, L.PROBE_HERE_BUTTON, function() Probe.Here() end, L.OPT_probeHere_TIP)
    -- Station R hat keinen Anlass (kein „when“): eigener Knopf (Leitlinie 3), im Kampf /ez probe rest
    page:Button(L.OPT_probeRest, L.PROBE_HERE_BUTTON, function() Probe.Run("R") end, L.OPT_probeRest_TIP)
    page:Button(L.OPT_probeRecord, L.PROBE_RECORD_BUTTON, function() Record.Toggle() end, L.OPT_probeRecord_TIP)
    page:Button(L.OPT_probeTempo, L.PROBE_TEMPO_BUTTON, function() Tempo.Toggle() end, L.OPT_probeTempo_TIP)
    page:Button(L.OPT_probeDoc, L.PROBE_DOC_BUTTON, function()
        if not Doc.Start() and Doc.Running() then ns.Print(L.PROBE_DOC_RUNNING) end
    end, L.OPT_probeDoc_TIP)
    if type(Probe.AddSpecialButtons) == "function" then Probe.AddSpecialButtons(page) end
    statusRow = page:Button(Probe.StatusLabel(), L.PROBE_STATUS_BUTTON, function()
        ns.Print(Probe.StatusText())
        Probe.Show()
    end, L.OPT_probeStatus_TIP)
    page:Button(L.OPT_probeClear, L.PROBE_CLEAR_BUTTON, function() Probe.AskClear() end, L.OPT_probeClear_TIP)
    return true
end
