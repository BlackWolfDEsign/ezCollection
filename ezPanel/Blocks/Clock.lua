local _, ns = ...
local L = ns.L

--[[
    Uhr (Titan Clock): Server- und/oder Ortszeit, Zeitverschiebung, Datum,
    Tages- und Wochenreset, Stoppuhr/Wecker und Kalender per Klick.
    Verbesserungen: Zeit springt pünktlich um (Prüfung jede Sekunde statt alle
    30 Sekunden), halbe Stunden Verschiebung gehen auch ins Plus, Minimap-Uhr
    und Kalenderknopf bleiben dauerhaft ausgeblendet (Hook statt einmaligem Hide).
]]

local block = ns.RegisterBlock({
    id = "clock",
    command = "uhr",
    name = L.CLOCK_NAME,
    icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    interval = 1,
    defaults = {
        enabled = true, zone = "right", order = 30, icon = false,
        mode = "server",      -- server | local | both
        h24 = true,
        seconds = false,
        date = false,
        offset = 0,           -- Stunden, auch halbe (nur Serverzeit)
        hideMinimapClock = false,
        hideCalendarButton = false,
    },
    hints = { L.CLOCK_HINT_LEFT, ezCore.ClickText("left", "SHIFT", L.CLOCK_HINT_SHIFT) },   -- Klick-Hinweis über ezCore (T18-9)
})

---------------------------------------------------------------------------
-- Zeit
---------------------------------------------------------------------------

local function ServerTime()
    local h, m = GetGameTime()
    local offset = block.cfg.offset or 0
    if offset ~= 0 then
        local total = (h * 60 + m + math.floor(offset * 60 + 0.5)) % 1440
        h, m = math.floor(total / 60), total % 60
    end
    return h, m
end

local function Format(h, m, s)
    local text
    if block.cfg.h24 then
        text = ("%02d:%02d"):format(h, m)
        if s then text = text .. (":%02d"):format(s) end
    else
        local suffix = h < 12 and (TIMEMANAGER_AM or "AM") or (TIMEMANAGER_PM or "PM")
        local h12 = h % 12
        if h12 == 0 then h12 = 12 end
        text = ("%d:%02d"):format(h12, m)
        if s then text = text .. (":%02d"):format(s) end
        text = text .. " " .. suffix
    end
    return text
end

local function LocalText()
    local t = date("*t")
    return Format(t.hour, t.min, block.cfg.seconds and t.sec or nil)
end

local function ServerText()
    local h, m = ServerTime()
    return Format(h, m, block.cfg.seconds and tonumber(date("%S")) or nil)
end

---------------------------------------------------------------------------
-- Blizzard-Uhr an der Minikarte (optional ausblenden)
---------------------------------------------------------------------------

local hooked = {}
-- Nur wieder zeigen, was ezPanel selbst verborgen hat (Gesamtreview 18.11.2026, T2-6; Muster wie hiddenByUs in
-- ezCore/Bausteine/Comfort.lua): Hat Blizzard oder ein anderes Minikarten-Addon den Rahmen verborgen, bleibt er so.
local hiddenByUs = {}
ns.ClockHiddenByUs = hiddenByUs   -- für die Prüfungen

-- Verbirgt danach jemand anderes den Rahmen (Hide oder SetShown(false) von Blizzard oder einem Minikarten-Addon),
-- gilt er als von ihm verborgen: der Merker fällt, ezPanel zeigt ihn beim Abschalten nicht wieder (Gegenprüfung P19b).
-- Das eigene Verbergen setzt hidingOwn, damit der Haken an Hide es nicht als fremd zählt.
local hidingOwn = false
local function HideOwn(frame)
    hiddenByUs[frame] = true
    hidingOwn = true
    frame:Hide()
    hidingOwn = false
end

-- Ausblenden nur, solange der Baustein an ist: Wer die Uhr-Anzeige abschaltet, bekommt Blizzards Uhr zurück
-- (der Schalter liegt im Menü des Bausteins und wäre sonst nicht mehr erreichbar).
local function Wanted(key)
    local cfg = block.cfg
    return cfg ~= nil and cfg.enabled == true and cfg[key] == true
end

local function KeepHidden(frame, key)
    if not frame then return end
    if not hooked[frame] then
        hooked[frame] = true
        hooksecurefunc(frame, "Show", function(self)
            if Wanted(key) then HideOwn(self) else hiddenByUs[self] = nil end
        end)
        hooksecurefunc(frame, "SetShown", function(self, shown)
            if shown and Wanted(key) then
                HideOwn(self)
            elseif not shown and not hidingOwn then
                hiddenByUs[self] = nil
            end
        end)
        hooksecurefunc(frame, "Hide", function(self)
            if not hidingOwn then hiddenByUs[self] = nil end
        end)
    end
    if Wanted(key) then
        -- schon verborgen (von ezPanel oder von anderen): nichts tun, der Merker bleibt, wie er ist
        if frame:IsShown() then HideOwn(frame) end
    elseif hiddenByUs[frame] then
        hiddenByUs[frame] = nil
        frame:Show()
    end
end

local function ApplyMinimap()
    if not (block.cfg.hideMinimapClock or block.cfg.hideCalendarButton or next(hooked)) then return end
    KeepHidden(_G.TimeManagerClockButton, "hideMinimapClock")
    KeepHidden(_G.GameTimeFrame, "hideCalendarButton")
end

ns.OnReady(function() C_Timer.After(1, ApplyMinimap) end)

