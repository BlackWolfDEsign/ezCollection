local Core = ezCore   -- nil, wenn tools/merge.lua die Datei lädt (LuaJIT, ohne Spiel)

--[[
    Anonyme Fassung der Entdecker-Datenbank für „Beitrag vorbereiten“ (Nutzer, 24.11.2026, wörtlich: „Natürlich anonymer
    Export“). Bis dahin schickten Helfer die Rohdatei des Trägers: ohne Namen von Spielern und Realms, aber mit
    sekundengenauen Zeitpunkten, Realm-Laufnummern und Namen aus dem Spiel in ihrer Sprache – bereinigt wurde erst beim
    Projekt, also nachdem die Datei schon an einem öffentlichen Issue hing.

    EINE Quelle für Spiel und Werkzeug: diese Datei braucht weder WoW noch ezCore. ezCore lädt sie über die TOC
    (Core.DB.Anon), tools/merge.lua mit dofile – dieselben Regeln bereinigen im Spiel und prüfen beim Zusammenführen noch
    einmal. Ein zweiter Durchgang ändert nichts mehr (tools/Tests/merge_test.lua prüft es).

      Anon.Clean(db, schema, tick)   → { meta = { id, builds, consent, updated, mapYards }, cache/held/seen = { [Tabelle]
                                       = … } }, Funde. Die Vorlage bleibt unverändert. schema = { tables = { [Name] =
                                       { life, explorer, v } }, fields = { [Feld] = true }, kinds = Keys.KINDS }
      Anon.Export(db, schema, tick)  → dasselbe für den Versand: dazu meta.tables (Versionen), meta.anon = 1, von den
                                       seltenen Gegnern nur die Nummern (tools/merge.lua hält damit ihre Fundorte heraus),
                                       ohne Fundorte von seltenen Gegnern, Kisten und Objekten ohne bekannte Art
                                       (schema.objKinds, schema.rareTiers; dieselbe Regel wie ExplorerSpot in merge.lua)
      Anon.Text(daten, tick)         → „ezWorldDB={…}“ – reiner Datentext, bei gleichen Daten bytegleich
      Anon.Wrap(art, körper, info)   → Beitrag zum Kopieren: Kopfzeile, darunter der Körper (art "zlib": Base64 eines
                                       zlib-Stroms, "text": der Datentext selbst). info = { id, build, size }
      Anon.Unwrap(text)              → { art, körper, id, build, size } oder nil (kein Beitrag in dieser Form)
      Anon.Rows(daten)               → Zahl der Sätze der obersten Ebene (für „leer“ und die Anzeige)
    tick() darf zwischendurch abgeben (Core.Sliced): die Schlüssel einer Ebene werden vorher gesammelt, ein Satz, der
    inzwischen dazukommt, fehlt dann nur.

    Was wegfällt: freier Text (Tabelle text, Notschlüssel, jeder Text außer kurzen Kennwörtern, Lehrer-Arten und der
    Fraktionsseite), die Felder as, realms und src, alles Unbekannte, Entdecker-Wissen und Anon.LOCKED. Zeitpunkte werden
    auf den Tag gerundet. Bleibt: Nummern, Zähler, Orte, Build – und die Zufallskennung meta.id, damit ein Beitrag nicht
    doppelt zählt und sich zurückziehen lässt.
]]

local Anon = {}

Anon.DAY = 86400
Anon.ID_MAX = 10000000
Anon.LIVES = { "cache", "held", "seen" }
-- gesperrt, solange Frage 7 der Daten-Probe offen ist (verdeckte Gegenstände)
Anon.LOCKED = { item = "Frage 7 (verdeckte Gegenstände)", itemVar = "Frage 7 (verdeckte Gegenstände)",
    reveal = "Frage 7 und Entdecker-Wissen" }
