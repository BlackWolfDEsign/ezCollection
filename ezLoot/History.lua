local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Beute-Verlauf: zeigt, was ezCore erfasst (ezCore.History, Art „loot“). ezLoot erfasst selbst nichts.
    Blizzard hat für die eigene Beute kein Fenster (die Würfelergebnisse zeigen nur Gruppen-Würfe), deshalb ein
    Fenster aus ezCores Layout-Grundlage (ezCore.NewWindow: Blizzards PortraitFrameFlatTemplate, Kopfzeile,
    Rollbereich, Fußzeile, Knopf „Einstellungen“, Position und Esc) – kein eigener Fensterbau im Modul.
      Filter: alle Charaktere oder nur dieser, nur die aktuelle Zone, ab einer Qualität (Knopf öffnet ein Menü)
      Zeile: Symbol, Gegenstand × Anzahl, Quelle · Zone (bei allen Charakteren mit Name), vor wie langer Zeit
      Kopfzeile: Qualität und „Würfelergebnisse“; unten Anzahl, in dieser Sitzung geplündertes Gold, „Einstellungen“
    Wege dahin: Knopf in den Einstellungen, Knopf oben links im Plündernfenster, Linksklick auf den
    Addon-Fach, Seitenreiter an Blizzards Würfelergebnissen, Befehl „verlauf“; andere Module über
    ezCore.API("ezLoot").ShowHistory().
    Lage (Entscheidung des Nutzers 13.11.2026, V-152): Sind Blizzards Würfelergebnisse offen, hängt der Verlauf rechts
    daran und wandert mit (ezCore.Dock; seit dem 19.11.2026 immer, Wegziehen löst ihn); sonst steht er frei an der
    gemerkten Stelle.
    Ansicht „Mögliche Beute“ (Entscheidung des Nutzers 13.11.2026 zu Tnny's Mob Loot: „Ja, in ezLoot zeigen“): im
    selben Fenster, kein neues – Knopf „Mögliche Beute“ in der zweiten Zeile schaltet um. Gezeigt wird das Ziel (ein
    NPC), sonst der zuletzt im Tooltip gezeigte Gegner: alles, was ezCores Quellen kennen (Core.Sources.LootOf über
    Drops.GetSources; mit Chance, wenn die Quelle eine nennt), dazu je Gegenstand „bei dir n×“ und darunter, was nur
    bei dir fiel. Knopf „In AtlasLoot öffnen“ (nur dessen Fenster, Core.Sources.OpenFor), solange AtlasLoot läuft.
    Wege: Knopf, /ezl mögliche, ezCore.API("ezLoot").ShowPossible(npcID). Seit Welle 16 (RB-01) ohne Tnny's Mob Loot:
    sein Knopf „In … öffnen“, der Knopf am Zielfenster (Target.lua) und die Zeile „Messung: …“ sind entfernt.
    „Als Text kopieren“ (V5, Welle 24; Bericht Welle 20, vom Nutzer freigegeben „zuerst V1–V5“): Knopf unten neben
    „Einstellungen“, nur in der Verlaufsansicht. Er gibt die gefilterte Liste (dieselben Filter wie im Fenster, älteste
    zuerst) als Tabelle mit Tabulatoren in ezCores Kopierfeld (Core.CopyAsText, Welle 23d – Grammatik-Kodes, Farb- und
    Link-Codes löst ezCore auf). Spalten: Zeit, (alle Charaktere: Charakter), Gegenstand, Gegenstands-ID, Qualität,
    Anzahl, Gold, Quelle, Zone. Namen anderer Spieler (Beute von einer Spieler-Leiche) stehen in einer eigenen Spalte,
    die ab Werk fehlt – das Häkchen „Namen mitnehmen“ im Kopierfeld nimmt sie auf (Frage E6, nach Empfehlung). Ohne
    den Dienst in ezCore fehlt der Knopf.
]]

local H = {}
ns.LootHistory = H

H.LIMIT = 200                       -- neueste Einträge im Fenster (ezCore hebt mehr auf)
H.QUALITIES = { -1, 2, 3, 4 }       -- alle, ab Ungewöhnlich, ab Selten, ab Episch
H.ROW_HEIGHT = 34
H.WIDTH = 460                       -- Breite des Fensters (bis Welle 24: 380; Platz für Fußzeile und „Als Text kopieren“)
H.FOOTER_Y = 30                     -- Fußzeile über der Knopfleiste: 4 + Knopfhöhe 22 + 4 (Gegenprüfung Welle 24)
H.LIST_BOTTOM = 48                  -- Unterkante der Liste über der Fußzeile (vorher FOOTER_H + 6 = 28)
H.COPY_BUTTON_W = 110               -- Mindestbreite des Knopfs „Als Text kopieren“
H.sessionStart = Core.Now()

local Num, Plain = Core.Num, Core.Plain

local function View()
    local db = ns.db
    if not db then return { all = false, zone = false, quality = -1 } end
    db.historyView = type(db.historyView) == "table" and db.historyView or {}
    local view = db.historyView
    if type(view.all) ~= "boolean" then view.all = false end
    if type(view.zone) ~= "boolean" then view.zone = false end
    if type(view.quality) ~= "number" then view.quality = -1 end
    return view
end
H.View = View

local function CurrentZone()
    return GetRealZoneText and Plain(GetRealZoneText()) or nil
end

---------------------------------------------------------------------------
-- Daten (ohne Oberfläche, deshalb gut prüfbar)
---------------------------------------------------------------------------

function H.Available()
    local history = Core.History
    return type(history) == "table" and type(history.List) == "function"
end

