local ADDON, ns = ...
local Core = ezCore
local L = Core.L

--[[
    Kennzeichen an Aktionsknöpfen – Core.MacroBadge (Welle 15, Paket kern/zauber-datengrundlage; Frage des Nutzers vom
    15.11.2026: „zu den makros, sollten wir denen noch symbole geben um zu zeigen z.b. das ist schnell zaubern ohne ziel
    anzubisieren sondern nur via maus überfahren?“ – ROADMAP.md, „Entscheidungen des Nutzers“).

    Makros, die ein Modul der ezCollection anlegt, bekommen auf Blizzards Aktionsknopf ein kleines Zeichen aus Blizzards
    eigenen Atlas-Grafiken (oben links) und im Tooltip des Knopfs eine Zeile, z. B. „Makro von ezHeal: wirkt auf die
    Einheit unter der Maus, ohne das Ziel zu wechseln“. Gestaltung nach Empfehlung, Antwort des Nutzers offen
    (docs/roadmap/ezCore.md): Zeichen 14 × 14 oben links, Maus für „Maus-Überfahren“, Gruppe für „Durchbuffen“.

    Taint-sicher (Leitlinie 5): nur eine eigene Kind-Textur am Knopf (CreateTexture), angehängt über hooksecurefunc an
    die Methoden Update/UpdateAction des Knopfs und an GameTooltip:SetAction; nichts wird in Blizzards Tabellen
    geschrieben (die Zuordnung Knopf » Zeichen steht in einer eigenen Tabelle mit schwachen Schlüsseln). Texturen sind
    keine geschützten Rahmen – Zeigen und Verbergen geht auch im Kampf.
    Abschaltbar: Schalter „Kennzeichen an Makro-Knöpfen“ (ezCoreDB.comfort.macroBadge, ab Werk an). Rücksicht auf fremde
    Leisten-Addons (Leitlinie 9): gezeichnet wird nur an Blizzards Leisten und an Knöpfen, die ein Modul über
    MacroBadge.Watch anmeldet (ezBars); die Knöpfe von Bartender4 oder Dominos bleiben unberührt, der Tooltip des
    Schalters nennt das laufende Addon (Funktion actionBars).

      MacroBadge.KINDS[art]               { atlases = { … }, glyph } – Arten: mouseover, group
      MacroBadge.Register(owner, regel)   regel: { kind = art | kindOf = fn(name, text) » art, prefix = "ezH ",
                                          body = "/click …", match = fn(name, text) » bool }; eine neue Anmeldung desselben
                                          owner ersetzt die alte. → true
      MacroBadge.Match(name, text)        » art, owner | nil
      MacroBadge.ForSlot(platz)           » art, owner | nil (nur Makros: GetActionInfo, ActionSlots.Text, GetMacroInfo);
                                          eigene Makros des Spielers mit Mausziel: "mouseover", MacroBadge.OWNER_PLAYER
      MacroBadge.OwnKind(text)            » "mouseover", wenn ein Makro-Text auf die Einheit unter der Maus zielt
                                          (@mouseover bzw. target=mouseover), sonst nil
      MacroBadge.OwnEnabled()             » Schalter „auch eigene Makros mit Mausziel“ an (und der Hauptschalter)?
      MacroBadge.Watch(knopf)             Knopf anmelden (Aktionsknopf mit Feld action bzw. Attribut action)
      MacroBadge.Watched(knopf)           » angemeldet?
      MacroBadge.Refresh(knopf), RefreshAll()
      MacroBadge.Enabled()                » Schalter an?
      MacroBadge.BadgeOf(knopf)           » eigene Textur des Knopfs oder nil (für Prüfungen)
      MacroBadge.TooltipLine(platz)       » Text der Tooltip-Zeile oder nil
    Eigene Makros (Welle 23d; Entscheidung des Nutzers vom 16.11.2026, Nr. 37 „den Empfehlungen folgen“): Makros, die
    der Spieler selbst geschrieben hat und die auf die Einheit unter der Maus zielen, bekommen dasselbe Maus-Zeichen und
    die Zeile „Eigenes Makro: wirkt auf die Einheit unter der Maus …“. Nur, wenn keine Regel eines Moduls greift (die
    geht vor); abschaltbar über den Schalter „Kennzeichen auch an eigenen Makros mit Mausziel“
    (ezCoreDB.comfort.macroBadgeOwn, ab Werk an). MacroBadge.Match bleibt bei den Regeln der Module (ezMacro fragt dort
    nach dem Modul eines Makros).
]]

