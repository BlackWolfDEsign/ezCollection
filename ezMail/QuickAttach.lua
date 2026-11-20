local _, ns = ...
local L = ns.L
local Menu = ezCore.Menu     -- Menüs an einer Stelle (Blizzards MenuUtil)

--[[
    Schnellanhängen nach Art: Auf „Verschicken“ stehen rechts am Postfenster Seitenreiter wie im
    Zauberbuch – einer je Gegenstandsart in den Taschen (Stoff, Kräuter, Metall und Stein, Edelsteine,
    Ausrüstung …), mit dem Icon eines echten Gegenstands und der Zahl der Stapel. Ein Klick hängt alle
    ungebundenen Stapel dieser Art an; was nicht mehr passt, folgt nach dem Senden (Nachsenden).
    Gibt es mehr Arten als Reiter, öffnet der letzte ein Menü mit allen. Zusätzlich öffnet ein
    Rechtsklick auf einen leeren Anhangplatz dasselbe Menü. Die Namen der Arten liefert der Client.
]]

local QA = {}
ns.QuickAttach = QA

-- Reihenfolge der Hauptarten (Enum.ItemClass): Handwerkswaren, Edelsteine, Reagenzien, Verbrauchbares,
-- Rezepte, Ausrüstung (Waffen und Rüstung zusammen, nach Qualität), Behälter, Verschiedenes.
local CLASS_ORDER = { [7] = 1, [3] = 2, [5] = 3, [0] = 4, [9] = 5, equip = 6, [1] = 7, [15] = 8 }
local EQUIPMENT = { [2] = true, [4] = true }
local SKIP_CLASS = { [12] = true }   -- Questgegenstände

local MAX_TABS = 6           -- darunter bleibt Platz für den Nachsenden-Reiter
local TAB_TOP = -48          -- unter der Titelleiste; Abstand und Reihenfolge setzt ezCores Seitenreiter-Stapel
local MORE_ICON = "Interface\\Icons\\INV_Misc_Bag_08"

local hooked = 0
local tabs = {}

-- Namen der Arten und Unterarten: ein Helfer in ezCore (Core.ItemClassName, V-063; vorher hier und in ezBag kopiert)
local function ClassName(classID)
    return ezCore.ItemClassName(classID)
end

local function SubClassName(classID, subClassID)
    return ezCore.ItemClassName(classID, subClassID)
end

local function QualityName(quality) return ezCore.QualityText(quality) end   -- ezCore (Gesamtreview 18.11.2026, T16-6)

