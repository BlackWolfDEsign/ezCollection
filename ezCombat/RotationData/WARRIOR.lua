local _, ns = ...
local T = ns.RotationData.T

-- Krieger (WARRIOR): Rotationen je Talentbaum und Spielweise für WoW Forever.
-- Quellen, abgerufen am 13.11.2026, nachgeprüft am 20.11.2026 (Paket ezcombat/rotation-recherche, im Browser gelesen) –
-- nur Fakten (Rangfolge, Bedingungen), alle Texte in eigenen Worten:
--   Waffen:  https://www.icy-veins.com/wow-forever/arms-warrior-melee-dps-pve-rotation-cooldowns-abilities  (Stand 04.11.2026)
--            (nachgeprüft 20.11.2026: Rangfolge unverändert; „Reckless Swings“ wie bei Furor, wenn Wut fehlt)
--            https://www.icy-veins.com/wow-forever/arms-warrior-leveling
--            https://www.wowhead.com/forever/guide/classes/warrior/arms/rotation-cooldowns-pve-dps          (Stand 04.11.2026)
--   Furor:   https://www.icy-veins.com/wow-forever/fury-warrior-melee-dps-pve-rotation-cooldowns-abilities  (Stand 16.11.2026:
--            „Reckless Swings“ nach Wirbelwind, Blutdurst und Hinrichten; Heldenhafter Stoß ab 65 Wut; Abfangen und
--            Spöttischer Schlag als Werkzeug)
--            https://www.icy-veins.com/wow-forever/fury-warrior-leveling  (Stand 16.11.2026, nachgeprüft 20.11.2026:
--            Verwunden und Überwältigen nur bis Wirbelwind, ab Stufe 34 „Reckless Swings“, nicht zugleich mit Blutrausch)
--            https://www.wowhead.com/forever/guide/classes/warrior/fury/rotation-cooldowns-pve-dps          (Stand 29.10.2026)
--   Schutz:  https://www.icy-veins.com/wow-forever/protection-warrior-tank-pve-rotation-cooldowns-abilities  (Stand 04.11.2026;
--            Erschütternder Schlag und Spöttischer Schlag nur als Werkzeug, nicht in der Rangfolge)
--            https://www.icy-veins.com/wow-forever/protection-warrior-leveling
--            https://www.wowhead.com/forever/guide/classes/warrior/protection/rotation-cooldowns-pve-tank   (Stand 29.10.2026)
-- Hauptquelle ist Icy Veins; wo Wowhead abweicht, steht es im Feld note. Nichts stammt aus einem Addon.
-- Zauber-IDs: Rang 1 aus dem früheren Bestand (RotationData.lua, damals gegen nether.wowhead.com/forever geprüft) und
-- aus den Seiten oben; weitere klassische Rang-1-IDs sind für Forever nicht gegen eine Quelle geprüft und tragen [V]
-- am Namens-Kommentar – ob der Client sie kennt, meldet der Selbsttest (/ez test).
-- Name, Symbol, Ränge, gelernt, Kosten, Zauberzeit, Abklingzeit und Dauer liefert der Client zur Laufzeit; hier
-- stehen nur Zauber-IDs (Rang 1) und Logik. Zahlen sind Schwellen der Logik (Wut, Stapel, Sekunden bis zum Erneuern).
-- Berserkerwut 18499: seit Build 1.60.1.71037 eine dritte Wirkung – Immunität gegen Mechanik 30 (Kopfnuss) neben
-- Mechanik 5 (Furcht) und 14 (laut wago.tools, wowf, SpellEffect; Hotfix vom 13.11.2026 „removes Sap“; den Namen von
-- Mechanik 14 belegt keine geladene Tabelle – SpellMechanic ist nicht geladen). Die Texte nennen Kopfnuss (Name im
-- Client für 6770) seit dem Paket „Daten auf Build 71037“ (22.11.2026) fest statt als {6770}: jede {ID} im Text zählt
-- als Zauber der Rotation (RotationData.lua, TextIDs), und die wago-Prüfung meldet einen Zauber, den die
-- Client-Tabellen einer anderen Klasse zuordnen, rot – 6770 ist laut Zauberfamilie 8 ein Schurkenzauber.
--
-- Bauart (gilt für alle sechs Rotationen):
--   * Die Haltung für den Pull steht unter „Vor dem Kampf“ (nur wenn schon eine zweite Haltung gelernt ist – vorher
--     gibt es nichts zu wechseln); der Wechsel in die Kampf-Haltung des Baums ist ein Schritt im Kampf.
--   * Der kurze Angriffskraft-Ruf steht zweimal: vor dem Kampf (nur mit Wut) und als Schritt im Kampf.
--   * Was keinen globalen Cooldown hat oder den nächsten Schlag ersetzt, läuft nebenher (side) und leuchtet nur.
--   * Wut-Vorhalt: Der niedrigere Schritt trägt eine Wut-Schwelle (need.rage) – „kurz vor Ende der Abklingzeit“
--     kann das Format nicht.
--   * Blutung zum Ablauf erneuern (refresh = "missing", mit Vorlauf); nicht mehr, sobald das Ziel in der Hinrichtungsphase
--     ist (need.unusable) – Annahme als Näherung für „stirbt gleich“.
--   * Rüstungs-Stapel zählen von jedem Krieger (mine = false).
-- [V] = Annahme oder ID nicht im Spiel bestätigt (/ez test meldet unbekannte IDs).
-- Bedarf:
--   * „Tollkühne Schwünge“ (Reckless Swings, Forever-Talent; Furor, Waffen, Furor Leveln): 1329555 ist Talent und aktive Fähigkeit laut
--     Client-Tabellen (wowf 1.60.1.70938: SpellCooldowns 15 s und globale Abklingzeit – StartRecoveryTime 1000, darum
--     kein Schritt nebenher; SpellPower 25 % Leben; SpellAuraOptions 4 Aufladungen; ezTalent/Computed.lua Reihe 4,
--     Spalte 2). 1329554 gleichen Namens ist der ausgelöste Wut-Effekt (SpellEffect: Kraft geben, Wut, 5 je Schlag).
--     Platz nach Wirbelwind, Blutdurst, Hinrichten und Siegesrausch (Icy Veins, Stand 16.11.2026; Siegesrausch heilt
--     nach einem Kill, Leben ausgeben kommt danach). „Bis 70 Wut“ ist eine Annahme wie bei Blutrausch; im Kampf ist die
--     Wut gesperrt und die Spanne aus Blizzards Nutzbarkeit belegt „höchstens 70“ meist nicht – dann steht der Schritt
--     unter „übersprungen“, vorgeschlagen wird er, wenn ein Zauber bis 70 Wut „zu wenig Wut“ meldet. Vorher „ID nicht
--     ermittelt“. Waffen: nach Zerschmettern und Siegesrausch (Icy Veins wie bei Furor, nachgeprüft 20.11.2026). Furor (Leveln): ab
--     Stufe 34 hinter Blutdurst, „nicht zugleich mit Blutrausch“ (Stand 16.11.2026). Die Wut-Grenze steht als Feld guess.
--   * Angriffskraft (Furor: Reihenfolge in der Hinrichtungsphase) ist im Kampf gesperrt – steht als Text in note;
--     der Nutzer kann den Schritt im Reiter verschieben.
--   * Talent „Vorhut“ (Sturmangriff aus der Verteidigungshaltung): ID nicht ermittelt; der Schritt hängt an „nutzbar“.

