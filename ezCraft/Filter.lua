local ADDON, ns = ...
local L = ns.L
local Core = ezCore
local Data = ns.Data

--[[
    Schwierigkeitsfarben und Chance auf einen Fertigkeitspunkt (Welle 15b; Wunsch des Nutzers vom 15.11.2026 abends:
    „neuer punkt bei filtern z.b. zauberbuch will ich nach grau, weiß grün, gelb, orange filtern könnne --> also was
    gibt mir mit wieviel wahrscheinlichkeit einen skillpunkt“).
    Auslegung (festgehalten in docs/roadmap/ezCraft.md): gemeint sind die Schwierigkeitsfarben der Rezepte in
    Blizzards Berufefenster – orange, gelb, grün, grau – und weiß für Rezepte ohne Farbe (der Client nennt keine
    relativeDifficulty, etwa ohne Fertigkeitslinie), dazu die Chance auf einen Fertigkeitspunkt.

    Datenquellen (Leitlinie 11, jede Zahl nennt ihre Quelle):
      Farbe       Client: C_TradeSkillUI.GetRecipeInfo – relativeDifficulty (Enum.TradeskillRelativeDifficulty: 0
                  Optimal = orange, 1 Medium = gelb, 2 Easy = grün, 3 Trivial = grau), canSkillUp = false heißt grau;
                  Probe 10, Station J: relativeDifficulty, maxTrivialLevel, numSkillUps, canSkillUp, skillLineAbilityID
      grau ab     Client: maxTrivialLevel
      gelb ab     zur Laufzeit nicht im Client (er liefert nur skillLineAbilityID, den Schlüssel in die Tabelle
                  SkillLineAbility mit TrivialSkillLineRankLow); seit Welle 26 (F2) aus ezCores Client-Tabellen
                  (Knowledge.RecipeStages, SkillLineAbility laut wago.tools) für alle Rezepte, sonst beobachtet
                  (Knowledge.SkillStages, „~“ solange nicht genau)
      Chance      orange 100 % und grau 0 % laut Client; dazwischen berechnet nach der allgemeinen Spielmechanik
                  (Warcraft-Wiki, Artikel „Profession“: Chance = (grau − Fertigkeit) / (grau − gelb)) und als
                  „berechnet“ gekennzeichnet; ohne Gelb-Schwelle nur die Farbe, keine Zahl

    Filter: Blizzards Filtermenü des Berufefensters (Forever-Quelle Blizzard_ProfessionsTemplates/Camelot/
    Blizzard_Professions.lua: Professions.SetupFilterMenu, Tag „MENU_PROFESSIONS_FILTER“) hat keinen Farbfilter, nur
    „Hat Fertigkeitsanstieg“ (C_TradeSkillUI.SetOnlyShowSkillUpRecipes). ezCraft hängt über Menu.ModifyMenu einen
    Abschnitt „Farbe (ezCraft)“ mit fünf Haken an (mehrfach wählbar, gemerkt je Charakter in ezCraftDB.colorFilter).
    Blizzards Liste wird nicht gekürzt (das hieße, in Blizzards Datenquelle zu schreiben – Leitlinie 5): Rezepte einer
    abgewählten Farbe werden abgeblendet (ezCraft setzt nur die Deckkraft der Zeile); „Grau (nie)“ abwählen schaltet
    zusätzlich Blizzards eigenen Filter „Hat Fertigkeitsanstieg“ ein, der graue Rezepte wirklich ausblendet
    (Empfehlung umgesetzt, Antwort offen: Abblenden statt Ausblenden). Der Tooltip einer Zeile nennt die Chance
    (über Blizzards Nachricht „Professions.RecipeListOnEnter“); auf Wunsch steht sie als kleine Zahl neben dem Namen
    (Schalter chanceNumber, ab Werk aus).

      Skill.Color(info)            → "orange" | "yellow" | "green" | "gray" | "white" | "unlearned" (nicht gelernt:
                                     der Client meldet dann orange, ohne dass das etwas bedeutet – Probe 10, Station J3;
                                     keine Chance, im Farbfilter nie abgeblendet)
      Skill.Chance(recipe, rank)   → { color, chance (0–1 oder nil), from ("client" | "computed"), approx, toGreen,
                                       toGray, yellow, gray, yellowFrom ("client" Tabelle | "seen" beobachtet) }
      Skill.ChanceText(c)          → „Fertigkeitspunkt: etwa 40 % (gelb, berechnet), noch 12 Punkte bis grün“
      Skill.Wanted(color), Skill.SetWanted(color, an), Skill.FilterActive()
]]

