local _, ns = ...
local L = ns.L

--[[
    Leistung (Titan Performance): Bilder pro Sekunde, Latenz, Speicher.
    Verbesserungen: Messwerte werden zeitgleichmäßig gesammelt (nicht bei jedem
    Neuzeichnen), der teure Addon-Speicher wird nur beim Öffnen des Tooltips
    und höchstens alle 10 Sekunden gemessen – nie im Kampf.
]]

local block = ns.RegisterBlock({
    id = "performance",
    command = "leistung",
    name = L.PERF_NAME,
    icon = "Interface\\Icons\\Spell_Nature_TimeStop",
    interval = 1.5,
    colorable = true,
    defaults = {
        enabled = true, zone = "right", order = 10, icon = false,
        fps = true, home = true, world = false, memory = false,
        addons = 10,
    },
    hints = { L.PERF_HINT_LEFT },
})

---------------------------------------------------------------------------
-- Messen
---------------------------------------------------------------------------

local fps = { min = nil, max = nil, sum = 0, n = 0 }
local sampler

local function Sample()
    local value = GetFramerate()
    if not ns.Num(value) then return end
    fps.min = fps.min and math.min(fps.min, value) or value
    fps.max = fps.max and math.max(fps.max, value) or value
    fps.sum, fps.n = fps.sum + value, fps.n + 1
end

function block:OnEnable()
    if not sampler then
        -- Erst nach dem Ladebildschirm messen, sonst verfälscht das Minimum.
        C_Timer.After(5, function()
            if not sampler and self.cfg.enabled then sampler = C_Timer.NewTicker(1, Sample) end
        end)
    end
end

function block:OnDisable()
    if sampler then
        sampler:Cancel()
        sampler = nil
    end
end

local function FpsColor(v)
    if v < 20 then return ns.RED elseif v < 30 then return ns.YELLOW end
    return ns.GREEN
end

local function MsColor(v)
    if v > 600 then return ns.RED elseif v > 300 then return ns.YELLOW end
    return ns.GREEN
end

local addonCache, addonCacheTime = nil, 0

local function AddonMemory()
    if ns.InCombat() then return addonCache end
    if addonCache and GetTime() - addonCacheTime < 10 then return addonCache end
    if not (UpdateAddOnMemoryUsage and GetAddOnMemoryUsage) then return nil end
    UpdateAddOnMemoryUsage()
    local num = (C_AddOns and C_AddOns.GetNumAddOns or GetNumAddOns)()
    local list = {}
    for i = 1, num do
        local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(i) or (IsAddOnLoaded and IsAddOnLoaded(i))
        if loaded then
            local name, title = (C_AddOns and C_AddOns.GetAddOnInfo or GetAddOnInfo)(i)
            local kb = GetAddOnMemoryUsage(i)
            if ns.Num(kb) then list[#list + 1] = { name = title or name, kb = kb } end
        end
    end
    table.sort(list, function(a, b) return a.kb > b.kb end)
    addonCache, addonCacheTime = list, GetTime()
    return list
end

local function Memory(kb)
    if kb >= 1024 then return ezCore.Decimal(kb / 1024, 1) .. " MB" end   -- Dezimalzeichen der Spielsprache (T16-2)
    return ("%.0f KB"):format(kb)
end

---------------------------------------------------------------------------
-- Anzeige
---------------------------------------------------------------------------

function block:GetText()
    local cfg = self.cfg
    local parts = {}
    local _, _, home, world = GetNetStats()
    if cfg.fps then
        local v = GetFramerate() or 0
        parts[#parts + 1] = FpsColor(v) .. ("%.0f"):format(v) .. "|r " .. L.PERF_FPS
    end
    if cfg.home and ns.Num(home) then
        parts[#parts + 1] = MsColor(home) .. home .. "|r " .. L.PERF_MS
    end
    if cfg.world and ns.Num(world) then
        parts[#parts + 1] = MsColor(world) .. world .. "|r " .. L.PERF_MS_WORLD
    end
    if cfg.memory then
        parts[#parts + 1] = Memory(collectgarbage("count"))
    end
    if #parts == 0 then return "" end
    return table.concat(parts, "  ")
end

function block:OnTooltip(tooltip)
    local cfg = self.cfg
    local bwIn, bwOut, home, world = GetNetStats()
    local v = GetFramerate() or 0
    tooltip:AddDoubleLine(L.PERF_FPS_NOW, FpsColor(v) .. ezCore.Decimal(v, 1) .. "|r")
    if fps.n > 0 then
        ns.TipDoubleLine(tooltip, L.PERF_FPS_AVG, ezCore.Decimal(fps.sum / fps.n, 1), "normal", "highlight")
        ns.TipDoubleLine(tooltip, L.PERF_FPS_MINMAX, ("%.0f / %.0f"):format(fps.min, fps.max), "normal", "highlight")
    end
    tooltip:AddLine(" ")
    if ns.Num(home) then tooltip:AddDoubleLine(L.PERF_LAT_HOME, MsColor(home) .. home .. " ms|r") end
    if ns.Num(world) then tooltip:AddDoubleLine(L.PERF_LAT_WORLD, MsColor(world) .. world .. " ms|r") end
    if ns.Num(bwIn) and ns.Num(bwOut) then
        ns.TipDoubleLine(tooltip, L.PERF_BANDWIDTH, ezCore.Decimal(bwIn, 1) .. " / " .. ezCore.Decimal(bwOut, 1) .. " KB/s", "normal", "highlight")
    end
    tooltip:AddLine(" ")
    ns.TipDoubleLine(tooltip, L.PERF_MEMORY, Memory(collectgarbage("count")), "normal", "highlight")

    if cfg.addons > 0 then
        local list = AddonMemory()
        if list and #list > 0 then
            tooltip:AddLine(" ")
            ns.TipLine(tooltip, L.PERF_TOP_ADDONS:format(math.min(cfg.addons, #list)), "normal")
            for i = 1, math.min(cfg.addons, #list) do
                ns.TipDoubleLine(tooltip, list[i].name, Memory(list[i].kb), "highlight", "highlight")
            end
            if ns.InCombat() then ns.TipLine(tooltip, L.PERF_COMBAT_CACHE, "hint") end
        end
    end
end

function block:OnClick(button)
    if button ~= "LeftButton" then return end
    local before = collectgarbage("count")
    collectgarbage("collect")
    local freed = before - collectgarbage("count")
    addonCache = nil
    ns.Print(L.PERF_FREED:format(Memory(math.max(0, freed))))
end

function block:OnMenu(root)
    local cfg = self.cfg
    local bar = root:CreateButton(L.MENU_BAR_SHOWS)
    ns.MenuCheck(bar, L.PERF_SHOW_FPS, cfg, "fps", self)
    ns.MenuCheck(bar, L.PERF_SHOW_HOME, cfg, "home", self)
    ns.MenuCheck(bar, L.PERF_SHOW_WORLD, cfg, "world", self)
    ns.MenuCheck(bar, L.PERF_SHOW_MEMORY, cfg, "memory", self)
    local list = root:CreateButton(L.PERF_ADDON_COUNT)
    for _, n in ipairs({ 0, 5, 10, 20, 40 }) do
        ns.MenuRadio(list, n == 0 and L.OFF or tostring(n), cfg, "addons", n, self)
    end
    root:CreateButton(L.PERF_RESET, function()
        fps.min, fps.max, fps.sum, fps.n = nil, nil, 0, 0
    end)
end
