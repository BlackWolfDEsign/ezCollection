local _, ns = ...
local L = ns.L

--[[
    Die Leiste am oberen Bildschirmrand.

    Nur oben: Unten liegen die Aktionsleisten des Spiels; eine zweite Leiste
    dort wäre ihnen im Weg (Titans untere Leiste wird nach oben übernommen).

    Aussehen: Standard ist der Titelstreifen der Client-Fenster (Optionen,
    Kombinierter Rucksack). Alle Maße wachsen mit der Schriftgröße (ns.Px).

    Platz für Blizzards Fenster („Platz oben für die Leiste“, ab Werk aus, „Allem zustimmen“ schaltet es ein):
      Fenster am oberen Rand (Minikarte, Buffs, Spieler-/Zielfenster oben …)
      rücken um die Höhe der Leiste nach unten – taint-sicher und nur in
      Blizzards Standardlage, siehe TopSpace.lua.

    Platz für die Spielwelt („Spielwelt verkleinern“):
      Damit die Leiste nicht über der 3D-Welt liegt, kann ezPanel optional nur
      den WorldFrame (die gerenderte Spielwelt) um die Höhe der Leiste
      verkleinern. Das ist eine reine Ankerung des WorldFrame, keine
      Änderung an UIParent oder geschützten Fenstern. Sie wird nur außerhalb
      des Kampfes gesetzt (im Kampf vorgemerkt über ns.AfterCombat) und
      beim Ausschalten exakt auf die ursprünglichen Anker zurückgesetzt.
      Eine automatisch ausgeblendete Leiste reserviert keinen Platz.
]]

ns.ZONES = { "left", "center", "right" }

-- Hintergründe: „title“ = Titelstreifen der Client-Fenster (Standard),
-- „tooltip“ = Tooltip-Optik des Clients, „flat“ = schlichte dunkle Fläche,
-- „none“ = durchsichtig. Kein ClassicUI-/Classic-Stil.
ns.SKIN_ORDER = { "title", "tooltip", "flat", "none" }

---------------------------------------------------------------------------
-- Schrift und Maße
---------------------------------------------------------------------------

ns.font = CreateFont("ezPanelFont")
ns.font:CopyFontObject(GameFontHighlightSmall)

local function ApplyFont()
    local face, _, flags = GameFontHighlightSmall:GetFont()
    ns.font:SetFont(face, ns.S.fontSize, flags or "")
end

-- Pixelmaß, das mit der Schriftgröße wächst (Bezug: Schriftgröße 10).
function ns.Px(n)
    return math.floor(n * ns.S.fontSize / 10 + 0.5)
end

function ns.BarHeight()
    return ns.Px(20)
end

---------------------------------------------------------------------------
-- Leiste
---------------------------------------------------------------------------

-- Die Leiste, wenn sie eingeschaltet ist (sonst nil).
function ns.ActiveBar()
    return ns.S.topBar and ns.bar or nil
end

local function ApplySkin(bar)
    local skin = ns.S.skin
    if skin == "title" and not bar.title then skin = "tooltip" end   -- Atlas fehlt auf diesem Client
    if bar.title then bar.title:SetShown(skin == "title") end
    bar.bg:SetShown(skin == "tooltip")
    bar.flat:SetShown(skin == "flat")
    if skin == "title" then
        bar.title:SetAlpha(ns.S.alpha)
        ns.PlaceTitleBackground(bar.title, bar, ns.BarHeight())
    elseif skin == "tooltip" then
        local bg = bar.bg
        ns.SetTooltipBackgroundAlpha(bg, ns.S.alpha)
        -- Der Rand liegt außerhalb des Bildschirms; sichtbar bleibt nur die Unterkante.
        local out = (bg.ezEdge or 0) + 2
        bg:ClearAllPoints()
        bg:SetPoint("TOPLEFT", bar, "TOPLEFT", -out, out)
        bg:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", out, 0)
    elseif skin == "flat" then
        bar.flat:SetColorTexture(0, 0, 0, ns.S.alpha)
    end
end

local function PlaceBar(bar)
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
    bar:SetHeight(ns.BarHeight())
    bar:SetScale(ns.S.scale)
    bar:SetFrameStrata(ns.S.strata)
end

local function CreateBar()
    local bar = CreateFrame("Frame", "ezPanelBar", UIParent)
    bar:EnableMouse(true)
    bar:SetFrameLevel(5)
    bar.title = ns.CreateTitleBackground(bar)
    bar.bg = ns.CreateTooltipBackground(bar)
    bar.bg:SetFrameLevel(bar:GetFrameLevel())
    bar.flat = bar:CreateTexture(nil, "BACKGROUND")
    bar.flat:SetAllPoints()
    bar.revealed = false
    bar.idle = 0
    bar:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then ns.OpenBarMenu(self) end
    end)
    ns.bar = bar
    return bar
end

function ns.ApplyBarStyle()
    ApplyFont()
    PlaceBar(ns.bar)
    ApplySkin(ns.bar)
end

