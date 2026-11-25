local _, ns = ...
local L = ns.L

-- Combo-Punkte (Schurke, Druide in Katzengestalt). Bis zum 23.11.2026 zeigte ezCombat sie zweimal – Blizzards Punkte
-- am Zielporträt (vergrößert auf 150 %) und eine eigene Leiste. Entscheidung des Nutzers vom 23.11.2026 („Ziel aus,
-- ein Regler“):
--   1. Combo-Leiste unter dem Spielerfenster (comboBar, ab Werk an): Blizzards Punkte (RogueComboPointTemplate) in
--      einer Reihe, so wie Retail sie unter dem Spielerfenster zeigt (Abstand 4 wie Blizzards Klassenleiste). Für
--      Druiden nur in Katzengestalt.
--   2. Blizzards Punkte am Zielporträt (comboTarget, ab Werk aus): WoW Forever zeigt sie im klassischen ComboFrame auf
--      einem Bogen um das Porträt, auf 60 % verkleinert. Aus: ezCombat blendet den Rahmen nach Blizzards eigenem
--      Zeigen gleich wieder aus (HookScript an OnShow). An: dieselben Punkte in der Größe des Reglers auf einem etwas
--      weiteren Bogen (Haken hinter Blizzards Anordnung LayoutPointsCircle). Blizzards Punkte, Blizzards Animationen.
--   Ein Regler (comboScale) für beide: Prozent von Blizzards Größe der Punkte (Vorlage 20 px); 60 % ist die Größe, in
--   der Blizzard sie am Zielporträt zeigt.
-- Taint (Leitlinie 5; Blizzards Forever-Quelle Gethe/wow-ui-source, Zweig forever, Blizzard_UnitFrame/Camelot/
-- ComboFrame.lua): ComboFrame ist ein einfacher Rahmen ohne geschützte Vorlage, und kein anderer Blizzard-Code liest
-- ihn. ezCombat schreibt nichts in seine Tabelle oder die seiner Punkte und ruft keinen Blizzard-Code auf, der dort
-- schreibt – weder Update noch SetActive (beide setzen Felder wie isFull, Mainline/RogueComboPoint.lua) noch
-- LayoutPointsCircle: Die Lage rechnet Combo.Relayout selbst aus Blizzards layout-Daten. Es bleiben Show/Hide,
-- SetScale und SetPoint (C-seitig, keine Lua-Werte) und das Lesen von GetEffectiveStartAngleDegrees. docs/blizzard-
-- regeln.md, Abschnitt 8, T11.
-- Verträglich mit ClassicUIForever: Dessen Option „Combopunkte“ blendet Blizzards Punkte aus und zeichnet eigene
-- klassische Kugeln. Dann rührt ezCombat Blizzards Punkte am Ziel nicht an (weder ausblenden noch vergrößern); die
-- Leiste bleibt. Erkannt über ezCore (ezCore.OtherAddOn("ClassicUIForever", "comboPoints"), docs/fremd-addons.md).
local Combo = {}
ns.Combo = Combo

local POINT_SIZE = 20       -- RogueComboPointTemplate
local BAR_SPACING = 4
local MAX_POINTS = 5
local BAR_WIDTH = MAX_POINTS * POINT_SIZE + (MAX_POINTS - 1) * BAR_SPACING
-- Nummer der Katzengestalt aus GetShapeshiftFormID(): ezCores Zauber-Wissen (Spells.FORM_IDS, Zauber 768; CB-08),
-- die 1 nur als Rückfall, solange ezCore sie nicht führt.
local CAT_FORM = (ezCore.Spells and ezCore.Spells.FORM_IDS and ezCore.Spells.FORM_IDS[768]) or 1
local BAR_ANCHOR = { "TOP", "PlayerFrame", "BOTTOM", 30, 20 }

local scaled = false
local hooked = false
local bar, barPoints, barPart
local barFailed = false
local previewUntil = 0

-- Maßstab der Punkte aus dem Regler: 1 = Blizzards Größe der Vorlage (20 px), in den Grenzen von ns.LIMITS.
function Combo.PointScale()
    local limit = ns.LIMITS.comboScale
    local value = tonumber(ns.S and ns.S.comboScale) or ns.DEFAULTS.comboScale
    return math.max(limit[1], math.min(limit[2], value)) / 100
end

local function IsComboUser()
    if ns.playerClass == "ROGUE" then return true end
    if ns.playerClass ~= "DRUID" then return false end
    local powerType = ns.Num(UnitPowerType("player"))
    local energy = Enum and Enum.PowerType and Enum.PowerType.Energy or 3
    if powerType ~= nil then return powerType == energy end
    return GetShapeshiftFormID ~= nil and ns.Num(GetShapeshiftFormID()) == CAT_FORM
end

