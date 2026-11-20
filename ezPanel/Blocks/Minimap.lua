local _, ns = ...
local L = ns.L

--[[
    Minikarten-Knöpfe: sammelt die Knöpfe
    anderer Addons von der Minikarte in einen Baustein der Leiste. Ein Klick öffnet
    darunter eine Leiste mit denselben Knöpfen im Aussehen der Minikarten-Knöpfe
    (Blizzards Rahmen und Hintergrund der Minikarte, Hintergrund wie die Tooltips).

    Erfasst werden die Knöpfe aus LibDBIcon (RareScanner, Questie, Atlas, DBM, Details …).
    ezPanel bringt LibDBIcon nicht mit, sondern nutzt es, wenn ein anderes Addon es lädt.
    - Die Minikarte und Blizzards eigene Knöpfe daran bleiben unberührt (Bearbeitungsmodus).
    - Die Originalknöpfe werden nur ausgeblendet, nicht umgehängt; ihre Einstellungen im
      jeweiligen Addon (Position, „verstecken“) bleiben, wie sie sind.
    - Die Knöpfe in der Leiste rufen dieselben Funktionen des Addons auf wie das Original
      (LibDataBroker: OnClick, OnTooltipShow bzw. OnEnter/OnLeave).
    - Baustein aus oder ein Addon im Menü abgewählt: der Knopf kehrt auf die Minikarte zurück.
    Einzelne Addons lassen sich zusätzlich direkt als Baustein auf die Leiste legen
    (Rechtsklick auf die Leiste → Bausteine → Andere Addons, Blocks/Broker.lua).
    Sammelt schon ein anderes Addon die Knöpfe (MinimapButtonButton, HidingBar, Leatrix Plus
    „Minimap button bag“), hält sich ezPanel heraus und sagt es im Tooltip (docs/fremd-addons.md).
]]

local SIZE, GAP, PAD = 31, 2, 6
local COLUMNS = { 4, 6, 8, 10, 12 }

local block = ns.RegisterBlock({
    id = "minimap",
    command = "minikarte",
    name = L.MINIMAP_NAME,
    label = L.MINIMAP_LABEL,
    icon = "Interface\\Icons\\INV_Misc_Map_01",
    fallbackIcon = ezCore.ICON_FALLBACK,
    defaults = {
        enabled = false, zone = "right", order = 45, label = false,
        count = true,          -- Zahl der gesammelten Knöpfe auf der Leiste
        columns = 6,           -- Knöpfe je Reihe in der aufgeklappten Leiste
        skip = {},             -- Addons, deren Knopf auf der Minikarte bleibt
    },
    hints = function() return { L.MINIMAP_HINT_LEFT } end,
})

local hooked = {}       -- Originalknopf → Name (OnShow-Hook gesetzt)
local registered = false
local flyout
local Apply

---------------------------------------------------------------------------
-- LibDBIcon (optional, von anderen Addons geladen)
---------------------------------------------------------------------------

local function Lib()
    local lib = LibStub and LibStub.GetLibrary and LibStub:GetLibrary("LibDBIcon-1.0", true)
    if type(lib) ~= "table" or type(lib.GetButtonList) ~= "function" then return nil end
    -- Später angelegte Knöpfe (Addons, die erst nach dem Einloggen laden) auch einsammeln.
    if not registered and type(lib.RegisterCallback) == "function" then
        registered = true
        lib.RegisterCallback(block, "LibDBIcon_IconCreated", function() if Apply then Apply() end end)
    end
    return lib
end

