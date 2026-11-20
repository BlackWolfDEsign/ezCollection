local _, ns = ...
local L = ns.L

--[[
    Lautstärke (Titan Volume): Gesamtlautstärke auf der Leiste, Mausrad ändert
    sie, Klick öffnet Schieberegler mit den Vorlagen des Clients (WoW-Forever-Stil).
    Verbesserungen: folgt Änderungen aus den Blizzard-Einstellungen (CVAR_UPDATE),
    Öffnen der Regler schreibt keine Werte, Verlassen des Reglers hebt keine
    Stummschaltung auf. Nutzt nur die Blizzard-CVars, keine eigenen Kopien.
]]

local block = ns.RegisterBlock({
    id = "volume",
    command = "ton",
    name = L.VOL_NAME,
    icon = "atlas:voicechat-icon-speaker",
    fallbackIcon = "Interface\\Icons\\INV_Misc_Bell_01",
    events = { "CVAR_UPDATE" },
    defaults = {
        enabled = true, zone = "right", order = 20,
        showText = true,
        step = 5,
    },
    hints = { L.VOL_HINT_LEFT, L.VOL_HINT_MIDDLE, L.VOL_HINT_WHEEL },
})

local CHANNELS = {
    { cvar = "Sound_MasterVolume", toggle = "Sound_EnableAllSound", label = "VOL_MASTER" },
    { cvar = "Sound_SFXVolume", toggle = "Sound_EnableSFX", label = "VOL_SFX" },
    { cvar = "Sound_MusicVolume", toggle = "Sound_EnableMusic", label = "VOL_MUSIC" },
    { cvar = "Sound_AmbienceVolume", toggle = "Sound_EnableAmbience", label = "VOL_AMBIENCE" },
    { cvar = "Sound_DialogVolume", toggle = "Sound_EnableDialog", label = "VOL_DIALOG" },
}

local function Get(cvar)
    return tonumber(ns.CVar(cvar)) or 0
end

local function Set(cvar, value)
    value = math.max(0, math.min(1, value))
    ns.SetCVar(cvar, ("%.2f"):format(value))
end

local function Enabled(cvar)
    return ns.CVar(cvar) == "1"
end

local function Muted()
    return not Enabled("Sound_EnableAllSound")
end

-- Lautsprecher-Symbole als Atlas des Clients (Namen je nach Client-Stand).
local SPEAKER = { "voicechat-icon-speaker", "chatframe-button-icon-speaker-on" }
local SPEAKER_MUTED = { "voicechat-icon-speaker-mute", "chatframe-button-icon-speaker-off" }

local function Icon(list)
    local atlas = ns.FirstAtlas(list)
    return atlas and ("atlas:" .. atlas) or block.fallbackIcon
end

function block:GetText()
    local master = Get("Sound_MasterVolume")
    local icon = Icon(Muted() and SPEAKER_MUTED or SPEAKER)
    if not self.cfg.showText then return "", icon end
    if Muted() then return ns.Grey(L.VOL_MUTED), icon end
    return ezCore.Percent(math.floor(master * 100 + 0.5)), icon
end

function block:OnTooltip(tooltip)
    if Muted() then ns.TipLine(tooltip, L.VOL_MUTED_TIP, "bad") end
    for _, ch in ipairs(CHANNELS) do
        local value = ezCore.Percent(math.floor(Get(ch.cvar) * 100 + 0.5))
        if ch.toggle ~= "Sound_EnableAllSound" and not Enabled(ch.toggle) then value = ns.Grey(L.OFF) end
        ns.TipDoubleLine(tooltip, L[ch.label], value, "normal", "highlight")
    end
    ns.TipDoubleLine(tooltip, L.VOL_BACKGROUND, Enabled("Sound_EnableSoundWhenGameIsInBG") and L.ON or L.OFF, "normal", "highlight")
end

function block:OnWheel(delta)
    local step = (self.cfg.step or 5) / 100
    Set("Sound_MasterVolume", Get("Sound_MasterVolume") + delta * step)
    ns.QueueUpdate(self)
