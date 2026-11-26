local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Ansagen für Anführer, Stufe 2 (MACRO-26): Eintrag „Ansage“ im Rechtsklick-Menü von Blizzards Gruppen- und
    Raidrahmen, des Zielfensters, des Fokus und der Bossrahmen (Core.Menu.ModifyUnits, Blizzards Menü bleibt
    sonst unberührt). Fertige Sätze mit eingesetztem Namen und Zielsymbol:
      Mitspieler   „<Name> heilt <Ziel>.“ (mit freundlichem Ziel), „<Name> unterbricht {Symbol} <Ziel>.“ (mit
                   feindlichem Ziel, sonst nur „<Name> unterbricht.“), „Bitte <Name> heilen!“
      Gegner       „Fokus auf {Symbol} <Name>!“, „CC auf {Symbol} <Name> – nicht angreifen!“, „Unterbrechen:
                   {Symbol} <Name>!“
    Die Zeile kommt nur in die Chat-Eingabe – mit Blizzards Befehl für den Kanal davor (/rw, /raid, /i, /p), Enter
    schickt sie ab (Core.OpenChatWith). Wo Blizzard den Namen sperrt, steht der Eintrag nicht (Core.Menu.ModifyUnits, Spieltest
    25.11.2026); der Knopf „Zum Ziel …“ geht auch dort. Ob das Menü direkt senden darf, entscheidet der Spieltest (Welle 2, Punkte 3
    bis 5 unter „Im Spiel prüfen“ in docs/roadmap/ezMacro.md); bis dahin sendet ezMacro hier nie selbst.
    Der Eintrag erscheint nur in einer Gruppe und mit der Einstellung „Eintrag „Ansage“ in Rechtsklick-Menüs“
    (announceMenu, ab Werk an). Sichtbarer Zugang (Leitlinie 3): Knopf „Zum Ziel …“ im Reiter „Chat“ (Ansagen) – dasselbe
    Menü für das aktuelle Ziel.

    AnnounceMenu.Entries(unit, name) → { { text, kind, shown }, … }   (leer: nichts anzubieten)
    AnnounceMenu.Add(root, unit, name, opts) → true, wenn etwas eingetragen wurde (opts.force: auch allein und mit
        ausgeschalteter Einstellung; opts.flat: direkt in root statt im Untermenü „Ansage“)
    AnnounceMenu.ToChat(entry) → true, Kanal | false, "alone" | "locked" | "missing" | "empty"
    AnnounceMenu.Hook() → true, sobald die Menüs ergänzt sind     AnnounceMenu.OpenFor(owner) Knopf im Reiter
]]
local AM = {}
ns.AnnounceMenu = AM

