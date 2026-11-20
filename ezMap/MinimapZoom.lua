local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Minikarte: von selbst wieder herauszoomen (Wunsch des Nutzers 13.11.2026: „aus der Minimap weiter herauszoomen“).

    Geprüft in Blizzards Forever-Quelle (Gethe/wow-ui-source, Zweig forever, Blizzard_Minimap: Mainline-Fassung,
    Camelot ändert nur den Rahmen): Mausrad und Blizzards Plus/Minus zoomen schon bis Stufe 0 – das ist die weiteste,
    die der Client kennt. Minimap:GetZoomLevels() zählt die Stufen 0 bis n-1, die CVars minimapZoom und
    minimapInsideZoom merken nur die gewählte Stufe (draußen bzw. drinnen). Mehr Fläche zeigen Addons wie SexyMap
    oder FarmHud nur, indem sie die Minikarte vergrößern oder umhängen – das baut ezMap nicht nach (Entscheidung des
    Nutzers vom 13.11.2026 gegen Skalieren und Umhängen; anfassen dürfte ezMap sie nur taint-sicher nach Leitlinie 5);
    größer stellen kann man sie selbst in Blizzards Bearbeitungsmodus („Größe“), das zeigt aber dieselbe Fläche größer.

    Den Knopf „Ganz herauszoomen“ aus 1.5 hat der Nutzer im Spieltest abgewählt („Blizzards − + reicht“, 13.11.2026).
    Geblieben ist: auf Wunsch (Standard aus) zoomt die Minikarte nach einigen Sekunden von selbst wieder ganz heraus;
    tut das schon ein anderes Addon (SexyMap, erkannt über ezCore „minimapAutoZoom“), hält sich ezMap zurück.
    Der Schieber (0 = aus) steht auf der Einstellungsseite, ein Haken im Menü „Aufspüren“ der Minikarte (Tracking.lua).
    Nichts wird verschoben, skaliert oder in Blizzards Tabellen geschrieben.
]]
local Zoom = {}
ns.MinimapZoom = Zoom

local generation = 0                         -- jede neue Frist macht ältere ungültig

local function Map() return rawget(_G, "Minimap") end

-- Aktuelle Stufe (0 = ganz heraus) und Anzahl der Stufen oder nil.
function Zoom.Level()
    local map = Map()
    if not (map and map.GetZoom) then return nil end
    return ns.Num(map:GetZoom())
end

function Zoom.Levels()
    local map = Map()
    if not (map and map.GetZoomLevels) then return nil end
    return ns.Num(map:GetZoomLevels())
end

-- Ganz heraus (Stufe 0). Blizzards Plus und Minus stellen sich wie nach ihrem eigenen Klick.
function Zoom.ZoomOut()
    local map, level = Map(), Zoom.Level()
    if not (map and map.SetZoom and level and level > 0) then return false end
    map:SetZoom(0)
    if map.ZoomIn and map.ZoomIn.Enable then map.ZoomIn:Enable() end
    if map.ZoomOut and map.ZoomOut.Disable then map.ZoomOut:Disable() end
    return true
end

-- Wer das schon übernimmt (SexyMap „Auto Zoom-Out“), sonst nil.
function Zoom.AutoElsewhere() return ns.OtherFor("minimapAutoZoom") end

-- Bereich des Schiebers „Von selbst wieder herauszoomen“ (0 = aus) und die Zeit, die der Haken im Menü „Aufspüren“
-- einschaltet, wenn noch keine gemerkt ist. Seit der Einstellungs-Prüfung vom 19.11.2026 (Nr. 91, 92) ein Schieber
-- statt Haken (minimapAutoZoom) und Schieber; die letzte Zeit über 0 merkt ezMap in ezMapDB.minimapAutoZoomLast.
Zoom.MIN, Zoom.MAX, Zoom.DEFAULT_ON = 3, 60, 10

-- Sekunden laut Schieber (0 = aus); ohne Wert der Standard
local function Seconds()
    return ns.Num(ns.S and ns.S.minimapAutoZoomDelay) or ns.DEFAULTS.minimapAutoZoomDelay or 0
end

-- Zoomt ezMap von selbst heraus (Schieber über 0)? true | false
function Zoom.On()
    return Seconds() > 0
end

-- Haken im Menü „Aufspüren“: an = die zuletzt gewählte Zeit (sonst DEFAULT_ON), aus = 0 (die Zeit bleibt gemerkt)
function Zoom.SetOn(on)
    on = on == true
    if on == Zoom.On() then return on end
    local db = type(ns.db) == "table" and ns.db or nil
    if on then
        local last = ns.Num(db and db.minimapAutoZoomLast)
        if not (last and last > 0) then last = Zoom.DEFAULT_ON end
        ns.SetSetting("minimapAutoZoomDelay", math.max(Zoom.MIN, math.min(Zoom.MAX, last)))
    else
        if db then db.minimapAutoZoomLast = Seconds() end
        ns.SetSetting("minimapAutoZoomDelay", 0)
    end
    return Zoom.On()
end

-- Beschriftung des Schiebers: 0 = „aus“, sonst die geltende Zeit (1 und 2 gelten als MIN)
function Zoom.Label(value)
    value = ns.Num(value) or 0
    if value <= 0 then return L.GMAP_DIM_OFF end
    return Core.Seconds(math.max(Zoom.MIN, math.min(Zoom.MAX, value)))
end

function Zoom.AutoActive()
    return Zoom.On() and not Zoom.AutoElsewhere()
end

function Zoom.Delay()
    return math.max(Zoom.MIN, math.min(Zoom.MAX, Seconds()))
end

-- Nach jedem Zoom beginnt die Frist neu; liegt die Maus dann auf der Minikarte, wartet ezMap noch eine Frist.
function Zoom.Schedule()
    generation = generation + 1
    local level = Zoom.Level()
    if not (Zoom.AutoActive() and level and level > 0) then return false end
    local mine = generation
    C_Timer.After(Zoom.Delay(), function()
        if mine ~= generation then return end
        local map = Map()
        if map and map.IsMouseOver and map:IsMouseOver() then return Zoom.Schedule() end
        Zoom.ZoomOut()
    end)
    return true
end

ns.OnReady(function() Zoom.Schedule() end)     -- nach dem Einloggen steht die zuletzt gewählte Stufe wieder da
ns.On("MINIMAP_UPDATE_ZOOM", function() Zoom.Schedule() end)
ns.On("PLAYER_ENTERING_WORLD", function() Zoom.Schedule() end)     -- drinnen und draußen je eine Stufe

ns.OnSettingChanged(function(key)
    if key == "minimapAutoZoomDelay" then
        -- jede gewählte Zeit über 0 merken, auch vom Schieber (code-reviewer 20.11.2026: sonst schaltete der Haken im
        -- Menü „Aufspüren“ nach „Schieber auf 0“ eine ältere Zeit ein)
        if Seconds() > 0 and type(ns.db) == "table" then ns.db.minimapAutoZoomLast = Seconds() end
        Zoom.Schedule()
    end
end)

ns.AddStatusLine(function()
    local level, levels = Zoom.Level(), Zoom.Levels()
    local where = level and levels and L.ZOOM_LEVEL:format(level, levels - 1) or "?"
    local other = Zoom.AutoElsewhere()
    if other then return L.STATUS_ZOOM_OTHER:format(where, other) end
    if Zoom.AutoActive() then return L.STATUS_ZOOM_AUTO:format(where, Zoom.Delay()) end
    return L.STATUS_ZOOM:format(where)
end)
