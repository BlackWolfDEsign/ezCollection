local ADDON, ns = ...
local Core = ezCore
local L = ns.L
local Traits = ns.Traits

--[[
    Vorlagen für Klassentalente und Vermächtnis – derselbe Code für beide Baumarten (Punkte 1 und 7).

    Gespeichert in ezTalentDB.templates[scope][name] = { nodes, choices, tree, primary, groups, points, saved, by,
      order, orderFrom, orderEdited, gear, bars }
      scope "class:MAGE"      Talent-Vorlagen gelten für alle Twinks derselben Klasse
      scope "legacy:<treeID>" Vermächtnis-Vorlagen gelten accountweit (die Punkte sind es auch)
    SavedVariables sind accountweit, deshalb sieht jeder Twink die Vorlagen seiner Klasse und alle Vermächtnis-Vorlagen.

    Reihenfolge der Punkte (TL-01, VP-57; optional): order = { Knoten-ID … }, je Eintrag ein Punkt in der Reihenfolge
    des Setzens (ein Knoten mit drei Rängen steht dreimal darin). Quelle (Leitlinie 11, orderFrom): "clicks" = deine
    Klicks beim „Anpassen“ (Plan.Adjust merkt sie), sonst der Schlüssel der Website in ns.PRESET_SITES, aus deren
    belegter Reihenfolge die Vorauswahl stammt (preset.order mit preset.orderSource); orderEdited = danach von dir
    geändert. Ohne belegte Quelle bleibt eine Vorlage ohne Reihenfolge.
    Ausrüstungsset und Leistenprofil (TL-02, VP-36, Frage 19 – Empfehlung umgesetzt, Antwort offen; optional): gear =
    Name eines Sets aus ezGear, bars = Name eines Leistenprofils aus ezMacro. Nach „Übernehmen“ bietet ezTalent beide per
    Zeile im Seitenteil an, nichts geschieht von selbst. Ohne ezGear bzw. ezMacro gibt es die Felder in der Oberfläche
    nicht (gespeicherte Namen bleiben erhalten).

    Bewusst nicht über Core.NewProfiles: Das Gerüst kennt ein „aktives Profil“, das es beim Wechsel und beim Ausloggen
    aus den Arbeitsdaten neu sichert. Die Arbeitsdaten sind hier Blizzards Talentverteilung – nur gestaffelt und
    außerhalb des Kampfes änderbar und je Charakter verschieden; ein automatisches Sichern überschriebe eine Vorlage mit
    der Verteilung eines anderen Twinks. Vorlagen sind deshalb reine Momentaufnahmen (wie die Profile von ezBars),
    geteilt wird über Core.Serialize mit der Kennung KIND.
]]

local Templates = {}
ns.Templates = Templates

Templates.KIND, Templates.VERSION = "ezTalent.template", 1
Templates.MAX_NAME = 40

local function Store(create)
    local db = ns.db
    if not db then return nil end
    if type(db.templates) ~= "table" then
        if not create then return nil end
        db.templates = {}
    end
    return db.templates
end

local function Scoped(scope, create)
    local store = Store(create)
    if not (store and scope) then return nil end
    if type(store[scope]) ~= "table" then
        if not create then return nil end
        store[scope] = {}
    end
    return store[scope]
end

function Templates.ClassScope(class)
    class = class or Core.PlayerClass()
    return class and ("class:" .. class) or nil
end

function Templates.LegacyScope(treeID)
    return treeID and ("legacy:" .. tostring(treeID)) or nil
end

-- Art und Wert eines Scopes: "class", "MAGE" bzw. "legacy", treeID.
function Templates.ParseScope(scope)
    local kind, value = tostring(scope or ""):match("^(%a+):(.+)$")
    if kind == "legacy" then return kind, tonumber(value) end
    return kind, value
end

