local ADDON, ns = ...
local L = ns.L
local Core = ezCore
local Data = ns.Data

--[[
    Listen in ezCraft (seit dem 21.11.2026 ezCores gemeinsame Listen, Core.Lists – dieselben wie in ezAuction;
    Entscheidung des Nutzers „Ein Speicher in ezCore (Empfohlen)“). Vorher eine eigene Einkaufsliste aus Rezepten
    (ezCraftDB.shopping); sie wird einmal zur Liste „ezCraft“ (Shopping.Adopt, Merker ezCraftDB.ezCoreDB.migrated.listsFromEzCraft) und
    bleibt als Rückfall liegen.
      Gewählte Liste   ezCraftDB.window.list (Name); ohne Wahl die erste Liste. „Auf die Liste“ legt ein Rezept in die
                       gewählte (fehlt jede Liste, entsteht „ezCraft“).
      Einträge         Rezepte ({ recipe, count, buy }) und Gegenstände ({ itemID, count }) – siehe Core.Lists
    Name, Symbol, Produkt und Zutaten liest ezCraft jedes Mal frisch (Data.Recipe: offenes Berufefenster, sonst das
    Rezept-Wissen von ezCore) – ezCraft meldet sich dafür als Anbieter bei Core.Lists an (auch für „vorhanden“ nach den
    Einstellungen, womit ezAuction das fehlende Material sucht).
    „Vorhanden“ zählt wie im Berufefenster nach den Einstellungen (Tasche immer, Bank, Post, Gildenbank, Twinks).
    Fehlendes, das sich im aktuellen Gebiet sammeln lässt, heißt „hier sammelbar“ (Data.Gather, ezCore.Gathering – eigene
    Ernten „bei dir“ zuerst); im Seitenteil führt der Kartenknopf „Nächste Fundorte“ zur Weltkarte (SAM-24, Panel.lua).

    Für andere Module (ezCore.API("ezCraft")):
      ShoppingList()        → { [itemID] = fehlende Anzahl } über alle Listen
      Needs()               → { [itemID] = Gesamtbedarf } über alle Listen (auch was schon da ist – z. B. damit ezBag
                              oder ezMerchant Material der Listen nicht als Plunder verkaufen; V-144)
      ShoppingRecipes()     → { { recipeID, name, count }, … } (alle Listen)
      AddRecipe(recipeID, n) → true, neue Anzahl (gewählte Liste)
    Nachricht EZCRAFT_SHOPPING_CHANGED (ezCore.Listen) bei jeder Änderung einer Liste (ezCores LISTS_CHANGED).
    Einkaufen über ezAuction: die Listen sind dieselben – ezAuction sucht bei Rezepten das fehlende Material.
]]

local Shopping = {}
ns.Shopping = Shopping

local floor, max, min = math.floor, math.max, math.min
local EMPTY = {}

local function Lists() return Core.Lists end

-- Gewählte Liste (Tabelle aus Core.Lists) oder nil, wenn es keine gibt: die gemerkte, sonst „ezCraft“, sonst die
-- erste änderbare, sonst die erste (Review 21.11.2026: nicht still eine Liste mit Quelle oder eine fremde Liste).
function Shopping.Selected()
    local lists = Lists()
    if not lists then return nil end
    local name = ns.db and ns.db.window.list
    local list = name and lists.Find(name)
    if list then return list end
    list = lists.Find(L.SHOP_AUCTION_LIST)
    if list then return list end
    for _, other in ipairs(lists.All()) do
        if lists.Editable(other) then return other end
    end
    return lists.All()[1]
end

-- Liste wählen (Tabelle oder Name). → true, wenn es sie gibt
function Shopping.Select(list)
    local lists = Lists()
    if type(list) == "string" and lists then list = lists.Find(list) end
    if type(list) ~= "table" or not ns.db then return false end
    ns.db.window.list = list.name
    Shopping.Invalidate()
    ns.Fire("SHOPPING_CHANGED")
    return true
end

