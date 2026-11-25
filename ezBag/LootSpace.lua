local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Vorschlag am Plündernfenster bei voller Tasche (Auftrag des Nutzers vom 24.11.2026, wörtlich: „"Tasche voll" -> noch
    lootbarer gegenstand z.b. von mob, zeige billigsten gegenstand aus tasche wenn loot mehr wert ist“).
    Liegt im offenen Plündernfenster ein Gegenstand, der nicht mehr in die Taschen passt, und ist er mehr wert als der
    billigste Gegenstand darin, steht unter Blizzards Fenster ein Knopf mit diesem Gegenstand und seinen Preisen. Klick
    fragt „zerstören?“ (Space.Ask, wie „Platz schaffen“), Rechtsklick öffnet dieselbe Liste. Ohne „Ja“ geschieht nichts.

    Händler gegen Auktion (Spieltest vom 24.11.2026, wörtlich: „ist nicht der billigste verkaufpreis aus der tasche -->
    zeige ggf. verkaufspreis vs ah an“): Am Knopf stehen beide Preise. Zuerst der Gegenstand mit dem kleinsten
    Händlerpreis (unter dem der Beute); ist ein anderer billiger, sobald der höhere der beiden Preise zählt, steht er als
    zweiter Knopf darunter (LS.Offers). Bringt der erste im Auktionshaus mehr als der sichere Wert der Beute, steht sein
    Auktionspreis orange und der Tooltip sagt es. „≈“: unsicherer Auktionspreis (Space.Worth).
    Warum überhaupt tauschen (Spieltest vom 24.11.2026, wörtlich: „bild 2 wieso solte ich den billigeren bolzen mit fläschen
    öl tauschen?“; Bolzen beim Händler 12 gegen 25 Kupfer, im Auktionshaus 1 S 23 gegen 24 Kupfer, am Knopf standen nur
    die Preise des Öls): „Weg:“ und „Dafür:“ nennen beide Gegenstände mit ihren Preisen. Spricht nur eine der beiden Arten
    dafür, sagt es die erste Zeile („Tausch lohnt nur im Auktionshaus:“ bzw. „… nur beim Händler:“, offer.only), der
    Tooltip und die Rückfrage.
    Nachplündern (ebd.: „mit ja wird zerstört aber icht automatisch die tasche erneut gelootet“): Nach jedem Zerstören
    über ezBag (Space.Remove) bei offenem Plündernfenster holt LS.LootAgain die Beute, um die es ging, sobald der Platz
    frei ist (BAG_UPDATE_DELAYED) – mit Blizzards „Automatisch plündern“ (so, wie das Spiel es für dieses Plündern meldet)
    auch alles andere, was dann passt. Immer nur ein Griff: der nächste erst, wenn der letzte aus dem Fenster ist (sonst
    nähme anderes den Platz ein, während Blizzard nach der Bindung fragt); jeder Platz nur einmal, je Griff höchstens
    LS.AGAIN Sekunden.

    Vorgeschlagen wird nur, was auch „Platz schaffen“ vorschlägt (Space.Candidates: Plunder und einfache weiße
    Gegenstände, nie Quest, Set, Zugewiesenes, Material der Einkaufsliste oder was ezGear besser bewertet) und dessen
    Platz die Beute aufnimmt
    (Transfer.BagAccepts: ein Platz im Köcher hilft einem Schwert nicht).
    Wert (Space.Worth): Händler- und Auktionspreis des ganzen Stapels. Bei der Beute zählt der Auktionspreis nur, wenn er
    sicher ist (Core.Prices.AuctionWorth: deutlich mehr als der Händler, oft genug gesehen), beim Vorschlag jeder bekannte –
    lieber einmal nichts vorschlagen als Wertvolles. Quest-Gegenstände (auch solche, die eine Quest beginnen) und Seltenes
    (Qualität ab 3) gelten immer als mehr wert. Ist der Wert der Beute noch nicht geladen, gibt es noch keinen Vorschlag.
    Einzigartiges, das du schon hast, zählt nicht – das Spiel lehnte es auch mit Platz ab.
    „Ja“ zerstört nur, solange genau diese Beute noch daliegt und nicht passt; schließt das Plündernfenster, geht auch die
    Rückfrage zu (LS.Needed, Space.CloseAsk).

    Nur ein eigener Knopf als Kind von Blizzards LootFrame (wandert mit, schließt mit ihm); nichts Geschütztes.
]]

