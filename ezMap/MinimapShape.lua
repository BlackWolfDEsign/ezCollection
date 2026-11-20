local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Eckige Minikarte (Schalter, Standard aus) – der einzige Weg, der wie weiter Herauszoomen wirkt.

    Geprüft in Blizzards Forever-Quelle: Die Fläche einer Zoomstufe legt der Client fest (C_Minimap.GetViewRadius());
    Blizzards eigene HybridMinimap (HybridMinimapMixin:UpdateZoom) rechnet den Sichtdurchmesser immer auf die volle
    Breite der Minikarte um – eine größere Minikarte (SetSize oder SetScale) zeigt also dieselbe Fläche größer.
    Die Minikarte selbst ist aber quadratisch; Blizzards runde Maske („ui-hud-minimap-frame-generic-mask“,
    Camelot/Minimap.lua) schneidet die Ecken ab. Mit einer eckigen Maske kommen die Ecken dazu: rund 27 % mehr
    Fläche bei derselben Stufe (Quadrat 4r² statt Kreis πr²), so wie bei ElvUI oder SexyMap.

    Was ezMap dafür tut (Leitlinie 4 ist gestrichen, Leitlinie 5 gilt): nur außerhalb des Kampfes Maske tauschen,
    Blizzards runden Rahmen ausblenden und einen schlichten Rahmen aus Blizzards Tooltip-Rand darumlegen; Lage und
    Größe der Minikarte bleiben, wie Blizzards Bearbeitungsmodus sie setzt. Ausschalten stellt Blizzards Maske und
    Rahmen wieder her. GetMinimapShape() meldet „SQUARE“, damit Minikarten-Knöpfe anderer Addons (LibDBIcon,
    HandyNotes, GatherMate2) richtig sitzen. Gestaltet ein anderes Addon die Minikarte selbst (SexyMap), hält sich
    ezMap heraus (erkannt über ezCore: Core.WhoHandles("minimapShape")).
]]
local Shape = {}
ns.MinimapShape = Shape

Shape.SQUARE_MASK = "Interface\\Buttons\\WHITE8X8"
Shape.BLIZZARD_MASK = "ui-hud-minimap-frame-generic-mask"     -- beide Lagen (fest und drehend) in Camelot/Minimap.lua

local active, border, hooked = false, nil, false

local function Map() return rawget(_G, "Minimap") end

-- Wer die Minikarte schon selbst gestaltet, sonst nil: ezCores Funktionsschlüssel „minimapShape“ wie bei
-- „minimapAutoZoom“ (MinimapZoom.lua). ezCore führt ihn (SexyMap, V-137); der frühere Rückfall, der zusätzlich
-- direkt nach SexyMap fragte, ist damit entfallen – ezMap führt keine eigene Erkennung, neue Addons kommen in
-- ezCores Liste (ezCore/Wissen/OtherAddOns.lua).
function Shape.Elsewhere()
    return ns.OtherFor("minimapShape")
end

function Shape.Wanted()
    return ns.Enabled("minimapSquare") and not Shape.Elsewhere()
end

function Shape.Active() return active end

local function ShowBlizzardFrame(show)
    local compass = rawget(_G, "MinimapCompassTexture")
    if compass and compass.SetShown then compass:SetShown(show) end
    local underlay = rawget(_G, "MinimapCompassTextureUnderlay")
    if underlay and underlay.Hide and not show then underlay:Hide() end
    if show and underlay and underlay.SetShown then
        underlay:SetShown(GetCVarBool ~= nil and GetCVarBool("rotateMinimap") == true)
    end
end

local function Border(map)
    if border then return border end
    border = CreateFrame("Frame", "ezMapMinimapSquareBorder", map, "BackdropTemplate")
    border:SetPoint("TOPLEFT", map, "TOPLEFT", -4, 4)
    border:SetPoint("BOTTOMRIGHT", map, "BOTTOMRIGHT", 4, -4)
    if border.SetBackdrop then
        border:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14 })
        if border.SetBackdropBorderColor then border:SetBackdropBorderColor(0.6, 0.6, 0.6, 1) end
    end
    if map.GetFrameLevel then border:SetFrameLevel(map:GetFrameLevel() + 1) end
    border:EnableMouse(false)
    border:Hide()
    return border
end

local function SquareShape() return active and "SQUARE" or "ROUND" end

-- Eckig oder rund, wie gewünscht – sofort; nur außerhalb des Kampfes rufen (Shape.Apply sorgt dafür).
function Shape.ApplyNow()
    local map = Map()
    if not (map and map.SetMaskTexture) then return false end
    if Shape.Wanted() then
        map:SetMaskTexture(Shape.SQUARE_MASK)
        ShowBlizzardFrame(false)
        Border(map):Show()
        active = true
        if rawget(_G, "GetMinimapShape") == nil then GetMinimapShape = SquareShape end
    elseif active then
        active = false
        map:SetMaskTexture(Shape.BLIZZARD_MASK)
        ShowBlizzardFrame(true)
        if border then border:Hide() end
    end
    return true
end

-- Eckig oder rund, wie gewünscht; im Kampf erst danach (ezCores Reihe „nach dem Kampf“, nur der letzte Wunsch
-- zählt). Rückgabe: true, wenn sofort umgestellt wurde.
function Shape.Apply()
    local map = Map()
    if not (map and map.SetMaskTexture) then return false end
    return ns.AfterCombat(Shape.ApplyNow, "minimapShape") == true
end

-- Blizzard setzt Maske und Rahmen neu, wenn sich „Minikarte drehen“ ändert (MinimapClusterMixin:UpdateMinimapConfig):
-- danach wieder eckig.
local function Hook()
    local cluster = rawget(_G, "MinimapCluster")
    if hooked or not (cluster and type(cluster.UpdateMinimapConfig) == "function") then return end
    hooksecurefunc(cluster, "UpdateMinimapConfig", function()
        if active then
            active = false
            Shape.Apply()
        end
    end)
    hooked = true
end

ns.OnReady(function()
    Hook()
    Shape.Apply()
end)
ns.OnSettingChanged(function(key)
    if key == "minimapSquare" then Shape.Apply() end
end)
-- Ein fremdes Addon sagt erst später, ob es die Minikarte gestaltet (Forever++ antwortet erst nach READY): dann neu
-- entscheiden – eckig werden oder Blizzards Maske und Rahmen zurückgeben (Welle 23, A6).
Core.Listen("OTHER_ADDONS_CHANGED", function() ns.Try("MinimapShape", Shape.Apply) end, "ezMap.MinimapShape")

ns.AddStatusLine(function()
    local other = Shape.Elsewhere()
    if other and ns.Enabled("minimapSquare") then return L.STATUS_SQUARE_OTHER:format(other) end
    if active then return L.STATUS_SQUARE_ON end
    return nil
end)
