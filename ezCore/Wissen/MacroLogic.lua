local _, ns = ...
local Core = ezCore

--[[
    Makro-Logik je Klasse (Klassen-Wissen für ezMacro, Kern-Teil von UE-26; Wunsch des Nutzers vom 13.11.2026: „die
    daten rotations recherche muss … auch nochmal für ezmacros … durchgeführt werden“). Hier stehen nur Zauber-IDs und
    die Logik in eigener Form – kein Makrotext, keine Namen (die liefert der Client), nichts aus einem Addon
    (Leitlinie 10). ezMacro baut daraus seine Vorlagen; Spells.MacroCondition übersetzt eine Bedingung in Blizzards
    Makro-Schreibweise.

    Quellen (abgerufen am 15.11.2026; Ideen, in eigenen Worten umgesetzt):
      - Makro-Seite des Forever-Guides von RankedBoost (rankedboost.com/world-of-warcraft/forever/macros/): je Klasse
        Ein-Klick-Ideen (Begleiter greift mit dem Zauber an, Aspekt mit Umschalttaste, Kanalzauber ohne Abbrechen,
        Unterbrechen je Haltung, Eröffnung aus der Verstohlenheit, Hilfe auf die Einheit unter der Maus).
      - ezMacros eigene Vorlagen (ezMacro/Data/Classes.lua, Herkunft MACRO-28: eigene Texte, IDs am 14.11.2026 gegen
        Wowheads Forever-Tooltip geprüft) – die Logik ist dieselbe, hier ohne Text als Daten.
      Zauber-IDs: klassische Rang-1-IDs aus Blizzards Client (Ersatznamen in SpellData.lua, /ez test prüft jede).

    Eintrag: { key, kind, unit, chain, pre, steps }
      kind   "oneKey"    ein Knopf, die Bedingung wählt den Zauber (Haltung, Gestalt, Umschalttaste, Begleiter)
             "opener"    Eröffnung: aus der Verstohlenheit bzw. vor dem Kampf ein anderer Zauber als danach
             "mouseover" wirkt auf die Einheit unter der Maus, sonst auf das Ziel bzw. dich
             "focus"     wirkt auf den Fokus, sonst die Maus, sonst das Ziel (Unterbrechen, Kontrolle)
      unit   "help" (Mitspieler), "harm" (Gegner), "exists" (beides), "dead" (tot, Wiederbeleben); nil = ohne Ziel
      chain  Reihenfolge der Ziele: "focus", "mouseover", "target", "player" (Standard je kind, siehe CHAINS)
             Steht die Maus auf einem Mitglied deiner Gruppe bzw. deines Schlachtzugs, wirkt ein Zauber auf Mitspieler
             (unit "help", "exists", "dead") auf genau dieses Mitglied oder gar nicht – nie rutscht er auf das Ziel
             durch (Spieltest des Nutzers vom 15.11.2026, siehe Spells.MACRO_GROUP_FIRST unten).
      pre    Zeilen davor als Schlüssel: "petattack", "startattack", "stopcasting", "trinkets" (Schmuckstücke 13/14)
      steps  { { spell = ID, when = { stance = n | form = n | noform = true | stealth = true | nostealth = true |
             combat = false | mod = "shift" | "ctrl" | "alt" | nochanneling = true | pet = false | petdead = true |
             orMod = "shift" }, notarget = true, keep = true } }
             – der erste Schritt, dessen Bedingung passt, wirkt; der letzte ohne when ist der Rest
             Seit Welle 23a (A57; Wünsche aus ezMacro „Klassen-Wissen, Rest“): notarget = der Schritt wirkt ohne
             Zielkette (Haltung, Gestalt, Verstohlenheit: „{s:71}“ statt „[@mouseover,harm,nodead][] {s:71}“);
             keep = „!“ vor dem Zauber (ein Aspekt schaltet sich nie aus); when.orMod = die Taste erzwingt den Schritt
             zusätzlich („[mod:shift][@pet,dead]“). Den Zauber-Teil der /cast-Zeile baut Spells.MacroCast(eintrag).
]]

local Spells = Core.Spells

Spells.MACRO_CHAINS = {
    mouseover = { "mouseover", "target", "player" },
    focus = { "focus", "mouseover", "target" },
}

