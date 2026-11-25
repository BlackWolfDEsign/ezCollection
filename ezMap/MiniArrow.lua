local _, ns = ...
local Core = ezCore

--[[
    Pfeil auf der Minikarte zum nächsten Schritt einer Route anderer Module (Spieltest des Nutzers vom 19.11.2026,
    wörtlich „ezmap sollte auf der mini map einen kleinen pfeil für die leveling route anzeigen, aber so dass es gut
    sichtbar ist aber nicht stört“; Auftrag freigegeben am 20.11.2026). Schnittstelle für ezQuests Leveling-Route:
      ezCore.API("ezMap").ShowMiniArrow(besitzer, { map, x, y }, opts)          → true | false
          opts = { family, size, near = "fade", text, pulse }
      ezCore.API("ezMap").MiniArrowText(besitzer, text | nil)                   → true | false (nur der Text)
      ezCore.API("ezMap").ClearMiniArrow(besitzer)                              → true
    Je Besitzer ein Ziel; gezeigt wird eines (das erste nach Namen). Den Schalter führt das Modul, dem die Route gehört
    (ezQuest: „Pfeil zur Leveling-Route auf der Minikarte“, routeMiniArrow).

    Aussehen: Blizzards Pfeil der Minikarte (Interface\Minimap\MinimapArrow), MiniArrow.SIZE Bildpunkte oder die Größe
    des Besitzers (opts.size, MiniArrow.SIZE_MIN bis SIZE_MAX; ezQuest: Regler „Größe des Pfeils“) und in der
    Anfangsfarbe der Route (Familie aus ns.RouteDraw, Gold für die Leveling-Route). Er steht am Rand der Minikarte in
    Richtung des Ziels, seine Spitze bei jeder Größe gleich weit vom Rand (MiniArrow.GAP); liegt das Ziel im
    Sichtbereich (C_Minimap.GetViewRadius), rückt er nach innen, bis seine Spitze auf dem Ziel steht, nie näher als
    MiniArrow.INNER an die Mitte (dort steht dein eigener Pfeil). In der Nähe (MiniArrow.NEAR Yards) verschwindet er – mit
    near = "fade" verblasst er dort nur und verschwindet erst auf der Stelle (MiniArrow.HERE Yards, dort hätte er keine
    Richtung mehr). Nimmt keine Maus an – Klicks und Tooltips der Minikarte bleiben, wie sie sind.
    Sprung sichtbar (Wunsch des Nutzers vom 24.11.2026, „Ja, so bauen“): pulse = true lässt ihn MiniArrow.PULSE Sekunden
    lang zweimal größer und heller werden. text: eine kleine Zeile (bis drei) in der Minikarte, auf der Hälfte, auf der
    der Pfeil nicht steht; wann und was, entscheidet das Modul der Route.
    Richtung: Lage des Ziels auf deiner Karte (Core.Map.PosOn, auch neben der Karte) und Größe der Karte in Yards
    (Core.Discovery.MapYards). Dreht sich die Minikarte mit (CVar rotateMinimap), zählt deine Blickrichtung
    (GetPlayerFacing); ist sie unbekannt oder gesperrt, bleibt der Pfeil weg statt falsch zu zeigen.
    Taint: ein eigener Rahmen als Kind von Blizzards Minimap (kein Fenster unter UIParent), nur lesende Abfragen,
    nichts in Blizzards Tabellen; geschützte Aktionen gibt es hier nicht.
]]
local Arrow = {}
ns.MiniArrow = Arrow

Arrow.TEXTURE = "Interface\\Minimap\\MinimapArrow"
-- Bildpunkte: Spieltest 20.11.2026 („der minimap pfeil der routen ist doch sehr klein“) – vorher 16; die Grafik hat
-- einen breiten leeren Rand, der Pfeil selbst ist nur etwa halb so groß. Spieltest 24.11.2026 („knapp doppelt so
-- groß“): 44 statt 24, der Regler reicht bis 64; danach „der pfeil ist zu groß bitte auf 32 default setzen“
Arrow.SIZE = 32
Arrow.SIZE_MIN, Arrow.SIZE_MAX = 12, 64
Arrow.ALPHA = 0.9
-- Spitze des Pfeils über der Mitte des Bilds, als Anteil der Größe: in Interface\Minimap\MinimapArrow (FileDataID 136431,
-- Client-Build 1.60.1.71037, 32 × 32 Bildpunkte) liegt die oberste sichtbare Zeile 10 Bildpunkte über der Mitte
Arrow.TIP = 10 / 32
Arrow.GAP = 3               -- Bildpunkte zwischen Spitze und Rand der Minikarte, bei jeder Größe gleich
Arrow.INNER = 0.35          -- Anteil des Halbmessers: näher an die Mitte rückt der Pfeil nicht
Arrow.NEAR = 25             -- Yards: so nah am Ziel verschwindet er (near = "fade": verblasst er)
Arrow.HERE = 8              -- Yards: so nah verschwindet er auch mit near = "fade"
Arrow.FADE = 0.4            -- Deckkraft des verblassten Pfeils
Arrow.PULSE = 1.2           -- Sekunden: Aufleuchten nach einem Sprung
Arrow.PULSE_COUNT = 2       -- so oft in dieser Zeit
Arrow.PULSE_SCALE = 0.6     -- so viel größer im Höhepunkt (Anteil)
Arrow.TEXT_WIDTH = 0.62     -- Breite der Zeile, Anteil der Minikarte (so breit ist der Ring dort noch)
Arrow.TEXT_INSET = 0.15     -- Abstand der Zeile vom oberen bzw. unteren Rand, Anteil der Minikarte
Arrow.TEXT_LINES = 3
Arrow.EVERY = 0.1           -- Sekunden zwischen zwei Lagen
Arrow.FAMILY = "gold"       -- Farbfamilie ohne eigene Angabe (wie Route.PATH_FAMILY)

