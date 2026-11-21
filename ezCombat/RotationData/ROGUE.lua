local _, ns = ...
local T = ns.RotationData.T

-- Schurke (ROGUE): Rotationen je Talentbaum und Spielweise für WoW Forever (Format: SPEZIFIKATION, Kopf von
-- RotationData.lua). Nur Fakten aus den Quellen – Rangfolge, Bedingungen –, alle Texte in eigenen Worten.
-- Quellen, abgerufen am 13.11.2026:
--   Meucheln:   https://www.icy-veins.com/wow-forever/assassination-rogue-melee-dps-pve-rotation-cooldowns-abilities  (Stand 04.11.2026)
--               https://www.icy-veins.com/wow-forever/assassination-rogue-leveling
--               https://www.wowhead.com/forever/guide/classes/rogue/assassination/rotation-cooldowns-pve-dps          (Stand 30.10.2026, älterer Talentstand)
--   Kampf:      https://www.icy-veins.com/wow-forever/combat-rogue-melee-dps-pve-rotation-cooldowns-abilities        (Stand 04.11.2026)
--               (nachgeprüft 20.11.2026: Nierenhieb 408 nennen alle drei Seiten nur als Werkzeug – Listeneintrag)
--               https://www.icy-veins.com/wow-forever/combat-rogue-leveling
--               https://www.wowhead.com/forever/guide/classes/rogue/combat/rotation-cooldowns-pve-dps                (Stand 30.10.2026)
--   Täuschung:  https://www.icy-veins.com/wow-forever/subtlety-rogue-melee-dps-pve-rotation-cooldowns-abilities      (Stand 04.11.2026)
--               https://www.icy-veins.com/wow-forever/subtlety-rogue-leveling
--               https://www.wowhead.com/forever/guide/classes/rogue/subtlety/rotation-cooldowns-pve-dps              (Stand 30.10.2026, vor dem Talent-Umbau vom 02.11.2026)
-- Hauptquelle ist Icy Veins (jünger, kennt den Umbau); wo Wowhead abweicht, steht es im Feld note.
-- Zauber-IDs (Rang 1) geprüft gegen nether.wowhead.com/forever. Nichts stammt aus einem Addon. Name, Symbol, Ränge,
-- gelernt, Kosten, Abklingzeit und Dauer liefert der Client zur Laufzeit.
--
-- Bauart aller Schurken-Rotationen: keine feste Folge, sondern eine Rangfolge (Reihenfolge der Liste) aus
-- Combo-Punkten, Energie und laufenden Effekten. Fest ist nur die Eröffnung aus der Verstohlenheit.
--
-- [V] = Annahme, im Spiel zu prüfen:
--   * Gifte sind Gegenstände; der Schritt hängt am gelernten Zauber 2842 (Gifte herstellen) als Träger. Ob der
--     Client ihn als gelernt meldet, zeigt erst das Spiel – sonst bleibt der Schritt stumm (nie falsch).
--   * Täuschung: Erdrosseln außerhalb der Verstohlenheit geht nur im Fenster nach Geisterhaftem Stoß. Der Schritt
--     verlässt sich darauf, dass der Client es sonst als „nicht nutzbar“ meldet.
-- Schwellen ohne Zahl in der Quelle (als „Annahme“ am Schritt): Combo-Punkte für Geisterhaften Stoß (höchstens 2,
-- weil danach Erdrosseln weitere Punkte bringt), Aufbauer nur bis 4 Punkte.
-- Scharfe Klinge und Adrenalinrausch haben keine Energie-Bedingung: Die Kraft ist im Kampf oft gesperrt (Befund aus dem
-- Spiel), ein gesperrter Wert machte den Schritt unbekannt, und er käme nie. „Nicht überlaufen“ steht nur im Text;
-- Adrenalinrausch kommt damit beim Pull wie bei Wowhead (Entscheidung des Nutzers vom 13.11.2026, „Alle nach Empfehlung“).
--
-- Bedarf (das Format kann es nicht, deshalb nur Text, optional oder situativ):
--   * Vorbereitung über einen Gegenstand: welches Gift auf welcher Hand liegt, ist nicht prüfbar – nur, ob die
--     Waffe überhaupt eine Verzauberung trägt. Name und Symbol des Gifts kann der Schritt nicht zeigen.
--   * Lebenszeit des Ziels, Bedrohung, Stellung hinter dem Ziel, zweiter Gegner, fremde Rüstungssenkung.
--   * „Energie ansparen“ ist kein Schritt: Ist nichts fällig, schlägt ezCombat nichts vor.

local DAGGER = { hand = "main", type = { "dagger" } }

