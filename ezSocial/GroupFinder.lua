local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Blizzards Fenster „Gruppe suchen“, Reiter „Durchsuchen“ (Blizzard_GroupFinder_VanillaStyle, lädt bei Bedarf).
    Blizzard zeigt bei Gruppen nur Rollen-Platzhalter und keine Stufe. ezSocial ergänzt am selben Eintrag:
      - Klassen-Symbole der Mitglieder mit Rolle, der Leiter zuerst (über Blizzards Rollen-Symbolen)
      - Stufe bzw. Stufenbereich der Gruppe (dort, wo Blizzard bei Einzelspielern die Stufe zeigt)
      - grüner Rahmen, wenn deine Rolle in der Gruppe noch frei ist
      - Zonen und Dungeons nach deiner Stufe gefärbt (in der Liste und im Auswahlmenü)
      - „gesperrt“ hinter der Aktivität, wenn der Charakter für die Instanz eine Sperre hat (Locks.lua; in der
        Liste und im Auswahlmenü), die Restzeit im Tooltip
      - Knopf „Gespräch“ mit dem Leiter (ezChat, Talk.lua); Blizzards Rechtsklick-Menü hat kein Tag für
        Menu.ModifyMenu, deshalb ein eigener Knopf
    Nur hooksecurefunc und eigene Texturen; die eigenen Teile je Eintrag stehen in einer schwachen Tabelle.
]]

local Finder = {}
ns.Finder = Finder

local ROLE_ORDER = { TANK = 1, HEALER = 2, DAMAGER = 3 }
local ROLE_ATLAS = ns.ROLE_ATLAS
local LEADER_ATLAS = "groupfinder-icon-leader"
local BORDER_COLOR = { 0.1, 0.9, 0.1, 0.9 }

---------------------------------------------------------------------------
-- Daten aus C_LFGList (nur lesen)
---------------------------------------------------------------------------

local Call = Core.Call

-- Mitglieder eines Suchergebnisses: { name, class, level, role, leader }, Leiter zuerst, dann Tank, Heiler, Schaden.
function Finder.Members(resultID)
    local api = C_LFGList
    local info = api and Call(api.GetSearchResultInfo, resultID)
    local count = info and Core.Num(info.numMembers) or 0
    local list = {}
    for i = 1, count do
        local m = Call(api.GetSearchResultPlayerInfo, resultID, i)
        if type(m) == "table" then
            local class = Core.Plain(m.classFilename)
            list[#list + 1] = {
                index = i,
                name = Core.Plain(m.name),
                class = type(class) == "string" and class or nil,
                level = Core.Num(m.level),
                role = Core.Plain(m.assignedRole),
                leader = Core.Bool(m.isLeader, false),
            }
        end
    end
    table.sort(list, function(a, b)
        if a.leader ~= b.leader then return a.leader end
        local ra, rb = ROLE_ORDER[a.role] or 4, ROLE_ORDER[b.role] or 4
        if ra ~= rb then return ra < rb end
        return a.index < b.index
    end)
    return list
end

-- Kleinste und größte Stufe der Mitglieder (nil ohne Angaben).
function Finder.LevelRange(members)
    local low, high
    for _, m in ipairs(members) do
        if m.level and m.level > 0 then
            low = (low == nil or m.level < low) and m.level or low
            high = (high == nil or m.level > high) and m.level or high
        end
    end
    return low, high
end

-- Rollen, die du im Fenster gewählt hast (Blizzards eigene Abfrage), sonst alle.
local function MyRoles()
    local getter = (C_LFGListRoles and C_LFGListRoles.GetRoles) or (C_LFGList and C_LFGList.GetRoles)
    local roles = Call(getter)
    if type(roles) == "table" then
        return { tank = roles.tank == true, healer = roles.healer == true, dps = roles.dps == true }
    end
    return { tank = true, healer = true, dps = true }
end

