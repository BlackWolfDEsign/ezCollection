local Core = ezCore

--[[
    Design-System: Werte und kleine Helfer (Welle 22, Zweig kern/design-system; Wunsch des Nutzers vom 15.11.2026
    abends: „blizzlike … bestehendes erweitern und modifizieren … konsistent“). Regeln mit Belegen: docs/design-system.md.

    Eine Quelle für Werte, die vorher in mehreren Modulen von Hand standen: Ebenen (SetFrameStrata), Symbolgrößen,
    Schrift-Rollen (Blizzards FontObjects) und Farb-Rollen (Blizzards Farbobjekte, ezCores Farbcodes aus Format.lua).
    tools/design.lua liest diese Datei offline und prüft die Module dagegen – Werte nur hier ändern. Die Datei läuft
    darum auch ohne den Rest von ezCore (nur Tabellen und Funktionen, beim Laden wird nichts gerufen).

    Werte (nur lesen):
      ezCore.Style.STRATA[rolle]   Ebene je Rolle: world = "LOW" (Überlagerung der Spielwelt, Anzeige über dem
                                   Charakter), hud = "MEDIUM" (Leisten und Teile wie Blizzards Leisten, eigene Fenster
                                   wie Blizzards Fenster), dialog = "DIALOG" (eigene Dialoge und Aufklappteile)
      ezCore.Style.STRATA_RULE     { LOW, MEDIUM, DIALOG } = true – ohne Eintrag in der Ausnahmeliste von
                                   tools/design.lua erlaubt; alles andere braucht dort einen Eintrag mit Begründung
      ezCore.Style.ICON[rolle]     Symbolgröße in Pixeln: line = 16 (Zeile in Menü und Liste), aura = 30 (Buff),
                                   small = 30 (kleiner Aktionsknopf), item = 37 (Gegenstand, Taschenplatz),
                                   action = 45 (Aktionsknopf)
      ezCore.Style.BUTTON[rolle]   quadratischer Knopf ohne Symbol: close = 24, check = 20, small = 16
      ezCore.Style.FONT[rolle]     Name von Blizzards FontObject: title, heading, label, text, value, hint, off,
                                   number, numberSmall, error
      ezCore.Style.COLOR[rolle]    { object = Name von Blizzards Farbobjekt, code = Name in ezCore (Core.GOLD …),
                                   r, g, b = Rückfall }: normal, highlight, disabled, gray, good, bad, warn; seit
                                   Welle 23a auch orange (Warnung, Marke), blue (Hinweis, Hellblau), bnet (Battle.net-
                                   Freunde) und link (Web-Adresse)

    Helfer (alle vertragen fehlende Blizzard-Objekte und geben dann nil bzw. false zurück):
      ezCore.Style.Strata(rolle) → Ebene oder nil
      ezCore.Style.SetStrata(rahmen, rolle) → true/false. rolle = "world" | "hud" | "dialog" | "parent" (Ebene des
                                   Elternrahmens übernehmen; gesperrt oder ohne Eltern: nichts tun, false)
      ezCore.Style.IconSize(rolle) → Zahl oder nil (Rolle aus ICON, sonst aus BUTTON – "small" ist darum das Symbol
                                   des kleinen Aktionsknopfs, 30)
      ezCore.Style.ButtonSize(rolle) → Zahl oder nil (nur BUTTON: "small" = 16, "close", "check"; Welle 23a)
      ezCore.Style.Font(rolle) → Blizzards FontObject oder nil
      ezCore.Style.SetFont(text, rolle) → true/false (SetFontObject mit Blizzards FontObject der Rolle)
      ezCore.Style.Color(rolle) → r, g, b, farbobjekt (Blizzards Objekt, sonst der Rückfall; unbekannt: nil)
      ezCore.Style.SetTextColor(text, rolle, alpha) → true/false: SetTextColor mit genau r, g, b (und alpha, wenn als
                                   Zahl angegeben) der Rolle – nie der vierte Wert von Style.Color als Alpha (Welle 23a;
                                   tools/design.lua meldet Style.Color direkt in SetTextColor als Fehler)
      ezCore.Style.ColorText(rolle, text) → text in der Farbe der Rolle (Blizzards WrapTextInColorCode, sonst ezCores
                                   Farbcode). Ein gesperrter Text bleibt unangetastet (Leitlinie 6).
      ezCore.Style.AllText(an) → „Alle auswählen“ (an) bzw. „Alle abwählen“: Blizzards CHECK_ALL/UNCHECK_ALL zuerst,
                                   sonst ezCores ALL_CHECK/ALL_UNCHECK (Regel „Mehrfachauswahl“; Bausteine dazu:
                                   Core.Menu.AllToggle im Menü, page:AllToggle auf der Einstellungsseite).
                                   Schutz: Blizzards UNCHECK_ALL heißt im deutschen Client „Alle Auswählen“; gleicht
                                   der Text für „aus“ ohne Groß-/Kleinschreibung CHECK_ALL oder ALL_CHECK, kommt
                                   ezCores ALL_UNCHECK
]]

