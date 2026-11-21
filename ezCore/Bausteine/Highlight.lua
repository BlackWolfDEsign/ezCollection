local _, ns = ...
local Core = ezCore

--[[
    Leuchten: Leuchtfarben nach Bedeutung (Core.GLOW_COLORS, Core.GLOW_KINDS, Core.GlowColor …) und die alte
    Schnittstelle Core.ActionHighlight (leitet an den Leucht-Dienst Glow.lua weiter). Bis Welle 11 in Widgets.lua
    (EC-53, V-019); Namen unverändert. Lädt direkt nach Widgets.lua.
]]

---------------------------------------------------------------------------
-- Aktionsknöpfe hervorheben wie Blizzards Zauberbuch (vorher ezMacro/ActionHighlight.lua)
---------------------------------------------------------------------------

--[[
    ActionButtonTemplate: SpellHighlightTexture mit Atlas „UI-HUD-ActionBar-IconFrame-Mouseover“, ADD,
    Alpha 0.4, pulsierend 0,35 s. Taint-sicher: eigene Rahmen über den Knöpfen; Blizzards Knöpfe und
    ON_BAR_HIGHLIGHT_MARKS bleiben unberührt (Blizzard warnt dort selbst vor Taint). Erkannt werden Zauber
    und Makros, die den Zauber zeigen; verglichen wird nach Namen, damit jeder Rang zählt.

      Highlight.Show(zauberIDs, nameOf) / Clear()      vorübergehend, z. B. beim Zeigen auf einen Eintrag (weiß)
      Highlight.ShowSlots(schlüssel, plätze, { kind = "rank", tip = Text | fn(platz) })
                                                       dauerhaft je Schlüssel (z. B. "ezMacro.ranks"), bis der Besitzer
                                                       es aufhebt; folgt Leisten- und Seitenwechseln. kind wählt die Farbe
                                                       (Core.GLOW_KINDS), tip erklärt es im Tooltip des Knopfs
      Highlight.ClearSlots(schlüssel)                  Highlight.SlotKind(platz) → Art des Leuchtens oder nil
      Highlight.SlotKeys() → Schlüssel mit Plätzen     Highlight.RefreshSlots() → Anzahl leuchtender Knöpfe
      Highlight.AddTipSource(schlüssel, fn(platz) → art, text)
                                                       Erklärzeile für Leuchten, das ein Modul selbst zeichnet (ezCombat)
      Highlight.SlotsFor(zauberIDs, nameOf) → { platz … } alle belegten Aktionsplätze mit einem der Zauber, nach
                                                       Namen verglichen: jeder Rang zählt (ezBuff „Buff fehlt“, Spieltest
                                                       13.11.2026: „nur der entsprechende lvl1 buff blinkt“)

    Leuchtfarben nach Bedeutung (Wunsch des Nutzers 13.11.2026: stärker, „einheitlicher und klar verständlicher
    farbcode“): fünf Farben wie eine Ampel, jede Art gehört zu genau einer.
      Weiß   – wo liegt der Zauber (Zauberbuch)          spell
      Gold   – jetzt nutzen (Blizzards Proc-Farbe)        reactive, next
      Grün   – bereit                                     ready, finisher
      Orange – erneuern oder aktualisieren                dot, totem, missing, rank
      Rot    – sofort                                     interrupt
      Core.GLOW_COLORS[farbe] = { r, g, b, order, natural }; Core.GLOW_KINDS[art] = { color, order, r, g, b, natural }
      Core.GlowColor(art) → r, g, b; Core.GlowLabel(art) → „Orange (erneuern): neuerer Rang gelernt“
      Core.GlowKinds() → { { key, color, r, g, b, label } … }; Core.GlowGroups() → je Farbe { key, r, g, b, label, kinds }
      Core.GlowLegend() → Legende je Farbe (Seite „ezCollection“)
      Core.TintGlow(rahmen, art) färbt eigene Leuchtrahmen (z. B. aus Blizzards ActionButtonSpellAlertTemplate)

    Seit dem Leucht-Dienst (Glow.lua, Core.Glow): ShowSlots, ClearSlots, SlotKind, SlotKeys, RefreshSlots,
    AddTipSource, TipLines und OnActionTooltip leiten dorthin weiter (Gründe unter dem Besitzer "ActionHighlight") –
    je Knopf ein Leuchtrahmen und eine Tooltip-Zeile, auch solange Module noch die alte Schnittstelle rufen.
    Neue Aufrufe nutzen Core.Glow.Set/Clear. Show/Clear (weiß, beim Zeigen im Zauberbuch) bleiben hier.
]]

