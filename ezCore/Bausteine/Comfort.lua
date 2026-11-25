local _, ns = ...
local Core = ezCore
local L = Core.L

--[[
    Abschnitt „Komfort“ auf der Seite „ezCollection“ (Punkt 9), zwischen „Module“ und „Erweitert“.

    Beta-Hinweise ausblenden: Blizzards schwebender Fehlerbericht-Knopf
    (PTR_IssueReporter) und die Umfragen nach einer Questbelohnung. Nur HookScript/hooksecurefunc und Hide(),
    nichts wird in Blizzards Tabellen geschrieben. Schalter in ezCoreDB.comfort.betaHints, Standard aus.
    Blendet Forever Tweaks sie schon aus, hält sich ezCore zurück (Core.WhoHandles("betaHints")).

    Komfort-Schalter für Blizzards eigene CVars: automatisch absteigen bzw. aufstehen,
    Gestalt verlassen, Gegenstände immer vergleichen, Bildschirmfoto-Qualität; dazu die Konsolen-Schalter aus dem
    ezMacro-Abgleich (ST-01, MACRO-32): Bedrohung in Prozent am Zielfenster, Klassenfarben an Namensplaketten,
    direkte Mauseingabe, Dichte und Sichtweite der Bodenvegetation, Schärfen, Controller. Die CVar ist die einzige Quelle;
    ezCoreDB speichert den Wert nicht. Gezeigt wird ein Schalter nur, wenn der Client die CVar kennt und
    Blizzards Optionen sie nicht schon anbieten (Settings.GetSetting(cvar)).

    Kamera weiter herauszoomen (Entscheidung des Nutzers 13.11.2026, Vollprüfung V-038): Blizzards Regler
    „Maximale Kameradistanz“ (Steuerung → Kamera, CVar cameraDistanceMaxZoomFactor) geht auf Forever nur von
    1,0 bis 2,0 (Blizzard_SettingsDefinitions_Frame/Camelot/ControlsOverrides.lua, Zweig forever, 1.60.1). Der
    Schalter setzt den Höchstwert der Retail-Engine, 2,6. Darum zählt
    hier nicht, dass Blizzard die CVar selbst anbietet. Schalter in ezCoreDB.comfort.cameraZoom, Standard aus;
    beim Einschalten merkt ezCore den Wert davor (comfort.cameraZoomOld) und stellt ihn beim Ausschalten wieder
    her. Hat jemand den Wert inzwischen selbst geändert (Blizzards Regler), bleibt er. Im Kampf wird nach dem
    Kampf gesetzt. Hat Leatrix Plus „Max camera zoom“ an, hält sich ezCore zurück (Core.WhoHandles("cameraZoom")).
    Spieltest des Nutzers vom 24.11.2026 (wörtlich): „die einstellung "kamera weiterheraus zoomen" geht nicht? oder ist
    meine kamera fixed eingestellt?“ – Das Spiel kann seine gespeicherten Werte erst nach PLAYER_LOGIN laden und den
    Faktor dabei zurückstellen: ezCore setzt ihn nach ACCOUNT_CVARS_LOADED (das Spiel hat seine Kontowerte geladen) und
    CAMERA_RECHECK Sekunden nach dem Anmelden noch einmal, ebenso, wenn die CVar in den ersten CAMERA_SETTLE Sekunden
    wechselt. Nach dem Umschalten sagt eine Chatzeile, welchen Faktor das Spiel
    angenommen hat (zurückgelesen) und ob das Mausrad die Kamera überhaupt zoomt; dasselbe in /ez status. Eine
    Einstellung, die den Zoom festhält, gibt es in Blizzards Optionen nicht (Forever-Quelle, Abschnitt Kamera).

      ezCore.Comfort.Switches()          → verfügbare CVar-Schalter { key, cvar, kind, min, max, step }
      ezCore.Comfort.AddSection(cat)     legt den Abschnitt an (Collection.lua ruft es auf)
      ezCore.Comfort.ApplyBetaHints()    wendet den Schalter an (beim Laden des Reporters und beim Umschalten)
      ezCore.Comfort.CameraZoom()        → aktueller Faktor (Zahl) oder nil (CVar unbekannt oder gesperrt)
      ezCore.Comfort.ApplyCameraZoom()   wendet den Kamera-Schalter an (beim Anmelden, beim Umschalten, nach dem
                                         Kampf) → true, wenn die CVar gesetzt wurde; sonst false, Grund
                                         ("db", "other", "unknown", "combat", "same", "changed", "failed"); bei true
                                         "capped", wenn das Spiel weniger als CAMERA_MAX angenommen hat
      ezCore.Comfort.CameraLines()       → Textzeilen zum Zustand (Faktor, Mausrad) für Chat und /ez status
]]

