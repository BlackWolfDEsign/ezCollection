local ADDON, ns = ...
local L = ns.L
local Core = ezCore
local UI = ns.UI

-- Leisten-Profile (wie Myslot): Aktionsleisten samt Makros und auf Wunsch der Tastenbelegung unter einem Namen
-- speichern und auf einem anderen Charakter laden. Seit dem Architektur-Review vom 22.11.2026 (Entscheidung des Nutzers
-- vom 22.11.2026) ein Dienst in ezCore (Core.BarProfiles, ezCore/Charakter/BarProfiles.lua): Speicher in
-- ezCoreDB.barProfiles, einmalige Übernahme aus ezMacroDB.profiles (der Altbestand bleibt liegen), Erfassen, Laden nach
-- **einer** Rückfrage nur außerhalb des Kampfes, Text. ezBars nutzt denselben Dienst direkt, auch ohne ezMacro.
-- Hier bleiben das Werkzeug „Leisten-Profile“ (Liste, Knöpfe, Häkchen), der Dialog „Als Text“ und die Weiterleitungen
-- (Leitlinie 8: jede bisherige Funktion bleibt unter ihrem Namen). ezMacro meldet beim Dienst an: lange Makros
-- (Long.lua, über 255 Zeichen), seine drei Einstellungen als Standard fürs Laden und das Auffrischen des Werkzeugs.
local Profiles = {}
ns.Profiles = Profiles

local BP = Core.BarProfiles

-- Meldungen des Dienstes erscheinen als „ezMacro:“, wenn ezMacro sie auslöst.
local function WithOwner(opts)
    local out = {}
    for key, value in pairs(type(opts) == "table" and opts or {}) do out[key] = value end
    out.owner = out.owner or ADDON
    return out
end

---------------------------------------------------------------------------
-- Weiterleitungen auf ezCore (Core.BarProfiles)
---------------------------------------------------------------------------

Profiles.KIND = BP.KIND
Profiles.VERSION = BP.VERSION
Profiles.MACROS_PER_PAGE = BP.MACROS_PER_PAGE   -- nur lesen: die Seitengröße der Rückfrage gilt aus BP.MACROS_PER_PAGE

function Profiles.CaptureSlot(slot) return BP.CaptureSlot(slot) end
function Profiles.Capture(slots) return BP.Capture(slots) end
function Profiles.Remap(data, order, targets) return BP.Remap(data, order, targets) end
function Profiles.Save(name, opts) return BP.Save(name, WithOwner(opts)) end
function Profiles.Get(name) return BP.Get(name) end
function Profiles.Names() return BP.Names() end
function Profiles.Count(profile) return BP.Count(profile) end
function Profiles.Delete(name) return BP.Delete(name, WithOwner()) end
function Profiles.ShareName(profile) return BP.ShareName(profile) end
function Profiles.Export(name) return BP.Export(name) end
function Profiles.CleanSlot(data) return BP.CleanSlot(data) end
function Profiles.KeyFormat(key) return BP.KeyFormat(key) end
function Profiles.CleanKey(key) return BP.CleanKey(key) end
function Profiles.Import(value) return BP.Import(value) end
function Profiles.PlaceSpell(slot, id) return BP.PlaceSpell(slot, id) end
function Profiles.Place(data, opts) return BP.Place(data, WithOwner(opts)) end
function Profiles.BindingSet() return BP.BindingSet() end
function Profiles.BindingSetText() return BP.BindingSetText() end
function Profiles.BindingPlan(list) return BP.BindingPlan(list) end
function Profiles.Plan(profile, opts) return BP.Plan(profile, opts) end
function Profiles.MacroLines(plan) return BP.MacroLines(plan) end
function Profiles.KeepLine(plan) return BP.KeepLine(plan) end
-- opts wie BP.Load; macros/bindings/clearEmpty fehlen → ezMacros Einstellungen (über BP.SetDefaults unten)
function Profiles.Load(name, opts) return BP.Load(name, WithOwner(opts)) end

---------------------------------------------------------------------------
-- Anmeldung beim Dienst
---------------------------------------------------------------------------

-- Lange Makros (Long.lua): der ganze Text beim Erfassen, Anlegen über 255 Zeichen beim Laden.
BP.SetMacroHelper({
    owner = ADDON,
    body = function(index) return ns.Import.BodyOf(index) end,
    write = function(name, icon, body, perChar) return ns.Import.Write(nil, name, icon, body, perChar) end,
    maxChars = function() return ns.Import.MaxChars() end,
    changed = function() ns.SettingChanged("macros") end,
})
-- Standard fürs Laden: die drei Häkchen im Werkzeug (Einstellungen profileMacros, profileBindings, profileClearEmpty)
BP.SetDefaults(function()
    local S = ns.S
    if type(S) ~= "table" then return nil end
    return { macros = S.profileMacros, bindings = S.profileBindings, clearEmpty = S.profileClearEmpty }
end)
BP.OnChange(function()
    if ns.Tools and ns.Tools.RefreshKey then ns.Tools.RefreshKey("profiles") end
end)

---------------------------------------------------------------------------
-- Als Text: Dialog
---------------------------------------------------------------------------

-- Dialog „Als Text“: zeigt das gewählte Profil zum Kopieren; eingefügter Text wird ein neues Profil.
function Profiles.TextDialog(name)
    local text = name and Profiles.Export(name) or ""
    return UI.TextDialog({
        title = L.PROFILE_TEXT_TITLE,
        hint = L.PROFILE_TEXT_HINT,
        text = text,
        select = text ~= "",
        accept = true,   -- ezCores „Übernehmen“ (L.TEXTDIALOG_ACCEPT, T18-22)
        onAccept = function(input)
            if text ~= "" and Core.Trim(input or "") == text then return true end   -- unverändert: nur schließen
            local imported, err = Profiles.Import(input)
            if not imported then
                ns.Print(err)
                return false
            end
            ns.Print(L.MACRO_PROFILE_IMPORTED:format(imported))
        end,
    })
