local _, ns = ...
local Core = ezCore

--[[
    Marken auf Gegenstandsknöpfen: grüner Pfeil „besser“, roter Pfeil nach unten „schlechter“ und Gold-Symbol
    „höchster Verkaufswert“. Einen roten Pfeil hat Blizzard in Forever nicht (Quelle geprüft: nur bags-greenarrow);
    der rote ist deshalb der grüne, um 180° gedreht, entsättigt und rot getönt – gleiche Größe, gleiche Ecke.
    Gelber Pfeil „besser, sobald gelernt“ bzw. „… sobald die Stufe reicht“ (Stände „learn“ und „level“, Score.LATER; Paket
    ezgear/lernbar-tragbar, Entscheidung des Nutzers vom 23.11.2026 „Vergleich + Hinweis (Empfohlen)“: „Pfeil gelb statt
    grün“; Stufe: 24.11.2026): derselbe Pfeil, entsättigt und gelb getönt.
    Blizzards eigene Atlanten: der Pfeil ist der des (in Forever unbenutzten) UpgradeIcon am Taschenplatz,
    gleiche Größe, Ecke oben links, Ebene OVERLAY 1. ezGear legt eigene Texturen an und fasst Blizzards
    Regionen nicht an (taint-sicher, keine Werte in Blizzards Tabellen).

    Läuft ezBag, zeichnet ezBag den Pfeil an seinen Plätzen selbst (Bags.lua meldet ihn dort an);
    Marks dient dann für Questbelohnung, Charakterfenster und Knöpfe anderer Module (API.SetUpgradeIcon).

    Farbenblind-Hilfe (EC-47): Ist ezCores Schalter „Zeichen am Leuchten“ an (Core.Glow.MarksEnabled), steht neben
    jeder Marke zusätzlich zur Farbe ein Zeichen. Die Zeichen kommen aus ezCores Liste Core.GLOW_COLORS (mark der
    Farbe green, red, gold – heute „+“, „!“, „>“), damit Rot in ezGear, ezMail und am Leuchten dasselbe Zeichen hat.
    Gelesen werden Schalter und Zeichen bei jedem Zeichnen der Marke.
]]

local Marks = {}
ns.Marks = Marks

Marks.ARROW_ATLAS = "bags-greenarrow"
Marks.ARROW_FILE = "Interface\\Buttons\\UI-MicroStream-Green"     -- Ersatz, falls der Atlas fehlt (Spitze nach oben gedreht)
Marks.COIN_ATLASES = { "bags-junkcoin", "auctionhouse-icon-coin-gold", "coin-gold" }
Marks.COIN_FILE = "Interface\\MoneyFrame\\UI-GoldIcon"

Marks.DOWN_COLOR = { 1, 0.22, 0.22 }
Marks.LEARN_COLOR = { 1, 0.82, 0 }      -- Blizzards Gelb (NORMAL_FONT_COLOR)

local arrows = setmetatable({}, { __mode = "k" })
local downs = setmetatable({}, { __mode = "k" })
local learns = setmetatable({}, { __mode = "k" })
local coins = setmetatable({}, { __mode = "k" })

-- Zeichen zusätzlich zur Farbe (EC-47): Farbe in ezCores Liste (glow), Textfarbe und Lage neben der Marke je Art.
-- Das Zeichen selbst steht nur in Core.GLOW_COLORS (Marks.SignText). Der gelbe Pfeil trägt das Zeichen von Orange
-- („?“ – etwas fehlt noch: die Fertigkeit), in Gelb.
Marks.SIGNS = {
    arrow = { glow = "green", color = { 0.1, 1, 0.1 }, point = "LEFT", relPoint = "RIGHT", x = -2 },
    down = { glow = "red", color = Marks.DOWN_COLOR, point = "LEFT", relPoint = "RIGHT", x = -2 },
    learn = { glow = "orange", color = Marks.LEARN_COLOR, point = "LEFT", relPoint = "RIGHT", x = -2 },
    coin = { glow = "gold", color = { 1, 0.82, 0 }, point = "RIGHT", relPoint = "LEFT", x = 2 },
}

