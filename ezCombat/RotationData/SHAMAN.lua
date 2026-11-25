local _, ns = ...
local T = ns.RotationData.T

-- Schamane (SHAMAN): Rotationen je Talentbaum und Spielweise für WoW Forever (Format: Kopf von RotationData.lua).
-- Hier stehen nur Zauber-ID und Logik. Name, Symbol, Ränge, gelernt, Lernstufe, Kosten, Zauberzeit, Abklingzeit
-- und Dauer liefert der Client zur Laufzeit; {Zauber-ID} im Text wird bei der Anzeige durch den Namen ersetzt.
--
-- Quellen (abgerufen am 13.11.2026; nur Fakten – Rangfolge, Bedingungen –, alle Texte in eigenen Worten):
--   Elementar      https://www.icy-veins.com/wow-forever/elemental-shaman-ranged-dps-pve-rotation-cooldowns-abilities  (Stand der Seite 07.11.2026)
--                  https://www.icy-veins.com/wow-forever/elemental-shaman-leveling  (Stand 04.11.2026)
--                  https://www.wowhead.com/forever/guide/classes/shaman/elemental/rotation-cooldowns-pve-dps
--                  https://www.wowhead.com/forever/guide/classes/shaman/elemental/dps-leveling-tips
--   Verstärkung    https://www.icy-veins.com/wow-forever/enhancement-shaman-melee-dps-pve-rotation-cooldowns-abilities  (Stand 04.11.2026)
--                  (nachgeprüft 20.11.2026 gegen den Stand vom 13.11.2026: Rangfolge unverändert, Waffe des
--                   Windzorns bleibt)
--                  https://www.icy-veins.com/wow-forever/enhancement-shaman-leveling
--                  (nachgeprüft 20.11.2026 (Stand 13.11.2026, Regler je Stufe): Rangfolge unverändert)
--                  https://www.wowhead.com/forever/guide/classes/shaman/enhancement/rotation-cooldowns-pve-dps
--   Wiederherst.   https://www.icy-veins.com/wow-forever/restoration-shaman-healer-pve-rotation-cooldowns-abilities  (Stand 04.11.2026)
--                  https://www.icy-veins.com/wow-forever/restoration-shaman-leveling
--                  https://www.wowhead.com/forever/guide/classes/shaman/restoration/rotation-cooldowns-pve-healer
-- Zauber-IDs (Rang 1) und Namen geprüft gegen nether.wowhead.com/forever (englisch, deutsch). Nichts stammt aus
-- einem Addon.
--
-- Aufbau (Reihenfolge der Liste = Rangfolge; die Art regelt nur Tor und Abschnitt):
--   Vor dem Kampf   Schild über ezCores Gruppe „shield“ (der bessere gelernte Schild zählt), Waffenverzauberung,
--                   Totems je Element über „Platz leer“ – jedes Totem des Elements zählt, die Wahl bleibt beim
--                   Spieler. Totems stehen nur mit angreifbarem Ziel an (sonst mahnte sie jede Stadt an).
--   Mehrere Gegner  stehen in der Liste VOR den Kampfschritten, weil sie im Flächenmodus Vorrang haben; ohne
--                   Flächenmodus werden sie nicht bewertet. Die Gegnerzahl sieht ezCombat nicht – der Spieler schaltet.
--   ODER            gibt es im Format nicht: zwei Schritte mit eigenem key (Freizaubern ODER Mana).
--
-- Annahmen (keine Quelle nennt eine Zahl; im Reiter abschaltbar):
--   Mana-Schwellen 30 / 40 / 50 / 60 Prozent für „mit Mana übrig“, 80 Prozent für das Mana-Totem (belegt: rund ein
--   Fünftel fehlt).
-- [V] – im Spiel zu prüfen (der Selbsttest /ez test nennt unbekannte IDs):
--   16166, 16246  als Aura auf dem Spieler (ID der Aura kann abweichen; dann greift der Namensvergleich)
-- Waffe des Mahlstroms: Die Stapel trägt laut Client-Tabellen die Aura 408505 „Maelstrom Weapon“ (SpellAuraOptions:
--   CumulativeAura 5, ProcCharges 1), nicht das Talent 408498 (CumulativeAura 0; laut wago.tools, wowf 1.60.1.70938 und
--   1.60.1.71037 gleich) – die Schritte prüfen 408505, der Text nennt das Talent. Seit dem Hotfix vom 10.11.2026 (in den
--   Tabellen ab 71037) senkt jeder Stapel Zauberzeit und Kosten um 20 %: fünf Stapel machen den Blitz sofort wirkbar,
--   die Regel „nur mit vollen Stapeln“ bleibt (Paket „Daten auf Build 71037“, 22.11.2026).
-- Laut Client-Tabellen (ClassSpells, wago.tools wowf 1.60.1.70938; Gesamtreview 18.11.2026, T14-NH5/NH1):
--   Totem der Manaflut 16190 ist Rang 1 (Talent) einer Gruppe mit 17354 (Stufe 38), 17359 (48) und 1325256 (58) –
--   der eine Schritt 16190 deckt über den Namen alle Ränge ab (der frühere zweite Schritt 1325256 mit need.unknown =
--   16190 griff nie). Springflut steht mit der Grund-ID 408521 (Rang 1, Talent; Schlüssel des früheren Schritts
--   1239243, Rang 3, bleibt für gemerkte Anpassungen).
-- Bedarf:
--   „irgendein Totem-Platz leer“ (Sammelzauber 66842) kennt der Motor nicht – der Schritt prüft ersatzweise den
--   Erd-Platz und ist optional. Wunsch-Totem je Element und Nähe des Feuer-Totems zum Gegner sind nicht prüfbar.