---------------------------------------------------------------------------
-- Sichtbarkeit: an/aus, im Kampf, automatisch ausblenden
---------------------------------------------------------------------------

local inCombat = false
local petBattle = false

function ns.UpdateBarVisibility()
    local bar = ns.bar
    local show = ns.S.topBar
    -- Im Bearbeitungsmodus immer sichtbar: So schiebt man keine Blizzard-Fenster unter die Leiste.
    local editing = ezCore.EditMode.IsActive()
    if show and ns.S.hideInCombat and inCombat and not editing then show = false end
    if show and petBattle then show = false end
    if show and ns.S.autoHideTop and not bar.revealed and not ns.IsDragging() and not editing then show = false end
    bar:SetShown(show and true or false)
    if show and ns.FlushHiddenUpdates then ns.FlushHiddenUpdates() end   -- T8-6: was verborgen liegen blieb
    ns.UpdateWatcher()
end

-- Zeigt die Leiste, solange die Maus auf ihr ist oder ein Menü/Ziehen läuft.
local function KeepOpen(bar)
    if ns.IsDragging() then return true end
    if bar:IsMouseOver() then return true end
    local owner = GameTooltip:IsShown() and GameTooltip:GetOwner()
    if owner and owner.ezBar == bar then return true end
    if ns.TourMouseOver and ns.TourMouseOver() then return true end   -- Erklärblase des Rundgangs (Tour.lua)
    local manager = Menu and Menu.GetManager and Menu.GetManager()
    if manager and manager.GetOpenMenu and manager:GetOpenMenu() then return true end
    return false
end

local function CursorAtTop()
    local _, y = GetCursorPosition()
    y = y / UIParent:GetEffectiveScale()
    return y >= UIParent:GetHeight() - 3
end

local watcher = CreateFrame("Frame")
watcher:Hide()
local acc = 0
watcher:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < 0.1 then return end
    local step = acc
    acc = 0
    if inCombat and ns.S.hideInCombat then return end
    local bar = ns.bar
    if bar.revealed then
        if KeepOpen(bar) then
            bar.idle = 0
        else
            bar.idle = bar.idle + step
            if bar.idle >= 0.8 then
                bar.revealed = false
                ns.UpdateBarVisibility()
            end
        end
    elseif CursorAtTop() then
        bar.revealed = true
        bar.idle = 0
        ns.UpdateBarVisibility()
    end
end)

function ns.UpdateWatcher()
    watcher:SetShown((ns.S.topBar and ns.S.autoHideTop) and true or false)
end

ns.On("PLAYER_REGEN_DISABLED", function()
    inCombat = true
    if ns.S and ns.S.hideInCombat and ns.bar then ns.UpdateBarVisibility() end
end)
ns.On("PLAYER_REGEN_ENABLED", function()
    inCombat = false
    if ns.S and ns.S.hideInCombat and ns.bar then ns.UpdateBarVisibility() end
    -- Die vorgemerkte Spielwelt-Ankerung holt ns.AfterCombat nach (ApplyViewport).
end)
ns.On("PET_BATTLE_OPENING_START", function()
    petBattle = true
    if ns.bar then ns.UpdateBarVisibility() end
end)
ns.On("PET_BATTLE_CLOSE", function()
    petBattle = false
    if ns.bar then ns.UpdateBarVisibility() end
end)

---------------------------------------------------------------------------
-- Spielwelt verkleinern (optional, nur außerhalb des Kampfes)
---------------------------------------------------------------------------

local worldPoints
local worldChanged = false

local function SaveWorldPoints()
    if worldPoints then return end
    worldPoints = {}
    for i = 1, WorldFrame:GetNumPoints() do
        local point, relativeTo, relativePoint, x, y = WorldFrame:GetPoint(i)
        worldPoints[i] = { point, relativeTo, relativePoint, x, y }
    end
end

local function RestoreWorldPoints()
    WorldFrame:ClearAllPoints()
    if worldPoints and #worldPoints > 0 then
        -- Einzeln übergeben: relativeTo kann nil sein, unpack würde dann abschneiden.
        for _, p in ipairs(worldPoints) do WorldFrame:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
    else
        WorldFrame:SetAllPoints()
    end
end

-- Höhe, die die Leiste oben belegt, in Einheiten von ref (WorldFrame, UIParent); 0, wenn sie aus oder
-- automatisch ausgeblendet ist. Folgt Schriftgröße und Skalierung. Eine Rechnung für Spielwelt und
-- Blizzards Fenster (TopSpace.lua).
function ns.ReservedHeight(ref)
    if not ns.S.topBar or ns.S.autoHideTop then return 0 end
    local bar = ns.bar
    local pixels = bar:GetHeight() * bar:GetEffectiveScale()
    return pixels / (ref or WorldFrame):GetEffectiveScale()
end