-- Zeichen einer Art (kind = "arrow" | "down" | "learn" | "coin") aus Core.GLOW_COLORS oder nil, wenn ezCore keines führt
function Marks.SignText(kind)
    local spec = Marks.SIGNS[kind]
    local colors = Core.GLOW_COLORS
    local entry = spec and type(colors) == "table" and colors[spec.glow]
    local mark = type(entry) == "table" and entry.mark
    return type(mark) == "string" and mark ~= "" and mark or nil
end
local signs = { arrow = setmetatable({}, { __mode = "k" }), down = setmetatable({}, { __mode = "k" }),
    learn = setmetatable({}, { __mode = "k" }), coin = setmetatable({}, { __mode = "k" }) }

-- ezCores Schalter „Zeichen am Leuchten“ (Farbenblind-Hilfe); leitet seit ezCore 1.12.0 auf Core.MarksOn weiter
-- (ein Ort für die Abfrage). Ein älteres ezCore ohne den Helfer: aus.
function Marks.SignsEnabled()
    return type(Core.MarksOn) == "function" and Core.MarksOn() == true
end

-- Zeichen neben der Marke tex zeigen oder verstecken (nur mit Schalter, nur bei sichtbarer Marke)
local function SetSign(kind, button, tex, shown)
    local store, spec = signs[kind], Marks.SIGNS[kind]
    local fs = store[button]
    local text = Marks.SignText(kind)
    local want = shown == true and text ~= nil and Marks.SignsEnabled()
    if not fs then
        if not want or not button.CreateFontString then return end
        fs = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        store[button] = fs
    end
    if want then
        fs:SetText(text)
        if fs.SetTextColor then fs:SetTextColor(spec.color[1], spec.color[2], spec.color[3]) end
        fs:ClearAllPoints()
        fs:SetPoint(spec.point, tex, spec.relPoint, spec.x, 0)
    end
    fs:SetShown(want)
end

-- Zeichen einer Marke am Knopf (kind = "arrow" | "down" | "coin") oder nil, wenn keines steht – für Tests und /dump
function Marks.SignShown(button, kind)
    local fs = signs[kind] and signs[kind][button]
    if not (fs and fs:IsShown()) then return nil end
    return fs:GetText()
end

-- Graues Zeichen der Stände ohne Pfeil (Score.Verdict; "noslot" = kein bewerteter Platz: Hemd, Wappenrock). Eine Tabelle für
-- alle Listen, die den Stand zeigen (API.StatusSign; ezAuction, ezCraft). „<“ nur, solange der rote Pfeil aus ist.
Marks.STATUS_SIGNS = { same = "=", equipped = "=", nostats = "–", unusable = "–", noslot = "–", pending = "…" }
Marks.STATUS_WORSE = "<"

function Marks.StatusSign(kind)
    if kind == "worse" then return not ns.Enabled("downArrows") and Marks.STATUS_WORSE or nil end
    return Marks.STATUS_SIGNS[kind or "noslot"]
end

-- Größe der Ersatzbilder ohne Atlas: Symbol in einer Zeile (Core.Style.ICON.line, 16 wie Blizzards Menüsymbole;
-- Design-System 2.3). Die Münze war 14 und ist jetzt so groß wie die Pfeile.
local function LineSize() return Core.Style.IconSize("line") end

local function NewArrow(button)
    local tex = button:CreateTexture(nil, "OVERLAY", nil, 1)
    if Core.AtlasExists(Marks.ARROW_ATLAS) then
        tex:SetAtlas(Marks.ARROW_ATLAS, true)
    else
        tex:SetTexture(Marks.ARROW_FILE)
        tex:SetTexCoord(0, 1, 1, 0)
        tex:SetSize(LineSize(), LineSize())
    end
    tex:Hide()
    return tex
end

-- Roter Pfeil nach unten: derselbe Atlas, gedreht (SetRotation), entsättigt und rot getönt
local function NewDown(button)
    local tex = button:CreateTexture(nil, "OVERLAY", nil, 1)
    if Core.AtlasExists(Marks.ARROW_ATLAS) then
        tex:SetAtlas(Marks.ARROW_ATLAS, true)
        if tex.SetRotation then tex:SetRotation(math.pi) end
    else
        tex:SetTexture(Marks.ARROW_FILE)   -- zeigt von sich aus nach unten
        tex:SetSize(LineSize(), LineSize())
    end
    if tex.SetDesaturated then tex:SetDesaturated(true) end
    tex:SetVertexColor(Marks.DOWN_COLOR[1], Marks.DOWN_COLOR[2], Marks.DOWN_COLOR[3])
    tex:Hide()
    return tex
