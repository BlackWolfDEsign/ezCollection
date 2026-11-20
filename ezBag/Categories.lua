local _, ns = ...

-- Anzeige-Reihenfolge der eingebauten Gruppen (Standard, per Ziehen änderbar).
ns.CATEGORY_ORDER = {
    "new", "books", "quest", "sets", "equipment", "consumable", "ammo", "tradegoods", "reagent",
    "recipe", "key", "container", "misc", "junk", "empty",
}

-- Gruppen, die man einem Gegenstand fest zuweisen kann.
ns.ASSIGNABLE = {
    "books", "quest", "sets", "equipment", "consumable", "ammo", "tradegoods", "reagent",
    "recipe", "key", "container", "misc", "junk",
}

local ASSIGNABLE_SET = {}
for _, key in ipairs(ns.ASSIGNABLE) do ASSIGNABLE_SET[key] = true end

-- Eingebaute Gruppe oder eigene Gruppe ("custom:<id>"), die es noch gibt.
function ns.IsAssignable(key)
    if ASSIGNABLE_SET[key] then return true end
    local id = type(key) == "string" and key:match("^custom:(.+)$")
    return id ~= nil and ns.db.custom[id] ~= nil
end

-- Enum.ItemClass: 0 Verbrauchbar, 1 Behälter, 2 Waffe, 4 Rüstung, 5 Reagenz, 6 Projektil,
-- 7 Handwerkswaren, 9 Rezept, 11 Köcher, 12 Quest, 13 Schlüssel.
local CLASS_TO_CATEGORY = {
    [0] = "consumable",
    [1] = "container",
    [2] = "equipment",
    [4] = "equipment",
    [5] = "reagent",
    [6] = "ammo",
    [7] = "tradegoods",
    [9] = "recipe",
    [11] = "container",
    [12] = "quest",
    [13] = "key",
}

-- Klasse, Unterklasse und Platz zum Anlegen über ezCore.ItemClass (V-177: eine Stelle, gesperrte Werte → nil).
function ns.ItemClassInfo(itemID)
    return ezCore.ItemClass(itemID)
end

-- Sammlungen und Bibliotheksbücher aus dem Item-Wissen (ezCore/Wissen/Collections.lua):
-- collect = { kind, known, otherClass } oder nil, book = { quest, done, doneBy } oder nil.
function ns.CollectInfo(itemID, link)
    local K = ns.Knowledge
    if not (K and K.Get) or not ns.PlainID(itemID) then return nil, nil end
    local f = K.Get(link or itemID)
    if type(f) ~= "table" then return nil, nil end
    return f.collect, f.book
end

---------------------------------------------------------------------------
-- "Neu": bleibt stehen, bis die Tasche geschlossen wird, damit nichts unter
-- der Maus wegspringt, wenn Blizzard die Markierung früher entfernt.
---------------------------------------------------------------------------

local stickyNew = {}

local function IsNew(bag, slot, itemID)
    local key = bag * 1000 + slot
    if C_NewItems and C_NewItems.IsNewItem and C_NewItems.IsNewItem(bag, slot) then
        stickyNew[key] = itemID
        return true
    end
    return stickyNew[key] == itemID
end

function ns.ClearNewItems()
    wipe(stickyNew)
end

---------------------------------------------------------------------------
-- Plunder
---------------------------------------------------------------------------

-- Liefert: istPlunder, vomSpielerMarkiert
function ns.IsJunk(info)
    local itemID = ns.ItemIDOf(info)
    if not itemID then return false, false end
    local assigned = ns.db.assign[itemID]
    if assigned == "junk" then return true, true end
    if assigned then return false, false end
    return info.quality == 0, false
end

---------------------------------------------------------------------------
-- Regeln eigener Gruppen
---------------------------------------------------------------------------

-- rules = { classes = { ["7"] = true, ["0:1"] = true }, boe = true, text = "...", minQuality = 3 }
-- Ein Gegenstand passt, wenn eine Art-, BoE- oder Textregel zutrifft UND die
-- Mindestqualität erfüllt ist. Nur eine Mindestqualität = alle ab dieser Qualität.
function ns.HasRules(rules)
    if type(rules) ~= "table" then return false end
    return (rules.classes and next(rules.classes) ~= nil) or rules.boe or (rules.text and rules.text ~= "")
        or (rules.tags and next(rules.tags) ~= nil) or rules.minQuality ~= nil
end

