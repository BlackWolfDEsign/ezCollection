local _, ns = ...
local Core = ezCore

---------------------------------------------------------------------------
-- Ausrüstungsplätze und Gegenstandsart (Core.EquipSlots)
---------------------------------------------------------------------------

--[[
    Ausrüstungsplätze und Gegenstandsarten – EINE Tabelle für alle Module (Vollprüfung V-177, V-178, V-063;
    vorher fünfmal: ezGear/Score.lua, ezGear/Character.lua, ezPanel/Blocks/ItemLevel.lua, ezCore/KnowledgeData.lua,
    ezCore/UnitTooltip.lua). Reine Daten und Rechnung, keine Oberfläche. Eigene Datei seit Welle 11 (EC-53, vorher Util.lua);
    lädt direkt nach Util.lua, weil KnowledgeData.lua und Knowledge.lua beim Laden darauf bauen.

      Core.EquipSlots.SLOT            Inventarplätze nach Namen (HEAD = 1 … TABARD = 19, AMMO = 0)
      Core.EquipSlots.LIST            Plätze in der Reihenfolge des Charakterfensters: { slot, name ("HEADSLOT"), key,
                                      frame ("Head" – Blizzards Platz-Knopf heißt "Character<frame>Slot" bzw.
                                      "Inspect<frame>Slot") }
      Core.EquipSlots.ButtonName(slot, betrachten) → "CharacterHeadSlot" | "InspectHeadSlot"
      Core.EquipSlots.COUNTED         Plätze, die fürs Itemlevel zählen (ohne Hemd und Wappenrock)
      Core.EquipSlots.ForLoc(loc)     → Liste der Inventarplätze zu einem INVTYPE ("INVTYPE_FINGER" → { 11, 12 }); nil = keiner
      Core.EquipSlots.Key(loc)        → gemeinsamer Schlüssel ("head", "finger", "ranged" …; Robe = "chest")
      Core.EquipSlots.Label(slot)     → Blizzards Name des Platzes („Kopf“), sonst der Schlüssel
      Core.EquipSlots.LocLabel(loc)   → Blizzards Name des INVTYPE („Brust“ auch für Roben)
      Core.EquipSlots.IsRanged(loc), IsOffhand(loc), IsCosmetic(loc), IsEquippable(loc)
      Core.EquipSlots.IsTwoHand(item) → Zweihänder? (item = INVTYPE, Link oder ID; die eine Regel)
      Core.EquipSlots.IsEquipment(classID, loc)  → die EINE Regel „ist Ausrüstung“ (Waffe oder Rüstung mit Platz)
      Core.ItemClass(item)            → classID, subClassID, equipLoc (sofort, ohne Server; item = ID, Link oder Name)
      Core.IsEquipment(item)          → true/false nach derselben Regel
      Core.ItemClassName(classID, subClassID) → Name der Art bzw. Unterart in der Client-Sprache
      Core.ITEM_CLASS                 Nummern der Arten nach Namen (Weapon = 2, Armor = 4, Tradegoods = 7 …)
]]

local ES = {}
Core.EquipSlots = ES

local SLOT = { AMMO = 0, HEAD = 1, NECK = 2, SHOULDER = 3, SHIRT = 4, CHEST = 5, WAIST = 6, LEGS = 7, FEET = 8, WRIST = 9,
    HANDS = 10, FINGER1 = 11, FINGER2 = 12, TRINKET1 = 13, TRINKET2 = 14, BACK = 15, MAINHAND = 16, OFFHAND = 17,
    RANGED = 18, TABARD = 19 }
ES.SLOT = SLOT

