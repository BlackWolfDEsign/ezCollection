local _, ns = ...
local L = ns.L
local UI = ns.UI
local Core = ezCore

--[[
    Angeln mit einer Taste (Welle 2b, Thema 3; Entscheidung des Nutzers vom 13.11.2026: „Ja, in ezMacro“ –
    auswerfen, während des Angelns holt dieselbe Taste über Blizzards „Mit Ziel interagieren“ ein; nur außerhalb des
    Kampfes, kein automatisches Einholen).

    Technik (ezCores Dienst Core.SecureButton, docs/ezcore.md „Sichere Knöpfe“):
      - ein unsichtbarer sicherer Knopf „ezMacroFishing“ (Besitzer ezMacro) mit der Aktion „Angeln“ (Zaubername vom
        Client, so wirkt immer der höchste Rang)
      - eingeschaltet, mit angelegter Angel und außerhalb des Angel-Kanals legt ezMacro die Tasten, die heute auf
        Blizzards Befehl „Mit Ziel interagieren“ (INTERACTTARGET) liegen, als Übersteuerung auf den Knopf
        (knopf:Bind(tasten, { inCombat = false })) – Blizzards eigene Belegung bleibt unberührt
      - beginnt der Angel-Kanal, nimmt ezMacro die Übersteuerung weg: dieselbe Taste ist wieder Blizzards
        „Mit Ziel interagieren“ und holt den Schwimmer ein, wenn der Spieler sie drückt. Nichts geschieht von selbst.
      - endet der Kanal, liegt die Taste wieder auf „Auswerfen“
      - Kampfbeginn: ezCores Dienst löst die Taste (inCombat = false), nach dem Kampf setzt er sie wieder;
        abschalten, Angel ablegen oder „Angeln“ verlernen lösen sie sofort (außerhalb des Kampfes)
      - Kampfbeginn mitten im Angeln: ob der Kanal endet, meldet nur UNIT_SPELLCAST_CHANNEL_STOP – der Zustand
        bleibt bis dahin stehen, nach dem Kampf legt ezMacro die Taste passend (läuft der Kanal noch: einholen)
      - ändert der Spieler die Belegung (UPDATE_BINDINGS), legt ezMacro die neuen Tasten um – nur, wenn sie sich
        wirklich geändert haben (das Setzen einer Übersteuerung löst dasselbe Ereignis aus)
      - Taste noch gedrückt (Spieltest 15.11.2026: „holt beim 2. Klick nicht den Fisch rein, sondern wirft neu aus“):
        Blizzards „Mit Ziel interagieren“ wirkt beim Drücken, der Knopf (RegisterForClicks "AnyUp", useOnKeyDown
        false – Blizzards SecureActionButton_OnClick, Zweig forever) erst beim Loslassen. Holt der Druck den Schwimmer
        ein, endet der Kanal, während die Taste noch unten ist; lag „Auswerfen“ dann sofort wieder auf ihr, warf das
        Loslassen neu aus. Darum legt ezMacro die Taste erst wieder auf den Knopf, wenn sie losgelassen ist
        (IsKeyDown, Blick alle HOLD_RETRY Sekunden, spätestens nach HOLD_MAX); kennt der Client IsKeyDown nicht,
        wartet ezMacro nach dem Kanal-Ende SETTLE Sekunden. Stand solange „held“.
      - Diagnose für den Spieltest: „/ezmacro angeln status“, der Knopf „Status im Chat“ und die Zeile „Diagnose“ der
        Werkzeug-Seite nennen Stand, ob der Kanal erkannt ist, was gerade auf den Tasten liegt (GetBindingAction mit
        Übersteuerung) und die letzten Ereignisse mit Zeit (Fishing.Diagnose)
    Im Spiel zu prüfen: ob „Mit Ziel interagieren“ auf Forever den Schwimmer nimmt (Soft-Target). Klappt das nicht,
    bleibt Auswerfen auf der Taste nutzbar und Einholen geht wie gewohnt per Rechtsklick auf den Schwimmer.

    Angel-Set: Welches Ausrüstungsset zum Angeln gehört, wählt der Spieler in ezGear (Menü „Sets“, Eintrag „Angeln“ –
    ein Set aus Blizzards Ausrüstungsmanager, kein fester Name). ezGear bietet es seit Welle 3 über seine Schnittstelle
    an: ezCore.API("ezGear").ToggleFishing legt das gewählte Set an bzw. wieder ab (im Kampf vorgemerkt; ohne gewähltes
    Set meldet es „noset“ und sagt es im Chat). Das Umziehen beim Auswerfen ist ezGears eigene Einstellung, nicht
    dieser Knopf. Läuft ezGear, ist der Knopf „Angel-Set“ aktiv; sonst grau, und die Seite sagt, dass er ezGear braucht.

    Rücksicht auf fremde Addons (Leitlinie 9): Läuft ein Addon, das Angeln mit einer Taste schon erledigt
    (ezCore: Core.WhoHandles("fishing"); docs/fremd-addons.md nennt Forever Angler, Fishing-OneKey, Better Fishing
    und Angleur), legt ezMacro keine Taste um und zeigt Stand „other“ mit dessen Namen (ns.OtherFor des Gerüsts).
    Die Funktion „fishing“ fehlt in ezCores Liste noch („wartet auf ezCore“, docs/roadmap/ezMacro.md) – bis dahin
    liefert die Abfrage nil.

    Zauber „Angeln“: aus ezCore (Spells.FISHING, in ns.CORE_NEEDS geprüft; dort steht die Quelle) – keine eigene Zahl mehr
    (MACRO-18).

    Sichere Knöpfe (Core.SecureButton, Core.SecureButtons) und Core.WeaponKind prüft ezCore über ns.CORE_NEEDS (EC-67).
]]
local Fishing = {}
ns.Fishing = Fishing

