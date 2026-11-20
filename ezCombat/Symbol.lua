local _, ns = ...
local L = ns.L
local Glow = ns.Glow
local Core = ezCore

-- Anzeige über dem Charakter (CB-N1, Wunsch des Nutzers vom 14.11.2026 nach dem Probe-Lauf: „ich hätte doch gern alle
-- fähigkeiten, meldungen davon zentral über den charakter, also auch die aktuelle fähigkeit der rotation … oder gar
-- einstellbar je nach gusto“). Aus dem einen Symbolplatz von 1.7 („ein icon platz für alles“) wird eine Gruppe aus
-- drei Plätzen – kein neues Fenster, derselbe Rahmen „ezCombatReadyPulse“, über ezCore.Mover als Ganzes verschiebbar
-- (Schlüssel wie bisher „pulse“, eine gespeicherte Lage bleibt):
--   links  (klein) – läuft aus:  1. dot  – eigener DoT/HoT auf dem Ziel läuft aus (bleibt, bis neu gesetzt; mit Restzeit)
--                                2. buff – eigener Buff läuft aus (bleibt, bis neu gewirkt; „ist ausgelaufen“ kurz)
--                                3. prep – vor dem Kampf fehlt etwas (Dauer-Buff, Begleiter, Stein, Gift)
--   Mitte  (groß)  – next:       nächste Fähigkeit der Rotation
--   rechts (klein) – ready:      Fähigkeit wieder bereit (kurz, Anzeigedauer einstellbar)
-- Je Meldungsart wählt man, ob sie hier erscheint, als Leuchten am Aktionsknopf, beides oder gar nicht (ns.ShowAt;
-- die Hilfen fragen das selbst, bevor sie einen Eintrag melden), dazu die Größe jedes Platzes. Beim Verschieben
-- steht in jedem Platz ein Beispiel (example). Jeder Platz zeigt seinen wichtigsten Eintrag, darunter bzw. daneben
-- einen kurzen Text in der Farbe seiner Art (Core.GlowColor, Core.GlowLabel). Dauerhafte Einträge (Set) stehen, bis
-- die Hilfe sie löscht (Clear); kurze (Pop) verblassen nach der Anzeigedauer.
--
-- Gesperrte Restzeiten (im Kampf auf Forever üblich): Ob ein gesperrter DoT gerade ausläuft, weiß ezCombat nicht –
-- Blizzards Dauer-Objekt wertet es über eine Stufenkurve aus, und SetAlpha nimmt das gesperrte Ergebnis an. Dafür
-- liegt über dem linken Platz eine eigene Ebene (SetSecret): Ihre Deckkraft kommt aus der Warnkurve, die übrigen
-- Einträge des linken Platzes liegen in einem Rahmen, dessen Deckkraft aus der Gegenkurve kommt – leuchtet der DoT,
-- verschwinden sie, sonst sind sie zu sehen. Die Spirale der Restzeit bekommt das Dauer-Objekt unverändert
-- (SetCooldownFromDurationObject). Mitte und rechts bleiben davon unberührt. ezCombat liest die Restzeit dabei nie.
--
-- Ein einzelnes Symbol steht in der Mitte (Wunsch des Nutzers vom 15.11.2026 nach dem Spieltest: „wenn es nur ein
-- symbol gibt, sollte es doch in der mitte sein“ und „wenn direkt einer neuer zauber eingesetzt werden muss nach links
-- rutschen bevor es verschwindet“; Schalter symbolCenter, ab Werk an): Zeigt nur der linke oder nur der rechte Platz
-- etwas, steht er mittig über dem Charakter, sein Text darunter wie in der Mitte. Kommt ein zweiter Eintrag dazu
-- (etwa die nächste Fähigkeit), gleitet er weich an seinen Platz – „läuft aus“ nach links, „wieder bereit“ nach
-- rechts – und verschwindet dort nach seiner Anzeigedauer; bleibt er wieder allein, gleitet er zurück in die Mitte.
-- Die Bewegung ist eine Translation am eigenen Rahmen (AnimationGroup), nichts Geschütztes.
--
-- Noch nicht bereit (Wunsch des Nutzers vom 15.11.2026 abends: „wenn das mittige symbol auftaucht aber genau diese
-- fähigkeit noch ne bereit ist muss man das auch sehen“): Trägt ein Eintrag seinen Zauber (spell), fragt die Anzeige
-- ns.Readiness und zeichnet das Symbol wie Blizzards Aktionsknopf – Abklingzeit als eigene Spirale
-- (CooldownFrameTemplate, Zahlen nach Blizzards Einstellung „Zahlen auf Abklingzeiten“), zu wenig Kraft blau, sonst
-- nicht nutzbar grau, außer Reichweite rot. Unter dem Text steht dann „wartet: …“, „bereit in n s“ nur bei offenem
-- Wert. Die globale Abklingzeit zeigt nur die kurze Spirale, kein „wartet“. Gesperrt geht Blizzards Dauer-Objekt
-- unverändert an die Spirale; ezCombat liest die Restzeit nie. Fest eingebaut wie an Blizzards Aktionsknopf
-- (Einstellungs-Prüfung 19.11.2026, Nr. 30–32; bis dahin je Hinweis ein Schalter). Ein leiser Takt (WAIT_EVERY) hält es aktuell, solange ein solcher
-- Eintrag steht – wie Blizzards Knöpfe, die ihre Reichweite ebenso im Takt nachsehen.
--
-- Text unter dem Symbol (Spielbefund des Nutzers vom 18.11.2026, Paladin: „viel zu viel text... wenn berhaupt
-- nötig...“; S-1811-Symboltext): Ab Werk steht nur das Symbol – seine Zustände zeigt es selbst (Spirale der
-- Abklingzeit, rot außer Reichweite, blau zu wenig Kraft, grau geht nicht, Farbe der Art am Rand). Die Auswahl
-- symbolText (Symbol.TextMode) gilt für alle Plätze und die gesperrte Ebene: "off" kein Text, "name" eine Zeile mit
-- dem Namen (ohne „Als Nächstes:“, ohne „wartet“), "full" wie bis 18.11.2026 (Text des Eintrags und „wartet: …“).
-- Dazu trägt jeder Eintrag neben seinem ausführlichen Text (label) den Namen (texts.name) und, wo das Symbol eine
-- Lage nicht selbst zeigen kann, eine Zeile für jede Auswahl (texts.always: „Richturteil – nicht auf der Leiste“ –
-- auf einem Knopf, den es nicht gibt, kann nichts leuchten; das sagt kein Symbol). Das Beispiel beim Verschieben
-- behält seinen Text in jeder Auswahl: Es erklärt, welcher Platz welche Meldung trägt.
local Symbol = {}
ns.Symbol = Symbol
Symbol.STRATA = "LOW"      -- Ebene der Anzeige über dem Charakter (unter allen Fenstern, Symbol.Frame)

