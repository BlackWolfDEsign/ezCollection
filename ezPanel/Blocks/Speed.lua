local _, ns = ...
local L = ns.L

--[[
    Tempo (Titan: „Speed“): aktuelles Tempo in Prozent des normalen Lauftempos, im Tooltip
    Lauf-, Flug- und Schwimmtempo. Werte aus GetUnitSpeed laufen durch ns.Num (im Kampf
    geheime Werte werden übersprungen). Aktualisiert sich nur, solange der Baustein an ist.
]]

local block = ns.RegisterBlock({
    id = "speed",
    command = "tempo",
    name = L.SPEED_NAME,
    label = L.SPEED_LABEL,
    icon = "Interface\\Icons\\Ability_Rogue_Sprint",
    fallbackIcon = ezCore.ICON_FALLBACK,
    interval = 0.5,
    defaults = {
        enabled = false, zone = "left", order = 97,
        standing = "run",    -- im Stand: run (Lauftempo) | hide (Baustein ausblenden)
    },
})

local function Base()
    return BASE_MOVEMENT_SPEED or 7
end

-- Prozent des normalen Lauftempos: aktuell, Lauf, Flug, Schwimmen (nil, wenn unbekannt).
local function Speeds()
    if type(GetUnitSpeed) ~= "function" then return nil end
    local ok, current, run, flight, swim = pcall(GetUnitSpeed, "player")
    if not ok then return nil end
    local base = Base()
    local function Pct(v)
        v = ns.Num(v)
        return v and v / base * 100 or nil
    end
    return Pct(current), Pct(run), Pct(flight), Pct(swim)
end

local function Text(v)
    return v and ezCore.Percent(v) or "?"
end

function block:GetText()
    local current, run = Speeds()
    if current and current > 0 then return Text(current) end
    if self.cfg.standing == "hide" then return nil end
    return ns.Grey(Text(run))
end

function block:OnTooltip(tooltip)
    local current, run, flight, swim = Speeds()
    ns.TipDoubleLine(tooltip, L.SPEED_CURRENT, Text(current), "normal", "highlight")
    ns.TipDoubleLine(tooltip, L.SPEED_RUN, Text(run), "normal", "highlight")
    if flight and run and flight > run then ns.TipDoubleLine(tooltip, L.SPEED_FLIGHT, Text(flight), "normal", "highlight") end
    if swim then ns.TipDoubleLine(tooltip, L.SPEED_SWIM, Text(swim), "normal", "highlight") end
end

function block:OnMenu(root)
    local still = root:CreateButton(L.SPEED_STANDING)
    ns.MenuRadio(still, L.SPEED_STANDING_RUN, self.cfg, "standing", "run", self)
    ns.MenuRadio(still, L.SPEED_STANDING_HIDE, self.cfg, "standing", "hide", self)
end
