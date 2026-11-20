local _, ns = ...
local Core = ezCore
local L = Core.L

--[[
    Tasten-Dienst (V-014, EC-73; Empfehlung „Ja, klein beginnen“ umgesetzt, Antwort offen): Tasten für ez-Knöpfe und
    Fenster in Blizzards Tastaturbelegung (Optionen » Tastaturbelegung » AddOns » „ezCollection“). Die Einträge stehen
    in ezCore/Bindings.xml (Blizzard liest sie beim Start; eine Liste, die sich zur Laufzeit ändert, gibt es dort
    nicht) – Keys.LIST nennt dieselben Einträge mit Text und Ausführung. Zuerst:
      * „ezBuff: fehlenden Buff wirken“ – CLICK auf den sicheren Knopf ezBuffButton (Core.SecureButton; die Taste
        drückt den Knopf, auch im Kampf – geschützt bleibt alles beim Knopf selbst)
      * „ezBuff: Durchbuffen“ – CLICK auf ezBuffGroupNext (Gesamtreview 18.11.2026, T9-NB7: vorher ein eigener
        Abschnitt „ezBuff“ aus ezBuff/Bindings.xml; jetzt stehen beide Tasten von ezBuff an einer Stelle)
        Beide über je einen Stellvertreter (unten; Nachlauf zu T9-NB1, Gesamtreview 18.11.2026)
      * Fenster-Umschalter: Einstellungen „ezCollection“, Fehlerliste, ezLoots Beute-Verlauf
      * ezCombats Flächenmodus an/aus (Einstellungs-Prüfung 19.11.2026, Nr. 100)
      * ezMacros sichere Knöpfe der Helfer „Eine Taste“ (Welle 23a, A52): „Öffnen und Entzaubern“
        (ezMacroOneKeyOpen) und „Begleiter füttern“ (ezMacroOneKeyFeed) – CLICK über je einen Stellvertreter (unten,
        T9-NB1), der den Knopf drückt; die übrigen Helfer
        sind Blizzard-Makros und liegen auf Blizzards Aktionsleisten, „Angeln“ belegt seine Taste selbst
    Weitere Fenster: je eine Zeile hier und in Bindings.xml; ein Modul kann die Ausführung über
    Keys.Register(id, fn, owner) selbst liefern.

    Tastendruck oder Loslassen (Gesamtreview 18.11.2026, T9-NB1): Ein CLICK-Eintrag mit proxy zeigt nicht auf den
    sicheren Knopf des Moduls (button), sondern auf einen Stellvertreter (Core.SecureButtons.KeyProxy). Der folgt
    Blizzards Einstellung „Aktion bei Tastendruck“ und drückt den Knopf; /click und Mausklick am Knopf bleiben, wie
    sie sind. Tasten, die noch auf dem früheren Befehl (old) liegen, zieht Keys.MigrateBindings einmal um.
    Fehlt das Modul, sagt der Name in Blizzards Tastaturbelegung es (T9-NB6, Keys.UpdateNames).

      Keys.LIST                  { { id, binding, text, module, run | secure [, button, proxy, old] } … } in der
                                 Reihenfolge der Belegung (binding = Befehl in Bindings.xml)
      Keys.Run(id)               Fenster-Umschalter ausführen (Bindings.xml ruft das) → true | false, Grund
                                 ("unknown", "module", "secure", "error")
      Keys.Register(id, fn, owner)   Ausführung eines Eintrags aus Keys.LIST durch ein Modul (nil: wieder ezCores)
      Keys.KeyText(id)           → belegte Taste(n) als Text oder nil – für Tooltips der Module („Taste: F5“)
      Keys.Open()                Blizzards Tastaturbelegung öffnen (Knopf „Tasten“ auf der Seite „ezCollection“)
      Keys.BindingName(id)       → Name in Blizzards Tastaturbelegung („… (ezBuff nicht geladen)“, wenn das Modul fehlt)
      Keys.UpdateNames()         alle Namen neu setzen (PLAYER_LOGIN, ADDON_LOADED)
      Keys.SetupProxies()        Stellvertreter der geladenen Module vormerken (PLAYER_LOGIN) → Anzahl
      Keys.MigrateBindings()     Tasten von old auf binding umziehen, nur außerhalb des Kampfes (PLAYER_LOGIN,
                                 UPDATE_BINDINGS) → Anzahl umgezogener Tasten
      Keys.CurrentCommand(befehl) → heutiger Befehl eines früheren (old » binding), sonst befehl unverändert – für
                                 gespeicherte Tastenlisten wie ezMacros Profile (den früheren Befehl führt
                                 Bindings.xml nicht mehr, der Client kennt ihn nicht)
]]

