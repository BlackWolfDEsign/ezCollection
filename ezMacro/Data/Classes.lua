local _, ns = ...

-- Klassen-Makros für den Classic-Inhalt von WoW Forever.
-- Regeln: jeder Tastendruck löst höchstens eine Aktion mit globaler Abklingzeit aus,
-- /castsequence schaltet nur bei jedem Druck einen Schritt weiter – nichts läuft automatisch.
-- (MO) = Mouseover: wirkt auf die Einheit unter der Maus, sonst auf das Ziel.
-- (F)  = Fokus: wirkt auf deinen Fokus, sonst auf das Ziel.
--
-- Herkunft (MACRO-28, belegt am 14.11.2026 in docs/roadmap/ezMacro.md, „Herkunft der Bestandsvorlagen“): Alle
-- Vorlagen sind eigene Texte in eigener Form – Name, Beschreibung, Nutzen und „ohne dieses Makro“ zweisprachig, der
-- Makrotext als Vorlage mit Platzhaltern ({s:ID} statt Zaubernamen). Nichts stammt aus einem fremden Addon
-- (Leitlinie 10); die Abgleiche mit anderen Makro-Addons betrafen Funktionen, keine Daten.
-- Quelle der Zauber-IDs: Fakten aus Blizzards Client (klassische Rang-1-IDs). Im Spiel nennt der Client den Namen
-- (ns.SpellName), „/ezmacro pruefen“ meldet jede ID, die er nicht kennt. Alle IDs der Vorlagen (Klasse, Volk,
-- Allgemein) sind am 14.11.2026 mit ID und Name gegen Wowheads Forever-Tooltip geprüft
-- (nether.wowhead.com/forever/tooltip/spell/<ID>, deutsch und englisch); Abweichungen stehen in der Moduldatei.
-- Diese Prüfung gilt für die Vorlagen bis Welle 8. Vorlagen mit logic = <Schlüssel> (Welle 9) nehmen ihre IDs aus
-- ezCore/MacroLogic.lua, deren Quelle dort im Dateikopf steht; neu kamen so 3044 Arkaner Schuss (Arcane Shot) und
-- 689 Blutsauger (Drain Life) dazu – klassische Rang-1-IDs, Ersatznamen in ezCore/SpellData.lua (Welle 8), nicht
-- gegen Wowhead nachgeprüft. Ob Forever sie kennt, melden „/ez test“ und „/ezmacro pruefen“.
--
-- Quelle der Zauber-IDs, die mit Welle 2b dazukamen: nur die Fakten ID und Name, geprüft am 14.11.2026 über Wowheads
-- Forever-Tooltip nether.wowhead.com/forever/tooltip/spell/<ID>; im Spiel liefert der Client den Namen (ns.SpellName).
-- Ersatznamen führt ezCore/SpellData.lua seit Welle 4 für 676, 5019, 5487 und 9634 (MACRO-17).
--   676    Entwaffnen (Disarm), Krieger
--   5019   Schießen (Shoot), Zauberstab
--   5487   Bärengestalt (Bear Form), Druide
--   9634   Terrorbärengestalt (Dire Bear Form), Druide
-- 50769 Wiederbeleben (Druide) stand bis Welle 24 als Wahl in druid_rebirth; der Forever-Tooltip kennt die ID nicht
-- (404), und ezCores Tabelle der Zaubernamen führt sie nicht. Seit Welle 24 (A3) liest druid_rebirth die Makro-Logik
-- DRUID.rebirth aus ezCore (nur Wiedergeburt, 20484); 50769 steht in keiner Vorlage mehr.
--
-- Welle 27 (Paket modul/ezmacro-faehigkeiten; Frage des Nutzers vom 16.11.2026, warum es kein Feuerbrand-Makro gibt,
-- aber Verderbnis und Pein – Antwort auf „Lücken füllen?“: „Ja, beides“): Die Vorlagen sind je Klasse gegen ezCores
-- Client-Tabellen abgeglichen – Klassenzauber ezCore/Wissen/Client/ClassSpells.lua, ihre Art (Unterbrechen, Kontrolle,
-- Schaden über Zeit) ezCore/Wissen/Client/SpellKinds.lua, beide laut wago.tools, Produkt wowf, Build 1.60.1.70938.
-- Jeder solche Zauber hat eine Vorlage oder steht mit Grund in ns.NO_TEMPLATE (unten; Tests/vorlagen27.lua hält das
-- fest); Zauber ohne Vorlage bietet ezMacro als „Aus deinen Fähigkeiten“ an (SpellMacros.lua). Neue IDs sind die
-- Grund-IDs (Rang 1) dieser Tabellen, die Namen nennt der Client (deutsch und englisch laut SpellName der Tabellen);
-- nicht gegen Wowhead nachgeprüft. Lernzauber für den Begleiter des Jägers zählen nicht (Art „pet“). Ersatznamen
-- führt ezCore/Wissen/SpellData.lua für alle 18 IDs seit dem Paket modul/ezmacro-reste (17.11.2026, Namen laut
-- SpellName enUS und deDE derselben Tabellen).
--   348    Feuerbrand (Immolate), Hexenmeister
--   702    Fluch der Schwäche (Curse of Weakness), Hexenmeister
--   704    Fluch der Tollkühnheit (Curse of Recklessness), Hexenmeister
--   1714   Fluch der Sprachen (Curse of Tongues), Hexenmeister
--   440892 Fluch der Elemente (Curse of the Elements), Hexenmeister
--   18265  Lebensentzug (Siphon Life), Hexenmeister, Talent
--   603    Omen der Verdammnis (Bane of Doom), Hexenmeister
--   1120   Seelendieb (Drain Soul), Hexenmeister
--   2944   Verschlingende Seuche (Devouring Plague), Priester
--   14914  Heiliges Feuer (Holy Fire), Priester
--   15407  Gedankenschinden (Mind Flay), Priester, Talent
--   8050   Flammenschock (Flame Shock), Schamane
--   1978   Schlangenbiss (Serpent Sting), Jäger
--   1513   Wildtier ängstigen (Scare Beast), Jäger
--   772    Verwunden (Rend), Krieger
--   2878   Untote vertreiben (Turn Undead), Paladin
--   20066  Buße (Repentance), Paladin, Talent
--   5570   Insektenschwarm (Insect Swarm), Druide, Talent
-- 15487 Stille (Silence, Priester) führt ezCore/SpellData.lua schon mit Ersatznamen.

-- Zauberstab ohne Abbrechen (Priester, Magier, Hexenmeister; Welle 2b, eigener Text): „!“ schaltet das Schießen nur ein, nie aus; [nochanneling] lässt einen kanalisierten Zauber weiterlaufen.
local function Wand(class)
    return {
        id = class .. "_wand",
        name = { "Zauberstab", "Wand" },
        desc = { "Schießt mit dem Zauberstab. Erneut drücken bricht das Schießen nicht ab, und ein kanalisierter Zauber läuft weiter.",
                 "Shoots your wand. Pressing again does not stop shooting, and a channelled spell keeps going." },
        why = { "Zauberstab auf einer Taste, die du gefahrlos mehrfach drücken kannst.",
                "Wand on a key you can safely press again and again." },
        body = "#showtooltip {s:5019}\n/cast [nochanneling] !{s:5019}",
    }
end

-- Makro-Logik aus ezCores Klassen-Wissen (UE-26; ezCore/MacroLogic.lua führt je Klasse nur Zauber-IDs und
-- Bedingungen, die Quelle steht dort im Dateikopf). Eine Vorlage mit logic = <Schlüssel> nimmt ihre /cast-Zeile samt
-- Zielkette und Vorzeilen (/petattack, /stopcasting …) von dort; eigen bleiben Name, Texte, #showtooltip und
-- Zusatzzeilen danach. Namen, Ränge und Dauern liefert wie bisher der Client ({s:ID}, ns.Resolve).
-- Umgestellt sind nur Vorlagen, deren Text ezCores Logik zeichengleich ergibt – übernommene Makros und gespeicherte
-- Anpassungen bleiben so, wie sie sind (Tests/welle9.lua hält das fest). Wo ezCores Logik vom eigenen Text abweicht,
-- bleibt der eigene Text; der Unterschied steht in docs/roadmap/ezMacro.md („Klassen-Wissen“).
local Core = ezCore
local PRE_LINES = { startattack = "/startattack", stopcasting = "/stopcasting", cancelform = "/cancelform",
    trinkets = "/use 13\n/use 14" }

-- Eintrag der Makro-Logik einer Klasse (Kopie aus ezCore) oder nil.
function ns.LogicEntry(class, key)
    local Spells = Core and Core.Spells
    if not (Spells and type(Spells.MacroLogic) == "function") then return nil end
    for _, entry in ipairs(Spells.MacroLogic(class)) do
        if entry.key == key then return entry end
    end
    return nil
end