local Comfort = {}
Core.Comfort = Comfort

-- Weitere Felder (ST-01, MACRO-32; Entscheidung 13.11.2026 „ezCore Komfort“): blizzard = { Name … } – Blizzards
-- Einstellung unter anderem Namen (Proxy wie „UNIT_NAMEPLATES_CLASS_COLOR“), dann kein Schalter; needs = fn() →
-- bool (z. B. „zeigt Blizzards Zielfenster überhaupt eine Bedrohungszahl?“); graphics = true – Hinweis auf Leistung
-- und darauf, dass Blizzards Grafikstufen den Wert überschreiben können; feature = Schlüssel für Core.WhoHandles
-- (Rücksicht, Leitlinie 9: übernimmt ein fremdes Addon die Funktion, fehlt der Schalter). Die CVar-Namen gelten erst,
-- wenn der Client sie kennt (Core.CVar liefert einen Wert) – sonst erscheint nichts.
-- Einstellungs-Prüfung 19.11.2026 (Abschnitt 4, Entscheidung des Nutzers „Ja, alle umsetzen“): defaultOn = true – steht
-- Blizzards Standard der CVar auf „an“ (C_CVar.GetCVarDefault) und der Wert auch, fehlt der Schalter: er könnte dann
-- nur etwas Hilfreiches abschalten. Wer ihn früher ausgeschaltet hat, sieht ihn weiter (Wert ≠ Standard), bis er wieder
-- an ist. parent = Schlüssel des Oberschalters: die Zeile ist eingerückt und grau, solange er aus ist.
Comfort.CVARS = {
    { key = "autoDismount", cvar = "autoDismount", defaultOn = true },
    { key = "autoDismountFlying", cvar = "autoDismountFlying", flying = true, parent = "autoDismount" },
    { key = "autoStand", cvar = "autoStand", defaultOn = true },
    { key = "autoUnshift", cvar = "autoUnshift" },
    { key = "alwaysCompare", cvar = "alwaysCompareItems" },
    { key = "screenshotQuality", cvar = "screenshotQuality", kind = "slider", min = 1, max = 10, step = 1 },
    -- Konsolen-Schalter aus dem ezMacro-Abgleich (ST-01, MACRO-32)
    { key = "threatNumeric", cvar = "threatShowNumeric", needs = function() return Comfort.TargetShowsThreat() end },
    { key = "nameplateClassColor", cvar = "nameplateShowClassColor", blizzard = { "UNIT_NAMEPLATES_CLASS_COLOR" } },
    { key = "nameplateFriendlyClassColor", cvar = "nameplateShowFriendlyClassColor", blizzard = { "UNIT_NAMEPLATES_CLASS_COLOR" } },
    { key = "rawMouse", cvar = "rawMouseEnable" },
    { key = "groundDensity", cvar = "groundEffectDensity", kind = "slider", min = 16, max = 256, step = 16, graphics = true,
        blizzard = { "PROXY_GROUND_CLUTTER", "graphicsGroundClutter" } },
    { key = "groundDistance", cvar = "groundEffectDist", kind = "slider", min = 40, max = 300, step = 10, graphics = true,
        blizzard = { "PROXY_GROUND_CLUTTER", "graphicsGroundClutter" } },
    { key = "sharpen", cvar = "resampleAlwaysSharpen", graphics = true },
    { key = "gamepad", cvar = "GamePadEnable" },
}

