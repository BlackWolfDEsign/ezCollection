local _, ns = ...
local L = ns.L

--[[
    Währungen (Titan CurrenciesMulti): ausgewählte Währungen auf der Leiste,
    alle bekannten im Tooltip, dazu Wochengrenzen, Sitzung und andere Charaktere.
    Standard wie bei Blizzard: Was im Währungsfenster „Im Rucksack anzeigen“
    hat, steht auch auf der Leiste. Zusätzlich frei wählbar per Rechtsklick.
    Verbesserungen: ereignisgesteuert statt jede Sekunde, Werte anderer
    Charaktere werden bei jeder Änderung gespeichert.
    Seit Welle 2 erfasst und speichert ezCore die Währungen (ezCore.Currencies: Info, Known, Of, Save;
    Nachricht CURRENCIES_CHANGED). ezPanel schreibt nichts mehr in den Charakter-Datensatz, meldet nur
    seine angehefteten Währungen an (Currencies.Track) und merkt sich die Startwerte der Sitzung.
]]

local Currencies = ezCore.Currencies

local block = ns.RegisterBlock({
    id = "currencies",
    command = "waehrung",
    name = L.CUR_NAME,
    label = L.CUR_LABEL,
    icon = "Interface\\Icons\\INV_Misc_Token_ArgentDawn",
    fallbackIcon = "Interface\\Icons\\INV_Misc_Coin_17",
    events = { "CURRENCY_DISPLAY_UPDATE" },
    defaults = {
        enabled = false, zone = "left", order = 90, label = false,
        backpack = true,
        pinned = {},
        showMax = false,
        alts = true,
    },
    hints = { L.CUR_HINT_LEFT },
})

local C = C_CurrencyInfo or {}

-- Daten einer Währung (gesperrte Menge gilt als unbekannt): ezCore.
local function Info(id)
    return Currencies.Info(id)
end

---------------------------------------------------------------------------
-- Bekannte Währungen sammeln
---------------------------------------------------------------------------

-- Angeheftete Währungen bei ezCore anmelden: Sie werden dann immer geprüft und gespeichert, auch wenn ihr
-- Abschnitt im Währungsfenster eingeklappt ist.
local function TrackPinned()
    local pinned = block.cfg and block.cfg.pinned
    if type(pinned) ~= "table" then return end
    for id in pairs(pinned) do Currencies.Track(id) end
end

-- IDs aus dem Währungsfenster, ezCores fester Forever-Liste (Currencies.EXTRA), angemeldete und gemerkte.
local function Collect()
    TrackPinned()
    return Currencies.Known()
end

local function Backpack()
    local set = {}
    if C.GetBackpackCurrencyInfo then
        for i = 1, 10 do
            local info = C.GetBackpackCurrencyInfo(i)
            if not info then break end
            local id = info.currencyTypesID or info.currencyID
            if id then set[id] = true end
        end
    end
    return set
end

-- Startwerte der Sitzung merken (ns.session.cur) – das Speichern je Charakter macht ezCore
-- (Currencies.Save bei CURRENCY_DISPLAY_UPDATE). Der bisherige Name bleibt für die Aufrufer.
local function Save()
    local s = ns.session
    if not s or not block.cfg then return end
    s.cur = s.cur or {}
    for _, id in ipairs(Collect()) do
        local info = Info(id)
        if info and (info.discovered ~= false or (info.quantity or 0) > 0) then
            if s.cur[id] == nil then s.cur[id] = info.quantity or 0 end
        end
    end
end

ns.OnReady(function()
    TrackPinned()
    C_Timer.After(2, Save)
end)
-- ezCore hat gespeichert: Startwerte neuer Währungen merken und neu zeichnen.
ezCore.Listen("CURRENCIES_CHANGED", function()
    Save()
    ns.QueueUpdate(block)
end, "ezPanel")

-- Profilwechsel: die angehefteten Währungen des neuen Profils anmelden.
function block:OnConfigChanged() TrackPinned() end
function block:OnEnable() TrackPinned() end

---------------------------------------------------------------------------
-- Anzeige
---------------------------------------------------------------------------

local function Icon(info, size)
    if not info.iconFileID then return "" end
    return "|T" .. info.iconFileID .. ":" .. (size or 0) .. "|t "
end

local function Amount(info, showMax)
    local qty = info.quantity or 0
    local max = info.maxQuantity or 0
    local text = ns.Number(qty)
    if max > 0 then
        local capped = info.useTotalEarnedForMaxQty and (info.totalEarned or 0) >= max or qty >= max
        if capped then text = ns.RED .. text .. "|r" end
        if showMax then text = text .. "/" .. ns.Number(max) end
    end
    return text
end

