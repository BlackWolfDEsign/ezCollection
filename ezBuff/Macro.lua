local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Vorlage „Durchbuffen“ je Klasse (Wunsch des Nutzers vom 15.11.2026: „für ezHeal und ezBuff für jede klasse presets
    für die macros zum healen und durchbuffen, recherchieren und einbauen“ – das Durchbuffen ist der Teil von ezBuff,
    das Heilen der von ezHeal).

    Das Makro hat keine eigene Logik (Leitlinie 2): Es drückt ezBuffs sicheren Knopf „Durchbuffen“ (Group.lua,
    ezBuffGroupNext) – „/click ezBuffGroupNext“. Der Knopf wirkt außerhalb des Kampfes den nächsten fehlenden Buff der
    Gruppe: erst was fehlt, dann was ausläuft, ab mehreren fehlenden Mitgliedern die Gruppenfassung, für jedes Ziel
    den Rang, den es annehmen darf; allein deine eigenen Buffs (Check.SoloNeeds). Je Klasse unterscheidet sich nur die
    Zeile #showtooltip: der Name des Buffs, für den das Makro steht – der erste gelernte Buff deiner Klasse aus ezCores
    Zauber-Wissen (Buffs auf andere vor Buffs nur auf dich, in ezCores Reihenfolge). Der Name kommt vom Client über die
    Zauber-ID (sprachfest) und steht ohne Rang da, so zeigt Blizzard den höchsten gelernten. Welche Klasse was gibt, steht
    nur in ezCore (Spells.BUFFS) – hier keine eigene Liste.

    Angelegt wird in Blizzards Makroverwaltung (das Original, Leitlinie 1) als Charakter-Makro, nur außerhalb des
    Kampfes. Steht dort schon ein Charakter-Makro mit diesem Namen und anderem Text, fragt ezBuff vor dem
    Überschreiben (Core.Confirm); ein allgemeines Makro gleichen Namens bleibt unberührt. Ist der Platz für
    Charakter-Makros voll, kommt ein Hinweis. Danach öffnet sich Blizzards Makrofenster (Core.OpenPanel("macro")),
    damit du das Makro auf eine Leiste ziehen kannst.

    Geschrieben wird über ezCores Dienst „Makro anlegen“ (Core.Macro, Welle 15; umgestellt in Welle 22): Plätze,
    Suche nach Namen und Schreiben stehen dort einmal für alle Module. Das Kennzeichen „Gruppe“ am Aktionsknopf meldet
    ezBuff selbst bei Core.MacroBadge an (Macro.RegisterBadge, unten).
]]

local Macro = {}
ns.Macro = Macro

-- Aus ezCore (Core.Macro; Gesamtreview 18.11.2026, T16-8 – vorher eigene Werte), die Namen bleiben:
Macro.ICON = Core.Macro.DEFAULT_ICON         -- Fragezeichen: mit #showtooltip zeigt das Makro den Zauber selbst
Macro.MAX_CHARS = Core.Macro.MAX_CHARS       -- Blizzards Grenze für den Text eines Makros (255)
Macro.MAX_NAME = 16              -- und für seinen Namen

-- Name des Makros in Blizzards Makroverwaltung (höchstens 16 Zeichen).
function Macro.Name()
    local name = L.MACRO_NAME
    if #name > Macro.MAX_NAME then name = name:sub(1, Macro.MAX_NAME) end
    return name
end

