local _, ns = ...
local Core = ezCore

--[[
    Gemeinsame Knöpfe in Blizzards Knopfleiste am Chat (vorher ezChat/ChatBar.lua und
    ezMacro/ChatButton.lua, die beide selbst gemessen haben).

    Aussehen wie VoiceToggleButtonTemplate: 27×26, chatframe-button-up/-down/-highlight, Symbol 15×15,
    gedrückt um (−1, −2) versetzt und zu 75 % sichtbar. Die Knöpfe sind Kinder der Knopfleiste des
    gewählten Chat-Reiters: Sie wandern mit, wenn Blizzard die Leiste auf die andere Seite setzt, und
    blenden mit ihr. Blizzards Knöpfe und Anker bleiben unangetastet (nur HookScript, hooksecurefunc).

    Zwei Gruppen, wie bisher:
      side = "bottom"  von Blizzards Chat-Menü (Sprechblase) nach oben gestapelt, so viele wie zwischen
                       Sprachchat oben und Menü unten passen (ezChat). Reihenfolge = order, der erste oben.
      side = "top"     direkt unter dem untersten sichtbaren Sprachknopf (ezMacro). Weicht aus (blendet
                       sich aus), wenn er einen anderen Knopf überdeckt oder unten herausragt.

    local button = ezCore.ChatBar.Add({
        key, owner, side, order, name,           -- name: globaler Frame-Name (optional)
        atlas, icon, file,                       -- Symbol: Atlas; sonst Datei icon (ganz); sonst file (Rand ab)
        sound,                                   -- Klang beim Klick (optional)
        shown = function() return true end,      -- z. B. Einstellung des Moduls
        onClick = function(button, mouseButton) end,
        tooltip = function(button) end,          -- Zeilen in GameTooltip (Besitzer und Anker setzt ezCore)
        refresh = function(button) end,          -- Zähler/Punkte (button.Dot, button.Count, button.dim)
    })
    ezCore.ChatBar.Layout(), .LayoutSoon(), .Refresh()
]]

local Bar = {}
Core.ChatBar = Bar

local WIDTH, HEIGHT, ICON, GAP = 27, 26, 15, 2
local MENU_HEIGHT = 32   -- Blizzards Chat-Menü-Knopf (ChatFrameMenuButton) unten in der Leiste
-- Blizzards Knöpfe oben in der Leiste (Sprachchat), von oben nach unten.
local TOP_BUTTONS = { "ChatFrameChannelButton", "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton" }

local defs = {}          -- alle angemeldeten Knöpfe
local hookedHosts = {}
local hooked = false

local function PrimaryColumn()
    local chat = ChatFrame1
    local column = type(chat) == "table" and chat.buttonFrame or ChatFrame1ButtonFrame
    return type(column) == "table" and column or nil
end

-- Knopfleiste des gerade gewählten Chat-Reiters: Jedes angedockte Chatfenster hat eine eigene;
-- Blizzard blendet die nicht gewählten Fenster samt Leiste aus.
function Bar.Host()
    local dock = GENERAL_CHAT_DOCK or GeneralDockManager
    local chat = type(dock) == "table" and dock.selected
    local column = type(chat) == "table" and chat.buttonFrame
    if type(column) == "table" then return column end
    return PrimaryColumn()
end

local function SetButtonAtlas(button, setter, atlas)
    if button[setter] then
        button[setter](button, atlas)
        return
    end
    local texture = button:CreateTexture()
    texture:SetAtlas(atlas)
    texture:SetAllPoints()
    local fallback = { SetNormalAtlas = "SetNormalTexture", SetPushedAtlas = "SetPushedTexture", SetHighlightAtlas = "SetHighlightTexture" }
    button[fallback[setter]](button, texture)
end

local function SetIconState(button, pushed)
    local alpha = button.dim and 0.5 or 1
    button.Icon:ClearAllPoints()
    if pushed then
        button.Icon:SetPoint("CENTER", -1, -2)
        button.Icon:SetAlpha(alpha * 0.75)
    else
        button.Icon:SetPoint("CENTER")
        button.Icon:SetAlpha(alpha)
    end
end
Bar.SetIconState = SetIconState

local function ShowTooltip(button)
    local def = button.def
    if not def.tooltip then return end
    local side = ChatFrame1 and ChatFrame1.buttonSide
    GameTooltip:SetOwner(button, side == "right" and "ANCHOR_LEFT" or "ANCHOR_RIGHT")
    local ok, err = pcall(def.tooltip, button)
    if not ok then Core.Error(def.owner, err, "ChatBar") end
    GameTooltip:Show()
end

