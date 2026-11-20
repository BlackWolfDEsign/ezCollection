local ADDON, ns = ...
local L = ns.L
local Core = ezCore
local Data = ns.Data

--[[
    Entzaubern: Wert im Tooltip und Liste der Kandidaten in der Tasche (Wunsch des Nutzers,
    13.11.2026: „enchantrix ist aber mehr als das oder, es fragt ob etwas entzaubert oder zerkleinert werden soll“).

    Daten und Rechnung kommen aus ezCore (Core.Salvage, Tabelle „Zerlegen“ je Art; Preise aus Core.Prices). ezCraft
    zeigt nur an und merkt, was der Spieler nicht vorgeschlagen haben will (ezCraftDB.salvageIgnore[itemID] = true).
    Solange ezCores Tabelle als ungeprüft gilt (unverified), steht ezCores Text „ungeprüft – im Spiel abgleichen“ dabei.

      Tooltip     „Entzaubern: ≈ 3s 20k“, je Material Anteil, Menge und Wert, dazu die Aussage „Entzaubern bringt mehr
                  als der Händler und die Auktion“ (die Preise selbst stehen schon im Tooltip; den Auktionspreis nennt
                  ezCraft nur, wenn ihn kein anderer zeigt – CRAFT-15). Abschnitt „ezCraft.salvage“, Schalter
                  tooltipSalvage. Im Reiter „Entzaubern“ bleibt die Vergleichszeile „Händler … · Auktion …“
      Kandidaten  Sal.Candidates() → Ausrüstung in der Tasche, die sich entzaubern lässt – ohne Ignoriertes und ohne
                  das, was ezGear als besser bewertet. Ansicht „Entzaubern“ am Berufefenster (Panel.lua, Schalter
                  salvageTab; nur, wenn der Charakter entzaubern kann)

      Klick       je Zeile ein Symbol „Entzaubern“: ein Klick entzaubert genau diesen Gegenstand über ezCores sicheren
                  Knopf (Core.SecureButton, Abschnitt „Entzaubern per Klick“ unten; nur außerhalb des Kampfes, CRAFT-09)
      Marke       „lohnt sich zu entzaubern“ am Taschenplatz über ezCores Platzmarken (Schalter salvageMark, CRAFT-10)
      bei dir     zweite Stufe (EC-52): was beim Entzaubern bei dir wirklich herauskam (Sal.Own, ezCores Entdecker-
                  Datenbank Core.Drops.Salvage) – je Material „· bei dir 3×“, dazu „bei dir 5× entzaubert“; NEBEN der
                  Tabelle, die bis zum Abgleich „ungeprüft“ bleibt. Der erwartete Wert rechnet weiter mit der Tabelle

    Sondieren und Mahlen: erst, wenn der Client die Zauber hat (ezCore hält sie unsichtbar).
]]

local Sal = {}
ns.Salvage = Sal

local Plain, Num, Call = Core.Plain, Core.Num, Core.Call
local EMPTY = {}
Sal.MARK_TEXTURE = "Interface\\Icons\\INV_Enchant_Disenchant"   -- Marke am Taschenplatz und Knopf je Zeile

local function Lib()
    local S = Core.Salvage
    return type(S) == "table" and type(S.For) == "function" and S or nil
end

function Sal.Available() return Lib() ~= nil end

-- Kann der gespielte Charakter entzaubern (Zauber gelernt)?
function Sal.CanDisenchant()
    local S = Lib()
    return S ~= nil and type(S.Known) == "function" and Call(S.Known, "disenchant") == true
end

-- Rücksicht (Leitlinie 9): Name eines Addons, das den Entzauber-Wert schon zeigt (ezCores Erkennung), sonst nil.
function Sal.Other()
    local label = ns.OtherFor("salvageValue")     -- Gerüst: Core.WhoHandles, innen gesichert
    return type(label) == "string" and label or nil
end

