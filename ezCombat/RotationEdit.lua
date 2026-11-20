local _, ns = ...
local Core = ezCore
local Rotation = ns.Rotation
local State = ns.RotationState

-- Anpassungen der Rotation je Charakter (Wunsch des Nutzers, 13.11.2026: die Vorlagen „müssen auch angezeigt
-- werden, als grundlage dienen und ggf anpassbar“). Die Vorlage in RotationData/<KLASSE>.lua bleibt unberührt;
-- gemerkt wird nur, was der Nutzer ändert:
--   ezCombatDB.rotationEdits[Charakter]["KLASSE:Rotationsschlüssel"] = {
--       off = { [Schritt-Schlüssel] = true },      ausgeschaltete Schritte
--       on = { [Schritt-Schlüssel] = true },       eingeschaltete optionale Schritte (optional = true in der Vorlage)
--       order = { Schritt-Schlüssel, … },          eigene Reihenfolge (alle Schlüssel der wirksamen Liste)
--   }
-- Ein Eintrag entfällt, sobald er der Vorlage entspricht. Schritt-Schlüssel: Rotation.StepKey (Feld key, sonst Art
-- und Zauber-ID; Volksfähigkeiten "racial:<ID>"). Bekommt die Vorlage später einen neuen Schritt, steht er hinter
-- seinem Vorgänger aus der Vorlage; Schlüssel, die es nicht mehr gibt, werden übergangen.
-- Die Knöpfe dazu (Ein/Aus, Hoch/Runter, „Zurück zur Vorlage“) gehören zum Reiter am Zauberbuch; „Zurück zur
-- Vorlage“ steht außerdem auf der Einstellungsseite.
-- Der Schlüssel trägt die Klasse („PRIEST:holy“): „holy“, „protection“, „restoration“ gibt es in mehreren Klassen,
-- sonst meldete die Schnittstelle die gleichnamige Rotation einer fremden Klasse als angepasst. Ältere Einträge nur
-- unter dem Rotationsschlüssel gehören zur eigenen Klasse und ziehen beim ersten Lesen um.

local function CharKey() return Core.charKey or "?" end

-- Klasse einer Rotation (über ns.ROTATIONS, zwischengespeichert); unbekannt: die eigene.
local classCache, classCacheFor = setmetatable({}, { __mode = "k" }), nil
local function ClassOf(rotation)
    -- eigene Rotation (RotationOwn.lua): trägt ihre Klasse selbst
    if Rotation.IsOwn(rotation) then return rotation.class or ns.playerClass or "?" end
    if classCacheFor ~= ns.ROTATIONS then
        classCache, classCacheFor = setmetatable({}, { __mode = "k" }), ns.ROTATIONS
    end
    local class = classCache[rotation]
    if class then return class end
    for name, list in pairs(ns.ROTATIONS or {}) do
        if name ~= "RACIAL" and type(list) == "table" then
            for _, one in ipairs(list) do
                if one == rotation then class = name end
            end
        end
    end
    class = class or ns.playerClass or "?"
    classCache[rotation] = class
    return class
end
Rotation.ClassOf = ClassOf

-- Schlüssel einer Rotation in den Anpassungen: "KLASSE:Rotationsschlüssel".
local function EditKey(rotation)
    return tostring(ClassOf(rotation)) .. ":" .. tostring(rotation.key)
end
Rotation.EditKey = EditKey

-- Gemerkte Anpassungen einer Rotation; create = true legt den Eintrag an.
local function Edits(rotation, create)
    local key = rotation and rotation.key
    local db = ns.db
    if key == nil or type(db) ~= "table" then return nil end
    if type(db.rotationEdits) ~= "table" then
        if not create then return nil end
        db.rotationEdits = {}
    end
    local char = db.rotationEdits[CharKey()]
    if type(char) ~= "table" then
        if not create then return nil end
        char = {}
        db.rotationEdits[CharKey()] = char
    end
    local editKey = EditKey(rotation)
    if type(char[editKey]) ~= "table" then
        -- alter Eintrag (nur der Rotationsschlüssel) der eigenen Klasse: umziehen
        if type(char[key]) == "table" and ClassOf(rotation) == ns.playerClass then
            char[editKey], char[key] = char[key], nil
        elseif not create then
            return nil
        else
            char[editKey] = {}
        end
    end
    return char[editKey]
