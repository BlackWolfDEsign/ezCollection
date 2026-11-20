local _, ns = ...
local L = ns.L

--[[
    Itemlevel je Platz am Charakterfenster und beim Betrachten, in der Farbe der
    Qualität, oben rechts am Platz – wie ezBags Itemlevel an den Taschenplätzen. Beim Betrachten dazu der Durchschnitt
    unter Blizzards Stufenzeile. Den eigenen Durchschnitt zeigt Blizzard schon in den Werten des Charakterfensters.
    Am eigenen Fenster außerdem die Haltbarkeit unten am Platz (ezCore.Durability; beim Betrachten gibt es keine)
    und oben links das Zeichen „Verzauberung fehlt“ an verzauberbaren Plätzen (W-38, Frage 24 – Empfehlung
    umgesetzt, Antwort offen; Liste ENCHANTABLE unten mit ihrer Quelle).

    Rücksicht (W-38, VP-47): Zeigt ein anderes Addon Itemlevel und Verzauberung an den Plätzen (ezCores Schlüssel
    slotLevels, heute Winter Essentials), hält sich ezGear am eigenen Fenster mit beidem zurück (ns.FOREIGN in
    Core.lua); /ezg status und der Tooltip der Schalter nennen das Addon.

    Hooks: PaperDollItemSlotButton_Update (Blizzard_UIPanels_Game, Forever-Fassung unter Camelot) und
    InspectPaperDollItemSlotButton_Update (Blizzard_InspectUI, lädt bei Bedarf). Itemlevel über ezCore.SlotText
    (EquippedLevel, Apply), Haltbarkeit und Verzauberungs-Zeichen als eigene Schrift bzw. Textur; Blizzards Felder
    bleiben unberührt.
]]

local Char = {}
ns.Character = Char

-- Plätze ohne Anzeige: Munition, Hemd, Wappenrock – aus ezCores Platzliste (Core.EquipSlots.BY_SLOT kennt die
-- Plätze des Charakterfensters, Hemd und Wappenrock sind dort „cosmetic“; die Munition steht nicht darin).
local function Skipped(slot)
    local slots = ezCore.EquipSlots
    local entry = slots and slots.BY_SLOT and slots.BY_SLOT[slot]
    return entry == nil or entry.cosmetic == true
end
Char.Skipped = Skipped

-- Schrift, Lage (oben rechts) und Qualitätsfarbe kommen aus ezCore.SlotText – dieselbe Fassung wie an ezBags und
-- ezLoots Plätzen (Core.QualityRGB).
function Char.SetLevel(button, level, quality)
    local slotText = ezCore.SlotText
    if not (slotText and slotText.Apply) then return end
    slotText.Apply(button, level and { ilvl = level, quality = quality } or nil)
end

function Char.LabelText(button)
    local slotText = ezCore.SlotText
    local overlay = slotText and slotText.Overlay and slotText.Overlay(button)
    return overlay and overlay.ilvl:GetText() or nil
end

-- Itemlevel und Qualität eines angelegten Platzes (unit = "player" oder der Betrachtete): ezCore.SlotText.EquippedLevel
-- (beim Spieler über ItemLocation, auch aufgewertete Gegenstände); Hemd, Wappenrock und Munition zeigen nichts.
function Char.SlotLevel(unit, slot)
    if Skipped(slot) then return nil end
    local slotText = ezCore.SlotText
    if not (slotText and slotText.EquippedLevel) then return nil end
    local level, quality, link = ns.Call(slotText.EquippedLevel, unit, slot)
    if not level or level <= 1 then return nil end
    return level, quality or ns.Stats.Quality(link), link
end

---------------------------------------------------------------------------
-- Haltbarkeit je Platz (nur das eigene Fenster): aus ezCores gemeinsamer Quelle (ezCore.Durability), unten am
-- Platz in Prozent, von Grün über Gelb nach Rot; erst, wenn der Gegenstand beschädigt ist.
---------------------------------------------------------------------------

local durabilityLabels = setmetatable({}, { __mode = "k" })

function Char.SetDurability(button, pct)
    local label = durabilityLabels[button]
    if not pct or pct >= 1 then
        if label then label:SetText("") end
        return
    end
    if not label then
        label = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        label:SetDrawLayer("OVERLAY", 7)
        label:SetPoint("BOTTOM", 0, 3)
        durabilityLabels[button] = label
    end
    label:SetText(ezCore.Gradient(pct) .. L.DURABILITY:format(math.floor(pct * 100 + 0.5)) .. "|r")
end

function Char.DurabilityText(button)
    local label = durabilityLabels[button]
    return label and label:GetText() or nil
end

