local _, ns = ...

--[[
    Sprachunabhängige Kennung der Talente der Vorauswahl (Presets.lua): Zauber-ID der Talent-Definition und Lage im
    Baum. Nur Daten – gelesen von Templates.lua (Templates.PresetID, Templates.ResolvePreset).

    Warum: Die Vorauswahl nennt Talente mit ihrem englischen Namen. Über Namen lässt sich nur zuordnen, wo der Client
    denselben Namen zeigt – im deutschen Client scheiterte das beim Hexenmeister fast ganz („1 von 17 Talenten
    zugeordnet“, Spieltest 14.11.2026). Zauber-ID und Lage sind in jeder Sprache dieselben.

    Quelle (Leitlinie 10 und 11): ausschließlich der Client, selbst erhoben mit ezTalents Werkzeug
    „Talente erheben“ (Einstellungen → ezTalent → Erweitert, oder /ezt erheben). Es liest je Talent der eigenen Klasse
      - den Talentbaum (Nummer der Gruppe, C_Traits.GetGroupDisplayInfoByTreeID),
      - Zeile und Spalte (aus C_Traits.GetNodeInfo(…).posX/posY gezählt, Traits.Layout),
      - den Höchstrang (maxRanks) und
      - die Zauber-ID (C_Traits.GetEntryInfo(…).definitionID → C_Traits.GetDefinitionInfo(…).spellID),
      - Namen und Text des ersten Rangs, wie der Client sie zeigt (nur zum Erkennen, nicht für diese Datei)
    und nennt dazu in Zeilen „fehlt“ die Talente der Vorauswahl, die der erhebende Client nicht zuordnet (seit Fassung 2
    der Erhebung, Spieltest 15.11.2026). Alles als ein Text zum Kopieren. Keine IDs aus fremden Addons, Datenbank-Seiten
    oder Talentrechnern.

    Erhoben im deutschen Client (Hexenmeister, Paladin: die Vorauswahl nennt fast nur englische Namen) fehlt an vielen
    Zeilen der englische Name. Dann nennt survey2ids je Zeile „fehlt“ die Knoten desselben Baums mit passendem
    Höchstrang; den englischen Namen trägt der Entwickler in Feld 7 der passenden Zeile ein – entschieden an Name, Text,
    Lage und Höchstrang aus dem Client – und wandelt noch einmal um. Am Eintrag steht dann „von Hand: <Grund>“ (Name,
    Text, Lage, Ausschluss), damit klar ist, dass die Kennung aus dem Client kommt und nur die Paarung von Hand.

    Form:
      ns.PRESET_IDS[KLASSE]["<Baum>:<englischer Name wie in Presets.lua>"] = Zauber-ID
                                                                         | { spell = Zauber-ID | { IDs … }, row = Zeile, col = Spalte }
    Zugeordnet wird in dieser Reihenfolge: Zauber-ID → Lage (Baum, Zeile, Spalte) → Name (wie bisher, sprachabhängig).
    Ein Talent ohne Eintrag hier geht also weiter über den Namen.

    Stand je Klasse (Datum der Erhebung, Sprache und Build des Clients dazuschreiben):
      Quelle aller neun Klassen: Erhebung im Client, Build 70938, deDE, 15.11.2026 (Client 1.60.1.70938, „Talente
      erheben“ Fassung 2, je Klasse ein Lauf des Nutzers). Krieger, Paladin, Jäger, Schurke, Priester, Schamane, Magier,
      Hexenmeister, Druide – mehr Klassen kennt die Vorauswahl nicht (Presets.lua). Jedes Talent jeder Vorauswahl dieser
      Klassen hat hier eine Kennung (Prüfung in Tests/kennungen.lua). Zeile und Spalte sind mit Traits.Grid gezählt
      (survey2ids zählt die Zahlen der Fassung 2 neu: der Hexenmeister hatte dort Zeilen wie 62 und 121, der Jäger im
      Baum Überleben 61 bis 361). Die Paarung „englischer Name ↔ Zauber-ID“: wo ezTalent das Talent im deutschen Client
      schon über den Namen fand, aus der Erhebung selbst; sonst von Hand, Grund am Eintrag (Hexenmeister 36, Paladin 45,
      Schurke 2, Krieger 1, Magier 1, Druide 2 – Liste und Befunde in docs/roadmap/ezTalent.md). Aus einem neuen
      Erhebungstext macht ezTalent/Tests/survey2ids.lua die Zeilen für diese Datei (luajit Tests/survey2ids.lua <Datei>).
]]

ns.PRESET_IDS = ns.PRESET_IDS or {}

