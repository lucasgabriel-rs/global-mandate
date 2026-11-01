// Gera data/capitais.json com nome em português e posição das capitais nacionais (Natural Earth).
// Uso: node tools/build_capitais.mjs   (depois, rode tools/clip_units.gd, que acrescenta a geometria)
//
// O Brasil fica de fora: suas capitais já são municípios, definidos em subdivisions.gd.
import { readFileSync, writeFileSync } from "node:fs";
import { project } from "./geo.mjs";

// Onde a fonte marca várias capitais ou a maior cidade em vez da capital oficial.
const CHOSEN = {
  ZAF: "Pretoria", CIV: "Yamoussoukro", BOL: "Sucre", MMR: "Naypyidaw", TZA: "Dodoma", BEN: "Porto-Novo",
  LKA: "Sri Jayawardenepura Kotte", HKG: "Hong Kong", XKX: "Pristina", PSE: "Ramallah",
};
// Código do país na fonte, quando difere da tabela do jogo.
const SOURCE_ISO = { XKX: "KOS", PSE: "PSX" };
const PT = {
  "Washington, D.C.": "Washington", Beijing: "Pequim", Berlin: "Berlim", Tokyo: "Tóquio", "New Delhi": "Nova Délhi",
  London: "Londres", Rome: "Roma", Moscow: "Moscou", Seoul: "Seul", "Mexico City": "Cidade do México",
  Jakarta: "Jacarta", Ankara: "Ancara", Amsterdam: "Amsterdã", Riyadh: "Riad", Bern: "Berna", Warsaw: "Varsóvia",
  Taipei: "Taipé", Brussels: "Bruxelas", Stockholm: "Estocolmo", Bangkok: "Bangcoc", Jerusalem: "Jerusalém",
  Vienna: "Viena", Singapore: "Singapura", Hanoi: "Hanói", Dhaka: "Daca", "København": "Copenhague", Bogota: "Bogotá",
  Pretoria: "Pretória", Bucharest: "Bucareste", Islamabad: "Islamabade", Tehran: "Teerã", Lisbon: "Lisboa",
  Prague: "Praga", "Nur-Sultan": "Astana", Algiers: "Argel", Baghdad: "Bagdá", Athens: "Atenas", Budapest: "Budapeste",
  "Kuwait City": "Cidade do Kuwait", Kyiv: "Kiev", "Addis Ababa": "Adis Abeba", Nairobi: "Nairóbi",
  "Santo Domingo": "São Domingos", Muscat: "Mascate", "Guatemala City": "Cidade da Guatemala", Luxembourg: "Luxemburgo",
  "San José": "São José", "Panama City": "Cidade do Panamá", Yamoussoukro: "Iamussucro", Belgrade: "Belgrado",
  Ashgabat: "Asgabate", Tashkent: "Tasquente", Accra: "Acra", Zagreb: "Zagrebe", Amman: "Amã", Tunis: "Túnis",
  "Yaoundé": "Iaundé", Kampala: "Campala", Ljubljana: "Liubliana", Khartoum: "Cartum", Tripoli: "Trípoli",
  Tallinn: "Talim", "Asunción": "Assunção", "San Salvador": "São Salvador", Kathmandu: "Catmandu", Dakar: "Dacar",
  "Reykjavík": "Reiquiavique", Nicosia: "Nicósia", Beirut: "Beirute", Lusaka: "Lusaca", Tbilisi: "Tbilissi",
  Sarajevo: "Saraievo", Kabul: "Cabul", Bamako: "Bamaco", Ouagadougou: "Uagadugu", Conakry: "Conacri",
  Windhoek: "Vinduque", Ulaanbaatar: "Ulan Bator", Yerevan: "Erevan", "Chișinău": "Chisinau", Damascus: "Damasco",
  Sanaa: "Saná", Vientiane: "Vienciana", Kigali: "Quigali", "N'Djamena": "Jamena", Niamey: "Niamei",
  "Port-au-Prince": "Porto Príncipe", "Port-of-Spain": "Porto da Espanha", Lilongwe: "Lilongué", Brazzaville: "Brazavile",
  "Porto-Novo": "Porto Novo", Mogadishu: "Mogadíscio", Nouakchott: "Nuaquexote", Bishkek: "Bisqueque", Dushanbe: "Duchambé",
  Skopje: "Escópia", Montevideo: "Montevidéu", Thimphu: "Timbu", Djibouti: "Djibuti", Dili: "Díli", Helsinki: "Helsinque",
  Ramallah: "Ramala", "Sri Jayawardenepura Kotte": "Kotte",
};

const iso = readFileSync("data/countries.csv", "utf8").trim().split("\n").slice(1).map((l) => l.split(",")[0]);
const places = JSON.parse(readFileSync("tools/raw/ne_10m_populated_places.geojson", "utf8")).features.map((f) => f.properties);

const out = [];
for (const code of iso) {
  if (code === "BRA") continue;
  const a3 = SOURCE_ISO[code] ?? code;
  const here = places.filter((p) => p.adm0_a3 === a3);
  const place = CHOSEN[code]
    ? here.find((p) => p.name === CHOSEN[code])
    : here.filter((p) => p.featurecla === "Admin-0 capital").sort((a, b) => b.pop_max - a.pop_max)[0];
  if (!place) throw new Error(`sem capital para ${code}: ${CHOSEN[code] ?? "nenhuma marcada"}`);
  const [x, y] = project([place.longitude, place.latitude]);
  const source = place.name.replace(/\s+/g, " ");
  out.push({ iso: code, n: PT[source] ?? source, q: source, x, y });
}
writeFileSync("data/capitais.json", JSON.stringify({ capitals: out }));
console.log(`capitais=${out.length}`);
