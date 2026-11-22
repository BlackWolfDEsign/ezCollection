local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Quest-Erfahrung als Vorschau auf Blizzards Erfahrungsleiste (Feature I1 des Gesamtreviews vom 18.11.2026, mit der
    Korrektur der Gegenprüfung; Entscheidung des Nutzers vom 18.11.2026, Punkt 8 im ROADMAP-Index: zuerst I1 und I2).
    Hinter dem Stand der Leiste: hell die Erfahrung der fertigen Quests, blass die aller Quests im Log. Maus über die
    Leiste bzw. die Erholungs-Marke: „nach Abgabe Stufe X, Y %“ für beide Summen. Nur Anzeige.

    Daten (Leitlinie 11, Quelle im Tooltip):
      Client      EP je Quest und „fertig“ über ezCore (Core.QuestLogXP: GetQuestLogRewardXP, C_QuestLog.IsComplete,
                  ReadyForTurnIn, Teilziele – dieselben Helfer wie die Leveling-Route, LevelRoute.lua), Stufe und
                  Erfahrung (UnitLevel, UnitXP, UnitXPMax), „keine Erfahrung“ (Core.XPBlocked: Höchststufe, beim Lehrer
                  ausgeschaltet, Stufengrenze eines Probe-Kontos; Core.XPLevelCap für „nach Abgabe“). Nennt das
                  Questlog für keine Quest EP, zeigt die Leiste nichts und der Tooltip sagt warum.
      geschätzt   Über eine Stufe hinaus rechnet Core.LevelAfterXP jede weitere Stufe mit den EP der jetzigen (der Client
                  nennt nur UnitXPMax); der Tooltip schreibt dann „geschätzt“.
    Leiste (Blizzards Forever-Quelle, Gethe/wow-ui-source Zweig forever, Blizzard_StatusTrackingBar:
    Mainline/StatusTrackingBar.xml, Mainline/StatusTrackingManagerOverrides.lua, Shared/ExpBar.lua, Mainline/ExpBar.xml):
    StatusTrackingBarManager.barContainers[i].bars[StatusTrackingBarInfo.BarsEnum.Experience] – je Container eine Leiste
    aus ExpStatusBarTemplate (isExpBar). Die Container sind Systeme des Bearbeitungsmodus
    (EditModeStatusTrackingBar1/2SystemTemplate): ezQuest hängt nur an (Leitlinien 1 und 5) – ein eigener Rahmen ohne
    Maus als Kind der Leiste über ihrer Füllung (StatusBar), dazu hooksecurefunc(bar, "Update") und HookScript("OnEnter")
    an Leiste und Erholungs-Marke (ExhaustionTick; die Zeilen kommen unter Blizzards Tooltip). Verschoben wird nur
    Blizzards Erholungs-Marke (Lage, außerhalb des Kampfes, abschaltbar; Abschnitt „Blizzards Erholungs-Marke wandert
    mit“), nichts in Blizzards Tabellen geschrieben; das Gold der Quests ist eine Fläche in Blizzards Questfarbe
    (NORMAL_FONT_COLOR über Core.Style) – dieselbe Farbe wie die Farbprobe im Tooltip (Abschnitt „Gold als Fläche“), die
    Erholung Blizzards eigener Streifen (Atlas UI-HUD-ExperienceBar-Fill-Prediction). Die eigenen Texturen laufen auch im
    Kampf; die Marke rückt erst danach nach.
    Fremde Addons (Leitlinie 9): Die Vorschau ist ein Kind von Blizzards Leiste. Blendet ein Addon die Leiste aus oder
    ersetzt sie durch eine eigene, ist die Vorschau mit weg (kein zweiter Balken daneben); versetzt es Blizzards Leiste,
    wandert die Vorschau mit. /ezq status nennt den Fall „Leiste nicht zu sehen“.

    Erholung nach den Quests (Spieltest 21.11.2026, wörtlich „der Balken "bis zur Marke reicht deine ..." ist garnicht
    sichtbar. bzw hinter den anderen neuen. ist das logisch? so wie blizzard seine ep berechnet/vergibt?“; Entscheidung
    des Nutzers vom 21.11.2026 „Erholung nach den Quests“, ROADMAP-Index): Blizzards Erholungs-Streifen
    (ExhaustionLevelFillBar, ARTWORK -1 der Leiste selbst) liegt unter der Füllung und damit unter ezQuests Rahmen – das
    Gold deckte ihn zu. Blizzards Rechnung (Shared/ExpBar.lua ExhaustionTickMixin:UpdateTickPosition): die Erholung
    (GetXPExhaustion) ist ein Vorrat ab deinem Stand, nur Monster-EP verbrauchen ihn (doppelt), Quest-EP nicht – nach der
    Abgabe steht die Leiste weiter und der Vorrat beginnt dort. Darum zeichnet ezQuest einen eigenen Streifen in
    Blizzards Farbe (Atlas UI-HUD-ExperienceBar-Fill-Prediction) ab dem Ende der fertigen Quests über das blasse Gold;
    das blasse Gold ist rechts vom Blau zu sehen und endet bei Stand + alle Quests; reicht es nur bis ins Blau, verdeckt
    das Blau es (den schmalen Streifen „alle Quests“ unter
    dem Blau gibt es nicht mehr: Entscheidung des Nutzers vom 22.11.2026 „weglassen“, ROADMAP-Index). Reihenfolge
    (unten → oben): blass alle Quests, Erholung, kräftig fertige Quests. XP.Segments rechnet die
    Stücke einmal für Leiste und Legende. Blizzards Marke rückt ans Ende des Blaus (Abschnitt „Blizzards Erholungs-Marke
    wandert mit“); mit Schalter aus bleibt sie, wo Blizzard sie setzt, und die Legende sagt das.
]]

