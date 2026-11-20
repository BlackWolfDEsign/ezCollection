local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Ansage-Leiste an Blizzards Raid-Verwaltung (Welle 2b, „Ansagen für Anführer – Rest“, Leitlinie 1: das Original
    erweitern). Vorlage: Blizzard_CompactRaidFrames/Mainline/Blizzard_CompactRaidFrameManager.xml und .lua in Blizzards
    Forever-Quelle (Gethe/wow-ui-source, Zweig forever; die Classic-Fassung hat dieselben Teile). Die Raid-Verwaltung
    (CompactRaidFrameManager) steht am linken Bildschirmrand, eingeklappt zeigt sie nur den Pfeil, aufgeklappt
    zeigt displayFrame alle Bedienelemente; ihre Höhe richtet Blizzard nach dem Inhalt (UpdateOptionsFlowContainer).

    Lage: eine Leiste direkt UNTER der Raid-Verwaltung, so breit wie sie, an ihrer Unterkante verankert – sie
    wandert mit, wenn Blizzard die Höhe ändert, und verdeckt keines ihrer Bedienelemente (die liegen alle innerhalb
    des Rahmens, auch die Knöpfe zum Verlassen der Gruppe unten). Kind von displayFrame: Blizzard blendet sie mit
    der Verwaltung ein und aus, beim Einklappen verschwindet sie, auch im Kampf ohne eigenes Zutun.

    Knöpfe: je Ansage der Gruppe, in der man gerade ist (Announce.DefaultGroup: Dungeon, Raid oder PvP), ein
    sicherer Knopf aus ezCores Dienst (Core.SecureButton, Besitzer ezMacro) mit dem Makrotext des Eintrags
    (ns.EntryBody: die angepasste Fassung, sonst die Vorlage – also genau das Makro aus dem Reiter „Chat“ (Ansagen), mit
    Kanalwahl beim Klick bzw. festem Blizzard-Befehl, Pull-Timer eines laufenden Addons). Aufgebaut und neu belegt
    wird nur außerhalb des Kampfes (im Kampf über ns.AfterCombat nachgeholt). Am Ende ein gewöhnlicher Knopf, der
    den Reiter „Chat“ (Ansagen) öffnet (dort ändern). Nichts wird automatisch gesendet.
    Abschaltbar: Einstellung „Ansage-Leiste an der Raid-Verwaltung“ (OPT_announceBar).
]]
local Bar = {}
ns.AnnounceBar = Bar

local PREFIX = "ezMacroAnnounce"
local SIZE, GAP, PAD, EDGE = 24, 3, 8, 6   -- Knopf, Abstand, Rand seitlich, Rand oben/unten
local MAX = 12                              -- größte Gruppe hat 11 Ansagen
local AFTER_KEY = "announceBar"
local OPEN_ICON = "Interface\\Icons\\INV_Misc_Note_02"   -- Symbol von ezMacro (TOC)
-- Hintergrund wie die Felder in Blizzards Raid-Verwaltung (Mainline: „GM-tab-body“); fehlt der Atlas, Blizzards
-- Rahmen der Chat-Knopfleiste (Vorlage FloatingBorderedFrame).
local BG_ATLAS = "GM-tab-body"

local holder, openButton
local entryOf = {}   -- [Rahmen eines Knopfs] = Eintrag (für den Tooltip)
local shownCount = 0

function Bar.Manager()
    local manager = rawget(_G, "CompactRaidFrameManager")
    if type(manager) == "table" and type(manager.displayFrame) == "table" then return manager, manager.displayFrame end
    return nil
end

-- Ansagen der Gruppe, in der man gerade ist (höchstens MAX).
function Bar.Entries(group)
    group = group or ns.Announce.DefaultGroup()
    local list = {}
    for _, entry in ipairs(ns.MACROS) do
        if entry.category == "announce" and entry.group == group and #list < MAX then list[#list + 1] = entry end
    end
    return list, group
end

function Bar.ButtonName(index) return PREFIX .. index end

-- Spalten je Reihe: so viele Knöpfe, wie in die Breite der Raid-Verwaltung passen.
local function Columns(manager)
    local width = manager.GetWidth and tonumber(manager:GetWidth()) or 0
    return math.max(1, math.floor((width - 2 * PAD + GAP) / (SIZE + GAP)))
end

-- Lage der n-ten Zelle unter der Raid-Verwaltung: x, y relativ zu ihrer Unterkante links.
local function Cell(index, columns)
    local col, row = (index - 1) % columns, math.floor((index - 1) / columns)
    return PAD + col * (SIZE + GAP), -EDGE - row * (SIZE + GAP)
end

local function ShowEntryTip(frame)
    local entry = entryOf[frame]
    if not entry then return end
    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    Core.TipTitle(GameTooltip, ns.EntryName(entry))      -- Rollen statt Farbzahlen (Gesamtreview 18.11.2026, T9-6)
    local say = entry.say and ns.Text(entry.say.text)
    if say then GameTooltip:AddLine(L.ABAR_SAY:format(ns.Announce.Expand(say)), nil, nil, nil, true) end
    Core.TipLine(GameTooltip, ns.Announce.InfoText(), "blue", true)
    Core.TipLine(GameTooltip, L.ABAR_TIP, "hint", true)
    GameTooltip:Show()
end