-- Rangfolge über alle Plätze (Symbol.Top, Tests); innerhalb eines Platzes gilt dieselbe Reihenfolge.
Symbol.RANK = { "dot", "buff", "ready", "prep", "next", "example" }
local RANK_OF = {}
for index, key in ipairs(Symbol.RANK) do RANK_OF[key] = index end

-- Die drei Plätze, ihre Einträge und ihre Größe (Einstellung).
Symbol.SLOTS = { "left", "middle", "right" }
Symbol.SLOT_OF = { dot = "left", buff = "left", prep = "left", next = "middle", ready = "right" }
Symbol.SIZE_KEY = { left = "sizeExpiring", middle = "sizeNext", right = "sizeReady" }
local SIZE_MIN, SIZE_MAX = 16, 128
local GAP = 14              -- Abstand zwischen den Plätzen

local DEFAULT_ICON = "Interface\\Icons\\Ability_DualWield"
Symbol.DEFAULT_ICON = DEFAULT_ICON
local FADE_SECONDS = 0.4
local SLIDE_SECONDS = 0.25  -- so lange gleitet ein Platz zwischen der Mitte und seinem eigenen Platz
local ANCHOR = { "CENTER", "UIParent", "CENTER", 0, 160 }

local WAIT_EVERY = 0.2      -- Sekunden: Takt für „noch nicht bereit“, solange ein Eintrag mit Zauber steht

-- Text unter dem Symbol: Die Werte der Auswahl symbolText stehen nur in ns.CHOICES.symbolText (Core.lua, SSOT); ein
-- unbekannter Wert gilt wie der Standard.
function Symbol.TextMode()
    local value = ns.S and ns.S.symbolText
    if not Core.IsSecret(value) and type(value) == "string" then
        for _, mode in ipairs(ns.CHOICES.symbolText) do
            if value == mode then return value end
        end
    end
    return ns.DEFAULTS.symbolText or "off"
end

local entries = {}          -- [Schlüssel] = { icon, label, kind, timer, untilTime (nil = dauerhaft), version, spell,
                            --   name, always } – name/always: Text bei „nur Name“ bzw. Zeile für jede Auswahl
local root
local slots = {}            -- [Platz] = { name, frame, gate, content, shownKey, shownVersion, place, slide }
local secretLayer
local secretInfo            -- { key, label, durationObject } solange die gesperrte Ebene an ist
local expireTimer = false

---------------------------------------------------------------------------
-- Rahmen
---------------------------------------------------------------------------

-- Text: in der Mitte darunter, links links daneben, rechts rechts daneben (überdecken sich so nie). where: der Platz,
-- an dem der Rahmen gerade steht ("middle" auch für ein einzelnes Symbol in der Mitte – das Symbol bleibt mittig).
local function PlaceLabel(label, frame, where)
    label:ClearAllPoints()
    if where == "left" then
        label:SetPoint("RIGHT", frame, "LEFT", -6, 0)
        if label.SetJustifyH then label:SetJustifyH("RIGHT") end
    elseif where == "right" then
        label:SetPoint("LEFT", frame, "RIGHT", 6, 0)
        if label.SetJustifyH then label:SetJustifyH("LEFT") end
    else
        label:SetPoint("TOP", frame, "BOTTOM", 0, -8)
        if label.SetJustifyH then label:SetJustifyH("CENTER") end
    end
    label.where = where
end

local function Label(frame, slotName)
    local label = frame:CreateFontString(nil, "OVERLAY", slotName == "middle" and "GameFontNormalLarge" or "GameFontNormal")
    PlaceLabel(label, frame, slotName)
    frame.label = label
    return label
end

-- Spirale der Restzeit (läuft aus), wie die DoT-Reihe: rückwärts, mit Kante und Zahlen.
local function Spiral(frame)
    local cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cooldown:SetAllPoints(frame.icon)
    if cooldown.SetReverse then cooldown:SetReverse(true) end
    if cooldown.SetDrawEdge then cooldown:SetDrawEdge(true) end
    if cooldown.SetHideCountdownNumbers then cooldown:SetHideCountdownNumbers(false) end
    cooldown:Hide()
    frame.cooldown = cooldown
    return cooldown
end

-- Spirale der Abklingzeit (noch nicht bereit), wie an Blizzards Aktionsknopf: vorwärts, ohne Kante; die Zahlen
-- folgen Blizzards Einstellung (ApplyWait).
local function WaitSpiral(frame)
    local cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cooldown:SetAllPoints(frame.icon)
    if cooldown.SetDrawEdge then cooldown:SetDrawEdge(false) end
    cooldown:Hide()
    frame.wait = cooldown
    return cooldown
end

local function Animations(frame)
    -- Aufspringen (beide) und, nur bei kurzen Einträgen, Verblassen nach der Anzeigedauer.
    local function Group(withFade)
        local anim = frame:CreateAnimationGroup()
        local grow = anim:CreateAnimation("Scale")
        if grow.SetScaleFrom then
            grow:SetScaleFrom(0.4, 0.4)
            grow:SetScaleTo(1, 1)
        elseif grow.SetFromScale then
            grow:SetFromScale(0.4, 0.4)
            grow:SetToScale(1, 1)
        end
        grow:SetDuration(0.15)
        grow:SetOrder(1)
        local fadeIn = anim:CreateAnimation("Alpha")
        fadeIn:SetFromAlpha(0)
        fadeIn:SetToAlpha(1)
        fadeIn:SetDuration(0.15)
        fadeIn:SetOrder(1)
        if withFade then
            local fadeOut = anim:CreateAnimation("Alpha")
            fadeOut:SetFromAlpha(1)
            fadeOut:SetToAlpha(0)
            fadeOut:SetStartDelay(1)
            fadeOut:SetDuration(FADE_SECONDS)
            fadeOut:SetOrder(2)
            anim.fadeOut = fadeOut
        end
        return anim
    end
    frame.anim = Group(true)        -- kurz: aufspringen, stehen, verblassen
    frame.appear = Group(false)     -- dauerhaft: nur aufspringen
