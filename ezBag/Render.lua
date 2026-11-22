local _, ns = ...
local L = ns.L

--[[
    Gemeinsame Darstellung der Gruppen für Tasche (Layout.lua), Bank (Bank.lua)
    und das ezBag-Fenster (Window.lua) als Fließ-Layout:

    - Alle Plätze liegen in Blizzards Raster (gleiche Spaltenzahl, Größe, Abstände).
      Die Gruppen folgen ohne Lücke aufeinander und füllen jede Reihe ganz.
    - Rahmen laufen in den Abständen zwischen den Plätzen, darum bleibt die
      Tasche so breit wie das Original. Eine Gruppe, die in einer Reihe beginnt
      und in einer späteren endet, bekommt einen Rahmen mit 6 oder 8 Ecken.
    - Der Titel einer Gruppe steht in einem schmalen Band über der Reihe, in der
      er ganz Platz hat. Reicht der Platz nirgends, wird er gekürzt.
    - Plätze einer Gruppe hängen zusammen: Ein umgebrochener Rest liegt direkt unter
      seiner ersten Reihe; ein Titelband daneben schafft freien Platz darunter.
    - Zugeklappte und leere Gruppen werden zu Schildern, genau so breit wie ihr
      Text. Sie stehen im freien Rest der letzten Reihe oder darunter.
    - Auf Wunsch fasst jede Gruppe gleiche Gegenstände zu einem Platz zusammen
      (BetterBags „Compact“): der Platz des größten Stapels zeigt die Gesamtzahl,
      die übrigen werden versteckt wie in zugeklappten Gruppen (g.hidden).
    - Kein eigener Hintergrund: Es bleibt der originale von Tasche bzw. Bank.
]]

local Render = {}
ns.Render = Render

local TITLE_H = 14        -- Titelband über einer Reihe
local CHIP_H = 16         -- Höhe eines Schilds (zugeklappte/leere Gruppe)
local CHIP_GAP = 3
local ICON = 10
local LABEL_EXTRA = ICON + 8
Render.TITLE_H = TITLE_H

local BORDER = { 0.55, 0.46, 0.30, 0.95 }    -- Bronze wie der Taschenrahmen
local TITLE_TINT = { 1, 0.82, 0, 0.08 }
local CHIP_FILL = { 0, 0, 0, 0.35 }

---------------------------------------------------------------------------
-- Text messen
---------------------------------------------------------------------------

local measure

function Render.TextWidth(text)
    if not measure then
        -- Unsichtbar statt versteckt, damit die Breite sicher gemessen wird.
        measure = UIParent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        measure:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -2000, 2000)
        measure:SetAlpha(0)
    end
    measure:SetText(text)
    if measure.GetUnboundedStringWidth then return measure:GetUnboundedStringWidth() end
    return measure:GetStringWidth()
end

function Render.HeaderText(group)
    return group.label .. " " .. ezCore.Grey("(" .. group.count .. ")")
end

---------------------------------------------------------------------------
-- Gruppen bauen und sortieren
---------------------------------------------------------------------------

