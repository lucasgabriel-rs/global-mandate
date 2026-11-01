// Converte o TopoJSON do Natural Earth (world-atlas) em data/map.json.
// Uso: node tools/build_map.mjs   (a partir da raiz do projeto)
//
// A simplificação é feita por arco, não por anel: fronteiras compartilhadas
// continuam idênticas nos dois países e não abrem frestas no mapa.
import { readFileSync, writeFileSync } from "node:fs";

const TOLERANCE_DEG = 0.02;
const MIN_ISLAND_AREA = 1; // unidades² do mapa projetado
const WIDTH = 2000;

// Territórios sem linha própria na tabela, coloridos como o país administrador.
const OWNERS = {
  "Greenland": "DNK", "Faeroe Is.": "DNK", "Puerto Rico": "USA", "Guam": "USA",
  "N. Mariana Is.": "USA", "U.S. Virgin Is.": "USA", "American Samoa": "USA",
  "Somaliland": "SOM", "N. Cyprus": "CYP", "W. Sahara": "MAR", "Falkland Is.": "GBR",
  "New Caledonia": "FRA", "Fr. Polynesia": "FRA", "Fr. S. Antarctic Lands": "FRA",
  "Macao": "CHN", "Siachen Glacier": "IND", "Åland": "FIN", "Bermuda": "GBR",
  "S. Geo. and the Is.": "GBR", "Heard I. and McDonald Is.": "AUS",
  "Curaçao": "NLD", "Aruba": "NLD",
};

const topo = JSON.parse(readFileSync("tools/raw/countries-50m.json", "utf8"));
const [sx, sy] = topo.transform.scale;
const [tx, ty] = topo.transform.translate;

const csv = readFileSync("data/countries.csv", "utf8").trim().split("\n");
const header = csv[0].split(",");
const numToIso = new Map();
const namesByIso = new Map();
for (const line of csv.slice(1)) {
  const f = line.split(",");
  const iso = f[header.indexOf("iso")];
  numToIso.set(String(f[header.indexOf("num")]).padStart(3, "0"), iso);
  namesByIso.set(iso, f[header.indexOf("name")]);
}

// Decodifica arcos delta para lon/lat.
const arcs = topo.arcs.map((arc) => {
  let x = 0, y = 0;
  return arc.map(([dx, dy]) => {
    x += dx; y += dy;
    return [x * sx + tx, y * sy + ty];
  });
});

function simplify(points, tol) {
  if (points.length < 3) return points;
  const keep = new Uint8Array(points.length);
  keep[0] = keep[points.length - 1] = 1;
  const stack = [[0, points.length - 1]];
  // Arco fechado (ilha): divide no ponto mais distante do início para o DP funcionar.
  const [a0, b0] = [points[0], points[points.length - 1]];
  if (a0[0] === b0[0] && a0[1] === b0[1]) {
    let far = 1, best = -1;
    for (let i = 1; i < points.length - 1; i++) {
      const d = (points[i][0] - a0[0]) ** 2 + (points[i][1] - a0[1]) ** 2;
      if (d > best) { best = d; far = i; }
    }
    keep[far] = 1;
    stack.length = 0;
    stack.push([0, far], [far, points.length - 1]);
  }
  while (stack.length) {
    const [s, e] = stack.pop();
    const [ax, ay] = points[s], [bx, by] = points[e];
    const dx = bx - ax, dy = by - ay, len2 = dx * dx + dy * dy || 1e-12;
    let idx = -1, best = tol * tol;
    for (let i = s + 1; i < e; i++) {
      const t = Math.max(0, Math.min(1, ((points[i][0] - ax) * dx + (points[i][1] - ay) * dy) / len2));
      const d = (points[i][0] - ax - t * dx) ** 2 + (points[i][1] - ay - t * dy) ** 2;
      if (d > best) { best = d; idx = i; }
    }
    if (idx >= 0) { keep[idx] = 1; stack.push([s, idx], [idx, e]); }
  }
  return points.filter((_, i) => keep[i]);
}
const simple = arcs.map((a) => simplify(a, TOLERANCE_DEG));

// Projeção Robinson.
const ROB_X = [1,0.9986,0.9954,0.99,0.9822,0.973,0.96,0.9427,0.9216,0.8962,0.8679,0.835,0.7986,0.7597,0.6732,0.6213,0.5722,0.5322];
const ROB_Y = [0,0.062,0.124,0.186,0.248,0.31,0.372,0.434,0.4958,0.5571,0.6176,0.6769,0.7346,0.7903,0.8435,0.8936,0.9394,0.9761,1];
ROB_X.splice(14, 0, 0.7186);
function project([lon, lat]) {
  const al = Math.min(Math.abs(lat), 89.999);
  const i = Math.floor(al / 5), f = al / 5 - i;
  const px = ROB_X[i] + (ROB_X[i + 1] - ROB_X[i]) * f;
  const py = ROB_Y[i] + (ROB_Y[i + 1] - ROB_Y[i]) * f;
  const k = WIDTH / (2 * 180);
  return [+(lon * px * k).toFixed(1), +(-Math.sign(lat) * py * WIDTH * 0.2535 * 1.0).toFixed(1)];
}

function ringFromArcs(refs) {
  const out = [];
  for (const ref of refs) {
    const seg = ref >= 0 ? simple[ref] : [...simple[~ref]].reverse();
    for (let i = out.length ? 1 : 0; i < seg.length; i++) out.push(seg[i]);
  }
  return out;
}

