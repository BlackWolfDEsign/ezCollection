local ADDON, ns = ...
local L = ns.L

-- Kurzüberblick und Rundgang (ezCore/Tests/einfuehrung_funktionen_test.lua): je Zeile von L.INTRO_FEATURES der
-- Schritt (oder die Schritte) des Rundgangs, der sie zeigt; false = kein eigenes Ziel (Automatik, Tooltip, Daten oder
-- ein Fenster ohne Rundgang). Eine neue Zeile im Kurzüberblick braucht hier ihren Eintrag.
ns.FEATURE_STEPS = { "recipe.buttons", false, "recipe.buttons", "side.tabs", "recipe.buttons" }
local Core = ezCore
local Data = ns.Data

--[[
    ezCraft als Seitenteil am Berufefenster (ProfessionsFrame aus Blizzard_Professions, Forever/Camelot) –
    Entscheidung des Nutzers vom 14.11.2026 „Seitenteil mit Pfeil (Empfohlen)“ (CRAFT-01, FP-13); seit dem zweiten
    Spieltest vom 21.11.2026 klappt es ein Symbol-Reiter im Seitenreiter-Stapel auf und zu statt des Pfeils. Vorher (1.5 bis
    Welle 5) saß ezCraft im Rezeptfeld unter Blizzards Zutaten, mit Knopfspalte und Seitenreitern; im Spieltest
    überlappten Auctionators Zeilen die Überschrift und die Knöpfe hingen über Blizzards Seitenreitern.

    Lage laut Forever-Quelle (Gethe/wow-ui-source, Zweig forever: Camelot/Blizzard_ProfessionsFrame.xml):
      Berufefenster                    673 × 594 (Seite „Rezepte“ bis 782 breit, GetDesiredPageWidth)
      Blizzards Reiter rechts außen    ProfessionsOverviewTab (LargeSideTabButtonTemplate) an TOPRIGHT, y −60, darunter
                                       Professions1Tab … 7Tab – sie ragen über den rechten Rand hinaus
      Seitenreiter-Stapel              ebenfalls rechts außen (Core.CreateSideTab, Reiter anderer Module)

    Aufbau (nur eigene Rahmen; nichts in Blizzards Tabellen, nur HookScript; im Rezeptfeld nur ezCrafts Kostenzeile und
    die Knöpfe „Auf die Liste“ und „Auktionshaus“ – Schematic.lua, seit dem 21.11.2026):
      Seitenteil         Core.NewSidePanel(ProfessionsFrame): Kind des Berufefensters (kein Rahmen unter UIParent),
                         angedockt rechts außen mit Abstand SIDE_GAP – so bleiben Blizzards Reiter und der
                         Seitenreiter-Stapel frei; ohne Platz wechselt ezCore die Seite oder legt es innen darüber
                         (dann sagt das Seitenteil es). Blizzards Vorlage InsetFrameTemplate, dazu der Hintergrund des
                         offenen Berufs aus dem Rezeptfeld (nur gelesen).
      Symbol-Reiter      Core.CreateSideTab im Seitenreiter-Stapel unten rechts, wie die Reiter der anderen Module;
                         eingedrückt, solange das Seitenteil offen ist; Zustand in ezCraftDB.window.open, Tooltip,
                         /ezcraft fenster. Der Pfeil von Core.NewSidePanel bleibt verborgen.
      Ansichten          Listen (Grundansicht, beim Öffnen des Berufefensters immer), Abklingzeiten, Entzaubern,
                         darunter – solange ein Beruf gewählt ist – „Was kommt wann“ und „Wo kommt was“ (Teach.lua; Nutzer
                         am 24.11.2026: „wenn beruf ausgewählt dann zeige die beiden reiter im unteren rechteck an“; sie
                         ersetzen die Ansicht „Fehlend“) – je ein Symbol-Reiter; ein zweiter Klick auf den gewählten oder
                         das X schließt.
                         Die Ansicht „Rezept“ ging am 21.11.2026 in Blizzards Rezeptbereich auf (Schematic.lua; Wunsch
                         des Nutzers: „der rest aus dem ezcraft rezepte ist uninteressant“); Inhalt scrollt
      Seite „Berufe“     dasselbe Seitenteil auch auf Blizzards Seite „Berufe“ (BookPage, Taste K; Schalter bookPanel,
                         Entscheidung des Nutzers Nr. 22 vom 16.11.2026) – ohne die zwei Berufs-Reiter,
                         außer für einen über „Fundorte“ gewählten Sammelberuf
      Knopfleiste        unten, je Ansicht die passenden Knöpfe („Im AH suchen“, „Anfordern“, „Leeren“, „Neu lesen“,
                         „Ignorierte zurück“) – Blizzards Vorlage der Herstellen-Knöpfe

    Gewählt wird über Blizzards Nachricht „ProfessionsRecipeListMixin.Event.OnRecipeSelected“ (EventRegistry), die Menge
    liest ezCraft aus Blizzards Feld „Herstellen“ (CreateMultipleInputBox) – nur lesen, nichts setzen.
]]

local Panel = {}
ns.Panel = Panel

local ROW_H = 18
-- Symbol-Reiter; „shopping“ (Listen) ist die Grundansicht. Die Ansicht „Rezept“ ging am 21.11.2026 in Blizzards
-- Rezeptbereich auf (Schematic.lua; Wunsch des Nutzers: „das Rezepte von ezCraft soll direkt in das original blizz
-- anzeige rezept gebaut werden … standardmäßig sollen dann die ezcraft listen beim berufe angezigt werden“).
local TAB_KEYS = { "shopping", "cooldowns", "salvage", "when", "where" }
local VIEW_ICONS = {
    shopping = "Interface\\Icons\\INV_Misc_Note_01",
    when = "Interface\\Icons\\INV_Misc_Book_11",       -- dieselben Symbole wie die Zauberbuch-Reiter (ezMerchant)
    where = "Interface\\Icons\\INV_Misc_Map_01",
    cooldowns = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    salvage = "Interface\\Icons\\INV_Enchant_Disenchant",
}
local TICK = 30                     -- Restzeiten alle 30 Sekunden auffrischen
-- Knöpfe aus ezCore (Core.PANEL_BUTTONS: 22 hoch, 14 vom Rand, 6 dazwischen – Entscheidung des Nutzers vom 21.11.2026
-- „6 für alle“, vorher 4); WITHDRAW_GAP: senkrechte Luft zwischen der Knopfreihe und „Aus der Bank holen“ (ezCrafts
-- eigene, nicht der waagrechte Abstand aus ezCore)
local BUTTON_H, WITHDRAW_GAP = Core.PANEL_BUTTONS.height, 6
local BUTTON_X, BUTTON_SPACE, BUTTON_Y = Core.PANEL_BUTTONS.left, Core.PANEL_BUTTONS.space, Core.PANEL_BUTTONS.bottom
-- Breite wie ezTalents Seitenteile (Entscheidung des Nutzers vom 21.11.2026: „460 wie ezTalent“); ist neben dem
-- Berufefenster weniger Platz, wird es schmaler bis SIDE_MIN (drei Knöpfe je Reihe wie ezTalent ab 300) – rechts zuerst,
-- reicht es dort nicht, links; erst wenn beide Seiten zu schmal sind, legt ezCore es innen über das Fenster (FitWidth).
Panel.SIDE_W = Core.PANEL_SIZE.width
Panel.SIDE_MIN = 300
Panel.SCREEN_MARGIN = Core.PANEL_SIZE.margin   -- Luft zum Bildschirmrand (ezCore, wie ezTalent)
Panel.SIDE_GAP = 46                 -- Abstand zum Berufefenster: Blizzards Berufe-Reiter und der Seitenreiter-Stapel
                                    -- ragen rechts außen bis rund 44 über den Rand (LargeSideTabButtonTemplate)
