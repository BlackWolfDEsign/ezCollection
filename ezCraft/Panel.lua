local ADDON, ns = ...
local L = ns.L
local Core = ezCore
local Data = ns.Data

--[[
    ezCraft als Seitenteil mit Pfeil am Berufefenster (ProfessionsFrame aus Blizzard_Professions, Forever/Camelot) –
    Entscheidung des Nutzers vom 14.11.2026 „Seitenteil mit Pfeil (Empfohlen)“ (CRAFT-01, FP-13). Vorher (1.5 bis
    Welle 5) saß ezCraft im Rezeptfeld unter Blizzards Zutaten, mit Knopfspalte und Seitenreitern; im Spieltest
    überlappten Auctionators Zeilen die Überschrift und die Knöpfe hingen über Blizzards Seitenreitern.

    Lage laut Forever-Quelle (Gethe/wow-ui-source, Zweig forever: Camelot/Blizzard_ProfessionsFrame.xml):
      Berufefenster                    673 × 594 (Seite „Rezepte“ bis 782 breit, GetDesiredPageWidth)
      Blizzards Reiter rechts außen    ProfessionsOverviewTab (LargeSideTabButtonTemplate) an TOPRIGHT, y −60, darunter
                                       Professions1Tab … 7Tab – sie ragen über den rechten Rand hinaus
      Seitenreiter-Stapel              ebenfalls rechts außen (Core.CreateSideTab, Reiter anderer Module)

    Aufbau (nur eigene Rahmen; nichts in Blizzards Tabellen, nur HookScript; Blizzards Rezeptfeld bleibt unberührt):
      Seitenteil         Core.NewSidePanel(ProfessionsFrame): Kind des Berufefensters (kein Rahmen unter UIParent),
                         angedockt rechts außen mit Abstand SIDE_GAP – so bleiben Blizzards Reiter und der
                         Seitenreiter-Stapel frei; ohne Platz wechselt ezCore die Seite oder legt es innen darüber
                         (dann sagt das Seitenteil es). Blizzards Vorlage InsetFrameTemplate, dazu der Hintergrund des
                         offenen Berufs aus dem Rezeptfeld (nur gelesen).
      Pfeil-Knopf        von ezCore: zu = oben außen am Berufefenster, offen = in der äußeren oberen Ecke des
                         Seitenteils; Zustand in ezCraftDB.window.open, Tooltip, /ezcraft fenster
      Reiterzeile        oben im Seitenteil: Rezept, Einkaufsliste, Fehlend, Abklingzeiten, Entzaubern (Symbole mit
                         Tooltip); der gewählte nochmal, das X oder ein Rezept in Blizzards Liste führt zum Rezept
      Inhalt             je Reiter (Rezept: Material aller Twinks, herstellbar, Kosten, Skill-Farben, Abklingzeit,
                         wer es herstellen kann); scrollt
      Seite „Berufe“     dasselbe Seitenteil auch auf Blizzards Seite „Berufe“ (BookPage, Taste K; Schalter bookPanel,
                         Entscheidung des Nutzers Nr. 22 vom 16.11.2026) – ohne die Reiter „Rezept“ und „Fehlend“
      Knopfleiste        unten: „Auf die Liste“, „Anfordern“, „Im AH suchen“ – Blizzards Vorlage der Herstellen-Knöpfe;
                         je Ansicht die passenden Knöpfe („Leeren“, „Neu lesen“, „Ignorierte zurück“)

    Gewählt wird über Blizzards Nachricht „ProfessionsRecipeListMixin.Event.OnRecipeSelected“ (EventRegistry), die Menge
    liest ezCraft aus Blizzards Feld „Herstellen“ (CreateMultipleInputBox) – nur lesen, nichts setzen.
]]

local Panel = {}
ns.Panel = Panel

local ROW_H = 18
local TAB_KEYS = { "recipe", "shopping", "missing", "cooldowns", "salvage" } -- Reiterzeile; „recipe“ ist die Grundansicht
local VIEW_ICONS = {
    recipe = "Interface\\Icons\\Trade_BlackSmithing",
    shopping = "Interface\\Icons\\INV_Misc_Note_01",
    missing = "Interface\\Icons\\INV_Scroll_03",
    cooldowns = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    salvage = "Interface\\Icons\\INV_Enchant_Disenchant",
}
local TICK = 30                     -- Restzeiten alle 30 Sekunden auffrischen
local BUTTON_W, BUTTON_H, BUTTON_GAP = 98, 22, 6
Panel.SIDE_W = 320                  -- Breite des Seitenteils: drei Knöpfe zu 98 nebeneinander
Panel.SIDE_GAP = 46                 -- Abstand zum Berufefenster: Blizzards Berufe-Reiter und der Seitenreiter-Stapel
                                    -- ragen rechts außen bis rund 44 über den Rand (LargeSideTabButtonTemplate)
local TAB_SIZE, TAB_GAP = 30, 6     -- Reiterzeile oben im Seitenteil
local TOP_ROOM = 32                 -- oben frei für Überschrift und Pfeil (Core.SIDEPANEL_ARROW_ROOM = 30)
local CONTENT_TOP = 98              -- Inhalt unter Reiterzeile und Überschrift der Ansicht
local CONTENT_BOTTOM = 40           -- über der Knopfleiste

local ui = { buttons = {}, tabs = {}, ticking = false, elapsed = 0 }
local selectedRecipeID

local function Professions() return ProfessionsFrame end
local function CraftingPage()
    local pf = Professions()
    return pf and pf.CraftingPage
end
local function SchematicForm()
    local page = CraftingPage()
    return page and page.SchematicForm
end
-- Seite „Berufe“ (Taste K) im Berufefenster (Forever: ProfessionsFrame.BookPage, siehe Book.lua)
local function BookPage()
    local pf = Professions()
    return pf and pf.BookPage
end

local function Visible(frame)
    return type(frame) == "table" and type(frame.IsShown) == "function" and frame:IsShown() and true or false
end

local function CraftingShown()
    return Visible(Professions()) and Visible(CraftingPage())
end

-- Entscheidung des Nutzers vom 16.11.2026 (Nr. 22, vorläufig nach Empfehlung): das Seitenteil auch auf der Seite
-- „Berufe“, mit Schalter bookPanel (ab Werk an). Dort gibt es kein gewähltes Rezept: die Reiter „Rezept“ und „Fehlend“
-- fehlen, Einkaufsliste, Abklingzeiten und Entzaubern bleiben.
local function OnBook()
    return ns.Enabled("bookPanel") and not CraftingShown() and Visible(Professions()) and Visible(BookPage())
end
Panel.OnBook = OnBook

local function RGB(stage) return Data.StageRGB(stage) end

local function Colored(text, colorObj)
    if colorObj and colorObj.WrapTextInColorCode then return colorObj:WrapTextInColorCode(text) end
    return text
end

-- Menge aus Blizzards Feld „Herstellen“ (nur lesen).
function Panel.Quantity()
    local page = CraftingPage()
    local box = page and page.CreateMultipleInputBox
    local value = box and box.GetValue and Core.Call(box.GetValue, box)
    value = Core.Num(value)
    if not value or value < 1 then return 1 end
    return math.floor(value)
end

function Panel.SelectedRecipeID()
    return selectedRecipeID or Data.SelectedRecipeID()
end

-- Ansichten, die sich abschalten lassen (oder ohne ezCore-Teil fehlen).
local function TabAvailable(key)
    if (key == "recipe" or key == "missing") and OnBook() then return false end
    if key == "missing" then return ns.Enabled("missingTab") end
    if key == "cooldowns" then return ns.Enabled("cooldownTab") and Data.HasCooldowns() end
    -- „Entzaubern“ nur, wenn der Charakter es kann (und ezCore die Tabelle hat)
    if key == "salvage" then return ns.Enabled("salvageTab") and ns.Salvage ~= nil and ns.Salvage.CanDisenchant() end
    return true
end

local function Tab()
    local tab = ns.db and ns.db.window.tab or "recipe"
    if not TabAvailable(tab) then tab = OnBook() and "shopping" or "recipe" end   -- Seite „Berufe“: Einkaufsliste
    return tab
end

---------------------------------------------------------------------------
-- Zeilen (ein Ziel im Seitenteil, für jede Ansicht wiederverwendet)
---------------------------------------------------------------------------

local cur   -- Ziel, in das gerade geschrieben wird: { scroll, content, rows, used, cursorY }

local function CreateScroll(parent)
    local ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, parent, "ScrollFrameTemplate")
    if not (ok and scroll) then scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate") end
    local bar = scroll.ScrollBar
    if type(bar) == "table" and bar.SetHideIfUnscrollable then bar:SetHideIfUnscrollable(true) end
    return scroll
end

local function NewTarget(parent)
    local target = { rows = {}, used = 0, cursorY = 0 }
    target.scroll = CreateScroll(parent)
    target.content = CreateFrame("Frame", nil, target.scroll)
    target.content:SetSize(260, 1)
    target.scroll:SetScrollChild(target.content)
    target.scroll:SetScript("OnSizeChanged", function(_, width)
        if width and width > 0 then target.content:SetWidth(width) end
    end)
    return target
end

