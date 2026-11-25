local ADDON, ns = ...
local L = ns.L

--[[
    Platz schaffen und leichter zerstören.
    - Ist die Tasche fast voll, zeigt die Werkzeugleiste der Tasche den Knopf „Platz schaffen“ mit
      der Zahl freier Plätze. Klick schlägt den billigsten Gegenstand vor (zuerst Plunder) und
      zerstört ihn erst nach Rückfrage; beim Händler wird stattdessen verkauft. Rechtsklick: Liste
      der billigsten Gegenstände zum Auswählen. Dasselbe im Menü der Gruppen „Plunder“ und „Frei“.
      Überall stehen Händler- und Auktionspreis nebeneinander (Nutzer am 24.11.2026: „zeige ggf.
      verkaufspreis vs ah an“; Space.Worth, Space.PriceText – auch für LootSpace.lua).
    - Blizzards Zerstören-Dialog: „LÖSCHEN“ steht schon im Feld (Enter oder „Ja“ genügt), und der
      Gegenstand steht als Link im Text (Tooltip beim Zeigen). Läuft Leatrix Plus mit „Easy item
      destroy“, hält sich ezBag zurück.
    Taint-sicher: nur hooksecurefunc, keine Werte in Blizzards Tabellen; zerstört wird nur nach Klick.
]]

local Space = {}
ns.Space = Space

Space.THRESHOLD = 2      -- ab so wenigen freien Plätzen erscheint der Knopf
local LIST_SIZE = 8

local function CarriedBags() return ns.SellBags() end

local function InSet(bag, slot)
    if not C_Container.GetContainerItemEquipmentSetInfo then return false end
    local ok, inSet = pcall(C_Container.GetContainerItemEquipmentSetInfo, bag, slot)
    return ok and inSet == true
end

-- Dieselbe Regel wie die Gruppe „Quest“: Blizzards Angabe und ezQuests Erkennung (ns.IsQuestSlot, Marks.lua).
local function IsQuest(bag, slot, itemID, link)
    return ns.IsQuestSlot(bag, slot, itemID, link)
end

--[[
    Kandidaten, billigste zuerst:
    1. Plunder (grau oder von dir markiert), aber nichts ab „selten“
    2. sonst einfache weiße Gegenstände mit Händlerwert – keine Quest-Gegenstände, nichts aus
       einem Ausrüstungsset und nichts, was du selbst einer Gruppe zugewiesen hast
    Nie, was eine Einkaufsliste braucht (ns.CraftNeed, Marks.lua), und nie Ausrüstung, die laut ezGear besser ist als das
    Angelegte – jetzt oder sobald gelernt bzw. die Stufe reicht (grüner und gelber Pfeil; Durchsicht 24.11.2026). Lädt
    ezGear noch, fehlt der Link oder scheitert die Frage, bleibt das Teil ebenfalls draußen (zerstört ist zerstört).
    Ausnahme: von dir als Plunder markiert – das hast du entschieden.
]]
local function WorthKeeping(info)
    if ns.db.assign[info.itemID] == "junk" then return false end
    return ezCore.GearProtects(ns, info.itemID, info.hyperlink)
end

function Space.Candidates()
    local list = {}
    if ns.ClearCraftNeeds then ns.ClearCraftNeeds() end   -- die Einkaufsliste frisch lesen (wie beim Plunder-Verkauf)
    -- ezCores Schleife über die Taschen zum Verkaufen (ohne Schlüsselbund), nur belegte Plätze.
    ezCore.ForEachBagItem(function(bag, slot, info)
        if ns.ItemIDOf(info) and not info.isLocked then
            local quality = info.quality or 1
            local junk = ns.IsJunk(info)
            local value = ns.SellValue(info)
            local ok
            if junk then
                ok = quality < 3
            else
                ok = quality <= 1 and value > 0 and not ns.db.assign[info.itemID]
                    and not IsQuest(bag, slot, info.itemID, info.hyperlink) and not InSet(bag, slot)
            end
            -- Material für eine Einkaufsliste nie vorschlagen (CRAFT-14, dieselbe Auskunft wie beim Plunder)
            if ok and ns.CraftNeed(info.itemID) then ok = false end
            if ok and WorthKeeping(info) then ok = false end
            if ok then
                list[#list + 1] = { bag = bag, slot = slot, itemID = info.itemID, link = info.hyperlink,
                    quality = quality, count = info.stackCount or 1, value = value, junk = junk }
            end
        end
    end, CarriedBags())
    table.sort(list, function(a, b)
        if a.junk ~= b.junk then return a.junk end
        if a.value ~= b.value then return a.value < b.value end
        if a.count ~= b.count then return a.count < b.count end
        return a.bag * 1000 + a.slot < b.bag * 1000 + b.slot
    end)
    return list
