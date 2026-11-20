local _, ns = ...
local L = ns.L
local Core = ezCore
local Buffs = ns.Buffs

--[[
    Buff zurückgeben (wie Manners): Bufft dich ein Spieler außerhalb deiner Gruppe, bietet der Knopf
    eine Minute lang an, ihm deinen Klassen-Buff zurückzugeben und mit Emote zu danken. Hast du nichts
    zu geben, bleibt das Danke. Gruppenmitglieder deckt die Gruppenprüfung ab (Checks.lua).
    Das Emote sendet ezCore (Core.PerformEmote, „/danke Name“; nie während der Chat-Sperre), höchstens einmal je
    erhaltenem Buff (Rebuff.Done).
]]

local Rebuff = {}
ns.Rebuff = Rebuff

local IsSecret = Core.IsSecret
local Value = ns.Value
local KEEP = 60                 -- Sekunden, so lange bleibt das Angebot
local givers = {}               -- [GUID] = { guid, name, at, key, class }
local thanked = {}              -- [GUID] = at des Buffs, für den schon gedankt wurde (höchstens ein Dank je Buff)
Rebuff.KEEP = KEEP

-- Ein anderes Addon dankt schon selbst (Manners, docs/fremd-addons.md): dann hält sich ezBuff zurück.
-- Erkennung über ezCore (Funktion „rebuffThanks“); Rückgabe: Name des Addons oder nil.
function Rebuff.OtherAddOn()
    return (ns.OtherFor("rebuffThanks"))
end

function Rebuff.Active()
    return ns.S ~= nil and ns.S.rebuff == true and not Rebuff.OtherAddOn()
end

-- Emote-Funktion (ezCore.PerformEmote(token, name) → true gesendet, false gesperrt), sonst nil.
function Rebuff.EmoteAPI()
    if type(Core.PerformEmote) == "function" then return Core.PerformEmote end
    return nil
end