end

-- Leere Teile und leere Einträge entfernen (dann gilt wieder die Vorlage).
local function Tidy(rotation)
    local db = ns.db
    local char = type(db) == "table" and type(db.rotationEdits) == "table" and db.rotationEdits[CharKey()]
    if type(char) ~= "table" then return end
    local editKey = EditKey(rotation)
    local edits = char[editKey]
    if type(edits) == "table" then
        for _, field in ipairs({ "off", "on", "order" }) do
            if type(edits[field]) ~= "table" or next(edits[field]) == nil then edits[field] = nil end
        end
        if next(edits) == nil then char[editKey] = nil end
    end
    if next(char) == nil then db.rotationEdits[CharKey()] = nil end
end

local function Changed(rotation)
    Tidy(rotation)
    State.Reset("all")
    ns.Try("Rotation", Rotation.Update)     -- ein Fehler hält die Zuhörer nicht auf (T7-NE2)
    for _, fn in ipairs(Rotation.listeners) do pcall(fn) end
end

local function TemplateKeys(rotation)
    local keys, steps = {}, {}
    for index, step in ipairs(Rotation.Template(rotation)) do
        local key = Rotation.StepKey(step)
        keys[index] = key
        steps[key] = steps[key] or step
    end
    return keys, steps
end

---------------------------------------------------------------------------
-- Ein und aus
---------------------------------------------------------------------------

-- Wird der Schritt bewertet? false, wenn der Nutzer ihn ausgeschaltet hat, oder wenn er in der Vorlage optional
-- ist und nicht eingeschaltet wurde. Ohne Rotation (einzelner Schritt) gilt nur die Vorlage.
function Rotation.StepEnabled(rotation, step)
    local key = Rotation.StepKey(step)
    local edits = rotation and Edits(rotation, false)
    if edits then
        if type(edits.off) == "table" and edits.off[key] then return false end
        if step.optional then return type(edits.on) == "table" and edits.on[key] == true end
        return true
    end
    return step.optional ~= true
end

-- Schritt ein- oder ausschalten; der Eintrag entfällt, wenn er der Vorlage entspricht. → true, wenn geändert
function Rotation.SetStepEnabled(rotation, step, on)
    if not (rotation and step) then return false end
    on = on and true or false
    if Rotation.StepEnabled(rotation, step) == on then return false end
    local edits = Edits(rotation, true)
    if not edits then return false end
    local key = Rotation.StepKey(step)
    edits.off = type(edits.off) == "table" and edits.off or {}
    edits.on = type(edits.on) == "table" and edits.on or {}
    if step.optional then
        edits.on[key] = on or nil
        edits.off[key] = nil
    else
        edits.off[key] = (not on) or nil
        edits.on[key] = nil
    end
    Changed(rotation)
    return true
end

---------------------------------------------------------------------------
-- Reihenfolge
---------------------------------------------------------------------------

