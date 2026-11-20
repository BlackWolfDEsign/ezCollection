local ADDON, ns = ...

--[[
    Neue Forever-Quests türkis hinterlegen: Questfenster (Details, Fortschritt,
    Belohnung), Details im Questlog, Zeilen der Questliste und der NPC-Listen (Levels.lua ruft Tint.Row).
    Eine eigene Textur über Blizzards Hintergrund; gemerkt in einer eigenen Tabelle, nie in Blizzards Rahmen.
    Läuft schon ein Addon, das neue Quests färbt (ezCore.WhoHandles("questTint")), hält sich ezQuest zurück.
]]

local Core = ezCore
local Tint = {}
ns.Tint = Tint
-- Farbenblind-Hilfe (EC-47): Ist in ezCore „Zeichen am Leuchten“ an (Core.MarksOn), steht zusätzlich zur
-- Tönung ein Zeichen oben rechts: ezCores grünes Zeichen („neu dazu“, Core.GLOW_COLORS); die Tönung allein bleibt
-- der Standard. „+“ nur, falls ezCore keines führt.
local green = type(Core.GLOW_COLORS) == "table" and Core.GLOW_COLORS.green
Tint.MARK = type(green) == "table" and type(green.mark) == "string" and green.mark or "+"

-- Türkis wie das Forever-Logo: eigener Ton, weil Blizzard für Forever-Quests keine Farbe hat (Design-System 2.5 kennt
-- als eigene Palette nur ezCores Leuchtfarben). Begründete Ausnahme nach der Entscheidung des Nutzers vom 16.11.2026
-- (vorläufig nach Empfehlung): eingetragen in FARBE_AUSNAHMEN von tools/design.lua (Ton 40d9cc = Tint.COLOR, zwei CreateColor);
-- ezQuest steht in FARBE_STRENG. Die beiden CreateColor in Paint sind nur die Enden des Verlaufs in diesem Ton
-- (SetGradient verlangt Farbobjekte) – ein weiterer eigener Ton wäre rot.
Tint.COLOR = { 0.25, 0.85, 0.80 }

local overlays = setmetatable({}, { __mode = "k" })   -- [Blizzard-Rahmen] = eigene Textur
local marks = setmetatable({}, { __mode = "k" })      -- [Blizzard-Rahmen] = eigenes Zeichen (Farbenblind-Hilfe)

-- Zeichen zusätzlich zur Farbe? Der Schalter gehört ezCore (comfort.glowMarks); leitet seit ezCore 1.12.0 auf
-- Core.MarksOn weiter. Ein älteres ezCore ohne den Helfer: nein.
function Tint.MarksEnabled()
    return type(Core.MarksOn) == "function" and Core.MarksOn() == true
end

-- Zeichen an frame zeigen oder verstecken; legt den Text erst an, wenn er gebraucht wird. Rückgabe: gezeigt?
local function ApplyMark(frame, show)
    show = show and Tint.MarksEnabled() or false
    local mark = marks[frame]
    if not mark then
        if not show or not frame.CreateFontString then return false end
        mark = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        mark:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -3)
        mark:SetText(Tint.MARK)
        mark:SetTextColor(Tint.COLOR[1], Tint.COLOR[2], Tint.COLOR[3])
        marks[frame] = mark
    end
    mark:SetShown(show)
    return show
end

-- Verlauf von from nach to (Deckkraft). Ohne SetGradient: gleichmäßige Fläche mit dem Mittelwert.
local function Paint(tex, orientation, from, to)
    local r, g, b = Tint.COLOR[1], Tint.COLOR[2], Tint.COLOR[3]
    tex:SetColorTexture(1, 1, 1, 1)
    if CreateColor and tex.SetGradient then
        local ok = pcall(tex.SetGradient, tex, orientation, CreateColor(r, g, b, from), CreateColor(r, g, b, to))
        if ok then return end
    end
    tex:SetColorTexture(r, g, b, (from + to) / 2)
end

function Tint.Active(questID)
    return ns.Enabled("tintNew") and ns.IsForeverQuest(questID) and not ns.OtherHandles("questTint")
end

