local ADDON, ns = ...
local L = ns.L

--[[
    Kleine Anzeigen an Blizzards eigenen Teilen der Tasche:
    - Geldfeld der Tasche: Tooltip mit dem Gold aller Charaktere (Blizzards Münz-Knöpfe haben
      eigene OnEnter-Skripte, der Tooltip ist bei der Tasche aber aus – wir hängen uns an)
    - Sortierknopf der Tasche: Händlerwert aller Gegenstände in den Taschen (davon Plunder), dazu
      der Auktionswert ungebundener Gegenstände aus dem Preis-Wissen von ezCore (ezCore.Prices)
    Die Charakterdaten kommen aus ezCore. Nur HookScript, keine Werte in Blizzards Tabellen.
]]

local Info = {}
ns.Info = Info

---------------------------------------------------------------------------
-- Gold aller Charaktere
---------------------------------------------------------------------------

-- { { key, c, money } … }, reichste zuerst; dazu die Summe.
-- Gold aller Charaktere aus ezCore (eine Liste für ezBag und ezPanel), reichste zuerst.
function Info.GoldList()
    return ezCore.GoldList()
end

-- Immer an seit der Einstellungs-Prüfung vom 19.11.2026 (Nr. 5): erscheint nur beim Draufzeigen.
function Info.ShowGold(owner)
    local list, total = Info.GoldList()
    GameTooltip:SetOwner(owner, "ANCHOR_TOPRIGHT")
    GameTooltip:SetText(L.GOLD_TITLE, ns.TipRGB("normal"))
    for _, row in ipairs(list) do
        GameTooltip:AddDoubleLine(ezCore.CharName(row.c, row.key, "-"), ezCore.White(ns.CoinText(row.money)))
    end
    if #list > 1 then
        GameTooltip:AddDoubleLine(L.TOTAL, ezCore.White(ns.CoinText(total)), ns.TipRGB("normal"))
    end
    GameTooltip:Show()
end

local hookedMoney = setmetatable({}, { __mode = "k" })

-- Münz-Knöpfe eines Geldfelds (Gold, Silber, Kupfer) und das Feld selbst.
function Info.HookMoneyFrame(moneyFrame)
    if not moneyFrame or hookedMoney[moneyFrame] then return end
    hookedMoney[moneyFrame] = true
    local name = moneyFrame.GetName and moneyFrame:GetName()
    for _, key in ipairs({ "GoldButton", "SilverButton", "CopperButton" }) do
        local b = rawget(moneyFrame, key) or (name and _G[name .. key])
        if type(b) == "table" and b.HookScript then
            b:HookScript("OnEnter", function(self) Info.ShowGold(self) end)
            b:HookScript("OnLeave", GameTooltip_Hide)
        end
    end
end

---------------------------------------------------------------------------
-- Händlerwert der Tasche (Tooltip des Sortierknopfs)
---------------------------------------------------------------------------

-- Händlerwert aller Gegenstände in den getragenen Taschen; dazu davon Plunder und der Auktionswert
-- ungebundener Gegenstände (Marktwert × Anzahl aus ezCore.Prices; nur Gegenstände mit Preis).
function Info.BagValue()
    local total, junk, auction, priced = 0, 0, 0, 0
    local P = ezCore.Prices
    do
        -- Alles, was der Charakter bei sich trägt (mit Reagenzientasche und Schlüsselbund): ezCores Schleife.
        ezCore.ForEachBagItem(function(_, _, info)
            if ns.ItemIDOf(info) then
                local value = ns.SellValue(info)
                total = total + value
                if ns.IsJunk(info) then junk = junk + value end
                if P and P.Value and not info.isBound then
                    local ok, market = pcall(P.Value, info.hyperlink or info.itemID, info.stackCount or 1)
                    if ok and type(market) == "number" and market > 0 then
                        auction = auction + market
                        priced = priced + 1
                    end
                end
            end
        end, "carried")
    end
    return total, junk, auction, priced
end

-- Zeilen zum Auktionswert im Tooltip „Wert der Tasche“: der Wert mit seiner Quelle (ezCores Preis-Wissen aus den
-- eigenen Besuchen im Auktionshaus) – oder die Erklärung, warum keiner dasteht. → { { left, right, r, g, b }, … }
local function Line(left, right, role)
    local r, g, b = ns.TipRGB(role)
    return { left = left, right = right, r = r, g = g, b = b }
end

function Info.AuctionLines(auction, priced)
    local lines = {}
    local P = ezCore.Prices
    if not (P and P.Value) then
        lines[1] = Line(L.VALUE_AUCTION_OFF, nil, "hint")
    elseif (auction or 0) > 0 then
        lines[1] = Line(L.VALUE_AUCTION:format(priced or 0), ezCore.White(ns.CoinText(auction)), "normal")
        lines[2] = Line(L.VALUE_AUCTION_SOURCE, nil, "hint")
    else
        lines[1] = Line(L.VALUE_AUCTION_NONE, nil, "hint")
    end
    return lines
end

-- Immer an seit der Einstellungs-Prüfung vom 19.11.2026 (Nr. 6): Zeilen nur im Tooltip des Knopfs.
function Info.AddBagValue(owner)
    local total, junk, auction, priced = Info.BagValue()
    if GameTooltip:GetOwner() ~= owner or not GameTooltip:IsShown() then
        GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
        GameTooltip:SetText(L.VALUE_TITLE, ns.TipRGB("normal"))
    else
        GameTooltip:AddLine(" ")
    end
    GameTooltip:AddDoubleLine(L.VALUE_BAGS, ezCore.White(ns.CoinText(total)), ns.TipRGB("normal"))
    if junk > 0 then
        GameTooltip:AddDoubleLine(L.VALUE_JUNK, ezCore.White(ns.CoinText(junk)), ns.TipRGB("hint"))
    end
    -- Regel „Datenquellen“ (Nutzer, 13.11.2026): Jede Angabe nennt ihre Quelle, und wo nichts steht, steht warum.
    for _, line in ipairs(Info.AuctionLines(auction, priced)) do
        if line.right then
            GameTooltip:AddDoubleLine(line.left, line.right, line.r, line.g, line.b)
        else
            GameTooltip:AddLine(line.left, line.r, line.g, line.b, true)
        end
    end
    GameTooltip:Show()
end

local sortHooked = false

function Info.HookSortButton()
    local sort = _G.BagItemAutoSortButton
    if sortHooked or not (sort and sort.HookScript) then return end
    sortHooked = true
    sort:HookScript("OnEnter", function(self) Info.AddBagValue(self) end)
    sort:HookScript("OnLeave", GameTooltip_Hide)
end

ns.OnReady(function()
    local bag = _G.ContainerFrameCombinedBags
    if bag then Info.HookMoneyFrame(bag.MoneyFrame) end
    -- Ohne kombinierte Tasche trägt der Rucksack (ContainerFrame1) das Geldfeld.
    local backpack = _G.ContainerFrame1
    if backpack then Info.HookMoneyFrame(backpack.MoneyFrame or _G.ContainerFrame1MoneyFrame) end
    Info.HookSortButton()
end)
