local _, ns = ...
local Core = ezCore

--[[
    Pfeil auf der Minikarte zum nächsten Schritt einer Route anderer Module (Spieltest des Nutzers vom 19.11.2026,
    wörtlich „ezmap sollte auf der mini map einen kleinen pfeil für die leveling route anzeigen, aber so dass es gut
    sichtbar ist aber nicht stört“; Auftrag freigegeben am 20.11.2026). Schnittstelle für ezQuests Leveling-Route:
      ezCore.API("ezMap").ShowMiniArrow(besitzer, { map, x, y }, { family })  → true | false
      ezCore.API("ezMap").ClearMiniArrow(besitzer)                              → true
    Je Besitzer ein Ziel; gezeigt wird eines (das erste nach Namen). Den Schalter führt das Modul, dem die Route gehört
    (ezQuest: „Pfeil zur Leveling-Route auf der Minikarte“, routeMiniArrow).

    Aussehen: Blizzards Pfeil der Minikarte (Interface\Minimap\MinimapArrow), klein (MiniArrow.SIZE) und in der
    Anfangsfarbe der Route (Familie aus ns.RouteDraw, Gold für die Leveling-Route). Er steht am Rand der Minikarte in
    Richtung des Ziels; liegt das Ziel im Sichtbereich (C_Minimap.GetViewRadius), rückt er nach innen an seine Stelle,
    nie näher als MiniArrow.INNER an die Mitte (dort steht dein eigener Pfeil). In der Nähe (MiniArrow.NEAR Yards)
    verschwindet er. Nimmt keine Maus an – Klicks und Tooltips der Minikarte bleiben, wie sie sind.
    Richtung: Lage des Ziels auf deiner Karte (Core.Map.PosOn, auch neben der Karte) und Größe der Karte in Yards
    (Core.Discovery.MapYards). Dreht sich die Minikarte mit (CVar rotateMinimap), zählt deine Blickrichtung
    (GetPlayerFacing); ist sie unbekannt oder gesperrt, bleibt der Pfeil weg statt falsch zu zeigen.
    Taint: ein eigener Rahmen als Kind von Blizzards Minimap (kein Fenster unter UIParent), nur lesende Abfragen,
    nichts in Blizzards Tabellen; geschützte Aktionen gibt es hier nicht.
]]
local Arrow = {}
ns.MiniArrow = Arrow

Arrow.TEXTURE = "Interface\\Minimap\\MinimapArrow"
Arrow.SIZE = 16             -- Bildpunkte: klein, aber gut zu sehen
Arrow.ALPHA = 0.9
Arrow.INSET = 9             -- Bildpunkte vom Rand der Minikarte nach innen
Arrow.INNER = 0.35          -- Anteil des Halbmessers: näher an die Mitte rückt der Pfeil nicht
Arrow.NEAR = 25             -- Yards: so nah am Ziel verschwindet er
Arrow.EVERY = 0.1           -- Sekunden zwischen zwei Lagen
Arrow.FAMILY = "gold"       -- Farbfamilie ohne eigene Angabe (wie Route.PATH_FAMILY)

local sqrt, atan2, sin, cos, max, min = math.sqrt, math.atan2, math.sin, math.cos, math.max, math.min
local targets = {}          -- [Besitzer] = { map, x, y, family }
local frame, tex

