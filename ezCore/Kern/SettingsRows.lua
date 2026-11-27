local _, ns = ...
local Core = ezCore

--[[
    Zeilen auf Blizzards Einstellungsseiten, ohne Blizzards Liste und Suche zu verunreinigen (25.11.2026; Meldungen „AddOn
    'ezCore' hat versucht die geschützte Funktion 'IsUserOAuthed()' aufzurufen“ beim Suchen in Blizzards Einstellungen;
    Entscheidung des Nutzers „Ja, umbauen (Empfohlen)“; docs/blizzard-regeln.md, T18 und Nachtrag vom 25.11.2026).

    Laut Blizzards Forever-Quelle entsteht jede Zeile eines Addons geschützt (Blizzard_SettingsInbound.lua). Drei Aufrufe aus
    Addon-Code schreiben danach Felder in die Zeile, die Blizzards Liste (SettingsListMixin:Display, RepairDisplay) und Suche
    (FindInitializersMatchingSearchText, OnSearchTextChanged) ungeschützt lesen – ab da läuft der Rest verunreinigt:
      AddSearchTags          searchTags          (auch CreateSettingsButtonInitializer mit addSearchTags = true)
      AddShownPredicate      shownPredicates
      SetParentInitializer   parentInitializer
    Kein Modul ruft einen davon auf (tools/lint.lua, Regel 16). Statt dessen:

    Rows.Button(kategorie, beschriftung, knopftext, onClick, tooltip, tags) → Zeile. Die Suchmarke setzt Blizzard selbst,
      geschützt, beim Anlegen einer Zeile mit Einstellung (Settings.CreateSettingInitializer nimmt deren Namen). Dafür gibt es
      je Text einer Suchmarke eine Träger-Einstellung (Name = dieser Text, Variable ezCore_rows_tag<n>); danach ist die Zeile
      wieder eine reine Knopfzeile. tags = { text … } oder nil (nicht über die Suche zu finden). Kennt der Client den Träger
      nicht: ohne Marke.
    Rows.TagCarrierCount() → wie viele Träger für Suchmarken angemeldet sind (Auskunft für Prüfungen)

    Jeder Träger heißt mit festem Text, nie mit einer Funktion (Spieltest vom 26.11.2026, docs/blizzard-regeln.md, T23):
    Blizzard prüft den Namen beim geschützten Anlegen (Blizzard_Setting.lua: ProxySettingMixin:Init →
    ErrorIfInvalidSettingArguments → GetNameType → GetOrCallName) und ruft eine Funktion dort ohne securecallfunction auf.
    Ab da lief Blizzards geschützter Weg „tainted by ezCore“, auch für Blizzards eigene Einstellungen, die danach
    entstanden – und jeder Klick auf einen Aktionsknopf liest sie (Settings.GetValue("lockActionBars") →
    SettingsPanel:GetSetting), UseAction war blockiert.
    Rows.Available() → gibt es Blizzards Knopfzeilen auf diesem Client?
    Rows.ShowWhen(page, zeile, fn, wo) – Zeile nur auf der Seite, solange fn() wahr ist: Sie wird in die Zeilenliste der
      eigenen Seite ein- und ausgereiht (Leitlinie 5, Ausnahme 6; Blizzard liest die Liste nur geschützt über
      EnumerateInitializers bzw. EnumerateTaintedKeysTable). Aus der gerade gezeigten Seite nimmt ezCore nie eine Zeile
      heraus (Blizzards RepairDisplay vergliche sie sonst mit nichts) – dort wird sie grau, bis die Seite das nächste Mal
      aufgeht.
    Rows.Refresh(auchGrau) – Bedingungen neu auswerten (Blizzards Seitenwechsel und Wertwechsel tun das von selbst);
      auchGrau: bei offenem Fenster auch das Grau der gezeigten Zeilen. Rows.changes zählt jede geänderte Zeilenliste.
    Rows.IsShown(zeile) → gilt ihre Bedingung? (ohne Bedingung: true)
    Rows.Child(page, zeile, oberzeile, setting) – eingerückt und klein wie Blizzards Unterschalter (nur, wenn die Oberzeile
      auf derselben Seite steht), neu ausgewertet, sobald sich der Wert von setting ändert. Findet die Suche einen
      Unterschalter, zeigt sie die Oberzeile nicht mehr mit an (Blizzard liest dafür parentInitializer).
    Rows.Indent(page, zeile, oberzeile) → eingerückt? (nur Einrücken und kleine Schrift, etwa ezMaps Baum)
    Rows.IsChild(zeile), Rows.ParentOf(zeile) → kleine Schrift? / Oberzeile aus Rows.Child (Auskunft für Prüfungen;
      Blizzard kennt sie nicht)
    Rows.ApplyFont(rahmen, zeile) – nach Blizzards Init: kleine Schrift für Unterschalter (Core.WrapSettingsLabel)
]]

