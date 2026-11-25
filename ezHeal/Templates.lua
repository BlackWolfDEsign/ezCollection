local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Vorlagen für Blizzards Klick-Zaubern (ezCore.ClickBindings) – je Klasse für alle Klassen, die Heil-, Bann-,
    Wiederbelebungs- oder Buff-Zauber auf Mitspieler haben (Entscheidung des Nutzers vom 13.11.2026: „direkt für alle“).

    Quelle der Zauber-IDs: ezCore allein (SSOT, HL-03). Heilen, Bannen und Wiederbeleben kommen aus den Gruppen
    Spells.HEALS, Spells.DISPELS und Spells.RESURRECTS, weitere Zauber auf Mitspieler aus Spells.HELPERS, Buffs aus
    ezCores Buff-Wissen (Leseschnittstelle Spells.IsBuff/BuffField/BuffKey, F7 – nie die Rohtabelle; alle Daten in
    ezCore/SpellData.lua: Rang-1-IDs aus Blizzards Client); Namen und Ersatznamen aus
    Spells.Name bzw. Spells.FALLBACK. Hier steht nur, welche Rolle auf welchem Platz liegt (T.SOURCES, Zuordnung wie
    in docs/roadmap/ezCore.md, Welle 8). Ob Forever jede ID kennt, prüft /ez test über Core.AddSelfTest (unten).
    Paladin: Segen des Schutzes und Segen der Freiheit (Entscheidung des Nutzers vom 13.11.2026: „Mit
    aufnehmen“) – Spells.HELPERS.PALADIN[1] und [2]; Plätze extra2 und extra3.
    Rang: Der Client entscheidet – je Taste gilt der höchste Rang, den das Zauberbuch kennt (Spells.Highest);
    eine Liste nennt Ersatz in Reihenfolge (z. B. Großes Heilen, sonst Heilen, sonst Geringes Heilen).
    Tasten: T.SLOTS ist der Vorschlag ab Werk; jeder Platz ist frei wählbar (Entscheidung des Nutzers vom 13.11.2026:
    „Jetzt frei wählbar“, „Ja, Vorschlag + wählbar“), gespeichert je Charakter und Vorlage (Heilen bzw. Buffs; „Beides“
    nutzt beide). Doppelt belegte Tasten sperren das Übernehmen.
]]

local T = {}
ns.Templates = T

-- Tasten der Vorlagen ab Werk (eine Stelle, der „Vorschlag“): Platz → { Maustaste, Umschalttasten }.
-- Linksklick und Rechtsklick ohne Umschalttaste bleiben Blizzards „Ziel“ und „Menü“.
-- Ohne Alt (Fehler des Nutzers vom 23.11.2026): Alt ist ab Werk Blizzards Selbstwirk-Taste (Forever-Quelle
-- Bindings_Camelot.xml, ModifiedClick SELFCAST = ALT; Kommentar bei Core.ClickBindings.SelfCastKey) – ein Klick mit
-- Alt wirkte auf dich statt auf den Rahmen. Bis dahin lagen Wiederbeleben, zweites Bannen, extra3 und Buff 4–6 auf
-- Alt bzw. Umschalt+Alt. Ohne Alt bleiben Umschalt, Strg und Umschalt+Strg: an Links, Rechts und Mitte für die
-- übrigen neun Plätze, an Maustaste 4 der Rest der Vorlage „Heilen“ (vorher die Reihe Alt), an Maustaste 5 Buff 4–6
-- (vorher die Reihe Umschalt+Alt). Jede Taste behält eine Umschalttaste – blanke Klicks bleiben für Blizzards „Ziel“
-- und „Menü“ und für eigene Belegungen frei. Wer keine Maustasten 4 und 5 hat, wählt die Taste unter „Tasten wählen“.
-- Liegt ein Platz auf der Selbstwirk-Taste (eigene Wahl oder eine andere Selbstwirk-Taste), sperrt T.Conflicts das
-- Übernehmen.
T.SLOTS = {
    fast = { "left", "SHIFT" },
    big = { "right", "SHIFT" },
    hot = { "left", "CTRL" },
    dispel = { "right", "CTRL" },
    res = { "button4", "SHIFT" },
    dispel2 = { "button4", "CTRL" },
    extra = { "middle", "SHIFT" },
    extra2 = { "middle", "CTRL" },
    extra3 = { "button4", "SHIFT-CTRL" },
    buff1 = { "left", "SHIFT-CTRL" },
    buff2 = { "right", "SHIFT-CTRL" },
    buff3 = { "middle", "SHIFT-CTRL" },
    buff4 = { "button5", "SHIFT" },
    buff5 = { "button5", "CTRL" },
    buff6 = { "button5", "SHIFT-CTRL" },
}
T.SLOT_ORDER = { "fast", "big", "hot", "dispel", "res", "dispel2", "extra", "extra2", "extra3",
    "buff1", "buff2", "buff3", "buff4", "buff5", "buff6" }
T.KINDS = { "heal", "buffs", "all" }

-- Wählbare Tasten (Auswahlfelder der Vorschau): Maustasten und Umschalttasten samt Kombinationen.
-- "" = ohne Umschalttaste; Links und Rechts ohne Umschalttaste gehören Blizzards „Ziel“ und „Menü“ (T.RESERVED).
-- T.RESERVED sperrt das Übernehmen, sobald ein Platz dort liegt (T.Conflicts): Da ezHeal genau die Vorschau schreibt
-- (keepDefaults = false, Fund H2), würde die Vorlage „Ziel“ bzw. „Menü“ sonst ersetzen – und ohne „Ziel“ per
-- Linksklick lässt sich an Blizzards Rahmen niemand mehr anwählen. Wer das wirklich will, belegt die Taste in
-- Blizzards Fenster selbst.
T.BUTTONS = { "left", "right", "middle", "button4", "button5" }
T.MODIFIERS = { "", "SHIFT", "CTRL", "ALT", "SHIFT-CTRL", "SHIFT-ALT", "CTRL-ALT", "SHIFT-CTRL-ALT" }
T.RESERVED = { ["left:"] = "target", ["right:"] = "menu" }

