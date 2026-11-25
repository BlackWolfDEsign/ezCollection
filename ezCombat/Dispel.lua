local ADDON, ns = ...
local L = ns.L
local Core = ezCore
local Spells = Core.Spells

-- Bann-Hinweis: Was du dir oder einem Gruppenmitglied abnehmen kannst (Frage des Nutzers vom 24.11.2026, wörtlich: „… oder
-- gifte oder ... von mir oder jmd nehmen kann?“; Schalter dispelHint). Auf dem Porträt von Blizzards Spielerfenster und der
-- klassischen Gruppenrahmen erscheint das Symbol deines Bann-Zaubers, mit Blizzards Rand in der Farbe der Art, sobald dort
-- ein schädlicher Effekt liegt, den er nimmt – je gelerntem Zauber eines.
--   • C_UnitAuras.GetUnitAuraInstanceIDs geht dafür nicht: Es wirft im Kampf für Addon-Code (Proben 14.11. und 23.11.2026,
--     docs/datenprobe.md, Station R3; Forever-Quelle UnitAuraDocumentation.lua: RequiresUnitAuraAccess). Darum Blizzards
--     Auren-Container (ezCores Core.AuraRow): Blizzard wählt die Auren in seiner geschützten Umgebung selbst aus
--     (candidateFilters.includeDispelTypes, AuraContainerUtil.DoesAuraPassCandidateFilters) und zeigt den Knopf – ezCombat
--     liest nichts und weiß auch nicht, ob er gerade zu sehen ist. Der Knopf trägt statt des Symbols der Aura das des
--     Zaubers dagegen (Knopf-Vorlage texture).
--   • Filter „HARMFUL“ mit den Arten der eigenen Zauber statt „RAID_PLAYER_DISPELLABLE“: Der fragt laut Blizzards
--     AuraUtil-Kommentar, ob jemand im Schlachtzug bannen kann – nicht, ob du es kannst.
--   • Raidstil: nichts. Dort zeigt Blizzard bannbare Debuffs selbst (Optionen der Raidrahmen); doppelt wäre falsch. ezHeal
--     bindet die Bann-Zauber an Klicks, ezBuff zeigt fehlende Buffs – keines zeigt bannbare Effekte.
--   • Ob der Zauber gerade geht (Mana, Reichweite, Abklingzeit), sagt das Symbol nicht: Der Container kennt nur die Aura.
--     Deshalb fehlt hier auch die Steingestalt der Zwerge (Abklingzeit) und Magie verschlingen (Zauber des Begleiters).
--   • Taint-sicher: Anlegen, Einheit und Sichtbarkeit ändert ezCore nur außerhalb des Kampfes. Maus aus – Klicks gehen an
--     Blizzards Rahmen (Klick-Zauber).
local Dispel = {}
ns.Dispel = Dispel

Dispel.WATCH = "ezCombat.dispel"     -- eigener Schlüssel: ezCombats Rückrufe für die Zahlen am Rahmen heißen „ezCombat“
Dispel.SLOT = "dispel"               -- Platz in Core.GroupFrames.SLOTS
Dispel.SPACING = 2
Dispel.LEVEL = 20                    -- Ebenen über Blizzards Rahmen (über Porträt und Balken)

local GF = Core.GroupFrames
local rows = setmetatable({}, { __mode = "k" })   -- [Blizzards Rahmen] = Reihe
local known                                       -- gelernte Bann-Zauber, bis das Zauberbuch sich ändert
local watching = false

function Dispel.Known()
    if not known then known = Spells.DispelsBySpell() end
    return known
end

-- Schlüssel einer Gruppe: Zauber und Arten (lernst du einen besseren Zauber, kann ein Zauber Arten abgeben)
local function GroupKey(entry)
    return "dispel:" .. entry.base .. ":" .. table.concat(entry.kinds, "+")
end