local Skill = {}
ns.Skill = Skill

Skill.COLORS = { "orange", "yellow", "green", "gray", "white" }
Skill.DIM = 0.3            -- Deckkraft abgeblendeter Zeilen
Skill.MENU_TAG = "MENU_PROFESSIONS_FILTER"

local Num, Plain, Call = Core.Num, Core.Plain, Core.Call
local BY_DIFFICULTY = { [0] = "orange", [1] = "yellow", [2] = "green", [3] = "gray" }

function Skill.Color(info)
    if type(info) ~= "table" then return "white" end
    local difficulty = Num(Plain(info.relativeDifficulty))
    if difficulty == nil then difficulty = Num(info.difficulty) end
    local color = difficulty and BY_DIFFICULTY[difficulty]
    if not color then return "white" end
    if Plain(info.learned) == false then return "unlearned" end
    if Plain(info.canSkillUp) == false then return "gray" end
    return color
end

-- recipe: Data.Recipe (difficulty, canSkillUp, maxTrivial) oder Blizzards recipeInfo; rank: eigene Fertigkeit
function Skill.Chance(recipe, rank)
    local c = { color = Skill.Color(recipe) }
    if c.color == "orange" then c.chance, c.from = 1, "client" end
    if c.color == "gray" then c.chance, c.from = 0, "client" end
    if c.color == "white" or c.color == "unlearned" or type(recipe) ~= "table" then return c end
    local stages = Data.SkillStages({ recipeID = Num(recipe.recipeID), maxTrivial = Num(recipe.maxTrivial)
        or Num(Plain(recipe.maxTrivialLevel)) })
    c.gray, c.yellow = Num(stages.gray), Num(stages.yellow)
    c.yellowFrom = stages.source and stages.source.yellow or nil
    rank = Num(rank)
    if rank and c.gray then c.toGray = math.max(0, c.gray - rank) end
    if rank and c.color == "yellow" and Num(stages.green) and stages.green > rank then c.toGreen = stages.green - rank end
    if c.chance == nil and rank and c.gray and c.yellow and c.gray > c.yellow then
        local chance = (c.gray - rank) / (c.gray - c.yellow)
        c.chance = math.max(0, math.min(1, chance))
        c.from, c.approx = "computed", stages.approx and stages.approx.yellow or nil
    end
    return c
end

function Skill.ChanceText(c)
    if type(c) ~= "table" or c.color == "unlearned" then return nil end
    local colorName = L["STAGE_" .. c.color] or L.STAGE_white
    local text
    if c.chance == nil then
        text = L.CHANCE_UNKNOWN:format(colorName)
    elseif c.from == "client" then
        text = (c.chance >= 1 and L.CHANCE_SURE or L.CHANCE_NEVER):format(colorName)
    else
        text = L.CHANCE_COMPUTED:format(Core.Percent(c.chance * 100), colorName)
    end
    if c.toGreen then
        text = text .. ", " .. L.CHANCE_TO_GREEN:format(c.toGreen)
    elseif c.toGray and c.chance and c.chance > 0 then
        text = text .. ", " .. L.CHANCE_TO_GRAY:format(c.toGray)
    end
    return text
end

-- Quelle der Zahl in einer Zeile (Leitlinie 11)
function Skill.SourceText(c)
    if type(c) ~= "table" or c.color == "unlearned" then return nil end
    if c.from == "computed" then
        if c.yellowFrom == "client" then return L.CHANCE_SOURCE_TABLE end
        return c.approx and L.CHANCE_SOURCE_APPROX or L.CHANCE_SOURCE_COMPUTED
    elseif c.from == "client" then
        return L.CHANCE_SOURCE_CLIENT
    end
    if c.color ~= "white" then return L.CHANCE_SOURCE_NOYELLOW end
    return nil
end

-- Kleine Zahl neben dem Namen: „100“, „40“, „0“; ohne Zahl nichts
function Skill.ShortText(c)
    if type(c) ~= "table" or c.chance == nil then return nil end
    return Data.StageColorCode(c.color == "white" and "gray" or c.color) .. Core.Percent(c.chance * 100) .. "|r"
end

---------------------------------------------------------------------------
-- Filter nach Farbe (gemerkt je Charakter)
---------------------------------------------------------------------------

local function Store()
    local db = ns.db
    if type(db) ~= "table" or not ns.charKey then return nil end
    if type(db.colorFilter) ~= "table" then db.colorFilter = {} end
    local mine = db.colorFilter[ns.charKey]
    if type(mine) ~= "table" then
        mine = {}
        db.colorFilter[ns.charKey] = mine
    end
    return mine
