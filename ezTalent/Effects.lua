local ADDON, ns = ...
local Core = ezCore
local L = ns.L
local Traits = ns.Traits

--[[
    Auswirkungen der gewählten Talente bzw. Vermächtnis-Vorteile (Punkt 8, Wunsch des Nutzers).

    Alles kommt aus dem Client: Name und Text des aktuellen Rangs über Traits.Entry (C_Traits.GetTraitDescription bzw.
    die Beschreibung des Zaubers). ezTalent erfindet keine Texte; die Werte oben im Seitenteil (Krit., Ausdauer …)
    zählt es nur aus diesen Texten zusammen (Abschnitt „Werte“ unten, Wunsch des Nutzers vom 19.11.2026).

    Gliederung nach dem veränderten Zauber:
      1. Der Eintrag ersetzt einen Zauber (Definition overriddenSpellID) → dieser Zauber
      2. Der Text nennt einen Zauber aus dem eigenen Zauberbuch (längster Name zuerst, nie der eigene Name des Talents)
      3. sonst „Allgemein“
    In der Vorschau (gestaffelte Änderungen) bekommt jede Zeile ihren Zustand: neu, entfällt, Rang geändert
    („vorher → nachher“, beide Texte aus dem Client) – bestätigter Rang gegen den Rang der Vorschau.
    Schwellen und Stufe (TL-09): Nennt der Client Bedingungen eines Knotens (Traits.Needs), steht je Bedingung eine
    Zeile „Voraussetzung: … – erfüllt | fehlt noch“ darunter (z. B. die Schwellen der Vermächtnis-Vorteile).

    Zeile „verändert durch: …“ im Zauber-Tooltip: über ezCores Tooltip-Pipeline für Zauber (Core.Tooltip.AddSpellSection,
    seit ezCore 1.12, Welle 6; TL-21). Angemeldet wird einmal beim Laden unter dem Schlüssel „ezTalent.modifiers“ –
    ezCore ersetzt einen gleichnamigen Abschnitt, die Zeile steht also auch nach /reload nur einmal. Fehlt der Dienst
    (älteres ezCore), bleibt die Zeile aus und /ezt status sagt es.
]]

local Effects = {}
ns.Effects = Effects

---------------------------------------------------------------------------
-- Zaubernamen aus dem eigenen Zauberbuch (ezCore.Spells), längste zuerst
---------------------------------------------------------------------------

local knownNames