-- Blizzards Menüs der Einheiten: ezCores eine Liste der Spieler-Menüs (Core.Menu.PlayerMenus, Welle 23 – vorher
-- führte ezMacro die Tags selbst), davon die Menüs mit Einheit (eigener Rahmen, Gruppe, Raid, Ziel, Fokus, feindlicher
-- Spieler), dazu die Bossrahmen (MENU_UNIT_BOSS – kein Spieler-Menü, darum nicht in ezCores Liste).
AM.EXTRA_TAGS = { "MENU_UNIT_BOSS" }
function AM.Tags()
    local tags = {}
    local menu = Core.Menu
    if menu and type(menu.PlayerMenus) == "function" then
        for _, tag in ipairs(menu.PlayerMenus({ unit = true })) do tags[#tags + 1] = tag end
    end
    for _, tag in ipairs(AM.EXTRA_TAGS) do tags[#tags + 1] = tag end
    return tags
end
AM.TAGS = AM.Tags()

-- Sätze: Text aus Locale.lua (%n Name aus dem Menü, %t Name des Ziels, %r Zielsymbol), Art des Kanals
-- (Announce.Channel: "warn" = Raidwarnung als Leiter oder Assistent) und was dafür da sein muss.
AM.FRIEND = {
    { key = "ANN_M_HEALS", kind = "group", target = "friend" },
    { key = "ANN_M_KICKS", kind = "group", target = "enemy" },
    { key = "ANN_M_KICKS_PLAIN", kind = "group", target = "none" },
    { key = "ANN_M_HEAL_ME", kind = "group" },
}
AM.ENEMY = {
    { key = "ANN_M_FOCUS", kind = "warn" },
    { key = "ANN_M_CC", kind = "warn" },
    { key = "ANN_M_KICK", kind = "group" },
}

-- Text, wenn er frei und nicht leer ist (Core.Plain prüft zuerst auf gesperrt).
local function FreeText(value)
    value = Core.Plain(value)
    if type(value) ~= "string" or value == "" then return nil end
    return value
end

local function Hostile(unit)
    return Core.Bool(Core.Call(rawget(_G, "UnitCanAttack"), "player", unit), false)
end

-- Was das eigene Ziel gerade ist: "none" (keins), "enemy", "friend" – gesperrte Antworten zählen als „keins“.
local function TargetKind(unit)
    if Core.UnitPresent("target") ~= true then return "none" end
    if unit and Core.UnitIs(unit, "target") == true then return "none" end   -- das Ziel ist die Einheit selbst
    return Hostile("target") and "enemy" or "friend"
end

-- {rt1} … {rt8} im Menü als Symbol zeigen (in der Chatzeile bleibt das Zeichen, der Chat zeigt es selbst); ein
-- stehen gebliebenes %t (gesperrter Name) heißt dort „<Ziel>“.
local function ShowMarks(text)
    text = text:gsub("{rt(%d)}", function(n) return "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. n .. ":0|t" end)
    return (text:gsub("%%t", function() return L.ANN_SHOW_TARGET end))
end

function AM.Entries(unit, name)
    local list = {}
    unit = FreeText(unit)
    local function Add(def, ctx)
        local text = ns.Announce.Expand(L[def.key], ctx)
        if text ~= "" then list[#list + 1] = { key = def.key, kind = def.kind, text = text, shown = ShowMarks(text) } end
    end
    if unit and Core.UnitPresent(unit) == true and Hostile(unit) then
        -- Gegner: Name und Symbol der Einheit selbst. Ist der Name gesperrt, geht das nur beim Ziel (%t setzt
        -- dann Blizzards Chat beim Abschicken ein; nur im eigenen Menü „Zum Ziel …“, Blizzards Menü bleibt dann
        -- unberührt); bei anderen Einheiten gibt es keine Ansage.
        local _, why = ns.Announce.UnitName(unit)
        if why == "secret" and unit ~= "target" then return list end
        for _, def in ipairs(AM.ENEMY) do Add(def, { target = unit }) end
        return list
    end
    -- Mitspieler (auch nur mit Namen, etwa im Raid-Reiter): Name aus dem Menü, Ziel ist dein eigenes Ziel.
    local who = unit and ns.Announce.UnitName(unit) or nil
    who = who or FreeText(name)
    if not who then return list end
    who = Core.ShortName and Core.ShortName(who) or who
    local target = TargetKind(unit)
    for _, def in ipairs(AM.FRIEND) do
        if def.target == nil or def.target == target then Add(def, { target = "target", name = who }) end
    end
    return list
end

-- Die fertige Zeile mit Blizzards Befehl für den Kanal in die Chat-Eingabe legen; gesendet wird erst mit Enter.
function AM.ToChat(entry)
    if type(entry) ~= "table" or type(entry.text) ~= "string" or entry.text == "" then return false, "empty" end
    local channel = ns.Announce.Channel(entry.kind)
    if not channel then
        ns.Print(L.ANN_ALONE:format(entry.text))
        return false, "alone"
    end
    local open = Core.OpenChatWith
    local ok, why = false, "missing"
    if type(open) == "function" then ok, why = open(ns.Announce.CommandFor(channel) .. " " .. entry.text) end
    if not ok then
        ns.Print(why == "locked" and L.ANN_MENU_LOCKED or L.ANN_MENU_FAILED:format(entry.text))
        return false, why
    end
    return true, channel
end

function AM.Add(root, unit, name, opts)
    opts = opts or {}
    if type(root) ~= "table" or type(root.CreateButton) ~= "function" then return false end
    if not opts.force and not (ns.S and ns.S.announceMenu and Core.GroupChannel()) then return false end
    local entries = AM.Entries(unit, name)
    if #entries == 0 then return false end
    local parent = root
    if not opts.flat then
        if root.CreateDivider then root:CreateDivider() end
        parent = root:CreateButton(L.MENU_ANNOUNCE)
    end
    for _, entry in ipairs(entries) do
        local channel = ns.Announce.Channel(entry.kind)
        local button = parent:CreateButton(entry.shown, function() AM.ToChat(entry) end)
        Core.Menu.Tip(button, L.MENU_ANNOUNCE, L.ANN_MENU_TIP:format(ns.Announce.ChannelLabel(channel)))
    end
    return true
end

-- Rückruf aus Blizzards Menü: contextData.unit (Rahmen, Ziel, Fokus) bzw. nur contextData.name (Raid-Reiter).
function AM.FromContext(root, contextData)
    if type(contextData) ~= "table" then return false end
    return AM.Add(root, contextData.unit, contextData.name)
end

local hooked = false
function AM.Hook()
    if hooked then return true end
    local blizzardMenu = rawget(_G, "Menu")
    if not (type(blizzardMenu) == "table" and type(blizzardMenu.ModifyMenu) == "function") then return false end
    AM.TAGS = AM.Tags()
    -- nicht in Menüs mit gesperrtem Namen (Core.Menu.UnitLocked; Spieltest 25.11.2026: Blizzards Menü brach ab, die
    -- Zielmarkierung ging nicht) – dafür gibt es den Knopf „Zum Ziel …“
    Core.Menu.ModifyUnits(AM.TAGS, function(root, contextData) ns.Try("AnnounceMenu", AM.FromContext, root, contextData) end)
    hooked = true
    return true
end

-- Knopf „Zum Ziel …“ im Reiter „Chat“ (Ansagen): dasselbe Menü für das aktuelle Ziel, auch allein (dann sagt ein Klick,
-- dass die Zeile keinen Kanal hat) und mit ausgeschaltetem Menü-Eintrag.
function AM.OpenFor(owner)
    return Core.Menu.Open(owner, function(root)
        root:CreateTitle(L.ANN_TARGET_TITLE)
        if not AM.Add(root, "target", nil, { force = true, flat = true }) then root:CreateTitle(L.ANN_MENU_NO_UNIT) end
    end)
end

ns.OnReady(function() AM.Hook() end)
