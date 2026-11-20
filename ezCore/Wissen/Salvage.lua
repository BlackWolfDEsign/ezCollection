local _, ns = ...
local Core = ezCore
local L = Core.L

--[[
    „Zerlegen“ – was ein Gegenstand beim Entzaubern (später Sondieren, Mahlen) ergibt und was das wert ist.
    Daten für eine geplante Anzeige des Entzauber-Werts (Idee des Nutzers, 13.11.2026); nur Daten und Rechnung, keine Oberfläche.
    Die Tabellen stehen in SalvageData.lua und sind UNGEPRÜFT (im Spiel abgleichen) – jedes Ergebnis trägt
    `unverified = true`, bis die Art in SalvageData.KINDS freigegeben ist.

      Salvage.Kinds(all)          → { { key, spell, name, order, known, hasData, unverified } … } nach Reihenfolge.
                                    Nur Arten, deren Zauber der Client kennt (all = true: jede, mit exists = true/false)
      Salvage.Exists(art)         → kennt der Client den Zauber der Art?
      Salvage.Known(art)          → kann der gespielte Charakter es? (Zauber gelernt)
      Salvage.For(item)           → Ergebnis oder nil, Grund. item = itemID oder Link (Link: Itemlevel der Variante).
                                    { kind, spell, known, itemID, quality, ilvl, weapon, unverified,
                                      materials = { { id, chance (0–1), min, max, avg (Stück je Treffer),
                                                      expected (Stück je Zerlegen) } … häufigstes zuerst } }
                                    Gründe: "item" (unbekannt), "loading" (Daten noch nicht da), "type" (keine
                                    Ausrüstung), "quality" (nicht grün/blau/violett), "level" (Itemlevel außerhalb
                                    der Tabelle), "missing" (keine Art im Client)
      Salvage.Disenchant(quality, ilvl, weapon) → Materialliste wie oben (reiner Tabellenzugriff) oder nil, Grund
      Salvage.Value(item, anzahl) → erwarteter Wert in Kupfer (über Core.Prices), Einzelheiten { result, parts =
                                    { { id, expected, price, value } }, missing = Anzahl Materialien ohne Preis,
                                    complete = true/false }; nil, Grund, wenn sich nichts zerlegen lässt oder
                                    kein einziges Material einen Preis hat ("price")
      Salvage.Label(art)          → „Entzaubern“ (Zaubername des Clients, sonst der eigene Text)
]]

local Salvage = {}
Core.Salvage = Salvage

local D = ns.SalvageData or {}
Salvage.KINDS = D.KINDS or {}

local function SpellExists(id)
    id = Core.Num(id)
    if not id then return false end
    if C_Spell and type(C_Spell.DoesSpellExist) == "function" then
        local ok, exists = pcall(C_Spell.DoesSpellExist, id)
        if ok then return Core.Bool(exists, false) end
    end
    return Core.SpellName(id) ~= nil
end

function Salvage.Exists(kind)
    local k = type(kind) == "string" and Salvage.KINDS[kind] or nil
    return k ~= nil and SpellExists(k.spell)
end

function Salvage.Known(kind)
    local k = type(kind) == "string" and Salvage.KINDS[kind] or nil
    if not k then return false end
    local Sp = Core.Spells
    if Sp and Sp.IsKnown then return Sp.IsKnown(k.spell) == true end
    local fn = rawget(_G, "IsPlayerSpell")
    if type(fn) ~= "function" then return false end
    local ok, known = pcall(fn, k.spell)
    return ok and Core.Bool(known, false) == true
end

function Salvage.Label(kind)
    local k = type(kind) == "string" and Salvage.KINDS[kind] or nil
    if not k then return nil end
    return Core.SpellName(k.spell) or L[k.label]
end

function Salvage.Kinds(all)
    local list = {}
    for key, k in pairs(Salvage.KINDS) do
        local exists = SpellExists(k.spell)
        if exists or all then
            list[#list + 1] = { key = key, spell = k.spell, name = Salvage.Label(key), order = k.order or 99,
                exists = exists, known = exists and Salvage.Known(key) or false, hasData = k.data ~= nil,
                unverified = k.unverified == true }
        end
    end
    table.sort(list, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.key < b.key
    end)
    return list
end

---------------------------------------------------------------------------
-- Entzaubern: Tabellenzugriff
---------------------------------------------------------------------------

local function Material(id, chance, min, max)
    local avg = (min + max) / 2
    return { id = id, chance = chance, min = min, max = max, avg = avg, expected = chance * avg }
end

local function Row(rows, ilvl)
    for _, row in ipairs(rows or {}) do
        if ilvl >= row[1] and ilvl <= row[2] then return row end
    end
    return nil