-- WARRIOR – 44 Talente; davon 1 von Hand gepaart (Grund am Eintrag), die übrigen hat ezTalent beim Erheben über den Namen zugeordnet
ns.PRESET_IDS.WARRIOR = {
    ["1:Improved Heroic Strike"] = { spell = 12282, row = 1, col = 1 },    -- Verbesserter heldenhafter Stoß
    ["1:Deflection"] = { spell = 16462, row = 1, col = 2 },    -- Abwehr
    ["1:Improved Rend"] = { spell = 12286, row = 1, col = 3 },    -- Verbessertes Verwunden
    ["1:Improved Charge"] = { spell = 12285, row = 2, col = 1 },    -- Verbesserter Sturmangriff
    ["1:Improved Tactical Mastery"] = { spell = 12295, row = 2, col = 2 },    -- Verbesserter Taktiker
    ["1:Improved Overpower"] = { spell = 12290, row = 2, col = 4 },    -- Verbessertes Überwältigen
    ["1:Anger Management"] = { spell = 12296, row = 3, col = 2 },    -- Aggressionskontrolle
    ["1:Deep Wounds"] = { spell = 12834, row = 3, col = 3 },    -- Tiefe Wunden
    ["1:Spearing Strike"] = { spell = 1310222, row = 4, col = 1 },    -- Aufspießender Stoß
    ["1:Two-Handed Weapon Specialization"] = { spell = 12163, row = 4, col = 2 },    -- Zweihandwaffen-Spezialisierung
    ["1:Impale"] = { spell = 16493, row = 4, col = 3 },    -- Durchbohren
    ["1:Bloodthrill"] = { spell = 1289682, row = 5, col = 1 },    -- Rausch des Blutes
    ["1:Sweeping Strikes"] = { spell = 12292, row = 5, col = 2 },    -- Weitreichende Stöße
    ["1:Weaponmaster"] = { spell = 1290261, row = 5, col = 3 },    -- Waffenmeister
    ["1:Improved Slam"] = { spell = 12862, row = 6, col = 1 },    -- Verbessertes Zerschmettern
    ["1:Mortal Strike"] = { spell = 12294, row = 7, col = 2 },    -- Tödlicher Stoß
    ["2:Cruelty"] = { spell = 12320, row = 1, col = 3 },    -- Grausamkeit
    ["2:Lingering Rage"] = { spell = 1323964, row = 2, col = 2 },    -- Schwelende Wut
    ["2:Unbridled Wrath"] = { spell = 12322, row = 2, col = 3 },    -- Entfesselter Zorn
    ["2:Furious Precision"] = { spell = 1323963, row = 3, col = 1 },    -- Zornige Präzision
    ["2:Piercing Howl"] = { spell = 12323, row = 3, col = 2 },    -- Durchdringendes Heulen
    ["2:Enrage"] = { spell = 12317, row = 3, col = 4 },    -- Wutanfall
    ["2:Dual Wield Specialization"] = { spell = 23584, row = 4, col = 1 },    -- Beidhändigkeits-Spezialisierung
    ["2:Reckless Swings"] = { spell = 1329555, row = 4, col = 2 },    -- Tollkühne Schwünge · von Hand: Name und Text; Vorauswahl nannte „Ungezügelte Hiebe“
    ["2:Improved Execute"] = { spell = 20502, row = 4, col = 4 },    -- Verbessertes Hinrichten
    ["2:Improved Berserker Rage"] = { spell = 20500, row = 5, col = 1 },    -- Verbesserte Berserkerwut
    ["2:Death Wish"] = { spell = 12328, row = 5, col = 2 },    -- Todeswunsch
    ["2:Improved Whirlwind"] = { spell = 1310315, row = 6, col = 1 },    -- Verbesserter Wirbelwind
    ["2:Flurry"] = { spell = 12319, row = 6, col = 3 },    -- Schlaghagel
    ["2:Bloodthirst"] = { spell = 23881, row = 7, col = 2 },    -- Blutdurst
    ["3:Improved Bloodrage"] = { spell = 12301, row = 1, col = 1 },    -- Verbesserter Blutrausch
    ["3:Shield Specialization"] = { spell = 12298, row = 1, col = 2 },    -- Schild-Spezialisierung
    ["3:Anticipation"] = { spell = 12297, row = 2, col = 1 },    -- Vorahnung
    ["3:Improved Revenge"] = { spell = 12797, row = 2, col = 3 },    -- Verbesserte Rache
    ["3:Improved Thunder Clap"] = { spell = 12287, row = 2, col = 4 },    -- Verbesserter Donnerknall
    ["3:Last Stand"] = { spell = 12975, row = 3, col = 1 },    -- Letztes Gefecht
    ["3:Master of Defense"] = { spell = 1310316, row = 3, col = 2 },    -- Meister der Verteidigung
    ["3:Defiance"] = { spell = 12792, row = 3, col = 4 },    -- Trotz
    ["3:Vanguard"] = { spell = 1310317, row = 4, col = 2 },    -- Frontkämpfer
    ["3:Improved Shield Wall"] = { spell = 12312, row = 5, col = 1 },    -- Verbesserter Schildwall
    ["3:Concussion Blow"] = { spell = 12809, row = 5, col = 2 },    -- Erschütternder Schlag
    ["3:Focused Rage"] = { spell = 29787, row = 5, col = 3 },    -- Fokussierte Wut
    ["3:Bastion"] = { spell = 16538, row = 6, col = 3 },    -- Bastion
    ["3:Shield Slam"] = { spell = 23922, row = 7, col = 2 },    -- Schildschlag
}