-- INVTYPE → { key = gemeinsamer Schlüssel, slots = Inventarplätze, label = INVTYPE, dessen Namen gezeigt wird }
local LOCS = {
    INVTYPE_HEAD = { key = "head", slots = { SLOT.HEAD } },
    INVTYPE_NECK = { key = "neck", slots = { SLOT.NECK } },
    INVTYPE_SHOULDER = { key = "shoulder", slots = { SLOT.SHOULDER } },
    INVTYPE_BODY = { key = "shirt", slots = { SLOT.SHIRT }, cosmetic = true },
    INVTYPE_CHEST = { key = "chest", slots = { SLOT.CHEST } },
    INVTYPE_ROBE = { key = "chest", slots = { SLOT.CHEST }, label = "INVTYPE_CHEST" },
    INVTYPE_WAIST = { key = "waist", slots = { SLOT.WAIST } },
    INVTYPE_LEGS = { key = "legs", slots = { SLOT.LEGS } },
    INVTYPE_FEET = { key = "feet", slots = { SLOT.FEET } },
    INVTYPE_WRIST = { key = "wrist", slots = { SLOT.WRIST } },
    INVTYPE_HAND = { key = "hands", slots = { SLOT.HANDS } },
    INVTYPE_FINGER = { key = "finger", slots = { SLOT.FINGER1, SLOT.FINGER2 } },
    INVTYPE_TRINKET = { key = "trinket", slots = { SLOT.TRINKET1, SLOT.TRINKET2 } },
    INVTYPE_CLOAK = { key = "back", slots = { SLOT.BACK } },
    INVTYPE_WEAPON = { key = "onehand", slots = { SLOT.MAINHAND, SLOT.OFFHAND } },
    INVTYPE_SHIELD = { key = "shield", slots = { SLOT.OFFHAND }, offhand = true },
    INVTYPE_2HWEAPON = { key = "twohand", slots = { SLOT.MAINHAND } },
    INVTYPE_WEAPONMAINHAND = { key = "mainhand", slots = { SLOT.MAINHAND } },
    INVTYPE_WEAPONOFFHAND = { key = "offhand", slots = { SLOT.OFFHAND }, offhand = true },
    INVTYPE_HOLDABLE = { key = "holdable", slots = { SLOT.OFFHAND }, offhand = true },
    INVTYPE_RANGED = { key = "ranged", slots = { SLOT.RANGED }, ranged = true },
    INVTYPE_RANGEDRIGHT = { key = "ranged", slots = { SLOT.RANGED }, ranged = true, label = "INVTYPE_RANGED" },
    INVTYPE_THROWN = { key = "ranged", slots = { SLOT.RANGED }, ranged = true, label = "INVTYPE_RANGED" },
    INVTYPE_RELIC = { key = "relic", slots = { SLOT.RANGED } },
    INVTYPE_TABARD = { key = "tabard", slots = { SLOT.TABARD }, cosmetic = true },
    INVTYPE_AMMO = { key = "ammo", slots = { SLOT.AMMO } },
    INVTYPE_BAG = { key = "bag", slots = {}, noEquip = true },
    INVTYPE_QUIVER = { key = "quiver", slots = {}, noEquip = true },
}
ES.LOCS = LOCS

-- Abgeleitete Tabellen (dieselben Namen wie bisher in KnowledgeData bzw. ezGear – dort nur noch Verweise).
ES.KEYS, ES.LOC_SLOTS, ES.RANGED_LOCS, ES.OFFHAND_LOCS, ES.COSMETIC_LOCS, ES.LABEL_FROM = {}, {}, {}, {}, {}, {}
ES.NOT_EQUIPPABLE = { [""] = true, INVTYPE_NON_EQUIP_IGNORE = true, INVTYPE_NON_EQUIP = true }
for loc, e in pairs(LOCS) do
    ES.KEYS[loc] = e.key
    if #e.slots > 0 then ES.LOC_SLOTS[loc] = e.slots end
    if e.ranged then ES.RANGED_LOCS[loc] = true end
    if e.offhand then ES.OFFHAND_LOCS[loc] = true end
    if e.cosmetic then ES.COSMETIC_LOCS[loc] = true end
    if e.label then ES.LABEL_FROM[loc] = e.label end
    if e.noEquip then ES.NOT_EQUIPPABLE[loc] = true end
