local _, ns = ...
local L = ns.L

-- Combo-Punkte (Schurke, Druide in Katzengestalt).
-- WoW Forever zeigt sie im klassischen ComboFrame am Zielporträt: fünf Retail-Punkte (RogueComboPointTemplate)
-- auf einem Bogen um das Porträt, aber auf 60 % verkleinert und deshalb schwer zu sehen.
--   1. Größer am Zielporträt: ezCombat hängt sich an Blizzards Anordnung (LayoutPointsCircle) und setzt
--      dieselben Punkte größer auf einen etwas weiteren Bogen. Blizzards Punkte, Blizzards Animationen.
--   2. Combo-Leiste unter dem Spielerfenster: dieselben Punkte in einer Reihe, so wie Retail sie unter dem
--      Spielerfenster zeigt (Abstand 4 wie Blizzards Klassenleiste). Für Druiden nur in Katzengestalt.
-- Verträglich mit ClassicUIForever: Dessen Option „Combopunkte“ blendet Blizzards Punkte aus und zeichnet
-- eigene klassische Kugeln. Dann sieht man (1) nicht; die Leiste (2) bleibt. Erkannt über ezCore
-- (ezCore.OtherAddOn("ClassicUIForever", "comboPoints"), Liste in docs/fremd-addons.md).
local Combo = {}
ns.Combo = Combo

local POINT_SIZE = 20       -- RogueComboPointTemplate
local BAR_SPACING = 4
local MAX_POINTS = 5
-- Nummer der Katzengestalt aus GetShapeshiftFormID(): ezCores Zauber-Wissen (Spells.FORM_IDS, Zauber 768; CB-08),
-- die 1 nur als Rückfall, solange ezCore sie nicht führt.
local CAT_FORM = (ezCore.Spells and ezCore.Spells.FORM_IDS and ezCore.Spells.FORM_IDS[768]) or 1
local BAR_ANCHOR = { "TOP", "PlayerFrame", "BOTTOM", 30, 20 }

local scaled = false
local hooked = false
local bar, barPoints
local barFailed = false
local previewUntil = 0

---------------------------------------------------------------------------
-- 1. Blizzards Punkte am Zielporträt größer
---------------------------------------------------------------------------

function Combo.ClassicUITakesOver()
    return ezCore.Call(ezCore.OtherAddOn, "ClassicUIForever", "comboPoints") == true
end