end

local function NewCoin(button)
    local tex = button:CreateTexture(nil, "OVERLAY", nil, 1)
    local atlas = Core.FirstAtlas(Marks.COIN_ATLASES)
    if atlas then
        tex:SetAtlas(atlas, true)
    else
        tex:SetTexture(Marks.COIN_FILE)
        tex:SetSize(LineSize(), LineSize())
    end
    tex:Hide()
    return tex
end

-- Pfeil zeigen/verstecken; anchor = Region, an deren Ecke er sitzt (Standard: der Knopf selbst)
function Marks.ShowArrow(button, shown, anchor)
    if type(button) ~= "table" or not button.CreateTexture then return end
    local tex = arrows[button]
    if not tex then
        if not shown then return end
        tex = NewArrow(button)
        arrows[button] = tex
    end
    if shown then
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", anchor or button, "TOPLEFT", 0, 0)
    end
    tex:SetShown(shown == true)
    SetSign("arrow", button, tex, shown)
end

function Marks.ArrowShown(button)
    local tex = arrows[button]
    return tex ~= nil and tex:IsShown() == true
end

-- Roter Pfeil nach unten zeigen/verstecken; gleiche Ecke wie der grüne
function Marks.ShowDown(button, shown, anchor)
    if type(button) ~= "table" or not button.CreateTexture then return end
    local tex = downs[button]
    if not tex then
        if not shown then return end
        tex = NewDown(button)
        downs[button] = tex
    end
    if shown then
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", anchor or button, "TOPLEFT", 0, 0)
    end
    tex:SetShown(shown == true)
    SetSign("down", button, tex, shown)
end

function Marks.DownShown(button)
    local tex = downs[button]
    return tex ~= nil and tex:IsShown() == true
end

-- Gelber Pfeil „besser, sobald gelernt“: derselbe Pfeil wie der grüne, entsättigt und gelb getönt
local function NewLearn(button)
    local tex = NewArrow(button)
    if tex.SetDesaturated then tex:SetDesaturated(true) end
    tex:SetVertexColor(Marks.LEARN_COLOR[1], Marks.LEARN_COLOR[2], Marks.LEARN_COLOR[3])
    return tex
end

-- Gelben Pfeil zeigen/verstecken; gleiche Ecke wie der grüne
function Marks.ShowLearn(button, shown, anchor)
    if type(button) ~= "table" or not button.CreateTexture then return end
    local tex = learns[button]
    if not tex then
        if not shown then return end
        tex = NewLearn(button)
        learns[button] = tex
    end
    if shown then
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", anchor or button, "TOPLEFT", 0, 0)
    end
    tex:SetShown(shown == true)
    SetSign("learn", button, tex, shown)
end

function Marks.LearnShown(button)
    local tex = learns[button]
    return tex ~= nil and tex:IsShown() == true
end

-- Alle Pfeile weg (Gold-Symbol bleibt)
function Marks.ClearArrows(button)
    Marks.ShowArrow(button, false)
    Marks.ShowDown(button, false)
    Marks.ShowLearn(button, false)
end

-- Gold-Symbol oben rechts
function Marks.SetValue(button, shown, anchor)
    if type(button) ~= "table" or not button.CreateTexture then return end
    local tex = coins[button]
    if not tex then
        if not shown then return end
        tex = NewCoin(button)
        coins[button] = tex
    end
    if shown then
        tex:ClearAllPoints()
        tex:SetPoint("TOPRIGHT", anchor or button, "TOPRIGHT", 0, 0)
    end
    tex:SetShown(shown == true)
    SetSign("coin", button, tex, shown)
end

function Marks.ValueShown(button)
    local tex = coins[button]
    return tex ~= nil and tex:IsShown() == true
end

-- Dieselben Bilder als Symbol im Text (Tooltip-Zeilen und Erklärblasen erklären so, was Pfeil und Münze heißen)
function Marks.ArrowIcon(size)
    size = size or 14
    if Core.AtlasExists(Marks.ARROW_ATLAS) then return ("|A:%s:%d:%d|a"):format(Marks.ARROW_ATLAS, size, size) end
    return ("|T%s:%d:%d:0:0:16:16:0:16:16:0|t"):format(Marks.ARROW_FILE, size, size)   -- Spitze nach oben