-- Liste für „Auf die Liste“ und „Hinzufügen“: die gewählte, wenn sie änderbar ist, sonst „ezCraft“ (änderbar; wird
-- angelegt). → Liste oder nil vor dem Laden
function Shopping.Target()
    local lists = Lists()
    if not lists then return nil end
    local list = Shopping.Selected()
    if list and lists.Editable(list) then return list end
    list = lists.Find(L.SHOP_AUCTION_LIST)
    if not (list and lists.Editable(list)) then list = lists.Create(L.SHOP_AUCTION_LIST) end
    if list and ns.db then ns.db.window.list = list.name end
    return list
end

local function List()
    local list = Shopping.Selected()
    return list and list.items or EMPTY
end

-- Gesamtbedarf der gewählten Liste, einmal gerechnet (V-145: vorher las jeder Item-Tooltip alle Rezepte neu).
-- Gilt, bis sich eine Liste oder die Rezepte ändern.
local needCache

function Shopping.Invalidate()
    needCache = nil
    if Lists() then Lists().Invalidate() end
end

-- Jede Änderung einer Liste (ezCores LISTS_CHANGED): eigene Nachricht und die alte (Alerts.lua).
local function Changed(list, oldName)
    -- Umbenannt (ezAuction, Durchsicht 24.11.2026): Die gemerkte Liste bleibt gewählt.
    local window = ns.db and ns.db.window
    if type(oldName) == "string" and type(list) == "table" and type(window) == "table" and type(window.list) == "string"
        and window.list:lower() == oldName:lower() then
        window.list = list.name
    end
    needCache = nil
    ns.Fire("SHOPPING_CHANGED")
    Core.Fire("EZCRAFT_SHOPPING_CHANGED")
end
Core.Listen("LISTS_CHANGED", Changed, ADDON)

-- Eintrag des Rezepts in der gewählten Liste und sein Index.
local function Find(recipeID)
    for index, entry in ipairs(List()) do
        if entry.recipe == recipeID then return entry, index end
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

