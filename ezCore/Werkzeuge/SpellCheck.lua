local ADDON, ns = ...
local Core = ezCore
local L = Core.L

--[[
    Zauber-Prüfung – /ez zauber (Welle 15, Paket kern/zauber-datengrundlage; Frage des Nutzers vom 15.11.2026: „haben
    wir wirklich eine perfekte datengrundlage für makros und rotationen?“ – ROADMAP.md, „Entscheidungen des Nutzers“).
    Knopf „Zauber prüfen“ auf der Seite „ezCollection“ » „Erweitert“ (Leitlinie 3) und Befehl „/ez zauber“.

    /ez test fragt je Zauber-ID nur „gibt es sie?“. Diese Prüfung hält je ID fest, was der Client weiß: Name, Symbol,
    vorhanden, Lernstufe laut Client (C_Spell.GetSpellLevelLearned; Forever-Signatur im Probe-Bericht 7,
    42-dokumentation-signaturen.md) und ob dein Charakter den Zauber kennt (C_SpellBook.IsSpellKnown, sonst
    IsPlayerSpell, sonst genau dieser Rang im Zauberbuch). Das Ergebnis steht im Speicher (eigener Ast ezCoreDB.spellCheck, klein, ohne
    Charaktername, Realm oder Kennung – nur Build, Sprache, Klasse und Stufe für die Spalte „kennt“) und in einem
    Kopierfeld, damit du es schicken kannst. Das Lese-Werkzeug tools/zauber.lua gleicht beides mit der Offline-Liste ab
    (abweichende Stufe, fehlt im Client, Name anders).

    Welche IDs: jede, die ezCore führt (Spells.FALLBACK, BUFFS samt Gruppen, FAMILIES, HEALS, DISPELS, RESURRECTS,
    HELPERS, CLASS, FORM_IDS, PROF_COOLDOWNS, AUTO_SHOT, MACRO_LOGIC, KnowledgeData.PROFESSIONS und WELL_FED_SPELLS,
    Gathering.TRACKING_SPELLS, Discovery.CONTEXT_SPELLS), dazu die Rotationen von ezCombat über dessen Schnittstelle
    (ezCore.API("ezCombat").Rotations/Sections, alle Klassen) und was Module über Core.AddSpellSource anmelden.
    Lücke bis zum Paket von ezCombat: Sections nennt je Schritt nur die Zauber-ID (für die eigene Klasse den höchsten
    gelernten Rang statt der ID aus den Daten), nicht aura, known, counters und die {ID} in den Texten. Diese IDs prüft
    erst eine Anmeldung von ezCombat über Core.AddSpellSource (Auftrag in docs/roadmap/ezCore.md); tools/zauber.lua
    führt sie bis dahin als „nicht geprüft“.

      Core.AddSpellSource(owner, fn)   fn() » { id … } oder { [id] = true }; eine neue Anmeldung ersetzt die alte
      Core.SpellCheck.IDs()            » sortierte Liste der Kennungen
      Core.SpellCheck.Row(id)          » { e = 1|0, n = Name, i = Symbol (Datei-ID), l = Stufe, k = 1|0 }
      Core.SpellCheck.Run()            » Momentaufnahme { v, t, build, locale, class, level, n, missing, ids } (gespeichert)
      Core.SpellCheck.Last()           » die gespeicherte Momentaufnahme oder nil
      Core.SpellCheck.Text(aufnahme)   » Kopierfeld-Text (Kopf „ezCollection Zauber v1 | …“, dann id;da;stufe;kennt;symbol;name)
      Core.RunSpellCheck()             Knopf und Befehl: prüfen (im Kampf erst danach), melden, Kopierfeld zeigen
    Nichts wird verändert; Zauber werden nur abgefragt.
]]

local SC = {}
Core.SpellCheck = SC
SC.VERSION = 1
SC.COPY_HEAD = "ezCollection Zauber v1"   -- tools/zauber.lua erkennt das Kopierfeld an dieser Zeile

local Spells = Core.Spells
local sources, sourceOrder = {}, {}

