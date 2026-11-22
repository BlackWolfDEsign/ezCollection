local _, ns = ...
local Core = ezCore

--[[
    Zeichnung der Routenlinien auf der Weltkarte – eine für beide Linien (Leitlinie 2): die Sammel-Route „Route durch
    diese Zone“ (Route.Redraw) und die Wege anderer Module (Route.ShowPath, ezQuests Leveling-Route). Spielbefunde des
    Nutzers vom 18.11.2026, wörtlich: „pfad muss sich mit meiner position aktualisieren "auflösen"“, „pfade evtl mit
    pfeilrichtung“, „lvl route wirkt komisch“ (kurze Linien im Zickzack ohne erkennbare Ziele an den Knicken).

      - Anfang an deinem Ort: die Linie beginnt dort, wo du stehst, und folgt dir gedrosselt (Draw.FOLLOW Sekunden, nur
        solange die Karte offen ist – der Takt hängt am eigenen Linien-Rahmen, der mit der Kartenfläche verschwindet).
        Stehst du schon am nächsten Schritt, entfällt das Stück dorthin; erreichte Schritte nimmt der Besitzer der Route
        weg (Ernte, erfülltes Ziel, Abgabe). Dein Ort kommt über ezCore (Core.PlayerPosition → C_Map.GetPlayerMapPosition;
        ein gesperrter Wert gilt als unbekannt, Core.Map.XY prüft Core.IsSecret zuerst).
      - Pfeile in Laufrichtung: zwei kurze Striche je Pfeil („>“) aus Blizzards weißer Fläche (WHITE8X8, Farbe der Linie)
        über CreateLine – keine fremde Grafik, keine gedrehte Textur mit unbekannter Grundrichtung.
      - Schritte: jeder Knick hat eine Marke mit der Nummer des Schritts (wie im Menü der Route), der nächste Schritt
        ist größer und in Blizzards Gold; der Tooltip nennt den Schritt. Schritte, die auf dem Bildschirm näher als
        Draw.GROUP_PX beieinander liegen und direkt aufeinander folgen, teilen sich eine Marke („3–4“) ohne Strich
        dazwischen – kein Zickzack aus Strichen von wenigen Bildpunkten. Kehrt die Linie später an einen Ort zurück,
        trägt seine eine Marke alle Nummern („1, 3“; golden, wenn einer davon der nächste ist) statt zwei Marken
        übereinander (Fund der Gegenprüfung vom 18.11.2026). Die Marke steht Draw.MARK_OFFSET Bildpunkte oben rechts
        neben dem Knick: die Linienebene liegt unter Blizzards Symbolen (Quests, Flugpunkte) und ezMaps Sammelpunkten,
        eine Marke genau auf dem Punkt wäre dort verdeckt (Fund der Gegenprüfung vom 18.11.2026). Höchstens
        Draw.MARK_MAX Marken ab dem nächsten.
    Spieltest des Nutzers vom 19.11.2026 (Bild Wald von Elwynn, beide Routen zugleich), wörtlich: „questroute sollte
    vllt farben mit gradient/verlauf sein --> ich erkenne nicht welche route was ist und was bringen dem spieler die
    punkte mit den zahlen?“. Seitdem:
      - Farbfamilie je Route (Draw.FAMILY, Farben aus Core.Style): die Leveling-Route (ezQuest) und Wege anderer Module
        in Gold bis Orange als durchgehender Strich, die Sammel-Route (ezMap) in Blau (Blizzards Linkfarbe bis Hellblau)
        gestrichelt über einer zarten Leitlinie. Beide Routen sind damit auch übereinander klar verschieden.
      - Verlauf entlang der Linie (Draw.Shade): der erste Abschnitt (zum nächsten Schritt) kräftig in der Anfangsfarbe,
        jeder weitere eine Stufe weiter zur Endfarbe und blasser (Deckkraft Draw.ALPHA_START bis Draw.ALPHA_END) – so
        sind Richtung und nächster Abschnitt ohne Lesen der Nummern zu erkennen.
      - Nummern nur, wo sie nützen (Schalter routeNumbers, ab Werk aus): ab Werk trägt nur der nächste Schritt eine
        Marke – groß, in der Anfangsfarbe der Route, mit Nummer und daneben dem Ziel (Quest bzw. Rohstoff). Mit dem
        Schalter tragen alle Schritte eine Marke, die folgenden klein und blasser. Begründung: auf der Karte zählt der
        nächste Schritt; die Reihenfolge zeigen Pfeile und Verlauf, die übrigen Nummern verdeckten nur Blizzards
        Symbole. Wer die ganze Folge sehen will, schaltet sie ein.
      - Maus über einer Marke oder über der Linie (Painter:CheckHover, gedrosselt Draw.HOVER_EVERY): der Tooltip nennt
        die Route („Leveling-Route (ezQuest)“, „Sammel-Route (ezMap)“), den Schritt mit Ziel und die Entfernung von dir.
        Die Linie selbst nimmt keine Maus an: der Takt misst den Abstand des Mauszeigers zu den Abschnitten und zeigt
        Blizzards GameTooltip nur, wenn kein anderer Tooltip offen ist (Blizzards Symbole und Marken haben Vorrang).
        Beim Neuzeichnen (Bewegung bei offener Karte, Zoom) bleibt der Tooltip stehen (Painter:Clear(true),
        Painter:AfterDraw), statt alle 0,5 s zu flackern (Gegenprüfung vom 19.11.2026).
      - Striche der gestrichelten Linie nur im sichtbaren Ausschnitt der Karte (self.viewArea, Draw.ClipT); passen sie
        nicht ins Budget Draw.DASH_MAX, werden Strich und Lücke für die ganze Route länger – die Strichart bleibt auf der
        ganzen Linie gleich (Gegenprüfung vom 19.11.2026: vorher ab einem Abschnitt durchgehend).
    Grafik von Blizzard: WHITE8X8 (Striche, wie bisher) und die runde Maske der Porträts (Interface\CHARACTERFRAME\
    TempPortraitAlphaMask) als Kreis der Marke; Zahl in der Rolle „numberSmall“, Ziel in der Rolle „text“ des
    Design-Systems.
    Taint: nur eigene Rahmen als Kind von Blizzards Kartenfläche, keine Hooks hier (die setzt Route.lua).
]]
local Draw = {}
ns.RouteDraw = Draw