-- Die fünf Farben. natural: Blizzards eigene Farbe bleibt (Gold der „Proc“-Leuchte).
-- mark: Zeichen zusätzlich zur Farbe (V-043, Farbenblind-Hilfe; Schalter „Zeichen am Leuchten“, Glow.lua) – nur
-- ASCII, damit jede Schrift es hat. Weiß (Zauberbuch) bleibt ohne Zeichen.
Core.GLOW_COLORS = {
    white  = { r = 1,   g = 1,    b = 1,    order = 1 },
    gold   = { r = 1,   g = 0.82, b = 0,    order = 2, natural = true, mark = ">" },
    green  = { r = 0.2, g = 1,    b = 0.2,  order = 3, mark = "+" },
    orange = { r = 1,   g = 0.4,  b = 0,    order = 4, mark = "?" },
    red    = { r = 1,   g = 0.1,  b = 0.1,  order = 5, mark = "!" },
}
-- Zeichen je Farbe (Farbenblind-Hilfe, V-043/EC-47): seit dem 21.11.2026 verständlich ohne Legende – Entscheidung des
-- Nutzers („nochmal zum 2x "o" das versteht doch keiner“, gewählt: „? > + !“, „nur optional anschaltbar,
-- standardmäßig aus“): Orange „?“ fehlt/erneuern (vorher „o“), Gold „>“ jetzt nutzen (vorher „*“), Grün „+“ bereit,
-- Rot „!“ sofort. Nur ASCII – die Schrift des Spiels zeichnet ✓ oder ↻ nicht.

-- Zeichen einer Art (über ihre Farbe) oder nil.
function Core.GlowMark(kind)
    local info = Core.GLOW_KINDS and Core.GLOW_KINDS[kind]
    local color = info and Core.GLOW_COLORS[info.color]
    return color and color.mark or nil
end

-- Zeichen für den grauen Zustand einer Marke (EC-47, Wunsch aus ezBag): „erledigt“ oder „nicht für dich“
-- (Buch abgegeben, Quest erledigt, Sammelstück nur für eine andere Klasse). Wie die Farbzeichen nur ASCII.
Core.MUTED_MARK = "-"

--[[
    Zeichen für Marken der Module (EC-47), nur wenn „Zeichen am Leuchten“ an ist (Core.Glow.MarksEnabled):
      Core.MarkSign(schlüssel) → Zeichen oder nil. schlüssel = eine Farbe ("green", "red", "gold", "orange"),
                                 eine Art ("ready", "missing", …) oder "muted" (grauer Zustand, Core.MUTED_MARK).
                                 Weiß, Unbekanntes und Schalter aus → nil.
      Core.GlowMarkText(text, art) → text mit Zeichen davor („+ bereit“), sonst text unverändert. Ein gesperrter oder
                                 leerer Text bleibt unangetastet (Leitlinie 6: zuerst IsSecret). Ohne art gilt "ready".
      Core.MarksOn()             → ist der Schalter an? (ein Ort für die Abfrage; ezGear, ezMail, ezQuest und ezMap
                                 fragten vorher je selbst Core.Glow.MarksEnabled ab). Ohne Leucht-Dienst: false.
    Schaltet der Spieler um, sendet ezCore GLOW_MARKS_CHANGED (an) – Module zeichnen dann sofort neu.
]]
function Core.MarksOn()
    local glow = Core.Glow
    return type(glow) == "table" and type(glow.MarksEnabled) == "function" and glow.MarksEnabled() == true
end
local MarksOn = Core.MarksOn

function Core.MarkSign(key)
    if type(key) ~= "string" or not MarksOn() then return nil end
    if key == "muted" then return Core.MUTED_MARK end
    local color = Core.GLOW_COLORS[key]
    if color then return color.mark end
    return Core.GlowMark(key)
end

