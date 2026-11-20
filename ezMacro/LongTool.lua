local _, ns = ...
local L = ns.L
local UI = ns.UI

-- Werkzeug „Lange Makros“ (V-099): zeigt, welche Makros in Blizzards Makroverwaltung nur ein „/click ezMacroLong<n>“
-- sind – ihr Text liegt in ezMacro und wirkt nur, solange ezMacro geladen ist. Teilen zeigt den ganzen Text,
-- „Als Vorlage“ legt ihn zu den eigenen Vorlagen (dort bleibt er auch, wenn das Makro gelöscht wird).

local function Items()
    local items = {}
    for _, entry in ipairs(ns.Long.List()) do
        local macro = entry.macro
        local scope = ns.Import.ScopeLabel(macro.perChar)
        items[#items + 1] = {
            key = (macro.perChar and "c:" or "a:") .. macro.name,
            icon = macro.icon or ns.DEFAULT_ICON,
            text = macro.name,
            sub = entry.missing and (scope .. "  ·  " .. L.LONG_MISSING) or L.LONG_SUB:format(scope, entry.chars),
            grey = entry.missing,
            tip = entry.missing and L.LONG_MISSING_TIP or nil,
            entry = entry,
        }
    end
    return items
end

local function Selected(panel)
    local item = panel.list:Selected()
    return item and item.entry
end

ns.Tools.Register({
    key = "long", order = 25, icon = { "INV_Scroll_03", "INV_Misc_Note_01" },
    name = L.TOOL_LONG, why = L.TOOL_LONG_WHY, desc = L.TOOL_LONG_DESC,
    status = function()
        local n = ns.Long.Count()
        if n == 0 then return L.LONG_NONE end
        return L.LONG_STATUS:format(n)
    end,
    build = function(panel)
        panel.share = UI.Button(panel, L.BTN_SHARE, 100, function()
            local entry = Selected(panel)
            if entry and entry.body then ns.Share(entry.macro.name, entry.body) end
        end, L.BTN_SHARE, L.BTN_SHARE_TIP)
        panel.share:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, -2)
        panel.template = UI.Button(panel, L.BTN_TEMPLATE, 120, function()
            local entry = Selected(panel)
            if not (entry and entry.body) then return end
            local custom = ns.Custom.FromMacro(entry.macro.index)
            if custom then
                ns.Print(L.CUSTOM_ADDED:format(custom.name))
                ns.Browser.ShowEntry(custom, true)
            end
        end, L.BTN_TEMPLATE, L.BTN_TEMPLATE_TIP)
        panel.template:SetPoint("LEFT", panel.share, "RIGHT", 4, 0)

        panel.list = UI.List(panel, "ezMacroLongList", panel.width, function() ns.Tools.RefreshKey("long") end)
        panel.list.frame:SetPoint("TOPLEFT", panel.top, "BOTTOMLEFT", 0, -8)
        panel.list.frame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 26)
    end,
    refresh = function(panel)
        panel.list:SetItems(Items(), L.LONG_EMPTY)
        local entry = Selected(panel)
        local usable = entry ~= nil and entry.body ~= nil
        panel.share:SetEnabled(usable)
        panel.template:SetEnabled(usable)
    end,
})
