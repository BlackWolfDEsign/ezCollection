local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Hinweis auf seltene Gegner (Auftrag des Nutzers 13.11.2026): eine Chatzeile mit Name und Koordinaten und ein Ton.
    Nichts aus fremden Addons übernommen – ezMap meldet nur, was der Client gerade selbst zeigt:
      - eine Einheit mit der Einstufung „rare“ bzw. „rareelite“ (Namensplakette erscheint, Maus über dem Gegner,
        neues Ziel – die Einheit heißt dann „nameplateN“, „mouseover“ oder „target“)
      - eine Vignette von Blizzards Minikarte mit dem Symbol für seltene Gegner (C_VignetteInfo)

    Regel „Datenquellen“ des Nutzers: Das ist Entdecker-Wissen, deshalb Schalter und AB WERK AUS. Die Meldung nennt
    ihre Quelle (Einheit oder Minikarte). Läuft ein Addon, das seltene Gegner schon meldet (RareScanner, SilverDragon
    … – erkannt über ezCore, Core.WhoHandles("rareAlerts")), schweigt ezMap und nennt es im Status.

    Geheime Werte (Leitlinie 6): Jeder gelesene Wert geht zuerst durch ezCore (Core.Plain, Core.NpcID, ns.Num,
    ns.IsSecret); ein gesperrter Wert ist keine Antwort und wird nie verglichen oder als Tabellenschlüssel benutzt.
    Im Kampf meldet ezMap nichts. Je Gegner höchstens eine Meldung in zehn Minuten.

    Seit Welle 15 (SAM-22): gemerkte Sichtungen auf der Weltkarte. ezCore merkt jede Sichtung eines seltenen Gegners
    in der Entdecker-Datenbank (DG-08, Core.Rares: NPC, Karte, Ort, Tag); ezMap zeichnet sie über ezCores
    Punkteschicht (Anbieter „ezMap.rares“) – „bei dir gesehen am …“. Entdecker-Wissen: Schalter rarePins (Gruppe
    „Schätze und Entdecker-Wissen“ im Baum), ab Werk aus; ist er an, fragt ezMap ezCore mit explorer = true. Zeichnet ein
    Addon seltene Gegner schon auf die Karte (Core.WhoHandles("rarePins"): RareScanner, SilverDragon, HandyNotes: WoW
    Forever – eigener Schlüssel seit dem Gesamtreview 18.11.2026, T5-1; vorher der Schlüssel der Chat-Meldung
    rareAlerts), zeichnet ezMap nicht.
    Was Blizzard gerade selbst als Vignette zeichnet, zeichnet ezMap nicht doppelt.
]]
local Rares = {}
ns.Rares = Rares

Rares.COOLDOWN = 600                                            -- Sekunden zwischen zwei Meldungen desselben Gegners
Rares.CLASSIFICATIONS = { rare = true, rareelite = true }       -- Einstufung aus Core.UnitRank
Rares.ATLAS_PREFIX = "VignetteKill"                             -- Blizzards Vignetten-Symbole „VignetteKill“, „VignetteKillElite“

local lastAlert = {}        -- [NPC-ID oder Name] = GetTime() der letzten Meldung (Schlüssel sind nie gesperrte Werte)
Rares.last = nil            -- { name, map, x, y, source, t } des zuletzt gemeldeten Gegners (nur diese Sitzung)

-- Wer seltene Gegner schon meldet, sonst nil.
-- Bei RareScanner sieht ezCore nur, dass es läuft (Entscheidung des Nutzers vom 19.11.2026, T5-6); „Trotzdem melden“
-- (rareOverride) hebt die Zurückhaltung auf.
function Rares.Elsewhere()
    if ns.Enabled("rareOverride") then return nil end
    return ns.OtherFor("rareAlerts")
end

function Rares.Active()
    return ns.Enabled("rareAlert") and not Rares.Elsewhere()
end

-- Wer seltene Gegner schon auf die Karte zeichnet, sonst nil (Schlüssel rarePins, T5-1). „Trotzdem melden“
-- (rareOverride) gilt auch hier: dann zeichnet ezMap seine gemerkten Sichtungen trotzdem.
function Rares.PinsElsewhere()
    if ns.Enabled("rareOverride") then return nil end
    return ns.OtherFor("rarePins")
