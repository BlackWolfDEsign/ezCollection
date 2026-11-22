local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Unter-Reiter „Verlauf“ neben Blizzards „Auktionen | Gebote“ (Reiter Auktionen): Verkäufe, Käufe, Rückläufer und
    überbotene Gebote mit Einnahmen, Ausgaben und Saldo des gewählten Zeitraums.
    Quelle ist ezCore.History("auction"): ezCore trägt die Einträge beim Entnehmen aus der Auktionshaus-Post ein,
    ezAuction zeigt sie nur an. Zeiträume (History.Since) und Summen (History.AuctionTotals) rechnet ezCore – eine
    Rechnung für ezAuction, ezMail und ezPanel. Auch die Auswahl der Zeiträume (History.PERIODS: heute, 7 Tage,
    30 Tage, alles) und ihre Texte (History.PeriodLabel, TypeLabel) kommen von dort: eine Auswahl für ezMail und
    ezAuction. Leert der Spieler den Verlauf („ezCollection“ → Daten → „Verlauf leeren“), folgt die offene Liste
    (HISTORY_CLEARED), ebenso bei neuen und zurückgenommenen Einträgen (HISTORY_ADDED, HISTORY_REMOVED).

    Eigener Reiter aus Blizzards Vorlage (AuctionHouseFrameTopTabTemplate), eigene Fläche über Blizzards Listen.
    Blizzards Reiter bleiben unberührt bis auf ihr Aussehen (PanelTemplates_SelectTab/DeselectTab rufen nur
    Widget-Methoden auf, schreiben nichts in Blizzards Tabellen); ein Klick auf „Auktionen“ oder „Gebote“ schließt
    den Verlauf wieder.
]]

local History = {}
ns.History = History

local KIND = "auction"
local ROW_HEIGHT = 20

