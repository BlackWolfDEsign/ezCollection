local ADDON, ns = ...
local Core = ezCore

--[[
    Blizzards Fenster „Klick-Zauber“ (ClickBindingFrame) dockt rechts am Zauberbuch an und wandert mit (Entscheidung des
    Nutzers vom 21.11.2026: „erstens, andocken, wandert mit, an der rechten seite“; wo das Zauberbuch steht, „spielt keine
    rolle“). Schalter „dockSpellbook“ (ab Werk an).

    Blizzards eigene Anordnung (Gethe/wow-ui-source, Zweig forever, Blizzard_ClickBindingUI.lua): ClickBindingFrame ist
    ein UIPanel mit area „left“, pushable 2; beim Zeigen öffnet es selbst das Zauberbuch (SetFocusedFrame), das
    verkleinerte Zauberbuch ist ebenfalls „left“ (Blizzard_PlayerSpellsFrame.lua, SetTabMinimized) – Blizzard stellt
    die Klick-Belegung also links neben das Zauberbuch, und verschiebt man das Zauberbuch (ezCores „Blizzard-Fenster
    verschieben“), bleibt sie stehen.

    So geht es (Leitlinie 5, taint-sicher):
      - Sind beide Fenster offen, hängt ClickBindingFrame mit seiner linken oberen Ecke an der rechten oberen Ecke von
        PlayerSpellsFrame – rechts neben dem Seitenreiter-Stapel (ezCore, Core.SIDETAB_SIZE, mit der Größe des
        Zauberbuchs umgerechnet) –
        und wandert damit von selbst mit (ziehen, Blizzards Fensterverwaltung, gemerkte Lage).
      - Reicht rechts der Platz nicht (Core.DockRoom), weicht es nach links aus; reicht er auf keiner Seite, bleibt es
        bei Blizzards Lage.
      - Nur außerhalb des Kampfes (sonst gleich danach, ns.AfterCombat); nichts wird in Blizzards Tabellen geschrieben
        (UIPanelWindows bleibt), Blizzards Fensterverwaltung wird nie selbst aufgerufen – nur hooksecurefunc und
        HookScript; ordnet Blizzard neu an (UpdateUIPanelPositions, FRAME_MOVED), dockt ezHeal einen Frame später neu.
      - Läuft ein Addon, das Blizzards Fenster selbst verschiebt (ns.OtherFor("moveFrames"): BlizzMove, MoveAny,
        Tweaks Forever, Forever++ – Liste in docs/fremd-addons.md; Leitlinie 9), hält sich ezHeal zurück; der Schalter
        nennt es (feature = "moveFrames").
      - Ausgang ist Blizzards eigene Lage: vor dem Andocken merkt sich ezHeal Blizzards Anker; schließt das Zauberbuch
        (z. B. Wechsel zu den Makros über Blizzards Portrait-Knopf), schließt die Klick-Belegung oder geht der Schalter
        aus, setzt ezHeal genau diese Anker zurück – nur, solange noch ezHeals Anker gilt.
]]

local D = {}
ns.SpellbookDock = D

D.ADDON = "Blizzard_ClickBindingUI"
D.BOOK_ADDON = "Blizzard_PlayerSpells"
D.GAP = 4               -- Abstand zum Reiter-Stapel bzw. links zum Zauberbuch

D.side = nil            -- "right" | "left", solange ezHeal angedockt hat; sonst nil
local saved             -- Blizzards Anker von ClickBindingFrame vor dem Andocken: { { punkt, rel, relPunkt, x, y } … }

local function Frames() return rawget(_G, "ClickBindingFrame"), rawget(_G, "PlayerSpellsFrame") end

local function Shown(frame)
    return type(frame) == "table" and type(frame.IsShown) == "function" and frame:IsShown() == true
end

