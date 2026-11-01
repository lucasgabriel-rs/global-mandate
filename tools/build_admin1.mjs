// Converte o Natural Earth admin-1 (10m) em data/admin1.json: as unidades subnacionais do cenário.
// Uso: node tools/build_admin1.mjs   (a partir da raiz do projeto)
//
// Divide os anéis em arcos e simplifica cada arco uma vez só: as divisas entre duas unidades
// continuam idênticas nos dois lados e não abrem frestas. Divisas dentro do mesmo país vão
// para "arcs", que é o que o mapa desenha.
import { readFileSync, writeFileSync } from "node:fs";
import { project, area, centroid, key, buildArcs } from "./geo.mjs";

const TOLERANCE_DEG = 0.04;
const MIN_PIECE_AREA = 0.02; // unidades² do mapa projetado

// Territórios com linha própria no Natural Earth, ligados ao país que os administra no jogo.
const ALIASES = {
  SDS: "SSD", KOS: "XKX", PSX: "PSE", SOL: "SOM", CYN: "CYP", SAH: "MAR", KAS: "IND", KAB: "KAZ",
  GRL: "DNK", FRO: "DNK", PRI: "USA", GUM: "USA", MNP: "USA", VIR: "USA", ASM: "USA", UMI: "USA",
  FLK: "GBR", BMU: "GBR", SGS: "GBR", NCL: "FRA", PYF: "FRA", ATF: "FRA", MAC: "CHN", ALD: "FIN",
  HMD: "AUS", CUW: "NLD", ABW: "NLD", HKG: "CHN",
};

const TYPES = {
  "province": "Província", "district": "Distrito", "region": "Região", "state": "Estado", "county": "Condado",
  "department": "Departamento", "departamento": "Departamento", "commune": "Comuna", "municipality": "Município",
  "prefecture": "Prefeitura", "préfecture": "Prefeitura", "metropolitan department": "Departamento metropolitano",
  "statistical region": "Região estatística", "governorate": "Governorado", "parish": "Paróquia",
  "unitary authority": "Autoridade unitária", "unitary authority (wales)": "Autoridade unitária",
  "autonomous community": "Comunidade autônoma", "canton": "Cantão", "metropolitan borough": "Distrito metropolitano",
  "highly urbanized city": "Cidade altamente urbanizada", "city": "Cidade", "town": "Cidade",
  "autonomous province": "Província autônoma", "london borough": "Distrito de Londres",
  "london borough (royal)": "Distrito de Londres", "london borough (city)": "Distrito de Londres",
  "administrative county": "Condado administrativo", "unitary district": "Distrito unitário",
  "unitary district (city)": "Distrito unitário", "division": "Divisão", "urban county": "Condado urbano",
  "republic": "República", "atoll": "Atol", "territory": "Território", "voivodeship": "Voivodia",
  "administrative state": "Estado", "quarter": "Bairro", "regional council": "Conselho regional",
  "administrative zone": "Zona administrativa", "union territory": "Território da União", "emirate": "Emirado",
  "special municipality": "Município especial", "republican city": "Cidade republicana",
  "autonomous region": "Região autônoma", "automonous region": "Região autônoma",
  "metropolitan city": "Cidade metropolitana", "unitary single-tier county": "Condado unitário",
  "federal district": "Distrito federal", "lansdele": "Região", "overseas department": "Departamento ultramarino",
  "commissiary": "Comissariado", "independent component city": "Cidade independente", "dependency": "Dependência",
  "intendancy": "Intendência", "autonomous republic": "República autônoma", "capital district": "Distrito da capital",
  "captial district": "Distrito da capital", "capital": "Capital", "indigenous territory": "Território indígena",
  "independent city": "Cidade independente", "independent town": "Cidade independente",
  "provincial city": "Cidade provincial", "federal city": "Cidade federal", "federal territory": "Território federal",
  "autonomous city": "Cidade autônoma", "centrally administered area": "Área de administração central",
  "national capital area": "Área da capital nacional", "economic prefecture": "Prefeitura econômica",
  "urban prefecture": "Prefeitura urbana", "neutral city": "Cidade neutra", "condominium": "Condomínio",
  "territorial unit": "Unidade territorial", "autonomous territory": "Território autônomo",
  "autonomous commune": "Comuna autônoma", "national territory": "Território nacional", "oblast'": "Oblast",
  "capital region": "Região da capital", "special district": "Distrito especial", "special region": "Região especial",
  "autonomous sector": "Setor autônomo", "metropolis": "Metrópole", "circuit": "Circuito", "principality": "Principado",
  "autonomous monastic state": "Estado monástico autônomo", "federal dependency": "Dependência federal",
  "national district": "Distrito nacional", "island area": "Área insular",
  "special island authority": "Autoridade insular especial", "capital territory": "Território da capital",
  "city corporation": "Corporação municipal", "kingdom": "Reino",
  "capital metropolitan city": "Cidade metropolitana da capital", "special self-governing city": "Cidade autônoma especial",
  "special city": "Cidade especial", "capital city": "Cidade capital", "township": "Município",
  "independent municipality": "Município independente",
};