-- Buffs der Klasse, für die das Makro steht: { { key, target } } – Buffs auf andere zuerst, dann nur auf dich.
local function OrderedBuffs(class)
    local any, own = {}, {}
    for _, entry in ipairs(ns.Buffs.ClassBuffs(class)) do
        if type(entry) == "table" and entry.key then
            if entry.target == "self" then own[#own + 1] = entry else any[#any + 1] = entry end
        end
    end
    for _, entry in ipairs(own) do any[#any + 1] = entry end
    return any
end

-- Kann ezBuff für diese Klasse durchbuffen? Wahr, wenn ezCores Zauber-Wissen ihr einen Buff zuordnet (Jäger und
-- Schurke: keiner – ihre Aspekte, Gifte und Haltungen sind keine Buffs auf andere).
function Macro.Supported(class)
    return #OrderedBuffs(class or ns.playerClass) > 0
end

-- Zauber für #showtooltip: der erste Buff der Klasse mit einem gelernten Rang (Name und ID), sonst nil.
function Macro.TooltipSpell(class)
    for _, entry in ipairs(OrderedBuffs(class or ns.playerClass)) do
        local spell = ns.Buffs.BestRank(entry.key)
        if spell then
            local name = Core.Spells.Name(spell)
            if type(name) == "string" and name ~= "" then return name, spell end
        end
    end
    return nil
end

-- Text des Makros: #showtooltip mit dem Buff der Klasse (ohne gelernten Buff ohne Namen) und der Klick auf den Knopf.
function Macro.Body(class)
    local name = Macro.TooltipSpell(class)
    local head = name and ("#showtooltip " .. name) or "#showtooltip"
    return head .. "\n/click " .. ns.Group.NEXT_NAME
end

-- Plätze: allgemeine Makros (1 bis maxAccount) und Charakter-Makros (dahinter) – eine Rechnung in ezCore
-- (Core.Macro.Limits, Bausteine/Macros.lua; Auftrag aus Welle 15 an ezBuff, umgestellt in Welle 22).
local function Limits()
    return Core.Macro.Limits()
end

-- Blizzards Makrofenster öffnen – über ezCores Fenster-Dienst (Core.OpenPanel("macro"): lädt Blizzard_MacroUI bei
-- Bedarf, dann ShowMacroFrame, sonst MacroFrame selbst). Nur außerhalb des Kampfes.
function Macro.ShowWindow()
    if ns.InCombat() then return false end
    return Core.OpenPanel("macro", nil, true) == true
end

-- Ist Blizzards Makroverwaltung da? (CreateMacro, EditMacro, GetMacroIndexByName, GetMacroInfo, GetNumMacros)
function Macro.Available()
    for _, name in ipairs({ "CreateMacro", "EditMacro", "GetMacroIndexByName", "GetMacroInfo", "GetNumMacros" }) do
        if type(rawget(_G, name)) ~= "function" then return false end
    end
    return true
end

-- Index des gleichnamigen Charakter-Makros und sein Text, sonst nil. Ein allgemeines Makro gleichen Namens zählt
-- nicht: Das Makro der Vorlage ist klassengebunden (#showtooltip mit dem Buff der Klasse) und gehört zum Charakter.
-- GetMacroIndexByName liefert nur den ersten Treffer, und die allgemeinen Makros kommen vor denen des Charakters –
-- dann werden die Charakter-Makros einzeln nach dem Namen gefragt. Seit Welle 22 über ezCores Dienst „Makro anlegen“ (Core.Macro.Find, nur Charakter-Makros).
function Macro.Existing(name)
    return Core.Macro.Find(name, true)
end

-- Schreiben: über ezCores Dienst (Core.Macro.Write – die eine Stelle für CreateMacro/EditMacro; im Kampf schreibt er
-- nichts). Index oder nil.
function Macro.Write(index, name, body)
    return (Core.Macro.Write(name, Macro.ICON, body, true, index))
end

-- Knopf „Makro anlegen“ (Einstellungen » Gruppe, Rechtsklick-Menü am Knopf, /ezbuff makro): legt das Makro an bzw.
-- frischt es auf. force = true überschreibt ohne Rückfrage (nach der Rückfrage). Rückgabe: true/false, Grund:
-- "created" | "updated" | "same" | "ask" | "combat" | "none" | "api" | "full" | "long" | "failed".
function Macro.Create(force)
    if ns.InCombat() then
        ns.Print(L.MACRO_COMBAT)
        return false, "combat"
    end
    if not Macro.Supported() then
        ns.Print(L.MACRO_NONE)
        return false, "none"
    end
    if not Macro.Available() then
        ns.Print(L.MACRO_NO_API)
        return false, "api"
    end
    local name, body = Macro.Name(), Macro.Body()
    if #body > Macro.MAX_CHARS then
        ns.Print(L.MACRO_FAILED)
        return false, "long"
    end
    local index, old = Macro.Existing(name)
    if index and old == body then
        ns.Print(L.MACRO_SAME:format(name))
        Macro.ShowWindow()
        return true, "same"
    end
    if index and not force then
        Core.Confirm(L.MACRO_OVERWRITE:format(name), function() Macro.Create(true) end)
        return false, "ask"
    end
    if not index then
        local _, perChar = Core.Call(GetNumMacros)
        perChar = ns.Num(perChar) or 0
        local _, max = Limits()
        if perChar >= max then
            ns.Print(L.MACRO_FULL:format(max))
            return false, "full"
        end
    end
    local written = Macro.Write(index, name, body)
    if not written then
        ns.Print(L.MACRO_FAILED)
        return false, "failed"
    end
    ns.Print((index and L.MACRO_UPDATED or L.MACRO_CREATED):format(name))
    Macro.ShowWindow()
    return true, index and "updated" or "created"
end

-- Kennzeichen „Gruppe“ an Aktionsknöpfen mit diesem Makro (Core.MacroBadge, Welle 15): ezBuff meldet sich selbst an
-- (Auftrag aus Welle 15; vorher stand eine Übergangsregel in ezCore/Bausteine/MacroBadge.lua). Erkennung am Text
-- „/click ezBuffGroupNext“ (Group.NEXT_NAME), den Macro.Body schreibt. Rückgabe wie MacroBadge.Register.
function Macro.RegisterBadge()
    local MB = Core.MacroBadge
    if not (MB and type(MB.Register) == "function") then return false end
    return MB.Register("ezBuff", { kind = "group", body = "/click " .. ns.Group.NEXT_NAME }) == true
end

-- Tooltip des Knopfs: was das Makro tut, sein Text und für welchen Buff es steht.
function Macro.Tip()
    local lines = { L.OPT_MACRO_TIP }
    if not Macro.Supported() then
        lines[#lines + 1] = L.MACRO_NONE
    else
        lines[#lines + 1] = L.MACRO_TEXT:format(Macro.Name(), Macro.Body())
        if not ns.Group.Active() then lines[#lines + 1] = L.MACRO_GROUP_OFF end
    end
    return table.concat(lines, "\n\n")
end

-- Anmeldung beim Kennzeichen-Dienst, sobald ezBuff bereit ist (ersetzt ezCores Übergangsregel für „ezBuff“).
ns.OnReady(function() Macro.RegisterBadge() end)
