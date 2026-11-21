local _, ns = ...
local T = ns.RotationData.T

-- Druide (DRUID): Rotationen je Talentbaum für WoW Forever. Format und Felder: Kopf von RotationData.lua.
-- Quellen, abgerufen am 13.11.2026 – nur Fakten (Rangfolge, Bedingungen), Texte in eigenen Worten:
--   Gleichgewicht:      https://www.icy-veins.com/wow-forever/balance-druid-ranged-dps-pve-rotation-cooldowns-abilities
--                       https://www.icy-veins.com/wow-forever/balance-druid-leveling
--                       https://www.wowhead.com/forever/guide/classes/druid/balance/rotation-cooldowns-pve-dps
--   Wilder Kampf:       https://www.icy-veins.com/wow-forever/feral-druid-melee-dps-and-tank-pve-rotation-cooldowns-abilities
--                       (Stand 04.11.2026, nachgeprüft 20.11.2026: „Primal Bite“ nur in der Bärengestalt, „Feral Charge“
--                       nicht in der Rangfolge; Katze unverändert)
--                       https://www.icy-veins.com/wow-forever/feral-druid-leveling
--                       https://www.wowhead.com/forever/guide/classes/druid/feral/rotation-cooldowns-pve-dps
--                       https://www.wowhead.com/forever/guide/classes/druid/feral/rotation-cooldowns-pve-tank
--   Wiederherstellung:  https://www.icy-veins.com/wow-forever/restoration-druid-healer-pve-rotation-cooldowns-abilities
--                       (nachgeprüft 20.11.2026: Heilende Berührung 5185 selten (Leveln-Seite: wenn Verjüngung und
--                        Nachwachsen laufen) – Listeneintrag)
--                       https://www.icy-veins.com/wow-forever/restoration-druid-leveling
--   Gestalten:          https://www.icy-veins.com/wow-forever/druid-shapeshift-forms
-- Zauber-IDs (Rang 1) geprüft gegen nether.wowhead.com/forever. Nichts stammt aus einem Addon. Name, Symbol, Ränge,
-- gelernt, Lernstufe, Kosten, Zauberzeit, Abklingzeit und Dauer liefert der Client zur Laufzeit; hier stehen nur
-- Zauber-ID und Logik. Zahlen sind Schwellen der Logik; wo keine Quelle sie nennt, sagt es das Feld guess (Tooltip „Annahme: …“).
-- [V] = ID oder Annahme nicht im Spiel bestätigt (der Selbsttest über den Befehl ez test meldet unbekannte IDs).
--
-- Wahl bei „Nach Talentbaum“ (Wilder Kampf): in der Katzengestalt die Katze, sonst der Bär. Der Bär steht bewusst
-- ohne pick da: Vor der Katzengestalt (Stufe 20) ist er die einzige Tiergestalt, und seine Liste trägt dafür auch die
-- zwei Zauber der Normalgestalt. Die Abfrage „Bär oder Terrorbär“ gäbe es jetzt (ezCore.Spells.FORM_IDS nennt beide
-- mit einer Nummer, CB-34); ein pick.form = 5487 schickte aber jeden Druiden in der Normalgestalt zur Katze – auch
-- den, der sie noch nicht gelernt hat.
-- Bedarf: Die Stellung hinter dem Ziel ist nicht lesbar – der Aufbauer von hinten ist deshalb ein Schritt zum
--         Einschalten (optional), und der Zauber auf den Gratis-Proc gilt nur in der Gruppe.

