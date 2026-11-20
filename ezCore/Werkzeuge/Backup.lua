local ADDON, ns = ...
local Core = ezCore
local L = Core.L

--[[
    Alles sichern und übernehmen (Vollprüfung V-040, Idee „Alles sichern“): die Einstellungen ALLER geladenen
    Module und ezCores eigene Schalter als EIN Text (Core.Serialize) – zum Aufheben, für einen zweiten Account oder
    einen Mitspieler. Zwei Knöpfe auf der Seite „ezCollection“ → „Erweitert“ (Leitlinie 3), dazu /ez sichern und
    /ez übernehmen.

    Was im Text steht: nur Einstellungen – je Modul die Schlüssel aus ns.DEFAULTS mit einem Wahrheitswert, einer
    Zahl oder einem Text als Standard, dazu Core.DEFAULTS (Komfort, Tooltip).
    Was NICHT im Text steht (persönliche Daten): Charaktere, Taschen, Post, Verlauf, Chat, Kontakte, Preise,
    Positionen, Listen und Tabellen in den Einstellungen, Texte mit einem bekannten Charakternamen, einem Link
    oder einer BattleTag. Ein Modul nimmt weitere Schlüssel mit ns.EXPORT_SKIP = { key = true } aus, ezCore seine
    eigenen mit Core.OwnExportSkip(gruppe, { key = true }) (Settings.lua) – so bleiben der Entwicklerschalter
    comfort.developer und der Testschalter comfort.editModeOpen draußen und werden auch nicht übernommen
    (Gegenprüfung zum Gesamtreview 18.11.2026, P6: sonst gingen sie über einen geteilten Text an, vorbei an
    /ez debug entwickler).
    Profile, Gruppen und Makros der Module behalten ihren eigenen Export (Core.NewProfiles, ezBag, ezMacro).
    Die Entdecker-Datenbank (ezWorldDB, DB.lua) ist Weltwissen und kein Teil des Textes; ihre zwei Schalter
    (Gruppe „discovery“: dataCollect, explorer) kommen wie alle eigenen Schalter mit. Ihr Weg nach außen ist der
    spätere Beitrag an das Projekt (DB-N1, Welle 10/11), nicht „Alles sichern“.
    Positionen (ezCoreDB.positions) kommen nur mit, wenn im Export-Dialog der Haken „Positionen mitnehmen“ gesetzt
    ist (EC-45; ab Werk aus, weil sie an der Auflösung hängen): Core.ExportAll({ positions = true }); beim Übernehmen
    zählen sie mit und gelten nach /reload (offene Teile ziehen über Mover nach).

      Core.Backup.Collect(opts)    → Daten { kind, v, core, modules = { ezBag = { key = wert } }, own = { comfort = { … } },
                                     positions = { [key] = { point, relPoint, x, y } } (nur mit opts.positions) },
                                     Zahlen { modules, values, skipped, positions }
      Core.ExportAll(opts)         → Text, Zahlen (nil und Grund, wenn Serialize scheitert)
      Core.ImportAll(text, opts)   → Ergebnis { ok, reason, modules, changes, unchanged, skipped, missing = { Modul … },
                                     missingCount }
                                     opts.dryRun = true: nur prüfen und zählen, nichts ändern
                                     reason: "empty" | "format" | "kind" | "version" | "combat" | "size" (zu lang
                                     oder zu viele Einträge, Core.Deserialize)
      Core.ValidSetting(mns, schlüssel, wert, maxText) → gültiger Wert oder nil (Gesamtreview 18.11.2026, T6-2): die
                                     Prüfung, die jeder eingefügte Wert eines Moduls besteht (siehe unten)
      Core.Backup.ShowExport(), Core.Backup.ShowImport()   die zwei Dialoge (Core.TextDialog)
      Core.ApplySetting(mns, schlüssel, wert) → "setting" | "set" | "raw"   einen Wert eines Moduls setzen wie ein Klick
                                     (Setting-Objekt, sonst mns.SetSetting, sonst mns.S; Welle 23a, auch für Profile)
    Gemeinsame Schalter (Core.ShareSettings, Kern/Settings.lua) stehen in neuen Texten unter ezCores eigenen Werten;
    ältere Texte führen sie noch unter dem Modul (z. B. ezMerchant repairAuto). Solche Werte gehen an ezCores Schalter
    (Gegenprüfung 19.11.2026; vorher wurden sie still übergangen): je Schalter zählen zuerst die Werte, die vom alten
    Standard des Moduls abweichen (Core.SharedChoice), unter ihnen gewinnt ein „an“; sonst die gespeicherten Standards.
    Ein Wert unter ezCores eigenen Werten im selben Text geht vor.
    Übernommen wird nur, was das Modul kennt (Schlüssel in ns.DEFAULTS), im Typ passt und Core.ValidSetting besteht
    (Zahlen endlich und in den Grenzen des Reglers, Texte kurz und aus der Auswahl des Felds; T6-2, vorher prüfte der
    Sammel-Import nur den Typ und umging so die Grenzen der Profil-Importe); ein Modul, das nicht geladen ist, wird
    genannt (Name bereinigt, höchstens Backup.MAX_MISSING) und übersprungen. ezCores eigene Werte prüft dieselbe
    Funktion mit den Grenzen und der Auswahl aus Core.OwnRules (Kern/Settings.lua). Positionen nur mit gültigem
    Ankerpunkt und x/y im Bildschirm (Core.CleanPosition, T6-3), Schlüssel kurz und ohne Codes (Backup.PositionKey),
    höchstens Backup.MAX_NEW_POSITIONS noch nicht gespeicherte. Gesetzt wird über das Setting-Objekt (offene Kästchen zeigen den
    neuen Wert) bzw. ns.SetSetting – die Module reagieren wie auf einen Klick. Nicht im Kampf.
]]