-- Zeiträume: die EINE Auswahl aus ezCore (History.PERIODS = today, week, month, all – dieselbe wie in ezMail),
-- als { { Schlüssel } … } wie CHARS und KINDS. ezAuction verlangt ezCore 1.10.1 mit History.PERIODS (Core.lua,
-- needs) – eine eigene Ersatzliste gibt es nicht mehr. OWN_PERIODS bleibt als Name und verweist auf ezCores Liste.
History.OWN_PERIODS = Core.History and Core.History.PERIODS
function History.BuildPeriods()
    local keys = Core.History and Core.History.PERIODS
    local periods = {}
    -- Ist ezCore zu alt, meldet das Gerüst es und das Modul bleibt still; hier nur kein Ladefehler.
    for _, key in ipairs(type(keys) == "table" and keys or {}) do periods[#periods + 1] = { key } end
    return periods
end
History.PERIODS = History.BuildPeriods()
History.CHARS = { { "me" }, { "all" } }
-- Beschriftung der Charakter-Auswahl: „Alle Charaktere“ ist ezCores Text (Core.L.ALL_CHARS, UE-08), „Dieser Charakter“
-- ezAuctions HISTORY_CHAR_me.
function History.CharLabel(key)
    if key == "all" then return L.ALL_CHARS end
    return L["HISTORY_CHAR_" .. tostring(key)]
end
History.KINDS = {
    { "all" },
    { "sale", { sale = true } },
    { "buy", { buy = true } },
    { "back", { expired = true, cancelled = true } },
    { "outbid", { outbid = true } },
}
local COLORS = {
    sale = { 0.25, 1, 0.25 }, buy = { 1, 0.82, 0 }, outbid = { 1, 0.5, 0.25 },
    expired = { 0.6, 0.6, 0.6 }, cancelled = { 0.6, 0.6, 0.6 },
}

local tab, tabHolder, panel, list, header, summary, emptyText, copyButton
local dropdowns = {}
local shown = false

local function AuctionsFrame() return AuctionHouseFrame and AuctionHouseFrame.AuctionsFrame end

local function Lookup(options, key)
    for _, option in ipairs(options) do
        if option[1] == key then return option end
    end
    return options[1]
end

-- Text eines Zeitraums aus ezCore (History.PeriodLabel; long = „Letzte 7 Tage“, sonst die Kurzform „7 Tage“ für
-- die Auswahl); kennt ezCore den Schlüssel nicht, der Schlüssel selbst (wie ezMail).
function History.PeriodLabel(key, long)
    return Core.History.PeriodLabel(key, not long) or tostring(key)
end

-- Verlauf von ezCore (nil, solange ezCore zu alt ist).
function History.Source()
    local source = Core.History
    if type(source) ~= "table" then return nil end
    for _, fn in ipairs({ "List", "Since", "AuctionTotals" }) do
        if type(source[fn]) ~= "function" then return nil end
    end
    return source
end

---------------------------------------------------------------------------
-- Daten
---------------------------------------------------------------------------

-- Gewählter Zeitraum, Charakter und Art (in ezAuctionDB.ui, für alle Charaktere gleich).
function History.Filter()
    local ui = ns.db and ns.db.ui
    local filter = ui and ui.history
    if type(filter) ~= "table" then
        filter = {}
        if ui then ui.history = filter end
    end
    -- Gemerkte Auswahl aus der Zeit der eigenen Liste: „24 Stunden“ heißt in ezCores Auswahl „Heute“.
    if filter.period == "day" and Lookup(History.PERIODS, "day")[1] ~= "day" then filter.period = "today" end
    filter.period = Lookup(History.PERIODS, filter.period)[1] == filter.period and filter.period or "week"
    filter.char = filter.char == "all" and "all" or "me"
    filter.kind = Lookup(History.KINDS, filter.kind)[1] == filter.kind and filter.kind or "all"
    return filter
end

function History.SetFilter(field, value)
    History.Filter()[field] = value
    History.Refresh()
end

-- Filter für ezCore.History.List/AuctionTotals: Zeitraum und Charakter aus der Auswahl, types = erlaubte Arten
-- oder nil.
function History.Query(types, filter)
    filter = filter or History.Filter()
    local query = {}
    if filter.char ~= "all" then query.char = Core.charKey end
    local source = History.Source()
    if source then query.since = source.Since(filter.period) end
    if types then query.match = function(entry) return types[entry.type] == true end end
    return query
end

-- Einträge der Auswahl, neueste zuerst.
function History.Entries(filter)
    local source = History.Source()
    if not source then return {} end
    filter = filter or History.Filter()
    return source.List(KIND, History.Query(Lookup(History.KINDS, filter.kind)[2], filter))
end

-- Zeitraum und Charakter (ohne Art-Filter), gerechnet von ezCore (History.AuctionTotals): Einnahmen = Netto der
-- Verkäufe, Ausgaben = Kaufpreis, Saldo, Gebühren, Anzahl je Art (sale, buy, back, outbid).
function History.Totals(filter)
    local source = History.Source()
    if not source then
        return { income = 0, spent = 0, fees = 0, balance = 0, sale = 0, buy = 0, back = 0, outbid = 0, ahIn = 0 }
    end
    return source.AuctionTotals(History.Query(nil, filter))
end

-- Betrag einer Zeile: Verkauf netto (+), Kauf (−), überboten (Gebot zurück, +), Rückläufer ohne Gold (nil).
function History.Amount(entry)
    if entry.type == "sale" then return Core.Num(entry.net) or Core.Num(entry.gross) end
    if entry.type == "buy" then
        local gross = Core.Num(entry.gross)
        return gross and -gross or nil
    end
    if entry.type == "outbid" then return Core.Num(entry.net) end
    return nil
end

function History.AmountText(entry)
    local amount = History.Amount(entry)
    if not amount then return Core.Grey("—") end
    if entry.type == "outbid" then return Core.Grey(Core.Money(amount)) end
    return Core.Money(amount, nil, true)
end

-- Text der Art aus ezCore (History.TypeLabel: „Verkauft“ …); unbekannte Art: ihr Schlüssel (wie ezMail). Ohne Farbe –
-- für „Als Text kopieren“; die Liste färbt ihn über History.TypeText.
function History.TypeName(entry)
    return Core.History.TypeLabel(entry.type) or tostring(entry.type or "?")
end

function History.TypeText(entry)
    local text = History.TypeName(entry)
    local color = COLORS[entry.type]
    if color then text = Core.ColorCode(color[1], color[2], color[3]) .. text .. "|r" end
    return text
end

-- Link des Gegenstands: aus dem Eintrag, sonst über den Namen (Verkäufe kommen nur mit Namen, ohne Anhang).
function History.Link(entry)
    if type(entry.link) == "string" and entry.link ~= "" then return entry.link end
    if type(entry.item) ~= "string" or entry.item == "" or not C_Item then return nil end
    local _, link = Core.Call(C_Item.GetItemInfo, entry.item)
    return type(link) == "string" and link or nil
end

function History.ItemText(entry)
    local link = History.Link(entry)
    local text = link or entry.item or "?"
    local count = Core.Num(entry.n)
    if count and count > 1 then text = text .. " " .. Core.White("×" .. count) end
    return text
end

function History.Icon(entry)
    return Core.ItemIcon(History.Link(entry))
end

function History.CharText(entry)
    if not entry.c then return "" end
    return Core.CharName(Core.Char(entry.c), entry.c)
end

function History.WhoText(entry)
    if type(entry.who) ~= "string" or entry.who == "" then return "" end
    return Core.ShortName(entry.who)
end

function History.TimeText(entry)
    local stamp = Core.Num(entry.t)
    if not stamp then return "?" end
    return Core.DateText(stamp, "full")
end

-- Geschätzter Verkaufstag eines Verkaufs (ezCores Feld sold mit soldEst, W-56): nur das Datum, nie eine Uhrzeit – die
-- Schätzung rechnet aus der Restlaufzeit des Briefs zurück, und deren Verzögerung ist auf Forever ungemessen (VP-73).
-- → „14.11.“ bzw. nil ohne Schätzung (Übergabe aus Welle 7, gebaut in Welle 23).
function History.SoldText(entry)
    local sold = type(entry) == "table" and entry.type == "sale" and Core.Num(entry.sold)
    if not sold or sold <= 0 then return nil end
    return date(Core.L.DATE_DAY or "%d.%m.", sold)
end

---------------------------------------------------------------------------
-- „Als Text kopieren“ (V5 aus docs/archiv/eroerterung-datenbank.md, vom Nutzer am 16.11.2026 freigegeben; Welle 24)
---------------------------------------------------------------------------
-- Die Liste der Auswahl (Zeitraum, Charakter, Art) als Tabelle für ezCores Kopierfeld (Core.CopyAsText aus Welle 23d),
-- älteste zuerst; darunter nach einer leeren Zeile die Bilanz wie in der Summenzeile (Einnahmen, Ausgaben, Saldo,
-- Gebühren – wie ezCore sie rechnet, ohne Art-Filter). Ausgaben stehen mit Minus, wie die Käufe in der Spalte „Betrag“.
-- „Käufer/Verkäufer“ ist eine Namens-Spalte (personal): ab Werk nicht im Text, das Häkchen „Namen mitnehmen“ im
-- Kopierfeld nimmt sie auf (Frage E6 des Berichts, vom Nutzer am 16.11.2026 nach Empfehlung entschieden). Die eigenen
-- Charaktere stehen wie in der Liste nur bei „Alle Charaktere“ da. Jede Zeile nennt ihre Quelle (Leitlinie 11).

-- Zeitpunkt eines Eintrags als „2026-11-14 18:05“ (Ortszeit, liest jede Tabellenkalkulation)
function History.CopyTime(entry)
    local stamp = type(entry) == "table" and Core.Num(entry.t)
    if not stamp then return nil end
    return date("%Y-%m-%d %H:%M", stamp)
end

-- → Spalten, Zeilen, Zahl der Einträge (ohne die Bilanz)
function History.CopyTable(filter)
    filter = filter or History.Filter()
    local money = "money"   -- Gold mit vier Stellen (ezCores Spalte, Core.GoldDecimal)
    local columns = {
        { key = "time", title = L.HISTORY_COL_TIME },
        { key = "kind", title = L.HISTORY_COL_KIND },
        { key = "item", title = L.HISTORY_COL_ITEM },
        { key = "quantity", title = L.COPY_COL_QTY },
        -- Köpfe mit der Einheit wie im Seitenteil: die Zahlen stehen in Gold, nicht in Kupfer
        { key = "amount", title = L.COPY_COL_AMOUNT, format = money },
        { key = "fee", title = L.COPY_COL_FEE, format = money },
        { key = "who", title = L.HISTORY_COL_WHO, personal = true },
    }
    if filter.char == "all" then columns[#columns + 1] = { key = "char", title = L.HISTORY_COL_CHAR } end
    columns[#columns + 1] = { key = "source", title = L.COPY_COL_SOURCE }
    local rows = {}
    local entries = History.Entries(filter)
    for i = #entries, 1, -1 do   -- ezCore liefert die neuesten zuerst
        local e = entries[i]
        rows[#rows + 1] = { time = History.CopyTime(e), kind = History.TypeName(e), item = e.item or History.Link(e),
            quantity = Core.Num(e.n), amount = History.Amount(e), fee = Core.Num(e.fee), who = History.WhoText(e),
            char = History.CharText(e), source = L.COPY_SOURCE_HISTORY }
    end
    local totals = History.Totals(filter)
    local source = L.COPY_SOURCE_TOTALS:format(History.PeriodLabel(filter.period, true))
    rows[#rows + 1] = {}
    rows[#rows + 1] = { kind = L.COPY_INCOME, amount = totals.income, source = source }
    rows[#rows + 1] = { kind = L.COPY_SPENT, amount = -(Core.Num(totals.spent) or 0), source = source }
    rows[#rows + 1] = { kind = L.COPY_BALANCE, amount = totals.balance, source = source }
    rows[#rows + 1] = { kind = L.COPY_FEES, fee = totals.fees, source = source }
    return columns, rows, #entries
end

-- Gibt es ezCores Kopierfeld (Welle 23d)? Ohne ihn steht kein Knopf da (defensiv, ezAuction verlangt ihn nicht in needs).
function History.CanCopy()
    return type(Core.CopyAsText) == "function"
end

-- Knopf „Als Text kopieren“: öffnet das Kopierfeld mit der Auswahl. → der Dialog | nil (kein Eintrag, kein Kopierfeld)
function History.Copy()
    if not History.CanCopy() then return nil end
    local filter = History.Filter()
    local columns, rows, count = History.CopyTable(filter)
    if count == 0 then return nil end
    return Core.CopyAsText({ title = L.HISTORY_COPY_TITLE:format(History.PeriodLabel(filter.period, true)),
        hint = Core.L.COPYTEXT_HINT and Core.L.COPYTEXT_HINT:format(count) or nil, columns = columns, rows = rows,
        anchor = AuctionHouseFrame, owner = ADDON })
end

---------------------------------------------------------------------------
-- Anzeige
---------------------------------------------------------------------------

-- Spalten: links Zeit und Art, rechts Charakter (nur bei „Alle Charaktere“), Käufer/Verkäufer und Betrag,
-- dazwischen der Gegenstand.
local function Layout(row, allChars)
    local cells = row.cells
    cells.time:ClearAllPoints()
    cells.time:SetPoint("LEFT", row, "LEFT", 6, 0)
    cells.time:SetWidth(80)
    cells.kind:ClearAllPoints()
    cells.kind:SetPoint("LEFT", cells.time, "RIGHT", 4, 0)
    cells.kind:SetWidth(80)
    cells.char:ClearAllPoints()
    cells.char:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    cells.char:SetWidth(allChars and 110 or 1)
    cells.char:SetShown(allChars)
    cells.who:ClearAllPoints()
    if allChars then
        cells.who:SetPoint("RIGHT", cells.char, "LEFT", -6, 0)
    else
        cells.who:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    end
    cells.who:SetWidth(120)
    cells.amount:ClearAllPoints()
    cells.amount:SetPoint("RIGHT", cells.who, "LEFT", -10, 0)
    cells.amount:SetWidth(110)
    cells.item:ClearAllPoints()
    cells.item:SetPoint("LEFT", cells.kind, "RIGHT", 4, 0)
    cells.item:SetPoint("RIGHT", cells.amount, "LEFT", -10, 0)
end

local function NewCells(row, font)
    local cells = {}
    for _, key in ipairs({ "time", "kind", "item", "amount", "who", "char" }) do
        local cell = row:CreateFontString(nil, "OVERLAY", font)
        cell:SetJustifyH(key == "amount" and "RIGHT" or "LEFT")
        if cell.SetWordWrap then cell:SetWordWrap(false) end
        cells[key] = cell
    end
    row.cells = cells
    return cells
end

local function RowTooltip(row)
    local entry = row.entry
    if not entry then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local link = History.Link(entry)
    if link then
        GameTooltip:SetHyperlink(link)
    else
        Core.TipTitle(GameTooltip, entry.item or "?")
    end
    Core.Tooltip.Gap(GameTooltip)   -- ezCores einer Trenner statt eigener Leerzeile (Gegenprüfung 19.11.2026)
    Core.TipDoubleLine(GameTooltip, History.TypeText(entry), History.TimeText(entry), "highlight", "highlight")
    local function Money(label, value)
        value = Core.Num(value)
        if value then Core.TipDoubleLine(GameTooltip, label, Core.Money(value), "normal", "highlight") end
    end
    if entry.type == "sale" then
        Money(L.HISTORY_TIP_GROSS, entry.gross)
        Money(L.HISTORY_TIP_FEE, entry.fee)
        Money(L.HISTORY_TIP_DEPOSIT, entry.deposit)
        Money(L.HISTORY_TIP_NET, entry.net)
        if entry.who then Core.TipDoubleLine(GameTooltip, L.HISTORY_TIP_BUYER, History.WhoText(entry), "normal", "highlight") end
        -- geschätzter Verkaufstag, als Schätzung benannt (Leitlinie 11: woher die Angabe stammt)
        local sold = History.SoldText(entry)
        if sold then
            Core.TipDoubleLine(GameTooltip, L.HISTORY_TIP_SOLD, sold, "normal", "highlight")
            Core.TipLine(GameTooltip, L.HISTORY_TIP_SOLD_EST, "hint", true)
        end
    elseif entry.type == "buy" then
        Money(L.HISTORY_TIP_PRICE, entry.gross)
        if entry.who then Core.TipDoubleLine(GameTooltip, L.HISTORY_TIP_SELLER, History.WhoText(entry), "normal", "highlight") end
    elseif entry.type == "outbid" then
        Money(L.HISTORY_TIP_RETURNED, entry.net)
    else
        Core.TipLine(GameTooltip, L.HISTORY_TIP_BACK, "highlight", true)
    end
    if entry.c then Core.TipDoubleLine(GameTooltip, L.HISTORY_TIP_CHAR, History.CharText(entry), "normal", "highlight") end
    GameTooltip:Show()
end
History.RowTooltip = RowTooltip

local function InitRow(row, entry)
    if not row.cells then
        NewCells(row, "GameFontHighlightSmall")
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(Core.Style.ICON.line, Core.Style.ICON.line)   -- Design-System 2.3 (bis Welle 22 14)
        row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
        row.highlight:SetAllPoints()
        row.highlight:SetColorTexture(1, 1, 1, 0.08)
        row:SetScript("OnEnter", RowTooltip)
        row:SetScript("OnLeave", GameTooltip_Hide)
        -- Shift-Klick stellt den Gegenstand in den Chat wie in Blizzards Listen.
        row:SetScript("OnClick", function(self)
            local link = self.entry and History.Link(self.entry)
            if link and HandleModifiedItemClick then HandleModifiedItemClick(link) end
        end)
    end
    row.entry = entry
    local allChars = History.Filter().char == "all"
    Layout(row, allChars)
    local icon = History.Icon(entry)
    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT", row.cells.kind, "RIGHT", 4, 0)
    row.icon:SetTexture(icon)
    row.icon:SetShown(icon ~= nil)
    if icon then
        row.cells.item:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    end
    row.cells.time:SetText(History.TimeText(entry))
    row.cells.kind:SetText(History.TypeText(entry))
    row.cells.item:SetText(History.ItemText(entry))
    row.cells.amount:SetText(History.AmountText(entry))
    row.cells.who:SetText(History.WhoText(entry))
    row.cells.char:SetText(allChars and History.CharText(entry) or "")
end

function History.SummaryText(totals)
    return L.HISTORY_SUMMARY:format(Core.Money(totals.income), Core.Money(totals.spent),
        Core.Money(totals.balance, nil, true))
end

-- Auswahl über ezCores Auswahlfeld (Core.Menu.Dropdown, T18-12): Blizzards WowStyle1DropdownTemplate, ohne ihn ein
-- Knopf mit demselben Menü (vorher schaltete der Rückfall still weiter). Text auffrischen: control:RefreshText().
-- labelPrefix: Anfang des Text-Schlüssels oder eine Funktion Schlüssel → Text (Zeiträume: History.PeriodLabel).
local function NewDropdown(field, options, labelPrefix, width)
    local function Label(key)
        if type(labelPrefix) == "function" then return labelPrefix(key) end
        return L[labelPrefix .. key]
    end
    local function Current() return History.Filter()[field] end
    local control = Core.Menu.Dropdown(panel, width, function(root)
        for _, option in ipairs(options) do
            Core.Menu.Radio(root, Label(option[1]), Current, function(key) History.SetFilter(field, key) end, option[1])
        end
    end, function() return Label(Current()) end)
    -- Tooltip für beide Fassungen (Blizzards Dropdown behält seine eigenen Skripte, darum HookScript).
    control:HookScript("OnEnter", function(self)
        Core.ShowTip(self, L["HISTORY_FILTER_" .. field], L["HISTORY_FILTER_" .. field .. "_TIP"])
    end)
    control:HookScript("OnLeave", GameTooltip_Hide)
    return control
end

-- Aussehen der drei Reiter: im Verlauf ist nur „Verlauf“ gewählt, sonst Blizzards gewählter Reiter.
local function Select(button, selected)
    if not button then return end
    local fn = selected and PanelTemplates_SelectTab or PanelTemplates_DeselectTab
    if fn and button.Left and button.LeftActive then
        pcall(fn, button)
    elseif button == tab then
        button:SetEnabled(not selected)
    end
end

-- Die Fläche des Verlaufs über alles legen, was Blizzard in Übersicht und Liste zeigt (beim Zeigen, Blizzards Zeilen
-- entstehen erst mit den Daten; Spielbefund vom 21.11.2026: Blizzards Spaltenköpfe und „Keine Gegenstände gefunden“
-- lagen über dem Verlauf). ns.RaiseAbove in Core.lua.
local function RaisePanel()
    local frame = AuctionsFrame()
    if not (frame and panel) then return end
    ns.RaiseAbove(panel, frame.SummaryList, frame.AllAuctionsList)
    -- der eigene Reiter überlappt die Fläche um 2 Pixel: dieselbe Schicht, solange der Verlauf offen ist
    if tab then ns.StrataAbove(tab) end
end
History.RaisePanel = RaisePanel

-- Ebene des eigenen Reiters: gewählt über der Fläche des Verlaufs (er überlappt sie wie Blizzards Reiter um 2 Pixel),
-- sonst auf der Ebene von Blizzards „Gebote“ – darüber lag er auf der Kopfzeile der Liste (Spielbefund 16.11.2026).
local function TabLevel()
    local frame = AuctionsFrame()
    if not (frame and tab) then return end
    if shown and panel then
        tab:SetFrameLevel(math.max(tab:GetFrameLevel(), panel:GetFrameLevel() + 1))
    elseif frame.BidsTab and frame.BidsTab.GetFrameLevel then
        tab:SetFrameLevel(frame.BidsTab:GetFrameLevel())
    end
end

local function UpdateTabLooks()
    local frame = AuctionsFrame()
    if not (frame and tab) then return end
    local blizzardSelected = frame.GetTab and frame:GetTab() or (frame.IsDisplayingBids and frame:IsDisplayingBids() and 2 or 1)
    Select(tab, shown)
    Select(frame.AuctionsTab, not shown and blizzardSelected == 1)
    Select(frame.BidsTab, not shown and blizzardSelected == 2)
    TabLevel()
end

local function Build()
    local frame = AuctionsFrame()
    if panel or not frame or not History.Source() then return end

    -- Reiter: Blizzards Vorlage der Unter-Reiter, rechts neben „Gebote“ (Abstand wie PanelTemplates_AnchorTabs). Die
    -- Vorlage trägt sich in die Liste Tabs ihres Elternrahmens ein (PanelTabButtonTemplate parentArray="Tabs"); damit
    -- Blizzards AuctionsFrame.Tabs unberührt bleibt (Leitlinie 5), hängt der Reiter an einem eigenen Halter.
    tabHolder = tabHolder or CreateFrame("Frame", nil, frame)
    tabHolder:SetAllPoints(frame)
    for _, template in ipairs({ "AuctionHouseFrameTopTabTemplate", "PanelTopTabButtonTemplate", "UIPanelButtonTemplate" }) do
        local ok, button = pcall(CreateFrame, "Button", "ezAuctionHistoryTab", tabHolder, template)
        if ok and button then
            tab = button
            tab.isTabTemplate = template ~= "UIPanelButtonTemplate"
            break
        end
    end
    if not tab then return end
    tab:SetText(L.HISTORY_TAB)
    if not tab.isTabTemplate then tab:SetSize(90, 22) end
    if frame.BidsTab then
        tab:SetPoint("TOPLEFT", frame.BidsTab, "TOPRIGHT", ns.Layout.TAB_GAP, 0)
    else
        tab:SetPoint("TOPLEFT", frame, "TOPLEFT", 250, -1)
    end
    if PanelTemplates_TabResize and tab.isTabTemplate then pcall(PanelTemplates_TabResize, tab, 20, nil, 70) end
    tab:SetScript("OnClick", function()
        Core.PlaySound("IG_CHARACTER_INFO_TAB")
        History.Show()
    end)
    tab:SetScript("OnEnter", function(self) Core.ShowTip(self, L.HISTORY_TAB, ns.CmdText(L.HISTORY_TAB_TIP)) end)
    tab:SetScript("OnLeave", GameTooltip_Hide)

    -- Fläche über Blizzards Übersicht (links die Zusammenfassung, rechts die Liste).
    panel = CreateFrame("Frame", "ezAuctionHistory", frame, "InsetFrameTemplate")
    local top, bottom = frame.SummaryList or frame.AllAuctionsList, frame.AllAuctionsList
    if top and bottom then
        panel:SetPoint("TOPLEFT", top, "TOPLEFT", 0, 0)
        panel:SetPoint("BOTTOMRIGHT", bottom, "BOTTOMRIGHT", 0, 0)
    else
        panel:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -28)
        panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -5, 0)
    end
    panel:SetFrameLevel((bottom and bottom:GetFrameLevel() or frame:GetFrameLevel()) + 20)
    panel:EnableMouse(true)
    local background = panel:CreateTexture(nil, "BACKGROUND", nil, 1)
    background:SetPoint("TOPLEFT", 3, -3)
    background:SetPoint("BOTTOMRIGHT", -3, 3)
    if Core.AtlasExists("auctionhouse-background-index") then
        background:SetAtlas("auctionhouse-background-index")
    else
        background:SetColorTexture(0.05, 0.05, 0.05, 0.95)
    end
    panel:Hide()

    dropdowns.period = NewDropdown("period", History.PERIODS, function(key) return History.PeriodLabel(key) end, 150)
    dropdowns.period:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -6)
    dropdowns.char = NewDropdown("char", History.CHARS, History.CharLabel, 140)
    dropdowns.char:SetPoint("LEFT", dropdowns.period, "RIGHT", 8, 0)
    dropdowns.kind = NewDropdown("kind", History.KINDS, "HISTORY_KIND_", 130)
    dropdowns.kind:SetPoint("LEFT", dropdowns.char, "RIGHT", 8, 0)

    -- „Als Text kopieren“ (V5, Welle 24): rechts in der Zeile der Auswahl, Blizzards Textknopf; nur mit ezCores
    -- Kopierfeld, abgeschaltet (mit Grund im Tooltip), solange die Auswahl leer ist
    copyButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    copyButton:SetSize(150, 22)
    copyButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -6)
    copyButton:SetText(Core.L.COPYTEXT_TITLE)
    copyButton:SetMotionScriptsWhileDisabled(true)
    copyButton:SetScript("OnClick", function() History.Copy() end)
    copyButton:SetScript("OnEnter", function(self)
        Core.ShowTip(self, Core.L.COPYTEXT_TITLE, self:IsEnabled() and L.HISTORY_COPY_TIP:format(Core.L.COPYTEXT_NAMES or "?") or Core.Grey(L.HISTORY_COPY_EMPTY))
    end)
    copyButton:SetScript("OnLeave", GameTooltip_Hide)
    copyButton:Hide()

    -- Summe des Zeitraums in eigener Zeile über die ganze Breite (drei Goldbeträge passen nicht neben die Auswahl).
    summary = CreateFrame("Button", nil, panel)
    summary:SetHeight(18)
    summary:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -36)
    summary:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -36)
    summary.text = summary:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    summary.text:SetPoint("LEFT")
    summary.text:SetJustifyH("LEFT")
    summary:SetScript("OnEnter", function(self)
        local totals = History.Totals()
        Core.ShowTip(self, History.PeriodLabel(History.Filter().period, true),
            L.HISTORY_SUMMARY_TIP:format(totals.sale, totals.buy, totals.back, totals.outbid, Core.Money(totals.fees)))
    end)
    summary:SetScript("OnLeave", GameTooltip_Hide)

    header = CreateFrame("Frame", nil, panel)
    header:SetHeight(18)
    header:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -58)
    header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -22, -58)
    NewCells(header, "GameFontNormalSmall")
    for key, cell in pairs(header.cells) do cell:SetText(L["HISTORY_COL_" .. key:upper()]) end

    list = ns.NewScrollList(panel, ROW_HEIGHT, InitRow)
    list:SetPoints(4, -78, -8, 6)

    emptyText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyText:SetPoint("TOPLEFT", panel, "TOPLEFT", 40, -110)
    emptyText:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -40, -110)
    emptyText:SetJustifyH("CENTER")

    -- Blizzards Reiter „Auktionen“ und „Gebote“ schließen den Verlauf: ihr Klick ruft SetTab, und der Hook läuft
    -- auch, wenn Blizzard früh aussteigt (Klick auf den schon gewählten Reiter).
    if frame.SetTab then
        hooksecurefunc(frame, "SetTab", function() History.Hide() end)
    else
        for _, blizzardTab in ipairs({ frame.AuctionsTab, frame.BidsTab }) do
            if blizzardTab and blizzardTab.HookScript then
                blizzardTab:HookScript("OnClick", function() History.Hide() end)
            end
        end
    end
    frame:HookScript("OnHide", function() History.Hide() end)
    History.UpdateTab()
    -- Gleich beim Bau als nicht gewählter Reiter zeichnen: ohne PanelTemplates_DeselectTab zeigte die Vorlage beide
    -- Bilder (gewählt und nicht gewählt) und die Schrift zu hoch (Spielbefund 16.11.2026). Blizzards eigene Reiter
    -- bleiben dabei, wie Blizzard sie gesetzt hat
    Select(tab, shown)
    TabLevel()