local SPELL = Core.Spells and Core.Spells.FISHING   -- „Angeln“ (ezCore, MACRO-18)
local BUTTON = "ezMacroFishing"
local COMMAND = "INTERACTTARGET"
local AFTER_KEY = "fishing"

local HOLD_RETRY = 0.1  -- Sekunden zwischen zwei Blicken, ob die Taste losgelassen ist
local HOLD_MAX = 3      -- spätestens nach so vielen Sekunden liegt „Auswerfen“ wieder auf der Taste
local SETTLE = 0.5      -- ohne IsKeyDown: so lange nach dem Kanal-Ende warten
local LOGIN_RECHECK = 2 -- Sekunden nach dem Betreten der Welt (Einloggen, /reload): noch einmal nachsehen
local REBIND_MAX, REBIND_WINDOW = 3, 10   -- höchstens so oft neu belegen, wenn der Client die Taste verwirft, je Fenster (s)
Fishing.HOLD_RETRY, Fishing.HOLD_MAX, Fishing.SETTLE = HOLD_RETRY, HOLD_MAX, SETTLE
Fishing.LOGIN_RECHECK, Fishing.REBIND_MAX, Fishing.REBIND_WINDOW = LOGIN_RECHECK, REBIND_MAX, REBIND_WINDOW
local CAST_ACTION = "CLICK " .. BUTTON .. ":LeftButton"   -- so nennt GetBindingAction(taste, true) ezMacros Knopf

local channeling = false
local state = "off"   -- off | on | reel | held | taken | noPole | noSpell | unbound | missing | combat | other
local otherName       -- Name des fremden Addons bei Stand „other“
local heldSince       -- seit wann ezMacro auf das Loslassen der Taste wartet (Core.Uptime) | nil
local settleUntil = 0 -- ohne IsKeyDown: bis dahin gilt die Taste nach dem Kanal-Ende als gedrückt
local retryQueued = false
local notes = {}      -- letzte Ereignisse für die Diagnose: { event = Name, at = Core.Uptime() }, neuestes vorn
local rebinds = {}    -- Zeiten (Core.Uptime), zu denen ezMacro eine verworfene Belegung neu gelegt hat

local Plain = Core.Plain   -- Wert nur, wenn er nicht geheim ist (ezCore, Leitlinie 2)

-- Fremdes Addon, das Angeln mit einer Taste schon erledigt (ezCore) → Name | nil
function Fishing.Other()
    local name = ns.OtherFor("fishing")       -- Gerüst: Core.WhoHandles, innen gesichert
    if type(name) == "string" and name ~= "" then return name end
    return nil