local Style = Core.Style or {}
Core.Style = Style

-- Ebenen je Rolle. Belege in Blizzards Forever-Quelle (Gethe/wow-ui-source, Zweig forever):
--   LOW     Blizzard_UnitFrame/Mainline/PlayerFrame.xml (PlayerFrame frameStrata="LOW"),
--           Blizzard_ChatFrameBase/Mainline/FloatingChatFrame.xml (DockManagerTemplate LOW)
--   MEDIUM  FloatingChatFrame.xml (ChatTabTemplate, ChatFrameMenuButton MEDIUM), Blizzard_MapCanvas.xml
--           (MapCanvasFrameTemplate MEDIUM), Mainline/ContainerFrame.xml (ContainerFrameTemplate MEDIUM); Vorgabe
--           jedes Rahmens unter UIParent
--   DIALOG  Blizzard_EditMode/Shared/EditModeManager.xml (EditModeManagerFrame DIALOG),
--           Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml (BottomPopupScrollBoxTemplate DIALOG)
Style.STRATA = { world = "LOW", hud = "MEDIUM", dialog = "DIALOG" }
Style.STRATA_RULE = { LOW = true, MEDIUM = true, DIALOG = true }

-- Symbolgrößen. Belege (Forever-Quelle):
--   line   16  Blizzard_SharedXML/Mainline/UIDropDownMenu.lua (icon:SetSize(16,16))
--   aura   30  Blizzard_BuffFrame/BuffFrameTemplates.xml (AuraButtonArtTemplate, Icon 30 × 30)
--   small  30  Blizzard_ActionBar/Mainline/ActionButtonTemplate.xml (SmallActionButtonTemplate 30 × 30)
--   item   37  Blizzard_ItemButton/Shared/ItemButtonTemplate.xml (37 × 37); Taschenplätze in
--              Blizzard_MainMenuBarBagButtons/Camelot/MainMenuBarBagButtons.xml ebenfalls 37 × 37
--   action 45  ActionButtonTemplate.xml (ActionButtonTemplate 45 × 45)
Style.ICON = { line = 16, aura = 30, small = 30, item = 37, action = 45 }

-- Quadratische Knöpfe ohne Symbol. Belege: Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml
--   close 24  UIPanelCloseButtonNoScripts, UIPanelHideButtonNoScripts (24 × 24)
--   check 20  NineSliceCheckButtonTemplate (20 × 20)
--   small 16  UIPanelInfoButton, PanelResizeButtonTemplate (16 × 16)
Style.BUTTON = { close = 24, check = 20, small = 16 }