local ELITE = { "elite", "rareelite", "worldboss" }

ns.RotationData.Add("WARRIOR", {
    -----------------------------------------------------------------------------------------------------------------
    -- Waffen, Höchststufe
    -----------------------------------------------------------------------------------------------------------------
    { key = "arms", tree = 1, name = T("Waffen", "Arms"),
      source = "https://www.icy-veins.com/wow-forever/arms-warrior-melee-dps-pve-rotation-cooldowns-abilities",
      sources = { "https://www.wowhead.com/forever/guide/classes/warrior/arms/rotation-cooldowns-pve-dps" },
      pick = { leveling = false },
      how = T("Zweihandwaffe in {2457}. {772} liegt immer und wird zum Ablauf erneuert: Nur an einem blutenden Ziel schalten deine Treffer {7384} zusätzlich frei. Danach zählt {12294}, sobald er bereit ist – behalte Wut dafür übrig. {5308} kommt erst hinter beiden, {1240193} füllt im Stand. Was an Wut übrig bleibt, geht in {1715} und {78}.",
              "Two-hander in {2457}. Keep {772} up and renew it as it ends: only on a bleeding target do your hits unlock extra {7384}. Next comes {12294} whenever it is ready – keep rage in reserve for it. {5308} ranks below both, {1240193} fills while you stand still. Leftover rage goes into {1715} and {78}."),
      note = T("Gegnerzahl, Lebenszeit des Ziels und Blutungsimmunität sieht ezCombat nicht: Flächenschritte nur im Flächenmodus, {7386} nur eingeschaltet. Wowhead nennt {78} ab 40 Wut und nie in der Hinrichtungsphase.",
               "ezCombat can't see enemy count, time to live or bleed immunity: AoE steps need AoE mode, {7386} only when turned on. Wowhead uses {78} from 40 rage and never in the kill phase."),
      steps = {
        -- Vor dem Kampf
        { id = 2457, kind = "prepare", when = "form", need = { known = 71 },
          text = T("Deine Haltung; vor dem Kampf einnehmen.", "Your stance; take it before combat.") },    -- Kampfhaltung / Battle Stance
        { id = 6673, kind = "longbuff", buff = "battleShout", when = "buff",
          text = T("Vor dem Angriff auffrischen, wenn Wut da ist.", "Refresh before you attack when you have rage.") },    -- Schlachtruf / Battle Shout
        -- Eröffnung
        { id = 100, kind = "opener", when = "ready", need = { combat = false, inrange = 100 },
          text = T("Kampf damit beginnen: bringt Wut.", "Start the fight with it: grants rage.") },    -- Sturmangriff / Charge
        -- Nebenher und Abklingzeiten
        { id = 2687, kind = "resource", when = "ready", side = true, need = { rage = { max = 70 } },
          guess = T("Die Wut-Grenze ist geschätzt; die Quelle nennt keine Zahl.", "The rage limit is estimated; the source gives no number."),
          text = T("Wenn Platz für Wut ist; kostet Leben.", "When you have room for rage; costs health.") },    -- Blutrausch / Bloodrage
        { id = 1719, kind = "cooldown", burst = true, when = "ready", optional = true, need = { combat = true },
          text = T("Für Schadensphasen aufheben; braucht {2458}.", "Save for damage phases; needs {2458}.") },    -- Tollkühnheit / Recklessness
        -- Mehrere Gegner (Flächenmodus)
        { id = 12292, kind = "aoe", when = "ready",
          text = T("Ab zwei Gegnern: Wut ansparen, dann zünden.", "Two or more enemies: pool rage, then use it.") },    -- Weitreichende Stöße / Sweeping Strikes
        { id = 1680, kind = "aoe", when = "ready",
          text = T("Ab drei Gegnern; nur in {2458}.", "Three or more enemies; only in {2458}.") },    -- Wirbelwind / Whirlwind
        -- Im Kampf (Reihenfolge = Rang)
        { id = 6673, kind = "maintain", when = "buff",
          text = T("Halten; im Kampf nur, wenn er fehlt oder ausläuft.", "Keep it up; in combat only when missing or ending.") },    -- Schlachtruf / Battle Shout
        { id = 1310222, kind = "priority", when = "ready", need = { enemy = { type = { "giant", "dragonkin" } } },
          text = T("Gegen Riesen und Drachkin zuerst.", "Top priority against giants and dragonkin.") },    -- Aufspießender Stoß / Spearing Strike
        { id = 772, kind = "maintain", when = "dot", refresh = "missing", need = { unusable = 5308 },
          guess = T("„Stirbt gleich“ ist geschätzt: sobald das Ziel unter 20 % ist.", "“About to die” is estimated: once the target is below 20%."),
          text = T("Fehlt: setzen. Zum Ablauf erneuern.", "Missing: apply. Renew it as it ends.") },    -- Verwunden / Rend
        { id = 7386, kind = "maintain", when = "dot", stacks = 5, mine = false, refresh = 5, optional = true,
          guess = T("Erneuern 5 Sek. vor Ablauf ist geschätzt.", "Refreshing 5 sec before it ends is estimated."),
          text = T("Nur wenn du zuständig bist: 5 Stapel halten.", "Only if it's your job: keep 5 stacks up.") },    -- Rüstung zerreißen / Sunder Armor
        { id = 7384, kind = "priority", when = "reactive",
          text = T("Sobald freigeschaltet, bevor das Fenster endet.", "As soon as it unlocks, before the window ends.") },    -- Überwältigen / Overpower
        { id = 12294, kind = "priority", when = "ready",
          text = T("Sobald bereit; Wut dafür zurückhalten.", "Whenever ready; hold rage back for it.") },    -- Tödlicher Stoß / Mortal Strike
        { id = 5308, kind = "phase", when = "reactive",
          text = T("Ziel unter 20 %: erst nach den beiden darüber.", "Target below 20%: only after the two above.") },    -- Hinrichten / Execute
        { id = 1240193, kind = "priority", when = "ready", need = { moving = false, rage = { min = 45 } },
          guess = T("Die Wut-Schwelle ist geschätzt: Wut für {12294} soll bleiben.", "The rage threshold is estimated: rage for {12294} should remain."),
          text = T("Im Stand, wenn danach Wut für {12294} bleibt.", "Standing still, if rage for {12294} remains.") },    -- Zerschmettern / Slam
        { id = 402927, kind = "priority", when = "reactive",
          text = T("Nach einem Kill, bevor es verfällt; heilt dich.", "After a kill, before it expires; heals you.") },    -- Siegesrausch / Victory Rush
        { id = 1329555, kind = "resource", when = "ready", need = { combat = true, rage = { max = 70 } },
          guess = T("Die Wut-Grenze ist geschätzt; die Quelle nennt keine Zahl.", "The rage limit is estimated; the source gives no number."),
          text = T("Wenn dir Wut fehlt, du Leben übrig hast und weiter zuschlägst; kostet Leben.", "When you need rage, can spare health and keep attacking; costs health.") },    -- Tollkühne Schwünge / Reckless Swings
        { id = 1310222, key = "spear:rage", kind = "priority", when = "ready", need = { rage = { min = 80 } },
          guess = T("„Kurz vor der Wutgrenze“ ist als Zahl geschätzt.", "“Close to the rage cap” is estimated as a number."),
          text = T("Sonst nur, bevor die Wut überläuft.", "Otherwise only before rage overflows.") },    -- Aufspießender Stoß / Spearing Strike
        { id = 1715, kind = "filler", when = "rage", min = 60,
          guess = T("Die Wut-Schwelle ist geschätzt; die Quelle sagt nur „übrige Wut“.", "The rage threshold is estimated; the source only says “spare rage”."),
          text = T("Restwut; löst Treffer-Effekte aus.", "Leftover rage; fishes for on-hit effects.") },    -- Kniesehne / Hamstring
        { id = 78, kind = "filler", when = "rage", min = 40, side = true, need = { queued = false, unusable = 5308 },
          text = T("Nur Überschuss; nicht in der Hinrichtungsphase.", "Surplus rage only; not during the kill phase.") },    -- Heldenhafter Stoß / Heroic Strike
        { id = 845, kind = "aoe", when = "rage", min = 40, side = true, need = { queued = false },
          text = T("Ab zwei Gegnern statt {78}.", "With two or more enemies instead of {78}.") },    -- Spalten / Cleave
        -- Situativ
        { id = 6343, kind = "situational", when = "manual",
          text = T("Nach Lage: wenn die Gruppe ihn braucht und kein anderer ihn setzt.", "As needed: when the group needs it and no one else applies it.") },    -- Donnerknall / Thunder Clap
        { id = 1160, kind = "situational", when = "manual",
          text = T("Nach Lage: wenn die Gruppe ihn braucht und kein anderer ihn setzt.", "As needed: when the group needs it and no one else applies it.") },    -- Demoralisierender Ruf / Demoralizing Shout
        { id = 18499, kind = "situational", when = "manual",
          text = T("Für Furcht-Effekte und Kopfnuss aufheben.", "Save it for fear effects and Sap.") },    -- Berserkerwut / Berserker Rage
        { id = 6552, kind = "situational", when = "manual",
          text = T("Unterbricht einen Zauber; braucht {2458}.", "Interrupts a cast; needs {2458}.") },    -- Zuschlagen / Pummel
      } },

    -----------------------------------------------------------------------------------------------------------------
    -- Furor, Höchststufe
    -----------------------------------------------------------------------------------------------------------------
    { key = "fury", tree = 2, name = T("Furor", "Fury"),
      source = "https://www.icy-veins.com/wow-forever/fury-warrior-melee-dps-pve-rotation-cooldowns-abilities",
      sources = { "https://www.wowhead.com/forever/guide/classes/warrior/fury/rotation-cooldowns-pve-dps" },
      pick = { leveling = false },
      how = T("Zwei Waffen. Der Pull läuft über {2457} und {100}, danach wechselst du in {2458}. Dort geht {1680} allem vor, auch in der Hinrichtungsphase; dann {23881} – halte Wut für beide zurück. {5308} steht dazwischen und meldet sich nur bei einem fast toten Ziel. {7384} lohnt den Haltungswechsel nur bei wenig Wut. Überschuss geht in {1715} und {78}.",
              "Dual wield. Pull through {2457} and {100}, then switch to {2458}. There {1680} beats everything, even in the kill phase; then {23881} – hold rage back for both. {5308} sits between them and only shows on a nearly dead target. {7384} is worth the stance swap only at low rage. Surplus goes into {1715} and {78}."),
      note = T("Wowhead ordnet {5308}, {23881}, {1680}. Icy Veins: mit sehr hoher Angriffskraft {23881} vor {5308} – die ist im Kampf nicht lesbar; verschiebe den Schritt selbst. {7384} ist in {2458} nicht zu sehen. {1329555} kostet Leben, das ezCombat im Kampf nicht sieht – schalte den Schritt aus, wenn dich niemand heilt.",
               "Wowhead orders {5308}, {23881}, {1680}. Icy Veins: with very high attack power {23881} before {5308} – it can't be read in combat; move the step yourself. {7384} can't be seen in {2458}. {1329555} costs health, which ezCombat can't see in combat – turn the step off if nobody heals you."),
      steps = {
        -- Vor dem Kampf
        { id = 2457, kind = "prepare", when = "form", need = { known = 71 },
          text = T("Zum Angriff mit {100}; im Kampf wechselst du.", "To start the fight with {100}; you swap in combat.") },    -- Kampfhaltung / Battle Stance
        { id = 6673, kind = "longbuff", buff = "battleShout", when = "buff",
          text = T("Vor dem Angriff auffrischen, wenn Wut da ist.", "Refresh before you attack when you have rage.") },    -- Schlachtruf / Battle Shout
        -- Eröffnung
        { id = 100, kind = "opener", when = "ready", need = { combat = false, inrange = 100 },
          text = T("Kampf damit beginnen: bringt Wut.", "Start the fight with it: grants rage.") },    -- Sturmangriff / Charge
        -- Nebenher und Abklingzeiten
        { id = 2687, kind = "resource", when = "ready", side = true, need = { rage = { max = 70 } },
          guess = T("Die Wut-Grenze ist geschätzt; die Quelle nennt keine Zahl.", "The rage limit is estimated; the source gives no number."),
          text = T("Wenn Platz für Wut ist; kostet Leben.", "When you have room for rage; costs health.") },    -- Blutrausch / Bloodrage
        { id = 12328, kind = "cooldown", burst = true, when = "ready", need = { combat = true },
          text = T("Wenn du fast die ganze Dauer am Ziel bleibst.", "When you can stay on target for most of it.") },    -- Todeswunsch / Death Wish
        { id = 1719, kind = "cooldown", burst = true, when = "ready", optional = true, need = { combat = true },
          text = T("Für starke Phasen, zusammen mit {12328}.", "For big damage phases, together with {12328}.") },    -- Tollkühnheit / Recklessness
        -- Im Kampf (Reihenfolge = Rang)
        { id = 6673, kind = "maintain", when = "buff",
          text = T("Halten; im Kampf nur, wenn er fehlt oder ausläuft.", "Keep it up; in combat only when missing or ending.") },    -- Schlachtruf / Battle Shout
        { id = 7386, kind = "maintain", when = "dot", stacks = 5, mine = false, refresh = 5, optional = true,
          guess = T("Erneuern 5 Sek. vor Ablauf ist geschätzt.", "Refreshing 5 sec before it ends is estimated."),
          text = T("Nur wenn zuständig: gleich zu Beginn 5 Stapel.", "Only if it's your job: 5 stacks right away.") },    -- Rüstung zerreißen / Sunder Armor
        { id = 7384, kind = "priority", when = "reactive", need = { rage = { max = 25 } },
          text = T("Nur bei wenig Wut den Haltungswechsel wert.", "Worth the stance swap only at low rage.") },    -- Überwältigen / Overpower
        { id = 1310222, kind = "priority", when = "ready", need = { enemy = { type = { "giant", "dragonkin" } } },
          text = T("Gegen Riesen und Drachkin, solange du in {2457} bist.", "Vs giants and dragonkin while still in {2457}.") },    -- Aufspießender Stoß / Spearing Strike
        { id = 772, kind = "maintain", when = "dot", refresh = "missing", need = { unusable = 5308 },
          guess = T("„Stirbt gleich“ ist geschätzt: sobald das Ziel unter 20 % ist.", "“About to die” is estimated: once the target is below 20%."),
          text = T("Solange du in {2457} bist; auslaufen lassen.", "While you are in {2457}; let it run out.") },    -- Verwunden / Rend
        { id = 2458, kind = "priority", when = "form", need = { combat = true },
          text = T("Im Kampf deine Haltung; Wechsel kostet Wut.", "Your stance in combat; swapping costs rage.") },    -- Berserkerhaltung / Berserker Stance
        { id = 1680, kind = "priority", when = "ready",
          text = T("Sobald bereit – auch in der Hinrichtungsphase.", "Whenever ready – even in the kill phase.") },    -- Wirbelwind / Whirlwind
        { id = 5308, kind = "phase", when = "reactive",
          text = T("Ziel unter 20 %: nach {1680}.", "Target below 20%: after {1680}.") },    -- Hinrichten / Execute
        { id = 23881, kind = "priority", when = "ready",
          text = T("Sobald bereit; verzögere {1680} nicht.", "Whenever ready; don't delay {1680}.") },    -- Blutdurst / Bloodthirst
        { id = 402927, kind = "priority", when = "reactive",
          text = T("Nach einem Kill, bevor es verfällt; heilt dich.", "After a kill, before it expires; heals you.") },    -- Siegesrausch / Victory Rush
        { id = 1329555, kind = "resource", when = "ready", need = { combat = true, rage = { max = 70 } },
          guess = T("Die Wut-Grenze ist geschätzt; die Quelle nennt keine Zahl.", "The rage limit is estimated; the source gives no number."),
          text = T("Wenn dir Wut fehlt, du Leben übrig hast und weiter zuschlägst; kostet Leben.", "When you need rage, can spare health and keep attacking; costs health.") },    -- Tollkühne Schwünge / Reckless Swings
        { id = 1715, kind = "filler", when = "rage", min = 85,
          text = T("Ab 85 Wut; löst Treffer-Effekte aus.", "From 85 rage; fishes for on-hit effects.") },    -- Kniesehne / Hamstring
        { id = 78, kind = "filler", when = "rage", min = 65, side = true, need = { queued = false },
          text = T("Ab 65 Wut, nur Überschuss.", "From 65 rage, surplus only.") },    -- Heldenhafter Stoß / Heroic Strike
        -- Mehrere Gegner (Flächenmodus)
        { id = 845, kind = "aoe", when = "rage", min = 65, side = true, need = { queued = false },
          text = T("Ab zwei Gegnern statt {78}.", "With two or more enemies instead of {78}.") },    -- Spalten / Cleave
        -- Situativ
        { id = 6343, kind = "situational", when = "manual",
          text = T("Nur wenn nötig und niemand sonst; braucht {2457}.", "Only when needed and no one else applies it; needs {2457}.") },    -- Donnerknall / Thunder Clap
        { id = 1160, kind = "situational", when = "manual",
          text = T("Nach Lage: wenn die Gruppe ihn braucht und kein anderer ihn setzt.", "As needed: when the group needs it and no one else applies it.") },    -- Demoralisierender Ruf / Demoralizing Shout
        { id = 18499, kind = "situational", when = "manual",
          text = T("Für Furcht-Effekte und Kopfnuss aufheben.", "Save it for fear effects and Sap.") },    -- Berserkerwut / Berserker Rage
        { id = 6552, kind = "situational", when = "manual",
          text = T("Unterbricht einen Zauber.", "Interrupts a cast.") },    -- Zuschlagen / Pummel
        { id = 20252, kind = "situational", when = "manual",
          text = T("Im Kampf zum Gegner und kurz betäuben; braucht {2458}, kostet Wut.", "Reach an enemy in combat and stun it briefly; needs {2458}, costs rage.") },    -- Abfangen / Intercept
        { id = 694, kind = "situational", when = "manual",
          text = T("Zwingt einen Gegner kurz auf dich; braucht {2457}.", "Forces an enemy onto you briefly; needs {2457}.") },    -- Spöttischer Schlag / Mocking Blow
      } },

    -----------------------------------------------------------------------------------------------------------------
    -- Schutz, Höchststufe
    -----------------------------------------------------------------------------------------------------------------
    { key = "protection", tree = 3, name = T("Schutz", "Protection"),
      source = "https://www.icy-veins.com/wow-forever/protection-warrior-tank-pve-rotation-cooldowns-abilities",
      sources = { "https://www.wowhead.com/forever/guide/classes/warrior/protection/rotation-cooldowns-pve-tank" },
      pick = { leveling = false },
      how = T("Schild und {71}. {2565} läuft neben allem her, solange dich Nahkämpfer treffen – er schaltet {6572} frei. {23922} geht vor {6572}; nach dem ersten Treffer baust du zügig 5 Stapel {7386} auf. {6343} kommt, wenn er bereit ist, {772} nur wenn die Blutung fehlt. Dazwischen füllt {7386} weiter, weil jede Anwendung Bedrohung bringt; {78} nur mit Restwut.",
              "Shield and {71}. {2565} runs alongside everything while melee enemies hit you – it unlocks {6572}. {23922} ranks above {6572}; after the first hit you quickly build 5 stacks of {7386}. {6343} whenever it is ready, {772} only when the bleed is missing. In between {7386} keeps filling, as every use adds threat; {78} with leftover rage only."),
      note = T("Wowhead setzt {6572} vor {23922} und hält {6343} nur als Debuff. Bedrohung, Zauberer als Ziel und eingehenden Schaden sieht ezCombat nicht: {355} und Notfallknöpfe stehen nur in der Liste.",
               "Wowhead puts {6572} above {23922} and keeps {6343} up as a debuff only. ezCombat can't see threat, caster targets or incoming damage: taunts and emergency buttons are list only."),
      steps = {
        -- Vor dem Kampf
        { id = 71, kind = "prepare", when = "form",
          text = T("Deine Haltung zum Tanken.", "Your stance for tanking.") },    -- Verteidigungshaltung / Defensive Stance
        { id = 6673, kind = "longbuff", buff = "battleShout", when = "buff",
          text = T("Vor dem Angriff auffrischen: spart später Zeit.", "Refresh before you attack: saves time later.") },    -- Schlachtruf / Battle Shout
        -- Eröffnung
        { id = 100, kind = "opener", when = "ready", need = { combat = false, inrange = 100 },
          text = T("Zum Angriff, sofern in deiner Haltung nutzbar.", "Start the fight with it if usable in your stance.") },    -- Sturmangriff / Charge
        -- Nebenher
        { id = 71, kind = "priority", when = "form", need = { combat = true },
          text = T("Nach dem ersten Angriff sofort zurück in diese Haltung.", "Right after your first attack, back into this stance.") },    -- Verteidigungshaltung / Defensive Stance
        { id = 2565, kind = "priority", when = "ready", side = true, need = { combat = true, usable = 2565 },
          text = T("Nebenher, solange Nahkämpfer auf dich einschlagen.", "Alongside your other attacks, as long as melee attackers are on you.") },    -- Schildblock / Shield Block
        { id = 2687, kind = "resource", when = "ready", side = true, need = { rage = { max = 70 } },
          guess = T("Die Wut-Grenze ist geschätzt; die Quelle nennt keine Zahl.", "The rage limit is estimated; the source gives no number."),
          text = T("Zum Angriff und wenn Platz für Wut ist.", "To start the fight and when you have room for rage.") },    -- Blutrausch / Bloodrage
        -- Mehrere Gegner (Flächenmodus)
        { id = 6343, kind = "aoe", when = "ready",
          text = T("Mehrere Gegner: zuerst, wenn sie ankommen.", "Several enemies: first, as they arrive.") },    -- Donnerknall / Thunder Clap
        -- Im Kampf (Reihenfolge = Rang)
        { id = 23922, kind = "priority", when = "ready",
          text = T("Sobald bereit; Wut dafür zurückhalten.", "Whenever ready; hold rage back for it.") },    -- Schildschlag / Shield Slam
        { id = 23881, kind = "priority", when = "ready",
          text = T("Falls geskillt: dein Hauptangriff neben {23922}.", "If talented: your main strike next to {23922}.") },    -- Blutdurst / Bloodthirst
        { id = 6572, kind = "priority", when = "reactive",
          text = T("Sobald Blocken oder Ausweichen sie freischaltet.", "As soon as a block or dodge unlocks it.") },    -- Rache / Revenge
        { id = 7386, kind = "maintain", when = "dot", stacks = 5, mine = false, refresh = 5,
          guess = T("Erneuern 5 Sek. vor Ablauf ist geschätzt.", "Refreshing 5 sec before it ends is estimated."),
          text = T("Zügig 5 Stapel aufbauen, vor Ablauf erneuern.", "Build 5 stacks quickly, renew before they end.") },    -- Rüstung zerreißen / Sunder Armor
        { id = 6343, kind = "priority", when = "ready",
          text = T("Sobald bereit: Schaden und langsamere Angriffe.", "Whenever ready: damage and slower attacks.") },    -- Donnerknall / Thunder Clap
        { id = 6673, kind = "maintain", when = "buff",
          text = T("Halten; im Kampf nur, wenn er fehlt oder ausläuft.", "Keep it up; in combat only when missing or ending.") },    -- Schlachtruf / Battle Shout
        { id = 1160, kind = "maintain", when = "dot", mine = false, refresh = "missing", optional = true,
          text = T("Nach Lage: wenn er zählt und kein anderer ihn setzt.", "As needed: when it counts and no one else applies it.") },    -- Demoralisierender Ruf / Demoralizing Shout
        { id = 772, kind = "maintain", when = "dot", refresh = "missing", need = { unusable = 5308 },
          guess = T("„Stirbt gleich“ ist geschätzt: sobald das Ziel unter 20 % ist.", "“About to die” is estimated: once the target is below 20%."),
          text = T("Nur wenn die Blutung fehlt; auslaufen lassen.", "Only when the bleed is missing; let it run out.") },    -- Verwunden / Rend
        { id = 7386, key = "filler:sunder", kind = "filler", when = "filler",
          text = T("Lückenfüller zwischen den Hauptangriffen: Bedrohung.", "Gap filler between your main strikes: threat.") },    -- Rüstung zerreißen / Sunder Armor
        { id = 78, kind = "filler", when = "rage", min = 30, side = true, need = { queued = false },
          text = T("Ab 30 Wut; Wut für {2565} behalten.", "From 30 rage; keep rage for {2565}.") },    -- Heldenhafter Stoß / Heroic Strike
        { id = 845, kind = "aoe", when = "rage", min = 30, side = true, need = { queued = false },
          text = T("Ab zwei Gegnern statt {78}.", "With two or more enemies instead of {78}.") },    -- Spalten / Cleave
        -- Situativ
        { id = 5308, kind = "situational", when = "manual",
          text = T("Verlangt einen Haltungswechsel: nur wenn sicher.", "Needs a stance swap: only when it is safe.") },    -- Hinrichten / Execute
        { id = 402927, kind = "situational", when = "manual",
          text = T("Nach einem Kill, wenn dir Leben fehlt.", "After a kill when you are missing health.") },    -- Siegesrausch / Victory Rush
        { id = 871, kind = "situational", when = "manual",
          text = T("Notfall: vor dem großen Treffer drücken.", "Emergency: press before the big hit.") },    -- Schildwall / Shield Wall
        { id = 12975, kind = "situational", when = "manual",
          text = T("Notfall: vor dem großen Treffer drücken.", "Emergency: press before the big hit.") },    -- Letztes Gefecht / Last Stand
        { id = 355, kind = "situational", when = "manual",
          text = T("Holt einen Gegner zurück; ezCombat sieht das nicht.", "Pulls an enemy back; ezCombat can't see that.") },    -- Spott / Taunt
        { id = 72, kind = "situational", when = "manual",
          text = T("Unterbricht einen Zauber.", "Interrupts a cast.") },    -- Schildhieb / Shield Bash
        { id = 12809, kind = "situational", when = "manual",
          text = T("Betäubt einen gefährlichen Gegner oder stoppt einen Zauber, wenn {72} nicht bereit ist.", "Stuns a dangerous enemy or stops a cast when {72} isn't ready.") },    -- Erschütternder Schlag / Concussion Blow
        { id = 694, kind = "situational", when = "manual",
          text = T("Wenn {355} nicht bereit ist; braucht {2457} und hält nur kurz.", "When {355} isn't ready; needs {2457} and only lasts briefly.") },    -- Spöttischer Schlag / Mocking Blow
      } },

    -----------------------------------------------------------------------------------------------------------------
    -- Waffen, Leveln
    -----------------------------------------------------------------------------------------------------------------
    { key = "arms_level", tree = 1, name = T("Waffen (Leveln)", "Arms (levelling)"),
      source = "https://www.icy-veins.com/wow-forever/arms-warrior-leveling",
      sources = { "https://www.icy-veins.com/wow-forever/arms-warrior-melee-dps-pve-rotation-cooldowns-abilities" },
      pick = { leveling = true },
      how = T("Jeder Kampf beginnt mit {100}, dann kommt {772}: Die Blutung macht aus Treffern später zusätzliche {7384}. Danach zählt {7384}, sobald es geht, dann {12294}; {1240193} füllt im Stand. Wut ist knapp: {78} nur bei Überschuss, {5308} nur gegen starke Gegner, damit Wut für den nächsten Kampf bleibt.",
              "Every fight starts with {100}, then {772}: later the bleed turns hits into extra {7384}. After that use {7384} whenever you can, then {12294}; {1240193} fills while you stand still. Rage is scarce: {78} with surplus only, {5308} only against strong enemies so rage is left for the next fight."),
      note = T("Zwei Gegner: Wut am ersten ansparen, dann {12292} und {845} – ezCombat zählt keine Gegner, schalte dafür den Flächenmodus ein. {7386} nur gegen Elite und Bosse.",
               "Two enemies: pool rage on the first, then {12292} and {845} – ezCombat can't count enemies, turn on AoE mode for that. {7386} against elites and bosses only."),
      steps = {
        -- Vor dem Kampf
        { id = 2457, kind = "prepare", when = "form", need = { known = 71 },
          text = T("Deine Haltung; vor dem Kampf einnehmen.", "Your stance; take it before combat.") },    -- Kampfhaltung / Battle Stance
        { id = 6673, kind = "longbuff", buff = "battleShout", when = "buff",
          text = T("Zwischen den Kämpfen mit Restwut auffrischen.", "Refresh between fights with leftover rage.") },    -- Schlachtruf / Battle Shout
        -- Eröffnung
        { id = 100, kind = "opener", when = "ready", need = { combat = false, inrange = 100 },
          text = T("Kampf damit beginnen: bringt Wut.", "Start the fight with it: grants rage.") },    -- Sturmangriff / Charge
        -- Nebenher
        { id = 2687, kind = "resource", when = "ready", side = true, need = { rage = { max = 70 } },
          guess = T("Die Wut-Grenze ist geschätzt; die Quelle nennt keine Zahl.", "The rage limit is estimated; the source gives no number."),
          text = T("Nach Bedarf, auch zwischen Kämpfen; kostet Leben.", "As needed, also between fights; costs health.") },    -- Blutrausch / Bloodrage
        -- Mehrere Gegner (Flächenmodus)
        { id = 12292, kind = "aoe", when = "ready",
          text = T("Zwei Gegner: Wut ansparen, dann zünden.", "Two enemies: pool rage, then use it.") },    -- Weitreichende Stöße / Sweeping Strikes
        { id = 6343, kind = "aoe", when = "ready", need = { unknown = 1680 },
          text = T("Dein Flächenangriff, bis du {1680} lernst.", "Your attack on several enemies until you learn {1680}.") },    -- Donnerknall / Thunder Clap
        { id = 1680, kind = "aoe", when = "ready", need = { grouped = true },
          text = T("Ab vier Gegnern in der Gruppe; nur in {2458}.", "Four or more enemies in a group; only in {2458}.") },    -- Wirbelwind / Whirlwind
        -- Im Kampf (Reihenfolge = Rang)
        { id = 6673, kind = "maintain", when = "buff",
          text = T("Halten; im Kampf nur, wenn er fehlt oder ausläuft.", "Keep it up; in combat only when missing or ending.") },    -- Schlachtruf / Battle Shout
        { id = 1310222, kind = "priority", when = "ready", need = { enemy = { type = { "giant", "dragonkin" } } },
          text = T("Gegen Riesen und Drachkin zuerst.", "Top priority against giants and dragonkin.") },    -- Aufspießender Stoß / Spearing Strike
        { id = 772, kind = "maintain", when = "dot", refresh = "missing", need = { unusable = 5308 },
          guess = T("„Stirbt gleich“ ist geschätzt: sobald das Ziel unter 20 % ist.", "“About to die” is estimated: once the target is below 20%."),
          text = T("Früh setzen; zum Ablauf erneuern.", "Apply early; renew it as it ends.") },    -- Verwunden / Rend
        { id = 7386, kind = "maintain", when = "dot", stacks = 5, mine = false, refresh = 5,
          need = { enemy = { rank = ELITE } },
          guess = T("Erneuern 5 Sek. vor Ablauf ist geschätzt.", "Refreshing 5 sec before it ends is estimated."),
          text = T("Nur gegen Elite und Bosse: 5 Stapel.", "Against elites and bosses only: 5 stacks.") },    -- Rüstung zerreißen / Sunder Armor
        { id = 7384, kind = "priority", when = "reactive",
          text = T("Sobald freigeschaltet, bevor das Fenster endet.", "As soon as it unlocks, before the window ends.") },    -- Überwältigen / Overpower
        { id = 402927, kind = "priority", when = "reactive",
          text = T("Nach einem Kill, bevor es verfällt; heilt dich.", "After a kill, before it expires; heals you.") },    -- Siegesrausch / Victory Rush
        { id = 12294, kind = "priority", when = "ready",
          text = T("Sobald bereit – hinter Blutung und {7384}.", "Whenever ready – below the bleed and {7384}.") },    -- Tödlicher Stoß / Mortal Strike
        { id = 5308, kind = "phase", when = "reactive", need = { enemy = { rank = ELITE } },
          text = T("Nur gegen starke Gegner; sonst Wut sparen.", "Strong enemies only; otherwise save the rage.") },    -- Hinrichten / Execute
        { id = 1240193, kind = "priority", when = "ready", need = { moving = false },
          text = T("Füllt, wenn du stehen bleiben kannst.", "Fills when you can stand still.") },    -- Zerschmettern / Slam
        { id = 1310222, key = "spear:rage", kind = "priority", when = "ready", need = { rage = { min = 80 } },
          guess = T("„Kurz vor der Wutgrenze“ ist als Zahl geschätzt.", "“Close to the rage cap” is estimated as a number."),
          text = T("Sonst nur, bevor die Wut überläuft.", "Otherwise only before rage overflows.") },    -- Aufspießender Stoß / Spearing Strike
        { id = 78, kind = "filler", when = "rage", min = 40, need = { queued = false },
          text = T("Nur mit überschüssiger Wut.", "With surplus rage only.") },    -- Heldenhafter Stoß / Heroic Strike
        { id = 845, kind = "aoe", when = "rage", min = 40, side = true, need = { queued = false },
          text = T("Zweiter Gegner in Reichweite: statt {78}.", "Second enemy in reach: instead of {78}.") },    -- Spalten / Cleave
        -- Situativ
        { id = 1160, kind = "situational", when = "manual",
          text = T("Früh im Kampf gegen harte Nahkämpfer.", "Early in the fight against hard-hitting melee.") },    -- Demoralisierender Ruf / Demoralizing Shout
        { id = 18499, kind = "situational", when = "manual",
          text = T("Vor dem Angriff für Wut; braucht {2458}.", "Before you attack for rage; needs {2458}.") },    -- Berserkerwut / Berserker Rage
        { id = 1719, kind = "situational", when = "manual",
          text = T("Für harte Kämpfe aufheben; braucht {2458}.", "Save for hard fights; needs {2458}.") },    -- Tollkühnheit / Recklessness
      } },

    -----------------------------------------------------------------------------------------------------------------
    -- Furor, Leveln
    -----------------------------------------------------------------------------------------------------------------
    { key = "fury_level", tree = 2, name = T("Furor (Leveln)", "Fury (levelling)"),
      source = "https://www.icy-veins.com/wow-forever/fury-warrior-leveling",
      sources = { "https://www.icy-veins.com/wow-forever/fury-warrior-melee-dps-pve-rotation-cooldowns-abilities" },
      pick = { leveling = true },
      how = T("Bis du {2458} lernst, bleibst du in {2457}: {100}, {772} und {7384} nach einem Ausweichen. Danach wechselst du nach dem Pull in {2458}; {1680} geht dann allem vor, es folgt {23881}. {12328} nutzt du beim Leveln regelmäßig statt ihn aufzuheben. {5308} und {78} kommen selten – die Wut wird für den nächsten Gegner gebraucht.",
              "Until you learn {2458} you stay in {2457}: {100}, {772} and {7384} after a dodge. Later you switch to {2458} after the pull; {1680} then beats everything, followed by {23881}. While levelling use {12328} regularly instead of saving it. {5308} and {78} are rare – you need the rage for the next enemy."),
      note = T("Der Kern des Baums kommt erst mit {2458}; davor ist es die Grundfolge aller Krieger. Flächenschritte nur im Flächenmodus – ezCombat zählt keine Gegner.",
               "The core of this tree only starts with {2458}; before that it is the basic sequence of all warriors. AoE steps need AoE mode – ezCombat can't count enemies."),
      steps = {
        -- Vor dem Kampf
        { id = 2457, kind = "prepare", when = "form", need = { known = 71 },
          text = T("Zum Angriff mit {100}.", "To start the fight with {100}.") },    -- Kampfhaltung / Battle Stance
        { id = 6673, kind = "longbuff", buff = "battleShout", when = "buff",
          text = T("Zwischen den Kämpfen mit Restwut auffrischen.", "Refresh between fights with leftover rage.") },    -- Schlachtruf / Battle Shout
        -- Eröffnung
        { id = 100, kind = "opener", when = "ready", need = { combat = false, inrange = 100 },
          text = T("Kampf damit beginnen: bringt Wut.", "Start the fight with it: grants rage.") },    -- Sturmangriff / Charge
        -- Nebenher und Abklingzeiten
        { id = 2687, kind = "resource", when = "ready", side = true, need = { rage = { max = 70 } },
          guess = T("Die Wut-Grenze ist geschätzt; die Quelle nennt keine Zahl.", "The rage limit is estimated; the source gives no number."),
          text = T("Nach Bedarf, auch zwischen Kämpfen; kostet Leben.", "As needed, also between fights; costs health.") },    -- Blutrausch / Bloodrage
        { id = 12328, kind = "cooldown", burst = true, when = "ready", need = { combat = true },
          text = T("Beim Leveln regelmäßig nutzen, nicht aufheben.", "Use it regularly while levelling, don't save it.") },    -- Todeswunsch / Death Wish
        -- Mehrere Gegner (Flächenmodus)
        { id = 6343, kind = "aoe", when = "ready", need = { unknown = 1680 },
          text = T("Dein Flächenangriff, bis du {1680} lernst.", "Your attack on several enemies until you learn {1680}.") },    -- Donnerknall / Thunder Clap
        -- Im Kampf (Reihenfolge = Rang)
        { id = 6673, kind = "maintain", when = "buff",
          text = T("Halten; im Kampf nur, wenn er fehlt oder ausläuft.", "Keep it up; in combat only when missing or ending.") },    -- Schlachtruf / Battle Shout
        { id = 7384, key = "overpower:early", kind = "priority", when = "reactive", need = { unknown = 2458 },
          text = T("Nach einem Ausweichen des Ziels sofort.", "Right after the target dodges.") },    -- Überwältigen / Overpower
        { id = 7384, kind = "priority", when = "reactive", need = { known = 2458, unknown = 1680, rage = { max = 25 } },
          text = T("Bis {1680} nur bei wenig Wut den Wechsel wert.", "Until {1680} worth the swap only at low rage.") },    -- Überwältigen / Overpower
        { id = 772, kind = "maintain", when = "dot", refresh = "missing", need = { unusable = 5308, unknown = 1680 },
          guess = T("„Stirbt gleich“ ist geschätzt: sobald das Ziel unter 20 % ist.", "“About to die” is estimated: once the target is below 20%."),
          text = T("Bis {1680} da ist, in {2457}; auslaufen lassen.", "Until you have {1680}, in {2457}; let it run out.") },    -- Verwunden / Rend
        { id = 402927, kind = "priority", when = "reactive",
          text = T("Nach einem Kill, bevor es verfällt; heilt dich.", "After a kill, before it expires; heals you.") },    -- Siegesrausch / Victory Rush
        { id = 2458, kind = "priority", when = "form", need = { combat = true },
          text = T("Sobald gelernt: im Kampf deine Haltung.", "Once learned: your stance in combat.") },    -- Berserkerhaltung / Berserker Stance
        { id = 1680, kind = "priority", when = "ready",
          text = T("Sobald gelernt und bereit: geht allem vor.", "Once learned and ready: beats everything.") },    -- Wirbelwind / Whirlwind
        { id = 5308, kind = "phase", when = "reactive", need = { enemy = { rank = ELITE } },
          text = T("Nur gegen starke Gegner; sonst Wut sparen.", "Strong enemies only; otherwise save the rage.") },    -- Hinrichten / Execute
        { id = 23881, kind = "priority", when = "ready",
          text = T("Sobald bereit; verzögere {1680} nicht.", "Whenever ready; don't delay {1680}.") },    -- Blutdurst / Bloodthirst
        { id = 1329555, kind = "resource", when = "ready", need = { combat = true, rage = { max = 70 } },
          guess = T("Die Wut-Grenze ist geschätzt; die Quelle nennt keine Zahl.", "The rage limit is estimated; the source gives no number."),
          text = T("Wenn Wut fehlt; nicht zugleich mit {2687}.", "When rage is short; not together with {2687}.") },    -- Tollkühne Schwünge / Reckless Swings
        { id = 78, kind = "filler", when = "rage", min = 65, need = { queued = false },
          text = T("Fast nie: nur bei viel überschüssiger Wut.", "Hardly ever: only with lots of surplus rage.") },    -- Heldenhafter Stoß / Heroic Strike
        { id = 845, kind = "aoe", when = "rage", min = 65, side = true, need = { queued = false },
          text = T("Zweiter Gegner in Reichweite: statt {78}.", "Second enemy in reach: instead of {78}.") },    -- Spalten / Cleave
        -- Situativ
        { id = 1160, kind = "situational", when = "manual",
          text = T("Früh im Kampf gegen harte Nahkämpfer.", "Early in the fight against hard-hitting melee.") },    -- Demoralisierender Ruf / Demoralizing Shout
        { id = 18499, kind = "situational", when = "manual",
          text = T("Vor dem Angriff für Wut oder gegen Furcht und Kopfnuss.", "Before you attack for rage, or against fear and Sap.") },    -- Berserkerwut / Berserker Rage
        { id = 1719, kind = "situational", when = "manual",
          text = T("Für harte Kämpfe aufheben.", "Save it for hard fights.") },    -- Tollkühnheit / Recklessness
      } },

    -----------------------------------------------------------------------------------------------------------------
    -- Schutz, Leveln
    -----------------------------------------------------------------------------------------------------------------
    { key = "protection_level", tree = 3, name = T("Schutz (Leveln)", "Protection (levelling)"),
      source = "https://www.icy-veins.com/wow-forever/protection-warrior-leveling",
      sources = { "https://www.icy-veins.com/wow-forever/protection-warrior-tank-pve-rotation-cooldowns-abilities" },
      pick = { leveling = true },
      how = T("Mit Schild in {71}. {2565} drückst du nebenher, sobald er gelernt ist: Jeder Block schaltet {6572} frei, und das ist beim Leveln dein Hauptangriff. {772} kommt früh auf den Gegner. {7386} lohnt allein nur gegen Elite und Bosse, in der Gruppe immer. Ab {23922} kommt dieser zuerst; nur bei wenig Wut geht {6572} vor.",
              "With a shield in {71}. Press {2565} alongside once you have it: every block unlocks {6572}, your main attack while levelling. {772} goes on the enemy early. Solo, {7386} is only worth it against elites and bosses; in a group always. Once you have {23922}, it comes first; only at low rage does {6572} go ahead."),
      note = T("Vor {71} spielt sich der Baum wie jeder Krieger. {6343} allein nur gegen gefährliche Nahkämpfer – deshalb steht er hier nur bei Elite oder in der Gruppe.",
               "Before {71} this tree plays like any warrior. Solo, {6343} only against dangerous melee enemies – so here it shows only on elites or in a group."),
      steps = {
        -- Vor dem Kampf
        { id = 71, kind = "prepare", when = "form",
          text = T("Deine Haltung, sobald gelernt.", "Your stance once learned.") },    -- Verteidigungshaltung / Defensive Stance
        { id = 6673, kind = "longbuff", buff = "battleShout", when = "buff",
          text = T("Zwischen den Kämpfen mit Restwut auffrischen.", "Refresh between fights with leftover rage.") },    -- Schlachtruf / Battle Shout
        -- Eröffnung
        { id = 100, kind = "opener", when = "ready", need = { combat = false, inrange = 100 },
          text = T("Zum Angriff, sofern in deiner Haltung nutzbar.", "Start the fight with it if usable in your stance.") },    -- Sturmangriff / Charge
        -- Nebenher
        { id = 71, kind = "priority", when = "form", need = { combat = true },
          text = T("Nach dem ersten Angriff sofort zurück in diese Haltung.", "Right after your first attack, back into this stance.") },    -- Verteidigungshaltung / Defensive Stance
        { id = 2565, kind = "priority", when = "ready", side = true, need = { combat = true, usable = 2565 },
          text = T("Nebenher, solange Nahkämpfer auf dich einschlagen.", "Alongside your other attacks, as long as melee attackers are on you.") },    -- Schildblock / Shield Block
        { id = 2687, kind = "resource", when = "ready", side = true, need = { rage = { max = 80 } },
          guess = T("Die Wut-Grenze ist geschätzt („so gut wie immer“).", "The rage limit is estimated (“almost always”)."),
          text = T("Beim Leveln, wann immer er bereit ist.", "While levelling whenever it is ready.") },    -- Blutrausch / Bloodrage
        -- Im Kampf (Reihenfolge = Rang)
        { id = 6673, kind = "maintain", when = "buff",
          text = T("Halten; im Kampf nur, wenn er fehlt oder ausläuft.", "Keep it up; in combat only when missing or ending.") },    -- Schlachtruf / Battle Shout
        { id = 23922, key = "shieldslam:rage", kind = "priority", when = "ready", need = { rage = { min = 40 } },
          guess = T("„Genug Wut“ ist als Zahl geschätzt.", "“Enough rage” is estimated as a number."),
          text = T("Sobald gelernt dein Hauptangriff, solange die Wut reicht.", "Once learned your main attack while rage allows.") },    -- Schildschlag / Shield Slam
        { id = 6572, kind = "priority", when = "reactive",
          text = T("Dein Hauptangriff: sobald freigeschaltet.", "Your main attack: as soon as it unlocks.") },    -- Rache / Revenge
        { id = 23922, kind = "priority", when = "ready",
          text = T("Bei wenig Wut erst nach {6572}.", "At low rage only after {6572}.") },    -- Schildschlag / Shield Slam
        { id = 772, kind = "maintain", when = "dot", refresh = "missing", need = { unusable = 5308 },
          guess = T("„Stirbt gleich“ ist geschätzt: sobald das Ziel unter 20 % ist.", "“About to die” is estimated: once the target is below 20%."),
          text = T("Früh setzen; zum Ablauf erneuern.", "Apply early; renew it as it ends.") },    -- Verwunden / Rend
        { id = 7386, kind = "maintain", when = "dot", stacks = 5, mine = false, refresh = 5,
          need = { grouped = true },
          guess = T("Erneuern 5 Sek. vor Ablauf ist geschätzt.", "Refreshing 5 sec before it ends is estimated."),
          text = T("In der Gruppe: 5 Stapel aufbauen und halten.", "In a group: build 5 stacks and keep them.") },    -- Rüstung zerreißen / Sunder Armor
        { id = 7386, key = "sunder:elite", kind = "maintain", when = "dot", stacks = 5, mine = false, refresh = 5,
          need = { solo = true, enemy = { rank = ELITE } },
          text = T("Allein nur gegen Elite und Bosse.", "Solo against elites and bosses only.") },    -- Rüstung zerreißen / Sunder Armor
        { id = 6343, kind = "priority", when = "ready", need = { grouped = true },
          text = T("In der Gruppe, sobald bereit.", "In a group whenever ready.") },    -- Donnerknall / Thunder Clap
        { id = 6343, key = "clap:elite", kind = "priority", when = "ready", need = { solo = true, enemy = { rank = ELITE } },
          text = T("Allein nur gegen gefährliche Nahkämpfer.", "Solo only against dangerous melee enemies.") },    -- Donnerknall / Thunder Clap
        { id = 78, kind = "filler", when = "rage", min = 30, need = { queued = false },
          text = T("Nur Restwut; Wut für {2565} behalten.", "Leftover rage only; keep rage for {2565}.") },    -- Heldenhafter Stoß / Heroic Strike
        -- Mehrere Gegner (Flächenmodus)
        { id = 845, kind = "aoe", when = "rage", min = 30, side = true, need = { queued = false },
          text = T("Zweiter Gegner in Reichweite: statt {78}.", "Second enemy in reach: instead of {78}.") },    -- Spalten / Cleave
        -- Situativ
        { id = 1160, kind = "situational", when = "manual",
          text = T("Früh im Kampf gegen harte Nahkämpfer.", "Early in the fight against hard-hitting melee.") },    -- Demoralisierender Ruf / Demoralizing Shout
        { id = 402927, kind = "situational", when = "manual",
          text = T("Nach einem Kill, wenn dir Leben fehlt.", "After a kill when you are missing health.") },    -- Siegesrausch / Victory Rush
        { id = 12975, kind = "situational", when = "manual",
          text = T("Notfall: vor dem großen Treffer drücken.", "Emergency: press before the big hit.") },    -- Letztes Gefecht / Last Stand
        { id = 355, kind = "situational", when = "manual",
          text = T("Holt einen Gegner zurück; ezCombat sieht das nicht.", "Pulls an enemy back; ezCombat can't see that.") },    -- Spott / Taunt
        { id = 72, kind = "situational", when = "manual",
          text = T("Unterbricht einen Zauber.", "Interrupts a cast.") },    -- Schildhieb / Shield Bash
      } },
})
