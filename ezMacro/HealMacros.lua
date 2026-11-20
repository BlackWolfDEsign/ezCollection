local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    ezHeals Heil-Makros im Reiter „Makros“ (Entscheidung des Nutzers vom 16.11.2026, Nr. 9: ezMacro zeigt ezHeals Makros
    über eine Schnittstelle an, statt eine zweite Liste zu führen; Bau in Welle 24 mit Entwurf A, Frage 14).

    Quelle ist ezHeals Leseschnittstelle aus Welle 23 (docs/roadmap/ezHeal.md, „Schnittstelle für ezMacro“):
      ezCore.API("ezHeal").HealMacros()            Liste (Kopie): key, name, icon, body, kind, badge, perChar, state, tip,
                                                   steps ({ name, id, mod }; das Symbol in der Liste)
      ezCore.API("ezHeal").CreateHealMacros(keys)  legt ohne Rückfrage an » true, { created, updated, same, foreign,
                                                   long, failed } | false, grund ("missing", "combat", "none", "full")
    ezMacro kopiert die Liste nicht, sondern liest sie bei jedem Zeichnen frisch (der Stand hängt an Blizzards
    Makroverwaltung). Läuft ezHeal nicht oder fehlt die Schnittstelle (älteres ezHeal), zeigt ezMacro nichts: Die
    Auswahl „Heil-Makros (ezHeal)“ fehlt dann im Reiter „Makros“, kein Fehler, kein leerer Eintrag.
    „Übernehmen“ fragt selbst (Core.Confirm) und ruft dann CreateHealMacros({ key }) – ezHeal legt das Makro an und
    merkt es sich als eigenes (es gilt danach für „ezHeal-Makros entfernen“). Anpassen und Klick-Zauber gibt es für
    diese Einträge nicht: Den Text baut ezHeal aus seinen Vorlagen, ein angepasster Text ginge beim nächsten
    Übernehmen verloren.

      HealMacros.Available()       » läuft ezHeal mit der Schnittstelle?
      HealMacros.Entries()         » Einträge für den Browser (frisch gelesen), leer ohne ezHeal
      HealMacros.Usable(entry)     » kann „Übernehmen“ etwas tun? (Zustand „new“ oder „update“)
      HealMacros.StateText(entry)  » Hinweis zum Zustand (deutsch/englisch) oder nil
      HealMacros.Apply(entry)      Rückfrage, dann anlegen bzw. aktualisieren über ezHeal
]]
local HealMacros = {}
ns.HealMacros = HealMacros

HealMacros.CATEGORY = "heal"
HealMacros.PREFIX = "heal:"          -- Kennung im Browser: heal:<Schlüssel aus ezHeal>

local function API()
    local api = Core.API and Core.API("ezHeal")
    if type(api) == "table" and type(api.HealMacros) == "function" and type(api.CreateHealMacros) == "function" then
        return api
    end
    return nil
end

function HealMacros.Available()
    return API() ~= nil
end

local STATES = { new = true, update = true, same = true, foreign = true, long = true }

