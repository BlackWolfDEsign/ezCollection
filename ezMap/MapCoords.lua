local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Koordinaten auf Blizzards Weltkarte: deine Position und die Stelle unter dem Mauszeiger (Entscheidung des Nutzers
    13.11.2026: „Koordinaten auf der Weltkarte nach ezMap“; vorher zeichnete sie ezPanels Ort-Baustein).

    Eine Textzeile unten links auf der Kartenfläche – ein Kind von Blizzards Kartenrahmen, kein eigenes Fenster; sie
    wandert und verschwindet mit der Karte und nimmt keine Klicks an. Sie liegt auf der Ebene „HIGH“ wie Blizzards
    eigene Knöpfe über der Karte (Forever-Quelle Blizzard_WorldMap/Blizzard_WorldMapTemplates.xml:
    WorldMapTrackingPinButtonTemplate, frameStrata="HIGH"), denn Blizzards Kartensymbole und die Flächen der erkundeten
    Gebiete haben Rahmenstufen ab 2000 (Blizzard_MapCanvas/MapCanvas_PinFrameLevelsManager.lua) und lägen sonst über
    dem Text. Gelesen wird nur:
      - deine Position auf der gezeigten Karte über Core.PlayerPosition (ezCore prüft gesperrte Werte)
      - die Stelle unter dem Mauszeiger über Blizzards eigene Kartenfläche (Forever-Quelle
        Blizzard_MapCanvas/MapCanvas_ScrollContainerMixin.lua: GetNormalizedCursorPosition, Werte von 0 bis 1);
        jeder Wert geht zuerst durch ezCore, ein gesperrter oder fehlender Wert zeigt nichts
    Geschrieben wird in Blizzards Karte nichts. Text über Core.CoordText (eine Nachkommastelle wie bei /way).

    Rücksicht: Zeigt ein anderes Addon Koordinaten auf der Weltkarte (Leatrix Maps, Tweaks Forever –
    Core.WhoHandles("mapCoords")), zeichnet ezMap nicht und nennt es im Kartenmenü und im Status.
    Für ezPanel: ezCore.API("ezMap").MapCoords() und .SetMapCoords(an) (Core.lua) – ezPanel zeigt seine eigene Zeile
    nur noch, solange ezMap sie nicht anbietet.
]]
local Coords = {}
ns.MapCoords = Coords

Coords.INTERVAL = 0.1       -- Sekunden zwischen zwei Aktualisierungen, solange die Karte offen ist
Coords.GAP = "     "        -- Abstand zwischen „Du“ und „Maus“
Coords.STRATA = "HIGH"      -- Ebene über Blizzards Kartensymbolen (wie Blizzards Knöpfe über der Karte)
Coords.LEVEL_OFFSET = 20    -- Rahmenstufen über Blizzards Kartenfläche (innerhalb der Ebene)

local frame, hooked

local function Map() return rawget(_G, "WorldMapFrame") end

-- Blizzards Kartenfläche (ScrollContainer), an der die Zeile hängt und die den Mauszeiger kennt.
local function Container(map)
    if not map then return nil end
    local container = map.ScrollContainer
    if type(container) ~= "table" and type(map.GetCanvasContainer) == "function" then
        container = map:GetCanvasContainer()
    end
    return type(container) == "table" and container or nil
end

-- Wer Koordinaten auf der Weltkarte schon zeigt (Leatrix Maps, Tweaks Forever), sonst nil.
function Coords.Elsewhere() return ns.OtherFor("mapCoords") end

-- Zeichnet ezMap die Zeile? Schalter an und kein anderes Addon zuständig.
function Coords.Wanted() return ns.Enabled("mapCoords") and not Coords.Elsewhere() end

-- Zustand für andere Module: true | false, "off" | false, "other", Name des anderen Addons.
function Coords.State()
    local other = Coords.Elsewhere()
    if other then return false, "other", other end
    if not ns.Enabled("mapCoords") then return false, "off" end
    return true
end

-- Schalter setzen (Kartenmenü, Schnittstelle). Rückgabe wie Coords.State.
function Coords.Set(on)
    ns.SetSetting("mapCoords", on and true or false)
    return Coords.State()
end

-- Gezeigte Karte (uiMapID) oder nil.
local function ShownMap(map)
    if not (map and type(map.GetMapID) == "function") then return nil end
    local ok, mapID = pcall(map.GetMapID, map)
    return ok and ns.Num(mapID) or nil
end

-- Stelle unter dem Mauszeiger auf der Kartenfläche: x, y von 0 bis 1 oder nil (Maus nicht über der Karte, Wert
-- gesperrt oder Schnittstelle fehlt).
function Coords.Cursor()
    local container = Container(Map())
    if not (container and type(container.GetNormalizedCursorPosition) == "function") then return nil end
    if type(container.IsMouseOver) == "function" then
        local okOver, over = pcall(container.IsMouseOver, container)
        if not okOver or not Core.Bool(over, false) then return nil end
    end
    local ok, x, y = pcall(container.GetNormalizedCursorPosition, container)
    if not ok then return nil end
    x, y = ns.Num(x), ns.Num(y)
    if not (x and y) or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    return x, y
end

