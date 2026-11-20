local _, ns = ...
local L = ns.L

--[[
    Taschen (Titan Bag): freie oder belegte Plätze der normalen Taschen.
    Spezialtaschen (Köcher, Kräuter-, Seelentaschen …) zählen getrennt, weil
    dort nicht jeder Gegenstand hineinpasst. Erkennung über die Taschenart, die
    das Spiel selbst meldet (GetContainerNumFreeSlots).
    Verbesserungen: richtige Farben auch im Modus „frei“, eine Prüfung pro
    Taschen-Update (BAG_UPDATE_DELAYED), Warnung bei vollen Taschen, Plätze der
    anderen Charaktere.
    ezBag: Klick öffnet die (von ezBag gruppierte) Originaltasche; ist ezBag
    da, gibt es seine Einstellungen im Menü und den letzten Bankbesuch im Tooltip.
]]

local block = ns.RegisterBlock({
    id = "bags",
    command = "taschen",
    name = L.BAGS_NAME,
    label = L.BAGS_LABEL,
    icon = "Interface\\Icons\\INV_Misc_Bag_08",
    events = { "BAG_UPDATE_DELAYED", "BAG_CONTAINER_UPDATE", "PLAYER_ENTERING_WORLD" },
    colorable = true,
    defaults = {
        enabled = true, zone = "left", order = 40,
        mode = "free",         -- free | used
        special = false,       -- Spezialtaschen mitzählen
        alert = true,
        alts = true,
    },
    hints = { L.BAGS_HINT_LEFT },
})