-- PALADIN – 46 Talente; davon 45 von Hand gepaart (Grund am Eintrag), die übrigen hat ezTalent beim Erheben über den Namen zugeordnet
ns.PRESET_IDS.PALADIN = {
    ["1:Spiritual Focus"] = { spell = 20205, row = 1, col = 2 },    -- Spiritueller Fokus · von Hand: Name
    ["1:Divine Strength"] = { spell = 20262, row = 1, col = 3 },    -- Göttliche Stärke · von Hand: Name
    ["1:Healing Light"] = { spell = 20237, row = 2, col = 1 },    -- Heilendes Licht · von Hand: Name
    ["1:Reverence"] = { spell = 1310899, row = 2, col = 2 },    -- Andacht · von Hand: Name (Andacht) und Ausschluss
    ["1:Improved Seals"] = { spell = 20224, row = 2, col = 3 },    -- Verbesserte Siegel · von Hand: Name
    ["1:Purifying Power"] = { spell = 429144, row = 2, col = 4 },    -- Reinigende Macht · von Hand: Name
    ["1:Divine Favor"] = { spell = 20216, row = 3, col = 1 },    -- Göttliche Gunst · von Hand: Name und Text
    ["1:Illumination"] = { spell = 20210, row = 3, col = 2 },    -- Illumination
    ["1:Holy Conduit"] = { spell = 1237268, row = 3, col = 3 },    -- Heiliges Medium · von Hand: Name (Medium = Conduit) und Ausschluss
    ["1:Divine Precision"] = { spell = 1310904, row = 4, col = 1 },    -- Göttliche Präzision · von Hand: Name und Text
    ["1:Infusion of Light"] = { spell = 426065, row = 4, col = 2 },    -- Lichtinfusion · von Hand: Name
    ["1:Oath of Light"] = { spell = 1328548, row = 4, col = 3 },    -- Eid des Lichts · von Hand: Name und Text
    ["1:Holy Shock"] = { spell = 1311606, row = 5, col = 2 },    -- Heiliger Schock · von Hand: Name
    ["1:Boundless Light"] = { spell = 1328550, row = 5, col = 3 },    -- Grenzenloses Licht · von Hand: Name und Text
    ["1:Holy Power"] = { spell = 5923, row = 6, col = 3 },    -- Heilige Kraft · von Hand: Name und Text
    ["1:Light's Vigil"] = { spell = 1310911, row = 7, col = 2 },    -- Lichtwacht · von Hand: Name und Text
    ["2:Divine Intellect"] = { spell = 20257, row = 1, col = 2 },    -- Göttliche Weisheit · von Hand: Ausschluss (letztes Talent mit 5 Rängen)
    ["2:Redoubt"] = { spell = 20127, row = 1, col = 3 },    -- Verschanzen · von Hand: Name
    ["2:Precision"] = { spell = 20189, row = 2, col = 1 },    -- Präzision · von Hand: Name
    ["2:Guardian's Favor"] = { spell = 20174, row = 2, col = 2 },    -- Gunst des Hüters · von Hand: Name
    ["2:Sacred Duty"] = { spell = 1224697, row = 2, col = 4 },    -- Heilige Pflicht · von Hand: Name und Text
    ["2:Templar's Bulwark"] = { spell = 1311015, row = 3, col = 1 },    -- Bollwerk des Templers · von Hand: Name
    ["2:Shield Specialization"] = { spell = 20150, row = 3, col = 3 },    -- Schild-Spezialisierung · von Hand: Name
    ["2:Toughness"] = { spell = 20143, row = 3, col = 4 },    -- Zähigkeit · von Hand: Name
    ["2:Swift Judgement"] = { spell = 1310994, row = 4, col = 1 },    -- Schnelles Richturteil · von Hand: Name und Text
    ["2:Improved Righteous Fury"] = { spell = 20468, row = 4, col = 2 },    -- Verbesserter Zorn der Gerechtigkeit · von Hand: Name
    ["2:Anticipation"] = { spell = 20096, row = 4, col = 3 },    -- Vorahnung · von Hand: Name
    ["2:Holy Shield"] = { spell = 20925, row = 5, col = 2 },    -- Heiliger Schild · von Hand: Name und Text
    ["2:Reckoning"] = { spell = 20177, row = 5, col = 3 },    -- Abrechnung · von Hand: Name und Text
    ["2:Iron Creed"] = { spell = 1311034, row = 6, col = 3 },    -- Eiserner Glaube · von Hand: Name
    ["2:Shieldsworn"] = { spell = 1328544, row = 7, col = 2 },    -- Schildgeschworen · von Hand: Name und Text
    ["3:Deflection"] = { spell = 20060, row = 1, col = 2 },    -- Abwehr · von Hand: Name
    ["3:Benediction"] = { spell = 20101, row = 1, col = 3 },    -- Segnung · von Hand: Name
    ["3:Improved Judgement"] = { spell = 25956, row = 2, col = 1 },    -- Verbessertes Richturteil · von Hand: Name
    ["3:Conviction"] = { spell = 20117, row = 2, col = 2 },    -- Überzeugung · von Hand: Name und Text
    ["3:Sanctified Judgement"] = { spell = 1311074, row = 2, col = 3 },    -- Gesegnetes Richturteil · von Hand: Name (gesegnet = sanctified) und Ausschluss
    ["3:Vindication"] = { spell = 9452, row = 3, col = 1 },    -- Rechtschaffene Schwächung · von Hand: Text (senkt die Angriffskraft des Angreifers) und Ausschluss
    ["3:Unyielding Faith"] = { spell = 9453, row = 3, col = 2 },    -- Unumstößlicher Glaube · von Hand: Name
    ["3:Seal of Command"] = { spell = 20375, row = 3, col = 3 },    -- Siegel des Befehls · von Hand: Name und Text
    ["3:Pursuit of Justice"] = { spell = 26022, row = 3, col = 4 },    -- Streben nach Gerechtigkeit · von Hand: Name
    ["3:Sacred Arbiter"] = { spell = 1311087, row = 4, col = 2 },    -- Heiliger Richter · von Hand: Name (Richter = Arbiter) und Ausschluss
    ["3:Two-Handed Weapon Specialization"] = { spell = 20111, row = 4, col = 4 },    -- Zweihandwaffen-Spezialisierung · von Hand: Name und Text
    ["3:Repentance"] = { spell = 20066, row = 5, col = 2 },    -- Buße · von Hand: Name
    ["3:Vengeance"] = { spell = 20049, row = 5, col = 3 },    -- Rache · von Hand: Name
    ["3:Champion of the Light"] = { spell = 1311084, row = 6, col = 3 },    -- Champion des Lichts · von Hand: Name und Text
    ["3:Unsealed Wrath"] = { spell = 1310735, row = 7, col = 2 },    -- Entfesselter Zorn · von Hand: Name und Text
}

-- HUNTER – 38 Talente; alle hat ezTalent beim Erheben über den Namen zugeordnet
ns.PRESET_IDS.HUNTER = {
    ["1:Deadly Aspects"] = { spell = 19552, row = 1, col = 2 },    -- Tödliche Aspekte
    ["1:Endurance Training"] = { spell = 19583, row = 1, col = 3 },    -- Belastbarkeit-Ausbildung
    ["1:Focused Fire"] = { spell = 1223755, row = 2, col = 1 },    -- Konzentriertes Feuer
    ["1:Improved Revive Pet"] = { spell = 24443, row = 2, col = 3 },    -- Verbessertes Tier wiederbeleben
    ["1:Pathfinding"] = { spell = 19559, row = 3, col = 1 },    -- Orientierung
    ["1:Bestial Swiftness"] = { spell = 19596, row = 3, col = 2 },    -- Erhöhte Tiergeschwindigkeit
    ["1:Unleashed Fury"] = { spell = 19616, row = 3, col = 3 },    -- Entfesselter Zorn
    ["1:Ferocity"] = { spell = 19598, row = 4, col = 3 },    -- Wildheit
    ["1:Summon Hawk"] = { spell = 1293241, row = 4, col = 4 },    -- Falke beschwören
    ["1:Intimidation"] = { spell = 19577, row = 5, col = 2 },    -- Einschüchterung
    ["1:Bestial Discipline"] = { spell = 19590, row = 5, col = 4 },    -- Wildtierdisziplin
    ["1:Frenzy"] = { spell = 19621, row = 6, col = 3 },    -- Raserei
    ["1:Bestial Wrath"] = { spell = 19574, row = 7, col = 2 },    -- Zorn des Wildtiers
    ["2:Hawk Eye"] = { spell = 19498, row = 1, col = 1 },    -- Falkenauge
    ["2:Lethal Attacks"] = { spell = 19426, row = 1, col = 3 },    -- Tödliche Angriffe
    ["2:Improved Stings"] = { spell = 1310661, row = 2, col = 1 },    -- Verbesserte Stiche und Bisse
    ["2:Efficiency"] = { spell = 19416, row = 2, col = 2 },    -- Effizienz
    ["2:Careful Aim"] = { spell = 1223984, row = 2, col = 3 },    -- Sorgfältiges Zielen
    ["2:Rapid Killing"] = { spell = 415405, row = 3, col = 1 },    -- Schneller Tod
    ["2:Lone Wolf"] = { spell = 415370, row = 3, col = 4 },    -- Einsamer Wolf
    ["2:Trueshot Aura"] = { spell = 1299346, row = 4, col = 2 },    -- Aura des Volltreffers
    ["2:Mortal Shots"] = { spell = 19485, row = 4, col = 3 },    -- Todbringende Schüsse
    ["2:Rapid Recuperation"] = { spell = 1223987, row = 5, col = 1 },    -- Rasche Erholung
    ["2:Barrage"] = { spell = 19461, row = 5, col = 3 },    -- Sperrfeuer
    ["2:Ranged Weapon Specialization"] = { spell = 19507, row = 6, col = 3 },    -- Distanzwaffen-Spezialisierung
    ["2:Sniper Shot"] = { spell = 1310687, row = 7, col = 2 },    -- Heckenschützenschuss
    ["3:Improved Tracking"] = { spell = 24293, row = 1, col = 2 },    -- Verbessertes Fährtenlesen
    ["3:Deflection"] = { spell = 19295, row = 1, col = 3 },    -- Abwehr
    ["3:Savage Strikes"] = { spell = 19159, row = 2, col = 2 },    -- Wilde Schläge
    ["3:Clever Traps"] = { spell = 19239, row = 3, col = 1 },    -- Falleneffizienz
    ["3:Surefooted"] = { spell = 19290, row = 3, col = 2 },    -- Sicherer Stand
    ["3:Predator's Edge"] = { spell = 1310627, row = 4, col = 2 },    -- Vorteil des Raubtiers
    ["3:Resourcefulness"] = { spell = 440529, row = 5, col = 1 },    -- Einfallsreichtum
    ["3:Expose Prey"] = { spell = 1310532, row = 5, col = 2 },    -- Beute aufspüren
    ["3:Survivalist's Discipline"] = { spell = 1310496, row = 5, col = 3 },    -- Disziplin des Überlebenskünstlers
    ["3:Strider Kick"] = { spell = 1317257, row = 5, col = 4 },    -- Streichertritt
    ["3:Lightning Reflexes"] = { spell = 19168, row = 6, col = 3 },    -- Blitzartige Reflexe
    ["3:Lacerating Strikes"] = { spell = 1310533, row = 7, col = 2 },    -- Aufschlitzende Schläge
}

