local _, ns = ...
local L = ns.L
local Core = ezCore

-- Eigene Vorlagen (Reiter „Makros“, Auswahl „Nur Eigene“): selbst geschriebene Makros, aus geteiltem Text übernommene, aus
-- vorhandenen Makros kopierte und Ergebnisse des Bedingungs-Baukastens. Sie stehen in ezMacroDB.custom
-- (allgemein für alle Twinks) und verhalten sich im Browser wie die mitgelieferten Makros: anpassen,
-- übernehmen, teilen. Über 255 Zeichen werden sie beim Übernehmen ein langes Makro (Long.lua).
local Custom = {}
ns.Custom = Custom
local Macros = ns.Macros

-- Umschlag eines geteilten Makros in ezCores Textform (Core.Pack/Core.Unpack, MACRO-04): Art und Fassung.
-- Ein Text mit höherer Fassung stammt aus einem neueren ezMacro.
Custom.KIND = "ezMacro.macro"
Custom.VERSION = 1

local function Store()
    local store = ns.db.custom
    store.list = type(store.list) == "table" and store.list or {}
    store.next = tonumber(store.next) or 1
    return store
end

-- Einträge in der Reihenfolge des Anlegens (Felder wie die Daten in Data\*.lua, dazu custom = true).
function Custom.Entries()
    return Store().list
end

function Custom.Find(id)
    for _, entry in ipairs(Store().list) do
        if entry.id == id then return entry end
    end
    return nil
end

-- Belegt sind die Namen der eigenen Vorlagen und die der Makros aus deinen Fähigkeiten (Fund 2 des Reviews vor dem Merge
-- von modul/ezmacro-reste): Ein erzeugter Eintrag weicht eigenen Vorlagen aus (SpellMacros.UniqueNames) und fände sein
-- angelegtes WoW-Makro, das nur über den Namen gebunden ist (Import.Find), sonst nicht mehr – „Als eigene Vorlage
-- speichern“ an ihm gäbe der Kopie seinen Namen, und erneutes Übernehmen legte ein zweites Makro an.
local function NameTaken(name)
    for _, entry in ipairs(Store().list) do
        if entry.name == name then return true end
    end
    local SM = ns.SpellMacros
    for _, entry in ipairs(SM and type(SM.Entries) == "function" and SM.Entries() or {}) do
        if ns.EntryName(entry) == name then return true end
    end
    return false
end