local Keys = {}
Core.Keys = Keys

local function ToggleSettings()
    local panel = rawget(_G, "SettingsPanel")
    if type(panel) == "table" and panel.IsShown and panel:IsShown() then
        -- offen: die Taste schließt. Im Kampf geht das nicht – dann nur ein Hinweis, kein Öffnen nach dem Kampf
        if Core.InCombat() or not HideUIPanel then
            Core.CombatNotice(Core.name, L.PANEL_WHAT)
            return false
        end
        HideUIPanel(panel)
        return true
    end
    return Core.OpenSettings and Core.OpenSettings()
end

local function LootHistory()
    local api = Core.API and Core.API("ezLoot")
    if not (api and api.ToggleHistory) then return false end
    return api.ToggleHistory()
end

-- ezCombats Flächenmodus an/aus (Einstellungs-Prüfung 19.11.2026, Nr. 100): nur ein gespeicherter Wert des Moduls,
-- nichts Geschütztes – deshalb kein CLICK-Eintrag. Die Meldung im Chat kommt von ezCombat.
local function CombatAoe()
    local api = Core.API and Core.API("ezCombat")
    if not (api and api.ToggleAoe) then return false end
    api.ToggleAoe()
    return true
end

Keys.LIST = {
    { id = "settings", binding = "EZCOLLECTION_SETTINGS", text = "KEY_SETTINGS", run = ToggleSettings },
    { id = "errors", binding = "EZCOLLECTION_ERRORS", text = "KEY_ERRORS", run = function() return Core.ShowErrorList() end },
    { id = "lootHistory", binding = "EZCOLLECTION_LOOT_HISTORY", text = "KEY_LOOT_HISTORY", module = "ezLoot", run = LootHistory },
    { id = "combatAoe", binding = "EZCOLLECTION_COMBAT_AOE", text = "KEY_COMBAT_AOE", module = "ezCombat", run = CombatAoe },
    { id = "buff", binding = "CLICK ezBuffButtonKey:LeftButton", text = "KEY_BUFF", module = "ezBuff", secure = true,
        button = "ezBuffButton", proxy = "ezBuffButtonKey", old = "CLICK ezBuffButton:LeftButton" },
    { id = "buffNext", binding = "CLICK ezBuffGroupNextKey:LeftButton", text = "KEY_BUFF_NEXT", module = "ezBuff",
        secure = true, button = "ezBuffGroupNext", proxy = "ezBuffGroupNextKey", old = "CLICK ezBuffGroupNext:LeftButton" },
    { id = "oneKeyOpen", binding = "CLICK ezMacroOneKeyOpenKey:LeftButton", text = "KEY_ONEKEY_OPEN", module = "ezMacro",
        secure = true, button = "ezMacroOneKeyOpen", proxy = "ezMacroOneKeyOpenKey",
        old = "CLICK ezMacroOneKeyOpen:LeftButton" },
    { id = "oneKeyFeed", binding = "CLICK ezMacroOneKeyFeedKey:LeftButton", text = "KEY_ONEKEY_FEED", module = "ezMacro",
        secure = true, button = "ezMacroOneKeyFeed", proxy = "ezMacroOneKeyFeedKey",
        old = "CLICK ezMacroOneKeyFeed:LeftButton" },
}

local byId, byOld, custom = {}, {}, {}
for _, entry in ipairs(Keys.LIST) do
    byId[entry.id] = entry
    if entry.old then byOld[entry.old] = entry end
end

