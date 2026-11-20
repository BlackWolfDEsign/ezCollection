local _, ns = ...

--[[
    Standardplätze für Leisten anderer Module (ns.RegisterBar, Core.lua): frei, seitlich am Chat, oben auf den
    Chat-Reitern oder ein eigener Anker des Anbieters. Die Leiste bleibt ein Teil von ezCore.Mover – der Standardplatz
    gilt, solange der Nutzer sie nicht verschoben hat („Standardplatz“ auf ihrer Seite setzt sie zurück).

    Am Chat (Entscheidungen des Nutzers, 13.11.2026: „die zweite leiste waagerecht zum roten kasten“; Spieltest
    14.11.2026: „dort wo der rahmen ist will ich keinen abstand haben sondern direkt die bar“):
      chatSide  senkrecht neben dem Chat-Hintergrund, auf der Seite gegenüber von Blizzards Chat-Knöpfen. Blizzard
                setzt die Knöpfe an den näheren Bildschirmrand (FCF_SetButtonSide, chat.buttonSide); wechseln sie die
                Seite, wechselt die Leiste mit.
      chatTop   waagerecht direkt auf den Reitern, ohne Lücke, rechts bündig mit dem Chat-Hintergrund. Blizzards Dock
                (GeneralDockManager) hängt an der Oberkante des Chat-Hintergrunds, die Reiter stehen mit der
                Unterkante darauf. Der Rahmen eines Reiters ist 32 hoch (ChatTabArtTemplate, FloatingChatFrame.xml,
                Zweig forever), gezeichnet sind davon die unteren 20 (im Spiel gemessen am 14.11.2026, Maßstab 1; bis
                Welle 3 stand das Maß nur in ezMacro/EmoteBar.lua, TAB_ART). Ein höherer Reiter eines anderen Addons
                hebt die Leiste um das, was er übersteht. Die Leiste liegt eine Ebene über den Reitern, damit ihre
                Knöpfe im oberen, leeren Teil der Reiter-Rahmen die Klicks bekommen. Reiter sind der des Haupt-Chats
                am Dock selbst und alle übrigen angedockten (Kampflog, weitere Fenster) im Rollbereich des Docks
                (DockTabs unten).
    Blizzards Chat wird nie verändert: ezBars liest nur (Hintergrund, Dock, buttonSide) und hört mit hooksecurefunc
    zu. Fehlt der Chat oder hat er eine andere Form, steht die Leiste frei (Mitte des Bildschirms) – ns.ExtraInfo
    nennt dann docked = "free". Ebenso, wenn sich an einem eigenen Anker des Anbieters nicht verankern lässt
    (entry.anchorFailed, gesetzt von Bars.ApplyExtras bis zur nächsten Anmeldung).

    Kein Dienst in ezCore: Bisher braucht nur ezBars diese Anker (Auftrag BARS-01). Seit Welle 5 meldet ezMacro seine
    Emote-Leisten hier an (ezMacro/EmoteBar.lua über ezCore.API("ezBars").RegisterBar); die frühere zweite Fassung der
    Chat-Anker in ezMacro ist dabei entfallen – die Technik steht nur noch in dieser Datei.
]]

local Anchors = {}
ns.Anchors = Anchors

-- Abstände von Blizzards Chat-Knopfleiste zum Chat-Hintergrund (FCF_SetButtonSide): 3 zur Seite, 3 nach unten.
Anchors.SIDE_GAP, Anchors.SIDE_Y = 3, -3
Anchors.TAB_H, Anchors.TAB_ART = 32, 20
local TAB_SNAP, TAB_MAX = 8, 64     -- als Reiter zählt, was mit der Unterkante auf dem Chat steht und nicht höher ist
local FREE_STEP = 48                -- freie Leisten stehen untereinander statt aufeinander

local NAMES = { free = true, chatSide = true, chatTop = true, custom = true }
-- Ankerpunkte, die SetPoint kennt (ein anderer Name wäre im Spiel ein Fehler)
local POINTS = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }

