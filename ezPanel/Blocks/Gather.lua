local _, ns = ...
local L = ns.L

--[[
    Sammeln (SAM-26, Welle 15): Ernten, Ertrag und Wert dieser Sitzung – nur aus ezCores Sammel-Zähler, kein eigener
    Zähler und keine eigene Preisrechnung (SSOT: ezCore).
      Core.Gathering.SessionStats() → { harvests, kinds = { art = n }, items = { [itemID] = menge }, value, priced,
        start } (SAM-09, ezCore/Wissen/Gathering.lua). Der Zähler hängt an Core.Session (Session.Data
        ("ezCore.gathering")), übersteht /reload und leert sich mit „Sitzung zurücksetzen“ (Core.Session.Reset, für
        alle Module). value ist der Marktwert aus Core.Prices (Prices.Value); das Alter der Preise nennt Prices.Get
        (seen) – der Tooltip zeigt den ältesten.
    Leiste: Ernten, dazu (abwählbar) der Wert und Ernten je Stunde.
    Tooltip: Dauer der Sitzung, Ernten je Art, Ertrag je Gegenstand mit Wert, Wert gesamt, je Stunde, Alter der Preise
    und Quelle; ohne Ernte ein erklärender Text.
    Linksklick: Weltkarte mit gesetztem Sammel-Filter über ezCore.API("ezMap").ShowGather({ art }) – die Art mit den
    meisten Ernten dieser Sitzung; das Menü bietet jede geerntete Art einzeln. Ohne ezMap nur der Tooltip.
    Menü „Sitzung zurücksetzen“: Core.Session.Reset (über ns.NewSession, dieselbe Stelle wie im Gold-Baustein).
]]

local Core = ezCore

local ITEM_LINES = 8     -- Gegenstände im Tooltip
local MIN_RATE = 60      -- Sekunden: erst danach „je Stunde“ (sonst sinnlos große Zahlen)

local block = ns.RegisterBlock({
    id = "gather",
    command = "sammeln",
    name = L.GATHER_NAME,
    label = L.GATHER_LABEL,
    icon = "Interface\\Icons\\Trade_Herbalism",
    fallbackIcon = "Interface\\Icons\\INV_Misc_Herb_07",
    events = { "PLAYER_ENTERING_WORLD" },
    colorable = true,
    defaults = {
        enabled = false, zone = "right", order = 47,
        value = true,           -- Wert der Sitzung auf der Leiste
        rate = false,           -- Ernten je Stunde auf der Leiste
    },
})

---------------------------------------------------------------------------
-- Daten (nur lesen)
---------------------------------------------------------------------------

-- ezCores Sammel-Zähler oder nil (älteres ezCore).
local function Stats()
    local G = Core.Gathering
    if type(G) ~= "table" or type(G.SessionStats) ~= "function" then return nil end
    local ok, stats = pcall(G.SessionStats)
    if not ok or type(stats) ~= "table" then return nil end
    stats.kinds = type(stats.kinds) == "table" and stats.kinds or {}
    stats.items = type(stats.items) == "table" and stats.items or {}
    return stats
end
block.Stats = Stats

local function Duration()
    local S = Core.Session
    local d = S and type(S.Duration) == "function" and ns.Num(S.Duration()) or nil
    return d or 0
end

-- n je Stunde oder nil (zu kurze Sitzung).
local function PerHour(n, duration)
    n = ns.Num(n)
    if not n or duration < MIN_RATE then return nil end
    return n * 3600 / duration
end
block.PerHour = PerHour