const csv = readFileSync("data/countries.csv", "utf8").trim().split("\n");
const known = new Set(csv.slice(1).map((l) => l.split(",")[0]));
const raw = JSON.parse(readFileSync("tools/raw/ne_10m_admin_1.geojson", "utf8"));

const skipped = {};
const units = [];
const unknownTypes = new Set();
for (const f of raw.features) {
  const q = f.properties;
  const a3 = q.adm0_a3;
  const iso = known.has(a3) ? a3 : ALIASES[a3];
  if (!iso || !known.has(iso)) { skipped[a3] = (skipped[a3] || 0) + 1; continue; }
  const kind = String(q.type_en || q.type || "").split("|")[0].trim().toLowerCase();
  if (kind && !TYPES[kind]) unknownTypes.add(kind);
  const polys = f.geometry.type === "Polygon" ? [f.geometry.coordinates] : f.geometry.coordinates;
  units.push({
    name: q.name || q.name_en || "Ilhas menores", owner: iso, type: TYPES[kind] || "Região",
    // Só o anel externo: enclaves são unidades próprias e a menor tem prioridade no clique.
    rings: polys.map((p) => p[0].slice(0, -1)),
  });
}

const { simplifyRing, arcCache } = buildArcs(units, TOLERANCE_DEG);

const output = [];
for (let i = 0; i < units.length; i++) {
  const u = units[i];
  let pieces = [];
  for (const r of u.rings) {
    if (r.length < 3) continue;
    const ring = simplifyRing(r, i).map(project).filter((p, k, arr) => k === 0 || key(p) !== key(arr[k - 1]));
    if (ring.length >= 3) pieces.push(ring);
  }
  if (!pieces.length) {
    // Unidade pequena demais para a tolerância: usa o anel original, só projetado.
    pieces = u.rings.filter((r) => r.length >= 3).map((r) => r.map(project));
  }
  const areas = pieces.map(area);
  const largest = Math.max(...areas);
  pieces = pieces.filter((_, k) => areas[k] >= MIN_PIECE_AREA || areas[k] === largest);
  const biggest = pieces[pieces.map(area).indexOf(Math.max(...pieces.map(area)))];
  const flat = pieces.flat();
  const xs = flat.map((p) => p[0]), ys = flat.map((p) => p[1]);
  output.push({
    n: u.name, o: u.owner, t: u.type,
    c: centroid(biggest).map((v) => +v.toFixed(2)),
    b: [Math.min(...xs), Math.min(...ys), Math.max(...xs), Math.max(...ys)],
    a: +pieces.reduce((s, r) => s + area(r), 0).toFixed(3),
    s: pieces.map((r) => r.flat()),
  });
}

const arcs = [];
for (const { points, owners } of arcCache.values()) {
  const ids = [...owners];
  if (ids.length !== 2 || units[ids[0]].owner !== units[ids[1]].owner) continue;
  const flat = points.map(project).flat();
  arcs.push([ids[0], ids[1], flat]);
}

const json = JSON.stringify({ units: output, arcs });
writeFileSync("data/admin1.json", json);

const counts = {};
for (const u of units) counts[u.owner] = (counts[u.owner] || 0) + 1;
const linked = new Set(arcs.flatMap((a) => [units[a[0]].owner]));
const verts = output.reduce((s, u) => s + u.s.reduce((a, r) => a + r.length / 2, 0), 0);
console.log(`unidades=${output.length} países=${Object.keys(counts).length} vértices=${verts} arcos internos=${arcs.length} bytes=${json.length}`);
console.log("tipos sem tradução:", [...unknownTypes].join(", ") || "nenhum");
console.log("países da tabela sem unidades:", [...known].filter((k) => !counts[k]).join(", ") || "nenhum");
console.log("com 2+ unidades e sem divisa interna:", Object.keys(counts).filter((k) => counts[k] > 1 && !linked.has(k)).join(", ") || "nenhum");
console.log("fora da tabela (ignorados):", Object.entries(skipped).map(([k, v]) => `${k}:${v}`).join(" "));
