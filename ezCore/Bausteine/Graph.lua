local _, ns = ...
local Core = ezCore

--[[
    Linien-Baustein Core.NewGraph (W-57, EC-25, VP-67) – zuerst für Preisverläufe (ezAuctions Seitenteil „Markt“ am
    Auktionsfenster, Entwurf 1 der Vollprüfung). Kein eigenes Fenster: der Graph ist ein Kind des übergebenen
    Rahmens. Blizzards Goldton (NORMAL_FONT_COLOR), keine fremde Bibliothek, nichts aus fremden Addons.

    Die Geometrie ist eine reine Funktion (ohne Spiel prüfbar):
      Core.Graph.Geometry(punkte, opts) → geo
        punkte: { { x = Zahl, y = Zahl oder nil (Lücke), high = Zahl oder nil (Band bis dahin), bar = Zahl oder nil
                    (Balken am Fuß, z. B. Menge) } … } in beliebiger Reihenfolge
        opts:   width, height (Bildpunkte, Pflicht), step (Abstand zweier Nachbarn in x, Standard 1 – ein größerer
                Abstand ist eine Lücke ohne Linie), barShare (Anteil der Höhe für die Balken, Standard 0,2),
                yMin, yMax, xMin, xMax (ohne Angabe aus den Daten), guides = { Wert … } (Hilfslinien, z. B. Median),
                dashed = { Wert … } (gestrichelt, z. B. Händlerpreis), dash = 6, gap = 4
        geo:    lines = { { x1, y1, x2, y2 } … }, band = { { x, y1, y2, w } … } (Rechteck ab x, Breite w),
                bars = { { x, w, h } … }, guides = { { y, value } … }, dashes = { { x1, y, x2 } … },
                dots = { { x, y, index } … }, slot (Breite je Schritt), plotBottom, xMin, xMax, yMin, yMax
      Core.Graph.Segment(x1, y1, x2, y2) → Mitte x, Mitte y, Länge, Winkel (für gedrehte Texturen)

    Zeichnen:
      local graph = Core.NewGraph(parent, { width = 220, height = 90, tooltip = function(punkt, i) return titel,
          zeile … end })
      graph:SetData(punkte, opts)  graph:Clear()  graph.frame  graph.mode ("line" oder "texture")
    Linien über frame:CreateLine; kennt Forever CreateLine nicht, nimmt der Ausweichweg gedrehte Texturen
    (Texture:SetRotation), ohne SetRotation eine Treppe aus waagrechten und senkrechten Strecken.
]]

local Graph = {}
Core.Graph = Graph

local floor, max, min, sqrt, atan2 = math.floor, math.max, math.min, math.sqrt, math.atan2 or math.atan

local function Range(values, lo, hi)
    for _, v in ipairs(values) do
        if v then
            lo = (lo == nil or v < lo) and v or lo
            hi = (hi == nil or v > hi) and v or hi
        end
    end
    return lo, hi
end

