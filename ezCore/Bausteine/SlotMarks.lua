local _, ns = ...
local Core = ezCore

--[[
    Platzmarken an Taschenplätzen – EINE Anmeldestelle (VP-37, Frage 18 – Empfehlung umgesetzt, Antwort offen;
    GEAR-09). Vorher gab es sie nur in ezBag (ezBag/Marks.lua, AddSlotMark); ohne ezBag zeichnete ezGear seinen
    Pfeil selbst an Blizzards Taschen, und Blizzards Bank (gepoolte BankPanel-Knöpfe) blieb leer.

    Läuft ezBag (Schnittstelle AddSlotMark), meldet ezCore jede Marke dort an – ezBag zeichnet sie in der
    zusammengefassten Tasche, Bank, Gildenbank und im ezBag-Fenster wie bisher. Ohne ezBag – und mit ezBag in Blizzards
    einzelnen Taschen (API("ezBag").MarksBags() = false) – zeichnet ezCore selbst: an Blizzards Taschenfenstern (hooksecurefunc auf UpdateItems je Fenster) und an Blizzards Bank
    (hooksecurefunc auf BankPanel.GenerateItemSlotsForSelectedTab und RefreshBankPanel, dazu BAG_UPDATE_DELAYED bei
    offener Bank). Taint-sicher: nur Hooks, eigene Texturen am Knopf, keine Werte in Blizzards Tabellen.

      SlotMarks.Add(key, { order, owner, fn })  → true; fn(itemID, link, bag, slot, quality) → nil oder Marke:
          { atlas, useAtlasSize } oder { texture }, dazu r, g, b, desaturate, rotation, x, y, sign (Schlüssel für
          Core.MarkSign) – dieselbe Form wie bei ezBag
      SlotMarks.Remove(key), SlotMarks.Keys(), SlotMarks.Refresh()
      SlotMarks.For(itemID, link, bag, slot, quality) → Marken für einen Platz (höchstens SlotMarks.MAX_SHOWN)
      SlotMarks.Apply(button, itemID, link, quality, bag, slot) → zeichnet sie oben links an einen Knopf
      SlotMarks.ViaEzBag()           → true, solange ezBag läuft (Bank, Gildenbank, ezBag-Fenster zeichnet dann ezBag)
      SlotMarks.BagsViaEzBag()       → true, solange ezBag auch die Taschen zeichnet (zusammengefasste Tasche)
      SlotMarks.ROTATION = true      → Marken dürfen rotation mitgeben (wie ezBags SLOT_MARK_ROTATION)
]]

local SlotMarks = {}
Core.SlotMarks = SlotMarks

SlotMarks.SIZE = 13
SlotMarks.MAX_SHOWN = 2
SlotMarks.ROTATION = true

local providers = {}
local forwarded = {}    -- key → true, wenn bei ezBag angemeldet
local hookedBags, hookedBank = {}, false

local function BagAPI()
    local api = Core.API and Core.API("ezBag")
    if type(api) == "table" and type(api.AddSlotMark) == "function" then return api end
    return nil
end

function SlotMarks.ViaEzBag()
    return BagAPI() ~= nil
end

-- Zeichnet ezBag die Marken auch in Blizzards Taschen? Nur in der zusammengefassten Tasche; stehen die Taschen einzeln,
-- zeichnet ezCore sie wie ohne ezBag (Durchsicht 24.11.2026 – vorher zeichnete dort niemand). Älteres ezBag: ja.
local function BagsViaEzBag()
    local api = BagAPI()
    if not api then return false end
    if type(api.MarksBags) ~= "function" then return true end
    return Core.Call(api.MarksBags) ~= false
end
SlotMarks.BagsViaEzBag = BagsViaEzBag

-- Reihenfolge der Anbieter (auch ezBags Marken)
function SlotMarks.Sort(list)
    table.sort(list, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.key < b.key
    end)
end

local function Forward(p)
    local api = BagAPI()
    if not api or forwarded[p.key] then return false end
    local ok, done = pcall(api.AddSlotMark, p.key, { order = p.order, owner = p.owner, corner = "TOPLEFT", fn = p.fn })
    if ok and done ~= false then
        forwarded[p.key] = true
        return true
    end
    if not ok then Core.Error(p.owner, done, "SlotMarks.Forward " .. p.key) end
    return false