-- Einmal: die alte Einkaufsliste (ezCraftDB.shopping) wird die gemeinsame Liste „ezCraft“ (Entscheidung des Nutzers
-- vom 21.11.2026). Die alte Tabelle bleibt unangetastet liegen. Merker ezCoreDB.migrated.listsFromEzCraft – im selben
-- Speicher wie die Listen (Review 21.11.2026: geht ezCoreDB verloren, wird erneut übernommen). → Zahl übernommener Rezepte
Shopping.ADOPT_FLAG = "listsFromEzCraft"
function Shopping.Adopt(db)
    local lists, core = Lists(), Core.db
    if not (lists and type(db) == "table" and type(core) == "table") then return 0 end
    if type(core.migrated) ~= "table" then core.migrated = {} end
    return Core.MigrateOnce(core.migrated, Shopping.ADOPT_FLAG, function()
        local items = {}
        for _, entry in ipairs(type(db.shopping) == "table" and db.shopping or EMPTY) do
            local id = type(entry) == "table" and Core.Num(entry.id)
            if id then items[#items + 1] = { recipe = id, count = max(1, floor(Core.Num(entry.count) or 1)) } end
        end
        if #items == 0 then return 0 end
        local _, created = lists.Adopt({ { name = L.SHOP_AUCTION_LIST, items = items } })
        if created and created[1] and type(db.window) == "table" and not db.window.list then db.window.list = created[1].name end
        return #items
    end) or 0
end

-- Rezept eines Eintrags, frisch gelesen (nil bei Gegenständen und wenn weder Fenster noch Rezept-Wissen es kennen).
function Shopping.Recipe(entry)
    return entry and entry.recipe and Data.Recipe(entry.recipe) or nil
end

-- Zutaten eines Eintrags: { [itemID] = Anzahl je Herstellung }.
function Shopping.Reagents(entry)
    local recipe = Shopping.Recipe(entry)
    local r = {}
    for _, reagent in ipairs(recipe and recipe.reagents or EMPTY) do r[reagent.itemID] = reagent.count end
    return r
end

-- Name und Symbol eines Eintrags (ezCores Core.Lists.Label/Icon); unbekannte Rezepte heißen „#recipeID“.
function Shopping.Name(entry)
    if Lists() then return Lists().Label(entry) end
    return "#" .. tostring(entry and (entry.recipe or entry.itemID))
end

function Shopping.Icon(entry)
    return Lists() and Lists().Icon(entry) or nil
end

-- Einträge der gewählten Liste (Rezepte und Gegenstände).
function Shopping.Entries() return List() end

-- Rezept (aus Data.Recipe) mit Menge in die gewählte Liste; dasselbe Rezept wird zusammengezählt. → true, Anzahl
function Shopping.Add(recipe, quantity)
    if not (recipe and recipe.recipeID and ns.db) then return false end
    local list = Shopping.Target()
    if not (list and Lists().Editable(list)) then return false end
    local entry = Lists().AddRecipe(list, recipe.recipeID, max(1, floor(tonumber(quantity) or 1)))
    if not entry then return false end
    return true, entry.count, list.name
end

-- Gegenstand, Link oder Rezept-Link (Eingabefeld, Shift-Klick) in die gewählte Liste. → Eintrag oder nil
function Shopping.AddItem(value)
    local list = Shopping.Target()
    if not (list and Lists().Editable(list)) then return nil end
    return Lists().AddEntry(list, value)
end

-- Anzahl eines Rezepts der gewählten Liste setzen; 0 oder weniger entfernt den Eintrag.
function Shopping.SetCount(recipeID, count)
    local _, index = Find(recipeID)
    if not index then return false end
    return Lists().SetCount(Shopping.Selected(), index, count)
end

function Shopping.Remove(recipeID) return Shopping.SetCount(recipeID, 0) end

-- Zeile index der gewählten Liste: Menge setzen (0 entfernt) bzw. entfernen.
function Shopping.SetEntryCount(index, count)
    local list = Shopping.Selected()
    return list ~= nil and Lists().SetCount(list, index, count)
end

function Shopping.RemoveEntry(index)
    local list = Shopping.Selected()
    return list ~= nil and Lists().RemoveEntry(list, index)
end

-- Rezept: im Auktionshaus Material (ab Werk) oder den Gegenstand selbst suchen.
function Shopping.ToggleBuy(index)
    local list = Shopping.Selected()
    local entry = list and list.items[index]
    return entry ~= nil and Lists().SetBuy(list, index, not entry.buy)
end

-- Gewählte Liste leeren (die Liste bleibt).
function Shopping.Clear()
    local list = Shopping.Selected()
    if not list then return end
    wipe(list.items)
    Lists().Changed(list)
end

-- Gewählte Liste leeren nach Rückfrage – ein Weg für die Knöpfe (Einstellungen, Seitenteil) und „/ezcraft leeren“
-- (T9-10). announce: danach „Liste geleert.“ im Chat (der Befehl hat sonst keine sichtbare Antwort).
function Shopping.AskClear(announce)
    local list = Shopping.Selected()
    if not (list and Lists().Editable(list)) then
        ns.Print(list and L.LIST_SOURCE_PANEL or L.SHOP_EMPTY)
        return nil
    end
    return Core.Confirm(L.SHOP_CLEAR_CONFIRM:format(list.name), function()
        Shopping.Clear()
        if announce then ns.Print(L.SHOP_CLEARED) end
    end)
end

---------------------------------------------------------------------------
-- Listen anlegen, umbenennen, löschen (Knöpfe in der Ansicht „Listen“)
---------------------------------------------------------------------------

function Shopping.Create(name)
    local list = Lists() and Lists().Create(name)
    if list then Shopping.Select(list) end
    return list
end

function Shopping.AskCreate()
    return Core.AskText(L.LIST_NEW_PROMPT, "", function(text) Shopping.Create(text) end, 40)
end

-- → true, Name | false
function Shopping.Rename(list, name)
    local ok, newName = Lists().Rename(list, name)
    if ok then
        if ns.db then ns.db.window.list = newName end
        ns.Fire("SHOPPING_CHANGED")
    else
        ns.Print(L.LIST_RENAME_TAKEN:format(type(name) == "string" and name or ""))
    end
    return ok, newName
end

function Shopping.AskRename()
    local list = Shopping.Selected()
    if not list then return nil end
    return Core.AskText(L.LIST_RENAME_PROMPT:format(list.name), list.name, function(text) Shopping.Rename(list, text) end, 40)
end

function Shopping.Delete(list)
    if not (list and Lists().Delete(list)) then return false end
    if ns.db then ns.db.window.list = nil end
    Shopping.Invalidate()
    ns.Fire("SHOPPING_CHANGED")
    return true
end

function Shopping.AskDelete()
    local list = Shopping.Selected()
    if not list then return nil end
    return Core.Confirm(L.LIST_DELETE_CONFIRM:format(list.name), function() Shopping.Delete(list) end, { alert = true })
end

---------------------------------------------------------------------------
-- Bedarf
---------------------------------------------------------------------------

-- Bedarf der gewählten Liste (Rezepte: Zutaten × Anzahl; Gegenstände mit Menge).
local function NeedMap()
    if needCache then return needCache end
    local need = Lists() and Lists().Needs(Shopping.Selected() or EMPTY) or {}
    if ns.db then needCache = need end   -- vor dem Laden der Datenbank nichts merken
    return need
end

-- Gesamtbedarf { [itemID] = Anzahl } der gewählten Liste (eine Kopie: der Aufrufer darf sie verändern).
function Shopping.Needs()
    local need = {}
    for itemID, n in pairs(NeedMap()) do need[itemID] = n end
    return need
end

-- Bedarf eines Gegenstands über alle Listen (Tooltip, Schutz vor dem Verkaufen).
function Shopping.NeedFor(itemID)
    return Lists() and Lists().NeedFor(itemID) or 0
end

-- Gesamtbedarf aller Listen (Schnittstelle Needs, V-144).
function Shopping.AllNeeds()
    return Lists() and Lists().Needs() or {}
end

-- Zeilen { itemID, name, icon, need, stock, have, missing }: fehlendes zuerst, dann nach Namen. needs: Bedarf (ohne
-- Angabe die gewählte Liste).
function Shopping.Totals(S, needs)
    local rows = {}
    for itemID, need in pairs(needs or Shopping.Needs()) do
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

function Shopping.MissingMap(S, needs)
    local map = {}
    for _, row in ipairs(Shopping.Totals(S, needs)) do
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

-- Anbieter für Core.Lists: Rezepte aus dem offenen Berufefenster bzw. dem Rezept-Wissen, „vorhanden“ nach den
-- Einstellungen (damit ezAuction bei Rezepten genau das Fehlende sucht).
function Shopping.RecipeForLists(recipeID)
    local recipe = Data.Recipe(recipeID)
    if not recipe then return nil end
    local reagents = {}
    for _, r in ipairs(recipe.reagents or EMPTY) do
        local id, n = Core.Num(r.itemID), Core.Num(r.count)
        if id and n then reagents[id] = (reagents[id] or 0) + n end
    end
    return { name = recipe.name, icon = recipe.icon or (recipe.product and Data.ItemIcon(recipe.product)) or nil,
        product = recipe.product, reagents = reagents }
end
if Core.Lists then
    Core.Lists.SetProvider({ recipe = Shopping.RecipeForLists,
        have = function(itemID) return Data.Have(Data.Stock(itemID)) end }, ADDON)
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

-- Statuszeile: Zahl der Listen, gewählte Liste und ihre Einträge.
function Shopping.StatusLine()
    local list = Shopping.Selected()
    return L.STATUS_SHOPPING:format(Lists() and #Lists().All() or 0, list and list.name or "–", list and #list.items or 0)
end

-- „2× Leinenhemd“ (Rezept), „20× Leinenstoff“ bzw. „Leinenstoff“ (Gegenstand mit bzw. ohne Menge)
function Shopping.EntryText(entry)
    local name = Shopping.Name(entry)
    if entry.count then return L.SHOP_LINE_RECIPE:format(entry.count, name) end
    return name
end

function Shopping.Print()
    local list = List()
    if #list == 0 then
        ns.Print(L.SHOP_EMPTY)
        return
    end
    ns.Print(L.SHOP_HEAD:format(Shopping.Selected().name))
    for _, entry in ipairs(list) do ns.Print(Shopping.EntryText(entry)) end
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

-- Ist das Auktionshaus offen (ezCores Core.AuctionHouseOpen)? Der Knopf „Auktionshaus“ am Rezept sucht nur dann.
function Shopping.AuctionOpen()
    return type(Core.AuctionHouseOpen) == "function" and Core.AuctionHouseOpen() == true
end

-- ezAuctions Suche ohne gespeicherte Liste (API.SearchItems) oder nil
function Shopping.SearchFunction()
    local api = Core.API("ezAuction")
    local fn = api and api.SearchItems
    return type(fn) == "function" and fn or nil
end

-- Bei offenem Auktionshaus die Liste dort gleich suchen (ezAuctions ShowList mit search; Wunsch des Nutzers vom
-- 21.11.2026: „der button auktionshaus muss bei geöffneten auktionshaus direkt die gegenstände suchen“). Ohne offenes
-- Auktionshaus oder ohne die Schnittstelle: nichts. → true, wenn ezAuction sucht
function Shopping.SearchInAuction(listName)
    local api = Core.API("ezAuction")
    local show = api and api.ShowList
    if type(show) ~= "function" or type(listName) ~= "string" then return false end
    local ok, shown = pcall(show, listName, true)
    if not ok then
        ns.Error(shown, "ezAuction.ShowList")
        return false
    end
    if shown then ns.Print(L.SHOP_AH_SEARCHING:format(listName)) end
    return shown == true
end

-- Die gewählte Liste im Auktionshaus: sie ist dieselbe wie dort (Core.Lists) – nichts wird kopiert. Bei offenem
-- Auktionshaus sucht ezAuction sie sofort, sonst sagt ezCraft, wo sie steht.
function Shopping.SendToAuction()
    local list = Shopping.Selected()
    if not list then return false end
    local api = Core.API("ezAuction")
    if Shopping.SearchInAuction(list.name) then return true end
    if not api then
        ns.Print(L.SHOP_NO_AUCTION)
        return false
    end
    ns.Print(L.SHOP_IN_AUCTION:format(list.name))
    return true
end

-- Knopf „Auktionshaus“ am Rezept: jede Zutat (Menge wie im Feld „Herstellen“, abzüglich der Tasche) sofort im Auktionshaus suchen, ohne
-- eine Liste zu speichern (Entscheidung des Nutzers vom 21.11.2026 „Nein, sofort suchen (Empfohlen)“; vorher legte
-- er eine Liste „Beruf: Rezept“ an). Der Name „Beruf: Rezept“ steht in Blizzards Ergebnisleiste. → true, wenn gesucht
-- label (frei): Name in Blizzards Ergebnisleiste; ohne „Beruf: Rezept“ des offenen Berufs.
function Shopping.SendRecipeToAuction(recipe, quantity, label)
    if not recipe then return false end
    local fn = Shopping.SearchFunction()
    if not fn then
        ns.Print(L.SHOP_NO_AUCTION)
        return false
    end
    -- jede Zutat, auch die vorhandene (Wunsch des Nutzers vom 21.11.2026: „zudem soll es mir im ah auch die mats
    -- anzeigen die ich schon habe“); Menge ist, was in der Tasche fehlt – reicht die Tasche, ohne Menge
    local items = {}
    for _, row in ipairs(Data.Materials(recipe, quantity)) do
        -- name dient ezAuction als Suchbegriff; ein Platzhalter „#itemID“ (noch nicht geladen) bleibt weg.
        local name = type(row.name) == "string" and not row.name:find("^#") and row.name or nil
        local lack = (row.need or 0) - ((row.stock and row.stock.bags) or 0)
        items[#items + 1] = { itemID = row.itemID, count = lack > 0 and lack or nil, name = name }
    end
    if #items == 0 then
        ns.Print(L.SHOP_NO_MATERIAL)
        return false
    end
    label = label or Shopping.RecipeLabel(recipe)
    local ok, started, why = pcall(fn, label, items)
    if not ok then
        ns.Error(started, "ezAuction.SearchItems")
        return false
    end
    if not started then
        ns.Print(why == "closed" and L.SHOP_AH_CLOSED or L.SHOP_AH_BUSY)
        return false
    end
    ns.Print(L.SHOP_AH_SEARCHING_RECIPE:format(label))
    return true
end

-- „Beruf: Rezept“ für Blizzards Ergebnisleiste (Beruf des offenen Fensters, sonst „ezCraft“)
function Shopping.RecipeLabel(recipe)
    return L.SHOP_AUCTION_RECIPE:format(Data.ProfessionName() or L.TITLE, recipe and recipe.name or "?")
end

---------------------------------------------------------------------------
-- Vormerken für das Auktionshaus (Entscheidung des Nutzers vom 21.11.2026 „Vormerken (Empfohlen)“; Frage: „button
-- auktionshaus, kann dieser das auf öffnen wenn ich einfach vor dem auktionator stehe?“ – öffnen kann ein Addon es
-- nicht, Blizzards sichere Knöpfe kennen keine Aktion „mit NPC sprechen“). Bei geschlossenem Auktionshaus merkt der
-- Knopf „Auktionshaus“ das Rezept mit Menge vor; beim Öffnen des Auktionshauses sucht ezAuction dann jede Zutat
-- sofort (ohne gespeicherte Liste). Ein zweiter Klick auf dasselbe Rezept nimmt es zurück. Nur bis /reload.
---------------------------------------------------------------------------

local pending   -- { recipeID, quantity, name, label }

function Shopping.Pending() return pending end
function Shopping.ClearPending()
    if not pending then return end
    pending = nil
    ns.Fire("SHOPPING_CHANGED")
end

-- Vormerken bzw. zurücknehmen. → true, wenn jetzt vorgemerkt
function Shopping.TogglePending(recipe, quantity)
    if not (recipe and recipe.recipeID) then return false end
    if pending and pending.recipeID == recipe.recipeID then
        pending = nil
        ns.Print(L.SHOP_AH_UNQUEUED:format(recipe.name))
        ns.Fire("SHOPPING_CHANGED")
        return false
    end
    local replaced = pending and pending.name
    pending = { recipeID = recipe.recipeID, quantity = max(1, floor(tonumber(quantity) or 1)), name = recipe.name,
        label = Shopping.RecipeLabel(recipe) }
    -- ein Platz: ein anderes Rezept ersetzt das vorgemerkte – die Meldung sagt es (Review 21.11.2026)
    ns.Print(replaced and L.SHOP_AH_QUEUED_REPLACE:format(recipe.name, replaced) or L.SHOP_AH_QUEUED:format(recipe.name))
    ns.Fire("SHOPPING_CHANGED")
    return true
end

-- Das Vorgemerkte jetzt suchen (beim Öffnen des Auktionshauses). → true, wenn ezAuction sucht
-- Ist das Auktionshaus schon wieder zu, bleibt die Vormerkung für das nächste Öffnen.
function Shopping.RunPending()
    local p = pending
    if not p or not Shopping.AuctionOpen() then return false end
    pending = nil
    ns.Fire("SHOPPING_CHANGED")
    local recipe = Data.Recipe(p.recipeID)
    if not recipe then return false end
    return Shopping.SendRecipeToAuction(recipe, p.quantity, p.label)
end

-- kurz nach dem Öffnen, damit ezAuction und Blizzards Kaufen-Seite bereit sind
ns.On("AUCTION_HOUSE_SHOW", function()
    if pending and C_Timer and C_Timer.After then C_Timer.After(0.5, Shopping.RunPending) end
end)

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

-- Was über alle Listen fehlt { [itemID] = Anzahl }.
ns.API.ShoppingList = function() return Shopping.MissingMap(nil, Shopping.AllNeeds()) end

-- Gesamtbedarf aller Listen je Gegenstand (V-144) – auch das, was schon vorhanden ist.
ns.API.Needs = function() return Shopping.AllNeeds() end

ns.On("TRADE_SKILL_SHOW", Shopping.Invalidate)
ns.On("TRADE_SKILL_LIST_UPDATE", Shopping.Invalidate)
ns.On("TRADE_SKILL_CLOSE", Shopping.Invalidate)
Core.Listen("RECIPES_CHANGED", Shopping.Invalidate, ADDON)

ns.API.ShoppingRecipes = function()
    local out = {}
    for _, list in ipairs(Lists() and Lists().All() or EMPTY) do
        for _, entry in ipairs(list.items or EMPTY) do
            if entry.recipe then
                out[#out + 1] = { recipeID = entry.recipe, name = Shopping.Name(entry), count = entry.count, list = list.name }
            end
        end
    end
    return out
end

ns.API.AddRecipe = function(recipeID, count)
    return Shopping.Add(Data.Recipe(recipeID), count)
end
