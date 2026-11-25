-- Waffen- und Rüstungsfertigkeiten je Klasse – laut wago.tools, Produkt wowf, Build 1.60.1.71037 (Client-Tabellen SkillLine, SkillLineAbility, SkillRaceClassInfo, SpellEquippedItems, SpellMisc).
-- Erzeugt am 2026-11-24 aus tools/daten/wago/ mit: luajit tools/wago.lua --ausliefern (mit Rohordner: luajit
-- tools/wago.lua <Rohordner> --aus=tools/daten/wago). Nicht von Hand ändern – die wago-Prüfung in sh tools/test.sh
-- meldet rot, wenn diese Datei nicht zu tools/daten/wago/ passt. Herkunft und Regeln: docs/wago-tools.md, Abschnitt 7.
-- Leser: ezCore.ClientData (Wissen/ClientData.lua). Felder: [Fertigkeitslinie] = { Zauber der Fertigkeit (passiv, kommt mit der Linie), Kategorie (6 Waffe, 8 Rüstung), Gegenstandsklasse (2 Waffe, 4 Rüstung), Unterklassen-Maske (Bit = Enum.ItemWeaponSubclass bzw. Enum.ItemArmorSubclass), { { Klassenmaske (Bit = Klassen-ID − 1), Volksmaske Bit 0–31, Volksmaske Bit 32–63 (Bit = ChrRaces.PlayableRaceBit; −1 oder 0 = alle), Availability (1 = von Anfang an, 0 = lernbar), Mindeststufe (0 = keine), Flags (0x100: nicht beim Lehrer – zählt als nie) } … } } – ohne Waffen-Linien, die jede Klasse von Anfang an hat (Verteidigung, Unbewaffnet); wo man lernt (Waffenmeister, Klassenlehrer), führt nur der Server; classIds[Klasse] = Klassen-ID (ChrClasses). Die Regeln liest ezCore.Proficiency (Wissen/Proficiency.lua)
local _, ns = ...
ns.ClientTables = ns.ClientTables or {}
ns.ClientTables.proficiencies = {build="1.60.1.71037",classIds={
DRUID=11,
HUNTER=3,
MAGE=8,
PALADIN=2,
PRIEST=5,
ROGUE=4,
SHAMAN=7,
WARLOCK=9,
WARRIOR=1,
},data={
[43]={201,6,2,128,{{1,91,3,1,0,128},{398,255,0,0,0,128},{1,164,0,0,0,128},{12,0,3,1,0,128},{128,0,3,0,0,128}}},
[44]={196,6,2,1,{{4,166,0,1,0,128},{66,-1,-1,0,0,128},{4,9,3,0,0,128},{9,167,0,1,0,128},{9,88,3,0,0,128}}},
[45]={264,6,2,4,{{4,139,3,1,0,128},{13,255,0,0,0,128},{9,0,3,1,0,128}}},
[46]={266,6,2,8,{{4,36,0,1,0,128},{9,-1,-1,0,0,128},{4,139,3,0,0,128}}},
[54]={198,6,2,16,{{82,-1,-1,1,0,128},{8,255,0,0,0,128},{1,-147,-1,1,0,128},{1,146,0,0,0,128},{1024,8,0,0,0,128},{1024,32,3,1,0,128},{8,0,3,1,0,128}}},
[55]={202,6,2,256,{{6,255,0,0,0,128},{1,16,3,1,0,128},{1,-17,-1,0,0,128},{4,0,3,1,0,128}}},
[136]={227,6,2,1024,{{1216,-1,-1,1,0,128},{277,-1,-1,0,0,128}}},
[160]={199,6,2,32,{{2,-1,-1,1,0,128},{1024,255,0,0,0,128},{1,32,0,1,0,128},{1,223,0,0,0,128},{64,255,0,0,0,384},{1089,0,3,1,0,128}}},
[172]={197,6,2,2,{{6,-1,-1,0,0,128},{1,6,0,1,0,128},{1,249,3,0,0,128},{64,-1,-1,0,0,384}}},
[173]={1180,6,2,32768,{
{268,-1,-1,1,0,128},
{208,255,0,0,0,128},
{4,8,0,1,0,128},
{4,166,0,0,0,128},
{1,216,0,1,0,128},
{1,39,0,0,0,128},
{1024,32,0,0,0,128},
{1024,8,3,1,0,128},
{1217,0,3,1,0,128},
}},
[176]={2567,6,2,65536,{{8,-1,-1,1,0,128},{4,-1,-1,0,0,128},{1,128,3,1,0,128},{1,127,0,0,0,128}}},
[226]={5011,6,2,262144,{{13,-1,-1,0,0,128}}},
[228]={5009,6,2,524288,{{400,-1,-1,1,0,128}}},
[229]={200,6,2,64,{{7,-1,-1,0,20,128},{1024,-1,-1,0,20,128}}},
[293]={750,8,4,16,{{3,-1,-1,0,40,128}}},
[413]={8737,8,4,8,{{68,-1,-1,0,40,128},{3,-1,-1,1,0,128}}},
[414]={9077,8,4,4,{{1103,-1,-1,1,0,128}}},
[415]={9078,8,4,2,{{1503,-1,-1,1,0,128}}},
[433]={9116,8,4,64,{{67,-1,-1,1,0,128}}},
[473]={15590,6,2,8192,{{1101,-1,-1,0,0,130}}},
},date="2026-11-24"}
