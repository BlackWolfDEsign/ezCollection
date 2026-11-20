local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Reiter „Aus dem Chat“ in Blizzards Fenster „Gruppe suchen“: ein vierter Seitenreiter unter Blizzards
    drei (Eintragen, Durchsuchen, Wer-Liste), gleiche Vorlage (LargeSideTabButtonTemplate), gleiche
    Hintergründe wie der Reiter „Durchsuchen“.
    Taint-sicher: Blizzards Reiter-Umschaltung bleibt unberührt. Die eigene Fläche liegt über dem Inhalt,
    Blizzards Reiter verlieren nur ihre Markierung (eigene Texturen-Aufrufe, keine Werte in ihren Tabellen);
    ein Klick auf einen ihrer Reiter blendet die Fläche wieder aus (HookScript, hooksecurefunc). Teile von Blizzards
    Reitern, die in einer höheren Schicht liegen (Suchfeld und Lupe der Wer-Liste), sind solange unsichtbar und ohne
    Maus (OVERLAYS unten).
]]

local Tab = {}
ns.ChatTab = Tab

local ROW_HEIGHT, HEADER_HEIGHT = 36, 22
local KINDS = { nil, "lfm", "lfg" }       -- Filter „Zeigen“: alle, LFM, LFG (Index 1–3)
local KIND_TEXT = { "CHAT_SHOW_ALL", "CHAT_SHOW_LFM", "CHAT_SHOW_LFG" }
local ROLES = { { "tank", "TANK" }, { "healer", "HEALER" }, { "dps", "DAMAGER" } }   -- gesucht → ns.ROLE_ATLAS
local ICON = "Interface\\Icons\\INV_Misc_GroupNeedMore"
Tab.ICON = ICON     -- dasselbe Symbol trägt der ezPanel-Baustein „Gruppen-Nachrichten“ (Panel.lua)
local BLIZZARD_TABS = { "ListingTab", "BrowsingTab", "WhoListingTab" }
-- Blizzards Inhalt der drei Reiter (je ein Rahmen über die ganze Fläche, Blizzards LFGParentFrame_SetActiveTab zeigt
-- genau einen davon).
local BLIZZARD_FRAMES = { "LFGListingFrame", "LFGBrowseFrame", "LFGWhoListFrame" }
-- Teile davon, die über der eigenen Fläche liegen, obwohl ihr Reiter darunter verdeckt ist (Forever-Quelle
-- Gethe/wow-ui-source, Zweig forever, Blizzard_GroupFinder_VanillaStyle/Mainline): Suchfeld und Lupe der Wer-Liste
-- stehen in der Schicht HIGH (WhoList.xml: EditBox „WhoFrameEditBox“ und WhoSearch, frameStrata="HIGH"), die
-- senkrechte Trennlinie von „Eintragen“ auf Ebene 501 (Blizzard_LFGVanilla_Listing.xml: DividerFrame). Blizzards
-- Rahmen der Reiter (NineSlice, Titel) bleibt sichtbar – er ist auch der Rahmen der eigenen Fläche.
-- Spielbefund vom 19.11.2026 („fehler von ich von ‚Wer-LISTE‘ auf ‚aus dem chat‘ wechsel“): nach der Wer-Liste lagen
-- Blizzards Suchfeld und Lupe sichtbar und anklickbar über Suche und Filter des Reiters „Aus dem Chat“.
-- Ein Punkt im Namen geht eine Stufe tiefer: das Suchfeld erbt SearchBoxTemplate mit dem Löschknopf „clearButton“
-- (gezeigt, sobald Text im Feld steht). Er erbt die Schicht und die Alpha 0, aber nicht EnableMouse(false) – ohne
-- eigenen Eintrag fing er unsichtbar Klicks auf den Knopf „Zeigen“ ab (Gegenprüfung vom 19.11.2026).
-- Teile laut Blizzards Forever-Quelle (Gethe/wow-ui-source, Zweig forever, Blizzard_GroupFinder_VanillaStyle/Mainline):
-- WhoList.xml – EditBox (WhoFrameEditBox, SearchBoxTemplate mit clearButton) und WhoSearch, beide frameStrata="HIGH";
-- Blizzard_LFGVanilla_Listing.xml – DividerFrame mit frameLevel="501" (die übrigen Knöpfe dort liegen auf Ebene 4).
local OVERLAYS = { LFGWhoListFrame = { "EditBox", "EditBox.clearButton", "WhoSearch" }, LFGListingFrame = { "DividerFrame" } }
Tab.OVERLAYS = OVERLAYS