local Backup = {}
Core.Backup = Backup
Backup.KIND = "ezCollection.settings"
Backup.VERSION = 1
Backup.MAX_TEXT = 200          -- längere Texte sind keine Einstellung, sondern Inhalt
Backup.MAX_MISSING = 10        -- so viele nicht geladene Module nennt das Ergebnis mit Namen, den Rest als Zahl

Backup.MAX_KEY = 100           -- Länge eines Positions-Schlüssels (Mover-Namen wie „ezBag.bag“ sind kurz)
Backup.MAX_NEW_POSITIONS = 200 -- so viele noch nicht gespeicherte Positionen übernimmt ein Text höchstens

local SIMPLE = { boolean = true, number = true, string = true }

-- Schlüssel einer Position aus einem Text: Text bis Backup.MAX_KEY Bytes, ohne Steuerzeichen und „|“, nicht geheim.
function Backup.PositionKey(key)
    return type(key) == "string" and not Core.IsSecret(key) and key ~= "" and #key <= Backup.MAX_KEY
        and not key:find("[%c|]")
end

-- Namen, die nicht in den Export dürfen: alle bekannten Charaktere (voller Name und Vorname, ab 3 Zeichen).
local function PersonalNames()
    local names = {}
    local function Add(name)
        if type(name) ~= "string" then return end
        name = Core.Trim(name):lower()
        if #name >= 3 then names[name] = true end
    end
    for key, c in pairs(Core.Chars and Core.Chars() or {}) do
        local name = type(c) == "table" and c.name or (type(key) == "string" and key:match("^(.-)%-")) or nil
        Add(name)
        if type(name) == "string" then Add(name:match("^([^%s]+)")) end
    end
    return names
end

-- Sieht ein Text nach persönlichen Daten aus? (Charaktername, Link, BattleTag, zu lang)
function Backup.IsPersonal(value, names)
    if type(value) ~= "string" then return false end
    if Core.IsSecret(value) then return true end
    if #value > Backup.MAX_TEXT then return true end
    if value:find("|H", 1, true) or value:find("[^#%s]#%d%d%d%d") then return true end
    local lower = value:lower()
    for name in pairs(names or PersonalNames()) do
        if lower:find(name, 1, true) then return true end
    end
    return false