end

-- Warnton auf dem Kanal „Master“, hörbar auch ohne Soundeffekte (docs/design-system.md, „Warntöne“; T16-NM5).
-- Über ezCores Ton-Helfer (Core.PlaySound: Schlüssel prüfen, pcall; Gesamtreview 18.11.2026, T16-NM4).
function Rares.PlaySound()
    return Core.PlaySound("RAID_WARNING", "Master")
end

local function Where(mapID, x, y)
    if mapID and x and y then return ns.MapName(mapID) .. " " .. ns.CoordText(x, y) end
    return L.RARE_NO_POSITION
end

-- Meldet den Gegner, wenn er in den letzten zehn Minuten noch nicht gemeldet wurde. key: NPC-ID oder Name.
-- source: "unit" | "vignette". Rückgabe: true, wenn gemeldet.
function Rares.Announce(key, name, source, mapID, x, y)
    if ns.IsSecret(key) or (type(key) ~= "string" and type(key) ~= "number") then return false end
    if ns.IsSecret(name) or type(name) ~= "string" or name == "" then return false end
    local now = Core.Uptime()
    local before = lastAlert[key]
    if before and now - before < Rares.COOLDOWN then return false end
    lastAlert[key] = now
    mapID, x, y = ns.Num(mapID), ns.Num(x), ns.Num(y)
    Rares.last = { name = name, map = mapID, x = x, y = y, source = source, t = now }
    ns.Print(L.RARE_ALERT:format(name, Where(mapID, x, y), L["RARE_SOURCE_" .. tostring(source)] or tostring(source)))
    if ns.Enabled("rareSound") then Rares.PlaySound() end
    return true
end

-- Einheit prüfen (unit = "nameplateN", "mouseover", "target"). Rückgabe: true, wenn gemeldet.
function Rares.CheckUnit(unit)
    if not Rares.Active() or Core.InCombat() then return false end
    if ns.IsSecret(unit) or type(unit) ~= "string" then return false end
    local class = Core.UnitRank(unit)   -- Einstufung aus ezCore (MAP-03): „rare“, „rareelite“ … oder nil (gesperrt)
    if type(class) ~= "string" or not Rares.CLASSIFICATIONS[class] then return false end
    -- tot oder unbekannt (gesperrt): keine Meldung
    if type(UnitIsDead) == "function" and Core.Bool(UnitIsDead(unit), true) then return false end
    local name = type(UnitName) == "function" and Core.Plain((UnitName(unit))) or nil
    if type(name) ~= "string" or name == "" then return false end
    -- Leitlinie 6 (Gesamtreview 18.11.2026, T3-4): die GUID nie als Wahrheitswert prüfen – Core.Call liefert sie,
    -- Core.NpcID prüft selbst zuerst auf IsSecret.
    local id = Core.NpcID(Core.Call(rawget(_G, "UnitGUID"), unit))
    -- der Gegner steht bei dir: deine Position ist sein Fundort
    local mapID, x, y = ns.PlayerPosition()
    return Rares.Announce(id or name, name, "unit", mapID, x, y)
end