-- Nach Blizzards Anordnung: gleiche Mitte des Bogens, größere Punkte, Winkel so weit, dass sie sich nicht berühren.
function Combo.Relayout(frame)
    local points, layout = frame.ComboPoints, frame.layout
    if type(points) ~= "table" or type(layout) ~= "table" then return end
    local baseScale = layout.pointScale or 0.6
    -- 100 % = Blizzards Größe, also aus (Einstellungs-Prüfung 19.11.2026, Nr. 73; bis dahin Kästchen combo)
    local factor = (tonumber(ns.S.comboScale) or 100) / 100
    if factor <= 1 then
        if scaled then
            for _, point in ipairs(points) do point:SetScale(baseScale) end
            scaled = false
        end
        return
    end
    local scale = baseScale * factor
    local count = math.min(ns.Num(frame.maxComboPoints) or #points, #points)
    local baseStep = layout.angleStepDegrees or 21
    local size = POINT_SIZE * scale
    local radius = (layout.radius or 66) * baseScale + (size - POINT_SIZE * baseScale) / 2
    local step = math.max(baseStep, math.deg((size + 1) / radius))
    local start = layout.startAngleDegrees or -10
    if type(frame.GetEffectiveStartAngleDegrees) == "function" then
        local ok, angle = pcall(frame.GetEffectiveStartAngleDegrees, frame)
        if ok and type(angle) == "number" then start = angle end
    end
    local center = start + (count - 1) * baseStep / 2
    local first = center - (count - 1) * step / 2
    for index = 1, count do
        local point = points[index]
        local angle = math.rad(first + (index - 1) * step)
        point:SetScale(scale)
        point:ClearAllPoints()
        -- Versatz gilt im Maßstab des Punkts, deshalb durch scale teilen.
        point:SetPoint("CENTER", frame, "CENTER", math.cos(angle) * radius / scale, math.sin(angle) * radius / scale)
    end
    scaled = true
end

function Combo.HookComboFrame()
    local frame = rawget(_G, "ComboFrame")
    if type(frame) ~= "table" or type(frame.LayoutPointsCircle) ~= "function" then return false end
    if not hooked then
        hooksecurefunc(frame, "LayoutPointsCircle", Combo.Relayout)
        hooked = true
    end
    Combo.Relayout(frame)
    return true
end

-- Nach einer Änderung in den Einstellungen: Blizzard ordnet neu, der Haken setzt die Größe.
function Combo.RefreshComboFrame()
    local frame = rawget(_G, "ComboFrame")
    if not (hooked and type(frame) == "table") then return end
    if not pcall(frame.LayoutPointsCircle, frame) then Combo.Relayout(frame) end
end

---------------------------------------------------------------------------
-- 2. Combo-Leiste unter dem Spielerfenster
---------------------------------------------------------------------------

local function IsComboUser()
    if ns.playerClass == "ROGUE" then return true end
    if ns.playerClass ~= "DRUID" then return false end
    local powerType = ns.Num(UnitPowerType("player"))
    local energy = Enum and Enum.PowerType and Enum.PowerType.Energy or 3
    if powerType ~= nil then return powerType == energy end
    return GetShapeshiftFormID ~= nil and ns.Num(GetShapeshiftFormID()) == CAT_FORM
end

-- Kind von Blizzards Spielerfenster: nur außerhalb des Kampfs anlegen.
local function CreateBar()
    if bar or barFailed or not PlayerFrame or ns.InCombat() then return bar end
    local frame = CreateFrame("Frame", "ezCombatComboBar", PlayerFrame)
    frame:SetSize(MAX_POINTS * POINT_SIZE + (MAX_POINTS - 1) * BAR_SPACING, POINT_SIZE)
    frame:SetPoint(BAR_ANCHOR[1], PlayerFrame, BAR_ANCHOR[3], BAR_ANCHOR[4], BAR_ANCHOR[5])
    frame:EnableMouse(false)
    local list = {}
    for index = 1, MAX_POINTS do
        local ok, point = pcall(CreateFrame, "Frame", nil, frame, "RogueComboPointTemplate")
        if not ok or type(point) ~= "table" or type(point.SetActive) ~= "function" then
            -- Vorlage fehlt in diesem Client: lieber nichts zeigen als eine fremde Optik.
            barFailed = true
            frame:Hide()
            return nil
        end
        if point.Setup then point:Setup() end
        point:ClearAllPoints()
        point:SetPoint("LEFT", frame, "LEFT", (index - 1) * (POINT_SIZE + BAR_SPACING), 0)
        list[index] = point
    end
    frame:Hide()
    bar, barPoints = frame, list
    -- Verschiebbar (ezCore.Mover); Standard: unter dem Spielerfenster, wandert mit ihm.
    ns.Movable(frame, "combo", L.MOVER_COMBO, BAR_ANCHOR, true)
    return bar
end

-- Einen Punkt der Leiste setzen. quiet: ohne Animation, wenn die Vorlage das kann – sonst mit (V-109: nie eine
-- Methode aufrufen, die dieser Client der Vorlage nicht mitgibt).
local function SetBarPoint(point, active, quiet)
    if quiet and type(point.SetActiveNoAnimation) == "function" then
        point:SetActiveNoAnimation(active)
    elseif type(point.SetActive) == "function" then
        point:SetActive(active)
    end
end

-- Hat die Leiste hier überhaupt etwas zu zeigen? Entschieden wird, bevor die Punkte gelesen werden: Wer keine
-- Combo-Punkte hat oder die Leiste abgeschaltet hat, liest sie nicht – sonst stünde ein gesperrter Wert als Störung
-- in /ezk status (ns.NoteSecret("combo") in Hints.ComboPoints), obwohl bei ihm nichts ruht.
local function BarActive()
    return ns.Enabled("comboBar") and IsComboUser()
end

local function BarWanted(points)
    if points > 0 or ns.InCombat() then return true end
    return ns.UnitPresent("target") == true and ns.Bool(UnitCanAttack("player", "target"), true)
end

function Combo.UpdateBar(suppressAnimation)
    local previewing = ns.Previewing(previewUntil)
    local points, maxPoints
    if previewing then
        points, maxPoints = MAX_POINTS, MAX_POINTS
    elseif BarActive() then
        points, maxPoints = ns.Hints.ComboPoints()
    end
    -- Punkte gesperrt = unbekannt: keine Leiste mit geratenen Punkten (Hints.ComboPoints vermerkt es, /ezk status
    -- sagt es). Ist nur der Höchstwert gesperrt, gelten Blizzards fünf Plätze.
    if points == nil or not (previewing or BarWanted(points)) then
        if bar then bar:Hide() end
        return
    end
    if not CreateBar() then return end
    maxPoints = math.max(1, math.min(maxPoints or MAX_POINTS, MAX_POINTS))
    for index, point in ipairs(barPoints) do
        if index <= maxPoints then
            point:Show()
            SetBarPoint(point, index <= points, suppressAnimation)
        else
            point:Hide()
        end
    end
    bar:Show()
end

---------------------------------------------------------------------------

local updateSoon = ns.Throttle(function() Combo.UpdateBar(false) end, 0.02)

-- Kraft nur des Spielers (ns.OnUnit, T8-1): Der Filter liegt bei ezCore, eine gesperrte Einheit zählt dort als
-- der Spieler und wird hier nie verglichen (T3-1, Leitlinie 6). Die übrigen Ereignisse haben keine Einheit.
for _, event in ipairs({ "UNIT_POWER_FREQUENT", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }) do
    ns.OnUnit(event, "player", updateSoon)
end
for _, event in ipairs({ "COMBO_TARGET_CHANGED", "UPDATE_SHAPESHIFT_FORM", "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED" }) do
    ns.On(event, updateSoon)
end
ns.On("PLAYER_TARGET_CHANGED", function() Combo.UpdateBar(true) end)

ns.OnSettingChanged(function(key)
    if key == "comboScale" then
        Combo.RefreshComboFrame()
    elseif key == "comboBar" then
        Combo.UpdateBar(true)
    end
end)

local function PrepareBar()
    if ns.Enabled("comboBar") and (ns.playerClass == "ROGUE" or ns.playerClass == "DRUID") then CreateBar() end
end
-- Kampfbeginn: Das Ereignis kommt noch vor der Kampfsperre.
ns.On("PLAYER_REGEN_DISABLED", PrepareBar)

ns.OnReady(function()
    Combo.HookComboFrame()
    PrepareBar()
    Combo.UpdateBar(true)
end)

ns.AddStatusLine(function()
    if (tonumber(ns.S.comboScale) or 100) > 100 and IsComboUser() and Combo.ClassicUITakesOver() then
        return L.STATUS_COMBO_CLASSICUI
    end
end)

-- Vorschau: die Combo-Leiste füllt sich für 3 Sekunden.
ns.AddPreview("combo", 40, function()
    if not (ns.playerClass == "ROGUE" or ns.playerClass == "DRUID") then return false end
    previewUntil = GetTime() + 3
    if bar then
        for _, point in ipairs(barPoints) do SetBarPoint(point, false, true) end
    end
    Combo.UpdateBar(false)
    C_Timer.After(3.1, function() Combo.UpdateBar(true) end)
    return bar ~= nil
end)

-- Auswahl zum Verschieben (Bearbeitungsmodus, „Teile verschieben“): volle Combo-Leiste unter dem Spielerfenster,
-- solange sie offen ist (Schurke, Druide).
ns.Listen("PARTS_SHOWING", function() Combo.UpdateBar(true) end)