end

local function CollectTable(values, defaults, skip, names, stats)
    local out
    for key, default in pairs(defaults) do
        local value = values[key]
        if type(key) == "string" and SIMPLE[type(default)] and type(value) == type(default)
            and not (skip and skip[key]) and not Core.IsSecret(value) and not Backup.IsPersonal(value, names) then
            out = out or {}
            out[key] = value
            stats.values = stats.values + 1
        elseif value ~= nil then
            stats.skipped = stats.skipped + 1
        end
    end
    return out
end

-- Gültige Lage oder nil: Ankerpunkt aus den neun von SetPoint, x/y endlich und im Bildschirm (T6-3; die eine
-- Fassung ist Core.CleanPosition in Widgets.lua, die auch Core.ApplyPosition nutzt).
local function CleanPosition(pos)
    return Core.CleanPosition(pos)
end
Backup.CleanPosition = CleanPosition

local function InChoices(list, value)
    for _, entry in ipairs(list) do
        local known = entry
        if type(entry) == "table" then known = entry[1] end
        if known == value then return true end
    end
    return false
end

-- Gültiger Wert einer Einstellung aus einem eingefügten Text oder nil (T6-2; dieselbe Strenge wie die Profil-Importe
-- von ezBuff, ezCombat und ezBars, aber für jedes Modul):
--   - Schlüssel aus mns.DEFAULTS mit einfachem Standard (Wahrheitswert, Zahl, Text), Wert vom selben Typ, nicht geheim
--   - Zahlen endlich; Grenzen aus mns.LIMITS[key] = { min, max } bzw. den Grenzen des Reglers auf der Einstellungsseite
--     (mns.settingLimits, gemerkt von page:Slider) – der Wert wird hineingeklemmt
--   - Texte höchstens maxText Bytes (Standard Backup.MAX_TEXT); hat das Feld eine Auswahl (mns.CHOICES[key] bzw. die
--     Einträge von page:Dropdown in mns.settingChoices), muss er darin stehen
--   - zuletzt mns.ValidSetting(key, wert), wenn das Modul eine hat: → Wert (auch geklemmt) oder nil (ablehnen)
function Core.ValidSetting(mns, key, value, maxText)
    if type(mns) ~= "table" or type(mns.DEFAULTS) ~= "table" or type(key) ~= "string" then return nil end
    local default = mns.DEFAULTS[key]
    if not SIMPLE[type(default)] or type(value) ~= type(default) or Core.IsSecret(value) then return nil end
    if type(value) == "number" then
        if not Core.FiniteNumber(value) then return nil end
        local limit = type(mns.LIMITS) == "table" and mns.LIMITS[key]
            or type(mns.settingLimits) == "table" and mns.settingLimits[key] or nil
        if type(limit) == "table" and type(limit[1]) == "number" and type(limit[2]) == "number" then
            value = math.max(limit[1], math.min(limit[2], value))
        end
    elseif type(value) == "string" then
        if #value > (type(maxText) == "number" and maxText or Backup.MAX_TEXT) then return nil end
        local choices = type(mns.CHOICES) == "table" and mns.CHOICES[key]
            or type(mns.settingChoices) == "table" and mns.settingChoices[key] or nil
        if type(choices) == "table" and #choices > 0 and not InChoices(choices, value) then return nil end
    end
    if type(mns.ValidSetting) == "function" then
        local ok, checked = pcall(mns.ValidSetting, key, value)
        if not ok or checked == nil or type(checked) ~= type(default) then return nil end
        value = checked
    end
    return value
end