-- Kleine Symbolknöpfe an Zeilen (Blizzards Plus/Minus der Questliste, rotes X der Würfel-Leiste).
local ROW_ICONS = {
    remove = { "Interface\\Buttons\\UI-GroupLoot-Pass-Up", "Interface\\Buttons\\UI-GroupLoot-Pass-Down",
        "Interface\\Buttons\\UI-GroupLoot-Pass-Highlight" },
    plus = { "Interface\\Buttons\\UI-PlusButton-Up", "Interface\\Buttons\\UI-PlusButton-Down",
        "Interface\\Buttons\\UI-PlusButton-Hilight" },
    minus = { "Interface\\Buttons\\UI-MinusButton-Up", "Interface\\Buttons\\UI-MinusButton-Down",
        "Interface\\Buttons\\UI-PlusButton-Hilight" },
    -- Entzaubern per Klick (CRAFT-09): das Symbol des Zaubers; den Klick nimmt ezCores sicherer Knopf darüber an
    disenchant = { "Interface\\Icons\\INV_Enchant_Disenchant", "Interface\\Icons\\INV_Enchant_Disenchant",
        "Interface\\Buttons\\ButtonHilight-Square" },
    -- „Nächste Fundorte“ (SAM-24): Blizzards Kartensymbol; der Klick öffnet die Weltkarte über ezMap
    map = { "Interface\\Icons\\INV_Misc_Map_01", "Interface\\Icons\\INV_Misc_Map_01",
        "Interface\\Buttons\\ButtonHilight-Square" },
}

-- Symbolknopf an einer Zeile; onEnter (optional) ersetzt den Standard-Tooltip aus tip.
local function RowButton(row, index, kind, tip, onClick, onEnter)
    local button = row.buttons[index]
    if not button then
        button = CreateFrame("Button", nil, row)
        button:SetSize(16, 16)
        if index == 1 then
            button:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        else
            button:SetPoint("RIGHT", row.buttons[index - 1], "LEFT", -2, 0)
        end
        button:SetScript("OnEnter", function(self)
            if self.onEnter then return self.onEnter(self) end
            if self.tip then Core.ShowTip(self, self.tip) end
        end)
        button:SetScript("OnLeave", GameTooltip_Hide)
        -- ausgegraut (z. B. „Entzaubern“ im Kampf) muss der Tooltip trotzdem sagen, warum
        if button.SetMotionScriptsWhileDisabled then button:SetMotionScriptsWhileDisabled(true) end
        row.buttons[index] = button
    end
    local files = ROW_ICONS[kind]
    if button.kind ~= kind and files then
        button:SetNormalTexture(files[1])
        button:SetPushedTexture(files[2])
        button:SetHighlightTexture(files[3], "ADD")
    end
    button.kind, button.tip, button.onEnter = kind, tip, onEnter
    button:SetScript("OnClick", onClick)
    button:SetEnabled(true)
    local normal = button.GetNormalTexture and button:GetNormalTexture()
    if normal and normal.SetDesaturated then normal:SetDesaturated(false) end
    button:Show()
    return button
end

local function NewRow()
    local row = CreateFrame("Button", nil, cur.content)
    row:SetHeight(ROW_H)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.left = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.left:SetJustifyH("LEFT")
    row.right = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.right:SetJustifyH("RIGHT")
    row.buttons = {}
    row:SetScript("OnEnter", function(self)
        if not self.tip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local ok, err = pcall(self.tip, GameTooltip)
        if not ok then ns.Error(err, "Tooltip") end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    return row
end

-- Neue Zeile; kind: "header", "text" (umbricht), "item" (Symbol links, Werte rechts).
local function Row(kind, height)
    cur.used = cur.used + 1
    local row = cur.rows[cur.used]
    if not row then
        row = NewRow()
        cur.rows[cur.used] = row
    end
    row.kind, row.tip = kind, nil
    for _, button in ipairs(row.buttons) do button:Hide() end
    row.icon:Hide()
    row.left:SetText("")
    row.right:SetText("")
    row.left:SetFontObject(kind == "header" and "GameFontNormal" or "GameFontHighlightSmall")
    local r, g, b = Core.Style.Color("highlight")   -- Blizzards Weiß (HIGHLIGHT_FONT_COLOR, Design-System 2.5)
    row.left:SetTextColor(r, g, b)   -- nur drei Werte: der vierte von Style.Color ist das Farbobjekt, nicht Alpha
    row.left:ClearAllPoints()
    row.right:ClearAllPoints()
    if kind == "item" then
        row.left:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
        row.left:SetPoint("RIGHT", row.right, "LEFT", -4, 0)
        row.right:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    else
        row.left:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -2)
        row.left:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    end
    row.left:SetWordWrap(kind == "text")
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", cur.content, "TOPLEFT", 0, -cur.cursorY)
    row:SetPoint("RIGHT", cur.content, "RIGHT", 0, 0)
    row:SetHeight(height or ROW_H)
    row:Show()
    return row
end

local function Advance(row, extra)
    cur.cursorY = cur.cursorY + row:GetHeight() + (extra or 0)
end

local function Header(text)
    if cur.cursorY > 0 then cur.cursorY = cur.cursorY + 6 end
    local row = Row("header", 20)
    row.left:SetText(text)
    Advance(row)
    return row
end

local function Text(text, r, g, b)
    local row = Row("text")
    row.left:SetText(text)
    if r then row.left:SetTextColor(r, g, b) end
    local height = (row.left.GetStringHeight and row.left:GetStringHeight()) or 0
    row:SetHeight(math.max(ROW_H, height + 4))
    Advance(row)
    return row
end

local function ItemRow(icon, left, right)
    local row = Row("item")
    if icon then
        row.icon:SetTexture(icon)
        row.icon:Show()
    end
    row.left:SetText(left or "")
    row.right:SetText(right or "")
    Advance(row)
    return row
end

local function BeginRows(target)
    cur = target
    cur.used, cur.cursorY = 0, 0
end

local function EndRows()
    for i = cur.used + 1, #cur.rows do cur.rows[i]:Hide() end
    cur.content:SetHeight(math.max(cur.cursorY, 1))
end

---------------------------------------------------------------------------
-- Tooltips
---------------------------------------------------------------------------