--[[
    Sal.Info(item) → Angaben oder nil, Grund (ezCores Gründe: "type", "quality", "level", "loading", "missing" …)
      item = itemID oder Link (ein Link zählt mit dem Itemlevel seiner Variante)
      { itemID, kind, spell (Zerlege-Zauber), label („Entzaubern“), known (der Charakter kann es), unverified,
        materials = { { id, name, chance (0–1), min, max, expected, price, value } … häufigstes zuerst },
        value = erwarteter Wert in Kupfer oder nil (kein Material hat einen Preis), complete (jedes Material hat einen),
        vendor = Händlerpreis oder nil, auction = Auktionspreis je Stück oder nil }
]]
function Sal.Info(item)
    local S = Lib()
    if not S or Core.IsSecret(item) or item == nil then return nil, "missing" end
    local result, reason = Call(S.For, item)
    result = Plain(result)
    if type(result) ~= "table" or type(result.materials) ~= "table" then return nil, Plain(reason) end
    local value, detail, detailNoPrice
    if type(S.Value) == "function" then value, detail, detailNoPrice = Call(S.Value, item, 1) end
    value = Num(Plain(value))
    if type(detail) ~= "table" then detail = type(detailNoPrice) == "table" and detailNoPrice or EMPTY end
    local byID = {}
    for _, part in ipairs(type(detail.parts) == "table" and detail.parts or EMPTY) do
        if type(part) == "table" and part.id then byID[part.id] = part end
    end
    local info = { itemID = Num(result.itemID) or Core.ItemID(item), kind = result.kind, spell = Num(result.spell),
        known = result.known == true, unverified = result.unverified == true, materials = {}, value = value, complete = value ~= nil and detail.complete == true }
    info.label = type(S.Label) == "function" and Plain(Call(S.Label, result.kind)) or nil
    if type(info.label) ~= "string" or info.label == "" then info.label = L.SALVAGE_TITLE end
    for _, m in ipairs(result.materials) do
        local id = type(m) == "table" and Num(m.id)
        if id then
            local part = byID[id] or EMPTY
            info.materials[#info.materials + 1] = { id = id, name = Data.ItemName(id), chance = Num(m.chance) or 0,
                min = Num(m.min) or 1, max = Num(m.max) or Num(m.min) or 1, expected = Num(m.expected) or 0,
                price = Num(part.price), value = Num(part.value) }
        end
    end
    if #info.materials == 0 then return nil, "type" end
    info.vendor = type(Core.VendorPrice) == "function" and Num(Plain(Call(Core.VendorPrice, item))) or nil
    if info.vendor and info.vendor <= 0 then info.vendor = nil end
    local price = info.itemID and Data.Price(info.itemID)
    info.auction = price and price.each or nil
    return info
end

--[[
    Sal.Own(itemID, spell) → eigene Beobachtung oder nil (zweite Stufe der Entzauber-Werte, EC-52; DG-07)
      Was beim Zerlegen dieses Gegenstands bei dir wirklich herauskam – ezCores Entdecker-Datenbank zählt es je
      Zerlege-Zauber und Gegenstand mit (Core.Drops.Salvage; selbst Gesammeltes, Leitlinie 11). Die Zahlen stehen
      NEBEN ezCores Tabelle, sie ersetzen sie nicht: die Tabelle bleibt „ungeprüft – im Spiel abgleichen“, bis der
      Abgleich (ezCore, Punkt 30) erledigt ist.
      { n = so oft zerlegt, label = „bei dir“ (ezCores Wortlaut), items = { [itemID] = { f = so oft dabei, s = Summe,
        lo, hi } } }
]]
function Sal.Own(itemID, spell)
    local D = Core.Drops
    itemID = Num(itemID)
    if not (type(D) == "table" and type(D.Salvage) == "function" and itemID) then return nil end
    local row, from = Call(D.Salvage, itemID, Num(spell))
    row, from = Plain(row), Plain(from)
    if type(row) ~= "table" then return nil end
    local n = (Num(row.cnt) or 0) + (Num(row.party) or 0)
    if n <= 0 then return nil end
    local items = {}
    for id, it in pairs(type(row.items) == "table" and row.items or EMPTY) do
        id = Num(id)
        local f = type(it) == "table" and Num(it.f) or nil
        if id and f and f > 0 then items[id] = { f = f, s = Num(it.s) or 0, lo = Num(it.lo), hi = Num(it.hi) } end
    end
    local label = type(from) == "table" and Plain(from.label) or nil
    if type(label) ~= "string" or label == "" then label = Core.L.DB_OWN end
    return { n = n, label = label, items = items }