-- Anteil 0–1 eines Platzes oder nil (keine Haltbarkeit, ezCore ohne Haltbarkeits-Quelle)
function Char.SlotDurability(slot)
    local source = ezCore.Durability
    if not (source and source.Slot) or Skipped(slot) then return nil end
    local _, _, pct = ns.Call(source.Slot, slot)
    return type(pct) == "number" and pct or nil
end

---------------------------------------------------------------------------
-- Zeichen „Verzauberung fehlt“ (nur das eigene Fenster; Schalter charEnchant)
---------------------------------------------------------------------------

-- Verzauberbare Plätze – eigene Liste (Leitlinie 10, nichts aus fremden Addons). Quelle: die Rezepte der
-- Verzauberkunst im Berufefenster des Clients („Umhang/Brust/Armschiene/Handschuhe/Stiefel/Waffe/Zweihandwaffe/
-- Schild verzaubern – …“), Stand der klassischen Rezepte; welche Plätze Forever wirklich anbietet, prüft der Spieltest
-- (Im Spiel prüfen 48). Bewusst nicht: Kopf und Beine (Arkanum bzw. Foliant von Fraktionen, keine Verzauberkunst),
-- Schultern, Hals, Ringe, Schmuck und Distanz (Zielfernrohr kommt aus der Ingenieurskunst).
-- Wert: "any" = jeder Gegenstand am Platz, "weapon" = nur Waffen (ohne Angelrute), "offhand" = Waffe oder Schild
-- (nichts „in der Schildhand Gehaltenes“).
local ENCHANTABLE = { BACK = "any", CHEST = "any", WRIST = "any", HANDS = "any", FEET = "any",
    MAINHAND = "weapon", OFFHAND = "offhand" }
Char.ENCHANTABLE = ENCHANTABLE
-- Erst ab dieser Qualität (Selten/Uncommon = 2, grün; Gewöhnlich/Common = 1 ist weiß): weiße und graue Teile verzaubert niemand – sonst stünde das
-- Zeichen auf niedriger Stufe an fast jedem Platz.
Char.ENCHANT_MIN_QUALITY = 2
local ENCHANT_ICON = "Interface\\Icons\\Trade_Engraving"   -- Blizzards Symbol der Verzauberkunst
local ENCHANT_SIZE = 13

-- Regel des Platzes (ENCHANTABLE) oder nil – über ezCores Platznamen (Core.EquipSlots.SLOT), erst beim Aufruf gelesen
local function EnchantRule(slot)
    local slots = ezCore.EquipSlots
    if not (slots and slots.SLOT) or type(slot) ~= "number" then return nil end
    for name, rule in pairs(ENCHANTABLE) do
        if slots.SLOT[name] == slot then return rule end
    end
    return nil
end

-- Lässt sich der Gegenstand an diesem Platz verzaubern? → true/false
function Char.Enchantable(slot, link)
    local rule = EnchantRule(slot)
    if not rule then return false end
    if rule == "any" then return true end
    local classID, subClassID = ezCore.ItemClass(link)
    local classes = ezCore.ITEM_CLASS or {}
    local weaponSub = Enum and Enum.ItemWeaponSubclass
    local armorSub = Enum and Enum.ItemArmorSubclass
    local FISHING_POLE = weaponSub and weaponSub.Fishingpole or 20
    local SHIELD = armorSub and armorSub.Shield or 6
    if classID == (classes.Weapon or 2) then return subClassID ~= FISHING_POLE end
    return rule == "offhand" and classID == (classes.Armor or 4) and subClassID == SHIELD
end

-- Verzauberung aus dem Gegenstands-Link (Feld nach der Item-ID: „item:ID:Verzauberung:…“) → Zahl (0 = keine) oder
-- nil (kein lesbarer Gegenstands-Link; gesperrte Werte werden nicht gelesen)
function Char.EnchantID(link)
    link = ns.Plain(link)
    if type(link) ~= "string" then return nil end
    local field = link:match("item:%-?%d+:([^:|]*)")
    if field == nil then return nil end
    return tonumber(field) or 0
end

-- Fehlt an einem angelegten Platz einer Einheit eine Verzauberung? – die EINE Regel für das eigene Charakterfenster
-- und den Ausrüstungs-Check der Gruppe (GroupCheck.lua; Gesamtreview 18.11.2026, I3). link ist freiwillig (schon
-- gelesen). Die Qualität kommt aus dem Item-Wissen, ersatzweise vom Client (GetInventoryItemQuality – Teile anderer
-- Spieler sind oft noch nicht im Zwischenspeicher). → true/false (Platz leer oder nicht verzauberbar, Teil unter
-- ENCHANT_MIN_QUALITY, Link oder Qualität nicht lesbar → false)
function Char.EnchantMissingFor(unit, slot, link)
    if Skipped(slot) or not EnchantRule(slot) then return false end
    link = ns.Plain(link or ns.Call(GetInventoryItemLink, unit, slot))
    if type(link) ~= "string" or link == "" or not Char.Enchantable(slot, link) then return false end
    local quality = ns.Stats.Quality(link) or ns.Num(ns.Call(rawget(_G, "GetInventoryItemQuality"), unit, slot))
    if not quality or quality < Char.ENCHANT_MIN_QUALITY then return false end
    return Char.EnchantID(link) == 0