end

function History.UpdateTab()
    if not tab then return end
    local show = ns.Enabled("historyTab")
    tab:SetShown(show)
    if not show and shown then History.Hide() end
end

function History.IsShown() return shown end

-- Reiter „Verlauf“, solange zu sehen (Ziel des Rundgangs); die Auswahlfelder für Prüfungen.
function History.Tab()
    return tab ~= nil and tab:IsVisible() and tab or nil
end
function History.Dropdowns() return dropdowns end
function History.CopyButton() return copyButton end

function History.Show()
    if not ns.Enabled("historyTab") then return false end
    Build()
    if not panel then return false end
    shown = true
    panel:Show()
    RaisePanel()
    UpdateTabLooks()
    History.Refresh()
    -- Unten im Reiter gehören Blizzards und ezAuctions Auktions-Knöpfe zur Übersicht, nicht zum Verlauf.
    ns.Fire("HISTORY_VIEW", true)
    return true
end

function History.Hide()
    if not shown then return end
    shown = false
    if panel then panel:Hide() end
    -- zu: der Reiter zurück auf Blizzards Schicht (sonst läge er auf der Kopfzeile der Liste, Spielbefund 16.11.2026)
    if tab then ns.StrataOf(tab) end
    UpdateTabLooks()
    ns.Fire("HISTORY_VIEW", false)
