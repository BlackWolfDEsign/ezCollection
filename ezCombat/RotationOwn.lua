local _, ns = ...
local L = ns.L
local Core = ezCore
local Spells = Core.Spells
local Rotation = ns.Rotation

-- Eigene Rotationen je Charakter (Wunsch des Nutzers vom 15.11.2026, Spieltest Hexenmeister Stufe 10: „eigene Rotation
-- ingame anlegen möglich?“; entschieden 16.11.2026 mit Entwurf A „Spickzettel“, nach Empfehlung „als Kopie einer
-- Vorlage beginnen“, docs/roadmap/ezCombat.md). Eine eigene Rotation beginnt immer als Kopie einer Vorlage (Knopf
-- „Als eigene Rotation speichern“ hinter „Anpassen“ auf der Seite „Rotation“): Abschnitte, Reihenfolge, Bedingungen
-- und Texte kommen mit; danach lassen sich Schritte aus dem Zauberbuch hinzufügen (Bedingung aus einer festen
-- Auswahl, keine freie Eingabe), selbst hinzugefügte wieder entfernen und die Bedingung jedes Schritts aus derselben
-- Auswahl setzen. Ein/Aus und Reihenfolge laufen wie bei den Vorlagen über RotationEdit.lua.
--
-- Gespeichert je Charakter, eigenes Format mit Versionsnummer (der Profil-Export bleibt unberührt):
--   ezCombatDB.ownRotations[Charakter] = { v = 1, next = <nächste Nummer>, list = { Eintrag … } }
--   Eintrag = { key = "own-<n>", name = Text, class = "KLASSE", tree, from = Schlüssel der Vorlage, fromName = Text,
--               how, note, source, sources, counters (aus der Vorlage), steps = { Schritt … } }
-- Ein Schritt hat die Felder der Vorlagen (RotationData.lua, Kopf) und dazu added = true, wenn er selbst hinzugefügt
-- ist. Jeder Schritt trägt ein festes key-Feld (Ein/Aus und Reihenfolge hängen daran).
-- Teilen als Text (Core.Serialize, Kennung „EZ1:“): { kind = "ezCombat.rotation", v = 1, class, name, from, tree,
-- how, note, source, sources, counters, steps } – die Schritte in der wirksamen Reihenfolge, ausgeschaltete mit
-- off = true. Beim Übernehmen geprüft: Art, Version, eigene Klasse, jedes Feld und jeder Wert (Own.Problems: dieselben
-- Regeln wie der Daten-Lint der Vorlagen, soweit sie zur Laufzeit gelten), Zauber, die dieser Client kennt, und
-- seit Welle 26 keine Zauber einer anderen Klasse (Own.ForeignSpells, laut Client-Tabellen über Spells.ClassOf).
-- Was der Client liefert (Name, Symbol, Ränge, gelernt), steht nie im Speicher – nur Zauber-IDs und Logik.
local Own = {}
ns.RotationOwn = Own

Own.VERSION = 1
Own.KIND = "ezCombat.rotation"
Own.MAX = 20            -- eigene Rotationen je Charakter
Own.MAX_STEPS = 80      -- Schritte je Rotation
Own.NAME_MAX = 40       -- Zeichen im Namen
Own.TEXT_MAX = 300      -- Bytes je Text (Schritt, how, note) beim Übernehmen

-- Die feste Auswahl der Bedingungen (Reihenfolge = Menü). Jede Auswahl setzt when und ihre Schwelle; refresh nur bei
-- „fehlt oder läuft aus“. „Bei Proc“ ist die Bedingung „reactive“ des Motors (das Spiel gibt den Zauber frei), damit
-- keine Aura-ID von Hand nötig ist.
Own.CONDITIONS = {
    { key = "ready", when = "ready" },
    { key = "dot", when = "dot" },
    { key = "dot:missing", when = "dot", refresh = "missing" },
    { key = "dot:cast", when = "dot", refresh = "cast" },
    { key = "buff", when = "buff" },
    { key = "buff:missing", when = "buff", refresh = "missing" },
    { key = "buff:cast", when = "buff", refresh = "cast" },
    { key = "proc", when = "reactive" },
    { key = "lowmana:20", when = "lowmana", max = 20 },
    { key = "lowmana:30", when = "lowmana", max = 30 },
    { key = "lowmana:50", when = "lowmana", max = 50 },
    { key = "finisher:3", when = "finisher", cp = 3 },
    { key = "finisher:4", when = "finisher", cp = 4 },
    { key = "finisher:5", when = "finisher", cp = 5 },
    { key = "filler", when = "filler" },
    { key = "manual", when = "manual" },
}
local CONDITION_BY_KEY = {}
for _, entry in ipairs(Own.CONDITIONS) do CONDITION_BY_KEY[entry.key] = entry end
-- Bedingung, mit der ein neuer Schritt je Abschnitt beginnt.
Own.SECTION_DEFAULT = { prep = "buff", opener = "ready", combat = "ready", cooldown = "ready", aoe = "ready",
    situational = "manual" }

-- Felder eines Schritts (wie der Daten-Lint der Vorlagen, ohne race/class der Volksfähigkeiten) und ihre Prüfung.
local ONCE = { target = true, combat = true }
local UNITS = { target = true, pettarget = true }
local HANDS = { main = true, off = true }
-- Pflichtwert je when (wie Tests/rotation_lint.lua, REQUIRED)
local REQUIRED = { finisher = "cp", rage = "min", energy = "min", mana = "min", lowmana = "max", proc = "aura",
    item = "item", totemslot = "slot" }
local ENTRY_FIELDS = { key = true, name = true, class = true, tree = true, from = true, fromName = true, how = true,
    note = true, source = true, sources = true, counters = true, steps = true }
local EXPORT_FIELDS = { kind = true, v = true }

local function CharKey() return Core.charKey or "?" end

