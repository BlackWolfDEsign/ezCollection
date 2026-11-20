local _, ns = ...
local Core = ezCore

--[[
    Funkeln an Quest-Gegenständen (Wunsch des Nutzers vom 15.11.2026: „sparkles bei questgegenstände und questobjekte,
    ressourcen und co“). Ein Ort für Aussehen und Regel, ezBag (Tasche, Bank, ezBag-Fenster, Gildenbank) und ezLoot
    (Beutefenster) rufen nur:
      ezCore.API("ezQuest").QuestShine(knopf, art, itemID, link, blizz) → true, wenn der Knopf jetzt funkelt
        art   "bag" (Schalter bagShine) oder "loot" (Schalter lootShine)
        blizz Blizzards Angabe zum Platz: { isQuestItem, questID, isActive } (C_Container.GetContainerItemQuestInfo bzw.
              GetLootSlotInfo), nil, wo es keinen Platz gibt (Gildenbank, ezBag-Fenster eines anderen Charakters)
      Ohne Gegenstand (itemID nil) oder abgeschaltet: das Funkeln am Knopf geht aus.
    Aussehen (Leitlinie 1): Blizzards Glanz neuer Gegenstände aus der Vorlage der Taschenplätze
    (ContainerFrameItemButtonTemplate, Forever-Quelle Blizzard_UIPanels_Game/Mainline/ContainerFrame.xml): Atlas
    „bags-glow-white“ mit additiver Mischung, pulsierend 1 » 0,2 » 1 in je 0,5 s (newitemglowAnim), dazu einmal der
    Blitz „bags-glow-flash“ (flashAnim, 0,6 s) beim Aufleuchten – in Blizzards Quest-Gold getönt. Eigene Texturen am
    Knopf (gemerkt in einer eigenen Tabelle, nie als Feld in Blizzards Rahmen), Ebene OVERLAY 0: unter ezBags Marken
    (OVERLAY 1, auch der Münze „im Auktionshaus mehr wert“) und Blizzards Quest-Rand (OVERLAY 2) – verdeckt nichts.
    Regel: funkelt, solange der Gegenstand noch gebraucht wird – ein offenes Ziel aus dem Quest-Log (ezQuest erkennt
    auch Waren wie Leinenstoff), ein Gegenstand zum Benutzen, ein Quest-Starter oder ein Gegenstand, den Blizzard einer
    aktiven Quest zuordnet; im Beutefenster auch jeder Gegenstand, den Blizzard als Quest-Gegenstand meldet. Ein erfülltes
    Ziel (8/8) funkelt nicht mehr – Blizzards Rand bleibt.
]]

local Shine = {}
ns.Shine = Shine

Shine.ATLAS = "bags-glow-white"
Shine.FLASH_ATLAS = "bags-glow-flash"
Shine.FALLBACK = "Interface\\Buttons\\UI-ActionButton-Border"   -- Client ohne die Atlanten: Blizzards Knopfrand
Shine.COLOR = { 1, 0.82, 0 }      -- Blizzards Gold (NORMAL_FONT_COLOR), wie die Quest-Zeilen im Tooltip
Shine.LOW, Shine.HALF = 0.2, 0.5  -- Pulsieren wie newitemglowAnim
Shine.FLASH = 0.6                 -- Blitz wie flashAnim
Shine.SETTING = { bag = "bagShine", loot = "lootShine" }

local shines = setmetatable({}, { __mode = "k" })   -- [Knopf] = { tex, flash, pulse, blink }

local function HasAtlas(name)
    if type(Core.AtlasExists) == "function" then return Core.AtlasExists(name) == true end
    return false
end

local function Alpha(group, from, to, duration, order, smoothing)
    local a = group:CreateAnimation("Alpha")
    a:SetFromAlpha(from)
    a:SetToAlpha(to)
    a:SetDuration(duration)
    a:SetOrder(order)
    if a.SetSmoothing then a:SetSmoothing(smoothing) end
    return a
end

local function Texture(button, atlas)
    local tex = button:CreateTexture(nil, "OVERLAY", nil, 0)
    if HasAtlas(atlas) and tex.SetAtlas then
        tex:SetAtlas(atlas, true)
    else
        tex:SetTexture(Shine.FALLBACK)
        local w, h = Core.Num(button.GetWidth and button:GetWidth()), Core.Num(button.GetHeight and button:GetHeight())
        if w and h and w > 0 and h > 0 then tex:SetSize(w * 1.6, h * 1.6) end
    end
    tex:SetPoint("CENTER", button, "CENTER", 0, 0)
    if tex.SetBlendMode then tex:SetBlendMode("ADD") end
    tex:SetVertexColor(Shine.COLOR[1], Shine.COLOR[2], Shine.COLOR[3])
    tex:Hide()
    return tex
