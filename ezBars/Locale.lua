local _, ns = ...

-- Texte: Deutsch ist die Grundsprache, Englisch für alle anderen Clients.
-- Jede Option sagt zuerst, was sie dir bringt.
local de = {
    -- Kurzüberblick für die Einführung (ezCore, Core.Intro.Features): was das Modul kann, 3 bis 6 Zeilen
    INTRO_FEATURES = "Bis zu vier Zusatzleisten, Blizzard-Knöpfe\nFormen frei, von 2×2 bis 12×12\nGröße, Sichtbarkeit und Tasten je Leiste\nVerschieben im Bearbeitungsmodus\nLeisten-Profile, auch ohne ezMacro",
    TITLE = "ezBars",
    -- Hilfe: Kopf und Standardbefehle (Einstellungen, status, hilfe, zuruecksetzen) sagt ezCore (Core.HelpLines),
    -- hier nur die eigenen Wörter; %s = der geltende Befehl (Gesamtreview 18.11.2026, T18-20)
    CMD_HELP_OWN = {
        "  %s tasten – Blizzards Tastaturbelegung öffnen",
        "  %s verschieben – Leisten verschieben (dieselben Rahmen wie im Bearbeitungsmodus)",
        "  %s plaetze – freie Aktionsplätze dieses Charakters",
    },

    BAR_NAME = "Leiste %d",
    BUTTON_NAME = "Leiste %d, Knopf %d",
    MOVER_LABEL = "ezBars: Leiste %d",
    BINDING_HEADER = "ezBars (Zusatzleisten)",

    -- Seiten der Aktionsplätze (je 12 Plätze). Blizzard zählt die Leisten in den Optionen „Aktionsleiste 2 … 8“.
    PAGE_AUTO = "Automatisch (freie Plätze)",
    PAGE_LABEL = "Plätze %d–%d: %s",
    PAGE_2 = "Hauptleiste, Seite 2 (Umschalt+Mausrad)",
    PAGE_BLIZZARD = "Blizzards Aktionsleiste %d",
    PAGE_STANCE = "Gestalt-/Haltungsleiste %d",
    PAGE_STATE_FREE = "frei",
    PAGE_STATE_BLIZZARD = "zeigt auch %s",
    PAGE_STATE_STANCE = "braucht deine Klasse für Gestalt/Haltung",
    PAGE_STATE_EZBARS = "nutzt schon %s",

    -- Kampfsperre über Core.CombatNotice („… kommt gleich nach dem Kampf.“, T18-1)
    APPLY_WHAT = "Das Einrichten der Leisten",
    CONFLICT_BLIZZARD = "%s nutzt dieselben Aktionsplätze wie %s (%d–%d). Beide zeigen dann dieselben Zauber.",
    CONFLICT_STANCE = "%s nutzt die Plätze %d–%d, die deine Klasse für Gestalt/Haltung braucht. Dort wechselt der Inhalt mit der Gestalt.",
    CONFLICT_BAR = "%s und %s teilen sich die Aktionsplätze %d–%d.",
    SHORT = "%s: %d Knöpfe eingestellt, aber nur %d Aktionsplätze frei – %d Felder bleiben leer. Mehr Platz: eine Blizzard-Leiste abschalten (in Blizzards Optionen unter „Aktionsleisten“), eine andere ezBars-Leiste verkleinern, unter „Aktionsplätze“ eine Seite von Hand wählen oder „Plätze neu wählen“ (/ezbars plaetze zeigt, was frei ist).",
    EMPTY_FIELD = "Kein Aktionsplatz frei",
    EMPTY_FIELD_TIP = "Für dieses Feld ist kein Aktionsplatz mehr frei (je Seite 12 Plätze; Blizzards sichtbare Leisten, die Gestalt-/Haltungsleisten deiner Klasse und die anderen ezBars-Leisten belegen den Rest). Mehr Platz: eine Blizzard-Leiste abschalten, eine andere Leiste verkleinern oder unter „Aktionsplätze“ eine Seite von Hand wählen. /ezbars plaetze zeigt, was frei ist.",
    GRID_MAX = "Höchstens %d Knöpfe – so viele Aktionsplätze sind für %s frei.",
    GRID_NOW = "Jetzt: %d × %d = %d Knöpfe.",
    GRID_OVER = "%d Felder bleiben leer (ohne Aktionsplatz).",
    TRIMMED = "%s: höchstens %d Knöpfe je Leiste – es werden %d von %d gezeigt.",
    REALLOCATED = "Aktionsplätze neu gewählt.",
    REALLOCATE_ASK = "Aktionsplätze für alle Leisten auf „Automatisch“ neu wählen? Die Leisten zeigen danach womöglich andere Plätze; die Zauber auf den alten Plätzen bleiben dort.",
    OTHER_BARS_ADDON = "%s läuft: ezBars ergänzt Blizzards Leisten, %s ersetzt sie. Achte darauf, dass keine Leiste von %s dieselben Aktionsplätze nutzt (/ezbars status).",
    -- %s = Weg zur Tastaturbelegung (Core.KeyBindPathText, T18-18)
    KEYBIND_FALLBACK = "%s Oder dort den „Schnelltastenbelegungsmodus“ wählen und mit der Maus auf den Knopf zeigen.",

    STATUS_BAR = "%s: %d × %d, Plätze %s%s",
    STATUS_AUTO = " (automatisch)",
    STATUS_EMPTY = ", %d |4Feld:Felder; ohne Aktionsplatz",
    STATUS_PENDING = "Wartet auf das Ende des Kampfes.",
    STATUS_NO_CONFLICTS = "Keine Überschneidungen.",
    STATUS_FREE_HEAD = "Aktionsplätze dieses Charakters:",

    -- Einstellungen
    OPT_KEYBIND = "Tastaturbelegung",
    OPT_KEYBIND_BUTTON = "Tasten belegen",
    OPT_KEYBIND_TIP = "Öffnet Blizzards Tastaturbelegung. Unter „AddOns » ezBars“ haben die ersten 24 Knöpfe jeder Leiste einen eigenen Eintrag, alle weiteren belegst du im Schnelltastenbelegungsmodus; oben im Fenster schaltet „Schnelltastenbelegungsmodus“ das Belegen per Mauszeiger ein (auf den Knopf zeigen, Taste drücken). Auch: /ezbars tasten.",

    OPT_HEADER_BARS = "Leisten",
    OPT_BAR_PAGE = "Leiste %d: Anordnung",
    OPT_BAR_PAGE_BUTTON = "Öffnen",
    OPT_BAR_PAGE_TIP = "Spalten, Reihen, Knopfgröße, Abstand, Sichtbarkeit, Aktionsplätze und Leisten-Profil dieser Leiste.",
    OPT_HEADER_LAYOUT = "Anordnung",
    OPT_HEADER_VISIBILITY = "Anzeige",
    OPT_HEADER_SLOTS = "Aktionsplätze",

    OPT_ON = "Leiste %d zeigen",
    OPT_ON_TIP = "Das bringt dir: eine zusätzliche Aktionsleiste im Blizzard-Stil, mit freier Anordnung (z. B. 2×2, 3×3, 4×4 oder 3×8) – das kann Blizzards Bearbeitungsmodus nicht. Anlegen und Ändern nur außerhalb des Kampfes.",
    OPT_COLS = "Spalten",
    OPT_COLS_TIP = "Knöpfe nebeneinander. Wie viele Knöpfe eine Leiste haben kann, hängt an den freien Aktionsplätzen (je Seite 12) – die Höchstzahl steht hier im Tooltip. Ist das Raster größer, bleiben die übrigen Felder leer.",
    OPT_ROWS = "Reihen",
    OPT_ROWS_TIP = "Knöpfe untereinander. Wie viele Knöpfe eine Leiste haben kann, hängt an den freien Aktionsplätzen (je Seite 12) – die Höchstzahl steht hier im Tooltip. Ist das Raster größer, bleiben die übrigen Felder leer.",
    OPT_SIZE = "Knopfgröße",
    OPT_SIZE_TIP = "Wie Blizzards „Symbolgröße“ im Bearbeitungsmodus: 100 % ist die Größe der Hauptleiste.",
    OPT_PADDING = "Abstand",
    OPT_PADDING_TIP = "Abstand zwischen den Knöpfen in Pixeln bei 100 % Knopfgröße (Blizzard: 2 bis 10); er wächst und schrumpft mit der Knopfgröße wie bei Blizzard.",
    OPT_SHOW = "Sichtbar",
    OPT_SHOW_TIP = "Wie Blizzards Einstellung „Leiste sichtbar“. In Fahrzeugen, beim Gedankenkontrollieren und in Haustierkämpfen blendet sich die Leiste wie Blizzards Leisten aus.",
    OPT_SHOW_ALWAYS = "Immer",
    OPT_SHOW_COMBAT = "Im Kampf",
    OPT_SHOW_NOCOMBAT = "Außerhalb des Kampfes",
    OPT_SHOW_HIDDEN = "Versteckt",
    OPT_EMPTY = "Leere Plätze zeigen",
    OPT_EMPTY_TIP = "Wie Blizzards „Knöpfe immer zeigen“. Aus: leere Plätze sind unsichtbar und erscheinen, sobald du einen Zauber ziehst oder Tasten belegst.",
    OPT_PAGE = "Aktionsplätze",
    OPT_PAGE_TIP = "Welche Aktionsplätze die Leiste zeigt (je Seite 12). „Automatisch“ nimmt Plätze, die weder eine sichtbare Blizzard-Leiste noch die Gestalt-/Haltungsleisten deiner Klasse nutzen, und merkt sie sich je Charakter. Mehr als 12 Knöpfe nutzen die nächste Seite mit.",

    OPT_SLOTS = "Freie Aktionsplätze",
    OPT_SLOTS_BUTTON = "Anzeigen",
    OPT_SLOTS_TIP = "Zeigt im Chat, welche Seiten der Aktionsplätze dieser Charakter noch frei hat und wer die anderen nutzt. Auch: /ezbars plaetze.",
    OPT_REALLOCATE = "Plätze neu wählen",
    OPT_REALLOCATE_BUTTON = "Neu wählen",
    OPT_REALLOCATE_TIP = "Wählt für alle Leisten auf „Automatisch“ die freien Aktionsplätze dieses Charakters neu – z. B. nachdem du eine Blizzard-Leiste eingeschaltet hast. Die Zauber auf den alten Plätzen bleiben dort.",
    OPT_STATUS_TIP = "Zeigt im Chat, welche Leiste welche Aktionsplätze nutzt und ob sie sich mit Blizzards Leisten überschneidet. Auch: /ezbars status.",
    -- Erklärblasen (Tour.lua); Knopf „Erklärung: Erneut zeigen“ kommt aus ezCore (page:TourButton)
    TOUR_BAR = "Das ist deine ezBars-Leiste: Zauber, Gegenstände und Makros hineinziehen – sie arbeitet wie Blizzards Leisten. Bis zu vier solcher Leisten schaltest du in den Einstellungen ein – %s",
    TOUR_LAYOUT = "Anordnung frei: Spalten, Reihen, Knopfgröße und Abstand stellst du je Leiste auf ihrer Seite „Leiste n: Anordnung“ ein – auch 2×2, 4×4 oder 3×8, was Blizzards Bearbeitungsmodus nicht kann. Dort auch „Sichtbar“ und „Leere Plätze zeigen“.",
    TOUR_MOVE = "Verschieben: Spielmenü (Esc) » Bearbeitungsmodus – jede eingeschaltete Leiste hat dort Blizzards blauen Rahmen, auch eine versteckte. Dieselben Rahmen zeigen der Knopf „Verschieben“ in den Einstellungen und /ezbars verschieben.",
    TOUR_KEYS = "Tasten belegen: Der Knopf „Tasten belegen“ in den Einstellungen (oder /ezbars tasten) öffnet Blizzards Tastaturbelegung; im Schnelltastenbelegungsmodus auf einen Knopf zeigen und die Taste drücken.",
    TOUR_SLOTS = "Aktionsplätze: ezBars nimmt Plätze, die keine sichtbare Blizzard-Leiste nutzt, und merkt sie je Charakter. Überschneidet sich etwas, meldet es der Chat – „Plätze neu wählen“ unter „Erweitert“ löst es; /ezbars status zeigt alles.",
    -- Leisten-Profile seit dem 22.11.2026 in ezCore, auch ohne ezMacro (Einführung nachgezogen am 23.11.2026)
    TOUR_PROFILE = "Leisten-Profil: Auf der Seite „Leiste n: Anordnung“ speichert „Als Profil speichern“ die Zauber, Makros und Gegenstände dieser Leiste. „Profil laden“ legt sie auf einem Twink in derselben Reihenfolge ab – nach einer Rückfrage, auch ohne ezMacro.",
    TOUR_RESET_TIP = "Zeigt die Erklärblasen an der Leiste wieder von vorn: was die Leiste ist, Anordnung, Verschieben, Tasten belegen, Aktionsplätze und Leisten-Profil. Sie erscheinen, sobald du eine Einstellung änderst, die Einstellungen über /ezbars öffnest oder dich neu einloggst.",
    -- Knopf „Einstellungen zurücksetzen“ kommt aus ezCore (page:ResetButton), nur der Tooltip ist eigen
    RESET_TIP = "Setzt alle Leisten auf den Standard (nur Leiste 1 an, 4 × 3; Leisten anderer Module auf die Werte ihres Moduls). Die Zauber auf den Aktionsplätzen, die gemerkten Plätze dieses Charakters und die Lage der Leisten bleiben.",

    -- Leisten-Profile (ezCores Dienst Core.BarProfiles, seit dem Architektur-Review 22.11.2026 auch ohne ezMacro): je
    -- Leiste ein Profil „ezBars: Leiste n“, auf jedem Charakter ladbar; die Übersicht aller Profile ist ezMacros Werkzeug
    OPT_HEADER_PROFILE = "Leisten-Profil",
    OPT_PROFILE_SAVE = "Als Profil speichern",
    OPT_PROFILE_SAVE_BUTTON = "Speichern",
    OPT_PROFILE_SAVE_TIP = "Das bringt dir: dieselbe Leiste auf jedem Twink mit einem Klick. Speichert die Zauber, Makros und Gegenstände dieser Leiste als Leisten-Profil „%s“ (ein gleichnamiges Profil wird ersetzt). Die Profile gelten für ezBars und ezMacros Werkzeug „Leisten-Profile“.",
    OPT_PROFILE_LOAD = "Profil laden",
    OPT_PROFILE_LOAD_BUTTON = "Laden",
    OPT_PROFILE_LOAD_TIP = "Legt das Profil „%s“ auf diese Leiste – Platz für Platz in derselben Reihenfolge, auch wenn die Leiste auf diesem Charakter andere Aktionsplätze nutzt. Fehlende Makros entstehen neu (die Rückfrage nennt sie; mit ezMacro nach dessen Häkchen „Fehlende Makros anlegen“). Es kommt vorher einmal eine Rückfrage. Nur außerhalb des Kampfes; belegte Tasten bleiben, wie sie sind.",
    OPT_PROFILES = "Alle Leisten-Profile",
    OPT_PROFILES_BUTTON = "ezMacro öffnen",
    OPT_PROFILES_TIP = "Öffnet ezMacros Werkzeug „Leisten-Profile“: alle gespeicherten Profile, auch die der ganzen Leisten, mit Löschen, Export und Import.",
    PROFILE_MISSING = "Kein Profil „%s“. Speichere die Leiste zuerst auf einem Charakter mit „Als Profil speichern“.",
    PROFILE_EMPTY = "%s hat keine Aktionsplätze – nichts zu speichern.",
    PROFILE_NO_MACRO = "Die Übersicht aller Leisten-Profile (Löschen, Als Text) gibt es mit ezMacro. Speichern und Laden je Leiste geht auch ohne.",

    -- Profile der Leisten-Einstellungen (ezCores Profil-Gerüst, Profiles.lua; Abschnitt aus page:Profiles). Nur, was
    -- von den Leisten spricht; Beschriftungen, Knöpfe und Meldungen mit demselben Wortlaut liefert ezCore (Rückfall).
    PROFILE_SECTION_TIP = "Ein Profil merkt sich alle Leisten-Einstellungen: welche Leisten an sind, Spalten, Reihen, Größe, Abstand, Sichtbarkeit und die Wahl der Aktionsplätze. Die Zauber auf den Plätzen und die Lage der Leisten gehören nicht dazu.",
    OPT_profile_TIP = "Das bringt dir: Dein Heiler hat andere Leisten als dein Krieger. Wähle hier, welches Profil dieser Charakter nutzt – die Leisten stellen sich sofort um (im Kampf gleich danach). Ein neues Profil beginnt als Kopie der jetzigen Einstellungen. Die Zauber auf den Plätzen bleiben, wo sie sind.",
    OPT_profileSpec_TIP = "An: Jede Spezialisierung dieses Charakters merkt sich ihr eigenes Profil; beim Umschalten wechseln die Leisten mit (im Kampf gleich danach).",
    OPT_PROFILE_NEW_TIP = "Fragt nach einem Namen, legt ein Profil mit den jetzigen Leisten-Einstellungen an und nutzt es für diesen Charakter.",
    OPT_PROFILE_EXPORT_TIP = "Zeigt das gewählte Profil als Text zum Kopieren (Strg+C) – für einen anderen Account oder zum Weitergeben.",
    OPT_PROFILE_IMPORT_TIP = "Text eines exportierten ezBars-Profils einfügen (Strg+V). Er wird ein neues Profil für diesen Charakter; dein jetziges bleibt erhalten.",
    STATUS_PROFILE = "Profil: %s",

    -- Leisten anderer Module (ns.RegisterBar): Knöpfe vom Anbieter, Anordnung und Lage von ezBars
    EXTRA_TITLE = "%s (%s)",
    EXTRA_MOVER_LABEL = "ezBars: %s",
    ANCHOR_free = "frei",
    ANCHOR_chatSide = "seitlich am Chat",
    ANCHOR_chatTop = "auf den Chat-Reitern",
    ANCHOR_custom = "am Platz des Moduls",
    ANCHOR_MOVED = "von dir verschoben",
    ANCHOR_FALLBACK = "frei (Standardplatz „%s“ nicht gefunden)",
    STATUS_EXTRA = "%s: %d × %d, zeigt %d von %d |4Knopf:Knöpfen;, %s",
    EXTRA_CUT = "%s: Das Modul liefert %d Knöpfe, das Raster %d × %d zeigt nur %d. Mehr Spalten oder Reihen stellst du auf der Seite der Leiste in den ezBars-Einstellungen ein (/ezbars).",
    EXTRA_GRID_NOW = "Jetzt: %d × %d = %d Felder für %d Knöpfe.",
    EXTRA_GRID_CUT = "%d Knöpfe passen nicht hinein und werden nicht gezeigt.",
    EXTRA_NONE = "Kein Modul hat eine Leiste angemeldet. Module wie ezMacro (Emote-Leisten) zeigen ihre Leisten über ezBars; sie erscheinen dann hier und in /ezbars status.",
    EXTRA_LIST_HEAD = "Leisten anderer Module (je eine eigene Seite links in der Liste unter ezBars):",
    OPT_EXTRA_LIST = "Leisten anderer Module",
    OPT_EXTRA_LIST_BUTTON = "Anzeigen",
    OPT_EXTRA_LIST_TIP = "Andere Module der ezCollection können ihre Knöpfe auf einer ezBars-Leiste zeigen (zum Beispiel ezMacro seine Emotes). Was auf den Knöpfen liegt, bestimmt das Modul; Spalten, Reihen, Knopfgröße, Abstand, Sichtbarkeit und Lage stellst du hier ein – jede dieser Leisten hat eine eigene Seite. Der Knopf öffnet die Seite bzw. zeigt die Auswahl.",
    OPT_EXTRA_COLS = "Spalten",
    OPT_EXTRA_COLS_TIP = "Knöpfe nebeneinander. Die Knöpfe liefert das Modul, dem die Leiste gehört. Liefert es mehr, als Spalten × Reihen fassen, zeigt die Leiste nur die ersten – die Zahlen stehen hier im Tooltip.",
    OPT_EXTRA_ROWS = "Reihen",
    OPT_EXTRA_ROWS_TIP = "Knöpfe untereinander. Die Knöpfe liefert das Modul, dem die Leiste gehört. Liefert es mehr, als Spalten × Reihen fassen, zeigt die Leiste nur die ersten – die Zahlen stehen hier im Tooltip.",
    OPT_EXTRA_SIZE = "Knopfgröße",
    OPT_EXTRA_SIZE_TIP = "100 % ist die Größe der Knöpfe auf Blizzards Hauptleiste. Symbol, Rahmen und Abstand wachsen gemeinsam.",
    OPT_EXTRA_PADDING = "Abstand",
    OPT_EXTRA_PADDING_TIP = "Abstand zwischen den Knöpfen in Pixeln bei 100 % Knopfgröße; er wächst und schrumpft mit der Knopfgröße.",
    OPT_EXTRA_SHOW = "Sichtbar",
    OPT_EXTRA_SHOW_TIP = "Wann die Leiste zu sehen ist: immer, nur im Kampf, nur außerhalb des Kampfes oder nie. Eine Änderung während des Kampfes gilt gleich danach. Alle Leisten eines Moduls schaltet das Modul selbst ab (etwa ezMacros „Emote-Leisten nutzen“).",
    OPT_EXTRA_HOME = "Standardplatz",
    OPT_EXTRA_HOME_BUTTON = "Zurücksetzen",
    OPT_EXTRA_HOME_TIP = "Setzt diese Leiste an ihren Standardplatz zurück (zum Beispiel an den Chat), wenn du sie verschoben hast. Verschieben: Knopf „Verschieben“ oder Blizzards Bearbeitungsmodus.",
    EXTRA_HOME_DONE = "%s steht wieder an ihrem Standardplatz.",
    EXTRA_HOME_LATER = "%s kommt gleich nach dem Kampf an ihren Standardplatz.",
    OPT_EXTRA_GONE = "Leiste gerade nicht angemeldet",
    OPT_EXTRA_GONE_BUTTON = "Erklären",
    OPT_EXTRA_GONE_TIP = "Das Modul, dem diese Leiste gehört, zeigt sie gerade nicht – es ist nicht geladen oder hat die Leiste abgeschaltet. Deshalb ändert sich auf dem Bildschirm nichts, wenn du hier etwas einstellst. Die Werte bleiben gespeichert und gelten, sobald das Modul die Leiste wieder zeigt. Der Knopf schreibt das in den Chat.",
    EXTRA_GONE = "%s ist gerade nicht angemeldet: Ihr Modul ist nicht geladen oder hat die Leiste abgeschaltet. Die Einstellungen auf ihrer Seite bleiben gespeichert und gelten, sobald das Modul sie wieder zeigt.",
}