end

-- Vergisst ezCore einen Twink (Core.ForgetChar, Nachricht CHAR_FORGOTTEN), geht seine Farbfilter-Wahl mit
-- (ezCraftDB.colorFilter[key]; Gesamtreview 18.11.2026, T4-2). → true, wenn etwas gemerkt war.
function Skill.ForgetChar(key)
    local db = ns.db
    if type(key) ~= "string" or key == ns.charKey or type(db) ~= "table" or type(db.colorFilter) ~= "table" then
        return false
    end
    if db.colorFilter[key] == nil then return false end
    db.colorFilter[key] = nil
    return true
end
Core.Listen("CHAR_FORGOTTEN", function(key) Skill.ForgetChar(key) end, ADDON)

function Skill.Wanted(color)
    local s = Store()
    return not (s and s[color] == false)
end

function Skill.FilterActive()
    for _, color in ipairs(Skill.COLORS) do
        if not Skill.Wanted(color) then return true end
    end
    return false
end

-- „Grau (nie)“ abwählen: Blizzards eigener Filter „Hat Fertigkeitsanstieg“ blendet graue Rezepte wirklich aus;
-- ezCraft merkt sich, dass es ihn gesetzt hat, und nimmt nur den eigenen wieder zurück.
local function SyncSkillUpFilter()
    local api = C_TradeSkillUI
    if not (api and type(api.SetOnlyShowSkillUpRecipes) == "function") then return false end
    local s = Store()
    if not s then return false end
    local want = not Skill.Wanted("gray")
    local now = Plain(Call(api.GetOnlyShowSkillUpRecipes)) == true
    if want and not now then
        Call(api.SetOnlyShowSkillUpRecipes, true)
        s.setByUs = true
    elseif not want and now and s.setByUs then
        Call(api.SetOnlyShowSkillUpRecipes, false)
        s.setByUs = nil
    elseif not want then
        s.setByUs = nil
    end
    return true
end
Skill.SyncSkillUpFilter = SyncSkillUpFilter

-- Blizzard setzt seine Filter zurück (Forever-Quelle Blizzard_Professions.lua: Professions.SetDefaultFilters ruft
-- SetOnlyShowSkillUpRecipes(false) – beim ersten SetTab nach dem Öffnen und beim Knopf „Standard“). Kurz nach dem
-- Öffnen ist das Blizzards Grundstellung: die gemerkte Auswahl gleich danach wieder anwenden. Später ist es der
-- Spieler („Standard“): dann gilt Blizzards Zurücksetzen auch für „Grau (nie)“.
Skill.OPEN_GRACE = 1     -- Sekunden nach dem Öffnen, in denen ein Zurücksetzen als Grundstellung gilt
function Skill.OnDefaultFilters()
    local s = Store()
    if not s or Skill.Wanted("gray") then return false end
    local pf = rawget(_G, "ProfessionsFrame")
    local shown = type(pf) == "table" and type(pf.IsShown) == "function" and pf:IsShown()
    local opening = not shown or (Core.Uptime() - (Skill.shownAt or -1000)) < Skill.OPEN_GRACE
    if opening then
        C_Timer.After(0, function() ns.Try("ColorFilter", SyncSkillUpFilter) end)
        return "again"
    end
    s.gray, s.setByUs = nil, nil
    Skill.ApplyAll()
    return "reset"
end

function Skill.SetWanted(color, on)
    local s = Store()
    if not s then return false end
    if on == false then s[color] = false else s[color] = nil end   -- nur Abgewähltes wird gemerkt
    if color == "gray" then SyncSkillUpFilter() end
    Skill.ApplyAll()
    return true
end

function Skill.Reset()
    local s = Store()
    if not s then return false end
    for _, color in ipairs(Skill.COLORS) do s[color] = nil end
    SyncSkillUpFilter()
    Skill.ApplyAll()
    return true
end

---------------------------------------------------------------------------
-- Blizzards Rezeptliste: Abblenden, kleine Zahl, Zeile im Tooltip (nur eigene Regionen und Deckkraft; nichts in
-- Blizzards Tabellen)
---------------------------------------------------------------------------

local numbers = setmetatable({}, { __mode = "k" })   -- Zeile » eigene Schrift (nicht an Blizzards Rahmen gemerkt)