end

function Fishing.SpellName()
    local name = ns.SpellName(SPELL)
    return type(name) == "string" and name ~= "" and name or nil
end

function Fishing.Known() return ns.IsSpellKnown(SPELL) end

function Fishing.PoleEquipped()
    return Core.WeaponKind("main") == "fishing"
end

-- ezCores sichere Knöpfe gibt es immer, wenn ezMacro läuft (ns.CORE_NEEDS); bleibt als Abfrage für Seite und Tests.
function Fishing.Available()
    return true
end

function Fishing.Keys() return Core.SecureButtons and Core.SecureButtons.KeysOf(COMMAND) or {} end

function Fishing.State() return state end
function Fishing.Channeling() return channeling end

-- Der sichere Knopf (wird beim ersten Einschalten angelegt).
function Fishing.Button(create)
    if not Fishing.Available() then return nil end
    local knopf = Core.SecureButtons.Get(BUTTON)
    if knopf or not create then return knopf end
    knopf = Core.SecureButton(BUTTON, {
        owner = "ezMacro",
        onCreate = function(frame)
            -- unsichtbar; der Tooltip erklärt ihn, falls ihn jemand über /fstack findet
            frame:HookScript("OnEnter", function(self) UI.Tip(self, L.FISH_TITLE, L.FISH_DESC) end)
            frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
        end,
    })
    return knopf
end

local function SameKeys(bound, keys)
    local count = 0
    for _ in pairs(bound) do count = count + 1 end
    if count ~= #keys then return false end
    for _, key in ipairs(keys) do
        if not bound[key] then return false end
    end
    return true
end

local function Release()
    local knopf = Fishing.Button(false)
    if knopf and next(knopf:Keys()) ~= nil then knopf:Unbind() end
end

-- Grundtaste einer Belegung ohne Umschalttasten: "SHIFT-F" » "F", "ALT-CTRL-BUTTON4" » "BUTTON4", "SHIFT--" » "-".
function Fishing.BaseKey(key)
    if Core.IsSecret(key) or type(key) ~= "string" then return nil end
    local base = key
    for _ = 1, 4 do
        local rest = base:match("^ALT%-(.+)$") or base:match("^CTRL%-(.+)$") or base:match("^SHIFT%-(.+)$")
            or base:match("^META%-(.+)$")
        if not rest then break end
        base = rest
    end
    return base
end

-- Maustaste einer Grundtaste in Blizzards Schreibweise für IsMouseButtonDown (mouseButton): "BUTTON1" » "LeftButton",
-- "BUTTON4" » "Button4"; keine Maustaste » nil.
local MOUSE_NAMES = { "LeftButton", "RightButton", "MiddleButton" }
function Fishing.MouseButton(base)
    local n = type(base) == "string" and tonumber(base:match("^BUTTON(%d+)$"))
    if not n then return nil end
    return MOUSE_NAMES[n] or ("Button" .. n)
end

-- Sagt der Client lesbar „gedrückt“? Gesperrte oder fehlerhafte Auskunft: nein (Leitlinie 6).
local function Asks(fn, arg)
    if type(fn) ~= "function" then return false end
    local ok, down = pcall(fn, arg)
    return ok and not Core.IsSecret(down) and down == true
end

-- Ist eine der Tasten gerade gedrückt? Fragt IsKeyDown des Clients (Grundtaste), bei Maustasten („BUTTON4“)
-- zusätzlich IsMouseButtonDown – ob IsKeyDown die Bindungs-Schreibweise der Maus kennt, ist nicht belegt.
-- Fehlt IsKeyDown, gilt die Taste bis SETTLE Sekunden nach dem Kanal-Ende als gedrückt.
function Fishing.KeyHeld(keys)
    local isDown = rawget(_G, "IsKeyDown")
    if type(isDown) ~= "function" then return Core.Uptime() < settleUntil end
    local mouseDown = rawget(_G, "IsMouseButtonDown")
    for _, key in ipairs(keys or {}) do
        local base = Fishing.BaseKey(key)
        if base then
            if Asks(isDown, base) then return true end
            local mouse = Fishing.MouseButton(base)
            if mouse and Asks(mouseDown, mouse) then return true end
        end
    end
    return false