end

function Space.Free()
    local free = ezCore.BagSpace()
    return free
end

-- Knopf „Platz schaffen“ in der Werkzeugleiste der Tasche zeigen?
function Space.ShouldShow()
    return ns.S ~= nil and ns.S.makeSpace == true and Space.Free() <= Space.THRESHOLD
end

local function AtMerchant()
    return ns.AtMerchant()
end

-- Werte eines Stapels in Kupfer → Händler (0 = unverkäuflich, nil = noch nicht geladen), Auktion (nil = kein Preis
-- bekannt oder gebunden), sicher (true: deutlich mehr als der Händler und an genug Tagen gesehen, Prices.AuctionWorth),
-- zuletzt gesehen (Zeitpunkt, nur beim unsicheren Preis). Auktion ist der Erlös des ganzen Stapels nach Blizzards Anteil, wo
-- er gemessen ist, sonst der volle Preis (Prices.Proceeds; den Hinweis dazu gibt Space.FeeNote).
-- unsicher = der zuletzt gesehene kleinste Preis, gezeigt mit „≈“. noValue: unverkäuflich laut Taschenplatz (hasNoValue)
function Space.Worth(link, count, bound, noValue)
    local vendor = noValue and 0 or ezCore.VendorPrice(link)
    if not vendor then return nil end
    local P, total, sure, seen = ezCore.Prices, nil, false, nil
    count = ezCore.Num(count) or 1
    if not bound and type(P) == "table" then
        local worth = ezCore.Call(P.AuctionWorth, link)
        local price = type(worth) == "table" and ezCore.Num(worth.price) or nil
        sure = price ~= nil
        if not price then
            local info = ezCore.Call(P.Get, link)
            price = type(info) == "table" and (ezCore.Num(info.min) or ezCore.Num(info.market)) or nil
            seen = price and ezCore.Num(info.seen) or nil
        end
        total = price and P.Proceeds(price, count) or nil
    end
    return vendor * count, total, sure, seen
end

-- Werte eines Kandidaten (Space.Candidates) an seinem Platz → wie Space.Worth
function Space.PricesOf(c)
    local info = C_Container.GetContainerItemInfo(c.bag, c.slot)
    info = type(info) == "table" and info or {}
    return Space.Worth(c.link or c.itemID, c.count, ezCore.Plain(info.isBound) == true, ezCore.Plain(info.hasNoValue) == true)
end

-- „Händler 15 K · Auktion 1 S 30 K“, unsicher „Auktion ≈ 1 S 30 K“ (ohne Auktionspreis nur der Händler; warn: orange)
function Space.PriceText(vendor, auction, sure, warn)
    local text = (vendor or 0) > 0 and L.SPACE_PRICE_VENDOR:format(ns.CoinText(vendor)) or L.SPACE_NO_VALUE
    if not auction then return text end
    local other = (sure and L.SPACE_PRICE_AUCTION or L.SPACE_PRICE_AUCTION_UNSURE):format(ns.CoinText(auction))
    return text .. " · " .. (warn and ezCore.Style.ColorText("orange", other) or other)
end