-- ROGUE – 45 Talente; davon 2 von Hand gepaart (Grund am Eintrag), die übrigen hat ezTalent beim Erheben über den Namen zugeordnet
ns.PRESET_IDS.ROGUE = {
    ["1:Remorseless Attacks"] = { spell = 14144, row = 1, col = 2 },    -- Gnadenlose Angriffe
    ["1:Malice"] = { spell = 14138, row = 1, col = 3 },    -- Tücke
    ["1:Ruthlessness"] = { spell = 14156, row = 2, col = 1 },    -- Skrupellosigkeit
    ["1:Improved Expose Armor"] = { spell = 14168, row = 2, col = 2 },    -- Verbessertes Rüstung schwächen
    ["1:Improved Slice and Dice"] = { spell = 14165, row = 2, col = 4 },    -- Verbessertes Zerhäckseln
    ["1:Blood Splatter"] = { spell = 1329256, row = 3, col = 2 },    -- Blutspritzer
    ["1:Lethality"] = { spell = 14128, row = 3, col = 3 },    -- Tödlichkeit
    ["1:Vile Poisons"] = { spell = 16513, row = 4, col = 1 },    -- Üble Gifte
    ["1:Cold Blood"] = { spell = 14177, row = 4, col = 2 },    -- Kaltblütigkeit
    ["1:Improved Poisons"] = { spell = 14113, row = 4, col = 3 },    -- Verbesserte Gifte
    ["1:Relentless Strikes"] = { spell = 14179, row = 5, col = 1 },    -- Unerbittliche Stöße
    ["1:Venom"] = { spell = 1329328, row = 5, col = 2 },    -- Toxin
    ["1:Seal Fate"] = { spell = 14186, row = 6, col = 3 },    -- Schicksal besiegeln
    ["1:Mutilate"] = { spell = 399956, row = 7, col = 2 },    -- Verstümmeln
    ["2:Coup de Grace"] = { spell = 14162, row = 1, col = 1 },    -- Gnadenstoß
    ["2:Efficient Strikes"] = { spell = 13732, row = 1, col = 2 },    -- Effiziente Schläge · von Hand: Name und Text; Vorauswahl nannte „Effiziente Stöße“
    ["2:Lightning Reflexes"] = { spell = 13712, row = 1, col = 3 },    -- Blitzartige Reflexe
    ["2:Puncturing Wounds"] = { spell = 1224716, row = 2, col = 1 },    -- Durchbohrende Wunden
    ["2:Deflection"] = { spell = 13713, row = 2, col = 2 },    -- Abwehr
    ["2:Precision"] = { spell = 13705, row = 2, col = 3 },    -- Präzision
    ["2:Improved Sprint"] = { spell = 13743, row = 2, col = 4 },    -- Verbessertes Sprinten
    ["2:Endurance"] = { spell = 13742, row = 3, col = 1 },    -- Durchhaltevermögen
    ["2:Riposte"] = { spell = 14251, row = 3, col = 2 },    -- Riposte
    ["2:Composure"] = { spell = 1329265, row = 3, col = 4 },    -- Gelassenheit
    ["2:Flawless Execution"] = { spell = 1310711, row = 4, col = 2 },    -- Perfekte Ausführung
    ["2:Weapon Expertise"] = { spell = 30919, row = 4, col = 3 },    -- Waffenexperte
    ["2:Aggression"] = { spell = 18427, row = 4, col = 4 },    -- Aggression
    ["2:Dual Wield Specialization"] = { spell = 13715, row = 5, col = 1 },    -- Beidhändigkeitsspezialisierung
    ["2:Blade Flurry"] = { spell = 13877, row = 5, col = 2 },    -- Klingenwirbel
    ["2:Hack and Slash"] = { spell = 13960, row = 5, col = 3 },    -- Niedermetzeln
    ["2:Flash of Steel"] = { spell = 1329284, row = 6, col = 3 },    -- Blitzender Stahl · von Hand: Name und Text; Vorauswahl nannte „Aufblitzender Stahl“
    ["2:Adrenaline Rush"] = { spell = 13750, row = 7, col = 2 },    -- Adrenalinrausch
    ["3:Setup"] = { spell = 13983, row = 1, col = 1 },    -- Reinlegen
    ["3:Opportunity"] = { spell = 14057, row = 1, col = 3 },    -- Günstige Gelegenheit
    ["3:Dirty Deeds"] = { spell = 14082, row = 2, col = 1 },    -- Gemeinheiten
    ["3:Camouflage"] = { spell = 13975, row = 2, col = 2 },    -- Camouflage
    ["3:Improved Ambush"] = { spell = 14079, row = 2, col = 3 },    -- Verbesserter Hinterhalt
    ["3:Initiative"] = { spell = 13976, row = 3, col = 1 },    -- Initiative
    ["3:Premeditation"] = { spell = 14183, row = 3, col = 2 },    -- Konzentration
    ["3:Serrated Blades"] = { spell = 14171, row = 3, col = 3 },    -- Gezahnte Klingen
    ["3:Ghostly Strike"] = { spell = 14278, row = 4, col = 2 },    -- Geisterhafter Stoß
    ["3:Preparation"] = { spell = 14185, row = 5, col = 2 },    -- Vorbereitung
    ["3:Hemorrhage"] = { spell = 16511, row = 5, col = 3 },    -- Blutsturz
    ["3:Boot Knife"] = { spell = 1329286, row = 6, col = 3 },    -- Stiefelmesser
    ["3:Death Mark"] = { spell = 1316709, row = 7, col = 2 },    -- Todesmal
}

