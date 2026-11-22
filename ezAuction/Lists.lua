local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Einkaufslisten – seit dem 21.11.2026 ezCores gemeinsame Listen (Core.Lists, ezCoreDB.lists; dieselben wie in ezCraft,
    Entscheidung des Nutzers „Ein Speicher in ezCore (Empfohlen)“). Die Funktionen hier sind dünne Weiterleitungen mit
    ezAuctions eigenen Feldern (Filter, Höchstpreis); ezAuctionDB.lists wird einmal übernommen (Lists.AdoptOld, Merker
    ezAuctionDB.ezCoreDB.migrated.listsFromEzAuction) und bleibt als Rückfall liegen. Neu: hergestellte Gegenstände (entry.recipe) – gesucht
    wird ihr fehlendes Material, mit entry.buy der Gegenstand selbst (Lists.SearchEntries).
    Form wie bisher (für alle Charaktere gleich):
      { name = "Kräuter", items = { entry, … } }
    entry = { text = Suchbegriff bzw. Name, itemID = nil|Zahl, exact = true|nil, count = nil|Zahl,
              minLevel, maxLevel, quality, category, maxPrice = nil|… }   (Filter und Höchstpreis: AH-09, unten)
      - mit itemID: sucht genau diesen Gegenstand (Name als Suchbegriff, Treffer nach itemID)
      - Text in Anführungszeichen: genau dieser Name; sonst wie Blizzards Suchfeld
      Einträge von früher ohne Filter bleiben gültig; Lists.Migrate prüft beim Anmelden jeden gespeicherten Eintrag.
    Andere Module legen Listen über ezCore.API("ezAuction").AddShoppingList an (z. B. ezCraft: Material eines Rezepts).

    Listen mit Quelle (list.source) speichern keinen eigenen Stand, sondern werden aus ihrer Quelle neu gebaut –
    bei jeder Änderung der Quelle, beim Anmelden, beim Öffnen des Auktionshauses und vor jeder Suche:
      books    „Bibliotheksbücher“: fehlende Bücher dieses Charakters (ezCore.Collections, BOOKS_CHANGED)
    (Bis 21.11.2026 gab es die Quelle „ezCraft“ als Kopie von ezCrafts Einkaufsliste; sie ist jetzt eine gemeinsame
    Liste mit Rezepten und wird beim Übernehmen übergangen.)
    Angelegt wird eine solche Liste auf Wunsch (Knopf „+ Fehlende Bücher“),
    gelöscht wie jede andere; umbenannt bleibt sie die Liste ihrer Quelle.
]]

local Lists = {}
ns.Lists = Lists

local function Shared() return Core.Lists end

-- Jede Änderung meldet ezCore (LISTS_CHANGED); ezAuction reicht sie als eigene Nachricht weiter (unten).
local function Changed(list) Shared().Changed(list) end

function Lists.All()
    return Shared() and Shared().All() or {}
end

function Lists.Find(name)
    return Shared().Find(name)
end

function Lists.IndexOf(list)
    return Shared().IndexOf(list)
end

local function Taken(name) return Lists.Find(name) ~= nil end

-- „Kräuter“, „Kräuter (2)“ … – ein freier Name (Core.UniqueName). base mit %d (z. B. „Liste %d“) zählt selbst
-- hoch: „Liste 1“, „Liste 2“ … („%.0s“ verschluckt den ersten Namen, %d bekommt die Zahl).
function Lists.UniqueName(base)
    base = Core.Trim(type(base) == "string" and not Core.IsSecret(base) and base or "")
    if base == "" then base = L.LIST_DEFAULT_NAME end
    if base:find("%%d") then
        local ok, first = pcall(string.format, base, 1)
        if ok then return Core.UniqueName(first, Taken, { format = "%.0s" .. base }) end
    end
    return Core.UniqueName(base, Taken)
end

function Lists.Create(name)
    local list = Shared().Create(Lists.UniqueName(name))
    return list
end

-- Rückgabe: true und der neue Name, oder false, wenn der Name leer oder schon vergeben ist.
function Lists.Rename(list, name)
    return Shared().Rename(list, name)
end

function Lists.Delete(list)
    return Shared().Delete(list)
end

-- itemID und Name aus einem Gegenstandslink („|Hitem:2589:…|h[Leinenstoff]|h“ oder „item:2589“).
-- Nur Links: eine getippte Zahl bleibt ein Suchbegriff.
function Lists.ParseLink(link)
    if type(link) ~= "string" or Core.IsSecret(link) or not link:find("item:%d") then return nil end
    return Core.ItemID(link), Core.ItemName(link)
end

-- Name zur itemID; fehlen die Daten, lädt ezCore sie nach (dann nil).
local ItemNameOf = Core.ItemNameByID

-- Jede Form, die Spieler oder andere Module liefern, wird zu einem Eintrag (nil, wenn nichts Brauchbares).
--   2589                                   itemID
--   "|cff…|Hitem:2589…|h[Leinenstoff]|h|r" Link
--   "Leinen" / "\"Leinenstoff\""           Suchbegriff / genau dieser Name
--   { itemID = 2589, count = 20 } / { text = "Leinen", exact = true } / { name = "…" }
--   { recipe = 2963, count = 2, buy = true }  hergestellter Gegenstand (ezCores Core.Lists)
function Lists.NormalizeEntry(value)
    return Shared().NormalizeEntry(value, Lists.CleanFilters)
end

-- Fügt einen Eintrag hinzu; derselbe Gegenstand bzw. Begriff wird zusammengelegt (Mengen addiert). Ein Suchbegriff
-- ist nur mit denselben Filtern derselbe („Erz“ in „Handwerkswaren“ und „Erz“ ohne Kategorie bleiben zwei Einträge).
-- Rückgabe: der Eintrag in der Liste, oder nil.
function Lists.AddEntry(list, value)
    return Shared().AddEntry(list, value, { extra = Lists.CleanFilters, key = Lists.FilterKey })
end

function Lists.RemoveEntry(list, index)
    return Shared().RemoveEntry(list, index)
end

-- Einträge zum Suchen: hergestellte Gegenstände als ihr fehlendes Material bzw. (buy) der Gegenstand selbst
-- (ezCores Core.Lists.SearchEntries – über die ganze Liste gerechnet: dasselbe Material mehrerer Rezepte zählt
-- zusammen, der Vorrat einmal; Review 21.11.2026); only (Index der Zeile) nur diese eine Zeile. Gemerkt je Liste, bis
-- sich eine Liste oder der Bestand ändert, höchstens Lists.SEARCH_CACHE Sekunden (Buy.Wanted fragt je Ergebniszeile).
Lists.SEARCH_CACHE = 2
local searchCache = setmetatable({}, { __mode = "k" })
function Lists.SearchEntries(list, only)
    if type(list) ~= "table" then return {} end
    if only ~= nil then
        local entry = type(list.items) == "table" and list.items[only]
        if not entry then return {} end
        if entry.recipe then return Shared().SearchEntries({ items = { entry } }) end
        return { entry }
    end
    local now = GetTime and GetTime() or 0
    local cached = searchCache[list]
    if not (cached and now - cached.at >= 0 and now - cached.at < Lists.SEARCH_CACHE) then
        cached = { at = now, entries = Shared().SearchEntries(list) }
        searchCache[list] = cached
    end
    local copy = {}   -- der Aufrufer darf die Folge ändern (Search.Start merkt sie sich)
    for i, entry in ipairs(cached.entries) do copy[i] = entry end
    return copy
end
function Lists.ForgetSearch() wipe(searchCache) end

-- Suchbegriff für Blizzards Suche (Name des Gegenstands bzw. der Begriff).
function Lists.SearchText(entry)
    if entry.recipe and not entry.itemID then   -- hergestellt: Name des Produkts
        local info = Shared().Recipe(entry.recipe)
        local product = info and Core.Num(info.product)
        return product and ItemNameOf(product) or entry.text or (info and info.name)
    end
    if entry.itemID then
        local name = ItemNameOf(entry.itemID)
        if name then entry.text = name end
    end
    return entry.text
