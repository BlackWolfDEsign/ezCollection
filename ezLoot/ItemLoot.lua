local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Beute bei dir im Gegenstands-Tooltip (LOOT-13, Entscheidungsfrage 7 – Empfehlung umgesetzt, Antwort offen):
    Abschnitt „ezLoot.sources“ für alle Gegenstände, nicht nur Rohstoffe (Spieltest 14.11.2026: „bei dir n×“ am
    Gegenstand vermisst).
      „Beute bei dir: 6× von Junger Wolf (Wald von Elwynn)“   die häufigsten zwei Gegner, mit Shift fünf und dazu
      „– in 3 von 4 Plünderungen“                              in wie vielen der gezählten Leichen er lag
    Nie geplündert: keine Zeile (ein Gegenstand hat viele Herkünfte – „noch nicht“ an jedem Gegenstand wäre Lärm).
    Daten nur selbst Gesammeltes (Leitlinie 11, die Zeile sagt „bei dir“), gerechnet von ezCore: welche Gegner
    ihn fallen ließen, aus Core.History.LootSources; die Zahlen je Gegner aus derselben Zählung wie im Gegner-Tooltip
    (Drops.Get: Core.Drops über History.LootOfNpc, sonst der Beute-Verlauf). Keine eigene Rechnung im Modul.
    Schalter „itemLoot“ (ab Werk an) unter „Allgemein“ neben „Beute im Tooltip von Gegnern“, /ezl gegenstand bzw.
    /ezl item, Zeile in /ezl status. Platz „loot“ im Gegenstands-Tooltip (Core.Tooltip.ORDER.loot, hinter den
    Fundorten). Ist der Schalter an und hat der Gegenstand eine Zeile, weicht ezCores Zeile
    „Beute bei dir von: …“ an Rohstoffen (Core.Tooltip.ClaimLine("lootFrom")) – die Angabe steht einmal; Schalter aus: ezCores
    Zeile ist wieder da.

      ItemLoot.Get(itemID)          → { { npc, name, zone, n, times, loots, what } … } geprüft kopiert, häufigste
                                      zuerst, höchstens LONG mit Zahlen je Gegner (zwischengespeichert; frisch nach
                                      HISTORY_ADDED, HISTORY_REMOVED und HISTORY_CLEARED der Art „loot“)
      ItemLoot.Lines(itemID, long)  → Zeilen (ohne Oberfläche, gut prüfbar)
      ItemLoot.AddSection(tooltip, itemID) → Zahl der Zeilen
      ItemLoot.OriginLine(itemID)   → „Herkunft laut Questie: fällt von …“ oder nil (siehe unten, Welle 23)
]]

local I = {}
ns.ItemLoot = I

I.SHORT = 2                 -- Gegner ohne Shift
I.LONG = 5                  -- mit Shift
I.COUNT_MAX = 20            -- Gegner, deren Zählung vor dem Sortieren nachgeschlagen wird
I.CACHE_TIME = 60           -- Sekunden (Sicherheitsnetz; Änderungen meldet ezCore)
I.CACHE_MAX = 200           -- Gegenstände im Zwischenspeicher; darüber wird er geleert (wie ezCores Gathering.lua)
I.RGB = { 0.6, 0.9, 0.6 }   -- wie ezCores Zeilen „Fundorte“ und „Beute bei dir von“ (Platz gathering, direkt davor)

local Num, Plain = Core.Num, Core.Plain
local Clock = Core.Uptime
local cache, cached = {}, 0 -- [itemID] = { list, at, ver }; cached = Zahl der Einträge

function I.Available()
    local history = Core.History
    return type(history) == "table" and type(history.LootSources) == "function"
end

local function Text(value)
    value = Plain(value)
    return type(value) == "string" and value ~= "" and value or nil
end