end

-- Top steht weiter unten; vorab bekannt, damit das OnFinished der Verblassen-Animation das lokale Top findet
-- (sonst ein globales nil – Vollprüfung V-104).
local Top
local WatchWait     -- weiter unten; Refresh startet bzw. beendet damit den Takt für „noch nicht bereit“

-- Größe eines Platzes aus der Einstellung (begrenzt; ein unbrauchbarer Wert gilt wie der Standard).
function Symbol.Size(slotName)
    local key = Symbol.SIZE_KEY[slotName]
    local value = key and ns.Num(ns.S and ns.S[key]) or nil
    if not value then value = key and ns.DEFAULTS[key] or ezCore.Style.ICON.small end
    return math.max(SIZE_MIN, math.min(SIZE_MAX, value))
end

-- Klick auf das Symbol in der Mitte (nächste Fähigkeit) schaltet den Flächenmodus um (Einstellungs-Prüfung 19.11.2026,
-- Nr. 100) – dieselbe Wirkung wie die Taste in Blizzards Tastaturbelegung und das Kästchen der Einstellungen. Nur der
-- eigene Rahmen nimmt die Maus, und nur solange er etwas zeigt (versteckt fängt er keine Klicks in der Welt ab); der
-- Tooltip nennt den Stand, die Wirkung des Klicks und die belegte Taste – nur außerhalb des Kampfes, damit er über dem
-- Charakter nicht bei jedem Überfahren aufgeht (Gegenprüfung 19.11.2026). Der Rechtsklick geht durch in die Welt
-- (Kamera drehen, Gegner anklicken): Symbol.PassRightClick.
function Symbol.ClickTip(owner)
    local tip = rawget(_G, "GameTooltip")
    local Rotation = ns.Rotation
    if not (tip and Rotation) or Core.InCombat() then return false end
    tip:SetOwner(owner, "ANCHOR_TOP")
    tip:SetText(L.OPT_rotationAoe)
    Core.TipLine(tip, Rotation.Aoe() and L.ROTATION_AOE_ON or L.ROTATION_AOE_OFF, "highlight")
    Core.TipLine(tip, ns.ClickText(L.SYMBOL_AOE_CLICK), "good", true)
    local key = Rotation.AoeKeyText()
    Core.TipLine(tip, key and L.SYMBOL_AOE_KEY:format(key) or L.SYMBOL_AOE_NOKEY, "hint", true)
    tip:Show()
    return true
end

-- Nur die linke Taste wird ausgewertet; die rechte reicht der Rahmen an die Welt weiter. SetPassThroughButtons ist im
-- Kampf gesperrt – ns.AfterCombat führt es sofort aus bzw. holt es nach dem Kampf nach (wie ezBuffs Group.PassRightClick).
Symbol.PASS_THROUGH = "RightButton"
function Symbol.PassRightClick(frame)
    if type(frame) ~= "table" or type(frame.SetPassThroughButtons) ~= "function" then return false end
    ns.AfterCombat(function() frame:SetPassThroughButtons(Symbol.PASS_THROUGH) end, "symbolPassRight")
    return true
end

-- Ein Linkszug (Kamera drehen) ist kein Klick: zwischen Drücken und Loslassen höchstens DRAG_PX Bildpunkte.
Symbol.DRAG_PX = 4
function Symbol.Dragged(frame)
    local x, y = frame.downX, frame.downY
    frame.downX, frame.downY = nil, nil
    local cursor = rawget(_G, "GetCursorPosition")
    if not (x and y and cursor) then return false end
    local nx, ny = cursor()
    if type(nx) ~= "number" or type(ny) ~= "number" then return false end
    return math.abs(nx - x) > Symbol.DRAG_PX or math.abs(ny - y) > Symbol.DRAG_PX
end

-- Im Kampf nimmt das Symbol keine Maus an (code-reviewer 20.11.2026): Es steht über dem Charakter, und ein Rahmen
-- mit Maus fängt Linksklicks auf Gegner dahinter ab und verdeckt sie für „mouseover“. Umgeschaltet wird im Kampf
-- mit der Taste (ezCore.Keys „combatAoe“). EnableMouse an diesem eigenen, ungeschützten Rahmen ist im Kampf erlaubt.
function Symbol.MouseForCombat(content, inCombat)
    if type(content) == "table" and content.EnableMouse then content:EnableMouse(not inCombat) end
end

function Symbol.MakeClickable(content)
    Symbol.MouseForCombat(content, Core.InCombat())
    ns.On("PLAYER_REGEN_DISABLED", function() Symbol.MouseForCombat(content, true) end)
    ns.On("PLAYER_REGEN_ENABLED", function() Symbol.MouseForCombat(content, false) end)
    Symbol.PassRightClick(content)
    content:SetScript("OnMouseDown", function(self, button)
        local cursor = rawget(_G, "GetCursorPosition")
        if button == "LeftButton" and cursor then self.downX, self.downY = cursor() end
    end)
    content:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" or not ns.Rotation or Core.InCombat() then return end
        if Symbol.Dragged(self) then return end
        ns.Try("Symbol", ns.Rotation.ToggleAoe)
    end)
    content:SetScript("OnEnter", function(self) ns.Try("Symbol", Symbol.ClickTip, self) end)
    content:SetScript("OnLeave", function(self)
        local tip = rawget(_G, "GameTooltip")
        if tip and (not tip.IsOwned or tip:IsOwned(self)) then tip:Hide() end
    end)
end

local function NewSlot(name)
    local frame = CreateFrame("Frame", nil, root)
    frame:EnableMouse(false)
    -- Rahmen der gewöhnlichen Einträge; seine Deckkraft regelt links die gesperrte Ebene (Gegenkurve), sonst 1.
    local gate = CreateFrame("Frame", nil, frame)
    gate:SetAllPoints(frame)
    local content = CreateFrame("Frame", nil, gate)
    content:SetAllPoints(gate)
    Glow.StyleIcon(content)
    Label(content, name)
    Spiral(content)
    WaitSpiral(content)
    Animations(content)
    content.anim:SetScript("OnFinished", function()
        -- Verblasst: Der kurze Eintrag ist vorbei, auch wenn seine Zeit um einen Hauch noch nicht um ist.
        local key, entry = Top(GetTime(), name)
        if entry and entry.untilTime and entry.untilTime - GetTime() < 0.15 then entries[key] = nil end
        Symbol.Refresh()
    end)
    content:Hide()
    local slot = { name = name, frame = frame, gate = gate, content = content }
    slots[name] = slot
    if name == "middle" then Symbol.MakeClickable(content) end
    return slot
