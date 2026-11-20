local _, ns = ...
local T = ns.RotationData.T

-- Magier (MAGE): Rotationen je Talentbaum und Spielweise für WoW Forever (Format: Kopf von RotationData.lua).
-- Quellen: Icy Veins, WoW Forever, abgerufen am 13.11.2026 – nur Fakten (Rangfolge, Bedingungen), alle Texte in
-- eigenen Worten. Stand der Seiten in Klammern.
--   Arkan:  https://www.icy-veins.com/wow-forever/arcane-mage-ranged-dps-pve-rotation-cooldowns-abilities (10.11.2026)
--           https://www.icy-veins.com/wow-forever/arcane-mage-leveling (04.11.2026)
--           https://www.icy-veins.com/wow-forever/arcane-mage-ranged-dps-pve-spec-builds-talents (04.11.2026)
--           https://www.icy-veins.com/wow-forever/arcane-mage-ranged-dps-pve-guide (10.11.2026)
--   Feuer:  https://www.icy-veins.com/wow-forever/fire-mage-ranged-dps-pve-rotation-cooldowns-abilities (10.11.2026)
--           https://www.icy-veins.com/wow-forever/fire-mage-leveling (04.11.2026)
--           https://www.icy-veins.com/wow-forever/fire-mage-ranged-dps-pve-spec-builds-talents (04.11.2026)
--           https://www.icy-veins.com/wow-forever/fire-mage-ranged-dps-pve-guide (10.11.2026)
--   Frost:  https://www.icy-veins.com/wow-forever/frost-mage-ranged-dps-pve-rotation-cooldowns-abilities (09.11.2026)
--           https://www.icy-veins.com/wow-forever/frost-mage-leveling (10.11.2026)
--           https://www.icy-veins.com/wow-forever/frost-mage-ranged-dps-pve-spec-builds-talents (10.11.2026)
--           https://www.icy-veins.com/wow-forever/frost-mage-ranged-dps-pve-guide (10.11.2026)
-- Dauer-Buffs, Manastein und der Umgang mit Mana stehen nur auf der Frost-Seite; sie gelten klassenweit und sind
-- deshalb auch bei Arkan und Feuer eingetragen. Nichts stammt aus einem Addon.
-- Zauber-IDs: Rang 1 aus dem früheren Bestand (RotationData.lua und ezCore/SpellData.lua, gegen
-- nether.wowhead.com/forever geprüft); übrige klassische Rang-1-IDs und die Gegenstands-IDs der Manasteine (5514,
-- 5513, 8007, 8008, aus dem klassischen Spiel): [B] laut Client-Tabellen (wago.tools, wowf 1.60.1.70938; Item,
-- ItemSparse, SpellName) gibt es alle; jede Zauber- und Gegenstands-ID hier gleicht die wago-Prüfung in sh
-- tools/test.sh ab (Kennung, Klasse, Rang; Gesamtreview 18.11.2026, T14-NH6). Eislanze steht mit der Grund-ID 1312002
-- (Rang 1, Talent; vorher 400640, Rang 2 ab Stufe 28 – die Schlüssel der Schritte bleiben für gemerkte Anpassungen).
-- Name, Symbol, Ränge, gelernt, Lernstufe, Kosten, Zauberzeit, Abklingzeit und Dauer liefert der Client zur Laufzeit.
--
-- Aufbau: je Talentbaum bleibt der bisherige Schlüssel (arcane, fire, frost) die Rotation für die Höchststufe.
--   arcane_level, fire_level   beim Leveln (pick.leveling)
--   fire_deep                  Feuer mit dem Talent am Ende des Baums (pick.known), fire = Aufbau ohne dieses Talent
-- Rüstung: ein Schritt für die Gruppe „armor“ – ezCore wählt die beste gelernte (Frost- → Eis- → Magische Rüstung).
-- Fläche: ezCombat kann Gegner nicht zählen. Die Flächenschritte stehen vorn in der Liste und werden nur im
--   Flächenmodus bewertet (den schaltet der Nutzer); Schritte mit when = "aoe" stehen nur in der Liste.
--
-- [V] = Zauber- oder Gegenstands-ID bzw. Annahme nicht im Spiel bestätigt (/ez test meldet unbekannte IDs).
-- Annahmen ohne Zahl in der Quelle: Feuerverwundbarkeit ab 6 s Rest erneuern; Arkanschlag beim Leveln höchstens
--   dreimal (Arkan, Quelle: ein- bis dreimal) bzw. zweimal (Feuer, Quelle: ein- bis zweimal).
-- Bedarf:
--   * Aura-ID des Schadensbonus der Eisbarriere („Frigid Power“): bis dahin prüft der Schritt die Schild-Aura.
--   * need.seen kennt nur Buffs des Spielers; ob das Talent hinter der Feuerverwundbarkeit gelernt ist, lässt sich
--     nicht prüfen – beim Leveln ist der Zauber deshalb Füller, der Schritt mit dem Debuff steht nur auf Höchststufe.
--   * Stapel „höchstens n“ für einen eigenen Buff gibt es nur über need.aura an einem zweiten Schritt.

