local ADDON, ns = ...
local Core = ezCore

-- Lange Makros über 255 Zeichen (wie Super Duper Macro): In Blizzards Makro steht nur „/click ezMacroLong<n>“,
-- der ganze Text liegt in ezMacroDB.long und läuft über einen unsichtbaren sicheren Knopf aus ezCore
-- (Core.SecureButton: SecureActionButtonTemplate, type „macro“, macrotext, Klick beim Loslassen). Anlegen und
-- Ändern geht nur außerhalb des Kampfes; was im Kampf ansteht, merkt sich ezCores Dienst und holt es danach nach.
-- Einschränkungen: Lange Makros wirken nur, solange ezMacro geladen ist; jede einzelne Zeile bleibt bei
-- höchstens 255 Zeichen (Blizzard führt Makros Zeile für Zeile aus).
ns.LONG_MAX_CHARS = 1023

local Long = {}
ns.Long = Long

local PREFIX = "ezMacroLong"

-- Lange Makros brauchen ezCores sichere Knöpfe (Core.SecureButton) – das prüft ezCore über ns.CORE_NEEDS (EC-67);
-- ist ezCore zu alt, läuft ezMacro gar nicht erst an. Ohne Datenbank (vor dem Laden) gibt es keine.
function Long.Available()
    return ns.db ~= nil
end

function Long.ButtonName(id) return PREFIX .. id end

-- Nummer des langen Makros aus Blizzards Makrotext („/click ezMacroLong3“), sonst nil.
function Long.IdOf(body)
    if type(body) ~= "string" then return nil end
    return tonumber(body:match("/click%s+" .. PREFIX .. "(%d+)"))
end

-- Ganzer Text eines langen Makros, sonst nil.
function Long.FullBody(body)
    local id = Long.IdOf(body)
    local record = id and ns.db and ns.db.long[id]
    return record and record.body or nil
end

-- Gilt das lange Makro für diesen Charakter? Allgemeine für alle, Charakter-Makros nur für ihren Besitzer.
local function Mine(record)
    return type(record) == "table" and (not record.perChar or record.owner == ns.charKey)
end

-- Knopf des langen Makros anlegen bzw. seinen Text setzen. Derselbe Name liefert denselben Knopf; im Kampf
-- wartet ezCores Dienst (der letzte Wunsch gewinnt). Klick beim Loslassen und useOnKeyDown = false sind dort der
-- Standard: /click sendet ein Loslassen, egal wie „Aktion beim Drücken“ eingestellt ist.
-- Rückgabe wie Core.SecureButton: Knopf | nil, grund. Den Dienst prüft ezCore über ns.CORE_NEEDS (EC-67).
local function Apply(id)
    local record = ns.db.long[id]
    return Core.SecureButton(Long.ButtonName(id), { owner = ADDON,
        action = { type = "macro", macrotext = Mine(record) and record.body or nil } })
end

-- Text in Blizzards Makro: die erste #showtooltip-Zeile (zeigt Symbol und Tooltip) und /click.
function Long.StubBody(id, body)
    local show = body:match("^(#show[^\n]*)\n")
    local click = "/click " .. Long.ButtonName(id)
    return show and (show .. "\n" .. click) or click
end

local function NextId()
    local id = math.max(tonumber(ns.db.longNext) or 1, 1)
    while ns.db.long[id] do id = id + 1 end
    ns.db.longNext = id + 1
    return id
end

-- Legt ein langes Makro an oder ändert es (current: bisheriger Text in Blizzards Makro, behält die Nummer).
-- Rückgabe: Text für Blizzards Makro oder nil (im Kampf bzw. ohne Datenbank).
function Long.Store(name, body, perChar, current)
    if not Long.Available() or ns.InCombat() then return nil end
    local id = Long.IdOf(current)
    if not (id and ns.db.long[id]) then id = NextId() end
    ns.db.long[id] = { name = name, body = body, perChar = perChar and true or nil,
        owner = perChar and ns.charKey or nil }
    Apply(id)
    return Long.StubBody(id, body)
end

-- Vergisst das lange Makro hinter einem Makrotext (Makro gelöscht oder wieder kurz).
function Long.Release(body)
    local id = Long.IdOf(body)
    if not (id and ns.db and ns.db.long[id]) then return end
    ns.db.long[id] = nil
    -- Text vom Knopf nehmen; im Kampf holt ezCore das nach (vorher blieb der alte Text bis zum Neuladen klickbar)
    local button = Core.SecureButtons and Core.SecureButtons.Get(Long.ButtonName(id))
    if button then button:Set("macrotext", nil) end
end

-- Räumt lange Makros auf, deren Blizzard-Makro es nicht mehr gibt (nur allgemeine und eigene; die
-- Charakter-Makros der Twinks kennt nur der jeweilige Twink). Erst, wenn die Makroliste geladen ist.
function Long.Cleanup()
    if not (ns.db and ns.Macros) then return end
    local all = ns.Macros.All()
    if #all == 0 then return end
    local used = {}
    for _, macro in ipairs(all) do
        local id = Long.IdOf(macro.body)
        if id then used[id] = true end
    end
    for id, record in pairs(ns.db.long) do
        if Mine(record) and not used[id] then ns.db.long[id] = nil end
    end
end

function Long.Count()
    local n = 0
    for _, record in pairs(ns.db and ns.db.long or {}) do
        if Mine(record) then n = n + 1 end
    end
    return n
end

-- Die langen Makros dieses Charakters, wie sie in Blizzards Makroverwaltung stehen (V-099, Werkzeug „Lange
-- Makros“): { { macro = { index, name, icon, perChar … }, id, chars, body } … }. Steht im Platz ein /click, dessen
-- Text ezMacro nicht (mehr) kennt, ist missing = true und body nil – das Makro wirkt dann nichts.
function Long.List()
    local list = {}
    if not (ns.db and ns.Macros) then return list end
    for _, macro in ipairs(ns.Macros.All()) do
        local id = Long.IdOf(macro.body)
        if id then
            local record = ns.db.long[id]
            local body = Mine(record) and record.body or nil
            list[#list + 1] = { macro = macro, id = id, body = body, chars = body and #body or 0, missing = body == nil }
        end
    end
    return list
end

-- Knöpfe aller eigenen langen Makros anlegen (beim Einloggen; nach einem Neuladen im Kampf erst nach dem Kampf).
function Long.ApplyAll()
    for id, record in pairs(ns.db.long) do
        if Mine(record) then Apply(id) end
    end
end

ns.OnReady(Long.ApplyAll)