function Templates.Names(scope)
    local names = {}
    for name in pairs(Scoped(scope, false) or {}) do names[#names + 1] = name end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

function Templates.Get(scope, name)
    local list = Scoped(scope, false)
    return list and name and list[name] or nil
end

function Templates.Count(scope)
    local n = 0
    local store = Store(false) or {}
    for key, list in pairs(store) do
        if (scope == nil or key == scope) and type(list) == "table" then
            for _ in pairs(list) do n = n + 1 end
        end
    end
    return n
end

-- MAX_NAME zählt Zeichen wie Blizzards Eingabefeld (Core.AskText, maxLetters), nicht Bytes – UTF-8-sicher gekürzt.
local function CleanName(name)
    name = Core.Trim(tostring(name or "")):gsub("|", "")
    return Core.TruncateChars(name, Templates.MAX_NAME)
end
Templates.CleanName = CleanName

-- Freier Name: „Name“, sonst „Name (2)“, „Name (3)“ … – über Core.UniqueName, das den Namen vor dem Zusatz kürzt,
-- damit „ (2)“ in MAX_NAME Platz hat (sonst schnitte Save ihn ab und überschriebe eine vorhandene Vorlage)
function Templates.UniqueName(scope, base)
    local function Taken(name) return Templates.Get(scope, name) ~= nil end
    local name = Core.UniqueName(CleanName(base), Taken, { maxChars = Templates.MAX_NAME, default = L.TEMPLATE_DEFAULT_NAME })
    if not Taken(name) then return name end
    local suffix = " (" .. tostring(time and time() or 0) .. ")"  -- alle Zusätze belegt: Zeitstempel, ebenfalls gekürzt
    return Core.TruncateChars(name, Templates.MAX_NAME - #suffix) .. suffix
end

-- Kopie nur der erlaubten Felder (Zahlen-Schlüssel, Zahlen-Werte) – auch für Eingefügtes aus fremder Hand.
local function CleanMap(map)
    local out = {}
    if type(map) ~= "table" then return out end
    for key, value in pairs(map) do
        key, value = tonumber(key), tonumber(value)
        if key and value and value > 0 and value == math.floor(value) then out[key] = value end
    end
    return out
end

Templates.MAX_ORDER = 200      -- höchstens so viele Schritte in der Reihenfolge (51 Klassenpunkte, Vermächtnis mehr)
Templates.MAX_LINK = 64        -- Länge eines Set- bzw. Profilnamens

-- Reihenfolge: nur Knoten-IDs, die im Plan stehen, je Knoten höchstens so oft wie sein Zielrang. → Liste oder nil
function Templates.CleanOrder(order, nodes)
    if type(order) ~= "table" then return nil end
    local out, counts = {}, {}
    for _, id in ipairs(order) do
        id = tonumber(id)
        local want = id and tonumber(type(nodes) == "table" and (nodes[id] or nodes[tostring(id)]) or nil) or 0
        if id and (counts[id] or 0) < want and #out < Templates.MAX_ORDER then
            counts[id] = (counts[id] or 0) + 1
            out[#out + 1] = id
        end
    end
    return #out > 0 and out or nil
end

-- Quelle der Reihenfolge: "clicks" oder ein Schlüssel aus ns.PRESET_SITES, sonst nil.
function Templates.CleanOrderFrom(from)
    if from == "clicks" then return from end
    if type(from) == "string" and ns.PRESET_SITES and ns.PRESET_SITES[from] then return from end
    return nil
end

-- Name eines Sets bzw. Leistenprofils: Text ohne „|“, gekürzt; leer → nil.
local function CleanLink(name)
    if type(name) ~= "string" or Core.IsSecret(name) then return nil end
    name = Core.TruncateChars(Core.Trim(name):gsub("|", ""), Templates.MAX_LINK)
    return name ~= "" and name or nil
end
Templates.CleanLink = CleanLink

local function CleanTemplate(tpl)
    if type(tpl) ~= "table" then return nil end
    local out = { nodes = CleanMap(tpl.nodes), choices = CleanMap(tpl.choices), tree = tonumber(tpl.tree),
        primary = tonumber(tpl.primary), saved = tonumber(tpl.saved), by = type(tpl.by) == "string" and tpl.by or nil }
    out.order = Templates.CleanOrder(tpl.order, out.nodes)
    if out.order then
        out.orderFrom = Templates.CleanOrderFrom(tpl.orderFrom) or "clicks"
        out.orderEdited = out.orderFrom ~= "clicks" and tpl.orderEdited == true or nil
    end
    out.gear, out.bars = CleanLink(tpl.gear), CleanLink(tpl.bars)
    if type(tpl.groups) == "table" then
        out.groups = {}
        for i, spent in ipairs(tpl.groups) do out.groups[i] = tonumber(spent) or 0 end
    end
    -- Aus einer Vorauswahl nur teilweise zugeordnet (T1): Zahl der fehlenden Talente und Gesamtzahl – bleibt sichtbar,
    -- bis die Vorlage mit „Speichern“ aus dem Fenster neu angelegt wird
    local unmatched, matchTotal = tonumber(tpl.unmatched), tonumber(tpl.matchTotal)
    if unmatched and unmatched > 0 and matchTotal and matchTotal >= unmatched then
        out.unmatched, out.matchTotal = math.floor(unmatched), math.floor(matchTotal)
    end
    out.points = Traits.Points(out)
    return out
end
Templates.Clean = CleanTemplate

-- Speichern (überschreibt einen gleichnamigen Eintrag). → Name oder nil, Grund ("empty", "noscope")
function Templates.Save(scope, name, snapshot, meta)
    name = CleanName(name)
    if name == "" then return nil, "empty" end
    local list = Scoped(scope, true)
    if not list then return nil, "noscope" end
    local tpl = CleanTemplate(snapshot) or { nodes = {}, choices = {} }
    meta = meta or {}
    if type(meta.groups) == "table" then
        tpl.groups = {}
        local groups = {}
        for i, g in ipairs(meta.groups) do
            tpl.groups[i] = tonumber(type(g) == "table" and g.spent or g) or 0
            groups[i] = { spent = tpl.groups[i] }
        end
        tpl.primary = Traits.PrimaryTree(groups)
    end
    if meta.primary then tpl.primary = meta.primary end
    tpl.tree = tpl.tree or meta.tree
    tpl.saved = time and time() or 0
    tpl.by = ns.charKey or Core.charKey
    -- Überschreiben behält Set und Leistenprofil der alten Vorlage, wenn die neue Fassung keine nennt (TL-02)
    local old = list[name]
    if type(old) == "table" then
        tpl.gear = tpl.gear or CleanLink(old.gear)
        tpl.bars = tpl.bars or CleanLink(old.bars)
    end
    list[name] = tpl
    ns.Fire("TEMPLATES_CHANGED", scope)
    return name
end

-- Umbenennen. → true oder false, Grund ("missing", "empty", "exists")
function Templates.Rename(scope, old, new)
    local list = Scoped(scope, false)
    if not (list and list[old]) then return false, "missing" end
    new = CleanName(new)
    if new == "" then return false, "empty" end
    if new == old then return true end
    if list[new] then return false, "exists" end
    list[new], list[old] = list[old], nil
    ns.Fire("TEMPLATES_CHANGED", scope)
    return true
end

function Templates.Delete(scope, name)
    local list = Scoped(scope, false)
    if not (list and list[name]) then return false end
    list[name] = nil
    ns.Fire("TEMPLATES_CHANGED", scope)
    return true
end

-- Gleiche Verteilung? (Ränge und Wahlknoten)
function Templates.Same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    local function Covers(x, y)
        for id, rank in pairs(x.nodes or {}) do
            if (tonumber((y.nodes or {})[id]) or 0) ~= tonumber(rank) then return false end
        end
        for id, entry in pairs(x.choices or {}) do
            if (y.choices or {})[id] ~= nil and tonumber(y.choices[id]) ~= tonumber(entry) then return false end
        end
        return true
    end
    return Covers(a, b) and Covers(b, a)
end

-- Vorlage dieses Scopes mit genau dieser Verteilung (für die Twink-Übersicht), sonst nil.
function Templates.Match(scope, snapshot)
    for _, name in ipairs(Templates.Names(scope)) do
        if Templates.Same(Templates.Get(scope, name), snapshot) then return name end
    end
    return nil
end

---------------------------------------------------------------------------
-- Als Text teilen
---------------------------------------------------------------------------

-- Der Text zum Weitergeben trägt keinen Charakter: ohne by (Charakterschlüssel „Name-Realm“ des Erstellers), ohne
-- saved (wann gespeichert) und ohne die Verknüpfungen gear/bars (T6-4, Gesamtreview 18.11.2026). Die Verknüpfungen
-- nennen ein Ausrüstungsset bzw. Leistenprofil, das es nur beim Teilenden gibt, und ezMacros vorgeschlagener
-- Profilname lautet „Klasse (Charaktername)“ (Gegenprüfung). Beim Einfügen werden alle vier verworfen.
local function Unshared(tpl)
    tpl.by, tpl.saved, tpl.gear, tpl.bars = nil, nil, nil, nil
    return tpl
end

function Templates.Export(scope, name)
    local tpl = Templates.Get(scope, name)
    if not tpl then return nil, "missing" end
    local out = Unshared(CleanTemplate(tpl))
    return Core.Serialize({ kind = Templates.KIND, v = Templates.VERSION, scope = scope, name = name, tpl = out })
end

-- Text einfügen. expectScope: nur Vorlagen dieses Scopes (andere Klasse bzw. anderer Baum → "scope").
-- → Name, Scope oder nil, Grund ("format", "kind", "version", "scope", "empty")
function Templates.Import(text, expectScope)
    local value, why = Core.Deserialize(text)
    if type(value) ~= "table" then return nil, why == "empty" and "empty" or "format" end
    if value.kind ~= Templates.KIND then return nil, "kind" end
    if (tonumber(value.v) or 0) > Templates.VERSION then return nil, "version" end
    local scope = type(value.scope) == "string" and value.scope or nil
    if not scope or (expectScope and scope ~= expectScope) then return nil, "scope" end
    local tpl = CleanTemplate(value.tpl)
    if not tpl then return nil, "format" end
    local name = Templates.UniqueName(scope, type(value.name) == "string" and value.name or L.TEMPLATE_DEFAULT_NAME)
    local list = Scoped(scope, true)
    Unshared(tpl)                   -- Ersteller und Verknüpfungen aus älteren Texten (T6-4)
    tpl.saved = time and time() or 0
    list[name] = tpl
    ns.Fire("TEMPLATES_CHANGED", scope)
    return name, scope
end

---------------------------------------------------------------------------
-- Vorauswahl (Punkt 2): Daten in Presets.lua, hier Zuordnung zu den Knoten des Clients, Anzeige und Kopieren
-- Zuordnung sprachunabhängig über die im Spiel erhobene Zauber-ID bzw. Lage (PresetIDs.lua); der Name ist nur Ersatz
-- für Talente, zu denen noch nichts erhoben ist (Spieltest 14.11.2026: über englische Namen im deutschen Client
-- „1 von 17 Talenten zugeordnet“).
---------------------------------------------------------------------------

-- Recherchierte Vorauswahl (Presets.lua) einer Klasse.
function Templates.Researched(class)
    local list = ns.PRESETS and ns.PRESETS[class or Core.PlayerClass() or ""]
    return type(list) == "table" and list or {}
end

-- Berechnete Verteilungen (Computed.lua, Welle 21) einer Klasse – immer (Einstellungs-Prüfung 19.11.2026, Nr. 38: der
-- Schalter „computedPresets“ versteckte nur Listeneinträge; wer sie nicht will, klickt sie nicht an).
function Templates.Computed(class)
    local list = ns.COMPUTED and ns.COMPUTED[class or Core.PlayerClass() or ""]
    return type(list) == "table" and list or {}
end

-- Alles, was die Liste „Vorauswahl“ zeigt: die recherchierten Bäume, dahinter die berechneten (Welle 21). Ohne
-- berechnete ist es dieselbe Liste wie Templates.Researched.
function Templates.Presets(class)
    local researched, computed = Templates.Researched(class), Templates.Computed(class)
    if #computed == 0 then return researched end
    local out = {}
    for _, p in ipairs(researched) do out[#out + 1] = p end
    for _, p in ipairs(computed) do out[#out + 1] = p end
    return out
end

-- Ist die Vorauswahl berechnet (Computed.lua) statt recherchiert?
function Templates.IsComputed(preset)
    return type(preset) == "table" and preset.grade == "computed"
end

---------------------------------------------------------------------------
-- Eigenen Baum gegen das Rechenmodell prüfen (Spieltest 20.11.2026, Wunsch des Nutzers wörtlich „Ggf die Möglichkeit
-- bieten Talentbäume die man selbst erstellt hat anhand der Berechnungsgrundlage zu prüfen?“). Grundlage sind die Werte
-- je Talent und Rang, die tools/talent_sim.lua in jede berechnete Verteilung schreibt (computed.weights, computed.value;
-- docs/talent-simulation.md). Im Spiel wird nichts neu berechnet – nur zusammengezählt.
---------------------------------------------------------------------------

-- Hauptbäume einer Aufteilung { Punkte je Baum }: der mit den meisten Punkten (wie Traits.PrimaryTree) – bei
-- Gleichstand alle gleich starken (beim Leveln etwa 10/10/0), damit keiner stumm herausfällt. → { [Baum] = true } oder nil
local function MainTrees(split)
    local most = 0
    for _, n in ipairs(split or {}) do if (tonumber(n) or 0) > most then most = tonumber(n) end end
    if most <= 0 then return nil end
    local trees = {}
    for i, n in ipairs(split) do if tonumber(n) == most then trees[i] = true end end
    return trees
end

-- Wert eines Talents bis zu einem Rang (kumuliert) – eine Quelle: ns.Optimize.Worth (Optimize.lua).
local function Worth(weights, spell, rank)
    return ns.Optimize.Worth(weights, spell, rank)
end

-- ranks: { [Zauber-ID] = Rang } (Plan.SpellRanks), split: { Punkte je Baum }, class. → Ergebnisse { { preset, value, best,
-- pct, more, less } } (je berechnete Verteilung mit demselben Hauptbaum, beste Übereinstimmung zuerst) oder nil, Grund
-- ("empty" | "none"). Je Zeile { spell, preset (Talent der Verteilung), mine, theirs, delta, per }:
--   more – das Modell setzt mehr Punkte als du (delta = was das bringt), lohnendster Punkt zuerst (per = delta je Punkt);
--   less – du setzt mehr Punkte als das Modell (delta = was sie hier bringen; das Modell setzt sie woanders ein, wo sie
--          mehr bringen), am wenigsten lohnender Punkt zuerst – die besten Kandidaten zum Umsetzen.
-- Die Werte sind kumuliert und fallen nie, darum steht in less nur, wo du mehr Ränge hast. Je höchstens limit (Standard 5).
-- opts (freiwillig, „Bewerten“ seit dem Spieltest vom 20.11.2026: „3/0/0 gegen 51 Punkte ist sinnlos“):
--   best(preset, points) → Ergebnis von ns.Optimize.Best: verglichen wird mit dem Besten des Modells mit genau so vielen
--                          Punkten (theirs = dessen Ränge, best = dessen Wert, Zeile .result); ohne best mit der vollen
--                          Verteilung wie bisher;
--   all = true           → alle berechneten Verteilungen der Klasse, nicht nur die desselben Hauptbaums;
--   keep(preset) → true  → diese Verteilung zusätzlich (etwa die empfohlene aus einem anderen Baum).
-- Hat das Beste mit diesen Punkten den Wert 0 (nichts im Modell erreichbar), gilt pct = 100 und flat = true.
function Templates.Rate(ranks, split, class, limit, opts)
    opts = opts or {}
    local mains = MainTrees(split)
    if not mains then return nil, "empty" end
    local points = 0
    for _, n in ipairs(split) do points = points + (tonumber(n) or 0) end
    local out = {}
    for _, preset in ipairs(Templates.Computed(class)) do
        local c = type(preset.computed) == "table" and preset.computed or nil
        local wanted = opts.all or mains[preset.tree] or (type(opts.keep) == "function" and opts.keep(preset))
        if wanted and c and type(c.weights) == "table" and (c.value or 0) > 0 then
            local value = 0
            for spell, rank in pairs(ranks) do value = value + Worth(c.weights, spell, rank) end
            local theirs, talents, bestValue, result = {}, {}, c.value, nil
            for _, t in ipairs(preset.talents or {}) do
                if t.spell then theirs[t.spell], talents[t.spell] = t[2], t end
            end
            if type(opts.best) == "function" then
                result = opts.best(preset, points)
                if result then theirs, bestValue = result.spells, result.value end
            end
            local more, less, seen = {}, {}, {}
            local function Compare(spell)
                if seen[spell] then return end
                seen[spell] = true
                local mine, other = ranks[spell] or 0, theirs[spell] or 0
                if mine == other then return end
                local delta = Worth(c.weights, spell, other) - Worth(c.weights, spell, mine)
                if math.abs(delta) < 0.005 then return end
                local row = { spell = spell, preset = talents[spell], mine = mine, theirs = other, delta = math.abs(delta) }
                row.per = row.delta / math.abs(other - mine)
                if delta > 0 then more[#more + 1] = row else less[#less + 1] = row end
            end
            for spell in pairs(theirs) do Compare(spell) end
            for spell in pairs(ranks) do Compare(spell) end
            table.sort(more, function(a, b)
                if a.per ~= b.per then return a.per > b.per end
                return a.spell < b.spell
            end)
            table.sort(less, function(a, b)
                if a.per ~= b.per then return a.per < b.per end
                return a.spell < b.spell
            end)
            for _, list in ipairs({ more, less }) do
                for i = #list, (limit or 5) + 1, -1 do list[i] = nil end
            end
            local flat = bestValue <= 0.005
            out[#out + 1] = { preset = preset, value = value, best = bestValue, pct = flat and 100 or value / bestValue * 100,
                flat = flat or nil, more = more, less = less, result = result, points = points }
        end
    end
    if #out == 0 then return nil, "none" end
    table.sort(out, function(a, b)
        if a.pct ~= b.pct then return a.pct > b.pct end
        return tostring(a.preset.key) < tostring(b.preset.key)
    end)
    return out
end

function Templates.PresetName(preset)
    local name = type(preset) == "table" and preset.name
    if type(name) == "table" then name = (Core.IsGerman() and name.de) or name.en or name.de end
    return type(name) == "string" and name or (preset and preset.key) or "?"
end

-- Anzeigename eines Talents der Vorauswahl ({ Baum, Rang, en, de, anderer }): deutsch im deutschen Client, falls belegt.
function Templates.TalentName(t)
    if type(t) ~= "table" then return "?" end
    if Core.IsGerman() and type(t[4]) == "string" and t[4] ~= "" then return t[4] end
    return tostring(t[3] or "?")
end

-- Vergleichsform eines Namens: klein, ohne Satz- und Leerzeichen; „Verbesserte(r/s)“ → „verb“ (Kurzform „Verb.“),
-- „Spezialisierung“ → „spez“ („-Spez.“). Umlaute bleiben, nur ihre Großform wird klein.
local UPPER = { ["\195\132"] = "\195\164", ["\195\150"] = "\195\182", ["\195\156"] = "\195\188" }
function Templates.NormName(name)
    if type(name) ~= "string" or name == "" then return nil end
    local s = name:lower():gsub("\195[\132\150\156]", UPPER)
    s = s:gsub("verbessert%a*", "verb"):gsub("spezialisierung", "spez")
    s = s:gsub("[%c%p%s]", "")
    return s ~= "" and s or nil
end

-- Sprachunabhängige Kennung eines Talents der Vorauswahl (PresetIDs.lua, im Spiel erhoben):
-- { spells = { Zauber-ID … }, row, col } oder nil, wenn für dieses Talent noch nichts erhoben ist.
-- Berechnete Verteilungen (Computed.lua) tragen die Kennung am Talent selbst (spell, row, col).
function Templates.PresetID(class, t)
    if type(t) == "table" and type(t.spell) == "number" then
        return { spells = { t.spell }, row = tonumber(t.row), col = tonumber(t.col) }
    end
    local ids = ns.PRESET_IDS and ns.PRESET_IDS[class or Core.PlayerClass() or ""]
    if type(ids) ~= "table" or type(t) ~= "table" then return nil end
    local id = ids[tostring(t[1]) .. ":" .. tostring(t[3])]
    if type(id) == "number" then return { spells = { id } } end
    if type(id) ~= "table" then return nil end
    local spells = {}
    if type(id.spell) == "number" then
        spells[1] = id.spell
    elseif type(id.spell) == "table" then
        for _, spell in ipairs(id.spell) do
            if type(spell) == "number" then spells[#spells + 1] = spell end
        end
    end
    return { spells = spells, row = tonumber(id.row), col = tonumber(id.col) }
end

-- Knoten eines Baums im Client, dreifach erschlossen (je Liste von { node, entry }):
--   spells[Zauber-ID]            Zauber der Definition – sprachunabhängig
--   pos["Baum:Zeile:Spalte"]     Lage im Baum (Traits.Layout) – sprachunabhängig
--   names[Vergleichsform]        Name im Client – nur Ersatz, solange für ein Talent nichts erhoben ist
-- Nur Namen und Zauber-IDs (Traits.EntryName/EntrySpell, zwischengespeichert) – Beschreibung und Symbol braucht die
-- Zuordnung nicht.
function Templates.PresetIndex(configID, treeID)
    local index = { groups = {}, names = {}, spells = {}, pos = {} }
    local groups = Traits.Groups(configID, treeID)
    for i, g in ipairs(groups) do index.groups[i] = g.id end
    local nodes = Traits.Nodes(configID, treeID)
    index.layout = Traits.Layout(configID, treeID, nodes, groups)
    local function Add(map, key, candidate)
        if key == nil then return end
        map[key] = map[key] or {}
        table.insert(map[key], candidate)
    end
    for _, node in ipairs(nodes) do
        local where = index.layout[node.id]
        if where and not where.aside then
            for _, entryID in ipairs(node.entries) do
                Add(index.pos, where.tree .. ":" .. where.row .. ":" .. where.col, { node = node, entry = entryID })
            end
        end
        for _, entryID in ipairs(node.entries) do
            local candidate = { node = node, entry = entryID, aside = where and where.aside or nil }
            Add(index.names, Templates.NormName(Traits.EntryName(configID, entryID)), candidate)
            Add(index.spells, Traits.EntrySpell(configID, entryID), candidate)
        end
    end
    -- Doppel (Erhebung 15.11.2026: Jäger „Blitzartige Reflexe“, Priester „Heiligspezialisierung“ je zweimal, das zweite
    -- Mal weit abseits des Baums): Steht derselbe Zauber bzw. Name auch an einem Knoten im Baum, gilt nur dieser.
    for _, map in ipairs({ index.spells, index.names }) do
        for key, list in pairs(map) do
            local inside = {}
            for _, c in ipairs(list) do if not c.aside then inside[#inside + 1] = c end end
            if #inside > 0 and #inside < #list then map[key] = inside end
        end
    end
    return index
end

local function InGroup(node, groupID)
    if not groupID or type(node.groups) ~= "table" or #node.groups == 0 then return nil end
    for _, g in ipairs(node.groups) do if g == groupID then return true end end
    return false
end

-- Bester Knoten für ein Talent: richtiger Baum (wenn der Client es sagt), noch nicht vergeben, Höchstrang genau
-- gleich (trennt gleichnamige Talente wie die zwei „Verbrennung“), sonst groß genug. Ein Knoten aus einem anderen
-- Talentbaum, einer, den schon ein anderes Talent belegt, oder einer mit kleinerem Höchstrang als der Rang der
-- Vorauswahl ist kein Treffer – dann gilt das Talent als nicht zugeordnet (T7-NT4, Gesamtreview 18.11.2026: vorher
-- nahm Pick den einzigen Kandidaten trotzdem, und „x von y zugeordnet“ zählte ihn mit).
local function Pick(candidates, t, groupID, used)
    local best, bestScore
    local rank = tonumber(t[2]) or 1
    for _, c in ipairs(candidates) do
        local inGroup = InGroup(c.node, groupID)
        local max = tonumber(c.node.max)
        if inGroup ~= false and not used[c.node.id] and (max == nil or max >= rank) then
            local score = 0
            if inGroup == true then score = score + 8 end
            if max == rank then score = score + 2 end
            if not bestScore or score > bestScore then best, bestScore = c, score end
        end
    end
    return best
end

-- Kandidaten für ein Talent der Vorauswahl und der Weg dorthin: zuerst die erhobene Zauber-ID, dann die erhobene Lage
-- (beides sprachunabhängig), erst dann die Namen (englisch, deutsch, anderer). → Liste, "spell" | "pos" | "name"
local function Candidates(index, class, t)
    local id = Templates.PresetID(class, t)
    if id then
        local list = {}
        for _, spell in ipairs(id.spells) do
            for _, c in ipairs(index.spells[spell] or {}) do list[#list + 1] = c end
        end
        if #list > 0 then return list, "spell" end
        if id.row and id.col then
            for _, c in ipairs(index.pos[tostring(t[1]) .. ":" .. id.row .. ":" .. id.col] or {}) do list[#list + 1] = c end
            if #list > 1 then       -- Wahlknoten: die Lage nennt nur den Knoten, der Name (falls er passt) die Wahl
                local named = {}
                for i = 3, 5 do
                    local key = Templates.NormName(t[i])
                    for _, c in ipairs(key and index.names[key] or {}) do
                        for _, p in ipairs(list) do
                            if p.node.id == c.node.id and p.entry == c.entry then named[#named + 1] = p end
                        end
                    end
                end
                if #named > 0 then list = named end
            end
            if #list > 0 then return list, "pos" end
        end
    end
    local list = {}
    for i = 3, 5 do
        local key = Templates.NormName(t[i])
        for _, c in ipairs(key and index.names[key] or {}) do list[#list + 1] = c end
    end
    return list, "name"
end

-- Vorauswahl → Vorlage dieses Clients (class: Standard die eigene Klasse).
-- → tpl { nodes, choices, tree }, gefunden, gesamt, { nicht gefundene Namen },
--   how { spell, pos, name } (wie viele Talente über welchen Weg), picks { { t, node, entry, via } … }
function Templates.ResolvePreset(preset, configID, treeID, index, class)
    local tpl = { nodes = {}, choices = {}, tree = treeID }
    local missing, found, total = {}, 0, 0
    local how, picks = { spell = 0, pos = 0, name = 0 }, {}
    if type(preset) ~= "table" or type(preset.talents) ~= "table" then return tpl, 0, 0, missing, how, picks end
    index = index or Templates.PresetIndex(configID, treeID)
    local used = {}
    for _, t in ipairs(preset.talents) do
        total = total + 1
        local candidates, via = Candidates(index, class, t)
        local pick = Pick(candidates, t, index.groups[t[1]], used)
        if pick then
            found = found + 1
            how[via] = how[via] + 1
            used[pick.node.id] = true
            tpl.nodes[pick.node.id] = t[2]
            if pick.node.choice then tpl.choices[pick.node.id] = pick.entry end
            picks[#picks + 1] = { t = t, node = pick.node.id, entry = pick.entry, via = via }
        else
            missing[#missing + 1] = Templates.ClientTalentName(t, class)
        end
    end
    tpl.order, tpl.orderFrom = Templates.PresetOrder(preset, picks)
    return tpl, found, total, missing, how, picks
end

-- Reihenfolge der Punkte einer Vorauswahl (TL-01): preset.order = { je Punkt der englische Name wie in talents, bei
-- gleichnamigen Talenten "<Baum>:<Name>" }, preset.orderSource = { site, path, stand } – nur aus einer belegten
-- Quelle (Leitlinie 10 und 11), sonst keine Reihenfolge. Gilt nur, wenn jeder Schritt einem zugeordneten Talent
-- entspricht: Eine Lücke führte zu einem falschen „nächsten Punkt“. → order, Schlüssel der Website oder nil
function Templates.PresetOrder(preset, picks)
    if type(preset) ~= "table" or type(preset.order) ~= "table" or #preset.order == 0 then return nil end
    local src = preset.orderSource
    local site = type(src) == "table" and Templates.CleanOrderFrom(src.site)
    if not site or site == "clicks" then return nil end
    local byName = {}
    for _, pick in ipairs(picks or {}) do
        local t = pick.t
        byName[tostring(t[1]) .. ":" .. tostring(t[3])] = pick.node
        local plain = tostring(t[3])
        if byName[plain] == nil then byName[plain] = pick.node else byName[plain] = false end  -- gleichnamig: mit Baum nennen
    end
    local order = {}
    for _, step in ipairs(preset.order) do
        local node = byName[tostring(step)]
        if not node then return nil end
        order[#order + 1] = node
    end
    return order, site
end

---------------------------------------------------------------------------
-- Erhebung: sprachunabhängige Kennungen aus dem Client lesen (Quelle für PresetIDs.lua, Leitlinie 10 und 11)
---------------------------------------------------------------------------

-- Fassung 2 (Spieltest 15.11.2026, deutscher Client: „1 von 17 Talenten zugeordnet“, PresetIDs.lua noch leer): Ein Lauf
-- im deutschen Client lieferte bisher Lage, Zauber-ID und deutschen Namen, aber nicht, welches englisch benannte Talent
-- der Vorauswahl wohin gehört. Dazu kommen jetzt je Talent der Text des ersten Rangs und die Zeilen „fehlt“ mit allen
-- Talenten der Vorauswahl, die der Client noch nicht zuordnet (Baum, Rang, englischer und – falls belegt – deutscher
-- Name). Damit steht die ganze Zuordnung „Name(n) » Zauber-ID/Lage“ aller Bäume der Klasse in EINEM Text;
-- Tests/survey2ids.lua nennt dazu je fehlendem Talent die passenden Knoten (Baum, Höchstrang).
-- Fassung 3 (Erhebung des Nutzers vom 15.11.2026, Build 70938): Zeile und Spalte zählt Traits.Grid (fast gleiche Lagen
-- sind eine Zeile – vorher kamen beim Hexenmeister Zeilen wie 62 und 121 heraus), und eine Talentzeile trägt in Feld 9
-- Kennzeichen, wo etwas auffällt: „abseits“ (Knoten weit außerhalb des Baums, Traits.Layout), „doppelt“ (dieselbe
-- Zauber-ID an einem zweiten Knoten desselben Baums), „verborgen“ (der Client meldet den Knoten als nicht sichtbar).
-- Ohne Kennzeichen endet die Zeile wie in Fassung 2 mit dem Text.
Templates.SURVEY_HEAD, Templates.SURVEY_VERSION, Templates.SURVEY_MISSING = "ezTalent-Erhebung", 3, "fehlt"
Templates.SURVEY_ASIDE, Templates.SURVEY_DOUBLE, Templates.SURVEY_HIDDEN = "abseits", "doppelt", "verborgen"
Templates.SURVEY_TEXT_BYTES = 120     -- Text je Talent gekürzt: reicht, um es zu erkennen, hält den Text kopierbar

-- Kennzeichen „doppelt“ je Zeile: dieselbe Zauber-ID an einem zweiten Knoten desselben Baums (row.node). Gemeinsam für
-- die Erhebung und die Messung „Werte für die Simulation“ (Measure.lua). rows: { { tree, spell, node } … } – setzt row.double
function Templates.MarkDoubles(rows)
    local nodesOfSpell = {}
    for _, row in ipairs(rows) do
        if (row.spell or 0) > 0 then
            local key = row.tree .. ":" .. row.spell
            nodesOfSpell[key] = nodesOfSpell[key] or {}
            nodesOfSpell[key][row.node] = true
        end
    end
    for _, row in ipairs(rows) do
        local n = 0
        for _ in pairs((row.spell or 0) > 0 and nodesOfSpell[row.tree .. ":" .. row.spell] or {}) do n = n + 1 end
        row.double = n > 1
    end
    return rows
end

-- Kennzeichen einer Zeile als Feld („abseits,doppelt,verborgen“) oder nil, wenn nichts auffällt. Erhebung und Messung.
function Templates.SurveyFlags(row)
    local flags = {}
    if row.aside then flags[#flags + 1] = Templates.SURVEY_ASIDE end
    if row.double then flags[#flags + 1] = Templates.SURVEY_DOUBLE end
    if row.hidden then flags[#flags + 1] = Templates.SURVEY_HIDDEN end
    return #flags > 0 and table.concat(flags, ",") or nil
end

-- Text eines Eintrags im ersten Rang, schlicht und kurz (ohne Farbcodes, ohne Zeilenumbruch) – nur für die Erhebung.
local function SurveyEntryText(configID, entryID)
    local entry = Traits.Entry(configID, entryID, 1)
    local text = type(entry) == "table" and type(entry.text) == "string" and entry.text or ""
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%s+", " ")
    return Core.TruncateBytes(Core.Trim(text), Templates.SURVEY_TEXT_BYTES) or ""
end

-- Je Eintrag jedes Knotens aller Talentbäume der Klasse: Lage, Höchstrang, Zauber-ID, Name im Client, Text des ersten
-- Rangs und – wo die Vorauswahl der Klasse das Talent hier schon zuordnet – ihr englischer Name. In Lesereihenfolge
-- (Baum, Zeile, Spalte). Dazu die Talente der Vorauswahl, die der Client nicht zuordnet (je „Baum:englischer Name“ einmal,
-- Rang = höchster Rang in der Vorauswahl), nach Baum und Name.
-- aside, double, hidden: Kennzeichen (siehe Fassung 3).
-- → { { tree, row, col, max, spell, name, text, node, entry, en, aside, double, hidden } … }, { { tree, rank, en, de } … }
function Templates.Survey(configID, treeID, class)
    configID = configID or Traits.ClassConfigID()
    treeID = treeID or Traits.TreeOfConfig(configID)
    local rows, missing = {}, {}
    if not (configID and treeID) then return rows, missing end
    local index = Templates.PresetIndex(configID, treeID)
    local english, matched, wanted = {}, {}, {}
    for _, preset in ipairs(Templates.Researched(class)) do
        local _, _, _, _, _, picks = Templates.ResolvePreset(preset, configID, treeID, index, class)
        for _, pick in ipairs(picks) do
            english[pick.node .. ":" .. pick.entry] = pick.t[3]
            matched[tostring(pick.t[1]) .. ":" .. tostring(pick.t[3])] = true
        end
        for _, t in ipairs(type(preset.talents) == "table" and preset.talents or {}) do
            local key = tostring(t[1]) .. ":" .. tostring(t[3])
            local rank = tonumber(t[2]) or 0
            if not wanted[key] then
                wanted[key] = { tree = tonumber(t[1]) or 0, rank = rank, en = tostring(t[3] or ""),
                    de = type(t[4]) == "string" and t[4] or "" }
            elseif rank > wanted[key].rank then
                wanted[key].rank = rank
            end
        end
    end
    for _, node in ipairs(Traits.Nodes(configID, treeID)) do
        local where = index.layout[node.id] or {}
        for _, entryID in ipairs(node.entries) do
            rows[#rows + 1] = { tree = where.tree or 0, row = where.row or 0, col = where.col or 0, max = node.max,
                spell = Traits.EntrySpell(configID, entryID) or 0, name = Traits.EntryName(configID, entryID) or "",
                text = SurveyEntryText(configID, entryID), node = node.id, entry = entryID,
                en = english[node.id .. ":" .. entryID], aside = where.aside == true, hidden = node.visible == false }
        end
    end
    Templates.MarkDoubles(rows)
    table.sort(rows, function(a, b)
        if a.tree ~= b.tree then return a.tree < b.tree end
        if a.row ~= b.row then return a.row < b.row end
        if a.col ~= b.col then return a.col < b.col end
        return a.entry < b.entry
    end)
    for key, w in pairs(wanted) do
        if not matched[key] then missing[#missing + 1] = w end
    end
    table.sort(missing, function(a, b)
        if a.tree ~= b.tree then return a.tree < b.tree end
        return a.en < b.en
    end)
    return rows, missing
end

-- Die Erhebung als Text zum Kopieren. Erste Zeile: Kennung;Fassung;Klasse;Sprache;Build;Datum. Danach je Talent
-- „Baum;Zeile;Spalte;Höchstrang;Zauber-ID;Name im Client;englischer Name der Vorauswahl;Text“ (englischer Name leer,
-- wenn die Vorauswahl das Talent hier nicht zuordnet oder nicht verwendet), dann je nicht zugeordnetem Talent der
-- Vorauswahl „fehlt;Baum;Rang;englischer Name;deutscher Name“. Fällt an einer Talentzeile etwas auf, folgt als Feld 9
-- die Liste der Kennzeichen, durch Kommas getrennt („abseits,doppelt“).
-- → Text, Zahl der Talentzeilen, Zahl der Talentzeilen ohne Namen; nil ohne Talentdaten
function Templates.SurveyText(configID, treeID, class)
    class = class or Core.PlayerClass() or "?"
    local rows, missing = Templates.Survey(configID, treeID, class)
    if #rows == 0 then return nil, 0, 0 end
    local version, build = Core.Call(rawget(_G, "GetBuildInfo"))
    local stamp = tostring(Core.Plain(version) or "?") .. "." .. tostring(Core.Plain(build) or "?")
    local function Field(value) return (tostring(value == nil and "" or value):gsub("[;\r\n]", " ")) end
    local lines = { table.concat({ Templates.SURVEY_HEAD, Templates.SURVEY_VERSION, class,
        Field(Core.Call(rawget(_G, "GetLocale")) or "?"), Field(stamp), date and date("%Y-%m-%d") or "?" }, ";") }
    local unnamed = 0
    for _, row in ipairs(rows) do
        if row.name == "" then unnamed = unnamed + 1 end
        local fields = { row.tree, row.row, row.col, row.max, row.spell, Field(row.name), Field(row.en), Field(row.text) }
        fields[#fields + 1] = Templates.SurveyFlags(row)
        lines[#lines + 1] = table.concat(fields, ";")
    end
    for _, w in ipairs(missing) do
        lines[#lines + 1] = table.concat({ Templates.SURVEY_MISSING, w.tree, w.rank, Field(w.en), Field(w.de) }, ";")
    end
    return table.concat(lines, "\n"), #rows, unnamed
end

-- Sichtbarer Weg: Knopf „Talente erheben“ auf der Einstellungsseite (Erweitert); /ezt erheben zusätzlich.
function Templates.ShowSurvey()
    local text, count, unnamed = Templates.SurveyText()
    if not text then
        ns.Print(L.SURVEY_NONE)
        return false
    end
    local hint = L.SURVEY_HINT
    if (unnamed or 0) > 0 then hint = hint .. "\n" .. L.SURVEY_NO_NAMES:format(unnamed) end
    if Core.TextDialog then
        Core.TextDialog({ title = L.SURVEY_TITLE:format(count), hint = hint, text = text, select = true,
            readOnly = true, owner = ADDON })
    else
        for line in text:gmatch("[^\n]+") do ns.Print(line) end
    end
    return true
end

-- Wie viele verschiedene Talente der Vorauswahl einer Klasse haben schon eine erhobene Kennung? → mit, gesamt
function Templates.PresetIDCoverage(class)
    local seen, with, total = {}, 0, 0
    for _, preset in ipairs(Templates.Researched(class)) do
        for _, t in ipairs(preset.talents or {}) do
            local key = tostring(t[1]) .. ":" .. tostring(t[3])
            if not seen[key] then
                seen[key] = true
                total = total + 1
                local id = Templates.PresetID(class, t)
                if id and (#id.spells > 0 or (id.row and id.col)) then with = with + 1 end
            end
        end
    end
    return with, total
end

-- Name eines Talents der Vorauswahl so, wie der Client es nennt (Welle 23, A3): über die Zauber-ID aus PresetIDs.lua
-- bzw. am Talent (berechnete Verteilungen) – Core.SpellName in der Sprache des Clients. Ohne Kennung oder ohne Namen im
-- Client der Name der Vorauswahl wie bisher (Templates.TalentName: deutsch, wo belegt, sonst englisch).
function Templates.ClientTalentName(t, class)
    local id = Templates.PresetID(class, t)
    for _, spell in ipairs(id and id.spells or {}) do
        local name = Core.SpellName(spell)
        if type(name) == "string" and name ~= "" then return name end
    end
    return Templates.TalentName(t)
end

-- Wirkungsänderungen durch Hotfixes, die gewählte Talente dieser Vorauswahl betreffen (Baum bleibt, Vermerk sichtbar).
-- → { { name, date } … } – name mit dem Namen des Clients (Templates.ClientTalentName)
function Templates.PresetHotfixes(class, preset)
    local out = {}
    local fixes = ns.PRESET_HOTFIXES and ns.PRESET_HOTFIXES[class or Core.PlayerClass() or ""]
    if type(fixes) ~= "table" or type(preset) ~= "table" then return out end
    for _, fix in ipairs(fixes) do
        for _, t in ipairs(preset.talents or {}) do
            if t[3] == fix[1] then
                out[#out + 1] = { name = Templates.ClientTalentName(t, class), date = fix[2] }
                break
            end
        end
    end
    return out
end

-- Punkte je Baum aus der Talentliste („18/33/0“) – zum Prüfen der Daten gegen split.
function Templates.PresetSplit(preset)
    local sums = { 0, 0, 0 }
    for _, t in ipairs(type(preset) == "table" and preset.talents or {}) do
        local tree, rank = tonumber(t[1]), tonumber(t[2])
        if tree and rank then sums[tree] = (sums[tree] or 0) + rank end
    end
    return table.concat(sums, "/")
end

-- Volle Adresse einer Quelle der Vorauswahl.
function Templates.SourceURL(source)
    local site = type(source) == "table" and ns.PRESET_SITES and ns.PRESET_SITES[source.site]
    if not site then return nil end
    return site.base .. (source.path or "")
end

-- Vorauswahl als eigene Vorlage kopieren (danach änderbar). Alte Form mit preset.nodes (Knoten-IDs) geht weiter.
-- Nur teilweise zugeordnet (gefunden < gesamt) kopiert sie erst mit opts.partial = true (UI: nach Rückfrage, T1) –
-- nie still als Teilvorlage; die Vorlage trägt dann unmatched/matchTotal.
-- → Name oder nil, Grund ("missing", "nomatch", "partial", …); dazu gefunden, gesamt, { nicht gefundene Namen }
function Templates.CopyPreset(class, preset, configID, treeID, opts)
    if type(preset) ~= "table" then return nil, "missing" end
    opts = opts or {}
    local scope = Templates.ClassScope(class)
    local nodes, choices, found, total, missing = preset.nodes, preset.choices, nil, nil, {}
    local order, orderFrom
    if type(preset.talents) == "table" then
        configID = configID or Traits.ClassConfigID()
        treeID = treeID or Traits.TreeOfConfig(configID)
        local tpl
        tpl, found, total, missing = Templates.ResolvePreset(preset, configID, treeID, nil, class)
        if found == 0 then return nil, "nomatch", found, total, missing end
        if found < total and not opts.partial then return nil, "partial", found, total, missing end
        nodes, choices, order, orderFrom = tpl.nodes, tpl.choices, tpl.order, tpl.orderFrom
    end
    local name = Templates.UniqueName(scope, Templates.PresetName(preset))
    local snapshot = { nodes = nodes, choices = choices, tree = treeID or preset.treeID, order = order, orderFrom = orderFrom }
    if found and total and found < total then snapshot.unmatched, snapshot.matchTotal = total - found, total end
    local saved, why = Templates.Save(scope, name, snapshot, { primary = tonumber(preset.tree) })
    return saved, why, found, total, missing
end

---------------------------------------------------------------------------
-- Eigene Vorlagen aus einer unvollständig zugeordneten Vorauswahl neu zuordnen (Spieltest 15.11.2026: „Dämonologie –
-- Schatten, Sukkubus, Pakt · 2 Punkte“, „Gebrechen – Wrack · 1 Punkte“ und „Gebrechen – Wrack (2)“ trugen weiter
-- „unvollständig zugeordnet“, obwohl seit Welle 11 alle neun Klassen Kennungen haben). Solche Vorlagen hielten nur die
-- Talente, die der Client damals über den Namen fand. Einmal je Sitzung und Klasse sucht ezTalent zu jeder Vorlage mit
-- Kennzeichen (unmatched) die Vorauswahl, aus der sie kopiert wurde – über ihren Namen (deutsch oder englisch; der
-- Zusatz „ (2)“ und die Kürzung auf MAX_NAME Zeichen zählen mit) –, ordnet diese über PresetIDs und den Client neu zu
-- und prüft, dass jedes gespeicherte Talent dort mit demselben Rang steht (sonst wurde die Vorlage verändert, und
-- ezTalent lässt sie, wie sie ist). Ergebnis: vollständig → ohne Kennzeichen; besser, aber noch nicht vollständig →
-- mit der neuen Zahl; sonst bleibt sie und nennt den Grund (Tooltip, Chat).
---------------------------------------------------------------------------

Templates.remapTried = {}     -- je Scope: in dieser Sitzung schon versucht
Templates.remapFail = {}      -- je Scope und Name: Grund, warum es nicht ging ("nopreset", "ambiguous", "changed", "partial")

-- Name einer eigenen Vorlage ohne Zusatz „ (2)“; dazu, ob der Name gekürzt sein kann (Zusatz oder volle Länge).
local function BaseName(name)
    name = tostring(name or "")
    local base = name:match("^(.-) %(%d+%)$")
    if base then return Core.Trim(base), true end
    local chars = select(2, name:gsub("[^\128-\191]", ""))          -- Zeichen, nicht Bytes (UTF-8)
    return Core.Trim(name), chars >= Templates.MAX_NAME - 1
end

-- Vorauswahlen, aus denen eine eigene Vorlage dieses Namens kopiert sein kann (gleicher Name in einer Sprache, bei
-- gekürzten Namen der Anfang). → Liste
function Templates.PresetsNamed(class, name)
    local base, maybeCut = BaseName(name)
    local exact, prefix = {}, {}
    if base == "" then return exact end
    for _, preset in ipairs(Templates.Presets(class)) do
        local names = type(preset.name) == "table" and { preset.name.de, preset.name.en } or { preset.name }
        local hitExact, hitPrefix = false, false
        for _, n in ipairs(names) do
            if type(n) == "string" then
                if n == base then hitExact = true
                elseif maybeCut and #base >= 8 and n:sub(1, #base) == base then hitPrefix = true end
            end
        end
        if hitExact then exact[#exact + 1] = preset elseif hitPrefix then prefix[#prefix + 1] = preset end
    end
    return #exact > 0 and exact or prefix
end

-- Steht jedes Talent der alten Vorlage mit demselben Rang (und derselben Wahl) in der neuen Zuordnung?
local function Covered(old, new)
    for id, rank in pairs(old.nodes or {}) do
        if tonumber(new.nodes[tonumber(id)] or new.nodes[tostring(id)]) ~= tonumber(rank) then return false end
    end
    for id, entry in pairs(old.choices or {}) do
        local now = new.choices[tonumber(id)] or new.choices[tostring(id)]
        if now ~= nil and tonumber(now) ~= tonumber(entry) then return false end
    end
    return true
end

-- Eine Vorlage neu zuordnen. → "done" | "better" | Grund des Fehlschlags; dazu gefunden, gesamt
function Templates.RemapOne(scope, name, configID, treeID, index, class)
    local tpl = Templates.Get(scope, name)
    if type(tpl) ~= "table" or not tpl.unmatched then return nil end
    local hits = {}
    for _, preset in ipairs(Templates.PresetsNamed(class, name)) do
        if type(preset.talents) == "table" then
            local new, found, total = Templates.ResolvePreset(preset, configID, treeID, index, class)
            if found > 0 and Covered(tpl, new) then hits[#hits + 1] = { preset = preset, tpl = new, found = found, total = total } end
        end
    end
    if #hits == 0 then
        return #Templates.PresetsNamed(class, name) == 0 and "nopreset" or "changed"
    end
    if #hits > 1 then return "ambiguous" end
    local hit = hits[1]
    local before = (tpl.matchTotal or tpl.unmatched) - tpl.unmatched
    if hit.found <= before then return "partial", hit.found, hit.total end
    tpl.nodes, tpl.choices = hit.tpl.nodes, hit.tpl.choices
    if not tpl.order and hit.tpl.order then tpl.order, tpl.orderFrom = hit.tpl.order, hit.tpl.orderFrom end
    if hit.found >= hit.total then
        tpl.unmatched, tpl.matchTotal = nil, nil
    else
        tpl.unmatched, tpl.matchTotal = hit.total - hit.found, hit.total
    end
    tpl.points = Traits.Points(tpl)
    tpl.primary = tpl.primary or tonumber(hit.preset.tree)
    tpl.remapped = time and time() or 0
    return hit.found >= hit.total and "done" or "better", hit.found, hit.total
end

-- Alle Vorlagen mit Kennzeichen eines Klassen-Scopes neu zuordnen – einmal je Sitzung (nur, wenn der Client den Baum
-- liefert; sonst später noch einmal). → { done = { Name … }, better = { … }, fail = { { name, why, found, total } … } }
-- oder nil (nichts versucht)
function Templates.RemapOwn(scope, configID, treeID, class)
    if not (scope and configID and treeID) or Templates.remapTried[scope] then return nil end
    local kind, value = Templates.ParseScope(scope)
    if kind ~= "class" then return nil end
    class = class or value
    if #Traits.Nodes(configID, treeID) == 0 then return nil end     -- Baum noch nicht geladen: später
    Templates.remapTried[scope] = true
    local out, index, changed = { done = {}, better = {}, fail = {} }, nil, false
    Templates.remapFail[scope] = {}
    for _, name in ipairs(Templates.Names(scope)) do
        local tpl = Templates.Get(scope, name)
        if type(tpl) == "table" and tpl.unmatched then
            index = index or Templates.PresetIndex(configID, treeID)
            local why, found, total = Templates.RemapOne(scope, name, configID, treeID, index, class)
            if why == "done" or why == "better" then
                changed = true
                table.insert(out[why], name)
            end
            if why == "done" then tpl.remapSaid = nil end
            if why and why ~= "done" then
                Templates.remapFail[scope][name] = why
                -- Im Chat nur, wenn der Grund neu ist – sonst käme dieselbe Zeile bei jedem Einloggen (Gegenprüfung
                -- Welle 13); der Tooltip nennt ihn immer. „besser“ heißt beim nächsten Mal „weiter nur x von y“.
                local key = (why == "better" and "partial" or why) .. ":" .. tostring(found) .. "/" .. tostring(total)
                local fresh = tpl.remapSaid ~= key
                tpl.remapSaid = key
                if why ~= "better" then
                    out.fail[#out.fail + 1] = { name = name, why = why, found = found, total = total, new = fresh }
                end
            end
        end
    end
    if changed then ns.Fire("TEMPLATES_CHANGED", scope) end
    return out
end

-- Text zum Grund (Tooltip und Chat).
function Templates.RemapWhy(why, found, total)
    if why == "partial" and found and total then return L.REMAP_WHY_partial:format(found, total) end
    return L["REMAP_WHY_" .. tostring(why)] or tostring(why)
end

-- Ergebnis von RemapOwn in den Chat: eine Zeile für die neu zugeordneten, eine für die übrigen (mit Grund; nur, was
-- seit der letzten Meldung neu ist).
function Templates.ReportRemap(out)
    if type(out) ~= "table" then return false end
    local said = false
    local fixed = {}
    for _, name in ipairs(out.done) do fixed[#fixed + 1] = L.REMAP_NAME:format(name) end
    if #fixed > 0 then
        ns.Print(L.REMAP_DONE:format(table.concat(fixed, ", ")))
        said = true
    end
    local rest = {}
    for _, name in ipairs(out.better) do rest[#rest + 1] = L.REMAP_NAME:format(name) .. " (" .. Templates.RemapWhy("better") .. ")" end
    for _, f in ipairs(out.fail) do
        if f.new ~= false then
            rest[#rest + 1] = L.REMAP_NAME:format(f.name) .. " (" .. Templates.RemapWhy(f.why, f.found, f.total) .. ")"
        end
    end
    if #rest > 0 then
        ns.Print(L.REMAP_REST:format(table.concat(rest, ", ")))
        said = true
    end
    return said
end

---------------------------------------------------------------------------
-- Passende Rotation (Punkt 3): ezCombat kennt sie, ezTalent nennt sie nur
---------------------------------------------------------------------------

-- Zusammenfassung der Rotation für den Hauptbaum der Vorlage ({ key, name, … } von ezCombat) oder nil.
function Templates.RotationFor(tpl, class)
    if type(tpl) ~= "table" or not tpl.primary then return nil end
    local combat = Core.API("ezCombat")
    if not (combat and type(combat.RotationFor) == "function") then return nil end
    local ok, rotation = pcall(combat.RotationFor, class or Core.PlayerClass(), tpl.primary)
    return ok and type(rotation) == "table" and rotation or nil
end

-- Berechnete Rotation zu einer berechneten Verteilung (Schlüssel aus Computed.lua, z. B. „sim-arms“; beide entstehen im
-- selben Lauf von tools/rotation_sim.lua – ezCombat API RotationForBuild, Welle 21/23 A4) oder nil.
function Templates.RotationForBuild(key, class)
    if type(key) ~= "string" then return nil end
    local combat = Core.API("ezCombat")
    if not (combat and type(combat.RotationForBuild) == "function") then return nil end
    local ok, rotation = pcall(combat.RotationForBuild, key, class or Core.PlayerClass())
    return ok and type(rotation) == "table" and rotation or nil
end

-- Passende Rotation zu einem geladenen Plan: bei einer berechneten Verteilung die berechnete Rotation desselben Laufs,
-- sonst die Vorlage für den Hauptbaum. → Rotation oder nil, berechnet (true, wenn über RotationForBuild)
function Templates.RotationForPlan(plan, class)
    if type(plan) ~= "table" then return nil, false end
    if plan.kind == "preset" and Templates.IsComputed(plan.preset) then
        local rotation = Templates.RotationForBuild(plan.key, class)
        if rotation then return rotation, true end
    end
    return Templates.RotationFor(plan.tpl, class), false
end

-- Diese Rotation in ezCombat wählen. → true, wenn ezCombat sie angenommen hat.
function Templates.SelectRotation(rotation)
    local combat = Core.API("ezCombat")
    if not (rotation and rotation.key and combat and type(combat.SelectRotation) == "function") then return false end
    local ok, done = pcall(combat.SelectRotation, rotation.key)
    return ok and done == true
end

---------------------------------------------------------------------------
-- Ausrüstungsset und Leistenprofil zur Vorlage (TL-02, VP-36; Frage 19 – Empfehlung umgesetzt, Antwort offen):
-- ezGear kennt die Sets (API Sets/EquipSet), ezMacro die Leistenprofile (API ProfileNames/LoadProfile). ezTalent
-- merkt nur den Namen und bietet ihn nach „Übernehmen“ an – angelegt bzw. geladen wird erst auf Klick.
---------------------------------------------------------------------------

Templates.LINKS = { "gear", "bars" }
local LINK_MODULE = { gear = "ezGear", bars = "ezMacro" }

local function LinkAPI(field)
    local module = LINK_MODULE[field]
    local api = module and Core.API(module)
    if type(api) ~= "table" then return nil end
    if field == "gear" and type(api.Sets) == "function" and type(api.EquipSet) == "function" then return api end
    if field == "bars" and type(api.ProfileNames) == "function" and type(api.LoadProfile) == "function" then return api end
    return nil
end

-- Liste des Moduls bereinigen: je Name ein Eintrag { name, icon, class, equipped }, nach Name sortiert. Gesperrte
-- Werte (Leitlinie 6) werden weder verglichen noch übernommen.
local function LinkCollect(fn)
    local ok, list = pcall(fn)
    local out, seen = {}, {}
    for _, item in ipairs(ok and type(list) == "table" and list or {}) do
        local name = CleanLink(type(item) == "table" and item.name or item)
        if name and not seen[name] then
            seen[name] = true
            local entry = { name = name }
            if type(item) == "table" then
                local icon, class, equipped = item.icon, item.class, item.equipped
                if not Core.IsSecret(icon) and (type(icon) == "number" or type(icon) == "string") then entry.icon = icon end
                if not Core.IsSecret(class) and type(class) == "string" and class ~= "" then entry.class = class end
                if not Core.IsSecret(equipped) and equipped == true then entry.equipped = true end
            end
            out[#out + 1] = entry
        end
    end
    table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
    return out
end

-- Wählbare Namen: { "Name" … } sortiert; nil, wenn das Modul fehlt (dann gibt es das Feld in der Oberfläche nicht).
function Templates.LinkChoices(field)
    local api = LinkAPI(field)
    if not api then return nil end
    local names = {}
    for i, entry in ipairs(LinkCollect(field == "gear" and api.Sets or api.ProfileNames)) do names[i] = entry.name end
    return names
end

-- Dieselben Einträge mit dem, was das Modul dazu weiß – für das Menü zur Wahl (Welle 27, Zweig modul/eztalent-menue):
-- { { name, icon = Bild des Sets (Blizzards Ausrüstungsmanager über ezGear), class = Klasse, mit der ein Profil
-- gespeichert wurde (ezMacros ProfileList), equipped = true (Set gerade angelegt) } … }; nil ohne Modul. Ohne
-- ProfileList (ältere ezMacro-Fassung) nur die Namen.
function Templates.LinkEntries(field)
    local api = LinkAPI(field)
    if not api then return nil end
    if field == "gear" then return LinkCollect(api.Sets) end
    return LinkCollect(type(api.ProfileList) == "function" and api.ProfileList or api.ProfileNames)
end

-- Verwalten im Modul (letzter Eintrag des Menüs zur Wahl): nur, wo das Modul dafür eine Schnittstelle hat – ezMacro
-- OpenProfiles (Werkzeug „Leisten-Profile“); ezGear hat keine. Templates.CanOpenLink(feld) → true/false;
-- Templates.OpenLink(feld) → true, wenn geöffnet
local LINK_OPEN = { bars = "OpenProfiles" }

-- Nennt das Modul, mit welcher Klasse ein Eintrag gespeichert wurde? (ezMacro mit ProfileList: ja; ältere Fassung und
-- ezGear: nein) → true/false. Ohne Klasseninfo ist die Klasse unbekannt, nicht leer (Fund des code-reviewers).
function Templates.LinkHasClass(field)
    local api = LinkAPI(field)
    return field == "bars" and api ~= nil and type(api.ProfileList) == "function"
end
function Templates.CanOpenLink(field)
    local api, key = LinkAPI(field), LINK_OPEN[field]
    return api ~= nil and key ~= nil and type(api[key]) == "function"
end
function Templates.OpenLink(field)
    if not Templates.CanOpenLink(field) then return false end
    local ok, done = pcall(LinkAPI(field)[LINK_OPEN[field]])
    return ok and done ~= false
end

-- Gibt es den gemerkten Namen im Modul noch? (gelöscht oder umbenannt: nein) → true/false; ohne Modul nil
function Templates.LinkKnown(field, name)
    local choices = Templates.LinkChoices(field)
    if not choices then return nil end
    name = CleanLink(name)
    for _, choice in ipairs(choices) do
        if choice == name then return true end
    end
    return false
end

-- Set bzw. Profil an eine Vorlage hängen (name = nil: lösen). → true oder false, Grund ("missing", "field")
function Templates.SetLink(scope, tplName, field, name)
    if not LINK_MODULE[field] then return false, "field" end
    local tpl = Templates.Get(scope, tplName)
    if not tpl then return false, "missing" end
    tpl[field] = CleanLink(name)
    ns.Fire("TEMPLATES_CHANGED", scope)
    return true
end

-- Set anlegen bzw. Profil laden (ezMacro fragt selbst nach). → true (erledigt oder vorgemerkt), Grund von ezGear |
-- false, "module" (Modul fehlt) | false, "failed"
function Templates.UseLink(field, name)
    local api = LinkAPI(field)
    if not api then return false, "module" end
    name = CleanLink(name)
    if not name then return false, "failed" end
    local ok, done, why
    if field == "gear" then
        ok, done, why = pcall(api.EquipSet, name)
    else
        ok, done = pcall(api.LoadProfile, name)
    end
    if not ok then return false, "failed" end
    return done == true, why
end

---------------------------------------------------------------------------
-- Zuletzt angewandt (je Charakter und Scope) – für die Twink-Übersicht
---------------------------------------------------------------------------

-- configID: die Talentgruppe, in der übernommen wurde (Plan.Followed folgt der Vorlage nur dort).
function Templates.NoteApplied(scope, name, configID)
    if not (ns.db and scope) then return end
    local key = ns.charKey or Core.charKey
    if not key then return end
    ns.db.chars[key] = type(ns.db.chars[key]) == "table" and ns.db.chars[key] or {}
    local c = ns.db.chars[key]
    c.applied = type(c.applied) == "table" and c.applied or {}
    c.applied[scope] = name
    c.appliedConfig = type(c.appliedConfig) == "table" and c.appliedConfig or {}
    c.appliedConfig[scope] = tonumber(configID)
end

-- Schnittstelle für andere Module
ns.API.TemplateNames = function(class) return Templates.Names(Templates.ClassScope(class)) end
ns.API.LegacyTemplateNames = function(treeID) return Templates.Names(Templates.LegacyScope(treeID)) end