function Core.GlowMarkText(text, kind)
    if Core.IsSecret(text) or type(text) ~= "string" or text == "" then return text end
    local mark = Core.MarkSign(kind or "ready")
    if mark then return mark .. " " .. text end
    return text
end

-- Eine Liste für alle Module; neue Arten nur hier, immer mit einer der fünf Farben.
-- order: Platz in der Legende (nach Farbe). rank: Rangfolge im Leucht-Dienst (Glow.lua, Core.GlowRank) – zeigen
-- mehrere Gründe auf denselben Knopf, gewinnt der kleinste Rang: unterbrechen, Proc, bereit, DoT, Totem,
-- Buff fehlt, Finisher, nächste Aktion, neuerer Rang, Zauberbuch.
Core.GLOW_KINDS = {
    spell     = { color = "white",  order = 1,  rank = 10 },  -- hier liegt der Zauber (Zauberbuch)
    reactive  = { color = "gold",   order = 2,  rank = 2 },   -- Proc oder Reaktion: jetzt nutzen
    next      = { color = "gold",   order = 3,  rank = 8 },   -- nächste Aktion der Rotation (ezCombat): jetzt nutzen
    ready     = { color = "green",  order = 4,  rank = 3 },   -- Abklingzeit vorbei
    finisher  = { color = "green",  order = 5,  rank = 7 },   -- Finisher bereit
    dot       = { color = "orange", order = 6,  rank = 4 },   -- DoT läuft aus
    totem     = { color = "orange", order = 7,  rank = 5 },   -- Totem fehlt oder läuft aus
    missing   = { color = "orange", order = 8,  rank = 6 },   -- Buff fehlt
    rank      = { color = "orange", order = 9,  rank = 9 },   -- neuerer Rang gelernt
    interrupt = { color = "red",    order = 10, rank = 1 },   -- jetzt unterbrechen
}
-- r, g, b und natural je Art aus ihrer Farbe (für Module, die direkt lesen)
for _, info in pairs(Core.GLOW_KINDS) do
    local color = Core.GLOW_COLORS[info.color]
    info.r, info.g, info.b, info.natural = color.r, color.g, color.b, color.natural
end

function Core.GlowColor(kind)
    local info = Core.GLOW_KINDS[kind]
    if not info then return 1, 1, 1 end
    return info.r, info.g, info.b
end

-- „Orange (erneuern): neuerer Rang gelernt“ (ohne Farbcode; die Farbe gibt der Aufrufer, z. B. AddLine(text, Core.GlowColor(art))).
function Core.GlowLabel(kind)
    local L = Core.L
    local info = Core.GLOW_KINDS[kind]
    local meaning = L["GLOW_" .. tostring(kind)]
    if not (info and meaning) then return nil end
    return L.GLOW_LABEL:format(L["GLOW_COLOR_" .. info.color] or "", L["GLOW_GROUP_" .. info.color] or "", meaning)
end

function Core.GlowKinds()
    local list = {}
    for key, info in pairs(Core.GLOW_KINDS) do
        list[#list + 1] = { key = key, color = info.color, r = info.r, g = info.g, b = info.b, order = info.order,
            label = Core.GlowLabel(key) }
    end
    table.sort(list, function(a, b) return (a.order or 99) < (b.order or 99) end)
    return list
end