-- Getragene Taschen samt Reagenzientasche (ezCore.Inventory.CarriedBags); der Schlüsselbund zählt nicht als Platz.
local function BagRange()
    local keyring = Enum.BagIndex and Enum.BagIndex.Keyring
    local list = {}
    for _, bag in ipairs((ezCore.Inventory.CarriedBags())) do
        if bag ~= keyring then list[#list + 1] = bag end
    end
    return list
end

local function BagName(bag)
    if bag == 0 then return BACKPACK_TOOLTIP or L.BAGS_BACKPACK end
    local name = C_Container.GetBagName and C_Container.GetBagName(bag) or (GetBagName and GetBagName(bag))
    return name or ("#" .. bag)
end

local function Read()
    local data = { free = 0, total = 0, bags = {}, specialFree = 0, specialTotal = 0 }
    for _, bag in ipairs(BagRange()) do
        local total = C_Container.GetContainerNumSlots(bag) or 0
        if total > 0 then
            local free, family = C_Container.GetContainerNumFreeSlots(bag)
            free = free or 0
            local special = family ~= nil and family ~= 0
            table.insert(data.bags, { bag = bag, name = BagName(bag), free = free, total = total, special = special })
            if special then
                data.specialFree, data.specialTotal = data.specialFree + free, data.specialTotal + total
            else
                data.free, data.total = data.free + free, data.total + total
            end
        end
    end
    return data
end

local alerted = false

-- Freie/alle Plätze je Charakter (bagFree, bagTotal) schreibt ezCore beim Erfassen der Taschen.

local function Check(data)
    if not block.cfg.alert then return end
    if data.total > 0 and data.free == 0 then
        if not alerted then
            alerted = true
            ezCore.ErrorMessage(L.BAGS_FULL, "warn")   -- Rolle statt Farbzahlen (T18-23)
        end
    else
        alerted = false
    end
end

function block:GetText()
    local cfg = self.cfg
    local data = Read()
    Check(data)
    local free, total = data.free, data.total
    if cfg.special then
        free, total = free + data.specialFree, total + data.specialTotal
    end
    if total == 0 then return "?" end
    local fraction = free / total
    local color = ns.Gradient(math.min(1, fraction * 3))   -- ab einem Drittel frei grün
    local value = cfg.mode == "used" and (total - free) or free
    return color .. value .. "|r/" .. total
end

-- Warnung „Taschen voll“ auch bei verborgener Leiste (ns.QueueUpdate ruft Alert statt GetText).
function block:Alert()
    Check(Read())
end

-- Für den Baustein „Meldungen“.
function block:Warnings()
    local data = Read()
    if data.total == 0 then return nil end
    if data.free == 0 then return { L.BAGS_FULL } end
    if data.free <= 2 then return { L.ALERT_BAGS_LOW:format(data.free) } end
    return nil
end

-- Plätze anderer Charaktere: frei, gesamt, gesehen aus ezCore.BagSpaceOf (über ns.ezBag.Slots, PANEL-08).
-- nil, wenn ezCore für den Charakter keinen brauchbaren Stand hat (nie erfasst oder „0 von 0“).
local function AltSlots(c, key)
    return ns.ezBag.Slots(c, key)
end

function block:OnTooltip(tooltip)
    local cfg = self.cfg
    local data = Read()
    for _, b in ipairs(data.bags) do
        local name = b.name
        if b.special then name = name .. " " .. ns.Grey(L.BAGS_SPECIAL) end
        ns.TipDoubleLine(tooltip, name, L.FREE_OF:format(b.free, b.total), b.special and "hint" or "highlight", "highlight")
    end
    tooltip:AddLine(" ")
    ns.TipDoubleLine(tooltip, L.BAGS_FREE, ("%d / %d"):format(data.free, data.total), "normal", "highlight")
    if data.specialTotal > 0 then
        ns.TipDoubleLine(tooltip, L.BAGS_SPECIAL_FREE, ("%d / %d"):format(data.specialFree, data.specialTotal), "normal", "highlight")
    end

    if ns.ezBag.Active() then
        local entry = ns.ezBag.Char()
        if entry and entry.bankSeen then
            ns.TipDoubleLine(tooltip, L.BAGS_BANK_SEEN, ns.Ago(entry.bankSeen), "normal", "highlight")
        end
    end

    if cfg.alts then
        local first = true
        for _, e in ipairs(ns.Characters()) do
            -- Nie erfasste Charaktere (etwa aus dem Titan-Import, auch gelöschte) bleiben weg wie in den anderen
            -- Twink-Listen; „unbekannt“ steht nur, wo ezCore einen unbrauchbaren Stand gespeichert hat.
            local free, total, seen = AltSlots(e.c, e.key)
            if not e.isMe and (free or e.c.bagFree ~= nil or e.c.bagTotal ~= nil) then
                if first then
                    tooltip:AddLine(" ")
                    ns.TipLine(tooltip, L.OTHER_CHARS, "normal")
                    first = false
                end
                if free then
                    ns.TipDoubleLine(tooltip, ns.CharName(e.c, e.key), L.FREE_OF:format(free, total) .. ns.AltStand(e.c, seen), "highlight", "highlight")
                else
                    -- Nie „0 / 0 frei“: ohne Stand sagt die Zeile, wie er entsteht.
                    ns.TipDoubleLine(tooltip, ns.CharName(e.c, e.key), L.BAGS_ALT_UNKNOWN, "highlight", "hint")
                end
            end
        end
    end
end

function block:OnClick(button)
    if button ~= "LeftButton" then return end
    ezCore.TogglePanel("bags")
end

function block:OnMenu(root)
    local cfg = self.cfg
    local bar = root:CreateButton(L.MENU_BAR_SHOWS)
    ns.MenuRadio(bar, L.BAGS_MODE_FREE, cfg, "mode", "free", self)
    ns.MenuRadio(bar, L.BAGS_MODE_USED, cfg, "mode", "used", self)
    bar:CreateDivider()
    ns.MenuCheck(bar, L.BAGS_COUNT_SPECIAL, cfg, "special", self)
    ns.MenuCheck(root, L.BAGS_ALERT, cfg, "alert", self)
    ns.MenuCheck(root, L.TIP_SHOW_ALTS, cfg, "alts", self)
    if ns.ezBag.Active() then
        root:CreateDivider()
        root:CreateButton(L.BAGS_EZBAG_SETTINGS, function() ns.ezBag.OpenSettings() end)
    end
end
