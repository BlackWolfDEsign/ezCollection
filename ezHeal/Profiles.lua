local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Benannte Profile der Klick-Belegung sichtbar machen (HL-08). Die Daten liefert ezCore (Core.ClickBindings.Save,
    Load, Delete, Profiles, Export, Import; gespeichert kontoweit in ezCoreDB, je Profil mit der Klasse des
    Charakters) – ezHeal baut nur die Oberfläche:
      Knopf „Vorlagen“ in Blizzards Fenster „Klick-Zauber“ → Untermenü „Profile der Klick-Belegung“ (PR.FillMenu)
      Einstellungsseite, Abschnitt „Profile“: Speichern unter …, Gespeicherte Profile (dasselbe Menü), Einfügen …
    Speichern unter einem Namen (Core.AskText; ein vorhandenes Profil nur nach Rückfrage überschreiben), Laden (nur
    außerhalb des Kampfes, mit Rückfrage; ezCore sichert vorher, „Zurück“ holt die Belegung wieder), Löschen (mit
    Rückfrage), Teilen und Einfügen als Text über Core.TextDialog. Kein eigenes Fenster (Leitlinie 1): Core.TextDialog
    ist ezCores gemeinsamer Text-Dialog.
    Die Rückfrage zum Laden listet die Belegung des Profils (Taste » Zauber bzw. Makro, höchstens PR.LIST_MAX Zeilen),
    die Meldung danach nennt, was ezCore ausließ (nicht per Klick wirkbar, Makro fehlt) und was Blizzards „Ziel“/„Menü“
    wich (Gesamtreview 18.11.2026, T4-NG5).
]]

local PR = {}
ns.Profiles = PR

PR.LIST_MAX = 10     -- Zeilen der Belegung in der Rückfrage zum Laden
PR.SKIP_MAX = 6      -- genannte Einträge in der Meldung „ausgelassen“ bzw. „wich“

local function CB() return Core.ClickBindings end

local function MaxName()
    local cb = CB()
    return cb and tonumber(cb.MAX_NAME) or 40
end

-- Grund als Text: „combat“ mit ezCores Kampfsatz, sonst eigene Texte der Profile, dann die allgemeinen von ezHeal (ERR_*), dann ezCores PROFILE_ERR_*
local function Explain(reason)
    reason = tostring(reason)
    if reason == "invalid" then return L.PROFILE_ERR_name:format(MaxName()) end
    if reason == "combat" then return ns.CombatText(L.APPLY_COMBAT_WHAT) end   -- ezCores Wortlaut (T18-1)
    return ns.Text("PROFILE_ERR_" .. reason) or ns.Text("ERR_" .. reason) or L.ERR_other:format(reason)
end
PR.Explain = Explain

