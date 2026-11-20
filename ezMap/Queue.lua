local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Warteschlangen-Zeit für Schlachtfelder als Baustein auf ezPanels Leiste (MAP-12, PANEL-19; gehört nicht in die
    Zeilen unter Blizzards Punkteanzeige, Battleground.lua). Nur, wenn ezPanel läuft; ab Werk aus – einschalten in
    ezPanels Menü „Bausteine“ bzw. Einstellungen, ezPanel, Bausteine (Häkchen „Schlachtfeld-Warteschlange“).

    Daten nur aus dem Client, so wie Blizzards eigenes Warteschlangen-Fenster am Knopf an der Minikarte sie liest
    (Forever-Quelle Gethe/wow-ui-source, Zweig forever: Blizzard_QueueStatusFrame/Mainline/QueueStatusFrame.lua,
    QueueStatusEntry_SetUpBattlefield; Camelot ändert dort nur Lage und Gruppensuche):
      GetMaxBattlefieldID()                    Anzahl der Plätze
      GetBattlefieldStatus(i)                  status ("queued", "confirm", "active", "none", "error" …), mapName, …,
                                               suspendedQueue (5. Wert: Warteschlange angehalten)
      GetBattlefieldTimeWaited(i)              gewartete Zeit in Millisekunden
      GetBattlefieldEstimatedWaitTime(i)       geschätzte Wartezeit in Millisekunden (0 = das Spiel nennt keine;
                                               Blizzard zeigt sie dann auch nicht)
      GetBattlefieldPortExpiration(i)          bei "confirm": Sekunden, die zum Betreten bleiben
    Jede Abfrage über Core.Call (fehlt eine Funktion oder wirft sie, gibt es keinen Wert), jeder Wert zuerst durch
    ezCore (Leitlinie 6): gesperrt oder fehlend = keine Angabe, nie eine geratene Zahl. Ohne Warteschlange blendet
    der Baustein sich aus (GetText → nil, ezPanel-Regel).

    Rücksicht (Leitlinie 9; Entscheidung des Nutzers vom 13.11.2026: „Läuft Capping, hält sich ezMap zurück“):
    Capping zeigt Warteschlangen selbst (Core.WhoHandles("battlegroundTimers")). Solange es läuft, bleibt der
    Baustein unsichtbar wie ohne Warteschlange (GetText → nil); /ezmap status nennt das Addon, die Erklärung des
    Bausteins in ezPanels Menü „Bausteine“ sagt es vorab.
]]
local Queue = {}
ns.Queue = Queue

Queue.KEY = "ezMap.queue"           -- Kennung des Bausteins bei ezPanel
Queue.ICON = "Interface\\Icons\\INV_BannerPVP_02"
Queue.SHOWN = { queued = true, confirm = true }     -- diese Zustände zeigt der Baustein

local api, block    -- ezPanels Schnittstelle und der angemeldete Baustein (nil ohne ezPanel)

---------------------------------------------------------------------------
-- Was der Client meldet
---------------------------------------------------------------------------

local function Text(value)
    value = Core.Plain(value)
    if type(value) == "string" and value ~= "" then return value end
    return nil
end

-- Millisekunden → Sekunden; gesperrt, fehlend oder negativ = nil.
local function Seconds(ms)
    ms = Core.Num(ms)
    if not ms or ms < 0 then return nil end
    return ms / 1000
end

-- Ein Platz der Warteschlange oder nil: { index, status, name, waited, estimated, expires, suspended }.
function Queue.Entry(i)
    local status, name, _, _, suspended = Core.Call(rawget(_G, "GetBattlefieldStatus"), i)
    status = Text(status)
    if not status then return nil end
    local e = { index = i, status = status, name = Text(name), suspended = Core.Bool(suspended, false) }
    if status == "queued" then
        e.waited = Seconds((Core.Call(rawget(_G, "GetBattlefieldTimeWaited"), i)))
        local estimated = Seconds((Core.Call(rawget(_G, "GetBattlefieldEstimatedWaitTime"), i)))
        if estimated and estimated > 0 then e.estimated = estimated end
    elseif status == "confirm" then
        local left = Core.Num((Core.Call(rawget(_G, "GetBattlefieldPortExpiration"), i)))
        if left and left >= 0 then e.expires = left end
    end
    return e
end