-- ezHeal liefert als Symbol das Fragezeichen (mit #showtooltip zeigt das Makro im Spiel den Zauber selbst). Die Liste
-- zeigt darum das Symbol des Zaubers, den das Makro ohne Umschalttaste wirkt: erster Schritt ohne mod, sonst der erste.
-- Ob es das Fragezeichen ist, sagt ezCore (Core.IsFallbackIcon: Datei-ID, Pfad oder alter Name; Gegenprüfung P19a zu
-- T16-8 – vorher eine eigene Kopie des Namens hier, die den Pfad und die Datei-ID nicht erkannte).

local function StepSpell(steps)
    if type(steps) ~= "table" then return nil end
    local first
    for _, step in ipairs(steps) do
        local id = type(step) == "table" and tonumber(Core.Plain(step.id)) or nil
        if id then
            first = first or id
            if step.mod == nil then return id end
        end
    end
    return first
end

-- Ein Makro aus ezHeals Liste als Browser-Eintrag; Fremdes (falsche Felder) fällt weg.
local function ToEntry(macro)
    if type(macro) ~= "table" then return nil end
    local key, name, body = Core.Plain(macro.key), Core.Plain(macro.name), Core.Plain(macro.body)
    if type(key) ~= "string" or key == "" or type(name) ~= "string" or name == "" or type(body) ~= "string" then
        return nil
    end
    local tip, icon, state = Core.Plain(macro.tip), Core.Plain(macro.icon), Core.Plain(macro.state)
    return {
        id = HealMacros.PREFIX .. key, key = key, category = HealMacros.CATEGORY, heal = true,
        name = name, body = body, icon = type(icon) == "string" and icon ~= "" and not Core.IsFallbackIcon(icon) and icon or nil,
        iconSpell = StepSpell(macro.steps),   -- Symbol in der Liste (ns.EntryIcon), solange icon fehlt
        why = type(tip) == "string" and tip ~= "" and tip or L.HEAL_WHY,
        state = STATES[state] and state or nil,
        perChar = macro.perChar ~= false,
        need = false,            -- „gelernt?“: ezHeal baut nur aus Gelerntem
    }
end

function HealMacros.Entries()
    local api = API()
    if not api then return {} end
    local ok, list = pcall(api.HealMacros)
    if not ok or type(list) ~= "table" then return {} end
    local out = {}
    for _, macro in ipairs(list) do
        local entry = ToEntry(macro)
        if entry then out[#out + 1] = entry end
    end
    return out
end

function HealMacros.Usable(entry)
    return type(entry) == "table" and entry.heal == true and (entry.state == "new" or entry.state == "update")
end

-- Hinweis zum Zustand (Texte HEAL_STATE_<zustand>); für „neu“ keiner.
function HealMacros.StateText(entry)
    if type(entry) ~= "table" or not entry.heal or entry.state == nil or entry.state == "new" then return nil end
    local text = L["HEAL_STATE_" .. entry.state]
    if type(text) == "string" and text ~= "HEAL_STATE_" .. entry.state then return text end
    return nil
end

local function Report(name, ok, result)
    if not ok then
        local why = L["HEAL_ERR_" .. tostring(result)]
        if type(why) ~= "string" or why == "HEAL_ERR_" .. tostring(result) then why = tostring(result) end
        ns.Print(L.HEAL_FAILED:format(name, why))
        return
    end
    result = type(result) == "table" and result or {}
    if (tonumber(result.created) or 0) > 0 then
        ns.Print(L.HEAL_CREATED:format(name))
    elseif (tonumber(result.updated) or 0) > 0 then
        ns.Print(L.HEAL_UPDATED:format(name))
    elseif (tonumber(result.same) or 0) > 0 then
        ns.Print(L.HEAL_SAME:format(name))
    elseif (tonumber(result.foreign) or 0) > 0 then
        ns.Print(L.HEAL_FAILED:format(name, L.HEAL_STATE_foreign))
    elseif (tonumber(result.long) or 0) > 0 then
        ns.Print(L.HEAL_FAILED:format(name, L.HEAL_STATE_long))
    else
        ns.Print(L.HEAL_FAILED:format(name, L.HEAL_ERR_failed))
    end
end

-- „Übernehmen“: Rückfrage, dann ezHeal anlegen bzw. aktualisieren lassen. → true (Rückfrage gezeigt) | false
function HealMacros.Apply(entry)
    if type(entry) ~= "table" or not entry.heal then return false end
    local api = API()
    if not api then
        ns.Print(L.HEAL_FAILED:format(tostring(entry.name), L.HEAL_ERR_missing))
        return false
    end
    if ns.InCombat() then
        ns.CombatNotice()
        return false
    end
    if not HealMacros.Usable(entry) then
        ns.Print(L.HEAL_FAILED:format(entry.name, HealMacros.StateText(entry) or L.HEAL_ERR_failed))
        return false
    end
    local key, name = entry.key, entry.name
    Core.Confirm(L.HEAL_CONFIRM:format(name), function()
        local call = API()
        if not call then return Report(name, false, "missing") end
        local okCall, ok, result = pcall(call.CreateHealMacros, { key })
        if not okCall then return Report(name, false, "failed") end
        Report(name, ok == true, result)
        ns.Fire("HEAL_MACROS_CHANGED")
    end)
    return true
end