end

function SlotMarks.Add(key, opts)
    if type(key) ~= "string" or type(opts) ~= "table" or type(opts.fn) ~= "function" then return false end
    SlotMarks.Remove(key)
    local p = { key = key, order = tonumber(opts.order) or 50, owner = opts.owner or key, fn = opts.fn }
    providers[#providers + 1] = p
    SlotMarks.Sort(providers)
    Forward(p)
    SlotMarks.Refresh()
    return true
end

function SlotMarks.Remove(key)
    for i = #providers, 1, -1 do
        if providers[i].key == key then table.remove(providers, i) end
    end
    if forwarded[key] then
        forwarded[key] = nil
        local api = BagAPI()
        if api and type(api.RemoveSlotMark) == "function" then pcall(api.RemoveSlotMark, key) end
    end
end

function SlotMarks.Keys()
    local list = {}
    for _, p in ipairs(providers) do list[#list + 1] = p.key end
    return list
end

function SlotMarks.For(itemID, link, bag, slot, quality)
    local list = {}
    if Core.IsSecret(itemID) or type(itemID) ~= "number" then return list end
    for _, p in ipairs(providers) do
        local ok, mark = true, nil
        if not p.failed then ok, mark = pcall(p.fn, itemID, link, bag, slot, quality) end
        if not ok then
            p.failed = true   -- einmal melden, sonst käme der Fehler für jeden Platz
            Core.Error(p.owner, mark, "SlotMark " .. p.key)
        elseif type(mark) == "table" and (mark.atlas or mark.texture) then
            mark.key = p.key
            list[#list + 1] = mark
            if #list >= SlotMarks.MAX_SHOWN then break end
        end
    end
    return list
end

-- Zeichen einer Marke (Farbenblind-Hilfe, EC-47): mark.sign; eine graue Marke (desaturate ohne Färbung) bekommt von sich
-- aus „muted“. → Zeichen oder nil
function SlotMarks.SignOf(mark)
    if type(mark) ~= "table" or type(Core.MarkSign) ~= "function" then return nil end
    local key = mark.sign
    if key == nil and mark.desaturate == true and mark.r == nil then key = "muted" end
    return Core.MarkSign(key)
end

--[[
    SlotMarks.NewDrawer() → Zeichner mit eigenen Texturen je Knopf (Durchsicht 24.11.2026, B10 Schritt 1: ezCore und ezBag
    zeichneten Marken mit zwei gleichen Fassungen; jeder behält seine Texturen, die Optik ist eine).
      drawer.Draw(button, list)     Marken (höchstens so viele, wie die Liste hat) am linken Rand untereinander; nil/{} räumt
      drawer.Has(button)            hat der Zeichner an diesem Knopf schon gezeichnet?
      drawer.Shown(button)          Zahl der sichtbaren Marken
      drawer.SignShown(button, i)   Zeichen neben der Marke i oder nil
]]
function SlotMarks.NewDrawer()
    local textures = setmetatable({}, { __mode = "k" })   -- [Knopf] = { Textur, … }
    local signs = setmetatable({}, { __mode = "k" })      -- [Knopf] = { FontString, … } (Zeichen neben der Marke)
    local drawer = {}

    local function Texture(button, i)
        local list = textures[button]
        if not list then
            list = {}
            textures[button] = list
        end
        local tex = list[i]
        if not tex then
            -- Unterebene 1: unter ezBags Grau-Schicht (Suche, Hervorheben), wie Blizzards Pfeil am Platz.
            tex = button:CreateTexture(nil, "OVERLAY", nil, 1)
            list[i] = tex
        end
        return tex
    end

    -- Zeichen i am Knopf zeigen (rechts neben der Marke tex) oder verstecken; legt den FontString erst bei Bedarf an.
    local function SetSign(button, i, tex, sign)
        local list = signs[button]
        if not sign then
            if list and list[i] then list[i]:Hide() end
            return
        end
        if not button.CreateFontString then return end
        if not list then
            list = {}
            signs[button] = list
        end
        local fs = list[i]
        if not fs then
            fs = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
            list[i] = fs
        end
        fs:SetText(sign)
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", tex, "RIGHT", 0, 0)
        fs:Show()
    end

    function drawer.Draw(button, list)
        list = list or {}
        local prev
        for i, mark in ipairs(list) do
            local tex = Texture(button, i)
            local atlasSize = mark.atlas and mark.useAtlasSize == true and tex.SetAtlas ~= nil
            if mark.atlas and tex.SetAtlas then
                tex:SetAtlas(mark.atlas, atlasSize)
            else
                tex:SetTexture(mark.texture)
            end
            if not atlasSize then tex:SetSize(SlotMarks.SIZE, SlotMarks.SIZE) end
            tex:ClearAllPoints()
            if prev then
                tex:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -1)
            else
                tex:SetPoint("TOPLEFT", button, "TOPLEFT", mark.x or (atlasSize and 0 or 2), mark.y or (atlasSize and 0 or -2))
            end
            prev = tex
            tex:SetVertexColor(mark.r or 1, mark.g or 1, mark.b or 1)
            if tex.SetDesaturated then tex:SetDesaturated(mark.desaturate == true) end
            -- Drehung je Marke (ezGear: roter Pfeil = Blizzards grüner Pfeil, um 180° gedreht); setzt wiederverwendete zurück
            if tex.SetRotation then tex:SetRotation(mark.rotation or 0) end
            tex:Show()
            SetSign(button, i, tex, SlotMarks.SignOf(mark))
        end
        local own = textures[button]
        if own then
            for i = #list + 1, #own do own[i]:Hide() end
        end
        -- Zeichen stehen nur an Marken mit Zeichen: die Liste kann Lücken haben ({ [2] = fs }), # wäre dann 0
        local text = signs[button]
        if text then
            for i, fs in pairs(text) do
                if i > #list then fs:Hide() end
            end
        end
        return #list
    end

    function drawer.Has(button) return textures[button] ~= nil end

    function drawer.Shown(button)
        local n = 0
        for _, tex in ipairs(textures[button] or {}) do
            if tex.IsShown and tex:IsShown() then n = n + 1 end
        end
        return n
    end

    function drawer.SignShown(button, i)
        local fs = signs[button] and signs[button][i or 1]
        if not (fs and fs.IsShown and fs:IsShown()) then return nil end
        return fs.GetText and fs:GetText() or nil
    end

    return drawer
end

local drawer = SlotMarks.NewDrawer()

function SlotMarks.Apply(button, itemID, link, quality, bag, slot)
    if type(button) ~= "table" or type(button.CreateTexture) ~= "function" then return 0 end
    return drawer.Draw(button, SlotMarks.For(itemID, link, bag, slot, quality))
end

-- Für Tests und /dump: wie viele Marken stehen am Knopf?
SlotMarks.Shown = drawer.Shown

---------------------------------------------------------------------------
-- Ohne ezBag: Blizzards Taschen und Bank; mit ezBag und einzelnen Taschen: nur die Taschen
---------------------------------------------------------------------------

local drewBags = false      -- hat ezCore schon Marken an Blizzards Taschen gezeichnet (dann räumt es sie, wenn ezBag übernimmt)

local function ApplySlot(button, bag, slot, viaEzBag)
    if viaEzBag or #providers == 0 then
        if drawer.Has(button) then SlotMarks.Apply(button, nil) end   -- eigene Marken räumen
        return
    end
    drewBags = true
    local info = C_Container and Core.Call(C_Container.GetContainerItemInfo, bag, slot)
    if type(info) ~= "table" or Core.IsSecret(info.itemID) then
        SlotMarks.Apply(button, nil)
        return
    end
    SlotMarks.Apply(button, info.itemID, Core.Plain(info.hyperlink), Core.Num(info.quality), bag, slot)
end

local function UpdateBagFrame(frame)
    if type(frame) ~= "table" or type(frame.EnumerateValidItems) ~= "function" then return end
    local viaEzBag = BagsViaEzBag()
    if viaEzBag and not drewBags then return end
    local ok, iterator, state, start = pcall(frame.EnumerateValidItems, frame)
    if not ok or type(iterator) ~= "function" then return end
    for _, button in iterator, state, start do
        if type(button) == "table" then
            local bag = button.GetBagID and Core.Call(button.GetBagID, button)
            local slot = button.GetID and Core.Call(button.GetID, button)
            if Core.Num(bag) and Core.Num(slot) then ApplySlot(button, bag, slot, viaEzBag) end
        end
    end
end
SlotMarks.UpdateBagFrame = UpdateBagFrame

local function BankPanel()
    local frame = rawget(_G, "BankFrame")
    local panel = (type(frame) == "table" and frame.BankPanel) or rawget(_G, "BankPanel")
    return type(panel) == "table" and panel or nil
end

local function UpdateBank()
    local panel = BankPanel()
    local pool = panel and panel.itemButtonPool
    if type(pool) ~= "table" or type(pool.EnumerateActive) ~= "function" then return end
    for button in pool:EnumerateActive() do
        if type(button) == "table" and button.GetBankTabID and button.GetContainerSlotID then
            local bag = Core.Call(button.GetBankTabID, button)
            local slot = Core.Call(button.GetContainerSlotID, button)
            if Core.Num(bag) and Core.Num(slot) then ApplySlot(button, bag, slot, SlotMarks.ViaEzBag()) end
        end
    end
end
SlotMarks.UpdateBank = UpdateBank

local function BlizzardBagFrames()
    local list = {}
    local combined = rawget(_G, "ContainerFrameCombinedBags")
    if combined then list[#list + 1] = combined end
    for i = 1, (rawget(_G, "NUM_TOTAL_BAG_FRAMES") or rawget(_G, "NUM_CONTAINER_FRAMES") or 13) do
        local frame = rawget(_G, "ContainerFrame" .. i)
        if frame then list[#list + 1] = frame end
    end
    return list
end

local function Safe(where, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then Core.Error(Core.name, err, where) end
end

function SlotMarks.Hook()
    for _, frame in ipairs(BlizzardBagFrames()) do
        if not hookedBags[frame] and type(frame.UpdateItems) == "function" then
            hooksecurefunc(frame, "UpdateItems", function(self) Safe("SlotMarks bags", UpdateBagFrame, self) end)
            hookedBags[frame] = true
        end
    end
    local panel = not BagAPI() and BankPanel() or nil       -- die Bank zeichnet ezBag immer selbst
    if panel and not hookedBank then
        local any = false
        for _, method in ipairs({ "GenerateItemSlotsForSelectedTab", "RefreshBankPanel" }) do
            if type(panel[method]) == "function" then
                hooksecurefunc(panel, method, function() Safe("SlotMarks bank", UpdateBank) end)
                any = true
            end
        end
        hookedBank = any
    end
end

local function BankShown()
    local frame = rawget(_G, "BankFrame")
    return type(frame) == "table" and type(frame.IsShown) == "function" and frame:IsShown() == true
end

SlotMarks.Refresh = Core.Throttle(function()
    local api = BagAPI()
    if api then
        for _, p in ipairs(providers) do Forward(p) end
        if type(api.RefreshMarks) == "function" then pcall(api.RefreshMarks) end
        if BagsViaEzBag() then return end
    end
    for frame in pairs(hookedBags) do
        if frame.IsShown and frame:IsShown() then UpdateBagFrame(frame) end
    end
    if not api and BankShown() then UpdateBank() end
end, 0.1, Core.name)

-- Nach dem Laden aller Module: Marken, die vor ezBag angemeldet wurden, dort nachreichen; sonst selbst zeichnen.
Core.Listen("CHARS_READY", function()
    if BagAPI() then
        for _, p in ipairs(providers) do Forward(p) end
    end
    SlotMarks.Hook()
end, "ezCore.SlotMarks")
ns.On("BANKFRAME_OPENED", function()
    if not BagAPI() then
        SlotMarks.Hook()
        C_Timer.After(0, function() Safe("SlotMarks bank", UpdateBank) end)
    end
end)
ns.On("BAG_UPDATE_DELAYED", function()
    if not BagAPI() and #providers > 0 and BankShown() then SlotMarks.Refresh() end
end)
Core.Listen("GLOW_MARKS_CHANGED", function() SlotMarks.Refresh() end, "ezCore.SlotMarks")
