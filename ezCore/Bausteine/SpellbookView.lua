local Core = ezCore

--[[
    Eigene Ansicht im Zauberbuch: Core.NewSpellbookView(opts) (vorher ezMerchant/Spellbook.lua, „Was kommt wann“;
    gemeinsam für ezMerchant, ezCombat „Rotation“ und jedes weitere Modul, Wunsch von ezCombat 13.11.2026).
    Ein Seitenreiter rechts an Blizzards Zauberbuch (Blizzard_PlayerSpells, Forever-Fassung „Camelot“) schlägt im
    Buch selbst eine eigene Seite auf – an Stelle der Zauberliste, solange der Reiter aktiv ist. Das Modul liefert nur
    seine Zeilen (lines) und Texte; Buchseiten, Kopfzeilen, Einträge, Seiten-Layout und Blättern baut ezCore.

    Optik aus Blizzards Zauberbuch (Forever-Quelle, Camelot/SpellBook/Blizzard_SpellBookTemplates.xml und
    SpellBook/Blizzard_SpellBookItem.xml): Buchseiten „spellbook-Page-Left/Right-C60“, Kopfzeilen aus
    SpellBookHeaderTemplate, Einträge wie SpellBookItemTemplate (Rahmen-Atlas, Symbol mit Maske, bis zu drei
    Textzeilen; „beim Lehrer erlernbar“ mit Blizzards Schatten, „kommt später“ grau), Blättern mit
    PagingControlsHorizontalTemplate an derselben Stelle wie Blizzards. Verkleinertes Buch: eine Seite statt zwei.

    Mehrere Ansichten: Nur eine eigene Ansicht ist offen; öffnet man eine zweite, schließt sich die erste. Die
    Seitenreiter stehen untereinander im Seitenreiter-Stapel des Zauberbuchs (Core.SideTabs, Anker PlayerSpellsFrame;
    Gesamtreview 18.11.2026, T16-4 – vorher feste y-Werte über das Register SV.ClaimTab): Reihenfolge-Zahl opts.order
    (ezMerchant 10, ezMacros „Ränge aktualisieren“ 20, ezCombat 30, ezHeal 40), sichtbare Reiter lückenlos. Ohne
    order gilt der alte Wunschplatz opts.tabY als Zahl (SV.OrderFromY: −70 » 10, −114 » 20 …). SV.ClaimTab und
    SV.TabOwner bleiben als Auskunft über die gewünschten Plätze (Leitlinie 8); die Lage setzt der Stapel.

    Einträge begrenzen ihre Zeilen selbst (FP-10, Spieltest 14.11.2026: lange Bedingungen überdeckten auf ezCombats
    Seite „Rotation“ Nachbarn und Kopfzeilen). Seit dem Spieltest vom 15.11.2026 (Befund 3: „Zauberbuch unsere
    sektion schlecht formatiert“ – Einträge mit drei Textzeilen liefen ineinander, auf „Was kommt wann“ lag der
    Kopf-Eintrag über „Stufe 12“, Texte endeten mitten im Wort mit „…“) rechnet die Ansicht die Zeilen VORHER aus,
    als reine Funktion (SV.Wrap, SV.EntryText), statt sich auf die Höhe zu verlassen, die das Spiel beim Zeichnen
    meldet: höchstens drei Zeilen je Eintrag (SV.ENTRY_LINES) in der Reihenfolge Name, dritte Zeile (Zustand,
    Kosten, Quelle), zweite Zeile, zweite Zeile des Namens, weitere der zweiten und dritten; umbrochen und gekürzt wird an
    Wortgrenzen („…“), der ganze Text steht dann im Tooltip. Jeder Eintrag ist so hoch wie seine Zeilen (mindestens
    wie Blizzards Eintrag, SV.EntryHeight), beide Einträge einer Reihe gleich hoch; jede Schrift bekommt ihre Höhe
    und Zeilengrenze fest. Kopfzeilen halten oben festen Abstand (SV.HEADER_GAP), der Text rechts daneben steht auf
    derselben Grundlinie. Der Text endet 14 Punkte vor der nächsten Spalte bzw. vor der Knopfspalte. Absätze ohne
    eigene Höhe bekommen eine aus der Textlänge (SV.TextHeight) und kürzen sich an Wortgrenzen auf ihre Zeilen. Der
    Tooltip wählt die Seite nach dem Platz (Core.TipAnchor). Eine Fußzeile (opts.footer) nennt z. B. die Quelle.

    Knöpfe (EC-35, nur mit opts.buttons = true): Ein Eintrag trägt bis zu drei Knöpfe (line.buttons, Kästchen oder
    Pfeil) in einer Spalte am rechten Rand, die Zeilenart „action“ einen Knopf unter ihrem Text (mit line.second einen
    zweiten rechts daneben). Ein Klick ruft nur opts.onButton des Moduls (nichts Geschütztes, kein Zauber) und zeichnet
    die Seite neu. Ziehen eines Eintrags auf einen anderen (line.drag, opts.onDrop): SV.DragStart/SV.DragStop.

    Taint-sicher: eigene Rahmen als Kinder von SpellBookFrame bzw. PlayerSpellsFrame, nur an Blizzards Teilen
    verankert (PagedSpellsFrame und seine Ansichten View1/View2, Buchseiten); die Ansicht deckt die Zauberliste ab,
    statt sie zu verstecken. Blizzards Zauberliste, Kategorie-Reiter, Suche und Einstellungen bleiben unberührt.
    Zurück zu den Zaubern: der Reiter, ein Kategorie-Reiter, ein Sprung zu einem Zauber oder die Suche – einmal für
    alle Ansichten über hooksecurefunc/HookScript. Nichts wird in Blizzards Tabellen geschrieben, nichts Geschütztes
    aufgerufen (Klick auf einen Eintrag ruft nur opts.onClick des Moduls).
]]

local SV = {}
Core.SpellbookView = SV

local TAB_ICON = "Interface\\Icons\\INV_Misc_Book_11"
local QUESTION_ICON = Core.ICON_FALLBACK
local TOP_GAP = 38                    -- unter Kategorie-Reitern und Suche; Blizzards Einträge beginnen 45 tiefer
local PAGE_X1, PAGE_X2, PAGE_Y = 85, -50, -45   -- wie PagedSpellsView1/View2Template (Ersatz ohne Blizzards Ansichten)
local PAGE_W, PAGE_H = 448, 520
local CELL_H, HEADER_H, TEXT_H = 60, 60, 100     -- SpellBookItemTemplate, SpellBookHeaderSizeTemplate
local X_PAD, Y_PAD = 8, 10
local BACKPLATE_ALPHA, BACKPLATE_HOVER = 0.25, 1  -- defaultBackplateAlpha, hoverBackplateAlpha
local UNLEARNED_ALPHA = 0.6                       -- unlearnedTextAlpha, unlearnedIconAlpha
local PAGE_ART = {                                -- Buchseiten des Zauberbuchs (SpellBookBG…Template)
    BookBGLeft = "spellbook-Page-Left-C60", BookBGRight = "spellbook-Page-Right-C60", BookBGHalved = "spellbook-Page-Right-C60",
}
local BORDER = {                                  -- SpellBookItemMixin.ArtSet.Square
    active = { atlas = "spellbook-item-iconframe", tl = { -11, 1 }, br = { 1, -7 } },
    inactive = { atlas = "spellbook-item-iconframe-inactive", tl = { -10, 1 }, br = { 2, -5 } },
}

SV.CELL_H, SV.HEADER_H, SV.TEXT_H, SV.PAGE_W, SV.PAGE_H = CELL_H, HEADER_H, TEXT_H, PAGE_W, PAGE_H

-- Grenzen der Einträge und Knöpfe (FP-10, EC-35; Maße wie ezCombats Seite „Rotation“, die das bisher selbst tat)
SV.TEXT_GAP = 14                      -- Abstand des Eintragstexts zur nächsten Spalte
SV.BUTTON_W = 22                      -- Knopfspalte am rechten Rand eines Eintrags
SV.MAX_BUTTONS = 3                    -- höchstens so viele Knöpfe je Eintrag
SV.NAME_LINES, SV.SUB_LINES, SV.DETAIL_LINES = 2, 2, 2   -- je Teil höchstens (zusammen SV.ENTRY_LINES)
SV.ACTION_H, SV.ACTION_BUTTON_H = 54, 22   -- Zeile mit Knopf: Text oben, Knopf darunter
SV.TEXT_LINE_H, SV.CHAR_W = 16, 7.5        -- Schätzung eines Absatzes (Zeilenhöhe, Breite je Zeichen)
SV.FOOTER_H = 28                      -- Fußzeile unter der ersten Buchseite (zwei kleine Zeilen)
-- Die Seite kann Knöpfe selbst zeichnen (für Module, die opts.buttons = true setzen). Der ältere Merker
-- Abnehmer prüfen SV.NATIVE_BUTTONS (ezCombat ist seit Welle 10 umgestellt: opts.buttons = true, Book.Decorate entfiel;
-- view:Widgets()/view:ActionButton(key) für Tests und Rundgang). Ein zweiter Merker SV.BUTTONS war geplant, wurde nie
-- gesetzt und hat keinen Leser – es gibt ihn nicht (Welle 11).
SV.NATIVE_BUTTONS = true
-- Vorab gerechnete Zeilen eines Eintrags (Spieltest 15.11.2026, Befund 3): Maße der Schriften aus Blizzards Eintrag
-- (Name SystemFont_Large, zweite und dritte Zeile SystemFont_Med1), eher zu groß geschätzt – lieber ein Wort früher
-- umbrechen, als dass das Spiel mitten im Wort kürzt.
SV.ENTRY_LINES = 3                    -- höchstens so viele Textzeilen je Eintrag
SV.NAME_LINE_H, SV.SMALL_LINE_H, SV.LINE_GAP = 20, 15, 2
SV.NAME_CHAR_W = 9                    -- Breite je Zeichen im Namen (SV.CHAR_W gilt für die kleine Schrift)
SV.ENTRY_PAD = 4                      -- Rand über und unter dem Text eines Eintrags
SV.ICON_W = 50                        -- Symbol links im Eintrag (Text beginnt dort)
SV.HEADER_GAP = 12                    -- fester Abstand über einer Kopfzeile (nicht ganz oben auf der Seite)
SV.HEADER_CHAR_W, SV.SUM_CHAR_W = 12, 8.5   -- Überschrift (SystemFont_Huge2), Text rechts (SystemFont_Med3)
SV.HEADER_SUM_Y = 4                   -- Unterkante des Texts rechts über der Mitte der Kopfzeile (Überschrift: +14)
SV.HEADER_LINE_H, SV.SUM_LINE_H = 26, 17    -- Zeilenhöhe der Überschrift und des Texts rechts (SV.CellRects)
local ELLIPSIS = "…"
local ARROW = "Interface\\Buttons\\Arrow-%s-%s"   -- klassische Dateien: Arrow-Up-Up, Arrow-Down-Disabled …