end

-- Anzeige in der Liste: Name, „genau“, Menge.
function Lists.EntryLabel(entry)
    if entry.recipe then   -- hergestellt: Name aus dem Rezept, dazu woran gesucht wird (Material oder Gegenstand)
        local text = Shared().Label(entry)
        if entry.count then text = L.EDITOR_COUNT:format(entry.count) .. " " .. text end
        return text .. " " .. (entry.buy and L.ENTRY_CRAFT_ITEM or L.ENTRY_CRAFT_MATERIAL)
    end
    local text = entry.text or (entry.itemID and ("#" .. entry.itemID)) or "?"
    if entry.exact and not entry.itemID then text = ('"%s"'):format(text) end
    if entry.count then text = L.EDITOR_COUNT:format(entry.count) .. " " .. text end
    return text
end

---------------------------------------------------------------------------
-- Filter und Höchstpreis je Eintrag (AH-09, Fertigstellungsplan Welle 12). Alle Felder sind freiwillig:
--   minLevel, maxLevel  benötigte Stufe von–bis (Blizzards Liste zeigt auf Forever die benötigte Stufe)
--   quality             ab dieser Qualität (1 = verbreitet … 6 = Artefakt)
--   category            { name = „Rüstung » Stoff“, filters = { { classID, subClassID, inventoryType } … },
--                         implicit = Zahl } – aus Blizzards Tabelle AuctionCategories, nur gelesen
--   maxPrice            Höchstpreis je Stück in Kupfer: Ergebniszeilen darüber tragen „über Höchstpreis“
-- Gesucht wird mit eigener Abfrage (Search.QueryFor); Blizzards Filterstand bleibt unberührt.
---------------------------------------------------------------------------

Lists.MAX_LEVEL = 999
Lists.QUALITY_MAX = 6
Lists.CATEGORY_FILTERS = 40   -- so viele Klassen-Filter je Kategorie übernimmt ein Eintrag höchstens
Lists.MAX_PRICE = 1e12        -- Kupfer (100 Millionen Gold)
Lists.NAME_LETTERS = 60       -- Name und Suchbegriff werden gekürzt (Blizzards Suchfeld nimmt ohnehin nicht mehr)
Lists.TEXT_LETTERS = 80

-- Ganze Zahl zwischen low und high oder nil.
local function Int(value, low, high)
    if type(value) == "string" and not Core.IsSecret(value) then value = tonumber(value) end
    value = Core.Num(value)
    if not value or value ~= value then return nil end
    value = math.floor(value)
    if value < low or value > high then return nil end
    return value
end

Lists.Int = Int   -- auch für den Suchverlauf (Search.lua)

local function PositiveInt(value) return Int(value, 1, 2 ^ 31) end

local function Cut(text, letters)
    if type(text) ~= "string" or Core.IsSecret(text) then return nil end
    -- ohne Steuerzeichen und „|“ (keine Farb- oder Link-Codes aus fremdem Text), UTF-8-sicher gekürzt
    text = Core.Trim(Core.TruncateChars(Core.Trim((text:gsub("[%c|]", ""))), letters))
    return text ~= "" and text or nil
end

-- Kategorie geprüft und als eigene Kopie (nie Blizzards Tabelle selbst); nil, wenn nichts Brauchbares darin ist.
function Lists.CleanCategory(value)
    if type(value) ~= "table" then return nil end
    local filters = {}
    for _, f in ipairs(type(value.filters) == "table" and value.filters or {}) do
        if #filters >= Lists.CATEGORY_FILTERS then break end
        local classID = type(f) == "table" and Int(f.classID, 0, 1e6)
        if classID then
            filters[#filters + 1] = { classID = classID, subClassID = Int(f.subClassID, 0, 1e6),
                inventoryType = Int(f.inventoryType, 0, 1e4) }
        end
    end
    local implicit = Int(value.implicit, 0, 1e4)
    if #filters == 0 and not implicit then return nil end
    return { name = Cut(value.name, Lists.TEXT_LETTERS), filters = filters[1] and filters or nil, implicit = implicit }
end

-- Übernimmt die Filter aus source nach target (geprüft; Unbrauchbares fällt weg). Rückgabe: target.
function Lists.CleanFilters(source, target)
    if type(source) ~= "table" or type(target) ~= "table" then return target end
    local low, high = Int(source.minLevel, 1, Lists.MAX_LEVEL), Int(source.maxLevel, 1, Lists.MAX_LEVEL)
    if low and high and low > high then low, high = high, low end
    target.minLevel, target.maxLevel = low, high
    target.quality = Int(source.quality, 1, Lists.QUALITY_MAX)
    target.category = Lists.CleanCategory(source.category)
    target.maxPrice = Int(source.maxPrice, 1, Lists.MAX_PRICE)
    return target
end

function Lists.HasFilters(entry)
    return type(entry) == "table" and (entry.minLevel or entry.maxLevel or entry.quality or entry.category) ~= nil
end

