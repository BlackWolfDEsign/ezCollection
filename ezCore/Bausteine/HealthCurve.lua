local _, ns = ...
local Core = ezCore

--[[
    Deckkraft über Blizzards Kurve: 1 unter einem Anteil an Leben bzw. Kraft, sonst 0 – ohne Vergleich im eigenen Code
    (Leitlinie 6). Der Client wertet UnitHealthPercent bzw. UnitPowerPercent mit einer Stufenkurve (C_CurveUtil) aus,
    das gesperrte Ergebnis geht nur an SetAlpha. Genutzt von ezCombats Trank im mittigen Symbol (Potions.lua; Wunsch
    des Nutzers vom 23.11.2026). Entstanden mit den Restschaden-Bausteinen (PR 1b, 22.11.2026, damals RestBar.lua);
    die Balken-Bausteine (Core.NewRestBar, Core.NewLethalMark, Core.UnitHealthBar, Core.UnitHealthBarMask) sind am
    23.11.2026 ohne Aufrufer entfernt (Restschaden entfällt bis auf die Tränke, Leitlinie 8, Beleg im PR).
    Maßstab: UnitHealthPercent meldet 0…1 (Daten-Probe X10 vom 23.11.2026, beide Quadrate sichtbar).

      Core.StepCurve(punkte)              → neue Stufenkurve aus { { x, y }, … } (der Wert gilt ab x) oder nil ohne
                                          C_CurveUtil bzw. wenn der Aufbau scheitert (nie gemerkt, der nächste Aufruf
                                          versucht es wieder); ohne Enum.LuaCurveType.Step gilt die Vorgabe-Art des
                                          Clients. Der Aufrufer merkt sie sich. Kurven und Dauer-Objekte sind im
                                          Spiel Userdata (ObjectType „Userdata“, LuaCurveObjectAPIDocumentation.lua):
                                          nie eine Tabelle verlangen (Spieltest 25.11.2026, „Kurven fehlen“)
      Core.HEALTH_PERCENT_SCALE           Maßstab von UnitHealthPercent (1 = 0…1)
      Core.HealthCurve(punkt)             → Stufenkurve: 1 unter punkt, 0 ab punkt (roher Maßstab), gemerkt; nil ohne
                                          C_CurveUtil
      Core.HealthBelowCurve(anteil)       → dieselbe für einen Anteil 0…1 (über Core.HEALTH_PERCENT_SCALE)
      Core.HealthBelowAlpha(rahmen, einheit, anteil, mitVorhersage, kurve)
                                          → true | false: rahmen:SetAlpha(UnitHealthPercent(einheit, mitVorhersage,
                                          kurve)) – 1 unter dem Anteil, sonst 0; der Wert bleibt im Widget
      Core.PowerBelowAlpha(rahmen, einheit, kraftart, anteil, kurve)
                                          → true | false: dasselbe für Kraft über UnitPowerPercent(einheit, kraftart,
                                          false, kurve) – laut Forever-Quelle derselbe Maßstab 0…1 wie beim Leben
                                          (Core.UnitPowerText nutzt die Funktion schon); ezCombats Manatrank
]]

Core.HEALTH_PERCENT_SCALE = 1

local Open = Core.Num   -- offene Zahl oder nil (gesperrt, keine Zahl)

function Core.StepCurve(points)
    local api = rawget(_G, "C_CurveUtil")
    if type(api) ~= "table" or type(api.CreateCurve) ~= "function" then return nil end
    local ok, curve = pcall(api.CreateCurve)
    if not ok or Core.IsSecret(curve) or curve == nil then return nil end
    local enum = rawget(_G, "Enum")
    local step = type(enum) == "table" and type(enum.LuaCurveType) == "table" and enum.LuaCurveType.Step or nil
    local built = pcall(function()
        if step ~= nil then curve:SetType(step) end
        for _, point in ipairs(points) do curve:AddPoint(point[1], point[2]) end
    end)
    if not built then return nil end
    return curve
end

-- Kurven für Leben und Kraft: gemerkt je Punkt
local curves = {}

function Core.HealthCurve(at)
    at = Open(at)
    if not at then return nil end
    if not curves[at] then curves[at] = Core.StepCurve({ { 0, 1 }, { at, 0 } }) end
    return curves[at]
end

function Core.HealthBelowCurve(share)
    share = Open(share)
    if not share then return nil end
    return Core.HealthCurve(share * (Open(Core.HEALTH_PERCENT_SCALE) or 1))
end

function Core.HealthBelowAlpha(frame, unit, share, predicted, curve)
    curve = curve or Core.HealthBelowCurve(share)
    local fn = rawget(_G, "UnitHealthPercent")
    if not curve or type(fn) ~= "function" or type(frame) ~= "table" or Core.IsSecret(unit) or type(unit) ~= "string" then
        return false
    end
    -- das Ergebnis der Kurve ist gesperrt: es geht nur an SetAlpha (AllowedWhenTainted)
    return (pcall(function() frame:SetAlpha(fn(unit, predicted and true or false, curve)) end))
end

function Core.PowerBelowAlpha(frame, unit, powerType, share, curve)
    curve = curve or Core.HealthBelowCurve(share)
    local fn = rawget(_G, "UnitPowerPercent")
    if not curve or type(fn) ~= "function" or type(frame) ~= "table" or Core.IsSecret(unit) or type(unit) ~= "string"
        or Core.IsSecret(powerType) then
        return false
    end
    return (pcall(function() frame:SetAlpha(fn(unit, powerType, false, curve)) end))
end