-- Hat die Gruppe noch einen Platz für eine deiner Rollen? (Wie Blizzards HasRemainingSlotsForLocalPlayerRole.)
function Finder.HasSlotForMe(resultID)
    local counts = C_LFGList and Call(C_LFGList.GetSearchResultMemberCounts, resultID)
    if type(counts) ~= "table" then return false end
    local roles = MyRoles()
    local function Free(key) return (Core.Num(counts[key]) or 0) > 0 end
    return (roles.tank and Free("TANK_REMAINING")) or (roles.healer and Free("HEALER_REMAINING"))
        or (roles.dps and Free("DAMAGER_REMAINING")) or false
end

-- Stufen einer Aktivität (Zone oder Dungeon) liest ezCore.Dungeons.ActivityLevels – dieselbe Regel wie die
-- Dungeon-Tabelle, damit die Liste und der Reiter „Aus dem Chat“ einen Dungeon gleich färben.

-- Gemeinsamer Bereich mehrerer Aktivitäten: min, max oder nil.
function Finder.ActivitiesRange(activityIDs)
    local low, high
    for _, id in ipairs(activityIDs or {}) do
        local a, b = Core.Dungeons.ActivityLevels(id)
        if a then low = (low == nil or a < low) and a or low end
        if b then high = (high == nil or b > high) and b or high end
    end
    if not low and not high then return nil end
    return low or high, high or low
end

---------------------------------------------------------------------------
-- Eigene Teile an Blizzards Einträgen
---------------------------------------------------------------------------

local extras = setmetatable({}, { __mode = "k" })

local function Border(entry)
    local edges = {}
    local function Edge(p1, p2, w, h)
        local t = entry:CreateTexture(nil, "OVERLAY", nil, 2)
        t:SetColorTexture(BORDER_COLOR[1], BORDER_COLOR[2], BORDER_COLOR[3], BORDER_COLOR[4])
        t:SetPoint(p1[1], entry, p1[1], p1[2], p1[3])
        t:SetPoint(p2[1], entry, p2[1], p2[2], p2[3])
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
        t:Hide()
        edges[#edges + 1] = t
    end
    -- Gleiche Fläche wie Blizzards Hintergrund des Eintrags (ResultBG: 3 / -2 bis -3 / 0).
    Edge({ "TOPLEFT", 3, -2 }, { "TOPRIGHT", -3, -2 }, nil, 2)
    Edge({ "BOTTOMLEFT", 3, 0 }, { "BOTTOMRIGHT", -3, 0 }, nil, 2)
    Edge({ "TOPLEFT", 3, -2 }, { "BOTTOMLEFT", 3, 0 }, 2, nil)
    Edge({ "TOPRIGHT", -3, -2 }, { "BOTTOMRIGHT", -3, 0 }, 2, nil)
    return edges
end

local function Extras(entry)
    local x = extras[entry]
    if x then return x end
    x = { icons = {} }
    -- Rolle „off“ (GameFontDisable) links bündig – dasselbe wie Blizzards GameFontDisableLeft, aber in den Rollen
    -- des Design-Systems (2.4, Welle 22)
    x.levels = entry:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    x.levels:SetJustifyH("LEFT")
    x.levels:SetHeight(14)
    x.levels:Hide()
    x.border = Border(entry)
    extras[entry] = x
    return x
end

local function SetShownAll(list, shown)
    for _, region in ipairs(list) do region:SetShown(shown) end
end

-- Überlagerung eines Rollen-Symbols: Klasse groß, Rolle klein unten rechts, Krone für den Leiter.
local function Overlay(x, index, icon)
    local o = x.icons[index]
    if o then return o end
    local parent = icon:GetParent()
    o = {}
    -- Rolle und Krone 12 × 12 wie Blizzards Abzeichen auf demselben Symbol (LFGListGroupDataDisplayClassRoleTemplate:
    -- RoleIcon und LeaverIcon 12 × 12, Blizzard_GroupFinder/Mainline/LFGList.xml) – die Größe folgt Blizzard.
    o.class = parent:CreateTexture(nil, "OVERLAY", nil, 1)
    o.class:SetAllPoints(icon)
    o.role = parent:CreateTexture(nil, "OVERLAY", nil, 3)
    o.role:SetSize(12, 12)
    o.role:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -2)
    o.leader = parent:CreateTexture(nil, "OVERLAY", nil, 3)
    o.leader:SetSize(12, 12)
    o.leader:SetPoint("TOPLEFT", icon, "TOPLEFT", -2, 2)
    x.icons[index] = o
    return o
