local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Zonenstufen im Kartenmenü (MAP-06, DG-47; Welle 10 – Empfehlung umgesetzt, Antwort offen).

    Forever liefert für seine Gebiete keine Zonenstufen (Spieltest 14.11.2026: ezCore.Dungeons.ZoneLevels → nil,
    "nodata"; C_Map.GetMapLevels gibt es, bleibt aber leer), Blizzards Kartenbeschriftung zeigt also keine. Eine
    Tabelle aus einem fremden Addon kommt nicht in Frage (Leitlinie 10), eine eigene Tabelle gibt es nicht (EC-08).
    Reihenfolge der Quellen (Leitlinie 11):
      1. der Client (Dungeons.ZoneLevels) – „laut Spiel“
      2. selbst gesehen: die Stufen der feindlichen Gegner, die ezCores Entdecker-Datenbank in diesem Gebiet gesehen
         hat (Core.Zones.Levels, Tabelle „zoneLv“) – „bei dir gesehen: 5–12“
      3. sonst sagt die Zeile, dass das Spiel keine liefert und noch nichts gesehen ist (nie stumm)
    Rücksicht: zeigt ein anderes Addon Zonenstufen (Core.WhoHandles("zoneLevels"): Leatrix Maps, Tweaks Forever),
    nennt ezMap nur dessen Namen. Zurücknehmen: der Aufruf von Zones.AddMenu in MapButton.BuildMenu und die
    Statuszeile unten.
]]
local Zones = {}
ns.Zones = Zones

-- Kartentypen mit eigenen Stufen: Zone (3), Dungeon (4) und darunter; Welt und Kontinent haben keine.
Zones.MIN_MAP_TYPE = 3

-- Stufen eines Gebiets → lo, hi, Quelle ("client" | "own"), Sichtungen (bei "own"); sonst nil, Grund
-- ("invalid": keine Karte bzw. Welt oder Kontinent, "none": das Spiel liefert keine und gesehen ist noch nichts).
function Zones.Levels(mapID)
    mapID = ns.Num(mapID)
    local info = mapID and Core.Map.Info(mapID)
    local mapType = type(info) == "table" and ns.Num(info.mapType) or nil
    if not (mapType and mapType >= Zones.MIN_MAP_TYPE) then return nil, "invalid" end
    local D = Core.Dungeons
    if D and D.ZoneLevels then
        local lo, hi = D.ZoneLevels(mapID)
        if ns.Num(lo) and ns.Num(hi) then return lo, hi, "client" end
    end
    if ns.Discovery.Usable() and Core.Zones and Core.Zones.Levels then
        local lo, hi, seen = Core.Zones.Levels(mapID)
        if ns.Num(lo) and ns.Num(hi) then return lo, hi, "own", type(seen) == "table" and ns.Num(seen.cnt) or nil end
    end
    return nil, "none"
end

-- Beschriftung mit Quelle und Farbe nach deiner Stufe (wie die Gruppensuche) → Text, Erklärzeile oder nil.
function Zones.Label(mapID)
    local lo, hi, source, seen = Zones.Levels(mapID)
    if not lo then
        if hi == "none" then return L.MENU_ZONE_LEVELS_NONE, L.MENU_ZONE_LEVELS_NONE_TIP end
        return nil
    end
    local text = source == "client" and L.MENU_ZONE_LEVELS_CLIENT:format(lo, hi) or L.MENU_ZONE_LEVELS_OWN:format(lo, hi)
    local tip = source == "client" and L.MENU_ZONE_LEVELS_CLIENT_TIP or L.MENU_ZONE_LEVELS_OWN_TIP:format(seen or 1)
    local D = Core.Dungeons
    local key = D and D.Difficulty and D.Difficulty(lo, hi)
    if key and D.Color then
        local r, g, b = D.Color(key)
        if r then text = Core.ColorCode(r, g, b) .. text .. "|r" end
    end
    return text, tip
end

-- Zeile im Kartenmenü (kein Klick: eine Angabe mit Erklärzeile). → der Eintrag oder nil
function Zones.AddMenu(root, mapID)
    local other = ns.OtherFor("zoneLevels")
    if other then
        local lo, why = Zones.Levels(mapID)
        if not lo and why == "invalid" then return nil end
        return ns.MapButton.OtherTitle(root, L.MENU_ZONE_LEVELS_OTHER:format(other))
    end
    local text, tip = Zones.Label(mapID)
    if not text then return nil end
    return ns.MapButton.Tip(Core.Menu.Title(root, text), text, tip)
end

-- /ezmap status: woher die Zonenstufen kommen
ns.AddStatusLine(function()
    local other = ns.OtherFor("zoneLevels")
    if other then return L.STATUS_ZONE_LEVELS_OTHER:format(other) end
    local mapID = ns.PlayerPosition()
    if mapID and select(3, Zones.Levels(mapID)) == "client" then return L.STATUS_ZONE_LEVELS_CLIENT end
    local DB = ns.Discovery.DB()
    return L.STATUS_ZONE_LEVELS_OWN:format(DB and #DB.KeysOf("zoneLv") or 0)
end)
