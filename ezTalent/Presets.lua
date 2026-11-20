local _, ns = ...

--[[
    Vorauswahl typischer Talentbäume je Klasse (Punkt 2 in docs/roadmap/ezTalent.md). Nur Daten – die Logik
    (Zuordnung zu den Knoten des Clients, Kopieren als eigene Vorlage, Anzeige) steht in Templates.lua.

    Grundlage: geprüfte Gesamtliste der Recherche vom 13.11.2026 (43 Bäume, je Klasse 3–5; Entscheidungen des Nutzers
    vom 13.11.2026: „Recherche mit Quelle“, „veraltete builds entfallen“, „wir sollten aber je klasse 3-5 talentbäume
    anbieten“, Einstufung „Streng, alle bleiben (Empfohlen)“, Hotfix-Regel „Nein, mit Vermerk (Empfohlen)“).
    Leitlinie 10 und 11: Fakten in eigener Form – nur welches Talent mit wie vielen Rängen, die Verteilung und die
    Quelle. Keine Texte, keine Tabellen, keine Rechner-Codes und keine Knoten-IDs der Seiten. Die Zuordnung zu Forevers
    Knoten macht ezTalent zur Laufzeit sprachunabhängig über die im Spiel erhobene Zauber-ID bzw. Lage im Baum
    (PresetIDs.lua; Werkzeug „Talente erheben“); nur für Talente, zu denen noch nichts erhoben ist, über die Namen, die
    der Client liefert (C_Traits → Definition → Zauber). Der englische Name hier ist der Schlüssel für PresetIDs.lua.

    Quellen (alle gelesen am 13.11.2026; Stand je Eintrag):
      IV  Icy Veins, Bereich WoW Forever      https://icy-veins.com/wow-forever/
      MOB Mobalytics, Bereich WoW Forever     https://mobalytics.gg/wow-forever/
      RB  RankedBoost, Forever-Builds         https://rankedboost.com/world-of-warcraft/forever/build/
      WT  Warcraft Tavern, Forever-Guides     https://warcrafttavern.com/forever/guides/  (Seiten ohne Datum: Stand
                                              nur über die Sitemap, zählt in der strengen Einstufung nicht)
      KL  kami-labs, WoW Forever              https://kami-labs.fr/en/wow-forever/
      CH  chromie.de, Talentrechner Forever   https://chromie.de/talente/forever/  (Community-Builds)
      ZO  Zockify, Forever                    https://zockify.com/forever/
      ME  Method, WoW Forever                 https://method.gg/wow-forever/
      WG  wow.gg, Guides                      https://wow.gg/guides/
    Hotfixes 05.–13.11.2026: Blizzard-Forum, Hotfix-Sammelthread https://us.forums.blizzard.com/en/wow/t/2403040
    (gelesen 13.11.2026, erneut 14.11.2026 – letzter Eintrag 13.11.; ns.PRESET_HOTFIX_READ) – kein Hotfix hat ein
    Talent hinzugefügt, entfernt oder in Lage, Rang oder Voraussetzung geändert; einige ändern die Wirkung gewählter
    Talente (ns.PRESET_HOTFIXES unten). Das Nachlesen bleibt Daueraufgabe (docs/roadmap/ezTalent.md).

    Nachführen am 14.11.2026 (Einstufung unverändert 19 „geprüft“, 24 „eine Quelle“; kein Baum neu):
      - kami-labs: alle sechs Seiten mit Vermerk „textdate“ erneut gelesen – weiter „Published on 14 septembre 2026“
        (Shockadin: 29 octobre 2026), kein Änderungsdatum; der 09.11. steht nur im Text. Sie zählen weiter nicht.
      - mobalytics.gg und icy-veins.com waren beim Abruf nicht lesbar (Fehler 403). Ihre Angaben stammen weiter aus der
        Recherche vom 13.11.; die Mobalytics-Seite zu „Elementar – Leveln/Solo“ ist damit weiter unbelegt.
      - Lücken (PvP, Leveln-Bäume für Hexenmeister, Heilig- und Schutz-Paladin, fünfter Jäger-Baum, zweite Quelle für
        Verstärkung): keine zwei übereinstimmenden aktuellen Quellen mit lesbaren Rängen gefunden – nichts aufgenommen
        (Einzelheiten und Kandidaten: docs/roadmap/ezTalent.md).

    Regeln:
      - „veraltete builds entfallen“: Stand vor dem Start (04.11.2026), für das Beta-Stufenlimit geschrieben, nach
        einem Talent-Hotfix nicht aktualisiert oder Stand unbelegt → nicht aufgenommen, auch nicht „mit Vorbehalt“.
      - Nur Talent-Änderungen (Lage, Rang, Voraussetzung) machen einen Baum veraltet. Reine Wirkungsänderungen
        gewählter Talente: der Baum bleibt, mit sichtbarem Vermerk (ns.PRESET_HOTFIXES).
      - Nach jedem Talent-Hotfix alle Bäume neu prüfen (docs/roadmap/ezTalent.md). Raids öffnen am 09.12.2026 –
        Raid-Bäume sind bis dahin Theorie bzw. Simulation.

    Form eines Eintrags:
      { key, name = { de, en }, tree = Hauptbaum (1–3, Client-Reihenfolge), split = "Punkte je Baum",
        grade = "checked" (zwei unabhängige Quellen mit belegtem Stand stimmen überein) | "single" (nur eine Quelle
        punktgenau, der Kern meist mehrfach belegt) | "unchecked" (ungeprüft – derzeit kein Eintrag),
        purpose = { "leveling" | "solo" | "dungeon" | "raid" | "tank" | "healer" | "hybrid" … },
        read = Lesedatum, sources = { { site, path, stand, role, note } … },
        talents = { { Baum, Rang, "englischer Name", "deutscher Name" (falls belegt), "anderer Name" (falls strittig) } … } }
      role: "exact" punktgenau · "core" im Kern gleich · "derived" punktgleich, vermutlich abgeleitet (zählt nicht als
            Bestätigung) · "extra" nur ergänzend
      note: "sitemap" Stand nur über die Sitemap belegt · "content" Seite neu, Inhalt vor dem Start · "textdate" Datum
            nur als Verweis im Text, die Seite selbst ist älter (kami-labs, nachgeprüft 14.11.2026: Katze, Gleichgewicht,
            Meucheln, Täuschung und Vergeltung veröffentlicht 14.09.2026, Shockadin 29.10.2026; der 09.11. ist nur das
            Datum einer Simulation im Text) · "split" die Seite verteilt die Punkte deutlich anders (im Kern gleich, aber
            ein anderer Baum; Verteilung der Seite im Kommentar am Eintrag) · "purpose" Seite für einen anderen Zweck
            (Endspiel- oder Tank-Guide zu einem Leveln-Baum)
      Strenge Regel für "checked" (Gegenprüfung 14.11.2026, Test in Tests/run.lua, in beiden Richtungen: jeder Baum,
      der sie erfüllt, ist „geprüft“, und jeder „geprüfte“ erfüllt sie): zwei Quellen von verschiedenen Websites, je mit
      eigener Adresse (kein leerer Pfad, keine Seite doppelt) und Stand ab dem Start (04.11.2026), Art exact oder core
      und ohne Vermerk. Ein Vermerk heißt: Stand nicht über die Seite selbst belegt (sitemap, content, textdate) oder die
      Seite zeigt nicht diesen Baum (split, purpose) – die Quelle bleibt sichtbar, zählt aber nicht als Bestätigung.
      Ergebnis nach Gegenprüfung 14.11.2026, Regel in beide Richtungen: 19 „geprüft“, 24 „eine Quelle“.
    Deutsche Namen nur, wo die Recherche sie belegt (Paladin und Hexenmeister fast nur englisch). Seit der Erhebung im
    Client (Build 70938, deDE, 15.11.2026) hat jedes Talent der Vorauswahl seine Kennung in PresetIDs.lua; die Namen
    sind nur noch Ersatz und Anzeige. Dabei sechs deutsche Namen auf den Namen des Clients berichtigt (vorher: Effiziente
    Stöße, Aufblitzender Stahl, Ungezügelte Hiebe, Permafrost, Räuberische Disziplin, Erblühen).
]]

ns.PRESETS = ns.PRESETS or {}
local P = ns.PRESETS

local R = "2026-11-13"   -- Lesedatum aller Quellen

ns.PRESET_SITES = {
    IV = { name = "Icy Veins", base = "https://icy-veins.com/wow-forever/" },
    MOB = { name = "Mobalytics", base = "https://mobalytics.gg/wow-forever/" },
    RB = { name = "RankedBoost", base = "https://rankedboost.com/world-of-warcraft/forever/build/" },
    WT = { name = "Warcraft Tavern", base = "https://warcrafttavern.com/forever/guides/" },
    KL = { name = "kami-labs", base = "https://kami-labs.fr/en/wow-forever/" },
    CH = { name = "chromie.de", base = "https://chromie.de/talente/forever/" },
    ZO = { name = "Zockify", base = "https://zockify.com/forever/" },
    ME = { name = "Method", base = "https://method.gg/wow-forever/" },
    WG = { name = "wow.gg", base = "https://wow.gg/guides/" },
}

