local _, ns = ...
local L = ns.L

-- Einstellungen unter Esc → Optionen → AddOns → ezCollection → ezBars (Seite von ezCore).
-- Hauptseite: Allgemein (Verschieben, Tasten belegen) → Leisten (je Leiste an/aus und Knopf zur eigenen Unterseite)
-- → Profile (Auswahl, für die Klasse, je Spezialisierung, Neu, Exportieren, Importieren, Löschen; Profiles.lua)
-- → Erweitert (Status, Plätze, Plätze neu wählen, Position zurücksetzen, Erklärung erneut zeigen, Einstellungen
-- zurücksetzen, ergänzende Addons).
-- Unterseite je Leiste: Anordnung, Anzeige, Aktionsplätze, Leisten-Profil (ezCores Dienst, auch ohne ezMacro).
-- Unterseite je Leiste eines anderen Moduls (ns.RegisterBar): Anordnung (Spalten, Reihen, Knopfgröße, Abstand),
-- Anzeige (Sichtbar), Lage (Verschieben, Standardplatz). Sie entsteht mit der Anmeldung – auch nach dem Einloggen;
-- der Knopf „Leisten anderer Module“ der Hauptseite führt hin, links in Blizzards Liste steht sie unter ezBars.
local page
ns.barPages = {}
ns.extraPages = {}

-- Abschnitt „Profile“ der Hauptseite: baut ezCore (page:Profiles, eine Umsetzung für alle Module; vorher hier selbst
-- gebaut) – Überschrift, Auswahl „Profil dieses Charakters“, „für die Klasse“, „je Spezialisierung“ (wo der Client
-- Spezialisierungen kennt), Neu, Exportieren, Importieren, Löschen; dieselben Funktionen wie ezCores Profil-Menü.
-- Die Texte, die von den Leisten sprechen, bleiben ezBars' (Locale.lua, gleiche Schlüssel wie in ezCore); nach jedem
-- Wechsel (Auswahl, Neu, Import, Löschen, Spezialisierung) zieht ezCore die Steuerelemente nach.
local function ProfileSection()
    local P = ns.Profiles and ns.Profiles.P
    if not (P and page.Profiles) then return end
    ns.profileSection = page:Profiles(P, { texts = L })
end

-- Zieht Auswahl und Häkchen des Abschnitts „Profile“ nach, ohne selbst etwas zu wechseln (Weiterleitung auf ezCore).
function ns.RefreshProfileControls()
    local section = ns.profileSection
    if section and section.Refresh then section.Refresh() end
end

-- Formate der Schieberegler aus ezCore: Prozent (Core.Percent, ohne Nachkommastellen) und Pixel (Core.Pixels).
local function Percent(value) return ezCore.Percent(value) end

