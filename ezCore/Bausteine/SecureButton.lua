local _, ns = ...
local Core = ezCore

--[[
    Sichere Aktionsknöpfe an einer Stelle (Vollprüfung V-170): Blizzards SecureActionButtonTemplate anlegen,
    Attribute setzen, zeigen, verankern und eine Taste darauf legen – alles Geschützte nur außerhalb des Kampfes.
    Was im Kampf gewünscht wird, merkt sich der Dienst als Soll-Zustand und holt es über Core.AfterCombat nach
    (ein Eintrag je Knopf; der letzte Wunsch je Attribut, Lage, Sichtbarkeit und Taste gewinnt).
    Vorher bauten ezMacro (lange Makros) und ezBuff (Buff-Knopf) das je selbst; geplant sind Ein-Klick-Makros
    und Angeln (ezMacro), Wildtierausbildung (ezMerchant), Symbol „Buff fehlt“ am Gruppenrahmen (ezBuff, ezHeal).
    Geschrieben wird nur in eigene Rahmen, nie in Blizzards Tabellen (Leitlinie 5).

      Core.SecureButton(name, opts) → knopf | nil, grund      derselbe Name liefert denselben Knopf (opts gelten neu).
                                      Scheiterte das Anlegen (etwa "taken" nach dem Kampf), versucht ein erneuter
                                      Aufruf es mit demselben Knopf noch einmal; scheitert es wieder (nil, grund),
                                      bleibt ein schon gehaltener Knopf gültig und meldet den Grund bei jeder Methode
        name   globaler Rahmenname (für „/click <name>“ und die Tastenbelegung), z. B. "ezMacroLong3"
        opts   owner         Modulname (Fehlerliste; ein anderes Modul bekommt den Knopf nicht: "taken")
               parent        Elternrahmen (Standard UIParent)
               template      weitere Vorlagen neben SecureActionButtonTemplate, z. B. Blizzards Buff-Vorlage AuraButtonArtTemplate;
                             kennt der Client sie nicht, entsteht der Knopf ohne sie (knopf:TemplateMissing())
               clicks        Text oder Liste für RegisterForClicks (Standard "AnyUp": /click sendet ein Loslassen)
               useOnKeyDown  Attribut useOnKeyDown (Standard false, passend zu "AnyUp"); "cvar": kein Attribut –
                             dann gilt Blizzards Einstellung „Aktion bei Tastendruck“ (CVar ActionButtonUseKeyDown)
               hideInCombat  true: im Kampf ausgeblendet, danach wieder da (Blizzards Zustandstreiber
                             "[combat] hide; show"; ohne RegisterStateDriver zum Kampfbeginn von Hand)
               onCreate      fn(rahmen, knopf): einmal nach dem Anlegen, außerhalb des Kampfes – für Symbol,
                             Schrift, PreClick/PostClick, Tooltip (alles Ungeschützte baut das Modul selbst)
               attributes, action, shown, size = { b, h }, anchor = { punkt, zu, zuPunkt, x, y } | fn, bind
                             Anfangszustand, wie die Methoden unten

      Jede Methode, die Geschütztes ändert, gibt zurück:
        true               sofort erledigt
        false, "combat"    gemerkt, läuft nach dem Kampf (knopf:Pending() → true)
        false, grund       nicht möglich: "invalid" (Parameter), "secret" (geheimer Wert), "missing" (der Client
                           hat die Funktion nicht), "taken" (der Name gehört schon einem fremden Rahmen),
                           "unbound" (BindLike: der Befehl hat keine Taste), "error" (Fehler steht in der Fehlerliste)

      knopf:Set(attribut, wert) | knopf:Set({ attribut = wert … })     wert nil löscht das Attribut
      knopf:Get(attribut)             → gewünschter Wert (auch, solange er noch wartet)
      knopf:SetAction(aktion, taste)  aktion = { type = "spell" | "item" | "macro" …, spell, item, macro, macrotext,
                                      unit } oder nil (Klick tut nichts); löscht zuerst die übrigen Aktions-Attribute.
                                      taste: Zusatz am Attributnamen (1 = nur Linksklick → "type1", "spell1" …)
      knopf:ClearAction(taste)
      knopf:Show() / :Hide() / :SetShown(an) / :Shown() → gewünschte Sichtbarkeit
      knopf:Size(breite, höhe)
      knopf:Anchor(punkt, zu, zuPunkt, x, y) | knopf:Anchor(fn(rahmen, knopf))   fn setzt die Punkte selbst
      knopf:Bind(taste | { tasten }, opts)   Taste als Übersteuerung auf den Knopf (SetOverrideBindingClick).
                                      opts: priority (Standard false), mouse (Standard "LeftButton"),
                                      inCombat = false → im Kampf gilt wieder die normale Belegung, danach wieder
                                      die eigene (gelöst wird beim Kampfbeginn, solange das noch erlaubt ist),
                                      command = Blizzards Befehl (z. B. "INTERACTTARGET"): die Taste löst diesen
                                      Befehl aus statt eines Klicks auf den Knopf (SetOverrideBinding; ezMacros
                                      Angeln holt so während des Kanals mit der eigenen Taste ein)
      knopf:BindLike(befehl, opts)    alle Tasten, die heute auf einem Befehl liegen (z. B. "INTERACTTARGET" für
                                      das Angeln) → ok, grund, { tasten }. Ändert der Spieler die Belegung, ruft
                                      das Modul es erneut (bei UPDATE_BINDINGS; nicht von selbst, weil das Setzen
                                      einer Übersteuerung dasselbe Ereignis auslöst).
      knopf:Unbind(taste | { tasten }) | knopf:Unbind()   eine, mehrere oder alle Tasten lösen
      knopf:Keys()                    → { [taste] = opts } gewünschte Tasten
      knopf:Applied()                 → { [taste] = opts } Tasten, die ezCore gerade im Client gesetzt hat (ohne
                                      wartende und ohne im Kampf ausgesetzte, inCombat = false) – zum Abgleich mit
                                      GetBindingAction(taste, true), ob der Client eine Übersteuerung verworfen hat
      knopf:Do(fn(rahmen, knopf), schlüssel)   beliebiges Geschütztes außerhalb des Kampfes; derselbe Schlüssel
                                      ersetzt einen wartenden Aufruf
      knopf:Release()                 Aktion leeren, ausblenden, alle Tasten lösen (der Rahmen bleibt – Rahmen
                                      lassen sich nicht entfernen; derselbe Name nutzt ihn weiter)
      knopf:Flush()                   Wartendes jetzt anwenden (macht der Dienst nach dem Kampf selbst)
      knopf:Name(), :Owner(), :Frame() → Rahmen oder nil (im Kampf angefragt: erst danach), :Pending(),
      knopf:TemplateMissing()

      Core.SecureButtons.Get(name) → knopf | nil     .List() → Namen in der Reihenfolge des Anlegens
      Core.SecureButtons.Count() → Anzahl, davon wartend     .StatusLine() → Zeile für /ez status oder nil
      Core.SecureButtons.KeysOf(befehl) → { tasten }
      Core.SecureButtons.OnCombatStart() / .OnCombatEnd()    intern (PLAYER_REGEN_DISABLED / _ENABLED)

      Core.SecureButtons.KeyProxy(ziel, name, owner) → true | false, grund     Stellvertreter für eine Taste
                                      (Gesamtreview 18.11.2026, T9-NB1). Ein sicherer Knopf mit "AnyUp" und
                                      useOnKeyDown = false wirkt bei /click und Mausklick richtig, über eine Taste aber
                                      immer erst beim Loslassen – auch wenn „Aktion bei Tastendruck“ an ist. Die Taste
                                      (CLICK <name>:LeftButton in einer Bindings.xml) liegt darum auf dem Stellvertreter:
                                      RegisterForClicks("AnyDown", "AnyUp"), kein Attribut useOnKeyDown (Blizzards CVar
                                      gilt), type = "click", clickbutton = der Rahmen von ziel. Blizzards
                                      SECURE_ACTIONS.click drückt den Zielknopf dann mit einem Loslassen – genau einmal,
                                      im Kampf wie außerhalb; /click und Mausklick am Ziel bleiben, wie sie sind.
                                      Angelegt wird der Stellvertreter erst, wenn der Rahmen von ziel entsteht (über diesen
                                      Dienst; vorher gibt es nichts zu drücken), beides nur außerhalb des Kampfes.
      Core.SecureButtons.ProxyOf(ziel) → stellvertreter (Knopf) | nil
]]