local en = {
    INTRO_FEATURES = "Up to four extra bars, Blizzard buttons\nAny shape, from 2×2 to 12×12\nSize, visibility and keys per bar\nMove them in Edit Mode\nBar profiles, even without ezMacro",
    TITLE = "ezBars",
    CMD_HELP_OWN = {
        "  %s keys – open Blizzard's key bindings",
        "  %s move – move the bars (the same frames as in Edit Mode)",
        "  %s slots – free action slots of this character",
    },

    BAR_NAME = "Bar %d",
    BUTTON_NAME = "Bar %d, button %d",
    MOVER_LABEL = "ezBars: Bar %d",
    BINDING_HEADER = "ezBars (extra bars)",

    PAGE_AUTO = "Automatic (free slots)",
    PAGE_LABEL = "Slots %d–%d: %s",
    PAGE_2 = "Main bar, page 2 (Shift+mouse wheel)",
    PAGE_BLIZZARD = "Blizzard's Action Bar %d",
    PAGE_STANCE = "Stance/form bar %d",
    PAGE_STATE_FREE = "free",
    PAGE_STATE_BLIZZARD = "also shown by %s",
    PAGE_STATE_STANCE = "needed by your class for stances/forms",
    PAGE_STATE_EZBARS = "already used by %s",

    APPLY_WHAT = "Setting up the bars",
    CONFLICT_BLIZZARD = "%s uses the same action slots as %s (%d–%d). Both then show the same spells.",
    CONFLICT_STANCE = "%s uses slots %d–%d, which your class needs for stances/forms. Their content changes with the form.",
    CONFLICT_BAR = "%s and %s share action slots %d–%d.",
    SHORT = "%s: %d buttons set, but only %d action slots free – %d fields stay empty. More room: turn off a Blizzard bar (in Blizzard's options under \"Action Bars\"), shrink another ezBars bar, pick a page by hand under \"Action slots\" or \"Pick slots again\" (/ezbars slots shows what is free).",
    EMPTY_FIELD = "No free action slot",
    EMPTY_FIELD_TIP = "There is no free action slot left for this field (12 slots per page; Blizzard's visible bars, your class's stance/form bars and the other ezBars bars use the rest). More room: turn off a Blizzard bar, shrink another bar or pick a page by hand under \"Action slots\". /ezbars slots shows what is free.",
    GRID_MAX = "At most %d buttons – that many action slots are free for %s.",
    GRID_NOW = "Now: %d × %d = %d buttons.",
    GRID_OVER = "%d fields stay empty (no action slot).",
    TRIMMED = "%s: at most %d buttons per bar – showing %d of %d.",
    REALLOCATED = "Action slots picked again.",
    REALLOCATE_ASK = "Pick the action slots again for every bar set to \"Automatic\"? The bars may show other slots afterwards; spells on the old slots stay there.",
    OTHER_BARS_ADDON = "%s is running: ezBars adds to Blizzard's bars, %s replaces them. Make sure no %s bar uses the same action slots (/ezbars status).",
    KEYBIND_FALLBACK = "%s Or use \"Quick Keybind Mode\" there and point at the button.",

    STATUS_BAR = "%s: %d × %d, slots %s%s",
    STATUS_AUTO = " (automatic)",
    STATUS_EMPTY = ", %d |4field:fields; without an action slot",
    STATUS_PENDING = "Waiting for combat to end.",
    STATUS_NO_CONFLICTS = "No overlaps.",
    STATUS_FREE_HEAD = "Action slots of this character:",

    OPT_KEYBIND = "Key bindings",
    OPT_KEYBIND_BUTTON = "Bind keys",
    OPT_KEYBIND_TIP = "Opens Blizzard's key bindings. Under \"AddOns » ezBars\" the first 24 buttons of every bar have their own entry, bind all others in Quick Keybind Mode; \"Quick Keybind Mode\" at the top lets you bind by pointing at a button and pressing a key. Also: /ezbars keys.",

    OPT_HEADER_BARS = "Bars",
    OPT_BAR_PAGE = "Bar %d: layout",
    OPT_BAR_PAGE_BUTTON = "Open",
    OPT_BAR_PAGE_TIP = "Columns, rows, button size, spacing, visibility, action slots and bar profile of this bar.",
    OPT_HEADER_LAYOUT = "Layout",
    OPT_HEADER_VISIBILITY = "Display",
    OPT_HEADER_SLOTS = "Action slots",

    OPT_ON = "Show bar %d",
    OPT_ON_TIP = "What you get: an extra action bar in Blizzard's style with a free layout (e.g. 2×2, 3×3, 4×4 or 3×8) – something Blizzard's Edit Mode can't do. Created and changed only out of combat.",
    OPT_COLS = "Columns",
    OPT_COLS_TIP = "Buttons side by side. How many buttons a bar can have depends on the free action slots (12 per page) – the maximum is shown here in the tooltip. If the grid is bigger, the remaining fields stay empty.",
    OPT_ROWS = "Rows",
    OPT_ROWS_TIP = "Buttons stacked. How many buttons a bar can have depends on the free action slots (12 per page) – the maximum is shown here in the tooltip. If the grid is bigger, the remaining fields stay empty.",
    OPT_SIZE = "Button size",
    OPT_SIZE_TIP = "Like Blizzard's \"Icon Size\" in Edit Mode: 100% is the size of the main bar.",
    OPT_PADDING = "Spacing",
    OPT_PADDING_TIP = "Space between buttons in pixels at 100% button size (Blizzard: 2 to 10); it grows and shrinks with the button size, as in Blizzard's bars.",
    OPT_SHOW = "Visible",
    OPT_SHOW_TIP = "Like Blizzard's \"Bar Visible\" setting. In vehicles, while mind controlling and in pet battles the bar hides like Blizzard's bars.",
    OPT_SHOW_ALWAYS = "Always",
    OPT_SHOW_COMBAT = "In combat",
    OPT_SHOW_NOCOMBAT = "Out of combat",
    OPT_SHOW_HIDDEN = "Hidden",
    OPT_EMPTY = "Show empty slots",
    OPT_EMPTY_TIP = "Like Blizzard's \"Always Show Buttons\". Off: empty slots are invisible and appear while you drag a spell or bind keys.",
    OPT_PAGE = "Action slots",
    OPT_PAGE_TIP = "Which action slots the bar shows (12 per page). \"Automatic\" takes slots that neither a visible Blizzard bar nor your class's stance/form bars use and remembers them per character. More than 12 buttons also use the next page.",

    OPT_SLOTS = "Free action slots",
    OPT_SLOTS_BUTTON = "Show",
    OPT_SLOTS_TIP = "Prints which pages of action slots this character still has free and who uses the others. Also: /ezbars slots.",
    OPT_REALLOCATE = "Pick slots again",
    OPT_REALLOCATE_BUTTON = "Pick again",
    OPT_REALLOCATE_TIP = "Picks the free action slots of this character again for every bar set to \"Automatic\" – e.g. after you turned on a Blizzard bar. Spells on the old slots stay there.",
    OPT_STATUS_TIP = "Prints which bar uses which action slots and whether it overlaps with Blizzard's bars. Also: /ezbars status.",
    TOUR_BAR = "This is your ezBars bar: drag spells, items and macros onto it – it works like Blizzard's bars. Turn on up to four of these bars in the settings – %s",
    TOUR_LAYOUT = "Free layout: set columns, rows, button size and spacing per bar on its page \"Bar n: layout\" – even 2×2, 4×4 or 3×8, which Blizzard's Edit Mode can't do. \"Visible\" and \"Show empty slots\" are there too.",
    TOUR_MOVE = "Moving: game menu (Esc) » Edit Mode – every bar that is turned on has Blizzard's blue frame there, even a hidden one. The \"Move\" button in the settings and /ezbars move show the same frames.",
    TOUR_KEYS = "Key bindings: the \"Bind keys\" button in the settings (or /ezbars keys) opens Blizzard's key bindings; in Quick Keybind Mode point at a button and press the key.",
    TOUR_SLOTS = "Action slots: ezBars takes slots no visible Blizzard bar uses and remembers them per character. If something overlaps, the chat says so – \"Pick slots again\" under \"Advanced\" fixes it; /ezbars status shows everything.",
    TOUR_PROFILE = "Bar profile: on the page \"Bar n: layout\", \"Save as profile\" stores the spells, macros and items of this bar. \"Load profile\" puts them on an alt in the same order – after a confirmation, even without ezMacro.",
    TOUR_RESET_TIP = "Shows the help bubbles at the bar again from the start: what the bar is, layout, moving, key bindings, action slots and bar profile. They appear as soon as you change a setting, open the settings with /ezbars or log in again.",
    RESET_TIP = "Resets every bar to the default (only bar 1 on, 4 × 3; bars of other modules to their module's values). Spells on the action slots, this character's remembered slots and the bar positions stay.",

    OPT_HEADER_PROFILE = "Bar profile",
    OPT_PROFILE_SAVE = "Save as profile",
    OPT_PROFILE_SAVE_BUTTON = "Save",
    OPT_PROFILE_SAVE_TIP = "What you get: the same bar on every alt with one click. Saves the spells, macros and items of this bar as the bar profile \"%s\" (a profile of the same name is replaced). The profiles apply to ezBars and to ezMacro's tool \"Bar profiles\".",
    OPT_PROFILE_LOAD = "Load profile",
    OPT_PROFILE_LOAD_BUTTON = "Load",
    OPT_PROFILE_LOAD_TIP = "Puts the profile \"%s\" on this bar – slot by slot in the same order, even if the bar uses other action slots on this character. Missing macros are created (the confirmation lists them; with ezMacro following its checkbox \"Create missing macros\"). You are asked once first. Only out of combat; key bindings stay as they are.",
    OPT_PROFILES = "All bar profiles",
    OPT_PROFILES_BUTTON = "Open ezMacro",
    OPT_PROFILES_TIP = "Opens ezMacro's tool \"Bar profiles\": every saved profile, including whole-bar profiles, with delete, export and import.",
    PROFILE_MISSING = "No profile \"%s\". Save the bar on a character first with \"Save as profile\".",
    PROFILE_EMPTY = "%s has no action slots – nothing to save.",
    PROFILE_NO_MACRO = "The overview of all bar profiles (delete, as text) comes with ezMacro. Saving and loading per bar works without it.",

    PROFILE_SECTION_TIP = "A profile remembers every bar setting: which bars are on, columns, rows, size, spacing, visibility and the choice of action slots. The spells on the slots and the bar positions are not part of it.",
    OPT_profile_TIP = "What you get: your healer has other bars than your warrior. Choose which profile this character uses – the bars change at once (in combat right after it). A new profile starts as a copy of the current settings. The spells on the slots stay where they are.",
    OPT_profileSpec_TIP = "On: each specialization of this character remembers its own profile; the bars switch along when you change it (in combat right after it).",
    OPT_PROFILE_NEW_TIP = "Asks for a name, creates a profile from the current bar settings and uses it for this character.",
    OPT_PROFILE_EXPORT_TIP = "Shows the selected profile as text to copy (Ctrl+C) – for another account or to pass on.",
    OPT_PROFILE_IMPORT_TIP = "Paste the text of an exported ezBars profile (Ctrl+V). It becomes a new profile for this character; your current one stays.",
    STATUS_PROFILE = "Profile: %s",

    EXTRA_TITLE = "%s (%s)",
    EXTRA_MOVER_LABEL = "ezBars: %s",
    ANCHOR_free = "free",
    ANCHOR_chatSide = "beside the chat",
    ANCHOR_chatTop = "on the chat tabs",
    ANCHOR_custom = "at the module's place",
    ANCHOR_MOVED = "moved by you",
    ANCHOR_FALLBACK = "free (default place \"%s\" not found)",
    STATUS_EXTRA = "%s: %d × %d, showing %d of %d |4button:buttons;, %s",
    EXTRA_CUT = "%s: the module provides %d buttons, the %d × %d grid shows only %d. Set more columns or rows on the bar's page in the ezBars settings (/ezbars).",
    EXTRA_GRID_NOW = "Now: %d × %d = %d fields for %d buttons.",
    EXTRA_GRID_CUT = "%d buttons do not fit and are not shown.",
    EXTRA_NONE = "No module has registered a bar. Modules like ezMacro (emote bars) show their bars through ezBars; they then appear here and in /ezbars status.",
    EXTRA_LIST_HEAD = "Bars of other modules (each has its own page in the list on the left under ezBars):",
    OPT_EXTRA_LIST = "Bars of other modules",
    OPT_EXTRA_LIST_BUTTON = "Show",
    OPT_EXTRA_LIST_TIP = "Other ezCollection modules can show their buttons on an ezBars bar (for example ezMacro its emotes). The module decides what is on the buttons; columns, rows, button size, spacing, visibility and position are set here – each of these bars has its own page. The button opens the page or shows the choice.",
    OPT_EXTRA_COLS = "Columns",
    OPT_EXTRA_COLS_TIP = "Buttons side by side. The buttons come from the module that owns the bar. If it provides more than columns × rows can hold, the bar shows only the first ones – the numbers are shown here in the tooltip.",
    OPT_EXTRA_ROWS = "Rows",
    OPT_EXTRA_ROWS_TIP = "Buttons stacked. The buttons come from the module that owns the bar. If it provides more than columns × rows can hold, the bar shows only the first ones – the numbers are shown here in the tooltip.",
    OPT_EXTRA_SIZE = "Button size",
    OPT_EXTRA_SIZE_TIP = "100% is the size of the buttons on Blizzard's main bar. Icon, frame and spacing grow together.",
    OPT_EXTRA_PADDING = "Spacing",
    OPT_EXTRA_PADDING_TIP = "Space between buttons in pixels at 100% button size; it grows and shrinks with the button size.",
    OPT_EXTRA_SHOW = "Visible",
    OPT_EXTRA_SHOW_TIP = "When the bar is visible: always, only in combat, only out of combat or never. A change during combat applies right after it. All bars of a module are turned off in that module (such as ezMacro's \"Use emote bars\").",
    OPT_EXTRA_HOME = "Default place",
    OPT_EXTRA_HOME_BUTTON = "Reset",
    OPT_EXTRA_HOME_TIP = "Puts this bar back at its default place (for example at the chat) if you moved it. Moving: the \"Move\" button or Blizzard's Edit Mode.",
    EXTRA_HOME_DONE = "%s is back at its default place.",
    EXTRA_HOME_LATER = "%s will return to its default place right after combat.",
    OPT_EXTRA_GONE = "Bar currently not registered",
    OPT_EXTRA_GONE_BUTTON = "Explain",
    OPT_EXTRA_GONE_TIP = "The module that owns this bar is not showing it right now – it is not loaded or has switched the bar off. That is why nothing changes on screen when you change a setting here. The values stay saved and apply as soon as the module shows the bar again. The button writes this to the chat.",
    EXTRA_GONE = "%s is not registered right now: its module is not loaded or has switched the bar off. The settings on its page stay saved and apply as soon as the module shows it again.",
}