-- Ungebundene, verschickbare Stapel in den Taschen, nach Art gruppiert und sortiert.
-- Ergebnis: { { name, list, groups = { { name, list } } } }
function QA.Scan()
    local classes, byKey = {}, {}
    -- "sell": alle getragenen Taschen samt Reagenzientasche, ohne Schlüsselbund (ezCores Taschenliste, V-063)
    ns.ForEachBagItem(function(bag, slot, info)
        if info.isBound or info.isLocked or (info.quality or 1) == 0 then return end
        local classID, subClassID = ezCore.ItemClass(info.itemID)     -- ezCore: sofort, gesperrt → nil (V-177)
        if not classID or SKIP_CLASS[classID] then return end

        local classKey = EQUIPMENT[classID] and "equip" or classID
        local class = byKey[classKey]
        if not class then
            class = {
                name = classKey == "equip" and L.QA_EQUIPMENT or ClassName(classID) or tostring(classID),
                sort = CLASS_ORDER[classKey] or (100 + classID),
                groups = {}, byKey = {}, list = {},
            }
            byKey[classKey] = class
            classes[#classes + 1] = class
        end

        local groupKey, groupName, groupSort
        if classKey == "equip" then
            groupKey, groupName, groupSort = "q" .. (info.quality or 1), QualityName(info.quality or 1), info.quality or 1
        else
            groupKey = "s" .. (subClassID or 0)
            groupName = SubClassName(classID, subClassID or 0) or class.name
            groupSort = subClassID or 0
        end
        local group = class.byKey[groupKey]
        if not group then
            group = { name = groupName, className = class.name, sort = groupSort, list = {} }
            class.byKey[groupKey] = group
            class.groups[#class.groups + 1] = group
        end
        group.list[#group.list + 1] = { bag = bag, slot = slot, itemID = info.itemID, size = info.stackCount or 1,
            icon = info.iconFileID }
    end, "sell")

    -- Gleiche Gegenstände nebeneinander (landen so im selben Brief), große Stapel zuerst.
    local function ByItem(a, b)
        if a.itemID ~= b.itemID then return a.itemID < b.itemID end
        return a.size > b.size
    end
    table.sort(classes, function(a, b) return a.sort < b.sort end)
    for _, class in ipairs(classes) do
        table.sort(class.groups, function(a, b) return a.sort < b.sort end)
        for _, group in ipairs(class.groups) do
            table.sort(group.list, ByItem)
            for _, entry in ipairs(group.list) do class.list[#class.list + 1] = entry end
        end
    end
    return classes
end

-- Kopie der Einträge: die Warteschlange schreibt in ihre Einträge (Wartezeit, neuer Platz).
local function Attach(list)
    local copy = {}
    for i, entry in ipairs(list) do copy[i] = { bag = entry.bag, slot = entry.slot, itemID = entry.itemID } end
    ns.Send.AttachEntries(copy)
end

function QA.ShowMenu(owner)
    local classes = QA.Scan()
    local opened = Menu.Open(owner, function(root)
        Menu.Title(root, L.QA_TITLE)
        if #classes == 0 then
            Menu.Title(root, L.QA_EMPTY)
            return
        end
        for _, class in ipairs(classes) do
            local sub = Menu.Button(root, L.QA_ENTRY:format(class.name, #class.list))
            if #class.groups > 1 then
                Menu.Button(sub, L.QA_ALL:format(class.name, #class.list), function() Attach(class.list) end)
                Menu.Divider(sub)
            end
            for _, group in ipairs(class.groups) do
                Menu.Button(sub, L.QA_ENTRY:format(group.name, #group.list), function() Attach(group.list) end)
            end
        end
        Menu.Divider(root)
        Menu.Title(root, ns.S.followUp and L.QA_NOTE or L.QA_NOTE_NO_FOLLOW)
    end)
    if not opened then ns.Print(L.NO_MENU) end
end

---------------------------------------------------------------------------
-- Seitenreiter rechts am Postfenster
---------------------------------------------------------------------------

local function Groups(classes)
    local list = {}
    for _, class in ipairs(classes) do
        for _, group in ipairs(class.groups) do list[#list + 1] = group end
    end
    return list
end

local function GroupIcon(group)
    local first = group.list[1]
    local icon = first and first.icon
    if not icon and first and C_Item and C_Item.GetItemIconByID then icon = C_Item.GetItemIconByID(first.itemID) end
    return icon or MORE_ICON
end

-- Grund, warum die Reiter gesperrt sind – aus derselben Bedingung wie RefreshTabs (T9-7; Gegenprüfung 18.11.2026:
-- vorher immer „hängt an“, auch während des Nachsendens, und am Überlauf-Reiter gar keiner). "": nicht gesperrt.
local function BusyReason(tab)
    if not (tab.IsEnabled and not tab:IsEnabled()) then return "" end
    local why = (ns.SendQueue.IsAttaching() and L.ATTACH_BUSY) or (ns.SendQueue.IsBusy() and L.QA_SEND_BUSY) or nil
    return why and ("\n\n" .. ezCore.Style.ColorText("bad", why)) or ""
end

local function ShowTabTip(tab)
    local group = tab.group
    if tab.more then
        ns.ShowTip(tab, L.QA_MORE, ezCore.More(tab.more) .. " " .. L.QA_MORE_TAIL .. BusyReason(tab))
    elseif group then
        local title = group.className ~= group.name and (group.className .. ": " .. group.name) or group.name
        local text = L.QA_TAB_TIP:format(#group.list)
        if ns.S.followUp then text = text .. "\n" .. L.QA_TAB_FOLLOW end
        if ns.S.altAttach then text = text .. "\n" .. L.QA_TAB_ALT end
        -- gesperrt, solange ezMail anhängt oder verschickt: der Tooltip nennt den Grund (T9-7)
        text = text .. BusyReason(tab)
        ns.ShowTip(tab, title, text)
    end
end

local function OnTabClick(tab)
    if tab.more then
        QA.ShowMenu(tab)
    elseif tab.group then
        Attach(tab.group.list)
    end
end

local function CreateTab(i)
    -- Stapel „Brief schreiben“ von oben (vereinbart: Schnell-Anhänge 10); bei gleicher Zahl entscheidet der Name.
    local tab = ns.CreateSideTab(SendMailFrame, { key = "ezMail.quick" .. i, order = 10, start = TAB_TOP,
        owner = "ezMail" })
    tab:SetScript("OnClick", ns.SideTabClick(OnTabClick))
    tab:SetScript("OnEnter", ShowTabTip)
    ezCore.Toolbar.ShowTipWhileDisabled(tab)
    tab:Hide()
    tabs[i] = tab
    return tab
end

local function RefreshTabs()
    if not (SendMailFrame and tabs[1]) then return end
    local groups = (ns.S.quickAttach and SendMailFrame:IsVisible()) and Groups(QA.Scan()) or {}
    local busy = ns.SendQueue.IsBusy() or ns.SendQueue.IsAttaching()
    local overflow = #groups > MAX_TABS
    for i = 1, MAX_TABS do
        local tab, group = tabs[i], groups[i]
        tab.group, tab.more = nil, nil
        if overflow and i == MAX_TABS then
            tab.more = #groups - MAX_TABS + 1
            tab.Icon:SetTexture(MORE_ICON)
            tab.Count:SetText("+" .. tab.more)
        elseif group then
            tab.group = group
            tab.Icon:SetTexture(GroupIcon(group))
            tab.Count:SetText(#group.list)
        end
        tab:SetShown(tab.group ~= nil or tab.more ~= nil)
        tab:SetEnabled(not busy)
        tab.Icon:SetDesaturated(busy)
    end
end

-- Mehrere Taschen-Ereignisse kurz hintereinander: nur einmal neu zählen (ezCores Drossel ns.Throttle, Gesamtreview
-- 18.11.2026, T16-13 – vorher von Hand nachgebaut; ein Fehler landet jetzt in der Fehlerliste von ezMail).
QA.RefreshTabs = ns.Throttle(RefreshTabs, 0.1)

-- Erster Reiter (Ziel einer Erklärblase, Tour.lua)
function QA.FirstTab() return tabs[1] end

function QA.VisibleTabs()
    local n = 0
    for _, tab in ipairs(tabs) do if tab:IsShown() then n = n + 1 end end
    return n
end

local function CreateTabs()
    if tabs[1] or not SendMailFrame then return end
    for i = 1, MAX_TABS do CreateTab(i) end
    SendMailFrame:HookScript("OnShow", QA.RefreshTabs)
    QA.RefreshTabs()
end

---------------------------------------------------------------------------
-- Einhängen: Seitenreiter und Rechtsklick auf einen leeren Anhangplatz
---------------------------------------------------------------------------

local wasEmpty = {}

local function HookSlots()
    for i = 1, ATTACHMENTS_MAX_SEND or 12 do
        local button = _G["SendMailAttachment" .. i]
        if button then
            -- Vorher merken: Blizzards Rechtsklick leert einen belegten Platz – das ist kein leerer.
            button:HookScript("PreClick", function(self)
                wasEmpty[self] = not HasSendMailItem(self:GetID()) and not CursorHasItem()
            end)
            button:HookScript("PostClick", function(self, mouse)
                if mouse == "RightButton" and wasEmpty[self] and ns.S.quickAttach then QA.ShowMenu(self) end
                wasEmpty[self] = nil
            end)
            hooked = hooked + 1
        end
    end
    if type(SendMailAttachment_OnEnter) == "function" then
        hooksecurefunc("SendMailAttachment_OnEnter", function(self)
            if ns.S.quickAttach and not HasSendMailItem(self:GetID()) then
                GameTooltip:AddLine(L.QA_TIP, nil, nil, nil, true)
                GameTooltip:Show()
            end
        end)
    end
end

ns.WhenMailUI("Schnellanhängen", HookSlots)
ns.WhenMailUI("Schnellanhängen-Reiter", CreateTabs)

ns.OnStatus(function()
    return L.STATUS_QA:format(QA.VisibleTabs(), #tabs, hooked)
end)

ns.On("BAG_UPDATE_DELAYED", function() if SendMailFrame and SendMailFrame:IsVisible() then QA.RefreshTabs() end end)
ns.On("MAIL_SEND_INFO_UPDATE", QA.RefreshTabs)
ns.On("MAIL_SEND_SUCCESS", QA.RefreshTabs)
ns.Listen("QUEUE_CHANGED", QA.RefreshTabs)
ns.OnSettingChanged(function(key)
    if key == "quickAttach" or key == "followUp" then QA.RefreshTabs() end
end)
