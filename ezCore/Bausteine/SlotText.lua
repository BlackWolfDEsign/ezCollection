local _, ns = ...
local Core = ezCore

--[[
    Texte auf Platzknöpfen (gemeinsamer Dienst, Vorschlag von ezLoot; vorher je eine Fassung in ezBag/Layout.lua
    und ezLoot/Frames.lua): Itemlevel oben rechts in der Farbe der Qualität, „BoE“ unten links in Grün.
    Die übrigen Ecken: Marken oben links (ezBag Marks.lua, Pfeil „besser“ von ezGear), Anzahl unten rechts (Blizzard).

      ezCore.SlotText.ItemLevel(link, facts, bag, slot) → Itemlevel (> 1) oder nil
      ezCore.SlotText.Marks(link, opts)  → marks { ilvl, quality, bind }, equipment
                                           opts.itemLevel / opts.bind = false schaltet einen Teil ab;
                                           opts.bound (true/false aus dem Platz) geht vor bindType
      ezCore.SlotText.Apply(button, marks)   marks = nil leert den Knopf (Blizzard verwendet Knöpfe wieder)
      ezCore.SlotText.QualityRGB(quality) → r, g, b
      ezCore.SlotText.EquippedLevel(unit, slot) → Itemlevel, Qualität, Link eines angelegten Platzes (ezGear, ezPanel)
    Taint-sicher: eigene FontStrings am Knopf, gemerkt in einer eigenen Tabelle (nie als Feld in Blizzards Rahmen).
]]

local ST = {}
Core.SlotText = ST

local BIND_ON_EQUIP = 2     -- bindType aus GetItemInfo: 1 beim Aufheben, 2 beim Anlegen, 3 beim Benutzen
local BIND_COLOR_QUALITY = 2   -- Farbe der Marke „BoE“: Blizzards Qualitätsfarbe „Ungewöhnlich“ (Enum.ItemQuality.Uncommon)

local L = Core.NewLocale({ BIND_BOE = "BoE" }, { BIND_BOE = "BoE" })

function ST.ItemLevel(link, facts, bag, slot)
    if bag and slot and ItemLocation and C_Item and C_Item.GetCurrentItemLevel then
        local ok, location = pcall(ItemLocation.CreateFromBagAndSlot, ItemLocation, bag, slot)
        if ok and location then
            local okLevel, level = pcall(C_Item.GetCurrentItemLevel, location)
            level = okLevel and Core.Num(level) or nil
            if level and level > 1 then return level end
        end
    end
    local getLevel = C_Item and C_Item.GetDetailedItemLevelInfo or GetDetailedItemLevelInfo
    if getLevel and type(link) == "string" then
        local ok, level = pcall(getLevel, link)
        level = ok and Core.Num(level) or nil
        if level and level > 1 then return level end
    end
    local level = type(facts) == "table" and Core.Num(facts.itemLevel)
    if level and level > 1 then return level end
    return nil
end

-- Angelegter Platz (unit "player" oder der Betrachtete): Itemlevel wie Blizzards Charakterfenster – beim
-- Spieler über ItemLocation (auch aufgewertete Gegenstände), sonst über den Link –, Qualität und Link; nil, wenn leer.
function ST.EquippedLevel(unit, slot)
    unit, slot = unit or "player", Core.Num(slot)
    if not slot then return nil end
    local link = Core.Plain(Core.Call(rawget(_G, "GetInventoryItemLink"), unit, slot))
    if type(link) ~= "string" then return nil end
    local level
    if unit == "player" and ItemLocation and ItemLocation.CreateFromEquipmentSlot and C_Item and C_Item.GetCurrentItemLevel then
        local location = Core.Call(ItemLocation.CreateFromEquipmentSlot, ItemLocation, slot)
        level = location and Core.Num(Core.Call(C_Item.GetCurrentItemLevel, location)) or nil
    end
    if not (level and level > 1) then level = ST.ItemLevel(link) end
    if not level then return nil end
    return level, Core.Num(Core.Call(rawget(_G, "GetInventoryItemQuality"), unit, slot)), link
end