ns.RotationData.Add("ROGUE", {
    ---------------------------------------------------------------------------------------------------------------
    -- Meucheln, Höchststufe
    ---------------------------------------------------------------------------------------------------------------
    { key = "assassination", tree = 1, name = T("Meucheln", "Assassination"),
      source = "https://www.icy-veins.com/wow-forever/assassination-rogue-melee-dps-pve-rotation-cooldowns-abilities",
      sources = { "https://www.icy-veins.com/wow-forever/assassination-rogue-melee-dps-pve-spec-builds-talents",
                  "https://www.wowhead.com/forever/guide/classes/rogue/assassination/rotation-cooldowns-pve-dps" },
      pick = { leveling = false },
      how = T("Kein fester Ablauf, sondern eine Rangfolge aus Combo-Punkten, Energie und laufenden Effekten. Vor dem Kampf beide Waffen vergiften, dann verstohlen mit {703} eröffnen. Im Kampf zuerst {5171} und {1943} halten, {1329283} nutzen, sobald es bereit ist, und mit {399956} Punkte aufbauen. {2098} kommt erst mit 5 Punkten, wenn beides läuft.",
              "No fixed sequence but a priority list driven by combo points, energy and running effects. Poison both weapons before combat, then open from stealth with {703}. In combat keep {5171} and {1943} up first, use {1329283} whenever it is ready and build points with {399956}. {2098} only comes at 5 points while both are up."),
      note = T("Ob das Ziel {1943} überlebt, ob die Bedrohung steht und ob du hinter dem Ziel stehst, sieht ezCombat nicht – das steht nur im Text. Wowhead (älterer Talentstand) nennt nur {5171} vor {2098} und empfiehlt {13877}.",
               "ezCombat can't see whether the target outlives {1943}, whether threat is settled or whether you stand behind it – that is text only. Wowhead (older talents) only lists {5171} before {2098} and recommends {13877}."),
      steps = {
        -- Vor dem Kampf --------------------------------------------------------------------------------------------
        { id = 2842, key = "poison:main", kind = "prepare", when = "enchant", hand = "main",
          text = T("Haupthand ohne Gift: {8679} auftragen.", "Main hand without poison: apply {8679}.") },    -- Gifte / Poisons [V]
        { id = 2842, key = "poison:off", kind = "prepare", when = "enchant", hand = "off",
          text = T("Nebenhand ohne Gift: {2823}, bis dahin {8679}.", "Off hand without poison: {2823}, until then {8679}.") },    -- Gifte / Poisons [V]
        { id = 1784, kind = "prepare", when = "stealth", need = { target = true },
          text = T("Vor jedem Kampf verstohlen an das Ziel heran.", "Sneak up on the target before every fight.") },    -- Verstohlenheit / Stealth
        -- Eröffnung ------------------------------------------------------------------------------------------------
        { id = 703, kind = "opener", when = "reactive", need = { stealth = true },
          text = T("Verstohlen und hinter dem Ziel: damit eröffnen.", "From stealth, behind the target: open with this.") },    -- Erdrosseln / Garrote
        -- Im Kampf (Reihenfolge = Rang) ----------------------------------------------------------------------------
        { id = 5171, kind = "maintain", when = "buff", need = { cp = { min = 1 } },
          text = T("Immer aktiv halten – geht ab dem ersten Combo-Punkt.", "Keep it up at all times – works from the first combo point.") },    -- Zerhäckseln / Slice and Dice
        -- zweiter Gegner ist für ezCombat unsichtbar: nur im Flächenmodus (den schaltet der Nutzer)
        { id = 13877, kind = "aoe", when = "ready",
          text = T("Flächenmodus: bei einem zweiten Gegner (braucht Punkte im Kampf-Baum).", "AoE mode: with a second enemy (needs points in the Combat tree).") },    -- Klingenwirbel / Blade Flurry
        { id = 1943, kind = "maintain", when = "dot", need = { cp = { min = 5 } },
          text = T("Mit 5 Combo-Punkten halten, wenn das Ziel lange genug lebt.", "Keep up with 5 combo points if the target lives long enough.") },    -- Blutung / Rupture
        -- ohne Energie-Bedingung: die Kraft ist im Kampf oft gesperrt (siehe Dateikopf)
        { id = 1329283, kind = "priority", when = "ready",
          text = T("Sobald bereit; bei fast voller Energie vorher etwas ausgeben.", "Whenever ready; at nearly full energy spend some first.") },    -- Scharfe Klinge / Shank
        { id = 14177, kind = "cooldown", burst = true, when = "ready", need = { cp = { min = 5 } },
          text = T("Mit 5 Combo-Punkten direkt vor {2098}, wenn die Bedrohung steht.", "At 5 combo points right before {2098}, once threat is settled.") },    -- Kaltblütigkeit / Cold Blood
        { id = 2098, kind = "priority", when = "finisher", cp = 5,
          text = T("Mit 5 Combo-Punkten, wenn {5171} und {1943} laufen.", "At 5 combo points while {5171} and {1943} are up.") },    -- Ausweiden / Eviscerate
        { id = 399956, kind = "filler", when = "filler", need = { cp = { max = 4 } },
          guess = T("„Aufbauen bis 4 Punkte“ ist geschätzt; die Quelle nennt keine Zahl.", "“Build up to 4 points” is estimated; the source gives no number."),
          text = T("Combo-Punkte aufbauen; braucht zwei Dolche.", "Build combo points; needs two daggers.") },    -- Verstümmeln / Mutilate
        { id = 53, kind = "filler", when = "filler", need = { unknown = 399956, weapon = DAGGER, cp = { max = 4 } },
          guess = T("„Aufbauen bis 4 Punkte“ ist geschätzt; die Quelle nennt keine Zahl.", "“Build up to 4 points” is estimated; the source gives no number."),
          text = T("Solange {399956} fehlt: Aufbau von hinten mit Dolch.", "Until you learn {399956}: build from behind with a dagger.") },    -- Meucheln / Backstab
        { id = 1752, kind = "filler", when = "filler", need = { cp = { max = 4 } },
          guess = T("„Aufbauen bis 4 Punkte“ ist geschätzt; die Quelle nennt keine Zahl.", "“Build up to 4 points” is estimated; the source gives no number."),
          text = T("Aufbau ohne Dolche oder von vorn.", "Builder without daggers or from the front.") },    -- Finsterer Stoß / Sinister Strike
        -- Situativ -------------------------------------------------------------------------------------------------
        { id = 8647, kind = "situational", when = "manual",
          text = T("Nur, wenn keine stärkere Rüstungssenkung auf dem Ziel liegt.", "Only when no stronger armor reduction is on the target.") },    -- Rüstung schwächen / Expose Armor
        { id = 1856, kind = "situational", when = "manual",
          text = T("Kein Schadensknopf: Mechanik umgehen oder Bedrohung abwerfen.", "Not a damage button: dodge a mechanic or drop threat.") },    -- Verschwinden / Vanish
        { id = 408, kind = "situational", when = "manual",
          text = T("Betäubung, je mehr Combo-Punkte, desto länger – kein Schadensknopf.", "Stun, longer with more combo points – not a damage button.") },    -- Nierenhieb / Kidney Shot
      } },

    ---------------------------------------------------------------------------------------------------------------
    -- Kampf, Höchststufe (Schwert- und Dolch-Spielweise: der Aufbauer folgt der Waffe in der Haupthand)
    ---------------------------------------------------------------------------------------------------------------
    { key = "combat", tree = 2, name = T("Kampf", "Combat"),
      source = "https://www.icy-veins.com/wow-forever/combat-rogue-melee-dps-pve-rotation-cooldowns-abilities",
      sources = { "https://www.icy-veins.com/wow-forever/combat-rogue-melee-dps-pve-spec-builds-talents",
                  "https://www.wowhead.com/forever/guide/classes/rogue/combat/rotation-cooldowns-pve-dps" },
      pick = { leveling = false },
      how = T("Die einfachste Spielweise: {1752} (mit Dolch in der Haupthand {53}) baut Combo-Punkte auf, Finisher verbrauchen sie. Vor dem Kampf Gifte auf beide Waffen, dann verstohlen mit {703} eröffnen. Im Kampf {5171} immer halten, {1943} bei langlebigen Zielen, {1329283} sobald bereit; {2098} erst mit 5 Punkten. {13877} und {13750} gleich mit dem Pull zünden; {13750} schlägt ezCombat ab Werk nur gegen Elite und Bosse vor („Immer“ ist wählbar).",
              "The simplest playstyle: {1752} (with a dagger in the main hand {53}) builds combo points, finishers spend them. Put poisons on both weapons before combat, then open from stealth with {703}. In combat always keep {5171} up, {1943} on long-lived targets, {1329283} whenever ready; {2098} only at 5 points. Fire {13877} and {13750} right away on the pull; by default ezCombat suggests {13750} only against elites and bosses (\"Always\" is selectable)."),
      note = T("Wowhead (älter) zündet {13877} und {13750} gemeinsam beim Pull. Ein zweiter Gegner, die Bedrohung und die Lebenszeit des Ziels sind für ezCombat unsichtbar – wer {13877} aufsparen will, schaltet den Schritt aus.",
               "Wowhead (older) fires {13877} and {13750} together on the pull. A second enemy, threat and the target's time to live are invisible to ezCombat – turn the {13877} step off if you want to save it."),
      steps = {
        -- Vor dem Kampf --------------------------------------------------------------------------------------------
        { id = 2842, key = "poison:main", kind = "prepare", when = "enchant", hand = "main",
          text = T("Haupthand ohne Gift: {8679} auftragen.", "Main hand without poison: apply {8679}.") },    -- Gifte / Poisons [V]
        { id = 2842, key = "poison:off", kind = "prepare", when = "enchant", hand = "off",
          text = T("Nebenhand ohne Gift: {2823}, bis dahin {8679}.", "Off hand without poison: {2823}, until then {8679}.") },    -- Gifte / Poisons [V]
        { id = 1784, kind = "prepare", when = "stealth", need = { target = true },
          text = T("Vor jedem Kampf verstohlen an das Ziel heran.", "Sneak up on the target before every fight.") },    -- Verstohlenheit / Stealth
        -- Eröffnung ------------------------------------------------------------------------------------------------
        { id = 703, kind = "opener", when = "reactive", need = { stealth = true },
          text = T("Verstohlen und hinter dem Ziel: damit eröffnen.", "From stealth, behind the target: open with this.") },    -- Erdrosseln / Garrote
        -- Im Kampf (Reihenfolge = Rang) ----------------------------------------------------------------------------
        { id = 5171, kind = "maintain", when = "buff", need = { cp = { min = 1 } },
          text = T("Immer aktiv halten – geht ab dem ersten Combo-Punkt.", "Keep it up at all times – works from the first combo point.") },    -- Zerhäckseln / Slice and Dice
        { id = 13877, kind = "cooldown", when = "ready",
          text = T("Sofort – oder aufheben, bis ein zweiter Gegner in Reichweite ist.", "At once – or hold it until a second enemy is in reach.") },    -- Klingenwirbel / Blade Flurry
        -- ohne Energie-Bedingung (Dateikopf): kommt mit dem Pull, nicht erst bei leerer Energie
        { id = 13750, kind = "cooldown", burst = true, when = "ready",
          text = T("Zum Kampfbeginn zünden, sobald die Bedrohung steht.", "Fire it as the fight starts once threat is settled.") },    -- Adrenalinrausch / Adrenaline Rush
        { id = 1943, kind = "maintain", when = "dot", need = { cp = { min = 5 } },
          text = T("Mit 5 Combo-Punkten halten, wenn das Ziel lange genug lebt.", "Keep up with 5 combo points if the target lives long enough.") },    -- Blutung / Rupture
        { id = 14251, kind = "priority", when = "reactive",
          text = T("Sofort, nachdem du pariert hast.", "At once after you parry.") },    -- Riposte / Riposte
        -- ohne Energie-Bedingung: die Kraft ist im Kampf oft gesperrt (siehe Dateikopf)
        { id = 1329283, kind = "priority", when = "ready",
          text = T("Sobald bereit; bei fast voller Energie vorher etwas ausgeben.", "Whenever ready; at nearly full energy spend some first.") },    -- Scharfe Klinge / Shank
        { id = 14177, kind = "cooldown", burst = true, when = "ready", need = { cp = { min = 5 } },
          text = T("Falls geskillt: mit 5 Combo-Punkten direkt vor {2098}.", "If talented: at 5 combo points right before {2098}.") },    -- Kaltblütigkeit / Cold Blood
        { id = 2098, kind = "priority", when = "finisher", cp = 5,
          text = T("Mit 5 Combo-Punkten, wenn {5171} und {1943} laufen.", "At 5 combo points while {5171} and {1943} are up.") },    -- Ausweiden / Eviscerate
        { id = 53, kind = "filler", when = "filler", need = { weapon = DAGGER, cp = { max = 4 } },
          guess = T("„Aufbauen bis 4 Punkte“ ist geschätzt; die Quelle nennt keine Zahl.", "“Build up to 4 points” is estimated; the source gives no number."),
          text = T("Dolch-Spielweise: Aufbau von hinten statt {1752}.", "Dagger build: build from behind instead of {1752}.") },    -- Meucheln / Backstab
        { id = 1752, kind = "filler", when = "filler", need = { cp = { max = 4 } },
          guess = T("„Aufbauen bis 4 Punkte“ ist geschätzt; die Quelle nennt keine Zahl.", "“Build up to 4 points” is estimated; the source gives no number."),
          text = T("Combo-Punkte aufbauen.", "Build combo points.") },    -- Finsterer Stoß / Sinister Strike
        -- Situativ -------------------------------------------------------------------------------------------------
        { id = 8647, kind = "situational", when = "manual",
          text = T("Nur, wenn keine stärkere Rüstungssenkung auf dem Ziel liegt.", "Only when no stronger armor reduction is on the target.") },    -- Rüstung schwächen / Expose Armor
        { id = 5277, kind = "situational", when = "manual",
          text = T("Für den Notfall; in Gruppen aufheben.", "For emergencies; save it in groups.") },    -- Entrinnen / Evasion
        { id = 1856, kind = "situational", when = "manual",
          text = T("Kein Schadensknopf: Mechanik umgehen oder Bedrohung abwerfen.", "Not a damage button: dodge a mechanic or drop threat.") },    -- Verschwinden / Vanish
        { id = 408, kind = "situational", when = "manual",
          text = T("Betäubung, je mehr Combo-Punkte, desto länger – kein Schadensknopf.", "Stun, longer with more combo points – not a damage button.") },    -- Nierenhieb / Kidney Shot
      } },

    ---------------------------------------------------------------------------------------------------------------
    -- Täuschung, Höchststufe (Stand nach dem Talent-Umbau vom 02.11.2026)
    ---------------------------------------------------------------------------------------------------------------
    { key = "subtlety", tree = 3, name = T("Täuschung", "Subtlety"),
      source = "https://www.icy-veins.com/wow-forever/subtlety-rogue-melee-dps-pve-rotation-cooldowns-abilities",
      sources = { "https://www.icy-veins.com/wow-forever/subtlety-rogue-melee-dps-pve-spec-builds-talents",
                  "https://www.wowhead.com/forever/guide/classes/rogue/subtlety/rotation-cooldowns-pve-dps" },
      pick = { leveling = false },
      how = T("Viele kurze Abklingzeiten und Schaden über Zeit; Energie wird angespart, damit alles bei Bereitschaft bezahlbar ist, darf aber nie überlaufen. Eröffnung verstohlen: {14183}, dann {8676}. Mit 5 Punkten zuerst {1943}, dann {1316709}, zuletzt {5171}. {1329283} und {14278} sobald bereit, nach {14278} sofort {703}. {16511} füllt auf. Läuft alles und sind 5 Punkte da, schlägt ezCombat nichts vor: Energie sparen.",
              "Many short cooldowns and damage over time; you pool energy so everything is affordable when it comes up, but never let it overcap. Open from stealth: {14183}, then {8676}. At 5 points {1943} first, then {1316709}, {5171} last. {1329283} and {14278} whenever ready, {703} right after {14278}. {16511} fills. With everything up and 5 points banked ezCombat suggests nothing: pool energy."),
      note = T("Wowhead beschreibt noch den Stand vor dem Umbau ({703} als Eröffner, {5171} vor {1943}). Lebenszeit des Ziels, Stellung und kommende Schadensphasen sieht ezCombat nicht.",
               "Wowhead still describes the state before the rework ({703} as the opener, {5171} above {1943}). ezCombat can't see time to live, positioning or upcoming damage phases."),
      steps = {
        -- Vor dem Kampf --------------------------------------------------------------------------------------------
        { id = 2842, key = "poison:main", kind = "prepare", when = "enchant", hand = "main",
          text = T("Haupthand ohne Gift: {8679} auftragen.", "Main hand without poison: apply {8679}.") },    -- Gifte / Poisons [V]
        { id = 2842, key = "poison:off", kind = "prepare", when = "enchant", hand = "off",
          text = T("Nebenhand ohne Gift: {2823}, bis dahin {8679}.", "Off hand without poison: {2823}, until then {8679}.") },    -- Gifte / Poisons [V]
        { id = 1784, kind = "prepare", when = "stealth", need = { target = true },
          text = T("Vor jedem Kampf verstohlen an das Ziel heran.", "Sneak up on the target before every fight.") },    -- Verstohlenheit / Stealth
        -- Eröffnung: feste Folge aus der Verstohlenheit ------------------------------------------------------------
        { id = 14183, kind = "opener", when = "ready", need = { stealth = true, cp = { max = 3 } },
          text = T("Getarnt direkt vor dem ersten Angriff: bringt Combo-Punkte.", "From stealth right before your first attack: grants combo points.") },    -- Konzentration / Premeditation
        { id = 8676, kind = "opener", when = "reactive", need = { stealth = true, weapon = DAGGER },
          text = T("Erster Angriff mit Dolch von hinten; dem Tank kurz Zeit lassen.", "First attack with a dagger from behind; give the tank a moment.") },    -- Hinterhalt / Ambush
        -- Im Kampf (Reihenfolge = Rang) ----------------------------------------------------------------------------
        { id = 1943, kind = "maintain", when = "dot", need = { cp = { min = 5 } },
          text = T("Immer halten, mit 5 Combo-Punkten – vor allem anderen.", "Always keep it up, at 5 combo points – before everything else.") },    -- Blutung / Rupture
        { id = 1316709, kind = "priority", when = "finisher", cp = 5,
          text = T("Mit 5 Combo-Punkten, sooft es bereit ist; Energie dafür sparen.", "At 5 combo points whenever ready; pool energy for it.") },    -- Todesmal / Death Mark
        -- [V] nutzbar nur verstohlen oder im Fenster nach 14278 – das meldet der Client (siehe Dateikopf)
        { id = 703, kind = "maintain", when = "dot", need = { cp = { max = 3 } },
          text = T("Direkt nach {14278} erneuern – nicht mit 4 oder mehr Punkten.", "Renew right after {14278} – not at 4 or more points.") },    -- Erdrosseln / Garrote
        { id = 5171, kind = "maintain", when = "buff", need = { cp = { min = 5 } },
          text = T("Möglichst ohne Lücke halten; mit 5 Combo-Punkten erneuern.", "Keep it running with few gaps; renew at 5 combo points.") },    -- Zerhäckseln / Slice and Dice
        -- ohne Energie-Bedingung: die Kraft ist im Kampf oft gesperrt (siehe Dateikopf)
        { id = 1329283, kind = "priority", when = "ready", need = { cp = { max = 3 } },
          text = T("Sobald bereit, bei 0 bis 3 Combo-Punkten; Energie nicht überlaufen lassen.", "Whenever ready, at 0 to 3 combo points; don't let energy overcap.") },    -- Scharfe Klinge / Shank
        { id = 14278, kind = "priority", when = "ready", need = { cp = { max = 2 } },
          guess = T("Höchstens 2 Punkte ist geschätzt, weil {703} danach weitere bringt.", "At most 2 points is estimated, as {703} adds more afterwards."),
          text = T("Sobald bereit; danach sofort {703}.", "Whenever ready; follow up with {703} at once.") },    -- Geisterhafter Stoß / Ghostly Strike
        { id = 14183, kind = "cooldown", when = "ready", need = { combat = true, cp = { max = 3 } },
          text = T("Sobald bereit, bei höchstens 3 Combo-Punkten.", "Whenever ready, at 3 combo points or fewer.") },    -- Konzentration / Premeditation
        { id = 16511, kind = "filler", when = "filler", need = { cp = { max = 4 } },
          guess = T("„Aufbauen bis 4 Punkte“ ist geschätzt; die Quelle nennt keine Zahl.", "“Build up to 4 points” is estimated; the source gives no number."),
          text = T("Einziger Aufbauer; mit vollen Punkten nicht weiterdrücken.", "Your only builder; don't keep pressing it at full points.") },    -- Blutsturz / Hemorrhage
        { id = 1752, kind = "filler", when = "filler", need = { unknown = 16511, cp = { max = 4 } },
          guess = T("„Aufbauen bis 4 Punkte“ ist geschätzt; die Quelle nennt keine Zahl.", "“Build up to 4 points” is estimated; the source gives no number."),
          text = T("Aufbau, solange {16511} fehlt.", "Builder until you learn {16511}.") },    -- Finsterer Stoß / Sinister Strike
        -- Situativ -------------------------------------------------------------------------------------------------
        { id = 2098, kind = "situational", when = "manual",
          text = T("Auf Höchststufe nicht Teil der Liste; höchstens als Gnadenstoß.", "Not part of the list at max level; a killing blow at most.") },    -- Ausweiden / Eviscerate
        { id = 1856, kind = "situational", when = "manual",
          text = T("Aufheben: Zusatzgegner, Schadensphase oder Notfall.", "Save it: adds, a damage phase or an emergency.") },    -- Verschwinden / Vanish
        { id = 14185, kind = "situational", when = "manual",
          text = T("Aufheben; setzt deine Abklingzeiten zurück.", "Save it; resets your cooldowns.") },    -- Vorbereitung / Preparation
        { id = 408, kind = "situational", when = "manual",
          text = T("Betäubung, je mehr Combo-Punkte, desto länger – kein Schadensknopf.", "Stun, longer with more combo points – not a damage button.") },    -- Nierenhieb / Kidney Shot
      } },

    ---------------------------------------------------------------------------------------------------------------
    -- Meucheln, Leveln
    ---------------------------------------------------------------------------------------------------------------
    { key = "assassination_level", tree = 1, name = T("Meucheln (Leveln)", "Assassination (levelling)"),
      source = "https://www.icy-veins.com/wow-forever/assassination-rogue-leveling",
      sources = { "https://www.icy-veins.com/wow-forever/assassination-rogue-melee-dps-pve-rotation-cooldowns-abilities" },
      pick = { leveling = true },
      how = T("Beim Leveln sterben Gegner schnell: verstohlen eröffnen, Combo-Punkte aufbauen und mit 5 Punkten {2098} setzen. {5171} lohnt nur, wenn noch Gegner für seine Laufzeit da sind. Aufbauer ist zuerst {53} von hinten oder {1752} von vorn, später {399956}. Sobald du Gifte herstellen kannst, gehören sie auf beide Waffen. Lass die Energie nie ungenutzt überlaufen.",
              "While levelling enemies die fast: open from stealth, build combo points and spend 5 points on {2098}. {5171} is only worth it while enemies remain for its duration. Your builder is {53} from behind or {1752} from the front at first, later {399956}. Once you can make poisons, put them on both weapons. Never let energy overcap unused."),
      note = T("Ob ein Gegner betäubbar ist, flieht oder gleich stirbt, sieht ezCombat nicht – {1833} ist deshalb ein Schritt zum Einschalten, das Gift gegen Flüchtende steht nur im Text.",
               "ezCombat can't see whether an enemy can be stunned, flees or is about to die – so {1833} is a step you turn on, and the poison against runners is text only."),
      steps = {
        -- Vor dem Kampf --------------------------------------------------------------------------------------------
        { id = 2842, key = "poison:main", kind = "prepare", when = "enchant", hand = "main",
          text = T("Haupthand ohne Gift: {8679} auftragen.", "Main hand without poison: apply {8679}.") },    -- Gifte / Poisons [V]
        { id = 2842, key = "poison:off", kind = "prepare", when = "enchant", hand = "off",
          text = T("Nebenhand ohne Gift: beim Leveln ebenfalls {8679}.", "Off hand without poison: {8679} here too while levelling.") },    -- Gifte / Poisons [V]
        { id = 1784, kind = "prepare", when = "stealth", need = { target = true },
          text = T("Vor jedem Kampf verstohlen an das Ziel heran.", "Sneak up on the target before every fight.") },    -- Verstohlenheit / Stealth
        -- Eröffnung ------------------------------------------------------------------------------------------------
        { id = 1833, kind = "opener", when = "reactive", optional = true, need = { stealth = true, solo = true },
          text = T("Allein gegen betäubbare Ziele statt {703} – bei Bedarf einschalten.", "Solo against stunnable targets instead of {703} – turn on if needed.") },    -- Fieser Trick / Cheap Shot
        { id = 703, kind = "opener", when = "reactive", need = { stealth = true },
          text = T("Verstohlen und hinter dem Ziel: damit eröffnen.", "From stealth, behind the target: open with this.") },    -- Erdrosseln / Garrote
        -- Im Kampf (Reihenfolge = Rang) ----------------------------------------------------------------------------
        { id = 5171, kind = "maintain", when = "buff", need = { cp = { min = 1 } },
          text = T("Lohnt, solange Gegner für die Laufzeit da sind – sonst ausschalten.", "Worth it while enemies remain for its duration – else turn it off.") },    -- Zerhäckseln / Slice and Dice
        -- ohne Energie-Bedingung: die Kraft ist im Kampf oft gesperrt (siehe Dateikopf)
        { id = 1329283, kind = "priority", when = "ready",
          text = T("Sobald bereit; bei fast voller Energie vorher etwas ausgeben.", "Whenever ready; at nearly full energy spend some first.") },    -- Scharfe Klinge / Shank
        { id = 14177, kind = "cooldown", burst = true, when = "ready", need = { cp = { min = 5 } },
          text = T("Mit 5 Combo-Punkten direkt vor {2098}.", "At 5 combo points right before {2098}.") },    -- Kaltblütigkeit / Cold Blood
        { id = 2098, kind = "priority", when = "finisher", cp = 5,
          text = T("Mit 5 Combo-Punkten; bei fast totem Ziel von Hand auch früher.", "At 5 combo points; by hand earlier on a nearly dead target.") },    -- Ausweiden / Eviscerate
        { id = 399956, kind = "filler", when = "filler", need = { cp = { max = 4 } },
          guess = T("„Aufbauen bis 4 Punkte“ ist geschätzt; die Quelle nennt keine Zahl.", "“Build up to 4 points” is estimated; the source gives no number."),
          text = T("Sobald gelernt der Aufbauer; braucht zwei Dolche.", "Your builder once learned; needs two daggers.") },    -- Verstümmeln / Mutilate
        { id = 53, kind = "filler", when = "filler", need = { unknown = 399956, weapon = DAGGER, cp = { max = 4 } },
          guess = T("„Aufbauen bis 4 Punkte“ ist geschätzt; die Quelle nennt keine Zahl.", "“Build up to 4 points” is estimated; the source gives no number."),
          text = T("Solange {399956} fehlt: Aufbau von hinten mit Dolch.", "Until you learn {399956}: build from behind with a dagger.") },    -- Meucheln / Backstab
        { id = 1752, kind = "filler", when = "filler", need = { cp = { max = 4 } },
          guess = T("„Aufbauen bis 4 Punkte“ ist geschätzt; die Quelle nennt keine Zahl.", "“Build up to 4 points” is estimated; the source gives no number."),
          text = T("Aufbau ohne Dolch oder von vorn.", "Builder without a dagger or from the front.") },    -- Finsterer Stoß / Sinister Strike
        -- Situativ -------------------------------------------------------------------------------------------------
        { id = 3408, kind = "situational", when = "manual",
          text = T("Gegen flüchtende Gegner statt eines Schadensgifts.", "Against fleeing enemies instead of a damage poison.") },    -- Verkrüppelndes Gift / Crippling Poison
        { id = 1856, kind = "situational", when = "manual",
          text = T("Für den Notfall aufheben.", "Save it for emergencies.") },    -- Verschwinden / Vanish
      } },

    ---------------------------------------------------------------------------------------------------------------
    -- Kampf, Leveln
    ---------------------------------------------------------------------------------------------------------------
    { key = "combat_level", tree = 2, name = T("Kampf (Leveln)", "Combat (levelling)"),
      source = "https://www.icy-veins.com/wow-forever/combat-rogue-leveling",
      sources = { "https://www.icy-veins.com/wow-forever/combat-rogue-melee-dps-pve-rotation-cooldowns-abilities" },
      pick = { leveling = true },
      how = T("Verstohlen eröffnen, mit {1752} Combo-Punkte aufbauen und sie mit 5 Punkten in {2098} stecken. {14251} kommt sofort, wenn du pariert hast. {5171} lohnt, solange noch Gegner für seine Laufzeit da sind. Sobald du Gifte herstellen kannst, gehören sie auf beide Waffen. {13877} und {13750} machen Kämpfe gegen mehrere oder starke Gegner leichter; {13750} kommt ab Werk nur gegen Elite und Bosse („Immer“ ist wählbar). Lass die Energie nie ungenutzt überlaufen.",
              "Open from stealth, build combo points with {1752} and spend 5 points on {2098}. {14251} comes at once after you parry. {5171} is worth it while enemies remain for its duration. Once you can make poisons, put them on both weapons. {13877} and {13750} ease fights against several or strong enemies; by default {13750} comes only against elites and bosses (\"Always\" is selectable). Never let energy overcap unused."),
      note = T("Die Leveling-Liste der Quelle kennt weder {1943} noch {8647}. Ob ein Gegner betäubbar ist oder ein zweiter dazukommt, sieht ezCombat nicht.",
               "The source's levelling list has neither {1943} nor {8647}. ezCombat can't see whether an enemy can be stunned or a second one joins."),
      steps = {
        -- Vor dem Kampf --------------------------------------------------------------------------------------------
        { id = 2842, key = "poison:main", kind = "prepare", when = "enchant", hand = "main",
          text = T("Haupthand ohne Gift: {8679} auftragen.", "Main hand without poison: apply {8679}.") },    -- Gifte / Poisons [V]
        { id = 2842, key = "poison:off", kind = "prepare", when = "enchant", hand = "off",
          text = T("Nebenhand ohne Gift: beim Leveln ebenfalls {8679}.", "Off hand without poison: {8679} here too while levelling.") },    -- Gifte / Poisons [V]
        { id = 1784, kind = "prepare", when = "stealth", need = { target = true },
          text = T("Vor jedem Kampf verstohlen an das Ziel heran.", "Sneak up on the target before every fight.") },    -- Verstohlenheit / Stealth
        -- Eröffnung ------------------------------------------------------------------------------------------------
        { id = 1833, kind = "opener", when = "reactive", optional = true, need = { stealth = true, solo = true },
          text = T("Allein gegen betäubbare Ziele statt {703} – bei Bedarf einschalten.", "Solo against stunnable targets instead of {703} – turn on if needed.") },    -- Fieser Trick / Cheap Shot
        { id = 703, kind = "opener", when = "reactive", need = { stealth = true },
          text = T("Verstohlen und hinter dem Ziel: damit eröffnen.", "From stealth, behind the target: open with this.") },    -- Erdrosseln / Garrote
        -- Im Kampf (Reihenfolge = Rang) ----------------------------------------------------------------------------
        { id = 14251, kind = "priority", when = "reactive",
          text = T("Sofort, nachdem du pariert hast.", "At once after you parry.") },    -- Riposte / Riposte
        { id = 5171, kind = "maintain", when = "buff", need = { cp = { min = 1 } },
          text = T("Lohnt, solange Gegner für die Laufzeit da sind – sonst ausschalten.", "Worth it while enemies remain for its duration – else turn it off.") },    -- Zerhäckseln / Slice and Dice
        { id = 13877, kind = "cooldown", when = "ready",
          text = T("Sofort – oder für zwei Gegner zugleich aufheben.", "At once – or save it for two enemies at a time.") },    -- Klingenwirbel / Blade Flurry
        -- ohne Energie-Bedingung (Dateikopf)
        { id = 13750, kind = "cooldown", burst = true, when = "ready",
          text = T("Zum Kampfbeginn zünden, zusammen mit den anderen Abklingzeiten.", "Fire it as the fight starts, together with your other cooldowns.") },    -- Adrenalinrausch / Adrenaline Rush
        -- ohne Energie-Bedingung: die Kraft ist im Kampf oft gesperrt (siehe Dateikopf)
        { id = 1329283, kind = "priority", when = "ready",
          text = T("Sobald bereit; bei fast voller Energie vorher etwas ausgeben.", "Whenever ready; at nearly full energy spend some first.") },    -- Scharfe Klinge / Shank
        { id = 2098, kind = "priority", when = "finisher", cp = 5,
          text = T("Mit 5 Combo-Punkten; bei fast totem Ziel von Hand auch früher.", "At 5 combo points; by hand earlier on a nearly dead target.") },    -- Ausweiden / Eviscerate
        { id = 53, kind = "filler", when = "filler", need = { weapon = DAGGER, cp = { max = 4 } },
          guess = T("„Aufbauen bis 4 Punkte“ ist geschätzt; die Quelle nennt keine Zahl.", "“Build up to 4 points” is estimated; the source gives no number."),
          text = T("Dolch-Spielweise: Aufbau von hinten statt {1752}.", "Dagger build: build from behind instead of {1752}.") },    -- Meucheln / Backstab
        { id = 1752, kind = "filler", when = "filler", need = { cp = { max = 4 } },
          guess = T("„Aufbauen bis 4 Punkte“ ist geschätzt; die Quelle nennt keine Zahl.", "“Build up to 4 points” is estimated; the source gives no number."),
          text = T("Combo-Punkte aufbauen.", "Build combo points.") },    -- Finsterer Stoß / Sinister Strike
        -- Situativ -------------------------------------------------------------------------------------------------
        { id = 5277, kind = "situational", when = "manual",
          text = T("Allein oft nutzen, gern mit {13877} gegen zwei Gegner.", "Use it often solo, ideally with {13877} against two enemies.") },    -- Entrinnen / Evasion
        { id = 3408, kind = "situational", when = "manual",
          text = T("Gegen flüchtende Gegner statt eines Schadensgifts.", "Against fleeing enemies instead of a damage poison.") },    -- Verkrüppelndes Gift / Crippling Poison
        { id = 1856, kind = "situational", when = "manual",
          text = T("Für den Notfall aufheben.", "Save it for emergencies.") },    -- Verschwinden / Vanish
      } },

    ---------------------------------------------------------------------------------------------------------------
    -- Täuschung, Leveln
    ---------------------------------------------------------------------------------------------------------------
    { key = "subtlety_level", tree = 3, name = T("Täuschung (Leveln)", "Subtlety (levelling)"),
      source = "https://www.icy-veins.com/wow-forever/subtlety-rogue-leveling",
      sources = { "https://www.icy-veins.com/wow-forever/subtlety-rogue-melee-dps-pve-rotation-cooldowns-abilities" },
      pick = { leveling = true },
      how = T("Verstohlen mit einem Dolch von hinten eröffnen, sobald gelernt mit {8676}. Aufbauer sind anfangs {53} von hinten und {1752} von vorn, später nur noch {16511}. Finisher ist früh {5171}, später {1943} und zuletzt {1316709}; {2098} nimmst du, wenn alles läuft oder das Ziel gleich fällt. {1329283} und {14278} nutzt du, sobald sie bereit sind – nach {14278} folgt sofort {703}.",
              "Open from stealth with a dagger from behind, with {8676} once learned. Your builders are {53} from behind and {1752} from the front at first, later only {16511}. Your finisher is {5171} early on, later {1943} and finally {1316709}; use {2098} when all is up or the target is about to die. Use {1329283} and {14278} whenever ready – {703} follows {14278} at once."),
      note = T("Ob das Ziel gleich stirbt und ob du hinter ihm stehst, sieht ezCombat nicht. Ab wann {1943} der übliche Finisher ist, folgt der Stufen-Angabe der Quelle.",
               "ezCombat can't see whether the target is about to die or whether you stand behind it. When {1943} becomes your usual finisher follows the level given by the source."),
      steps = {
        -- Vor dem Kampf --------------------------------------------------------------------------------------------
        { id = 2842, key = "poison:main", kind = "prepare", when = "enchant", hand = "main",
          text = T("Haupthand ohne Gift: {8679} auftragen.", "Main hand without poison: apply {8679}.") },    -- Gifte / Poisons [V]
        { id = 2842, key = "poison:off", kind = "prepare", when = "enchant", hand = "off",
          text = T("Nebenhand ohne Gift: beim Leveln ebenfalls {8679}.", "Off hand without poison: {8679} here too while levelling.") },    -- Gifte / Poisons [V]
        { id = 1784, kind = "prepare", when = "stealth", need = { target = true },
          text = T("Vor jedem Kampf verstohlen an das Ziel heran.", "Sneak up on the target before every fight.") },    -- Verstohlenheit / Stealth
        -- Eröffnung: feste Folge aus der Verstohlenheit ------------------------------------------------------------
        { id = 14183, kind = "opener", when = "ready", need = { stealth = true, cp = { max = 3 } },
          text = T("Getarnt direkt vor dem ersten Angriff: bringt Combo-Punkte.", "From stealth right before your first attack: grants combo points.") },    -- Konzentration / Premeditation
        { id = 8676, kind = "opener", when = "reactive", need = { stealth = true, weapon = DAGGER },
          text = T("Erster Angriff mit Dolch von hinten.", "First attack with a dagger from behind.") },    -- Hinterhalt / Ambush
        { id = 53, kind = "opener", when = "ready", need = { stealth = true, unknown = 8676, weapon = DAGGER },
          text = T("Solange {8676} fehlt: verstohlen von hinten eröffnen.", "Until you learn {8676}: open from stealth, from behind.") },    -- Meucheln / Backstab
        -- Im Kampf (Reihenfolge = Rang) ----------------------------------------------------------------------------
        -- Stufen-Schwelle aus der Quelle (Leveling-Guide): vorher ist der Finisher 5171
        { id = 1943, kind = "maintain", when = "dot", need = { level = { min = 30 }, cp = { min = 5 } },
          text = T("Später im Leveln der übliche Finisher, mit 5 Combo-Punkten.", "Later while levelling your usual finisher, at 5 combo points.") },    -- Blutung / Rupture
        { id = 1316709, kind = "priority", when = "finisher", cp = 5,
          text = T("Mit 5 Combo-Punkten, sooft es bereit ist.", "At 5 combo points whenever it is ready.") },    -- Todesmal / Death Mark
        -- [V] nutzbar nur verstohlen oder im Fenster nach 14278 – das meldet der Client (siehe Dateikopf)
        { id = 703, kind = "maintain", when = "dot", need = { cp = { max = 3 } },
          text = T("Fehlt es: verstohlen oder direkt nach {14278} setzen.", "When missing: apply from stealth or right after {14278}.") },    -- Erdrosseln / Garrote
        -- Stufen-Schwelle aus der Quelle (Leveling-Guide, wie bei 1943): bis 29 der Finisher, ab 30 nur mit 5 Punkten
        { id = 5171, kind = "maintain", when = "buff", need = { level = { max = 29 }, cp = { min = 1 } },
          text = T("Früh dein wichtigster Finisher, ab dem ersten Combo-Punkt.", "Your main finisher early on, from the first combo point.") },    -- Zerhäckseln / Slice and Dice
        { id = 5171, key = "maintain:5171:late", kind = "maintain", when = "buff", need = { level = { min = 30 }, cp = { min = 5 } },
          text = T("Später nach {1943}, nur noch mit 5 Combo-Punkten.", "Later after {1943}, only at 5 combo points.") },    -- Zerhäckseln / Slice and Dice
        -- ohne Energie-Bedingung: die Kraft ist im Kampf oft gesperrt (siehe Dateikopf)
        { id = 1329283, kind = "priority", when = "ready", need = { cp = { max = 3 } },
          text = T("Sobald bereit, bei 0 bis 3 Combo-Punkten; Energie nicht überlaufen lassen.", "Whenever ready, at 0 to 3 combo points; don't let energy overcap.") },    -- Scharfe Klinge / Shank
        { id = 14278, kind = "priority", when = "ready", need = { cp = { max = 2 } },
          guess = T("Höchstens 2 Punkte ist geschätzt, weil {703} danach weitere bringt.", "At most 2 points is estimated, as {703} adds more afterwards."),
          text = T("Sobald bereit; danach sofort {703}.", "Whenever ready; follow up with {703} at once.") },    -- Geisterhafter Stoß / Ghostly Strike
        { id = 14183, kind = "cooldown", when = "ready", need = { combat = true, cp = { max = 3 } },
          text = T("Sobald bereit, bei höchstens 3 Combo-Punkten.", "Whenever ready, at 3 combo points or fewer.") },    -- Konzentration / Premeditation
        { id = 2098, kind = "phase", when = "finisher", cp = 5,
          text = T("Mit 5 Punkten, wenn alles läuft oder das Ziel gleich fällt.", "At 5 points when all is up or the target is about to die.") },    -- Ausweiden / Eviscerate
        { id = 16511, kind = "filler", when = "filler", need = { cp = { max = 4 } },
          guess = T("„Aufbauen bis 4 Punkte“ ist geschätzt; die Quelle nennt keine Zahl.", "“Build up to 4 points” is estimated; the source gives no number."),
          text = T("Sobald gelernt dein einziger Aufbauer.", "Your only builder once learned.") },    -- Blutsturz / Hemorrhage
        { id = 53, kind = "filler", when = "filler", need = { unknown = 16511, weapon = DAGGER, cp = { max = 4 } },
          guess = T("„Aufbauen bis 4 Punkte“ ist geschätzt; die Quelle nennt keine Zahl.", "“Build up to 4 points” is estimated; the source gives no number."),
          text = T("Solange {16511} fehlt: Aufbau von hinten mit Dolch.", "Until you learn {16511}: build from behind with a dagger.") },    -- Meucheln / Backstab
        { id = 1752, kind = "filler", when = "filler", need = { unknown = 16511, cp = { max = 4 } },
          guess = T("„Aufbauen bis 4 Punkte“ ist geschätzt; die Quelle nennt keine Zahl.", "“Build up to 4 points” is estimated; the source gives no number."),
          text = T("Solange {16511} fehlt: Aufbau von vorn oder ohne Dolch.", "Until you learn {16511}: build from the front or without a dagger.") },    -- Finsterer Stoß / Sinister Strike
        -- Situativ -------------------------------------------------------------------------------------------------
        { id = 3408, kind = "situational", when = "manual",
          text = T("Gegen flüchtende Gegner statt eines Schadensgifts.", "Against fleeing enemies instead of a damage poison.") },    -- Verkrüppelndes Gift / Crippling Poison
        { id = 1856, kind = "situational", when = "manual",
          text = T("Für den Notfall aufheben.", "Save it for emergencies.") },    -- Verschwinden / Vanish
      } },
})