function Keys.Get(id) return byId[id] end

function Keys.CurrentCommand(command)
    if Core.IsSecret(command) or type(command) ~= "string" then return command end
    local entry = byOld[command]
    return entry and entry.binding or command
end

function Keys.Register(id, fn, owner)
    if not byId[id] then return false end
    custom[id] = type(fn) == "function" and { fn = fn, owner = owner } or nil
    return true
end

function Keys.Run(id)
    local entry = byId[id]
    if not entry then return false, "unknown" end
    if entry.secure then return false, "secure" end   -- ein CLICK-Eintrag läuft über den Knopf selbst
    if entry.module and not custom[id] and not (Core.IsLoaded and Core.IsLoaded(entry.module)) then
        Core.Print(Core.name, L.KEY_NO_MODULE:format(entry.module))
        return false, "module"
    end
    local own = custom[id]
    local ok, result = Core.Try(own and own.owner or Core.name, "Keys " .. id, own and own.fn or entry.run)
    if not ok then return false, "error" end
    return result ~= false, nil
end

function Keys.KeyText(id)
    local entry = byId[id]
    if not (entry and GetBindingKey) then return nil end
    local ok, a, b = pcall(GetBindingKey, entry.binding)
    -- noch nicht umgezogen (etwa nach /reload im Kampf): die Taste liegt noch auf dem früheren Befehl und wirkt dort
    if entry.old and ok and (Core.IsSecret(a) or type(a) ~= "string" or a == "") then ok, a, b = pcall(GetBindingKey, entry.old) end
    if not ok or Core.IsSecret(a) or type(a) ~= "string" or a == "" then return nil end
    if Core.IsSecret(b) then b = nil end
    local text = GetBindingText and select(2, pcall(GetBindingText, a)) or a
    if type(b) == "string" and b ~= "" then
        text = text .. ", " .. (GetBindingText and select(2, pcall(GetBindingText, b)) or b)
    end
    return type(text) == "string" and text or a
end

function Keys.Open()
    return Core.OpenPanel and Core.OpenPanel("settings", "keybindings")
end

-- Name eines Eintrags in Blizzards Tastaturbelegung. Fehlt das Modul (nicht installiert oder abgeschaltet), sagt der
-- Name es (T9-NB6) – eine belegte CLICK-Taste tut dann nichts, ohne dass ezCollection davon erfährt (sie läuft nicht
-- über Lua). Vor PLAYER_LOGIN sind die Module noch nicht geladen: dann ohne Zusatz.
local loggedIn = false

function Keys.BindingName(id)
    local entry = byId[id]
    if not entry then return nil end
    local text = L[entry.text]
    if loggedIn and entry.module and not Core.IsLoaded(entry.module) then
        return L.KEY_NAME_NO_MODULE:format(text, entry.module)
    end
    return text
end

function Keys.UpdateNames()
    for _, entry in ipairs(Keys.LIST) do
        _G["BINDING_NAME_" .. entry.binding] = Keys.BindingName(entry.id)
    end
end

-- Stellvertreter der geladenen Module vormerken; angelegt wird er, sobald ihr Knopf entsteht (Core.SecureButtons).
function Keys.SetupProxies()
    local count = 0
    local SB = Core.SecureButtons
    if not (SB and SB.KeyProxy) then return count end
    for _, entry in ipairs(Keys.LIST) do
        if entry.proxy and entry.button and (entry.module == nil or Core.IsLoaded(entry.module)) then
            local ok, reason = SB.KeyProxy(entry.button, entry.proxy, entry.module)
            if ok or reason == "combat" then count = count + 1 end
        end
    end
    return count
end

-- Tasten vom früheren Befehl auf den Stellvertreter umziehen (in den gerade gültigen Belegungssatz, wie Blizzards
-- Tastaturbelegung beim Speichern). Nur außerhalb des Kampfes; SetBinding löst UPDATE_BINDINGS aus, darum der
-- Riegel gegen einen zweiten Lauf mittendrin. → Anzahl umgezogener Tasten
local migrating = false