Draw.LINE_THICK = 3         -- Bildpunkte auf dem Bildschirm
Draw.ARROW_GAP = 90         -- Bildpunkte zwischen zwei Pfeilen auf einem Abschnitt
Draw.ARROW_MIN = 36         -- Bildpunkte: kürzere Abschnitte bekommen keinen Pfeil
Draw.ARROW_PER_SEG = 8      -- höchstens so viele Pfeile je Abschnitt
Draw.ARROW_MAX = 160        -- höchstens so viele Pfeile je Zeichnung
Draw.ARROW_LEN = 8          -- Bildpunkte: Länge eines Pfeilstrichs
Draw.ARROW_ANGLE = 0.6      -- Bogenmaß zwischen Linie und Pfeilstrich (etwa 35 Grad)
Draw.GROUP_PX = 14          -- Bildpunkte: so nah beieinander teilen aufeinanderfolgende Schritte eine Marke
Draw.MARK_SIZE = 14         -- Bildpunkte: Kreis eines folgenden Schritts (nur mit routeNumbers)
Draw.NEXT_SIZE = 20         -- Bildpunkte: Kreis des nächsten Schritts
Draw.MARK_MAX = 100         -- höchstens so viele Marken je Zeichnung, ab dem nächsten Schritt
Draw.MARK_COLOR = { 0, 0, 0, 0.5 }          -- folgende Schritte: dunkel und blass
Draw.MARK_TEXT_ALPHA = 0.7  -- Deckkraft der Nummer eines folgenden Schritts
Draw.NEXT_COLOR = { 1, 0.82, 0, 1 }         -- Blizzards Gold (NORMAL_FONT_COLOR; Rückfall ohne Farbfamilie)
Draw.MARK_TEXTURE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
Draw.MARK_OFFSET = 14       -- Bildpunkte: Marke so weit oben rechts neben dem Knick (Symbole darüber verdecken sonst die Zahl)
Draw.TARGET_WIDTH = 220     -- Bildpunkte: höchstens so breit steht das Ziel neben der Marke des nächsten Schritts
Draw.FOLLOW = 0.5           -- Sekunden: so oft schaut die Linie bei offener Karte nach deinem Ort
Draw.MOVED = 0.0005         -- Kartenanteil: kleinere Bewegungen zeichnen nicht neu
-- Farbfamilien (Spieltest 19.11.2026): Anfangs- und Endfarbe als Rollen aus Core.Style (Blizzards Farbobjekte), Strichart
Draw.FAMILY = {
    gold = { from = "normal", to = "orange", style = "solid" },    -- Leveling-Route (ezQuest), Wege anderer Module
    blue = { from = "link", to = "blue", style = "dash" },         -- Sammel-Route (ezMap)
}
Draw.ALPHA_START = 1        -- Deckkraft des ersten Abschnitts (zum nächsten Schritt)
Draw.ALPHA_END = 0.4        -- Deckkraft des letzten Abschnitts
Draw.DASH_LEN = 10          -- Bildpunkte: Länge eines Strichs der gestrichelten Linie
Draw.DASH_GAP = 6           -- Bildpunkte: Lücke dazwischen
Draw.DASH_MAX = 400         -- höchstens so viele Striche je Zeichnung (nur im sichtbaren Ausschnitt gezählt); darüber
                            -- werden Strich und Lücke für die ganze Route länger (Painter:DashFactor), nie halb durchgehend
Draw.DASH_GROW = 1.25       -- so viel länger je Versuch, bis die Striche ins Budget passen
Draw.DASH_TRIES = 24        -- höchstens so viele Versuche (dann durchgehend, für die ganze Route gleich)
Draw.GUIDE_THICK = 1        -- Bildpunkte: Leitlinie unter der gestrichelten Linie
Draw.GUIDE_ALPHA = 0.35     -- ihre Deckkraft (Anteil der Farbe des Abschnitts)
Draw.HOVER_EVERY = 0.1      -- Sekunden: so oft prüft der Takt bei offener Karte, ob die Maus über der Linie steht
Draw.HOVER_PX = 6           -- Bildpunkte: so nah an einem Abschnitt gilt die Maus als darüber

local sqrt, floor, max, min, cos, sin = math.sqrt, math.floor, math.max, math.min, math.cos, math.sin

---------------------------------------------------------------------------
-- Farben (Spieltest 19.11.2026): Farbfamilie je Route, Verlauf entlang der Linie
---------------------------------------------------------------------------

local function RoleRGB(role)
    local Style = Core.Style
    if type(Style) == "table" and type(Style.Color) == "function" then
        local r, g, b = Style.Color(role)
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then return { r, g, b } end
    end
    return { Draw.NEXT_COLOR[1], Draw.NEXT_COLOR[2], Draw.NEXT_COLOR[3] }
end

-- Farbfamilie → { from = { r, g, b }, to = { r, g, b }, alpha, style }. name: Schlüssel aus Draw.FAMILY; ohne Namen und
-- mit color = { r, g, b, a } (ältere Aufrufer von ShowPath) eine Familie aus dieser einen Farbe (nur blasser zum Ende).
function Draw.Family(name, color)
    local def = type(name) == "string" and Draw.FAMILY[name] or nil
    if def then return { from = RoleRGB(def.from), to = RoleRGB(def.to), alpha = 1, style = def.style, name = name } end
    local c = type(color) == "table" and color or Draw.NEXT_COLOR
    local rgb = { tonumber(c[1]) or 1, tonumber(c[2]) or 1, tonumber(c[3]) or 1 }
    return { from = rgb, to = rgb, alpha = tonumber(c[4]) or 1, style = "solid" }