local ADDON = "ezCore"
local SecureButtons = {}
Core.SecureButtons = SecureButtons

SecureButtons.TEMPLATE = "SecureActionButtonTemplate"
SecureButtons.VISIBILITY = "[combat] hide; show"
SecureButtons.ACTION_KEYS = { "type", "spell", "item", "macro", "macrotext", "unit" }
SecureButtons.QUEUE_PREFIX = "SecureButton:"

local NIL = {}                          -- Platzhalter „Attribut löschen“ im Soll-Zustand
local handles, order, states = {}, {}, {}
local Handle = {}
Handle.__index = Handle

local function Report(state, err, what)
    Core.Error(state.owner or ADDON, err, "SecureButton " .. tostring(state.name) .. (what and (" " .. what) or ""))
end

-- Ruft eine Funktion des Clients geschützt; Fehler landen in der Fehlerliste. → true bei Erfolg.
local function Safe(state, what, fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, err = pcall(fn, ...)
    if not ok then Report(state, err, what) end
    return ok
end

-- Stellvertreter für Tasten (T9-NB1, Kopf oben): [ziel] = { name, owner } gewünscht | [ziel] = Knopf angelegt
SecureButtons.KEY_CLICKS = { "AnyDown", "AnyUp" }
local proxyWishes, proxies = {}, {}

-- Legt den Stellvertreter von ziel an und lässt ihn auf den Rahmen von ziel zeigen – erst, wenn es den Rahmen gibt.
-- → true | false (noch kein Rahmen) | false, grund. Scheitert das Anlegen (etwa "taken": der Name gehört schon einem
-- fremden Rahmen), steht das in der Fehlerliste des Moduls („SecureButton <ziel> KeyProxy <name>: taken“) – sonst
-- bliebe die Taste stumm, ohne dass es jemand erfährt, auch wenn das Ziel erst später entsteht (Create, Gegenprüfung).
local function LinkProxy(target)
    local wish, handle = proxyWishes[target], handles[target]
    local frame = wish and handle and states[handle].frame
    if not frame then return false end
    local proxy = proxies[target]
    if not proxy then
        local made, reason = Core.SecureButton(wish.name, { owner = wish.owner, clicks = SecureButtons.KEY_CLICKS,
            useOnKeyDown = "cvar", attributes = { type = "click" } })
        if not made then
            Core.Error(wish.owner or ADDON, tostring(reason),
                "SecureButton " .. tostring(target) .. " KeyProxy " .. tostring(wish.name))
            return false, reason
        end
        proxy = made
        proxies[target] = proxy
    end
    if proxy:Get("clickbutton") ~= frame then return proxy:Set("clickbutton", frame) end
    return true
end

local function HasPending(state)
    local p = state.pending
    return state.frame == nil or next(p.attrs) ~= nil or p.size ~= nil or p.anchor ~= nil or p.shown ~= nil
        or next(p.binds) ~= nil or p.unbindAll == true or #p.todo > 0
end

---------------------------------------------------------------------------
-- Anwenden (nur außerhalb des Kampfes – gerufen über Core.AfterCombat)
---------------------------------------------------------------------------

local function Create(state)
    if type(CreateFrame) ~= "function" then return nil, "missing" end
    if _G[state.name] ~= nil then return nil, "taken" end
    local frame
    if state.template then
        local ok, made = pcall(CreateFrame, "Button", state.name, state.parent or UIParent,
            SecureButtons.TEMPLATE .. ", " .. state.template)
        if ok and type(made) == "table" then frame = made else state.templateMissing = true end
    end
    if not frame then
        local ok, made = pcall(CreateFrame, "Button", state.name, state.parent or UIParent, SecureButtons.TEMPLATE)
        if not ok or type(made) ~= "table" then
            Report(state, made, "CreateFrame")
            return nil, "error"
        end
        frame = made
    end
    frame:Hide()
    local clicks = state.clicks
    if type(clicks) == "table" then frame:RegisterForClicks(unpack(clicks)) else frame:RegisterForClicks(clicks or "AnyUp") end
    -- "cvar": kein Attribut, dann gilt Blizzards CVar ActionButtonUseKeyDown (SecureActionButton_ShouldUseOnKeyDown)
    if state.useOnKeyDown ~= "cvar" then frame:SetAttribute("useOnKeyDown", state.useOnKeyDown == true) end
    state.frame = frame
    if state.onCreate then Safe(state, "onCreate", state.onCreate, frame, state.handle) end
    if proxyWishes[state.name] then LinkProxy(state.name) end   -- Stellvertreter für die Taste (T9-NB1)
    return frame
end

-- Zustandstreiber abmelden, wenn einer liegt – auch, wenn hideInCombat inzwischen aus ist (sonst zeigte der alte
-- Treiber „[combat] hide; show“ einen verborgenen Knopf nach jedem Kampf wieder). Ohne UnregisterStateDriver
-- ersetzt ein fester Treiber den alten; er bleibt dann gemerkt und wird beim nächsten Mal wieder ersetzt.
local function DropDriver(state, frame, show)
    if not state.driver then return end
    if type(UnregisterStateDriver) == "function" then
        UnregisterStateDriver(frame, "visibility")
        state.driver = false
    elseif type(RegisterStateDriver) == "function" then
        RegisterStateDriver(frame, "visibility", show and "show" or "hide")
    else
        state.driver = false
    end
end

local function ApplyShown(state, show)
    local frame = state.frame
    if show and state.hideInCombat and type(RegisterStateDriver) == "function" then
        RegisterStateDriver(frame, "visibility", SecureButtons.VISIBILITY)
        state.driver = true
        frame:Show()
    else
        DropDriver(state, frame, show)
        if show then frame:Show() else frame:Hide() end
    end
    state.combatHidden = nil
end

local function ApplyAnchor(state, anchor)
    local frame = state.frame
    if type(anchor.fn) == "function" then
        anchor.fn(frame, state.handle)
        return
    end
    frame:ClearAllPoints()
    if anchor.rel == nil and anchor.relPoint == nil then
        frame:SetPoint(anchor.point, anchor.x or 0, anchor.y or 0)
    else
        frame:SetPoint(anchor.point, anchor.rel, anchor.relPoint or anchor.point, anchor.x or 0, anchor.y or 0)
    end
end

local function ClearKey(state, key)
    local spec = state.bound[key]
    if not spec then return end
    state.bound[key] = nil
    Safe(state, "SetOverrideBinding", SetOverrideBinding, state.frame, spec.priority == true, key, nil)
end

local function ApplyBinds(state)
    local p = state.pending
    if p.unbindAll then
        p.unbindAll = nil
        if next(state.bound) ~= nil then Safe(state, "ClearOverrideBindings", ClearOverrideBindings, state.frame) end
        state.bound, state.suspended = {}, {}
    end
    local binds = p.binds
    p.binds = {}
    for key, spec in pairs(binds) do
        state.suspended[key] = nil
        if spec == false then
            ClearKey(state, key)
        else
            -- andere Priorität als bisher: die alte Übersteuerung zuerst lösen
            if state.bound[key] and (state.bound[key].priority == true) ~= (spec.priority == true) then ClearKey(state, key) end
            local set
            if spec.command then
                set = Safe(state, "SetOverrideBinding", SetOverrideBinding, state.frame, spec.priority == true, key,
                    spec.command)
            else
                set = Safe(state, "SetOverrideBindingClick", SetOverrideBindingClick, state.frame, spec.priority == true,
                    key, state.name, spec.mouse or "LeftButton")
            end
            if set then state.bound[key] = spec end
        end
    end
end

-- → true | false, grund
local function Apply(state)
    if not state.frame then
        local frame, reason = Create(state)
        if not frame then
            state.failed = reason
            return false, reason
        end
    end
    local frame, p = state.frame, state.pending
    local attrs = p.attrs
    p.attrs = {}
    for attr, value in pairs(attrs) do
        if value == NIL then frame:SetAttribute(attr, nil) else frame:SetAttribute(attr, value) end
    end
    if p.size then
        local size = p.size
        p.size = nil
        frame:SetSize(size[1], size[2])
    end
    if p.anchor then
        local anchor = p.anchor
        p.anchor = nil
        ApplyAnchor(state, anchor)
    end
    if p.shown ~= nil then
        local show = p.shown
        p.shown = nil
        ApplyShown(state, show)
    end
    ApplyBinds(state)
    if #p.todo > 0 then
        local todo = p.todo
        p.todo = {}
        for _, entry in ipairs(todo) do Safe(state, "Do", entry.fn, frame, state.handle) end
    end
    return true
end

local function Flush(state)
    if state.failed then return false, state.failed end
    local ok, reason = true, nil
    local ran = Core.AfterCombat(function()
        local fine, a, b = pcall(Apply, state)
        if fine then
            ok, reason = a, b
        else
            Report(state, a)
            ok, reason = false, "error"
        end
    end, SecureButtons.QUEUE_PREFIX .. state.name, state.owner)
    if not ran then return false, "combat" end
    return ok, reason
end

---------------------------------------------------------------------------
-- Soll-Zustand vormerken (ohne anzuwenden) – jede → true | false, grund
---------------------------------------------------------------------------

local function StageAttr(state, attr, value)
    if Core.IsSecret(attr) or Core.IsSecret(value) then return false, "secret" end
    if type(attr) ~= "string" or attr == "" then return false, "invalid" end
    state.attrs[attr] = value
    if value == nil then state.pending.attrs[attr] = NIL else state.pending.attrs[attr] = value end
    return true
end

local function StageAttrs(state, map)
    if type(map) ~= "table" then return false, "invalid" end
    for attr, value in pairs(map) do
        local ok, reason = StageAttr(state, attr, value)
        if not ok then return false, reason end
    end
    return true
end

local function Suffix(button)
    if button == nil then return "" end
    if Core.IsSecret(button) or (type(button) ~= "string" and type(button) ~= "number") then return nil end
    return tostring(button)
end

local function StageAction(state, action, button)
    local suffix = Suffix(button)
    if not suffix or (action ~= nil and type(action) ~= "table") then return false, "invalid" end
    if action then
        for _, key in ipairs(SecureButtons.ACTION_KEYS) do
            if Core.IsSecret(action[key]) then return false, "secret" end
        end
        if action.type ~= nil and type(action.type) ~= "string" then return false, "invalid" end
    end
    state.suffixes[suffix] = true
    for _, key in ipairs(SecureButtons.ACTION_KEYS) do
        StageAttr(state, key .. suffix, action and action[key] or nil)
    end
    return true
end

local function StageShown(state, show)
    state.shown = show == true
    state.pending.shown = state.shown
    return true
end

local function StageSize(state, width, height)
    if Core.IsSecret(width) or Core.IsSecret(height) then return false, "secret" end
    if type(width) ~= "number" or type(height) ~= "number" then return false, "invalid" end
    state.pending.size = { width, height }
    return true
end

local function StageAnchor(state, point, rel, relPoint, x, y)
    if type(point) == "function" then
        state.pending.anchor = { fn = point }
        return true
    end
    if Core.IsSecret(point) or Core.IsSecret(x) or Core.IsSecret(y) then return false, "secret" end
    if type(point) ~= "string" or point == "" then return false, "invalid" end
    state.pending.anchor = { point = point, rel = rel, relPoint = relPoint, x = x, y = y }
    return true
end

local function KeyList(keys)
    if Core.IsSecret(keys) then return nil, "secret" end
    if type(keys) == "string" then keys = { keys } end
    if type(keys) ~= "table" or #keys == 0 then return nil, "invalid" end
    for _, key in ipairs(keys) do
        if Core.IsSecret(key) then return nil, "secret" end
        if type(key) ~= "string" or key == "" then return nil, "invalid" end
    end
    return keys
end

local function StageBind(state, keys, opts)
    local list, reason = KeyList(keys)
    if not list then return false, reason end
    if opts ~= nil and type(opts) ~= "table" then return false, "invalid" end
    local command = opts and opts.command
    if command ~= nil and (Core.IsSecret(command) or type(command) ~= "string" or command == "") then
        return false, "invalid"
    end
    if type(SetOverrideBindingClick) ~= "function" or type(SetOverrideBinding) ~= "function" then return false, "missing" end
    for _, key in ipairs(list) do
        local spec = { priority = opts and opts.priority == true or false, mouse = opts and opts.mouse or "LeftButton",
            inCombat = not (opts and opts.inCombat == false), command = command }
        state.keys[key] = spec
        state.pending.binds[key] = spec
    end
    return true
end

local function StageUnbind(state, keys)
    if keys == nil then
        state.keys = {}
        state.pending.binds = {}
        state.pending.unbindAll = true
        return true
    end
    local list, reason = KeyList(keys)
    if not list then return false, reason end
    for _, key in ipairs(list) do
        state.keys[key] = nil
        state.pending.binds[key] = false
    end
    return true
end

local function Staged(state, ok, reason)
    if not ok then return false, reason end
    return Flush(state)
end

---------------------------------------------------------------------------
-- Der Knopf
---------------------------------------------------------------------------

function Handle:Name() return states[self].name end
function Handle:Owner() return states[self].owner end
function Handle:Frame() return states[self].frame end
function Handle:TemplateMissing() return states[self].templateMissing == true end

function Handle:Pending()
    local state = states[self]
    return not state.failed and HasPending(state)
end

function Handle:Flush() return Flush(states[self]) end

function Handle:Set(attr, value)
    local state = states[self]
    if not Core.IsSecret(attr) and type(attr) == "table" then return Staged(state, StageAttrs(state, attr)) end
    return Staged(state, StageAttr(state, attr, value))
end

function Handle:Get(attr)
    if Core.IsSecret(attr) or type(attr) ~= "string" then return nil end
    return states[self].attrs[attr]
end

function Handle:SetAction(action, button)
    local state = states[self]
    return Staged(state, StageAction(state, action, button))
end

function Handle:ClearAction(button) return self:SetAction(nil, button) end

function Handle:SetShown(show)
    local state = states[self]
    return Staged(state, StageShown(state, show))
end
function Handle:Show() return self:SetShown(true) end
function Handle:Hide() return self:SetShown(false) end
function Handle:Shown() return states[self].shown == true end

function Handle:Size(width, height)
    local state = states[self]
    return Staged(state, StageSize(state, width, height))
end

function Handle:Anchor(point, rel, relPoint, x, y)
    local state = states[self]
    return Staged(state, StageAnchor(state, point, rel, relPoint, x, y))
end

function Handle:Bind(keys, opts)
    local state = states[self]
    return Staged(state, StageBind(state, keys, opts))
end

function Handle:BindLike(command, opts)
    local keys = SecureButtons.KeysOf(command)
    if #keys == 0 then return false, "unbound", keys end
    local ok, reason = self:Bind(keys, opts)
    return ok, reason, keys
end

function Handle:Unbind(keys)
    local state = states[self]
    return Staged(state, StageUnbind(state, keys))
end

function Handle:Keys()
    local copy = {}
    for key, spec in pairs(states[self].keys) do copy[key] = spec end
    return copy
end

function Handle:Applied()
    local copy = {}
    for key, spec in pairs(states[self].bound) do copy[key] = spec end
    return copy
end

function Handle:Do(fn, key)
    local state = states[self]
    if type(fn) ~= "function" then return false, "invalid" end
    local todo = state.pending.todo
    local replaced = false
    if key ~= nil then
        for _, entry in ipairs(todo) do
            if entry.key == key then
                entry.fn, replaced = fn, true
                break
            end
        end
    end
    if not replaced then todo[#todo + 1] = { fn = fn, key = key } end
    return Flush(state)
end

function Handle:Release()
    local state = states[self]
    for suffix in pairs(state.suffixes) do StageAction(state, nil, suffix ~= "" and suffix or nil) end
    StageShown(state, false)
    StageUnbind(state, nil)
    return Flush(state)
end

---------------------------------------------------------------------------
-- Anlegen und Nachschlagen
---------------------------------------------------------------------------

local function StageOpts(state, opts)
    local ok, reason = true, nil
    local function Step(a, b)
        if ok and not a then ok, reason = false, b end
    end
    if opts.attributes ~= nil then Step(StageAttrs(state, opts.attributes)) end
    if opts.action ~= nil then Step(StageAction(state, opts.action, opts.button)) end
    if opts.size ~= nil then
        if type(opts.size) == "table" then Step(StageSize(state, opts.size[1], opts.size[2])) else Step(false, "invalid") end
    end
    if opts.anchor ~= nil then
        if type(opts.anchor) == "function" then
            Step(StageAnchor(state, opts.anchor))
        elseif type(opts.anchor) == "table" then
            Step(StageAnchor(state, opts.anchor[1], opts.anchor[2], opts.anchor[3], opts.anchor[4], opts.anchor[5]))
        else
            Step(false, "invalid")
        end
    end
    if opts.shown ~= nil then Step(StageShown(state, opts.shown)) end
    if opts.bind ~= nil then Step(StageBind(state, opts.bind, opts.bindOpts)) end
    return ok, reason
end

--[[
    Core.SecureButton(name, opts) → knopf | nil, grund   ("invalid", "secret", "taken")
    Zweite Rückgabe bei Erfolg: nil, oder "combat", solange der Knopf bzw. sein Anfangszustand auf das Kampfende
    wartet, oder der Grund, aus dem ein Teil der opts nicht übernommen wurde.
]]
function Core.SecureButton(name, opts)
    if Core.IsSecret(name) then return nil, "secret" end
    if type(name) ~= "string" or name == "" or (opts ~= nil and type(opts) ~= "table") then return nil, "invalid" end
    opts = opts or {}
    local handle = handles[name]
    local state = handle and states[handle]
    local fresh = state == nil
    if state then
        if opts.owner ~= nil and state.owner ~= nil and opts.owner ~= state.owner then return nil, "taken" end
        -- früher gescheitert (z. B. Name inzwischen fremd belegt): neu versuchen – mit demselben Knopf, damit Griffe,
        -- die ein Modul schon hält, gültig bleiben
        if state.failed and not state.frame then state.failed = nil end
        if opts.hideInCombat ~= nil and (opts.hideInCombat == true) ~= state.hideInCombat then
            state.hideInCombat = opts.hideInCombat == true
            if state.frame then state.pending.shown = state.shown end
        end
    else
        if _G[name] ~= nil then return nil, "taken" end
        handle = setmetatable({}, Handle)
        state = {
            handle = handle, name = name, owner = opts.owner, parent = opts.parent, template = opts.template,
            clicks = opts.clicks, useOnKeyDown = opts.useOnKeyDown == "cvar" and "cvar" or opts.useOnKeyDown == true,
            hideInCombat = opts.hideInCombat == true,
            onCreate = type(opts.onCreate) == "function" and opts.onCreate or nil,
            attrs = {}, keys = {}, bound = {}, suspended = {}, suffixes = {}, shown = false,
            pending = { attrs = {}, binds = {}, todo = {} },
        }
        states[handle], handles[name] = state, handle
        order[#order + 1] = name
    end
    local staged, stageReason = StageOpts(state, opts)
    local ok, reason = Flush(state)
    if not ok and reason ~= "combat" and not state.frame then
        -- Anlegen gescheitert. Ein Knopf, den schon jemand hält, bleibt bestehen und meldet den Grund bei jeder
        -- Methode (state.failed); ein neuer gibt den Namen wieder frei, damit ein späterer Versuch neu beginnt
        if not fresh then return nil, reason end
        states[handle], handles[name] = nil, nil
        for index = #order, 1, -1 do
            if order[index] == name then table.remove(order, index) end
        end
        return nil, reason
    end
    if not staged then return handle, stageReason end
    return handle, (not ok) and reason or nil
end

function SecureButtons.Get(name)
    return type(name) == "string" and handles[name] or nil
end

function SecureButtons.List()
    local list = {}
    for index, name in ipairs(order) do list[index] = name end
    return list
end

function SecureButtons.Count()
    local waiting = 0
    for _, name in ipairs(order) do
        if handles[name]:Pending() then waiting = waiting + 1 end
    end
    return #order, waiting
end

function SecureButtons.StatusLine()
    local count, waiting = SecureButtons.Count()
    if count == 0 then return nil end
    local L = Core.L
    if waiting > 0 then return L.STATUS_SECURE_WAITING:format(count, waiting) end
    return L.STATUS_SECURE:format(count)
end

-- Tasten, die heute auf einem Befehl liegen (z. B. "INTERACTTARGET"). Übersteuerungen zählen nicht mit.
function SecureButtons.KeysOf(command)
    local keys = {}
    if Core.IsSecret(command) or type(command) ~= "string" or command == "" or type(GetBindingKey) ~= "function" then return keys end
    local result = { pcall(GetBindingKey, command) }
    if result[1] then
        for index = 2, #result do
            local key = result[index]
            if not Core.IsSecret(key) and type(key) == "string" and key ~= "" then keys[#keys + 1] = key end
        end
    end
    return keys
end

-- Stellvertreter für eine Taste (Kopf oben). → true (angelegt oder vorgemerkt, bis es den Rahmen von ziel gibt)
-- | false, grund ("invalid", "secret", "taken": ziel hat schon einen Stellvertreter mit anderem Namen bzw. der Name
-- gehört einem fremden Rahmen, "combat": wartet auf das Kampfende)
function SecureButtons.KeyProxy(target, name, owner)
    if Core.IsSecret(target) or Core.IsSecret(name) then return false, "secret" end
    if type(target) ~= "string" or target == "" or type(name) ~= "string" or name == "" or name == target then
        return false, "invalid"
    end
    local wish = proxyWishes[target]
    if wish and wish.name ~= name then return false, "taken" end
    proxyWishes[target] = wish or { name = name, owner = owner or ADDON }
    local ok, reason = LinkProxy(target)
    if not ok and reason ~= nil then return false, reason end
    return true
end

function SecureButtons.ProxyOf(target)
    return type(target) == "string" and proxies[target] or nil
end

---------------------------------------------------------------------------
-- Kampfbeginn und Kampfende
---------------------------------------------------------------------------

-- PLAYER_REGEN_DISABLED: Die Sperre greift erst nach dem Ereignis – Tasten mit inCombat = false jetzt lösen,
-- Knöpfe mit hideInCombat ohne Zustandstreiber jetzt ausblenden. → Anzahl gelöster Tasten.
function SecureButtons.OnCombatStart()
    local released = 0
    if Core.InCombat() then return released end
    for _, name in ipairs(order) do
        local state = states[handles[name]]
        if state.frame then
            for key, spec in pairs(state.bound) do
                if spec.inCombat == false then
                    ClearKey(state, key)
                    state.suspended[key] = spec
                    released = released + 1
                end
            end
            if state.hideInCombat and not state.driver and state.shown and state.pending.shown == nil then
                state.frame:Hide()
                state.combatHidden = true
            end
        end
    end
    return released
end

-- PLAYER_REGEN_ENABLED (nach Core.RunAfterCombat): gelöste Tasten wieder setzen, Ausgeblendetes wieder zeigen.
function SecureButtons.OnCombatEnd()
    for _, name in ipairs(order) do
        local state = states[handles[name]]
        local again = false
        for key, spec in pairs(state.suspended) do
            if state.pending.binds[key] == nil and state.keys[key] == spec then
                state.pending.binds[key] = spec
                again = true
            end
        end
        state.suspended = {}
        if state.combatHidden then
            state.combatHidden = nil
            if state.pending.shown == nil then
                state.pending.shown = state.shown
                again = true
            end
        end
        if again then Flush(state) end
    end
end

Core.RegisterEvent(ADDON, "PLAYER_REGEN_DISABLED", function() SecureButtons.OnCombatStart() end)
Core.RegisterEvent(ADDON, "PLAYER_REGEN_ENABLED", function() SecureButtons.OnCombatEnd() end)
