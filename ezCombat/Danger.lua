local _, ns = ...
local L = ns.L
local Core = ezCore

-- Blizzards Spielerfenster leuchtet, wenn du fast stirbst (Frage des Nutzers vom 24.11.2026, wörtlich: „kann der rahmen des
-- spielers leuchten wenn er fast stirbt?“; Schalter dangerGlow). Der Restschaden-Plan mit „Gefahr-Leuchten“ entfiel am
-- 23.11.2026; gewünscht ist seit dem 24.11.2026 nur dieses Leuchten wieder, der übrige Restschaden nicht.
--   • Dieselbe Grenze wie Trank und Rettungsfähigkeit (potionBelow, ab Werk 15 %; Potions.Share). Das Leben liest ezCombat
--     nie: Die Deckkraft des Rahmens „gate“ setzt Blizzards Kurve (Core.HealthBelowAlpha, Ergebnis nur an SetAlpha). Darin
--     pulst ein zweiter Rahmen – die Bewegung hängt nicht am Leben und läuft, solange der Schalter an ist.
--   • Optik aus Blizzards eigenem Rahmen: der Umriss von PlayerFrame.PlayerFrameContainer.FrameFlash (Blizzards
--     Bedrohungs-Blitz, Camelot/PlayerFrame.lua: PlayerFrame_UpdateFlashTextureVisuals) doppelt gezeichnet, dazu ein
--     Schleier über dem Lebensbalken – beides im Rot der Art „interrupt“ („sofort“). Der Schleier und der starke Umriss
--     unterscheiden es von Blizzards Kampf-Puls am Porträt (StatusTexture) und vom Bedrohungs-Blitz.
--   • Auch außerhalb des Kampfes (etwa nach einem Sturz), nie tot oder als Geist (dort liefert die Kurve ebenfalls 1).
--   • Taint-sicher (Leitlinie 5): ein eigener, ungeschützter Kind-Rahmen ohne Maus, angelegt außerhalb des Kampfes; an
--     Blizzards Teilen wird nur gelesen (GetAtlas) und verankert. Blizzards Wechsel des Umrisses (Klassenleiste) folgt
--     hooksecurefunc.
--   • Rücksicht (Leitlinie 9): Blendet ein fremdes Addon PlayerFrame aus, ist auch das Leuchten weg (Kind-Rahmen) – die
--     Statuszeile sagt es. Blizzards roter Bildschirmrand (LowHealthFrame, ab 35 %) bleibt, wie er ist.
local Danger = {}
ns.Danger = Danger

Danger.KIND = "interrupt"            -- Farbe aus ezCore.GLOW_KINDS (Rot, „sofort“)
Danger.ATLAS = "UI-HUD-UnitFrame-Player-PortraitOn-InCombat"   -- Rückfall, wenn FrameFlash keinen nennt
Danger.LEVEL = 30                    -- Ebenen über PlayerFrame: über Balken und Porträt
Danger.PULSE_SECONDS = 0.5
Danger.PULSE_FROM = 0.3              -- schwächste Deckkraft im Puls
Danger.BAR_ALPHA = 0.45              -- Schleier über dem Lebensbalken
Danger.OUTSET = 3                    -- px: so weit ragt der zweite Umriss über den ersten

local gate
local deadSeen = false               -- letzter offen gelesener Stand bzw. PLAYER_DEAD/PLAYER_UNGHOST
local demoUntil = 0

local function Host()
    local frame = rawget(_G, "PlayerFrame")
    return type(frame) == "table" and frame or nil
end

-- Blizzards Umriss am Spielerfenster (Textur) oder nil
local function Flash()
    local frame = Host()
    local container = frame and Core.Peek(frame, "PlayerFrameContainer")
    local flash = type(container) == "table" and Core.Peek(container, "FrameFlash") or nil
    return type(flash) == "table" and flash or nil
end

-- Blizzards Bereich des Lebensbalkens oder nil
local function HealthArea()
    local area = Core.Call(rawget(_G, "PlayerFrame_GetHealthBarContainer"))
    return type(area) == "table" and area or nil
end

-- Umriss nach Blizzards Stand: derselbe Atlas, dieselbe Lage (mit Klassenleiste ist er größer)
function Danger.Place()
    if not gate then return end
    local flash = Flash()
    local atlas = flash and type(flash.GetAtlas) == "function" and Core.PlainCall(flash.GetAtlas, flash) or nil
    if type(atlas) ~= "string" or atlas == "" then atlas = Danger.ATLAS end
    local r, g, b = Core.GlowColor(Danger.KIND)
    for index, ring in ipairs(gate.rings) do
        local out = (index - 1) * Danger.OUTSET
        ring:SetAtlas(atlas)
        ring:SetVertexColor(r, g, b)
        ring:ClearAllPoints()
        ring:SetPoint("TOPLEFT", flash or gate, "TOPLEFT", -out, out)
        ring:SetPoint("BOTTOMRIGHT", flash or gate, "BOTTOMRIGHT", out, -out)
    end
    local area = HealthArea()
    gate.bar:ClearAllPoints()
    if area then gate.bar:SetAllPoints(area) end
    gate.bar:SetShown(area ~= nil)
end