---------------------------------------------------------------------------
-- 1. Blizzards Punkte am Zielporträt: aus (ab Werk) oder in der Größe des Reglers
---------------------------------------------------------------------------

function Combo.ClassicUITakesOver()
    return ezCore.Call(ezCore.OtherAddOn, "ClassicUIForever", "comboPoints") == true
end

-- Tooltip des Schalters: mit dem Hinweis auf ClassicUIForever, solange es die Punkte am Ziel selbst zeichnet.
function Combo.TargetTip()
    if Combo.ClassicUITakesOver() then return L.OPT_comboTarget_TIP .. "\n\n" .. L.STATUS_COMBO_CLASSICUI end
    return L.OPT_comboTarget_TIP
end

-- Darf ezCombat den Rahmen gerade zeigen oder verstecken? Nur, falls ein Client ihn schützt, nicht im Kampf
-- (Leitlinie 5) – Blizzards Quelle schützt ihn nicht (ComboFrame.xml: ohne geschützte Vorlage).
local function Touchable(frame)
    return not (ns.InCombat() and type(frame.IsProtected) == "function" and frame:IsProtected())
end

-- Punkte auf Blizzards Bogen im Maßstab scale: gleiche Mitte des Bogens wie Blizzards Anordnung, der Winkel so weit,
-- dass sich größere Punkte nicht berühren. Bei Blizzards Maßstab (layout.pointScale) genau Blizzards Lage
-- (ComboFrameMixin:LayoutPointsCircle: Radius und Versatz im Maßstab des Punkts).
local function PlacePoints(frame, scale)
    local points, layout = frame.ComboPoints, frame.layout
    local baseScale = layout.pointScale or 0.6
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
end

-- Nach Blizzards Anordnung (Haken an LayoutPointsCircle) und nach einer Einstellung: in der Größe des Reglers, solange
-- der Schalter an ist und ClassicUIForever die Punkte nicht übernimmt; sonst Blizzards Größe und Lage (zurückgesetzt nur,
-- wenn ezCombat vorher vergrößert hat – nach Blizzards Anordnung ist dann nichts zu tun).
function Combo.Relayout(frame)
    local points, layout = frame.ComboPoints, frame.layout
    if type(points) ~= "table" or type(layout) ~= "table" then return end
    -- ClassicUIForever übernimmt: gar nicht anfassen, auch nicht zurücksetzen (das tut Blizzards nächste Anordnung)
    if Combo.ClassicUITakesOver() then return end
    local baseScale = layout.pointScale or 0.6
    local scale = Combo.PointScale()
    if not ns.Enabled("comboTarget") or scale <= baseScale + 0.001 then
        if scaled then
            PlacePoints(frame, baseScale)
            scaled = false
        end
        return
    end
    PlacePoints(frame, scale)
    scaled = true
end

-- Schalter aus: Blizzards Punkte am Zielporträt ausblenden. Blizzard zeigt den Rahmen in ComboFrameMixin:Update neu,
-- sobald Punkte liegen und er nicht sichtbar ist (Show, beim Einblenden über UIFrameFadeIn noch einmal); der Haken an
-- OnShow blendet ihn gleich wieder aus, bevor er gezeichnet wird. Blizzards Punkte führen ihren Stand trotzdem weiter.
-- → true, wenn ausgeblendet.
function Combo.HideTarget(frame)
    frame = frame or rawget(_G, "ComboFrame")
    if type(frame) ~= "table" or type(frame.IsShown) ~= "function" then return false end
    if ns.Enabled("comboTarget") or Combo.ClassicUITakesOver() or not frame:IsShown() then return false end
    if not Touchable(frame) then
        ns.AfterCombat(function() Combo.HideTarget() end, "comboTarget")
        return false
    end
    frame:Hide()
    return true
end

-- Schalter an: Blizzard zeigt den Rahmen erst beim nächsten Combo-Punkt oder Zielwechsel neu. Liegen gerade Punkte,
-- zeigt ezCombat ihn sofort (so wie Blizzard ihn zeigen würde). Nur mit Combo-Punkten (wer keine hat, liest sie nicht –
-- Combo.UpdateBar, BarActive); gesperrt = unbekannt, dann zeigt ihn Blizzard beim nächsten Mal. → true, wenn gezeigt.
function Combo.ShowTarget(frame)
    frame = frame or rawget(_G, "ComboFrame")
    if type(frame) ~= "table" or type(frame.IsShown) ~= "function" then return false end
    if not ns.Enabled("comboTarget") or Combo.ClassicUITakesOver() or frame:IsShown() or not IsComboUser() then
        return false
    end
    local points = ns.Hints.ComboPoints()
    if not points or points <= 0 or not Touchable(frame) then return false end
    frame:Show()
    return true
end