---------------------------------------------------------------------------
-- Plätze der Seitenreiter (y an PlayerSpellsFrame TOPRIGHT)
---------------------------------------------------------------------------

SV.TAB_TOP, SV.TAB_STEP = -70, 44
-- Feste Plätze von Reitern, die keine eigene Ansicht sind (ezMacro „Ränge aktualisieren“, ezMacro/Ranks.lua).
-- Sie gelten auch, wenn das Modul nicht geladen ist: kein Reiter springt je nach Ladereihenfolge.
SV.RESERVED = { [-114] = "ezMacro.ranks" }
-- Geplant (ROADMAP): ezMerchant „Was kommt wann“ −70, ezMacro −114, ezCombat „Rotation“ −158.
local claims = {}
for y, key in pairs(SV.RESERVED) do claims[y] = key end

-- Reihenfolge-Zahl im Seitenreiter-Stapel aus einem alten Wunschplatz y (−70 » 10, −114 » 20, −158 » 30, −202 » 40 …);
-- ohne y die Standardzahl des Stapels (T16-4).
function SV.OrderFromY(y)
    y = tonumber(y)
    if not y then return Core.SideTabs and Core.SideTabs.ORDER or 100 end
    return math.floor((SV.TAB_TOP - y) / SV.TAB_STEP + 0.5) * 10 + 10
end

-- Platz für den Reiter von key: der gewünschte (Standard: der oberste), sonst der nächste freie darunter. → y
-- Seit T16-4 nur noch Auskunft (die Lage setzt der Seitenreiter-Stapel).
function SV.ClaimTab(key, y)
    y = tonumber(y) or SV.TAB_TOP
    for _ = 1, 50 do
        local owner = claims[y]
        if owner == nil or owner == key then
            claims[y] = key
            return y
        end
        y = y - SV.TAB_STEP
    end
    return y
end

-- Wer hat den Platz y? → key oder nil
function SV.TabOwner(y) return claims[tonumber(y) or 0] end

---------------------------------------------------------------------------
-- Zauberbuch
---------------------------------------------------------------------------

local function Book() return PlayerSpellsFrame and PlayerSpellsFrame.SpellBookFrame end

local function BookShown()
    local book = Book()
    return book ~= nil and book:IsVisible()
end

-- Schriftfarbe der Buchseiten (Blizzards SPELLBOOK_FONT_COLOR, sonst ein dunkles Braun).
local function BookColor()
    local c = _G.SPELLBOOK_FONT_COLOR
    if type(c) == "table" and c.GetRGB then return c:GetRGB() end
    return 0.21, 0.13, 0.05
end

-- Verkleinertes Zauberbuch (eine Seite)? Blizzard blendet dann View2 aus (SpellBookFrameMixin:SetMinimized).
function SV.Minimized()
    local book = Book()
    local list = book and book.PagedSpellsFrame
    local second = list and list.View2
    if type(second) == "table" and second.IsShown then return not second:IsShown() end
    return book ~= nil and book.isMinimized == true
end

local function PageSize()
    local book = Book()
    local first = book and book.PagedSpellsFrame and book.PagedSpellsFrame.View1
    local w, h = first and first:GetWidth(), first and first:GetHeight()
    if not (w and w > 100) then w = PAGE_W end
    if not (h and h > 100) then h = PAGE_H end
    return w, h
end

-- Text, Zahl oder Pfad aus den Zeilen des Moduls: geheime Werte gelten als nicht da (nie vergleichen).
local function Plain(v)
    if Core.IsSecret(v) then return nil end
    return v
end

local function HasText(v)
    v = Plain(v)
    return (type(v) == "string" and v ~= "") or type(v) == "number"
end

-- Was von einem Text auf der Seite zu sehen ist (Spieltest 15.11.2026, „Was kommt wann“: „bei manchen ‚Stufe...‘ bei
-- anderen das richtige level“): Steuerzeichen des Spiels zählen nicht – Farbe (|cAARRGGBB, |cn…:, |r), Verweise
-- (|H…|h Text |h: nur der Text) –, ein Bild (|T…|t, |A…|a, etwa Blizzards Münzen aus GetCoinTextureString) zählt
-- wie SV.ICON_CHARS Zeichen. Vorher zählte jede Münze mit ihrem Pfad als rund 45 Zeichen: Die Summe rechts in der
-- Kopfzeile („bis hier“ mit Münzbildern) bekam bis zu drei Viertel der Breite, die Überschrift „Stufe 30“ nur so
-- viel, wie die Schätzung knapp für sie annahm – das Spiel kürzte sie zu „Stufe...“. Kosten im Eintrag wurden mitten
-- im Pfad einer Münze umbrochen.
SV.ICON_CHARS = 2
local ICON_STAND_IN = string.rep("M", SV.ICON_CHARS)
local function Visible(text)
    text = tostring(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:|]*:", ""):gsub("|r", "")
    text = text:gsub("|H.-|h(.-)|h", "%1"):gsub("|[TA].-|[ta]", ICON_STAND_IN)
    return text
end

-- Sichtbare Zeichen eines Textes (nicht Bytes, ohne Steuerzeichen; ein Bild wie SV.ICON_CHARS Zeichen).
local function Chars(text) return select(2, Visible(text):gsub("[^\128-\191]", "")) end
SV.VisibleChars = Chars

-- Geschätzte Höhe eines Absatzes für das Seiten-Layout (vor dem Zeichnen; sichtbare Zeichen). → Punkte
function SV.TextHeight(text, width)
    text = Plain(text)
    if not HasText(text) then return TEXT_H end
    local perLine = math.max(10, math.floor((tonumber(width) or PAGE_W) / SV.CHAR_W))
    local lines = 0
    for part in (tostring(text) .. "\n"):gmatch("(.-)\n") do
        lines = lines + math.max(1, math.ceil(Chars(part) / perLine))
    end
    return lines * SV.TEXT_LINE_H + 10
end

-- Die ersten n Zeichen (UTF-8).
local function Head(text, n)
    if n <= 0 then return "" end
    local count, cut = 0, #text
    for pos = 1, #text do
        local byte = text:byte(pos)
        if byte < 128 or byte >= 192 then
            count = count + 1
            if count > n then
                cut = pos - 1
                break
            end
        end
    end
    return text:sub(1, cut)
end