function Render.NewGroup(groups, byKey, key, groupKey)
    local group = {
        key = key, groupKey = groupKey, rank = ns.Groups.Rank(groupKey),
        label = ns.Groups.Label(groupKey), entries = {}, copper = 0,
    }
    byKey[groupKey] = group
    groups[#groups + 1] = group
    return group
end

-- Eigene Gruppen auch ohne Gegenstände zeigen, damit man etwas hineinziehen kann.
function Render.AddEmptyCustomGroups(groups, byKey)
    for id in pairs(ns.db.custom) do
        local groupKey = "custom:" .. id
        if not byKey[groupKey] then Render.NewGroup(groups, byKey, groupKey, groupKey) end
    end
end

-- Art eines Gegenstands (Klasse/Unterklasse) für "ähnliche liegen zusammen".
function Render.TypeOf(itemID)
    if not itemID then return 0 end
    local classID, subClassID = ezCore.ItemClass(itemID)   -- V-177: eine Stelle in ezCore
    return (classID or 99) * 1000 + (subClassID or 0)
end

-- Eingebaute Sortierungen. Weitere liefert ns.Knowledge (Stufe, Beruf, Wert ...).
local BUILTIN_SORTS = { "type", "quality", "name", "count" }

function Render.SortModes()
    local list, seen = {}, {}
    for _, key in ipairs(BUILTIN_SORTS) do
        list[#list + 1] = { key = key, label = L["SORT_" .. key] }
        seen[key] = true
    end
    local K = ns.Knowledge
    if K and type(K.SortModes) == "table" then
        for _, mode in ipairs(K.SortModes) do
            if mode.key and not seen[mode.key] then
                list[#list + 1] = { key = mode.key, label = mode.label or mode.key }
                seen[mode.key] = true
            end
        end
    end
    return list
end

local function KnowledgeValue(entry, mode)
    local K = ns.Knowledge
    if not (K and K.Get and K.SortValue and entry.itemID) then return nil end
    local ok, facts = pcall(K.Get, entry.link or entry.itemID)
    if not ok or not facts then return nil end
    local ok2, value = pcall(K.SortValue, facts, mode)
    if ok2 then return value end
end

local function Fallback(a, b)
    if a.quality ~= b.quality then return (a.quality or 0) > (b.quality or 0) end
    if a.name ~= b.name then return (a.name or "") < (b.name or "") end
    if a.itemID ~= b.itemID then return (a.itemID or 0) < (b.itemID or 0) end
    if a.count ~= b.count then return (a.count or 0) > (b.count or 0) end
    return (a.order or 0) < (b.order or 0)
end

local function Comparator(mode)
    return function(a, b)
        if not (a.itemID and b.itemID) then
            if a.itemID or b.itemID then return a.itemID ~= nil end
            return (a.order or 0) < (b.order or 0)
        end
        if mode == "type" then
            if a.sortType ~= b.sortType then return (a.sortType or 0) < (b.sortType or 0) end
        elseif mode == "name" then
            if a.name ~= b.name then return (a.name or "") < (b.name or "") end
        elseif mode == "count" then
            if a.count ~= b.count then return (a.count or 0) > (b.count or 0) end
        elseif mode ~= "quality" then
            local va, vb = KnowledgeValue(a, mode), KnowledgeValue(b, mode)
            if va ~= vb then
                if va == nil then return false end
                if vb == nil then return true end
                if type(va) == type(vb) then return va < vb end
                return tostring(va) < tostring(vb)
            end
        end
        return Fallback(a, b)
    end
end

local comparators = {}

function Render.SortEntries(entries, mode)
    mode = mode or "type"
    for _, e in ipairs(entries) do
        if e.itemID and not e.sortType then e.sortType = Render.TypeOf(e.itemID) end
    end
    local cmp = comparators[mode]
    if not cmp then
        cmp = Comparator(mode)
        comparators[mode] = cmp
    end
    table.sort(entries, cmp)
end

function Render.SortGroups(groups)
    table.sort(groups, function(a, b) return a.rank < b.rank end)
end

---------------------------------------------------------------------------
-- Suche und Hervorheben
---------------------------------------------------------------------------

-- Passt ein Eintrag zur Suche? Name oder (falls vorhanden) Wissen über den Gegenstand.
function Render.Matches(entry, search)
    if not search or search == "" then return true end
    if not entry.itemID then return false end
    if entry.name and entry.name:lower():find(search, 1, true) then return true end
    local K = ns.Knowledge
    if K and K.Get and K.Match then
        local ok, facts = pcall(K.Get, entry.link or entry.itemID)
        if ok and facts then
            local ok2, hit = pcall(K.Match, facts, search)
            return ok2 and hit == true
        end
    end
    return false
end

-- Gehören zwei Gegenstände zusammen (gleich, Rezept ↔ Material, Rezept ↔ Ergebnis)?
function Render.Related(a, b)
    if not (a.itemID and b.itemID) then return false end
    if a.itemID == b.itemID then return true end
    local K = ns.Knowledge
    if K and K.Get and K.Related then
        local okA, fa = pcall(K.Get, a.link or a.itemID)
        local okB, fb = pcall(K.Get, b.link or b.itemID)
        if okA and okB and fa and fb then
            local ok, related = pcall(K.Related, fa, fb)
            return ok and related == true
        end
    end
    return false
end

---------------------------------------------------------------------------
-- Fließ-Layout berechnen
---------------------------------------------------------------------------

-- Spalten [a, b] einer Gruppe in Reihe r (0-basiert).
local function SpanOf(g, r, cols)
    local r0, r1 = math.floor(g.first / cols), math.floor(g.last / cols)
    local a = (r == r0) and (g.first % cols) or 0
    local b = (r == r1) and (g.last % cols) or (cols - 1)
    return a, b
end

local function PlaceLabel(g, cols, stepX, spX)
    local full, short = Render.HeaderText(g), g.label
    local texts = { full, short, g.shortLabel or short }
    local needs = {}
    for i, text in ipairs(texts) do needs[i] = Render.TextWidth(text) + LABEL_EXTRA end
    local r0, r1 = math.floor(g.first / cols), math.floor(g.last / cols)
    for pass = 1, #texts do
        for r = r0, r1 do
            local a, b = SpanOf(g, r, cols)
            if (b - a + 1) * stepX - spX >= needs[pass] then
                g.labelRow, g.labelA, g.labelB, g.labelText = r, a, b, texts[pass]
                return
            end
        end
    end
    -- Nirgends genug Platz: in die Reihe mit dem meisten Platz, gekürzt.
    local bestR, bestW = r0, -1
    for r = r0, r1 do
        local a, b = SpanOf(g, r, cols)
        if b - a > bestW then bestR, bestW = r, b - a end
    end
    -- Der kürzeste Text ohne Zahl: so bleibt vom Namen am meisten lesbar; Name und Zahl nennt der Tooltip.
    local a, b = SpanOf(g, bestR, cols)
    g.labelRow, g.labelA, g.labelB, g.labelText = bestR, a, b, texts[#texts]
end
Render.PlaceLabel = PlaceLabel

-- Merkmal zum Unterteilen (aus ns.Knowledge.Facets) suchen.
function Render.Facet(key)
    local K = ns.Knowledge
    if not (key and K and type(K.Facets) == "table") then return nil end
    for _, facet in ipairs(K.Facets) do
        if facet.key == key then return facet end
    end
end

-- Titel einer Untergruppe: „Gruppe: Teil“ bzw. „Gruppe › Teil › Teil“. Heißt der Teil wie die Stufe darüber
-- (Kategorie „Behälter“, Unterkategorie „Behälter“), steht der Name nur einmal da.
-- parentPart: der Teil, den die Stufe darüber angehängt hat (nil bei der obersten Gruppe).
function Render.SubLabel(parentLabel, parentShort, parentPart, part, nested)
    if part == (parentPart or parentLabel) then return parentLabel, parentShort or parentLabel end
    if nested then return parentLabel .. " › " .. part, (parentShort or parentLabel) .. " › " .. part end
    return parentLabel .. ": " .. part, part
end

-- Eine Gruppe nach einem Merkmal aufteilen. root ist die oberste Gruppe (Menü, Ziehen, Sortierung).
local function Split(g, facet, root)
    local K = ns.Knowledge
    local buckets, order = {}, {}
    for _, entry in ipairs(g.entries) do
        local subKey, subLabel, sortKey
        if entry.itemID then
            local ok, facts = pcall(K.Get, entry.link or entry.itemID)
            if ok and facts then
                local ok2, k, label, order2 = pcall(facet.value, facts)
                if ok2 and k ~= nil then
                    subKey, subLabel = tostring(k), label or tostring(k)
                    sortKey = order2 ~= nil and tostring(order2) or subLabel
                end
            end
        end
        subKey = subKey or "~"
        local b = buckets[subKey]
        if not b then
            local part = subLabel or L.TAGS_other
            local nested = g ~= root
            local label, shortLabel = Render.SubLabel(g.label, g.shortLabel, g.part, part, nested)
            b = { key = g.key, groupKey = g.groupKey .. "|" .. subKey, parentKey = root.groupKey,
                label = label, shortLabel = shortLabel, part = part,
                entries = {}, copper = 0, rank = g.rank, subKey = subKey, sortKey = sortKey or "~" }
            buckets[subKey] = b
            order[#order + 1] = b
        end
        b.entries[#b.entries + 1] = entry
    end
    -- Ohne Merkmal ("~") ans Ende, sonst nach dem Sortierschlüssel des Merkmals.
    table.sort(order, function(a, b)
        if (a.subKey == "~") ~= (b.subKey == "~") then return b.subKey == "~" end
        if a.sortKey ~= b.sortKey then return a.sortKey < b.sortKey end
        return a.label < b.label
    end)
    return order
end

-- Gruppen mit "Unterteilen nach" in Untergruppen aufteilen (gleich nach der Elterngruppe),
-- auf Wunsch in zwei Stufen (z. B. Ausrüstung › Waffe › Schwert).
local function Expand(groups)
    local K = ns.Knowledge
    local out = {}
    for _, g in ipairs(groups) do
        local f1 = K and K.Get and Render.Facet(ns.Groups.Subdivide(g.groupKey, 1))
        if not f1 or type(f1.value) ~= "function" or #g.entries == 0 then
            out[#out + 1] = g
        else
            local f2 = Render.Facet(ns.Groups.Subdivide(g.groupKey, 2))
            if f2 and type(f2.value) ~= "function" then f2 = nil end
            for _, b in ipairs(Split(g, f1, g)) do
                if f2 and b.subKey ~= "~" then
                    for _, c in ipairs(Split(b, f2, g)) do out[#out + 1] = c end
                else
                    out[#out + 1] = b
                end
            end
        end
    end
    return out
end

-- Gleiche Gegenstände (gleicher Link) einer Gruppe zu einem Platz zusammenfassen:
-- der größte Stapel behält seinen Platz und bekommt stackTotal, die übrigen wandern nach g.hidden. Der größte, weil
-- unter dem Platz Blizzards Knopf dieses Stapels liegt: Blizzards Anzahl-Fenster (Umschalt+Klick) reicht nur bis zu
-- dessen Größe (Spielbefund vom 21.11.2026: „ich habe 24 wollstoff mit shift und reechtsklick kann ich davon nur 4
-- nehmen anstatt max 20“; vorher der erste in Taschenreihenfolge). Bei gleicher Größe bleibt der erste.
-- entry.compactKey (falls gesetzt) ersetzt den Link als Schlüssel – das ezBag-Fenster fasst mit „Fundort zeigen“
-- nur Stapel am selben Ort zusammen (Gegenprüfung W-1811-ezBag), damit Symbol und Zeilen „Liegt:“ stimmen.
function Render.Compact(g)
    local seen, keep, hidden, at = {}, {}, {}, {}
    for _, entry in ipairs(g.entries) do
        local key = entry.itemID and (entry.compactKey or entry.link or entry.itemID)
        local rep = key and seen[key]
        if rep then
            local total = (rep.stackTotal or rep.count or 1) + (entry.count or 1)
            local merged = rep.merged or {}
            if (entry.count or 1) > (rep.count or 1) then
                -- der größere Stapel übernimmt den Platz, der bisherige wird einer der zusammengefassten
                rep.stackTotal, rep.merged = nil, nil
                merged[#merged + 1] = rep
                hidden[#hidden + 1] = rep
                entry.stackTotal, entry.merged = total, merged
                keep[at[key]] = entry
                seen[key] = entry
            else
                merged[#merged + 1] = entry
                rep.stackTotal, rep.merged = total, merged
                hidden[#hidden + 1] = entry
            end
        else
            entry.stackTotal, entry.merged = nil, nil
            keep[#keep + 1] = entry
            if key then seen[key], at[key] = entry, #keep end
        end
    end
    g.entries, g.hidden = keep, hidden
end

-- Zusammenfassen an? (Einstellung; ein Bereich kann es mit opts.compact = false abschalten)
local function CompactOn(opts)
    if opts.compact ~= nil then return opts.compact == true end
    return ns.S and ns.S.compactStacks == true
end

--[[
    geom = { cols, w, h, spX, spY }
    opts = { viewKey = "bag"|"bank"|"window", searching = bool, compact = bool (sonst Einstellung) }
    Ergebnis: Positionen aller Gruppen, Titel und Schilder.
]]
function Render.Flow(groups, geom, opts)
    groups = Expand(groups)
    -- „/eb zuklappen“ gilt auch für Untergruppen, die erst hier entstehen (Groups.CollapseEverything).
    ns.Groups.ApplyPendingCollapse(opts.viewKey, groups)
    local compact = CompactOn(opts)
    local cols, w, h = math.max(1, geom.cols), geom.w, geom.h
    local spX, spY = geom.spX or geom.sp or 5, geom.spY or geom.sp or 5
    local stepX = w + spX
    local out = {
        groups = {}, chips = {}, cols = cols, w = w, h = h, spX = spX, spY = spY, stepX = stepX,
        width = cols * stepX, leftHalf = math.floor(spX / 2),
    }

    local pos = 0
    for _, g in ipairs(groups) do
        g.hidden = nil
        if compact then Render.Compact(g) end
        Render.SortEntries(g.entries, ns.Groups.SortMode(g.parentKey or g.groupKey))
        g.count = #g.entries
        g.collapsed = not opts.searching and ns.Groups.IsCollapsed(opts.viewKey, g.groupKey)
        g.compressed = g.key == "empty" and ns.S.compressEmpty and g.count > 1
        -- Zusammengefasstes „Frei“ zeigt den LETZTEN leeren Platz: Blizzard legt Eingelagertes, Herausgenommenes und
        -- Abgeteiltes in den ersten freien Platz. Zeigte die Kachel ihn, stünde dort bis zum nächsten Neuordnen (nicht,
        -- solange die Maus über dem Fenster steht) ein Gegenstand mit der Frei-Zahl (Spielbefund vom 21.11.2026:
        -- „beim ein und auslagern kommt es kurz zum anzeigefehler, der nach 3-5s erledigt ist“).
        if g.compressed then table.insert(g.entries, 1, table.remove(g.entries)) end
        g.visible = g.collapsed and 0 or (g.compressed and 1 or g.count)
        if g.visible == 0 then
            out.chips[#out.chips + 1] = g
        else
            if ns.Groups.NewRow(g.parentKey or g.groupKey) and pos % cols ~= 0 then pos = pos + cols - pos % cols end
            g.first, g.last = pos, pos + g.visible - 1
            pos = pos + g.visible
            out.groups[#out.groups + 1] = g
        end
    end

    local rows = math.ceil(pos / cols)
    out.rows = rows
    local band = {}
    for _, g in ipairs(out.groups) do
        PlaceLabel(g, cols, stepX, spX)
        band[g.labelRow] = true
        -- Umbruch, bei dem der Rest die Gruppe nicht berührt (z. B. letzter Platz ganz links in
        -- der nächsten Reihe): dieser Teil bekommt einen eigenen, kurzen Titel.
        g.extraLabels = nil
        local r0, r1 = math.floor(g.first / cols), math.floor(g.last / cols)
        if r1 == r0 + 1 and g.last % cols < g.first % cols then
            local r = (g.labelRow == r0) and r1 or r0
            local a, b = SpanOf(g, r, cols)
            g.extraLabels = { { row = r, a = a, b = b, text = g.shortLabel or g.label } }
            band[r] = true
        end
    end

    -- Reihen: Band (falls ein Titel darin steht) + Platzhöhe + halber Abstand.
    local topHalf = math.floor(spY / 2)
    local bottomHalf = spY - topHalf
    local B, cellTop = {}, {}
    local y = 0
    for r = 0, rows - 1 do
        B[r] = y
        cellTop[r] = y + (band[r] and TITLE_H or topHalf)
        y = cellTop[r] + h + bottomHalf
    end
    B[rows] = y
    out.B, out.cellTop, out.band, out.gridH = B, cellTop, band, y
    out.bottomHalf = bottomHalf

    -- Plätze einer Gruppe hängen zusammen: Ein umgebrochener Rest ohne eigenen Titel liegt
    -- direkt unter seiner vorigen Reihe, auch wenn rechts daneben eine Gruppe mit Titel
    -- beginnt. Der freie Streifen gehört dann unten in das Feld des Rests, nicht dazwischen.
    for _, g in ipairs(out.groups) do
        local r0, r1 = math.floor(g.first / cols), math.floor(g.last / cols)
        local titled = { [g.labelRow] = true }
        for _, x in ipairs(g.extraLabels or {}) do titled[x.row] = true end
        g.rowTop = {}
        for r = r0, r1 do
            g.rowTop[r] = (r > r0 and not titled[r]) and (B[r] + topHalf) or cellTop[r]
        end
    end

    -- Schilder: zuerst in den freien Rest der letzten Reihe, sonst darunter.
    local used = pos % cols
    local freeX = (rows > 0 and used > 0) and (used * stepX + out.leftHalf + 2) or nil
    local slotLines = {}
    if freeX then
        local top = cellTop[rows - 1]
        local n = math.floor((h + CHIP_GAP) / (CHIP_H + CHIP_GAP))
        for i = 1, n do slotLines[i] = { x = freeX, y = top + (i - 1) * (CHIP_H + CHIP_GAP), right = out.width - 1 } end
    end
    local lineIndex, below, belowY = 1, false, y + CHIP_GAP
    local cursorX = slotLines[1] and slotLines[1].x or 0
    local belowX = 0
    for _, g in ipairs(out.chips) do
        g.chipText = Render.HeaderText(g)
        g.chipW = math.min(out.width, math.ceil(Render.TextWidth(g.chipText) + LABEL_EXTRA + 2))
        local placed = false
        while not below and slotLines[lineIndex] do
            local line = slotLines[lineIndex]
            if cursorX + g.chipW <= line.right then
                g.chipX, g.chipY = cursorX, line.y
                cursorX = cursorX + g.chipW + CHIP_GAP
                placed = true
                break
            end
            lineIndex = lineIndex + 1
            cursorX = slotLines[lineIndex] and slotLines[lineIndex].x or 0
        end
        if not placed then
            below = true
            if belowX > 0 and belowX + g.chipW > out.width then
                belowX, belowY = 0, belowY + CHIP_H + CHIP_GAP
            end
            g.chipX, g.chipY = belowX, belowY
            belowX = belowX + g.chipW + CHIP_GAP
            out.belowUsed = true
        end
    end
    out.totalH = out.belowUsed and (belowY + CHIP_H) or y
    if rows == 0 and not out.belowUsed then out.totalH = 0 end
    return out
end

function Render.Signature(out, extra)
    local parts = { out.totalH, out.cols, extra or "" }
    for _, g in ipairs(out.groups) do
        parts[#parts + 1] = table.concat({ g.groupKey, g.label, g.first, g.last, g.labelRow, g.labelText,
            g.count, g.copper or 0 }, ":")
        for j = 1, g.count do
            local e = g.entries[j]
            parts[#parts + 1] = (e.sig or j) .. (e.stackTotal and ("x" .. e.stackTotal) or "")
        end
        parts[#parts + 1] = #(g.hidden or {})
    end
    for _, g in ipairs(out.chips) do
        parts[#parts + 1] = table.concat({ "c", g.groupKey, g.label, g.count, g.chipX, g.chipY }, ":")
        for j = 1, g.count do parts[#parts + 1] = g.entries[j].sig or j end
    end
    return table.concat(parts, ",")
end

---------------------------------------------------------------------------
-- Ziehen: Gruppe verschieben
---------------------------------------------------------------------------

local drag, lastDragStop = nil, 0
local ghost, marker

local function CursorIn(frame)
    local x, y = GetCursorPosition()
    local scale = frame:GetEffectiveScale()
    return x / scale, y / scale
end

--[[
    Ziel beim Verschieben: die ganze Gruppe zählt, nicht nur ihr schmaler Titel.
    Über die Position des Mauszeigers im Layout finden wir Reihe und Spalte und
    damit die Gruppe. Erste Hälfte ihrer Plätze = davor, zweite Hälfte = dahinter.
    Schilder (zugeklappt/leer) treffen wir direkt.
]]
local function DragTarget()
    local view = drag.view
    for _, chip in ipairs(view.chips) do
        if chip:IsShown() and chip.menuKey ~= drag.key and chip:IsMouseOver() then
            local x = CursorIn(chip)
            return { key = chip.menuKey, frame = chip, after = x > chip:GetLeft() + chip:GetWidth() / 2 }
        end
    end
    local area, out = view.area, view.out
    if not (area and out and area:IsShown() and area:GetLeft() and out.rows and out.rows > 0) then return nil end
    local x, y = CursorIn(area)
    local lx, ly = x - area:GetLeft(), area:GetTop() - y
    if lx < 0 or ly < 0 or lx > out.width or ly > out.gridH then return nil end
    local row
    for r = 0, out.rows - 1 do
        if ly >= out.B[r] and ly < out.B[r + 1] then
            row = r
            break
        end
    end
    if not row then return nil end
    local cell = row * out.cols + math.min(out.cols - 1, math.floor(lx / out.stepX))
    for _, g in ipairs(out.groups) do
        if cell >= g.first and cell <= g.last then
            local key = g.parentKey or g.groupKey
            if key == drag.key then return nil end
            return { key = key, group = g, after = (cell - g.first) >= (g.last - g.first + 1) / 2 }
        end
    end
    return nil
end

local function UpdateDrag()
    local x, y = CursorIn(UIParent)
    ghost:ClearAllPoints()
    ghost:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x + 14, y - 8)
    local target = DragTarget()
    marker:ClearAllPoints()
    if target and target.frame then
        local f, after = target.frame, target.after
        marker:SetPoint("TOP", f, after and "TOPRIGHT" or "TOPLEFT", after and 2 or -2, 2)
        marker:SetPoint("BOTTOM", f, after and "BOTTOMRIGHT" or "BOTTOMLEFT", after and 2 or -2, -2)
        marker:SetWidth(3)
        marker:Show()
    elseif target and target.group then
        -- Senkrechter Strich vor dem ersten bzw. hinter dem letzten Platz der Zielgruppe.
        local out, g, area = drag.view.out, target.group, drag.view.area
        local cell = target.after and g.last or g.first
        local r, c = math.floor(cell / out.cols), cell % out.cols
        local lx = (target.after and (c + 1) or c) * out.stepX
        marker:SetPoint("TOPLEFT", area, "TOPLEFT", lx - 2, -out.B[r])
        marker:SetSize(3, out.B[r + 1] - out.B[r])
        marker:Show()
    else
        marker:Hide()
    end
end

local function DragVisuals()
    if ghost then return end
    ghost = CreateFrame("Frame", nil, UIParent)
    ghost:SetFrameStrata("TOOLTIP")
    ghost:SetSize(140, 18)
    local bg = ghost:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.85)
    ghost.text = ghost:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    ghost.text:SetPoint("LEFT", 6, 0)
    ghost:SetScript("OnUpdate", function() if drag then UpdateDrag() end end)
    ghost:Hide()

    marker = CreateFrame("Frame", nil, UIParent)
    marker:SetFrameStrata("TOOLTIP")
    local bar = marker:CreateTexture(nil, "OVERLAY")
    bar:SetAllPoints()
    bar:SetColorTexture(1, 0.82, 0, 0.95)
    marker:Hide()
end

local function StartDrag(self)
    if not self.menuKey or CursorHasItem() then return end
    DragVisuals()
    drag = { key = self.menuKey, view = self.view }
    ghost.text:SetText(self.title or "")
    ghost:SetWidth(math.max(80, ghost.text:GetStringWidth() + 14))
    ghost:Show()
    UpdateDrag()
end

local function StopDrag()
    if not drag then return end
    local target = DragTarget()
    local key = drag.key
    drag = nil
    lastDragStop = GetTime()
    ghost:Hide()
    marker:Hide()
    if target and target.key then ns.Groups.Move(key, target.key, target.after) end
end

function Render.CancelDrag()
    if drag then StopDrag() end
end

function Render.IsBusy()
    return drag ~= nil
end

---------------------------------------------------------------------------
-- Gemeinsames Gerüst der Ansichten (V-052): Tasche, Bank, Gildenbank und Fenster ordnen aufgeschoben neu und
-- merken sich, was sie an Blizzards Fenstern umgestellt haben. Eine Fassung hier statt je einer pro Datei.
---------------------------------------------------------------------------

Render.CHECK_INTERVAL = 0.2    -- wie oft eine aufgeschobene Neuordnung geprüft wird

-- Darf jetzt neu geordnet werden? Nicht, solange eine Gruppe gezogen wird, etwas am Mauszeiger hängt, Blizzards
-- Stapel-Teiler offen ist oder die Maus über dem Fenster steht (sonst springt beim Benutzen etwas weg) – außer in der
-- zusammengefassten „Frei“-Kachel liegt inzwischen etwas (view:FreeTileTaken()).
-- busy: weiterer Grund der Ansicht (Breite wird gezogen, Umlagern läuft). view: die Ansicht (optional).
function Render.CanRelayout(frame, busy, view)
    if Render.IsBusy() or busy or CursorHasItem() then return false end
    if StackSplitFrame and StackSplitFrame:IsShown() then return false end
    if frame and frame:IsMouseOver(10, -10, -10, 10) and not (view and view:FreeTileTaken()) then return false end
    return true
end

-- OnUpdate-Skript für den Halter einer Ansicht: solange isDirty() gilt, alle interval Sekunden run(self).
function Render.DeferredUpdate(isDirty, run, interval)
    interval = interval or Render.CHECK_INTERVAL
    return function(self, elapsed)
        if not isDirty() then return end
        self.elapsed = (self.elapsed or 0) + elapsed
        if self.elapsed < interval then return end
        self.elapsed = 0
        run(self)
    end
end

-- Merker für Anker, Größe und Deckkraft von Blizzards Teilen, die eine Ansicht umstellt (nur lesen und über
-- Blizzards eigene Setter zurücksetzen, nichts in ihre Tabellen). opts.scale = true merkt auch die Skalierung,
-- opts.widthOf = "EditBox" setzt die Breite nur bei dieser Art zurück (sonst bei allen).
--   store.Save(region), store.Restore(), store.saved (region → Merker)
function Render.NewRegionStore(opts)
    opts = opts or {}
    local saved = {}
    local store = { saved = saved }
    function store.Save(region)
        if not region or saved[region] then return end
        local points = {}
        for i = 1, region:GetNumPoints() do points[i] = { region:GetPoint(i) } end
        saved[region] = { points = points, w = region:GetWidth(), h = region:GetHeight(), alpha = region:GetAlpha(),
            scale = opts.scale and region.GetScale and region:GetScale() or nil }
    end
    function store.Restore()
        for region, s in pairs(saved) do
            region:ClearAllPoints()
            for _, p in ipairs(s.points) do region:SetPoint(unpack(p)) end
            region:SetAlpha(s.alpha or 1)
            if s.scale and region.SetScale then region:SetScale(s.scale) end
            if s.w and s.w > 0 and (not opts.widthOf or region:GetObjectType() == opts.widthOf) then
                region:SetWidth(s.w)
            end
        end
        wipe(saved)
    end
    return store
end

---------------------------------------------------------------------------
-- Titel und Schilder (Klick, Ziehen, Rechtsklick, Gegenstand ablegen)
---------------------------------------------------------------------------

local function OnHeaderClick(self, mouse)
    if GetTime() - lastDragStop < 0.25 then return end
    if CursorHasItem() then
        ns.Groups.DropCursorItem(self.menuKey)
        return
    end
    if mouse == "RightButton" then
        ns.Groups.OpenHeaderMenu(self, self.menuKey, self.view.viewKey, self.groupKey, self.view:AllKeys())
        return
    end
    if IsShiftKeyDown() then
        -- Shift+Klick: alle Gruppen dieser Ansicht so wie die angeklickte umschalten.
        ns.Groups.SetAllCollapsed(self.view.viewKey, self.view:AllKeys(),
            not ns.Groups.IsCollapsed(self.view.viewKey, self.groupKey))
    else
        ns.Groups.ToggleCollapsed(self.view.viewKey, self.groupKey)
    end
    ezCore.PlaySound("IG_MAINMENU_OPTION_CHECKBOX_ON")
end

local function OnHeaderEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    -- Immer der volle Name, auch wenn der Titel am Platz gekürzt ist („Tasch…“).
    GameTooltip:SetText(self.title or "", ns.TipRGB("normal"))
    if self.count then GameTooltip:AddLine(ns.CountWord("SLOT", self.count), ns.TipRGB("highlight")) end
    GameTooltip:AddLine(self.collapsed and L.HEADER_EXPAND or L.HEADER_TOGGLE, ns.TipRGB("highlight"))
    GameTooltip:AddLine(L.HEADER_TOGGLE_ALL, ns.TipRGB("highlight"))
    GameTooltip:AddLine(L.HEADER_DRAG, ns.TipRGB("highlight"))
    GameTooltip:AddLine(L.HEADER_MENU, ns.TipRGB("highlight"))
    if self.key == "junk" and (self.copper or 0) > 0 then
        GameTooltip:AddLine(L.HEADER_JUNK_VALUE:format(ns.CoinText(self.copper)), ns.TipRGB("highlight"))
    end
    GameTooltip:AddLine(L.HEADER_ASSIGN_HINT, ns.TipRGB("hint"))
    GameTooltip:Show()
end

local function SetupClicks(b, view)
    b.view = view
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnClick", OnHeaderClick)
    b:SetScript("OnEnter", OnHeaderEnter)
    b:SetScript("OnLeave", GameTooltip_Hide)
    b:SetScript("OnDragStart", StartDrag)
    b:SetScript("OnDragStop", StopDrag)
    b:SetScript("OnReceiveDrag", function(self) ns.Groups.DropCursorItem(self.menuKey) end)
end

local function LabelParts(b)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(ICON, ICON)
    b.icon:SetPoint("LEFT", 2, 0)
    b.label = b:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    b.label:SetPoint("LEFT", b.icon, "RIGHT", 3, 0)
    b.label:SetJustifyH("LEFT")
    b.label:SetWordWrap(false)
    local glow = b:CreateTexture(nil, "HIGHLIGHT")
    glow:SetAllPoints()
    glow:SetColorTexture(1, 0.82, 0, 0.10)
end

-- groupKey: diese (Unter-)Gruppe (zum Zuklappen); menuKey: die eigentliche Gruppe
-- (Menü, Verschieben, Gegenstand ablegen).
local function SetHeaderData(b, g)
    b.key, b.groupKey, b.title, b.copper, b.count, b.collapsed = g.key, g.groupKey, g.label, g.copper, g.count, g.collapsed
    b.menuKey = g.parentKey or g.groupKey
end

---------------------------------------------------------------------------
-- Zeichnen
---------------------------------------------------------------------------

local function LineThickness(frame)
    if PixelUtil and PixelUtil.GetNearestPixelSize then
        return PixelUtil.GetNearestPixelSize(1, frame:GetEffectiveScale(), 1)
    end
    return 1
end

local function Tex(frame, list, i, layer, color)
    local t = list[i]
    if not t then
        t = frame:CreateTexture(nil, layer)
        t:SetColorTexture(color[1], color[2], color[3], color[4])
        list[i] = t
    end
    return t
end

local function Rect(frame, t, x, y, w, h)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -y)
    t:SetSize(math.max(w, 0.01), math.max(h, 0.01))
    t:Show()
end

-- [a0, a1) ohne [b0, b1) an list anhängen.
local function Minus(a0, a1, b0, b1, list)
    local e = math.min(a1, b0)
    if a0 < e then list[#list + 1] = { a0, e } end
    local s = math.max(a0, b1)
    if s < a1 then list[#list + 1] = { s, a1 } end
end

local function NewBox(view)
    local box = CreateFrame("Frame", nil, view.parent)
    box.view = view
    box.extra = {}
    box.lines = {}
    box.band = box:CreateTexture(nil, "BACKGROUND")
    box.band:SetColorTexture(TITLE_TINT[1], TITLE_TINT[2], TITLE_TINT[3], TITLE_TINT[4])
    local header = CreateFrame("Button", nil, box)
    header:SetHeight(TITLE_H - 2)
    LabelParts(header)
    SetupClicks(header, view)
    box.header = header
    return box
end

-- Titelband und Titel über den Spalten la..lb der Reihe lr.
local function DrawLabel(box, header, band, g, la, lb, lr, text, out, t)
    local stepX, B = out.stepX, out.B
    local bandW = (lb + 1 - la) * stepX
    Rect(box, band, la * stepX + t, B[lr] + t, bandW - 2 * t, TITLE_H - t)
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", box, "TOPLEFT", la * stepX + 2, -(B[lr] + 1))
    header:SetWidth(math.max(bandW - 4, 8))
    SetHeaderData(header, g)
    -- Schmale Gruppen (z. B. 1 Platz): ohne Symbol und mit kleinerer Schrift, damit der Titel lesbar bleibt.
    local avail = bandW - 4
    local narrow = Render.TextWidth(text) + LABEL_EXTRA > avail
    header.icon:SetTexture("Interface\\Buttons\\UI-MinusButton-Up")
    header.icon:SetShown(not narrow)
    header.label:ClearAllPoints()
    if narrow then
        header.label:SetPoint("LEFT", header, "LEFT", 1, 0)
        header.label:SetFontObject(_G.GameFontNormalTiny2 or _G.GameFontNormalTiny or GameFontNormalSmall)
        header.label:SetWidth(math.max(avail - 2, 4))
    else
        header.label:SetPoint("LEFT", header.icon, "RIGHT", 3, 0)
        header.label:SetFontObject(GameFontNormalSmall)
        header.label:SetWidth(math.max(avail - ICON - 6, 4))
    end
    header.label:SetText(text)
    header:Show()
end

-- Rahmen einer Gruppe: Kanten aus den Reihen-Abschnitten, gleiche Spalten zusammengefasst.
local function DrawGroup(box, g, out)
    local cols, B, stepX = out.cols, out.B, out.stepX
    local t = LineThickness(box)
    local W, H = out.width, out.gridH
    local r0, r1 = math.floor(g.first / cols), math.floor(g.last / cols)
    local spans = {}
    for r = r0, r1 do
        local a, b = SpanOf(g, r, cols)
        spans[#spans + 1] = { r = r, a = a, b = b + 1 }
    end

    local n = 0
    local function HLine(x0, x1, y)
        n = n + 1
        local yy = (y >= H - 0.01) and (y - t) or y
        Rect(box, Tex(box, box.lines, n, "BORDER", BORDER), x0 * stepX, yy, (x1 - x0) * stepX, t)
    end

    local verticals = {}
    for k, s in ipairs(spans) do
        local prev, nxt = spans[k - 1], spans[k + 1]
        local list = {}
        if prev then Minus(s.a, s.b, prev.a, prev.b, list) else list[1] = { s.a, s.b } end
        for _, seg in ipairs(list) do HLine(seg[1], seg[2], B[s.r]) end
        list = {}
        if nxt then Minus(s.a, s.b, nxt.a, nxt.b, list) else list[1] = { s.a, s.b } end
        for _, seg in ipairs(list) do HLine(seg[1], seg[2], B[s.r + 1]) end
        verticals[#verticals + 1] = { x = s.a, y0 = B[s.r], y1 = B[s.r + 1] }
        verticals[#verticals + 1] = { x = s.b, y0 = B[s.r], y1 = B[s.r + 1] }
    end

    table.sort(verticals, function(p, q)
        if p.x ~= q.x then return p.x < q.x end
        return p.y0 < q.y0
    end)
    local k = 1
    while k <= #verticals do
        local v = verticals[k]
        local y1 = v.y1
        local m = k + 1
        while verticals[m] and verticals[m].x == v.x and verticals[m].y0 <= y1 + 0.01 do
            if verticals[m].y1 > y1 then y1 = verticals[m].y1 end
            m = m + 1
        end
        n = n + 1
        local xx = v.x * stepX
        if xx >= W - 0.01 then xx = xx - t end
        local extra = (y1 >= H - 0.01) and 0 or t
        Rect(box, Tex(box, box.lines, n, "BORDER", BORDER), xx, v.y0, t, y1 - v.y0 + extra)
        k = m
    end
    for i = n + 1, #box.lines do box.lines[i]:Hide() end

    -- Titelband und Titel, dazu ein kurzer Titel für einen abgetrennten Teil.
    DrawLabel(box, box.header, box.band, g, g.labelA, g.labelB, g.labelRow, g.labelText, out, t)
    local extras = g.extraLabels or {}
    for i, x in ipairs(extras) do
        local e = box.extra[i]
        if not e then
            e = { band = box:CreateTexture(nil, "BACKGROUND"), header = CreateFrame("Button", nil, box) }
            e.band:SetColorTexture(TITLE_TINT[1], TITLE_TINT[2], TITLE_TINT[3], TITLE_TINT[4])
            e.header:SetHeight(TITLE_H - 2)
            LabelParts(e.header)
            SetupClicks(e.header, box.view)
            box.extra[i] = e
        end
        DrawLabel(box, e.header, e.band, g, x.a, x.b, x.row, x.text, out, t)
    end
    for i = #extras + 1, #box.extra do
        box.extra[i].band:Hide()
        box.extra[i].header:Hide()
    end
end

local function NewChip(view)
    local chip = CreateFrame("Button", nil, view.parent)
    chip.fill = chip:CreateTexture(nil, "BACKGROUND")
    chip.fill:SetAllPoints()
    chip.fill:SetColorTexture(CHIP_FILL[1], CHIP_FILL[2], CHIP_FILL[3], CHIP_FILL[4])
    chip.lines = {}
    for i = 1, 4 do chip.lines[i] = chip:CreateTexture(nil, "BORDER") end
    for _, l in ipairs(chip.lines) do l:SetColorTexture(BORDER[1], BORDER[2], BORDER[3], BORDER[4]) end
    LabelParts(chip)
    SetupClicks(chip, view)
    return chip
end

local function DrawChip(chip, g)
    local t = LineThickness(chip)
    local top, bottom, left, right = unpack(chip.lines)
    top:ClearAllPoints(); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(t)
    bottom:ClearAllPoints(); bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT"); bottom:SetHeight(t)
    left:ClearAllPoints(); left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT"); left:SetWidth(t)
    right:ClearAllPoints(); right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT"); right:SetWidth(t)
    SetHeaderData(chip, g)
    if g.collapsed then
        chip.icon:SetTexture("Interface\\Buttons\\UI-PlusButton-Up")
        chip.icon:Show()
    else
        chip.icon:Hide()
    end
    chip.label:SetWidth(math.max(g.chipW - ICON - 7, 4))
    chip.label:SetText(g.chipText)
end

---------------------------------------------------------------------------
-- Ansicht (eine pro Tasche, Bank und Fenster)
---------------------------------------------------------------------------

local View = {}
View.__index = View

function Render.NewView(parent, viewKey)
    return setmetatable({ parent = parent, viewKey = viewKey, boxes = {}, chips = {}, targets = {},
        entries = {}, byButton = {} }, View)
end

-- Alle (Unter-)Gruppen dieser Ansicht, auch zugeklappte und leere.
function View:AllKeys()
    local keys = {}
    local out = self.out
    if not out then return keys end
    for _, g in ipairs(out.groups) do keys[#keys + 1] = g.groupKey end
    for _, g in ipairs(out.chips) do keys[#keys + 1] = g.groupKey end
    return keys
end

function View:HideAll()
    if self.area then self.area:Hide() end
    for _, box in ipairs(self.boxes) do box:Hide() end
    for _, chip in ipairs(self.chips) do chip:Hide() end
    wipe(self.targets)
    wipe(self.entries)
    wipe(self.byButton)
    self.out = nil   -- nichts mehr gezeigt: auch keine „Frei“-Kachel mehr (View:FreeTileTaken)
end

--[[
    Place(region, left, top, w, h) setzt einen Bereich relativ zur linken oberen
    Ecke des Layouts; PlaceItem(entry, shown, left, top, group) kümmert sich um
    den Platz-Knopf eines Eintrags.
]]
-- Liegt im gezeigten Platz der zusammengefassten „Frei“-Kachel inzwischen ein Gegenstand? Dann hat der Spieler dort
-- etwas abgelegt, und die Kachel zeigt bis zum Neuordnen einen Gegenstand unter „Frei“ (Spielbefund vom 22.11.2026 mit
-- Bildschirmfoto, wörtlich: „aus 24 wuden 24+16 … jetzt zeigt es wieder 24 an“) – dann ordnet ezBag gleich neu, auch
-- unter der Maus (Render.CanRelayout).
function View:FreeTileTaken()
    local out = self.out
    if not out then return false end
    for _, g in ipairs(out.groups or {}) do
        local e = g.compressed and g.entries and g.entries[1]
        -- dieselbe Regel wie beim Einsortieren (Categories.lua): belegt ist ein Platz mit einer Gegenstands-ID
        if e and type(e.bag) == "number" and e.slot and ns.ItemIDOf(C_Container.GetContainerItemInfo(e.bag, e.slot)) then
            return true
        end
    end
    return false
end

function View:Draw(out, Place, PlaceItem)
    self.out = out
    wipe(self.targets)
    wipe(self.entries)
    wipe(self.byButton)
    local nb, nc = 0, 0
    local stepX = out.stepX

    -- Unsichtbare Fläche über dem ganzen Layout: Bezug für "welche Gruppe liegt unter der Maus".
    if not self.area then self.area = CreateFrame("Frame", nil, self.parent) end
    self.area:SetSize(out.width, math.max(out.totalH, 1))
    Place(self.area, 0, 0, out.width, math.max(out.totalH, 1))
    self.area:Show()

    for _, g in ipairs(out.groups) do
        nb = nb + 1
        local box = self.boxes[nb]
        if not box then
            box = NewBox(self)
            self.boxes[nb] = box
        end
        box:SetSize(out.width, math.max(out.gridH, 1))
        Place(box, 0, 0, out.width, math.max(out.gridH, 1))
        box:Show()
        DrawGroup(box, g, out)
        self.targets[#self.targets + 1] = box.header
        for i = 1, #(g.extraLabels or {}) do self.targets[#self.targets + 1] = box.extra[i].header end

        for j, entry in ipairs(g.entries) do
            entry.groupKey, entry.rootKey = g.groupKey, g.parentKey or g.groupKey
            if j <= g.visible then
                local cell = g.first + j - 1
                local r, c = math.floor(cell / out.cols), cell % out.cols
                PlaceItem(entry, true, c * stepX + out.leftHalf, (g.rowTop and g.rowTop[r]) or out.cellTop[r], g)
                self.entries[#self.entries + 1] = entry
                if entry.button then self.byButton[entry.button] = entry end
            else
                PlaceItem(entry, false, 0, 0, g)
            end
        end
        -- Zusammengefasste Doppelte verschwinden wie in zugeklappten Gruppen.
        for _, entry in ipairs(g.hidden or {}) do
            entry.groupKey, entry.rootKey = g.groupKey, g.parentKey or g.groupKey
            PlaceItem(entry, false, 0, 0, g)
        end
    end

    for _, g in ipairs(out.chips) do
        nc = nc + 1
        local chip = self.chips[nc]
        if not chip then
            chip = NewChip(self)
            self.chips[nc] = chip
        end
        chip:SetSize(g.chipW, CHIP_H)
        Place(chip, g.chipX, g.chipY, g.chipW, CHIP_H)
        DrawChip(chip, g)
        chip:Show()
        self.targets[#self.targets + 1] = chip
        for _, entry in ipairs(g.entries) do PlaceItem(entry, false, 0, 0, g) end
        for _, entry in ipairs(g.hidden or {}) do PlaceItem(entry, false, 0, 0, g) end
    end

    for i = nb + 1, #self.boxes do self.boxes[i]:Hide() end
    for i = nc + 1, #self.chips do self.chips[i]:Hide() end
    -- Mehrfachauswahl: Markier-Knöpfe folgen den Plätzen (Select.lua).
    if ns.Select and ns.Select.IsActive(self) then ns.Select.Refresh(self) end
end

-- Titel und Schilder auf eine Rahmenebene setzen (unter den Plätzen bleiben).
function View:SetLevel(level)
    for _, box in ipairs(self.boxes) do box:SetFrameLevel(level) end
    for _, chip in ipairs(self.chips) do chip:SetFrameLevel(level + 1) end
end

---------------------------------------------------------------------------
-- Ausgrauen: Suche und Hervorheben verwandter Gegenstände
---------------------------------------------------------------------------

local dimmed = setmetatable({}, { __mode = "k" })

-- Eigene dunkle Fläche auf dem Platz; Blizzards Felder bleiben unberührt.
function Render.SetDimmed(button, dim)
    local tex = dimmed[button]
    if not tex then
        if not dim then return end
        tex = button:CreateTexture(nil, "OVERLAY", nil, 6)
        tex:SetAllPoints(button)
        tex:SetColorTexture(0, 0, 0, 0.62)
        dimmed[button] = tex
    end
    tex:SetShown(dim == true)
end

-- Fokus: nur eine Tasche oder Gruppe hell lassen (aus der Werkzeugleiste).
-- focus = { kind = "bag", bag = ID } oder { kind = "group", key = Gruppenschlüssel }
local function OutOfFocus(focus, entry)
    if not focus then return false end
    if focus.kind == "bag" then return entry.bag ~= focus.bag end
    return entry.groupKey ~= focus.key and entry.rootKey ~= focus.key
end

function View:SetFocus(focus)
    self.focus = focus
    self:ApplyDim()
end

-- Suche, Fokus und Zeigen zusammen anwenden.
function View:ApplyDim()
    local focus = self.focus
    for _, entry in ipairs(self.entries) do
        local button = entry.button or entry.display
        if button then
            Render.SetDimmed(button, entry.searchDim or entry.hoverDim or OutOfFocus(focus, entry) or false)
        end
    end
end

-- Blizzards Suche kennt nur Namen. Was über das Item-Wissen passt (z. B. "buff",
-- "hände", "lvl<20"), holen wir zurück: Blizzards Grau-Schicht nur ausblenden.
function View:ExtendSearch(search)
    if not search or search == "" or not ns.Knowledge then return end
    search = search:lower()
    for _, entry in ipairs(self.entries) do
        local overlay = entry.button and entry.button.searchOverlay
        if overlay and overlay:IsShown() and Render.Matches(entry, search) then overlay:Hide() end
    end
end

function View:SetHover(hovered)
    local any = false
    if hovered and ns.S.highlight then
        for _, entry in ipairs(self.entries) do
            if entry ~= hovered and Render.Related(hovered, entry) then
                any = true
                break
            end
        end
    end
    for _, entry in ipairs(self.entries) do
        entry.hoverDim = any and entry ~= hovered and not Render.Related(hovered, entry) or nil
    end
    self:ApplyDim()
end

local hoverHooked = setmetatable({}, { __mode = "k" })

-- Ansicht, zu der ein Platz-Knopf gerade gehört (Tasche, Bank, Gildenbank) – für Tooltip-Zeilen (Stacks.lua).
function Render.ViewOf(button)
    return hoverHooked[button]
end

-- Platz-Knopf für "verwandte Gegenstände hervorheben" vorbereiten.
function Render.HookHover(button, view)
    if hoverHooked[button] then
        hoverHooked[button] = view
        return
    end
    hoverHooked[button] = view
    button:HookScript("OnEnter", function(self)
        local v = hoverHooked[self]
        local entry = v and (v.byButton[self])
        if entry then v:SetHover(entry) end
    end)
    button:HookScript("OnLeave", function(self)
        local v = hoverHooked[self]
        if v then v:SetHover(nil) end
    end)
end