-- Alle Plätze, die gerade warten oder zum Betreten bereit sind (Reihenfolge wie bei Blizzard).
function Queue.List()
    local list = {}
    local count = Core.Num((Core.Call(rawget(_G, "GetMaxBattlefieldID"))))
    if not count then return list end
    for i = 1, math.min(count, 10) do
        local e = Queue.Entry(i)
        if e and Queue.SHOWN[e.status] then list[#list + 1] = e end
    end
    return list
end

-- Wer Warteschlangen schon zeigt (Capping), sonst nil.
function Queue.Elsewhere() return ns.OtherFor("battlegroundTimers") end

---------------------------------------------------------------------------
-- Texte
---------------------------------------------------------------------------

-- Kurztext eines Platzes für die Leiste: „3:12 / ~5:00“, „3:12“ (ohne Schätzung), „Bereit 0:45“, „angehalten“.
function Queue.Short(e)
    if e.status == "confirm" then
        return e.expires and L.QUEUE_READY_TIME:format(ns.Clock(e.expires)) or L.QUEUE_READY
    end
    if e.suspended then return L.QUEUE_SUSPENDED end
    local waited = e.waited and ns.Clock(e.waited) or "-:--"
    if e.estimated then return L.QUEUE_SHORT_ESTIMATE:format(waited, ns.Clock(e.estimated)) end
    return waited
end

-- Text auf der Leiste: der erste Platz, dazu „(+1)“ für weitere. nil ohne Warteschlange oder solange Capping die
-- Warteschlange zeigt (Baustein blendet sich aus).
function Queue.BarText()
    if Queue.Elsewhere() then return nil end
    local list = Queue.List()
    if #list == 0 then return nil end
    local text = Queue.Short(list[1])
    if list[1].status == "confirm" then text = Core.Green(text) end
    if #list > 1 then text = text .. " " .. L.QUEUE_MORE:format(#list - 1) end
    return text
end

-- Tooltip: je Platz Name und Zustand, dazu gewartete und geschätzte Zeit; die Quelle steht darunter (Leitlinie 11).
function Queue.FillTooltip(tooltip)
    local list = Queue.List()
    if #list == 0 then
        Core.TipLine(tooltip, L.QUEUE_TIP_NONE, "hint", true)
    end
    for _, e in ipairs(list) do
        Core.TipLine(tooltip, e.name or L.QUEUE_UNKNOWN_NAME, "normal")
        if e.status == "confirm" then
            Core.TipLine(tooltip, e.expires and L.QUEUE_TIP_READY_TIME:format(ns.Clock(e.expires)) or L.QUEUE_TIP_READY, "good", true)
        elseif e.suspended then
            Core.TipLine(tooltip, L.QUEUE_TIP_SUSPENDED, "orange", true)
        else
            Core.TipDoubleLine(tooltip, L.QUEUE_TIP_WAITED, e.waited and ns.Clock(e.waited) or L.QUEUE_TIP_NOVALUE, "highlight", "highlight")
            Core.TipDoubleLine(tooltip, L.QUEUE_TIP_ESTIMATE, e.estimated and ns.Clock(e.estimated) or L.QUEUE_TIP_NOESTIMATE, "highlight", "highlight")
        end
    end
    tooltip:AddLine(" ")
    Core.TipLine(tooltip, L.QUEUE_TIP_SOURCE, "hint", true)
end

---------------------------------------------------------------------------
-- Baustein bei ezPanel
---------------------------------------------------------------------------

-- Beschreibung des Bausteins (Felder: Kopf von ezPanel/Blocks.lua und ezPanel/API.lua).
function Queue.BlockDef()
    local def = {
        id = Queue.KEY,
        owner = "ezMap",
        name = L.QUEUE_NAME,
        label = L.QUEUE_LABEL,
        tip = L.QUEUE_TIP,
        icon = Queue.ICON,
        fallbackIcon = Core.ICON_FALLBACK,
        events = { "UPDATE_BATTLEFIELD_STATUS", "PLAYER_ENTERING_WORLD" },
        interval = 1,           -- die gewartete Zeit läuft sekundengenau
        defaults = { enabled = false, zone = "right", order = 58, label = true },
    }
    function def:GetText() return Queue.BarText() end
    function def:OnTooltip(tooltip) Queue.FillTooltip(tooltip) end
    return def
end

function Queue.Connected() return api end
function Queue.Block() return block end

-- Bei ezPanel anmelden. → true, wenn der Baustein angemeldet ist; false ohne ezPanel (oder mit einer alten Fassung
-- ohne RegisterBlock). Erneuter Aufruf meldet nichts doppelt an.
function Queue.Connect()
    if block then return true end
    local panel = Core.API("ezPanel")
    if type(panel) ~= "table" or type(panel.RegisterBlock) ~= "function" then return false end
    ns.Try("ezPanel.RegisterBlock", function()
        local def = panel.RegisterBlock(Queue.BlockDef())
        block = type(def) == "table" and def or nil
    end)
    if block then api = panel end
    return block ~= nil
end

ns.OnReady(function() Queue.Connect() end)

ns.AddStatusLine(function()
    if not block then return L.STATUS_QUEUE_NOPANEL end
    local other = Queue.Elsewhere()
    if other then return L.STATUS_QUEUE_OTHER:format(other) end
    local on = type(api.BlockEnabled) == "function" and api.BlockEnabled(Queue.KEY)
    return on and L.STATUS_QUEUE_ON or L.STATUS_QUEUE_OFF
end)