-- Zahlen dieses Gegenstands bei diesem Gegner aus der Zählung des Gegner-Tooltips (Drops.Get).
local function Counted(entry, itemID)
    local s = ns.Drops.Get(entry.npc)
    if type(s) ~= "table" then return end
    entry.name = entry.name or Text(s.name)
    if (s.loots or 0) < 1 then return end
    for _, item in ipairs(s.items or {}) do
        if item.id == itemID then
            entry.n, entry.times = item.n or entry.n, math.min(item.times or 0, s.loots)
            entry.loots, entry.what = s.loots, s.what
            return
        end
    end
end

local function Build(itemID)
    local ok, list = pcall(Core.History.LootSources, itemID)
    if not ok or ns.IsSecret(list) or type(list) ~= "table" then return {} end
    local out = {}
    for _, e in ipairs(list) do
        if type(e) == "table" and not ns.IsSecret(e) then
            local npc = Num(e.npc)
            local entry = { npc = npc and npc > 0 and npc or nil, name = Text(e.name), zone = Text(e.zone),
                n = Num(e.n) or 0, times = Num(e.times) or 0 }
            if entry.times > 0 and (entry.name or entry.npc) then out[#out + 1] = entry end
        end
    end
    local function Order(a, b)
        if a.times ~= b.times then return a.times > b.times end
        if a.n ~= b.n then return a.n > b.n end
        return (a.npc or 0) < (b.npc or 0)
    end
    table.sort(out, Order)
    -- Zahlen je Gegner aus der Zählung (Drops.Get), dann noch einmal sortieren: die Zählung der Datenbank reicht weiter
    -- zurück als der gekappte Verlauf, sonst stünde der häufigste Gegner hinten (Gegenprüfung). Nur die ersten
    -- COUNT_MAX nach dem Verlauf – jede Abfrage geht durch den Verlauf.
    for i = 1, math.min(I.COUNT_MAX, #out) do
        if out[i].npc then Counted(out[i], itemID) end
    end
    table.sort(out, Order)
    for i = 1, math.min(I.LONG, #out) do
        out[i].name = out[i].name or L.POSSIBLE_NPC:format(out[i].npc or 0)
    end
    return out
end

function I.Get(itemID)
    if ns.IsSecret(itemID) then return {} end
    itemID = Num(itemID)
    if not (itemID and itemID > 0 and I.Available()) then return {} end
    local c = cache[itemID]
    -- frisch: jünger als CACHE_TIME und derselbe Stand von ezCores Zählung (Drops.DbVersion: Tode, leere Fenster)
    if c and Clock() - c.at < I.CACHE_TIME and c.ver == ns.Drops.DbVersion() then return c.list end
    local list = Build(itemID)
    if not c then
        -- höchstens CACHE_MAX Gegenstände (Stöbern im Auktionshaus oder in der Bank ohne zu plündern)
        if cached >= I.CACHE_MAX then wipe(cache); cached = 0 end
        cached = cached + 1
    end
    cache[itemID] = { list = list, at = Clock(), ver = ns.Drops.DbVersion() }
    return list
end

function I.ClearCache()
    wipe(cache); cached = 0
    I.ClearOrigin()
end

-- Ein Gegner: „6× von Junger Wolf (Wald von Elwynn)“, mit Shift „– in 3 von 4 Plünderungen“ (bzw. „getöteten“).
function I.EntryText(e, long)
    local who = e.zone and L.ITEMLOOT_NPC_ZONE:format(e.name, e.zone) or e.name
    local text = L.ITEMLOOT_FROM:format(e.n > 0 and e.n or e.times, who)
    if long and e.loots then
        text = text .. (e.what == "deaths" and L.ITEMLOOT_IN_DEATHS or L.ITEMLOOT_IN):format(e.times, e.loots)
    end
    return text
end

function I.Lines(itemID, long)
    local lines = {}
    local list = I.Get(itemID)
    if #list == 0 then return lines end
    local limit = long and I.LONG or I.SHORT
    for i = 1, math.min(limit, #list) do
        lines[#lines + 1] = (i == 1 and L.ITEMLOOT_HEAD or L.ITEMLOOT_NEXT):format(I.EntryText(list[i], long))
    end
    if #list > limit then
        lines[#lines + 1] = "  " .. ns.Drops.MoreText(#list - limit, long)
    end
    return lines
end

local function ShiftDown() return IsShiftKeyDown ~= nil and IsShiftKeyDown() == true end

-- Zeigt ezLoot für diesen Gegenstand eine Zeile? Dann weicht ezCores „Beute bei dir von: …“ (eine Aussage je
-- Zeile, FP-06).
function I.Shows(itemID)
    return ns.Enabled("itemLoot") and #I.Get(itemID) > 0
end

-- Herkunft laut einer angebundenen Datenbank („fällt von …“) an Nicht-Rohstoffen (Welle 23, Entscheidung des Nutzers
-- vom 16.11.2026, Nr. 24 – vorläufig nach Empfehlung): dieselbe Zeile wie ezCores an Rohstoffen
-- (Core.Gathering.OriginText: „Herkunft laut Questie: fällt von …; verkauft von …“, nennt die Quelle, Leitlinie 11;
-- an Quest-Gegenständen nicht, solange Questies Tooltip läuft; verschleierte Gegenstände nur mit Entdecker-Wissen).
-- Nur ohne eigene Beute (auch bei ausgeschalteter Zeile „Beute bei dir“) und nicht an Rohstoffen – dort steht sie
-- schon in ezCores Abschnitt. Schalter „itemOrigin“ (ab Werk an), /ezl herkunft bzw. /ezl origin.
local originCache, originCached = {}, 0   -- [itemID] = { text = Text | false, at }

function I.ClearOrigin() wipe(originCache); originCached = 0 end

function I.OriginAvailable()
    local G = Core.Gathering
    return type(G) == "table" and type(G.OriginText) == "function"
end

local function IsResource(itemID)
    local K = Core.Knowledge
    if not (type(K) == "table" and type(K.IsResource) == "function") then return false end
    local ok, yes = pcall(K.IsResource, itemID)
    return ok and yes == true
end

function I.Origin(itemID)
    if ns.IsSecret(itemID) then return nil end
    itemID = Num(itemID)
    if not (itemID and itemID > 0 and I.OriginAvailable()) then return nil end
    local c = originCache[itemID]
    if c and Clock() - c.at < I.CACHE_TIME then return c.text or nil end
    local ok, text = pcall(Core.Gathering.OriginText, itemID)
    text = ok and not ns.IsSecret(text) and type(text) == "string" and text ~= "" and text or false
    if not c then
        if originCached >= I.CACHE_MAX then wipe(originCache); originCached = 0 end
        originCached = originCached + 1
    end
    originCache[itemID] = { text = text, at = Clock() }
    return text or nil
end

-- Rezept-Gegenstand (Klasse 9), solange ezCraft läuft: Dessen Abschnitt „Erhältlich bei … laut Questie“
-- (ezCraft.recipeWhere) fragt dieselbe Datenbank (Knowledge.RecipeWhere über Sources.WhereFrom) – die Herkunft stünde
-- sonst zweimal da (Gegenprüfung Welle 23). Meldet ein Abschnitt die Aussage „origin“ an (Tooltip.ClaimLine), gilt das
-- für jeden Gegenstand; ezCraft tut das noch nicht (offen in docs/roadmap/ezLoot.md).
local function ShownElsewhere(itemID)
    local T = Core.Tooltip
    if type(T) == "table" and type(T.Shows) == "function" then
        local ok, yes = pcall(T.Shows, itemID, "origin")
        if ok and yes == true then return true end
    end
    if not (type(Core.IsLoaded) == "function" and Core.IsLoaded("ezCraft")) then return false end
    local K = Core.Knowledge
    if not (type(K) == "table" and type(K.RecipeItemProfession) == "function") then return false end
    local ok, prof = pcall(K.RecipeItemProfession, itemID)
    return ok and not ns.IsSecret(prof) and prof ~= nil
end
I.OriginShownElsewhere = ShownElsewhere

-- Zeile „Herkunft laut …“ für diesen Gegenstand oder nil (Schalter, Rohstoff, schon anderswo im Tooltip, eigene
-- Beute). Eigene Beute zählt auch bei ausgeschaltetem itemLoot: Die Herkunft gilt nur für nie Geplündertes
-- (OPT_itemOrigin_TIP, STATUS_ITEMORIGIN_ON).
function I.OriginLine(itemID)
    if not ns.Enabled("itemOrigin") or IsResource(itemID) or ShownElsewhere(itemID) or #I.Get(itemID) > 0 then
        return nil
    end
    return I.Origin(itemID)
end

-- Abstand (S-1811-Tooltipabstand): ezCores Trenner in der Gruppe der Fundorte (Core.Gathering.TOOLTIP_GROUP, „origin“) –
-- direkt hinter ezCores Fundorten keine Leerzeile, sonst eine.
function I.Gap(tooltip)
    local T, G = Core.Tooltip, Core.Gathering
    if not (type(T) == "table" and type(T.Gap) == "function") then return false end
    return T.Gap(tooltip, type(G) == "table" and G.TOOLTIP_GROUP or "origin")
end

function I.AddSection(tooltip, itemID)
    local lines = ns.Enabled("itemLoot") and I.Lines(itemID, ShiftDown()) or {}
    if #lines > 0 then I.Gap(tooltip) end
    for _, text in ipairs(lines) do tooltip:AddLine(text, I.RGB[1], I.RGB[2], I.RGB[3], true) end
    if #lines > 0 then
        I.shownItem = Num(itemID)
        return #lines
    end
    local origin = I.OriginLine(itemID)
    if not origin then return 0 end
    I.Gap(tooltip)
    tooltip:AddLine(origin, I.RGB[1], I.RGB[2], I.RGB[3], true)
    return 1
end

local tooltip = Core.Tooltip
if type(tooltip) == "table" and type(tooltip.AddItemSection) == "function" then
    -- eigener Platz „loot“ hinter ezCores Fundorten (Tooltip.ORDER.loot, Welle 23c/A28; vorher „gathering“ wie ezCores
    -- Zeile „Beute bei dir von“, die hier weicht)
    tooltip.AddItemSection("ezLoot.sources", "loot", function(tip, itemID) I.AddSection(tip, itemID) end, ADDON)
end
if type(tooltip) == "table" and type(tooltip.ClaimLine) == "function" then
    tooltip.ClaimLine("lootFrom", ADDON, function(itemID) return I.Shows(itemID) end)
end

-- Neue oder entfernte Beute ändert auch den Nenner „in a von b“ anderer Gegenstände desselben Gegners: alles frisch.
local function Forget(kind)
    if kind == nil or kind == "loot" then I.ClearCache() end
end
Core.Listen("HISTORY_ADDED", Forget, ADDON)
Core.Listen("HISTORY_REMOVED", Forget, ADDON)
Core.Listen("HISTORY_CLEARED", Forget, ADDON)

-- Shift gedrückt oder losgelassen, während der Tooltip unsere Zeilen an diesem Gegenstand zeigt: neu zeichnen.
function I.OnModifier(key)
    if key ~= "LSHIFT" and key ~= "RSHIFT" then return false end
    if not (I.shownItem and GameTooltip and GameTooltip:IsShown() and GameTooltip.GetItem and GameTooltip.RefreshData) then
        return false
    end
    local ok, _, _, id = pcall(GameTooltip.GetItem, GameTooltip)
    if not ok or ns.IsSecret(id) or Num(id) ~= I.shownItem then return false end
    return pcall(GameTooltip.RefreshData, GameTooltip) == true
end
ns.On("MODIFIER_STATE_CHANGED", function(_, key) I.OnModifier(key) end)