-- Durchschnitts-Itemlevel einer Einheit – EINE Regel (GEAR-11, V-113; vorher je einmal in ezGear und im Spieler-
-- Tooltip, mit verschiedenem Ausweichweg): zuerst Blizzards eigene Zahl (Spieler: GetAverageItemLevel, angelegt;
-- sonst C_PaperDollInfo.GetInspectItemLevel), sonst das Mittel über Core.EquipSlots.COUNTED. Im Ausweichweg zählt
-- ein Zweihänder auch für die leere Schildhand (wie Blizzards Durchschnitt). → Stufe (gerundet), "blizzard" | "mean";
-- nil ohne ein einziges lesbares Stück.
function ST.AverageLevel(unit)
    unit = unit or "player"
    if Core.IsSecret(unit) or type(unit) ~= "string" then return nil end
    local blizzard
    if unit == "player" then
        local _, equipped = Core.Call(rawget(_G, "GetAverageItemLevel"))
        blizzard = Core.Num(equipped)
    else
        local api = rawget(_G, "C_PaperDollInfo")
        blizzard = type(api) == "table" and Core.Num(Core.Call(api.GetInspectItemLevel, unit)) or nil
    end
    if blizzard and blizzard > 0 then return math.floor(blizzard + 0.5), "blizzard" end
    local slots = Core.EquipSlots
    local sum, n = 0, 0
    local mainLevel, mainIsTwoHand, offhand = nil, false, false
    for _, slot in ipairs(slots.COUNTED) do
        local level, _, link = ST.EquippedLevel(unit, slot)
        if level then
            sum, n = sum + level, n + 1
            if slot == slots.SLOT.MAINHAND then
                mainLevel = level
                mainIsTwoHand = slots.IsTwoHand(link)
            elseif slot == slots.SLOT.OFFHAND then
                offhand = true
            end
        end
    end
    if mainIsTwoHand and not offhand then sum, n = sum + mainLevel, n + 1 end
    if n == 0 then return nil end
    return math.floor(sum / n + 0.5), "mean"
end

-- Gemeinsame Schalter „Itemlevel auf Ausrüstung“ und „BoE auf Ausrüstung“ für Taschenplätze (ezBag) und Beutefenster
-- (ezLoot) – Einstellungs-Prüfung 19.11.2026, Nr. 95/96: vorher zwei gleich benannte Schalter je Modul. Beide Module lesen
-- Core.SharedOn("itemMarks", "itemLevel" | "boe") und reichen den Wert als opts.itemLevel / opts.bind an ST.Marks; ihre
-- alten Werte übernehmen sie einmal (Core.AdoptShared, Art "first").
Core.OwnDefaults("itemMarks", { itemLevel = true, boe = true })

function ST.Marks(link, opts)
    opts = opts or {}
    if Core.IsSecret(link) or (type(link) ~= "string" and type(link) ~= "number") or link == "" then return nil, false end
    local knowledge = Core.Knowledge
    local facts = knowledge and knowledge.Get and knowledge.Get(link)
    if type(facts) ~= "table" or not facts.isEquipment then return nil, false end
    local marks = { quality = Core.Num(facts.quality) }
    if opts.itemLevel ~= false then marks.ilvl = ST.ItemLevel(type(link) == "string" and link or nil, facts, opts.bag, opts.slot) end
    if opts.bind ~= false then
        local boe
        if opts.bound ~= nil then
            boe = opts.bound == false and (marks.quality or 0) >= 2 and Core.Num(facts.bindType) == BIND_ON_EQUIP
        else
            boe = Core.Num(facts.bindType) == BIND_ON_EQUIP
        end
        if boe then marks.bind = L.BIND_BOE end
    end
    if not (marks.ilvl or marks.bind) then return nil, true end
    return marks, true
end

-- Qualitätsfarbe: eine Stelle in Format.lua (Core.QualityRGB); hier nur der frühere Name.
function ST.QualityRGB(quality) return Core.QualityRGB(quality) end

local overlays = setmetatable({}, { __mode = "k" })

local function Overlay(button)
    local o = overlays[button]
    if o then return o end
    o = {}
    o.ilvl = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    o.ilvl:SetDrawLayer("OVERLAY", 7)
    o.ilvl:SetPoint("TOPRIGHT", -2, -3)
    o.bind = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    o.bind:SetDrawLayer("OVERLAY", 7)
    o.bind:SetPoint("BOTTOMLEFT", 3, 3)
    o.bind:SetTextColor(Core.QualityRGB(BIND_COLOR_QUALITY))   -- Grün der Qualität „Ungewöhnlich“ (vorher 0.12, 1, 0 von Hand)
    overlays[button] = o
    return o
end

function ST.Apply(button, marks)
    if type(button) ~= "table" or not button.CreateFontString then return end
    local o = overlays[button]
    if not marks and not o then return end
    o = o or Overlay(button)
    marks = marks or {}
    o.ilvl:SetText(marks.ilvl and tostring(marks.ilvl) or "")
    if marks.ilvl then o.ilvl:SetTextColor(ST.QualityRGB(marks.quality)) end
    o.bind:SetText(marks.bind or "")
end

-- Die FontStrings eines Knopfs (oder nil), z. B. für Tests.
function ST.Overlay(button) return overlays[button] end
