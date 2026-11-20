local ADDON, ns = ...
local Core = ezCore
local L = ns.L
local Traits = ns.Traits

--[[
    Messwerte für die Talent-Simulation (Welle 21, docs/talent-simulation.md; Wunsch des Nutzers vom 15.11.2026).

    Das Rechnen läuft offline (tools/talent_sim.lua, LuaJIT) – im Spiel liest ezTalent nur aus, was der Client weiß
    (Leitlinie 11: der Client zuerst), und gibt es als EINEN Text zum Kopieren aus:
      - Grundwerte des Charakters: Stufe, Stärke, Beweglichkeit, Ausdauer, Intelligenz, Willenskraft, Gesundheit,
        Mana bzw. Kraft, Rüstung, Angriffskraft, kritische Treffer, Ausweichen, Parieren, Blocken, Zaubermacht,
        Heilung, Mana- und Kraftregeneration, Waffenschaden und Angriffstempo (UnitStat, UnitHealthMax, UnitPowerMax, UnitArmor,
        GetCritChance, GetPowerRegen … – Blizzards Funktionen, jede geschützt; geheime Werte werden übersprungen, Leitlinie 6).
        „Nackt“ heißt: kein Gegenstand auf den Plätzen 1–19 außer Hemd und Wappenrock (GetInventoryItemID).
      - Je Talent deiner Klasse: Lage, Höchstrang, Zauber-ID, Schwelle („benötigt n Punkte im Baum“) und Vorgänger aus
        den Bedingungen und Kanten des Clients (Traits.Condition, Traits.Incoming), dazu der Text jedes Rangs
        (C_Traits.GetTraitDescription wie Blizzards Talent-Tooltip) – verdichtet: Text mit Platzhaltern {1}, {2} … und
        die Zahlen je Rang. Weicht der Text eines Rangs außer in den Zahlen ab, steht jeder Rang ganz da.
    Gemerkt (SavedVariables ezTalentDB.measure, ohne Charakternamen): die Grundwerte je Klasse, Volk und Stufe – damit
    sie auch nach dem Schließen des Fensters weitergegeben werden können (Knopf „Gemerkte Grundwerte zeigen“ unter
    „Erweitert“, Measure.ShowSaved); eine unsauberere Messung ersetzt keine sauberere (Measure.Remember).

    Form des Textes (Fassung 1, gelesen von tools/talent_sim.lua):
      ezTalent-Werte;1;<Klasse>;<Volk>;<Stufe>;<Sprache>;<Build>;<Datum>;<Zahl angelegter Gegenstände>
      wert;<Schlüssel>;<Zahl>
      talent;<Baum>;<Zeile>;<Spalte>;<Höchstrang>;<Zauber-ID>;<Schwelle>;<Vorgänger>;<Name>;<Text mit {n}>;<Zahlen je Rang>[;<Kennzeichen>]
        Vorgänger: „Zeile:Spalte“ je erforderlichem Vorgänger, durch Kommas getrennt („~Zeile:Spalte“ = einer von
        mehreren genügt); Zahlen je Rang: je Rang die Zahlen durch Leerzeichen, die Ränge durch „/“ („1 6/2 12/3 18“),
        Dezimalpunkt; Kennzeichen (nur wenn etwas auffällt, wie in der Erhebung – Templates.SurveyFlags): „abseits“
        (Knoten weit außerhalb des Baums), „doppelt“ (dieselbe Zauber-ID an einem zweiten Knoten desselben Baums),
        „verborgen“ (der Client meldet den Knoten als nicht sichtbar). Das Werkzeug verwirft verborgene Knoten und das
        Doppel abseits, wenn derselbe Zauber im Baum steht (wie Templates.PresetIndex) – sonst zählte ein Talent zweimal.
      rangtext;<Baum>;<Zeile>;<Spalte>;<Zauber-ID>;<Rang>;<Text>
]]

local Measure = {}
ns.Measure = Measure