local Rows = {}
Core.SettingsRows = Rows

Rows.CARRIER = "ezCore_rows"                -- Variable des Trägers für „neu auswerten“ (nie gespeichert)
Rows.TAG_PREFIX = "ezCore_rows_tag"         -- Variablen der Träger für Suchmarken: …1, …2 (nie gespeichert)
Rows.BUTTON_TEMPLATE = "SettingButtonControlTemplate"   -- wie CreateSettingsButtonInitializer
Rows.changes = 0                            -- wie oft ezCore eine Zeilenliste geändert hat (Core.CollectOwnSettingsRows)

---------------------------------------------------------------------------
-- Träger-Einstellungen (Name immer ein fester Text, Kopf oben)
---------------------------------------------------------------------------

local carrier                               -- Träger für „neu auswerten“ (false: geht auf diesem Client nicht)
local tagCarriers, tagCount = {}, 0         -- [Text der Suchmarke] = Träger; Zahl der angemeldeten
local tagsFailed                            -- true: der Client nahm keinen Träger an (dann Knopfzeilen ohne Marke)

local function CanRegister(category)
    return type(category) == "table" and type(Settings) == "table" and Settings.RegisterProxySetting ~= nil
        and Settings.CreateSettingInitializer ~= nil
end

-- → Träger oder false (der Client lehnte ab); name ist immer ein Text. Blizzards Weg liefert das Ergebnis über den Rahmen
-- (GetSecureAttributeResults) – nur ein Objekt mit genau dieser Variable gilt als angelegt.
local function Register(category, variable, name)
    if type(name) ~= "string" then return false end
    local ok, setting = pcall(Settings.RegisterProxySetting, category, variable, Settings.VarType.Boolean, name, false,
        function() return false end, function() end)
    if not (ok and type(setting) == "table" and type(setting.GetVariable) == "function") then return false end
    local okVar, var = pcall(setting.GetVariable, setting)
    return okVar and var == variable and setting or false
end

local function Carrier(category)
    if carrier ~= nil then return carrier or nil end
    if not CanRegister(category) then return nil end
    -- Name: der Titel der Sammlung (Core.TITLE, „ezCollection“); Variable Rows.CARRIER
    carrier = Register(category, Rows.CARRIER, type(Core.TITLE) == "string" and Core.TITLE or "ezCollection")
    return carrier or nil
end

local function TagCarrier(category, text)
    if tagsFailed then return nil end
    if tagCarriers[text] then return tagCarriers[text] end
    if not CanRegister(category) then return nil end
    tagCount = tagCount + 1
    local setting = Register(category, Rows.TAG_PREFIX .. tagCount, text)
    if not setting then
        tagsFailed = true                   -- nur einmal versuchen
        return nil
    end
    tagCarriers[text] = setting
    return setting
end

function Rows.TagCarrierCount()
    local n = 0
    for _ in pairs(tagCarriers) do n = n + 1 end
    return n
end

---------------------------------------------------------------------------
-- Knopfzeile mit Suchmarke
---------------------------------------------------------------------------