-- Baustein an/aus und Profilwechsel: Uhr und Kalenderknopf der Minikarte folgen sofort.
function block:OnEnable() ApplyMinimap() end
function block:OnDisable() ApplyMinimap() end
function block:OnConfigChanged() ApplyMinimap() end

---------------------------------------------------------------------------
-- Anzeige
---------------------------------------------------------------------------

function block:GetText()
    local cfg = self.cfg
    local text
    if cfg.mode == "local" then
        text = LocalText()
    elseif cfg.mode == "both" then
        text = ServerText() .. ns.Grey(" " .. L.CLOCK_S) .. "  " .. LocalText() .. ns.Grey(" " .. L.CLOCK_L)
    else
        text = ServerText()
    end
    if cfg.date then text = date(L.CLOCK_DATE_FORMAT) .. "  " .. text end
    return text
end

local Reset = ns.ResetIn   -- Sekunden bis zum Tages- oder Wochenreset (Core.lua, eine Fassung mit „Werkzeuge“)

function block:OnTooltip(tooltip)
    local cfg = self.cfg
    local h, m = GetGameTime()
    ns.TipDoubleLine(tooltip, L.CLOCK_SERVER, Format(h, m), "normal", "highlight")
    if (cfg.offset or 0) ~= 0 then
        local ah, am = ServerTime()
        ns.TipDoubleLine(tooltip, L.CLOCK_ADJUSTED:format(cfg.offset > 0 and "+" .. cfg.offset or tostring(cfg.offset)), Format(ah, am), "normal", "highlight")
    end
    local t = date("*t")
    ns.TipDoubleLine(tooltip, L.CLOCK_LOCAL, Format(t.hour, t.min), "normal", "highlight")
    ns.TipDoubleLine(tooltip, L.CLOCK_DATE, date(L.CLOCK_DATE_LONG), "normal", "highlight")

    local daily, weekly = Reset("GetSecondsUntilDailyReset"), Reset("GetSecondsUntilWeeklyReset")
    if daily or weekly then tooltip:AddLine(" ") end
    if daily then ns.TipDoubleLine(tooltip, L.CLOCK_DAILY, ns.Duration(daily, true), "normal", "highlight") end
    if weekly then ns.TipDoubleLine(tooltip, L.CLOCK_WEEKLY, ns.Duration(weekly, true), "normal", "highlight") end

    tooltip:AddLine(" ")
    ns.TipDoubleLine(tooltip, L.SESSION, ns.Duration(time() - ns.SessionStart(), true), "normal", "highlight")
    local played = ns.PlayedNow and ns.PlayedNow(ns.me)
    if played then ns.TipDoubleLine(tooltip, L.PLAYED_TOTAL, ns.Duration(played, true), "normal", "highlight") end

    if C_Calendar and C_Calendar.GetNumPendingInvites then
        local ok, invites = pcall(C_Calendar.GetNumPendingInvites)
        if ok and ns.Num(invites) and invites > 0 then
            tooltip:AddLine(" ")
            ns.TipLine(tooltip, L.CLOCK_INVITES:format(invites), "good")
        end
    end
end

-- ezCore lädt Blizzards Kalender bzw. Zeitmanager selbst nach; im Kampf erscheint sein Hinweis.
local function OpenStopwatch() return ezCore.TogglePanel("clock") end
local function OpenCalendar() return ezCore.TogglePanel("calendar") end

-- Die Klicks auch als Menüeinträge: Der Kalender bleibt erreichbar, wenn sein Minikarten-Knopf ausgeblendet ist.
block.actions = {
    { text = L.CLOCK_OPEN_STOPWATCH, fn = OpenStopwatch },
    { text = L.CLOCK_OPEN_CALENDAR, fn = OpenCalendar },
}

function block:OnClick(button)
    if button ~= "LeftButton" then return end
    if IsShiftKeyDown() then OpenCalendar() else OpenStopwatch() end
end

local OFFSETS = { -12, -9, -6, -5, -4, -3, -2, -1.5, -1, -0.5, 0, 0.5, 1, 1.5, 2, 3, 4, 5, 6, 9, 12 }

function block:OnMenu(root)
    local cfg = self.cfg
    local mode = root:CreateButton(L.MENU_BAR_SHOWS)
    ns.MenuRadio(mode, L.CLOCK_MODE_SERVER, cfg, "mode", "server", self)
    ns.MenuRadio(mode, L.CLOCK_MODE_LOCAL, cfg, "mode", "local", self)
    ns.MenuRadio(mode, L.CLOCK_MODE_BOTH, cfg, "mode", "both", self)
    mode:CreateDivider()
    ns.MenuCheck(mode, L.CLOCK_24H, cfg, "h24", self)
    ns.MenuCheck(mode, L.CLOCK_SECONDS, cfg, "seconds", self)
    ns.MenuCheck(mode, L.CLOCK_SHOW_DATE, cfg, "date", self)

    local offset = root:CreateButton(L.CLOCK_OFFSET)
    for _, value in ipairs(OFFSETS) do
        local text = value == 0 and L.CLOCK_OFFSET_NONE or ((value > 0 and "+" or "") .. value .. " " .. L.HOURS_SHORT)
        ns.MenuRadio(offset, text, cfg, "offset", value, self)
    end

    local minimap = root:CreateButton(L.CLOCK_MINIMAP)
    ns.MenuCheck(minimap, L.CLOCK_HIDE_CLOCK, cfg, "hideMinimapClock", self, ApplyMinimap)
    ns.MenuCheck(minimap, L.CLOCK_HIDE_CALENDAR, cfg, "hideCalendarButton", self, ApplyMinimap)
end