local function Point(value)
    value = type(value) == "string" and value:upper() or nil
    return value and POINTS[value] and value or nil
end

-- Ein Rahmen, an dem sich verankern lässt? (pcall: Schon das Nachschlagen an einem gesperrten Rahmen ist ein Fehler.)
local function IsFrame(value)
    if type(value) ~= "table" then return false end
    local ok, fn = pcall(function() return value.SetPoint end)
    return ok and type(fn) == "function"
end

-- Welche Standardanker ezBars abdeckt (Abfrage für Anbieter: Anchors.Covered().chatTop).
function Anchors.Covered()
    local out = {}
    for name in pairs(NAMES) do out[name] = true end
    return out
end

-- Wunsch des Anbieters → Name des Ankers und (bei einem eigenen Anker) seine Werte. Unbekanntes wird "free" – auch
-- ein eigener Anker mit einem Punkt, den SetPoint nicht kennt ("MIDDLE"), oder mit einer Tabelle, die kein Rahmen ist.
-- Der Rahmen darf ein Name sein (nachgeschlagen beim Setzen; gibt es ihn nicht, gilt UIParent) oder fehlen.
function Anchors.Parse(wish)
    if type(wish) == "string" and NAMES[wish] and wish ~= "custom" then return wish, nil end
    local point = type(wish) == "table" and Point(wish[1]) or nil
    if point then
        local relative = wish[2]
        if type(relative) == "table" then
            if not IsFrame(relative) then return "free", nil end
        elseif type(relative) ~= "string" then
            relative = nil
        end
        return "custom", { point, relative, Point(wish[3]) or point, tonumber(wish[4]) or 0, tonumber(wish[5]) or 0 }
    end
    return "free", nil
end

---------------------------------------------------------------------------
-- Blizzards Chat (nur lesen)
---------------------------------------------------------------------------

local function PrimaryChat()
    local dock = rawget(_G, "GENERAL_CHAT_DOCK")
    local chat = type(dock) == "table" and dock.primary or rawget(_G, "ChatFrame1")
    return type(chat) == "table" and chat or nil
end

-- Woran die Leisten am Chat hängen: sein Hintergrund (FloatingBorderedFrame: parentKey „Background“ bzw.
-- $parentBackground), ohne ihn das Chatfenster selbst. nil, wenn es keinen Chat gibt.
function Anchors.ChatEdge()
    local chat = PrimaryChat()
    if not chat then return nil end
    local background = chat.Background
    if type(background) ~= "table" and type(chat.GetName) == "function" then
        background = rawget(_G, (chat:GetName() or "") .. "Background")
    end
    local edge = type(background) == "table" and background or chat
    return type(edge.SetPoint) == "function" and edge or nil
end

-- Seite gegenüber von Blizzards Chat-Knöpfen: "left" oder "right".
function Anchors.ChatSide()
    local chat = PrimaryChat()
    return chat and chat.buttonSide == "right" and "left" or "right"
end

