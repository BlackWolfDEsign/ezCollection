local ADDON, ns = ...
local Core = ezCore
local L = ns.L
local Traits = ns.Traits
local Templates = ns.Templates
local Effects = ns.Effects
local Plan = ns.Plan

--[[
    Seitenreiter und Seitenteile an Blizzards Fenstern (Leitlinie 1: keine freien Fenster).

      Talente     PlayerSpellsFrame.TalentsFrame (Blizzard_PlayerSpells, Camelot-Fassung) – Reiter rechts am Talentfenster,
                  Seitenteil daneben; beides Kinder des Talentfensters, sichtbar nur mit ihm
      Vermächtnis LegacySystemFrame.TreePage (Blizzard_LegacySystem, nur Spieltyp camelot) – dieselben Reiter und
                  Seitenteile, Konfiguration und Baum liest ezTalent aus TreePage.LegacyTreeTraitPanel

    Reiter über ezCores Seitenreiter-Stapel (Core.CreateSideTab, eigener Stapel am Talent- bzw. Vermächtnisrahmen):
    „Vorlagen“ (order 10) und „Auswirkungen“ (order 20) an beiden Fenstern, am Talentfenster dazu „Twinks“ (order 30,
    TL-12). Ein Klick öffnet das Seitenteil, ein zweiter schließt es; es ist immer nur eines offen.

    Seitenteil „Vorlagen“ (Ablauf nach dem Spieltest vom 14.11.2026): Die Liste zeigt „Aktuelle Verteilung“, die
    eigenen Vorlagen und die Vorauswahl der Klasse. Ein Klick lädt den Eintrag als Vorschau in Blizzards Baum
    (Plan.lua) – kopiert oder gesetzt wird dabei nichts. Darunter die Knöpfe in der Reihenfolge des Ablaufs:
    „Übernehmen“ (Punkte der Vorschau gestaffelt setzen), „Anpassen“ (Planen an/aus), „Speichern“ (Vorschau bzw.
    aktuelle Verteilung als Vorlage ablegen), dann Teilen, Einfügen, Twinks, Umbenennen, Löschen und „Zurücksetzen
    und übernehmen“.

    Taint: Blizzards Rahmen werden nur gelesen (GetConfigID, GetTalentTreeID, IsLocked, GetTalentButtonByNodeID, Größe
    und Lage); eigene Rahmen hängen als Kinder daran; hooksecurefunc nur auf SetTalentTreeID der Instanz, HookScript
    auf OnShow/OnHide des Elternrahmens, Blizzards Rückruf „TalentFrameBase.ButtonsUpdated“ nur über
    EventRegistry:RegisterCallback. Bestätigt wird mit Blizzards Knopf.

    Lage (Forever-Quelle, Zweig forever):
      - Das Vermächtnis-Fenster hat rechts drei eigene Reiter (Blizzard_LegacySystem.xml: LegacyRewardTrackTab bei
        TOPLEFT → TOPRIGHT y −60, darunter LegacyChallengeTab und LegacyTreeTab mit je −2 Abstand; Vorlage
        LargeSideTabButtonTemplate, Größe aus dem Atlas „common-sidetab“, unter Camelot breiter). ezTalents Stapel
        beginnt deshalb darunter, die Breite liest UI.TabsBelow zur Laufzeit.
      - Das Talentfenster ist 1218 breit (TalentsFrame 1212) und steht mittig (Camelot/Blizzard_PlayerSpellsFrame.xml
        talentsWidth, AreaAttributeForTab: "center"). Das Seitenteil dockt außen rechts an (Spieltest 14.11.2026:
        innen verdeckte es den dritten Baum). UI.Place nimmt die Breite, die rechts frei ist (UI.PANEL_MIN bis
        UI.PANEL_WIDTH), und prüft das bei jedem Zeigen. Nur wenn nicht einmal die Mindestbreite passt, liegt es als
        letzter Ausweg innen rechts über dem Baum – zwischen Blizzards Kopf und Fußleiste –, sagt das im Kopf und
        klappt nie von selbst auf.
        Wie viel Platz der Nutzer hat, ist NICHT belegt (Gegenprüfung 14.11.2026). Rechnung für 16:9: Außen passt
        es, wenn rechts mindestens 280 Punkte frei sind (240 + Reiter 36 + Rand 4) – also ab einer Bildschirmbreite
        von 1772 Punkten (effektive UI-Skala bis etwa 0,77; bei 1920 Punkten sind es 314 statt der Wunschbreite). Ist
        UIParent 768 Punkte hoch (Skala 1,0; rund 1365 breit), bleiben rechts nur rund 77 Punkte: Dann liegt das
        Seitenteil weiter innen, und auch ein nach links gerücktes Fenster reichte nicht (1212 + 280 > 1365).
        Seit TL-13 (Entscheidungsfrage 5, Empfehlung umgesetzt, Antwort offen) macht ezTalent dann Platz: Blizzards
        Fenster rückt nach links und wird, wo das nicht reicht, verkleinert – nur solange ein Seitenteil offen ist,
        nie im Kampf, abschaltbar (UI.MakeRoom, UI.GiveRoom). Innen liegt es nur noch, wenn auch das nicht geht.
      - Der Reiter „Vorlagen“ klappt das Seitenteil auf und zu (Leitlinie 3; bis zum Spielbefund vom 19.11.2026 stand
        dafür zusätzlich ein Knopf „Vorlagen »“ neben Blizzards Suchfeld); ob es offen war, merkt sich ezTalent
        (ezTalentDB.ui.open) und stellt es beim ersten Öffnen des Fensters wieder her – am Talentfenster ab Werk offen.
      - Blizzard_PlayerSpells lädt erst bei Bedarf (TOC: LoadOnDemand); ezTalent hängt sich über
        ns.WhenAddOnLoaded an, sobald es geladen ist – auch beim ersten Öffnen mit der Taste.
]]

local UI = {}
ns.UI = UI
UI.hosts = {}
UI.PANEL_WIDTH = 360       -- Wunschbreite des Seitenteils (Spieltest 15.11.2026: Liste zu schmal – vorher 320; nur, wo
                           -- rechts so viel Platz ist, sonst schmaler bis UI.PANEL_MIN)
UI.PANEL_MIN = 240         -- schmaler wird es nicht (dann zwei statt drei Knöpfe je Reihe)
UI.SCREEN_MARGIN = 4       -- Luft zum Bildschirmrand
UI.BUTTON_COLUMNS_AT = 300 -- ab dieser Breite drei Knöpfe je Reihe
UI.ROW_GAP = 2
UI.TIP_NAMES = 4           -- so viele nicht gefundene Talente nennt der Tooltip, dann „und n weitere“
UI.TAB_WIDTH = 32          -- ezCores Seitenreiter (Core.BuildSideTab, 32 × 32)
UI.TAB_SPACE = 4           -- Abstand Reiter → Seitenteil
UI.STACK_SPACE = 12        -- Abstand Blizzards letzter Reiter → erster eigener (wie in ezCores Stapel: 44 − 32)
UI.LEGACY_TAB_TOP = -60    -- Blizzard_LegacySystem.xml: erster Reiter bei TOPLEFT → TOPRIGHT y −60
UI.LEGACY_TAB_GAP = 2      -- … die folgenden je 2 darunter
UI.INSET = { top = 60, bottom = 40, right = 4 }   -- innen angedockt: Kopf und Fußleiste von Blizzard bleiben frei
UI.PANEL_LEVEL = 1500      -- über dem Elternrahmen: Talentfenster 100 → 1600, über Blizzards Kopf (1010), unter der Suchvorschau (2000)

-- Ton je Zustand in „Auswirkungen“ (ns.TONES in Core.lua; Design-System 2.5, Welle 22)
local STATE_TONE = { new = "good", removed = "bad", changed = "gold" }

-- Rundgang (Tour.lua lädt nach dieser Datei): bei jedem Wechsel dessen, was zu sehen ist, die nächste Erklärblase
-- vormerken – Öffnen und Schließen des Fensters, Auf- und Zuklappen eines Seitenteils, Reiter an/aus.
local function TourSoon(host)
    if ns.Tour then ns.Try("Tour", ns.Tour.Soon, host) end
end

---------------------------------------------------------------------------
-- Kontext eines Fensters: welche Konfiguration, welcher Baum, welcher Scope?
---------------------------------------------------------------------------

local function Read(frame, method)
    if type(frame) ~= "table" or type(frame[method]) ~= "function" then return nil end
    return Core.Call(frame[method], frame)
end

function UI.Context(host)
    if not host then return nil end
    local frame = host.source()
    local configID = Core.Num(Read(frame, "GetConfigID"))
    local treeID = Core.Num(Read(frame, "GetTalentTreeID"))
    local ctx = { kind = host.kind }
    if host.kind == "class" then
        configID = configID or Traits.ClassConfigID()
        treeID = treeID or Traits.TreeOfConfig(configID)
        ctx.scope = Templates.ClassScope()
        ctx.inspecting = Read(frame, "IsInspecting") == true      -- Baum eines betrachteten Spielers
        ctx.locked = Read(frame, "IsLocked") == true or ctx.inspecting
        -- Baum der inaktiven Spezialisierung (Nr. 29): gesperrt, eigener Baum, aber nicht die aktive Konfiguration
        local active = Traits.ClassConfigID()
        ctx.inactive = ctx.locked and not ctx.inspecting and configID ~= nil and active ~= nil and configID ~= active
    else
        if not treeID then
            local first = Traits.LegacyTrees()[1]
            treeID = first and first.treeID
        end
        configID = configID or Traits.LegacyConfigID(treeID)
        ctx.scope = Templates.LegacyScope(treeID)
        ctx.legacyKey = Traits.LegacyKey(treeID)
    end
    ctx.configID, ctx.treeID = configID, treeID
    -- Blizzards „Übernehmen“ läuft gerade (Zauber mit Wirkzeit): Übernehmen, Zurücksetzen und Vormerkung warten (T7-NT1)
    ctx.committing = Traits.Committing(frame)
    return ctx
end

---------------------------------------------------------------------------
-- Bausteine
---------------------------------------------------------------------------

-- tipLeft = true: Tooltip links neben dem Knopf (Knöpfe im Seitenteil stehen am rechten Bildschirmrand)
-- Gesperrt zeigt der Knopf seinen Tooltip weiter (ezCores Toolbar.ShowTipWhileDisabled, Gesamtreview T9-7), darunter
-- den Grund in der Rolle „bad“: button.whyDisabled = Text oder fn() → Text.
local function DisabledReason(button)
    if button:IsEnabled() then return nil end
    local why = button.whyDisabled
    if type(why) == "function" then why = why() end
    return type(why) == "string" and why ~= "" and why or nil
end
UI.DisabledReason = DisabledReason

local function Button(parent, text, tip, onClick, width, tipLeft)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width or 92, 22)
    button:SetText(text)
    Core.Toolbar.ShowTipWhileDisabled(button)
    button:SetScript("OnClick", function(self) ns.Try("UI", onClick, self) end)
    button:SetScript("OnEnter", function(self)
        local body, why = tip, DisabledReason(self)
        if why then body = (body and (body .. "\n\n") or "") .. ns.Tone("bad", why) end
        if tipLeft then UI.ShowRowTip(self, text, body) else Core.ShowTip(self, text, body) end
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    return button
end

local function CreateScroll(parent)
    local ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, parent, "ScrollFrameTemplate")
    if not (ok and scroll) then scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate") end
    local bar = scroll.ScrollBar
    if type(bar) == "table" and bar.SetHideIfUnscrollable then bar:SetHideIfUnscrollable(true) end
    scroll.content = CreateFrame("Frame", nil, scroll)
    scroll.content:SetSize(UI.PANEL_WIDTH - 40, 1)
    scroll:SetScrollChild(scroll.content)
    scroll.rows, scroll.used = {}, 0
    return scroll
end

-- Zeilen schreiben: lines = { { text, sub, font, subFont, indent, gap, onClick, tip, tipTitle, selected } }
-- Je Eintrag eine Hauptzeile (text, Name) und höchstens eine Unterzeile (sub: Zweck · Verteilung · Zustand) – Spieltest
-- 15.11.2026: Einträge brachen mitten in der Zeile um, Unterzeilen standen in mehreren Farben und Größen durcheinander.
-- Schriften nur aus Blizzards Schrift-Objekten (UI.FONTS); beide Texte brechen an Wortgrenzen um, nichts wird gekürzt.
UI.FONTS = { row = "GameFontHighlight", sub = "GameFontDisableSmall", section = "GameFontNormal",
    note = "GameFontHighlightSmall", headTitle = "GameFontNormal", head = "GameFontHighlight" }
UI.SUB_GAP = 1           -- Abstand Hauptzeile → Unterzeile
UI.ENTRY_GAP = 5         -- Abstand zwischen zwei Einträgen
UI.SECTION_GAP = 12      -- Luft über einer Überschrift („Eigene Vorlagen“, „Vorauswahl“)
UI.LINE_HEIGHT = { GameFontHighlight = 14, GameFontNormal = 14, GameFontHighlightSmall = 12, GameFontDisableSmall = 12,
    GameFontNormalSmall = 12 }   -- Ersatz, wenn der Client (noch) keine Texthöhe nennt

local function TextHeight(fontString, font)
    local h = Core.Num(Read(fontString, "GetStringHeight"))
    if h and h > 0 then return h end
    return UI.LINE_HEIGHT[font or ""] or 12
end

local function Row(scroll, index)
    local row = scroll.rows[index]
    if row then return row end
    row = CreateFrame("Button", nil, scroll.content)
    row.text = row:CreateFontString(nil, "ARTWORK", UI.FONTS.row)
    row.text:SetJustifyH("LEFT")
    row.text:SetJustifyV("TOP")
    Core.Call(row.text.SetWordWrap, row.text, true)
    -- beide Anker oben: die Breite steht fest, die Höhe folgt dem umbrochenen Text
    row.text:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
    row.text:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, -1)
    -- Unterzeile direkt unter der Hauptzeile (gleiche Breite)
    row.sub = row:CreateFontString(nil, "ARTWORK", UI.FONTS.sub)
    row.sub:SetJustifyH("LEFT")
    row.sub:SetJustifyV("TOP")
    Core.Call(row.sub.SetWordWrap, row.sub, true)
    row.sub:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -UI.SUB_GAP)
    row.sub:SetPoint("TOPRIGHT", row.text, "BOTTOMRIGHT", 0, -UI.SUB_GAP)
    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints(row)
    row.highlight:SetColorTexture(1, 1, 1, 0.08)
    row.selected = row:CreateTexture(nil, "BACKGROUND")
    row.selected:SetAllPoints(row)
    row.selected:SetColorTexture(1, 0.82, 0, 0.15)
    row:SetScript("OnEnter", function(self)
        if self.tip and self.tipWide then UI.ShowWideRowTip(self, self.tipTitle or "", self.tip)
        elseif self.tip then UI.ShowRowTip(self, self.tipTitle or "", self.tip) end
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:SetScript("OnClick", function(self) if self.onClick then ns.Try("UI", self.onClick, self) end end)
    scroll.rows[index] = row
    return row
end

-- Tooltip einer Listenzeile bzw. eines Knopfs im Seitenteil. Spieltest 14.11.2026: rechts daneben (ANCHOR_RIGHT) lief
-- der Tooltip mit den Quellen bis an den Bildschirmrand. Weiterleitung auf ezCores Core.ShowTip ohne Anker (TL-23):
-- Core.TipAnchor wählt die Seite nach dem Platz – links, wenn der Besitzer in der rechten Bildschirmhälfte steht –,
-- und der Text bricht um. Vorher stand der Tooltip hier immer links (eigene Fassung, solange ezCore das nicht konnte).
function UI.ShowRowTip(owner, title, body)
    if body == "" then body = nil end
    return Core.ShowTip(owner, title, body)
end

-- Lange Beschreibung einer Vorlage (Spielbefund des Nutzers vom 19.11.2026, Bild 38: „das fenster der beschreibung eines
-- presets sollte breiter sein und es fehlen abstände zwischen den texten“): ezCores breiter Tooltip, jede Zeile des
-- Texts ein Abschnitt mit Leerzeile dazwischen (Core.ShowWideTip).
function UI.ShowWideRowTip(owner, title, body)
    if body == "" then body = nil end
    if not Core.ShowWideTip then return UI.ShowRowTip(owner, title, body) end
    return Core.ShowWideTip(owner, title, body)
end

-- Höhe einer Zeile aus den Höhen von Haupt- und Unterzeile (rein gerechnet, für Fill und die Prüfung der Geometrie).
function UI.RowHeight(textH, subH)
    local h = (textH or 0) + 4
    if subH and subH > 0 then h = h + UI.SUB_GAP + subH end
    return math.max(14, h)
end

function UI.Fill(scroll, lines)
    local y = 0
    for i, line in ipairs(lines) do
        local row = Row(scroll, i)
        local font = line.font or UI.FONTS.note
        row.text:SetFontObject(font)
        row.text:SetText(line.text or "")
        local subFont = line.subFont or UI.FONTS.sub
        local hasSub = type(line.sub) == "string" and line.sub ~= ""
        row.sub:SetFontObject(subFont)
        row.sub:SetText(hasSub and line.sub or "")
        row.sub:SetShown(hasSub)
        row.onClick, row.tip, row.tipTitle, row.tipWide = line.onClick, line.tip, line.tipTitle, line.tipWide == true
        row.highlight:SetShown(line.onClick ~= nil)
        row.selected:SetShown(line.selected == true)
        y = y + (line.before or 0)                  -- Luft über einer Überschrift
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scroll.content, "TOPLEFT", line.indent or 0, -y)
        row:SetPoint("RIGHT", scroll.content, "RIGHT", 0, 0)
        local height = UI.RowHeight(TextHeight(row.text, font), hasSub and TextHeight(row.sub, subFont) or nil)
        row:SetHeight(height)
        row.top, row.bottom = y, y + height          -- Lage in der Liste (für die Prüfung: keine Überlappung)
        row:Show()
        y = y + height + (line.gap or UI.ROW_GAP)
    end
    for i = #lines + 1, #scroll.rows do scroll.rows[i]:Hide() end
    scroll.used = #lines
    scroll.lines = lines
    scroll.content:SetHeight(math.max(1, y))
    return #lines
end

---------------------------------------------------------------------------
-- Lage: Blizzards Reiter freihalten, Seitenteil auf dem Bildschirm halten
---------------------------------------------------------------------------

