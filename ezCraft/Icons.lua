local _, ns = ...
local Core = ezCore

--[[
    Symbole der ezCraft-Menüs an EINER Stelle (Welle 27, Zweig modul/ezcraft-menue; Wunsch des Nutzers vom 16.11.2026,
    wörtlich: „ggf auch das ezcraft refaktorieren? + eztalente“ und „also das menü“ – im Anschluss an den Wunsch zum
    ezMap-Menü: „die passenden icons wären der hit – menüaufteilung und ggf. eine refactorierung sinnvoll, ein stil
    siehe designsystem“). Regel: Design-System 2.3 („Symbole an Menüeinträgen“, Rolle line = 16) über ezCores Helfer
    Core.Menu.Icon, Core.Menu.IconRoot, Core.Menu.Section und Core.Menu.ProfessionIcon – keine eigene Kopie (Leitlinie 2).

    Menüs von ezCraft (eine Suche über das Modul; das Seitenteil Panel.lua hat Knöpfe und Reiter, aber kein Menü):
      Book.lua    Menü „Fundorte“ am Knopf der Sammelberufe im Berufsbuch (Kräuterkunde, Bergbau, Kürschnerei, Angeln)
      Filter.lua  Abschnitt „Farbe (ezCraft)“ in Blizzards Filtermenü des Berufefensters (ergänzt, nicht nachgebaut)
      Sort.lua    Abschnitt „Reihenfolge (ezCraft)“ im selben Menü

    Quellen in dieser Reihenfolge (Leitlinien 1 und 11), keine eigenen Bilddateien:
      1. Blizzards Bild derselben Sache zur Laufzeit: Gegenstandssymbol des Rohstoffs (Core.ItemIcon, C_Item), Bild des
         Berufszaubers (Core.Menu.ProfessionIcon) – mit abgeschnittenem Rand wie Blizzards Zauber im Menü „Aufspüren“.
      2. Blizzards Atlas (gilt nur, wenn der Client ihn kennt – Core.AtlasExists).
      3. Blizzards Dateien (nur, wenn der Client sie kennt – Core.KnownFile).
      Fehlt alles, nimmt ezCore Blizzards Fragezeichen (Core.Menu.ICON_FALLBACK) – nie ein leeres Feld.
    Gleiche Dinge tragen dasselbe Symbol wie in ezMap (ezMap/Icons.lua): „Farbe“ wie ezMaps „gatherColor“
    (INV_Misc_Gem_Variety_01), Hinweise wie ezMaps „info“ (Blizzards „i“ der Hilfe-Knöpfe), der Kartenpunkt wie ezMaps
    Wegpunkte (Atlas „Waypoint-MapPin-Tracked“).

    Farbstufen als Marke: Blizzards farbige Kennzeichen Interface\Common\Indicator-Red/-Yellow/-Green/-Gray. Ein
    oranges Kennzeichen hat Blizzard nicht – „Orange (sicher)“ nimmt das rote (Blizzards Farbe für „optimal“ ist ein
    rötliches Orange). „Weiß“ hat keine eigene Farbe (der Client nennt keine Schwierigkeit) und trägt das Symbol der
    Gruppe. Kennt der Client ein Kennzeichen nicht, gilt das Symbol der Gruppe, dann ezCores Rückfall. Eine genaue
    Einfärbung bräuchte eine Farb-Angabe in Core.Menu.IconMarkup (Vorschlag in docs/roadmap/ezCraft.md).

      Icons.DEF[schlüssel] = Angabe für Core.Menu.IconMarkup ({ atlas, file, crop })
      Icons.For(schlüssel) → Angabe oder nil; Icons.Color(farbe) → Angabe (nie nil)
      Icons.Profession(art) → Angabe des Berufs („herb“, „ore“, „fish“, „skin“) oder nil
      Icons.Item(itemID, art) → Angabe: Blizzards Gegenstandssymbol, sonst das Symbol des Berufs
      Icons.Apply(eintrag, schlüssel | angabe) → eintrag; Icons.Root(root, schlüssel | angabe) → Hülle (Core.Menu.IconRoot)
      Icons.Section(root, titel, opts) → Hülle (Core.Menu.Section); ohne den Helfer Trenner und Überschrift (nur Schutz für Tests)
]]
local Icons = {}
ns.Icons = Icons

local I = "Interface\\Icons\\"
local COLORS = I .. "INV_Misc_Gem_Variety_01"

