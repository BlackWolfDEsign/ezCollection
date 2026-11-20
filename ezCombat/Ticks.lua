local _, ns = ...
local L = ns.L

-- Kraftleiste des Spielerfensters (Blizzards Manaleiste, die auch Energie zeigt):
--   • Energie-Tick (Schurke, Druide in Katzengestalt): Energie kommt alle 2 s in einem Schub. Ein Funke wandert
--     über die Leiste und erreicht das Ende, wenn der nächste Schub kommt – wichtig zum Energie-Sparen.
--   • 5-Sekunden-Regel (Mana): Nach dem Ausgeben von Mana ruht die Regeneration 5 s. Der Funke wandert in
--     diesen 5 s einmal langsam über die Leiste; danach zeigt er die 2-s-Ticks der Mana-Regeneration.
-- Den Takt liest ezCombat aus den Kraftänderungen selbst. Regeneriert der Client fließend statt in Schüben,
-- erkennt ezCombat keinen Tick und zeigt nichts.
-- Gesperrte Kraft (UnitPower, UnitPowerMax oder UnitPowerType geheim): Der Takt lässt sich dann nicht lesen – der
-- Funke ruht, ns.NoteSecret("power"), und /ezk status sowie die Tooltips der beiden Schalter sagen es (Vollprüfung
-- W-03: sichtbarer Hinweis statt stiller Lücke). Ob Forever die Kraft der eigenen Einheit sperrt, zeigt der Spieltest.
local Ticks = {}
ns.Ticks = Ticks

local TICK = 2.0
local FIVE_SECONDS = 5.0
local MIN_ENERGY_TICK = 9       -- ab hier ist ein Anstieg ein Schub (20, mit Adrenalinrausch 40)
local SPARK_ATLAS = { "ui-castingbar-pip" }
local SPARK_FILE = "Interface\\CastingBar\\UI-CastingBar-Spark"

local holder, spark
local state = {}
local previewUntil = 0

local function PowerTypes()
    local types = Enum and Enum.PowerType or {}
    return types.Mana or 0, types.Energy or 3
end

local function PowerBar()
    local bar = ezCore.Call(rawget(_G, "PlayerFrame_GetManaBar"))
    if type(bar) == "table" then return bar end
    return rawget(_G, "PlayerFrameManaBar")
end

-- Funke auf Blizzards Leiste: eigener Rahmen als Kind der Leiste, außerhalb des Kampfs angelegt.
local function Holder()
    if holder then return holder end
    if ns.InCombat() then return nil end
    local bar = PowerBar()
    if not bar then return nil end
    holder = CreateFrame("Frame", nil, bar)
    holder:SetAllPoints(bar)
    holder:SetFrameLevel(bar:GetFrameLevel() + 3)
    holder:EnableMouse(false)
    spark = holder:CreateTexture(nil, "OVERLAY")
    local atlas = ns.FirstAtlas(SPARK_ATLAS)
    if atlas then
        spark:SetAtlas(atlas)
    else
        spark:SetTexture(SPARK_FILE)
    end
    spark:SetBlendMode("ADD")
    holder:Hide()
    holder:SetScript("OnUpdate", function() ns.Try("Ticks", Ticks.Draw) end)
    return holder
end

function Ticks.Reset(powerType)
    state = { powerType = powerType }
end

-- Kraftänderung auswerten.
function Ticks.OnPower()
    local rawType, rawPower, rawMax = UnitPowerType("player"), UnitPower("player"), UnitPowerMax("player")
    local powerType, power, maxPower = ns.Num(rawType), ns.Num(rawPower), ns.Num(rawMax)
    if not (powerType and power and maxPower) then
        -- Unbekannt: nichts zeigen. Vermerkt wird nur ein wirklich gesperrter Wert (kein Hinweis auf Verdacht).
        if ns.IsSecret(rawType) or ns.IsSecret(rawPower) or ns.IsSecret(rawMax) then ns.NoteSecret("power") end
        Ticks.Reset(nil)
        Ticks.Refresh()
        return
    end
    if powerType ~= state.powerType then
        Ticks.Reset(powerType)
        state.power, state.max = power, maxPower
        Ticks.Refresh()
        return
    end
    local mana, energy = PowerTypes()
    local delta = power - (state.power or power)
    local now = GetTime()
    if powerType == energy then
        if delta >= MIN_ENERGY_TICK then state.lastTick, state.seen = now, true end
    elseif powerType == mana then
        if delta < 0 then
            state.fiveStart = now
        elseif delta > 0 then
            state.lastTick, state.seen = now, true
        end
    end
    state.power, state.max = power, maxPower
    Ticks.Refresh()
