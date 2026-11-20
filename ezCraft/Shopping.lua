local ADDON, ns = ...
local L = ns.L
local Core = ezCore
local Data = ns.Data

--[[
    Einkaufsliste aus Rezepten (ezCraftDB.shopping, für alle Twinks gemeinsam).
      Eintrag: { id = recipeID, count }  – nur das, was dem Spieler gehört.
    Name, Symbol, Produkt und Zutaten liest ezCraft jedes Mal frisch (Data.Recipe: offenes Berufefenster,
    sonst das Rezept-Wissen von ezCore, Knowledge.Recipe) – so veraltet nichts, und die Liste funktioniert
    auch am Auktionshaus, wenn das Berufefenster zu ist.
    „Vorhanden“ zählt wie im Berufefenster nach den Einstellungen (Tasche immer, Bank, Post, Gildenbank, Twinks).
    Fehlendes, das sich im aktuellen Gebiet sammeln lässt, heißt „hier sammelbar“ (Data.Gather, ezCore.Gathering – eigene
    Ernten „bei dir“ zuerst); im Seitenteil führt der Kartenknopf „Nächste Fundorte“ zur Weltkarte (SAM-24, Panel.lua).

    Für andere Module (ezCore.API("ezCraft")):
      ShoppingList()        → { [itemID] = fehlende Anzahl }
      Needs()               → { [itemID] = Gesamtbedarf } (auch was schon da ist – z. B. damit ezBag oder ezMerchant
                              Material der Liste nicht als Plunder verkaufen; V-144)
      ShoppingRecipes()     → { { recipeID, name, count }, … }
      AddRecipe(recipeID, n) → true, neue Anzahl
    Nachricht EZCRAFT_SHOPPING_CHANGED (ezCore.Listen) bei jeder Änderung.
    Einkaufen über ezAuction (abgestimmt mit m-ezauction, 13.11.2026):
      ezCore.API("ezAuction").AddShoppingList(name, items, true) mit items = { { itemID, count, name }, … };
      true leert eine Liste gleichen Namens und füllt sie neu. Rückgabe: Listenname, Anzahl übernommener
      Einträge – nil, solange ezAuction noch nicht bereit ist. Die Liste steht im Auktionshaus im Reiter
      „Kaufen“ oben in Blizzards Kategorienliste. Übergeben wird nur, was fehlt.
]]

local Shopping = {}
ns.Shopping = Shopping

local floor, max, min = math.floor, math.max, math.min
local EMPTY = {}

local function List() return ns.db and ns.db.shopping or EMPTY end

-- Gesamtbedarf je Gegenstand, einmal gerechnet (V-145: vorher las jeder Item-Tooltip alle Rezepte der Liste neu).
-- Gilt, bis sich die Liste oder die Rezepte ändern: Shopping.Invalidate bei jeder Änderung der Liste, beim Öffnen,
-- Auffrischen und Schließen des Berufefensters und wenn ezCore Rezepte gelernt hat.
local needCache

function Shopping.Invalidate() needCache = nil end

local function Changed()
    needCache = nil
    ns.Fire("SHOPPING_CHANGED")
    Core.Fire("EZCRAFT_SHOPPING_CHANGED")
end

local function Find(recipeID)
    for index, entry in ipairs(List()) do
        if entry.id == recipeID then return entry, index end
    end
    return nil
end

-- Altes Format (vor 1.2: Name, Symbol, Produkt und Zutaten mitgespeichert) auf { id, count } kürzen.
function Shopping.Migrate(list)
    for i = #list, 1, -1 do
        local entry = list[i]
        local id = type(entry) == "table" and Core.Num(entry.id)
        if id then
            list[i] = { id = id, count = max(1, floor(Core.Num(entry.count) or 1)) }
        else
            table.remove(list, i)
        end
    end
    return list
end

-- Rezept eines Eintrags, frisch gelesen (nil, wenn weder Fenster noch Rezept-Wissen es kennen).
function Shopping.Recipe(entry)
    return entry and Data.Recipe(entry.id) or nil
end

-- Zutaten eines Eintrags: { [itemID] = Anzahl je Herstellung }.
function Shopping.Reagents(entry)
    local recipe = Shopping.Recipe(entry)
    local r = {}
    for _, reagent in ipairs(recipe and recipe.reagents or EMPTY) do r[reagent.itemID] = reagent.count end
    return r
end

-- Name und Symbol eines Eintrags; unbekannte Rezepte heißen „#recipeID“.
function Shopping.Name(entry)
    local recipe = Shopping.Recipe(entry)
    return recipe and recipe.name or ("#" .. tostring(entry.id))
end