local function RecipeList()
    local pf = rawget(_G, "ProfessionsFrame")
    local page = type(pf) == "table" and pf.CraftingPage
    local list = type(page) == "table" and page.RecipeList
    return type(list) == "table" and list or nil
end

local function RowInfo(button, node)
    local data = node and type(node.GetData) == "function" and node:GetData()
    if not data and button and type(button.GetElementData) == "function" then
        local ok, el = pcall(button.GetElementData, button)
        data = ok and el and (type(el.GetData) == "function" and el:GetData() or el.data) or nil
    end
    return type(data) == "table" and type(data.recipeInfo) == "table" and data.recipeInfo or nil
end

function Skill.ApplyRow(button, node)
    if type(button) ~= "table" or type(button.SetAlpha) ~= "function" then return false end
    local info = RowInfo(button, node)
    if not info then return false end
    local color = Skill.Color(info)
    button:SetAlpha(not Skill.Wanted(color) and Skill.DIM or 1)
    local text = numbers[button]
    if ns.Enabled("chanceNumber") then
        if not text then
            text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            text:SetPoint("RIGHT", button, "RIGHT", -4, 0)
            numbers[button] = text
        end
        text:SetText(Skill.ShortText(Skill.Chance(info, ns.Where.Rank())) or "")
        text:Show()
    elseif text then
        text:Hide()
    end
    return true
end

function Skill.ApplyAll()
    local list = RecipeList()
    local box = list and rawget(list, "ScrollBox") or (list and list.ScrollBox)
    if type(box) ~= "table" or type(box.ForEachFrame) ~= "function" then return 0 end
    local n = 0
    pcall(box.ForEachFrame, box, function(frame)
        if Skill.ApplyRow(frame) then n = n + 1 end
    end)
    return n
end

-- Zeile im Tooltip einer Rezeptzeile (Blizzards Nachricht beim Überfahren, Professions.RecipeListOnEnter)
-- Immer an seit der Einstellungs-Prüfung vom 19.11.2026 (Nr. 21: reine Hilfe).
function Skill.OnRecipeEnter(_, button, data)
    local info = type(data) == "table" and data.recipeInfo
    if type(info) ~= "table" then return end
    local c = Skill.Chance(info, ns.Where.Rank())
    local text = Skill.ChanceText(c)
    if not text then return end
    if not GameTooltip:IsShown() then GameTooltip:SetOwner(button, "ANCHOR_RIGHT") end
    -- Stufenfarbe aus ezCore (Data.StageRGB); „weiß“ (Farbe unbekannt) bleibt Blizzards Weiß wie bisher
    local r, g, b
    if Data.IsStage(c.color) then r, g, b = Data.StageRGB(c.color) else r, g, b = Core.Style.Color("highlight") end
    GameTooltip:AddLine(text, r, g, b)
    local src = Skill.SourceText(c)
    if src then ns.TipLine(GameTooltip, src, "hint", true) end
    GameTooltip:Show()
end

-- Erklärung je Farbe im Menü (Schlüssel der Texte; fehlt eine Farbe, gilt FILTER_COLOR_TIP)
Skill.MENU_TIPS = { gray = "FILTER_gray_TIP", white = "FILTER_white_TIP" }