end

local function Build(button)
    local s = { tex = Texture(button, Shine.ATLAS), flash = Texture(button, Shine.FLASH_ATLAS) }
    s.pulse = s.tex:CreateAnimationGroup()
    s.pulse:SetLooping("REPEAT")
    Alpha(s.pulse, 1, Shine.LOW, Shine.HALF, 1, "NONE")
    Alpha(s.pulse, Shine.LOW, 1, Shine.HALF, 2, "NONE")
    s.blink = s.flash:CreateAnimationGroup()
    if s.blink.SetToFinalAlpha then s.blink:SetToFinalAlpha(true) end
    Alpha(s.blink, 1, 0, Shine.FLASH, 1, "OUT")
    shines[button] = s
    return s
end

-- Funkeln an oder aus. → true, wenn es danach funkelt
function Shine.Set(button, on)
    if type(button) ~= "table" or type(button.CreateTexture) ~= "function" then return false end
    local s = shines[button]
    if not on then
        if s and s.tex:IsShown() then
            s.pulse:Stop()
            s.blink:Stop()
            s.tex:Hide()
            s.flash:Hide()
        end
        return false
    end
    s = s or Build(button)
    if not s.tex:IsShown() then
        s.tex:Show()
        s.flash:Show()
        s.blink:Play()
        s.pulse:Play()
    end
    return true
end

-- Funkelt der Knopf gerade? (Tests, /dump)
function Shine.Shown(button)
    local s = shines[button]
    return s ~= nil and s.tex:IsShown() == true
end

-- Blizzards Angabe zum Platz ohne gesperrte Werte → isQuestItem, questID, isActive
local function Blizz(blizz)
    if type(blizz) ~= "table" or Core.IsSecret(blizz) then return false, nil, false end
    return Core.Plain(blizz.isQuestItem) == true, Core.Num(blizz.questID), Core.Plain(blizz.isActive) == true
end

--[[
    Soll der Gegenstand funkeln? info = ezCore.API("ezQuest").ItemQuest (oder nil), blizz wie oben, art "bag" | "loot".
    → true | false (ohne Rücksicht auf die Schalter)
]]
function Shine.Wanted(info, blizz, kind)
    if type(info) == "table" and info.done == true then return false end   -- Ziel erfüllt: Blizzards Rand genügt
    if type(info) == "table" and (info.starts == true or info.questID ~= nil) then return true end
    local isQuestItem, questID = Blizz(blizz)
    if questID then return true end                       -- startet eine Quest (Blizzards „!“) oder gehört zu einer aktiven
    return kind == "loot" and isQuestItem                 -- Beute: der Client bietet Quest-Gegenstände nur an, wenn du sie brauchst
end

function Shine.Enabled(kind)
    local key = Shine.SETTING[kind]
    return key ~= nil and ns.Enabled(key) == true
end

-- Spiegel des Schalters auf der Seite des Moduls, das zeichnet (Einstellungs-Prüfung vom 19.11.2026, Abschnitt 3:
-- „Quest-Gegenstände im Beutefenster funkeln“ auch bei ezLoot unter „Plündern- und Würfelfenster“). Der Wert bleibt
-- EINER, in ezQuest (SSOT): ezCore.API("ezQuest").ShineEnabled(art) → true | false, .SetShine(art, an) → true, wenn
-- die Art bekannt ist (art "bag" | "loot").
function Shine.SetEnabled(kind, on)
    local key = Shine.SETTING[kind]
    if not key then return false end
    ns.SetSetting(key, on == true)
    return true
end
ns.API.ShineEnabled = Shine.Enabled
ns.API.SetShine = Shine.SetEnabled

-- Schnittstelle für ezBag und ezLoot (siehe Kopf). Fehler fangen die Aufrufer ab (pcall).
function Shine.ForSlot(button, kind, itemID, link, blizz)
    local on = false
    itemID = Core.Num(itemID) or Core.ItemID(link)
    if itemID and Shine.Enabled(kind) then
        local info = ns.Items and ns.Items.Get(itemID, link) or nil
        on = Shine.Wanted(info, blizz, kind)
    end
    return Shine.Set(button, on)
end
ns.API.QuestShine = Shine.ForSlot