local panel, sideTab
local kindIndex, searchText = 1, ""
local dimmed = {}           -- [Teil von Blizzard] = { alpha, mouse }: solange die Fläche offen ist ausgeblendet
local activeFrame           -- Blizzards Reiter-Inhalt, der beim Öffnen der Fläche zu sehen war

---------------------------------------------------------------------------
-- Gespräch öffnen: ezChat, sonst Blizzards Flüstern
---------------------------------------------------------------------------

-- Ein Weg für das ganze Modul: Talk.Whisper (Talk.lua). text = vorbereitete Antwort (nur ezChat).
function ns.Whisper(name, text)
    return ns.Talk.Whisper(name, text)
end

-- Antwortvorschlag für eine Gruppen-Nachricht (Schalter chatReply): „LFM“ → ob noch Platz ist, „LFG“ → ob er
-- noch sucht; mit dem Dungeon, wenn die Nachricht genau einen nennt. nil bei ausgeschaltetem Schalter.
function Tab.ReplyFor(e)
    if type(e) ~= "table" or not ns.Enabled("chatReply") then return nil end
    local keys = ns.Chat.DungeonsOf(e) or {}
    local d = #keys == 1 and ns.Chat.DungeonInfo(keys[1]) or nil
    local name = d and type(d.name) == "string" and d.name ~= "" and d.name or nil
    if e.k == "lfm" then
        return name and L.REPLY_LFM_DUNGEON:format(name) or L.REPLY_LFM
    end
    return name and L.REPLY_LFG_DUNGEON:format(name) or L.REPLY_LFG
end

-- Blizzards Spieler-Menü (Flüstern, Einladen, Freund, Ignorieren …).
local function PlayerMenu(name)
    if type(FriendsFrame_ShowDropdown) == "function" then
        FriendsFrame_ShowDropdown(Core.LinkName(name), true)
    end
end

---------------------------------------------------------------------------
-- Zeilen
---------------------------------------------------------------------------

local function KindLabel(kind)
    if kind == "lfm" then return ns.Colored(L.KIND_LFM, 0.25, 1, 0.25) end
    return ns.Colored(L.KIND_LFG, 0.4, 0.75, 1)
end
Tab.KindLabel = KindLabel

-- „Handel, vor 3 Min.“ – Kanal und Alter einer Nachricht (Tooltip im Reiter und am ezPanel-Baustein).
function Tab.WhereText(e)
    local where = e.ch and L["OPT_" .. e.ch] or nil
    return where and L.CHAT_TIP_WHERE:format(where, Core.Ago(e.t)) or Core.Ago(e.t)
end

-- Dungeon-Name in der Farbe der Schwierigkeit (ezCore.Dungeons.Label, hier ohne Stufen).
local function DungeonLabel(key)
    local d = ns.Chat.DungeonInfo(key)
    return d and (Core.Dungeons.Label(d, nil, { range = false })) or nil
end

local function EntryTooltip(row)
    local e = row.entry
    if not e then
        -- Überschrift eines gesperrten Dungeons: Sperre und Restzeit (Locks.lua)
        if not row.lock then return end
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        if ns.Locks.FillTooltip(GameTooltip, { row.lock }) then GameTooltip:Show() else GameTooltip:Hide() end
        return
    end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    -- Zeilen in den Rollen von ezCore (Gesamtreview T9-6): Titel, Nachricht, Herkunft grau, Klick grün
    Core.TipTitle(GameTooltip, e.c and Core.ClassText(Core.ShortName(e.s), e.c) or Core.ShortName(e.s))
    Core.TipLine(GameTooltip, e.m, "highlight", true)
    Core.TipLine(GameTooltip, Tab.WhereText(e), "hint")
    -- Sperren der genannten Dungeons: Restzeit, besiegte Bosse und die Quelle (wie an der Überschrift)
    ns.Locks.AddLines(GameTooltip, ns.Locks.OfDungeons(ns.Chat.DungeonsOf(e)))
    Core.TipClick(GameTooltip, L.CHAT_TIP_CLICK)
    GameTooltip:Show()