local sqrt, atan2, sin, cos, max, min = math.sqrt, math.atan2, math.sin, math.cos, math.max, math.min
local targets = {}          -- [Besitzer] = { map, x, y, family, size, near, text }
local frame, tex
local textFrame, label      -- die Zeile in der Minikarte
local shown                 -- das gezeigte Ziel (Arrow.Refresh)
local pulse                 -- Sekunden seit dem Sprung, nil: kein Aufleuchten

-- Größe aus opts.size, auf SIZE_MIN bis SIZE_MAX begrenzt; sonst SIZE → Bildpunkte
function Arrow.SizeOf(value)
    local n = ns.Num(value)
    if not n then return Arrow.SIZE end
    return max(Arrow.SIZE_MIN, min(Arrow.SIZE_MAX, n))
end

-- Abstand der Mitte des Pfeils vom Rand der Minikarte → Bildpunkte. Gerechnet mit der sichtbaren Spitze, nicht mit dem
-- halben Bild: Sonst rückt der Pfeil mit der Größe vom Rand weg (Spieltest 24.11.2026: „je größer er wird deesto weiter
-- kommt er vom kreis weg“)
local function Inset(size) return (size or Arrow.SIZE) * Arrow.TIP + Arrow.GAP end

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
-- oder nil, Grund ("where", "near", "facing"); vierter Wert true: verblasst (near = "fade"). Sichtradius und Drehung rechnet ezCores Punkteschicht
-- (MapPins.MinimapRadius, MapPins.MinimapOffset) – dieselbe Geometrie wie die Punkte auf der Minikarte.
-- radius: so weit von der Mitte steht der Pfeil am Rand; half: halbe Breite der Minikarte (Standard radius) – der Maßstab
-- für ein Ziel in Sicht; tip: Spitze über der Mitte des Pfeils in Bildpunkten (Standard 0). In Sicht steht die Spitze auf
-- dem Ziel, am Rand fehlt nur GAP (Nutzer, 24.11.2026, zum Pfeil vor der wahren Stelle: „ja bitte“)
function Arrow.Layout(target, radius, half, tip)
    local _, yards, east, south = Arrow.Bearing(target)
    if not yards then return nil, "where" end
    local near = yards < Arrow.NEAR
    if near and (target.near ~= "fade" or yards < Arrow.HERE) then return nil, "near" end
    local rotating, facing = Arrow.Rotation()
    if rotating == nil then return nil, "facing" end
    local P = Core.MapPins
    local view = P and type(P.MinimapRadius) == "function" and ns.Num((P.MinimapRadius())) or nil
    if not (view and view > 0) then view = yards end
    local e, n
    if P and type(P.MinimapOffset) == "function" then e, n = P.MinimapOffset(east, south, view, rotating and facing or nil) end
    if not e then return nil, "where" end
    radius = radius or 0
    local angle = atan2(e, n)
    local r = max(Arrow.INNER * radius, min(radius, (half or radius) * sqrt(e * e + n * n) - (tip or 0)))
    return angle, r * sin(angle), r * cos(angle), near
end

-- Auf welcher Hälfte steht die Zeile: gegenüber dem Pfeil; steht er seitlich, bleibt sie, wo sie war. → "TOP" | "BOTTOM"
function Arrow.TextSide(dy, radius, before)
    if type(dy) == "number" and type(radius) == "number" and radius > 0 then
        if dy > 0.2 * radius then return "BOTTOM" end
        if dy < -0.2 * radius then return "TOP" end
    end
    return before or "BOTTOM"
end

-- Zeile setzen und an ihre Hälfte hängen; leer: verborgen. side fehlt: wo sie ist
local function DrawText(target, side)
    if not (textFrame and label) then return end
    local text = target and target.text or nil
    local mm = rawget(_G, "Minimap")
    local width = mm and mm.GetWidth and ns.Num(mm:GetWidth()) or nil
    if not (text and width and width > 0) then
        textFrame:Hide()
        return
    end
    side = side or textFrame.side or "BOTTOM"
    if textFrame.side ~= side or textFrame.width ~= width then
        textFrame.side, textFrame.width = side, width
        label:ClearAllPoints()
        label:SetPoint(side, mm, side, 0, (side == "TOP" and -1 or 1) * Arrow.TEXT_INSET * width)
        label:SetWidth(Arrow.TEXT_WIDTH * width)
    end
    if textFrame.text ~= text then
        textFrame.text = text
        label:SetText(text)
    end
    textFrame:Show()