local IV_ELE = "https://www.icy-veins.com/wow-forever/elemental-shaman-ranged-dps-pve-rotation-cooldowns-abilities"
local IV_ELE_LEVEL = "https://www.icy-veins.com/wow-forever/elemental-shaman-leveling"
local IV_ENH = "https://www.icy-veins.com/wow-forever/enhancement-shaman-melee-dps-pve-rotation-cooldowns-abilities"
local IV_ENH_LEVEL = "https://www.icy-veins.com/wow-forever/enhancement-shaman-leveling"
local IV_RES = "https://www.icy-veins.com/wow-forever/restoration-shaman-healer-pve-rotation-cooldowns-abilities"
local IV_RES_LEVEL = "https://www.icy-veins.com/wow-forever/restoration-shaman-leveling"

ns.RotationData.Add("SHAMAN", {
    ---------------------------------------------------------------------------------------------------------------
    -- Elementar
    ---------------------------------------------------------------------------------------------------------------
    { key = "elemental", tree = 1, name = T("Elementar", "Elemental"),
      source = IV_ELE,
      sources = { IV_ELE_LEVEL,
          "https://www.wowhead.com/forever/guide/classes/shaman/elemental/rotation-cooldowns-pve-dps",
          "https://www.wowhead.com/forever/guide/classes/shaman/elemental/dps-leveling-tips" },
      how = T("Vor dem Pull Schild und Totems setzen, das Feuer-Totem zuletzt; aus der Ferne mit {403} eröffnen. Im Kampf {8050} halten und zum Ablauf erneuern, dann {16166} zünden. {421} nur außerhalb von {16166} und nur mit {16246} oder genug Mana; sonst füllt {403}. Mana ist die Grenze: den Schild gleich nach dem Kampf erneuern, schwache Gegner im Nahkampf erledigen.",
              "Before the pull set your shield and totems, the fire totem last; open from range with {403}. In combat keep {8050} up and renew it as it ends, then fire {16166}. Use {421} only outside {16166} and only with {16246} or enough mana; {403} fills the rest. Mana is the limit: renew the shield right after a fight and finish weak enemies in melee."),
      note = T("Gegnerzahl und Kampfdauer sieht ezCombat nicht: ab drei Gegnern den Flächenmodus einschalten; in langen Kämpfen Manatränke nutzen. Welches Totem je Element passt, entscheidest du – geprüft wird nur, ob der Platz leer ist.",
               "ezCombat can't see enemy count or fight length: switch on AoE mode from three enemies up; use mana potions in long fights. Which totem fits each element is your call – only an empty slot is checked."),
      steps = {
        -- Vor dem Kampf (eigene Auswertung, im Kampf nie) ----------------------------------------------------------
        { id = 324, kind = "longbuff", buff = "shield", when = "buff",
          text = T("Zwischen den Kämpfen; ab {408510} zählt nur noch dieser.", "Between fights; once you have {408510}, only that counts.") },    -- Blitzschlagschild / Lightning Shield
        { id = 66842, kind = "prepare", when = "totemslot", slot = 2, optional = true, need = { target = true },
          text = T("Alle Totems auf einmal – lohnt vor schweren Kämpfen.", "All totems at once – worth it before hard fights.") },    -- Ruf der Elemente / Call of the Elements
        { id = 8075, kind = "prepare", when = "totemslot", slot = 2, need = { target = true, grouped = true },
          text = T("Erd-Platz leer: in der Gruppe für die Nahkämpfer.", "Earth slot empty: in a group, for your melee.") },    -- Totem der Erdstärke / Strength of Earth Totem
        { id = 8071, kind = "prepare", when = "totemslot", slot = 2, need = { target = true, solo = true },
          text = T("Erd-Platz leer: allein zur Abwehr; auf Abstand {2484}.", "Earth slot empty: solo for defence; {2484} to keep enemies away.") },    -- Totem der Steinhaut / Stoneskin Totem
        { id = 5675, kind = "prepare", when = "totemslot", slot = 3, need = { target = true },
          text = T("Wasser-Platz leer: der Standard für dein Mana.", "Water slot empty: the default for your mana.") },    -- Totem der Manaquelle / Mana Spring Totem
        { id = 8512, kind = "prepare", when = "totemslot", slot = 4, need = { target = true, grouped = true },
          text = T("Luft-Platz leer: für Nahkämpfer; gegen Zauberer {8177}.", "Air slot empty: for melee; {8177} against casters.") },    -- Totem des Windzorns / Windfury Totem
        { id = 8190, kind = "prepare", when = "totemslot", slot = 1, need = { target = true, aoe = true },
          text = T("Flächenmodus: als letztes Totem vor dem Angriff.", "AoE mode: your last totem before you attack.") },    -- Totem der glühenden Magma / Magma Totem
        { id = 3599, kind = "prepare", when = "totemslot", slot = 1, need = { target = true, aoe = false },
          text = T("Als letztes Totem vor dem Angriff – es hält nur kurz.", "Your last totem before you attack – it is short-lived.") },    -- Totem der Verbrennung / Searing Totem
        -- Eröffnung (nur vor dem Kampf, einmal je Gegner) -----------------------------------------------------------
        { id = 421, kind = "opener", when = "ready", once = "target", need = { combat = false, aoe = true },
          text = T("Flächenmodus: aus größter Entfernung eröffnen.", "AoE mode: open from maximum range.") },    -- Kettenblitzschlag / Chain Lightning
        { id = 403, kind = "opener", when = "ready", once = "target", need = { combat = false, aoe = false },
          text = T("Aus größter Entfernung vorzaubern.", "Pre-cast from maximum range.") },    -- Blitzschlag / Lightning Bolt
        -- Mehrere Gegner (nur im Flächenmodus; dann vor den Kampfschritten) ------------------------------------------
        { id = 8190, kind = "aoe", when = "totemslot", slot = 1,
          text = T("Kein Feuer-Totem: setzen und gegen mehrere Gegner halten.", "No fire totem: drop it and keep it up against several enemies.") },    -- Totem der glühenden Magma / Magma Totem
        { id = 421, kind = "aoe", when = "ready",
          text = T("Gegen mehrere Gegner immer, wenn bereit.", "Against several enemies whenever it is ready.") },    -- Kettenblitzschlag / Chain Lightning
        { id = 408341, kind = "aoe", when = "ready", need = { totem = { slot = 1 } },
          text = T("Immer, wenn bereit; geht vom Feuer-Totem aus.", "Whenever ready; it bursts from your fire totem.") },    -- Feuernova / Fire Nova
        { id = 8050, kind = "aoe", when = "dot", refresh = "missing",
          text = T("Auf Ziele ohne ihn; in langen Kämpfen weglassen.", "On targets without it; skip it in long fights.") },    -- Flammenschock / Flame Shock
        -- Im Kampf (Reihenfolge = Rang) ---------------------------------------------------------------------------
        { id = 408510, kind = "maintain", when = "buff", refresh = "missing",
          text = T("Sobald geskillt: auch im Kampf halten.", "Once talented: keep it up in combat too.") },    -- Wasserschild / Water Shield
        { id = 3599, kind = "maintain", when = "totemslot", slot = 1,
          text = T("Kein Feuer-Totem mehr: neu setzen.", "No fire totem left: drop a new one.") },    -- Totem der Verbrennung / Searing Totem
        { id = 8050, kind = "maintain", when = "dot", refresh = "missing",
          text = T("Fehlt er: setzen. Zum Ablauf erneuern.", "Missing: apply. Renew it as it ends.") },    -- Flammenschock / Flame Shock
        { id = 16166, kind = "cooldown", burst = true, when = "ready", need = { combat = true, aura = { id = 8050, unit = "target" } },
          text = T("Nach Totems und {8050}; mit Schmuck und Volksfähigkeit.", "After totems and {8050}; with trinkets and racial.") },    -- Blitzbeherrschung / Lightning Mastery
        { id = 16190, kind = "resource", when = "lowmana", max = 80, need = { combat = true },
          text = T("Früh setzen, sobald rund ein Fünftel Mana fehlt.", "Drop it early, once about a fifth of your mana is gone.") },    -- Totem der Manaflut / Mana Tide Totem
        { id = 421, key = "priority:421:proc", kind = "priority", when = "proc", aura = 16246,
          need = { noaura = { id = 16166 } },
          text = T("Mit {16246} – aber nie während {16166}.", "With {16246} – but never during {16166}.") },    -- Kettenblitzschlag / Chain Lightning
        { id = 421, kind = "priority", when = "ready",
          need = { noaura = { id = 16166 }, mana = { min = 50 } },
          guess = T("Die Mana-Schwelle ist geschätzt; die Quelle nennt keine Zahl.", "The mana threshold is estimated; the source gives no number."),
          text = T("Außerhalb von {16166}, solange das Mana reicht.", "Outside {16166} while your mana lasts.") },    -- Kettenblitzschlag / Chain Lightning
        { id = 403, kind = "filler", when = "filler",
          text = T("Füllt jeden freien Zauberplatz.", "Fills every free cast.") },    -- Blitzschlag / Lightning Bolt
        -- Situativ (nur Liste) --------------------------------------------------------------------------------------
        { id = 8042, kind = "situational", when = "manual",
          text = T("Kein Rotationszauber: unterbricht Zauber.", "Not a rotation spell: interrupts casts.") },    -- Erdschock / Earth Shock
        { id = 8056, kind = "situational", when = "manual",
          text = T("Gegner verlangsamen und auf Abstand halten.", "To slow enemies and keep them away.") },    -- Frostschock / Frost Shock
        { id = 2484, kind = "situational", when = "manual",
          text = T("Erd-Platz, um Gegner auf Abstand zu halten.", "Earth slot to keep enemies away.") },    -- Totem der Erdbindung / Earthbind Totem
        { id = 8143, kind = "situational", when = "manual",
          text = T("Erd-Platz gegen Furcht, Schlaf und Bezauberung.", "Earth slot against fear, sleep and charm.") },    -- Totem des Erdstoßes / Tremor Totem
        { id = 36936, kind = "situational", when = "manual",
          text = T("Beim Ortswechsel: holt Totems und etwas Mana zurück.", "When moving on: returns your totems and some mana.") },    -- Totemischer Rückruf / Totemic Recall
      } },

    ---------------------------------------------------------------------------------------------------------------
    -- Verstärkung beim Leveln (steht vor „enhancement“: „Nach Talentbaum“ nimmt die erste Rotation, deren pick passt)
    ---------------------------------------------------------------------------------------------------------------
    { key = "enhancement_level", tree = 2, name = T("Verstärkung (Leveln)", "Enhancement (levelling)"),
      source = IV_ENH_LEVEL,
      sources = { IV_ENH, "https://www.wowhead.com/forever/guide/classes/shaman/elemental/dps-leveling-tips" },
      pick = { leveling = true },
      how = T("Die Waffe bleibt verzaubert, der Schild liegt zwischen den Kämpfen. Im Kampf {17364}, sobald es bereit ist, sonst {8042} und Autoangriffe – Mana sparen geht vor. {8050} lohnt allein nicht, nur in Gruppen. {403} nur mit vollen Stapeln von {408498}. Steht nichts an, einfach weiter zuschlagen.",
              "Keep your weapon enchanted and your shield up between fights. In combat use {17364} whenever it is ready, otherwise {8042} and auto-attacks – saving mana comes first. {8050} isn't worth it solo, only in groups. {403} only at full {408498} stacks. When nothing is suggested, just keep swinging."),
      note = T("Ob ein Gegner gefährlich ist, sieht ezCombat nicht: {425336} dafür aufsparen (Einstellung „Große Abklingzeiten“). Feuer-Totem und {408341} kosten viel Mana – deshalb abgeschaltet bzw. nur mit Mana übrig.",
               "ezCombat can't tell a dangerous enemy: save {425336} for those (setting “Major cooldowns”). Fire totem and {408341} are mana-hungry – hence off by default or only with mana to spare."),
      steps = {
        -- Vor dem Kampf --------------------------------------------------------------------------------------------
        { id = 8232, kind = "prepare", when = "enchant", hand = "main",
          text = T("Waffe ohne Verzauberung: auftragen.", "Weapon without an enchant: apply it.") },    -- Waffe des Windzorns / Windfury Weapon
        { id = 8017, kind = "prepare", when = "enchant", hand = "main", need = { unknown = 8232 },
          text = T("Solange {8232} fehlt: diese Verzauberung.", "Until you learn {8232}: this enchant.") },    -- Waffe des Felsbeißers / Rockbiter Weapon
        { id = 324, kind = "longbuff", buff = "shield", when = "buff",
          text = T("Zwischen den Kämpfen auftragen.", "Apply it between fights.") },    -- Blitzschlagschild / Lightning Shield
        { id = 8075, kind = "prepare", when = "totemslot", slot = 2, need = { target = true },
          text = T("Erd-Platz leer: vor dem Kampf setzen.", "Earth slot empty: drop it before the fight.") },    -- Totem der Erdstärke / Strength of Earth Totem
        -- Im Kampf ---------------------------------------------------------------------------------------------------
        { id = 425336, kind = "cooldown", burst = true, when = "ready", need = { combat = true },
          text = T("Gegen gefährliche Gegner; sonst aufsparen.", "Against dangerous enemies; otherwise save it.") },    -- Zorn des Scharfsehers / Rage of the Farseer
        { id = 17364, kind = "priority", when = "ready",
          text = T("Immer, wenn bereit.", "Whenever it is ready.") },    -- Sturmschlag / Stormstrike
        { id = 8050, kind = "maintain", when = "dot", refresh = "missing", need = { grouped = true },
          text = T("Nur in Gruppen: fehlt er, setzen.", "In groups only: apply when missing.") },    -- Flammenschock / Flame Shock
        { id = 403, kind = "priority", when = "proc", aura = 408505, stacks = 5,
          text = T("Nur mit vollen Stapeln von {408498}.", "Only at full {408498} stacks.") },    -- Blitzschlag / Lightning Bolt
        { id = 8042, kind = "priority", when = "ready",
          text = T("Dein Schock beim Leveln, sobald er bereit ist.", "Your levelling shock whenever it is ready.") },    -- Erdschock / Earth Shock
        { id = 3599, kind = "maintain", when = "totemslot", slot = 1, optional = true,
          need = { mana = { min = 50 } },
          guess = T("Die Mana-Schwelle ist geschätzt; die Quelle nennt keine Zahl.", "The mana threshold is estimated; the source gives no number."),
          text = T("Mit Mana übrig: ein Feuer-Totem für längere Kämpfe.", "With mana to spare: a fire totem for longer fights.") },    -- Totem der Verbrennung / Searing Totem
        { id = 408341, kind = "filler", when = "ready",
          need = { totem = { slot = 1 }, mana = { min = 60 } },
          guess = T("Die Mana-Schwelle ist geschätzt; die Quelle nennt keine Zahl.", "The mana threshold is estimated; the source gives no number."),
          text = T("Nur mit Feuer-Totem und viel Mana übrig.", "Only with a fire totem and plenty of mana.") },    -- Feuernova / Fire Nova
        -- Situativ ---------------------------------------------------------------------------------------------------
        { id = 403, kind = "situational", when = "manual",
          text = T("Niedrigster Rang, um Gegner heranzuziehen.", "Lowest rank to pull enemies to you.") },    -- Blitzschlag / Lightning Bolt
        { id = 8056, kind = "situational", when = "manual",
          text = T("Statt {8042}, wenn du zu viel Bedrohung erzeugst.", "Instead of {8042} when you draw too much threat.") },    -- Frostschock / Frost Shock
      } },

    ---------------------------------------------------------------------------------------------------------------
    -- Verstärkung
    ---------------------------------------------------------------------------------------------------------------
    { key = "enhancement", tree = 2, name = T("Verstärkung", "Enhancement"),
      source = IV_ENH,
      sources = { IV_ENH_LEVEL,
          "https://www.wowhead.com/forever/guide/classes/shaman/enhancement/rotation-cooldowns-pve-dps" },
      how = T("Vor dem Kampf: Waffe verzaubern, Schild, vier Totems. Im Kampf muss immer ein Feuer-Totem stehen. Der Schock geht an {8050}, wenn er fehlt, sonst an {8042}. {17364} hat Vorrang, sobald es bereit ist; {403} nur mit vollen Stapeln von {408498}, nie darunter. {408341} füllt Lücken, solange Mana übrig ist – am besten mit {16246}. Sind alle Zauber in der Abklingzeit, schlägst du einfach weiter zu.",
              "Before combat: enchant your weapon, shield, four totems. In combat a fire totem must always be up. Your shock goes to {8050} when it is missing, otherwise to {8042}. {17364} comes first whenever ready; {403} only at full {408498} stacks, never below. {408341} fills gaps while you have mana – ideally with {16246}. When everything is on cooldown, just keep swinging."),
      note = T("Bedrohung und Gegnerzahl sieht ezCombat nicht: in Gruppen bei zu viel Bedrohung {8056} statt {8042}; ab drei Gegnern den Flächenmodus einschalten ({408341} rückt dann nach vorn). Totem und Waffenverzauberung gleichen Namens stapeln nicht.",
               "ezCombat can't see threat or enemy count: in groups use {8056} instead of {8042} on threat trouble; switch on AoE mode from three enemies up ({408341} then moves to the front). The totem and weapon enchant of the same name don't stack."),
      steps = {
        -- Vor dem Kampf --------------------------------------------------------------------------------------------
        { id = 8232, kind = "prepare", when = "enchant", hand = "main",
          text = T("Waffe ohne Verzauberung: auftragen.", "Weapon without an enchant: apply it.") },    -- Waffe des Windzorns / Windfury Weapon
        { id = 8017, kind = "prepare", when = "enchant", hand = "main", need = { unknown = 8232 },
          text = T("Solange {8232} fehlt: diese Verzauberung.", "Until you learn {8232}: this enchant.") },    -- Waffe des Felsbeißers / Rockbiter Weapon
        { id = 324, kind = "longbuff", buff = "shield", when = "buff",
          text = T("Vor dem Angriff auftragen.", "Apply it before you attack.") },    -- Blitzschlagschild / Lightning Shield
        { id = 66842, kind = "prepare", when = "totemslot", slot = 2, optional = true, need = { target = true },
          text = T("Alle Totems auf einmal statt einzeln.", "All totems at once instead of one by one.") },    -- Ruf der Elemente / Call of the Elements
        { id = 8075, kind = "prepare", when = "totemslot", slot = 2, need = { target = true },
          text = T("Erd-Platz leer: der Standard; zur Abwehr {8071}.", "Earth slot empty: the default; {8071} for defence.") },    -- Totem der Erdstärke / Strength of Earth Totem
        { id = 5675, kind = "prepare", when = "totemslot", slot = 3, need = { target = true },
          text = T("Wasser-Platz leer: der Standard.", "Water slot empty: the default.") },    -- Totem der Manaquelle / Mana Spring Totem
        { id = 8512, kind = "prepare", when = "totemslot", slot = 4, need = { target = true, grouped = true },
          text = T("Luft-Platz leer: in jeder Gruppe; gegen Zauberer {8177}.", "Air slot empty: in any group; {8177} against casters.") },    -- Totem des Windzorns / Windfury Totem
        { id = 8835, kind = "prepare", when = "totemslot", slot = 4, need = { target = true, solo = true },
          text = T("Luft-Platz leer: allein dieses.", "Air slot empty: this one when solo.") },    -- Totem der luftgleichen Anmut / Grace of Air Totem
        { id = 8190, kind = "prepare", when = "totemslot", slot = 1, need = { target = true },
          text = T("Feuer-Platz leer: als letztes Totem vor dem Angriff.", "Fire slot empty: your last totem before you attack.") },    -- Totem der glühenden Magma / Magma Totem
        { id = 3599, kind = "prepare", when = "totemslot", slot = 1, need = { target = true, unknown = 8190 },
          text = T("Feuer-Platz leer: solange {8190} fehlt, dieses.", "Fire slot empty: this one until you learn {8190}.") },    -- Totem der Verbrennung / Searing Totem
        -- Mehrere Gegner (nur im Flächenmodus; dann vor den Kampfschritten) ------------------------------------------
        { id = 8190, kind = "aoe", when = "totemslot", slot = 1,
          text = T("Kein Feuer-Totem: zuerst setzen.", "No fire totem: drop it first.") },    -- Totem der glühenden Magma / Magma Totem
        { id = 408341, kind = "aoe", when = "ready", need = { totem = { slot = 1 } },
          text = T("Gegen mehrere Gegner gleich nach dem Totem, immer wenn bereit.", "Against several enemies right after the totem, whenever ready.") },    -- Feuernova / Fire Nova
        -- Im Kampf (Reihenfolge = Rang) ---------------------------------------------------------------------------
        { id = 8190, kind = "maintain", when = "totemslot", slot = 1,
          need = { mana = { min = 30 } },
          guess = T("Die Mana-Schwelle ist geschätzt; die Quelle nennt keine Zahl.", "The mana threshold is estimated; the source gives no number."),
          text = T("Kein Feuer-Totem aktiv: setzen.", "No fire totem active: drop it.") },    -- Totem der glühenden Magma / Magma Totem
        { id = 3599, key = "maintain:3599:lowmana", kind = "maintain", when = "totemslot", slot = 1,
          need = { known = 8190, mana = { max = 30 } },
          guess = T("Die Mana-Schwelle ist geschätzt; die Quelle nennt keine Zahl.", "The mana threshold is estimated; the source gives no number."),
          text = T("Bei knappem Mana der sparsame Ersatz für {8190}.", "The cheap stand-in for {8190} when mana is short.") },    -- Totem der Verbrennung / Searing Totem
        { id = 3599, kind = "maintain", when = "totemslot", slot = 1, need = { unknown = 8190 },
          text = T("Kein Feuer-Totem aktiv: setzen, solange {8190} fehlt.", "No fire totem active: drop it until you learn {8190}.") },    -- Totem der Verbrennung / Searing Totem
        { id = 8050, kind = "maintain", when = "dot", refresh = "missing",
          text = T("Fehlt er auf dem Ziel: der Schock geht hierhin.", "Missing on the target: your shock goes here.") },    -- Flammenschock / Flame Shock
        { id = 425336, kind = "cooldown", burst = true, when = "ready", need = { combat = true },
          text = T("Wenn bereit oder für starke Momente; mit Schmuck und Volksfähigkeit.", "When ready or saved for big moments; with trinkets and racial.") },    -- Zorn des Scharfsehers / Rage of the Farseer
        { id = 17364, kind = "priority", when = "ready",
          text = T("Immer, wenn bereit – trägt Schaden und Mana.", "Whenever ready – it carries damage and mana.") },    -- Sturmschlag / Stormstrike
        { id = 403, kind = "priority", when = "proc", aura = 408505, stacks = 5,
          text = T("Nur mit vollen Stapeln von {408498}, nie darunter.", "Only at full {408498} stacks, never below.") },    -- Blitzschlag / Lightning Bolt
        { id = 8042, kind = "priority", when = "ready", need = { aura = { id = 8050, unit = "target" } },
          text = T("Schock frei und {8050} liegt: dieser.", "Shock ready and {8050} is up: this one.") },    -- Erdschock / Earth Shock
        { id = 8042, key = "priority:8042:early", kind = "priority", when = "ready", need = { unknown = 8050 },
          text = T("Solange {8050} fehlt: dein einziger Schock.", "Until you learn {8050}: your only shock.") },    -- Erdschock / Earth Shock
        { id = 408341, key = "filler:408341:proc", kind = "filler", when = "proc", aura = 16246,
          need = { totem = { slot = 1 } },
          text = T("Am besten mit {16246} verbrauchen.", "Best spent on {16246}.") },    -- Feuernova / Fire Nova
        { id = 408341, kind = "filler", when = "ready",
          need = { totem = { slot = 1 }, mana = { min = 40 } },
          guess = T("Die Mana-Schwelle ist geschätzt; die Quelle nennt keine Zahl.", "The mana threshold is estimated; the source gives no number."),
          text = T("Lückenfüller mit Feuer-Totem und Mana übrig.", "Gap filler with a fire totem and mana to spare.") },    -- Feuernova / Fire Nova
        -- Situativ ---------------------------------------------------------------------------------------------------
        { id = 8056, kind = "situational", when = "manual",
          text = T("Statt {8042}, wenn du zu viel Bedrohung erzeugst.", "Instead of {8042} when you draw too much threat.") },    -- Frostschock / Frost Shock
        { id = 8024, kind = "situational", when = "manual",
          text = T("Mögliche Wahl mit Zaubermacht-Ausrüstung (offen).", "A possible pick with spell power gear (unsettled).") },    -- Waffe der Flammenzunge / Flametongue Weapon
        { id = 8177, kind = "situational", when = "manual",
          text = T("Luft-Platz gegen Zauberer.", "Air slot against casters.") },    -- Totem der Erdung / Grounding Totem
        { id = 8071, kind = "situational", when = "manual",
          text = T("Erd-Platz zur Abwehr.", "Earth slot for defence.") },    -- Totem der Steinhaut / Stoneskin Totem
      } },

    ---------------------------------------------------------------------------------------------------------------
    -- Wiederherstellung (Heilerbaum: Heilen ist keine Rotation – hier stehen Vorbereitung und der Schaden nebenher)
    ---------------------------------------------------------------------------------------------------------------
    { key = "restoration", tree = 3, name = T("Wiederherstellung", "Restoration"),
      source = IV_RES,
      sources = { IV_RES_LEVEL,
          "https://www.wowhead.com/forever/guide/classes/shaman/restoration/rotation-cooldowns-pve-healer" },
      how = T("Heilen ist keine feste Folge – wen du heilst, entscheidest du; ezCombat schlägt keine Heilzauber vor. Es zeigt, was vor dem Kampf fehlt (Schild, Totems, das Feuer-Totem zuletzt), hält {408510} im Kampf und nennt das Mana-Totem, sobald rund ein Fünftel Mana fehlt. {403} erscheint nur als Schaden nebenher: wenn niemand Heilung braucht und das Mana reicht.",
              "Healing is no fixed sequence – whom you heal is your call; ezCombat suggests no healing spells. It shows what is missing before combat (shield, totems, the fire totem last), keeps {408510} up in combat and names the mana totem once about a fifth of your mana is gone. {403} appears only as damage on the side: when nobody needs healing and mana allows."),
      note = T("Den Heilbedarf der Gruppe sieht ezCombat nicht – Heilung geht immer vor. Die Quelle rät davon ab, mit diesem Baum allein zu leveln.",
               "ezCombat can't see who needs healing – healing always comes first. The source advises against levelling solo in this tree."),
      steps = {
        -- Vor dem Kampf --------------------------------------------------------------------------------------------
        { id = 324, kind = "longbuff", buff = "shield", when = "buff",
          text = T("Zwischen den Kämpfen; ab {408510} zählt nur noch dieser.", "Between fights; once you have {408510}, only that counts.") },    -- Blitzschlagschild / Lightning Shield
        { id = 66842, kind = "prepare", when = "totemslot", slot = 2, optional = true, need = { target = true },
          text = T("Alle Totems auf einmal vor dem Angriff.", "All totems at once before you attack.") },    -- Ruf der Elemente / Call of the Elements
        { id = 8075, kind = "prepare", when = "totemslot", slot = 2, need = { target = true, grouped = true },
          text = T("Erd-Platz leer: in der Gruppe für die Nahkämpfer.", "Earth slot empty: in a group, for your melee.") },    -- Totem der Erdstärke / Strength of Earth Totem
        { id = 8071, kind = "prepare", when = "totemslot", slot = 2, need = { target = true, solo = true },
          text = T("Erd-Platz leer: allein zur Abwehr.", "Earth slot empty: solo for defence.") },    -- Totem der Steinhaut / Stoneskin Totem
        { id = 5675, kind = "prepare", when = "totemslot", slot = 3, need = { target = true },
          text = T("Wasser-Platz leer: der Standard; sonst {5394}.", "Water slot empty: the default; otherwise {5394}.") },    -- Totem der Manaquelle / Mana Spring Totem
        { id = 8512, kind = "prepare", when = "totemslot", slot = 4, need = { target = true, grouped = true },
          text = T("Luft-Platz leer: für Nahkämpfer; gegen Zauberer {8177}.", "Air slot empty: for melee; {8177} against casters.") },    -- Totem des Windzorns / Windfury Totem
        { id = 8190, kind = "prepare", when = "totemslot", slot = 1, need = { target = true, aoe = true },
          text = T("Flächenmodus: als letztes Totem vor dem Angriff.", "AoE mode: your last totem before you attack.") },    -- Totem der glühenden Magma / Magma Totem
        { id = 3599, kind = "prepare", when = "totemslot", slot = 1, need = { target = true, aoe = false },
          text = T("Als letztes Totem vor dem Angriff – es hält nur kurz.", "Your last totem before you attack – it is short-lived.") },    -- Totem der Verbrennung / Searing Totem
        -- Im Kampf ---------------------------------------------------------------------------------------------------
        { id = 408510, kind = "maintain", when = "buff", refresh = "missing",
          text = T("Sobald geskillt: zu jeder Zeit halten.", "Once talented: keep it up at all times.") },    -- Wasserschild / Water Shield
        { id = 16190, kind = "resource", when = "lowmana", max = 80, need = { combat = true },
          text = T("Früh setzen, sobald rund ein Fünftel Mana fehlt.", "Drop it early, once about a fifth of your mana is gone.") },    -- Totem der Manaflut / Mana Tide Totem
        { id = 403, kind = "filler", when = "filler",
          need = { mana = { min = 50 } },
          guess = T("Die Mana-Schwelle ist geschätzt; die Quelle nennt keine Zahl.", "The mana threshold is estimated; the source gives no number."),
          text = T("Schaden nebenher: nur ohne Heilbedarf und mit Mana.", "Damage on the side: only with nobody to heal and mana.") },    -- Blitzschlag / Lightning Bolt
        -- Mehrere Gegner (nur Liste) ---------------------------------------------------------------------------------
        { id = 408341, kind = "aoe", when = "aoe",
          text = T("Ab drei Gegnern, ohne Heilbedarf und mit Mana.", "Three or more enemies, nobody to heal, mana to spare.") },    -- Feuernova / Fire Nova
        { id = 421, kind = "aoe", when = "aoe",
          text = T("Ab drei Gegnern, ohne Heilbedarf und mit Mana.", "Three or more enemies, nobody to heal, mana to spare.") },    -- Kettenblitzschlag / Chain Lightning
        -- Situativ (Heilung und Bestand – nie vorgeschlagen) ---------------------------------------------------------
        { id = 408521, key = "situational:1239243", kind = "situational", when = "manual",
          text = T("Immer wenn bereit auf den am stärksten Verletzten.", "Whenever ready on whoever is hurt most.") },    -- Springflut / Riptide
        { id = 331, kind = "situational", when = "manual",
          text = T("Einzelne Ziele; bei wenig Schaden ein niedriger Rang.", "Single targets; a lower rank for light damage.") },    -- Welle der Heilung / Healing Wave
        { id = 1064, kind = "situational", when = "manual",
          text = T("Für die Gruppe, am besten auf ein Ziel mit {408521}.", "For the group, ideally on a target with {408521}.") },    -- Kettenheilung / Chain Heal
        { id = 16188, kind = "situational", when = "manual",
          text = T("Für den Notfall aufheben: die nächste Heilung sofort.", "Save for emergencies: your next heal is instant.") },    -- Schnelligkeit der Natur / Nature's Swiftness
        { id = 8042, kind = "situational", when = "manual",
          text = T("Dein einziger Unterbrecher.", "Your only interrupt.") },    -- Erdschock / Earth Shock
        { id = 8050, kind = "situational", when = "manual",
          text = T("Aus dem Bestand; die Quellen nennen ihn hier nicht.", "From the old list; the sources don't name it here.") },    -- Flammenschock / Flame Shock
      } },
})