end

-- Tooltip des Seitenreiters: Name und Erklärung samt geltendem Befehl (beim Zeigen gelesen – der Kurzbefehl steht
-- erst nach dem Einloggen fest; Gesamtreview T18-2)
function Tab.ShowTabTip(owner)
    Core.ShowTip(owner, L.CHAT_TAB, L.CHAT_TAB_TIP:format(ns.SlashCmd and ns.SlashCmd("chat") or "/ezsocial chat"), "ANCHOR_RIGHT")
end

local function CreateRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAtlas("groupfinder-highlightbar")
    bg:SetPoint("TOPLEFT", 3, -2)
    bg:SetPoint("BOTTOMRIGHT", -3, 0)
    row.bg = bg
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAtlas("groupfinder-highlightbar-blue")
    hl:SetBlendMode("ADD")
    hl:SetPoint("TOPLEFT", 3, -3)
    hl:SetPoint("BOTTOMRIGHT", -3, -1)
    row.hl = hl

    row.name = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", 10, -5)
    row.name:SetJustifyH("LEFT")
    row.kind = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    row.kind:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
    row.roles = {}
    for i = 1, 3 do
        local icon = row:CreateTexture(nil, "ARTWORK")
        -- Symbol in einer Zeile: Core.Style.ICON.line (16; Design-System 2.3, bis Welle 22 14)
        icon:SetSize(Core.Style.ICON.line, Core.Style.ICON.line)
        icon:SetPoint("LEFT", i == 1 and row.kind or row.roles[i - 1], "RIGHT", i == 1 and 4 or 1, 0)
        icon:Hide()
        row.roles[i] = icon
    end
    -- Sichtbarer Knopf für Blizzards Spieler-Menü (Rechtsklick auf die Zeile geht auch).
    row.menu = Core.Toolbar.ArrowButton(row, function()
        if row.entry then PlayerMenu(row.entry.s) end
    end, L.CHAT_MENU, L.CHAT_MENU_TIP)
    row.menu:SetSize(16, 16)
    row.menu:SetPoint("TOPRIGHT", -8, -3)
    row.age = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    row.age:SetPoint("RIGHT", row.menu, "LEFT", -4, 0)
    row.age:SetJustifyH("RIGHT")
    row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.text:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
    row.text:SetPoint("RIGHT", -10, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)

    row.header = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.header:SetPoint("LEFT", 12, -2)
    row.header:SetJustifyH("LEFT")

    row:SetScript("OnClick", function(self, button)
        if not self.entry then return end
        if button == "RightButton" then
            PlayerMenu(self.entry.s)
        else
            ns.Whisper(self.entry.s, Tab.ReplyFor(self.entry))
        end
    end)
    row:SetScript("OnEnter", EntryTooltip)
    row:SetScript("OnLeave", GameTooltip_Hide)
    return row
end