-- Text auf Zeilen verteilen, umbrochen an Wortgrenzen (Leerzeichen; ein Zeilenwechsel bricht fest um). Ein Wort,
-- das allein länger als eine Zeile ist, wird geteilt. Mehr als maxLines Zeilen: die letzte endet an einer Wortgrenze
-- mit „…“. Gemessen werden sichtbare Zeichen (Visible); ein Wort mit Steuerzeichen wird nie geteilt. width in
-- Punkten, charW Breite je Zeichen (Standard SV.CHAR_W). → { Zeile … }, gekürzt (true/false)
function SV.Wrap(text, width, maxLines, charW)
    text = Plain(text)
    if not HasText(text) then return {}, false end
    maxLines = math.max(0, math.floor(tonumber(maxLines) or 1))
    local perLine = math.max(4, math.floor((tonumber(width) or PAGE_W) / (tonumber(charW) or SV.CHAR_W)))
    local lines = {}
    for paragraph in (tostring(text) .. "\n"):gmatch("(.-)\n") do
        local current = ""
        for word in paragraph:gmatch("%S+") do
            -- überlanges Wort: teilen – nie eines mit Steuerzeichen (Münze, Farbe), sonst bräche ein Bildpfad auf
            while Chars(word) > perLine and not word:find("|", 1, true) do
                if current ~= "" then
                    lines[#lines + 1] = current
                    current = ""
                end
                local head = Head(word, perLine)
                lines[#lines + 1] = head
                word = word:sub(#head + 1)
            end
            if word ~= "" then
                if current == "" then
                    current = word
                elseif Chars(current) + 1 + Chars(word) <= perLine then
                    current = current .. " " .. word
                else
                    lines[#lines + 1] = current
                    current = word
                end
            end
        end
        lines[#lines + 1] = current
    end
    while #lines > 0 and lines[#lines] == "" do lines[#lines] = nil end
    if #lines <= maxLines then return lines, false end
    if maxLines == 0 then return {}, true end
    local kept = {}
    for i = 1, maxLines do kept[i] = lines[i] end
    -- letzte Zeile: Wörter abwerfen, bis „…“ dahinter passt (an einer Wortgrenze)
    local last = kept[maxLines]
    while Chars(last) + 1 > perLine do
        local shorter = last:match("^(.*%S)%s+%S+$")
        if not shorter then
            if not last:find("|", 1, true) then last = Head(last, perLine - 1) end
            break
        end
        last = shorter
    end
    kept[maxLines] = last .. ELLIPSIS
    return kept, true
end

-- Felder eines Eintrags wie FillSpell sie liest: Name, zweite, dritte Zeile (Text oder nil).
local function EntryFields(line)
    local name = Plain(line.name) or Plain(line.left) or ""
    local sub = Plain(line.sub)
    local detail = Plain(line.detail)
    if detail == nil then detail = Plain(line.right) end
    return tostring(name), HasText(sub) and tostring(sub) or nil, HasText(detail) and tostring(detail) or nil
end

-- Breite des Texts in einem Eintrag der Breite w (Symbol links, rechts Abstand bzw. Knopfspalte).
function SV.EntryTextWidth(line, w)
    local inset = type(line.buttons) == "table" and (SV.BUTTON_W + 2) or SV.TEXT_GAP
    return math.max(20, (tonumber(w) or 220) - SV.ICON_W - inset)
end

-- Zeilen eines Eintrags vorab (reine Funktion, Befund 3): höchstens SV.ENTRY_LINES, verteilt in der Reihenfolge
-- Name, dritte Zeile, zweite Zeile, zweite Zeile des Namens, zweite der zweiten Zeile, zweite der dritten Zeile (je
-- Teil höchstens SV.NAME_LINES, SV.SUB_LINES, SV.DETAIL_LINES). w: Breite des Eintrags.
-- → { name = { text, lines, full }, sub = …, detail = …, height (Höhe des Texts), cut (etwas ist gekürzt) };
-- lines = 0: der Teil fehlt oder hat keinen Platz (dann steht er nur im Tooltip).
function SV.EntryText(line, w)
    local width = SV.EntryTextWidth(line, w)
    local name, sub, detail = EntryFields(line)
    local texts = { name = name, sub = sub, detail = detail }
    local charW = { name = SV.NAME_CHAR_W, sub = SV.CHAR_W, detail = SV.CHAR_W }
    local caps = { name = SV.NAME_LINES, sub = SV.SUB_LINES, detail = SV.DETAIL_LINES }
    local want, got = {}, { name = 0, sub = 0, detail = 0 }
    for _, part in ipairs({ "name", "sub", "detail" }) do
        want[part] = texts[part] and #(SV.Wrap(texts[part], width, 99, charW[part])) or 0
    end
    want.name = math.max(1, want.name)
    local left = SV.ENTRY_LINES
    for _, part in ipairs({ "name", "detail", "sub", "name", "sub", "detail" }) do
        if left > 0 and got[part] < want[part] and got[part] < caps[part] then
            got[part] = got[part] + 1
            left = left - 1
        end
    end
    local result, cut, parts = { height = 0 }, false, 0
    for _, part in ipairs({ "name", "sub", "detail" }) do
        local text, n = texts[part], got[part]
        local entry = { text = "", lines = n, full = text }
        if text and n > 0 then
            local lines, partCut = SV.Wrap(text, width, n, charW[part])
            entry.text = partCut and table.concat(lines, "\n") or text   -- ungekürzt: der Text, wie er ist
            entry.lines = math.max(1, math.min(n, #lines))
            cut = cut or partCut
        elseif text and HasText(text) then
            cut = true                                                  -- kein Platz: nur im Tooltip
        end
        if part == "name" then entry.lines = math.max(1, entry.lines) end
        if entry.lines > 0 then
            parts = parts + 1
            result.height = result.height + entry.lines * (part == "name" and SV.NAME_LINE_H or SV.SMALL_LINE_H)
        end
        result[part] = entry
    end
    result.height = result.height + math.max(0, parts - 1) * SV.LINE_GAP
    result.cut = cut
    return result
end

-- Kopfzeile (reine Funktion): Überschrift links, Text rechts – beide eine Zeile, die Überschrift endet vor dem Text
-- rechts (an einer Wortgrenze gekürzt). w: Breite der Kopfzeile. → { left, right, leftW, rightW, cut }
function SV.HeaderText(line, w)
    w = tonumber(w) or PAGE_W
    local left = HasText(line.left) and tostring(Plain(line.left)) or ""
    local right = HasText(line.right) and tostring(Plain(line.right)) or ""
    local span = w + 8 - 60                                   -- Blizzards Anker: links −8, rechts −60
    -- Der Zusatz bekommt, was die Überschrift nicht braucht (bis zur Hälfte, wenn beide lang sind); die Überschrift
    -- behält ein Zeichen Reserve, denn die Schätzung je Zeichen ist ein Mittelwert (Ziffern und „W“ sind breiter).
    local leftNeed = math.min(span, math.ceil((Chars(left) + (left ~= "" and 1 or 0)) * SV.HEADER_CHAR_W))
    local rightW = right ~= "" and math.min(math.ceil(Chars(right) * SV.SUM_CHAR_W),
        math.max(span - leftNeed - 8, math.floor(span / 2))) or 0
    local leftW = span - (rightW > 0 and rightW + 8 or 0)
    local lines, cutL = SV.Wrap(left, leftW, 1, SV.HEADER_CHAR_W)
    local rlines, cutR = SV.Wrap(right, rightW, 1, SV.SUM_CHAR_W)
    return { left = cutL and (lines[1] or "") or left, right = cutR and (rlines[1] or "") or right,
        leftW = leftW, rightW = rightW, cut = cutL or cutR }
end

-- Höhe eines Eintrags: so hoch wie seine Zeilen, mindestens wie Blizzards Eintrag (CELL_H).
function SV.EntryHeight(line, w)
    return math.max(CELL_H, SV.EntryText(line, w).height + 2 * SV.ENTRY_PAD)
end

---------------------------------------------------------------------------
-- Seiten-Layout
---------------------------------------------------------------------------

-- Verteilt die Zeilen auf Buchseiten wie Blizzards Zauberbuch: Kopfzeile über die ganze Breite, Einträge zu zweit
-- nebeneinander; passt etwas nicht mehr, geht es auf der nächsten Seite weiter (eine Kopfzeile nie allein unten).
-- Einträge sind so hoch wie ihre Zeilen (SV.EntryHeight; beide einer Reihe gleich hoch; cell.text: die vorab
-- gerechneten Zeilen, SV.EntryText), Kopfzeilen halten oben SV.HEADER_GAP Abstand.
-- → { Seite = { { line, x, y, w, h, text } … } … }
function SV.Layout(lines, pageW, pageH)
    pageW, pageH = pageW or PAGE_W, pageH or PAGE_H
    local colW = math.floor((pageW - X_PAD) / 2)
    local pages, page = {}, {}
    pages[1] = page
    local y, col = 0, 0
    local row               -- Zellen der laufenden Reihe (am Ende gleich hoch)
    local function CloseRow()
        local h = CELL_H
        for _, cell in ipairs(row or {}) do h = math.max(h, cell.h) end
        for _, cell in ipairs(row or {}) do cell.h = h end
        row = nil
        y, col = y + h + Y_PAD, 0
    end
    local function NewPage()
        page = {}
        pages[#pages + 1] = page
        y, col = 0, 0
    end
    -- Vorab: Zeilen und Höhe jedes Eintrags (eine Reihe ist so hoch wie ihr höherer Eintrag)
    local texts, heights = {}, {}
    for i, line in ipairs(lines or {}) do
        if line.kind == "spell" then
            texts[i] = SV.EntryText(line, colW)
            heights[i] = math.min(math.max(CELL_H, texts[i].height + 2 * SV.ENTRY_PAD), pageH)
        end
    end
    -- Höhe der Reihe, die bei Zeile i beginnt (ein Eintrag oder zwei nebeneinander); 0, wenn dort kein Eintrag steht.
    local function RowHeight(i)
        local h = heights[i]
        if not h then return 0 end
        return math.max(h, heights[i + 1] or 0)
    end
    -- Höhe einer Zeile über die ganze Breite (Kopfzeile, Absatz, Zeile mit Knopf); nie höher als die Seite: der
    -- Absatz kürzt sich, der Tooltip zeigt alles.
    local function BlockHeight(line)
        if line.kind == "header" then return math.min(HEADER_H, pageH) end
        local h = tonumber(Plain(line.height))
        if not h then
            h = line.kind == "action" and SV.ACTION_H or SV.TextHeight(Plain(line.text) or Plain(line.left), pageW)
        end
        return math.min(h, pageH)
    end
    for i, line in ipairs(lines or {}) do
        if line.kind == "spell" then
            local text, h = texts[i], heights[i]
            -- Die Reihe muss ganz auf die Seite passen, auch mit einem höheren rechten Partner (Gegenprüfung Welle 13)
            if col == 0 and y > 0 and y + RowHeight(i) > pageH then NewPage() end
            local cell = { line = line, x = col * (colW + X_PAD), y = y, w = colW, h = h, text = text }
            page[#page + 1] = cell
            if col == 1 then
                row[#row + 1] = cell
                CloseRow()
            else
                row = { cell }
                col = 1
            end
        else
            if col == 1 then CloseRow() end
            if line.kind == "header" and y > 0 then y = y + SV.HEADER_GAP end
            local h = BlockHeight(line)
            -- Eine Kopfzeile nie allein unten (Spieltest 21.11.2026, Bild 1: „Im Kampf“ unten, die Fähigkeiten erst
            -- auf der nächsten Seite – dazwischen stand der Einleitungssatz): mit ihr müssen die Absätze und Knopfzeilen
            -- darunter UND die erste Reihe von Einträgen passen (samt Zeilenabständen); folgt bis zur nächsten
            -- Kopfzeile keine Reihe, wenigstens die erste Zeile darunter. Passt das nicht, beginnt der Abschnitt
            -- auf einer neuen Seite.
            local need = h
            if line.kind == "header" then
                local j, extra = i + 1, 0
                while lines[j] and lines[j].kind ~= "header" and lines[j].kind ~= "spell" do
                    extra = extra + Y_PAD + BlockHeight(lines[j])
                    j = j + 1
                end
                local first = lines[i + 1] and lines[i + 1].kind ~= "header"
                    and (heights[i + 1] and RowHeight(i + 1) or BlockHeight(lines[i + 1])) or nil
                if heights[j] then
                    need = h + extra + Y_PAD + RowHeight(j)
                end
                -- passt der Anfang nicht einmal auf eine leere Seite: wenigstens die erste Zeile darunter
                if first and (need == h or need > pageH) then need = h + Y_PAD + first end
            end
            if y > 0 and y + need > pageH then NewPage() end
            page[#page + 1] = { line = line, x = 0, y = y, w = pageW, h = h }
            y = y + h + Y_PAD
        end
    end
    return pages
end

-- Wo auf der Seite gezeichnet wird (reine Funktion, Befund 3; dieselben Anker wie Render): Rechtecke einer Zelle aus
-- SV.Layout in Seiten-Punkten von oben links – { kind = "icon" | "text" | "title" | "right" | "block", x, y, w, h }.
-- Damit lässt sich ohne Spiel prüfen, dass kein Text einen anderen überdeckt.
function SV.CellRects(cell)
    local rects = {}
    local line, x, y, w, h = cell.line, cell.x, cell.y, cell.w, cell.h
    local function Add(kind, rx, ry, rw, rh)
        if rw > 0 and rh > 0 then rects[#rects + 1] = { kind = kind, x = rx, y = ry, w = rw, h = rh, cell = cell } end
    end
    if line.kind == "spell" then
        local fit = cell.text or SV.EntryText(line, w)
        Add("icon", x, y + h / 2 - 20, 40, 40)
        Add("text", x + SV.ICON_W, y + (h - fit.height) / 2 + 1, SV.EntryTextWidth(line, w), fit.height)
    elseif line.kind == "header" then
        local head = SV.HeaderText(line, w)
        local mid = y + h / 2
        Add("title", x - 8, mid - 14 - SV.HEADER_LINE_H / 2, head.leftW, SV.HEADER_LINE_H)
        Add("right", x + w - 60 - head.rightW, mid - SV.HEADER_SUM_Y - SV.SUM_LINE_H, head.rightW, SV.SUM_LINE_H)
    else
        Add("block", x + 4, y + 4, w - 8, h - 8)
    end
    return rects
end

---------------------------------------------------------------------------
-- Bausteine in Blizzards Optik
---------------------------------------------------------------------------

local function Color(fs) fs:SetTextColor(BookColor()) end

-- Kopfzeile: Blizzards SpellBookHeaderTemplate (Schrift, Trennlinie, Hintergrund), rechts ein zweiter Text.
local function NewHeader(parent)
    local ok, h = pcall(CreateFrame, "Frame", nil, parent, "SpellBookHeaderTemplate")
    if not (ok and h and type(h.Text) == "table") then
        h = CreateFrame("Frame", nil, parent)
        h.Text = h:CreateFontString(nil, "ARTWORK", "SystemFont_Huge2")
        h.Text:SetPoint("LEFT", -8, 14)
        h.Text:SetPoint("RIGHT", -60, 14)
        h.Text:SetJustifyH("LEFT")
        Color(h.Text)
        local border = h:CreateTexture(nil, "ARTWORK")
        border:SetAtlas("spellbook-divider")
        border:SetHeight(11)
        border:SetPoint("BOTTOMLEFT", -32, 0)
        border:SetPoint("BOTTOMRIGHT", -60, 0)
    end
    -- Text rechts (Befund 3: „viel kleiner und hängt lose“): etwas größer, unten bündig mit der Überschrift
    h.Sum = h:CreateFontString(nil, "ARTWORK", "SystemFont_Med3")
    h.Sum:SetPoint("BOTTOMRIGHT", h, "RIGHT", -60, SV.HEADER_SUM_Y)
    h.Sum:SetJustifyH("RIGHT")
    if h.Sum.SetMaxLines then h.Sum:SetMaxLines(1) end
    if h.Text.SetMaxLines then h.Text:SetMaxLines(1) end
    Color(h.Sum)
    h.Right = h.Sum
    return h
end

local function SetBorder(f, kind)
    local b = BORDER[kind]
    f.Border:SetAtlas(b.atlas)
    f.Border:ClearAllPoints()
    f.Border:SetPoint("TOPLEFT", f.IconFrame, "TOPLEFT", b.tl[1], b.tl[2])
    f.Border:SetPoint("BOTTOMRIGHT", f.IconFrame, "BOTTOMRIGHT", b.br[1], b.br[2])
end

-- Zusatzzeilen im Tooltip eines Eintrags: Text (weiß, umbrochen), { text, rolle, umbrechen } mit einer Rolle wie
-- Core.TipLine („hint“, „good“ …; umbrochen, solange umbrechen nicht false ist – Gesamtreview 18.11.2026, Wunsch aus
-- ezMerchant statt dessen Rekorder ns.TipRow; Fähigkeit spellbookTipRoles in Core.FEATURES, damit ein Modul mit
-- solchen Zeilen ein älteres ezCore über needs erkennt), { text, r, g, b, wrap } oder fn(tooltip, line).
-- line.tipWide = true: breiter Tooltip (Core.TipWide) mit einer Leerzeile zwischen den Zusatzzeilen (Core.Tooltip.Gap);
-- eine Zeile als Tabelle mit join = true hängt ohne Leerzeile an der vorigen (kurze Hinweise als ein Block).
local function AddTipLines(tooltip, extra, line)
    local gaps = type(line) == "table" and line.tipWide == true
    if type(extra) == "function" then
        extra(tooltip, line)
    elseif type(extra) == "table" then
        local any = false
        for _, t in ipairs(extra) do
            local text = type(t) == "table" and t[1] or t
            local join = type(t) == "table" and t.join == true
            if gaps and any and not join and HasText(text) and Core.Tooltip and Core.Tooltip.Gap then
                Core.Tooltip.Gap(tooltip)
            end
            if HasText(text) then any = true end
            if type(t) == "table" and type(t[2]) == "string" then
                if HasText(t[1]) then Core.TipLine(tooltip, t[1], t[2], t[3] ~= false) end
            elseif type(t) == "table" then
                if HasText(t[1]) then tooltip:AddLine(t[1], t[2] or 1, t[3] or 1, t[4] or 1, t[5]) end
            elseif HasText(t) then
                Core.TipLine(tooltip, t, "highlight")
            end
        end
    elseif HasText(extra) then
        Core.TipLine(tooltip, extra, "highlight", true)
    end
end

SV.AddTipLines = AddTipLines   -- Tests

-- Steht dieser Text schon in den Zusatzzeilen des Tooltips?
local function TipHas(extra, text)
    if type(extra) == "string" then return extra:find(text, 1, true) ~= nil end
    if type(extra) ~= "table" then return false end
    for _, t in ipairs(extra) do
        local v = type(t) == "table" and t[1] or t
        if type(v) == "string" and v:find(text, 1, true) then return true end
    end
    return false
end

-- Gekürzte Teile eines Eintrags ganz in den Tooltip (Befund 3), sofern das Modul sie nicht schon dort nennt.
function SV.CutTipLines(line, fit)
    local result = {}
    if type(fit) ~= "table" or not fit.cut then return result end
    for _, part in ipairs({ "name", "sub", "detail" }) do
        local entry = fit[part]
        local full = entry and entry.full
        if HasText(full) and entry.text ~= full and not TipHas(line.tooltip, full)
            and not (part == "name" and Plain(line.title) == full) then
            result[#result + 1] = full
        end
    end
    return result
end

local function ShowSpellTip(self)
    local line = self.line
    if not line then return end
    self.Backplate:SetAlpha(BACKPLATE_HOVER)
    GameTooltip:SetOwner(self, Core.TipAnchor(self))
    local id = tonumber(Plain(line.spellID))
    if id and GameTooltip.SetSpellByID then
        GameTooltip:SetSpellByID(id)
    else
        Core.TipTitle(GameTooltip, Plain(line.title) or Plain(line.left) or Plain(line.name) or "")
    end
    if line.tipWide == true and Core.TipWide then
        Core.TipWide(GameTooltip)
        if id and Core.Tooltip and Core.Tooltip.Gap then Core.Tooltip.Gap(GameTooltip) end   -- Abstand zu Blizzards Text
    end
    AddTipLines(GameTooltip, line.tooltip, line)
    for _, text in ipairs(SV.CutTipLines(line, self.fit)) do Core.TipLine(GameTooltip, text, "highlight", true) end
    GameTooltip:Show()
end

--[[
    Ziehen mit der Maus (Rotation im Zauberbuch: Reihenfolge der Schritte ändern, Entscheidung des Nutzers vom
    20.11.2026 „Klick tauscht, Ziehen schiebt“): Ein Eintrag mit line.drag = true lässt sich mit gedrückter linker
    Maustaste auf einen anderen Eintrag ziehen, wenn das Modul opts.onDrop(vonZeile, aufZeile, vonEintrag, aufEintrag)
    angibt. opts.canDrag(zeile) → false, grund verbietet den Anfang (das Modul zeigt den Grund selbst, z. B. im Kampf).
    Gezogen wird nur in eigenen Rahmen (nichts Geschütztes, kein Zauber auf dem Cursor); der gezogene Eintrag ist
    währenddessen halb durchsichtig. Losgelassen über einem anderen Eintrag ruft ezCore onDrop und zeichnet die Seite
    neu; anderswo losgelassen ruft es onDrop mit aufZeile = nil. Ein Klick direkt nach dem Loslassen
    (SV.DRAG_CLICK_GUARD Sekunden) zählt nicht als Klick.
]]
SV.DRAG_ALPHA = 0.5
SV.DRAG_CLICK_GUARD = 0.1

function SV.DragStart(view, f)
    local line = f and f.line
    if not (view and view.opts and type(view.opts.onDrop) == "function" and type(line) == "table" and line.drag) then
        return false
    end
    local canDrag = view.opts.canDrag
    if type(canDrag) == "function" then
        local ok, allowed = pcall(canDrag, line)
        if not ok then Core.Error(view.owner, allowed, "canDrag") end
        if not ok or allowed == false then return false end
    end
    view.dragging = f
    if f.SetAlpha then f:SetAlpha(SV.DRAG_ALPHA) end
    GameTooltip:Hide()
    return true
end

-- Eintrag unter der Maus (sichtbar, nicht der gezogene) oder nil.
function SV.DropTarget(view, from)
    for _, other in ipairs(view and view.pools and view.pools.spell or {}) do
        if other ~= from and other.line and other.IsShown and other:IsShown() and other.IsMouseOver
            and other:IsMouseOver() then
            return other
        end
    end
    return nil
end

function SV.DragStop(view, f)
    local from = view and view.dragging
    if not from then return false end
    view.dragging = nil
    if from.SetAlpha then from:SetAlpha(1) end
    from.dropAt = GetTime and GetTime() or nil
    local target = SV.DropTarget(view, from)
    local ok, err = pcall(view.opts.onDrop, from.line, target and target.line or nil, from, target)
    if not ok then Core.Error(view.owner, err, "onDrop") end
    view:Refresh()
    return true
end

-- Eintrag wie Blizzards SpellBookItemTemplate: Symbol mit Rahmen, Name, zweite und dritte Zeile.
local function NewSpell(parent, view)
    local f = CreateFrame("Button", nil, parent)
    f:SetSize(220, CELL_H)
    f.Backplate = f:CreateTexture(nil, "BACKGROUND")
    f.Backplate:SetAtlas("spellbook-item-backplate", true)
    f.Backplate:SetPoint("CENTER", 5, -5)
    f.Backplate:SetAlpha(BACKPLATE_ALPHA)

    local icon = CreateFrame("Frame", nil, f)
    icon:SetSize(40, 40)
    icon:SetPoint("LEFT")
    f.IconFrame = icon
    f.TrainableShadow = icon:CreateTexture(nil, "BACKGROUND", nil, -1)
    f.TrainableShadow:SetAtlas("spellbook-item-needtrainer-shadow")
    f.TrainableShadow:SetSize(56, 56)
    f.TrainableShadow:SetPoint("CENTER")
    f.Icon = icon:CreateTexture(nil, "ARTWORK", nil, -1)
    f.Icon:SetSize(36, 36)
    f.Icon:SetPoint("CENTER")
    local mask = icon.CreateMaskTexture and icon:CreateMaskTexture()   -- runde Ecken wie Blizzards IconMask
    if mask and f.Icon.AddMaskTexture then
        mask:SetAtlas("spellbook-item-spellicon-mask")
        mask:SetAllPoints(f.Icon)
        f.Icon:AddMaskTexture(mask)
    end
    f.BorderShadow = icon:CreateTexture(nil, "ARTWORK", nil, 1)
    f.BorderShadow:SetAtlas("spellbook-item-iconframe-shadow")
    f.BorderShadow:SetPoint("TOPLEFT", -12, 3)
    f.BorderShadow:SetPoint("BOTTOMRIGHT", 2, -8)
    f.Border = icon:CreateTexture(nil, "OVERLAY", nil, 1)
    f.TrainableBackplate = icon:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.TrainableBackplate:SetAtlas("spellbook-item-needtrainer-iconframe-backplate")
    f.TrainableBackplate:SetAllPoints(f.Border)

    local text = CreateFrame("Frame", nil, f)
    text:SetPoint("LEFT", f, "LEFT", 50, -1)
    text:SetPoint("RIGHT", f, "RIGHT", 0, -1)
    text:SetHeight(1)
    f.TextContainer = text
    f.Name = text:CreateFontString(nil, "ARTWORK", "SystemFont_Large")
    f.Name:SetPoint("TOPLEFT")
    f.Name:SetPoint("TOPRIGHT")
    f.Name:SetJustifyH("LEFT")
    if f.Name.SetMaxLines then f.Name:SetMaxLines(2) end
    f.SubName = text:CreateFontString(nil, "ARTWORK", "SystemFont_Med1")
    f.SubName:SetPoint("TOPLEFT", f.Name, "BOTTOMLEFT", 0, -2)
    f.SubName:SetPoint("TOPRIGHT", f.Name, "BOTTOMRIGHT", 0, -2)
    f.SubName:SetJustifyH("LEFT")
    f.Detail = text:CreateFontString(nil, "ARTWORK", "SystemFont_Med1")
    f.Detail:SetPoint("TOPLEFT", f.SubName, "BOTTOMLEFT", 0, -2)
    f.Detail:SetPoint("TOPRIGHT", f.SubName, "BOTTOMRIGHT", 0, -2)
    f.Detail:SetJustifyH("LEFT")
    for _, fs in ipairs({ f.Name, f.SubName, f.Detail }) do Color(fs) end

    f:EnableMouse(true)
    if f.RegisterForClicks then f:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    f:SetScript("OnEnter", ShowSpellTip)
    f:SetScript("OnLeave", function(self)
        self.Backplate:SetAlpha(BACKPLATE_ALPHA)
        GameTooltip:Hide()
    end)
    -- Ziehen (nur Einträge mit line.drag und opts.onDrop): SV.DragStart/SV.DragStop
    if f.RegisterForDrag then f:RegisterForDrag("LeftButton") end
    f:SetScript("OnDragStart", function(self) SV.DragStart(view, self) end)
    f:SetScript("OnDragStop", function(self) SV.DragStop(view, self) end)
    -- Buch zugeschlagen, während gezogen wird: kein OnDragStop mehr – Ziehen ohne Ablegen beenden
    f:SetScript("OnHide", function(self)
        if view.dragging == self then
            view.dragging = nil
            if self.SetAlpha then self:SetAlpha(1) end
        end
    end)
    -- Klick: nur der Rückruf des Moduls (kein Zauber, nichts Geschütztes); direkt nach einem Ziehen keiner
    f:SetScript("OnClick", function(self, button)
        local onClick = view.opts.onClick
        if not (onClick and self.line) then return end
        if self.dropAt and GetTime and GetTime() - self.dropAt < SV.DRAG_CLICK_GUARD then
            self.dropAt = nil
            return
        end
        local ok, err = pcall(onClick, self.line, button or "LeftButton", self)
        if not ok then Core.Error(view.owner, err, "onClick") end
    end)
    return f
end

-- Höhe eines Textes, wie die Seite ihn gerade umbricht; ohne Auskunft des Spiels die Höhe einer Zeile.
local function TextHeightOf(fs, fallback)
    local height = fs.GetStringHeight and Core.Num((fs:GetStringHeight()))
    return (height and height > 0) and height or fallback
end

-- style: "known" (Standard, wie ein gelernter Zauber), "trainable" (Rahmen „beim Lehrer erlernbar“),
-- "future" (grau wie „kommt später“). desaturate überschreibt das Grau des Symbols, readable = true das Grau des Texts.
-- Schrift auf ihre vorab gerechneten Zeilen festlegen: Zeilengrenze und Höhe (nichts ragt über den Eintrag).
local function FixLines(fs, lines, lineH)
    lines = math.max(1, lines)
    if fs.SetMaxLines then fs:SetMaxLines(lines) end
    if fs.SetHeight then fs:SetHeight(lines * lineH) end
end

-- fit: die vorab gerechneten Zeilen (SV.EntryText, aus SV.Layout); fehlt es, rechnet FillSpell selbst.
local function FillSpell(f, line, fit)
    local style = line.style
    local trainable, future = style == "trainable", style == "future"
    f.line = line
    f.Icon:SetTexture(Plain(line.icon) or QUESTION_ICON)
    fit = type(fit) == "table" and fit or SV.EntryText(line, Core.Num(f:GetWidth()) or 220)
    f.fit = fit
    local hasSub, hasDetail = fit.sub.lines > 0, fit.detail.lines > 0
    f.Name:SetText(fit.name.text)
    f.SubName:SetText(hasSub and fit.sub.text or "")
    f.SubName:SetShown(hasSub)
    f.Detail:SetText(hasDetail and fit.detail.text or "")
    f.Detail:SetShown(hasDetail)
    -- Die dritte Zeile hängt unter der zweiten, fehlt die zweite, direkt unter dem Namen (Spieltest 21.11.2026, Bild 3:
    -- sonst blieb eine leere Zeile stehen, der Text ragte eine Zeile über den Eintrag – auf „Was kommt wann“ stand
    -- „Kosten: noch nicht gesehen“ direkt über „Stufe 14“, und SV.EntryText hatte die Zeile nicht gezählt)
    local above = hasSub and f.SubName or f.Name
    f.Detail:ClearAllPoints()
    f.Detail:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -SV.LINE_GAP)
    f.Detail:SetPoint("TOPRIGHT", above, "BOTTOMRIGHT", 0, -SV.LINE_GAP)
    SetBorder(f, future and "inactive" or "active")
    f.TrainableShadow:SetShown(trainable)
    f.TrainableBackplate:SetShown(trainable)
    local desaturate = line.desaturate
    if type(desaturate) ~= "boolean" then desaturate = future end
    f.Icon:SetDesaturated(desaturate)
    local alpha = future and UNLEARNED_ALPHA or 1
    f.Icon:SetAlpha(alpha)
    -- line.readable = true: der Text bleibt in voller Buchfarbe, auch wenn Symbol und Rahmen „kommt später“ zeigen
    -- (Spieltest 21.11.2026, Bild 4: „statt grauer text der fähigkeiten text? macht mehr sinn“)
    local textAlpha = line.readable == true and 1 or alpha
    for _, fs in ipairs({ f.Name, f.SubName, f.Detail }) do fs:SetAlpha(textAlpha) end
    -- Text endet vor der nächsten Spalte bzw. vor der Knopfspalte
    local inset = type(line.buttons) == "table" and -(SV.BUTTON_W + 2) or -SV.TEXT_GAP
    f.TextContainer:SetPoint("RIGHT", f, "RIGHT", inset, -1)
    -- Text senkrecht mittig wie Blizzards TextContainer; jede Schrift so hoch wie ihre Zeilen (Befund 3: vorher
    -- zählte die Höhe, die das Spiel beim Zeichnen meldete – zu früh gefragt, war sie zu klein, und drei Teile mit je
    -- zwei Zeilen liefen über den Eintrag hinaus)
    FixLines(f.Name, fit.name.lines, SV.NAME_LINE_H)
    FixLines(f.SubName, fit.sub.lines, SV.SMALL_LINE_H)
    FixLines(f.Detail, fit.detail.lines, SV.SMALL_LINE_H)
    f.TextContainer:SetHeight(math.min(fit.height, Core.Num(f:GetHeight()) or CELL_H))
    f.caps = { name = fit.name.lines, sub = fit.sub.lines, detail = fit.detail.lines }
end

local function NewText(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.Text = f:CreateFontString(nil, "ARTWORK", "SystemFont_Med1")
    f.Text:SetPoint("TOPLEFT", 4, -4)
    f.Text:SetPoint("BOTTOMRIGHT", -4, 4)
    f.Text:SetJustifyH("LEFT")
    f.Text:SetJustifyV("TOP")
    if f.Text.SetWordWrap then f.Text:SetWordWrap(true) end
    Color(f.Text)
    f:SetScript("OnEnter", function(self)
        if self.full then Core.ShowTip(self, self.full) end
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return f
end

-- Absatz auf seine Zeile begrenzen: so viele Zeilen, wie in die Höhe passen; gekürzt zeigt der Tooltip alles.
local function FillText(f, text, h)
    h = Core.Num(h) or TEXT_H
    local maxLines = math.max(1, math.floor((h - 8) / SV.TEXT_LINE_H))
    -- gekürzt an einer Wortgrenze (Befund 3), nicht erst vom Spiel mitten im Wort
    local lines, wrapped = SV.Wrap(text, (Core.Num(f:GetWidth()) or PAGE_W) - 8, maxLines, SV.CHAR_W)
    f.Text:SetText(wrapped and table.concat(lines, "\n") or text)
    if f.Text.SetMaxLines then f.Text:SetMaxLines(maxLines) end
    local cut = wrapped or TextHeightOf(f.Text, 0) > h - 8 or SV.TextHeight(text, Core.Num(f:GetWidth())) > h
    f.full = (cut and text ~= "") and text or nil
    if f.EnableMouse then f:EnableMouse(f.full ~= nil) end
end

---------------------------------------------------------------------------
-- Knöpfe (EC-35): Knopfspalte eines Eintrags, Zeile mit Knopf
---------------------------------------------------------------------------

-- Klick auf einen Knopf: nur der Rückruf des Moduls, danach neu zeichnen (das Kästchen zeigt den wahren Stand).
local function Press(self)
    local view, line = self.view, self.line
    if not (view and line) then return end
    Core.PlaySound("IG_MAINMENU_OPTION_CHECKBOX_ON")
    local onButton = view.opts.onButton
    if onButton then
        local ok, err = pcall(onButton, line, self.key, self)
        if not ok then Core.Error(view.owner, err, "onButton") end
    end
    view:Refresh()
end

local function ButtonTip(self)
    local spec, line = self.spec, self.line
    if not spec then return end
    local title = Plain(spec.title) or (line and (Plain(line.title) or Plain(line.name) or Plain(line.left))) or ""
    Core.ShowTip(self, title, Plain(spec.tip))
end

local function Wire(button, view)
    button.view = view
    if button.SetMotionScriptsWhileDisabled then button:SetMotionScriptsWhileDisabled(true) end
    button:SetScript("OnClick", Press)
    button:SetScript("OnEnter", ButtonTip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return button
end

-- Pfeil bzw. Symbol-Knopf: spec.arrow ("Up"/"Down"/"Left"/"Right") oder spec.texture (eine Datei auf „-Up“ bekommt
-- „-Down“ und „-Disabled“ dazu).
local function SetArrow(button, spec)
    local arrow = Plain(spec.arrow)
    local normal = Plain(spec.texture) or (type(arrow) == "string" and ARROW:format(arrow, "Up")) or nil
    if type(normal) ~= "string" or button.normal == normal then return end
    button.normal = normal
    button:SetNormalTexture(normal)
    local base = normal:match("^(.*)%-Up$")
    button:SetPushedTexture(Plain(spec.pushed) or (base and base .. "-Down") or normal)
    button:SetDisabledTexture(Plain(spec.disabledTexture) or (base and base .. "-Disabled") or normal)
end

local function NewArrow(parent, view)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(16, 16)
    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    return Wire(button, view)
end

-- Knopfspalte eines Eintrags: höchstens drei Knöpfe untereinander (oben, Mitte, unten; spec.place wählt selbst).
local function NewButtons(parent, view)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(SV.BUTTON_W, CELL_H)
    holder.checks, holder.arrows, holder.byKey = {}, {}, {}
    holder.view = view
    return holder
end

local PLACES = { [1] = { "CENTER" }, [2] = { "TOP", "BOTTOM" }, [3] = { "TOP", "CENTER", "BOTTOM" } }
local OFFSET = { TOP = -1, CENTER = 0, BOTTOM = 1 }

local function FillButtons(holder, line, height)
    holder.line = line
    holder:SetHeight(height or CELL_H)
    local specs = {}
    for _, spec in ipairs(line.buttons) do
        if type(spec) == "table" and #specs < SV.MAX_BUTTONS then specs[#specs + 1] = spec end
    end
    local usedChecks, usedArrows = 0, 0
    holder.byKey = {}
    for index, spec in ipairs(specs) do
        local button
        if spec.check ~= nil then
            usedChecks = usedChecks + 1
            button = holder.checks[usedChecks]
            if not button then
                button = Wire(Core.CreateCheck(holder, SV.BUTTON_W), holder.view)
                holder.checks[usedChecks] = button
            end
            button:SetChecked(Plain(spec.check) == true)
        else
            usedArrows = usedArrows + 1
            button = holder.arrows[usedArrows]
            if not button then
                button = NewArrow(holder, holder.view)
                holder.arrows[usedArrows] = button
            end
            SetArrow(button, spec)
        end
        local place = Plain(spec.place)
        if not OFFSET[place] then place = PLACES[#specs][index] end
        button:ClearAllPoints()
        button:SetPoint(place, holder, place, 0, OFFSET[place])
        button.line, button.spec, button.key = line, spec, spec.key
        button:SetEnabled(not spec.disabled)
        button:Show()
        if spec.key ~= nil then holder.byKey[spec.key] = button end
    end
    for i = usedChecks + 1, #holder.checks do holder.checks[i]:Hide() end
    for i = usedArrows + 1, #holder.arrows do holder.arrows[i]:Hide() end
end

-- Zeile mit Knopf (kind = "action"): Text oben (left), Knopf darunter (button = Beschriftung, tip, disabled, key).
local function NewAction(parent, view)
    local f = CreateFrame("Frame", nil, parent)
    f.Text = f:CreateFontString(nil, "ARTWORK", "SystemFont_Med1")
    f.Text:SetPoint("TOPLEFT", 4, -4)
    f.Text:SetPoint("TOPRIGHT", -4, -4)
    f.Text:SetJustifyH("LEFT")
    if f.Text.SetWordWrap then f.Text:SetWordWrap(true) end
    if f.Text.SetMaxLines then f.Text:SetMaxLines(2) end
    Color(f.Text)
    local ok, button = pcall(CreateFrame, "Button", nil, f, "UIPanelButtonTemplate")
    if not (ok and button) then
        button = CreateFrame("Button", nil, f)
        button:SetNormalFontObject("GameFontNormal")
        button:SetHighlightFontObject("GameFontHighlight")
        button:SetDisabledFontObject("GameFontDisable")
    end
    button:SetHeight(SV.ACTION_BUTTON_H)
    button:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 4, 2)
    f.Button = Wire(button, view)
    -- zweiter Knopf rechts daneben (line.second = { key, button, tip, disabled }), z. B. „Andere wählen“ und „Erstellen“
    local okSecond, second = pcall(CreateFrame, "Button", nil, f, "UIPanelButtonTemplate")
    if not (okSecond and second) then
        second = CreateFrame("Button", nil, f)
        second:SetNormalFontObject("GameFontNormal")
        second:SetHighlightFontObject("GameFontHighlight")
        second:SetDisabledFontObject("GameFontDisable")
    end
    second:SetHeight(SV.ACTION_BUTTON_H)
    second:SetPoint("LEFT", button, "RIGHT", 6, 0)
    second:Hide()
    f.Second = Wire(second, view)
    return f
end

SV.ACTION_BUTTON_W, SV.ACTION_PAIR_W = 150, 100   -- Mindestbreite eines Knopfs allein bzw. zu zweit

local function FillActionButton(button, line, key, label, tip, disabled, minWidth)
    button.line, button.key = line, key
    button.spec = { title = Plain(label), tip = tip }
    button:SetText(Plain(label) or "")
    local width = button.GetTextWidth and Core.Num((button:GetTextWidth())) or 0
    button:SetWidth(math.max(minWidth, (width or 0) + 30))
    button:SetEnabled(not disabled)
end

local function FillAction(f, line)
    f.line = line
    f.Text:SetText(Plain(line.left) or Plain(line.text) or "")
    local second = type(line.second) == "table" and line.second or nil
    local minWidth = second and SV.ACTION_PAIR_W or SV.ACTION_BUTTON_W
    FillActionButton(f.Button, line, line.key, line.button, line.tip, line.disabled, minWidth)
    if f.Second then
        if second then
            FillActionButton(f.Second, line, second.key, second.button, second.tip, second.disabled, minWidth)
            f.Second:Show()
        else
            f.Second.key = nil
            f.Second:Hide()
        end
    end
end

local BUILD = { header = NewHeader, spell = NewSpell, text = NewText, action = NewAction, buttons = NewButtons }

-- Seitensteuerung, falls Blizzards PagingControlsHorizontalTemplate fehlt: dieselben Felder und Methoden
-- (PageText, PrevPageButton, NextPageButton, SetMaxPages, SetCurrentPage, meldet OnPageChanged an den Elternrahmen).
local function NewPaging(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetSize(140, 32)
    p.currentPage, p.maxPages = 1, 1
    local function Arrow(dir, tip)
        local b = CreateFrame("Button", nil, p)
        b:SetSize(32, 32)
        b:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. dir .. "Page-Up")
        b:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. dir .. "Page-Down")
        b:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. dir .. "Page-Disabled")
        b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        b:SetScript("OnEnter", function(self) if tip then Core.ShowTip(self, tip) end end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end
    p.NextPageButton = Arrow("Next", _G.NEXT)
    p.NextPageButton:SetPoint("RIGHT", p, "RIGHT", 0, 0)
    p.PrevPageButton = Arrow("Prev", _G.PREV)
    p.PrevPageButton:SetPoint("RIGHT", p.NextPageButton, "LEFT", -4, 0)
    p.PageText = p:CreateFontString(nil, "ARTWORK", "SystemFont_Med3")
    p.PageText:SetPoint("RIGHT", p.PrevPageButton, "LEFT", -6, 0)
    function p:UpdateControls()
        self.PrevPageButton:SetEnabled(self.currentPage > 1)
        self.NextPageButton:SetEnabled(self.currentPage < self.maxPages)
        local fmt = type(_G.PAGE_NUMBER_WITH_MAX) == "string" and _G.PAGE_NUMBER_WITH_MAX or "%d/%d"
        self.PageText:SetText(fmt:format(self.currentPage, self.maxPages))
    end
    function p:GetCurrentPage() return self.currentPage end
    function p:GetMaxPages() return self.maxPages end
    function p:SetMaxPages(n)
        self.maxPages = math.max(tonumber(n) or 1, 1)
        if self.maxPages < self.currentPage then self:SetCurrentPage(self.maxPages) else self:UpdateControls() end
    end
    function p:SetCurrentPage(page)
        page = math.max(1, math.min(self.maxPages, page))
        if page == self.currentPage then return false end
        self.currentPage = page
        self:UpdateControls()
        local owner = self:GetParent()
        if owner and owner.OnPageChanged then owner:OnPageChanged() end
        return true
    end
    p.PrevPageButton:SetScript("OnClick", function() p:SetCurrentPage(p.currentPage - 1) end)
    p.NextPageButton:SetScript("OnClick", function() p:SetCurrentPage(p.currentPage + 1) end)
    p:UpdateControls()
    return p
end

---------------------------------------------------------------------------
-- Ansichten
---------------------------------------------------------------------------

local views, byKey = {}, {}
local View = {}
local ViewMT = { __index = View }

function SV.Get(key) return byKey[key] end
function SV.Views() return views end

-- Die gerade aufgeschlagene eigene Ansicht (oder nil).
function SV.Active()
    for _, v in ipairs(views) do
        if v:IsShown() then return v end
    end
    return nil
end

-- Zurück zu Blizzards Zauberliste: schließt jede eigene Ansicht.
function SV.CloseAll()
    for _, v in ipairs(views) do
        if v:IsShown() then v:Hide() end
    end
end

local function UpdateTabs()
    for _, v in ipairs(views) do v:UpdateTab() end
end

local function RenderAll()
    for _, v in ipairs(views) do v:Render() end
end

-- Zauberbuch bzw. Blizzards Fenster geht zu (auch beim Wechsel auf „Talente“): jede eigene Ansicht zuschlagen. Das
-- Zauberbuch öffnet so immer auf Blizzards eigener Zauberliste, eine eigene Seite nur auf Klick (Spielbefund des
-- Nutzers vom 19.11.2026: „Zauberbuch öffnen landet direkt bei "Deine Rotation" anstatt auf dem original“; für alle
-- Ansichten, auch ezMerchants „Was kommt wann“ – Antwort des Nutzers vom 20.11.2026: „Ja, auch ezMerchant“). Nur die
-- eigenen Rahmen, nichts an Blizzards.
local function CloseOnHide()
    SV.CloseAll()
    UpdateTabs()
end
SV.CloseOnHide = CloseOnHide

-- Einmal für alle Ansichten: Zauberbuch auf/zu, Blizzards Reiter und Suche, verkleinertes Buch.
local hookedBook
local function HookBook(book)
    if hookedBook == book then return end
    hookedBook = book
    book:HookScript("OnShow", UpdateTabs)
    book:HookScript("OnHide", CloseOnHide)
    PlayerSpellsFrame:HookScript("OnShow", UpdateTabs)
    PlayerSpellsFrame:HookScript("OnHide", CloseOnHide)
    -- Kategorie-Reiter: Blizzards Knopf ruft CategoryTabSystem:SetTab(tabID, isUserAction) – nur ein Klick des Spielers
    -- schlägt zu. (SpellBookFrame:SetTab ruft Blizzard auch selbst beim ersten Öffnen; das darf die Seite nicht schließen.)
    local tabs = book.CategoryTabSystem
    if type(tabs) == "table" and type(tabs.SetTab) == "function" then
        hooksecurefunc(tabs, "SetTab", function(_, _, isUserAction) if isUserAction then SV.CloseAll() end end)
    end
    -- Sprung zu einem Zauber oder einer Kategorie (Suche, Glyphen, Gamepad-Schultertasten): ebenfalls zurück.
    for _, method in ipairs({ "GoToSpell", "TrySetCategory", "SelectNextTab" }) do
        if type(book[method]) == "function" then hooksecurefunc(book, method, SV.CloseAll) end
    end
    if type(book.SetMinimized) == "function" then hooksecurefunc(book, "SetMinimized", RenderAll) end
    local search = book.SearchBox
    if type(search) == "table" and search.HookScript then search:HookScript("OnEditFocusGained", SV.CloseAll) end
end

function View:Enabled()
    local enabled = self.opts.enabled
    if enabled == nil then return true end
    return enabled() and true or false
end

function View:IsShown() return self.frame ~= nil and self.frame:IsShown() end

function View:Minimized() return SV.Minimized() end

-- Blizzards Buchseiten unter der Ansicht nachzeichnen: dieselbe Textur genau über der Seite (der Rahmen schneidet
-- auf seinen Bereich zu, Kategorie-Reiter und Suche oben bleiben frei).
function View:SyncArt()
    local frame = self.frame
    if not frame then return end
    local book = Book()
    local minimized = SV.Minimized()
    for key, tex in pairs(frame.art) do
        local source = book and book[key]
        local atlas = type(source) == "table" and source.GetAtlas and source:GetAtlas() or PAGE_ART[key]
        tex:SetAtlas(atlas)
        local shown
        if type(source) == "table" and source.IsShown then
            shown = source:IsShown()
        elseif key == "BookBGHalved" then
            shown = minimized
        else
            shown = not minimized
        end
        tex:SetShown(shown == true)
    end
    frame.pages[2]:SetShown(not minimized)
end

function View:Acquire(kind, used, parent)
    local pool = self.pools[kind]
    used[kind] = (used[kind] or 0) + 1
    local f = pool[used[kind]]
    if not f then
        f = BUILD[kind](parent, self)
        pool[used[kind]] = f
    end
    if f:GetParent() ~= parent and f.SetParent then f:SetParent(parent) end
    return f
end

-- Zeilen holen, auf Seiten verteilen und die aktuelle (Doppel-)Seite zeichnen. Nur, solange die Ansicht sichtbar ist.
function View:Render()
    local frame = self.frame
    if not (frame and frame:IsVisible()) then return end
    self:SyncArt()
    local ok, lines = pcall(self.opts.lines)
    if not ok then
        Core.Error(self.owner, lines, "lines")
        lines = nil
    end
    if type(lines) ~= "table" then lines = {} end
    local perSpread = SV.Minimized() and 1 or 2
    local pageW, pageH = PageSize()
    local footer = self:Footer()
    if frame.Footer then
        frame.Footer:SetText(footer or "")
        frame.Footer:SetShown(footer ~= nil)
    end
    if footer then pageH = pageH - SV.FOOTER_H end
    local native = self.opts.buttons == true
    local pages = SV.Layout(lines, pageW, pageH)
    local spreads = math.max(1, math.ceil(#pages / perSpread))
    self.page = math.max(1, math.min(spreads, self.page or 1))
    if frame.Paging then
        self.syncing = true
        frame.Paging:SetMaxPages(spreads)
        frame.Paging:SetCurrentPage(self.page)
        self.syncing = false
    end
    local used = {}
    for side = 1, perSpread do
        local target = frame.pages[side]
        for _, cell in ipairs(pages[(self.page - 1) * perSpread + side] or {}) do
            local line = cell.line
            local kind = line.kind
            if not (kind == "header" or kind == "spell" or kind == "text" or (kind == "action" and native)) then
                kind = "text"
            end
            local f = self:Acquire(kind, used, target)
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", target, "TOPLEFT", cell.x, -cell.y)
            f:SetSize(cell.w, cell.h)
            if kind == "header" then
                local head = SV.HeaderText(line, cell.w)
                f.Text:SetText(head.left)
                f.Sum:SetText(head.right)
                -- Die Überschrift endet vor dem Text rechts (eigene Kopie der Vorlage, Blizzards Rahmen unberührt)
                f.Text:ClearAllPoints()
                f.Text:SetPoint("LEFT", f, "LEFT", -8, 14)
                f.Text:SetPoint("RIGHT", f, "RIGHT", -60 - (head.rightW > 0 and head.rightW + 8 or 0), 14)
                f.head = head
            elseif kind == "spell" then
                FillSpell(f, line, cell.text)
                if native and type(line.buttons) == "table" then
                    local holder = self:Acquire("buttons", used, target)
                    holder:ClearAllPoints()
                    holder:SetPoint("TOPRIGHT", target, "TOPLEFT", cell.x + cell.w, -cell.y)
                    holder:SetFrameLevel((f:GetFrameLevel() or 1) + 6)
                    FillButtons(holder, line, cell.h)
                    holder:Show()
                end
            elseif kind == "action" then
                FillAction(f, line)
            else
                FillText(f, Plain(line.text) or Plain(line.left) or "", cell.h)
            end
            f:Show()
        end
    end
    for kind, pool in pairs(self.pools) do
        for i = (used[kind] or 0) + 1, #pool do pool[i]:Hide() end
    end
    self.lines, self.pages, self.spreads = lines, pages, spreads
end

-- Text der Fußzeile (opts.footer: Text oder fn() → Text), nil ohne.
function View:Footer()
    local footer = self.opts.footer
    if type(footer) == "function" then
        local ok, text = pcall(footer)
        if not ok then
            Core.Error(self.owner, text, "footer")
            text = nil
        end
        footer = text
    end
    footer = Plain(footer)
    return HasText(footer) and tostring(footer) or nil
end

-- Die sichtbaren Knöpfe der Seite (nur mit opts.buttons): { steps = { Knopfspalte … }, actions = { Knopf … } }.
function View:Widgets()
    local widgets = { steps = {}, actions = {} }
    for _, holder in ipairs(self.pools.buttons or {}) do
        if holder:IsShown() then widgets.steps[#widgets.steps + 1] = holder end
    end
    for _, f in ipairs(self.pools.action or {}) do
        if f:IsShown() then
            widgets.actions[#widgets.actions + 1] = f.Button
            if f.Second and f.Second:IsShown() then widgets.actions[#widgets.actions + 1] = f.Second end
        end
    end
    return widgets
end

-- Sichtbarer Knopf einer Zeile mit Knopf (line.key), z. B. als Ziel einer Erklärblase. → Knopf oder nil
function View:ActionButton(key)
    for _, button in ipairs(self:Widgets().actions) do
        if button.key == key then return button end
    end
    return nil
end

-- Blättern (Seite = Doppelseite, im verkleinerten Buch eine Seite).
function View:SetPage(page)
    if not self.spreads then return end
    page = math.max(1, math.min(self.spreads, tonumber(page) or 1))
    if page == self.page then return end
    self.page = page
    Core.PlaySound("IG_ABILITY_PAGE_TURN")
    self:Render()
end

-- Inhalt, Seiten und Reiter neu (nach neuen Daten des Moduls).
function View:Refresh()
    self:Render()
    self:UpdateTab()
end

-- Reiter: nur bei offenem Zauberbuch und eingeschalteter Ansicht; Zahl unten rechts, aktiv solange aufgeschlagen.
function View:UpdateTab()
    local tab = self.tab
    if not tab then return end
    local enabled = self:Enabled()
    if not enabled and self.frame:IsShown() then self.frame:Hide() end
    local shown = enabled and BookShown()
    tab:SetShown(shown)
    if not shown then return end
    local count = self.opts.count and Plain(self.opts.count())
    if type(count) == "number" then count = count > 0 and tostring(count) or "" end
    tab.Count:SetText(type(count) == "string" and count or "")
    if tab.SetChecked then tab:SetChecked(self:IsShown()) end
end

-- Aufschlagen (schließt jede andere eigene Ansicht), immer auf der ersten Seite. → true, wenn aufgeschlagen
function View:Show()
    if not (self.frame and self:Enabled()) then return false end
    for _, other in ipairs(views) do
        if other ~= self and other:IsShown() then other:Hide() end
    end
    self.page = 1
    if self.frame:IsShown() then self:Render() else self.frame:Show() end   -- OnShow zeichnet den Inhalt
    self:UpdateTab()
    return true
end

-- Zuschlagen: zurück zu Blizzards Zauberliste.
function View:Hide()
    if not self.frame then return end
    self.frame:Hide()
    self:UpdateTab()
end

function View:Toggle()
    if self:IsShown() then self:Hide() else self:Show() end
end

function View:CreateFrames(book)
    local list = book.PagedSpellsFrame or book
    local opts = self.opts
    local frame = CreateFrame("Frame", opts.frameName, book)
    frame:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -TOP_GAP)
    frame:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", 0, 0)
    frame:SetFrameLevel((list:GetFrameLevel() or 100) + 30)
    frame:EnableMouse(true)                        -- Klicks erreichen die abgedeckten Zauber nicht
    if frame.EnableMouseWheel then frame:EnableMouseWheel(true) end
    if frame.SetClipsChildren then frame:SetClipsChildren(true) end
    frame:Hide()
    frame.view = self

    local art = CreateFrame("Frame", nil, frame)
    art:SetAllPoints(book)
    frame.art = {}
    for key in pairs(PAGE_ART) do
        local tex = art:CreateTexture(nil, "BACKGROUND")
        if type(book[key]) == "table" then tex:SetAllPoints(book[key]) else tex:SetAllPoints(art) end
        frame.art[key] = tex
    end

    frame.pages = {}
    local paged = book.PagedSpellsFrame
    local sides = paged and { paged.View1, paged.View2 } or {}
    for side = 1, 2 do
        local page = CreateFrame("Frame", nil, frame)
        if type(sides[side]) == "table" then
            page:SetAllPoints(sides[side])
        elseif side == 1 then
            page:SetSize(PAGE_W, PAGE_H)
            page:SetPoint("TOPLEFT", frame, "TOPLEFT", PAGE_X1, PAGE_Y + TOP_GAP)
        else
            page:SetSize(PAGE_W, PAGE_H)
            page:SetPoint("TOPRIGHT", frame, "TOPRIGHT", PAGE_X2, PAGE_Y + TOP_GAP)
        end
        frame.pages[side] = page
    end

    -- Blättern: Blizzards Seitensteuerung an derselben Stelle wie im Zauberbuch, dazu das Mausrad
    local ok, paging = pcall(CreateFrame, "Frame", nil, frame, "PagingControlsHorizontalTemplate")
    if not (ok and paging and type(paging.NextPageButton) == "table" and type(paging.PrevPageButton) == "table") then
        paging = NewPaging(frame)
        frame.ownPaging = true
    end
    paging:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -75, 40)
    if type(paging.PageText) == "table" then
        paging.PageText:SetFontObject("SystemFont_Med3")
        paging.PageText:SetTextColor(BookColor())
    end
    if SOUNDKIT and SOUNDKIT.IG_ABILITY_PAGE_TURN then
        paging.prevPageSound, paging.nextPageSound = SOUNDKIT.IG_ABILITY_PAGE_TURN, SOUNDKIT.IG_ABILITY_PAGE_TURN
    end
    frame.Paging = paging
    -- Fußzeile (opts.footer) unter der ersten Buchseite, z. B. die Quelle der Daten
    local footer = frame.pages[1]:CreateFontString(nil, "ARTWORK", "SystemFont_Small")
    footer:SetPoint("BOTTOMLEFT", frame.pages[1], "BOTTOMLEFT", 4, 2)
    footer:SetPoint("BOTTOMRIGHT", frame.pages[1], "BOTTOMRIGHT", -4, 2)
    footer:SetJustifyH("LEFT")
    if footer.SetWordWrap then footer:SetWordWrap(true) end
    if footer.SetMaxLines then footer:SetMaxLines(2) end
    Color(footer)
    footer:Hide()
    frame.Footer = footer
    local view = self
    -- Blizzards Seitensteuerung meldet den Seitenwechsel an ihren Elternrahmen (PagingControlsMixin:SetCurrentPage).
    function frame:OnPageChanged()
        if view.syncing or not self.Paging then return end
        view.page = self.Paging:GetCurrentPage()
        view:Render()
    end
    frame:SetScript("OnMouseWheel", function(_, delta) view:SetPage((view.page or 1) + (delta > 0 and -1 or 1)) end)
    frame:SetScript("OnShow", function() view:Render() end)
    self.frame = frame
end

function View:CreateTab()
    local opts = self.opts
    -- im Seitenreiter-Stapel des Zauberbuchs (T16-4): sichtbare Reiter aller Module lückenlos nach order
    local tab = Core.CreateSideTab(PlayerSpellsFrame, { key = self.key, order = self.order, anchor = PlayerSpellsFrame,
        owner = self.owner })
    tab.Icon:SetTexture(opts.icon or TAB_ICON)
    local view = self
    tab:SetScript("OnClick", Core.SideTabClick(function() view:Toggle() end))
    tab:SetScript("OnEnter", function(btn)
        local title, tip = opts.title, opts.tip
        if type(title) == "function" then title = title() end
        if type(tip) == "function" then tip = tip() end
        Core.ShowTip(btn, Plain(title) or "", Plain(tip))
    end)
    tab:Hide()
    self.tab = tab
end

-- Bauen, sobald Blizzards Zauberbuch geladen ist. Zu: das Buch öffnet auf Blizzards Liste (kein „remember“ mehr).
function View:Build()
    local book = Book()
    if self.frame or not (PlayerSpellsFrame and book) then return end
    HookBook(book)
    self:CreateFrames(book)
    self:CreateTab()
    self:UpdateTab()
end

--[[
    Core.NewSpellbookView(opts) → Ansicht. opts:
      key        eindeutiger Name ("ezMerchant.upcoming"), Pflicht
      lines      fn() → { Zeile … }, Pflicht (Zeilen siehe docs/ezcore.md)
      icon       Symbol des Reiters; order Reihenfolge-Zahl im Seitenreiter-Stapel (ezMerchant 10, ezMacro 20,
                 ezCombat 30, ezHeal 40); tabY alter Wunschplatz (−70, −114 …), gilt ohne order als Zahl
      title, tip Tooltip des Reiters (Text oder fn), count fn() → Zahl/Text unten rechts am Reiter
      onClick    fn(zeile, maustaste, eintrag) bei Klick auf einen Zauber-Eintrag
      buttons    true: ezCore zeichnet line.buttons (bis zu drei: { key, check | arrow | texture, title, tip, disabled,
                 place }) und Zeilen kind = "action" ({ left, button, tip, disabled, key, height }) selbst
      onButton   fn(zeile, knopfSchlüssel, knopf) bei Klick auf einen Knopf; danach zeichnet die Seite neu
      footer     Text oder fn() → Text der Fußzeile (z. B. „Quelle: …“), nil = keine
      enabled    fn() → bool (aus: Reiter und Ansicht weg). Beim Schließen des Zauberbuchs (auch Wechsel auf „Talente“)
                 schlägt ezCore jede Ansicht zu; gemerkt wird nichts (seit 20.11.2026, vorher opts.remember)
      owner      Modulname für Fehler (Standard key), frameName Name des Rahmens (für /fstack)
]]
function Core.NewSpellbookView(opts)
    assert(type(opts) == "table" and type(opts.key) == "string" and type(opts.lines) == "function",
        "Core.NewSpellbookView: key und lines fehlen")
    if byKey[opts.key] then return byKey[opts.key] end
    local view = setmetatable({ opts = opts, key = opts.key, owner = opts.owner or opts.key, page = 1,
        pools = { header = {}, spell = {}, text = {}, action = {}, buttons = {} } }, ViewMT)
    view.tabY = SV.ClaimTab(opts.key, opts.tabY)
    view.order = tonumber(opts.order) or SV.OrderFromY(opts.tabY)
    views[#views + 1] = view
    byKey[opts.key] = view
    Core.WhenAddOnLoaded("Blizzard_PlayerSpells", function() view:Build() end, view.owner)
    return view
end
