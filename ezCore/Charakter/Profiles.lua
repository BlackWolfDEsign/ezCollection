local _, ns = ...
local Core = ezCore

--[[
    Profile (Core.NewProfiles) – ein Gerüst für ezBag (Layout) und ezPanel (Leiste); vorher zwei Fassungen
    mit eigener Liste, eigenem Wechsel, eigenem Export und eigenen Texten.

    local P = Core.NewProfiles({
        owner = "ezBag",                          -- für Fehler-Log, Ereignisse und Meldungen
        db = function() return ns.db end,         -- Tabelle des Moduls; dort liegen die Felder unten
        snapshot = function() return { … } end,   -- Arbeitsdaten → neue Tabelle (Kopie)
        apply = function(data) end,               -- Tabelle → Arbeitsdaten (auch Auffrischen)
        clean = function(data, v) return data end,-- Import: nur bekannte Felder mit passendem Typ (nil = kaputt)
        kind = "ezBag.groups", version = 1,       -- Kennung im Export-Text
        wrap = "layout",                          -- Feld mit den Daten im Text; false = Felder oben im Text
        default = "Standard",                     -- Name des Standard-Profils (gespeichert, nicht übersetzt)
        scopes = { class = true, spec = true },   -- Zuordnung außer „Charakter“: Klasse, Spezialisierung
        perChar = true,                           -- Auswahl gilt gleich für diesen Charakter (ezPanel)
        texts = L, print = ns.Print, hint = "…", maxName = 40,
        fields = { profiles = …, active = …, assign = …, specMode = … },   -- nur, wenn die Felder anders heißen
        export = function(data) return data end,  -- Export-Filter (V-087): Kopie des Profils → was in den Text kommt
        maxItems = 50000,                         -- höchstens so viele Einträge im Import-Text (Standard Core.PROFILE_MAX_ITEMS)
    })

    Gespeichert: db.profiles[name], db.activeProfile (nil = Standard), db.profileFor[schlüssel]
    (charKey, "class:MAGE", "charKey#Gruppe"), db.specMode[charKey]. Das passende Profil: Spezialisierung
    (wenn an), sonst Charakter, sonst Klasse, sonst Standard. Texte aus ezCore (PROFILE_*), ein Modul kann
    einzelne über opts.texts ersetzen (gleiche Schlüssel).

    P.Active(), P.Label(name), P.Names(), P.Exists(name), P.UniqueName(name)
    P.Save(), P.Switch(name, quiet), P.Use(name, quiet), P.Create(name) → name, P.Delete(name)
    P.Assigned(scope), P.Assign(scope, name), P.Wanted(), P.Load(quiet)
    P.SpecGroup(), P.SpecMode(), P.SetSpecMode(on)
    P.Export() → Text, P.Import(text) → Name | nil, Grund
        opts.export bekommt eine Kopie des Profils und gibt zurück, was in den Text kommt (ohne Charakter-Schlüssel,
        Fraktionslisten …); das gespeicherte Profil bleibt vollständig. Wirft der Filter, gibt es keinen Text.
    P.ShowExport(), P.ShowImport(), P.AskNew(), P.AskDelete(name), P.AskDeleteActive() → false bei „Standard“
    P.ForClass() → gilt das aktive Profil für die Klasse?  P.SetForClass(on) → true, wenn geändert (mit Meldung)
    P.ClassLabel() → Name der Klasse dieses Charakters
    P.FillMenu(root) → Auswahl, Neu, Zuordnung, Löschen, Export/Import (Knoten von MenuUtil); „für die Klasse“
        auch mit perChar (vorher nur ohne)
    P.OnChange(fn(name))
    P.Forget(charKey) → Anzahl gestrichener Einträge: specMode[charKey], profileFor[charKey] und jedes
        profileFor["charKey#…"] (Welle 23a, A14; vorher je eine Kopie in ezCombat und ezGear). Läuft von selbst bei
        CHAR_FORGOTTEN (Core.ForgetChar) – die Module brauchen keinen eigenen Zuhörer mehr.
    page:Profiles(P, opts) (Settings.lua) baut daraus den Abschnitt „Profile“ einer Einstellungsseite.
    Beim Ausloggen sichert ezCore das aktive Profil; mit Spezialisierung wechselt es beim Umschalten mit.
]]