-- Je Klasse: heal = Heilen, Bannen, Wiederbeleben; buffs = Buffs auf Mitspieler. Wert eines Platzes ist die Herkunft
-- in ezCore, keine Zauber-ID (HL-03; die Rollen in ezCore heißen nach dem Zauber, nicht nach ezHeals Platz):
--   { "heal", Rolle }    Spells.HEALS[Klasse][Rolle]       (fast, big, hot, shield, group, emergency)
--   { "dispel", Art }    Spells.DISPELS[Klasse][Art]       (magic, curse, poison, disease)
--   { "res" }            Spells.RESURRECTS[Klasse]
--   { "helper", n }      Spells.HELPERS[Klasse][n]         (in Reihenfolge)
--   "schlüssel"          Buff-Schlüssel (Spells.IsBuff)    (Buff mit Rang-Liste: Spells.BuffField(…, "spells"))
-- Der Schamane führt Kettenheilung (HEALS.SHAMAN.group) auf dem Platz hot; der Paladin bannt auf dispel mit der
-- Liste für Gift (Läutern-Ersatz in Reihenfolge wie bisher).
-- Prüfung je Klasse für den Forever-Client (Welle 14, Wunsch des Nutzers vom 15.11.2026; Beleg je ID im Kopf von
-- Spells.HELPERS in ezCore/Wissen/SpellData.lua und in docs/roadmap/ezHeal.md): Der Paladin verliert die Segen der
-- Rettung, des Lichts und des Refugiums (der Forever-Client kennt sie nicht) und bekommt Segen der Opferung; der
-- Schamane bekommt eine Vorlage „Buffs“ (Wasseratmung, Wasserwandeln), der Hexenmeister Unsichtbarkeit entdecken.
-- Krieger, Schurke und Jäger haben keine Zauber auf Mitspieler und darum keine Vorlage (Jäger: Makro für das Tier,
-- Macros.lua).
T.SOURCES = {
    PRIEST = {
        heal = { fast = { "heal", "fast" }, big = { "heal", "big" }, hot = { "heal", "hot" }, dispel = { "dispel", "magic" },
            res = { "res" }, dispel2 = { "dispel", "disease" }, extra = { "heal", "shield" } },
        buffs = { buff1 = "fort", buff2 = "spirit", buff3 = "shadowProt", buff4 = { "helper", 1 } },
    },
    DRUID = {
        heal = { fast = { "heal", "fast" }, big = { "heal", "big" }, hot = { "heal", "hot" }, dispel = { "dispel", "curse" },
            res = { "res" }, dispel2 = { "dispel", "poison" } },
        buffs = { buff1 = "motw", buff2 = "thorns", buff3 = { "helper", 1 } },
    },
    SHAMAN = {
        heal = { fast = { "heal", "fast" }, big = { "heal", "big" }, hot = { "heal", "group" }, dispel = { "dispel", "poison" },
            res = { "res" }, dispel2 = { "dispel", "disease" } },
        buffs = { buff1 = { "helper", 1 }, buff2 = { "helper", 2 } },
    },
    PALADIN = {
        heal = { fast = { "heal", "fast" }, big = { "heal", "big" }, hot = { "heal", "hot" }, dispel = { "dispel", "poison" },
            res = { "res" }, extra = { "heal", "emergency" }, extra2 = { "helper", 1 }, extra3 = { "helper", 2 } },
        buffs = { buff1 = "might", buff2 = "wisdom", buff3 = "kings", buff4 = { "helper", 3 } },
    },
    MAGE = {
        heal = { dispel = { "dispel", "curse" } },
        buffs = { buff1 = "int", buff2 = { "helper", 1 }, buff3 = { "helper", 2 }, buff4 = { "helper", 3 } },
    },
    WARLOCK = {
        buffs = { buff1 = { "helper", 1 }, buff2 = { "helper", 2 } },
    },
}

-- Herkunft → Liste von Zauber-IDs aus ezCore (Kopie; die erste, die du kennst, gilt) bzw. der Buff-Schlüssel;
-- nil, wenn ezCore für Klasse und Rolle nichts führt (der Platz bleibt dann leer).
local function FromCore(class, source)
    if type(source) == "string" then return source end
    local Sp = Core.Spells
    if type(source) ~= "table" or type(Sp) ~= "table" then return nil end
    local kind, key, list = source[1], source[2], nil
    if kind == "heal" and type(Sp.HealSpells) == "function" then
        list = Sp.HealSpells(class, key)
    elseif kind == "dispel" and type(Sp.DispelSpells) == "function" then
        list = Sp.DispelSpells(class, key)
    elseif kind == "res" and type(Sp.ResurrectSpells) == "function" then
        list = Sp.ResurrectSpells(class)
    elseif kind == "helper" then
        local helpers = type(Sp.HELPERS) == "table" and Sp.HELPERS[class]
        local id = type(helpers) == "table" and helpers[key] or nil
        list = id and { id } or nil
    end
    if type(list) == "table" and list[1] ~= nil then return list end
    return nil
end

-- Vorlagen aus ezCore bauen: { [Klasse] = { heal = { [platz] = Liste }, buffs = { [platz] = Liste | Schlüssel } } }.
-- Läuft beim Laden (ezCore ist dann geladen, RequiredDeps); ruft man es erneut, gilt ezCores Stand von jetzt.
function T.Build()
    local out = {}
    for class, parts in pairs(T.SOURCES) do
        local data = {}
        for part, slots in pairs(parts) do
            local filled = {}
            for slot, source in pairs(slots) do filled[slot] = FromCore(class, source) end
            if next(filled) then data[part] = filled end
        end
        if next(data) then out[class] = data end
    end
    return out
end

-- Je Klasse und Vorlage: Wert eines Platzes ist eine Liste von Zauber-IDs oder ein Buff-Schlüssel aus ezCore.
T.CLASSES = T.Build()

local function CB() return Core.ClickBindings end

-- Text oder nil (ezCores Text-Tabelle liefert für fehlende Schlüssel den Schlüssel selbst)
local function Text(key)
    local value = L[key]
    if value ~= key then return value end
    return nil
end
ns.Text = Text

function ns.KindLabel(kind)
    return Text("KIND_" .. tostring(kind)) or tostring(kind)
end

local function PlayerClass()
    return ns.playerClass or Core.PlayerClass()
end

-- Zauber-IDs eines Platzes (Liste oder Buff-Schlüssel) → Liste
local function Candidates(value)
    if type(value) == "table" then return value end
    local spells = type(value) == "string" and Core.Call(Core.Spells and Core.Spells.BuffField, value, "spells")
    if type(spells) == "table" and spells[1] then return { spells[1] } end
    return {}
end

function T.SpellName(id)
    local name = Core.Spells and Core.Spells.Name and Core.Spells.Name(id)
    if name then return name end   -- Client, sonst ezCores Ersatzname (Spells.FALLBACK)
    return "#" .. tostring(id)
end

-- Plätze einer Vorlage für eine Klasse: { [platz] = Wert } (bei "all" beide zusammen)
function T.Slots(kind, class)
    local data = T.CLASSES[class or PlayerClass() or ""]
    local out = {}
    if not data then return out end
    for _, part in ipairs(kind == "all" and { "heal", "buffs" } or { kind }) do
        for slot, value in pairs(data[part] or {}) do out[slot] = value end
    end
    return out
end

-- Hat die Klasse in dieser Vorlage überhaupt etwas? (für Auswahl und Schnittstelle)
function T.Has(kind, class)
    return next(T.Slots(kind, class)) ~= nil
end