-- Alle Addon-Knöpfe mit LDB-Objekt: { name, button, obj }, nach Name sortiert.
local function Buttons()
    local list = {}
    local lib = Lib()
    if not lib then return list end
    local ok, names = pcall(lib.GetButtonList, lib)
    for _, name in ipairs(ok and type(names) == "table" and names or {}) do
        local button = lib:GetMinimapButton(name)
        if type(name) == "string" and button and type(button.dataObject) == "table" then
            list[#list + 1] = { name = name, button = button, obj = button.dataObject }
        end
    end
    table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
    return list
end

-- Sammelt schon ein anderes Addon die Minikarten-Knöpfe? Dann dessen Name.
-- Erkennung in ezCore (Funktion „minimapBag“: Leatrix Plus, MinimapButtonButton, HidingBar).
local function OtherCollector()
    return (ns.OtherFor("minimapBag"))
end

local function Collected(name)
    local cfg = block.cfg
    return cfg ~= nil and cfg.enabled == true and not cfg.skip[name] and not OtherCollector()
end

local function CollectedButtons()
    local list = {}
    for _, e in ipairs(Buttons()) do
        if Collected(e.name) then list[#list + 1] = e end
    end
    return list
end

---------------------------------------------------------------------------
-- Originalknöpfe aus- und wieder einblenden
---------------------------------------------------------------------------

local function Collect(name, button)
    if not hooked[button] then
        hooked[button] = name
        -- LibDBIcon blendet seine Knöpfe beim Einloggen und bei Refresh wieder ein.
        button:HookScript("OnShow", function(self)
            if Collected(hooked[self]) then self:Hide() end
        end)
    end
    button:Hide()
end

local function Release(name, button)
    -- Wie LibDBIcon selbst: sichtbar, außer das Addon hat seinen Knopf versteckt.
    if type(button.db) == "table" and button.db.hide then return end
    if button:IsShown() then return end
    local lib = Lib()
    if lib and type(lib.Show) == "function" then
        pcall(lib.Show, lib, name)
    else
        button:Show()
    end
end

---------------------------------------------------------------------------
-- Aufgeklappte Leiste
---------------------------------------------------------------------------

local function Anchor(frame)
    local x, y = frame:GetCenter()
    if not x then return "TOP", frame, "BOTTOM" end
    local h = (x > UIParent:GetWidth() * 2 / 3) and "RIGHT" or (x < UIParent:GetWidth() / 3) and "LEFT" or ""
    local v = (y > UIParent:GetHeight() / 2) and "TOP" or "BOTTOM"
    return v .. h, frame, (v == "TOP" and "BOTTOM" or "TOP") .. h
end

local function ProxyEnter(self)
    local obj = self.entry and self.entry.obj
    if not obj then return end
    if type(obj.OnTooltipShow) == "function" then
        GameTooltip:SetOwner(self, "ANCHOR_NONE")
        GameTooltip:ClearAllPoints()
        GameTooltip:SetPoint(Anchor(self))
        local ok, err = pcall(obj.OnTooltipShow, GameTooltip)
        if not ok then geterrorhandler()(err) end
        GameTooltip:Show()
    elseif type(obj.OnEnter) == "function" then
        local ok, err = pcall(obj.OnEnter, self)
        if not ok then geterrorhandler()(err) end
    else
        -- Ohne eigenen Tooltip des Addons: Name und was der Klick tut.
        local name = type(obj.label) == "string" and obj.label ~= "" and obj.label or self.entry.name
        ezCore.ShowTip(self, name, L.MINIMAP_PROXY_TIP)
    end
end

local function ProxyLeave(self)
    if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    local obj = self.entry and self.entry.obj
    if obj and type(obj.OnLeave) == "function" then pcall(obj.OnLeave, self) end
end

local function ProxyClick(self, button)
    local obj = self.entry and self.entry.obj
    if obj and type(obj.OnClick) == "function" then
        local ok, err = pcall(obj.OnClick, self, button)
        if not ok then geterrorhandler()(err) end
    end
end

-- Ein Knopf im Aussehen der Minikarten-Knöpfe (Blizzards Texturen, Maße wie LibDBIcon). Die Größen 18 (Symbol) und 50
-- (Rand) folgen den Addon-Knöpfen an der Minikarte, die dieser Knopf vertritt – nicht Core.Style (Design-System 2.3:
-- eine Größe, die einem vorhandenen Teil folgt, bleibt mit Begründung).
local function CreateProxy(index)
    local b = CreateFrame("Button", nil, flyout)
    b:SetSize(SIZE, SIZE)
    b:RegisterForClicks("AnyUp")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    b.background = b:CreateTexture(nil, "BACKGROUND")
    b.background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    b.background:SetSize(24, 24)
    b.background:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(18, 18)
    b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.border = b:CreateTexture(nil, "OVERLAY")
    b.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b.border:SetSize(50, 50)
    b.border:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    b:SetScript("OnEnter", ProxyEnter)
    b:SetScript("OnLeave", ProxyLeave)
    b:SetScript("OnClick", ProxyClick)
    flyout.buttons[index] = b
    return b
end

local function UpdateProxy(b, e)
    b.entry = e
    local obj = e.obj
    local icon = obj.icon
    if icon == nil and e.button.icon and e.button.icon.GetTexture then icon = e.button.icon:GetTexture() end
    b.icon:SetTexture(icon)
    local c = obj.iconCoords
    if type(c) == "table" and #c >= 4 then
        local dx, dy = (c[2] - c[1]) * 0.05, (c[4] - c[3]) * 0.05
        b.icon:SetTexCoord(c[1] + dx, c[2] - dx, c[3] + dy, c[4] - dy)
    else
        b.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    end
    b.icon:SetVertexColor(obj.iconR or 1, obj.iconG or 1, obj.iconB or 1)
end

local function Layout()
    local list = CollectedButtons()
    local cols = math.max(1, math.min(block.cfg.columns or 6, #list))
    for i, e in ipairs(list) do
        local b = flyout.buttons[i] or CreateProxy(i)
        UpdateProxy(b, e)
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", flyout, "TOPLEFT", PAD + col * (SIZE + GAP), -PAD - row * (SIZE + GAP))
        b:Show()
    end
    for i = #list + 1, #flyout.buttons do
        flyout.buttons[i]:Hide()
        flyout.buttons[i].entry = nil
    end
    if #list == 0 then
        local other = OtherCollector()
        flyout.empty:SetText(other and L.MINIMAP_OTHER:format(other) or L.MINIMAP_NONE)
        flyout.empty:Show()
        flyout:SetSize(math.ceil(flyout.empty:GetStringWidth()) + 4 * PAD, SIZE + 2 * PAD)
        return
    end
    flyout.empty:Hide()
    local rows = math.ceil(#list / cols)
    flyout:SetSize(2 * PAD + cols * SIZE + (cols - 1) * GAP, 2 * PAD + rows * SIZE + (rows - 1) * GAP)
end

local function FlyoutUpdate(self, elapsed)
    local owner = block.frame
    if not (owner and owner:IsVisible()) then return self:Hide() end
    if self:IsMouseOver() or owner:IsMouseOver() then
        self.away = 0
        return
    end
    self.away = (self.away or 0) + elapsed
    if self.away > 1.5 then self:Hide() end
end

local function CreateFlyout()
    flyout = CreateFrame("Frame", "ezPanelMinimapButtons", UIParent)
    flyout:SetFrameStrata("DIALOG")
    flyout:SetClampedToScreen(true)
    flyout:EnableMouse(true)
    flyout.bg = ns.CreateTooltipBackground(flyout)
    flyout.bg:SetAllPoints()
    ns.SetTooltipBackgroundAlpha(flyout.bg, 0.9)
    flyout.empty = flyout:CreateFontString(nil, "OVERLAY")
    flyout.empty:SetFontObject(ns.font)
    flyout.empty:SetPoint("CENTER")
    flyout.empty:SetText(L.MINIMAP_NONE)
    flyout.buttons = {}
    flyout:Hide()
    flyout:SetScript("OnUpdate", FlyoutUpdate)
end

local function ToggleFlyout(owner)
    if not flyout then CreateFlyout() end
    if flyout:IsShown() then return flyout:Hide() end
    GameTooltip:Hide()
    Layout()
    flyout:ClearAllPoints()
    local h = (owner.zone == "left" and "LEFT") or (owner.zone == "right" and "RIGHT") or ""
    flyout:SetPoint("TOP" .. h, owner, "BOTTOM" .. h, 0, -2)
    flyout.away = 0
    flyout:Show()
end

---------------------------------------------------------------------------
-- Anwenden
---------------------------------------------------------------------------

Apply = function()
    -- Ein anderes Addon sammelt: dessen Knöpfe nicht anfassen (auch nicht „zurückgeben“).
    if OtherCollector() then
        ns.QueueUpdate(block)
        return
    end
    for _, e in ipairs(Buttons()) do
        if Collected(e.name) then
            Collect(e.name, e.button)
        elseif hooked[e.button] then
            Release(e.name, e.button)
        end
    end
    ns.QueueUpdate(block)
    if flyout and flyout:IsShown() then Layout() end
end

function block:OnEnable()
    Apply()
end

function block:OnDisable()
    if flyout then flyout:Hide() end
    Apply()   -- cfg.enabled ist schon aus: alle Knöpfe zurück auf die Minikarte
end

-- Profilwechsel: die Auswahl der eingesammelten Knöpfe (cfg.skip) kann anders sein.
function block:OnConfigChanged()
    Apply()
end

---------------------------------------------------------------------------
-- Anzeige
---------------------------------------------------------------------------

function block:GetText()
    if not self.cfg.count then return "" end
    return tostring(#CollectedButtons())
end

function block:OnTooltip(tooltip)
    local other = OtherCollector()
    if other then ns.TipLine(tooltip, L.MINIMAP_OTHER:format(other), "orange", true) end
    local all = Buttons()
    if #all == 0 then
        ns.TipLine(tooltip, L.MINIMAP_NONE, "hint", true)
        return
    end
    for _, e in ipairs(all) do
        local label = type(e.obj.label) == "string" and e.obj.label or e.name
        if Collected(e.name) then
            ns.TipLine(tooltip, label, "highlight")
        else
            ns.TipDoubleLine(tooltip, label, L.MINIMAP_LEFT_ON_MAP, "hint", "hint")
        end
    end
end

function block:OnClick(button, frame)
    if button == "LeftButton" then ToggleFlyout(frame) end
end

function block:OnMenu(root)
    local cfg = self.cfg
    local pick = root:CreateButton(L.MINIMAP_COLLECT)
    local all = Buttons()
    if #all == 0 then pick:CreateTitle(L.MINIMAP_NONE) end
    -- „Alle auswählen / Alle abwählen“ über den Knöpfen (Design-System 2.11; gemerkt in cfg.skip), einmal Apply
    ns.MenuAllToggle(pick, all, function(e) return not cfg.skip[e.name] end,
        function(e, on) cfg.skip[e.name] = (not on) or nil end, function() Apply() end)
    for _, e in ipairs(all) do
        local name = e.name
        pick:CreateCheckbox(type(e.obj.label) == "string" and e.obj.label or name,
            function() return not cfg.skip[name] end,
            function()
                cfg.skip[name] = not cfg.skip[name] or nil
                Apply()
                return MenuResponse and MenuResponse.Refresh
            end)
    end
    local cols = root:CreateButton(L.MINIMAP_COLUMNS)
    for _, n in ipairs(COLUMNS) do
        ns.MenuRadio(cols, tostring(n), cfg, "columns", n, self, function()
            if flyout and flyout:IsShown() then Layout() end
        end)
    end
    ns.MenuCheck(root, L.MINIMAP_SHOW_COUNT, cfg, "count", self)
    root:CreateButton(L.MINIMAP_OPEN, function() if self.frame then ToggleFlyout(self.frame) end end)
end

-- Erst nach allen Addons (deren LibDBIcon-Knöpfe entstehen beim Laden) noch einmal einsammeln.
ns.OnReady(function()
    C_Timer.After(2, function()
        if block.cfg and block.cfg.enabled then Apply() end
    end)
end)