-- Hinweis „Gebühr noch unbekannt …“ zu einem gezeigten Auktionspreis (auction), sonst nil (Entscheidung des Nutzers vom
-- 24.11.2026, „Brutto mit Hinweis (Recommended)“)
function Space.FeeNote(auction)
    return auction and ezCore.Prices.FeeNote() or nil
end

-- Gegenstand mit Menge, seine beiden Preise, der Hinweis zur Gebühr (nil = gemessen oder kein Auktionspreis)
local function Describe(c)
    local _, auction, sure = Space.PricesOf(c)
    local count = c.count > 1 and (" x" .. c.count) or ""
    return (c.link or tostring(c.itemID)) .. count, Space.PriceText(c.value, auction, sure), Space.FeeNote(auction)
end
Space.Describe = Describe

-- Die offene Rückfrage (Space.Ask): Gegenstand, Art („sell“/„destroy“) und Text – damit „Ja“ genau das ausführt,
-- was gefragt wurde, und die Frage „verkaufen?“ beim Schließen des Händlers zugeht (Space.CloseSellAsk).
local asking

-- Ausführen (nach der Rückfrage). mode = "sell" oder "destroy": die Art, nach der gefragt wurde. „sell“ verkauft nur,
-- solange der Händler offen ist – ist er inzwischen zu, wird abgebrochen, nie zerstört (T1-1, Gesamtreview
-- 18.11.2026); zerstört wird nur nach der eigenen Frage „zerstören?“. Ohne mode (Aufruf ohne Rückfrage) gilt der
-- Zustand jetzt. Verkauft und zerstört wird nie im Kampf (T1-2, Risiko 11 in docs/blizzard-regeln.md).
-- Liegt am Platz inzwischen eine andere Menge (z. B. Beute auf denselben Stapel gelegt), wird ebenso abgebrochen:
-- „Ja“ gilt nur für die Menge, nach der gefragt wurde (Gegenprüfung des Pakets P2).
-- loot = Beute, um die es ging (Vorschlag am Plündernfenster): danach holt LootSpace genau sie.
function Space.Remove(c, mode, loot)
    local info = C_Container.GetContainerItemInfo(c.bag, c.slot)
    if not info or info.itemID ~= c.itemID or (c.count and (info.stackCount or 1) ~= c.count) then
        ns.Print(L.SPACE_CHANGED)
        return false
    end
    mode = mode or (AtMerchant() and "sell" or "destroy")
    if mode == "sell" then
        if not AtMerchant() then
            ns.Print(L.SPACE_MERCHANT_GONE)
            return false
        end
        if ns.InCombat() then
            ezCore.CombatNotice(ns, L.SELL_WHAT)   -- ein Satz zur Kampfsperre (T18-1)
            return false
        end
        if CursorHasItem() then ClearCursor() end
        C_Container.UseContainerItem(c.bag, c.slot)
        return true
    end
    if ns.InCombat() then
        ezCore.CombatNotice(ns, L.SPACE_WHAT)
        return false
    end
    if CursorHasItem() then ClearCursor() end
    local item, value, feeNote = Describe(c)   -- vor dem Zerstören gelesen: danach ist der Platz leer
    C_Container.PickupContainerItem(c.bag, c.slot)
    local kind, itemID = GetCursorInfo()
    if kind ~= "item" or itemID ~= c.itemID then
        ClearCursor()
        ns.Print(L.SPACE_CHANGED)
        return false
    end
    DeleteCursorItem()
    ns.Print(L.SPACE_DESTROYED:format(item, value) .. (feeNote and (" " .. feeNote) or ""))
    if ns.LootSpace then ns.LootSpace.Freed(loot) end   -- offenes Plündernfenster: die Beute gleich noch einmal plündern
    return true
end

