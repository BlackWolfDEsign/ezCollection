local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Heilen und Buffen per Klick – der Makro-Teil von ezHeal in ezMacro (Welle 2b, Thema 6; Entscheidungen des Nutzers
    vom 13.11.2026: „ezHeal als eigenes schlankes Modul mit dem Makro-Teil in ezMacro“, ezHeal bleibt die Klick-Schicht
    für Heilen, Bannen und Wiederbeleben, Buffs zusätzlich in den Klick-Vorlagen).

    1. Knopf „Klick-Zauber“ im Makro-Browser (unter „Anpassen“): legt das gewählte Makro über ezCores Dienst
       Core.ClickBindings auf eine Maustaste mit Umschalttaste – Blizzards Klick-Zaubern, wirkt auf Gruppen- und
       Raidrahmen. Ablauf: Taste im Menü wählen (je Taste steht dabei, was heute dort liegt) → Rückfrage (Core.Confirm)
       → fehlt das Makro in Blizzards Makroverwaltung, legt ezMacro es zuerst an → CB.Assign(CB.Macro(name, taste,
       umschalttasten), { owner = "ezMacro" }). Nur außerhalb des Kampfes; ezCore sichert die alte Belegung
       (Core.ClickBindings.Restore) und lässt „Ziel“ und „Menü“ auf ihren Tasten.

    2. Gruppe „Heilen und Buffen per Klick“ im Reiter „Makros“ (eigene Auswahl): Maus-über-Makros für Heilen,
       Bannen, Wiederbeleben und Buffs auf Mitspieler.
       - Läuft ezHeal (ezCore.API("ezHeal").Template), kommen die Zauber aus seinen Vorlagen („all“: Heilen und Buffs
         für deine Klasse, der höchste gelernte Rang) – je Platz ein Makro, die Taste der Vorlage ist beim Knopf
         „Klick-Zauber“ vorgeschlagen. ezMacro führt dafür keine eigene Zauberliste.
       - Ohne ezHeal: die vorhandenen Maus-über-Makros deiner Klasse aus Data\Classes.lua (alle, die auf freundliche
         Einheiten unter der Maus wirken) – keine zweite Liste, dieselben Einträge wie in der Auswahl „Klasse“.
]]
local ClickCast = {}
ns.ClickCast = ClickCast

local Menu = Core.Menu

-- Text oder nil (ezCores Texttabelle liefert für einen fehlenden Schlüssel den Schlüssel selbst)
local function Text(key)
    local value = L[key]
    if type(value) == "string" and value ~= key then return value end
    return nil
end

-- Tasten zur Wahl (Maustaste, Umschalttasten). Links und Rechts ohne Umschalttaste bleiben Blizzards „Ziel“ und
-- „Menü“ und stehen deshalb nicht in der Liste.
ClickCast.KEYS = {
    { "left", "SHIFT" }, { "right", "SHIFT" }, { "left", "CTRL" }, { "right", "CTRL" },
    { "left", "ALT" }, { "right", "ALT" }, { "middle", nil }, { "middle", "SHIFT" },
}

local function CB()
    local cb = Core.ClickBindings
    if type(cb) == "table" and type(cb.Writable) == "function" then return cb end
    return nil
end

function ClickCast.Available()
    local cb = CB()
    return cb ~= nil and cb.Writable() == true
end

-- Rücksicht auf fremde Addons (Leitlinie 9): Läuft ein Addon, das die Klicks auf Gruppenrahmen selbst belegt
-- (ezCore: Core.WhoHandles("clickCast"), heute Clique), nennen Tooltip und Rückfrage es. Der Knopf bleibt: Er
-- wirkt nur auf ausdrücklichen Wunsch mit Rückfrage; Blizzards Klick-Zauber und Clique können sich aber auf
-- derselben Taste überschneiden – das soll der Spieler vor dem Ja wissen. → Name | nil
function ClickCast.Other()
    local name = ns.OtherFor("clickCast")     -- Gerüst: Core.WhoHandles, innen gesichert
    if type(name) == "string" and name ~= "" then return name end
    return nil
end

local Plain = Core.Plain   -- Wert nur, wenn er nicht geheim ist (ezCore, Leitlinie 2)

-- Tastentexte aus ezCore (Core.ClickBindings.KeyText/Describe samt Texten CLICK_MOD_*, CLICK_BUTTON_*, CLICK_ACTION_*,
-- CLICK_FREE, CLICK_IS_MACRO, CLICK_OTHER in ezCores Locale; EC-109, MACRO-20) – eine Fassung mit ezHeal. Die beiden
-- Namen hier bleiben als Weiterleitung (Leitlinie 8).

