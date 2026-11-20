local _, ns = ...
local L = ns.L

--[[
    Gegenstandsstufe (Titan: „Item Level“): eigene Gegenstandsstufe auf der Leiste, im Tooltip
    angelegt und in den Taschen, die Stufe jedes Platzes (niedrigster zuerst markiert) und die
    Gegenstandsstufe der anderen Charaktere (ezCore erfasst sie für alle: ezCore.ItemLevelOf).
    Linksklick öffnet Blizzards Charakterfenster. Die Bewertung „besser“ gehört zu ezGear.
    Die Plätze kommen aus ezCore.EquipSlots.LIST (Reihenfolge des Charakterfensters, ohne Hemd und Wappenrock).
]]

local EquipSlots = ezCore.EquipSlots

local block = ns.RegisterBlock({
    id = "ilvl",
    command = "itemlevel",
    name = L.ILVL_NAME,
    label = L.ILVL_LABEL,
    icon = "Interface\\Icons\\INV_Chest_Chain_05",
    fallbackIcon = ezCore.ICON_FALLBACK,
    events = { "PLAYER_EQUIPMENT_CHANGED", "PLAYER_AVG_ITEM_LEVEL_UPDATE", "PLAYER_ENTERING_WORLD" },
    defaults = {
        enabled = false, zone = "left", order = 62,
        overall = false,     -- auf der Leiste zusätzlich die Stufe mit den Taschen
        slots = true,        -- Plätze im Tooltip
        alts = true,         -- andere Charaktere im Tooltip
    },
    hints = function() return { L.ILVL_HINT_LEFT } end,
})

-- Stufe eines angelegten Gegenstands (wie Blizzards Charakterfenster) und sein Link; nil wenn leer.
-- Eine Rechnung mit ezGear: ezCore.SlotText.EquippedLevel.
local function SlotLevel(slot)
    local level, _, link = ezCore.SlotText.EquippedLevel("player", slot)
    return level, link
end

local function Format(v)
    return v and ezCore.Decimal(v, 1) or "?"   -- Dezimalzeichen der Spielsprache (Gesamtreview 18.11.2026, T16-2)
end

function block:GetText()
    local equipped, overall = ns.ItemLevel()
    if not equipped then return "?" end
    local text = Format(equipped)
    if self.cfg.overall and overall and math.floor(overall * 10 + 0.5) ~= math.floor(equipped * 10 + 0.5) then
        text = text .. " " .. ns.Grey("(" .. Format(overall) .. ")")
    end
    return text
end

function block:OnTooltip(tooltip)
    local cfg = self.cfg
    local equipped, overall = ns.ItemLevel()
    ns.TipDoubleLine(tooltip, L.ILVL_EQUIPPED, Format(equipped), "normal", "highlight")
    if overall then ns.TipDoubleLine(tooltip, L.ILVL_OVERALL, Format(overall), "normal", "highlight") end

    if cfg.slots then
        local rows, lowest = {}, nil
        for _, s in ipairs(EquipSlots.LIST) do
            local level, link = nil, nil
            if not s.cosmetic then level, link = SlotLevel(s.slot) end
            if level then
                rows[#rows + 1] = { name = EquipSlots.Label(s.slot) or s.name, level = level, link = link }
                if not lowest or level < lowest then lowest = level end
            end
        end
        if #rows > 0 then
            tooltip:AddLine(" ")
            for _, r in ipairs(rows) do
                local value = r.level == lowest and (ns.RED .. r.level .. "|r") or tostring(r.level)
                ns.TipDoubleLine(tooltip, r.link, value, "highlight", "highlight")
            end
        end
    end

    if cfg.alts then
        local others = ns.Characters(function(_, key) return key ~= ns.charKey and ezCore.ItemLevelOf(key) ~= nil end)
        if #others > 0 then
            tooltip:AddLine(" ")
            ns.TipLine(tooltip, L.OTHER_CHARS, "normal")
            for _, e in ipairs(others) do e.ilvl = ezCore.ItemLevelOf(e.key) end
            table.sort(others, function(a, b) return a.ilvl > b.ilvl end)
            for _, e in ipairs(others) do
                ns.TipDoubleLine(tooltip, ns.CharName(e.c, e.key), ("%.0f"):format(e.ilvl) .. ns.AltStand(e.c), "highlight", "highlight")
            end
        end
    end
end

ezCore.Listen("GEAR_CHANGED", function() ns.QueueUpdate(block) end, "ezPanel")

function block:OnClick(button)
    if button ~= "LeftButton" then return end
    ezCore.TogglePanel("character", "PaperDollFrame")
end

function block:OnMenu(root)
    local cfg = self.cfg
    ns.MenuCheck(root, L.ILVL_SHOW_OVERALL, cfg, "overall", self)
    local tip = root:CreateButton(L.MENU_TOOLTIP)
    ns.MenuCheck(tip, L.ILVL_SHOW_SLOTS, cfg, "slots", self)
    ns.MenuCheck(tip, L.TIP_SHOW_ALTS, cfg, "alts", self)
end