end

-- Die Mover-Lage (ezCore.Mover, Schlüssel „pulse“), sobald angemeldet.
local moverPart

-- Die gespeicherte Lage um die Hälfte einer Größenänderung der Mitte verschieben, damit die Mitte stehen bleibt.
-- ezCore merkt sich nach dem Ziehen eine Ecke (Core.QuadrantPos: BOTTOMLEFT, TOPRIGHT …), keine Mitte; ohne
-- Ausgleich wüchse die Mitte von dieser Ecke weg. Ohne gespeicherte Lage (Anker CENTER) ist nichts zu tun.
function Symbol.KeepCenter(delta)
    delta = ns.Num(delta)
    if not delta or delta == 0 or not moverPart then return false end
    local pos = moverPart:Position()
    local point = type(pos) == "table" and pos.point or nil
    if type(point) ~= "string" then return false end
    local half = delta / 2
    local x, y = ns.Num(pos.x) or 0, ns.Num(pos.y) or 0
    if point:find("LEFT", 1, true) then x = x - half elseif point:find("RIGHT", 1, true) then x = x + half end
    if point:find("TOP", 1, true) then y = y + half elseif point:find("BOTTOM", 1, true) then y = y - half end
    if x == pos.x and y == pos.y then return false end
    Core.StorePosition(moverPart.key, { point = point, relPoint = pos.relPoint or point, x = x, y = y })
    moverPart:Apply()
    return true
end

-- Einmalige Nachführung nach der Umstellung der Größen ab Werk (52 auf 45, ns.OnLoad, Merker iconSizes45): die
-- gespeicherte Ecke um die halbe Änderung rücken, damit die Mitte einer verschobenen Anzeige stehen bleibt. Wartet,
-- bis der Rahmen mit seiner Lage angemeldet ist; ohne gespeicherte Lage ist nichts zu tun, der Merker geht trotzdem.
function Symbol.TakeShift()
    local db = ns.db
    local shift = type(db) == "table" and ns.Num(db.iconSizes45Shift) or nil
    if not shift or not moverPart then return false end
    db.iconSizes45Shift = nil
    return Symbol.KeepCenter(shift)
end

-- Mitte des eigenen Platzes, waagerecht vom Mittelpunkt der Gruppe aus (links negativ, Mitte 0).
function Symbol.OwnX(slotName)
    if slotName ~= "left" and slotName ~= "right" then return 0 end
    local half = Symbol.Size("middle") / 2 + GAP + Symbol.Size(slotName) / 2
    return slotName == "left" and -half or half
end

-- Steht ein Platz gerade in der Mitte (einzelnes Symbol)? → "center" oder "own"
function Symbol.Place(slotName)
    local slot = slots[slotName]
    return (slot and slot.place == "center") and "center" or "own"
end

-- Animation „Gleiten“ eines Platzes (Tests): AnimationGroup mit fromX oder nil, solange er nie geglitten ist.
function Symbol.SlideOf(slotName)
    return slots[slotName] and slots[slotName].slide or nil
end

-- Lage eines Platzes setzen, ohne Bewegung: links bzw. rechts neben der Mitte oder (place = "center") mittig; der
-- Text folgt (mittig darunter bzw. außen daneben), beim linken Platz auch der der gesperrten Ebene.
local function Anchor(slot)
    local frame = slot.frame
    local centered = slot.name == "middle" or slot.place == "center"
    frame:ClearAllPoints()
    if centered then
        frame:SetPoint("CENTER", root, "CENTER", 0, 0)
    elseif slot.name == "left" then
        frame:SetPoint("RIGHT", slots.middle.frame, "LEFT", -GAP, 0)
    else
        frame:SetPoint("LEFT", slots.middle.frame, "RIGHT", GAP, 0)
    end
    local where = centered and "middle" or slot.name
    PlaceLabel(slot.content.label, slot.content, where)
    if slot.name == "left" and secretLayer then PlaceLabel(secretLayer.label, secretLayer, where) end
end

-- Weich zur neuen Lage gleiten: Der Rahmen steht schon an der neuen Stelle; die Animation setzt ihn zuerst um fromX
-- an die alte zurück und führt ihn in SLIDE_SECONDS her. Am Ende steht er genau an seinem Anker.
local function Slide(slot, fromX)
    local anim = slot.slide
    if not anim then
        anim = slot.frame:CreateAnimationGroup()
        anim.jump = anim:CreateAnimation("Translation")
        anim.jump:SetDuration(0.001)
        anim.jump:SetOrder(1)
        anim.move = anim:CreateAnimation("Translation")
        anim.move:SetDuration(SLIDE_SECONDS)
        anim.move:SetOrder(2)
        if anim.move.SetSmoothing then anim.move:SetSmoothing("OUT") end
        slot.slide = anim
    end
    anim:Stop()
    anim.jump:SetOffset(fromX, 0)
    anim.move:SetOffset(-fromX, 0)
    anim.fromX = fromX
    anim:Play()
end

-- Einzelnes Symbol in die Mitte, zwei und mehr an ihren Platz (shown[Platz] = zeigt etwas). Gleiten nur, wenn der
-- Platz schon zu sehen war; ein neu erscheinender springt an seiner Stelle auf.
local function Arrange(shown, groupShown)
    local single, count = nil, 0
    for _, name in ipairs(Symbol.SLOTS) do
        if shown[name] then
            count = count + 1
            single = name
        end
    end
    if count ~= 1 or single == "middle" or not ns.Enabled("symbolCenter") then single = nil end
    for _, name in ipairs({ "left", "right" }) do
        local slot = slots[name]
        local want = single == name and "center" or "own"
        if slot.place ~= want then
            slot.place = want
            Anchor(slot)
            if groupShown and slot.wasShown and shown[name] then
                local ownX = Symbol.OwnX(name)
                Slide(slot, want == "own" and -ownX or ownX)
            elseif slot.slide then
                slot.slide:Stop()
            end
        end
        slot.wasShown = shown[name] and true or false
    end
end