-- Makrotext einer Vorlage aus der Makro-Logik: { tip = Zauber-ID hinter #showtooltip, before = Zeilen vor /cast
-- (nach den Vorzeilen der Logik, z. B. Schmuckstücke), after = Zeilen danach, steps = { [n] = Angaben für Schritt n }
-- (an Spells.MacroCast, z. B. { short = true }: ezCores Kurzform „@mouseover,exists,noharm“ nur in diesem Schritt) }.
-- Den Zauber-Teil der /cast-Zeile baut ezCore (Spells.MacroCast, Welle 23: samt „ohne Ziel“, „!“ und „Taste erzwingt“).
-- nil, wenn ezCore die Logik nicht führt oder sie etwas enthält, das ezMacro nicht schreiben kann (lieber keine
-- Vorlage als eine halbe).
function ns.LogicBody(class, key, opts)
    local entry = ns.LogicEntry(class, key)
    local Condition = entry and Core.Spells.MacroCondition
    local Cast = entry and Core.Spells.MacroCast
    if not (entry and type(Condition) == "function" and type(Cast) == "function" and type(entry.steps) == "table"
        and #entry.steps > 0) then
        return nil
    end
    opts = opts or {}
    local lines = { opts.tip and ("#showtooltip {s:%d}"):format(opts.tip) or "#showtooltip" }
    for _, pre in ipairs(type(entry.pre) == "table" and entry.pre or {}) do
        if pre == "petattack" then
            local cond = Condition(nil, entry.unit, entry.chain, entry.kind)
            lines[#lines + 1] = cond ~= "" and ("/petattack " .. cond) or "/petattack"
        elseif PRE_LINES[pre] then
            lines[#lines + 1] = PRE_LINES[pre]
        else
            return nil
        end
    end
    if opts.before then lines[#lines + 1] = opts.before end
    local cast
    if type(opts.steps) == "table" then
        -- je Schritt eigene Angaben: Schritt für Schritt bauen (Zielkette und Art bleiben die des Eintrags)
        local parts = {}
        for index, step in ipairs(entry.steps) do
            parts[index] = Cast({ steps = { step }, unit = entry.unit, chain = entry.chain, kind = entry.kind },
                opts.steps[index])
            if not parts[index] then return nil end
        end
        cast = table.concat(parts, "; ")
    else
        cast = Cast(entry)
    end
    if type(cast) ~= "string" then return nil end
    lines[#lines + 1] = "/cast " .. cast
    if opts.after then lines[#lines + 1] = opts.after end
    return table.concat(lines, "\n")
end
local Logic = ns.LogicBody

ns.AddMacros("class", "WARRIOR", {
    {
        id = "warrior_charge",
        name = { "Ansturm", "Charge" },
        desc = { "Kampfhaltung: Sturmangriff. Berserkerhaltung: Abfangen. In der Verteidigungshaltung wechselt es in die Kampfhaltung.",
                 "Battle Stance: Charge. Berserker Stance: Intercept. In Defensive Stance it switches to Battle Stance." },
        why = { "Ein Knopf, um zum Gegner zu stürmen – egal in welcher Haltung du gerade bist.",
                "One key to rush at the enemy – no matter which stance you are in." },
        without = { "Erst Haltung wechseln, dann Sturmangriff oder Abfangen drücken – zwei Tasten.",
                    "Switch stance first, then press Charge or Intercept – two different keys." },
        rec = true,
        logic = "charge",
        body = Logic("WARRIOR", "charge"),
    },
    {
        id = "warrior_interrupt",
        name = { "Unterbrechen (F)", "Interrupt (F)" },
        desc = { "Unterbricht deinen Fokus, sonst den Gegner unter der Maus, sonst das Ziel. Berserkerhaltung: Zuschlagen, sonst Schildhieb (Schild nötig).",
                 "Interrupts your focus, otherwise the enemy under your mouse, otherwise your target. Berserker Stance: Pummel, otherwise Shield Bash (needs a shield)." },
        why = { "Unterbrich deinen Fokus mit Zuschlagen oder Schildhieb, ohne dein Ziel zu verlieren.",
                "Interrupt your focus with Pummel or Shield Bash without losing your current target." },
        without = { "Zauberer anklicken, Zuschlagen oder Schildhieb drücken, dann zurück zu deinem Ziel.",
                    "Click the caster, press Pummel or Shield Bash, then click back to your target." },
        rec = true,
        logic = "interrupt",
        body = Logic("WARRIOR", "interrupt"),
        need = 72,
    },
    {
        id = "warrior_taunt",
        name = { "Spott (MO)", "Taunt (MO)" },
        desc = { "Spottet auf den Gegner unter der Maus, sonst auf dein Ziel. Außerhalb der Verteidigungshaltung wechselt es zuerst in diese.",
                 "Taunts the enemy under your mouse, otherwise your target. Outside Defensive Stance it switches to it first." },
        why = { "Maus über den Gegner halten und drücken – Spott holt ihn zu dir, dein Ziel bleibt.",
                "Mouse over the enemy and press – Taunt pulls it to you while your target stays." },
        without = { "Gegner anklicken, Spott drücken, zurück zum alten Ziel – oft erst Haltung wechseln.",
                    "Click the enemy, press Taunt, click back – often after switching stance first." },
        rec = true,
        logic = "taunt",
        body = Logic("WARRIOR", "taunt", { tip = 355 }),
    },
    {
        id = "warrior_strike",
        name = { "Stoß/Spalten", "Strike/Cleave" },
        desc = { "Heldenhafter Stoß, mit Shift Spalten gegen mehrere Gegner. Beide ersetzen deinen nächsten Schlag.",
                 "Heroic Strike, with Shift Cleave against several enemies. Both replace your next swing." },
        why = { "Spart nur einen Platz in der Leiste: Heldenhafter Stoß, mit Shift Spalten.",
                "Only saves a bar slot: Heroic Strike, hold Shift for Cleave." },
        body = "#showtooltip\n/cast [mod:shift] {s:845}; {s:78}",
        need = 78,
    },
    {
        id = "warrior_overpower",
        name = { "Überwältigen", "Overpower" },
        desc = { "Überwältigen nach einem ausgewichenen Schlag. Wechselt bei Bedarf in die Kampfhaltung.",
                 "Overpower after a dodge. Switches to Battle Stance if needed." },
        why = { "Eine Taste für Überwältigen: bist du nicht in Kampfhaltung, wechselt der erste Druck dorthin.",
                "One key for Overpower: if you are not in Battle Stance, the first press switches to it." },
        body = "#showtooltip {s:7384}\n/cast [stance:1] {s:7384}; {s:2457}",
    },
    {
        id = "warrior_berserkerrage",
        name = { "Berserkerwut", "Berserker Rage" },
        desc = { "Berserkerwut gegen Furcht und für Wut. Wechselt bei Bedarf in die Berserkerhaltung.",
                 "Berserker Rage against fear and for rage. Switches to Berserker Stance if needed." },
        why = { "Eine Taste für Berserkerwut gegen Furcht: der erste Druck wechselt bei Bedarf die Haltung.",
                "One key for Berserker Rage against fear: the first press switches stance if needed." },
        body = "#showtooltip {s:18499}\n/cast [stance:3] {s:18499}; {s:2458}",
    },
    {
        id = "warrior_mocking",
        name = { "Spött. Schlag", "Mocking Blow" },
        desc = { "Spöttischer Schlag als zweiter Spott. Wechselt bei Bedarf in die Kampfhaltung.",
                 "Mocking Blow as a second taunt. Switches to Battle Stance if needed." },
        why = { "Spöttischer Schlag, wenn Spott noch abklingt – der erste Druck wechselt bei Bedarf die Haltung.",
                "Mocking Blow while Taunt is on cooldown – the first press switches stance if needed." },
        body = "#showtooltip {s:694}\n/cast [stance:1] {s:694}; {s:2457}",
    },
    {
        id = "warrior_emergency",
        name = { "Notfall-Tank", "Emergency Tank" },
        desc = { "Legt Einhandwaffe und Schild an (beim Übernehmen aus deiner Ausrüstung und den Taschen gewählt), dann Letztes Gefecht (Talent) und Schildwall. Außerhalb der Verteidigungshaltung wechselt der erste Druck die Haltung.",
                 "Equips a one-hander and a shield (picked from your gear and bags when you add it), then Last Stand (talent) and Shield Wall. Outside Defensive Stance the first press switches stance." },
        why = { "Letztes Gefecht und Schildwall mit einem Druck – im Notfall vergisst du keins von beiden.",
                "Last Stand and Shield Wall in one press – in an emergency you forget neither." },
        without = { "Zwei Tasten in Panik drücken, oft erst noch in die Verteidigungshaltung wechseln.",
                    "Hit two keys in a panic, often after switching to Defensive Stance first." },
        rec = true,
        body = "#showtooltip {s:871}\n{g:shield}\n/cast {s:12975}\n/cast [stance:2] {s:871}; {s:71}",
        need = 871,
    },
    {
        id = "warrior_shout",
        name = { "Blutrausch-Ruf", "Rage Shout" },
        desc = { "Blutrausch für Wut und sofort danach Schlachtruf. Kostet etwas Gesundheit.",
                 "Bloodrage for rage, then Battle Shout right away. Costs some health." },
        why = { "Blutrausch und Schlachtruf mit einem Druck – spart eine Taste, kostet etwas Gesundheit.",
                "Bloodrage and Battle Shout in one press – saves a key but costs some health." },
        body = "#showtooltip {s:6673}\n/cast {s:2687}\n/cast {s:6673}",
        need = 6673,
    },
    {
        id = "warrior_burst",
        name = { "Burst Furor", "Burst Fury" },
        desc = { "Blutrausch für Wut, beide Schmuckstücke, dann Todeswunsch – alles mit einem Druck.",
                 "Bloodrage for rage, both trinkets, then Death Wish – all in one press." },
        why = { "Blutrausch, beide Schmuckstücke und Todeswunsch mit einem Druck – nichts wird vergessen.",
                "Bloodrage, both trinkets and Death Wish in one press – nothing gets forgotten." },
        without = { "Vier Tasten nacheinander drücken – und dabei oft ein Schmuckstück vergessen.",
                    "Press four keys in a row – and often forget one of the trinkets." },
        rec = true,
        body = "#showtooltip {s:12328}\n/cast {s:2687}\n/use 13\n/use 14\n/cast {s:12328}",
        need = 12328,
    },
    {
        id = "warrior_reckless",
        name = { "Burst Tollkühn", "Burst Reckless" },
        desc = { "Berserkerhaltung: Blutrausch, beide Schmuckstücke und Tollkühnheit. Sonst wechselt es zuerst in die Berserkerhaltung.",
                 "Berserker Stance: Bloodrage, both trinkets and Recklessness. Otherwise it switches to Berserker Stance first." },
        why = { "Blutrausch, Schmuckstücke und Tollkühnheit in einem Druck – davor bei Bedarf ein Haltungswechsel.",
                "Bloodrage, trinkets and Recklessness in one press; the first press switches stance if needed." },
        body = "#showtooltip {s:1719}\n/cast [stance:3] {s:2687}\n/use [stance:3] 13\n/use [stance:3] 14\n/cast [stance:3] {s:1719}; {s:2458}",
        need = 1719,
    },
    {
        id = "warrior_sweeping",
        name = { "Weitreich+Spalt", "Sweep+Cleave" },
        desc = { "Kampfhaltung: Weitreichende Stöße, dazu Spalten auf den nächsten Schlag. Sonst wechselt es zuerst in die Kampfhaltung.",
                 "Battle Stance: Sweeping Strikes plus Cleave on your next swing. Otherwise it switches to Battle Stance first." },
        why = { "Weitreichende Stöße und Spalten mit einem Druck – gut gegen Gruppen, spart eine Taste.",
                "Sweeping Strikes and Cleave in one press – good against groups, saves a key." },
        body = "#showtooltip {s:12292}\n/cast [stance:1] {s:12292}; {s:2457}\n/cast [stance:1] {s:845}",
        need = 12292,
    },
    {
        id = "warrior_disarm",
        name = { "Entwaffnen", "Disarm" },
        desc = { "Verteidigungshaltung: Entwaffnen auf dein Ziel. In jeder anderen Haltung wechselt der erste Druck in die Verteidigungshaltung.",
                 "Defensive Stance: Disarm on your target. In any other stance the first press switches to Defensive Stance." },
        why = { "Eine Taste für Entwaffnen: der erste Druck holt dich bei Bedarf in die Verteidigungshaltung.",
                "One key for Disarm: the first press puts you in Defensive Stance if needed." },
        body = "#showtooltip {s:676}\n/cast [stance:2] {s:676}; {s:71}",
    },
    {
        id = "warrior_stances",
        name = { "Haltungswahl", "Stance Picker" },
        desc = { "Eine Taste für alle drei Haltungen: ohne Umschalttaste Kampfhaltung, mit Shift Verteidigungshaltung, mit Alt Berserkerhaltung.",
                 "One key for all three stances: no modifier for Battle Stance, Shift for Defensive Stance, Alt for Berserker Stance." },
        why = { "Drei Haltungen auf einem Platz der Leiste – Shift und Alt wählen die Haltung.",
                "Three stances on one bar slot – Shift and Alt pick the stance." },
        body = "#showtooltip\n/cast [mod:shift] {s:71}; [mod:alt] {s:2458}; {s:2457}",
        need = 2457,
    },
    -- Welle 27 (Paket modul/ezmacro-faehigkeiten): Lücken gegen ezCores Client-Tabellen gefüllt (Kopf der Datei), eigene Texte
    {
        id = "warrior_rend",
        name = { "Verwunden (MO)", "Rend (MO)" },
        desc = { "Verwunden auf den Gegner unter der Maus, sonst aufs Ziel – zum Verteilen auf mehrere Gegner.",
                 "Rend on the enemy under your mouse, otherwise your target – for spreading it on several enemies." },
        why = { "Verteile Verwunden auf mehrere Gegner: Maus drüber halten und drücken, ohne Zielwechsel.",
                "Spread Rend on several enemies: mouse over each and press, no target switching." },
        body = "#showtooltip\n/cast [@mouseover,harm,nodead][] {s:772}",
    },
})

ns.AddMacros("class", "PALADIN", {
    {
        id = "paladin_heal",
        name = { "Lichtblitz (MO)", "Flash (MO)" },
        desc = { "Lichtblitz auf den Spieler unter der Maus, sonst auf dein Ziel. Shift: Heiliges Licht.",
                 "Flash of Light on the player under your mouse, otherwise your target. Shift: Holy Light." },
        why = { "Heile Mitspieler, indem du nur die Maus über sie hältst – Lichtblitz, mit Shift Heiliges Licht.",
                "Heal players just by holding your mouse over them – Flash of Light, Shift for Holy Light." },
        without = { "Spieler anklicken, heilen, zurück zum Gegner – drei Handgriffe, während jemand stirbt.",
                    "Click the player, heal, click back to the enemy – three steps while someone is dying." },
        rec = true,
        logic = "heal",
        body = Logic("PALADIN", "heal"),
        need = 635,
    },
    {
        id = "paladin_blessing",
        name = { "Segen (MO)", "Blessing (MO)" },
        desc = { "Segen der Macht auf den Spieler unter der Maus, sonst aufs Ziel. Shift: Weisheit, Strg: Könige (Talent).",
                 "Blessing of Might on the player under your mouse, otherwise your target. Shift: Wisdom, Ctrl: Kings (talent)." },
        why = { "Segen der Macht, Shift Weisheit, Strg Könige – Maus über den Spieler halten, kein Zielwechsel.",
                "Blessing of Might, Shift Wisdom, Ctrl Kings – mouse over the player, no target switch." },
        -- Umschalt-Schritte in ezCores Kurzform „exists,noharm“ (kein Durchrutschen auf das Ziel; die langen Gruppen-Glieder
        -- für alle drei Segen sprengten Blizzards 255 Zeichen), der Schritt ohne Taste bekommt sie über ns.GroupFirst
        body = "#showtooltip\n/cast [mod:ctrl,@mouseover,exists,noharm][mod:ctrl] {s:20217}; [mod:shift,@mouseover,exists,noharm][mod:shift] {s:19742}; [@mouseover,help,nodead][] {s:19740}",
        need = 19740,
    },
    {
        id = "paladin_cleanse",
        name = { "Reinigung (MO)", "Cleanse (MO)" },
        desc = { "Entfernt Gift, Krankheit und Magie vom Spieler unter der Maus, sonst vom freundlichen Ziel, sonst von dir.",
                 "Removes poison, disease and magic from the player under your mouse, otherwise your friendly target, otherwise you." },
        why = { "Gift, Krankheit und Magie entfernen: Maus über den Spieler halten und drücken – dein Ziel bleibt.",
                "Remove poison, disease and magic: mouse over the player and press – your target stays." },
        without = { "Spieler anklicken, reinigen, zurück zum Ziel – bis dahin wirkt das Gift weiter.",
                    "Click the player, cleanse, click back – meanwhile the poison keeps working." },
        rec = true,
        logic = "cleanse",
        body = Logic("PALADIN", "cleanse"),
    },
    {
        id = "paladin_protection",
        name = { "Schutz (MO)", "Protection (MO)" },
        desc = { "Segen des Schutzes auf den Spieler unter der Maus, sonst aufs freundliche Ziel, sonst auf dich.",
                 "Blessing of Protection on the player under your mouse, otherwise your friendly target, otherwise you." },
        why = { "Rette einen Mitspieler mit Segen des Schutzes: Maus über ihn halten und drücken, kein Zielwechsel.",
                "Save a player with Blessing of Protection: mouse over them and press – no target switch." },
        without = { "Spieler suchen, anklicken, Segen wirken, zurück zum Ziel – meist zu spät.",
                    "Find the player, click them, cast the blessing, click back – usually too late." },
        rec = true,
        body = "#showtooltip\n/cast [@mouseover,help,nodead][help,nodead][@player] {s:1022}",
    },
    {
        id = "paladin_freedom",
        name = { "Freiheit (MO)", "Freedom (MO)" },
        desc = { "Segen der Freiheit auf den Spieler unter der Maus, sonst aufs freundliche Ziel, sonst auf dich.",
                 "Blessing of Freedom on the player under your mouse, otherwise your friendly target, otherwise you." },
        why = { "Segen der Freiheit auf den Spieler unter der Maus, sonst auf dich – kein Zielwechsel nötig.",
                "Blessing of Freedom on the player under your mouse, otherwise you – no target switch needed." },
        body = "#showtooltip\n/cast [@mouseover,help,nodead][help,nodead][@player] {s:1044}",
    },
    {
        id = "paladin_hammer",
        name = { "Hammer (F)", "Hammer (F)" },
        desc = { "Hammer der Gerechtigkeit betäubt deinen Fokus (z. B. gegen einen Zauber), sonst den Gegner unter der Maus oder das Ziel.",
                 "Hammer of Justice stuns your focus (e.g. to stop a cast), otherwise the enemy under your mouse or your target." },
        why = { "Betäube deinen Fokus mit Hammer der Gerechtigkeit, um einen Zauber zu stoppen – dein Ziel bleibt.",
                "Stun your focus with Hammer of Justice to stop a cast – your current target stays." },
        without = { "Zauberer anklicken, Hammer werfen, zurück zum alten Ziel – oft ist der Zauber dann durch.",
                    "Click the caster, throw the hammer, click back – often the cast is through by then." },
        rec = true,
        logic = "hammer",
        body = Logic("PALADIN", "hammer"),
    },
    {
        id = "paladin_res",
        name = { "Erlösung (MO)", "Redemption (MO)" },
        desc = { "Erlösung auf den toten Spieler unter der Maus, sonst aufs Ziel.",
                 "Redemption on the dead player under your mouse, otherwise your target." },
        why = { "Erlösung auf den toten Spieler unter der Maus – kein Anklicken der Leiche nötig.",
                "Redemption on the dead player under your mouse – no need to click the body first." },
        logic = "res",
        body = Logic("PALADIN", "res"),
    },
    {
        id = "paladin_layonhands",
        name = { "Handauflegung", "Lay on Hands" },
        desc = { "Handauflegung auf den Spieler unter der Maus, sonst aufs freundliche Ziel, sonst auf dich.",
                 "Lay on Hands on the player under your mouse, otherwise your friendly target, otherwise you." },
        why = { "Handauflegung auf den Spieler unter der Maus, sonst auf dich – kein Zielwechsel im Notfall.",
                "Lay on Hands on the player under your mouse, otherwise you – no target switch in an emergency." },
        logic = "layOnHands",
        body = Logic("PALADIN", "layOnHands"),
    },
    {
        id = "paladin_sealjudge",
        name = { "Siegel & Urteil", "Seal & Judge" },
        desc = { "Startet den Angriff und wechselt bei jedem Druck zwischen Siegel der Rechtschaffenheit und Richturteil. Beginnt bei neuem Ziel oder nach 15 s von vorn.",
                 "Starts attacking and alternates between Seal of Righteousness and Judgement on each press. Restarts on a new target or after 15 sec." },
        why = { "Eine Taste fürs Leveln: wechselt bei jedem Druck Siegel der Rechtschaffenheit und Richturteil.",
                "One key for leveling: alternates Seal of Righteousness and Judgement on each press." },
        body = "#showtooltip\n/startattack\n/castsequence reset=target/15 {s:21084}, {s:20271}",
    },
    {
        id = "paladin_shield",
        name = { "Gottesschild", "Divine Shield" },
        desc = { "Bricht einen laufenden Zauber ab und wirkt sofort Gottesschild.",
                 "Stops your current cast and uses Divine Shield right away." },
        why = { "Gottesschild sofort, auch mitten im Zaubern – du musst den Zauber nicht erst abbrechen.",
                "Divine Shield right away, even mid-cast – no need to stop your cast first." },
        body = "#showtooltip\n/stopcasting\n/cast {s:642}",
    },
    {
        id = "paladin_favorlight",
        name = { "Gunst-Licht", "Favor Light" },
        desc = { "Göttliche Gunst und beide Schmuckstücke, dann ein sicher kritisches Heiliges Licht – auf Mouseover, Ziel oder dich.",
                 "Divine Favor and both trinkets, then a guaranteed critical Holy Light – on mouseover, target or yourself." },
        why = { "Göttliche Gunst, Schmuckstücke und sicher kritisches Heiliges Licht in einem Druck – auch per Maus.",
                "Divine Favor, trinkets and a sure critical Holy Light in one press – mouse over works too." },
        without = { "Drei Tasten drücken, dann Spieler anklicken und Heiliges Licht – im Notfall zu langsam.",
                    "Press three keys, then click the player and cast Holy Light – too slow in an emergency." },
        rec = true,
        body = "#showtooltip {s:635}\n/cast {s:20216}\n/use 13\n/use 14\n/cast [@mouseover,help,nodead][help,nodead][@player] {s:635}",
        need = 20216,
    },
    {
        id = "paladin_favorshock",
        name = { "Gunst-Schock", "Favor Shock" },
        desc = { "Göttliche Gunst und beide Schmuckstücke, dann Heiliger Schock: heilt Verbündete, trifft Gegner (Mouseover, sonst Ziel).",
                 "Divine Favor and both trinkets, then Holy Shock: heals allies, hits enemies (mouseover, otherwise target)." },
        why = { "Göttliche Gunst, Schmuckstücke, Heiliger Schock mit einem Druck – heilt Verbündete, trifft Gegner.",
                "Divine Favor, trinkets and Holy Shock in one press – heals allies, hits enemies." },
        -- Heiliger Schock: Grund-ID 1311606 (Rang 1, Talent ab Stufe 30) laut ClassSpells, wie ezCores HEALS.PALADIN.hot;
        -- 20473 ist Rang 2 (ab Stufe 40). Die Laufzeit löst Ränge über den Namen auf (Gesamtreview 18.11.2026, T14-NH1)
        body = "#showtooltip {s:1311606}\n/cast {s:20216}\n/use 13\n/use 14\n/cast [@mouseover,exists,nodead][] {s:1311606}",
        need = 1311606,
    },
    -- Welle 27 (Paket modul/ezmacro-faehigkeiten): Lücken gegen ezCores Client-Tabellen gefüllt (Kopf der Datei), eigene Texte
    {
        id = "paladin_turnundead",
        name = { "Vertreiben (F)", "Turn Undead (F)" },
        desc = { "Untote vertreiben auf deinen Fokus, ohne Fokus auf dein Ziel – wirkt nur gegen Untote.",
                 "Turn Undead on your focus, or your target without one – works on undead only." },
        why = { "Schick einen zweiten Untoten weg (Fokus), ohne dein Ziel zu wechseln.",
                "Send a second undead away (focus) without switching your target." },
        body = "#showtooltip\n/cast [@focus,harm,nodead][] {s:2878}",
    },
    {
        id = "paladin_repentance",
        name = { "Buße (F)", "Repentance (F)" },
        desc = { "Buße (Talent) auf deinen Fokus, ohne Fokus auf dein Ziel.",
                 "Repentance (talent) on your focus, or your target without one." },
        why = { "Setz einen zweiten Gegner mit Buße außer Gefecht, ohne dein Ziel zu wechseln.",
                "Take a second enemy out with Repentance without switching your target." },
        body = "#showtooltip\n/cast [@focus,harm,nodead][] {s:20066}",
    },
})

ns.AddMacros("class", "HUNTER", {
    {
        id = "hunter_markattack",
        name = { "Mal & Angriff", "Mark & Attack" },
        desc = { "Setzt Mal des Jägers auf den Gegner unter der Maus oder dein Ziel und schickt dein Tier hinterher.",
                 "Places Hunter's Mark on the enemy under your mouse or your target and sends your pet in." },
        why = { "Mal des Jägers setzen und dein Tier losschicken mit einem Druck – spart einen Klick zu Kampfbeginn.",
                "Hunter's Mark and sending your pet in with one press – saves a click when a fight starts." },
        body = "#showtooltip {s:1130}\n/petattack [@mouseover,harm,nodead][]\n/cast [@mouseover,harm,nodead][] {s:1130}",
    },
    {
        id = "hunter_shoot",
        name = { "Schuss + Tier", "Shoot + Pet" },
        desc = { "Startet den automatischen Schuss, ohne ihn versehentlich abzuschalten, und schickt dein Tier mit.",
                 "Starts Auto Shot without accidentally switching it off and sends your pet along." },
        why = { "Startet den automatischen Schuss und schickt dein Tier mit – zweimal drücken schaltet nichts ab.",
                "Starts Auto Shot and sends your pet along – pressing twice never switches the shot off." },
        without = { "Schuss starten, dann Tier per Klick losschicken – und ein Doppeldruck stoppt den Schuss.",
                    "Start shooting, then click your pet to attack – and a double press stops the shot." },
        rec = true,
        body = "#showtooltip {s:75}\n/petattack [@mouseover,harm,nodead][]\n/cast [@mouseover,harm,nodead][] !{s:75}",
    },
    {
        id = "hunter_petcare",
        name = { "Tier: Pflege", "Pet Care" },
        desc = { "Ohne Tier: Tier rufen. Tier tot oder mit Shift: Tier wiederbeleben. Sonst: Tier heilen.",
                 "No pet: Call Pet. Pet dead or with Shift: Revive Pet. Otherwise: Mend Pet." },
        why = { "Tier rufen, Tier wiederbeleben oder Tier heilen – eine Taste wählt, was gerade passt.",
                "Call Pet, Revive Pet or Mend Pet – one key picks whatever fits right now." },
        logic = "petCare",
        body = Logic("HUNTER", "petCare"),
        need = 883,
    },
    {
        id = "hunter_feign",
        name = { "Totstellen", "Feign Death" },
        desc = { "Hört auf anzugreifen und stellt dich tot. Allein holt es dein Tier zurück, in einer Gruppe kämpft es weiter.",
                 "Stops attacking and feigns death. Solo it calls your pet back; in a group it keeps fighting." },
        why = { "Totstellen und Angriff stoppen in einem Druck; allein kommt dein Tier zurück, in der Gruppe nicht.",
                "Feign Death and stop attacking in one press; solo your pet comes back, in a group it stays." },
        body = "#showtooltip {s:5384}\n/petfollow [nogroup]\n/stopattack\n/cast {s:5384}",
    },
    {
        id = "hunter_feigntrap",
        name = { "Tot-Falle", "Feign Trap" },
        desc = { "Erster Druck: Totstellen. Zweiter Druck innerhalb von 5 s: Eiskältefalle. Fallen lassen sich nur außerhalb des Kampfes legen.",
                 "First press: Feign Death. Second press within 5 sec: Freezing Trap. Traps can only be laid out of combat." },
        why = { "Totstellen und gleich danach Eiskältefalle auf derselben Taste – einfach zweimal drücken.",
                "Feign Death, then Freezing Trap on the same key – just press it twice." },
        body = "#showtooltip {s:1499}\n/castsequence reset=5 {s:5384}, {s:1499}",
        need = 1499,
    },
    {
        id = "hunter_aspects",
        name = { "Aspekte", "Aspects" },
        desc = { "Aspekt des Falken. Shift: Gepard, Strg: Affe. Schaltet einen aktiven Aspekt nie versehentlich ab.",
                 "Aspect of the Hawk. Shift: Cheetah, Ctrl: Monkey. Never switches an active aspect off by accident." },
        why = { "Spart Plätze: Aspekt des Falken, Shift Gepard, Strg Affe – schaltet keinen aus Versehen ab.",
                "Saves slots: Aspect of the Hawk, Shift Cheetah, Ctrl Monkey – never turns one off by mistake." },
        logic = "aspects",
        body = Logic("HUNTER", "aspects"),
        need = 13165,
    },
    {
        id = "hunter_tranq",
        name = { "Einlullen (F)", "Tranq Shot (F)" },
        desc = { "Einlullender Schuss auf deinen Fokus (z. B. den Boss), sonst auf den Gegner unter der Maus oder das Ziel.",
                 "Tranquilizing Shot on your focus (e.g. the boss), otherwise the enemy under your mouse or your target." },
        why = { "Einlullender Schuss auf deinen Fokus, ohne dein Ziel zu wechseln – nur bei wenigen Bossen nötig.",
                "Tranquilizing Shot on your focus without switching target – needed only for a few bosses." },
        logic = "tranq",
        body = Logic("HUNTER", "tranq"),
    },
    {
        id = "hunter_scatter",
        name = { "Streuschuss (F)", "Scatter (F)" },
        desc = { "Streuschuss auf deinen Fokus, sonst aufs Ziel.",
                 "Scatter Shot on your focus, otherwise your target." },
        why = { "Streuschuss auf deinen Fokus: einen zweiten Gegner kurz aufhalten, ohne dein Ziel zu verlieren.",
                "Scatter Shot on your focus: briefly stop a second enemy without losing your target." },
        without = { "Zweiten Gegner anklicken, Streuschuss, zurück zum Ziel – kostet wertvolle Sekunden.",
                    "Click the second enemy, Scatter Shot, click back to your target – costs precious seconds." },
        rec = true,
        body = "#showtooltip\n/cast [@focus,harm,nodead][] {s:19503}",
    },
    {
        id = "hunter_melee",
        name = { "Nahkampf", "Melee" },
        desc = { "Startet den Nahkampf, nutzt Mungobiss, sobald er bereit ist, sonst Raptorstoß.",
                 "Starts melee, uses Mongoose Bite when it is ready, otherwise Raptor Strike." },
        why = { "Im Nahkampf nimmt die Taste Mungobiss, sobald er bereit ist, sonst Raptorstoß – nichts verpasst.",
                "In melee the key uses Mongoose Bite as soon as it is ready, otherwise Raptor Strike." },
        body = "#showtooltip {s:2973}\n/startattack\n/cast {s:1495}\n/cast {s:2973}",
        need = 2973,
    },
    {
        id = "hunter_growl",
        name = { "Knurren an/aus", "Growl On/Off" },
        desc = { "Schaltet das automatische Knurren deines Tiers an oder aus – in Gruppen mit Tank ausschalten.",
                 "Toggles your pet's automatic Growl – switch it off in groups with a tank." },
        why = { "Schaltet das Knurren deines Tiers an oder aus – geht genauso per Rechtsklick in der Tierleiste.",
                "Toggles your pet's Growl – a right-click on the pet bar does the same." },
        body = "#showtooltip {s:2649}\n/petautocasttoggle {s:2649}",
        need = 883,
    },
    {
        id = "hunter_burst",
        name = { "Burst Fernkampf", "Burst Ranged" },
        desc = { "Schickt dein Tier los, nutzt beide Schmuckstücke und Schnellfeuer (Mouseover, sonst Ziel).",
                 "Sends your pet in, uses both trinkets and Rapid Fire (mouseover, otherwise target)." },
        why = { "Tier losschicken, beide Schmuckstücke und Schnellfeuer mit einem Druck – nichts wird vergessen.",
                "Sends your pet, uses both trinkets and Rapid Fire in one press – nothing gets forgotten." },
        without = { "Tier losschicken, zwei Schmuckstücke und Schnellfeuer einzeln drücken – vier Tasten.",
                    "Send the pet, use two trinkets and Rapid Fire one by one – four separate keys." },
        rec = true,
        body = "#showtooltip {s:3045}\n/petattack [@mouseover,harm,nodead][]\n/use 13\n/use 14\n/cast {s:3045}",
        need = 3045,
    },
    {
        id = "hunter_wrath",
        name = { "Zorn & Angriff", "Wrath & Attack" },
        desc = { "Dein Tier greift an, dazu Zorn des Wildtiers und beide Schmuckstücke (Talent der Tierherrschaft).",
                 "Your pet attacks, plus Bestial Wrath and both trinkets (Beast Mastery talent)." },
        why = { "Dein Tier greift an, dazu Zorn des Wildtiers und beide Schmuckstücke – alles in einem Druck.",
                "Your pet attacks, plus Bestial Wrath and both trinkets – all in one press." },
        without = { "Tier losschicken, Zorn des Wildtiers, zwei Schmuckstücke – vier Tasten, leicht vergessen.",
                    "Send the pet, Bestial Wrath, two trinkets – four keys, easy to forget one." },
        rec = true,
        body = "#showtooltip {s:19574}\n/petattack [@mouseover,harm,nodead][]\n/cast {s:19574}\n/use 13\n/use 14",
        need = 19574,
    },
    -- Welle 9 (UE-26): neu aus ezCores Klassen-Wissen (Makro-Logik „petShot“), eigene Texte
    {
        id = "hunter_arcanepet",
        name = { "Arkan+Tier (MO)", "Arcane+Pet (MO)" },
        desc = { "Schickt dein Tier auf den Gegner unter der Maus, sonst auf dein Ziel, und wirkt dort Arkaner Schuss.",
                 "Sends your pet at the enemy under your mouse, otherwise your target, and casts Arcane Shot on it." },
        why = { "Tier und Arkaner Schuss treffen denselben Gegner – mit einem Druck.",
                "Pet and Arcane Shot hit the same enemy – in one press." },
        logic = "petShot",
        body = Logic("HUNTER", "petShot"),
    },
    -- Welle 27 (Paket modul/ezmacro-faehigkeiten): Lücken gegen ezCores Client-Tabellen gefüllt (Kopf der Datei), eigene Texte
    {
        id = "hunter_serpent",
        name = { "Schlangenb. (MO)", "Serpent (MO)" },
        desc = { "Schlangenbiss auf den Gegner unter der Maus, sonst aufs Ziel – zum Verteilen auf mehrere Gegner.",
                 "Serpent Sting on the enemy under your mouse, otherwise your target – for spreading it on several enemies." },
        why = { "Verteile Schlangenbiss auf mehrere Gegner: Maus drüber halten und drücken, ohne Zielwechsel.",
                "Spread Serpent Sting on several enemies: mouse over each and press, no target switching." },
        body = "#showtooltip\n/cast [@mouseover,harm,nodead][] {s:1978}",
    },
    {
        id = "hunter_scarebeast",
        name = { "Ängstigen (F)", "Scare Beast (F)" },
        desc = { "Wildtier ängstigen auf deinen Fokus, ohne Fokus auf dein Ziel – wirkt nur gegen Wildtiere.",
                 "Scare Beast on your focus, or your target without one – works on beasts only." },
        why = { "Schick ein zweites Wildtier mit Furcht weg (Fokus), ohne dein Ziel zu wechseln.",
                "Send a second beast away with fear (focus) without switching your target." },
        body = "#showtooltip\n/cast [@focus,harm,nodead][] {s:1513}",
    },
})

ns.AddMacros("class", "ROGUE", {
    {
        id = "rogue_kick",
        name = { "Tritt (F)", "Kick (F)" },
        desc = { "Tritt unterbricht deinen Fokus, ohne Fokus das Ziel.",
                 "Kick interrupts your focus, or your target without one." },
        why = { "Unterbrich mit Tritt einen zweiten Gegner (deinen Fokus), ohne dein Ziel zu wechseln.",
                "Kick a second enemy (your focus) to interrupt it without switching away from your target." },
        without = { "Ziel auf den Zauberer wechseln, Tritt drücken, dann zurück zum alten Ziel.",
                    "Target the caster, press Kick, then find and target your old enemy again." },
        rec = true,
        logic = "kick",
        body = Logic("ROGUE", "kick"),
    },
    {
        id = "rogue_sap",
        name = { "Kopfnuss (MO)", "Sap (MO)" },
        desc = { "Erster Druck: Verstohlenheit. Danach Kopfnuss auf den Gegner unter der Maus, sonst aufs Ziel.",
                 "First press: Stealth. Then Sap on the enemy under your mouse, otherwise your target." },
        why = { "Ein Knopf für Verstohlenheit und danach Kopfnuss – auch auf einen Gegner unter der Maus.",
                "One key for Stealth and then Sap – also on an enemy under your mouse, no targeting needed." },
        -- empfohlen seit dem Spieltest 20.11.2026 (wörtlich „wieso fehlt davon auf einmal die hälfte? z.b. kopfnuss und
        -- taschendiebstahl“): Kontrolle vor dem Kampf, wie Verwandlung (F) beim Magier – steht damit ab Werk in der Liste
        without = { "Gegner anklicken, Verstohlenheit drücken, dann Kopfnuss – und zurück zu deinem Ziel.",
                    "Click the enemy, press Stealth, then Sap – and switch back to your target." },
        rec = true,
        logic = "sap",
        body = Logic("ROGUE", "sap", { tip = 6770 }),
    },
    {
        id = "rogue_opener",
        name = { "Öffner", "Opener" },
        desc = { "Ohne Verstohlenheit: verstohlen werden. Verstohlen: Fieser Trick, mit Shift Hinterhalt. Im Kampf: Finsterer Stoß.",
                 "Not stealthed: Stealth. Stealthed: Cheap Shot, with Shift Ambush. In combat: Sinister Strike." },
        why = { "Verstohlenheit, Fieser Trick, Hinterhalt (Shift) und Finsterer Stoß auf einer Taste – spart Plätze.",
                "Stealth, Cheap Shot, Ambush (Shift) and Sinister Strike on one key – saves bar slots." },
        body = "#showtooltip\n/cast [nostealth,nocombat] {s:1784}; [stealth,mod:shift] {s:8676}; [stealth] {s:1833}; {s:1752}",
        need = 1784,
    },
    {
        id = "rogue_blind",
        name = { "Blenden (F)", "Blind (F)" },
        desc = { "Blenden auf deinen Fokus, sonst auf den Gegner unter der Maus oder das Ziel.",
                 "Blind on your focus, otherwise the enemy under your mouse or your target." },
        why = { "Blende einen zweiten Gegner (Fokus oder unter der Maus), ohne dein Ziel zu verlieren.",
                "Blind a second enemy (focus or under your mouse) without losing your current target." },
        without = { "Ziel wechseln, Blenden wirken, dann dein eigentliches Ziel wieder anklicken.",
                    "Switch target, cast Blind, then click your real target again." },
        rec = true,
        body = "#showtooltip\n/cast [@focus,harm,nodead][@mouseover,harm,nodead][] {s:2094}",
    },
    {
        id = "rogue_gouge",
        name = { "Solarplexus (F)", "Gouge (F)" },
        desc = { "Solarplexus auf deinen Fokus, sonst aufs Ziel – auch als Unterbrechung nutzbar.",
                 "Gouge on your focus, otherwise your target – also works as an interrupt." },
        why = { "Solarplexus auf deinen Fokus, ohne Zielwechsel – als Ersatz, wenn Tritt gerade abklingt.",
                "Gouge your focus without switching target – a backup when Kick is on cooldown." },
        body = "#showtooltip\n/cast [@focus,harm,nodead][] {s:1776}",
    },
    {
        id = "rogue_distract",
        name = { "Ablenken", "Distract" },
        desc = { "Wirft Ablenken sofort dorthin, wo die Maus zeigt – ohne zusätzlichen Klick.",
                 "Throws Distract right where your mouse points – no extra click." },
        why = { "Ablenken landet sofort dort, wo deine Maus zeigt – kein zweiter Klick zum Zielen.",
                "Distract lands right where your mouse points – no second click to aim." },
        body = "#showtooltip\n/cast [@cursor] {s:1725}",
    },
    {
        id = "rogue_coldblood",
        name = { "Kaltblütig", "Cold Blood Evis" },
        desc = { "Kaltblütigkeit (Talent) und sofort Ausweiden – garantiert kritisch.",
                 "Cold Blood (talent) and Eviscerate right away – a guaranteed critical hit." },
        why = { "Kaltblütigkeit und Ausweiden mit einem Druck statt zwei – für den sicheren kritischen Treffer.",
                "Cold Blood and Eviscerate in one press instead of two – for the guaranteed critical hit." },
        without = { "Erst Kaltblütigkeit drücken, dann Ausweiden – zwei Tasten im entscheidenden Moment.",
                    "Press Cold Blood first, then Eviscerate – two keys at the deciding moment." },
        rec = true,
        body = "#showtooltip {s:2098}\n/cast {s:14177}\n/cast {s:2098}",
        need = 14177,
    },
    {
        id = "rogue_pickpocket",
        name = { "Taschendieb (MO)", "Pick Pocket (MO)" },
        desc = { "Taschendiebstahl beim Gegner unter der Maus, sonst beim Ziel.",
                 "Pick Pocket on the enemy under your mouse, otherwise your target." },
        why = { "Taschendiebstahl beim Gegner unter der Maus, ohne ihn erst anklicken zu müssen.",
                "Pick Pocket the enemy under your mouse without clicking it first." },
        body = "#showtooltip\n/cast [@mouseover,harm,nodead][] {s:921}",
    },
    {
        id = "rogue_vanish",
        name = { "Verschwinden", "Vanish" },
        desc = { "Hört auf anzugreifen und verschwindet – so springst du nicht gleich wieder in den Kampf.",
                 "Stops attacking and vanishes – so you do not jump straight back into combat." },
        why = { "Verschwinden stoppt zugleich deinen Angriff – du springst nicht gleich wieder in den Kampf.",
                "Vanish also stops your attack – so you don't jump straight back into combat." },
        body = "#showtooltip\n/stopattack\n/cast {s:1856}",
    },
    {
        id = "rogue_burst",
        name = { "Burst Kampf", "Burst Combat" },
        desc = { "Greift an, zündet beide Schmuckstücke und Klingenwirbel; mit Shift statt Klingenwirbel Adrenalinrausch.",
                 "Attacks, fires both trinkets and Blade Flurry; with Shift Adrenaline Rush instead of Blade Flurry." },
        why = { "Schmuckstücke und Klingenwirbel auf einer Taste, mit Shift Adrenalinrausch – nichts vergessen.",
                "Trinkets and Blade Flurry on one key, Adrenaline Rush with Shift – nothing forgotten." },
        without = { "Zwei Schmuckstücke, Klingenwirbel und Adrenalinrausch einzeln drücken – vier Tasten.",
                    "Press both trinkets, Blade Flurry and Adrenaline Rush one by one – four keys." },
        rec = true,
        body = "#showtooltip\n/startattack\n/use 13\n/use 14\n/cast [mod:shift] {s:13750}; {s:13877}",
        need = 13877,
    },
})

ns.AddMacros("class", "PRIEST", {
    {
        id = "priest_flash",
        name = { "Blitzheil. (MO)", "Flash Heal (MO)" },
        desc = { "Blitzheilung auf den Spieler unter der Maus, sonst auf dein freundliches Ziel, sonst auf dich.",
                 "Flash Heal on the player under your mouse, otherwise your friendly target, otherwise you." },
        why = { "Blitzheilung auf den Spieler, über dem deine Maus ist – ein Druck, dein Ziel bleibt.",
                "Flash Heal whoever is under your mouse – one press, and your target stays." },
        without = { "Spieler im Gruppenfenster anklicken, Blitzheilung drücken, altes Ziel wieder suchen.",
                    "Click the player's frame, press Flash Heal, then look for your old target again." },
        rec = true,
        logic = "flash",
        body = Logic("PRIEST", "flash"),
    },
    {
        id = "priest_heal",
        name = { "Heilen (MO)", "Heal (MO)" },
        desc = { "Heilen, mit Shift Großes Heilen – auf den Spieler unter der Maus, sonst aufs Ziel.",
                 "Heal, with Shift Greater Heal – on the player under your mouse, otherwise your target." },
        why = { "Heilen oder mit Shift Großes Heilen auf den Spieler unter der Maus – dein Ziel bleibt.",
                "Heal, or Greater Heal with Shift, on the player under your mouse – your target stays." },
        body = "#showtooltip\n/cast [mod:shift,@mouseover,help,nodead][mod:shift] {s:2060}; [@mouseover,help,nodead][] {s:2054}",
        need = 2054,
    },
    {
        id = "priest_renew",
        name = { "Erneuerung (MO)", "Renew (MO)" },
        desc = { "Erneuerung auf den Spieler unter der Maus, sonst aufs freundliche Ziel, sonst auf dich.",
                 "Renew on the player under your mouse, otherwise your friendly target, otherwise you." },
        why = { "Verteile Erneuerung schnell: Maus über den Spieler halten und drücken – kein Zielwechsel.",
                "Spread Renew fast: mouse over a player and press – no target switching." },
        without = { "Für jeden Spieler einzeln: Rahmen anklicken, Erneuerung drücken, weiter zum nächsten.",
                    "For every player: click their frame, press Renew, then move on to the next." },
        rec = true,
        body = "#showtooltip\n/cast [@mouseover,help,nodead][help,nodead][@player] {s:139}",
    },
    {
        id = "priest_shield",
        name = { "Schild (MO)", "Shield (MO)" },
        desc = { "Machtwort: Schild auf den Spieler unter der Maus, sonst aufs freundliche Ziel, sonst auf dich.",
                 "Power Word: Shield on the player under your mouse, otherwise your friendly target, otherwise you." },
        why = { "Machtwort: Schild sofort auf den Spieler unter der Maus – rettet ihn ohne Zielwechsel.",
                "Power Word: Shield right on the player under your mouse – save them without switching target." },
        without = { "Spieler anklicken, Machtwort: Schild drücken, dann wieder dein altes Ziel anklicken.",
                    "Click the player, press Power Word: Shield, then click your old target again." },
        rec = true,
        logic = "shield",
        body = Logic("PRIEST", "shield"),
    },
    {
        id = "priest_dispel",
        name = { "Bannen (MO)", "Dispel (MO)" },
        desc = { "Magiebannung auf die Einheit unter der Maus, sonst aufs Ziel, ohne Ziel auf dich: entfernt bei Freunden schädliche, bei Gegnern nützliche Magie.",
                 "Dispel Magic on the unit under your mouse, otherwise your target, without one on you: removes harmful magic from friends and helpful magic from enemies." },
        why = { "Magiebannung auf die Einheit unter der Maus – für Freund und Feind, ohne Zielwechsel.",
                "Dispel Magic whatever is under your mouse – friend or enemy, no target switch." },
        without = { "Betroffenen anklicken, Magiebannung drücken, dann zurück zu deinem alten Ziel.",
                    "Click the affected unit, press Dispel Magic, then go back to your old target." },
        rec = true,
        logic = "dispel",
        body = Logic("PRIEST", "dispel"),
    },
    {
        id = "priest_disease",
        name = { "Krankheit (MO)", "Disease (MO)" },
        desc = { "Krankheit aufheben auf den Spieler unter der Maus, sonst aufs freundliche Ziel, sonst auf dich. Shift: Krankheit heilen.",
                 "Abolish Disease on the player under your mouse, otherwise your friendly target, otherwise you. Shift: Cure Disease." },
        why = { "Krankheit aufheben (Shift: Krankheit heilen) auf den Spieler unter der Maus – ohne Zielwechsel.",
                "Abolish Disease (Shift: Cure Disease) on the player under your mouse – no target switch." },
        -- Umschalt in ezCores Kurzform „exists,noharm“: mit den langen Gruppen-Glieder in beiden Schritten wäre der Text
        -- länger als Blizzards 255 Zeichen (Spieltest 15.11.2026, kein Durchrutschen auf das Ziel)
        body = "#showtooltip\n/cast [mod:shift,@mouseover,exists,noharm][mod:shift,help,nodead][mod:shift,@player] {s:528}; [@mouseover,help,nodead][help,nodead][@player] {s:552}",
        need = 528,
    },
    {
        id = "priest_pain",
        name = { "Schmerz (MO)", "Pain (MO)" },
        desc = { "Schattenwort: Schmerz auf den Gegner unter der Maus, sonst aufs Ziel – ideal für mehrere Gegner.",
                 "Shadow Word: Pain on the enemy under your mouse, otherwise your target – great for several enemies." },
        why = { "Verteile Schattenwort: Schmerz auf mehrere Gegner – Maus drüber, drücken, dein Ziel bleibt.",
                "Spread Shadow Word: Pain over several enemies – mouse over, press, your target stays." },
        body = "#showtooltip\n/cast [@mouseover,harm,nodead][] {s:589}",
    },
    {
        id = "priest_shackle",
        name = { "Fesseln (F)", "Shackle (F)" },
        desc = { "Untote fesseln auf deinen Fokus, sonst auf den Gegner unter der Maus oder das Ziel.",
                 "Shackle Undead on your focus, otherwise the enemy under your mouse or your target." },
        why = { "Untote fesseln auf deinen Fokus oder den Gegner unter der Maus – dein Ziel bleibt dabei.",
                "Shackle Undead on your focus or the enemy under your mouse – your target stays." },
        logic = "shackle",
        body = Logic("PRIEST", "shackle"),
    },
    {
        id = "priest_innerfocus",
        name = { "Fokus-Heilung", "Focused Heal" },
        desc = { "Innerer Fokus (Talent) und sofort Großes Heilen ohne Manakosten auf den Spieler unter der Maus oder das Ziel.",
                 "Inner Focus (talent) and a free Greater Heal right away on the player under your mouse or your target." },
        why = { "Innerer Fokus und Großes Heilen ohne Manakosten mit einem Druck statt zwei.",
                "Inner Focus and a free Greater Heal with one press instead of two." },
        body = "#showtooltip {s:2060}\n/cast {s:14751}\n/cast [@mouseover,help,nodead][] {s:2060}",
        need = 14751,
    },
    {
        id = "priest_res",
        name = { "Auferstehen (MO)", "Resurrect (MO)" },
        desc = { "Auferstehung auf den toten Spieler unter der Maus, sonst aufs Ziel.",
                 "Resurrection on the dead player under your mouse, otherwise your target." },
        why = { "Auferstehung auf den toten Spieler unter der Maus – kein Anklicken der Leiche nötig.",
                "Resurrection on the dead player under your mouse – no need to click the body first." },
        logic = "res",
        body = Logic("PRIEST", "res"),
    },
    {
        id = "priest_scream",
        name = { "Psych. Schrei", "Psychic Scream" },
        desc = { "Bricht einen laufenden Zauber ab und wirkt sofort Psychischer Schrei.",
                 "Stops your current cast and uses Psychic Scream right away." },
        why = { "Bricht deinen Zauber ab und wirkt sofort Psychischer Schrei – ein Druck, wenn es brenzlig wird.",
                "Stops your cast and uses Psychic Scream at once – one press when things get dangerous." },
        body = "#showtooltip\n/stopcasting\n/cast {s:8122}",
    },
    {
        id = "priest_focusprayer",
        name = { "Fokus-Gebet", "Focus Prayer" },
        desc = { "Innerer Fokus und beide Schmuckstücke, dann Gebet der Heilung ohne Manakosten.",
                 "Inner Focus and both trinkets, then a free Prayer of Healing." },
        why = { "Innerer Fokus, beide Schmuckstücke und Gebet der Heilung mit einem Druck – nichts vergessen.",
                "Inner Focus, both trinkets and Prayer of Healing in one press – nothing forgotten." },
        without = { "Innerer Fokus, zwei Schmuckstücke und Gebet der Heilung einzeln drücken – vier Tasten.",
                    "Press Inner Focus, both trinkets and Prayer of Healing one by one – four keys." },
        rec = true,
        body = "#showtooltip {s:596}\n/cast {s:14751}\n/use 13\n/use 14\n/cast {s:596}",
        need = 14751,
    },
    {
        id = "priest_burstshadow",
        name = { "Burst Schatten", "Burst Shadow" },
        desc = { "Innerer Fokus und beide Schmuckstücke, dann Gedankenschlag mit höherer Chance auf kritischen Treffer (Mouseover, sonst Ziel).",
                 "Inner Focus and both trinkets, then Mind Blast with a higher critical chance (mouseover, otherwise target)." },
        why = { "Innerer Fokus, beide Schmuckstücke und Gedankenschlag mit einem Druck – nichts vergessen.",
                "Inner Focus, both trinkets and Mind Blast in one press – nothing forgotten." },
        body = "#showtooltip {s:8092}\n/cast {s:14751}\n/use 13\n/use 14\n/cast [@mouseover,harm,nodead][] {s:8092}",
        need = 14751,
    },
    Wand("priest"),
    -- Welle 27 (Paket modul/ezmacro-faehigkeiten): Lücken gegen ezCores Client-Tabellen gefüllt (Kopf der Datei), eigene Texte
    {
        id = "priest_plague",
        name = { "Seuche (MO)", "Plague (MO)" },
        desc = { "Verschlingende Seuche auf den Gegner unter der Maus, sonst aufs Ziel.",
                 "Devouring Plague on the enemy under your mouse, otherwise your target." },
        why = { "Verschlingende Seuche auf einen zweiten Gegner, ohne Zielwechsel – Maus drüber und drücken.",
                "Devouring Plague on a second enemy without switching target – mouse over it and press." },
        body = "#showtooltip\n/cast [@mouseover,harm,nodead][] {s:2944}",
    },
    {
        id = "priest_holyfire",
        name = { "Heil. Feuer (MO)", "Holy Fire (MO)" },
        desc = { "Heiliges Feuer auf den Gegner unter der Maus, sonst aufs Ziel.",
                 "Holy Fire on the enemy under your mouse, otherwise your target." },
        why = { "Heiliges Feuer auf den Gegner unter der Maus, ohne dein Ziel zu wechseln.",
                "Holy Fire on the enemy under your mouse without switching your target." },
        body = "#showtooltip\n/cast [@mouseover,harm,nodead][] {s:14914}",
    },
    {
        id = "priest_mindflay",
        name = { "Schinden (MO)", "Mind Flay (MO)" },
        desc = { "Gedankenschinden (Talent) auf den Gegner unter der Maus, sonst aufs Ziel.",
                 "Mind Flay (talent) on the enemy under your mouse, otherwise your target." },
        why = { "Gedankenschinden auf einen zweiten Gegner, etwa um ihn zu verlangsamen, ohne Zielwechsel.",
                "Mind Flay a second enemy, e.g. to slow it, without switching target." },
        body = "#showtooltip\n/cast [@mouseover,harm,nodead][] {s:15407}",
    },
    {
        id = "priest_silence",
        name = { "Stille (F)", "Silence (F)" },
        desc = { "Bricht deinen eigenen Zauber ab und wirkt Stille (Talent) auf deinen Fokus, ohne Fokus auf dein Ziel.",
                 "Stops your own cast and casts Silence (talent) on your focus, or your target without one." },
        why = { "Unterbrich einen zaubernden Gegner (Fokus), auch mitten in deinem eigenen Zauber, ohne Zielwechsel.",
                "Interrupt a casting enemy (focus), even in the middle of your own cast, without switching target." },
        body = "#showtooltip\n/stopcasting\n/cast [@focus,harm,nodead][] {s:15487}",
    },
})

ns.AddMacros("class", "SHAMAN", {
    {
        id = "shaman_interrupt",
        name = { "Erdschock (F)", "Earth Shock (F)" },
        desc = { "Bricht deinen eigenen Zauber ab; Erdschock unterbricht dann den Zauber deines Fokus, sonst des Ziels.",
                 "Stops your own cast; Earth Shock then interrupts the cast of your focus, otherwise your target." },
        why = { "Unterbrich mit Erdschock einen zweiten Gegner (deinen Fokus), ohne dein Ziel zu wechseln.",
                "Interrupt a second enemy (your focus) with Earth Shock without switching your target." },
        without = { "Zauberer anklicken, Erdschock drücken, dann dein eigentliches Ziel wieder anklicken.",
                    "Click the caster, press Earth Shock, then click your real target again." },
        rec = true,
        logic = "interrupt",
        body = Logic("SHAMAN", "interrupt"),
    },
    {
        id = "shaman_wave",
        name = { "Welle (MO)", "Wave (MO)" },
        desc = { "Geringe Welle der Heilung (schnell), mit Shift Welle der Heilung (stark) – auf den Spieler unter der Maus, sonst aufs Ziel.",
                 "Lesser Healing Wave (fast), with Shift Healing Wave (strong) – on the player under your mouse, otherwise your target." },
        why = { "Geringe Welle der Heilung (Shift: Welle der Heilung) auf wen die Maus zeigt – Ziel bleibt.",
                "Lesser Healing Wave (Shift: Healing Wave) on whoever is under your mouse – target stays." },
        without = { "Spieler im Gruppenfenster anklicken, heilen, dann dein altes Ziel wieder suchen.",
                    "Click the player's frame, cast the heal, then find your old target again." },
        rec = true,
        logic = "wave",
        body = Logic("SHAMAN", "wave"),
        need = 331,
    },
    {
        id = "shaman_chainheal",
        name = { "Kettenheil. (MO)", "Chain Heal (MO)" },
        desc = { "Kettenheilung, beginnend beim Spieler unter der Maus, sonst beim Ziel.",
                 "Chain Heal starting on the player under your mouse, otherwise your target." },
        why = { "Kettenheilung startet beim Spieler unter der Maus – ein Druck, ohne Zielwechsel.",
                "Chain Heal starts on the player under your mouse – one press, no target switch." },
        without = { "Erst den richtigen Spieler anklicken, dann Kettenheilung, dann altes Ziel zurückholen.",
                    "Click the right player first, cast Chain Heal, then get your old target back." },
        rec = true,
        body = "#showtooltip\n/cast [@mouseover,help,nodead][] {s:1064}",
    },
    {
        id = "shaman_purge",
        name = { "Reinigen (MO)", "Purge (MO)" },
        desc = { "Reinigen entfernt nützliche Magie vom Gegner unter der Maus, sonst vom Ziel.",
                 "Purge removes helpful magic from the enemy under your mouse, otherwise your target." },
        why = { "Reinigen nimmt dem Gegner unter der Maus nützliche Magie – ohne ihn erst anzuklicken.",
                "Purge strips helpful magic from the enemy under your mouse – no need to target it first." },
        logic = "purge",
        body = Logic("SHAMAN", "purge"),
    },
    {
        id = "shaman_cure",
        name = { "Gift/Krank. (MO)", "Cure (MO)" },
        desc = { "Vergiftung heilen beim Spieler unter der Maus, sonst beim freundlichen Ziel, sonst bei dir. Shift: Krankheit heilen.",
                 "Cure Poison on the player under your mouse, otherwise your friendly target, otherwise you. Shift: Cure Disease." },
        why = { "Vergiftung heilen (Shift: Krankheit heilen) auf den Spieler unter der Maus – ohne Zielwechsel.",
                "Cure Poison (Shift: Cure Disease) on the player under your mouse – no target switch." },
        -- Umschalt in ezCores Kurzform „exists,noharm“: mit den langen Gruppen-Glieder in beiden Schritten wäre der Text
        -- länger als Blizzards 255 Zeichen (Spieltest 15.11.2026, kein Durchrutschen auf das Ziel)
        body = "#showtooltip\n/cast [mod:shift,@mouseover,exists,noharm][mod:shift,help,nodead][mod:shift,@player] {s:2870}; [@mouseover,help,nodead][help,nodead][@player] {s:526}",
        need = 526,
    },
    {
        id = "shaman_totems",
        name = { "Totem-Reihe", "Totem Sequence" },
        desc = { "Jeder Druck setzt das nächste Totem: Erdstärke, Heilender Fluss, Verbrennung, Windzorn. Beginnt nach dem Kampf oder nach 30 s von vorn. Totems im Text nach Bedarf tauschen.",
                 "Each press drops the next totem: Strength of Earth, Healing Stream, Searing, Windfury. Restarts after combat or 30 sec. Swap totems in the text as you like." },
        why = { "Vier Totems nacheinander auf einer Taste – du drückst trotzdem viermal, sparst nur Plätze.",
                "Four totems in a row on one key – you still press four times, it only saves bar slots." },
        body = "#showtooltip\n/castsequence reset=combat/30 {s:8075}, {s:5394}, {s:3599}, {s:8512}",
    },
    {
        id = "shaman_res",
        name = { "Ahnengeist (MO)", "Anc. Spirit (MO)" },
        desc = { "Geist der Ahnen auf den toten Spieler unter der Maus, sonst aufs Ziel.",
                 "Ancestral Spirit on the dead player under your mouse, otherwise your target." },
        why = { "Geist der Ahnen auf den toten Spieler unter der Maus – kein Anklicken der Leiche nötig.",
                "Ancestral Spirit on the dead player under your mouse – no need to click the body first." },
        logic = "res",
        body = Logic("SHAMAN", "res"),
    },
    {
        id = "shaman_wolf",
        name = { "Geisterwolf", "Ghost Wolf" },
        desc = { "Verwandelt dich in den Geisterwolf, erneut drücken verwandelt dich zurück.",
                 "Turns you into a Ghost Wolf, press again to turn back." },
        why = { "Geisterwolf an und wieder aus mit derselben Taste – das kann der normale Knopf meist auch.",
                "Ghost Wolf on and off with the same key – the normal spell button mostly does this too." },
        logic = "wolf",
        body = Logic("SHAMAN", "wolf", { tip = 2645, after = "/cancelform [form]" }),
    },
    {
        id = "shaman_burst",
        name = { "Burst Elementar", "Burst Elemental" },
        desc = { "Elementarbeherrschung und beide Schmuckstücke, dann ein sicher kritischer Kettenblitzschlag (Mouseover, sonst Ziel).",
                 "Elemental Mastery and both trinkets, then a guaranteed critical Chain Lightning (mouseover, otherwise target)." },
        why = { "Elementarbeherrschung, Schmuckstücke und Kettenblitzschlag in einem Druck – nichts vergessen.",
                "Elemental Mastery, both trinkets and Chain Lightning in one press – nothing forgotten." },
        without = { "Elementarbeherrschung, zwei Schmuckstücke und Kettenblitzschlag einzeln – vier Tasten.",
                    "Press Elemental Mastery, both trinkets and Chain Lightning one by one – four keys." },
        rec = true,
        body = "#showtooltip {s:421}\n/cast {s:16166}\n/use 13\n/use 14\n/cast [@mouseover,harm,nodead][] {s:421}",
        need = 16166,
    },
    {
        id = "shaman_emergency",
        name = { "Notfall-Welle", "Emergency Wave" },
        desc = { "Schnelligkeit der Natur und beide Schmuckstücke, dann sofort Welle der Heilung – auf Mouseover, Ziel oder dich.",
                 "Nature's Swiftness and both trinkets, then an instant Healing Wave – on mouseover, target or yourself." },
        why = { "Schnelligkeit der Natur, Schmuckstücke und sofort Welle der Heilung – ein Druck im Notfall.",
                "Nature's Swiftness, trinkets and an instant Healing Wave – one press in an emergency." },
        without = { "Schnelligkeit der Natur, zwei Schmuckstücke, Spieler anklicken, Welle der Heilung.",
                    "Press Nature's Swiftness, both trinkets, click the player, then cast Healing Wave." },
        rec = true,
        body = "#showtooltip {s:331}\n/cast {s:16188}\n/use 13\n/use 14\n/cast [@mouseover,help,nodead][help,nodead][@player] {s:331}",
        need = 16188,
    },
    -- Welle 27 (Paket modul/ezmacro-faehigkeiten): Lücken gegen ezCores Client-Tabellen gefüllt (Kopf der Datei), eigene Texte
    {
        id = "shaman_flameshock",
        name = { "Flammensch. (MO)", "Flame Shock (MO)" },
        desc = { "Flammenschock auf den Gegner unter der Maus, sonst aufs Ziel – zum Verteilen auf mehrere Gegner.",
                 "Flame Shock on the enemy under your mouse, otherwise your target – for spreading it on several enemies." },
        why = { "Verteile Flammenschock auf mehrere Gegner: Maus drüber halten und drücken, ohne Zielwechsel.",
                "Spread Flame Shock on several enemies: mouse over each and press, no target switching." },
        body = "#showtooltip\n/cast [@mouseover,harm,nodead][] {s:8050}",
    },
})

ns.AddMacros("class", "MAGE", {
    {
        id = "mage_counterspell",
        name = { "Gegenzauber (F)", "Counterspell (F)" },
        desc = { "Bricht deinen eigenen Zauber ab und wirkt Gegenzauber auf deinen Fokus, ohne Fokus aufs Ziel.",
                 "Stops your own cast and uses Counterspell on your focus, or your target without one." },
        why = { "Unterbrich deinen Fokus-Gegner mit Gegenzauber, ohne dein Ziel zu wechseln.",
                "Interrupt your focus enemy with Counterspell without switching away from your target." },
        without = { "Den Zaubernden anklicken, Gegenzauber drücken, dann zurück zum alten Ziel.",
                    "Click the caster, press Counterspell, then switch back to your old target." },
        rec = true,
        logic = "counterspell",
        body = Logic("MAGE", "counterspell"),
    },
    {
        id = "mage_polymorph",
        name = { "Verwandlung (F)", "Polymorph (F)" },
        desc = { "Verwandelt deinen Fokus, sonst den Gegner unter der Maus, sonst das Ziel. Tipp: das Schaf vorher mit „Fokus setzen“ (Allgemein) markieren.",
                 "Polymorphs your focus, otherwise the enemy under your mouse, otherwise your target. Tip: mark the sheep first with \"Set Focus\" (General)." },
        why = { "Verwandlung trifft deinen Fokus oder den Gegner unter der Maus – dein Ziel bleibt dasselbe.",
                "Polymorph hits your focus or the enemy under your mouse – your target stays the same." },
        without = { "Das Schaf anklicken, Verwandlung zaubern, dann dein eigentliches Ziel wieder suchen.",
                    "Click the sheep, cast Polymorph, then find and click your real target again." },
        rec = true,
        logic = "polymorph",
        body = Logic("MAGE", "polymorph"),
    },
    {
        id = "mage_iceblock",
        name = { "Eisblock", "Ice Block" },
        desc = { "Erster Druck: Eisblock (Talent), auch mitten in einem eigenen Zauber. Erneut drücken beendet ihn vorzeitig.",
                 "First press: Ice Block (talent), even in the middle of your own cast. Press again to end it early." },
        why = { "Ein Knopf für Eisblock: einmal drücken schützt dich, nochmal drücken beendet ihn sofort.",
                "One key for Ice Block: press to protect yourself, press again to end it right away." },
        body = "#showtooltip\n/stopcasting\n/cancelaura {s:11958}\n/cast {s:11958}",
    },
    {
        id = "mage_instantpyro",
        name = { "Sofort-Pyro", "Instant Pyro" },
        desc = { "Geistesgegenwart (Talent) und sofort ein Pyroschlag ohne Zauberzeit.",
                 "Presence of Mind (talent) and an instant Pyroblast right away." },
        why = { "Geistesgegenwart und gleich danach Pyroschlag – ein Knopf statt zwei.",
                "Presence of Mind and right after it Pyroblast – one key instead of two." },
        body = "#showtooltip {s:11366}\n/cast {s:12043}\n/cast {s:11366}",
        need = 12043,
    },
    {
        id = "mage_intellect",
        name = { "Intelligenz (MO)", "Intellect (MO)" },
        desc = { "Arkane Intelligenz auf den Spieler unter der Maus, sonst aufs Ziel. Shift: Arkane Brillanz für die ganze Gruppe.",
                 "Arcane Intellect on the player under your mouse, otherwise your target. Shift: Arcane Brilliance for the whole group." },
        why = { "Arkane Intelligenz verteilen, ohne jeden Mitspieler anzuklicken. Shift: Arkane Brillanz.",
                "Hand out Arcane Intellect without clicking each player. Shift: Arcane Brilliance." },
        body = "#showtooltip\n/cast [mod:shift] {s:23028}; [@mouseover,help,nodead][] {s:1459}",
        need = 1459,
    },
    {
        id = "mage_decurse",
        name = { "Fluch weg (MO)", "Decurse (MO)" },
        desc = { "Geringen Fluch aufheben beim Spieler unter der Maus, sonst beim freundlichen Ziel, sonst bei dir.",
                 "Remove Lesser Curse on the player under your mouse, otherwise your friendly target, otherwise you." },
        why = { "Geringen Fluch aufheben beim Spieler unter der Maus – du musst dein Ziel nicht wechseln.",
                "Remove Lesser Curse on the player under your mouse – no need to switch your target." },
        without = { "Mitspieler anklicken, Geringen Fluch aufheben drücken, dann den Gegner wieder anklicken.",
                    "Click the player, cast Remove Lesser Curse, then click the enemy again." },
        rec = true,
        logic = "decurse",
        body = Logic("MAGE", "decurse"),
    },
    {
        id = "mage_conjure",
        name = { "Herbeizaubern", "Conjure" },
        desc = { "Wasser herbeizaubern, mit Shift Essen.",
                 "Conjure Water, with Shift Conjure Food." },
        why = { "Wasser herbeizaubern und mit Shift Essen auf einem Knopf – spart einen Platz auf der Leiste.",
                "Conjure Water and, with Shift, Conjure Food on one key – saves a slot on your bar." },
        body = "#showtooltip\n/cast [mod:shift] {s:587}; {s:5504}",
        need = 5504,
    },
    {
        id = "mage_aoe",
        name = { "Fläche (Maus)", "AoE at Cursor" },
        desc = { "Blizzard sofort dort, wo die Maus zeigt. Shift: Flammenstoß.",
                 "Blizzard right where your mouse points. Shift: Flamestrike." },
        why = { "Blizzard landet sofort dort, wo die Maus zeigt – kein extra Klick. Shift: Flammenstoß.",
                "Blizzard lands right where your mouse points – no extra click. Shift: Flamestrike." },
        body = "#showtooltip\n/cast [mod:shift,@cursor] {s:2120}; [@cursor] {s:10}",
        need = 10,
    },
    {
        id = "mage_slowfall",
        name = { "Lgs. Fall (MO)", "Slow Fall (MO)" },
        desc = { "Langsamer Fall auf den Spieler unter der Maus, sonst aufs freundliche Ziel, sonst auf dich.",
                 "Slow Fall on the player under your mouse, otherwise your friendly target, otherwise you." },
        why = { "Langsamer Fall auf den Spieler unter der Maus oder dich – praktisch an Klippen, selten nötig.",
                "Slow Fall on the player under your mouse or yourself – handy at cliffs, rarely needed." },
        body = "#showtooltip\n/cast [@mouseover,help,nodead][help,nodead][@player] {s:130}",
    },
    {
        id = "mage_burstarcane",
        name = { "Burst Arkan", "Burst Arcane" },
        desc = { "Arkane Macht, Geistesgegenwart und beide Schmuckstücke, dann ein sofortiger Feuerball – ohne Feuer-Talente. Mit Pyroschlag-Talent: „Sofort-Pyro“.",
                 "Arcane Power, Presence of Mind and both trinkets, then an instant Fireball – no Fire talents needed. With the Pyroblast talent: Instant Pyro." },
        why = { "Arkane Macht, Geistesgegenwart, Schmuckstücke und ein sofortiger Feuerball – ein Knopf.",
                "Arcane Power, Presence of Mind, both trinkets and an instant Fireball – one press." },
        without = { "Fünf Tasten einzeln drücken – leicht vergisst du ein Schmuckstück oder eine Abklingzeit.",
                    "Press five keys one by one – easy to forget a trinket or a cooldown." },
        rec = true,
        body = "#showtooltip {s:133}\n/cast {s:12042}\n/cast {s:12043}\n/use 13\n/use 14\n/cast [@mouseover,harm,nodead][] {s:133}",
        need = 12042,
    },
    {
        id = "mage_burstfire",
        name = { "Burst Feuer", "Burst Fire" },
        desc = { "Verbrennen und beide Schmuckstücke, dann Feuerball (Mouseover, sonst Ziel).",
                 "Combustion and both trinkets, then Fireball (mouseover, otherwise target)." },
        why = { "Verbrennen, beide Schmuckstücke und Feuerball auf einem Knopf – keine Abklingzeit vergessen.",
                "Combustion, both trinkets and Fireball on one key – no cooldown gets forgotten." },
        without = { "Verbrennen, zwei Schmuckstücke und Feuerball einzeln drücken – vier Tasten.",
                    "Press Combustion, two trinkets and Fireball separately – four keys." },
        rec = true,
        body = "#showtooltip {s:133}\n/cast {s:11129}\n/use 13\n/use 14\n/cast [@mouseover,harm,nodead][] {s:133}",
        need = 11129,
    },
    Wand("mage"),
})

ns.AddMacros("class", "WARLOCK", {
    {
        id = "warlock_spelllock",
        name = { "Zaubersperre (F)", "Spell Lock (F)" },
        desc = { "Dein Teufelsjäger unterbricht deinen Fokus, ohne Fokus das Ziel.",
                 "Your Felhunter interrupts your focus, or your target without one." },
        why = { "Dein Teufelsjäger unterbricht mit Zaubersperre deinen Fokus – dein Ziel bleibt, wie es ist.",
                "Your Felhunter uses Spell Lock on your focus – your own target stays as it is." },
        without = { "Den Zaubernden anklicken, Zaubersperre auf der Dämonenleiste klicken, zurück zum Ziel.",
                    "Click the caster, click Spell Lock on the pet bar, then click your target again." },
        rec = true,
        body = "#showtooltip {s:19244}\n/cast [@focus,harm,nodead][] {s:19244}",
        need = 691,
    },
    {
        id = "warlock_fear",
        name = { "Furcht (F)", "Fear (F)" },
        desc = { "Furcht auf deinen Fokus, sonst auf den Gegner unter der Maus oder das Ziel.",
                 "Fear on your focus, otherwise the enemy under your mouse or your target." },
        why = { "Schick einen zweiten Gegner mit Furcht weg (Fokus oder Maus), ohne dein Ziel zu wechseln.",
                "Send a second enemy away with Fear (focus or mouse) without switching your target." },
        without = { "Den zweiten Gegner anklicken, Furcht zaubern, dann dein Ziel wieder anklicken.",
                    "Click the second enemy, cast Fear, then click your target again." },
        rec = true,
        logic = "fear",
        body = Logic("WARLOCK", "fear"),
    },
    {
        id = "warlock_banish",
        name = { "Verbannen (F)", "Banish (F)" },
        desc = { "Verbannen auf deinen Fokus, sonst auf den Gegner unter der Maus oder das Ziel.",
                 "Banish on your focus, otherwise the enemy under your mouse or your target." },
        why = { "Verbannen auf Fokus oder Gegner unter der Maus, ohne Zielwechsel – nur gegen Dämonen und Elementare.",
                "Banish your focus or the enemy under your mouse, no retargeting – only on demons and elementals." },
        body = "#showtooltip\n/cast [@focus,harm,nodead][@mouseover,harm,nodead][] {s:710}",
    },
    {
        id = "warlock_seduction",
        name = { "Verführung (F)", "Seduction (F)" },
        desc = { "Deine Sukkubus verführt deinen Fokus, ohne Fokus das Ziel.",
                 "Your Succubus seduces your focus, or your target without one." },
        why = { "Deine Sukkubus verführt deinen Fokus – du behältst dein Ziel und klickst nicht die Dämonenleiste.",
                "Your Succubus seduces your focus – you keep your target and skip the pet bar." },
        without = { "Gegner anklicken, Verführung auf der Dämonenleiste klicken, dann zurück zum Ziel.",
                    "Click the enemy, click Seduction on the pet bar, then click your target again." },
        rec = true,
        body = "#showtooltip {s:6358}\n/cast [@focus,harm,nodead][] {s:6358}",
        need = 712,
    },
    {
        id = "warlock_petattack",
        name = { "Diener: Angriff", "Pet Attack" },
        desc = { "Schickt deinen Diener auf den Gegner unter der Maus, sonst auf dein Ziel.",
                 "Sends your demon at the enemy under your mouse, otherwise your target." },
        why = { "Schick deinen Dämon auf den Gegner unter der Maus – dein eigenes Ziel bleibt.",
                "Send your demon at the enemy under your mouse – your own target stays." },
        body = "/petattack [@mouseover,harm,nodead][]",
        icon = "Ability_GhoulFrenzy",
        need = false,
    },
    {
        id = "warlock_corruption",
        name = { "Verderbnis (MO)", "Corruption (MO)" },
        desc = { "Verderbnis auf den Gegner unter der Maus, sonst aufs Ziel – zum Verteilen auf mehrere Gegner.",
                 "Corruption on the enemy under your mouse, otherwise your target – for spreading it on several enemies." },
        why = { "Verteile Verderbnis auf mehrere Gegner: Maus drüber halten und drücken, ohne Zielwechsel.",
                "Spread Corruption on several enemies: mouse over each and press, no target switching." },
        without = { "Jeden Gegner einzeln anklicken, Verderbnis zaubern und danach dein Ziel neu wählen.",
                    "Click each enemy, cast Corruption, then pick your main target again." },
        rec = true,
        body = "#showtooltip\n/cast [@mouseover,harm,nodead][] {s:172}",
    },
    {
        id = "warlock_agony",
        name = { "Pein (MO)", "Agony (MO)" },
        desc = { "Fluch der Pein auf den Gegner unter der Maus, sonst aufs Ziel.",
                 "Curse of Agony on the enemy under your mouse, otherwise your target." },
        why = { "Verteile Fluch der Pein auf mehrere Gegner, indem du nur die Maus darüber hältst und drückst.",
                "Spread Curse of Agony on several enemies by just holding the mouse over them and pressing." },
        without = { "Jeden Gegner einzeln anklicken, Fluch der Pein zaubern und danach dein Ziel neu wählen.",
                    "Click each enemy, cast Curse of Agony, then pick your main target again." },
        rec = true,
        body = "#showtooltip\n/cast [@mouseover,harm,nodead][] {s:980}",
    },
    {
        id = "warlock_instantdemon",
        name = { "Sofort-Diener", "Instant Demon" },
        desc = { "Teufelsbeherrschung (Talent) und sofort ein Diener: Teufelsjäger, Shift: Leerwandler, Strg: Sukkubus, Alt: Wichtel.",
                 "Fel Domination (talent) and a demon right away: Felhunter, Shift: Voidwalker, Ctrl: Succubus, Alt: Imp." },
        why = { "Teufelsbeherrschung und sofort ein Dämon – ein Knopf statt zwei; Shift, Strg, Alt wählen ihn.",
                "Fel Domination and a demon in one press instead of two; Shift, Ctrl or Alt picks the demon." },
        body = "#showtooltip\n/cast {s:18708}\n/cast [mod:shift] {s:697}; [mod:ctrl] {s:712}; [mod:alt] {s:688}; {s:691}",
    },
    {
        id = "warlock_deathcoil",
        name = { "Todesmantel (MO)", "Death Coil (MO)" },
        desc = { "Todesmantel auf den Gegner unter der Maus, sonst aufs Ziel.",
                 "Death Coil on the enemy under your mouse, otherwise your target." },
        why = { "Todesmantel auf den Gegner unter der Maus, ohne dein Ziel zu wechseln – z. B. auf einen Angreifer.",
                "Death Coil the enemy under your mouse without switching target – e.g. one attacking you." },
        body = "#showtooltip\n/cast [@mouseover,harm,nodead][] {s:6789}",
    },
    {
        id = "warlock_amplify",
        name = { "Fluch verstärkt", "Amplified Curse" },
        desc = { "Fluch verstärken, dann Fluch der Pein; mit Shift Fluch der Erschöpfung (Mouseover, sonst Ziel).",
                 "Amplify Curse, then Curse of Agony; with Shift Curse of Exhaustion (mouseover, otherwise target)." },
        why = { "Fluch verstärken und Fluch der Pein mit einem Druck statt zwei. Shift: Fluch der Erschöpfung.",
                "Amplify Curse and Curse of Agony in one press instead of two. Shift: Curse of Exhaustion." },
        body = "#showtooltip\n/cast {s:18288}\n/cast [mod:shift,@mouseover,harm,nodead][mod:shift] {s:18223}; [@mouseover,harm,nodead][] {s:980}",
        need = 18288,
    },
    {
        id = "warlock_burst",
        name = { "Burst Hexer", "Burst Warlock" },
        desc = { "Dein Dämon greift an, beide Schmuckstücke, dann Schattenblitz (Mouseover, sonst Ziel).",
                 "Your demon attacks, both trinkets, then Shadow Bolt (mouseover, otherwise target)." },
        why = { "Dämon, Schmuckstücke und Schattenblitz auf einem Knopf – lohnt nur mit aktiven Schmuckstücken.",
                "Demon attacks, trinkets and Shadow Bolt on one key – only worth it with usable trinkets." },
        -- Logik „petBolt“ mit den Schmuckstücken zwischen /petattack und /cast (Welle 23, A4)
        logic = "petBolt",
        body = Logic("WARLOCK", "petBolt", { tip = 686, before = PRE_LINES.trinkets }),
    },
    Wand("warlock"),
    -- Welle 9 (UE-26): neu aus ezCores Klassen-Wissen (Makro-Logik „petBolt“ und „drain“), eigene Texte
    {
        id = "warlock_petbolt",
        name = { "Blitz+Dämon (MO)", "Bolt+Demon (MO)" },
        desc = { "Schickt deinen Dämon auf den Gegner unter der Maus, sonst auf dein Ziel, und wirkt dort Schattenblitz.",
                 "Sends your demon at the enemy under your mouse, otherwise your target, and casts Shadow Bolt on it." },
        why = { "Dämon und Schattenblitz treffen denselben Gegner – mit einem Druck.",
                "Demon and Shadow Bolt hit the same enemy – in one press." },
        logic = "petBolt",
        body = Logic("WARLOCK", "petBolt"),
    },
    {
        id = "warlock_drain",
        name = { "Blutsauger (MO)", "Drain Life (MO)" },
        desc = { "Blutsauger auf den Gegner unter der Maus, sonst auf dein Ziel. Läuft schon ein kanalisierter Zauber, bricht erneutes Drücken ihn nicht ab.",
                 "Drain Life on the enemy under your mouse, otherwise your target. While a channelled spell is running, pressing again does not cut it short." },
        why = { "Blutsauger auf einer Taste, die du gefahrlos mehrfach drücken kannst.",
                "Drain Life on a key you can safely press again and again." },
        logic = "drain",
        body = Logic("WARLOCK", "drain"),
    },
    -- Welle 27 (Paket modul/ezmacro-faehigkeiten): Lücken gegen ezCores Client-Tabellen gefüllt (Kopf der Datei), eigene Texte
    {
        id = "warlock_immolate",
        name = { "Feuerbrand (MO)", "Immolate (MO)" },
        desc = { "Feuerbrand auf den Gegner unter der Maus, sonst aufs Ziel – zum Verteilen auf mehrere Gegner.",
                 "Immolate on the enemy under your mouse, otherwise your target – for spreading it on several enemies." },
        why = { "Verteile Feuerbrand auf mehrere Gegner: Maus drüber halten und drücken, ohne Zielwechsel.",
                "Spread Immolate on several enemies: mouse over each and press, no target switching." },
        without = { "Jeden Gegner einzeln anklicken, Feuerbrand zaubern und danach dein Ziel neu wählen.",
                    "Click each enemy, cast Immolate, then pick your main target again." },
        rec = true,
        body = "#showtooltip\n/cast [@mouseover,harm,nodead][] {s:348}",
    },
    {
        id = "warlock_curses",
        name = { "Flüche (MO)", "Curses (MO)" },
        desc = { "Fluch der Schwäche; Shift: Fluch der Elemente, Strg: Fluch der Tollkühnheit, Alt: Fluch der Sprachen – auf den Gegner unter der Maus, sonst aufs Ziel.",
                 "Curse of Weakness; Shift: Curse of the Elements, Ctrl: Curse of Recklessness, Alt: Curse of Tongues – on the enemy under your mouse, otherwise your target." },
        why = { "Alle Flüche auf einer Taste: Shift, Strg oder Alt wählen den Fluch, die Maus den Gegner.",
                "All curses on one key: Shift, Ctrl or Alt pick the curse, the mouse picks the enemy." },
        need = 702,
        -- ohne „nodead“ an den vier Maus-Gliedern: mit den echten Namen („Fluch der Tollkühnheit“ …) lag der Text sonst
        -- bei 262 Bytes, über Blizzards 255 (Fund des code-reviewers vor dem Merge, 16.11.2026); ein toter Gegner unter
        -- der Maus nimmt keinen Fluch an, der Client meldet es
        body = "#showtooltip\n/cast [mod:shift,@mouseover,harm][mod:shift] {s:440892}; [mod:ctrl,@mouseover,harm][mod:ctrl] {s:704}; [mod:alt,@mouseover,harm][mod:alt] {s:1714}; [@mouseover,harm][] {s:702}",
    },
    {
        id = "warlock_siphon",
        name = { "Lebensentz. (MO)", "Siphon Life (MO)" },
        desc = { "Lebensentzug (Talent) auf den Gegner unter der Maus, sonst aufs Ziel.",
                 "Siphon Life (talent) on the enemy under your mouse, otherwise your target." },
        why = { "Verteile Lebensentzug auf mehrere Gegner, ohne dein Ziel zu wechseln.",
                "Spread Siphon Life on several enemies without switching your target." },
        body = "#showtooltip\n/cast [@mouseover,harm,nodead][] {s:18265}",
    },
    {
        id = "warlock_doom",
        name = { "Verdammnis (MO)", "Doom (MO)" },
        desc = { "Omen der Verdammnis auf den Gegner unter der Maus, sonst aufs Ziel.",
                 "Bane of Doom on the enemy under your mouse, otherwise your target." },
        why = { "Omen der Verdammnis auf einen zähen Gegner unter der Maus, ohne dein Ziel zu wechseln.",
                "Bane of Doom on a tough enemy under your mouse without switching your target." },
        body = "#showtooltip\n/cast [@mouseover,harm,nodead][] {s:603}",
    },
    {
        id = "warlock_drainsoul",
        name = { "Seelendieb (MO)", "Drain Soul (MO)" },
        desc = { "Seelendieb auf den Gegner unter der Maus, sonst aufs Ziel – stirbt er dabei, bekommst du einen Seelensplitter.",
                 "Drain Soul on the enemy under your mouse, otherwise your target – if it dies meanwhile, you get a soul shard." },
        why = { "Hol dir Seelensplitter von einem sterbenden Gegner unter der Maus, ohne Zielwechsel.",
                "Get soul shards from a dying enemy under your mouse without switching target." },
        body = "#showtooltip\n/cast [@mouseover,harm,nodead][] {s:1120}",
    },
})

ns.AddMacros("class", "DRUID", {
    {
        id = "druid_rejuv",
        name = { "Verjüngung (MO)", "Rejuv (MO)" },
        desc = { "Verjüngung auf den Spieler unter der Maus, sonst aufs freundliche Ziel, sonst auf dich.",
                 "Rejuvenation on the player under your mouse, otherwise your friendly target, otherwise you." },
        why = { "Verjüngung auf Mitspieler, indem du nur die Maus über sie hältst und drückst – dein Ziel bleibt.",
                "Rejuvenation on any player by just mousing over them and pressing – your target stays." },
        without = { "Mitspieler anklicken, Verjüngung drücken, dann zurück zum Gegner oder Tank klicken.",
                    "Click the player, cast Rejuvenation, then click back to the enemy or tank." },
        rec = true,
        body = "#showtooltip\n/cast [@mouseover,help,nodead][help,nodead][@player] {s:774}",
    },
    {
        id = "druid_touch",
        name = { "Berührung (MO)", "Touch (MO)" },
        desc = { "Heilende Berührung, mit Shift Nachwachsen – auf den Spieler unter der Maus, sonst aufs Ziel.",
                 "Healing Touch, with Shift Regrowth – on the player under your mouse, otherwise your target." },
        why = { "Heilende Berührung (Shift: Nachwachsen) auf den Spieler unter der Maus – kein Zielwechsel.",
                "Healing Touch (Shift: Regrowth) on the player under your mouse – no target switching." },
        without = { "Mitspieler anklicken, Heilende Berührung oder Nachwachsen drücken, Ziel zurückholen.",
                    "Click the player, cast Healing Touch or Regrowth, then get your old target back." },
        rec = true,
        body = "#showtooltip\n/cast [mod:shift,@mouseover,help,nodead][mod:shift] {s:8936}; [@mouseover,help,nodead][] {s:5185}",
        need = 5185,
    },
    {
        id = "druid_innervate",
        name = { "Anregen (MO)", "Innervate (MO)" },
        desc = { "Anregen auf den Spieler unter der Maus, sonst aufs freundliche Ziel, sonst auf dich.",
                 "Innervate on the player under your mouse, otherwise your friendly target, otherwise you." },
        why = { "Gib Anregen dem Spieler unter der Maus, ohne ihn erst anzuklicken – meist einem Heiler.",
                "Give Innervate to the player under your mouse without clicking them first – usually a healer." },
        logic = "innervate",
        body = Logic("DRUID", "innervate"),
    },
    {
        id = "druid_rebirth",
        name = { "Wiedergeb. (MO)", "Rebirth (MO)" },
        desc = { "Wiedergeburt auf den toten Spieler unter der Maus, sonst aufs tote Ziel.",
                 "Rebirth on the dead player under your mouse, otherwise your dead target." },
        why = { "Wiedergeburt auf den toten Spieler unter der Maus – du musst ihn nicht erst anklicken.",
                "Rebirth on the dead player under your mouse – no need to click them first." },
        logic = "rebirth",
        body = Logic("DRUID", "rebirth"),
    },
    {
        id = "druid_revive",
        name = { "Wiederbel. (MO)", "Revive (MO)" },
        desc = { "Wiederbeleben auf den toten Spieler unter der Maus, sonst aufs Ziel – außerhalb des Kampfes.",
                 "Revive on the dead player under your mouse, otherwise your target – out of combat." },
        why = { "Wiederbeleben auf den toten Spieler unter der Maus – kein Anklicken der Leiche nötig.",
                "Revive on the dead player under your mouse – no need to click the body first." },
        logic = "revive",
        body = Logic("DRUID", "revive"),
    },
    {
        id = "druid_cure",
        name = { "Fluch/Gift (MO)", "Curse/Poison MO" },
        desc = { "Fluch aufheben beim Spieler unter der Maus, sonst beim freundlichen Ziel, sonst bei dir. Shift: Vergiftung aufheben.",
                 "Remove Curse on the player under your mouse, otherwise your friendly target, otherwise you. Shift: Abolish Poison." },
        why = { "Fluch aufheben (Shift: Vergiftung aufheben) beim Spieler unter der Maus – dein Ziel bleibt.",
                "Remove Curse (Shift: Abolish Poison) on the player under your mouse – your target stays." },
        without = { "Mitspieler anklicken, Fluch aufheben oder Vergiftung aufheben drücken, zurückwechseln.",
                    "Click the player, cast Remove Curse or Abolish Poison, then switch back." },
        rec = true,
        -- Umschalt in ezCores Kurzform „exists,noharm“: mit den langen Gruppen-Glieder in beiden Schritten wäre der Text
        -- länger als Blizzards 255 Zeichen (Spieltest 15.11.2026, kein Durchrutschen auf das Ziel)
        logic = "decurse",
        body = Logic("DRUID", "decurse", { steps = { { short = true } } }),
        need = 2782,
    },
    {
        id = "druid_roots",
        name = { "Wurzeln (F)", "Roots (F)" },
        desc = { "Wucherwurzeln auf deinen Fokus, sonst auf den Gegner unter der Maus oder das Ziel.",
                 "Entangling Roots on your focus, otherwise the enemy under your mouse or your target." },
        why = { "Halte einen zweiten Gegner mit Wucherwurzeln fest (Fokus oder Maus), ohne Zielwechsel.",
                "Hold a second enemy with Entangling Roots (focus or mouse) without switching your target." },
        body = "#showtooltip\n/cast [@focus,harm,nodead][@mouseover,harm,nodead][] {s:339}",
    },
    {
        id = "druid_hibernate",
        name = { "Winterschlaf (F)", "Hibernate (F)" },
        desc = { "Winterschlaf auf deinen Fokus, sonst auf den Gegner unter der Maus oder das Ziel.",
                 "Hibernate on your focus, otherwise the enemy under your mouse or your target." },
        why = { "Winterschlaf auf Fokus oder Gegner unter der Maus, ohne Zielwechsel – nur Wildtiere und Drachkin.",
                "Hibernate your focus or the enemy under your mouse, no retargeting – only beasts and dragonkin." },
        body = "#showtooltip\n/cast [@focus,harm,nodead][@mouseover,harm,nodead][] {s:2637}",
    },
    {
        id = "druid_cat",
        name = { "Katze/Powershift", "Cat/Powershift" },
        desc = { "Wechselt aus jeder Gestalt in die Katze. In Katzengestalt: Powershift – neue Gestalt und mit dem Talent Furor frische Energie.",
                 "Shifts into Cat Form from any form. In Cat Form: powershift – a fresh form and, with the Furor talent, fresh energy." },
        why = { "Aus jeder Gestalt mit einem Knopf in die Katze; in der Katze gibt's so frische Energie (Talent).",
                "One key into Cat Form from any form; in Cat Form it reshifts for fresh energy (with Furor)." },
        without = { "Erst die alte Gestalt verlassen, dann Katzengestalt drücken – zwei Tasten, jedes Mal.",
                    "Leave your current form first, then press Cat Form – two keys every time." },
        rec = true,
        body = "#showtooltip {s:768}\n/cancelform [form]\n/cast {s:768}",
    },
    {
        id = "druid_travel",
        name = { "Reisen", "Travel" },
        desc = { "Im Wasser Wassergestalt, draußen Reisegestalt. Erneut drücken verwandelt dich zurück.",
                 "Aquatic Form in water, Travel Form outdoors. Press again to turn back." },
        why = { "Ein Knopf wählt selbst: im Wasser Wassergestalt, draußen Reisegestalt – spart einen Platz.",
                "One key picks for you: Aquatic Form in water, Travel Form outdoors – saves a bar slot." },
        body = "#showtooltip\n/cast [swimming] {s:1066}; [outdoors] {s:783}",
        need = 783,
    },
    {
        id = "druid_growl",
        name = { "Knurren (MO)", "Growl (MO)" },
        desc = { "Außerhalb der Bärengestalt wechselt der erste Druck in die (Terror-)Bärengestalt. In ihr: Knurren auf den Gegner unter der Maus, sonst aufs Ziel, und der Nahkampf beginnt.",
                 "Outside Bear Form the first press shifts into (Dire) Bear Form. In it: Growl on the enemy under your mouse, otherwise your target, and melee starts." },
        why = { "Knurren aus jeder Gestalt: erst Bär, dann Spott und Nahkampf – halten musst du ihn mit Angriffen.",
                "Growl from any form: bear first, then taunt and melee – you still have to hit it to keep it." },
        body = "#showtooltip {s:6795}\n/cancelform [noform:1]\n/cast [noform:1] {s:9634|5487}; [@mouseover,harm,nodead][] {s:6795}\n/startattack [form:1,harm,nodead]",
    },
    {
        id = "druid_prowl",
        name = { "Schleich-Öffner", "Prowl Opener" },
        desc = { "Erster Druck: Schleichen (Katzengestalt). Danach Anspringen.",
                 "First press: Prowl (Cat Form). Then Pounce." },
        why = { "Schleichen und danach Anspringen auf einem Knopf – du deckst dich nicht aus Versehen auf.",
                "Prowl, then Pounce on the same key – you can't break your own stealth by pressing twice." },
        body = "#showtooltip\n/cast [nostealth] {s:5215}; {s:9005}",
        need = 5215,
    },
    {
        id = "druid_moonfire",
        name = { "Mondfeuer (MO)", "Moonfire (MO)" },
        desc = { "Mondfeuer auf den Gegner unter der Maus, sonst aufs Ziel.",
                 "Moonfire on the enemy under your mouse, otherwise your target." },
        why = { "Mondfeuer auf den Gegner unter der Maus – so verteilst du es auf mehrere, ohne Zielwechsel.",
                "Moonfire on the enemy under your mouse – spread it on several enemies without retargeting." },
        body = "#showtooltip\n/cast [@mouseover,harm,nodead][] {s:8921}",
    },
    {
        id = "druid_emergency",
        name = { "Sofort-Berührung", "Instant Touch" },
        desc = { "Verlässt jede Gestalt, Schnelligkeit der Natur und beide Schmuckstücke, dann sofort Heilende Berührung – auf Mouseover, Ziel oder dich.",
                 "Leaves any form, Nature's Swiftness and both trinkets, then an instant Healing Touch – on mouseover, target or yourself." },
        why = { "Aus jeder Gestalt: Schnelligkeit der Natur, Schmuckstücke und sofort Heilende Berührung – ein Knopf.",
                "From any form: Nature's Swiftness, trinkets and an instant Healing Touch – one key." },
        without = { "Gestalt verlassen, Schnelligkeit der Natur, Schmuckstücke, Heilende Berührung – 5 Tasten.",
                    "Leave form, Nature's Swiftness, trinkets, Healing Touch – up to five separate keys." },
        rec = true,
        body = "#showtooltip {s:5185}\n/cancelform\n/cast {s:17116}\n/use 13\n/use 14\n/cast [@mouseover,help,nodead][help,nodead][@player] {s:5185}",
        need = 17116,
    },
    -- Welle 9 (UE-26): neu aus ezCores Klassen-Wissen (Makro-Logik „formHeal“), eigene Texte
    {
        id = "druid_formheal",
        name = { "Nachwachsen (MO)", "Regrowth (MO)" },
        desc = { "Verlässt jede Gestalt und wirkt Nachwachsen auf den Spieler unter der Maus, sonst auf dein Ziel, sonst auf dich.",
                 "Leaves any form and casts Regrowth on the player under your mouse, otherwise your target, otherwise yourself." },
        why = { "Aus Bär oder Katze heraus heilen, ohne die Gestalt erst von Hand zu verlassen.",
                "Heal out of bear or cat form without leaving the form by hand first." },
        logic = "formHeal",
        body = Logic("DRUID", "formHeal"),
    },
    -- Welle 27 (Paket modul/ezmacro-faehigkeiten): Lücken gegen ezCores Client-Tabellen gefüllt (Kopf der Datei), eigene Texte
    {
        id = "druid_insectswarm",
        name = { "Schwarm (MO)", "Swarm (MO)" },
        desc = { "Insektenschwarm (Talent) auf den Gegner unter der Maus, sonst aufs Ziel – zum Verteilen auf mehrere Gegner.",
                 "Insect Swarm (talent) on the enemy under your mouse, otherwise your target – for spreading it on several enemies." },
        why = { "Verteile Insektenschwarm auf mehrere Gegner: Maus drüber halten und drücken, ohne Zielwechsel.",
                "Spread Insect Swarm on several enemies: mouse over each and press, no target switching." },
        body = "#showtooltip\n/cast [@mouseover,harm,nodead][] {s:5570}",
    },
})


-- Welle 27: Zauber über Zeit, Kontrolle und Unterbrechen ohne eigene Vorlage – je mit Grund (ein Satz). Die Liste ist
-- Entwicklerwissen, keine Oberfläche: Tests/vorlagen27.lua prüft, dass jeder solche Zauber einer Klasse (Art laut
-- ezCores Client-Tabelle SpellKinds) eine Vorlage hat oder hier steht, und dass hier nur solche ohne Vorlage stehen.
-- Nur ausgelöste Zauber (Art „proc“, z. B. Feuerschwall 18093) erkennt ezCore selbst (Paket kern/ausgeloeste-zauber,
-- 17.11.2026) – sie stehen nicht hier; „Aus deinen Fähigkeiten“ bietet für sie ohnehin kein Makro an.
-- Im Spiel bietet ezMacro die davon, die du gelernt hast, in der Gruppe „Aus deinen Fähigkeiten“ an (SpellMacros.lua) –
-- außer denen in ns.NO_GENERATE (unter der Liste): dort sagt der Grund, dass eine Maus- oder Fokus-Fassung nicht wirkt
-- oder nichts bringt.
ns.NO_TEMPLATE = {
    -- Krieger
    [12809] = "Erschütternder Schlag: Nahkampf-Betäubung (Talent) aufs Ziel vor dir – im Nahkampf brächte eine Vorlage keinen Mehrwert gegenüber dem Zauber.",
    -- Jäger
    [19306] = "Gegenangriff: nur nach deiner Parade und im Nahkampf aufs Ziel – ein Makro bringt nichts dazu.",
    [3674] = "Schwarzer Pfeil: Schuss mit eigener Abklingzeit aufs Ziel; die Maus-Fassung bietet „Aus deinen Fähigkeiten“ an.",
    [24118] = "Aufschlitzen (Jäger, neu auf Forever): Wirkung im Spiel unbelegt; „Aus deinen Fähigkeiten“ bietet die Maus-Fassung an.",
    -- Schurke
    [408] = "Nierenhieb: Finishing-Move – die Combopunkte liegen auf dem Ziel, auf einem anderen Gegner wirkt er nicht.",
    [703] = "Erdrosseln: Eröffnung aus der Verstohlenheit hinter dem Ziel – eine Vorlage brächte keinen Mehrwert gegenüber dem Zauber.",
    [1943] = "Blutung: Finishing-Move – die Combopunkte liegen auf dem Ziel, auf einem anderen Gegner wirkt er nicht.",
    [1316709] = "Todesmal (neu auf Forever): Wirkung im Spiel unbelegt; „Aus deinen Fähigkeiten“ bietet die Maus-Fassung an.",
    -- Priester
    [10797] = "Sternensplitter: Volkszauber der Nachtelfen-Priester; „Aus deinen Fähigkeiten“ bietet ihn an, wer ihn hat.",
    [1277331] = "Züchtigung: Volkszauber der Zwergen-Priester; „Aus deinen Fähigkeiten“ bietet ihn an, wer ihn hat.",
    -- Magier
    [28270] = "Verwandlung: Kuh – Spielart von Verwandlung; die Vorlage „Verwandlung (F)“ deckt den Zweck ab.",
    [401502] = "Frostfeuerblitz: Hauptzauber mit kurzem Nachbrennen aufs Ziel; die Maus-Fassung bietet „Aus deinen Fähigkeiten“ an.",
    -- Hexenmeister
    [1098] = "Dämon unterwerfen: beherrscht einen Dämon dauerhaft, ohne Eile; die Fokus-Fassung bietet „Aus deinen Fähigkeiten“ an.",
    [1316697] = "Zermürben (Talent, neu auf Forever): Wirkung im Spiel unbelegt; „Aus deinen Fähigkeiten“ bietet die Maus-Fassung an.",
    -- Druide
    [5211] = "Hieb: Nahkampf-Betäubung in Bärengestalt aufs Ziel vor dir – eine Vorlage brächte keinen Mehrwert gegenüber dem Zauber.",
    [1079] = "Zerfetzen: Finishing-Move in Katzengestalt – die Combopunkte liegen auf dem Ziel.",
    [1822] = "Krallenhieb: Katzengestalt im Nahkampf aufs Ziel, baut Combopunkte auf dem Ziel auf – eine Vorlage brächte keinen Mehrwert.",
    [1328617] = "Aufschlitzen (neu auf Forever): Bärengestalt im Nahkampf aufs Ziel – eine Vorlage brächte keinen Mehrwert gegenüber dem Zauber.",
    [1238122] = "Wilde Attacke: Ansturm in Bärengestalt aufs Ziel; die Fokus-Fassung mit /stopcasting bietet „Aus deinen Fähigkeiten“ an.",
}

-- Welle 27, Gegenprüfung: Ausnahmen, zu denen auch „Aus deinen Fähigkeiten“ kein Makro anbietet – ihr Grund oben sagt,
-- dass eine Maus- oder Fokus-Fassung nicht wirkt (Finishing-Moves: die Combopunkte liegen auf dem Ziel), nichts bringt
-- (Nahkampf aufs Ziel vor dir, nur nach einer Parade) oder von einer Vorlage abgedeckt wird. Die übrigen Ausnahmen
-- (Schwarzer Pfeil, Dämon unterwerfen, Wilde Attacke …) bietet die Gruppe an.
-- Was ezCores Spells.CLASS als reactive, finisher oder nextSwing führt (Gegenangriff 19306, Zerfetzen 1079), filtert
-- SpellMacros.lua schon über SM.CLASS_SKIP – es steht hier nicht noch einmal (SSOT; Paket ezmacro/rangtausch-ezheal,
-- Tests/rangtausch2011.lua hält das fest).
ns.NO_GENERATE = {
    [12809] = true,   -- Erschütternder Schlag
    [408] = true,     -- Nierenhieb
    [703] = true,     -- Erdrosseln
    [1943] = true,    -- Blutung
    [28270] = true,   -- Verwandlung: Kuh (Vorlage „Verwandlung (F)“)
    [5211] = true,    -- Hieb
    [1822] = true,    -- Krallenhieb
    [1328617] = true, -- Aufschlitzen (Druide)
}

-- Paket modul/ezmacro-reste (17.11.2026; Fund c des Reviews vor dem Merge von Welle 27): Klassenzauber für Mitspieler,
-- die nicht auf dich selbst gehen. Für sie endet ein Makro aus „Aus deinen Fähigkeiten“ nicht auf „[@player]“, sondern
-- auf dem Ziel (SpellMacros.lua). Merkmal laut Client-Tabelle SpellMisc, Feld Attributes_1, Bit 0x80000 („Exclude
-- Caster“, nicht auf den Zaubernden) des Produkts „wowf“, Build ns.NOT_SELF_BUILD (wago.tools, im Rohordner nachgesehen am
-- 17.11.2026, docs/wago-tools.md); geprüft über alle Grund-IDs der Arten Heilung, Stärkung und Ziel beliebig in ezCores
-- Client-Tabelle SpellKinds – genau diese vier tragen das Bit. Namen laut SpellName (deDE, enUS) derselben Tabellen.
-- Begründete Liste von Hand, weil ezCores ausgelieferte Tabellen das Merkmal nicht führen (Folgepunkt in
-- docs/roadmap/ezCore.md unter „Offen“: das Merkmal in SpellKinds aufnehmen, dann liest ezMacro es dort). Tests/reste27.lua
-- hält die Liste an ezCores Tabelle fest (nur Zauber dieser Arten, ns.NOT_SELF_BUILD gleich dem Build der Tabelle).
ns.NOT_SELF_BUILD = "1.60.1.70938"
ns.NOT_SELF = {
    [6940] = true,    -- Segen der Opferung (Blessing of Sacrifice), Paladin, Stärkung
    [19752] = true,   -- Göttliches Eingreifen (Divine Intervention), Paladin, Stärkung
    [1277370] = true, -- Göttliche Anmut (Divine Grace), Priester, Heilung
    [2096] = true,    -- Gedankensicht (Mind Vision), Priester, Ziel beliebig – fällt ohnehin nie auf dich
}