-- Das gezeigte Ziel (das erste nach Namen) → Eintrag, Besitzer oder nil
function Arrow.Current()
    local keys = {}
    for owner in pairs(targets) do keys[#keys + 1] = owner end
    if #keys == 0 then return nil end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return targets[keys[1]], keys[1]
end

-- Richtung zum Ziel: Winkel im Uhrzeigersinn von Norden (Bogenmaß) und Entfernung in Yards, oder nil (Ort, Karte oder
-- Kartengröße unbekannt)
function Arrow.Bearing(target)
    if type(target) ~= "table" then return nil end
    local map, px, py = Core.PlayerPosition()
    if not map then return nil end
    local tx, ty = Core.Map.PosOn(map, target.map, target.x, target.y, true)
    if not (tx and ty) then return nil end
    local D = Core.Discovery
    local w, h
    if D and type(D.MapYards) == "function" then w, h = D.MapYards(map) end
    if not (w and h) then return nil end
    local east, south = (tx - px) * w, (ty - py) * h
    return atan2(east, -south), sqrt(east * east + south * south), east, south
end

-- Dreht sich die Minikarte mit dir? → true, Blickrichtung (Bogenmaß gegen den Uhrzeigersinn von Norden) | false |
-- nil (dreht sich, Richtung aber unbekannt). Dieselbe Abfrage wie ezCores Punkteschicht (MapPins.Rotating/Facing:
-- pcall, geheime Werte zuerst geprüft)
function Arrow.Rotation()
    local P = Core.MapPins
    if not (P and type(P.Rotating) == "function" and P.Rotating()) then return false end
    local f = type(P.Facing) == "function" and P.Facing() or nil
    if type(f) ~= "number" then return nil end
    return true, f
end

-- Lage auf der Minikarte → winkel (auf dem Bildschirm, im Uhrzeigersinn von oben), dx, dy (Bildpunkte von der Mitte)
-- oder nil, Grund ("where", "near", "facing"). Sichtradius und Drehung rechnet ezCores Punkteschicht
-- (MapPins.MinimapRadius, MapPins.MinimapOffset) – dieselbe Geometrie wie die Punkte auf der Minikarte.
function Arrow.Layout(target, radius)
    local _, yards, east, south = Arrow.Bearing(target)
    if not yards then return nil, "where" end
    if yards < Arrow.NEAR then return nil, "near" end
    local rotating, facing = Arrow.Rotation()
    if rotating == nil then return nil, "facing" end
    local P = Core.MapPins
    local view = P and type(P.MinimapRadius) == "function" and ns.Num((P.MinimapRadius())) or nil
    if not (view and view > 0) then view = yards end
    local e, n
    if P and type(P.MinimapOffset) == "function" then e, n = P.MinimapOffset(east, south, view, rotating and facing or nil) end
    if not e then return nil, "where" end
    local frac = max(Arrow.INNER, min(1, sqrt(e * e + n * n)))
    local angle = atan2(e, n)
    local r = (radius or 0) * frac
    return angle, r * sin(angle), r * cos(angle)
end

local shown                 -- das gezeigte Ziel (Arrow.Refresh)
local last = {}             -- Lage der letzten Zeichnung: nichts tun, solange du stehst und dich nicht drehst

local function Place(force)
    if not (frame and tex) then return end
    local target = shown
    local mm = rawget(_G, "Minimap")
    local width = mm and mm.GetWidth and ns.Num(mm:GetWidth()) or nil
    local map, px, py = Core.PlayerPosition()
    local _, facing = Arrow.Rotation()
    local P = Core.MapPins
    local view = P and type(P.MinimapRadius) == "function" and (P.MinimapRadius()) or nil     -- Zoom der Minikarte
    if not force and last.target == target and last.map == map and last.x == px and last.y == py
        and last.facing == facing and last.width == width and last.view == view then return end
    last.target, last.map, last.x, last.y, last.facing, last.width, last.view = target, map, px, py, facing, width, view
    local angle, dx, dy = nil, nil, nil
    if target and width and width > 0 then
        angle, dx, dy = Arrow.Layout(target, width / 2 - Arrow.INSET)
    end
    if not angle then
        tex:Hide()
        return
    end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", mm, "CENTER", dx, dy)
    if tex.SetRotation then tex:SetRotation(-angle) end
    tex:Show()
end

local function Build()
    if frame then return frame end
    local mm = rawget(_G, "Minimap")
    if type(mm) ~= "table" then return nil end
    frame = CreateFrame("Frame", "ezMapMiniArrow", mm)
    frame:SetSize(Arrow.SIZE, Arrow.SIZE)
    if frame.SetFrameLevel and mm.GetFrameLevel then frame:SetFrameLevel((ns.Num(mm:GetFrameLevel()) or 0) + 8) end
    if frame.EnableMouse then frame:EnableMouse(false) end
    tex = frame:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints(frame)
    tex:SetTexture(Arrow.TEXTURE)
    local wait = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        wait = wait + (tonumber(elapsed) or 0)
        if wait < Arrow.EVERY then return end
        wait = 0
        ns.Try("MiniArrow", Place)
    end)
    frame:Hide()
    return frame
end

-- Rahmen zeigen bzw. verstecken (versteckt läuft kein Takt), Farbe nach dem gezeigten Ziel
function Arrow.Refresh()
    local target = Arrow.Current()
    shown = target
    if not target then
        if frame then frame:Hide() end
        return false
    end
    if not Build() then return false end
    local fam = ns.RouteDraw.Family(target.family)
    local c = fam and fam.from or { 1, 0.82, 0 }
    tex:SetVertexColor(c[1], c[2], c[3], Arrow.ALPHA)
    frame:Show()
    Place(true)
    return true
end

function Arrow.Show(owner, point, opts)
    if owner == nil then return false end
    local m = type(point) == "table" and ns.Num(point.map) or nil
    local x, y = type(point) == "table" and ns.Num(point.x) or nil, type(point) == "table" and ns.Num(point.y) or nil
    if not (m and x and y) then
        Arrow.Clear(owner)
        return false
    end
    opts = type(opts) == "table" and opts or {}
    local family = type(opts.family) == "string" and ns.RouteDraw.FAMILY[opts.family] and opts.family or Arrow.FAMILY
    targets[owner] = { map = m, x = x, y = y, family = family }
    Arrow.Refresh()
    return true
end

function Arrow.Clear(owner)
    if owner ~= nil then targets[owner] = nil end
    Arrow.Refresh()
    return true
end

-- Für Prüfungen: Rahmen und Bild
function Arrow.Frame() return frame, tex end
