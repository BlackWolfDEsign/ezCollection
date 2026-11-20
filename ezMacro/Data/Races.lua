local _, ns = ...

-- Volks-Makros: Volksfähigkeiten des Classic-Inhalts, sinnvoll kombiniert.
-- class = nur für diese Klasse (Volks-Klassenzauber wie Furchtzauberschutz).
-- Herkunft und Quelle der Zauber-IDs wie in Data\Classes.lua (Dateikopf dort): eigene Texte in eigener Form, nichts
-- aus fremden Addons; IDs sind Fakten aus Blizzards Client, am 14.11.2026 gegen Wowheads Forever-Tooltip geprüft
-- (Beleg: docs/roadmap/ezMacro.md, „Herkunft der Bestandsvorlagen“).

ns.AddMacros("race", "Human", {
    {
        id = "human_perception",
        name = { "Wahrnehmung", "Perception" },
        desc = { "Erhöht 20 s lang deine Entdeckung von Verstohlenheit – gegen Schurken und schleichende Druiden.",
                 "Raises your stealth detection for 20 sec – against rogues and prowling druids." },
        why = { "Du siehst 20 Sekunden lang schleichende Schurken und Druiden leichter – gut gegen Überfälle.",
                "For 20 seconds you spot sneaking rogues and prowling druids more easily – good against ambushes." },
        body = "#showtooltip\n/cast {s:20600}",
    },
    -- Verzweifeltes Gebet gibt es hier nicht: 13908 und seine Ränge stehen laut Client nur Zwergen offen
    -- (SkillLineAbility.RaceMask 4, ClientTables.classSpells; wago.tools, wowf 1.60.1.70938). Die Vorlage
    -- „human_desperate“ entfiel nach der Volksprüfung der wago-Prüfung (Gesamtreview 18.11.2026, T14-1);
    -- „dwarf_desperate“ bleibt.
})

ns.AddMacros("race", "Dwarf", {
    {
        id = "dwarf_stoneform",
        name = { "Steingestalt", "Stoneform" },
        desc = { "Bricht einen laufenden Zauber ab und wirkt Steingestalt: entfernt Gift, Krankheit und Blutungen und erhöht die Rüstung.",
                 "Stops your current cast and uses Stoneform: removes poison, disease and bleeds and raises armor." },
        why = { "Steingestalt entfernt Gift, Krankheit und Blutungen und erhöht die Rüstung – stark gegen Schurken.",
                "Stoneform removes poison, disease and bleeds and raises armor – strong against rogues." },
        body = "#showtooltip\n/stopcasting\n/cast {s:20594}",
    },
    {
        id = "dwarf_treasure",
        name = { "Schatzsuche", "Find Treasure" },
        desc = { "Zeigt Schätze auf der Minikarte an.",
                 "Shows treasure on the minimap." },
        why = { "Zeigt Schätze auf der Minikarte – praktisch, wenn du beim Erkunden Truhen suchst.",
                "Shows treasure on the minimap – handy when you look for chests while exploring." },
        body = "#showtooltip\n/cast {s:2481}",
    },
    {
        id = "dwarf_fearward",
        name = { "Furchtschutz MO", "Fear Ward (MO)" },
        desc = { "Furchtzauberschutz (Priester) auf den Spieler unter der Maus, sonst aufs freundliche Ziel, sonst auf dich – z. B. auf den Tank.",
                 "Fear Ward (priest) on the player under your mouse, otherwise your friendly target, otherwise you – e.g. on the tank." },
        why = { "Furchtzauberschutz auf den Tank, ohne dein Ziel zu wechseln: Maus auf ihn, Taste drücken.",
                "Fear Ward on the tank without changing your target: point your mouse at him, press the key." },
        without = { "Tank anklicken, Furchtzauberschutz wirken, dann deinen Gegner wieder ins Ziel nehmen.",
                    "Click the tank, cast Fear Ward, then target your enemy again." },
        rec = true,
        body = "#showtooltip\n/cast [@mouseover,help,nodead][help,nodead][@player] {s:6346}",
        class = "PRIEST",
    },
    {
        id = "dwarf_desperate",
        name = { "Verzw. Gebet", "Desperate Pray" },
        desc = { "Verzweifeltes Gebet (Priester): heilt dich sofort, auch mitten in einem anderen Zauber.",
                 "Desperate Prayer (priest): heals you instantly, even in the middle of another cast." },
        why = { "Verzweifeltes Gebet heilt dich sofort, auch mitten in einem anderen Zauber – rettet dich in Not.",
                "Desperate Prayer heals you instantly, even mid-cast – saves you when you are about to die." },
        without = { "Laufenden Zauber erst abbrechen (Esc oder Schritt), dann Verzweifeltes Gebet drücken.",
                    "Cancel your current cast first (Esc or a step), then press Desperate Prayer." },
        rec = true,
        body = "#showtooltip\n/stopcasting\n/cast {s:13908}",
        class = "PRIEST",
    },
})