-- Tiefe Kopie über ezCores Core.CopyTable (Gesamtreview 18.11.2026, T16-7): vorher gab die eigene Fassung ab Tiefe 8 die
-- ORIGINAL-Tabelle zurück (Kopie und Original teilten sich den Rest); jetzt fällt Tieferes weg, nie eine geteilte
-- Referenz. Eigene Rotationen sind höchstens fünf Ebenen tief, die Grenze bleibt 8. Der Name Own.Copy bleibt.
local COPY_DEPTH = 8
local function Copy(value) return Core.CopyTable(value, COPY_DEPTH) end
Own.Copy = Copy

local function Fmt(text, ...)
    local ok, result = pcall(string.format, text, ...)
    return ok and result or text
end

---------------------------------------------------------------------------
-- Speicher
---------------------------------------------------------------------------

-- Speicher dieses Charakters; create = true legt ihn an. Ein Stand mit anderer oder ohne Versionsnummer wird nicht
-- angefasst (nil), damit eine spätere Fassung ihn umziehen kann.
local function Store(create)
    local db = ns.db
    if type(db) ~= "table" then return nil end
    if type(db.ownRotations) ~= "table" then
        if not create then return nil end
        db.ownRotations = {}
    end
    local store = db.ownRotations[CharKey()]
    if type(store) ~= "table" then
        if not create then return nil end
        store = { v = Own.VERSION, next = 1, list = {} }
        db.ownRotations[CharKey()] = store
    end
    if store.v ~= Own.VERSION or type(store.list) ~= "table" then return nil end
    return store
end

local revision = 0          -- zählt jede Änderung (Rotation.ForClass merkt sich die Liste bis dahin)
local built = setmetatable({}, { __mode = "k" })   -- Eintrag → Rotations-Objekt (gleiche Tabelle, solange es ihn gibt)
local cache = { list = {} }
local reported = setmetatable({}, { __mode = "k" })

-- Rotations-Objekt eines Eintrags: dieselbe Form wie eine Vorlage (key, tree, name, how, note, source, steps …),
-- dazu own (der Eintrag) und class. Die Schritte sind die gespeicherten Tabellen selbst.
local function Build(entry)
    local rotation = built[entry]
    if not rotation then
        rotation = {}
        built[entry] = rotation
    end
    rotation.key, rotation.tree, rotation.class, rotation.own = entry.key, entry.tree, entry.class, entry
    rotation.name = { entry.name, entry.name }
    rotation.how, rotation.note, rotation.counters, rotation.steps = entry.how, entry.note, entry.counters, entry.steps
    rotation.source, rotation.sources = entry.source, entry.sources
    return rotation
end