-- Alle Zauber-IDs aller Vorlagen (für den Selbsttest und die Tests)
function T.AllSpellIDs()
    local ids, seen = {}, {}
    for _, data in pairs(T.CLASSES) do
        for _, part in pairs(data) do
            for _, value in pairs(part) do
                for _, id in ipairs(Candidates(value)) do
                    if not seen[id] then seen[id] = true; ids[#ids + 1] = id end
                end
            end
        end
    end
    table.sort(ids)
    return ids
end

---------------------------------------------------------------------------
-- Tasten frei wählbar: Vorschlag ab Werk (T.SLOTS) oder eigene Wahl je Charakter und Vorlage
---------------------------------------------------------------------------

-- Zu welcher Vorlage gehört ein Platz? Buff-Plätze → "buffs", alle anderen → "heal" („Beides“ nutzt beide).
function T.PartOf(slot)
    return tostring(slot):match("^buff") and "buffs" or "heal"
end

local function Listed(list, value)
    for _, v in ipairs(list) do
        if v == value then return true end
    end
    return false
end

-- Derselbe Zauber, auch in einem anderen Rang? (HL-05: ezMacros „Ränge aktualisieren“ tauscht auf einer von ezHeal
-- geschriebenen Taste nur die Zauber-ID – die Belegung bleibt die eigene.) Gleich sind: dieselbe ID, zwei Ränge
-- derselben Rang-Liste eines Buffs (Spells.BuffField(schlüssel, "spells")) und zwei IDs mit demselben Namen im
-- Client (Ränge eines Zaubers heißen gleich). Bewusst NICHT über Spells.FamilyOf: Eine Familie (Siegel, Aspekte,
-- Flüche) fasst verschiedene Zauber zusammen, die sich nur ausschließen – das wäre ein fremder Zauber, und der
-- bleibt geschützt.
-- Auch die Gruppenfassung eines Buffs (Gebet der Seelenstärke) ist ein anderer Zauber.
function T.SameSpell(a, b)
    a, b = tonumber(a), tonumber(b)
    if not (a and b) then return false end
    if a == b then return true end
    local spells = Core.Spells
    if type(spells) ~= "table" then return false end
    local key = Core.Call(spells.BuffKey, a)
    local ranks = type(key) == "string" and Core.Call(spells.BuffField, key, "spells")
    if type(ranks) == "table" and Listed(ranks, a) and Listed(ranks, b) then return true end
    if type(spells.Name) ~= "function" then return false end
    local nameA, nameB = spells.Name(a), spells.Name(b)
    return type(nameA) == "string" and nameA ~= "" and nameA == nameB
end

-- Umschalttasten in fester Reihenfolge (Umschalt, Strg, Alt) → Text wie in T.MODIFIERS; nil bei Unbekanntem
function T.NormalizeModifiers(modifiers)
    if modifiers == nil or modifiers == "" then return "" end
    if type(modifiers) ~= "string" then return nil end
    local have = {}
    for part in modifiers:upper():gmatch("[^%-%s%+]+") do
        if part ~= "SHIFT" and part ~= "CTRL" and part ~= "ALT" then return nil end
        have[part] = true
    end
    local out = {}
    for _, name in ipairs({ "SHIFT", "CTRL", "ALT" }) do
        if have[name] then out[#out + 1] = name end
    end
    return table.concat(out, "-")
end

-- Teil der Datenbank je Charakter: db[feld][charKey] (create: anlegen, wenn es ihn nicht gibt). stale(tabelle) →
-- true, wenn db[feld] noch im alten Format steht (wird beim Anlegen verworfen, beim Lesen übergangen).
local function CharStore(field, create, stale)
    local db = ns.db
    if type(db) ~= "table" then return nil end
    local all = db[field]
    if type(all) ~= "table" or (stale and stale(all)) then
        if not create then return nil end
        all = {}
        db[field] = all
    end
    local charKey = ns.charKey or Core.charKey or "?"
    local mine = all[charKey]
    if type(mine) ~= "table" then
        if not create then return nil end
        mine = {}
        all[charKey] = mine
    end
    return mine
end
T.CharStore = CharStore      -- auch für die Heil-Makros (Macros.lua: db.macros[charKey])

-- Eigene Tasten des Charakters: db.keys[charKey][vorlage][platz] = { Maustaste, Umschalttasten }
local function OwnStore(create)
    return CharStore("keys", create)
end

-- Was ezHeal auf diesem Charakter geschrieben hat (Fund H1; Blizzards Klick-Belegung gilt je Charakter):
--   db.applied[charKey] = { kind, class, count, time,
--     slots = { [platz] = { Maustaste, Umschalttasten, Zauber-ID } },   -- Belegungen, die ezHeal selbst schrieb
--     previous = slots vor dem letzten Schreiben }                     -- für „Zurück“ (wird getauscht)
-- Bis Welle 2b stand dort kontoweit nur { kind, class, count, time } ohne Tasten – dieses Format wird verworfen.
local function OldApplied(all) return all.kind ~= nil end
local function AppliedStore(create)
    return CharStore("applied", create, OldApplied)
end

-- Zuletzt übernommen (für den Status) → Tabelle des Charakters oder nil
function T.Applied()
    return AppliedStore(false)
end

-- Ein vergessener Charakter verliert auch seine Belegungs-Merkliste (Core.lua, CHAR_FORGOTTEN)
function T.ForgetApplied(charKey)
    local db = ns.db
    if type(db) == "table" and type(db.applied) == "table" and not OldApplied(db.applied) and charKey then
        db.applied[charKey] = nil
    end
end

-- Eigene Tasten gelten nur für die eigene Klasse (die Schnittstelle kann auch nach anderen Klassen fragen).
local function OwnClass(class)
    return class == nil or class == PlayerClass()
end

-- Taste eines Platzes → Maustaste, Umschalttasten, eigen (true = eigene Wahl statt Vorschlag)
function T.Key(slot, class)
    local default = T.SLOTS[slot]
    if not default then return nil end
    if OwnClass(class) then
        local mine = OwnStore(false)
        local part = mine and mine[T.PartOf(slot)]
        local own = type(part) == "table" and part[slot] or nil
        if type(own) == "table" then
            local mods = T.NormalizeModifiers(own[2])
            if Listed(T.BUTTONS, own[1]) and mods and Listed(T.MODIFIERS, mods) then
                return own[1], mods, not (own[1] == default[1] and mods == default[2])
            end
        end
    end
    return default[1], default[2], false
end

-- Taste eines Platzes wählen. Nur Daten (geschrieben wird erst beim Übernehmen), darum auch im Kampf erlaubt.
-- Gleich dem Vorschlag → der eigene Eintrag entfällt. → true | false, grund
function T.SetKey(slot, button, modifiers)
    local default = T.SLOTS[slot]
    if not default then return false, "slot" end
    local mods = T.NormalizeModifiers(modifiers)
    if not (Listed(T.BUTTONS, button) and mods and Listed(T.MODIFIERS, mods)) then return false, "invalid" end
    local mine = OwnStore(true)
    if not mine then return false, "nodb" end
    local partKey = T.PartOf(slot)
    local part = type(mine[partKey]) == "table" and mine[partKey] or {}
    mine[partKey] = part
    if button == default[1] and mods == default[2] then
        part[slot] = nil
    else
        part[slot] = { button, mods }
    end
    if next(part) == nil then mine[partKey] = nil end
    return true
end

-- Vorschlag wiederherstellen: eigene Tasten einer Vorlage verwerfen ("heal", "buffs"; "all" = beide) → Anzahl
function T.ResetKeys(kind)
    local mine = OwnStore(false)
    if not mine then return 0 end
    local count = 0
    for _, part in ipairs(kind == "all" and { "heal", "buffs" } or { kind }) do
        if type(mine[part]) == "table" then
            for _ in pairs(mine[part]) do count = count + 1 end
            mine[part] = nil
        end
    end
    return count
end

-- Weicht eine Taste der Vorlage vom Vorschlag ab?
function T.HasOwnKeys(kind, class)
    for slot in pairs(T.Slots(kind, class)) do
        if select(3, T.Key(slot, class)) then return true end
    end
    return false
end

-- Blizzards Selbstwirk-Taste (Core.ClickBindings.SelfCastKey; ab Werk Alt) → "ALT" … | nil (keine)
function T.SelfCastKey()
    local cb = CB()
    if not (cb and type(cb.SelfCastKey) == "function") then return nil end
    return cb.SelfCastKey()
end

-- Liegen die Umschalttasten auf der Selbstwirk-Taste? (Umschalt+Alt trifft Alt; Core.ClickBindings.HitsSelfCast)
-- selfKey: Selbstwirk-Taste (ohne Angabe T.SelfCastKey()). → selfKey | nil
function T.HitsSelfCast(modifiers, selfKey)
    local cb = CB()
    if not (cb and type(cb.HitsSelfCast) == "function") then return nil end
    if selfKey == nil then selfKey = T.SelfCastKey() end
    if not selfKey then return nil end
    return cb.HitsSelfCast(modifiers, selfKey)
end

-- Doppelbelegungen über alle Plätze der Klasse (Heilen und Buffs sollen nebeneinander liegen können), gegen
-- Blizzards „Ziel“ (Linksklick) und „Menü“ (Rechtsklick) ohne Umschalttaste und gegen Blizzards Selbstwirk-Taste
-- (ein Klick damit wirkt auf dich statt auf den Rahmen, Fehler des Nutzers vom 23.11.2026).
-- → { [platz] = { slots = { andere Plätze auf derselben Taste }, reserved = "target" | "menu" | nil,
--                 selfcast = Selbstwirk-Taste ("ALT" …) | nil } }
function T.Conflicts(class)
    local slots = T.Slots("all", class)
    local byKey, out = {}, {}
    local selfKey = T.SelfCastKey()
    for _, slot in ipairs(T.SLOT_ORDER) do
        if slots[slot] ~= nil then
            local button, mods = T.Key(slot, class)
            local id = button .. ":" .. mods
            byKey[id] = byKey[id] or {}
            table.insert(byKey[id], slot)
            if T.RESERVED[id] then out[slot] = { slots = {}, reserved = T.RESERVED[id] } end
            local hit = selfKey and T.HitsSelfCast(mods, selfKey)
            if hit then
                out[slot] = out[slot] or { slots = {} }
                out[slot].selfcast = hit
            end
        end
    end
    for _, list in pairs(byKey) do
        if #list > 1 then
            for _, slot in ipairs(list) do
                local conflict = out[slot] or { slots = {} }
                for _, other in ipairs(list) do
                    if other ~= slot then conflict.slots[#conflict.slots + 1] = other end
                end
                out[slot] = conflict
            end
        end
    end
    return out
end

-- Name eines Platzes für Meldungen: der erste Zauber der Vorlage („Seelenstärke“), sonst die Art des Platzes
function T.SlotLabel(slot, class)
    local value = T.Slots("all", class)[slot]
    local first = value ~= nil and Candidates(value)[1] or nil
    if first then return T.SpellName(first) end
    return Text("SLOT_" .. tostring(slot)) or L.SLOT_buff
end

-- Tastentexte kommen aus ezCore (Core.ClickBindings, EC-109: eine Stelle für ezMacro und ezHeal). T.KeyText,
-- T.ModifierText und T.ButtonText bleiben als Weiterleitung (Leitlinie 8); ezHeals eigene Fassung samt den Texten
-- MOD_*, BUTTON_*, ACTION_*, MACRO und OTHER ist entfernt.

-- Blizzards Interaktion „Ziel“ bzw. „Menü“ als Text (ezCores CLICK_ACTION_*)
local function ActionText(action)
    local cb = CB()
    if cb and cb.Describe then return cb.Describe({ kind = "interaction", action = action }) end
    return tostring(action)
end
T.ActionText = ActionText

-- Selbstwirk-Taste als Text: „Alt“ (Core.ClickBindings.ModifierText)
function T.SelfCastText(selfKey)
    return T.ModifierText(selfKey)
end

-- Grund einer Doppelbelegung als Text (oder nil)
function T.ConflictText(conflict, class)
    if type(conflict) ~= "table" then return nil end
    if conflict.reserved then return L.CONFLICT_RESERVED:format(ActionText(conflict.reserved)) end
    if conflict.selfcast then return L.CONFLICT_SELFCAST:format(T.SelfCastText(conflict.selfcast)) end
    local names = {}
    for _, other in ipairs(conflict.slots or {}) do names[#names + 1] = T.SlotLabel(other, class) end
    if #names == 0 then return nil end
    return L.CONFLICT_DOUBLE:format(table.concat(names, ", "))
end

-- Text einer Taste: „Umschalt + Strg + Linksklick“ (Core.ClickBindings.KeyText)
function T.KeyText(button, modifiers)
    local cb = CB()
    if cb and cb.KeyText then return cb.KeyText(button, modifiers) end
    return tostring(modifiers or "") .. " " .. tostring(button)
end

-- Kurzer Text der Umschalttasten für die Auswahlfelder: „Umschalt+Strg“, ohne Umschalttaste „keine“
-- (Core.ClickBindings.ModifierText)
function T.ModifierText(modifiers)
    local cb = CB()
    local text = cb and cb.ModifierText and cb.ModifierText(modifiers or "")
    return text or tostring(modifiers or "")
end

-- Text einer Maustaste: „Linksklick“, „Maustaste 4“ (Core.ClickBindings.ButtonText)
function T.ButtonText(button)
    local cb = CB()
    if cb and cb.ButtonText then return cb.ButtonText(button) end
    return tostring(button)
end

-- Was liegt heute auf einer Taste? → Text (Core.ClickBindings.Describe; Zaubernamen nennt ezHeal selbst, weil es für
-- die acht IDs, die ezCore noch nicht führt, Ersatznamen kennt). Kann ezCore den Eintrag nicht benennen (Begleiter-Aktion,
-- unbekannte Interaktion), sagt es nur „belegt“ – hinter „ersetzt:“ hieße das nichts; ezHeal nennt dann die Art.
local function Describe(entry)
    local cb = CB()
    local spellName = entry.kind == "spell" and entry.id and T.SpellName(entry.id) or nil
    local text = cb and cb.Describe and cb.Describe(entry, spellName) or spellName
    if text == nil or text == Core.L.CLICK_OTHER then
        return entry.kind == "pet" and L.BINDING_PET or L.BINDING_OTHER
    end
    return text
end

-- Wer hält eine Taste, bevor der Platz slot dorthin gelegt wird? (HL-14: Die Auswahlfelder der Vorschau
-- kennzeichnen belegte Kombinationen schon vor der Wahl.) Der Platz selbst zählt nicht.
--   opts.class    Klasse (ohne Angabe die eigene)
--   opts.current  aktuelle Belegung (CB.List()); ohne sie wird nur gegen die Plätze der Vorlagen geprüft
--   opts.spellID  Zauber des Platzes – liegt er (in irgendeinem Rang) schon auf der Taste, gilt sie als frei
-- → art, name:  "reserved"  Blizzards „Ziel“ bzw. „Menü“ (T.RESERVED) – sperrt das Übernehmen
--               "selfcast"  Blizzards Selbstwirk-Taste (name: „Alt“) – sperrt das Übernehmen (T.Conflicts)
--               "slot"      ein anderer Platz der Klasse liegt dort – sperrt das Übernehmen (T.Conflicts)
--               "bound"     in Blizzards Klick-Belegung liegt dort etwas anderes – würde beim Übernehmen ersetzt
--               nil         frei
function T.KeyUse(slot, button, modifiers, opts)
    opts = type(opts) == "table" and opts or {}
    local mods = T.NormalizeModifiers(modifiers)
    if not (Listed(T.BUTTONS, button) and mods) then return nil end
    local reserved = T.RESERVED[button .. ":" .. mods]
    if reserved then return "reserved", ActionText(reserved) end
    local selfKey = T.HitsSelfCast(mods)
    if selfKey then return "selfcast", T.SelfCastText(selfKey) end
    local slots = T.Slots("all", opts.class)
    for _, other in ipairs(T.SLOT_ORDER) do
        if other ~= slot and slots[other] ~= nil then
            local otherButton, otherMods = T.Key(other, opts.class)
            if otherButton == button and otherMods == mods then return "slot", T.SlotLabel(other, opts.class) end
        end
    end
    local cb = CB()
    local entry = cb and type(opts.current) == "table" and cb.Find(opts.current, button, mods) or nil
    if entry and not (entry.kind == "spell" and opts.spellID and T.SameSpell(entry.id, opts.spellID)) then
        return "bound", Describe(entry)
    end
    return nil
end

-- Zusatz hinter einer Taste der Auswahlfelder: „belegt: Großes Heilen“ bzw. „ersetzt: Makro …“ (oder nil)
function T.KeyUseText(use, name)
    if use == "selfcast" then return L.KEY_SELFCAST:format(tostring(name)) end
    if use == "reserved" or use == "slot" then return L.KEY_TAKEN:format(tostring(name)) end
    if use == "bound" then return L.REPLACES:format(tostring(name)) end
    return nil
end

-- Vorlage für den Spieler auflösen → Zeilen in fester Reihenfolge:
--   { slot, button, modifiers, key, own, conflict, spellID, name, rank,
--     state = "ok" | "unknown" | Grund aus CB.Spell, entry, replaces }
-- Tasten: eigene Wahl des Charakters, sonst der Vorschlag (T.Key); conflict = Grund einer Doppelbelegung (Text).
-- current: aktuelle Belegung (CB.List()) für „ersetzt“; ohne Angabe wird sie gelesen.
function T.Resolve(kind, class, current)
    local cb = CB()
    local slots = T.Slots(kind, class)
    local conflicts = T.Conflicts(class)
    if current == nil and cb and cb.Available() then current = cb.List() end
    local rows = {}
    for _, slot in ipairs(T.SLOT_ORDER) do
        local value = slots[slot]
        if value ~= nil then
            local button, modifiers, own = T.Key(slot, class)
            local candidates = Candidates(value)
            local chosen, rank
            for _, id in ipairs(candidates) do
                local maxID, maxRank = Core.Spells.Highest(id)
                if maxID then chosen, rank = maxID, maxRank break end
            end
            local row = { slot = slot, button = button, modifiers = modifiers, key = T.KeyText(button, modifiers),
                own = own, conflict = T.ConflictText(conflicts[slot], class),
                spellID = chosen or candidates[1], rank = rank, buff = type(value) == "string" and value or nil }
            row.name = row.spellID and T.SpellName(row.spellID) or "?"
            if not chosen then
                row.state = "unknown"
            elseif not cb then
                row.state = "missing"
            else
                local entry, reason = cb.Spell(chosen, button, modifiers)
                row.entry, row.state = entry, entry and "ok" or (reason or "invalid")
                if entry and type(current) == "table" then
                    -- Derselbe Zauber in anderem Rang ist kein „ersetzt“ (T.SameSpell, wie T.KeyUse und die
                    -- Merkliste): Die Zeile nennt den Rang, der geschrieben wird – sonst stünde „ersetzt:
                    -- Blitzheilung“ an der Zeile Blitzheilung, sobald ein neuer Rang gelernt ist.
                    local old = cb.Find(current, entry.button, entry.modifiers)
                    if old and not (old.kind == "spell" and T.SameSpell(old.id, chosen)) then row.replaces = Describe(old) end
                end
            end
            rows[#rows + 1] = row
        end
    end
    return rows
end

-- Erste doppelt belegte Zeile → Zeile oder nil (sperrt das Übernehmen)
function T.FirstConflict(rows)
    for _, row in ipairs(rows or {}) do
        if row.conflict then return row end
    end
    return nil
end

-- Eigene alte Belegungen, die beim Übernehmen entfernt werden (Fund H1): Hat ein Platz jetzt eine andere Taste als
-- beim letzten Übernehmen, läge der Zauber sonst auf alter und neuer Taste. Entfernt wird nur, was ezHeal selbst
-- geschrieben hat und was noch dort liegt: derselbe Zauber, auch in einem anderen Rang (T.SameSpell, HL-05 – ezMacros
-- „Ränge aktualisieren“ tauscht nur die ID) – fremde Belegungen (anderer Zauber, Makro, „Ziel“/„Menü“) nie. Plätze
-- ohne belegbaren Zauber und Tasten, die die Vorlage gleich wieder belegt, bleiben unberührt. spellID und name
-- nennen, was heute auf der alten Taste liegt.
-- rows: T.Resolve; current: aktuelle Belegung (CB.List()). → { { slot, button, modifiers, key, spellID, name } }
function T.Removals(rows, current)
    local out = {}
    local cb = CB()
    local mine = AppliedStore(false)
    local slots = mine and type(mine.slots) == "table" and mine.slots or nil
    if not (cb and slots and type(current) == "table") then return out end
    -- Taste samt ganzer Umschalt-Maske: ein toter Eintrag (nur das linke Umschalt-Bit, vor dem 15.11.2026 von ezCore
    -- geschrieben) gilt als dieselbe Taste wie der neue – ihn ersetzt das Übernehmen ohnehin (T4-NG4)
    local function UsedKey(button, modifiers)
        local mask = modifiers or 0
        if cb.FullMask then mask = cb.FullMask(mask) end
        return tostring(button) .. ":" .. tostring(mask)
    end
    local used = {}
    for _, row in ipairs(rows or {}) do
        if row.entry then used[UsedKey(row.entry.button, row.entry.modifiers)] = true end
    end
    for _, row in ipairs(rows or {}) do
        local old = slots[row.slot]
        if row.entry and type(old) == "table" then
            local entry = cb.Find(current, old[1], old[2])
            if entry and entry.kind == "spell" and T.SameSpell(entry.id, old[3])
                and not used[UsedKey(entry.button, entry.modifiers)] then
                out[#out + 1] = { slot = row.slot, button = old[1], modifiers = old[2], spellID = entry.id,
                    key = T.KeyText(old[1], old[2]), name = T.SpellName(entry.id) }
            end
        end
    end
    return out
end

-- Belegbare Einträge einer Vorlage (für ezMacro und die Schnittstelle) → Liste für ezCore.ClickBindings
function T.Entries(kind, class)
    local list = {}
    for _, row in ipairs(T.Resolve(kind, class)) do
        if row.entry then list[#list + 1] = row.entry end
    end
    return list
end

-- Vorschau als Zeilen: „Umschalt + Linksklick → Blitzheilung (Rang 7) – schnelle Heilung“
-- → zeilen, rows (T.Resolve), removals (T.Removals: eigene alte Tasten, die entfernt werden)
function T.PreviewLines(kind, class)
    class = class or PlayerClass()
    local cb = CB()
    local current
    if cb and cb.Available() then current = cb.List() end
    local rows = T.Resolve(kind, class, current)
    local removals = T.Removals(rows, current)
    local className = class and Core.ClassName(class) or class or "?"     -- Klassenname aus ezCore (HL-02)
    local lines = { L.PREVIEW_HEAD:format(ns.KindLabel(kind), className) }
    if #rows == 0 then
        lines[#lines + 1] = L.PREVIEW_NONE:format(ns.KindLabel(kind))
        -- Jäger: keine Klick-Vorlage, aber ein Makro für das Tier (Macros.lua)
        if not T.Has("all", class) and ns.Macros and ns.Macros.ForClass(class) then lines[#lines + 1] = L.PREVIEW_NONE_MACROS end
        return lines, rows, removals
    end
    local skipped = 0
    for _, row in ipairs(rows) do
        local spell = row.name
        if row.rank and row.rank > 0 then spell = spell .. " (" .. L.RANK:format(row.rank) .. ")" end
        local what = Text("SLOT_" .. row.slot) or L.SLOT_buff
        local line = row.key .. " " .. Core.ARROW .. " " .. spell .. " – " .. what
        if row.own then line = line .. " (" .. L.OWN_KEY .. ")" end
        if row.conflict then line = line .. " [" .. row.conflict .. "]" end
        if row.state ~= "ok" then
            skipped = skipped + 1
            line = line .. " [" .. (Text("STATE_" .. row.state) or row.state) .. "]"
        elseif row.replaces then
            line = line .. " (" .. L.REPLACES:format(row.replaces) .. ")"
        end
        lines[#lines + 1] = line
    end
    for _, gone in ipairs(removals) do lines[#lines + 1] = L.PREVIEW_REMOVE:format(gone.key, gone.name) end
    if skipped > 0 then lines[#lines + 1] = L.PREVIEW_SKIP:format(skipped) end
    if T.FirstConflict(rows) then lines[#lines + 1] = L.ERR_conflict end
    lines[#lines + 1] = L.PREVIEW_KEEP
    -- Blizzards „Selbstwirken: Automatisch“: außer Reichweite wirkt das Spiel auf dein Ziel bzw. dich (Core.lua)
    local selfHint = ns.AutoSelfCastHint and ns.AutoSelfCastHint()
    if selfHint then lines[#lines + 1] = selfHint end
    for _, hint in ipairs(ns.OtherHints()) do lines[#lines + 1] = hint end
    return lines, rows, removals
end

-- Klick-Belegung in Blizzards offenem Fenster neu zeigen: Es liest die Belegung beim Öffnen
-- (ClickBindingFrameMixin:OnShow → Refresh); ein offenes Fenster mit altem Stand könnte sie sonst beim Speichern
-- zurückschreiben. Das erledigt seit dem Gesamtreview vom 18.11.2026 (T4-NG2) ezCore nach jedem Schreiben selbst
-- (Core.ClickBindings.Reload, auch für ezMacro und das Nachholen nach dem Kampf); T.ReopenBlizzard leitet nur noch
-- dorthin weiter (Schnittstelle bleibt). → wie Core.ClickBindings.Reload
local function ReopenBlizzard(quiet)
    local cb = CB()
    if not (cb and cb.Reload) then return false, "missing" end
    return cb.Reload(quiet)
end

-- Vorlage übernehmen: in die aktuelle Belegung einfügen (gleiche Taste wird ersetzt, alles andere bleibt), dann
-- über ezCore schreiben – ezCore sichert die alte Belegung. Nur außerhalb des Kampfes.
-- → true, anzahl | true, "same" | false, grund
function T.Apply(kind, opts)
    opts = type(opts) == "table" and opts or {}
    local cb = CB()
    if not (cb and cb.Writable()) then return false, "missing" end
    if Core.InCombat() then return false, "combat" end
    local list, complete = cb.List()
    if not list then return false, complete or "error" end
    if complete == false then return false, "unreadable" end
    local rows = T.Resolve(kind, opts.class, list)
    if T.FirstConflict(rows) then return false, "conflict" end
    -- eigene alte Tasten zuerst entfernen (Fund H1; dieselben, die Vorschau und Rückfrage nennen)
    local removals = T.Removals(rows, list)
    for _, gone in ipairs(removals) do cb.Remove(list, gone.button, gone.modifiers) end
    local mine = AppliedStore(false)
    local before = mine and type(mine.slots) == "table" and mine.slots or {}
    local ours, count = {}, 0
    for _, row in ipairs(rows) do
        if row.entry then
            -- Lag genau dieser Zauber schon auf der Taste, hat ezHeal ihn nicht geschrieben – außer er stammt
            -- nachweislich vom letzten Übernehmen (derselbe Zauber auf derselben Taste; der Rang darf inzwischen ein
            -- anderer sein, HL-05: sonst verlöre die Merkliste die Taste, sobald ezMacro den Rang getauscht hat).
            -- Nur Eigenes kommt in die Merkliste (fremdes wird nie entfernt).
            -- Ein toter Eintrag (cb.Dead: nur das linke Umschalt-Bit, so schrieb ezCore vor dem 15.11.2026) wirkte nie
            -- und stammt von ezCore: Er zählt nicht als „lag schon da“, das Übernehmen ersetzt ihn (T4-NG4).
            local old = cb.Find(list, row.entry.button, row.entry.modifiers)
            local had = old ~= nil and old.kind == "spell" and old.id == row.entry.id and not (cb.Dead and cb.Dead(old))
            local prev = before[row.slot]
            local again = type(prev) == "table" and T.SameSpell(prev[3], row.entry.id) and prev[1] == row.button
                and T.NormalizeModifiers(prev[2]) == row.modifiers
            if not had or again then ours[row.slot] = { row.button, row.modifiers, row.entry.id } end
            cb.Put(list, row.entry)
            count = count + 1
        end
    end
    if count == 0 then return false, "empty" end
    -- keepDefaults = false (Fund H2): geschrieben wird genau die Liste, die die Vorschau beschreibt. ezCores
    -- KeepDefaults legte sonst „Ziel“/„Menü“ still zurück, wenn sie fehlten oder verlegt waren, und verdrängte dabei
    -- eine Heilung oder eine eigene Belegung, ohne dass die Vorschau es sagte. „Ziel“ und „Menü“ bleiben trotzdem: Die
    -- Liste ist die jetzige Belegung, nur die Tasten der Vorlage werden ersetzt – und blanker Links-/Rechtsklick ist
    -- für die Vorlage gesperrt (T.RESERVED).
    local ok, reason, detail = cb.Set(list, { owner = ADDON, checkSpells = true, quiet = opts.quiet, keepDefaults = false })
    if not ok then return false, reason end
    -- was ezCore ausließ (checkSpells), hat ezHeal nicht geschrieben
    for _, entry in ipairs(type(detail) == "table" and detail.skipped or {}) do
        for _, row in ipairs(rows) do
            if row.entry and row.entry.button == entry.button and row.entry.modifiers == entry.modifiers then
                ours[row.slot] = nil
            end
        end
    end
    local store = AppliedStore(true)
    if store then
        local slots = {}
        for slot, record in pairs(type(store.slots) == "table" and store.slots or {}) do slots[slot] = record end
        for _, gone in ipairs(removals) do slots[gone.slot] = nil end
        for _, row in ipairs(rows) do
            if row.entry then slots[row.slot] = ours[row.slot] end
        end
        -- Nur ein echter Schreibvorgang legt bei ezCore eine neue Sicherung an – dann auch hier den Stand davor merken.
        -- Die Sicherung „last“ stammt jetzt von ezHeal: „Zurück“ tauscht die Merkliste wieder mit (HL-06).
        if reason ~= "same" then store.previous, store.foreign = store.slots, nil end
        store.slots = slots
        store.kind, store.class, store.count, store.time = kind, opts.class or PlayerClass(), count, Core.Now()
        store.lastMacro, store.lastRanks = nil, nil
    end
    -- Blizzards offenes Fenster lädt ezCore nach dem Schreiben selbst neu (Core.ClickBindings.Reload, T4-NG2)
    if reason == "same" then return true, "same" end
    return true, count
end

-- T.AssignMacro (ein Makro auf eine Taste legen, für ezMacros Knopf „Klick-Zauber“) ist seit dem 23.11.2026 weg: Der
-- Knopf öffnet Blizzards Fenster „Klick-Zauber“ und schreibt nicht mehr selbst (Entscheidung des Nutzers „menü weg wenn
-- verhalten gleich bleibt“, docs/roadmap/ezMacro.md). store.lastMacro aus älteren Ständen räumen T.Apply, T.Restore,
-- T.ReplaceSpells und T.ProfileLoaded weiter ab.

-- Ränge tauschen (Paket ezmacro/rangtausch-ezheal; Folgepunkt aus PR 570): ezMacros „Ränge aktualisieren“ tauscht in
-- Blizzards Klick-Belegung nur Zauber-IDs (alter Rang → höchster Rang). Auch das schreibt der eine Besitzer ezHeal
-- (Entscheidung des Nutzers vom 13.11.2026: „ezHeal bleibt die Klick-Schicht“), damit Merkliste und „Zurück“ den Tausch
-- kennen. Wie T.Apply: nur außerhalb des Kampfes, ezCore sichert die alte Belegung, Blizzards Standard wird nicht ergänzt
-- (keepDefaults = false), alles andere bleibt. Getauscht wird nur, wo auf der Taste noch genau der alte Rang liegt.
-- changes: { { button, modifiers, id = alte ID, newID } } (Taste und Umschalttasten wie in ezCores CB.List).
-- Die Merkliste behält ihre Tasten und bekommt die neue ID; opts.via nennt das Modul für die Rückfrage zu „Zurück“
-- (store.lastRanks, gelöscht von T.Apply, T.Restore und T.ProfileLoaded). → true, anzahl | true, "same" | false, grund
function T.ReplaceSpells(changes, opts)
    opts = type(opts) == "table" and opts or {}
    local cb = CB()
    if not (cb and cb.Writable()) then return false, "missing" end
    if Core.InCombat() then return false, "combat" end
    if type(changes) ~= "table" then return false, "invalid" end
    local list, complete = cb.List()
    if not list then return false, complete or "error" end
    if complete == false then return false, "unreadable" end
    local swapped, count = {}, 0
    for _, change in ipairs(changes) do
        local valid = type(change) == "table" and not Core.IsSecret(change)
        local id, newID = valid and change.id, valid and change.newID
        if type(id) == "number" and type(newID) == "number" and not Core.IsSecret(id) and not Core.IsSecret(newID)
            and not Core.IsSecret(change.button) and not Core.IsSecret(change.modifiers) and id ~= newID then
            local entry = cb.Find(list, change.button, change.modifiers)
            if entry and entry.kind == "spell" and entry.id == id and not swapped[entry] then
                entry.id = newID
                swapped[entry] = id
                count = count + 1
            end
        end
    end
    if count == 0 then return true, "same" end
    local ok, reason = cb.Set(list, { owner = ADDON, keepDefaults = false, quiet = opts.quiet })
    if not ok then return false, reason end
    -- Merkliste: eigene Tasten mit dem getauschten Zauber bekommen die neue ID (neue Tabellen – previous teilt die alten)
    local store = AppliedStore(false)
    local before = store and type(store.slots) == "table" and store.slots or nil
    if before then
        local slots = {}
        for slot, record in pairs(before) do
            local entry = type(record) == "table" and cb.Find(list, record[1], record[2]) or nil
            if entry and swapped[entry] and T.SameSpell(record[3], swapped[entry]) then
                slots[slot] = { record[1], record[2], entry.id }
            else
                slots[slot] = record
            end
        end
        store.slots = slots
    end
    if reason == "same" then return true, "same" end
    store = store or AppliedStore(true)
    if store then
        -- die Sicherung „last“ stammt jetzt von ezHeal: „Zurück“ tauscht die Merkliste mit (HL-06)
        store.previous, store.foreign, store.lastMacro = before, nil, nil
        store.lastRanks = { count = count, via = type(opts.via) == "string" and opts.via or nil }
    end
    return true, count
end

-- Wer hat die Sicherung „last“ ausgelöst? (HL-06; ezCore merkt den Urheber, EC-115) → "own" | "other", name | "unknown"
--   "own"      ezHeal selbst (Übernehmen, Zurück, Profil laden) – „Zurück“ tauscht die Merkliste mit
--   "other"    ein anderes Modul (ezMacro „Ränge aktualisieren“ …) – „Zurück“ stellt dessen Stand davor her
--   "unknown"  Sicherung ohne Urheber (vor ezCore 1.12.0 angelegt)
-- Hat ezHeal zuletzt eine fremde Sicherung zurückgeschrieben (store.foreign), gilt auch seine eigene folgende
-- Sicherung als fremd: Sie enthält den Stand nach dem fremden Schreiben, nicht ezHeals Übernehmen.
function T.LastWriter()
    local cb = CB()
    local backup = cb and cb.Backup and cb.Backup("last")
    if type(backup) ~= "table" then return nil end
    local owner = backup.owner
    if type(owner) ~= "string" or Core.IsSecret(owner) or owner == "" then return "unknown" end
    if owner ~= ADDON then return "other", owner end
    local store = AppliedStore(false)
    local foreign = store and store.foreign
    if type(foreign) == "string" then return "other", foreign end
    if foreign then return "unknown" end
    return "own"
end

-- Sicherung wiederherstellen: "last" (Standard) = von vor dem letzten Schreiben (ezCore: die jetzige wird dabei
-- „last“, ein zweites „Zurück“ macht es rückgängig); "first" = von vor dem allerersten Schreiben über ezCore auf
-- diesem Charakter (ezCore überschreibt sie nie). → true | true, "same" | false, grund
function T.Restore(which)
    which = which == "first" and "first" or "last"
    local cb = CB()
    if not (cb and cb.Writable()) then return false, "missing" end
    if Core.InCombat() then return false, "combat" end
    if not cb.Backup(which) then return false, "nobackup" end
    local writer, writerName = T.LastWriter()
    local ok, reason = cb.Restore(which, { owner = ADDON })
    if not ok then return false, reason end
    -- Merkliste mitführen: „Zurück“ tauscht sie mit dem Stand davor – aber nur, wenn die Sicherung von ezHeal stammt
    -- (HL-06). Hat ein anderes Modul dazwischen geschrieben, stellt „Zurück“ dessen Stand davor her; ezHeals Tasten
    -- liegen dann unverändert, und die Merkliste bleibt, wie sie ist (store.foreign merkt das für das nächste „Zurück“).
    -- Vor dem ersten Übernehmen gab es nichts Eigenes (der jetzige Stand wird „davor“, damit ein folgendes „Zurück“
    -- ihn wiederbringt). Ob eine gemerkte Belegung noch liegt, prüft T.Removals ohnehin vor jedem Entfernen.
    local store = AppliedStore(false)
    if store and reason ~= "same" then
        store.lastMacro, store.lastRanks = nil, nil
        if which == "first" then
            store.previous, store.slots, store.foreign = store.slots, nil, nil
        elseif writer == "own" then
            store.slots, store.previous = store.previous, store.slots
        else
            store.foreign = writer == "other" and writerName or true   -- Name des Moduls, true = unbekannt
        end
    end
    return true, reason
end

-- Nach dem Laden eines benannten Profils (Profiles.lua): Was dort liegt, hat ezHeal nicht als Vorlage geschrieben –
-- die Merkliste wird „davor“, damit „Zurück“ (Sicherung von ezHeal) sie wiederbringt.
function T.ProfileLoaded()
    local store = AppliedStore(false)
    if store then
        store.previous, store.slots, store.foreign, store.lastMacro, store.lastRanks = store.slots, nil, nil, nil, nil
    end
end
T.ReopenBlizzard = ReopenBlizzard
T.Describe = Describe

-- „Menü“ und „Ziel“ zurückgeholt (MenuClick.lua): ezHeals Tasten bleiben, die Sicherung „last“ stammt jetzt von ezHeal –
-- „Zurück“ tauscht die Merkliste, darum steht davor dieselbe.
function T.DefaultsRestored()
    local store = AppliedStore(false)
    if store then
        store.previous = type(store.slots) == "table" and Core.CopyTable(store.slots) or nil
        store.foreign, store.lastMacro, store.lastRanks = nil, nil, nil
    end
end

---------------------------------------------------------------------------
-- Sichtbare Wege (Einstellungen, Knopf am Klick-Zauber-Fenster, Befehle)
---------------------------------------------------------------------------

local function Chosen(kind)
    kind = kind or (ns.S and ns.S.template) or "heal"
    if kind ~= "heal" and kind ~= "buffs" and kind ~= "all" then kind = "heal" end
    return kind
end
ns.ChosenKind = Chosen

local function Explain(reason)
    if reason == "combat" then return ns.CombatText(L.APPLY_COMBAT_WHAT) end   -- ezCores Wortlaut (T18-1)
    return Text("ERR_" .. tostring(reason)) or L.ERR_other:format(tostring(reason))
end
ns.Explain = Explain

function ns.PrintPreview(kind)
    for _, line in ipairs((T.PreviewLines(Chosen(kind)))) do ns.Print(line) end
end

function ns.AskApply(kind)
    kind = Chosen(kind)
    if Core.InCombat() then ns.CombatNotice(L.APPLY_COMBAT_WHAT) return false end
    local cb = CB()
    if not (cb and cb.Writable()) then ns.Print(L.ERR_missing) return false end
    local lines, rows = T.PreviewLines(kind)
    local usable = 0
    for _, row in ipairs(rows) do if row.entry then usable = usable + 1 end end
    if usable == 0 then
        ns.Print(#rows == 0 and L.PREVIEW_NONE:format(ns.KindLabel(kind)) or L.ERR_empty)
        return false
    end
    local bad = T.FirstConflict(rows)
    if bad then
        ns.Print(L.ERR_conflict)
        ns.Print(bad.key .. " – " .. bad.conflict)
        return false
    end
    table.remove(lines, 1)   -- Kopfzeile steht schon in der Frage
    Core.Confirm(L.ASK_APPLY:format(ns.KindLabel(kind), table.concat(lines, "\n")), function() ns.ApplyNow(kind) end)
    return true
end

function ns.ApplyNow(kind)
    kind = Chosen(kind)
    local ok, result = T.Apply(kind)
    if ok then
        ns.Print(result == "same" and L.APPLIED_SAME:format(ns.KindLabel(kind)) or L.APPLIED:format(ns.KindLabel(kind), result))
        local clique = ns.ClickCaster()
        if clique then ns.Print(L.CLIQUE_HINT:format(clique, clique)) end
    else
        ns.Print(Explain(result))
    end
    return ok, result
end

-- which: "last" (Standard, „Zurück“) oder "first" („Belegung vor dem ersten Übernehmen“)
function ns.AskRestore(which)
    which = which == "first" and "first" or "last"
    if Core.InCombat() then ns.CombatNotice(L.APPLY_COMBAT_WHAT) return false end
    local cb = CB()
    if not (cb and cb.Writable()) then ns.Print(L.ERR_missing) return false end
    if not cb.Backup(which) then ns.Print(L.ERR_nobackup) return false end
    Core.Confirm(T.RestorePrompt(which), function() ns.RestoreNow(which) end)
    return true
end

-- Text der Rückfrage zu „Zurück“: Stammt die Sicherung nicht von ezHeal, sagt sie, wer zuletzt geschrieben hat und
-- dass die Merkliste bleibt (HL-06).
function T.RestorePrompt(which)
    if which == "first" then return L.ASK_RESTORE_FIRST end
    local writer, name = T.LastWriter()
    if writer == "other" then return L.ASK_RESTORE .. "\n\n" .. L.RESTORE_OTHER:format(tostring(name)) end
    if writer == "unknown" then return L.ASK_RESTORE .. "\n\n" .. L.RESTORE_UNKNOWN end
    local store = AppliedStore(false)
    -- zuletzt Ränge getauscht (T.ReplaceSpells, ezMacros „Ränge aktualisieren“)
    local ranks = store and store.lastRanks
    if type(ranks) == "table" and type(ranks.count) == "number" then
        return L.ASK_RESTORE .. "\n\n" .. L.RESTORE_RANKS:format(ranks.count, ranks.via or ADDON)
    end
    return L.ASK_RESTORE
end

function ns.RestoreNow(which)
    which = which == "first" and "first" or "last"
    local ok, reason = T.Restore(which)
    ns.Print(ok and (which == "first" and L.RESTORED_FIRST or L.RESTORED) or Explain(reason))
    return ok, reason
end

---------------------------------------------------------------------------
-- Schnittstelle für andere Module: ezCore.API("ezHeal") (ezMacro, ezBuff)
---------------------------------------------------------------------------

local function CopyRow(row)
    return { slot = row.slot, button = row.button, modifiers = row.modifiers, key = row.key, spellID = row.spellID,
        name = row.name, rank = row.rank, state = row.state, buff = row.buff, replaces = row.replaces,
        own = row.own, conflict = row.conflict }
end

ns.API = {
    -- Vorlagen-Arten, die es für eine Klasse gibt → { { kind, label, slots } }
    Templates = function(class)
        local out = {}
        for _, kind in ipairs(T.KINDS) do
            local count = 0
            for _ in pairs(T.Slots(kind, class)) do count = count + 1 end
            if count > 0 then out[#out + 1] = { kind = kind, label = ns.KindLabel(kind), slots = count } end
        end
        return out
    end,
    -- Belegung einer Vorlage, aufgelöst für den Spieler → Zeilen (Kopie; Tasten mit der eigenen Wahl des Charakters,
    -- own = eigene Taste, conflict = Grund einer Doppelbelegung)
    Template = function(kind, class)
        local out = {}
        for _, row in ipairs(T.Resolve(kind, class)) do out[#out + 1] = CopyRow(row) end
        return out
    end,
    -- Einträge für ezCore.ClickBindings (z. B. als Grundlage einer eigenen Vorlage in ezMacro)
    Entries = function(kind, class) return T.Entries(kind, class) end,
    -- Vorschau als Textzeilen
    Preview = function(kind, class) return (T.PreviewLines(kind, class)) end,
    -- Anwenden ohne Rückfrage (der Aufrufer fragt selbst) → wie ezHeal: true, anzahl | true, "same" | false, grund
    -- (mit den eigenen Tasten; bei einer Doppelbelegung false, "conflict")
    Apply = function(kind, opts) return T.Apply(kind, opts) end,
    -- Ränge tauschen, ohne Rückfrage (ezMacros „Ränge aktualisieren“): { { button, modifiers, id, newID } } →
    -- true, anzahl | true, "same" | false, grund. Nur, wo noch der alte Rang liegt; die Merkliste geht mit.
    ReplaceSpells = function(changes, opts) return T.ReplaceSpells(changes, opts) end,
    -- Belegung vor dem letzten Schreiben wiederherstellen ("last", Standard) oder vor dem ersten ("first")
    Restore = function(which) return T.Restore(which) end,
    -- Tasten der Vorlagen, wie sie gelten (eigene Wahl des Charakters, sonst Vorschlag):
    -- { [platz] = { Maustaste, Umschalttasten } } (Kopie); class: andere Klasse → nur der Vorschlag
    Slots = function(class)
        local out = {}
        for slot in pairs(T.SLOTS) do
            local button, mods = T.Key(slot, class)
            out[slot] = { button, mods }
        end
        return out
    end,
    -- Vorschlag ab Werk (ohne eigene Wahl): { [platz] = { Maustaste, Umschalttasten } } (Kopie)
    SuggestedSlots = function() return Core.CopyTable(T.SLOTS) end,
}

-- /ez test: Kennt der Client jede Zauber-ID der Vorlagen? (optional – eine fehlende ID lässt nur die Taste frei)
if Core.AddSelfTest then
    Core.AddSelfTest(ADDON, function()
        local out = {}
        for _, id in ipairs(T.AllSpellIDs()) do
            local there = Core.Spells.Exists and Core.Spells.Exists(id)
            out[#out + 1] = { kind = "spell", name = T.SpellName(id) .. " (" .. id .. ")", there = there ~= false, optional = true }
        end
        return out
    end)
end