function Backup.Collect(opts)
    local names = PersonalNames()
    local stats = { modules = 0, values = 0, skipped = 0, positions = 0 }
    local data = { kind = Backup.KIND, v = Backup.VERSION, core = Core.Version and Core.Version(ADDON) or "?", modules = {}, own = {} }
    for _, name in ipairs(Core.moduleOrder) do
        local mod = Core.Module(name)
        local mns = mod and mod.ns
        if name ~= ADDON and type(mns) == "table" and type(mns.S) == "table" and type(mns.DEFAULTS) == "table" then
            local values = CollectTable(mns.S, mns.DEFAULTS, type(mns.EXPORT_SKIP) == "table" and mns.EXPORT_SKIP or nil, names, stats)
            if values then
                data.modules[name] = values
                stats.modules = stats.modules + 1
            end
        end
    end
    for group, defaults in pairs(Core.DEFAULTS or {}) do
        local tbl = Core.OwnSettings(group)
        local values = tbl and CollectTable(tbl, defaults, Core.OWN_EXPORT_SKIP and Core.OWN_EXPORT_SKIP[group], names, stats)
        if values then data.own[group] = values end
    end
    if type(opts) == "table" and opts.positions then
        local positions = Core.Positions and Core.Positions(false)
        for key, pos in pairs(type(positions) == "table" and positions or {}) do
            local clean = type(key) == "string" and CleanPosition(pos)
            if clean then
                data.positions = data.positions or {}
                data.positions[key] = clean
                stats.positions = stats.positions + 1
            end
        end
    end
    return data, stats
end

function Core.ExportAll(opts)
    local data, stats = Backup.Collect(opts)
    local text, why = Core.Serialize(data)
    if not text then return nil, why end
    return text, stats
end

-- Einen Wert eines Moduls setzen (Welle 23a, A15; vorher nur hier als ApplyModuleValue, gleich gebaut in ezCombat
-- und ezBars Profiles.lua): zuerst über das Setting-Objekt (Blizzards Anzeige zieht nach; gilt nur, wenn der Wert
-- danach wirklich in mns.S steht), sonst mns.SetSetting (Rückrufe des Moduls), sonst direkt in mns.S.
-- → "setting" | "set" | "raw" – welcher Weg es war; nil ohne Modul-Tabelle.
function Core.ApplySetting(mns, key, value)
    if type(mns) ~= "table" or key == nil then return nil end
    local setting = type(mns.settingObjects) == "table" and mns.settingObjects[key]
    if setting and setting.SetValue and pcall(setting.SetValue, setting, value)
        and type(mns.S) == "table" and mns.S[key] == value then
        return "setting"
    end
    if type(mns.SetSetting) == "function" then
        mns.SetSetting(key, value)
        return "set"
    end
    if type(mns.S) ~= "table" then mns.S = {} end
    mns.S[key] = value
    return "raw"
end
local ApplyModuleValue = Core.ApplySetting

-- eigene Schalter setzen wie ein Klick: Core.ApplyOwnSetting (Settings.lua; vorher hier als ApplyOwnValue)
local function ApplyOwnValue(group, key, value)
    return Core.ApplyOwnSetting(group, key, value)
end

