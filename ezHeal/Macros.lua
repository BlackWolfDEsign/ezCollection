local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Heil-Makros je Klasse (Wunsch des Nutzers vom 15.11.2026: „für ezHeal und ezBuff für jede klasse presets für die
    macros zum healen und durchbuffen, recherchieren und einbauen“; ezHeal macht das Heilen, ezBuff das Durchbuffen).
    Neben den Klick-Vorlagen legt ezHeal auf Wunsch Makros in Blizzards Makrofenster an (das Original, Leitlinie 1) –
    sichtbar über den Knopf „Vorlagen“ an Blizzards Fenster „Klick-Zauber“ und die Einstellungsseite (Leitlinie 3),
    immer mit Vorschau und Rückfrage.

    Woher die Makros kommen (SSOT, nichts doppelt):
      - Zauber: dieselben Plätze wie die Klick-Vorlage „Heilen“ (Templates.lua, T.CLASSES – Zauber-IDs nur aus ezCore,
        HL-03); der Jäger nimmt die Logik „petCare“ aus ezCores Makro-Logik (Spells.MacroLogic).
      - Bedingungen: ezCores Spells.MacroCondition (dieselbe Schreibweise wie ezMacros Vorlagen), Zielkette
        Mausziel, sonst Ziel, sonst du selbst; Wiederbeleben: Mausziel, wenn es tot ist, sonst dein Ziel (das letzte
        Glied prüft ezCore nicht – passt das Ziel nicht, meldet Blizzard es selbst). Steht die Maus auf einem Mitglied
        deiner Gruppe bzw. deines Schlachtzugs, wirkt das Makro auf genau dieses oder gar nicht – nie auf dein Ziel
        (Spieltest des Nutzers vom 15.11.2026; die Glieder „[@mouseover,party][@mouseover,raid]“ setzt ezCore).
        Würde der Text dadurch länger als Blizzards 255 Zeichen, nehmen erst die Umschalt-Schritte, dann alle ezCores
        Kurzform „[@mouseover,exists,noharm]“ (jede nicht feindliche Einheit unter der Maus fängt den Zauber ab).
      - Alte Makros: Makros, die ezHeal vor dieser Kette angelegt hat und deren Text noch genau so dasteht, hebt
        ezHeal still beim Laden auf die neue Kette (außerhalb des Kampfes, einmal mit Hinweis im Chat; M.Lift) –
        ebenso beim nächsten „Makros anlegen“. Selbst geänderte Makros fasst ezHeal nie an.
      - Namen: aus der Zauber-ID über den Client (Spells.Name, Sprache des Clients), der erste gelernte Zauber einer
        Liste. Den Rang nennt das Makro nicht: /cast mit dem Namen wirkt den höchsten gelernten Rang.
    Angelegt und geändert wird über ezCores Dienst „Makro anlegen“ (Core.Macro: Find, Write, Limits, Free – eine Stelle
    für CreateMacro/EditMacro, Welle 23, A2; vorher ein eigener schmaler Anleger hier). Nur das Löschen eigener Makros
    (DeleteMacro) bleibt hier, weil Core.Macro keines anbietet. Die Kennzeichen „Maus“ an Blizzards Aktionsknöpfen
    meldet ezHeal selbst bei Core.MacroBadge an (M.RegisterBadge, Welle 23, A1; vorher eine Übergangsregel in ezCore).
    ezMacro zeigt diese Makros über ezCore.API("ezHeal").HealMacros und legt sie über CreateHealMacros an (Entscheidung
    des Nutzers vom 16.11.2026, Nr. 9: Reiter „Makros“ nach Entwurf A; die Liste führt nur ezHeal, keine zweite).

    Regeln (Leitlinie 5 und Auftrag): CreateMacro/EditMacro/DeleteMacro nur außerhalb des Kampfes. Ein Makro mit
    demselben Namen, das ezHeal nicht selbst so angelegt hat (oder dessen Text du seitdem geändert hast), wird nie
    überschrieben oder gelöscht; beim Aktualisieren behält ein Makro sein Symbol (ein eigenes bleibt). Angelegt werden Charakter-Makros (Zauber der Klasse); reichen die freien Plätze
    nicht, legt ezHeal keines an. Zurück: „ezHeal-Makros entfernen“ löscht nur unveränderte eigene Makros.
    Gemerkt wird je Charakter, was ezHeal angelegt hat: ezHealDB.macros[charKey][name] = Text.

    Gestaltung (Empfehlung umgesetzt, Antwort des Nutzers offen – docs/roadmap/ezHeal.md): Name „ezH “ + Rolle bzw.
    Zaubername (höchstens 16 Zeichen), Symbol Fragezeichen mit #showtooltip (zeigt den Zauber), je Platz der Vorlage
    „Heilen“ ein Makro; zweite Stufe auf Umschalt (große Heilung, zweite Bann-Art); Notfallzauber (Handauflegung)
    wirken nur mit Umschalttaste.
]]