local FIELDS = { profiles = "profiles", active = "activeProfile", assign = "profileFor", specMode = "specMode" }

-- Höchstzahl an Einträgen eines eingefügten Profiltextes (T6-7); ein Modul mit größeren Profilen gibt opts.maxItems an.
Core.PROFILE_MAX_ITEMS = 50000

function Core.NewProfiles(opts)
    opts = opts or {}
    local P = {}
    local owner = opts.owner or "ezCore"
    P.perChar = opts.perChar == true
    local DEFAULT = opts.default or "Standard"
    local scopes = opts.scopes or {}
    P.scopes = scopes
    local L = opts.texts or Core.L
    local maxName = opts.maxName or 40
    local listeners = {}
    local F = {}
    for key, name in pairs(FIELDS) do F[key] = (opts.fields and opts.fields[key]) or name end

    local function Print(msg)
        if opts.print then opts.print(msg) else Core.Print(owner, msg) end
    end

    local scratch = {}
    local function DB()
        local db = opts.db
        if type(db) == "function" then db = db() end
        if type(db) ~= "table" then db = scratch end   -- vor dem Laden: nichts kaputt machen
        if type(db[F.profiles]) ~= "table" then db[F.profiles] = {} end
        if type(db[F.assign]) ~= "table" then db[F.assign] = {} end
        if type(db[F.specMode]) ~= "table" then db[F.specMode] = {} end
        return db
    end

    local function Changed()
        local name = P.Active()
        for _, fn in ipairs(listeners) do
            local ok, err = pcall(fn, name)
            if not ok then Core.Error(owner, err, "profile") end
        end
    end

    local function Snapshot()
        local ok, data = Core.PCall(opts.snapshot)
        if ok and type(data) == "table" then return data end
        if not ok and data ~= nil then Core.Error(owner, data, "profile snapshot") end
        return {}
    end

    local function Apply(data)
        local ok, err = Core.PCall(opts.apply, data)
        if not ok and err ~= nil then Core.Error(owner, err, "profile apply") end
    end

    local function Valid(name)
        return type(name) == "string" and not Core.IsSecret(name) and name ~= "" and name or nil
    end

    function P.OnChange(fn)
        if type(fn) == "function" then listeners[#listeners + 1] = fn end
    end

    ---------------------------------------------------------------------------
    -- Lesen
    ---------------------------------------------------------------------------

    function P.Active()
        return Valid(DB()[F.active]) or DEFAULT
    end

    local function SetActive(name)
        DB()[F.active] = name ~= DEFAULT and name or nil
    end

    function P.Label(name)
        name = name or P.Active()
        if name == DEFAULT then return L.PROFILE_DEFAULT end
        return tostring(name)
    end

    function P.Exists(name)
        return name == DEFAULT or (Valid(name) ~= nil and DB()[F.profiles][name] ~= nil)
    end

    -- Alle Namen, „Standard“ zuerst, dann nach dem Alphabet.
    function P.Names()
        local db = DB()
        local seen, list = { [DEFAULT] = true }, { DEFAULT }
        local function Add(name)
            name = Valid(name)
            if name and not seen[name] then
                seen[name] = true
                list[#list + 1] = name
            end
        end
        for name in pairs(db[F.profiles]) do Add(name) end
        Add(P.Active())
        table.sort(list, function(a, b)
            if (a == DEFAULT) ~= (b == DEFAULT) then return a == DEFAULT end
            return a:lower() < b:lower()
        end)
        return list
    end

    function P.UniqueName(name)
        local db = DB()
        return Core.UniqueName(name, function(n)
            return n == DEFAULT or n == L.PROFILE_DEFAULT or db[F.profiles][n] ~= nil or n == P.Active()
        end, { maxChars = maxName, default = L.PROFILE_IMPORTED })
    end

    ---------------------------------------------------------------------------
    -- Zuordnung: Charakter, Klasse, Spezialisierung
    ---------------------------------------------------------------------------

    function P.SpecGroup()
        return Core.Num((Core.Call(C_SpecializationInfo and C_SpecializationInfo.GetActiveSpecGroup)))
    end

    local function ScopeKey(scope)
        local char = Core.charKey
        if scope == "class" then
            local class = (Core.me and Core.me.class) or Core.PlayerClass()
            return class and ("class:" .. class) or nil
        elseif scope == "spec" then
            local group = P.SpecGroup()
            return group and char and (char .. "#" .. group) or nil
        end
        return char
    end

    function P.SpecMode()
        return scopes.spec == true and Core.charKey ~= nil and DB()[F.specMode][Core.charKey] == true
    end

    function P.Assigned(scope)
        local key = ScopeKey(scope)
        return key and Valid(DB()[F.assign][key]) or nil
    end

    function P.Assign(scope, name)
        local key = ScopeKey(scope)
        if not key then return false end
        DB()[F.assign][key] = Valid(name)
        return true
    end

    -- Passendes Profil: Spezialisierung (wenn an), sonst Charakter, sonst Klasse, sonst Standard.
    function P.Wanted()
        local assign = DB()[F.assign]
        local spec = P.SpecMode() and ScopeKey("spec")
        local class = scopes.class and ScopeKey("class")
        return (spec and Valid(assign[spec])) or Valid(assign[ScopeKey("char") or ""])
            or (class and Valid(assign[class])) or DEFAULT
    end

    ---------------------------------------------------------------------------
    -- Sichern und wechseln
    ---------------------------------------------------------------------------

    function P.Save()
        DB()[F.profiles][P.Active()] = Snapshot()
    end

    -- Wechseln: das aktuelle sichern, das neue übernehmen; ein neues Profil startet als Kopie.
    function P.Switch(name, quiet)
        name = Valid(name)
        if not name then return false end
        if name == P.Active() then return true end
        local db = DB()
        P.Save()
        local data = db[F.profiles][name]
        SetActive(name)
        if data then Apply(data) end
        db[F.profiles][name] = Snapshot()
        if not quiet then Print(L.PROFILE_ACTIVE:format(P.Label(name))) end
        Changed()
        return true
    end

    -- Für diesen Charakter (bzw. seine Spezialisierung) wählen und wechseln. Auch „Standard“ wird
    -- gemerkt, sonst fiele eine Spezialisierung auf das Profil des Charakters zurück.
    function P.Use(name, quiet)
        name = Valid(name)
        if not name then return false end
        local key = ScopeKey(P.SpecMode() and "spec" or "char")
        if key then DB()[F.assign][key] = name end
        if name == P.Active() then
            Changed()
            return true
        end
        return P.Switch(name, quiet)
    end

    function P.SetSpecMode(on)
        on = on and true or false
        if not scopes.spec or not Core.charKey or P.SpecMode() == on then return end
        local db = DB()
        db[F.specMode][Core.charKey] = on or nil
        if on then
            local spec = ScopeKey("spec")
            if spec then db[F.assign][spec] = P.Active() end
        else
            local prefix = Core.charKey .. "#"
            for key in pairs(db[F.assign]) do
                if type(key) == "string" and key:sub(1, #prefix) == prefix then db[F.assign][key] = nil end
            end
        end
        P.Switch(P.Wanted())
        Changed()
    end

    -- Neues Profil aus den Arbeitsdaten, gleich aktiv (mit perChar auch für diesen Charakter).
    function P.Create(name)
        name = Valid(type(name) == "string" and Core.Trim(name) or nil)
        if not name then return nil end
        name = P.UniqueName(name)
        P.Save()
        DB()[F.profiles][name] = Snapshot()
        if opts.perChar then
            P.Use(name, true)
        else
            SetActive(name)
            Changed()
        end
        Print(L.PROFILE_CREATED:format(name))
        return name
    end

    -- Löschen; wer es nutzt, bekommt wieder „Standard“.
    function P.Delete(name)
        name = Valid(name)
        local db = DB()
        if not name or name == DEFAULT or (db[F.profiles][name] == nil and name ~= P.Active()) then return false end
        if name == P.Active() then P.Switch(DEFAULT, true) end
        db[F.profiles][name] = nil
        for key, value in pairs(db[F.assign]) do
            if value == name then db[F.assign][key] = nil end
        end
        Print(L.PROFILE_DELETED:format(name))
        Changed()
        return true
    end

    function P.Load(quiet)
        P.loaded = true
        local wanted = P.Wanted()
        if wanted ~= P.Active() then P.Switch(wanted, quiet) end
    end

    ---------------------------------------------------------------------------
    -- Als Text exportieren und importieren (Core.Serialize)
    ---------------------------------------------------------------------------

    local VERSION = opts.version or 1

    function P.Export()
        P.Save()
        local active = P.Active()
        local data = Core.CopyTable(DB()[F.profiles][active] or {})
        if type(opts.export) == "function" then
            local ok, filtered = pcall(opts.export, data)
            if not ok then
                Core.Error(owner, filtered, "profile export")
                return nil, "filter"
            end
            if type(filtered) == "table" then data = filtered end
        end
        local value = data
        if opts.wrap ~= false then value = { [opts.wrap or "data"] = data } end
        value.kind, value.v, value.name = opts.kind, VERSION, active == DEFAULT and P.Label(active) or active
        return Core.Serialize(value)
    end

    -- Text → neues Profil (Name aus dem Text, bei Gleichheit mit Zusatz), gleich aktiv.
    -- Gesamtreview 18.11.2026: höchstens maxItems Einträge (opts.maxItems, Standard Core.PROFILE_MAX_ITEMS; mehr →
    -- Grund "size", T6-7); der Name aus dem Text ohne „|“-Codes und Steuerzeichen, gekürzt (Core.CleanImportName, T6-5).
    function P.Import(text)
        local value, reason = Core.Deserialize(text, { maxItems = opts.maxItems or Core.PROFILE_MAX_ITEMS })
        if type(value) ~= "table" then return nil, reason or "syntax" end
        if value.kind ~= opts.kind then return nil, "kind" end
        if (tonumber(value.v) or 0) > VERSION then return nil, "version" end
        local data
        if opts.wrap == false then
            data = {}
            for key, v in pairs(value) do
                if key ~= "kind" and key ~= "v" and key ~= "name" then data[key] = v end
            end
        else
            data = value[opts.wrap or "data"]
        end
        if type(opts.clean) == "function" then
            local ok, cleaned = pcall(opts.clean, data, value.v)
            data = ok and cleaned or nil
        end
        if type(data) ~= "table" then return nil, "syntax" end
        local base = Valid(Core.CleanImportName(value.name, maxName))
        if base == DEFAULT or base == L.PROFILE_DEFAULT then base = nil end
        local name = P.UniqueName(base or L.PROFILE_IMPORTED)
        P.Save()
        DB()[F.profiles][name] = data
        if opts.perChar then P.Use(name, true) else P.Switch(name, true) end
        Print(L.PROFILE_IMPORT_DONE:format(name))
        return name
    end

    ---------------------------------------------------------------------------
    -- Dialoge und Menü (Knöpfe auf der Einstellungsseite rufen dieselben Funktionen)
    ---------------------------------------------------------------------------

    function P.ShowExport()
        local text, reason = P.Export()
        if not text then
            Print(L.PROFILE_EXPORT_FAIL:format(L["PROFILE_ERR_" .. tostring(reason)] or tostring(reason)))
            return
        end
        Core.AskText(L.PROFILE_EXPORT_PROMPT:format(P.Label()), text, function() end, 0)
    end

    function P.ShowImport()
        Core.AskText(L.PROFILE_IMPORT_PROMPT, "", function(text)
            if type(text) ~= "string" or text == "" then return end
            local name, reason = P.Import(text)
            if not name then
                Print(L.PROFILE_IMPORT_FAIL:format(L["PROFILE_ERR_" .. tostring(reason)] or tostring(reason)))
            end
        end, 0)
    end

    function P.AskNew()
        Core.AskText(L.PROFILE_NEW_PROMPT, "", function(text) P.Create(text) end, maxName)
    end

    function P.AskDelete(name)
        Core.Confirm(L.PROFILE_DELETE_ASK:format(P.Label(name)), function() P.Delete(name) end)
    end

    -- „Löschen“ auf der Einstellungsseite: das aktive Profil, nach Rückfrage; „Standard“ bleibt immer.
    function P.AskDeleteActive()
        local name = P.Active()
        if name == DEFAULT then
            Print(L.PROFILE_DELETE_DEFAULT)
            return false
        end
        P.AskDelete(name)
        return true
    end

    function P.ClassLabel()
        local class = (Core.me and Core.me.class) or Core.PlayerClass()
        return class and Core.ClassName and Core.ClassName(class) or class or "?"
    end

    -- Gilt das aktive Profil für die Klasse dieses Charakters? (auch mit perChar; vorher ezBars/Profiles.lua)
    function P.ForClass()
        return scopes.class == true and P.Assigned("class") == P.Active()
    end

    -- Aktives Profil der Klasse zuordnen bzw. die Zuordnung lösen. Charaktere der Klasse ohne eigene Wahl bekommen
    -- es beim nächsten Einloggen. → true, wenn sich etwas geändert hat (mit Meldung).
    function P.SetForClass(on)
        if not scopes.class then return false end
        local active = P.Active()
        if on then
            if P.Assigned("class") == active or not P.Assign("class", active) then return false end
            Print(L.PROFILE_CLASS_ON:format(P.Label(active), P.ClassLabel()))
        else
            if P.Assigned("class") == nil then return false end
            P.Assign("class", nil)
            Print(L.PROFILE_CLASS_OFF:format(P.ClassLabel()))
        end
        Changed()
        return true
    end

    function P.FillMenu(root)
        local refresh = MenuResponse and MenuResponse.Refresh
        -- Tooltips der Einträge (Core.Menu.Tip, Layout.lua): dieselben Texte wie page:Profiles, damit Menü und
        -- Einstellungsseite gleich erklären (Hinweis aus ezGear, W5).
        local function Tip(entry, title, text)
            if Core.Menu and Core.Menu.Tip then Core.Menu.Tip(entry, title, text) end
            return entry
        end
        root:CreateTitle(L.PROFILE_TITLE)
        for _, name in ipairs(P.Names()) do
            root:CreateRadio(P.Label(name), function() return P.Active() == name end, function()
                if opts.perChar then P.Use(name) else P.Switch(name) end
                return refresh
            end, name)
        end
        root:CreateDivider()
        Tip(root:CreateButton(L.PROFILE_NEW, P.AskNew), L.PROFILE_NEW, L.OPT_PROFILE_NEW_TIP)
        local active = P.Active()
        local label = P.Label(active)
        if not opts.perChar then
            local forChar = L.PROFILE_FOR_CHAR:format(label)
            Tip(root:CreateCheckbox(forChar, function() return P.Assigned("char") == active end, function()
                P.Assign("char", P.Assigned("char") ~= active and active or nil)
            end), forChar, L.PROFILE_FOR_CHAR_TIP)
        end
        if scopes.class then
            local class = (Core.me and Core.me.class) or Core.PlayerClass()
            local forClass = L.PROFILE_FOR_CLASS:format(label, class and Core.ClassName(class) or "?")
            Tip(root:CreateCheckbox(forClass,
                function() return P.Assigned("class") == active end,
                function()
                    if opts.perChar then
                        P.SetForClass(not P.ForClass())
                    else
                        P.Assign("class", P.Assigned("class") ~= active and active or nil)
                    end
                end), forClass, L.OPT_profileClass_TIP)
        end
        if scopes.spec and P.SpecGroup() then
            Tip(root:CreateCheckbox(L.PROFILE_FOR_SPEC, function() return P.SpecMode() end, function()
                P.SetSpecMode(not P.SpecMode())
                return refresh
            end), L.PROFILE_FOR_SPEC, L.OPT_profileSpec_TIP)
        end
        local deletable = {}
        for _, name in ipairs(P.Names()) do
            if name ~= DEFAULT and DB()[F.profiles][name] ~= nil then deletable[#deletable + 1] = name end
        end
        if #deletable > 0 then
            local delete = Tip(root:CreateButton(L.PROFILE_DELETE), L.PROFILE_DELETE, L.OPT_PROFILE_DELETE_TIP)
            for _, name in ipairs(deletable) do
                delete:CreateButton(name, function() P.AskDelete(name) end)
            end
        end
        root:CreateDivider()
        Tip(root:CreateButton(L.PROFILE_EXPORT, P.ShowExport), L.PROFILE_EXPORT, L.OPT_PROFILE_EXPORT_TIP)
        Tip(root:CreateButton(L.PROFILE_IMPORT, P.ShowImport), L.PROFILE_IMPORT, L.OPT_PROFILE_IMPORT_TIP)
        if opts.hint then root:CreateTitle(opts.hint) end
        return root
    end

    ---------------------------------------------------------------------------
    -- Ausloggen sichert, Spezialisierung wechselt mit
    ---------------------------------------------------------------------------

    Core.RegisterEvent(owner, "PLAYER_LOGOUT", function()
        if P.loaded then P.Save() end
    end)

    -- Vergessener Charakter: seine Zuordnungen sind Felder des Gerüsts (Welle 23a, A14)
    function P.Forget(key)
        if Core.IsSecret(key) or type(key) ~= "string" or key == "" then return 0 end
        local db, gone = DB(), 0
        if db[F.specMode][key] ~= nil then db[F.specMode][key] = nil; gone = gone + 1 end
        local prefix = key .. "#"
        local drop = {}
        for assigned in pairs(db[F.assign]) do
            if assigned == key or (type(assigned) == "string" and assigned:sub(1, #prefix) == prefix) then
                drop[#drop + 1] = assigned
            end
        end
        for _, assigned in ipairs(drop) do db[F.assign][assigned] = nil end
        return gone + #drop
    end
    Core.Listen("CHAR_FORGOTTEN", function(key) P.Forget(key) end, owner)
    if scopes.spec then
        for _, event in ipairs({ "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_SPECIALIZATION_CHANGED" }) do
            Core.RegisterEvent(owner, event, function()
                if P.loaded and P.SpecMode() then P.Switch(P.Wanted()) end
            end)
        end
    end

    return P
end

--[[
    Core.NewSettingsProfiles(ns, opts) → Profiles: Profile, die genau die Einstellungen eines Moduls halten (ns.DEFAULTS,
    Arbeitsdaten ns.S). Vorher je eine gleiche Fassung in ezBuff und ezCombat (Durchsicht 24.11.2026, C9).
      opts = { owner = ADDON, kind = "ezBuff.profile", version = 1,
               skip = { schlüssel = true },      -- nie im Profil (je Charakter)
               adopt = function(settings) … end, -- Werte eines alten Textes umstellen → Tabelle (nie die übergebene ändern)
               maxText = 40,                     -- längere Texte sind kein Wert eines Auswahlfelds
               texts = L, print = ns.Print }
      Profiles.P (das Gerüst), .Valid(key, value), .Snapshot(), .Apply(data), .Clean(data), .Adopted(settings),
      .Active(), .Label(name), .Login() → true, wenn das Ausgangsprofil eben angelegt wurde, .StatusText(format)
    Geprüft wird mit Core.ValidSetting (Grenzen ns.LIMITS, Auswahl ns.CHOICES). Beim Wechsel übernimmt Core.ApplySetting
    jeden geänderten Wert (er meldet sich wie von Hand umgestellt); beim Einloggen (Login, vor allen übrigen Aufgaben des
    Moduls) still in ns.S – die Teile lesen die Werte erst danach beim Einrichten.
]]
function Core.NewSettingsProfiles(mns, opts)
    opts = opts or {}
    local Profiles = { DEFAULT = "Standard", KIND = opts.kind, VERSION = opts.version or 1, SKIP = opts.skip or {},
        MAX_TEXT = opts.maxText or 40 }

    -- Gültiger Wert für eine Einstellung im Profil oder nil (unbekannt, nicht im Profil, falscher Typ, gesperrt,
    -- außerhalb der Auswahl)
    function Profiles.Valid(key, value)
        if type(key) ~= "string" or Profiles.SKIP[key] then return nil end
        return Core.ValidSetting(mns, key, value, Profiles.MAX_TEXT)
    end

    -- Arbeitsdaten → Profil (Kopie)
    function Profiles.Snapshot()
        local settings = {}
        for key in pairs(mns.DEFAULTS) do
            local value = Profiles.Valid(key, mns.S and mns.S[key])
            if value ~= nil then settings[key] = value end
        end
        return { settings = settings }
    end

    function Profiles.Adopted(settings)
        if opts.adopt then settings = opts.adopt(settings) end
        return settings
    end

    local starting = false      -- Profiles.Login läuft: die Teile sind noch nicht eingerichtet
    local function Set(key, value)
        if starting then
            mns.S[key] = value
        else
            Core.ApplySetting(mns, key, value)
        end
    end

    -- Profil → Arbeitsdaten: jeder Wert geprüft, Fehlendes und Ungültiges aus dem Standard; opts.skip bleibt
    function Profiles.Apply(data)
        if not mns.S then return false end
        local src = type(data) == "table" and type(data.settings) == "table" and Profiles.Adopted(data.settings) or nil
        if type(src) ~= "table" then src = {} end
        for key, default in pairs(mns.DEFAULTS) do
            if not Profiles.SKIP[key] then
                local value = Profiles.Valid(key, src[key])
                if value == nil then value = default end
                if mns.S[key] ~= value then Set(key, value) end
            end
        end
        return true
    end

    -- Import: nur bekannte Einstellungen mit gültigem Wert (der Text kann von irgendwoher kommen). nil = unbrauchbar.
    function Profiles.Clean(data)
        if type(data) ~= "table" or type(data.settings) ~= "table" then return nil end
        local src = Profiles.Adopted(data.settings)
        if type(src) ~= "table" then return nil end
        local settings, any = {}, false
        for key in pairs(mns.DEFAULTS) do
            local value = Profiles.Valid(key, src[key])
            if value ~= nil then
                settings[key] = value
                any = true
            end
        end
        if not any then return nil end
        return { settings = settings }
    end

    local P = Core.NewProfiles({
        owner = opts.owner,
        db = function() return mns.db end,
        snapshot = function() return Profiles.Snapshot() end,
        apply = function(data) return Profiles.Apply(data) end,
        clean = function(data) return Profiles.Clean(data) end,
        kind = Profiles.KIND, version = Profiles.VERSION, wrap = "profile", default = Profiles.DEFAULT,
        perChar = true,                             -- die Auswahl gilt für diesen Charakter
        scopes = { class = true, spec = true },     -- dazu: ein Profil für die Klasse, auf Wunsch je Spezialisierung
        texts = opts.texts, print = opts.print,
    })
    Profiles.P = P

    function Profiles.Active() return P.Active() end
    function Profiles.Label(name) return P.Label(name) end

    -- Einloggen: Beim ersten Mal die bisherigen Einstellungen als „Standard“ sichern (Ausgangsprofil), dann das Profil
    -- dieses Charakters laden (Spezialisierung → Charakter → Klasse → Standard).
    function Profiles.Login()
        local db = mns.db
        local created = false
        if type(db) == "table" and (type(db.profiles) ~= "table" or db.profiles[P.Active()] == nil) then
            P.Save()
            created = true
        end
        starting = true
        local ok, err = pcall(P.Load, true)
        starting = false
        if not ok then error(err, 0) end
        return created
    end

    -- Zeile für den Status: „Profil: Standard – je Spezialisierung“ (format mit %s für den Namen)
    function Profiles.StatusText(format)
        local line = format:format(P.Label())
        if P.SpecMode() then line = line .. " – " .. Core.L.PROFILE_FOR_SPEC end
        return line
    end

    return Profiles
end
