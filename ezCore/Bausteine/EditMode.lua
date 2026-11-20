local _, ns = ...
local Core = ezCore

--[[
    Blizzards Bearbeitungsmodus (Edit Mode, Esc → Bearbeitungsmodus): Die Module fragen nur, ob er offen
    ist, und hören auf Ein- und Austritt. An Blizzards Systemen (Aktionsleisten, Einheitenfenster, Chat,
    Minikarte, Schlag-Timer …) ändert ezCore nichts – keine Anker, keine Werte, keine Registrierung.

    ezCore.EditMode.IsActive()            true, solange der Bearbeitungsmodus offen ist
    ezCore.EditMode.OnChange(fn, owner)   fn(active) bei Ein- und Austritt (Fehler ins Protokoll von owner)

    So zeigen Module ihre Teile, die an Blizzard-Fenstern hängen, während man diese verschiebt
    (ezCombat), oder bleiben sichtbar, damit nichts darunter geschoben wird (ezPanel).
]]

local EditMode = {}
Core.EditMode = EditMode

local listeners = {}

function EditMode.IsActive()
    local manager = rawget(_G, "EditModeManagerFrame")
    if type(manager) ~= "table" or type(manager.IsEditModeActive) ~= "function" then return false end
    local ok, active = pcall(manager.IsEditModeActive, manager)
    return ok and active == true
end

function EditMode.OnChange(fn, owner)
    listeners[#listeners + 1] = { fn = fn, owner = owner or Core.name }
end

-- Nur bei einem Wechsel melden: Blizzards Ereignis und der Rückweg über OnShow/OnHide (unten) melden denselben
-- Eintritt; Zuhörer hören ihn einmal.
local last = false

local function Notify(active)
    active = active and true or false
    if active == last then return end
    last = active
    for _, entry in ipairs(listeners) do
        local ok, err = pcall(entry.fn, active)
        if not ok then Core.Error(entry.owner, err, "EditMode") end
    end
end
EditMode.Notify = Notify   -- für Tests

-- Blizzard meldet beides über EventRegistry (EditModeManager: EnterEditMode/ExitEditMode, Shared/
-- EditModeManager.lua im Zweig forever).
local registry = rawget(_G, "EventRegistry")
if type(registry) == "table" and type(registry.RegisterCallback) == "function" then
    registry:RegisterCallback("EditMode.Enter", function() Notify(true) end, EditMode)
    registry:RegisterCallback("EditMode.Exit", function() Notify(false) end, EditMode)
end

-- EC-11 (Spieltest 14.11.2026: ezBars-Teile ohne Rahmen im Bearbeitungsmodus): zweiter Weg über das Fenster selbst –
-- nur HookScript, nach Blizzards eigenem OnShow/OnHide (dort setzt EnterEditMode den Zustand). Fragt danach
-- IsActive, damit ein bloßes Ein- und Ausblenden im gesperrten Zustand nichts meldet.
local hookedManager
local function HookManager()
    local manager = rawget(_G, "EditModeManagerFrame")
    if hookedManager or type(manager) ~= "table" or type(manager.HookScript) ~= "function" then return end
    hookedManager = manager
    manager:HookScript("OnShow", function() Notify(EditMode.IsActive()) end)
    manager:HookScript("OnHide", function() Notify(EditMode.IsActive()) end)
end
EditMode.HookManager = HookManager
HookManager()
ns.On("PLAYER_LOGIN", HookManager)