local function Points(frame)
    local list = {}
    for i = 1, 8 do
        local point, rel, relPoint, x, y = frame:GetPoint(i)
        if not point then break end
        list[#list + 1] = { point, rel, relPoint, x, y }
    end
    return list
end

-- Hängt das Fenster am Zauberbuch (ezHeals Anker)? Hat Blizzard inzwischen neu gesetzt, ist das Blizzards Lage.
local function AtBook(click, book)
    local _, rel = click:GetPoint(1)
    return rel ~= nil and rel == book
end
local function Ours(click, book) return D.side ~= nil and AtBook(click, book) end

-- Breite des Reiter-Stapels in den Punkten der Klick-Belegung: die Reiter sind Kinder des Zauberbuchs und wachsen mit
-- dessen Größe (ezCores „Blizzard-Fenster skalieren“).
function D.TabWidth(click, book)
    local size = Core.Num(Core.SIDETAB_SIZE) or 0
    local bs = Core.Num(book:GetEffectiveScale()) or 1
    local cs = Core.Num(click:GetEffectiveScale()) or 1
    if cs <= 0 then return size end
    return size * bs / cs
end

-- Zurück zu Blizzards Lage (Anker von vor dem Andocken), nur solange ezHeals Anker gilt.
function D.Release()
    local click, book = Frames()
    if D.side and type(click) == "table" and Ours(click, book) and saved and #saved > 0 then
        if Core.InCombat() then
            ns.AfterCombat(D.Update, "spellbookDock")
            return
        end
        click:ClearAllPoints()
        for _, p in ipairs(saved) do click:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
    end
    D.side, saved = nil, nil
end

-- Seite und Abstand: rechts neben dem Reiter-Stapel, sonst links; nil, wenn auf keiner Seite Platz ist.
-- Unbekannte Lage (Fenster noch nie gezeigt): rechts.
function D.Side(click, book)
    local width = Core.Num(click:GetWidth())
    local rightGap = D.TabWidth(click, book) + D.GAP
    local right = Core.DockRoom(click, book, "right", rightGap)
    if not (width and width > 0 and right) or right >= width then return "right", rightGap end
    local left = Core.DockRoom(click, book, "left", D.GAP)
    if left and left >= width then return "left", D.GAP end
    return nil
end

-- Andocken bzw. lösen, je nach Schalter und offenen Fenstern. → Seite oder nil
function D.Update()
    local click, book = Frames()
    if type(click) ~= "table" then return nil end
    -- Läuft ein Addon, das Blizzards Fenster selbst verschiebt (BlizzMove, MoveAny – ns.OtherFor, Leitlinie 9),
    -- bleibt die Lage dort.
    if not (ns.Enabled("dockSpellbook") and Shown(click) and Shown(book)) or ns.OtherFor("moveFrames") then
        D.Release()
        return nil
    end
    if Core.InCombat() then
        ns.AfterCombat(D.Update, "spellbookDock")
        return D.side
    end
    local side, gap = D.Side(click, book)
    if not side then
        D.Release()
        return nil
    end
    if not AtBook(click, book) then saved = Points(click) end   -- Blizzards Lage, bevor ezHeal ankert
    click:ClearAllPoints()
    if side == "right" then
        click:SetPoint("TOPLEFT", book, "TOPRIGHT", gap, 0)
    else
        click:SetPoint("TOPRIGHT", book, "TOPLEFT", -gap, 0)
    end
    D.side = side
    return side
end

-- Sofort und einen Frame später (Blizzards Fensterverwaltung und ezCores gemerkte Lage setzen erst nach dem Zeigen).
function D.Soon()
    D.Update()
    local timer = rawget(_G, "C_Timer")
    if type(timer) == "table" and type(timer.After) == "function" then timer.After(0, D.Update) end
end

---------------------------------------------------------------------------
-- Gemeinsam schließen (Spieltest 21.11.2026, wörtlich: „schließen von Klickbelegung soll nur das eigene fenster aber
-- nicht zauberbuch schließen“, „zauberbuch schließen soll auch klcikbelegung schließen“; Soll laut zweitem Spieltest:
-- „beide offen -> zauberbuch zu auch klickbelegung zu ODER klickbelegung zu zauberbuch aber weiterhin offen“; Schalter
-- pairSpellbook). Blizzards Fenster schließt in seinem eigenen OnHide das Zauberbuch mit (ClearFocusedFrame →
-- HideUIPanel); das Skript bleibt unberührt (Leitlinie 5).
-- Dritte Fassung: Die erste öffnete mitten in Blizzards Schließen, die zweite verließ sich darauf, dass Blizzard das
-- Zauberbuch im selben Bild schließt (zweiter Spieltest: „hat nichts gebracht“). Jetzt zählt, was der Spieler tut:
--   - Klick auf Blizzards X oder „Speichern“ der Klick-Belegung (HookScript OnClick, nach Blizzards Skript) oder auf
--     „Verwerfen“ in Blizzards Rückfrage CONFIRM_LOSE_UNSAVED_CLICK_BINDINGS (hooksecurefunc StaticPopup_OnClick, Knopf
--     1; Blizzards OnHide der Klick-Belegung schließt die Rückfrage selbst, darum zählt nicht „Rückfrage noch offen“;
--     hat das X die Rückfrage geöffnet, zählt das X selbst nicht) → ging das Zauberbuch mit zu (vorher, im selben Bild oder
--     bis D.RECHECK Sekunden danach), öffnet ezHeal es wieder (Core.OpenPanel, Blizzards
--     PlayerSpellsUtil.OpenToSpellBookTab). Schließt Blizzard die Klick-Belegung selbst (ein anderes Fenster verdrängt
--     sie) oder Esc (CloseWindows), öffnet ezHeal nichts.
--     Grenzen: Andere Wege, die Klick-Belegung zu schließen (eine eigene Taste, /run ToggleClickBindingFrame()), sind
--     von Blizzards Verdrängen nicht zu unterscheiden und zählen nicht – das Zauberbuch geht dann wie bei Blizzard mit
--     zu. Schließt der Spieler das Zauberbuch selbst innerhalb von D.RECHECK Sekunden nach dem X, kann ezHeal es noch
--     einmal öffnen. Den zweiten Versuch (nach D.VERIFY) gibt es nur, wenn das Zauberbuch höchstens D.REOPEN_CLOSED
--     Sekunden nach dem Öffnen wieder zuging (so schnell schließt nur Blizzard) und kein Esc dazwischen lag.
--   - Nur das Zauberbuch zu, die Klick-Belegung offen und zu sehen → die Klick-Belegung ein Bild später mit schließen;
--     nicht, wenn Blizzards Portrait-Knopf zu den Makros gewechselt hat (Blizzards gewähltes Fenster ist ein anderes und
--     zu sehen, nur gelesen, oder die Makros sind offen) oder die Oberfläche ausgeblendet ist (Alt+Z). Kein gewähltes
--     Fenster oder ein verwaistes (Makros mit ihrem eigenen X geschlossen – Blizzard leert die Wahl dann nicht) zählt
--     wie das Zauberbuch (fünfter Spieltest 21.11.2026, Bericht: „gewählt: keins“; Blizzard leert die Wahl nur in
--     ClearFocusedFrame – OnHide der Klick-Belegung und Abwählen über einen Portrait-Knopf). Mit ungespeicherten
--     Änderungen erst
--     Blizzards eigene Rückfrage (CONFIRM_LOSE_UNSAVED_CLICK_BINDINGS, wie sein X).
-- Alles nur außerhalb des Kampfes und nicht, während ezCore Klick-Zauber neu lädt (Core.ClickBindings.Reloading).
-- Die letzten Entscheidungen stehen im Bericht von /ez debug (deutsch, Leitlinie 7).
---------------------------------------------------------------------------

D.RECHECK = 0.25                -- so lange nach dem X darf Blizzard das Zauberbuch noch schließen
-- Dritter Spieltest 21.11.2026 („geht nicht... machst du irgendwas oder verstehst du was du tust“): Klick und Schließen
-- müssen nicht im selben Bild liegen (Blizzards Fensterverwaltung kann die Klick-Belegung später schließen) – der Klick
-- gilt D.INTENT_SPAN Sekunden vor oder nach dem Schließen. Bleibt das Zauberbuch nach dem Öffnen nicht offen (nach
-- D.VERIFY Sekunden geprüft), versucht ezHeal es ein zweites Mal. Jeder Schritt steht im Bericht von /ez debug.
D.INTENT_SPAN = 0.5
D.VERIFY = 0.3
D.REOPEN_CLOSED = 0.1           -- so schnell nach ezHeals Öffnen wieder zu: das war Blizzard, nicht der Spieler
D.CONFIRM = "CONFIRM_LOSE_UNSAVED_CLICK_BINDINGS"   -- Blizzards Rückfrage beim X mit ungespeicherten Änderungen
D.clickHiddenAt = nil           -- GetTime() des Bilds, in dem die Klick-Belegung zuging
D.bookHiddenAt = nil            -- … das Zauberbuch zuging
D.escAt = nil                   -- … Blizzards CloseWindows lief (Esc, Verlust der Kontrolle)
D.intentAt = nil                -- … der Spieler auf X oder „Speichern“ der Klick-Belegung klickte
D.intentWait = false            -- das X hat Blizzards Rückfrage geöffnet (nur für den Bericht; zählt erst „Verwerfen“)
local closingWithBook = false   -- ezHeal schließt die Klick-Belegung, weil das Zauberbuch zuging
local bookWithClick = false     -- das Zauberbuch war offen, als die Klick-Belegung zuging (ohne sein späteres OnHide)
D.LOG_MAX = 20
D.log = {}

local function Now()
    local fn = rawget(_G, "GetTime")
    return type(fn) == "function" and Core.Num(fn()) or nil
end

local function Note(text)
    D.log[#D.log + 1] = string.format("%.2f %s", Now() or 0, text)
    while #D.log > D.LOG_MAX do table.remove(D.log, 1) end
end

-- Schalter an, und ezCore lädt Blizzards Fenster nicht gerade neu (CB.Reload schließt und öffnet es selbst)
local function Paired()
    local CB = Core.ClickBindings
    if type(CB) == "table" and type(CB.Reloading) == "function" and CB.Reloading() then return false end
    return ns.Enabled("pairSpellbook")
end

-- Ungespeicherte Änderungen in Blizzards Fenster (ezCore liest sie, Core.ClickBindings.Unsaved)
local function Unsaved()
    local CB = Core.ClickBindings
    return type(CB) == "table" and type(CB.Unsaved) == "function" and CB.Unsaved() == true
end

-- Blizzards gewähltes Fenster der Klick-Belegung (GetFocusedFrame, sonst das Feld focusedFrame; nur gelesen)
local function Focused(click)
    if type(click.GetFocusedFrame) == "function" then
        local ok, frame = pcall(click.GetFocusedFrame, click)
        if ok and frame ~= nil then return frame end
    end
    return rawget(click, "focusedFrame")
end

-- Name eines Fensters für den Bericht (GetName, nur gelesen)
local function FrameName(frame)
    if frame == nil then return "keins" end
    if type(frame) == "table" and type(frame.GetName) == "function" then
        local ok, name = pcall(frame.GetName, frame)
        if ok and type(name) == "string" then return name end
    end
    return "unbekannt"
end

local function After(seconds, fn)
    local timer = rawget(_G, "C_Timer")
    if type(timer) == "table" and type(timer.After) == "function" then timer.After(seconds, fn) else fn() end
end

-- Klick auf Blizzards X bzw. „Speichern“ (nach Blizzards Skript): der Spieler will nur die Klick-Belegung schließen.
function D.Intent(button)
    local click = Frames()
    -- Hat das X Blizzards Rückfrage (ungespeicherte Änderungen) geöffnet, zählt erst „Verwerfen“ (D.ConfirmClicked);
    -- „noch offen“ allein heißt nichts: Blizzards Fensterverwaltung kann die Klick-Belegung erst später schließen
    D.intentWait = Shown(click) and type(click) == "table" and button ~= nil and button == rawget(click, "CloseButton")
        and D.ConfirmOpen()
    D.intentAt = (not D.intentWait) and Now() or nil
    Note("Klick auf " .. (type(click) == "table" and button == rawget(click, "SaveButton") and "„Speichern“" or "X")
        .. ", Klick-Zauber noch offen: " .. tostring(Shown(click)) .. (D.intentWait and ", Rückfrage offen" or ""))
end

-- Blizzards StaticPopup_OnClick (hooksecurefunc, danach): Knopf 1 („Verwerfen“) in Blizzards Rückfrage der
-- Klick-Belegung. Blizzards OnAccept hat die Klick-Belegung da schon geschlossen (im selben Bild, D.INTENT_SPAN).
function D.ConfirmClicked(dialog, index)
    if index ~= 1 or type(dialog) ~= "table" or rawget(dialog, "which") ~= D.CONFIRM then return end
    D.intentAt, D.intentWait = Now(), false
    Note("„Verwerfen“ in Blizzards Rückfrage")
end

-- Ist Blizzards Rückfrage gerade offen? (StaticPopup_Visible, nur gelesen)
function D.ConfirmOpen()
    local visible = rawget(_G, "StaticPopup_Visible")
    if type(visible) ~= "function" then return false end
    local ok, dialog = pcall(visible, D.CONFIRM)
    return ok and dialog ~= nil and dialog ~= false
end

local function IntentFor(at)
    return D.intentAt ~= nil and at ~= nil and math.abs(at - D.intentAt) <= D.INTENT_SPAN
end

function D.ClickShown()
    local click, book = Frames()
    Note("Klick-Zauber auf, gewählt: " .. FrameName(Focused(click)) .. ", Zauberbuch offen: " .. tostring(Shown(book)))
    D.Soon()
end

function D.ClickHidden()
    local _, book = Frames()
    D.Release()
    if not Paired() then
        Note("Klick-Zauber zu – Schalter aus oder ezCore lädt neu, nichts zu tun")
        D.intentAt, D.intentWait = nil, false   -- der Klick ist verbraucht (gilt nicht für ein späteres Verdrängen)
        return
    end
    D.clickHiddenAt = Now()
    Note("Klick-Zauber zu, Zauberbuch offen: " .. tostring(Shown(book)))
    bookWithClick = Shown(book)          -- im selben Bild zugegangen: erst D.AfterClickHidden (bookHiddenAt)
    After(0, D.AfterClickHidden)
end

function D.BookShown()
    closingWithBook = false
    D.Soon()
end

function D.BookHidden()
    local click = Frames()
    D.Update()
    if not Paired() then return end
    D.bookHiddenAt = Now()
    Note("Zauberbuch zu, Klick-Zauber offen: " .. tostring(Shown(click)))
    After(0, D.CloseWithBook)
end

local function Reopen(why, again)
    local openedAt = Now()
    local ok, reason = Core.OpenPanel("spellbook", nil, true)
    local _, book = Frames()
    Note("Zauberbuch öffnen (" .. why .. "): " .. tostring(ok) .. (reason and (", " .. tostring(reason)) or "")
        .. ", jetzt offen: " .. tostring(Shown(book)))
    -- Blieb es offen? Sonst ein zweiter Versuch – nur, wenn Blizzard es gleich wieder schloss (nicht der Spieler mit
    -- Esc, P oder dem X des Zauberbuchs), und nicht im Kampf.
    After(D.VERIFY, function()
        local _, later = Frames()
        local byBlizzard = openedAt ~= nil and D.bookHiddenAt ~= nil and D.bookHiddenAt >= openedAt
            and D.bookHiddenAt - openedAt <= D.REOPEN_CLOSED
        local esc = openedAt ~= nil and D.escAt ~= nil and D.escAt >= openedAt
        if Shown(later) then
            Note("Zauberbuch nach " .. D.VERIFY .. " s offen")
        elseif not again and byBlizzard and not esc and Paired() and not Core.InCombat() then
            Note("Zauberbuch nach " .. D.VERIFY .. " s wieder zu – zweiter Versuch")
            Reopen(why .. ", zweiter Versuch", true)
        else
            Note("Zauberbuch nach " .. D.VERIFY .. " s wieder zu (gleich wieder zu: " .. tostring(byBlizzard)
                .. ", Esc: " .. tostring(esc) .. ")")
        end
    end)
    return ok == true
end

-- Ein Bild nach dem Schließen der Klick-Belegung: Hat der Spieler X bzw. „Speichern“ geklickt und ging das Zauberbuch
-- mit zu, öffnet ezHeal es wieder; ist es noch offen, ein zweites Mal nach D.RECHECK Sekunden. → true, wenn geöffnet
function D.AfterClickHidden(second)
    local _, book = Frames()
    local at = D.clickHiddenAt
    if at == nil then return false end
    local withBook = closingWithBook
    local intent = IntentFor(at)
    -- Vierter Spieltest 21.11.2026 (Bericht von /ez debug): Im Spiel ist das Zauberbuch beim OnHide der Klick-Belegung
    -- schon zu (IsShown false), sein eigenes OnHide kommt erst nach ezHeals Haken, im selben Bild – danach erst der Klick
    -- auf das X. Darum zählt hier, ein Bild später, auch das Bild, in dem das Zauberbuch zuging.
    -- offen bis zur Klick-Belegung: beim Schließen noch offen oder im selben Bild zugegangen (auch erst danach gemeldet)
    local bookToo = bookWithClick or (D.bookHiddenAt ~= nil and D.bookHiddenAt == at)
    if withBook or not intent or not bookToo or D.escAt == at or not Paired() or Core.InCombat() then
        Note((second == true and "spät: " or "") .. "Klick-Zauber zu, nichts zu tun (Klick: " .. tostring(intent)
            .. ", Zauberbuch offen: " .. tostring(bookToo) .. ", mit Zauberbuch: " .. tostring(withBook)
            .. ", Esc: " .. tostring(D.escAt == at) .. ", Kampf: " .. tostring(Core.InCombat()) .. ")")
        closingWithBook, D.intentAt, D.intentWait = false, nil, false
        return false
    end
    if Shown(book) then
        if second ~= true then
            After(D.RECHECK, function() D.AfterClickHidden(true) end)
            return false
        end
        Note("Klick-Zauber zu, Zauberbuch blieb offen")
        D.intentAt, D.intentWait = nil, false
        return false
    end
    D.intentAt, D.intentWait = nil, false
    return Reopen(second == true and "spät" or "gleich")
end

-- Ein Bild nach dem Schließen des Zauberbuchs: die Klick-Belegung mit schließen, wenn sie noch offen und zu sehen ist
-- und Blizzard nicht nur zu den Makros gewechselt hat. Ein anderes gewähltes Fenster, das zu sehen ist: nicht
-- schließen; keines oder ein verwaistes: schließen.
function D.CloseWithBook()
    local click, book = Frames()
    if not (Shown(click) and not Shown(book) and Paired()) or Core.InCombat() then return false end
    if type(click.IsVisible) == "function" and click:IsVisible() ~= true then return false end
    local focused, macros = Focused(click), Core.PanelShown("macro") == true
    if (focused ~= nil and focused ~= book and Shown(focused)) or macros then
        Note("Zauberbuch zu, Klick-Zauber bleibt (gewählt: " .. FrameName(focused) .. ", Makros offen: "
            .. tostring(macros) .. ")")
        return false
    end
    closingWithBook = true
    if Unsaved() and type(rawget(_G, "StaticPopup_Show")) == "function" then
        StaticPopup_Show(D.CONFIRM)   -- Blizzards eigene Rückfrage, wie sein X
        Note("Zauberbuch zu, Rückfrage wegen ungespeicherter Änderungen")
        return "ask"
    end
    local ok = Core.ClosePanel("clickbindings", nil, true) == true
    Note("Zauberbuch zu, Klick-Zauber geschlossen: " .. tostring(ok))
    return ok
end

-- Esc (Blizzards CloseWindows): im selben Bild Geschlossenes bleibt zu.
function D.AfterCloseWindows() D.escAt = Now() end

-- Bericht von /ez debug (Core.Debug.AddLine): die letzten Entscheidungen
local debug = Core.Debug
if type(debug) == "table" and type(debug.AddLine) == "function" then
    debug.AddLine("ezHeal: Zauberbuch und Klick-Zauber", function()
        if #D.log == 0 then return "noch nichts entschieden" end
        return D.log
    end, ADDON)
end

local hookedButtons = {}

-- Blizzards X und „Speichern“ der Klick-Belegung (Forever-Quelle: CloseButton aus PortraitFrameTemplate, SaveButton im
-- XML): nach Blizzards Skript zuhören
local function HookButtons(click)
    for _, key in ipairs({ "CloseButton", "SaveButton" }) do
        local button = rawget(click, key)
        if not hookedButtons[key] and type(button) == "table" and type(button.HookScript) == "function" then
            hookedButtons[key] = true
            button:HookScript("OnClick", D.Intent)
        end
    end
end

local hookedClick, hookedBook, hookedPanels, hookedDelegate, hookedClose = false, false, false, false, false
local hookedConfirm = false

local function HookBook()
    local _, book = Frames()
    if hookedBook or type(book) ~= "table" or type(book.HookScript) ~= "function" then return end
    hookedBook = true
    book:HookScript("OnShow", D.BookShown)
    book:HookScript("OnHide", D.BookHidden)
    book:HookScript("OnSizeChanged", D.Update)    -- verkleinert ↔ ganz: der Reiter-Stapel wandert mit der Kante
end

function D.Hook()
    local click = Frames()
    if type(click) ~= "table" then return end
    if not hookedClick and type(click.HookScript) == "function" then
        hookedClick = true
        click:HookScript("OnShow", D.ClickShown)
        click:HookScript("OnHide", D.ClickHidden)
    end
    HookButtons(click)
    if not hookedClose and type(rawget(_G, "CloseWindows")) == "function" then
        hookedClose = true
        hooksecurefunc("CloseWindows", D.AfterCloseWindows)
    end
    if not hookedConfirm and type(rawget(_G, "StaticPopup_OnClick")) == "function" then
        hookedConfirm = true
        hooksecurefunc("StaticPopup_OnClick", D.ConfirmClicked)
    end
    HookBook()
    -- Blizzards Neuordnung: die globale Funktion und die Methode der Fensterverwaltung (wie ezCores MoveFrames)
    if not hookedPanels and type(rawget(_G, "UpdateUIPanelPositions")) == "function" then
        hookedPanels = true
        hooksecurefunc("UpdateUIPanelPositions", D.Soon)
    end
    local delegate = rawget(_G, "FramePositionDelegate")
    if not hookedDelegate and type(delegate) == "table" and type(delegate.UpdateUIPanelPositions) == "function" then
        hookedDelegate = true
        hooksecurefunc(delegate, "UpdateUIPanelPositions", D.Soon)
    end
    if Shown(click) then D.Soon() end
end

Core.Listen("FRAME_MOVED", function() D.Soon() end, ADDON)
-- Forever++ sagt erst nach seinem READY, ob es Fenster verschiebt (Leitlinie 9)
Core.Listen("OTHER_ADDONS_CHANGED", function() D.Update() end, ADDON)
ns.OnSettingChanged(function(key) if key == "dockSpellbook" then D.Update() end end)

ns.OnReady(function()
    ns.WhenAddOnLoaded(D.BOOK_ADDON, function() ns.Try("Klick-Zauber am Zauberbuch", HookBook) end)
    ns.WhenAddOnLoaded(D.ADDON, function() ns.Try("Klick-Zauber am Zauberbuch", D.Hook) end)
end)
