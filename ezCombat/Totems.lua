local _, ns = ...
local L = ns.L
local Glow = ns.Glow

-- Totem-Timer (Schamane): Blizzards Totemleiste am Spielerfenster (TotemFrame) zeigt Symbol und Restzeit.
-- Kurz bevor ein Totem verschwindet, leuchten sein Knopf dort und der Totem-Zauber auf den Aktionsleisten –
-- Zeit, es neu zu setzen.
local Totems = {}
ns.Totems = Totems

local TICK = 0.25
local glowing = setmetatable({}, { __mode = "k" })

local function MaxSlots()
    return tonumber(rawget(_G, "MAX_TOTEMS")) or 4
end

-- Blizzards Totemknöpfe nach Platz.
function Totems.Buttons()
    local result = {}
    local frame = rawget(_G, "TotemFrame")
    if type(frame) ~= "table" or type(frame.GetChildren) ~= "function" then return result end
    for _, child in ipairs({ frame:GetChildren() }) do
        local slot = child.slot
        if type(slot) == "number" and child:IsShown() then result[slot] = child end
    end
    return result
end

-- „Totem des glühenden Magmas III“ → „Totem des glühenden Magmas“ (Rang am Ende weg).
function Totems.BaseName(name)
    return (name:gsub("%s+[IVX]+$", ""))
end

-- Totems kurz vor dem Ende: { [Platz] = Name }
function Totems.Expiring(now)
    local list = {}
    if not GetTotemInfo then return list end
    for slot = 1, MaxSlots() do
        local have, name, start, duration = GetTotemInfo(slot)
        have, name, start, duration = ns.Bool(have, false), ns.Plain(name), ns.Num(start), ns.Num(duration)
        if have and name and start and duration and duration > 0 then
            local left = start + duration - now
            if left > 0 and left <= ns.S.totemWarn then list[slot] = name end
        elseif have and not (start and duration) then
            ns.NoteSecret("totems")
        end
    end
    return list
end

-- Gesamtreview 18.11.2026 (T8-4): Der Takt läuft nur, solange ein Totem steht und der Schalter an ist
-- (Totems.UpdateTicker: PLAYER_TOTEM_UPDATE, Schalter, Anmelden); im Takt kehrt Update früh zurück, wenn nichts
-- ausläuft und nichts leuchtet, und die Hilfstabellen werden wiederverwendet. Vorher lief er für jeden Schamanen
-- viermal je Sekunde und legte je Takt mehrere Tabellen an.
local want, names = {}, {}
local spellsSet = false

function Totems.Update()
    local expiring
    if ns.Enabled("totems") and ns.playerClass == "SHAMAN" then expiring = Totems.Expiring(GetTime()) end
    if not (expiring and next(expiring)) and not next(glowing) and not spellsSet then return end
    expiring = expiring or {}
    wipe(want)
    for slot, button in pairs(Totems.Buttons()) do
        if expiring[slot] then want[button] = true end
    end
    for button in pairs(glowing) do
        if not want[button] then
            Glow.Hide(button)
            glowing[button] = nil
        end
    end
    for button in pairs(want) do
        if Glow.Show(button, false, "totem") then glowing[button] = true end
    end
    wipe(names)
    for _, name in pairs(expiring) do
        names[name] = true
        names[Totems.BaseName(name)] = true
    end
    spellsSet = next(names) ~= nil
    Glow.SetSpells("totem", names)
end

-- Steht gerade irgendein Totem? (gesperrte Antwort zählt als „steht“, damit die Warnung nicht ausfällt)
function Totems.AnyActive()
    if not GetTotemInfo then return false end
    for slot = 1, MaxSlots() do
        local have = GetTotemInfo(slot)
        if ns.IsSecret(have) or have == true then return true end
    end
    return false
end

local ticker
function Totems.UpdateTicker()
    local run = ns.playerClass == "SHAMAN" and ns.Enabled("totems") and Totems.AnyActive()
    if run and not ticker and C_Timer.NewTicker then
        ticker = C_Timer.NewTicker(TICK, function() ns.Try("Totems", Totems.Update) end)
    elseif not run and ticker then
        ticker:Cancel()
        ticker = nil
    end
    return ticker ~= nil
end

local function Refresh()
    Totems.UpdateTicker()
    Totems.Update()
end

ns.On("PLAYER_TOTEM_UPDATE", function() ns.Try("Totems", Refresh) end)
ns.OnReady(function() ns.Try("Totems", Refresh) end)
ns.OnSettingChanged(function(key)
    if key == "totems" then ns.Try("Totems", Refresh) end
end)

-- Vorschau: Totemknöpfe (gesetzte Totems) oder die Totem-Zauber auf den Leisten leuchten 3 Sekunden.
ns.AddPreview("totems", 70, function()
    if ns.playerClass ~= "SHAMAN" then return false end
    local shown = 0
    for _, button in pairs(Totems.Buttons()) do
        if Glow.Show(button, false, "totem") then
            shown = shown + 1
            C_Timer.After(3, function()
                if not glowing[button] then Glow.Hide(button) end
            end)
        end
    end
    for _, button in ipairs(Glow.Buttons()) do
        local name = button:IsVisible() and Glow.SpellOf(button)
        if name and name:find(L.TOTEM_WORD, 1, true) then
            Glow.Flash(button, 3)
            shown = shown + 1
        end
    end
    return shown > 0
end)
