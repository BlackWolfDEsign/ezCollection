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
    an Leiste und Erholungs-Marke (ExhaustionTick; die Zeilen kommen unter Blizzards Tooltip). Nichts wird verschoben,
    nichts in Blizzards Tabellen geschrieben; gezeichnet wird mit Blizzards Füllung der Leiste (Atlas
    UI-HUD-ExperienceBar-Fill-Experience, ExpBarOverrides.lua; Ausschnitt über Core.AtlasTexCoord) in Blizzards Questfarbe
    (NORMAL_FONT_COLOR über Core.Style). Läuft auch im Kampf: nur eigene Texturen.
    Fremde Addons (Leitlinie 9): Die Vorschau ist ein Kind von Blizzards Leiste. Blendet ein Addon die Leiste aus oder
    ersetzt sie durch eine eigene, ist die Vorschau mit weg (kein zweiter Balken daneben); versetzt es Blizzards Leiste,
    wandert die Vorschau mit. /ezq status nennt den Fall „Leiste nicht zu sehen“.
]]

local XP = {}
ns.XPPreview = XP

local Num = Core.Num

XP.ATLAS = "UI-HUD-ExperienceBar-Fill-Experience"
XP.ALPHA_DONE = 0.8     -- fertige Quests: hell
XP.ALPHA_ALL = 0.35     -- alle Quests im Log: blass
XP.MIN_WIDTH = 0.5      -- schmalere Stücke (Bildpunkte) bleiben verborgen

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

local function Texture(frame, sub, alpha)
    local tex = frame:CreateTexture(nil, "ARTWORK", nil, sub)
    local ok, set = pcall(tex.SetAtlas, tex, XP.ATLAS)
    local r, g, b = Core.Style.Color("normal")
    if not ok or set == false then
        tex:SetColorTexture(r, g, b)          -- Atlas unbekannt: Blizzards Questfarbe als Fläche
    else
        tex:SetDesaturated(true)
        tex:SetVertexColor(r, g, b)
    end
    tex:SetAlpha(alpha)
    tex:Hide()
    return tex
end

-- ein Stück der Vorschau: ab dem Stand der Leiste bis zum Stand nach gain weiteren EP (höchstens bis zum Ende)
local function Place(frame, tex, xp, max, gain, width)
    local from = math.min(1, math.max(0, xp / max))
    local to = math.min(1, (xp + (gain or 0)) / max)
    local w = (to - from) * width
    if not gain or gain <= 0 or w < XP.MIN_WIDTH then
        tex:Hide()
        return
    end
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", frame, "TOPLEFT", from * width, 0)
    tex:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", from * width, 0)
    tex:SetWidth(w)
    -- nur dieser Ausschnitt der Füllung: SetTexCoord rechnet gegen die ganze Datei, darum über den Bereich des Atlas
    -- (Core.AtlasTexCoord, Gegenprüfung I1); ohne Angaben des Clients bleibt das ganze Atlas-Stück gestreckt
    local l, r, t, b = Core.AtlasTexCoord(XP.ATLAS, from, to, 0, 1)
    if l then tex:SetTexCoord(l, r, t, b) end
    tex:Show()
end

-- Lage der Vorschau auf einer Leiste neu setzen (nach Update der Leiste, neuer Größe, neuer Summe)
function XP.Layout(frame)
    if type(frame) ~= "table" or not frame.all then return end
    local okW, width = pcall(frame.GetWidth, frame)
    width = okW and Num(width) or nil
    local xp = Num(Core.Call(rawget(_G, "UnitXP"), "player"))
    local max = Num(Core.Call(rawget(_G, "UnitXPMax"), "player"))
    if not (sums and width and width > 0 and xp and max and max > 0) or not XP.Active() then
        frame.all:Hide()
        frame.done:Hide()
        return
    end
    Place(frame, frame.all, xp, max, sums.all, width)
    Place(frame, frame.done, xp, max, sums.done, width)
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
    frame.all = Texture(frame, 1, XP.ALPHA_ALL)
    frame.done = Texture(frame, 2, XP.ALPHA_DONE)
    frame:SetScript("OnSizeChanged", function(self) ns.Try("XPPreviewLayout", XP.Layout, self) end)
    frame:SetScript("OnShow", function(self) ns.Try("XPPreviewLayout", XP.Layout, self) end)
    overlays[bar] = frame
    order[#order + 1] = frame
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
XP.ATLAS_RESTED = "UI-HUD-ExperienceBar-Fill-Rested"
XP.ATLAS_PREDICTION = "UI-HUD-ExperienceBar-Fill-Prediction"
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

local function GoldSwatch(alpha)
    local r, g, b = Core.Style.Color("normal")
    return XP.Swatch(nil, r, g, b, alpha)
end

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

-- Blizzards Erholung: GetRestState() → 1 erholt (Füllung Fill-Rested), sonst normal (Fill-Experience).
-- Streifen (ExhaustionLevelFillBar, Shared/ExpBar.lua ExhaustionTickMixin:UpdateTickPosition): nur mit
-- GetXPExhaustion() > 0; reicht die Erholung über die Stufe hinaus, zeigt Blizzard ihn nur mit
-- ShouldRestedXpBarDisplayWhenOverflowing() – dann bis zum Rand und ohne Marke (ab 99 %). → erholt, Streifen
-- (nil | "tick" bis zur Marke | "over" über die Stufe hinaus)
function XP.RestInfo()
    local state = Num(Core.Call(rawget(_G, "GetRestState")))
    local left = Num(Core.Call(rawget(_G, "GetXPExhaustion")))
    local band
    if left and left > 0 then
        local xp = Num(Core.Call(rawget(_G, "UnitXP"), "player"))
        local max = Num(Core.Call(rawget(_G, "UnitXPMax"), "player"))
        local ratio = (xp and max and max > 0) and (xp + left) / max or 0
        if ratio > 1 then
            if Core.Call(rawget(_G, "ShouldRestedXpBarDisplayWhenOverflowing")) == true then band = "over" end
        elseif ratio > 0.99 then
            band = "over"
        else
            band = "tick"
        end
    end
    return state == 1, band
end
local RestInfo = XP.RestInfo

-- Legende der Leiste: deine Erfahrung (Blizzards Füllung je nach Erholung), Streifen bis zur Marke, ezQuests Gold
function XP.Legend()
    local rested, band = RestInfo()
    local out = { { L.XPP_LEGEND_HEAD, "normal", gap = true } }
    if rested then
        out[#out + 1] = { XP.Swatch(XP.ATLAS_RESTED) .. " " .. L.XPP_LEG_XP_RESTED, "highlight" }
    else
        out[#out + 1] = { XP.Swatch(XP.ATLAS) .. " " .. L.XPP_LEG_XP, "highlight" }
    end
    if band then
        out[#out + 1] = { XP.Swatch(XP.ATLAS_PREDICTION) .. " " .. (band == "over" and L.XPP_LEG_REST_OVER or L.XPP_LEG_REST),
            "highlight" }
    end
    out[#out + 1] = { GoldSwatch(XP.ALPHA_DONE) .. " " .. L.XPP_LEG_DONE, "highlight" }
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
    if key == "xpPreview" then ns.Try("XPPreview", XP.Refresh) end
end)