end

local function HideOverlay(o)
    o.class:Hide()
    o.role:Hide()
    o.leader:Hide()
end

local function ShowMembers(entry, x, members, disabled)
    local display = ns.Region(entry.DataDisplay)
    local enumerate = display and ns.Region(display.Enumerate)
    local icons = enumerate and ns.Region(enumerate.Icons)
    local shown = 0
    if icons and enumerate:IsShown() then
        for i = 1, #icons do
            if icons[i]:IsShown() then shown = i end
        end
    end
    -- Blizzard zählt die Symbole von rechts nach links; besetzte Plätze stehen links.
    for i = 1, #(icons or {}) do
        local member = shown > 0 and members[shown - i + 1] or nil
        if i <= shown and member and member.class then
            local o = Overlay(x, i, icons[i])
            o.class:SetAtlas("groupfinder-icon-class-" .. member.class:lower(), false)
            o.class:SetDesaturated(disabled)
            o.class:Show()
            if ROLE_ATLAS[member.role] then
                o.role:SetAtlas(ROLE_ATLAS[member.role], false)
                o.role:Show()
            else
                o.role:Hide()
            end
            if member.leader then
                o.leader:SetAtlas(LEADER_ATLAS, false)
                o.leader:Show()
            else
                o.leader:Hide()
            end
        elseif x.icons[i] then
            HideOverlay(x.icons[i])
        end
    end
end

local function HideMembers(x)
    for _, o in pairs(x.icons) do HideOverlay(o) end
end

-- Blizzards neutrales Grau für den Namen der Aktivität.
local function Neutral()
    return GRAY_FONT_COLOR or { r = 0.5, g = 0.5, b = 0.5 }
end

local function SameColor(fontString, color)
    if not (fontString and color and fontString.GetTextColor) then return false end
    local r, g, b = fontString:GetTextColor()
    if type(r) ~= "number" then return false end
    return math.abs(r - color.r) < 0.02 and math.abs(g - color.g) < 0.02 and math.abs(b - color.b) < 0.02
end

-- Knopf „Gespräch“ mit dem Leiter (Talk.lua) am Platz von Blizzards Abmelde-Knopf (den gibt es nur am eigenen
-- Eintrag, dort bleibt ezSocials Knopf weg). Blizzards Fenster ist „Secure“: neue Knöpfe nur außerhalb des
-- Kampfes, sonst danach (ezCores Reihe Core.AfterCombat – viele Einträge ergeben ein Auffrischen).
local function SetTalk(entry, x, leader)
    if not x.talk then
        if not (leader and ns.Talk.Enabled()) then return end
        if Core.InCombat() then
            ns.AfterCombat(Finder.Refresh, "talk")
            return
        end
        x.talk = ns.Talk.Button(entry, 24, 22)
        x.talk:SetPoint("RIGHT", ns.Region(entry.DataDisplay) or entry, "RIGHT", -8, 0)
    end
    ns.Talk.Set(x.talk, leader, false)
end
function Finder.TalkButton(entry) return extras[entry] and extras[entry].talk end