end

-- Fehlt am eigenen Platz eine Verzauberung? → true/false (Schalter aus oder ein anderes Addon zeigt es → false,
-- sonst Char.EnchantMissingFor)
function Char.EnchantMissing(slot)
    if not ns.Active("charEnchant") then return false end
    return Char.EnchantMissingFor("player", slot)
end

local enchantMarks = setmetatable({}, { __mode = "k" })

function Char.SetEnchantMark(button, shown)
    local mark = enchantMarks[button]
    if not shown then
        if mark then mark:Hide() end
        return
    end
    if not mark then
        mark = button:CreateTexture(nil, "OVERLAY", nil, 6)
        mark:SetTexture(ENCHANT_ICON)
        mark:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        mark:SetSize(ENCHANT_SIZE, ENCHANT_SIZE)
        mark:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
        enchantMarks[button] = mark
    end
    mark:Show()
end

-- Trägt der Knopf gerade das Zeichen? (Tooltip-Zeile in Tooltip.lua, Tests)
function Char.EnchantShown(button)
    local mark = type(button) == "table" and enchantMarks[button] or nil
    return mark ~= nil and mark:IsShown() == true
end

local function UpdatePlayerSlot(button)
    local slot = ns.Call(button.GetID, button)
    if type(slot) ~= "number" then return end
    if ns.Active("charLevels") then
        Char.SetLevel(button, Char.SlotLevel("player", slot))
    else
        Char.SetLevel(button, nil)
    end
    Char.SetDurability(button, Char.SlotDurability(slot))   -- fest (Nr. 43): erscheint nur bei Schaden
    Char.SetEnchantMark(button, Char.EnchantMissing(slot))
end

---------------------------------------------------------------------------
-- Betrachten
---------------------------------------------------------------------------

local avgLabel

-- Durchschnitt des Betrachteten: EINE Regel mit ezCores Spieler-Tooltip (GEAR-11, V-113) – Core.SlotText.AverageLevel
-- (zuerst Blizzards eigene Zahl, Entscheidung „Ø-Itemlevel wie Blizzard“; sonst das Mittel über EquipSlots.COUNTED,
-- ein Zweihänder zählt auch für die leere Schildhand). → Stufe oder nil.
function Char.Average(unit)
    local slotText = ezCore.SlotText
    if not (slotText and slotText.AverageLevel) then return nil end
    return (ns.Call(slotText.AverageLevel, unit))
end

local function UpdateAverage()
    local frame = InspectPaperDollFrame
    if not frame then return end
    if not avgLabel then
        avgLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        local anchor = InspectLevelText or frame
        avgLabel:SetPoint("TOP", anchor, "BOTTOM", 0, -2)
    end
    local unit = InspectFrame and InspectFrame.unit
    local avg = ns.Enabled("inspectLevels") and unit and Char.Average(unit)
    avgLabel:SetText(avg and L.INSPECT_AVG:format(avg) or "")
end
Char.UpdateAverage = UpdateAverage
local averageSoon

local function UpdateInspectSlot(button)
    local unit = InspectFrame and InspectFrame.unit
    local slot = ns.Call(button.GetID, button)
    if not (ns.Enabled("inspectLevels") and unit and type(slot) == "number") then
        Char.SetLevel(button, nil)
    else
        Char.SetLevel(button, Char.SlotLevel(unit, slot))
    end
    averageSoon = averageSoon or ns.Throttle(function() ns.Try("InspectAverage", UpdateAverage) end, 0.1)
    averageSoon()
end

local function InstallInspect()
    if type(InspectPaperDollItemSlotButton_Update) ~= "function" then return false end
    hooksecurefunc("InspectPaperDollItemSlotButton_Update", function(button) ns.Try("Inspect", UpdateInspectSlot, button) end)
    return true
end