Spells.MACRO_LOGIC = {
    WARRIOR = {
        { key = "charge", kind = "oneKey", steps = { { spell = 100, when = { stance = 1 } }, { spell = 20252, when = { stance = 3 } },
            { spell = 2457 } } },
        { key = "interrupt", kind = "focus", unit = "harm", steps = { { spell = 6552, when = { stance = 3 } }, { spell = 72 } } },
        { key = "taunt", kind = "mouseover", unit = "harm", chain = { "mouseover", "target" },
            steps = { { spell = 355, when = { stance = 2 } }, { spell = 71, notarget = true } } },
    },
    ROGUE = {
        { key = "opener", kind = "opener", steps = { { spell = 1784, when = { nostealth = true, combat = false } },
            { spell = 8676, when = { stealth = true, mod = "shift" } }, { spell = 1833, when = { stealth = true } }, { spell = 1752 } } },
        { key = "kick", kind = "focus", unit = "harm", chain = { "focus", "target" }, steps = { { spell = 1766 } } },
        { key = "sap", kind = "mouseover", unit = "harm", chain = { "mouseover", "target" },
            steps = { { spell = 1784, when = { nostealth = true }, notarget = true }, { spell = 6770 } } },
    },
    HUNTER = {
        { key = "petShot", kind = "oneKey", unit = "harm", chain = { "mouseover", "target" }, pre = { "petattack" },
            steps = { { spell = 3044 } } },
        { key = "aspects", kind = "oneKey", steps = { { spell = 5118, when = { mod = "shift" }, keep = true },
            { spell = 13163, when = { mod = "ctrl" }, keep = true }, { spell = 13165, keep = true } } },
        { key = "petCare", kind = "oneKey", steps = { { spell = 982, when = { petdead = true, orMod = "shift" } },
            { spell = 883, when = { pet = false } }, { spell = 136 } } },
        { key = "tranq", kind = "focus", unit = "harm", steps = { { spell = 19801 } } },
    },
    WARLOCK = {
        { key = "petBolt", kind = "oneKey", unit = "harm", chain = { "mouseover", "target" }, pre = { "petattack" },
            steps = { { spell = 686 } } },
        { key = "drain", kind = "oneKey", unit = "harm", chain = { "mouseover", "target" },
            steps = { { spell = 689, when = { nochanneling = true } } } },
        { key = "fear", kind = "focus", unit = "harm", steps = { { spell = 5782 } } },
    },
    PRIEST = {
        { key = "flash", kind = "mouseover", unit = "help", steps = { { spell = 2061 } } },
        { key = "shield", kind = "mouseover", unit = "help", steps = { { spell = 17 } } },
        { key = "dispel", kind = "mouseover", unit = "exists", steps = { { spell = 527 } } },
        { key = "res", kind = "mouseover", unit = "dead", chain = { "mouseover", "target" }, steps = { { spell = 2006 } } },
        { key = "shackle", kind = "focus", unit = "harm", steps = { { spell = 9484 } } },
    },
    DRUID = {
        { key = "innervate", kind = "mouseover", unit = "help", steps = { { spell = 29166 } } },
        { key = "rebirth", kind = "mouseover", unit = "dead", chain = { "mouseover", "target" }, steps = { { spell = 20484 } } },
        { key = "formHeal", kind = "oneKey", unit = "help", chain = { "mouseover", "target", "player" }, pre = { "cancelform" },
            steps = { { spell = 8936 } } },
        -- Shift: Vergiftung aufheben (2893, wie Spells.DISPELS.DRUID.poison), sonst Fluch aufheben (Welle 23a, A57).
        -- Die Teilung „im Kampf Wiedergeburt, sonst Wiederbeleben“ bei rebirth entfällt: 50769 gibt es auf Forever nicht.
        { key = "decurse", kind = "mouseover", unit = "help", steps = { { spell = 2893, when = { mod = "shift" } },
            { spell = 2782 } } },
    },
    SHAMAN = {
        { key = "interrupt", kind = "focus", unit = "harm", chain = { "focus", "target" }, pre = { "stopcasting" },
            steps = { { spell = 8042 } } },
        { key = "wave", kind = "mouseover", unit = "help", chain = { "mouseover", "target" },
            steps = { { spell = 331, when = { mod = "shift" } }, { spell = 8004 } } },
        { key = "purge", kind = "mouseover", unit = "harm", chain = { "mouseover", "target" }, steps = { { spell = 370 } } },
        { key = "wolf", kind = "oneKey", steps = { { spell = 2645, when = { noform = true } } } },
    },
    PALADIN = {
        { key = "heal", kind = "mouseover", unit = "help", chain = { "mouseover", "target" },
            steps = { { spell = 635, when = { mod = "shift" } }, { spell = 19750 } } },
        { key = "cleanse", kind = "mouseover", unit = "help", steps = { { spell = 4987 } } },
        { key = "hammer", kind = "focus", unit = "harm", steps = { { spell = 853 } } },
        { key = "layOnHands", kind = "mouseover", unit = "help", steps = { { spell = 633 } } },
    },
    MAGE = {
        { key = "counterspell", kind = "focus", unit = "harm", chain = { "focus", "target" }, pre = { "stopcasting" },
            steps = { { spell = 2139 } } },
        { key = "polymorph", kind = "focus", unit = "harm", steps = { { spell = 118 } } },
        { key = "decurse", kind = "mouseover", unit = "help", steps = { { spell = 475 } } },
    },
}

