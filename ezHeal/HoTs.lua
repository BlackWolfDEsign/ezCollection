local ADDON, ns = ...
local Core = ezCore

--[[
    Eigene HoTs als kleine Symbolreihe an Blizzards Gruppen- und Raidrahmen (Entscheidung des Nutzers vom 13.11.2026:
    „eigene HoTs als abschaltbare Symbolreihe“). Keine eigenen Rahmen: je Rahmen aus ezCore.GroupFrames eine
    Reihe aus Blizzards Auren-Vorlage über ezCore.AuraRow. Blizzard sammelt und zeichnet die Auren selbst, auch im
    Kampf, wenn ihre Werte geheim sind – ezHeal liest keinen Wert. Anlegen, Einheit und Sichtbarkeit ändert ezCore
    nur außerhalb des Kampfes (im Kampf gemerkt, danach nachgeholt). Belegt Blizzard einen Rahmen im Kampf mit einem
    anderen Mitglied neu (onUnit) oder fällt er weg (onRemove), bleibt die Reihe bis Kampfende leer: ezCore macht sie
    durchsichtig, statt die HoTs des vorigen Mitglieds am neuen zu zeigen (Core.AuraRow, Gesamtreview 18.11.2026,
    T4-NG1); nach dem Kampf zeigt sie das neue Mitglied.
    Filter: eigene hilfreiche Auren („HELPFUL|PLAYER“) mit höchstens 60 Sekunden Dauer, also HoTs und Schilde,
    keine Dauer-Buffs.
    Platz am Rahmen (Platzplan „Mittelband teilen“, Entscheidung des Nutzers vom 14.11.2026): Die Reihe sitzt am
    Platz "midRight" aus ezCore.GroupFrames.SLOTS (Core.AuraRow slot statt eines eigenen Ankers) – im Raidstil Mitte
    rechts, nach links wachsend; klassisch rechts auf Blizzards Lebensbalken (seit dem Spielbefund vom 18.11.2026 im
    Rahmen statt rechts außen daneben). Vorher oben rechts, wo ezBuffs Symbol und
    Blizzards bannbare Debuffs liegen. ezBuff weicht den sichtbaren HoTs (die Reihe steht auch im Kampf).
]]

local H = {}
ns.HoTs = H

H.GROUP = "hots"
H.FILTER = "HELPFUL|PLAYER"
H.MAX = 4
H.MAX_DURATION = 60
H.SLOT = "midRight"
-- Symbolgröße für die Vormerkung: Blizzards Aurengröße an Raidrahmen. Die Zahl steht an einer Stelle in ezCore
-- (Core.GroupFrames.AURA_SIZE, NATIVE_UNIT_FRAME_AURA_SIZE aus CompactUnitFrame.lua) – keine eigene Kopie hier.
H.ICON = Core.GroupFrames and Core.GroupFrames.AURA_SIZE

-- Platz vormerken (einmal beim Laden): bis H.MAX Symbole nebeneinander.
if Core.GroupFrames and Core.GroupFrames.Reserve and H.ICON then
    Core.GroupFrames.Reserve(ADDON, H.SLOT, H.GROUP, { size = { H.MAX * H.ICON + (H.MAX - 1), H.ICON } })
end

local rows = setmetatable({}, { __mode = "k" })   -- [Blizzards Rahmen] = Reihe
local watching = false

local function Options(frame, unit)
    return {
        parent = frame, unit = unit, shown = true,
        slot = { H.SLOT, H.GROUP },
        groups = { { H.GROUP, H.FILTER, { maxFrameCount = H.MAX, candidateFilters = { maxDuration = H.MAX_DURATION } } } },
    }
end

function H.Add(frame, unit)
    if not (ns.Enabled("hots") and Core.AuraRow) then return nil end
    local row, reason = Core.AuraRow(ADDON, frame, Options(frame, unit))
    if row then rows[frame] = row end
    return row, reason
end

function H.SetUnit(frame, unit)
    local row = rows[frame]
    if row then return row:SetUnit(unit) end
    return H.Add(frame, unit)
end

function H.Remove(frame)
    local row = rows[frame]
    if row then row:Release() end
    rows[frame] = nil
end

-- Alle Reihen ausblenden (ezCore behält die Rahmen und benutzt sie beim Wiedereinschalten wieder)
function H.Stop()
    for frame, row in pairs(rows) do
        row:Release()
        rows[frame] = nil
    end
end

function H.Count()
    local n = 0
    for _ in pairs(rows) do n = n + 1 end
    return n
end

local function Watch()
    if watching or not (Core.GroupFrames and Core.GroupFrames.Watch) then return end
    watching = Core.GroupFrames.Watch(ADDON, {
        onAdd = function(frame, unit) H.Add(frame, unit) end,
        onUnit = function(frame, unit) H.SetUnit(frame, unit) end,
        onRemove = function(frame) H.Remove(frame) end,
    }) == true
end

-- Einstellung anwenden: an → für jeden bekannten Rahmen eine Reihe, aus → alle ausblenden
function H.Apply()
    if not ns.Enabled("hots") then
        H.Stop()
        return
    end
    if not watching then
        Watch()   -- onAdd läuft sofort für jeden schon bekannten Rahmen
        return
    end
    for _, info in ipairs(Core.GroupFrames.List()) do H.SetUnit(info.frame, info.unit) end
end

ns.OnReady(function() ns.Try("HoTs", H.Apply) end)
ns.OnSettingChanged(function(key)
    if key == "hots" then H.Apply() end
end)