function Keys.MigrateBindings()
    if migrating or Core.InCombat() then return 0 end
    local getKey, setBinding = rawget(_G, "GetBindingKey"), rawget(_G, "SetBinding")
    if type(getKey) ~= "function" or type(setBinding) ~= "function" then return 0 end
    migrating = true
    local moved = 0
    for _, entry in ipairs(Keys.LIST) do
        if entry.old then
            local result = { pcall(getKey, entry.old) }
            if result[1] then
                for index = 2, #result do
                    local key = result[index]
                    if not Core.IsSecret(key) and type(key) == "string" and key ~= "" then
                        local ok, set = pcall(setBinding, key, entry.binding)
                        if ok and set ~= false then moved = moved + 1 end
                    end
                end
            end
        end
    end
    if moved > 0 then
        local save, current = rawget(_G, "SaveBindings"), rawget(_G, "GetCurrentBindingSet")
        if type(save) == "function" and type(current) == "function" then
            local okSet, set = pcall(current)
            if okSet and (set == 1 or set == 2) then pcall(save, set) end
        end
        Core.Print(Core.name, L.KEY_MOVED:format(moved))
    end
    migrating = false
    return moved
end

local function MigrateLater()
    if loggedIn then Core.AfterCombat(Keys.MigrateBindings, "Keys:migrate", Core.name) end
end

---------------------------------------------------------------------------
-- Tasten, die nur bei offenem Blizzard-Fenster gelten (AH-15, Welle 14)
---------------------------------------------------------------------------
--[[
    Eine fenstergebundene Taste klickt einen sicheren ez-Knopf (ein Tastendruck = ein Klick), solange ein genanntes
    Blizzard-Fenster offen ist – etwa „Einstellen“ am Auktionshaus. Gesetzt als Übersteuerung (SetOverrideBindingClick)
    auf EINEM eigenen Rahmen, nur außerhalb des Kampfes. Gelöst wird beim Schließen des Fensters UND spätestens bei
    PLAYER_REGEN_DISABLED (dort sind geschützte Aufrufe noch erlaubt) – so bleibt im Kampf nie eine Taste gekapert
    und keine Aktionsleisten-Taste ohne Wirkung; neu gesetzt erst nach PLAYER_REGEN_ENABLED, wenn das Fenster noch
    offen ist. Ab Werk ist keine Taste belegt (ezCoreDB.windowKeys).

      Keys.AddWindowKey(id, { frame = "AuctionHouseFrame", button = "ezAuctionPostButton", text = Anzeigename,
                       owner = Modul, addon = "Blizzard_AuctionHouseUI" (lädt das Fenster auf Abruf) }) → true
                       frame und button sind globale Rahmennamen; der Knopf muss beim Öffnen des Fensters bestehen.
      Keys.WindowKeys() → { { id, text, owner, key } … } in der Reihenfolge der Anmeldung
      Keys.WindowKey(id) → belegte Taste oder nil
      Keys.SetWindowKey(id, taste | nil) → true | false, grund ("unknown", "key")   Taste im Format der Tastaturbelegung
                       ("F5", "CTRL-P", "SHIFT-ALT-1"); nil löscht. Gilt sofort, wenn das Fenster offen ist (sonst beim
                       nächsten Öffnen; im Kampf erst danach).
      Keys.NormalizeKey(text, opts) → Taste, Zusatztasten, eigentliche Taste oder nil ("strg-p" » "CTRL-P", "Umschalt-F" »
                       "SHIFT-F", "LALT-ä" » "ALT-ä"; opts.sides: "LALT-ä" bleibt) – Einzelheiten an der Funktion
      Keys.Conflict(taste) → Name der Blizzard-Aktion, die schon auf der Taste liegt (GetBindingAction ohne
                             Übersteuerungen – auch nicht die eigene Fenster-Taste), oder nil
      Keys.AskWindowKey(id)   Knopf „Taste belegen“: fragt die Taste ab, warnt bei einer schon belegten Blizzard-Aktion
      Keys.ApplyWindowKeys()  intern: alle Übersteuerungen neu setzen (nur außerhalb des Kampfes)
      Keys.WindowOpen(id)     → true, solange das Fenster offen ist
]]
Keys.WINDOW_OWNER = "ezCoreWindowKeys"
local windowKeys, windowOrder, windowOpen = {}, {}, {}
local windowOwner, windowBound = nil, false
Core.OwnDefaults("windowKeys", {})