-- Makro-Logik einer Klasse (Standard: eigene) als Kopie; leere Liste für eine unbekannte Klasse.
function Spells.MacroLogic(class)
    class = class or Core.PlayerClass()
    local out = {}
    for i, entry in ipairs(Spells.MACRO_LOGIC[class or ""] or {}) do
        local copy = {}
        for k, v in pairs(entry) do copy[k] = v end
        out[i] = copy
    end
    return out
end

-- Alle Zauber-IDs der Makro-Logik (für den Selbsttest): { [ID] = true }.
function Spells.MacroSpells()
    local set = {}
    for _, list in pairs(Spells.MACRO_LOGIC) do
        for _, entry in ipairs(list) do
            for _, step in ipairs(entry.steps) do set[step.spell] = true end
        end
    end
    return set
end

local UNIT_WORD = { help = "help,nodead", harm = "harm,nodead", exists = "exists,nodead", dead = "help,dead" }

--[[
    Kein Durchrutschen auf das Ziel (Spieltest des Nutzers vom 15.11.2026, wörtlich: „wenn ich  einen aus der
    gruppeheilen oder buffen will der aber nicht in reichweite ist, ich aber noch focus auf jmd anderen habe, dann wird
    dieser geheilt“). Die Kette „[@mouseover,help,nodead][help,nodead][@player]“ springt zum nächsten Glied, sobald
    „help“ oder „nodead“ für die Einheit unter der Maus falsch ist – bei einem Mitspieler außer Sichtweite bzw. einem
    toten Mitspieler wirkte das Makro so auf das Ziel. Darum stehen vor dem Glied der Maus zwei Glieder, die nur fragen,
    ob die Einheit zur eigenen Gruppe bzw. zum Schlachtzug gehört: „[@mouseover,party][@mouseover,raid]“. Blizzards
    Makro-Bedingungen „party“ und „raid“ prüfen die Einheit hinter „@“ (warcraft.wiki.gg, „Macro conditionals“,
    abgerufen am 15.11.2026: „The unit exists and is in your party/raid (party excludes self)“; Forever nutzt die
    Retail-Engine, Blizzards UnitPlayerOrPetInParty/UnitPlayerOrPetInRaid stehen im Probe-Bericht 7,
    41-dokumentation-systeme.md). Trifft eines, wirkt der Zauber auf genau dieses Mitglied; ist es außer Reichweite
    oder tot, meldet Blizzard das selbst („Außer Reichweite“, „Ziel ist tot“). Ein fremder freundlicher Spieler, du
    selbst („party“ schließt dich aus) und ein leerer Mauszeiger laufen wie bisher durch die Kette.
    Nur für Zauber auf Mitspieler (help, exists, dead); bei „harm“ ist ein Mitglied der eigenen Gruppe nie ein Ziel,
    „harm“ hängt nicht an der Reichweite, die Kette bleibt dort, wie sie ist.
    Kurzform (opts.short, wenn Blizzards 255 Zeichen sonst nicht reichen, z. B. mehrere Umschalt-Schritte): ein Glied
    „[@mouseover,exists,noharm]“ statt der drei – jede vorhandene, nicht feindliche Einheit unter der Maus bekommt den
    Zauber oder Blizzards Meldung, auch ein Mitglied außer Sichtweite oder tot. Unterschied zur langen Form: Auch ein
    toter oder nicht unterstützbarer fremder Spieler unter der Maus fängt den Zauber ab (Meldung statt Ziel).
]]
Spells.MACRO_GROUP_FIRST = { "party", "raid" }
Spells.MACRO_GROUP_SHORT = "exists,noharm"
local GROUP_UNITS = { help = true, exists = true, dead = true }
-- Was hinter „@mouseover,“ ein Glied für Mitspieler ausmacht (für Spells.MacroGroupFirst auf fertigem Makrotext).
-- Das bloße „exists“ fehlt mit Absicht: „[@mouseover,exists]“ rutscht nie durch, party und raid wären nur länger.
local GROUP_WORDS = { ["help,nodead"] = true, ["exists,nodead"] = true, ["help,dead"] = true, help = true }
-- Zeilen, die Spells.MacroGroupFirst hebt: Zauber und Gegenstände. /focus, /assist, /follow, /tm und die übrigen
-- Befehle bleiben, wie sie sind (Gegenprüfung Welle 14: der Auftrag galt Heilen und Buffen, nicht dem Fokus).
local CAST_COMMANDS = { cast = true, spell = true, use = true, castsequence = true, castrandom = true, userandom = true }