-- Schrift-Rollen, abgebildet auf Blizzards FontObjects (Blizzard_Fonts_Shared/Shared/GameFonts.xml). Die Rollen
-- decken die Schriften ab, die die Module heute schon nutzen (Bestandsaufnahme in docs/design-system.md).
Style.FONT = {
    title = "GameFontNormalLarge",          -- Überschrift eines Fensters oder Abschnitts
    heading = "GameFontNormal",             -- Kopf einer Gruppe, Name in Gold
    label = "GameFontNormalSmall",          -- Beschriftung (Gold, klein)
    text = "GameFontHighlightSmall",        -- Fließtext und Werte (weiß, klein)
    value = "GameFontHighlight",            -- hervorgehobener Wert (weiß)
    hint = "GameFontDisableSmall",          -- Erklärung, „wartet auf Daten“ (grau, klein)
    off = "GameFontDisable",                -- ausgeschaltet (grau)
    number = "NumberFontNormal",            -- Zahl auf einem Symbol (Stapel, Anzahl)
    numberSmall = "NumberFontNormalSmall",  -- kleine Zahl auf einem Symbol
    error = "GameFontRedSmall",             -- Fehler, fehlt (rot, klein)
}

-- Farb-Rollen: Blizzards Farbobjekt zuerst, ezCores Farbcode (Kern/Format.lua) als zweiter Weg, Zahlen als Rückfall.
-- Die eigene Palette von ezCore sind nur Core.GLOW_COLORS/GLOW_KINDS (Bausteine/Highlight.lua) – keine weiteren hier.
Style.COLOR = {
    normal    = { object = "NORMAL_FONT_COLOR",    code = "GOLD",   r = 1,    g = 0.82, b = 0 },
    highlight = { object = "HIGHLIGHT_FONT_COLOR", code = "WHITE",  r = 1,    g = 1,    b = 1 },
    disabled  = { object = "DISABLED_FONT_COLOR",                   r = 0.5,  g = 0.5,  b = 0.5 },
    gray      = { object = "GRAY_FONT_COLOR",      code = "GREY",   r = 0.5,  g = 0.5,  b = 0.5 },
    good      = { object = "GREEN_FONT_COLOR",     code = "GREEN",  r = 0.1,  g = 1,    b = 0.1 },
    bad       = { object = "RED_FONT_COLOR",       code = "RED",    r = 1,    g = 0.1,  b = 0.1 },
    warn      = { object = "YELLOW_FONT_COLOR",    code = "YELLOW", r = 1,    g = 1,    b = 0 },
    -- Welle 23a (A4; Wunsch aus ezChat, ezAuction, ezMacro, ezPanel, ezTalent): Blizzards Objekte, Rückfall wie dort
    -- (Blizzard_SharedXMLBase/ColorConstants.lua bzw. ezChats ns.COLOR_OBJECTS)
    orange    = { object = "ORANGE_FONT_COLOR",                     r = 1,    g = 0.5,  b = 0.25 },
    blue      = { object = "LIGHTBLUE_FONT_COLOR",                  r = 0.53, g = 0.67, b = 1 },
    bnet      = { object = "BATTLENET_FONT_COLOR",                  r = 0.51, g = 0.773, b = 1 },
    link      = { object = "BLUE_FONT_COLOR",                       r = 0,    g = 0.749, b = 0.953 },
}

local function Secret(v)
    local f = Core.IsSecret
    if type(f) == "function" then return f(v) end
    local check = rawget(_G, "issecretvalue")
    return type(check) == "function" and check(v) or false
end

function Style.Strata(role)
    return type(role) == "string" and Style.STRATA[role] or nil
end

function Style.SetStrata(frame, role)
    if type(frame) ~= "table" or type(frame.SetFrameStrata) ~= "function" then return false end
    local strata
    if role == "parent" then
        local okParent, parent = pcall(frame.GetParent, frame)
        if not okParent or type(parent) ~= "table" or type(parent.GetFrameStrata) ~= "function" then return false end
        local okStrata, value = pcall(parent.GetFrameStrata, parent)
        if not okStrata or Secret(value) or type(value) ~= "string" then return false end
        strata = value
    else
        strata = Style.Strata(role)
    end
    if not strata then return false end
    return (pcall(frame.SetFrameStrata, frame, strata))
