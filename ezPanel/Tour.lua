local _, ns = ...
local L = ns.L

--[[
    Rundgang mit Erklärblasen (Abschlussrunde „Tooltip-Guide“, ezCore.NewTour): beim ersten Erscheinen der
    Leiste die wichtigsten Funktionen – Bausteine, Leistenmenü, Gold, Charaktere, Meldungen, Werkzeuge.
    „OK“ oder das X führt zur nächsten Blase; Schritte zu ausgeschalteten Bausteinen werden übersprungen
    und erscheinen, sobald der Baustein auf der Leiste steht. Gesehen wird in ezPanelDB.tour gemerkt.
    Im Kampf wartet der Rundgang bis danach. Erneut zeigen: Einstellungen → ezPanel → Erweitert →
    „Erklärung“ (page:TourButton); danach beginnt er, sobald das Einstellungsfenster zu ist.
]]

-- Der Baustein ganz links auf der Leiste (der erste, den man sieht).
local function FirstBlock()
    local best, left
    for _, def in ipairs(ns.blockList or {}) do
        local frame = def.frame
        if frame and frame:IsVisible() and frame:GetParent() == ns.bar then
            local x = frame:GetLeft()
            if x and (not left or x < left) then best, left = frame, x end
        end
    end
    return best
end

local function Block(id)
    return function()
        local def = ns.blocks and ns.blocks[id]
        return def and def.cfg and def.cfg.enabled and def.frame or nil
    end
end

local tour = ezCore.NewTour({
    owner = ns,   -- gesehen wird in ezPanelDB.tour gemerkt (ezCores Gerüst)
    steps = {
        { key = "block", target = FirstBlock, text = L.TOUR_BLOCK, side = "below" },
        { key = "bar", target = function() return ns.bar end, text = L.TOUR_BAR, side = "below" },
        { key = "gold", target = Block("gold"), text = L.TOUR_GOLD, side = "below" },
        { key = "alts", target = Block("alts"), text = L.TOUR_ALTS, side = "below" },
        { key = "alerts", target = Block("alerts"), text = L.TOUR_ALERTS, side = "below" },
        { key = "tools", target = Block("tools"), text = L.TOUR_TOOLS, side = "below" },
    },
})
ns.tour = tour

local waitCombat, pending, hookedSettings = false, false, false

-- Erste noch nicht gesehene Blase zeigen (nur mit sichtbarer Leiste, nicht im Kampf). → Schlüssel oder nil
function ns.StartTour()
    local bar = ns.bar
    if not ns.ready or not bar or not bar:IsVisible() then return nil end
    if ns.InCombat() then
        waitCombat = true
        ns.AfterCombat(function()
            if waitCombat then C_Timer.After(1, ns.StartTour) end
        end, "tour")
        return nil
    end
    waitCombat, pending = false, false
    return tour:Start(bar)
end

-- Steht die Maus auf einer Blase? Dann bleibt die automatisch ausgeblendete Leiste offen (Bar.lua).
function ns.TourMouseOver()
    for _, step in ipairs(tour.steps) do
        local box = tour.hints.Box(step.key)
        if box and box:IsVisible() and box:IsMouseOver() then return true end
    end
    return false
end

-- „Erneut zeigen“: von vorn, sobald das Einstellungsfenster zu ist (sonst gleich).
local reset = tour.Reset
function tour:Reset()
    reset(self)
    pending = true
    local panel = _G.SettingsPanel
    if panel and panel.IsShown and panel:IsShown() then
        if not hookedSettings and panel.HookScript then
            hookedSettings = true
            panel:HookScript("OnHide", function()
                if pending then C_Timer.After(0.2, ns.StartTour) end
            end)
        end
    else
        ns.StartTour()
    end
end

ns.OnReady(function()
    C_Timer.After(2, ns.StartTour)
    if ns.bar then
        ns.bar:HookScript("OnShow", function() C_Timer.After(0.3, ns.StartTour) end)
    end
end)
