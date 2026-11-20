local _, ns = ...
local Core = ezCore

--[[
    Punkteschicht auf Blizzards Weltkarte (SAM-06, Welle 13): EIN Dienst für viele Punkte – Sammel-Fundorte,
    Eingänge, seltene Gegner, Bücher. Vorher zeichnete jedes Modul eigene Knöpfe je Punkt (ezMap/Entrances.lua); für
    hunderte Punkte je Zone ist das zu teuer und ruckelt beim Zoomen (Teil B der Analyse, Risiken 4 und 5).

      MapPins.AddProvider(schlüssel, anbieter) → true
          anbieter = { punkte|points = fn(mapID) → { punkt … }, tooltip = fn(tooltip, punkt, mapID),
                       klick|click = fn(punkt, maustaste, mapID), menu = fn(punkt, root, mapID) (Rechtsklick, Blizzards
                       Menü), sichtbar|visible = fn(mapID, fläche) → bool (fläche "minimap" auf der Minikarte),
                       minikarte|minimap = true | fn(mapID) (auch auf der Minikarte, SAM-07),
                       nahAus|hideNear = Yards | fn() → Yards (Minikarte: Punkte so nah am Spieler auslassen;
                       ein Punkt mit nahAus|hideNear = false bleibt trotzdem stehen),
                       owner = Modulname }
          punkt = { x, y (0–1 auf der Karte map, Standard: die gezeigte Karte), map, texture | atlas, size, r, g, b, a }
          Punkte einer anderen Karte rechnet der Dienst über Weltkoordinaten um (Core.Map.PosOn; Eltern- und
          Kontinentkarten), was sich nicht umrechnen lässt, entfällt.
      MapPins.RemoveProvider(schlüssel), MapPins.Providers() → { schlüssel … }
      MapPins.Refresh()        baut die Punkte der gezeigten Karte neu (in Scheiben zu MapPins.SLICE je Bild)
      MapPins.Rescale()        passt nur die Größe an (beim Zoomen; höchstens einmal je Bild)
      MapPins.Count()          → gesetzte Punkte, Karte;  MapPins.Building() → true, solange Scheiben ausstehen
      MapPins.Nearest(x, y, abstand) → punkt, schlüssel (nächster Punkt zur Kartenstelle, abstand in Bildpunkten)
      MapPins.Overlay(), MapPins.Grip() → der Überlagerungsrahmen bzw. der Griff-Knopf (für Tests und /dump)
      MapPins.MinimapRadius(zoom) → Yards, Herkunft ("client" | "probe") – Sichtradius der Minikarte
      Seit Welle 14 (SAM-07): Feld minikarte am Anbieter – dieselben Punkte auch auf der Minikarte (Abschnitt unten).

    Aufbau (Belege aus Blizzards Quelle, Zweig forever, Blizzard_MapCanvas/Blizzard_MapCanvas.lua, am 15.11.2026
    nachgelesen): WorldMapFrame:GetCanvas() ist ScrollContainer.Child (wandert und skaliert beim Zoomen);
    OnMapChanged läuft beim Kartenwechsel, OnCanvasScaleChanged in jedem Bild der Zoom-Animation;
    GetNormalizedCursorPosition nennt die Mausstelle auf der Karte (0–1). Darauf: EIN eigener Rahmen als Kind der
    Kartenfläche (wie ezMap/Entrances.lua), Punkte als Texturen aus einem Vorrat, ein Rasterindex je gezeigter Karte
    (MapPins.CELLS Zellen je Achse), EIN gemeinsamer Tooltip über die Mausposition und EIN beweglicher Griff-Knopf, der
    sich auf den Punkt unter der Maus legt (Klick und Menü). Der Rahmen selbst nimmt keine Maus an – Ziehen und Klicken
    auf der Karte bleiben Blizzards.

    Taint (Leitlinie 5): nur hooksecurefunc (OnMapChanged, OnCanvasScaleChanged) und HookScript (OnShow). KEIN
    AcquirePin (schreibt in self.pinPools), KEIN AddDataProvider (schreibt in self.dataProviders), kein
    SetPassThroughButtons (im Kampf gesperrt). Schicht: Rahmenebene der Kartenfläche plus MapPins.LEVEL, mindestens aber
    MapPins.AREA_GAP über Blizzards Flächen (Erkundung, Nebel, Quest-Flächen; MapPins.AreaLevel, seit dem Spielbefund
    vom 18.11.2026), Strata der Karte unverändert – im Spiel zu prüfen (ezCore „Im Spiel prüfen“, Punkt 62).
      MapPins.AreaLevel([karte]) → oberste Stufe von Blizzards Flächen oder nil (nur lesend)
      MapPins.LayerLevel(kartenfläche, abstand, abstandFlächen) → Stufe einer eigenen Schicht, Stufe der Flächen
]]

local MapPins = {}
Core.MapPins = MapPins

MapPins.SIZE = 12        -- Bildpunkte auf dem Bildschirm, bei jeder Zoomstufe gleich
MapPins.HIT = 8          -- so nah (Bildpunkte) muss die Maus an einem Punkt sein, damit der Griff sich darauflegt
MapPins.CELLS = 32       -- Rasterindex: Zellen je Achse (etwa 1/32 der Kartenbreite, Teil B, Datenmodell)
MapPins.SLICE = 300      -- Punkte je Bild beim Aufbau
MapPins.MAX = 3000       -- Obergrenze gesetzter Punkte je Karte (Sicherung)
MapPins.SCAN_MAX = 20000 -- Obergrenze geprüfter Punkte je Aufbau (auch verworfene zählen)
MapPins.CONVERT_MAX = 2000 -- Obergrenze einzeln umgerechneter Punkte je Aufbau (ohne Umrechnung je Karte)
MapPins.LEVEL = 10       -- Rahmenebene über der Kartenfläche
-- Blizzards Flächen-Ebenen der Weltkarte (Forever-Quelle, Zweig forever, am 18.11.2026 nachgelesen:
-- Blizzard_WorldMap/Blizzard_WorldMap.lua, AddFrameLevel in WorldMapMixin; Blizzard_MapCanvas/
-- MapCanvas_PinFrameLevelsManager.lua: die Stufen beginnen absolut bei 2000). Die Erkundungs-Flächen
-- (MapExplorationDataProvider: Kartenbild der erkundeten Gebiete), Nebel, Quest- und Szenario-Flächen liegen damit
-- weit über „Kartenfläche + 10“ und decken dort zu, was eine eigene Schicht darunter zeichnet (Spielbefund vom
-- 18.11.2026: Linien der Routen unsichtbar). Die Schicht liegt deshalb mindestens MapPins.AREA_GAP Stufen über der
-- obersten dieser Flächen – und unter Blizzards Symbolen (Eingänge, Flugpunkte, Quests), die danach kommen.
MapPins.AREA_LEVELS = { "PIN_FRAME_LEVEL_MAP_EXPLORATION", "PIN_FRAME_LEVEL_EVENT_OVERLAY", "PIN_FRAME_LEVEL_GARRISON_PLOT",
    "PIN_FRAME_LEVEL_FOG_OF_WAR", "PIN_FRAME_LEVEL_QUEST_BLOB", "PIN_FRAME_LEVEL_SCENARIO_BLOB",
    "PIN_FRAME_LEVEL_MAP_HIGHLIGHT" }