-- Rückfrage für einen Kandidaten: die Art (beim Händler verkaufen, sonst zerstören) wird hier festgelegt und gilt
-- beim Klick auf „Ja“ unverändert. Liefert die Art.
-- opts (Vorschlag am Plündernfenster, LootSpace.lua): valid = fn() – beim „Ja“ gefragt, gilt der Anlass nicht mehr,
-- geschieht nichts (opts.gone sagt es); tag = Name für Space.CloseAsk; loot = die Beute, um die es geht (Space.Remove);
-- note = weiterer Text unter der Frage (was dafür kommt); feeNote = Hinweis zur Gebühr, wenn dessen Preise ihn brauchen.
function Space.Ask(c, opts)
    opts = opts or {}
    if not c then
        ns.Print(L.SPACE_NONE)
        return
    end
    local item, value, feeNote = Describe(c)
    local mode = AtMerchant() and "sell" or "destroy"
    local prompt = mode == "sell" and L.SPACE_ASK_SELL:format(item, value) or L.SPACE_ASK_DESTROY:format(item, value)
    feeNote = feeNote or opts.feeNote
    if feeNote then prompt = prompt .. "\n" .. ezCore.Grey(feeNote) end
    if opts.note then prompt = prompt .. "\n\n" .. opts.note end
    local entry = { mode = mode, prompt = prompt, tag = opts.tag }
    asking = entry
    entry.dialog = ezCore.Confirm(prompt, function()
        if asking == entry then asking = nil end
        if opts.valid and not opts.valid() then
            if opts.gone then ns.Print(opts.gone) end
            return
        end
        Space.Remove(c, mode, opts.loot)
    end, { onCancel = function() if asking == entry then asking = nil end end })   -- „Nein“, Esc, ersetzt: vergessen
    return mode
end

-- Art der offenen Frage („sell“ oder „destroy“), nil ohne offene Frage (für die Prüfungen: „Nein“ vergisst sie).
function Space.Pending() return asking and asking.mode or nil end

function Space.SuggestCheapest()
    Space.Ask(Space.Candidates()[1])
end