local function GroupOptions(entry, size)
    local types = {}
    for _, kind in ipairs(entry.kinds) do types[kind] = true end
    return {
        maxFrameCount = 1,
        candidateFilters = { includeDispelTypes = types },
        layout = { elementWidth = size, elementHeight = size, elementSpacing = Dispel.SPACING, groupSpacing = Dispel.SPACING },
        button = { size = size, texture = Spells.Icon(entry.id) or Core.ICON_FALLBACK_ID, dispelBorder = true,
            duration = false, count = false, tooltip = false },
    }
end

-- Gruppen der Reihe auf den gelernten Stand bringen (ezCore merkt im Kampf vor)
local function SyncGroups(row, size)
    local want, have = {}, {}
    for _, key in ipairs(row:Groups()) do have[key] = true end
    for _, entry in ipairs(Dispel.Known()) do
        local key = GroupKey(entry)
        want[key] = true
        if not have[key] then
            row:AddAuraGroup(key, "HARMFUL", GroupOptions(entry, size))
        end
        row:SetEnabled(key, true)
    end
    for key in pairs(have) do
        if not want[key] then row:SetEnabled(key, false) end
    end
end

-- Reihe an einem Rahmen anlegen bzw. auffrischen. kind: "player" | "party" → Reihe oder nil, grund
function Dispel.Add(frame, unit, kind)
    if type(frame) ~= "table" or type(unit) ~= "string" then return nil, "invalid" end
    if not ns.Enabled("dispelHint") or not Core.AuraRow then return nil, "off" end
    if not rows[frame] and #Dispel.Known() == 0 then return nil, "none" end   -- diese Klasse kann (noch) nichts bannen
    local spec = GF.SlotSpec(kind, Dispel.SLOT)
    if not spec or spec.off then return nil, "slot" end
    local groups = {}
    for _, entry in ipairs(Dispel.Known()) do
        groups[#groups + 1] = { GroupKey(entry), "HARMFUL", GroupOptions(entry, spec.size) }
    end
    local fresh = rows[frame] == nil
    local row, reason = Core.AuraRow(ADDON, frame, {
        parent = frame, unit = unit, shown = true,
        anchor = { spec.point, frame, spec.relPoint, spec.x, spec.y }, groups = groups,
    })
    if not row then return nil, reason end
    rows[frame] = row
    SyncGroups(row, spec.size)
    if fresh then
        row:Do(function(container)
            container:SetFrameLevel((Core.Num(frame:GetFrameLevel()) or 1) + Dispel.LEVEL)
        end, "level")
    end
    return row, reason
end

function Dispel.Remove(frame)
    local row = rows[frame]
    if row then row:Release() end
    rows[frame] = nil
end

function Dispel.Stop()
    for frame in pairs(rows) do Dispel.Remove(frame) end
    Dispel.EndDemo()
end

function Dispel.Count()
    local n = 0
    for _ in pairs(rows) do n = n + 1 end
    return n
end

function Dispel.Row(frame) return rows[frame] end

-- Nur die klassischen Gruppenrahmen: den eigenen führt PlayerFrame selbst, im Raidstil zeigt Blizzard es
local function OnFrame(frame, unit, kind)
    if kind ~= "party" then return end
    ns.Try("Dispel", Dispel.Add, frame, unit, "party")
end

local function Watch()
    if watching or not (GF and GF.Watch) then return end
    watching = GF.Watch(Dispel.WATCH, {
        onAdd = function(frame, unit, kind) OnFrame(frame, unit, kind) end,
        onUnit = function(frame, unit, _, kind) OnFrame(frame, unit, kind) end,
        -- löst sich die Gruppe auf, meldet ezCore auch PlayerFrame ab (Art „player“): dessen Reihe bleibt
        onRemove = function(frame, _, kind)
            if kind == "party" then ns.Try("Dispel", Dispel.Remove, frame) end
        end,
    }) == true
end

-- Einstellung und gelernte Zauber anwenden
function Dispel.Update()
    if not ns.Enabled("dispelHint") then
        Dispel.Stop()
        return
    end
    local own = rawget(_G, "PlayerFrame")
    if type(own) == "table" then Dispel.Add(own, "player", "player") end
    if not watching then
        Watch()   -- onAdd läuft sofort für jeden schon bekannten Rahmen
    else
        for _, info in ipairs(GF.List()) do OnFrame(info.frame, info.unit, info.kind) end
    end
end

local demoRow, demoRun = nil, 0
function Dispel.EndDemo()
    local row = demoRow
    demoRow = nil
    if row then row:Preview(0) end
end

-- Vorschau („Zeigen“): deine Bann-Zauber am Spielerfenster. → true, wenn etwas zu sehen ist
function Dispel.Demo(seconds)
    local row = ns.Enabled("dispelHint") and rows[rawget(_G, "PlayerFrame") or false]
    local spec = GF and GF.SlotSpec("player", Dispel.SLOT)
    local icons = {}
    for index, entry in ipairs(Dispel.Known()) do icons[index] = Spells.Icon(entry.id) or Core.ICON_FALLBACK_ID end
    if not row or not spec or #icons == 0 then return false end
    if not row:Preview(#icons, { icons = icons, size = spec.size, spacing = Dispel.SPACING, plain = true,
        at = { spec.point, PlayerFrame, spec.relPoint, spec.x, spec.y } }) then return false end
    demoRow, demoRun = row, demoRun + 1
    local run = demoRun
    C_Timer.After(Core.Num(seconds) or 4, function()
        if run == demoRun then Dispel.EndDemo() end   -- sonst läuft eine neuere Vorschau
    end)
    return true
