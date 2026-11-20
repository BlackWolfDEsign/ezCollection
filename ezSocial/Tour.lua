local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Rundgang mit Erklärblasen (Abschlussrunde, Entscheidung des Nutzers 13.11.2026): beim ersten Öffnen von
    „Gruppe suchen“ bzw. der Freundesliste je eine Blase zu den wichtigsten Funktionen; „OK“ oder das X führt
    zur nächsten. Eine Blase, deren Ziel gerade nicht zu sehen ist (anderer Reiter, Fenster zu, Funktion aus),
    kommt beim nächsten Öffnen. Erneut zeigen: Einstellungen → ezSocial → „Erweitert“ → „Erklärung“.
    Bausteine aus ezCore (Core.NewTour mit owner = ns, Blasen wie Blizzards Tutorial-Hinweise); gemerkt in
    ezSocialDB.tour. Gestartet wird über ezCores gemeinsamen Starter (tour:StartSoon): viele Auslöser ergeben
    einen Start, im Kampf erst danach.
    Taint-sicher: eigene Rahmen, an Blizzards Fenster nur verankert; Hooks nur über HookScript.
]]

local Tour = {}
ns.Tour = Tour

local function Finder() return _G.LFGParentFrame end

-- Blizzards Reiter „Durchsuchen“: ezSocial ergänzt dort immer etwas (Stufe der Gruppe, gesperrte Instanzen; seit der
-- Prüfung der Einstellungen vom 19.11.2026 ohne Schalter).
local function BrowseTab()
    local parent = Finder()
    if not parent then return nil end
    return ns.Region(parent.BrowsingTab)
end

local function ChatPanel() return ns.ChatTab and ns.ChatTab.Panel() end

local function FilterButton()
    local panel = ChatPanel()
    return panel and panel.kindButton
end

local function MenuButton() return ns.ChatTab and ns.ChatTab.FirstMenuButton() end

-- Blizzards Freundesliste (Reiter „Freunde“): die Twinks der Freunde zeigt ezSocial immer.
local function FriendsList()
    return ns.Region(_G.FriendsListFrame)
end

-- parentOf: Rahmen, mit dem sich die Blase ausblendet (nicht das Ziel selbst: Zeilen liegen in einer
-- Scroll-Fläche, die alles außerhalb abschneidet).
Tour.STEPS = {
    { key = "browse", target = BrowseTab, parentOf = Finder, text = L.TOUR_BROWSE, side = "right" },
    { key = "chatTab", target = function() return ns.ChatTab and ns.ChatTab.SideTab() end, parentOf = Finder,
        text = L.TOUR_CHAT_TAB, side = "right" },
    { key = "chatFilter", target = FilterButton, parentOf = ChatPanel, text = L.TOUR_CHAT_FILTER, side = "below" },
    { key = "chatMenu", target = MenuButton, parentOf = ChatPanel, text = L.TOUR_CHAT_MENU, side = "right" },
    { key = "friends", target = FriendsList, parentOf = function() return _G.FriendsFrame end,
        text = L.TOUR_FRIENDS, side = "right" },
}

-- Speicher ezSocialDB.tour über das Gerüst (owner = ns; das Feld „tour“ gab es schon vorher, nichts zu übernehmen).
Tour.tour = Core.NewTour({ owner = ns, steps = Tour.STEPS })

-- Vor jedem Start: je Schritt den Rahmen bestimmen, mit dem sich die Blase ausblendet (parentOf).
function Tour.Prepare()
    for _, step in ipairs(Tour.STEPS) do
        if step.parentOf then step.parent = ns.Region(step.parentOf()) end
    end
end

-- Auch der gebündelte Starter aus ezCore (tour:StartSoon ruft tour:Start) bereitet so vor.
do
    local start = Tour.tour.Start
    function Tour.tour:Start(parent)
        Tour.Prepare()
        return start(self, parent)
    end
end

-- Erste noch nicht gesehene Blase, deren Ziel zu sehen ist; Schlüssel oder nil.
function Tour.Start()
    if not ns.db then return nil end
    return Tour.tour:Start()
end

-- Nach dem Öffnen eines Fensters: erst wenn Blizzard es fertig aufgebaut hat (nächster Frame), gebündelt und
-- nie im Kampf (ezCore: tour:StartSoon). → true, wenn ein Start vorgemerkt ist.
local function StartSoon()
    if not ns.db then return false end
    return Tour.tour:StartSoon(nil, 0)
end
Tour.StartSoon = StartSoon

---------------------------------------------------------------------------
-- Anmelden: „Gruppe suchen“ (lädt bei Bedarf) und die Freundesliste
---------------------------------------------------------------------------

local finderHooked = false
function Tour.HookFinder()
    local parent = Finder()
    if finderHooked or not parent then return finderHooked end
    finderHooked = true
    parent:HookScript("OnShow", StartSoon)
    if parent:IsShown() then StartSoon() end
    return true
end

local friendsHooked = false
function Tour.HookFriends()
    local list = _G.FriendsListFrame
    if friendsHooked or type(list) ~= "table" or not list.HookScript then return friendsHooked end
    friendsHooked = true
    list:HookScript("OnShow", StartSoon)
    if list:IsVisible() then StartSoon() end
    return true
end

ns.OnReady(function()
    ns.WhenAddOnLoaded(ns.FINDER_ADDON, Tour.HookFinder)
    if not Tour.HookFriends() then ns.WhenAddOnLoaded("Blizzard_FriendsFrame", Tour.HookFriends) end
end)