Measure.HEAD, Measure.VERSION = "ezTalent-Werte", 1
Measure.MAX_LEVEL = 60          -- Stufe, für die die Simulation rechnet (Höchststufe in Forever)
Measure.TALENT_LEVEL = 10       -- ab dieser Stufe gibt es Talentpunkte (darunter fehlen die Talente in der Messung)
Measure.SLOTS = 19              -- Ausrüstungsplätze 1–19 (Kopf … Wappenrock)
Measure.NO_STATS = { [4] = true, [19] = true }   -- Hemd und Wappenrock tragen keine Werte
Measure.SCHOOLS = { 2, 3, 4, 5, 6, 7 }           -- Zauberschulen (Heilig … Arkan); die kleinste Zahl ist der Grundwert

-- Sprachen mit Dezimalkomma (und Punkt als Tausender-Trenner) – alle übrigen schreiben „2.5“ und „1,000“.
Measure.COMMA_DECIMAL = { deDE = true, frFR = true, esES = true, esMX = true, itIT = true, ptBR = true, ruRU = true }

-- Zahl aus dem Text eines Tooltips („2,5“ bzw. „1.000“ im deutschen Client) → number oder nil.
function Measure.Number(s, comma)
    if type(s) ~= "string" or s == "" then return nil end
    local thousand, decimal = comma and "%." or ",", comma and "," or "."
    -- Tausender-Trenner nur in der Form 1.000 bzw. 1.000.000 (genau drei Ziffern je Gruppe)
    if s:find("^%d%d?%d?" .. thousand .. "%d%d%d") then
        local plain = s:gsub(thousand .. "(%d%d%d)", "%1")
        if plain:find("^%d+$") or plain:find("^%d+" .. (comma and "," or "%.") .. "%d+$") then s = plain end
    end
    if decimal == "," then s = s:gsub(",", ".") end
    return tonumber(s)
end