-- Rahmen anlegen (einmal, außerhalb des Kampfes: Kind eines geschützten Fensters) → Rahmen oder nil
function Danger.Build()
    local host = Host()
    if gate or not host or ns.InCombat() then return gate end
    gate = CreateFrame("Frame", "ezCombatDangerGlow", host)
    gate:SetAllPoints(host)
    gate:SetFrameLevel((Core.Num(host:GetFrameLevel()) or 1) + Danger.LEVEL)
    gate:EnableMouse(false)
    gate:SetAlpha(0)
    local pulse = CreateFrame("Frame", nil, gate)
    pulse:SetAllPoints(gate)
    pulse:EnableMouse(false)
    gate.pulse = pulse
    gate.rings = {}
    for index = 1, 2 do
        local ring = pulse:CreateTexture(nil, "OVERLAY", nil, index)
        if index == 2 and ring.SetBlendMode then ring:SetBlendMode("ADD") end
        gate.rings[index] = ring
    end
    local r, g, b = Core.GlowColor(Danger.KIND)
    local bar = pulse:CreateTexture(nil, "ARTWORK")
    bar:SetColorTexture(r, g, b, Danger.BAR_ALPHA)
    gate.bar = bar
    local anim = pulse:CreateAnimationGroup()
    anim:SetLooping("BOUNCE")
    local fade = anim:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(Danger.PULSE_FROM)
    fade:SetDuration(Danger.PULSE_SECONDS)
    gate.anim = anim
    gate:Hide()
    -- auch, wenn nur ein Elternrahmen verschwand und wiederkommt (Alt+Z, Filmsequenz): der Puls läuft neu an (wie Glow)
    gate:SetScript("OnShow", function() anim:Play() end)
    gate:SetScript("OnHide", function() anim:Stop() end)
    Danger.Place()
    if type(rawget(_G, "PlayerFrame_UpdateFlashTextureVisuals")) == "function" then
        hooksecurefunc("PlayerFrame_UpdateFlashTextureVisuals", function() ns.Try("Danger", Danger.Place) end)
    end
    return gate
end

-- Tot oder Geist? Offen gelesen (Blizzards Dokumentation nennt bei UnitIsDeadOrGhost keine gesperrte Rückgabe, Build
-- 1.60.1.71037: tools/daten/blizzard/api.lua), sonst der letzte bekannte Stand.
function Danger.Dead()
    local value = Core.PlainCall(rawget(_G, "UnitIsDeadOrGhost"), "player")
    if type(value) == "boolean" then deadSeen = value end
    return deadSeen
end

-- Deckkraft aus Blizzards Kurve (1 unter der Grenze, sonst 0); ohne Kurve lieber nichts zeigen als raten
function Danger.Apply()
    if not gate then return end
    if GetTime() < demoUntil then
        gate:Show()
        gate:SetAlpha(1)
        return
    end
    gate:SetShown(ns.Enabled("dangerGlow") and not Danger.Dead())
    if not gate:IsShown() then return end
    if not Core.HealthBelowAlpha(gate, "player", ns.Potions.Share(), false) then gate:SetAlpha(0) end
end

function Danger.Update()
    ns.Try("Danger", function()
        if not gate and ns.Enabled("dangerGlow") then
            if ns.InCombat() then
                ns.AfterCombat(Danger.Update, "danger")   -- im Kampf neu geladen oder eingeschaltet
                return
            end
            Danger.Build()
        end
        Danger.Apply()
    end)
end

-- Vorschau („Zeigen“): das Leuchten voll sichtbar. → true, wenn es zu sehen ist
function Danger.Demo(seconds)
    if not ns.Enabled("dangerGlow") then return false end
    Danger.Build()
    if not gate then return false end
    seconds = Core.Num(seconds) or 4
    local untilTime = GetTime() + seconds
    demoUntil = untilTime
    Danger.Apply()
    C_Timer.After(seconds, function()
        if demoUntil ~= untilTime then return end   -- eine neuere Vorschau läuft noch
        demoUntil = 0
        Danger.Update()
    end)
    return true
end

function Danger.Frame() return gate end

---------------------------------------------------------------------------

ns.OnReady(Danger.Update)
for _, event in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH" }) do
    ns.OnUnit(event, "player", function() Danger.Apply() end)
end
ns.On("PLAYER_DEAD", function()
    deadSeen = true
    Danger.Apply()
end)
ns.On("PLAYER_UNGHOST", function()
    deadSeen = false
    Danger.Apply()
end)
-- PLAYER_ALIVE kommt auch beim Freilassen des Geists: nur neu lesen
for _, event in ipairs({ "PLAYER_ALIVE", "PLAYER_ENTERING_WORLD" }) do
    ns.On(event, function() Danger.Apply() end)
end
ns.OnSettingChanged(function(key)
    if key == "dangerGlow" or key == "potionBelow" then Danger.Update() end
end)
-- /ezk status: Das Spielerfenster ist ausgeblendet (fremder Ersatz) – dort kann nichts leuchten
ns.AddStatusLine(function()
    local frame = Host()
    if ns.Enabled("dangerGlow") and frame and Core.PlainCall(frame.IsVisible, frame) == false then
        return L.STATUS_DANGER_HIDDEN
    end
end)
