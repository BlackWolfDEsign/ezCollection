local _, ns = ...
local L = ns.L
local Core = ezCore
local UI = ns.UI

-- Werkzeug „Makros ohne Leiste“ (wie Macro Toolkit): Makros, die auf keinem Aktionsplatz liegen und auch
-- nicht per Taste oder Klick-Zauber belegt sind. Aufnehmen legt eines an den Mauszeiger (zum Ablegen auf
-- einer Leiste), Teilen zeigt den Text, Löschen fragt vorher nach.

local function FirstLine(body)
    for line in tostring(body or ""):gmatch("[^\n]+") do
        if not line:match("^%s*#") then return line end
    end
    return tostring(body or ""):match("^[^\n]*") or ""
end

local function Items()
    local items = {}
    for _, macro in ipairs(ns.Macros.Unused()) do
        items[#items + 1] = {
            key = (macro.perChar and "c:" or "a:") .. macro.name,
            icon = macro.icon or ns.DEFAULT_ICON,
            text = macro.name,
            sub = ns.Import.ScopeLabel(macro.perChar) .. "  ·  " .. FirstLine(ns.Import.BodyOf(macro.index)),
            macro = macro,
        }
    end
    return items
end

local function Selected(panel)
    local item = panel.list:Selected()
    return item and item.macro
end

ns.Tools.Register({
    key = "unused", order = 20, icon = { "INV_Misc_Spyglass_02", "INV_Misc_Spyglass_03" },
    name = L.TOOL_UNUSED, why = L.TOOL_UNUSED_WHY, desc = L.TOOL_UNUSED_DESC,
    status = function()
        local n = #ns.Macros.Unused()
        if n == 0 then return UI.Colored("GREEN_FONT_COLOR", L.UNUSED_NONE) end
        return L.UNUSED_STATUS:format(n)
    end,
    build = function(panel)
        panel.pickup = UI.Button(panel, L.UNUSED_PICKUP, 120, function()
            local macro = Selected(panel)
            if macro and ns.Macros.PickUp(macro.name, macro.perChar) then ns.Print(L.MSG_PICKUP) end
        end, L.UNUSED_PICKUP, L.UNUSED_PICKUP_TIP)
        panel.pickup:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, -2)
        panel.share = UI.Button(panel, L.BTN_SHARE, 100, function()
            local macro = Selected(panel)
            if macro then ns.Share(macro.name, ns.Import.BodyOf(macro.index)) end
        end, L.BTN_SHARE, L.BTN_SHARE_TIP)
        panel.share:SetPoint("LEFT", panel.pickup, "RIGHT", 4, 0)
        panel.delete = UI.Button(panel, Core.Word("DELETE"), 100, function()
            local macro = Selected(panel)
            if not macro then return end
            Core.Confirm(L.UNUSED_DELETE_CONFIRM:format(macro.name, ns.Import.ScopeLabel(macro.perChar)), function()
                ns.Macros.Delete(macro.name, macro.perChar)
                ns.Tools.RefreshKey("unused")
            end)
        end, Core.Word("DELETE"), L.UNUSED_DELETE_TIP)
        panel.delete:SetPoint("LEFT", panel.share, "RIGHT", 4, 0)

        panel.list = UI.List(panel, "ezMacroUnusedList", panel.width, function() ns.Tools.RefreshKey("unused") end,
            function(item) ns.Macros.PickUp(item.macro.name, item.macro.perChar) end)
        panel.list.frame:SetPoint("TOPLEFT", panel.top, "BOTTOMLEFT", 0, -8)
        panel.list.frame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 26)
    end,
    refresh = function(panel)
        panel.list:SetItems(Items(), L.UNUSED_EMPTY)
        local selected = Selected(panel) ~= nil
        local free = not ns.InCombat()
        panel.pickup:SetEnabled(selected and free)
        panel.share:SetEnabled(selected)
        panel.delete:SetEnabled(selected and free)
    end,
})