-- Größe und Lage der drei Plätze: Der Rahmen ezCombatReadyPulse ist genau die Mitte (wie der Symbolplatz bis 1.7,
-- ab Werk 45 groß wie Blizzards Aktionsknopf), links und rechts hängen außen daneben. So gilt eine früher gespeicherte Lage weiter – ezCore
-- merkt sich eine Ecke des Rahmens –, und die Größen links und rechts verschieben die Mitte nie. keepCenter (beim
-- Ändern der Größe in der Mitte): die gespeicherte Ecke so nachführen, dass die Mitte stehen bleibt.
function Symbol.Layout(keepCenter)
    if not root then return end
    local left, middle, right = Symbol.Size("left"), Symbol.Size("middle"), Symbol.Size("right")
    local before = ns.Num(root:GetWidth())
    root:SetSize(middle, middle)
    if keepCenter and before then Symbol.KeepCenter(middle - before) end
    slots.middle.frame:SetSize(middle, middle)
    slots.left.frame:SetSize(left, left)
    slots.right.frame:SetSize(right, right)
    for _, name in ipairs(Symbol.SLOTS) do Anchor(slots[name]) end
end

function Symbol.Frame()
    if root then return root end
    root = CreateFrame("Frame", "ezCombatReadyPulse", UIParent)
    -- Größe aus der Einstellung „Größe der Mitte“ (sizeNext, ab Werk 45) statt einer festen Zahl; Symbol.Layout setzt
    -- sie unten ohnehin (Design-System 2.3: eine einstellbare Größe des Spielers ist keine feste Abweichung).
    local size = Symbol.Size("middle")
    root:SetSize(size, size)
    root:SetPoint(ANCHOR[1], UIParent, ANCHOR[3], ANCHOR[4], ANCHOR[5])
    -- Ebene LOW: über der Spielwelt, aber unter Blizzards Fenstern (Taschen und Aktionsleisten MEDIUM, Optionen HIGH,
    -- Dialoge DIALOG). Vorher HIGH – das Symbol lag über dem Rucksack und dem Optionsfenster (Spieltest des Nutzers vom
    -- 15.11.2026, zwei Bildschirmfotos).
    root:SetFrameStrata(Symbol.STRATA)
    root:EnableMouse(false)
    for _, name in ipairs(Symbol.SLOTS) do NewSlot(name) end

    -- Gesperrter DoT: eigene Ebene über dem linken Platz, Deckkraft aus Blizzards Dauer-Objekt.
    local leftFrame = slots.left.frame
    secretLayer = CreateFrame("Frame", nil, leftFrame)
    secretLayer:SetAllPoints(leftFrame)
    secretLayer:SetFrameLevel((leftFrame:GetFrameLevel() or 1) + 10)
    Glow.StyleIcon(secretLayer)
    Label(secretLayer, "left")
    Spiral(secretLayer)
    secretLayer:Hide()
    Symbol.Layout()

    -- Bisheriger Name (Tests, Erklärblasen): die gesperrte Ebene.
    root.secret = secretLayer
    root:Hide()
    -- Verschiebbar (ezCore.Mover); Schlüssel wie bisher „pulse“, damit eine gespeicherte Lage bleibt.
    moverPart = ns.Movable(root, "pulse", L.MOVER_PULSE, ANCHOR)
    Symbol.TakeShift()
    return root
end

-- Der Rahmen eines Platzes mit .icon, .label, .cooldown, .anim (Tests, Erklärblasen); legt die Gruppe bei Bedarf an.
function Symbol.Slot(slotName)
    Symbol.Frame()
    return slots[slotName] and slots[slotName].content or nil
end

---------------------------------------------------------------------------
-- Einträge
---------------------------------------------------------------------------

-- Farbenblind-Hilfe (EC-47): Ist in ezCore „Zeichen am Leuchten“ an (Core.Glow.MarksEnabled), steht das Zeichen der
-- Art (Core.GlowMark: * + o !) zusätzlich zur Farbe vor dem Text. Ein gesperrter Text bleibt unangetastet.
function Symbol.MarkedText(text, kind)
    if Core.IsSecret(text) or text == nil then return text end   -- zuerst IsSecret (Leitlinie 6)
    -- Seit ezCore 1.12.0 ein Helfer für alle Module (Core.GlowMarkText); die eigene Fassung bleibt als Rückfall.
    if type(Core.GlowMarkText) == "function" then return Core.GlowMarkText(text, kind or "ready") end
    local on = Core.Glow and type(Core.Glow.MarksEnabled) == "function" and Core.Glow.MarksEnabled()
    local mark = on and Core.GlowMark(kind or "ready") or nil
    if mark and text ~= "" then return mark .. " " .. text end
    return text
end

local function SetText(frame, text, kind)
    frame.label:SetText(Symbol.MarkedText(text, kind) or "")
    frame.label:SetTextColor(Core.GlowColor(kind or "ready"))
end

local function SetIcon(frame, icon)
    -- Ein gesperrtes Symbol darf an SetTexture gehen, aber nicht geprüft werden – auch nicht mit „or“: zuerst IsSecret,
    -- erst dann der Ersatz für ein fehlendes Symbol (ganz gesperrte Aura ohne Wissen aus dem eigenen Zauber, CB-05).
    if not ns.IsSecret(icon) and icon == nil then icon = DEFAULT_ICON end
    if not pcall(frame.icon.SetTexture, frame.icon, icon) then frame.icon:SetTexture(DEFAULT_ICON) end
end

-- Restzeit als Spirale: timer = { start, duration } aus offen gelesenen Zahlen, sonst keine Spirale.
local function SetTimer(frame, timer)
    local cooldown = frame.cooldown
    local start = timer and ns.Num(timer.start)
    local duration = timer and ns.Num(timer.duration)
    if start and duration and duration > 0 then
        cooldown:SetCooldown(start, duration)
        cooldown:Show()
    else
        if cooldown.Clear then cooldown:Clear() end
        cooldown:Hide()
    end
end

---------------------------------------------------------------------------
-- Noch nicht bereit: Spirale, Tönung und „wartet: …“ (ns.Readiness)
---------------------------------------------------------------------------

local function CountdownOn()
    return ns.Ready ~= nil and type(ns.Ready.CountdownOn) == "function" and ns.Ready.CountdownOn() == true
end

local function Tint(content, tint, force)
    if not force and content.waitTint == tint then return end
    local color = ns.Readiness.TINT[tint] or ns.Readiness.TINT.ready
    content.icon:SetVertexColor(color[1], color[2], color[3])
    content.waitTint = tint
end

