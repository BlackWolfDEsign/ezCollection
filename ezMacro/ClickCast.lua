local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Heilen und Buffen per Klick – der Makro-Teil von ezHeal in ezMacro (Welle 2b, Thema 6; Entscheidungen des Nutzers
    vom 13.11.2026: „ezHeal als eigenes schlankes Modul mit dem Makro-Teil in ezMacro“, ezHeal bleibt die Klick-Schicht
    für Heilen, Bannen und Wiederbeleben, Buffs zusätzlich in den Klick-Vorlagen).

    1. Knopf „Klick-Zauber“ im Makro-Browser (unter „Anpassen“): öffnet Blizzards Fenster „Klick-Zauber“ und hängt das
       gewählte Makro an den Mauszeiger (ClickCast.Hand); fehlt es in Blizzards Makroverwaltung, legt ezMacro es zuerst
       an. Die Taste wählt der Spieler in Blizzards Fenster wie aus dem Zauberbuch (Spieltest vom 23.11.2026); der Chat
       nennt dazu ezHeals Vorschlag, die Selbstwirk-Taste und ein fremdes Klick-Addon. Nur außerhalb des Kampfes.
       Bis zum 23.11.2026 hatte der Knopf ein eigenes Tastenmenü mit Rückfrage und schrieb über ezHeal bzw. ezCore
       (Entscheidung des Nutzers vom 23.11.2026: „menü weg wenn verhalten gleich bleibt“).

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

-- Empfohlene Tasten (Maustaste, Umschalttasten) für den Erklärtext (ClickCast.Guide). Links und Rechts ohne
-- Umschalttaste bleiben Blizzards „Ziel“ und „Menü“ und stehen deshalb nicht in der Liste. Keine Alt-Taste: Alt ist ab Werk Blizzards Selbstwirk-Taste, die
-- gedrückt jeden Klick-Zauber auf dich lenkt (Fehler des Nutzers vom 23.11.2026, Ursache in docs/roadmap/ezHeal.md);
-- an ihrer Stelle Maustaste 4 und 5 ohne Umschalttaste – ezHeals Vorlagen lassen sie frei.
ClickCast.KEYS = {
    { "left", "SHIFT" }, { "right", "SHIFT" }, { "left", "CTRL" }, { "right", "CTRL" },
    { "button4", nil }, { "button5", nil }, { "middle", nil }, { "middle", "SHIFT" },
}

-- Liegt die Taste auf Blizzards Selbstwirk-Taste (ezCore liest sie aus dem Client; ein Vorschlag aus ezHeal mit eigener
-- Wahl, oder der Spieler hat Umschalt/Strg als Selbstwirk-Taste)? Dann wirkt ein Klick-Zauber dort auf dich – der
-- Chat beim Knopf sagt es (ClickCast.HandText).
function ClickCast.HitsSelfCast(modifiers)
    local cb = Core.ClickBindings
    if type(cb) ~= "table" or type(cb.HitsSelfCast) ~= "function" or type(cb.SelfCastKey) ~= "function" then return false end
    local selfKey = cb.SelfCastKey()
    if selfKey == nil then return false end
    return cb.HitsSelfCast(modifiers, selfKey) ~= nil   -- ezCore: Selbstwirk-Taste oder nil
end

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
-- (ezCore: Core.WhoHandles("clickCast"), heute Clique), nennen Tooltip und Chat-Hinweis es. Der Knopf bleibt: Er
-- wirkt nur auf ausdrücklichen Wunsch; Blizzards Klick-Zauber und Clique können sich aber auf derselben Taste
-- überschneiden – das soll der Spieler vor dem Speichern wissen. → Name | nil
function ClickCast.Other()
    local name = ns.OtherFor("clickCast")     -- Gerüst: Core.WhoHandles, innen gesichert
    if type(name) == "string" and name ~= "" then return name end
    return nil
end

local Plain = Core.Plain   -- Wert nur, wenn er nicht geheim ist (ezCore, Leitlinie 2)