function Rares.IsRareAtlas(atlas)
    if ns.IsSecret(atlas) or type(atlas) ~= "string" then return false end
    return atlas:sub(1, #Rares.ATLAS_PREFIX) == Rares.ATLAS_PREFIX
end

-- Vignette von Blizzards Minikarte prüfen. Rückgabe: true, wenn gemeldet.
function Rares.CheckVignette(guid)
    if not Rares.Active() or Core.InCombat() then return false end
    local V = C_VignetteInfo
    if ns.IsSecret(guid) or type(guid) ~= "string" or not (V and V.GetVignetteInfo) then return false end
    local ok, info = pcall(V.GetVignetteInfo, guid)
    if not ok or ns.IsSecret(info) or type(info) ~= "table" then return false end
    if not Rares.IsRareAtlas(info.atlasName) then return false end
    local dead = info.isDead
    if ns.IsSecret(dead) or dead == true then return false end
    local name = Core.Plain(info.name)
    if type(name) ~= "string" or name == "" then return false end
    local id = Core.NpcID(info.objectGUID)
    local mapID, x, y = ns.PlayerPosition()
    if mapID and V.GetVignettePosition then
        local okPos, pos = pcall(V.GetVignettePosition, guid, mapID)
        if okPos then
            local vx, vy = Core.Map.XY(pos)
            if vx and vy then x, y = vx, vy end
        end
    end
    return Rares.Announce(id or name, name, "vignette", mapID, x, y)
end

-- Alle Vignetten, die der Client gerade kennt. Rückgabe: Anzahl der Meldungen.
function Rares.ScanVignettes()
    if not Rares.Active() or Core.InCombat() then return 0 end
    local V = C_VignetteInfo
    if not (V and V.GetVignettes) then return 0 end
    local ok, list = pcall(V.GetVignettes)
    if not ok or ns.IsSecret(list) or type(list) ~= "table" then return 0 end
    local n = 0
    for _, guid in ipairs(list) do
        if Rares.CheckVignette(guid) then n = n + 1 end
    end
    return n
end

---------------------------------------------------------------------------
-- Sichtbar: Menüpunkt im Kartenmenü, Knöpfe in den Einstellungen
---------------------------------------------------------------------------

-- Blizzards Markierung auf den zuletzt gemeldeten Gegner. Rückgabe: true oder false, Grund.
function Rares.GoLast(verbose)
    local last = Rares.last
    if not last then
        if verbose then ns.Print(L.RARE_NONE) end
        return false, "none"
    end
    if not (last.map and last.x and last.y) then
        if verbose then ns.Print(L.RARE_LAST_NO_POSITION:format(last.name)) end
        return false, "position"
    end
    return ns.Way.Set(last.map, last.x, last.y, last.name, verbose)
end

-- Kartenmenü: „Letzter seltener Gegner – Wegpunkt“ (nur, wenn in dieser Sitzung einer gemeldet wurde).
function Rares.AddMenu(root)
    local last = Rares.last
    if not last then return false end
    local text = L.MENU_RARE_LAST:format(last.name)
    local source = L["RARE_SOURCE_" .. tostring(last.source)] or tostring(last.source)
    ns.MapButton.Tip(Core.Menu.Button(root, text, function() Rares.GoLast(true) end), text,
        L.MENU_RARE_LAST_TIP:format(source))
    return true
end

-- Probe (Einstellungen): so sieht und klingt der Hinweis – auch, wenn der Schalter aus ist.
function Rares.Preview()
    local mapID, x, y = ns.PlayerPosition()
    ns.Print(L.RARE_ALERT:format(L.RARE_PREVIEW_NAME, Where(mapID, x, y), L.RARE_SOURCE_preview))
    if ns.Enabled("rareSound") then Rares.PlaySound() end
end

-- Für Prüfungen und nach „Einstellungen zurücksetzen“: die Zehn-Minuten-Sperren vergessen.
function Rares.ResetCooldowns()
    wipe(lastAlert)
end

---------------------------------------------------------------------------
-- Gemerkte Sichtungen auf der Weltkarte (SAM-22; Entdecker-Wissen, ab Werk aus)
---------------------------------------------------------------------------

Rares.PROVIDER = "ezMap.rares"
Rares.PIN_SIZE = 16
Rares.ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"   -- Rückfall, wenn Blizzards Atlas fehlt

local function Pins()
    local P = Core.MapPins
    if type(P) == "table" and type(P.AddProvider) == "function" then return P end
    return nil
end

function Rares.PinsWanted()
    return ns.Enabled("rarePins") and not Rares.PinsElsewhere()
end

-- NPC-IDs, die Blizzard gerade als Vignette kennt (die zeichnet Blizzards Karte selbst) → { [npc] = true }
function Rares.VignetteNpcs()
    local out = {}
    local V = rawget(_G, "C_VignetteInfo")
    if not (type(V) == "table" and V.GetVignettes and V.GetVignetteInfo) then return out end
    local ok, list = pcall(V.GetVignettes)
    if not ok or ns.IsSecret(list) or type(list) ~= "table" then return out end
    for _, guid in ipairs(list) do
        if not ns.IsSecret(guid) and type(guid) == "string" then
            local okInfo, info = pcall(V.GetVignetteInfo, guid)
            if okInfo and type(info) == "table" and not ns.IsSecret(info) then
                local id = Core.NpcID(info.objectGUID)
                if id then out[id] = true end
            end
        end
    end
    return out
end

-- Letzte Sichtung (Zeitstempel) und Zahl aus ezCores Satz „rare“ (sight = { { t, map, dead } … }, cnt)
local function Sightings(row)
    local last, dead
    for _, s in ipairs(type(row) == "table" and type(row.sight) == "table" and row.sight or {}) do
        local t = ns.Num(s.t)
        if t and (not last or t > last) then last, dead = t, s.dead == true end
    end
    return last, ns.Num(type(row) == "table" and row.cnt) or 0, dead
end

-- Sichtungen auf der Karte mapID (Zone und darunter; gelesen wird die Speicherkarte) → Punkte für Core.MapPins
function Rares.Points(mapID)
    mapID = ns.Num(mapID)
    local R = Core.Rares
    if not (mapID and type(R) == "table" and type(R.OnMap) == "function") then return {} end
    local info = Core.Map.Info(mapID)
    local mapType = type(info) == "table" and ns.Num(info.mapType) or nil
    if not (mapType and mapType >= 3) then return {} end
    local Keys = Core.DB and Core.DB.Keys
    local store = Keys and Keys.MapOf and Keys.MapOf(mapID) or mapID
    local skip = Rares.VignetteNpcs()
    local useAtlas = Core.AtlasExists(Rares.ATLAS_PREFIX)
    local out = {}
    for _, r in ipairs(R.OnMap(store, { explorer = true }) or {}) do
        local npc = ns.Num(r.npc)
        if npc and not skip[npc] then
            local best
            for _, p in ipairs(type(r.places) == "table" and r.places or {}) do
                if ns.Num(p.x) and ns.Num(p.y) and (not best or (ns.Num(p.cnt) or 0) > (ns.Num(best.cnt) or 0)) then best = p end
            end
            if best then
                local row = type(R.Of) == "function" and R.Of(npc, { explorer = true }) or nil
                local last, count, dead = Sightings(row)
                local name = Core.DB and Core.DB.Text and Core.DB.Text("npc", npc) or nil
                local point = { x = best.x, y = best.y, map = ns.Num(best.map) or store, size = Rares.PIN_SIZE,
                    rare = { npc = npc, name = type(name) == "string" and name ~= "" and name or ("#" .. npc),
                        last = last or ns.Num(best.t), count = count, dead = dead } }
                if useAtlas then point.atlas = Rares.ATLAS_PREFIX else point.texture = Rares.ICON end
                out[#out + 1] = point
            end
        end
    end
    return out
end

function Rares.PinTooltip(tip, point)
    local r = type(point) == "table" and point.rare
    if not r then return end
    Core.TipTitle(tip, r.name)
    -- r.last: Sichtung aus der Datenbank (Serveruhr), angezeigt in Ortszeit (T16-NZ1)
    if r.last then Core.TipLine(tip, L.RAREPIN_SEEN:format(Core.DateText(r.last, "day", "server")), "highlight") end
    if (r.count or 0) > 1 then Core.TipLine(tip, L.RAREPIN_COUNT:format(r.count), "hint") end
    if r.dead then Core.TipLine(tip, L.RAREPIN_DEAD, "hint") end
    Core.TipLine(tip, L.RAREPIN_SOURCE, "hint", true)
    Core.TipClick(tip, L.RAREPIN_HINT)
end

function Rares.PinClick(point, button)
    local r = type(point) == "table" and point.rare
    if not r or button == "RightButton" then return false end
    return ns.Way.Set(point.map, point.x, point.y, r.name, true)
end

function Rares.InitPins()
    local P = Pins()
    if not P then return false end
    P.AddProvider(Rares.PROVIDER, {
        owner = "ezMap",
        order = 45,
        punkte = Rares.Points,
        sichtbar = function() return Rares.PinsWanted() end,
        tooltip = Rares.PinTooltip,
        klick = Rares.PinClick,
    })
    return true
end

-- Blizzards Vignetten wechseln: Punkte neu (höchstens einmal je Sekunde, nur mit eingeschaltetem Schalter und offener
-- Weltkarte – die Sichtungen stehen nur dort, und ezCores Neuaufbau holte sonst auch alle Minikarten-Punkte neu ab;
-- beim Öffnen baut ezCores Punkteschicht ohnehin neu)
local function WorldMapShown()
    local map = rawget(_G, "WorldMapFrame")
    if type(map) ~= "table" or type(map.IsShown) ~= "function" then return false end
    local ok, shown = pcall(map.IsShown, map)
    return ok and shown == true
end
Rares.WorldMapShown = WorldMapShown

local refreshPins = ns.Throttle(function()
    local P = Pins()
    if P and Rares.PinsWanted() and WorldMapShown() then P.Refresh() end
end, 1)

ns.Tree.Add("explorer", { key = "rarePins" }, "bookTargets")
ns.OnReady(function() ns.Try("RarePins", Rares.InitPins) end)
ns.OnSettingChanged(function(key)
    local P = Pins()
    if (key == "rarePins" or key == "rareOverride") and P then P.Refresh() end
end)

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------

ns.On("NAME_PLATE_UNIT_ADDED", function(_, unit) ns.Try("Rares", Rares.CheckUnit, unit) end)
ns.On("UPDATE_MOUSEOVER_UNIT", function() ns.Try("Rares", Rares.CheckUnit, "mouseover") end)
ns.On("PLAYER_TARGET_CHANGED", function() ns.Try("Rares", Rares.CheckUnit, "target") end)
ns.On("VIGNETTE_MINIMAP_UPDATED", function(_, guid) ns.Try("Rares", Rares.CheckVignette, guid) end)
ns.On("VIGNETTES_UPDATED", function()
    ns.Try("Rares", Rares.ScanVignettes)
    refreshPins()
end)

-- Statuszeile: läuft ein anderes Addon, steht der Weg zu „Trotzdem melden“ da – und, solange der Hinweis selbst aus ist,
-- auch der Weg zu ihm (der Haken wirkt nur zusammen mit ihm). Mit „Trotzdem melden“ nennt die Zeile das weiter laufende
-- Addon, denn Meldungen können dann doppelt kommen (Gegenprüfung D2).
-- Der Teil zu den Kartenpunkten (rarePins) steht in jedem Fall am Ende, auch wenn ein Addon für die Chat-Meldung läuft
-- (Gegenprüfung D3).
local function pinsStatus()
    local pins = ns.Enabled("rarePins") and Rares.PinsElsewhere()
    if pins then return L.STATUS_RAREPINS_OTHER:format(pins) end
    return ns.Enabled("rarePins") and L.STATUS_RAREPINS_ON or L.STATUS_RAREPINS_OFF
end

ns.AddStatusLine(function()
    local alertPath = Core.SettingsPathText("ezMap", "OPT_HEADER_RARES", "OPT_rareAlert", L)
    local other = Rares.Elsewhere()
    local line
    if other then
        line = L.STATUS_RARES_OTHER:format(other) .. " " .. Core.SettingsPathText("ezMap", "OPT_HEADER_RARES", "OPT_rareOverride", L)
        if not ns.Enabled("rareAlert") then line = line .. " " .. L.STATUS_RARES_ALSO .. " " .. alertPath end
    else
        line = ns.Enabled("rareAlert") and L.STATUS_RARES_ON or (L.STATUS_RARES_OFF .. " " .. alertPath)
        local running = ns.Enabled("rareOverride") and ns.OtherFor("rareAlerts")
        if running and ns.Enabled("rareAlert") then line = line .. " " .. L.STATUS_RARES_DESPITE:format(running) end
    end
    return line .. " " .. pinsStatus()
end)