local function CreateButton(def, parent)
    local button = CreateFrame("Button", def.name, parent)
    button.def = def
    button:SetSize(WIDTH, HEIGHT)
    button:SetFrameStrata("MEDIUM")   -- wie Blizzards Chat-Knöpfe (frameStrata="MEDIUM")
    if Core.AtlasExists("chatframe-button-up") then
        SetButtonAtlas(button, "SetNormalAtlas", "chatframe-button-up")
        SetButtonAtlas(button, "SetPushedAtlas", "chatframe-button-down")
        SetButtonAtlas(button, "SetHighlightAtlas", "chatframe-button-highlight")
    else
        button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    end

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON, ICON)
    if def.atlas and Core.AtlasExists(def.atlas) then
        icon:SetAtlas(def.atlas)
    elseif def.icon and Core.KnownFile(def.icon) then
        icon:SetTexture(def.icon)
    else
        icon:SetTexture(def.file)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)   -- Rand des Symbols abschneiden
    end
    button.Icon = icon
    SetIconState(button, false)

    -- Ungelesen-Punkt wie in der Communities-Liste, Anzahl wie bei Blizzards Zählern
    local dot = button:CreateTexture(nil, "OVERLAY")
    dot:SetAtlas("communities-icon-notification")
    dot:SetSize(11, 11)
    dot:SetPoint("TOPRIGHT", 2, 2)
    dot:Hide()
    button.Dot = dot
    local count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    count:SetPoint("BOTTOMRIGHT", 0, 1)
    button.Count = count

    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnMouseDown", function(self) SetIconState(self, true) end)
    button:SetScript("OnMouseUp", function(self) SetIconState(self, false) end)
    button:SetScript("OnClick", function(self, mouse)
        GameTooltip:Hide()
        local d = self.def
        if d.sound then Core.PlaySound(d.sound) end
        if d.onClick then
            local ok, err = pcall(d.onClick, self, mouse)
            if not ok then Core.Error(d.owner, err, "ChatBar") end
        end
    end)
    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:Hide()
    return button
end