local VIEW_TOP = Core.PANEL_TOP or 30   -- Inhalt unter Blizzards Titelleiste (gemeinsamer Rahmen, Core.PanelLook)
local HEAD_H = 46                   -- Ansicht „Listen“: Kopf mit Listenwahl (22), 4 Luft, Eingabefeld (20)
local BUTTONS_TOP = BUTTON_Y + BUTTON_H   -- Oberkante der Knopfreihe über der Unterkante
-- Kopf, Kasten und Liste wie in ezTalent (Auftrag des Nutzers vom 21.11.2026: „gleiches design und formatierung“) –
-- die Maße kommen aus ezCore (Core.PANEL_LIST), ein Ort für alle Seitenteile.
local LOOK = Core.PANEL_LIST
local ROW_FONT = { header = LOOK.fonts.section, item = LOOK.fonts.entry, text = LOOK.fonts.detail,
    sub = LOOK.fonts.sub, detail = LOOK.fonts.detail }

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
-- „Berufe“, mit Schalter bookPanel (ab Werk an). Dort ist kein Beruf gewählt: die Reiter „Was kommt wann“ und „Wo kommt
-- was“ fehlen (außer für einen über „Fundorte“ gewählten Sammelberuf), Listen, Abklingzeiten und Entzaubern bleiben.
local function OnBook()
    return ns.Enabled("bookPanel") and not CraftingShown() and Visible(Professions()) and Visible(BookPage())
end
Panel.OnBook = OnBook

local function Colored(text, colorObj)
    if colorObj and colorObj.WrapTextInColorCode then return colorObj:WrapTextInColorCode(text) end
    return text
end

Panel.SchematicForm = SchematicForm   -- Blizzards Rezeptbereich (Schematic.lua)
Panel.CraftingShown = CraftingShown

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
    -- nur mit gewähltem Beruf (Schlüssel missingTab aus der Zeit der Ansicht „Fehlend“)
    if key == "when" or key == "where" then return ns.Enabled("missingTab") and ns.Teach.Current() ~= nil end
    if key == "cooldowns" then return ns.Enabled("cooldownTab") and Data.HasCooldowns() end
    -- „Entzaubern“ nur, wenn der Charakter es kann (und ezCore die Tabelle hat)
    if key == "salvage" then return ns.Enabled("salvageTab") and ns.Salvage ~= nil and ns.Salvage.CanDisenchant() end
    return true
end