local LS = {}
ns.LootSpace = LS

LS.ALWAYS = math.huge     -- Quest-Gegenstand oder Seltenes: mehr wert als jeder Vorschlag
LS.RARE = 3               -- ab dieser Qualität
LS.LINE = 13
LS.HEIGHT = 74            -- fünf Zeilen: Anlass, „Weg:“ mit Preisen, „Dafür:“ mit Preisen
LS.GAP = 2                -- unter dem Fenster und zwischen zwei Knöpfen
LS.TIP_LIST = 5           -- so viele Gegenstände zum Vergleich im Tooltip
LS.AGAIN = 3              -- Sekunden, in denen nach dem Zerstören nachgeplündert wird
LS.ASK = "loot"           -- Name der eigenen Rückfrage (Space.Ask, Space.CloseAsk)
LS.KEY_CLASS = 13         -- Gegenstandsklasse Schlüssel (Enum.ItemClass.Key): passt auch in den Schlüsselbund
LS.waiting = {}           -- [itemID] = true: Daten fehlen noch, GET_ITEM_INFO_RECEIVED zeichnet neu

local buttons, current, again = {}, {}, nil
local autoLoot            -- plündert das Spiel gerade automatisch? (aus LOOT_READY bzw. LOOT_OPENED; nil = unbekannt)

---------------------------------------------------------------------------
-- Wert und Platz
---------------------------------------------------------------------------

-- Bindungsart laut Client (14. Rückgabe von GetItemInfo: 1 beim Aufheben, 4 Quest) → true, wenn Beute damit gebunden ist
local function BindsOnPickup(link)
    local info = { Core.Call(C_Item and C_Item.GetItemInfo or rawget(_G, "GetItemInfo"), link) }
    local bind = Core.Num(info[14])
    return bind == 1 or bind == 4
end

-- Händlerwert noch unbekannt: gemerkt, GET_ITEM_INFO_RECEIVED zeichnet neu
local function Await(link)
    local id = Core.ItemID(link)
    if id then LS.waiting[id] = true end
end

-- Einzigartig und schon im Besitz (Taschen und Bank)? Dann nützt ein freier Platz nichts. „Einzigartig (n)“ zählt
-- vorsichtshalber schon ab dem ersten Stück: dann gibt es keinen Vorschlag.
function LS.OwnedUnique(itemID, link)
    if Core.ItemCount(itemID, true) < 1 then return false end
    local K = Core.Knowledge
    local facts = K and Core.Call(K.Get, link)
    for _, key in ipairs(type(facts) == "table" and type(facts.specialKeys) == "table" and facts.specialKeys or {}) do
        if key == "unique" then return true end
    end
    return false
end

-- Schlüssel passen auch in den Schlüsselbund, wenn der Client einen mit Plätzen führt
local function KeyringFree(itemID)
    local bag = Enum and Enum.BagIndex and Core.Num(Enum.BagIndex.Keyring)
    if not bag or Core.ItemClass(itemID) ~= LS.KEY_CLASS then return false end
    local size = Core.Num(Core.Call(C_Container.GetContainerNumSlots, bag)) or 0
    return size > 0 and (Core.Num((Core.Call(C_Container.GetContainerNumFreeSlots, bag))) or 0) > 0
end

-- Passt die Menge noch in eine Tasche (freier Platz, der sie aufnimmt, oder Platz auf angebrochenen Stapeln)?
-- Ohne Stapelgröße (Daten noch nicht geladen) gilt: passt – dann gibt es noch keinen Vorschlag.
function LS.Fits(itemID, count)
    local room = 0
    local max, known = Core.MaxStack(itemID, 1)
    if not known then
        LS.waiting[itemID] = true
        return true
    end
    if KeyringFree(itemID) then return true end
    for _, bag in ipairs(ns.Transfer.BagIDs()) do
        local size = Core.Num(C_Container.GetContainerNumSlots(bag)) or 0
        if size > 0 then
            local free = Core.Num((C_Container.GetContainerNumFreeSlots(bag))) or 0
            if free > 0 and ns.Transfer.BagAccepts(bag, itemID) then return true end
            if max > 1 then
                for slot = 1, size do
                    local info = C_Container.GetContainerItemInfo(bag, slot)
                    if ns.ItemIDOf(info) == itemID then room = room + math.max(0, max - (Core.Num(info.stackCount) or 1)) end
                end
            end
        end
    end
    return room >= (Core.Num(count) or 1)