-- Wirksame Reihenfolge der Schritt-Schlüssel: die gemerkte, gefiltert auf Schlüssel der Vorlage; neue Schritte der
-- Vorlage direkt hinter ihrem Vorgänger aus der Vorlage.
function Rotation.Order(rotation)
    local keys, steps = TemplateKeys(rotation)
    local edits = Edits(rotation, false)
    local saved = edits and edits.order
    if type(saved) ~= "table" then return keys end
    local order, placed = {}, {}
    for _, key in ipairs(saved) do
        if steps[key] and not placed[key] then
            placed[key] = true
            order[#order + 1] = key
        end
    end
    for index, key in ipairs(keys) do
        if not placed[key] then
            local at = 1
            local before = keys[index - 1]
            if before then
                for position, other in ipairs(order) do
                    if other == before then at = position + 1 break end
                end
            end
            table.insert(order, at, key)
            placed[key] = true
        end
    end
    return order
end

-- Schritte der Vorlage in der wirksamen Reihenfolge (gerufen von Rotation.Steps).
function Rotation.ApplyOrder(rotation, template)
    local edits = rotation and Edits(rotation, false)
    if not (edits and type(edits.order) == "table") then return template end
    local byKey = {}
    for _, step in ipairs(template) do
        local key = Rotation.StepKey(step)
        byKey[key] = byKey[key] or step
    end
    local steps, used = {}, {}
    for _, key in ipairs(Rotation.Order(rotation)) do
        local step = byKey[key]
        if step and not used[step] then
            used[step] = true
            steps[#steps + 1] = step
        end
    end
    -- Schritte, die die gemerkte Reihenfolge nicht kennt (anderes Volk, doppelter Schlüssel), behalten ihren Platz am Ende.
    for _, step in ipairs(template) do
        if not used[step] then steps[#steps + 1] = step end
    end
    return steps
end

local function SameList(a, b)
    if #a ~= #b then return false end
    for index = 1, #a do
        if a[index] ~= b[index] then return false end
    end
    return true
end

-- Schritt eine Stelle nach oben (-1) oder unten (+1): tauscht den Platz mit dem nächsten Schritt desselben
-- Abschnitts in der wirksamen Reihenfolge. false am Rand des Abschnitts.
function Rotation.MoveStep(rotation, step, direction)
    if not (rotation and step) or (direction ~= -1 and direction ~= 1) then return false end
    local keys, steps = TemplateKeys(rotation)
    local order = Rotation.Order(rotation)
    local key = Rotation.StepKey(step)
    local from
    for index, other in ipairs(order) do
        if other == key then from = index break end
    end
    if not from then return false end
    local section = Rotation.SectionOf(step)
    local to
    local index = from + direction
    while order[index] do
        local other = steps[order[index]]
        if other and Rotation.SectionOf(other) == section then to = index break end
        index = index + direction
    end
    if not to then return false end
    order[from], order[to] = order[to], order[from]
    local edits = Edits(rotation, true)
    if not edits then return false end
    edits.order = (not SameList(order, keys)) and order or nil
    Changed(rotation)
    return true
end

---------------------------------------------------------------------------
-- Vorlage oder angepasst?
---------------------------------------------------------------------------

-- Zahl der Abweichungen von der Vorlage: aus- bzw. eingeschaltete Schritte und verschobene Plätze (ein Tausch
-- zweier Nachbarn zählt als eine).
function Rotation.EditCount(rotation)
    local edits = rotation and Edits(rotation, false)
    if not edits then return 0 end
    local keys, steps = TemplateKeys(rotation)
    local count = 0
    for _, field in ipairs({ "off", "on" }) do
        for key in pairs(type(edits[field]) == "table" and edits[field] or {}) do
            if steps[key] then count = count + 1 end
        end
    end
    if type(edits.order) == "table" then
        local order, moved = Rotation.Order(rotation), 0
        for index, key in ipairs(keys) do
            if order[index] ~= key then moved = moved + 1 end
        end
        count = count + math.ceil(moved / 2)
    end
    return count
end

function Rotation.IsEdited(rotation)
    return Rotation.EditCount(rotation) > 0
end

-- Einen Schritt-Schlüssel aus den Anpassungen streichen (Ein/Aus und Platz in der Reihenfolge) – für einen Schritt,
-- den es nicht mehr gibt (eigene Rotation: selbst hinzugefügter Schritt entfernt). Sonst erbte ein späterer Schritt
-- mit demselben Schlüssel dessen Zustand. → true, wenn etwas gestrichen wurde
function Rotation.ForgetStepEdits(rotation, stepKey)
    local edits = rotation and stepKey ~= nil and Edits(rotation, false)
    if not edits then return false end
    local changed = false
    for _, field in ipairs({ "off", "on" }) do
        if type(edits[field]) == "table" and edits[field][stepKey] ~= nil then
            edits[field][stepKey] = nil
            changed = true
        end
    end
    if type(edits.order) == "table" then
        for index = #edits.order, 1, -1 do
            if edits.order[index] == stepKey then
                table.remove(edits.order, index)
                changed = true
            end
        end
    end
    if changed then Tidy(rotation) end
    return changed
end

-- „Zurück zur Vorlage“: löscht die Anpassungen dieser Rotation für diesen Charakter. → true, wenn es welche gab
function Rotation.ResetEdits(rotation)
    if not rotation or Edits(rotation, false) == nil then return false end     -- zieht einen alten Eintrag vorher um
    local char = ns.db.rotationEdits[CharKey()]
    char[EditKey(rotation)] = nil
    Changed(rotation)
    return true
end