-- Filter für ezCore.History.List aus der Ansicht.
function H.Filter(view)
    view = view or View()
    local filter = { limit = H.LIMIT }
    if not view.all then filter.char = Core.charKey end
    local minQuality = view.quality or -1
    local zone = view.zone and CurrentZone() or nil
    if minQuality >= 0 or zone then
        filter.match = function(e)
            if minQuality >= 0 then
                if e.money then return false end                -- Münzen haben keine Qualität
                if (Num(e.q) or -1) < minQuality then return false end
            end
            if zone and e.zone ~= zone then return false end
            return true
        end
    end
    return filter
end

function H.Entries(view)
    if not H.Available() then return {} end
    local ok, list = pcall(Core.History.List, "loot", H.Filter(view))
    return ok and type(list) == "table" and list or {}
end

-- In dieser Sitzung geplündertes Gold (Kupfer) dieses Charakters.
function H.SessionGold()
    if not (H.Available() and Core.History.Sum) then return 0 end
    local ok, sum = pcall(Core.History.Sum, "loot", "money", { char = Core.charKey, since = H.sessionStart })
    return ok and Num(sum) or 0
end

local SOURCE_KEYS = { Creature = "SRC_CREATURE", Vehicle = "SRC_CREATURE", GameObject = "SRC_OBJECT",
    Item = "SRC_ITEM", fishing = "SRC_FISHING", roll = "SRC_ROLL" }

function H.SourceText(src)
    if type(src) ~= "table" then return nil end
    local name = Plain(src.name)
    if type(name) == "string" and name ~= "" then
        if src.type == "roll" then return L.SRC_ROLL_NAMED:format(name) end
        return name
    end
    local key = SOURCE_KEYS[src.type]
    return key and L[key] or nil
end

-- Farbe der Qualität als Farbcode (ezCore.QualityHex, eine Stelle für alle Module; unbekannt: weiß).
local function QualityHex(q) return Core.QualityHex(q) end

-- Name eines Gegenstands: der Link, sonst der Name zur itemID (ezCore lädt fehlende Daten nach).
local function ItemText(e)
    local link = Plain(e.link)
    if type(link) == "string" and link ~= "" then return link end
    return Core.ItemNameByID(e.id) or "?"
end
H.ItemText = ItemText