-- Tastentexte aus ezCore (Core.ClickBindings.KeyText samt Texten CLICK_MOD_*, CLICK_BUTTON_* in ezCores Locale; EC-109,
-- MACRO-20) – eine Fassung mit ezHeal. Der Name hier bleibt als Weiterleitung (Leitlinie 8). Das eigene Tastenmenü
-- (Menu, KeysFor, Ask, Run, Assign, Owner, CurrentOn, Describe) ist seit dem 23.11.2026 weg: Entscheidung des Nutzers
-- „menü weg wenn verhalten gleich bleibt“ – Blizzards Fenster „Klick-Zauber“ zeigt Belegung und Konflikte selbst.

-- „Umschalt + Linksklick“
function ClickCast.KeyText(button, modifiers)
    return Core.ClickBindings.KeyText(button, modifiers)
end

-- Roter Faden (Spieltest 20.11.2026, wörtlich „Klick-Zauber muss auch klar erklärt werden, wann wo(rahmen, makro,
-- fähigkeit) welche tasten(kombi) wie verwendet wird, sonst fehlt der rote faden und verständnis“): Leiste, Rahmen und
-- Fähigkeit in drei Zeilen, dazu die Tasten aus ClickCast.KEYS (eine Quelle für Text und Prüfung). → Text
-- Tasten, die schon belegt sind (von ezHeals Vorlagen oder von Hand, laut Blizzards Klick-Zaubern), fehlen in der
-- Empfehlung; sind alle belegt oder nennt das Spiel die Belegung nicht, stehen alle da (Durchsicht 24.11.2026).
function ClickCast.FreeKeys()
    local cb = Core.ClickBindings
    if type(cb) ~= "table" or type(cb.List) ~= "function" or type(cb.Find) ~= "function" then return ClickCast.KEYS, false end
    local list, complete = Core.Call(cb.List)
    local bits = type(cb.ModifierBits) == "function" and Core.Call(cb.ModifierBits)
    -- unvollständig gelesen oder Umschalttasten unbekannt: nichts „frei“ nennen
    if type(list) ~= "table" or complete == false or type(bits) ~= "table" then return ClickCast.KEYS, false end
    local free = {}
    for _, key in ipairs(ClickCast.KEYS) do
        if not Core.Call(cb.Find, list, key[1], key[2]) then free[#free + 1] = key end
    end
    if #free == 0 then return ClickCast.KEYS, false end
    return free, #free < #ClickCast.KEYS
end

function ClickCast.Guide()
    local keys = {}
    local list, some = ClickCast.FreeKeys()
    for _, key in ipairs(list) do keys[#keys + 1] = ClickCast.KeyText(key[1], key[2]) end
    return table.concat({ L.CLICK_GUIDE_HEAD, L.CLICK_GUIDE_BAR, L.CLICK_GUIDE_FRAME, L.CLICK_GUIDE_SPELL,
        (some and L.CLICK_GUIDE_KEYS_FREE or L.CLICK_GUIDE_KEYS):format(table.concat(keys, ", ")) }, "\n")
end

-- Knopf „Klick-Zauber“ wie Blizzards Klick-Zauber aus dem Zauberbuch (Spieltest vom 23.11.2026, wörtlich: „wieso
-- "klick-zauber" tasteneinstellungeN nicht wie bei klick-zauber(klickbelegunG) aus zauberbuch“; Leitlinie 1): öffnet
-- Blizzards Fenster „Klick-Zauber“ (Core.OpenPanel("clickbindings")) und hängt das Makro an den Mauszeiger
-- (PickupMacro, wie „auf Leiste ziehen“); fehlt es, legt ezMacro es zuerst an. Die Taste wählt der Spieler in Blizzards
-- Fenster: in die Liste klicken (Blizzard nimmt das Makro vom Zeiger in eine neue Zeile), mit der Tasten-Kombination auf
-- diese Zeile klicken, „Speichern“ (Blizzard_ClickBindingUI.lua, Zweig forever: AddFromCursorInfo). Der Chat sagt es
-- samt ezHeals Vorschlag und Blizzards Selbstwirk-Taste. An Blizzards Fenster ändert ezMacro nichts (Leitlinie 5).
function ClickCast.HandText(entry, name)
    local parts = { L.CLICK_HAND:format(name) }
    if type(entry) == "table" and type(entry.click) == "table" then
        local suggested = L.CLICK_TIP_SUGGESTED:format(ClickCast.KeyText(entry.click[1], entry.click[2]))
        if ClickCast.HitsSelfCast(entry.click[2]) then suggested = suggested .. " " .. Core.Red(L.CLICK_SELFCAST) end
        parts[#parts + 1] = suggested .. "."
    end
    local cb = Core.ClickBindings
    local selfKey = type(cb) == "table" and type(cb.SelfCastKey) == "function" and cb.SelfCastKey() or nil
    if selfKey then
        local text = type(cb.ModifierText) == "function" and cb.ModifierText(selfKey) or nil
        parts[#parts + 1] = L.CLICK_HAND_SELFCAST:format(Plain(text) or selfKey)
    end
    -- Leitlinie 9: läuft ein Addon, das die Klicks auf Rahmen selbst belegt (heute Clique), kann es sich mit Blizzards
    -- Klick-Zaubern auf derselben Taste überschneiden – das sagte bisher die Rückfrage des Menüs
    local other = ClickCast.Other()
    if other then parts[#parts + 1] = L.CLICK_OTHER_ADDON:format(other, other) end
    return table.concat(parts, " ")
end

-- → true | false (Kampf, kein Klick-Zaubern, Makro nicht anzulegen oder nicht aufzunehmen). Geht Blizzards Fenster nicht
-- auf, hängt das Makro trotzdem am Zeiger, und der Chat nennt den Weg über das Zauberbuch (Review vom 23.11.2026).
-- Klick-Zauber behalten die Maus-Kette immer (Schalter „Maus über“, Resolver.lua): Zeigt das Feld die Vorlage ohne
-- Maus, kommt die Fassung mit Kette und „(MO)“ auf die Taste – ohne sie wirkte der Klick auf das Ziel statt auf den
-- angeklickten Rahmen. Eine Anpassung des Spielers bleibt, wie sie ist. → Name, Text
function ClickCast.FullChain(entry, name, body)
    if type(entry) == "table" and ns.MouseoverActive(entry) == false and not ns.IsEdited(entry)
        and body == (ns.EntryBody(entry)) then
        return ns.MouseoverOtherName(entry) or name, (ns.Resolve(entry.body))
    end
    return name, body
end

function ClickCast.Hand(entry, name, body, perChar)
    name, body = ClickCast.FullChain(entry, name, body)
    if ns.InCombat() then
        ns.CombatNotice()
        return false
    end
    if not ClickCast.Available() then
        ns.Print(L.CLICK_FAILED:format(tostring(name), L.CLICK_ERR_missing))
        return false
    end
    name = ns.Import.CleanName(name)
    local function hand(index, existing)
        if not index or ns.InCombat() or type(PickupMacro) ~= "function" then return false end
        -- erst das Fenster (Blizzard ordnet dabei neu), dann der Zeiger. Sperrt ezCore das Öffnen von „Klick-Zauber“
        -- (Kern/Panels.lua, selfOnly mit OPEN_SELF_ONLY; seit dem Versuch vom 23.11.2026 aus): dann der Weg
        local opened, why = Core.OpenPanel("clickbindings", nil, true)
        ClearCursor()
        PickupMacro(index)
        local text = opened == true and ClickCast.HandText(entry, name) or L.CLICK_HAND_NOFRAME:format(name)
        if why == "self" and Core.Panels.SelfHint then
            text = L.CLICK_HAND_SELF:format(name) .. " " .. (Core.Panels.SelfHint("clickbindings") or "") .. " "
                .. ClickCast.HandText(entry, name)
        end
        if existing then text = text .. " " .. L.CLICK_HAND_EXISTING:format(name) end
        ns.Print(text)
        return true
    end
    -- Gibt es schon ein Makro dieses Namens, kommt genau dieses an den Zeiger (wie bisher beim Belegen); weicht sein
    -- Text ab, sagt es der Chat (vorher die Rückfrage des Menüs)
    local Import = ns.Import
    local index = Import.Find(name)
    if index then
        local differs = Import.CleanBody(Import.BodyOf(index) or "") ~= Import.CleanBody(body or "")
        return hand(index, differs)
    end
    local handed
    local ok = Import.Apply(entry, name, body, perChar, false, function(newIndex) handed = hand(newIndex) end)
    if handed ~= nil then return handed end
    return ok == true
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

-- Mitglied unter der Maus zuerst, nie auf das Ziel durchrutschen (ns.GroupFirst, Spieltest 15.11.2026). Die Kette baut
-- ezCores Makro-Logik (Spells.MacroCondition; Paket ezmacro/ssot-doppelungen – vorher fester Text hier):
-- Heilen „Maus, sonst Ziel, sonst du“, Wiederbeleben „tote Maus, sonst totes Ziel, sonst ohne Bedingung“.
local HEAL_CHAIN, RES_CHAIN = { "mouseover", "target", "player" }, { "mouseover", "target", "any" }
local function HealBody(slot, spellID)
    local Cond = Core.Spells.MacroCondition
    local cond = RES_SLOTS[slot] and Cond(nil, "dead", RES_CHAIN) or Cond(nil, "help", HEAL_CHAIN)
    return ns.GroupFirst(("#showtooltip\n/cast %s {s:%d}"):format(cond, spellID))
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

---------------------------------------------------------------------------
-- „Durchbuffen“ aus ezBuff im Reiter „Ein-Klick“ (Paket ezmacro/klickzauber-besitzer; Frage des Nutzers vom 20.11.2026:
-- „Zum Rahmen klick - ezheal und ezbuff - sind diese sinnvoll mit ezMacro nutzbar? --> so dass ich z.b. schnell alle
-- durchbuffen kann?“). Den Text liefert ezBuff (ezCore.API("ezBuff").GroupMacro: „#showtooltip <Buff>“ und
-- „/click ezBuffGroupNext“) – ezMacro baut nichts nach. Jeder Druck drückt ezBuffs sicheren Knopf: ein Buff je Druck
-- auf das nächste Mitglied, dem einer fehlt, nur außerhalb des Kampfes (ezBuff, Group.lua). Dieselbe Funktion liegt
-- auch auf einer eigenen Taste (Blizzards Tastaturbelegung „ezBuff: Durchbuffen“, ezCore.Keys „buffNext“).
---------------------------------------------------------------------------

-- Name des sicheren Knopfs aus ezCores Tastenliste (eine Stelle mit ezBuff und Core.MacroBadge)
local function GroupButton()
    local keys = Core.Keys
    local entry = keys and type(keys.Get) == "function" and keys.Get("buffNext") or nil
    return type(entry) == "table" and entry.button or nil
end

-- Text | nil, Grund ("noBuff": ezBuff läuft nicht, "no_groupBuff": deine Klasse hat keinen Buff auf andere)
function ClickCast.GroupBuffLines()
    local api = Core.API and Core.API("ezBuff")
    if type(api) ~= "table" or type(api.GroupMacro) ~= "function" then return nil, "noBuff" end
    local ok, text = Core.Try("ezMacro", "ClickCast.GroupBuffLines", api.GroupMacro)
    text = ok and Plain(text) or nil
    if type(text) ~= "string" or text == "" then return nil, "no_groupBuff" end
    return text
end

ns.Dynamic.Register("buffNext", ClickCast.GroupBuffLines)
do
    local button = GroupButton()
    if button then ns.OneClick.SHAPES.buffNext = "^#showtooltip[^\n]*\n/click " .. button:gsub("%W", "%%%0") .. "$" end
end