end

-- Reihenfolge des Charakterfensters (links von oben, rechts von oben, unten); name = Blizzards Platzname.
ES.LIST = {
    { slot = 1, name = "HEADSLOT", key = "head", frame = "Head" }, { slot = 2, name = "NECKSLOT", key = "neck", frame = "Neck" },
    { slot = 3, name = "SHOULDERSLOT", key = "shoulder", frame = "Shoulder" }, { slot = 15, name = "BACKSLOT", key = "back", frame = "Back" },
    { slot = 5, name = "CHESTSLOT", key = "chest", frame = "Chest" }, { slot = 4, name = "SHIRTSLOT", key = "shirt", frame = "Shirt", cosmetic = true },
    { slot = 19, name = "TABARDSLOT", key = "tabard", frame = "Tabard", cosmetic = true }, { slot = 9, name = "WRISTSLOT", key = "wrist", frame = "Wrist" },
    { slot = 10, name = "HANDSSLOT", key = "hands", frame = "Hands" }, { slot = 6, name = "WAISTSLOT", key = "waist", frame = "Waist" },
    { slot = 7, name = "LEGSSLOT", key = "legs", frame = "Legs" }, { slot = 8, name = "FEETSLOT", key = "feet", frame = "Feet" },
    { slot = 11, name = "FINGER0SLOT", key = "finger", frame = "Finger0" }, { slot = 12, name = "FINGER1SLOT", key = "finger", frame = "Finger1" },
    { slot = 13, name = "TRINKET0SLOT", key = "trinket", frame = "Trinket0" }, { slot = 14, name = "TRINKET1SLOT", key = "trinket", frame = "Trinket1" },
    { slot = 16, name = "MAINHANDSLOT", key = "mainhand", frame = "MainHand" }, { slot = 17, name = "SECONDARYHANDSLOT", key = "offhand", frame = "SecondaryHand" },
    { slot = 18, name = "RANGEDSLOT", key = "ranged", frame = "Ranged" },
}

-- Name von Blizzards Platz-Knopf: ES.ButtonName(16) → "CharacterMainHandSlot", ES.ButtonName(16, true) →
-- "InspectMainHandSlot" (Feld frame der Liste, GEAR-08: vorher eine eigene Liste in ezGear). Unbekannter Platz: nil.
function ES.ButtonName(slot, inspect)
    local entry = ES.BY_SLOT[Core.Num(slot) or -1]
    if not entry then return nil end
    return (inspect and "Inspect" or "Character") .. entry.frame .. "Slot"
end

