local ADDON, ns = ...
local Core = ezCore

--[[
    Rezeptliste etwas breiter (Nutzer am 24.11.2026, wörtlich: „die rezept seite/leiste etwas breiter“; vorher schon „oder
    ggf fenster etwas verbreitern“). Schalter rowWide, ab Werk an.

    Maße laut Forever-Quelle (Gethe/wow-ui-source, Zweig forever): Berufefenster 673 (Camelot/Blizzard_ProfessionsFrame.xml),
    Rezeptliste 304 (Camelot/Blizzard_ProfessionsCrafting.lua, OverrideArt), Hintergrund der Seite 665
    (Profession-Background-Template2, useAtlasSize). Das Rezeptfeld hängt rechts an der Liste und trägt seinen Rahmen selbst
    (common-insideframe), die Knöpfe hängen an der rechten unteren Ecke: beides wandert mit. Im Hintergrund liegt an der
    Grenze nur ein dunkler Streifen, der mitgestreckt wird. Die Fertigkeitsleiste rückt um die Hälfte, damit sie mittig bleibt.
    EXTRA = 36: Blizzard meldet das Fenster seiner Fensterverwaltung mit 750 an (professionsFrameWidthOverride), mehr als
    das verbreiterte Fenster (709). Nur Blizzards Herstellungsprotokoll (CraftingOutputLog) meldet beim Öffnen die Breite des
    Fensters selbst; sie stimmt dann auch verbreitert.

    Nur auf der Seite „Rezepte“; auf der Seite „Berufe“ (BookPage) gilt wieder Blizzards Breite. Gesetzt werden nur Breiten
    und der Anker der Fertigkeitsleiste, nichts in Blizzards Tabellen, nie im Kampf (das Fenster trägt geschützte Knöpfe).
    Andere Maße als Blizzards (ein anderes Addon, ein neuer Client): ezCraft lässt alles, wie es ist (Leitlinie 9).
]]

local Wide = {}
ns.Wide = Wide

local Plain, Num, Call, Peek = Core.Plain, Core.Num, Core.Call, Core.Peek

Wide.EXTRA = 36
Wide.BLIZZARD = { frame = 673, list = 304, back = 665 }
Wide.ATLAS = "profession-background-template2"

local hooked = setmetatable({}, { __mode = "k" })
local own                             -- solange ezCraft verbreitert hat: { frame, list, back, bar, barX }

local function Gamepad()
    local util = rawget(_G, "InputUtil")
    return type(util) == "table" and Plain(Call(util.IsGamepadUIEnabled)) == true
end

-- Blizzards Rahmen: Fenster, Seite „Rezepte“, Liste, Hintergrund der Seite (ohne Namen; am Atlas erkannt – die Vorlage
-- trägt je nach Client einen Zusatz wie „-c60“), Leiste
local function Parts()
    local pf = rawget(_G, "ProfessionsFrame")
    local page = Peek(pf, "CraftingPage")
    local list = Peek(page, "RecipeList")
    if type(list) ~= "table" or type(list.SetWidth) ~= "function" then return nil end
    local back
    for _, region in ipairs({ Call(page.GetRegions, page) }) do
        local atlas = type(region) == "table" and Plain(Call(region.GetAtlas, region))
        if type(atlas) == "string" and atlas:lower():sub(1, #Wide.ATLAS) == Wide.ATLAS then back = region end
    end
    return { frame = pf, page = page, list = list, back = back, bar = Peek(page, "RankBar") }
end

local function Is(frame, want)
    local width = frame and Num(Plain(Call(frame.GetWidth, frame)))
    return width ~= nil and math.abs(width - want) < 1
end

-- Die Leiste um x verschieben; only: nur, wenn sie noch dort steht. → ihre neue Lage
local function ShiftBar(bar, x, only)
    if type(bar) ~= "table" or Num(Plain(Call(bar.GetNumPoints, bar))) ~= 1 then return nil end
    local point, anchor, anchorPoint, at, y = bar:GetPoint(1)
    at = Num(Plain(at))
    if not (point and at) or (only and math.abs(at - only) > 0.5) then return nil end
    bar:ClearAllPoints()
    bar:SetPoint(point, anchor, anchorPoint, at + x, y)
    return at + x
end

-- So viel breiter ist die Liste gerade
function Wide.Extra() return own and Wide.EXTRA or 0 end

-- Auf die Breite stellen (on) oder zurück. → true, wenn sich etwas geändert hat
function Wide.Set(on)
    on = on == true
    if on == (own ~= nil) then return false end
    local B = Wide.BLIZZARD
    if on then
        local p = Parts()
        -- nur ausgehend von Blizzards Maßen; sonst hat sie jemand anders gesetzt
        if not (p and Is(p.frame, B.frame) and Is(p.list, B.list) and Is(p.back, B.back)) then return false end
        own = p
        for key, width in pairs(B) do p[key]:SetWidth(width + Wide.EXTRA) end
        p.barX = ShiftBar(p.bar, Wide.EXTRA / 2)
    else
        -- jedes Teil für sich zurück, solange es noch ezCrafts Maß hat – nie ein halber Stand
        local p = own
        own = nil
        for key, width in pairs(B) do
            if Is(p[key], width + Wide.EXTRA) then p[key]:SetWidth(width) end
        end
        if p.barX then ShiftBar(p.bar, -Wide.EXTRA / 2, p.barX) end
    end
    -- die Zeilen haben ihre neue Breite erst nach Blizzards nächstem Aufbau
    C_Timer.After(0, function()
        ns.Try("RecipeRow", ns.Skill.ApplyAll)
        ns.Try("Panel", ns.Panel.FitWidth)
    end)
    return true
end

local function IsShown(frame)
    return type(frame) == "table" and Plain(Call(frame.IsShown, frame)) == true
end

-- Blizzard zeigt beim Wechsel erst die neue Seite und versteckt dann die alte: solange „Berufe“ zu sehen ist, gilt sie
function Wide.Want()
    local pf = rawget(_G, "ProfessionsFrame")
    return ns.Enabled("rowWide") and not Gamepad() and IsShown(Peek(pf, "CraftingPage")) and not IsShown(Peek(pf, "BookPage"))
end

function Wide.Update()
    return ns.AfterCombat(function() Wide.Set(Wide.Want()) end, "Wide")
end

-- Auf beide Seiten achten (die Seite „Berufe“ kann später dazukommen). → hört ezCraft auf die Seite „Rezepte“?
function Wide.Hook()
    local pf = rawget(_G, "ProfessionsFrame")
    local fresh = false
    for _, key in ipairs({ "CraftingPage", "BookPage" }) do
        local page = Peek(pf, key)
        if type(page) == "table" and type(page.HookScript) == "function" and not hooked[page] then
            hooked[page], fresh = true, true
            page:HookScript("OnShow", function() Wide.Update() end)
            page:HookScript("OnHide", function() Wide.Update() end)
        end
    end
    if fresh then Wide.Update() end
    return hooked[Peek(pf, "CraftingPage") or false] == true
end

ns.WhenAddOnLoaded("Blizzard_Professions", Wide.Hook)
ns.On("TRADE_SKILL_SHOW", function()
    Wide.Hook()
    Wide.Update()
end)
ns.OnSettingChanged(function(key)
    if key == "rowWide" then Wide.Update() end
end)
