local ADDON, ns = ...
local L = ns.L

--[[
    Suchen in Tasche, Bank, Gildenbank und ezBag-Fenster (Knopf „Suchen“ der Werkzeugleiste):
    - Schnellsuche: Nutzbar, BoE, Rezept (Suchwörter des Item-Wissens) und Neu (Gruppe „Neu“)
    - eigene gespeicherte Suchen (ezBagDB.searches)
    - Treffer anderswo zählen: eigene Bank, Post, angelegt, andere Charaktere, Gildenbanken.
      „Bei allen Charakteren suchen“ öffnet das ezBag-Fenster mit allen Charakteren (Window.lua).
    Die Daten aller Charaktere kommen aus ezCore (Inventory), ezBag zeigt nur an.
]]

local Search = {}
ns.Search = Search

function Search.Presets()
    return {
        { label = L.SEARCH_USABLE, text = L.SEARCH_USABLE_WORD },
        { label = "BoE", text = "boe" },
        { label = L.SEARCH_RECIPE, text = L.SEARCH_RECIPE_WORD },
    }
end

---------------------------------------------------------------------------
-- Gespeicherte Suchen
---------------------------------------------------------------------------

local function List()
    ns.db.searches = ns.db.searches or {}
    return ns.db.searches
end

function Search.Saved()
    local out = {}
    for i, text in ipairs(List()) do out[i] = text end
    return out
end

function Search.IsSaved(text)
    for _, t in ipairs(List()) do
        if t == text then return true end
    end
    return false
end

function Search.Save(text)
    text = strtrim(text or "")
    if text == "" or Search.IsSaved(text) then return false end
    local list = List()
    list[#list + 1] = text
    ns.Print(L.SEARCH_SAVED:format(text))
    return true
end

function Search.Remove(text)
    local list = List()
    for i = #list, 1, -1 do
        if list[i] == text then table.remove(list, i) end
    end
end

---------------------------------------------------------------------------
-- Gespeicherte Bestände aller Charaktere (ezCore)
---------------------------------------------------------------------------

-- fn(e, charKey, location, guildKey) für jeden gespeicherten Eintrag { i, l, c, q, b }.
-- skipOwnBags: die eigenen Taschen auslassen (die zeigt die Tasche schon selbst). Veraltete Gildenbanken (kein eigener
-- Charakter mehr Mitglied, ezCore.Inventory.ActiveGuilds; Gesamtreview 18.11.2026, T4-NR3) zählen wie in ezCores
-- Bestandszahlen nicht mit; ansehen lassen sie sich weiter einzeln im Fenster.
function Search.ForEachStored(fn, skipOwnBags)
    local inv = ezCore.Inventory
    local active = inv and type(inv.ActiveGuilds) == "function" and inv.ActiveGuilds() or nil
    local mine = active and type(inv.MyGuildKey) == "function" and inv.MyGuildKey() or nil
    for key, c in pairs(ezCore.Chars()) do
        local items = c.items or {}
        for _, location in ipairs(ns.Inventory.LOCATIONS) do
            if not (skipOwnBags and key == ns.charKey and location == "bags") then
                for _, e in ipairs(items[location] or {}) do fn(e, key, location) end
            end
        end
    end
    for guildKey, g in pairs(ezCore.Guilds()) do
        if not active or active[guildKey] or guildKey == mine then
            for _, tab in pairs(g.tabs or {}) do
                for _, e in ipairs(tab.items or {}) do fn(e, nil, "guild", guildKey) end
            end
        end
    end
end

-- Gespeicherter Eintrag → Eintrag zum Suchen (wie in Render.Matches).
function Search.EntryOf(e)
    local itemID = ezCore.ItemID(e.i or e.l)   -- V-176
    itemID = ns.PlainID(itemID)
    if not itemID then return nil end
    local name = ns.ItemName(e.l) or (C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)) or ""
    return { itemID = itemID, link = e.l, name = name }
end

---------------------------------------------------------------------------
-- Fundort (Wunsch des Nutzers vom 18.11.2026, W-1811-ezBag): wo liegen die Gegenstände anderer Charaktere?
---------------------------------------------------------------------------

-- Orte in fester Reihenfolge: die vier aus ezCore (Taschen, Bank, Post, angelegt), dann die Gildenbank.
function Search.Places()
    local list = {}
    for _, location in ipairs(ns.Inventory.LOCATIONS) do list[#list + 1] = location end
    list[#list + 1] = "guild"
    return list
end

-- Schalter „Gleiche Gegenstände je Ort getrennt zeigen“ (OPT_showPlace, ab Werk an): unter „Alle Charaktere“ je Ort ein
-- eigener Platz samt Ortssymbol und Hervorheben eines Orts. Die Suchhilfe (Treffer je Ort am Suchknopf) und die Zeilen
-- „Liegt: …“ im Tooltip stehen seit der Einstellungs-Prüfung vom 19.11.2026 (Abschnitt 4) immer da.
function ns.ShowPlace()
    return not (type(ns.S) == "table" and ns.S.showPlace == false)
end

local cache, cached = {}, 0

-- Treffer anderswo: Zahl der verschiedenen Gegenstände und je Ort, wie viele davon dort liegen.
local function Compute(text)
    local seen, seenAt, n, places = {}, {}, 0, {}
    Search.ForEachStored(function(e, _, location)
        local entry = Search.EntryOf(e)
        if entry and ns.Render.Matches(entry, text) then
            local key = entry.link or entry.itemID
            if not seen[key] then
                seen[key] = true
                n = n + 1
            end
            local at = seenAt[location] or {}
            seenAt[location] = at
            if not at[key] then
                at[key] = true
                places[location] = (places[location] or 0) + 1
            end
        end
    end, true)
    return { n = n, places = places }
end

local function Cached(text)
    text = strtrim(text or ""):lower()
    if text == "" then return nil end
    if cache[text] then return cache[text] end
    if cached > 50 then
        wipe(cache)
        cached = 0
    end
    cache[text] = Compute(text)
    cached = cached + 1
    return cache[text]
end

-- Wie viele verschiedene Gegenstände passen anderswo (Bank, Post, angelegt, Twinks, Gildenbank)?
function Search.OtherCount(text)
    local hit = Cached(text)
    return hit and hit.n or 0
end

-- Dieselben Treffer je Ort: { bags = 2, bank = 1, guild = 3 … } (die eigenen Taschen zählen nicht mit). Ein Gegenstand
-- an mehreren Orten zählt an jedem Ort, die Summe kann also größer sein als OtherCount („Treffer je Ort“).
function Search.OtherPlaces(text)
    local hit = Cached(text)
    return hit and hit.places or {}
end

-- „Taschen 2, Bank 1, Gildenbank 3“ – oder nil ohne Treffer.
function Search.OtherPlacesText(text)
    local places, parts = Search.OtherPlaces(text), {}
    for _, location in ipairs(Search.Places()) do
        local n = places[location]
        if n and n > 0 then parts[#parts + 1] = L["LOC_" .. location] .. " " .. n end
    end
    return #parts > 0 and table.concat(parts, ", ") or nil
end

function Search.ClearCache()
    wipe(cache)
    cached = 0
end

ezCore.Listen("INVENTORY_CHANGED", Search.ClearCache, ADDON)
ezCore.Listen("GUILDBANK_CHANGED", Search.ClearCache, ADDON)
