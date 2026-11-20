local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Blizzards Verfolgung nach Stufe sortieren, niedrigste zuerst.
    Blizzard ordnet die verfolgten Quests nach der Reihenfolge, in der sie verfolgt wurden, und sortiert sie
    beim Zonenwechsel selbst um (C_QuestLog.SortQuestWatches). ezQuest meldet sie deshalb ab der ersten falschen
    Stelle über Blizzards eigene API neu an – Blizzards Code und Tabellen bleiben unberührt, nur außerhalb des
    Kampfes. Der Knopf sitzt am Kopf „Quests“ der Verfolgung (wandert mit ihr im Bearbeitungsmodus).
    Rücksicht auf andere Addons (Leitlinie 9): Ersetzt Questies eigener Tracker Blizzards Verfolgung oder sortiert
    Forever Tweaks sie schon, hält sich ezQuest zurück (Tracker.Other, Erkennung über ezCore).

    Ab Werk aus (Welle 29, NACH-27; Grundsatz des Nutzers vom 17.11.2026, wörtlich „user muss auf sowas hingewiesen
    werden, er kann es nutzen muss es aber einschalten“): Das Sortieren meldet Quests ohne Klick bei Blizzard ab und wieder
    an – das stellt Blizzards Questverfolgung um (sortTracker, ab Werk aus). Dabei endet kurz Blizzards Zielverfolgung
    einer abgemeldeten Quest; sie setzt ezQuest nur mit dem eigenen Schalter sortSuperTrack zurück (ab Werk aus). Ohne
    ihn wartet das Sortieren, solange die Zielverfolgung einer Quest folgt, die es abmelden müsste (Tracker.waiting) –
    sonst beendete ezQuest sie ohne Klick. Der Knopf „Jetzt sortieren“ (ein Klick) sortiert trotzdem und setzt sie
    zurück. Einmal umgestellt in ns.MigrateSortOptIn (Core.lua), Hinweis an der Questverfolgung über ezCores
    Core.OptInHint (Tracker.RegisterOptInHints).
]]

local Tracker = {}
ns.Tracker = Tracker

local applying = false
local button

-- Wer die Verfolgung schon übernimmt: Questies Tracker ersetzt sie (questTracker), Forever Tweaks sortiert sie
-- selbst (questSort). Rückgabe: Name des Addons, Funktion – sonst nil.
function Tracker.Other()
    local name = ns.OtherHandles("questTracker")
    if name then return name, "questTracker" end
    name = ns.OtherHandles("questSort")
    if name then return name, "questSort" end
    return nil
end

function Tracker.Active()
    return ns.Enabled("sortTracker") and not Tracker.Other()
end

local function Level(questID)
    local level = Core.Num(Core.Call(C_QuestLog and C_QuestLog.GetQuestDifficultyLevel, questID))
    if level and level > 0 then return level end
    return math.huge   -- ohne Stufe ans Ende
end

