local _, ns = ...
local L = ns.L

--[[
    Ort (Titan Location): Zone, Unterzone und Koordinaten, eingefärbt nach
    PvP-Status wie der Zonenname an der Minikarte; Koordinaten auf der Weltkarte.
    Verbesserungen: kein Timer-Leck, Koordinaten nur neu gezeichnet, wenn sie
    sich ändern; Shift+Klick öffnet die Chatzeile selbst; die Weltkarte zeigt
    die Spielerposition auf der gerade angezeigten Karte.
    Position und Kartenname aus ezCore (PlayerPosition, MapName) – eine Fassung mit ezMap.
    Koordinaten auf der Weltkarte (PANEL-16, V-080; Entscheidung des Nutzers 13.11.2026: „nach ezMap verlegen“):
    Bietet ezMap sie an (ezCore.API("ezMap").MapCoords/SetMapCoords, seit Welle 3), zeichnet ezPanel keine eigene
    Zeile mehr; Menü und Tooltip nennen ezMap, der Menüpunkt schaltet ezMaps Schalter. Ohne dieses Angebot (ezMap aus
    oder zu alt) bleibt ezPanels eigene Zeile als Rückfall, wie bisher mit Rücksicht auf Leatrix Maps und Tweaks
    Forever (ezCore.WhoHandles("mapCoords")). Einmalige Übergabe: siehe HandOver unten.
]]