MapPins.AREA_GAP = 2     -- Stufen über Blizzards Flächen (die Linien der Routen in ezMap liegen eine darunter)
-- Index an GetValidFrameLevel: Blizzard begrenzt ihn auf das Ende der Ebene (MapCanvas_PinFrameLevelsManager.lua,
-- GetValidFrameLevel: Clamp(optionalIndex or 1, 1, definition.range)); eine Ebene, die Forever nicht anlegt, liefert
-- die Stufe von PIN_FRAME_LEVEL_DEFAULT (2000) – kein Ausreißer nach oben (Gegenprüfung vom 18.11.2026)
MapPins.AREA_INDEX = 10000
MapPins.MOUSE_EVERY = 0.05   -- Sekunden zwischen zwei Maus-Abfragen
-- Rückfall, wenn ein Punkt weder einen bekannten Atlas noch eine Datei nennt: ein Einzelbild (Blizzards gelber Punkt,
-- wie ezMap/QuestieSpawns.lua und ezCraft/Icons.lua), kennt der Client es nicht, Blizzards Fragezeichen. Vorher stand
-- hier das ganze Symbolblatt Interface\Minimap\ObjectIconsAtlas ohne Ausschnitt, gestaucht auf 12 Bildpunkte
-- (Gesamtreview 18.11.2026, T16-NM2).
MapPins.TEXTURE = "Interface\\Common\\Indicator-Yellow"

-- Sichtradius der Minikarte je Zoomstufe in Yards (Sonderprobe X8, 15.11.2026, Build 70938, deDE: C_Minimap.
-- GetViewRadius nach SetZoom(0 bis 5), draußen und drinnen dieselben Werte; Zoomstufen laut GetZoomLevels 6).
-- Nur Rückfall – zuerst fragt MinimapRadius den Client.
MapPins.MINIMAP_RADIUS = { [0] = 150, [1] = 120, [2] = 90, [3] = 60, [4] = 40, [5] = 25 }

local providers, order = {}, {}
local overlay, grip
local textures, used = {}, 0
local placed = {}             -- { x, y, key, point } je gesetzter Textur (Index = Textur)
local grid = {}               -- Zelle » { Index … }
local shownMap, build = nil, nil
local hooked, rescalePlanned = false, false
local hover                   -- { index } unter der Maus
-- Minikarte (SAM-07, unten): Punkte der gezeigten Speicherkarte, Rasterindex, Zustand
local mini = { points = {}, grid = {}, map = nil, dirty = true, since = 0, reason = "none", shown = 0, placed = {} }

local function Num(v) return Core.Num(v) end

--[[
    Symbol eines Punkts setzen: EINE Stelle für Weltkarte und Minikarte (Spielbefund vom 18.11.2026, wörtlich:
    „manche icons haben komische rahmen“). Gegenstands- und Zaubersymbole (Dateien unter Interface\Icons\, Datei-IDs aus
    GetItemIcon bzw. C_Spell.GetSpellTexture) tragen im Bild einen dunklen Rand mit eckigen Kanten; Blizzard schneidet
    ihn an seinen Knöpfen ab (wie Core.SetIcon, Layout.lua, ChatBar.lua: 0.08 bis 0.92). Atlas-Symbole und eigene
    Punkt-Texturen (Interface\Common\Indicator-…, Interface\Minimap\…, WHITE8X8) bleiben unverändert.
      MapPins.IsIconFile(textur) → true für eine Datei unter Interface\Icons\ (Groß/klein und / egal) oder eine
          Datei-ID über 0 (Zahlen bekommen die Punkte nur aus den Gegenstands- und Zauber-APIs)
      MapPins.SetSymbol(tex, punkt) → "atlas" | "icon" | "file". Atlas nur, wenn der Client ihn kennt, sonst die Datei
          des Punkts (Gesamtreview 18.11.2026, Nachsuche Texturen: ein unbekannter Atlas verdrängte den Datei-Rückfall);
          punkt.crop = true/false erzwingt bzw. verbietet den Beschnitt.
      MapPins.ForgetAtlases() vergisst die gemerkten Antworten zu Atlasnamen (Prüfungen mit eigenem C_Texture).
      MapPins.SetRoundIcons(an) → true bei Änderung; MapPins.RoundIcons() → an. Beschnittene Symbole zusätzlich rund
          maskieren (Blizzards runde Maske MapPins.ICON_MASK, wie bei den Porträts); Schalter „Symbole rund“ in ezMap
          (pinsRound). Baut beide Karten neu.
]]
MapPins.ICON_CROP = { 0.08, 0.92, 0.08, 0.92 }
MapPins.ICON_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local roundIcons = false
local masks = setmetatable({}, { __mode = "k" })     -- eigene Textur » eigene Maske
local masked = setmetatable({}, { __mode = "k" })    -- eigene Textur » true, solange die Maske hängt
local fallbackFile
local atlasKnown = {}                                  -- Atlasname » bekannt (der Client ändert sie nicht)

local function KnownAtlas(name)
    local known = atlasKnown[name]
    if known == nil then
        known = Core.AtlasExists(name) == true
        atlasKnown[name] = known
    end
    return known
end

-- Gemerkte Antworten zu Atlasnamen vergessen (für Prüfungen mit eigenem C_Texture; im Spiel ohne Aufrufer nötig)
function MapPins.ForgetAtlases() atlasKnown = {} end

function MapPins.IsIconFile(texture)
    if Core.IsSecret(texture) then return false end
    if type(texture) == "number" then return texture > 0 end
    if type(texture) ~= "string" then return false end
    local path = texture:lower():gsub("/", "\\")
    return path:find("^interface\\icons\\") ~= nil
end

local function FallbackFile()
    if fallbackFile == nil then
        local menu = Core.Menu
        fallbackFile = (Core.KnownFile(MapPins.TEXTURE) or not (menu and menu.ICON_FALLBACK)) and MapPins.TEXTURE
            or menu.ICON_FALLBACK
    end
    return fallbackFile
end