-- Die Einstellungen jeder Leiste heißen bar<n><Name> (z. B. bar2Cols); ihre Texte sind für alle Leisten gleich.
ns.MAX_BARS = 4
ns.BAR_KEYS = { "On", "Cols", "Rows", "Size", "Padding", "Show", "Empty", "Page" }
for _, tbl in ipairs({ de, en }) do
    for n = 1, ns.MAX_BARS do
        for _, name in ipairs(ns.BAR_KEYS) do
            local generic = "OPT_" .. name:upper()
            tbl["OPT_bar" .. n .. name] = name == "On" and tbl[generic]:format(n) or tbl[generic]
            tbl["OPT_bar" .. n .. name .. "_TIP"] = tbl[generic .. "_TIP"]
        end
    end
end

ns.isGerman = ezCore.IsGerman()
ns.L = ezCore.NewLocale(de, en, ezCore.L)
ns.LOCALES = { de = de, en = en }    -- für die Tests: beide Sprachen gleich vollständig

-- Knöpfe je Leiste: höchstens 12 × 12 (so weit reichen die Schieberegler). Die echte Grenze sind die freien
-- Aktionsplätze dieses Charakters (Slots.FreeButtons); Felder ohne Platz bleiben leer (Bars.lua).
ns.MAX_BUTTONS = 144
-- Einträge in Blizzards Tastaturbelegung (Bindings.xml) je Leiste: die ersten 24 Knöpfe. Weitere Knöpfe belegt
-- Blizzards Schnelltastenbelegungsmodus (er bindet jeden „CLICK …“-Befehl über SetBinding, auch ohne Eintrag).
ns.BOUND_BUTTONS = 24

-- Namen in Blizzards Tastaturbelegung und im Schnelltastenbelegungsmodus (GetBindingName); WoW sucht sie in
-- diesen globalen Variablen.
BINDING_HEADER_EZBARS = ns.L.BINDING_HEADER
for n = 1, ns.MAX_BARS do
    for i = 1, ns.MAX_BUTTONS do
        _G[("BINDING_NAME_CLICK ezBarsBar%dButton%d:LeftButton"):format(n, i)] = ns.L.BUTTON_NAME:format(n, i)
    end
end
