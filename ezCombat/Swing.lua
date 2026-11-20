local _, ns = ...
local L = ns.L

-- Schlag- und Autoschuss-Timer: WoW Forever bringt eigene Schlagtimer mit (Blizzard_SwingTimer: Haupthand,
-- Schildhand, Distanz; Option „showSwingTimer“, Lage im Bearbeitungsmodus). ezCombat baut keinen zweiten,
-- sondern ergänzt Blizzards Leisten:
--   • Autoschuss-Fenster (Jäger): Die letzten 0,5 s vor dem Schuss rot markiert – wer sich jetzt bewegt,
--     verzögert den Autoschuss.
--   • Vorgemerkter Schlag: Heldenhafter Stoß, Spalten, Zermalmen und Raptorstoß warten auf den nächsten
--     Schlag. Solange einer vorgemerkt ist, leuchtet die Haupthand-Leiste und zeigt sein Symbol.
-- Ein Knopf in den Einstellungen schaltet Blizzards Timer selbst ein und aus.
local Swing = {}
ns.Swing = Swing

local CVAR = "showSwingTimer"
local AUTO_SHOT_WINDOW = 0.5
local FILL_MAIN = "ui-swingtimerbar-filling-mainhand"
local PIP = "ui-swingtimerbar-pip"

local zone, queuedFrame
local rangedSpeed
local previewUntil = 0

local function SwingType(name, fallback)
    local enum = Enum and Enum.PlayerSwingType
    return enum and enum[name] or fallback
end

Swing.CVAR = CVAR

-- Vorschau der Extras: Knopf „Zeigen“ oder Blizzards Bearbeitungsmodus (dort ist der Schlag-Timer zu sehen).
local function Previewing()
    return GetTime() < previewUntil or ezCore.EditMode.IsActive()
end

function Swing.GameTimerOn()
    return ns.CVarOn(CVAR)
end

-- Schaltet Blizzards Schlagtimer. → true nur, wenn das Spiel die Einstellung angenommen hat; „an“/„aus“ meldet
-- ezCombat erst dann (V-108), sonst, dass es nicht geklappt hat. Im Kampf schaltet der Knopf nicht um; die
-- Prüfung macht Core.SwitchCVar (eine Stelle, Gegenprüfung P14 zum Gesamtreview 18.11.2026), den Satz sagt ezCore
-- (Core.CombatNotice mit L.SWING_WHAT, das den Schlagtimer beim Namen nennt; T18-1).
function Swing.SetGameTimer(on)
    local ok, why = ezCore.SwitchCVar(CVAR, on and "1" or "0")
    if not ok then
        if why == "combat" then ezCore.CombatNotice(ns, L.SWING_WHAT) else ns.Print(L.SWING_FAILED) end
        return false
    end
    ns.Print(on and L.SWING_ON or L.SWING_OFF)
    return true
end

local function TimerFrame(name)
    local frame = rawget(_G, name)
    if type(frame) == "table" and type(frame.StatusBar) == "table" then return frame, frame.StatusBar end
    return nil
end

---------------------------------------------------------------------------
-- Autoschuss-Fenster
---------------------------------------------------------------------------

local function RangedSpeed()
    if rangedSpeed and rangedSpeed > 0 then return rangedSpeed end
    local _, _, speed = UnitAttackSpeed("player")
    speed = ns.Num(speed)
    if (not speed or speed <= 0) and UnitRangedDamage then speed = ns.Num((UnitRangedDamage("player"))) end
    return speed
end

function Swing.UpdateZone()
    local timer, statusBar = TimerFrame("SwingTimerRangedFrame")
    local wanted = (ns.Enabled("swingExtras") and ns.playerClass == "HUNTER") or Previewing()
    if not (timer and wanted) then
        if zone then zone:Hide() end
        return
    end
    if not zone then
        zone = CreateFrame("Frame", nil, statusBar)
        zone:SetPoint("TOPRIGHT", statusBar, "TOPRIGHT", 0, 0)
        zone:SetPoint("BOTTOMRIGHT", statusBar, "BOTTOMRIGHT", 0, 0)
        local fill = zone:CreateTexture(nil, "OVERLAY")
        fill:SetAllPoints()
        fill:SetColorTexture(1, 0.15, 0.1, 0.45)
        local edge = zone:CreateTexture(nil, "OVERLAY", nil, 2)
        if ns.AtlasExists(PIP) then
            edge:SetAtlas(PIP, true)
        else
            edge:SetColorTexture(1, 0.3, 0.2, 1)
            edge:SetSize(2, statusBar:GetHeight())
        end
        edge:SetPoint("CENTER", zone, "LEFT", 0, 0)
        statusBar:HookScript("OnSizeChanged", function() Swing.UpdateZone() end)
    end
    local speed = RangedSpeed()
    local width = statusBar:GetWidth()
    if not (speed and speed > 0 and width and width > 0) then
        zone:Hide()
        return
    end
    zone:SetWidth(math.max(2, width * math.min(1, AUTO_SHOT_WINDOW / speed)))
    zone:Show()
end

---------------------------------------------------------------------------
-- Vorgemerkter Schlag
---------------------------------------------------------------------------

local function IsCurrent(name)
    local fn = (C_Spell and C_Spell.IsCurrentSpell) or IsCurrentSpell
    if not fn then return false end
    local ok, current = pcall(fn, name)
    return ok and ns.Bool(current, false)