end

---------------------------------------------------------------------------
-- Blizzards Audio-Seite (Esc → Optionen → Audio)
---------------------------------------------------------------------------

-- Öffnet Blizzards Einstellungen auf der Seite „Audio“ – dort liegt alles, was die Regler hier nicht zeigen
-- (Ausgabegerät, Sprachchat, Tonqualität …). Kennt der Client die Seite nicht unter Settings.AUDIO_CATEGORY_ID,
-- öffnet sich das Einstellungsfenster ohne Seite. Im Kampf öffnet nichts; den Hinweis zeigt ezCore.
local function OpenAudioSettings()
    local settings = rawget(_G, "Settings")
    local ok, reason = false, nil
    if type(settings) == "table" and settings.AUDIO_CATEGORY_ID ~= nil then
        ok, reason = ezCore.OpenPanel("settings", "AUDIO_CATEGORY_ID")
    end
    if not ok and reason ~= "combat" then ok, reason = ezCore.OpenPanel("settings") end
    if not ok and reason ~= "combat" then ns.Print(L.VOL_ALL_MISSING) end
    return ok
end
ns.OpenAudioSettings = OpenAudioSettings

---------------------------------------------------------------------------
-- Schieberegler (Client-Vorlage MinimalSliderWithSteppersTemplate)
---------------------------------------------------------------------------

local popup