local function ClearSpiral(content)
    local spiral = content.wait
    if content.waitSig ~= nil or spiral:IsShown() then
        if spiral.Clear then spiral:Clear() end
        spiral:Hide()
    end
    content.waitSig = nil
end

-- Text des Platzes: der Text des Eintrags, darunter „wartet: …“ (extra, nur bei „ausführlich“), beides in der Farbe
-- der Art. Tönung und Spirale zeigen den Zustand in jeder Auswahl.
local function WaitLabel(content, extra, force)
    if not force and extra == content.waitText then return end
    content.waitText = extra
    local base = content.baseLabel
    local text = base
    if extra and not Core.IsSecret(base) and Symbol.TextMode() == "full" then
        text = (type(base) == "string" and base ~= "") and (base .. "\n" .. extra) or extra
    end
    SetText(content, text, content.baseKind)
end

-- Spirale der Abklingzeit: offen aus Start und Dauer, gesperrt aus Blizzards Dauer-Objekt (nur weitergereicht). Neu
-- gesetzt wird nur bei anderer Abklingzeit oder force (SPELL_UPDATE_COOLDOWN, neuer Eintrag).
local function WaitSpiralFor(content, spell, cd, force)
    local sig
    if cd and cd.timer then
        sig = "t" .. cd.timer.start .. ":" .. cd.timer.duration
    elseif cd and cd.durationObject and cd.kind ~= "none" then
        sig = "o" .. tostring(cd.kind) .. ":" .. tostring(spell)
    end
    if not sig then return ClearSpiral(content) end
    local spiral = content.wait
    if force or sig ~= content.waitSig then
        local shown = false
        if cd.timer then
            spiral:SetCooldown(cd.timer.start, cd.timer.duration)
            shown = true
        elseif spiral.SetCooldownFromDurationObject then
            shown = pcall(spiral.SetCooldownFromDurationObject, spiral, cd.durationObject)
        end
        if not shown then return ClearSpiral(content) end
        spiral:Show()
        content.waitSig = sig
    end
    -- Zahlen wie an Blizzards Knopf (CVar countdownForCooldowns); die globale Abklingzeit nur als kurze Spirale.
    if spiral.SetHideCountdownNumbers then spiral:SetHideCountdownNumbers(cd.kind == "gcd" or not CountdownOn()) end
end