-- Ungeschütztes am eigenen sicheren Knopf (einmal, außerhalb des Kampfes – ezCores onCreate).
local function Decorate(frame)
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetAllPoints()
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local highlight = frame:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    highlight:SetBlendMode("ADD")
    highlight:SetAllPoints()
    frame:HookScript("OnEnter", ShowEntryTip)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function EnsureHolder(display)
    if holder then return holder end
    holder = CreateFrame("Frame", PREFIX .. "Bar", display)
    if Core.AtlasExists(BG_ATLAS) then
        holder.bg = holder:CreateTexture(nil, "BACKGROUND")
        holder.bg:SetAllPoints()
        holder.bg:SetAtlas(BG_ATLAS)
    else
        local ok, framed = pcall(CreateFrame, "Frame", PREFIX .. "BarBorder", holder, "FloatingBorderedFrame")
        if ok and framed then framed:SetAllPoints() end
    end
    openButton = CreateFrame("Button", PREFIX .. "Open", holder)
    openButton:SetSize(SIZE, SIZE)
    openButton.icon = openButton:CreateTexture(nil, "ARTWORK")
    openButton.icon:SetAllPoints()
    openButton.icon:SetTexture(OPEN_ICON)
    openButton.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local highlight = openButton:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    highlight:SetBlendMode("ADD")
    highlight:SetAllPoints()
    openButton:SetScript("OnClick", function() ns.Browser.ShowCategory("announce") end)
    openButton:SetScript("OnEnter", function(self) Core.ShowTip(self, L.ABAR_OPEN, L.ABAR_OPEN_TIP) end)
    openButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return holder
end

-- Alle Knöpfe weg (Einstellung aus, keine Raid-Verwaltung): Text vom Knopf, ausgeblendet; die Rahmen bleiben.
local function ReleaseFrom(first)
    for index = first, MAX do
        local knopf = Core.SecureButtons and Core.SecureButtons.Get(Bar.ButtonName(index))
        if knopf then knopf:Release() end
    end
end

-- Baut die Leiste neu auf bzw. belegt sie neu. Nur außerhalb des Kampfes; im Kampf danach.
function Bar.Refresh()
    if not ns.db then return false end
    if ns.InCombat() then
        ns.AfterCombat(Bar.Refresh, AFTER_KEY)
        return false, "combat"
    end
    local manager, display = Bar.Manager()
    if not ns.S.announceBar or not manager then     -- Core.SecureButton prüft ezCore über ns.CORE_NEEDS (EC-67)
        ReleaseFrom(1)
        if holder then holder:Hide() end
        shownCount = 0
        return false, not ns.S.announceBar and "off" or "missing"
    end
    local entries = Bar.Entries()
    local columns = Columns(manager)
    for index, entry in ipairs(entries) do
        local x, y = Cell(index, columns)
        local knopf = Core.SecureButton(Bar.ButtonName(index), {
            owner = "ezMacro", parent = display, size = { SIZE, SIZE },
            anchor = { "TOPLEFT", manager, "BOTTOMLEFT", x, y },
            action = { type = "macro", macrotext = (ns.EntryBody(entry)) }, shown = true,
            onCreate = Decorate,
        })
        local frame = knopf and knopf:Frame()
        if frame then
            entryOf[frame] = entry
            if frame.icon then frame.icon:SetTexture(ns.EntryIcon(entry)) end
        end
    end
    ReleaseFrom(#entries + 1)
    shownCount = #entries
    -- Hintergrund und Knopf „Ansagen öffnen“ in der Zelle nach der letzten Ansage
    EnsureHolder(display)
    local cells = #entries + 1
    local rows = math.ceil(cells / columns)
    holder:ClearAllPoints()
    holder:SetPoint("TOPLEFT", manager, "BOTTOMLEFT", 0, 0)
    holder:SetPoint("TOPRIGHT", manager, "BOTTOMRIGHT", 0, 0)
    holder:SetHeight(2 * EDGE + rows * SIZE + (rows - 1) * GAP)
    local x, y = Cell(cells, columns)
    openButton:ClearAllPoints()
    openButton:SetPoint("TOPLEFT", manager, "BOTTOMLEFT", x, y)
    holder:Show()
    return true
end

-- Anzahl der belegten Ansage-Knöpfe (Status, Prüfungen).
function Bar.Count() return shownCount end

local refreshSoon = ns.Throttle(function() ns.Try("AnnounceBar", Bar.Refresh) end, 0.2)

-- Blizzards Raid-Verwaltung: beim Aufklappen neu belegen (angepasste Ansagen, Kanal bei festem Befehl). Nur
-- nachträgliche Haken (Leitlinie 5), nichts an Blizzards Rahmen geschrieben.
local hooked = false
function Bar.Hook()
    if hooked or not Bar.Manager() then return end
    hooked = true
    if type(rawget(_G, "CompactRaidFrameManager_Expand")) == "function" then
        hooksecurefunc("CompactRaidFrameManager_Expand", refreshSoon)
    end
    CompactRaidFrameManager:HookScript("OnShow", refreshSoon)
    refreshSoon()
end

ns.On("GROUP_ROSTER_UPDATE", refreshSoon)
ns.On("PLAYER_ENTERING_WORLD", refreshSoon)
ns.On("ZONE_CHANGED_NEW_AREA", refreshSoon)

ns.OnSettingChanged(function(key)
    if key == "announceBar" or key == "announceMode" then refreshSoon() end
end)

ns.OnReady(function()
    ns.WhenAddOnLoaded("Blizzard_CompactRaidFrames", Bar.Hook)
    Bar.Hook()
end)

ns.AddStatusLine(function()
    if not ns.S.announceBar then return L.ABAR_STATUS_OFF end
    return L.ABAR_STATUS:format(shownCount)
end)