-- Wirkungsänderungen gewählter Talente durch Hotfixes (Baum bleibt, Vermerk sichtbar). Schlüssel: englischer Name
-- wie in den Einträgen. Quelle: Hotfix-Sammelthread (s. o.), gelesen 13.11.2026 und erneut 14.11.2026.
-- Nachgetragen am 14.11.2026 (im Thread schon am 13.11. vorhanden, in der ersten Liste übersehen): Sweeping Strikes,
-- Unsealed Wrath, Lightning Overload, Power Infusion, Arcane Concentration, Natural Instinct, Rend and Tear. Nach der
-- Gegenprüfung am selben Tag den Thread je Klasse gegen alle Talentnamen der Vorauswahl gelesen und nachgetragen:
-- Wild Growth, Bloom, Arcane Blast, Bane of Havoc.
-- Grenze (Entscheidungsfrage 9 in docs/roadmap/ezTalent.md): Einen Vermerk bekommt, was ändert, was das gewählte
-- Talent im üblichen Spiel bewirkt – Schaden, Heilung, Dauer, Abklingzeit, Aufladungen, Kosten, worauf es wirkt –,
-- auch wenn Blizzard es als Fehlerbehebung führt. Kein Vermerk, je mit Grund:
--   nur Anzeige oder Verwaltung: Boot Knife (Tooltip von Shank, 06.11.), Reckless Swings und Swiftmend (Tooltip,
--     06.11.), Lacerate, Redoubt und Maelstrom Weapon in Blizzards Abklingzeit-Anzeige (09./10.11.), Lightning Mastery
--     und Improved Ghost Wolf (Optik, 09.11.), Incinerate (war ohne Zerstörung verfügbar, 09.11.), Holy Nova (blieb
--     beim Verlernen erhalten, 10.11.)
--   Randfall, der die Wirkung im üblichen Spiel nicht ändert: Feral Charge (die Katze kam nicht sofort in den Kampf,
--     09.11.), Shadowform (brach bei Fear Ward ab, 09.11.; eine Volksfähigkeit der Gnome war darin gesperrt, 11.11.),
--     Vampiric Embrace (löste eine Verzauberung aus, 10.11.), Siphon Life (Rang 1 ließ sich unter Stille wirken, 13.11.)
--   kein Talent genannt: Hotfixes zu Grundfähigkeiten, die ein gewähltes Talent nur verbessert (Judgement 11.11. und
--     Judgement of Command 13.11. – das Urteil des Befehls zählt danach wieder als Nahkampfangriff wie vor dem 11.11.;
--     Berserker Rage und Frost Nova 13.11.)
ns.PRESET_HOTFIX_READ = "2026-11-14"   -- so weit ist der Sammelthread gelesen (Tooltip der Vermerke nennt das Datum)
ns.PRESET_HOTFIXES = {
    WARRIOR = { { "Sweeping Strikes", "2026-11-10" } },                              -- verliert keine Aufladung ohne zweites Ziel
    PALADIN = { { "Unsealed Wrath", "2026-11-11" } },                                -- im Thread „Unsealed Fury“: keine Echos mehr
                                                                                     -- durch Angriffe des Windzorntotems
    WARLOCK = { { "Soul Siphon", "2026-11-10" }, { "Wrack", "2026-11-10" },          -- Gebrechen: Wirkung umgebaut
        { "Bane of Havoc", "2026-11-10" } },                                         -- löst jetzt die globale Abklingzeit aus
    SHAMAN = { { "Mental Dexterity", "2026-11-10" }, { "Maelstrom Weapon", "2026-11-10" },
        { "Stormstrike", "2026-11-10" },                                             -- Verstärkung: Werte (live 12.11.)
        { "Lightning Overload", "2026-11-09" } },                                    -- richtiger Schaden für Blitzschlag
    HUNTER = { { "Summon Hawk", "2026-11-10" } },                                    -- Manakosten, Falkenschaden
    DRUID = { { "Nature's Swiftness", "2026-11-10" },                                -- wirkt auch auf Wild Growth
        { "Natural Instinct", "2026-11-09" },                                        -- gilt jetzt für Lacerate und Pounce
        { "Rend and Tear", "2026-11-11" },                                           -- wirkt auch auf die Blutung von Pounce
        { "Bloom", "2026-11-06" },                                                   -- heilt das Ziel jetzt richtig
        { "Wild Growth", "2026-11-13" } },                                           -- Heilwert 6,6 % statt 3,3 %, nicht mehr im Laufen
    PRIEST = { { "Twilight Focus", "2026-11-11" },                                   -- wirkt in Schattengestalt
        { "Power Infusion", "2026-11-09" } },                                        -- bleibt auf Verbündeten bestehen
    MAGE = { { "Arcane Concentration", "2026-11-09" },                               -- Chance auf Zauber und jedes Geschoss verteilt
        { "Arcane Blast", "2026-11-06" } },                                          -- Dauer jetzt wie vorgesehen 18 Sekunden
}

local function S(site, path, stand, role, note)
    return { site = site, path = path, stand = stand, role = role, note = note }
end

