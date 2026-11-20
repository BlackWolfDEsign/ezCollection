local _, ns = ...
local L = ns.L

-- Bedingungs-Baukasten (wie Macro Toolkit): Knopf „Bedingung“ auf der Seite „Anpassen“ öffnet ein Menü.
-- Oben fertige Bausteine („Maus, sonst Ziel“ …), darunter eine eigene Bedingung zum Ankreuzen: ein Ziel,
-- beliebig viele Zustände und Tasten. „Einfügen“ setzt sie an der Schreibmarke in den Makrotext.
-- Blizzards Makro-Bedingungen: [@ziel,help,nodead,mod:shift,combat …], mehrere Klammern = „sonst“.
local Builder = {}
ns.Builder = Builder

-- Fertige Bausteine: Text der Bedingung und Beschreibung (L.BUILDER_Q_<key>). „Heilen: Maus“ setzt das Mitglied unter
-- der Maus zuerst – kein Durchrutschen auf das Ziel (ns.GroupFirst, Spieltest 15.11.2026).
Builder.QUICK = {
    { key = "MOUSE_HELP", text = ns.GroupFirst("[@mouseover,help,nodead][]") },
    { key = "MOUSE_HARM", text = "[@mouseover,harm,nodead][]" },
    { key = "FOCUS", text = "[@focus,harm,nodead][]" },
    { key = "SELF_ALT", text = "[mod:alt,@player][]" },
    { key = "CURSOR", text = "[@cursor]" },
    { key = "COMBAT", text = "[combat]" },
    { key = "NOCOMBAT", text = "[nocombat]" },
    { key = "SHIFT", text = "[mod:shift]" },
}

-- Ziele (eins oder keins), Zustände und Tasten (beliebig viele).
Builder.TARGETS = { "@mouseover", "@focus", "@target", "@targettarget", "@player", "@cursor", "@pet" }
Builder.STATES = { "help", "harm", "exists", "nodead", "dead", "party", "raid", "combat", "nocombat", "stealth", "mounted",
    "nomounted", "swimming", "flying", "indoors", "outdoors", "group", "group:raid", "channeling" }
Builder.KEYS = { "mod:shift", "mod:ctrl", "mod:alt", "nomod", "btn:2" }

local chosen = { target = nil, set = {} }

-- Bedingung aus der Auswahl, z. B. „[@mouseover,help,nodead]“; ohne Auswahl „[]“.
function Builder.Compose(target, set)
    local parts = {}
    if target then parts[#parts + 1] = target end
    for _, list in ipairs({ Builder.STATES, Builder.KEYS }) do
        for _, condition in ipairs(list) do
            if set[condition] then parts[#parts + 1] = condition end
        end
    end
    return "[" .. table.concat(parts, ",") .. "]"
end

function Builder.Current() return Builder.Compose(chosen.target, chosen.set) end

function Builder.Reset()
    chosen.target = nil
    wipe(chosen.set)
end

-- Beschriftung eines Bausteins: Text der Bedingung und, falls übersetzt, was sie bedeutet.
local function Label(condition)
    local key = "BUILDER_C_" .. condition:gsub("[@:]", ""):upper()
    local meaning = L[key]   -- fehlende Texte liefern den Schlüssel selbst
    if type(meaning) == "string" and meaning ~= key then
        return condition .. "  " .. ezCore.Grey(meaning)   -- Erklärung grau wie ezCores Hinweise (Design-System 2.5)
    end
    return condition
end

-- Menü am Knopf; insert(text) fügt in den Makrotext ein.
-- Menü über ezCore.Menu (Blizzards MenuUtil); Häkchen lassen das Menü offen.
local function GetTarget() return chosen.target end
local function SetTarget(target) chosen.target = target end

local function Toggle(root, condition)
    ezCore.Menu.Toggle(root, Label(condition), function() return chosen.set[condition] == true end,
        function(on) chosen.set[condition] = on or nil end)
end

function Builder.Menu(owner, insert)
    local Menu = ezCore.Menu
    return Menu.Open(owner, function(root)
        Menu.Title(root, L.BUILDER_QUICK)
        for _, quick in ipairs(Builder.QUICK) do
            Menu.Button(root, L["BUILDER_Q_" .. quick.key] .. "  " .. ezCore.Grey(quick.text), function()
                insert(quick.text .. " ")
            end)
        end
        Menu.Divider(root)
        Menu.Title(root, L.BUILDER_OWN)
        local targets = Menu.Button(root, L.BUILDER_TARGET)
        Menu.Radio(targets, L.BUILDER_TARGET_NONE, GetTarget, SetTarget, nil)
        for _, target in ipairs(Builder.TARGETS) do
            Menu.Radio(targets, Label(target), GetTarget, SetTarget, target)
        end
        local states = Menu.Button(root, L.BUILDER_STATE)
        for _, condition in ipairs(Builder.STATES) do Toggle(states, condition) end
        local keys = Menu.Button(root, L.BUILDER_KEYS)
        for _, condition in ipairs(Builder.KEYS) do Toggle(keys, condition) end
        Menu.Button(root, L.BUILDER_INSERT, function()
            insert(Builder.Current() .. " ")
        end)
        Menu.Button(root, L.BUILDER_RESET, Builder.Reset)
        Menu.Divider(root)
        Menu.Button(root, L.BUILDER_SHOWTOOLTIP, function() insert("#showtooltip\n") end)
    end)
end