-- Blizzards eigene Seitenreiter eines Fensters (parentArray "Tabs"), nur gelesen.
function UI.BlizzardTabs(frame)
    local tabs = {}
    local list = type(frame) == "table" and frame.Tabs
    if type(list) ~= "table" then return tabs end
    for _, tab in ipairs(list) do
        if type(tab) == "table" then tabs[#tabs + 1] = tab end
    end
    return tabs
end

-- Wo ein eigener Stapel unter Blizzards Reitern beginnt und wie breit diese sind.
-- → start (y für ezCores Stapel, von oben) oder nil (keine Blizzard-Reiter), Breite des breitesten Reiters
function UI.TabsBelow(tabs)
    if type(tabs) ~= "table" or #tabs == 0 then return nil, 0 end
    local first = tabs[1]
    local _, _, relPoint, _, y = Core.Call(first.GetPoint, first, 1)
    y = relPoint == "TOPRIGHT" and Core.Num(y) or UI.LEGACY_TAB_TOP
    -- Ersatz, falls ein Reiter (noch) keine Größe hat: wie Blizzard selbst aus dem Atlas (SharedUIPanelTemplates.lua,
    -- SidePanelTabButtonMixin.CalculateTabSizeBasedOnTabArt: Breite, Höhe − 5)
    local info = C_Texture and Core.Call(C_Texture.GetAtlasInfo, "common-sidetab")
    local atlasW = type(info) == "table" and Core.Num(info.width) or 0
    local atlasH = type(info) == "table" and Core.Num(info.height) and math.max(0, info.height - 5) or 0
    local width, height = 0, 0
    for i, tab in ipairs(tabs) do
        local h, w = Core.Num(Read(tab, "GetHeight")), Core.Num(Read(tab, "GetWidth"))
        height = height + ((h and h > 0) and h or atlasH) + (i > 1 and UI.LEGACY_TAB_GAP or 0)
        width = math.max(width, (w and w > 0) and w or atlasW)
    end
    return y - height - UI.STACK_SPACE, width
end

-- Abstand des Seitenteils zum Fenster: breitester Reiter (eigene 32, Blizzards evtl. breiter) plus Luft.
function UI.DockGap(blizzardWidth)
    return math.max(UI.TAB_WIDTH, Core.Num(blizzardWidth) or 0) + UI.TAB_SPACE
end

-- Wie viel Platz ist rechts neben dem Fenster für das Seitenteil (in dessen eigenen Punkten, nach Abstand und
-- Randluft)? nil, wenn die Lage (noch) unbekannt ist. Weiterleitung auf ezCores Core.DockRoom (TL-23: eine
-- Platzrechnung für alle Seitenteile; Bildschirm-Punkte = Wert × effektive Skala), dazu die Randluft von ezTalent.
function UI.RoomRight(anchor, panel, gap)
    local room = Core.DockRoom(panel, anchor, "right", gap or 0)
    return room and room - UI.SCREEN_MARGIN or nil
end

-- Breite aus dem freien Platz: Wunschbreite, sonst was frei ist (mindestens UI.PANEL_MIN). room = nil (Lage
-- unbekannt) gilt als genug. → Breite, oder nil = nicht einmal die Mindestbreite
function UI.WidthFor(room)
    if room == nil or room >= UI.PANEL_WIDTH then return UI.PANEL_WIDTH end
    if room >= UI.PANEL_MIN then return math.floor(room) end
    return nil
end

-- Breite für das Seitenteil außen rechts. → Breite, oder nil = außen passt nicht einmal die Mindestbreite
function UI.PanelWidth(anchor, panel, gap)
    return UI.WidthFor(UI.RoomRight(anchor, panel, gap))
end

---------------------------------------------------------------------------
-- Platz machen (TL-13; Entscheidungsfrage 5, Empfehlung umgesetzt, Antwort offen): Passt das Seitenteil rechts nicht
-- neben das Talentfenster, rückt ezTalent Blizzards Fenster (PlayerSpellsFrame) nach links und verkleinert es, wo
-- das nicht reicht – nur solange ein Seitenteil offen ist, nur außerhalb des Kampfes, abschaltbar (Schalter
-- „makeRoom“). Blizzards eigene Lage und Größe sind der Ausgang: ezTalent merkt sie vor dem Rücken (Anker und Skala,
-- nur gelesen) und stellt sie beim Zuklappen bzw. Schließen wieder her – im Kampf erst danach (Core.AfterCombat).
-- Hat Blizzard (oder ezCores „Blizzard-Fenster verschieben“) das Fenster inzwischen selbst neu gesetzt, gilt dessen
-- Lage: dann wird nur die eigene Skala zurückgenommen. Nichts wird in Blizzards Tabellen geschrieben (Leitlinie 5).
---------------------------------------------------------------------------

UI.SHRINK_MIN = 0.7        -- kleiner macht ezTalent Blizzards Fenster nie – dann bleibt es beim letzten Ausweg innen

local function Same(a, b) return a ~= nil and b ~= nil and math.abs(a - b) < 0.01 end

UI.NEIGHBOR_AREAS = { "left", "center", "right", "doublewide" }   -- Plätze von Blizzards Fensterverwaltung

-- Bis wohin darf Blizzards Fenster nach links rücken (Bildschirm-Punkte)? Bis zum Rand samt Randluft – oder bis zum
-- rechten Rand eines anderen offenen Blizzard-Fensters links daneben (z. B. das Charakterfenster, das Blizzards
-- Fensterverwaltung links neben das Talentfenster setzt; nur gelesen über GetUIPanel). Fund der Gegenprüfung: sonst
-- rückte das Talentfenster über das Nachbarfenster.
function UI.LeftBound(frame, left, margin)
    local bound = margin
    local getPanel = rawget(_G, "GetUIPanel")
    if type(getPanel) ~= "function" then return bound end
    for _, area in ipairs(UI.NEIGHBOR_AREAS) do
        local other = Core.Call(getPanel, area)
        if type(other) == "table" and other ~= frame and Read(other, "IsVisible") == true then
            local r, e = Core.Num(Read(other, "GetRight")), Core.Num(Read(other, "GetEffectiveScale"))
            if r and e and r * e <= left + 1 then bound = math.max(bound, r * e) end
        end
    end
    return bound
end

-- Wie Blizzards Fenster weichen müsste, damit das Seitenteil außen mindestens UI.PANEL_MIN breit wird.
-- → { dx (Bildschirm-Punkte nach links), scale (Faktor, 1 = Größe bleibt), room (Platz rechts danach, in Punkten des
--   Seitenteils) } – dx = 0 und scale = 1, wenn es schon passt; nil, wenn die Lage unbekannt ist, es kein Fenster zum
--   Rücken gibt oder es kleiner als UI.SHRINK_MIN werden müsste
function UI.RoomPlan(host, panel)
    local frame = host.mover and host.mover()
    if type(frame) ~= "table" then return nil end
    local uiW, uiScale = Core.Num(Read(UIParent, "GetWidth")), Core.Num(Read(UIParent, "GetEffectiveScale"))
    local eff, left = Core.Num(Read(frame, "GetEffectiveScale")), Core.Num(Read(frame, "GetLeft"))
    local right, anchorEff = Core.Num(Read(host.anchor, "GetRight")), Core.Num(Read(host.anchor, "GetEffectiveScale"))
    if not (uiW and uiScale and eff and left and right and anchorEff) or eff <= 0 or anchorEff <= 0 then return nil end
    local panelEff = Core.Num(Read(panel, "GetEffectiveScale")) or anchorEff
    local screenW, margin = uiW * uiScale, UI.SCREEN_MARGIN * uiScale
    left, right = left * eff, right * anchorEff                       -- Bildschirm-Punkte
    local need = (UI.PANEL_MIN + 1 + host.gap + UI.SCREEN_MARGIN) * panelEff       -- 1 Punkt Luft gegen Rundung
    local bound = UI.LeftBound(frame, left, margin)
    local freeRight, freeLeft = screenW - right, math.max(0, left - bound)
    local function Room(r, scale) return r / (panelEff * scale) - host.gap - UI.SCREEN_MARGIN end
    if freeRight >= need then return { dx = 0, scale = 1, room = Room(freeRight, 1) } end
    if freeRight + freeLeft >= need then
        local dx = need - freeRight
        return { dx = dx, scale = 1, room = Room(freeRight + dx, 1) }
    end
    -- nach links an den Rand (bzw. ans Nachbarfenster) und verkleinern: Fenster samt Seitenteil passen mit dem Faktor
    -- f nebeneinander
    local f = (screenW - bound) / (right - left + need)
    if f < UI.SHRINK_MIN then return nil end
    return { dx = freeLeft, scale = f, room = Room(screenW - bound - (right - left) * f, f) }
end

-- Liegt Blizzards Fenster noch da, wo ezTalent es hingesetzt hat?
function UI.StillMoved(saved, frame)
    if type(saved) ~= "table" or type(frame) ~= "table" then return false end
    local point, rel, relPoint, x, y = Core.Call(frame.GetPoint, frame, 1)
    return point == "TOPLEFT" and rel == UIParent and relPoint == "BOTTOMLEFT" and Same(Core.Num(x), saved.x)
        and Same(Core.Num(y), saved.y)
end

-- Darf und kann ezTalent gerade Platz machen?
function UI.CanMakeRoom(host, panel)
    return ns.Enabled("makeRoom") and not Core.InCombat() and host.mover ~= nil and UI.RoomPlan(host, panel) ~= nil
end

-- Blizzards Fenster rücken bzw. verkleinern. → Platz rechts danach (Punkte des Seitenteils) oder nil (nichts getan)
function UI.MakeRoom(host, panel)
    if not ns.Enabled("makeRoom") or Core.InCombat() then return nil end
    local frame = host.mover and host.mover()
    local plan = UI.RoomPlan(host, panel)
    if not plan or (plan.dx <= 0 and plan.scale >= 1) then return nil end
    local scale = Core.Num(Read(frame, "GetScale")) or 1
    local eff, left, top = Core.Num(Read(frame, "GetEffectiveScale")), Core.Num(Read(frame, "GetLeft")),
        Core.Num(Read(frame, "GetTop"))
    if not (eff and left and top) or scale <= 0 then return nil end
    -- Ausgang merken: Blizzards Anker und Skala. Schon gerückt, aber inzwischen neu gesetzt: die neue Lage gilt, die
    -- ursprüngliche Skala bleibt (die jetzige ist noch die eigene).
    local old = host.moved
    local saved = { scale = scale, points = {} }
    if old and Same(scale, old.newScale) then saved.scale = old.scale end
    if old and UI.StillMoved(old, frame) then
        saved.points = old.points
    else
        for i = 1, Core.Num(Read(frame, "GetNumPoints")) or 0 do saved.points[i] = { Core.Call(frame.GetPoint, frame, i) } end
    end
    local newScale = scale * plan.scale
    local newEff = eff / scale * newScale
    local x, y = (left * eff - plan.dx) / newEff, top * eff / newEff      -- oben bleibt, wo es war
    if plan.scale < 1 then frame:SetScale(newScale) end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    saved.x, saved.y, saved.newScale = x, y, newScale
    host.moved = saved
    return plan.room
end

-- Braucht ein offenes Seitenteil den gemachten Platz noch? (Fenster offen, Seitenteil gezeigt, Schalter an)
local function StillNeeded(host)
    local panel = host.open and host.panels[host.open]
    return ns.Enabled("makeRoom") and panel ~= nil and panel:IsShown() and Read(host.parent, "IsVisible") == true
end

-- Nach dem Kampf: Wurde das Seitenteil im Kampf zugeklappt und wieder geöffnet (bzw. das Fenster geschlossen und
-- wieder geöffnet), steht es am noch gerückten Fenster außen – dann bleibt der Platz, und das Seitenteil wird nur neu
-- gesetzt. Sonst zurückstellen und ein offenes Seitenteil neu setzen (Schalter im Kampf aus: dann innen mit Hinweis),
-- damit es nicht über den Bildschirmrand ragt (Fund der Gegenprüfung).
function UI.GiveRoomAfterCombat(host)
    if StillNeeded(host) or UI.GiveRoom(host) then
        ns.Try("UI", UI.PlaceOpen, host)
        UI.Refresh()          -- Kopf neu (Hinweis „innen“ an bzw. aus)
    end
end

-- Blizzards Lage und Größe wiederherstellen (Seitenteil zu, Fenster zu, Schalter aus). → true, wenn zurückgestellt
function UI.GiveRoom(host)
    local saved = host and host.moved
    if not saved then return false end
    local frame = host.mover and host.mover()
    if type(frame) ~= "table" then
        host.moved = nil
        return false
    end
    if Core.InCombat() then
        Core.AfterCombat(function() ns.Try("UI", UI.GiveRoomAfterCombat, host) end,
            "ezTalent.giveRoom." .. tostring(host.kind), ADDON)
        return false
    end
    host.moved = nil
    if Same(Core.Num(Read(frame, "GetScale")), saved.newScale) then frame:SetScale(saved.scale) end
    if UI.StillMoved(saved, frame) then
        frame:ClearAllPoints()
        for _, p in ipairs(saved.points) do
            if p[1] then frame:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
        end
    end
    return true
end

-- Seitenteil setzen: außen rechts am Fenster, so breit wie dort Platz ist. Passt nicht einmal die Mindestbreite und
-- ist roomOK gesetzt (das Seitenteil wird gerade gezeigt), macht ezTalent Platz (UI.MakeRoom); geht auch das nicht,
-- liegt es als letzter Ausweg innen rechts. → true, wenn innen
function UI.Place(host, panel, roomOK)
    local width = UI.PanelWidth(host.anchor, panel, host.gap)
    if width == nil and roomOK then
        local room = UI.MakeRoom(host, panel)
        if room then width = UI.WidthFor(room) end
    end
    local inside = width == nil
    width = width or UI.PANEL_WIDTH
    if inside then
        local inset = host.inset or UI.INSET
        panel:ClearAllPoints()
        panel:SetPoint("TOPRIGHT", host.anchor, "TOPRIGHT", -inset.right, -inset.top)
        panel:SetPoint("BOTTOMRIGHT", host.anchor, "BOTTOMRIGHT", -inset.right, inset.bottom)
    else
        Core.Dock(panel, host.anchor, { gap = host.gap })
    end
    panel:SetWidth(width)
    panel.width, panel.inside = width, inside
    if panel.Layout then panel:Layout(width) end
    return inside
end

-- Knöpfe eines Seitenteils als Raster von unten nach oben: order = Knöpfe in Lesereihenfolge, wide = Knopf über die
-- ganze Breite in der untersten Reihe (oder nil). Drei je Reihe ab UI.BUTTON_COLUMNS_AT, sonst zwei.
-- → Höhe des Knopfbereichs (für die Unterkante der Liste)
function UI.LayoutButtons(panel, width, order, wide)
    local left, gapX, rowH, bottom = 14, 4, 24, 10
    local cols = width >= UI.BUTTON_COLUMNS_AT and 3 or 2
    local buttonW = math.floor((width - 2 * left - (cols - 1) * gapX) / cols)
    local rows = math.ceil(#order / cols)
    local base = bottom
    if wide then
        wide:ClearAllPoints()
        wide:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", left, bottom)
        wide:SetWidth(width - 2 * left)
        base = bottom + rowH
    end
    for i, button in ipairs(order) do
        local row, col = math.floor((i - 1) / cols), (i - 1) % cols
        button:ClearAllPoints()
        button:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", left + col * (buttonW + gapX), base + (rows - 1 - row) * rowH)
        button:SetWidth(buttonW)
    end
    return base + rows * rowH
end

-- Geometrie des Seitenteils (Spieltest 15.11.2026: Titel „Vo…“ abgeschnitten, Kopf als ungegliederter Block). Alles
-- relativ zum Seitenteil, von oben: Blizzards Titelleiste (Titel zwischen linkem Rand und Schließen-Kreuz), darunter der
-- Kopf (headTitle, dann head; rechts daneben der Knopf „?“ mit Legende und Einzelheiten), dann die Liste bis zu den
-- Knöpfen. Jedes Teil hängt am vorigen – nichts überlappt, wie hoch der umbrochene Text auch ist (Tests/seitenteil.lua).
UI.TITLE_LEFT, UI.TITLE_RIGHT, UI.TITLE_TOP = 8, 26, -5   -- Schließen-Kreuz der Vorlage: 28 breit oben rechts (Camelot)
UI.HEAD_TOP = 30           -- Kopf beginnt unter der Titelleiste (ButtonFrameTemplate: Titelleiste 0 bis −24)
UI.HEAD_LEFT, UI.HEAD_RIGHT = 14, 14
UI.HELP_SIZE = 18          -- Knopf „?“ rechts neben der ersten Kopfzeile (oben 2 Punkte über ihr)
UI.HEAD_SPACING = 2        -- Zeilenabstand im Kopf
UI.HEAD_TITLE_GAP = 4      -- headTitle → head
UI.HEAD_LIST_GAP = 8       -- Kopf → Liste

-- Titeltext eines Seitenteils: Blizzards TitleText der Vorlage, sonst der eigene Ersatz.
function UI.TitleText(panel)
    local container = type(panel.TitleContainer) == "table" and panel.TitleContainer
    if container and type(container.TitleText) == "table" then return container.TitleText end
    if type(panel.TitleText) == "table" then return panel.TitleText end
    if type(panel.GetTitleText) == "function" then
        local fs = Core.Call(panel.GetTitleText, panel)
        if type(fs) == "table" then return fs end
    end
    return panel.title
end

-- Titel über die ganze Breite (ohne Umbruch, mittig) – direkt am Seitenteil, nicht an Blizzards Titel-Rahmen.
function UI.AnchorTitle(panel)
    local fs = panel.titleText
    if type(fs) ~= "table" or type(fs.SetPoint) ~= "function" then return end
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", panel, "TOPLEFT", UI.TITLE_LEFT, UI.TITLE_TOP)
    fs:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -UI.TITLE_RIGHT, UI.TITLE_TOP)
    Core.Call(fs.SetWordWrap, fs, false)
end

-- Rechter Abstand der ersten Kopfzeile: Platz für den Knopf „?“, falls das Seitenteil einen hat.
function UI.HeadRight(panel)
    return UI.HEAD_RIGHT + (panel.help and (UI.HELP_SIZE + 4) or 0)
end

-- Kopf verankern: headTitle oben (rechts Platz für „?“), head darunter über die volle Breite; ohne headTitle steht
-- head selbst oben.
function UI.AnchorHead(panel)
    local t, h = panel.headTitle, panel.head
    local right = UI.HeadRight(panel)
    t:ClearAllPoints()
    h:ClearAllPoints()
    t:SetPoint("TOPLEFT", panel, "TOPLEFT", UI.HEAD_LEFT, -UI.HEAD_TOP)
    t:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -right, -UI.HEAD_TOP)
    if t:IsShown() then
        h:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -UI.HEAD_TITLE_GAP)
        h:SetPoint("TOPRIGHT", t, "BOTTOMRIGHT", right - UI.HEAD_RIGHT, -UI.HEAD_TITLE_GAP)
    else
        h:SetPoint("TOPLEFT", panel, "TOPLEFT", UI.HEAD_LEFT, -UI.HEAD_TOP)
        h:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -right, -UI.HEAD_TOP)
    end
    if panel.help then
        panel.help:ClearAllPoints()
        panel.help:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -UI.HEAD_RIGHT, -UI.HEAD_TOP + 2)
    end
end

local function NewPanel(host, title)
    local ok, panel = pcall(CreateFrame, "Frame", nil, host.parent, "ButtonFrameTemplate")
    if not (ok and panel) then panel = CreateFrame("Frame", nil, host.parent) end
    Core.Call(rawget(_G, "ButtonFrameTemplate_HidePortrait"), panel)
    panel:SetWidth(UI.PANEL_WIDTH)
    local level = Core.Num(Read(host.parent, "GetFrameLevel"))
    if level then panel:SetFrameLevel(level + UI.PANEL_LEVEL) end
    if type(panel.SetTitle) == "function" then
        Core.Call(panel.SetTitle, panel, title)
    else
        panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        panel.title:SetText(title)
    end
    -- Titel: Blizzards Titeltext der Vorlage (bzw. der eigene Ersatz) – über die ganze Breite zwischen linkem Rand und
    -- Schließen-Kreuz, ohne Umbruch (Spieltest 15.11.2026: „Vo…“). Gesetzt in panel:Layout.
    panel.titleText = UI.TitleText(panel)
    if not panel.titleText then          -- Vorlage ohne Titeltext: eigener in Blizzards Schrift
        panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        panel.title:SetText(title)
        panel.titleText = panel.title
    end
    -- Kopf in zwei Teilen: headTitle (eine gold Zeile, z. B. „Vorschau: Name · 30/0/21“) und head (die Zeilen darunter).
    -- Beide Anker oben: die Breite steht fest, die Höhe folgt dem umbrochenen Text (mit einem Anker „RIGHT“ läge die
    -- Mitte des Textfelds auf der Mitte des Seitenteils, und die Liste begänne erst darunter).
    panel.headTitle = panel:CreateFontString(nil, "ARTWORK", UI.FONTS.headTitle)
    panel.head = panel:CreateFontString(nil, "ARTWORK", UI.FONTS.head)
    for _, fs in ipairs({ panel.headTitle, panel.head }) do
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        Core.Call(fs.SetWordWrap, fs, true)
        Core.Call(fs.SetSpacing, fs, UI.HEAD_SPACING)
    end
    panel.headTitle:Hide()
    panel.scroll = CreateScroll(panel)
    -- Breite folgt dem Platz neben dem Fenster (UI.Place): Liste und Knöpfe richten sich danach. Die Liste beginnt
    -- unter dem Kopf (der umbricht und verschieden hoch ist) und endet über den Knöpfen (panel.LayoutButtons, falls
    -- das Seitenteil welche hat → Höhe des Knopfbereichs).
    function panel:Layout(width)
        self.scroll.content:SetWidth(width - 40)
        UI.AnchorTitle(self)
        UI.AnchorHead(self)
        local bottom = self.LayoutButtons and self:LayoutButtons(width) or 14
        self.buttonsTop = bottom
        self.scroll:ClearAllPoints()
        self.scroll:SetPoint("TOPLEFT", self.head, "BOTTOMLEFT", 0, -UI.HEAD_LIST_GAP)
        self.scroll:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -30, bottom)
    end
    UI.Place(host, panel)
    panel:Hide()
    -- OnHide kommt im Spiel auch, wenn Blizzards Fenster zugeht (das Seitenteil bleibt dabei „shown“): Nur wenn das
    -- Seitenteil selbst zugeklappt wurde, ist es nicht mehr offen.
    panel:HookScript("OnHide", function(self)
        if self:IsShown() then return end
        if host.open and host.panels[host.open] == panel then
            host.open = nil
            UI.RememberOpen(host)       -- auch über das Schließen-Kreuz des Seitenteils zugeklappt: gemerkt
        end
        if not host.switching and not host.open then UI.GiveRoom(host) end   -- TL-13: Blizzards Lage zurück
        TourSoon(host)
    end)
    return panel
end