-- Texte einer Zeile: Haupttext, Untertext, rechts (Zeit).
function H.Describe(e, showChar)
    local main
    if Num(e.money) then
        main = Core.CoinText(e.money)
    else
        main = ItemText(e)
        if not main:find("|c", 1, true) then main = QualityHex(Num(e.q)) .. main .. "|r" end
        local n = Num(e.n) or 1
        if n > 1 then main = main .. " ×" .. n end
    end
    local parts = {}
    if showChar and e.c then parts[#parts + 1] = Core.CharName(Core.Char(e.c), e.c) end
    parts[#parts + 1] = H.SourceText(e.src)
    if type(e.zone) == "string" and e.zone ~= "" then parts[#parts + 1] = e.zone end
    return main, table.concat(parts, " · "), Core.Ago(e.t)
end

function H.Icon(e)
    if Num(e.money) then return "Interface\\Icons\\INV_Misc_Coin_01" end
    if Num(e.cur) and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, e.cur)
        if ok and type(info) == "table" and info.iconFileID then return info.iconFileID end
    end
    return Core.ItemIcon(e.id) or Core.ItemIcon(Plain(e.link)) or Core.ICON_FALLBACK
end

---------------------------------------------------------------------------
-- „Als Text kopieren“ (V5): Zeilen und Spalten für Core.CopyAsText (ohne Oberfläche, deshalb gut prüfbar)
---------------------------------------------------------------------------

H.PLAYER_SOURCE = "Player"          -- Art der Quelle bei einer Spieler-Leiche (erstes Feld der GUID, ezCore History.Source)

-- Hat dieses ezCore die gemeinsame Ausgabe? (Welle 23d) Ohne sie fehlt der Knopf.
function H.CanCopy()
    return type(Core.CopyAsText) == "function"
end

-- Quelle ohne Namen anderer Spieler: bei einer Spieler-Leiche nur „Spieler“, der Name steht in H.CopyPlayer.
function H.CopySource(src)
    if type(src) == "table" and src.type == H.PLAYER_SOURCE then return L.SRC_PLAYER end
    return H.SourceText(src)
end

-- Name des Spielers, von dessen Leiche die Beute kam (sonst nil) – Spalte „personal“ (Frage E6).
function H.CopyPlayer(src)
    if type(src) ~= "table" or src.type ~= H.PLAYER_SOURCE then return nil end
    local name = Plain(src.name)
    return type(name) == "string" and name ~= "" and name or nil
end

-- Zeit und Gold wie in ezPanels Kopien (ein Format für alle Tabellen): Datum lang (Core.DateText, „long“); Gold mit
-- vier Nachkommastellen schreibt ezCores Spalte format = "money" (Core.GoldDecimal, Welle 26).
function H.CopyDate(t)
    t = Num(t)
    return t and Core.DateText(t, "long") or nil
end

-- Zeilen aus den Einträgen, älteste zuerst. → Zeilen, true wenn eine Zeile einen Spielernamen hat
function H.CopyRows(entries, view)
    view = view or View()
    local list = {}
    for i, e in ipairs(type(entries) == "table" and entries or {}) do
        if type(e) == "table" and not ns.IsSecret(e) then list[#list + 1] = { e = e, i = i } end
    end
    table.sort(list, function(a, b)
        local ta, tb = Num(a.e.t) or 0, Num(b.e.t) or 0
        if ta ~= tb then return ta < tb end
        return a.i > b.i                    -- gleiche Zeit: die Liste kommt neueste zuerst
    end)
    local rows, player = {}, false
    for _, item in ipairs(list) do
        local e = item.e
        local money = Num(e.money)
        local row = { t = e.t, src = H.CopySource(e.src), player = H.CopyPlayer(e.src), zone = Plain(e.zone) }
        if view.all and e.c then row.char = Core.CharName(Core.Char(e.c), e.c) end
        if money then
            row.item, row.gold = L.COPY_MONEY, money
        else
            local text = ItemText(e)
            row.item = type(text) == "string" and text:match("%[(.-)%]") or text
            row.id, row.n = Num(e.id), Num(e.n) or 1
            local q = Num(e.q)
            row.q = q and Core.QualityName(q) or nil   -- T16-6
        end
        if row.player then player = true end
        rows[#rows + 1] = row
    end
    return rows, player
end

-- Spalten: Charakter nur mit „Alle Charaktere“, Spielername nur, wenn eine Zeile einen hat (sonst erschiene das
-- Häkchen „Namen mitnehmen“ ohne Grund).
function H.CopyColumns(view, player)
    view = view or View()
    local cols = { { key = "t", title = L.COPY_COL_TIME, format = function(t) return H.CopyDate(t) end } }
    if view.all then cols[#cols + 1] = { key = "char", title = L.COPY_COL_CHAR } end
    cols[#cols + 1] = { key = "item", title = L.COPY_COL_ITEM }
    cols[#cols + 1] = { key = "id", title = L.COPY_COL_ID }
    cols[#cols + 1] = { key = "q", title = L.COPY_COL_QUALITY }
    cols[#cols + 1] = { key = "n", title = L.COPY_COL_COUNT }
    cols[#cols + 1] = { key = "gold", title = L.COPY_COL_GOLD, format = "money" }   -- Gold mit vier Stellen (ezCore)
    cols[#cols + 1] = { key = "src", title = L.COPY_COL_SOURCE }
    if player then cols[#cols + 1] = { key = "player", title = L.COPY_COL_PLAYER, personal = true } end
    cols[#cols + 1] = { key = "zone", title = L.COPY_COL_ZONE }
    return cols
end

-- Knopf „Als Text kopieren“: die gefilterte Liste ins Kopierfeld. → true, wenn das Kopierfeld aufging
function H.Copy()
    if not H.CanCopy() then return false end
    local view = View()
    local entries = H.Entries(view)
    if #entries == 0 then
        ns.Print(L.COPY_EMPTY)
        return false
    end
    local rows, player = H.CopyRows(entries, view)
    local ok, err = pcall(Core.CopyAsText, { title = L.COPY_TITLE, columns = H.CopyColumns(view, player), rows = rows,
        anchor = H.frame, owner = ADDON })
    if not ok then
        if type(Core.Error) == "function" then Core.Error(ADDON, err, "CopyAsText") end
        return false
    end
    return true
end

---------------------------------------------------------------------------
-- Fenster
---------------------------------------------------------------------------

local frame
local rows = {}
local LAYOUT = Core.LAYOUT or { EDGE = 8, GAP = 6, CONTENT_TOP = -60, FOOTER_H = 22 }
H.POSITION_KEY = "ezLoot.history"   -- gemerkte Lage in ezCore (Core.StoredPosition, ezCore.NewWindow)

-- Zeile der Ansicht „Mögliche Beute“: Blizzards Tooltip des Gegenstands, darunter Quelle und „bei dir“.
local function PossibleRowEnter(row)
    local id = row.item and row.item.id
    if not id then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if GameTooltip.SetItemByID then
        GameTooltip:SetItemByID(id)
    else
        Core.TipTitle(GameTooltip, row.main:GetText() or "?")
    end
    local sub = row.sub:GetText()
    if type(sub) == "string" and sub ~= "" then
        Core.Tooltip.Gap(GameTooltip)   -- ezCores einer Trenner unter Blizzards Zeilen und den Abschnitten der Sammlung
        Core.TipLine(GameTooltip, sub, "hint", true)
    end
    GameTooltip:Show()
end
H.PossibleRowEnter = PossibleRowEnter

local function RowEnter(row)
    if row.item then return PossibleRowEnter(row) end
    local e = row.entry
    if not e then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local link = Plain(e.link)
    if type(link) == "string" and link:find("|H", 1, true) and GameTooltip.SetHyperlink then
        GameTooltip:SetHyperlink(link)
    else
        Core.TipTitle(GameTooltip, row.main:GetText() or "?")
    end
    -- Gegenprüfung 19.11.2026 (Spielbefund „auch hier fehlender abstand“): das Datum klebte an „Beute bei dir: …“,
    -- dem letzten Abschnitt des Gegenstands-Tooltips – ezCores einer Trenner davor
    Core.Tooltip.Gap(GameTooltip)
    Core.TipLine(GameTooltip, Core.DateText(e.t, "full"), "hint")
    if type(link) == "string" and link:find("|H", 1, true) then
        Core.TipClick(GameTooltip, Core.ClickText(nil, "SHIFT", L.HISTORY_ROW_LINK))   -- „Umschalt-Klick: …“ (T18-9)
    end
    GameTooltip:Show()
end
H.RowEnter = RowEnter

local function RowClick(row)
    local link = row.entry and Plain(row.entry.link)
    if type(link) == "string" and IsModifiedClick and IsModifiedClick() and HandleModifiedItemClick then
        HandleModifiedItemClick(link)
    end
end

local function Row(index)
    local row = rows[index]
    if row then return row end
    row = CreateFrame("Button", nil, frame.content)
    row:SetHeight(H.ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * H.ROW_HEIGHT)
    row:SetPoint("RIGHT", frame.content, "RIGHT", 0, 0)
    row:RegisterForClicks("LeftButtonUp")
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.icon = row:CreateTexture(nil, "ARTWORK")
    -- Symbol der zweizeiligen Zeile: Blizzards kleiner Aktionsknopf (Core.Style.ICON.small, 30; bisher 28 von Hand) –
    -- passt in H.ROW_HEIGHT; „line“ (16) wäre neben zwei Textzeilen zu klein (Design-System 2.3)
    local iconSize = Core.Style.IconSize("small")
    row.icon:SetSize(iconSize, iconSize)
    row.icon:SetPoint("LEFT", 2, 0)
    row.main = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.main:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -1)
    row.main:SetPoint("RIGHT", row, "RIGHT", -64, 0)
    row.main:SetJustifyH("LEFT")
    row.main:SetWordWrap(false)
    row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 1)
    row.sub:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.sub:SetJustifyH("LEFT")
    row.sub:SetWordWrap(false)
    row.when = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.when:SetPoint("TOPRIGHT", -4, -3)
    row:SetScript("OnEnter", RowEnter)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", RowClick)
    rows[index] = row
    return row
end

-- Textfarbe aus einer Farb-Rolle: Core.Style.SetTextColor (Welle 23, A3) setzt genau r, g, b der Rolle – vorher ein
-- lokales Tint, gleich dem in ezHeal (Core.Style.Color gibt vier Werte, der vierte landete sonst als Alpha).
local function QualityLabel(q)
    if q < 0 then return L.HISTORY_QUALITY_ALL end
    return Core.QualityText(q)   -- Name und Farbe aus ezCore (T16-6)
end

function H.Refresh()
    if not frame then return end
    if H.mode == "possible" then return H.RefreshPossible() end
    local view = View()
    frame.allCheck:SetChecked(view.all)
    frame.zoneCheck:SetChecked(view.zone)
    frame.qualityButton:SetText(L.HISTORY_QUALITY:format(QualityLabel(view.quality)))
    local entries = H.Entries(view)
    for index, e in ipairs(entries) do
        local row = Row(index)
        local main, sub, when = H.Describe(e, view.all)
        row.entry, row.item = e, nil
        row.icon:SetTexture(H.Icon(e))
        row.main:SetText(main)
        row.sub:SetText(sub)
        row.when:SetText(when)
        Core.Style.SetTextColor(row.when, "highlight")
        row:Show()
    end
    for index = #entries + 1, #rows do
        rows[index].entry, rows[index].item = nil, nil
        rows[index]:Hide()
    end
    frame.content:SetHeight(math.max(1, #entries * H.ROW_HEIGHT))
    frame.copyButton:SetEnabled(#entries > 0)
    if not H.Available() then
        frame.empty:SetText(L.HISTORY_NO_CORE)
    else
        frame.empty:SetText(#entries == 0 and L.HISTORY_EMPTY or "")
    end
    local count = #entries >= H.LIMIT and L.HISTORY_COUNT_LIMIT:format(H.LIMIT) or L.HISTORY_COUNT:format(#entries)
    frame:Footer(count .. "  ·  " .. L.HISTORY_GOLD:format(Core.CoinText(H.SessionGold())))
    H.shown = entries
end

local function CycleQuality()
    local view = View()
    local nextIndex = 1
    for i, q in ipairs(H.QUALITIES) do
        if q == view.quality then nextIndex = i % #H.QUALITIES + 1 end
    end
    view.quality = H.QUALITIES[nextIndex]
    H.Refresh()
end
H.CycleQuality = CycleQuality

-- Qualität wählen: Blizzards Menü über ezCore.Menu (alle Stufen auf einen Blick). Ohne Menü schaltet der
-- Knopf wie früher eine Stufe weiter.
local function SetQuality(q)
    View().quality = q
    H.Refresh()
end
H.SetQuality = SetQuality

function H.QualityOptions()
    local options = {}
    for _, q in ipairs(H.QUALITIES) do options[#options + 1] = { q, QualityLabel(q) } end
    return options
end

function H.OpenQualityMenu(owner)
    local menu = Core.Menu
    local opened = type(menu) == "table" and type(menu.Open) == "function" and menu.Open(owner, function(root)
        menu.Title(root, L.HISTORY_QUALITY_TITLE)
        for _, o in ipairs(H.QualityOptions()) do
            menu.Radio(root, o[2], function() return View().quality end, SetQuality, o[1])
        end
    end)
    if not opened then CycleQuality() end
end

---------------------------------------------------------------------------
-- Ansicht „Mögliche Beute“ (im selben Fenster; Daten aus Drops.GetSources und Drops.Get)
---------------------------------------------------------------------------

H.mode = "loot"                     -- "loot" (Verlauf) | "possible" (mögliche Beute eines Gegners)
H.possible = nil                    -- { npc, name, level } des gezeigten Gegners

local function UnitText(fn, unit)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, unit)
    value = ok and Plain(value) or nil
    return type(value) == "string" and value ~= "" and value or nil
end

-- Gegner für die Ansicht: das Ziel, wenn es ein NPC mit lesbarer GUID ist, sonst der zuletzt im Tooltip gezeigte.
function H.PossibleTarget()
    local D = ns.Drops
    local npc = D.UnitNpc("target")
    if npc then return { npc = npc, name = UnitText(UnitName, "target"), level = D.UnitLevel("target") } end
    if D.shownNpc then return { npc = D.shownNpc } end
    return nil
end

-- Name des Gegners: wie er kam, sonst aus dem eigenen Verlauf, sonst „Gegner <ID>“.
function H.PossibleName(target)
    if type(target) ~= "table" then return nil end
    if target.name then return target.name end
    local s = ns.Drops.Get(target.npc)
    local name = s and Plain(s.name)
    if type(name) == "string" and name ~= "" then return name end
    return L.POSSIBLE_NPC:format(target.npc or 0)
end

-- Untertext: woher die Angabe kommt, dazu „bei dir“. source = Name der Quelle (für „laut Questie, ohne Chance“).
local function PossibleSub(item, own, s, source)
    local parts = {}
    if item then
        if item.chance ~= nil then
            parts[#parts + 1] = L.SOURCES_ACCORDING:format(source or "?")
        else
            -- keine Chance: die Quelle nennt den Gegenstand nur (QuestieDB)
            parts[#parts + 1] = L.POSSIBLE_LISTED:format(source or "?")
        end
    end
    if own and s and (s.loots or 0) > 0 then
        parts[#parts + 1] = L.POSSIBLE_OWN:format(own.n or 0, math.min(own.times or 0, s.loots), s.loots)
    elseif item then
        parts[#parts + 1] = L.POSSIBLE_OWN_NONE
    end
    return table.concat(parts, " · ")
end

local function PossibleRow(item, own, s, source)
    local shown = item or own
    local row = { id = shown.id, main = ns.Drops.ItemText(shown), sub = PossibleSub(item, own, s, source) }
    if item then
        local right, rgb = ns.Drops.ChanceRight(item)
        row.right, row.rgb = right or "", rgb
    else
        row.right = L.DROPS_ITEM_SHORT:format(own.n or 0)
    end
    return row
end

-- Zeilen der Ansicht (ohne Oberfläche): was die Quelle kennt, dann was nur bei dir fiel.
-- → { { id, main, sub, right, rgb } … }
function H.PossibleRows(b, s)
    local D = ns.Drops
    local list, own, used = {}, {}, {}
    if type(s) == "table" and type(s.items) == "table" then
        for _, item in ipairs(s.items) do if item.id then own[item.id] = item end end
    end
    if type(b) == "table" then
        for _, item in ipairs(D.SortedSource(b.items)) do
            used[item.id] = true
            list[#list + 1] = PossibleRow(item, own[item.id], s, b.source)
        end
    end
    if type(s) == "table" and (s.loots or 0) > 0 then
        for _, item in ipairs(D.Sorted(s)) do
            if item.id and not used[item.id] then list[#list + 1] = PossibleRow(nil, item, s) end
        end
    end
    return list
end

function H.SetTitle(text)
    H.title = text
    if not frame then return end
    if frame.SetTitle then frame:SetTitle(text) elseif frame.TitleText then frame.TitleText:SetText(text) end
end

-- Filter des Verlaufs nur in der Verlaufsansicht, Knopf zum Öffnen in der Quelle nur in der Ansicht „Mögliche Beute“.
local function ApplyMode()
    if not frame then return end
    local possible = H.mode == "possible"
    for _, part in ipairs({ frame.allCheck, frame.allLabel, frame.zoneCheck, frame.zoneLabel, frame.qualityButton }) do
        part:SetShown(not possible)
    end
    frame.possibleButton:SetText(possible and L.POSSIBLE_BACK or L.POSSIBLE_TITLE)
    frame.copyButton:SetShown(not possible and H.CanCopy())
    if not possible then
        frame.openButton:Hide()
        H.SetTitle(L.HISTORY_TITLE)
    end
end

function H.RefreshPossible()
    if not frame then return end
    local D = ns.Drops
    local target = H.possible
    local b = target and D.GetSources(target.npc, target.level) or nil
    local s = target and D.Get(target.npc) or nil
    local list = target and H.PossibleRows(b, s) or {}
    for index, r in ipairs(list) do
        local row = Row(index)
        row.entry, row.item = nil, r
        row.icon:SetTexture(Core.ItemIcon(r.id) or Core.ICON_FALLBACK)
        row.main:SetText(r.main)
        row.sub:SetText(r.sub)
        row.when:SetText(r.right or "")
        local rgb = r.rgb
        if rgb then row.when:SetTextColor(rgb[1], rgb[2], rgb[3]) else Core.Style.SetTextColor(row.when, "highlight") end
        row:Show()
    end
    for index = #list + 1, #rows do
        rows[index].entry, rows[index].item = nil, nil
        rows[index]:Hide()
    end
    frame.content:SetHeight(math.max(1, #list * H.ROW_HEIGHT))
    H.SetTitle(target and L.POSSIBLE_TITLE_NPC:format(H.PossibleName(target)) or L.POSSIBLE_TITLE)
    if not target then
        frame.empty:SetText(L.POSSIBLE_NO_TARGET)
    elseif #list == 0 then
        frame.empty:SetText(D.SourceHint())
    else
        frame.empty:SetText("")
    end
    local footer = L.POSSIBLE_COUNT:format(#list)
    if b then
        footer = footer .. "  ·  " .. b.label
    elseif target then
        footer = footer .. "  ·  " .. D.SourceHint()
    end
    frame:Footer(footer)
    -- Solange AtlasLoot läuft: „In AtlasLoot öffnen“ – nur sein Fenster (DG-49, Tooltip sagt es)
    local atlas = target ~= nil and D.AtlasLabel() or nil
    frame.openButton.mode = atlas and "atlas" or nil
    if atlas then frame.openButton:SetText(Core.L["SOURCES_OPEN"]:format(atlas)) end
    frame.openButton:SetShown(atlas ~= nil)
    H.shownPossible = { b = b, s = s, rows = list }
end

function H.SetMode(mode)
    H.mode = mode == "possible" and "possible" or "loot"
    ApplyMode()
    H.Refresh()
end

-- Knopf „Mögliche Beute“ bzw. „Zurück zum Verlauf“; beim Wechsel in die Ansicht gilt das aktuelle Ziel.
function H.TogglePossible()
    if H.IsShown() and H.mode == "possible" then
        H.SetMode("loot")
        return false
    end
    return H.ShowPossible()
end

-- Ansicht für einen Gegner öffnen (ohne npc: das Ziel bzw. der zuletzt gezeigte Gegner). → true
function H.ShowPossible(npc, name)
    npc = Num(npc)
    if npc then
        H.possible = { npc = npc, name = type(name) == "string" and name ~= "" and name or nil }
    else
        H.possible = H.PossibleTarget() or H.possible
    end
    return H.Show("possible")
end

-- Knopf „In AtlasLoot öffnen“ (nur dessen Fenster). Der Name bleibt (früher auch „In <Quelle> öffnen“).
function H.OpenInSource()
    local ok, message = ns.Drops.OpenAtlas(H.possible and H.possible.npc)
    if not ok and message then ns.Print(message) end
    return ok
end

---------------------------------------------------------------------------
-- Andocken an Blizzards Würfelergebnisse (nur Anker am eigenen Fenster; Blizzards Fenster bleibt unberührt)
---------------------------------------------------------------------------

H.DOCK_GAP = 36                     -- Platz für den Seitenreiter rechts an den Würfelergebnissen
H.ROLL_FRAMES = { "GroupLootHistoryFrame", "LootHistoryFrame" }     -- wie ezCores Panel „loothistory“
H.TAB_ICON = "Interface\\Icons\\INV_Misc_Bag_10"
local docked, dockHooked = false, false

-- Blizzards Würfelergebnis-Fenster oder nil (älterer Client, noch nicht geladen).
function H.RollFrame()
    for _, name in ipairs(H.ROLL_FRAMES) do
        local rolls = rawget(_G, name)
        if type(rolls) == "table" and type(rolls.IsShown) == "function" then return rolls end
    end
    return nil
end

-- Woran jetzt angedockt würde: die offenen Würfelergebnisse, sonst nil (frei). Seit der Einstellungs-Prüfung vom
-- 19.11.2026 ohne Schalter dockHistory (Abschnitt 4 nach Empfehlung): Wegziehen löst den Verlauf schon (OnDragStart).
function H.DockTarget()
    local rolls = H.RollFrame()
    return rolls and rolls:IsShown() and rolls or nil
end

function H.IsDocked() return docked end

-- Zurück an die gemerkte freie Stelle. true, wenn das Fenster angedockt war.
function H.Undock()
    if not docked then return false end
    docked = false
    if frame then
        frame:ClearAllPoints()
        frame:SetClampedToScreen(true)   -- ezCore.Dock hatte das für die Andock-Lage ausgeschaltet
        frame:RestorePosition()
    end
    return true
end

-- Lage nach dem Stand der Dinge: angedockt, wenn es ein Ziel gibt, sonst frei. → angedockt?
function H.UpdateDock()
    if not frame then return false end
    local target = H.DockTarget()
    if target then
        Core.Dock(frame, target, { gap = H.DOCK_GAP, matchHeight = false })
        docked = true
    else
        H.Undock()
    end
    return docked
end

-- Tooltip des Seitenreiters: was er tut, wie man ihn löst (Wegziehen – den Schalter „andocken“ gibt es seit der
-- Einstellungs-Prüfung vom 19.11.2026 nicht mehr, vorher stand hier sein Weg) und der geltende Befehl (T18-2)
function H.DockTabTooltip(owner)
    GameTooltip:SetOwner(owner, Core.TipAnchor(owner))
    Core.TipTitle(GameTooltip, L.HISTORY_TITLE)
    Core.TipText(GameTooltip, L.DOCK_TAB_TIP)
    Core.TipLine(GameTooltip, L.DOCK_TAB_UNDOCK, "hint", true)
    Core.TipClick(GameTooltip, L.DOCK_TAB_CMD:format(ns.SlashCmd()))
    GameTooltip:Show()
end

-- Seitenreiter rechts an Blizzards Würfelergebnissen: der sichtbare Weg von dort zum Beute-Verlauf.
function H.CreateDockTab()
    local rolls = H.RollFrame()
    if H.dockTab or not rolls then return H.dockTab end
    local tab = Core.CreateSideTab(rolls, { key = "ezLoot.history", order = 10, owner = ADDON })
    Core.SetIcon(tab.Icon, nil, H.TAB_ICON)
    tab:SetScript("OnClick", Core.SideTabClick(function() H.Toggle() end))
    tab:SetScript("OnEnter", function(self) H.DockTabTooltip(self) end)
    H.dockTab = tab
    return tab
end

function H.OnRollsShown()
    if H.IsShown() then H.UpdateDock() end
end

-- Würfelergebnisse zu: Der Verlauf bleibt offen und steht wieder frei (ein Anker an einem versteckten Fenster
-- ließe ihn mit verschwinden).
function H.OnRollsHidden()
    H.Undock()
end

-- Einmal an Blizzards Fenster einhängen (nur HookScript). → true, wenn es das Fenster gibt.
function H.SetupDock()
    if dockHooked then return true end
    local rolls = H.RollFrame()
    if not (rolls and rolls.HookScript) then return false end
    dockHooked = true
    rolls:HookScript("OnShow", function() ns.Try("HistoryDock", H.OnRollsShown) end)
    rolls:HookScript("OnHide", function() ns.Try("HistoryDock", H.OnRollsHidden) end)
    H.CreateDockTab()
    if rolls:IsShown() then H.OnRollsShown() end
    return true
end

-- Gemerkte Lage vergessen, Fenster an den Standardplatz (ezCore.NewWindow bzw. ezCore.StorePosition).
-- Ein angedocktes Fenster löst sich dabei; beim nächsten Öffnen dockt es wieder an.
function H.ResetPosition()
    if frame then
        if docked then
            docked = false
            frame:SetClampedToScreen(true)
        end
        frame:ResetPosition()
    elseif type(Core.StorePosition) == "function" then
        Core.StorePosition(H.POSITION_KEY, nil)
    end
end

-- Häkchen mit Beschriftung in der zweiten Kopfzeile (Filter, gemerkt in ezLootDB.historyView).
local function FilterCheck(anchor, key, text, tip)
    local check = Core.CreateCheck(frame, 24)
    if anchor then
        check:SetPoint("LEFT", anchor, "RIGHT", 12, 0)
    else
        check:SetPoint("TOPLEFT", frame, "TOPLEFT", LAYOUT.EDGE + 4, LAYOUT.CONTENT_TOP + 2)
    end
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", check, "RIGHT", 0, 0)
    label:SetText(text)
    check:SetScript("OnClick", function(self)
        View()[key] = self:GetChecked() == true
        H.Refresh()
    end)
    check:SetScript("OnEnter", Core.TipScript(text, tip))
    check:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return check, label
end

-- Fenster aus ezCores Layout-Grundlage (Blizzards PortraitFrameFlatTemplate, Position und Esc von ezCore).
local function Create()
    if frame then return frame end
    frame = Core.NewWindow("ezLootHistoryFrame", {
        portrait = "Interface\\Icons\\INV_Misc_Bag_10", title = L.HISTORY_TITLE, width = H.WIDTH, height = 460,
        positionKey = H.POSITION_KEY, default = { "CENTER", "CENTER", 0, 0 }, escape = true,
    })
    -- Ebene: Core.NewWindow setzt MEDIUM wie Blizzards Fenster (ContainerFrameTemplate; Design-System 2.6) und
    -- SetToplevel – ein Klick holt das Fenster nach vorn. Bisher stand es auf HIGH über allen anderen Fenstern.

    -- Kopfzeile: Qualität (Klick schaltet weiter) und Blizzards Würfelergebnisse
    frame.qualityButton = frame:HeaderButton("", 140, function(button) H.OpenQualityMenu(button or frame.qualityButton) end,
        L.HISTORY_QUALITY_TITLE, L.HISTORY_QUALITY_TIP)
    frame.rollsButton = frame:HeaderButton(L.OPT_ROLLS, 140, function() ns.OpenRollHistory() end,
        L.OPT_ROLLS, L.OPT_ROLLS_TIP)

    -- zweite Zeile: Filter
    frame.allCheck, frame.allLabel = FilterCheck(nil, "all", L.ALL_CHARS, L.HISTORY_ALL_CHARS_TIP)
    frame.zoneCheck, frame.zoneLabel = FilterCheck(frame.allLabel, "zone", L.HISTORY_ZONE, L.HISTORY_ZONE_TIP)

    -- zweite Zeile rechts: Ansicht „Mögliche Beute“ ein/aus; links (nur dort) „In <Quelle> öffnen“
    frame.possibleButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.possibleButton:SetSize(130, LAYOUT.BUTTON_H or 22)
    frame.possibleButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(LAYOUT.EDGE + 4), LAYOUT.CONTENT_TOP + 2)
    frame.possibleButton:SetText(L.POSSIBLE_TITLE)
    frame.possibleButton:SetScript("OnClick", function() H.TogglePossible() end)
    frame.possibleButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, Core.TipAnchor(self))
        Core.TipTitle(GameTooltip, L.POSSIBLE_TITLE)
        Core.TipText(GameTooltip, L.POSSIBLE_BUTTON_TIP)
        Core.TipClick(GameTooltip, L.POSSIBLE_BUTTON_CMD:format(ns.SlashCmd()))
        GameTooltip:Show()
    end)
    frame.possibleButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.openButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.openButton:SetSize(180, LAYOUT.BUTTON_H or 22)
    frame.openButton:SetPoint("TOPLEFT", frame, "TOPLEFT", LAYOUT.EDGE + 4, LAYOUT.CONTENT_TOP + 2)
    frame.openButton:SetScript("OnClick", function() H.OpenInSource() end)
    frame.openButton:SetScript("OnEnter", function(self) Core.ShowTip(self, L.POSSIBLE_ATLAS_TITLE, L.POSSIBLE_ATLAS_TIP) end)
    frame.openButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.openButton:Hide()

    -- Liste unter den Filtern, Fußzeile mit Anzahl und Gold, Knopf „Einstellungen“
    frame.scroll, frame.content = frame:Scroll()
    frame.scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", LAYOUT.EDGE, LAYOUT.CONTENT_TOP - 28)
    frame.content:SetWidth(330)
    frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    frame.empty:SetPoint("CENTER", frame.scroll, "CENTER", 0, 0)
    frame.empty:SetWidth(280)
    frame.footer = frame:Footer("")
    frame.settingsButton = frame:SettingsButton(function() ns.OpenSettings() end)
    -- „Als Text kopieren“ (V5) links neben „Einstellungen“
    frame.copyButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.copyButton:SetText(L.COPYTEXT_TITLE)
    local label = frame.copyButton.GetFontString and frame.copyButton:GetFontString()
    local textWidth = label and label.GetStringWidth and Num(label:GetStringWidth()) or 0
    frame.copyButton:SetSize(math.max(H.COPY_BUTTON_W, textWidth + 24), LAYOUT.BUTTON_H or 22)
    frame.copyButton:SetPoint("RIGHT", frame.settingsButton, "LEFT", -(LAYOUT.GAP or 6), 0)
    -- ausgeschaltet (leere Liste) zeigt er trotzdem seinen Tooltip samt Grund (Design-System: SetMotionScriptsWhileDisabled)
    if frame.copyButton.SetMotionScriptsWhileDisabled then frame.copyButton:SetMotionScriptsWhileDisabled(true) end
    frame.copyButton:SetScript("OnClick", function() H.Copy() end)
    frame.copyButton:SetScript("OnEnter", function(self)
        local on = not self.IsEnabled or self:IsEnabled()
        Core.ShowTip(self, L.COPYTEXT_TITLE, on and L.COPY_BUTTON_TIP or L.COPY_EMPTY)
    end)
    frame.copyButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Fußzeile über der Knopfleiste, so breit wie das Fenster (Gegenprüfung Welle 24): neben zwei Knöpfen blieb für
    -- „n Einträge · Gold geplündert (Sitzung): …“ zu wenig Platz, die Gold-Summe endete auf „…“. So hängt sie auch
    -- in der Ansicht „Mögliche Beute“ (Knopf versteckt) an keinem Knopf; die Liste endet darüber.
    local footer = frame.footer
    if footer and footer.ClearAllPoints then
        footer:ClearAllPoints()
        footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", LAYOUT.EDGE + 4, H.FOOTER_Y)
        footer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(LAYOUT.EDGE + 4), H.FOOTER_Y)
        if footer.SetWordWrap then footer:SetWordWrap(false) end
        frame.scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -26, H.LIST_BOTTOM)
    end
    frame.copyButton:SetShown(H.CanCopy())

    frame:HookScript("OnShow", function() H.Refresh() end)
    -- Wegziehen löst das angedockte Fenster; die neue Stelle merkt ezCore beim Loslassen als freie Lage.
    frame:HookScript("OnDragStart", function(self)
        if docked then
            docked = false
            self:SetClampedToScreen(true)
        end
    end)
    H.frame = frame
    return frame
end

-- mode: "possible" öffnet die Ansicht „Mögliche Beute“, sonst den Verlauf.
function H.Show(mode)
    Create()
    H.SetupDock()
    H.UpdateDock()
    H.mode = mode == "possible" and "possible" or "loot"
    ApplyMode()
    frame:Show()
    H.Refresh()
    if ns.StartTour then ns.StartTour(frame) end     -- Erklärblasen beim ersten Öffnen (Tour.lua)
    return true
end

function H.Toggle()
    if frame and frame:IsShown() then
        frame:Hide()
        return false
    end
    return H.Show()
end

function H.IsShown()
    return frame ~= nil and frame:IsShown() == true
end

-- Schnittstelle für andere Module (z. B. ezPanels Beute-Block): ezCore.API("ezLoot").ShowHistory()
ns.API = ns.API or {}
ns.API.ShowHistory = function() return H.Show() end
ns.API.ToggleHistory = function() return H.Toggle() end
ns.API.ShowPossible = function(npcID, name) return H.ShowPossible(npcID, name) end

-- Taste „ezLoot: Beute-Verlauf öffnen/schließen“ (Tastaturbelegung » ezCollection; Eintrag in ezCores Keys.LIST und
-- Bindings.xml): ezLoot liefert die Ausführung selbst (Welle 23, A2; Core.Keys.Register) – ein Fehler landet bei ezLoot,
-- und die Taste meldet auch das Schließen als ausgeführt. Ohne Keys.Register (ältere ezCore-Fassung) bleibt ezCores
-- Weg über ezCore.API("ezLoot").ToggleHistory.
local keys = Core.Keys
if type(keys) == "table" and type(keys.Register) == "function" then
    keys.Register("lootHistory", function() H.Toggle() return true end, ADDON)
end

-- Neue Beute oder neues Gold: offenes Fenster nachziehen.
local refreshSoon = ns.Throttle(function() if H.IsShown() then H.Refresh() end end, 0.2)
Core.Listen("HISTORY_ADDED", function(kind)
    if kind == "loot" and H.IsShown() then refreshSoon() end
end, ADDON)
-- „Verlauf leeren“ (art = nil: alles): ein offenes Fenster zeigt sonst weiter den alten Stand.
Core.Listen("HISTORY_CLEARED", function(kind)
    if (kind == nil or kind == "loot") and H.IsShown() then refreshSoon() end
end, ADDON)
ns.On("ZONE_CHANGED_NEW_AREA", function() if H.IsShown() and View().zone then refreshSoon() end end)
-- Ansicht „Mögliche Beute“ folgt dem Ziel, solange es ein NPC ist (sonst bleibt der zuletzt gezeigte Gegner).
function H.OnTargetChanged()
    if not (H.IsShown() and H.mode == "possible") then return false end
    local npc = ns.Drops.UnitNpc("target")
    if not npc then return false end
    H.possible = H.PossibleTarget()
    refreshSoon()
    return true
end
ns.On("PLAYER_TARGET_CHANGED", function() H.OnTargetChanged() end)

-- Andocken: Blizzards Fenster einhängen, sobald es da ist (ohne Schalter seit dem 19.11.2026)
ns.OnReady(function() H.SetupDock() end)