local M = {}
ns.Macros = M

M.PREFIX = "ezH "
M.NAME_MAX = 16                      -- Blizzards Makroname (Makrofenster: 16 Zeichen)
-- Aus ezCore (Core.Macro; Gesamtreview 18.11.2026, T16-8 – vorher eigene Werte, das Symbol als Texturname):
M.BODY_MAX = Core.Macro.MAX_CHARS    -- Blizzards Makrotext (255)
M.ICON = Core.Macro.DEFAULT_ICON     -- Fragezeichen (Datei-ID): mit #showtooltip zeigt das Makro den Zauber selbst
M.KIND = "mouseover"                 -- Zielkette aus ezCore (Spells.MACRO_CHAINS.mouseover)
M.EMERGENCY_MOD = "shift"            -- Notfallzauber nur mit dieser Umschalttaste

-- Je Makro: Plätze der Klick-Vorlage „Heilen“ (in Reihenfolge; der erste passende Schritt wirkt) oder ein Eintrag
-- aus ezCores Makro-Logik (logic). label: Text-Schlüssel des Namens; ohne label heißt das Makro nach dem Zauber.
M.DEFS = {
    { key = "heal", label = "MACRO_heal", unit = "help", steps = { { slot = "big", mod = "shift" }, { slot = "fast" } } },
    { key = "hot", unit = "help", steps = { { slot = "hot" } } },
    { key = "extra", unit = "help", steps = { { slot = "extra" } } },
    { key = "extra2", unit = "help", steps = { { slot = "extra2" } } },
    { key = "extra3", unit = "help", steps = { { slot = "extra3" } } },
    { key = "dispel", label = "MACRO_dispel", unit = "help", steps = { { slot = "dispel2", mod = "shift" }, { slot = "dispel" } } },
    { key = "res", label = "MACRO_res", unit = "dead", chain = { "mouseover", "target" }, steps = { { slot = "res" } } },
    { key = "pet", label = "MACRO_pet", logic = "petCare" },
}

local function Templates() return ns.Templates end

local function PlayerClass()
    return ns.playerClass or Core.PlayerClass()
end

-- Zauber-IDs eines Platzes der Vorlage „Heilen“ (Liste aus ezCore) oder nil
local function SlotList(class, slot)
    local data = Templates().CLASSES[class or ""]
    local value = data and data.heal and data.heal[slot]
    return type(value) == "table" and value[1] ~= nil and value or nil
end

-- Ist der Platz ein Notfallzauber? (Rolle „emergency“ in ezCores HEALS, z. B. Handauflegung)
local function IsEmergency(class, slot)
    local parts = Templates().SOURCES[class or ""]
    local source = parts and parts.heal and parts.heal[slot]
    return type(source) == "table" and source[1] == "heal" and source[2] == "emergency"
end

-- Erster gelernter Zauber einer Liste → Name (Sprache des Clients), Zauber-ID der Liste; nil, wenn keiner gelernt ist
local function LearnedName(list)
    local Sp = Core.Spells
    for _, id in ipairs(list or {}) do
        local maxID = Sp.Highest(id)
        if maxID then
            local name = Sp.Name(maxID) or Sp.Name(id)
            if type(name) == "string" and not Core.IsSecret(name) and name ~= "" then return name, id end
        end
    end
    return nil
end