-- Geerntete Arten, meiste zuerst: { { kind, n } … }.
local function Kinds(stats)
    local list = {}
    for kind, n in pairs(stats and stats.kinds or {}) do
        n = ns.Num(n)
        if n and n > 0 then list[#list + 1] = { kind = kind, n = n } end
    end
    table.sort(list, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return tostring(a.kind) < tostring(b.kind)
    end)
    return list
end
block.Kinds = Kinds

local function KindLabel(kind)
    local text = L["GATHER_KIND_" .. tostring(kind)]
    if type(text) ~= "string" or text == "GATHER_KIND_" .. tostring(kind) then return tostring(kind) end
    return text
end

-- Ertrag, größte Menge zuerst: { { item, n, value, seen } … }; value und seen aus Core.Prices (oder nil).
local function Items(stats)
    local P = Core.Prices
    local list = {}
    for item, n in pairs(stats and stats.items or {}) do
        n = ns.Num(n)
        if n and n > 0 then
            local e = { item = item, n = n }
            if P and type(P.Value) == "function" then
                local ok, v = pcall(P.Value, item, n)
                e.value = ok and ns.Num(v) or nil
            end
            if e.value and type(P.Get) == "function" then
                local ok, info = pcall(P.Get, item)
                e.seen = ok and type(info) == "table" and ns.Num(info.seen) or nil
            end
            list[#list + 1] = e
        end
    end
    table.sort(list, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return (ns.Num(a.item) or 0) < (ns.Num(b.item) or 0)
    end)
    return list
end
block.Items = Items

---------------------------------------------------------------------------
-- Anzeige
---------------------------------------------------------------------------

function block:GetText()
    local stats = Stats()
    if not stats then return ns.Grey(L.GATHER_NO_CORE_SHORT) end
    local harvests = ns.Num(stats.harvests) or 0
    if harvests == 0 and not next(stats.items) then return ns.Grey(L.GATHER_NONE_SHORT) end
    local cfg = self.cfg
    local parts = { L.GATHER_HARVESTS_SHORT:format(harvests) }
    local value = ns.Num(stats.value) or 0
    if cfg.value and value > 0 then parts[#parts + 1] = ns.Money(value) end
    if cfg.rate then
        local rate = PerHour(harvests, Duration())
        if rate then parts[#parts + 1] = L.GATHER_RATE_SHORT:format(ns.Number(math.floor(rate + 0.5))) end
    end
    return table.concat(parts, ns.Grey(" · "))
end

local function Line(tooltip, left, right)
    ns.TipDoubleLine(tooltip, left, right, "normal", "highlight")
end

-- „12 (30 je Stunde)“
local function WithRate(text, n, duration)
    local rate = PerHour(n, duration)
    if not rate then return text end
    return L.GATHER_WITH_RATE:format(text, ns.Number(math.floor(rate + 0.5)))
end

function block:OnTooltip(tooltip)
    local stats = Stats()
    if not stats then
        ns.TipLine(tooltip, L.GATHER_NO_CORE, "highlight", true)
        return
    end
    local harvests = ns.Num(stats.harvests) or 0
    local items = Items(stats)
    local duration = Duration()
    Line(tooltip, L.SESSION, ns.Duration(duration, true))
    if harvests == 0 and #items == 0 then
        ns.TipLine(tooltip, L.GATHER_NONE, "highlight", true)
        if not ns.IsLoaded("ezMap") then ns.TipLine(tooltip, L.GATHER_NO_EZMAP, "hint", true) end
        return
    end
    Line(tooltip, L.GATHER_HARVESTS, WithRate(ns.Number(harvests), harvests, duration))
    for _, k in ipairs(Kinds(stats)) do
        ns.TipDoubleLine(tooltip, "  " .. KindLabel(k.kind), WithRate(ns.Number(k.n), k.n, duration), "highlight", "highlight")
    end
    if #items > 0 then
        tooltip:AddLine(" ")
        ns.TipLine(tooltip, L.GATHER_YIELD, "normal")
        local oldest, unpriced = nil, 0
        for i, e in ipairs(items) do
            if not e.value then unpriced = unpriced + 1 end
            if e.seen and (not oldest or e.seen < oldest) then oldest = e.seen end
            if i <= ITEM_LINES then
                -- Symbol und Name in der Farbe der Qualität über ezCores Helfer (Wunsch vom 18.11.2026 „mit den item
                -- icons“); ohne Helfer wie vorher der Name allein
                local name
                if type(Core.ItemIconText) == "function" then
                    name = Core.ItemIconText(e.item) or Core.ItemIconText(e.item, L.UNKNOWN)
                else
                    name = Core.ItemNameByID and Core.ItemNameByID(e.item) or nil
                end
                ns.TipDoubleLine(tooltip, "  " .. (name or L.UNKNOWN) .. " ×" .. WithRate(ns.Number(e.n), e.n, duration), e.value and ns.Money(e.value) or ns.Grey(L.GATHER_NO_PRICE), "highlight", "highlight")
            end
        end
        if #items > ITEM_LINES then
            ns.TipLine(tooltip, "  " .. ezCore.More(#items - ITEM_LINES), "hint")
        end
        local value = ns.Num(stats.value) or 0
        tooltip:AddLine(" ")
        if value > 0 then
            local rate = PerHour(value, duration)
            Line(tooltip, L.GATHER_VALUE, ns.Money(value))
            if rate then Line(tooltip, L.GATHER_VALUE_RATE, ns.Money(math.floor(rate + 0.5))) end
            if oldest then ns.TipLine(tooltip, L.GATHER_PRICE_AGE:format(ns.Ago(oldest)), "hint", true) end
        end
        if unpriced > 0 then
            ns.TipLine(tooltip, L.GATHER_UNPRICED:format(unpriced, #items), "hint", true)
        end
    end
    tooltip:AddLine(" ")
    ns.TipLine(tooltip, L.GATHER_SOURCE, "hint", true)
    if not ns.IsLoaded("ezMap") then ns.TipLine(tooltip, L.GATHER_NO_EZMAP, "hint", true) end
end

---------------------------------------------------------------------------
-- Klick: Weltkarte mit Sammel-Filter (ezMap); Menü: Arten, Sitzung zurücksetzen
---------------------------------------------------------------------------

local function MapAPI()
    local api = Core.API and Core.API("ezMap")
    if type(api) ~= "table" or type(api.ShowGather) ~= "function" then return nil end
    return api
end
block.MapAPI = MapAPI

-- Antwort von ShowGather in Worte fassen (Grund bei false: args, kind, explorer, nocore, none, nomap).
local REASON = { kind = "GATHER_MAP_KIND", explorer = "GATHER_MAP_EXPLORER", none = "GATHER_MAP_NONE",
    nomap = "GATHER_MAP_NOMAP", nocore = "GATHER_MAP_NOCORE" }

-- Weltkarte mit der Art öffnen (ohne Angabe: die meistgeerntete). → true, wenn ezMap sie öffnet oder vormerkt.
local function ShowMap(kind)
    local api = MapAPI()
    if not api then
        ns.Print(L.GATHER_NO_EZMAP)
        return false
    end
    kind = kind or (Kinds(Stats())[1] or {}).kind
    if not kind then
        ns.Print(L.GATHER_MAP_NOTHING)
        return false
    end
    local ok, done, info = pcall(api.ShowGather, { art = kind })
    if not ok then
        ns.Error(done, "ShowGather")
        return false
    end
    if not done then
        local key = REASON[info] or "GATHER_MAP_FAILED"
        ns.Print(L[key]:format(KindLabel(kind)))
        return false
    end
    if type(info) == "table" and info.later then Core.CombatNotice(ns, L.GATHER_MAP_WHAT, "later") end   -- T18-1
    return true
end
block.ShowMap = ShowMap

local function ResetSession()
    ns.NewSession()   -- Core.Session.Reset: ezCores Sammel-Zähler leert sich mit (für alle Module)
    ns.UpdateAllBlocks()
    ns.Print(L.SESSION_RESET)
end
block.ResetSession = ResetSession

block.hints = function()
    if not MapAPI() or not Kinds(Stats())[1] then return {} end
    return { L.GATHER_HINT_LEFT }
end

block.actions = function()
    local list = {}
    if MapAPI() then
        for _, k in ipairs(Kinds(Stats())) do
            local kind = k.kind
            list[#list + 1] = { text = L.GATHER_MAP_ACTION:format(KindLabel(kind)), fn = function() ShowMap(kind) end }
        end
    end
    list[#list + 1] = { text = L.MENU_RESET_SESSION, fn = ResetSession }
    return list
end

function block:OnClick(button)
    if button ~= "LeftButton" or not MapAPI() then return end
    ShowMap()
end

function block:OnMenu(root)
    local cfg = self.cfg
    local bar = root:CreateButton(L.MENU_BAR_SHOWS)
    ns.MenuCheck(bar, L.GATHER_SHOW_VALUE, cfg, "value", self)
    ns.MenuCheck(bar, L.GATHER_SHOW_RATE, cfg, "rate", self)
end

-- Neue Ernte (ezCore zählt sie vorher) und neue Preise: neu zeichnen. SESSION_RESET zeichnet Core.lua alle neu.
local function Refresh() ns.QueueUpdate(block) end
Core.Listen("GATHERING_HARVEST", Refresh, "ezPanel")
Core.Listen("PRICES_CHANGED", Refresh, "ezPanel")