-- Tooltip der Schieberegler „Spalten“ und „Reihen“ als Funktion (Blizzards Settings.InitTooltip ruft sie beim
-- Zeigen auf): der feste Text, dazu wie viele Knöpfe die freien Aktionsplätze gerade erlauben, das jetzige Raster
-- und – wenn es größer ist – wie viele Felder leer bleiben.
function ns.GridTooltip(n, name)
    return function()
        local cols = math.max(1, math.floor(ns.BarSetting(n, "Cols") or 1))
        local rows = math.max(1, math.floor(ns.BarSetting(n, "Rows") or 1))
        local count = ns.Slots.ButtonCount(n)
        local free = ns.Slots.FreeButtons(n)
        local lines = {
            L["OPT_bar" .. n .. name .. "_TIP"],
            L.GRID_MAX:format(free, ns.BarName(n)),
            L.GRID_NOW:format(cols, rows, cols * rows),
        }
        if count > free then lines[#lines + 1] = ezCore.RED .. L.GRID_OVER:format(count - free) .. "|r" end
        return table.concat(lines, "\n\n")
    end
end

local function BarPage(n)
    local sub = page:Sub(ns.BarName(n))
    if not sub then return nil end
    local prefix = "bar" .. n
    sub:Header(L.OPT_HEADER_LAYOUT)
    -- Spalten und Reihen: Tooltip mit der Höchstzahl, die die freien Aktionsplätze gerade erlauben
    sub:Slider(prefix .. "Cols", 1, 12, 1, nil, ns.GridTooltip(n, "Cols"))
    sub:Slider(prefix .. "Rows", 1, 12, 1, nil, ns.GridTooltip(n, "Rows"))
    sub:Slider(prefix .. "Size", 50, 200, 10, Percent)
    sub:Slider(prefix .. "Padding", 0, 20, 1, ezCore.Pixels)

    sub:Header(L.OPT_HEADER_VISIBILITY)
    sub:Dropdown(prefix .. "Show", {
        { "always", L.OPT_SHOW_ALWAYS }, { "combat", L.OPT_SHOW_COMBAT },
        { "nocombat", L.OPT_SHOW_NOCOMBAT }, { "hidden", L.OPT_SHOW_HIDDEN },
    })
    sub:Checkbox(prefix .. "Empty")

    sub:Header(L.OPT_HEADER_SLOTS)
    sub:Dropdown(prefix .. "Page", ns.Slots.DropdownValues())
    sub:Button(L.OPT_SLOTS, L.OPT_SLOTS_BUTTON, ns.PrintFreeSlots, L.OPT_SLOTS_TIP)
    sub:Button(L.OPT_KEYBIND, L.OPT_KEYBIND_BUTTON, ns.OpenKeybindings, L.OPT_KEYBIND_TIP)

    -- Leisten-Profil: ezCores Dienst (Core.BarProfiles) – seit dem Architektur-Review 22.11.2026 auch ohne ezMacro
    do
        local name = ns.ProfileName(n)
        sub:Header(L.OPT_HEADER_PROFILE)
        sub:Button(L.OPT_PROFILE_SAVE, L.OPT_PROFILE_SAVE_BUTTON, function() ns.SaveBarProfile(n) end,
            L.OPT_PROFILE_SAVE_TIP:format(name))
        sub:Button(L.OPT_PROFILE_LOAD, L.OPT_PROFILE_LOAD_BUTTON, function() ns.LoadBarProfile(n) end,
            L.OPT_PROFILE_LOAD_TIP:format(name))
    end
    return sub
end

---------------------------------------------------------------------------
-- Leisten anderer Module
---------------------------------------------------------------------------

-- Tooltip der Regler „Spalten“ und „Reihen“ (beim Zeigen berechnet): der feste Text, das jetzige Raster und die
-- Zahl der Knöpfe des Anbieters; passen nicht alle hinein, wie viele fehlen.
function ns.ExtraGridTooltip(id, name)
    return function()
        local lines = { L["OPT_EXTRA_" .. name:upper() .. "_TIP"] }
        local info = ns.ExtraInfo(id)
        if info then
            lines[#lines + 1] = L.EXTRA_GRID_NOW:format(info.cols, info.rows, info.cols * info.rows, info.buttons)
            if info.cut > 0 then lines[#lines + 1] = ezCore.RED .. L.EXTRA_GRID_CUT:format(info.cut) .. "|r" end
        end
        return table.concat(lines, "\n\n")
    end
end

-- Hinweis für die Unterseite einer Leiste, die ihr Anbieter abgemeldet hat (die Seite bleibt bis zum nächsten Laden
-- stehen): warum sich auf dem Bildschirm nichts ändert. false, wenn es zu der Kennung keine Seite gibt.
function ns.ExtraGoneHint(id)
    local sub = ns.extraPages[id]
    if not sub then return false end
    ns.Print(L.EXTRA_GONE:format(sub.ezTitle or tostring(id)))
    return true
end

-- „Standardplatz“: gemerkte Lage dieser einen Leiste vergessen (ezCore.Mover setzt sie an ihren Anker zurück).
-- Im Kampf vergisst Mover die Lage gleich, setzt die Leiste aber erst danach um – die Meldung sagt, was gilt.
-- Nicht angemeldet: nur der Hinweis. Wirft der Anker des Anbieters beim Setzen, steht die Leiste frei (Fehlerliste
-- des Anbieters, Bars.ExtraAnchorFailed).
function ns.ExtraHome(id)
    local entry = ns.Extra(id)
    if not entry then
        ns.ExtraGoneHint(id)
        return false
    end
    local mover = ezCore.Mover
    if not (mover and mover.Reset) then return false end
    local ok, done = pcall(mover.Reset, ns.Bars.MoverKey(id))
    local title = ns.ExtraTitle(entry)
    if not ok then
        ns.Bars.ExtraAnchorFailed(entry, done)
        ns.Print(title .. ": " .. L.ANCHOR_FALLBACK:format(L["ANCHOR_" .. tostring(entry.anchor)]))
        return false
    end
    if not done then return false end
    ns.Print((ns.InCombat() and L.EXTRA_HOME_LATER or L.EXTRA_HOME_DONE):format(title))
    return true
end

local function ExtraPage(id)
    local entry = ns.Extra(id)
    local sub = entry and page:Sub(ns.ExtraTitle(entry))
    if not sub then return nil end
    sub.ezTitle = ns.ExtraTitle(entry)
    local function Key(name) return ns.ExtraKey(id, name) end
    local function Registered() return ns.Extra(id) ~= nil end
    -- Abgemeldet (der Anbieter zeigt die Leiste nicht mehr, die Seite bleibt bis zum nächsten Laden): Die erste Zeile
    -- sagt, warum sich auf dem Bildschirm nichts ändert. Die Regler bleiben – ihre Werte gelten bei der nächsten
    -- Anmeldung; „Standardplatz“ hätte nichts zu tun und verschwindet. Ein- und Ausblenden über ezCores opts.shown
    -- (page:Button; Blizzards AddShownPredicate, ein Fehler landet in der Fehlerliste).
    sub:Button(L.OPT_EXTRA_GONE, L.OPT_EXTRA_GONE_BUTTON, function() ns.ExtraGoneHint(id) end, L.OPT_EXTRA_GONE_TIP,
        { shown = function() return not Registered() end })
    sub:Header(L.OPT_HEADER_LAYOUT)
    sub:Slider(Key("Cols"), 1, 12, 1, nil, ns.ExtraGridTooltip(id, "Cols"))
    sub:Slider(Key("Rows"), 1, 12, 1, nil, ns.ExtraGridTooltip(id, "Rows"))
    sub:Slider(Key("Size"), 50, 200, 10, Percent)
    sub:Slider(Key("Padding"), 0, 20, 1, ezCore.Pixels)

    sub:Header(L.OPT_HEADER_VISIBILITY)
    sub:Dropdown(Key("Show"), {
        { "always", L.OPT_SHOW_ALWAYS }, { "combat", L.OPT_SHOW_COMBAT },
        { "nocombat", L.OPT_SHOW_NOCOMBAT }, { "hidden", L.OPT_SHOW_HIDDEN },
    })
    -- Lage: Verschieben wie auf der Hauptseite, dazu zurück an den Standardplatz dieser Leiste
    if ezCore.Mover and sub.MoverButton then sub:MoverButton() end
    sub:Button(L.OPT_EXTRA_HOME, L.OPT_EXTRA_HOME_BUTTON, function() ns.ExtraHome(id) end, L.OPT_EXTRA_HOME_TIP,
        { shown = Registered })
    return sub
end

-- Legt die Unterseite einer angemeldeten Leiste an, sobald es die Hauptseite gibt (einmal je Kennung: Blizzards
-- Einstellungen kennen kein Abmelden, eine erneut angemeldete Leiste nutzt ihre Seite weiter).
function ns.EnsureExtraPage(id)
    if not page or ns.extraPages[id] then return ns.extraPages[id] end
    local sub
    ns.Try("Settings", function() sub = ExtraPage(id) end)
    ns.extraPages[id] = sub
    return sub
end

function ns.OpenExtraSettings(id)
    local sub = ns.Extra(id) and ns.EnsureExtraPage(id)
    return sub ~= nil and sub:Open() == true
end

-- Knopf „Leisten anderer Module“: eine Leiste → ihre Seite; mehrere → Auswahl am Knopf (ezCore.Menu), ohne Menü die
-- Liste im Chat; keine → Hinweis, was hier erscheinen würde.
function ns.ShowExtraList(owner)
    local list = ns.Extras()
    if #list == 0 then
        ns.Print(L.EXTRA_NONE)
        return false
    end
    if #list == 1 then return ns.OpenExtraSettings(list[1].id) end
    local Menu = ezCore.Menu
    if type(owner) == "table" and Menu and Menu.Open and Menu.Open(owner, function(root)
        Menu.Title(root, L.OPT_EXTRA_LIST)
        for _, entry in ipairs(list) do
            local id = entry.id
            Menu.Button(root, ns.ExtraTitle(entry), function() ns.OpenExtraSettings(id) end)
        end
    end) then
        return true
    end
    ns.Print(L.EXTRA_LIST_HEAD)
    for _, entry in ipairs(list) do ns.Print("  " .. ns.ExtraTitle(entry)) end
    return false
end

local function Register()
    if page then return end
    page = ezCore.NewSettingsPage(ns)
    if not page then return end

    -- Allgemein: Verschieben über ezCore.Mover (ein Modus: dieselben Rahmen wie in Blizzards Bearbeitungsmodus),
    -- Tasten über Blizzards Tastaturbelegung
    if ezCore.Mover and page.MoverButton then page:MoverButton() end
    page:Button(L.OPT_KEYBIND, L.OPT_KEYBIND_BUTTON, ns.OpenKeybindings, L.OPT_KEYBIND_TIP)

    -- Leisten: an/aus hier, alles Weitere auf der Unterseite der Leiste
    page:Header(L.OPT_HEADER_BARS)
    for n = 1, ns.MAX_BARS do
        page:Checkbox("bar" .. n .. "On")
        page:Button(L.OPT_BAR_PAGE:format(n), L.OPT_BAR_PAGE_BUTTON, function()
            local sub = ns.barPages[n]
            if sub then sub:Open() end
        end, L.OPT_BAR_PAGE_TIP)
    end
    local mac = ns.MacroProfiles()
    if mac and type(mac.OpenProfiles) == "function" then
        page:Button(L.OPT_PROFILES, L.OPT_PROFILES_BUTTON, ns.OpenMacroProfiles, L.OPT_PROFILES_TIP)
    end
    -- Leisten, deren Knöpfe ein anderes Modul liefert (ns.RegisterBar): der sichtbare Weg zu ihren Unterseiten
    page:Button(L.OPT_EXTRA_LIST, L.OPT_EXTRA_LIST_BUTTON, ns.ShowExtraList, L.OPT_EXTRA_LIST_TIP)

    -- Profile der Leisten-Einstellungen (ezCores Profil-Gerüst): je Charakter, Klasse oder Spezialisierung
    ProfileSection()

    page:Advanced()
    page:StatusButton(L.OPT_STATUS_TIP)   -- Beschriftung von ezCore (Gesamtreview T9-2)
    page:Button(L.OPT_SLOTS, L.OPT_SLOTS_BUTTON, ns.PrintFreeSlots, L.OPT_SLOTS_TIP)
    if ezCore.Mover and page.MoverResetButton then page:MoverResetButton() end
    page:Button(L.OPT_REALLOCATE, L.OPT_REALLOCATE_BUTTON, ns.AskReallocate, L.OPT_REALLOCATE_TIP)
    -- „Einstellungen zurücksetzen“ von ezCore (mit Rückfrage); gemerkte Plätze und Lagen bleiben
    -- Erklärblasen (Tour.lua) wieder von vorn zeigen
    if ns.Tour and ns.Tour.tour and page.TourButton then page:TourButton(ns.Tour.tour, L.TOUR_RESET_TIP) end
    page:ResetButton({ tip = L.RESET_TIP, onReset = function() ns.Bars.Apply() end })
    -- Ergänzende Addons anderer Autoren (ezCore.AddCompanion); ezBars braucht nur ezCore, die Liste ist heute leer
    if page.Companions then page:Companions() end

    -- Unterseiten nach der Hauptseite, damit Blizzards Liste sie darunter einrückt
    for n = 1, ns.MAX_BARS do
        ns.barPages[n] = BarPage(n)
    end
    -- Leisten, die schon vor der Seite angemeldet wurden (spätere legt ns.RegisterBar an)
    for _, entry in ipairs(ns.Extras()) do ns.EnsureExtraPage(entry.id) end

    page:Register()
end

ns.OnReady(function() ns.Try("Settings", Register) end)

function ns.OpenSettings()
    local opened = page ~= nil and page:Open()
    if opened and ns.Tour then ns.Tour.Later(0.5) end
    return opened
end

-- „Plätze neu wählen“: nach einer Rückfrage (ezCore.Confirm), weil die Leisten danach andere Plätze zeigen können.
function ns.Reallocate()
    ns.Slots.Reallocate()
    ns.Bars.Apply()
    ns.Print(L.REALLOCATED)
end

function ns.AskReallocate()
    return ezCore.Confirm(L.REALLOCATE_ASK, ns.Reallocate)
end

-- Verschieben (/ezbars verschieben, wie der Knopf „Verschieben“ der Seite): ein Modus über ezCore.Mover.Open – ezCores
-- eigene Auswahl mit Leiste „Fertig“; Blizzards Bearbeitungsmodus (Esc » Bearbeitungsmodus) zeigt dieselben Rahmen. Beide
-- zeigen jede eingeschaltete Leiste mit Blizzards Rahmen (auch versteckte und die Leisten anderer Module). Den Testschalter
-- „comfort.editModeOpen“, mit dem Mover.Open Blizzards Bearbeitungsmodus öffnete, hat der Nutzer am 22.11.2026
-- gestrichen. Alte Basis ohne Mover.Open: Mover.Unlock.
-- → "unlock" (eine ältere ezCore-Fassung kann noch "editmode" liefern), oder false ohne ezCore.Mover.
function ns.OpenMover()
    local mover = ezCore.Mover
    local open = mover and (mover.Open or mover.Unlock)
    if not open then return false end
    return open(ns.moduleName, page) or "unlock"
end