function Core.ImportAll(text, opts)
    opts = opts or {}
    local result = { ok = false, modules = 0, changes = 0, unchanged = 0, skipped = 0, missing = {}, missingCount = 0 }
    if type(text) ~= "string" or Core.Trim(text) == "" then
        result.reason = "empty"
        return result
    end
    local data, why = Core.Deserialize(text)
    if type(data) ~= "table" then
        result.reason, result.detail = why == "size" and "size" or "format", why
        return result
    end
    if data.kind ~= Backup.KIND or type(data.modules) ~= "table" then
        result.reason = "kind"
        return result
    end
    if type(data.v) ~= "number" or data.v > Backup.VERSION then
        result.reason = "version"
        return result
    end
    if not opts.dryRun and Core.InCombat() then
        result.reason = "combat"
        return result
    end
    local names = {}
    for name in pairs(data.modules) do names[#names + 1] = name end
    table.sort(names, function(a, b) return tostring(a) < tostring(b) end)
    local shared, sharedOrder = {}, {}   -- gemeinsame Schalter aus älteren Texten: [gruppe.key] = Stimmen
    for _, name in ipairs(names) do
        local values = data.modules[name]
        local mod = type(name) == "string" and Core.Module(name)
        local mns = mod and mod.ns
        if type(values) ~= "table" then
            result.skipped = result.skipped + 1
        elseif not (type(mns) == "table" and type(mns.S) == "table" and type(mns.DEFAULTS) == "table") then
            -- Name aus dem Text: bereinigt (keine „|“-Codes, kein Umbruch, kurz; T6-5), höchstens MAX_MISSING mit Namen
            result.missingCount = result.missingCount + 1
            local shown = #result.missing < Backup.MAX_MISSING and Core.CleanImportName(tostring(name))
            if shown then result.missing[#result.missing + 1] = shown end
        else
            result.modules = result.modules + 1
            -- Einmal-Umstellungen des Moduls auch für ältere Texte (code-reviewer 20.11.2026: sonst kamen z. B. in
            -- ezChat die gespeicherten Lagen ohne den alten Hauptschalter zurück): ns.ImportLegacy(kopie) → Werte
            if type(mns.ImportLegacy) == "function" then
                local copy = {}
                for k, v in pairs(values) do copy[k] = v end
                local ok, adopted = pcall(mns.ImportLegacy, copy)
                if ok and type(adopted) == "table" then
                    values = adopted
                elseif not ok then
                    Core.Error(name, adopted, "ImportAll ImportLegacy")
                end
            end
            local skip = type(mns.EXPORT_SKIP) == "table" and mns.EXPORT_SKIP or nil
            local keys = {}
            for key in pairs(values) do keys[#keys + 1] = key end
            table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
            for _, key in ipairs(keys) do
                local value, voted
                local target = type(mns.SHARED) == "table" and type(key) == "string" and mns.SHARED[key] or nil
                if type(target) == "table" and type(values[key]) == "boolean" and not (skip and skip[key]) then
                    voted = true
                    local id = tostring(target[1]) .. "." .. tostring(target[2])
                    local votes = shared[id]
                    if not votes then
                        votes = { group = target[1], key = target[2] }
                        shared[id] = votes
                        sharedOrder[#sharedOrder + 1] = id
                    end
                    if Core.SharedChoice(target, values[key]) then
                        votes.choice = votes.choice or values[key]
                    else
                        votes.default = votes.default or values[key]
                    end
                elseif not (skip and skip[key]) then value = Core.ValidSetting(mns, key, values[key]) end
                if voted then
                    -- oben gezählt; gesetzt wird nach allen Modulen
                elseif value == nil then
                    result.skipped = result.skipped + 1
                elseif mns.S[key] == value then
                    result.unchanged = result.unchanged + 1
                else
                    result.changes = result.changes + 1
                    if not opts.dryRun then
                        local ok, err = pcall(ApplyModuleValue, mns, key, value)
                        if not ok then Core.Error(name, err, "ImportAll " .. key) end
                    end
                end
            end
        end
    end
    -- gemeinsame Schalter aus älteren Texten (s. Kopf): eine abweichende Wahl vor dem gespeicherten Standard
    local ownTaken = {}   -- [group][key] = true: oben schon gesetzt, die Schleife über data.own lässt ihn aus
    for _, id in ipairs(sharedOrder) do
        local votes = shared[id]
        local want = votes.choice
        if want == nil then want = votes.default end
        local ownGroup = type(data.own) == "table" and data.own[votes.group] or nil
        local own
        if type(ownGroup) == "table" then own = ownGroup[votes.key] end
        -- Ältere Texte führen ezCores eigenen Wert immer mit (Backup.Collect nimmt alle Gruppen aus Core.DEFAULTS),
        -- meist als gespeicherten Standard. Eine bewusste Wahl des Moduls zählt dann wie beim Laden
        -- (Core.AdoptModuleShared): ein „an“ gewinnt (code-reviewer 20.11.2026: sonst verlor eine alte Sicherung mit
        -- ezBag auctionWorth = true die Münze, weil priceOpts.worthBag = false im selben Text vorging).
        if own ~= nil and type(own) == "boolean" and type(votes.choice) == "boolean" then
            want = own or votes.choice
            if want ~= own then
                ownTaken[votes.group] = ownTaken[votes.group] or {}
                ownTaken[votes.group][votes.key] = true
                own = nil
            end
        end
        if own ~= nil or type(Core.OwnSettings(votes.group)) ~= "table" then
            result.skipped = result.skipped + 1   -- ezCores eigener Wert im Text geht vor bzw. Gruppe unbekannt
        elseif Core.SharedOn(votes.group, votes.key) == want then
            result.unchanged = result.unchanged + 1
        else
            result.changes = result.changes + 1
            if not opts.dryRun then
                local ok, err = pcall(Core.SetShared, votes.group, votes.key, want)
                if not ok then Core.Error(ADDON, err, "ImportAll " .. id) end
            end
        end
    end
    for group, values in pairs(type(data.own) == "table" and data.own or {}) do
        local defaults = type(group) == "string" and Core.DEFAULTS[group]
        local tbl = defaults and Core.OwnSettings(group)
        local skip = type(group) == "string" and Core.OWN_EXPORT_SKIP and Core.OWN_EXPORT_SKIP[group]
        if tbl and type(values) == "table" then
            for key, raw in pairs(values) do
                -- dieselbe Prüfung wie bei den Modulen (T6-2): Typ, endliche Zahl, kurzer Text, dazu Grenzen und
                -- Auswahl aus Core.OwnRules (Gegenprüfung: vorher kam z. B. gatherCare.mergeYards = 1000000 durch)
                local value = Core.ValidSetting({ DEFAULTS = defaults, LIMITS = Core.OWN_LIMITS and Core.OWN_LIMITS[group],
                    CHOICES = Core.OWN_CHOICES and Core.OWN_CHOICES[group] }, key, raw)
                -- Entwickler- und Testschalter werden nie eingelesen (Gesamtreview 18.11.2026, T2-7)
                if skip and skip[key] then value = nil end
                if ownTaken[group] and ownTaken[group][key] then value = nil end
                if value == nil then
                    result.skipped = result.skipped + 1
                elseif tbl[key] == value then
                    result.unchanged = result.unchanged + 1
                else
                    result.changes = result.changes + 1
                    if not opts.dryRun then
                        local ok, err = pcall(ApplyOwnValue, group, key, value)
                        if not ok then Core.Error(ADDON, err, "ImportAll " .. tostring(key)) end
                    end
                end
            end
        elseif type(values) == "table" then
            result.skipped = result.skipped + 1
        end
    end
    -- Positionen (EC-45): nur gültige Lagen; gesetzt wird in ezCoreDB.positions, die Teile ziehen nach /reload nach
    if type(data.positions) == "table" then
        local stored = not opts.dryRun and Core.Positions and Core.Positions(true) or (Core.Positions and Core.Positions(false)) or {}
        result.positions = 0
        local fresh, keys = 0, {}
        for key in pairs(data.positions) do keys[#keys + 1] = key end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)   -- feste Reihenfolge für die Grenze
        for _, key in ipairs(keys) do
            local pos = data.positions[key]
            local clean = Backup.PositionKey(key) and CleanPosition(pos)
            -- höchstens Backup.MAX_NEW_POSITIONS Schlüssel, die es hier noch nicht gibt (Gegenprüfung: vorher legte ein
            -- Text beliebig viele dauerhafte Einträge in ezCoreDB.positions an)
            if clean and not (type(stored) == "table" and stored[key] ~= nil) then
                fresh = fresh + 1
                if fresh > Backup.MAX_NEW_POSITIONS then clean = nil end
            end
            if not clean then
                result.skipped = result.skipped + 1
            else
                local old = type(stored) == "table" and CleanPosition(stored[key])
                if old and old.point == clean.point and old.relPoint == clean.relPoint and old.x == clean.x and old.y == clean.y then
                    result.unchanged = result.unchanged + 1
                else
                    result.changes = result.changes + 1
                    result.positions = result.positions + 1
                    if not opts.dryRun and type(stored) == "table" then stored[key] = clean end
                end
            end
        end
    end
    result.ok = true
    return result
end

---------------------------------------------------------------------------
-- Dialoge
---------------------------------------------------------------------------

local REASON_TEXT = { empty = "BACKUP_ERR_EMPTY", format = "BACKUP_ERR_FORMAT", kind = "BACKUP_ERR_KIND",
    version = "BACKUP_ERR_VERSION", size = "BACKUP_ERR_SIZE" }

function Backup.ReasonText(reason)
    -- im Kampf ezCores Satz zur Kampfsperre (T18-1; vorher eigener Text BACKUP_ERR_COMBAT)
    if reason == "combat" then return Core.CombatText(L.BACKUP_WHAT) end
    return L[REASON_TEXT[reason] or "BACKUP_ERR_FORMAT"]
end

function Backup.ResultText(result)
    local text = L.BACKUP_IMPORT_DONE:format(result.changes, result.modules, result.unchanged)
    if result.skipped > 0 then text = text .. " " .. L.BACKUP_IMPORT_SKIPPED:format(result.skipped) end
    local missing = math.max(result.missingCount or 0, #result.missing)
    if missing > 0 then
        local names = table.concat(result.missing, ", ")
        if missing > #result.missing then names = (names ~= "" and names .. " " or "") .. Core.More(missing - #result.missing) end
        text = text .. " " .. L.BACKUP_IMPORT_MISSING:format(names)
    end
    if (result.positions or 0) > 0 then text = text .. " " .. L.BACKUP_IMPORT_POSITIONS:format(result.positions) end
    return text
end

Backup.withPositions = false   -- Haken „Positionen mitnehmen“ im Export-Dialog (je Sitzung gemerkt, ab Werk aus)

local function ExportHint(stats)
    local hint = L.BACKUP_EXPORT_HINT:format(stats.values, stats.modules)
    if (stats.positions or 0) > 0 then hint = hint .. " " .. L.BACKUP_EXPORT_POSITIONS:format(stats.positions) end
    return hint
end

function Backup.ShowExport()
    local text, stats = Core.ExportAll({ positions = Backup.withPositions })
    if not text then
        ns.Print(L.BACKUP_EXPORT_FAILED:format(tostring(stats)))
        return nil
    end
    local dialog
    dialog = Core.TextDialog({ anchor = rawget(_G, "SettingsPanel"), title = L.BACKUP_EXPORT_TITLE, hint = ExportHint(stats),
        text = text, readOnly = true, select = true, maxLetters = 0, owner = ADDON,
        option = { text = L.BACKUP_POSITIONS, tip = L.BACKUP_POSITIONS_TIP, checked = Backup.withPositions,
            onChange = function(on)
                Backup.withPositions = on
                local again, counts = Core.ExportAll({ positions = on })
                if again and dialog then
                    dialog:SetText(again)
                    dialog.hint:SetText(ExportHint(counts))
                end
            end } })
    return dialog
end

function Backup.ShowImport()
    return Core.TextDialog({ anchor = rawget(_G, "SettingsPanel"), title = L.BACKUP_IMPORT_TITLE, hint = L.BACKUP_IMPORT_HINT, text = "", maxLetters = 0, owner = ADDON,
        accept = L.BACKUP_IMPORT_ACCEPT,
        onAccept = function(text)
            local check = Core.ImportAll(text, { dryRun = true })
            if not check.ok then
                ns.Print(Backup.ReasonText(check.reason))
                return false   -- Dialog bleibt offen
            end
            if check.changes == 0 then
                ns.Print(Backup.ResultText(check))
                return true
            end
            Core.Confirm(L.BACKUP_IMPORT_ASK:format(check.changes, check.modules), function()
                local result = Core.ImportAll(text)
                ns.Print(result.ok and Backup.ResultText(result) or Backup.ReasonText(result.reason))
            end)
            return true
        end })
end
