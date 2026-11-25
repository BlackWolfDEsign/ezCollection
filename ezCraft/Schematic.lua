local ADDON, ns = ...
local L = ns.L
local Core = ezCore
local Data = ns.Data

--[[
    ezCraft in Blizzards Rezeptbereich (ProfessionsFrame.CraftingPage.SchematicForm) – Spieltest vom 21.11.2026 mit
    Bildschirmfoto (zwei rote Kästchen links neben Blizzards „Rezept listen“). Wünsche des Nutzers, wörtlich:
    „zudem sollten bild 2 rote kästchen "auf die liste" "auktionshaus" sein“, „das Rezepte von ezCraft soll direkt in das
    original blizz anzeige rezept gebaut werden gerne mit materialkosten und gewinn im ah, der rest aus dem ezcraft
    rezepte ist uninteressant“, „„Auf die Liste" reicht da rechts die entsprechende liste ausgewählt werden kann“;
    zum Auktionshaus gewählt: „Nein, sofort suchen (Empfohlen)“. Leitlinie 1: Blizzards Fenster erweitern.

      Kostenzeile     „Material 65s (fehlt 11s) · Auktionshaus 91s · Gewinn 26s“ über den Knöpfen; der Tooltip nennt
                      alle Zeilen aus Panel.CostLines (Gebühr, Anzahlung, Quelle und Alter der Preise – Leitlinie 11)
      Auf die Liste   setzt das Rezept mit der Menge aus Blizzards Feld „Herstellen“ auf die Liste, die rechts im
                      Seitenteil gewählt ist (ns.Shopping.Add), und zeigt sie dort
      Auktionshaus    sucht bei offenem Auktionshaus sofort jede Zutat (Menge: was der Tasche fehlt) (ns.Shopping.SendRecipeToAuction über
                      ezAuctions API.SearchItems) – ohne eine Liste zu speichern; bei geschlossenem merkt er es vor,
                      beim Öffnen des Auktionshauses wird gesucht (ns.Shopping.TogglePending, Entscheidung vom
                      21.11.2026 „Vormerken (Empfohlen)“)

    Nur gelesen bzw. eigene Kinder am Rezeptbereich (Leitlinie 5): Blizzards Rahmen bleiben unverändert; die Knöpfe
    hängen links an Blizzards „Rezept listen“ (TrackRecipeCheckbox).
]]

local Sch = {}
ns.Schematic = Sch

Sch.BUTTON_W, Sch.BUTTON_H, Sch.GAP = 110, 22, 4
local ui = {}