-- Ausblenden (OnShow) und Größe (LayoutPointsCircle) unabhängig voneinander: Fehlte einem Client die Anordnung, wirkt
-- der Schalter trotzdem. Weder ComboFrame.xml noch RogueComboPointTemplate haben OnShow- oder OnHide-Skripte – Show und
-- Hide aus ezCombat lösen keinen Blizzard-Code aus.
function Combo.HookComboFrame()
    local frame = rawget(_G, "ComboFrame")
    if type(frame) ~= "table" or type(frame.HookScript) ~= "function" then return false end
    if not hooked then
        frame:HookScript("OnShow", Combo.HideTarget)
        if type(frame.LayoutPointsCircle) == "function" then
            hooksecurefunc(frame, "LayoutPointsCircle", Combo.Relayout)
        end
        hooked = true
    end
    Combo.Relayout(frame)
    Combo.HideTarget(frame)
    return true
end

-- Nach einer Änderung in den Einstellungen (Schalter, Regler) oder bei ClassicUIForever: Größe und Lage selbst setzen
-- (ohne Blizzards Code aufzurufen), dann aus- bzw. einblenden.
function Combo.RefreshComboFrame()
    local frame = rawget(_G, "ComboFrame")
    if not (hooked and type(frame) == "table") then return end
    Combo.Relayout(frame)
    if not Combo.HideTarget(frame) then Combo.ShowTarget(frame) end
end

---------------------------------------------------------------------------
-- 2. Combo-Leiste unter dem Spielerfenster
---------------------------------------------------------------------------

-- Größe der Leiste aus dem Regler: Die Punkte bekommen den Maßstab, ihre Lage (gesetzt im Maßstab des Punkts) wächst
-- mit, die Abstände also auch. Die Leiste selbst bleibt ungeskaliert, damit ihr Anker und eine gespeicherte Lage
-- gelten; sie wächst um ihre Mitte (Standardanker TOP, eine gespeicherte Ecke rückt über ns.KeepCenter nach).
function Combo.SizeBar(keepCenter)
    if not bar then return false end
    local scale = Combo.PointScale()
    local width, height = BAR_WIDTH * scale, POINT_SIZE * scale
    local oldWidth, oldHeight = ns.Num(bar:GetWidth()), ns.Num(bar:GetHeight())
    bar:SetSize(width, height)
    for _, point in ipairs(barPoints) do point:SetScale(scale) end
    if keepCenter and oldWidth and oldHeight then ns.KeepCenter(barPart, width - oldWidth, height - oldHeight) end
    return true
end

-- Kind von Blizzards Spielerfenster: nur außerhalb des Kampfs anlegen.
local function CreateBar()
    if bar or barFailed or not PlayerFrame or ns.InCombat() then return bar end
    local frame = CreateFrame("Frame", "ezCombatComboBar", PlayerFrame)
    frame:SetSize(BAR_WIDTH, POINT_SIZE)
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
    Combo.SizeBar(false)
    -- Verschiebbar (ezCore.Mover); Standard: unter dem Spielerfenster, wandert mit ihm.
    barPart = ns.Movable(frame, "combo", L.MOVER_COMBO, BAR_ANCHOR, true)
    Combo.TakeShift()
    return bar
end

-- Einmalige Nachführung nach der Umstellung vom 23.11.2026 (ns.MigrateCombo2311, Merker db.comboBarShift): Bis dahin
-- war die Leiste immer 100 % groß; gilt jetzt eine andere Größe, rückt die gespeicherte Ecke einer verschobenen Leiste um
-- die halbe Änderung, damit ihre Mitte stehen bleibt (wie Symbol.TakeShift). Wartet, bis die Leiste angemeldet ist
-- (erster Schurke oder Druide); ohne gespeicherte Lage ist nichts zu tun, der Merker geht trotzdem. → true, wenn gerückt.
function Combo.TakeShift()
    local db = ns.db
    if not (type(db) == "table" and db.comboBarShift and barPart) then return false end
    db.comboBarShift = nil
    local grow = Combo.PointScale() - 1
    return ns.KeepCenter(barPart, BAR_WIDTH * grow, POINT_SIZE * grow)
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
        Combo.SizeBar(true)
        Combo.RefreshComboFrame()
    elseif key == "comboTarget" then
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

-- /ezk status: ClassicUIForever zeichnet die Punkte am Ziel selbst – dort wirken Schalter und Größe von ezCombat nicht.
ns.AddStatusLine(function()
    if IsComboUser() and Combo.ClassicUITakesOver() then return L.STATUS_COMBO_CLASSICUI end
end)

-- Vorschau: die Combo-Leiste füllt sich für 3 Sekunden (Blizzards Punkte am Ziel nicht: deren Stand setzt nur
-- Blizzards Update – SetActive schriebe Felder in Blizzards Punkte, siehe Kopf).
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
