local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Anbindung an ezPanel (Vollprüfung 14.11.2026 W-25, Vollprüfung 13.11.2026 V-129) – nur, wenn ezPanel läuft:

      Meldung   Quelle „Gruppen-Nachrichten“ beim Baustein „Meldungen“ (ezCore.API("ezPanel").AddWarning):
                „3 neue Gruppen-Nachrichten für deine Stufe“. In ezPanels Menü „Quellen“ einzeln abwählbar.
      Baustein  „Gruppen-Nachrichten“ auf der Leiste (RegisterBlock, ab Werk aus): dieselbe Zahl, Linksklick
                öffnet den Reiter „Aus dem Chat“, der Tooltip nennt die neuesten Nachrichten mit Kanal und Alter.

    Beide teilen sich eine Zahl (Chat.Unseen in ChatLFG.lua): Nachrichten, die seit dem letzten Öffnen des Reiters
    kamen und einen Dungeon für die eigene Stufe nennen (was der Reiter wegen eines Filters nicht gezeigt hat,
    bleibt neu). ezSocial meldet beides selbst an (im ns.OnReady – dann
    sind alle Addons geladen); in ezPanel steht dafür kein Code. Ändert sich die Liste oder wird der Reiter
    geöffnet, zeichnet ezPanel neu – höchstens einmal je Sekunde (ns.Throttle). Ohne ezPanel passiert nichts.
]]

local Panel = {}
ns.Panel = Panel

Panel.KEY = "ezSocial.lfg"      -- Kennung der Quelle und des Bausteins bei ezPanel
Panel.TIP_ROWS = 6              -- so viele Nachrichten nennt der Tooltip
Panel.REFRESH = 1               -- Sekunden: so oft höchstens bittet ezSocial ezPanel um ein Neuzeichnen

local api, block   -- ezPanels Schnittstelle und der angemeldete Baustein (nil ohne ezPanel)

---------------------------------------------------------------------------
-- Die Zahl: neu seit dem letzten Öffnen des Reiters und passend zur Stufe
---------------------------------------------------------------------------

function Panel.Unseen()
    if not (ns.Chat and ns.Enabled("chatTab")) then return {} end
    return ns.Chat.Unseen()     -- ohne Stufe: Chat.Unseen nimmt die eigene aus ezCore
end

function Panel.Count()
    return #Panel.Unseen()
end

-- Text für ezPanels Meldungen: „3 neue Gruppen-Nachrichten für deine Stufe“, nil ohne neue Nachricht.
function Panel.Warning()
    local n = Panel.Count()
    if n == 0 then return nil end
    return n == 1 and L.PANEL_WARNING_ONE or L.PANEL_WARNING:format(n)
end

---------------------------------------------------------------------------
-- Baustein
---------------------------------------------------------------------------