end

-- Ereignis für die Diagnose merken (die letzten NOTES, neuestes vorn): Das eigene Lösen der Taste löst
-- UPDATE_BINDINGS aus – allein als „letztes Ereignis“ verdeckte es den Kanal-Beginn.
local NOTES = 3
local function Note(event)
    table.insert(notes, 1, { event = event, at = Core.Uptime() })
    notes[NOTES + 1] = nil
end

-- Nochmals nachsehen, sobald die Taste losgelassen sein könnte (ein wartender Blick genügt).
local function RetryLater()
    if retryQueued then return end
    retryQueued = true
    C_Timer.After(HOLD_RETRY, function()
        retryQueued = false
        if state ~= "held" then return end
        Fishing.Update()
        ns.Tools.RefreshKey("fishing")
    end)
end

-- Kanalisiert der Spieler gerade gar nichts? Nur wenn der Client es lesbar sagt (UnitChannelInfo liefert nil);
-- fehlt die Funktion oder ist die Auskunft gesperrt, bleibt es bei dem, was die Ereignisse gemeldet haben.
local function NoChannel()
    local info = rawget(_G, "UnitChannelInfo")
    if type(info) ~= "function" then return false end
    local ok, name = pcall(info, "player")
    if not ok or Core.IsSecret(name) then return false end
    return name == nil
end

-- Hält der Client die Übersteuerung nicht mehr, obwohl ezMacro sie gesetzt hat? (Spieltest 15.11.2026: „angel geht
-- nicht nach reload“ – Vermutung: der Client verwirft eine früh gesetzte Übersteuerung, etwa wenn er nach dem
-- Einloggen die Belegung lädt; knopf:Keys() nennt nur, was ezMacro will.) Geprüft werden nur Tasten, die ezCore gerade
-- gesetzt hat (knopf:Applied()) – nicht die beim Kampfbeginn ausgesetzten (inCombat = false), die ezCore erst nach
-- PLAYER_REGEN_ENABLED zurücklegt, und nicht wartende. Nur eine lesbare, abweichende Auskunft zählt als verloren;
-- fehlt GetBindingAction oder ist die Antwort gesperrt bzw. fehlerhaft, bleibt es beim Gemerkten (Leitlinie 6).
function Fishing.Lost(keys)
    local get = rawget(_G, "GetBindingAction")
    local knopf = Fishing.Button(false)
    if type(get) ~= "function" or not knopf or type(knopf.Applied) ~= "function" then return false end
    local applied = knopf:Applied()
    for _, key in ipairs(keys or {}) do
        if applied[key] then
            local ok, action = pcall(get, key, true)
            if ok and not Core.IsSecret(action) and type(action) == "string" and action ~= CAST_ACTION then return true end
        end
    end
    return false
end

