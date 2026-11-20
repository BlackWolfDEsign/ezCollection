local _, ns = ...
local L = ns.L
local Conv = ns.Conv

-- Gesprächsfenster an Blizzards Freundesliste andocken (Entscheidung des Nutzers 13.11.2026: „als zusätzliche
-- optionale Möglichkeit“). Ein Seitenreiter rechts an der Freundesliste (ezCore.CreateSideTab, wie im
-- Zauberbuch) öffnet ezChats Gesprächsfenster rechts daneben, so hoch wie die Freundesliste (Window.OpenDocked).
-- Schließt man die Freundesliste, geht das angedockte Fenster mit zu; ob es offen war, merkt sich ezChat
-- (ezChatDB.friendsDockOpen) und öffnet es beim nächsten Mal wieder. Das freie Fenster über den Reiter
-- „Gespräche“ am Chat oder /ezchat bleibt, wie es war.
-- Taint-sicher: nur eigene Frames und HookScript an FriendsFrame; keine Reiter über PanelTemplates, nichts
-- in Blizzards Tabellen. Schalter: friendsDock (Einstellungen → Gesprächsfenster).

local Dock = {}
ns.FriendsDock = Dock

-- Lage des Reiters: ezCores Seitenreiter-Stapel der Freundesliste (Core.SideTabs; vereinbart in docs/ezcore.md:
-- ezChat 10, ezSocial 20 – kleiner steht weiter oben, ein versteckter Reiter gibt seinen Platz frei).
local TAB_KEY, TAB_ORDER = "ezChat.dock", 10
local ICON = "Interface\\Icons\\INV_Letter_15"

local tab

local function Friends() return rawget(_G, "FriendsFrame") end

-- Schalter an und Blizzards Freundesliste vorhanden?
function Dock.Enabled()
    return ns.S ~= nil and ns.S.friendsDock == true and Friends() ~= nil
end

-- Soll ein Gespräch jetzt angedockt aufgehen? (Schalter an und Freundesliste offen)
function Dock.Active()
    local friends = Friends()
    return Dock.Enabled() and friends:IsShown() == true
end

function Dock.Tab() return tab end

-- Reiter zeigen oder verstecken, Zahl der ungelesenen Nachrichten.
function Dock.Refresh()
    if ns.Window.UpdateDockButton then ns.Window.UpdateDockButton() end   -- Knopf „Andocken“/„Lösen“ im Fenster
    if not tab then return end
    local on = Dock.Active()
    tab:SetShown(on)
    if not on then return end
    local unread = Conv.UnreadTotal()
    tab.Count:SetText(unread > 0 and unread or "")
end

local function ShowTip(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local r, g, b = ns.RGB("highlight")   -- Farben aus ezCores Rollen (Welle 23, A5)
    GameTooltip:SetText(L.DOCK_TAB, r, g, b)
    GameTooltip:AddLine(L.DOCK_TAB_TIP, nil, nil, nil, true)
    local unread = Conv.UnreadTotal()
    r, g, b = ns.RGB("normal")
    if unread > 0 then GameTooltip:AddLine(L.BAR_UNREAD:format(unread), r, g, b, true) end
    r, g, b = ns.RGB("grey")
    -- Befehl und Weg zur Einstellung über ezCore (Gesamtreview T18-2, T18-18)
    local where = ezCore.SettingsPathText(ns.moduleName or "ezChat", "SECTION_WINDOW", "OPT_friendsDock", L)
    GameTooltip:AddLine(L.DOCK_TAB_FREE:format(ns.SlashCmd and ns.SlashCmd() or "/ezchat", where), r, g, b, true)
    GameTooltip:Show()
end

-- Angedocktes Fenster öffnen oder schließen (Klick auf den Reiter).
function Dock.Toggle()
    if not ns.db then return end
    if ns.Window.IsDocked() and ns.Window.IsShown() then
        ns.db.friendsDockOpen = false
        ns.Window.Close()
    else
        ns.db.friendsDockOpen = true
        ns.Window.OpenDocked()
    end
    Dock.Refresh()
end

local function CreateTab()
    local friends = Friends()
    if tab or not friends then return end
    tab = ezCore.CreateSideTab(friends, { key = TAB_KEY, order = TAB_ORDER, owner = "ezChat" })
    ezCore.SetIcon(tab.Icon, nil, ICON)
    tab:SetScript("OnClick", ezCore.SideTabClick(function() Dock.Toggle() end))
    tab:SetScript("OnEnter", ShowTip)
    tab:Hide()
end

local function OnFriendsShow()
    if not Dock.Enabled() then return Dock.Refresh() end
    CreateTab()
    if ns.db and ns.db.friendsDockOpen then ns.Window.OpenDocked() end
    Dock.Refresh()
end

local function OnFriendsHide()
    ns.Window.Undock(true)   -- angedocktes Fenster geht mit zu, das nächste freie Öffnen steht an der alten Stelle
    Dock.Refresh()
end

local hooked = false
local function Setup()
    local friends = Friends()
    if hooked or not friends then return end
    hooked = true
    friends:HookScript("OnShow", function() ns.Try("FriendsDock", OnFriendsShow) end)
    friends:HookScript("OnHide", function() ns.Try("FriendsDock", OnFriendsHide) end)
    if friends:IsShown() then OnFriendsShow() end
end

ns.OnReady(function()
    if Friends() then Setup() else ns.WhenAddOnLoaded("Blizzard_FriendsFrame", Setup) end
end)

-- Zahl am Reiter mit den Gesprächen aktuell halten (gesammelt, viele Nachrichten kommen oft zugleich).
local RefreshSoon = ns.Throttle(function() Dock.Refresh() end, 0.2)
Conv.OnChange(function() if tab and tab:IsShown() then RefreshSoon() end end)
Conv.OnRead(function() if tab and tab:IsShown() then RefreshSoon() end end)

ns.OnSettingChanged(function(key)
    if key ~= "friendsDock" then return end
    if ns.S.friendsDock then
        Setup()
        if Dock.Active() then CreateTab() end
    else
        ns.Window.Undock(true)
    end
    Dock.Refresh()
end)