-- Freier Name: „Neues Makro“, „Neues Makro 2“ … (höchstens 16 Zeichen wie bei Blizzard). Die Suche macht ezCore
-- (Core.UniqueName mit format und maxChars, MACRO-03); Custom.FreeName bleibt als Weiterleitung. Endet der Name auf ein
-- Kürzel der Makros aus deinen Fähigkeiten („ (MO)“, „ (F)“; SpellMacros.SplitSuffix), steht die Zahl davor wie bei den
-- erzeugten Einträgen („X 2 (MO)“), und ein langer Name wird vor dem Kürzel gekürzt (Gegenprüfung des Pakets
-- modul/ezmacro-reste: aus „Sengender S (MO)“ wurde sonst „Sengender S (M 2“).
function Custom.FreeName(base)
    -- Namen aus fremdem Text ohne Farbcodes, Links, „|“ und Steuerzeichen (Core.CleanImportName, T6-5/P19)
    if base ~= nil then base = Core.CleanImportName(tostring(base)) end
    local SM = ns.SpellMacros
    local suffix
    if base ~= nil and SM and type(SM.SplitSuffix) == "function" then base, suffix = SM.SplitSuffix(base) end
    return Core.UniqueName(base or L.CUSTOM_NEW_NAME, NameTaken,
        { format = "%s %d", maxChars = ns.MACRO_NAME_MAX, default = L.CUSTOM_NEW_NAME, suffix = suffix })
end

function Custom.Add(name, body, icon, why)
    local store = Store()
    local entry = {
        id = "custom:" .. store.next,
        category = "custom",
        custom = true,
        name = ns.Import.CleanName(name ~= nil and name ~= "" and name or Custom.FreeName()),
        body = ns.Import.CleanBody(body),
        icon = type(icon) == "number" and icon or nil,
        why = why,
        desc = "",
        created = Core.Now(),
    }
    store.next = store.next + 1
    table.insert(store.list, entry)
    ns.NamesChanged()
    ns.Fire("CUSTOM_CHANGED", entry)
    return entry
end

function Custom.Remove(entry)
    local list = Store().list
    for index, other in ipairs(list) do
        if other == entry or other.id == entry.id then
            table.remove(list, index)
            if ns.db.window.selected then ns.db.window.selected.custom = nil end
            ns.NamesChanged()
            ns.Fire("CUSTOM_CHANGED")
            return true
        end
    end
    return false
end

function Custom.Save(entry, name, body)
    entry.name = name
    entry.body = body
end

-- Neue, leere Vorlage mit einem Gerüst, das zeigt, wie es geht.
function Custom.New()
    return Custom.Add(Custom.FreeName(), L.CUSTOM_NEW_BODY)
end

-- Aus geteiltem Text (Macros.ShareText) oder einem einfach eingefügten Makrotext. Rückgabe: Eintrag oder nil, Fehler.
function Custom.FromText(text)
    -- Text aus ezCores Umschlag („EZ1:…“): ein Makro oder ein Leisten-Profil. Beide gehen durch Core.Unpack (Art und
    -- Fassung geprüft, MACRO-04); ein Profil liest Profiles.Import mit seiner eigenen Fassung.
    if type(text) == "string" and text:match("^%s*EZ%d+:") then
        local value = Core.Unpack(text, { ns.Profiles.KIND, Custom.KIND })
        if type(value) == "table" and value.kind == ns.Profiles.KIND then
            local imported, err = ns.Profiles.Import(text)
            if not imported then return nil, err end
            ns.Print(L.MACRO_PROFILE_IMPORTED:format(imported))
            return nil, nil, imported
        end
        if type(value) == "table" and value.v > Custom.VERSION then return nil, L.IMPORT_NEWER end
        if type(value) == "table" and type(value.body) == "string" then
            text = Macros.ShareText(type(value.name) == "string" and value.name or nil, value.body)
        else
            return nil, L.IMPORT_BAD
        end
    end
    local name, body = ns.Macros.ParseShareText(text or "")
    if body == "" then return nil, L.ERR_EMPTY_BODY end
    if #body > ns.LONG_MAX_CHARS then return nil, L.ERR_TOO_LONG:format(#body, ns.LONG_MAX_CHARS) end
    return Custom.Add(name and Custom.FreeName(name) or Custom.FreeName(), body)
end

-- Kopie eines vorhandenen Makros aus Blizzards Makroverwaltung (lange Makros mit ganzem Text).
function Custom.FromMacro(index)
    local name, icon = GetMacroInfo(index)
    if not name then return nil end
    return Custom.Add(Custom.FreeName(name), ns.Import.BodyOf(index), icon)
end

-- Dialog zum Einfügen eines geteilten Makros; legt daraus eine eigene Vorlage an und zeigt sie zum Anpassen.
function ns.ImportText()
    return ns.UI.TextDialog({
        title = L.IMPORT_TITLE,
        hint = L.IMPORT_HINT,
        text = "",
        accept = true,   -- ezCores „Übernehmen“ (L.TEXTDIALOG_ACCEPT, T18-22)
        onAccept = function(text)
            local entry, err, profile = Custom.FromText(text)
            if profile then
                ns.Browser.ShowEntry(ns.Tools.Get("profiles"))
                return
            end
            if not entry then
                ns.Print(err)
                return false
            end
            ns.Print(L.CUSTOM_ADDED:format(entry.name))
            if ns.Browser then ns.Browser.ShowEntry(entry, true) end
        end,
    })
end