ns.RotationData.Add("MAGE", {
    -----------------------------------------------------------------------------------------------------------------
    -- Arkan, Höchststufe
    -----------------------------------------------------------------------------------------------------------------
    { key = "arcane", tree = 1, name = T("Arkan", "Arcane"),
      source = "https://www.icy-veins.com/wow-forever/arcane-mage-ranged-dps-pve-rotation-cooldowns-abilities",
      sources = { "https://www.icy-veins.com/wow-forever/arcane-mage-ranged-dps-pve-spec-builds-talents",
                  "https://www.icy-veins.com/wow-forever/arcane-mage-ranged-dps-pve-guide",
                  "https://www.icy-veins.com/wow-forever/frost-mage-ranged-dps-pve-rotation-cooldowns-abilities" },
      pick = { leveling = false },
      how = T("Den Kampf eröffnet ein vorgezauberter {11366}. Danach gilt eine Rangfolge ohne festen Takt: {11366} sofort bei drei Stapeln {400624}, {2136} baut diese Stapel auf, {1326079} sobald bereit, {5143} nur mit {400588}. {400574} füllt jede Lücke und hält dabei seinen eigenen Stapel-Buff oben. Buffs und Rüstung gehören vor den Kampf.",
              "A pre-cast {11366} opens the fight. After that it is a priority list without a fixed cycle: {11366} at once at three stacks of {400624}, {2136} builds those stacks, {1326079} whenever ready, {5143} only with {400588}. {400574} fills every gap and keeps its own stacking buff up. Buffs and armor belong before the fight."),
      note = T("Für {12042} nennt die Quelle keine Regel – der Schritt ist aus, bis du ihn einschaltest. Gegner zählen kann ezCombat nicht: Fläche gibt es nur im Flächenmodus.",
               "The source gives no rule for {12042} – the step is off until you turn it on. ezCombat can't count enemies: AoE is suggested in AoE mode only."),
      steps = {
        -- Vor dem Kampf ---------------------------------------------------------------------------------------------
        { id = 1459, kind = "longbuff", buff = "int", when = "buff",
          text = T("Vor dem Kampf auf dich und die Gruppe.", "Before combat on yourself and the group.") },    -- Arkane Intelligenz / Arcane Intellect
        { id = 6117, kind = "longbuff", buff = "armor", when = "buff",
          text = T("Vor dem Kampf; es zählt die beste gelernte Rüstung.", "Before combat; your best learned armor counts.") },    -- Magische Rüstung / Mage Armor
        { id = 10054, kind = "prepare", when = "item", item = { 8008 }, optional = true,
          text = T("Einen Manastein für lange Kämpfe herstellen.", "Conjure a mana gem for long fights.") },    -- Manarubin herbeizaubern / Conjure Mana Ruby [V]
        { id = 10053, kind = "prepare", when = "item", item = { 8007 }, optional = true, need = { unknown = 10054 },
          text = T("Manastein herstellen, solange der bessere fehlt.", "Conjure a mana gem until you learn the better one.") },    -- Manacitrin herbeizaubern / Conjure Mana Citrine [V]
        { id = 3552, kind = "prepare", when = "item", item = { 5513 }, optional = true, need = { unknown = { 10054, 10053 } },
          text = T("Manastein herstellen, solange der bessere fehlt.", "Conjure a mana gem until you learn the better one.") },    -- Manajade herbeizaubern / Conjure Mana Jade [V]
        { id = 759, kind = "prepare", when = "item", item = { 5514 }, optional = true, need = { unknown = { 10054, 10053, 3552 } },
          text = T("Manastein herstellen, solange der bessere fehlt.", "Conjure a mana gem until you learn the better one.") },    -- Manaachat herbeizaubern / Conjure Mana Agate [V]
        -- Mehrere Gegner (nur im Flächenmodus; stehen vorn, weil sie dann die Einzelziel-Liste ersetzen) ------------
        { id = 2120, kind = "aoe", when = "ready", once = "combat",
          text = T("Eröffnet gegen mehrere Gegner; danach nah an die Gegner heran.", "Opens against several enemies; then move close to the enemies.") },    -- Flammenstoß / Flamestrike
        { id = 1449, kind = "aoe", when = "ready",
          text = T("Immer wieder wirken; lohnt erst bei mehr als drei Gegnern.", "Cast it over and over; only worth it against more than three enemies.") },    -- Arkane Explosion / Arcane Explosion
        { id = 120, kind = "aoe", when = "aoe",
          text = T("Allein: Gegner bündeln und verlangsamen.", "Solo: bunch the enemies up and slow them.") },    -- Kältekegel / Cone of Cold
        { id = 10, kind = "aoe", when = "aoe",
          text = T("Aus der Ferne, wenn der Nahkampf zu gefährlich ist.", "From range when melee range is unsafe.") },    -- Blizzard / Blizzard
        -- Eröffnung -------------------------------------------------------------------------------------------------
        { id = 11366, kind = "opener", when = "ready", once = "target", need = { combat = false },
          text = T("Als ersten Zauber vorzaubern.", "Pre-cast it as your first spell.") },    -- Pyroschlag / Pyroblast
        -- Abklingzeiten ---------------------------------------------------------------------------------------------
        { id = 12042, kind = "cooldown", burst = true, when = "ready", optional = true, need = { combat = true },
          text = T("Für starke Momente; die Quelle nennt keine Regel – nach Lage.", "For big moments; the source gives no rule – use as needed.") },    -- Arkane Macht / Arcane Power
        { id = 12043, kind = "cooldown", when = "manual",
          text = T("Mehrere Gegner: macht den zweiten {2120} sofort. Sonst für Bewegung.", "Several enemies: makes the second {2120} instant. Else for movement.") },    -- Geistesgegenwart / Presence of Mind
        -- Im Kampf (Reihenfolge = Rang) -----------------------------------------------------------------------------
        { id = 11366, kind = "priority", when = "proc", aura = 400624, stacks = 3,
          text = T("Sofort bei drei Stapeln {400624} – sonst verfallen weitere.", "At once at three stacks of {400624} – more would be wasted.") },    -- Pyroschlag / Pyroblast
        { id = 2136, kind = "priority", when = "ready",
          text = T("Sobald bereit: baut {400624} auf.", "Whenever ready: builds {400624}.") },    -- Feuerschlag / Fire Blast
        { id = 1326079, kind = "priority", when = "ready",
          text = T("Sobald die Abklingzeit vorbei ist.", "Whenever off cooldown.") },    -- Arkaner Zorn / Arcane Wrath
        { id = 5143, kind = "priority", when = "proc", aura = 400588,
          text = T("Nur mit {400588}, wenn nichts Höheres bereit ist.", "Only with {400588} when nothing higher is ready.") },    -- Arkane Geschosse / Arcane Missiles
        { id = 12051, kind = "resource", when = "lowmana", max = 5,
          text = T("Bei fast leerem Mana, wenn du ungestört kanalisieren kannst.", "Nearly out of mana, when you can channel undisturbed.") },    -- Hervorrufung / Evocation
        { id = 400574, kind = "filler", when = "filler",
          text = T("Lückenfüller; hält dabei die eigene Stapel-Stärkung oben.", "Gap filler; keeps its own stacking bonus up.") },    -- Arkanschlag / Arcane Blast
        { id = 116, kind = "filler", when = "filler", need = { unknown = 400574 },
          text = T("Lückenfüller, solange {400574} fehlt.", "Gap filler until you learn {400574}.") },    -- Frostblitz / Frostbolt
        { id = 133, kind = "filler", when = "filler", need = { unknown = { 400574, 116 } },
          text = T("Lückenfüller ganz am Anfang, solange {116} fehlt.", "Gap filler at the very start until you learn {116}.") },    -- Feuerball / Fireball
        -- Situativ --------------------------------------------------------------------------------------------------
        { id = 7302, kind = "situational", when = "manual",
          text = T("Statt {6117}, wenn dich Nahkämpfer treffen.", "Instead of {6117} when melee attackers hit you.") },    -- Eisrüstung / Ice Armor
      } },

    -----------------------------------------------------------------------------------------------------------------
    -- Arkan, Leveln
    -----------------------------------------------------------------------------------------------------------------
    { key = "arcane_level", tree = 1, name = T("Arkan (Leveln)", "Arcane (levelling)"),
      source = "https://www.icy-veins.com/wow-forever/arcane-mage-leveling",
      sources = { "https://www.icy-veins.com/wow-forever/arcane-mage-ranged-dps-pve-rotation-cooldowns-abilities",
                  "https://www.icy-veins.com/wow-forever/frost-mage-ranged-dps-pve-rotation-cooldowns-abilities" },
      pick = { leveling = true },
      how = T("Je Gegner eine kurze Folge: {116} aus voller Entfernung, dann {1326079} und wenige {400574}, bis {400588} auslöst und {5143} folgt. {400574} wird mit jedem Stapel teurer – deshalb nur wenige Male wirken und den Stapel-Buff auslaufen lassen. {2136} steht am Ende zum Erledigen. Kommt der Gegner heran, hilft {122}; fast tote Gegner erledigt der Zauberstab.",
              "A short sequence per enemy: {116} from full range, then {1326079} and a few {400574} until {400588} procs and {5143} follows. {400574} costs more with every stack – cast it only a few times and let the stacking buff drop. {2136} comes last to finish. If the enemy reaches you, {122} helps; nearly dead enemies are for your wand."),
      note = T("Leben des Ziels und Abstand sieht ezCombat nicht – Zauberstab und {122} stehen nur als Text. Was nach dem letzten {400574} bleibt, nennt die Quelle nicht; hier ist es {116}.",
               "ezCombat can't see target health or distance – wand and {122} are text only. The source doesn't say what follows the last {400574}; here it is {116}."),
      steps = {
        -- Vor dem Kampf ---------------------------------------------------------------------------------------------
        { id = 1459, kind = "longbuff", buff = "int", when = "buff",
          text = T("Vor dem Kampf auf dich und die Gruppe.", "Before combat on yourself and the group.") },    -- Arkane Intelligenz / Arcane Intellect
        { id = 6117, kind = "longbuff", buff = "armor", when = "buff",
          text = T("Vor dem Kampf; es zählt die beste gelernte Rüstung.", "Before combat; your best learned armor counts.") },    -- Magische Rüstung / Mage Armor
        { id = 10054, kind = "prepare", when = "item", item = { 8008 }, optional = true,
          text = T("Einen Manastein für lange Kämpfe herstellen.", "Conjure a mana gem for long fights.") },    -- Manarubin herbeizaubern / Conjure Mana Ruby [V]
        { id = 10053, kind = "prepare", when = "item", item = { 8007 }, optional = true, need = { unknown = 10054 },
          text = T("Manastein herstellen, solange der bessere fehlt.", "Conjure a mana gem until you learn the better one.") },    -- Manacitrin herbeizaubern / Conjure Mana Citrine [V]
        { id = 3552, kind = "prepare", when = "item", item = { 5513 }, optional = true, need = { unknown = { 10054, 10053 } },
          text = T("Manastein herstellen, solange der bessere fehlt.", "Conjure a mana gem until you learn the better one.") },    -- Manajade herbeizaubern / Conjure Mana Jade [V]
        { id = 759, kind = "prepare", when = "item", item = { 5514 }, optional = true, need = { unknown = { 10054, 10053, 3552 } },
          text = T("Manastein herstellen, solange der bessere fehlt.", "Conjure a mana gem until you learn the better one.") },    -- Manaachat herbeizaubern / Conjure Mana Agate [V]
        -- Mehrere Gegner (nur im Flächenmodus) ----------------------------------------------------------------------
        { id = 2120, kind = "aoe", when = "ready", once = "combat",
          text = T("Eröffnet gegen mehrere Gegner; danach nah an die Gegner heran.", "Opens against several enemies; then move close to the enemies.") },    -- Flammenstoß / Flamestrike
        { id = 1449, kind = "aoe", when = "ready",
          text = T("Immer wieder wirken; lohnt erst bei mehr als drei Gegnern.", "Cast it over and over; only worth it against more than three enemies.") },    -- Arkane Explosion / Arcane Explosion
        { id = 120, kind = "aoe", when = "aoe",
          text = T("Allein: Gegner bündeln und verlangsamen.", "Solo: bunch the enemies up and slow them.") },    -- Kältekegel / Cone of Cold
        { id = 10, kind = "aoe", when = "aoe",
          text = T("Aus der Ferne, wenn der Nahkampf zu gefährlich ist.", "From range when melee range is unsafe.") },    -- Blizzard / Blizzard
        -- Eröffnung -------------------------------------------------------------------------------------------------
        { id = 11366, kind = "opener", when = "ready", once = "target", need = { combat = false },
          text = T("Sobald gelernt: als ersten Zauber vorzaubern.", "Once learned: pre-cast it as your first spell.") },    -- Pyroschlag / Pyroblast
        { id = 116, kind = "opener", when = "ready", once = "target", need = { combat = false, unknown = 11366 },
          text = T("Aus voller Entfernung eröffnen; verlangsamt den Gegner.", "Open from full range; slows the enemy.") },    -- Frostblitz / Frostbolt
        -- Abklingzeiten ---------------------------------------------------------------------------------------------
        { id = 12042, kind = "cooldown", burst = true, when = "ready", optional = true, need = { combat = true },
          text = T("Für starke Momente; die Quelle nennt keine Regel – nach Lage.", "For big moments; the source gives no rule – use as needed.") },    -- Arkane Macht / Arcane Power
        { id = 12043, kind = "cooldown", when = "manual",
          text = T("Mehrere Gegner: macht den zweiten {2120} sofort. Sonst für Bewegung.", "Several enemies: makes the second {2120} instant. Else for movement.") },    -- Geistesgegenwart / Presence of Mind
        -- Im Kampf (Reihenfolge = Rang) -----------------------------------------------------------------------------
        { id = 11366, kind = "priority", when = "proc", aura = 400624, stacks = 3,
          text = T("Sofort bei drei Stapeln {400624}.", "At once at three stacks of {400624}.") },    -- Pyroschlag / Pyroblast
        { id = 2136, kind = "priority", when = "ready", need = { seen = 400624 },
          text = T("Mit dem Talent hinter {400624}: sobald bereit.", "With the talent behind {400624}: whenever ready.") },    -- Feuerschlag / Fire Blast
        { id = 1326079, kind = "priority", when = "ready",
          text = T("Sobald die Abklingzeit vorbei ist.", "Whenever off cooldown.") },    -- Arkaner Zorn / Arcane Wrath
        { id = 5143, kind = "priority", when = "proc", aura = 400588,
          text = T("Nur mit {400588}.", "Only with {400588}.") },    -- Arkane Geschosse / Arcane Missiles
        { id = 400574, kind = "maintain", when = "buff", refresh = "missing",
          text = T("Einmal wirken, sobald die Stapel-Stärkung ausgelaufen ist.", "Cast once after the stacking bonus has dropped.") },    -- Arkanschlag / Arcane Blast
        { id = 400574, key = "maintain:400574-stack", kind = "maintain", when = "ready", need = { aura = { id = 400574, max = 2 } },    -- Annahme: Obergrenze der Quelle
          text = T("Höchstens dreimal in Folge – jeder Stapel kostet mehr Mana.", "Three in a row at most – each stack costs more mana.") },    -- Arkanschlag / Arcane Blast
        { id = 12051, kind = "resource", when = "lowmana", max = 5,
          text = T("Bei fast leerem Mana, wenn du ungestört kanalisieren kannst.", "Nearly out of mana, when you can channel undisturbed.") },    -- Hervorrufung / Evocation
        { id = 116, kind = "filler", when = "filler",
          text = T("Lückenfüller, solange {400574} fehlt oder seine Stärkung auslaufen soll.", "Gap filler without {400574} or while its bonus should drop.") },    -- Frostblitz / Frostbolt
        { id = 133, kind = "filler", when = "filler", need = { unknown = 116 },
          text = T("Lückenfüller ganz am Anfang, solange {116} fehlt.", "Gap filler at the very start until you learn {116}.") },    -- Feuerball / Fireball
        -- Situativ --------------------------------------------------------------------------------------------------
        { id = 122, kind = "situational", when = "manual",
          text = T("Gegner am Leib: einfrieren, Abstand, dann {1326079} und {2136}.", "Enemy on you: freeze, step back, then {1326079} and {2136}.") },    -- Frostnova / Frost Nova [V]
        { id = 2136, kind = "situational", when = "manual",
          text = T("Ohne das Talent hinter {400624}: nur zum Erledigen am Ende.", "Without the talent behind {400624}: only to finish at the end.") },    -- Feuerschlag / Fire Blast
        { id = 5019, kind = "situational", when = "manual",
          text = T("Zauberstab: fast tote Gegner ohne Mana erledigen.", "Wand: finish nearly dead enemies without mana.") },    -- Schießen / Shoot [V]
        { id = 7302, kind = "situational", when = "manual",
          text = T("Statt {6117}, wenn dich Nahkämpfer treffen.", "Instead of {6117} when melee attackers hit you.") },    -- Eisrüstung / Ice Armor
      } },

    -----------------------------------------------------------------------------------------------------------------
    -- Feuer, Höchststufe, ohne das Talent am Ende des Baums (Füller aus zwei Schulen)
    -----------------------------------------------------------------------------------------------------------------
    { key = "fire", tree = 2, name = T("Feuer (Frostfeuer)", "Fire (Frostfire)"),
      source = "https://www.icy-veins.com/wow-forever/fire-mage-ranged-dps-pve-rotation-cooldowns-abilities",
      sources = { "https://www.icy-veins.com/wow-forever/fire-mage-ranged-dps-pve-spec-builds-talents",
                  "https://www.icy-veins.com/wow-forever/fire-mage-ranged-dps-pve-guide",
                  "https://www.icy-veins.com/wow-forever/frost-mage-ranged-dps-pve-rotation-cooldowns-abilities" },
      pick = { leveling = false, unknown = 11129 },
      how = T("Eröffnung: {11366} vorzaubern, dann {2948}, bis {22959} fünf Stapel hat. Der Debuff wird vor seinem Ablauf mit einem {2948} erneuert – das geht dem Füller vor. Sonst gilt: {11366} sofort bei drei Stapeln {400624}, {2136} sobald bereit, {401502} als Füller. Die Quelle empfiehlt diesen Aufbau vor allem für Kämpfe gegen mehrere Gegner.",
              "Opener: pre-cast {11366}, then {2948} until {22959} has five stacks. Refresh the debuff with one {2948} before it ends – that beats the filler. Otherwise: {11366} at once at three stacks of {400624}, {2136} whenever ready, {401502} as filler. The source recommends this build mainly for fights against several enemies."),
      note = T("Ohne das Talent hinter {22959} entsteht kein Debuff – dann den Schritt {2948} ausschalten. Einen Sofortzauber ans Ende eines laufenden Zaubers zu legen, kann ezCombat nicht anzeigen.",
               "Without the talent behind {22959} no debuff appears – turn the {2948} step off then. ezCombat can't show how to batch an instant into the end of a cast."),
      steps = {
        -- Vor dem Kampf ---------------------------------------------------------------------------------------------
        { id = 1459, kind = "longbuff", buff = "int", when = "buff",
          text = T("Vor dem Kampf auf dich und die Gruppe.", "Before combat on yourself and the group.") },    -- Arkane Intelligenz / Arcane Intellect
        { id = 6117, kind = "longbuff", buff = "armor", when = "buff",
          text = T("Vor dem Kampf; es zählt die beste gelernte Rüstung.", "Before combat; your best learned armor counts.") },    -- Magische Rüstung / Mage Armor
        { id = 10054, kind = "prepare", when = "item", item = { 8008 }, optional = true,
          text = T("Einen Manastein für lange Kämpfe herstellen.", "Conjure a mana gem for long fights.") },    -- Manarubin herbeizaubern / Conjure Mana Ruby [V]
        { id = 10053, kind = "prepare", when = "item", item = { 8007 }, optional = true, need = { unknown = 10054 },
          text = T("Manastein herstellen, solange der bessere fehlt.", "Conjure a mana gem until you learn the better one.") },    -- Manacitrin herbeizaubern / Conjure Mana Citrine [V]
        { id = 3552, kind = "prepare", when = "item", item = { 5513 }, optional = true, need = { unknown = { 10054, 10053 } },
          text = T("Manastein herstellen, solange der bessere fehlt.", "Conjure a mana gem until you learn the better one.") },    -- Manajade herbeizaubern / Conjure Mana Jade [V]
        { id = 759, kind = "prepare", when = "item", item = { 5514 }, optional = true, need = { unknown = { 10054, 10053, 3552 } },
          text = T("Manastein herstellen, solange der bessere fehlt.", "Conjure a mana gem until you learn the better one.") },    -- Manaachat herbeizaubern / Conjure Mana Agate [V]
        -- Mehrere Gegner (nur im Flächenmodus) ----------------------------------------------------------------------
        { id = 2120, kind = "aoe", when = "ready", once = "combat",
          text = T("Eröffnet gegen mehrere Gegner; vor Ablauf des Feuers selbst erneuern.", "Opens against several enemies; renew it yourself before the fire ends.") },    -- Flammenstoß / Flamestrike
        { id = 11113, kind = "aoe", when = "ready",
          text = T("Nah an den Gegnern, sobald bereit.", "Close to the enemies, whenever ready.") },    -- Druckwelle / Blast Wave
        { id = 120, kind = "aoe", when = "ready",
          text = T("Danach; allein nicht direkt hinter {11113}.", "After that; solo not right behind {11113}.") },    -- Kältekegel / Cone of Cold
        { id = 1449, kind = "aoe", when = "ready",
          text = T("Füllt den Rest – nur, solange dich niemand angreift.", "Fills the rest – only while nobody attacks you.") },    -- Arkane Explosion / Arcane Explosion
        -- Eröffnung -------------------------------------------------------------------------------------------------
        { id = 11366, kind = "opener", when = "ready", once = "target", need = { combat = false },
          text = T("Als ersten Zauber vorzaubern.", "Pre-cast it as your first spell.") },    -- Pyroschlag / Pyroblast
        -- Im Kampf (Reihenfolge = Rang) -----------------------------------------------------------------------------
        { id = 11366, kind = "priority", when = "proc", aura = 400624, stacks = 3,
          text = T("Sofort bei drei Stapeln {400624} – auch mitten im Aufbau.", "At once at three stacks of {400624} – even mid-setup.") },    -- Pyroschlag / Pyroblast
        { id = 2948, kind = "maintain", when = "dot", aura = 22959, stacks = 5, refresh = 6, mine = false,    -- Annahme: 6 s; Debuff geteilt [V]
          text = T("Bis fünf Stapel {22959}; danach vor Ablauf erneuern.", "Up to five stacks of {22959}; then refresh before it ends.") },    -- Versengen / Scorch
        { id = 2136, kind = "priority", when = "ready",
          text = T("Sobald bereit: baut {400624} auf.", "Whenever ready: builds {400624}.") },    -- Feuerschlag / Fire Blast
        { id = 12051, kind = "resource", when = "lowmana", max = 5,
          text = T("Bei fast leerem Mana, wenn du ungestört kanalisieren kannst.", "Nearly out of mana, when you can channel undisturbed.") },    -- Hervorrufung / Evocation
        { id = 401502, kind = "filler", when = "filler",
          text = T("Lückenfüller, bis {400624} drei Stapel hat.", "Gap filler until {400624} has three stacks.") },    -- Frostfeuerblitz / Frostfire Bolt
        { id = 133, kind = "filler", when = "filler", need = { unknown = 401502 },
          text = T("Lückenfüller, solange {401502} fehlt.", "Gap filler until you learn {401502}.") },    -- Feuerball / Fireball
        -- Situativ --------------------------------------------------------------------------------------------------
        { id = 7302, kind = "situational", when = "manual",
          text = T("Statt {6117}, wenn dich Nahkämpfer treffen.", "Instead of {6117} when melee attackers hit you.") },    -- Eisrüstung / Ice Armor
      } },

    -----------------------------------------------------------------------------------------------------------------
    -- Feuer, Höchststufe, mit dem Talent am Ende des Baums (laut Quelle der stärkste Aufbau gegen ein Ziel)
    -----------------------------------------------------------------------------------------------------------------
    { key = "fire_deep", tree = 2, name = T("Feuer (Tiefes Feuer)", "Fire (Deep Fire)"),
      source = "https://www.icy-veins.com/wow-forever/fire-mage-ranged-dps-pve-rotation-cooldowns-abilities",
      sources = { "https://www.icy-veins.com/wow-forever/fire-mage-ranged-dps-pve-spec-builds-talents",
                  "https://www.icy-veins.com/wow-forever/fire-mage-ranged-dps-pve-guide",
                  "https://www.icy-veins.com/wow-forever/frost-mage-ranged-dps-pve-rotation-cooldowns-abilities" },
      pick = { leveling = false, known = 11129 },
      how = T("Eröffnung wie im anderen Feuer-Aufbau: {11366} vorzaubern, dann {2948}, bis {22959} fünf Stapel hat, und den Debuff vor Ablauf erneuern. Im Kampf: {11366} bei drei Stapeln {400624}, {2136} sobald bereit. Dazu ein einzelner {400574}, der erst nach Ablauf seines Buffs wiederholt wird, und {5143} bei {400588}. Füller ist {133}.",
              "Opener as in the other fire build: pre-cast {11366}, then {2948} until {22959} has five stacks, and refresh the debuff before it ends. In combat: {11366} at three stacks of {400624}, {2136} whenever ready. Add a single {400574}, repeated only after its buff has dropped, and {5143} on {400588}. The filler is {133}."),
      note = T("Für {11129} nennt die Quelle keine Regel – der Schritt ist aus, bis du ihn einschaltest. Ohne das Talent hinter {22959} den Schritt {2948} ausschalten.",
               "The source gives no rule for {11129} – the step is off until you turn it on. Without the talent behind {22959} turn the {2948} step off."),
      steps = {
        -- Vor dem Kampf ---------------------------------------------------------------------------------------------
        { id = 1459, kind = "longbuff", buff = "int", when = "buff",
          text = T("Vor dem Kampf auf dich und die Gruppe.", "Before combat on yourself and the group.") },    -- Arkane Intelligenz / Arcane Intellect
        { id = 6117, kind = "longbuff", buff = "armor", when = "buff",
          text = T("Vor dem Kampf; es zählt die beste gelernte Rüstung.", "Before combat; your best learned armor counts.") },    -- Magische Rüstung / Mage Armor
        { id = 10054, kind = "prepare", when = "item", item = { 8008 }, optional = true,
          text = T("Einen Manastein für lange Kämpfe herstellen.", "Conjure a mana gem for long fights.") },    -- Manarubin herbeizaubern / Conjure Mana Ruby [V]
        { id = 10053, kind = "prepare", when = "item", item = { 8007 }, optional = true, need = { unknown = 10054 },
          text = T("Manastein herstellen, solange der bessere fehlt.", "Conjure a mana gem until you learn the better one.") },    -- Manacitrin herbeizaubern / Conjure Mana Citrine [V]
        { id = 3552, kind = "prepare", when = "item", item = { 5513 }, optional = true, need = { unknown = { 10054, 10053 } },
          text = T("Manastein herstellen, solange der bessere fehlt.", "Conjure a mana gem until you learn the better one.") },    -- Manajade herbeizaubern / Conjure Mana Jade [V]
        { id = 759, kind = "prepare", when = "item", item = { 5514 }, optional = true, need = { unknown = { 10054, 10053, 3552 } },
          text = T("Manastein herstellen, solange der bessere fehlt.", "Conjure a mana gem until you learn the better one.") },    -- Manaachat herbeizaubern / Conjure Mana Agate [V]
        -- Mehrere Gegner (nur im Flächenmodus) ----------------------------------------------------------------------
        { id = 2120, kind = "aoe", when = "ready", once = "combat",
          text = T("Eröffnet gegen mehrere Gegner; vor Ablauf des Feuers selbst erneuern.", "Opens against several enemies; renew it yourself before the fire ends.") },    -- Flammenstoß / Flamestrike
        { id = 11113, kind = "aoe", when = "ready",
          text = T("Nah an den Gegnern, sobald bereit.", "Close to the enemies, whenever ready.") },    -- Druckwelle / Blast Wave
        { id = 120, kind = "aoe", when = "ready",
          text = T("Danach; allein nicht direkt hinter {11113}.", "After that; solo not right behind {11113}.") },    -- Kältekegel / Cone of Cold
        { id = 1449, kind = "aoe", when = "ready",
          text = T("Füllt den Rest – nur, solange dich niemand angreift.", "Fills the rest – only while nobody attacks you.") },    -- Arkane Explosion / Arcane Explosion
        -- Eröffnung -------------------------------------------------------------------------------------------------
        { id = 11366, kind = "opener", when = "ready", once = "target", need = { combat = false },
          text = T("Als ersten Zauber vorzaubern.", "Pre-cast it as your first spell.") },    -- Pyroschlag / Pyroblast
        -- Abklingzeiten ---------------------------------------------------------------------------------------------
        { id = 11129, kind = "cooldown", burst = true, when = "ready", optional = true, need = { combat = true },
          text = T("Für starke Momente; die Quelle nennt keine Regel – nach Lage.", "For big moments; the source gives no rule – use as needed.") },    -- Verbrennen / Combustion
        -- Im Kampf (Reihenfolge = Rang) -----------------------------------------------------------------------------
        { id = 11366, kind = "priority", when = "proc", aura = 400624, stacks = 3,
          text = T("Sofort bei drei Stapeln {400624} – auch mitten im Aufbau.", "At once at three stacks of {400624} – even mid-setup.") },    -- Pyroschlag / Pyroblast
        { id = 2948, kind = "maintain", when = "dot", aura = 22959, stacks = 5, refresh = 6, mine = false,    -- Annahme: 6 s; Debuff geteilt [V]
          text = T("Bis fünf Stapel {22959}; danach vor Ablauf erneuern.", "Up to five stacks of {22959}; then refresh before it ends.") },    -- Versengen / Scorch
        { id = 2136, kind = "priority", when = "ready",
          text = T("Sobald bereit: baut {400624} auf.", "Whenever ready: builds {400624}.") },    -- Feuerschlag / Fire Blast
        { id = 400574, kind = "maintain", when = "buff", refresh = "missing",
          text = T("Ein Stapel; erst neu wirken, wenn die Stärkung ausgelaufen ist.", "One stack; recast only after the bonus has dropped.") },    -- Arkanschlag / Arcane Blast
        { id = 5143, kind = "priority", when = "proc", aura = 400588,
          text = T("Mit {400588}, wenn {2136} nicht bereit ist.", "With {400588} when {2136} isn't ready.") },    -- Arkane Geschosse / Arcane Missiles
        { id = 12051, kind = "resource", when = "lowmana", max = 5,
          text = T("Bei fast leerem Mana, wenn du ungestört kanalisieren kannst.", "Nearly out of mana, when you can channel undisturbed.") },    -- Hervorrufung / Evocation
        { id = 133, kind = "filler", when = "filler",
          text = T("Sonst immer.", "Otherwise always.") },    -- Feuerball / Fireball
        -- Situativ --------------------------------------------------------------------------------------------------
        { id = 7302, kind = "situational", when = "manual",
          text = T("Statt {6117}, wenn dich Nahkämpfer treffen.", "Instead of {6117} when melee attackers hit you.") },    -- Eisrüstung / Ice Armor
      } },

    -----------------------------------------------------------------------------------------------------------------
    -- Feuer, Leveln
    -----------------------------------------------------------------------------------------------------------------
    { key = "fire_level", tree = 2, name = T("Feuer (Leveln)", "Fire (levelling)"),
      source = "https://www.icy-veins.com/wow-forever/fire-mage-leveling",
      sources = { "https://www.icy-veins.com/wow-forever/fire-mage-ranged-dps-pve-rotation-cooldowns-abilities",
                  "https://www.icy-veins.com/wow-forever/frost-mage-ranged-dps-pve-rotation-cooldowns-abilities" },
      pick = { leveling = true },
      how = T("Eröffnet wird mit dem größten gelernten Zauber, solange der Gegner noch anläuft. Der Talentweg beginnt im Arkanbaum: ein bis zwei {400574}, bis {400588} auslöst, dann {5143}. Später kommen {11366} bei drei Stapeln {400624} und {2136} auf Abklingzeit dazu. Füller ist der kurze, sparsame {2948}; fast tote Gegner erledigt der Zauberstab.",
              "Open with your biggest learned spell while the enemy is still running at you. The talent path starts in the arcane tree: one or two {400574} until {400588} procs, then {5143}. Later add {11366} at three stacks of {400624} and {2136} on cooldown. The filler is the short, cheap {2948}; nearly dead enemies are for your wand."),
      note = T("Das Leben des Ziels sieht ezCombat nicht – der Zauberstab steht nur als Text. Fläche lohnt laut Quelle erst ab drei Gegnern.",
               "ezCombat can't see target health – the wand is text only. Per the source AoE pays off from three enemies."),
      steps = {
        -- Vor dem Kampf ---------------------------------------------------------------------------------------------
        { id = 1459, kind = "longbuff", buff = "int", when = "buff",
          text = T("Vor dem Kampf auf dich und die Gruppe.", "Before combat on yourself and the group.") },    -- Arkane Intelligenz / Arcane Intellect
        { id = 6117, kind = "longbuff", buff = "armor", when = "buff",
          text = T("Vor dem Kampf; es zählt die beste gelernte Rüstung.", "Before combat; your best learned armor counts.") },    -- Magische Rüstung / Mage Armor
        { id = 10054, kind = "prepare", when = "item", item = { 8008 }, optional = true,
          text = T("Einen Manastein für lange Kämpfe herstellen.", "Conjure a mana gem for long fights.") },    -- Manarubin herbeizaubern / Conjure Mana Ruby [V]
        { id = 10053, kind = "prepare", when = "item", item = { 8007 }, optional = true, need = { unknown = 10054 },
          text = T("Manastein herstellen, solange der bessere fehlt.", "Conjure a mana gem until you learn the better one.") },    -- Manacitrin herbeizaubern / Conjure Mana Citrine [V]
        { id = 3552, kind = "prepare", when = "item", item = { 5513 }, optional = true, need = { unknown = { 10054, 10053 } },
          text = T("Manastein herstellen, solange der bessere fehlt.", "Conjure a mana gem until you learn the better one.") },    -- Manajade herbeizaubern / Conjure Mana Jade [V]
        { id = 759, kind = "prepare", when = "item", item = { 5514 }, optional = true, need = { unknown = { 10054, 10053, 3552 } },
          text = T("Manastein herstellen, solange der bessere fehlt.", "Conjure a mana gem until you learn the better one.") },    -- Manaachat herbeizaubern / Conjure Mana Agate [V]
        -- Mehrere Gegner (nur im Flächenmodus) ----------------------------------------------------------------------
        { id = 2120, kind = "aoe", when = "ready", once = "combat",
          text = T("Eröffnet gegen mehrere Gegner; vor Ablauf des Feuers selbst erneuern.", "Opens against several enemies; renew it yourself before the fire ends.") },    -- Flammenstoß / Flamestrike
        { id = 11113, kind = "aoe", when = "ready",
          text = T("Nah an den Gegnern, sobald bereit.", "Close to the enemies, whenever ready.") },    -- Druckwelle / Blast Wave
        { id = 120, kind = "aoe", when = "ready",
          text = T("Ersetzt {11113}, solange sie fehlt; nie direkt hintereinander.", "Replaces {11113} until learned; never back to back.") },    -- Kältekegel / Cone of Cold
        { id = 1449, kind = "aoe", when = "ready",
          text = T("Füllt den Rest – nur, solange dich niemand angreift.", "Fills the rest – only while nobody attacks you.") },    -- Arkane Explosion / Arcane Explosion
        -- Eröffnung (der größte gelernte Zauber) --------------------------------------------------------------------
        { id = 11366, kind = "opener", when = "ready", once = "target", need = { combat = false },
          text = T("Sobald gelernt: als ersten Zauber vorzaubern.", "Once learned: pre-cast it as your first spell.") },    -- Pyroschlag / Pyroblast
        { id = 401502, kind = "opener", when = "ready", once = "target", need = { combat = false, unknown = 11366 },
          text = T("Eröffnet, solange {11366} fehlt.", "Opens until you learn {11366}.") },    -- Frostfeuerblitz / Frostfire Bolt
        { id = 133, kind = "opener", when = "ready", once = "target", need = { combat = false, unknown = { 11366, 401502 } },
          text = T("Eröffnet, solange die größeren Zauber fehlen.", "Opens until you learn the bigger spells.") },    -- Feuerball / Fireball
        -- Im Kampf (Reihenfolge = Rang) -----------------------------------------------------------------------------
        { id = 11366, kind = "priority", when = "proc", aura = 400624, stacks = 3,
          text = T("Sofort bei drei Stapeln {400624}.", "At once at three stacks of {400624}.") },    -- Pyroschlag / Pyroblast
        { id = 5143, kind = "priority", when = "proc", aura = 400588,
          text = T("Nur mit {400588}.", "Only with {400588}.") },    -- Arkane Geschosse / Arcane Missiles
        { id = 400574, kind = "maintain", when = "buff", refresh = "missing",
          text = T("Einmal wirken, sobald die Stapel-Stärkung ausgelaufen ist.", "Cast once after the stacking bonus has dropped.") },    -- Arkanschlag / Arcane Blast
        { id = 400574, key = "maintain:400574-stack", kind = "maintain", when = "ready", need = { aura = { id = 400574, max = 1 } },    -- Annahme: Obergrenze der Quelle
          text = T("Höchstens zweimal in Folge – jeder Stapel kostet mehr Mana.", "Twice in a row at most – each stack costs more mana.") },    -- Arkanschlag / Arcane Blast
        { id = 2136, kind = "priority", when = "ready",
          text = T("Auf Abklingzeit.", "On cooldown.") },    -- Feuerschlag / Fire Blast
        { id = 12051, kind = "resource", when = "lowmana", max = 5,
          text = T("Bei fast leerem Mana, wenn du ungestört kanalisieren kannst.", "Nearly out of mana, when you can channel undisturbed.") },    -- Hervorrufung / Evocation
        { id = 2948, kind = "filler", when = "filler",
          text = T("Lückenfüller: kurz und sparsam.", "Gap filler: short and cheap.") },    -- Versengen / Scorch
        { id = 133, kind = "filler", when = "filler", need = { unknown = 2948 },
          text = T("Lückenfüller, solange {2948} fehlt.", "Gap filler until you learn {2948}.") },    -- Feuerball / Fireball
        -- Situativ --------------------------------------------------------------------------------------------------
        { id = 5019, kind = "situational", when = "manual",
          text = T("Zauberstab: fast tote Gegner oder leeres Mana.", "Wand: nearly dead enemies or no mana left.") },    -- Schießen / Shoot [V]
        { id = 7302, kind = "situational", when = "manual",
          text = T("Statt {6117}, wenn dich Nahkämpfer treffen.", "Instead of {6117} when melee attackers hit you.") },    -- Eisrüstung / Ice Armor
      } },

    -----------------------------------------------------------------------------------------------------------------
    -- Frost (eine Liste für Leveln und Höchststufe: ungelernte Schritte fallen weg)
    -----------------------------------------------------------------------------------------------------------------
    { key = "frost", tree = 3, name = T("Frost", "Frost"),
      source = "https://www.icy-veins.com/wow-forever/frost-mage-ranged-dps-pve-rotation-cooldowns-abilities",
      sources = { "https://www.icy-veins.com/wow-forever/frost-mage-leveling",
                  "https://www.icy-veins.com/wow-forever/frost-mage-ranged-dps-pve-spec-builds-talents",
                  "https://www.icy-veins.com/wow-forever/frost-mage-ranged-dps-pve-guide" },
      how = T("Alles dreht sich um {116}. Zum Pull {11426} wirken und {116} vorzaubern. Im Kampf: {120}, sobald das Ziel fünf Stapel {12579} trägt; {1312002}, wenn von {400647} genau eine Ladung übrig ist oder das Ziel eingefroren ist; {11426} kurz vor Ablauf erneuern, weil sie den Schaden erhöht. Sonst immer {116}. {12472} bleibt im Kampf gegen ein Ziel Reserve.",
              "Everything revolves around {116}. For the pull cast {11426} and pre-cast {116}. In combat: {120} once the target carries five stacks of {12579}; {1312002} when exactly one charge of {400647} is left or the target is frozen; renew {11426} shortly before it ends because it raises your damage. Otherwise always {116}. {12472} stays in reserve against a single target."),
      note = T("{120} und {1312002} gehören ans Ende des laufenden {116} – das zeigt ezCombat nicht. Bricht der Schild von {11426} früh, läuft ihr Schadensbonus weiter; ezCombat sieht nur den Schild.",
               "{120} and {1312002} belong at the end of the running {116} – ezCombat can't show that. If the {11426} shield breaks early its damage bonus keeps running; ezCombat only sees the shield."),
      steps = {
        -- Vor dem Kampf ---------------------------------------------------------------------------------------------
        { id = 1459, kind = "longbuff", buff = "int", when = "buff",
          text = T("Vor dem Kampf auf dich und die Gruppe.", "Before combat on yourself and the group.") },    -- Arkane Intelligenz / Arcane Intellect
        { id = 7302, kind = "longbuff", buff = "iceArmor", when = "buff", need = { solo = true },
          text = T("Allein: schützt vor Nahkämpfern (vorher die kleinere Rüstung).", "Solo: protects against melee (the lesser armor before that).") },    -- Eisrüstung / Ice Armor
        { id = 6117, kind = "longbuff", buff = "mageArmor", when = "buff", need = { grouped = true },
          text = T("In der Gruppe: Mana zählt mehr als Schutz.", "In a group: mana matters more than protection.") },    -- Magische Rüstung / Mage Armor
        { id = 10054, kind = "prepare", when = "item", item = { 8008 }, optional = true,
          text = T("Einen Manastein für lange Kämpfe herstellen.", "Conjure a mana gem for long fights.") },    -- Manarubin herbeizaubern / Conjure Mana Ruby [V]
        { id = 10053, kind = "prepare", when = "item", item = { 8007 }, optional = true, need = { unknown = 10054 },
          text = T("Manastein herstellen, solange der bessere fehlt.", "Conjure a mana gem until you learn the better one.") },    -- Manacitrin herbeizaubern / Conjure Mana Citrine [V]
        { id = 3552, kind = "prepare", when = "item", item = { 5513 }, optional = true, need = { unknown = { 10054, 10053 } },
          text = T("Manastein herstellen, solange der bessere fehlt.", "Conjure a mana gem until you learn the better one.") },    -- Manajade herbeizaubern / Conjure Mana Jade [V]
        { id = 759, kind = "prepare", when = "item", item = { 5514 }, optional = true, need = { unknown = { 10054, 10053, 3552 } },
          text = T("Manastein herstellen, solange der bessere fehlt.", "Conjure a mana gem until you learn the better one.") },    -- Manaachat herbeizaubern / Conjure Mana Agate [V]
        { id = 11426, kind = "prepare", when = "buff", refresh = "missing", need = { target = true },
          text = T("Direkt zum Kampfbeginn wirken (erhöht deinen Schaden).", "Cast right as the fight starts (raises your damage).") },    -- Eisbarriere / Ice Barrier
        -- Mehrere Gegner (nur im Flächenmodus; ohne Hauptziel) ------------------------------------------------------
        { id = 120, key = "aoe:120", kind = "aoe", when = "ready",
          text = T("Ohne Hauptziel: sobald bereit; {12472} erlaubt einen zweiten.", "No main target: whenever ready; {12472} allows a second.") },    -- Kältekegel / Cone of Cold
        { id = 10, kind = "aoe", when = "ready",
          text = T("Lückenfüller zwischen zwei {120}.", "Gap filler between two {120}.") },    -- Blizzard / Blizzard
        { id = 122, key = "aoe:122", kind = "aoe", when = "aoe",
          text = T("Beim Leveln vor {120}: eingefrorene Gegner nehmen mehr Schaden.", "Levelling, before {120}: frozen enemies take more damage.") },    -- Frostnova / Frost Nova [V]
        { id = 1449, kind = "aoe", when = "aoe",
          text = T("Statt {10}, wenn du angegriffen wirst oder läufst.", "Instead of {10} when you are attacked or moving.") },    -- Arkane Explosion / Arcane Explosion
        -- Eröffnung -------------------------------------------------------------------------------------------------
        { id = 116, kind = "opener", when = "ready", once = "target", need = { combat = false },
          text = T("Aus voller Entfernung vorzaubern.", "Pre-cast from full range.") },    -- Frostblitz / Frostbolt
        -- Abklingzeiten ---------------------------------------------------------------------------------------------
        { id = 12472, kind = "cooldown", when = "manual",
          text = T("Reserve: Schutz zurücksetzen. Mehrere Gegner: zweiter {120}.", "Reserve: resets your defences. Several enemies: a second {120}.") },    -- Kälteeinbruch / Cold Snap [V]
        -- Im Kampf (Reihenfolge = Rang) -----------------------------------------------------------------------------
        { id = 120, kind = "priority", when = "proc", aura = 12579, stacks = 5, unit = "target", mine = false,    -- Debuff geteilt [V]
          text = T("Bei fünf Stapeln {12579} auf dem Ziel – nah genug heran.", "At five stacks of {12579} on the target – get close enough.") },    -- Kältekegel / Cone of Cold
        { id = 1312002, key = "priority:400640", kind = "priority", when = "proc", aura = 400647, need = { aura = { id = 400647, max = 1 } },
          text = T("Wenn von {400647} genau eine Ladung übrig ist.", "When exactly one charge of {400647} is left.") },    -- Eislanze / Ice Lance
        { id = 1312002, key = "priority:400640-frozen", kind = "priority", when = "ready", need = { aura = { id = { 122, 12494 }, unit = "target" } },    -- 12494 Erfrierung / Frostbite [V]
          text = T("Auf ein eingefrorenes Ziel.", "On a frozen target.") },    -- Eislanze / Ice Lance
        { id = 11426, key = "maintain:11426", kind = "maintain", when = "buff", refresh = 3,
          text = T("Kurz vor Ablauf erneuern – der Schadensbonus soll nie fehlen.", "Renew shortly before it ends – never lose the damage bonus.") },    -- Eisbarriere / Ice Barrier
        { id = 12051, kind = "resource", when = "lowmana", max = 5,
          text = T("Bei fast leerem Mana, wenn du ungestört kanalisieren kannst.", "Nearly out of mana, when you can channel undisturbed.") },    -- Hervorrufung / Evocation
        { id = 116, kind = "filler", when = "filler",
          text = T("Sonst immer.", "Otherwise always.") },    -- Frostblitz / Frostbolt
        { id = 133, kind = "filler", when = "filler", need = { unknown = 116 },
          text = T("Lückenfüller ganz am Anfang, solange {116} fehlt.", "Gap filler at the very start until you learn {116}.") },    -- Feuerball / Fireball
        -- Situativ --------------------------------------------------------------------------------------------------
        { id = 2136, kind = "situational", when = "manual",
          text = T("Leveln: nur für fast tote Gegner, die nicht eingefroren sind.", "Levelling: only for nearly dead enemies that aren't frozen.") },    -- Feuerschlag / Fire Blast
        { id = 5019, kind = "situational", when = "manual",
          text = T("Zauberstab: fast tote Gegner ohne Mana erledigen.", "Wand: finish nearly dead enemies without mana.") },    -- Schießen / Shoot [V]
        { id = 122, kind = "situational", when = "manual",
          text = T("Gegner am Leib, allein: einfrieren, Abstand, {116} und {1312002}.", "Enemy on you, solo: freeze, step back, {116} and {1312002}.") },    -- Frostnova / Frost Nova [V]
        { id = 604, kind = "situational", when = "manual",
          text = T("Allein vor dem Kampf auf dich, wenn es zur Lage passt.", "Solo before combat on yourself when it fits the situation.") },    -- Magie dämpfen / Dampen Magic [V]
      } },
})