-- Kennung der Filter (für SameEntry); "" ohne Filter.
function Lists.FilterKey(entry)
    if not Lists.HasFilters(entry) then return "" end
    local category = entry.category
    local parts = { entry.minLevel or "", entry.maxLevel or "", entry.quality or "",
        category and (category.name or "") or "", category and category.implicit or "" }
    for _, f in ipairs(category and category.filters or {}) do
        parts[#parts + 1] = ("%s.%s.%s"):format(f.classID, f.subClassID or "", f.inventoryType or "")
    end
    return table.concat(parts, "|")
end

-- Name einer Qualität: Blizzards eigener Text (ITEM_QUALITY2_DESC …), sonst ezCores Rückfall – über ezCores Helfer
-- (Core.QualityName, Gesamtreview 18.11.2026, T16-6; vorher eine eigene Kopie samt Texten QUALITY_0 … in Locale.lua).
function Lists.QualityName(quality)
    return Core.QualityName(quality)
end

-- „Stufe 20–30“, „ab Stufe 20“, „bis Stufe 30“ oder nil.
function Lists.LevelText(low, high)
    if low and high then return L.FILTER_LEVELS:format(low, high) end
    if low then return L.FILTER_LEVEL_FROM:format(low) end
    if high then return L.FILTER_LEVEL_TO:format(high) end
    return nil
end

-- Die Filter eines Eintrags als Text für Editor, Tooltip und Filterzeile: „Rüstung » Stoff, Stufe 20–30, ab selten“;
-- withPrice: dazu „bis 5 g“. nil ohne Filter.
function Lists.FilterText(entry, withPrice)
    if type(entry) ~= "table" then return nil end
    local parts = {}
    if entry.category then parts[#parts + 1] = entry.category.name or L.FILTER_CATEGORY end
    parts[#parts + 1] = Lists.LevelText(entry.minLevel, entry.maxLevel)
    if entry.quality then parts[#parts + 1] = L.FILTER_QUALITY:format(Lists.QualityName(entry.quality)) end
    if withPrice and entry.maxPrice then parts[#parts + 1] = L.FILTER_MAX_PRICE:format(ns.Money(entry.maxPrice)) end
    if #parts == 0 then return nil end
    return table.concat(parts, ", ")
end

-- Filter eines Eintrags ändern: changes = { minLevel = …, category = false (= entfernen) … }; geprüft wie beim Laden.
-- Rückgabe: true, wenn der Eintrag zur Liste gehört.
function Lists.SetFilters(list, entry, changes)
    if not (list and entry and Lists.IndexOf(list)) then return false end
    local merged = { minLevel = entry.minLevel, maxLevel = entry.maxLevel, quality = entry.quality,
        category = entry.category, maxPrice = entry.maxPrice }
    for key, value in pairs(type(changes) == "table" and changes or {}) do
        if value == false then merged[key] = nil else merged[key] = value end
    end
    Lists.CleanFilters(merged, entry)
    -- „genau“ nur für Suchbegriffe (ein Gegenstand wird ohnehin genau gesucht)
    if type(changes) == "table" and changes.exact ~= nil and not entry.itemID then entry.exact = merged.exact == true or nil end
    Changed()
    return true
end

-- „20-30“, „20–30“, „20“ (genau diese Stufe), „-30“, „20-“ → min, max; "" → nil, nil (Filter weg); Unsinn → false.
function Lists.ParseLevels(text)
    if type(text) ~= "string" or Core.IsSecret(text) then return false end
    text = Core.Trim(text):gsub("–", "-"):gsub("%s+", "")
    if text == "" then return nil, nil end
    local a, b = text:match("^(%d*)%-(%d*)$")
    if not a then
        a = text:match("^(%d+)$")
        b = a
    end
    if not a then return false end
    local low, high = Int(a, 1, Lists.MAX_LEVEL), Int(b, 1, Lists.MAX_LEVEL)
    if (a ~= "" and not low) or (b ~= "" and not high) or (not low and not high) then return false end
    if low and high and low > high then low, high = high, low end
    return low, high
end

-- Betrag aus einem getippten Text: „5“ oder „5,5“ (Gold), „5g 20s 3c“, „20s“, „3k“ (Kupfer) → Kupfer; "" → nil;
-- Unsinn, 0 oder über Lists.MAX_PRICE → false. Die Rechnung steht einmal in ezCore (Core.ParseMoney, Welle 23a – sie
-- kennt dazu Blizzards Münzzeichen); hier nur die Obergrenze der Listen. Editor und Seitenteil rufen diesen Namen.
function Lists.ParseMoney(text)
    return Core.ParseMoney(text, Lists.MAX_PRICE)
end

-- Gespeicherte Einkaufslisten beim Anmelden prüfen (Einträge von früher bleiben gültig): kaputte Einträge fallen
-- weg, unbrauchbare Filter-Felder auch, alles andere bleibt, wie es ist. Rückgabe: Zahl der geänderten Einträge.
function Lists.Migrate()
    local changed = 0
    for _, list in ipairs(Lists.All()) do
        if type(list) == "table" and type(list.items) == "table" then
            for index = #list.items, 1, -1 do
                local entry = list.items[index]
                if type(entry) ~= "table" or (not Core.Num(entry.itemID) and type(entry.text) ~= "string"
                    and not Core.Num(entry.recipe)) then
                    table.remove(list.items, index)
                    changed = changed + 1
                else
                    local before = Lists.FilterKey(entry) .. "#" .. tostring(entry.maxPrice)
                    Lists.CleanFilters(entry, entry)
                    if Lists.FilterKey(entry) .. "#" .. tostring(entry.maxPrice) ~= before then changed = changed + 1 end
                end
            end
        end
    end
    return changed
end

-- Blizzards Kategorien zum Auswählen (nur gelesen, AuctionCategories aus Blizzard_AuctionData.lua): { { name,
-- filters, implicit, children } … }, höchstens drei Ebenen, ohne die WoW-Marke; nil ohne Blizzards Tabelle.
function Lists.CategoryTree()
    local root = rawget(_G, "AuctionCategories")
    if type(root) ~= "table" then return nil end
    local function IsToken(node)
        if type(node.HasFlag) ~= "function" then return false end
        local ok, flag = pcall(node.HasFlag, node, "WOW_TOKEN_FLAG")
        return ok and flag == true
    end
    local function Walk(nodes, depth)
        local out = {}
        for _, node in ipairs(nodes) do
            if type(node) == "table" and type(node.name) == "string" and not IsToken(node) then
                local item = { name = node.name, filters = node.filters, implicit = node.implicitFilter }
                if depth < 3 and type(node.subCategories) == "table" and #node.subCategories > 0 then
                    item.children = Walk(node.subCategories, depth + 1)
                end
                out[#out + 1] = item
            end
        end
        return out
    end
    return Walk(root, 1)
end

---------------------------------------------------------------------------
-- Kostenvoranschlag einer Liste (AH-10): „heute ≈ …, im Mittel ≈ …“ aus ezCores Prices.Stats – heute der Tiefstpreis
-- des heutigen Tags, im Mittel der Median der Tages-Tiefstpreise (14 Tage), je mal der Menge des Eintrags (ohne
-- Menge: 1 Stück). Ohne Preis zählen Suchbegriffe ohne Gegenstand und Gegenstände ohne Erfassung.
---------------------------------------------------------------------------

function Lists.Cost(list)
    local out = { today = 0, todayItems = 0, mean = 0, meanItems = 0, missing = 0, items = 0 }
    local prices = ns.Prices()
    local stats = prices and type(prices.Stats) == "function" and prices.Stats
    for _, entry in ipairs(type(list) == "table" and list.items or {}) do
        out.items = out.items + 1
        local itemID, qty = Core.Num(entry.itemID), Core.Num(entry.count) or 1
        local all = itemID and stats and Core.Call(stats, itemID)
        local mean = type(all) == "table" and Core.Num(all.median)
        if mean and mean > 0 then
            out.mean, out.meanItems = out.mean + mean * qty, out.meanItems + 1
            local day = Core.Call(stats, itemID, 1)
            local today = type(day) == "table" and Core.Num(day.low)
            if today and today > 0 then out.today, out.todayItems = out.today + today * qty, out.todayItems + 1 end
        else
            out.missing = out.missing + 1
        end
    end
    return out
end

-- Eine Zeile für Editor und Tooltip; nil für eine leere Liste.
function Lists.CostText(list)
    local cost = Lists.Cost(list)
    if cost.items == 0 then return nil end
    if cost.meanItems == 0 then return L.LIST_COST_NONE end
    local today
    if cost.todayItems == 0 then
        today = L.LIST_COST_TODAY_NONE
    elseif cost.todayItems < cost.meanItems then
        today = L.LIST_COST_TODAY_PART:format(ns.Money(cost.today), cost.todayItems, cost.meanItems)
    else
        today = L.LIST_COST_TODAY:format(ns.Money(cost.today))
    end
    local text = L.LIST_COST:format(today, L.LIST_COST_MEAN:format(ns.Money(cost.mean)))
    if cost.missing > 0 then text = text .. ", " .. Core.Plural(cost.missing, L.LIST_COST_MISSING_ONE, L.LIST_COST_MISSING_MANY) end
    return text .. " – " .. L.LIST_COST_SOURCE
end

---------------------------------------------------------------------------
-- Bestand aller Charaktere (Frage 3, entschieden am 13.11.2026: nur im Tooltip – die Zahl „12×“ in der Zeile
-- bleibt die eingetragene Menge)
---------------------------------------------------------------------------

-- Orte je Charakter in der Antwort von ezCore.Inventory.CountAll (Taschen, Bank, Post, angelegt).
Lists.STOCK_PLACES = { "bags", "bank", "mail", "equip" }

-- Wie oft ein Gegenstand schon da ist: bei allen Charakteren und in den gemerkten Gildenbanken –
-- ezCore.Inventory.CountAll, dieselbe Zählung wie in ezBag und ezCraft. Die eine Stelle, an der ezAuction den Bestand
-- zusammenzählt (Listen, Editor, Tooltip der Ergebniszeile). Rückgabe: { chars = n, guilds = n, most = n, part =
-- Teil des Charakters, place = Ort, reach = erreichbarer Teil } – most, part und place nennen den größten Teil an einem
-- Ort (part fehlt ohne Bestand bei Charakteren); nil ohne Gegenstand und ohne die Zählung von ezCore.
-- reach (Gesamtreview 18.11.2026, T4-NR5): ezCores eine Regel „erreichbarer Bestand“ (Inventory.Reachable, wie ezCraft):
-- Taschen, Bank und Post dieses Charakters und der Twinks, die Post von ihm bekommen können, dazu die eigene Gildenbank.
-- Angezeigt wird weiter der Bestand aller Charaktere (Frage 3 vom 13.11.2026); „genug da“, „fehlt“, der Bedarf und die
-- Warnung vor Doppelkauf rechnen mit dem erreichbaren Teil (Lists.Reach).
function Lists.StockOf(itemID)
    local Inventory = Core.Inventory
    itemID = Core.Num(itemID)
    if not (itemID and type(Inventory) == "table" and type(Inventory.CountAll) == "function") then return nil end
    local all = Core.Call(Inventory.CountAll, itemID)
    if type(all) ~= "table" then return nil end
    local info = { chars = 0, guilds = 0, most = 0 }
    for _, part in ipairs(type(all.chars) == "table" and all.chars or {}) do
        if type(part) == "table" then
            info.chars = info.chars + (Core.Num(part.total) or 0)
            for _, place in ipairs(Lists.STOCK_PLACES) do
                local n = Core.Num(part[place]) or 0
                if n > info.most then info.most, info.part, info.place = n, part, place end
            end
        end
    end
    for _, part in ipairs(type(all.guilds) == "table" and all.guilds or {}) do
        info.guilds = info.guilds + (type(part) == "table" and Core.Num(part.total) or 0)
    end
    if type(Inventory.Reachable) == "function" then
        local reach = Core.Call(Inventory.Reachable, itemID, all)
        info.reach = type(reach) == "table" and Core.Num(reach.total) or nil
    end
    return info
end

-- Erreichbarer Bestand einer Angabe von Lists.StockOf (ohne ezCores Regel: alles Gezählte wie bisher).
function Lists.Reach(info)
    if type(info) ~= "table" then return nil end
    return Core.Num(info.reach) or ((Core.Num(info.chars) or 0) + (Core.Num(info.guilds) or 0))
end

-- Bestand zum Gegenstand eines Eintrags (Lists.StockOf). Rückgabe: Charaktere, Gildenbanken, die ganze Angabe;
-- nil für Suchbegriffe ohne Gegenstand und ohne die Zählung von ezCore.
function Lists.Stock(entry)
    local info = type(entry) == "table" and entry.itemID and Lists.StockOf(entry.itemID)
    if not info then return nil end
    return info.chars, info.guilds, info
end

-- Deckt der Bestand (have) die Menge des Eintrags? Nur bei eigenen Listen ohne Quelle – bei ezCraft ist die Menge
-- schon „fehlt noch n“. Rückgabe: true/false und die Menge.
function Lists.Covers(entry, list, have)
    local need = type(entry) == "table" and Core.Num(entry.count) or nil
    if not (need and list ~= nil and not Lists.CountIsMissing(list) and Core.Num(have)) then return false, need end
    return have >= need, need
end

-- Bestand eines Eintrags als Text: mit Menge „brauche 12, hast 4 (alle Charaktere), fehlt 8“, ohne Menge
-- „hast 4 (alle Charaktere)“; liegt etwas in einer Gildenbank, steht es dabei und zählt mit. Ist davon nicht alles
-- erreichbar (Lists.Reach: andere Fraktion, nicht erreichbarer Realm, angelegt, fremde Gildenbank), steht „erreichbar n“
-- dabei, und „fehlt“ bzw. „genug da“ rechnen damit (T4-NR5).
-- nil: Suchbegriff ohne Gegenstand, Eintrag ohne Menge und ohne Bestand (keine Zeile „0“ an jedem Eintrag),
-- und Listen mit Quelle – ezCrafts Menge ist schon „fehlt noch n“, die Bücher-Liste nennt nur, was fehlt.
-- extra (Tooltip der Ergebniszeile, AH-11): { info = schon gezählter Bestand, place = Ort hinter „hast …“,
-- warned = true (dann fehlt „genug da“, weil die Warnung vor Doppelkauf folgt) }.
function Lists.StockText(entry, list, extra)
    if list ~= nil and Lists.CountIsMissing(list) then return nil end
    local info = type(extra) == "table" and type(extra.info) == "table" and extra.info or nil
    local chars, guilds
    if info then chars, guilds = info.chars, info.guilds else chars, guilds, info = Lists.Stock(entry) end
    if not chars then return nil end
    local have = chars + guilds
    local reach = math.min(have, Lists.Reach(info) or have)
    local need = Core.Num(entry.count)
    if not need and have == 0 then return nil end
    local text = need and L.LIST_STOCK_NEED:format(need, chars) or L.LIST_STOCK_HAVE:format(chars)
    if extra and type(extra.place) == "string" then text = text .. extra.place end
    if guilds > 0 then text = text .. L.LIST_STOCK_GUILD:format(guilds) end
    if reach < have then text = text .. L.LIST_STOCK_REACH:format(reach) end
    if need then
        if reach < need then
            text = text .. L.LIST_STOCK_SHORT:format(need - reach)
        elseif not (extra and extra.warned) then
            text = text .. L.LIST_STOCK_ENOUGH
        end
    end
    return text
end

-- Bestandszeilen einer Liste für ihren Tooltip: { „Leinenstoff: brauche 12, hast 4 …“ … }, höchstens
-- Lists.STOCK_LINES; zweite Rückgabe: wie viele Einträge darüber hinaus eine Zeile hätten.
Lists.STOCK_LINES = 8
function Lists.StockLines(list)
    local lines, more = {}, 0
    for _, entry in ipairs(type(list) == "table" and list.items or {}) do
        local text = Lists.StockText(entry, list)
        if text then
            if #lines < Lists.STOCK_LINES then
                lines[#lines + 1] = L.LIST_STOCK_ENTRY:format(entry.text or ("#" .. tostring(entry.itemID)), text)
            else
                more = more + 1
            end
        end
    end
    return lines, more
end

-- Zutaten eines Rezepts aus dem Item-Wissen von ezCore: { { itemID, name, count }, … } oder nil.
function Lists.ReagentsOf(itemID)
    local K = Core.Knowledge
    local facts = itemID and K and K.Get and K.Get(itemID)
    local reagents = facts and facts.recipe and facts.recipe.reagents
    if type(reagents) ~= "table" or #reagents == 0 then return nil end
    return reagents
end

-- Ersetzt nichts: hängt die Zutaten als Einträge an (Mengen je Rezept, mal times).
function Lists.AddReagents(list, itemID, times)
    local reagents = Lists.ReagentsOf(itemID)
    if not reagents then return 0 end
    local added = 0
    for _, reagent in ipairs(reagents) do
        local value = reagent.itemID and { itemID = reagent.itemID, text = reagent.name } or { text = reagent.name, exact = true }
        if reagent.count then value.count = reagent.count * (times or 1) end
        if Lists.AddEntry(list, value) then added = added + 1 end
    end
    return added
end

-- Bibliotheksbücher aus dem Item-Wissen von ezCore (Core.Collections): die dieser Charakter noch nicht abgegeben
-- hat und nicht in der Tasche trägt, als Einträge { itemID, text, exact }; nil ohne Item-Wissen für Bücher.
function Lists.MissingBooks()
    local C = Core.Collections
    if not (C and type(C.Books) == "function") then return nil end
    local missing = {}
    for _, book in ipairs(Core.Call(C.Books) or {}) do
        local have = Core.Num(book.have) or 0
        if book.item and not book.done and have == 0 then
            missing[#missing + 1] = { itemID = book.item, text = book.name, exact = true }
        end
    end
    return missing
end

-- Quellen in fester Reihenfolge: key, Name der Liste, Einträge (nil = Quelle fehlt gerade).
Lists.SOURCES = {
    { key = "books", name = function() return L.LIST_BOOKS end, entries = function() return Lists.MissingBooks() end },
}

function Lists.Source(key)
    for _, source in ipairs(Lists.SOURCES) do
        if source.key == key then return source end
    end
    return nil
end

-- Die Liste einer Quelle (nil, solange es sie nicht gibt) – erkannt nur an ihrer Kennung list.source.
-- Eine von Hand angelegte Liste, die zufällig „ezCraft“ oder „Bibliotheksbücher“ heißt, bleibt die Liste des
-- Spielers (Vollprüfung V-157); die Quelle bekommt dann eine eigene („ezCraft (2)“).
function Lists.OfSource(key)
    local source = Lists.Source(key)
    if not source then return nil end
    for _, list in ipairs(Lists.All()) do
        if list.source == key then return list end
    end
    return nil
end

-- Einmalige Übernahme (Merker ezAuctionDB.ui.sourcesAdopted): Listen aus der Zeit vor der Kennung – als Kopie
-- angelegt und nur am Namen zu erkennen – werden zur Liste ihrer Quelle. Rückgabe: Anzahl übernommener Listen.
function Lists.AdoptByName()
    local ui = ns.db and ns.db.ui
    if not ui or ui.sourcesAdopted then return 0 end
    ui.sourcesAdopted = true
    local adopted = 0
    for _, source in ipairs(Lists.SOURCES) do
        if not Lists.OfSource(source.key) then
            local list = Lists.Find(source.name())
            if list and list.source == nil then
                list.source = source.key
                adopted = adopted + 1
            end
        end
    end
    return adopted
end

-- Einmal: ezAuctions alte Listen (ezAuctionDB.lists) in ezCores gemeinsame Listen; die alte Tabelle bleibt liegen.
-- Die frühere Kopie „ezCraft“ (Quelle ezCraft) wird übergangen – ezCraft bringt seine Liste selbst (mit Rezepten).
-- → Zahl übernommener Listen
-- Merker ezCoreDB.migrated.listsFromEzAuction – im selben Speicher wie die Listen (Review 21.11.2026). Vorher bekommt
-- eine alte Kopie „Bibliotheksbücher“ ohne Kennung ihre Quelle (wie AdoptByName, nur in der alten Tabelle); danach
-- gilt die Übernahme über den Namen als gelaufen – sie fände sonst später Listen aus ezCraft.
Lists.ADOPT_FLAG = "listsFromEzAuction"
function Lists.AdoptOld()
    local db, core = ns.db, Core.db
    if not (db and type(db.ui) == "table" and Shared() and type(core) == "table") then return 0 end
    if type(core.migrated) ~= "table" then core.migrated = {} end
    return Core.MigrateOnce(core.migrated, Lists.ADOPT_FLAG, function()
        local old = type(db.lists) == "table" and db.lists or {}
        if not db.ui.sourcesAdopted then
            local hasBooks = false
            for _, list in ipairs(old) do if type(list) == "table" and list.source == "books" then hasBooks = true end end
            for _, list in ipairs(old) do
                if not hasBooks and type(list) == "table" and list.source == nil and type(list.name) == "string"
                    and list.name:lower() == L.LIST_BOOKS:lower() then
                    list.source, hasBooks = "books", true
                end
            end
            db.ui.sourcesAdopted = true
        end
        return (Shared().Adopt(old, { extra = Lists.CleanFilters, key = Lists.FilterKey,
            skip = function(list) return list.source == "ezCraft" end }))
    end) or 0
end

-- Quelle einer Liste (key) oder nil.
function Lists.SourceOf(list)
    if type(list) ~= "table" or not Lists.Source(list.source) then return nil end
    return list.source
end

-- Ist die Menge der Einträge schon „fehlt noch n“ (nicht gegen den Bestand aller Charaktere zu rechnen)? Listen mit
-- Quelle und die vorübergehende Suchliste aus ezCrafts Knopf „Auktionshaus“ (API.SearchItems, list.temporary: Menge =
-- Bedarf minus Tasche). Vorher rechneten „genug da“ und die Warnung vor Doppelkauf dort gegen alle Charaktere
-- (Hinweis der ezCraft-Session vom 21.11.2026).
function Lists.CountIsMissing(list)
    return Lists.SourceOf(list) ~= nil or (type(list) == "table" and list.temporary == true)
end

-- Liste einer Quelle neu bauen (create = true legt sie an, aber nie leer). Rückgabe: Liste, Anzahl der Einträge.
-- Fehlt die Quelle gerade (ezCraft aus), bleibt die Liste, wie sie ist.
function Lists.UpdateSource(key, create)
    local source = Lists.Source(key)
    local entries = source and source.entries()
    if not entries then return nil, 0 end
    local list = Lists.OfSource(key)
    if not list then
        if not create or #entries == 0 then return nil, #entries end
        list = Lists.Create(source.name())
        list.source = key
    end
    local items = {}
    for _, value in ipairs(entries) do
        local entry = Lists.NormalizeEntry(value)
        if entry then items[#items + 1] = entry end
    end
    list.items = items
    Changed()
    return list, #entries
end

-- Alle vorhandenen Listen mit Quelle auffrischen.
function Lists.UpdateSources()
    for _, source in ipairs(Lists.SOURCES) do
        if Lists.OfSource(source.key) then Lists.UpdateSource(source.key, false) end
    end
end

-- Liste „Bibliotheksbücher“ auffrischen (create = true legt sie an). Rückgabe: Liste, Anzahl fehlender Bücher.
-- Ohne fehlendes Buch wird keine leere Liste angelegt.
function Lists.UpdateBooks(create)
    return Lists.UpdateSource("books", create)
end

---------------------------------------------------------------------------
-- Als Text weitergeben (AUC-20, VP-75 – Empfehlung umgesetzt, Antwort offen): ezCores Umschlag (Core.Pack/Unpack)
-- mit Art Lists.EXPORT_KIND, Fassung Lists.EXPORT_VERSION; Inhalt { lists = { { n = Name, e = { { i = itemID,
-- t = Text, x = genau, c = Menge } … } } … } }. Ein Import legt immer neue Listen an (freier Name), ersetzt nichts
-- und übernimmt keine Quelle: eine geteilte „ezCraft“-Liste wird eine gewöhnliche Liste.
---------------------------------------------------------------------------

Lists.EXPORT_KIND = "ezAuctionLists"
Lists.EXPORT_VERSION = 1
Lists.IMPORT_LISTS = 20       -- höchstens so viele Listen je Import …
Lists.IMPORT_ENTRIES = 200    -- … und so viele Einträge je Liste (Länge von Name und Begriff: Lists.NAME_LETTERS oben)

-- Text einer Liste (oder einer Folge von Listen) für ezCores Text-Dialog; nil, Grund ohne ezCores Umschlag.
function Lists.Export(lists)
    if type(Core.Pack) ~= "function" then return nil, "core" end
    if type(lists) == "table" and lists.items ~= nil then lists = { lists } end
    local out = {}
    for _, list in ipairs(type(lists) == "table" and lists or {}) do
        local entries = {}
        for _, entry in ipairs(type(list) == "table" and list.items or {}) do
            if type(entry) == "table" then
                -- Filter und Höchstpreis (AH-09) als zusätzliche Felder: eine ältere Fassung liest sie nicht und
                -- übernimmt den Eintrag ohne sie – darum bleibt es Fassung 1.
                entries[#entries + 1] = { i = Core.Num(entry.itemID), t = entry.text, x = entry.exact and true or nil,
                    c = Core.Num(entry.count), l = entry.minLevel, h = entry.maxLevel, q = entry.quality,
                    m = entry.maxPrice, k = Lists.CleanCategory(entry.category),
                    r = Core.Num(entry.recipe), b = entry.buy and true or nil }   -- hergestellt (Core.Lists, 21.11.2026)
            end
        end
        out[#out + 1] = { n = list.name, e = entries }
    end
    return Core.Pack(Lists.EXPORT_KIND, Lists.EXPORT_VERSION, { lists = out })
end

-- Listen aus einem Text übernehmen. → neue Listen { list … }, Zahl der Einträge – oder nil und Grund: "empty",
-- "kind" (kein Text von ezAuctions Einkaufslisten), "newer" (aus einer neueren Fassung), "bad" (beschädigt), "core".
function Lists.Import(text)
    if type(Core.Unpack) ~= "function" then return nil, "core" end
    if type(text) ~= "string" or Core.IsSecret(text) or Core.Trim(text) == "" then return nil, "empty" end
    local data, why = Core.Unpack(text, Lists.EXPORT_KIND, Lists.EXPORT_VERSION)
    if not data then
        if why == "kind" or why == "newer" or why == "empty" then return nil, why end
        return nil, "bad"
    end
    if type(data.lists) ~= "table" or #data.lists == 0 then return nil, "bad" end
    local created, total = {}, 0
    for index, source in ipairs(data.lists) do
        if index > Lists.IMPORT_LISTS then break end
        if type(source) == "table" then
            local items = {}
            for n, e in ipairs(type(source.e) == "table" and source.e or {}) do
                if n > Lists.IMPORT_ENTRIES then break end
                if type(e) == "table" then
                    local entry = Lists.NormalizeEntry({ itemID = PositiveInt(e.i), text = Cut(e.t, Lists.TEXT_LETTERS),
                        exact = e.x == true or nil, count = PositiveInt(e.c), minLevel = e.l, maxLevel = e.h,
                        quality = e.q, maxPrice = e.m, category = e.k, recipe = PositiveInt(e.r), buy = e.b == true })
                    if entry then items[#items + 1] = entry end
                end
            end
            local list = Lists.Create(Cut(source.n, Lists.NAME_LETTERS))
            for _, entry in ipairs(items) do
                if Lists.AddEntry(list, entry) then total = total + 1 end
            end
            created[#created + 1] = list
        end
    end
    if #created == 0 then return nil, "bad" end
    return created, total
end

function Lists.PrintAll()
    local all = Lists.All()
    if #all == 0 then return ns.Print(L.LISTS_NONE) end
    ns.Print(L.LISTS_HEAD)
    for _, list in ipairs(all) do
        local labels = {}
        for _, entry in ipairs(list.items or {}) do
            local filters = Lists.FilterText(entry, true)
            labels[#labels + 1] = Lists.EntryLabel(entry) .. (filters and (" (" .. filters .. ")") or "")
        end
        ns.Print(("  %s (%d): %s"):format(list.name, #labels, table.concat(labels, ", ")))
    end
end

---------------------------------------------------------------------------
-- Schnittstelle für andere Module (README „ezAuction“)
---------------------------------------------------------------------------

--[[
    ezCore.API("ezAuction").AddShoppingList(name, items, replace)
      name     Name der Liste (ist er vergeben, wird ergänzt bzw. bei replace ersetzt)
      items    Liste wie bei Lists.NormalizeEntry: itemIDs, Links, Begriffe oder { itemID = …, count = … }
      replace  true: eine vorhandene Liste gleichen Namens wird geleert und neu gefüllt
    Rückgabe: Name der Liste, Anzahl übernommener Einträge (nil, wenn ezAuction noch nicht bereit ist).
    Beispiel (ezCraft): api.AddShoppingList("Schneiderei: Leinenhemd", { { itemID = 2589, count = 4 }, { itemID = 2320, count = 1 } })
]]
function ns.API.AddShoppingList(name, items, replace)
    if not ns.db then return nil end
    -- Der Name einer Quelle (ezCrafts „ezCraft“): die Liste folgt ab jetzt der Quelle statt einer Kopie.
    for _, source in ipairs(Lists.SOURCES) do
        if type(name) == "string" and Core.Trim(name):lower() == source.name():lower() then
            local own, count = Lists.UpdateSource(source.key, true)
            if own then return own.name, count end
        end
    end
    local list = Lists.Find(name)
    if list and replace then
        list.items = {}
    elseif not list then
        list = Lists.Create(name)
    end
    local added = 0
    for _, value in ipairs(type(items) == "table" and items or {}) do
        if Lists.AddEntry(list, value) then added = added + 1 end
    end
    Changed()
    return list.name, added
end

-- Eine Liste im Reiter „Kaufen“ wählen (ezCraft „Im AH suchen“): nur bei offenem Auktionshaus. search = true sucht
-- sie gleich (Wunsch des Nutzers vom 21.11.2026: „der button auktionshaus muss bei geöffneten auktionshaus direkt die
-- gegenstände suchen“) – wie Blizzards „Suchen“ bei gewählter Liste (Buy.StartList: ein Klick, ohne Haltezeit).
-- → true, wenn gewählt (bzw. die Suche begonnen hat)
function ns.API.ShowList(name, search)
    local list = Lists.Find(name)
    if not (list and ns.Buy and ns.AuctionHouseShown and ns.AuctionHouseShown()) then return false end
    if search then
        ns.Buy.StartList(list)
        return ns.Buy.active == list
    end
    return ns.Buy.Select(list)
end

-- Einträge sofort suchen, ohne eine Liste zu speichern (ezCrafts Knopf „Auktionshaus“ am Rezept; Entscheidung des
-- Nutzers vom 21.11.2026 „Nein, sofort suchen (Empfohlen)“): name steht in Blizzards Ergebnisleiste, items wie bei
-- AddShoppingList (auch { recipe = …, count = … } – dann das fehlende Material). Nur bei offenem Auktionshaus.
-- → true, wenn gesucht wird; sonst false, Grund ("closed" – Auktionshaus zu, "empty" – keine Einträge, "busy" – Blizzards
-- Suche gerade nicht möglich, etwa der Reiter eines fremden Addons vorn)
function ns.API.SearchItems(name, items)
    if not (ns.Search and ns.AuctionHouseShown and ns.AuctionHouseShown()) then return false, "closed" end
    local list = { name = type(name) == "string" and name or L.TITLE, items = {}, temporary = true }
    for _, value in ipairs(type(items) == "table" and items or {}) do
        local entry = Core.Lists.NormalizeEntry(value)
        if entry then list.items[#list.items + 1] = entry end
    end
    if #list.items == 0 then return false, "empty" end
    if ns.Search.Start(list) == true then return true end
    return false, "busy"
end

-- Namen und Größe aller Einkaufslisten: { { name = …, count = … }, … }
function ns.API.ShoppingLists()
    local result = {}
    for _, list in ipairs(Lists.All()) do
        result[#result + 1] = { name = list.name, count = #(list.items or {}) }
    end
    return result
end

-- Listen mit Quelle folgen ihr: Buch gefunden oder abgegeben, anderer Charakter, Auktionshaus geöffnet. ezCrafts
-- Listen sind seit dem 21.11.2026 dieselben (Core.Lists) – sie brauchen keine Kopie mehr.
Core.Listen("BOOKS_CHANGED", function() Lists.UpdateSource("books", false) end, ADDON)
-- Jede Änderung einer gemeinsamen Liste (auch aus ezCraft): ezAuctions eigene Nachricht für Editor und Kategorien
Core.Listen("LISTS_CHANGED", function()
    Lists.ForgetSearch()
    ns.Fire("LISTS_CHANGED")
end, ADDON)
Core.Listen("INVENTORY_CHANGED", function() Lists.ForgetSearch() end, ADDON)   -- Material gekauft: weniger fehlt
ns.OnReady(function()
    Lists.AdoptOld()
    Lists.Migrate()
    Lists.AdoptByName()
    Lists.UpdateSources()
end)
ns.Listen("AH_SHOW", Lists.UpdateSources)

---------------------------------------------------------------------------
-- Bedarf einer Einkaufsliste (AH-24, Welle 14): Menge des Eintrags minus erreichbarer Bestand (Lists.StockOf und
-- Lists.Reach, dieselbe Zählung wie AUC-12; seit T4-NR5 nur der erreichbare Teil). Bei Listen mit Quelle ist die Menge schon „fehlt noch n“ (ezCraft rechnet selbst) –
-- dort zählt sie unverändert.
---------------------------------------------------------------------------

-- Eintrag mit Menge zu einem Gegenstand: zuerst in der Liste prefer (der gerade gesuchten), dann in allen Listen
-- der Reihe nach. Rückgabe: Eintrag, Liste oder nil.
function Lists.EntryWithCount(itemID, prefer)
    itemID = Core.Num(itemID)
    if not itemID then return nil end
    local function Look(list)
        for _, entry in ipairs(type(list) == "table" and type(list.items) == "table" and list.items or {}) do
            if type(entry) == "table" and entry.itemID == itemID and Core.Num(entry.count) and not entry.recipe then return entry end
        end
        -- Material hergestellter Gegenstände (Menge = was noch fehlt)
        for _, entry in ipairs(Lists.SearchEntries(list)) do
            if entry.fromRecipe and entry.itemID == itemID and Core.Num(entry.count) then return entry end
        end
        return nil
    end
    local entry = prefer and Look(prefer)
    if entry then return entry, prefer end
    for _, list in ipairs(Lists.All()) do
        entry = Look(list)
        if entry then return entry, list end
    end
    return nil
end

-- „Bedarf: n“. Rückgabe: { need, count, have, entry, list, source = true (Liste mit Quelle) } oder nil ohne Eintrag
-- mit Menge. need ist nie kleiner als 0; have fehlt ohne ezCores Zählung (dann gilt die eingetragene Menge).
function Lists.Need(itemID, prefer)
    local entry, list = Lists.EntryWithCount(itemID, prefer)
    if not entry then return nil end
    local count = Core.Num(entry.count)
    if Lists.CountIsMissing(list) or entry.fromRecipe then
        return { need = count, count = count, entry = entry, list = list, source = true }
    end
    local info = Lists.StockOf(itemID)
    local have = info and (info.chars + info.guilds) or nil
    local reach = info and math.min(have, Lists.Reach(info) or have) or nil   -- Bedarf aus dem erreichbaren Teil (T4-NR5)
    return { need = math.max(0, count - (reach or 0)), count = count, have = have, reach = reach, entry = entry, list = list,
        chars = info and info.chars or nil, guilds = info and info.guilds or nil }
end

---------------------------------------------------------------------------
-- Beobachtet (AH-23, Welle 14): Spiegel der Favoriten mit Zielpreis
---------------------------------------------------------------------------
--[[
    Blizzards Favoriten lassen sich nicht aufzählen (AuctionHouseDocumentation, Zweig forever: nur FavoritesAreAvailable,
    HasFavorites, HasMaxFavorites, IsFavoriteItem, SetFavoriteItem, SearchForFavorites). ezAuction führt darum einen
    eigenen Spiegel in ezAuctionDB.watch (für das Konto, wie Blizzards Favoriten):
      [ns.KeyString(itemKey)] = { itemID, level, suffix, species, fav = true|false, target = Kupfer|nil, seen = Zeit }
    Gelernt wird nur aus dem, was Blizzard ohnehin zeigt – ezAuction schickt keine eigene Favoritenabfrage, um zu lernen:
      - die Treffer von Blizzards eigener Favoritensuche (beim Öffnen und bei jedem Klick auf Blizzards Favoriten-Knopf;
        erkannt an Blizzards Feld isDisplayingFavorites, nur gelesen) und der Suche hinter „Beobachtet (n)“,
      - hooksecurefunc auf C_AuctionHouse.SetFavoriteItem (Stern gesetzt oder gelöst),
      - AUCTION_HOUSE_FAVORITES_UPDATED: Abgleich der bekannten Schlüssel über IsFavoriteItem.
    Darum heißt es überall ehrlich „Favoriten, die ezAuction schon gesehen hat“. Der Zielpreis hängt am eigenen
    Eintrag, nicht an Blizzards Stern: wird der Stern gelöst, bleibt ein Eintrag mit Zielpreis ruhend liegen (fav =
    false) und gilt wieder, sobald der Stern zurückkommt; ohne Zielpreis fällt er weg.
    Preise kommen aus ezCore.Prices (nur bei offenem Auktionshaus erfasst – es gibt keinen Alarm im Hintergrund).
]]
local Watch = {}
ns.Watch = Watch
Watch.ALERT_NAMES = 3     -- so viele Namen nennt die Meldung „3 Beobachtete unter Zielpreis“

function Watch.Store()
    local db = ns.db
    if not db then return {} end
    if type(db.watch) ~= "table" then db.watch = {} end
    return db.watch
end

-- Blizzards Schlüssel eines Eintrags (über C_AuctionHouse.MakeItemKey, wenn es sie gibt; sonst eine eigene Tabelle).
function Watch.ItemKey(entry)
    if type(entry) ~= "table" or not Core.Num(entry.itemID) then return nil end
    local api = C_AuctionHouse
    if api and type(api.MakeItemKey) == "function" then
        local ok, key = pcall(api.MakeItemKey, entry.itemID, entry.level or 0, entry.suffix or 0, entry.species or 0)
        if ok and type(key) == "table" then return key end
    end
    return { itemID = entry.itemID, itemLevel = entry.level or 0, itemSuffix = entry.suffix or 0,
        battlePetSpeciesID = entry.species or 0 }
end

local function KeyOf(itemKey)
    if type(itemKey) ~= "table" or Core.IsSecret(itemKey) or not Core.Num(itemKey.itemID) then return nil end
    return ns.KeyString(itemKey)
end

-- Ein Favorit ist bestätigt (Treffer der Favoritensuche, Stern gesetzt). Rückgabe: der Eintrag.
function Watch.Learn(itemKey)
    local key = KeyOf(itemKey)
    if not key then return nil end
    local store = Watch.Store()
    local entry = store[key]
    if type(entry) ~= "table" then
        entry = { itemID = itemKey.itemID, level = Core.Num(itemKey.itemLevel) or 0, suffix = Core.Num(itemKey.itemSuffix) or 0,
            species = Core.Num(itemKey.battlePetSpeciesID) or 0 }
        store[key] = entry
    end
    entry.fav, entry.seen = true, time()
    return entry
end

-- Stern gesetzt (true) oder gelöst (false) – aus dem Hook auf C_AuctionHouse.SetFavoriteItem bzw. dem Abgleich.
function Watch.SetFavorite(itemKey, isFavorite)
    if isFavorite then
        local entry = Watch.Learn(itemKey)
        if entry then ns.Fire("WATCH_CHANGED") end
        return entry ~= nil
    end
    local key = KeyOf(itemKey)
    local store = Watch.Store()
    local entry = key and store[key]
    if type(entry) ~= "table" then return false end
    if Core.Num(entry.target) then entry.fav = false else store[key] = nil end
    ns.Fire("WATCH_CHANGED")
    return true
end

-- AUCTION_HOUSE_FAVORITES_UPDATED: jeden bekannten Schlüssel mit IsFavoriteItem abgleichen. Antwortet der Client
-- nicht mit true/false, bleibt der Eintrag, wie er ist. Rückgabe: Zahl der geänderten Einträge.
function Watch.Sync()
    local api = C_AuctionHouse
    if not (api and type(api.IsFavoriteItem) == "function") then return 0 end
    local changed, list = 0, {}
    for _, entry in pairs(Watch.Store()) do list[#list + 1] = entry end
    for _, entry in ipairs(list) do
        local itemKey = Watch.ItemKey(entry)
        local fav = itemKey and Core.Call(api.IsFavoriteItem, itemKey)
        if type(fav) == "boolean" and not Core.IsSecret(fav) and fav ~= (entry.fav == true) then
            changed = changed + 1
            Watch.SetFavorite(itemKey, fav)
        end
    end
    return changed
end

-- Eintrag zu einem Schlüssel aus Blizzards Listen: genau dieser Schlüssel, sonst ein Favorit mit derselben itemID
-- (Blizzards Ergebniszeilen tragen bei Ausrüstung oft eine andere Stufe als der Stern). Nur Favoriten.
function Watch.Of(itemKey)
    local key = KeyOf(itemKey)
    if not key then return nil end
    local store = Watch.Store()
    local entry = store[key]
    if type(entry) == "table" and entry.fav then return entry end
    for _, other in pairs(store) do
        if type(other) == "table" and other.fav and other.itemID == itemKey.itemID then return other end
    end
    return nil
end

local function Name(entry)
    return Core.ItemNameByID(entry.itemID) or ("#" .. tostring(entry.itemID))
end
Watch.Name = Name

-- Favoriten, die ezAuction schon gesehen hat, nach Namen sortiert.
function Watch.Entries()
    local out = {}
    for _, entry in pairs(Watch.Store()) do
        if type(entry) == "table" and entry.fav and Core.Num(entry.itemID) then out[#out + 1] = entry end
    end
    table.sort(out, function(a, b)
        local na, nb = Name(a), Name(b)
        if na ~= nb then return na < nb end
        return ns.KeyString(Watch.ItemKey(a)) < ns.KeyString(Watch.ItemKey(b))
    end)
    return out
end

function Watch.Count() return #Watch.Entries() end

-- Tiefstpreis von heute aus ezCores Preis-Wissen (Abwandlung: ihr eigener Preis). Rückgabe: Preis, info – Preis nil
-- ohne Erfassung von heute.
function Watch.TodayPrice(entry)
    local prices = ns.Prices()
    local info = prices and ns.PriceInfo(Watch.ItemKey(entry))
    local seen, min = info and Core.Num(info.seen), info and Core.Num(info.min)
    if not (seen and min and min > 0) then return nil, info end
    local day = type(prices.Day) == "function" and Core.Call(prices.Day)
    if day and Core.Call(prices.Day, seen) ~= day then return nil, info end
    return min, info
end

-- Zielpreis setzen (Kupfer je Stück) oder mit nil/0 entfernen. Rückgabe: true, wenn es den Eintrag gibt.
function Watch.SetTarget(entry, copper)
    if type(entry) ~= "table" then return false end
    copper = Core.Num(copper)
    entry.target = copper and copper > 0 and math.floor(copper) or nil
    ns.Fire("WATCH_CHANGED")
    return true
end

-- Beobachtete mit Zielpreis, deren Preis von heute ihn erreicht: { { entry, price } … }
function Watch.Hits()
    local out = {}
    for _, entry in ipairs(Watch.Entries()) do
        local target = Core.Num(entry.target)
        local price = target and Watch.TodayPrice(entry)
        if price and price <= target then out[#out + 1] = { entry = entry, price = price } end
    end
    return out
end

-- Beobachtete ohne Preis von heute (für „Fehlende auffrischen“ über Prices.Refresh): Liste von ItemKeys.
function Watch.Missing()
    local out = {}
    for _, entry in ipairs(Watch.Entries()) do
        if not Watch.TodayPrice(entry) then out[#out + 1] = Watch.ItemKey(entry) end
    end
    return out
end

-- Anbieter für Beobachtetes (ezCore.Prices.AddWatchProvider): die Favoriten im Spiegel.
function Watch.ProviderItems()
    local out = {}
    for _, entry in ipairs(Watch.Entries()) do out[#out + 1] = Watch.ItemKey(entry) end
    return out
end

-- Zeile über den Zielpreis eines Eintrags (Tooltip der Ergebniszeile, Seitenteil); price = Preis der Zeile.
function Watch.TargetText(entry, price)
    local target = Core.Num(entry and entry.target)
    if not target then return L.WATCH_NO_TARGET end
    price = Core.Num(price) or Watch.TodayPrice(entry)
    if not price then return L.WATCH_TARGET_NOPRICE:format(ns.Money(target)) end
    if price <= target then return L.WATCH_TARGET_HIT:format(ns.Money(target), ns.Money(price)) end
    return L.WATCH_TARGET_ABOVE:format(ns.Money(target), ns.Money(price), Core.Percent(Core.Round((price - target) / target * 100)))
end

-- Meldung „3 Beobachtete unter Zielpreis“ (Schalter watchAlert): nur bei offenem Auktionshaus und nur, wenn sich die
-- Zahl seit der letzten Meldung dieses Besuchs geändert hat. Rückgabe: Zahl der Treffer, wenn gemeldet.
function Watch.Alert()
    if not (ns.Enabled("watchList") and ns.Enabled("watchAlert") and ns.AuctionHouseShown()) then return nil end
    local hits = Watch.Hits()
    if #hits == 0 then
        Watch.alerted = nil
        return nil
    end
    if #hits == Watch.alerted then return nil end
    Watch.alerted = #hits
    local names = {}
    for index, hit in ipairs(hits) do
        if index > Watch.ALERT_NAMES then break end
        names[#names + 1] = Name(hit.entry)
    end
    if #hits > Watch.ALERT_NAMES then names[#names + 1] = "…" end
    ns.Print(Core.Plural(#hits, L.WATCH_ALERT_ONE, L.WATCH_ALERT_MANY, table.concat(names, ", ")))
    return #hits
end

-- Antwort der Übersicht: Zeigt sie Blizzards Favoriten (Blizzards Feld isDisplayingFavorites, nur gelesen) oder die
-- Suche hinter „Beobachtet (n)“ (Watch.pending), sind ihre Zeilen Favoriten – lernen. Rückgabe: Zahl der Zeilen.
function Watch.OnBrowseResults()
    local favorites = Watch.pending or Core.Peek(AuctionHouseFrame, "isDisplayingFavorites") == true
    if not favorites then return 0 end
    local own = Watch.pending == true
    Watch.pending = nil
    local api = C_AuctionHouse
    local learned = 0
    for _, result in ipairs(api and Core.Call(api.GetBrowseResults) or {}) do
        local itemKey = type(result) == "table" and result.itemKey
        -- Gegenprobe, wenn der Client sie kennt: nur, was er selbst als Favorit nennt. Blizzards Feld
        -- isDisplayingFavorites bleibt stehen, bis Blizzards eigenes Suchfeld wieder sucht – Antworten auf Abfragen
        -- anderer (ezAuctions Listen, ezCores Erfassungen) kämen sonst als Favoriten an.
        local fav
        if itemKey and type(api.IsFavoriteItem) == "function" then
            fav = Core.Call(api.IsFavoriteItem, itemKey) == true
        else
            fav = itemKey ~= nil and (own or Core.Peek(AuctionHouseFrame, "isDisplayingFavorites") == true)
        end
        if fav and Watch.Learn(itemKey) then learned = learned + 1 end
    end
    if learned > 0 then ns.Fire("WATCH_CHANGED") end
    return learned
end

do
    local api = C_AuctionHouse
    if type(api) == "table" and type(api.SetFavoriteItem) == "function" then
        hooksecurefunc(api, "SetFavoriteItem", function(itemKey, setFavorite)
            ns.Try("Watch", Watch.SetFavorite, itemKey, setFavorite == true)
        end)
    end
    local prices = ns.Prices()
    if prices and type(prices.AddWatchProvider) == "function" then
        prices.AddWatchProvider("ezAuction.favorites", Watch.ProviderItems)
    end
end
ns.On("AUCTION_HOUSE_FAVORITES_UPDATED", function() Watch.Sync() end)
local function BrowseAnswer()
    if not ns.Enabled("watchList") then
        Watch.pending = nil
        return
    end
    Watch.OnBrowseResults()
    Watch.Alert()
end
ns.On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", BrowseAnswer)
ns.On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", BrowseAnswer)
ns.Listen("AH_HIDE", function()
    Watch.pending, Watch.alerted = nil, nil
end)