-- Die Zeilen der Liste; der Hinweis zur Gebühr einmal darunter
function Space.AddList(menu, list)
    local note
    for i = 1, math.min(LIST_SIZE, #list) do
        local c = list[i]
        local item, value, feeNote = Describe(c)
        note = note or feeNote
        menu:CreateButton(item .. "  " .. ezCore.Grey(value), function() Space.Ask(c) end)
    end
    if note then menu:CreateTitle(note) end
end

-- Liste der billigsten Gegenstände (Rechtsklick auf den Knopf, Menü der Gruppen „Plunder“ und „Frei“).
function Space.AddMenu(root)
    local list = Space.Candidates()
    local sub = root:CreateButton(L.SPACE_MENU)
    if #list == 0 then
        sub:CreateTitle(L.SPACE_NONE)
        return sub
    end
    sub:CreateTitle(AtMerchant() and L.SPACE_MENU_SELL or L.SPACE_MENU_DESTROY)
    Space.AddList(sub, list)
    return sub
end

-- key = Schalter, der unten im Menü steht (Standard „Platz schaffen“; der Vorschlag am Plündernfenster nennt seinen)
function Space.OpenMenu(owner, key)
    key = key or "makeSpace"
    -- Ohne Menü (MenuUtil fehlt) gleich den billigsten vorschlagen.
    local opened = ezCore.Menu.Open(owner, function(root)
        root:CreateTitle(L.SPACE_TITLE)
        local list = Space.Candidates()
        if #list == 0 then
            root:CreateTitle(L.SPACE_NONE)
            return
        end
        Space.AddList(root, list)
        root:CreateDivider()
        root:CreateCheckbox(L["OPT_" .. key], function() return ns.S[key] end,
            function() ns.SetSetting(key, not ns.S[key]) end)
    end)
    if not opened then Space.SuggestCheapest() end
end

---------------------------------------------------------------------------
-- Leichter zerstören: Blizzards Zerstören-Dialog
---------------------------------------------------------------------------

local DELETE_DIALOGS = { DELETE_ITEM = true, DELETE_QUEST_ITEM = true, DELETE_GOOD_ITEM = true, DELETE_GOOD_QUEST_ITEM = true }
local NEEDS_TYPING = { DELETE_GOOD_ITEM = true, DELETE_GOOD_QUEST_ITEM = true }

-- Name des Addons, das den Zerstören-Dialog schon vereinfacht (Leatrix „Easy item destroy“), sonst nil.
function Space.OtherDestroys()
    return (ns.OtherFor("easyDestroy"))
end

-- Link ohne eckige Klammern: gleiche Breite wie der Name, der Dialog muss nicht neu umbrechen.
function Space.PlainLink(link)
    if type(link) ~= "string" then return nil end
    local plain = link:gsub("|h%[(.-)%]|h", "|h%1|h")
    return plain
end

-- Ersten Fund von name in text (ohne Muster) durch replacement ersetzen.
function Space.ReplacePlain(text, name, replacement)
    if type(text) ~= "string" or type(name) ~= "string" or name == "" then return nil end
    local a, b = text:find(name, 1, true)
    if not a then return nil end
    return text:sub(1, a - 1) .. replacement .. text:sub(b + 1)
end

local function EditBoxOf(dialog)
    if dialog.GetEditBox then return dialog:GetEditBox() end
    return dialog.editBox or dialog.EditBox
end

local function TextOf(dialog)
    if dialog.GetTextFontString then return dialog:GetTextFontString() end
    return dialog.text or dialog.Text
end

function Space.OnDialogShown(which, textArg1)
    if not DELETE_DIALOGS[which] or not (ns.S and ns.S.easyDelete) or Space.OtherDestroys() then return end
    local dialog = StaticPopup_FindVisible and StaticPopup_FindVisible(which)
    if not dialog then return end
    -- Gegenstand als Link (farbig, mit Tooltip beim Zeigen).
    local kind, _, link = GetCursorInfo()
    local fs = TextOf(dialog)
    if kind == "item" and link and fs and fs.GetText then
        local name = type(textArg1) == "string" and textArg1 or ns.ItemName(link)
        local text = Space.ReplacePlain(fs:GetText(), name, Space.PlainLink(link))
        if text then fs:SetText(text) end
    end
    -- „LÖSCHEN“ schon eintragen: Blizzards eigene Prüfung schaltet „Ja“ frei.
    if NEEDS_TYPING[which] and DELETE_ITEM_CONFIRM_STRING then
        local box = EditBoxOf(dialog)
        if box and box:IsShown() then box:SetText(DELETE_ITEM_CONFIRM_STRING) end
    end
end

-- Händler zu, während „<Gegenstand> verkaufen?“ noch offen ist: die Frage schließen (ein Klick auf „Ja“ bräche ohnehin
-- ab, Space.Remove). Geschlossen wird nur, solange genau unsere Frage offen ist – ezCores Rückfrage teilen sich alle
-- Module; das prüft ezCore selbst (Core.CancelConfirm, Gesamtreview 18.11.2026, D1; vorher las ezBag dazu den Text des
-- sichtbaren Dialogs). Liefert true, wenn eine Frage geschlossen wurde.
function Space.CloseSellAsk()
    local entry = asking
    if not entry or entry.mode ~= "sell" then return false end
    asking = nil
    if not ezCore.CancelConfirm(entry.prompt) then return false end
    ns.Print(L.SPACE_MERCHANT_GONE)
    return true
end

-- Offene Frage mit diesem Namen (opts.tag) schließen, weil ihr Anlass weg ist. → true, wenn geschlossen
function Space.CloseAsk(tag)
    local entry = asking
    if not entry or tag == nil or entry.tag ~= tag then return false end
    asking = nil
    return ezCore.CancelConfirm(entry.prompt) == true
end

ns.On("MERCHANT_CLOSED", function() Space.CloseSellAsk() end)

ns.OnReady(function()
    if type(StaticPopup_Show) == "function" then
        hooksecurefunc("StaticPopup_Show", function(which, textArg1)
            local ok, err = pcall(Space.OnDialogShown, which, textArg1)
            if not ok then ns.Error(err, "EasyDelete") end
        end)
    end
end)