// O world-atlas costura os polígonos no antimeridiano (Rússia, Fiji, Alasca, Antártida).
// Desenrola as longitudes e recorta de volta em uma ou mais janelas de 360°.
function clipLon(ring, limit, keepBelow) {
  const inside = (p) => (keepBelow ? p[0] <= limit : p[0] >= limit);
  const out = [];
  for (let i = 0; i < ring.length; i++) {
    const a = ring[i], b = ring[(i + 1) % ring.length];
    const ia = inside(a), ib = inside(b);
    if (ia) out.push(a);
    if (ia !== ib) {
      const t = (limit - a[0]) / (b[0] - a[0]);
      out.push([limit, a[1] + (b[1] - a[1]) * t]);
    }
  }
  return out;
}
function cutAntimeridian(ring) {
  let crosses = false;
  const un = [ring[0].slice()];
  for (let i = 1; i < ring.length; i++) {
    let lon = ring[i][0];
    const prev = un[i - 1][0];
    while (lon - prev > 180) lon -= 360;
    while (lon - prev < -180) lon += 360;
    if (Math.abs(lon - ring[i][0]) > 1) crosses = true;
    un.push([lon, ring[i][1]]);
  }
  if (!crosses) return [ring];
  const span = un[un.length - 1][0] - un[0][0];
  if (Math.abs(span) > 300) {
    // Anel que dá a volta no polo: fecha pela borda inferior do mapa.
    un.push([un[un.length - 1][0], -89.9], [un[0][0], -89.9]);
  }
  const pieces = [];
  for (const shift of [-360, 0, 360]) {
    let piece = un.map(([x, y]) => [x + shift, y]);
    piece = clipLon(piece, -180, false);
    if (piece.length) piece = clipLon(piece, 180, true);
    if (piece.length >= 3) pieces.push(piece);
  }
  return pieces;
}

function area(r) {
  let a = 0;
  for (let i = 0, j = r.length - 1; i < r.length; j = i++) a += r[j][0] * r[i][1] - r[i][0] * r[j][1];
  return a / 2;
}
function centroid(r) {
  let a = 0, cx = 0, cy = 0;
  for (let i = 0, j = r.length - 1; i < r.length; j = i++) {
    const c = r[j][0] * r[i][1] - r[i][0] * r[j][1];
    a += c; cx += (r[j][0] + r[i][0]) * c; cy += (r[j][1] + r[i][1]) * c;
  }
  return a ? [cx / (3 * a), cy / (3 * a)] : r[0];
}

const features = [];
const unmatched = [];
const matched = new Set();
for (const g of topo.objects.countries.geometries) {
  const name = g.properties.name;
  const iso = name === "Kosovo" ? "XKX" : numToIso.get(g.id) ?? OWNERS[name] ?? "";
  if (name === "Ashmore and Cartier Is." || name === "Indian Ocean Ter.") continue;
  if (!iso && name !== "Antarctica") unmatched.push(name); // fica neutro, sem país jogável
  if (iso) matched.add(iso);
  const polys = g.type === "Polygon" ? [g.arcs] : g.type === "MultiPolygon" ? g.arcs : [];
  const shapes = [];
  for (const poly of polys) {
    const lonlat = ringFromArcs(poly[0]);
    if (lonlat.length > 1) {
      const [a, b] = [lonlat[0], lonlat[lonlat.length - 1]];
      if (a[0] === b[0] && a[1] === b[1]) lonlat.pop();
    }
    if (lonlat.length < 3) continue;
    // Buracos (Lesoto na África do Sul etc.) já são cobertos pelo país de dentro.
    for (const piece of cutAntimeridian(lonlat)) {
      const ring = piece.map(project).filter((p, i, arr) => i === 0 || p[0] !== arr[i - 1][0] || p[1] !== arr[i - 1][1]);
      if (ring.length >= 3) shapes.push([ring]);
    }
  }
  if (!shapes.length) continue;
  const areas = shapes.map((s) => Math.abs(area(s[0])));
  const largest = Math.max(...areas);
  const kept = shapes.filter((_, i) => areas[i] >= MIN_ISLAND_AREA / 100 || areas[i] === largest || areas[i] > largest * 0.02);
  const biggest = shapes[areas.indexOf(largest)][0];
  features.push({
    iso, name,
    label: iso === "" || OWNERS[name] ? "" : (namesByIso.get(iso) ?? name),
    area: Math.round(kept.reduce((s, x) => s + Math.abs(area(x[0])), 0)),
    center: centroid(biggest).map((v) => +v.toFixed(1)),
    shapes: kept.map((s) => s.map((r) => r.flat())),
  });
}

const missing = [...numToIso.values()].filter((i) => !matched.has(i));
console.log("sem país na tabela (ignorados):", unmatched.join(", "));
console.log("países da tabela sem geometria:", missing.join(", ") || "nenhum");
const json = JSON.stringify({ width: WIDTH, features });
writeFileSync("data/map.json", json);
const verts = features.reduce((s, f) => s + f.shapes.flat().reduce((a, r) => a + r.length / 2, 0), 0);
console.log(`features=${features.length} vértices=${verts} bytes=${json.length}`);
// Conferência de identificadores: nome do atlas -> nome da tabela.
if (process.argv.includes("--check")) {
  for (const f of features) if (f.label) console.log(`${f.iso}\t${f.name}\t${f.label}`);
}