ns.RotationData.Add("DRUID", {
    ---------------------------------------------------------------------------------------------------------------
    -- Gleichgewicht
    ---------------------------------------------------------------------------------------------------------------
    { key = "balance", tree = 1, name = T("Gleichgewicht", "Balance"),
      source = "https://www.icy-veins.com/wow-forever/balance-druid-ranged-dps-pve-rotation-cooldowns-abilities",
      sources = { "https://www.icy-veins.com/wow-forever/balance-druid-leveling",
          "https://www.wowhead.com/forever/guide/classes/druid/balance/rotation-cooldowns-pve-dps" },
      how = T("Halte {5570} und {8921} auf dem Ziel und erneuere sie erst, wenn sie ausgelaufen sind. Dazwischen lädt ein {5176} das Talent {408248} auf; die Ladungen verbrauchst du mit {2912}, ohne Ladung bleibt es bei {5176}. Buffs und Gestalt gehören vor den Kampf, der Pull ist ein vorgezauberter {5176}. Ohne das Talent ist {5176} der einzige Füller.",
              "Keep {5570} and {8921} on the target and renew them only after they have run out. In between, one {5176} charges the {408248} talent; you spend the charges on {2912}, and without a charge you stay on {5176}. Buffs and form belong before combat, the pull is a pre-cast {5176}. Without the talent {5176} is your only filler."),
      note = T("Ob {5176} getroffen hat, sieht ezCombat nicht; sind die Ladungen gesperrt, wird mitgezählt. Bei Manamangel nur {5176}, {2912} dann nur mit {16870}. Die Gegnerzahl ist unsichtbar: Fläche nur im Flächenmodus, sinnvoll ab etwa fünf Gegnern.",
               "ezCombat can't see whether {5176} hit; locked charges are counted instead. Low on mana cast {5176} only, {2912} just on {16870}. Enemy count is invisible: AoE only in AoE mode, worth it from about five enemies."),
      counters = {
          -- Ladungen des Talents: gelesen aus der eigenen Aura; gesperrt: aus den eigenen Zaubern gezählt.
          -- Rückfall für den Verfall (Tooltip des Talents), solange der Client die Dauer nicht geliefert hat.
          eclipse = { aura = 408248, known = 408248, max = 4, gain = { [5176] = 2 }, spend = { [2912] = 1 },
              fallback = { seconds = 15 } },
      },
      steps = {
        -- Vor dem Kampf --------------------------------------------------------------------------------------------
        { id = 1126, kind = "longbuff", buff = "motw", when = "buff",
          text = T("Vor dem Kampf auf dich und die Gruppe.", "Before combat on yourself and the group.") },    -- Mal der Wildnis / Mark of the Wild
        { id = 467, kind = "longbuff", buff = "thorns", when = "buff", need = { solo = true },
          text = T("Allein auf dich; in der Gruppe gehört es auf den Tank.", "Solo on yourself; in a group it belongs on the tank.") },    -- Dornen / Thorns
        { id = 24858, kind = "prepare", when = "form",
          text = T("Sobald gelernt: immer in dieser Gestalt kämpfen.", "Once learned: always fight in this form.") },    -- Moonkingestalt / Moonkin Form
        -- Eröffnung ------------------------------------------------------------------------------------------------
        { id = 5176, key = "opener:5176", kind = "opener", when = "ready", once = "target", need = { combat = false },
          text = T("Als ersten Angriff vorzaubern; danach die beiden Dauerschaden-Zauber.", "Pre-cast as your first attack; then both damage-over-time spells.") },    -- Zorn / Wrath
        -- Mehrere Gegner (nur im Flächenmodus; steht vor den DoTs, weil die Reihenfolge der Rang ist) --------------
        { id = 16914, kind = "aoe", when = "ready", hold = true,
          text = T("Ab etwa fünf Gegnern kanalisieren; darunter Dauerschaden verteilen.", "Channel on about five or more enemies; below that spread damage over time.") },    -- Hurrikan / Hurricane
        -- Im Kampf (Reihenfolge = Rang) ----------------------------------------------------------------------------
        { id = 5570, kind = "maintain", when = "dot", refresh = "missing",
          text = T("Fehlt er: setzen. Nie vorzeitig erneuern.", "Missing: apply. Never renew it early.") },    -- Insektenschwarm / Insect Swarm
        { id = 8921, kind = "maintain", when = "dot", refresh = "missing",
          text = T("Fehlt es: setzen. Bei Manamangel weglassen.", "Missing: apply. Drop it when low on mana.") },    -- Mondfeuer / Moonfire
        { id = 770, kind = "maintain", when = "dot", mine = false, refresh = "missing", optional = true, need = { grouped = true },
          text = T("Nur in der Gruppe, wenn es kein anderer Druide hält.", "In a group only, if no other druid keeps it up.") },    -- Feenfeuer / Faerie Fire
        { id = 2912, kind = "priority", when = "ready", need = { counter = { name = "eclipse", min = 1 } },
          text = T("Nur mit einer Ladung von {408248}; nie ohne.", "Only with a charge of {408248}; never without.") },    -- Sternenfeuer / Starfire
        -- Schwelle 10 % Mana: Wowhead; üblich geht der Zauber an einen Heiler.
        { id = 29166, kind = "resource", when = "lowmana", max = 10,
          text = T("Auf dich nur bei fast leerem Mana; sonst für einen Heiler.", "On yourself only when nearly out of mana; else for a healer.") },    -- Anregen / Innervate
        { id = 5176, kind = "filler", when = "filler",
          text = T("Ohne Ladung: lädt {408248} wieder auf.", "Without a charge: recharges {408248}.") },    -- Zorn / Wrath
        -- Situativ -------------------------------------------------------------------------------------------------
        { id = 22812, kind = "situational", when = "manual",
          text = T("Vor {16914}, damit Treffer das Kanalisieren nicht verkürzen.", "Before {16914} so hits don't cut the channel short.") },    -- Baumrinde / Barkskin
        { id = 774, kind = "situational", when = "manual",
          text = T("Beim Leveln vor dem Angriff auf dich.", "While levelling: on yourself before you attack.") },    -- Verjüngung / Rejuvenation
      } },

    ---------------------------------------------------------------------------------------------------------------
    -- Wilder Kampf – Katze
    ---------------------------------------------------------------------------------------------------------------
    { key = "feral", tree = 2, name = T("Wilder Kampf", "Feral Combat"),
      source = "https://www.icy-veins.com/wow-forever/feral-druid-melee-dps-and-tank-pve-rotation-cooldowns-abilities",
      sources = { "https://www.icy-veins.com/wow-forever/feral-druid-leveling",
          "https://www.icy-veins.com/wow-forever/druid-shapeshift-forms",
          "https://www.wowhead.com/forever/guide/classes/druid/feral/rotation-cooldowns-pve-dps" },
      pick = { form = 768 },
      how = T("Gilt in {768}: Halte {770}, {1822} und – mit fünf Combo-Punkten – {1079} auf dem Ziel und baue dazwischen Punkte auf. Auf Höchststufe gehen fünf Punkte und viel Energie in {1328618}, solange {1079} lange genug läuft; dafür sparst du an. {1322605} drückst du bei wenig Energie. Allein eröffnest du aus {5215}.",
              "Applies in {768}: keep {770}, {1822} and – at five combo points – {1079} on the target and build points in between. At max level five points and plenty of energy go into {1328618} while {1079} runs long enough; you pool for that. Press {1322605} when energy is low. Solo you open from {5215}."),
      note = T("Ob du hinter dem Ziel stehst und wie lange es lebt, sieht ezCombat nicht: {5221} als Aufbauer ist ein Schritt zum Einschalten (reine Katzen-Skillung, jemand anderes tankt). Blutungen lohnen nur, wenn das Ziel ihre Dauer überlebt.",
               "ezCombat can't see whether you stand behind the target or how long it lives: {5221} as builder is a step to switch on (pure cat build, someone else tanks). Bleeds only pay off if the target outlives them."),
      steps = {
        -- Vor dem Kampf --------------------------------------------------------------------------------------------
        { id = 1126, kind = "longbuff", buff = "motw", when = "buff",
          text = T("Vor dem Kampf; braucht die Normalgestalt.", "Before combat; needs caster form.") },    -- Mal der Wildnis / Mark of the Wild
        { id = 467, kind = "longbuff", buff = "thorns", when = "buff",
          text = T("Vor dem Kampf auf dich; braucht die Normalgestalt.", "Before combat on yourself; needs caster form.") },    -- Dornen / Thorns
        { id = 768, kind = "prepare", when = "form",
          text = T("Diese Rotation gilt nur in dieser Gestalt.", "This rotation only applies in this form.") },    -- Katzengestalt / Cat Form
        { id = 5215, kind = "prepare", when = "stealth", need = { target = true, solo = true, form = 768 },
          text = T("Allein: anschleichen und von hinten eröffnen.", "Solo: sneak up and open from behind.") },    -- Schleichen / Prowl
        -- Eröffnung (nur verstohlen) -------------------------------------------------------------------------------
        { id = 6785, kind = "opener", when = "ready", once = "target", need = { stealth = true },
          text = T("Verstohlen und von hinten als erster Schlag.", "From stealth and from behind as your first strike.") },    -- Verheeren / Ravage
        { id = 5221, key = "opener:5221", kind = "opener", when = "ready", once = "target", need = { stealth = true, unknown = 6785 },
          text = T("Verstohlen von hinten, solange {6785} fehlt.", "From stealth and behind until you learn {6785}.") },    -- Schreddern / Shred
        -- Im Kampf (Reihenfolge = Rang) ----------------------------------------------------------------------------
        { id = 770, kind = "maintain", when = "dot", mine = false, refresh = "missing",
          text = T("Auf dem Ziel halten; egal von wem es stammt.", "Keep it on the target; anyone's counts.") },    -- Feenfeuer / Faerie Fire [V in Tiergestalt]
        -- Schwellen (Rest der Blutung in Sekunden, Energie): Icy Veins. Nur auf Höchststufe: Die Regel hängt am Talent
        -- Predatory Discipline, die Level-Rotation von Icy Veins kennt den Biss nicht.
        { id = 1328618, key = "bite", kind = "priority", when = "finisher", cp = 5,
          need = { leveling = false, aura = { id = 1079, unit = "target", left = { min = 4 } }, energy = { min = 70 } },
          text = T("Fünf Punkte, {1079} läuft noch, ab 70 Energie.", "Five points, {1079} still running, 70+ energy.") },    -- Wilder Biss / Ferocious Bite
        { id = 1328618, key = "bite:proc", kind = "priority", when = "proc", aura = 16870, cp = 5,
          need = { leveling = false, aura = { id = 1079, unit = "target", left = { min = 4 } }, energy = { min = 35 } },
          text = T("Mit {16870} schon ab 35 Energie.", "With {16870} already at 35 energy.") },    -- Wilder Biss / Ferocious Bite
        { id = 1322605, kind = "resource", when = "ready", need = { energy = { max = 50 } },
          text = T("Erst bei höchstens 50 Energie, sonst verfällt welche.", "Only at 50 energy or less, or some goes to waste.") },    -- Machtverschiebung / Shifting Power
        { id = 5221, key = "proc:5221", kind = "priority", when = "proc", aura = 16870, need = { grouped = true },
          text = T("{16870} dafür ausgeben, wenn du hinter dem Ziel stehst.", "Spend {16870} on it when you stand behind the target.") },    -- Schreddern / Shred
        { id = 1079, key = "rip:level", kind = "maintain", when = "dot", cp = 4, refresh = "missing", need = { leveling = true },
          text = T("Beim Leveln ab vier Punkten, wenn das Ziel lange lebt.", "While levelling from four points if the target lives long.") },    -- Zerfetzen / Rip
        { id = 1079, key = "rip", kind = "maintain", when = "dot", cp = 5, refresh = "missing",
          text = T("Mit fünf Punkten, sobald es nicht mehr liegt.", "At five points once it is no longer up.") },    -- Zerfetzen / Rip
        { id = 1822, kind = "maintain", when = "dot", refresh = "missing",
          text = T("Fehlt er: setzen. Nicht vorzeitig erneuern.", "Missing: apply. Don't renew it early.") },    -- Krallenhieb / Rake
        { id = 5221, key = "filler:5221", kind = "filler", when = "filler", optional = true, need = { grouped = true, cp = { max = 4 } },
          text = T("Aufbauer von hinten (reine Katzen-Skillung).", "Builder from behind (pure cat build).") },    -- Schreddern / Shred
        { id = 1082, kind = "filler", when = "filler", need = { cp = { max = 4 } },
          text = T("Aufbauer; mit fünf Punkten stattdessen Energie sparen.", "Builder; at five points pool energy instead.") },    -- Klaue / Claw
        { id = 1082, key = "filler:1082:early", kind = "filler", when = "filler", need = { unknown = 1328618 },
          text = T("Solange {1328618} fehlt: auch mit vollen Punkten.", "Until you learn {1328618}: at full points too.") },    -- Klaue / Claw
        { id = 1082, key = "filler:1082:level", kind = "filler", when = "filler", need = { leveling = true },
          text = T("Beim Leveln auch mit vollen Punkten.", "While levelling at full points too.") },    -- Klaue / Claw
        -- Situativ -------------------------------------------------------------------------------------------------
        { id = 9005, kind = "situational", when = "manual",
          text = T("Verstohlen, wenn du die Betäubung brauchst.", "From stealth when you need the stun.") },    -- Anspringen / Pounce
        { id = 29166, kind = "situational", when = "manual",
          text = T("Letzter Ausweg bei leerem Mana; verlässt die Gestalt.", "Last resort when out of mana; leaves your form.") },    -- Anregen / Innervate
      } },

    ---------------------------------------------------------------------------------------------------------------
    -- Wilder Kampf – Bär
    ---------------------------------------------------------------------------------------------------------------
    { key = "feral_bear", tree = 2, name = T("Wilder Kampf (Bär)", "Feral Combat (Bear)"),
      source = "https://www.icy-veins.com/wow-forever/feral-druid-melee-dps-and-tank-pve-rotation-cooldowns-abilities",
      sources = { "https://www.icy-veins.com/wow-forever/feral-druid-leveling",
          "https://www.icy-veins.com/wow-forever/druid-shapeshift-forms",
          "https://www.wowhead.com/forever/guide/classes/druid/feral/rotation-cooldowns-pve-tank" },
      how = T("Gilt in {5487} bzw. {9634}: {407995} bei jeder Abklingzeit, jede andere Lücke füllt {1328617}; volle Stapel dürfen nie auslaufen. {770} und {99} hältst du auf dem Ziel. {6807} läuft nebenher über den nächsten Schlag – erst mit Wutpolster, damit {407995} bezahlbar bleibt. Im Flächenmodus ersetzt {779} das {1328617}; beim Leveln ist {779} der Füller, bis {1328617} gelernt ist.",
              "Applies in {5487} or {9634}: {407995} on every cooldown, every other gap goes to {1328617}; full stacks must never drop. Keep {770} and {99} on the target. {6807} runs alongside on your next swing – only with rage to spare so {407995} stays affordable. In AoE mode {779} replaces {1328617}; while levelling {779} is the filler until you learn {1328617}."),
      note = T("Gegnerzahl, Bedrohung und eingehender Schaden sind unsichtbar: Verteidigung steht nur als Liste da. {99} ist unnötig, wenn ein Krieger seinen Ruf hält. Die Quellen ordnen verschieden: Hier rettet {1328617} erst volle Stapel, dann kommt {407995}.",
               "Enemy count, threat and incoming damage are invisible: defensives are list only. {99} is not needed while a warrior keeps his shout up. Sources differ in order: here {1328617} first saves full stacks, then comes {407995}."),
      steps = {
        -- Vor dem Kampf --------------------------------------------------------------------------------------------
        { id = 1126, kind = "longbuff", buff = "motw", when = "buff",
          text = T("Vor dem Kampf; braucht die Normalgestalt.", "Before combat; needs caster form.") },    -- Mal der Wildnis / Mark of the Wild
        { id = 467, kind = "longbuff", buff = "thorns", when = "buff",
          text = T("Vor dem Kampf auf dich; stark gegen viele Gegner.", "Before combat on yourself; strong against many enemies.") },    -- Dornen / Thorns
        { id = 5487, kind = "prepare", when = "form", need = { unknown = 9634 },
          text = T("Diese Rotation gilt nur in dieser Gestalt.", "This rotation only applies in this form.") },    -- Bärengestalt / Bear Form
        { id = 9634, kind = "prepare", when = "form",
          text = T("Löst {5487} ab, sobald gelernt.", "Replaces {5487} once learned.") },    -- Terrorbärengestalt / Dire Bear Form
        -- Eröffnung ------------------------------------------------------------------------------------------------
        { id = 5229, key = "opener:5229", kind = "opener", when = "ready", once = "target", need = { combat = false },
          text = T("Kurz vor dem Angriff, um mit Wut zu starten.", "Right before you attack to start with rage.") },    -- Wutanfall / Enrage
        -- Im Kampf (Reihenfolge = Rang) ----------------------------------------------------------------------------
        -- Normalgestalt nur, solange keine der beiden Bärengestalten gelernt ist: Die höhere löst die erste ab [V].
        { id = 8921, key = "caster:8921", kind = "maintain", when = "dot", refresh = "missing", need = { unknown = { 5487, 9634 } },
          text = T("Vor der ersten Tiergestalt: auf dem Ziel halten.", "Before your first animal form: keep it on the target.") },    -- Mondfeuer / Moonfire
        -- Steht vor Debuffs und Biss (Icy Veins Leveln: allein auch im Kampf bei Wutmangel); weiter hinten käme er nur,
        -- wenn alles andere liegt oder abklingt.
        { id = 5229, key = "resource:5229", kind = "resource", when = "ready", need = { solo = true, combat = true, rage = { max = 10 } },
          guess = T("„Wutmangel“ ist als höchstens 10 Wut geschätzt.", "“Starved for rage” is estimated as at most 10 rage."),
          text = T("Allein bei Wutmangel; senkt deine Rüstung.", "Solo when starved for rage; lowers your armor.") },    -- Wutanfall / Enrage
        { id = 770, kind = "maintain", when = "dot", mine = false, refresh = "missing",
          text = T("Auf dem Ziel halten; egal von wem es stammt.", "Keep it on the target; anyone's counts.") },    -- Feenfeuer / Faerie Fire [V in Tiergestalt]
        { id = 99, kind = "maintain", when = "dot", mine = false, refresh = "missing",
          text = T("Fehlt es: setzen – außer jemand hält es schon.", "Missing: apply – unless someone already keeps it up.") },    -- Demoralisierendes Gebrüll / Demoralizing Roar
        { id = 1328617, key = "rescue:1328617", kind = "maintain", when = "ready",
          need = { aura = { id = 1328617, unit = "target", min = 5, left = { max = 3 } } },
          guess = T("„Läuft gleich aus“ ist als höchstens 3 Sek. Rest geschätzt.", "“About to expire” is estimated as at most 3 sec left."),
          text = T("Volle Stapel laufen gleich aus: erst retten.", "Full stacks about to drop: save them first.") },    -- Aufschlitzen / Lacerate
        { id = 407995, kind = "priority", when = "ready",
          text = T("Bei jeder Abklingzeit; nie verzögern.", "On every cooldown; never delay it.") },    -- Urtümlicher Biss / Primal Bite
        { id = 779, kind = "aoe", when = "ready",
          text = T("Gegen mehrere Gegner statt {1328617}.", "Against several enemies instead of {1328617}.") },    -- Prankenhieb / Swipe
        { id = 1328617, kind = "filler", when = "filler",
          text = T("Stapel aufbauen, danach jede freie Lücke.", "Build stacks, then every free gap.") },    -- Aufschlitzen / Lacerate
        { id = 779, key = "filler:779", kind = "filler", when = "filler", need = { unknown = 1328617 },
          text = T("Lückenfüller, solange {1328617} fehlt.", "Gap filler until you learn {1328617}.") },    -- Prankenhieb / Swipe
        -- Schwelle 35 Wut: Icy Veins und Wowhead (der ersetzte Schlag bringt keine Wut).
        { id = 6807, key = "side:6807", kind = "resource", when = "rage", min = 35, side = true, need = { queued = false },
          text = T("Nebenher ab 35 Wut; der Biss muss bezahlbar bleiben.", "Alongside at 35+ rage; the bite must stay affordable.") },    -- Zermalmen / Maul
        { id = 6807, key = "filler:6807", kind = "filler", when = "filler", need = { unknown = { 779, 1328617 }, queued = false },
          text = T("Dein einziger Angriff, bis {779} gelernt ist.", "Your only attack until you learn {779}.") },    -- Zermalmen / Maul
        { id = 5176, key = "caster:5176", kind = "filler", when = "filler", need = { unknown = { 5487, 9634 } },
          text = T("Vor der ersten Tiergestalt der Lückenfüller.", "Your gap filler before your first animal form.") },    -- Zorn / Wrath
        -- Situativ -------------------------------------------------------------------------------------------------
        { id = 22812, kind = "situational", when = "manual",
          text = T("Verteidigung, wenn viel Schaden kommt.", "Defensive when heavy damage comes in.") },    -- Baumrinde / Barkskin
        { id = 22842, kind = "situational", when = "manual",
          text = T("Notfall: wandelt Wut in Heilung.", "Emergency: turns rage into healing.") },    -- Rasende Regeneration / Frenzied Regeneration
        { id = 5209, kind = "situational", when = "manual",
          text = T("Notfall: zwingt alle Gegner um dich auf dich.", "Emergency: forces all nearby enemies onto you.") },    -- Herausforderndes Gebrüll / Challenging Roar
      } },

    ---------------------------------------------------------------------------------------------------------------
    -- Wiederherstellung (Heiler: Buffs, Vorbereitung und der Schaden allein)
    ---------------------------------------------------------------------------------------------------------------
    { key = "restoration", tree = 3, name = T("Wiederherstellung", "Restoration"),
      source = "https://www.icy-veins.com/wow-forever/restoration-druid-healer-pve-rotation-cooldowns-abilities",
      sources = { "https://www.icy-veins.com/wow-forever/restoration-druid-leveling" },
      how = T("Heilen ist keine Rotation: Wen du wann heilst, hängt von der Gruppe ab, und deren Leben sieht ezCombat im Kampf nicht – die Heilzauber stehen deshalb nur als Liste hier. Vorgeschlagen werden die Buffs vor dem Kampf und der Schaden allein: Pull mit vorgezaubertem {5176}, {8921} halten, {5570} falls geskillt, sonst {5176}.",
              "Healing is not a rotation: whom you heal and when depends on the group, and ezCombat can't see their health in combat – so the healing spells are list only. Suggested are your buffs before combat and solo damage: pull with a pre-cast {5176}, keep {8921} up, {5570} if talented, otherwise {5176}."),
      note = T("Im Schlachtzug nebenbei {5570} auf dem Boss halten und {5176} nur im Leerlauf wirken; {8921} ist dort zu teuer. Pausen sparen Mana.",
               "In a raid keep {5570} on the boss on the side and cast {5176} only when idle; {8921} costs too much there. Pauses save mana."),
      steps = {
        -- Vor dem Kampf --------------------------------------------------------------------------------------------
        { id = 1126, kind = "longbuff", buff = "motw", when = "buff",
          text = T("Vor dem Kampf auf dich und die Gruppe.", "Before combat on yourself and the group.") },    -- Mal der Wildnis / Mark of the Wild
        { id = 467, kind = "longbuff", buff = "thorns", when = "buff", need = { solo = true },
          text = T("Allein auf dich; in der Gruppe gehört es auf den Tank.", "Solo on yourself; in a group it belongs on the tank.") },    -- Dornen / Thorns
        -- Eröffnung ------------------------------------------------------------------------------------------------
        { id = 5176, key = "opener:5176", kind = "opener", when = "ready", once = "target", need = { combat = false, solo = true },
          text = T("Allein als ersten Angriff vorzaubern.", "Solo: pre-cast as your first attack.") },    -- Zorn / Wrath
        -- Mehrere Gegner (nur im Flächenmodus) ---------------------------------------------------------------------
        { id = 16914, kind = "aoe", when = "ready", hold = true, need = { solo = true },
          text = T("Allein ab drei Gegnern kanalisieren.", "Solo: channel on three or more enemies.") },    -- Hurrikan / Hurricane
        -- Im Kampf (Reihenfolge = Rang) ----------------------------------------------------------------------------
        { id = 8921, kind = "maintain", when = "dot", refresh = "missing", need = { solo = true },
          text = T("Allein auf dem Ziel halten; in der Gruppe zu teuer.", "Solo: keep it on the target; too costly in a group.") },    -- Mondfeuer / Moonfire
        { id = 5570, kind = "maintain", when = "dot", refresh = "missing", need = { solo = true },
          text = T("Falls geskillt: auf dem Ziel halten.", "If talented: keep it on the target.") },    -- Insektenschwarm / Insect Swarm
        -- In der Gruppe erst im Kampf: Der Heiler eröffnet dort nicht.
        { id = 5570, key = "group:5570", kind = "maintain", when = "dot", refresh = "missing", need = { grouped = true, combat = true },
          text = T("In der Gruppe nebenbei auf dem Boss halten.", "In a group keep it on the boss on the side.") },    -- Insektenschwarm / Insect Swarm
        { id = 29166, kind = "resource", when = "lowmana", max = 30,
          guess = T("„Ein guter Teil des Manas ist weg“ ist als höchstens 30 % geschätzt.", "“A good part of your mana is gone” is estimated as at most 30%."),
          text = T("Auf dich, wenn ein guter Teil des Manas fehlt.", "On yourself once a good part of your mana is gone.") },    -- Anregen / Innervate
        { id = 5176, kind = "filler", when = "filler", need = { solo = true },
          text = T("Allein dein Lückenfüller.", "Your gap filler when solo.") },    -- Zorn / Wrath
        { id = 5176, key = "group:5176", kind = "filler", when = "filler", need = { grouped = true, combat = true },
          text = T("In der Gruppe nur im Kampf und nur im Leerlauf.", "In a group only in combat and only when idle.") },    -- Zorn / Wrath
        -- Situativ: Heilung und Kontrolle (nie vorgeschlagen) ------------------------------------------------------
        { id = 774, kind = "situational", when = "manual",
          text = T("Auf den Tank, bei anhaltendem Schaden; allein vor dem Angriff.", "On the tank, under steady damage; solo before you attack.") },    -- Verjüngung / Rejuvenation
        { id = 8936, kind = "situational", when = "manual",
          text = T("Auf Verletzte; auf dem Tank dauerhaft halten.", "On the injured; keep it rolling on the tank.") },    -- Nachwachsen / Regrowth
        { id = 18562, kind = "situational", when = "manual",
          text = T("Günstige Sofortheilung bei plötzlichem Schaden.", "Cheap instant heal for sudden damage.") },    -- Rasche Heilung / Swiftmend
        { id = 5185, kind = "situational", when = "manual",
          text = T("Selten: nur wenn {774} und {8936} schon laufen und der Tank weiter Schaden nimmt.", "Rarely: only when {774} and {8936} already run and the tank keeps taking damage.") },    -- Heilende Berührung / Healing Touch
        { id = 408120, kind = "situational", when = "manual",
          text = T("Wenn die ganze Gruppe tief ist, am besten mit {16870}.", "When the whole group is low, ideally with {16870}.") },    -- Wildwuchs / Wild Growth
        { id = 740, kind = "situational", when = "manual",
          text = T("Großer Notfall der Gruppe, eher im Dungeon.", "Major group emergency, mostly in dungeons.") },    -- Gelassenheit / Tranquility
        { id = 339, kind = "situational", when = "manual",
          text = T("Allein: Gegner festhalten und Abstand gewinnen.", "Solo: root enemies and gain distance.") },    -- Wucherwurzeln / Entangling Roots [V]
        { id = 22812, kind = "situational", when = "manual",
          text = T("Zusammen mit {16914} oder wenn du Schaden nimmst.", "Together with {16914} or when you take damage.") },    -- Baumrinde / Barkskin
      } },
})