local XP = {}
ns.XPPreview = XP

local Num = Core.Num

XP.ATLAS = "UI-HUD-ExperienceBar-Fill-Experience"
--[[ Gold als Fläche. Spieltests 21./22.11.2026 mit Bildschirmfotos: „siehe tooltip das ist nicht das kräftige“ (die
    entsättigte, gold getönte Erfahrungs-Füllung wirkte oliv, gemessen etwa RGB 99/83/7), nach #657 „hat sich gar nichts
    getan“ und nach #662 „jetzt stimmen die farben nicht mehr mit dem tooltip überein“ (Blizzards gelbe Füllung der
    Ruf-Leiste, UI-HUD-ExperienceBar-Fill-Reputation-Faction-Yellow, hat Scheiben-Ränder; über SetAtlas wie über ihre
    Datei zeigte das Stück auf der Leiste etwas anderes als die Farbprobe, zuletzt blau, gemessen etwa 77/107/216).
    Gleich aussehen können Leiste und Farbprobe sicher nur mit derselben Farbe: eine Fläche in Blizzards Questfarbe,
    kräftig voll deckend, blass mit weniger Deckkraft; die Farbprobe ist dieselbe Fläche (XP.Swatch). ]]
XP.ALPHA_DONE = 1       -- fertige Quests: kräftig, voll deckend
XP.ALPHA_ALL = 0.35     -- alle Quests im Log: blass
XP.MIN_WIDTH = 0.5      -- schmalere Stücke (Bildpunkte) bleiben verborgen
XP.ATLAS_RESTED = "UI-HUD-ExperienceBar-Fill-Rested"
XP.ATLAS_PREDICTION = "UI-HUD-ExperienceBar-Fill-Prediction"   -- Blizzards Erholungs-Streifen (ExpBar.xml)
XP.ATLAS_PIP = "UI-HUD-ExperienceBar-Frame-Pip"                -- Blizzards Erholungs-Marke (ExpBar.xml)
XP.REST_FALLBACK = { 0.25, 0.4, 0.85 }                         -- Fläche, falls der Client den Atlas nicht kennt
XP.LAYERS = { "all", "rest", "done" }                          -- Schichten von unten nach oben (Sub-Ebene = Index)
XP.LAYER_ALPHA = { all = XP.ALPHA_ALL, rest = 1, done = XP.ALPHA_DONE }

local overlays = {}     -- [Blizzards Leiste] = eigener Rahmen
local order = {}        -- dieselben Rahmen in Reihenfolge (für Tests und Status)
local sums              -- letzte Summe aus Core.QuestLogXP (nil: noch nicht gerechnet)
local waiting = false   -- wartet auf Blizzard_StatusTrackingBar