-- Hinweis, wenn das Seitenteil aus Platzmangel innen liegt (sonst nil).
function UI.InsideText(panel)
    if not (panel and panel.inside) then return nil end
    -- Wege über Core.SettingsPathText (T18-18): Fenster verschieben steht auf ezCores Übersichtsseite
    return ns.Tone("orange", L.HEAD_INSIDE:format(Core.SettingsPathText(nil, nil, "OPT_moveFrames"))
        .. (ns.Enabled("makeRoom") and "" or (" " .. L.HEAD_INSIDE_ROOM:format(L.OPT_makeRoom,
            ns.PathText("OPT_HEADER_TEMPLATES", "OPT_makeRoom")))))
end

-- Kopf eines Seitenteils: Text des Fensters (bei Auswirkungen und Twinks dazu der Hinweis „innen“; das Seitenteil
-- „Vorlagen“ nennt ihn selbst unter seinen Hinweisen, UI.HeadLines). title (freiwillig): gold erste Zeile.
local function SetHead(panel, text, title, noInside)
    local inside = not noInside and UI.InsideText(panel)
    if inside then text = (text ~= "" and (text .. "\n") or "") .. inside end
    panel.headTitle:SetText(title or "")
    panel.headTitle:SetShown(title ~= nil and title ~= "")
    panel.head:SetText(text)
    UI.AnchorHead(panel)
end

---------------------------------------------------------------------------
-- Meldungen
---------------------------------------------------------------------------

