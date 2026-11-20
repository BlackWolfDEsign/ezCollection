local _, ns = ...
local L = ns.L

--[[
    Munition (Titan Ammo): Pfeile/Kugeln bzw. Wurfwaffen, Warnung bei wenig
    Vorrat und bei falscher Munition für die Fernkampfwaffe.
    Verbesserungen: kein Fehler ohne angelegte Munition, nicht geladene
    Gegenstände werden nachgeladen, Warnung wenn der Vorrat zur Neige geht,
    Köcher/Munitionsbeutel im Tooltip. Ohne Fernkampfwaffe mit Munition blendet
    sich der Baustein aus (Zauberstäbe, Klassen ohne Munition).
]]

local block = ns.RegisterBlock({
    id = "ammo",
    command = "munition",
    name = L.AMMO_NAME,
    label = L.AMMO_LABEL,
    icon = "Interface\\Icons\\INV_Ammo_Arrow_02",
    events = { "UNIT_INVENTORY_CHANGED", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "GET_ITEM_INFO_RECEIVED" },
    colorable = true,
    defaults = {
        enabled = false, zone = "left", order = 45,
        showName = false,
        warn = 200,
        warnThrown = 30,
        alert = true,
    },
})

local RANGED = INVSLOT_RANGED or 18

local function AmmoSlot()
    if INVSLOT_AMMO then return INVSLOT_AMMO end
    local ok, slot = pcall(GetInventorySlotInfo, "AMMOSLOT")
    return ok and slot or 0
end

local WEAPON, PROJECTILE = 2, 6
local BOW, GUN, CROSSBOW, THROWN = 2, 3, 18, 16     -- Zauberstäbe (19) brauchen keine Munition
local ARROW, BULLET = 2, 3

-- Art und Unterart eines Gegenstands aus ezCore (Core.ItemClass, V-177; gesperrt oder unbekannt: nil).
local function ItemClass(id)
    if not id then return nil end
    local classID, subclassID = ezCore.ItemClass(id)
    return classID, subclassID
end

local function ItemName(id)
    if not id then return nil end
    return ezCore.ItemNameByID(id) or ("item:" .. id)   -- fehlende Daten fordert ezCore an
end

-- Liefert: Art ("ammo"|"thrown"), Anzahl, Munitions-ID, Waffen-ID, falsche Munition?
local function Read()
    local weapon = GetInventoryItemID("player", RANGED)
    if not weapon then return nil end
    local class, sub = ItemClass(weapon)
    if class ~= WEAPON then return nil end
    if sub == THROWN then
        local count = GetInventoryItemCount("player", RANGED) or 0
        return "thrown", count, weapon, weapon, false
    end
    if sub ~= BOW and sub ~= GUN and sub ~= CROSSBOW then return nil end
    local slot = AmmoSlot()
    local ammo = GetInventoryItemID("player", slot)
    local count = ammo and (GetInventoryItemCount("player", slot) or 0) or 0
    local wrong = false
    if ammo then
        local aClass, aSub = ItemClass(ammo)
        if aClass == PROJECTILE then
            wrong = (sub == GUN and aSub == ARROW) or ((sub == BOW or sub == CROSSBOW) and aSub == BULLET)
        end
    end
    return "ammo", count, ammo, weapon, wrong
end

local function Limit(kind)
    return kind == "thrown" and block.cfg.warnThrown or block.cfg.warn
end

-- Einmal warnen, wenn der Vorrat unter die Grenze fällt.
local warned = false
local function CheckAlert(kind, count)
    if not block.cfg.alert then return end
    local limit = Limit(kind)
    if count < limit and count > 0 then
        if not warned then
            warned = true
            local msg = L.AMMO_LOW:format(count)
            ezCore.ErrorMessage(msg, "warn")   -- Rolle statt Farbzahlen (T18-23)
            ns.Print(msg)
        end
    elseif count >= limit then
        warned = false
    end
end

-- Warnung „Munition knapp“ auch bei verborgener Leiste (ns.QueueUpdate ruft Alert statt GetText).
function block:Alert()
    local kind, count, ammo, _, wrong = Read()
    if not kind or wrong or (kind == "ammo" and not ammo) then return end
    CheckAlert(kind, count)