-- Text mit Platzhaltern {1}, {2} … statt der Zahlen und die Zahlen dazu. → Text, { Zahl … }
function Measure.Template(text, locale)
    local nums = {}
    if type(text) ~= "string" then return "", nums end
    local comma = Measure.COMMA_DECIMAL[locale or ""] == true
    local out = text:gsub("%d[%d%.,]*", function(s)
        local tail = s:match("[%.,]+$") or ""
        local value = Measure.Number(s:sub(1, #s - #tail), comma)
        if not value then return nil end
        nums[#nums + 1] = value
        return "{" .. #nums .. "}" .. tail
    end)
    return out, nums
end

-- Zahl für den Text: ganzzahlig ohne Nachkommastellen, sonst höchstens vier Stellen (Dezimalpunkt).
function Measure.Format(value)
    if type(value) ~= "number" then return "" end
    if value == math.floor(value) and math.abs(value) < 1e12 then return string.format("%d", value) end
    return (string.format("%.4f", value):gsub("0+$", ""):gsub("%.$", ""))
end

-- Werte aus dem Client, geschützt (Core.Call); Pick nimmt nur Zahlen, die nicht geheim sind (Leitlinie 6).
-- → Liste der Rückgabewerte bzw. Zahl oder nil, geheim?
local function Read(fn, ...)
    return { Core.Call(rawget(_G, fn), ...) }
end

local function Pick(values, i)
    local v = values[i]
    if Core.IsSecret(v) then return nil, true end
    if type(v) ~= "number" then return nil, false end
    return v, false
end

-- Grundwerte des eigenen Charakters. → { Schlüssel = Zahl }, Zahl angelegter Gegenstände, Zahl geheimer Werte, Zahl der
-- Werte mit Bonus (UnitStat Rückgabe 3/4 bzw. UnitAttackPower 2/3 ungleich 0: Stärkungszauber, Ausrüstung, Talente)
function Measure.Stats()
    local stats, secret, buffed = {}, 0, 0
    local function Bonus(pos, neg)
        if (pos or 0) > 0 or (neg or 0) < 0 then buffed = buffed + 1 end
    end
    local function Put(key, value, isSecret)
        if isSecret then secret = secret + 1 elseif value then stats[key] = value end
    end
    Put("level", Pick(Read("UnitLevel", "player"), 1))
    for i, key in ipairs({ "str", "agi", "sta", "int", "spi" }) do
        local values = Read("UnitStat", "player", i)
        Put(key, Pick(values, 2))
        Put(key .. "Base", Pick(values, 1))
        Bonus(Pick(values, 3), (Pick(values, 4)))
    end
    Put("hp", Pick(Read("UnitHealthMax", "player"), 1))
    Put("mana", Pick(Read("UnitPowerMax", "player", 0), 1))          -- Enum.PowerType.Mana = 0
    local powerType = Read("UnitPowerType", "player")
    Put("powerType", Pick(powerType, 1))
    if stats.powerType then Put("power", Pick(Read("UnitPowerMax", "player", stats.powerType), 1)) end
    Put("powerRegen", Pick(Read("GetPowerRegen"), 1))                   -- wie Blizzards Charakterfenster (Energie je Sekunde)
    Put("armor", Pick(Read("UnitArmor", "player"), 2))
    for key, fn in pairs({ ap = "UnitAttackPower", rap = "UnitRangedAttackPower" }) do
        local values = Read(fn, "player")
        local base, sBase = Pick(values, 1)
        local pos, sPos = Pick(values, 2)
        local neg, sNeg = Pick(values, 3)
        if sBase or sPos or sNeg then secret = secret + 1
        elseif base then
            stats[key] = base + (pos or 0) + (neg or 0)
            Bonus(pos, neg)
        end
    end
    Put("meleeCrit", Pick(Read("GetCritChance"), 1))
    Put("rangedCrit", Pick(Read("GetRangedCritChance"), 1))
    Put("dodge", Pick(Read("GetDodgeChance"), 1))
    Put("parry", Pick(Read("GetParryChance"), 1))
    Put("block", Pick(Read("GetBlockChance"), 1))
    Put("hit", Pick(Read("GetHitModifier"), 1))
    Put("spellHit", Pick(Read("GetSpellHitModifier"), 1))
    Put("healing", Pick(Read("GetSpellBonusHealing"), 1))
    for key, fn in pairs({ spellCrit = "GetSpellCritChance", spellPower = "GetSpellBonusDamage" }) do
        for _, school in ipairs(Measure.SCHOOLS) do
            local v, s = Pick(Read(fn, school), 1)
            if s then secret = secret + 1
            elseif v and (stats[key] == nil or v < stats[key]) then stats[key] = v end
        end
    end
    local regen = Read("GetManaRegen")
    Put("regen", Pick(regen, 1))
    Put("regenCasting", Pick(regen, 2))
    Put("meleeSpeed", Pick(Read("UnitAttackSpeed", "player"), 1))
    local damage = Read("UnitDamage", "player")
    Put("dmgMin", Pick(damage, 1))
    Put("dmgMax", Pick(damage, 2))
    local items = 0
    for slot = 1, Measure.SLOTS do
        if not Measure.NO_STATS[slot] then
            local id = Core.Call(rawget(_G, "GetInventoryItemID"), "player", slot)
            if Core.IsSecret(id) or id ~= nil then items = items + 1 end
        end
    end
    return stats, items, secret, buffed
end

-- Text eines Rangs für die Messung: ohne Farbcodes, Links und Zeilenumbrüche, nicht gekürzt (die Zahlen jedes Satzes
-- zählen). Feld-Trenner „;“ wird zum Leerzeichen.
local function RankText(configID, entryID, rank)
    local entry = Traits.Entry(configID, entryID, rank)
    local text = type(entry) == "table" and type(entry.text) == "string" and entry.text or ""
    return (Core.Trim(Core.PlainText(text):gsub("[;\r\n]", " "):gsub("%s+", " ")) or "")
end

-- Schwelle eines Knotens (höchste geforderte Punktzahl im Baum aus seinen einschränkenden Bedingungen) oder 0.
local function Threshold(configID, node)
    local need = 0
    for _, condID in ipairs(node.conditions or {}) do
        local cond = Traits.Condition(configID, condID)
        if Traits.Restricts(cond) and cond.spent and cond.spent > need then need = cond.spent end
    end
    return need
end

-- Je Eintrag jedes Knotens aller Talentbäume der Klasse: Lage, Höchstrang, Zauber-ID, Schwelle, Vorgänger, Name und
-- die Texte aller Ränge (verdichtet) und die Kennzeichen wie in der Erhebung (aside, double, hidden).
-- → { { tree, row, col, max, spell, need, prereqs, name, template, ranks, texts, node, aside, double, hidden } … }
--   ranks: { { Zahl … } je Rang } oder nil, wenn die Texte der Ränge nicht nur in den Zahlen abweichen (dann texts)
function Measure.Talents(configID, treeID, locale)
    configID = configID or Traits.ClassConfigID()
    treeID = treeID or Traits.TreeOfConfig(configID)
    local rows = {}
    if not (configID and treeID) then return rows end
    locale = locale or Core.Call(rawget(_G, "GetLocale")) or "enUS"
    local nodes = Traits.Nodes(configID, treeID)
    local layout = Traits.Layout(configID, treeID, nodes, Traits.Groups(configID, treeID))
    local incoming = Traits.Incoming(nodes)
    for _, node in ipairs(nodes) do
        local where = layout[node.id] or {}
        local prereqs = {}
        for _, e in ipairs(incoming[node.id] or {}) do
            local from = layout[e.from]
            if from and (e.kind == Traits.EDGE.required or e.kind == Traits.EDGE.sufficient) then
                prereqs[#prereqs + 1] = (e.kind == Traits.EDGE.sufficient and "~" or "") .. from.row .. ":" .. from.col
            end
        end
        table.sort(prereqs)
        local need = Threshold(configID, node)
        for _, entryID in ipairs(node.entries) do
            local texts, template, ranks, same = {}, nil, {}, true
            for rank = 1, math.max(node.max or 1, 1) do
                texts[rank] = RankText(configID, entryID, rank)
                local t, nums = Measure.Template(texts[rank], locale)
                if rank == 1 then template = t elseif t ~= template then same = false end
                ranks[rank] = nums
            end
            rows[#rows + 1] = { tree = where.tree or 0, row = where.row or 0, col = where.col or 0, max = node.max or 1,
                spell = Traits.EntrySpell(configID, entryID) or 0, need = need, prereqs = prereqs,
                name = Traits.EntryName(configID, entryID) or "", template = template or "",
                ranks = same and ranks or nil, texts = texts, node = node.id, aside = where.aside == true,
                hidden = node.visible == false }
        end
    end
    ns.Templates.MarkDoubles(rows)
    table.sort(rows, function(a, b)
        if a.tree ~= b.tree then return a.tree < b.tree end
        if a.row ~= b.row then return a.row < b.row end
        if a.col ~= b.col then return a.col < b.col end
        return a.spell < b.spell
    end)
    return rows
end

-- Feld einer Zeile: ezCores Feldhelfer (Welle 23a, A16 – vorher hier und in ezCombat je eine eigene Fassung; neu: ein
-- gesperrter Wert wird zum leeren Feld statt verglichen zu werden, Leitlinie 6)
local Field = Core.MeasureField

-- Zahlen je Rang als „1 6/2 12/3 18“.
function Measure.RankField(ranks)
    local parts = {}
    for i, nums in ipairs(ranks or {}) do
        local list = {}
        for j, v in ipairs(nums) do list[j] = Measure.Format(v) end
        parts[i] = table.concat(list, " ")
    end
    return table.concat(parts, "/")
end

-- Der ganze Text zum Kopieren. → Text, Zahl der Talentzeilen, Grundwerte, Zahl angelegter Gegenstände, Zahl geheimer
-- Werte, Zahl der Werte mit Bonus; nil, wenn der Client weder Werte noch Talente liefert
function Measure.Text(configID, treeID)
    local class = Core.PlayerClass() or "?"
    local _, race = Core.Call(rawget(_G, "UnitRace"), "player")
    race = Core.Plain(race)
    local locale = Core.Call(rawget(_G, "GetLocale")) or "?"
    local stats, items, secret, buffed = Measure.Stats()
    local rows = Measure.Talents(configID, treeID, locale)
    if not stats.level and #rows == 0 then return nil end
    local version, build = Core.Call(rawget(_G, "GetBuildInfo"))
    local stamp = tostring(Core.Plain(version) or "?") .. "." .. tostring(Core.Plain(build) or "?")
    local lines = { table.concat({ Measure.HEAD, Measure.VERSION, class, Field(race or "?"), Measure.Format(stats.level),
        Field(locale), Field(stamp), date and date("%Y-%m-%d") or "?", items }, ";") }
    local keys = {}
    for key in pairs(stats) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do lines[#lines + 1] = "wert;" .. key .. ";" .. Measure.Format(stats[key]) end
    for _, r in ipairs(rows) do
        lines[#lines + 1] = table.concat({ "talent", r.tree, r.row, r.col, r.max, r.spell, r.need,
            table.concat(r.prereqs, ","), Field(r.name), Field(r.template), r.ranks and Measure.RankField(r.ranks) or "",
            ns.Templates.SurveyFlags(r) }, ";")
        if not r.ranks then
            for rank, text in ipairs(r.texts) do
                lines[#lines + 1] = table.concat({ "rangtext", r.tree, r.row, r.col, r.spell, rank, Field(text) }, ";")
            end
        end
    end
    return table.concat(lines, "\n"), #rows, stats, items, secret, buffed
end

-- Wie „unsauber“ eine Messung für die Grundwerte ist: angelegte Gegenstände wiegen am schwersten, dann geheime Werte,
-- dann Werte mit Bonus (Stärkungszauber). 0 = nackt, ohne Bonus, alles lesbar. Ältere Einträge ohne secret/buffed
-- zählen dort mit 0.
function Measure.Badness(items, secret, buffed)
    return ((tonumber(items) or 0) > 0 and 4 or 0) + ((tonumber(secret) or 0) > 0 and 2 or 0)
        + ((tonumber(buffed) or 0) > 0 and 1 or 0)
end

-- Grundwerte merken (je Klasse, Volk und Stufe; ohne Charakternamen), damit sie auch später weitergegeben werden können.
-- Eine Messung ersetzt einen gemerkten Eintrag nur, wenn sie nicht unsauberer ist (Measure.Badness; T7-NT7,
-- Gesamtreview 18.11.2026: vorher überschrieb eine Messung mit Ausrüstung die nackte). → Schlüssel, gemerkt? (false:
-- der alte, sauberere Eintrag blieb) bzw. nil
function Measure.Remember(stats, items, secret, buffed)
    if not (ns.db and type(stats) == "table" and stats.level) then return nil end
    ns.db.measure = type(ns.db.measure) == "table" and ns.db.measure or {}
    local _, race = Core.Call(rawget(_G, "UnitRace"), "player")
    race = Core.Plain(race)
    local key = table.concat({ Core.PlayerClass() or "?", type(race) == "string" and race or "?", Measure.Format(stats.level) }, ":")
    local old = ns.db.measure[key]
    if type(old) == "table" and type(old.stats) == "table"
        and Measure.Badness(items, secret, buffed) > Measure.Badness(old.items, old.secret, old.buffed) then
        return key, false
    end
    local version, build = Core.Call(rawget(_G, "GetBuildInfo"))
    local locale = Core.Plain(Core.Call(rawget(_G, "GetLocale")))
    local copy = {}
    for k, v in pairs(stats) do copy[k] = v end
    ns.db.measure[key] = { date = date and date("%Y-%m-%d") or "?", items = items or 0, secret = secret or 0,
        buffed = buffed or 0, stats = copy, locale = type(locale) == "string" and locale or nil,
        build = tostring(Core.Plain(version) or "?") .. "." .. tostring(Core.Plain(build) or "?") }
    return key, true
end

-- Gemerkte Grundwerte als Text (Form wie Measure.Text, ohne Talentzeilen; je Eintrag eine Kopfzeile, Einträge durch
-- eine Leerzeile getrennt). Jeder Block ist eine eigene Messung – die Werkzeuge lesen eine je Datei (MEASURE_SAVED_HINT
-- sagt es; tools/talent_sim.lua bricht an einer zweiten Kopfzeile ab). Reihenfolge: Klasse, Volk, Stufe als Zahl
-- (Gegenprüfung zu T7-NT7: als Text stand Stufe 10 vor Stufe 9). → Text, Zahl der Einträge; nil, 0 ohne Einträge
function Measure.SavedText()
    local list = ns.db and type(ns.db.measure) == "table" and ns.db.measure or {}
    local keys = {}
    for key, rec in pairs(list) do
        if type(key) == "string" and type(rec) == "table" and type(rec.stats) == "table" then keys[#keys + 1] = key end
    end
    if #keys == 0 then return nil, 0 end
    local function Parts(key)
        local class, race, level = key:match("^([^:]*):([^:]*):([^:]*)$")
        return class or key, race or "", tonumber(level) or math.huge, level or ""
    end
    table.sort(keys, function(a, b)
        local ca, ra, la, ta = Parts(a)
        local cb, rb, lb, tb = Parts(b)
        if ca ~= cb then return ca < cb end
        if ra ~= rb then return ra < rb end
        if la ~= lb then return la < lb end
        if ta ~= tb then return ta < tb end
        return a < b
    end)
    local blocks = {}
    for _, key in ipairs(keys) do
        local rec = list[key]
        local class, race, level = key:match("^([^:]*):([^:]*):([^:]*)$")
        local lines = { table.concat({ Measure.HEAD, Measure.VERSION, Field(class or "?"), Field(race or "?"),
            Field(level or "?"), Field(rec.locale or "?"), Field(rec.build or "?"), Field(rec.date or "?"),
            tonumber(rec.items) or 0 }, ";") }
        local names = {}
        for name, value in pairs(rec.stats) do
            if type(name) == "string" and type(value) == "number" then names[#names + 1] = name end
        end
        table.sort(names)
        for _, name in ipairs(names) do lines[#lines + 1] = "wert;" .. Field(name) .. ";" .. Measure.Format(rec.stats[name]) end
        blocks[#blocks + 1] = table.concat(lines, "\n")
    end
    return table.concat(blocks, "\n\n"), #keys
end

-- Sichtbarer Weg zu den gemerkten Grundwerten (T7-NT7): Knopf „Gemerkte Grundwerte zeigen“ unter „Erweitert“.
function Measure.ShowSaved()
    local text, count = Measure.SavedText()
    return Core.Measure.Show({ text = text, print = ns.Print, emptyText = L.MEASURE_SAVED_NONE,
        title = text and L.MEASURE_SAVED_TITLE:format(count) or nil,
        hint = L.MEASURE_SAVED_HINT .. "\n" .. Measure.SendLine(), owner = ADDON })
end

-- Hinweise zur Messung: nicht Stufe 60, nicht nackt, geheime Werte, Werte mit Bonus, keine Talente gelesen (count = 0;
-- nil heißt: nicht bekannt). → { Text … }
-- Welle 23 (Frage des Nutzers vom 16.11.2026, ob Stufe 1 oder 20 reicht): Die Messung gilt auf jeder Stufe – unter
-- Stufe 60 ein Hinweis statt einer Warnung („hilft trotzdem, je mehr Stufen, desto genauer“), unter Stufe 10 fehlen die
-- Talente (es gibt noch keine) ohne die Bitte, das Talentfenster zu öffnen.
function Measure.Warnings(stats, items, secret, count, buffed)
    local out = {}
    local level = stats.level
    if count == 0 then
        if level and level < Measure.TALENT_LEVEL then
            out[#out + 1] = L.MEASURE_NO_TALENTS_LOW:format(Measure.TALENT_LEVEL)
        else
            out[#out + 1] = L.MEASURE_NO_TALENTS
        end
    end
    if level and level ~= Measure.MAX_LEVEL then out[#out + 1] = L.MEASURE_LEVEL:format(level) end
    if (items or 0) > 0 then out[#out + 1] = L.MEASURE_GEAR:format(items) end
    if (secret or 0) > 0 then out[#out + 1] = L.MEASURE_SECRET:format(secret) end
    if (buffed or 0) > 0 and (items or 0) == 0 then out[#out + 1] = L.MEASURE_BUFF:format(buffed) end
    return out
end

-- Wohin mit dem Text (Wunsch des Nutzers vom 16.11.2026: Helfer sollen ohne Anleitung wissen, was zu tun ist): eine
-- Zeile „Als GitHub-Issue mit der Vorlage „Werte messen“ schicken“ – mit der Adresse der Vorlage „Werte messen“ aus ezCore
-- (Core.Contribute.VALUES_URL; bis zum Gesamtreview 18.11.2026, T11-1, die allgemeine Vorlage beitrag.yml), ohne
-- sie trotzdem der Weg (Leitlinie 11: nie ein Text ohne Erklärung).
function Measure.SendLine()
    local url = Core.Contribute and Core.Contribute.VALUES_URL
    if type(url) == "string" and url ~= "" then return L.MEASURE_SEND:format(url) end
    return L.MEASURE_SEND_PLAIN
end

-- Titel des Fensters: Stufe, Klasse und Volk (die Messung gilt auf jeder Stufe) und die Zahl der Talentzeilen.
function Measure.Title(stats, count)
    local class = Core.PlayerClass()
    local className = class and Core.ClassName(class) or class or "?"
    local race = Core.Plain((Core.Call(rawget(_G, "UnitRace"), "player")))
    local level = type(stats) == "table" and stats.level
    return L.MEASURE_TITLE:format(level or 0, tostring(className), type(race) == "string" and race or "?", count or 0)
end

-- Sichtbarer Weg: Knopf „Werte für die Simulation messen“ auf der Einstellungsseite (Erweitert); /ezt werte zusätzlich.
-- Der Ablauf (leer? Hinweise, Textfenster bzw. Chat) ist ezCores gemeinsamer für alle Messungen (Core.Measure.Show,
-- Welle 23a A16); die Zeile „wohin damit“ steht direkt unter der Erklärung, darunter die Hinweise zur Messung.
-- Im Kampf wird nicht gemessen (T7-NT8, wie ezCombats /ezk werte): Kampf-Stärkungszauber und geheime Werte verfälschen
-- die Grundwerte – geprüft vor dem Lesen, damit nichts gemerkt wird; ezCores Kampfsperre (combatText) zusätzlich.
function Measure.Show()
    if ns.InCombat() == true then
        Core.CombatNotice(ns, L.MEASURE_COMBAT_WHAT)   -- ezCores Satz zur Kampfsperre (T18-1)
        return false
    end
    local text, count, stats, items, secret, buffed = Measure.Text()
    local warnings
    if text then
        warnings = Measure.Warnings(stats, items, secret, count, buffed)
        local _, saved = Measure.Remember(stats, items, secret, buffed)
        if saved == false then warnings[#warnings + 1] = L.MEASURE_KEPT:format(stats.level) end
    end
    return Core.Measure.Show({ text = text, print = ns.Print, emptyText = L.MEASURE_NONE, combatText = ns.CombatText(L.MEASURE_COMBAT_WHAT),
        title = text and Measure.Title(stats, count) or nil,
        hint = L.MEASURE_HINT .. "\n" .. Measure.SendLine(),
        warnings = warnings, owner = ADDON })
end