local function BlizzardOffers(cvar)
    if not (Settings and Settings.GetSetting) then return false end
    local ok, setting = pcall(Settings.GetSetting, cvar)
    return ok and setting ~= nil
end

-- Bedrohung in Prozent am Zielfenster: Blizzards Zielfenster der Retail-Familie hat dafür eine Anzeige
-- (NumericalThreat, Blizzard_UnitFrame/Mainline); Forevers eigenes Zielfenster (Camelot/TargetFrame.lua, Zweig
-- forever) hat keine – dann wäre der Schalter wirkungslos und erscheint nicht.
function Comfort.TargetShowsThreat()
    local target = rawget(_G, "TargetFrame")
    if type(target) ~= "table" then return false end
    if rawget(target, "threatNumericIndicator") ~= nil then return true end
    local content = rawget(target, "TargetFrameContent")
    local contextual = type(content) == "table" and rawget(content, "TargetFrameContentContextual")
    return type(contextual) == "table" and rawget(contextual, "NumericalThreat") ~= nil
end

local function Offered(entry)
    if BlizzardOffers(entry.cvar) then return true end
    for _, name in ipairs(entry.blizzard or {}) do
        if BlizzardOffers(name) then return true end
    end
    return false
end

-- Fliegen möglich? Auf Forever gibt es keine Flugreittiere, nur Flugrouten (Nutzer 13.11.2026) – dann fehlt
-- „Auch im Flug absteigen“ (die Funktion bleibt, sie erscheint nur, wo IsFlyableArea Fliegen meldet).
function Comfort.CanFly()
    if IsFlyableArea then
        local ok, flyable = pcall(IsFlyableArea)
        if ok and flyable == true then return true end
    end
    return false
end

-- Steht die CVar auf Blizzards Standard „an“? (Nur gelesen; gesperrt oder unbekannt zählt als nein.)
function Comfort.DefaultAndOn(entry, value)
    if not (C_CVar and C_CVar.GetCVarDefault) or Core.IsSecret(value) then return false end
    local ok, default = pcall(C_CVar.GetCVarDefault, entry.cvar)
    if not ok or Core.IsSecret(default) then return false end
    return tostring(default) == "1" and tostring(value) == "1"
end