-- Schlüssel des Item-Wissens (z. B. "prof:leatherworking", "slot:hands", "bufffood", "for:MAGE").
function ns.ItemTags(item)
    local K = ns.Knowledge
    if not (K and K.Get and K.Tags and item.itemID) then return nil end
    local ok, facts = pcall(K.Get, item.link or item.itemID)
    if not ok or not facts then return nil end
    local ok2, list = pcall(K.Tags, facts)
    if not ok2 or type(list) ~= "table" then return nil end
    local set = {}
    for _, tag in ipairs(list) do
        if type(tag) == "table" and tag.key then set[tag.key] = true elseif type(tag) == "string" then set[tag] = true end
    end
    return set
end

--[[
    Bedingungen: gewählte Arten (eine davon), ungebunden, Text im Namen und
    jedes gewählte Merkmal aus dem Item-Wissen. rules.mode == "and": alle
    müssen passen, sonst reicht eine. Mindestqualität gilt immer zusätzlich.
]]
function ns.MatchRules(rules, item)
    local results = {}
    if rules.classes and next(rules.classes) ~= nil then
        results[#results + 1] = item.classID ~= nil and (rules.classes[tostring(item.classID)]
            or rules.classes[item.classID .. ":" .. (item.subClassID or 0)]) == true
    end
    if rules.boe then
        results[#results + 1] = (item.isEquip and not item.bound and (item.quality or 0) >= 2) == true
    end
    if rules.text and rules.text ~= "" then
        results[#results + 1] = item.name ~= nil and item.name:lower():find(rules.text:lower(), 1, true) ~= nil
    end
    if rules.tags and next(rules.tags) ~= nil then
        local tags = ns.ItemTags(item) or {}
        for tag in pairs(rules.tags) do results[#results + 1] = tags[tag] == true end
    end

    local hit
    if #results == 0 then
        hit = true
    elseif rules.mode == "and" then
        hit = true
        for _, r in ipairs(results) do if not r then hit = false break end end
    else
        hit = false
        for _, r in ipairs(results) do if r then hit = true break end end
    end
    if not hit then return false end
    if rules.minQuality and (item.quality or 0) < rules.minQuality then return false end
    return true
end

---------------------------------------------------------------------------
-- Einsortieren
---------------------------------------------------------------------------

--[[
    item = { itemID, quality, name, bound, isNew, isQuest, inSet }
    Reihenfolge: feste Zuweisung > grau = Plunder > Neu > Regeln eigener
    Gruppen > Ausrüstungsset > Quest > Gegenstandsart.
]]
function ns.ClassifyItem(item)
    local itemID = ns.PlainID(item.itemID)
    if not itemID then return "empty" end

    local assigned = ns.db.assign[itemID]
    if assigned and ns.IsAssignable(assigned) then return assigned end

    if item.quality == 0 then return "junk" end
    if item.isNew then return "new" end

    local classID, subClassID, equipLoc = ns.ItemClassInfo(itemID)
    item.classID, item.subClassID = classID, subClassID
    -- Die eine Regel „ist Ausrüstung“ aus ezCore (Waffe oder Rüstung mit einem Platz zum Anlegen).
    item.isEquip = ezCore.EquipSlots.IsEquipment(classID, equipLoc) == true

    for _, group in ipairs(ns.Groups.RuleGroups()) do
        if ns.MatchRules(group.rules, item) then return group.key end
    end

    if item.inSet then return "sets" end
    if select(2, ns.CollectInfo(itemID, item.link)) then return "books" end
    if item.isQuest then return "quest" end

    local category = CLASS_TO_CATEGORY[classID]
    if category == "equipment" and not item.isEquip then category = "misc" end
    return category or "misc"
end

-- Für einen Platz in Tasche oder Bank (mit Neu, Quest und Set).
function ns.Classify(bag, slot, info, allowNew)
    local itemID = ns.ItemIDOf(info)
    if not itemID then return "empty" end
    local item = {
        itemID = itemID,
        link = info.hyperlink,
        quality = info.quality,
        name = ns.ItemName(info.hyperlink),
        bound = info.isBound,
    }
    if allowNew ~= false and ns.S.newItems then item.isNew = IsNew(bag, slot, itemID) end
    -- Blizzards Angabe und was ezQuest erkennt – dieselbe Regel wie bei „Platz schaffen“ (Marks.lua).
    item.isQuest = ns.IsQuestSlot(bag, slot, itemID, info.hyperlink)
    if C_Container.GetContainerItemEquipmentSetInfo then
        local ok, inSet = pcall(C_Container.GetContainerItemEquipmentSetInfo, bag, slot)
        item.inSet = ok and inSet == true
    end
    return ns.ClassifyItem(item)
end