end

-- Der gelbe Pfeil als Symbol im Text. Im Text lässt sich Blizzards grüner Pfeil nicht entsättigen (Markup kennt nur
-- die Tönung, und Gelb über Grün bleibt grün – Review vom 23.11.2026); darum Blizzards gelber Pfeil aus den klassischen
-- Knopf-Dateien (dieselbe Datei nutzen ezPanel und ezCores Zauberbuch).
Marks.LEARN_ICON_FILE = "Interface\\Buttons\\Arrow-Up-Up"
function Marks.LearnIcon(size)
    size = size or 14
    return ("|T%s:%d:%d|t"):format(Marks.LEARN_ICON_FILE, size, size)
end

function Marks.CoinIcon(size)
    size = size or 14
    local atlas = Core.FirstAtlas(Marks.COIN_ATLASES)
    if atlas then return ("|A:%s:%d:%d|a"):format(atlas, size, size) end
    return ("|T%s:%d:%d|t"):format(Marks.COIN_FILE, size, size)
end

---------------------------------------------------------------------------
-- Pfeil nach Bewertung; fehlen Daten, wird es kurz darauf noch einmal versucht.
---------------------------------------------------------------------------

local pending = setmetatable({}, { __mode = "k" })
-- [Knopf] = { link, anchor }: alle Versuche verbraucht und Daten fehlen noch, oder der Pfeil ruht auf unvollständigem
-- Wissen (info.provisional) – die nächste neue Bewertung zeichnet ihn neu
local spent = setmetatable({}, { __mode = "k" })
local MAX_TRIES = 6

local function RetryPending()
    local list = {}
    for button, entry in pairs(pending) do list[button] = entry end
    for button, entry in pairs(list) do
        pending[button] = nil
        Marks.SetUpgrade(button, entry.link, entry.anchor, entry.tries)
    end
end
local retrySoon

local function Retry()
    retrySoon = retrySoon or ns.Throttle(RetryPending, 0.5)
    retrySoon()
end
Marks.RetryPending = RetryPending

-- Marks.SetUpgrade(button, link, anchor) → true/false/nil wie Score.IsUpgrade. Grüner Pfeil, wenn besser; gelber,
-- wenn besser, sobald die Fertigkeit gelernt ist bzw. die Stufe reicht (Score.LATER); roter Pfeil nach unten, wenn
-- schlechter (Schalter downArrows). link = nil leert alle.
function Marks.SetUpgrade(button, link, anchor, tries)
    if type(button) ~= "table" then return nil end
    pending[button], spent[button] = nil, nil
    if type(link) ~= "string" or ns.IsSecret(link) then
        Marks.ClearArrows(button)
        return false
    end
    local kind, info = ns.Score.Check(link)
    if info and info.provisional then spent[button] = { link = link, anchor = anchor } end
    if kind == "pending" then
        tries = (tries or 0) + 1
        if tries <= MAX_TRIES then
            pending[button] = { link = link, anchor = anchor, tries = tries }
            Retry()
        else
            spent[button] = { link = link, anchor = anchor }
        end
        Marks.ClearArrows(button)
        return nil
    end
    Marks.ShowArrow(button, kind == "better", anchor)
    Marks.ShowLearn(button, ns.Score.LATER[kind] == true, anchor)
    Marks.ShowDown(button, kind == "worse" and ns.Enabled("downArrows"), anchor)
    return kind == "better"
end

-- Alle Versuche verbraucht bzw. vorläufig gezeichnet und danach nachgeladen (Score.OnKnowledge meldet SCORES_CHANGED):
-- neu versuchen
function Marks.RetrySpent()
    local list = {}
    for button, entry in pairs(spent) do list[button] = entry end
    for button, entry in pairs(list) do Marks.SetUpgrade(button, entry.link, entry.anchor) end
end

-- Nachgeladene Gegenstände: offene Versuche sofort wiederholen.
ns.OnReady(function()
    ns.On("GET_ITEM_INFO_RECEIVED", function()
        if next(pending) then Retry() end
    end)
    ns.Listen("SCORES_CHANGED", Marks.RetrySpent)
    local K = Core.Knowledge
    if K and type(K.OnReady) == "function" then
        K.OnReady(function(itemID) ns.Try("KnowledgeReady", ns.Score.OnKnowledge, itemID) end)
    end
end)
