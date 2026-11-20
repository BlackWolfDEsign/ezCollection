local _, ns = ...
local L = ns.L

--[[
    Andere Addons (LibDataBroker): Wie Titan zeigt ezPanel die LDB-Anzeigen
    und -Starter anderer Addons (Details, Atlas, DBM, Questie …) als Bausteine.
    ezPanel bringt LDB nicht selbst mit, sondern nutzt die Bibliothek, wenn ein
    anderes Addon sie geladen hat. Alle LDB-Bausteine sind zunächst aus und
    lassen sich per Rechtsklick auf die Leiste → Bausteine → Andere Addons
    einschalten. Rechtsklick geht an das Addon selbst, die ezPanel-Optionen
    öffnet Shift+Rechtsklick.
]]

local ldb

local function Text(obj)
    local text = obj.text
    if text == nil and obj.value ~= nil then
        text = tostring(obj.value)
        if obj.suffix and obj.suffix ~= "" then text = text .. " " .. obj.suffix end
    end
    if type(text) ~= "string" or ns.IsSecret(text) then text = "" end
    return text
end

local function MakeBlock(name, obj)
    if type(name) ~= "string" or type(obj) ~= "table" then return end
    local id = "ldb:" .. name
    if ns.blocks[id] then return end
    local isLauncher = obj.type == "launcher"
    local def = {
        id = id,
        name = obj.label or name,
        broker = true,
        obj = obj,
        noTitle = obj.OnTooltipShow ~= nil,
        label = isLauncher and (obj.label or name) or (obj.label or nil),
        defaults = { enabled = false, bar = "top", zone = "right", order = 900, label = isLauncher },
        ownRightClick = type(obj.OnClick) == "function",
    }

    function def:GetText()
        return Text(self.obj), self.obj.icon
    end

    if type(obj.OnTooltipShow) == "function" then
        function def:OnTooltip(tooltip)
            self.obj.OnTooltipShow(tooltip)
        end
    elseif type(obj.OnEnter) == "function" then
        function def:OnEnterCustom(frame)
            self.obj.OnEnter(frame)
        end
        function def:OnLeaveCustom(frame)
            if type(self.obj.OnLeave) == "function" then self.obj.OnLeave(frame) end
        end
    end

    if def.ownRightClick then
        function def:OnClick(button, frame)
            self.obj.OnClick(frame, button)
        end
    end

    ns.RegisterBlock(def)
end

local function OnCreated(_, name, obj)
    MakeBlock(name, obj)
end

local function OnChanged(_, name)
    local def = ns.blocks["ldb:" .. tostring(name)]
    if def then ns.QueueUpdate(def) end
end

ns.OnReady(function()
    ldb = LibStub and LibStub.GetLibrary and LibStub:GetLibrary("LibDataBroker-1.1", true)
    if not ldb then return end
    for name, obj in ldb:DataObjectIterator() do MakeBlock(name, obj) end
    ldb.RegisterCallback(ns, "LibDataBroker_DataObjectCreated", OnCreated)
    ldb.RegisterCallback(ns, "LibDataBroker_AttributeChanged", OnChanged)
end)