local function CreatePopup()
    local f = CreateFrame("Frame", "ezPanelVolumeFrame", UIParent)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    -- Gleicher Hintergrund wie die Tooltips des Clients.
    f.bg = ns.CreateTooltipBackground(f)
    f.bg:SetAllPoints()
    f.bg:SetFrameLevel(f:GetFrameLevel())
    ns.SetTooltipBackgroundAlpha(f.bg, 0.95)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText(L.VOL_NAME)

    f.sliders = {}
    local y = -36
    for _, ch in ipairs(CHANNELS) do
        local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", 14, y - 4)
        label:SetWidth(90)
        label:SetJustifyH("LEFT")
        label:SetText(L[ch.label])
        local ok, slider = pcall(CreateFrame, "Frame", nil, f, "MinimalSliderWithSteppersTemplate")
        if not ok or not slider or not slider.Init then
            f:Hide()
            return nil
        end
        slider:SetPoint("TOPLEFT", 104, y)
        slider:SetWidth(200)
        slider:SetHeight(20)
        local formatters
        if MinimalSliderWithSteppersMixin and CreateMinimalSliderFormatter then
            formatters = {
                [MinimalSliderWithSteppersMixin.Label.Right] = CreateMinimalSliderFormatter(
                    MinimalSliderWithSteppersMixin.Label.Right, function(v) return ezCore.Percent(v) end),
            }
        end
        slider.ch, slider.formatters = ch, formatters
        slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
            if f.updating then return end
            Set(ch.cvar, value / 100)
            ns.QueueUpdate(block)
        end, f)
        f.sliders[#f.sliders + 1] = slider
        y = y - 28
    end

    local function Check(cvar, text, yOffset, tip)
        local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("TOPLEFT", 10, yOffset)
        local label = cb.Text or cb.text or cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:ClearAllPoints()
        label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        label:SetFontObject("GameFontHighlightSmall")
        label:SetText(text)
        cb.cvar = cvar
        cb.tip = tip
        cb:SetScript("OnEnter", ezCore.TipScript(text, tip))
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        cb:SetScript("OnClick", function(self)
            ns.SetCVar(cvar, self:GetChecked() and "1" or "0")
            ns.QueueUpdate(block)
        end)
        return cb
    end
    f.checks = {
        Check("Sound_EnableAllSound", L.VOL_SOUND_ON, y - 4, L.VOL_SOUND_ON_TIP),
        Check("Sound_EnableMusic", L.VOL_MUSIC_ON, y - 28, L.VOL_MUSIC_ON_TIP),
        Check("Sound_EnableSoundWhenGameIsInBG", L.VOL_BACKGROUND, y - 52, L.VOL_BACKGROUND_TIP),
    }
    -- Knopf „Alle Ton-Einstellungen“: Blizzards Audio-Seite (Blizzards Knopf-Vorlage, mit Tooltip).
    local okButton, all = pcall(CreateFrame, "Button", nil, f, "UIPanelButtonTemplate")
    if okButton and all then
        all:SetSize(200, 22)
        all:SetPoint("TOPLEFT", 12, y - 82)
        all:SetText(L.VOL_ALL)
        all:SetScript("OnEnter", ezCore.TipScript(L.VOL_ALL, L.VOL_ALL_TIP))
        all:SetScript("OnLeave", function() GameTooltip:Hide() end)
        all:SetScript("OnClick", function()
            f:Hide()
            OpenAudioSettings()
        end)
        f.allButton = all
    end
    f:SetSize(370, -y + 92 + (f.allButton and 30 or 0))

    -- Schließen bei Klick daneben.
    f:SetScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
    f:SetScript("OnHide", function(self) self:UnregisterEvent("GLOBAL_MOUSE_DOWN") end)
    f:SetScript("OnEvent", function(self)
        if not self:IsMouseOver() and not (block.frame and block.frame:IsMouseOver()) then self:Hide() end
    end)
    f:Hide()
    return f
end

local function RefreshPopup()
    popup.updating = true
    for _, slider in ipairs(popup.sliders) do
        slider:Init(math.floor(Get(slider.ch.cvar) * 100 + 0.5), 0, 100, 20, slider.formatters)
    end
    for _, cb in ipairs(popup.checks) do cb:SetChecked(Enabled(cb.cvar)) end
    popup.updating = false
end

local function TogglePopup(anchor)
    if popup == nil then popup = CreatePopup() or false end
    if not popup then return false end
    if popup:IsShown() then
        popup:Hide()
        return true
    end
    popup:ClearAllPoints()
    popup:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
    RefreshPopup()
    popup:Show()
    GameTooltip:Hide()
    return true
end

-- Die Klicks auch als Menüeinträge (Leitlinie 3); „Ton an“ steht als Häkchen in OnMenu.
block.actions = function(self)
    local list = {}
    if self.frame and self.frame:IsVisible() then
        list[#list + 1] = { text = L.VOL_OPEN_SLIDERS, fn = function(def) TogglePopup(def.frame) end }
    end
    list[#list + 1] = { text = L.VOL_ALL, fn = OpenAudioSettings }
    return list
end

function block:OnClick(button, frame)
    if button == "MiddleButton" then
        ns.SetCVar("Sound_EnableAllSound", Muted() and "1" or "0")
    elseif button == "LeftButton" then
        if not TogglePopup(frame) then
            ns.SetCVar("Sound_EnableAllSound", Muted() and "1" or "0")
        end
    end
end

-- Änderungen von außen (Blizzard-Einstellungen, Tastenkürzel) übernehmen –
-- aber nicht, während die Maus gerade einen Regler bedient.
ns.On("CVAR_UPDATE", function()
    if popup and popup:IsShown() and not popup.updating and not popup:IsMouseOver() then RefreshPopup() end
end)

function block:OnMenu(root)
    local cfg = self.cfg
    ns.MenuCheck(root, L.VOL_SHOW_TEXT, cfg, "showText", self)
    root:CreateCheckbox(L.VOL_SOUND_ON, function() return not Muted() end, function()
        ns.SetCVar("Sound_EnableAllSound", Muted() and "1" or "0")
        ns.QueueUpdate(self)
        return MenuResponse and MenuResponse.Refresh
    end)
    local step = root:CreateButton(L.VOL_STEP)
    for _, n in ipairs({ 1, 2, 5, 10 }) do ns.MenuRadio(step, ezCore.Percent(n), cfg, "step", n, self) end
end
