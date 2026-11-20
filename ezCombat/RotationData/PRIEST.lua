local _, ns = ...
local T = ns.RotationData.T

-- Priester (PRIEST): Rotationen je Talentbaum für WoW Forever (Format und Felder: Kopf von RotationData.lua).
-- Quellen: Icy Veins, WoW Forever, abgerufen am 13.11.2026 – nur Fakten (Rangfolge, Bedingungen), alle Texte in
-- eigenen Worten. Stand der Seiten in Klammern.
--   Disziplin:  https://www.icy-veins.com/wow-forever/discipline-priest-healer-pve-rotation-cooldowns-abilities (04.11.2026)
--               https://www.icy-veins.com/wow-forever/discipline-priest-leveling (10.11.2026)
--   Heilig:     https://www.icy-veins.com/wow-forever/holy-priest-leveling (10.11.2026)
--               https://www.icy-veins.com/wow-forever/holy-priest-healer-pve-rotation-cooldowns-abilities (04.11.2026)
--   Schatten:   https://www.icy-veins.com/wow-forever/shadow-priest-ranged-dps-pve-rotation-cooldowns-abilities (04.11.2026)
--               https://www.icy-veins.com/wow-forever/shadow-priest-leveling (04.11.2026)
-- Zauber-IDs (Rang 1) geprüft gegen nether.wowhead.com/forever. Nichts stammt aus einem Addon. Name, Symbol, Ränge,
-- gelernt, Lernstufe, Kosten, Zauberzeit, Abklingzeit und Dauer liefert der Client zur Laufzeit.
--
-- Aufbau: Die Heiler-Bäume führen Dauer-Buffs, Vorbereitung und die feste Schadensfolge je Gegner, die die Quelle für
-- Solo-Spiel nennt – Heilen selbst ist keine Rotation. Schatten hat zwei Fassungen: „shadow“ (Höchststufe: Eröffnung,
-- dann Rangfolge) und „shadow_level“ (Leveln: feste Folge je Gegner, dann Zauberstab); „Nach Talentbaum“ wählt nach Stufe.
--
-- [V]     = nicht im Spiel bestätigt (/ez test meldet IDs, die der Client nicht kennt).
-- Annahme = Schwelle ohne Zahl in der Quelle.
-- Aufladungen von Inneres Feuer: Der zweite Schritt meldet nur, wenn der Client 2 bis 5 Stapel nennt. Zeigt der
--   Client die Aufladungen nicht als Stapel, meldet er nie (statt dauernd) – [V].
-- Schattengestalt wird als Aura auf dem Spieler geprüft (wie im Bestand), nicht über die Gestaltleiste: Ob sie dort
--   steht, ist offen; die Aura trägt in jedem Fall.
-- Bedarf: Aura-ID des Talent-Procs „Searing Light“ (Heilig) – erst damit kann Heilige Nova als Proc-Schritt
--   vorgeschlagen werden; bis dahin steht sie nur in der Liste.
-- Nicht abbildbar (nur Text): Gegnerzahl und Lebenszeit der Ziele (Fläche), eigenes Leben im Kampf (Schattenwort:
--   Tod), ob jemand Heilung braucht (Sühne in der Gruppe), Bedrohung (Verblassen als Reaktion), Schild auf den Tank.