function Shopping.Icon(entry)
    local recipe = Shopping.Recipe(entry)
    return recipe and (recipe.icon or (recipe.product and Data.ItemIcon(recipe.product))) or nil
end

function Shopping.Entries() return List() end

-- Rezept (aus Data.Recipe) mit Menge hinzufügen; dasselbe Rezept wird zusammengezählt.
function Shopping.Add(recipe, quantity)
    if not (recipe and recipe.recipeID and ns.db) then return false end
    quantity = max(1, floor(tonumber(quantity) or 1))
    local entry = Find(recipe.recipeID)
    if not entry then
        entry = { id = recipe.recipeID, count = 0 }
        table.insert(ns.db.shopping, entry)
    end
    entry.count = entry.count + quantity
    Changed()
    return true, entry.count
end

-- Anzahl setzen; 0 oder weniger entfernt den Eintrag.
function Shopping.SetCount(recipeID, count)
    local entry, index = Find(recipeID)
    if not entry then return false end
    count = floor(tonumber(count) or 0)
    if count <= 0 then
        table.remove(ns.db.shopping, index)
    else
        entry.count = count
    end
    Changed()
    return true
end

function Shopping.Remove(recipeID) return Shopping.SetCount(recipeID, 0) end

function Shopping.Clear()
    if not ns.db then return end
    wipe(ns.db.shopping)
    Changed()
end

-- Einkaufsliste leeren nach Rückfrage – ein Weg für die Knöpfe (Einstellungen, Seitenteil) und „/ezcraft leeren“
-- (T9-10). announce: danach „Einkaufsliste geleert.“ im Chat (der Befehl hat sonst keine sichtbare Antwort).
function Shopping.AskClear(announce)
    return Core.Confirm(L.SHOP_CLEAR_CONFIRM, function()
        Shopping.Clear()
        if announce then ns.Print(L.SHOP_CLEARED) end
    end)
end

local function NeedMap()
    if needCache then return needCache end
    local need = {}
    for _, entry in ipairs(List()) do
        for itemID, per in pairs(Shopping.Reagents(entry)) do
            need[itemID] = (need[itemID] or 0) + per * (entry.count or 1)
        end
    end
    if ns.db then needCache = need end   -- vor dem Laden der Datenbank nichts merken
    return need
end

-- Gesamtbedarf { [itemID] = Anzahl } über alle Einträge (eine Kopie: der Aufrufer darf sie verändern).
function Shopping.Needs()
    local need = {}
    for itemID, n in pairs(NeedMap()) do need[itemID] = n end
    return need
end

-- Bedarf eines einzelnen Gegenstands (für den Tooltip).
function Shopping.NeedFor(itemID)
    return NeedMap()[itemID] or 0
end

-- Zeilen { itemID, name, icon, need, stock, have, missing }: fehlendes zuerst, dann nach Namen.
function Shopping.Totals(S)
    local rows = {}
    for itemID, need in pairs(Shopping.Needs()) do
        local stock = Data.Stock(itemID)
        local have = Data.Have(stock, S)
        rows[#rows + 1] = { itemID = itemID, name = Data.ItemName(itemID), icon = Data.ItemIcon(itemID), need = need,
            stock = stock, have = have, missing = max(0, need - have) }
    end
    table.sort(rows, function(a, b)
        if (a.missing > 0) ~= (b.missing > 0) then return a.missing > 0 end
        return a.name < b.name
    end)
    return rows
end

function Shopping.MissingMap(S)
    local map = {}
    for _, row in ipairs(Shopping.Totals(S)) do
        if row.missing > 0 then map[row.itemID] = row.missing end
    end
    return map
end

-- Was in der eigenen Tasche fehlt (zum Anfordern bei Twinks).
function Shopping.BagNeeds()
    local needs = {}
    for itemID, need in pairs(Shopping.Needs()) do
        local lack = need - Data.Stock(itemID).bags
        if lack > 0 then needs[itemID] = lack end
    end
    return needs
end

---------------------------------------------------------------------------
-- Aus der Bank holen (NEU-01): was der Tasche für die Einkaufsliste fehlt, aus der offenen Bank bzw. Gildenbank –
-- umgelagert von ezBag (ezCore.API("ezBag").Withdraw; ezBag plant Schritt für Schritt, nie im Kampf, und meldet im
-- Chat, was kam). Gezeigt nur bei offener Bank oder Gildenbank und laufendem ezBag (Knopf im Reiter „Einkaufsliste“).
-- Defensiv gebaut (Grundsatz 5): das Umlagern selbst ist im Spiel noch zu bestätigen.
---------------------------------------------------------------------------

function Shopping.WithdrawFunction()
    local api = Core.API("ezBag")
    local fn = api and api.Withdraw
    return type(fn) == "function" and fn or nil