-- Blizzards Erfahrungsleisten (eine je Container) → Liste, leer ohne StatusTrackingBarManager
function XP.Bars()
    local out = {}
    local manager = rawget(_G, "StatusTrackingBarManager")
    local containers = type(manager) == "table" and Core.Peek(manager, "barContainers") or nil
    if type(containers) ~= "table" then return out end
    local info = rawget(_G, "StatusTrackingBarInfo")
    local enum = type(info) == "table" and Core.Peek(info, "BarsEnum") or nil
    local index = type(enum) == "table" and Num(Core.Peek(enum, "Experience")) or nil
    for _, container in ipairs(containers) do
        local bars = type(container) == "table" and Core.Peek(container, "bars") or nil
        if type(bars) == "table" then
            local bar = index and bars[index] or nil
            if type(bar) ~= "table" then
                bar = nil
                -- Rückfall: an der Kennung der Vorlage (ExpStatusBarTemplate, KeyValue isExpBar)
                for _, b in pairs(bars) do
                    if type(b) == "table" and Core.Peek(b, "isExpBar") == true then bar = b break end
                end
            end
            if bar then out[#out + 1] = bar end
        end
    end
    return out
end

-- Vorschau aktiv? Schalter an und der Charakter bekommt Erfahrung
function XP.Active()
    if not ns.Enabled("xpPreview") then return false end
    return not Core.XPBlocked()
end

-- Atlas setzen → true, wenn der Client ihn kennt
local function TrySetAtlas(tex, atlas)
    if not Core.AtlasExists(atlas) then return false end
    local ok, set = pcall(tex.SetAtlas, tex, atlas)
    return ok and set ~= false
end

-- Textur auf ezQuests Rahmen: Gold als Fläche in Blizzards Questfarbe (wie die Farbprobe) oder Blizzards
-- Erholungs-Streifen (ohne den Atlas eine blaue Fläche)
local function Texture(frame, sub, alpha, rest)
    local tex = frame:CreateTexture(nil, "ARTWORK", nil, sub)
    tex:SetAlpha(alpha)
    tex:Hide()
    if rest and TrySetAtlas(tex, XP.ATLAS_PREDICTION) then
        tex.ezAtlas = XP.ATLAS_PREDICTION
        return tex
    end
    local r, g, b
    if rest then
        r, g, b = XP.REST_FALLBACK[1], XP.REST_FALLBACK[2], XP.REST_FALLBACK[3]
    else
        r, g, b = Core.Style.Color("normal")
    end
    tex:SetColorTexture(r, g, b)
    tex.ezAtlas = nil
    return tex
end
XP.Texture = Texture    -- für die Prüfungen der Rückfälle

-- Stücke der Leiste in EP { Anfang, Ende } (Ende über max heißt „bis zum Rand“) → { done, all, rest }, je nil,
-- wenn es das Stück nicht gibt. Erholung ab dem Ende der fertigen Quests (Quest-EP verbrauchen keine Erholung); beginnt
-- sie erst auf der nächsten Stufe, steht sie nicht auf dieser Leiste; ohne Quest-EP (all 0) zeichnet nur Blizzard sie
-- (nichts deckt dann seinen Streifen).
function XP.Segments(xp, max, done, all, left)
    local out = {}
    if not (xp and max and max > 0) then return out end
    done, all = done or 0, all or 0
    if done > 0 then out.done = { xp, xp + done } end
    if all > 0 then out.all = { xp, xp + all } end
    if left and left > 0 and all > 0 and xp + done < max then
        out.rest = { xp + done, xp + done + left }
    end
    return out
end

-- ein Stück der Vorschau (EP von seg[1] bis seg[2], höchstens bis zum Ende)
local function Place(frame, tex, seg, max, width)
    if not seg then tex:Hide() return end
    local from = math.min(1, math.max(0, seg[1] / max))
    local to = math.min(1, seg[2] / max)
    local w = (to - from) * width
    if w < XP.MIN_WIDTH then
        tex:Hide()
        return
    end
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", frame, "TOPLEFT", from * width, 0)
    tex:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", from * width, 0)
    tex:SetWidth(w)
    -- nur dieser Ausschnitt der Füllung: SetTexCoord rechnet gegen die ganze Datei, darum über den Bereich des Atlas
    -- (Core.AtlasTexCoord, Gegenprüfung I1); ohne Angaben des Clients bleibt das ganze Atlas-Stück gestreckt
    if tex.ezAtlas then
        local l, r, t, b = Core.AtlasTexCoord(tex.ezAtlas, from, to, 0, 1)
        if l then tex:SetTexCoord(l, r, t, b) end
    end
    tex:Show()
end

-- Blizzards Erholungs-Vorrat (GetXPExhaustion) → EP oder nil
local function RestLeft()
    return Num(Core.Call(rawget(_G, "GetXPExhaustion")))
end

-- Lage der Vorschau auf einer Leiste neu setzen (nach Update der Leiste, neuer Größe, neuer Summe)
function XP.Layout(frame)
    if type(frame) ~= "table" or not frame.all then return end
    local okW, width = pcall(frame.GetWidth, frame)
    width = okW and Num(width) or nil
    local xp = Num(Core.Call(rawget(_G, "UnitXP"), "player"))
    local max = Num(Core.Call(rawget(_G, "UnitXPMax"), "player"))
    if not (sums and width and width > 0 and xp and max and max > 0) or not XP.Active() then
        for _, key in ipairs(XP.LAYERS) do frame[key]:Hide() end
        XP.PlaceTick(frame)
        return
    end
    local seg = XP.Segments(xp, max, sums.done, sums.all, RestLeft())
    for _, key in ipairs(XP.LAYERS) do
        Place(frame, frame[key], seg[key], max, width)
    end
    XP.PlaceTick(frame)
end

---------------------------------------------------------------------------
-- Blizzards Erholungs-Marke wandert mit (Spieltest 21.11.2026, wörtlich „der marker stimmt nicht mehr mit dem balken
-- überein“; Entscheidung des Nutzers vom 21.11.2026 „Ja, Marke mitwandern“, ROADMAP-Index). Blizzard setzt die Marke
-- (ExhaustionTick) in ExhaustionTickMixin:UpdateTickPosition auf Stand + Erholung (Shared/ExpBar.lua); ezQuest setzt
-- sie danach (hooksecurefunc) ans Ende des blauen Stücks, also um die fertigen Quests weiter. Leitlinie 4/5: nur die
-- Lage, nur außerhalb des Kampfes (im Kampf bleibt Blizzards Lage, danach über ns.AfterCombat), abschaltbar
-- (xpTickFollow), Blizzards eigene Lage als Ausgang: ohne fertige Quests, mit Schalter aus oder ohne Vorschau setzt
-- ezQuest die Marke einmal dorthin zurück, wo Blizzard sie hätte (XP.BlizzardTick rechnet UpdateTickPosition nach),
-- und rührt sie danach nicht mehr an.
---------------------------------------------------------------------------

-- Wohin die Marke gehört → Anteil der Leiste (Ende des blauen Stücks) | false (Erholung beginnt erst auf der nächsten
-- Stufe: keine Marke auf dieser Leiste) | nil (Blizzards Lage)
function XP.TickTarget()
    if not (ns.Enabled("xpTickFollow") and XP.Active() and sums and (sums.done or 0) > 0) then return nil end
    local xp = Num(Core.Call(rawget(_G, "UnitXP"), "player"))
    local max = Num(Core.Call(rawget(_G, "UnitXPMax"), "player"))
    local left = RestLeft()
    if not (xp and max and max > 0 and left and left > 0) then return nil end
    local seg = XP.Segments(xp, max, sums.done, sums.all, left)
    if seg.rest then return seg.rest[2] / max end
    if xp + sums.done >= max then return false end
    return nil
end

-- Blizzards Rand-Regel der Marke (KeyValue hideAtBarEdge in ExpBar.xml): zu sehen nur zwischen 1 % und 99 %
local function TickShown(tick, ratio)
    if Core.Peek(tick, "hideAtBarEdge") == true then return ratio >= 0.01 and ratio <= 0.99 end
    return true
end

local function TickOffsetY()
    return Num(rawget(_G, "EXHAUSTION_TICK_OFFSET_Y")) or 0
end

-- Blizzards eigene Lage der Marke, wie ExhaustionTickMixin:UpdateTickPosition sie setzt (Rückweg)
function XP.BlizzardTick(bar, tick, width)
    local xp = Num(Core.Call(rawget(_G, "UnitXP"), "player"))
    local max = Num(Core.Call(rawget(_G, "UnitXPMax"), "player"))
    local left = RestLeft()
    if not (left and left > 0 and xp and max and max > 0) or Core.XPBlocked() then
        tick:Hide()
        return
    end
    local ratio = math.max((xp + left) / max, 0)
    tick:SetShown(TickShown(tick, ratio))
    local x = math.max(ratio * width, 0)
    tick:ClearAllPoints()
    if x > width and Core.Call(rawget(_G, "ShouldRestedXpBarDisplayWhenOverflowing")) ~= true then return end
    tick:SetPoint("CENTER", bar, "LEFT", math.min(x, width), TickOffsetY())
end

-- Marke an einer Leiste setzen (nach Blizzards UpdateTickPosition und nach jedem Layout der Vorschau)
function XP.PlaceTick(frame)
    local owner = type(frame) == "table" and frame.bar or nil
    local tick = owner and Core.Peek(owner, "ExhaustionTick") or nil
    if type(tick) ~= "table" or type(tick.SetPoint) ~= "function" then return end
    local target = XP.TickTarget()
    if target == nil and not frame.tickMoved then return end      -- Blizzards Lage, nie angefasst: nichts tun
    if Core.InCombat() then
        frame.tickPending = true
        ns.AfterCombat(function() ns.Try("XPPreviewTick", XP.PlaceTick, frame) end, frame.tickKey)
        return
    end
    frame.tickPending = nil
    -- Bezug wie Blizzard: die Eltern der Marke (self:GetParent() in UpdateTickPosition)
    local okP, bar = pcall(tick.GetParent, tick)
    if not okP or type(bar) ~= "table" then bar = owner end
    local okW, width = pcall(bar.GetWidth, bar)
    width = okW and Num(width) or nil
    if not (width and width > 0) then return end
    if target == nil then
        frame.tickMoved = nil
        XP.BlizzardTick(bar, tick, width)
        return
    end
    frame.tickMoved = true
    if target == false then
        tick:Hide()
        return
    end
    tick:ClearAllPoints()
    tick:SetShown(TickShown(tick, target))
    -- über die Stufe hinaus wie Blizzard: ohne ShouldRestedXpBarDisplayWhenOverflowing kein Anker
    if target > 1 and Core.Call(rawget(_G, "ShouldRestedXpBarDisplayWhenOverflowing")) ~= true then return end
    tick:SetPoint("CENTER", bar, "LEFT", math.min(target, 1) * width, TickOffsetY())
end

-- Wartet eine Marke auf das Ende des Kampfes (steht also gerade auf Blizzards Lage)?
function XP.TickPending()
    for _, frame in ipairs(order) do
        if frame.tickPending then return true end
    end
    return false
end

-- Blizzards Leiste hat neu gezeichnet (neue EP, Stufe, Größe): die Summen frisch lesen, damit eine gerade abgegebene
-- Quest nicht bis zur gedrosselten Neuberechnung doppelt steht (neuer Stand plus alte Summe; Gegenprüfung I1)
function XP.OnBarUpdate(frame)
    if XP.Active() then sums = Core.QuestLogXP() end
    XP.Layout(frame)
end

-- Eigener Rahmen an einer Leiste (einmal je Leiste)
function XP.Attach(bar)
    if overlays[bar] then return overlays[bar] end
    local status = Core.Peek(bar, "StatusBar")
    local base = type(status) == "table" and status or bar
    local frame = CreateFrame("Frame", nil, bar)
    frame:SetAllPoints(base)
    local okLevel, level = pcall(base.GetFrameLevel, base)
    if okLevel and Num(level) then frame:SetFrameLevel(level + 1) end
    for i, key in ipairs(XP.LAYERS) do frame[key] = Texture(frame, i, XP.LAYER_ALPHA[key], key == "rest") end
    frame:SetScript("OnSizeChanged", function(self) ns.Try("XPPreviewLayout", XP.Layout, self) end)
    frame:SetScript("OnShow", function(self) ns.Try("XPPreviewLayout", XP.Layout, self) end)
    overlays[bar] = frame
    order[#order + 1] = frame
    frame.bar = bar
    frame.tickKey = "XPPreviewTick" .. #order
    if type(bar.Update) == "function" then
        hooksecurefunc(bar, "Update", function() ns.Try("XPPreviewLayout", XP.OnBarUpdate, frame) end)
    end
    if type(bar.HookScript) == "function" then
        bar:HookScript("OnEnter", function(self) ns.Try("XPPreviewTip", XP.ShowTip, self) end)
    end
    local tick = Core.Peek(bar, "ExhaustionTick")
    if type(tick) == "table" and type(tick.HookScript) == "function" then
        tick:HookScript("OnEnter", function() ns.Try("XPPreviewTip", XP.AddToTip, GameTooltip) end)
    end
    if type(tick) == "table" and type(tick.UpdateTickPosition) == "function" then
        hooksecurefunc(tick, "UpdateTickPosition", function() ns.Try("XPPreviewTick", XP.PlaceTick, frame) end)
    end
    XP.Layout(frame)
    return frame
end

-- An allen Leisten anhängen; fehlt Blizzards Leiste noch, nach dem Laden von Blizzard_StatusTrackingBar
function XP.Hook()
    local bars = XP.Bars()
    for _, bar in ipairs(bars) do XP.Attach(bar) end
    if #bars == 0 and not waiting then
        waiting = true
        ns.WhenAddOnLoaded("Blizzard_StatusTrackingBar", function()
            if #XP.Bars() > 0 then XP.Hook() end
        end)
    end
    return #bars
end

-- Summen neu rechnen und alle Vorschauen setzen
function XP.Refresh()
    if ns.Enabled("xpPreview") then
        if #order == 0 then XP.Hook() end
        sums = Core.QuestLogXP()
    end
    for _, frame in ipairs(order) do XP.Layout(frame) end
end

function XP.Sums() return sums end
function XP.Overlays() return order end

---------------------------------------------------------------------------
-- Tooltip: „nach Abgabe Stufe X, Y %“ und was die Farben der Leiste bedeuten
-- Spieltest 20.11.2026 (wörtlich „ep balken tooltip scheint nicht formatiert zu sein und keiner versteht die farben
-- (bedeutung/farben müssen in tooltip ersichtlich sein)“): breiter Tooltip (Core.TipWide) mit Abstand zu Blizzards
-- Zeilen (Core.Tooltip.Gap), die Menge rechtsbündig, „nach Abgabe“ in eigener Zeile, darunter eine Legende mit
-- Farbproben: Blizzards eigene Füllungen als Atlas (Forever-Quelle Blizzard_StatusTrackingBar/Mainline/
-- ExpBarOverrides.lua: UI-HUD-ExperienceBar-Fill-Rested bzw. -Fill-Experience; Mainline/ExpBar.xml:
-- ExhaustionLevelFillBar mit -Fill-Prediction) und ezQuests Gold in den beiden Helligkeiten der Leiste.
---------------------------------------------------------------------------

XP.SWATCH_W, XP.SWATCH_H = 22, 10
XP.PIP_W = 8            -- Farbprobe der Marke (Blizzards Marke ist 10 × 14)
XP.INDENT = "    "      -- Einzug der Zeile „nach Abgabe …“ unter ihrer Summe

-- Farbprobe: Blizzards Atlas → „|A…|a“; ohne Atlas eine Fläche in r, g, b (0–1) mit Deckkraft alpha über dem dunklen
-- Tooltip-Grund → „|T…|t“
function XP.Swatch(atlas, r, g, b, alpha)
    if atlas then return ("|A:%s:%d:%d|a"):format(atlas, XP.SWATCH_H, XP.SWATCH_W) end
    local a = type(alpha) == "number" and alpha or 1
    local function C(v) return math.floor((v or 1) * a * 255 + 0.5) end
    return ("|TInterface\\Buttons\\WHITE8X8:%d:%d:0:0:8:8:0:8:0:8:%d:%d:%d|t"):format(XP.SWATCH_H, XP.SWATCH_W,
        C(r), C(g), C(b))
end

-- Farbprobe des Golds: dieselbe Fläche wie auf der Leiste (Blizzards Questfarbe), blass mit derselben Deckkraft über dem
-- dunklen Grund
function XP.GoldSwatch(alpha)
    local r, g, b = Core.Style.Color("normal")
    return XP.Swatch(nil, r, g, b, type(alpha) == "number" and alpha or 1)
end
local GoldSwatch = XP.GoldSwatch

-- „nach Abgabe …“ einer Summe (Höchststufe bzw. Stufengrenze eines Probe-Kontos über Core.XPLevelCap: dort bleibt die
-- Stufe stehen, die Erfahrung wird gesammelt) → Text oder nil, geschätzt
local function AfterText(gain, level, xp, max)
    local cap, trial = Core.XPLevelCap()
    local lvl, frac, estimated, top = Core.LevelAfterXP(gain, level, xp, max, cap)
    if not lvl then return nil, false end
    if top then return (trial and L.XPP_AFTER_CAP or L.XPP_AFTER_MAX):format(lvl), estimated end
    local text = L.XPP_AFTER:format(lvl, Core.Percent(math.floor(frac * 100)))
    if estimated then text = text .. L.XPP_GUESS end
    return text, estimated
end

-- eine Summe: Farbprobe und Name links, Menge rechts, darunter eingerückt „nach Abgabe …“ → geschätzt
local function AddSum(lines, swatch, fmt, count, gain, level, xp, max)
    lines[#lines + 1] = { swatch .. " " .. fmt:format(count), "highlight", right = L.XPP_AMOUNT:format(Core.FormatNumber(gain)) }
    local after, estimated = AfterText(gain, level, xp, max)
    if after then lines[#lines + 1] = { after, "highlight", indent = true } end
    return estimated
end

-- Erholung, wie ezQuest sie auf der Leiste zeichnet (eine Rechnung über XP.Segments). Blizzard: GetRestState() → 1
-- erholt (Füllung Fill-Rested), sonst normal (Fill-Experience); Vorrat GetXPExhaustion(). Der Streifen beginnt nach den
-- fertigen Quests (done, all: Standard die letzte Summe) und reicht höchstens bis zum Rand.
-- → erholt, Streifen (nil | "tick" endet auf dieser Stufe | "over" reicht über die Stufe hinaus | "next" beginnt nach der
-- Abgabe erst auf der nächsten Stufe), Blizzards Marke steht woanders (fertige Quests und Blizzard zeigt sie:
-- hideAtBarEdge, 1 % bis 99 %; Shared/ExpBar.lua ExhaustionTickMixin:UpdateTickPosition)
function XP.RestInfo(done, all)
    local state = Num(Core.Call(rawget(_G, "GetRestState")))
    local left = RestLeft()
    local xp = Num(Core.Call(rawget(_G, "UnitXP"), "player"))
    local max = Num(Core.Call(rawget(_G, "UnitXPMax"), "player"))
    if done == nil then done = sums and sums.done or 0 end
    if all == nil then all = sums and sums.all or 0 end
    local band, tickElsewhere
    local seg = XP.Segments(xp, max, done, all, left)
    if seg.rest then
        band = seg.rest[2] > max and "over" or "tick"
    elseif left and left > 0 and xp and max and max > 0 and done > 0 and xp + done >= max then
        band = "next"
    end
    if band and done > 0 then
        local blizz = (xp + left) / max
        tickElsewhere = blizz >= 0.01 and blizz <= 0.99
    end
    return state == 1, band, tickElsewhere == true
end
local RestInfo = XP.RestInfo

XP.REST_TEXT = { tick = "XPP_LEG_REST", over = "XPP_LEG_REST", next = "XPP_LEG_REST_NEXT" }

-- Legende der Leiste in der Reihenfolge auf der Leiste: deine Erfahrung (Blizzards Füllung je nach Erholung),
-- ezQuests Gold kräftig, Erholung ab dort (Blizzards Farbe), Blizzards Marke (wenn sie woanders steht), Gold blass
function XP.Legend()
    local done = sums and sums.done or 0
    local rested, band, tickElsewhere = RestInfo(done)
    local out = { { L.XPP_LEGEND_HEAD, "normal", gap = true } }
    if rested then
        out[#out + 1] = { XP.Swatch(XP.ATLAS_RESTED) .. " " .. L.XPP_LEG_XP_RESTED, "highlight" }
    else
        out[#out + 1] = { XP.Swatch(XP.ATLAS) .. " " .. L.XPP_LEG_XP, "highlight" }
    end
    out[#out + 1] = { GoldSwatch(XP.ALPHA_DONE) .. " " .. L.XPP_LEG_DONE, "highlight" }
    if band then
        local text = L[XP.REST_TEXT[band]]
        if band ~= "next" and done > 0 then text = L.XPP_LEG_REST_AFTER end
        if band == "over" then text = text .. L.XPP_LEG_REST_OVER end
        out[#out + 1] = { XP.Swatch(XP.ATLAS_PREDICTION) .. " " .. text, "highlight" }
    end
    -- Blizzards Marke: wandert sie mit (XP.TickTarget), steht sie am Ende des Blaus; sonst am Stand ohne Abgabe
    local target = XP.TickTarget()
    if XP.TickPending() then target = nil end   -- im Kampf steht sie noch auf Blizzards Lage
    local tickText
    if type(target) == "number" then
        if target >= 0.01 and target <= 0.99 then tickText = L.XPP_LEG_TICK_MOVED end
    elseif target == nil and tickElsewhere then
        tickText = L.XPP_LEG_TICK
    end
    if tickText then
        out[#out + 1] = { ("|A:%s:%d:%d|a"):format(XP.ATLAS_PIP, XP.SWATCH_H, XP.PIP_W) .. " " .. tickText, "highlight" }
    end
    out[#out + 1] = { GoldSwatch(XP.ALPHA_ALL) .. " " .. L.XPP_LEG_ALL, "highlight" }
    return out
end

-- Zeilen des Tooltips → { { text, rolle [, right = Text] [, indent = true] [, gap = true] } … }, leer, wenn die Vorschau
-- aus ist oder keine Erfahrung kommt (gap: Abstand davor; indent: eingerückt unter der Zeile davor)
function XP.Lines()
    local lines = {}
    if not XP.Active() then return lines end
    if not sums then sums = Core.QuestLogXP() end
    local s = sums
    if not s then return lines end
    lines[#lines + 1] = { L.XPP_HEADER, "normal", gap = true }
    if s.allCount == 0 then
        lines[#lines + 1] = { L.XPP_EMPTY, "gray" }
        return lines
    end
    if s.allCount == s.unknown then
        lines[#lines + 1] = { L.XPP_NONE, "gray" }
        return lines
    end
    local level = Core.PlayerLevel()
    local xp = Num(Core.Call(rawget(_G, "UnitXP"), "player"))
    local max = Num(Core.Call(rawget(_G, "UnitXPMax"), "player"))
    local guess = false
    if s.done > 0 then
        guess = AddSum(lines, GoldSwatch(XP.ALPHA_DONE), L.XPP_DONE, s.doneCount, s.done, level, xp, max) or guess
    else
        lines[#lines + 1] = { GoldSwatch(XP.ALPHA_DONE) .. " " .. L.XPP_DONE_NONE, "highlight" }
    end
    guess = AddSum(lines, GoldSwatch(XP.ALPHA_ALL), L.XPP_ALL, s.allCount, s.all, level, xp, max) or guess
    if s.unknown > 0 then lines[#lines + 1] = { Core.Plural(s.unknown, L.XPP_UNKNOWN_ONE, L.XPP_UNKNOWN_MANY), "gray" } end
    if guess then lines[#lines + 1] = { L.XPP_GUESS_TIP, "gray" } end
    for _, line in ipairs(XP.Legend()) do lines[#lines + 1] = line end
    return lines
end

-- Zeilen an einen offenen Tooltip hängen (Erholungs-Marke: Blizzards Tooltip steht schon); breit, damit auch Blizzards
-- Zeilen darüber nicht eng umbrechen
function XP.AddToTip(tooltip)
    if type(tooltip) ~= "table" or type(tooltip.AddLine) ~= "function" then return false end
    local lines = XP.Lines()
    if #lines == 0 then return false end
    Core.TipWide(tooltip)
    for _, line in ipairs(lines) do
        if line.gap and Core.Tooltip and Core.Tooltip.Gap then Core.Tooltip.Gap(tooltip) end
        local r, g, b = Core.Style.Color(line[2])
        local text = line.indent and (XP.INDENT .. line[1]) or line[1]
        if line.right and type(tooltip.AddDoubleLine) == "function" then
            local hr, hg, hb = Core.Style.Color("highlight")
            tooltip:AddDoubleLine(text, line.right, r, g, b, hr, hg, hb)
        else
            tooltip:AddLine(line.right and (text .. "  " .. line.right) or text, r, g, b, true)
        end
    end
    tooltip:Show()
    return true
end

-- Maus über Blizzards Leiste. Blizzards ExpBarMixin:OnEnter hat GameTooltip gerade gefüllt (EP x / y, Ruhezustand;
-- Shared/ExpBar.lua über ExhaustionTick:ExhaustionToolTipText, Mainline/ExpBarOverrides.lua) – dann nur anhängen, nie
-- SetOwner (das leerte Blizzards Zeilen; Gegenprüfung I1). Nur ohne Blizzards Tooltip (GetRestState ohne Angabe) ein
-- eigener über der Leiste. Ausblenden: Blizzards ExpBarMixin:OnLeave (GameTooltip:Hide).
function XP.ShowTip(bar)
    if #XP.Lines() == 0 then return false end
    if not GameTooltip:IsShown() then GameTooltip:SetOwner(bar, "ANCHOR_TOP") end
    return XP.AddToTip(GameTooltip)
end

---------------------------------------------------------------------------
-- Status (/ezq status)
---------------------------------------------------------------------------

function XP.StatusLine()
    if not ns.Enabled("xpPreview") then return nil end
    local blocked = Core.XPBlocked()
    if blocked then return L.XPP_STATUS_BLOCKED end
    if #order == 0 then return L.XPP_STATUS_NOBAR end
    local visible = false
    for _, frame in ipairs(order) do
        local ok, shown = pcall(frame.IsVisible, frame)
        if ok and shown == true then visible = true end
    end
    if not visible then return L.XPP_STATUS_HIDDEN end
    local s = sums or Core.QuestLogXP()
    if s and s.allCount == 0 then return L.XPP_STATUS_EMPTY end
    if not s or s.allCount == s.unknown then return L.XPP_STATUS_NONE end
    return L.XPP_STATUS:format(Core.FormatNumber(s.done), Core.FormatNumber(s.all))
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------

ns.OnReady(function()
    ns.Try("XPPreviewHook", XP.Refresh)
    local refresh = ns.Throttle(function() ns.Try("XPPreview", XP.Refresh) end, 0.3)
    for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "QUEST_ACCEPTED", "QUEST_REMOVED",
        "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "ENABLE_XP_GAIN", "DISABLE_XP_GAIN", "PLAYER_ENTERING_WORLD" }) do
        ns.On(event, function() if ns.Enabled("xpPreview") then refresh() end end)
    end
end)

ns.OnSettingChanged(function(key)
    if key == "xpPreview" or key == "xpTickFollow" then ns.Try("XPPreview", XP.Refresh) end
end)