end

-- Was gerade zu zeigen ist: Anteil 0..1 auf der Leiste oder nil.
function Ticks.Position(now)
    now = now or GetTime()
    if now < previewUntil then
        return ((now % TICK) / TICK)
    end
    local mana, energy = PowerTypes()
    local powerType = state.powerType
    if powerType == energy and not ns.Enabled("energyTick") then return nil end
    if powerType == mana and not ns.Enabled("manaRule") then return nil end
    if powerType ~= energy and powerType ~= mana then return nil end
    if powerType == mana and state.fiveStart and now - state.fiveStart < FIVE_SECONDS then
        return (now - state.fiveStart) / FIVE_SECONDS
    end
    if not (state.seen and state.lastTick) then return nil end
    local full = state.max and state.power and state.power >= state.max
    if full and not ns.InCombat() then return nil end
    return ((now - state.lastTick) % TICK) / TICK
end

function Ticks.Draw()
    if not holder then return end
    local position = Ticks.Position()
    if not position then
        holder:Hide()
        return
    end
    local width, height = holder:GetWidth(), holder:GetHeight()
    spark:SetSize(math.max(8, height * 0.6), height * 1.8)
    spark:ClearAllPoints()
    spark:SetPoint("CENTER", holder, "LEFT", width * position, 0)
end

function Ticks.Refresh()
    if not Ticks.Position() then
        if holder then holder:Hide() end
        return
    end
    if Holder() then
        holder:Show()
        Ticks.Draw()
    end
end

-- Nur für den Spieler (ns.OnUnit: Blizzard weckt den Zuhörer nur für ihn, V-042). Eine gesperrte Einheit stellt
-- ezCore trotzdem zu – sie zählt als der Spieler und wird nie verglichen (Leitlinie 6).
ns.OnUnit("UNIT_POWER_FREQUENT", "player", function(_, unit)
    if ns.IsSecret(unit) or unit == "player" then Ticks.OnPower() end
end)
-- Ebenso Kraftart und Höchstwert (T3-2): nur der Spieler, ohne eigenen Vergleich – der Filter liegt bei ezCore.
for _, event in ipairs({ "UNIT_DISPLAYPOWER", "UNIT_MAXPOWER" }) do
    ns.OnUnit(event, "player", function() Ticks.OnPower() end)
end
ns.On("PLAYER_REGEN_DISABLED", function()
    Holder()
    Ticks.Refresh()
end)
ns.On("PLAYER_REGEN_ENABLED", Ticks.Refresh)

ns.OnSettingChanged(function(key)
    if key == "energyTick" or key == "manaRule" then Ticks.Refresh() end
end)

ns.OnReady(function()
    Holder()
    Ticks.OnPower()
end)

-- /ezk status: nur, wenn die Kraft wirklich gesperrt gesehen wurde (hier oder in der Rotation) – sagt, was ruht.
ns.AddStatusLine(function()
    if not ns.secretSeen.power then return nil end
    return L.STATUS_POWER_LOCKED
end)

-- Vorschau: der Funke läuft 4 Sekunden im 2-s-Takt über die Kraftleiste.
ns.AddPreview("ticks", 60, function()
    if not Holder() then return false end
    previewUntil = GetTime() + 4
    Ticks.Refresh()
    C_Timer.After(4.1, Ticks.Refresh)
    return true
end)
