local _, ns = ...
local Core = ezCore

-- Fehlertext aus der Locale (deutsch und englisch, Leitlinie 7; Gesamtreview 18.11.2026, T10-2). Fehlt die Locale
-- (Werkzeuge unter tools/, die diese Datei offline laden), bleibt der Schlüssel samt Wert lesbar.
local function ErrorText(key, value)
    local text = type(ns.L) == "table" and ns.L[key]
    if type(text) ~= "string" then return key .. ": " .. tostring(value) end
    return text:format(tostring(value))
end

-- Rotationen je Klasse und Talentbaum (Wunsch des Nutzers, 13.11.2026) für WoW Forever – Classic-Fähigkeiten und
-- die neuen aus Forever. Diese Datei ist nur die Sammelstelle; die Daten stehen je Klasse in
-- RotationData/<KLASSE>.lua, die Volksfähigkeiten in RotationData/Racial.lua (Quellen im Kopf jeder Datei).
--
-- Grundsatz: Der Client ist die Quelle. In den Datendateien stehen nur Zauber-ID (Rang 1) und Logik – Name, Symbol,
-- Ränge, gelernt, Lernstufe, Kosten, Zauberzeit, Abklingzeit, Dauer und „nutzbar“ fragt der Motor zur Laufzeit ab
-- (ezCore.Spells). Feste Zahlen sind nur Schwellen der Logik (cp, min, max, stacks, refresh …) oder ein
-- gekennzeichneter Rückfall.
--
-- Rotation: key (eindeutig je Klasse), tree (Talentbaum 1–3), name = T(deutsch, englisch), source (https://…),
--   sources (weitere Seiten), how (so funktioniert sie, eigene Worte), note (Widersprüche, Grenzen), pick (wann
--   „Nach Talentbaum“ sie nimmt), counters (Zähler für Zyklen), steps (flache Liste – die Reihenfolge ist der Rang).
-- Schritt: id = Zauber-ID, kind = Art (longbuff, prepare, opener, maintain, priority, resource, phase, filler,
--   cooldown, aoe, situational – steuert nur das Tor und den Abschnitt; ohne kind: Altschritt, bewertet wie bisher),
--   when = Bedingung (Rotation.CONDITIONS: ready, reactive, dot, buff, proc, finisher, rage, energy, mana, lowmana,
--   totem, filler, aoe; neu: enchant, pet, form, item, totemslot, stealth, autorepeat, manual), text = T(de, en),
--   key (Name für Anpassungen, Standard kind:id), buff (Schlüssel oder Gruppe aus ezCores Buff-Wissen), refresh
--   ("missing" | "cast" | Sekunden), once ("target" | "combat"), side, hold, optional, mine, need = { … } (weitere
--   Bedingungen, Rotation.CHECKS), aura (andere Aura als der Zauber), stacks, unit, group (schließen sich aus), cp,
--   min, max, item, hand, slot, burst (true: große Burst-Abklingzeit, nur an kind = "cooldown" – nur sie folgt
--   „Große Abklingzeiten vorschlagen“, alle übrigen Abklingzeiten kommen, sobald sie bereit sind), guess = T(de, en)
--   (was am Schritt geschätzt ist, weil die Quelle keine Zahl nennt – steht im Tooltip als „Annahme: …“; Paket
--   ezcombat/rotation-recherche-2 vom 20.11.2026, vorher nur als Kommentar im Quelltext); nur für
--   Volksfähigkeiten: race, class.
-- Ungelernte Schritte überspringt ezCombat – so passt dieselbe Liste beim Leveln.
local function T(de, en) return { de, en } end

ns.ROTATIONS = {}

-- Schlüssel eines Schritts ohne eigenes key-Feld (dieselbe Regel wie Rotation.StepKey).
local function DefaultKey(step)
    if step.race then return "racial:" .. tostring(step.id) end
    if step.kind then return step.kind .. ":" .. tostring(step.id) end
    return (step.when or "ready") .. ":" .. tostring(step.id)
end

-- Altdaten (Schritte ohne kind und ohne key): Wäre der Standard-Schlüssel in der Rotation doppelt, bekommt der
-- zweite „#2“, der dritte „#3“ … Neue Schritte (mit kind) brauchen dann ein eigenes key-Feld (Test).
local function NumberLegacyKeys(steps)
    local seen = {}
    for _, step in ipairs(steps) do
        if type(step) == "table" then
            local key = step.key or DefaultKey(step)
            if seen[key] and step.key == nil and step.kind == nil then
                seen[key] = seen[key] + 1
                step.key = key .. "#" .. seen[key]
            else
                seen[key] = seen[key] or 1
            end
        end
    end
end

-- Hängt die Rotationen einer Klasse an ns.ROTATIONS[class] an (legt die Liste an). "RACIAL": Liste von Schritten.
-- Ein doppelter Schlüssel je Klasse ist ein Fehler (Core.Error); die zweite Rotation wird nicht aufgenommen.
-- → Anzahl aufgenommener Einträge
local function Add(class, list)
    if type(class) ~= "string" or type(list) ~= "table" then return 0 end
    local target = ns.ROTATIONS[class]
    if type(target) ~= "table" then
        target = {}
        ns.ROTATIONS[class] = target
    end
    local added = 0
    if class == "RACIAL" then
        for _, step in ipairs(list) do
            target[#target + 1] = step
            added = added + 1
        end
        return added
    end
    local keys = {}
    for _, rotation in ipairs(target) do keys[rotation.key] = true end
    for _, rotation in ipairs(list) do
        if type(rotation) == "table" and rotation.key ~= nil and not keys[rotation.key] then
            keys[rotation.key] = true
            NumberLegacyKeys(rotation.steps or {})
            target[#target + 1] = rotation
            added = added + 1
        else
            Core.Error("ezCombat", ErrorText("ROTATION_DATA_DUPLICATE", class .. "/"
                .. tostring(type(rotation) == "table" and rotation.key or rotation)), "RotationData.Add")
        end
    end
    return added
end

-- Berechnete Rotationen (Welle 21; tools/rotation_sim.lua schreibt RotationComputed.lua, docs/talent-simulation.md,
-- Abschnitt 6): nur Einträge mit Schlüssel „sim-…“, Talentbaum, Namen, Schritten und Herkunft (computed). Was davon
-- abweicht oder den Schlüssel einer Vorlage trägt, bleibt draußen (Core.Error). Gemerkt je Klasse, bis sich die
-- Tabelle ändert. → { Rotation … } (ezCombats eigene Tabellen, nur lesen)
local computedCache = {}
local NONE = {}         -- gemeinsame leere Liste (nur lesen): ForClass fragt bei jeder Bewertung

local function ValidComputed(rotation, keys)
    return type(rotation) == "table" and type(rotation.key) == "string" and rotation.key:find("^sim%-") ~= nil
        and not keys[rotation.key] and type(rotation.tree) == "number" and type(rotation.name) == "table"
        and type(rotation.steps) == "table" and #rotation.steps > 0 and type(rotation.computed) == "table"
end

local function Computed(class)
    local all = ns.ROTATION_COMPUTED
    local source = type(all) == "table" and type(class) == "string" and all[class] or nil
    if type(source) ~= "table" or #source == 0 then return NONE end
    local cached = computedCache[class]
    if cached and cached.source == source and cached.count == #source then return cached.list end
    local keys, list = {}, {}
    local own = ns.ROTATIONS[class]
    for _, rotation in ipairs(type(own) == "table" and own or {}) do
        if type(rotation) == "table" and rotation.key ~= nil then keys[rotation.key] = true end
    end
    for _, rotation in ipairs(source) do
        if ValidComputed(rotation, keys) then
            keys[rotation.key] = true
            list[#list + 1] = rotation
        else
            Core.Error("ezCombat", ErrorText("ROTATION_COMPUTED_INVALID", class .. "/"
                .. tostring(type(rotation) == "table" and rotation.key or rotation)), "RotationData.Computed")
        end
    end
    computedCache[class] = { source = source, count = #source, list = list }
    return list
end

-- Alle Kennungen eines Schritts bzw. einer Rotation – die EINE Sammelstelle (Gesamtreview 18.11.2026, T7-NE4) für
-- /ez zauber (SpellIDs unten), ezCombats Selbsttest (Rotation.CheckSpells, /ez test und /ezk status) und das
-- Offline-Werkzeug tools/zauber.lua (lädt diese Datei). Vorher führten alle drei eigene Sammler mit verschiedener
-- Abdeckung: zwei lasen ein Feld step.known, das kein Schritt hat, und keiner die IDs in pick.
--   StepIDs(step, fn)          step.id, step.aura, step.item, die Bedingungen need (known, unknown, seen, form,
--                              inrange, outrange, usable, unusable, aura.id, noaura.id, item.id) und {ID} im Satz
--   RotationIDs(rotation, fn)  alle Schritte, dazu pick (wie need), counters (aura, known, gain, spend) und {ID} in
--                              how und note
-- fn(id, what, field, step): what = "spell" (der Zauber eines Schritts, gain/spend eines Zählers, {ID} in Texten),
-- "aura" (Aura, Talent, Vergleichszauber in Bedingungen und Zählern) oder "item" (Gegenstand); field nennt die Stelle
-- ("id", "aura", "item", "need.outrange", "pick.known", "counter:eclipse", "text", "how", "note"); step ist der Schritt
-- bzw. nil bei Feldern der Rotation. Nur Zahlen über 0; Namen in Bedingungen (need.aura.id = { …, "bane" }) zählen nicht.
local NEED_SPELL_KEYS = { "known", "unknown", "seen", "form", "inrange", "outrange", "usable", "unusable" }

local function EachNumber(value, fn)
    if type(value) == "number" then
        if value > 0 then fn(value) end
    elseif type(value) == "table" then
        for _, one in ipairs(value) do
            if type(one) == "number" and one > 0 then fn(one) end
        end
    end
end

local function NeedIDs(need, prefix, fn, step)
    if type(need) ~= "table" then return end
    for _, key in ipairs(NEED_SPELL_KEYS) do
        EachNumber(need[key], function(id) fn(id, "aura", prefix .. key, step) end)
    end
    for _, key in ipairs({ "aura", "noaura" }) do
        if type(need[key]) == "table" then
            EachNumber(need[key].id, function(id) fn(id, "aura", prefix .. key, step) end)
        end
    end
    if type(need.item) == "table" then EachNumber(need.item.id, function(id) fn(id, "item", prefix .. "item", step) end) end
end

local function TextIDs(text, field, fn, step)
    if type(text) ~= "table" then return end
    for i = 1, 2 do
        if type(text[i]) == "string" then
            for id in text[i]:gmatch("{(%d+)}") do EachNumber(tonumber(id), function(n) fn(n, "spell", field, step) end) end
        end
    end
end

local function StepIDs(step, fn)
    if type(step) ~= "table" then return end
    EachNumber(step.id, function(id) fn(id, "spell", "id", step) end)
    EachNumber(step.aura, function(id) fn(id, "aura", "aura", step) end)
    EachNumber(step.item, function(id) fn(id, "item", "item", step) end)
    NeedIDs(step.need, "need.", fn, step)
    TextIDs(step.text, "text", fn, step)
    TextIDs(step.guess, "guess", fn, step)
end

local function RotationIDs(rotation, fn)
    if type(rotation) ~= "table" then return end
    for _, step in ipairs(type(rotation.steps) == "table" and rotation.steps or {}) do StepIDs(step, fn) end
    NeedIDs(rotation.pick, "pick.", fn, nil)
    for name, def in pairs(type(rotation.counters) == "table" and rotation.counters or {}) do
        if type(def) == "table" then
            local field = "counter:" .. tostring(name)
            EachNumber(def.aura, function(id) fn(id, "aura", field) end)
            EachNumber(def.known, function(id) fn(id, "aura", field) end)
            for _, map in ipairs({ def.gain, def.spend }) do
                for id in pairs(type(map) == "table" and map or {}) do
                    EachNumber(id, function(n) fn(n, "spell", field) end)
                end
            end
        end
    end
    TextIDs(rotation.how, "how", fn)
    TextIDs(rotation.note, "note", fn)
end

-- Alle Zauber-Kennungen der Rotationsdaten als Menge { [id] = true } – für ezCores Zauber-Prüfung (/ez zauber,
-- Core.AddSpellSource; Auftrag aus Welle 15, docs/roadmap/ezCore.md): alles aus RotationIDs außer Gegenständen, für
-- die Rotationen aller Klassen, die Volksfähigkeiten (RACIAL) und die berechneten Rotationen (Computed). Ohne diese
-- Anmeldung prüfte /ez zauber nur step.id (über ezCore.API("ezCombat").Sections).
local function SpellIDs()
    local set = {}
    local function Add(id, what)
        if what ~= "item" then set[id] = true end
    end
    local lists = {}
    for class, list in pairs(ns.ROTATIONS or {}) do lists[#lists + 1] = { class, list } end
    for class in pairs(type(ns.ROTATION_COMPUTED) == "table" and ns.ROTATION_COMPUTED or {}) do
        lists[#lists + 1] = { "computed", Computed(class) }
    end
    for _, pair in ipairs(lists) do
        local class, list = pair[1], pair[2]
        if type(list) == "table" then
            if class == "RACIAL" then
                for _, step in ipairs(list) do StepIDs(step, Add) end
            else
                for _, rotation in ipairs(list) do RotationIDs(rotation, Add) end
            end
        end
    end
    return set
end

ns.RotationData = {
    T = T,
    Add = Add,
    DefaultKey = DefaultKey,
    SpellIDs = SpellIDs,
    StepIDs = StepIDs,
    RotationIDs = RotationIDs,
    Computed = Computed,
    -- Die Klassen mit Rotationsdaten: ezCores Klassenliste (CB-08, eine Stelle; Reihenfolge wie dort).
    Classes = ezCore and ezCore.CLASSES,
}

-- Anmeldung bei ezCores Zauber-Prüfung; die Liste entsteht erst beim Prüfen (alle Datendateien sind dann geladen).
if type(Core) == "table" and type(Core.AddSpellSource) == "function" then Core.AddSpellSource("ezCombat", SpellIDs) end