-- as, realms: Angaben über andere; src: Herkunft eines Fundorts (eigene Ernte oder eingelesene Sicherung, siehe
-- Anon.BACKUP) – wird hier ausgewertet und nie weitergegeben
Anon.DROP_FIELDS = { as = true, realms = true, src = true }
-- Felder, die nur die Auslieferung schreibt (orig: Zahl der Herkünfte je Satz bzw. je Eintrag einer Liste, DB.FIELDS):
-- aus einem Beitrag fallen sie weg, damit kein Beitrag seine Stütze selbst angibt
Anon.SHIP_FIELDS = { orig = true }
-- Fundorte aus einer eingelesenen Sicherung (Core.Gathering.ImportText: src = "backup") hat dieser Spieler nie selbst
-- gesehen. Sie zählen nicht als Herkunft – sonst stützte eine weitergegebene Sicherung sich selbst (Durchsicht 24.11.2026).
-- Nach der ersten eigenen Ernte dort (src = "own", Discovery.lua Place) zählt die Herkunft, aber nur mit einem Vorgang:
-- Zähler und „zuerst gesehen“ stammen aus der Sicherung. Dazu legt ImportText je Objekt seine Art an (obj = { kind });
-- ohne eigene Beobachtung (nur kind und Stempel) zählt auch die nicht.
Anon.BACKUP, Anon.BACKUP_OWN = "backup", "own"
Anon.OBJ_UNSEEN = { kind = true, t = true, t0 = true, tf = true, b = true, b0 = true, pt = true, src = true }
Anon.TIME_FIELDS = { t = true, t0 = true, tf = true }
-- Untertabellen, deren Werte Zeitstempel sind (npc.roles = { vendor = zuletzt, … }, offer.svc[…].at = { [npcID] =
-- zuletzt }): jeder Wert auf den Tag gerundet
Anon.TIME_MAPS = { roles = true, at = true }
-- Fraktionsseite eines NPC (NpcSide in Discovery.lua): die einzigen Texte in Großbuchstaben, nur unter side
Anon.SIDES = { A = true, H = true, N = true }

local function NoTick() end

local function IsWord(text) return type(text) == "string" and #text <= 16 and text:match("^%l[%w]*$") ~= nil end
local function IsId(k) return type(k) == "number" and k == math.floor(k) and k >= 0 and k <= Anon.ID_MAX end
-- Lehrer-Art aus Keys.Offer (DBKeys.lua): "c:<Klasse>", "pet:<Klasse>", "p:<Berufsnummer>" ("o" ist ein Kennwort).
-- Notschlüssel "~…" und Rezeptnamen "L:…" tragen Namen und fallen weiter weg. Seit ezData (22.11.2026) streng: nach
-- c: und pet: nur ein Klassen-Kürzel in Großbuchstaben (classFile, etwa MAGE), nach p: nur Ziffern – so kommt kein
-- Name („c:Ein Name“, „c:Thrall“) durch.
local OFFER_FORM = { c = "^%u+$", pet = "^%u+$", p = "^%d+$" }
local function IsOfferKey(text)
    if type(text) ~= "string" or #text > 24 then return false end
    local prefix, rest = text:match("^(%l+):(.+)$")
    local form = prefix and OFFER_FORM[prefix]
    return form ~= nil and rest:match(form) ~= nil
end
local function Finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end
local function IsSide(k, v) return k == "side" and type(v) == "string" and Anon.SIDES[v] == true end
Anon.IsWord, Anon.IsId, Anon.IsOfferKey, Anon.Finite, Anon.IsSide = IsWord, IsId, IsOfferKey, Finite, IsSide