local function StockLines(tooltip, stock)
    local function line(label, n)
        if n > 0 then ns.TipDoubleLine(tooltip, label, n, "normal", "highlight") end
    end
    line(L.SRC_bags, stock.bags)
    line(L.SRC_bank, stock.bank)
    line(L.SRC_mail, stock.mail)
    line(L.SRC_guild, stock.guild)
    for _, alt in ipairs(stock.altList) do
        local parts = {}
        if alt.bags > 0 then parts[#parts + 1] = L.SRC_SHORT_bags:format(alt.bags) end
        if alt.bank > 0 then parts[#parts + 1] = L.SRC_SHORT_bank:format(alt.bank) end
        if alt.mail > 0 then parts[#parts + 1] = L.SRC_SHORT_mail:format(alt.mail) end
        local name = Core.CharName(alt.c, alt.key)
        if not alt.mailable then name = Core.Grey(Core.CharName(alt.c, alt.key, nil, true) .. " " .. L.NOT_MAILABLE) end
        ns.TipDoubleLine(tooltip, name, table.concat(parts, ", "), "highlight", "highlight")
    end
end

local function MaterialTip(row)
    return function(tooltip)
        tooltip:SetText(row.name)
        ns.TipLine(tooltip, L.TIP_NEED:format(row.need), "highlight")
        StockLines(tooltip, row.stock)
        if row.missing > 0 then ns.TipLine(tooltip, L.TIP_MISSING:format(row.missing), "bad") end
        local price = ns.Enabled("costs") and Data.Price(row.itemID)
        if price then
            local when = price.seen and (" (" .. Core.Ago(price.seen) .. ")") or ""
            ns.TipDoubleLine(tooltip, L.TIP_PRICE, Core.Money(price.each) .. when, "normal", "highlight")
        end
        local gather = row.gather
        if gather then
            if gather.here > 0 then ns.TipLine(tooltip, L.GATHER_HERE_TIP, "good") end
            -- „Fundorte: … (bei dir, n Punkte; laut …)“ ist ezCores Zeile (Core.Gathering.Line, DG-56: eigene Ernten
            -- zuerst, jede Quelle genannt – derselbe Wortlaut wie im Item-Tooltip); ältere ezCore: nur die Gebiete
            if gather.line then
                ns.TipLine(tooltip, gather.line, "good", true)
            elseif gather.text then
                ns.TipLine(tooltip, L.GATHER_LINE:format(gather.text), "good", true)
            end
        end
        ns.TipLine(tooltip, L.TIP_COUNTED, "hint", true)
    end
end

-- „4/6“ grün (Tasche reicht), gelb (mit Bank, Post, Twinks …), rot (fehlt).
local function HaveText(have, need, status)
    local text = ("%d/%d"):format(math.min(have, need), need)
    if status == "bags" then return Colored(text, GREEN_FONT_COLOR) end
    if status == "have" then return Colored(text, YELLOW_FONT_COLOR or NORMAL_FONT_COLOR) end
    return Colored(text, RED_FONT_COLOR)
end

---------------------------------------------------------------------------
-- Inhalte
---------------------------------------------------------------------------

-- Kartenknopf „Nächste Fundorte“ (SAM-24) an einer Zeile mit fehlendem, sammelbarem Material: öffnet über ezMap
-- Blizzards Weltkarte mit deinen Fundorten (Leitlinie 3). Ohne ezMap oder ohne eigenen Fundort ausgegraut; der
-- Tooltip sagt dann, warum (SetMotionScriptsWhileDisabled in RowButton).
local function GatherButton(item, row)
    local state = Data.GatherState(row.itemID)
    local tip
    if state == "nomap" then
        tip = L.GATHER_BTN_NOMAP
    elseif state == "none" then
        tip = L.GATHER_BTN_NONE:format(row.name or "?")
    else
        tip = L.GATHER_BTN_TIP:format(row.name or "?")
    end
    local itemID = row.itemID
    local button = RowButton(item, 1, "map", tip, function() Data.ShowGather(itemID) end, function(self)
        Core.ShowTip(self, L.GATHER_BTN, self.tip)
    end)
    button.state, button.itemID = state, itemID
    if state ~= "ok" then
        button:SetEnabled(false)
        local normal = button.GetNormalTexture and button:GetNormalTexture()
        if normal and normal.SetDesaturated then normal:SetDesaturated(true) end
    end
    item.right:ClearAllPoints()
    item.right:SetPoint("RIGHT", button, "LEFT", -4, 0)
    return button
end
Panel.GatherButton = GatherButton
Panel.MaterialTip = MaterialTip   -- für die Tests: Tooltip einer Materialzeile

-- Fehlendes, das sich im aktuellen Gebiet sammeln lässt, bekommt „hier sammelbar“ (Fundorte von ezCore, eigene Ernten
-- zuerst); fehlendes Sammelbares dazu den Kartenknopf „Nächste Fundorte“. Beides hängt am Schalter gatherHint.
local function MaterialRows(rows)
    local gatherOn = ns.Enabled("gatherHint")
    for _, row in ipairs(rows) do
        local status = row.status or (row.stock.bags >= row.need and "bags" or (row.missing == 0 and "have" or "missing"))
        row.gather = gatherOn and Data.Gather(row.itemID) or nil
        local name = row.name
        if row.gather and row.gather.here > 0 and row.missing > 0 then
            name = name .. " " .. Colored(L.GATHER_HERE, GREEN_FONT_COLOR)
        end
        local item = ItemRow(row.icon, name, HaveText(row.have, row.need, status))
        item.tip = MaterialTip(row)
        if gatherOn and row.missing > 0 and (row.gather or Data.CanGather(row.itemID)) then GatherButton(item, row) end
    end
end

-- Materialkosten aus dem Preis-Wissen von ezCore; mit Rezept auch Wert des Ergebnisses und Gewinn.
-- Rücksicht (Leitlinie 9, CRAFT-02/VP-68): Zeigt ein anderes Addon Kosten und Gewinn am Rezept schon (Auctionator,
-- Core.WhoHandles("craftCost")), bleiben beim Rezept nur die Kosten des Fehlenden und der Hinweis auf das Addon; der
-- Schalter „costsBeside“ gibt die Wahl zurück. Die Einkaufsliste (ohne Rezept) rechnet weiter alles.
-- AH-32: Der Gewinn rechnet nach Auktionsgebühr (Prices.Net über Data.Profit); kennt ezCore den Anteil des Hauses
-- noch nicht, heißt er „Gewinn brutto“ und eine Zeile sagt „Gebühr noch unbekannt“. Quelle und Alter stehen grau
-- darunter (Leitlinie 11): ältester Materialpreis, Preis des Ergebnisses, Gebühr mit „zuletzt gemessen am …“.
local function ValueRows(recipe, quantity, cost)
    local profit = Data.Profit(recipe, quantity, cost)
    if not profit then return nil end
    local Money = Core.Money
    if profit.kind == "net" then
        if profit.profit then
            Text(L.PANEL_VALUE_NET:format(Money(profit.gross), Money(profit.net), Money(profit.profit, nil, true)))
        else
            Text(L.PANEL_VALUE_NET_ONLY:format(Money(profit.gross), Money(profit.net)))
        end
    elseif profit.profit then
        Text(L.PANEL_VALUE_PROFIT:format(Money(profit.gross), Money(profit.profit, nil, true)))
    else
        Text(L.PANEL_VALUE:format(Money(profit.gross)))
    end
    return profit
end

local function CostRows(rows, recipe, quantity)
    if not (ns.Enabled("costs") and Data.HasPrices()) or #rows == 0 then return end
    local cost = Data.Cost(rows)
    local other = recipe and Data.CraftCostOther()
    if other then
        if cost.missing > 0 then Text(L.PANEL_COST_MISSING_ONLY:format(Core.Money(cost.missing))) end
        Text(L.PANEL_COST_OTHER:format(other), 0.6, 0.6, 0.6)
        return
    end
    if cost.unknown == #rows then
        Text(L.PANEL_COST_NONE, 0.6, 0.6, 0.6)
        return
    end
    local text = L.PANEL_COST:format(Core.Money(cost.total))
    if cost.missing > 0 and cost.missing < cost.total then text = text .. "  " .. L.PANEL_COST_MISSING:format(Core.Money(cost.missing)) end
    Text(text)
    if cost.unknown > 0 then Text(L.PANEL_COST_UNKNOWN:format(cost.unknown), 0.6, 0.6, 0.6) end
    local profit = recipe and ValueRows(recipe, quantity, cost)
    local source = Data.CostSource(cost)
    if source then Text(L.PANEL_COST_SOURCE:format(source), 0.6, 0.6, 0.6) end
    if profit then
        if profit.source then Text(L.PANEL_VALUE_SOURCE:format(profit.source), 0.6, 0.6, 0.6) end
        if profit.kind == "net" then
            local fee = L.PANEL_FEE:format(Core.Money(profit.fee))
            if profit.feeStand then fee = fee .. " (" .. profit.feeStand .. ")" end
            Text(fee, 0.6, 0.6, 0.6)
        else
            Text(L.PANEL_FEE_UNKNOWN, 0.6, 0.6, 0.6)
        end
        -- Welle 23, A3: Anzahlung (zählt nicht zum Gewinn, sie kommt beim Verkauf zurück – verloren nur bei Ablauf)
        if profit.deposit then
            local deposit = L.PANEL_DEPOSIT:format(Core.Money(profit.deposit))
            if profit.depositStand then deposit = deposit .. " (" .. profit.depositStand .. ")" end
            Text(deposit, 0.6, 0.6, 0.6)
        end
    end
end

local function StageRows(recipe)
    local otherStages = ns.Enabled("skillStages") and Data.SkillStagesOther()
    if otherStages then
        -- Rücksicht: SkillUp Forever o. Ä. zeigt die Skill-Farben schon – ezCraft nennt es nur.
        Text(L.PANEL_STAGES_OTHER:format(otherStages), 0.6, 0.6, 0.6)
        return
    end
    if not ns.Enabled("skillStages") then return end
    local stages = Data.SkillStages(recipe)
    local row = Row("item")
    row.left:SetText(L.PANEL_STAGES)
    row.right:SetText(Data.StagesText(stages))
    row.tip = function(tooltip)
        tooltip:SetText(L.PANEL_STAGES)
        local approx = false
        for _, stage in ipairs(Data.STAGES) do
            local value = stages[stage]
            local text = "?"
            if value and stages.approx[stage] then
                text, approx = L.STAGE_FROM_APPROX:format(value), true
            elseif value then
                text = L.STAGE_FROM:format(value)
            end
            -- Quelle je Stufe (Leitlinie 11, Welle 26): laut Client, bei dir beobachtet, laut Berufefenster, gerechnet
            local src = Data.StageSource(stages, stage)
            if src then text = text .. " " .. Core.Grey("(" .. src .. ")") end
            tooltip:AddDoubleLine(L["STAGE_" .. stage], text, RGB(stage))
        end
        if stages.current then
            tooltip:AddLine(L.STAGE_NOW:format(L["STAGE_" .. stages.current]), RGB(stages.current))
        elseif recipe.live and recipe.learned == false then
            -- nicht gelernt (Welle 26): die Farbe nach dem Lernen aus den Grenzen und deiner Fertigkeit
            -- Lernstufe nur, wenn sie genau ist (Lehrer, Rezept-Gegenstand, „lernbar ab“ laut Client); eine nur
            -- beobachtete ist höchstens zu hoch und ergibt weder den roten Satz noch „gelernt wäre es orange“
            local W = ns.Where
            local rank = W and W.Rank()
            local learn, rough
            if W and W.Skill and W.List then learn, rough = W.Skill(recipe.recipeID, W.List(recipe.recipeID)) end
            if rough then learn = nil end
            local at, from = Data.StageAt(stages, rank, learn)
            if at == "low" then
                ns.TipLine(tooltip, L.STAGE_IF_LEARNED_LOW:format(rank, from), "bad", true)
            elseif at then
                tooltip:AddLine(L.STAGE_IF_LEARNED:format(L["STAGE_" .. at], rank), RGB(at))
            end
        end
        -- Abweichung zwischen Beobachtung bzw. Berufefenster und Client-Tabelle: als Hinweis, nicht still überschrieben
        for _, line in ipairs(Data.StageConflicts(stages)) do ns.TipLine(tooltip, line, "warn", true) end
        if stages.sourceText then ns.TipLine(tooltip, L.STAGE_CLIENT_SOURCE:format(stages.sourceText), "hint", true) end
        if approx then ns.TipLine(tooltip, L.STAGE_APPROX, "hint", true) end
        if stages.computed and stages.computed.green then ns.TipLine(tooltip, L.STAGE_COMPUTED_GREEN, "hint", true) end
        if not Data.HasStageData(stages) or not stages.yellow then
            ns.TipLine(tooltip, L.STAGE_LEARNING, "hint", true)
        end
    end
    Advance(row)
end

-- Chance auf einen Fertigkeitspunkt (Welle 15b, Filter.lua): „Fertigkeitspunkt: etwa 40 % (gelb, berechnet)“, im
-- Tooltip der Zeile die Quelle der Zahl. Nur bei Rezepten aus dem offenen Fenster (die Farbe nennt nur der Client).
local function ChanceRow(recipe)
    if not (recipe.live and ns.Skill) then return end
    local c = ns.Skill.Chance(recipe, ns.Where.Rank())
    local text = ns.Skill.ChanceText(c)
    if not text then return end
    local row = Text(text, RGB(c.color == "white" and "gray" or c.color))
    local src = ns.Skill.SourceText(c)
    row.tip = function(tooltip)
        tooltip:SetText(L.CHANCE_HEAD)
        ns.TipLine(tooltip, text, "highlight", true)
        if src then ns.TipLine(tooltip, src, "hint", true) end
    end
end

-- Kartenknopf an einer Fundort-Zeile: öffnet Blizzards Weltkarte am Ort (Where.Show, auf Wunsch mit Wegpunkt)
local function PlaceButton(row, e)
    local zone = Core.MapName(e.map) or "?"
    local tip = L.WHERE_SHOW_TIP:format(e.name or "?", zone)
    if ns.Enabled("recipeWaypoint") then tip = tip .. "\n" .. L.WHERE_SHOW_TIP_WAY end
    local button = RowButton(row, 1, "map", tip, function() ns.Where.Show(e) end, function(self)
        Core.ShowTip(self, L.WHERE_SHOW, self.tip)
    end)
    row.left:ClearAllPoints()
    row.left:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -2)
    row.left:SetPoint("RIGHT", button, "LEFT", -4, 0)
    -- schmaler geworden: lange Zeilen brechen jetzt öfter um – Höhe neu und die folgenden Zeilen nachrücken (die Zeile
    -- kommt gerade aus Text(), ist also die zuletzt eingerechnete)
    if cur and row.left.GetStringHeight then
        local before = row:GetHeight()
        local height = math.max(ROW_H, row.left:GetStringHeight() + 4)
        if height ~= before then
            row:SetHeight(height)
            cur.cursorY = cur.cursorY + height - before
        end
    end
    return button
end
Panel.PlaceButton = PlaceButton

-- Abschnitt „Woher“ bei nicht gelernten Rezepten (Welle 15b): Fundorte aus ezCores Knowledge.RecipeWhere, je Zeile
-- mit Quelle; die Zeile mit dem besten Ort trägt den Kartenknopf „Auf der Karte zeigen“.
local function WhereRows(recipe)
    if recipe.learned ~= false or not ns.Enabled("recipeWhere") or not ns.Where.Available() then return end
    local list = ns.Where.List(recipe.recipeID)
    Header(L.WHERE_HEAD)
    if #list == 0 then
        Text(L.WHERE_NONE, 0.7, 0.7, 0.7)
        return
    end
    local best = ns.Where.Best(list)
    local shown = 0
    for _, e in ipairs(list) do
        if shown >= ns.Where.MAX_LINES then break end
        local line = ns.Where.Line(e)
        if line then
            shown = shown + 1
            local row = Text(line, e.gone and 0.6 or 0.9, e.gone and 0.6 or 0.9, e.gone and 0.6 or 0.9)
            if e == best then PlaceButton(row, e) end
            row.tip = function(tooltip)
                tooltip:SetText(L.WHERE_HEAD)
                for _, other in ipairs(list) do
                    local text = ns.Where.Line(other)
                    if text then ns.TipLine(tooltip, text, "highlight", true) end
                end
            end
        end
    end
    -- „… und 3 weitere (Tooltip der Zeile)“ – Core.More plus Zusatz (Welle 23; vorher eigener Text WHERE_MORE_LINES)
    if #list > shown then Text(Core.More(#list - shown) .. " " .. L.WHERE_MORE_HINT, 0.6, 0.6, 0.6) end
    if not best then Text(L.WHERE_NO_PLACE, 0.6, 0.6, 0.6) end
end
Panel.WhereRows = WhereRows

-- Ansicht „Rezept“ im Seitenteil: Name und Symbol zeigt Blizzard schon, ezCraft ergänzt, was dort fehlt.
local function ShowRecipe()
    local recipe = Data.Recipe(Panel.SelectedRecipeID())
    if not recipe then
        Text(L.PANEL_NO_RECIPE, 0.7, 0.7, 0.7)
        return nil
    end
    local quantity = Panel.Quantity()
    Header(quantity > 1 and L.PANEL_MATERIAL_QTY:format(quantity) or L.PANEL_MATERIAL)
    local rows, craftable = Data.Materials(recipe, quantity)
    if #rows == 0 then
        Text(L.PANEL_NO_MATERIAL, 0.7, 0.7, 0.7)
    else
        MaterialRows(rows)
        Text(L.PANEL_CRAFTABLE:format(craftable.bags, craftable.all), 0.9, 0.9, 0.9)
        CostRows(rows, recipe, quantity)
    end

    cur.cursorY = cur.cursorY + 4
    StageRows(recipe)
    ChanceRow(recipe)
    WhereRows(recipe)
    -- „Abklingzeit: du 29m, Mira bereit“ – fertige stehen da, bis der Twink das nächste Mal eingelesen wird
    local cooldowns = Data.RecipeCooldowns(recipe.recipeID, true)
    if #cooldowns > 0 then
        local parts = {}
        for _, e in ipairs(cooldowns) do
            local left = e.ready and Colored(L.CD_READY, GREEN_FONT_COLOR) or Core.Duration(e.left, true)
            parts[#parts + 1] = L.CD_PART:format(Data.CharLabel(e.char), left)
            if not e.ready then ui.ticking = true end
        end
        Text(L.PANEL_COOLDOWN:format(table.concat(parts, ", ")), 1, 0.82, 0)
    end

    Header(L.PANEL_CRAFTERS)
    local crafters = Data.Crafters(recipe)
    if crafters and #crafters > 0 then
        Text(Data.CrafterNames(crafters))
    end
    if not Data.CraftersKnown() then
        Text(L.PANEL_CRAFTERS_WAIT, 0.6, 0.6, 0.6)
    elseif not crafters or #crafters == 0 then
        Text(L.PANEL_CRAFTERS_NONE, 0.7, 0.7, 0.7)
    end

    local incoming = ns.Shipments.Incoming()
    if #incoming > 0 then
        Header(L.PANEL_INCOMING)
        for _, s in ipairs(incoming) do Text(ns.Shipments.Describe(s)) end
    end
    return recipe, rows
end

local function ShowShopping()
    local entries = ns.Shopping.Entries()
    if #entries == 0 then
        Text(L.SHOP_EMPTY_PANEL, 0.7, 0.7, 0.7)
    else
        Header(L.PANEL_SHOP_RECIPES)
        for _, entry in ipairs(entries) do
            local row = ItemRow(ns.Shopping.Icon(entry), L.SHOP_LINE_RECIPE:format(entry.count, ns.Shopping.Name(entry)), "")
            local id = entry.id
            RowButton(row, 1, "remove", L.SHOP_REMOVE_TIP, function() ns.Shopping.Remove(id) end)
            RowButton(row, 2, "plus", L.SHOP_PLUS_TIP, function() ns.Shopping.SetCount(id, entry.count + 1) end)
            local minus = RowButton(row, 3, "minus", L.SHOP_MINUS_TIP, function() ns.Shopping.SetCount(id, entry.count - 1) end)
            row.left:ClearAllPoints()
            row.left:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
            row.left:SetPoint("RIGHT", minus, "LEFT", -4, 0)
        end
        Header(L.PANEL_MATERIAL)
        local totals = ns.Shopping.Totals()
        for _, row in ipairs(totals) do
            row.status = row.stock.bags >= row.need and "bags" or (row.missing == 0 and "have" or "missing")
        end
        MaterialRows(totals)
        CostRows(totals)
    end

    local shipments = ns.Shipments.All()
    if #shipments > 0 then
        Header(L.PANEL_SHIPMENTS)
        for _, s in ipairs(shipments) do
            local row = Text(ns.Shipments.Describe(s))
            local remove = RowButton(row, 1, "remove", L.SHIP_REMOVE_TIP, function() ns.Shipments.Remove(s) end)
            row.left:SetPoint("RIGHT", remove, "LEFT", -4, 0)
        end
    end
end

-- Ansicht „Fehlend“ als Liste „Noch zu lernen“ (Welle 15b): Fundort und Stufe je Rezept, sortiert nach Erreichbarkeit
-- (jetzt lernbar, Stufe unbekannt, Fertigkeit zu niedrig; darin dein Gebiet zuerst). Rechts die Stufe, links unter dem
-- Namen der erste Fundort; Kartenknopf, wo ein Ort bekannt ist. Der Tooltip nennt alle Fundorte und Blizzards Text.
local function ShowMissing()
    local list, total, rank = ns.Where.ToLearn()
    if total == 0 then
        Text(L.MISSING_NO_WINDOW, 0.7, 0.7, 0.7)
        return
    end
    Header(L.MISSING_HEAD:format(#list, total))
    if #list == 0 then
        Text(L.MISSING_NONE, 0.7, 0.7, 0.7)
        return
    end
    for _, entry in ipairs(list) do
        local first = entry.where[1] and ns.Where.Line(entry.where[1]) or Data.SourceFirstLine(entry.source)
        local skill = ns.Where.SkillText(entry, rank)
        local color = entry.reach == 3 and RED_FONT_COLOR or (entry.reach == 1 and GREEN_FONT_COLOR or nil)
        local row = ItemRow(entry.icon, entry.name, skill and Colored(skill, color) or "")
        local best = ns.Where.Best(entry.where)
        if best then
            local button = RowButton(row, 1, "map", L.WHERE_SHOW_TIP:format(best.name or "?", Core.MapName(best.map) or "?"),
                function() ns.Where.Show(best) end, function(self) Core.ShowTip(self, L.WHERE_SHOW, self.tip) end)
            row.right:ClearAllPoints()
            row.right:SetPoint("RIGHT", button, "LEFT", -4, 0)
        end
        if first then Text("   " .. first, 0.6, 0.6, 0.6) end
        row.tip = function(tooltip)
            tooltip:SetText(entry.name)
            if skill then ns.TipLine(tooltip, L.WHERE_SKILL_LINE:format(skill), "normal") end
            for _, e in ipairs(entry.where) do
                local text = ns.Where.Line(e)
                if text then ns.TipLine(tooltip, text, "highlight", true) end
            end
            if #entry.where == 0 then ns.TipLine(tooltip, entry.source or L.MISSING_NO_SOURCE, "highlight", true) end
        end
    end
end

-- Fertige oben („Transmutation bei Mira bereit“), darunter die laufenden nach Twink gruppiert (ezCore.Professions).
local function ReadyRows(ready)
    if #ready == 0 then return end
    Header(L.CD_READY_HEAD)
    for _, item in ipairs(ready) do
        local e, name = item.entry, item.name   -- geteilte Abklingzeiten einmal (ezCores Gruppe, Welle 23 A6)
        local line = Data.ReadyCooldownLine(e, name)
        local row = ItemRow(Data.CooldownIcon(e.id), line, Colored(L.CD_READY, GREEN_FONT_COLOR))
        row.tip = function(tooltip)
            tooltip:SetText(name)
            ns.TipDoubleLine(tooltip, L.CD_READY_SINCE, Data.ReadyAtText(e.readyAt), "normal", "highlight")
            ns.TipLine(tooltip, L.CD_READY_TIP, "hint", true)
        end
    end
end

local function ShowCooldowns()
    local ready, groups = Data.ReadyCooldownsMerged(), Data.CooldownsByChar()
    if #groups == 0 and #ready == 0 then
        Text(L.CD_NONE, 0.7, 0.7, 0.7)
    end
    ReadyRows(ready)
    for _, group in ipairs(groups) do
        Header(group.label)
        for _, e in ipairs(group.list) do
            local name = Data.CooldownLabel(e)
            local row = ItemRow(Data.CooldownIcon(e.id), name, Core.Duration(e.left, true))
            row.tip = function(tooltip)
                tooltip:SetText(name)
                ns.TipDoubleLine(tooltip, L.CD_READY_AT, Data.ReadyAtText(e.readyAt), "normal", "highlight")
                ns.TipDoubleLine(tooltip, L.CD_LEFT, Core.Duration(e.left), "normal", "highlight")
            end
        end
    end
    cur.cursorY = cur.cursorY + 6
    Text(L.CD_HINT, 0.6, 0.6, 0.6)
    ui.ticking = #groups > 0
end

-- Symbol „Entzaubern“ an einer Zeile (CRAFT-09). Zeigt die Maus darauf, legt ezCraft außerhalb des Kampfes ezCores
-- sicheren Knopf darüber (ns.Salvage.Arm) – der nimmt den Klick an und entzaubert genau diesen Gegenstand. Im Kampf
-- ist das Symbol ausgegraut (aus, aber mit Tooltip: SetMotionScriptsWhileDisabled in RowButton), der Tooltip sagt warum.
local function DisenchantButton(row, entry)
    local Sal = ns.Salvage
    local function Enter(self)
        if not Core.InCombat() then Sal.Arm(self, entry) end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        Sal.ClickTip(GameTooltip, entry)
        GameTooltip:Show()
    end
    local tip = L.SALVAGE_CLICK_TIP:format(entry.name or "?", entry.bag, entry.slot)   -- Enter zeigt ihn (Sal.ClickTip)
    local button = RowButton(row, 2, "disenchant", tip, function(self)
        if Core.InCombat() then
            Core.CombatNotice(ns, L.SALVAGE_WHAT)   -- ein Satz zur Kampfsperre (T18-1)
        else
            Sal.Arm(self, entry)   -- der sichere Knopf liegt jetzt darüber; der nächste Klick entzaubert
        end
    end, Enter)
    button.entry = entry
    if Core.InCombat() then
        button:SetEnabled(false)
        local normal = button.GetNormalTexture and button:GetNormalTexture()
        if normal and normal.SetDesaturated then normal:SetDesaturated(true) end
    end
    return button
end

-- Ausrüstung in der Tasche, die sich entzaubern lässt (ezCore.Salvage): wertvollstes zuerst; das x ignoriert.
local function ShowSalvage()
    local Sal = ns.Salvage
    local list, skipped = Sal.Candidates()
    if #list == 0 then
        Text(L.SALVAGE_NONE, 0.7, 0.7, 0.7)
    else
        Header(L.SALVAGE_HEAD:format(#list))
        for _, entry in ipairs(list) do
            local info = entry.info
            local value = info.value and L.SALVAGE_VALUE:format(Core.Money(info.value)) or Core.Grey(L.SALVAGE_PRICE_UNKNOWN)
            local row = ItemRow(entry.icon, entry.name, value)
            RowButton(row, 1, "remove", L.SALVAGE_IGNORE_TIP, function() Sal.Ignore(entry.itemID) end)
            local click = DisenchantButton(row, entry)
            row.right:ClearAllPoints()
            row.right:SetPoint("RIGHT", click, "LEFT", -4, 0)
            row.tip = function(tooltip)
                tooltip:SetText(entry.name)
                ns.TipLine(tooltip, L.SALVAGE_ROW_BAG:format(entry.bag, entry.slot), "hint")
                ns.TipLines(tooltip, (Sal.Lines(entry.link or entry.itemID)))
            end
        end
    end
    if skipped > 0 then Text(L.SALVAGE_SKIPPED:format(skipped), 0.6, 0.6, 0.6) end
    cur.cursorY = cur.cursorY + 6
    Text(Core.L.SALVAGE_UNVERIFIED, 0.6, 0.6, 0.6)
    Text(L.SALVAGE_HOW:format(L.SALVAGE_TITLE), 0.6, 0.6, 0.6)
end

---------------------------------------------------------------------------
-- Knopfleiste unten im Seitenteil (je Ansicht andere Knöpfe)
---------------------------------------------------------------------------

local function SetButton(index, text, onClick, tip, enabled)
    local button = ui.buttons[index]
    if not button then return end
    if not text then
        button:Hide()
        return
    end
    button:SetText(text)
    button.tip = tip
    button:SetScript("OnClick", onClick)
    button:SetEnabled(enabled ~= false)
    button:Show()
end

local function RequestNeeds(needs, note)
    local count, rest = ns.Shipments.Request(needs, note)
    local restCount = 0
    for _ in pairs(rest) do restCount = restCount + 1 end
    if count > 0 then
        ns.Print(L.SHIP_REQUESTED:format(count))
    elseif restCount == 0 then
        ns.Print(L.SHIP_NOTHING_NEEDED)
    end
    if restCount > 0 then ns.Print(L.SHIP_REST:format(ns.Shipments.ItemsText(rest))) end
end

local function UpdateButtons(tab, recipe, rows)
    if tab == "recipe" then
        SetButton(1, L.BTN_ADD_SHOPPING, function()
            local r = Data.Recipe(Panel.SelectedRecipeID())
            local ok, count = ns.Shopping.Add(r, Panel.Quantity())
            if ok then ns.Print(L.SHOP_ADDED:format(r.name, count)) end
        end, L.BTN_ADD_SHOPPING_TIP, recipe ~= nil and #(recipe.reagents or {}) > 0)
        local needs = rows and Data.MissingInBags(rows) or {}
        SetButton(2, L.BTN_REQUEST, function()
            local r = Data.Recipe(Panel.SelectedRecipeID())
            local current = Data.Materials(r, Panel.Quantity())
            RequestNeeds(Data.MissingInBags(current), r and r.name)
        end, L.BTN_REQUEST_TIP, next(needs) ~= nil)
        local auction = ns.Shopping.AuctionFunction() ~= nil
        local lacking = false
        for _, row in ipairs(rows or {}) do
            if row.missing > 0 then lacking = true end
        end
        SetButton(3, L.BTN_AUCTION, function()
            ns.Shopping.SendRecipeToAuction(Data.Recipe(Panel.SelectedRecipeID()), Panel.Quantity())
        end, auction and L.BTN_AUCTION_RECIPE_TIP or L.BTN_AUCTION_MISSING_TIP, auction and lacking)
    elseif tab == "shopping" then
        local hasList = #ns.Shopping.Entries() > 0
        local auction = ns.Shopping.AuctionFunction() ~= nil
        SetButton(1, L.BTN_AUCTION, function() ns.Shopping.SendToAuction() end,
            auction and L.BTN_AUCTION_TIP or L.BTN_AUCTION_MISSING_TIP, hasList and auction)
        SetButton(2, L.BTN_REQUEST, function() RequestNeeds(ns.Shopping.BagNeeds(), L.SHIP_SHOPPING_NOTE) end,
            L.BTN_REQUEST_SHOP_TIP, hasList)
        SetButton(3, L.BTN_CLEAR, function()
            ns.Shopping.AskClear()
        end, L.BTN_CLEAR_TIP, hasList)
    elseif tab == "cooldowns" then
        SetButton(1, L.BTN_REFRESH, function()
            Data.ScanCooldowns()
            Panel.Refresh()
        end, L.BTN_CD_REFRESH_TIP)
        SetButton(2, nil)
        SetButton(3, nil)
    elseif tab == "salvage" then
        SetButton(1, L.BTN_REFRESH, function() Panel.Refresh() end, L.BTN_SALVAGE_REFRESH_TIP)
        SetButton(2, L.BTN_SALVAGE_RESET, function()
            ns.Print(L.SALVAGE_RESET_DONE:format(ns.Salvage.ClearIgnored()))
        end, L.BTN_SALVAGE_RESET_TIP, ns.Salvage.IgnoredCount() > 0)
        SetButton(3, nil)
    else
        SetButton(1, L.BTN_REFRESH, function()
            Data.InvalidateMissing()
            Panel.Refresh()
        end, L.BTN_REFRESH_TIP)
        SetButton(2, nil)
        SetButton(3, nil)
    end
end

---------------------------------------------------------------------------
-- Rundgang mit Erklärblasen (Core.NewTour): beim ersten Öffnen des Berufefensters die wichtigsten Funktionen.
-- Eine Blase nach der anderen; was gerade nicht zu sehen ist (Seitenteil zu, andere Ansicht, Fenster zu), kommt
-- später dran. Eigene Schlüssel für das Seitenteil (Welle 6): wer den Rundgang von 1.5 kannte, sieht den neuen einmal.
-- Die Seite der Blasen richtet sich nach der Seite des Seitenteils (SetTourSides): der Pfeil nach außen, der Inhalt
-- zum Berufefenster hin, Knöpfe und Reiter innerhalb des Seitenteils.
---------------------------------------------------------------------------

local function OnRecipeView(widget)
    return function() return Tab() == "recipe" and widget() or nil end
end

local TOUR_STEPS = {
    { key = "side.arrow", target = function() return ui.side and ui.side.arrow end, text = L.TOUR_ARROW, side = "right" },
    { key = "side.material", target = OnRecipeView(function() return ui.target and ui.target.scroll end), text = L.TOUR_MATERIAL, side = "left" },
    { key = "side.shopping", target = OnRecipeView(function() return ui.buttons[1] end), text = L.TOUR_SHOPPING, side = "above" },
    { key = "side.request", target = OnRecipeView(function() return ui.buttons[2] end), text = L.TOUR_REQUEST, side = "above" },
    -- Seite „Berufe“ (Nr. 22): dort gibt es kein „Rezept“ und keine Rückkehr dorthin, von denen TOUR_TABS spricht
    { key = "side.tabs", target = function() return not OnBook() and ui.tabs.shopping or nil end, text = L.TOUR_TABS, side = "below" },
}

-- Gemerkt wird in ezCraftDB.hints (wie bisher); den Speicher stellt ezCores Rundgang-Starter (owner, field).
Panel.tour = Core.NewTour({
    owner = ns,
    field = "hints",
    okay = L.HINT_OK,
    steps = TOUR_STEPS,
})

local function SetTourSides()
    local left = ui.side and ui.side.side == "left"
    -- offen sitzt der Pfeil in der äußeren Ecke des Seitenteils: die Blase darunter, sonst ragte sie aus dem Bildschirm
    local open = ui.side and ui.side:IsOpen()
    TOUR_STEPS[1].side = open and "below" or (left and "left" or "right")
    TOUR_STEPS[2].side = left and "right" or "left"
end

-- off: ezCraft im Berufefenster abgeschaltet (Schalter „panel“) – dann keine Blase.
local function StartTour(off)
    local tour = Panel.tour
    SetTourSides()
    local current = not off and tour:Start(Professions()) or nil
    for _, step in ipairs(tour.steps) do
        if step.key ~= current then tour.hints.Hide(step.key) end
    end
    return current
end

---------------------------------------------------------------------------
-- Aufbau
---------------------------------------------------------------------------

local function SelectTab(key)
    if not ns.db then return end
    ns.db.window.tab = key
    Panel.Refresh()
end

-- Reiterzeile im Seitenteil: ein abgeschalteter Reiter hinterlässt keine Lücke, der gewählte ist gedrückt.
local function UpdateTabs()
    local current, x, shown = Tab(), 10, 0
    for _, key in ipairs(TAB_KEYS) do
        local tab = ui.tabs[key]
        local visible = TabAvailable(key)
        tab:SetShown(visible)
        tab:SetChecked(key == current)
        if visible then
            tab:ClearAllPoints()
            tab:SetPoint("TOPLEFT", ui.side, "TOPLEFT", x, -TOP_ROOM - 2)
            x = x + TAB_SIZE + TAB_GAP
            shown = shown + 1
        end
    end
    local count = ns.Shopping and #ns.Shopping.Entries() or 0
    if ui.tabs.shopping.Count then ui.tabs.shopping.Count:SetText(count > 0 and count or "") end
    return shown
end

-- Hintergrund des offenen Berufs ins Seitenteil übernehmen (nur gelesen).
local function SyncViewArt()
    if OnBook() then   -- Seite „Berufe“: kein offener Beruf, dessen Hintergrund passte
        ui.side.Art:Hide()
        return
    end
    local form = SchematicForm()
    local bg = form and form.Background
    local atlas = type(bg) == "table" and bg.GetAtlas and Core.Call(bg.GetAtlas, bg)
    if type(atlas) == "string" and atlas ~= "" and ui.side.Art.SetAtlas then
        ui.side.Art:SetAtlas(atlas)
        ui.side.Art:Show()
    else
        ui.side.Art:Hide()
    end
end

local function CreateTabs(side)
    for _, key in ipairs(TAB_KEYS) do
        local tab = CreateFrame("CheckButton", nil, side)
        tab:SetSize(TAB_SIZE, TAB_SIZE)
        tab.Icon = tab:CreateTexture(nil, "ARTWORK")
        tab.Icon:SetAllPoints()
        tab.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        Core.SetIcon(tab.Icon, nil, VIEW_ICONS[key])
        tab:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        tab:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight", "ADD")
        tab.Count = tab:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        tab.Count:SetPoint("BOTTOMRIGHT", -1, 2)
        tab.key = key
        tab:SetScript("OnClick", function(self)
            Core.PlaySound("IG_CHARACTER_INFO_TAB")
            -- nochmal klicken führt zurück zum Rezept (auf der Seite „Berufe“ gibt es keins)
            local back = not OnBook() and (Tab() == self.key or self.key == "recipe")
            SelectTab(back and "recipe" or self.key)
        end)
        tab:SetScript("OnEnter", function(self)
            local body = L["TAB_" .. key .. "_TIP"]
            if key ~= "recipe" and not OnBook() then body = body .. "\n\n" .. L.VIEW_TAB_CLICK end
            Core.ShowTip(self, L["TAB_" .. key], body)
        end)
        tab:SetScript("OnLeave", GameTooltip_Hide)
        ui.tabs[key] = tab
    end
end

local function CreateButtons(side)
    for index = 1, 3 do
        -- Blizzards Vorlage der Herstellen-Knöpfe im Forever-Berufefenster (SharedButtonSmallTemplate)
        local ok, button = pcall(CreateFrame, "Button", "ezCraftButton" .. index, side, "SharedButtonSmallTemplate")
        if not (ok and button) then
            ok, button = pcall(CreateFrame, "Button", "ezCraftButton" .. index, side, "UIPanelButtonTemplate")
            if not (ok and button) then button = CreateFrame("Button", "ezCraftButton" .. index, side) end
        end
        button:SetSize(BUTTON_W, BUTTON_H)
        if index == 1 then
            button:SetPoint("BOTTOMLEFT", side, "BOTTOMLEFT", 8, 10)
        else
            button:SetPoint("LEFT", ui.buttons[index - 1], "RIGHT", BUTTON_GAP, 0)
        end
        button:SetScript("OnEnter", function(self)
            if self.tip then Core.ShowTip(self, self:GetText() or "", self.tip, "ANCHOR_TOP") end
        end)
        button:SetScript("OnLeave", GameTooltip_Hide)
        if button.SetMotionScriptsWhileDisabled then button:SetMotionScriptsWhileDisabled(true) end   -- Tooltip auch, wenn aus
        button:Hide()
        ui.buttons[index] = button
    end
    -- „Aus der Bank holen (n)“ (NEU-01): eigene Zeile über der Knopfleiste, nur im Reiter „Einkaufsliste“ bei offener
    -- Bank bzw. Gildenbank und laufendem ezBag (UpdateWithdraw)
    local ok, wide = pcall(CreateFrame, "Button", "ezCraftWithdrawButton", side, "SharedButtonSmallTemplate")
    if not (ok and wide) then
        ok, wide = pcall(CreateFrame, "Button", "ezCraftWithdrawButton", side, "UIPanelButtonTemplate")
        if not (ok and wide) then wide = CreateFrame("Button", "ezCraftWithdrawButton", side) end
    end
    wide:SetSize(3 * BUTTON_W + 2 * BUTTON_GAP, BUTTON_H)
    wide:SetPoint("BOTTOMLEFT", side, "BOTTOMLEFT", 8, 10 + BUTTON_H + BUTTON_GAP)
    wide:SetScript("OnClick", function() ns.Shopping.Withdraw() end)
    wide:SetScript("OnEnter", function(self) Panel.WithdrawTip(self) end)
    wide:SetScript("OnLeave", GameTooltip_Hide)
    -- „nichts dort“ schaltet den Knopf aus – der Tooltip sagt dann, warum (WITHDRAW_NOTHING)
    if wide.SetMotionScriptsWhileDisabled then wide:SetMotionScriptsWhileDisabled(true) end
    wide:Hide()
    ui.withdraw = wide
end

-- Tooltip von „Aus der Bank holen“: was ein Klick holen würde (je Material), sonst warum nichts.
function Panel.WithdrawTip(owner)
    local _, rows = ns.Shopping.FromBank()
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:SetText(L.BTN_WITHDRAW_TITLE)
    ns.TipLine(GameTooltip, L.BTN_WITHDRAW_TIP, "highlight", true)
    if #rows == 0 then
        ns.TipLine(GameTooltip, L.WITHDRAW_NOTHING, "hint", true)
    else
        GameTooltip:AddLine(" ")
        for _, row in ipairs(rows) do
            ns.TipDoubleLine(GameTooltip, row.name, L.WITHDRAW_COUNT:format(row.count, row.lack), "highlight", "normal")
        end
    end
    local _, guild = ns.Shopping.BankOpen()
    if guild then ns.TipLine(GameTooltip, L.BTN_WITHDRAW_GUILD, "hint", true) end
    GameTooltip:Show()
end

-- Knopf „Aus der Bank holen (n)“ zeigen oder verstecken; der Inhalt weicht ihm nach oben.
local function UpdateWithdraw(tab)
    local wide = ui.withdraw
    if not wide then return end
    local show = tab == "shopping" and ns.Shopping.CanWithdraw()
    local bottom = CONTENT_BOTTOM
    if show then
        local _, rows = ns.Shopping.FromBank()
        wide:SetText(L.BTN_WITHDRAW:format(#rows))
        wide:SetEnabled(#rows > 0)
        wide:Show()
        bottom = CONTENT_BOTTOM + BUTTON_H + BUTTON_GAP
    else
        wide:Hide()
    end
    ui.target.scroll:SetPoint("BOTTOMRIGHT", ui.side, "BOTTOMRIGHT", -28, bottom)
end

local function OnTick(_, elapsed)
    if not ui.ticking then return end
    ui.elapsed = ui.elapsed + (elapsed or 0)
    if ui.elapsed >= TICK then
        ui.elapsed = 0
        Panel.Refresh()
    end
end

-- Das Seitenteil (Core.NewSidePanel): Überschrift, Reiterzeile, Überschrift der Ansicht mit X, Inhalt, Knopfleiste.
local function CreateSide(pf)
    local side = Core.NewSidePanel(pf, {
        name = "ezCraftSide", width = Panel.SIDE_W, gap = Panel.SIDE_GAP, owner = ADDON,
        store = ns.db and ns.db.window, key = "open", open = true,
        tip = L.SIDE_TITLE, tipBody = L.SIDE_ARROW_TIP,
        onToggle = function() Panel.Refresh() end,
        onPlaced = function() Panel.RefreshSoon() end,
    })
    if not side then return nil end
    side.Art = side:CreateTexture(nil, "BACKGROUND", nil, 1)
    side.Art:SetPoint("TOPLEFT", side, "TOPLEFT", 3, -3)
    side.Art:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", -3, 3)
    side.Art:SetAlpha(0.6)
    side.Art:Hide()
    -- Überschrift „ezCraft“ in Blizzards Gold, mittig (links und rechts bleibt Platz für den Pfeil)
    side.Title = CreateFrame("Button", nil, side)
    side.Title:SetHeight(20)
    side.Title:SetPoint("TOPLEFT", side, "TOPLEFT", Core.SIDEPANEL_ARROW_ROOM + 4, -8)
    side.Title:SetPoint("TOPRIGHT", side, "TOPRIGHT", -Core.SIDEPANEL_ARROW_ROOM - 4, -8)
    side.Title.Text = side.Title:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    side.Title.Text:SetPoint("CENTER", side.Title, "CENTER", 0, 0)
    side.Title.Text:SetText(L.TITLE)
    side.Title:SetScript("OnEnter", Core.TipScript(L.TITLE, L.SIDE_TITLE_TIP))
    side.Title:SetScript("OnLeave", GameTooltip_Hide)
    CreateTabs(side)
    -- Überschrift der Ansicht mit feiner Linie, X führt zurück zum Rezept
    -- Schrift wie Blizzards Rezept-Überschrift (OutputText inherits="GameFontHighlightMed2" in
    -- Blizzard_ProfessionsTemplates/Blizzard_ProfessionsRecipeSchematicForm.xml, Zweig forever): Nachbild eines
    -- Blizzard-Teils, darum außerhalb der Rollen von Core.Style.FONT (Design-System 2.4)
    side.ViewTitle = side:CreateFontString(nil, "ARTWORK", "GameFontHighlightMed2")
    side.ViewTitle:SetPoint("TOPLEFT", side, "TOPLEFT", 12, -TOP_ROOM - TAB_SIZE - 12)
    side.Line = side:CreateTexture(nil, "ARTWORK")
    side.Line:SetHeight(1)
    side.Line:SetColorTexture(1, 0.82, 0, 0.3)
    side.Line:SetPoint("TOPLEFT", side, "TOPLEFT", 10, -CONTENT_TOP + 6)
    side.Line:SetPoint("TOPRIGHT", side, "TOPRIGHT", -10, -CONTENT_TOP + 6)
    local ok, close = pcall(CreateFrame, "Button", nil, side, "UIPanelCloseButton")
    side.ViewClose = ok and close or CreateFrame("Button", nil, side)
    side.ViewClose:SetPoint("TOPRIGHT", side, "TOPRIGHT", -4, -TOP_ROOM - TAB_SIZE - 2)
    side.ViewClose:SetScript("OnClick", function() SelectTab("recipe") end)
    side.ViewClose:SetScript("OnEnter", Core.TipScript(L.VIEW_CLOSE, L.VIEW_CLOSE_TIP))
    side.ViewClose:SetScript("OnLeave", GameTooltip_Hide)
    ui.target = NewTarget(side)
    ui.target.scroll:SetPoint("TOPLEFT", side, "TOPLEFT", 10, -CONTENT_TOP)
    ui.target.scroll:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", -28, CONTENT_BOTTOM)
    CreateButtons(side)
    -- Restzeiten (Abklingzeiten) laufen weiter, solange sie zu sehen sind.
    side:SetScript("OnUpdate", OnTick)
    -- Seitenteil zu: der sichere Knopf „Entzaubern“ darf nicht über einer unsichtbaren Zeile stehen bleiben.
    side:HookScript("OnHide", function() if ns.Salvage then ns.Salvage.Disarm() end end)
    side.arrow:SetScript("OnEnter", function(self)
        Core.ShowTip(self, ui.side:IsOpen() and L.SIDE_CLOSE or L.SIDE_OPEN, L.SIDE_ARROW_TIP)
    end)
    return side
end

local function Create()
    local pf = Professions()
    if ui.side then return true end
    if not (pf and CraftingPage()) then return false end
    ui.side = CreateSide(pf)
    if not ui.side then return false end
    -- Blasen zu Teilen im Seitenteil schließen mit ihm (die zum Pfeil hängt am Berufefenster).
    for _, step in ipairs(TOUR_STEPS) do
        if step.key ~= "side.arrow" then step.parent = ui.side end
    end
    return true
end

---------------------------------------------------------------------------
-- Sichtbarkeit und Aktualisieren
---------------------------------------------------------------------------

local function IsOn()
    return ns.Enabled("panel") and (CraftingShown() or OnBook())
end

-- Ist ezCraft gerade im Berufefenster zu sehen (Seitenteil offen)?
function Panel.IsOpen() return ui.side ~= nil and IsOn() and ui.side:IsOpen() end

-- Seitenteil auf- oder zuklappen (Pfeil, /ezcraft fenster). Ohne Berufefenster nur den Zustand merken.
-- → true, wenn es jetzt offen ist.
function Panel.SetOpen(open)
    open = open and true or false
    if ui.side then
        if open then ui.side:Open() else ui.side:Close() end
    elseif ns.db then
        ns.db.window.open = open
    end
    return open
end

function Panel.Toggle()
    local open
    if ui.side then open = ui.side:IsOpen() else open = not (ns.db and ns.db.window.open == false) end
    return Panel.SetOpen(not open)
end

-- Derselbe Gegenstand am selben Platz?
local function SameEntry(a, b)
    return a and b and a.bag == b.bag and a.slot == b.slot and a.itemID == b.itemID
end

-- Nach dem Neuzeichnen: Lag der sichere Knopf vorher über einer Zeile (prev) und zeigt die Maus noch auf das Symbol
-- „Entzaubern“ DESSELBEN Gegenstands, den Knopf wieder darüberlegen. Zeigt die Zeile jetzt etwas anderes (die Zeilen
-- werden wiederverwendet; nach einem Klick rückt der nächste Gegenstand nach), bleibt er gelöst – scharf wird er erst,
-- wenn die Maus neu auf das Symbol zeigt. Nach einem Klick ist prev nil (PostClick entschärft).
local function RearmUnderMouse(prev)
    if not prev then return false end
    local rows, used = ui.target.rows, ui.target.used
    for i = 1, used do
        local button = rows[i].buttons[2]
        if button and button:IsShown() and button.kind == "disenchant" and button.entry
            and button.IsMouseOver and button:IsMouseOver() then
            if not SameEntry(button.entry, prev.entry) then return false end
            ns.Salvage.Arm(button, button.entry)
            return true
        end
    end
    return false
end

function Panel.Refresh()
    local side = ui.side
    if not side then return end
    -- Der sichere Knopf „Entzaubern“ gehört zu einer Zeile, die gleich neu belegt wird: erst lösen (CRAFT-09).
    local armedBefore = ns.Salvage and ns.Salvage.Armed()
    if ns.Salvage then ns.Salvage.Disarm() end
    local on = IsOn()
    side.arrow:SetShown(on)
    if not on then
        side:Hide()
        if ns.db then StartTour(true) end
        return
    end
    side:SetShown(side:IsOpen())
    if not side:IsOpen() then
        ui.ticking = false
        if ns.db then StartTour() end
        return
    end
    local tab = Tab()
    UpdateTabs()
    SyncViewArt()
    side.ViewTitle:SetText(L["TAB_" .. tab])
    side.ViewClose:SetShown(tab ~= "recipe" and not OnBook())
    ui.ticking = false
    local recipe, rows
    BeginRows(ui.target)
    -- Kein Platz neben dem Berufefenster: ezCore legt das Seitenteil innen darüber – das Seitenteil sagt es.
    if side.mode == "overlap" then Text(L.SIDE_OVERLAP, 1, 0.3, 0.3) end
    if tab == "recipe" then
        recipe, rows = ShowRecipe()
    elseif tab == "shopping" then
        ShowShopping()
    elseif tab == "cooldowns" then
        ShowCooldowns()
    elseif tab == "salvage" then
        ShowSalvage()
        if not Core.InCombat() then RearmUnderMouse(armedBefore) end
    else
        ShowMissing()
    end
    EndRows()
    UpdateButtons(tab, recipe, rows)
    UpdateWithdraw(tab)
    if ns.db then StartTour() end
end

Panel.UpdateVisibility = Panel.Refresh

local RefreshSoon = ns.Throttle(function() Panel.Refresh() end, 0.15)
Panel.RefreshSoon = RefreshSoon

-- Für die Tests und /ezcraft status: was gerade im Seitenteil steht.
function Panel.Lines()
    local lines = {}
    local target = ui.target
    if not target then return lines end
    for i = 1, target.used do
        local row = target.rows[i]
        local text = row.left:GetText() or ""
        local right = row.right:GetText() or ""
        lines[#lines + 1] = right ~= "" and (text .. " | " .. right) or text
    end
    return lines
end
function Panel.Side() return ui.side end
-- Weiterleitungen aus der Zeit vor dem Seitenteil (Abschnitt im Rezeptfeld, Ansicht darüber): beides ist jetzt das
-- Seitenteil.
function Panel.Info() return ui.side end
function Panel.View() return ui.side end
function Panel.Buttons() return ui.buttons end
function Panel.Tabs() return ui.tabs end
function Panel.Tab() return Tab() end
function Panel.Rows()
    local target = ui.target
    if not target then return {}, 0 end
    return target.rows, target.used
end

---------------------------------------------------------------------------
-- Anbindung an Blizzards Berufefenster
---------------------------------------------------------------------------

-- Ein Rezept in Blizzards Liste gewählt: zurück zur Rezeptansicht. Das Rezept zählt als „zuletzt angesehen“ (sein
-- Material meldet ezCraft bei ezCore zum Beobachten an, AH-39); Blizzards Stern (favorite) wird mitgemerkt. Ein
-- fremdes Berufefenster (Link, Gilde, NPC-Werkbank) übergeht Data.NoteViewed selbst.
local function OnRecipeSelected(_, recipeInfo)
    local id = type(recipeInfo) == "table" and Core.Num(recipeInfo.recipeID)
    if id then
        selectedRecipeID = id
        local favorite = Core.Plain(recipeInfo.favorite)
        if type(favorite) ~= "boolean" then favorite = nil end
        Data.NoteViewed(id, favorite)
    end
    if ns.db then ns.db.window.tab = "recipe" end
    RefreshSoon()
end

local function Attach()
    local pf = Professions()
    if not pf or ui.side then return end
    if not Create() then return end
    -- Beim Öffnen des Berufefensters immer das Rezept (eine Ansicht von vorhin passt selten zum neuen Beruf).
    pf:HookScript("OnShow", function()
        if ns.db then ns.db.window.tab = "recipe" end
        Panel.Refresh()
    end)
    pf:HookScript("OnHide", Panel.Refresh)
    local page = CraftingPage()
    page:HookScript("OnShow", Panel.Refresh)
    page:HookScript("OnHide", Panel.Refresh)
    -- Seite „Berufe“ (Nr. 22): Seitenteil ohne Rezeptbezug
    local book = BookPage()
    if type(book) == "table" and type(book.HookScript) == "function" then
        book:HookScript("OnShow", Panel.Refresh)
        book:HookScript("OnHide", Panel.Refresh)
    end
    local box = page.CreateMultipleInputBox
    if box and box.HookScript then box:HookScript("OnTextChanged", RefreshSoon) end
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("ProfessionsRecipeListMixin.Event.OnRecipeSelected", OnRecipeSelected, Panel)
        EventRegistry:RegisterCallback("Professions.ProfessionSelected", function()
            selectedRecipeID = nil
            Data.InvalidateMissing()   -- anderer Beruf: andere Rezepte
            RefreshSoon()
        end, ui)
    end
    Panel.Refresh()
end

ns.OnReady(function()
    ns.WhenAddOnLoaded("Blizzard_Professions", Attach)
end)

local function RefreshIfOpen()
    if Panel.IsOpen() then RefreshSoon() end
end

ns.On("TRADE_SKILL_LIST_UPDATE", RefreshIfOpen)
ns.On("TRADE_SKILL_SHOW", function() RefreshSoon() end)
ns.On("GET_ITEM_INFO_RECEIVED", RefreshIfOpen)
Core.Listen("INVENTORY_CHANGED", RefreshIfOpen, ADDON)
Core.Listen("GUILDBANK_CHANGED", RefreshIfOpen, ADDON)
Core.Listen("PRICES_CHANGED", RefreshIfOpen, ADDON)
Core.Listen("PRICES_SCAN_DONE", RefreshIfOpen, ADDON)
Core.Listen("PROF_COOLDOWNS_CHANGED", RefreshIfOpen, ADDON)
Core.Listen("OTHER_ADDONS_CHANGED", RefreshIfOpen, ADDON)   -- ein Addon meldet später, was es übernimmt (craftCost)
ns.On("ZONE_CHANGED_NEW_AREA", RefreshIfOpen)      -- „hier sammelbar“ hängt am Gebiet
Core.Listen("GATHERING_CHANGED", RefreshIfOpen, ADDON)   -- Fundorte vergessen oder zusammengelegt (SAM-24)
ns.Listen("SHOPPING_CHANGED", function() RefreshSoon() end)
ns.Listen("SHIPMENTS_CHANGED", RefreshIfOpen)
ns.Listen("SALVAGE_CHANGED", RefreshIfOpen)
-- Kampfbeginn und -ende: das Symbol „Entzaubern“ je Zeile aus- bzw. wieder einschalten (gebündelt – beim Ereignis
-- PLAYER_REGEN_DISABLED selbst gilt die Kampfsperre noch nicht)
ns.On("PLAYER_REGEN_DISABLED", RefreshIfOpen)
ns.On("PLAYER_REGEN_ENABLED", RefreshIfOpen)
-- „Aus der Bank holen“ (NEU-01) hängt an offener Bank bzw. Gildenbank
Core.Listen("BANK_OPENED", RefreshIfOpen, ADDON)
Core.Listen("BANK_CLOSED", RefreshIfOpen, ADDON)
ns.On("GUILDBANKFRAME_OPENED", RefreshIfOpen)
ns.On("GUILDBANKFRAME_CLOSED", RefreshIfOpen)
ns.OnSettingChanged(function() Panel.Refresh() end)