end

function History.Toggle()
    if shown then History.Hide() else History.Show() end
end

function History.Refresh()
    if not (panel and shown) then return end
    local entries = History.Entries()
    list:SetData(entries)
    for _, dropdown in pairs(dropdowns) do dropdown:RefreshText() end
    summary.text:SetText(History.SummaryText(History.Totals()))
    copyButton:SetShown(History.CanCopy())
    copyButton:SetEnabled(#entries > 0)
    local allChars = History.Filter().char == "all"
    Layout(header, allChars)
    if #entries > 0 then
        emptyText:Hide()
    else
        local source = History.Source()
        local any = source and #source.List(KIND, { limit = 1 }) > 0
        emptyText:SetText(any and L.HISTORY_EMPTY_FILTER or L.HISTORY_EMPTY)
        emptyText:Show()
    end
end

-- Text für Chat und Status: Einnahmen, Ausgaben, Saldo eines Zeitraums (dieser Charakter).
function History.PrintSummary()
    if not History.Source() then return ns.Print(L.STATUS_HISTORY_MISSING) end
    for _, period in ipairs({ "week", "month" }) do
        local totals = History.Totals({ period = period, char = "me", kind = "all" })
        ns.Print(L.HISTORY_PRINT:format(History.PeriodLabel(period, true), History.SummaryText(totals)))
    end
end

---------------------------------------------------------------------------
-- Auktionspost (AH-28) und Verkaufsempfehlung (AH-29), Welle 15 – nur Auskunft, nie eine Aktion
---------------------------------------------------------------------------
--[[
    History.Mail()  ezCores Auskunft „Auktionspost“ (History.AuctionMail, dieser Charakter), zusammengefasst:
                    { sale = Verkäufe in der Post, back = Rückläufer in der Post (beide: beim letzten Besuch des
                      Briefkastens gesehen und nicht abgeholt), seen = Zeitpunkt dieses Besuchs,
                      returned = { [itemID] = { kind = "expired" | "cancelled", n, price, t } } – in dieser Sitzung
                      abgeholte Rückläufer, die seitdem nicht neu eingestellt wurden (sie liegen in der Tasche) }
    History.Advice(itemID, preis)  Verkaufsempfehlung aus ezCores Einstell-Verlauf (History.PostStats) und dem
                    Preis-Wissen (Prices.Stats, Prices.Net): { lines = { Sätze … }, short = „4/6 verkauft“ | nil }.
                    Jede Aussage nennt die Zahl ihrer Erfassungen; „günstig/teuer“ nur über Market.Judge (AUC-04);
                    bei wenig Daten der ehrliche Satz statt einer Aussage. preis: Grundlage für die Anzahlung (der Preis
                    im Verkaufsbereich), sonst der übliche Verkaufspreis bzw. der letzte eigene Preis.
]]
History.ADVICE_MIN = 3     -- Einstellungen mit Ergebnis, ab denen eine Erfolgsquote zählt
History.BACK_KINDS = { expired = true, cancelled = true }

function History.Mail()
    local out = { sale = 0, back = 0, returned = {} }
    local source = Core.History
    if not ns.Enabled("auctionMail") or type(source) ~= "table" or type(source.AuctionMail) ~= "function" then
        return out
    end
    local mail = Core.Call(source.AuctionMail)
    if type(mail) ~= "table" or type(mail.list) ~= "table" then return out end
    out.seen = Core.Num(mail.seen)
    for _, e in ipairs(mail.list) do
        local back = type(e) == "table" and History.BACK_KINDS[e.kind] == true
        if type(e) ~= "table" then
            -- unlesbarer Eintrag: übergehen
        elseif not e.taken then
            if e.kind == "sale" then out.sale = out.sale + 1 elseif back then out.back = out.back + 1 end
        elseif back and Core.Num(e.item) then
            local item, t = Core.Num(e.item), Core.Num(e.t) or 0
            -- seit dem Abholen neu eingestellt (eigener letzter Preis jünger)? Dann ist es kein Rückläufer mehr.
            local last = ns.LastPost(item)
            local reposted = type(last) == "table" and t > 0 and (Core.Num(last.time) or 0) >= t
            local old = out.returned[item]
            if not reposted and (not old or t > old.t) then
                out.returned[item] = { kind = e.kind, n = Core.Num(e.n), price = Core.Num(e.price), t = t }
            end
        end
    end
    return out
end

-- Zeile im Seitenteil „Markt“ (Reiter Verkaufen): „Post: 2 Verkäufe, 3 Rückläufer (Briefkasten vor 2 Std.)“;
-- nil, wenn dort nichts liegt oder der Schalter aus ist.
function History.MailLine(mail)
    mail = mail or History.Mail()
    if mail.sale + mail.back == 0 then return nil end
    local parts = {}
    if mail.sale > 0 then parts[#parts + 1] = Core.Plural(mail.sale, L.MAIL_SALES_ONE, L.MAIL_SALES_MANY) end
    if mail.back > 0 then parts[#parts + 1] = Core.Plural(mail.back, L.MAIL_BACK_ONE, L.MAIL_BACK_MANY) end
    local text = L.MAIL_LINE:format(table.concat(parts, ", "))
    if mail.seen and Core.Ago then text = text .. " " .. L.MAIL_SEEN:format(Core.Ago(mail.seen)) end
    return text
end

-- Einstell-Verlauf eines Gegenstands aus ezCore (nil, solange ezCore ihn nicht führt) – nur Einstellungen an diesem
-- Auktionshaus (ns.PostKey wie „Zuletzt“; Gesamtreview 18.11.2026, T4-NR6): Quote und üblicher Preis eines Twinks
-- auf einem anderen Realm oder der anderen Fraktion gelten hier nicht.
local function PostStats(itemID)
    local source = Core.History
    if type(source) ~= "table" or type(source.PostStats) ~= "function" then return nil end
    local stats = Core.Call(source.PostStats, itemID, { house = ns.PostKey() })
    return type(stats) == "table" and stats or nil
end

-- Anzahlung gegen den erwartbaren Gewinn: Quote × (Erlös nach Gebühr − Händlerpreis) je Stück. Rückgabe: Anzahlung,
-- Gewinn – nur, wenn die Anzahlung bekannt ist und den Gewinn übersteigt.
function History.DepositRisk(itemID, price, duration, rate)
    local prices = ns.Prices()
    if not (prices and type(prices.Net) == "function" and price and price > 0 and rate) then return nil end
    local net = Core.Call(prices.Net, itemID, price, duration or 2, 1)
    if type(net) ~= "table" or type(net.bekannt) ~= "table" or not net.bekannt.anzahlung then return nil end
    local deposit = Core.Num(net.anzahlung)
    if not (deposit and deposit > 0) then return nil end
    local after = net.bekannt.erloes and Core.Num(net.erloes) or math.floor(price * (1 - ns.AH_CUT))
    local gain = math.max(0, math.floor(rate * (after - (Core.VendorPrice(itemID) or 0))))
    if deposit <= gain then return nil end
    return deposit, gain
end

-- quick = true: nur die Quote (für jede Zeile der Taschenliste – ohne Bewertung und Anzahlung, die das Preis-Wissen je
-- Aufruf rechnen lassen).
function History.Advice(itemID, price, quick)
    local out = { lines = {} }
    itemID = Core.Num(itemID)
    if not (itemID and ns.Enabled("sellAdvice")) then return out end
    local stats = PostStats(itemID)
    if not stats or (Core.Num(stats.posted) or 0) == 0 then return out end
    local lines = out.lines
    local sold = Core.Num(stats.sold) or 0
    local done = sold + (Core.Num(stats.expired) or 0) + (Core.Num(stats.cancelled) or 0)
    local rate
    if done >= History.ADVICE_MIN then
        rate = sold / done
        lines[#lines + 1] = L.ADVICE_RATE:format(sold, done)
        out.short = L.ADVICE_SHORT:format(sold, done)
    elseif done > 0 then
        lines[#lines + 1] = Core.Plural(done, L.ADVICE_FEW_POSTS_ONE, L.ADVICE_FEW_POSTS_MANY, History.ADVICE_MIN)
    else
        lines[#lines + 1] = Core.Plural(Core.Num(stats.open) or 0, L.ADVICE_OPEN_ONE, L.ADVICE_OPEN_MANY)
    end
    if quick then return out end
    local usual = Core.Num(stats.usual)
    if usual and sold > 0 then
        lines[#lines + 1] = L.ADVICE_USUAL:format(ns.Money(usual), Core.Plural(sold, L.ADVICE_SALES_ONE, L.ADVICE_SALES_MANY))
        -- „günstig/teuer“: die eine Bewertung aus AUC-04 (Market.Judge) – bei wenigen Tagen der Satz, wie viele es sind
        local Market = ns.Market
        local judgement, why
        if Market then judgement, why = Market.Judge(itemID, usual, false) end
        if judgement then
            lines[#lines + 1] = L.ADVICE_JUDGE:format(Market.JudgeText(judgement))
        elseif why == "few" then
            -- Dieselbe Größe, die Market.Assess prüft: Tage mit Preis für DIESEN Gegenstand (points), nicht die erfassten
            -- Tage des Hauses (daysCaptured) – sonst stünde „erst 12 Tage“ neben einer Schwelle von 5.
            local market = Market.Stats(itemID)
            local points = type(market) == "table" and Core.Num(market.points) or 0
            if points < Market.HINT_DAYS then
                lines[#lines + 1] = Core.Plural(points, L.ADVICE_FEW_DAYS_ONE, L.ADVICE_FEW_DAYS_MANY, Market.HINT_DAYS)
            end
        end
    end
    if rate then
        local last = ns.LastPost(itemID)
        local basis = Core.Num(price) or usual or (type(last) == "table" and Core.Num(last.price)) or nil
        local deposit, gain = History.DepositRisk(itemID, basis, type(last) == "table" and Core.Num(last.duration) or 2, rate)
        if deposit then lines[#lines + 1] = L.ADVICE_DEPOSIT:format(ns.Money(deposit), ns.Money(gain), sold, done) end
    end
    return out
end

ns.OnAuctionHouse(function() if ns.Enabled("historyTab") then Build() end end)
-- ezCore trägt ein (Post entnommen) und nimmt zurück (abgelehnter Anhang): der offene Verlauf folgt beidem.
Core.Listen("HISTORY_ADDED", function(kind)
    if kind == KIND then History.Refresh() end
end, ADDON)
Core.Listen("HISTORY_REMOVED", function(kind)
    if kind == KIND then History.Refresh() end
end, ADDON)
-- „Verlauf leeren“ (ezCore, Seite „ezCollection“ → Daten bzw. /ez verlauf): kind = nil heißt alle Arten.
Core.Listen("HISTORY_CLEARED", function(kind)
    if kind == nil or kind == KIND then History.Refresh() end
end, ADDON)
ns.OnSettingChanged(function(key)
    if key == "historyTab" then
        if ns.Enabled("historyTab") then Build() end
        History.UpdateTab()
    end
end)