-- Plätze fürs Itemlevel: alles außer Hemd und Wappenrock (ein leerer Platz zählt beim Mitteln nicht mit).
ES.COUNTED, ES.BY_SLOT = {}, {}
for _, e in ipairs(ES.LIST) do
    ES.BY_SLOT[e.slot] = e
    if not e.cosmetic then ES.COUNTED[#ES.COUNTED + 1] = e.slot end
end
table.sort(ES.COUNTED)

local function Loc(loc)
    if Core.IsSecret(loc) or type(loc) ~= "string" then return nil end
    return LOCS[loc]
end

function ES.ForLoc(loc)
    local e = Loc(loc)
    return e and #e.slots > 0 and e.slots or nil
end

function ES.Key(loc)
    local e = Loc(loc)
    return e and e.key or nil
end

function ES.IsRanged(loc) local e = Loc(loc) return e ~= nil and e.ranged == true end
function ES.IsOffhand(loc) local e = Loc(loc) return e ~= nil and e.offhand == true end
function ES.IsCosmetic(loc) local e = Loc(loc) return e ~= nil and e.cosmetic == true end

-- Die eine Zweihänder-Regel (Gegenprüfung I3, Gesamtreview 18.11.2026; vorher in SlotText.AverageLevel und
-- ezGear/GroupCheck.lua je für sich): item ist ein INVTYPE ("INVTYPE_2HWEAPON") oder ein Gegenstand (Link, ID).
function ES.IsTwoHand(item)
    if Core.IsSecret(item) or item == nil then return false end
    local loc = item
    if type(item) ~= "string" or item:sub(1, 8) ~= "INVTYPE_" then loc = select(3, Core.ItemClass(item)) end
    return loc == "INVTYPE_2HWEAPON"
end

-- Lässt sich ein Gegenstand mit diesem INVTYPE anlegen? (Taschen und Köcher zählen nicht als Ausrüstung.)
function ES.IsEquippable(loc)
    if Core.IsSecret(loc) or type(loc) ~= "string" then return false end
    return not ES.NOT_EQUIPPABLE[loc]
end

-- Die eine Regel „ist Ausrüstung“: Waffe (2) oder Rüstung (4) mit einem Platz zum Anlegen.
function ES.IsEquipment(classID, loc)
    classID = Core.Num(classID)
    return (classID == 2 or classID == 4) and ES.IsEquippable(loc)
end

local function GlobalText(name)
    local text = name and Core.Plain(rawget(_G, name))
    if type(text) == "string" and text ~= "" then return text end
    return nil
end

function ES.Label(slot)
    local e = ES.BY_SLOT[Core.Num(slot) or -1]
    if not e then return nil end
    return GlobalText(e.name) or e.key
end

function ES.LocLabel(loc)
    local e = Loc(loc)
    if not e then return nil end
    return GlobalText(e.label or loc) or e.key
end

---------------------------------------------------------------------------
-- Gegenstandsart
---------------------------------------------------------------------------

-- Nummern der Arten: Blizzards Enum.ItemClass, sonst die festen Werte (seit Classic unverändert).
Core.ITEM_CLASS = { Consumable = 0, Container = 1, Weapon = 2, Gem = 3, Armor = 4, Reagent = 5, Projectile = 6,
    Tradegoods = 7, ItemEnhancement = 8, Recipe = 9, Quiver = 11, Questitem = 12, Key = 13, Miscellaneous = 15 }
if type(Enum) == "table" and type(Enum.ItemClass) == "table" then
    for name, id in pairs(Enum.ItemClass) do
        if type(name) == "string" and type(id) == "number" then Core.ITEM_CLASS[name] = id end
    end
end

-- classID, subClassID, equipLoc – sofort (GetItemInfoInstant fragt den Server nicht); nil, wenn unbekannt.
-- api (freiwillig) wie bei Core.ItemInstant (Gesamtreview 18.11.2026, T16-16: die eine Umhüllung von GetItemInfoInstant).
function Core.ItemClass(item, api)
    local _, _, _, equipLoc, _, classID, subClassID = Core.ItemInstant(item, api)
    classID = Core.Num(classID)
    if not classID then return nil end
    equipLoc = Core.Plain(equipLoc)
    if type(equipLoc) ~= "string" or equipLoc == "" then equipLoc = nil end
    return classID, Core.Num(subClassID), equipLoc
end

function Core.IsEquipment(item)
    local classID, _, equipLoc = Core.ItemClass(item)
    return ES.IsEquipment(classID, equipLoc)
end

-- Name einer Art („Waffe“) bzw. mit subClassID einer Unterart („Schwert“) in der Client-Sprache; nil, wenn unbekannt.
function Core.ItemClassName(classID, subClassID)
    classID, subClassID = Core.Num(classID), Core.Num(subClassID)
    if not classID then return nil end
    local name
    if subClassID then
        name = Core.Call((C_Item and C_Item.GetItemSubClassInfo) or rawget(_G, "GetItemSubClassInfo"), classID, subClassID)
    else
        name = Core.Call((C_Item and C_Item.GetItemClassInfo) or rawget(_G, "GetItemClassInfo"), classID)
    end
    name = Core.Plain(name)
    if type(name) == "string" and name ~= "" then return name end
    return nil
end