-- PRIEST – 42 Talente; alle hat ezTalent beim Erheben über den Namen zugeordnet
ns.PRESET_IDS.PRIEST = {
    ["1:Power in Light"] = { spell = 1309969, row = 1, col = 1 },    -- Macht im Licht
    ["1:Wand Specialization"] = { spell = 14524, row = 1, col = 2 },    -- Zauberstab-Spezialisierung
    ["1:Twin Disciplines"] = { spell = 1225132, row = 1, col = 3 },    -- Zwillingsdisziplinen
    ["1:Silent Resolve"] = { spell = 14523, row = 2, col = 1 },    -- Schweigsame Entschlossenheit
    ["1:Mental Strength"] = { spell = 18551, row = 2, col = 3 },    -- Mentale Stärke
    ["1:Mental Agility"] = { spell = 14520, row = 3, col = 1 },    -- Mentale Beweglichkeit
    ["1:Inner Focus"] = { spell = 14751, row = 3, col = 2 },    -- Innerer Fokus
    ["1:Improved Power Word: Shield"] = { spell = 14748, row = 3, col = 3 },    -- Verbessertes Machtwort: Schild
    ["1:Meditation"] = { spell = 14521, row = 3, col = 4 },    -- Meditation
    ["1:Soul Warding"] = { spell = 402000, row = 4, col = 3 },    -- Seelenwehr
    ["1:Penance"] = { spell = 402174, row = 5, col = 2 },    -- Sühne
    ["1:Renewed Hope"] = { spell = 425280, row = 5, col = 3 },    -- Erneuerte Hoffnung
    ["1:Divine Aegis"] = { spell = 431622, row = 6, col = 3 },    -- Göttliche Aegis
    ["1:Power Infusion"] = { spell = 10060, row = 7, col = 2 },    -- Seele der Macht
    ["2:Twilight Focus"] = { spell = 14913, row = 1, col = 1 },    -- Zwielichtfokus
    ["2:Improved Renew"] = { spell = 14908, row = 1, col = 2 },    -- Verbesserte Erneuerung
    ["2:Holy Specialization"] = { spell = 14889, row = 1, col = 3 },    -- Heiligspezialisierung
    ["2:Divine Fury"] = { spell = 18530, row = 2, col = 3 },    -- Göttlicher Furor
    ["2:Holy Nova"] = { spell = 15237, row = 3, col = 1 },    -- Heilige Nova
    ["2:Inspiration"] = { spell = 14892, row = 3, col = 4 },    -- Inspiration
    ["2:Holy Reach"] = { spell = 27789, row = 4, col = 1 },    -- Heilige Reichweite
    ["2:Improved Healing"] = { spell = 14912, row = 4, col = 2 },    -- Verbesserte Heilung
    ["2:Searing Light"] = { spell = 14909, row = 4, col = 3 },    -- Sengendes Licht
    ["2:Litany of Light"] = { spell = 1317006, row = 5, col = 1 },    -- Litanei des Lichts
    ["2:Spirit of Redemption"] = { spell = 20711, row = 5, col = 2 },    -- Geist der Erlösung
    ["2:Spiritual Guidance"] = { spell = 14901, row = 5, col = 3 },    -- Geistige Führung
    ["2:Spiritual Healing"] = { spell = 14898, row = 6, col = 3 },    -- Spirituelle Heilung
    ["2:Prayer of Mending"] = { spell = 401859, row = 7, col = 2 },    -- Gebet der Besserung
    ["3:Shadow Focus"] = { spell = 15260, row = 1, col = 1 },    -- Schattenfokus
    ["3:Spirit Tap"] = { spell = 15270, row = 1, col = 3 },    -- Willensentzug
    ["3:Improved Mind Blast"] = { spell = 15273, row = 2, col = 1 },    -- Verbesserter Gedankenschlag
    ["3:Improved Shadow Word: Pain"] = { spell = 15275, row = 2, col = 3 },    -- Verbessertes Schattenwort: Schmerz
    ["3:Shadow Reach"] = { spell = 17322, row = 2, col = 4 },    -- Schattenreichweite
    ["3:Mind Flay"] = { spell = 15407, row = 3, col = 3 },    -- Gedankenschinden
    ["3:Improved Mind Flay"] = { spell = 1225139, row = 3, col = 4 },    -- Verbessertes Gedankenschinden
    ["3:Dark Inspiration"] = { spell = 1326159, row = 4, col = 1 },    -- Dunkle Inspiration
    ["3:Vampiric Embrace"] = { spell = 15286, row = 4, col = 2 },    -- Vampirumarmung
    ["3:Shadow Weaving"] = { spell = 15257, row = 4, col = 3 },    -- Schattenwirken
    ["3:Silence"] = { spell = 15487, row = 5, col = 1 },    -- Stille
    ["3:Devouring Contagion"] = { spell = 1309950, row = 5, col = 3 },    -- Verschlingende Ansteckung
    ["3:Darkness"] = { spell = 15259, row = 6, col = 3 },    -- Dunkelheit
    ["3:Shadowform"] = { spell = 15473, row = 7, col = 2 },    -- Schattengestalt
}