-- Zustand eines Eintrags anwenden. Ohne Zauber (Beispiel, Vorschau) oder ohne Antwort: Symbol wie sonst.
local function ApplyWait(content, entry, force)
    local spell = entry and entry.spell
    local state = spell ~= nil and ns.Readiness.State(spell) or nil
    local cd = state and state.cooldown or nil
    -- Einträge mit eigener Restzeit (läuft aus: DoT, Buff) haben schon ihre Spirale samt Zahl (SetTimer): keine
    -- zweite darüber, nur Tönung und Text – sonst deckt nach jedem Zauber die globale Abklingzeit die Restzeit ab,
    -- und bei echter Abklingzeit stünden zwei Zahlen übereinander.
    WaitSpiralFor(content, spell, entry.timer == nil and cd or nil, force)
    local wait, parts, tint = {}, {}, "ready"
    if cd and cd.kind == "real" then
        wait.cooldown = true
        if cd.wait then
            wait.seconds = math.max(1, math.ceil(cd.wait))
            parts[#parts + 1] = L.SYMBOL_WAIT_READY_IN:format(wait.seconds)
        elseif cd.shared then
            -- geteilte Abklingzeit (Welle 26): der andere Zauber derselben Kategorie steht im Text
            wait.locked, wait.shared = true, cd.shared
            parts[#parts + 1] = L.SYMBOL_WAIT_SHARED:format(cd.shared)
        else
            wait.locked = true
            parts[#parts + 1] = L.SYMBOL_WAIT_COOLDOWN
        end
    end
    if state then
        if state.usable == "power" then
            wait.power, tint = true, "power"
            parts[#parts + 1] = L.SYMBOL_WAIT_POWER:format(ns.Readiness.PowerName() or L.SYMBOL_WAIT_POWER_ANY)
        elseif state.usable == "unusable" then
            wait.unusable, tint = true, "unusable"
            parts[#parts + 1] = L.SYMBOL_WAIT_UNUSABLE
        end
    end
    if state and state.inRange == false then
        wait.range, tint = true, "range"         -- Reichweite vor Kraft: sie lässt sich gleich beheben
        parts[#parts + 1] = L.SYMBOL_WAIT_RANGE
    end
    Tint(content, tint, force)
    local extra = #parts > 0 and L.SYMBOL_WAIT:format(table.concat(parts, " · ")) or nil
    WaitLabel(content, extra, force)
    wait.text, wait.tint = extra, tint
    wait.spiral = content.waitSig ~= nil
    content.waitState = (wait.cooldown or wait.power or wait.unusable or wait.range or wait.spiral) and wait or nil
end

local function ClearWait(content)
    ClearSpiral(content)
    Tint(content, "ready")
    content.waitText, content.waitState = nil, nil
end

-- „Noch nicht bereit“ eines Platzes (Tests, Erklärblasen): { cooldown, seconds, locked, shared, power, unusable,
-- range, spiral, text, tint } oder nil, solange das Symbol bereit ist.
function Symbol.Wait(slotName)
    local slot = slots[slotName]
    return slot and slot.content.waitState or nil
end

-- Wichtigster gültiger Eintrag eines Platzes (slotName) bzw. über alle Plätze (ohne slotName): Schlüssel, Eintrag.
-- Das Beispiel (example) gehört in jeden Platz.
function Top(now, slotName)   -- weist dem lokalen Top von oben zu
    local bestKey, bestEntry
    for key, entry in pairs(entries) do
        if entry.untilTime and entry.untilTime <= now then
            entries[key] = nil
        elseif slotName == nil or key == "example" or Symbol.SLOT_OF[key] == slotName then
            if not bestKey or (RANK_OF[key] or 99) < (RANK_OF[bestKey] or 99) then
                bestKey, bestEntry = key, entry
            end
        end
    end
    return bestKey, bestEntry
end
Symbol.Top = function(slotName) return Top(GetTime(), slotName) end

local function ScheduleExpiry()
    local soonest
    for _, entry in pairs(entries) do
        if entry.untilTime and (not soonest or entry.untilTime < soonest) then soonest = entry.untilTime end
    end
    if soonest and not expireTimer then
        expireTimer = true
        C_Timer.After(math.max(0.05, soonest - GetTime() + 0.02), function()
            expireTimer = false
            Symbol.Refresh()
        end)
    end
end

-- Den Zustand „noch nicht bereit“ aller sichtbaren Plätze nachführen (Takt, Ereignisse; force: Spirale neu setzen).
local waitTicker
function Symbol.UpdateWait(force)
    if not root then return false end
    local any = false
    for _, name in ipairs(Symbol.SLOTS) do
        local slot = slots[name]
        local entry = slot.shownKey and entries[slot.shownKey]
        if entry and slot.content:IsShown() then
            ApplyWait(slot.content, entry, force == true)
            if entry.spell ~= nil then any = true end
        end
    end
    return any
end

-- Der Takt läuft nur, solange ein sichtbarer Eintrag einen Zauber trägt.
function WatchWait()   -- weist dem lokalen WatchWait von oben zu
    local any = false
    for _, name in ipairs(Symbol.SLOTS) do
        local slot = slots[name]
        local entry = slot.shownKey and entries[slot.shownKey]
        if entry and entry.spell ~= nil and slot.content:IsShown() then any = true end
    end
    if any and not waitTicker and C_Timer.NewTicker then
        waitTicker = C_Timer.NewTicker(WAIT_EVERY, function()
            ns.Try("Symbol", function()
                if not Symbol.UpdateWait() and waitTicker then
                    waitTicker:Cancel()
                    waitTicker = nil
                end
            end)
        end)
    elseif not any and waitTicker then
        waitTicker:Cancel()
        waitTicker = nil
    end
end
function Symbol.Waiting() return waitTicker ~= nil end

-- Text eines Eintrags nach der Auswahl symbolText: "full" der ausführliche (label), "name" der Name, "off" keiner –
-- außer der Zeile für jede Auswahl (always).
function Symbol.TextOf(entry, mode)
    if type(entry) ~= "table" then return nil end
    mode = mode or Symbol.TextMode()
    if mode == "full" then return entry.label end
    if entry.always ~= nil then return entry.always end
    if mode == "name" then return entry.name end
    return nil
end

-- Grundtext eines Platzes: das Beispiel beim Verschieben mit seinem Text (jede Auswahl), sonst Symbol.TextOf.
local function BaseLabel(slotName, key, entry)
    if key == "example" then return L["SYMBOL_EXAMPLE_" .. slotName] or entry.label end
    return Symbol.TextOf(entry)
end

-- Einen Platz neu zeichnen; Rückgabe: zeigt er etwas (auch die gesperrte Ebene)?
local function RefreshSlot(slot, now, groupShown)
    local content = slot.content
    local key, entry = Top(now, slot.name)
    if not key then
        content:Hide()
        Glow.Hide(content)
        ClearWait(content)
        slot.shownKey, slot.shownVersion = nil, nil
        return slot.name == "left" and secretInfo ~= nil
    end
    local changed = key ~= slot.shownKey or entry.version ~= slot.shownVersion
    local fresh = key ~= slot.shownKey or not groupShown or not content:IsShown()
    slot.shownKey, slot.shownVersion = key, entry.version
    content:Show()
    if changed or fresh then
        SetIcon(content, entry.icon)
        content.baseLabel, content.baseKind = BaseLabel(slot.name, key, entry), entry.kind
        SetTimer(content, entry.timer)
        Glow.Show(content, false, entry.kind)
    end
    -- Noch nicht bereit? Bei neuem Eintrag alles neu (Text, Tönung, Spirale), sonst nur, was sich geändert hat.
    ApplyWait(content, entry, changed or fresh)
    if fresh or (changed and entry.untilTime) then
        content.anim:Stop()
        content.appear:Stop()
        content:SetAlpha(1)
        if entry.untilTime then
            local hold = math.max(0.2, entry.untilTime - GetTime() - FADE_SECONDS)
            if content.anim.fadeOut then content.anim.fadeOut:SetStartDelay(hold) end
            content.anim:Play()
        else
            content.appear:Play()
        end
    end
    return true
end

function Symbol.Refresh()
    local frame = Symbol.Frame()
    local now = GetTime()
    local groupShown = frame:IsShown()
    local any, shown = false, {}
    for _, name in ipairs(Symbol.SLOTS) do
        shown[name] = RefreshSlot(slots[name], now, groupShown)
        if shown[name] then any = true end
    end
    Arrange(shown, groupShown)
    if any then frame:Show() else frame:Hide() end
    ScheduleExpiry()
    WatchWait()
end

local function SameTimer(a, b)
    if a == nil or b == nil then return a == b end
    return a.start == b.start and a.duration == b.duration
end

-- Name bzw. Zeile für jede Auswahl aus texts ({ name = …, always = … }); gesperrt oder leer gilt als nicht genannt
-- (ein gesperrter Text lässt sich nicht vergleichen, Leitlinie 6).
local function PlainText(value)
    if Core.IsSecret(value) or type(value) ~= "string" or value == "" then return nil end
    return value
end
local function Texts(texts)
    if Core.IsSecret(texts) or type(texts) ~= "table" then return nil, nil end
    return PlainText(texts.name), PlainText(texts.always)
end

-- spell: Zauber des Eintrags (ID oder Name, offen) für „noch nicht bereit“; gesperrt gilt er als nicht genannt.
local function Store(key, icon, label, kind, untilTime, timer, spell, texts)
    if Core.IsSecret(spell) then spell = nil end
    local name, always = Texts(texts)
    local entry = entries[key]
    if entry and entry.icon == icon and entry.label == label and entry.kind == kind and not untilTime
        and not entry.untilTime and SameTimer(entry.timer, timer) and entry.spell == spell
        and entry.name == name and entry.always == always then
        return false        -- unverändert (dauerhafte Einträge werden in jedem Takt erneut gemeldet)
    end
    entries[key] = { icon = icon, label = label, kind = kind, untilTime = untilTime, timer = timer, spell = spell,
        name = name, always = always, version = ((entry and entry.version) or 0) + 1 }
    return true
end

-- Dauerhafter Eintrag, bis Clear(key). timer (nur „läuft aus“): { start = …, duration = … } aus offen gelesenen
-- Zahlen – der linke Platz zeigt dann die Restzeit als Spirale. spell: Zauber, dessen Bereitschaft das Symbol zeigt.
-- label: der ausführliche Text; texts: { name = Text bei „nur Name“, always = Zeile für jede Auswahl } (TextOf).
function Symbol.Set(key, icon, label, kind, timer, spell, texts)
    if Store(key, icon, label, kind, nil, timer, spell, texts) then Symbol.Refresh() end
end

-- Kurzer Eintrag: steht die eingestellte Anzeigedauer (oder seconds), dann verblasst er.
function Symbol.Pop(key, icon, label, kind, seconds, spell, texts)
    seconds = seconds or ns.S.symbolHold or 2
    Store(key, icon, label, kind, GetTime() + seconds + FADE_SECONDS, nil, spell, texts)
    local slot = slots[Symbol.SLOT_OF[key] or ""]
    if slot and slot.shownKey == key then slot.shownKey = nil end      -- auch derselbe Eintrag springt erneut auf
    Symbol.Refresh()
end

function Symbol.Clear(key)
    if entries[key] == nil then return end
    entries[key] = nil
    Symbol.Refresh()
end

function Symbol.Entry(key) return entries[key] end

---------------------------------------------------------------------------
-- Gesperrter DoT: Deckkraft aus Blizzards Dauer-Objekt (darf gesperrt sein, wird nur weitergereicht)
---------------------------------------------------------------------------

-- key: Instanz-ID der Aura (Symbol und Text werden nur bei einer anderen Aura oder anderem Text neu gesetzt – ein
-- gesperrtes Symbol lässt sich nicht vergleichen), icon darf gesperrt sein. alpha: Warnkurve (1 = läuft aus),
-- gateAlpha: Gegenkurve (0 = läuft aus) – beide nur weitergereicht. durationObject: Blizzards Dauer-Objekt für die
-- Spirale der Restzeit (unverändert an SetCooldownFromDurationObject; ohne die Methode keine Spirale). texts: wie
-- bei Symbol.Set – der Text folgt der Auswahl symbolText.
function Symbol.SetSecret(key, icon, label, alpha, gateAlpha, durationObject, texts)
    local frame = Symbol.Frame()
    if Core.IsSecret(durationObject) then durationObject = nil end      -- nie einen gesperrten Wert vergleichen
    local name, always = Texts(texts)
    if not secretInfo or secretInfo.key ~= key or secretInfo.label ~= label or secretInfo.name ~= name
        or secretInfo.always ~= always or secretInfo.durationObject ~= durationObject then
        SetIcon(secretLayer, icon)
        SetText(secretLayer, Symbol.TextOf({ label = label, name = name, always = always }), "dot")
        local cooldown, shown = secretLayer.cooldown, false
        if durationObject and cooldown.SetCooldownFromDurationObject then
            shown = pcall(cooldown.SetCooldownFromDurationObject, cooldown, durationObject)
        end
        if shown then
            cooldown:Show()
        else
            if cooldown.Clear then cooldown:Clear() end
            cooldown:Hide()
        end
        secretInfo = { key = key, label = label, name = name, always = always, durationObject = durationObject }
    end
    secretLayer:Show()
    Glow.Show(secretLayer, false, "dot")
    secretLayer:SetAlpha(alpha)
    slots.left.gate:SetAlpha(gateAlpha)
    -- Die gesperrte Ebene zählt als Eintrag des linken Platzes (einzelnes Symbol in der Mitte)
    local shown = { left = true }
    for _, name in ipairs({ "middle", "right" }) do shown[name] = slots[name].content:IsShown() end
    Arrange(shown, frame:IsShown())
    frame:Show()
end

function Symbol.ClearSecret()
    if not secretInfo then return end
    secretInfo = nil
    secretLayer:Hide()
    Glow.Hide(secretLayer)
    slots.left.gate:SetAlpha(1)
    Symbol.Refresh()
end

function Symbol.SecretShown() return secretInfo ~= nil end

-- Auswahl symbolText geändert: Text aller sichtbaren Plätze und der gesperrten Ebene neu setzen, ohne Aufspringen.
function Symbol.Relabel()
    if not root then return end
    for _, name in ipairs(Symbol.SLOTS) do
        local slot = slots[name]
        local entry = slot.shownKey and entries[slot.shownKey]
        if entry then slot.content.baseLabel = BaseLabel(name, slot.shownKey, entry) end
    end
    if secretInfo then SetText(secretLayer, Symbol.TextOf(secretInfo), "dot") end
    Symbol.UpdateWait(true)
end

-- „Zeigen“: alle drei Plätze zugleich – links ein auslaufender DoT mit Restzeit, in der Mitte die nächste
-- Fähigkeit, rechts „wieder bereit“ (kurz). Nach einigen Sekunden räumt die Vorschau ihre Einträge wieder ab.
local DEMO_SECONDS = 4
function Symbol.Demo()
    local now = GetTime()
    Symbol.Set("dot", 136118, L.SYMBOL_DOT_PLAIN, "dot", { start = now - 2, duration = 2 + DEMO_SECONDS })
    local dot = entries.dot
    if not entries.next then
        Symbol.Set("next", DEFAULT_ICON, L.SYMBOL_NEXT:format(L.SYMBOL_DEMO_NEXT), "next", nil, nil,
            { name = L.SYMBOL_DEMO_NEXT })
    end
    local nextEntry = entries.next
    ns.Ready.Pulse(DEFAULT_ICON, "ready")
    C_Timer.After(DEMO_SECONDS, function()
        if entries.dot == dot then Symbol.Clear("dot") end
        if entries.next == nextEntry and nextEntry.label == L.SYMBOL_NEXT:format(L.SYMBOL_DEMO_NEXT) then
            Symbol.Clear("next")
        end
    end)
    return true
end

---------------------------------------------------------------------------

ns.OnSettingChanged(function(key)
    if key == "sizeNext" or key == "sizeExpiring" or key == "sizeReady" then Symbol.Layout(key == "sizeNext") end
    if key == "symbolCenter" and root then Symbol.Refresh() end
    if key == "symbolText" and root then Symbol.Relabel() end
end)

-- Blizzard meldet eine neue oder beendete Abklingzeit: Spiralen neu setzen (das Dauer-Objekt lässt sich nicht
-- vergleichen). Kraft, Nutzbarkeit und Ziel ändern nur Tönung und Text.
ns.On("SPELL_UPDATE_COOLDOWN", function() Symbol.UpdateWait(true) end)
for _, event in ipairs({ "SPELL_UPDATE_USABLE", "PLAYER_TARGET_CHANGED" }) do
    ns.On(event, function() Symbol.UpdateWait() end)
end

ns.OnReady(Symbol.Frame)