-- Je Farbe: { key, r, g, b, label = „Orange – erneuern oder aktualisieren“, kinds = { Bedeutung … } }, nach order.
function Core.GlowGroups()
    local L, groups, byKey = Core.L, {}, {}
    for key, color in pairs(Core.GLOW_COLORS) do
        local group = { key = key, r = color.r, g = color.g, b = color.b, order = color.order, kinds = {},
            label = L.GLOW_GROUP_LABEL:format(L["GLOW_COLOR_" .. key] or key, L["GLOW_GROUP_LONG_" .. key] or "") }
        groups[#groups + 1], byKey[key] = group, group
    end
    for _, kind in ipairs(Core.GlowKinds()) do
        local group = byKey[kind.color]
        if group then group.kinds[#group.kinds + 1] = L["GLOW_" .. kind.key] end
    end
    table.sort(groups, function(a, b) return a.order < b.order end)
    return groups
end

-- Legende in einem Text (Tooltip der Überschrift „Leuchtfarben“): je Farbe eine Zeile mit ihren Arten.
-- withMarks: Zeichen immer nennen (die Überschrift entsteht nur einmal, der Schalter „Zeichen am Leuchten“ steht darunter).
function Core.GlowLegend(withMarks)
    local lines = {}
    local marks = withMarks == true or (Core.Glow and Core.Glow.MarksEnabled and Core.Glow.MarksEnabled())
    for _, group in ipairs(Core.GlowGroups()) do
        local mark = marks and Core.GLOW_COLORS[group.key].mark
        lines[#lines + 1] = Core.ColorCode(group.r, group.g, group.b) .. (mark and ("[" .. mark .. "] ") or "") .. group.label
            .. "|r: " .. table.concat(group.kinds, ", ")
    end
    return table.concat(lines, "\n")
end

-- Färbt alle Texturen eines EIGENEN Leuchtrahmens (und seiner Kinder) in der Farbe der Art: entsättigt, dann getönt;
-- bei natural (Gold) bleibt Blizzards Farbe. Nie auf Blizzards eigene Rahmen anwenden. Rückgabe: Anzahl Texturen.
function Core.TintGlow(frame, kind)
    if type(frame) ~= "table" then return 0 end
    local info = Core.GLOW_KINDS[kind]
    local natural = info == nil or info.natural
    local r, g, b = Core.GlowColor(kind)
    local count = 0
    local function Paint(region)
        if type(region) == "table" and region.SetVertexColor and region.GetObjectType
            and region:GetObjectType() == "Texture" then
            if region.SetDesaturated then region:SetDesaturated(not natural) end
            if natural then region:SetVertexColor(1, 1, 1) else region:SetVertexColor(r, g, b) end
            count = count + 1
        end
    end
    local function Walk(f, depth)
        if f.GetRegions then
            for _, region in ipairs({ f:GetRegions() }) do Paint(region) end
        end
        if depth < 2 and f.GetChildren then
            for _, child in ipairs({ f:GetChildren() }) do Walk(child, depth + 1) end
        end
    end
    Walk(frame, 0)
    return count
end

local Highlight = {}
Core.ActionHighlight = Highlight

local HIGHLIGHT_ATLAS = "UI-HUD-ActionBar-IconFrame-Mouseover"
local FILL_ATLAS = "UI-HUD-ActionBar-IconFrame-Flash"
local BAR_PREFIXES = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
    "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }

local pool, active = {}, 0

-- Zaubername aus dem Client (nicht geheim), sonst nil.
-- Core.SpellName steht in Spells.lua (ein Zaubername-Helfer für alle, V-029; bis Welle 11 in Util.lua).

-- Alle Aktionsknöpfe von Blizzard: die Liste des Ereignisrahmens, sonst die bekannten Leistennamen.
function Highlight.Buttons()
    local list = {}
    local events = ActionBarButtonEventsFrame
    if type(events) == "table" and type(events.frames) == "table" then
        for _, button in pairs(events.frames) do list[#list + 1] = button end
    end
    if #list == 0 then
        for _, prefix in ipairs(BAR_PREFIXES) do
            for index = 1, 12 do
                local button = _G[prefix .. index]
                if type(button) == "table" then list[#list + 1] = button end
            end
        end
    end
    return list
end

-- Name des Zaubers auf einem Aktionsplatz, auch für Makros, die einen Zauber zeigen (vorher ezCombat).
-- Gelesen wird über Core.ActionSlots.SpellID (eine Stelle, geheime Werte zuerst geprüft).
-- nameOf(id): Standard Core.SpellName.
function Highlight.SlotSpellName(slot, nameOf)
    if type(slot) ~= "number" or not Core.ActionSlots then return nil end
    local id = Core.ActionSlots.SpellID(slot)
    if id == nil then return nil end
    return (nameOf or Core.SpellName)(id)
end

-- Stärker als Blizzards Zauberbuch-Hervorhebung (die liegt bei 0,4): Rand voll, dazu eine halb durchsichtige
-- Füllung (Blizzards Klick-Aufblitzen), beide entsättigt und in der Farbe der Art getönt; pulsiert 0,25 ↔ 1.
local function NewOverlay()
    local overlay = CreateFrame("Frame", nil, UIParent)
    overlay:EnableMouse(false)
    local texture = overlay:CreateTexture(nil, "OVERLAY")
    texture:SetAllPoints()
    if Core.AtlasExists(HIGHLIGHT_ATLAS) then
        texture:SetAtlas(HIGHLIGHT_ATLAS)
    else
        texture:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    end
    texture:SetBlendMode("ADD")
    texture:SetDesaturated(true)
    local fill = overlay:CreateTexture(nil, "ARTWORK")
    fill:SetAllPoints()
    if Core.AtlasExists(FILL_ATLAS) then
        fill:SetAtlas(FILL_ATLAS)
    else
        fill:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    end
    fill:SetBlendMode("ADD")
    fill:SetDesaturated(true)
    fill:SetAlpha(0.45)
    local anim = overlay:CreateAnimationGroup()
    anim:SetLooping("REPEAT")
    local fadeIn = anim:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0.25)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.4)
    fadeIn:SetSmoothing("OUT")
    fadeIn:SetOrder(1)
    local fadeOut = anim:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0.25)
    fadeOut:SetDuration(0.4)
    fadeOut:SetSmoothing("IN")
    fadeOut:SetOrder(2)
    overlay.texture, overlay.fill, overlay.anim = texture, fill, anim
    overlay:Hide()
    return overlay
end

local function Overlay(index)
    pool[index] = pool[index] or NewOverlay()
    return pool[index]
end

local function Place(overlay, button, kind)
    local r, g, b = Core.GlowColor(kind or "spell")
    overlay.texture:SetVertexColor(r, g, b)
    overlay.fill:SetVertexColor(r, g, b)
    overlay.kind = kind or "spell"
    overlay:ClearAllPoints()
    overlay:SetAllPoints(button)
    -- Schicht und Ebene des Knopfs über Core.Plain/Core.Num (V-186: seit 1.60.1 möglicherweise gesperrt); gesperrt
    -- gilt die Schicht des Zauberbuchs. Ein Kind des Knopfs wird der Rahmen bewusst nicht: er wandert von Knopf zu
    -- Knopf, und Blizzards Knöpfe bekommen keine fremden Kinder (Leitlinie 5).
    overlay:SetFrameStrata(Core.Plain(button:GetFrameStrata()) or "HIGH")
    overlay:SetFrameLevel((Core.Num(button:GetFrameLevel()) or 0) + 5)
    overlay:Show()
    overlay.anim:Play()
end

function Highlight.Clear()
    for index = 1, active do
        pool[index].anim:Stop()
        pool[index]:Hide()
    end
    active = 0
end

-- Namen der Zauber als Menge (Ränge teilen sich den Namen), nil wenn keiner bekannt ist.
local function SpellNameSet(spellIDs, nameOf)
    nameOf = nameOf or Core.SpellName
    local names, any = {}, false
    for _, id in ipairs(type(spellIDs) == "table" and spellIDs or {}) do
        local ok, name = pcall(nameOf, id)
        if ok and type(name) == "string" and not Core.IsSecret(name) and name ~= "" then names[name], any = true, true end
    end
    return any and names or nil
end

-- Hebt alle sichtbaren Aktionsknöpfe mit einem der Zauber hervor; Rückgabe: Anzahl der Knöpfe.
-- nameOf(id) liefert den Zaubernamen (Standard: Core.SpellName).
function Highlight.Show(spellIDs, nameOf)
    Highlight.Clear()
    local names = SpellNameSet(spellIDs, nameOf)
    if not names then return 0 end
    local count = 0
    for _, button in ipairs(Highlight.Buttons()) do
        if button:IsVisible() then
            local ok, name = pcall(Highlight.SlotSpellName, button.action)
            if ok and name and names[name] then
                count = count + 1
                Place(Overlay(count), button, "spell")
            end
        end
    end
    active = count
    return count
end

-- Alle belegten Aktionsplätze (Core.ActionSlots.USABLE, auch nicht angezeigte Seiten) mit einem der Zauber, nach
-- Namen verglichen – jeder Rang zählt. Für ShowSlots: Seitenwechsel folgt RefreshSlots von selbst.
function Highlight.SlotsFor(spellIDs, nameOf)
    local slots = {}
    local names = SpellNameSet(spellIDs, nameOf)
    local usable = Core.ActionSlots and Core.ActionSlots.USABLE
    if not (names and usable) then return slots end
    for _, slot in ipairs(usable) do
        local ok, name = pcall(Highlight.SlotSpellName, slot, nameOf)
        if ok and name and names[name] then slots[#slots + 1] = slot end
    end
    return slots
end

-- Dauerhaftes Leuchten nach Aktionsplatz, je Schlüssel eines Moduls (eigener Vorrat, unabhängig von Show/Clear).
local slotSets, slotOpts, slotPool, slotActive = {}, {}, {}, 0
local tipSources = {}

-- Schlüssel in Textfolge wie bisher (Core.SortedKeys, Util.lua)
local function SortedKeys(map) return Core.SortedKeys(map, true) end

-- Art des Leuchtens an einem Platz (der erste Schlüssel in Namensfolge gewinnt), sonst nil.
function Highlight.SlotKind(slot)
    if Core.Glow then return Core.Glow.SlotKind(slot) end
    slot = Core.Num(slot)
    if not slot then return nil end
    for _, key in ipairs(SortedKeys(slotSets)) do
        if slotSets[key][slot] then return (slotOpts[key] and slotOpts[key].kind) or "spell" end
    end
    return nil
end

function Highlight.RefreshSlots()
    if Core.Glow then return Core.Glow.Refresh() end
    for index = 1, slotActive do
        slotPool[index].anim:Stop()
        slotPool[index]:Hide()
    end
    slotActive = 0
    if not next(slotSets) then return 0 end
    for _, button in ipairs(Highlight.Buttons()) do
        local slot = Core.Num(button.action)
        local kind = slot and Highlight.SlotKind(slot)
        if kind and button:IsVisible() then
            slotActive = slotActive + 1
            slotPool[slotActive] = slotPool[slotActive] or NewOverlay()
            Place(slotPool[slotActive], button, kind)
        end
    end
    return slotActive
end

-- Plätze (Aktionsplatz-Nummern) eines Schlüssels leuchten lassen; eine leere Liste hebt ihn auf.
-- opts: { kind = Art aus Core.GLOW_KINDS, tip = Text oder fn(platz) → Text für den Tooltip des Knopfs }
-- (ein Text allein gilt als kind).
function Highlight.ShowSlots(key, slots, opts)
    if key == nil then return 0 end
    if type(opts) == "string" then opts = { kind = opts } end
    if Core.Glow then
        -- Weiterleitung an den Leucht-Dienst: ohne Art und Text keine Tooltip-Zeile, ohne Art kein Farb-Etikett
        local kind, tip = nil, false
        if type(opts) == "table" then
            kind = opts.kind
            if opts.kind or opts.tip then tip = opts.tip end
        end
        Core.Glow.Set(Core.Glow.LEGACY_OWNER, key, { slots = slots, kind = kind, tip = tip, label = kind and true or false })
        return Core.Glow.Refresh()
    end
    slotOpts[key] = type(opts) == "table" and { kind = opts.kind, tip = opts.tip } or nil
    local set
    for _, slot in ipairs(type(slots) == "table" and slots or {}) do
        slot = Core.Num(slot)
        if slot then
            set = set or {}
            set[slot] = true
        end
    end
    slotSets[key] = set
    return Highlight.RefreshSlots()
end

-- Schlüssel aufheben; ohne Schlüssel alle.
function Highlight.ClearSlots(key)
    if Core.Glow then
        Core.Glow.Clear(Core.Glow.LEGACY_OWNER, key)
        return Core.Glow.Refresh()
    end
    if key == nil then
        slotSets, slotOpts = {}, {}
    else
        slotSets[key], slotOpts[key] = nil, nil
    end
    return Highlight.RefreshSlots()
end

function Highlight.SlotKeys()
    if Core.Glow then
        local keys = {}
        for _, reason in ipairs(Core.Glow.List()) do
            if reason.owner == Core.Glow.LEGACY_OWNER then keys[#keys + 1] = reason.key end
        end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        return keys
    end
    return SortedKeys(slotSets)
end

-- Erklärzeile für Leuchten, das ein Modul selbst zeichnet: fn(platz) → art, text (nil = nichts). nil hebt auf.
function Highlight.AddTipSource(key, fn)
    if Core.Glow then return Core.Glow.AddTipSource(key, fn) end
    if key == nil then return end
    tipSources[key] = type(fn) == "function" and fn or nil
end

-- Zeilen für den Tooltip eines Aktionsplatzes: { { kind, text } … } (ShowSlots mit kind oder tip, dann die Quellen).
function Highlight.TipLines(slot)
    if Core.Glow then return Core.Glow.TipLines(slot) end
    local lines = {}
    slot = Core.Num(slot)
    if not slot then return lines end
    for _, key in ipairs(SortedKeys(slotSets)) do
        local opts = slotOpts[key]
        if slotSets[key][slot] and opts and (opts.kind or opts.tip) then
            local text = opts.tip
            if type(text) == "function" then
                local ok, result = pcall(text, slot)
                text = ok and result or nil
            end
            lines[#lines + 1] = { kind = opts.kind, text = type(text) == "string" and text or nil }
        end
    end
    for _, key in ipairs(SortedKeys(tipSources)) do
        local ok, kind, text = pcall(tipSources[key], slot)
        if ok and (kind or text) then
            lines[#lines + 1] = { kind = kind, text = type(text) == "string" and text or nil }
        end
    end
    return lines
end

-- Tooltip eines Aktionsknopfs: EINE Zeile für den dringendsten Grund in der Farbe des Leuchtens (Leucht-Dienst).
-- Ohne den Dienst (alt): je Grund eine Zeile, darunter die Erklärung des Moduls.
function Highlight.OnActionTooltip(tooltip, slot)
    if Core.Glow then return Core.Glow.OnActionTooltip(tooltip, slot) end
    if type(tooltip) ~= "table" or not tooltip.AddLine then return 0 end
    local lines = Highlight.TipLines(slot)
    for _, line in ipairs(lines) do
        local label = Core.GlowLabel(line.kind)
        if label then
            local r, g, b = Core.GlowColor(line.kind)
            tooltip:AddLine(label, r, g, b, true)
        end
        if line.text then Core.TipLine(tooltip, line.text, "highlight", true) end
    end
    if #lines > 0 and tooltip.Show then tooltip:Show() end
    return #lines
end

if GameTooltip and GameTooltip.SetAction then
    hooksecurefunc(GameTooltip, "SetAction", function(tooltip, slot)
        local ok, err = pcall(Highlight.OnActionTooltip, tooltip, slot)
        if not ok then Core.Error("ezCore", err, "ActionTooltip") end
    end)
end

-- Leiste umgeblättert, Platz geändert, Leiste ein- oder ausgeblendet: Plätze neu den Knöpfen zuordnen.
local refreshSlots = Core.Throttle(function()
    if next(slotSets) or slotActive > 0 then Highlight.RefreshSlots() end
end, 0.1, "ezCore")
for _, event in ipairs({ "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM",
    "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_ENTERING_WORLD" }) do
    ns.On(event, refreshSlots)
end
-- Bearbeitungsmodus: EditMode.lua lädt nach dieser Datei
C_Timer.After(0, function()
    if Core.EditMode then Core.EditMode.OnChange(function() refreshSlots() end, "ezCore") end
end)

-- Alte Schnittstelle (EC-30): Module rufen Core.Glow.Set/Clear/AddTipSource; wer noch die alten Namen ruft, erscheint
-- in /ez status („Abgelöste Aufrufe“). Die Arbeit tut weiter dieselbe Funktion (leitet selbst an Core.Glow weiter).
Highlight.ShowSlots = Core.Deprecated("Core.ActionHighlight.ShowSlots", "Core.Glow.Set", Highlight.ShowSlots)
Highlight.ClearSlots = Core.Deprecated("Core.ActionHighlight.ClearSlots", "Core.Glow.Clear", Highlight.ClearSlots)
Highlight.AddTipSource = Core.Deprecated("Core.ActionHighlight.AddTipSource", "Core.Glow.AddTipSource", Highlight.AddTipSource)