-- Neu belegen erlaubt? Höchstens REBIND_MAX Mal je REBIND_WINDOW Sekunden – legt ein anderes Addon die Taste dauerhaft
-- mit Vorrang um, liefe jedes Neulegen sonst in das nächste UPDATE_BINDINGS.
local function MayRebind()
    local now, kept = Core.Uptime(), {}
    for _, at in ipairs(rebinds) do
        if now - at < REBIND_WINDOW then kept[#kept + 1] = at end
    end
    rebinds = kept
    if #rebinds >= REBIND_MAX then return false end
    rebinds[#rebinds + 1] = now
    return true
end

-- Nach dem Kampf (ns.AfterCombat): Taste neu legen. Sicherheitsnetz für ein im Kampf verlorenes Kanal-Ende: Sagt
-- der Client, dass nichts mehr kanalisiert wird, gilt das Angeln als beendet – sonst bliebe die Taste auf „einholen“.
local UpdateAfterCombat
function UpdateAfterCombat()
    if channeling and NoChannel() then channeling = false end
    Fishing.Update()
    ns.Tools.RefreshKey("fishing")
end

-- Taste setzen oder lösen, je nach Lage. → Stand (siehe oben)
function Fishing.Update()
    if not ns.db then return state end
    if not Fishing.Available() then
        state = "missing"
        return state
    end
    if ns.InCombat() then
        -- Im Kampf ändert ezMacro nichts; ezCores Dienst hat die Taste beim Kampfbeginn gelöst
        ns.AfterCombat(UpdateAfterCombat, AFTER_KEY)
        state = ns.S.fishingKey and "combat" or "off"
        return state
    end
    local name = Fishing.SpellName()
    local want = ns.S.fishingKey == true
    otherName = want and Fishing.Other() or nil
    if otherName then
        state, want = "other", false
    elseif want and not (name and Fishing.Known()) then
        state, want = "noSpell", false
    elseif want and not Fishing.PoleEquipped() then
        state, want = "noPole", false
    elseif want and channeling then
        state, want = "reel", false
    end
    if not want then
        heldSince = nil
        Release()
        if not ns.S.fishingKey then state = "off" end
        return state
    end
    local knopf = Fishing.Button(true)
    if not knopf then
        state = "missing"
        return state
    end
    if knopf:Get("spell") ~= name or knopf:Get("type") ~= "spell" then knopf:SetAction({ type = "spell", spell = name }) end
    local keys = Fishing.Keys()
    if #keys == 0 then
        Release()
        state = "unbound"
        return state
    end
    local bound, taken = SameKeys(knopf:Keys(), keys), false
    if bound and Fishing.Lost(keys) then
        -- ezMacro meint, die Taste liegt auf dem Knopf, der Client sagt etwas anderes: neu legen – oder, nach
        -- REBIND_MAX Versuchen, sagen, dass etwas anderes die Taste hält (Diagnose nennt was)
        if MayRebind() then
            Note("rebind")
            bound = false
        else
            taken = true
        end
    end
    if not bound then
        -- Taste noch unten (etwa der Druck, der gerade eingeholt hat): erst nach dem Loslassen belegen, sonst wirft
        -- das Loslassen über den Knopf neu aus
        if Fishing.KeyHeld(keys) then
            heldSince = heldSince or Core.Uptime()
            if Core.Uptime() - heldSince < HOLD_MAX then
                Release()
                if state ~= "held" then Note("held") end
                state = "held"
                RetryLater()
                return state
            end
        end
        knopf:Unbind()
        knopf:Bind(keys, { inCombat = false })
    end
    heldSince = nil
    state = taken and "taken" or "on"
    return state
end

-- Knopf „Einschalten/Ausschalten“ auf der Werkzeug-Seite und Befehl.
function Fishing.Toggle()
    ns.SetSetting("fishingKey", not ns.S.fishingKey)
    Fishing.Update()
    ns.Print(L.FISH_TITLE .. ": " .. Fishing.StatusText())
end

-- Angel-Set aus ezGear, falls dessen Schnittstelle es anbietet.
function Fishing.GearSet()
    local gear = Core.API and Core.API("ezGear")
    if type(gear) == "table" and type(gear.ToggleFishing) == "function" then return gear.ToggleFishing end
    return nil
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------

local function IsFishingCast(spellID)
    spellID = Plain(spellID)
    if not spellID then return false end
    local name = Fishing.SpellName()
    return name ~= nil and ns.SpellName(spellID) == name
end

-- Nutzlast im Forever-Client: Einheit, castGUID (nil!), spellID, castBarID (Daten-Probe 15.11.2026) – spellID steht
-- an derselben Stelle wie bisher.
ns.OnUnit("UNIT_SPELLCAST_CHANNEL_START", "player", function(event, _, _, spellID)
    if not IsFishingCast(spellID) then return end
    Note(event)
    channeling = true
    Fishing.Update()
    ns.Tools.RefreshKey("fishing")
end)

ns.OnUnit("UNIT_SPELLCAST_CHANNEL_STOP", "player", function(event, _, _, spellID)
    if not channeling then return end
    -- Leitlinie 6: geheim zuerst prüfen; ein geheimer oder fehlender spellID beendet den Kanal (kein Vergleich darauf)
    if not Core.IsSecret(spellID) and spellID ~= nil and not IsFishingCast(spellID) then return end
    Note(event)
    channeling = false
    settleUntil = Core.Uptime() + SETTLE
    Fishing.Update()
    ns.Tools.RefreshKey("fishing")
end)

ns.On("PLAYER_EQUIPMENT_CHANGED", function(event, slot)
    slot = Plain(slot)
    if slot == nil or slot == 16 then
        if ns.S and ns.S.fishingKey then Note(event) end
        Fishing.Update()
        ns.Tools.RefreshKey("fishing")
    end
end)
ns.On("UPDATE_BINDINGS", function(event)
    if ns.S and ns.S.fishingKey then
        Note(event)
        Fishing.Update()
        ns.Tools.RefreshKey("fishing")
    end
end)
ns.On("SPELLS_CHANGED", function()
    if ns.S and ns.S.fishingKey then Fishing.Update() end
end)
ns.On("PLAYER_REGEN_DISABLED", function()
    -- Kampfbeginn mitten im Angeln: die Taste löst ezCores Dienst (inCombat = false). „channeling“ bleibt stehen –
    -- ob der Kampf das Angeln abbricht, meldet UNIT_SPELLCAST_CHANNEL_STOP; läuft der Kanal über den Kampf hinaus
    -- weiter, holt die Taste danach ein statt neu auszuwerfen (MACRO-24: vorher galt der Kanal hier als beendet).
    if not channeling then return end
    Note("PLAYER_REGEN_DISABLED")
    -- Im Stand „reel“ lag keine Taste auf dem Knopf, also setzt ezCores Dienst nach dem Kampf auch keine zurück.
    -- Darum Update nach dem Kampf vormerken. Erst im nächsten Bild: Die Sperre greift erst nach diesem Ereignis,
    -- ein Update jetzt liefe noch vor dem Kampf.
    state = "combat"
    C_Timer.After(0, function() ns.AfterCombat(UpdateAfterCombat, AFTER_KEY) end)
end)

ns.OnReady(function() Fishing.Update() end)
-- Nach dem Einloggen und nach /reload noch einmal nachsehen – sofort und nach LOGIN_RECHECK Sekunden. Ausrüstung,
-- Zauberbuch und Belegung sind bei PLAYER_LOGIN (OnReady) nicht in jedem Client vollständig da, und eine dort gesetzte
-- Übersteuerung kann der Client verwerfen (Spieltest 15.11.2026: „angel geht nicht nach reload“).
local function Recheck()
    if not (ns.S and ns.S.fishingKey) then return end
    Fishing.Update()
    ns.Tools.RefreshKey("fishing")
end
ns.On("PLAYER_ENTERING_WORLD", function(event)
    if not (ns.S and ns.S.fishingKey) then return end
    Note(event)
    Recheck()
    C_Timer.After(LOGIN_RECHECK, Recheck)
end)
ns.OnSettingChanged(function(key)
    if key == "fishingKey" then
        Fishing.Update()
        ns.Tools.RefreshKey("fishing")
    end
end)

---------------------------------------------------------------------------
-- Werkzeug-Seite „Angeln mit einer Taste“ (Reiter „Werkzeuge“)
---------------------------------------------------------------------------

local function KeyText()
    local keys = Fishing.Keys()
    if #keys == 0 then return L.FISH_NO_KEY end
    local names = {}
    for _, key in ipairs(keys) do names[#names + 1] = (GetBindingText and GetBindingText(key, "KEY_")) or key end
    return table.concat(names, ", ")
end

function Fishing.StatusText()
    if not ns.S.fishingKey then return L.FISH_STATE_off end
    if state == "other" then return L.FISH_STATE_other:format(otherName or "?") end
    return (L["FISH_STATE_" .. state] or state):format(KeyText())
end

-- Was liegt gerade auf der Taste? GetBindingAction(taste, true) zählt Übersteuerungen mit („CLICK ezMacroFishing:…“).
local function KeyAction(key)
    local get = rawget(_G, "GetBindingAction")
    if type(get) ~= "function" then return "?" end
    local ok, action = pcall(get, key, true)
    if not ok or Core.IsSecret(action) or type(action) ~= "string" then return "?" end
    if action == "" then return L.FISH_DIAG_NONE end
    return action
end

-- Diagnose für den Spieltest: Stand, Kanal erkannt, Tasten mit dem, was gerade auf ihnen liegt, letzte Ereignisse
-- mit Zeit (noTimes: nur ihre Namen – die Werkzeug-Seite zeichnet nur bei Ereignissen neu, eine Zeit bliebe dort
-- stehen). → { zeilen }
function Fishing.Diagnose(noTimes)
    local keys = {}
    for _, key in ipairs(Fishing.Keys()) do keys[#keys + 1] = key .. " " .. Core.ARROW .. " " .. KeyAction(key) end
    local events = {}
    local now = Core.Uptime()
    for _, note in ipairs(notes) do
        events[#events + 1] = noTimes and note.event
            or L.FISH_DIAG_AGO:format(note.event, Core.Seconds(math.max(0, now - note.at), 1))
    end
    return {
        L.FISH_DIAG_STATE:format(ns.S.fishingKey and state or "off"),
        L.FISH_DIAG_CHANNEL:format(channeling and L.YES or L.NO),
        L.FISH_DIAG_KEYS:format(#keys > 0 and table.concat(keys, ", ") or L.FISH_NO_KEY),
        L.FISH_DIAG_LAST:format(#events > 0 and table.concat(events, ", ") or L.FISH_DIAG_NONE),
    }
end

-- Knopf „Status im Chat“ und „/ezmacro angeln status“
function Fishing.PrintStatus()
    ns.Print(L.FISH_TITLE .. ": " .. Fishing.StatusText())
    for _, line in ipairs(Fishing.Diagnose()) do ns.Print("  " .. line) end
end

ns.Tools.Register({
    key = "fishing", order = 40, place = "oneclick", icon = { "Trade_Fishing", "INV_Fishingpole_02" },
    name = L.FISH_TITLE, why = L.FISH_WHY, desc = L.FISH_DESC,
    status = function() return Fishing.StatusText() end,
    build = function(panel)
        panel.toggle = UI.Button(panel, L.FISH_ON, 140, function() Fishing.Toggle() end, L.FISH_TITLE, L.FISH_TOGGLE_TIP)
        panel.toggle:SetPoint("TOPLEFT", panel.top, "BOTTOMLEFT", 0, -10)
        panel.gear = UI.Button(panel, L.FISH_GEAR, 140, function()
            local toggle = Fishing.GearSet()
            if toggle then Core.Call(toggle) end
        end, L.FISH_GEAR, L.FISH_GEAR_TIP)
        panel.gear:SetPoint("LEFT", panel.toggle, "RIGHT", 6, 0)
        panel.info = UI.Text(panel, "GameFontHighlightSmall", panel.width)
        panel.info:SetPoint("TOPLEFT", panel.toggle, "BOTTOMLEFT", 0, -10)
        panel.diag = UI.Button(panel, L.FISH_DIAG_BUTTON, 140, function() Fishing.PrintStatus() end,
            L.FISH_DIAG_BUTTON, L.FISH_DIAG_TIP)
        panel.diag:SetPoint("TOPLEFT", panel.info, "BOTTOMLEFT", 0, -8)
    end,
    refresh = function(panel)
        panel.toggle:SetText(ns.S.fishingKey and L.FISH_OFF or L.FISH_ON)
        panel.toggle:SetEnabled(not ns.InCombat())
        local gear = Fishing.GearSet()
        panel.gear:SetEnabled(gear ~= nil and not ns.InCombat())
        local lines = {
            L.FISH_INFO_KEY:format(KeyText()),
            Fishing.Known() and L.FISH_INFO_SPELL or L.FISH_INFO_NOSPELL,
            Fishing.PoleEquipped() and L.FISH_INFO_POLE or L.FISH_INFO_NOPOLE,
            gear and L.FISH_INFO_GEAR or L.FISH_INFO_NOGEAR,
        }
        local other = Fishing.Other()
        if other then table.insert(lines, 1, L.FISH_INFO_OTHER:format(other)) end
        -- Diagnose in einer Zeile (wie „/ezmacro angeln status“, aber ohne Zeiten), damit ein Spieltest eindeutig ist
        lines[#lines + 1] = L.FISH_INFO_DIAG:format(table.concat(Fishing.Diagnose(true), " · "))
        panel.info:SetText(table.concat(lines, "\n"))
    end,
})
