local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Klick-Legende im Tooltip von Blizzards Gruppen- und Raidrahmen (HL-01, VP-54): Zeigt der Tooltip ein Mitglied
    über einem Rahmen aus ezCore.GroupFrames, hängt ezHeal die geltende Klick-Belegung an
    („Umschalt + Linksklick   Blitzheilung (Rang 7)“). Kein eigener Tooltip-Hook: ezCores Einheiten-Pipeline
    (Core.Tooltip.AddUnitSection, UnitTooltip.lua) ruft den Abschnitt; gelesen wird über Core.ClickBindings.List.

      Legend.Lines()                  → { { key = Text, what = Text, self = true | nil } … }, weitere | nil   (nil: nichts
                                         zu zeigen; self: liegt auf Blizzards Selbstwirk-Taste, wirkt auf dich – rot)
      Legend.FrameUnit(tooltip)       → Einheit, wenn der Tooltip zu einem Gruppen- oder Raidrahmen gehört (GF.TooltipUnit)
      Legend.AddSection(tooltip, unit) hängt die Zeilen an (Abschnitt der Pipeline)
      Legend.Other()                  → Anzeigename des Addons, das die Legende schon zeigt, oder nil

    Regeln:
      - nur am Rahmen aus Core.GroupFrames (Besitzer des Tooltips oder dessen Elternrahmen), nie an Namensplaketten,
        der Welt-Einheit oder anderen Einheitenrahmen
      - nur lesbare Einträge: Core.ClickBindings.List lässt Unlesbares weg; geheime Werte werden nie verglichen
      - Zauber im geltenden Rang: der Rang der belegten Zauber-ID (Core.Spells.Rank), nicht der höchste bekannte
      - Blizzards Standard (Linksklick = Ziel, Rechtsklick = Menü ohne Umschalttaste) kennt jeder: ausgelassen
      - tote Einträge (Core.ClickBindings.Dead: nur eine Hälfte einer Umschalttaste, etwa Umschalt als 1 aus der Zeit
        vor dem 15.11.2026) greifen beim Klick nie: ausgelassen, sonst stünde „Umschalt + Linksklick“ doppelt da
        (Gesamtreview 18.11.2026, T4-NG4)
      - Schalter clickLegend unter „Anzeige“. Läuft „Click Casting Tooltip“ (Core.WhoHandles("clickLegend"), Liste in
        ezCore/OtherAddOns.lua), hält sich die Legende zurück; das sagen der Tooltip des Schalters und /ezheal status
      - übernimmt ein anderes Addon das Klick-Zaubern (Clique …), kann es Tasten überdecken: eine graue Zeile sagt es
    Die Belegung wird bei jedem Aufruf frisch gelesen (Blizzard frischt den Tooltip am Rahmen laufend auf; Änderungen
    in Blizzards Fenster stehen so sofort da). Lesen ist auch im Kampf erlaubt.
]]

local Legend = {}
ns.Legend = Legend

Legend.KEY = "ezHeal.clickLegend"
Legend.ORDER = 55          -- nach den Zeilen ohne Platzangabe (50), vor möglicher Beute (ezLoot, 60)
Legend.MAX = 12            -- mehr Zeilen machen den Tooltip unlesbar; der Rest steht als Anzahl da
Legend.BUTTON_ORDER = { left = 1, right = 2, middle = 3 }

local function CB() return Core.ClickBindings end

function Legend.Other()
    return (ns.OtherFor("clickLegend"))
end

-- Blizzards Standard ohne Umschalttaste: Links = Ziel, Rechts = Menü
local function IsStandard(entry)
    if entry.kind ~= "interaction" or entry.modifiers ~= 0 then return false end
    return (entry.button == "LeftButton" and entry.action == "target")
        or (entry.button == "RightButton" and entry.action == "menu")
end

-- Was auf der Taste liegt, als Text; nil = nichts Nennenswertes (unbekannte Art)
local function What(entry)
    local cb = CB()
    if entry.kind == "spell" then
        local name = ns.Templates and ns.Templates.SpellName(entry.id) or Core.SpellName(entry.id)
        if type(name) ~= "string" or name == "" then return nil end
        local rank = Core.Spells and Core.Spells.Rank and Core.Spells.Rank(entry.id)
        -- zuerst IsSecret: im Client hat ein gesperrter Rang den Typ "number" (Leitlinie 6)
        if not Core.IsSecret(rank) and type(rank) == "number" and rank > 0 then
            name = name .. " (" .. L.RANK:format(rank) .. ")"
        end
        return name
    end
    if entry.kind == "pet" then return L.BINDING_PET end
    if entry.kind == "macro" or entry.kind == "interaction" then
        local text = cb and cb.Describe and cb.Describe(entry)
        if type(text) == "string" and text ~= "" and text ~= Core.L.CLICK_OTHER then return text end
    end
    return nil
end

local function ButtonRank(button)
    local cb = CB()
    local key = cb and cb.ButtonKey and cb.ButtonKey(button)
    if not key then return 99 end
    if Legend.BUTTON_ORDER[key] then return Legend.BUTTON_ORDER[key] end
    return 3 + (tonumber(key:match("^button(%d+)$")) or 96)
