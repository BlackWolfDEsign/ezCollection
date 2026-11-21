local _, ns = ...
local Core = ezCore

--[[
    Leucht-Dienst (Core.Glow) – EIN Dienst für das Leuchten an Aktionsknöpfen (Entscheidung des Nutzers 13.11.2026:
    „Leucht-Dienst in ezCore“, Vollprüfung V-105). Module melden Gründe nur noch an und ab; je Knopf zeigt der Dienst
    den dringendsten Grund: genau EIN Leuchtrahmen und EINE Tooltip-Zeile. Gleiche Gründe zweier Module (z. B.
    „Buff fehlt“ von ezBuff und ezCombat) fallen zusammen.

    Gründe anmelden
      Glow.Set(owner, key, opts) → true (angemeldet) | false (nichts zu zeigen: abgemeldet)
          owner  Modulname ("ezCombat"), key  Name des Grundes im Modul ("missing", "ranks")
          opts.kind    Art aus Core.GLOW_KINDS (Farbe und Rang); ohne Angabe "spell"
          opts.spell   Zauber-ID, Zaubername oder Liste davon – verglichen wird nach Namen, jeder Rang zählt, auch
                       Makros, die den Zauber zeigen (opts.spells ist dasselbe)
          opts.names   Menge { [Zaubername] = true } oder Liste von Namen
          opts.slots   Liste von Aktionsplätzen
          opts.tip     Text oder fn(platz, grund) → Text für den Tooltip des Knopfs; false = keine Zeile
          opts.label   false = die Zeile ohne „Orange (erneuern): …“ davor
          opts.order   Rang als Zahl, kleiner gewinnt; ohne Angabe der Rang der Art (Core.GlowRank)
          opts.alpha   Deckkraft: Zahl, gesperrter Wert (wird nur an SetAlpha gereicht), { [Zaubername] = Wert }
                       oder fn(platz, zaubername) → Wert
          opts.duration  Sekunden; danach meldet sich der Grund selbst ab (kurzes Leuchten „wieder bereit“)
          opts.nameOf  fn(id) → Zaubername (Standard Core.SpellName)
      Glow.Clear(owner, key)   ein Grund; ohne key alle Gründe des Moduls → Anzahl
      Glow.Flash(owner, platz, sekunden, art, opts)   kurzes Leuchten an einem Platz (Standard "ready", 1,5 s) unter
          dem Schlüssel "flash:<platz>"; opts wie bei Set (tip, order …) → true/false
      Glow.SetAlpha(owner, key, alpha)   Deckkraft eines Grundes ändern, ohne das Leuchten neu zu starten

    Rangfolge (fest, in Core.GLOW_KINDS[art].rank, kleiner gewinnt):
      interrupt, reactive, ready, dot, totem, missing, finisher, next, rank, spell
    Bei gleichem Rang gewinnt der Modulname, dann der Schlüssel (Namensfolge).

    Abfragen
      Glow.Reason(platz) → { kind, order, owner, key, owners = { … }, text } des dringendsten Grundes oder nil
      Glow.Reasons(platz) → alle Gründe des Platzes, dringendster zuerst
      Glow.SlotKind(platz) → Art oder nil          Glow.List() → alle angemeldeten Gründe (für /dump)
      Glow.TipLines(platz) → { { kind, text, owners } … } je Art eine, dringendste zuerst (mit den Quellen aus
          AddTipSource)                            Glow.TipLine(platz) → Text, r, g, b der EINEN Zeile oder nil
      Glow.OnActionTooltip(tooltip, platz) → 0 oder 1 (hängt über ActionHighlight an GameTooltip:SetAction)
      Glow.AddTipSource(schlüssel, fn(platz) → art, text)   für Module, die noch selbst zeichnen (alt)
      Glow.Refresh() → Anzahl leuchtender Knöpfe   Glow.RefreshSoon()   Glow.PrepareAll() → Anzahl Rahmen
      Glow.RankText() → „unterbrechen, Proc oder Reaktion, …“ (Legende)
      Glow.StatusLine() → Zeile für /ez status (wer hat was angemeldet) oder nil

    Der Leuchtrahmen (einmal gebaut, vorher je einmal in ezCombat, ezBuff und ezCore)
      Core.NewGlow(ziel, opts) → Rahmen-Objekt oder nil; je Ziel genau einer (ein zweiter Aufruf gibt denselben)
          Blizzards Proc-Leuchten (ActionButtonSpellAlertTemplate: ProcStartAnim, dann ProcLoop), sonst ein
          pulsierender Rand. opts.secure = true: Ziel ist ein geschützter Knopf – gebaut wird nur außerhalb des
          Kampfes (im Kampf nil). opts.factor (1,4 wie Blizzard), opts.width/height (feste Größe), opts.anchor
          (Region, an der der Rahmen mittig sitzt, Standard das Ziel), opts.start = false (ohne Blizzards
          Start-Blitz, nur die Schleife), opts.pulse = true (zusätzliches Pulsieren 1 ↔ 0,45), opts.level (Ebene
          über dem Ziel)
      glow:Show(art) → true   glow:Hide()   glow:IsShown()   glow:Kind() → Art, solange sichtbar
      glow:SetAlpha(wert)     glow.frame
      Glow.Get(ziel) → Rahmen-Objekt oder nil

    Taint-sicher: Der Rahmen ist ein eigenes Kind des Ziels (wie Blizzards eigenes Leuchten und ezCombat bisher);
    gemerkt wird alles in eigenen Tabellen mit schwachen Schlüsseln. Blizzards Knöpfe bekommen keine Werte,
    ActionButtonSpellAlertManager wird nur gelesen (zeigt Blizzard selbst einen Proc, leuchtet der Dienst dort nicht
    zusätzlich). Geheime Werte: Plätze über Core.Num, Deckkraft wird ungeprüft durchgereicht.
]]