function Comfort.Switches()
    local list = {}
    for _, entry in ipairs(Comfort.CVARS) do
        local ok, value = pcall(Core.CVar, entry.cvar)
        value = ok and value or nil
        local needs = true
        if entry.needs then
            local okNeeds, yes = pcall(entry.needs)
            needs = okNeeds and yes == true
        end
        if not Core.IsSecret(value) and value ~= nil and not Offered(entry) and needs
            and (not entry.flying or Comfort.CanFly())
            and not (entry.defaultOn and Comfort.DefaultAndOn(entry, value))
            and not (entry.feature and Core.WhoHandles and Core.WhoHandles(entry.feature)) then
            list[#list + 1] = entry
        end
    end
    return list
end

---------------------------------------------------------------------------
-- Beta-Hinweise
---------------------------------------------------------------------------

-- Standardwerte an EINER Stelle (V-018): Core.DEFAULTS.comfort, aufgefüllt von Core.OwnSettings.
Comfort.DEFAULTS = Core.OwnDefaults("comfort", { betaHints = false, cameraZoom = false })

local function DB()
    return Core.OwnSettings("comfort")
end

local function HideBeta()
    local c = DB()
    return c ~= nil and c.betaHints == true and Core.WhoHandles("betaHints") == nil
end

local hookedReporter, hiddenByUs
local hookedSurveys = setmetatable({}, { __mode = "k" })

local function HideSurveys(reporter)
    local data = type(reporter.Data) == "table" and reporter.Data
    local surveys = data and type(data.FrameAttachedSurveyFrames) == "table" and data.FrameAttachedSurveyFrames
    if not surveys then return end
    for _, survey in pairs(surveys) do
        if type(survey) == "table" and survey.HookScript then
            if not hookedSurveys[survey] then
                hookedSurveys[survey] = true
                survey:HookScript("OnShow", function(self) if HideBeta() then self:Hide() end end)
            end
            if survey:IsShown() then survey:Hide() end
        end
    end
end

function Comfort.ApplyBetaHints()
    local reporter = rawget(_G, "PTR_IssueReporter")
    if type(reporter) ~= "table" or not reporter.HookScript then return false end
    if hookedReporter ~= reporter then
        hookedReporter = reporter
        reporter:HookScript("OnShow", function(self)
            if HideBeta() then
                hiddenByUs = true
                self:Hide()
            end
        end)
        if type(reporter.PopFrameAttachedSurvey) == "function" then
            hooksecurefunc(reporter, "PopFrameAttachedSurvey", function(self) if HideBeta() then HideSurveys(self) end end)
        end
    end
    if HideBeta() then
        if reporter:IsShown() then hiddenByUs = true end
        reporter:Hide()
        HideSurveys(reporter)
    elseif hiddenByUs then
        hiddenByUs = false
        reporter:Show()
    end
    return true
end

local applyLater = Core.Throttle(function() Comfort.ApplyBetaHints() end, 0.1, "ezCore")
ns.On("ADDON_LOADED", applyLater)
ns.On("PLAYER_LOGIN", applyLater)

---------------------------------------------------------------------------
-- Kamera weiter herauszoomen
---------------------------------------------------------------------------

Comfort.CAMERA_CVAR = "cameraDistanceMaxZoomFactor"
Comfort.CAMERA_MAX = 2.6
local CAMERA_EPSILON = 0.001
Comfort.CAMERA_RECHECK, Comfort.CAMERA_SETTLE = 5, 15
Comfort.CAMERA_TRIES = 3    -- so oft setzt ezCore je Anmeldung nach einem CVAR_UPDATE neu (kein Hin und Her mit dem Client)
Comfort.CAMERA_ANSWER = 2   -- so lange nach dem eigenen Setzen gilt ein kleinerer Wert als Antwort des Clients, nicht als Wahl
local cameraPending, cameraSetting, cameraSettled = false, false, false
local cameraTries, cameraSetAt, cameraChosen = 0, nil, false

function Comfort.CameraZoom()
    local raw = Core.CVar(Comfort.CAMERA_CVAR)
    if Core.IsSecret(raw) or raw == nil then return nil end
    return tonumber(raw)
end

-- Blizzards Standard der CVar, nur wenn er unter dem Höchstwert liegt (Rückfall, falls beim Einschalten schon
-- jemand anderes ganz herausgezoomt hatte – sonst täte „aus“ nichts).
local function CameraDefault()
    if not (C_CVar and C_CVar.GetCVarDefault) then return nil end
    local ok, raw = pcall(C_CVar.GetCVarDefault, Comfort.CAMERA_CVAR)
    if not ok or Core.IsSecret(raw) or raw == nil then return nil end
    local value = tonumber(raw)
    if value and value < Comfort.CAMERA_MAX - CAMERA_EPSILON then return value end
    return nil
end

local function SetCamera(value)
    cameraSetting = true        -- CVAR_UPDATE der eigenen Umstellung nicht als fremde zählen
    local ok = Core.SetCVar(Comfort.CAMERA_CVAR, tostring(value))
    cameraSetting = false
    cameraSetAt = Core.Uptime()
    return ok
end

local function Near(a, b) return a ~= nil and b ~= nil and math.abs(a - b) <= CAMERA_EPSILON end

function Comfort.ApplyCameraZoom()
    local c = DB()
    if not c then return false, "db" end
    if Core.WhoHandles("cameraZoom") then return false, "other" end
    local current = Comfort.CameraZoom()
    if current == nil then return false, "unknown" end
    if Core.InCombat() then
        cameraPending = true
        Core.AfterCombat(function()
            if cameraPending then Comfort.ApplyCameraZoom() end
        end, "ezCore.cameraZoom", Core.name)
        return false, "combat"
    end
    cameraPending = false
    local max = Comfort.CAMERA_MAX
    if c.cameraZoom == true then
        if current >= max - CAMERA_EPSILON then
            if c.cameraZoomOld == nil then c.cameraZoomOld = CameraDefault() end
            return false, "same"
        end
        -- Der gemerkte Wert des Spielers bleibt: Was beim Anmelden gelesen wird, kann der Client gerade erst laden oder
        -- begrenzt haben (cameraZoomCap). Eine Wahl über Blizzards Regler merkt Comfort.OnCameraCVar (Review 24.11.2026).
        if c.cameraZoomOld == nil then c.cameraZoomOld = current end
        if not SetCamera(max) then return false, "failed" end
        local now = Comfort.CameraZoom()
        if now ~= nil and now < max - CAMERA_EPSILON then
            c.cameraZoomCap = now
            return true, "capped"
        end
        c.cameraZoomCap = nil
        return true
    end
    local old = c.cameraZoomOld
    if old == nil then return false, "same" end
    local cap = c.cameraZoomCap
    c.cameraZoomOld, c.cameraZoomCap = nil, nil
    if current < max - CAMERA_EPSILON and not Near(current, cap) then return false, "changed" end
    if SetCamera(old) then return true end
    c.cameraZoomOld, c.cameraZoomCap = old, cap   -- nicht gesetzt (geschützt): beim nächsten Mal noch einmal
    return false, "failed"
end

-- Was das Mausrad beim Herunterdrehen tut: true (Kamera), sonst Name der Belegung oder false (nichts) und die Taste, auf
-- der „Herauszoomen“ stattdessen liegt (nil: auf keiner) – nur gelesen; nil: der Client nennt es nicht
Comfort.CAMERA_ACTION = "CAMERAZOOMOUT"
function Comfort.CameraWheel()
    local action = Core.Call(rawget(_G, "GetBindingAction"), "MOUSEWHEELDOWN", true)
    if Core.IsSecret(action) or type(action) ~= "string" then return nil end
    if action == Comfort.CAMERA_ACTION then return true end
    local key = Core.Call(rawget(_G, "GetBindingKey"), Comfort.CAMERA_ACTION)
    if Core.IsSecret(key) or type(key) ~= "string" or key == "" then key = nil end
    if action == "" then return false, key end
    local name = Core.Call(rawget(_G, "GetBindingName"), action)
    if Core.IsSecret(name) or type(name) ~= "string" or name == "" then name = action end
    return name, key
end

-- Zustand in Worten: Faktor laut Spiel und Schalter, dazu das Mausrad, wenn es die Kamera nicht zoomt. → Liste
function Comfort.CameraLines()
    local c = DB()
    local now = Comfort.CameraZoom()
    if not c or now == nil then return {} end
    local on = c.cameraZoom == true
    local lines = {}
    local other = Core.WhoHandlesInfo("cameraZoom")     -- Auskunft: zählt nicht als „gewichen“
    local factor = Core.Decimal(now, 1)
    if other then
        lines[1] = L.CAMERA_OTHER:format(factor, other)
    elseif not on then
        lines[1] = L.CAMERA_OFF:format(factor, L.OPT_cameraZoom)
    elseif now >= Comfort.CAMERA_MAX - CAMERA_EPSILON then
        lines[1] = L.CAMERA_ON:format(factor)
    elseif Near(now, c.cameraZoomCap) then
        lines[1] = L.CAMERA_CAPPED:format(factor, Core.Decimal(Comfort.CAMERA_MAX, 1))
    else
        lines[1] = L.CAMERA_WAITING:format(factor, Core.Decimal(Comfort.CAMERA_MAX, 1), L.OPT_cameraZoom)
    end
    local yards = Core.Num(Core.Call(rawget(_G, "GetCameraZoom")))
    if yards then lines[1] = lines[1] .. " " .. L.CAMERA_DISTANCE:format(Core.Decimal(yards, 1)) end
    local wheel, key = Comfort.CameraWheel()
    if wheel ~= nil and wheel ~= true then
        lines[2] = wheel and L.CAMERA_WHEEL:format(wheel) or L.CAMERA_WHEEL_NONE
        lines[3] = key and L.CAMERA_KEY:format(key) or L.CAMERA_KEY_NONE
    end
    return lines
end

-- Umschalten auf der Seite, in der Einführung und über „Allem zustimmen“: setzen und sagen, was das Spiel daraus macht
function Comfort.OnCameraToggle()
    cameraChosen = false
    local ok, why = Comfort.ApplyCameraZoom()
    local c = DB()
    if not c then return ok, why end
    if c.cameraZoom == true and why ~= "combat" then
        if why == "failed" then ns.Print(L.CAMERA_FAILED) end
        for _, line in ipairs(Comfort.CameraLines()) do ns.Print(line) end
    end
    return ok, why
end

-- Noch einmal anwenden, sofern der Spieler den Regler seit dem Anmelden nicht selbst verstellt hat
local function Again()
    if not cameraChosen then Comfort.ApplyCameraZoom() end
end
function Comfort.CameraLogin()
    cameraSettled, cameraTries, cameraChosen = false, 0, false
    Comfort.ApplyCameraZoom()
    C_Timer.After(Comfort.CAMERA_RECHECK, Again)
    C_Timer.After(Comfort.CAMERA_SETTLE, function() cameraSettled = true end)
end

-- Blizzards Einstellungen offen? Dann ist eine Änderung die Wahl des Spielers, auch kurz nach /reload.
local function OptionsOpen()
    local panel = rawget(_G, "SettingsPanel")
    if type(panel) ~= "table" or type(panel.IsShown) ~= "function" then return false end
    local shown = Core.Call(panel.IsShown, panel)
    return not Core.IsSecret(shown) and shown == true
end

-- Der Faktor wurde kleiner, ohne dass ezCore ihn gerade setzt. Kurz nach dem Anmelden: Das Spiel lädt seine Werte nach –
-- wieder anwenden, höchstens CAMERA_TRIES Mal (danach gilt der Wert als Grenze des Clients). Direkt nach dem eigenen Setzen:
-- die Grenze des Clients. Bei offenen Einstellungen: die Wahl des Spielers (gemerkt für „aus“). Sonst (später, Konsole,
-- fremdes Addon) nichts – „aus“ lässt einen anderen Wert ohnehin stehen.
function Comfort.OnCameraCVar(name)
    if cameraSetting or Core.IsSecret(name) or name ~= Comfort.CAMERA_CVAR then return end
    local c = DB()
    local now = Comfort.CameraZoom()
    if not c or c.cameraZoom ~= true or now == nil or now >= Comfort.CAMERA_MAX - CAMERA_EPSILON
        or Near(now, c.cameraZoomCap) or Core.WhoHandlesInfo("cameraZoom") then
        return
    end
    local answer = cameraSetAt ~= nil and Core.Uptime() - cameraSetAt < Comfort.CAMERA_ANSWER
    local options = OptionsOpen()
    if answer and (cameraSettled or options) then
        c.cameraZoomCap = now
    elseif options then
        c.cameraZoomOld, cameraChosen, cameraPending = now, true, false
    elseif cameraSettled then
        return
    elseif cameraTries >= Comfort.CAMERA_TRIES then
        c.cameraZoomCap = now
    else
        cameraTries = cameraTries + 1
        Comfort.ApplyCameraZoom()
    end
end
ns.On("PLAYER_LOGIN", function() Comfort.CameraLogin() end)
ns.On("ACCOUNT_CVARS_LOADED", Again)
ns.On("CVAR_UPDATE", function(_, name) Comfort.OnCameraCVar(name) end)
-- Im Kampf gewünscht: Core.AfterCombat holt es nach (siehe ApplyCameraZoom).


---------------------------------------------------------------------------
-- Abschnitt auf der Seite „ezCollection“
---------------------------------------------------------------------------

local function Tip(key, entry)
    local tip = L["OPT_" .. key .. "_TIP"]
    if entry and entry.graphics then tip = tip .. "\n\n" .. L.COMFORT_GRAPHICS_NOTE end
    return tip
end

-- Kästchen für einen Schalter in ezCoreDB.comfort (Schlüssel = Funktion in Core.OTHER_ADDONS); übernimmt ein
-- fremdes Addon die Funktion, sagt der Tooltip, wer. Läuft über die Page-Helfer (V-018: page:OwnCheckbox) – damit
-- gelten Core.DEFAULTS.comfort und der Knopf „Einstellungen zurücksetzen“ auch hier.
local function ComfortCheckbox(page, key, onChange)
    return page:OwnCheckbox("comfort", key, { feature = key, onChange = function() onChange() end })
end

-- Bereich eines Reglers: der eigene, aber immer so weit, dass der heutige Wert des Clients darin liegt (die Grenzen
-- der Grafik-CVars sind auf Forever nicht belegt – ein Regler darf den Wert beim Öffnen nie verschieben).
function Comfort.SliderRange(entry)
    local low, high = entry.min, entry.max
    local ok, raw = pcall(Core.CVar, entry.cvar)
    local current = ok and not Core.IsSecret(raw) and tonumber(raw) or nil
    if current then
        if current < low then low = current end
        if current > high then high = current end
    end
    return low, high
end

function Comfort.AddSection(cat)
    if not (cat and Settings and Settings.CreateCheckbox) then return end
    local page = Core.ParentPage()
    if not page then return end
    page:Header(L.COMFORT_HEADER, L.COMFORT_HEADER_TIP)
    local c = DB()
    if c and Settings.RegisterAddOnSetting then
        ComfortCheckbox(page, "betaHints", Comfort.ApplyBetaHints)
        if Comfort.CameraZoom() ~= nil then ComfortCheckbox(page, "cameraZoom", Comfort.OnCameraToggle) end
    end
    if Core.MoveFrames then
        local okMove, errMove = pcall(Core.MoveFrames.AddSettings, cat)
        if not okMove then Core.Error(Core.name, errMove, "MoveFrames") end
    end
    if not Settings.RegisterProxySetting then return end
    -- Grafik-Werte unter eigener Überschrift „Grafik“ (Einstellungs-Prüfung 19.11.2026, Abschnitt 3: vorher zwischen den
    -- Komfort-Schaltern)
    local switches, graphics = {}, {}
    for _, entry in ipairs(Comfort.Switches()) do
        if entry.graphics then graphics[#graphics + 1] = entry else switches[#switches + 1] = entry end
    end
    local rows = {}
    local function Add(entry)
        local ok, err = pcall(function()
            local variable = "ezCore_comfort_" .. entry.key
            local opts = { parent = entry.parent and rows[entry.parent] or nil }
            local tip = Core.SettingsDependentTip(page, opts, Tip(entry.key, entry))
            local setting, row
            if entry.kind == "slider" then
                setting = Core.CVarSetting(cat, variable, entry.cvar, Settings.VarType.Number, L["OPT_" .. entry.key])
                local low, high = Comfort.SliderRange(entry)
                local options = Settings.CreateSliderOptions(low, high, entry.step)
                row = Settings.CreateSlider(cat, setting, options, tip)
            else
                setting = Core.CVarSetting(cat, variable, entry.cvar, Settings.VarType.Boolean, L["OPT_" .. entry.key])
                row = Settings.CreateCheckbox(cat, setting, tip)
            end
            if type(row) == "table" then rows[entry.key] = row end
            Core.AddSettingsDependency(page, row, opts)
        end)
        if not ok then Core.Error(Core.name, err, "Comfort") end
    end
    for _, entry in ipairs(switches) do Add(entry) end
    if #graphics > 0 then
        page:Header(L.COMFORT_GRAPHICS_HEADER, L.COMFORT_GRAPHICS_HEADER_TIP)
        for _, entry in ipairs(graphics) do Add(entry) end
    end
end