local function NameList(ctx, ids, limit)
    local names = {}
    for i, id in ipairs(ids) do
        if i > (limit or 5) then
            names[#names + 1] = ezCore.More(#ids - (limit or 5), true)
            break
        end
        names[#names + 1] = Traits.NodeName(ctx.configID, id)
    end
    return table.concat(names, ", ")
end

-- Warum Talente nach „Übernehmen“ fehlen (TL-09): je Talent, was der Client als ungedeckt meldet – Schwelle
-- („benötigt 10 Punkte im Baum (hast 5)“), Stufe oder Vorgänger. Ohne Angaben des Clients leer (dann bleibt es beim
-- allgemeinen „Voraussetzung, Stufe oder zu wenig Punkte“). Mehr als limit Talente mit Grund: „und n weitere“ zählt
-- nur die übrigen mit Grund (Fund der Gegenprüfung: Talente ohne Grund bekämen nie eine Zeile). → Text oder ""
function UI.MissingReasons(ctx, ids, limit)
    limit = limit or 5
    local parts, withReason, incoming = {}, 0, nil
    for _, id in ipairs(ids or {}) do
        local node = Traits.Node(ctx.configID, id)
        if node then
            incoming = incoming or Traits.Incoming(Traits.Nodes(ctx.configID, ctx.treeID))
            local reqs = Traits.Requirements(ctx.configID, ctx.treeID, node, incoming)
            if #reqs > 0 then
                withReason = withReason + 1
                if withReason <= limit then
                    local texts = {}
                    for i, req in ipairs(reqs) do texts[i] = Traits.RequirementText(ctx.configID, req) end
                    parts[#parts + 1] = Traits.NodeName(ctx.configID, id) .. ": " .. table.concat(texts, "; ")
                end
            end
        end
    end
    if withReason > limit then parts[#parts + 1] = ezCore.More(withReason - limit, true) end
    return table.concat(parts, " · ")
end

function UI.ReportApply(ctx, name, result, why)
    if not result then
        -- Kampf: ezCores Satz zur Kampfsperre (T18-1)
        ns.Print(why == "combat" and ns.CombatText() or L["APPLY_FAIL_" .. tostring(why)] or L.APPLY_FAIL_noconfig)
        return
    end
    local resetFailed = result.resetTried and not result.reset
    -- nur ein Teil der Währungen zurückgesetzt (T7-NT6): eigener Satz, damit niemand einen sauberen Baum erwartet
    if resetFailed then ns.Print(result.resetPartial and L.APPLY_RESET_PARTIAL or L.APPLY_RESET_FAIL) end
    ns.Print(L.APPLY_DONE:format(name, result.bought))
    if #result.missing > 0 then
        ns.Print(L.APPLY_MISSING:format(NameList(ctx, result.missing)))
        local reasons = UI.MissingReasons(ctx, result.missing)
        if reasons ~= "" then ns.Print(L.APPLY_MISSING_WHY:format(reasons)) end
    end
    if #result.unknown > 0 then ns.Print(L.APPLY_UNKNOWN:format(#result.unknown)) end
    if result.otherChoice and #result.otherChoice > 0 then
        ns.Print(L.APPLY_OTHER_CHOICE:format(NameList(ctx, result.otherChoice)))
    end
    if #result.extra > 0 then
        -- Die Empfehlung „Zurücksetzen und anwenden“ nur, wenn nicht gerade das Zurücksetzen fehlgeschlagen ist
        local useExtraClass = ctx.kind == "class" and not resetFailed
        ns.Print((useExtraClass and L.APPLY_EXTRA_CLASS or L.APPLY_EXTRA):format(NameList(ctx, result.extra)))
    end
    if result.bought > 0 or result.reset then ns.Print(L.APPLY_CONFIRM) end
end

---------------------------------------------------------------------------
-- Seitenteil „Vorlagen“
---------------------------------------------------------------------------

local function Selected(host, ctx)
    local name = host.selected
    if name and Templates.Get(ctx.scope, name) then return name, Templates.Get(ctx.scope, name) end
    host.selected = nil
    return nil
end

---------------------------------------------------------------------------
-- Vorschau (Plan.lua): Was ist in den Baum geladen?
---------------------------------------------------------------------------

-- Der geladene Plan dieses Fensters (eigene Vorlage, Vorauswahl oder neuer Plan), sonst nil = „Aktuelle Verteilung“.
-- host.selected (Name einer eigenen Vorlage) führt: Der Plan einer eigenen Vorlage gehört immer zu ihr; eine
-- Vorauswahl oder ein neuer Plan gilt nur, solange keine eigene Vorlage gewählt ist. Ist nichts gewählt, wird je Baum
-- einmal der gemerkte Plan geholt („liegt die Vorlage direkt immer vor, wenn ich das Fenster öffne“).
function UI.ActivePlan(host, ctx)
    if not (ctx and ctx.scope) then return nil end
    local plan = host.plan
    if plan and plan.scope ~= ctx.scope then plan, host.plan = nil, nil end
    local name = Selected(host, ctx)
    if name then
        if not (plan and plan.kind == "own" and plan.key == name) then
            plan = Plan.FromTemplate(ctx.scope, name)
            host.plan = plan
        end
    elseif plan and plan.kind == "own" then
        plan, host.plan = nil, nil
    end
    if not plan and not name and host.recalled ~= ctx.scope then
        host.recalled = ctx.scope
        plan = Plan.Recall(ctx)
        host.plan = plan
        if plan and plan.kind == "own" then host.selected = plan.key end
    end
    return plan
end

-- Vor dem Wechsel der Auswahl: ungespeicherte Änderungen der Vorschau nur nach Rückfrage verwerfen.
local function LeavePlan(host, fn)
    local plan = host.plan
    if plan and plan.edited then
        Core.Confirm(L.ASK_PLAN_DISCARD:format(plan.name or "?"), fn, { alert = true })
    else
        fn()
    end
end

local function Pick(host, ctx, selected, plan)
    host.selected, host.plan, host.recalled = selected, plan, ctx.scope
    if not (selected or plan) then host.editing = false end
    Plan.Remember(ctx.scope, UI.ActivePlan(host, ctx))
    UI.Refresh()
end

-- Klick auf eine eigene Vorlage: als Vorschau laden.
function UI.SelectOwn(host, name)
    local ctx = UI.Context(host)
    if not (ctx and ctx.scope) then return end
    LeavePlan(host, function() Pick(host, ctx, name, nil) end)
end

-- Chatzeile nach dem Laden einer nicht ganz zugeordneten Vorauswahl: EINE Zeile je Laden; die Abhilfe („Talente
-- erheben“) hängt nur an der ersten in der Sitzung (Spieltest 15.11.2026: je Laden zwei Zeilen, dieselbe Abhilfe
-- mehrmals untereinander). Tooltip und Kopf des Seitenteils nennen sie weiter jedes Mal. → Text oder nil (alles da)
function UI.PresetLoadLine(plan)
    if not (type(plan) == "table" and plan.total and plan.total > 0 and (plan.found or 0) < plan.total) then return nil end
    local text
    if (plan.found or 0) == 0 then
        text = L.PRESET_PLAN_NONE:format(plan.name or "?")
    else
        text = L.PRESET_PLAN_PARTIAL:format(plan.name or "?", plan.found, plan.total, UI.JoinNames(plan.missing, 5))
    end
    if not UI.surveyHinted then
        UI.surveyHinted = true
        text = text .. " " .. ns.SurveyShort()
    end
    return text
end

-- Klick auf eine Vorauswahl: als Vorschau laden – nichts wird kopiert oder gesetzt (Spieltest 14.11.2026: der Klick
-- kopierte sofort, zweimal geklickt gab „… (2)“). Teilweise zugeordnet zeigt die Vorschau, was zugeordnet ist.
function UI.SelectPreset(host, preset)
    local ctx = UI.Context(host)
    if not (ctx and ctx.scope) then return end
    LeavePlan(host, function()
        local plan = Plan.FromPreset(preset, ctx)
        Pick(host, ctx, nil, plan)
        local line = UI.PresetLoadLine(plan)
        if line then ns.Print(line) end
    end)
end

-- Klick auf „Aktuelle Verteilung“: keine Vorschau, der Baum wie er ist.
function UI.SelectCurrent(host)
    local ctx = UI.Context(host)
    if not (ctx and ctx.scope) then return end
    LeavePlan(host, function() Pick(host, ctx, nil, nil) end)
end

-- „Anpassen“: Planen an/aus. Ohne geladene Vorschau beginnt ein neuer Plan mit der aktuellen Verteilung; wird er
-- nicht geändert, verschwindet er beim Ausschalten wieder.
function UI.ToggleEdit(host)
    local ctx = UI.Context(host)
    if not (ctx and ctx.scope) then return end
    if not Plan.CanShow(host.source()) then ns.Print(L.PLAN_NO_TREE) return end
    if host.editing then
        UI.StopEditing(host)
    else
        host.editing = true
        if not UI.ActivePlan(host, ctx) then host.plan, host.recalled = Plan.FromCurrent(ctx), ctx.scope end
    end
    UI.Refresh()
end

-- Planen beenden; ein neuer, nie geänderter Plan (nur die aktuelle Verteilung) verschwindet dabei wieder.
function UI.StopEditing(host)
    host.editing = false
    if host.plan and host.plan.kind == "new" and not host.plan.edited then host.plan = nil end
end

-- Klick auf ein Talent im Planen-Modus (Plan.Sync ruft das): ändert nur die Vorschau.
function UI.AdjustPlan(host, nodeID, delta)
    local ctx = UI.Context(host)
    local plan = ctx and UI.ActivePlan(host, ctx)
    local node = plan and Traits.Node(ctx.configID, nodeID)
    if not node then return end
    if Plan.Adjust(plan, node, delta) then
        Plan.Remember(ctx.scope, plan)
        -- vorgemerkte Vorschau weiter angepasst: die Vormerkung bekommt die neuen Ränge (Nr. 29)
        if UI.IsQueuedHere(host, ctx) then UI.SetQueued(UI.QueueRecord(ctx, plan)) end
        UI.Refresh()
    end
end

function UI.Save(host)
    local ctx = UI.Context(host)
    if not (ctx and ctx.configID and ctx.treeID and ctx.scope) then ns.Print(L.APPLY_FAIL_noconfig) return end
    local plan = UI.ActivePlan(host, ctx)
    -- Unveränderte Vorauswahl: als eigene Vorlage kopieren (unvollständig zugeordnet nur nach Rückfrage, T1)
    if plan and plan.kind == "preset" and not plan.edited and plan.preset then
        UI.CopyPreset(host, ctx, plan.preset)
        return
    end
    local default = host.selected or Templates.UniqueName(ctx.scope, plan and plan.name or L.TEMPLATE_DEFAULT_NAME)
    Core.AskText(L.ASK_NAME, default, function(text)
        local name = Templates.CleanName(text)
        if name == "" then return end
        local function Do()
            -- Mit Vorschau wird die Vorschau gespeichert (die Zahlen an den Talenten), sonst der Baum, wie er steht
            local snap, meta
            if plan then
                snap = { nodes = plan.tpl.nodes, choices = plan.tpl.choices, tree = ctx.treeID, order = plan.tpl.order,
                    orderFrom = plan.tpl.orderFrom, orderEdited = plan.tpl.orderEdited }
                local split = Plan.Split(plan, ctx)
                meta = { groups = #split > 0 and split or nil, tree = ctx.treeID,
                    primary = #split == 0 and plan.tpl.primary or nil }
            else
                snap = Traits.Snapshot(ctx.configID, ctx.treeID, false)
                meta = { groups = ctx.kind == "class" and Traits.Groups(ctx.configID, ctx.treeID) or nil, tree = ctx.treeID }
            end
            local saved = Templates.Save(ctx.scope, name, snap, meta)
            if saved then
                host.selected, host.plan, host.recalled = saved, nil, ctx.scope
                Plan.Remember(ctx.scope, UI.ActivePlan(host, ctx))
                ns.Print(L.SAVED:format(saved, Traits.Points(snap)))
            end
            UI.Refresh()
        end
        -- Jede vorhandene Vorlage nur nach Rückfrage überschreiben – auch die gerade gewählte (Tooltip BTN_SAVE_TIP)
        if Templates.Get(ctx.scope, name) then
            Core.Confirm(L.ASK_OVERWRITE:format(name), Do)
        else
            Do()
        end
    end, Templates.MAX_NAME)
end

-- Erinnerung nach dem Übernehmen einer unvollständig zugeordneten Vorschau: eigene Vorlage mit Kennzeichen (T1) oder
-- Vorauswahl, deren Talente der Client nicht alle kennt.
local function RemindPartial(plan)
    local tpl = plan.tpl
    if tpl.unmatched then
        ns.Print(L.APPLY_PARTIAL:format(tpl.unmatched, tpl.matchTotal or tpl.unmatched))
    elseif plan.kind == "preset" and plan.total and (plan.found or 0) < plan.total then
        ns.Print(L.APPLY_PARTIAL:format(plan.total - (plan.found or 0), plan.total))
    end
end

-- Warum es mit dieser Vorschau nichts zu übernehmen gibt: "unmatched" (Vorauswahl, von der kein Talent im Client
-- zugeordnet ist), "empty" (Plan ohne einen Punkt), sonst nil. Gegenprüfung 14.11.2026: Mit einer leeren Vorschau
-- setzte „Übernehmen“ nichts, empfahl aber „Zurücksetzen und übernehmen“ – und das setzte den ganzen Baum zurück,
-- ohne etwas zu verteilen. Beide Knöpfe sind deshalb gesperrt und nennen den Grund.
function UI.EmptyReason(plan)
    if not Plan.IsEmpty(plan) then return nil end
    if plan.kind == "preset" and plan.total and plan.total > 0 and (plan.found or 0) == 0 then return "unmatched" end
    return "empty"
end

-- Grund, warum „Übernehmen“ nicht geht ("select", "locked", "commit", "unmatched", "empty"), sonst nil. Gleiche
-- Prüfung für Knopf (gesperrt + Tooltip) und Klick.
function UI.ApplyBlocker(host, ctx)
    ctx = ctx or UI.Context(host)
    local plan = ctx and UI.ActivePlan(host, ctx)
    if not plan then return "select" end
    if ctx.locked then return "locked" end
    if ctx.committing then return "commit" end
    return UI.EmptyReason(plan)
end

local APPLY_BLOCK_TEXT = { select = "SELECT_FIRST", locked = "APPLY_LOCKED" }
local SHARED_BLOCK_TEXT = { commit = "COMMIT_BUSY" }    -- gleicher Satz für „Übernehmen“ und „Zurücksetzen und übernehmen“

-- Text zu einem Grund aus UI.ApplyBlocker bzw. UI.ResetBlocker. Kampf: ezCores Satz (T18-1); „unmatched“ nennt den Weg
-- zu „Talente erheben“ (Core.SettingsPathText, T18-18).
function UI.BlockerText(why, apply)
    if why == "combat" then return ns.CombatText() end
    if why == "unmatched" then return L.RESET_NO_unmatched:format(ns.SurveyPath()) end
    return L[SHARED_BLOCK_TEXT[why] or (apply and APPLY_BLOCK_TEXT[why]) or ("RESET_NO_" .. tostring(why))] or L.RESET_NO_noapi
end

-- Vermächtnis mit „Vor dem Übernehmen zurücksetzen“ (legacyReset): Grund, warum das Zurücksetzen hier nicht geht
-- ("norefund", "noapi", "noconfig"), sonst nil. Im Kampf nil – dann ändert „Übernehmen“ ohnehin nichts (T7-NT3,
-- Gesamtreview 18.11.2026: vorher rief ezTalent ResetTree auch an Bäumen, die Blizzard nicht erstattet).
function UI.LegacyResetBlocked(ctx)
    if not (ctx and ctx.kind == "legacy" and ns.Enabled("legacyReset")) then return nil end
    local ok, why = Traits.CanReset(ctx.configID, ctx.treeID)
    if ok or why == "combat" or why == "noconfig" then return nil end    -- noconfig meldet Traits.Apply selbst
    return why or "noapi"
end

-- „Übernehmen“: die Punkte der geladenen Vorschau gestaffelt in Blizzards Baum setzen, soweit Stufe und Punkte reichen.
function UI.Apply(host)
    local ctx = UI.Context(host)
    local plan = ctx and UI.ActivePlan(host, ctx)
    local blocker = UI.ApplyBlocker(host, ctx)
    if blocker then ns.Print(UI.BlockerText(blocker, true)) return end
    local name, tpl = plan.name, plan.tpl
    local noReset = UI.LegacyResetBlocked(ctx)
    local reset = ctx.kind == "legacy" and ns.Enabled("legacyReset") and not noReset
    local function Do()
        if noReset then ns.Print(L["APPLY_LEGACY_NORESET_" .. noReset] or L.APPLY_LEGACY_NORESET_noapi) end
        local result, why = Traits.Apply(ctx.configID, ctx.treeID, tpl, { reset = reset, frame = host.source() })
        if result then Templates.NoteApplied(ctx.scope, name, ctx.configID) end
        UI.ReportApply(ctx, name, result, why)
        if result then
            RemindPartial(plan)
            UI.OfferLinks(ctx, plan)
        end
        UI.Refresh()
    end
    -- Vermächtnis setzt vorher zurück: noch nicht übernommene Vorschau-Punkte gingen dabei verloren → erst nachfragen
    if reset and Traits.HasStaged(ctx.configID) then
        Core.Confirm(L.ASK_LEGACY_RESET:format(name), Do, { alert = true })
    else
        Do()
    end
end

---------------------------------------------------------------------------
-- Vorlage für die inaktive Spezialisierung vormerken (Nr. 29 der Entscheidung des Nutzers vom 16.11.2026, Frage 4 in
-- docs/roadmap/ezTalent.md – Empfehlung umgesetzt, Antwort offen). Blizzard sperrt den Baum der inaktiven
-- Spezialisierung; dort heißt „Übernehmen“ deshalb „Vormerken“: ezTalent merkt sich die geladene Vorschau samt
-- Konfiguration (ezTalentDB.chars[<Charakter>].queued, ohne Namen anderer). Ist diese Spezialisierung aktiv und das
-- Talentfenster offen, setzt ezTalent die Punkte wie „Übernehmen“ – nur als Vorschau, endgültig erst mit Blizzards Knopf.
-- Umkehrbar: ein zweiter Klick hebt die Vormerkung auf. Die Vormerkung trägt den Plan selbst (Plan.Record): Die
-- Vorschau ist je Klasse eine (Templates.ClassScope gilt für beide Spezialisierungen) – wer danach an der aktiven
-- Spezialisierung eine andere Vorschau lädt, behält die Vormerkung (Fund der Gegenprüfung 16.11.2026). Sie verfällt
-- nur, wenn es ihre Vorlage bzw. Vorauswahl nicht mehr gibt; ungespeicherte Änderungen werden nur nach Rückfrage verworfen.
---------------------------------------------------------------------------

local function QueueStore(create)
    local key = ns.charKey or Core.charKey
    if not (ns.db and key and type(ns.db.chars) == "table") then return nil end
    local c = ns.db.chars[key]
    if type(c) ~= "table" then
        if not create then return nil end
        c = {}
        ns.db.chars[key] = c
    end
    return c
end

-- Die Vormerkung dieses Charakters ({ config, name, kind, plan = Plan.Record(…) }) oder nil.
function UI.Queued()
    local c = QueueStore(false)
    local q = c and c.queued
    if type(q) ~= "table" or not tonumber(q.config) or type(q.name) ~= "string" then return nil end
    return q
end

function UI.SetQueued(rec)
    local c = QueueStore(rec ~= nil)
    if c then c.queued = rec end
end

-- Lässt sich die geladene Vorschau hier vormerken? (inaktive Spezialisierung, Vorschau mit Punkten)
function UI.CanQueue(host, ctx)
    ctx = ctx or UI.Context(host)
    local plan = ctx and ctx.inactive and UI.ActivePlan(host, ctx)
    return plan ~= nil and plan ~= false and UI.EmptyReason(plan) == nil
end

-- Ist genau diese Vorschau für diesen Baum vorgemerkt?
function UI.IsQueuedHere(host, ctx)
    ctx = ctx or UI.Context(host)
    local plan = ctx and UI.ActivePlan(host, ctx)
    local q = UI.Queued()
    return q ~= nil and plan ~= nil and q.config == ctx.configID and q.name == plan.name
end

-- Klick auf „Vormerken“ bzw. „Aufheben“.
function UI.ToggleQueue(host)
    local ctx = UI.Context(host)
    if not UI.CanQueue(host, ctx) then
        ns.Print(UI.BlockerText(UI.ApplyBlocker(host, ctx) or "locked", true))
        return
    end
    local plan = UI.ActivePlan(host, ctx)
    if UI.IsQueuedHere(host, ctx) then
        UI.SetQueued(nil)
        ns.Print(L.QUEUE_CANCELLED:format(plan.name or "?"))
    else
        UI.SetQueued(UI.QueueRecord(ctx, plan))
        ns.Print(L.QUEUE_SET:format(plan.name or "?"))
    end
    UI.Refresh()
end

-- Merkbare Vormerkung: Konfiguration und der Plan selbst (eigene Tabellen – spätere Vorschauen ändern sie nicht).
function UI.QueueRecord(ctx, plan)
    return { config = ctx.configID, name = plan.name or "?", kind = plan.kind, plan = Plan.Record(plan, true) }
end

-- Umbenannte eigene Vorlage: die Vormerkung folgt ihr (sonst verfiele sie, weil es den alten Namen nicht mehr gibt).
function UI.RenameQueued(old, new)
    local q = UI.Queued()
    local rec = q and type(q.plan) == "table" and q.plan
    if not (rec and rec.kind == "own" and rec.key == old and new) then return end
    rec.key, rec.name, q.name = new, new, new
end

-- Gleicher Plan mit gleichen Rängen? (dann verwirft das Laden der Vormerkung nichts)
local function SameMap(a, b)
    a, b = type(a) == "table" and a or {}, type(b) == "table" and b or {}
    for k, v in pairs(a) do if b[k] ~= v then return false end end
    for k, v in pairs(b) do if a[k] ~= v then return false end end
    return true
end

local function SamePlan(a, b)
    return type(a) == "table" and type(b) == "table" and a.kind == b.kind and a.key == b.key and a.name == b.name
        and SameMap(a.tpl and a.tpl.nodes, b.tpl and b.tpl.nodes) and SameMap(a.tpl and a.tpl.choices, b.tpl and b.tpl.choices)
end

-- Vormerkung ausführen, sobald ihr Baum aktiv und das Talentfenster offen ist (aus UI.Refresh). Im Kampf wartet sie
-- und wird nach dem Kampf angestoßen (T7-NT9, Gesamtreview 18.11.2026: vorher blieb sie liegen, bis zufällig ein
-- TRAIT_*-Ereignis kam); ebenso, solange Blizzards „Übernehmen“ läuft (T7-NT1 – danach kommt TRAIT_CONFIG_UPDATED).
-- Der Plan kommt aus der Vormerkung (UI.QueueRecord), nicht aus der gerade geladenen Vorschau; er wird als Vorschau
-- geladen und wie „Übernehmen“ gesetzt. Hat die geladene Vorschau ungespeicherte Änderungen, erst nach Rückfrage –
-- einmal je Öffnen des Talentfensters (host.queueAsked). Gelöscht wird die Vormerkung erst mit „Ja“ (T7-NT2: vorher
-- schon beim Fragen, ein „Nein“ verlor sie ohne Meldung) und erst, wenn der Baum beim „Ja“ noch frei ist; nach „Nein“
-- bleibt sie und kommt beim nächsten Öffnen wieder.
-- → true, wenn „Übernehmen“ lief
UI.QUEUE_COMBAT_KEY = "ezTalent.runQueued"

function UI.RunQueued(host)
    local q = UI.Queued()
    if not (q and host and host.kind == "class") or Read(host.parent, "IsVisible") ~= true then return false end
    local ctx = UI.Context(host)
    if not ctx or ctx.inspecting or ctx.locked or ctx.configID ~= tonumber(q.config) then return false end
    if ns.InCombat() == true then
        -- einen Takt später: läuft AfterCombat sofort (Kampf schon vorbei), ruft sich UI.Refresh nicht selbst auf
        Core.AfterCombat(function() C_Timer.After(0, function() UI.Refresh() end) end, UI.QUEUE_COMBAT_KEY, ADDON)
        return false
    end
    if ctx.committing or host.queueAsked == q then return false end
    local plan = Plan.FromRecord(q.plan, ctx)
    if not plan then
        UI.SetQueued(nil)
        ns.Print(L.QUEUE_GONE:format(q.name))
        return false
    end
    local function Run()
        if UI.Queued() ~= q then return end     -- inzwischen aufgehoben oder ersetzt
        -- „Ja“ kann später kommen als die Frage. Ist der Baum dann nicht frei (Kampf, Blizzards „Übernehmen“, anderer
        -- Reiter), bleibt die Vormerkung samt „Ja“ (host.queueYes) und läuft ohne zweite Rückfrage, sobald er es wieder
        -- ist (Gegenprüfung zu T7-NT2: vorher gelöscht, dann scheiterte „Übernehmen“, und die Vormerkung war weg;
        -- am anderen Reiter kam dazu fälschlich „Die Vorlage gibt es nicht mehr“)
        local now = UI.Context(host)
        if ns.InCombat() == true or not now or now.committing or now.locked or now.inspecting
            or now.configID ~= ctx.configID then
            host.queueAsked, host.queueYes = nil, q
            if ns.InCombat() == true then
                Core.AfterCombat(function() C_Timer.After(0, function() UI.Refresh() end) end, UI.QUEUE_COMBAT_KEY, ADDON)
            end
            return
        end
        UI.SetQueued(nil)
        host.queueAsked, host.queueYes = nil, nil
        host.selected = plan.kind == "own" and plan.key or nil
        host.plan, host.recalled = plan, now.scope
        Plan.Remember(now.scope, plan)
        ns.Print(L.QUEUE_RUN:format(q.name))
        UI.Apply(host)
    end
    local current = host.plan
    if host.queueYes ~= q and current and current.scope == ctx.scope and current.edited and not SamePlan(current, plan) then
        -- je Frage ein eigenes Zeichen: stellt ezTalent dieselbe Frage neu (Fenster ohne Esc geschlossen, Dialog blieb
        -- stehen, wieder geöffnet), meldet ezCore der alten „replaced“ – das darf die neue, offene Frage nicht als
        -- „Nein“ werten (q ist dieselbe Tabelle aus der DB, host.queueAsked allein unterscheidet die Fragen nicht)
        local token = {}
        host.queueAsked, host.queueToken = q, token
        host.queueDeclined = nil
        -- „Nein“ (auch Esc, eine andere Frage an ihrer Stelle) meldet ezCore über onCancel: dann sagt der Kopf, dass
        -- die Vormerkung bis zum nächsten Öffnen wartet (vorher stand dort beides, weil „Nein“ nicht gemeldet wurde)
        Core.Confirm(L.ASK_QUEUE_DISCARD:format(q.name, current.name or "?", q.name), Run, { alert = true, owner = ADDON,
            onCancel = function()
                if host.queueAsked ~= q or host.queueToken ~= token then return end
                host.queueDeclined = q
                UI.Refresh()
            end })
        return false
    end
    Run()
    return UI.Queued() ~= q
end

-- „Zurücksetzen und anwenden“ (Klassentalente; Entscheidung des Nutzers 13.11.2026: „beides“): Grund, warum es nicht
-- geht, sonst nil. Gleiche Prüfung für Knopf (gesperrt + Tooltip) und Klick.
function UI.ResetBlocker(host, ctx)
    ctx = ctx or UI.Context(host)
    if not ctx or ctx.kind ~= "class" then return "noconfig" end
    local plan = UI.ActivePlan(host, ctx)
    if not plan then return "select" end
    -- leere Vorschau: Zurücksetzen nähme alle Punkte weg und verteilte nichts
    local empty = UI.EmptyReason(plan)
    if empty then return empty end
    if ctx.locked then return "locked" end
    if ctx.committing then return "commit" end
    local ok, why = Traits.CanReset(ctx.configID, ctx.treeID)
    if not ok then return why or "noapi" end
    return nil
end

function UI.ResetApply(host)
    local ctx = UI.Context(host)
    local blocker = UI.ResetBlocker(host, ctx)
    if blocker then ns.Print(UI.BlockerText(blocker)) return end
    local plan = UI.ActivePlan(host, ctx)
    local name, tpl = plan.name, plan.tpl
    Core.Confirm(L.ASK_RESET_APPLY:format(name), function()
        -- Zwischen Rückfrage und Klick kann der Kampf begonnen oder die Spezialisierung gewechselt haben
        local again = UI.Context(host)
        local why = UI.ResetBlocker(host, again)
        if why then ns.Print(UI.BlockerText(why)) return end
        local result, fail = Traits.Apply(again.configID, again.treeID, tpl,
            { reset = true, byCurrency = true, frame = host.source() })
        if result then Templates.NoteApplied(again.scope, name, again.configID) end
        UI.ReportApply(again, name, result, fail)
        if result then
            RemindPartial(plan)
            UI.OfferLinks(again, plan)
        end
        UI.Refresh()
    end, { alert = true })
end

-- Datum aus den Daten (JJJJ-MM-TT) in der Schreibweise des Clients.
function UI.Date(iso)
    local y, m, d = tostring(iso or ""):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
    if not y then return tostring(iso or "?") end
    if Core.IsGerman() then return d .. "." .. m .. "." .. y end
    return y .. "-" .. m .. "-" .. d
end

local GRADE_TONE = { checked = "good", single = "gold", unchecked = "bad" }   -- ns.TONES (Design-System 2.5, Welle 22)

function UI.GradeText(preset)
    local grade = type(preset) == "table" and preset.grade or "unchecked"
    -- Berechnet (Welle 21): Farbe über das Design-System (Core.Style), nicht als eigener Farbcode
    if grade == "computed" then
        -- vorläufig (Welle 24): aus den Client-Tabellen ohne gemessene Grundwerte – schon in der Liste sichtbar
        local provisional = type(preset.computed) == "table" and preset.computed.provisional
        return UI.StyleText("highlight", provisional and L.PRESET_GRADE_computed_PROVISIONAL or L.PRESET_GRADE_computed)
    end
    return ns.Tone(GRADE_TONE[grade], L["PRESET_GRADE_" .. grade] or L.PRESET_GRADE_unchecked)
end

-- Text in einer Farb-Rolle des Design-Systems (docs/design-system.md 2.5); ohne Core.Style unverändert.
function UI.StyleText(role, text)
    local style = Core.Style
    if type(style) == "table" and type(style.ColorText) == "function" then return style.ColorText(role, text) end
    return text
end

-- Zeilen zur Herkunft einer berechneten Verteilung (Welle 21): berechnet am …, Annahmen, Quelle der Werte und – bei
-- einer Abweichung – die Grundverteilung; eine vorläufige (computed.provisional, Welle 24) nennt das zuerst:
-- „Vorläufig – Grundwerte geschätzt“ (Leitlinie 11). Leer für recherchierte Vorauswahl.
function UI.ComputedLines(preset)
    local lines = {}
    local info = Templates.IsComputed(preset) and type(preset.computed) == "table" and preset.computed
    if not info then return lines end
    if info.provisional then lines[#lines + 1] = UI.StyleText("highlight", L.PRESET_COMPUTED_PROVISIONAL) end
    local function Lang(field)
        if type(field) ~= "table" then return type(field) == "string" and field or nil end
        return (Core.IsGerman() and field.de) or field.en or field.de
    end
    if preset.variantOf then
        for _, other in ipairs(Templates.Presets()) do
            if other.key == preset.variantOf then
                lines[#lines + 1] = L.PRESET_COMPUTED_VARIANT:format(Templates.PresetName(other))
            end
        end
    end
    lines[#lines + 1] = L.PRESET_COMPUTED_AT:format(UI.Date(info.date), tostring(info.model or "?"), tostring(info.build or "?"))
    -- „%s“ in den Annahmen ist der geltende Befehl (tools/talent_sim.lua schreibt keinen festen Kurzbefehl; T18-2, D3)
    local assume, values = ns.CmdText(Lang(info.assumptions)), Lang(info.values)
    if assume then lines[#lines + 1] = L.PRESET_COMPUTED_ASSUME:format(assume) end
    if values then lines[#lines + 1] = UI.StyleText("gray", L.PRESET_COMPUTED_VALUES:format(values)) end
    -- die passende berechnete Rotation desselben Rechenlaufs (ezCombat, Welle 23 A4)
    local rotation = Templates.RotationForBuild(preset.key)
    if rotation then lines[#lines + 1] = L.PRESET_COMPUTED_ROTATION:format(rotation.name or rotation.key) end
    return lines
end

-- Kategorie einer Vorauswahl für die Listenzeile: wofür sie gedacht ist („Leveln, Solo“, „Dungeon, Raid“, „Tank“ …).
function UI.PresetCategory(preset)
    local labels = {}
    for _, p in ipairs(type(preset) == "table" and preset.purpose or {}) do
        labels[#labels + 1] = L["PRESET_PURPOSE_" .. p] or p
    end
    return table.concat(labels, ", ")
end

-- Zwecke ohne recherchierten Baum der Klasse (Gesamtreview 18.11.2026, T14-5; Leitlinie 11 „nie stumm“): Leveln und
-- PvP, wenn keine recherchierte Vorauswahl (ohne „Berechnet“) sie nennt. → Text „Leveln, PvP“ oder nil
UI.PRESET_GAP_PURPOSES = { "leveling", "pvp" }
function UI.PresetGaps(presets)
    local has = {}
    for _, preset in ipairs(type(presets) == "table" and presets or {}) do
        if not Templates.IsComputed(preset) then
            for _, p in ipairs(type(preset.purpose) == "table" and preset.purpose or {}) do has[p] = true end
        end
    end
    local labels = {}
    for _, p in ipairs(UI.PRESET_GAP_PURPOSES) do
        if not has[p] then labels[#labels + 1] = L["PRESET_PURPOSE_" .. p] or p end
    end
    return #labels > 0 and table.concat(labels, ", ") or nil
end

-- Kurzer Zweck in einem Halbsatz, aus den Angaben der Vorauswahl abgeleitet (Rolle vor Inhalt): Tank, Heiler,
-- Schaden zum Stufen oder Schaden in der Gruppe; dazu „auch zum Stufen“ bzw. „kann eine zweite Rolle“.
function UI.PresetWhy(preset)
    local has = {}
    for _, p in ipairs(type(preset) == "table" and preset.purpose or {}) do has[p] = true end
    local role = has.tank and "tank" or has.healer and "healer" or nil
    local key = role or ((has.leveling or has.solo) and "leveling") or ((has.dungeon or has.raid) and "group") or nil
    if not key then return "" end
    local text = L["PRESET_WHY_" .. key]
    if role and has.leveling then text = text .. ", " .. L.PRESET_WHY_also_leveling end
    if has.hybrid then text = text .. ", " .. L.PRESET_WHY_hybrid end
    return text
end

-- Listenzeile einer Vorauswahl: Name · Kategorie · Verteilung · kurzer Zweck (Wunsch des Nutzers, Spieltest
-- 14.11.2026: „mit name, kategorie, talent(verteilung) oder so, so dass jeder dau ungefähr weiß wofür und weshalb“),
-- dahinter die Einstufung und – falls nötig – das Kennzeichen der Zuordnung.
-- Seit dem Spieltest vom 15.11.2026 steht das in zwei Zeilen: Hauptzeile der Name, Unterzeile UI.PresetRowSub. Diese
-- Fassung (alles in einer Zeile) bleibt für Texte außerhalb der Liste.
function UI.PresetRowText(preset, found, total)
    return Templates.PresetName(preset) .. " · " .. UI.PresetRowSub(preset, found, total)
end

-- Unterzeile einer Vorauswahl: Kategorie · Verteilung · kurzer Zweck · Einstufung, dahinter falls nötig das Kennzeichen
-- der Zuordnung und „Hotfix-Vermerk“ (der Vermerk selbst steht im Tooltip – vorher als eigene orange Dauerzeile).
function UI.PresetRowSub(preset, found, total)
    local parts = {}
    local category, why = UI.PresetCategory(preset), UI.PresetWhy(preset)
    if category ~= "" then parts[#parts + 1] = category end
    if preset.split then parts[#parts + 1] = preset.split end
    if why ~= "" then parts[#parts + 1] = why end
    parts[#parts + 1] = UI.GradeText(preset)
    local tag = UI.MatchTag(found, total)
    if tag then parts[#parts + 1] = tag end
    if #Templates.PresetHotfixes(nil, preset) > 0 then parts[#parts + 1] = ns.Tone("orange", L.PRESET_HOTFIX_TAG) end
    return table.concat(parts, " · ")
end

-- Namen der Websites einer Vorauswahl, jede einmal („Icy Veins, Mobalytics“).
function UI.SourceSites(preset)
    local names, seen = {}, {}
    for _, src in ipairs(type(preset) == "table" and preset.sources or {}) do
        local site = ns.PRESET_SITES and ns.PRESET_SITES[src.site]
        local name = site and site.name or tostring(src.site or "?")
        if not seen[name] then
            seen[name] = true
            names[#names + 1] = name
        end
    end
    return names
end

-- Art einer Quelle samt Vermerk („im Kern gleich; Stand nur über die Sitemap belegt“).
local function SourceRole(src)
    local role = L["PRESET_ROLE_" .. tostring(src.role)] or tostring(src.role or "")
    if src.note and L["PRESET_NOTE_" .. src.note] then role = role .. "; " .. L["PRESET_NOTE_" .. src.note] end
    return role
end

-- Quellen einer Vorauswahl als kurze Zeilen ohne Adresse: „Icy Veins – Stand 04.11.2026, punktgenau“.
function UI.SourceLines(preset)
    local lines = {}
    for _, src in ipairs(type(preset) == "table" and preset.sources or {}) do
        local site = ns.PRESET_SITES and ns.PRESET_SITES[src.site]
        lines[#lines + 1] = L.PRESET_SOURCE_LINE:format(site and site.name or tostring(src.site or "?"), UI.Date(src.stand),
            SourceRole(src))
    end
    return lines
end

-- Quellen mit voller Adresse als Text zum Kopieren (ezCores Textfenster) – die Adressen stehen nicht mehr im Tooltip.
function UI.ShowSources(preset)
    local lines = { L.PRESET_SOURCES:format(UI.Date(preset.read)), "" }
    for i, src in ipairs(preset.sources or {}) do
        lines[#lines + 1] = UI.SourceLines(preset)[i]
        lines[#lines + 1] = Templates.SourceURL(src) or "?"
        lines[#lines + 1] = ""
    end
    local text = table.concat(lines, "\n")
    if Core.TextDialog then
        Core.TextDialog({ title = L.SOURCES_TITLE:format(Templates.PresetName(preset)), hint = L.SOURCES_HINT, text = text,
            readOnly = true, owner = ADDON })
    else
        for line in text:gmatch("[^\n]+") do ns.Print(line) end
    end
end

-- Tooltip einer Vorauswahl – kurz: Zweck, Einstufung, Zuordnung im Client, Hotfix-Vermerke, Namen der Quellen.
-- Die Quellen mit Stand und Art stehen in der Liste unter der geladenen Vorauswahl, die Adressen zeigt „Quellen mit
-- Adressen zeigen »“ (UI.ShowSources) – vorher standen alle Adressen im Tooltip und zogen ihn bis zum Bildschirmrand.
-- how (freiwillig): { spell, pos, name } aus Templates.ResolvePreset – wie viele Talente über welchen Weg.
function UI.PresetTip(preset, found, total, missing, how)
    local lines = {}
    local grade = preset.grade or "unchecked"
    local category, why, raid = UI.PresetCategory(preset), UI.PresetWhy(preset), false
    for _, p in ipairs(preset.purpose or {}) do
        if p == "raid" then raid = true end
    end
    if category ~= "" then
        lines[#lines + 1] = L.PRESET_PURPOSE:format(category) .. (why ~= "" and (" – " .. why) or "")
    end
    if preset.split then lines[#lines + 1] = L.PRESET_SPLIT:format(preset.split) end
    lines[#lines + 1] = ns.Tone(GRADE_TONE[grade], L["PRESET_GRADE_" .. grade .. "_TIP"] or "")
    if raid then lines[#lines + 1] = L.PRESET_RAID_THEORY end
    for _, line in ipairs(UI.ComputedLines(preset)) do lines[#lines + 1] = line end
    if total and total > 0 then
        lines[#lines + 1] = L.PRESET_MATCH:format(found or 0, total)
        if how and (how.name or 0) > 0 then lines[#lines + 1] = L.PRESET_MATCH_NAMES:format(how.name) end
        -- fehlt alles, wäre die Liste nur die ganze Vorauswahl – dann sagt es die Zeile darunter
        if missing and #missing > 0 and (found or 0) > 0 then
            lines[#lines + 1] = L.PRESET_MATCH_MISSING:format(UI.JoinNames(missing, UI.TIP_NAMES))
        end
        if UI.MatchTag(found, total) then
            lines[#lines + 1] = UI.MatchTag(found, total) .. " – "
                .. ((found or 0) > 0 and L.PRESET_PARTIAL_TIP or L.PRESET_UNMATCHED_TIP)
            lines[#lines + 1] = ns.SurveyHint()
        end
    end
    local fixes = Templates.PresetHotfixes(nil, preset)
    for _, fix in ipairs(fixes) do
        lines[#lines + 1] = ns.Tone("orange", L.PRESET_HOTFIX:format(fix.name, UI.Date(fix.date)))
    end
    -- Erklärung und Quelle des Vermerks (vorher im Tooltip der eigenen Zeile unter dem Baum)
    if #fixes > 0 then lines[#lines + 1] = ns.Tone("hint", L.PRESET_HOTFIX_TIP:format(UI.Date(ns.PRESET_HOTFIX_READ))) end
    local sites = UI.SourceSites(preset)
    if #sites > 0 then
        lines[#lines + 1] = L.PRESET_SOURCES_SHORT:format(table.concat(sites, ", "), UI.Date(preset.read))
    end
    lines[#lines + 1] = L.PRESET_TIP
    return table.concat(lines, "\n")
end

-- Namen aufzählen, höchstens limit, dann „und n weitere“.
function UI.JoinNames(names, limit)
    limit = limit or 8
    local out, more = {}, nil
    for i, n in ipairs(names or {}) do
        if i > limit then
            more = ezCore.More(#names - limit, true)
            break
        end
        out[#out + 1] = n
    end
    return table.concat(out, ", ") .. (more and (" " .. more) or "")
end

-- Kennzeichen der Zuordnung einer Vorauswahl (T1): nil bei vollständiger Zuordnung bzw. ohne Talentliste.
function UI.MatchTag(found, total)
    if not (total and total > 0) or (found or 0) >= total then return nil end
    if (found or 0) == 0 then return ns.Tone("bad", L.PRESET_UNMATCHED) end
    return ns.Tone("orange", L.PRESET_PARTIAL)
end

function UI.CopyPreset(host, ctx, preset, partial)
    local name, why, found, total, missing = Templates.CopyPreset(nil, preset, ctx.configID, ctx.treeID,
        { partial = partial })
    if not name then
        if why == "nomatch" then
            ns.Print(L.PRESET_COPY_NONE:format(Templates.PresetName(preset)))
        elseif why == "partial" then
            -- Nie still eine Teilvorlage: erst nach Rückfrage mit „x von y“ und den fehlenden Talenten
            Core.Confirm(L.ASK_PRESET_PARTIAL:format(Templates.PresetName(preset), found or 0, total or 0,
                UI.JoinNames(missing)), function() UI.CopyPreset(host, UI.Context(host) or ctx, preset, true) end,
                { alert = true })
        end
        return
    end
    host.selected, host.plan, host.recalled = name, nil, ctx.scope
    Plan.Remember(ctx.scope, UI.ActivePlan(host, ctx))
    if total then
        -- EINE Zeile wie beim Laden (UI.PresetLoadLine), die fehlenden Talente gekürzt auf fünf Namen
        local text = L.PRESET_COPIED:format(Templates.PresetName(preset), name, found or 0, total)
        if missing and #missing > 0 then text = text .. " " .. L.PRESET_COPY_MISSING:format(UI.JoinNames(missing, 5)) end
        ns.Print(text)
    end
    UI.Refresh()
end

function UI.Share(host)
    local ctx = UI.Context(host)
    local name = Selected(host, ctx or {})
    if not name then ns.Print(L.SELECT_FIRST) return end
    local text = Templates.Export(ctx.scope, name)
    if not text then return end
    Core.TextDialog({ title = L.SHARE_TITLE:format(name), hint = L.SHARE_HINT, text = text, select = true,
        readOnly = true, owner = ADDON })
end

function UI.Import(host)
    local ctx = UI.Context(host)
    if not (ctx and ctx.scope) then return end
    Core.TextDialog({ title = L.IMPORT_TITLE, hint = L.IMPORT_HINT, text = "", accept = true, owner = ADDON,
        onAccept = function(text)
            local name, why = Templates.Import(text, ctx.scope)
            if not name then
                ns.Print(L["IMPORT_FAIL_" .. tostring(why)] or L.IMPORT_FAIL_format)
                return false
            end
            host.selected, host.plan, host.recalled = name, nil, ctx.scope
            Plan.Remember(ctx.scope, UI.ActivePlan(host, ctx))
            ns.Print(L.IMPORTED:format(name))
            UI.Refresh()
        end })
end

function UI.Rename(host)
    local ctx = UI.Context(host)
    local name = Selected(host, ctx or {})
    if not name then ns.Print(L.SELECT_FIRST) return end
    Core.AskText(L.ASK_RENAME, name, function(text)
        local ok, why = Templates.Rename(ctx.scope, name, text)
        if ok then
            host.selected = Templates.CleanName(text)
            -- die geladene Vorschau (samt ungespeicherten Änderungen) gehört weiter zu dieser Vorlage
            if host.plan and host.plan.kind == "own" and host.plan.key == name then
                host.plan.key, host.plan.name = host.selected, host.selected
            end
            UI.RenameQueued(name, host.selected)
            Plan.Remember(ctx.scope, UI.ActivePlan(host, ctx))
        else
            ns.Print(L["RENAME_FAIL_" .. tostring(why)] or "")
        end
        UI.Refresh()
    end, Templates.MAX_NAME)
end

function UI.Delete(host)
    local ctx = UI.Context(host)
    local name = Selected(host, ctx or {})
    if not name then ns.Print(L.SELECT_FIRST) return end
    Core.Confirm(L.ASK_DELETE:format(name), function()
        Templates.Delete(ctx.scope, name)
        host.selected, host.plan = nil, nil
        Plan.Remember(ctx.scope, nil)
        UI.Refresh()
    end, { alert = true })
end

---------------------------------------------------------------------------
-- Ausrüstungsset und Leistenprofil zur Vorlage (TL-02, VP-36; Frage 19 – Empfehlung umgesetzt, Antwort offen)
---------------------------------------------------------------------------

-- Texte je Feld; seit Welle 27 (Zweig modul/eztalent-menue) auch die des Menüs zur Wahl: Abschnitt (group, groupTip),
-- Tooltip je Eintrag (entryTip), Quelle (source, grau über L.SOURCES_ACCORDING) und Verwalten im Modul (manage).
-- Funde des code-reviewers vor dem Merge: Titelzeile ohne „»“ (title; „»“ zeigt nur an der Zeile im Seitenteil, dass
-- ein Klick ein Menü öffnet), eigener Tooltip für „Noch nichts angelegt“ (emptyTip; tip spricht von der Zeile darüber
-- im Seitenteil), Chatzeile, wenn das Modul sein Werkzeug nicht öffnen konnte (openFail).
local LINK_TEXT = {
    gear = { pick = "LINK_GEAR_PICK", use = "LINK_GEAR_USE", named = "LINK_GEAR_NAMED", tip = "LINK_GEAR_TIP",
        useTip = "LINK_GEAR_USE_TIP", gone = "LINK_GEAR_GONE", group = "LINK_GEAR_GROUP", groupTip = "LINK_GEAR_GROUP_TIP",
        entryTip = "LINK_GEAR_ENTRY_TIP", source = "LINK_GEAR_SOURCE", title = "LINK_GEAR_TITLE", emptyTip = "LINK_GEAR_EMPTY_TIP" },
    bars = { pick = "LINK_BARS_PICK", use = "LINK_BARS_USE", named = "LINK_BARS_NAMED", tip = "LINK_BARS_TIP",
        useTip = "LINK_BARS_USE_TIP", gone = "LINK_BARS_GONE", group = "LINK_BARS_NOCLASS", groupTip = "LINK_BARS_GROUP_TIP",
        entryTip = "LINK_BARS_ENTRY_TIP", source = "LINK_BARS_SOURCE", manage = "LINK_BARS_MANAGE",
        manageTip = "LINK_BARS_MANAGE_TIP", title = "LINK_BARS_TITLE", emptyTip = "LINK_BARS_EMPTY_TIP",
        openFail = "LINK_BARS_OPEN_FAIL" },
}

--[[
    Symbole des Menüs zur Wahl an EINER Stelle (Welle 27, Zweig modul/eztalent-menue; Wunsch des Nutzers vom 16.11.2026
    „+ eztalente … also das menü“, Stil wie das ezMap-Menü, Design-System 2.3: Rolle line über ezCores Core.Menu.Icon).
    Quellen in dieser Reihenfolge (Leitlinien 1 und 11), keine eigenen Bilddateien:
      1. Blizzards Bild derselben Sache zur Laufzeit: das Bild eines Sets aus Blizzards Ausrüstungsmanager
         (C_EquipmentSet.GetEquipmentSetInfo über ezGears Sets), das Klassensymbol eines Profils über Blizzards Atlas
         „classicon-<klasse>“ bzw. Blizzards Datei Interface\Icons\ClassIcon_<Klasse>.
      2. Blizzards Datei für das Feld: dieselbe, die das Modul zeigt (Leistenprofile: ezMacros Werkzeug „Leisten-Profile“,
         ezMacro/Profiles.lua), für Sets ein Brustteil.
      3. ezCores Fragezeichen (Core.Menu.ICON_FALLBACK, über Core.Menu.Icon) – nie ein leeres Feld.
    UI.LINK_ICON[schlüssel] = Angabe für Core.Menu.Icon (file: eine Datei oder eine Liste); UI.LinkIcon(feld, eintrag)
    → Angabe je Eintrag.
    Das Buch der Leistenprofile bildet ezMacros Symbol des Werkzeugs „Leisten-Profile“ nach (ezMacro/Profiles.lua) –
    liefert ezMacro es über seine Schnittstelle, entfällt die Kopie (docs/roadmap/ezTalent.md, „Wartet auf ezGear und
    ezMacro“).
    „keins“ nimmt ezCores Symbol „nichts“ (Core.Menu.ICON_ALL_OFF) zur Laufzeit – keine Kopie hier (Leitlinie 2).
]]
UI.LINK_ICON = {
    gear = { file = { "Interface\\Icons\\INV_Chest_Chain" }, crop = true },
    bars = { file = { "Interface\\Icons\\INV_Misc_Book_09", "Interface\\Icons\\INV_Misc_Book_11" }, crop = true },
    gone = { atlas = "services-icon-warning", file = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew" },
    info = { file = "Interface\\Common\\help-i" },
}

function UI.LinkIcon(field, entry)
    local base = UI.LINK_ICON[field] or UI.LINK_ICON.info
    if type(entry) ~= "table" then return base end
    local files, atlas = {}, base.atlas
    if field == "gear" and entry.icon ~= nil then files[1] = entry.icon end
    local class = entry.class
    if field == "bars" and type(class) == "string" and class:find("^%u+$") then
        atlas = "classicon-" .. class:lower()
        files[#files + 1] = "Interface\\Icons\\ClassIcon_" .. class:sub(1, 1) .. class:sub(2):lower()
    end
    -- base.file: eine Datei oder eine Liste (gone, info: eine; Fund des code-reviewers – ipairs auf eine Zeichenkette warf)
    local own = type(base.file) == "table" and base.file or { base.file }
    for _, file in ipairs(own) do files[#files + 1] = file end
    return { atlas = atlas, file = files, crop = true }
end

-- Abschnitte des Menüs (datengetrieben): { { title, icon, tip, entries } | { title, icon, tip, subs = { { title, icon,
-- entries } … } } }. Sets: ein Abschnitt. Profile nach der Klasse, mit der sie gespeichert wurden: eigene Klasse, ohne
-- Klasse, andere Klassen je in einem Untermenü (statt einer langen Liste); leere Abschnitte fehlen. Nennt ezMacro die
-- Klasse nicht (ältere Fassung ohne ProfileList, Templates.LinkHasClass), ein Abschnitt „Leistenprofile“ statt
-- „Profile ohne Klasse“ – die Klasse ist dann unbekannt, nicht leer (Fund des code-reviewers vor dem Merge).
function UI.LinkGroups(field, entries)
    local texts = LINK_TEXT[field]
    if field ~= "bars" then
        return { { title = L[texts.group], icon = UI.LinkIcon(field), tip = L[texts.groupTip], entries = entries } }
    end
    if not Templates.LinkHasClass(field) then
        if #entries == 0 then return {} end
        return { { title = L.LINK_BARS_GROUP, icon = UI.LinkIcon(field), tip = L.LINK_BARS_ALL_TIP, entries = entries } }
    end
    local mine = Core.PlayerClass()
    local own, none, other, classes = {}, {}, {}, {}
    for _, entry in ipairs(entries) do
        local class = entry.class
        if not class then
            none[#none + 1] = entry
        elseif class == mine then
            own[#own + 1] = entry
        else
            if not other[class] then
                other[class] = {}
                classes[#classes + 1] = class
            end
            table.insert(other[class], entry)
        end
    end
    local groups = {}
    if #own > 0 then
        groups[#groups + 1] = { title = L.LINK_BARS_OWN:format(Core.ClassName(mine) or mine),
            icon = UI.LinkIcon(field, { class = mine }), tip = L[texts.groupTip], entries = own }
    end
    if #none > 0 then
        groups[#groups + 1] = { title = L[texts.group], icon = UI.LinkIcon(field), tip = L[texts.groupTip], entries = none }
    end
    if #classes > 0 then
        local function Name(class) return Core.ClassName(class) or class end
        table.sort(classes, function(a, b) return Name(a) < Name(b) end)
        local subs = {}
        for i, class in ipairs(classes) do
            subs[i] = { title = Name(class), icon = UI.LinkIcon(field, { class = class }), entries = other[class] }
        end
        groups[#groups + 1] = { title = L.LINK_BARS_OTHER, icon = UI.LinkIcon(field), tip = L[texts.groupTip], subs = subs }
    end
    return groups
end

-- Nach „Übernehmen“ (nur eigene Vorlagen der Klassentalente): Set und Profil der Vorlage im Chat nennen – angelegt
-- bzw. geladen wird erst mit der Zeile im Seitenteil; was es im Modul nicht mehr gibt, wird nicht genannt. → Zahl der
-- genannten
function UI.OfferLinks(ctx, plan)
    if not (ctx and ctx.kind == "class" and type(plan) == "table" and plan.kind == "own") then return 0 end
    local tpl = Templates.Get(ctx.scope, plan.key)
    if not tpl then return 0 end
    local parts = {}
    for _, field in ipairs(Templates.LINKS) do
        if tpl[field] and Templates.LinkKnown(field, tpl[field]) then parts[#parts + 1] = L[LINK_TEXT[field].named]:format(tpl[field]) end
    end
    if #parts > 0 then ns.Print(L.APPLY_LINKS:format(table.concat(parts, ", "))) end
    return #parts
end

-- Wahl setzen (nil: keins) und neu zeichnen.
function UI.SetLink(host, field, value)
    local ctx = UI.Context(host)
    local name = ctx and Selected(host, ctx)
    if not name then return false end
    local ok = Templates.SetLink(ctx.scope, name, field, value)
    UI.Refresh()
    return ok
end

-- Inhalt des Menüs zur Wahl (Welle 27, Zweig modul/eztalent-menue): Titelzeile mit dem Symbol des Felds, „keins“,
-- ein gemerkter Name, den es nicht mehr gibt (Warnsymbol), dann die Abschnitte aus UI.LinkGroups mit Überschrift
-- (Core.Menu.Section) – je Eintrag ein Symbol (UI.LinkIcon) und ein Tooltip nach Design-System 2.7 (Titel,
-- Beschreibung, Quelle grau). Zuletzt „Verwalten“ im Modul, wo es eine Schnittstelle gibt. Die Wahl landet über
-- UI.SetLink in der Vorlage (ezTalentDB, bleibt nach /reload). entries: Templates.LinkEntries(feld).
function UI.BuildLinkMenu(root, host, field, current, entries)
    local Menu = Core.Menu
    local texts = LINK_TEXT[field]
    local source = L.SOURCES_ACCORDING:format(L[texts.source])
    local mine = Core.PlayerClass()
    local function Get() return current or false end
    local function Entry(parent, entry)
        local radio = Menu.Radio(parent, entry.name, Get, function() UI.SetLink(host, field, entry.name) end, entry.name)
        Menu.Icon(radio, UI.LinkIcon(field, entry))
        local tip = L[texts.entryTip]
        if entry.equipped then tip = tip .. " " .. L.LINK_GEAR_EQUIPPED end
        if entry.class and entry.class ~= mine then tip = tip .. " " .. L.LINK_BARS_CLASS:format(Core.ClassName(entry.class) or entry.class) end
        Menu.Tip(radio, entry.name, tip, source)
        return radio
    end
    Menu.Icon(Menu.Title(root, L[texts.title]:format(current or L.LINK_NONE)), UI.LinkIcon(field))
    local none = Menu.Radio(root, L.LINK_NONE, Get, function() UI.SetLink(host, field, nil) end, false)
    Menu.Icon(none, Menu.ICON_ALL_OFF)     -- „nichts“: ezCores Symbol (SSOT), zur Laufzeit gelesen
    Menu.Tip(none, L.LINK_NONE, L.LINK_NONE_TIP)
    local known = false
    for _, entry in ipairs(entries) do if entry.name == current then known = true end end
    if current and not known then
        local gone = Menu.Radio(root, L.LINK_GONE_ENTRY:format(current), Get, function() UI.SetLink(host, field, current) end, current)
        Menu.Icon(gone, UI.LINK_ICON.gone)
        Menu.Tip(gone, L[texts.gone]:format(current), L.LINK_GONE_ENTRY_TIP, source)
    end
    for _, group in ipairs(UI.LinkGroups(field, entries)) do
        local section = Menu.Section(root, group.title, { icon = group.icon, tip = group.tip, source = source })
        for _, entry in ipairs(group.entries or {}) do Entry(section, entry) end
        for _, sub in ipairs(group.subs or {}) do
            local button = Menu.Icon(Menu.Button(section, sub.title), sub.icon)
            Menu.Tip(button, sub.title, L[texts.groupTip], source)
            for _, entry in ipairs(sub.entries) do Entry(button, entry) end
        end
    end
    if #entries == 0 then
        local empty = Menu.Button(root, L.LINK_EMPTY, function() end)
        Menu.Icon(empty, UI.LINK_ICON.info)
        Menu.Tip(empty, L.LINK_EMPTY, L[texts.emptyTip], source)
    end
    if texts.manage and Templates.CanOpenLink(field) then
        Menu.Divider(root)
        local manage = Menu.Button(root, L[texts.manage], function()
            if not Templates.OpenLink(field) then ns.Print(L[texts.openFail]) end
        end)
        Menu.Icon(manage, UI.LinkIcon(field))
        Menu.Tip(manage, L[texts.manage], L[texts.manageTip], source)
    end
end

-- Auswahl über Blizzards Menü (Core.Menu, Inhalt: UI.BuildLinkMenu): „keins“ und alle Sets bzw. Profile. Ohne Menü
-- wechselt jeder Klick zum nächsten Eintrag (keins » erstes » zweites … » keins).
function UI.PickLink(host, owner, field)
    local ctx = UI.Context(host)
    local name = ctx and Selected(host, ctx)
    local choices = name and Templates.LinkChoices(field)
    if not choices then return false end
    local current = Templates.Get(ctx.scope, name)[field]
    local Menu = Core.Menu
    local opened = Menu and Menu.Open and Menu.Open(owner, function(root)
        UI.BuildLinkMenu(root, host, field, current, Templates.LinkEntries(field) or {})
    end)
    if opened then return true end
    local nextValue, at = choices[1], nil
    for i, choice in ipairs(choices) do if choice == current then at = i end end
    if at then nextValue = choices[at + 1] end
    return UI.SetLink(host, field, nextValue)
end

-- Set anlegen bzw. Profil laden (Klick auf die Zeile).
function UI.UseLink(host, field)
    local ctx = UI.Context(host)
    local name = ctx and Selected(host, ctx)
    local tpl = name and Templates.Get(ctx.scope, name)
    if not (tpl and tpl[field]) then return false end
    if Templates.LinkKnown(field, tpl[field]) == false then        -- gelöscht oder umbenannt: sagen statt still nichts
        ns.Print(L[LINK_TEXT[field].gone]:format(tpl[field]) .. ".")
        return false
    end
    local ok, why = Templates.UseLink(field, tpl[field])
    if not ok and why == "module" then ns.Print(L.LINK_NO_MODULE) end
    return ok
end

-- Zeilen unter der gewählten eigenen Vorlage: wählen (»), anlegen bzw. laden – je nur mit dem Modul (ohne keine Felder).
-- Gibt es den gemerkten Namen nicht mehr, steht statt „anlegen“ bzw. „laden“ grau, dass er fehlt.
function UI.LinkLines(host, ctx, Add)
    if ctx.kind ~= "class" then return end
    local name = Selected(host, ctx)
    local tpl = name and Templates.Get(ctx.scope, name)
    if not tpl then return end
    for _, field in ipairs(Templates.LINKS) do
        if Templates.LinkChoices(field) then
            local texts = LINK_TEXT[field]
            if tpl[field] and Templates.LinkKnown(field, tpl[field]) then
                Add({ text = L[texts.use]:format(tpl[field]), indent = 6, tipTitle = L[texts.use]:format(tpl[field]),
                    tip = L[texts.useTip], onClick = function() UI.UseLink(host, field) end })
            elseif tpl[field] then
                Add({ text = ns.Tone("hint", L[texts.gone]:format(tpl[field])), indent = 6,
                    tipTitle = L[texts.gone]:format(tpl[field]), tip = L.LINK_GONE_TIP })
            end
            Add({ text = ns.Tone("hint", L[texts.pick]:format(tpl[field] or L.LINK_NONE)), indent = 6,
                tipTitle = L[texts.pick]:format(tpl[field] or L.LINK_NONE), tip = L[texts.tip],
                onClick = function(row) UI.PickLink(host, row, field) end })
        end
    end
end

function UI.Rotation(host)
    local ctx = UI.Context(host)
    local plan = ctx and UI.ActivePlan(host, ctx)
    local rotation = plan and Templates.RotationForPlan(plan)
    if not rotation then ns.Print(L.ROTATION_NONE) return end
    if Templates.SelectRotation(rotation) then ns.Print(L.ROTATION_SELECTED:format(rotation.name or rotation.key)) end
end

-- Zeilen des Seitenteils „Vorlagen“ (ohne Rahmen – auch für die Tests).
-- Quellen einer geladenen Vorauswahl auf- bzw. zuklappen (Zeile „Quellen und Stand »“ unter dem Eintrag).
function UI.ToggleSources(host, key)
    host.sourcesOpen = host.sourcesOpen ~= key and key or nil
    UI.Refresh()
end

-- Zeilen des Seitenteils „Vorlagen“ (ohne Rahmen – auch für die Tests). Gliederung nach dem Spieltest vom 15.11.2026:
-- „Aktuelle Verteilung“, Abschnitt „Eigene Vorlagen“, Abschnitt „Vorauswahl“ – je mit Überschrift und Abstand; je
-- Eintrag die Hauptzeile (Name) und höchstens eine Unterzeile (text/sub). Hinweise (Hotfix-Vermerke, Zuordnung) stehen
-- im Tooltip des Eintrags, die Quellen der geladenen Vorauswahl klappen unter ihr auf. Der Hinweis auf einen fremden
-- Planer steht im Kopf (UI.HeadLines).
function UI.TemplateLines(host, ctx)
    local lines = {}
    local function Add(line) lines[#lines + 1] = line end
    local entry = UI.FONTS.row

    -- Was in den Baum geladen ist, ist markiert: „Aktuelle Verteilung“ (keine Vorschau), eine eigene Vorlage oder
    -- eine Vorauswahl. Ein Klick lädt – kopiert oder gesetzt wird dabei nichts.
    local plan = UI.ActivePlan(host, ctx)
    local currentSub
    if ctx.kind == "class" then
        local groups = Traits.Groups(ctx.configID, ctx.treeID)
        if #groups > 0 then currentSub = Traits.GroupText(groups) end
    end
    Add({ text = L.ROW_CURRENT, sub = currentSub, font = entry, selected = plan == nil, tipTitle = L.ROW_CURRENT,
        tip = L.ROW_CURRENT_TIP, gap = UI.ENTRY_GAP, onClick = function() UI.SelectCurrent(host) end })

    Add({ text = L.TEMPLATES_OWN, font = UI.FONTS.section, before = UI.SECTION_GAP - UI.ENTRY_GAP, section = true })
    local names = Templates.Names(ctx.scope)
    local selected = Selected(host, ctx)
    local fails = Templates.remapFail[ctx.scope] or {}
    for _, name in ipairs(names) do
        local tpl = Templates.Get(ctx.scope, name)
        -- Unterzeile: Verteilung · Punkte · Zustand (wie die Vorauswahl)
        local parts = {}
        if tpl.groups and #tpl.groups > 0 then parts[#parts + 1] = table.concat(tpl.groups, "/") end
        parts[#parts + 1] = L.TEMPLATE_POINTS:format(tpl.points or Traits.Points(tpl))
        local tip = L.TEMPLATE_ROW_TIP
        if tpl.unmatched then      -- aus einer nur teilweise zugeordneten Vorauswahl kopiert (T1)
            local found = (tpl.matchTotal or tpl.unmatched) - tpl.unmatched
            parts[#parts + 1] = UI.MatchTag(found, tpl.matchTotal)
            tip = tip .. "\n\n" .. L.PRESET_MATCH:format(found, tpl.matchTotal) .. "\n" .. L.TEMPLATE_PARTIAL_TIP
            if fails[name] then tip = tip .. "\n" .. ns.Tone("orange", L.REMAP_TIP:format(Templates.RemapWhy(fails[name]))) end
        end
        if tpl.order then parts[#parts + 1] = L.TEMPLATE_ORDER_SHORT:format(#tpl.order) end
        -- Reihenfolge der Punkte (TL-01), Set und Leistenprofil (TL-02): im Tooltip mit Quelle
        if tpl.order then tip = tip .. "\n\n" .. L.TEMPLATE_ORDER_TIP:format(#tpl.order, Plan.OrderSource(tpl)) end
        for _, field in ipairs(Templates.LINKS) do
            if tpl[field] then tip = tip .. "\n" .. L[LINK_TEXT[field].named]:format(tpl[field]) end
        end
        Add({ text = name, sub = table.concat(parts, " · "), font = entry, indent = 6, selected = name == selected,
            tipTitle = name, tip = tip, tipWide = true, gap = UI.ENTRY_GAP, onClick = function() UI.SelectOwn(host, name) end })
    end
    if #names == 0 then Add({ text = L.TEMPLATES_NONE, font = UI.FONTS.sub, indent = 6, gap = UI.ENTRY_GAP }) end

    if ctx.kind == "class" then
        -- berechnete Verteilung: die berechnete Rotation desselben Rechenlaufs (Welle 23, A4), sonst die für den Hauptbaum
        local rotation, built = Templates.RotationForPlan(plan)
        if rotation then
            Add({ text = L.ROTATION_LINE:format(rotation.name or rotation.key), indent = 6, gap = UI.ENTRY_GAP,
                tipTitle = L.ROTATION_TITLE, tip = built and L.ROTATION_TIP_BUILD or L.ROTATION_TIP,
                onClick = function() UI.Rotation(host) end })
        end
        UI.LinkLines(host, ctx, Add)
        Add({ text = L.PRESETS_TITLE, font = UI.FONTS.section, before = UI.SECTION_GAP - UI.ENTRY_GAP, section = true })
        local presets = Templates.Presets()
        local index = #presets > 0 and Templates.PresetIndex(ctx.configID, ctx.treeID) or nil
        local computedShown = false
        local gaps = #presets > 0 and UI.PresetGaps(presets) or nil
        local function AddGaps()
            if not gaps then return end
            Add({ text = L.PRESETS_GAP:format(gaps), font = UI.FONTS.note, indent = 6, gap = UI.ENTRY_GAP,
                tipTitle = L.PRESETS_TITLE, tip = L.PRESETS_GAP_TIP })
            gaps = nil
        end
        for _, preset in ipairs(presets) do
            -- Berechnete Verteilungen (Welle 21) stehen hinter den recherchierten unter eigener Überschrift
            if Templates.IsComputed(preset) and not computedShown then
                AddGaps()   -- T14-5: Lücken der recherchierten Bäume vor „Berechnet“
                computedShown = true
                -- Erklärung der berechneten Verteilungen am Abschnitt (vorher im Tooltip des Schalters computedPresets)
                Add({ text = L.COMPUTED_TITLE, font = UI.FONTS.section, before = UI.SECTION_GAP - UI.ENTRY_GAP, section = true,
                    tipTitle = L.COMPUTED_TITLE, tip = L.COMPUTED_TITLE_TIP })
            end
            local found, total, missing, how
            if type(preset.talents) == "table" then
                local _
                _, found, total, missing, how = Templates.ResolvePreset(preset, ctx.configID, ctx.treeID, index)
            end
            local loaded = plan ~= nil and plan.kind == "preset" and plan.key == preset.key
            Add({ text = Templates.PresetName(preset), sub = UI.PresetRowSub(preset, found, total), font = entry,
                indent = 6, tipTitle = Templates.PresetName(preset), selected = loaded, gap = UI.ENTRY_GAP,
                tip = UI.PresetTip(preset, found, total, missing, how), tipWide = true,
                onClick = function() UI.SelectPreset(host, preset) end })
            -- Unter der geladenen Vorauswahl: ihre Quellen zum Aufklappen (mit Stand und Art, ohne Adressen) und der Weg
            -- zu den Adressen
            if loaded and type(preset.sources) == "table" and #preset.sources > 0 then
                local open = host.sourcesOpen == preset.key
                Add({ text = (open and L.SOURCES_TOGGLE_OPEN or L.SOURCES_TOGGLE):format(#preset.sources),
                    font = UI.FONTS.note, indent = 14, gap = UI.ENTRY_GAP, tipTitle = L.SOURCES_TOGGLE_TITLE,
                    tip = L.SOURCES_TOGGLE_TIP:format(UI.Date(preset.read)),
                    onClick = function() UI.ToggleSources(host, preset.key) end })
                if open then
                    Add({ text = L.PRESET_SOURCES:format(UI.Date(preset.read)), font = UI.FONTS.sub, indent = 20 })
                    for _, line in ipairs(UI.SourceLines(preset)) do
                        Add({ text = line, font = UI.FONTS.sub, indent = 20 })
                    end
                    Add({ text = L.SOURCES_SHOW, font = UI.FONTS.note, indent = 20, gap = UI.ENTRY_GAP,
                        tipTitle = L.SOURCES_SHOW, tip = L.SOURCES_SHOW_TIP, onClick = function() UI.ShowSources(preset) end })
                end
            end
        end
        AddGaps()
        if #presets == 0 then Add({ text = L.PRESETS_NONE, font = UI.FONTS.sub, indent = 6 }) end
    end
    return lines
end

-- Kopfzeile: Punkte und Vorschau-Hinweis.
function UI.HeadText(ctx)
    local parts = {}
    if ctx.kind == "class" then
        local groups = Traits.Groups(ctx.configID, ctx.treeID)
        if #groups > 0 then parts[#parts + 1] = L.HEAD_TREES:format(Traits.GroupText(groups)) end
        if ctx.locked then parts[#parts + 1] = L.HEAD_LOCKED end
    else
        local free, _, total = Traits.Currency(ctx.configID, ctx.treeID)
        if free then parts[#parts + 1] = L.HEAD_FREE:format(free, total) end
    end
    if Traits.HasStaged(ctx.configID) then parts[#parts + 1] = ns.Tone("gold", L.HEAD_STAGED) end
    if #parts == 0 then parts[1] = Traits.Available() and L.HEAD_EMPTY or L.HEAD_NOAPI end
    return table.concat(parts, "\n")
end

-- Zeile zur Reihenfolge der Punkte (TL-01, VP-57): nächster Schritt mit Quelle, „alle gesetzt“, beim Anpassen ohne
-- Reihenfolge der Hinweis, dass die Klicks sie festlegen. → Text oder nil
function UI.OrderText(plan, ctx, points, editing)
    local order = plan.tpl.order
    if type(order) ~= "table" or #order == 0 then
        -- der Hinweis nennt die Meldung beim Stufenaufstieg – die gibt es nur für Klassentalente
        return editing and type(ctx) == "table" and ctx.kind == "class" and ns.Tone("hint", L.PLAN_ORDER_HINT) or nil
    end
    local source = Plan.OrderSource(plan.tpl)
    local step = Plan.NextStep(plan, ctx)
    local text
    if step then
        text = L.PLAN_ORDER_NEXT:format(step.name, step.step, step.total, source)
    else
        text = L.PLAN_ORDER_DONE:format(#order, source)
    end
    if points and #order < points then text = text .. " " .. L.PLAN_ORDER_PART:format(#order, points) end
    return ns.Tone("next", text)
end

-- Alle Angaben zur geladenen Vorschau: Name, Verteilung, Fortschritt im Baum, was fehlt – und wie man sie bedient.
-- Seit dem Spieltest vom 15.11.2026 stehen sie im Tooltip des Knopfs „?“ („Einzelheiten“); der Kopf selbst zeigt die
-- kurze Fassung aus UI.HeadLines. noLegend = true: ohne die Zeile mit den Farben (die zeigt der Tooltip als Legende).
function UI.PlanText(host, ctx, noLegend)
    local plan = UI.ActivePlan(host, ctx)
    if not plan then return nil end
    local lines = {}
    -- Vorauswahl ohne jede Zuordnung: Die Vorschau ist leer – statt „0 von 0“ sagen, warum, und was hilft
    if plan.kind == "preset" and plan.total and plan.total > 0 and (plan.found or 0) == 0 then
        return table.concat({ L.PLAN_HEAD_EMPTY:format(plan.name or "?"), ns.Tone("bad", L.PRESET_UNMATCHED_TIP),
            ns.SurveyHint() }, "\n")
    end
    local split, points = Plan.Split(plan, ctx), Plan.Points(plan)
    if #split > 0 then
        lines[#lines + 1] = L.PLAN_HEAD_SPLIT:format(plan.name or "?", table.concat(split, "/"), points)
    else
        lines[#lines + 1] = L.PLAN_HEAD:format(plan.name or "?", points)
    end
    if plan.kind == "preset" and plan.total and plan.total > 0 and (plan.found or 0) < plan.total then
        lines[#lines + 1] = ns.Tone("orange", L.PLAN_MATCH:format(plan.found or 0, plan.total, UI.JoinNames(plan.missing, 4)))
    end
    -- Regeln des Baums (TL-10): Gesamtpunkte und was so nicht geht – schon beim Planen, nicht erst beim Übernehmen
    local check = Plan.Check(plan, ctx)
    if check.over then
        lines[#lines + 1] = ns.Tone("bad", L.PLAN_TOTAL_OVER:format(check.points, check.max))
    elseif check.max then
        lines[#lines + 1] = L.PLAN_TOTAL:format(check.points, check.max)
    end
    if #check.list > 0 then
        local parts = {}
        for i, id in ipairs(check.list) do
            if i > UI.TIP_NAMES then
                parts[#parts + 1] = ezCore.More(#check.list - UI.TIP_NAMES, true)
                break
            end
            parts[#parts + 1] = Traits.NodeName(ctx.configID, id) .. " (" .. Plan.BadText(ctx, check.bad[id]) .. ")"
        end
        lines[#lines + 1] = ns.Tone("invalid", L.PLAN_INVALID:format(table.concat(parts, ", ")))
    end
    local progress = Plan.Progress(plan, ctx)
    lines[#lines + 1] = L.PLAN_PROGRESS:format(progress.have, progress.want)
    if progress.short then lines[#lines + 1] = L.PLAN_SHORT:format(progress.free, progress.need) end
    if progress.extra > 0 then lines[#lines + 1] = ns.Tone("bad", L.PLAN_EXTRA:format(progress.extra)) end
    if progress.other > 0 then lines[#lines + 1] = ns.Tone("orange", L.PLAN_OTHER:format(progress.other)) end
    local orderLine = UI.OrderText(plan, ctx, points, host.editing)
    if orderLine then lines[#lines + 1] = orderLine end
    if plan.edited then lines[#lines + 1] = ns.Tone("gold", L.PLAN_EDITED) end
    if not Plan.CanShow(host.source()) then
        lines[#lines + 1] = L.PLAN_NO_TREE
    elseif host.editing then
        lines[#lines + 1] = ns.Tone("good", L.PLAN_EDITING)
    elseif not noLegend then
        lines[#lines + 1] = ns.Tone("hint", L.PLAN_LEGEND)
    end
    return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Kopf des Seitenteils „Vorlagen“ (Spieltest 15.11.2026: „das vorschau-talentfenster ist furchtbar formatiert“).
-- Eine gold Zeile (was geladen ist, mit Verteilung), darunter zwei Zeilen: „Gesetzt: n von m Punkten · frei: k“ und EIN
-- Satz, was „Übernehmen“ jetzt tut. Dazu höchstens UI.HEAD_NOTES farbige Hinweise (vorgemerkte Punkte, Regeln, Platz,
-- fremder Planer …); was nicht hineinpasst, zählt die letzte Zeile und zeigt der Knopf „?“ – dort auch die Legende der
-- Farben und alle Einzelheiten (UI.HeadText, UI.PlanText).
---------------------------------------------------------------------------

UI.HEAD_NOTES = 2          -- so viele Hinweise stehen im Kopf, der Rest unter „?“
UI.HEAD_MAX_LINES = 4      -- Zeilen unter der gold Kopfzeile: Fortschritt, Satz zu „Übernehmen“, zwei Hinweise

-- Ein Satz: was „Übernehmen“ mit der geladenen Vorschau gerade tut (Spieltest 15.11.2026: „ich dachte zwar das wählt
-- autom. die richtigen aus“ – die Vorschau markiert die Ziel-Talente und setzt nichts, solange die Punkte nicht reichen).
-- progress (freiwillig): Plan.Progress, falls schon gerechnet.
function UI.ApplyText(host, ctx, plan, progress)
    if host.editing then return ns.Tone("good", L.PLAN_EDITING) end
    if not plan then return ctx.locked and L.HEAD_LOCKED or L.ACT_PICK end
    if UI.EmptyReason(plan) then return L.ACT_EMPTY end
    if ctx.inactive then return UI.IsQueuedHere(host, ctx) and L.HEAD_QUEUED:format(plan.name or "?") or L.HEAD_LOCKED_QUEUE end
    if ctx.locked then return L.HEAD_LOCKED end
    if ctx.committing then return L.COMMIT_BUSY end
    if ctx.kind == "legacy" and ns.Enabled("legacyReset") and not UI.LegacyResetBlocked(ctx) then return L.ACT_LEGACY end
    progress = progress or Plan.Progress(plan, ctx)
    if progress.need <= 0 then return L.ACT_DONE end
    local lead = progress.have == 0 and (L.ACT_NOTHING .. " ") or ""
    local free, need = progress.free, progress.need
    if free ~= nil and free <= 0 then return lead .. L.ACT_NOFREE end
    if free == nil or not progress.short then
        return lead .. (need == 1 and L.ACT_ALL_ONE or L.ACT_ALL:format(need))
    end
    local first, _, step = Plan.FirstApply(plan, ctx)
    if not first then
        if step then return lead .. L.ACT_ORDER_BLOCKED:format(step.name) end
        return lead .. L.ACT_BLOCKED
    end
    if first.order then
        return lead .. (free == 1 and L.ACT_ORDER_ONE:format(first.name) or L.ACT_ORDER_MANY:format(free, first.name))
    end
    return lead .. (free == 1 and L.ACT_POS_ONE:format(first.name) or L.ACT_POS_MANY:format(free, first.name))
end

-- Hinweise zur Vorschau, nach Gewicht: was den Plan ungültig macht, was im Baum anders steht, was fehlt.
local function PlanNotes(host, ctx, plan, progress, Note)
    if plan.kind == "preset" and plan.total and plan.total > 0 and (plan.found or 0) == 0 then
        Note(ns.Tone("bad", L.PRESET_UNMATCHED_TIP))
        Note(ns.SurveyHint())
        return
    end
    local check = Plan.Check(plan, ctx)
    if check.over then Note(ns.Tone("bad", L.PLAN_TOTAL_OVER:format(check.points, check.max))) end
    if #check.list > 0 then
        local first = check.list[1]
        Note(ns.Tone("invalid", L.HEAD_INVALID:format(Traits.NodeName(ctx.configID, first) .. " ("
            .. Plan.BadText(ctx, check.bad[first]) .. ")" .. (#check.list > 1 and (" " .. ezCore.More(#check.list - 1, true)) or ""))))
    end
    if progress.extra > 0 then Note(ns.Tone("bad", L.PLAN_EXTRA:format(progress.extra))) end
    if progress.other > 0 then Note(ns.Tone("orange", L.HEAD_OTHER:format(progress.other))) end
    if plan.kind == "preset" and plan.total and plan.total > 0 and (plan.found or 0) < plan.total then
        Note(ns.Tone("orange", L.PLAN_MATCH:format(plan.found or 0, plan.total, UI.JoinNames(plan.missing, 2))))
    end
    -- Reihenfolge (TL-01): steht im Satz zu „Übernehmen“ nur, wenn die Punkte nicht reichen – sonst hier
    local orderLine = UI.OrderText(plan, ctx, Plan.Points(plan), host.editing)
    if orderLine and not (progress.short and (progress.free or 0) > 0) then Note(orderLine) end
    if plan.edited then Note(ns.Tone("gold", L.PLAN_EDITED)) end
    if not Plan.CanShow(host.source()) then Note(L.PLAN_NO_TREE) end
end

-- Kopf des Seitenteils „Vorlagen“. → { title = gold Zeile, lines = { Zeilen darunter } (höchstens UI.HEAD_MAX_LINES),
-- notes = { alle Hinweise }, hidden = Zahl der Hinweise, die nur unter „?“ stehen }
function UI.HeadLines(host, ctx, panel)
    local plan = UI.ActivePlan(host, ctx)
    local out = { lines = {}, notes = {}, hidden = 0 }
    local function Note(text) if text and text ~= "" then out.notes[#out.notes + 1] = text end end
    local function Line(text) if text and text ~= "" then out.lines[#out.lines + 1] = text end end
    Note(UI.InsideText(panel))
    if Traits.HasStaged(ctx.configID) then Note(ns.Tone("gold", L.HEAD_STAGED)) end
    -- Vormerkung, zu der gefragt wurde (T7-NT2): solange die Rückfrage offen ist „wartet auf deine Antwort“, nach „Nein“
    -- (Core.Confirm meldet es über onCancel, host.queueDeclined) „fragt beim nächsten Öffnen wieder“
    local queued = UI.Queued()
    if queued and host.queueAsked == queued then
        local text = host.queueDeclined == queued and L.HEAD_QUEUE_WAIT or L.HEAD_QUEUE_ASKING
        Note(ns.Tone("gold", text:format(queued.name)))
    end
    local groups = ctx.kind == "class" and Traits.Groups(ctx.configID, ctx.treeID) or {}
    if plan then
        local split = Plan.Split(plan, ctx)
        out.title = #split > 0 and L.HEAD_PLAN_SPLIT:format(plan.name or "?", table.concat(split, "/"))
            or L.HEAD_PLAN:format(plan.name or "?")
        local progress = Plan.Progress(plan, ctx)
        if UI.EmptyReason(plan) then
            Line(L.HEAD_EMPTY_PLAN)
        elseif progress.free ~= nil then
            Line(L.HEAD_SET_FREE:format(progress.have, progress.want, progress.free))
        else
            Line(L.HEAD_SET:format(progress.have, progress.want))
        end
        Line(UI.ApplyText(host, ctx, plan, progress))
        PlanNotes(host, ctx, plan, progress, Note)
    else
        out.title = L.HEAD_NO_PLAN
        if ctx.kind == "class" then
            if #groups > 0 then Line(L.HEAD_TREES:format(Traits.GroupText(groups))) end
        else
            local free, _, total = Traits.Currency(ctx.configID, ctx.treeID)
            if free then Line(L.HEAD_FREE:format(free, total)) end
        end
        if not Traits.Available() then Line(L.HEAD_NOAPI) end
        Line(UI.ApplyText(host, ctx, nil))
    end
    Note(ns.OtherHint(ctx.kind == "class" and "talentTemplates" or "legacyPlanner"))
    -- höchstens UI.HEAD_NOTES Hinweise; sonst der erste und „+ n weitere unter „?““
    local room = UI.HEAD_NOTES
    if #out.notes > room then
        for i = 1, room - 1 do Line(out.notes[i]) end
        out.hidden = #out.notes - (room - 1)
        Line(ns.Tone("hint", UI.MoreText(out.hidden)))
    else
        for _, note in ipairs(out.notes) do Line(note) end
    end
    return out
end

-- Rest der Hinweise, die nur unter „?“ stehen: ezCores „… und 3 weitere“ bzw. „… und noch 1“ (Core.More, eine Stelle
-- für alle gekürzten Listen; Welle 23) plus Zusatz „unter „?““ – vorher eigene Texte HEAD_MORE/HEAD_MORE_ONE.
function UI.MoreText(count)
    return ezCore.More(count) .. " " .. L.HEAD_MORE_WHERE
end

-- Legende der Zahlen am Talent: je Zustand das Wort in seinem Ton (Plan.TONE) – vorher ein Satz im Kopf.
UI.LEGEND_ORDER = { "done", "open", "next", "locked", "extra", "other", "invalid" }
function UI.LegendLines()
    local lines = { L.LEGEND_TITLE }
    for _, state in ipairs(UI.LEGEND_ORDER) do
        lines[#lines + 1] = ns.Tone(Plan.TONE[state], L["LEGEND_" .. state] or state)
    end
    return lines
end

-- Tooltip des Knopfs „?“: Legende, alle Hinweise und die Einzelheiten (Punkte je Baum, Plan, Regeln, Reihenfolge).
function UI.HelpText(host, ctx)
    ctx = ctx or UI.Context(host)
    local parts = { table.concat(UI.LegendLines(), "\n") }
    if ctx then
        local details = { UI.HeadText(ctx) }
        local planText = UI.PlanText(host, ctx, true)
        if planText then details[#details + 1] = planText end
        local panel = host.panels and host.panels.templates
        local inside = UI.InsideText(panel)
        if inside then details[#details + 1] = inside end
        local other = ns.OtherHint(ctx.kind == "class" and "talentTemplates" or "legacyPlanner")
        if other then details[#details + 1] = other end
        parts[#parts + 1] = L.HELP_DETAILS .. "\n" .. table.concat(details, "\n")
    end
    return table.concat(parts, "\n\n")
end

-- Eigene Vorlagen mit Kennzeichen einmal neu zuordnen (Templates.RemapOwn), sobald das Seitenteil einen Baum hat. Eine
-- gerade geladene, unveränderte eigene Vorlage wird danach neu aus der Vorlage gebaut.
function UI.RemapOnce(host, ctx)
    if not (ctx and ctx.kind == "class" and not ctx.inspecting) then return nil end
    local out = Templates.RemapOwn(ctx.scope, ctx.configID, ctx.treeID)
    if not out then return nil end
    Templates.ReportRemap(out)
    if (#out.done + #out.better) > 0 and host.plan and host.plan.kind == "own" and not host.plan.edited then host.plan = nil end
    return out
end

-- Kästchen „Vor dem Übernehmen zurücksetzen“ (Einstellung legacyReset) als Zeile über die ganze Breite: Blizzards
-- Kästchen-Vorlage und ein Text in Blizzards Schrift; der Tooltip ist der der früheren Einstellung.
function UI.LegacyResetBox(panel)
    local row = CreateFrame("Frame", nil, panel)
    row:SetHeight(22)
    local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    check:SetSize(22, 22)
    check:SetPoint("LEFT", row, "LEFT", 0, 0)
    local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    label:SetPoint("LEFT", check, "RIGHT", 2, 0)
    label:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    label:SetJustifyH("LEFT")
    label:SetText(L.OPT_legacyReset)
    check:SetChecked(ns.Enabled("legacyReset"))
    check:SetScript("OnClick", function(self) ns.SetSetting("legacyReset", self:GetChecked() and true or false) end)
    check:SetScript("OnEnter", function(self) UI.ShowRowTip(self, L.OPT_legacyReset, L.OPT_legacyReset_TIP) end)
    check:SetScript("OnLeave", GameTooltip_Hide)
    row.check, row.label = check, label
    return row
end

local function BuildTemplatesPanel(host)
    local panel = NewPanel(host, L.TEMPLATES_TITLE)
    local w = 92
    panel.buttons = {
        save = Button(panel, L.BTN_SAVE, L.BTN_SAVE_TIP, function() UI.Save(host) end, w, true),
        -- inaktive Spezialisierung: derselbe Knopf merkt vor (Nr. 29, UI.ToggleQueue)
        apply = Button(panel, L.BTN_APPLY, L.BTN_APPLY_TIP, function()
            if UI.CanQueue(host) then UI.ToggleQueue(host) else UI.Apply(host) end
        end, w, true),
        edit = Button(panel, L.BTN_EDIT, L.BTN_EDIT_TIP, function() UI.ToggleEdit(host) end, w, true),
        share = Button(panel, L.BTN_SHARE, L.BTN_SHARE_TIP, function() UI.Share(host) end, w, true),
        rename = Button(panel, L.BTN_RENAME, L.BTN_RENAME_TIP, function() UI.Rename(host) end, w, true),
        -- Blizzards DELETE (Gesamtreview T18-22) über Core.Word – den Rückfall hält ezCore
        delete = Button(panel, Core.Word("DELETE"), L.BTN_DELETE_TIP, function() UI.Delete(host) end, w, true),
        import = Button(panel, L.BTN_IMPORT, L.BTN_IMPORT_TIP, function() UI.Import(host) end, w, true),
        roster = Button(panel, L.BTN_ROSTER, L.BTN_ROSTER_TIP, function() ns.Roster.Show() end, w, true),
        resetApply = Button(panel, L.BTN_RESET_APPLY, L.BTN_RESET_APPLY_TIP, function() UI.ResetApply(host) end, 188, true),
    }
    local b = panel.buttons
    -- Grund am gesperrten Knopf (T9-7): Teilen, Umbenennen, Löschen nur bei eigener Vorlage; Planen nur, wenn Blizzards
    -- Fenster den Plan zeigen kann; Speichern nur mit Talentbaum
    b.share.whyDisabled, b.rename.whyDisabled, b.delete.whyDisabled = L.BTN_OWN_ONLY, L.BTN_OWN_ONLY, L.BTN_OWN_ONLY
    b.edit.whyDisabled, b.save.whyDisabled = L.BTN_EDIT_BLOCKED, L.APPLY_FAIL_noconfig
    b.resetApply:SetShown(host.kind == "class")    -- Vermächtnis setzt beim Anwenden ohnehin zurück (legacyReset)
    -- Vermächtnis: „Vor dem Übernehmen zurücksetzen“ als Kästchen direkt bei „Übernehmen“ (Einstellungs-Prüfung
    -- 19.11.2026, Abschnitt 3: diese Wahl trifft man beim Übernehmen; vorher auf der Einstellungsseite)
    if host.kind == "legacy" then panel.legacyReset = UI.LegacyResetBox(panel) end
    -- Knopf „?“ rechts neben der ersten Kopfzeile: Legende der Farben, alle Hinweise und Einzelheiten (Spieltest
    -- 15.11.2026: die Legende stand als Fließtext im Kopf). Klick zeigt dasselbe (Leitlinie 3: sichtbarer Knopf).
    local function ShowHelp(self) UI.ShowRowTip(self, L.HELP_TITLE, UI.HelpText(host)) end
    panel.help = Button(panel, "?", nil, ShowHelp, UI.HELP_SIZE, true)
    panel.help:SetSize(UI.HELP_SIZE, UI.HELP_SIZE)
    panel.help:SetScript("OnEnter", ShowHelp)
    -- Reihenfolge wie der Ablauf: laden (Liste) » Übernehmen oder Anpassen » Speichern; darunter das Verwalten
    local order = { b.apply, b.edit, b.save, b.share, b.import, b.roster, b.rename, b.delete }
    function panel:LayoutButtons(width)
        return UI.LayoutButtons(self, width, order, host.kind == "class" and b.resetApply or panel.legacyReset) + 8
    end
    panel:Layout(panel.width or UI.PANEL_WIDTH)
    -- „Speichern“ sagt im Tooltip, was es gerade ablegt: die geladene Vorschau oder den Baum, wie er steht
    b.save:SetScript("OnEnter", function(self)
        local ctx = UI.Context(host)
        local plan = ctx and UI.ActivePlan(host, ctx)
        local why = DisabledReason(self)
        UI.ShowRowTip(self, L.BTN_SAVE, L.BTN_SAVE_TIP .. "\n\n" .. (why and ns.Tone("bad", why)
            or ns.Tone("gold", plan and L.BTN_SAVE_NOW_PLAN:format(plan.name or "?") or L.BTN_SAVE_NOW_CURRENT)))
    end)
    -- Wird das Seitenteil zugeklappt, endet das Planen: sonst nähmen die Talente weiter Klicks für den Plan an, ohne
    -- dass man sähe, warum (der Schalter steht im Seitenteil)
    panel:HookScript("OnHide", function(self)
        if self:IsShown() or not host.editing then return end
        UI.StopEditing(host)
        ns.Try("UI", UI.SyncPlan, host)
    end)
    -- Gesperrt zeigt der Knopf den Grund (Core.Toolbar.ShowTipWhileDisabled im Knopf-Helfer Button, T9-7)
    b.resetApply:SetScript("OnEnter", function(self)
        local why = UI.ResetBlocker(host)
        local tip = L.BTN_RESET_APPLY_TIP
        if why then tip = tip .. "\n\n" .. ns.Tone("bad", UI.BlockerText(why)) end
        UI.ShowRowTip(self, L.BTN_RESET_APPLY, tip)
    end)
    b.apply:SetScript("OnEnter", function(self)
        if UI.CanQueue(host) then
            local here = UI.IsQueuedHere(host)
            UI.ShowRowTip(self, here and L.BTN_QUEUE_OFF or L.BTN_QUEUE, here and L.BTN_QUEUE_OFF_TIP or L.BTN_QUEUE_TIP)
            return
        end
        local why = UI.ApplyBlocker(host)
        local tip = L.BTN_APPLY_TIP
        if why then tip = tip .. "\n\n" .. ns.Tone("bad", UI.BlockerText(why, true)) end
        UI.ShowRowTip(self, L.BTN_APPLY, tip)
    end)
    function panel:Render()
        local ctx = UI.Context(host)
        if not ctx then return end
        UI.RemapOnce(host, ctx)
        local head = UI.HeadLines(host, ctx, self)
        self.headInfo = head
        SetHead(self, table.concat(head.lines, "\n"), head.title, true)
        UI.Fill(self.scroll, UI.TemplateLines(host, ctx))
        local own = Selected(host, ctx) ~= nil                  -- Teilen, Umbenennen, Löschen: nur eigene Vorlagen
        local queue = UI.CanQueue(host, ctx)
        b.apply:SetText(queue and (UI.IsQueuedHere(host, ctx) and L.BTN_QUEUE_OFF or L.BTN_QUEUE) or L.BTN_APPLY)
        b.apply:SetEnabled(queue or UI.ApplyBlocker(host, ctx) == nil)
        b.edit:SetEnabled(Plan.CanShow(host.source()))
        b.edit:SetText(host.editing and L.BTN_EDIT_ON or L.BTN_EDIT)
        b.share:SetEnabled(own)
        b.rename:SetEnabled(own)
        b.delete:SetEnabled(own)
        b.save:SetEnabled(ctx.configID ~= nil)
        if ctx.kind == "class" then b.resetApply:SetEnabled(UI.ResetBlocker(host, ctx) == nil) end
        if self.legacyReset then self.legacyReset.check:SetChecked(ns.Enabled("legacyReset")) end
    end
    return panel
end

---------------------------------------------------------------------------
-- Seitenteil „Auswirkungen“
---------------------------------------------------------------------------

-- Vergleichsplan des Seitenteils „Auswirkungen“ (host.compare = { kind = "own" | "preset", key, name }), sonst nil.
function UI.ComparePlan(host, ctx)
    local cmp = host and host.compare
    if not (type(cmp) == "table" and ctx and ctx.scope) then return nil end
    if cmp.scope ~= ctx.scope then host.compare = nil return nil end
    if cmp.kind == "own" then return Plan.FromTemplate(ctx.scope, cmp.key) end
    if cmp.kind == "preset" and ctx.kind == "class" then
        for _, preset in ipairs(Templates.Presets()) do
            if preset.key == cmp.key then return Plan.FromPreset(preset, ctx) end
        end
    end
    return nil
end

-- Abschnitt „Werte“: was die gewählten Talente laut ihrem Text an Werten bewirken, mit Vergleich zu einer Vorlage
-- (Effects.StatTotals, Effects.CompareStats). plan: der schon bestimmte Vergleichsplan (false = keiner); ohne Angabe
-- wird er hier bestimmt. → Zeilen
function UI.StatLines(host, ctx, items, plan)
    local lines = {}
    local now, recognised, general = Effects.StatTotals(items)
    if plan == nil then plan = UI.ComparePlan(host, ctx) end
    plan = plan or nil
    local other = plan and Effects.StatTotals(Effects.PlanItems(ctx.configID, ctx.treeID, plan)) or nil
    local rows = Effects.CompareStats(now, other)
    lines[#lines + 1] = { text = L.EFFECTS_STATS, font = "GameFontNormal" }
    if plan then
        lines[#lines + 1] = { text = ns.Tone("gold", L.EFFECTS_COMPARE_WITH:format(plan.name or "?")), indent = 6, gap = 2 }
    end
    for _, row in ipairs(rows) do
        local text = (L["STAT_" .. row.key] or row.key) .. "  " .. Effects.StatValue(row.now, row.percent)
        if row.diff then
            local tone = row.diff > 0 and "good" or (row.diff < 0 and "bad" or "hint")
            text = text .. "  " .. ns.Tone("hint", L.EFFECTS_COMPARE_VALUE:format(Effects.StatValue(row.other, row.percent)))
                .. " " .. ns.Tone(tone, "(" .. (row.diff == 0 and L.EFFECTS_COMPARE_SAME or Effects.StatValue(row.diff, row.percent)) .. ")")
        end
        lines[#lines + 1] = { text = text, indent = 6, font = "GameFontHighlight" }
    end
    if #rows == 0 then lines[#lines + 1] = { text = ns.Tone("hint", L.EFFECTS_STATS_NONE), indent = 6 } end
    -- Quelle (Leitlinie 11): aus den Texten des Clients, wie viele Talente ohne Zauberbezug erkannt wurden
    lines[#lines + 1] = { text = ns.Tone("hint", L.EFFECTS_STATS_SOURCE:format(recognised, general)), indent = 6, gap = 8 }
    return lines
end

-- plan: wie bei UI.StatLines (panel:Render bestimmt ihn einmal und gibt ihn weiter)
function UI.EffectLines(ctx, host, plan)
    local lines = {}
    local items = Effects.Collect(ctx.configID, ctx.treeID)
    local new, removed, changed = Effects.Changes(items)
    if new + removed + changed > 0 then
        lines[#lines + 1] = { text = L.EFFECTS_PREVIEW:format(new, changed, removed), font = "GameFontNormalSmall", gap = 6 }
    end
    if #items > 0 or (host and host.compare) then
        for _, line in ipairs(UI.StatLines(host, ctx, items, plan)) do lines[#lines + 1] = line end
    end
    for _, group in ipairs(Effects.Grouped(items)) do
        lines[#lines + 1] = { text = group.title, font = "GameFontNormal" }
        for _, item in ipairs(group.items) do
            local tone = STATE_TONE[item.state]
            lines[#lines + 1] = { text = (tone and ns.Tone(tone, item.name) or item.name) .. "  " .. ns.Tone("hint", Effects.RankText(item)),
                indent = 6, font = "GameFontHighlight" }
            -- Schwellen und Stufe des Talents bzw. Vorteils (TL-09), mit Stand: erfüllt oder fehlt
            for _, need in ipairs(item.needs or {}) do
                lines[#lines + 1] = { text = ns.Tone(need.met and "hint" or "orange", L.EFFECTS_NEED:format(need.text)
                    .. " – " .. (need.met and L.EFFECTS_NEED_MET or L.EFFECTS_NEED_OPEN)), indent = 12 }
            end
            if item.state == "changed" and item.textBefore and item.textBefore ~= "" then
                lines[#lines + 1] = { text = ns.Tone("hint", L.EFFECTS_BEFORE .. " " .. item.textBefore), indent = 12 }
                lines[#lines + 1] = { text = L.EFFECTS_AFTER .. " " .. (item.text or ""), indent = 12, gap = 6 }
            elseif item.state == "removed" then
                lines[#lines + 1] = { text = ns.Tone("hint", item.text or ""), indent = 12, gap = 6 }
            else
                lines[#lines + 1] = { text = item.text ~= "" and item.text or L.EFFECTS_NO_TEXT, indent = 12, gap = 6 }
            end
        end
    end
    if #items == 0 then lines[#lines + 1] = { text = L.EFFECTS_EMPTY, font = "GameFontDisableSmall" } end
    return lines
end

-- Menü „Vergleichen mit“: nichts, eigene Vorlagen dieses Baums, (am Talentfenster) die Vorauswahl der Klasse.
function UI.CompareMenu(host, root)
    local ctx = UI.Context(host)
    if not ctx then return end
    local function Get() local c = host.compare return c and (c.kind .. ":" .. tostring(c.key)) or "none" end
    local function Set(value)
        if value == "none" then
            host.compare = nil
        else
            local kind, key = value:match("^(%a+):(.+)$")
            host.compare = { kind = kind, key = key, scope = ctx.scope }
        end
        UI.Refresh()
    end
    Core.Menu.Radio(root, L.EFFECTS_COMPARE_NONE, Get, Set, "none")
    local names = Templates.Names(ctx.scope)
    if #names > 0 then
        Core.Menu.Title(root, L.EFFECTS_COMPARE_OWN)
        for _, name in ipairs(names) do Core.Menu.Radio(root, name, Get, Set, "own:" .. name) end
    end
    if ctx.kind == "class" then
        local presets = Templates.Presets()
        if #presets > 0 then
            Core.Menu.Title(root, L.EFFECTS_COMPARE_PRESETS)
            for _, preset in ipairs(presets) do
                if preset.key then Core.Menu.Radio(root, Templates.PresetName(preset), Get, Set, "preset:" .. preset.key) end
            end
        end
    end
end

local function BuildEffectsPanel(host)
    local panel = NewPanel(host, L.EFFECTS_TITLE)
    -- Sichtbarer Knopf für den Vergleich (Leitlinie 3): öffnet die Auswahl der Vorlage
    panel.buttons = {
        compare = Button(panel, L.BTN_COMPARE, L.BTN_COMPARE_TIP, function(self)
            if not Core.Menu.Open(self, function(root) UI.CompareMenu(host, root) end) then ns.Print(L.BTN_COMPARE_NOMENU) end
        end, 188, true),
    }
    function panel:LayoutButtons(width)
        return UI.LayoutButtons(self, width, {}, self.buttons.compare) + 8
    end
    panel:Layout(panel.width or UI.PANEL_WIDTH)
    function panel:Render()
        local ctx = UI.Context(host)
        if not ctx then return end
        SetHead(self, UI.HeadText(ctx))
        local plan = UI.ComparePlan(host, ctx)
        self.buttons.compare:SetText(plan and L.BTN_COMPARE_ON:format(plan.name or "?") or L.BTN_COMPARE)
        UI.Fill(self.scroll, UI.EffectLines(ctx, host, plan or false))
    end
    return panel
end

---------------------------------------------------------------------------
-- Seitenteil „Twinks“ (TL-12): die Übersicht der eigenen Charaktere als drittes Seitenteil am Talentfenster
-- (vorher nur ein Textfenster). Je Twink eine Zeile „Name · Stufe Klasse · Punkte je Baum“; ein Klick klappt die
-- Einzelheiten auf (Vorlage, Berufe, Vermächtnis) – ein zweiter wieder zu. Die Daten kommen aus Roster.List
-- (ezCores Charakterliste und Berufe, dazu was ezTalent je Twink merkt); „Als Text zeigen“ öffnet den Text zum Kopieren.
---------------------------------------------------------------------------

function UI.RosterLines(host)
    local lines = {}
    for _, row in ipairs(ns.Roster.List()) do
        local open = host.rosterOpen == row.key
        local name = row.name .. (row.isMe and (" " .. L.ROSTER_ME) or "")
        local details = ns.Roster.Details(row)
        lines[#lines + 1] = { text = name .. " " .. ns.Tone("hint", "· " .. ns.Roster.Head(row) .. " · " .. (row.talents or L.ROSTER_UNKNOWN))
            .. (open and "" or ("  " .. ns.Tone("hint", Core.ARROW))), font = "GameFontHighlight", selected = open, tipTitle = row.name,
            tip = table.concat(details, "\n") .. "\n\n" .. L.ROSTER_ROW_TIP, gap = open and 2 or 4,
            onClick = function()
                host.rosterOpen = (host.rosterOpen ~= row.key) and row.key or nil
                UI.Refresh()
            end }
        if open then
            for i, detail in ipairs(details) do
                lines[#lines + 1] = { text = ns.Tone("detail", detail), indent = 14, gap = i == #details and 8 or 2 }
            end
        end
    end
    if #lines == 0 then lines[1] = { text = L.ROSTER_EMPTY, font = "GameFontDisableSmall" } end
    return lines
end

local function BuildRosterPanel(host)
    local panel = NewPanel(host, L.ROSTER_PANEL_TITLE)
    panel.buttons = {
        text = Button(panel, L.BTN_ROSTER_TEXT, L.BTN_ROSTER_TEXT_TIP, function() ns.Roster.ShowText() end, 188, true),
    }
    function panel:LayoutButtons(width)
        return UI.LayoutButtons(self, width, {}, self.buttons.text) + 8
    end
    panel:Layout(panel.width or UI.PANEL_WIDTH)
    function panel:Render()
        SetHead(self, L.ROSTER_HINT)
        UI.Fill(self.scroll, UI.RosterLines(host))
    end
    return panel
end

---------------------------------------------------------------------------
-- Reiter und Fenster
---------------------------------------------------------------------------

-- „Vorlagen“ steht an beiden Fenstern immer (Einstellungs-Prüfung 19.11.2026, Nr. 37 und 39: Kernfunktion, öffnet sich
-- nur auf Klick; bis dahin Schalter templatesTab bzw. legacyTab).
local function TabEnabled(host, key)
    if key == "effects" then return ns.Enabled("effectsTab") end
    if key == "roster" then return ns.Enabled("rosterTab") end
    return true
end

-- Welches Seitenteil war an diesem Fenster zuletzt offen? (ezTalentDB.ui.open[kind] = Schlüssel oder false)
-- Noch nie gemerkt: am Talentfenster „Vorlagen“ (Spieltest 14.11.2026: beim Öffnen war nichts von ezTalent zu sehen),
-- am Vermächtnis-Fenster nichts.
local function OpenStore(create)
    local ui = ns.db and ns.db.ui
    if type(ui) ~= "table" then return nil end
    if type(ui.open) ~= "table" then
        if not create then return nil end
        ui.open = {}
    end
    return ui.open
end

function UI.RememberedOpen(host)
    local store = OpenStore(false)
    local key = store and store[host.kind]
    if key == nil and host.kind == "class" then key = "templates" end
    return (type(key) == "string" and host.panels[key]) and key or nil
end

function UI.RememberOpen(host)
    local store = OpenStore(true)
    if store then store[host.kind] = host.open or false end
end

-- quiet = true: nur zeigen, nichts merken (Wiederherstellen beim Öffnen des Fensters)
function UI.Toggle(host, key, quiet)
    local panel = host.panels[key]
    if not panel then return end
    if host.open == key and panel:IsShown() then
        panel:Hide()
        host.open = nil
        UI.GiveRoom(host)      -- kein Seitenteil mehr offen: Blizzards Lage und Größe zurück (TL-13)
    else
        -- Wechsel zwischen Seitenteilen: Blizzards Fenster bleibt, wo es ist (kein Zurück und gleich wieder Rücken)
        host.switching = true
        for other, p in pairs(host.panels) do
            if other ~= key then p:Hide() end
        end
        host.switching = nil
        host.open = key
        UI.Place(host, panel, true)
        panel:Show()
        ns.Try("UI", panel.Render, panel)
    end
    if not quiet then UI.RememberOpen(host) end
    TourSoon(host)
end

-- Ein Seitenteil öffnen (offen lassen, wenn es schon offen ist). → true, wenn es jetzt offen ist
function UI.Open(host, key)
    local panel = host and host.panels[key]
    if not (panel and TabEnabled(host, key)) then return false end
    if host.open == key and panel:IsShown() then
        ns.Try("UI", panel.Render, panel)
    else
        UI.Toggle(host, key)
    end
    return host.open == key
end

-- /ezt twinks, Knopf „Twinks“ (Einstellungen, Seitenteil „Vorlagen“): das Seitenteil „Twinks“ am Talentfenster
-- öffnen – das Fenster vorher öffnen, wenn es zu ist (nicht im Kampf). → true, wenn das Seitenteil jetzt zu sehen ist;
-- false = Rückfall Text (Roster.Show)
function UI.ShowRoster()
    if not ns.Enabled("rosterTab") then return false end
    local host = UI.hosts.class
    if not (host and Read(host.parent, "IsVisible") == true) then
        if Core.InCombat() then return false end
        ns.OpenTalents()
        host = UI.hosts.class
    end
    if not (host and Read(host.parent, "IsVisible") == true) then return false end
    host.restored = true      -- nicht danach noch das gemerkte Seitenteil aufklappen (RestoreOpen)
    return UI.Open(host, "roster")
end

-- Beim ersten Öffnen des Fensters in dieser Sitzung das zuletzt offene Seitenteil wieder aufklappen – nur wenn es
-- außen neben das Fenster passt, notfalls nachdem ezTalent Platz gemacht hat (TL-13); innen verdeckte es den Baum, das
-- soll nie von selbst geschehen.
function UI.RestoreOpen(host)
    if host.restored then return end
    host.restored = true
    if host.open then return end
    local key = UI.RememberedOpen(host)
    if not (key and TabEnabled(host, key)) then return end
    if UI.PanelWidth(host.anchor, host.panels[key], host.gap) == nil and not UI.CanMakeRoom(host, host.panels[key]) then return end
    UI.Toggle(host, key, true)
end

local TAB_ICONS = { templates = "Interface\\Icons\\INV_Misc_Book_09", effects = "Interface\\Icons\\INV_Misc_Book_11",
    roster = "Interface\\Icons\\INV_Misc_GroupNeedMore" }

local function BuildTab(host, key, order, title, tip)
    local tab = Core.CreateSideTab(host.parent, { key = "ezTalent." .. key, order = order, anchor = host.anchor,
        start = host.tabStart, owner = ADDON })
    if type(tab.Icon) == "table" then tab.Icon:SetTexture(TAB_ICONS[key]) end
    tab:SetScript("OnClick", Core.SideTabClick(function() UI.Toggle(host, key) end))
    tab:SetScript("OnEnter", function(self) Core.ShowTip(self, title, tip, "ANCHOR_RIGHT") end)
    return tab
end

-- Ein Knopf „Vorlagen“ (Spielbefund des Nutzers vom 19.11.2026: „talente hat 2 vorlagen buttons... unsinn“): der
-- Seitenreiter im Stapel mit „Auswirkungen“ und „Twinks“. Der zweite Klappknopf „Vorlagen »“ neben Blizzards Suchfeld
-- (BuildToggle, UI.UpdateToggle, PlaceClassToggle, UI.TOGGLE_LEVEL) ist entfernt – er öffnete dasselbe Seitenteil.

function UI.ApplySettings()
    for _, host in pairs(UI.hosts) do
        for key, tab in pairs(host.tabs) do
            local on = TabEnabled(host, key)
            tab:SetShown(on)
            if not on and host.panels[key] then host.panels[key]:Hide() end
        end
        TourSoon(host)
        -- „Talentfenster rücken“ aus: Blizzards Lage und Größe sofort zurück, das offene Seitenteil neu setzen
        if host.moved and not ns.Enabled("makeRoom") then
            UI.GiveRoom(host)
            ns.Try("UI", UI.PlaceOpen, host)
        elseif ns.Enabled("makeRoom") and host.open and host.panels[host.open] and host.panels[host.open].inside then
            ns.Try("UI", UI.PlaceOpen, host)        -- wieder an: gleich Platz machen statt innen
        end
    end
end

-- Die geladene Vorschau in Blizzards Baum zeigen bzw. abgleichen (Plan.Sync) – auch bei zugeklapptem Seitenteil,
-- solange das Fenster offen und „Vorlagen“ an diesem Fenster eingeschaltet ist. → Zahl der gezeigten Zahlen
function UI.SyncPlan(host)
    if Read(host.parent, "IsVisible") ~= true then return 0 end
    local ctx = UI.Context(host)
    -- nie über dem Baum eines betrachteten Spielers: die Zahlen gälten dessen Rängen
    local plan = ctx and not ctx.inspecting and TabEnabled(host, "templates") and UI.ActivePlan(host, ctx) or nil
    return Plan.Sync(host, ctx, plan, {
        editing = host.editing == true and plan ~= nil,
        onAdjust = function(nodeID, delta) UI.AdjustPlan(host, nodeID, delta) end,
        tipFn = function(nodeID)
            local now = UI.Context(host)
            local node = now and Traits.Node(now.configID, nodeID)
            if not node then return nil end
            return Plan.TipText(UI.ActivePlan(host, now), now, node)
        end,
    })
end

-- Nur sichtbare Seitenteile neu zeichnen: ein offenes Seitenteil bleibt „shown“, wenn Blizzards Fenster zugeht
-- (Kind des Fensters) – IsVisible prüft auch die Eltern.
function UI.Refresh()
    -- Vormerkung für die (bisher) inaktive Spezialisierung zuerst (Nr. 29); sie ruft UI.Apply und damit UI.Refresh erneut
    if UI.hosts.class then ns.Try("UI", UI.RunQueued, UI.hosts.class) end
    for _, host in pairs(UI.hosts) do
        local panel = host.open and host.panels[host.open]
        if panel and panel:IsVisible() then ns.Try("UI", panel.Render, panel) end
        ns.Try("UI", UI.SyncPlan, host)
    end
end

local refreshSoon = ns.Throttle(function() UI.Refresh() end, 0.2)

-- Offenes Seitenteil neu setzen (das Fenster kann seit dem letzten Mal woanders stehen oder anders skaliert sein);
-- passt es nicht mehr, darf ezTalent wieder Platz machen (TL-13).
function UI.PlaceOpen(host)
    local panel = host.open and host.panels[host.open]
    if panel and panel:IsShown() and Read(host.parent, "IsVisible") == true then return UI.Place(host, panel, true) end
end

-- host = { kind, parent (Elternrahmen für Reiter und Seitenteile), anchor (Rand für Reiter und Andocken),
--          source = function → Blizzards Trait-Rahmen (für GetConfigID/GetTalentTreeID),
--          tabStart (y des ersten Reiters, nil = ezCores Standard), gap (Abstand des Seitenteils), inset,
--          mover (function → Blizzards Fenster, das für das Seitenteil weichen darf, TL-13), moved (gemerkter Ausgang) }
-- opts (freiwillig): { tabStart, gap, inset, mover = function → Rahmen }
function UI.Attach(kind, parent, anchor, source, opts)
    if UI.hosts[kind] or type(parent) ~= "table" then return UI.hosts[kind] end
    opts = opts or {}
    local host = { kind = kind, parent = parent, anchor = anchor or parent, source = source, tabs = {}, panels = {},
        tabStart = opts.tabStart, gap = opts.gap or UI.DockGap(), inset = opts.inset or UI.INSET, mover = opts.mover }
    UI.hosts[kind] = host
    host.panels.templates = BuildTemplatesPanel(host)
    host.panels.effects = BuildEffectsPanel(host)
    host.tabs.templates = BuildTab(host, "templates", 10, L.TEMPLATES_TITLE,
        kind == "class" and L.TAB_TEMPLATES_TIP or L.TAB_LEGACY_TIP)
    host.tabs.effects = BuildTab(host, "effects", 20, L.EFFECTS_TITLE, L.TAB_EFFECTS_TIP)
    if kind == "class" then   -- Twinks nur am Talentfenster (TL-12), Reiter-Zahl 30
        host.panels.roster = BuildRosterPanel(host)
        host.tabs.roster = BuildTab(host, "roster", 30, L.ROSTER_PANEL_TITLE, L.TAB_ROSTER_TIP)
    end
    local frame = source()
    if type(frame) == "table" and type(frame.SetTalentTreeID) == "function" then
        hooksecurefunc(frame, "SetTalentTreeID", function() refreshSoon() end)
    end
    -- Blizzards Bestätigung beginnt bzw. endet (TalentFrameBaseMixin:SetCommitStarted): Knöpfe neu sperren bzw.
    -- freigeben, eine wartende Vormerkung danach setzen (T7-NT1). Nur zugehört.
    if type(frame) == "table" and type(frame.SetCommitStarted) == "function" then
        hooksecurefunc(frame, "SetCommitStarted", function() refreshSoon() end)
    end
    -- Blizzards Fensterverwaltung setzt Lage und Skala erst nach dem Zeigen – darum einen Takt später. Danach neu
    -- zeichnen: solange das Fenster zu war, hat UI.Refresh das offene Seitenteil übersprungen.
    local function Shown()
        C_Timer.After(0, function()
            ns.Try("UI", UI.PlaceOpen, host)
            ns.Try("UI", UI.RestoreOpen, host)
            UI.Refresh()
            TourSoon(host)
        end)
    end
    parent:HookScript("OnShow", Shown)
    -- Fenster zu: Planen aus – beim nächsten Öffnen gehen Klicks wieder an Blizzards Talente. Und die Erklärblase
    -- weg: sie kommt beim nächsten Öffnen nur wieder, wenn sie dann stehen darf (nicht im Kampf, nicht über dem Baum
    -- eines betrachteten Spielers).
    parent:HookScript("OnHide", function()
        host.queueAsked, host.queueYes, host.queueDeclined = nil, nil, nil   -- beim nächsten Öffnen wieder fragen (T7-NT2)
        UI.StopEditing(host)
        UI.GiveRoom(host)       -- Fenster zu: Blizzards Lage und Größe zurück (TL-13)
        TourSoon(host)
    end)
    UI.ApplySettings()
    -- Blizzard_PlayerSpells lädt erst beim ersten Öffnen: dann ist das Fenster schon offen, bevor ezTalent sich
    -- anhängt, und OnShow kommt nicht mehr – deshalb gleich nachholen.
    if Read(parent, "IsVisible") == true then Shown() end
    return host
end

local function AttachClass()
    local spells = rawget(_G, "PlayerSpellsFrame")
    local talents = spells and spells.TalentsFrame
    if not talents then return end
    -- Platz machen (TL-13) darf nur Blizzards äußeres Fenster (PlayerSpellsFrame), nie das Talentfenster darin
    UI.Attach("class", talents, talents, function() return talents end, {
        mover = function() return rawget(_G, "PlayerSpellsFrame") end })
end

local function AttachLegacy()
    local legacy = rawget(_G, "LegacySystemFrame")
    local page = legacy and legacy.TreePage
    if not page then return end
    -- Blizzards drei Reiter (Belohnungen, Herausforderungen, Vermächtnis) freihalten: eigener Stapel darunter,
    -- Seitenteil hinter dem breitesten Reiter.
    local start, width = UI.TabsBelow(UI.BlizzardTabs(legacy))
    UI.Attach("legacy", page, legacy, function() return page.LegacyTreeTraitPanel end,
        { tabStart = start, gap = UI.DockGap(width) })
end

ns.OnReady(function()
    ns.WhenAddOnLoaded("Blizzard_PlayerSpells", AttachClass)
    ns.WhenAddOnLoaded("Blizzard_LegacySystem", AttachLegacy)
    for _, event in ipairs({ "TRAIT_CONFIG_UPDATED", "TRAIT_NODE_CHANGED", "TRAIT_TREE_CURRENCY_INFO_UPDATED",
        "TRAIT_TREE_CHANGED", "ACTIVE_COMBAT_CONFIG_CHANGED", "PLAYER_TALENT_UPDATE" }) do
        ns.On(event, function() refreshSoon() end)
    end
    ns.Listen("TEMPLATES_CHANGED", function() refreshSoon() end)
    -- Blizzard (oder ezCores „Blizzard-Fenster verschieben“) hat Fenster neu gesetzt: offenes Seitenteil neu prüfen –
    -- ein gerücktes Fenster kann wieder an Blizzards Platz stehen (TL-13)
    Core.Listen("FRAME_MOVED", function()
        for _, host in pairs(UI.hosts) do
            if host.open then C_Timer.After(0, function() ns.Try("UI", UI.PlaceOpen, host) end) end
        end
    end, ADDON)
    ns.OnSettingChanged(function()
        UI.ApplySettings()
        UI.Refresh()
    end)
    -- Blizzard baut die Talentknöpfe neu auf (anderer Baum, andere Spezialisierung, Zurücksetzen): die Zahlen der
    -- Vorschau gehören dann an andere Knöpfe (Blizzard_SharedTalentFrame.lua meldet „TalentFrameBase.ButtonsUpdated“)
    local registry = rawget(_G, "EventRegistry")
    if type(registry) == "table" and type(registry.RegisterCallback) == "function" then
        Core.Call(registry.RegisterCallback, registry, "TalentFrameBase.ButtonsUpdated", function() refreshSoon() end, UI)
    end
end)