end

local function ByChance(a, b)
    if a.chance ~= b.chance then return a.chance > b.chance end
    return a.id < b.id
end

function Salvage.Disenchant(quality, ilvl, weapon)
    quality, ilvl = Core.Num(quality), Core.Num(ilvl)
    if not (quality and ilvl) then return nil, "item" end
    local tableName = D.DISENCHANT and D.DISENCHANT[quality]
    if not tableName then return nil, "quality" end
    local row = Row(D[tableName], math.floor(ilvl))
    if not row then return nil, "level" end
    local list = {}
    if quality == 2 then
        local dust, essence, shard, shardChance = row[3], row[4], row[5], row[6] or 0
        local major = shard and (D.UNCOMMON_MAJOR or 0.75) or (D.UNCOMMON_MAJOR_ALONE or 0.80)
        local minor = 1 - major - (shard and shardChance or 0)
        if minor < 0 then minor = 0 end
        list[#list + 1] = Material(dust[1], weapon and minor or major, dust[2], dust[3])
        list[#list + 1] = Material(essence[1], weapon and major or minor, essence[2], essence[3])
        if shard then list[#list + 1] = Material(shard, shardChance, 1, 1) end
    else
        for _, m in ipairs(row[3]) do list[#list + 1] = Material(m[1], m[2], m[3], m[4]) end
    end
    table.sort(list, ByChance)
    return list
end

---------------------------------------------------------------------------
-- Gegenstand → Ergebnis
---------------------------------------------------------------------------

-- Qualität und Itemlevel: Link → Itemlevel der Variante (GetDetailedItemLevelInfo), sonst der Grundwert.
local function QualityAndLevel(item)
    local info = { Core.Call((C_Item and C_Item.GetItemInfo) or rawget(_G, "GetItemInfo"), item) }
    local quality, ilvl = Core.Num(info[3]), Core.Num(info[4])
    if type(item) == "string" then
        local detailed = Core.Num((Core.Call((C_Item and C_Item.GetDetailedItemLevelInfo) or rawget(_G, "GetDetailedItemLevelInfo"), item)))
        if detailed and detailed > 0 then ilvl = detailed end
    end
    return quality, ilvl
end

function Salvage.For(item)
    if Core.IsSecret(item) or item == nil then return nil, "item" end
    local itemID = Core.ItemID(item)
    if not itemID then return nil, "item" end
    -- heute gibt es nur für das Entzaubern Daten; weitere Arten hängen hier ihre Prüfung an
    local kind = "disenchant"
    local k = Salvage.KINDS[kind]
    if not (k and k.data and SpellExists(k.spell)) then return nil, "missing" end
    local classID, _, equipLoc = Core.ItemClass(type(item) == "string" and item or itemID)
    if not classID then
        classID, _, equipLoc = Core.ItemClass(itemID)
        if not classID then return nil, "loading" end
    end
    if not Core.EquipSlots.IsEquipment(classID, equipLoc) then return nil, "type" end
    local quality, ilvl = QualityAndLevel(type(item) == "string" and item or itemID)
    if not (quality and ilvl) then
        Core.Call(C_Item and C_Item.RequestLoadItemDataByID, itemID)
        return nil, "loading"
    end
    local weapon = classID == Core.ITEM_CLASS.Weapon
    local materials, reason = Salvage.Disenchant(quality, ilvl, weapon)
    if not materials then return nil, reason end
    return { kind = kind, spell = k.spell, known = Salvage.Known(kind), itemID = itemID, quality = quality, ilvl = ilvl,
        weapon = weapon, unverified = k.unverified == true, materials = materials }
end

-- Erwarteter Wert beim Zerlegen (Kupfer, gerundet), Einzelheiten. Preise aus Core.Prices (Marktwert des Auktionshauses).
function Salvage.Value(item, count)
    local result, reason = Salvage.For(item)
    if not result then return nil, reason end
    count = Core.Num(count) or 1
    local Prices = Core.Prices
    local total, missing, parts = 0, 0, {}
    for _, m in ipairs(result.materials) do
        local price = Prices and Prices.Value and Core.Num(Prices.Value(m.id, 1)) or nil
        local value = price and price * m.expected * count or nil
        if value then total = total + value else missing = missing + 1 end
        parts[#parts + 1] = { id = m.id, expected = m.expected * count, price = price, value = value and math.floor(value + 0.5) or nil }
    end
    local detail = { result = result, parts = parts, missing = missing, complete = missing == 0 }
    if missing == #result.materials then return nil, "price", detail end
    return math.floor(total + 0.5), detail
end