-- Zeilen in ezCores Rollen statt Farbzahlen (Gesamtreview 18.11.2026, T9-6, Nachtrag im Paket D3): Absender weiß,
-- Kanal und Alter sowie Rest und Erklärung grau („hint“), Nachricht weiß wie im Reiter „Aus dem Chat“.
local function TooltipRows(tooltip, list)
    for i = 1, math.min(#list, Panel.TIP_ROWS) do
        local e = list[i]
        local name = Core.ShortName(e.s)
        name = e.c and Core.ClassText(name, e.c) or name
        Core.TipDoubleLine(tooltip, name .. " " .. ns.ChatTab.KindLabel(e.k), ns.ChatTab.WhereText(e), "highlight", "hint")
        Core.TipLine(tooltip, e.m, "highlight", true)
    end
    if #list > Panel.TIP_ROWS then
        Core.TipLine(tooltip, ezCore.More(#list - Panel.TIP_ROWS), "hint")
    end
end

-- Tooltip des Bausteins: die neuen Nachrichten für die eigene Stufe; gibt es keine, die zuletzt gesammelten.
-- Jede Zeile nennt Kanal und Alter, die letzte Zeile sagt, was „neu“ und „für deine Stufe“ heißt (Leitlinie 11).
function Panel.FillTooltip(tooltip)
    if not ns.Enabled("chatTab") then
        Core.TipLine(tooltip, L.PANEL_TIP_OFF, "bad", true)
        return
    end
    local unseen = Panel.Unseen()
    if #unseen > 0 then
        Core.TipLine(tooltip, L.PANEL_TIP_NEW:format(#unseen), "good")
        TooltipRows(tooltip, unseen)
    else
        Core.TipLine(tooltip, L.PANEL_TIP_NONE, "highlight")
        local all = ns.Chat.Filter()
        if #all > 0 then
            tooltip:AddLine(" ")
            Core.TipLine(tooltip, L.PANEL_TIP_LATEST:format(#all), "normal")
            TooltipRows(tooltip, all)
        end
    end
    tooltip:AddLine(" ")
    Core.TipLine(tooltip, L.PANEL_TIP_EXPLAIN, "hint", true)
end

-- Beschreibung des Bausteins für ezPanel (Felder: Kopf von ezPanel/Blocks.lua und ezPanel/API.lua).
function Panel.BlockDef()
    local def = {
        id = Panel.KEY,
        owner = "ezSocial",
        name = L.PANEL_NAME,
        label = L.PANEL_NAME,
        tip = L.PANEL_TIP,
        icon = ns.ChatTab.ICON,     -- das Symbol des Reiters, den der Klick öffnet (eine Quelle: ChatTab.lua)
        fallbackIcon = Core.ICON_FALLBACK,
        events = { "PLAYER_LEVEL_UP" },
        interval = 30,          -- abgelaufene Nachrichten fallen aus der Zahl, auch ohne neue Nachricht
        -- Mit Beschriftung: ezPanels Baustein „Freunde/Gilde“ trägt dasselbe Symbol und hat den Platz direkt
        -- daneben – eine nackte Zahl wäre nicht zu unterscheiden (abschaltbar in ezPanels Menü des Bausteins)
        defaults = { enabled = false, zone = "right", order = 56, label = true },
        hints = { L.PANEL_HINT_LEFT },
        -- Leitlinie 3: der Klick steht auch als Eintrag im Menü des Bausteins
        actions = { { text = L.PANEL_ACTION_OPEN, fn = function() ns.API.OpenChatTab() end } },
    }
    function def:GetText()
        local n = Panel.Count()
        if n == 0 then return Core.Grey("0") end
        return Core.ColorCode(0.1, 1, 0.1) .. n .. "|r"
    end
    function def:OnTooltip(tooltip)
        Panel.FillTooltip(tooltip)
    end
    function def:OnClick(button)
        if button == "LeftButton" then ns.API.OpenChatTab() end
    end
    return def
end

---------------------------------------------------------------------------
-- Anmelden und auffrischen
---------------------------------------------------------------------------

-- ezPanels Schnittstelle, wenn Quelle oder Baustein angemeldet sind, sonst nil.
function Panel.Connected()
    return api
end

function Panel.Block()
    return block
end

-- Bei ezPanel anmelden. → true, wenn die Quelle oder der Baustein angemeldet ist; false ohne ezPanel (oder mit
-- einer alten Fassung ohne die Schnittstelle). Erneuter Aufruf meldet nichts doppelt an.
function Panel.Connect()
    local panel = Core.API("ezPanel")
    if type(panel) ~= "table" then return false end
    local warned = false
    if type(panel.AddWarning) == "function" then
        ns.Try("ezPanel.AddWarning", function()
            warned = panel.AddWarning(Panel.KEY, L.PANEL_NAME, Panel.Warning) == true
        end)
    end
    if not block and type(panel.RegisterBlock) == "function" then
        ns.Try("ezPanel.RegisterBlock", function()
            local def = panel.RegisterBlock(Panel.BlockDef())
            block = type(def) == "table" and def or nil
        end)
    end
    if warned or block then api = panel end
    return api ~= nil
end

-- ezPanel neu zeichnen lassen: die Meldungen und den Baustein.
function Panel.Notify()
    if not api then return false end
    if type(api.RefreshWarnings) == "function" then api.RefreshWarnings() end
    if block and type(api.UpdateBlock) == "function" then api.UpdateBlock(Panel.KEY) end
    return true
end

-- Viele Nachrichten in kurzer Zeit (Handel) ergeben ein Neuzeichnen.
local Notify = ns.Throttle(function() Panel.Notify() end, Panel.REFRESH)
ns.Listen("LFG_CHAT_CHANGED", Notify)
ns.Listen("LFG_SEEN_CHANGED", Notify)

ns.OnReady(function() Panel.Connect() end)