local function SlotSteps(def, class)
    local steps = {}
    for _, step in ipairs(def.steps) do
        local name, id = LearnedName(SlotList(class, step.slot))
        if name then
            local emergency = IsEmergency(class, step.slot)
            local mod = emergency and M.EMERGENCY_MOD or step.mod
            steps[#steps + 1] = { name = name, id = id, when = mod and { mod = mod } or nil, emergency = emergency }
        end
    end
    -- Derselbe Zauber zweimal (z. B. Druide ohne Nachwachsen: schnell und groß sind Heilende Berührung): nur einmal
    local out = {}
    for i, step in ipairs(steps) do
        local later = false
        for j = i + 1, #steps do
            if steps[j].name == step.name then later = true break end
        end
        if not later then out[#out + 1] = step end
    end
    -- Ohne Schritt ohne Umschalttaste wirkt der letzte auch ohne – außer bei einem Notfallzauber
    local last = out[#out]
    if last and last.when and not last.emergency then last.when = nil end
    return out
end

-- Eintrag aus ezCores Makro-Logik (Spells.MacroLogic) → Schritte, Eintrag. Einträge mit Vorzeilen (pre) baut ezHeal
-- nicht (die Zeilen führt ezMacro); petCare hat keine.
local function LogicEntry(class, key)
    local Sp = Core.Spells
    if type(Sp.MacroLogic) ~= "function" then return nil end
    for _, entry in ipairs(Sp.MacroLogic(class)) do
        if entry.key == key and entry.pre == nil then return entry end
    end
    return nil
end

local function LogicSteps(def, class)
    local entry = LogicEntry(class, def.logic)
    if not entry then return nil end
    local steps = {}
    for _, step in ipairs(entry.steps or {}) do
        local name, id = LearnedName({ step.spell })
        if name then steps[#steps + 1] = { name = name, id = id, when = step.when } end
    end
    return steps, entry
end

-- Makrotext. opts.short: 1 = Umschalt-Schritte, 2 = alle Schritte in ezCores Kurzform (Spells.MacroCondition,
-- opts.short); opts.group == false: alte Kette ohne die Glieder „Mitglied unter der Maus“ (zum Wiedererkennen).
local function Body(steps, unit, chain, kind, opts)
    opts = opts or {}
    local parts = {}
    for _, step in ipairs(steps) do
        local condOpts
        if opts.group == false then
            condOpts = { group = false }
        elseif opts.short == 2 or (opts.short == 1 and step.when ~= nil) then
            condOpts = { short = true }
        end
        local condition = Core.Spells.MacroCondition(step.when, unit, chain, kind, condOpts)
        parts[#parts + 1] = (condition ~= "" and (condition .. " ") or "") .. step.name
    end
    return "#showtooltip\n/cast " .. table.concat(parts, "; ")
end

-- Erster passender Text: volle Kette, sonst Umschalt-Schritte kurz, sonst alle kurz → Text, Stufe (0, 1, 2)
local function FittingBody(steps, unit, chain, kind)
    local body
    for short = 0, 2 do
        body = Body(steps, unit, chain, kind, { short = short })
        if #body <= M.BODY_MAX then return body, short end
    end
    return body, 2
end

local function Text(key)
    local value = L[key]
    if value ~= key then return value end
    return nil
end

-- Hat die Klasse überhaupt Zauber für Makros (unabhängig davon, was schon gelernt ist)?
function M.ForClass(class)
    class = class or PlayerClass()
    for _, def in ipairs(M.DEFS) do
        if def.logic then
            if LogicEntry(class, def.logic) then return true end
        else
            for _, step in ipairs(def.steps) do
                if SlotList(class, step.slot) then return true end
            end
        end
    end
    return false
end

-- Makros der Klasse aus dem, was der Spieler gelernt hat → { { key, name, body, steps, unit, chain, kind, emergency,
-- long, short, legacy } } in fester Reihenfolge (M.DEFS). steps: { { name, id, when } }; short: Stufe der Kürzung
-- (0 = volle Kette); legacy: derselbe Text in der Fassung vor dem 15.11.2026 (ohne die Gruppen-Glieder).
function M.Build(class)
    class = class or PlayerClass()
    local out, taken = {}, {}
    -- Name aus Vorsilbe und Rolle bzw. Zauber, höchstens 16 Zeichen; ergäbe das Kürzen denselben Namen wie ein Makro
    -- davor, bekommt es eine Nummer (zwei Makros mit demselben Namen findet Blizzard nicht getrennt)
    local function Name(label)
        local name = Core.TruncateChars(M.PREFIX .. label, M.NAME_MAX)
        local n = 1
        while taken[name] do
            n = n + 1
            name = Core.TruncateChars(M.PREFIX .. label, M.NAME_MAX - 1 - #tostring(n)) .. " " .. n
        end
        taken[name] = true
        return name
    end
    for _, def in ipairs(M.DEFS) do
        local steps, unit, chain, kind = nil, def.unit, def.chain, M.KIND
        if def.logic then
            local entry
            steps, entry = LogicSteps(def, class)
            if entry then unit, chain, kind = entry.unit, entry.chain, entry.kind end
        else
            steps = SlotSteps(def, class)
        end
        if steps and #steps > 0 then
            local emergency = true
            for _, step in ipairs(steps) do emergency = emergency and step.emergency == true end
            local label = (emergency and Text("MACRO_emergency")) or (def.label and Text(def.label)) or steps[#steps].name
            local body, short = FittingBody(steps, unit, chain, kind)
            out[#out + 1] = { key = def.key, name = Name(label), body = body, short = short,
                legacy = Body(steps, unit, chain, kind, { group = false }),
                steps = steps, unit = unit, chain = chain, kind = kind, emergency = emergency, long = #body > M.BODY_MAX }
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Blizzards Makroverwaltung – über ezCores Dienst „Makro anlegen“ (Core.Macro, Welle 23, A2)
---------------------------------------------------------------------------

local function Api(name)
    local fn = rawget(_G, name)
    return type(fn) == "function" and fn or nil
end

-- Anlegen, Ändern und Suchen über Core.Macro; Löschen eigener Makros über Blizzards DeleteMacro (Core.Macro hat keines)
function M.Available()
    return Core.Macro.Available() == true and Api("DeleteMacro") ~= nil
end

-- Höchstzahl der Charakter-Makros (Core.Macro.Limits: Blizzards Konstante, sonst 18 wie in Blizzards Makrofenster)
function M.MaxChar()
    local _, maxChar = Core.Macro.Limits()
    return maxChar
end

-- Freie Plätze für Charakter-Makros (Core.Macro.Free)
function M.FreeSlots()
    return Core.Macro.Free(true)
end

local function Clean(body)
    if type(body) ~= "string" then return nil end
    return (body:gsub("\r\n", "\n"):gsub("\r", "\n"):gsub("%s+$", ""))
end

-- Vorhandenes Makro gleichen Namens → Index, Text (oder nil). Wie Blizzards GetMacroIndexByName der erste Treffer,
-- allgemein oder Charakter (Core.Macro.Find ohne perChar): Ein gleichnamiges allgemeines Makro zählt weiter als
-- fremdes und bleibt – ezHeal legt daneben kein zweites gleichen Namens an.
local function Find(name)
    local index, body = Core.Macro.Find(name)
    if not index then return nil end
    return index, Clean(body)
end

-- Schreiben über Core.Macro.Write (im Kampf schreibt der Dienst nichts): ohne index als Charakter-Makro anlegen, mit
-- index den Text ändern (Symbol nil: Blizzard behält das vorhandene, auch ein vom Spieler gewähltes). → Index | nil
local function Write(name, body, index)
    return (Core.Macro.Write(name, not index and M.ICON or nil, body, true, index))
end

-- Was ezHeal auf diesem Charakter angelegt hat: db.macros[charKey] = { [name] = Text } (Teil je Charakter wie die
-- Tasten und Belegungen der Vorlagen: Templates.lua, T.CharStore)
local function Store(create)
    return Templates().CharStore("macros", create)
end

-- Ein vergessener Charakter verliert auch seine Liste (Core.lua, CHAR_FORGOTTEN)
function M.Forget(charKey)
    if ns.db and type(ns.db.macros) == "table" and charKey then ns.db.macros[charKey] = nil end
end

-- Namen der Makros, die ezHeal auf diesem Charakter angelegt hat (sortiert)
function M.Owned()
    local names = {}
    for name in pairs(Store(false) or {}) do names[#names + 1] = name end
    table.sort(names)
    return names
end

-- Plan: M.Build plus Zustand je Makro:
--   "new"      gibt es noch nicht – wird angelegt
--   "update"   von ezHeal angelegt und seitdem unverändert, Text weicht ab (neu gelernter Zauber) – wird ersetzt
--   "same"     steht schon so da
--   "foreign"  gleichnamiges Makro, das nicht (mehr) von ezHeal stammt – bleibt unverändert
--   "long"     länger als Blizzard erlaubt – wird nicht angelegt
-- lift = true: ein „update“, dessen Text noch genau ezHeals alte Kette ist (M.Lift hebt es still)
function M.Plan(class)
    local store = Store(false) or {}
    local plan = M.Build(class)
    local available = M.Available()
    for _, macro in ipairs(plan) do
        local index, current
        if available then index, current = Find(macro.name) end
        if macro.long then
            macro.state = "long"
        elseif not index then
            macro.state = "new"
        elseif current == macro.body then
            macro.state = "same"
        elseif store[macro.name] and current == Clean(store[macro.name]) then
            macro.state = "update"
            macro.lift = current == macro.legacy and macro.legacy ~= macro.body
        else
            macro.state = "foreign"
        end
    end
    return plan
end

function M.Count(plan, state)
    local n = 0
    for _, macro in ipairs(plan) do
        if macro.state == state then n = n + 1 end
    end
    return n
end

-- Makros anlegen bzw. eigene aktualisieren. Nur außerhalb des Kampfes. only (optional): nur diese Makros, als Liste
-- oder Menge ihrer Schlüssel (M.DEFS, z. B. { "heal" }) – für ezMacro, das ein einzelnes Makro übernimmt.
-- → true, { created, updated, same, foreign, long, failed } | false, grund ("missing", "combat", "none", "full")
function M.Create(class, only)
    if not M.Available() then return false, "missing" end
    if Core.InCombat() then return false, "combat" end
    local plan = M.Plan(class)
    if type(only) == "table" then
        local wanted = {}
        for k, v in pairs(only) do
            if type(k) == "number" and type(v) == "string" then wanted[v] = true elseif v == true then wanted[k] = true end
        end
        local picked = {}
        for _, macro in ipairs(plan) do
            if wanted[macro.key] then picked[#picked + 1] = macro end
        end
        plan = picked
    end
    if #plan == 0 then return false, "none" end
    if M.Count(plan, "new") > M.FreeSlots() then return false, "full" end
    local store = Store(true)
    local result = { created = 0, updated = 0, same = 0, foreign = 0, long = 0, failed = 0 }
    for _, macro in ipairs(plan) do
        if macro.state == "new" then
            if Write(macro.name, macro.body) then
                store[macro.name] = macro.body
                result.created = result.created + 1
            else
                result.failed = result.failed + 1
            end
        elseif macro.state == "update" then
            local index = Find(macro.name)
            -- Symbol nil: Blizzard behält das vorhandene (auch ein vom Spieler gewähltes), wie Blizzards Makrofenster
            -- beim Speichern des Textes
            local ok = index and Write(macro.name, macro.body, index)
            if ok then
                store[macro.name] = macro.body
                result.updated = result.updated + 1
            else
                result.failed = result.failed + 1
            end
        elseif result[macro.state] then
            result[macro.state] = result[macro.state] + 1
        end
    end
    return true, result
end

-- Alte Makros still auf die Kette ohne Durchrutschen heben (Spieltest 15.11.2026): nur Makros, die ezHeal angelegt
-- hat, deren Text du seitdem nicht geändert hast und genau ezHeals alte Kette ist (Plan: lift). Nur außerhalb des
-- Kampfes; das Symbol bleibt. → Anzahl gehobener Makros (0, wenn nichts zu tun war oder gerade Kampf ist)
function M.Lift(class)
    if not M.Available() or Core.InCombat() then return 0 end
    local store = Store(false)
    if not store or next(store) == nil then return 0 end
    local lifted = 0
    for _, macro in ipairs(M.Plan(class)) do
        if macro.state == "update" and macro.lift then
            local index = Find(macro.name)
            if index and Write(macro.name, macro.body, index) then
                store[macro.name] = macro.body
                lifted = lifted + 1
            end
        end
    end
    return lifted
end

-- Beim Laden: heben und einmal im Chat sagen, was geschah (im Kampf wartet es auf das Kampfende)
function M.LiftNow()
    local lifted = M.Lift()
    if lifted > 0 then ns.Print(L.MACRO_LIFTED:format(lifted)) end
    return lifted
end

-- Eigene Makros entfernen (Zurück-Weg): nur, was ezHeal angelegt hat und dessen Text noch unverändert dasteht.
-- Makros mit geändertem Text bleiben und gelten danach als deine (das Symbol zählt nicht: GetMacroInfo meldet für
-- Fragezeichen-Makros mit #showtooltip je nach Client das Symbol des Zaubers, ein Vergleich wäre unsicher). → true, entfernt, behalten | false, grund ("missing", "combat", "nothing")
function M.Remove()
    if not M.Available() then return false, "missing" end
    if Core.InCombat() then return false, "combat" end
    local store = Store(false)
    if not store or next(store) == nil then return false, "nothing" end
    local removed, kept = 0, 0
    for _, name in ipairs(M.Owned()) do
        local index, current = Find(name)        -- je Name neu suchen: Löschen verschiebt die Nummern
        if index and current == Clean(store[name]) then
            if pcall(DeleteMacro, index) then
                removed = removed + 1
                store[name] = nil
            else
                kept = kept + 1
            end
        else
            if index then kept = kept + 1 end
            store[name] = nil
        end
    end
    return true, removed, kept
end

---------------------------------------------------------------------------
-- Vorschau, Rückfrage, Meldungen (Knopf „Vorlagen“, Einstellungen, /ezheal makros)
---------------------------------------------------------------------------

-- Bedingung eines Schritts als Text: „mit Umschalt“, „Tier tot“, „ohne Tier“
local function WhenText(when)
    if type(when) ~= "table" then return nil end
    local parts = {}
    if when.mod then
        local cb = Core.ClickBindings
        local mod = cb and cb.ModifierText and cb.ModifierText(tostring(when.mod):upper()) or tostring(when.mod)
        parts[#parts + 1] = L.MACRO_WITH:format(mod)
    end
    if when.petdead then parts[#parts + 1] = L.MACRO_WHEN_petdead end
    if when.pet == false then parts[#parts + 1] = L.MACRO_WHEN_nopet end
    if #parts == 0 then return nil end
    return table.concat(parts, ", ")
end

-- Was das Makro tut, ohne Namen: „Großes Heilen (mit Umschalt), sonst Blitzheilung – Mausziel, sonst Ziel, sonst du“
-- (Sprache des Clients; dieselbe Erklärung bekommt ezMacro über die Schnittstelle HealMacros)
function M.Explain(macro)
    local steps = {}
    for _, step in ipairs(macro.steps) do
        local when = WhenText(step.when)
        steps[#steps + 1] = when and (step.name .. " (" .. when .. ")") or step.name
    end
    local text = table.concat(steps, L.MACRO_ELSE)
    -- Kürzungsstufe 1 kürzt nur die Schritte mit Taste (_shiftshort), Stufe 2 alle Schritte (_short)
    local level = macro.short or 0
    local target = macro.unit and ((level >= 2 and Text("MACRO_TARGET_" .. macro.unit .. "_short"))
        or (level == 1 and Text("MACRO_TARGET_" .. macro.unit .. "_shiftshort"))
        or Text("MACRO_TARGET_" .. macro.unit))
    if target then text = text .. " – " .. target end
    return text
end

-- Zeile der Vorschau: „ezH Heilen: Großes Heilen (mit Umschalt), sonst Blitzheilung – Mausziel, sonst Ziel, sonst du [neu]“
function M.Line(macro)
    local text = macro.name .. ": " .. M.Explain(macro)
    local state = macro.state and Text("MACRO_STATE_" .. macro.state)
    if state then text = text .. " [" .. state .. "]" end
    return text
end

-- Hinweis, wenn es nichts anzulegen gibt → Zeilen
function M.NoneLines(class)
    class = class or PlayerClass()
    local className = Core.ClassName(class) or tostring(class)
    if M.ForClass(class) then return { L.MACRO_NONE_LEVEL } end
    local lines = { L.MACRO_NONE_CLASS:format(className) }
    if Templates().Has("buffs", class) then lines[#lines + 1] = L.MACRO_NONE_BUFFS:format(ns.KindLabel("buffs")) end
    return lines
end

-- Vorschau als Zeilen (mit Makrotext, wenn full)
function M.PreviewLines(class, full)
    class = class or PlayerClass()
    local plan = M.Plan(class)
    local lines = { L.MACRO_HEAD:format(Core.ClassName(class) or tostring(class)) }
    if #plan == 0 then
        for _, line in ipairs(M.NoneLines(class)) do lines[#lines + 1] = line end
        return lines, plan
    end
    for _, macro in ipairs(plan) do
        lines[#lines + 1] = M.Line(macro)
        if full then
            for bodyLine in macro.body:gmatch("[^\n]+") do lines[#lines + 1] = "    " .. bodyLine end
        end
    end
    return lines, plan
end

function ns.PrintMacros()
    for _, line in ipairs((M.PreviewLines(nil, true))) do ns.Print(line) end
end

-- Grund „combat“: ezCores Satz zur Kampfsperre (ns.CombatText, T18-1) statt eines eigenen Texts
local ERR = { missing = "MACRO_ERR_missing", full = "MACRO_ERR_full", none = "MACRO_NONE_LEVEL",
    nothing = "MACRO_NONE_OWNED" }
local function ErrText(reason)
    if reason == "combat" then return ns.CombatText(L.MACRO_COMBAT_WHAT) end
    local key = ERR[reason]
    return key and L[key] or tostring(reason)
end

-- Hinweise zu Makros, die ezHeal nicht anlegt: gleichnamige fremde, zu lange
function ns.PrintSkipped(foreign, long)
    if (foreign or 0) > 0 then ns.Print(L.MACRO_KEPT_FOREIGN:format(foreign)) end
    if (long or 0) > 0 then ns.Print(L.MACRO_SKIPPED_LONG:format(long)) end
end

function ns.AskMacros()
    if not M.Available() then ns.Print(L.MACRO_ERR_missing) return false end
    if Core.InCombat() then ns.CombatNotice(L.MACRO_COMBAT_WHAT) return false end
    local lines, plan = M.PreviewLines()
    if #plan == 0 then
        for _, line in ipairs(lines) do ns.Print(line) end
        return false
    end
    local new, update = M.Count(plan, "new"), M.Count(plan, "update")
    if new + update == 0 then
        for _, line in ipairs(lines) do ns.Print(line) end
        -- „Alles schon da“ nur, wenn wirklich jedes Makro so dasteht; sonst sagen, warum keines angelegt wird
        if M.Count(plan, "same") == #plan then
            ns.Print(L.MACRO_NOTHING_NEW)
        else
            ns.PrintSkipped(M.Count(plan, "foreign"), M.Count(plan, "long"))
            ns.Print(L.MACRO_NOTHING_CREATED)
        end
        return false
    end
    local free = M.FreeSlots()
    if new > free then
        ns.Print(L.MACRO_ERR_full:format(new, free, M.MaxChar()))
        return false
    end
    table.remove(lines, 1)   -- Kopfzeile steht in der Frage
    Core.Confirm(L.MACRO_ASK:format(table.concat(lines, "\n"), free, M.MaxChar()), function() ns.CreateMacrosNow() end)
    return true
end

function ns.CreateMacrosNow()
    local ok, result = M.Create()
    if not ok then
        local text = ErrText(result)
        if result == "full" then text = text:format(M.Count(M.Plan(), "new"), M.FreeSlots(), M.MaxChar()) end
        ns.Print(text)
        return false, result
    end
    ns.Print(L.MACRO_DONE:format(result.created, result.updated))
    ns.PrintSkipped(result.foreign, result.long)
    if result.failed > 0 then ns.Print(L.MACRO_FAILED:format(result.failed)) end
    -- Ergebnis im Original zeigen: Blizzards Makrofenster (nur außerhalb des Kampfes)
    local show = Api("ShowMacroFrame")
    if show and (result.created + result.updated) > 0 and not Core.InCombat() then pcall(show) end
    return true, result
end

function ns.AskRemoveMacros()
    if not M.Available() then ns.Print(L.MACRO_ERR_missing) return false end
    if Core.InCombat() then ns.CombatNotice(L.MACRO_COMBAT_WHAT) return false end
    local names = M.Owned()
    if #names == 0 then ns.Print(L.MACRO_NONE_OWNED) return false end
    Core.Confirm(L.MACRO_ASK_REMOVE:format(table.concat(names, ", ")), function() ns.RemoveMacrosNow() end, { alert = true })
    return true
end

function ns.RemoveMacrosNow()
    local ok, removed, kept = M.Remove()
    if not ok then
        ns.Print(ErrText(removed))
        return false, removed
    end
    ns.Print(L.MACRO_REMOVED:format(removed, kept))
    return true, removed, kept
end

-- Zeile für /ezheal status
function M.StatusLine()
    local owned = #M.Owned()
    if owned == 0 then return nil end
    return L.STATUS_MACROS:format(owned)
end

---------------------------------------------------------------------------
-- Schnittstelle für ezMacro (Entscheidung des Nutzers vom 16.11.2026, Nr. 9; Reiter „Makros“ nach Entwurf A)
---------------------------------------------------------------------------

-- Heil-Makros der Klasse, wie ezHeal sie anlegen würde → Liste (Kopie) in fester Reihenfolge:
--   { key, name, icon, body, kind = "heal", badge = "mouseover" | nil, perChar = true, state, tip,
--     steps = { { name, id, mod } } }
-- state wie M.Plan ("new", "update", "same", "foreign", "long"); tip erklärt das Makro in der Sprache des Clients
-- (Texte deutsch und englisch in Locale.lua); badge ist das Kennzeichen am Aktionsknopf (Core.MacroBadge).
function M.HealMacros(class)
    local out = {}
    for _, macro in ipairs(M.Plan(class)) do
        local steps = {}
        for i, step in ipairs(macro.steps) do
            steps[i] = { name = step.name, id = step.id, mod = type(step.when) == "table" and step.when.mod or nil }
        end
        out[#out + 1] = { key = macro.key, name = macro.name, icon = M.ICON, body = macro.body, kind = "heal",
            badge = M.BadgeKind(macro.name, macro.body), perChar = true, state = macro.state, tip = M.Explain(macro),
            steps = steps }
    end
    return out
end

if type(ns.API) == "table" then
    -- Liste der Heil-Makros (M.HealMacros); class: andere Klasse (Zauber, die der Spieler kennt)
    ns.API.HealMacros = function(class) return M.HealMacros(class) end
    -- Anlegen ohne Rückfrage (der Aufrufer fragt selbst), über ezCores Dienst Core.Macro; keys: nur diese Makros
    -- (Liste der Schlüssel aus HealMacros). → wie M.Create: true, Ergebnis | false, Grund
    ns.API.CreateHealMacros = function(keys, class) return M.Create(class, keys) end
end

-- Kennzeichen „Maus“ an Blizzards Aktionsknöpfen mit einem ezH-Makro (Core.MacroBadge, Welle 15): ezHeal meldet sich
-- selbst an (Welle 23, A1; vorher stand eine Übergangsregel in ezCore/Bausteine/MacroBadge.lua, die diese Anmeldung
-- ersetzt). Erkennung am Namen (M.PREFIX, den M.Build vergibt) und an der Zielkette: ein Makro mit Mausziel bekommt
-- M.KIND, das Begleiter-Makro (petCare, ohne Mausziel) kein Zeichen. Rückgabe wie MacroBadge.Register.
-- Leitlinie 6: Der Makrotext kann gesperrt sein (type() meldet dann "string", find würfe) – IsSecret zuerst, ein
-- gesperrter Text bekommt kein Zeichen (Gesamtreview 18.11.2026, T13-4).
function M.BadgeKind(_, body)
    if Core.IsSecret(body) then return nil end
    if type(body) == "string" and body:find("@mouseover", 1, true) then return M.KIND end
    return nil
end

function M.RegisterBadge()
    local MB = Core.MacroBadge
    if not (MB and type(MB.Register) == "function") then return false end
    return MB.Register("ezHeal", { prefix = M.PREFIX, kindOf = M.BadgeKind }) == true
end

ns.OnReady(function() M.RegisterBadge() end)

-- Alte Makros beim Laden heben (M.Lift): kurz nach dem Einloggen, wenn das Zauberbuch steht; im Kampf danach
ns.OnReady(function()
    local function Run()
        if ns.AfterCombat then ns.AfterCombat(M.LiftNow, "macroLift") else M.LiftNow() end
    end
    if C_Timer and C_Timer.After then C_Timer.After(3, function() ns.Try("MacroLift", Run) end) else Run() end
end)