local function Owner()
    if not windowOwner then windowOwner = CreateFrame("Frame", Keys.WINDOW_OWNER) end
    return windowOwner
end

local function ClearWindow()
    if not windowBound then return end
    windowBound = false
    if type(ClearOverrideBindings) == "function" then
        local ok, err = pcall(ClearOverrideBindings, Owner())
        if not ok then Core.Error(Core.name, err, "Keys window clear") end
    end
end

function Keys.WindowKey(id)
    local t = Core.OwnSettings("windowKeys")
    local key = t and t[id]
    return type(key) == "string" and key ~= "" and key or nil
end

function Keys.WindowOpen(id) return windowOpen[id] == true end

function Keys.ApplyWindowKeys()
    if Core.InCombat() then return false end
    ClearWindow()
    if type(SetOverrideBindingClick) ~= "function" then return false end
    local owner = Owner()
    for _, id in ipairs(windowOrder) do
        local w, key = windowKeys[id], Keys.WindowKey(id)
        if key and windowOpen[id] and rawget(_G, w.button) then
            local ok, err = pcall(SetOverrideBindingClick, owner, false, key, w.button, "LeftButton")
            if ok then windowBound = true else Core.Error(w.owner or Core.name, err, "Keys window " .. id) end
        end
    end
    return true
end

local function Hook(id)
    local w = windowKeys[id]
    if not w or w.hooked then return end
    local frame = rawget(_G, w.frame)
    if type(frame) ~= "table" or type(frame.HookScript) ~= "function" then return end
    w.hooked = true
    frame:HookScript("OnShow", function()
        windowOpen[id] = true
        Keys.ApplyWindowKeys()
    end)
    frame:HookScript("OnHide", function()
        windowOpen[id] = nil
        -- im Kampf ist nichts mehr gesetzt (gelöst bei PLAYER_REGEN_DISABLED); danach setzt Apply nur Offenes
        Keys.ApplyWindowKeys()
    end)
    windowOpen[id] = frame.IsShown and frame:IsShown() and true or nil
    if windowOpen[id] then Keys.ApplyWindowKeys() end
end

