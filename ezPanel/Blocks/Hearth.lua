local _, ns = ...
local L = ns.L

--[[
    Ruhestein (wie Titan „Hearth“ und Broker-Plugins): Ruheort und Abklingzeit auf einen Blick,
    beim Leveln und vor dem Raid. Kein Klick zum Benutzen – das ginge nur über einen geschützten
    Knopf; benutzt wird der Ruhestein wie gewohnt aus Tasche oder Aktionsleiste.
    Werte aus der Spiel-API laufen durch ns.Num (Secret Values im Kampf werden übersprungen).
]]

local HEARTHSTONE = 6948
local GCD = 1.5    -- kürzere „Abklingzeiten“ sind die globale Abklingzeit

local block = ns.RegisterBlock({
    id = "hearth",
    command = "ruhestein",
    name = L.HEARTH,
    icon = "Interface\\Icons\\INV_Misc_Rune_01",
    events = { "HEARTHSTONE_BOUND", "BAG_UPDATE_COOLDOWN", "BAG_UPDATE_DELAYED" },
    interval = 1,
    defaults = {
        enabled = false, zone = "left", order = 65,
        location = true,
    },
})

local function BindLocation()
    local place = GetBindLocation and ezCore.Plain(GetBindLocation())
    return type(place) == "string" and place ~= "" and place or nil
end

local function Count()
    -- Kennt der Client die Abfrage nicht, bleibt die Anzahl unbekannt (nil) statt „kein Ruhestein“.
    if not ((C_Item and C_Item.GetItemCount) or GetItemCount) then return nil end
    return ezCore.ItemCount(HEARTHSTONE)
end

-- Restliche Abklingzeit in Sekunden (0 = bereit), nil wenn unbekannt.
local function Remaining()
    local get = (C_Item and C_Item.GetItemCooldown) or GetItemCooldown
    if not get then return nil end
    local ok, start, duration = pcall(get, HEARTHSTONE)
    start, duration = ok and ns.Num(start), ok and ns.Num(duration)
    if not (start and duration) then return nil end
    if start <= 0 or duration <= GCD then return 0 end
    return math.max(0, start + duration - GetTime())
end

function block:GetText()
    local parts = {}
    if self.cfg.location then parts[#parts + 1] = BindLocation() end
    local count, left = Count(), Remaining()
    if count ~= 0 and left then
        parts[#parts + 1] = left > 0 and (ns.OrangeCode() .. ns.Duration(left, true) .. "|r")
            or (ns.GREEN .. L.HEARTH_READY .. "|r")
    end
    if #parts == 0 then return L.HEARTH end
    return table.concat(parts, "  ")
end

function block:OnTooltip(tooltip)
    ns.TipDoubleLine(tooltip, L.HEARTH_HOME, BindLocation() or UNKNOWN or "?", "normal", "highlight")
    local count, left = Count(), Remaining()
    if count == 0 then
        ns.TipLine(tooltip, L.HEARTH_NONE, "orange", true)
    elseif left then
        ns.TipDoubleLine(tooltip, L.HEARTH_COOLDOWN, left > 0 and ns.Duration(left) or L.HEARTH_READY, "normal", "highlight")
    end
end

function block:OnMenu(root)
    ns.MenuCheck(root, L.HEARTH_SHOW_LOCATION, self.cfg, "location", self)
end