-- Dein Teil der Zeile für die gezeigte Karte. Drei Fälle, jeder mit eigenem Text statt einer leeren Zeile:
--   Position auf der gezeigten Karte lesbar           „Du: 45.3, 32.1“
--   du stehst nachweislich auf einer anderen Karte    „Du: nicht auf dieser Karte“
--   sonst (Instanz, gesperrter Wert, Ladebildschirm)  „Du: Position gerade nicht bekannt“
-- „Nicht auf dieser Karte“ behauptet ezMap nur, wenn der Client deine Position auf deiner eigenen Karte hergibt und
-- das eine andere ist als die gezeigte.
function Coords.PlayerText(mapID)
    local _, px, py
    if mapID then _, px, py = ns.PlayerPosition(mapID) end
    if px then return L.COORDS_PLAYER:format(ns.CoordText(px, py)) end
    local own = ns.PlayerPosition()
    if own and mapID and own ~= mapID then return L.COORDS_PLAYER_NONE end
    return L.COORDS_PLAYER_UNKNOWN
end

-- Text der Zeile: „Du: 45.3, 32.1     Maus: 50.0, 60.2“.
function Coords.Text()
    local text = Coords.PlayerText(ShownMap(Map()))
    local cx, cy = Coords.Cursor()
    if cx then text = text .. Coords.GAP .. L.COORDS_CURSOR:format(ns.CoordText(cx, cy)) end
    return text
end

function Coords.Update()
    if frame and frame.Text then frame.Text:SetText(Coords.Text()) end
end

local function OnUpdate(self, elapsed)
    self.since = (self.since or 0) + elapsed
    if self.since < Coords.INTERVAL then return end
    self.since = 0
    ns.Try("MapCoords", Coords.Update)
end

-- Rahmenstufe für die Zeile innerhalb ihrer Ebene: etwas über der Kartenfläche. Ist Blizzards Stufe nicht lesbar
-- (gesperrt, fehlt), nil – dann bleibt die Stufe, die ein Kind von selbst bekommt. Über Blizzards Kartensymbole
-- hebt die Zeile nicht die Stufe, sondern die Ebene (Coords.STRATA).
function Coords.LevelAbove(parent)
    if not (parent and type(parent.GetFrameLevel) == "function") then return nil end
    local ok, level = pcall(parent.GetFrameLevel, parent)
    level = ok and ns.Num(level) or nil
    return level and level + Coords.LEVEL_OFFSET or nil
end

-- Zeile an Blizzards Kartenfläche anlegen (einmal, sobald die Weltkarte geladen ist).
function Coords.Create()
    local map = Map()
    if frame or not map then return frame end
    local parent = Container(map) or map
    frame = CreateFrame("Frame", "ezMapWorldMapCoords", parent)
    frame:SetSize(320, 18)
    frame:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 8, 6)
    if frame.SetFrameStrata then frame:SetFrameStrata(Coords.STRATA) end    -- über Blizzards Kartensymbolen
    local level = Coords.LevelAbove(parent)
    if level and frame.SetFrameLevel then frame:SetFrameLevel(level) end
    if frame.EnableMouse then frame:EnableMouse(false) end     -- Klicks gehören der Karte
    frame.Text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.Text:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    if frame.Text.SetJustifyH then frame.Text:SetJustifyH("LEFT") end
    if frame.Text.SetShadowOffset then frame.Text:SetShadowOffset(1, -1) end
    frame:SetScript("OnUpdate", OnUpdate)
    frame:Hide()
    if not hooked and map.HookScript then
        hooked = true
        -- beim Öffnen der Karte neu entscheiden: ein anderes Addon kann seine Koordinaten inzwischen eingeschaltet haben
        map:HookScript("OnShow", function() ns.Try("MapCoords", Coords.Refresh) end)
    end
    Coords.Refresh()
    return frame
end

-- Zeile zeigen oder verstecken. Rückgabe: true, wenn sie gezeigt wird.
function Coords.Refresh()
    if not frame then return false end
    local want = Coords.Wanted()
    frame:SetShown(want)
    if want then Coords.Update() end
    return want
end

function Coords.Frame() return frame end

-- Kartenmenü: Schalter für die Zeile; zeigt ein anderes Addon die Koordinaten, steht dort dessen Name. Mit hintOnly
-- nur dieser Hinweis (der Schalter steht dann schon im Baum des ezMap-Knopfs, MapButton.TreeInMenu).
function Coords.AddMenuToggle(root, hintOnly)
    local other = Coords.Elsewhere()
    if other then
        ns.MapButton.OtherTitle(root, L.MENU_MAP_COORDS_OTHER:format(other))
        return false
    end
    if hintOnly then return false end
    -- Erklärzeile wie auf der Einstellungsseite (OPT_mapCoords_TIP)
    ns.MapButton.Toggle(root, L.MENU_MAP_COORDS, "mapCoords", function(on) Coords.Set(on) end)
    return true
end

ns.OnReady(function()
    ns.WhenAddOnLoaded("Blizzard_WorldMap", function() ns.Try("MapCoords", Coords.Create) end)
end)

ns.OnSettingChanged(function(key)
    if key == "mapCoords" then Coords.Refresh() end
end)

ns.AddStatusLine(function()
    local other = Coords.Elsewhere()
    if other then return L.STATUS_COORDS_OTHER:format(other) end
    if ns.Enabled("mapCoords") then return L.STATUS_COORDS_ON end
    return L.STATUS_COORDS_OFF
end)