function Core.AddSpellSource(owner, fn)
    if type(fn) ~= "function" then return false end
    owner = type(owner) == "string" and owner ~= "" and owner or "?"
    if not sources[owner] then sourceOrder[#sourceOrder + 1] = owner end
    sources[owner] = fn
    return true
end

local function AddAll(set, t)
    for k, v in pairs(type(t) == "table" and t or {}) do
        if type(v) == "table" then AddAll(set, v)
        elseif type(v) == "number" and type(k) == "number" and v > 0 then set[v] = true end
    end
end

local function AddKeys(set, t)
    for id in pairs(type(t) == "table" and t or {}) do
        if type(id) == "number" then set[id] = true end
    end
end

-- Angemeldete Quelle: Listenwerte { id … } und Mengen-Schlüssel { [id] = true }. Nur Schlüssel mit dem Wert true
-- zählen, sonst kämen bei einer Liste die Plätze 1, 2, 3 … als Zauber-IDs mit (Gegenprüfung Welle 15).
local function AddSource(set, t)
    AddAll(set, t)
    for id, v in pairs(type(t) == "table" and t or {}) do
        if v == true and type(id) == "number" and id > 0 then set[id] = true end
    end
end

-- Rotationen von ezCombat über dessen Schnittstelle (alle Klassen; ohne ezCombat nichts). Nur step.id – Auren,
-- known, counters und Text-Verweise liefert Sections nicht (siehe Kopf).
local function CombatIDs(set)
    local api = Core.API and Core.API("ezCombat")
    if type(api) ~= "table" or type(api.Rotations) ~= "function" or type(api.Sections) ~= "function" then return end
    for _, class in ipairs(Core.CLASSES or {}) do
        local ok, list = pcall(api.Rotations, class)
        for _, rotation in ipairs(ok and type(list) == "table" and list or {}) do
            local okS, sections = pcall(api.Sections, rotation.key, class)
            for _, section in ipairs(okS and type(sections) == "table" and sections or {}) do
                for _, step in ipairs(type(section.steps) == "table" and section.steps or {}) do
                    local id = Core.Num(step.id)
                    if id and id > 0 then set[id] = true end
                end
            end
        end
    end
end

function SC.IDs()
    local set = {}
    AddKeys(set, Spells.FALLBACK)
    for _, d in pairs(Spells.BUFFS or {}) do
        AddAll(set, d.spells)
        AddAll(set, d.group)
        if type(d.cast) == "number" then set[d.cast] = true end
    end
    for _, f in pairs(Spells.FAMILIES or {}) do AddAll(set, f.spells) end
    AddAll(set, Spells.HEALS)
    AddAll(set, Spells.DISPELS)
    AddAll(set, Spells.RESURRECTS)
    AddAll(set, Spells.HELPERS)
    AddAll(set, Spells.CLASS)
    AddKeys(set, Spells.FORM_IDS)
    AddKeys(set, Spells.PROF_COOLDOWNS)
    if type(Spells.AUTO_SHOT) == "number" then set[Spells.AUTO_SHOT] = true end
    if type(Spells.MacroSpells) == "function" then AddKeys(set, Spells.MacroSpells()) end
    local data = ns.KnowledgeData
    for _, p in ipairs(type(data) == "table" and data.PROFESSIONS or {}) do
        if type(p.spell) == "number" then set[p.spell] = true end
    end
    AddAll(set, type(data) == "table" and data.WELL_FED_SPELLS or nil)
    for _, v in pairs(Core.Gathering and Core.Gathering.TRACKING_SPELLS or {}) do if type(v) == "number" then set[v] = true end end
    for _, v in pairs(Core.Discovery and Core.Discovery.CONTEXT_SPELLS or {}) do if type(v) == "number" then set[v] = true end end
    CombatIDs(set)
    for _, owner in ipairs(sourceOrder) do
        local ok, list = pcall(sources[owner])
        if ok and type(list) == "table" then
            AddSource(set, list)
        elseif not ok then
            Core.Error(owner, list, "spellSource")
        end
    end
    local out = {}
    for id in pairs(set) do out[#out + 1] = id end
    table.sort(out)
    return out
end

local function Known(id)
    local book = rawget(_G, "C_SpellBook")
    local known = Core.Call(book and Core.Peek(book, "IsSpellKnown"), id)
    if not Core.IsSecret(known) and type(known) == "boolean" then
        if known then return true end
    end
    local player = Core.Call(rawget(_G, "IsPlayerSpell"), id)
    if not Core.IsSecret(player) and player == true then return true end
    -- Zauberbuch: genau dieser Rang muss drinstehen. Spells.Highest sucht über den Namen und fände für Rang 2 auch
    -- den gelernten Rang 1 (Gegenprüfung Welle 15).
    local entry = Spells.Known and Spells.Known(id)
    for _, rid in pairs(type(entry) == "table" and type(entry.ranks) == "table" and entry.ranks or {}) do
        if rid == id then return true end
    end
    return false
end

function SC.Row(id)
    local api = rawget(_G, "C_Spell")
    local row = { e = Spells.Exists(id) and 1 or 0, k = 0 }
    local name = Core.Plain((Core.Call(api and Core.Peek(api, "GetSpellName"), id)))
    if type(name) == "string" and name ~= "" then row.n = name end
    local icon = Core.Num((Core.Call(api and Core.Peek(api, "GetSpellTexture"), id)))
    if icon and icon > 0 then row.i = icon end
    local level = Core.Num((Core.Call(api and Core.Peek(api, "GetSpellLevelLearned"), id)))
    if level and level > 0 then row.l = level end
    if row.e == 1 and Known(id) then row.k = 1 end
    return row
end

local function Build()
    local info = rawget(_G, "GetBuildInfo")
    if type(info) ~= "function" then return nil end
    local ok, version, build = pcall(info)
    version, build = ok and Core.Plain(version), ok and Core.Plain(build)
    if not version then return nil end
    return build and ("%s (%s)"):format(tostring(version), tostring(build)) or tostring(version)
end

function SC.Run()
    local ids = SC.IDs()
    local snap = { v = SC.VERSION, t = time and time() or 0, build = Build(), locale = Core.Plain((Core.Call(rawget(_G, "GetLocale")))),
        class = Core.PlayerClass and Core.PlayerClass() or nil, level = Core.Num((Core.Call(rawget(_G, "UnitLevel"), "player"))),
        n = #ids, missing = 0, ids = {} }
    for _, id in ipairs(ids) do
        local row = SC.Row(id)
        snap.ids[id] = row
        if row.e == 0 then snap.missing = snap.missing + 1 end
    end
    if type(Core.db) == "table" then Core.db.spellCheck = snap end
    return snap
end

function SC.Last()
    local snap = type(Core.db) == "table" and Core.db.spellCheck or nil
    return type(snap) == "table" and type(snap.ids) == "table" and snap or nil
end

function SC.Text(snap)
    snap = snap or SC.Last()
    if not snap then return "" end
    local head = ("%s | build %s | %s | %s %s | %s"):format(SC.COPY_HEAD, tostring(snap.build or "?"), tostring(snap.locale or "?"),
        tostring(snap.class or "?"), tostring(snap.level or 0), Core.DateText(snap.t or 0, "iso"))   -- Maschinentext: ISO (T16-NZ5)
    local lines = { head, "id;da;stufe;kennt;symbol;name" }
    local ids = {}
    for id in pairs(snap.ids) do if type(id) == "number" then ids[#ids + 1] = id end end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local r = snap.ids[id]
        local name = tostring(r.n or ""):gsub("[;\r\n]", " ")
        lines[#lines + 1] = ("%d;%d;%s;%d;%s;%s"):format(id, r.e == 1 and 1 or 0, r.l and tostring(r.l) or "", r.k == 1 and 1 or 0,
            r.i and tostring(r.i) or "", name)
    end
    return table.concat(lines, "\n")
end

function SC.Show(snap)
    snap = snap or SC.Last()
    if not snap then return nil end
    return Core.TextDialog({ anchor = rawget(_G, "SettingsPanel"), title = L.SPELLCHECK_TITLE,
        hint = L.SPELLCHECK_HINT:format(snap.n or 0, snap.missing or 0), text = SC.Text(snap), readOnly = true, select = true,
        maxLetters = 0, owner = ADDON })
end

-- Knopf und „/ez zauber“: prüfen (im Kampf erst danach), im Chat melden, Kopierfeld zeigen.
function Core.RunSpellCheck(quiet)
    local snap
    local ran = Core.AfterCombat(function()
        snap = SC.Run()
        if quiet then return end
        ns.Print(L.SPELLCHECK_DONE:format(snap.n, snap.missing))
        SC.Show(snap)
    end, "ezCore.spellCheck", ADDON)
    if not ran and not quiet then ns.Print(L.SPELLCHECK_COMBAT) end
    return snap
end