local function Sorted(side)
    local list = {}
    for _, def in ipairs(defs) do
        if def.side == side and def.button then list[#list + 1] = def end
    end
    table.sort(list, function(a, b) return (a.order or 50) < (b.order or 50) end)
    return list
end

local function Wanted(def)
    if not def.shown then return true end
    local ok, result = pcall(def.shown)
    return ok and result and true or false
end

local function HookHost(host)
    if hookedHosts[host] or not host.HookScript then return end
    hookedHosts[host] = true
    host:HookScript("OnSizeChanged", Bar.LayoutSoon)
    host:HookScript("OnShow", Bar.LayoutSoon)
end

-- Der unterste sichtbare Sprachknopf in dieser Leiste (oder keiner).
local function LowestTopButton(host)
    local lowest
    for _, name in ipairs(TOP_BUTTONS) do
        local other = _G[name]
        if type(other) == "table" and other.IsVisible and other:IsVisible() and other:GetParent() == host then
            lowest = other
        end
    end
    return lowest
end

-- Überdeckt der Knopf einen anderen sichtbaren Knopf der Leiste oder ragt er unten heraus?
local function Crowded(button, host)
    local top, bottom = button:GetTop(), button:GetBottom()
    if not (top and bottom) then return false end
    local skip = {}
    for _, name in ipairs(TOP_BUTTONS) do
        if _G[name] then skip[_G[name]] = true end
    end
    for _, child in ipairs({ host:GetChildren() }) do
        if child ~= button and not skip[child] and child:IsShown() then
            local childTop, childBottom = child:GetTop(), child:GetBottom()
            if childTop and childBottom and childTop > bottom + 0.5 and childBottom < top - 0.5 then return true end
        end
    end
    local hostBottom = host:GetBottom()
    return hostBottom ~= nil and bottom < hostBottom - 0.5
end

-- Untere Gruppe: so viele Knöpfe, wie zwischen Sprachchat oben und Chat-Menü unten Platz haben.
-- Blizzards Chat-Menü gibt es nur in der Leiste des ersten Fensters; in den anderen Leisten bleibt
-- sein Platz frei, damit die Knöpfe beim Reiterwechsel nicht springen.
local function LayoutBottom(host)
    local list = Sorted("bottom")
    if #list == 0 then return end
    local menuButton = ChatFrameMenuButton
    local aboveMenu = menuButton and menuButton:IsVisible() and menuButton:GetParent() == host
    local fit = #list
    local top, bottom = host:GetTop(), host:GetBottom()
    if aboveMenu then
        bottom = menuButton:GetTop()
    elseif bottom then
        bottom = bottom + MENU_HEIGHT
    end
    if top and bottom then
        for _, name in ipairs(TOP_BUTTONS) do
            local other = _G[name]
            local otherBottom = other and other:IsVisible() and other:GetBottom()
            if otherBottom then top = math.min(top, otherBottom) end
        end
        fit = math.floor((top - bottom - GAP) / (HEIGHT + GAP))
    end

    local visible = {}
    for i, def in ipairs(list) do
        if Wanted(def) and i <= fit then
            visible[#visible + 1] = def.button
        else
            def.button:Hide()
        end
    end
    local anchor, point, y = host, "BOTTOM", MENU_HEIGHT
    if aboveMenu then anchor, point, y = menuButton, "TOP", 0 end
    for i = #visible, 1, -1 do
        local button = visible[i]
        button:ClearAllPoints()
        button:SetPoint("BOTTOM", anchor, point, 0, y)
        button:Show()
        anchor, point, y = button, "TOP", GAP
    end
end

-- Obere Gruppe: unter dem untersten sichtbaren Sprachknopf; in den Leisten der anderen Reiter fehlt
-- Blizzards Sprachchat-Knopf, sein Platz bleibt frei.
local function LayoutTop(host)
    local anchor, point, y = LowestTopButton(host), "BOTTOM", -GAP
    if not anchor then
        local channel = _G.ChatFrameChannelButton
        local keep = 0
        if host ~= PrimaryColumn() and type(channel) == "table" then
            keep = (channel:GetHeight() or HEIGHT) + GAP
        end
        anchor, point, y = host, "TOP", -keep
    end
    for _, def in ipairs(Sorted("top")) do
        local button = def.button
        if Wanted(def) then
            button:ClearAllPoints()
            button:SetPoint("TOP", anchor, point, 0, y)
            button:Show()
            if Crowded(button, host) then
                button:Hide()
            else
                anchor, point, y = button, "BOTTOM", -GAP
            end
        else
            button:Hide()
        end
    end
end

function Bar.Layout()
    local host = Bar.Host()
    if not host then return end
    for _, def in ipairs(defs) do
        if not def.button then def.button = CreateButton(def, host) end
        if def.button:GetParent() ~= host then
            def.button:SetParent(host)
            def.button:SetFrameStrata("MEDIUM")
        end
    end
    HookHost(host)
    LayoutBottom(host)
    LayoutTop(host)
end

local function SafeLayout()
    local ok, err = pcall(Bar.Layout)
    if not ok then Core.Error(Core.name, err, "ChatBar") end
end

-- Nach dem Umbau der Leiste durch Blizzard oder andere Addons (die oft einen Frame später ordnen).
function Bar.LayoutSoon()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, SafeLayout)
        C_Timer.After(0.5, SafeLayout)
    else
        SafeLayout()
    end
end

-- Zähler und Punkte aller Knöpfe auf den neuesten Stand bringen.
function Bar.Refresh()
    for _, def in ipairs(defs) do
        if def.button and def.refresh then
            local ok, err = pcall(def.refresh, def.button)
            if not ok then Core.Error(def.owner, err, "ChatBar") end
            SetIconState(def.button, false)
        end
    end
end

local function HookBlizzard()
    if hooked then return end
    hooked = true
    -- Reiterwechsel: Knöpfe in die Leiste des neu gewählten Fensters
    if type(FCFDock_SelectWindow) == "function" then
        hooksecurefunc("FCFDock_SelectWindow", Bar.LayoutSoon)
    end
    for _, name in ipairs(TOP_BUTTONS) do
        local other = _G[name]
        if type(other) == "table" and other.HookScript then
            other:HookScript("OnShow", Bar.LayoutSoon)
            other:HookScript("OnHide", Bar.LayoutSoon)
        end
    end
end

-- Knopf anmelden; liefert den Knopf (nil, solange es noch keine Knopfleiste gibt).
function Bar.Add(def)
    def.side = def.side == "top" and "top" or "bottom"
    def.owner = def.owner or Core.name
    for i = #defs, 1, -1 do
        if defs[i].key == def.key then
            def.button = defs[i].button   -- erneut angemeldet: denselben Knopf weiterverwenden
            table.remove(defs, i)
        end
    end
    defs[#defs + 1] = def
    if def.button then def.button.def = def end
    local host = Bar.Host()
    if host and not def.button then def.button = CreateButton(def, host) end
    HookBlizzard()
    if def.button and def.refresh then Core.Try(def.owner, "ChatBar refresh " .. tostring(def.key), def.refresh, def.button) end
    SafeLayout()
    Bar.LayoutSoon()
    return def.button
end

function Bar.Button(key)
    for _, def in ipairs(defs) do
        if def.key == key then return def.button end
    end
end

ns.On("PLAYER_ENTERING_WORLD", function() if #defs > 0 then Bar.LayoutSoon() end end)
