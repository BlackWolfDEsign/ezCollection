local Core = ezCore

--[[
    Wo steht welcher Lehrer: Core.TrainerSpots – eine Stelle für „Wo kommt was“ im Zauberbuch (ezMerchant) und am
    Berufefenster (ezCraft). Bis zum 24.11.2026 stand das nur in ezMerchant (Where.lua); der Nutzer am 24.11.2026,
    wörtlich: „ggf. teilen zauberbuch und berufe dann funktion "WAS KOMMT WANN" … "WO KOMMT WAS"“.

    Quellen (Leitlinie 11): die Lehrer, deren Fenster du geöffnet hast (Core.Npcs), und – mit ezMap, solange Questie läuft –
    alle deines Kontinents laut Questie (ezCore.API("ezMap").TrainersNear, nur zur Laufzeit). Ohne ezMap nur die besuchten.

    Schnittstelle:
      TrainerSpots.MapAPI()         → ezMaps Schnittstelle, wenn ezMap läuft und Lehrer findet; sonst nil
      TrainerSpots.Read()           → { list, pending (Questie liest noch), withMap } – eine Frage für alle Arten. Mit ezMap
                                      nach Entfernung (die deines Kontinents mit .distance), mit älterem ezMap nach Zone
                                      und Name, ohne ezMap die besuchten
      TrainerSpots.List(art, read)  → Liste, pending, withMap. art: "class" (nur die eigene Klasse), "weapon", "riding",
                                      "pet" (Tierausbilder), "demon" (Dämonenausbilder), "prof:<Beruf>"
      TrainerSpots.Nearest(art, list) → nächster auf deinem Kontinent oder nil
      TrainerSpots.Fits(t, art)     → passt ein Lehrer zur Art?
      TrainerSpots.ProfKey(art)     → Beruf aus "prof:<Beruf>" oder nil
      TrainerSpots.Name(t), Place(t), SourceLabel(t) → „Name (Titel)“, Gebiet, „laut Questie“ bzw. „von dir besucht“
      TrainerSpots.PositionKnown()  → kennt das Spiel deine Position (Instanz, gesperrter Wert: nein)?
      TrainerSpots.Mark(t)          → true | false, Grund ("nomap" ohne ezMap, "noplace", sonst ezMaps Text): setzt
                                      Blizzards Kartenmarkierung über ezMap
]]

local TS = {}
Core.TrainerSpots = TS

local function Num(v) return Core.Num(v) end

function TS.MapAPI()
    local api = Core.API("ezMap")
    if type(api) == "table" and type(api.NearestTrainer) == "function" and type(api.SetWaypoint) == "function" then
        return api
    end
    return nil
end

function TS.ProfKey(kind)
    return type(kind) == "string" and kind:match("^prof:(.+)$") or nil
end

function TS.Fits(t, kind)
    if type(t) ~= "table" then return false end
    if kind == "class" then return t.trainer == "class" end
    if kind == "weapon" then return t.weapon == true end
    if kind == "riding" then return t.riding == true end
    if kind == "demon" then return t.demon == true end
    local prof = TS.ProfKey(kind)
    if prof then                    -- Berufslehrer dieses Berufs, erkannt am Titel (wie ezMaps Menü)
        local M = Core.Menu
        if t.trainer ~= "profession" or not (type(M) == "table" and type(M.ProfessionOfTitle) == "function") then
            return false
        end
        local ok, key = pcall(M.ProfessionOfTitle, t.title)
        return ok and key == prof
    end
    if kind == "pet" then           -- Tierausbilder: Art laut ezMap, sonst dieselbe Regel wie ezMaps KindOf
        if t.kind == "pet" then return true end
        local N = Core.Npcs
        return type(N) == "table" and type(N.IsPetTrainer) == "function" and N.IsPetTrainer(t) == true
    end
    return false
end

function TS.Read()
    local api = TS.MapAPI()
    if api then
        local fn = type(api.TrainersNear) == "function" and api.TrainersNear or api.Trainers
        if type(fn) ~= "function" then return { list = {}, pending = false, withMap = true } end
        local ok, list, pending = pcall(fn, nil)
        if not ok then
            Core.Error(Core.name, list, "TrainerSpots.Read")
            list, pending = nil, false
        end
        return { list = type(list) == "table" and list or {}, pending = pending == true, withMap = true }
    end
    local N = Core.Npcs
    if not (type(N) == "table" and type(N.List) == "function") then return { list = {}, pending = false } end
    local ok, all = pcall(N.List, { kind = "trainer", located = true, fits = true })
    if not ok then
        Core.Error(Core.name, all, "TrainerSpots.Read")
        all = nil
    end
    return { list = type(all) == "table" and all or {}, pending = false, withMap = false }
end

-- read = schon gelesenes TS.Read() (sonst liest die Funktion selbst).
function TS.List(kind, read)
    read = read or TS.Read()
    local out = {}
    for _, t in ipairs(read.list) do
        if TS.Fits(t, kind) then out[#out + 1] = t end
    end
    return out, read.pending, read.withMap
end

-- list = schon gelesene Liste aus TS.List (ihr erster Eintrag mit Entfernung); ohne sie bzw. mit älterem ezMap (ohne
-- TrainersNear) fragt es ezMap direkt.
function TS.Nearest(kind, list)
    if type(list) == "table" and list[1] and list[1].distance then return list[1] end
    local api = TS.MapAPI()
    if not api then return nil end
    if type(list) == "table" and type(api.TrainersNear) == "function" then return nil end   -- keiner mit Entfernung
    local ok, t = pcall(api.NearestTrainer, kind)
    if not ok or type(t) ~= "table" or not (Num(t.map) and Num(t.x) and Num(t.y)) then return nil end
    return t
end

function TS.Name(t)
    local label = Core.Npcs and Core.Npcs.Label and Core.Npcs.Label(t)
    return type(label) == "string" and label or (type(t.name) == "string" and t.name) or "?"
end

function TS.Place(t)
    local name = t.map and Core.MapName and Core.MapName(t.map)
    if type(name) == "string" and name ~= "" then return name end
    if type(t.zone) == "string" and t.zone ~= "" then return t.zone end
    return "#" .. tostring(t.map)
end

function TS.SourceLabel(t)
    local label = Core.Npcs and Core.Npcs.SourceLabel and Core.Npcs.SourceLabel(t)
    return type(label) == "string" and label or nil
end

-- Kennt das Spiel die eigene Position samt Kontinent? Ohne sie (Instanz, gesperrter Wert) findet ezMap keinen Lehrer –
-- das heißt dann nicht, dass keiner gemerkt ist. Eine Fassung, auch für ezMap (Trainers.PositionKnown).
function TS.PositionKnown()
    local mapID, x, y = Core.PlayerPosition()
    return mapID ~= nil and Core.Map.WorldPos(mapID, x, y) ~= nil
end

function TS.Mark(t)
    local api = TS.MapAPI()
    if not api then return false, "nomap" end
    if type(t) ~= "table" or not (Num(t.map) and Num(t.x) and Num(t.y)) then return false, "noplace" end
    local ok, done, err = pcall(api.SetWaypoint, t.map, t.x, t.y, TS.Name(t))
    if ok and done then return true end
    return false, tostring(ok and err or done or "?")
end