end

function Swing.QueuedSpell()
    for name, id in pairs(ns.ClassSpellNames("nextSwing")) do
        if IsCurrent(name) then return name, id end
    end
    return nil
end

local function QueuedFrame(timer, statusBar)
    if queuedFrame then return queuedFrame end
    local frame = CreateFrame("Frame", nil, timer)
    frame:SetAllPoints(statusBar)
    frame:SetFrameLevel(statusBar:GetFrameLevel() + 2)
    local glow = frame:CreateTexture(nil, "OVERLAY")
    glow:SetAllPoints()
    if ns.AtlasExists(FILL_MAIN) then
        glow:SetAtlas(FILL_MAIN)
    else
        glow:SetColorTexture(1, 0.82, 0, 1)
    end
    glow:SetBlendMode("ADD")
    glow:SetAlpha(0.55)
    local icon = frame:CreateTexture(nil, "OVERLAY")
    local size = math.max(14, statusBar:GetHeight() + 6)
    icon:SetSize(size, size)
    icon:SetPoint("RIGHT", frame, "LEFT", -4, 0)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    frame.icon = icon
    frame:Hide()
    queuedFrame = frame
    return frame
end

function Swing.UpdateQueued()
    local timer, statusBar = TimerFrame("SwingTimerMainHandFrame")
    if not timer then return end
    local name, id = nil, nil
    if Previewing() then
        name, id = next(ns.ClassSpellNames("nextSwing"))
        if not name then name, id = ns.SpellName(78), 78 end
    elseif ns.Enabled("swingExtras") then
        name, id = Swing.QueuedSpell()
    end
    if not name then
        if queuedFrame then queuedFrame:Hide() end
        return
    end
    local frame = QueuedFrame(timer, statusBar)
    frame.icon:SetTexture(ezCore.Spells.Icon(id) or 132282)
    frame:Show()
end

---------------------------------------------------------------------------

local updateQueuedSoon = ns.Throttle(Swing.UpdateQueued, 0.02)

-- swingType kann gesperrt sein: erst offen lesen, dann vergleichen (T3-1, Leitlinie 6).
ns.On("PLAYER_SWING", function(_, duration, swingType)
    if ns.Plain(swingType) == SwingType("Ranged", 2) then
        rangedSpeed = ns.Num(duration)
        Swing.UpdateZone()
    end
    updateQueuedSoon()
end)
-- Einheiten-Ereignisse nur für den Spieler (ns.OnUnit, T8-1): der Filter liegt bei ezCore, eine gesperrte Einheit
-- zählt dort als der Spieler und wird hier nie verglichen (T3-1).
for _, event in ipairs({ "UNIT_ATTACK_SPEED", "UNIT_RANGEDDAMAGE", "UNIT_INVENTORY_CHANGED" }) do
    ns.OnUnit(event, "player", function()
        rangedSpeed = nil
        Swing.UpdateZone()
    end)
end
for _, event in ipairs({ "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }) do
    ns.OnUnit(event, "player", updateQueuedSoon)
end
-- Ohne Einheit. CURRENT_SPELL_CAST_CHANGED nennt als ersten Wert einen Wahrheitswert (cancelledCast) – vorher
-- ließ der Vergleich „nil oder player“ das Ereignis darum nie durch.
for _, event in ipairs({ "CURRENT_SPELL_CAST_CHANGED", "ACTIONBAR_UPDATE_STATE", "PLAYER_REGEN_ENABLED" }) do
    ns.On(event, updateQueuedSoon)
end

ns.OnSettingChanged(function(key)
    if key == "swingExtras" then
        Swing.UpdateZone()
        Swing.UpdateQueued()
    end
end)

ns.OnReady(function()
    ns.WhenAddOnLoaded("Blizzard_SwingTimer", function()
        Swing.UpdateZone()
        Swing.UpdateQueued()
    end)
end)

-- „Schlagtimer aus“ mit dem Weg zum Kästchen (Core.SettingsPathText, T18-18)
function Swing.OffText()
    return L.STATUS_SWING_OFF:format(ns.PathText("OPT_HEADER_SWING", "OPT_SWING_GAME"))
end

ns.AddStatusLine(function()
    if rawget(_G, "SwingTimerMainHandFrame") and not Swing.GameTimerOn() then return Swing.OffText() end
end)

-- Vorschau: Autoschuss-Fenster und vorgemerkter Schlag für 3 Sekunden (nur sichtbar, wenn Blizzards Timer an ist).
ns.AddPreview("swing", 50, function()
    if not rawget(_G, "SwingTimerMainHandFrame") then return false end
    if not Swing.GameTimerOn() then
        ns.Print(Swing.OffText())
        return false
    end
    previewUntil = GetTime() + 3
    Swing.UpdateZone()
    Swing.UpdateQueued()
    C_Timer.After(3.1, function()
        Swing.UpdateZone()
        Swing.UpdateQueued()
    end)
    return true
end)

-- Bearbeitungsmodus: Autoschuss-Fenster und vorgemerkter Schlag am Schlag-Timer, solange er offen ist.
ns.Listen("EDIT_MODE", function()
    Swing.UpdateZone()
    Swing.UpdateQueued()
end)