local MB = {}
Core.MacroBadge = MB

MB.SIZE = 14
MB.KINDS = {
    mouseover = { atlases = { "newplayertutorial-icon-mouse-leftbutton", "NPE_LeftClick" }, glyph = "M" },
    group = { atlases = { "socialqueuing-icon-group", "groupfinder-icon-friend" }, glyph = "G" },
}
-- Blizzards Leisten (Forever, Mainline: Blizzard_ActionBar), je 12 Knöpfe
MB.BLIZZARD_BARS = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
    "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }

Core.OwnDefaults("comfort", { macroBadge = true, macroBadgeOwn = true })
MB.OWNER_PLAYER = "player"

-- Selbsttest (/ez test): kennt der Client die Atlanten? (optional – sonst steht ein Buchstabe da)
if Core.SELFTEST and type(Core.SELFTEST.atlases) == "table" then
    for _, kind in pairs(MB.KINDS) do
        for _, name in ipairs(kind.atlases) do table.insert(Core.SELFTEST.atlases, { name, optional = true }) end
    end
end

function MB.Enabled()
    return Core.OwnSetting("comfort", "macroBadge") ~= false
end

function MB.OwnEnabled()
    return MB.Enabled() and Core.OwnSetting("comfort", "macroBadgeOwn") ~= false
end

-- Zielt ein Makro-Text auf die Einheit unter der Maus? „@mouseover“ bzw. „target=mouseover“ in einer Bedingung,
-- Groß- und Kleinschreibung egal (Blizzards Makro-Bedingungen). → "mouseover" oder nil
-- Gegenprüfung 23d: nur die Einheit selbst (nicht „@mouseovertarget“, das Ziel der Einheit unter der Maus) und nicht
-- in Zeilen, die das Ziel oder den Fokus ausdrücklich wechseln (MB.OWN_TARGETING) – die Tooltip-Zeile sagt „ohne das
-- Ziel zu wechseln“.
MB.OWN_TARGETING = { ["/target"] = true, ["/tar"] = true, ["/targetexact"] = true, ["/focus"] = true,
    ["/assist"] = true }
function MB.OwnKind(body)
    if type(body) ~= "string" or Core.IsSecret(body) then return nil end
    for line in body:lower():gmatch("[^\r\n]+") do
        local cmd = line:match("^%s*(/[^%s%[]+)")
        if not (cmd and MB.OWN_TARGETING[cmd]) and (line:find("@mouseover%f[^%w_]")
            or line:find("target%s*=%s*mouseover%f[^%w_]")) then
            return "mouseover"
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- Regeln
---------------------------------------------------------------------------

local rules, ruleOrder = {}, {}