local block = ns.RegisterBlock({
    id = "location",
    command = "ort",
    name = L.LOC_NAME,
    label = L.LOC_LABEL,
    icon = "Interface\\Icons\\INV_Misc_Map_01",
    events = { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" },
    colorable = true,
    defaults = {
        -- Ab-Werk-Platz = Ziel von „Zurücksetzen“ (Spieltest 20.11.2026, Bildschirmfoto des Nutzers 23:37, wörtlich „das
        -- ezpanel sollte nach dem zurücksetzen aber wie auf zweiten bild angeordnet sein“): links Lautstärke, XP, Gold,
        -- Taschen, Haltbarkeit; Mitte Freunde; rechts außen Ort, dann die Uhr – hinter allen anderen rechts (auch den
        -- LDB-Anzeigen, 900), wo Blizzards Kästchen mit Ort und Uhr stand
        enabled = true, zone = "right", order = 960, label = false,
        showZone = true,
        showSubzone = true,
        coords = true,
        precision = 1,
        mapCoords = true,
    },
    hints = { L.LOC_HINT_LEFT, ezCore.ClickText("left", "SHIFT", L.LOC_HINT_SHIFT) },   -- Klick-Hinweis über ezCore (T18-9)
})

---------------------------------------------------------------------------
-- Koordinaten
---------------------------------------------------------------------------

-- Eigene Position (0 bis 1) und die Karte dazu, sonst nil (ezCore prüft gesperrte Werte).
local function PlayerPosition(mapID)
    local id, x, y = ezCore.PlayerPosition(mapID)
    if not id then return nil end
    return x, y, id
end

local CoordText = ezCore.CoordText   -- (x, y von 0 bis 1, Nachkommastellen) → „45.3, 32.2“

local lastCoords
local ticker

local function Poll()
    local x, y = PlayerPosition()
    local text = x and CoordText(x, y, block.cfg.precision) or nil
    if text ~= lastCoords then
        lastCoords = text
        ns.QueueUpdate(block)
    end
end

local function UpdatePolling()
    local want = block.cfg.enabled and block.cfg.coords
    if want and not ticker then
        ticker = C_Timer.NewTicker(0.2, Poll)
    elseif not want and ticker then
        ticker:Cancel()
        ticker = nil
    end
end

function block:OnEnable()
    UpdatePolling()
    ns.UpdateMapCoords()
end

function block:OnDisable()
    UpdatePolling()
    ns.UpdateMapCoords()
end

-- Profilwechsel: Abfrage der Koordinaten und Anzeige auf der Weltkarte folgen den neuen Optionen.
function block:OnConfigChanged()
    lastCoords = nil
    UpdatePolling()
    if self.cfg.coords then Poll() end
    ns.UpdateMapCoords()
end

---------------------------------------------------------------------------
-- Farben wie an der Minikarte
---------------------------------------------------------------------------

-- Wie Blizzards Minikarte (Blizzard_Minimap/Mainline/Minimap.lua, Minimap_Update, Zweig forever; Design-System 2.5,
-- Welle 22 – vorher eigene Farbcodes): Arena, Freundlich, Feindlich und Kampfgebiet sind dort genau Blizzards Grün bzw.
-- Rot (0.1, 1, 0.1 bzw. 1, 0.1, 0.1 = GREEN_FONT_COLOR/RED_FONT_COLOR, Rollen „good“/„bad“); Zuflucht und umkämpft
-- haben bei Blizzard kein Farbobjekt, nur diese Zahlen.
local PVP_ROLE = { arena = "bad", friendly = "good", hostile = "bad", combat = "bad" }
local PVP_RGB = { sanctuary = { 0.41, 0.8, 0.94 }, contested = { 1, 0.7, 0 } }
local function PvpColor(pvpType)
    local role = PVP_ROLE[pvpType]
    if role then
        local r, g, b = ezCore.Style.Color(role)
        return ezCore.ColorCode(r, g, b)
    end
    local rgb = PVP_RGB[pvpType]
    if rgb then return ezCore.ColorCode(rgb[1], rgb[2], rgb[3]) end
    return ns.GOLD
end

local function PvpInfo()
    if C_PvP and C_PvP.GetZonePVPInfo then return C_PvP.GetZonePVPInfo() end
    if GetZonePVPInfo then return GetZonePVPInfo() end
end

local function PvpText(pvpType, faction)
    if pvpType == "sanctuary" then return SANCTUARY_TERRITORY or L.LOC_SANCTUARY end
    if pvpType == "arena" then return FREE_FOR_ALL_TERRITORY or L.LOC_ARENA end
    if pvpType == "friendly" or pvpType == "hostile" then
        return FACTION_CONTROLLED_TERRITORY and faction and FACTION_CONTROLLED_TERRITORY:format(faction) or nil
    end
    if pvpType == "contested" then return CONTESTED_TERRITORY or L.LOC_CONTESTED end
    if pvpType == "combat" then return COMBAT_ZONE or nil end
end

local function Names()
    local zone = GetRealZoneText and GetRealZoneText() or GetZoneText()
    local sub = GetSubZoneText()
    if sub == zone then sub = "" end
    return zone or "", sub or ""
end

---------------------------------------------------------------------------
-- Anzeige
---------------------------------------------------------------------------

function block:GetText()
    local cfg = self.cfg
    local zone, sub = Names()
    local parts = {}
    if cfg.showZone or sub == "" then parts[#parts + 1] = zone end
    if cfg.showSubzone and sub ~= "" then parts[#parts + 1] = sub end
    local text = table.concat(parts, ": ")
    local color = PvpColor(PvpInfo())
    text = color .. text .. "|r"
    if cfg.coords then
        text = text .. " " .. ns.White("(" .. (lastCoords or "–") .. ")")
    end
    return text
end

function block:OnTooltip(tooltip)
    local zone, sub = Names()
    local pvpType, _, faction = PvpInfo()
    local color = PvpColor(pvpType)
    tooltip:AddDoubleLine(L.LOC_ZONE, color .. zone .. "|r")
    if sub ~= "" then tooltip:AddDoubleLine(L.LOC_SUBZONE, color .. sub .. "|r") end
    local pvp = PvpText(pvpType, faction)
    if pvp then tooltip:AddLine(color .. pvp .. "|r") end
    local x, y, mapID = PlayerPosition()
    ns.TipDoubleLine(tooltip, L.LOC_COORDS, x and CoordText(x, y, 2) or L.LOC_NO_COORDS, "normal", "highlight")
    -- Gilt die Position für eine andere Karte als die Zone (Stadt, Höhle, Ebene), steht sie darunter.
    local mapName = mapID and ezCore.MapName(mapID)
    if mapName and mapName ~= "#" .. mapID and mapName ~= zone and mapName ~= sub then
        ns.TipDoubleLine(tooltip, L.LOC_MAP_NAME, mapName, "normal", "highlight")
    end
    ns.TipDoubleLine(tooltip, L.LOC_MAP_COORDS, ns.MapCoordsText(self.cfg), "normal", "highlight")
    local hearth = GetBindLocation and GetBindLocation()
    if hearth then ns.TipDoubleLine(tooltip, L.HEARTH, hearth, "normal", "highlight") end
    ns.TipDoubleLine(tooltip, L.LOC_REALM, GetRealmName(), "normal", "highlight")
end

local function ShareLocation()
    local zone, sub = Names()
    local text = zone
    if sub ~= "" then text = text .. ", " .. sub end
    local x, y = PlayerPosition()
    if x then text = text .. " (" .. CoordText(x, y, 1) .. ")" end
    -- In die Chatzeile (offenes Eingabefeld oder neue Eingabe); gesendet wird nie.
    return ezCore.OpenChatWith(text)
end

local function OpenMap() return ezCore.TogglePanel("map") end

block.actions = {
    { text = L.LOC_OPEN_MAP, fn = OpenMap },
    { text = L.LOC_SHARE, fn = ShareLocation },
}

function block:OnClick(button)
    if button ~= "LeftButton" then return end
    if IsShiftKeyDown() then return ShareLocation() end
    OpenMap()
end

function block:OnMenu(root)
    local cfg = self.cfg
    local bar = root:CreateButton(L.MENU_BAR_SHOWS)
    ns.MenuCheck(bar, L.LOC_SHOW_ZONE, cfg, "showZone", self)
    ns.MenuCheck(bar, L.LOC_SHOW_SUBZONE, cfg, "showSubzone", self)
    ns.MenuCheck(bar, L.LOC_SHOW_COORDS, cfg, "coords", self, function()
        lastCoords = nil
        UpdatePolling()
        Poll()
    end)
    local precision = root:CreateButton(L.LOC_PRECISION)
    for digits = 0, 2 do
        ns.MenuRadio(precision, CoordText(0.45123, 0.67891, digits), cfg, "precision", digits, self, function()
            lastCoords = nil
            Poll()
        end)
    end
    ns.AddMapCoordsMenu(root, cfg, self)
end

---------------------------------------------------------------------------
-- Koordinaten auf der Weltkarte
---------------------------------------------------------------------------

local mapFrame

-- Zeigt schon ein anderes Addon Koordinaten auf der Weltkarte (Leatrix Maps)? Erkennung in ezCore.
local function LeatrixMapCoords()
    return ns.OtherFor("mapCoords") ~= nil
end

-- Bietet ezMap die Koordinaten auf der Weltkarte an? → seine Schnittstelle oder nil.
local function EzMapCoords()
    local api = ezCore.API("ezMap")
    if type(api) == "table" and type(api.MapCoords) == "function" and type(api.SetMapCoords) == "function" then
        return api
    end
    return nil
end
ns.EzMapCoords = EzMapCoords

-- Zustand bei ezMap: true | false, "off" | false, "other", Name des anderen Addons – nil ohne Angebot.
local function EzMapState()
    local api = EzMapCoords()
    if not api then return nil end
    local ok, on, why, who = pcall(api.MapCoords)
    if not ok then return nil end
    return on == true, why, who
end

--[[
    Einmalige Übergabe der Einstellung an ezMap (PANEL-16): Was auf der Karte zu sehen war, bleibt zu sehen.
    Zeigte ezPanel die Zeile (Baustein an, „Koordinaten auf der Weltkarte“ an) und ist ezMaps Schalter aus, schaltet
    ezPanel ihn einmal ein. Ein „aus“ wird nicht übergeben: ezMaps eigene Zeile stand seit Welle 3 schon da (eigener
    Schalter, ab Werk an) – wer ezPanels Häkchen abgewählt hatte, sah weiter ezMaps Zeile. Gemerkt in
    ezPanelDB.mapCoordsToEzMap (nicht im Profil); ezPanels eigener Wert bleibt für den Rückfall ohne ezMap stehen.
]]
local function HandOver()
    local api = EzMapCoords()
    if not api or type(ns.db) ~= "table" or ns.db.mapCoordsToEzMap then return end
    ns.db.mapCoordsToEzMap = true
    local cfg = block.cfg
    if not (cfg and cfg.enabled and cfg.mapCoords) then return end
    local on, why = EzMapState()
    if on == false and why == "off" then pcall(api.SetMapCoords, true) end
end
ns.MapCoordsHandOver = HandOver

local function MapUpdate(self, elapsed)
    self.acc = (self.acc or 0) + elapsed
    if self.acc < 0.05 then return end
    self.acc = 0
    local map = WorldMapFrame
    local mapID = map.GetMapID and map:GetMapID()
    local px, py = PlayerPosition(mapID)
    local text = L.LOC_MAP_PLAYER .. " " .. (px and CoordText(px, py, 1) or "–")
    local scroll = map.ScrollContainer
    if scroll and scroll:IsMouseOver() and scroll.GetNormalizedCursorPosition then
        local cx, cy = scroll:GetNormalizedCursorPosition()
        if cx and cx >= 0 and cx <= 1 and cy >= 0 and cy <= 1 then
            text = text .. "     " .. L.LOC_MAP_CURSOR .. " " .. CoordText(cx, cy, 1)
        end
    end
    self.text:SetText(text)
end

function ns.UpdateMapCoords()
    local map = _G.WorldMapFrame
    if not map then return end
    local want = block.cfg.enabled and block.cfg.mapCoords and not LeatrixMapCoords() and not EzMapCoords()
    if want and not mapFrame then
        local parent = map.ScrollContainer or map
        mapFrame = CreateFrame("Frame", nil, parent)
        -- Ebene „HIGH“ wie ezMaps Zeile und Blizzards Knöpfe über der Karte: Blizzards Kartensymbole haben
        -- Rahmenstufen ab 2000 und lägen sonst über dem Text (Forever-Quelle MapCanvas_PinFrameLevelsManager.lua).
        mapFrame:SetFrameStrata("HIGH")
        mapFrame:SetFrameLevel(parent:GetFrameLevel() + 20)
        mapFrame:SetSize(300, 18)
        mapFrame:SetPoint("BOTTOM", parent, "BOTTOM", 0, 6)
        mapFrame.text = mapFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        mapFrame.text:SetPoint("CENTER")
        mapFrame.text:SetShadowOffset(1, -1)
        mapFrame:SetScript("OnUpdate", MapUpdate)
    end
    if mapFrame then mapFrame:SetShown(want and true or false) end
end

ns.OnReady(function()
    C_Timer.After(1, function()
        HandOver()
        ns.UpdateMapCoords()
    end)
end)
ns.On("ADDON_LOADED", function(_, name)
    if name == "Blizzard_WorldMap" and ns.ready then ns.UpdateMapCoords() end
end)

-- Wer zeichnet die Koordinaten auf der Weltkarte? Text für den Tooltip des Bausteins.
function ns.MapCoordsText(cfg)
    local on, why, who = EzMapState()
    if on ~= nil then
        if on then return L.LOC_MAP_COORDS_BY:format("ezMap") end
        if why == "other" then return L.LOC_MAP_COORDS_BY:format(tostring(who or "?")) end
        return L.LOC_MAP_COORDS_EZMAP_OFF
    end
    local other = ns.OtherFor("mapCoords")
    if other then return L.LOC_MAP_COORDS_BY:format(other) end
    return (cfg and cfg.mapCoords) and L.ON or L.OFF
end

-- Menüpunkt „Koordinaten auf der Weltkarte“: mit ezMaps Angebot dessen Schalter, sonst ezPanels eigener.
function ns.AddMapCoordsMenu(root, cfg, def)
    local api = EzMapCoords()
    if not api then
        return ns.MenuCheck(root, L.LOC_MAP_COORDS, cfg, "mapCoords", def, function() ns.UpdateMapCoords() end)
    end
    local _, why, who = EzMapState()
    if why == "other" then
        return root:CreateTitle(L.LOC_MAP_COORDS .. ": " .. L.LOC_MAP_COORDS_BY:format(tostring(who or "?")))
    end
    return root:CreateCheckbox(L.LOC_MAP_COORDS_EZMAP, function() return (EzMapState()) == true end, function()
        pcall(api.SetMapCoords, not ((EzMapState()) == true))
        if def then ns.QueueUpdate(def) end
        return MenuResponse and MenuResponse.Refresh
    end)
end