end

function Style.IconSize(role)
    return type(role) == "string" and (Style.ICON[role] or Style.BUTTON[role]) or nil
end

function Style.ButtonSize(role)
    return type(role) == "string" and Style.BUTTON[role] or nil
end

function Style.Font(role)
    local name = type(role) == "string" and Style.FONT[role]
    if not name then return nil end
    local font = rawget(_G, name)
    return type(font) == "table" and font or nil
end

function Style.SetFont(text, role)
    local font = Style.Font(role)
    if not font or type(text) ~= "table" or type(text.SetFontObject) ~= "function" then return false end
    return (pcall(text.SetFontObject, text, font))
end

local function BlizzardColor(info)
    local obj = info.object and rawget(_G, info.object)
    if type(obj) == "table" and type(obj.GetRGB) == "function" then return obj end
    return nil
end

function Style.Color(role)
    local info = type(role) == "string" and Style.COLOR[role]
    if not info then return nil end
    local obj = BlizzardColor(info)
    if obj then
        local ok, r, g, b = pcall(obj.GetRGB, obj)
        if ok and type(r) == "number" and type(g) == "number" and type(b) == "number" then return r, g, b, obj end
    end
    return info.r, info.g, info.b, nil
end

function Style.SetTextColor(text, role, alpha)
    if type(text) ~= "table" or type(text.SetTextColor) ~= "function" then return false end
    local r, g, b = Style.Color(role)
    if type(r) ~= "number" then return false end
    if type(alpha) == "number" and not Secret(alpha) then return (pcall(text.SetTextColor, text, r, g, b, alpha)) end
    return (pcall(text.SetTextColor, text, r, g, b))
end

-- Blizzards UNCHECK_ALL heißt im deutschen Client „Alle Auswählen“ – derselbe Wortlaut wie „Alle auswählen“
-- (Bildschirmfoto des Nutzers vom 15.11.2026, Menü „Aufspüren“: Blizzards Eintrag UNCHECK_ALL nimmt alle Haken
-- heraus, steht aber als „Alle Auswählen“ da). Ein Text für „aus“, der ohne Groß- und Kleinschreibung dem Text für
-- „an“ gleicht, ist kein Text für „aus“.
local function SameText(a, b)
    return type(a) == "string" and type(b) == "string" and not Secret(a) and not Secret(b) and a:lower() == b:lower()
end

function Style.AllText(on)
    local L = Core.L
    local own = type(L) == "table" and L[on and "ALL_CHECK" or "ALL_UNCHECK"] or nil
    local text = rawget(_G, on and "CHECK_ALL" or "UNCHECK_ALL")
    if Secret(text) or type(text) ~= "string" or text == "" then return own end
    if not on and (SameText(text, rawget(_G, "CHECK_ALL")) or SameText(text, type(L) == "table" and L.ALL_CHECK or nil)) then
        return own   -- ohne ezCores Text lieber kein Eintrag als „aus“ mit dem Text für „an“
    end
    return text
end

function Style.ColorText(role, text)
    if Secret(text) then return text end
    local info = type(role) == "string" and Style.COLOR[role]
    if text == nil or not info then return text end
    text = tostring(text)
    local obj = BlizzardColor(info)
    if obj and type(obj.WrapTextInColorCode) == "function" then
        local ok, wrapped = pcall(obj.WrapTextInColorCode, obj, text)
        if ok and type(wrapped) == "string" then return wrapped end
    end
    local code = info.code and Core[info.code]
    if type(code) ~= "string" then
        code = ("|cff%02x%02x%02x"):format(math.floor(info.r * 255 + 0.5), math.floor(info.g * 255 + 0.5),
            math.floor(info.b * 255 + 0.5))
    end
    return code .. text .. "|r"
end