local function Mask(tex, on)
    if not on then
        if masked[tex] and tex.RemoveMaskTexture then tex:RemoveMaskTexture(masks[tex]) end
        masked[tex] = nil
        return
    end
    if masked[tex] then return end
    local mask = masks[tex]
    if not mask then
        local parent = tex.GetParent and tex:GetParent()
        if not (parent and parent.CreateMaskTexture and tex.AddMaskTexture) then return end
        mask = parent:CreateMaskTexture()
        mask:SetTexture(MapPins.ICON_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(tex)
        masks[tex] = mask
    end
    tex:AddMaskTexture(mask)
    masked[tex] = true
end

function MapPins.SetSymbol(tex, p)
    if type(p) ~= "table" then p = {} end
    local atlas = p.atlas
    if Core.IsSecret(atlas) or type(atlas) ~= "string" or atlas == "" then atlas = nil end
    if atlas and tex.SetAtlas and KnownAtlas(atlas) then
        Mask(tex, false)
        tex:SetAtlas(atlas)    -- setzt den Ausschnitt des Atlas selbst
        return "atlas"
    end
    local file = p.texture
    if Core.IsSecret(file) or (type(file) ~= "string" and type(file) ~= "number") or file == "" then
        file = FallbackFile()
    end
    tex:SetTexture(file)
    local crop = p.crop
    if crop == nil then crop = MapPins.IsIconFile(file) end
    crop = crop == true
    if crop then
        local c = MapPins.ICON_CROP
        tex:SetTexCoord(c[1], c[2], c[3], c[4])
    else
        tex:SetTexCoord(0, 1, 0, 1)    -- Vorrat: den Beschnitt eines früheren Symbols nicht weitertragen
    end
    Mask(tex, crop and roundIcons)
    return crop and "icon" or "file"
end

function MapPins.RoundIcons() return roundIcons end

function MapPins.SetRoundIcons(on)
    on = on == true
    if on == roundIcons then return false end
    roundIcons = on
    MapPins.Refresh()
    Core.Try(nil, "MapPins.MinimapRefresh", MapPins.MinimapRefresh)
    return true
end

local function Map() return rawget(_G, "WorldMapFrame") end

local function Canvas()
    local map = Map()
    if type(map) ~= "table" then return nil end
    if type(map.GetCanvas) == "function" then
        local ok, canvas = pcall(map.GetCanvas, map)
        if ok and type(canvas) == "table" then return canvas end
    end
    return map.ScrollContainer and map.ScrollContainer.Child or nil
end

-- Oberste Rahmenstufe von Blizzards Flächen auf der Weltkarte (MapPins.AREA_LEVELS) oder nil, wenn die Karte keine
-- Ebenen-Verwaltung hat. Nur lesend (GetPinFrameLevelsManager, GetValidFrameLevel) – nichts in Blizzards Tabellen.
function MapPins.AreaLevel(map)
    map = map or Map()
    if type(map) ~= "table" or type(map.GetPinFrameLevelsManager) ~= "function" then return nil end
    local ok, manager = pcall(map.GetPinFrameLevelsManager, map)
    if not ok or type(manager) ~= "table" or type(manager.GetValidFrameLevel) ~= "function" then return nil end
    local top
    for _, kind in ipairs(MapPins.AREA_LEVELS) do
        local okLevel, level = pcall(manager.GetValidFrameLevel, manager, kind, MapPins.AREA_INDEX)
        level = okLevel and Num(level) or nil
        if level and (top == nil or level > top) then top = level end
    end
    return top
end

-- Rahmenstufe einer eigenen Schicht auf der Kartenfläche canvas: Kartenfläche + offset, mindestens aber areaGap Stufen
-- über Blizzards Flächen (MapPins.AreaLevel) → Stufe oder nil (nichts lesbar), dazu die Stufe der Flächen
function MapPins.LayerLevel(canvas, offset, areaGap)
    local level
    if type(canvas) == "table" and type(canvas.GetFrameLevel) == "function" then
        local ok, base = pcall(canvas.GetFrameLevel, canvas)
        base = ok and Num(base) or nil
        if base then level = base + (Num(offset) or 0) end
    end
    local area = MapPins.AreaLevel()
    if area then
        local above = area + (Num(areaGap) or MapPins.AREA_GAP)
        if level == nil or above > level then level = above end
    end
    return level, area
end

local function Sort()
    table.sort(order, function(a, b)
        local pa, pb = providers[a], providers[b]
        if pa.order ~= pb.order then return pa.order < pb.order end
        return a < b
    end)
end

function MapPins.AddProvider(key, p)
    if type(key) ~= "string" or key == "" or type(p) ~= "table" then return false end
    local points = p.punkte or p.points
    if type(points) ~= "function" then return false end
    if not providers[key] then order[#order + 1] = key end
    local minimap = p.minikarte
    if minimap == nil then minimap = p.minimap end
    providers[key] = { key = key, points = points, tooltip = p.tooltip, click = p.klick or p.click, menu = p.menu,
        visible = p.sichtbar or p.visible, owner = p.owner or key, order = Num(p.order) or 50,
        minimap = (minimap == true or type(minimap) == "function") and minimap or nil,
        hideNear = p.nahAus or p.hideNear }
    Sort()
    MapPins.ForgetMiniProviders()
    mini.dirty = true
    MapPins.Refresh()
    if providers[key].minimap then Core.Try(nil, "MapPins.MinimapUpdate", MapPins.MinimapUpdate) end
    return true
end

function MapPins.RemoveProvider(key)
    if not providers[key] then return false end
    providers[key] = nil
    for i = #order, 1, -1 do
        if order[i] == key then table.remove(order, i) end
    end
    MapPins.ForgetMiniProviders()
    mini.dirty = true
    MapPins.Refresh()
    Core.Try(nil, "MapPins.MinimapUpdate", MapPins.MinimapUpdate)
    return true
end

function MapPins.Providers()
    local out = {}
    for i, key in ipairs(order) do out[i] = key end
    return out
end

-- Kartenfläche, Breite, Höhe, Zoom, wenn die Weltkarte offen ist; sonst nil
local function Surface()
    local map = Map()
    if not (type(map) == "table" and map.IsShown and map:IsShown() and map.GetMapID) then return nil end
    local canvas = Canvas()
    if not canvas then return nil end
    local w, h = Num(canvas:GetWidth()), Num(canvas:GetHeight())
    local scale = Num(canvas.GetScale and canvas:GetScale()) or 1
    if not (w and h) or w <= 0 or h <= 0 or scale <= 0 then return nil end
    return map, canvas, w, h, scale
end

local function Overlay(canvas)
    if not overlay then
        overlay = CreateFrame("Frame", "ezCoreMapPins", canvas)
        overlay:SetAllPoints(canvas)
        if overlay.EnableMouse then overlay:EnableMouse(false) end
        overlay:SetScript("OnUpdate", function(self, elapsed) MapPins.OnUpdate(elapsed) end)
    end
    if overlay.SetFrameLevel then
        local level = MapPins.LayerLevel(canvas, MapPins.LEVEL, MapPins.AREA_GAP)
        if level then overlay:SetFrameLevel(level) end
    end
    return overlay
end

local function Texture(i)
    local tex = textures[i]
    if not tex then
        tex = overlay:CreateTexture(nil, "OVERLAY")
        textures[i] = tex
    end
    return tex
end

local function Clear()
    for i = 1, used do
        textures[i]:Hide()
        placed[i] = nil
    end
    used, grid, hover = 0, {}, nil
    if grip then grip:Hide() end
end

local function Cell(x, y)
    local n = MapPins.CELLS
    local cx = math.min(n - 1, math.max(0, math.floor(x * n)))
    local cy = math.min(n - 1, math.max(0, math.floor(y * n)))
    return cx * n + cy
end

local function Size(p, scale)
    return (Num(p.size) or MapPins.SIZE) / scale
end

local function Place(e, w, h, scale)
    used = used + 1
    local tex = Texture(used)
    local p = e.point
    MapPins.SetSymbol(tex, p)
    local s = Size(p, scale)
    tex:SetSize(s, s)
    tex:ClearAllPoints()
    tex:SetPoint("CENTER", overlay, "TOPLEFT", e.x * w, -e.y * h)
    tex:SetVertexColor(Num(p.r) or 1, Num(p.g) or 1, Num(p.b) or 1, Num(p.a) or 1)
    tex:Show()
    placed[used] = e
    local c = Cell(e.x, e.y)
    local list = grid[c]
    if not list then list = {} grid[c] = list end
    list[#list + 1] = used
end

-- Umrechnung je Quellkarte (Gegenprüfung Welle 13: vorher je Punkt zwei C_Map-Aufrufe in einem Bild). Kartenflächen
-- sind achsenparallele Rechtecke in Weltkoordinaten, die Umrechnung ist also affin: drei Bezugspunkte über
-- Core.Map.PosOn genügen. Liegt ein Bezugspunkt außerhalb der Zielkarte (PosOn → nil), wird je Punkt umgerechnet –
-- höchstens MapPins.CONVERT_MAX Punkte je Aufbau. → fn(x, y) → x, y; false: je Punkt
local function Affine(target, from)
    local PosOn = Core.Map.PosOn
    local x0, y0 = PosOn(target, from, 0, 0)
    local x1, y1 = PosOn(target, from, 1, 0)
    local x2, y2 = PosOn(target, from, 0, 1)
    if not (x0 and y0 and x1 and y1 and x2 and y2) then return false end
    local ax, ay, bx, by = x1 - x0, y1 - y0, x2 - x0, y2 - y0
    return function(x, y) return x0 + ax * x + bx * y, y0 + ay * x + by * y end
end

-- Punkte aller sichtbaren Anbieter für die Karte mapID (umgerechnet), höchstens MapPins.MAX
local function Gather(mapID)
    local out = {}
    local affine, seen, single = {}, 0, 0
    for _, key in ipairs(order) do
        local p = providers[key]
        local show = true
        if p.visible then
            local ok, yes = Core.Try(p.owner, "MapPins " .. key .. " visible", p.visible, mapID)
            show = ok and yes ~= false
        end
        if show then
            local ok, list = Core.Try(p.owner, "MapPins " .. key .. " points", p.points, mapID)
            for _, point in ipairs(ok and type(list) == "table" and list or {}) do
                if #out >= MapPins.MAX or seen >= MapPins.SCAN_MAX then return out end
                seen = seen + 1
                local x, y = Num(type(point) == "table" and point.x), Num(type(point) == "table" and point.y)
                local from = Num(type(point) == "table" and point.map)
                if x and y and from and from ~= mapID then
                    local fn = affine[from]
                    if fn == nil then
                        fn = Affine(mapID, from)
                        affine[from] = fn
                    end
                    if fn then
                        x, y = fn(x, y)
                    elseif single < MapPins.CONVERT_MAX then
                        single = single + 1
                        x, y = Core.Map.PosOn(mapID, from, x, y)
                    else
                        x, y = nil, nil
                    end
                end
                if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
                    out[#out + 1] = { x = x, y = y, key = key, point = point }
                end
            end
        end
    end
    return out
end

local Step

-- Eine Scheibe setzen; ist noch etwas übrig, im nächsten Bild weiter
Step = function()
    local b = build
    if not b then return end
    local map, _, w, h, scale = Surface()
    if not map or map:GetMapID() ~= b.map then
        build = nil
        return
    end
    local stop = math.min(#b.list, b.at + MapPins.SLICE - 1)
    for i = b.at, stop do Place(b.list[i], w, h, scale) end
    b.at = stop + 1
    if b.at > #b.list then
        build = nil
        return
    end
    C_Timer.After(0, Step)
end

function MapPins.Refresh()
    -- Minikarte: Punkte beim nächsten Schritt neu holen (die Anbieter rufen Refresh, wenn sich ihre Daten ändern)
    mini.map, mini.dirty = nil, true
    build = nil
    if overlay then Clear() end
    local map, canvas = Surface()
    if not map then
        shownMap = nil
        if overlay then overlay:Hide() end
        return 0
    end
    Overlay(canvas):Show()
    local mapID = Num(map:GetMapID())
    shownMap = mapID
    if not mapID or #order == 0 then return 0 end
    build = { map = mapID, list = Gather(mapID), at = 1 }
    local total = #build.list
    Step()   -- die erste Scheibe sofort, der Rest in den folgenden Bildern
    return total
end

-- Zoom: nur die Größe (die Lage in der Kartenfläche bleibt) – höchstens einmal je Bild
local function Resize()
    rescalePlanned = false
    local map, _, _, _, scale = Surface()
    if not map then return end
    if map:GetMapID() ~= shownMap then return MapPins.Refresh() end
    for i = 1, used do
        local s = Size(placed[i].point, scale)
        textures[i]:SetSize(s, s)
    end
    if grip and grip:IsShown() and hover then
        local s = Size(placed[hover].point, scale)
        grip:SetSize(s, s)
    end
end

function MapPins.Rescale()
    if rescalePlanned then return false end
    rescalePlanned = true
    C_Timer.After(0, Resize)
    return true
end

function MapPins.Count() return used, shownMap end
function MapPins.Building() return build ~= nil end
function MapPins.Overlay() return overlay end
function MapPins.Grip() return grip end

-- Nächster gesetzter Punkt zur Kartenstelle x, y (0–1) im Umkreis von abstand Bildpunkten (Standard MapPins.HIT)
function MapPins.Nearest(x, y, radius)
    x, y = Num(x), Num(y)
    local map, _, w, h, scale = Surface()
    if not (map and x and y) or used == 0 then return nil end
    radius = (Num(radius) or MapPins.HIT) / scale   -- Bildpunkte auf dem Bildschirm » Einheiten der Kartenfläche
    local n = MapPins.CELLS
    local rx, ry = math.ceil(radius / w * n), math.ceil(radius / h * n)
    local cx, cy = math.floor(x * n), math.floor(y * n)
    local best, bestD
    for gx = cx - rx, cx + rx do
        for gy = cy - ry, cy + ry do
            if gx >= 0 and gy >= 0 and gx < n and gy < n then
                for _, i in ipairs(grid[gx * n + gy] or {}) do
                    local e = placed[i]
                    local d = math.sqrt(((e.x - x) * w) ^ 2 + ((e.y - y) * h) ^ 2)
                    if d <= radius and (not bestD or d < bestD) then best, bestD = i, d end
                end
            end
        end
    end
    if not best then return nil end
    return placed[best].point, placed[best].key, best
end

---------------------------------------------------------------------------
-- Griff-Knopf: legt sich auf den Punkt unter der Maus (Tooltip, Klick, Menü)
---------------------------------------------------------------------------

local function Hovered()
    local e = hover and placed[hover]
    if not e then return nil end
    return e, providers[e.key]
end

local function ShowTip(self)
    local e, p = Hovered()
    if not (e and p and p.tooltip) then return end
    local tip = rawget(_G, "GameTooltip")
    if not tip then return end
    tip:SetOwner(self, "ANCHOR_RIGHT")
    local ok = Core.Try(p.owner, "MapPins " .. e.key .. " tooltip", p.tooltip, tip, e.point, shownMap)
    if ok then tip:Show() else tip:Hide() end
end

local function OnClick(self, button)
    local e, p = Hovered()
    if not (e and p) then return end
    local tip = rawget(_G, "GameTooltip")
    if button == "RightButton" and p.menu and MenuUtil and MenuUtil.CreateContextMenu then
        if tip then tip:Hide() end
        MenuUtil.CreateContextMenu(self, function(_, root)
            Core.Try(p.owner, "MapPins " .. e.key .. " menu", p.menu, e.point, root, shownMap)
        end)
    elseif p.click then
        Core.Try(p.owner, "MapPins " .. e.key .. " click", p.click, e.point, button, shownMap)
    end
end

local function Grip()
    if grip then return grip end
    grip = CreateFrame("Button", "ezCoreMapPinsGrip", overlay)
    grip:SetSize(MapPins.SIZE, MapPins.SIZE)
    if grip.RegisterForClicks then grip:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    grip:SetScript("OnEnter", ShowTip)
    grip:SetScript("OnLeave", function() local tip = rawget(_G, "GameTooltip") if tip then tip:Hide() end end)
    grip:SetScript("OnClick", OnClick)
    grip:Hide()
    return grip
end

-- Mausstelle auf der Karte (0–1): Blizzards GetNormalizedCursorPosition, sonst aus GetCursorPosition gerechnet
local function Cursor(map, canvas)
    if type(map.GetNormalizedCursorPosition) == "function" then
        local ok, x, y = pcall(map.GetNormalizedCursorPosition, map)
        if ok and Num(x) and Num(y) then return x, y end
    end
    local cx, cy = GetCursorPosition()
    local left, top = Num(canvas:GetLeft()), Num(canvas:GetTop())
    local s = Num(canvas:GetEffectiveScale()) or 1
    local w, h = Num(canvas:GetWidth()), Num(canvas:GetHeight())
    if not (cx and cy and left and top and w and h) or w <= 0 or h <= 0 then return nil end
    return (cx / s - left) / w, (top - cy / s) / h
end

-- Griff auf den Punkt index legen (oder verstecken). → true, wenn er jetzt auf einem Punkt liegt
function MapPins.Hover(index)
    local e = index and placed[index]
    if not e then
        if grip and grip:IsShown() then
            grip:Hide()
            local tip = rawget(_G, "GameTooltip")
            if tip and tip.IsOwned and tip:IsOwned(grip) then tip:Hide() end
        end
        hover = nil
        return false
    end
    if hover == index and grip and grip:IsShown() then return true end
    local map, _, w, h, scale = Surface()
    if not map then return false end
    hover = index
    local g = Grip()
    local s = Size(e.point, scale)
    g:SetSize(s, s)
    g:ClearAllPoints()
    g:SetPoint("CENTER", overlay, "TOPLEFT", e.x * w, -e.y * h)
    g:Show()
    if g.IsMouseOver and g:IsMouseOver() then ShowTip(g) end
    return true
end

local since = 0
function MapPins.OnUpdate(elapsed)
    since = since + (Num(elapsed) or 0)
    if since < MapPins.MOUSE_EVERY then return end
    since = 0
    if used == 0 then return MapPins.Hover(nil) end
    local map, canvas = Surface()
    if not map then return MapPins.Hover(nil) end
    local x, y = Cursor(map, canvas)
    local _, _, index = MapPins.Nearest(x, y)
    MapPins.Hover(index)
end

---------------------------------------------------------------------------
-- Haken an Blizzards Weltkarte
---------------------------------------------------------------------------

function MapPins.Hook()
    local map = Map()
    if hooked or type(map) ~= "table" then return false end
    hooked = true
    local function Later() Core.Try(nil, "MapPins.Refresh", MapPins.Refresh) end
    local function Zoomed() Core.Try(nil, "MapPins.Rescale", MapPins.Rescale) end
    if map.HookScript then map:HookScript("OnShow", Later) end
    if type(map.OnMapChanged) == "function" then hooksecurefunc(map, "OnMapChanged", Later) end
    if type(map.OnCanvasScaleChanged) == "function" then hooksecurefunc(map, "OnCanvasScaleChanged", Zoomed) end
    Later()
    return true
end

-- Haken, sobald Blizzards Weltkarte geladen ist (sie lädt auf Abruf); beim Anmelden, falls sie schon da ist
ns.On("ADDON_LOADED", function(_, name)
    if name == "Blizzard_WorldMap" then Core.Try(nil, "MapPins.Hook", MapPins.Hook) end
end)
ns.On("PLAYER_LOGIN", function()
    if Core.IsLoaded("Blizzard_WorldMap") then Core.Try(nil, "MapPins.Hook", MapPins.Hook) end
end)

---------------------------------------------------------------------------
-- Sichtradius der Minikarte (Geometrie für SAM-07, Welle 14)
---------------------------------------------------------------------------

function MapPins.MinimapRadius(zoom)
    local api = rawget(_G, "C_Minimap")
    if zoom == nil and type(api) == "table" and type(api.GetViewRadius) == "function" then
        local ok, yards = pcall(api.GetViewRadius)
        yards = ok and not Core.IsSecret(yards) and Num(yards)
        if yards and yards > 0 then return yards, "client" end
    end
    if zoom == nil then
        local mm = rawget(_G, "Minimap")
        zoom = type(mm) == "table" and type(mm.GetZoom) == "function" and Num((select(2, pcall(mm.GetZoom, mm)))) or 0
    end
    local yards = MapPins.MINIMAP_RADIUS[Num(zoom) or 0]
    if yards then return yards, "probe" end
    return nil
end

---------------------------------------------------------------------------
-- Punkte auf der Minikarte (SAM-07, Welle 14)
---------------------------------------------------------------------------
--[[
    Anbieter mit dem Feld minikarte (true: dieselbe Funktion punkte; oder eine eigene fn(mapID) → { punkt … }) zeigen
    ihre Punkte zusätzlich auf Blizzards Minikarte; sichtbar|visible bekommt dort als zweiten Wert "minimap".
    Feld nahAus|hideNear (Zahl oder fn() → Yards; nil oder 0 = aus; Wunsch des Nutzers vom 18.11.2026 für ezMaps
    Sammel-Fundorte): Punkte dieses Anbieters, die näher als so viele Yards am Spieler liegen, setzt die Minikarte nicht –
    Blizzards eigenes Aufspür-Symbol darunter bleibt frei. Ein Punkt mit nahAus|hideNear = false ist ausgenommen (etwa
    die Zwischenpunkte einer Route, die auf keinem Vorkommen liegen und nur die Richtung zeigen; Gegenprüfung vom
    18.11.2026). MapPins.HIDE_NEAR = true zeigt Modulen, dass dieser ezCore das Feld kennt. Gefragt wird einmal je Neuberechnung, die ohnehin nach jeder
    Bewegung um MINI_MOVE läuft; kein eigener Ticker, keine Arbeit, solange der Spieler steht. Die Weltkarte bleibt unberührt.
    Grundlage: Sonderprobe X8 (15.11.2026) – C_Minimap.GetViewRadius gibt es auf Forever (150 bis 25 Yards je
    Zoomstufe, draußen und drinnen gleich). Fehlt die Funktion im Client, bleiben die Punkte aus (Grund "api" in
    MapPins.MinimapState und /ez status) – keine selbst gemessenen Radien; MINIMAP_RADIUS dient hier nicht als Ersatz.

    Geometrie als reine Funktionen (Prüfungen in minikarte14_test.lua):
      MapPins.MinimapOffset(ost, süd, radius, blick) → rechts, oben in Vielfachen des Sichtradius. ost/süd: Abstand
          Fundort minus Spieler in Yards (Karten-x wächst nach Osten, Karten-y nach Süden); blick (Bogenmaß, 0 =
          Norden, gegen den Uhrzeigersinn wachsend wie GetPlayerFacing) nur bei gedrehter Minikarte, sonst nil.
      MapPins.MinimapRound(form) → { tl, tr, bl, br } je Viertel true = rund (GetMinimapShape: "ROUND", "SQUARE",
          "CORNER-<Viertel>" (nur dieses Viertel rund), "SIDE-<Seite>" (die beiden Viertel dieser Seite rund),
          "TRICORNER-<Viertel>" (dieses und die beiden Nachbarn rund); Unbekanntes gilt als rund)
      MapPins.MinimapInside(rechts, oben, form, rand) → true, wenn der Punkt samt Rand (Anteil des Halbmessers) noch
          ganz auf der Minikarte liegt – sonst wird er ausgeblendet, nie an den Rand geklemmt
      MapPins.MinimapPlace(px, py, sx, sy, breite, höhe, radius, blick, form, halbB, halbH, rand) → dx, dy in
          Bildpunkten vom Mittelpunkt der Minikarte oder nil (außerhalb). px/py Punkt, sx/sy Spieler (0–1 auf derselben
          Karte), breite/höhe der Karte in Yards (Discovery.MapYards).
    Dienst:
      MapPins.MinimapRefresh()  Punkte der Anbieter neu holen (Kartenwechsel, MapPins.Refresh, Anbieter neu)
      MapPins.MinimapUpdate()   Lage jetzt neu rechnen (sonst gedrosselt: MapPins.MINI_EVERY Sekunden, nur nach
                                Bewegung, Drehung, Zoom, drinnen/draußen oder neuen Punkten)
      MapPins.MinimapState()    → { on, reason, shown, total, map } – reason: "api" (kein GetViewRadius), "instance",
                                "position", "facing" (gedreht, aber kein Blickwinkel), "nosize" (Karte ohne Größe),
                                "nominimap", "none" (kein Anbieter mit minikarte), nil = an
      MapPins.MinimapLayer(), MapPins.MinimapGrip()   die Rahmen (für Tests und /dump)
      MapPins.MinimapPlaced()   → { { dx, dy, key, point } … } die gesetzten Punkte (Bildpunkte vom Mittelpunkt)
      MapPins.StatusLine()      → Zeile für /ez status oder nil
    Rahmen: EIN Rahmen als Kind von Minimap (nimmt keine Maus an), Punkte als Texturen aus einem Vorrat, Umkreissuche
    über einen Rasterindex je Karte. Der Tooltip kommt über EINEN Griff, der nur Mausbewegung annimmt
    (SetMouseClickEnabled(false)) – ein Klick geht durch auf die Minikarte, der Ping bleibt. Kennt der Client das nicht,
    gibt es keinen Griff (nur die Punkte, ohne Tooltip).
    Taint: kein SetPassThroughButtons, kein SetPropagateMouseClicks (im Kampf gesperrt), Minimap:SetZoom und Blizzards
    Symbole bleiben unberührt; der Rahmen ist ein eigenes, ungeschütztes Kind. Gezeichnet werden die Sammelpunkte von
    ezMap (Welle 15) über einen Anbieter mit minikarte.
]]
MapPins.MINI_SIZE = 12        -- Bildpunkte
MapPins.MINI_EVERY = 0.1      -- Sekunden zwischen zwei Neuberechnungen (Drossel)
MapPins.MINI_MOVE = 0.5       -- so weit (Yards) muss der Spieler gehen, damit neu gerechnet wird
MapPins.MINI_TURN = 0.02      -- so weit (Bogenmaß) muss er sich drehen (nur bei gedrehter Minikarte)
MapPins.MINI_MAX = 300        -- höchstens so viele Punkte gleichzeitig auf der Minikarte
MapPins.MINI_CELLS = 32       -- Rasterindex je Karte (Zellen je Achse) für die Umkreissuche
MapPins.HIDE_NEAR = true      -- Fähigkeitsmarke: dieser ezCore kennt das Feld nahAus|hideNear (Anbieter und Punkt)
MapPins.MINI_LEVEL = 5        -- Rahmenebene über der Minikarte

function MapPins.MinimapOffset(east, south, radius, facing)
    east, south, radius = Num(east), Num(south), Num(radius)
    if not (east and south and radius) or radius <= 0 then return nil end
    local e, n = east / radius, -south / radius
    local f = Num(facing)
    if not f then return e, n end
    -- gedreht: oben ist die Blickrichtung (−sin f, cos f), rechts (cos f, sin f)
    local c, s = math.cos(f), math.sin(f)
    return e * c + n * s, -e * s + n * c
end

local QUARTERS = { TOPLEFT = { "tl" }, TOPRIGHT = { "tr" }, BOTTOMLEFT = { "bl" }, BOTTOMRIGHT = { "br" } }
local SIDES = { TOP = { "tl", "tr" }, BOTTOM = { "bl", "br" }, LEFT = { "tl", "bl" }, RIGHT = { "tr", "br" } }
local NEIGHBOURS = { TOPLEFT = { "tl", "tr", "bl" }, TOPRIGHT = { "tr", "tl", "br" }, BOTTOMLEFT = { "bl", "tl", "br" },
    BOTTOMRIGHT = { "br", "tr", "bl" } }

function MapPins.MinimapRound(shape)
    shape = type(shape) == "string" and shape:upper() or "ROUND"
    if shape == "SQUARE" then return { tl = false, tr = false, bl = false, br = false } end
    local kind, where = shape:match("^(%a+)%-(%a+)$")
    local list = (kind == "CORNER" and QUARTERS[where]) or (kind == "SIDE" and SIDES[where])
        or (kind == "TRICORNER" and NEIGHBOURS[where])
    if not list then return { tl = true, tr = true, bl = true, br = true } end
    local out = { tl = false, tr = false, bl = false, br = false }
    for _, q in ipairs(list) do out[q] = true end
    return out
end

function MapPins.MinimapInside(right, up, shape, margin)
    right, up = Num(right), Num(up)
    if not (right and up) then return false end
    local limit = 1 - math.max(0, Num(margin) or 0)
    if limit <= 0 then return false end
    local quarter = (up >= 0 and "t" or "b") .. (right >= 0 and "r" or "l")
    local round = type(shape) == "table" and shape or MapPins.MinimapRound(shape)
    if round[quarter] then return right * right + up * up <= limit * limit end
    return math.abs(right) <= limit and math.abs(up) <= limit
end

function MapPins.MinimapPlace(px, py, sx, sy, w, h, radius, facing, shape, halfW, halfH, margin)
    px, py, sx, sy, w, h = Num(px), Num(py), Num(sx), Num(sy), Num(w), Num(h)
    halfW, halfH = Num(halfW), Num(halfH)
    if not (px and py and sx and sy and w and h and halfW and halfH) then return nil end
    local right, up = MapPins.MinimapOffset((px - sx) * w, (py - sy) * h, radius, facing)
    if not right or not MapPins.MinimapInside(right, up, shape, margin) then return nil end
    return right * halfW, up * halfH
end

local miniLayer, miniGrip
local miniTextures = {}
local miniLast = {}

local function MinimapFrame()
    local mm = rawget(_G, "Minimap")
    return type(mm) == "table" and mm.GetWidth and mm or nil
end

-- Anbieter mit Minikarten-Punkten, zwischengespeichert bis ein Anbieter kommt oder geht (Gesamtreview 18.11.2026, T8-5:
-- vorher je Takt eine neue Liste). Leser ändern die Liste nicht.
local miniList
function MapPins.ForgetMiniProviders() miniList = nil end
local function MiniProviders()
    if miniList then return miniList end
    local list = {}
    for _, key in ipairs(order) do
        local p = providers[key]
        if p.minimap then list[#list + 1] = p end
    end
    miniList = list
    return list
end

-- Speicherkarte des Spielers (Zone; dieselbe Regel wie die Entdecker-Datenbank) und seine Lage darauf
local function PlayerSpot()
    local best = Core.PlayerPosition and select(1, Core.PlayerPosition()) or nil
    if not best then return nil end
    local DB = Core.DB
    local map = DB and DB.Keys and DB.Keys.MapOf and DB.Keys.MapOf(best) or best
    local m, x, y = Core.PlayerPosition(map)
    if not m then return nil end
    return map, x, y
end

local function ClientRadius()
    local api = rawget(_G, "C_Minimap")
    if type(api) ~= "table" or type(api.GetViewRadius) ~= "function" then return nil end
    local ok, yards = pcall(api.GetViewRadius)
    yards = ok and not Core.IsSecret(yards) and Num(yards)
    return yards and yards > 0 and yards or nil
end

local function Rotating()
    local cvar = rawget(_G, "C_CVar")
    local get = (type(cvar) == "table" and cvar.GetCVar) or rawget(_G, "GetCVar")
    if type(get) ~= "function" then return false end
    local ok, value = pcall(get, "rotateMinimap")
    return ok and (value == "1" or value == 1 or value == true)
end

local function Facing()
    local fn = rawget(_G, "GetPlayerFacing")
    if type(fn) ~= "function" then return nil end
    local ok, f = pcall(fn)
    if not ok or Core.IsSecret(f) then return nil end
    return Num(f)
end

-- Für Module, die selbst etwas auf der Minikarte ausrichten (ezMaps Pfeil der Leveling-Route): dieselbe Abfrage statt
-- einer Kopie. MapPins.Rotating() → dreht sich die Minikarte mit? MapPins.Facing() → Blickrichtung oder nil (gesperrt)
MapPins.Rotating = Rotating
MapPins.Facing = Facing

local function Shape()
    local fn = rawget(_G, "GetMinimapShape")
    if type(fn) ~= "function" then return "ROUND" end
    local ok, shape = pcall(fn)
    return ok and type(shape) == "string" and shape or "ROUND"
end

local function MiniCell(x, y)
    local n = MapPins.MINI_CELLS
    local cx = math.min(n - 1, math.max(0, math.floor(x * n)))
    local cy = math.min(n - 1, math.max(0, math.floor(y * n)))
    return cx * n + cy
end

-- Umkreis je Anbieter, in dem die Minikarte seine Punkte auslässt (Feld nahAus|hideNear) → { schlüssel = Yards² }
local function MiniHideNear()
    local out = {}
    for _, p in ipairs(MiniProviders()) do
        local v = p.hideNear
        if type(v) == "function" then
            local ok, yards = Core.Try(p.owner, "MapPins " .. p.key .. " hideNear", v)
            v = ok and yards or nil
        end
        v = Num(v)
        if v and v > 0 then out[p.key] = v * v end
    end
    return out
end

-- Punkte der Anbieter für die Karte map (umgerechnet wie auf der Weltkarte), dazu ein Rasterindex
local function MiniGather(map)
    local out, grid, affine = {}, {}, {}
    for _, p in ipairs(MiniProviders()) do
        local show = true
        if p.visible then
            local ok, yes = Core.Try(p.owner, "MapPins " .. p.key .. " visible", p.visible, map, "minimap")
            show = ok and yes ~= false
        end
        local fn = type(p.minimap) == "function" and p.minimap or p.points
        if show then
            local ok, list = Core.Try(p.owner, "MapPins " .. p.key .. " minimap", fn, map)
            for _, point in ipairs(ok and type(list) == "table" and list or {}) do
                if #out >= MapPins.MAX then break end
                local x, y = Num(type(point) == "table" and point.x), Num(type(point) == "table" and point.y)
                local from = Num(type(point) == "table" and point.map)
                if x and y and from and from ~= map then
                    local conv = affine[from]
                    if conv == nil then
                        conv = Affine(map, from)
                        affine[from] = conv
                    end
                    if conv then x, y = conv(x, y) else x, y = nil, nil end
                end
                if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
                    local e = { x = x, y = y, key = p.key, point = point,
                        keep = point.nahAus == false or point.hideNear == false }   -- in der Nähe nicht auslassen
                    out[#out + 1] = e
                    local c = MiniCell(x, y)
                    local cell = grid[c]
                    if not cell then cell = {} grid[c] = cell end
                    cell[#cell + 1] = e
                end
            end
        end
    end
    return out, grid
end

local function MiniTexture(i)
    local tex = miniTextures[i]
    if not tex then
        tex = miniLayer:CreateTexture(nil, "OVERLAY")
        miniTextures[i] = tex
    end
    return tex
end

local function MiniHideAll()
    for i = 1, mini.shown do miniTextures[i]:Hide() end
    mini.shown = 0
    wipe(mini.placed)   -- leeren statt je Takt eine neue Tabelle (T8-5)
    if miniGrip then miniGrip:Hide() end
end

local function MiniOff(reason)
    mini.reason = reason
    mini.dirty = false   -- geprüft; ein Ereignis setzt es wieder (MinimapTick, T8-5)
    MiniHideAll()
    return 0
end

local function MiniShowTip(self)
    local e = self.entry
    local p = e and providers[e.key]
    if not (p and p.tooltip) then return end
    local tip = rawget(_G, "GameTooltip")
    if not tip then return end
    tip:SetOwner(self, "ANCHOR_RIGHT")
    local ok = Core.Try(p.owner, "MapPins " .. e.key .. " tooltip", p.tooltip, tip, e.point, mini.map)
    if ok then tip:Show() else tip:Hide() end
end

local function MiniGripFrame()
    if miniGrip ~= nil then return miniGrip or nil end
    local g = CreateFrame("Frame", "ezCoreMinimapPinsGrip", miniLayer)
    if type(g.SetMouseClickEnabled) ~= "function" or type(g.SetMouseMotionEnabled) ~= "function" then
        miniGrip = false
        g:Hide()
        return nil
    end
    g:SetMouseClickEnabled(false)     -- Klicks gehen durch auf die Minikarte (Ping)
    g:SetMouseMotionEnabled(true)     -- nur die Mausbewegung für den Tooltip
    g:SetScript("OnEnter", MiniShowTip)
    g:SetScript("OnLeave", function() local tip = rawget(_G, "GameTooltip") if tip then tip:Hide() end end)
    g:Hide()
    miniGrip = g
    return g
end

-- Griff auf den gesetzten Punkt unter der Maus legen (Mausstelle relativ zur Mitte der Minikarte)
local function MiniHover()
    local g = miniLayer and MiniGripFrame()
    if not g then return end
    local mm = MinimapFrame()
    local cx, cy = GetCursorPosition()
    local scale = Num(mm and mm.GetEffectiveScale and mm:GetEffectiveScale()) or 1
    local mx, my
    if mm and mm.GetCenter then mx, my = mm:GetCenter() end
    mx, my, cx, cy = Num(mx), Num(my), Num(cx), Num(cy)
    local best, bestD
    if mx and my and cx and cy and scale > 0 then
        local rx, ry = cx / scale - mx, cy / scale - my
        for _, e in ipairs(mini.placed) do
            local d = math.sqrt((e.dx - rx) ^ 2 + (e.dy - ry) ^ 2)
            if d <= MapPins.HIT and (not bestD or d < bestD) then best, bestD = e, d end
        end
    end
    if not best then
        if g:IsShown() then
            g:Hide()
            local tip = rawget(_G, "GameTooltip")
            if tip and tip.IsOwned and tip:IsOwned(g) then tip:Hide() end
        end
        g.entry = nil
        return
    end
    if g.entry == best and g:IsShown() then return end
    g.entry = best
    local s = Num(best.point.size) or MapPins.MINI_SIZE
    g:SetSize(s, s)
    g:ClearAllPoints()
    g:SetPoint("CENTER", miniLayer, "CENTER", best.dx, best.dy)
    g:Show()
end

local function MiniPlace(e, n, dx, dy)
    local tex = MiniTexture(n)
    local p = e.point
    MapPins.SetSymbol(tex, p)
    local s = Num(p.size) or MapPins.MINI_SIZE
    tex:SetSize(s, s)
    tex:ClearAllPoints()
    tex:SetPoint("CENTER", miniLayer, "CENTER", dx, dy)
    tex:SetVertexColor(Num(p.r) or 1, Num(p.g) or 1, Num(p.b) or 1, Num(p.a) or 1)
    tex:Show()
    e.dx, e.dy = dx, dy
    mini.placed[#mini.placed + 1] = e
end

local function MiniLayerFrame(mm)
    if miniLayer then return miniLayer end
    miniLayer = CreateFrame("Frame", "ezCoreMinimapPins", mm)
    miniLayer:SetAllPoints(mm)
    if miniLayer.EnableMouse then miniLayer:EnableMouse(false) end
    if miniLayer.SetFrameLevel and mm.GetFrameLevel then
        local level = Num(mm:GetFrameLevel())
        if level then miniLayer:SetFrameLevel(level + MapPins.MINI_LEVEL) end
    end
    miniLayer:SetScript("OnUpdate", function(_, elapsed) MapPins.MinimapTick(elapsed) end)
    miniLayer:Show()
    return miniLayer
end

function MapPins.MinimapUpdate()
    local mm = MinimapFrame()
    if not mm then return MiniOff("nominimap") end
    if #MiniProviders() == 0 then return MiniOff("none") end
    MiniLayerFrame(mm)
    local radius = ClientRadius()
    if not radius then return MiniOff("api") end
    if Core.InInstance() == true then return MiniOff("instance") end
    local map, sx, sy = PlayerSpot()
    if not map then return MiniOff("position") end
    local facing
    if Rotating() then
        facing = Facing()
        if not facing then return MiniOff("facing") end
    end
    local D = Core.Discovery
    local w, h
    if D and D.MapYards then w, h = D.MapYards(map) end
    if not w then return MiniOff("nosize") end
    if mini.map ~= map then
        mini.map = map
        mini.points, mini.grid = MiniGather(map)
    end
    mini.reason = nil
    miniLast = { map = map, x = sx, y = sy, f = facing, r = radius }
    MiniHideAll()
    local halfW, halfH = (Num(mm:GetWidth()) or 0) / 2, (Num(mm:GetHeight()) or 0) / 2
    if halfW <= 0 or halfH <= 0 then return 0 end
    local shape = MapPins.MinimapRound(Shape())
    local margin = (MapPins.MINI_SIZE / 2) / halfW
    local hide = MiniHideNear()
    -- nur die Zellen im Umkreis des Sichtradius (Diagonale der eckigen Form: × 1,5)
    local n = MapPins.MINI_CELLS
    local reachX, reachY = math.ceil(radius * 1.5 / w * n), math.ceil(radius * 1.5 / h * n)
    local cx, cy = math.floor(sx * n), math.floor(sy * n)
    for gx = math.max(0, cx - reachX), math.min(n - 1, cx + reachX) do
        for gy = math.max(0, cy - reachY), math.min(n - 1, cy + reachY) do
            for _, e in ipairs(mini.grid[gx * n + gy] or {}) do
                if mini.shown >= MapPins.MINI_MAX then break end
                local near2 = hide[e.key]
                local dx, dy
                if not (near2 and not e.keep and ((e.x - sx) * w) ^ 2 + ((e.y - sy) * h) ^ 2 < near2) then
                    dx, dy = MapPins.MinimapPlace(e.x, e.y, sx, sy, w, h, radius, facing, shape, halfW, halfH, margin)
                end
                if dx then
                    mini.shown = mini.shown + 1
                    MiniPlace(e, mini.shown, dx, dy)
                end
            end
        end
    end
    mini.dirty = false
    MiniHover()
    return mini.shown
end

function MapPins.MinimapRefresh()
    mini.map, mini.points, mini.grid = nil, {}, {}
    mini.dirty = true
    return MapPins.MinimapUpdate()
end

-- Gründe, aus denen die Minikarten-Punkte aus sind und die nur ein Ereignis ändert (Instanz, kein Anbieter, keine
-- Minikarte): dann prüft der Takt nicht mehr 10× je Sekunde neu, sondern erst nach einem Ereignis (ZONE_CHANGED*,
-- PLAYER_ENTERING_WORLD, MINIMAP_UPDATE_ZOOM, ein Anbieter kommt oder geht – mini.dirty bzw. MinimapRefresh).
-- Gesamtreview 18.11.2026, T8-5. Lage, Blickrichtung, Sichtradius oder Kartengröße unbekannt kann sich ohne Ereignis
-- ändern: das prüft der Takt weiter, legt dabei aber keine Tabellen mehr an (Anbieterliste zwischengespeichert,
-- mini.placed geleert statt ersetzt).
MapPins.MINI_STICKY = { instance = true, none = true, nominimap = true }

-- Gedrosselt: höchstens alle MINI_EVERY Sekunden, und nur, wenn sich etwas geändert hat
function MapPins.MinimapTick(elapsed)
    mini.since = mini.since + (Num(elapsed) or 0)
    if mini.reason ~= nil and not mini.dirty and MapPins.MINI_STICKY[mini.reason] then
        mini.since = 0
        return
    end
    if mini.since < MapPins.MINI_EVERY then return end
    mini.since = 0
    if not mini.dirty and mini.reason == nil then
        local map, sx, sy = PlayerSpot()
        local D = Core.Discovery
        local w, h
        if map and D and D.MapYards then w, h = D.MapYards(map) end
        local moved = map ~= miniLast.map or not (w and sx and miniLast.x)
            or math.sqrt(((sx - miniLast.x) * w) ^ 2 + ((sy - miniLast.y) * h) ^ 2) >= MapPins.MINI_MOVE
        local turned = false
        if Rotating() then
            local f = Facing()
            turned = f == nil or miniLast.f == nil or math.abs(f - miniLast.f) >= MapPins.MINI_TURN
        elseif miniLast.f ~= nil then
            turned = true
        end
        if not (moved or turned or ClientRadius() ~= miniLast.r) then
            MiniHover()
            return
        end
    end
    MapPins.MinimapUpdate()
end

function MapPins.MinimapState()
    return { on = mini.reason == nil, reason = mini.reason, shown = mini.shown, total = #mini.points, map = mini.map }
end
function MapPins.MinimapLayer() return miniLayer end
-- gesetzte Punkte: { { dx, dy, key, point } … } (Kopien; für Prüfungen und /dump)
function MapPins.MinimapPlaced()
    local out = {}
    for i, e in ipairs(mini.placed) do out[i] = { dx = e.dx, dy = e.dy, key = e.key, point = e.point } end
    return out
end
function MapPins.MinimapGrip() return miniGrip or nil end

-- Zeile für /ez status: wenn ein Anbieter Minikarten-Punkte liefert oder der Client keinen Sichtradius kennt
function MapPins.StatusLine()
    local L = Core.L
    if #MiniProviders() == 0 then
        if ClientRadius() == nil and MinimapFrame() then return L.MINIPINS_STATUS_OFF:format(L.MINIPINS_REASON_api) end
        return nil
    end
    if mini.reason then return L.MINIPINS_STATUS_OFF:format(L["MINIPINS_REASON_" .. mini.reason] or mini.reason) end
    return L.MINIPINS_STATUS_ON:format(mini.shown, #mini.points)
end

local function MiniDirty() mini.dirty = true end
for _, event in ipairs({ "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "PLAYER_ENTERING_WORLD" }) do
    ns.On(event, function() Core.Try(nil, "MapPins.MinimapRefresh", MapPins.MinimapRefresh) end)
end
for _, event in ipairs({ "MINIMAP_UPDATE_ZOOM", "ZONE_CHANGED_INDOORS" }) do ns.On(event, MiniDirty) end
ns.On("CVAR_UPDATE", function(_, name) if name == "rotateMinimap" then MiniDirty() end end)