local Glow = {}
Core.Glow = Glow

local TEMPLATE = "ActionButtonSpellAlertTemplate"
local FALLBACK_ATLAS = "UI-HUD-ActionBar-IconFrame-Mouseover"
local FALLBACK_FILE = "Interface\\Buttons\\ButtonHilight-Square"
Glow.SIZE_FACTOR = 1.4      -- wie Blizzard: Leuchten 1,4-mal so groß wie der Knopf
Glow.LEGACY_OWNER = "ActionHighlight"   -- Gründe aus der alten Schnittstelle ActionHighlight.ShowSlots

---------------------------------------------------------------------------
-- Rangfolge der Arten
---------------------------------------------------------------------------

function Core.GlowRank(kind)
    local info = Core.GLOW_KINDS[kind]
    return (info and info.rank) or 99
end

-- Arten nach Rang, dringendste zuerst.
Glow.KIND_ORDER = {}
for kind in pairs(Core.GLOW_KINDS) do Glow.KIND_ORDER[#Glow.KIND_ORDER + 1] = kind end
table.sort(Glow.KIND_ORDER, function(a, b) return Core.GlowRank(a) < Core.GlowRank(b) end)

function Glow.RankText()
    local L, names = Core.L, {}
    for _, kind in ipairs(Glow.KIND_ORDER) do
        if kind ~= "spell" then names[#names + 1] = L["GLOW_" .. kind] or kind end
    end
    return table.concat(names, ", ")
end

---------------------------------------------------------------------------
-- Der Leuchtrahmen
---------------------------------------------------------------------------

local frames = setmetatable({}, { __mode = "k" })   -- Ziel → Rahmen-Objekt
local GlowFrame = {}
GlowFrame.__index = GlowFrame

local function AlphaLoop(frame, low, half, smoothIn, smoothOut)
    local group = frame:CreateAnimationGroup()
    group:SetLooping("REPEAT")
    local fadeOut = group:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(low)
    fadeOut:SetDuration(half)
    fadeOut:SetSmoothing(smoothOut)
    fadeOut:SetOrder(1)
    local fadeIn = group:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(low)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(half)
    fadeIn:SetSmoothing(smoothIn)
    fadeIn:SetOrder(2)
    return group
end

local function Playing(group)
    if type(group) ~= "table" or not group.IsPlaying then return false end
    return group:IsPlaying() == true
end

-- Blizzards Vorlage hält die Schleife beim Ausblenden an: beim Zeigen (auch wenn nur der Elternrahmen wieder
-- erscheint) läuft sie wieder an. Der Start-Blitz kommt nur nach einem ausdrücklichen Show.
local function PlayAnims(glow)
    if not (Playing(glow.start) or Playing(glow.loop)) then
        if glow.start and glow.wantStart then
            glow.start:Play()
        elseif glow.loop then
            glow.loop:Play()
        end
    end
    glow.wantStart = false
    if glow.pulse and not Playing(glow.pulse) then glow.pulse:Play() end
end

local function StopAnims(glow)
    if glow.start then glow.start:Stop() end
    if glow.loop then glow.loop:Stop() end
    if glow.pulse then glow.pulse:Stop() end
end

local function Build(target, opts)
    local ok, frame = pcall(CreateFrame, "Frame", nil, target, TEMPLATE)
    local start = ok and type(frame) == "table" and rawget(frame, "ProcStartAnim") or nil
    local loop = ok and type(frame) == "table" and rawget(frame, "ProcLoop") or nil
    if type(start) ~= "table" then start = nil end
    if type(loop) ~= "table" then loop = nil end
    local template = (start or loop) and true or false
    if not template then
        frame = CreateFrame("Frame", nil, target)
        local texture = frame:CreateTexture(nil, "OVERLAY")
        texture:SetAllPoints()
        if Core.AtlasExists(FALLBACK_ATLAS) then texture:SetAtlas(FALLBACK_ATLAS) else texture:SetTexture(FALLBACK_FILE) end
        texture:SetBlendMode("ADD")
        frame.texture = texture
        loop = AlphaLoop(frame, 0.3, 0.35, "OUT", "IN")
    end
    if frame.EnableMouse then frame:EnableMouse(false) end
    local glow = setmetatable({
        frame = frame, target = target, template = template,
        start = (opts.start ~= false) and start or nil, loop = loop,
        pulse = opts.pulse and AlphaLoop(frame, 0.45, 0.6, "IN_OUT", "IN_OUT") or nil,
        factor = Core.Num(opts.factor) or Glow.SIZE_FACTOR,
        width = Core.Num(opts.width), height = Core.Num(opts.height),
        anchor = type(opts.anchor) == "table" and opts.anchor or nil,
    }, GlowFrame)
    local level = Core.Num(opts.level)
    if level and frame.SetFrameLevel and target.GetFrameLevel then
        local base = Core.Num(target:GetFrameLevel())
        if base then frame:SetFrameLevel(base + level) end
    end
    -- Zeichen zusätzlich zur Farbe (V-043): gleich mitgebaut (außerhalb des Kampfes), gezeigt nur mit Schalter.
    local okMark, mark = pcall(frame.CreateFontString, frame, nil, "OVERLAY", "GameFontNormalHuge")
    if okMark and type(mark) == "table" and mark.SetText then
        pcall(mark.SetPoint, mark, "TOPRIGHT", frame, "TOPRIGHT", -6, -4)
        if mark.Hide then mark:Hide() end
        glow.mark = mark
    end
    frame:HookScript("OnShow", function() PlayAnims(glow) end)
    frame:HookScript("OnHide", function() StopAnims(glow) end)
    frame:Hide()
    return glow
end

-- Farbenblind-Hilfe (V-043): Schalter „Zeichen am Leuchten“ (ezCoreDB.comfort.glowMarks, Standard aus).
Core.OwnDefaults("comfort", { glowMarks = false })

-- Ein gespeichertes „an“ bleibt (Entscheidung des Nutzers vom 21.11.2026 vor v1.0.0-beta2, Frage: einmalige Umstellung
-- behalten? – „Remove it (Recommended)“): Schon in v1.0.0-beta1 war der Schalter ab Werk aus, ein „an“ ist dort immer
-- eine eigene Wahl. Die einmalige Umstellung Glow.MigrateMarksOff vom 21.11.2026 ist darum gestrichen.
function Glow.MarksEnabled()
    return Core.OwnSetting("comfort", "glowMarks") == true
end

local function UpdateMark(glow)
    local mark = glow.mark
    if not mark then return false end
    local symbol = Glow.MarksEnabled() and Core.GlowMark(glow.kind) or nil
    if symbol then
        mark:SetText(symbol)
        if mark.SetTextColor then mark:SetTextColor(Core.GlowColor(glow.kind)) end
        mark:Show()
        return true
    end
    mark:Hide()
    return false
end

-- Zeichen des Leuchtrahmens (nil, wenn keines gezeigt wird) – für Tests und /dump.
function GlowFrame:Mark()
    local mark = self.mark
    if not (mark and mark.IsShown and mark:IsShown()) then return nil end
    return mark.GetText and mark:GetText() or nil
end

-- Nach dem Umschalten: alle vorhandenen Rahmen nachziehen. → Anzahl Rahmen mit Zeichen
function Glow.RefreshMarks()
    local n = 0
    for _, glow in pairs(frames) do
        if UpdateMark(glow) then n = n + 1 end
    end
    return n
end

-- Der Schalter wurde umgelegt (Einstellungsseite „ezCollection“): eigene Rahmen nachziehen und den Modulen
-- GLOW_MARKS_CHANGED (an) senden, damit ihre Marken sofort neu zeichnen (Wunsch aus ezGear und ezMail).
function Glow.MarksChanged()
    local n = Glow.RefreshMarks()
    Core.Fire("GLOW_MARKS_CHANGED", Glow.MarksEnabled())
    return n
end

-- Größe und Lage: 1,4-mal das Ziel, mittig. Ist die Größe des Ziels nicht lesbar, an seinen Ecken mit Überstand.
function GlowFrame:Place()
    local frame, target = self.frame, self.target
    local anchor = self.anchor or target
    local width, height = self.width, self.height
    if not (width and height) and target.GetWidth then
        local w, h = Core.Num(target:GetWidth()), Core.Num(target:GetHeight())
        if w and h and w > 0 and h > 0 then width, height = w * self.factor, h * self.factor end
    end
    frame:ClearAllPoints()
    if width and height then
        frame:SetSize(width, height)
        frame:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    else
        frame:SetPoint("TOPLEFT", anchor, "TOPLEFT", -7, 7)
        frame:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 7, -7)
    end
end

-- art: Art aus Core.GLOW_KINDS (Farbe); ohne Angabe Blizzards Gold. Ein laufendes Leuchten startet nicht neu.
function GlowFrame:Show(kind)
    kind = kind or "reactive"
    if self.kind ~= kind then
        self.kind = kind
        Core.Call(Core.TintGlow, self.frame, kind)
    end
    UpdateMark(self)
    if self.frame:IsShown() then return true end
    self:Place()
    self.wantStart = true
    self.frame:Show()
    PlayAnims(self)
    return true
end

function GlowFrame:Hide()
    if not self.frame:IsShown() then return end
    StopAnims(self)
    self.frame:Hide()
end

function GlowFrame:IsShown()
    return self.frame:IsShown() and true or false
end

function GlowFrame:Kind()
    return self.frame:IsShown() and self.kind or nil
end

-- Deckkraft; darf ein gesperrter Wert sein (SetAlpha nimmt ihn an) – nie prüfen oder vergleichen.
function GlowFrame:SetAlpha(alpha)
    self.frame:SetAlpha(alpha)
end

function Glow.Get(target)
    if type(target) ~= "table" then return nil end
    return frames[target]
end

function Core.NewGlow(target, opts)
    if type(target) ~= "table" then return nil end
    local glow = frames[target]
    if glow then return glow end
    opts = type(opts) == "table" and opts or {}
    if opts.secure and Core.InCombat() then return nil end
    local ok, built = pcall(Build, target, opts)
    if not ok then
        Core.Error("ezCore", built, "NewGlow")
        return nil
    end
    frames[target] = built
    return built
end

---------------------------------------------------------------------------
-- Gründe
---------------------------------------------------------------------------

local reasons = {}          -- owner → key → Grund
local sorted = {}           -- alle Gründe, dringendster zuerst
local tipSources = {}       -- schlüssel → fn(platz) → art, text
local shown = setmetatable({}, { __mode = "k" })    -- Aktionsknopf → Grund, für den er leuchtet
local used = false          -- Grund angemeldet oder PrepareAll gerufen: dann Rahmen vor dem Kampf vorbereiten
local SECURE = { secure = true }

-- Schlüssel in Textfolge wie bisher (Core.SortedKeys, Util.lua)
local function SortedKeys(map) return Core.SortedKeys(map, true) end

local function Before(a, b)
    if a.order ~= b.order then return a.order < b.order end
    if a.rank ~= b.rank then return a.rank < b.rank end
    if a.owner ~= b.owner then return a.owner < b.owner end
    return tostring(a.key) < tostring(b.key)
end

local function Rebuild()
    sorted = {}
    for _, set in pairs(reasons) do
        for _, reason in pairs(set) do sorted[#sorted + 1] = reason end
    end
    table.sort(sorted, Before)
end

local function AddName(names, value, nameOf)
    if Core.IsSecret(value) then return end
    if type(value) == "number" then
        local ok, name = pcall(nameOf, value)
        if ok then value = name else value = nil end
        if Core.IsSecret(value) then return end
    end
    if type(value) == "string" and value ~= "" then names[value] = true end
end

-- Zauber (ID, Name, Liste) und Namen (Menge oder Liste) → Menge der Zaubernamen oder nil.
local function NameSet(opts, nameOf)
    local names = {}
    local function Add(source)
        if Core.IsSecret(source) then return end
        if type(source) == "table" then
            for key, value in pairs(source) do
                if type(key) == "number" then
                    AddName(names, value, nameOf)
                elseif value then
                    AddName(names, key, nameOf)
                end
            end
        else
            AddName(names, source, nameOf)
        end
    end
    Add(opts.spell)
    Add(opts.spells)
    Add(opts.names)
    return next(names) and names or nil
end

local function SlotSet(list)
    local set
    for _, slot in ipairs(type(list) == "table" and list or {}) do
        slot = Core.Num(slot)
        if slot then
            set = set or {}
            set[slot] = true
        end
    end
    return set
end

local function Signature(reason)
    local parts = { reason.kind, tostring(reason.order) }
    if reason.slots then parts[#parts + 1] = "s:" .. table.concat(SortedKeys(reason.slots), ",") end
    if reason.names then parts[#parts + 1] = "n:" .. table.concat(SortedKeys(reason.names), "\1") end
    return table.concat(parts, "|")
end

local function Remove(owner, key)
    local set = reasons[owner]
    if not (set and set[key]) then return false end
    set[key] = nil
    if not next(set) then reasons[owner] = nil end
    return true
end

function Glow.Set(owner, key, opts)
    if type(owner) ~= "string" or owner == "" or key == nil then return false end
    if type(opts) ~= "table" then
        if Remove(owner, key) then
            Rebuild()
            Glow.RefreshSoon()
        end
        return false
    end
    local nameOf = type(opts.nameOf) == "function" and opts.nameOf or Core.SpellName
    local kind = Core.GLOW_KINDS[opts.kind] and opts.kind or "spell"
    local reason = {
        owner = owner, key = key, kind = kind, rank = Core.GlowRank(kind),
        order = Core.Num(opts.order) or Core.GlowRank(kind),
        slots = SlotSet(opts.slots), names = NameSet(opts, nameOf),
        nameOf = opts.nameOf and nameOf or nil,
        tip = opts.tip, label = opts.label, alpha = opts.alpha,
    }
    if not (reason.slots or reason.names) then
        if Remove(owner, key) then
            Rebuild()
            Glow.RefreshSoon()
        end
        return false
    end
    reason.signature = Signature(reason)
    local duration = Core.Num(opts.duration)
    if duration and duration > 0 then
        reason.expires = GetTime() + duration
        C_Timer.After(duration + 0.05, function() Glow.RefreshSoon() end)
    end
    local old = reasons[owner] and reasons[owner][key]
    reasons[owner] = reasons[owner] or {}
    reasons[owner][key] = reason
    Rebuild()
    if not used then Glow.PrepareAll() end
    if old and old.signature == reason.signature and not (old.expires or reason.expires) then
        -- nur Text oder Deckkraft neu: Knöpfe, die für den alten Grund leuchten, zeigen auf den neuen
        for button, current in pairs(shown) do
            if current == old then shown[button] = reason end
        end
        Glow.ApplyAlpha(reason)
        return true
    end
    Glow.RefreshSoon()
    return true
end

function Glow.Clear(owner, key)
    local count = 0
    if type(owner) ~= "string" then return count end
    if key == nil then
        for _ in pairs(reasons[owner] or {}) do count = count + 1 end
        reasons[owner] = nil
    elseif Remove(owner, key) then
        count = 1
    end
    if count > 0 then
        Rebuild()
        Glow.RefreshSoon()
    end
    return count
end

-- Kurzes Leuchten an einem Aktionsplatz (z. B. „wieder bereit“); meldet sich nach der Zeit selbst ab.
function Glow.Flash(owner, slot, seconds, kind, opts)
    slot = Core.Num(slot)
    if not slot then return false end
    local flash = {}
    for key, value in pairs(type(opts) == "table" and opts or {}) do flash[key] = value end
    local duration = Core.Num(seconds)
    if not duration or duration <= 0 then duration = 1.5 end   -- 0 oder weniger hieße sonst: leuchtet dauerhaft
    flash.slots, flash.kind, flash.duration = { slot }, kind or flash.kind or "ready", duration
    flash.spell, flash.spells, flash.names = nil, nil, nil
    return Glow.Set(owner, "flash:" .. slot, flash)
end

function Glow.List()
    local list = {}
    for _, reason in ipairs(sorted) do
        list[#list + 1] = { owner = reason.owner, key = reason.key, kind = reason.kind, order = reason.order,
            slots = reason.slots and SortedKeys(reason.slots) or nil,
            names = reason.names and SortedKeys(reason.names) or nil, expires = reason.expires }
    end
    return list
end

-- Zeile für /ez status: „Leuchten an Aktionsknöpfen: 3 Gründe (ezBuff: missing; ezCombat: dot, next)“, sonst nil.
function Glow.StatusLine()
    if #sorted == 0 then return nil end
    local parts = {}
    for _, owner in ipairs(SortedKeys(reasons)) do
        local kinds, seen = {}, {}
        for _, key in ipairs(SortedKeys(reasons[owner])) do
            local kind = reasons[owner][key].kind
            if not seen[kind] then
                seen[kind] = true
                kinds[#kinds + 1] = kind
            end
        end
        parts[#parts + 1] = owner .. ": " .. table.concat(kinds, ", ")
    end
    return Core.L.STATUS_GLOW:format(#sorted, table.concat(parts, "; "))
end

---------------------------------------------------------------------------
-- Welcher Grund gilt für einen Platz?
---------------------------------------------------------------------------

-- Zaubername des Platzes je Namensfunktion, je Durchlauf einmal gelesen.
local function SlotName(slot, nameOf, cache)
    local key = nameOf or 1
    local bySlot = cache[key]
    if not bySlot then
        bySlot = {}
        cache[key] = bySlot
    end
    local name = bySlot[slot]
    if name == nil then
        local ok, result = pcall(Core.ActionHighlight.SlotSpellName, slot, nameOf)
        name = (ok and type(result) == "string" and not Core.IsSecret(result)) and result or false
        bySlot[slot] = name
    end
    return name or nil
end

local function Matches(reason, slot, cache, now)
    if reason.expires and reason.expires <= now then return false end
    if reason.slots and reason.slots[slot] then return true end
    if reason.names then
        local name = SlotName(slot, reason.nameOf, cache)
        if name and reason.names[name] then return true end
    end
    return false
end

local function Winner(slot, cache, now)
    for _, reason in ipairs(sorted) do
        if Matches(reason, slot, cache, now) then return reason end
    end
    return nil
end

local function TipText(reason, slot)
    local text = reason.tip
    if type(text) == "function" then
        local ok, result = pcall(text, slot, reason)
        if ok then text = result else text = nil end
    end
    if Core.IsSecret(text) then return nil end
    return type(text) == "string" and text ~= "" and text or nil
end

function Glow.Reasons(slot)
    local list = {}
    slot = Core.Num(slot)
    if not slot then return list end
    local cache, now = {}, GetTime()
    for _, reason in ipairs(sorted) do
        if Matches(reason, slot, cache, now) then
            list[#list + 1] = { owner = reason.owner, key = reason.key, kind = reason.kind, order = reason.order,
                text = TipText(reason, slot), silent = reason.tip == false, label = reason.label }
        end
    end
    return list
end

-- Der dringendste Grund; gleiche Arten anderer Module fallen hinein (owners), der erste Text gilt.
function Glow.Reason(slot)
    local list = Glow.Reasons(slot)
    local first = list[1]
    if not first then return nil end
    local result = { kind = first.kind, order = first.order, owner = first.owner, key = first.key,
        owners = {}, text = first.text }
    local seen = {}
    for _, entry in ipairs(list) do
        if entry.kind == first.kind then
            if not seen[entry.owner] then
                seen[entry.owner] = true
                result.owners[#result.owners + 1] = entry.owner
            end
            if not result.text then result.text = entry.text end
        end
    end
    return result
end

function Glow.SlotKind(slot)
    slot = Core.Num(slot)
    if not slot then return nil end
    local reason = Winner(slot, {}, GetTime())
    return reason and reason.kind or nil
end

---------------------------------------------------------------------------
-- Tooltip: EINE Zeile je Knopf
---------------------------------------------------------------------------

-- Erklärzeile für Leuchten, das ein Modul noch selbst zeichnet: fn(platz) → art, text (nil = nichts). nil hebt auf.
function Glow.AddTipSource(key, fn)
    if key == nil then return end
    tipSources[key] = type(fn) == "function" and fn or nil
end

-- Je Art eine Zeile, dringendste zuerst: { kind, text, owners, order, label }.
function Glow.TipLines(slot)
    local lines, byKind = {}, {}
    slot = Core.Num(slot)
    if not slot then return lines end
    local function Add(kind, text, owner, order, silent, label)
        local id = kind or ("?" .. tostring(owner))
        local line = byKind[id]
        if not line then
            if silent then return end
            line = { kind = kind, text = text, owners = {}, order = order, label = label }
            byKind[id] = line
            lines[#lines + 1] = line
        elseif silent then
            return
        end
        if not line.text then line.text = text end
        line.owners[#line.owners + 1] = owner
    end
    for _, entry in ipairs(Glow.Reasons(slot)) do
        Add(entry.kind, entry.text, entry.owner, entry.order, entry.silent, entry.label)
    end
    for _, key in ipairs(SortedKeys(tipSources)) do
        local ok, kind, text = pcall(tipSources[key], slot)
        if ok and not Core.IsSecret(kind) and not Core.IsSecret(text) and (kind or text) then
            Add(kind, type(text) == "string" and text or nil, key, Core.GlowRank(kind))
        end
    end
    -- stabil: bei gleichem Rang bleibt die Reihenfolge des Anmeldens
    for index, line in ipairs(lines) do line.index = index end
    table.sort(lines, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.index < b.index
    end)
    return lines
end

-- Die eine Zeile: „Orange (erneuern): Buff fehlt – Dämonenhaut, klicken zum Buffen“ in der Farbe des Leuchtens.
function Glow.TipLine(slot)
    local line = Glow.TipLines(slot)[1]
    if not line then return nil end
    local label = line.label ~= false and Core.GlowLabel(line.kind) or nil
    local r, g, b = 1, 1, 1
    if label then r, g, b = Core.GlowColor(line.kind) end
    local text
    if label and line.text then
        text = Core.L.GLOW_LINE:format(label, Core.WHITE .. line.text .. "|r")
    else
        text = label or line.text
    end
    if not text then return nil end
    return text, r, g, b, line
end

function Glow.OnActionTooltip(tooltip, slot)
    if type(tooltip) ~= "table" or not tooltip.AddLine then return 0 end
    local text, r, g, b = Glow.TipLine(slot)
    if not text then return 0 end
    tooltip:AddLine(text, r, g, b, true)
    if tooltip.Show then tooltip:Show() end
    return 1
end

---------------------------------------------------------------------------
-- Zeichnen
---------------------------------------------------------------------------

local function BlizzardAlert(button)
    local manager = rawget(_G, "ActionButtonSpellAlertManager")
    if type(manager) ~= "table" or type(manager.HasAlert) ~= "function" then return false end
    local ok, has = pcall(manager.HasAlert, manager, button)
    if not ok or Core.IsSecret(has) then return false end
    return has == true
end

-- Deckkraft eines Grundes an einem Platz: gesperrter Wert unverändert, sonst Zahl oder 1.
local function AlphaFor(reason, slot, cache)
    local alpha = reason.alpha
    if Core.IsSecret(alpha) then return alpha end
    if type(alpha) == "function" then
        local ok, value = pcall(alpha, slot, SlotName(slot, reason.nameOf, cache))
        if ok then alpha = value else alpha = nil end
    elseif type(alpha) == "table" then
        local name = SlotName(slot, reason.nameOf, cache)
        if name then alpha = alpha[name] else alpha = nil end
    end
    if Core.IsSecret(alpha) then return alpha end
    if type(alpha) == "number" then return alpha end
    return 1
end

-- Deckkraft der Knöpfe, die gerade für diesen Grund leuchten, neu setzen.
function Glow.ApplyAlpha(reason)
    local cache = {}
    for button, current in pairs(shown) do
        if current == reason then
            local glow, slot = frames[button], Core.Num(button.action)
            if glow and slot then glow:SetAlpha(AlphaFor(reason, slot, cache)) end
        end
    end
end

function Glow.SetAlpha(owner, key, alpha)
    local reason = reasons[owner] and reasons[owner][key]
    if not reason then return false end
    reason.alpha = alpha
    Glow.ApplyAlpha(reason)
    return true
end

-- Rahmen für alle Aktionsknöpfe vorab anlegen (außerhalb des Kampfes) → Anzahl vorhandener Rahmen.
-- Der ausdrückliche Aufruf heißt: Ein Modul will Rahmen (ein Kampf-Modul ruft ihn in OnReady, weil seine
-- Gründe erst im Kampf entstehen). Von da an hält der Dienst die Rahmen bei Leistenwechsel und Kampfbeginn nach.
function Glow.PrepareAll()
    local count = 0
    used = true
    for _, button in ipairs(Core.ActionHighlight.Buttons()) do
        if Core.NewGlow(button, SECURE) then count = count + 1 end
    end
    return count
end

local function Purge(now)
    local changed = false
    for owner, set in pairs(reasons) do
        for key, reason in pairs(set) do
            if reason.expires and reason.expires <= now then
                set[key] = nil
                changed = true
            end
        end
        if not next(set) then reasons[owner] = nil end
    end
    if changed then Rebuild() end
end

local function HideButton(button)
    local glow = frames[button]
    if glow then glow:Hide() end
    shown[button] = nil
end

-- Ordnet die Gründe den Aktionsknöpfen zu → Anzahl sichtbar leuchtender Knöpfe.
function Glow.Refresh()
    local now = GetTime()
    Purge(now)
    local count, cache, seen = 0, {}, {}
    if #sorted > 0 or next(shown) then
        for _, button in ipairs(Core.ActionHighlight.Buttons()) do
            seen[button] = true
            -- auch für verborgene Knöpfe: der Rahmen ist ihr Kind und erscheint mit der Leiste von selbst
            local reason, slot
            if #sorted > 0 then
                slot = Core.Num(button.action)
                if slot then reason = Winner(slot, cache, now) end
                if reason and BlizzardAlert(button) then reason = nil end
            end
            local glow = reason and Core.NewGlow(button, SECURE)
            if glow and glow:Show(reason.kind) then
                shown[button] = reason
                glow:SetAlpha(AlphaFor(reason, slot, cache))
                if button:IsVisible() then count = count + 1 end
            elseif shown[button] then
                HideButton(button)
            end
        end
    end
    for button in pairs(shown) do
        if not seen[button] then HideButton(button) end
    end
    return count
end

Glow.RefreshSoon = Core.Throttle(Glow.Refresh, 0.05, "ezCore")

---------------------------------------------------------------------------
-- Leistenwechsel, Blizzards eigenes Leuchten, Kampf
---------------------------------------------------------------------------

-- Die eigenen Ereignisse bereiten nur vor, wenn je ein Modul den Dienst nutzt (Grund oder PrepareAll).
local function PrepareIfUsed()
    if used then return Glow.PrepareAll() end
    return 0
end

local prepareSoon = Core.Throttle(PrepareIfUsed, 1, "ezCore")

for _, event in ipairs({ "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR",
    "UPDATE_SHAPESHIFT_FORM", "UPDATE_MACROS", "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW",
    "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", "PLAYER_ENTERING_WORLD" }) do
    ns.On(event, function()
        if #sorted > 0 or next(shown) then Glow.RefreshSoon() end
        if event == "ACTIONBAR_SLOT_CHANGED" or event == "ACTIONBAR_PAGE_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
            prepareSoon()
        end
    end)
end

-- Kampfbeginn: Das Ereignis kommt noch vor der Kampfsperre, also letzte Gelegenheit für fehlende Rahmen.
ns.On("PLAYER_REGEN_DISABLED", function() PrepareIfUsed() end)
ns.On("PLAYER_REGEN_ENABLED", function()
    PrepareIfUsed()
    if #sorted > 0 or next(shown) then Glow.RefreshSoon() end
end)

---------------------------------------------------------------------------
-- Symbol in der Optik von Blizzards Aktionsknopf (vorher ezCombats Glow.StyleIcon; EC-105, ST-11): Maske und
-- Rahmen „UI-HUD-ActionBar-IconFrame(-Mask)“, sonst beschnittene Ränder. Für ezCombat, AuraRow und weitere Module.
---------------------------------------------------------------------------

Core.ICON_MASK = { "UI-HUD-ActionBar-IconFrame-Mask" }
Core.ICON_FRAME = { "UI-HUD-ActionBar-IconFrame" }

-- Die Maske hat einen leeren Rand: Blizzard legt sie größer als das Symbol und mittig darauf (Forever-Quelle
-- Blizzard_PerksProgram/Blizzard_PerksProgramElements.xml: Icon 32 × 32, IconMask 48 × 48; Blizzard_ActionBar/Mainline/
-- ActionButtonTemplate.xml: IconMask mittig auf dem Symbol in eigener Größe). Über das Symbol gespannt (SetAllPoints)
-- schnitt sie es auf etwa zwei Drittel zu – im Spieltest 20.11.2026 saß das Symbol klein im Rahmen (ezBars-Leisten).
-- Verhältnis Maske : Knopf zuerst aus dem Client (Leitlinie 11): Blizzards Aktionsknopf ist 45 × 45 und trägt die Maske
-- in ihrer Atlasgröße → Breite des Atlas / 45. Liefert der Client nichts Brauchbares (nicht größer als der Knopf),
-- gilt Blizzards Verhältnis aus PerksProgram (Icon 32, IconMask 48 = 1,5) – das der Aktionsleiste ist dann unbelegt.
Core.ICON_MASK_SCALE = 48 / 32
local ACTION_BUTTON_SIZE = 45     -- ActionButtonTemplate.xml (Forever), Size 45 × 45
local maskScale
function Core.IconMaskScale()
    if maskScale then return maskScale end
    maskScale = Core.ICON_MASK_SCALE
    local atlas = Core.FirstAtlas(Core.ICON_MASK)
    if atlas and C_Texture and C_Texture.GetAtlasInfo then
        local ok, info = pcall(C_Texture.GetAtlasInfo, atlas)
        local w = ok and type(info) == "table" and info.width or nil
        if type(w) == "number" and not Core.IsSecret(w) and w > ACTION_BUTTON_SIZE and w < ACTION_BUTTON_SIZE * 3 then
            maskScale = w / ACTION_BUTTON_SIZE
        end
    end
    return maskScale
end

-- Masken der Knöpfe – nicht im Rahmen gespeichert: AuraRow legt Symbole auch an Blizzards eigenen Aurenknöpfen an
-- (Leitlinie 5: keine Werte in Blizzards Tabellen). Schwache Schlüssel: verschwindet der Knopf, verschwindet der Eintrag.
local iconMasks = setmetatable({}, { __mode = "k" })

-- Maske mittig auf dem Symbol, Core.IconMaskScale()-mal so groß wie der Knopf (das Symbol füllt ihn). Solange der Knopf
-- noch keine Größe hat (ezCombat: Fläche erst nach dem Layout), bleibt sie über das Symbol gespannt – das Symbol ist
-- dann kleiner, aber zu sehen. Läuft bei jeder Größenänderung (OnSizeChanged); Module rufen es nach eigenem SetSize,
-- wo der Hook fehlt.
local function FitIconMask(frame)
    local entry = frame and iconMasks[frame]
    if not (entry and frame.GetSize) then return end
    local w, h = frame:GetSize()
    if type(w) ~= "number" or type(h) ~= "number" or Core.IsSecret(w) or Core.IsSecret(h) or w <= 0 or h <= 0 then return end
    local scale = Core.IconMaskScale()
    entry.mask:ClearAllPoints()
    entry.mask:SetPoint("CENTER", entry.icon)
    entry.mask:SetSize(w * scale, h * scale)
end
Core.FitIconMask = FitIconMask

-- Maske eines Knopfs aus Core.StyleIcon (Prüfungen, Diagnose). → MaskTexture oder nil
function Core.IconMaskOf(frame) return frame and iconMasks[frame] and iconMasks[frame].mask or nil end

-- Legt in frame ein Symbol mit Maske und Rahmen an (frame.icon, frame.border). → Symbol-Textur
function Core.StyleIcon(frame)
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    local maskAtlas = Core.FirstAtlas(Core.ICON_MASK)
    if maskAtlas and frame.CreateMaskTexture then
        local mask = frame:CreateMaskTexture()
        mask:SetAtlas(maskAtlas)
        mask:SetAllPoints(icon)
        icon:AddMaskTexture(mask)
        iconMasks[frame] = { mask = mask, icon = icon }
        FitIconMask(frame)
        -- geschützt: an Blizzards Aurenknöpfen darf ein Hook nicht den Rest des Aufbaus abbrechen (AuraRow)
        if frame.HookScript then pcall(frame.HookScript, frame, "OnSizeChanged", FitIconMask) end
    else
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    end
    local frameAtlas = Core.FirstAtlas(Core.ICON_FRAME)
    if frameAtlas then
        local border = frame:CreateTexture(nil, "OVERLAY")
        border:SetAtlas(frameAtlas)
        border:SetPoint("TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", 1, -1)
        frame.border = border
    end
    frame.icon = icon
    return icon
end
Glow.StyleIcon = Core.StyleIcon

-- Bearbeitungsmodus: EditMode.lua lädt vor dieser Datei
if Core.EditMode and Core.EditMode.OnChange then
    Core.EditMode.OnChange(function()
        if #sorted > 0 or next(shown) then Glow.RefreshSoon() end
    end, "ezCore")
end