function ns.ApplyViewport()
    if ns.InCombat() then
        ns.viewportPending = true
        ns.AfterCombat(function() ns.ApplyViewport() end, "viewport")
        return
    end
    ns.viewportPending = false
    local top = ns.S.viewport and ns.ReservedHeight(WorldFrame) or 0
    if top == 0 then
        if worldChanged then
            RestoreWorldPoints()
            worldChanged = false
        end
        return
    end
    SaveWorldPoints()
    local ok = pcall(function()
        WorldFrame:ClearAllPoints()
        WorldFrame:SetPoint("TOPLEFT", nil, "TOPLEFT", 0, -top)
        WorldFrame:SetPoint("BOTTOMRIGHT", nil, "BOTTOMRIGHT", 0, 0)
    end)
    if ok then
        worldChanged = true
    else
        RestoreWorldPoints()
        worldChanged = false
    end
end

---------------------------------------------------------------------------
-- Rechtsklick auf eine freie Stelle der Leiste
---------------------------------------------------------------------------

function ns.OpenBarMenu(bar)
    ezCore.Menu.Open(bar, function(root)
        root:CreateTitle("ezPanel")

        local blocks = root:CreateButton(L.MENU_BLOCKS)
        local brokers = nil
        -- „Alle auswählen / Alle abwählen“ je Gruppe (eigene Bausteine, Datenquellen; Design-System 2.11), vor den Haken
        local own, broker = {}, {}
        for _, def in ipairs(ns.blockList) do
            local group = def.broker and broker or own
            group[#group + 1] = def
        end
        local function BlockOn(def) return ns.BlockEnabled(def.id) end
        local function SetBlock(def, on) ns.SetBlockEnabled(def.id, on) end
        ns.MenuAllToggle(blocks, own, BlockOn, SetBlock)
        for _, def in ipairs(ns.blockList) do
            local target = blocks
            if def.broker then
                if not brokers then
                    brokers = blocks:CreateButton(L.MENU_BROKERS)
                    ns.MenuAllToggle(brokers, broker, BlockOn, SetBlock)
                end
                target = brokers
            end
            target:CreateCheckbox(def.name, function() return ns.BlockEnabled(def.id) end, function()
                ns.SetBlockEnabled(def.id, not ns.BlockEnabled(def.id))
                return MenuResponse and MenuResponse.Refresh
            end)
        end

        ns.FillAllBlockMenus(root:CreateButton(L.MENU_BLOCK_OPTIONS))

        root:CreateDivider()
        local function Toggle(key, text)
            root:CreateCheckbox(text, function() return ns.S[key] end, function()
                ns.SetSetting(key, not ns.S[key])
                return MenuResponse and MenuResponse.Refresh
            end)
        end
        Toggle("autoHideTop", L.OPT_autoHideTop)
        Toggle("locked", L.OPT_locked)
        if ns.Profiles then
            local P = ns.Profiles.P
            P.FillMenu(root:CreateButton(L.PROFILE_MENU:format(P.Label())))
        end
        root:CreateDivider()
        ezCore.Menu.Settings(root, ns)   -- „Einstellungen …“ von ezCore (Zahnrad, Tooltip; T18-8)
    end)
end

---------------------------------------------------------------------------
-- Start und Einstellungen
---------------------------------------------------------------------------

ns.OnReady(function()
    CreateBar()
    ns.ApplyBarStyle()
    ns.UpdateBarVisibility()
end)

ns.On("PLAYER_ENTERING_WORLD", function()
    if ns.bar then ns.ApplyViewport() end
end)

-- Platz für Spielwelt und Blizzards Fenster neu berechnen.
local function ApplySpace()
    ns.ApplyViewport()
    if ns.ApplyTopSpace then ns.ApplyTopSpace() end
end

-- Auflösung oder UI-Skalierung geändert: Platz neu berechnen.
ns.On("UI_SCALE_CHANGED", function() if ns.bar then ApplySpace() end end)
ns.On("DISPLAY_SIZE_CHANGED", function() if ns.bar then ApplySpace() end end)

local STYLE_KEYS = { skin = true, alpha = true, fontSize = true, scale = true, strata = true }
local VISIBILITY_KEYS = { topBar = true, autoHideTop = true, hideInCombat = true }

ezCore.EditMode.OnChange(function()
    if ns.bar and ns.S then ns.UpdateBarVisibility() end
end, "ezPanel")

-- Nach einer neuen Schrift erst im nächsten Frame messen: dann stimmen die Textbreiten sicher.
local function Remeasure()
    ns.UpdateAllBlocks()
    ns.RequestLayout()
end

ns.OnSettingChanged(function(key)
    if not ns.bar then return end
    if STYLE_KEYS[key] then
        ns.ApplyBarStyle()
        if key == "fontSize" or key == "scale" then
            Remeasure()
            C_Timer.After(0, Remeasure)
        end
        ns.RequestLayout()
        ApplySpace()
    elseif VISIBILITY_KEYS[key] then
        ns.bar.revealed = false
        ns.UpdateBarVisibility()
        ns.RequestLayout()
        ApplySpace()
    elseif key == "viewport" then
        ns.ApplyViewport()
    elseif key == "reserveTop" then
        ns.ApplyTopSpace()
    elseif key == "spacing" then
        ns.RequestLayout()
    end
end)