end

-- Farbe an der Stelle f (0 = erster Abschnitt, 1 = letzter) der Familie fam → { r, g, b, a }
function Draw.Shade(fam, f)
    f = tonumber(f) or 0
    if f < 0 then f = 0 elseif f > 1 then f = 1 end
    local a, b = fam.from, fam.to
    local alpha = (fam.alpha or 1) * (Draw.ALPHA_START + (Draw.ALPHA_END - Draw.ALPHA_START) * f)
    return { a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f, alpha }
end

-- Nummern an der Route (ezMaps Schalter routeNumbers): "all" (alle Schritte) oder "next" (nur der nächste, ab Werk)
function Draw.NumbersMode()
    return (type(ns.Enabled) == "function" and ns.Enabled("routeNumbers")) and "all" or "next"
end

-- Entfernung von dir zum Punkt x, y (Kartenanteil) auf der Karte map → „120 Yards“ oder nil (nicht dort, unbekannt,
-- Karte ohne Größe)
function Draw.DistanceText(map, x, y)
    x, y = tonumber(x), tonumber(y)
    if not (map and x and y) then return nil end
    local px, py = Draw.PlayerOn(map)
    local D = Core.Discovery
    if not px or not (type(D) == "table" and type(D.MapYards) == "function") then return nil end
    local w, h = D.MapYards(map)
    w, h = tonumber(w), tonumber(h)
    if not (w and h) then return nil end
    local d = sqrt(((x - px) * w) ^ 2 + ((y - py) * h) ^ 2)
    return Core.L.GATHER_YARDS:format(floor(d + 0.5))
end

---------------------------------------------------------------------------
-- Reine Rechnung (ohne Rahmen; Bildpunkte der Kartenfläche, y nach unten)
---------------------------------------------------------------------------

-- Pfeile eines Abschnitts von a nach b → Liste { x, y (Spitze), lx, ly, rx, ry (Enden der beiden Striche) }. scale ist
-- der Zoom der Kartenfläche: Abstand und Größe gelten in Bildpunkten auf dem Bildschirm.
function Draw.Arrows(ax, ay, bx, by, scale)
    scale = (type(scale) == "number" and scale > 0) and scale or 1
    local dx, dy = bx - ax, by - ay
    local len = sqrt(dx * dx + dy * dy)
    if len <= 0 or len * scale < Draw.ARROW_MIN then return {} end
    local n = max(1, min(Draw.ARROW_PER_SEG, floor(len * scale / Draw.ARROW_GAP)))
    local ux, uy = dx / len, dy / len
    local wing = Draw.ARROW_LEN / scale
    local c, s = cos(Draw.ARROW_ANGLE), sin(Draw.ARROW_ANGLE)
    -- Richtung zurück, um +/- den Winkel gedreht
    local lx, ly = -(ux * c - uy * s), -(ux * s + uy * c)
    local rx, ry = -(ux * c + uy * s), -(-ux * s + uy * c)
    local out = {}
    for k = 1, n do
        local f = (k - 0.5) / n
        local tx, ty = ax + dx * f + ux * wing * 0.5, ay + dy * f + uy * wing * 0.5
        out[k] = { x = tx, y = ty, lx = tx + lx * wing, ly = ty + ly * wing, rx = tx + rx * wing, ry = ty + ry * wing }
    end
    return out
end

