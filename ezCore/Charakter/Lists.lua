local Core = ezCore

--[[
    Gemeinsame Listen (Einkaufs- und Merklisten) von ezCraft und ezAuction – eine Quelle für beide (Entscheidung des
    Nutzers vom 21.11.2026: „Ein Speicher in ezCore (Empfohlen)“; Wunsch im Spieltest: „da sich beide das selbe mehr
    oder weniger teilen also listen, muss das logisch ssot und dry sein“). Für alle Charaktere gleich, ezCoreDB.lists.

      Liste   { name = "Kräuter", items = { eintrag, … }, source = nil | "books" }
      Eintrag { itemID = nil|Zahl, text = Suchbegriff bzw. Name, exact = true|nil, count = nil|Zahl,
                recipe = nil|Rezept-ID, buy = true|nil, … }
        - mit itemID: genau dieser Gegenstand; Text in Anführungszeichen: genau dieser Name; sonst ein Suchbegriff
        - recipe: ein hergestellter Gegenstand (count = Anzahl Herstellungen, itemID = Produkt, falls bekannt). Ab Werk
          zählt sein Material („muss beides möglichsein primär aber material“); buy = true: der Gegenstand selbst
        - weitere Felder (Filter und Höchstpreis von ezAuction: minLevel, maxLevel, quality, category, maxPrice) bleiben
          unangetastet; NormalizeEntry übernimmt sie über den extra-Rückruf des Moduls
      source: Listen mit Quelle werden von ihrem Modul neu gebaut (ezAuction „Bibliotheksbücher“); von Hand nicht
              änderbar (Lists.Editable)

    Funktionen (alle über Core.Lists):
      All() → Listen · Find(name) → Liste, Index · IndexOf(liste) · UniqueName(base) · Create(name) → Liste
      Rename(liste, name) → true, name | false · Delete(liste) → true | false · Editable(liste)
      NormalizeEntry(wert, extra) → Eintrag | nil · SameEntry(a, b, key) · AddEntry(liste, wert, extra) → Eintrag
      AddRecipe(liste, recipeID, n) → Eintrag · RemoveEntry(liste, index) · SetCount(liste, index, n) · SetBuy(…)
      Recipe(recipeID) → { name, icon, product, reagents = { [itemID] = je Herstellung } } | nil
      Needs(liste | nil) → { [itemID] = Bedarf } (nil = alle Listen) · NeedFor(itemID) (alle Listen)
      SearchEntries(liste) → Einträge zum Suchen (Rezepte zu ihrem fehlenden Material bzw. Produkt aufgelöst)
      Label(eintrag) · Icon(eintrag)
      SetProvider({ recipe = fn(recipeID), have = fn(itemID) }, owner) – ezCraft liefert Rezepte aus dem offenen
        Berufefenster und „vorhanden“ nach seinen Einstellungen; ohne Anbieter: ezCores Rezept-Wissen, nichts vorhanden
      Nachricht LISTS_CHANGED (Liste | nil, bisheriger Name beim Umbenennen | nil) bei jeder Änderung.

    Übernahme alter Listen: jedes Modul übernimmt seine eigenen einmal (Lists.Adopt) – ezAuction ezAuctionDB.lists,
    ezCraft ezCraftDB.shopping als Liste „ezCraft“. Die alten Tabellen bleiben als Rückfall liegen.
]]

local Lists = {}
Core.Lists = Lists

local EMPTY = {}
local floor, max = math.floor, math.max
local provider = {}

-- oldName: nur beim Umbenennen der bisherige Name (wer eine Liste am Namen merkt, zieht ihn nach)
local function Changed(list, oldName)
    Core.Fire("LISTS_CHANGED", list, oldName)
end
Lists.Changed = Changed

-- Speicher (nil vor dem Laden von ezCoreDB).
local function Store()
    local db = Core.db
    if type(db) ~= "table" then return nil end
    if type(db.lists) ~= "table" then db.lists = {} end
    return db.lists
end

local function Text(value)
    return type(value) == "string" and not Core.IsSecret(value) and value or nil
end

function Lists.All()
    return Store() or EMPTY
end

function Lists.Find(name)
    name = Text(name)
    if not name then return nil end
    local wanted = Core.Trim(name):lower()
    for index, list in ipairs(Lists.All()) do
        if type(list.name) == "string" and list.name:lower() == wanted then return list, index end
    end
    return nil
end

function Lists.IndexOf(list)
    for index, other in ipairs(Lists.All()) do
        if other == list then return index end
    end
    return nil