-- Gewählte Ansicht; ohne Wahl, abgeschaltet oder das gemerkte „recipe“ von vor dem 21.11.2026: die Listen. „missing“
-- (bis zum 24.11.2026) heißt „when“.
local function Tab()
    local tab = ns.db and ns.db.window.tab or "shopping"
    if tab == "missing" then tab = "when" end
    if tab == "recipe" or not VIEW_ICONS[tab] or not TabAvailable(tab) then tab = "shopping" end
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
    -- Rezept auf einer Liste: im Auktionshaus den Gegenstand selbst kaufen (Münze farbig) oder das Material (grau)
    buy = { "Interface\\Icons\\INV_Misc_Coin_01", "Interface\\Icons\\INV_Misc_Coin_01",
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
    row:SetScript("OnClick", function(self)      -- nur Zeilen mit eigener Aktion („… und n weitere“)
        if not self.onClick then return end
        Core.PlaySound("IG_MAINMENU_OPTION_CHECKBOX_ON")
        self.onClick()
    end)
    return row
end

-- Neue Zeile; kind: "header", "text" (umbricht), "item" (Eintrag: Symbol links, Werte rechts), "sub" (Unterzeile
-- eines Eintrags, grau), "detail" (Einzelheiten, eingerückt). Zwischen zwei Einträgen (item, text) liegt LOOK.entryGap;
-- Unterzeile und Einzelheiten hängen ohne Luft am Eintrag darüber.
local function Row(kind, height)
    if (kind == "item" or kind == "text") and (cur.last == "item" or cur.last == "text" or cur.last == "sub"
        or cur.last == "detail") then
        cur.cursorY = cur.cursorY + LOOK.entryGap
    end
    cur.last = kind
    cur.used = cur.used + 1
    local row = cur.rows[cur.used]
    if not row then
        row = NewRow()
        cur.rows[cur.used] = row
    end
    row.kind, row.tip, row.onClick = kind, nil, nil
    for _, button in ipairs(row.buttons) do button:Hide() end
    row.icon:Hide()
    row.left:SetText("")
    row.right:SetText("")
    row.left:SetFontObject(ROW_FONT[kind] or ROW_FONT.text)
    -- Gold für Überschriften, Grau für Unterzeilen, sonst Blizzards Weiß (Design-System 2.5)
    Core.Style.SetTextColor(row.left, kind == "header" and "normal" or kind == "sub" and "disabled" or "highlight")
    row.left:ClearAllPoints()
    row.right:ClearAllPoints()
    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT", row, "LEFT", LOOK.entryIndent, 0)
    if kind == "item" then
        row.left:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
        row.left:SetPoint("RIGHT", row.right, "LEFT", -4, 0)
        row.right:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    else
        -- Unterzeile unter dem Namen (hinter dem Symbol), Einzelheiten 14, Text wie ein Eintrag, Überschrift am Rand
        local x = kind == "sub" and LOOK.entryIndent + 20 or kind == "detail" and LOOK.detailIndent
            or kind == "header" and 4 or LOOK.entryIndent
        row.left:SetPoint("TOPLEFT", row, "TOPLEFT", x, -2)
        row.left:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    end
    row.left:SetWordWrap(kind == "text" or kind == "detail" or kind == "sub")
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
    if cur.cursorY > 0 then cur.cursorY = cur.cursorY + LOOK.sectionGap end
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

-- Unterzeile eines Eintrags (höchstens eine, grau) bzw. Einzelheiten (eingerückt, umbrechend; grey: grau).
local function Sub(text)
    local row = Row("sub")
    row.left:SetText(text)
    local height = (row.left.GetStringHeight and row.left:GetStringHeight()) or 0
    row:SetHeight(math.max(14, height + 2))   -- ein langer Fundort bricht um statt abgeschnitten zu werden
    Advance(row)
    return row
end

local function Detail(text, grey)
    local row = Row("detail")
    row.left:SetText(text)
    if grey then
        row.left:SetFontObject(ROW_FONT.sub)
        Core.Style.SetTextColor(row.left, "disabled")
    end
    local height = (row.left.GetStringHeight and row.left:GetStringHeight()) or 0
    row:SetHeight(math.max(14, height + 2))
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
    cur.used, cur.cursorY, cur.last = 0, 0, nil
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
-- Panel.CostLines(rows, recipe, quantity) → { { text, grey = true|nil }, … }, cost, profit, other – dieselben Zeilen für
-- die Ansicht „Listen“ (CostRows) und den Tooltip der Kostenzeile in Blizzards Rezeptbereich (Schematic.lua).
function Panel.CostLines(rows, recipe, quantity)
    local lines = {}
    local function Add(text, grey) lines[#lines + 1] = { text = text, grey = grey or nil } end
    if not (ns.Enabled("costs") and Data.HasPrices()) or #(rows or {}) == 0 then return lines end
    local Money = Core.Money
    local cost = Data.Cost(rows)
    local other = recipe and Data.CraftCostOther()
    if other then
        if cost.missing > 0 then Add(L.PANEL_COST_MISSING_ONLY:format(Money(cost.missing))) end
        Add(L.PANEL_COST_OTHER:format(other), true)
        return lines, cost, nil, other
    end
    if cost.unknown == #rows then
        Add(L.PANEL_COST_NONE, true)
        return lines, cost
    end
    local text = L.PANEL_COST:format(Money(cost.total))
    if cost.missing > 0 and cost.missing < cost.total then text = text .. "  " .. L.PANEL_COST_MISSING:format(Money(cost.missing)) end
    Add(text)
    if cost.unknown > 0 then Add(L.PANEL_COST_UNKNOWN:format(cost.unknown), true) end
    local profit = recipe and Data.Profit(recipe, quantity, cost)
    if profit then
        if profit.kind == "net" then
            if profit.profit then
                Add(L.PANEL_VALUE_NET:format(Money(profit.gross), Money(profit.net), Money(profit.profit, nil, true)))
            else
                Add(L.PANEL_VALUE_NET_ONLY:format(Money(profit.gross), Money(profit.net)))
            end
        elseif profit.profit then
            Add(L.PANEL_VALUE_PROFIT:format(Money(profit.gross), Money(profit.profit, nil, true)))
        else
            Add(L.PANEL_VALUE:format(Money(profit.gross)))
        end
    end
    local source = Data.CostSource(cost)
    if source then Add(L.PANEL_COST_SOURCE:format(source), true) end
    if profit then
        if profit.source then Add(L.PANEL_VALUE_SOURCE:format(profit.source), true) end
        if profit.kind == "net" then
            local fee = L.PANEL_FEE:format(Money(profit.fee))
            if profit.feeStand then fee = fee .. " (" .. profit.feeStand .. ")" end
            Add(fee, true)
        else
            Add(L.PANEL_FEE_UNKNOWN, true)
        end
        -- Welle 23, A3: Anzahlung (zählt nicht zum Gewinn, sie kommt beim Verkauf zurück – verloren nur bei Ablauf)
        if profit.deposit then
            local deposit = L.PANEL_DEPOSIT:format(Money(profit.deposit))
            if profit.depositStand then deposit = deposit .. " (" .. profit.depositStand .. ")" end
            Add(deposit, true)
        end
    end
    return lines, cost, profit
end

-- Kosten der ganzen Liste: ein eigener Block unter dem Material (Luft wie zwischen Einträgen, dann eingerückt wie
-- Einzelheiten in ezTalent) – nicht als Einzelheit nur des letzten Materials zu lesen (Review 21.11.2026)
local function CostRows(rows)
    local lines = Panel.CostLines(rows)
    if #lines > 0 and cur.used > 0 then cur.cursorY = cur.cursorY + LOOK.entryGap end
    for _, line in ipairs(lines) do Detail(line.text, line.grey) end
end

-- Umschalter an einem Rezept der Liste: im Auktionshaus Material (ab Werk, Münze grau) oder den Gegenstand selbst
-- (Münze farbig) suchen – Entscheidung des Nutzers vom 21.11.2026 „muss beides möglichsein primär aber material“.
local function BuyButton(row, slot, index, entry)
    local button = RowButton(row, slot, "buy", entry.buy and L.SHOP_BUY_ITEM_TIP or L.SHOP_BUY_MATERIAL_TIP, function() ns.Shopping.ToggleBuy(index) end, function(self)
        Core.ShowTip(self, entry.buy and L.SHOP_BUY_ITEM or L.SHOP_BUY_MATERIAL,
            entry.buy and L.SHOP_BUY_ITEM_TIP or L.SHOP_BUY_MATERIAL_TIP)
    end)
    local normal = button.GetNormalTexture and button:GetNormalTexture()
    if normal and normal.SetDesaturated then normal:SetDesaturated(not entry.buy) end
    return button
end

-- Tooltip einer Zeile der Liste: Gegenstand (Blizzards Tooltip), dazu Art und Suchweg im Auktionshaus.
local function EntryTip(entry)
    return function(tooltip)
        if entry.itemID and tooltip.SetItemByID then
            tooltip:SetItemByID(entry.itemID)
        else
            tooltip:SetText(ns.Shopping.Name(entry))
        end
        if entry.recipe then
            ns.TipLine(tooltip, entry.buy and L.SHOP_ENTRY_RECIPE_ITEM or L.SHOP_ENTRY_RECIPE, "hint", true)
        elseif not entry.itemID then
            ns.TipLine(tooltip, L.SHOP_ENTRY_TERM, "hint", true)
        end
    end
end

-- Ansicht „Listen“: Einträge der gewählten Liste (Rezepte und Gegenstände) mit −/+/x, bei Rezepten der Umschalter
-- Material/Gegenstand; darunter das Material mit Bestand und Kosten, dann die angeforderten Sendungen.
local function ShowShopping()
    local list = ns.Shopping.Selected()
    local entries = list and list.items or {}
    if not list then
        Text(L.LIST_NONE_PANEL, 0.7, 0.7, 0.7)
    elseif #entries == 0 then
        Text(L.SHOP_EMPTY_PANEL, 0.7, 0.7, 0.7)
    else
        local editable = Core.Lists.Editable(list)
        if not editable then Text(L.LIST_SOURCE_PANEL, 0.7, 0.7, 0.7) end
        Header(L.PANEL_SHOP_RECIPES)
        for index, entry in ipairs(entries) do
            local row = ItemRow(ns.Shopping.Icon(entry), ns.Shopping.EntryText(entry), "")
            row.tip = EntryTip(entry)
            local last
            if editable then
                RowButton(row, 1, "remove", L.SHOP_REMOVE_TIP, function() ns.Shopping.RemoveEntry(index) end)
                last = RowButton(row, 2, "plus", L.SHOP_PLUS_TIP, function() ns.Shopping.SetEntryCount(index, (entry.count or 0) + 1) end)
                -- „−“ nur mit Menge (ein Gegenstand ohne Menge wird mit x entfernt)
                if entry.count then
                    last = RowButton(row, 3, "minus", L.SHOP_MINUS_TIP, function()
                        ns.Shopping.SetEntryCount(index, entry.count - 1)
                    end)
                end
                if entry.recipe then last = BuyButton(row, 4, index, entry) end
            end
            row.left:ClearAllPoints()
            row.left:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
            if last then
                row.left:SetPoint("RIGHT", last, "LEFT", -4, 0)
            else
                row.left:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            end
        end
        local totals = ns.Shopping.Totals()
        if #totals > 0 then
            Header(L.PANEL_MATERIAL)
            for _, row in ipairs(totals) do
                row.status = row.stock.bags >= row.need and "bags" or (row.missing == 0 and "have" or "missing")
            end
            MaterialRows(totals)
            CostRows(totals)
        end
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

---------------------------------------------------------------------------
-- „Was kommt wann“ und „Wo kommt was“ für den gewählten Beruf (Daten: Teach.lua; bis zum 24.11.2026 eine Ansicht „Fehlend“)
---------------------------------------------------------------------------

Panel.TEACH_MAX = { later = 15, unknown = 8, trainers = 5, zone = 8, noplace = 8 }
local expanded, expandedFor = {}, nil      -- aufgeklappte Abschnitte, gelten für den gewählten Beruf

-- Höchstens max Einträge eines Abschnitts; der Rest hinter einer anklickbaren Zeile „… und n weitere“ (aufgeklappt:
-- „Weniger zeigen“) – wie im Zauberbuch-Reiter „Wo kommt was“ (Nutzer am 24.11.2026: „das "5weitere" AUSKLAPPBAR“).
local function Capped(key, list, max, draw)
    local open = expanded[key]
    local shown = open and #list or math.min(#list, max)
    for i = 1, shown do draw(list[i]) end
    if #list <= max then return end
    -- mit Aufklapp-Pfeil (Nutzer am 24.11.2026: „"und x weitere" brauch noch einen aufklapppfeil“)
    local row = Text(Core.FoldText(open, open and L.TEACH_LESS or Core.More(#list - max)))
    Core.Style.SetTextColor(row.left, "normal")
    row.tip = function(tooltip) tooltip:SetText(open and L.TEACH_LESS_TIP or L.TEACH_MORE_TIP) end
    row.onClick = function()
        expanded[key] = not open or nil
        Panel.Refresh()
    end
end

-- Kartenknopf an einer Zeile: Blizzards Weltkarte am Ort, auf Wunsch der Wegpunkt (Where.Show)
local function PlaceButton(row, place)
    local button = RowButton(row, 1, "map", L.WHERE_SHOW_TIP:format(place.name or "?", Core.MapName(place.map) or place.zone or "?"),
        function() ns.Where.Show(place) end, function(self) Core.ShowTip(self, L.WHERE_SHOW, self.tip) end)
    row.right:ClearAllPoints()
    row.right:SetPoint("RIGHT", button, "LEFT", -4, 0)
    return button
end

-- Ein Rezept: Symbol, Name, rechts right, darunter sub, Kartenknopf zu place; Tooltip mit Fertigkeit, Stufe, Preis und
-- allen Fundorten samt Quelle.
local function TeachRow(entry, rank, right, sub, place)
    local row = ItemRow(entry.icon or Data.CooldownIcon(entry.id or entry.recipeID), entry.name or "?", right or "")
    if place then PlaceButton(row, place) end
    if sub then Sub(sub) end
    row.tip = function(tooltip)
        tooltip:SetText(entry.name or "?")
        local skill = ns.Where.SkillText(entry, rank)
        if skill then ns.TipLine(tooltip, L.WHERE_SKILL_LINE:format(skill), "normal") end
        if entry.lvl and entry.lvl > 0 then ns.TipLine(tooltip, L.TEACH_LEVEL:format(entry.lvl), "normal") end
        if entry.price and entry.price > 0 then ns.TipLine(tooltip, L.TEACH_PRICE:format(Core.Money(entry.price)), "normal") end
        -- Farbstufen laut Client-Tabellen (standen bis zum 24.11.2026 im Zauberbuch-Reiter „Wo kommt was“)
        local K, id = Core.Knowledge, entry.id or entry.recipeID
        local st = id and K and type(K.RecipeStages) == "function" and Core.Plain(Core.Call(K.RecipeStages, id)) or nil
        if type(st) == "table" and Core.Num(st.yellow) and Core.Num(st.gray) then
            ns.TipLine(tooltip, L.TEACH_STAGES:format(st.yellow, st.gray), "hint", true)
        end
        local trainer, lines = false, 0
        for _, e in ipairs(entry.where or {}) do
            local text = ns.Where.Line(e)
            if text then
                ns.TipLine(tooltip, text, "highlight", true)
                lines = lines + 1
                if e.kind == "trainer" then trainer = true end
            end
        end
        if entry.npcName and not trainer then
            ns.TipLine(tooltip, L.TEACH_SEEN:format(entry.npcName), "hint", true)
            lines = lines + 1
        end
        if entry.source or lines == 0 then
            if lines == 0 or not entry.where or #entry.where == 0 then
                ns.TipLine(tooltip, entry.source or L.MISSING_NO_SOURCE, "highlight", true)
            end
        end
    end
    return row
end

-- Überschrift der Ansicht: „Kochkunst 66/75“
local function ProfHead(prof)
    if prof.rank and prof.max then return Header(L.TEACH_HEAD:format(prof.name or "?", prof.rank, prof.max)) end
    if prof.rank then return Header(("%s %d"):format(prof.name or "?", prof.rank)) end
    return Header(prof.name or "?")
end

local function Hint(text)
    cur.cursorY = cur.cursorY + LOOK.sectionGap - LOOK.entryGap   -- Hinweise als eigener Block (12 Luft)
    Text(text, 0.6, 0.6, 0.6)
end

-- Unterzeile: erster Fundort, sonst der Lehrer, bei dem das Angebot gesehen wurde, sonst Blizzards Text
local function FirstLine(entry)
    if entry.where and entry.where[1] then return ns.Where.Line(entry.where[1]) end
    if entry.npcName then return L.TEACH_SEEN:format(entry.npcName) end
    return Data.SourceFirstLine(entry.source)
end

-- „Was kommt wann“: jetzt lernbar, kommt noch (nach Fertigkeit), Fertigkeit unbekannt.
local function ShowWhen()
    local prof = ns.Teach.Current()
    if not prof then return Text(L.MISSING_NO_WINDOW, 0.7, 0.7, 0.7) end
    local when = ns.Teach.When(prof)
    ProfHead(prof)
    if when.window and when.total > 0 then
        Text(when.missing > 0 and L.MISSING_HEAD:format(when.missing, when.total) or L.MISSING_NONE, 0.8, 0.8, 0.8)
    end
    if when.all == 0 then
        if not (when.window and when.total > 0) then
            Text(when.seen and L.TEACH_NOTHING or L.TEACH_NO_OFFERS:format(L.TAB_where), 0.7, 0.7, 0.7)
        end
    else
        if #when.now > 0 then
            Header(L.TEACH_NOW:format(#when.now))
            for _, e in ipairs(when.now) do
                local right = e.price and e.price > 0 and Core.Money(e.price) or Colored(ns.Where.SkillText(e, when.rank) or "", GREEN_FONT_COLOR)
                TeachRow(e, when.rank, right, FirstLine(e), ns.Where.Best(e.where))
            end
        end
        if #when.later > 0 then
            Header(L.TEACH_LATER:format(#when.later))
            Capped("later", when.later, Panel.TEACH_MAX.later, function(e)
                local text = ns.Where.SkillText(e, when.rank)
                if e.lvl and e.lvl > (Core.PlayerLevel and Core.PlayerLevel() or 1) then
                    text = (text and (text .. ", ") or "") .. L.TEACH_LEVEL:format(e.lvl)
                end
                TeachRow(e, when.rank, Colored(text or "", RED_FONT_COLOR), FirstLine(e), ns.Where.Best(e.where))
            end)
        end
        if #when.unknown > 0 then
            Header(L.TEACH_UNKNOWN:format(#when.unknown))
            Capped("unknown", when.unknown, Panel.TEACH_MAX.unknown, function(e)
                TeachRow(e, when.rank, ns.Where.SkillText(e, when.rank), FirstLine(e), ns.Where.Best(e.where))
            end)
        end
        if not when.seen and prof.own then Hint(L.TEACH_NO_OFFERS:format(L.TAB_where)) end
    end
    Hint(when.window and L.TEACH_SRC_WHEN or L.TEACH_SRC_WHEN_NOWINDOW)
end

-- „Wo kommt was“: die Lehrer (nächster zuerst), dann je Gebiet die Rezepte, die es nicht beim Lehrer gibt (dein Gebiet
-- zuerst), dann die ohne bekannten Ort.
local function ShowWhere()
    local prof = ns.Teach.Current()
    if not prof then return Text(L.MISSING_NO_WINDOW, 0.7, 0.7, 0.7) end
    local TS = Core.TrainerSpots
    local data = ns.Teach.Where(prof)
    local zone = Data.PlayerZone()
    ProfHead(prof)
    Header(L.TEACH_TRAINERS)
    if #data.trainers == 0 then
        Text(data.pending and L.TEACH_PENDING or (data.withMap and L.TEACH_TRAINERS_NONE or L.TEACH_TRAINERS_NOMAP), 0.7, 0.7, 0.7)
    else
        Capped("trainers", data.trainers, Panel.TEACH_MAX.trainers, function(t)
            local here = zone ~= nil and t.map == zone
            local row = ItemRow(prof.icon, TS.Name(t), here and Colored(L.TEACH_HERE, GREEN_FONT_COLOR) or "")
            local source, place = TS.SourceLabel(t), TS.Place(t)
            if t.map and t.x and t.y then
                PlaceButton(row, { map = t.map, x = t.x, y = t.y, name = TS.Name(t), zone = place })
            end
            Sub(source and L.TEACH_PLACE_SRC:format(place, source) or place)
            row.tip = function(tooltip)
                tooltip:SetText(TS.Name(t))
                ns.TipLine(tooltip, place, "highlight")
                if source then ns.TipLine(tooltip, source, "hint") end
                if t.map and t.x and t.y then ns.TipLine(tooltip, L.TEACH_MAP_TIP, "hint", true) end
            end
        end)
        if data.pending then Text(L.TEACH_PENDING, 0.6, 0.6, 0.6) end
    end
    for _, z in ipairs(data.zones) do
        Header(z.mine and L.TEACH_ZONE_MINE:format(z.name) or z.name)
        Capped("zone" .. z.map, z.list, Panel.TEACH_MAX.zone, function(x)
            local onMap = x.place.x and x.place.y and x.place or nil      -- nur mit Kartenpunkt ein Kartenknopf
            TeachRow(x.entry, data.rank, ns.Where.SkillText(x.entry, data.rank), ns.Where.Line(x.place), onMap)
        end)
    end
    if #data.noplace > 0 then
        Header(L.TEACH_NOPLACE)
        Capped("noplace", data.noplace, Panel.TEACH_MAX.noplace, function(x)
            TeachRow(x.entry, data.rank, ns.Where.SkillText(x.entry, data.rank),
                x.place and ns.Where.Line(x.place) or Data.SourceFirstLine(x.entry.source))
        end)
    end
    if #data.zones == 0 and #data.noplace == 0 and data.blind == 0 then
        Header(L.TEACH_ELSEWHERE)
        Text(L.TEACH_ELSEWHERE_NONE, 0.7, 0.7, 0.7)
    end
    if data.taught > 0 then
        Hint(Core.Plural(data.taught, L.TEACH_TAUGHT_ONE, L.TEACH_TAUGHT_MANY, L.TAB_when))
    end
    if data.blind > 0 then Hint(Core.Plural(data.blind, L.TEACH_BLIND_ONE, L.TEACH_BLIND_MANY)) end
    Hint(L.TEACH_SRC_WHERE)
end

-- Ansicht für einen Sammelberuf auf der Seite „Berufe“ öffnen (Menü „Fundorte“, Book.lua) → true, wenn zu sehen
-- nur mit Seitenteil: ezCraft im Berufefenster an (Schalter „panel“, „bookPanel“) und angelegt
function Panel.CanTeach() return ns.Enabled("missingTab") and ns.Enabled("panel") and ui.side ~= nil and OnBook() end

function Panel.OpenTeach(key, tab)
    if not Panel.CanTeach() then return false end
    if not ns.Teach.Pick(key) or not ns.Teach.Current() then
        ns.Teach.Unpick()
        return false
    end
    Panel.SelectTab(tab == "where" and "where" or "when")
    return true
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
    cur.cursorY = cur.cursorY + LOOK.sectionGap - LOOK.entryGap   -- Hinweise als eigener Block (12 Luft)
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
            -- der sichere Knopf liegt jetzt darüber; der nächste Klick entzaubert – außer eine Nachfrage ist offen
            local _, why = Sal.Arm(self, entry)
            if why == "asking" then ns.Print(L.SALVAGE_CLICK_ASKING) end
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
    cur.cursorY = cur.cursorY + LOOK.sectionGap - LOOK.entryGap   -- Hinweise als eigener Block (12 Luft)
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

local function UpdateButtons(tab)
    if tab == "shopping" then
        local hasList = #ns.Shopping.Entries() > 0
        local auction = Core.API("ezAuction") ~= nil
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
    else      -- „Was kommt wann“, „Wo kommt was“
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
-- Die Seite der Blasen richtet sich nach der Seite des Seitenteils (SetTourSides): der Symbol-Reiter darüber, der Inhalt
-- zum Berufefenster hin, Knöpfe und Reiter innerhalb des Seitenteils.
---------------------------------------------------------------------------

local TOUR_STEPS = {
    -- Schlüssel bleibt „side.arrow“ (gemerkte Blasen); Ziel sind die Symbol-Reiter (Panel.SideTab)
    { key = "side.arrow", target = function() return Panel.SideTab() end, text = L.TOUR_ARROW },   -- Seite: SetTourSides
    -- Knöpfe „Auf die Liste“ und „Auktionshaus“ in Blizzards Rezeptbereich (Schematic.lua, seit dem 21.11.2026 statt
    -- der Blasen zur Ansicht „Rezept“: side.material, side.shopping, side.request); neuer Schlüssel, damit jeder sie sieht
    { key = "recipe.buttons", target = function()
        local button = ns.Schematic and ns.Schematic.AddButton()
        return button and button:IsVisible() and button or nil
    end, text = L.TOUR_SHOPPING, side = "above" },
    -- Seite „Berufe“ (Nr. 22): dort gibt es kein „Rezept“ und keine Rückkehr dorthin, von denen TOUR_TABS spricht
    { key = "side.tabs", target = function()
        -- erst bei offenem Seitenteil (wie die übrigen Blasen; die erste zeigt schon auf die Symbole)
        local tab = not OnBook() and ui.side and ui.side:IsOpen() and ui.tabs.shopping
        return tab and tab:IsVisible() and tab or nil
    end, text = L.TOUR_TABS, side = "left" },
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
    -- die Symbol-Reiter stehen rechts außen am Berufefenster: die Blase darüber (rechts daneben läge sie auf dem
    -- offenen Seitenteil)
    TOUR_STEPS[1].side = "above"
    TOUR_STEPS[3].side = left and "right" or "left"   -- „side.tabs“: zum Seitenteil hin
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

-- Ansicht wählen und das Seitenteil öffnen (Symbol-Reiter, Rundgang, Prüfungen).
local function SelectTab(key)
    if not ns.db then return end
    ns.db.window.tab = key
    if ui.side and not ui.side:IsOpen() then
        ui.side:Open()        -- onToggle zeichnet neu
    else
        Panel.Refresh()
    end
end
Panel.SelectTab = SelectTab

-- Klick auf einen Symbol-Reiter: öffnet das Seitenteil mit dieser Ansicht; ein zweiter Klick auf den gewählten
-- schließt es (wie ezTalents Reiter).
function Panel.ClickTab(key)
    Core.PlaySound("IG_CHARACTER_INFO_TAB")
    if ui.side and ui.side:IsOpen() and Tab() == key then
        ui.side:Close()
        return false
    end
    SelectTab(key)
    return true
end

-- Symbol-Reiter: nur die verfügbaren Ansichten (ein abgeschalteter hinterlässt keine Lücke – ezCores Stapel rückt
-- nach), der gewählte ist bei offenem Seitenteil eingedrückt. on: ezCraft ist gerade zu sehen.
local function UpdateTabs(on)
    local current, open, shown = Tab(), ui.side and ui.side:IsOpen(), 0
    for _, key in ipairs(TAB_KEYS) do
        local tab = ui.tabs[key]
        local visible = on and TabAvailable(key)
        tab:SetShown(visible)
        if visible then shown = shown + 1 end
    end
    -- eingedrückt: der Reiter des offenen Seitenteils – eine Regel für alle Module (Core.CheckSideTabs)
    Core.CheckSideTabs(ui.tabs, (on and open and TabAvailable(current)) and current or nil)
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

-- Blizzards Berufe-Reiter rechts am Berufefenster (Forever/Camelot: ProfessionsOverviewTab, Professions1Tab …
-- 7Tab; je nach Zahl der Berufe verschieden viele) – gelesen, nie verändert.
local function BlizzardTabs(pf)
    local tabs = {}
    local function Add(tab)
        if type(tab) == "table" and type(tab.IsShown) == "function" and tab:IsShown() then tabs[#tabs + 1] = tab end
    end
    Add(rawget(_G, "ProfessionsOverviewTab") or Core.Peek(pf, "ProfessionsOverviewTab") or Core.Peek(pf, "OverviewTab"))
    for i = 1, 9 do Add(rawget(_G, "Professions" .. i .. "Tab") or Core.Peek(pf, "Professions" .. i .. "Tab")) end
    return tabs
end
Panel.BlizzardTabs = BlizzardTabs

-- Lage des ersten Symbol-Reiters (von oben): Panel.TAB_GAP unter dem untersten Berufe-Reiter von Blizzard; ohne
-- bekannte Lage nach ihrer Zahl (Blizzards Reiter beginnen bei y −60, je rund 50 hoch); ohne Berufe-Reiter ezCores
-- Standard. → y
function Panel.TabStart(pf)
    local tabs = BlizzardTabs(pf)
    if #tabs == 0 then return Core.SideTabs.TOP end
    local top = Core.Num(Core.Call(Core.Peek(pf, "GetTop"), pf))
    local lowest
    for _, tab in ipairs(tabs) do
        local bottom = Core.Num(Core.Call(Core.Peek(tab, "GetBottom"), tab))
        if top and bottom and (not lowest or bottom - top < lowest) then lowest = bottom - top end
    end
    if lowest then return math.floor(lowest - Panel.TAB_GAP) end
    return Panel.BLIZZARD_TAB_TOP - #tabs * Panel.BLIZZARD_TAB_STEP - Panel.TAB_GAP
end
Panel.TAB_GAP = 12
Panel.BLIZZARD_TAB_TOP, Panel.BLIZZARD_TAB_STEP = -60, 50

-- Symbol-Reiter unter Blizzards Berufe-Reiter rücken (beim Zeigen, bei anderem Beruf).
function Panel.PlaceTabs()
    local pf = Professions()
    if not (pf and ui.tabs.shopping) then return nil end
    local start = Panel.TabStart(pf)
    Core.SideTabs.SetStart(pf, "top", start)
    return start
end

-- Ansichten als Symbol-Reiter im Seitenreiter-Stapel des Berufefensters (Spieltest vom 21.11.2026: „ezcraft soll
-- direkt die symbole dort anhängen“ – wie ezTalents Vorlagen, Auswirkungen, Twinks). Vorher eine Reiterzeile oben im
-- Seitenteil und ein einzelner Reiter „ezCraft.side“ zum Auf- und Zuklappen; beides ersetzen diese Reiter.
local function CreateTabs(pf)
    for index, key in ipairs(TAB_KEYS) do
        local tab = Core.CreateSideTab(pf, { key = "ezCraft." .. key, order = index * 10, from = "top", owner = ADDON })
        Core.SetIcon(tab.Icon, nil, VIEW_ICONS[key])
        tab.key = key
        tab:SetScript("OnClick", function(self) Panel.ClickTab(self.key) end)
        tab:SetScript("OnEnter", function(self)
            local open = ui.side and ui.side:IsOpen() and Tab() == key
            Core.ShowTip(self, L["TAB_" .. key], L["TAB_" .. key .. "_TIP"] .. "\n\n" .. (open and L.TAB_CLICK_CLOSE or L.TAB_CLICK_OPEN),
                "ANCHOR_RIGHT")
        end)
        tab:SetScript("OnLeave", GameTooltip_Hide)
        tab:Hide()
        ui.tabs[key] = tab
    end
    Panel.PlaceTabs()
end

local function CreateButtons(side)
    for index = 1, 3 do
        -- Blizzards Vorlage der Herstellen-Knöpfe im Forever-Berufefenster (SharedButtonSmallTemplate)
        local ok, button = pcall(CreateFrame, "Button", "ezCraftButton" .. index, side, "SharedButtonSmallTemplate")
        if not (ok and button) then
            ok, button = pcall(CreateFrame, "Button", "ezCraftButton" .. index, side, "UIPanelButtonTemplate")
            if not (ok and button) then button = CreateFrame("Button", "ezCraftButton" .. index, side) end
        end
        button:SetHeight(BUTTON_H)   -- Breite: LayoutButtons (folgt der Breite des Seitenteils)
        if index == 1 then
            button:SetPoint("BOTTOMLEFT", side, "BOTTOMLEFT", BUTTON_X, BUTTON_Y)
        else
            button:SetPoint("LEFT", ui.buttons[index - 1], "RIGHT", BUTTON_SPACE, 0)
        end
        button:SetScript("OnEnter", function(self)
            if self.tip then Core.ShowTip(self, self:GetText() or "", self.tip, "ANCHOR_TOP") end
        end)
        button:SetScript("OnLeave", GameTooltip_Hide)
        if button.SetMotionScriptsWhileDisabled then button:SetMotionScriptsWhileDisabled(true) end   -- Tooltip auch, wenn aus
        button:Hide()
        ui.buttons[index] = button
    end
    -- „Aus der Bank holen (n)“ (NEU-01): eigene Zeile über der Knopfleiste, nur in der Ansicht „Listen“ bei offener
    -- Bank bzw. Gildenbank und laufendem ezBag (UpdateWithdraw)
    local ok, wide = pcall(CreateFrame, "Button", "ezCraftWithdrawButton", side, "SharedButtonSmallTemplate")
    if not (ok and wide) then
        ok, wide = pcall(CreateFrame, "Button", "ezCraftWithdrawButton", side, "UIPanelButtonTemplate")
        if not (ok and wide) then wide = CreateFrame("Button", "ezCraftWithdrawButton", side) end
    end
    wide:SetHeight(BUTTON_H)
    wide:SetPoint("BOTTOMLEFT", side, "BOTTOMLEFT", BUTTON_X, BUTTON_Y + BUTTON_H + WITHDRAW_GAP)
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
-- → Oberkante des Knopfbereichs über der Unterkante des Seitenteils
local function UpdateWithdraw(tab)
    local wide = ui.withdraw
    if not wide then return BUTTONS_TOP end
    local show = tab == "shopping" and ns.Shopping.CanWithdraw()
    if show then
        local _, rows = ns.Shopping.FromBank()
        wide:SetText(L.BTN_WITHDRAW:format(#rows))
        wide:SetEnabled(#rows > 0)
        wide:Show()
        return BUTTONS_TOP + WITHDRAW_GAP + BUTTON_H
    end
    wide:Hide()
    return BUTTONS_TOP
end

-- Drei Knöpfe gleich breit über die Breite des Seitenteils, „Aus der Bank holen“ über alle drei.
local function LayoutButtons(width)
    local w = math.floor((width - 2 * BUTTON_X - 2 * BUTTON_SPACE) / 3)
    for _, button in ipairs(ui.buttons) do button:SetWidth(w) end
    if ui.withdraw then ui.withdraw:SetWidth(3 * w + 2 * BUTTON_SPACE) end
    return w
end

-- Breite nach dem Platz neben dem Berufefenster: SIDE_W, bei weniger Platz bis SIDE_MIN schmaler (wie ezTalents
-- UI.Place). Rechts zuerst; reicht es dort nicht einmal für SIDE_MIN, zählt der Platz links (dorthin legt ezCores
-- Core.Dock das Teil dann). Unbekannter Platz (Fenster noch nicht gesetzt): SIDE_W. Ändert sich die Breite, dockt
-- ezCore neu an (nur der eigene, ungeschützte Rahmen; ein geschützter Teil daran müsste nach dem Kampf warten).
-- → die Breite
function Panel.FitWidth()
    local side, pf = ui.side, Professions()
    if not (side and pf) then return Panel.SIDE_W end
    local function Room(where)
        local room = Core.DockRoom(side, pf, where, Panel.SIDE_GAP)
        return room and math.floor(room - Panel.SCREEN_MARGIN) or nil
    end
    local width, room = Panel.SIDE_W, Room("right")
    if room and room < Panel.SIDE_MIN then
        local left = Room("left")
        if left and left > room then room = left end
    end
    width = Core.PanelWidth(room, width, Panel.SIDE_MIN) or Panel.SIDE_MIN   -- Regel aus ezCore
    if side:GetWidth() ~= width then
        side:SetWidth(width)
        side:Place()
    end
    LayoutButtons(width)
    return width
end

-- Blizzards inneren Kasten zwischen Kopf (bzw. Titelleiste) und Knöpfe legen, die Liste in den Kasten – wie ezTalent
-- (Core.PanelInset; vorher lag die Liste frei, der Kasten fest bei 60 unter dem Rand quer unter dem Kopf).
-- → der Kasten oder nil (Vorlage ohne Inset: die Liste wie früher frei unter dem Kopf)
local function LayoutList(withHead, buttonsTop)
    local side, scroll = ui.side, ui.target.scroll
    local below = withHead and side.ListHead or VIEW_TOP
    local inset = Core.PanelInset(side, below, buttonsTop + LOOK.buttonGap, { left = LOOK.headLeft, gap = LOOK.headGap })
    scroll:ClearAllPoints()
    if inset then
        scroll:SetPoint("TOPLEFT", inset, "TOPLEFT", LOOK.insetLeft, -LOOK.insetTop)
        scroll:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -LOOK.insetRight, LOOK.insetTop)
    else
        scroll:SetPoint("TOPLEFT", side, "TOPLEFT", 10, -(withHead and VIEW_TOP + HEAD_H or VIEW_TOP))
        scroll:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", -28, buttonsTop + LOOK.buttonGap)
    end
    return inset
end
Panel.LayoutList = LayoutList

local function OnTick(_, elapsed)
    if not ui.ticking then return end
    ui.elapsed = ui.elapsed + (elapsed or 0)
    if ui.elapsed >= TICK then
        ui.elapsed = 0
        Panel.Refresh()
    end
end

---------------------------------------------------------------------------
-- Kopf der Ansicht „Listen“ (Spieltest vom 21.11.2026: „ich muss listen anlegen, umbenennenund löschen können und
-- auch items oder herstellungsgegenstände hinzufügen können, am besten wie original blizz mit shift linke maustaste
-- auf icon in suche einfügen“): Listenwahl, Neu, Umbenennen, Löschen; Eingabefeld „Hinzufügen“ mit Knopf. Jede
-- Funktion hat ihren sichtbaren Knopf (Leitlinie 3); Shift-Klick geht in das Feld, solange es den Fokus hat.
---------------------------------------------------------------------------

local HEAD_ICONS = {
    new = "Interface\\PaperDollInfoFrame\\Character-Plus",
    rename = "Interface\\Buttons\\UI-GuildButton-PublicNote-Up",
    delete = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
    add = "Interface\\Buttons\\UI-PlusButton-Up",
}

-- Symbolknöpfe im Kopf „Listen“ (Neu, Umbenennen, Löschen): HEAD_ICON groß, Abstand wie die Knopfreihe unten
-- (Core.PANEL_BUTTONS.space – Entscheidung des Nutzers vom 21.11.2026 „6 für alle“, auch für den Kopf: „perfekt, ja
-- behebe das noch“; vorher 4). Die Listenwahl links endet einen Abstand vor dem ersten Symbolknopf.
local HEAD_ICON = 20
local function HeadButton(parent, key, title, tip, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(HEAD_ICON, HEAD_ICON)
    button:SetNormalTexture(HEAD_ICONS[key])
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button:SetScript("OnClick", function(self)
        Core.PlaySound("IG_MAINMENU_OPTION_CHECKBOX_ON")
        onClick(self)
    end)
    button:SetScript("OnEnter", function(self) Core.ShowTip(self, title, tip, "ANCHOR_TOP") end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    if button.SetMotionScriptsWhileDisabled then button:SetMotionScriptsWhileDisabled(true) end
    return button
end

-- Menü „Liste wählen“: alle Listen (gewählte mit Punkt) und „Neue Liste …“. Ohne Blizzards Menü: nächste Liste.
function Panel.PickList(owner)
    local lists = Core.Lists and Core.Lists.All() or {}
    local current = ns.Shopping.Selected()
    local opened = Core.Menu.Open(owner, function(root)
        Core.Menu.Title(root, L.LIST_PICK)
        for _, list in ipairs(lists) do
            Core.Menu.Radio(root, ("%s (%d)"):format(list.name, #(list.items or {})),
                function() return ns.Shopping.Selected() end, function(value) ns.Shopping.Select(value) end, list)
        end
        Core.Menu.Divider(root)
        Core.Menu.Button(root, L.LIST_NEW, function() ns.Shopping.AskCreate() end)
    end)
    if opened or #lists == 0 then return opened end
    local index = 1
    for i, list in ipairs(lists) do
        if list == current then index = i % #lists + 1 end
    end
    return ns.Shopping.Select(lists[index])
end

-- Gegenstand, Link oder Rezept aus dem Eingabefeld übernehmen. → Eintrag oder nil
function Panel.AddFromInput(value)
    local entry = ns.Shopping.AddItem(Panel.LinkEntry(value) or value)
    if entry and ui.listInput then ui.listInput:SetText("") end
    return entry
end

-- Shift-Klick auf das Ergebnis-Symbol des gewählten Rezepts: der hergestellte Gegenstand (Rezept), sonst nil – dann
-- zählt der Gegenstand selbst (Material, gekaufte Ware).
function Panel.LinkEntry(link)
    if type(link) ~= "string" or not Core.Lists then return nil end
    local itemID = Core.Lists.ParseLink(link)
    local recipeID = itemID and CraftingShown() and Panel.SelectedRecipeID()
    local recipe = recipeID and Data.Recipe(recipeID)
    if recipe and recipe.product == itemID then return { recipe = recipeID, count = 1 } end
    return nil
end

-- Shift-Klick (ezCores Core.OnInsertLink): nur, solange das Feld „Hinzufügen“ den Fokus hat – wie Blizzards Suchfeld.
local function OnInsertLink(link)
    local input = ui.listInput
    if not (input and input:IsVisible() and input:HasFocus()) then return false end
    local entry = Panel.AddFromInput(link)
    if entry then ns.Print(L.LIST_ADDED:format(ns.Shopping.Name(entry), ns.Shopping.Selected().name)) end
    return entry ~= nil
end

local function CreateListHead(side)
    local head = CreateFrame("Frame", nil, side)
    head:SetPoint("TOPLEFT", side, "TOPLEFT", LOOK.headLeft, -VIEW_TOP)
    head:SetPoint("TOPRIGHT", side, "TOPRIGHT", -LOOK.headLeft, -VIEW_TOP)
    head:SetHeight(HEAD_H)
    local ok, pick = pcall(CreateFrame, "Button", nil, head, "SharedButtonSmallTemplate")
    if not (ok and pick) then
        ok, pick = pcall(CreateFrame, "Button", nil, head, "UIPanelButtonTemplate")
        if not (ok and pick) then pick = CreateFrame("Button", nil, head) end
    end
    pick:SetHeight(BUTTON_H)
    pick:SetPoint("TOPLEFT", head, "TOPLEFT", 0, 0)
    pick:SetPoint("RIGHT", head, "RIGHT", -(3 * HEAD_ICON + 3 * BUTTON_SPACE), 0)
    pick:SetScript("OnClick", function(self) Panel.PickList(self) end)
    pick:SetScript("OnEnter", function(self) Core.ShowTip(self, L.LIST_PICK, L.LIST_PICK_TIP, "ANCHOR_TOP") end)
    pick:SetScript("OnLeave", GameTooltip_Hide)
    head.pick = pick
    head.delete = HeadButton(head, "delete", L.LIST_DELETE, L.LIST_DELETE_TIP, function() ns.Shopping.AskDelete() end)
    head.delete:SetPoint("TOPRIGHT", head, "TOPRIGHT", 0, -1)
    head.rename = HeadButton(head, "rename", L.LIST_RENAME, L.LIST_RENAME_TIP, function() ns.Shopping.AskRename() end)
    head.rename:SetPoint("RIGHT", head.delete, "LEFT", -BUTTON_SPACE, 0)
    head.new = HeadButton(head, "new", L.LIST_NEW, L.LIST_NEW_TIP, function() ns.Shopping.AskCreate() end)
    head.new:SetPoint("RIGHT", head.rename, "LEFT", -BUTTON_SPACE, 0)
    -- Eingabefeld „Hinzufügen“: Name, Link oder Shift-Klick auf Gegenstand, Rezept-Symbol oder Rezept
    local okInput, input = pcall(CreateFrame, "EditBox", "ezCraftListInput", head, "InputBoxTemplate")
    if not (okInput and input) then input = CreateFrame("EditBox", "ezCraftListInput", head) end
    input:SetAutoFocus(false)
    input:SetHeight(20)
    input:SetPoint("TOPLEFT", pick, "BOTTOMLEFT", 6, -4)
    input:SetPoint("RIGHT", head, "RIGHT", -28, 0)
    input:SetScript("OnEnterPressed", function(self)
        local text = self:GetText()
        if Panel.AddFromInput(text) == nil and Core.Trim(text or "") ~= "" then ns.Print(L.LIST_ADD_FAILED) end
        self:ClearFocus()
    end)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    input:SetScript("OnEnter", function(self) Core.ShowTip(self, L.LIST_INPUT, L.LIST_INPUT_TIP, "ANCHOR_TOP") end)
    input:SetScript("OnLeave", GameTooltip_Hide)
    input.hint = input:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    input.hint:SetPoint("LEFT", input, "LEFT", 2, 0)
    input.hint:SetText(L.LIST_INPUT_HINT)
    local function Hint() input.hint:SetShown((input:GetText() or "") == "" and not input:HasFocus()) end
    input:SetScript("OnEditFocusGained", Hint)
    input:SetScript("OnEditFocusLost", Hint)
    input:SetScript("OnTextChanged", Hint)
    head.add = HeadButton(head, "add", L.LIST_ADD, L.LIST_ADD_TIP, function()
        local text = input:GetText()
        if Core.Trim(text or "") == "" then
            input:SetFocus()       -- leer: ins Feld, dann Shift-Klick oder tippen
        elseif Panel.AddFromInput(text) == nil then
            ns.Print(L.LIST_ADD_FAILED)
        end
    end)
    head.add:SetPoint("LEFT", input, "RIGHT", 6, 0)
    ui.listInput = input
    Core.OnInsertLink(OnInsertLink, ADDON)
    head:Hide()
    return head
end

-- Kopf zeigen und füllen (nur in der Ansicht „Listen“). → true, wenn er zu sehen ist
local function UpdateListHead(tab)
    local head = ui.side.ListHead
    local show = tab == "shopping"
    head:SetShown(show)
    if not show then
        if ui.listInput and ui.listInput:HasFocus() then ui.listInput:ClearFocus() end
        return false
    end
    local list = ns.Shopping.Selected()
    head.pick:SetText(list and L.LIST_PICK_TEXT:format(list.name, #(list.items or {})) or L.LIST_PICK_NONE)
    local editable = list ~= nil and Core.Lists.Editable(list)
    head.rename:SetEnabled(editable)
    head.delete:SetEnabled(list ~= nil)
    head.add:SetEnabled(list == nil or editable)
    ui.listInput:SetEnabled(list == nil or editable)
    for _, b in ipairs({ head.rename, head.delete, head.add }) do
        local t = b.GetNormalTexture and b:GetNormalTexture()
        if t and t.SetDesaturated then t:SetDesaturated(not b:IsEnabled()) end
    end
    return true
end

-- Das Seitenteil (Core.NewSidePanel) im gemeinsamen Rahmen der Seitenteile (Core.PanelLook: Blizzards
-- ButtonFrameTemplate, Titel = Ansicht, X schließt): Inhalt, Knopfleiste; in „Listen“ dazu der Kopf.
local function CreateSide(pf)
    local side = Core.NewSidePanel(pf, {
        name = "ezCraftSide", width = Panel.SIDE_W, gap = Panel.SIDE_GAP, owner = ADDON, template = "ButtonFrameTemplate",
        store = ns.db and ns.db.window, key = "open", open = true,
        tip = L.SIDE_TITLE, tipBody = L.SIDE_ARROW_TIP,
        onToggle = function() Panel.Refresh() end,
        onPlaced = function() Panel.RefreshSoon() end,
    })
    if not side then return nil end
    Core.PanelLook(side, L.TITLE, { close = true, onClose = function() side:Close() end })
    if type(side.CloseButton) == "table" then
        side.CloseButton:SetScript("OnEnter", Core.TipScript(L.SIDE_CLOSE, L.SIDE_CLOSE_TIP))
        side.CloseButton:SetScript("OnLeave", GameTooltip_Hide)
    end
    local inset = type(side.Inset) == "table" and side.Inset or side
    side.Art = inset:CreateTexture(nil, "BACKGROUND", nil, 2)
    side.Art:SetPoint("TOPLEFT", inset, "TOPLEFT", 3, -3)
    side.Art:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -3, 3)
    side.Art:SetAlpha(0.6)
    side.Art:Hide()
    side.ListHead = CreateListHead(side)
    ui.target = NewTarget(side)
    CreateButtons(side)
    LayoutButtons(Panel.SIDE_W)
    LayoutList(false, BUTTONS_TOP)
    -- Restzeiten (Abklingzeiten) laufen weiter, solange sie zu sehen sind.
    side:SetScript("OnUpdate", OnTick)
    -- Seitenteil zu: der sichere Knopf „Entzaubern“ darf nicht über einer unsichtbaren Zeile stehen bleiben.
    side:HookScript("OnHide", function() if ns.Salvage then ns.Salvage.Disarm() end end)
    return side
end

Panel.TAB_ICON = "Interface\\Icons\\Trade_BlackSmithing"   -- das Symbol von ezCraft (ezCraft.toc, IconTexture)

-- Symbol-Reiter der gewählten Ansicht, sonst der erste sichtbare – solange zu sehen (Ziel des Rundgangs, Prüfungen).
function Panel.SideTab()
    local tab = ui.tabs[Tab()]
    if tab and tab:IsVisible() then return tab end
    for _, key in ipairs(TAB_KEYS) do
        tab = ui.tabs[key]
        if tab and tab:IsVisible() then return tab end
    end
    return nil
end

local function Create()
    local pf = Professions()
    if ui.side then return true end
    if not (pf and CraftingPage()) then return false end
    ui.side = CreateSide(pf)
    if not ui.side then return false end
    ui.side.arrow:Hide()
    CreateTabs(pf)
    -- Blasen zu Teilen im Seitenteil schließen mit ihm (die zu den Symbol-Reitern hängt am Berufefenster, die zu den
    -- Knöpfen in Blizzards Rezeptbereich an diesem).
    for _, step in ipairs(TOUR_STEPS) do
        if step.key ~= "side.arrow" and step.key ~= "side.tabs" and step.key ~= "recipe.buttons" then step.parent = ui.side end
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

-- Seitenteil auf- oder zuklappen (Symbol-Reiter, /ezcraft fenster). Ohne Berufefenster nur den Zustand merken.
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
    if ns.Schematic then ns.Schematic.Refresh() end   -- Zeile und Knöpfe in Blizzards Rezeptbereich
    local side = ui.side
    if not side then return end
    -- Der sichere Knopf „Entzaubern“ gehört zu einer Zeile, die gleich neu belegt wird: erst lösen (CRAFT-09).
    local armedBefore = ns.Salvage and ns.Salvage.Armed()
    if ns.Salvage then ns.Salvage.Disarm() end
    local on = IsOn()
    side.arrow:Hide()   -- seit dem 21.11.2026 die Symbol-Reiter (CreateTabs)
    UpdateTabs(on)
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
    SyncViewArt()
    Core.PanelTitle(side, L["TAB_" .. tab])
    Panel.FitWidth()
    LayoutList(UpdateListHead(tab), UpdateWithdraw(tab))
    ui.ticking = false
    BeginRows(ui.target)
    -- Kein Platz neben dem Berufefenster: ezCore legt das Seitenteil innen darüber – das Seitenteil sagt es.
    if side.mode == "overlap" then Text(L.SIDE_OVERLAP, 1, 0.3, 0.3) end
    if tab == "shopping" then
        ShowShopping()
    elseif tab == "cooldowns" then
        ShowCooldowns()
    elseif tab == "salvage" then
        ShowSalvage()
        if not Core.InCombat() then RearmUnderMouse(armedBefore) end
    else
        local prof = ns.Teach.Current()
        local key = prof and (prof.key or prof.name)
        if expandedFor ~= key then expanded, expandedFor = {}, key end
        if tab == "when" then ShowWhen() else ShowWhere() end
    end
    EndRows()
    UpdateButtons(tab)
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
function Panel.ListInput() return ui.listInput end
function Panel.Tab() return Tab() end
function Panel.Scroll() return ui.target and ui.target.scroll end
function Panel.WithdrawButton() return ui.withdraw end
function Panel.Rows()
    local target = ui.target
    if not target then return {}, 0 end
    return target.rows, target.used
end

---------------------------------------------------------------------------
-- Anbindung an Blizzards Berufefenster
---------------------------------------------------------------------------

-- Ein Rezept in Blizzards Liste gewählt: die Zeile und die Knöpfe in Blizzards Rezeptbereich folgen ihm (Schematic.lua;
-- das Seitenteil bleibt bei seiner Ansicht – seit dem 21.11.2026 gibt es keine Rezeptansicht mehr). Das Rezept zählt als „zuletzt angesehen“ (sein
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
    RefreshSoon()
end

local function Attach()
    local pf = Professions()
    if not pf or ui.side then return end
    if not Create() then return end
    -- Beim Öffnen des Berufefensters immer die Listen (Wunsch des Nutzers vom 21.11.2026: „standardmäßig sollen dann
    -- die ezcraft listen beim berufe angezigt werden“; eine Ansicht von vorhin passt selten zum neuen Beruf).
    pf:HookScript("OnShow", function()
        if ns.db then ns.db.window.tab = "shopping" end
        Panel.PlaceTabs()
        Panel.Refresh()
        -- Blizzard setzt seine Berufe-Reiter erst nach dem Zeigen: einen Frame später noch einmal darunter rücken
        local timer = rawget(_G, "C_Timer")
        if type(timer) == "table" and type(timer.After) == "function" then timer.After(0, Panel.PlaceTabs) end
    end)
    pf:HookScript("OnHide", function()
        ns.Teach.Unpick()
        Panel.Refresh()
    end)
    local page = CraftingPage()
    page:HookScript("OnShow", function()
        ns.Teach.Unpick()         -- jetzt gilt der Beruf des Fensters
        Panel.Refresh()
    end)
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
            Panel.PlaceTabs()
            RefreshSoon()
        end, ui)
    end
    Panel.Refresh()
end

ns.OnReady(function()
    ns.WhenAddOnLoaded("Blizzard_Professions", Attach)
end)

-- Auch bei zugeklapptem Seitenteil, solange das Berufefenster ein Rezept zeigt: Kostenzeile und Knopf „Auktionshaus“
-- im Rezeptbereich (Schematic.lua) folgen Bestand und Preisen (Review 21.11.2026).
local function RefreshIfOpen()
    if Panel.IsOpen() or (ns.Enabled("panel") and CraftingShown()) then RefreshSoon() end
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
-- „Wo kommt was“: ein Lehrer wurde besucht, Questie hat die Lehrer einer Karte gelesen
Core.Listen("NPCS_CHANGED", RefreshIfOpen, ADDON)
Core.Listen("QUESTIE_TOWNSFOLK", RefreshIfOpen, ADDON)
ns.On("SKILL_LINES_CHANGED", RefreshIfOpen)
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