end

-- Menge, wie sie bei dir herauskam: „1–3“ bzw. „2“
local function OwnAmount(it)
    if it.lo and it.hi and it.hi > it.lo then return ("%d–%d"):format(it.lo, it.hi) end
    if it.lo then return tostring(it.lo) end
    return tostring(math.floor(it.s / it.f + 0.5))
end

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------

local ORDER = 28            -- nach „Rezept und Zutaten“ (27), vor der Einkaufsliste (30)
-- Farben der Zeilen sind Rollen (Core.Style.COLOR, dazu "hint" = Core.GREY), gezeichnet über ns.TipLines (Welle 23, A2)

local function AmountText(m)
    if m.max > m.min then return ("%d–%d"):format(m.min, m.max) end
    return tostring(m.min)
end

-- „80 % · 1–2× Seltsamer Staub“
-- Das Symbol des Materials steht vor seinem Namen (ezCores Helfer Core.ItemIconText, Wunsch vom 18.11.2026 „mit den
-- item icons“); ohne Symbol nur der Name.
function Sal.MaterialText(m)
    return L.SALVAGE_MATERIAL:format(math.floor(m.chance * 100 + 0.5), AmountText(m), Core.ItemIconText(m.id, m.name))
end

-- Steht der Auktionspreis des Gegenstands schon im selben Item-Tooltip (CRAFT-15)? ezAuction meldet seine Zeile über
-- ezCores Core.Tooltip.ClaimLine("price") an, Auctionator zeigt ihn selbst (ezCores Erkennung „auctionTooltip“).
-- → Name dessen, der ihn zeigt, oder nil. Den Händlerpreis zeigt Blizzard immer selbst.
function Sal.AuctionShown(itemID, link)
    local T = Core.Tooltip
    if type(T) == "table" and type(T.Shows) == "function" and itemID then
        local shown, owner = Call(T.Shows, itemID, "price", link)
        if shown == true then return type(owner) == "string" and owner or "ezAuction" end
    end
    local other = ns.OtherFor("auctionTooltip")
    return type(other) == "string" and other or nil
end