---------------------------------------------------------------------------
-- Angelegte Ausrüstung als Links in den EIGENEN Chat (Knopf „Chat“ am Charakterfenster, Sets.lua; aus dem Abgleich
-- mit ezMacros Sammlung „Makros & Scripte“). Gesendet wird nichts: ns.Print schreibt nur ins eigene Chatfenster,
-- von dort lässt sich ein Link mit Umschalt-Klick weitergeben. Plätze und Reihenfolge aus ezCores Platzliste
-- (Core.EquipSlots.LIST – wie am Charakterfenster, mit Hemd und Wappenrock), Namen der Plätze von Blizzard
-- (EquipSlots.Label), Links vom Client (GetInventoryItemLink).
---------------------------------------------------------------------------

-- Char.EquippedLines() → { { slot, label, link, level }, … } der belegten Plätze (level fehlt bei Hemd und Wappenrock)
function Char.EquippedLines()
    local lines = {}
    local slots = ezCore.EquipSlots
    for _, entry in ipairs(slots and slots.LIST or {}) do
        local link = ns.Plain(ns.Call(GetInventoryItemLink, "player", entry.slot))
        if type(link) == "string" and link ~= "" then
            local level = Char.SlotLevel("player", entry.slot)
            lines[#lines + 1] = { slot = entry.slot, link = link, level = level,
                label = (slots.Label and slots.Label(entry.slot)) or entry.key }
        end
    end
    return lines
end

-- → Zahl der geschriebenen Plätze
function ns.PrintEquipped()
    local lines = Char.EquippedLines()
    if #lines == 0 then
        ns.Print(L.GEARCHAT_NONE)
        return 0
    end
    ns.Print(L.GEARCHAT_HEAD)
    for _, line in ipairs(lines) do
        if line.level then
            ns.Print(L.GEARCHAT_LINE_LEVEL:format(line.label, line.link, line.level))
        else
            ns.Print(L.GEARCHAT_LINE:format(line.label, line.link))
        end
    end
    return #lines
end

---------------------------------------------------------------------------

-- Blizzards Platz-Knöpfe („CharacterHeadSlot“, beim Betrachten „InspectHeadSlot“) aus ezCores Platzliste
-- (Core.EquipSlots.LIST, Feld frame; EquipSlots.ButtonName – GEAR-08, vorher eine eigene Namensliste hier).
-- Hemd und Wappenrock stehen in der Liste und werden geleert (Char.Skipped: ohne Itemlevel und Haltbarkeit).
-- Char.ForEachSlotButton(inspect, fn) → Zahl der gefundenen Knöpfe
function Char.ForEachSlotButton(inspect, fn)
    local slots = ezCore.EquipSlots
    if not (slots and slots.LIST and slots.ButtonName) then return 0 end
    local found = 0
    for _, entry in ipairs(slots.LIST) do
        local name = slots.ButtonName(entry.slot, inspect)
        local button = name and _G[name]
        if button then
            found = found + 1
            fn(button)
        end
    end
    return found
end

-- → Zahl der neu gezeichneten Plätze
function Char.RefreshPlayer()
    return Char.ForEachSlotButton(false, function(button) ns.Try("Character", UpdatePlayerSlot, button) end)
end

-- Betrachten: alle Plätze neu (Schalter „Itemlevel beim Betrachten“ wirkt sofort, nicht erst beim nächsten
-- Betrachten). → Zahl der Plätze (0, solange Blizzards Betrachten-Fenster nicht geladen oder kein Ziel offen ist)
function Char.RefreshInspect()
    if not (InspectFrame and InspectFrame.unit) then return 0 end
    return Char.ForEachSlotButton(true, function(button) ns.Try("Inspect", UpdateInspectSlot, button) end)
end

ns.OnReady(function()
    if type(PaperDollItemSlotButton_Update) == "function" then
        hooksecurefunc("PaperDollItemSlotButton_Update", function(button) ns.Try("Character", UpdatePlayerSlot, button) end)
    end
    if not InstallInspect() then ns.WhenAddOnLoaded("Blizzard_InspectUI", InstallInspect) end
    ns.On("INSPECT_READY", function()
        averageSoon = averageSoon or ns.Throttle(function() ns.Try("InspectAverage", UpdateAverage) end, 0.1)
        averageSoon()
    end)
    ezCore.Listen("DURABILITY_CHANGED", function() Char.RefreshPlayer() end, "ezGear")
    -- Ein fremdes Addon übernimmt bzw. gibt die Plätze frei (Forever++ antwortet erst nach seinem READY)
    ezCore.Listen("OTHER_ADDONS_CHANGED", function() Char.RefreshPlayer() end, "ezGear")
    ns.OnSettingChanged(function(key)
        if key == "charLevels" or key == "charEnchant" then Char.RefreshPlayer() end
        if key == "inspectLevels" then
            Char.RefreshInspect()
            ns.Try("InspectAverage", UpdateAverage)
        end
    end)
end)