-- Liste aus zwei Teilen (gemeinsame Abschnitte mehrerer Bäume nur einmal aufschreiben)
local function With(list, extra)
    local out = {}
    for _, t in ipairs(list) do out[#out + 1] = t end
    for _, t in ipairs(extra) do out[#out + 1] = t end
    return out
end

---------------------------------------------------------------------------
-- Krieger (Bäume: 1 Waffen, 2 Furor, 3 Schutz)
---------------------------------------------------------------------------

P.WARRIOR = {
    { key = "fury-dual", name = { de = "Furor – Zwei Waffen", en = "Fury – dual wield" }, tree = 2, split = "18/33/0",
      grade = "checked", purpose = { "dungeon", "raid" }, read = R,
      sources = { S("IV", "fury-warrior-melee-dps-pve-spec-builds-talents", "2026-11-04", "exact"),
          S("MOB", "classes/fury-warrior-guide", "2026-11-06", "core"),
          S("KL", "build-guerrier-fureur-wow-forever/", "2026-11-06", "core"),
          S("WG", "wow-forever-fury-warrior", "2026-11-04", "derived"),
          S("RB", "warrior/", "2026-11-08", "derived") },
      talents = {
          { 1, 3, "Improved Heroic Strike", "Verb. heldenhafter Stoß" }, { 1, 3, "Improved Rend", "Verb. Verwunden" },
          { 1, 3, "Improved Tactical Mastery", "Verb. Taktiker" }, { 1, 2, "Improved Overpower", "Verb. Überwältigen" },
          { 1, 1, "Anger Management", "Aggressionskontrolle" }, { 1, 3, "Deep Wounds", "Tiefe Wunden" },
          { 1, 1, "Spearing Strike", "Aufspießender Stoß" }, { 1, 2, "Impale", "Durchbohren" },
          { 2, 5, "Cruelty", "Grausamkeit" }, { 2, 5, "Unbridled Wrath", "Entfesselter Zorn" },
          { 2, 3, "Furious Precision", "Zornige Präzision" }, { 2, 5, "Enrage", "Wutanfall" },
          { 2, 5, "Dual Wield Specialization", "Beidhändigkeits-Spez." }, { 2, 1, "Reckless Swings", "Tollkühne Schwünge" },
          { 2, 2, "Improved Berserker Rage", "Verb. Berserkerwut" }, { 2, 1, "Death Wish", "Todeswunsch" },
          { 2, 2, "Improved Whirlwind", "Verb. Wirbelwind" }, { 2, 3, "Flurry", "Schlaghagel" },
          { 2, 1, "Bloodthirst", "Blutdurst" },
      } },
    { key = "arms-2h", name = { de = "Waffen – Zweihand", en = "Arms – two-handed" }, tree = 1, split = "32/17/2",
      grade = "checked", purpose = { "dungeon", "raid" }, read = R,
      sources = { S("IV", "arms-warrior-melee-dps-pve-spec-builds-talents", "2026-11-04", "exact"),
          S("MOB", "classes/arms-warrior-guide", "2026-11-12", "core"),
          S("RB", "warrior/", "2026-11-08", "derived") },
      talents = {
          { 1, 3, "Improved Heroic Strike", "Verb. heldenhafter Stoß" }, { 1, 3, "Improved Rend", "Verb. Verwunden" },
          { 1, 3, "Improved Tactical Mastery", "Verb. Taktiker" }, { 1, 2, "Improved Overpower", "Verb. Überwältigen" },
          { 1, 1, "Anger Management", "Aggressionskontrolle" }, { 1, 3, "Deep Wounds", "Tiefe Wunden" },
          { 1, 1, "Spearing Strike", "Aufspießender Stoß" },
          { 1, 3, "Two-Handed Weapon Specialization", "Zweihandwaffen-Spez." }, { 1, 2, "Impale", "Durchbohren" },
          { 1, 2, "Bloodthrill", "Rausch des Blutes" }, { 1, 1, "Sweeping Strikes", "Weitreichende Stöße" },
          { 1, 5, "Weaponmaster", "Waffenmeister" }, { 1, 2, "Improved Slam", "Verb. Zerschmettern" },
          { 1, 1, "Mortal Strike", "Tödlicher Stoß" },
          { 2, 5, "Cruelty", "Grausamkeit" }, { 2, 5, "Unbridled Wrath", "Entfesselter Zorn" }, { 2, 5, "Enrage", "Wutanfall" },
          { 2, 1, "Reckless Swings", "Tollkühne Schwünge" }, { 2, 1, "Improved Execute", "Verb. Hinrichten" },
          { 3, 2, "Improved Bloodrage", "Verb. Blutrausch" },
      } },
    { key = "prot-tank", name = { de = "Schutz – Tank", en = "Protection – tank" }, tree = 3, split = "5/15/31",
      grade = "single", purpose = { "tank" }, read = R,
      -- RankedBoost verteilt 13/0/38 (Seite aktualisiert 08.11., nachgeprüft 14.11.2026) – Kern gleich, Verteilung nicht
      sources = { S("IV", "protection-warrior-tank-pve-spec-builds-talents", "2026-11-04", "exact"),
          S("RB", "warrior/#build=auth-warrior-protection-tank", "2026-11-08", "core", "split") },
      talents = {
          { 1, 5, "Deflection", "Abwehr" },
          { 2, 5, "Cruelty", "Grausamkeit" }, { 2, 5, "Lingering Rage", "Schwelende Wut" }, { 2, 5, "Enrage", "Wutanfall" },
          { 3, 5, "Shield Specialization", "Schild-Spez." }, { 3, 5, "Anticipation", "Vorahnung" },
          { 3, 3, "Improved Revenge", "Verb. Rache" }, { 3, 1, "Last Stand", "Letztes Gefecht" },
          { 3, 2, "Master of Defense", "Meister der Verteidigung" }, { 3, 3, "Defiance", "Trotz" },
          { 3, 1, "Vanguard", "Frontkämpfer" }, { 3, 2, "Improved Shield Wall", "Verb. Schildwall" },
          { 3, 1, "Concussion Blow", "Erschütternder Schlag" }, { 3, 2, "Focused Rage", "Fokussierte Wut" },
          { 3, 5, "Bastion", "Bastion" }, { 3, 1, "Shield Slam", "Schildschlag" },
      } },
    { key = "arms-leveling", name = { de = "Waffen – Leveln", en = "Arms – leveling" }, tree = 1, split = "32/19/0",
      grade = "single", purpose = { "leveling" }, read = R,
      sources = { S("MOB", "classes/warrior-leveling-guide", "2026-11-13", "exact") },
      talents = {
          { 1, 5, "Deflection", "Abwehr" }, { 1, 3, "Improved Rend", "Verb. Verwunden" },
          { 1, 2, "Improved Charge", "Verb. Sturmangriff" }, { 1, 2, "Improved Overpower", "Verb. Überwältigen" },
          { 1, 3, "Deep Wounds", "Tiefe Wunden" }, { 1, 1, "Spearing Strike", "Aufspießender Stoß" },
          { 1, 3, "Two-Handed Weapon Specialization", "Zweihandwaffen-Spez." }, { 1, 2, "Impale", "Durchbohren" },
          { 1, 2, "Bloodthrill", "Rausch des Blutes" }, { 1, 1, "Sweeping Strikes", "Weitreichende Stöße" },
          { 1, 5, "Weaponmaster", "Waffenmeister" }, { 1, 2, "Improved Slam", "Verb. Zerschmettern" },
          { 1, 1, "Mortal Strike", "Tödlicher Stoß" },
          { 2, 5, "Cruelty", "Grausamkeit" }, { 2, 2, "Lingering Rage", "Schwelende Wut" },
          { 2, 5, "Unbridled Wrath", "Entfesselter Zorn" }, { 2, 1, "Piercing Howl", "Durchdringendes Heulen" },
          { 2, 5, "Enrage", "Wutanfall" }, { 2, 1, "Reckless Swings", "Tollkühne Schwünge" },
      } },
    { key = "prot-leveling", name = { de = "Schutz – Leveln", en = "Protection – leveling" }, tree = 3, split = "5/15/31",
      grade = "single", purpose = { "leveling", "tank" }, read = R,
      sources = { S("MOB", "classes/warrior-leveling-guide", "2026-11-13", "exact") },
      talents = {
          { 1, 2, "Deflection", "Abwehr" }, { 1, 3, "Improved Rend", "Verb. Verwunden" },
          { 2, 5, "Cruelty", "Grausamkeit" }, { 2, 5, "Lingering Rage", "Schwelende Wut" }, { 2, 5, "Enrage", "Wutanfall" },
          { 3, 2, "Improved Bloodrage", "Verb. Blutrausch" }, { 3, 5, "Shield Specialization", "Schild-Spez." },
          { 3, 3, "Improved Revenge", "Verb. Rache" }, { 3, 3, "Improved Thunder Clap", "Verb. Donnerknall" },
          { 3, 1, "Last Stand", "Letztes Gefecht" }, { 3, 2, "Master of Defense", "Meister der Verteidigung" },
          { 3, 3, "Defiance", "Trotz" }, { 3, 1, "Vanguard", "Frontkämpfer" },
          { 3, 1, "Improved Shield Wall", "Verb. Schildwall" }, { 3, 1, "Concussion Blow", "Erschütternder Schlag" },
          { 3, 3, "Focused Rage", "Fokussierte Wut" }, { 3, 5, "Bastion", "Bastion" }, { 3, 1, "Shield Slam", "Schildschlag" },
      } },
}

---------------------------------------------------------------------------
-- Paladin (Bäume: 1 Heilig, 2 Schutz, 3 Vergeltung) – deutsche Namen nicht belegt
---------------------------------------------------------------------------

P.PALADIN = {
    { key = "holy-vigil", name = { de = "Heilig – Lichtwacht", en = "Holy – Light's Vigil" }, tree = 1, split = "31/8/12",
      grade = "single", purpose = { "healer" }, read = R,
      -- RankedBoost verteilt 31/20/0 (Schutz statt Vergeltung; Seite aktualisiert 08.11., nachgeprüft 14.11.2026)
      sources = { S("IV", "holy-paladin-healer-pve-spec-builds-talents", "2026-11-04", "exact"),
          S("WG", "wow-forever-holy-paladin", "2026-11-04", "derived"),
          S("RB", "paladin/", "2026-11-08", "core", "split") },
      talents = {
          { 1, 5, "Spiritual Focus" }, { 1, 3, "Healing Light" }, { 1, 2, "Reverence" }, { 1, 2, "Purifying Power" },
          { 1, 1, "Divine Favor" }, { 1, 5, "Illumination" }, { 1, 1, "Holy Conduit" }, { 1, 2, "Infusion of Light" },
          { 1, 1, "Oath of Light" }, { 1, 1, "Holy Shock" }, { 1, 2, "Boundless Light" }, { 1, 5, "Holy Power" },
          { 1, 1, "Light's Vigil" },
          { 2, 5, "Divine Intellect" }, { 2, 1, "Guardian's Favor" }, { 2, 2, "Sacred Duty" },
          { 3, 5, "Benediction" }, { 3, 2, "Improved Judgement" }, { 3, 3, "Conviction" }, { 3, 2, "Pursuit of Justice" },
      } },
    { key = "prot-deep", name = { de = "Schutz – Tiefer Schutz", en = "Protection – deep protection" }, tree = 2,
      split = "0/35/16", grade = "checked", purpose = { "tank" }, read = R,
      sources = { S("IV", "protection-paladin-tank-pve-spec-builds-talents", "2026-11-04", "exact"),
          S("WG", "wow-forever-protection-paladin", "2026-11-04", "exact"),
          S("CH", "paladin", "2026-11-10", "core") },
      talents = {
          { 2, 5, "Redoubt" }, { 2, 3, "Precision" }, { 2, 2, "Sacred Duty" }, { 2, 1, "Templar's Bulwark" },
          { 2, 2, "Shield Specialization" }, { 2, 3, "Toughness" }, { 2, 1, "Swift Judgement" },
          { 2, 3, "Improved Righteous Fury" }, { 2, 5, "Anticipation" }, { 2, 1, "Holy Shield" }, { 2, 5, "Reckoning" },
          { 2, 3, "Iron Creed" }, { 2, 1, "Shieldsworn" },
          { 3, 5, "Benediction" }, { 3, 2, "Improved Judgement" }, { 3, 3, "Conviction" },
          { 3, 3, "Sanctified Judgement" }, { 3, 2, "Pursuit of Justice" }, { 3, 1, "Sacred Arbiter" },
      } },
    { key = "ret-unsealed", name = { de = "Vergeltung – Entfesselter Zorn", en = "Retribution – Unsealed Wrath" }, tree = 3,
      split = "12/8/31", grade = "checked", purpose = { "dungeon", "raid" }, read = R,
      sources = { S("WG", "wow-forever-retribution-paladin", "2026-11-04", "exact"),
          S("KL", "build-paladin-vindicte-wow-forever/", "2026-11-09", "derived", "textdate"),
          S("RB", "paladin/", "2026-11-08", "core"),
          S("IV", "retribution-paladin-melee-dps-pve-spec-builds-talents", "2026-11-04", "core") },
      talents = {
          { 1, 5, "Divine Strength" }, { 1, 5, "Improved Seals" }, { 1, 2, "Holy Conduit" },
          { 2, 5, "Divine Intellect" }, { 2, 3, "Precision" },
          { 3, 5, "Benediction" }, { 3, 2, "Improved Judgement" }, { 3, 3, "Conviction" },
          { 3, 3, "Sanctified Judgement" }, { 3, 3, "Vindication" }, { 3, 1, "Seal of Command" }, { 3, 1, "Sacred Arbiter" },
          { 3, 3, "Two-Handed Weapon Specialization" }, { 3, 1, "Repentance" }, { 3, 3, "Vengeance" },
          { 3, 5, "Champion of the Light" }, { 3, 1, "Unsealed Wrath", nil, "Unsealed Fury" },
      } },
    { key = "ret-leveling", name = { de = "Vergeltung – Leveln", en = "Retribution – leveling" }, tree = 3, split = "12/8/31",
      grade = "checked", purpose = { "leveling" }, read = R,
      sources = { S("KL", "build-paladin-vindicte-leveling-wow-forever/", "2026-11-12", "exact"),
          S("CH", "paladin", "2026-11-04", "core") },
      talents = {
          { 1, 5, "Divine Strength" }, { 1, 2, "Reverence" }, { 1, 5, "Improved Seals" },
          { 2, 5, "Divine Intellect" }, { 2, 3, "Precision" },
          { 3, 5, "Deflection" }, { 3, 1, "Benediction" }, { 3, 2, "Improved Judgement" }, { 3, 3, "Conviction" },
          { 3, 3, "Sanctified Judgement" }, { 3, 1, "Seal of Command" }, { 3, 2, "Pursuit of Justice" },
          { 3, 1, "Sacred Arbiter" }, { 3, 3, "Two-Handed Weapon Specialization" }, { 3, 1, "Repentance" },
          { 3, 3, "Vengeance" }, { 3, 5, "Champion of the Light" }, { 3, 1, "Unsealed Wrath", nil, "Unsealed Fury" },
      } },
    { key = "shockadin", name = { de = "Vergeltung – Shockadin", en = "Retribution – Shockadin" }, tree = 3,
      split = "21/0/30", grade = "single", purpose = { "dungeon", "hybrid" }, read = R,
      sources = { S("IV", "retribution-paladin-melee-dps-pve-spec-builds-talents", "2026-11-04", "exact"),
          S("KL", "build-paladin-shockadin-wow-forever/", "2026-11-09", "core", "textdate") },
      talents = {
          { 1, 5, "Divine Strength" }, { 1, 2, "Reverence" }, { 1, 5, "Improved Seals" }, { 1, 2, "Purifying Power" },
          { 1, 1, "Divine Favor" }, { 1, 2, "Holy Conduit" }, { 1, 2, "Divine Precision" }, { 1, 1, "Oath of Light" },
          { 1, 1, "Holy Shock" },
          { 3, 5, "Benediction" }, { 3, 2, "Improved Judgement" }, { 3, 3, "Conviction" },
          { 3, 3, "Sanctified Judgement" }, { 3, 1, "Unyielding Faith" }, { 3, 1, "Seal of Command" },
          { 3, 2, "Pursuit of Justice" }, { 3, 1, "Sacred Arbiter" }, { 3, 3, "Two-Handed Weapon Specialization" },
          { 3, 1, "Repentance" }, { 3, 3, "Vengeance" }, { 3, 5, "Champion of the Light" },
      } },
}

---------------------------------------------------------------------------
-- Jäger (Bäume: 1 Tierherrschaft, 2 Treffsicherheit, 3 Überleben)
---------------------------------------------------------------------------

P.HUNTER = {
    { key = "bm-group", name = { de = "Tierherrschaft – Raid/Dungeon", en = "Beast Mastery – raid/dungeon" }, tree = 1,
      split = "31/20/0", grade = "checked", purpose = { "raid", "dungeon" }, read = R,
      sources = { S("IV", "beast-mastery-hunter-ranged-dps-pve-spec-builds-talents", "2026-11-04", "exact"),
          S("MOB", "classes/beast-mastery-hunter-guide", "2026-11-05", "core"),
          S("CH", "jaeger", "2026-11-10", "core"),
          S("RB", "hunter/", "2026-11-08", "core") },
      talents = {
          { 1, 5, "Deadly Aspects", "Tödliche Aspekte" }, { 1, 1, "Endurance Training", "Belastbarkeit-Ausbildung" },
          { 1, 2, "Focused Fire", "Konzentriertes Feuer" }, { 1, 2, "Improved Revive Pet", "Verb. Tier wiederbeleben" },
          { 1, 1, "Bestial Swiftness", "Erhöhte Tiergeschwindigkeit" }, { 1, 5, "Unleashed Fury", "Entfesselter Zorn" },
          { 1, 5, "Ferocity", "Wildheit" }, { 1, 1, "Summon Hawk", "Falke beschwören" },
          { 1, 1, "Intimidation", "Einschüchterung" }, { 1, 2, "Bestial Discipline", "Wildtierdisziplin" },
          { 1, 5, "Frenzy", "Raserei" }, { 1, 1, "Bestial Wrath", "Zorn des Wildtiers" },
          { 2, 5, "Lethal Attacks", "Tödliche Angriffe" }, { 2, 3, "Improved Stings", "Verb. Stiche und Bisse" },
          { 2, 5, "Careful Aim", "Sorgfältiges Zielen" }, { 2, 2, "Rapid Killing", "Schneller Tod" },
          { 2, 5, "Mortal Shots", "Todbringende Schüsse" },
      } },
    { key = "bm-leveling", name = { de = "Tierherrschaft – Leveln", en = "Beast Mastery – leveling" }, tree = 1,
      split = "31/20/0", grade = "checked", purpose = { "leveling", "solo" }, read = R,
      sources = { S("MOB", "classes/hunter-leveling-guide", "2026-11-13", "exact"),
          S("ME", "wow-forever-hunter-leveling-guide-and-talents", "2026-11-10", "core") },
      talents = {
          { 1, 5, "Deadly Aspects", "Tödliche Aspekte" }, { 1, 1, "Endurance Training", "Belastbarkeit-Ausbildung" },
          { 1, 2, "Focused Fire", "Konzentriertes Feuer" }, { 1, 2, "Improved Revive Pet", "Verb. Tier wiederbeleben" },
          { 1, 2, "Pathfinding", "Orientierung" }, { 1, 1, "Bestial Swiftness", "Erhöhte Tiergeschwindigkeit" },
          { 1, 4, "Unleashed Fury", "Entfesselter Zorn" }, { 1, 5, "Ferocity", "Wildheit" },
          { 1, 1, "Summon Hawk", "Falke beschwören" }, { 1, 1, "Intimidation", "Einschüchterung" },
          { 1, 2, "Bestial Discipline", "Wildtierdisziplin" }, { 1, 4, "Frenzy", "Raserei" },
          { 1, 1, "Bestial Wrath", "Zorn des Wildtiers" },
          { 2, 3, "Hawk Eye", "Falkenauge" }, { 2, 5, "Lethal Attacks", "Tödliche Angriffe" },
          { 2, 5, "Careful Aim", "Sorgfältiges Zielen" }, { 2, 2, "Rapid Killing", "Schneller Tod" },
          { 2, 1, "Trueshot Aura", "Aura des Volltreffers" }, { 2, 4, "Mortal Shots", "Todbringende Schüsse" },
      } },
    { key = "mm-lonewolf", name = { de = "Treffsicherheit – Einsamer Wolf", en = "Marksmanship – Lone Wolf" }, tree = 2,
      split = "5/41/5", grade = "checked", purpose = { "raid", "dungeon" }, read = R,
      sources = { S("IV", "marksmanship-hunter-ranged-dps-pve-spec-builds-talents", "2026-11-04", "exact"),
          S("RB", "hunter/#build=auth-hunter-marksmanship-dps", "2026-11-08", "core") },
      talents = {
          { 1, 5, "Deadly Aspects", "Tödliche Aspekte" },
          { 2, 3, "Hawk Eye", "Falkenauge" }, { 2, 5, "Lethal Attacks", "Tödliche Angriffe" },
          { 2, 3, "Improved Stings", "Verb. Stiche und Bisse" }, { 2, 5, "Efficiency", "Effizienz" },
          { 2, 5, "Careful Aim", "Sorgfältiges Zielen" }, { 2, 2, "Rapid Killing", "Schneller Tod" },
          { 2, 1, "Lone Wolf", "Einsamer Wolf" }, { 2, 1, "Trueshot Aura", "Aura des Volltreffers" },
          { 2, 5, "Mortal Shots", "Todbringende Schüsse" }, { 2, 2, "Rapid Recuperation", "Rasche Erholung" },
          { 2, 3, "Barrage", "Sperrfeuer" }, { 2, 5, "Ranged Weapon Specialization", "Distanzwaffen-Spez." },
          { 2, 1, "Sniper Shot", "Heckenschützenschuss" },
          { 3, 5, "Improved Tracking", "Verb. Fährtenlesen" },
      } },
    { key = "sv-weave", name = { de = "Überleben – Weben ohne Tier", en = "Survival – weaving, no pet" }, tree = 3,
      split = "0/18/33", grade = "single", purpose = { "raid", "dungeon" }, read = R,
      sources = { S("WT", "survival-hunter/", "2026-11-10", "exact", "sitemap"),
          S("RB", "hunter/#build=auth-hunter-survival-dps", "2026-11-08", "core") },
      talents = {
          { 2, 5, "Lethal Attacks", "Tödliche Angriffe" }, { 2, 3, "Improved Stings", "Verb. Stiche und Bisse" },
          { 2, 5, "Careful Aim", "Sorgfältiges Zielen" }, { 2, 2, "Rapid Killing", "Schneller Tod" },
          { 2, 1, "Lone Wolf", "Einsamer Wolf" }, { 2, 1, "Trueshot Aura", "Aura des Volltreffers" },
          { 2, 1, "Mortal Shots", "Todbringende Schüsse" },
          { 3, 5, "Improved Tracking", "Verb. Fährtenlesen" }, { 3, 3, "Deflection", "Abwehr" },
          { 3, 2, "Savage Strikes", "Wilde Schläge" }, { 3, 2, "Clever Traps", "Falleneffizienz" },
          { 3, 3, "Surefooted", "Sicherer Stand" }, { 3, 5, "Predator's Edge", "Vorteil des Raubtiers" },
          { 3, 2, "Resourcefulness", "Einfallsreichtum" }, { 3, 2, "Expose Prey", "Beute aufspüren" },
          { 3, 2, "Survivalist's Discipline", "Disziplin des Überlebenskünstlers" },
          { 3, 1, "Strider Kick", "Streichertritt" }, { 3, 5, "Lightning Reflexes", "Blitzartige Reflexe" },
          { 3, 1, "Lacerating Strikes", "Aufschlitzende Schläge" },
      } },
}

---------------------------------------------------------------------------
-- Schurke (Bäume: 1 Meucheln, 2 Kampf, 3 Täuschung)
---------------------------------------------------------------------------

P.ROGUE = {
    { key = "combat-leveling", name = { de = "Kampf – Leveln", en = "Combat – leveling" }, tree = 2, split = "16/35/0",
      grade = "single", purpose = { "leveling", "solo" }, read = R,
      sources = { S("IV", "combat-rogue-leveling", "2026-11-04", "exact"),
          S("WT", "rogue-leveling/", "2026-11-10", "core", "sitemap") },
      talents = {
          { 1, 2, "Remorseless Attacks", "Gnadenlose Angriffe" }, { 1, 5, "Malice", "Tücke" },
          { 1, 3, "Ruthlessness", "Skrupellosigkeit" }, { 1, 2, "Improved Slice and Dice", "Verb. Zerhäckseln" },
          { 1, 1, "Blood Splatter", "Blutspritzer" }, { 1, 2, "Lethality", "Tödlichkeit" },
          { 1, 1, "Cold Blood", "Kaltblütigkeit" },
          { 2, 3, "Coup de Grace", "Gnadenstoß" }, { 2, 2, "Efficient Strikes", "Effiziente Schläge" },
          { 2, 3, "Deflection", "Abwehr" }, { 2, 3, "Precision", "Präzision" }, { 2, 1, "Endurance", "Durchhaltevermögen" },
          { 2, 1, "Riposte", "Riposte" }, { 2, 2, "Composure", "Gelassenheit" },
          { 2, 1, "Flawless Execution", "Perfekte Ausführung" }, { 2, 2, "Weapon Expertise", "Waffenexperte" },
          { 2, 3, "Aggression", "Aggression" }, { 2, 2, "Dual Wield Specialization", "Beidhändigkeits-Spez." },
          { 2, 1, "Blade Flurry", "Klingenwirbel" }, { 2, 5, "Hack and Slash", "Niedermetzeln" },
          { 2, 5, "Flash of Steel", "Blitzender Stahl" }, { 2, 1, "Adrenaline Rush", "Adrenalinrausch" },
      } },
    { key = "combat-end", name = { de = "Kampf – Endspiel", en = "Combat – endgame" }, tree = 2, split = "16/35/0",
      grade = "single", purpose = { "dungeon", "raid" }, read = R,
      sources = { S("IV", "combat-rogue-melee-dps-pve-spec-builds-talents", "2026-11-04", "exact"),
          S("WT", "combat-rogue/", "2026-11-10", "core", "sitemap") },
      talents = {
          { 1, 5, "Malice", "Tücke" }, { 1, 3, "Ruthlessness", "Skrupellosigkeit" },
          { 1, 2, "Improved Expose Armor", "Verb. Rüstung schwächen" }, { 1, 3, "Improved Slice and Dice", "Verb. Zerhäckseln" },
          { 1, 1, "Blood Splatter", "Blutspritzer" }, { 1, 1, "Lethality", "Tödlichkeit" },
          { 1, 1, "Cold Blood", "Kaltblütigkeit" },
          { 2, 3, "Coup de Grace", "Gnadenstoß" }, { 2, 2, "Efficient Strikes", "Effiziente Schläge" },
          { 2, 1, "Lightning Reflexes", "Blitzartige Reflexe" }, { 2, 3, "Precision", "Präzision" },
          { 2, 2, "Improved Sprint", "Verb. Sprinten" }, { 2, 2, "Endurance", "Durchhaltevermögen" },
          { 2, 2, "Composure", "Gelassenheit" }, { 2, 1, "Flawless Execution", "Perfekte Ausführung" },
          { 2, 2, "Weapon Expertise", "Waffenexperte" }, { 2, 3, "Aggression", "Aggression" },
          { 2, 2, "Dual Wield Specialization", "Beidhändigkeits-Spez." }, { 2, 1, "Blade Flurry", "Klingenwirbel" },
          { 2, 5, "Hack and Slash", "Niedermetzeln" }, { 2, 5, "Flash of Steel", "Blitzender Stahl" },
          { 2, 1, "Adrenaline Rush", "Adrenalinrausch" },
      } },
    { key = "assa-mutilate", name = { de = "Meucheln – Verstümmeln", en = "Assassination – Mutilate" }, tree = 1,
      split = "33/18/0", grade = "single", purpose = { "dungeon", "raid" }, read = R,
      sources = { S("IV", "assassination-rogue-melee-dps-pve-spec-builds-talents", "2026-11-04", "exact"),
          S("KL", "build-voleur-assassinat-wow-forever/", "2026-11-09", "core", "textdate") },
      talents = {
          { 1, 5, "Malice", "Tücke" }, { 1, 3, "Ruthlessness", "Skrupellosigkeit" },
          { 1, 2, "Improved Expose Armor", "Verb. Rüstung schwächen" }, { 1, 3, "Improved Slice and Dice", "Verb. Zerhäckseln" },
          { 1, 1, "Blood Splatter", "Blutspritzer" }, { 1, 2, "Lethality", "Tödlichkeit" },
          { 1, 5, "Vile Poisons", "Üble Gifte" }, { 1, 1, "Cold Blood", "Kaltblütigkeit" },
          { 1, 1, "Improved Poisons", "Verb. Gifte" }, { 1, 5, "Relentless Strikes", "Unerbittliche Stöße" },
          { 1, 1, "Venom", "Toxin" }, { 1, 3, "Seal Fate", "Schicksal besiegeln" }, { 1, 1, "Mutilate", "Verstümmeln" },
          { 2, 3, "Coup de Grace", "Gnadenstoß" }, { 2, 2, "Lightning Reflexes", "Blitzartige Reflexe" },
          { 2, 3, "Puncturing Wounds", "Durchbohrende Wunden" }, { 2, 3, "Precision", "Präzision" },
          { 2, 2, "Endurance", "Durchhaltevermögen" }, { 2, 2, "Composure", "Gelassenheit" },
          { 2, 1, "Flawless Execution", "Perfekte Ausführung" }, { 2, 2, "Weapon Expertise", "Waffenexperte" },
      } },
    { key = "sub-bleed", name = { de = "Täuschung – Blutung", en = "Subtlety – bleed" }, tree = 3, split = "15/5/31",
      grade = "single", purpose = { "dungeon" }, read = R,
      sources = { S("IV", "subtlety-rogue-melee-dps-pve-spec-builds-talents", "2026-11-04", "exact"),
          S("KL", "build-voleur-finesse-wow-forever/", "2026-11-09", "core", "textdate") },
      talents = {
          { 1, 2, "Remorseless Attacks", "Gnadenlose Angriffe" }, { 1, 5, "Malice", "Tücke" },
          { 1, 3, "Ruthlessness", "Skrupellosigkeit" }, { 1, 2, "Improved Slice and Dice", "Verb. Zerhäckseln" },
          { 1, 1, "Blood Splatter", "Blutspritzer" }, { 1, 2, "Lethality", "Tödlichkeit" },
          { 2, 3, "Coup de Grace", "Gnadenstoß" }, { 2, 2, "Efficient Strikes", "Effiziente Schläge" },
          { 3, 3, "Setup", "Reinlegen" }, { 3, 5, "Opportunity", "Günstige Gelegenheit" },
          { 3, 2, "Dirty Deeds", "Gemeinheiten" }, { 3, 2, "Camouflage", "Camouflage" },
          { 3, 3, "Improved Ambush", "Verb. Hinterhalt" }, { 3, 3, "Initiative", "Initiative" },
          { 3, 1, "Premeditation", "Konzentration" }, { 3, 3, "Serrated Blades", "Gezahnte Klingen" },
          { 3, 1, "Ghostly Strike", "Geisterhafter Stoß" }, { 3, 1, "Preparation", "Vorbereitung" },
          { 3, 1, "Hemorrhage", "Blutsturz" }, { 3, 5, "Boot Knife", "Stiefelmesser" }, { 3, 1, "Death Mark", "Todesmal" },
      } },
}

---------------------------------------------------------------------------
-- Priester (Bäume: 1 Disziplin, 2 Heilig, 3 Schatten)
---------------------------------------------------------------------------

P.PRIEST = {
    { key = "holy-group", name = { de = "Heilig – Gruppenheiler", en = "Holy – group healer" }, tree = 2, split = "17/34/0",
      grade = "checked", purpose = { "healer" }, read = R,
      sources = { S("IV", "holy-priest-healer-pve-spec-builds-talents", "2026-11-04", "exact"),
          S("MOB", "classes/holy-priest-guide", "2026-11-13", "core"),
          S("CH", "priester", "2026-11-10", "core"),
          S("RB", "priest/", "2026-11-08", "derived") },
      talents = {
          { 1, 5, "Twin Disciplines", "Zwillingsdisziplinen" }, { 1, 3, "Silent Resolve", "Schweigsame Entschlossenheit" },
          { 1, 5, "Mental Strength", "Mentale Stärke" }, { 1, 1, "Inner Focus", "Innerer Fokus" },
          { 1, 3, "Meditation", "Meditation" },
          { 2, 3, "Improved Renew", "Verb. Erneuerung" }, { 2, 5, "Holy Specialization", "Heiligspezialisierung" },
          { 2, 5, "Divine Fury", "Göttlicher Furor" }, { 2, 1, "Holy Nova", "Heilige Nova" },
          { 2, 3, "Inspiration", "Inspiration" }, { 2, 3, "Improved Healing", "Verb. Heilung" },
          { 2, 2, "Searing Light", "Sengendes Licht" }, { 2, 2, "Litany of Light", "Litanei des Lichts" },
          { 2, 1, "Spirit of Redemption", "Geist der Erlösung" }, { 2, 5, "Spiritual Guidance", "Geistige Führung" },
          { 2, 3, "Spiritual Healing", "Spirituelle Heilung" }, { 2, 1, "Prayer of Mending", "Gebet der Besserung" },
      } },
    { key = "disc-shield", name = { de = "Disziplin – Schild/Tank", en = "Discipline – shields/tank" }, tree = 1,
      split = "31/20/0", grade = "checked", purpose = { "healer" }, read = R,
      sources = { S("IV", "discipline-priest-healer-pve-spec-builds-talents", "2026-11-04", "exact"),
          S("MOB", "classes/discipline-priest-guide-progress", "2026-11-11", "exact"),
          S("RB", "priest/", "2026-11-08", "derived") },
      talents = {
          { 1, 5, "Twin Disciplines", "Zwillingsdisziplinen" }, { 1, 5, "Mental Strength", "Mentale Stärke" },
          { 1, 3, "Mental Agility", "Mentale Beweglichkeit" }, { 1, 1, "Inner Focus", "Innerer Fokus" },
          { 1, 3, "Improved Power Word: Shield", "Verb. Machtwort: Schild" }, { 1, 3, "Meditation", "Meditation" },
          { 1, 1, "Soul Warding", "Seelenwehr" }, { 1, 1, "Penance", "Sühne" },
          { 1, 5, "Renewed Hope", "Erneuerte Hoffnung" }, { 1, 3, "Divine Aegis", "Göttliche Aegis" },
          { 1, 1, "Power Infusion", "Seele der Macht" },
          { 2, 3, "Twilight Focus", "Zwielichtfokus" }, { 2, 5, "Holy Specialization", "Heiligspezialisierung" },
          { 2, 5, "Divine Fury", "Göttlicher Furor" }, { 2, 1, "Holy Nova", "Heilige Nova" },
          { 2, 3, "Inspiration", "Inspiration" }, { 2, 1, "Holy Reach", "Heilige Reichweite" },
          { 2, 2, "Searing Light", "Sengendes Licht" },
      } },
    { key = "shadow-end", name = { de = "Schatten – Endspiel", en = "Shadow – endgame" }, tree = 3, split = "15/3/33",
      grade = "checked", purpose = { "dungeon", "raid" }, read = R,
      sources = { S("IV", "shadow-priest-ranged-dps-pve-spec-builds-talents", "2026-11-04", "exact"),
          S("MOB", "classes/shadow-priest-guide-progress", "2026-11-11", "core"),
          S("CH", "priester", "2026-11-13", "core"),
          S("RB", "priest/", "2026-11-08", "derived") },
      talents = {
          { 1, 5, "Twin Disciplines", "Zwillingsdisziplinen" }, { 1, 3, "Silent Resolve", "Schweigsame Entschlossenheit" },
          { 1, 4, "Mental Strength", "Mentale Stärke" }, { 1, 3, "Meditation", "Meditation" },
          { 2, 3, "Twilight Focus", "Zwielichtfokus" },
          { 3, 5, "Shadow Focus", "Schattenfokus" }, { 3, 4, "Improved Mind Blast", "Verb. Gedankenschlag" },
          { 3, 2, "Improved Shadow Word: Pain", "Verb. Schattenwort: Schmerz" }, { 3, 1, "Shadow Reach", "Schattenreichweite" },
          { 3, 1, "Mind Flay", "Gedankenschinden" }, { 3, 2, "Improved Mind Flay", "Verb. Gedankenschinden" },
          { 3, 5, "Dark Inspiration", "Dunkle Inspiration" }, { 3, 1, "Vampiric Embrace", "Vampirumarmung" },
          { 3, 3, "Shadow Weaving", "Schattenwirken" }, { 3, 1, "Silence", "Stille" },
          { 3, 2, "Devouring Contagion", "Verschlingende Ansteckung" }, { 3, 5, "Darkness", "Dunkelheit" },
          { 3, 1, "Shadowform", "Schattengestalt" },
      } },
    { key = "shadow-leveling", name = { de = "Schatten – Leveln", en = "Shadow – leveling" }, tree = 3, split = "13/3/35",
      grade = "single", purpose = { "leveling" }, read = R,
      sources = { S("IV", "shadow-priest-leveling", "2026-11-04", "exact"),
          S("MOB", "classes/shadow-priest-guide-progress", "2026-11-11", "core", "purpose") },   -- Endspiel-Guide
      talents = {
          { 1, 2, "Wand Specialization", "Zauberstab-Spez." }, { 1, 3, "Twin Disciplines", "Zwillingsdisziplinen" },
          { 1, 5, "Mental Strength", "Mentale Stärke" }, { 1, 3, "Meditation", "Meditation" },
          { 2, 3, "Twilight Focus", "Zwielichtfokus" },
          { 3, 2, "Shadow Focus", "Schattenfokus" }, { 3, 5, "Spirit Tap", "Willensentzug" },
          { 3, 4, "Improved Mind Blast", "Verb. Gedankenschlag" },
          { 3, 2, "Improved Shadow Word: Pain", "Verb. Schattenwort: Schmerz" }, { 3, 1, "Shadow Reach", "Schattenreichweite" },
          { 3, 1, "Mind Flay", "Gedankenschinden" }, { 3, 2, "Improved Mind Flay", "Verb. Gedankenschinden" },
          { 3, 5, "Dark Inspiration", "Dunkle Inspiration" }, { 3, 1, "Vampiric Embrace", "Vampirumarmung" },
          { 3, 3, "Shadow Weaving", "Schattenwirken" }, { 3, 1, "Silence", "Stille" },
          { 3, 2, "Devouring Contagion", "Verschlingende Ansteckung" }, { 3, 5, "Darkness", "Dunkelheit" },
          { 3, 1, "Shadowform", "Schattengestalt" },
      } },
    { key = "disc-leveling", name = { de = "Disziplin – Leveln", en = "Discipline – leveling" }, tree = 1, split = "33/13/5",
      grade = "single", purpose = { "leveling", "healer" }, read = R,
      sources = { S("IV", "discipline-priest-leveling", "2026-11-10", "exact"),
          S("MOB", "classes/discipline-priest-guide-progress", "2026-11-11", "core", "purpose") },   -- Endspiel, 31/20/0
      talents = {
          { 1, 5, "Power in Light", "Macht im Licht" }, { 1, 2, "Wand Specialization", "Zauberstab-Spez." },
          { 1, 5, "Mental Strength", "Mentale Stärke" }, { 1, 3, "Mental Agility", "Mentale Beweglichkeit" },
          { 1, 1, "Inner Focus", "Innerer Fokus" }, { 1, 3, "Improved Power Word: Shield", "Verb. Machtwort: Schild" },
          { 1, 3, "Meditation", "Meditation" }, { 1, 1, "Soul Warding", "Seelenwehr" }, { 1, 1, "Penance", "Sühne" },
          { 1, 5, "Renewed Hope", "Erneuerte Hoffnung" }, { 1, 3, "Divine Aegis", "Göttliche Aegis" },
          { 1, 1, "Power Infusion", "Seele der Macht" },
          { 2, 3, "Twilight Focus", "Zwielichtfokus" }, { 2, 5, "Holy Specialization", "Heiligspezialisierung" },
          { 2, 5, "Divine Fury", "Göttlicher Furor" },
          { 3, 5, "Spirit Tap", "Willensentzug" },
      } },
}

---------------------------------------------------------------------------
-- Schamane (Bäume: 1 Elementar, 2 Verstärkung, 3 Wiederherstellung)
---------------------------------------------------------------------------

local SHAMAN_RESTO_DIP = {   -- 11 Punkte Wiederherstellung, in drei Bäumen gleich
    { 3, 5, "Tidal Focus", "Gezeitenfokus" }, { 3, 3, "Mindfulness", "Achtsamkeit" },
    { 3, 2, "Totemic Focus", "Totemfokus" }, { 3, 1, "Water Shield", "Wasserschild" },
}

P.SHAMAN = {
    { key = "ele-aoe", name = { de = "Elementar – Gruppe/AoE", en = "Elemental – group/AoE" }, tree = 1, split = "32/8/11",
      grade = "checked", purpose = { "dungeon", "raid" }, read = R,
      sources = { S("IV", "elemental-shaman-ranged-dps-pve-spec-builds-talents", "2026-11-04", "exact"),
          S("CH", "schamane", "2026-11-12", "core"),
          S("RB", "shaman/", "2026-11-08", "core") },
      talents = With({
          { 1, 5, "Convection", "Konvektion" }, { 1, 5, "Concussion", "Erschütterung" },
          { 1, 3, "Elemental Alacrity", "Elementare Geschwindigkeit" }, { 1, 3, "Call of Flame", "Ruf der Flamme" },
          { 1, 1, "Elemental Focus", "Elementarfokus" }, { 1, 2, "Trial by Fire", "Feuerprobe" },
          { 1, 3, "Eye of the Storm", "Auge des Sturms" }, { 1, 1, "Call of Thunder", "Ruf des Donners" },
          { 1, 3, "Lightning Overload", "Blitzschlag-Überladung" }, { 1, 5, "Elemental Fury", "Elementarfuror" },
          { 1, 1, "Lightning Mastery", "Blitzbeherrschung" },
          { 2, 5, "Thundering Strikes", "Donnernde Stöße" }, { 2, 3, "Ancestral Knowledge", "Wissen der Ahnen" },
      }, SHAMAN_RESTO_DIP) },
    { key = "ele-leveling", name = { de = "Elementar – Leveln/Solo", en = "Elemental – leveling/solo" }, tree = 1,
      split = "31/9/11", grade = "single", purpose = { "leveling", "solo" }, read = R,
      -- Mobalytics bestätigt den Kern (Build „Solo Single Target“, Stand 06.11.), die genaue Seite ist aber nicht notiert –
      -- ohne Seite keine Quelle (Gegenprüfung 14.11.2026): herabgestuft auf „eine Quelle“, bis die Seite belegt ist.
      -- Nachführen 14.11.2026: Kandidat laut Websuche „classes/elemental-shaman-leveling-guide“, aber nicht abrufbar
      -- (Fehler 403) – ungelesen, also weiter keine Quelle
      sources = { S("ZO", "shaman/leveling/", "2026-11-12", "exact") },
      talents = With({
          { 1, 5, "Convection", "Konvektion" }, { 1, 5, "Concussion", "Erschütterung" },
          { 1, 3, "Elemental Alacrity", "Elementare Geschwindigkeit" }, { 1, 3, "Call of Flame", "Ruf der Flamme" },
          { 1, 1, "Elemental Focus", "Elementarfokus" }, { 1, 3, "Eye of the Storm", "Auge des Sturms" },
          { 1, 1, "Earthbound", "Erdgebunden" }, { 1, 1, "Call of Thunder", "Ruf des Donners" },
          { 1, 3, "Lightning Overload", "Blitzschlag-Überladung" }, { 1, 5, "Elemental Fury", "Elementarfuror" },
          { 1, 1, "Lightning Mastery", "Blitzbeherrschung" },
          { 2, 5, "Thundering Strikes", "Donnernde Stöße" }, { 2, 4, "Ancestral Knowledge", "Wissen der Ahnen" },
      }, SHAMAN_RESTO_DIP) },
    { key = "enh-leveling", name = { de = "Verstärkung – Leveln/Solo", en = "Enhancement – leveling/solo" }, tree = 2,
      split = "8/32/11", grade = "single", purpose = { "leveling", "solo" }, read = R,
      sources = { S("ZO", "shaman/leveling/", "2026-11-12", "exact") },
      talents = With({
          { 1, 5, "Concussion", "Erschütterung" }, { 1, 3, "Elemental Devastation", "Elementarverwüstung" },
          { 2, 5, "Thundering Strikes", "Donnernde Stöße" }, { 2, 3, "Ancestral Knowledge", "Wissen der Ahnen" },
          { 2, 3, "Mental Dexterity", "Geistige Gewandtheit" }, { 2, 3, "Elemental Weapons", "Elementarwaffen" },
          { 2, 1, "Shamanistic Focus", "Schamanistischer Fokus" }, { 2, 3, "Flurry", "Schlaghagel" },
          { 2, 1, "Stormstrike", "Sturmschlag" }, { 2, 2, "Improved Ghost Wolf", "Verb. Geisterwolf" },
          { 2, 1, "Spirit Weapons", "Waffen der Geister" }, { 2, 2, "Mental Quickness", "Geistige Schnelligkeit" },
          { 2, 2, "Improved Stormstrike", "Verb. Sturmschlag" }, { 2, 5, "Maelstrom Weapon", "Waffe des Mahlstroms" },
          { 2, 1, "Rage of the Farseer", "Zorn des Scharfsehers" },
      }, SHAMAN_RESTO_DIP) },
    { key = "enh-end", name = { de = "Verstärkung – Endspiel", en = "Enhancement – endgame" }, tree = 2, split = "17/34/0",
      grade = "single", purpose = { "dungeon" }, read = R,
      sources = { S("ME", "class-guides/enhancement-shaman/talents", "2026-11-12", "exact") },
      talents = {
          { 1, 5, "Concussion", "Erschütterung" }, { 1, 3, "Elemental Devastation", "Elementarverwüstung" },
          { 1, 3, "Reverberation", "Nachklingen" }, { 1, 3, "Call of Flame", "Ruf der Flamme" },
          { 1, 1, "Elemental Focus", "Elementarfokus" }, { 1, 2, "Trial by Fire", "Feuerprobe" },
          { 2, 5, "Thundering Strikes", "Donnernde Stöße" }, { 2, 5, "Ancestral Knowledge", "Wissen der Ahnen" },
          { 2, 3, "Mental Dexterity", "Geistige Gewandtheit" }, { 2, 3, "Elemental Weapons", "Elementarwaffen" },
          { 2, 1, "Shamanistic Focus", "Schamanistischer Fokus" }, { 2, 5, "Flurry", "Schlaghagel" },
          { 2, 1, "Stormstrike", "Sturmschlag" }, { 2, 1, "Spirit Weapons", "Waffen der Geister" },
          { 2, 2, "Mental Quickness", "Geistige Schnelligkeit" }, { 2, 2, "Improved Stormstrike", "Verb. Sturmschlag" },
          { 2, 5, "Maelstrom Weapon", "Waffe des Mahlstroms" }, { 2, 1, "Rage of the Farseer", "Zorn des Scharfsehers" },
      } },
    { key = "resto-healer", name = { de = "Wiederherstellung – Heiler", en = "Restoration – healer" }, tree = 3,
      split = "0/10/41", grade = "single", purpose = { "healer" }, read = R,
      sources = { S("IV", "restoration-shaman-healer-pve-spec-builds-talents", "2026-11-04", "exact"),
          S("RB", "shaman/#build=auth-shaman-restoration-healing", "2026-11-08", "derived") },
      talents = {
          { 2, 5, "Thundering Strikes", "Donnernde Stöße" }, { 2, 5, "Ancestral Knowledge", "Wissen der Ahnen" },
          { 3, 5, "Improved Healing Wave", "Verb. Welle der Heilung" }, { 3, 5, "Tidal Focus", "Gezeitenfokus" },
          { 3, 3, "Mindfulness", "Achtsamkeit" }, { 3, 3, "Ancestral Healing", "Heilung der Ahnen" },
          { 3, 3, "Healing Focus", "Heilfokus" }, { 3, 1, "Water Shield", "Wasserschild" },
          { 3, 5, "Tidal Mastery", "Gezeitenbeherrschung" }, { 3, 5, "Restorative Totems", "Regenerationstotems" },
          { 3, 1, "Mana Tide Totem", "Totem der Manaflut" }, { 3, 3, "Healing Way", "Pfad der Heilung" },
          { 3, 1, "Nature's Swiftness", "Schnelligkeit der Natur" }, { 3, 5, "Purification", "Läuterung" },
          { 3, 1, "Riptide", "Springflut" },
      } },
}

---------------------------------------------------------------------------
-- Magier (Bäume: 1 Arkan, 2 Feuer, 3 Frost) – zwei Talente heißen deutsch „Verbrennung“ (Incineration, Combustion);
-- die Zuordnung trennt sie über den Höchstrang.
---------------------------------------------------------------------------

P.MAGE = {
    { key = "frost-leveling", name = { de = "Frost – Leveln (mit Arkan)", en = "Frost – leveling (with Arcane)" }, tree = 3,
      split = "18/0/33", grade = "single", purpose = { "leveling" }, read = R,
      sources = { S("ME", "wow-forever-mage-leveling-guide-and-talents", "2026-11-10", "exact") },
      talents = {
          { 1, 5, "Improved Channeling", "Verb. Kanalisierung" }, { 1, 5, "Arcane Concentration", "Arkane Konzentration" },
          { 1, 2, "Missile Barrage", "Geschosssalve" }, { 1, 2, "Arcane Subtlety", "Arkanes Feingefühl" },
          { 1, 1, "Arcane Blast", "Arkanschlag" }, { 1, 3, "Arcane Meditation", "Arkane Meditation" },
          { 3, 5, "Improved Frostbolt", "Verb. Frostblitz" }, { 3, 3, "Precision", "Präzision" },
          { 3, 3, "Frostbite", "Erfrierung" }, { 3, 1, "Ice Lance", "Eislanze" }, { 3, 5, "Ice Shards", "Eissplitter" },
          { 3, 1, "Ice Block", "Eisblock" }, { 3, 3, "Shatter", "Zertrümmern" }, { 3, 2, "Fingers of Frost", "Eisige Finger" },
          { 3, 3, "Improved Cone of Cold", "Verb. Kältekegel" }, { 3, 1, "Cold Snap", "Kälteeinbruch" },
          { 3, 5, "Winter's Chill", "Winterkälte" }, { 3, 1, "Ice Barrier", "Eisbarriere" },
      } },
    { key = "frost-deep", name = { de = "Frost – Tiefer Frost", en = "Frost – deep frost" }, tree = 3, split = "7/0/44",
      grade = "single", purpose = { "leveling", "solo", "dungeon" }, read = R,
      sources = { S("IV", "frost-mage-ranged-dps-pve-spec-builds-talents", "2026-11-10", "exact"),
          S("IV", "frost-mage-leveling", "2026-11-10", "core") },
      talents = {
          { 1, 2, "Wand Specialization", "Zauberstab-Spez." }, { 1, 3, "Arcane Resilience", "Arkane Widerstandsfähigkeit" },
          { 1, 2, "Arcane Subtlety", "Arkanes Feingefühl" },
          { 3, 1, "Frost Warding", "Schutz des Frostes" }, { 3, 5, "Improved Frostbolt", "Verb. Frostblitz" },
          { 3, 3, "Precision", "Präzision" }, { 3, 5, "Ice Shards", "Eissplitter" },
          { 3, 2, "Improved Frost Nova", "Verb. Frostnova" }, { 3, 3, "Permafrost", "Dauerfrost" },
          { 3, 3, "Frost Channeling", "Frost-Kanalisierung" }, { 3, 3, "Improved Blizzard", "Verb. Blizzard" },
          { 3, 1, "Ice Lance", "Eislanze" }, { 3, 2, "Arctic Reach", "Arktische Reichweite" },
          { 3, 1, "Ice Block", "Eisblock" }, { 3, 3, "Shatter", "Zertrümmern" },
          { 3, 3, "Improved Cone of Cold", "Verb. Kältekegel" }, { 3, 1, "Cold Snap", "Kälteeinbruch" },
          { 3, 2, "Fingers of Frost", "Eisige Finger" }, { 3, 5, "Winter's Chill", "Winterkälte" },
          { 3, 1, "Ice Barrier", "Eisbarriere" },
      } },
    { key = "frost-raid", name = { de = "Frost – Raid (Kältekegel)", en = "Frost – raid (Cone of Cold)" }, tree = 3,
      split = "18/0/33", grade = "checked", purpose = { "raid" }, read = R,
      -- RankedBoost „Frost Mage DPS“ verteilt 19/0/32 mit Verb. Kältekegel 3/3 und Winterkälte 5/5 (Seite aktualisiert
      -- 08.11., nachgeprüft 14.11.2026): im Kern gleich, eigene Seite – erfüllt die strenge Regel, hochgestuft
      sources = { S("IV", "frost-mage-ranged-dps-pve-spec-builds-talents", "2026-11-10", "exact"),
          S("RB", "mage/", "2026-11-08", "core") },
      talents = {
          { 1, 2, "Wand Specialization", "Zauberstab-Spez." }, { 1, 3, "Arcane Resilience", "Arkane Widerstandsfähigkeit" },
          { 1, 2, "Arcane Subtlety", "Arkanes Feingefühl" }, { 1, 2, "Magic Absorption", "Magische Vereinnahmung" },
          { 1, 5, "Arcane Concentration", "Arkane Konzentration" }, { 1, 1, "Arcane Geometry", "Arkane Geometrie" },
          { 1, 3, "Arcane Meditation", "Arkane Meditation" },
          { 3, 5, "Improved Frostbolt", "Verb. Frostblitz" }, { 3, 3, "Precision", "Präzision" },
          { 3, 5, "Ice Shards", "Eissplitter" }, { 3, 1, "Improved Blizzard", "Verb. Blizzard" },
          { 3, 1, "Ice Lance", "Eislanze" }, { 3, 2, "Arctic Reach", "Arktische Reichweite" },
          { 3, 1, "Ice Block", "Eisblock" }, { 3, 3, "Shatter", "Zertrümmern" },
          { 3, 3, "Improved Cone of Cold", "Verb. Kältekegel" }, { 3, 1, "Cold Snap", "Kälteeinbruch" },
          { 3, 2, "Fingers of Frost", "Eisige Finger" }, { 3, 5, "Winter's Chill", "Winterkälte" },
          { 3, 1, "Ice Barrier", "Eisbarriere" },
      } },
    { key = "arcane-fire", name = { de = "Arkan – Arkan/Feuer", en = "Arcane – arcane/fire" }, tree = 1, split = "32/16/3",
      grade = "single", purpose = { "raid", "dungeon" }, read = R,
      sources = { S("IV", "arcane-mage-ranged-dps-pve-spec-builds-talents", "2026-11-04", "exact"),
          S("RB", "mage/", "2026-11-08", "derived") },
      talents = {
          { 1, 5, "Improved Channeling", "Verb. Kanalisierung" }, { 1, 2, "Arcane Subtlety", "Arkanes Feingefühl" },
          { 1, 5, "Arcane Concentration", "Arkane Konzentration" }, { 1, 2, "Missile Barrage", "Geschosssalve" },
          { 1, 3, "Arcane Impact", "Arkaner Einschlag" }, { 1, 1, "Arcane Blast", "Arkanschlag" },
          { 1, 3, "Arcane Meditation", "Arkane Meditation" }, { 1, 1, "Arcane Wrath", "Arkaner Zorn" },
          { 1, 1, "Presence of Mind", "Geistesgegenwart" }, { 1, 5, "Arcane Mind", "Arkaner Geist" },
          { 1, 3, "Arcane Instability", "Arkane Instabilität" }, { 1, 1, "Arcane Power", "Arkane Macht" },
          { 2, 5, "Incineration", "Verbrennung" }, { 2, 2, "Accelerant", "Beschleuniger" }, { 2, 5, "Ignite", "Entzünden" },
          { 2, 1, "Pyroblast", "Pyroschlag" }, { 2, 2, "Improved Fire Blast", "Verb. Feuerschlag" },
          { 2, 1, "Heating Up", "Aufwärmen" },
          { 3, 3, "Precision", "Präzision" },
      } },
    { key = "fire-arcane", name = { de = "Feuer – Feuer/Arkan", en = "Fire – fire/arcane" }, tree = 2, split = "16/32/3",
      grade = "single", purpose = { "raid", "dungeon" }, read = R,
      sources = { S("IV", "fire-mage-ranged-dps-pve-spec-builds-talents", "2026-11-04", "exact"),
          S("RB", "mage/", "2026-11-08", "derived") },
      talents = {
          { 1, 5, "Improved Channeling", "Verb. Kanalisierung" }, { 1, 2, "Arcane Subtlety", "Arkanes Feingefühl" },
          { 1, 5, "Arcane Concentration", "Arkane Konzentration" }, { 1, 2, "Missile Barrage", "Geschosssalve" },
          { 1, 1, "Arcane Blast", "Arkanschlag" }, { 1, 1, "Arcane Meditation", "Arkane Meditation" },
          { 2, 5, "Incineration", "Verbrennung" }, { 2, 5, "Accelerant", "Beschleuniger" }, { 2, 5, "Ignite", "Entzünden" },
          { 2, 1, "Pyroblast", "Pyroschlag" }, { 2, 2, "Improved Fire Blast", "Verb. Feuerschlag" },
          { 2, 3, "Improved Scorch", "Verb. Versengen" }, { 2, 1, "Heating Up", "Aufwärmen" },
          { 2, 3, "Master of Elements", "Meister der Elemente" }, { 2, 3, "Critical Mass", "Kritische Masse" },
          { 2, 3, "Fire Power", "Feuermacht" }, { 2, 1, "Combustion", "Verbrennung" },
          { 3, 3, "Precision", "Präzision" },
      } },
}

---------------------------------------------------------------------------
-- Hexenmeister (Bäume: 1 Gebrechen, 2 Dämonologie, 3 Zerstörung) – deutsche Namen nur zwei belegt
---------------------------------------------------------------------------

local DESTRUCTION_CORE = {   -- 33 Punkte Zerstörung, in zwei Bäumen gleich
    { 3, 5, "Bane" }, { 3, 3, "Cataclysm" }, { 3, 5, "Aftermath" }, { 3, 5, "Ruin" }, { 3, 1, "Shadowburn" },
    { 3, 3, "Agonizing Flames" }, { 3, 1, "Conflagrate" }, { 3, 1, "Bane of Havoc" }, { 3, 3, "Fire and Brimstone" },
    { 3, 5, "Shadow and Flame" }, { 3, 1, "Incinerate" },
}

P.WARLOCK = {
    { key = "aff-wrack", name = { de = "Gebrechen – Wrack", en = "Affliction – Wrack" }, tree = 1, split = "35/11/5",
      grade = "checked", purpose = { "raid", "dungeon" }, read = R,
      sources = { S("WT", "affliction-warlock/", "2026-11-11", "exact"),
          S("MOB", "classes/affliction-warlock-guide", "2026-11-12", "exact"),
          S("MOB", "classes/affliction-warlock-guide-progress", "2026-11-13", "core") },
      talents = {
          { 1, 2, "Improved Life Tap" }, { 1, 5, "Suppression" }, { 1, 5, "Improved Corruption" },
          { 1, 2, "Improved Bane of Agony" }, { 1, 1, "Amplify Curse" }, { 1, 3, "Pandemic" }, { 1, 5, "Malevolence" },
          { 1, 2, "Nightfall" }, { 1, 1, "Siphon Life" }, { 1, 3, "Soul Siphon" }, { 1, 5, "Shadow Mastery" },
          { 1, 1, "Wrack" },
          { 2, 5, "Demonic Embrace" }, { 2, 2, "Demonic Aegis" }, { 2, 3, "Fel Vitality" },
          { 2, 1, "Demonic Sacrifice", "Dämonische Opferung" },
          { 3, 5, "Improved Shadow Bolt" },
      } },
    { key = "aff-ruin", name = { de = "Gebrechen – Schattenmeisterschaft/Ruin", en = "Affliction – Shadow Mastery/Ruin" },
      tree = 1, split = "30/0/21", grade = "checked", purpose = { "raid", "dungeon" }, read = R,
      -- Warcraft Tavern führt „SM Ruin“ 30/0/21 mit Seitendatum („Last updated“ 11.11., nachgeprüft 14.11.2026),
      -- Mobalytics (Raid-Guide, datiert) im Kern gleich – erfüllt die strenge Regel, hochgestuft
      sources = { S("WT", "affliction-warlock/", "2026-11-11", "exact"),
          S("MOB", "classes/affliction-warlock-guide-progress", "2026-11-13", "core") },
      talents = {
          { 1, 2, "Improved Life Tap" }, { 1, 5, "Suppression" }, { 1, 5, "Improved Corruption" },
          { 1, 1, "Improved Bane of Agony" }, { 1, 1, "Amplify Curse" }, { 1, 3, "Pandemic" }, { 1, 5, "Malevolence" },
          { 1, 2, "Nightfall" }, { 1, 1, "Siphon Life" }, { 1, 5, "Shadow Mastery" },
          { 3, 5, "Improved Shadow Bolt" }, { 3, 5, "Bane" }, { 3, 3, "Cataclysm" }, { 3, 5, "Ruin" },
          { 3, 3, "Agonizing Flames" },
      } },
    { key = "demo-pact", name = { de = "Dämonologie – Schatten, Sukkubus, Pakt", en = "Demonology – shadow, succubus, pact" },
      tree = 2, split = "2/31/18", grade = "checked", purpose = { "raid", "dungeon" }, read = R,
      sources = { S("MOB", "classes/demonology-warlock-guide-progress", "2026-11-06", "exact"),
          S("CH", "hexenmeister", "2026-11-09", "exact"),
          S("RB", "warlock/", "2026-11-08", "derived") },
      talents = {
          { 1, 1, "Suppression" }, { 1, 1, "Improved Corruption" },
          { 2, 5, "Unholy Power" }, { 2, 3, "Fel Vitality" }, { 2, 2, "Demonic Energies" }, { 2, 3, "Improved Sayaad" },
          { 2, 1, "Demonic Sacrifice", "Dämonische Opferung" }, { 2, 2, "Master Summoner" }, { 2, 2, "Decimation" },
          { 2, 3, "Demonic Brand" }, { 2, 1, "Soul Link" }, { 2, 3, "Demonic Knowledge" },
          { 2, 5, "Master Demonologist" }, { 2, 1, "Demonic Pact", "Dämonischer Pakt" },
          { 3, 5, "Improved Shadow Bolt" }, { 3, 5, "Bane" }, { 3, 5, "Ruin" }, { 3, 3, "Agonizing Flames" },
      } },
    { key = "destro-sacrifice", name = { de = "Zerstörung – Feuer mit Opferung", en = "Destruction – fire with sacrifice" },
      tree = 3, split = "7/11/33", grade = "checked", purpose = { "raid", "dungeon" }, read = R,
      sources = { S("IV", "destruction-warlock-ranged-dps-pve-spec-builds-talents", "2026-11-04", "exact"),
          S("MOB", "classes/destruction-warlock-guide-progress", "2026-11-06", "core"),
          S("RB", "warlock/", "2026-11-08", "derived") },
      talents = With({
          { 1, 5, "Suppression" }, { 1, 2, "Improved Corruption" },
          { 2, 5, "Demonic Embrace" }, { 2, 2, "Demonic Aegis" }, { 2, 3, "Fel Vitality" },
          { 2, 1, "Demonic Sacrifice", "Dämonische Opferung" },
      }, DESTRUCTION_CORE) },
    { key = "destro-sayaad", name = { de = "Zerstörung – Sukkubus/Sayaad", en = "Destruction – succubus/sayaad" }, tree = 3,
      split = "14/4/33", grade = "single", purpose = { "raid", "dungeon" }, read = R,
      sources = { S("CH", "hexenmeister", "2026-11-04", "exact"),
          S("MOB", "classes/destruction-warlock-guide", "2026-11-12", "extra", "content") },
      talents = With({
          { 1, 2, "Improved Life Tap" }, { 1, 5, "Suppression" }, { 1, 3, "Improved Corruption" },
          { 1, 1, "Amplify Curse" }, { 1, 3, "Pandemic" },
          { 2, 4, "Unholy Power" },
      }, DESTRUCTION_CORE) },
}

---------------------------------------------------------------------------
-- Druide (Bäume: 1 Gleichgewicht, 2 Wilder Kampf, 3 Wiederherstellung; drei Bäume angenommen – Spielprüfung)
---------------------------------------------------------------------------

local DRUID_RESTO_DIP = {   -- 10 Punkte Wiederherstellung, in drei Wilder-Kampf-Bäumen gleich
    { 3, 5, "Heart of the Wild", "Herz der Wildnis" }, { 3, 5, "Naturalist", "Naturalist" },
}

P.DRUID = {
    { key = "feral-leveling", name = { de = "Wilder Kampf – Leveln", en = "Feral – leveling" }, tree = 2, split = "9/32/10",
      grade = "single", purpose = { "leveling", "solo" }, read = R,
      sources = { S("IV", "feral-druid-leveling", "2026-11-04", "exact"),
          S("MOB", "classes/feral-druid-tank-guide", "2026-11-13", "core", "purpose") },   -- Tank-Guide, 8/33/10
      talents = With({
          { 1, 5, "Genesis", "Genesis" }, { 1, 2, "Nature's Reach", "Reichweite der Natur" },
          { 1, 2, "Nature's Majesty", "Erhabenheit der Natur" },
          { 2, 5, "Ferocity", "Wildheit" }, { 2, 3, "Feral Instinct", "Instinkt der Wildnis" },
          { 2, 2, "Feral Swiftness", "Schnelligkeit der Wildnis" }, { 2, 1, "Feral Charge", "Wilde Attacke" },
          { 2, 2, "Savage Fury", "Ungezähmte Wut" }, { 2, 2, "Sharpened Claws", "Geschärfte Klauen" },
          { 2, 1, "Lacerate", "Aufschlitzen" }, { 2, 2, "Blood Frenzy", "Blutraserei" },
          { 2, 1, "Predatory Discipline", "Disziplin des Raubtiers" }, { 2, 3, "Predatory Strikes", "Raubtierschläge" },
          { 2, 1, "Leader of the Pack", "Rudelführer" }, { 2, 2, "Natural Instinct", "Instinkt der Natur" },
          { 2, 5, "Rend and Tear", "Beißen und Reißen" }, { 2, 1, "Primal Bite", "Urtümlicher Biss" },
          { 2, 1, "Shifting Power", "Machtverschiebung" },
      }, DRUID_RESTO_DIP) },
    { key = "feral-hybrid", name = { de = "Wilder Kampf – Hybrid Bär/Katze", en = "Feral – hybrid bear/cat" }, tree = 2,
      split = "8/33/10", grade = "checked", purpose = { "tank", "dungeon" }, read = R,
      sources = { S("IV", "feral-druid-melee-dps-and-tank-pve-spec-builds-talents", "2026-11-04", "exact"),
          S("MOB", "classes/feral-druid-tank-guide", "2026-11-13", "exact") },
      talents = With({
          { 1, 5, "Genesis", "Genesis" }, { 1, 1, "Nature's Majesty", "Erhabenheit der Natur" },
          { 1, 2, "Nature's Reach", "Reichweite der Natur" },
          { 2, 5, "Ferocity", "Wildheit" }, { 2, 2, "Feral Swiftness", "Schnelligkeit der Wildnis" },
          { 2, 3, "Feral Instinct", "Instinkt der Wildnis" }, { 2, 3, "Thick Hide", "Dickes Fell" },
          { 2, 2, "Savage Fury", "Ungezähmte Wut" }, { 2, 1, "Feral Charge", "Wilde Attacke" },
          { 2, 2, "Sharpened Claws", "Geschärfte Klauen" }, { 2, 3, "Predatory Strikes", "Raubtierschläge" },
          { 2, 1, "Lacerate", "Aufschlitzen" }, { 2, 1, "Predatory Discipline", "Disziplin des Raubtiers" },
          { 2, 1, "Leader of the Pack", "Rudelführer" }, { 2, 2, "Natural Instinct", "Instinkt der Natur" },
          { 2, 5, "Rend and Tear", "Beißen und Reißen" }, { 2, 1, "Primal Bite", "Urtümlicher Biss" },
          { 2, 1, "Shifting Power", "Machtverschiebung" },
      }, DRUID_RESTO_DIP) },
    { key = "feral-cat", name = { de = "Wilder Kampf – Katze", en = "Feral – cat" }, tree = 2, split = "9/32/10",
      grade = "single", purpose = { "raid", "dungeon" }, read = R,
      sources = { S("MOB", "classes/feral-druid-guide", "2026-11-11", "exact"),
          S("KL", "build-druide-farouche-wow-forever/", "2026-11-09", "core", "textdate") },
      talents = With({
          { 1, 5, "Genesis", "Genesis" }, { 1, 2, "Nature's Majesty", "Erhabenheit der Natur" },
          { 1, 2, "Nature's Reach", "Reichweite der Natur" },
          { 2, 5, "Ferocity", "Wildheit" }, { 2, 3, "Furor", "Ingrimm" },
          { 2, 2, "Feral Swiftness", "Schnelligkeit der Wildnis" }, { 2, 3, "Shredding Attacks", "Schreddernde Angriffe" },
          { 2, 2, "Savage Fury", "Ungezähmte Wut" }, { 2, 1, "Feral Charge", "Wilde Attacke" },
          { 2, 2, "Sharpened Claws", "Geschärfte Klauen" }, { 2, 3, "Predatory Strikes", "Raubtierschläge" },
          { 2, 1, "Predatory Discipline", "Disziplin des Raubtiers" }, { 2, 2, "Blood Frenzy", "Blutraserei" },
          { 2, 1, "Leader of the Pack", "Rudelführer" }, { 2, 2, "Natural Instinct", "Instinkt der Natur" },
          { 2, 4, "Rend and Tear", "Beißen und Reißen" }, { 2, 1, "Shifting Power", "Machtverschiebung" },
      }, DRUID_RESTO_DIP) },
    { key = "balance-raid", name = { de = "Gleichgewicht – Raid", en = "Balance – raid" }, tree = 1, split = "41/0/10",
      grade = "single", purpose = { "raid", "dungeon" }, read = R,
      sources = { S("IV", "balance-druid-ranged-dps-pve-spec-builds-talents", "2026-11-04", "exact"),
          S("KL", "build-druide-equilibre-wow-forever/", "2026-11-09", "core", "textdate"),
          S("RB", "druid/", "2026-11-08", "derived") },
      talents = {
          { 1, 5, "Improved Wrath", "Verb. Zorn" }, { 1, 5, "Genesis", "Genesis" }, { 1, 3, "Moonglow", "Mondschein" },
          { 1, 2, "Improved Moonfire", "Verb. Mondfeuer" }, { 1, 2, "Nature's Majesty", "Erhabenheit der Natur" },
          { 1, 2, "Nature's Reach", "Reichweite der Natur" }, { 1, 1, "Nature's Splendor", "Pracht der Natur" },
          { 1, 1, "Insect Swarm", "Insektenschwarm" }, { 1, 5, "Vengeance", "Rache" },
          { 1, 5, "Improved Starfire", "Verb. Sternenfeuer" }, { 1, 1, "Nature's Grace", "Anmut der Natur" },
          { 1, 3, "Eclipse", "Finsternis" }, { 1, 5, "Moonfury", "Mondfuror" },
          { 1, 1, "Moonkin Form", "Mondkingestalt", "Moonkingestalt" },
          { 3, 5, "Nature's Focus", "Naturfokus" }, { 3, 5, "Naturalist", "Naturalist" },
      } },
    { key = "resto-healer", name = { de = "Wiederherstellung – Heiler", en = "Restoration – healer" }, tree = 3,
      split = "11/0/40", grade = "checked", purpose = { "healer" }, read = R,
      sources = { S("MOB", "classes/restoration-druid-guide", "2026-11-04", "exact"),
          S("RB", "druid/", "2026-11-08", "core") },
      talents = {
          { 1, 5, "Genesis", "Genesis" }, { 1, 1, "Moonglow", "Mondschein" }, { 1, 2, "Improved Moonfire", "Verb. Mondfeuer" },
          { 1, 2, "Nature's Majesty", "Erhabenheit der Natur" }, { 1, 1, "Nature's Splendor", "Pracht der Natur" },
          { 3, 5, "Nature's Focus", "Naturfokus" }, { 3, 5, "Heart of the Wild", "Herz der Wildnis" },
          { 3, 5, "Naturalist", "Naturalist" }, { 3, 3, "Reflection", "Reflexion" },
          { 3, 5, "Gift of Nature", "Geschenk der Natur" }, { 3, 1, "Bloom", "Blüte" },
          { 3, 3, "Improved Rejuvenation", "Verb. Verjüngung" }, { 3, 1, "Swiftmend", "Rasche Heilung" },
          { 3, 1, "Nature's Swiftness", "Schnelligkeit der Natur" }, { 3, 3, "Living Spirit", "Geist des Lebens" },
          { 3, 2, "Improved Tranquility", "Verb. Gelassenheit" }, { 3, 5, "Improved Regrowth", "Verb. Nachwachsen" },
          { 3, 1, "Wild Growth", "Wildwuchs" },
      } },
}