-- SHAMAN – 41 Talente; alle hat ezTalent beim Erheben über den Namen zugeordnet
ns.PRESET_IDS.SHAMAN = {
    ["1:Convection"] = { spell = 16039, row = 1, col = 2 },    -- Konvektion
    ["1:Concussion"] = { spell = 16035, row = 1, col = 3 },    -- Erschütterung
    ["1:Elemental Devastation"] = { spell = 30160, row = 2, col = 1 },    -- Elementarverwüstung
    ["1:Reverberation"] = { spell = 16040, row = 2, col = 2 },    -- Nachklingen
    ["1:Elemental Alacrity"] = { spell = 16578, row = 2, col = 3 },    -- Elementare Geschwindigkeit
    ["1:Call of Flame"] = { spell = 16038, row = 2, col = 4 },    -- Ruf der Flamme
    ["1:Elemental Focus"] = { spell = 16164, row = 3, col = 1 },    -- Elementarfokus
    ["1:Trial by Fire"] = { spell = 16086, row = 4, col = 1 },    -- Feuerprobe
    ["1:Eye of the Storm"] = { spell = 29062, row = 4, col = 2 },    -- Auge des Sturms
    ["1:Earthbound"] = { spell = 1222988, row = 4, col = 4 },    -- Erdgebunden
    ["1:Call of Thunder"] = { spell = 16120, row = 5, col = 2 },    -- Ruf des Donners
    ["1:Lightning Overload"] = { spell = 408438, row = 5, col = 3 },    -- Blitzschlag-Überladung
    ["1:Elemental Fury"] = { spell = 16089, row = 6, col = 3 },    -- Elementarfuror
    ["1:Lightning Mastery"] = { spell = 16166, row = 7, col = 2 },    -- Blitzbeherrschung
    ["2:Thundering Strikes"] = { spell = 16255, row = 1, col = 2 },    -- Donnernde Stöße
    ["2:Ancestral Knowledge"] = { spell = 17485, row = 1, col = 3 },    -- Wissen der Ahnen
    ["2:Mental Dexterity"] = { spell = 415140, row = 2, col = 2 },    -- Geistige Gewandtheit
    ["2:Elemental Weapons"] = { spell = 16266, row = 3, col = 1 },    -- Elementarwaffen
    ["2:Shamanistic Focus"] = { spell = 1223030, row = 3, col = 3 },    -- Schamanistischer Fokus
    ["2:Flurry"] = { spell = 16256, row = 4, col = 2 },    -- Schlaghagel
    ["2:Stormstrike"] = { spell = 17364, row = 4, col = 3 },    -- Sturmschlag
    ["2:Improved Ghost Wolf"] = { spell = 16262, row = 4, col = 4 },    -- Verbesserter Geisterwolf
    ["2:Spirit Weapons"] = { spell = 16268, row = 5, col = 1 },    -- Waffen der Geister
    ["2:Mental Quickness"] = { spell = 30812, row = 5, col = 2 },    -- Geistige Schnelligkeit
    ["2:Improved Stormstrike"] = { spell = 1223031, row = 5, col = 3 },    -- Verbesserter Sturmschlag
    ["2:Maelstrom Weapon"] = { spell = 408498, row = 6, col = 3 },    -- Waffe des Mahlstroms
    ["2:Rage of the Farseer"] = { spell = 425336, row = 7, col = 2 },    -- Zorn des Scharfsehers
    ["3:Improved Healing Wave"] = { spell = 16182, row = 1, col = 2 },    -- Verbesserte Welle der Heilung
    ["3:Tidal Focus"] = { spell = 16179, row = 1, col = 3 },    -- Gezeitenfokus
    ["3:Mindfulness"] = { spell = 1223033, row = 2, col = 1 },    -- Achtsamkeit
    ["3:Totemic Focus"] = { spell = 16173, row = 2, col = 3 },    -- Totemfokus
    ["3:Ancestral Healing"] = { spell = 16176, row = 3, col = 1 },    -- Heilung der Ahnen
    ["3:Healing Focus"] = { spell = 16181, row = 3, col = 2 },    -- Heilfokus
    ["3:Water Shield"] = { spell = 408510, row = 3, col = 3 },    -- Wasserschild
    ["3:Tidal Mastery"] = { spell = 16194, row = 4, col = 1 },    -- Gezeitenbeherrschung
    ["3:Restorative Totems"] = { spell = 16187, row = 4, col = 2 },    -- Regenerationstotems
    ["3:Mana Tide Totem"] = { spell = 16190, row = 4, col = 3 },    -- Totem der Manaflut
    ["3:Healing Way"] = { spell = 29206, row = 5, col = 2 },    -- Pfad der Heilung
    ["3:Nature's Swiftness"] = { spell = 16188, row = 5, col = 3 },    -- Schnelligkeit der Natur
    ["3:Purification"] = { spell = 16178, row = 6, col = 3 },    -- Läuterung
    ["3:Riptide"] = { spell = 408521, row = 7, col = 2 },    -- Springflut
}

-- MAGE – 45 Talente; davon 1 von Hand gepaart (Grund am Eintrag), die übrigen hat ezTalent beim Erheben über den Namen zugeordnet
ns.PRESET_IDS.MAGE = {
    ["1:Wand Specialization"] = { spell = 6057, row = 1, col = 1 },    -- Zauberstab-Spezialisierung
    ["1:Improved Channeling"] = { spell = 11237, row = 1, col = 2 },    -- Verbesserte Kanalisierung
    ["1:Arcane Resilience"] = { spell = 28574, row = 1, col = 3 },    -- Arkane Widerstandsfähigkeit
    ["1:Arcane Subtlety"] = { spell = 11210, row = 2, col = 1 },    -- Arkanes Feingefühl
    ["1:Magic Absorption"] = { spell = 29441, row = 2, col = 2 },    -- Magische Vereinnahmung
    ["1:Arcane Concentration"] = { spell = 11213, row = 2, col = 3 },    -- Arkane Konzentration
    ["1:Missile Barrage"] = { spell = 400588, row = 2, col = 4 },    -- Geschosssalve
    ["1:Arcane Geometry"] = { spell = 11247, row = 3, col = 1 },    -- Arkane Geometrie
    ["1:Arcane Impact"] = { spell = 11242, row = 3, col = 2 },    -- Arkaner Einschlag
    ["1:Arcane Blast"] = { spell = 400574, row = 3, col = 4 },    -- Arkanschlag
    ["1:Arcane Meditation"] = { spell = 18462, row = 4, col = 3 },    -- Arkane Meditation
    ["1:Arcane Wrath"] = { spell = 1326079, row = 4, col = 4 },    -- Arkaner Zorn
    ["1:Presence of Mind"] = { spell = 12043, row = 5, col = 2 },    -- Geistesgegenwart
    ["1:Arcane Mind"] = { spell = 11232, row = 5, col = 3 },    -- Arkaner Geist
    ["1:Arcane Instability"] = { spell = 15058, row = 6, col = 3 },    -- Arkane Instabilität
    ["1:Arcane Power"] = { spell = 12042, row = 7, col = 2 },    -- Arkane Macht
    ["2:Incineration"] = { spell = 18459, row = 1, col = 2 },    -- Verbrennung
    ["2:Accelerant"] = { spell = 11069, row = 1, col = 3 },    -- Beschleuniger
    ["2:Ignite"] = { spell = 11119, row = 2, col = 1 },    -- Entzünden
    ["2:Pyroblast"] = { spell = 11366, row = 3, col = 3 },    -- Pyroschlag
    ["2:Improved Fire Blast"] = { spell = 11078, row = 3, col = 4 },    -- Verbesserter Feuerschlag
    ["2:Improved Scorch"] = { spell = 11095, row = 4, col = 1 },    -- Verbessertes Versengen
    ["2:Heating Up"] = { spell = 400624, row = 4, col = 3 },    -- Aufwärmen
    ["2:Master of Elements"] = { spell = 29074, row = 4, col = 4 },    -- Meister der Elemente
    ["2:Critical Mass"] = { spell = 11115, row = 5, col = 2 },    -- Kritische Masse
    ["2:Fire Power"] = { spell = 11124, row = 6, col = 3 },    -- Feuermacht
    ["2:Combustion"] = { spell = 11129, row = 7, col = 2 },    -- Verbrennung
    ["3:Frost Warding"] = { spell = 11189, row = 1, col = 1 },    -- Schutz des Frostes
    ["3:Improved Frostbolt"] = { spell = 11070, row = 1, col = 2 },    -- Verbesserter Frostblitz
    ["3:Precision"] = { spell = 29438, row = 1, col = 3 },    -- Präzision
    ["3:Ice Shards"] = { spell = 11207, row = 2, col = 1 },    -- Eissplitter
    ["3:Frostbite"] = { spell = 11071, row = 2, col = 2 },    -- Erfrierung
    ["3:Improved Frost Nova"] = { spell = 11165, row = 2, col = 3 },    -- Verbesserte Frostnova
    ["3:Permafrost"] = { spell = 11175, row = 2, col = 4 },    -- Dauerfrost · von Hand: Name (Dauerfrost = Permafrost) und Höchstrang
    ["3:Frost Channeling"] = { spell = 11160, row = 3, col = 1 },    -- Frost-Kanalisierung
    ["3:Improved Blizzard"] = { spell = 11185, row = 3, col = 2 },    -- Verbesserter Blizzard
    ["3:Ice Lance"] = { spell = 1312002, row = 3, col = 3 },    -- Eislanze
    ["3:Arctic Reach"] = { spell = 16757, row = 4, col = 1 },    -- Arktische Reichweite
    ["3:Ice Block"] = { spell = 11958, row = 4, col = 2 },    -- Eisblock
    ["3:Shatter"] = { spell = 11170, row = 4, col = 4 },    -- Zertrümmern
    ["3:Improved Cone of Cold"] = { spell = 11190, row = 5, col = 1 },    -- Verbesserter Kältekegel
    ["3:Cold Snap"] = { spell = 12472, row = 5, col = 2 },    -- Kälteeinbruch
    ["3:Fingers of Frost"] = { spell = 400647, row = 5, col = 3 },    -- Eisige Finger
    ["3:Winter's Chill"] = { spell = 11180, row = 6, col = 3 },    -- Winterkälte
    ["3:Ice Barrier"] = { spell = 11426, row = 7, col = 2 },    -- Eisbarriere
}