-- Schlüssel einer Ebene, bevor jemand dazwischen abgibt
local function KeyList(t)
    local list = {}
    for k in pairs(t) do list[#list + 1] = k end
    return list
end

-- Fundorte ohne die aus Sicherungen (Anon.BACKUP): spot[Karte][Art][ID] = Liste von Orten; die Liste bleibt lückenlos.
-- Ändert die Vorlage nicht. » neue Tabelle, Zahl der weggelassenen Orte
local function SpotsWithoutBackups(spots)
    local backups = 0
    local function Places(list)
        local keys, out = {}, {}
        for k, v in pairs(list) do if type(k) == "number" and type(v) == "table" then keys[#keys + 1] = k end end
        if #keys == 0 then return list end        -- keine Liste: die Plausibilität meldet sie (RowProblem in merge.lua)
        table.sort(keys)
        for _, k in ipairs(keys) do
            local place = list[k]
            if place.src == Anon.BACKUP then
                backups = backups + 1
            elseif place.src == Anon.BACKUP_OWN then
                local own = {}
                for f, v in pairs(place) do own[f] = v end
                own.cnt, own.t0 = 1, nil
                out[#out + 1] = own
            else
                out[#out + 1] = place
            end
        end
        return out
    end
    local function Level(t, depth)
        if type(t) ~= "table" then return t end
        if depth == 3 then return Places(t) end
        local out = {}
        for k, v in pairs(t) do out[k] = Level(v, depth + 1) end
        return out
    end
    return Level(spots, 0), backups
end

-- Objekte ohne die, von denen nur die Art bekannt ist (Anon.OBJ_UNSEEN). » neue Tabelle, Zahl der weggelassenen Sätze
local function SeenObjects(rows)
    local out, unseen = {}, 0
    for id, row in pairs(rows) do
        local seen = type(row) ~= "table"
        for k in pairs(type(row) == "table" and row or {}) do if not Anon.OBJ_UNSEEN[k] then seen = true break end end
        if seen then out[id] = row else unseen = unseen + 1 end
    end
    return out, unseen
end

-- Tabelle rekursiv säubern: Schlüssel nur Nummern, bekannte Felder oder Kennwörter; Werte nur Zahlen, Wahrheitswerte,
-- Kennwörter und Tabellen davon. » saubere Tabelle (nil, wenn leer), Zahl der weggelassenen Werte
local function CleanValue(value, fields, depth, parent, tick)
    if depth > 12 then return nil, 1 end
    tick()
    local out, dropped = {}, 0
    for _, k in ipairs(KeyList(value)) do
        local v = value[k]
        -- ganze Zahlen bleiben auch außerhalb des Bereichs stehen: die Plausibilität meldet sie (Ausreißer)
        local keyOk = (type(k) == "number" and k == math.floor(k))
            or (type(k) == "string" and (fields[k] or IsWord(k) or IsOfferKey(k)) and not Anon.DROP_FIELDS[k]
                and not Anon.SHIP_FIELDS[k])
        if v == nil then
            -- inzwischen entfernt (Scheiben im Spiel)
        elseif not keyOk then
            if k ~= "src" then dropped = dropped + 1 end        -- src ist ausgewertet, nichts Auffälliges
        elseif type(v) == "table" then
            local sub, d = CleanValue(v, fields, depth + 1, k, tick)
            dropped = dropped + d
            if sub then out[k] = sub end
        elseif Finite(v) then
            if (type(k) == "string" and Anon.TIME_FIELDS[k]) or Anon.TIME_MAPS[parent] then v = v - v % Anon.DAY end
            out[k] = v
        elseif type(v) == "boolean" or IsWord(v) or IsOfferKey(v) or IsSide(k, v) then
            out[k] = v
        else
            dropped = dropped + 1
        end
    end
    if next(out) == nil then return nil, dropped end
    return out, dropped
end

-- ezWorldDB » { meta = { id, builds, consent, updated }, cache/held/seen = { [Tabelle] = … } }, Funde
function Anon.Clean(db, schema, tick)
    tick = tick or NoTick
    local notes = { dropped = 0, tables = {}, locked = {}, unknown = {}, versions = {}, backups = 0 }
    local meta = type(db.meta) == "table" and db.meta or {}
    local versions = type(meta.tables) == "table" and meta.tables or {}
    local builds = type(meta.builds) == "table" and meta.builds or {}
    local consent = type(meta.consent) == "table" and meta.consent or nil
    -- Welle 23c (A66): Kartengrößen in Yards (keine private Angabe), nur gültige Paare
    local sizes
    for map, wh in pairs(type(meta.mapYards) == "table" and meta.mapYards or {}) do
        local w, h = type(wh) == "table" and wh[1], type(wh) == "table" and wh[2]
        if IsId(map) and map > 0 and Finite(w) and Finite(h) and w > 0 and h > 0 and w < 1e6 and h < 1e6 then
            sizes = sizes or {}
            sizes[map] = { w, h }
        end
    end
    local out = { meta = {
        mapYards = sizes,
        id = (Finite(meta.id) or IsWord(meta.id) or (type(meta.id) == "string" and meta.id:match("^%x+$"))) and meta.id or nil,
        builds = { lo = Finite(builds.lo) and builds.lo or nil, hi = Finite(builds.hi) and builds.hi or nil },
        updated = Finite(meta.updated) and meta.updated - meta.updated % Anon.DAY or nil,
        consent = consent and { lic = type(consent.lic) == "string" and consent.lic or nil,
            t = Finite(consent.t) and consent.t - consent.t % Anon.DAY or nil } or nil,
    } }
    for _, life in ipairs(Anon.LIVES) do
        local layer = db[life]
        if type(layer) == "table" then
            for _, name in ipairs(KeyList(layer)) do
                local rows = layer[name]
                local spec = schema.tables[name]
                if type(name) ~= "string" or not spec or spec.life ~= life then
                    notes.unknown[#notes.unknown + 1] = life .. "." .. tostring(name)
                elseif spec.explorer or Anon.LOCKED[name] then
                    notes.locked[name] = true
                elseif type(rows) == "table" and type(versions[name]) == "table" and (versions[name].v or 1) ~= spec.v then
                    -- andere Version der Tabelle als heute (Umzug der Datenbank noch offen oder neueres Addon): ihre
                    -- Felder bedeuten etwas anderes. Ohne Vermerk (meta.tables fehlt) gilt die heutige, ein Vermerk ohne
                    -- v heißt 1 (wie EnsureTable in DB.lua).
                    local v = versions[name].v or 1
                    if next(rows) ~= nil then notes.versions[name] = Finite(v) and v or "unlesbar" end
                elseif type(rows) == "table" then
                    local n = 0
                    if name == "spot" then rows, n = SpotsWithoutBackups(rows) end
                    if name == "obj" then rows, n = SeenObjects(rows) end
                    notes.backups = notes.backups + n
                    local entry = versions[name]
                    local before = type(entry) == "table" and entry.v or nil
                    local clean, dropped = CleanValue(rows, schema.fields, 0, nil, tick)
                    notes.dropped = notes.dropped + dropped
                    if type(entry) == "table" and entry.v ~= before then
                        -- im Spiel zwischen zwei Scheiben umgezogen (Versionsschritt): gemischt gelesen, bleibt weg
                        notes.versions[name] = Finite(before) and before or "unlesbar"
                    elseif clean then
                        out[life] = out[life] or {}
                        out[life][name] = clean
                        notes.tables[#notes.tables + 1] = name
                    end
                end
            end
        end
    end
    -- ezData (22.11.2026): Entdecker-Arten in spot (Keys.KINDS, explorer = true: vignette, book) fallen weg
    local spots = out.seen and out.seen.spot
    for _, byKind in pairs(spots or {}) do
        for kind in pairs(byKind) do
            local k = schema.kinds and schema.kinds[kind]
            if k and k.explorer then
                byKind[kind] = nil
                notes.locked[kind] = true
            end
        end
    end
    -- Kennungen seltener Gegner (Tabelle rare ist gesperrt, ihre Fundorte in spot sind Entdecker-Wissen): nur die Nummern
    notes.rare = {}
    local rare = type(db.seen) == "table" and type(db.seen.rare) == "table" and db.seen.rare or {}
    for id in pairs(rare) do if IsId(id) then notes.rare[id] = true end end
    -- freier Text (Tabelle text) fällt immer weg
    if type(db.text) == "table" then notes.text = true end
    table.sort(notes.tables)
    table.sort(notes.unknown)
    return out, notes
end

-- Fundorte, die Entdecker-Wissen sind (Pfad [Karte][Art][ID]), aus einem schon bereinigten Export nehmen
local function DropExplorerSpots(out, notes, schema)
    local seen = out.seen or {}
    local rare = {}
    for id in pairs(notes.rare) do rare[id] = true end
    for id, row in pairs(seen.npc or {}) do
        if type(row) == "table" and schema.rareTiers[row.tier] then rare[id] = true end
    end
    local kinds = {}
    for id, row in pairs(seen.obj or {}) do kinds[id] = type(row) == "table" and row.kind or nil end
    for map, byKind in pairs(seen.spot or {}) do
        for id in pairs(byKind.npc or {}) do if rare[id] then byKind.npc[id] = nil end end
        for id in pairs(byKind.object or {}) do
            if schema.objKinds[kinds[id]] ~= "lookup" then byKind.object[id] = nil end
        end
        for kind, list in pairs(byKind) do if next(list) == nil then byKind[kind] = nil end end
        if next(byKind) == nil then seen.spot[map] = nil end
    end
    if seen.spot and next(seen.spot) == nil then seen.spot = nil end
end

function Anon.Export(db, schema, tick)
    local out, notes = Anon.Clean(db, schema, tick)
    DropExplorerSpots(out, notes, schema)
    local versions = {}
    for _, name in ipairs(notes.tables) do versions[name] = { v = schema.tables[name].v or 1 } end
    out.meta.tables, out.meta.anon = versions, 1
    if next(notes.rare) ~= nil then
        local rare = {}
        for id in pairs(notes.rare) do rare[id] = { cnt = 1 } end
        out.seen = out.seen or {}
        out.seen.rare = rare
    end
    return out, notes
end

function Anon.Rows(data)
    local n = 0
    for _, life in ipairs(Anon.LIVES) do
        for name, rows in pairs(type(data[life]) == "table" and data[life] or {}) do
            if name ~= "rare" then for _ in pairs(rows) do n = n + 1 end end
        end
    end
    return n
end

---------------------------------------------------------------------------
-- Datentext: gelesen wird er nur mit dem reinen Datenleser (tools/probe.lua, M.ReadData)
---------------------------------------------------------------------------

Anon.CARRIER = "ezWorldDB"

local function KeyLess(a, b)
    if type(a) == type(b) then return a < b end
    return type(a) == "number"
end

local function NumberText(n)
    if n == math.floor(n) and n >= -2 ^ 53 and n <= 2 ^ 53 then return ("%.0f"):format(n) end   -- %d reicht im Client nur bis 2^31
    return ("%.14g"):format(n)
end

local RESERVED = {}
for word in ("and break do else elseif end false for function if in local nil not or repeat return then true until while"):gmatch("%a+") do
    RESERVED[word] = true
end

local function KeyText(k)
    if type(k) == "number" then return "[" .. NumberText(k) .. "]=" end
    if k:match("^[%a_][%w_]*$") and not RESERVED[k] then return k .. "=" end
    return '["' .. k .. '"]='
end

-- Nur Werte, die Anon.Clean durchlässt: Texte sind Kennwörter bzw. die Lizenz im Kopf (%q zur Sicherheit)
local function Write(value, out, tick)
    if type(value) == "table" then
        tick()
        local keys = KeyList(value)
        table.sort(keys, KeyLess)
        out[#out + 1] = "{"
        for i, k in ipairs(keys) do
            if i > 1 then out[#out + 1] = "," end
            out[#out + 1] = KeyText(k)
            Write(value[k], out, tick)
        end
        out[#out + 1] = "}"
    elseif type(value) == "number" then
        out[#out + 1] = NumberText(value)
    elseif type(value) == "boolean" then
        out[#out + 1] = value and "true" or "false"
    else
        out[#out + 1] = ("%q"):format(value)
    end
end

function Anon.Text(data, tick)
    local out = { Anon.CARRIER, "=" }
    Write(data, out, type(tick) == "function" and tick or NoTick)
    return table.concat(out)
end

---------------------------------------------------------------------------
-- Beitrag zum Kopieren: „ezCollection-Beitrag;1;<Kennung>;<Build>;<Art>;<Zeichen des Datentexts>“
---------------------------------------------------------------------------

Anon.HEAD, Anon.FORMAT = "ezCollection-Beitrag", 1
Anon.LINE = 1000   -- Zeichen je Zeile des gepackten Körpers

function Anon.Wrap(kind, body, info)
    if kind == "zlib" then
        local lines = {}
        for i = 1, #body, Anon.LINE do lines[#lines + 1] = body:sub(i, i + Anon.LINE - 1) end
        body = table.concat(lines, "\n")
    end
    -- „;Ende“ beendet auch das Base64 (kein Zeichen davon): Text hinter dem Beitrag stört nicht
    return ("%s;%d;%s;%s;%s;%.0f\n%s\n;Ende\n"):format(Anon.HEAD, Anon.FORMAT, tostring(info.id), tostring(info.build), kind,
        info.size, body)
end

function Anon.Unwrap(text)
    if type(text) ~= "string" then return nil end
    local v, id, build, kind, size, body =
        text:match("ezCollection%-Beitrag;(%d+);([^;\n]*);([^;\n]*);(%l+);(%d+)[ \t\r]*\n(.*)$")
    if tonumber(v) ~= Anon.FORMAT then return nil end
    return { kind = kind, body = body, id = id, build = build, size = tonumber(size) }
end

if Core and Core.DB then Core.DB.Anon = Anon end
return Anon