-- Abschnitt im Filtermenü des Berufefensters (Blizzards Menü-API; Blizzards Einträge bleiben unberührt).
-- Seit Welle 27 (Zweig modul/ezcraft-menue, Stil wie das ezMap-Menü, Design-System 2.3/2.7/2.11/2.12): Überschrift mit
-- dem Symbol „Farbe“ (Core.Menu.Section über ns.Icons.Section: Trenner und Überschrift erst mit dem ersten Eintrag),
-- „Alle auswählen / Alle abwählen“ mit Blizzards Häkchen bzw. Kreuz, je Farbe Blizzards farbiges Kennzeichen als Marke
-- (ns.Icons.Color), Tooltip je Eintrag mit grauer Quellenzeile. Gemerkt wie bisher je Charakter (ezCraftDB.colorFilter).
-- Immer im Menü seit der Einstellungs-Prüfung vom 19.11.2026 (Nr. 20, Fall des Nutzers: der Schalter schaltete einen
-- Suchfilter ab; ab Werk sind alle Farben gewählt, der Filter tut also nichts, bis man ihn benutzt).
function Skill.BuildMenu(root)
    local Menu, Icons = Core.Menu, ns.Icons
    local sec = Icons.Section(root, L.FILTER_HEAD, { icon = Icons.For("colors"), tip = L.FILTER_HEAD_TIP,
        source = L.FILTER_SOURCE })
    -- Design-System 2.11 (Mehrfachauswahl): „Alle auswählen / Alle abwählen“ direkt unter der Überschrift, vor den
    -- Haken; Wortlaut Core.Style.AllText (Blizzards CHECK_ALL/UNCHECK_ALL, sonst ezCores Text). Gemerkt wie jeder Haken.
    if type(Menu.AllToggle) == "function" and Core.Style then
        Menu.AllToggle(sec, Skill.COLORS, Skill.Wanted, Skill.SetWanted,
            { onText = Core.Style.AllText(true), offText = Core.Style.AllText(false), icons = true,
              onTip = Core.L.ALL_CHECK_TIP, offTip = L.FILTER_ALL_OFF_TIP })
    end
    for _, color in ipairs(Skill.COLORS) do
        local label = L["FILTER_" .. color]
        local entry = sec:CreateCheckbox(Data.StageColorCode(color == "white" and "gray" or color) .. label .. "|r",
            function() return Skill.Wanted(color) end,
            function() Skill.SetWanted(color, not Skill.Wanted(color)) end)
        Icons.Apply(entry, Icons.Color(color))
        Menu.Tip(entry, label, L[Skill.MENU_TIPS[color] or "FILTER_COLOR_TIP"], L.FILTER_SOURCE)
    end
    -- Kein eigener Eintrag „Alle Farben zeigen“ mehr: „Alle auswählen“ tut dasselbe (Regel 2.11 „nie doppelt“;
    -- Entscheidung des Nutzers vom 16.11.2026, Nr. 21, vorläufig nach Empfehlung). Skill.Reset bleibt (Leitlinie 8).
    return true
end

Skill.registered, Skill.hooked, Skill.tipHooked = false, false, false
function Skill.Register()
    local blizzardMenu = rawget(_G, "Menu")
    if not Skill.registered and type(blizzardMenu) == "table" and type(blizzardMenu.ModifyMenu) == "function" then
        Skill.registered = pcall(blizzardMenu.ModifyMenu, Skill.MENU_TAG, function(_, root)
            ns.Try("ColorFilter", Skill.BuildMenu, root)
        end)
    end
    return Skill.registered
end

-- Rezeptzeilen: neu eingerichtete Zeilen (ScrollUtil.AddInitializedFrameCallback, Blizzards Weg für Ergänzungen)
-- und Blizzards Nachricht beim Überfahren
function Skill.Hook()
    local list = RecipeList()
    local box = list and rawget(list, "ScrollBox") or (list and list.ScrollBox)
    local util = rawget(_G, "ScrollUtil")
    if not Skill.hooked and type(box) == "table" and type(util) == "table"
        and type(util.AddInitializedFrameCallback) == "function" then
        pcall(util.AddInitializedFrameCallback, box, function(_, frame, node)
            ns.Try("ColorRow", Skill.ApplyRow, frame, node)
        end, Skill, true)
        Skill.hooked = true
    end
    local reg = rawget(_G, "EventRegistry")
    if not Skill.tipHooked and type(reg) == "table" and type(reg.RegisterCallback) == "function" then
        reg:RegisterCallback("Professions.RecipeListOnEnter", function(...)
            ns.Try("ChanceTip", Skill.OnRecipeEnter, ...)
        end, Skill)
        Skill.tipHooked = true
    end
    -- Blizzards Zurücksetzen der Filter (nur hooksecurefunc, Leitlinie 5) und der Zeitpunkt des Öffnens
    local P = rawget(_G, "Professions")
    if not Skill.defaultsHooked and type(P) == "table" and type(P.SetDefaultFilters) == "function" then
        hooksecurefunc(P, "SetDefaultFilters", function() ns.Try("ColorFilter", Skill.OnDefaultFilters) end)
        Skill.defaultsHooked = true
    end
    local pf = rawget(_G, "ProfessionsFrame")
    if not Skill.showHooked and type(pf) == "table" and type(pf.HookScript) == "function" then
        pf:HookScript("OnShow", function() Skill.shownAt = Core.Uptime() end)
        Skill.showHooked = true
    end
    return Skill.hooked
end

ns.WhenAddOnLoaded("Blizzard_Professions", function()
    Skill.Register()
    Skill.Hook()
end)
ns.On("TRADE_SKILL_SHOW", function()
    Skill.shownAt = Core.Uptime()
    Skill.Register()
    Skill.Hook()
    SyncSkillUpFilter()
end)
ns.OnSettingChanged(function(key)
    if key == "chanceNumber" then Skill.ApplyAll() end
end)