end

-- Offen? → Bank, Gildenbank (ezCores Inventar weiß es)
function Shopping.BankOpen()
    local inv = Core.Inventory
    if type(inv) ~= "table" then return false, false end
    return Core.Call(inv.IsBankOpen) == true, Core.Call(inv.IsGuildBankOpen) == true
end

-- Was ein Klick holen würde: { [itemID] = Anzahl } und Zeilen { itemID, name, count, lack } nach Name.
-- Je Material höchstens, was der Tasche fehlt (Bedarf aus Needs() minus Tasche) und was in den offenen Quellen liegt
-- (Bank: Stand des Besuchs; Gildenbank: die eigene, ezBag nimmt nur aus dem offenen Fach).
function Shopping.FromBank()
    local map, rows = {}, {}
    local bank, guild = Shopping.BankOpen()
    if not (bank or guild) then return map, rows end
    for itemID, lack in pairs(Shopping.BagNeeds()) do
        local stock = Data.Stock(itemID)
        local there = (bank and stock.bank or 0) + (guild and stock.guild or 0)
        local n = min(lack, there)
        if n > 0 then
            map[itemID] = n
            rows[#rows + 1] = { itemID = itemID, name = Data.ItemName(itemID), count = n, lack = lack }
        end
    end
    table.sort(rows, function(a, b) return a.name < b.name end)
    return map, rows
end

-- Knopf zeigen? (ezBag läuft und Bank oder Gildenbank ist offen, die Liste ist nicht leer)
function Shopping.CanWithdraw()
    if not Shopping.WithdrawFunction() or #List() == 0 then return false end
    local bank, guild = Shopping.BankOpen()
    return bank or guild
end

-- „Linnen (4×), Faden (1×)“
local function ItemsText(map)
    local parts = {}
    for itemID, n in pairs(map) do parts[#parts + 1] = L.WITHDRAW_ITEM:format(Data.ItemName(itemID), n) end
    table.sort(parts)
    return table.concat(parts, ", ")
end
Shopping.ItemsText = ItemsText

-- Was der Tasche danach noch fehlt: Bedarf beim Start minus was kam (ezBag meldet, was es nicht holen konnte).
function Shopping.StillMissing(lackAtStart, planned, notFetched)
    local still = {}
    for itemID, lack in pairs(lackAtStart or EMPTY) do
        local got = (planned[itemID] or 0) - ((notFetched or EMPTY)[itemID] or 0)
        local left = lack - max(0, got)
        if left > 0 then still[itemID] = left end
    end
    return still
end

local function ReportLeft(still)
    if next(still) == nil then
        ns.Print(L.WITHDRAW_ALL_THERE)
    else
        ns.Print(L.WITHDRAW_STILL_MISSING:format(ItemsText(still)))
    end
end

local REASONS = { input = true, busy = true, combat = true, closed = true, nothing = true, full = true, limit = true }

-- Holt nach einer Rückfrage, was Shopping.FromBank nennt. → true, wenn ezBag den Auftrag begonnen hat (bzw. die
-- Rückfrage steht). Am Ende meldet ezCraft, was der Tasche für die Einkaufsliste noch fehlt.
function Shopping.Withdraw()
    local fn = Shopping.WithdrawFunction()
    if not fn then
        ns.Print(L.WITHDRAW_NO_BAG)
        return false
    end
    local map = Shopping.FromBank()
    if next(map) == nil then
        ns.Print(L.WITHDRAW_NOTHING)
        return false
    end
    Core.Confirm(L.WITHDRAW_CONFIRM:format(ItemsText(map)), function()
        local lack, planned = Shopping.BagNeeds(), Shopping.FromBank()   -- neu gelesen: inzwischen kann sich etwas ändern
        if next(planned) == nil then
            ns.Print(L.WITHDRAW_NOTHING)
            return
        end
        local ok, started, _, reason = pcall(fn, planned, function(missing)
            ReportLeft(Shopping.StillMissing(lack, planned, type(missing) == "table" and missing or EMPTY))
        end)
        if not ok then
            ns.Error(started, "ezBag.Withdraw")
            return
        end
        if started ~= true then
            local why = REASONS[reason] and L["WITHDRAW_WHY_" .. reason] or tostring(reason)
            ns.Print(L.WITHDRAW_NOT_STARTED:format(why))
        end
    end)
    return true
end

function Shopping.Print()
    local list = List()
    if #list == 0 then
        ns.Print(L.SHOP_EMPTY)
        return
    end
    ns.Print(L.SHOP_HEAD)
    for _, entry in ipairs(list) do ns.Print(L.SHOP_LINE_RECIPE:format(entry.count, Shopping.Name(entry))) end
    local gatherOn = ns.Enabled("gatherHint")
    for _, row in ipairs(Shopping.Totals()) do
        local line = L.SHOP_LINE_ITEM:format(row.name, min(row.have, row.need), row.need)
        local gather = gatherOn and row.missing > 0 and Data.Gather(row.itemID)
        if gather and gather.here > 0 then line = line .. " – " .. L.GATHER_HERE end
        ns.Print(line)
    end
end

---------------------------------------------------------------------------
-- ezAuction: Einkaufen über dessen Einkaufslisten
---------------------------------------------------------------------------

function Shopping.AuctionFunction()
    local api = Core.API("ezAuction")
    local fn = api and api.AddShoppingList
    return type(fn) == "function" and fn or nil
end

-- Übergibt das Fehlende aus Material-Zeilen (Data.Materials oder Shopping.Totals) als Liste listName an ezAuction;
-- eine Liste gleichen Namens wird ersetzt. Rückgabe: true bei Erfolg.
function Shopping.SendRowsToAuction(listName, rows)
    local fn = Shopping.AuctionFunction()
    if not fn then
        ns.Print(L.SHOP_NO_AUCTION)
        return false
    end
    local items = {}
    for _, row in ipairs(rows or EMPTY) do
        if (row.missing or 0) > 0 then
            -- name dient ezAuction als Suchbegriff; ein Platzhalter „#itemID“ (noch nicht geladen) bleibt weg.
            local name = type(row.name) == "string" and not row.name:find("^#") and row.name or nil
            items[#items + 1] = { itemID = row.itemID, count = row.missing, name = name }
        end
    end
    if #items == 0 then
        ns.Print(L.SHOP_NOTHING_MISSING)
        return false
    end
    local ok, name, added = pcall(fn, listName, items, true)
    if not ok then
        ns.Error(name, "ezAuction.AddShoppingList")
        return false
    end
    if type(name) ~= "string" then
        ns.Print(L.SHOP_AUCTION_NOT_READY)
        return false
    end
    ns.Print(L.SHOP_TO_AUCTION:format(tonumber(added) or #items, name))
    return true
end

-- Das Fehlende der ganzen Einkaufsliste als Liste „ezCraft“.
function Shopping.SendToAuction()
    return Shopping.SendRowsToAuction(L.SHOP_AUCTION_LIST, Shopping.Totals())
end

-- Das Fehlende eines Rezepts (Menge wie im Feld „Herstellen“) als Liste „Beruf: Rezept“.
function Shopping.SendRecipeToAuction(recipe, quantity)
    if not recipe then return false end
    local rows = Data.Materials(recipe, quantity)
    local prefix = Data.ProfessionName() or L.TITLE
    return Shopping.SendRowsToAuction(L.SHOP_AUCTION_RECIPE:format(prefix, recipe.name), rows)
end

---------------------------------------------------------------------------
-- Tooltip-Zeile an Material, das auf der Liste steht
---------------------------------------------------------------------------

-- Immer an seit der Einstellungs-Prüfung vom 19.11.2026 (Nr. 22): erscheint nur an Material auf der eigenen Liste.
Core.Tooltip.AddItemSection("ezCraft.shopping", 30, function(tooltip, itemID)
    local need = Shopping.NeedFor(itemID)
    if need <= 0 then return end
    local have = Data.Have(Data.Stock(itemID))
    Core.Tooltip.Gap(tooltip)   -- ezCores einer Trenner (Spielbefund 18.11.2026 „auch hier fehlender abstand“)
    ns.TipLine(tooltip, L.TIP_SHOPPING:format(min(have, need), need), have >= need and "good" or "normal")
end, ADDON)

---------------------------------------------------------------------------
-- Schnittstelle für andere Module
---------------------------------------------------------------------------

ns.API.ShoppingList = function() return Shopping.MissingMap() end

-- Gesamtbedarf der Einkaufsliste je Gegenstand (V-144) – auch das, was schon vorhanden ist.
ns.API.Needs = function() return Shopping.Needs() end

ns.On("TRADE_SKILL_SHOW", Shopping.Invalidate)
ns.On("TRADE_SKILL_LIST_UPDATE", Shopping.Invalidate)
ns.On("TRADE_SKILL_CLOSE", Shopping.Invalidate)
Core.Listen("RECIPES_CHANGED", Shopping.Invalidate, ADDON)

ns.API.ShoppingRecipes = function()
    local out = {}
    for _, entry in ipairs(List()) do
        out[#out + 1] = { recipeID = entry.id, name = Shopping.Name(entry), count = entry.count }
    end
    return out
end

ns.API.AddRecipe = function(recipeID, count)
    return Shopping.Add(Data.Recipe(recipeID), count)
end