-- WARLOCK – 38 Talente; davon 36 von Hand gepaart (Grund am Eintrag), die übrigen hat ezTalent beim Erheben über den Namen zugeordnet
ns.PRESET_IDS.WARLOCK = {
    ["1:Improved Life Tap"] = { spell = 18182, row = 1, col = 1 },    -- Verbesserter Aderlass · von Hand: Name
    ["1:Suppression"] = { spell = 18174, row = 1, col = 2 },    -- Unterdrückung · von Hand: Name
    ["1:Improved Corruption"] = { spell = 17810, row = 1, col = 3 },    -- Verbesserte Verderbnis · von Hand: Name
    ["1:Improved Bane of Agony"] = { spell = 18827, row = 3, col = 1 },    -- Verbessertes Omen der Pein · von Hand: Name (Omen = Bane)
    ["1:Amplify Curse"] = { spell = 18288, row = 3, col = 3 },    -- Fluch verstärken · von Hand: Name
    ["1:Pandemic"] = { spell = 427712, row = 3, col = 4 },    -- Pandemie · von Hand: Name
    ["1:Malevolence"] = { spell = 1310949, row = 4, col = 1 },    -- Böswilligkeit · von Hand: Name
    ["1:Nightfall"] = { spell = 18094, row = 4, col = 2 },    -- Einbruch der Nacht · von Hand: Name
    ["1:Siphon Life"] = { spell = 18265, row = 5, col = 2 },    -- Lebensentzug · von Hand: Name und Text
    ["1:Soul Siphon"] = { spell = 17804, row = 5, col = 3 },    -- Seelenentzug · von Hand: Name und Text
    ["1:Shadow Mastery"] = { spell = 18271, row = 6, col = 3 },    -- Schattenbeherrschung · von Hand: Name
    ["1:Wrack"] = { spell = 1316697, row = 7, col = 2 },    -- Zermürben · von Hand: Name und Text
    ["2:Demonic Embrace"] = { spell = 18697, row = 1, col = 3 },    -- Dämonische Umarmung · von Hand: Name
    ["2:Unholy Power"] = { spell = 18769, row = 1, col = 4 },    -- Unheilige Macht · von Hand: Name
    ["2:Demonic Aegis"] = { spell = 1235316, row = 2, col = 1 },    -- Dämonische Ägide · von Hand: Name
    ["2:Fel Vitality"] = { spell = 18731, row = 2, col = 3 },    -- Teuflische Vitalität · von Hand: Name
    ["2:Demonic Energies"] = { spell = 1225214, row = 2, col = 4 },    -- Dämonische Energien · von Hand: Name
    ["2:Improved Sayaad"] = { spell = 18754, row = 3, col = 1 },    -- Verbesserte Sayaad · von Hand: Name
    ["2:Demonic Sacrifice"] = { spell = 18788, row = 3, col = 2 },    -- Dämonische Opferung
    ["2:Master Summoner"] = { spell = 18709, row = 3, col = 3 },    -- Meister der Beschwörung · von Hand: Name
    ["2:Decimation"] = { spell = 440870, row = 4, col = 1 },    -- Dezimierung · von Hand: Name
    ["2:Demonic Brand"] = { spell = 1293695, row = 4, col = 4 },    -- Dämonisches Brandmal · von Hand: Name
    ["2:Soul Link"] = { spell = 19028, row = 5, col = 2 },    -- Seelenverbindung · von Hand: Name
    ["2:Demonic Knowledge"] = { spell = 412732, row = 5, col = 3 },    -- Dämonisches Wissen · von Hand: Name
    ["2:Master Demonologist"] = { spell = 23785, row = 6, col = 3 },    -- Meister der Dämonologie · von Hand: Name
    ["2:Demonic Pact"] = { spell = 425464, row = 7, col = 2 },    -- Dämonischer Pakt
    ["3:Improved Shadow Bolt"] = { spell = 17793, row = 1, col = 2 },    -- Verbesserter Schattenblitz · von Hand: Name
    ["3:Bane"] = { spell = 17788, row = 1, col = 3 },    -- Dunkle Macht · von Hand, vorläufig: nur über Ausschluss (siehe Roadmap), Bestätigung über Spielprüfung 73
    ["3:Cataclysm"] = { spell = 17778, row = 2, col = 2 },    -- Katastrophe · von Hand: Name
    ["3:Aftermath"] = { spell = 18119, row = 2, col = 3 },    -- Nachwirkung · von Hand: Name
    ["3:Ruin"] = { spell = 17959, row = 3, col = 2 },    -- Verderben · von Hand, vorläufig: nur über Ausschluss (siehe Roadmap), Bestätigung über Spielprüfung 73
    ["3:Shadowburn"] = { spell = 17877, row = 3, col = 3 },    -- Schattenbrand · von Hand: Name
    ["3:Agonizing Flames"] = { spell = 17927, row = 4, col = 2 },    -- Peinigende Flammen · von Hand: Name (wörtlich)
    ["3:Conflagrate"] = { spell = 1293817, row = 4, col = 3 },    -- Feuersbrunst · von Hand: Name (Feuersbrunst = Conflagrate)
    ["3:Bane of Havoc"] = { spell = 1225228, row = 5, col = 2 },    -- Omen der Verwüstung · von Hand: Name und Text (Omen der Verwüstung = Bane of Havoc)
    ["3:Fire and Brimstone"] = { spell = 412751, row = 5, col = 3 },    -- Feuer und Schwefel · von Hand: Name
    ["3:Shadow and Flame"] = { spell = 426316, row = 6, col = 3 },    -- Schatten und Flamme · von Hand: Name
    ["3:Incinerate"] = { spell = 412758, row = 7, col = 2 },    -- Verbrennen · von Hand: Name (Verbrennen = Incinerate)
}