-- Gespeicherte Profile → { { name, class, time, count } } (Kopie, nach Namen sortiert)
function PR.List()
    local cb = CB()
    local out = {}
    if not (cb and cb.Profiles) then return out end
    for _, profile in ipairs(cb.Profiles()) do
        out[#out + 1] = { name = profile.name, class = profile.class, time = profile.time,
            count = type(profile.list) == "table" and #profile.list or 0 }
    end
    return out
end

-- Text eines Eintrags im Menü: „Heilen (Priester, 9 Tasten)“
function PR.Label(info)
    local className = info.class and Core.ClassName(info.class) or "?"
    return L.PROFILE_ENTRY:format(tostring(info.name), tostring(className), tonumber(info.count) or 0)
end

-- Einträge als Zeilen „Umschalt + Linksklick » Blitzheilung“ (Tastentext und Inhalt aus ezCore); mehr als max: die
-- letzte Zeile nennt den Rest („… und 3 weitere“)
function PR.EntryLines(list, max)
    local cb = CB()
    local lines = {}
    if not (cb and type(list) == "table") then return lines end
    max = tonumber(max) or #list
    for index, entry in ipairs(list) do
        if index > max then
            lines[#lines + 1] = Core.More(#list - max)   -- „… und 3 weitere“ (gemeinsamer Text)
            break
        end
        if type(entry) == "table" then
            lines[#lines + 1] = cb.KeyText(entry.button, entry.modifiers) .. " " .. Core.ARROW .. " " .. cb.Describe(entry)
        end
    end
    return lines
end

-- Dieselben Einträge als Satzteil für eine Chatmeldung: „A, B und 3 weitere“ (Core.More in Satzform, ohne „… “)
function PR.EntryText(list, max)
    if type(list) ~= "table" then return "" end
    max = tonumber(max) or #list
    local head = {}
    for index = 1, math.min(max, #list) do head[index] = list[index] end
    local text = table.concat(PR.EntryLines(head), ", ")
    if #list > max then text = text .. " " .. Core.More(#list - max, true) end
    return text
end

---------------------------------------------------------------------------
-- Daten (auch für die Schnittstelle ezCore.API("ezHeal"))
---------------------------------------------------------------------------

-- Jetzige Belegung unter einem Namen merken → name | nil, grund (nur lesen: auch im Kampf erlaubt)
function PR.Save(name)
    local cb = CB()
    if not (cb and cb.Available()) then return nil, "missing" end
    return cb.Save(name)
end

-- Profil auf Blizzards Klick-Zaubern legen (ohne Rückfrage) → true | true, "same" | false, grund; dritter Wert wie bei
-- Core.ClickBindings.Set: { skipped, dropped } (ausgelassen bzw. Blizzards „Ziel“/„Menü“ gewichen). Nur außerhalb des
-- Kampfes: ezHeal schreibt nie im Kampf und merkt nichts vor. ezCore sichert vorher (owner = ezHeal), „Zurück“ holt
-- die alte Belegung; die Merkliste der Vorlagen wird „davor“ (Templates.lua, T.ProfileLoaded).
function PR.Load(name, opts)
    opts = type(opts) == "table" and opts or {}
    local cb = CB()
    if not (cb and cb.Writable()) then return false, "missing" end
    if Core.InCombat() then return false, "combat" end
    if not cb.Has(name) then return false, "unknown" end
    local ok, reason, detail = cb.Load(name, { owner = ADDON, quiet = opts.quiet })
    if not ok then return false, reason, detail end
    if reason ~= "same" then ns.Templates.ProfileLoaded() end
    -- Blizzards offenes Fenster lädt ezCore nach dem Schreiben selbst neu (Core.ClickBindings.Reload, T4-NG2)
    return true, reason, detail
end

function PR.Delete(name)
    local cb = CB()
    return cb ~= nil and cb.Delete(name) or false
end

-- Text eines Profils (ohne name: die jetzige Belegung) → text | nil, grund
function PR.Export(name)
    local cb = CB()
    if not (cb and cb.Export) then return nil, "missing" end
    return cb.Export(name)
end

-- Text als neues Profil → name | nil, grund (angewendet wird nichts)
function PR.Import(text, name)
    local cb = CB()
    if not (cb and cb.Import) then return nil, "missing" end
    return cb.Import(text, name)
end

-- Schnittstelle ezCore.API("ezHeal") um die Profile ergänzen (ohne Rückfrage; der Aufrufer fragt selbst):
--   Profiles() → { { name, class, time, count } }   SaveProfile(name) → name | nil, grund
--   LoadProfile(name, opts) → true | true, "same" | false, grund (nur außerhalb des Kampfes, ezCore sichert vorher)
--   DeleteProfile(name) → true | false   ExportProfile(name) → text | nil, grund (ohne name: die jetzige Belegung)
--   ImportProfile(text, name) → name | nil, grund (neues Profil, angewendet wird nichts)
if type(ns.API) == "table" then
    ns.API.Profiles = function() return PR.List() end
    ns.API.SaveProfile = function(name) return PR.Save(name) end
    ns.API.LoadProfile = function(name, opts) return PR.Load(name, opts) end
    ns.API.DeleteProfile = function(name) return PR.Delete(name) end
    ns.API.ExportProfile = function(name) return PR.Export(name) end
    ns.API.ImportProfile = function(text, name) return PR.Import(text, name) end
end

---------------------------------------------------------------------------
-- Sichtbare Wege (mit Rückfragen)
---------------------------------------------------------------------------

function PR.SaveNow(name)
    local saved, reason = PR.Save(name)
    if saved then
        ns.Print(L.PROFILE_SAVED:format(saved))
    else
        ns.Print(Explain(reason))
    end
    return saved, reason
end

-- Name für ein neues Profil erfragen; ein vorhandenes wird erst nach Rückfrage überschrieben
function PR.AskSave()
    local cb = CB()
    if not (cb and cb.Available()) then ns.Print(L.ERR_missing) return false end
    Core.AskText(L.PROFILE_SAVE_PROMPT:format(MaxName()), "", function(text)
        local name = type(text) == "string" and Core.Trim(text) or ""
        if name ~= "" and cb.Has(name) then
            Core.Confirm(L.PROFILE_OVERWRITE_ASK:format(name), function() PR.SaveNow(name) end)
        else
            PR.SaveNow(name)
        end
    end, MaxName())
    return true
end

function PR.LoadNow(name)
    local ok, reason, detail = PR.Load(name)
    if ok then
        ns.Print((reason == "same" and L.PROFILE_LOADED_SAME or L.PROFILE_LOADED):format(tostring(name)))
        -- was ezCore ausließ bzw. was „Ziel“/„Menü“ wich, nennen (T4-NG5; vorher still verschwiegen)
        local skipped = type(detail) == "table" and type(detail.skipped) == "table" and detail.skipped or {}
        local dropped = type(detail) == "table" and type(detail.dropped) == "table" and detail.dropped or {}
        if #skipped > 0 then
            ns.Print(L.PROFILE_SKIPPED:format(#skipped, PR.EntryText(skipped, PR.SKIP_MAX)))
        end
        if #dropped > 0 then
            ns.Print(L.PROFILE_DROPPED:format(#dropped, PR.EntryText(dropped, PR.SKIP_MAX)))
        end
    else
        ns.Print(Explain(reason))
    end
    return ok, reason, detail
end

-- Laden mit Rückfrage: nennt eine fremde Klasse und listet die Belegung des Profils (T4-NG5 – auch ein gerade
-- eingefügtes, fremdes Profil sieht man so vor dem Laden); im Kampf nur ein Hinweis
function PR.AskLoad(name)
    if Core.InCombat() then ns.CombatNotice(L.APPLY_COMBAT_WHAT) return false end
    local cb = CB()
    if not (cb and cb.Writable()) then ns.Print(L.ERR_missing) return false end
    local profile = cb.Profile(name)
    if not profile then ns.Print(L.PROFILE_ERR_unknown) return false end
    local prompt = L.PROFILE_LOAD_ASK:format(tostring(name))
    if profile.class and profile.class ~= Core.PlayerClass() then
        prompt = prompt .. "\n\n" .. L.PROFILE_OTHER_CLASS:format(tostring(Core.ClassName(profile.class) or profile.class))
    end
    if #profile.list == 0 then
        prompt = prompt .. "\n\n" .. L.PROFILE_LOAD_NONE
    else
        prompt = prompt .. "\n\n" .. L.PROFILE_LOAD_LIST .. "\n" .. table.concat(PR.EntryLines(profile.list, PR.LIST_MAX), "\n")
    end
    Core.Confirm(prompt, function() PR.LoadNow(name) end)
    return true
end

function PR.AskDelete(name)
    local cb = CB()
    if not (cb and cb.Has(name)) then ns.Print(L.PROFILE_ERR_unknown) return false end
    Core.Confirm(L.PROFILE_REMOVE_ASK:format(tostring(name)), function()
        if PR.Delete(name) then ns.Print(L.PROFILE_REMOVED:format(tostring(name))) end
    end, { alert = true })
    return true
end

-- Teilen: Text zum Kopieren im gemeinsamen Text-Dialog von ezCore (name = nil: die jetzige Belegung)
function PR.Share(name)
    local text, reason = PR.Export(name)
    if not text then ns.Print(Explain(reason)) return false end
    Core.TextDialog({ title = L.PROFILE_SHARE_TITLE, owner = ADDON, text = text, select = true, readOnly = true,
        hint = name and L.PROFILE_SHARE_HINT:format(tostring(name)) or L.PROFILE_SHARE_CURRENT_HINT })
    return true
end

-- Einfügen: Text in den Dialog, „Übernehmen“ legt ein neues Profil an (Fehler: Dialog bleibt offen, Grund im Chat)
function PR.AskImport()
    Core.TextDialog({ title = L.PROFILE_PASTE_TITLE, hint = L.PROFILE_PASTE_HINT, owner = ADDON, text = "", accept = true,
        onAccept = function(text)
            local name, reason = PR.Import(text)
            if not name then
                ns.Print(L.PROFILE_IMPORT_FAIL:format(Explain(reason)))
                return false
            end
            ns.Print(L.PROFILE_PASTED:format(name))
        end })
    return true
end

-- Menü der Profile (Untermenü am Knopf „Vorlagen“ und Knopf „Gespeicherte Profile“ der Einstellungsseite)
function PR.FillMenu(root)
    root:CreateButton(L.MENU_PROFILE_SAVE, function() PR.AskSave() end)
    local list = PR.List()
    if #list == 0 then
        root:CreateTitle(L.MENU_PROFILE_NONE)
    else
        root:CreateDivider()
        for _, info in ipairs(list) do
            local name = info.name
            local entry = root:CreateButton(PR.Label(info))
            entry:CreateButton(L.MENU_PROFILE_LOAD, function() PR.AskLoad(name) end)
            entry:CreateButton(L.MENU_PROFILE_SHARE, function() PR.Share(name) end)
            entry:CreateButton(L.MENU_PROFILE_DELETE, function() PR.AskDelete(name) end)
        end
    end
    root:CreateDivider()
    root:CreateButton(L.MENU_PROFILE_IMPORT, function() PR.AskImport() end)
    root:CreateButton(L.MENU_PROFILE_SHARE_CURRENT, function() PR.Share(nil) end)
end

-- Menü an einem Knopf öffnen (ohne Knopf: am Mauszeiger über Blizzards Einstellungsfenster)
function PR.OpenMenu(owner)
    owner = owner or rawget(_G, "SettingsPanel") or UIParent
    return Core.Menu.Open(owner, function(root)
        root:CreateTitle(L.MENU_PROFILES)
        PR.FillMenu(root)
    end)
end