ns.RotationData.Add("PRIEST", {
    -----------------------------------------------------------------------------------------------------------------
    -- Disziplin
    -----------------------------------------------------------------------------------------------------------------
    { key = "discipline", tree = 1, name = T("Disziplin", "Discipline"),
      source = "https://www.icy-veins.com/wow-forever/discipline-priest-healer-pve-rotation-cooldowns-abilities",
      sources = { "https://www.icy-veins.com/wow-forever/discipline-priest-leveling" },
      how = T("Heilen ist keine Rotation – das entscheidest du nach Lage. Für Solo-Schaden gilt eine feste Folge je Gegner: Buffs und Schild vorab, {14914} als Pull, dann jeder Zauber einmal. Danach der Zauberstab, bis der Gegner fällt – Mana ist knapp. Den Gegner nie mit {585} oder {8092} beenden.",
              "Healing is not a rotation – you decide that as the fight demands. For solo damage there is a fixed sequence per enemy: buffs and shield first, {14914} as the pull, then each spell once. After that your wand until the enemy dies – mana is scarce. Never finish an enemy with {585} or {8092}."),
      note = T("Die Quelle widerspricht sich: Die Rotationsseite setzt {402174} hinter {589} (Vorlage), die Leveling-Seite direkt hinter {585}, solange {14914} auf dem Ziel brennt – als Schritt zum Einschalten enthalten. Ob jemand Heilung braucht, sieht ezCombat nicht: {402174} wird nur allein vorgeschlagen. In Dungeons bei knappem Mana nur der Zauberstab.",
               "The source contradicts itself: the rotation page puts {402174} after {589} (template), the levelling page right after {585} while {14914} burns on the target – included as a step you can turn on. ezCombat can't see whether anyone needs healing: {402174} is suggested solo only. In dungeons with little mana, wand only."),
      steps = {
        -- Vor dem Kampf (eigene Auswertung, im Kampf nie) ------------------------------------------------------------
        { id = 1243, kind = "longbuff", buff = "fort", when = "buff",
          text = T("Vor dem Kampf auf dich und die Gruppe.", "Before combat on yourself and the group.") },    -- Machtwort: Seelenstärke / Power Word: Fortitude
        { id = 588, kind = "longbuff", buff = "innerFire", when = "buff",
          text = T("Vor dem Kampf; Treffer verbrauchen die Aufladungen.", "Before combat; hits use up its charges.") },    -- Inneres Feuer / Inner Fire
        { id = 588, key = "charges:588", kind = "prepare", when = "ready",
          need = { aura = { id = "innerFire", min = 2, max = 5 } },    -- Annahme: „wenige“ = höchstens 5; ab 2, siehe Dateikopf [V]
          text = T("Nur noch wenige Aufladungen: vor dem Kampf erneuern.", "Only a few charges left: renew before combat.") },    -- Inneres Feuer / Inner Fire
        { id = 14752, kind = "longbuff", buff = "spirit", when = "buff",
          text = T("Vor dem Kampf, sobald gelernt.", "Before combat once learned.") },    -- Göttlicher Willen / Divine Spirit
        { id = 976, kind = "longbuff", buff = "shadowProt", when = "buff", optional = true,
          text = T("Nur wo Schattenschaden droht – bei Bedarf einschalten.", "Only where shadow damage is expected – turn on if needed.") },    -- Schattenschutz / Shadow Protection
        { id = 17, kind = "prepare", when = "buff", refresh = "missing",
          need = { target = true, solo = true, noaura = { id = 6788, filter = "HARMFUL" } },    -- 6788: die Sperre nach dem Schild (Debuff auf dir)
          text = T("Allein: direkt vor dem Angriff auf dich (Gruppe: auf den Tank).", "Solo: on yourself right before you attack (group: on the tank).") },    -- Machtwort: Schild / Power Word: Shield
        -- Eröffnung: feste Folge je Gegner (geschlossener Block) -----------------------------------------------------
        { id = 14914, kind = "opener", when = "ready", once = "target", need = { combat = false },
          text = T("Als ersten Angriff aus der Ferne vorzaubern; im Kampf nicht erneuern.", "Pre-cast from range as your first attack; don't renew it in combat.") },    -- Heiliges Feuer / Holy Fire
        { id = 585, kind = "opener", when = "ready", once = "target",
          text = T("Einmal, solange der Gegner heranläuft.", "Once while the enemy runs towards you.") },    -- Heilige Pein / Smite
        { id = 402174, key = "early:402174", kind = "opener", when = "ready", once = "target", hold = true, optional = true,
          need = { solo = true, aura = { id = 14914, unit = "target" } },
          text = T("Leveling-Variante: schon hier, solange {14914} auf dem Ziel brennt.", "Levelling variant: already here while {14914} burns on the target.") },    -- Sühne / Penance
        { id = 8092, kind = "opener", when = "ready", once = "target",
          text = T("Einmal je Gegner – nicht, um ihn zu beenden.", "Once per enemy – not to finish it off.") },    -- Gedankenschlag / Mind Blast
        { id = 589, kind = "opener", when = "dot", refresh = "missing",
          text = T("Einmal setzen.", "Apply once.") },    -- Schattenwort: Schmerz / Shadow Word: Pain
        { id = 402174, kind = "opener", when = "ready", once = "target", hold = true, need = { solo = true },
          text = T("Einmal, wenn nicht zum Heilen gebraucht (nur allein vorgeschlagen).", "Once unless needed for healing (suggested solo only).") },    -- Sühne / Penance
        -- Im Kampf ---------------------------------------------------------------------------------------------------
        { id = 5019, kind = "filler", when = "autorepeat",
          text = T("Danach der Zauberstab, bis der Gegner fällt – spart Mana.", "Then your wand until the enemy dies – saves mana.") },    -- Schießen / Shoot [V]
        -- Mehrere Gegner (nur Liste) -----------------------------------------------------------------------------------
        { id = 15237, kind = "aoe", when = "aoe",
          text = T("Teuer; laut Quelle für diesen Baum kaum lohnend.", "Costly; per the source hardly worth it for this tree.") },    -- Heilige Nova / Holy Nova
        -- Situativ ---------------------------------------------------------------------------------------------------
        { id = 10060, kind = "situational", when = "manual",
          text = T("Auf einen Schadensverursacher in der Schadensphase oder zum Heilen.", "On a damage dealer in a damage phase, or for healing.") },    -- Seele der Macht / Power Infusion [V]
        { id = 14751, kind = "situational", when = "manual",
          text = T("Vor einer teuren Gruppenheilung, wenn es eng wird.", "Before a costly group heal when things get tight.") },    -- Innerer Fokus / Inner Focus [V]
      } },

    -----------------------------------------------------------------------------------------------------------------
    -- Heilig
    -----------------------------------------------------------------------------------------------------------------
    { key = "holy", tree = 2, name = T("Heilig", "Holy"),
      source = "https://www.icy-veins.com/wow-forever/holy-priest-leveling",
      sources = { "https://www.icy-veins.com/wow-forever/holy-priest-healer-pve-rotation-cooldowns-abilities" },
      how = T("Heilen ist keine Rotation – das entscheidest du nach Lage. Für Solo-Schaden gilt eine feste Folge je Gegner: Buffs und Schild vorab, {14914} als Pull, dann {585}, {8092} und {589} je einmal. Danach der Zauberstab, bis der Gegner fällt – so reicht das Mana.",
              "Healing is not a rotation – you decide that as the fight demands. For solo damage there is a fixed sequence per enemy: buffs and shield first, {14914} as the pull, then {585}, {8092} and {589} once each. After that your wand until the enemy dies – that makes your mana last."),
      note = T("Die Rotationsseite nennt dieselbe Folge ohne {14914}, die Leveling-Seite mit. {15237} lohnt laut Quelle nur, wenn ihr Talent-Proc auslöst – dessen Aura kennt ezCombat noch nicht, deshalb steht der Zauber nur in der Liste. In Gruppen bei knappem Mana nur der Zauberstab.",
               "The rotation page lists the same sequence without {14914}, the levelling page with it. Per the source {15237} only pays off when its talent proc fires – ezCombat doesn't know that aura yet, so the spell is list only. In groups with little mana, wand only."),
      steps = {
        -- Vor dem Kampf ------------------------------------------------------------------------------------------------
        { id = 1243, kind = "longbuff", buff = "fort", when = "buff",
          text = T("Vor dem Kampf auf dich und die Gruppe.", "Before combat on yourself and the group.") },    -- Machtwort: Seelenstärke / Power Word: Fortitude
        { id = 588, kind = "longbuff", buff = "innerFire", when = "buff",
          text = T("Vor dem Kampf; Treffer verbrauchen die Aufladungen.", "Before combat; hits use up its charges.") },    -- Inneres Feuer / Inner Fire
        { id = 588, key = "charges:588", kind = "prepare", when = "ready",
          need = { aura = { id = "innerFire", min = 2, max = 5 } },    -- Annahme: „wenige“ = höchstens 5; ab 2, siehe Dateikopf [V]
          text = T("Nur noch wenige Aufladungen: vor dem Kampf erneuern.", "Only a few charges left: renew before combat.") },    -- Inneres Feuer / Inner Fire
        { id = 14752, kind = "longbuff", buff = "spirit", when = "buff",
          text = T("Vor dem Kampf, sobald gelernt.", "Before combat once learned.") },    -- Göttlicher Willen / Divine Spirit
        { id = 976, kind = "longbuff", buff = "shadowProt", when = "buff", optional = true,
          text = T("Nur wo Schattenschaden droht – bei Bedarf einschalten.", "Only where shadow damage is expected – turn on if needed.") },    -- Schattenschutz / Shadow Protection
        { id = 17, kind = "prepare", when = "buff", refresh = "missing",
          need = { target = true, solo = true, noaura = { id = 6788, filter = "HARMFUL" } },    -- 6788: die Sperre nach dem Schild (Debuff auf dir)
          text = T("Allein: direkt vor dem Angriff auf dich (Gruppe: auf den Tank).", "Solo: on yourself right before you attack (group: on the tank).") },    -- Machtwort: Schild / Power Word: Shield
        -- Eröffnung: feste Folge je Gegner -----------------------------------------------------------------------------
        { id = 14914, kind = "opener", when = "ready", once = "target", need = { combat = false },
          text = T("Als ersten Angriff aus der Ferne vorzaubern; im Kampf nicht erneuern.", "Pre-cast from range as your first attack; don't renew it in combat.") },    -- Heiliges Feuer / Holy Fire
        { id = 585, kind = "opener", when = "ready", once = "target",
          text = T("Einmal, solange der Gegner heranläuft.", "Once while the enemy runs towards you.") },    -- Heilige Pein / Smite
        { id = 8092, kind = "opener", when = "ready", once = "target",
          text = T("Einmal je Gegner – nicht, um ihn zu beenden.", "Once per enemy – not to finish it off.") },    -- Gedankenschlag / Mind Blast
        { id = 589, kind = "opener", when = "dot", refresh = "missing",
          text = T("Einmal setzen.", "Apply once.") },    -- Schattenwort: Schmerz / Shadow Word: Pain
        -- Im Kampf ---------------------------------------------------------------------------------------------------
        { id = 5019, kind = "filler", when = "autorepeat",
          text = T("Danach der Zauberstab, bis der Gegner fällt – spart Mana.", "Then your wand until the enemy dies – saves mana.") },    -- Schießen / Shoot [V]
        -- Mehrere Gegner (nur Liste) -----------------------------------------------------------------------------------
        { id = 15237, kind = "aoe", when = "aoe",
          text = T("Nur wenn ihr Talent auslöst und niemand in Gefahr ist.", "Only when its talent triggers and nobody is in danger.") },    -- Heilige Nova / Holy Nova
        -- Situativ ---------------------------------------------------------------------------------------------------
        { id = 14751, kind = "situational", when = "manual",
          text = T("Vor einer teuren Gruppenheilung, wenn es eng wird.", "Before a costly group heal when things get tight.") },    -- Innerer Fokus / Inner Focus [V]
      } },

    -----------------------------------------------------------------------------------------------------------------
    -- Schatten, Höchststufe: Eröffnung, dann Rangfolge
    -----------------------------------------------------------------------------------------------------------------
    { key = "shadow", tree = 3, name = T("Schatten", "Shadow"),
      source = "https://www.icy-veins.com/wow-forever/shadow-priest-ranged-dps-pve-rotation-cooldowns-abilities",
      sources = { "https://www.icy-veins.com/wow-forever/shadow-priest-leveling" },
      pick = { leveling = false },    -- „Nach Talentbaum“: auf Höchststufe diese, darunter „shadow_level“
      how = T("Vor dem Kampf Gestalt und Buffs, in der Gruppe {586} vor dem Pull. Eröffnet wird mit einem vorgezauberten {8092}. Danach {589} und {2944} halten und erst nach Ablauf erneuern, {8092} und {1309595} nutzen, sobald sie bereit sind, und {15286} halten. Alle Lücken füllt {15407} – den Kanal nie abbrechen.",
              "Before combat: your form and buffs, in a group {586} before the pull. Open with a pre-cast {8092}. Then keep {589} and {2944} up and renew them only after they end, use {8092} and {1309595} whenever ready, and keep {15286} up. Fill every gap with {15407} – never clip the channel."),
      note = T("{1309595} kostet Leben, wenn das Ziel überlebt, und dein Leben kann ezCombat im Kampf nicht lesen: Schalte den Schritt aus, wenn dich niemand heilt. Gegnerzahl und Lebenszeit der Ziele sieht ezCombat nicht – Fläche nur als Liste. Bei Abklingzeit von {1309595} und Lernstufe von {15286} weichen Guide und Tooltip ab; es gilt der Client.",
               "{1309595} costs health if the target survives, and ezCombat can't read your health in combat: turn the step off when nobody heals you. ezCombat can't see enemy count or time to live – AoE is list only. Guide and tooltip differ on the cooldown of {1309595} and when you learn {15286}; the client decides."),
      steps = {
        -- Vor dem Kampf ------------------------------------------------------------------------------------------------
        { id = 15473, kind = "prepare", when = "buff", refresh = "missing",
          text = T("Immer in dieser Gestalt kämpfen; ein Heilzauber beendet sie.", "Always fight in this form; a healing spell ends it.") },    -- Schattengestalt / Shadowform
        { id = 588, kind = "longbuff", buff = "innerFire", when = "buff",
          text = T("Vor dem Kampf; Treffer verbrauchen die Aufladungen.", "Before combat; hits use up its charges.") },    -- Inneres Feuer / Inner Fire
        { id = 588, key = "charges:588", kind = "prepare", when = "ready",
          need = { aura = { id = "innerFire", min = 2, max = 5 } },    -- Annahme: „wenige“ = höchstens 5; ab 2, siehe Dateikopf [V]
          text = T("Nur noch wenige Aufladungen: vor dem Kampf erneuern.", "Only a few charges left: renew before combat.") },    -- Inneres Feuer / Inner Fire
        { id = 1243, kind = "longbuff", buff = "fort", when = "buff",
          text = T("Vor dem Kampf auf dich und die Gruppe.", "Before combat on yourself and the group.") },    -- Machtwort: Seelenstärke / Power Word: Fortitude
        { id = 14752, kind = "longbuff", buff = "spirit", when = "buff",
          text = T("Vor dem Kampf, sobald gelernt.", "Before combat once learned.") },    -- Göttlicher Willen / Divine Spirit
        { id = 976, kind = "longbuff", buff = "shadowProt", when = "buff", optional = true,
          text = T("Nur wo Schattenschaden droht – bei Bedarf einschalten.", "Only where shadow damage is expected – turn on if needed.") },    -- Schattenschutz / Shadow Protection
        { id = 586, kind = "prepare", when = "ready", need = { target = true, grouped = true },
          text = T("In der Gruppe als Erstes vor dem Angriff – dämpft die Bedrohung.", "In a group first thing before you attack – dampens your threat.") },    -- Verblassen / Fade
        -- Eröffnung --------------------------------------------------------------------------------------------------
        { id = 585, kind = "opener", when = "ready", once = "target", need = { unknown = 15407, combat = false },
          text = T("Solange {15407} fehlt: als Erstes vorzaubern.", "Until you learn {15407}: pre-cast it first.") },    -- Heilige Pein / Smite
        { id = 8092, kind = "opener", when = "ready", once = "target", need = { combat = false },
          text = T("Als ersten Angriff vorzaubern, damit er mit Kampfbeginn einschlägt.", "Pre-cast as your first attack so it lands as combat starts.") },    -- Gedankenschlag / Mind Blast
        -- Im Kampf (Reihenfolge = Rang) --------------------------------------------------------------------------------
        { id = 15473, kind = "maintain", when = "buff", refresh = "missing", need = { combat = true },
          text = T("Nach einer Notheilung verloren: wieder annehmen.", "Lost after an emergency heal: enter it again.") },    -- Schattengestalt / Shadowform
        { id = 589, kind = "maintain", when = "dot", refresh = "missing",
          text = T("Fehlt: setzen. Erst nach Ablauf erneuern.", "Missing: apply. Renew only after it ends.") },    -- Schattenwort: Schmerz / Shadow Word: Pain
        { id = 2944, kind = "maintain", when = "dot", refresh = "missing",
          text = T("Fehlt und bereit: setzen (nur auf einem Ziel).", "Missing and ready: apply (one target only).") },    -- Verschlingende Seuche / Devouring Plague
        { id = 8092, kind = "priority", when = "ready",
          text = T("Sobald bereit.", "Whenever ready.") },    -- Gedankenschlag / Mind Blast
        { id = 1309595, kind = "priority", when = "ready",
          text = T("Sobald bereit – nicht bei wenig Leben oder ohne Heiler.", "Whenever ready – not at low health or without a healer.") },    -- Schattenwort: Tod / Shadow Word: Death
        { id = 15286, kind = "maintain", when = "dot", refresh = "missing",
          text = T("Fehlt und bereit: setzen – heilt die Gruppe.", "Missing and ready: apply – it heals your group.") },    -- Vampirumarmung / Vampiric Embrace
        -- Abklingzeiten ----------------------------------------------------------------------------------------------
        { id = 14751, kind = "cooldown", when = "ready", need = { known = 15407, noaura = { id = 14751 } },
          text = T("Wenn geskillt: direkt vor {15407} zünden.", "If talented: trigger it right before {15407}.") },    -- Innerer Fokus / Inner Focus [V]
        -- Im Kampf: Füller ---------------------------------------------------------------------------------------------
        { id = 15407, kind = "filler", when = "filler", hold = true,
          text = T("Lückenfüller; stehen bleiben und das Kanalisieren nie abbrechen.", "Gap filler; stand still and never cut the channel short.") },    -- Gedankenschinden / Mind Flay
        { id = 5019, kind = "filler", when = "autorepeat", need = { unknown = 15407 },
          text = T("Solange {15407} fehlt: der Zauberstab füllt die Lücken.", "Until you learn {15407}: your wand fills the gaps.") },    -- Schießen / Shoot [V]
        -- Mehrere Gegner (nur Liste) -----------------------------------------------------------------------------------
        { id = 589, kind = "aoe", when = "aoe",
          text = T("Auf jeden Gegner, der nicht gleich stirbt; {2944} auf den schwächsten.", "On every enemy that won't die at once; {2944} on the weakest.") },    -- Schattenwort: Schmerz / Shadow Word: Pain
      } },

    -----------------------------------------------------------------------------------------------------------------
    -- Schatten beim Leveln: feste Folge je Gegner, dann Zauberstab
    -----------------------------------------------------------------------------------------------------------------
    { key = "shadow_level", tree = 3, name = T("Schatten (Leveln)", "Shadow (levelling)"),
      source = "https://www.icy-veins.com/wow-forever/shadow-priest-leveling",
      sources = { "https://www.icy-veins.com/wow-forever/shadow-priest-ranged-dps-pve-rotation-cooldowns-abilities" },
      pick = { leveling = true },     -- „Nach Talentbaum“: unter der Höchststufe diese
      how = T("Kein Dauer-Ablauf, sondern eine feste Folge je Gegner: Schild, ein vorgezauberter Pull, dann jeder Zauber einmal. Danach der Zauberstab bis zum Ende – das spart Mana und startet die Regeneration früher. {2944} und {15407} lohnen erst später im Leveln und nur mit Mana übrig.",
              "Not an endless cycle but a fixed sequence per enemy: shield, a pre-cast pull, then each spell once. After that your wand to the end – it saves mana and starts regeneration sooner. {2944} and {15407} only pay off later while levelling and with mana to spare."),
      note = T("Die Mana-Schwelle für {2944} und {15407} ist eine Annahme – die Quelle sagt nur „bei Manamangel weglassen“. Ist dein Mana im Kampf nicht lesbar, überspringt ezCombat beide und nennt sie.",
               "The mana threshold for {2944} and {15407} is an assumption – the source only says to skip them when mana is short. When your mana can't be read in combat, ezCombat skips both and names them."),
      steps = {
        -- Vor dem Kampf ------------------------------------------------------------------------------------------------
        { id = 1243, kind = "longbuff", buff = "fort", when = "buff",
          text = T("Vor dem Kampf auf dich und die Gruppe.", "Before combat on yourself and the group.") },    -- Machtwort: Seelenstärke / Power Word: Fortitude
        { id = 588, kind = "longbuff", buff = "innerFire", when = "buff",
          text = T("Vor dem Kampf; Treffer verbrauchen die Aufladungen.", "Before combat; hits use up its charges.") },    -- Inneres Feuer / Inner Fire
        { id = 588, key = "charges:588", kind = "prepare", when = "ready",
          need = { aura = { id = "innerFire", min = 2, max = 5 } },    -- Annahme: „wenige“ = höchstens 5; ab 2, siehe Dateikopf [V]
          text = T("Nur noch wenige Aufladungen: vor dem Kampf erneuern.", "Only a few charges left: renew before combat.") },    -- Inneres Feuer / Inner Fire
        { id = 14752, kind = "longbuff", buff = "spirit", when = "buff",
          text = T("Vor dem Kampf, sobald gelernt.", "Before combat once learned.") },    -- Göttlicher Willen / Divine Spirit
        { id = 976, kind = "longbuff", buff = "shadowProt", when = "buff", optional = true,
          text = T("Nur wo Schattenschaden droht – bei Bedarf einschalten.", "Only where shadow damage is expected – turn on if needed.") },    -- Schattenschutz / Shadow Protection
        { id = 15473, kind = "prepare", when = "buff", refresh = "missing",
          text = T("Sobald gelernt: immer in dieser Gestalt kämpfen.", "Once learned: always fight in this form.") },    -- Schattengestalt / Shadowform
        { id = 17, kind = "prepare", when = "buff", refresh = "missing",
          need = { target = true, solo = true, noaura = { id = 6788, filter = "HARMFUL" } },    -- 6788: die Sperre nach dem Schild (Debuff auf dir)
          text = T("Allein: direkt vor dem Angriff auf dich.", "Solo: on yourself right before you attack.") },    -- Machtwort: Schild / Power Word: Shield
        -- Eröffnung: feste Folge je Gegner (geschlossener Block) -----------------------------------------------------
        { id = 585, kind = "opener", when = "ready", once = "target", need = { unknown = 15407, combat = false },
          text = T("Solange {15407} fehlt: als Erstes vorzaubern.", "Until you learn {15407}: pre-cast it first.") },    -- Heilige Pein / Smite
        { id = 8092, kind = "opener", when = "ready", once = "target",
          text = T("Als ersten Angriff vorzaubern, einmal je Gegner.", "Pre-cast as your first attack, once per enemy.") },    -- Gedankenschlag / Mind Blast
        { id = 589, kind = "opener", when = "dot", refresh = "missing",
          text = T("Einmal setzen.", "Apply once.") },    -- Schattenwort: Schmerz / Shadow Word: Pain
        { id = 2944, kind = "opener", when = "dot", refresh = "missing",
          need = { level = { min = 30 }, mana = { min = 40 } },    -- Stufe: Schwelle aus dem Guide; Mana: Annahme
          text = T("Nur mit Mana übrig; früh im Leveln weglassen.", "Only with mana to spare; skip it early on.") },    -- Verschlingende Seuche / Devouring Plague
        { id = 15407, kind = "opener", when = "ready", once = "target", hold = true,
          need = { level = { min = 30 }, mana = { min = 40 } },    -- wie oben
          text = T("Einmal je Gegner, mit Mana übrig; Kanalisieren nie abbrechen.", "Once per enemy with mana to spare; never cut the channel short.") },    -- Gedankenschinden / Mind Flay
        -- Im Kampf ---------------------------------------------------------------------------------------------------
        { id = 5019, kind = "filler", when = "autorepeat",
          text = T("Danach der Zauberstab, bis der Gegner fällt.", "Then your wand until the enemy dies.") },    -- Schießen / Shoot [V]
        -- Situativ ---------------------------------------------------------------------------------------------------
        { id = 1309595, kind = "situational", when = "manual",
          text = T("Nur für starke Momente: kostet Leben, wenn das Ziel überlebt.", "Big moments only: costs health if the target survives.") },    -- Schattenwort: Tod / Shadow Word: Death
        { id = 15286, kind = "situational", when = "manual",
          text = T("Heilt dich und die Gruppe über deinen Schattenschaden.", "Heals you and your group through your shadow damage.") },    -- Vampirumarmung / Vampiric Embrace
        { id = 14751, kind = "situational", when = "manual",
          text = T("Vor einem teuren Zauber oder wenn ein kritischer Treffer zählt.", "Before a costly spell or when a critical hit matters.") },    -- Innerer Fokus / Inner Focus [V]
      } },
})