-- Tooltip mit der Restzeit der Sperren eines Eintrags: unter Blizzards eigenem Tooltip (LFGBrowseSearchEntryTooltip,
-- ein eigener Rahmen rechts neben dem Eintrag), sonst rechts am Eintrag. Blizzards Tooltip bleibt, wie er ist.
function Finder.LockTooltip(entry)
    local x = extras[entry]
    if not (x and x.locks and #x.locks > 0 and ns.Locks.Enabled()) then return false end
    local blizzard = ns.Region(_G.LFGBrowseSearchEntryTooltip)
    GameTooltip:SetOwner(entry, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    if blizzard and blizzard.IsShown and blizzard:IsShown() then
        GameTooltip:SetPoint("TOPLEFT", blizzard, "BOTTOMLEFT", 0, -2)
    else
        GameTooltip:SetPoint("TOPLEFT", entry, "TOPRIGHT", 8, 0)
    end
    if not ns.Locks.FillTooltip(GameTooltip, x.locks) then
        -- Alle Sperren sind inzwischen abgelaufen: der Zusatz geht mit dem Tooltip (keine Markierung ohne Erklärung)
        x.locks = nil
        if x.locked then x.locked:Hide() end
        GameTooltip:Hide()
        return false
    end
    GameTooltip:Show()
    return true
end

-- „gesperrt“ hinter dem Namen der Aktivität (eigene Schrift rechts daneben; Blizzards Text bleibt unberührt).
-- Der Tooltip hängt einmal je Eintrag an dessen OnEnter/OnLeave (HookScript) und liest die Sperren beim Zeigen.
local function SetLocked(entry, x, locks)
    local activity = ns.Region(entry.ActivityName)
    if not (activity and locks and #locks > 0) then
        x.locks = nil
        if x.locked then x.locked:Hide() end
        return
    end
    if not x.locked then
        x.locked = entry:CreateFontString(nil, "ARTWORK", "GameFontRedSmall")
        x.locked:SetPoint("LEFT", activity, "RIGHT", 5, 0)
        if entry.HookScript then
            entry:HookScript("OnEnter", function(self) ns.Try("FinderLock", Finder.LockTooltip, self) end)
            entry:HookScript("OnLeave", function(self)
                if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
            end)
        end
    end
    x.locks = locks
    x.locked:SetText(L.LOCKED)
    x.locked:Show()
end
function Finder.Locks(entry) return extras[entry] and extras[entry].locks or nil end

-- Nach Blizzards LFGBrowseSearchEntry_Update(self): eigene Teile setzen.
function Finder.Decorate(entry)
    if not (entry and entry.resultID) then return end
    local x = Extras(entry)
    local info = C_LFGList and Call(C_LFGList.GetSearchResultInfo, entry.resultID)
    if type(info) ~= "table" then
        x.levels:Hide()
        SetShownAll(x.border, false)
        HideMembers(x)
        SetTalk(entry, x, nil)
        SetLocked(entry, x, nil)
        return
    end
    local delisted = Core.Bool(info.isDelisted, false)
    local hasSelf = Core.Bool(info.hasSelf, false)
    local leader = Core.Plain(info.leaderName)
    SetTalk(entry, x, (not hasSelf and type(leader) == "string") and leader or nil)
    local isGroup = (Core.Num(info.numMembers) or 0) > 1
    local members = isGroup and Finder.Members(entry.resultID) or {}

    -- Mitglieder mit Klasse und Rolle
    if isGroup and ns.Enabled("finderMembers") then
        ShowMembers(entry, x, members, delisted)
    else
        HideMembers(x)
    end

    -- Stufenbereich der Gruppe
    local low, high = Finder.LevelRange(members)
    if isGroup and low then   -- immer (Prüfung der Einstellungen vom 19.11.2026, Nr. 25)
        local discord = ns.Region(entry.DiscordIcon)
        local anchor = (discord and discord:IsShown()) and discord or entry.Name
        x.levels:ClearAllPoints()
        x.levels:SetPoint("BOTTOMLEFT", anchor, "BOTTOMRIGHT", 4, 0)
        x.levels:SetText(ns.LevelText(low, high))
        local grey = delisted and { r = 0.3, g = 0.3, b = 0.3 } or GRAY_FONT_COLOR or { r = 0.5, g = 0.5, b = 0.5 }
        x.levels:SetTextColor(grey.r, grey.g, grey.b)
        x.levels:Show()
    else
        x.levels:Hide()
    end

    -- Grüner Rahmen: deine Rolle ist noch frei
    local free = isGroup and not delisted and not hasSelf and ns.Enabled("finderRoleBorder")
        and Finder.HasSlotForMe(entry.resultID)
    SetShownAll(x.border, free and true or false)

    -- Gesperrte Instanz: „gesperrt“ hinter der Aktivität (nicht an abgemeldeten Gruppen)
    SetLocked(entry, x, not delisted and ns.Locks.OfActivities(info.activityIDs) or nil)

    -- Zone bzw. Dungeon nach deiner Stufe färben. Nur, wo Blizzard das neutrale Grau gesetzt hat
    -- (Blau für „passt zu deinem Eintrag“, Grün für den eigenen und Dunkelgrau für „abgemeldet“ bleiben)
    -- oder noch ezSocials eigene Farbe steht (x.color). Schalter aus oder keine Stufen mehr: Blizzards Grau
    -- zurück, nicht erst bei Blizzards nächstem Neuaufbau (Vollprüfung V-131).
    local activity = ns.Region(entry.ActivityName)
    local ours = x.color ~= nil and SameColor(activity, x.color)
    if activity and (ours or SameColor(activity, Neutral())) then
        local r, g, b
        if ns.Enabled("colors") and not delisted and not hasSelf then
            r, g, b = ns.RangeRGB(Finder.ActivitiesRange(info.activityIDs))
        end
        if r then
            activity:SetTextColor(r, g, b)
            x.color = { r = r, g = g, b = b }
        else
            if ours then
                local grey = Neutral()
                activity:SetTextColor(grey.r, grey.g, grey.b)
            end
            x.color = nil
        end
    else
        x.color = nil   -- Blizzard hat inzwischen selbst gefärbt (Blau, Grün, abgemeldet)
    end
end

-- Hat ezSocial die Aktivität dieses Eintrags gefärbt? (für Tests und /dump)
function Finder.Colored(entry)
    return extras[entry] ~= nil and extras[entry].color ~= nil
end

-- Alle sichtbaren Einträge neu schmücken (nach einer Änderung der Einstellungen).
function Finder.Refresh()
    local frame = _G.LFGBrowseFrame
    local box = frame and frame.ScrollBox
    if not (box and box.ForEachFrame and frame:IsShown()) then return end
    box:ForEachFrame(function(entry) ns.Try("Finder", Finder.Decorate, entry) end)
end

---------------------------------------------------------------------------
-- Auswahlmenü „Aktivität“: Zonen und Dungeons nach Stufe färben, gesperrte Instanzen markieren
-- (Blizzards Menü-Schnittstelle für Addons)
---------------------------------------------------------------------------

local function ElementText(desc)
    if MenuUtil and MenuUtil.GetElementText then
        local ok, text = pcall(MenuUtil.GetElementText, desc)
        if ok and type(text) == "string" then return text end
    end
    return type(desc.text) == "string" and desc.text or nil
end

-- Aktivität eines Menüeintrags: nur, wenn data eine Aktivität ist und ihr Name im Text steht (die Kennungen der
-- Aktivitätsgruppen sind auch Zahlen). → Info-Tabelle von C_LFGList.GetActivityInfoTable oder nil.
function Finder.MenuActivity(data, text)
    if type(data) ~= "number" or type(text) ~= "string" then return nil end
    local info = C_LFGList and Call(C_LFGList.GetActivityInfoTable, data)
    if type(info) ~= "table" then return nil end
    local name = (type(info.shortName) == "string" and info.shortName ~= "") and info.shortName or info.fullName
    if type(name) ~= "string" or name == "" or not text:find(name, 1, true) then return nil end
    return info
end

-- Farbe für einen Menüeintrag: nur für eine Aktivität mit Stufen.
function Finder.MenuColor(data, text)
    local info = Finder.MenuActivity(data, text)
    if not info then return nil end
    local low, high = Core.Dungeons.ActivityLevels(info)
    if not (low or high) then return nil end
    return ns.RangeRGB(low, high)
end

-- Sperre des Charakters für die Aktivität eines Menüeintrags, sonst nil.
function Finder.MenuLock(data, text)
    if not ns.Locks.Enabled() then return nil end
    local info = Finder.MenuActivity(data, text)
    return info and ns.Locks.OfActivity(info) or nil
end

-- „(gesperrt)“ hinter den Text eines Menüknopfs (einmal; Blizzard beschriftet ihn bei jedem Öffnen neu).
function Finder.MarkMenuText(fontString)
    if not (fontString and fontString.GetText) then return false end
    local text = fontString:GetText()
    if Core.IsSecret(text) or type(text) ~= "string" or ns.Locks.HasMark(text) then return false end
    local set = fontString.SetTextToFit or fontString.SetText   -- Blizzards Menü misst die Breite am Text
    if not set then return false end
    set(fontString, text .. " " .. ns.Locks.Mark())
    return true
end

-- Tooltip eines gesperrten Menüeintrags: Name der Aktivität, Sperre und Restzeit. Hat der Eintrag schon einen
-- eigenen Tooltip von Blizzard, bleibt der.
function Finder.MenuLockTooltip(desc, lock)
    if type(desc.SetTooltip) ~= "function" then return false end
    if type(desc.GetOnEnter) == "function" and desc:GetOnEnter() ~= nil then return false end
    desc:SetTooltip(function(tooltip, description)
        local title = ElementText(type(description) == "table" and description or desc)
        ns.Locks.FillTooltip(tooltip, { lock }, title and Core.Trim(title) or nil)
    end)
    return true
end

local function Walk(desc, depth, color, locked)
    if depth > 3 or type(desc) ~= "table" or type(desc.EnumerateElementDescriptions) ~= "function" then return end
    local ok, iter, state, start = pcall(desc.EnumerateElementDescriptions, desc)
    if not ok or type(iter) ~= "function" then return end
    -- Blizzard liefert (Index, Eintrag); ein Iterator, der nur den Eintrag liefert, geht auch.
    for first, second in iter, state, start do
        local child = type(second) == "table" and second or first
        if type(child) == "table" then
            local data = type(child.GetData) == "function" and child:GetData() or nil
            local label = ElementText(child)
            local r, g, b
            if color then r, g, b = Finder.MenuColor(data, label) end
            local lock = locked and Finder.MenuLock(data, label) or nil
            if (r or lock) and type(child.AddInitializer) == "function" then
                child:AddInitializer(function(button)
                    local text = button and (ns.Region(button.fontString) or ns.Region(button.Text))
                    if not text then return end
                    if r and text.SetTextColor then text:SetTextColor(r, g, b) end
                    if lock then Finder.MarkMenuText(text) end
                end)
            end
            if lock then Finder.MenuLockTooltip(child, lock) end
            Walk(child, depth + 1, color, locked)
        end
    end
end

function Finder.ColorActivityMenu(_, rootDescription)
    local color, locked = ns.Enabled("colors"), ns.Locks.Any()
    if not (color or locked) then return end
    Walk(rootDescription, 0, color, locked)
end

---------------------------------------------------------------------------
-- Anmelden, sobald Blizzards Fenster geladen ist
---------------------------------------------------------------------------

local hooked = false
function Finder.Hook()
    if hooked or type(LFGBrowseSearchEntry_Update) ~= "function" then return hooked end
    hooked = true
    hooksecurefunc("LFGBrowseSearchEntry_Update", function(entry) ns.Try("Finder", Finder.Decorate, entry) end)
    if Menu and type(Menu.ModifyMenu) == "function" then
        Menu.ModifyMenu("MENU_LFG_BROWSE_ACTIVITY", function(...) ns.Try("FinderMenu", Finder.ColorActivityMenu, ...) end)
    end
    return true
end

ns.OnReady(function()
    ns.WhenAddOnLoaded(ns.FINDER_ADDON, Finder.Hook)
end)

ns.OnSettingChanged(function(key)
    if key:find("^finder") or key == "colors" or key == "talkButtons" then Finder.Refresh() end
end)