end

local spot = {}             -- Lage laut Place: angle, dx, dy, faded (angle nil: kein Pfeil)

-- Größe, Lage, Farbe und Deckkraft setzen – die einzige Stelle dafür. share: Anteil des Aufleuchtens (0: keines); der
-- Pfeil wächst nach innen, seine Spitze bleibt, wo sie ist. Deckkraft nur über die Farbe (SetAlpha und der vierte Wert
-- von SetVertexColor können im Client derselbe Wert sein)
local function Paint(target, share)
    local size = target.size or Arrow.SIZE
    local grow = size * Arrow.PULSE_SCALE * share
    frame:SetSize(size + grow, size + grow)
    local fam = ns.RouteDraw.Family(target.family)
    local c = fam and fam.from or { 1, 0.82, 0 }
    local alpha = Arrow.ALPHA * (spot.faded and Arrow.FADE or 1)
    tex:SetVertexColor(c[1] + (1 - c[1]) * share, c[2] + (1 - c[2]) * share, c[3] + (1 - c[3]) * share,
        alpha + (1 - alpha) * share)
    if not spot.angle then return end
    local back = grow * Arrow.TIP
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", rawget(_G, "Minimap"), "CENTER", spot.dx - back * sin(spot.angle),
        spot.dy - back * cos(spot.angle))
end

-- Anteil des Aufleuchtens jetzt: 0 bis 1
local function Share()
    return pulse and math.abs(sin(pulse / Arrow.PULSE * Arrow.PULSE_COUNT * math.pi)) or 0
end

-- Ein Bild des Aufleuchtens → true, solange es läuft
function Arrow.PulseStep(elapsed, target)
    if not (pulse and target and frame) then return false end
    pulse = pulse + (tonumber(elapsed) or 0)
    if pulse >= Arrow.PULSE then pulse = nil end
    Paint(target, Share())
    return pulse ~= nil
end

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
    local size = target and target.size or Arrow.SIZE
    local angle, dx, dy, faded, radius = nil, nil, nil, nil, nil
    if target and width and width > 0 then
        local half = width / 2
        radius = half - Inset(size)
        -- zu kleine Minikarte: kein Pfeil statt verkehrt
        if radius > 0 then angle, dx, dy, faded = Arrow.Layout(target, radius, half, size * Arrow.TIP) end
    end
    DrawText(target, angle and Arrow.TextSide(dy, radius, textFrame and textFrame.side) or nil)
    spot.angle, spot.dx, spot.dy, spot.faded = angle, dx, dy, faded
    if target then Paint(target, Share()) end
    if not angle then
        tex:Hide()
        return
    end
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
    -- eigene Fläche für die Zeile: der Rahmen des Pfeils wandert
    textFrame = CreateFrame("Frame", nil, frame)
    textFrame:SetAllPoints(mm)
    if textFrame.EnableMouse then textFrame:EnableMouse(false) end
    label = textFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if label.SetMaxLines then label:SetMaxLines(Arrow.TEXT_LINES) end
    textFrame:Hide()
    local wait = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        if pulse then ns.Try("MiniArrow", Arrow.PulseStep, elapsed, shown) end
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
        pulse = nil
        if frame then frame:Hide() end
        return false
    end
    if not Build() then return false end
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
    targets[owner] = { map = m, x = x, y = y, family = family, size = Arrow.SizeOf(opts.size),
        near = opts.near == "fade" and "fade" or nil, text = Arrow.TextOf(opts.text) }
    -- aufleuchten nur, wenn dieses Ziel auch gezeigt wird
    if opts.pulse == true and select(2, Arrow.Current()) == owner then pulse = 0 end
    Arrow.Refresh()
    return true
end

-- Text eines Moduls: nur eine lesbare, nicht leere Zeichenkette
function Arrow.TextOf(text)
    text = Core.Plain(text)
    return type(text) == "string" and text ~= "" and text or nil
end

-- Nur die Zeile ändern (nil: weg) → true, wenn der Besitzer ein Ziel hat
function Arrow.Text(owner, text)
    local target = owner ~= nil and targets[owner] or nil
    if not target then return false end
    target.text = Arrow.TextOf(text)
    if target == shown then DrawText(target) end
    return true
end

function Arrow.Clear(owner)
    if owner ~= nil then targets[owner] = nil end
    Arrow.Refresh()
    return true
end

-- Für Prüfungen: Rahmen, Bild, Fläche und Zeile des Textes; läuft das Aufleuchten?
function Arrow.Frame() return frame, tex, textFrame, label end
function Arrow.Pulsing() return pulse ~= nil end