end

local function Taken(name) return Lists.Find(name) ~= nil end

-- „Kräuter“, „Kräuter (2)“ … – ein freier Name (Core.UniqueName). base mit %d (z. B. „Liste %d“) zählt selbst
-- hoch: „Liste 1“, „Liste 2“ … Leer: Core.L.LISTS_DEFAULT_NAME.
function Lists.UniqueName(base)
    base = Core.Trim(Text(base) or "")
    if base == "" then base = Core.L.LISTS_DEFAULT_NAME or "%d" end
    if base:find("%%d") then
        local ok, first = pcall(string.format, base, 1)
        if ok then return Core.UniqueName(first, Taken, { format = "%.0s" .. base }) end
    end
    return Core.UniqueName(base, Taken)
end

-- Neue, leere Liste mit freiem Namen. → Liste (nil vor dem Laden)
function Lists.Create(name)
    local store = Store()
    if not store then return nil end
    local list = { name = Lists.UniqueName(name), items = {} }
    store[#store + 1] = list
    Changed(list)
    return list
end

-- → true und der neue Name, oder false, wenn der Name leer oder schon vergeben ist
function Lists.Rename(list, name)
    name = Core.Trim(Text(name) or "")
    if type(list) ~= "table" or name == "" then return false end
    local other = Lists.Find(name)
    if other and other ~= list then return false end
    local oldName = list.name
    list.name = name
    Changed(list, oldName)
    return true, name
end

function Lists.Delete(list)
    local index = Lists.IndexOf(list)
    if not index then return false end
    table.remove(Store(), index)
    Changed(nil)
    return true
end

-- Von Hand änderbar? (Listen mit Quelle baut ihr Modul neu.)
function Lists.Editable(list)
    return type(list) == "table" and list.source == nil
end

---------------------------------------------------------------------------
-- Einträge
---------------------------------------------------------------------------

-- itemID und Name aus einem Gegenstandslink („|Hitem:2589:…|h[Leinenstoff]|h“ oder „item:2589“).
function Lists.ParseLink(link)
    link = Text(link)
    if not link or not link:find("item:%d") then return nil end
    return Core.ItemID(link), Core.ItemName(link)
end

-- Rezept-ID aus einem Rezept-Link (Shift-Klick auf ein Rezept in Blizzards Liste: „|Henchant:2330|h[…]|h“,
-- „|Htrade:…“ nennt nur den Beruf und zählt nicht). → recipeID, Name oder nil
function Lists.ParseRecipeLink(link)
    link = Text(link)
    if not link then return nil end
    local id = tonumber(link:match("enchant:(%d+)"))
    if not id then return nil end
    return id, link:match("|h%[(.-)%]|h")
end

-- Rezept lesen: zuerst der Anbieter (ezCraft: offenes Berufefenster), dann ezCores Rezept-Wissen.
-- → { name, icon, product, reagents = { [itemID] = Anzahl je Herstellung } } oder nil
function Lists.Recipe(recipeID)
    recipeID = Core.Num(recipeID)
    if not recipeID then return nil end
    if type(provider.recipe) == "function" then
        local ok, info = pcall(provider.recipe, recipeID)
        if ok and type(info) == "table" then return info end
    end
    local K = Core.Knowledge
    local rec = K and Core.Call(K.Recipe, recipeID)
    if type(rec) ~= "table" then return nil end
    local reagents = {}
    for itemID, count in pairs(type(rec.r) == "table" and rec.r or EMPTY) do
        local id, n = Core.Num(itemID), Core.Num(count)
        if id and n and n > 0 then reagents[id] = n end
    end
    local product = Core.Num(rec.o)
    return { name = Text(rec.n), product = product, icon = product and Core.ItemIcon and Core.ItemIcon(product) or nil,
        reagents = reagents }
end

local function PositiveCount(value)
    local n = Core.Num(value)
    if n and n > 0 then return max(1, floor(n)) end
    return nil
end

--[[
    Jede Form, die Spieler oder Module liefern, wird zu einem Eintrag (nil, wenn nichts Brauchbares):
      2589 · Gegenstandslink · Rezept-Link („enchant:…“) · "Leinen" / "\"Leinenstoff\"" ·
      { itemID = 2589, count = 20 } / { text = "Leinen", exact = true } / { recipe = 2330, count = 2, buy = true }
    extra(wert, eintrag) – freiwillig: das Modul übernimmt eigene Felder (ezAuction: Filter, Höchstpreis).
]]
function Lists.NormalizeEntry(value, extra)
    local entry
    if type(value) == "number" then
        local id = Core.Num(value)
        if not id then return nil end
        entry = { itemID = id }
    elseif Text(value) then
        local id, name = Lists.ParseLink(value)
        local recipe = Lists.ParseRecipeLink(value)
        if id then
            entry = { itemID = id, text = name }
        elseif recipe then
            entry = { recipe = recipe, count = 1 }
        else
            local text = Core.Trim(value)
            local quoted = text:match('^"(.+)"$')
            if quoted then
                entry = { text = Core.Trim(quoted), exact = true }
            elseif text ~= "" then
                entry = { text = text }
            end
        end
    elseif type(value) == "table" then
        local recipe = Core.Num(value.recipe or value.recipeID)
        local id = Core.Num(value.itemID or value.id)
        local text = Text(value.text) or Text(value.name)
        if not id and Text(value.link) then id, text = Lists.ParseLink(value.link) end
        if recipe and recipe > 0 then
            entry = { recipe = recipe, itemID = id, text = text and Core.Trim(text) or nil,
                count = PositiveCount(value.count or value.quantity) or 1, buy = value.buy == true or nil }
        elseif id or (text and Core.Trim(text) ~= "") then
            entry = { itemID = id, text = text and Core.Trim(text) or nil, exact = value.exact and true or nil,
                count = PositiveCount(value.count or value.quantity) }
        end
        if entry and type(extra) == "function" then extra(value, entry) end
    end
    if not entry then return nil end
    -- Rezepte speichern nur Rezept-ID und Menge (dazu buy und, falls mitgegeben, Name bzw. Produkt): Name, Symbol,
    -- Produkt und Zutaten kommen jedes Mal frisch aus Lists.Recipe – so veraltet nichts (wie ezCrafts Liste seit 1.2)
    if entry.itemID and not entry.text and not entry.recipe and Core.ItemNameByID then
        entry.text = Core.ItemNameByID(entry.itemID)
    end
    if entry.text == "" then entry.text = nil end
    if not entry.itemID and not entry.text and not entry.recipe then return nil end
    return entry
end

-- Derselbe Eintrag? Rezepte nach Rezept, Gegenstände nach itemID, Begriffe nach Text, „genau“ und key(eintrag)
-- (ezAuction: dieselben Filter – „Erz“ in „Handwerkswaren“ und „Erz“ ohne Kategorie bleiben zwei Einträge).
function Lists.SameEntry(a, b, key)
    if a.recipe or b.recipe then return a.recipe == b.recipe end
    if a.itemID or b.itemID then return a.itemID == b.itemID end
    if (a.text or ""):lower() ~= (b.text or ""):lower() or a.exact ~= b.exact then return false end
    if type(key) == "function" then return key(a) == key(b) end
    return true
end

-- Eintrag hinzufügen; derselbe wird zusammengelegt (Mengen addiert). → Eintrag in der Liste oder nil
-- opts (freiwillig): { extra = fn (NormalizeEntry), key = fn (SameEntry) }
function Lists.AddEntry(list, value, opts)
    opts = opts or EMPTY
    local entry = Lists.NormalizeEntry(value, opts.extra)
    if not (type(list) == "table" and entry) then return nil end
    list.items = list.items or {}
    for _, existing in ipairs(list.items) do
        if Lists.SameEntry(existing, entry, opts.key) then
            if entry.count then existing.count = (existing.count or 0) + entry.count end
            existing.text = existing.text or entry.text
            existing.itemID = existing.itemID or entry.itemID
            Changed(list)
            return existing
        end
    end
    list.items[#list.items + 1] = entry
    Changed(list)
    return entry
end

-- Hergestellten Gegenstand (Rezept) n-mal auf die Liste. → Eintrag oder nil
function Lists.AddRecipe(list, recipeID, n)
    return Lists.AddEntry(list, { recipe = recipeID, count = PositiveCount(n) or 1 })
end

function Lists.RemoveEntry(list, index)
    if not (type(list) == "table" and list.items and list.items[index]) then return false end
    table.remove(list.items, index)
    Changed(list)
    return true
end

-- Menge setzen; 0 oder weniger entfernt den Eintrag. nil bei einem Gegenstand: „ohne Menge“. → true bei Erfolg
function Lists.SetCount(list, index, count)
    local entry = type(list) == "table" and list.items and list.items[index]
    if not entry then return false end
    if count == nil and not entry.recipe then
        entry.count = nil
        Changed(list)
        return true
    end
    count = floor(Core.Num(count) or 0)
    if count <= 0 then return Lists.RemoveEntry(list, index) end
    entry.count = count
    Changed(list)
    return true
end

-- Rezept: im Auktionshaus Material (false) oder den Gegenstand selbst (true) suchen. → true bei Erfolg
function Lists.SetBuy(list, index, buy)
    local entry = type(list) == "table" and list.items and list.items[index]
    if not (entry and entry.recipe) then return false end
    entry.buy = buy == true or nil
    Changed(list)
    return true
end

-- Name eines Eintrags für Zeilen und Tooltips; unbekannte Rezepte heißen „#Rezept-ID“.
function Lists.Label(entry)
    if type(entry) ~= "table" then return "?" end
    if entry.recipe then
        local info = Lists.Recipe(entry.recipe)
        return Text(info and info.name) or entry.text or ("#" .. tostring(entry.recipe))
    end
    if entry.itemID and Core.ItemNameByID then
        local name = Core.ItemNameByID(entry.itemID)
        if name then return name end
    end
    if entry.text then return entry.exact and ('"' .. entry.text .. '"') or entry.text end
    return entry.itemID and ("#" .. tostring(entry.itemID)) or "?"
end

-- Symbol eines Eintrags (Rezept: sein Symbol bzw. das des Produkts) oder nil.
function Lists.Icon(entry)
    if type(entry) ~= "table" then return nil end
    if entry.recipe then
        local info = Lists.Recipe(entry.recipe)
        if info and info.icon then return info.icon end
    end
    local id = entry.itemID
    return id and Core.ItemIcon and Core.ItemIcon(id) or nil
end

---------------------------------------------------------------------------
-- Bedarf und Suche
---------------------------------------------------------------------------

-- Bedarf eines Eintrags in map eintragen: Rezept (Material) = Zutaten × Anzahl, Rezept mit buy = Produkt × Anzahl,
-- Gegenstand mit Menge = Menge. Begriffe ohne itemID und Gegenstände ohne Menge zählen nicht.
local function AddNeeds(map, entry, sources)
    if type(entry) ~= "table" then return end
    -- kaputte Werte aus dem Speicher zählen nicht (die Rechnung läuft beim Verkaufen je Taschenplatz)
    local count = Core.Num(entry.count)
    if entry.recipe and not entry.buy then
        local info = Lists.Recipe(entry.recipe)
        for itemID, per in pairs(type(info) == "table" and type(info.reagents) == "table" and info.reagents or EMPTY) do
            per = Core.Num(per)
            if per then
                map[itemID] = (map[itemID] or 0) + per * (count or 1)
                if sources then sources[itemID] = sources[itemID] or entry.recipe end
            end
        end
    elseif entry.recipe then
        local info = not entry.itemID and Lists.Recipe(entry.recipe) or nil
        local product = entry.itemID or (type(info) == "table" and Core.Num(info.product))
        if product then map[product] = (map[product] or 0) + (count or 1) end
    elseif entry.itemID and count then
        map[entry.itemID] = (map[entry.itemID] or 0) + count
    end
end

local needCache   -- Bedarf aller Listen, bis LISTS_CHANGED oder neues Rezept-Wissen

-- Bedarf { [itemID] = Anzahl } einer Liste – oder (nil) aller Listen. Eine Kopie: der Aufrufer darf sie ändern.
function Lists.Needs(list)
    local map = {}
    if list ~= nil then
        for _, entry in ipairs(type(list) == "table" and type(list.items) == "table" and list.items or EMPTY) do
            AddNeeds(map, entry)
        end
        return map
    end
    if not needCache then
        local all = {}
        for _, other in ipairs(Lists.All()) do
            for _, entry in ipairs(type(other) == "table" and type(other.items) == "table" and other.items or EMPTY) do
                AddNeeds(all, entry)
            end
        end
        if Store() then needCache = all end
        for id, n in pairs(all) do map[id] = n end
        return map
    end
    for id, n in pairs(needCache) do map[id] = n end
    return map
end

-- Bedarf eines Gegenstands über alle Listen (Tooltip, Schutz vor dem Verkaufen).
function Lists.NeedFor(itemID)
    if not needCache then Lists.Needs() end
    return needCache and needCache[itemID] or 0
end

function Lists.Invalidate() needCache = nil end

-- Vorhanden laut Anbieter (ezCraft nach seinen Einstellungen); ohne Anbieter 0.
function Lists.Have(itemID)
    if type(provider.have) ~= "function" then return 0 end
    local ok, n = pcall(provider.have, itemID)
    return ok and Core.Num(n) or 0
end

--[[
    Einträge zum Suchen (ezAuction): Gegenstände und Begriffe wie sie sind; ein Rezept wird zu seinem Material, das noch
    fehlt (Bedarf minus vorhanden laut Anbieter, je Gegenstand zusammengezählt; fertig = nichts mehr zu suchen), mit
    buy = true zum Produkt selbst. Material-Einträge tragen fromRecipe (Rezept-ID) und haben exact = true.
    → { eintrag, … } (neue Tabellen für Material; Gegenstände sind die Einträge der Liste selbst)
]]
function Lists.SearchEntries(list)
    local out, reagentNeed, reagentSource, order = {}, {}, {}, {}
    for _, entry in ipairs(type(list) == "table" and type(list.items) == "table" and list.items or EMPTY) do
        if entry.recipe and not entry.buy then
            local before = {}
            for id in pairs(reagentNeed) do before[id] = true end
            AddNeeds(reagentNeed, entry, reagentSource)
            for id in pairs(reagentNeed) do
                if not before[id] then order[#order + 1] = id end
            end
        elseif entry.recipe then
            local info = Lists.Recipe(entry.recipe)
            local product = entry.itemID or (info and Core.Num(info.product))
            if product then
                out[#out + 1] = { itemID = product, text = entry.text or (info and info.name), count = entry.count,
                    fromRecipe = entry.recipe, buy = true }
            end
        else
            out[#out + 1] = entry
        end
    end
    table.sort(order)
    for _, itemID in ipairs(order) do
        local missing = reagentNeed[itemID] - Lists.Have(itemID)
        if missing > 0 then
            out[#out + 1] = { itemID = itemID, count = math.ceil(missing), exact = true,
                text = Core.ItemNameByID and Core.ItemNameByID(itemID) or nil, fromRecipe = reagentSource[itemID] }
        end
    end
    return out
end

-- Anbieter für Rezepte und „vorhanden“ anmelden (ezCraft). fields: { recipe = fn, have = fn }
function Lists.SetProvider(fields, owner)
    if type(fields) ~= "table" then return false end
    provider.recipe = type(fields.recipe) == "function" and fields.recipe or provider.recipe
    provider.have = type(fields.have) == "function" and fields.have or provider.have
    provider.owner = owner
    needCache = nil
    return true
end

---------------------------------------------------------------------------
-- Übernahme alter Listen (einmal je Modul)
---------------------------------------------------------------------------

--[[
    Lists.Adopt(lists, opts) – Listen eines Moduls übernehmen. lists = { { name, items, source }, … }; Einträge über
    NormalizeEntry (opts.extra für eigene Felder). opts.skip(liste) → true: nicht übernehmen (z. B. eine nur abgeleitete
    Liste). Jede Liste wird neu angelegt (freier Name: eine gleichnamige Liste eines anderen Moduls bleibt getrennt,
    Review 21.11.2026), Listen mit Quelle nur einmal je Quelle. Den Merker „schon übernommen“ hält der Aufrufer in
    ezCoreDB.migrated (Core.MigrateOnce) – im selben Speicher wie die Listen.
    → Zahl übernommener Listen, { neu angelegte Listen in Reihenfolge }
]]
function Lists.Adopt(lists, opts)
    opts = opts or EMPTY
    if not Store() then return 0, {} end
    local adopted, created = 0, {}
    for _, old in ipairs(type(lists) == "table" and lists or EMPTY) do
        if type(old) == "table" and not (type(opts.skip) == "function" and opts.skip(old)) then
            local target
            if old.source ~= nil then
                for _, list in ipairs(Lists.All()) do
                    if list.source == old.source then target = list end
                end
            end
            if not target then
                target = Lists.Create(Text(old.name))
                target.source = old.source
                created[#created + 1] = target
            end
            for _, value in ipairs(type(old.items) == "table" and old.items or EMPTY) do
                if type(value) == "table" then
                    Lists.AddEntry(target, value, { extra = opts.extra, key = opts.key })
                end
            end
            adopted = adopted + 1
        end
    end
    if adopted > 0 then Changed(nil) end
    return adopted, created
end

Core.Listen("LISTS_CHANGED", Lists.Invalidate, Core.name)
Core.Listen("RECIPES_CHANGED", Lists.Invalidate, Core.name)