function Graph.Segment(x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    return (x1 + x2) / 2, (y1 + y2) / 2, sqrt(dx * dx + dy * dy), atan2(dy, dx)
end

function Graph.Geometry(points, opts)
    opts = opts or {}
    local width, height = Core.Num(opts.width) or 0, Core.Num(opts.height) or 0
    local list = {}
    for i, p in ipairs(type(points) == "table" and points or {}) do
        if type(p) == "table" and Core.Num(p.x) then list[#list + 1] = { p = p, i = i } end
    end
    table.sort(list, function(a, b) return a.p.x < b.p.x end)
    local geo = { lines = {}, band = {}, bars = {}, guides = {}, dashes = {}, dots = {} }
    if #list == 0 or width <= 0 or height <= 0 then return geo end
    local step = Core.Num(opts.step) or 1
    local xs, ys, bars = {}, {}, {}
    for _, e in ipairs(list) do
        xs[#xs + 1] = e.p.x
        ys[#ys + 1] = Core.Num(e.p.y)
        ys[#ys + 1] = Core.Num(e.p.high)
        bars[#bars + 1] = Core.Num(e.p.bar)
    end
    for _, v in ipairs(type(opts.guides) == "table" and opts.guides or {}) do ys[#ys + 1] = Core.Num(v) end
    for _, v in ipairs(type(opts.dashed) == "table" and opts.dashed or {}) do ys[#ys + 1] = Core.Num(v) end
    local xMin, xMax = Core.Num(opts.xMin) or xs[1], Core.Num(opts.xMax) or xs[#xs]
    local yMin, yMax = Range(ys, Core.Num(opts.yMin), Core.Num(opts.yMax))
    if not yMin then yMin, yMax = 0, 1 end
    if not opts.yMin and not opts.yMax then
        local pad = (yMax - yMin) * 0.05
        if pad == 0 then pad = max(1, math.abs(yMax) * 0.05) end
        yMin, yMax = yMin - pad, yMax + pad
    elseif yMax <= yMin then
        yMax = yMin + 1
    end
    local _, barMax = Range(bars)
    local plotBottom = (barMax and barMax > 0) and floor(height * (Core.Num(opts.barShare) or 0.2) + 0.5) or 0
    local slots = max(1, (xMax - xMin) / step)
    local slot = (xMax > xMin) and (width / (slots + 1)) or width
    local function X(x) if xMax <= xMin then return width / 2 end return slot / 2 + (x - xMin) / step * slot end
    local function Y(v) return plotBottom + (v - yMin) / (yMax - yMin) * (height - plotBottom) end
    geo.slot, geo.plotBottom, geo.xMin, geo.xMax, geo.yMin, geo.yMax = slot, plotBottom, xMin, xMax, yMin, yMax
    local prev
    for _, e in ipairs(list) do
        local p = e.p
        local x, y = X(p.x), Core.Num(p.y)
        local w = slot * 0.6
        if y then
            local py = Y(y)
            geo.dots[#geo.dots + 1] = { x, py, e.i }
            local high = Core.Num(p.high)
            if high and high > y then geo.band[#geo.band + 1] = { x - w / 2, py, Y(high), w } end
            if prev and p.x - prev.x <= step + 1e-9 then
                geo.lines[#geo.lines + 1] = { X(prev.x), Y(prev.y), x, py }
            end
            prev = { x = p.x, y = y }
        else
            prev = nil   -- Lücke: fehlender Tag
        end
        local bar = Core.Num(p.bar)
        if bar and bar > 0 and barMax and barMax > 0 then
            geo.bars[#geo.bars + 1] = { x - w / 2, w, max(1, bar / barMax * (plotBottom - 2)) }
        end
    end
    for _, v in ipairs(type(opts.guides) == "table" and opts.guides or {}) do
        if Core.Num(v) then geo.guides[#geo.guides + 1] = { Y(v), v } end
    end
    local dash, gap = Core.Num(opts.dash) or 6, Core.Num(opts.gap) or 4
    for _, v in ipairs(type(opts.dashed) == "table" and opts.dashed or {}) do
        if Core.Num(v) then
            local y, x = Y(v), 0
            while x < width do
                geo.dashes[#geo.dashes + 1] = { x, y, min(x + dash, width) }
                x = x + dash + gap
            end
        end
    end
    return geo
end

---------------------------------------------------------------------------
-- Zeichnen
---------------------------------------------------------------------------

local function Gold()
    local c = rawget(_G, "NORMAL_FONT_COLOR")
    if type(c) == "table" and c.r then return c.r, c.g, c.b end
    return 1, 0.82, 0
end

local Methods = {}
Methods.__index = Methods

local function Take(self, kind)
    local pool = self.pools[kind]
    pool.used = pool.used + 1
    local obj = pool[pool.used]
    if not obj then
        if kind == "line" then
            obj = self.frame:CreateLine(nil, "ARTWORK")
        elseif kind == "hit" then
            obj = CreateFrame("Frame", nil, self.frame)
            obj:EnableMouse(true)
            obj:SetScript("OnEnter", function(hit) self:ShowTip(hit) end)
            obj:SetScript("OnLeave", function() GameTooltip:Hide() end)
        else
            obj = self.frame:CreateTexture(nil, kind == "band" and "BACKGROUND" or "ARTWORK")
        end
        pool[pool.used] = obj
    end
    obj:Show()
    return obj
end

local function Rect(self, kind, x, y, w, h, r, g, b, a)
    local t = Take(self, kind)
    t:ClearAllPoints()
    t:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", x, y)
    t:SetSize(max(1, w), max(1, h))
    t:SetColorTexture(r, g, b, a)
    return t
end

-- Eine Strecke: CreateLine, sonst gedrehte Textur, sonst Treppe.
local function Segment(self, x1, y1, x2, y2, thick, r, g, b, a)
    if self.mode == "line" then
        local line = Take(self, "line")
        line:SetThickness(thick)
        line:SetColorTexture(r, g, b, a)
        line:SetStartPoint("BOTTOMLEFT", self.frame, x1, y1)
        line:SetEndPoint("BOTTOMLEFT", self.frame, x2, y2)
        return
    end
    local t = Take(self, "seg")
    if t.SetRotation then
        local cx, cy, len, angle = Graph.Segment(x1, y1, x2, y2)
        t:ClearAllPoints()
        t:SetPoint("CENTER", self.frame, "BOTTOMLEFT", cx, cy)
        t:SetSize(max(1, len), thick)
        t:SetColorTexture(r, g, b, a)
        t:SetRotation(angle)
    else
        t:Hide()
        self.pools.seg.used = self.pools.seg.used - 1
        Rect(self, "seg", min(x1, x2), y1 - thick / 2, math.abs(x2 - x1), thick, r, g, b, a)
        Rect(self, "seg", x2 - thick / 2, min(y1, y2), thick, math.abs(y2 - y1), r, g, b, a)
    end
end

function Methods:Clear()
    for _, pool in pairs(self.pools) do
        for i = 1, pool.used do pool[i]:Hide() end
        pool.used = 0
    end
    self.points, self.geo = nil, nil
end

function Methods:ShowTip(hit)
    local fn, p = self.opts.tooltip, hit.ezPoint
    if type(fn) ~= "function" or not p then return end
    local ok, title, a, b, c, d, e = pcall(fn, p, hit.ezIndex)
    if not ok then return Core.Error(self.opts.owner or Core.name, title, "Graph tooltip") end
    if not title then return end
    GameTooltip:SetOwner(hit, "ANCHOR_TOP")
    Core.TipLine(GameTooltip, title, "highlight")
    for _, line in ipairs({ a, b, c, d, e }) do GameTooltip:AddLine(line, nil, nil, nil, true) end
    GameTooltip:Show()
end

function Methods:SetData(points, opts)
    self:Clear()
    opts = opts or {}
    local width = Core.Num(opts.width) or self.opts.width or (self.frame:GetWidth() or 0)
    local height = Core.Num(opts.height) or self.opts.height or (self.frame:GetHeight() or 0)
    local merged = {}
    for k, v in pairs(self.opts) do merged[k] = v end
    for k, v in pairs(opts) do merged[k] = v end
    merged.width, merged.height = width, height
    local geo = Graph.Geometry(points, merged)
    local r, g, b = Gold()
    for _, rect in ipairs(geo.band) do Rect(self, "band", rect[1], rect[2], rect[4], rect[3] - rect[2], r, g, b, 0.18) end
    for _, bar in ipairs(geo.bars) do Rect(self, "bar", bar[1], 0, bar[2], bar[3], 0.6, 0.6, 0.6, 0.45) end
    for _, guide in ipairs(geo.guides) do Rect(self, "guide", 0, guide[1], width, 1, 1, 1, 1, 0.35) end
    for _, d in ipairs(geo.dashes) do Rect(self, "guide", d[1], d[2], d[3] - d[1], 1, 0.7, 0.7, 0.7, 0.7) end
    for _, l in ipairs(geo.lines) do Segment(self, l[1], l[2], l[3], l[4], 2, r, g, b, 1) end
    for _, dot in ipairs(geo.dots) do
        Rect(self, "dot", dot[1] - 2, dot[2] - 2, 4, 4, r, g, b, 1)
        local hit = Take(self, "hit")
        hit:ClearAllPoints()
        hit:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", dot[1] - geo.slot / 2, 0)
        hit:SetSize(max(4, geo.slot), max(1, height))
        hit.ezPoint, hit.ezIndex = points[dot[3]], dot[3]
    end
    self.points, self.geo = points, geo
    return geo
end

-- parent: Rahmen, an dem der Graph hängt (Pflicht); opts: width, height, tooltip, owner, noLines (Ausweichweg
-- erzwingen, für Prüfungen) und die Vorgaben für Geometry.
function Core.NewGraph(parent, opts)
    assert(type(parent) == "table", "Core.NewGraph(parent, opts)")
    opts = opts or {}
    local frame = CreateFrame("Frame", nil, parent)
    if opts.width and opts.height then frame:SetSize(opts.width, opts.height) end
    local graph = setmetatable({ frame = frame, opts = opts, pools = {} }, Methods)
    for _, kind in ipairs({ "line", "seg", "band", "bar", "guide", "dot", "hit" }) do graph.pools[kind] = { used = 0 } end
    graph.mode = (not opts.noLines and type(frame.CreateLine) == "function") and "line" or "texture"
    return graph
end