local function Joined(parts)
    if #parts <= 1 then return parts[1] end
    return table.concat(parts, ", ", 1, #parts - 1) .. L.SALVAGE_AND .. parts[#parts]
end

-- Die Aussage, die im Item-Tooltip fehlt, wenn die Preise schon dastehen: bringt Entzaubern mehr oder weniger als
-- Händler bzw. Auktion? → Text, mehr (true) | weniger (false) – nil ohne Wert oder ohne Vergleich.
-- Fehlt einem Material der Preis, ist der Wert eine Untergrenze: „mehr“ gilt trotzdem, „weniger“ sagt es dazu.
function Sal.Verdict(info)
    if not (info and info.value) then return nil end
    local more, less = {}, {}
    if info.vendor then
        local list = info.value >= info.vendor and more or less
        list[#list + 1] = L.SALVAGE_VS_VENDOR
    end
    if info.auction then
        local list = info.value >= info.auction and more or less
        list[#list + 1] = L.SALVAGE_VS_AUCTION
    end
    if #less > 0 then
        return L.SALVAGE_LESS:format(Joined(less)) .. (info.complete and "" or " " .. L.SALVAGE_PARTIAL), false
    end
    if #more > 0 then return L.SALVAGE_MORE:format(Joined(more)), true end
    return nil
end

--[[
    Zeilen { left, right, color, rightColor } für einen Gegenstand (auch für die Tests und die Ansicht).
      opts.tooltip = true: im Item-Tooltip (Blizzards Verkaufspreis steht darüber, die Auktion je nach Sal.AuctionShown).
        Statt der Vergleichszeile „Händler … · Auktion …“ steht dann nur die fehlende Aussage (Sal.Verdict); den
        Auktionspreis nennt sie nur, wenn ihn kein anderer im Tooltip zeigt (CRAFT-15). Ohne opts (Reiter „Entzaubern“,
        eigener Tooltip ohne Preise darüber) bleibt die Vergleichszeile.
]]
function Sal.Lines(item, opts)
    local out = {}
    local info = Sal.Info(item)
    if not info then return out, nil end
    local inTooltip = type(opts) == "table" and opts.tooltip == true
    local function Line(left, right, color, rightColor)
        out[#out + 1] = { left = left, right = right, color = color or "highlight", rightColor = rightColor or "highlight" }
    end
    local head = Core.Gold(info.label .. ":")
    if info.value then
        -- „≈“: ein Erwartungswert über viele Gegenstände; unvollständig, wenn einem Material der Preis fehlt
        Line(head, L.SALVAGE_VALUE:format(Core.Money(info.value)) .. (info.complete and "" or " " .. L.SALVAGE_PARTIAL))
    else
        Line(head, L.SALVAGE_NO_PRICE, "highlight", "hint")
    end
    -- Eigene Beobachtung neben der Tabelle (EC-52): je Material „· bei dir 3×“, was nur bei dir herauskam, eigens
    local own = Sal.Own(info.itemID, info.spell)
    local inTable = {}
    for _, m in ipairs(info.materials) do
        inTable[m.id] = true
        local seen = own and own.items[m.id]
        local text = Sal.MaterialText(m) .. (seen and Core.Grey(" · " .. L.SALVAGE_OWN_PART:format(own.label, seen.f)) or "")
        Line("  " .. text, m.value and Core.Money(m.value) or L.SALVAGE_PRICE_UNKNOWN, "highlight", m.value and "highlight" or "hint")
    end
    if own then
        local extra = {}
        for id in pairs(own.items) do if not inTable[id] then extra[#extra + 1] = id end end
        table.sort(extra)
        for _, id in ipairs(extra) do
            local it = own.items[id]
            Line("  " .. L.SALVAGE_OWN_ONLY:format(OwnAmount(it), Core.ItemIconText(id, Data.ItemName(id)))
                .. Core.Grey(" · " .. L.SALVAGE_OWN_PART:format(own.label, it.f)), nil, "highlight")
        end
    end
    if inTooltip then
        local verdict, more = Sal.Verdict(info)
        local auctionText = info.auction and not Sal.AuctionShown(info.itemID, type(item) == "string" and item or nil)
            and L.SALVAGE_AUCTION:format(Core.Money(info.auction)) or nil
        if verdict then
            Line("  " .. verdict .. (auctionText and " (" .. auctionText .. ")" or ""), nil, more and "good" or "orange")
        elseif auctionText then
            Line("  " .. auctionText, nil, "highlight")
        end
        -- Erklärung der Marke am Taschenplatz (CRAFT-10): was ohne Taschenplatz prüfbar ist, wie in Sal.MarkFor – an,
        -- lohnt sich, nicht ignoriert, laut ezGear nicht besser. Platz und ezBags Schloss kennt der Tooltip nicht (Bank,
        -- Chat-Link, Auktionshaus); darum behauptet der Satz keinen Platz („in der Tasche mit diesem Zeichen markiert“).
        if Sal.MarkActive() and Sal.Worth(info) and not (info.itemID and Sal.IsIgnored(info.itemID))
            and not Sal.IsUpgrade(type(item) == "string" and item or nil) then
            Line("  " .. L.SALVAGE_MARK_LINE:format(Sal.MARK_TEXTURE), nil, "highlight")
        end
    else
        local compare = {}
        if info.vendor then compare[#compare + 1] = L.SALVAGE_VENDOR:format(Core.Money(info.vendor)) end
        if info.auction then compare[#compare + 1] = L.SALVAGE_AUCTION:format(Core.Money(info.auction)) end
        if #compare > 0 then Line("  " .. table.concat(compare, " · "), nil, "highlight") end
    end
    if own then Line("  " .. L.SALVAGE_OWN_COUNT:format(own.label, own.n), nil, "hint") end
    if info.unverified then Line("  " .. Core.L.SALVAGE_UNVERIFIED, nil, "hint") end   -- ezCores Text, Pflicht bis zum Abgleich
    return out, info
end

function Sal.Draw(tooltip, item, opts)
    local lines = Sal.Lines(item, opts)
    if #lines == 0 then return 0 end
    Core.Tooltip.Gap(tooltip)   -- ezCores einer Trenner (S-1811-Tooltipabstand): keine doppelte Leerzeile
    ns.TipLines(tooltip, lines)
    return #lines
end

Core.Tooltip.AddItemSection("ezCraft.salvage", ORDER, function(tooltip, itemID, data)
    if not ns.Enabled("tooltipSalvage") or Sal.Other() then return end
    -- der Link nennt die Variante (Itemlevel); ohne Link der Grundgegenstand
    local link = Core.Tooltip.ItemLink and Call(Core.Tooltip.ItemLink, tooltip, data) or nil
    Sal.Draw(tooltip, type(link) == "string" and link or itemID, { tooltip = true })
end, ADDON)

---------------------------------------------------------------------------
-- Kandidaten in der Tasche („Entzaubern?“ – Ja über den Zauber, Nein: nichts tun, Ignorieren: nie wieder vorschlagen)
---------------------------------------------------------------------------

local function Ignored() return ns.db and ns.db.salvageIgnore or EMPTY end

function Sal.IsIgnored(itemID) return Ignored()[itemID] == true end

function Sal.Ignore(itemID, on)
    itemID = Num(itemID)
    if not (itemID and ns.db and type(ns.db.salvageIgnore) == "table") then return false end
    ns.db.salvageIgnore[itemID] = on ~= false and true or nil
    ns.Fire("SALVAGE_CHANGED")
    return true
end

function Sal.IgnoredCount()
    local n = 0
    for _ in pairs(Ignored()) do n = n + 1 end
    return n
end

-- Alle Ignorierten wieder vorschlagen. → Anzahl
function Sal.ClearIgnored()
    local n = Sal.IgnoredCount()
    if n > 0 and ns.db then
        wipe(ns.db.salvageIgnore)
        ns.Fire("SALVAGE_CHANGED")
    end
    return n
end

-- Bewertet ezGear das Teil als besser als das Angelegte? Dann wird es nie vorgeschlagen.
local function IsUpgrade(link)
    local api = Core.API("ezGear")
    local fn = api and api.IsUpgrade
    if type(fn) ~= "function" or type(link) ~= "string" then return false end
    return Call(fn, link) == true
end
Sal.IsUpgrade = IsUpgrade   -- auch für den Item-Tooltip (Sal.Lines steht weiter oben)

-- Trägt der Taschenplatz ezBags Schloss „nie verkaufen“? Die EINE Auskunft dafür ist ezCore.API("ezBag").IsLocked
-- (CRAFT-10, Entscheidung „Auctionator und GatherMate ablösen“ vom 14.11.2026: keine eigene Marke „behalten“).
-- Ohne ezBag (oder mit einer Fassung ohne IsLocked) gibt es kein Schloss.
function Sal.IsLocked(bag, slot)
    local api = Core.API("ezBag")
    local fn = api and api.IsLocked
    if type(fn) ~= "function" then return false end
    return Call(fn, bag, slot) == true
end

-- Nie vorschlagen: ignoriert, mit ezBags Schloss oder laut ezGear besser als das Angelegte.
local function Excluded(itemID, link, bag, slot)
    return Sal.IsIgnored(itemID) or Sal.IsLocked(bag, slot) or IsUpgrade(link)
end

-- Ausrüstung in der Tasche, die sich entzaubern lässt: { { bag, slot, itemID, link, name, icon, info } … },
-- wertvollstes zuerst (ohne Preis ans Ende, dann nach Name). Zweite Rückgabe: Anzahl übersprungener (ignoriert,
-- mit ezBags Schloss, besser).
function Sal.Candidates()
    local list, skipped = {}, 0
    if not Lib() then return list, skipped end
    Core.ForEachBagItem(function(bag, slot, item)
        local itemID = Num(item.itemID)
        local link = Plain(item.hyperlink)
        if not itemID or item.isLocked then return end
        local info = Sal.Info(type(link) == "string" and link or itemID)
        if not info then return end
        if Excluded(itemID, link, bag, slot) then
            skipped = skipped + 1
            return
        end
        list[#list + 1] = { bag = bag, slot = slot, itemID = itemID, link = link, name = Data.ItemName(itemID),
            icon = Data.ItemIcon(itemID), info = info }
    end, "sell")
    table.sort(list, function(a, b)
        local va, vb = a.info.value or -1, b.info.value or -1
        if va ~= vb then return va > vb end
        if a.name ~= b.name then return a.name < b.name end
        if a.bag ~= b.bag then return a.bag < b.bag end
        return a.slot < b.slot
    end)
    return list, skipped
end

---------------------------------------------------------------------------
-- Marke „lohnt sich zu entzaubern“ am Taschenplatz (CRAFT-10; Entscheidungsfrage 3 vom 13.11.2026: Liste plus
-- Marke an der Tasche, kein aufspringendes Fenster). Angemeldet bei ezCores Platzmarken (Core.SlotMarks, Frage 18 –
-- Empfehlung umgesetzt, Antwort offen): mit ezBag zeichnet ezBag sie, ohne ezBag ezCore an Blizzards Taschen.
-- Gezeigt wird sie nur, wenn der gespielte Charakter entzaubern kann, nur in den Taschen (nicht in der Bank) und nur
-- für Gegenstände, die auch die Liste vorschlagen würde. Schalter salvageMark.
---------------------------------------------------------------------------

Sal.MARK_KEY = "ezCraft.salvage"
local MARK = { texture = Sal.MARK_TEXTURE }

-- Lohnt sich das Entzaubern? Der erwartete Wert liegt über dem Händlerpreis und über dem Auktionspreis – soweit
-- sie bekannt sind; ohne Wert nie (ein Material ohne Preis macht den Wert zur Untergrenze, das reicht).
function Sal.Worth(info)
    if not (type(info) == "table" and info.value and info.value > 0) then return false end
    if info.vendor and info.value <= info.vendor then return false end
    if info.auction and info.value <= info.auction then return false end
    return true
end

-- Zeigt ezCraft die Marke gerade überhaupt (Schalter an, ezCores Platzmarken da, der Charakter kann entzaubern)?
function Sal.MarkActive()
    return ns.Enabled("salvageMark") and type(Core.SlotMarks) == "table" and Sal.CanDisenchant()
end

local function InBags(bag)
    for _, b in ipairs(Core.BagList("sell") or EMPTY) do
        if b == bag then return true end
    end
    return false
end

-- fn der Platzmarke: fn(itemID, link, bag, slot, quality) → Marke oder nil
function Sal.MarkFor(itemID, link, bag, slot, quality)
    if not Sal.MarkActive() then return nil end
    itemID, link, bag, slot = Num(Plain(itemID)), Plain(link), Num(Plain(bag)), Num(Plain(slot))
    if not (itemID and bag and slot) or not InBags(bag) then return nil end
    quality = Num(Plain(quality))
    if quality and (quality < 2 or quality > 4) then return nil end   -- entzaubern lässt sich Grün bis Violett
    if Excluded(itemID, link, bag, slot) then return nil end
    if not Sal.Worth(Sal.Info(type(link) == "string" and link or itemID)) then return nil end
    return MARK
end

function Sal.RegisterMark()
    local M = Core.SlotMarks
    if not (type(M) == "table" and type(M.Add) == "function") then return false end
    return Call(M.Add, Sal.MARK_KEY, { order = 60, owner = ADDON, fn = Sal.MarkFor }) == true
end

local function RefreshMarks()
    local M = Core.SlotMarks
    if type(M) == "table" and type(M.Refresh) == "function" then Call(M.Refresh) end
end
Sal.RefreshMarks = RefreshMarks

ns.OnReady(function() Sal.RegisterMark() end)
ns.Listen("SALVAGE_CHANGED", RefreshMarks)
Core.Listen("PRICES_CHANGED", RefreshMarks, ADDON)
Core.Listen("PRICES_SCAN_DONE", RefreshMarks, ADDON)
Core.Listen("GEAR_SCORES_CHANGED", RefreshMarks, ADDON)   -- ezGear bewertet neu (besser als das Angelegte)
ns.On("SPELLS_CHANGED", RefreshMarks)                     -- Entzaubern gelernt
ns.OnSettingChanged(function(key)
    if key == "salvageMark" or key == nil then RefreshMarks() end
end)

---------------------------------------------------------------------------
-- Entzaubern per Klick in der Liste „Entzaubern“ (CRAFT-09) über ezCores sicheren Knopf (Core.SecureButton)
--
-- Zauber auf einen Taschenplatz wirken ist eine geschützte Aktion. Ein geschützter Knopf als Kind des Seitenteils
-- machte das Seitenteil und das Berufefenster im Kampf selbst geschützt (Blizzard könnte es dann nicht mehr
-- schließen). Deshalb gibt es EINEN sicheren Knopf (Eltern: UIParent, nur Technik – kein Fenster), der außerhalb des
-- Kampfes über das sichtbare Symbol einer Zeile gelegt wird, sobald die Maus darauf zeigt (Sal.Arm). Er trägt das
-- Makro „/cast Entzaubern“ + „/use Tasche Platz“ für genau diesen Gegenstand:
--   ein Klick = ein Gegenstand, nie automatisch; vor dem Klick prüft PreClick, dass derselbe Gegenstand noch
--   ungesperrt auf dem Platz liegt (sonst leert er das Makro und sagt es); nach dem Klick ist der Knopf entschärft.
--   Beim Kampfbeginn (PLAYER_REGEN_DISABLED – da ist es noch erlaubt) wird er gelöst und versteckt; im Kampf ist das
--   Symbol der Zeile ausgegraut und sagt im Tooltip, warum.
---------------------------------------------------------------------------

Sal.BUTTON_NAME = "ezCraftDisenchantButton"
local secure      -- Griff von Core.SecureButton
local armed       -- { entry, anchor } solange der Knopf über einer Zeile liegt

-- Makro für einen Eintrag aus Sal.Candidates: „/cast Entzaubern\n/use 0 5“ (Zaubername in der Spielsprache, ezCore).
function Sal.MacroText(entry)
    local spell = entry and entry.info and entry.info.label or L.SALVAGE_TITLE
    return ("/cast %s\n/use %d %d"):format(spell, entry.bag, entry.slot)
end

-- Liegt noch derselbe Gegenstand ungesperrt auf dem Platz? → true | false, "gone" | "busy"
function Sal.SlotHolds(entry)
    local get = C_Container and C_Container.GetContainerItemInfo
    local info = type(get) == "function" and Plain(Call(get, entry.bag, entry.slot)) or nil
    if type(info) ~= "table" or Num(Plain(info.itemID)) ~= entry.itemID then return false, "gone" end
    if Plain(info.isLocked) == true then return false, "busy" end
    return true
end

-- Zaubert oder kanalisiert der Charakter gerade, oder wartet ein Zauber auf sein Ziel? Dann schlüge „/cast Entzaubern“
-- fehl, und die zweite Makrozeile „/use Tasche Platz“ legte die Ausrüstung an (gebunden: still). Das trifft vor allem
-- den zweiten schnellen Klick, während das erste Entzaubern noch läuft – der nächste Gegenstand ist da schon nachgerückt.
-- Also nichts tun. Ein geheimer Wert gilt als „beschäftigt“ – ein verweigerter Klick lässt sich wiederholen.
local function Busy(value)
    if Core.IsSecret(value) then return true end
    return value ~= nil and value ~= false
end
function Sal.PlayerBusy()
    if Busy((Call(_G.UnitCastingInfo, "player"))) or Busy((Call(_G.UnitChannelInfo, "player"))) then return true end
    return Busy((Call(_G.SpellIsTargeting)))
end

-- Tooltip des Klicks (sichtbares Symbol und darübergelegter Knopf): was passiert, bzw. warum nicht.
function Sal.ClickTip(tooltip, entry)
    if not entry then return end
    tooltip:SetText(L.SALVAGE_TITLE)
    ns.TipLine(tooltip, L.SALVAGE_CLICK_TIP:format(entry.name or "?", entry.bag, entry.slot), "highlight", true)
    if Core.InCombat() then ns.TipLine(tooltip, Sal.CombatText(), "bad", true) end
end

-- Derselbe Satz wie Core.CombatNotice (T18-1) als Tooltip-Zeile: „Entzaubern geht im Kampf nicht – …“
function Sal.CombatText()
    return Core.CombatText(L.SALVAGE_WHAT)
end

local function OnEnterSecure(frame)
    if not armed then return end
    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    Sal.ClickTip(GameTooltip, armed.entry)
    GameTooltip:Show()
end

local function OnLeaveSecure()
    GameTooltip_Hide()
    Sal.Disarm()
end

local function PreClick()
    local entry = armed and armed.entry
    local ok, why = false, "gone"
    if entry then ok, why = Sal.SlotHolds(entry) end
    if ok and Sal.PlayerBusy() then ok, why = false, "casting" end
    if not ok and secure then
        secure:SetAction(nil)   -- dieser Klick tut nichts (außerhalb des Kampfes wirkt das sofort)
        ns.Print(why == "casting" and L.SALVAGE_CLICK_CASTING or why == "busy" and L.SALVAGE_CLICK_BUSY
            or L.SALVAGE_CLICK_GONE)
    end
end

local function PostClick()
    Sal.Disarm()                -- ein Klick, ein Gegenstand: für den nächsten neu auf das Symbol zeigen
    if ns.Panel and ns.Panel.RefreshSoon then ns.Panel.RefreshSoon() end
end

local function SecureHandle()
    if secure then return secure end
    if type(Core.SecureButton) ~= "function" then return nil end
    local handle = Core.SecureButton(Sal.BUTTON_NAME, {
        owner = ADDON,
        onCreate = function(frame)
            frame:SetScript("PreClick", PreClick)
            frame:SetScript("PostClick", PostClick)
            frame:HookScript("OnEnter", OnEnterSecure)
            frame:HookScript("OnLeave", OnLeaveSecure)
            if frame.SetHighlightTexture then frame:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD") end
        end,
    })
    secure = handle
    return secure
end

-- Legt den sicheren Knopf über anchor (das Symbol der Zeile) und belegt ihn mit dem Makro für entry.
-- → true | false, Grund ("combat", "unknown" – der Charakter kann nicht entzaubern, "missing" – kein sicherer Knopf)
function Sal.Arm(anchor, entry)
    if not (anchor and entry and entry.bag and entry.slot) then return false, "invalid" end
    if Core.InCombat() then return false, "combat" end
    if not Sal.CanDisenchant() then return false, "unknown" end
    local handle = SecureHandle()
    if not handle then return false, "missing" end
    armed = { entry = entry, anchor = anchor }
    handle:SetAction({ type = "macro", macrotext = Sal.MacroText(entry) })
    handle:Anchor(function(frame)
        frame:ClearAllPoints()
        frame:SetAllPoints(anchor)
        if anchor.GetFrameStrata then frame:SetFrameStrata(anchor:GetFrameStrata()) end
        if anchor.GetFrameLevel then frame:SetFrameLevel(anchor:GetFrameLevel() + 10) end
    end)
    handle:Show()
    return true
end

-- Entschärfen: Makro leeren, verstecken, vom Symbol lösen. Außerhalb des Kampfes sofort; im Kampf ist er schon gelöst.
function Sal.Disarm()
    local was = armed
    armed = nil
    if not secure or Core.InCombat() then return end
    if not was and not secure:Shown() then return end   -- nichts zu lösen (Panel.Refresh ruft das oft)
    secure:Release()
    secure:Do(function(frame) frame:ClearAllPoints() end, "detach")
end

function Sal.Armed() return armed end
function Sal.SecureButton() return secure end

-- Kampfbeginn: Die Sperre greift erst nach dem Ereignis – jetzt lösen, damit das Seitenteil ungeschützt bleibt
-- (ein geschützter Rahmen, der an einem Rahmen verankert ist, schützt diesen im Kampf mit).
ns.On("PLAYER_REGEN_DISABLED", function() Sal.Disarm() end)

-- Status (/ezcraft status): ob der Entzauber-Wert gezeigt wird, wer ihn sonst zeigt, wie viel ignoriert ist.
ns.AddStatusLine(function()
    if not Sal.Available() then return L.WAIT_SALVAGE end
    local other = Sal.Other()
    if other then return L.STATUS_SALVAGE_OTHER:format(other) end
    return L.STATUS_SALVAGE:format(ns.Enabled("tooltipSalvage") and L.ON or L.OFF, Sal.IgnoredCount())
end)