local function OnBarList()
    local cfg = block.cfg
    local set = cfg.backpack and Backpack() or {}
    for id, on in pairs(cfg.pinned) do
        if on then set[id] = true end
    end
    local list = {}
    for id in pairs(set) do
        local info = Info(id)
        if info then list[#list + 1] = { id = id, info = info } end
    end
    table.sort(list, function(a, b) return a.info.name < b.info.name end)
    return list
end

function block:GetText()
    -- Neue Sitzung (Login, „Sitzung zurücksetzen“): Startwerte sofort merken, nicht erst bei der nächsten Änderung.
    if ns.session and not ns.session.cur then Save() end
    local parts = {}
    for _, e in ipairs(OnBarList()) do
        parts[#parts + 1] = Icon(e.info) .. Amount(e.info, self.cfg.showMax)
    end
    if #parts == 0 then return ns.Grey(L.CUR_NONE) end
    return table.concat(parts, "  ")
end

function block:OnTooltip(tooltip)
    local list = {}
    for _, id in ipairs(Collect()) do
        local info = Info(id)
        if info and ((info.quantity or 0) > 0 or block.cfg.pinned[id]) then
            list[#list + 1] = { id = id, info = info }
        end
    end
    table.sort(list, function(a, b) return a.info.name < b.info.name end)
    if #list == 0 then ns.TipLine(tooltip, L.CUR_NONE_TIP, "highlight", true) end
    local s = ns.session
    for _, e in ipairs(list) do
        local info = e.info
        local right = Amount(info, true)
        local start = s.cur and s.cur[e.id]
        if start and start ~= info.quantity then
            local d = (info.quantity or 0) - start
            right = right .. (d > 0 and (" " .. ns.GREEN .. "+") or (" " .. ns.RED)) .. ns.Number(d) .. "|r"
        end
        ns.TipDoubleLine(tooltip, Icon(info, 14) .. info.name, right, "normal", "highlight")
        if (info.maxWeeklyQuantity or 0) > 0 then
            ns.TipDoubleLine(tooltip, "    " .. L.CUR_WEEKLY, ("%s/%s"):format(ns.Number(info.quantityEarnedThisWeek or 0),
                ns.Number(info.maxWeeklyQuantity)), "hint", "hint")
        end
        if info.useTotalEarnedForMaxQty and (info.maxQuantity or 0) > 0 then
            ns.TipDoubleLine(tooltip, "    " .. L.CUR_CAN_EARN, ns.Number(math.max(0, info.maxQuantity - (info.totalEarned or 0))),
                "hint", "hint")
        end
    end

    if self.cfg.alts then
        local bar = OnBarList()
        local first = true
        for _, entry in ipairs(ns.Characters()) do
            local c = entry.c
            local theirs = not entry.isMe and Currencies.Of(entry.key)
            if theirs then
                local parts = {}
                for _, e in ipairs(bar) do
                    local qty = ns.Num(theirs[e.id])
                    if qty and qty > 0 then parts[#parts + 1] = Icon(e.info) .. ns.Number(qty) end
                end
                if #parts > 0 then
                    if first then
                        tooltip:AddLine(" ")
                        ns.TipLine(tooltip, L.OTHER_CHARS, "normal")
                        first = false
                    end
                    ns.TipDoubleLine(tooltip, ns.CharName(c, entry.key), table.concat(parts, "  ") .. ns.AltStand(c), "highlight", "highlight")
                end
            end
        end
    end
end

function block:OnClick(button)
    if button ~= "LeftButton" then return end
    ezCore.TogglePanel("character", "TokenFrame")
end

function block:OnMenu(root)
    local cfg = self.cfg
    local bar = root:CreateButton(L.MENU_BAR_SHOWS)
    ns.MenuCheck(bar, L.CUR_BACKPACK, cfg, "backpack", self)
    bar:CreateDivider()
    local list = {}
    for _, id in ipairs(Collect()) do
        local info = Info(id)
        if info then list[#list + 1] = { id = id, info = info } end
    end
    table.sort(list, function(a, b) return a.info.name < b.info.name end)
    -- Angeheftete Währungen: nur „Alle abwählen“ (Design-System 2.11 – „alle anheften“ hat keinen Sinn; gemerkt in
    -- cfg.pinned), danach einmal TrackPinned und neu zeichnen
    ns.MenuAllToggle(bar, list, function(e) return cfg.pinned[e.id] == true end,
        function(e, on) cfg.pinned[e.id] = on or nil end,
        function() TrackPinned() ns.QueueUpdate(self) end, { on = false })
    for _, e in ipairs(list) do
        local id = e.id
        bar:CreateCheckbox(Icon(e.info) .. e.info.name, function() return cfg.pinned[id] == true end, function()
            cfg.pinned[id] = not cfg.pinned[id] or nil
            TrackPinned()
            ns.QueueUpdate(self)
            return MenuResponse and MenuResponse.Refresh
        end)
    end
    ns.MenuCheck(root, L.CUR_SHOW_MAX, cfg, "showMax", self)
    ns.MenuCheck(root, L.TIP_SHOW_ALTS, cfg, "alts", self)
end