local function ShowHeader(row, group)
    row.entry = nil
    row:SetHeight(HEADER_HEIGHT)
    -- Hat der Charakter für den Dungeon eine Sperre, steht „(gesperrt)“ dahinter und die Überschrift bekommt einen
    -- Tooltip mit der Restzeit; sonst bleibt sie ohne Maus wie bisher.
    local lock = group.key and ns.Locks.OfDungeon(group.key) or nil
    row.lock = lock
    row:EnableMouse(lock ~= nil)
    row.hl:SetAlpha(0)
    for _, region in ipairs({ row.bg, row.name, row.kind, row.age, row.text, row.menu }) do region:Hide() end
    for _, icon in ipairs(row.roles) do icon:Hide() end
    -- „Die Todesminen (17–26)“ in der Farbe der Schwierigkeit (ezCore.Dungeons.Label), dahinter die Anzahl.
    local name = L.CHAT_OTHER
    if group.key then name = Core.Dungeons.Label(group) or tostring(group.key) end
    if lock then name = name .. " " .. ns.Locks.Mark() end
    row.header:SetText(name .. "  " .. Core.Grey("· " .. #group.entries))
    row.header:Show()
end

local function ShowEntry(row, e, withDungeons)
    row.entry = e
    row.lock = nil
    row:SetHeight(ROW_HEIGHT)
    row:EnableMouse(true)
    row.hl:SetAlpha(1)
    row.header:Hide()
    for _, region in ipairs({ row.bg, row.name, row.kind, row.age, row.text, row.menu }) do region:Show() end
    local name = Core.ShortName(e.s)
    row.name:SetText(e.c and Core.ClassText(name, e.c) or name)
    row.kind:SetText(KindLabel(e.k))
    local i = 0
    for _, role in ipairs(ROLES) do
        if e.r and e.r[role[1]] then
            i = i + 1
            row.roles[i]:SetAtlas(ns.ROLE_ATLAS[role[2]], false)
            row.roles[i]:Show()
        end
    end
    for j = i + 1, 3 do row.roles[j]:Hide() end
    row.age:SetText(Core.Ago(e.t))
    local text = e.m or ""
    if withDungeons then
        local labels = {}
        for _, key in ipairs(ns.Chat.DungeonsOf(e) or {}) do
            local label = DungeonLabel(key)
            if label and ns.Locks.OfDungeon(key) then label = label .. " " .. ns.Locks.Mark() end
            labels[#labels + 1] = label
        end
        if #labels > 0 then text = "[" .. table.concat(labels, ", ") .. "] " .. text end
    end
    row.text:SetText(text)
end

---------------------------------------------------------------------------
-- Liste füllen
---------------------------------------------------------------------------

function Tab.Grouped()
    return ns.Enabled("chatGroup")
end

-- Was angezeigt wird: Liste von { group } bzw. { entry } in Reihenfolge.
function Tab.Items()
    local entries = ns.Chat.Filter(KINDS[kindIndex], searchText)
    local items = {}
    if Tab.Grouped() then
        for _, group in ipairs(ns.Chat.Group(entries)) do
            items[#items + 1] = { group = group }
            for _, e in ipairs(group.entries) do items[#items + 1] = { entry = e } end
        end
    else
        for _, e in ipairs(entries) do items[#items + 1] = { entry = e } end
    end
    return items, #entries, entries
end

-- Blendet der Filter „Zeigen“ oder ein Suchtext gerade Nachrichten aus?
function Tab.Filtered()
    return kindIndex ~= 1 or Core.Trim(searchText) ~= ""
end

-- Der Spieler hat gesehen, was in der Liste steht: ohne Filter alles, mit Filter nur die Treffer – was der
-- Filter ausblendet, bleibt „neu“ (für ezPanels Meldung und den Baustein, Panel.lua).
local function MarkSeen(entries)
    if not Tab.Filtered() then return ns.Chat.MarkSeen() end
    return ns.Chat.MarkShown(entries or ns.Chat.Filter(KINDS[kindIndex], searchText))
end

local function UpdateCount()
    if not sideTab then return end
    local count = ns.Chat and #ns.Chat.List() or 0
    sideTab.count:SetText(count > 0 and tostring(count) or "")
end

function Tab.Refresh()
    ns.Chat.Prune()
    UpdateCount()
    if not (panel and panel:IsShown()) then return end
    local items, count, entries = Tab.Items()
    MarkSeen(entries)   -- was bei offenem Reiter in der Liste dazukommt, hat der Spieler gesehen
    local grouped = Tab.Grouped()
    local y = 0
    for i, item in ipairs(items) do
        local row = panel.rows[i]
        if not row then
            row = CreateRow(panel.content)
            panel.rows[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 0, -y)
        row:SetPoint("RIGHT", panel.content, "RIGHT", 0, 0)
        if item.group then ShowHeader(row, item.group) else ShowEntry(row, item.entry, not grouped) end
        row:Show()
        y = y + row:GetHeight()
    end
    for i = #items + 1, #panel.rows do panel.rows[i]:Hide() end
    panel.content:SetHeight(math.max(y, 1))
    panel.empty:SetShown(#items == 0)
    panel.empty:SetText(#ns.Chat.List() == 0 and L.CHAT_EMPTY or L.CHAT_NO_MATCH)
    panel.status:SetText(L.CHAT_STATUS:format(count, ns.S.chatMaxAge))
    panel.kindButton:SetText(L[KIND_TEXT[kindIndex]])
    panel.groupCheck:SetChecked(ns.Enabled("chatGroup"))
    local hints = ns.OtherAddonHints()
    panel.hint:SetText(hints[1] or "")
    -- Erklärblasen zu Filter und Spieler-Menü, sobald die Fläche (und eine Nachricht) zu sehen ist
    if ns.Tour and not ns.Tour.tour:Done() then ns.Tour.Start() end
end

-- Für den Rundgang (Tour.lua): die eigenen Teile im Fenster.
function Tab.Panel() return panel end
function Tab.SideTab() return sideTab end

-- Pfeil für das Spieler-Menü an der ersten sichtbaren Nachricht.
function Tab.FirstMenuButton()
    if not (panel and panel:IsShown()) then return nil end
    for _, row in ipairs(panel.rows) do
        if row:IsShown() and row.entry and row.menu:IsShown() then return row.menu end
    end
    return nil
end

---------------------------------------------------------------------------
-- Fläche im Fenster
---------------------------------------------------------------------------

local function SetBlizzardTabsMarked(marked)
    local parent = _G.LFGParentFrame
    if not parent then return end
    for _, key in ipairs(BLIZZARD_TABS) do
        local tab = ns.Region(parent[key])
        local selectedTexture = tab and ns.Region(tab.SelectedTexture)
        if selectedTexture then
            local selected = marked and parent.selectedTab == tab:GetID()
            selectedTexture:SetShown(selected and true or false)
        end
    end
end

local function SetSideTabMarked(marked)
    if not sideTab then return end
    local selectedTexture = ns.Region(sideTab.SelectedTexture)
    if selectedTexture then
        selectedTexture:SetShown(marked)
    elseif sideTab.SetChecked then
        sideTab:SetChecked(marked)
    end
end

-- Blizzards Reiter-Inhalt, der gerade zu sehen ist (nil, wenn keiner).
function Tab.BlizzardFrame()
    for _, name in ipairs(BLIZZARD_FRAMES) do
        local frame = ns.Region(_G[name])
        if frame and frame.IsShown and frame:IsShown() then return frame end
    end
    return nil
end

-- Teil eines Rahmens über einen Pfad aus OVERLAYS („EditBox.clearButton“); nil, wenn es ihn nicht gibt.
local function OverlayPart(frame, path)
    local region = frame
    for key in path:gmatch("[^%.]+") do
        region = region and ns.Region(region[key])
    end
    return region
end

-- Teile von Blizzard, die über der Fläche lägen, unsichtbar und ohne Maus machen (nur SetAlpha/EnableMouse/ClearFocus
-- auf die Teile selbst: kein Show/Hide; keine Werte in Blizzards Tabellen). ClearFocus löst Blizzards OnEditFocusLost
-- des Suchfelds sofort aus, also aus Addon-Code – das Suchfeld ist nicht geschützt, und ohne ClearFocus liefen
-- Tastatureingaben in ein unsichtbares Feld. Der alte Zustand steht in der eigenen Tabelle dimmed und kommt mit
-- Tab.Hide zurück.
local function DimOverlays()
    for frameName, keys in pairs(OVERLAYS) do
        local frame = ns.Region(_G[frameName])
        for _, key in ipairs(keys) do
            local region = frame and OverlayPart(frame, key)
            if region and not dimmed[region] and region.SetAlpha then
                local mouse = region.IsMouseEnabled and region:IsMouseEnabled() and true or false
                -- Klick und Bewegung getrennt merken (code-reviewer 20.11.2026: ein Teil, das nur Bewegung zuließ,
                -- fing nach EnableMouse(true) auch Klicks ab)
                local click = region.IsMouseClickEnabled and region:IsMouseClickEnabled()
                local motion = region.IsMouseMotionEnabled and region:IsMouseMotionEnabled()
                if click or motion then mouse = true end
                local alpha = region.GetAlpha and region:GetAlpha() or 1
                dimmed[region] = { alpha = type(alpha) == "number" and alpha or 1, mouse = mouse, click = click, motion = motion }
                if region.HasFocus and region:HasFocus() and region.ClearFocus then region:ClearFocus() end
                region:SetAlpha(0)
                if mouse and region.EnableMouse then region:EnableMouse(false) end
            end
        end
    end
end
Tab.DimOverlays = DimOverlays

local function RestoreOverlays()
    for region, state in pairs(dimmed) do
        region:SetAlpha(state.alpha)
        if state.mouse and type(state.click) == "boolean" and type(state.motion) == "boolean"
            and region.SetMouseClickEnabled and region.SetMouseMotionEnabled then
            region:SetMouseClickEnabled(state.click)
            region:SetMouseMotionEnabled(state.motion)
        elseif state.mouse and region.EnableMouse then
            region:EnableMouse(true)
        end
        dimmed[region] = nil
    end
end
Tab.RestoreOverlays = RestoreOverlays

function Tab.Hide()
    RestoreOverlays()
    activeFrame = nil
    if not (panel and panel:IsShown()) then return end
    MarkSeen()
    panel:Hide()
    SetSideTabMarked(false)
    SetBlizzardTabsMarked(true)
end

local function CreatePanel()
    local parent = _G.LFGParentFrame
    panel = CreateFrame("Frame", "ezSocialChatPanel", parent)
    panel:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, -21)
    panel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -2, 2)
    panel:SetFrameLevel((parent:GetFrameLevel() or 1) + 20)
    panel:EnableMouse(true)
    panel:Hide()

    -- Hintergründe wie im Reiter „Durchsuchen“ (Steinband oben, Gruppenbild im Rahmen darunter)
    local stone = panel:CreateTexture(nil, "BACKGROUND", nil, -5)
    stone:SetAtlas("groupfinder-Stat-StoneBG")
    stone:SetPoint("TOPLEFT")
    stone:SetPoint("BOTTOMRIGHT", panel, "TOPRIGHT", 0, -66)
    local inset = CreateFrame("Frame", nil, panel)
    inset:SetPoint("TOPLEFT", 2, -59)
    inset:SetPoint("BOTTOMRIGHT", -2, 1)
    local art = inset:CreateTexture(nil, "BACKGROUND")
    art:SetAtlas("groupfinder-background")
    art:SetPoint("TOPLEFT", 3, -3)
    art:SetPoint("BOTTOMRIGHT", -3, 3)
    local border = inset:CreateTexture(nil, "BORDER")
    border:SetAtlas("common-insideframe", true)
    border:SetPoint("TOPLEFT", 0, 2)
    border:SetPoint("BOTTOMRIGHT")

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 66, -6)
    title:SetText(L.CHAT_TAB)

    -- Kopfzeile: Suche, Filter „Zeigen“, nach Dungeon gruppieren
    local search = CreateFrame("EditBox", nil, panel, "SearchBoxTemplate")
    search:SetSize(130, 20)
    search:SetPoint("TOPLEFT", 72, -30)
    search:SetAutoFocus(false)
    search:HookScript("OnTextChanged", function(self)
        searchText = self:GetText() or ""
        Tab.Refresh()
    end)
    search:HookScript("OnEnter", Core.TipScript(L.CHAT_SEARCH, L.CHAT_SEARCH_TIP))
    search:HookScript("OnLeave", GameTooltip_Hide)
    panel.search = search

    local kindButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    kindButton:SetSize(96, 22)
    kindButton:SetPoint("LEFT", search, "RIGHT", 8, 0)
    kindButton:SetScript("OnClick", function()
        kindIndex = kindIndex % #KIND_TEXT + 1
        Tab.Refresh()
    end)
    kindButton:SetScript("OnEnter", Core.TipScript(L.CHAT_SHOW, L.CHAT_SHOW_TIP))
    kindButton:SetScript("OnLeave", GameTooltip_Hide)
    panel.kindButton = kindButton

    local groupCheck = Core.CreateCheck(panel, 24)
    groupCheck:SetPoint("LEFT", kindButton, "RIGHT", 8, 0)
    groupCheck:SetScript("OnClick", function(self) ns.SetSetting("chatGroup", self:GetChecked() and true or false) end)
    groupCheck:SetScript("OnEnter", Core.TipScript(L.OPT_chatGroup, L.OPT_chatGroup_TIP))
    groupCheck:SetScript("OnLeave", GameTooltip_Hide)
    local groupLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    groupLabel:SetPoint("LEFT", groupCheck, "RIGHT", 0, 1)
    groupLabel:SetText(L.CHAT_GROUP)
    panel.groupCheck = groupCheck

    -- Liste
    local scroll = CreateFrame("ScrollFrame", nil, panel, "ScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 7, -66)
    scroll:SetPoint("BOTTOMRIGHT", -26, 44)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(self, width) content:SetWidth(width or self:GetWidth()) end)
    content:SetWidth(math.max(scroll:GetWidth() or 0, 380))
    panel.scroll, panel.content, panel.rows = scroll, content, {}

    local empty = panel:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    empty:SetPoint("TOPLEFT", scroll, "TOPLEFT", 20, -40)
    empty:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -20, -40)
    empty:SetJustifyH("CENTER")
    panel.empty = empty

    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontRedSmall")
    hint:SetPoint("BOTTOMLEFT", scroll, "BOTTOMLEFT", 6, 4)
    hint:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", -6, 4)
    hint:SetJustifyH("CENTER")
    panel.hint = hint

    -- Fußzeile: Liste leeren (links), Stand (Mitte), Einstellungen (rechts)
    local clear = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    clear:SetSize(110, 24)
    clear:SetPoint("BOTTOMLEFT", 19, 13)
    clear:SetText(L.CHAT_CLEAR)
    clear:SetScript("OnClick", function() ns.Chat.Clear() end)
    clear:SetScript("OnEnter", Core.TipScript(L.CHAT_CLEAR, L.CHAT_CLEAR_TIP))
    clear:SetScript("OnLeave", GameTooltip_Hide)

    local settings = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    settings:SetSize(110, 24)
    settings:SetPoint("BOTTOMRIGHT", -19, 13)
    -- „Einstellungen …“ mit ezCores Text und Tooltip (Gesamtreview T18-8)
    settings:SetText(Core.L.MENU_OWN_SETTINGS)
    settings:SetScript("OnClick", function() ns.OpenSettings() end)
    settings:SetScript("OnEnter", Core.TipScript(Core.L.MENU_OWN_SETTINGS, Core.L.MENU_OWN_SETTINGS_TIP:format(ns.moduleName or "ezSocial")))
    settings:SetScript("OnLeave", GameTooltip_Hide)

    local status = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    status:SetPoint("LEFT", clear, "RIGHT", 6, 0)
    status:SetPoint("RIGHT", settings, "LEFT", -6, 0)
    status:SetJustifyH("CENTER")
    panel.status = status

    -- Alter der Nachrichten nachführen, solange die Fläche offen ist
    local elapsed = 0
    panel:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + (delta or 0)
        if elapsed >= 15 then
            elapsed = 0
            Tab.Refresh()
        end
    end)
    panel:SetScript("OnShow", function() elapsed = 0 end)
end

function Tab.Show()
    if not ns.Enabled("chatTab") then return false end
    if not panel then
        if not _G.LFGParentFrame then return false end
        CreatePanel()
    end
    activeFrame = Tab.BlizzardFrame()
    DimOverlays()
    panel:Show()
    SetBlizzardTabsMarked(false)
    SetSideTabMarked(true)
    Tab.Refresh()
    return true
end

function Tab.Toggle()
    if panel and panel:IsShown() then Tab.Hide() else Tab.Show() end
end

-- Von außen (Slash, Minikarten-Knopf, ezCore.API): Fenster öffnen und den Reiter zeigen.
function ns.OpenChatTab()
    if not ns.Enabled("chatTab") then
        ns.Print(L.CHAT_OFF:format(Core.SettingsPathText(ns.moduleName or "ezSocial", "OPT_HEADER_CHAT", "OPT_chatTab", L)))
        return false
    end
    if not ns.OpenGroupFinder() then return false end
    Tab.Hook()
    return Tab.Show()
end

---------------------------------------------------------------------------
-- Seitenreiter und Anbindung an Blizzards Fenster
---------------------------------------------------------------------------

local function CreateSideTab(parent)
    local stacked = false
    local ok, tab = pcall(CreateFrame, "Frame", "ezSocialChatSideTab", parent, "LargeSideTabButtonTemplate")
    local icon = ok and tab and ns.Region(tab.Icon)
    if icon then
        tab:EnableMouse(true)
        icon:SetTexture(ICON)
        icon:SetSize(30, 30)
        icon:SetTexCoord(0.03125, 0.96875, 0.03125, 0.96875)
        local selectedTexture = ns.Region(tab.SelectedTexture)
        if selectedTexture then selectedTexture:Hide() end
        tab.tooltipText = L.CHAT_TAB
        -- Blizzards Vorlage zeigt nur den Namen; danach Name und Erklärung samt Befehl (eigener Rahmen)
        tab:HookScript("OnEnter", function(self) Tab.ShowTabTip(self) end)
        tab:HookScript("OnLeave", GameTooltip_Hide)
        local onMouseUp = function(_, button, upInside)
            if button == "LeftButton" and upInside ~= false then Tab.Toggle() end
        end
        if type(tab.SetCustomOnMouseUpHandler) == "function" then
            tab:SetCustomOnMouseUpHandler(onMouseUp)
        else
            tab:SetScript("OnMouseUp", onMouseUp)
        end
    else
        -- Ersatz auf Clients ohne die Vorlage: Seitenreiter aus ezCore; die Lage setzt ezCores Stapel
        -- (Core.SideTabs: lückenlos nach order, auch wenn ein anderes Modul dort einen Reiter hat)
        stacked = true
        tab = Core.CreateSideTab(parent, { key = "ezSocial.chat", order = 20, owner = "ezSocial" })
        tab.Icon:SetTexture(ICON)
        tab:SetScript("OnClick", function(self)
            Core.PlaySound("IG_CHARACTER_INFO_TAB")
            Tab.Toggle()
            self:SetChecked(panel ~= nil and panel:IsShown())
        end)
        tab:SetScript("OnEnter", function(self) Tab.ShowTabTip(self) end)
    end
    tab.count = ns.Region(tab.Count) or tab:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    tab.count:ClearAllPoints()
    tab.count:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -6, 4)
    if stacked then return tab end
    -- Blizzards Vorlage: unter Blizzards drei Reitern (die stehen nicht in ezCores Stapel)
    local anchor = ns.Region(parent.WhoListingTab) or ns.Region(parent.BrowsingTab)
    if anchor then
        tab:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    else
        tab:SetPoint("TOPLEFT", parent, "TOPRIGHT", 0, -60)
    end
    return tab
end

local hooked = false
function Tab.Hook()
    local parent = _G.LFGParentFrame
    if hooked or not parent then return hooked end
    hooked = true
    sideTab = CreateSideTab(parent)
    sideTab:SetShown(ns.Enabled("chatTab"))
    parent:HookScript("OnHide", Tab.Hide)
    for _, key in ipairs(BLIZZARD_TABS) do
        local tab = ns.Region(parent[key])
        if tab and tab.HookScript then
            tab:HookScript("OnMouseUp", function(_, button, upInside)
                if button == "LeftButton" and upInside ~= false then Tab.Hide() end
            end)
        end
    end
    if type(parent.UpdateTabs) == "function" then
        -- Blizzards LFGParentFrame_SetActiveTab ruft UpdateTabs, nachdem es den Inhalt gewechselt hat: wechselt Blizzard
        -- selbst den Reiter, während die Fläche offen ist (Taste, „Aktive Gruppe suchen“), geht die Fläche zu, statt über
        -- dem neuen Inhalt zu bleiben; sonst (Ereignisse, Öffnen) behalten Blizzards Reiter nur keine Markierung.
        hooksecurefunc(parent, "UpdateTabs", function()
            if not (panel and panel:IsShown()) then return end
            local current = Tab.BlizzardFrame()
            -- war beim Öffnen kein Inhalt gezeigt, gilt der erste, den Blizzard danach zeigt (code-reviewer 20.11.2026:
            -- sonst schloss das nächste UpdateTabs aus einem Ereignis die Fläche)
            if activeFrame == nil and current then activeFrame = current end
            if current and current ~= activeFrame then Tab.Hide() else SetBlizzardTabsMarked(false) end
        end)
    end
    if type(LFGVanilla_ShowFrame) == "function" then
        hooksecurefunc("LFGVanilla_ShowFrame", function() Tab.Hide() end)
    end
    UpdateCount()
    return true
end

ns.OnReady(function()
    ns.WhenAddOnLoaded(ns.FINDER_ADDON, Tab.Hook)
end)

local Refresh = ns.Throttle(function() Tab.Refresh() end, 0.2)
ns.Listen("LFG_CHAT_CHANGED", Refresh)

ns.OnSettingChanged(function(key)
    if key == "chatTab" then
        if sideTab then sideTab:SetShown(ns.Enabled("chatTab")) end
        if not ns.Enabled("chatTab") then Tab.Hide() end
    elseif key:find("^chat") then
        Refresh()
    end
end)