-- Eigene Rotationen dieser Klasse (nur des eingeloggten Charakters, nur gültige) – dieselbe Tabelle, bis sich etwas
-- ändert. Ein ungültiger Eintrag (von Hand verändert, ältere Fassung) bleibt im Speicher und steht in der Fehlerliste.
function Own.ForClass(class)
    class = class or ns.playerClass
    local store = Store(false)
    if cache.store == store and cache.rev == revision and cache.class == class and cache.char == CharKey() then
        return cache.list
    end
    local list = {}
    for _, entry in ipairs(store and store.list or {}) do
        if type(entry) == "table" and entry.class == class then
            local problems = Own.Problems(entry, class)
            if #problems == 0 then
                list[#list + 1] = Build(entry)
            elseif not reported[entry] then
                reported[entry] = true
                Core.Error("ezCombat", Fmt(L.ROTATION_OWN_INVALID, tostring(entry.key), problems[1]),
                    "RotationOwn.ForClass")
            end
        end
    end
    cache.store, cache.rev, cache.class, cache.char, cache.list = store, revision, class, CharKey(), list
    return list
end

-- „Eigene Rotation?“ hat eine Quelle: Rotation.IsOwn (Rotation.lua).
Own.IsOwn = Rotation.IsOwn

-- Gespeicherter Eintrag zu einem Schlüssel („own-3“) oder nil.
function Own.Get(key)
    local store = Store(false)
    for _, entry in ipairs(store and store.list or {}) do
        if type(entry) == "table" and entry.key == key then return entry end
    end
    return nil
end

function Own.Count()
    local store = Store(false)
    return store and #store.list or 0
end

-- Nach jeder Änderung: Liste neu, Zustand zurück, Motor und Seite neu, Auswahl der Einstellungen neu.
local function Changed()
    revision = revision + 1
    if ns.RotationState then ns.RotationState.Reset("all") end
    if Rotation.ChoiceValues then Rotation.ChoiceValues() end
    ns.Try("Rotation", Rotation.Update)     -- ein Fehler hält die Zuhörer nicht auf (T7-NE2)
    for _, fn in ipairs(Rotation.listeners) do pcall(fn) end
end
Own.Changed = Changed

---------------------------------------------------------------------------
-- Prüfung (Own.Problems): dieselben Regeln wie der Daten-Lint der Vorlagen (Tests/rotation_lint.lua, Punkte 1, 3, 4,
-- 6, 7), soweit sie ohne Quelltext gelten – für gespeicherte, kopierte und übernommene Rotationen.
---------------------------------------------------------------------------

local function IsPair(value, max)
    if type(value) ~= "table" or type(value[1]) ~= "string" or type(value[2]) ~= "string" then return false end
    for key in pairs(value) do
        if key ~= 1 and key ~= 2 then return false end
    end
    return #value[1] <= (max or Own.TEXT_MAX) and #value[2] <= (max or Own.TEXT_MAX)
end

local function IsIDs(value)
    if type(value) == "number" then return value > 0 end
    if type(value) ~= "table" or #value == 0 then return false end
    for key, id in pairs(value) do
        if type(key) ~= "number" or type(id) ~= "number" or id <= 0 then return false end
    end
    return true
end

-- Nur Zahlen, Texte, Wahrheitswerte und Tabellen davon (keine Funktionen), nicht tiefer als vier Ebenen.
local function PlainData(value, depth)
    local kind = type(value)
    if kind == "number" or kind == "string" or kind == "boolean" then return true end
    if kind ~= "table" or depth > 4 then return false end
    for key, inner in pairs(value) do
        if (type(key) ~= "string" and type(key) ~= "number") or not PlainData(inner, depth + 1) then return false end
    end
    return true
end

local function IsHttps(value) return type(value) == "string" and value:find("^https://") ~= nil and #value <= 300 end

-- Typ je weiterer Bedingung (need) – dieselbe Tabelle wie im Daten-Lint (Tests/rotation_lint.lua, NEED): Ein Wert
-- vom falschen Typ aus einem geteilten Text darf die Prüfungen des Motors nicht bei jeder Bewertung werfen lassen.
local NEED_TYPE = { combat = "bool", target = "true", solo = "true", grouped = "true", leveling = "bool", level = "range",
    known = "ids", unknown = "ids", seen = "ids", aura = "table", noaura = "table", cp = "range", rage = "range",
    energy = "range", mana = "range", form = "number", stealth = "bool", pet = "bool", inrange = "number",
    outrange = "number", moving = "bool", queued = "false", usable = "number", unusable = "number", item = "table",
    weapon = "table", enemy = "table", totem = "table", counter = "table", aoe = "bool" }

-- Nur diese Felder (allowed: { Feld = true }).
local function OnlyFields(value, allowed)
    for key in pairs(value) do
        if not allowed[key] then return false end
    end
    return true
end

local function OptNumber(value) return value == nil or type(value) == "number" end

local function IsRange(value)
    return type(value) == "table" and OnlyFields(value, { min = true, max = true }) and OptNumber(value.min)
        and OptNumber(value.max) and (value.min ~= nil or value.max ~= nil)
end

-- Liste von Texten ({ "elite", "rareelite" }); nil erlaubt, wenn optional.
local function IsTexts(value, optional)
    if value == nil then return optional == true end
    if type(value) ~= "table" or #value == 0 then return false end
    for key, text in pairs(value) do
        if type(key) ~= "number" or type(text) ~= "string" or #text > 40 then return false end
    end
    return true
end

-- Aura-Verweis: Zauber-ID, Name einer Buff-Gruppe („bane“) oder Liste davon (RotationChecks.lua, NeedAura/FindAura).
local function IsAuraRef(value)
    local function One(one)
        if type(one) == "number" then return one > 0 end
        return type(one) == "string" and one ~= "" and #one <= 40
    end
    if type(value) ~= "table" then return One(value) end
    if #value == 0 then return false end
    for key, one in pairs(value) do
        if type(key) ~= "number" or not One(one) then return false end
    end
    return true
end

local AURA_UNITS = { player = true, target = true, pet = true, pettarget = true }
local AURA_FILTERS = { HELPFUL = true, HARMFUL = true }

-- Form der Tabellen-Bedingungen, wie sie die Prüfungen des Motors lesen (RotationChecks.lua, CHECKS.<Schlüssel>):
-- Ein Text statt einer Zahl (min = "2") ließe dort jeden Vergleich werfen und den Vorschlag ausfallen.
local NEED_SHAPE = {
    item = function(v)
        return OnlyFields(v, { id = true, min = true }) and IsIDs(v.id) and OptNumber(v.min)
    end,
    aura = function(v)
        return OnlyFields(v, { id = true, unit = true, mine = true, filter = true, min = true, max = true, left = true })
            and IsAuraRef(v.id) and (v.unit == nil or AURA_UNITS[v.unit] == true)
            and (v.mine == nil or type(v.mine) == "boolean") and (v.filter == nil or AURA_FILTERS[v.filter] == true)
            and OptNumber(v.min) and OptNumber(v.max) and (v.left == nil or IsRange(v.left))
    end,
    enemy = function(v)
        return OnlyFields(v, { rank = true, norank = true, type = true }) and next(v) ~= nil
            and IsTexts(v.rank, true) and IsTexts(v.norank, true) and IsTexts(v.type, true)
    end,
    totem = function(v)
        return OnlyFields(v, { slot = true, up = true }) and type(v.slot) == "number" and v.slot >= 1 and v.slot <= 4
            and (v.up == nil or type(v.up) == "boolean")
    end,
    counter = function(v)
        return OnlyFields(v, { name = true, min = true, max = true, oldest = true }) and type(v.name) == "string"
            and v.name ~= "" and OptNumber(v.min) and OptNumber(v.max)
            and (v.oldest == nil or (type(v.oldest) == "table" and OnlyFields(v.oldest, { min = true })
                and type(v.oldest.min) == "number"))
    end,
    weapon = function(v)
        return OnlyFields(v, { hand = true, type = true }) and (v.hand == nil or HANDS[v.hand] == true)
            and IsTexts(v.type, true)
    end,
}
NEED_SHAPE.noaura = NEED_SHAPE.aura

local function TypeOK(kind, value, key)
    if kind == "bool" then return type(value) == "boolean" end
    if kind == "true" then return value == true end
    if kind == "false" then return value == false end
    if kind == "number" then return type(value) == "number" end
    if kind == "table" then return type(value) == "table" and NEED_SHAPE[key] ~= nil and NEED_SHAPE[key](value) end
    if kind == "range" then return IsRange(value) end
    if kind == "ids" then return IsIDs(value) end
    return false
end

-- Ganze Zahl von low bis high (NaN und unendlich fallen durch).
local function IsWhole(value, low, high)
    return type(value) == "number" and value >= low and value <= high and value == math.floor(value)
end

-- Zahlen je Zauber-ID ({ [5176] = 2 }) für die Zähler (RotationState.lua, Amount): ganze Zahlen von 0 bis max.
local function IsAmounts(value, max)
    if type(value) ~= "table" then return false end
    for id, amount in pairs(value) do
        if type(id) ~= "number" or id <= 0 or not IsWhole(amount, 0, max) then return false end
    end
    return true
end

-- Ein Zähler der Rotation (counters[Name]), wie RotationState.lua ihn liest. Grenzen (T7-NE1, Gesamtreview
-- 18.11.2026): max ganz von 1 bis State.COUNTER_MAX, gain/spend ganz von 0 bis max, fallback.seconds über 0 bis
-- State.COUNTER_SECONDS_MAX – sonst hängt ein geteilter Text den Client in einer Schleife auf.
local function CounterOK(def)
    local State = ns.RotationState
    if type(def) ~= "table" or not IsWhole(def.max, 1, State.COUNTER_MAX) then return false end
    local seconds = type(def.fallback) == "table" and def.fallback.seconds
    return OnlyFields(def, { aura = true, known = true, max = true, gain = true, spend = true,
        fallback = true, each = true }) and IsAmounts(def.gain, def.max)
        and (def.spend == nil or IsAmounts(def.spend, def.max)) and (def.aura == nil or IsAuraRef(def.aura))
        and (def.known == nil or IsIDs(def.known)) and (def.each == nil or type(def.each) == "boolean")
        and (def.fallback == nil or (type(def.fallback) == "table" and OnlyFields(def.fallback, { seconds = true })
            and type(seconds) == "number" and seconds > 0 and seconds <= State.COUNTER_SECONDS_MAX))
end

local STEP_CHECKS = {
    id = function(v) return type(v) == "number" and v > 0 and v == math.floor(v) end,
    kind = function(v) return Rotation.KINDS[v] ~= nil end,
    when = function(v) return Rotation.CONDITIONS[v] ~= nil end,
    text = function(v) return IsPair(v) end,
    guess = function(v) return IsPair(v) end,
    key = function(v) return type(v) == "string" and v ~= "" and #v <= 80 end,
    buff = function(v) return type(v) == "string" and Spells.BuffGroup(v, nil) ~= nil end,
    refresh = function(v) return v == "missing" or v == "cast" or (type(v) == "number" and v > 0) end,
    once = function(v) return ONCE[v] == true end,
    side = function(v) return v == true end,
    hold = function(v) return v == true end,
    optional = function(v) return v == true end,
    added = function(v) return v == true end,
    off = function(v) return v == true end,
    mine = function(v) return v == false end,
    need = function(v)
        if type(v) ~= "table" or not PlainData(v, 1) then return false end
        for key, value in pairs(v) do
            if Rotation.CHECKS[key] == nil or not TypeOK(NEED_TYPE[key], value, key) then return false end
        end
        return true
    end,
    aura = function(v) return type(v) == "number" and v > 0 end,
    stacks = function(v) return type(v) == "number" and v > 0 end,
    unit = function(v) return UNITS[v] == true end,
    group = function(v) return type(v) == "string" and v ~= "" and #v <= 40 end,
    cp = function(v) return type(v) == "number" and v >= 1 and v <= 5 end,
    min = function(v) return type(v) == "number" and v >= 0 end,
    max = function(v) return type(v) == "number" and v >= 0 end,
    item = function(v) return IsIDs(v) end,
    hand = function(v) return HANDS[v] == true end,
    slot = function(v) return type(v) == "number" and v >= 1 and v <= 4 end,
    burst = function(v) return v == true end,
}

-- Ein Problem in Worten (deutsch oder englisch, Leitlinie 7): Text ROTATION_OWN_PROBLEM_<key>, bei einem Schritt mit
-- dessen Nummer davor („Schritt 3: …“). Die Texte erscheinen beim Übernehmen im Chat und in der Fehlerliste.
local function Problem(out, index, key, ...)
    local text = Fmt(L["ROTATION_OWN_PROBLEM_" .. key], ...)
    if index then text = Fmt(L.ROTATION_OWN_PROBLEM_AT, index, text) end
    out[#out + 1] = text
end

local function StepProblems(step, index, counters, out)
    if type(step) ~= "table" then
        Problem(out, index, "NOSTEP")
        return
    end
    for field, value in pairs(step) do
        local fn = STEP_CHECKS[field]
        if not fn then
            Problem(out, index, "FIELD", tostring(field))
        elseif not fn(value) then
            Problem(out, index, "VALUE", tostring(field))
        end
    end
    for _, field in ipairs({ "id", "kind", "key" }) do
        if step[field] == nil then Problem(out, index, "MISSING", field) end
    end
    local when = step.when or "ready"
    local required = REQUIRED[when]
    if required and step[required] == nil then Problem(out, index, "REQUIRED", required, when) end
    if step.refresh ~= nil and when ~= "dot" and when ~= "buff" then Problem(out, index, "RULE", "refresh", "when = dot, buff") end
    if step.kind == "longbuff" and when ~= "buff" then Problem(out, index, "RULE", "kind = longbuff", "when = buff") end
    if step.burst ~= nil and step.kind ~= "cooldown" then Problem(out, index, "RULE", "burst", "kind = cooldown") end
    if step.buff ~= nil and (when ~= "buff" or step.group ~= nil) then
        Problem(out, index, "RULE", "buff", "when = buff, group = nil")
    end
    local counter = type(step.need) == "table" and step.need.counter or nil
    if counter ~= nil and not (type(counter) == "table" and type(counters) == "table" and counters[counter.name] ~= nil) then
        Problem(out, index, "COUNTER")
    end
end

-- Probleme eines Eintrags (gespeichert, Kopie oder übernommen): { Text … }, leer = in Ordnung. class: die Klasse,
-- zu der er gehören muss (nil: nicht prüfen).
function Own.Problems(entry, class)
    local out = {}
    if type(entry) ~= "table" then
        Problem(out, nil, "NOTABLE")
        return out
    end
    for field in pairs(entry) do
        if not ENTRY_FIELDS[field] then Problem(out, nil, "FIELD", tostring(field)) end
    end
    if type(entry.key) ~= "string" or not entry.key:find("^own%-%d+$") then Problem(out, nil, "KEY") end
    if type(entry.name) ~= "string" or entry.name == "" or #entry.name > Own.NAME_MAX * 4 then Problem(out, nil, "NAME") end
    if type(entry.class) ~= "string" or (class ~= nil and entry.class ~= class) then Problem(out, nil, "CLASS") end
    if entry.tree ~= nil and not (type(entry.tree) == "number" and entry.tree >= 1 and entry.tree <= 3) then
        Problem(out, nil, "TREE")
    end
    for _, field in ipairs({ "from", "fromName" }) do
        if entry[field] ~= nil and (type(entry[field]) ~= "string" or #entry[field] > 120) then
            Problem(out, nil, "VALUE", field)
        end
    end
    for _, field in ipairs({ "how", "note" }) do
        if entry[field] ~= nil and not IsPair(entry[field], Own.TEXT_MAX * 3) then Problem(out, nil, "PAIR", field) end
    end
    if entry.source ~= nil and not IsHttps(entry.source) then Problem(out, nil, "HTTPS", "source") end
    if entry.sources ~= nil then
        local ok = type(entry.sources) == "table"
        for _, url in pairs(ok and entry.sources or {}) do ok = ok and IsHttps(url) end
        if not ok then Problem(out, nil, "HTTPS", "sources") end
    end
    if entry.counters ~= nil then
        local ok = type(entry.counters) == "table" and PlainData(entry.counters, 1)
        for name, def in pairs(ok and entry.counters or {}) do
            ok = ok and type(name) == "string" and CounterOK(def)
        end
        if not ok then Problem(out, nil, "COUNTERS") end
    end
    local steps = entry.steps
    if type(steps) ~= "table" or #steps == 0 or #steps > Own.MAX_STEPS then
        Problem(out, nil, "STEPS", Own.MAX_STEPS)
        return out
    end
    local keys = {}
    for index, step in ipairs(steps) do
        StepProblems(step, index, entry.counters, out)
        if type(step) == "table" and step.key ~= nil then
            if keys[step.key] then Problem(out, index, "DUPLICATE", tostring(step.key)) end
            keys[step.key] = true
        end
    end
    for key in pairs(steps) do
        if type(key) ~= "number" or key > #steps then
            Problem(out, nil, "LIST")
            break
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Anlegen als Kopie, Umbenennen, Löschen
---------------------------------------------------------------------------

-- Schritte einer Rotation in der wirksamen Reihenfolge (Anpassungen dieses Charakters), ohne die Volksfähigkeiten
-- (die reiht der Motor selbst ein), je als Kopie mit festem key; ausgeschaltete tragen off = true, ein optionaler,
-- der eingeschaltet ist, verliert optional (sein Zustand steht dann in off).
function Own.Effective(rotation)
    local steps = {}
    for _, step in ipairs(Rotation.Steps(rotation)) do
        if not step.race then
            local copy = Copy(step)
            copy.key = Rotation.StepKey(step)
            copy.optional, copy.off = nil, nil
            if not Rotation.StepEnabled(rotation, step) then copy.off = true end
            steps[#steps + 1] = copy
        end
    end
    return steps
end

-- Freier Name: „<Vorlage> (eigene)“, bei Gleichstand mit Nummer.
function Own.DefaultName(rotation)
    local base = Fmt(L.ROTATION_OWN_DEFAULT_NAME, Rotation.Name(rotation))
    local taken = {}
    local store = Store(false)
    for _, entry in ipairs(store and store.list or {}) do
        if type(entry) == "table" then taken[entry.name] = true end
    end
    if not taken[base] then return base end
    for n = 2, Own.MAX + 1 do
        local name = base .. " " .. n
        if not taken[name] then return name end
    end
    return base
end

-- Name säubern: ohne „|“ (Steuerzeichen des Spiels), ohne Leerraum am Rand, höchstens Own.NAME_MAX Zeichen.
function Own.CleanName(name)
    if Core.IsSecret(name) or type(name) ~= "string" then return nil end
    name = Core.Trim((name:gsub("|", ""):gsub("[%c]", " ")))   -- Core.Trim (Gesamtreview 18.11.2026, T16-15)
    if name == "" then return nil end
    local chars, out = 0, {}
    for char in name:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        chars = chars + 1
        if chars > Own.NAME_MAX then break end
        out[#out + 1] = char
    end
    return table.concat(out)
end

-- Eintrag als Kopie einer Rotation (noch nicht gespeichert; key bleibt leer) – auch für den Daten-Lint.
function Own.CopyOf(rotation, name)
    if type(rotation) ~= "table" then return nil end
    local fromName = Rotation.Name(rotation)
    local entry = { name = Own.CleanName(name) or Own.DefaultName(rotation), class = Rotation.ClassOf and
        Rotation.ClassOf(rotation) or ns.playerClass, tree = rotation.tree, steps = Own.Effective(rotation),
        how = Copy(rotation.how), note = Copy(rotation.note), source = rotation.source, sources = Copy(rotation.sources),
        counters = Copy(rotation.counters) }
    if Own.IsOwn(rotation) then
        entry.from, entry.fromName = rotation.own.from, rotation.own.fromName
    else
        entry.from, entry.fromName = rotation.key, fromName
    end
    if type(entry.tree) ~= "number" or entry.tree < 1 or entry.tree > 3 then entry.tree = nil end
    return entry
end

-- Ausgeschaltete Schritte (off = true) in die Anpassungen schreiben und aus den Schritten nehmen.
local function ApplyOff(entry)
    local off = {}
    for _, step in ipairs(entry.steps) do
        if step.off then
            off[#off + 1] = step.key
            step.off = nil
        end
    end
    if #off == 0 or not Rotation.SetStepEnabled then return end
    local rotation = Build(entry)
    for _, key in ipairs(off) do
        for _, step in ipairs(entry.steps) do
            if step.key == key then Rotation.SetStepEnabled(rotation, step, false) end
        end
    end
end

-- Einen fertigen Eintrag aufnehmen (neuer Schlüssel). → Schlüssel oder nil, Grund ("max", "invalid", "db").
local function Add(entry)
    local store = Store(true)
    if not store then return nil, "db" end
    if #store.list >= Own.MAX then return nil, "max" end
    local number = tonumber(store.next) or 1
    for _, other in ipairs(store.list) do
        local n = type(other) == "table" and type(other.key) == "string" and tonumber(other.key:match("^own%-(%d+)$"))
        if n and n >= number then number = n + 1 end
    end
    entry.key = "own-" .. number
    store.next = number + 1
    local problems = Own.Problems(entry, ns.playerClass)
    if #problems > 0 then return nil, "invalid", problems[1] end
    table.insert(store.list, entry)
    revision = revision + 1
    ApplyOff(entry)
    Changed()
    return entry.key
end

-- „Als eigene Rotation speichern“: Kopie der Rotation (mit den Anpassungen dieses Charakters) unter dem Namen.
-- select = true wählt sie gleich. → Schlüssel oder nil, Grund.
function Own.Create(rotation, name, select)
    local entry = Own.CopyOf(rotation, name)
    if not entry then return nil, "invalid" end
    entry.class = ns.playerClass
    local key, reason, detail = Add(entry)
    if key and select then Rotation.Select(key) end
    return key, reason, detail
end

function Own.Rename(key, name)
    local entry = Own.Get(key)
    name = Own.CleanName(name)
    if not (entry and name) or entry.name == name then return false end
    entry.name = name
    Changed()
    return true
end

-- Löschen: Eintrag, seine Anpassungen und – war sie gewählt – die Wahl („Nach Talentbaum“). → true, wenn gelöscht
function Own.Delete(key)
    local store = Store(false)
    if not store then return false end
    for index, entry in ipairs(store.list) do
        if type(entry) == "table" and entry.key == key then
            local rotation = Build(entry)
            -- immer (ResetEdits prüft selbst): auch Anpassungen entfernter Schritte, die EditCount nicht mehr zählt –
            -- sonst erbte die nächste eigene Rotation mit demselben Schlüssel (own-1) sie
            if Rotation.ResetEdits then Rotation.ResetEdits(rotation) end
            table.remove(store.list, index)
            built[entry] = nil
            if next(store.list) == nil then ns.db.ownRotations[CharKey()] = nil end
            if type(ns.db.rotations) == "table" and ns.db.rotations[CharKey()] == key then Rotation.Select("auto") end
            Changed()
            return true
        end
    end
    return false
end

---------------------------------------------------------------------------
-- Schritte: hinzufügen, entfernen, Bedingung
---------------------------------------------------------------------------

local function FindStep(entry, stepKey)
    for index, step in ipairs(entry and entry.steps or {}) do
        if step.key == stepKey then return step, index end
    end
    return nil
end

-- Art eines Schritts im Abschnitt zur Bedingung: Die Auswahl verschiebt nie den Abschnitt.
local function KindFor(section, when)
    if section == "prep" then return when == "buff" and "longbuff" or "prepare" end
    if section == "combat" then
        if when == "filler" then return "filler" end
        if when == "dot" or when == "buff" then return "maintain" end
        if when == "lowmana" then return "resource" end
        return "priority"
    end
    return section
end
Own.KindFor = KindFor

-- Bedingungs-Schlüssel der Auswahl, wenn der Schritt genau einer entspricht (sonst nil: Bedingung der Vorlage).
function Own.ConditionOf(step)
    if type(step) ~= "table" then return nil end
    for _, entry in ipairs(Own.CONDITIONS) do
        if (step.when or "ready") == entry.when and step.refresh == entry.refresh and step.max == entry.max
            and step.cp == entry.cp and step.need == nil and step.aura == nil and step.stacks == nil
            and step.min == nil and step.group == nil and step.buff == nil and step.once == nil then
            return entry.key
        end
    end
    return nil
end

-- Text einer Auswahl im Menü und ihr Satz in Alltagssprache (Spickzettel, Tooltip).
function Own.ConditionLabel(key)
    local entry = CONDITION_BY_KEY[key]
    if not entry then return nil end
    local base = key:gsub(":.*$", "")
    return Fmt(L["ROTATION_OWN_COND_" .. base .. (entry.refresh and ("_" .. entry.refresh) or "")], entry.max or entry.cp)
end
function Own.ConditionTip(key)
    local entry = CONDITION_BY_KEY[key]
    if not entry then return nil end
    local base = key:gsub(":.*$", "")
    return Fmt(L["ROTATION_OWN_COND_" .. base .. (entry.refresh and ("_" .. entry.refresh) or "") .. "_TIP"],
        entry.max or entry.cp)
end

-- Bedingung eines Schritts aus der Auswahl setzen. Die Werte der alten Bedingung (Schwellen, Aura, Stapel, Wahlgruppe,
-- einmal je Ziel, weitere Bedingungen) entfallen, ebenso der Text der Vorlage – der Satz folgt dann der Auswahl.
-- → true, wenn geändert
function Own.SetCondition(key, stepKey, condition)
    local entry = Own.Get(key)
    local step = FindStep(entry, stepKey)
    local choice = CONDITION_BY_KEY[condition]
    if not (step and choice) or Own.ConditionOf(step) == condition then return false end
    local section = Rotation.KINDS[step.kind] or "combat"
    step.when, step.refresh, step.max, step.cp = choice.when, choice.refresh, choice.max, choice.cp
    step.min, step.stacks, step.aura, step.group, step.buff, step.once, step.need = nil, nil, nil, nil, nil, nil, nil
    step.unit, step.mine, step.item, step.hand, step.slot, step.text = nil, nil, nil, nil, nil, nil
    step.guess = nil   -- die Annahme gehörte zur alten Bedingung
    step.kind = KindFor(section, choice.when)
    if step.kind ~= "cooldown" then step.burst = nil end
    Changed()
    return true
end

-- Gelernte Zauber zum Hinzufügen: { { id = niedrigster Rang, name } … } nach Namen (aus ezCores Zauberwissen).
function Own.KnownSpells()
    local list = {}
    if type(Spells.ForEachKnown) ~= "function" then return list end
    -- ns.Try statt nacktem pcall (Gesamtreview 18.11.2026, T7-1): ein Fehler steht in der Fehlerliste
    ns.Try("KnownSpells", Spells.ForEachKnown, function(entry)
        if type(entry) ~= "table" or type(entry.name) ~= "string" or type(entry.ranks) ~= "table" then return end
        local low
        for rank, id in pairs(entry.ranks) do
            if type(rank) == "number" and type(id) == "number" and (not low or rank < low) then low = rank end
        end
        local id = low and entry.ranks[low] or entry.maxID
        if type(id) == "number" then list[#list + 1] = { id = id, name = entry.name } end
    end)
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- Schritt aus dem Zauberbuch hinzufügen: am Ende des Abschnitts, Bedingung nach Own.SECTION_DEFAULT (eine Auswahl
-- passt sie an). → Schritt-Schlüssel oder nil
function Own.AddStep(key, section, spellID)
    local entry = Own.Get(key)
    if not entry or not Own.SECTION_DEFAULT[section] then return nil end
    if type(spellID) ~= "number" or spellID <= 0 or #entry.steps >= Own.MAX_STEPS then return nil end
    local choice = CONDITION_BY_KEY[Own.SECTION_DEFAULT[section] or "ready"]
    local base, stepKey, n = "own:" .. spellID, nil, 1
    stepKey = base
    while FindStep(entry, stepKey) do
        n = n + 1
        stepKey = base .. "#" .. n
    end
    local step = { id = spellID, key = stepKey, added = true, when = choice.when, refresh = choice.refresh,
        max = choice.max, cp = choice.cp, kind = KindFor(section, choice.when) }
    -- hinter den letzten Schritt desselben Abschnitts (sonst ans Ende)
    local at = #entry.steps + 1
    for index, other in ipairs(entry.steps) do
        if Rotation.SectionOf(other) == section then at = index + 1 end
    end
    table.insert(entry.steps, at, step)
    Changed()
    return stepKey
end

-- Fähigkeit eines Schritts tauschen (Zauberbuch-Seite „Rotation“: Klick auf einen Schritt, Entscheidung des Nutzers
-- vom 20.11.2026 „Klick tauscht, Ziehen schiebt“). Der Schritt behält Schlüssel, Platz, Ein/Aus und Abschnitt; die
-- Bedingung bleibt, wenn sie einer Auswahl entspricht (Own.ConditionOf), sonst gilt die des Abschnitts
-- (Own.SECTION_DEFAULT). Alles, was am alten Zauber hing (Text, Buff-Schlüssel, Aura, Wahlgruppe, Schwellen), entfällt;
-- der Schritt gilt danach als selbst hinzugefügt (added, mit Kreuz zum Entfernen). → true, wenn getauscht
function Own.SwapSpell(key, stepKey, spellID)
    local entry = Own.Get(key)
    local old, index = FindStep(entry, stepKey)
    if not old or type(spellID) ~= "number" or spellID <= 0 then return false end
    if old.id == spellID and old.buff == nil and old.group == nil then return false end
    local section = Rotation.SectionOf(old) or "combat"
    if not Own.SECTION_DEFAULT[section] then section = "combat" end
    local condition = Own.ConditionOf(old) or Own.SECTION_DEFAULT[section]
    local choice = CONDITION_BY_KEY[condition] or CONDITION_BY_KEY.ready
    local step = { id = spellID, key = old.key, added = true, when = choice.when, refresh = choice.refresh,
        max = choice.max, cp = choice.cp, kind = KindFor(section, choice.when) }
    if step.kind == "cooldown" then step.burst = old.burst end
    entry.steps[index] = step
    Changed()
    return true
end

-- Selbst hinzugefügten Schritt entfernen (Schritte der Vorlage bleiben ein/aus). → true, wenn entfernt
function Own.RemoveStep(key, stepKey)
    local entry = Own.Get(key)
    local step, index = FindStep(entry, stepKey)
    if not (step and step.added) or #entry.steps <= 1 then return false end
    table.remove(entry.steps, index)
    -- Ein/Aus und Platz des Schritts streichen: ein später hinzugefügter Schritt mit demselben Schlüssel beginnt neu
    if Rotation.ForgetStepEdits then Rotation.ForgetStepEdits(Build(entry), stepKey) end
    Changed()
    return true
end

---------------------------------------------------------------------------
-- Teilen als Text
---------------------------------------------------------------------------

-- Text zum Kopieren für eine eigene Rotation (oder jede andere – dann als Kopie). → Text oder nil, Grund
function Own.Export(rotation)
    if type(rotation) == "string" then
        local entry = Own.Get(rotation)
        rotation = entry and Build(entry)
    end
    if type(rotation) ~= "table" then return nil, "none" end
    local entry = Own.CopyOf(rotation, Own.IsOwn(rotation) and rotation.own.name or Rotation.Name(rotation))
    local data = { kind = Own.KIND, v = Own.VERSION }
    for field, value in pairs(entry) do
        if field ~= "key" then data[field] = value end
    end
    return Core.Serialize(data)
end

-- Texte aus fremder Hand säubern: ohne „|“ (Steuerzeichen, Links, Bilder des Spiels).
local function Sanitize(value, depth)
    depth = depth or 0
    if type(value) == "string" then return (value:gsub("|", "")) end
    if type(value) ~= "table" or depth > 6 then return value end
    local out = {}
    for key, inner in pairs(value) do out[Sanitize(key, depth + 1)] = Sanitize(inner, depth + 1) end
    return out
end

-- Zauber einer anderen Klasse in den Schritten (Welle 26, Paket modul/ezcombat-klasse; Fund 4 / Empfehlung k der
-- Gegenprüfung des Spickzettels, Welle 24): laut ezCores Spells.ClassOf (Client-Tabellen, SkillLineAbility). Fremd ist
-- nur, was die Tabelle sicher einer anderen Klasse zuordnet und nicht zugleich der eigenen; fehlt der Helfer oder kennt
-- die Tabelle einen Zauber nicht (Volks-, Berufs- und Allgemeinzauber, einrangige Talente), gilt er als eigen – lieber
-- übernehmen als einen Zauber abweisen, den der Teilende kennt (Leitlinie 11). Geprüft werden nur die Zauber der
-- Schritte (id), nicht die Auren in den Bedingungen: die dürfen von anderen Klassen stammen.
-- → { { id = Zauber-ID, class = Klassen-Token } … } in der Reihenfolge der Schritte (jede ID einmal), Quelle als Text
function Own.ForeignSpells(steps, class)
    local out, seen, source = {}, {}, nil
    local ClassOf = Spells and Spells.ClassOf
    if type(ClassOf) ~= "function" or type(class) ~= "string" or type(steps) ~= "table" then return out end
    local CD = Core.ClientData
    for _, step in ipairs(steps) do
        local id = type(step) == "table" and step.id or nil
        if type(id) == "number" and not seen[id] then
            seen[id] = true
            local owner, from = ClassOf(id)
            if type(owner) == "string" and owner ~= class
                and not (CD and type(CD.ClassSpell) == "function" and CD.ClassSpell(id, class)) then
                out[#out + 1] = { id = id, class = owner }
                source = source or from
            end
        end
    end
    return out, source
end

Own.FOREIGN_NAMES = 5   -- so viele fremde Zauber nennt der Grund mit Namen, die übrigen als Zahl

-- Die fremden Zauber in Worten: „Feuerball (Magier), Frostblitz (Magier) – laut Client-Tabellen (…)“.
function Own.ForeignText(list, source)
    local names = {}
    for index, entry in ipairs(type(list) == "table" and list or {}) do
        if index > Own.FOREIGN_NAMES then
            -- Rest über ezCores Core.More: „und noch 1“ statt „und 1 weitere“ (Gegenprüfung Welle 26)
            names[#names] = Fmt(L.ROTATION_OWN_FOREIGN_MORE, names[#names], Core.More(#list - Own.FOREIGN_NAMES, true))
            break
        end
        local name = Spells.Name and Spells.Name(entry.id)
        if type(name) ~= "string" or name == "" then name = "#" .. tostring(entry.id) end
        local className = Core.ClassName and Core.ClassName(entry.class) or entry.class
        names[#names + 1] = Fmt(L.ROTATION_OWN_FOREIGN_SPELL, name, tostring(className))
    end
    local text = table.concat(names, ", ")
    if type(source) == "string" and source ~= "" then text = text .. " – " .. source end
    return text
end

-- Text prüfen und (ohne dry) als neue eigene Rotation aufnehmen. → Eintrag bzw. Schlüssel, oder nil, Grund, Hinweis
-- Gründe: "empty", "prefix", "version", "syntax", "depth" (Core.Deserialize), "kind", "class", "invalid",
-- "spell" (eine Zauber-ID kennt dieser Client nicht), "foreign" (Zauber einer anderen Klasse laut Client-Tabellen,
-- Own.ForeignSpells; der Hinweis nennt sie und die Quelle), "max", "db".
function Own.Import(text, opts)
    opts = opts or {}
    local data, why = Core.Deserialize(text)
    if data == nil then return nil, why or "syntax" end
    if type(data) ~= "table" or data.kind ~= Own.KIND then return nil, "kind" end
    if type(data.v) ~= "number" or data.v > Own.VERSION or data.v < 1 then return nil, "version" end
    if data.class ~= ns.playerClass then return nil, "class", tostring(data.class) end
    data = Sanitize(data)
    local entry = {}
    for field, value in pairs(data) do
        if not EXPORT_FIELDS[field] then entry[field] = value end
    end
    entry.key = "own-1"         -- Platzhalter für die Prüfung; Add vergibt den echten
    entry.name = Own.CleanName(entry.name) or L.ROTATION_OWN_IMPORTED
    local problems = Own.Problems(entry, ns.playerClass)
    if #problems > 0 then return nil, "invalid", problems[1] end
    for _, step in ipairs(entry.steps) do
        if Spells.Exists and Spells.Exists(step.id) == false then return nil, "spell", tostring(step.id) end
    end
    local foreign, source = Own.ForeignSpells(entry.steps, ns.playerClass)
    if #foreign > 0 then return nil, "foreign", Own.ForeignText(foreign, source) end
    if opts.dry then return entry end
    entry.key = nil
    return Add(entry)
end

-- Grund eines gescheiterten Übernehmens in Worten.
function Own.ReasonText(reason, detail)
    local text = L["ROTATION_OWN_IMPORT_" .. tostring(reason)]
    if type(text) ~= "string" or text:find("^ROTATION_OWN_IMPORT_") then text = L.ROTATION_OWN_IMPORT_syntax end
    return Fmt(text, detail or "?")
end

-- Grund eines gescheiterten „Als eigene Rotation speichern“ in Worten ("max", "invalid", "db").
function Own.SaveReasonText(reason, detail)
    local text = L["ROTATION_OWN_SAVE_FAIL_" .. tostring(reason)]
    if type(text) ~= "string" or text:find("^ROTATION_OWN_SAVE_FAIL_") then text = L.ROTATION_OWN_SAVE_FAIL_invalid end
    if reason == "max" then return Fmt(text, Own.MAX) end
    return Fmt(text, detail or "?")
end

-- Beim Laden: alte Speicherstände anderer Fassungen bleiben unangetastet (Store liefert für sie nil).
ns.OnReady(function()
    revision = revision + 1
end)

-- Vergessener Twink (Core.ForgetChar): alles, was ezCombat je Charakter merkt, geht mit – seine eigenen Rotationen,
-- der Merker „Anpassen“ der Seite, die gewählte Rotation (ezCombatDB.rotations), seine Anpassungen der Vorlagen
-- (rotationEdits, Welle 26 – die Lücke bestand seit Welle 24) und die gesehenen Auren (rotationSeen). Die Felder sind
-- je Charakter-Schlüssel (Core.charKey) gemerkt; andere Charaktere bleiben unberührt.
Own.FORGET_FIELDS = { "ownRotations", "rotationBookEdit", "rotations", "rotationEdits", "rotationSeen" }
if type(Core.Listen) == "function" then
    Core.Listen("CHAR_FORGOTTEN", function(key)
        local db = ns.db
        if Core.IsSecret(key) or type(key) ~= "string" or type(db) ~= "table" then return end
        for _, field in ipairs(Own.FORGET_FIELDS) do
            if type(db[field]) == "table" then db[field][key] = nil end
        end
        revision = revision + 1
    end, "ezCombat")
end