-- „Umschalt + Linksklick“
function ClickCast.KeyText(button, modifiers)
    return Core.ClickBindings.KeyText(button, modifiers)
end

-- Was liegt heute auf einer Taste? → Text (Zaubername samt Rang aus ezMacros Zauberwissen, wenn es ihn kennt)
function ClickCast.Describe(entry)
    local spellName = type(entry) == "table" and entry.kind == "spell" and entry.id ~= nil and ns.SpellName(entry.id) or nil
    return Core.ClickBindings.Describe(entry, spellName)
end

-- Aktuelle Belegung (Liste) oder nil
local function Current()
    local cb = CB()
    if not cb then return nil end
    local list = cb.List()
    return type(list) == "table" and list or nil
end

function ClickCast.CurrentOn(button, modifiers, list)
    local cb = CB()
    list = list or Current()
    if not (cb and list) then return Core.L.CLICK_FREE end
    return ClickCast.Describe((cb.Find(list, button, modifiers)))
end

-- Tasten für einen Eintrag: der Vorschlag (entry.click, aus ezHeals Vorlage) zuerst.
function ClickCast.KeysFor(entry)
    local keys, seen = {}, {}
    local function add(key, suggested)
        local id = tostring(key[1]) .. ":" .. tostring(key[2] or "")
        if seen[id] then return end
        seen[id] = true
        keys[#keys + 1] = { key[1], key[2], suggested = suggested or nil }
    end
    if type(entry) == "table" and type(entry.click) == "table" then add(entry.click, true) end
    for _, key in ipairs(ClickCast.KEYS) do add(key) end
    return keys
end

---------------------------------------------------------------------------
-- Belegen
---------------------------------------------------------------------------

-- Makro (Name) auf die Taste legen. → true | false, grund ("combat" heißt: kommt nach dem Kampf)
function ClickCast.Assign(name, button, modifiers)
    local cb = CB()
    if not (cb and cb.Writable()) then return false, "missing" end
    if ns.InCombat() then return false, "combat" end
    local entry, why = cb.Macro(name, button, modifiers)
    if not entry then return false, why or "invalid" end
    return cb.Assign(entry, { owner = "ezMacro" })
end

local function Report(name, keyText, ok, reason)
    if ok then
        ns.Print((reason == "same" and L.CLICK_SAME or L.CLICK_DONE):format(name, keyText))
    elseif reason == "combat" then
        ns.Print(L.CLICK_LATER:format(name, keyText))
    else
        ns.Print(L.CLICK_FAILED:format(name, Text("CLICK_ERR_" .. tostring(reason)) or tostring(reason)))
    end
end

-- Nach der Rückfrage: fehlt das Makro, zuerst anlegen (Import.lua), dann belegen.
function ClickCast.Run(entry, name, body, perChar, button, modifiers)
    if ns.InCombat() then
        ns.CombatNotice()
        return false
    end
    name = ns.Import.CleanName(name)
    local keyText = ClickCast.KeyText(button, modifiers)
    local function assign()
        local ok, reason = ClickCast.Assign(name, button, modifiers)
        Report(name, keyText, ok, reason)
    end
    if ns.Import.Find(name) then
        assign()
        return true
    end
    return ns.Import.Apply(entry, name, body, perChar, false, assign)
end

-- Rückfrage mit Makro, Taste und dem, was dort heute liegt.
function ClickCast.Ask(entry, name, body, perChar, button, modifiers)
    if ns.InCombat() then
        ns.CombatNotice()
        return false
    end
    if not ClickCast.Available() then
        ns.Print(L.CLICK_FAILED:format(name, L.CLICK_ERR_missing))
        return false
    end
    name = ns.Import.CleanName(name)
    local text = L.CLICK_CONFIRM:format(name, ClickCast.KeyText(button, modifiers), ClickCast.CurrentOn(button, modifiers))
    -- Gibt es schon ein Makro dieses Namens, belegt ClickCast.Run genau dieses (mit seinem Text) – das sagt die Frage
    if ns.Import.Find(name) then
        text = text .. "\n" .. L.CLICK_CONFIRM_EXISTING:format(name)
    else
        text = text .. "\n" .. L.CLICK_CONFIRM_CREATE
    end
    local other = ClickCast.Other()
    if other then text = text .. "\n" .. L.CLICK_OTHER_ADDON:format(other, other) end
    Core.Confirm(text, function() ClickCast.Run(entry, name, body, perChar, button, modifiers) end)
    return true
end

-- Menü am Knopf „Klick-Zauber“: je Taste ein Eintrag mit dem, was dort heute liegt; der Vorschlag oben.
function ClickCast.Menu(owner, entry, name, body, perChar)
    if ns.InCombat() then
        ns.CombatNotice()
        return false
    end
    if not ClickCast.Available() then
        ns.Print(L.CLICK_FAILED:format(tostring(name), L.CLICK_ERR_missing))
        return false
    end
    local list = Current()
    Menu.Open(owner, function(root)
        Menu.Title(root, L.CLICK_MENU_TITLE:format(ns.Import.CleanName(name)))
        for _, key in ipairs(ClickCast.KeysFor(entry)) do
            local label = ClickCast.KeyText(key[1], key[2]) .. " – " .. ClickCast.CurrentOn(key[1], key[2], list)
            if key.suggested then label = label .. " " .. L.CLICK_SUGGESTED end
            Menu.Button(root, label, function() ClickCast.Ask(entry, name, body, perChar, key[1], key[2]) end)
        end
    end)
    return true
end

---------------------------------------------------------------------------
-- Gruppe „Heilen und Buffen per Klick“ (Reiter „Makros“)
---------------------------------------------------------------------------

local RES_SLOTS = { res = true }
local generated = {}   -- [Platz] = Eintrag (bleibt derselbe, damit die Auswahl im Browser hält)
local wrapped = {}     -- [Eintrag aus Data\Classes.lua] = Hülle in der Gruppe

-- Wirkt die Vorlage auf freundliche Einheiten unter der Maus (Heilen, Bannen, Wiederbeleben, Buffs)?
function ClickCast.IsClickMacro(body)
    body = type(body) == "string" and body or ""
    return body:find("@mouseover,help", 1, true) ~= nil or body:find("@mouseover,exists", 1, true) ~= nil
end

-- Mitglied unter der Maus zuerst, nie auf das Ziel durchrutschen (ns.GroupFirst, Spieltest 15.11.2026)
local function HealBody(slot, spellID)
    if RES_SLOTS[slot] then
        return ns.GroupFirst(("#showtooltip\n/cast [@mouseover,help,dead][help,dead][] {s:%d}"):format(spellID))
    end
    return ns.GroupFirst(("#showtooltip\n/cast [@mouseover,help,nodead][help,nodead][@player] {s:%d}"):format(spellID))
end

-- Aus ezHeals Vorlagen → Liste | nil (ezHeal nicht geladen oder ohne Vorlage für diese Klasse)
local function FromHeal()
    local api = Core.API and Core.API("ezHeal")
    if type(api) ~= "table" or type(api.Template) ~= "function" then return nil end
    local ok, rows = pcall(api.Template, "all", ns.playerClass)
    if not ok or type(rows) ~= "table" or #rows == 0 then return nil end
    local list = {}
    for _, row in ipairs(rows) do
        local spellID = type(row) == "table" and tonumber(Plain(row.spellID))
        local slot = type(row) == "table" and Plain(row.slot)
        if spellID and type(slot) == "string" then
            local spell = ns.SpellName(spellID) or Plain(row.name) or ("#" .. spellID)
            local name = ns.Truncate(spell, ns.MACRO_NAME_MAX - 5) .. " (MO)"
            local keyText = ClickCast.KeyText(row.button, row.modifiers)
            local entry = generated[slot] or { id = "clickheal_" .. slot }
            entry.category, entry.group = "general", "clickheal"
            entry.name = { name, name }
            entry.body = HealBody(slot, spellID)
            entry.need = spellID
            entry.click = row.button and { row.button, row.modifiers } or nil
            entry.why = { L.CLICKHEAL_WHY:format(spell), L.CLICKHEAL_WHY:format(spell) }
            entry.desc = { L.CLICKHEAL_DESC:format(spell, keyText), L.CLICKHEAL_DESC:format(spell, keyText) }
            entry.source = "ezHeal"
            generated[slot] = entry
            list[#list + 1] = entry
        end
    end
    return #list > 0 and list or nil
end

-- Ohne ezHeal: die Maus-über-Makros deiner Klasse (Data\Classes.lua) als Hüllen in dieser Gruppe.
local function FromClass()
    local list = {}
    for _, entry in ipairs(ns.MACROS) do
        if entry.category == "class" and entry.group == ns.playerClass and ClickCast.IsClickMacro(entry.body) then
            local wrapper = wrapped[entry]
            if not wrapper then
                wrapper = setmetatable({ category = "general", group = "clickheal", source = "class" }, { __index = entry })
                wrapped[entry] = wrapper
            end
            list[#list + 1] = wrapper
        end
    end
    return list
end

-- Einträge der Gruppe → Liste, Quelle ("ezHeal" | "class")
function ClickCast.Entries()
    local list = FromHeal()
    if list then return list, "ezHeal" end
    return FromClass(), "class"
end