local function NewButton(form, name, text)
    -- dieselbe Vorlage wie Blizzards Knopf „Gildenhandwerker“ im Berufefenster (UIPanelButtonTemplate)
    local ok, button = pcall(CreateFrame, "Button", name, form, "UIPanelButtonTemplate")
    if not (ok and button) then button = CreateFrame("Button", name, form) end
    button:SetSize(Sch.BUTTON_W, Sch.BUTTON_H)
    button:SetText(text)
    button:SetScript("OnEnter", function(self)
        if self.tip then Core.ShowTip(self, self:GetText() or "", self.tip, "ANCHOR_TOP") end
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    if button.SetMotionScriptsWhileDisabled then button:SetMotionScriptsWhileDisabled(true) end   -- Tooltip auch aus
    button:Hide()
    return button
end

-- Tooltip der Kostenzeile: alle Zeilen aus Panel.CostLines
local function LineTip(self)
    if not self.lines then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(L.RECIPE_LINE_TITLE)
    for _, line in ipairs(self.lines) do ns.TipLine(GameTooltip, line.text, line.grey and "hint" or "highlight", true) end
    GameTooltip:Show()
end

function Sch.Create()
    if ui.add then return true end
    local form = ns.Panel and ns.Panel.SchematicForm()
    if type(form) ~= "table" then return false end
    ui.form = form
    ui.add = NewButton(form, "ezCraftRecipeAddButton", L.BTN_ADD_SHOPPING)
    ui.auction = NewButton(form, "ezCraftRecipeAuctionButton", L.BTN_AUCTION)
    local track = Core.Peek(form, "TrackRecipeCheckbox")
    if type(track) == "table" then
        ui.auction:SetPoint("RIGHT", track, "LEFT", -6, 0)
    else
        ui.auction:SetPoint("BOTTOMRIGHT", form, "BOTTOMRIGHT", -150, 12)
    end
    ui.add:SetPoint("RIGHT", ui.auction, "LEFT", -Sch.GAP, 0)
    ui.add:SetScript("OnClick", function() Sch.AddToList() end)
    ui.auction:SetScript("OnClick", function() Sch.SearchAuction() end)

    local line = CreateFrame("Frame", nil, form)
    line:SetHeight(16)
    line:SetPoint("BOTTOMLEFT", ui.add, "TOPLEFT", 0, 6)
    line:SetPoint("RIGHT", form, "RIGHT", -20, 0)
    line.text = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    line.text:SetPoint("BOTTOMLEFT", line, "BOTTOMLEFT", 0, 2)
    line.text:SetPoint("RIGHT", line, "RIGHT", 0, 0)
    line.text:SetJustifyH("LEFT")
    line:EnableMouse(true)
    line:SetScript("OnEnter", LineTip)
    line:SetScript("OnLeave", GameTooltip_Hide)
    line:Hide()
    ui.line = line
    return true
end

-- Kurzform für die Zeile: „Material 65s (fehlt 11s) · Auktionshaus 91s · Gewinn 26s“. → Teile, grau?
function Sch.LineParts(lines, cost, profit, other)
    if other or not cost or cost.unknown == cost.count then
        local parts = {}
        for _, line in ipairs(lines) do parts[#parts + 1] = line.text end
        return parts, other == nil
    end
    local Money = Core.Money
    local text = L.RECIPE_COST:format(Money(cost.total))
    if cost.missing > 0 and cost.missing < cost.total then text = text .. " " .. L.RECIPE_COST_MISSING:format(Money(cost.missing)) end
    local parts = { text }
    if profit then
        parts[#parts + 1] = L.RECIPE_VALUE:format(Money(profit.gross))
        if profit.profit then
            parts[#parts + 1] = (profit.kind == "net" and L.RECIPE_PROFIT or L.RECIPE_PROFIT_GROSS):format(Money(profit.profit, nil, true))
        end
    end
    return parts, false
end

-- Reicht die Breite nicht, nur zwischen den Teilen umbrechen: Sonst trennte der Client die Münze von ihrer Zahl („Gewinn
-- −32“, darunter das Kupfer; Spieltest 25.11.2026). Nur ein Teil, der allein zu breit ist, bleibt dem Client. → umgebrochen?
function Sch.SetLine(text, parts, room)
    room = Core.Num(Core.Plain(room))
    local function TooWide(line)
        text:SetText(line)
        local width = Core.Num(Core.Plain(Core.Call(text.GetUnboundedStringWidth or text.GetStringWidth, text)))
        return width ~= nil and room ~= nil and room > 0 and width > room
    end
    local whole = table.concat(parts, " · ")
    if #parts < 2 or not TooWide(whole) then
        text:SetText(whole)
        return false
    end
    local lines, current = {}, parts[1]
    for i = 2, #parts do
        local longer = current .. " · " .. parts[i]
        if TooWide(longer) then
            lines[#lines + 1], current = current, parts[i]
        else
            current = longer
        end
    end
    lines[#lines + 1] = current
    text:SetText(table.concat(lines, "\n"))
    return true
end

-- Name der Liste, in die „Auf die Liste“ einträgt: die rechts gewählte, wenn sie änderbar ist, sonst „ezCraft“
-- (wie ns.Shopping.Target, ohne sie schon anzulegen)
local function TargetName()
    local list = ns.Shopping.Selected()
    if list and Core.Lists and Core.Lists.Editable(list) then return list.name end
    return L.SHOP_AUCTION_LIST
end

function Sch.Refresh()
    if not Sch.Create() then return end
    local P = ns.Panel
    local recipe = ns.Enabled("panel") and P.CraftingShown() and Data.Recipe(P.SelectedRecipeID()) or nil
    ui.add:SetShown(recipe ~= nil)
    ui.auction:SetShown(recipe ~= nil)
    if not recipe then
        ui.line:Hide()
        return
    end
    local quantity = P.Quantity()
    local rows = Data.Materials(recipe, quantity)
    ui.add:SetEnabled(#rows > 0)
    ui.add.tip = L.BTN_ADD_SHOPPING_TIP:format(TargetName())

    -- an, sobald das Rezept Material braucht – nicht grau, weil ein Twink es hat (Wunsch des Nutzers vom 21.11.2026:
    -- „ausgebrauter button weil es ein anderer char hat ist blödsinn“); gesucht wird jede Zutat
    local material = #rows > 0
    local search, open = ns.Shopping.SearchFunction() ~= nil, ns.Shopping.AuctionOpen()
    local pending = ns.Shopping.Pending()
    local queued = pending and pending.recipeID == recipe.recipeID
    ui.auction:SetEnabled(search and (material or queued))
    ui.auction.tip = not search and L.BTN_AUCTION_MISSING_TIP or queued and L.BTN_AUCTION_QUEUED_TIP
        or not material and L.SHOP_NO_MATERIAL or not open and L.BTN_AUCTION_CLOSED_TIP or L.BTN_AUCTION_RECIPE_TIP

    local lines, cost, profit, other = P.CostLines(rows, recipe, quantity)
    if #lines == 0 then
        ui.line:Hide()
        return
    end
    if cost then cost.count = #rows end
    local parts, grey = Sch.LineParts(lines, cost, profit, other)
    Sch.SetLine(ui.line.text, parts, ui.line:GetWidth())
    Core.Style.SetTextColor(ui.line.text, grey and "gray" or "highlight")   -- Blizzards Farbrollen (ezCore)
    ui.line.lines = lines
    ui.line:Show()
end

-- „Auf die Liste“: das gewählte Rezept mit der Menge aus „Herstellen“ in die rechts gewählte Liste; das Seitenteil
-- zeigt danach die Listen. → true bei Erfolg
function Sch.AddToList()
    local P = ns.Panel
    local recipe = Data.Recipe(P.SelectedRecipeID())
    local ok, count, listName = ns.Shopping.Add(recipe, P.Quantity())
    if not ok then return false end
    local text = L.SHOP_ADDED:format(recipe.name, count, listName)
    if Core.API("ezAuction") then text = text .. " " .. L.SHOP_ADDED_AH:format(listName) end
    ns.Print(text)
    if not (P.IsOpen() and P.Tab() == "shopping") then P.SelectTab("shopping") end
    return true
end

-- „Auktionshaus“: bei offenem Auktionshaus jede Zutat sofort suchen (ohne Liste), sonst vormerken bzw. die
-- Vormerkung zurücknehmen. → true, wenn ezAuction sucht bzw. jetzt vorgemerkt ist
function Sch.SearchAuction()
    local P = ns.Panel
    local recipe = Data.Recipe(P.SelectedRecipeID())
    if not ns.Shopping.AuctionOpen() then return ns.Shopping.TogglePending(recipe, P.Quantity()) end
    -- Auktionshaus offen: jetzt suchen; eine Vormerkung für dieses Rezept ist damit erledigt (keine zweite Suche)
    local pending = ns.Shopping.Pending()
    if pending and recipe and pending.recipeID == recipe.recipeID then ns.Shopping.ClearPending() end
    return ns.Shopping.SendRecipeToAuction(recipe, P.Quantity())
end

-- Für die Tests und den Rundgang
function Sch.AddButton() return ui.add end
function Sch.AuctionButton() return ui.auction end
function Sch.Line() return ui.line end

local function RefreshSoon() if ns.Panel and ns.Panel.RefreshSoon then ns.Panel.RefreshSoon() end end
ns.On("AUCTION_HOUSE_SHOW", RefreshSoon)
ns.On("AUCTION_HOUSE_CLOSED", RefreshSoon)
Core.Listen("LISTS_CHANGED", RefreshSoon, ADDON)   -- andere Liste gewählt oder umbenannt: Tooltip von „Auf die Liste“