-- Sammelt die sichtbaren Kinder von parent ein, die Reiter sein können (nicht höher als TAB_MAX). snap: nur, was
-- mit der Unterkante auf dem Chat-Hintergrund steht; skip: dieses Kind auslassen.
local function CollectTabs(tabs, parent, chatTop, snap, skip)
    if type(parent) ~= "table" or type(parent.GetChildren) ~= "function" then return end
    for _, child in ipairs({ parent:GetChildren() }) do
        local shown = child ~= skip and child.IsShown and child:IsShown()
        local top, bottom = child.GetTop and child:GetTop(), child.GetBottom and child:GetBottom()
        if shown and top and bottom and top - bottom <= TAB_MAX and (not snap or math.abs(bottom - chatTop) <= TAB_SNAP) then
            tabs[#tabs + 1] = child
        end
    end
end

-- Reiter im Dock (nur lesen). Blizzards FCFDock_UpdateTabs (FloatingChatFrame.lua, Zweig forever) hängt nur die fest
-- angedockten Reiter an das Dock selbst (isStaticDocked – allein der Haupt-Chat); alle übrigen angedockten Reiter
-- (Kampflog, weitere Chatfenster) hängen am Rollkind von dock.scrollFrame. Am Dock zählt, was mit der Unterkante auf
-- dem Chat-Hintergrund steht (Blizzards Reiter, ezChats „Gespräche“ …) – der Rollbereich selbst ist kein Reiter; im
-- Rollkind zählt jedes sichtbare Kind (dort liegen nur Reiter, Blizzard verankert sie eine Zeile tiefer).
local function DockTabs(edge)
    local tabs = {}
    local dock = rawget(_G, "GENERAL_CHAT_DOCK")
    local chatTop = edge and type(edge.GetTop) == "function" and edge:GetTop() or nil
    if type(dock) ~= "table" or not chatTop then return tabs, chatTop end
    local scroll = type(dock.scrollFrame) == "table" and dock.scrollFrame or nil
    CollectTabs(tabs, dock, chatTop, true, scroll)
    if scroll and type(scroll.GetScrollChild) == "function" then
        CollectTabs(tabs, scroll:GetScrollChild(), chatTop, false)
    end
    return tabs, chatTop
end

-- Oberkante des gezeichneten Reiterrahmens über dem Chat-Hintergrund (ohne Hervorhebung und Glow): Blizzards Rahmen
-- (TAB_ART); ein höherer Reiter hebt sie um das, was er über Blizzards Rahmen (TAB_H) hinausragt.
function Anchors.TabRowTop(edge)
    local row = Anchors.TAB_ART
    local tabs, chatTop = DockTabs(edge or Anchors.ChatEdge())
    for _, tab in ipairs(tabs) do
        row = math.max(row, math.ceil(tab:GetTop() - chatTop) - (Anchors.TAB_H - Anchors.TAB_ART))
    end
    return row
end

-- Hebt den eigenen Rahmen eine Ebene über die Reiter derselben Schicht. Nur am eigenen (ungeschützten) Rahmen.
-- Schicht und Ebene können seit Forever 1.60.1 gesperrt sein (V-186): zuerst über ezCore.Plain/Num, ein gesperrter
-- Wert zählt nicht (der Reiter wird dann übergangen, nie verglichen). Ist die eigene Ebene gesperrt, bleibt sie, wie
-- sie ist – ein Ersatzwert (0) senkte die Leiste unter die Reiter.
function Anchors.RaiseAboveTabs(frame)
    if not (frame.GetFrameLevel and frame.SetFrameLevel and frame.GetFrameStrata) then return false end
    local own = ezCore.Plain(frame:GetFrameStrata())
    local current = ezCore.Num(frame:GetFrameLevel())
    if current == nil then return false end
    local level = current
    for _, tab in ipairs((DockTabs(Anchors.ChatEdge()))) do
        local strata = tab.GetFrameLevel and tab.GetFrameStrata and ezCore.Plain(tab:GetFrameStrata()) or nil
        local tabLevel = own ~= nil and strata == own and ezCore.Num(tab:GetFrameLevel()) or nil
        if tabLevel ~= nil then level = math.max(level, tabLevel + 1) end
    end
    if level ~= current then frame:SetFrameLevel(level) end
    return true
end

---------------------------------------------------------------------------
-- Anker einer Leiste
---------------------------------------------------------------------------

-- Standardplatz der Leiste entry (Eintrag aus ns.Extras, index = Stelle in der Liste).
-- Rückgabe: Anker { Punkt, Rahmen, Bezugspunkt, x, y } für ezCore.Mover, die Ecke, an der das Raster beginnt, und
-- woran die Leiste damit hängt ("chatSide", "chatTop", "custom" oder "free").
--   chatSide: Die Spalten wachsen vom Chat weg (links vom Chat beginnt das Raster rechts oben).
--   chatTop:  Die Reihen wachsen nach oben, die ersten Knöpfe liegen unten am Chat.
-- Ließ sich am gewünschten Platz nicht verankern (entry.anchorFailed), gilt die freie Lage.
function Anchors.Resolve(entry, index)
    local x, y = entry.offsetX or 0, entry.offsetY or 0
    local wish = not entry.anchorFailed and entry.anchor or "free"
    local edge = (wish == "chatSide" or wish == "chatTop") and Anchors.ChatEdge() or nil
    if edge and wish == "chatSide" then
        if Anchors.ChatSide() == "left" then
            return { "TOPRIGHT", edge, "TOPLEFT", -Anchors.SIDE_GAP + x, Anchors.SIDE_Y + y }, "TOPRIGHT", "chatSide"
        end
        return { "TOPLEFT", edge, "TOPRIGHT", Anchors.SIDE_GAP + x, Anchors.SIDE_Y + y }, "TOPLEFT", "chatSide"
    elseif edge and wish == "chatTop" then
        return { "BOTTOMRIGHT", edge, "TOPRIGHT", x, Anchors.TabRowTop(edge) + y }, "BOTTOMLEFT", "chatTop"
    elseif wish == "custom" and type(entry.point) == "table" then
        return entry.point, "TOPLEFT", "custom"
    end
    return { "CENTER", "UIParent", "CENTER", 0, -FREE_STEP * ((index or 1) - 1) }, "TOPLEFT", "free"
end

-- Stand des Chats, an dem die Anker hängen: Seite und Höhe der Reiterreihe (zum Vergleichen nach einer Änderung).
function Anchors.ChatState()
    local edge = Anchors.ChatEdge()
    return Anchors.ChatSide(), edge and Anchors.TabRowTop(edge) or nil
end

---------------------------------------------------------------------------
-- Zuhören: Chat-Knöpfe wechseln die Seite, Reiter werden neu geordnet
---------------------------------------------------------------------------

local watch = {}        -- onChange, onTabs, side, top (Stand beim letzten Einrichten), sideHooked, tabsHooked

-- Stand des Chats merken, an dem die Leisten gerade ausgerichtet wurden (ruft Bars.ApplyExtras nach dem Einrichten).
function Anchors.Placed()
    watch.side, watch.top = Anchors.ChatState()
end

-- Hat sich der Chat seit dem letzten Einrichten geändert (Seite der Knöpfe, Höhe der Reiterreihe)? Dann onChange.
local function Changed()
    local side, top = Anchors.ChatState()
    if side == watch.side and top == watch.top then return false end
    if watch.onChange then watch.onChange() end
    return true
end

-- Hängt sich einmal an Blizzards Funktionen (hooksecurefunc – sie laufen unverändert). onChange(): Seite oder Höhe
-- der Reiterreihe hat sich geändert, die Leisten am Chat brauchen ihren Anker neu. onTabs(): Reiter neu geordnet,
-- die Höhe ist gleich – nur die Ebene über den Reitern nachziehen (Blizzard hängt die Reiter dabei um).
-- Wiederholbar: Eine Funktion, die es beim ersten Aufruf noch nicht gab, bekommt ihren Zuhörer beim nächsten.
function Anchors.Watch(onChange, onTabs)
    watch.onChange, watch.onTabs = onChange, onTabs
    if type(hooksecurefunc) ~= "function" then return false end
    if not watch.sideHooked and type(rawget(_G, "FCF_SetButtonSide")) == "function" then
        watch.sideHooked = true
        hooksecurefunc("FCF_SetButtonSide", function(chat)
            if chat ~= nil and chat == PrimaryChat() then Changed() end
        end)
    end
    -- Erst im nächsten Bild messen, wenn auch andere Addons ihre Reiter gesetzt haben (ezChat hängt sich ebenfalls an).
    if not watch.tabsHooked and type(rawget(_G, "FCFDock_UpdateTabs")) == "function" and C_Timer and C_Timer.After then
        watch.tabsHooked = true
        hooksecurefunc("FCFDock_UpdateTabs", function(dock)
            if dock ~= rawget(_G, "GENERAL_CHAT_DOCK") then return end
            C_Timer.After(0, function()
                if not Changed() and watch.onTabs then watch.onTabs() end
            end)
        end)
    end
    return watch.sideHooked == true or watch.tabsHooked == true
end