end

function block:GetText()
    local kind, count, ammo, _, wrong = Read()
    if not kind then return nil end
    if wrong then return ns.RED .. L.AMMO_WRONG .. "|r", self.icon end
    if kind == "ammo" and not ammo then return ns.RED .. L.AMMO_NONE .. "|r" end
    CheckAlert(kind, count)
    local limit = Limit(kind)
    local color = count < limit and ns.RED or count < limit * 2 and ns.OrangeCode() or ns.WHITE
    local text = color .. ns.Number(count) .. "|r"
    if self.cfg.showName and ammo then text = text .. " " .. ItemName(ammo) end
    local icon = ammo and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(ammo)
    return text, icon
end

-- Für den Baustein „Meldungen“.
function block:Warnings()
    local kind, count, ammo, _, wrong = Read()
    if not kind then return nil end
    if wrong then return { L.AMMO_WRONG } end
    if kind == "ammo" and not ammo then return { L.AMMO_NONE } end
    if count < Limit(kind) then return { L.AMMO_LOW:format(count) } end
    return nil
end

-- Köcher und Munitionsbeutel: die normalen Taschenplätze aus ezCores Taschenliste (Core.BagList("bags") ohne den
-- Rucksack 0, der nie eine Taschenart hat; V-175, EC-50). Gesperrte Antworten gelten als „keine Spezialtasche“.
local function Pouches()
    local list = {}
    for _, bag in ipairs(ezCore.BagList("bags")) do
        local free, family = C_Container.GetContainerNumFreeSlots(bag)
        free, family = ns.Num(free), ns.Num(family)
        local total = ns.Num(C_Container.GetContainerNumSlots(bag)) or 0
        if bag ~= 0 and family and family ~= 0 and total > 0 then
            local invID = C_Container.ContainerIDToInventoryID and C_Container.ContainerIDToInventoryID(bag)
            local id = invID and GetInventoryItemID("player", invID)
            local class = id and ItemClass(id)
            if class == 11 then
                list[#list + 1] = { name = ItemName(id), free = free or 0, total = total }
            end
        end
    end
    return list
end

function block:OnTooltip(tooltip)
    local kind, count, ammo, weapon, wrong = Read()
    if not kind then
        ns.TipLine(tooltip, L.AMMO_NO_WEAPON, "highlight", true)
        return
    end
    ns.TipDoubleLine(tooltip, L.AMMO_WEAPON, ItemName(weapon), "normal", "highlight")
    if kind == "ammo" then
        ns.TipDoubleLine(tooltip, L.AMMO_AMMO, ammo and ItemName(ammo) or (ns.RED .. L.AMMO_NONE .. "|r"), "normal", "highlight")
    end
    ns.TipDoubleLine(tooltip, L.AMMO_COUNT, ns.Number(count), "normal", "highlight")
    if wrong then ns.TipLine(tooltip, L.AMMO_WRONG_TIP, "bad", true) end
    local pouches = Pouches()
    if #pouches > 0 then
        tooltip:AddLine(" ")
        for _, p in ipairs(pouches) do
            ns.TipDoubleLine(tooltip, p.name, L.FREE_OF:format(p.free, p.total), "normal", "highlight")
        end
    end
    tooltip:AddLine(" ")
    ns.TipDoubleLine(tooltip, L.AMMO_WARN_AT, ns.Number(Limit(kind)), "hint", "hint")
end

function block:OnMenu(root)
    local cfg = self.cfg
    ns.MenuCheck(root, L.AMMO_SHOW_NAME, cfg, "showName", self)
    ns.MenuCheck(root, L.AMMO_ALERT, cfg, "alert", self)
    local warn = root:CreateButton(L.AMMO_WARN_AMMO)
    for _, n in ipairs({ 100, 200, 400, 600, 1000 }) do ns.MenuRadio(warn, ns.Number(n), cfg, "warn", n, self) end
    local thrown = root:CreateButton(L.AMMO_WARN_THROWN)
    for _, n in ipairs({ 10, 20, 30, 50, 100 }) do ns.MenuRadio(thrown, ns.Number(n), cfg, "warnThrown", n, self) end
end
