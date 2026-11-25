local _, ns = ...
local Core = ezCore

--[[
    Taschen: Zahl, freie Plätze, Listen der Taschen und jeder belegte Platz (Core.NumBagSlots, Core.FreeBagSlots,
    Core.BagKind, Core.EmptyBagSlot, Core.BagSpace, Core.FreeSpaceText, Core.BagList, Core.ForEachBagItem). Bis Welle 11 in Util.lua (EC-53, V-019);
    Namen unverändert.
]]

---------------------------------------------------------------------------
-- Taschen
---------------------------------------------------------------------------

function Core.NumBagSlots()
    return (Constants and Constants.InventoryConstants and Constants.InventoryConstants.NumBagSlots) or NUM_BAG_SLOTS or 4
end

--[[
    Was nimmt eine Tasche? Core.BagKind(bag) → Art, Familie (Durchsicht 24.11.2026 aus ezBag hierher: die Zählung der freien
    Plätze und die Post nahmen nur die Familie am Taschenplatz und hielten eine Bergbautasche für eine normale Tasche).
      "family"      Spezialtasche, deren Familie der Client am Platz (GetContainerNumFreeSlots) oder am Taschengegenstand
                    nennt (Seelen-, Kräuter-, Bergbautasche, Köcher, Munitionsbeutel …): nur passende Familie
      "profession"  Berufstasche ohne Familie (Untertyp der Tasche bzw. IsInventoryItemProfessionBag): nur, was dort liegt
      "reagent"     echte Reagenzientasche (Untertyp 11, sonst der Reagenzien-Platz): Handwerksmaterial
      nil           normale Tasche: alles
    Core.IsProfessionBag(bag), Core.IsBagItem(itemID) (Taschen und Köcher – die gehören nie in eine Spezialtasche: eine leere
    Bergbautasche hat selbst die Familie Bergbau, ein leerer Köcher die Familie Pfeile).
]]
-- Gegenstandsklassen der Taschen: 1 Behälter und 11 Köcher (Untertyp 2 Köcher, 3 Munitionsbeutel; Item.csv, Build
-- 1.60.1.71037: 28 bzw. 13 Gegenstände, Familie laut ItemSparse 1 Pfeile bzw. 2 Kugeln). Untertyp 11 von Klasse 1 ist die
-- Reagenzientasche. Vorher zählte nur Klasse 1 – Köcher galten als normale Taschen (Nutzer am 23.11.2026, wörtlich:
-- „es fehlt das munition autom im munitionsbeutel landet, seelensplitter ebenso bestimmt“)
local CONTAINER_CLASS, QUIVER_CLASS, REAGENT_SUBCLASS = 1, 11, 11
local function IsBagClass(classID)
    return classID == CONTAINER_CLASS or classID == QUIVER_CLASS
end

function Core.IsBagItem(itemID)
    return IsBagClass((Core.ItemClass(itemID)))
end

local function InventorySlotOf(bag)
    if type(bag) ~= "number" or bag <= 0 or not (C_Container and C_Container.ContainerIDToInventoryID) then return nil end
    local ok, slot = pcall(C_Container.ContainerIDToInventoryID, bag)
    return ok and type(slot) == "number" and not Core.IsSecret(slot) and slot or nil
end

-- Berufstasche (Bergbau, Kräuter …)? Wie Blizzard (ContainerFrame_IsProfessionBag): IsInventoryItemProfessionBag am
-- Taschenplatz. Spieltest vom 23.11.2026: „beim verschieben von reagienzen in tasche bugt es immer wieder die selbe
-- meldung im loop“ (Meldung „Ihr könnt hier nur Bergbaubedarf ablegen.“) – die Taschenfamilie aus
-- GetContainerNumFreeSlots erkannte die Bergbautasche nicht.
function Core.IsProfessionBag(bag)
    local slot = type(IsInventoryItemProfessionBag) == "function" and InventorySlotOf(bag)
    if not slot then return false end
    local ok, profession = pcall(IsInventoryItemProfessionBag, "player", slot)
    return ok and not Core.IsSecret(profession) and profession == true
end

local function BagSubclass(bag)
    local slot = type(GetInventoryItemID) == "function" and InventorySlotOf(bag)
    if not slot then return nil end
    local ok, bagItem = pcall(GetInventoryItemID, "player", slot)
    if not ok or type(bagItem) ~= "number" or Core.IsSecret(bagItem) then return nil end
    local classID, subclassID = Core.ItemClass(bagItem)   -- eine Fassung (GetItemInfoInstant)
    if IsBagClass(classID) and type(subclassID) == "number" then return subclassID, bagItem, classID end
    return nil
end

-- Familie, die der Taschengegenstand selbst aufnimmt (bei Taschen liefert GetItemFamily die Arten, die sie nehmen)
local function BagItemFamily(bagItem)
    if not (bagItem and C_Item and C_Item.GetItemFamily) then return 0 end
    local ok, family = pcall(C_Item.GetItemFamily, bagItem)
    return ok and Core.Num(family) or 0