function Keys.AddWindowKey(id, spec)
    if type(id) ~= "string" or id == "" or type(spec) ~= "table" then return false end
    if type(spec.frame) ~= "string" or type(spec.button) ~= "string" then return false end
    if not windowKeys[id] then windowOrder[#windowOrder + 1] = id end
    windowKeys[id] = { id = id, frame = spec.frame, button = spec.button, text = spec.text or id, owner = spec.owner,
        addon = spec.addon }
    Hook(id)
    return true
end

function Keys.WindowKeys()
    local out = {}
    for _, id in ipairs(windowOrder) do
        local w = windowKeys[id]
        out[#out + 1] = { id = id, text = w.text, owner = w.owner, key = Keys.WindowKey(id) }
    end
    return out
end

local MODIFIERS = { CTRL = "CTRL", STRG = "CTRL", CONTROL = "CTRL", SHIFT = "SHIFT", UMSCHALT = "SHIFT",
    ALT = "ALT", META = "META", CMD = "META" }
local MOD_ORDER = { "ALT", "CTRL", "SHIFT", "META" }
-- Linke und rechte Zusatztasten (Gesamtreview 18.11.2026, Nachlauf zu T9-NB5 aus ezMacro): Blizzard fasst sie in
-- Tastenbelegungen zu ALT, CTRL, SHIFT, META zusammen (CreateKeyChordString…); mit opts.sides bleiben sie stehen.
local SIDE_MODIFIERS = { LALT = "ALT", RALT = "ALT", LCTRL = "CTRL", RCTRL = "CTRL", LSHIFT = "SHIFT",
    RSHIFT = "SHIFT", LMETA = "META", RMETA = "META" }
local SIDE_ORDER = { "LALT", "RALT", "LCTRL", "RCTRL", "LSHIFT", "RSHIFT", "LMETA", "RMETA" }
-- Eigentliche Taste: Buchstaben und Ziffern (F5, NUMPAD1, BUTTON3), genau ein Zeichen („-“, „ä“) – ein Umlaut oder ein
-- anderes Zeichen aus mehreren Bytes zählt als ein Zeichen (deutsche Tastatur: „ä“, „ö“, „ü“, „ß“, „^“)
local function MainKey(main)
    return main:match("^[%w]+$") ~= nil or #main == 1 or (#main <= 4 and main:match("^[\194-\244][\128-\191]+$") ~= nil)
end

--[[
    Keys.NormalizeKey(text, opts) → Taste, Zusatztasten (Liste), eigentliche Taste – oder nil
      "strg-p" » "CTRL-P", "Umschalt+F" » "SHIFT-F"; linke und rechte Zusatztasten („LALT-1“, „RSHIFT-X“) werden zu
      ALT, SHIFT … zusammengefasst, mit opts.sides = true bleiben sie, wie sie sind (für Text aus fremden Profilen,
      ezMacros Profiles.KeyFormat). Die eigentliche Taste darf ein Umlaut sein („ä“; Kleinbuchstaben außerhalb ASCII
      bleiben, wie sie sind). „+“ trennt nur zwischen zwei Teilen („shift+x“); als letztes Zeichen ist es die Plus-
      Taste („+“, „CTRL-+“, „Strg++“, „Strg+“ » „CTRL-+“; Gesamtreview 18.11.2026, Gegenprüfung P13 D2 – vorher wurde daraus die
      Minus-Taste „CTRL--“). Leer-, Steuerzeichen und „|“ in der Taste, mehr als 40 Zeichen, eine Zusatztaste als
      eigentliche Taste oder unbekannte Zusatztasten → nil.
]]
function Keys.NormalizeKey(text, opts)
    if Core.IsSecret(text) or type(text) ~= "string" or #text > 40 then return nil end
    local sides = type(opts) == "table" and opts.sides == true
    text = Core.Trim(text):upper()   -- Core.Trim (Gesamtreview 18.11.2026, T16-15)
    -- Ein „+“ am Ende ist die Plus-Taste selbst; ein Trenner („-“ oder „+“) direkt davor gehört nicht zur Taste
    local plus = text:sub(-1) == "+"
    if plus then
        text = text:sub(1, -2):gsub("%s+$", "")
        text = text:match("^(.-)%s*[%-%+]$") or text
    end
    text = text:gsub("%s*%+%s*", "-")
    if (text == "" and not plus) or text:find("[%s%c|]") then return nil end
    local parts = {}
    for part in text:gmatch("[^%-]+") do parts[#parts + 1] = part end
    if text:sub(-1) == "-" then parts[#parts + 1] = "-" end   -- die Minus-Taste selbst
    if plus then parts[#parts + 1] = "+" end
    local main = table.remove(parts)
    if not main or main == "" or MODIFIERS[main] or SIDE_MODIFIERS[main] then return nil end
    if not MainKey(main) then return nil end
    local mods = {}
    for _, m in ipairs(parts) do
        local norm = MODIFIERS[m] or (sides and SIDE_MODIFIERS[m] and m) or SIDE_MODIFIERS[m]
        if not norm then return nil end
        mods[norm] = true
    end
    local out = {}
    for _, m in ipairs(MOD_ORDER) do if mods[m] then out[#out + 1] = m end end
    if sides then for _, m in ipairs(SIDE_ORDER) do if mods[m] then out[#out + 1] = m end end end
    local list = {}
    for i = 1, #out do list[i] = out[i] end
    out[#out + 1] = main
    return table.concat(out, "-"), list, main
end

-- Gefragt wird die gespeicherte Belegung (ohne checkOverride): sie gilt im Kampf und nach dem Schließen des Fensters.
-- Mit Übersteuerungen meldete sich bei offenem Fenster die eigene Fenster-Taste („CLICK <ez-Knopf>“) als Konflikt.
function Keys.Conflict(key)
    if type(key) ~= "string" or type(GetBindingAction) ~= "function" then return nil end
    local ok, action = pcall(GetBindingAction, key)
    if not ok or Core.IsSecret(action) or type(action) ~= "string" or action == "" then return nil end
    local text = action
    if type(GetBindingName) == "function" then
        local okName, name = pcall(GetBindingName, action)
        if okName and type(name) == "string" and name ~= "" then text = name end
    end
    return text, action
end

function Keys.SetWindowKey(id, key)
    if not windowKeys[id] then return false, "unknown" end
    local t = Core.OwnSettings("windowKeys")
    if not t then return false, "unknown" end
    if key ~= nil then
        key = Keys.NormalizeKey(key)
        if not key then return false, "key" end
    end
    t[id] = key
    Keys.ApplyWindowKeys()   -- im Kampf: tut nichts, PLAYER_REGEN_ENABLED holt es nach
    return true
end

function Keys.AskWindowKey(id)
    local w = windowKeys[id]
    if not (w and Core.AskText) then return false end
    Core.AskText(L.KEY_WINDOW_ASK:format(w.text), Keys.WindowKey(id) or "", function(text)
        if text == nil or text == "" then
            Keys.SetWindowKey(id, nil)
            Core.Print(Core.name, L.KEY_WINDOW_CLEARED:format(w.text))
            return
        end
        local key = Keys.NormalizeKey(text)
        if not key then return Core.Print(Core.name, L.KEY_WINDOW_BAD:format(text)) end
        local function Save()
            Keys.SetWindowKey(id, key)
            Core.Print(Core.name, L.KEY_WINDOW_SET:format(key, w.text))
        end
        local busy = Keys.Conflict(key)
        if busy then
            Core.Confirm(L.KEY_WINDOW_CONFLICT:format(key, busy, w.text), Save, { alert = true })
        else
            Save()
        end
    end, 30)
    return true
end

-- Knöpfe je angemeldeter Taste auf der Seite „ezCollection“ (Collection.lua); ohne Anmeldung nur die Überschrift
function Keys.AddWindowSettings(page)
    if type(page) ~= "table" or type(page.Button) ~= "function" then return false end
    page:Header(L.KEY_WINDOW_HEADER, L.KEY_WINDOW_HEADER_TIP)
    for _, entry in ipairs(Keys.WindowKeys()) do
        local id = entry.id
        page:Button(entry.text, L.KEY_WINDOW_BUTTON, function() Keys.AskWindowKey(id) end,
            L.KEY_WINDOW_TIP:format(entry.text))
    end
    return true
end

ns.On("PLAYER_REGEN_DISABLED", function()
    -- geschützte Aufrufe sind in diesem Augenblick noch erlaubt: jetzt lösen, nicht erst nach dem Kampf
    ClearWindow()
end)
ns.On("PLAYER_REGEN_ENABLED", function() Keys.ApplyWindowKeys() end)
ns.On("ADDON_LOADED", function(_, name)
    for _, id in ipairs(windowOrder) do
        local w = windowKeys[id]
        if not w.hooked and (w.addon == nil or w.addon == name) then Hook(id) end
    end
    if loggedIn then Keys.UpdateNames() end   -- ein später geladenes Modul verliert den Zusatz „nicht geladen“
end)

-- Namen in Blizzards Tastaturbelegung (Leitlinie 7: Texte aus der Locale); ab PLAYER_LOGIN mit dem Zusatz für fehlende
-- Module (T9-NB6), dazu Stellvertreter und Umzug der Tasten (T9-NB1)
_G.BINDING_HEADER_EZCOLLECTION = L.KEY_HEADER
Keys.UpdateNames()
ns.On("PLAYER_LOGIN", function()
    loggedIn = true
    Keys.UpdateNames()
    Keys.SetupProxies()
    MigrateLater()
end)
ns.On("UPDATE_BINDINGS", MigrateLater)   -- etwa ein Profil, das eine Taste noch auf den früheren Befehl legt