-- Art des Menüs im Berufsbuch » Kennung in ezCores Berufsliste (KnowledgeData.PROFESSIONS)
Icons.PROFESSION = { herb = "herbalism", ore = "mining", fish = "fishing", skin = "skinning" }
-- Blizzards Berufssymbole als Rückfall, wenn der Client weder Gegenstands- noch Zaubersymbol nennt
Icons.PROFESSION_FILE = {
    herb = I .. "Trade_Herbalism", ore = I .. "Trade_Mining", fish = I .. "Trade_Fishing",
    skin = I .. "INV_Misc_Pelt_Wolf_01",
}

Icons.DEF = {
    -- Berufsbuch (Book.lua)
    nearest = { atlas = "Waypoint-MapPin-Tracked", file = I .. "INV_Misc_Map_01" },
    above = { file = { "Interface\\LFGFrame\\UI-LFG-ICON-LOCK", I .. "INV_Misc_Key_03" } },
    info = { file = "Interface\\Common\\help-i" },
    -- Farbfilter (Filter.lua)
    colors = { file = COLORS, crop = true },
    orange = { file = { "Interface\\Common\\Indicator-Red", COLORS } },
    yellow = { file = { "Interface\\Common\\Indicator-Yellow", COLORS } },
    green = { file = { "Interface\\Common\\Indicator-Green", COLORS } },
    gray = { file = { "Interface\\Common\\Indicator-Gray", COLORS } },
    white = { file = COLORS, crop = true },
    -- Reihenfolge der Rezeptliste (Sort.lua): Blizzards Besen der Taschen
    sort = { atlas = "bags-button-autosort-up", file = { I .. "INV_Pet_Broom", I .. "INV_Misc_Note_01" } },
}

-- Die Helfer stehen in den needs von Core.lua: fehlt einer (älteres ezCore), meldet ezCore „zu alt“ und ezCraft startet
-- nicht (RunReady läuft nicht). Die Abfragen über Has greifen darum nur in Tests und Stubs, die needs umgehen.
local function Has(name) return type(Core.Menu) == "table" and type(Core.Menu[name]) == "function" end

function Icons.For(key) return Icons.DEF[key] end

function Icons.Color(color) return Icons.DEF[color] or Icons.DEF.colors end

-- Bild des Berufszaubers (ezCores Core.Menu.ProfessionIcon), dahinter Blizzards Datei des Berufs als Rückfall
function Icons.Profession(kind)
    local key, file = Icons.PROFESSION[kind], Icons.PROFESSION_FILE[kind]
    if not (key or file) then return nil end
    local spec = key and Has("ProfessionIcon") and Core.Menu.ProfessionIcon(key) or nil
    return function()
        local files = {}
        if type(spec) == "function" then
            local ok, s = pcall(spec)
            if ok and type(s) == "table" then
                for _, f in ipairs(type(s.file) == "table" and s.file or { s.file }) do files[#files + 1] = f end
            end
        end
        files[#files + 1] = file
        return { file = files, crop = true }
    end
end

-- Gegenstandssymbol aus dem Client (rechnet erst beim Bau des Menüs), sonst Blizzards Datei des Berufs
function Icons.Item(itemID, kind)
    return function()
        local files = {}
        local ok, icon = pcall(Core.ItemIcon, itemID)
        if ok and not Core.IsSecret(icon) and (type(icon) == "number" or type(icon) == "string") then files[1] = icon end
        files[#files + 1] = Icons.PROFESSION_FILE[kind]
        return { file = files, crop = true }
    end
end

local function Spec(key)
    if type(key) == "string" then return Icons.DEF[key] end
    return key
end

function Icons.Apply(entry, key)
    local spec = Spec(key)
    if spec == nil or not Has("Icon") then return entry end
    return Core.Menu.Icon(entry, spec)
end

-- Hülle: Symbol als Vorgabe für jeden Eintrag, den ein Baustein direkt anlegt; Hilfszeilen mit „info“
function Icons.Root(root, key)
    local spec = Spec(key)
    if spec == nil or not Has("IconRoot") then return root end
    return Core.Menu.IconRoot(root, spec, { titleIcon = Icons.DEF.info })
end

-- Abschnitt mit Überschrift, die erst mit dem ersten Eintrag erscheint (Core.Menu.Section). Ohne den Helfer: Trenner
-- (ohne opts.first) und Überschrift mit Tooltip sofort – im Spiel nie (siehe Has), nur Schutz für Tests und Stubs.
function Icons.Section(root, title, opts)
    opts = type(opts) == "table" and opts or {}
    local M = Core.Menu
    if Has("Section") then return M.Section(root, title, opts) end
    if not opts.first then M.Divider(root) end
    M.Tip(M.Title(root, title), title, opts.tip, opts.source)
    return root
end