end

local function ModifierCount(mask)
    local cb = CB()
    local names = cb and cb.ModifierNames and cb.ModifierNames(mask)
    return names and #names or 0
end

-- Zeilen der Legende in fester Reihenfolge (Maustaste, dann Zahl der Umschalttasten, dann Blizzards Maske)
function Legend.Lines()
    local cb = CB()
    if not (cb and cb.Available and cb.Available()) then return nil end
    local list = cb.List()
    if type(list) ~= "table" then return nil end
    local rows = {}
    -- Blizzards Selbstwirk-Taste (Fehler vom 23.11.2026): Zauber, Makro und Begleiter-Aktion auf dieser Taste wirken
    -- auf dich statt auf den Rahmen – die Zeile sagt es (self = true); „Ziel“ und „Menü“ wirken nichts
    local selfKey = type(cb.SelfCastKey) == "function" and cb.SelfCastKey() or nil
    for _, entry in ipairs(list) do
        if type(entry) == "table" and not IsStandard(entry) and not (cb.Dead and cb.Dead(entry)) then
            local what = What(entry)
            if what then
                local casts = entry.kind == "spell" or entry.kind == "macro" or entry.kind == "pet"
                rows[#rows + 1] = { key = cb.KeyText(entry.button, entry.modifiers), what = what,
                    button = ButtonRank(entry.button), count = ModifierCount(entry.modifiers), mask = entry.modifiers,
                    self = casts and selfKey ~= nil and cb.HitsSelfCast(entry.modifiers, selfKey) ~= nil or nil }
            end
        end
    end
    if #rows == 0 then return nil end
    table.sort(rows, function(a, b)
        if a.button ~= b.button then return a.button < b.button end
        if a.count ~= b.count then return a.count < b.count end
        if a.mask ~= b.mask then return a.mask < b.mask end
        return a.what < b.what
    end)
    local more = 0
    while #rows > Legend.MAX do
        table.remove(rows)
        more = more + 1
    end
    return rows, more
end

-- Gehört der Tooltip zu einem Gruppen- oder Raidrahmen aus ezCore.GroupFrames? → Einheit | nil. Besitzer des Tooltips
-- oder dessen Elternrahmen (Blizzard setzt den Tooltip mancher Rahmen an ein Kind), gesperrte Werte zählen nicht – eine
-- Stelle in ezCore (GF.TooltipUnit, Welle 23a, A9; vorher stand dieselbe Suche hier und in ezCombat).
function Legend.FrameUnit(tooltip)
    local GF = Core.GroupFrames
    if not (GF and type(GF.TooltipUnit) == "function") then return nil end
    local ok, unit = pcall(GF.TooltipUnit, tooltip)
    if ok and type(unit) == "string" and not Core.IsSecret(unit) then return unit end
    return nil
end

function Legend.AddSection(tooltip, unit)
    if not ns.Enabled("clickLegend") or Legend.Other() then return end
    if not Legend.FrameUnit(tooltip) then return end
    local rows, more = Legend.Lines()
    if not rows then return end
    Core.Tooltip.Gap(tooltip)   -- ezCores einer Trenner (S-1811-Tooltipabstand): keine doppelte Leerzeile
    -- Rollen statt Farbzahlen (T9-6): Überschrift gold, Taste grau, Inhalt weiß, Hinweise grau
    Core.TipLine(tooltip, L.LEGEND_HEAD, "normal")
    for _, row in ipairs(rows) do
        if row.self then
            Core.TipDoubleLine(tooltip, row.key, row.what .. " – " .. L.LEGEND_SELF, "gray", "bad")
        else
            Core.TipDoubleLine(tooltip, row.key, row.what, "gray", "highlight")
        end
    end
    -- Rest der gekürzten Liste: ezCores „… und n weitere“ (Core.More) plus der Ort, an dem alles steht
    if more > 0 then Core.TipLine(tooltip, Core.More(more) .. " " .. L.LEGEND_MORE_WHERE, "hint") end
    local clique = ns.ClickCaster and ns.ClickCaster()
    if clique then Core.TipLine(tooltip, L.LEGEND_CLIQUE:format(clique), "hint", true) end
end

-- Abschnitt anmelden (einmal beim Laden)
if Core.Tooltip and Core.Tooltip.AddUnitSection then
    Core.Tooltip.AddUnitSection(Legend.KEY, Legend.ORDER, function(tooltip, unit) Legend.AddSection(tooltip, unit) end, ADDON)
end

-- Tooltip des Schalters: läuft ein Addon, das die Legende schon zeigt, sagt es das (Leitlinie 9)
function Legend.OptionTip()
    local other = Legend.Other()
    if other then return L.OPT_clickLegend_TIP .. "\n\n" .. L.LEGEND_OTHER:format(other) end
    return L.OPT_clickLegend_TIP
end

-- Zeile für /ezheal status
function Legend.StatusLine()
    local other = Legend.Other()
    if other then return L.STATUS_LEGEND_OTHER:format(other) end
    return L.STATUS_LEGEND:format(ns.Enabled("clickLegend") and L.ON or L.OFF)
end
