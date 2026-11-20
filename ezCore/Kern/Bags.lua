local _, ns = ...
local Core = ezCore

--[[
    Taschen: Zahl, freie Plätze, Listen der Taschen und jeder belegte Platz (Core.NumBagSlots, Core.FreeBagSlots,
    Core.BagSpace, Core.BagList, Core.ForEachBagItem). Bis Welle 11 in Util.lua (EC-53, V-019); Namen unverändert.
]]

---------------------------------------------------------------------------
-- Taschen
---------------------------------------------------------------------------

function Core.NumBagSlots()
    return (Constants and Constants.InventoryConstants and Constants.InventoryConstants.NumBagSlots) or NUM_BAG_SLOTS or 4
end

-- Freie Plätze in normalen Taschen (Berufstaschen und Köcher fassen nicht alles).
function Core.FreeBagSlots()
    if C_Container and C_Container.CalculateTotalNumberOfFreeBagSlots then
        return C_Container.CalculateTotalNumberOfFreeBagSlots() or 0
    end
    local free = 0
    for bag = 0, Core.NumBagSlots() do
        local count, family = C_Container.GetContainerNumFreeSlots(bag)
        if family == 0 then free = free + (count or 0) end
    end
    return free
end

-- Freie und alle Plätze der normalen Taschen: free, total – dazu getrennt die der Spezialtaschen (Berufstaschen,
-- Köcher, Munitionsbeutel: fassen nicht alles): specialFree, specialTotal. Gesperrte Antworten zählen als 0.
-- total == 0 heißt: Der Client kennt die Taschen (noch oder schon) nicht – jeder Charakter hat einen Rucksack.
function Core.BagSpace()
    local total, free, specialTotal, specialFree = 0, 0, 0, 0
    for bag = 0, Core.NumBagSlots() do
        local slots = Core.Num(C_Container.GetContainerNumSlots(bag)) or 0
        local freeSlots, family = C_Container.GetContainerNumFreeSlots(bag)
        freeSlots, family = Core.Num(freeSlots) or 0, Core.Num(family) or 0
        if family == 0 then
            total = total + slots
            free = free + freeSlots
        else
            specialTotal = specialTotal + slots
            specialFree = specialFree + freeSlots
        end
    end
    return free, total, specialFree, specialTotal
end

--[=[
    Taschenlisten – EINE Regel (V-175, V-053, V-163). Core.BagList(art) → Liste der Behälter-IDs:
      "bags"    (Standard) Rucksack und die normalen Taschenplätze, 0..NumBagSlots – was Blizzards „alle Taschen“ zeigt
                und worin freie Plätze gezählt werden
      "carried" alles, was der Charakter bei sich trägt: dazu Reagenzientasche und Schlüsselbund (zählen, Wert, Suche)
      "sell"    wie "carried" ohne Schlüsselbund (verkaufen, verschicken, umlagern)
      "bank"    die Bank (Inventory.BankBags)
    Eine Liste von IDs wird unverändert genommen. Module schreiben keine eigene Doppelschleife mehr:
      Core.ForEachBagItem(fn, art oder Liste)   fn(bag, slot, info) für jeden belegten Platz
]=]
function Core.BagList(kind)
    if type(kind) == "table" then return kind end
    local inv = Core.Inventory
    if kind == "carried" and inv and inv.CarriedBags then return (inv.CarriedBags()) end
    if kind == "sell" and inv and inv.CarriedBags then return (inv.CarriedBags({ keyring = false })) end
    if kind == "bank" and inv and inv.BankBags then return inv.BankBags() end
    local list = {}
    for bag = 0, Core.NumBagSlots() do list[#list + 1] = bag end
    return list
end

-- Jeder belegte Taschenplatz: fn(bag, slot, info) mit Blizzards ContainerItemInfo. bags = Art oder Liste (Core.BagList);
-- ohne Angabe die normalen Taschen (wie bisher). Eine gesperrte Gegenstands-ID gilt wie ein leerer Platz: erst
-- Core.IsSecret, dann der Test auf nil (Leitlinie 6, dieselbe Reihenfolge wie V-054 in ezBag).
function Core.ForEachBagItem(fn, bags)
    if type(fn) ~= "function" or not C_Container then return 0 end
    local count = 0
    for _, bag in ipairs(Core.BagList(bags)) do
        for slot = 1, Core.Num(C_Container.GetContainerNumSlots(bag)) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if type(info) == "table" and not Core.IsSecret(info.itemID) and info.itemID ~= nil then
                count = count + 1
                fn(bag, slot, info)
            end
        end
    end
    return count
end