local function Joined(tags)
    local out = {}
    for _, tag in ipairs(type(tags) == "table" and tags or {}) do
        if type(tag) == "string" and tag:find("%S") then out[#out + 1] = tag end
    end
    return #out > 0 and table.concat(out, " ") or nil
end

-- Gibt es Knopfzeilen auf diesem Client?
function Rows.Available()
    return type(rawget(_G, "CreateSettingsButtonInitializer")) == "function"
end

function Rows.Button(category, label, buttonText, onClick, tooltip, tags)
    local text = Joined(tags)
    local setting = text and TagCarrier(category, text)
    if not setting then
        -- ohne Suchmarke, oder der Client kennt den Träger nicht: Blizzards Knopfzeile ohne Marke. Eine Marke aus
        -- Addon-Code verunreinigte Blizzards Suche wieder (Review 26.11.2026) – dann findet die Suche den Knopf eben nicht.
        return CreateSettingsButtonInitializer(label, buttonText, onClick, tooltip, false)
    end
    local data = { name = label, buttonText = buttonText, buttonClick = onClick, tooltip = tooltip, setting = setting }
    local ok, row = pcall(Settings.CreateSettingInitializer, Rows.BUTTON_TEMPLATE, data)
    data.setting = nil                      -- ab hier eine Knopfzeile wie jede andere: Beschriftung aus data.name
    if not ok then error(row, 0) end
    return row
end

---------------------------------------------------------------------------
-- Zeilen mit Bedingung
---------------------------------------------------------------------------

local conditions = setmetatable({}, { __mode = "k" })   -- [Zeile] = fn() → bool
local lists = setmetatable({}, { __mode = "k" })        -- [Layout] = alle Zeilen der Seite in ihrer Reihenfolge

function Rows.IsShown(row)
    local condition = conditions[row]
    return condition == nil or condition() == true
end

-- Zeilenliste eines Layouts (Blizzards Liste der eigenen Seite) oder nil
local function ListOf(layout)
    local get = Core.Peek(layout, "GetInitializers")
    if type(get) ~= "function" then return nil end
    local ok, list = pcall(get, layout)
    return ok and type(list) == "table" and list or nil
end

-- → geändert? current: diese Seite zeigt Blizzard gerade (dann nur einreihen, nie herausnehmen)
local function SyncLayout(layout, all, current)
    local list = ListOf(layout)
    if not list then return false end
    local known, present = {}, {}
    for _, row in ipairs(all) do known[row] = true end
    for _, row in ipairs(list) do
        present[row] = true
        if not known[row] then all[#all + 1] = row end
    end
    local want = {}
    for _, row in ipairs(all) do
        if Rows.IsShown(row) or (current and present[row]) then want[#want + 1] = row end
    end
    local same = #want == #list
    for i = 1, same and #want or 0 do same = same and want[i] == list[i] end
    if same then return false end
    for i = 1, math.max(#want, #list) do list[i] = want[i] end
    Rows.changes = Rows.changes + 1
    return true
end

local hooked
local function Hook()
    local panel = rawget(_G, "SettingsPanel")
    if hooked or type(panel) ~= "table" or not hooksecurefunc then return end
    hooked = true
    -- nach jedem Seitenwechsel (auch beim Öffnen und in der Suche) und nach jedem geänderten Wert
    for _, name in ipairs({ "DisplayLayout", "RepairDisplay" }) do
        if type(Core.Peek(panel, name)) == "function" then hooksecurefunc(panel, name, function() Rows.Refresh() end) end
    end
end

local function PanelShown(panel)
    local shown = Core.Peek(panel, "IsShown")
    if type(shown) ~= "function" then return false end
    local ok, value = pcall(shown, panel)
    return ok and value == true
end

local function RefreshNow(grey)
    local panel = rawget(_G, "SettingsPanel")
    local get = Core.Peek(panel, "GetCurrentLayout")
    local ok, current = false, nil
    if type(get) == "function" then ok, current = pcall(get, panel) end
    current = ok and current or nil
    local repair = false
    for layout, all in pairs(lists) do
        local changed = SyncLayout(layout, all, layout == current)
        if changed and layout == current then repair = true end
    end
    -- Nachziehen über Blizzards geschützten Weg (SettingsInbound), nie über die Liste selbst
    local inbound = rawget(_G, "SettingsInbound")
    if repair and type(inbound) == "table" and type(inbound.RepairDisplay) == "function" then pcall(inbound.RepairDisplay) end
    -- Grau neu auswerten nur bei offenem Fenster (beim nächsten Anzeigen wertet Blizzard jede Zeile ohnehin neu aus)
    if grey and carrier and PanelShown(panel) and type(carrier.NotifyUpdate) == "function" then
        pcall(carrier.NotifyUpdate, carrier)
    end
    return repair
end

local busy
function Rows.Refresh(grey)
    if busy then return false end
    Hook()                                  -- gab es Blizzards Fenster beim ersten ShowWhen noch nicht: jetzt
    busy = true
    local ok, result = pcall(RefreshNow, grey)
    busy = nil
    if not ok then
        Core.Error(Core.name, result, "SettingsRows.Refresh")
        return false
    end
    return result
end

function Rows.ShowWhen(page, row, condition, where)
    if type(condition) ~= "function" or type(row) ~= "table" or type(page) ~= "table" then return false end
    local owner = page.owner
    local function Shown()
        local ok, value = Core.Try(owner, (where or "Settings") .. " shown", condition)
        return ok and value and true or false
    end
    conditions[row] = Shown
    local layout = page.layout
    if type(layout) == "table" then lists[layout] = lists[layout] or {} end
    -- fällt die Bedingung weg, während die Seite offen ist: grau, bis sie das nächste Mal aufgeht
    if type(row.AddModifyPredicate) == "function" then pcall(row.AddModifyPredicate, row, Shown) end
    if type(row.AddEvaluateStateCVar) == "function" and Carrier(page.category) then
        pcall(row.AddEvaluateStateCVar, row, Rows.CARRIER)
    end
    Hook()
    return true
end

---------------------------------------------------------------------------
-- Unterschalter
---------------------------------------------------------------------------

local children = setmetatable({}, { __mode = "k" })     -- [Zeile] = true: kleine Schrift wie Blizzards Unterzeilen
local parents = setmetatable({}, { __mode = "k" })      -- [Zeile] = Oberzeile
Rows.CHILD_FONT = "GameFontNormalSmall"

function Rows.IsChild(row) return children[row] == true end
function Rows.ParentOf(row) return parents[row] end

local function OnPage(page, row)
    if type(page) ~= "table" then return false end
    -- die Zeilen-Merker der Seite (page.rows; eine Unterseite erbt die der Modulseite nur über __index, pairs sieht sie nicht)
    for _, other in pairs(type(page.rows) == "table" and page.rows or {}) do
        if other == row then return true end
    end
    local list = ListOf(page.layout)
    for _, other in ipairs(list or {}) do
        if other == row then return true end
    end
    return list == nil          -- Liste nicht lesbar: die Helfer legen Ober- und Unterzeile auf derselben Seite an
end

-- Variable einer Einstellung oder nil
local function Variable(setting)
    if type(setting) ~= "table" or type(setting.GetVariable) ~= "function" then return nil end
    local ok, name = pcall(setting.GetVariable, setting)
    return ok and type(name) == "string" and name or nil
end

-- Einrücken und klein schreiben, wenn die Oberzeile auf derselben Seite steht → eingerückt?
function Rows.Indent(page, row, parentRow)
    if type(row) ~= "table" or type(parentRow) ~= "table" or row == parentRow or not OnPage(page, parentRow) then return false end
    children[row] = true
    if type(row.Indent) == "function" then return (pcall(row.Indent, row)) end
    return false
end

-- Unterschalter einer Oberzeile bzw. eines Oberschalters
function Rows.Child(page, row, parentRow, setting)
    if type(row) ~= "table" then return end
    if type(parentRow) == "table" and parentRow ~= row then parents[row] = parentRow end
    Rows.Indent(page, row, parentRow)
    local variable = Variable(setting)
    if variable and type(row.AddEvaluateStateCVar) == "function" then pcall(row.AddEvaluateStateCVar, row, variable) end
end

-- Nach Blizzards Init einer Zeile (Core.WrapSettingsLabel): Blizzard setzt die Schrift bei jedem Init selbst
function Rows.ApplyFont(frame, row)
    if not children[row] then return false end
    local text = Core.Peek(frame, "Text")
    if type(text) ~= "table" or type(text.SetFontObject) ~= "function" then return false end
    text:SetFontObject(Rows.CHILD_FONT)
    return true
end
