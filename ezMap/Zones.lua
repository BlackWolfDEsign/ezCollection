local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Zonenstufen im Kartenmenü (MAP-06, DG-47; Welle 10 – Empfehlung umgesetzt, Antwort offen).

    Forever liefert für seine Gebiete zur Laufzeit keine Zonenstufen (Spieltest 14.11.2026: C_Map.GetMapLevels gibt es,
    bleibt aber leer), Blizzards Kartenbeschriftung zeigt also keine. Eine Tabelle aus einem fremden Addon kommt nicht in
    Frage (Leitlinie 10). Reihenfolge der Quellen (Leitlinie 11):
      1. der Client zur Laufzeit (Dungeons.ZoneLevels, "client") – „laut Spiel“
      2. die Client-Tabellen (Dungeons.ZoneLevels, "tables": Erkundungsstufen der Teilgebiete, seit 24.11.2026) – „laut
         Client-Tabellen“
      3. selbst gesehen: die Stufen der feindlichen Gegner, die ezCores Entdecker-Datenbank in diesem Gebiet gesehen
         hat (Core.Zones.Levels, Tabelle „zoneLv“) – „bei dir gesehen: 5–12“
      4. aus Beiträgen anderer Spieler (ezData, Core.Zones.Shipped; seit 25.11.2026) – „aus Beiträgen“
      5. sonst sagt die Zeile, dass das Spiel keine liefert und noch nichts gesehen ist (nie stumm)
    Rücksicht: zeigt ein anderes Addon Zonenstufen (Core.WhoHandles("zoneLevels"): Leatrix Maps, Tweaks Forever),
    nennt ezMap nur dessen Namen. Zurücknehmen: der Aufruf von Zones.AddMenu in MapButton.BuildMenu und die
    Statuszeile unten.
]]
local Zones = {}
ns.Zones = Zones

-- Kartentypen mit eigenen Stufen: Zone (3), Dungeon (4) und darunter; Welt und Kontinent haben keine.
Zones.MIN_MAP_TYPE = 3

-- Stufen der feindlichen Gegner, die du im Gebiet gesehen hast → lo, hi, Sichtungen oder nil
function Zones.Seen(mapID)
    if not (ns.Discovery.Usable() and Core.Zones and Core.Zones.Levels) then return nil end
    local lo, hi, seen = Core.Zones.Levels(mapID)
    if not (ns.Num(lo) and ns.Num(hi)) then return nil end
    return lo, hi, type(seen) == "table" and ns.Num(seen.cnt) or nil
end

-- Stufen der Gegner aus Beiträgen anderer Spieler → lo, hi, Herkunft oder nil
function Zones.Shared(mapID)
    if not (ns.Discovery.Usable() and Core.Zones and Core.Zones.Shipped) then return nil end
    local lo, hi, info = Core.Zones.Shipped(mapID)
    if not (ns.Num(lo) and ns.Num(hi)) then return nil end
    return lo, hi, type(info) == "table" and info.label or Core.L["SOURCES_SHIP"]
end

-- Stufen eines Gebiets → lo, hi, Quelle ("client" | "tables" | "own" | "ship"), Sichtungen (bei "own") bzw. Herkunft (bei
-- "ship"); sonst nil, Grund
-- ("invalid": keine Karte bzw. Welt oder Kontinent, "none": das Spiel liefert keine und gesehen ist noch nichts).
function Zones.Levels(mapID)
    mapID = ns.Num(mapID)
    local info = mapID and Core.Map.Info(mapID)
    local mapType = type(info) == "table" and ns.Num(info.mapType) or nil
    if not (mapType and mapType >= Zones.MIN_MAP_TYPE) then return nil, "invalid" end
    local D = Core.Dungeons
    if D and D.ZoneLevels then
        local lo, hi, source = D.ZoneLevels(mapID)
        if ns.Num(lo) and ns.Num(hi) then return lo, hi, source == "tables" and "tables" or "client" end
    end
    local lo, hi, cnt = Zones.Seen(mapID)
    if lo then return lo, hi, "own", cnt end
    local label
    lo, hi, label = Zones.Shared(mapID)
    if lo then return lo, hi, "ship", label end
    return nil, "none"
end

-- Beschriftung mit Quelle und Farbe nach deiner Stufe (wie die Gruppensuche) → Text, Erklärzeile oder nil.
function Zones.Label(mapID)
    local lo, hi, source, seen = Zones.Levels(mapID)
    if not lo then
        if hi == "none" then return L.MENU_ZONE_LEVELS_NONE, L.MENU_ZONE_LEVELS_NONE_TIP end
        return nil
    end
    local text, tip
    if source == "client" then
        text, tip = L.MENU_ZONE_LEVELS_CLIENT:format(lo, hi), L.MENU_ZONE_LEVELS_CLIENT_TIP
    elseif source == "tables" then
        local CD = Core.ClientData
        text = L.MENU_ZONE_LEVELS_TABLES:format(lo, hi)
        tip = L.MENU_ZONE_LEVELS_TABLES_TIP:format(CD and CD.Build and CD.Build("areas") or "?")
        -- dazu, was du selbst gesehen hast (Persönliches neben dem Nachschlage-Wissen)
        local ownLo, ownHi, cnt = Zones.Seen(mapID)
        if ownLo then tip = tip .. " " .. L.MENU_ZONE_LEVELS_SEEN:format(ownLo, ownHi, cnt or 1) end
    elseif source == "ship" then
        text, tip = L.MENU_ZONE_LEVELS_SHIP:format(lo, hi), L.MENU_ZONE_LEVELS_SHIP_TIP:format(tostring(seen))
    else
        text, tip = L.MENU_ZONE_LEVELS_OWN:format(lo, hi), L.MENU_ZONE_LEVELS_OWN_TIP:format(seen or 1)
    end
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
    local source = mapID and select(3, Zones.Levels(mapID)) or nil
    if source == "client" then return L.STATUS_ZONE_LEVELS_CLIENT end
    if source == "tables" then return L.STATUS_ZONE_LEVELS_TABLES end
    if source == "ship" then return L.STATUS_ZONE_LEVELS_SHIP:format(tostring((select(4, Zones.Levels(mapID))))) end
    local DB = ns.Discovery.DB()
    return L.STATUS_ZONE_LEVELS_OWN:format(DB and #DB.KeysOf("zoneLv") or 0)
end)