end

function Core.BagKind(bag)
    if type(bag) ~= "number" or bag <= 0 then return nil, 0 end
    local family = Core.Num(select(2, C_Container.GetContainerNumFreeSlots(bag))) or 0
    local subclass, bagItem, bagClass = BagSubclass(bag)
    if bagClass == CONTAINER_CLASS and subclass == REAGENT_SUBCLASS then return "reagent", 0 end
    if family ~= 0 then return "family", family end
    if (subclass and subclass > 0) or Core.IsProfessionBag(bag) then
        -- Der Client nennt am Platz keine Familie (Spieltest: Bergbautasche): die des Taschengegenstands nehmen
        local own = BagItemFamily(bagItem)
        if own ~= 0 then return "family", own end
        return "profession", 0
    end
    if bag == (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) then return "reagent", 0 end
    return nil, 0
end

--[[
    Core.IsSpecialBag(bag): nimmt die Tasche nicht alles (Köcher, Seelen-, Berufstasche)? Die Reagenzientasche gilt nicht als
    Spezialtasche. Bankfächer (und alles jenseits der eigenen Taschen): nur die Familie, die der Client nennt – Blizzard
    prüft Berufstaschen dort nicht (wie beim Umlagern in ezBag).
]]
function Core.IsSpecialBag(bag)
    local last = Core.Num(Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or 5
    if type(bag) == "number" and bag > 0 and bag <= last then
        local kind = Core.BagKind(bag)
        return kind ~= nil and kind ~= "reagent"
    end
    return (Core.Num(select(2, C_Container.GetContainerNumFreeSlots(bag))) or 0) ~= 0
end

-- Freie Plätze in normalen Taschen (Berufstaschen und Köcher fassen nicht alles).
function Core.FreeBagSlots()
    return (Core.BagSpace())
end

-- So lange höchstens auf einen gerade abgeteilten Stapel warten: Der Client meldet seinen neuen Platz leer, bis der
-- Server das Abteilen bestätigt (Spielbefunde vom 21. und 22.11.2026). Eine Stelle für ezCores Anhang-Schlange
-- (MailQueue.lua) und ezBags Anzahl-Feld (Stacks.lua).
Core.SPLIT_ARRIVE_WAIT = 5

-- Ein leerer Platz in einer normalen Tasche (Berufstaschen nehmen nicht alles) → bag, slot oder nil.
-- used (optional): { [bag * 1000 + slot] = true } – schon vergebene Plätze überspringen (MailQueue beim Abteilen,
-- ezBag beim Verkauf einer Teilmenge; vorher lokal in MailQueue.lua).
function Core.EmptyBagSlot(used)
    used = type(used) == "table" and used or {}
    for bag = 0, Core.NumBagSlots() do
        local free = Core.Num((C_Container.GetContainerNumFreeSlots(bag))) or 0
        if free > 0 and Core.BagKind(bag) == nil then
            for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
                if not used[bag * 1000 + slot] and not C_Container.GetContainerItemInfo(bag, slot) then
                    return bag, slot
                end
            end
        end
    end
    return nil
end

-- Freie und alle Plätze der normalen Taschen: free, total – dazu getrennt die der Spezialtaschen (Berufstaschen,
-- Köcher, Munitionsbeutel: fassen nicht alles): specialFree, specialTotal. Gesperrte Antworten zählen als 0.
-- total == 0 heißt: Der Client kennt die Taschen (noch oder schon) nicht – jeder Charakter hat einen Rucksack.
function Core.BagSpace()
    local total, free, specialTotal, specialFree = 0, 0, 0, 0
    for bag = 0, Core.NumBagSlots() do
        local slots = Core.Num(C_Container.GetContainerNumSlots(bag)) or 0
        local freeSlots = Core.Num((C_Container.GetContainerNumFreeSlots(bag))) or 0
        if Core.BagKind(bag) == nil then
            total = total + slots
            free = free + freeSlots
        else
            specialTotal = specialTotal + slots
            specialFree = specialFree + freeSlots
        end
    end
    return free, total, specialFree, specialTotal
end

-- Freier Platz als Text – eine Fassung für ezBag (Rucksack-Symbol, Suchzeile der Bank, Menü der Werkzeugleisten) und
-- ezPanels Taschen-Block (Auftrag des Nutzers vom 23.11.2026: „statt min/max (freier platz) --> einfach nur freier
-- platz anzeigen“, für ezPanel: „Ja, überall (Empfohlen)“). Nur die freien Plätze, kein „belegt/gesamt“ mehr.
-- → „16 frei“; kurz = nur „16“ (wo eine Beschriftung schon sagt, was die Zahl ist, oder kein Platz ist). Kein Wert,
-- ein gesperrter Wert oder weniger als 0 → 0.
function Core.FreeSpaceText(free, short)
    free = math.max(0, math.floor(Core.Num(free) or 0))
    if short then return tostring(free) end
    return Core.L.SPACE_FREE:format(free)
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