function Tracker.Watched()
    local list = {}
    if not (C_QuestLog and C_QuestLog.GetNumQuestWatches and C_QuestLog.GetQuestIDForQuestWatchIndex) then return list end
    local count = Core.Num(C_QuestLog.GetNumQuestWatches()) or 0
    for i = 1, count do
        local questID = Core.Num(C_QuestLog.GetQuestIDForQuestWatchIndex(i))
        if questID then list[#list + 1] = questID end
    end
    return list
end

-- Nach Stufe; bei gleicher Stufe bleibt die bisherige Reihenfolge (stabil).
function Tracker.Ordered(list)
    local entries = {}
    for i, questID in ipairs(list) do entries[i] = { id = questID, level = Level(questID), pos = i } end
    table.sort(entries, function(a, b)
        if a.level ~= b.level then return a.level < b.level end
        return a.pos < b.pos
    end)
    local ordered = {}
    for i, entry in ipairs(entries) do ordered[i] = entry.id end
    return ordered
end

-- Blizzards Zielverfolgung (Super-Tracking) endet, sobald ihre Quest nicht mehr verfolgt wird – auch kurz beim
-- Neu-Anmelden (Blizzard_QuestSuperTracking, nach dem Ereignis). ezQuest merkt sie sich und setzt sie zurück.
local function SuperTracked()
    local questID = Core.Num(Core.Call(C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID))
    return questID and questID > 0 and questID or nil
end

-- Der zweite Versuch läuft 0,2 Sekunden später im Zeitgeber: hat inzwischen ein Kampf begonnen, setzt ezQuest die
-- Zielverfolgung nicht im Kampf, sondern erst danach (ns.AfterCombat; Prüfung auf Blizzards Regeln vom 17.11.2026,
-- Risiko 22 – C_SuperTrack gilt in Forevers Entwickler-Hinweisen als Taint-Weg, V-183). Nur mit sortSuperTrack bzw.
-- nach einem Klick auf „Jetzt sortieren“ (Tracker.Sort).
local function RestoreSuperTrack(questID)
    if not (questID and C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID) then return end
    local function Restore()
        if Core.InCombat() then
            ns.AfterCombat(Restore, "superTrack")
            return
        end
        if SuperTracked() == nil then Core.Call(C_SuperTrack.SetSuperTrackedQuestID, questID) end
    end
    Restore()
    C_Timer.After(0.2, Restore)
end

-- true, wenn umsortiert wurde. Im Kampf: gemerkt und nach dem Kampf nachgeholt (false, "combat"). byHand: ein Klick
-- („Jetzt sortieren“) – dann sortiert ezQuest auch, wenn die Zielverfolgung einer betroffenen Quest folgt, und setzt sie
-- zurück; ein Klick im Kampf bleibt ein Klick, auch wenn danach noch ein Sortieren ohne Klick dazukommt
-- (Tracker.pendingByHand; Fund der Gegenprüfung vom 17.11.2026).
-- Ohne Klick und ohne sortSuperTrack: false, solange die Zielverfolgung einer Quest folgt, die das Sortieren abmelden
-- müsste (Tracker.waiting = ihre ID; SUPER_TRACKING_CHANGED holt es nach).
function Tracker.Sort(byHand)
    if applying or not Tracker.Active() then return false end
    if not (C_QuestLog and C_QuestLog.AddQuestWatch and C_QuestLog.RemoveQuestWatch) then return false end
    if Core.InCombat() then
        -- ezCore holt es nach dem Kampf nach; gleicher Schlüssel = nur ein wartender Aufruf
        if byHand == true then Tracker.pendingByHand = true end
        ns.AfterCombat(function()
            if Tracker.pendingByHand then
                Tracker.pendingByHand = nil
                Tracker.Sort(true)
            else
                Tracker.Request()
            end
        end, "sort")
        return false, "combat"
    end
    local list = Tracker.Watched()
    local ordered = Tracker.Ordered(list)
    local first
    for i = 1, #list do
        if list[i] ~= ordered[i] then first = i break end
    end
    Tracker.waiting = nil
    if not first then return false end
    local superTracked = SuperTracked()
    local restore = byHand == true or ns.Enabled("sortSuperTrack")
    if superTracked and not restore then
        for i = first, #list do
            if list[i] == superTracked then
                Tracker.waiting = superTracked
                return false
            end
        end
        superTracked = nil       -- liegt vor der ersten falschen Stelle: bleibt angemeldet, nichts zurückzusetzen
    end
    applying = true
    local ok, err = pcall(function()
        for i = first, #list do C_QuestLog.RemoveQuestWatch(list[i]) end
        for i = first, #ordered do C_QuestLog.AddQuestWatch(ordered[i]) end
    end)
    applying = false
    if restore then RestoreSuperTrack(superTracked) end
    if not ok then ns.Error(err, "Tracker.Sort") end
    return ok
end

-- Viele Meldungen in kurzer Zeit (Zonenwechsel, mehrere Quests angenommen) lösen nur ein Sortieren aus;
-- die Verzögerung lässt Blizzards eigenes Sortieren beim Zonenwechsel zuerst laufen.
Tracker.Request = ns.Throttle(function() Tracker.Sort() end, 0.5)

-- Knopf „Jetzt sortieren“ in den Einstellungen: ein Klick (Tracker.Sort(true)). Ist nichts zu tun, sagt der Chat es;
-- im Kampf, dass gleich danach sortiert wird (nicht „schon sortiert“). → wie Tracker.Sort
function Tracker.SortNow()
    local ok, why = Tracker.Sort(true)
    if ok then return true end
    if why == "combat" then
        Core.CombatNotice(ns, L.SORT_WHAT, "later")   -- ezCores eine Meldung (T18-1)
    else
        ns.Print(Tracker.Active() and L.SORT_ALREADY or L.SORT_INACTIVE)
    end
    return false, why
end

---------------------------------------------------------------------------
-- Knopf am Kopf „Quests“ der Verfolgung
---------------------------------------------------------------------------

function Tracker.UpdateButton()
    if not button then return end
    local on = Tracker.Active()
    button.icon:SetDesaturated(not on)
    button.icon:SetAlpha(on and 1 or 0.5)
end

local function ShowButtonTip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    Core.TipTitle(GameTooltip, L.TRACKER_BUTTON)
    local other, feature = Tracker.Other()
    if feature == "questTracker" then
        GameTooltip:AddLine(L.TRACKER_OTHER:format(other), nil, nil, nil, true)
    elseif other then
        GameTooltip:AddLine(L.TRACKER_OTHER_SORT:format(other), nil, nil, nil, true)
    else
        GameTooltip:AddLine(ns.Enabled("sortTracker") and L.TRACKER_ON or L.TRACKER_OFF, nil, nil, nil, true)
        if Tracker.waiting and ns.Enabled("sortTracker") then
            Core.TipLine(GameTooltip, L.TRACKER_WAITING, "normal", true)
        end
    end
    Core.TipClick(GameTooltip, L.TRACKER_CLICK)
    Core.TipClick(GameTooltip, L.TIP_COMMAND:format(ns.SlashCmd(L.CMD_SORT)))
    GameTooltip:Show()
end

-- Der Pfeil-Knopf am Kopf „Quests“ (nil, solange Blizzards Verfolgung fehlt); Ziel einer Erklärblase.
function Tracker.Button() return button end

function Tracker.CreateButton()
    if button then return button end
    local module = rawget(_G, "QuestObjectiveTracker")
    local header = type(module) == "table" and module.Header
    if type(header) ~= "table" or not header.CreateTexture then return nil end
    button = CreateFrame("Button", nil, header)
    -- Größe wie Blizzards Knopf daneben (ObjectiveTrackerModuleMinimizeButtonTemplate 16 × 16,
    -- Blizzard_ObjectiveTrackerModule.xml): Core.Style.BUTTON.small (Design-System 2.3; bis Welle 22 14)
    local size = Core.Style.BUTTON.small
    button:SetSize(size, size)
    if header.MinimizeButton then
        button:SetPoint("RIGHT", header.MinimizeButton, "LEFT", -4, 0)
    else
        button:SetPoint("RIGHT", header, "RIGHT", -24, 0)
    end
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    Core.SetIcon(button.icon, "auctionhouse-ui-sortarrow", "Interface\\Buttons\\Arrow-Down-Up")
    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    button:SetScript("OnClick", function()
        ns.SetSetting("sortTracker", not ns.Enabled("sortTracker"))
        if GameTooltip:IsOwned(button) then ShowButtonTip(button) end
    end)
    button:SetScript("OnEnter", ShowButtonTip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Tracker.UpdateButton()
    return button
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------

ns.OnReady(function()
    ns.Try("Tracker", Tracker.CreateButton)
    for _, event in ipairs({ "QUEST_WATCH_LIST_CHANGED", "QUEST_ACCEPTED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED",
        "PLAYER_ENTERING_WORLD" }) do
        ns.On(event, function() if not applying then Tracker.Request() end end)
    end
    -- wartet das Sortieren auf die Zielverfolgung: sobald sie wechselt oder endet, noch einmal versuchen
    ns.On("SUPER_TRACKING_CHANGED", function() if Tracker.waiting and not applying then Tracker.Request() end end)
    Tracker.Request()
end)

ns.OnSettingChanged(function(key)
    if key == "sortSuperTrack" then
        if ns.Enabled("sortSuperTrack") and Tracker.waiting then Tracker.Request() end
        return
    end
    if key ~= "sortTracker" then return end
    Tracker.UpdateButton()
    if ns.Enabled("sortTracker") then Tracker.Request() else Tracker.waiting = nil end
end)

---------------------------------------------------------------------------
-- Hinweis an der Questverfolgung (ezCores Hinweis-Helfer, Welle 29, NACH-27)
---------------------------------------------------------------------------

-- Beide Schalter sind ab Werk aus (Grundsatz des Nutzers vom 17.11.2026). Einmal je Account, wenn du eine Quest annimmst
-- und Blizzards Questverfolgung zu sehen ist; Pfeil auf den Sortier-Pfeil am Kopf „Quests“. Nicht, wenn ein anderes
-- Addon die Verfolgung übernimmt, und nicht, solange dort gerade die Erklärblase von ezQuests Rundgang steht.
-- „Zielverfolgung zurücksetzen“ erst, wenn das Sortieren an ist. Für die beim Update umgestellten (ns.MigrateSortOptIn)
-- sagen beide das dazu (das Zurücksetzen gehörte vorher zum Sortieren).
local function TourShowing()
    local tour = ns.Tour and ns.Tour.tour
    local box = tour and tour.hints and tour.hints.Box and tour.hints.Box("sort")
    return box ~= nil and box.IsShown ~= nil and box:IsShown() == true
end
Tracker.TourShowing = TourShowing   -- auch für die Hinweise zu Funkeln und Symbolen (World.RegisterOptInHints)

function Tracker.RegisterOptInHints()
    local Hint = Core.OptInHint
    if not (Hint and Hint.Register) then return false end
    local function Applies() return not Tracker.Other() and not TourShowing() end
    local function SwitchedOff() return type(ns.db) == "table" and ns.db.sortOff29Was == true end
    local function Target() return Tracker.Button() end
    Hint.Register("ezQuest.sortTracker", {
        owner = ADDON,
        window = "tracker",
        label = function() return L.OPT_sortTracker end,
        what = function() return L.OPTIN_sortTracker end,
        where = function()
            return Core.SettingsPathText("ezQuest", "OPT_HEADER_LEVEL", "OPT_sortTracker", L) .. " " .. L.OPTIN_WHERE_sortTracker
        end,
        isOn = function() return ns.Enabled("sortTracker") end,
        enable = function()
            ns.SetSetting("sortTracker", true)
            return ns.Enabled("sortTracker")
        end,
        applies = Applies,
        switchedOff = SwitchedOff,
        target = Target,
        side = "left",
    })
    Hint.Register("ezQuest.sortSuperTrack", {
        owner = ADDON,
        window = "tracker",
        label = function() return L.OPT_sortSuperTrack end,
        what = function() return L.OPTIN_sortSuperTrack end,
        isOn = function() return ns.Enabled("sortSuperTrack") end,
        enable = function()
            ns.SetSetting("sortSuperTrack", true)
            return ns.Enabled("sortSuperTrack")
        end,
        applies = function() return ns.Enabled("sortTracker") and Applies() end,
        switchedOff = SwitchedOff,
        target = Target,
        side = "left",
    })
    return true
end
Tracker.RegisterOptInHints()