ns.AddMacros("race", "NightElf", {
    {
        id = "nightelf_shadowmeld",
        name = { "Schattenmimik", "Shadowmeld" },
        desc = { "Hört auf anzugreifen, ruft dein Tier zu dir und verschmilzt mit den Schatten. Funktioniert, solange du stillstehst.",
                 "Stops attacking, calls your pet to you and melds into the shadows. Works while you stand still." },
        why = { "Versteckt dich, solange du stillstehst; der Angriff stoppt und dein Tier kommt zu dir.",
                "Hides you while you stand still; attacking stops and your pet comes back to you." },
        body = "#showtooltip\n/stopattack\n/petfollow\n/cast {s:20580}",
    },
})

ns.AddMacros("race", "Gnome", {
    {
        id = "gnome_escape",
        name = { "Entfesseln", "Escape Artist" },
        desc = { "Befreit dich von Verlangsamungen und Bewegungsunfähigkeit – bricht dafür einen laufenden Zauber ab.",
                 "Frees you from slows and roots – stops your current cast to do so." },
        why = { "Befreit dich, wenn du verlangsamt oder festgehalten wirst – auch mitten in einem Zauber.",
                "Frees you when you are slowed or rooted – even in the middle of a cast." },
        body = "#showtooltip\n/stopcasting\n/cast {s:20589}",
    },
})

ns.AddMacros("race", "Orc", {
    {
        id = "orc_bloodfury",
        name = { "Kochendes Blut", "Blood Fury" },
        desc = { "Kochendes Blut zusammen mit beiden Schmuckstücken, sofern sie benutzbar sind.",
                 "Blood Fury together with both trinkets, if they can be used." },
        why = { "Kochendes Blut und beide Schmuckstücke mit einem Tastendruck – so vergisst du keins davon.",
                "Blood Fury and both trinkets with one key press – so you never forget one of them." },
        without = { "Kochendes Blut und beide Schmuckstücke einzeln drücken – drei Tasten statt einer.",
                    "Press Blood Fury and each trinket separately – three keys instead of one." },
        rec = true,
        body = "#showtooltip {s:20572}\n/cast {s:20572}\n/use 13\n/use 14",
    },
})

ns.AddMacros("race", "Scourge", {
    {
        id = "undead_wotf",
        name = { "Wille d. Verl.", "Will Forsaken" },
        desc = { "Wirkt Wille der Verlassenen: befreit dich von Furcht, Bezauberung und Schlaf.",
                 "Uses Will of the Forsaken: frees you from fear, charm and sleep." },
        why = { "Spart nur einen Platz in der Leiste: dein Notknopf gegen Furcht, Bezauberung und Schlaf.",
                "Only saves a bar slot: your panic button against fear, charm and sleep." },
        body = "#showtooltip\n/cast {s:7744}",
    },
    {
        id = "undead_cannibalize",
        name = { "Kannibalismus", "Cannibalize" },
        desc = { "Frisst eine humanoide oder untote Leiche in der Nähe und heilt dich.",
                 "Eats a nearby humanoid or undead corpse to heal you." },
        why = { "Heilt dich an einer menschenähnlichen oder untoten Leiche – spart dir Essen nach dem Kampf.",
                "Heals you by eating a humanoid or undead corpse – saves food after a fight." },
        body = "#showtooltip\n/cast {s:20577}",
    },
})

ns.AddMacros("race", "Tauren", {
    {
        id = "tauren_warstomp",
        name = { "Kriegsdonner", "War Stomp" },
        desc = { "Betäubt Gegner um dich herum – bricht dafür einen laufenden Zauber ab.",
                 "Stuns enemies around you – stops your current cast to do so." },
        why = { "Kriegsdonner betäubt Gegner um dich, auch mitten im Zauber – verschafft dir sofort Luft.",
                "War Stomp stuns enemies around you, even mid-cast – buys you breathing room right away." },
        without = { "Erst den Zauber abbrechen (Esc oder Schritt) oder abwarten, dann Kriegsdonner drücken.",
                    "Cancel your cast first (Esc or a step) or wait for it, then press War Stomp." },
        rec = true,
        body = "#showtooltip\n/stopcasting\n/cast {s:20549}",
    },
})

ns.AddMacros("race", "Troll", {
    {
        id = "troll_berserking",
        name = { "Berserker", "Berserking" },
        desc = { "Berserker zusammen mit beiden Schmuckstücken, sofern sie benutzbar sind.",
                 "Berserking together with both trinkets, if they can be used." },
        why = { "Berserker und beide Schmuckstücke mit einem Tastendruck – so vergisst du keins davon.",
                "Berserking and both trinkets with one key press – so you never forget one of them." },
        without = { "Berserker und beide Schmuckstücke einzeln drücken – drei Tasten statt einer.",
                    "Press Berserking and each trinket separately – three keys instead of one." },
        rec = true,
        body = "#showtooltip {s:20554}\n/cast {s:20554}\n/use 13\n/use 14",
    },
})