-- Aktuelles Einheiten-Kürzel eines Spielers (Ziel, Namensplakette …), nil wenn nicht sichtbar.
function Rebuff.Token(guid)
    if not guid then return nil end
    local token = Value(UnitTokenFromGUID, guid)
    if type(token) == "string" then return token end
    local candidates = { "target", "focus", "mouseover" }
    for index = 1, 40 do candidates[#candidates + 1] = "nameplate" .. index end
    for _, unit in ipairs(candidates) do
        if Value(UnitGUID, unit) == guid then return unit end
    end
    return nil
end

-- Neue Aura auf dir: von einem fremden Spieler?
function Rebuff.Seen(aura)
    if IsSecret(aura) or type(aura) ~= "table" then return end
    local source, helpful, spellId, name = aura.sourceUnit, aura.isHelpful, aura.spellId, aura.name
    if IsSecret(source) or IsSecret(helpful) or IsSecret(spellId) or IsSecret(name) then return end
    if type(source) ~= "string" or helpful == false then return end
    if Value(UnitIsUnit, source, "player") or not Value(UnitIsPlayer, source) then return end
    if Value(UnitInParty, source) or Value(UnitInRaid, source) then return end
    local key = Buffs.KeyOf(spellId, name)
    if not key then return end   -- nur Buffs aus ezCores Buff-Gruppen (Klassen-Buffs, keine HoTs)
    local guid, unitName = Value(UnitGUID, source), ns.UnitFullName(source)
    if type(guid) ~= "string" or type(unitName) ~= "string" then return end
    local _, class = UnitClass(source)
    givers[guid] = { guid = guid, name = unitName, at = GetTime(), key = key,
        class = Core.Plain(class) }
    if ns.Check then ns.Check.Request() end
end

-- Was kann ich zurückgeben? Ein Klassen-Buff (für alle), den der Spieler noch nicht hat.
local function Gift(giver, token)
    local auras = token and Buffs.Scan(token)
    local level = token and ns.Num(UnitLevel(token)) or nil
    for _, group in ipairs(ns.Check.Groups(ns.playerClass)) do
        if group.target == "any" then
            local has = false
            for _, entry in ipairs(group.entries) do
                if auras and Buffs.Has(auras, entry.key, 0) then has = true end
            end
            if not has then
                local entry, spell = ns.Check.Choose(group, level)
                if entry then return entry, spell end
            end
        end
    end
    return nil
end

-- Klick-Aktion für den Knopf: mit Kürzel direkt (feste Einheit), sonst über ein Makro mit /targetexact. Das Makro
-- leert vorher das Ziel und wirkt nur auf ein vorhandenes Ziel: Findet /targetexact den Spieler nicht (zu weit weg),
-- wirkt es auf niemanden statt auf dein bisheriges Ziel (Spieltest des Nutzers vom 15.11.2026: nie auf das Ziel
-- ausweichen); /targetlasttarget holt dein Ziel zurück.
local REBUFF_MACRO = "/cleartarget\n/targetexact %s\n/cast [@target,exists] %s\n/targetlasttarget"
Rebuff.MACRO = REBUFF_MACRO
local function Action(giver, spell)
    local token = Rebuff.Token(giver.guid)
    if token then return { type = "spell", spell = spell, unit = token }, token end
    local spellName = Core.Spells.Name(spell)
    if not spellName then return nil end
    return { type = "macro", macrotext = REBUFF_MACRO:format(giver.name, spellName) }
end

function Rebuff.Tasks()
    local list, now = {}, GetTime()
    local emote = ns.S.thank and Rebuff.EmoteAPI() ~= nil
    for guid, at in pairs(thanked) do
        if now - at > KEEP then thanked[guid] = nil end
    end
    for guid, giver in pairs(givers) do
        if now - giver.at > KEEP then
            givers[guid] = nil
        else
            local token = Rebuff.Token(guid)
            local entry, spell = Gift(giver, token)
            local task = { kind = "rebuff", key = guid, guid = guid, target = giver.name, at = giver.at, thank = emote }
            if entry then
                task.label = L.REBUFF:format(Buffs.Name(entry, spell), giver.name)
                task.icon = Core.Spells.Icon(spell)
                task.spellName = Core.Spells.Name(spell)
                task.action = Action(giver, spell)
                -- Das Kürzel kann sich bis zum Klick ändern: der Knopf fragt vor dem Klick neu.
                task.refresh = function() return (Action(giver, spell)) end
            elseif emote then
                task.label = L.THANK:format(giver.name)
                task.thankOnly = true
            end
            if task.label then list[#list + 1] = task end
        end
    end
    table.sort(list, function(a, b) return a.at > b.at end)
    return list
end

-- Schon für diesen Buff gedankt? (Spender und Zeitpunkt des Buffs; gilt auch für eine neu gebaute Aufgabe.)
function Rebuff.Thanked(task)
    if type(task) ~= "table" then return false end
    return task.thanked == true or (task.guid ~= nil and thanked[task.guid] ~= nil and thanked[task.guid] == task.at)
end

-- Nach dem Klick: danken (ezCore.PerformEmote) und das Angebot schließen. Gedankt wird höchstens einmal je erhaltenem
-- Buff (Blizzards Regeln, Chat: kein Spam an andere Spieler): Ein zweiter Druck – Doppelklick, bevor die Prüfung die
-- Aufgabe abräumt, oder die Taste im Kampf, wo der Knopf seine Aufgabe bis nach dem Kampf behält – dankt nicht erneut.
-- Ein gesperrter Chat (PerformEmote ohne true) zählt nicht als Dank. Rückgabe: true, wenn jetzt gedankt wurde.
function Rebuff.Done(task)
    if not task or task.kind ~= "rebuff" then return false end
    local sent = false
    if task.thank and not Rebuff.Thanked(task) then
        local emote = Rebuff.EmoteAPI()
        -- Mit dem Spielernamen („/danke Name“); der Server nennt ihn nur in Reichweite.
        if emote then
            local ok, result = pcall(emote, "THANK", task.target)
            sent = ok and result == true
        end
        if sent then
            task.thanked = true
            if task.guid ~= nil and task.at ~= nil then thanked[task.guid] = task.at end
        end
    end
    givers[task.guid] = nil
    return sent
end

function Rebuff.Forget()
    wipe(givers)
    wipe(thanked)
end

ns.OnReady(function()
    local other = Rebuff.OtherAddOn()
    if ns.S.rebuff and other then ns.Print(L.STATUS_MANNERS:format(other)) end
    -- Gesperrte Einheit (W-04): nie vergleichen, hinter ns.OnUnit mit „player“ zählt sie als Treffer. Im Kampf ruht
    -- das Zurückgeben ohnehin; gesperrte Angaben der Aura selbst verwirft Rebuff.Seen.
    ns.OnUnit("UNIT_AURA", "player", function(_, unit, info)
        if ns.InCombat() or not Rebuff.Active() then return end
        if not IsSecret(unit) and unit ~= "player" then return end
        if IsSecret(info) or type(info) ~= "table" then return end
        local added = info.addedAuras
        if IsSecret(added) or type(added) ~= "table" then return end
        for _, aura in ipairs(added) do Rebuff.Seen(aura) end
    end)
end)