function Effects.KnownNames()
    if knownNames then return knownNames end
    local names = {}
    local spells = Core.Spells
    if spells and spells.ForEachKnown then
        pcall(spells.ForEachKnown, function(entry)
            if type(entry) == "table" and type(entry.name) == "string" then names[#names + 1] = entry.name end
        end)
    end
    table.sort(names, function(a, b)
        if #a ~= #b then return #a > #b end
        return a < b
    end)
    knownNames = names
    return names
end

function Effects.ForgetNames() knownNames = nil end

-- Welchen Zauber verändert der Text? names: Liste, längste zuerst. → Name oder nil
function Effects.TargetOf(text, ownName, names)
    if type(text) ~= "string" or text == "" then return nil end
    for _, name in ipairs(names or {}) do
        if name ~= ownName and #name >= 3 and text:find(name, 1, true) then return name end
    end
    return nil
end

local function Target(entry, names)
    if entry.overridden then
        local name = Core.SpellName(entry.overridden)
        if name then return name end
    end
    return Effects.TargetOf(entry.text, entry.name, names)
end

---------------------------------------------------------------------------
-- Einträge sammeln
---------------------------------------------------------------------------

-- Gewählte Knoten einer Konfiguration: { { nodeID, name, icon, rank, before, max, text, textBefore, target, state,
--   needs = { { text, met } } (Schwellen und Stufe laut Client, sonst nil) } }
-- state: "same" | "new" (nur in der Vorschau) | "removed" (bestätigt, in der Vorschau weg) | "changed" (Rang anders)
function Effects.Collect(configID, treeID)
    local items, names = {}, Effects.KnownNames()
    for _, node in ipairs(Traits.Nodes(configID, treeID)) do
        local now, before = node.current or 0, node.active or 0
        if (now > 0 or before > 0) and node.entry then
            local entry = Traits.Entry(configID, node.entry, now > 0 and now or before)
            if entry then
                local item = { nodeID = node.id, name = entry.name or ("#" .. node.id), icon = entry.icon,
                    rank = now, before = before, max = node.max, text = entry.text, spellID = entry.spellID }
                if now == before then
                    item.state = "same"
                elseif before == 0 then
                    item.state = "new"
                elseif now == 0 then
                    item.state = "removed"
                else
                    item.state = "changed"
                    local old = Traits.Entry(configID, node.entry, before)
                    item.textBefore = old and old.text or nil
                end
                item.target = Target(entry, names)
                item.needs = Traits.Needs(configID, treeID, node)     -- Schwellen, Stufe (TL-09); leer ohne Angaben
                if #item.needs == 0 then item.needs = nil end
                items[#items + 1] = item
            end
        end
    end
    return items
end

-- Nach Ziel gegliedert: { { target = Name | nil (Allgemein), title, items } }, Zauber alphabetisch, „Allgemein“ zuletzt.
function Effects.Grouped(items)
    local byTarget, list, general = {}, {}, nil
    for _, item in ipairs(items or {}) do
        local key = item.target
        if key then
            if not byTarget[key] then
                byTarget[key] = { target = key, title = key, items = {} }
                list[#list + 1] = byTarget[key]
            end
            table.insert(byTarget[key].items, item)
        else
            general = general or { target = nil, title = L.EFFECTS_GENERAL, items = {} }
            table.insert(general.items, item)
        end
    end
    table.sort(list, function(a, b) return a.title:lower() < b.title:lower() end)
    if general then list[#list + 1] = general end
    for _, group in ipairs(list) do
        table.sort(group.items, function(a, b) return a.name:lower() < b.name:lower() end)
    end
    return list
end

-- Zahl der Änderungen in der Vorschau: neu, entfällt, geändert.
function Effects.Changes(items)
    local new, removed, changed = 0, 0, 0
    for _, item in ipairs(items or {}) do
        if item.state == "new" then new = new + 1
        elseif item.state == "removed" then removed = removed + 1
        elseif item.state == "changed" then changed = changed + 1 end
    end
    return new, removed, changed
end

-- Rang als Text: „2/3“, in der Vorschau „1 → 2/3“.
function Effects.RankText(item)
    if item.state == "changed" or item.state == "new" or item.state == "removed" then
        return L.EFFECTS_RANK_CHANGE:format(item.before or 0, item.rank or 0, item.max or 1)
    end
    return L.EFFECTS_RANK:format(item.rank or 0, item.max or 1)
end

---------------------------------------------------------------------------
-- „verändert durch“: Zauber → Talente (aus der Klassen-Konfiguration, bestätigt und Vorschau)
---------------------------------------------------------------------------

local index, dirty = {}, true

function Effects.MarkDirty()
    dirty = true
end

function Effects.BuildIndex()
    index = {}
    local configID = Traits.ClassConfigID()
    local treeID = Traits.TreeOfConfig(configID)
    if configID and treeID then
        for _, item in ipairs(Effects.Collect(configID, treeID)) do
            if item.target and item.rank > 0 then
                index[item.target] = index[item.target] or {}
                table.insert(index[item.target], item)
            end
        end
    end
    dirty = false
    return index
end

-- Talente, die einen Zauber verändern: Liste der Einträge (Name, Rang …), leer wenn keine.
function Effects.ModifiersOf(spell)
    local name = type(spell) == "number" and Core.SpellName(spell) or spell
    if type(name) ~= "string" then return {} end
    if dirty then Effects.BuildIndex() end
    return index[name] or {}
end

-- Text der Tooltip-Zeile oder nil.
function Effects.TooltipText(spell)
    local list = Effects.ModifiersOf(spell)
    if #list == 0 then return nil end
    local parts = {}
    for i, item in ipairs(list) do parts[i] = item.name .. " (" .. L.EFFECTS_RANK:format(item.rank, item.max) .. ")" end
    return L.EFFECTS_TOOLTIP:format(table.concat(parts, ", "))
end

local tooltipRegistered = false

function Effects.TooltipReady() return tooltipRegistered end

-- Anmeldung an ezCores Zauber-Tooltip (defensiv: fehlt der Dienst, bleibt die Zeile aus).
function Effects.RegisterTooltip()
    if tooltipRegistered then return true end
    local tooltip = Core.Tooltip
    if not (tooltip and type(tooltip.AddSpellSection) == "function") then return false end
    local ok = pcall(tooltip.AddSpellSection, "ezTalent.modifiers", 60, function(tip, spellID)
        -- fest an (Einstellungs-Prüfung 19.11.2026, Nr. 40): reine Hilfe, kein Schalter mehr
        if Core.IsSecret(spellID) then return end
        local text = Effects.TooltipText(spellID)
        if not (text and tip and tip.AddLine) then return end
        -- ezCores einer Trenner (S-1811-Tooltipabstand, Spielbefund 18.11.2026): Leerzeile vor der Zeile, nie zwei
        if type(tooltip.Gap) == "function" then tooltip.Gap(tip) end
        Core.TipLine(tip, text, "blue", true)   -- Rolle statt Farbzahlen (T9-6)
    end, ADDON)
    tooltipRegistered = ok
    return ok
end

ns.OnReady(function()
    Effects.RegisterTooltip()
    for _, event in ipairs({ "TRAIT_CONFIG_UPDATED", "TRAIT_NODE_CHANGED", "TRAIT_TREE_CHANGED",
        "ACTIVE_COMBAT_CONFIG_CHANGED", "PLAYER_TALENT_UPDATE" }) do
        ns.On(event, Effects.MarkDirty)
    end
    ns.On("SPELLS_CHANGED", function()
        Effects.ForgetNames()
        Effects.MarkDirty()
    end)
end)

---------------------------------------------------------------------------
-- Werte (Wunsch des Nutzers vom 19.11.2026: „bei talente auswirkungen, soll das die auswirkungen auf die stats zeigen
-- und am besten möglich sein vorlagen damit zu vergleichen“)
---------------------------------------------------------------------------

--[[
    Quelle (Leitlinie 11): der Text des aktuellen Rangs, den der Client liefert (Traits.Entry: C_Traits.GetTraitDescription
    bzw. die Beschreibung des Zaubers) – derselbe Text, den Blizzards Talent-Tooltip zeigt. Ein Addon kann die Wirkungen
    eines Talents nicht als Zahlen abfragen; ezTalent liest deshalb nur Sätze der Form „Erhöht … um 3 %“ bzw.
    „Increases … by 3%“ und ordnet das Stichwort einem Wert zu (Effects.STATS, je Sprache des Clients). Ausgelassen wird:
      * ein Talent, das einen bestimmten Zauber verändert (item.target – der gehört unter dessen Überschrift unten),
      * ein Satz mit Bedingung oder anderem Bezug (Kosten, Abklingzeit, Dauer, Bedrohung, „nachdem“, „wenn“ …),
      * ein Satz ohne Zahl hinter „um“ bzw. „by“.
    Gleiche Werte gleicher Einheit werden zusammengezählt (Ränge stecken schon im Text des Rangs). Erkannt heißt nicht
    geprüft: Die Anzeige sagt, wie viele Talente erkannt wurden, und alle Texte stehen weiter darunter.
]]

-- Werte in der Reihenfolge der Anzeige; words: alle Stichwörter müssen im Satz stehen (klein geschrieben), die
-- genaueren zuerst (Zauber-Krit. vor Krit.).
Effects.STATS = {
    { key = "spellCrit", de = { { "kritisch", "zauber" } }, en = { { "critical", "spell" } } },
    { key = "crit", de = { { "kritisch" } }, en = { { "critical" } } },
    { key = "spellHit", de = { { "treff", "zauber" } }, en = { { "hit", "spell" } } },
    { key = "hit", de = { { "trefferchance" }, { "zu treffen" } }, en = { { "chance to hit" }, { "hit chance" } } },
    { key = "dodge", de = { { "ausweich" } }, en = { { "dodge" } } },
    { key = "parry", de = { { "parier" } }, en = { { "parry" } } },
    { key = "block", de = { { "block" } }, en = { { "block" } } },
    { key = "attackPower", de = { { "angriffskraft" } }, en = { { "attack power" } } },
    { key = "spellDamage", de = { { "zauberschaden" }, { "schaden", "zauber" } }, en = { { "spell damage" }, { "damage", "spell" } } },
    { key = "healing", de = { { "heilung" }, { "heilzauber" } }, en = { { "healing" } } },
    { key = "attackSpeed", de = { { "angriffsgeschwindigkeit" } }, en = { { "attack speed" } } },
    { key = "stamina", de = { { "ausdauer" } }, en = { { "stamina" } } },
    { key = "strength", de = { { "stärke" } }, en = { { "strength" } } },
    { key = "agility", de = { { "beweglichkeit" } }, en = { { "agility" } } },
    { key = "intellect", de = { { "intelligenz" } }, en = { { "intellect" } } },
    { key = "spirit", de = { { "willenskraft" } }, en = { { "spirit" } } },
    { key = "armor", de = { { "rüstung" } }, en = { { "armor" }, { "armour" } } },
    { key = "health", de = { { "gesundheit" } }, en = { { "health" } } },
    { key = "mana", de = { { "mana" } }, en = { { "mana" } } },
}

-- Satz zählt nur mit diesem Verb und ohne diese Wörter (Bedingungen, andere Bezüge).
Effects.STAT_VERB = { de = { "erhöht", "erhöhen" }, en = { "increase" } }
Effects.STAT_SKIP = {
    -- (jeder Satz beginnt und endet für diese Suche mit einem Leerzeichen: „ dauer“ trifft „die Dauer“, nicht
    -- „Ausdauer“; „ range “ trifft „range“, nicht „ranged“ – Fernkampf zählt in beiden Sprachen.)
    -- Beide Sprachen schließen dasselbe aus (Gegenprüfung 19.11.2026): Schaden kritischer Treffer (ist keine
    -- Trefferchance), Begleiter und Tiere, Bedingungen („während“, „in … gestalt“).
    de = { "kosten", "abklingzeit", " dauer", "bedrohung", "nachdem", " wenn ", "jedes mal", "chance bei", "widerst",
        "reichweite", "verringert", "verbündete", "gruppenmitglied", "begleiter", " tier", "tiere", "während",
        "gestalt", "schadensbonus", "kritischen schaden", "kritischer schaden", "schaden eurer kritisch",
        "schaden kritischer", "regenera" },
    en = { "cost", "cooldown", "duration", "threat", " after ", " when ", "each time", "chance on", "resist", " range ",
        "reduc", "allies", "party member", " pet", " while", " form ", " form,", "damage bonus",
        "critical strike damage", "critical damage", "damage of your critical", "damage done by critical", "regenera" },
}
-- Treffen mehrere Werte im selben Satz zusammen, gilt nur der gemeinte: „kritische Trefferchance“ ist Krit., nicht
-- Treffer; Zauber-Krit. ersetzt Krit. (Schlüssel: verdrängter Wert, Liste: Werte, die ihn verdrängen).
Effects.STAT_COVERED = {
    crit = { "spellCrit" },
    hit = { "spellHit", "crit", "spellCrit" },
    spellHit = { "crit", "spellCrit" },
}
-- Zahl hinter „um“ bzw. „by“, mit Prozent oder ohne
-- (die Dezimalstelle ist vorher zu „#“ geworden, siehe Effects.StatsFromText)
Effects.STAT_NUMBER = { de = "um (%d+#?%d*)(%s?%%?)", en = "by (%d+#?%d*)(%s?%%?)" }
-- Tausendertrenner je Sprache (de „1.000“, en „1,000“): genau drei Ziffern, danach keine weitere
Effects.STAT_THOUSANDS = { de = "(%d)%.(%d%d%d)%f[^%d]", en = "(%d),(%d%d%d)%f[^%d]" }

local function Lang() return Core.IsGerman() and "de" or "en" end

local function HasAll(sentence, words)
    for _, word in ipairs(words) do
        if not sentence:find(word, 1, true) then return false end
    end
    return true
end

local function HasAny(sentence, words)
    for _, word in ipairs(words or {}) do
        if sentence:find(word, 1, true) then return true end
    end
    return false
end

-- Werte aus einem Text: { { key, value, percent = true|nil } } (leer, wenn nichts erkannt). lang: "de" | "en"
-- (ohne Angabe die Sprache des Clients). Ein Satz mit mehreren Werten („Stärke, Beweglichkeit und Ausdauer um 2 %“)
-- liefert jeden davon – aber nur bei genau einer Zahl im Satz; sonst ist die Zuordnung unsicher und der Satz zählt nicht.
function Effects.StatsFromText(text, lang)
    local out = {}
    if Core.IsSecret(text) or type(text) ~= "string" or text == "" then return out end
    lang = lang or Lang()
    local verbs, skip, number = Effects.STAT_VERB[lang], Effects.STAT_SKIP[lang], Effects.STAT_NUMBER[lang]
    local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    -- Tausendertrenner weg („1.000.000“ braucht zwei Durchgänge) …
    local thousands = Effects.STAT_THOUSANDS[lang] or Effects.STAT_THOUSANDS.en
    for _ = 1, 4 do
        local changed
        plain, changed = plain:gsub(thousands, "%1%2")
        if changed == 0 then break end
    end
    -- … dann die Dezimalstelle zu „#“: Sätze werden an Punkt, Semikolon und Zeilenumbruch getrennt, ohne eine Zahl
    -- zu zerreißen
    plain = plain:gsub("(%d)[%.,](%d)", "%1#%2")
    for sentence in (plain .. "."):gmatch("([^%.;\n]+)") do
        local low = " " .. sentence:lower() .. " "
        if HasAny(low, verbs) and not HasAny(low, skip) then
            local found, hit = {}, {}
            for _, def in ipairs(Effects.STATS) do
                for _, words in ipairs(def[lang] or {}) do
                    if HasAll(low, words) then
                        found[#found + 1] = def.key
                        hit[def.key] = true
                        break
                    end
                end
            end
            local keys = {}
            for _, key in ipairs(found) do
                local covered = false
                for _, by in ipairs(Effects.STAT_COVERED[key] or {}) do
                    if hit[by] then covered = true break end
                end
                if not covered then keys[#keys + 1] = key end
            end
            local numbers = 0
            for _ in low:gmatch("%d+#?%d*") do numbers = numbers + 1 end
            local digits, unit = low:match(number)
            if #keys > 0 and digits and (#keys == 1 or numbers == 1) then
                local value = tonumber((digits:gsub("#", ".")))
                if value and value > 0 then
                    local percent = unit:find("%", 1, true) ~= nil or nil
                    for _, key in ipairs(keys) do
                        out[#out + 1] = { key = key, value = value, percent = percent }
                    end
                end
            end
        end
    end
    return out
end

-- Werte einer Liste von Einträgen (Effects.Collect bzw. Effects.PlanItems) zusammengezählt.
-- → { [key .. "%"/""] = { key, value, percent } }, Zahl der Talente mit erkanntem Wert, Zahl der Talente ohne Zauberbezug
function Effects.StatTotals(items, lang)
    local totals, recognised, general = {}, 0, 0
    for _, item in ipairs(items or {}) do
        if (item.rank or 0) > 0 and item.state ~= "removed" and not item.target then
            general = general + 1
            local stats = Effects.StatsFromText(item.text, lang)
            if #stats > 0 then recognised = recognised + 1 end
            for _, stat in ipairs(stats) do
                local id = stat.key .. (stat.percent and "%" or "")
                local sum = totals[id] or { key = stat.key, value = 0, percent = stat.percent }
                sum.value = sum.value + stat.value
                totals[id] = sum
            end
        end
    end
    return totals, recognised, general
end

-- Einträge, wie sie ein Plan (Vorlage, Vorauswahl) setzen würde: Text des Rangs aus dem Client wie bei Collect.
function Effects.PlanItems(configID, treeID, plan)
    local items, names = {}, Effects.KnownNames()
    local nodes = type(plan) == "table" and type(plan.tpl) == "table" and plan.tpl.nodes
    if type(nodes) ~= "table" then return items end
    for _, node in ipairs(Traits.Nodes(configID, treeID)) do
        local rank = tonumber(nodes[node.id] or nodes[tostring(node.id)]) or 0
        local entryID = rank > 0 and ns.Plan and ns.Plan.EntryOf(plan, node) or nil
        local entry = entryID and Traits.Entry(configID, entryID, rank)
        if entry then
            local item = { nodeID = node.id, name = entry.name or ("#" .. node.id), rank = rank, max = node.max,
                text = entry.text, spellID = entry.spellID, state = "same" }
            item.target = Target(entry, names)
            items[#items + 1] = item
        end
    end
    return items
end

-- Werte in der Reihenfolge von Effects.STATS: { { key, percent, now, other, diff } } – other/diff nur mit Vergleich.
function Effects.CompareStats(now, other)
    local rows, seen = {}, {}
    local function Add(id, stat)
        if seen[id] then return end
        seen[id] = true
        local a = now and now[id] and now[id].value or 0
        local row = { key = stat.key, percent = stat.percent, now = a }
        if other then
            row.other = other[id] and other[id].value or 0
            -- auf 0,01 gerundet (code-reviewer 20.11.2026: 0,2 + 0,1 gegen 0,3 ergab sonst „+0,0 %“ statt „gleich“)
            local diff = row.other - a
            diff = math.floor(diff * 100 + 0.5) / 100
            if math.abs(diff) < 0.005 then diff = 0 end
            row.diff = diff
        end
        rows[#rows + 1] = row
    end
    for _, def in ipairs(Effects.STATS) do
        for _, suffix in ipairs({ "%", "" }) do
            local id = def.key .. suffix
            local stat = (now and now[id]) or (other and other[id])
            if stat then Add(id, stat) end
        end
    end
    return rows
end

-- Zahl als „+3 %“ bzw. „+12“ (eine Nachkommastelle nur, wenn nötig; Komma im deutschen Client).
function Effects.StatValue(value, percent, signed)
    value = tonumber(value) or 0
    local text = (value % 1 == 0) and tostring(math.floor(value)) or string.format("%.1f", value)
    if Core.IsGerman() then text = text:gsub("%.", ",") end
    if signed ~= false and value > 0 then text = "+" .. text end
    if percent then text = text .. (Core.IsGerman() and " %" or "%") end
    return text
end

-- Schnittstelle für andere Module: Talente, die einen Zauber verändern ({ { name, rank, max, text } }).
function ns.API.ModifiersOf(spell)
    local out = {}
    for i, item in ipairs(Effects.ModifiersOf(spell)) do
        out[i] = { name = item.name, rank = item.rank, max = item.max, text = item.text }
    end
    return out
end