-- Glieder „Mitglied unter der Maus“ mit den Teilen davor (prefix: "" oder z. B. "mod:shift,") → "[…@mouseover,party][…]"
local function GroupLinks(prefix)
    local out = {}
    for _, word in ipairs(Spells.MACRO_GROUP_FIRST) do out[#out + 1] = "[" .. prefix .. "@mouseover," .. word .. "]" end
    return table.concat(out)
end
local ORDER = { "mod", "stance", "form", "noform", "stealth", "nostealth", "combat", "nochanneling", "pet", "petdead" }

-- Bedingung eines Schritts ohne Ziel (when) → Teile in Blizzards Schreibweise: { "mod:shift", "stance:1", … }
local function Parts(when)
    local parts = {}
    if type(when) ~= "table" then return parts end
    for _, key in ipairs(ORDER) do
        local v = when[key]
        -- false zählt nur bei combat und pet („nicht im Kampf“, „ohne Begleiter“); sonst heißt false „ohne Bedingung“
        if (v ~= nil and v ~= false) or ((key == "combat" or key == "pet") and v == false) then
            if key == "mod" then parts[#parts + 1] = "mod:" .. tostring(v)
            elseif key == "stance" then parts[#parts + 1] = "stance:" .. tostring(v)
            elseif key == "form" then parts[#parts + 1] = "form:" .. tostring(v)
            elseif key == "combat" then parts[#parts + 1] = v and "combat" or "nocombat"
            elseif key == "pet" then parts[#parts + 1] = v and "pet" or "nopet"
            elseif key == "petdead" then parts[#parts + 1] = "@pet,dead"
            else parts[#parts + 1] = key end
        end
    end
    return parts
end

-- Bedingung eines Schritts in Blizzards Makro-Schreibweise, mit der Zielkette des Eintrags (unit, chain, kind):
-- { mod = "shift" } mit unit = "help", kind = "mouseover" → "[mod:shift,@mouseover,party][mod:shift,@mouseover,raid]
-- [mod:shift,@mouseover,help,nodead][mod:shift,help,nodead][mod:shift,@player]" (ohne Zeilenumbruch).
-- Ohne Ziel bzw. Kette nur die Bedingung ("[stance:1]"); leere Bedingung ohne Ziel → "".
-- opts.group == false: die Kette ohne die Glieder „Mitglied unter der Maus“ (Fassung vor dem 15.11.2026) – nur, um alte
-- Makros wiederzuerkennen (ezHeal hebt seine unveränderten Makros auf die neue Kette). opts.short == true: Kurzform
-- „[…@mouseover,exists,noharm]“ statt der Gruppen-Glieder und des Maus-Glieds (siehe oben).
function Spells.MacroCondition(when, unit, chain, kind, opts)
    local base = Parts(when)
    chain = chain or (kind and Spells.MACRO_CHAINS[kind]) or nil
    local word = unit and UNIT_WORD[unit]
    if not (word and type(chain) == "table") then
        if #base == 0 then return "" end
        return "[" .. table.concat(base, ",") .. "]"
    end
    local out = {}
    for index, target in ipairs(chain) do
        local parts = {}
        for _, p in ipairs(base) do parts[#parts + 1] = p end
        if target == "player" then
            parts[#parts + 1] = "@player"
        elseif target == "target" then
            -- Als letztes Glied ohne Prüfung („sonst das Ziel“: Blizzard meldet selbst, wenn es nicht passt),
            -- davor mit (dann folgt noch ein Glied, z. B. „sonst du selbst“)
            if index < #chain then parts[#parts + 1] = word end
        else
            local group = target == "mouseover" and GROUP_UNITS[unit] and not (type(opts) == "table" and opts.group == false)
            local short = group and type(opts) == "table" and opts.short == true
            if group and not short then
                out[#out + 1] = GroupLinks(#parts > 0 and (table.concat(parts, ",") .. ",") or "")
            end
            parts[#parts + 1] = "@" .. target
            parts[#parts + 1] = short and Spells.MACRO_GROUP_SHORT or word
        end
        out[#out + 1] = "[" .. table.concat(parts, ",") .. "]"
    end
    return table.concat(out)
end

-- Fertigen Makrotext auf die Kette ohne Durchrutschen heben: vor jedes Glied „[…@mouseover,help,nodead]“ (ebenso
-- exists,nodead, help,dead, help) kommen die Glieder „Mitglied unter der Maus“ mit denselben Teilen davor,
-- z. B. "[mod:shift,@mouseover,help,nodead][mod:shift]" → "[mod:shift,@mouseover,party][mod:shift,@mouseover,raid]
-- [mod:shift,@mouseover,help,nodead][mod:shift]". Glieder für Gegner bleiben. Mehrfach angewandt ändert es nichts
-- mehr (stehen die Glieder schon davor, bleibt der Text). Für ezMacros feste Vorlagen und eigene Makrotexte.
-- Nur Zeilen mit /cast, /use und Verwandten (CAST_COMMANDS) und Zeilen ohne Befehl (Bausteine wie
-- "[@mouseover,help,nodead][]"); /focus, /assist, /follow, /tm … bleiben.
local function LiftLine(line)
    local command = line:match("^%s*/(%a+)")
    if command and not CAST_COMMANDS[command:lower()] then return line end
    return (line:gsub("()%[([^%[%]]-)@mouseover,([^%[%]]*)%]", function(at, prefix, word)
        if not GROUP_WORDS[word] then return nil end
        local links = GroupLinks(prefix)
        if at > #links and line:sub(at - #links, at - 1) == links then return nil end
        return links .. "[" .. prefix .. "@mouseover," .. word .. "]"
    end))
end

-- Zauber-Teil der /cast-Zeile eines Eintrags der Makro-Logik (Welle 23a, A57): „Bedingung {s:ID}; … ; {s:ID}“ mit
-- Platzhaltern {s:ID} (den Namen setzt das Modul ein, wie ezMacro es tut). Je Schritt die Bedingung samt Zielkette
-- (Spells.MacroCondition mit unit/chain/kind des Eintrags und opts), ohne Zielkette bei notarget, „[mod:…]“ davor bei
-- when.orMod, „!“ vor dem Zauber bei keep. nil, wenn der Eintrag keine Schritte hat oder ein Schritt keine Zauber-ID.
function Spells.MacroCast(entry, opts)
    if type(entry) ~= "table" or type(entry.steps) ~= "table" or #entry.steps == 0 then return nil end
    local parts = {}
    for _, step in ipairs(entry.steps) do
        if type(step) ~= "table" or type(step.spell) ~= "number" then return nil end
        local cond
        if step.notarget then
            cond = Spells.MacroCondition(step.when)
        else
            cond = Spells.MacroCondition(step.when, entry.unit, entry.chain, entry.kind, opts)
        end
        local alt = type(step.when) == "table" and step.when.orMod
        if alt and cond ~= "" then cond = "[mod:" .. tostring(alt) .. "]" .. cond end
        parts[#parts + 1] = (cond ~= "" and (cond .. " ") or "") .. (step.keep and "!" or "") .. ("{s:%d}"):format(step.spell)
    end
    return table.concat(parts, "; ")
end

function Spells.MacroGroupFirst(text)
    if type(text) ~= "string" then return text end
    local out = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do out[#out + 1] = LiftLine(line) end
    return table.concat(out, "\n")
end

-- Steht in einem Makrotext schon die Kette ohne Durchrutschen? (jedes Glied für Mitspieler hat die Gruppen-Glieder)
function Spells.MacroGroupSafe(text)
    return type(text) == "string" and Spells.MacroGroupFirst(text) == text
end