function MB.Register(owner, rule)
    if type(owner) ~= "string" or owner == "" or type(rule) ~= "table" then return false end
    if not (MB.KINDS[rule.kind] or type(rule.kindOf) == "function") then return false end
    if not (rule.prefix or rule.body or type(rule.match) == "function") then return false end
    if not rules[owner] then ruleOrder[#ruleOrder + 1] = owner end
    rules[owner] = rule
    if MB.RefreshAll then MB.RefreshAll() end
    return true
end

function MB.Match(name, body)
    if type(name) ~= "string" then return nil end
    body = type(body) == "string" and body or ""
    for _, owner in ipairs(ruleOrder) do
        local r = rules[owner]
        local hit = (type(r.prefix) == "string" and name:sub(1, #r.prefix) == r.prefix)
            or (type(r.body) == "string" and body:find(r.body, 1, true) ~= nil)
        if not hit and type(r.match) == "function" then
            local ok, result = pcall(r.match, name, body)
            hit = ok and result == true
        end
        if hit then
            local kind = r.kind
            if type(r.kindOf) == "function" then
                local ok, result = pcall(r.kindOf, name, body)
                kind = ok and result or nil
            end
            if MB.KINDS[kind] then return kind, owner end
        end
    end
    return nil
end

-- Rückfall für ezBuff: „/click ezBuffGroupNext“ (Group.NEXT_NAME, ezBuff/Macro.lua). ezBuff meldet sich seit Welle 22
-- selbst an (Macro.RegisterBadge, ersetzt diese Regel); sie wirkt, solange ezBuff nicht geladen ist (ein ezBuff-Makro
-- auf der Leiste behält sein Kennzeichen; ezMacro/Tests/makro_arten15.lua prüft genau das).
-- Welle 26 (Nachtrag A7 aus Welle 23): die Übergangsregel für ezHeal (Vorsilbe „ezH “, Art aus @mouseover) ist
-- gestrichen – ezHeal meldet sich seit Welle 23 beim Laden selbst an (ezHeal/Macros.lua, M.RegisterBadge;
-- ezHeal/Tests/reste23.lua prüft es).
MB.Register("ezBuff", { kind = "group", body = "/click ezBuffGroupNext" })

---------------------------------------------------------------------------
-- Aktionsplatz » Makro » Art
---------------------------------------------------------------------------

function MB.ForSlot(slot)
    slot = Core.Num(slot)
    if not slot then return nil end
    local kind = Core.Call(rawget(_G, "GetActionInfo"), slot)
    if Core.IsSecret(kind) or kind ~= "macro" then return nil end
    local name = Core.ActionSlots.Text(slot)
    if not name then return nil end
    local macroName, _, body = Core.Call(rawget(_G, "GetMacroInfo"), name)
    macroName, body = Core.Plain(macroName), Core.Plain(body)
    local kind, owner = MB.Match(type(macroName) == "string" and macroName or name, body)
    if kind then return kind, owner end
    -- eigenes Makro des Spielers mit Mausziel (Welle 23d, Nr. 37): nur, wenn keine Regel eines Moduls greift
    if MB.OwnEnabled() then
        kind = MB.OwnKind(body)
        if kind then return kind, MB.OWNER_PLAYER end
    end
    return nil
end

function MB.TooltipLine(slot)
    if not MB.Enabled() then return nil end
    local kind, owner = MB.ForSlot(slot)
    if not kind then return nil end
    if owner == MB.OWNER_PLAYER then return L.MACROBADGE_OWN_LINE:format(L["MACROBADGE_" .. kind]) end
    return L.MACROBADGE_LINE:format(owner, L["MACROBADGE_" .. kind])
end

---------------------------------------------------------------------------
-- Zeichen am Knopf
---------------------------------------------------------------------------

local watched = setmetatable({}, { __mode = "k" })   -- Knopf » true
local badges = setmetatable({}, { __mode = "k" })    -- Knopf » { tex, text }
local hooked = setmetatable({}, { __mode = "k" })

local function SlotOf(button)
    local action = Core.Num(Core.Peek(button, "action"))
    if action and action > 0 then return action end
    local getter = Core.Peek(button, "GetAttribute")
    local value = getter and Core.Call(getter, button, "action")
    value = Core.Plain(value)
    return tonumber(value)
end

local function Badge(button)
    local b = badges[button]
    if b then return b end
    b = {}
    b.tex = button:CreateTexture(nil, "OVERLAY", nil, 7)
    b.tex:SetSize(MB.SIZE, MB.SIZE)
    b.tex:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
    if button.CreateFontString then
        b.text = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        b.text:SetPoint("TOPLEFT", button, "TOPLEFT", 3, -2)
    end
    badges[button] = b
    return b
end

local atlasOf = {}   -- Art » erster vorhandener Atlas (false: keiner)
local function AtlasFor(kind)
    if atlasOf[kind] == nil then atlasOf[kind] = Core.FirstAtlas(MB.KINDS[kind].atlases) or false end
    return atlasOf[kind]
end

function MB.Refresh(button)
    if not button then return end
    local kind
    if MB.Enabled() then kind = MB.ForSlot(SlotOf(button)) end
    local b = badges[button]
    if not kind then
        if b then
            b.tex:Hide()
            if b.text then b.text:Hide() end
            b.kind = nil
        end
        return
    end
    b = Badge(button)
    if b.kind ~= kind then
        local atlas = AtlasFor(kind)
        if atlas and pcall(b.tex.SetAtlas, b.tex, atlas) then
            if b.text then b.text:Hide() end
            b.tex:Show()
        else
            b.tex:Hide()
            if b.text then b.text:SetText(MB.KINDS[kind].glyph) b.text:Show() end
        end
        b.kind = kind
    elseif not b.tex:IsShown() and not (b.text and b.text:IsShown()) then
        if AtlasFor(kind) then b.tex:Show() elseif b.text then b.text:Show() end
    end
end

function MB.BadgeOf(button)
    local b = badges[button]
    return b and b.kind and b or nil
end

function MB.Watch(button)
    if type(button) ~= "table" or watched[button] then return false end
    watched[button] = true
    if not hooked[button] and type(hooksecurefunc) == "function" then
        for _, method in ipairs({ "Update", "UpdateAction" }) do
            if type(Core.Peek(button, method)) == "function" then
                hooksecurefunc(button, method, function(self) MB.Refresh(self) end)
            end
        end
        hooked[button] = true
    end
    MB.Refresh(button)
    return true
end

function MB.Watched(button) return watched[button] == true end

-- Gehört der Tooltip einem angemeldeten Knopf? (GameTooltip:GetOwner; ohne Besitzer: nein)
function MB.TooltipOwnerWatched(tip)
    local getOwner = type(tip) == "table" and Core.Peek(tip, "GetOwner")
    if type(getOwner) ~= "function" then return false end
    local ok, owner = pcall(getOwner, tip)
    return ok and owner ~= nil and watched[owner] == true or false
end

function MB.RefreshAll()
    for button in pairs(watched) do MB.Refresh(button) end
end

-- Viele ACTIONBAR_SLOT_CHANGED hintereinander (Anmelden, Profilwechsel): einmal danach neu zeichnen
local pending = false
local function Soon()
    if pending then return end
    pending = true
    C_Timer.After(0.1, function()
        pending = false
        MB.RefreshAll()
    end)
end
MB.Soon = Soon

function MB.WatchBlizzard()
    local n = 0
    for _, prefix in ipairs(MB.BLIZZARD_BARS) do
        for i = 1, 12 do
            local button = rawget(_G, prefix .. i)
            if type(button) == "table" and MB.Watch(button) then n = n + 1 end
        end
    end
    return n
end

for _, event in ipairs({ "ACTIONBAR_SLOT_CHANGED", "UPDATE_MACROS", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR" }) do
    Core.RegisterEvent(ADDON, event, Soon)
end
Core.RegisterEvent(ADDON, "PLAYER_LOGIN", function()
    MB.WatchBlizzard()
    local tip = rawget(_G, "GameTooltip")
    if tip and type(hooksecurefunc) == "function" and type(Core.Peek(tip, "SetAction")) == "function" then
        hooksecurefunc(tip, "SetAction", function(self, slot)
            -- nur an angemeldeten Knöpfen (Blizzard, ezBars): fremde Leisten-Addons, die ihren Tooltip ebenfalls
            -- über GameTooltip:SetAction zeigen, bleiben ohne Zeile (Gegenprüfung Welle 15)
            if not MB.TooltipOwnerWatched(self) then return end
            local line = MB.TooltipLine(slot)
            if line then
                Core.TipLine(self, line, "blue", true)
                self:Show()
            end
        end)
    end
end)