-- Schritte zu Marken zusammenfassen: seq = Liste { x, y (Bildpunkte) oder ohne x (nicht auf dieser Karte), n, label,
-- noMark (nur Knick, keine eigene Marke – etwa der Schluss eines Rings) } in Reihenfolge. Folgt ein Schritt direkt auf
-- den vorigen und liegt näher als Draw.GROUP_PX (Bildschirm) am ersten der Gruppe, kommt er dazu.
-- → Liste { x, y, first, last, labels, members, noMark } bzw. { gap = true } (Lücke, nicht auf der Karte)
function Draw.Group(seq, scale)
    scale = (type(scale) == "number" and scale > 0) and scale or 1
    local limit = Draw.GROUP_PX / scale
    local out, cur = {}, nil
    for _, p in ipairs(seq) do
        if not p.x then
            cur = nil
            out[#out + 1] = { gap = true }
        elseif p.off then
            -- neben der Karte (Lage außerhalb der Fläche): eigener Knick ohne Marke, die Linie läuft zum Rand
            cur = nil
            out[#out + 1] = { x = p.x, y = p.y, first = p.n, last = p.n, labels = { p.label }, members = { p },
                noMark = true, off = true }
        elseif cur and (p.x - cur.x) ^ 2 + (p.y - cur.y) ^ 2 < limit * limit then
            if not p.noMark then
                cur.last = p.n
                cur.members[#cur.members + 1] = p
            end
            if p.label then cur.labels[#cur.labels + 1] = p.label end
        else
            cur = { x = p.x, y = p.y, first = p.n, last = p.n, labels = { p.label }, members = { p }, noMark = p.noMark }
            out[#out + 1] = cur
        end
    end
    return out
end

-- Text der Marke: „3“, „3–4“ (Gruppe) bzw. „1, 3“ (Ort mit mehreren Gruppen, parts aus Draw.Spots)
function Draw.MarkText(g)
    if type(g.parts) == "table" and #g.parts > 1 then
        local texts = {}
        for _, part in ipairs(g.parts) do texts[#texts + 1] = Draw.MarkText(part) end
        return table.concat(texts, ", ")
    end
    if g.first == nil then return "" end
    if g.last == nil or g.last == g.first then return tostring(g.first) end
    return tostring(g.first) .. "–" .. tostring(g.last)
end

-- Enthält die Gruppe den Schritt n?
local function Holds(g, n)
    if n == nil or g.members == nil then return false end
    for _, p in ipairs(g.members) do
        if p.n == n then return true end
    end
    return false
end

-- Marken je Ort: Gruppen aus Draw.Group (ohne Lücken und Knicke ohne Marke; eine Nummer nur einmal – der Schluss eines
-- Rings kehrt zum ersten Punkt zurück), die auf dem Bildschirm näher als Draw.GROUP_PX an einer schon gesetzten Marke
-- liegen, kommen zu ihr – auch wenn andere Schritte dazwischen liegen (Linie A – B – A: eine Marke „1, 3“ an A).
-- nextN: Nummer des nächsten Schritts; limit: höchstens so viele Orte → Liste { x, y, first, last, labels, parts, isNext }
function Draw.Spots(groups, scale, nextN, limit)
    scale = (type(scale) == "number" and scale > 0) and scale or 1
    local near = Draw.GROUP_PX / scale
    local spots, numbered = {}, {}
    for _, g in ipairs(groups) do
        if not g.gap and not g.noMark and g.first ~= nil and not numbered[g.first] then
            numbered[g.first] = true
            local spot
            for _, s in ipairs(spots) do
                if (g.x - s.x) ^ 2 + (g.y - s.y) ^ 2 < near * near then
                    spot = s
                    break
                end
            end
            if spot then
                spot.parts[#spot.parts + 1] = g
                spot.last = g.last
                for _, l in ipairs(g.labels) do spot.labels[#spot.labels + 1] = l end
                spot.isNext = spot.isNext or Holds(g, nextN)
            elseif limit == nil or #spots < limit then
                local labels = {}
                for _, l in ipairs(g.labels) do labels[#labels + 1] = l end
                spots[#spots + 1] = { x = g.x, y = g.y, first = g.first, last = g.last, labels = labels, parts = { g },
                    isNext = Holds(g, nextN) }
            end
        end
    end
    return spots
end

-- Ziel des Schritts n an einem Ort (aus Draw.Spots bzw. Draw.Group): das Feld target des Schritts, sonst nil
function Draw.TargetOf(spot, n)
    for _, part in ipairs(type(spot.parts) == "table" and spot.parts or { spot }) do
        for _, p in ipairs(part.members or {}) do
            if p.n == n and type(p.target) == "string" and p.target ~= "" then return p.target end
        end
    end
    return nil
end

-- Abstand des Punkts x, y zum Abschnitt a – b (Bildpunkte der Kartenfläche)
function Draw.SegDist(x, y, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local len2 = dx * dx + dy * dy
    local t = len2 > 0 and ((x - ax) * dx + (y - ay) * dy) / len2 or 0
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local qx, qy = ax + dx * t, ay + dy * t
    return sqrt((x - qx) ^ 2 + (y - qy) ^ 2)
end

-- Nächster Abschnitt zu x, y aus segs ({ ax, ay, bx, by } …), höchstens limit entfernt → Abschnitt oder nil
function Draw.Nearest(segs, x, y, limit)
    local best, bestD
    for _, s in ipairs(segs) do
        local d = Draw.SegDist(x, y, s.ax, s.ay, s.bx, s.by)
        if d <= limit and (bestD == nil or d < bestD) then best, bestD = s, d end
    end
    return best
end

---------------------------------------------------------------------------
-- Zeichner: Striche, Pfeile und Marken auf einem Rahmen über Blizzards Kartenfläche
---------------------------------------------------------------------------

local Painter = {}
Painter.__index = Painter

local function NewLine(frame, sub)
    if type(frame.CreateLine) ~= "function" then return false end
    local ok, created = pcall(frame.CreateLine, frame, nil, "OVERLAY", nil, sub)
    return ok and type(created) == "table" and created or false
end

-- Tooltip einer Marke bzw. eines Abschnitts: Name der Route als Titel, darunter die Zeilen der Schritte (head: etwa
-- „Weg zu Schritt 3“) und die Entfernung von dir zum Ort (Kartenanteil x, y auf der Karte map). Ohne Namen der Route
-- (ältere Aufrufer) steht der Schritt im Titel wie bisher.
function Draw.FillTip(tip, name, labels, head, map, x, y)
    local L = ns.L
    local list = type(labels) == "table" and labels or {}
    if name then
        Core.TipTitle(tip, name)
        if head then Core.TipLine(tip, head, "normal") end
        for _, line in ipairs(list) do Core.TipLine(tip, line, "highlight", true) end
    else
        Core.TipTitle(tip, list[1] or head or "")
        for i = 2, #list do Core.TipLine(tip, list[i], "highlight", true) end
    end
    local dist = Draw.DistanceText(map, x, y)
    if dist then Core.TipLine(tip, L.ROUTE_TIP_DIST:format(dist), "hint") end
end

local function MarkEnter(self)
    local tip = rawget(_G, "GameTooltip")
    if not (tip and (self.ezLabel or self.ezName)) then return end
    tip:SetOwner(self, "ANCHOR_RIGHT")
    Draw.FillTip(tip, self.ezName, self.ezLabels, nil, self.ezMap, self.ezX, self.ezY)
    tip:Show()
end

local function MarkLeave()
    local tip = rawget(_G, "GameTooltip")
    if tip then tip:Hide() end
end

local function NewMark(layer)
    local f = CreateFrame("Frame", nil, layer)
    f.Circle = f:CreateTexture(nil, "ARTWORK")
    f.Circle:SetAllPoints(f)
    f.Circle:SetTexture(Draw.MARK_TEXTURE)
    f.Text = f:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")     -- Rolle numberSmall des Design-Systems
    f.Text:SetPoint("CENTER", f, "CENTER", 0, 0)
    -- Ziel des nächsten Schritts rechts neben dem Kreis (Rolle „text“ des Design-Systems), eine Zeile
    f.Target = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.Target:SetPoint("LEFT", f, "RIGHT", 3, 0)
    if f.Target.SetWidth then f.Target:SetWidth(Draw.TARGET_WIDTH) end
    if f.Target.SetJustifyH then f.Target:SetJustifyH("LEFT") end
    if f.Target.SetWordWrap then f.Target:SetWordWrap(false) end
    f.Target:Hide()
    -- nur die Mausbewegung (Tooltip), Klicks gehen durch auf Blizzards Karte; ohne diese Abfragen keine Maus
    if type(f.SetMouseClickEnabled) == "function" and type(f.SetMouseMotionEnabled) == "function" then
        f:SetMouseClickEnabled(false)
        f:SetMouseMotionEnabled(true)
        f:SetScript("OnEnter", MarkEnter)
        f:SetScript("OnLeave", MarkLeave)
    elseif f.EnableMouse then
        f:EnableMouse(false)
    end
    return f
end

-- Zeichner für den Rahmen layer (Kind von Blizzards Kartenfläche)
function Draw.Painter(layer)
    return setmetatable({ layer = layer, lines = {}, arrows = {}, marks = {}, dashes = {}, segs = {}, nLines = 0,
        nArrows = 0, nMarks = 0, nDashes = 0, failed = false }, Painter)
end

-- Tooltip über der Linie freigeben (nur, wenn er diesem Zeichner gehört)
function Painter:ReleaseTip()
    self.hovered = nil
    local tip = rawget(_G, "GameTooltip")
    if tip and self.layer and tip.IsOwned and tip:IsOwned(self.layer) then tip:Hide() end
end

-- Alles verstecken und für eine neue Zeichnung mit der Fläche w × h beim Zoom scale bereit machen; map: die gezeigte
-- Karte (für die Entfernung im Tooltip, freiwillig)
function Painter:Begin(w, h, scale, map)
    for _, l in ipairs(self.lines) do if l then l:Hide() end end
    for _, l in ipairs(self.arrows) do if l then l:Hide() end end
    for _, l in ipairs(self.dashes) do if l then l:Hide() end end
    for _, m in ipairs(self.marks) do m:Hide() end
    self.nLines, self.nArrows, self.nMarks, self.nDashes, self.failed = 0, 0, 0, 0, false
    self.segs = {}
    self.w, self.h, self.scale, self.map = w, h, scale, map
end

-- Alles verstecken (Karte zu, nichts zu zeichnen). keepTip: der Tooltip über der Linie bleibt stehen, weil gleich neu
-- gezeichnet wird – danach Painter:AfterDraw (sonst flackerte er bei jedem Neuzeichnen, Gegenprüfung vom 19.11.2026)
function Painter:Clear(keepTip)
    if not keepTip then self:ReleaseTip() end
    self:Begin(self.w, self.h, self.scale)
    self.followMap = nil
end

-- Nach einer Zeichnung mit Clear(true): gehört der Tooltip diesem Zeichner, gleich an die neuen Abschnitte hängen bzw.
-- freigeben, wenn nichts mehr gezeichnet ist oder die Maus nicht mehr über der Linie steht
function Painter:AfterDraw()
    local tip = rawget(_G, "GameTooltip")
    if not (tip and self.layer and tip.IsOwned and tip:IsOwned(self.layer)) then
        self.hovered = nil
        return
    end
    if #self.segs == 0 then return self:ReleaseTip() end
    self.hovered = nil
    self:CheckHover()
end

local function Place(line, layer, ax, ay, bx, by, thick, c)
    line:SetStartPoint("TOPLEFT", layer, ax, -ay)
    line:SetEndPoint("TOPLEFT", layer, bx, -by)
    line:SetThickness(thick)
    line:SetColorTexture(c[1], c[2], c[3], c[4])
    line:Show()
end

-- Ein Strich, ohne Pfeil (Bildpunkte der Kartenfläche; thick in Bildpunkten auf dem Bildschirm, Standard
-- Draw.LINE_THICK) → true, wenn gezeichnet
function Painter:Line(ax, ay, bx, by, color, thick)
    local i = self.nLines + 1
    local line = self.lines[i]
    if line == nil then
        line = NewLine(self.layer)
        self.lines[i] = line
    end
    if not line then
        self.failed = true
        return false
    end
    self.nLines = i
    Place(line, self.layer, ax, ay, bx, by, (thick or Draw.LINE_THICK) / self.scale, color)
    return true
end

-- Teil des Abschnitts a → b im Rechteck rect = { x0, y0, x1, y1 } (Liang-Barsky) → t0, t1 (Anteile 0 bis 1) oder nil,
-- wenn er ganz außerhalb liegt; ohne rect der ganze Abschnitt
function Draw.ClipT(ax, ay, bx, by, rect)
    if type(rect) ~= "table" then return 0, 1 end
    local t0, t1 = 0, 1
    local function edge(p, q)
        if p == 0 then return q >= 0 end
        local r = q / p
        if p < 0 then
            if r > t1 then return false end
            if r > t0 then t0 = r end
        else
            if r < t0 then return false end
            if r < t1 then t1 = r end
        end
        return true
    end
    local dx, dy = bx - ax, by - ay
    if edge(-dx, ax - rect[1]) and edge(dx, rect[3] - ax) and edge(-dy, ay - rect[2]) and edge(dy, rect[4] - ay) then
        return t0, t1
    end
    return nil
end

-- Striche auf dem Abschnitt a → b beim Strichmaß period (Kartenfläche) im Rechteck rect → erste Nummer k0, Zahl n,
-- Länge des Abschnitts. Die Striche bleiben an den Anfang des Abschnitts gebunden (beim Verschieben der Karte wandern
-- sie nicht).
function Draw.DashRange(ax, ay, bx, by, period, rect)
    local dx, dy = bx - ax, by - ay
    local len = sqrt(dx * dx + dy * dy)
    if len <= 0 or not (period and period > 0) then return 0, 0, len end
    local t0, t1 = Draw.ClipT(ax, ay, bx, by, rect)
    if not t0 then return 0, 0, len end
    local k0 = floor(t0 * len / period)
    local k1 = math.ceil(t1 * len / period)
    return k0, max(0, k1 - k0), len
end

-- Sichtbarer Ausschnitt (self.viewArea, freiwillig: fn(layer) → x0, y0, x1, y1 in Bildpunkten der Kartenfläche) mit
-- Rand margin → { x0, y0, x1, y1 } oder nil (dann zählt die ganze Linie)
function Painter:ViewRect(margin)
    if type(self.viewArea) ~= "function" then return nil end
    local x0, y0, x1, y1 = self.viewArea(self.layer)
    if not (type(x0) == "number" and type(y0) == "number" and type(x1) == "number" and type(y1) == "number") then return nil end
    local m = margin or 0
    return { min(x0, x1) - m, min(y0, y1) - m, max(x0, x1) + m, max(y0, y1) + m }
end

-- Faktor für Strich und Lücke der ganzen gestrichelten Route list (Abschnitte { ax, ay, { x, y } }) → f, rect: f = 1,
-- solange die sichtbaren Striche ins Restbudget passen, sonst so viel länger, dass sie passen; nil, wenn auch das nicht
-- reicht (dann durchgehend, für die ganze Route gleich). Gegenprüfung vom 19.11.2026: vorher entschied das Budget je
-- Abschnitt, und die Linie wechselte mitten drin von gestrichelt auf durchgehend.
function Painter:DashFactor(list)
    local base = (Draw.DASH_LEN + Draw.DASH_GAP) / (self.scale or 1)
    local rect = self:ViewRect(base)
    local budget = Draw.DASH_MAX - (self.nDashes or 0)
    local f = 1
    for _ = 1, Draw.DASH_TRIES do
        local need = 0
        for _, s in ipairs(list) do
            local _, n = Draw.DashRange(s[1], s[2], s[3].x, s[3].y, base * f, rect)
            need = need + n
        end
        if need <= budget then return f, rect end
        f = f * Draw.DASH_GROW
    end
    return nil, rect
end

-- Striche der gestrichelten Linie auf dem Abschnitt a → b (Länge und Lücke in Bildpunkten auf dem Bildschirm, mal
-- self.dashFactor; nur im Ausschnitt self.dashRect) → true, wenn gezeichnet; false, wenn Draw.DASH_MAX erreicht wäre
-- oder die ganze Route durchgehend gezeichnet wird (dashFactor false; dann zeichnet der Aufrufer durchgehend)
function Painter:Dashes(ax, ay, bx, by, color)
    local scale = self.scale
    local f = self.dashFactor
    if f == false then return false end
    f = f or 1
    local period = (Draw.DASH_LEN + Draw.DASH_GAP) * f / scale
    local k0, n, len = Draw.DashRange(ax, ay, bx, by, period, self.dashRect)
    if len <= 0 or n == 0 then return true end
    if self.nDashes + n > Draw.DASH_MAX then return false end
    local dx, dy = bx - ax, by - ay
    local ux, uy = dx / len, dy / len
    local dash = Draw.DASH_LEN * f / scale
    for k = k0, k0 + n - 1 do
        local t0 = min(len, k * period)
        local t1 = min(len, t0 + dash)
        local i = self.nDashes + 1
        local line = self.dashes[i]
        if line == nil then
            line = NewLine(self.layer)
            self.dashes[i] = line
        end
        if not line then return false end
        self.nDashes = i
        Place(line, self.layer, ax + ux * t0, ay + uy * t0, ax + ux * t1, ay + uy * t1, Draw.LINE_THICK / scale, color)
    end
    return true
end

-- Pfeile auf dem Abschnitt a → b
function Painter:Arrows(ax, ay, bx, by, color)
    for _, a in ipairs(Draw.Arrows(ax, ay, bx, by, self.scale)) do
        if self.nArrows + 2 > Draw.ARROW_MAX * 2 then return end
        for _, wing in ipairs({ { a.lx, a.ly }, { a.rx, a.ry } }) do
            local i = self.nArrows + 1
            local line = self.arrows[i]
            if line == nil then
                line = NewLine(self.layer, 1)
                self.arrows[i] = line
            end
            if not line then return end
            self.nArrows = i
            Place(line, self.layer, a.x, a.y, wing[1], wing[2], Draw.LINE_THICK / self.scale, color)
        end
    end
end

-- Abschnitt mit Pfeilen in Laufrichtung → true, wenn gezeichnet. style "dash": gestrichelt über einer zarten Leitlinie
-- (Sammel-Route); hover = { to (Gruppe des Ziels), name (Route) } für den Tooltip über der Linie (freiwillig)
function Painter:Segment(ax, ay, bx, by, color, style, hover)
    local dashed = style == "dash" and self:Dashes(ax, ay, bx, by, color)
    local lineColor, thick = color, nil
    if dashed then lineColor, thick = { color[1], color[2], color[3], color[4] * Draw.GUIDE_ALPHA }, Draw.GUIDE_THICK end
    if not self:Line(ax, ay, bx, by, lineColor, thick) then return false end
    self:Arrows(ax, ay, bx, by, color)
    if hover then
        self.segs[#self.segs + 1] = { ax = ax, ay = ay, bx = bx, by = by, to = hover.to, name = hover.name }
    end
    return true
end

-- Marke eines Orts (aus Draw.Spots) oben rechts neben ihm (Draw.MARK_OFFSET). isNext: groß, in der Anfangsfarbe der
-- Route (fam, sonst Blizzards Gold) und mit dem Ziel daneben (target); sonst klein und blass. name: Name der Route
-- für den Tooltip.
function Painter:Mark(g, isNext, fam, name, target)
    local i = self.nMarks + 1
    local m = self.marks[i]
    if not m then
        m = NewMark(self.layer)
        self.marks[i] = m
    end
    self.nMarks = i
    local scale = self.scale
    local size = isNext and Draw.NEXT_SIZE or Draw.MARK_SIZE
    local c = Draw.MARK_COLOR
    if isNext then
        c = fam and { fam.from[1], fam.from[2], fam.from[3], 1 } or Draw.NEXT_COLOR
    end
    -- gleich groß bei jedem Zoom: eigener Maßstab 1/Zoom, die Lage dann in diesem Maßstab
    if m.SetScale then m:SetScale(1 / scale) end
    m:SetSize(size, size)
    m:ClearAllPoints()
    -- neben dem Knick statt darauf: Blizzards Symbole und ezMaps Punkte liegen über der Linienebene
    m:SetPoint("CENTER", self.layer, "TOPLEFT", g.x * scale + Draw.MARK_OFFSET, -g.y * scale + Draw.MARK_OFFSET)
    m.Circle:SetVertexColor(c[1], c[2], c[3], c[4])
    m.Text:SetText(Draw.MarkText(g))
    if m.Text.SetAlpha then m.Text:SetAlpha(isNext and 1 or Draw.MARK_TEXT_ALPHA) end
    if isNext and target then
        m.Target:SetText(target)
        m.Target:Show()
    else
        m.Target:SetText("")
        m.Target:Hide()
    end
    m.ezLabels = g.labels
    m.ezLabel = #g.labels > 0 and table.concat(g.labels, "\n") or nil
    m.ezName = name
    m.ezTarget = isNext and target or nil
    m.ezNext = isNext and true or false
    m.ezFirst, m.ezLast = g.first, g.last
    local w, h = tonumber(self.w), tonumber(self.h)
    m.ezMap = self.map
    m.ezX, m.ezY = w and w > 0 and g.x / w or nil, h and h > 0 and g.y / h or nil
    m:Show()
    return m
end

--[[
    Einen Weg zeichnen: seq = Schritte in Reihenfolge { x, y (Kartenanteil auf der gezeigten Karte; ohne: nicht auf
    dieser Karte), n (Nummer), label (Tooltip), target (Ziel, kurz: steht neben der Marke des nächsten Schritts),
    noMark }; opts = { start = { x, y } (dein Ort auf dieser Karte, freiwillig), family (Schlüssel aus Draw.FAMILY) oder
    color (eine Farbe, ältere Aufrufer), name (Name der Route für Tooltips), nextN (Nummer des nächsten Schritts), marks
    (false: ohne Marken), numbers ("all" | "next"; Standard Draw.NumbersMode()) }. Eine Nummer bekommt nur eine Marke,
    ein Ort nur eine (Draw.Spots). Die Abschnitte laufen im Verlauf der Familie (Draw.Shade): der erste kräftig, der
    letzte blass. → Zahl der Abschnitte
]]
function Painter:Path(seq, opts)
    opts = opts or {}
    local w, h, scale = self.w, self.h, self.scale
    local px = {}
    for i, p in ipairs(seq) do
        if p.x and p.y then
            px[i] = { x = p.x * w, y = p.y * h, n = p.n, label = p.label, target = p.target, noMark = p.noMark,
                off = p.off }
        else
            px[i] = { n = p.n }
        end
    end
    local groups = Draw.Group(px, scale)
    local fam = Draw.Family(opts.family, opts.color)
    local list = {}
    -- Anfang an deinem Ort, außer du stehst schon am ersten Schritt
    local first = groups[1]
    if opts.start and first and not first.gap then
        local sx, sy = opts.start[1] * w, opts.start[2] * h
        local limit = Draw.GROUP_PX / scale
        if (first.x - sx) ^ 2 + (first.y - sy) ^ 2 >= limit * limit then
            list[#list + 1] = { sx, sy, first }
        end
    end
    for k = 2, #groups do
        local a, b = groups[k - 1], groups[k]
        -- zwei Schritte neben der Karte: keine Linie quer über die Karte (Spielbefund vom 21.11.2026 – eine Linie ohne
        -- Punkte lief durch Elwynn); vom letzten Schritt auf der Karte führt die Linie bis zum Rand in Richtung des nächsten
        if not a.gap and not b.gap and not (a.off and b.off) then list[#list + 1] = { a.x, a.y, b } end
    end
    -- Abschnitte zu Schritten neben der Karte (off) enden am Kartenrand: EINE durchgehende Linie statt zweier Stücke
    -- (Spielbefund vom 19.11.2026, Bilder 35–37 und 42: „es sieht wie 2 leveling routen aus“; vorher fiel ein Schritt
    -- außerhalb der Karte als Lücke heraus, und lag der nächste Schritt dort, begann die Linie nicht an deinem Ort)
    local clipped = {}
    local area = { 0, 0, w, h }
    for _, s in ipairs(list) do
        local ax, ay, bx, by = s[1], s[2], s[3].x, s[3].y
        local t0, t1 = Draw.ClipT(ax, ay, bx, by, area)
        if t0 and t1 > t0 then
            clipped[#clipped + 1] = { ax + (bx - ax) * t0, ay + (by - ay) * t0,
                { x = ax + (bx - ax) * t1, y = ay + (by - ay) * t1 }, to = s[3] }
        end
    end
    list = clipped
    local drawn = 0
    -- gestrichelt: ein Strichmaß für die ganze Route (Painter:DashFactor), nicht je Abschnitt
    self.dashFactor, self.dashRect = nil, nil
    if fam.style == "dash" then
        local f, rect = self:DashFactor(list)
        self.dashFactor, self.dashRect = f or false, rect
    end
    for k, s in ipairs(list) do
        local color = Draw.Shade(fam, #list > 1 and (k - 1) / (#list - 1) or 0)
        if self:Segment(s[1], s[2], s[3].x, s[3].y, color, fam.style, { to = s.to, name = opts.name }) then
            drawn = drawn + 1
        end
    end
    self.dashFactor, self.dashRect = nil, nil
    if opts.marks ~= false then
        local onlyNext = (opts.numbers or Draw.NumbersMode()) ~= "all"
        for _, spot in ipairs(Draw.Spots(groups, scale, opts.nextN, max(0, Draw.MARK_MAX - self.nMarks))) do
            if spot.isNext or not onlyNext then
                self:Mark(spot, spot.isNext, fam, opts.name, spot.isNext and Draw.TargetOf(spot, opts.nextN) or nil)
            end
        end
    end
    return drawn
end

-- Dein Mauszeiger: Lage über dem Rahmen frame in dessen Bildpunkten (von oben links, y nach unten) oder nil
function Draw.CursorOn(frame)
    local get = rawget(_G, "GetCursorPosition")
    if type(get) ~= "function" or not (frame and frame.GetLeft and frame.GetTop and frame.GetEffectiveScale) then return nil end
    local cx, cy = get()
    local scale, left, top = tonumber(frame:GetEffectiveScale()), tonumber(frame:GetLeft()), tonumber(frame:GetTop())
    cx, cy = tonumber(cx), tonumber(cy)
    if not (cx and cy and scale and left and top) or scale <= 0 then return nil end
    return cx / scale - left, top - cy / scale
end

-- Steht die Maus über einem Abschnitt (Draw.HOVER_PX auf dem Bildschirm)? Dann Blizzards GameTooltip mit Route, Schritt
-- und Entfernung – nur, wenn kein anderer Tooltip offen ist (Blizzards Symbole, Marken). self.hoverArea (freiwillig):
-- fn() → false, wenn die Maus nicht über dem sichtbaren Teil der Karte steht. → der Abschnitt oder nil
function Painter:CheckHover()
    local tip = rawget(_G, "GameTooltip")
    local layer = self.layer
    if not (tip and layer and #self.segs > 0) or (self.hoverArea and not self.hoverArea()) then
        self:ReleaseTip()
        return nil
    end
    local x, y = Draw.CursorOn(layer)
    local seg = x and Draw.Nearest(self.segs, x, y, Draw.HOVER_PX / (self.scale or 1)) or nil
    if not seg then
        self:ReleaseTip()
        return nil
    end
    local mine = tip.IsOwned and tip:IsOwned(layer)
    if tip:IsShown() and not mine then return nil end       -- ein anderer Tooltip hat Vorrang
    if mine and self.hovered == seg then return seg end
    self.hovered = seg
    local to = seg.to
    tip:SetOwner(layer, "ANCHOR_CURSOR")
    local w, h = tonumber(self.w), tonumber(self.h)
    Draw.FillTip(tip, seg.name, to.labels, ns.L.ROUTE_TIP_SEG:format(Draw.MarkText(to)), self.map,
        w and w > 0 and to.x / w or nil, h and h > 0 and to.y / h or nil)
    tip:Show()
    return seg
end

-- Gezeigte Abschnitte (ohne Pfeile)
function Painter:Shown()
    local out = {}
    for i = 1, self.nLines do
        local line = self.lines[i]
        if line and line:IsShown() then out[#out + 1] = line end
    end
    return out
end

-- Gezeigte Marken (für Prüfungen und /ezmap status)
function Painter:Marks()
    local out = {}
    for i = 1, self.nMarks do out[#out + 1] = self.marks[i] end
    return out
end

function Painter:ArrowCount() return floor(self.nArrows / 2) end

---------------------------------------------------------------------------
-- Dem Ort folgen (nur bei offener Karte)
---------------------------------------------------------------------------

-- Dein Ort auf der Karte map → x, y oder nil (nicht dort, unbekannt bzw. gesperrt)
function Draw.PlayerOn(map)
    if map == nil then return nil end
    local where, x, y = Core.PlayerPosition(map)
    if where ~= map or not (x and y) then return nil end
    return x, y
end

-- Für die nächste Zeichnung merken, von wo die Linie beginnt (map nil: die Linie hängt nicht an deinem Ort)
function Painter:Follow(map, x, y)
    self.followMap, self.fx, self.fy = map, x, y
end

-- Hat sich dein Ort seit der Zeichnung merklich geändert (auch: erst jetzt bzw. nicht mehr auf der Karte)?
function Painter:Moved()
    local map = self.followMap
    if map == nil then return false end
    local x, y = Draw.PlayerOn(map)
    if not x or not self.fx then return (x ~= nil) ~= (self.fx ~= nil) end
    return math.abs(x - self.fx) > Draw.MOVED or math.abs(y - self.fy) > Draw.MOVED
end

-- Takt am Linien-Rahmen: läuft nur, solange er sichtbar ist (Karte offen); redraw zeichnet neu, wenn du dich bewegt
-- hast. Dazu alle Draw.HOVER_EVERY Sekunden der Tooltip über der Linie (Painter:CheckHover, Spieltest 19.11.2026).
function Painter:StartFollowing(redraw)
    local layer = self.layer
    if self.following or not (layer and layer.SetScript) then return end
    self.following = true
    local wait, hover = 0, 0
    local painter = self
    layer:SetScript("OnUpdate", function(_, elapsed)
        elapsed = tonumber(elapsed) or 0
        hover = hover + elapsed
        if hover >= Draw.HOVER_EVERY then
            hover = 0
            ns.Try("RouteHover", painter.CheckHover, painter)
        end
        wait = wait + elapsed
        if wait < Draw.FOLLOW then return end
        wait = 0
        if painter:Moved() then redraw() end
    end)
end