-- Textur an frame zeigen oder verstecken; legt sie erst an, wenn sie gebraucht wird. Rückgabe: gezeigt?
local function Apply(frame, questID, anchor, orientation, from, to)
    if type(frame) ~= "table" or not frame.CreateTexture then return false end
    local show = Tint.Active(questID) and true or false
    ApplyMark(frame, show)
    local tex = overlays[frame]
    if not tex then
        if not show then return false end
        tex = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
        tex:SetAllPoints(anchor or frame)
        Paint(tex, orientation, from, to)
        overlays[frame] = tex
    end
    tex:SetShown(show)
    return show
end

-- Fläche (Hintergrund eines Panels): unten kräftiger, nach oben zart. anchor: Blizzards Hintergrund-Textur.
function Tint.Panel(frame, questID, anchor)
    return Apply(frame, questID, anchor, "VERTICAL", 0.32, 0.06)
end

-- Zeile (Knopf in der Questliste oder im NPC-Dialog): von links nach rechts auslaufend.
function Tint.Row(button, questID)
    return Apply(button, questID, nil, "HORIZONTAL", 0.30, 0)
end

-- Test-Abfrage: Zeigt ezQuest an diesem Rahmen gerade die Tönung? Aufrufer sind nur die Prüfungen in Tests/run.lua
-- (Gossip, Begrüßung, Questfenster, Questlog) – die Textur liegt in der privaten Tabelle overlays und ist von außen
-- sonst nicht zu sehen. Als Kandidat für toten Code beurteilt (QUEST-04, 14.11.2026): bleibt, die Tests bauen darauf.
function Tint.Shown(frame)
    local tex = overlays[frame]
    return tex ~= nil and tex:IsShown() == true
end

-- Test-Abfrage wie Tint.Shown: steht am Rahmen gerade das Zeichen der Farbenblind-Hilfe?
function Tint.MarkShown(frame)
    local mark = marks[frame]
    return mark ~= nil and mark:IsShown() == true
end

-- Questfenster: die drei Seiten einer Quest (der Hintergrund heißt bei Blizzard .Bg).
local function HookQuestFrame()
    for _, name in ipairs({ "QuestFrameDetailPanel", "QuestFrameProgressPanel", "QuestFrameRewardPanel" }) do
        local panel = rawget(_G, name)
        if type(panel) == "table" and panel.HookScript then
            panel:HookScript("OnShow", function(self)
                ns.Try("Tint " .. name, function()
                    local questID = GetQuestID and GetQuestID()
                    Tint.Panel(self, questID, self.Bg)
                end)
            end)
        end
    end
end

-- Questlog (in der Weltkarte): Details einer Quest und die Zeilen der Liste.
local function HookQuestLog()
    if type(rawget(_G, "QuestMapFrame_ShowQuestDetails")) == "function" then
        hooksecurefunc("QuestMapFrame_ShowQuestDetails", function(questID)
            ns.Try("Tint QuestLog", function()
                local details = QuestMapFrame and QuestMapFrame.DetailsFrame
                if details then Tint.Panel(details, questID, details.Bg) end
            end)
        end)
    end
    if type(rawget(_G, "QuestLogQuests_Update")) == "function" then
        hooksecurefunc("QuestLogQuests_Update", function()
            ns.Try("Tint QuestList", function()
                local pool = QuestScrollFrame and QuestScrollFrame.titleFramePool
                if not (pool and pool.EnumerateActive) then return end
                for button in pool:EnumerateActive() do Tint.Row(button, button.questID) end
            end)
        end)
    end
end

ns.OnReady(function()
    ns.Try("Tint", HookQuestFrame)
    ns.Try("Tint", HookQuestLog)
end)

-- „Zeichen am Leuchten“ umgelegt (ezCore 1.12.0): an jedem gerade getönten Rahmen das Zeichen sofort nachziehen
Core.Listen("GLOW_MARKS_CHANGED", function()
    for frame, tex in pairs(overlays) do ApplyMark(frame, tex:IsShown() == true) end
end, ADDON)

-- Abgeschaltet: alle Tönungen sofort weg (eingeschaltet wirken sie beim nächsten Öffnen).
ns.OnSettingChanged(function(key)
    if key ~= "tintNew" or ns.Enabled("tintNew") then return end
    for _, tex in pairs(overlays) do tex:Hide() end
    for _, mark in pairs(marks) do mark:Hide() end
end)