end

-- Gegenstände im Plündernfenster, die nicht gesperrt sind (kein Gold, keine Währung)
-- → { { slot, itemID, link, count, quality, quest } … } in Blizzards Reihenfolge
local function Slots()
    local out = {}
    local itemType = Enum and Enum.LootSlotType and Enum.LootSlotType.Item or 1
    for slot = 1, Core.Num(Core.Call(rawget(_G, "GetNumLootItems"))) or 0 do
        local kind = Core.Num(Core.Call(rawget(_G, "GetLootSlotType"), slot))
        local link = Core.Plain(Core.Call(rawget(_G, "GetLootSlotLink"), slot))
        local itemID = type(link) == "string" and Core.ItemID(link) or nil
        if (kind == nil or kind == itemType) and itemID then
            local _, _, quantity, _, quality, locked, isQuest, questID = Core.Call(rawget(_G, "GetLootSlotInfo"), slot)
            if Core.Plain(locked) ~= true then
                out[#out + 1] = { slot = slot, itemID = itemID, link = link, count = Core.Num(quantity) or 1,
                    quality = Core.Num(quality) or 1,
                    quest = Core.Plain(isQuest) == true or (Core.Num(questID) or 0) > 0 }
            end
        end
    end
    return out
end

-- Davon die, die nicht passen, die wertvollste zuerst; dazu vendor, auction, sure (Space.Worth), value (Händler oder
-- sichere Auktion), rank und vendorRank (zum Vergleichen: LS.ALWAYS bei Quest-Gegenstand und Seltenem), rare
function LS.Loot()
    local out = {}
    for _, e in ipairs(Slots()) do
        if not LS.Fits(e.itemID, e.count) and not LS.OwnedUnique(e.itemID, e.link) then
            e.rare = e.quality >= LS.RARE
            e.vendor, e.auction, e.sure, e.seen = ns.Space.Worth(e.link, e.count, BindsOnPickup(e.link))
            if e.vendor then e.value = math.max(e.vendor, e.sure and e.auction or 0) else Await(e.link) end
            local always = (e.quest or e.rare) and LS.ALWAYS or nil
            e.rank, e.vendorRank = always or e.value, always or e.vendor
            if e.rank then out[#out + 1] = e end
        end
    end
    table.sort(out, function(a, b)
        if a.rank ~= b.rank then return a.rank > b.rank end
        return a.slot < b.slot
    end)
    return out
end

-- Was „Platz schaffen“ vorschlägt, mit beiden Preisen, beim Händler billigste zuerst
-- → { { item, vendor, auction, sure, seen, value (der höhere der beiden) } … }; ein unbekannter Händlerwert fehlt
function LS.Items()
    local out = {}
    for i, c in ipairs(ns.Space.Candidates()) do
        local vendor, auction, sure, seen = ns.Space.PricesOf(c)
        if vendor then
            out[#out + 1] = { item = c, vendor = vendor, auction = auction, sure = sure, seen = seen,
                value = math.max(vendor, auction or 0), at = i }
        else
            Await(c.link or c.itemID)
        end
    end
    table.sort(out, function(a, b)
        if a.vendor ~= b.vendor then return a.vendor < b.vendor end
        if a.value ~= b.value then return a.value < b.value end
        return a.at < b.at
    end)
    return out
end

-- Davon, was dieser Beute hilft: nicht derselbe Gegenstand, und sein Platz nimmt sie auf
local function Helps(items, loot)
    local out = {}
    for _, e in ipairs(items) do
        if e.item.itemID ~= loot.itemID and ns.Transfer.BagAccepts(e.item.bag, loot.itemID) then out[#out + 1] = e end
    end
    return out
end

-- Ist e (aus LS.Items) für diese Art des Vorschlags weniger wert als die Beute? „both“: bei beiden Arten
local function Less(kind, e, loot)
    local byVendor = e.vendor < (loot.vendorRank or 0)
    local byValue = e.value < loot.rank
    if kind == "vendor" then return byVendor end
    if kind == "value" then return byValue end
    return byVendor and byValue
end

-- Spricht nur eine der beiden Arten für den Tausch? → "vendor" (nur beim Händler), "value" (nur im Auktionshaus) | nil.
-- Ein unsicherer Auktionspreis der Beute über dem Vorschlag macht „nur beim Händler“ ungewiss: dann nil (Review).
local function Only(e, loot)
    local byVendor, byValue = Less("vendor", e, loot), Less("value", e, loot)
    if byVendor == byValue then return nil end
    if byVendor and loot.auction and not loot.sure and loot.auction > e.value then return nil end
    return byVendor and "vendor" or "value"
end

-- Vorschläge für die wertvollste Beute, für die ein Platz hilft: „vendor“ = kleinster Händlerpreis, „value“ = kleinster
-- Wert, wenn der höhere der beiden Preise zählt; derselbe Gegenstand: ein Vorschlag „both“. Nur, was weniger wert ist als
-- die Beute. → { { kind, loot, item, vendor, auction, sure, seen, value, warn, only } … } (leer = nichts); warn: im
-- Auktionshaus mehr wert als der sichere Wert der Beute (bei einem Quest-Gegenstand und ohne ihren Wert nie); only: nur
-- diese Art spricht für den Tausch (Only)
function LS.Offers()
    local loots = LS.Loot()
    if #loots == 0 then return {} end
    local items = LS.Items()
    for _, loot in ipairs(loots) do
        local vendor, value
        for _, e in ipairs(Helps(items, loot)) do
            if not vendor and Less("vendor", e, loot) then vendor = e end
            if Less("value", e, loot) and (not value or e.value < value.value) then value = e end
        end
        local out = {}
        local function Add(kind, e)
            out[#out + 1] = { kind = kind, loot = loot, item = e.item, vendor = e.vendor, auction = e.auction, sure = e.sure,
                seen = e.seen, value = e.value, only = Only(e, loot),
                warn = not loot.quest and loot.value ~= nil and e.auction ~= nil and e.auction > e.vendor
                    and e.auction >= loot.value }
        end
        -- gleich viel wert bei beiden Arten: ein Knopf genügt
        if vendor and value and (vendor == value or vendor.value <= value.value) then
            Add("both", vendor)
        else
            if vendor then Add("vendor", vendor) end
            if value then Add("value", value) end
        end
        if #out > 0 then return out end
    end
    return {}
end

-- Der erste Vorschlag; mit kind nur einer dieser Art, ersatzweise „both“ (dann gilt er für beide Arten). → Vorschlag
-- oder nil, irgendeiner da?
function LS.Offer(kind)
    local offers = LS.Offers()
    if kind == nil then return offers[1], #offers > 0 end
    for _, o in ipairs(offers) do
        if o.kind == kind or o.kind == "both" then return o, true end
    end
    return nil, #offers > 0
end

-- Gilt der Vorschlag noch (beim „Ja“ der Rückfrage): das Plündernfenster ist offen und dieselbe Beute liegt noch darin,
-- passt weiter nicht und ist weiter mehr wert?
function LS.Needed(offer)
    if not (LootFrame and LootFrame:IsShown()) then return false end
    for _, loot in ipairs(LS.Loot()) do
        if loot.itemID == offer.loot.itemID and Less(offer.kind, offer, loot) then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Nachplündern, sobald der Platz frei ist
---------------------------------------------------------------------------

-- Nach dem Zerstören (Space.Remove): merken, was danach zu holen ist. loot = die Beute der Rückfrage; ohne sie (Liste,
-- „Platz schaffen“) die des gezeigten Vorschlags. → true, wenn nachgeplündert wird
function LS.Freed(loot)
    again = nil
    if not (LootFrame and LootFrame:IsShown() and ns.Enabled("lootSpace")) then return false end
    loot = loot or (current[1] and current[1].loot)
    local auto = autoLoot
    if auto == nil then auto = Core.CVar("autoLootDefault") == "1" end
    if not (loot or auto) then return false end
    again = { itemID = loot and loot.itemID or nil, auto = auto, at = Core.Uptime(), tried = {} }
    return true
end

local function Key(slot, itemID) return slot .. ":" .. itemID end

-- Ein Taschenereignis: den nächsten Platz holen, der jetzt passt – zuerst die Beute, um die es ging. Liegt der letzte
-- Griff noch im Fenster, wird gewartet. → Platz oder nil
function LS.LootAgain()
    local a = again
    if not a then return nil end
    local loot = rawget(_G, "LootSlot")
    if type(loot) ~= "function" or not (LootFrame and LootFrame:IsShown()) or not ns.Enabled("lootSpace")
        or Core.Uptime() - a.at > LS.AGAIN then
        again = nil
        return nil
    end
    local slots, pick = Slots(), nil
    for _, e in ipairs(slots) do
        if a.pending == Key(e.slot, e.itemID) then return nil end    -- noch unterwegs, oder Blizzard fragt nach der Bindung
    end
    a.pending = nil
    for _, e in ipairs(slots) do
        local mine = e.itemID == a.itemID
        if not a.tried[Key(e.slot, e.itemID)] and (mine or (a.auto and not pick)) and LS.Fits(e.itemID, e.count)
            and not LS.OwnedUnique(e.itemID, e.link) then
            pick = e
            if mine then break end
        end
    end
    if not pick then return nil end
    local key = Key(pick.slot, pick.itemID)
    a.tried[key], a.pending, a.at = true, key, Core.Uptime()
    loot(pick.slot)
    return pick.slot
end

---------------------------------------------------------------------------
-- Knopf unter Blizzards Plündernfenster
---------------------------------------------------------------------------

local function Named(link, count)
    return tostring(link) .. ((count or 1) > 1 and (" x" .. count) or "")
end

-- Beute mit ihrem Wert: Quest-Gegenstand, „selten oder besser“ (dazu die Preise, wenn sie bekannt sind) oder die Preise
local function LootText(loot)
    if loot.quest then return L.LOOT_SPACE_QUEST end
    local prices = loot.vendor and ns.Space.PriceText(loot.vendor, loot.auction, loot.sure) or nil
    if loot.rare then return prices and (L.LOOT_SPACE_RARE .. ", " .. prices) or L.LOOT_SPACE_RARE end
    return prices or L.SPACE_NO_VALUE
end

-- Gegenstand mit Symbol, Name und Menge
local function IconName(itemID, link, count)
    return Named(Core.ItemIconText(itemID, ns.Space.PlainLink(link) or tostring(link)), count)
end

-- Texte des Knopfs: Anlass, „Weg:“ Gegenstand, seine beiden Preise, „Dafür:“ Beute, ihre Preise (bei Seltenem und
-- Quest-Gegenständen steht der Grund, warum sie immer mehr gilt, im Tooltip bzw. statt der Preise)
function LS.Text(offer)
    local item, loot = offer.item, offer.loot
    local head = offer.only and L["LOOT_SPACE_BUTTON_" .. offer.only .. "_only"] or L["LOOT_SPACE_BUTTON_" .. offer.kind]
    local lootPrice = not loot.quest and loot.vendor and ns.Space.PriceText(loot.vendor, loot.auction, loot.sure) or LootText(loot)
    return head, L.LOOT_SPACE_BUTTON_OUT:format(IconName(item.itemID, item.link or item.itemID, item.count)),
        ns.Space.PriceText(offer.vendor, offer.auction, offer.sure, offer.warn),
        L.LOOT_SPACE_BUTTON_IN:format(IconName(loot.itemID, loot.link, loot.count)), lootPrice
end

-- Zusatz der Rückfrage: was dafür kommt, und ob sich der Tausch nur auf eine Art lohnt
function LS.AskNote(offer)
    local loot = offer.loot
    local text = L.LOOT_SPACE_BUTTON_IN:format(Named(loot.link, loot.count)) .. "\n" .. LootText(loot)
    return offer.only and (text .. "\n" .. Core.Style.ColorText("orange", L["LOOT_SPACE_ONLY_" .. offer.only])) or text
end

function LS.TipText(offer)
    local loot, item = offer.loot, offer.item
    local lines = {
        L.LOOT_SPACE_LOOT:format(Named(loot.link, loot.count), LootText(loot)),
        L.LOOT_SPACE_ITEM:format(Named(item.link or item.itemID, item.count),
            ns.Space.PriceText(offer.vendor, offer.auction, offer.sure, offer.warn)),
        L["LOOT_SPACE_WHY_" .. offer.kind],
    }
    if offer.only then lines[#lines + 1] = Core.Style.ColorText("orange", L["LOOT_SPACE_ONLY_" .. offer.only]) end
    -- „nur beim Händler“ sagt dasselbe schon
    if offer.warn and offer.only ~= "vendor" then lines[#lines + 1] = Core.Style.ColorText("orange", L.LOOT_SPACE_AH_MORE) end
    if offer.seen then lines[#lines + 1] = Core.Grey(L.LOOT_SPACE_SEEN:format(Core.Ago(offer.seen, "server"))) end
    -- zum Nachrechnen: die billigsten, die dieser Beute helfen, mit beiden Preisen
    local lootAuction = not loot.quest and loot.auction or nil      -- bei einem Quest-Gegenstand steht kein Preis da
    local items, source = Helps(LS.Items(), loot), lootAuction ~= nil or offer.auction ~= nil
    local unsure = (lootAuction and not loot.sure) or (offer.auction and not offer.sure)
    if #items > 1 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = L.LOOT_SPACE_LIST
        for i = 1, math.min(LS.TIP_LIST, #items) do
            local e = items[i]
            lines[#lines + 1] = Named(e.item.link or e.item.itemID, e.item.count) .. "  "
                .. ns.Space.PriceText(e.vendor, e.auction, e.sure)
            source = source or e.auction ~= nil
            unsure = unsure or (e.auction and not e.sure)
        end
    end
    if source then lines[#lines + 1] = Core.Grey(L.VALUE_AUCTION_SOURCE) end
    local feeNote = ns.Space.FeeNote(source or nil)
    if feeNote then lines[#lines + 1] = Core.Grey(feeNote) end
    if unsure then lines[#lines + 1] = Core.Grey(L.SPACE_PRICE_UNSURE_TIP) end
    lines[#lines + 1] = ""
    lines[#lines + 1] = L.LOOT_SPACE_CLICK
    lines[#lines + 1] = L.SPACE_RIGHT
    return table.concat(lines, "\n")
end

-- Knopf i (1 oder 2), sobald es ihn gibt
function LS.Button(i) return buttons[i or 1] end

local function Create(i)
    local b = buttons[i]
    if b or not LootFrame then return b end
    local ok
    ok, b = pcall(CreateFrame, "Button", nil, LootFrame, "UIPanelButtonTemplate")
    if not ok or not b then return nil end
    buttons[i] = b
    b:SetHeight(LS.HEIGHT)
    -- fünf Zeilen, jede kürzt sich für sich
    local function Line(font, at)
        local y = -5 - (at - 1) * LS.LINE
        local fs = b:CreateFontString(nil, "OVERLAY", font)
        fs:SetPoint("TOPLEFT", 10, y)
        fs:SetPoint("TOPRIGHT", -10, y)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        return fs
    end
    b.head = Line("GameFontNormalSmall", 1)
    b.item = Line("GameFontHighlightSmall", 2)
    b.value = Line("GameFontHighlightSmall", 3)
    b.loot = Line("GameFontHighlightSmall", 4)
    b.lootValue = Line("GameFontHighlightSmall", 5)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self, mouse) ns.Try("LootSpace", LS.Click, self, mouse) end)
    b:SetScript("OnEnter", function(self)
        if self.offer then Core.ShowTip(self, L.LOOT_SPACE_TITLE, LS.TipText(self.offer)) end
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    return b
end

-- Lage: unter dem Plündernfenster, der zweite unter dem ersten; ist dort kein Platz (Beute unter der Maus am unteren
-- Rand), darüber
local function Place(b, i, count)
    local step = LS.HEIGHT + LS.GAP
    local bottom = Core.Num(Core.Call(LootFrame.GetBottom, LootFrame))
    local above = bottom ~= nil and bottom < count * step + LS.GAP
    b:ClearAllPoints()
    if above then
        local y = LS.GAP + (count - i) * step
        b:SetPoint("BOTTOMLEFT", LootFrame, "TOPLEFT", 0, y)
        b:SetPoint("BOTTOMRIGHT", LootFrame, "TOPRIGHT", 0, y)
    else
        local y = -LS.GAP - (i - 1) * step
        b:SetPoint("TOPLEFT", LootFrame, "BOTTOMLEFT", 0, y)
        b:SetPoint("TOPRIGHT", LootFrame, "BOTTOMRIGHT", 0, y)
    end
end

-- Klick: der Vorschlag von jetzt (die Tasche kann sich seit dem Zeichnen geändert haben). Rechtsklick: die Liste.
function LS.Click(owner, mouse)
    if mouse == "RightButton" then return ns.Space.OpenMenu(owner, "lootSpace") end
    local offer, any = LS.Offer(owner.offer and owner.offer.kind)
    if not offer then
        LS.Update()
        ns.Print(any and L.LOOT_SPACE_RENEWED or L.LOOT_SPACE_GONE)
        return nil
    end
    return ns.Space.Ask(offer.item, { tag = LS.ASK, loot = offer.loot, note = LS.AskNote(offer), gone = L.LOOT_SPACE_GONE,
        feeNote = not offer.loot.quest and ns.Space.FeeNote(offer.loot.auction) or nil,
        valid = function() return LS.Needed(offer) end })
end

-- Knöpfe zeigen oder verstecken (ohne Vorschlag geht auch die eigene Rückfrage zu). → true, wenn einer steht
function LS.Update()
    local open = LootFrame and LootFrame:IsShown() == true
    LS.waiting = {}
    current = open and ns.Enabled("lootSpace") and LS.Offers() or {}
    for i = 1, math.max(#buttons, #current) do
        local offer = current[i]
        local b = offer and Create(i) or buttons[i]
        if b then
            b.offer = offer
            if offer then
                local head, item, value, loot, lootValue = LS.Text(offer)
                b.head:SetText(head)
                b.item:SetText(item)
                b.value:SetText(value)
                b.loot:SetText(loot)
                b.lootValue:SetText(lootValue)
                Place(b, i, #current)
            end
            b:SetShown(offer ~= nil)
        end
    end
    if #current == 0 then
        ns.Space.CloseAsk(LS.ASK)
        return false
    end
    return buttons[1] ~= nil
end

local function HideAll()
    for _, b in ipairs(buttons) do
        b.offer = nil
        b:Hide()
    end
end

local UpdateSoon = ns.Throttle(function() ns.Try("LootSpace", LS.Update) end, 0.2)
local function IfOpen() if LootFrame and LootFrame:IsShown() then UpdateSoon() end end

-- Plündert das Spiel dieses Fenster automatisch (mit der Taste dafür umgekehrt)? Beide Ereignisse melden es.
local function NoteAuto(_, auto)
    auto = Core.Plain(auto)
    if type(auto) == "boolean" then autoLoot = auto end
end
ns.On("LOOT_READY", NoteAuto)
ns.On("LOOT_OPENED", NoteAuto)
ns.On("LOOT_OPENED", UpdateSoon)
for _, event in ipairs({ "LOOT_SLOT_CLEARED", "LOOT_SLOT_CHANGED", "BAG_UPDATE_DELAYED" }) do ns.On(event, IfOpen) end
ezCore.Listen("GEAR_SCORES_CHANGED", IfOpen, ADDON)      -- ezGear bewertet neu: Verbesserungen werden nie vorgeschlagen
ns.On("BAG_UPDATE_DELAYED", function() if again then ns.Try("LootSpace", LS.LootAgain) end end)
-- nur, wenn auf genau diesen Gegenstand gewartet wird und der Client ihn kennt (sonst fragte ein nie ladbarer
-- Gegenstand sich selbst immer wieder an)
ns.On("GET_ITEM_INFO_RECEIVED", function(_, itemID, success)
    local id = Core.Num(itemID)
    if id and LS.waiting[id] and Core.Plain(success) ~= false then IfOpen() end
end)
ns.On("LOOT_CLOSED", function()
    current, again, autoLoot = {}, nil, nil
    HideAll()
    ns.Space.CloseAsk(LS.ASK)
end)
ns.OnSettingChanged(function(key) if key == "lootSpace" then UpdateSoon() end end)