-- DRUID – 45 Talente; davon 2 von Hand gepaart (Grund am Eintrag), die übrigen hat ezTalent beim Erheben über den Namen zugeordnet
ns.PRESET_IDS.DRUID = {
    ["1:Improved Wrath"] = { spell = 16814, row = 1, col = 2 },    -- Verbesserter Zorn
    ["1:Genesis"] = { spell = 1223081, row = 1, col = 3 },    -- Genesis
    ["1:Moonglow"] = { spell = 16845, row = 2, col = 1 },    -- Mondschein
    ["1:Improved Moonfire"] = { spell = 16821, row = 2, col = 2 },    -- Verbessertes Mondfeuer
    ["1:Nature's Majesty"] = { spell = 1223082, row = 2, col = 3 },    -- Erhabenheit der Natur
    ["1:Nature's Reach"] = { spell = 16819, row = 2, col = 4 },    -- Reichweite der Natur
    ["1:Nature's Splendor"] = { spell = 1223083, row = 3, col = 3 },    -- Pracht der Natur
    ["1:Insect Swarm"] = { spell = 5570, row = 4, col = 1 },    -- Insektenschwarm
    ["1:Vengeance"] = { spell = 16909, row = 4, col = 2 },    -- Rache
    ["1:Improved Starfire"] = { spell = 16850, row = 4, col = 3 },    -- Verbessertes Sternenfeuer
    ["1:Nature's Grace"] = { spell = 16880, row = 5, col = 2 },    -- Anmut der Natur
    ["1:Eclipse"] = { spell = 408248, row = 5, col = 3 },    -- Finsternis
    ["1:Moonfury"] = { spell = 16896, row = 6, col = 2 },    -- Mondfuror
    ["1:Moonkin Form"] = { spell = 24858, row = 7, col = 2 },    -- Moonkingestalt
    ["2:Ferocity"] = { spell = 16934, row = 1, col = 2 },    -- Wildheit
    ["2:Furor"] = { spell = 17056, row = 1, col = 3 },    -- Ingrimm
    ["2:Feral Swiftness"] = { spell = 17002, row = 2, col = 1 },    -- Schnelligkeit der Wildnis
    ["2:Feral Instinct"] = { spell = 16947, row = 2, col = 2 },    -- Instinkt der Wildnis
    ["2:Thick Hide"] = { spell = 16929, row = 2, col = 4 },    -- Dickes Fell
    ["2:Shredding Attacks"] = { spell = 16966, row = 3, col = 1 },    -- Schreddernde Angriffe
    ["2:Savage Fury"] = { spell = 16998, row = 3, col = 2 },    -- Ungezähmte Wut
    ["2:Feral Charge"] = { spell = 1238122, row = 3, col = 3 },    -- Wilde Attacke
    ["2:Sharpened Claws"] = { spell = 16942, row = 3, col = 4 },    -- Geschärfte Klauen
    ["2:Predatory Strikes"] = { spell = 16972, row = 4, col = 1 },    -- Raubtierschläge
    ["2:Lacerate"] = { spell = 1328617, row = 4, col = 2 },    -- Aufschlitzen
    ["2:Predatory Discipline"] = { spell = 1328613, row = 4, col = 3 },    -- Disziplin des Raubtiers · von Hand: Name und Text; Vorauswahl nannte „Räuberische Disziplin“
    ["2:Blood Frenzy"] = { spell = 16958, row = 4, col = 4 },    -- Blutraserei
    ["2:Leader of the Pack"] = { spell = 17007, row = 5, col = 2 },    -- Rudelführer
    ["2:Natural Instinct"] = { spell = 1223242, row = 5, col = 4 },    -- Instinkt der Natur
    ["2:Rend and Tear"] = { spell = 1223246, row = 6, col = 1 },    -- Beißen und Reißen
    ["2:Primal Bite"] = { spell = 407995, row = 7, col = 2 },    -- Urtümlicher Biss
    ["2:Shifting Power"] = { spell = 1322605, row = 7, col = 3 },    -- Machtverschiebung
    ["3:Nature's Focus"] = { spell = 17063, row = 1, col = 2 },    -- Naturfokus
    ["3:Heart of the Wild"] = { spell = 17003, row = 1, col = 3 },    -- Herz der Wildnis
    ["3:Naturalist"] = { spell = 17069, row = 2, col = 1 },    -- Naturalist
    ["3:Reflection"] = { spell = 17106, row = 2, col = 2 },    -- Reflexion
    ["3:Gift of Nature"] = { spell = 17104, row = 3, col = 3 },    -- Geschenk der Natur
    ["3:Bloom"] = { spell = 1328621, row = 3, col = 4 },    -- Blüte · von Hand: Name und Text; Vorauswahl nannte „Erblühen“
    ["3:Improved Rejuvenation"] = { spell = 17111, row = 4, col = 3 },    -- Verbesserte Verjüngung
    ["3:Swiftmend"] = { spell = 18562, row = 4, col = 4 },    -- Rasche Heilung
    ["3:Nature's Swiftness"] = { spell = 17116, row = 5, col = 1 },    -- Schnelligkeit der Natur
    ["3:Living Spirit"] = { spell = 1309631, row = 5, col = 2 },    -- Geist des Lebens
    ["3:Improved Tranquility"] = { spell = 17123, row = 5, col = 4 },    -- Verbesserte Gelassenheit
    ["3:Improved Regrowth"] = { spell = 17074, row = 6, col = 3 },    -- Verbessertes Nachwachsen
    ["3:Wild Growth"] = { spell = 408120, row = 7, col = 2 },    -- Wildwuchs
}