end

---------------------------------------------------------------------------
-- Werkzeug „Leisten-Profile“
---------------------------------------------------------------------------

local function Items()
    local items = {}
    for _, name in ipairs(Profiles.Names()) do
        local profile = Profiles.Get(name)
        local slots, macros = Profiles.Count(profile)
        local who = profile.class and ns.ClassName(profile.class) or ""
        items[#items + 1] = {
            key = name,
            icon = ns.IconPath({ "INV_Misc_Book_09", "INV_Misc_Book_11" }),
            text = name,
            sub = L.PROFILE_ROW:format(slots, macros, who, Core.Ago(profile.time)),
            grey = profile.class ~= nil and profile.class ~= ns.playerClass,
            -- aus Text übernommen: ohne Absender (der Export nimmt ihn seit T6-4 nicht mehr mit)
            tip = profile.imported and L.PROFILE_ROW_TIP_IMPORTED
                or L.PROFILE_ROW_TIP:format(profile.charName or profile.char or "?"),
        }
    end
    return items
end

local function DefaultName()
    local info = Core.CharInfo(ns.charKey) or {}
    return ns.ClassName(ns.playerClass) .. " (" .. tostring(info.name or Core.ShortName(Core.selfName)) .. ")"
end

ns.Tools.Register({
    key = "profiles", order = 30, icon = { "INV_Misc_Book_09", "INV_Misc_Book_11" },
    name = L.TOOL_PROFILES, why = L.TOOL_PROFILES_WHY, desc = L.TOOL_PROFILES_DESC,
    status = function()
        -- Rücksicht (Leitlinie 9): Läuft Myslot (ezCore, Funktion „barProfiles“), sagt die Seite das. ezMacros Profile
        -- tun ohnehin nur etwas auf Knopfdruck – nichts läuft doppelt (Fund aus Welle 5: der Erste Start führt ezMacro
        -- bei Myslot als zurücktretend, die Seite sagte davon nichts).
        local other = ns.OtherFor("barProfiles")
        if other then return UI.Colored("ORANGE_FONT_COLOR", L.PROFILE_OTHER:format(other)) end
        local n = #Profiles.Names()
        return n == 0 and L.PROFILE_NONE or L.PROFILE_STATUS:format(n)
    end,
    build = function(panel)
        panel.clearEmpty = UI.SettingCheck(panel, "profileClearEmpty")
        panel.clearEmpty:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", -4, -4)
        panel.bindings = UI.SettingCheck(panel, "profileBindings")
        panel.bindings:SetPoint("BOTTOMLEFT", panel.clearEmpty, "TOPLEFT", 0, -2)
        panel.macros = UI.SettingCheck(panel, "profileMacros")
        panel.macros:SetPoint("BOTTOMLEFT", panel.bindings, "TOPLEFT", 0, -2)

        panel.save = UI.Button(panel, L.PROFILE_SAVE, 100, function()
            local selected = panel.list:Selected()
            Core.AskText(L.PROFILE_SAVE_ASK, selected and selected.key or DefaultName(), function(text)
                local name = Core.Trim(text or "")
                if name == "" then return end
                if Profiles.Get(name) then
                    Core.Confirm(L.PROFILE_OVERWRITE:format(name), function() Profiles.Save(name) end)
                else
                    Profiles.Save(name)
                end
            end, 40)
        end, L.PROFILE_SAVE, L.PROFILE_SAVE_TIP)
        panel.save:SetPoint("BOTTOMLEFT", panel.macros, "TOPLEFT", 4, 2)
        panel.load = UI.Button(panel, L.PROFILE_LOAD, 90, function()
            local item = panel.list:Selected()
            if item then Profiles.Load(item.key) end
        end, L.PROFILE_LOAD, L.PROFILE_LOAD_TIP)
        panel.load:SetPoint("LEFT", panel.save, "RIGHT", 4, 0)
        panel.delete = UI.Button(panel, Core.Word("DELETE"), 90, function()
            local item = panel.list:Selected()
            if item then Profiles.Delete(item.key) end
        end, Core.Word("DELETE"), L.PROFILE_DELETE_TIP)
        panel.delete:SetPoint("LEFT", panel.load, "RIGHT", 4, 0)
        panel.text = UI.Button(panel, L.PROFILE_TEXT, 100, function()
            local item = panel.list:Selected()
            Profiles.TextDialog(item and item.key)
        end, L.PROFILE_TEXT, L.PROFILE_TEXT_TIP)
        panel.text:SetPoint("LEFT", panel.delete, "RIGHT", 4, 0)

        panel.list = UI.List(panel, "ezMacroProfileList", panel.width, function() ns.Tools.RefreshKey("profiles") end,
            function(item) Profiles.Load(item.key) end)
        -- Unten: drei Häkchen (je 24 hoch) und die Knopfzeile – zusammen rund 98 Punkte.
        panel.list.frame:SetPoint("TOPLEFT", panel.top, "BOTTOMLEFT", 0, -8)
        panel.list.frame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 98)
    end,
    refresh = function(panel)
        panel.list:SetItems(Items(), L.PROFILE_EMPTY)
        local selected = panel.list:Selected() ~= nil
        local free = not ns.InCombat()
        panel.save:SetEnabled(free)
        panel.load:SetEnabled(selected and free)
        panel.delete:SetEnabled(selected)
        panel.macros.Refresh()
        panel.bindings.Refresh()
        panel.clearEmpty.Refresh()
    end,
})