end

-- „Entgiften (Gift), Krankheit heilen (Krankheit)“ – leer: nichts gelernt
function Dispel.KnownText()
    local parts = {}
    for _, entry in ipairs(Dispel.Known()) do
        local kinds = {}
        for index, kind in ipairs(entry.kinds) do kinds[index] = L["DISPEL_" .. kind] or kind end
        parts[#parts + 1] = L.DISPEL_ENTRY:format(Spells.Name(entry.id) or ("#" .. entry.id), table.concat(kinds, ", "))
    end
    return table.concat(parts, ", ")
end

-- Tooltip des Schalters mit den gelernten Zaubern
function Dispel.Tip()
    local text = Dispel.KnownText()
    local tip = L.OPT_dispelHint_TIP .. "\n\n" .. (text ~= "" and L.DISPEL_KNOWN:format(text) or L.DISPEL_NONE)
    -- Rücksicht auf Rahmen-Ersatz (HealBot, VuhDo …): Dort steht der Hinweis nicht, das sagt der Tooltip (Leitlinie 9)
    local other = ns.OtherFor("healFrames")
    return other and (tip .. "\n\n" .. L.DISPEL_OTHER:format(other)) or tip
end

---------------------------------------------------------------------------

ns.OnReady(function() ns.Try("Dispel", Dispel.Update) end)
-- Im Kampf kein Beispiel: Es sähe aus wie ein Effekt, den du nehmen kannst
ns.On("PLAYER_REGEN_DISABLED", Dispel.EndDemo)
local Relearn = ns.Throttle(function()
    known = nil
    ns.Try("Dispel", Dispel.Update)
end, 0.5)
ns.On("SPELLS_CHANGED", function() Relearn() end)
ns.OnSettingChanged(function(key)
    if key == "dispelHint" then ns.Try("Dispel", Dispel.Update) end
end)
-- /ezk status: Ohne Blizzards Auren-Container gibt es keinen Hinweis (nichts wird geraten)
ns.AddStatusLine(function()
    if ns.Enabled("dispelHint") and Core.AuraRows and Core.AuraRows.Available() == false then return L.STATUS_DISPEL_MISSING end
end)

---------------------------------------------------------------------------
-- „Zeigen“ im Abschnitt: Trank, Rettungsfähigkeit, Leuchten und Bann-Zauber zusammen
ns.AddPreview("danger", 48, function()
    local seconds, shown = 4, false
    for _, part in ipairs({ ns.Potions, ns.Rescue, ns.Danger, Dispel }) do
        if part.Demo(seconds) then shown = true end
    end
    return shown
end)
