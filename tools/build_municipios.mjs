// Converte a malha municipal do Brasil (IBGE, via tbrugz/geodata-br) em data/municipios.json.
// Uso: node tools/build_municipios.mjs   (a partir da raiz do projeto)
//
// O código IBGE do município começa com o código do estado. Só as divisas entre municípios do
// mesmo estado vão para "arcs": as divisas entre estados já vêm de data/admin1.json.
import { readFileSync, writeFileSync } from "node:fs";
import { project, area, centroid, key, buildArcs } from "./geo.mjs";

const TOLERANCE_DEG = 0.012;
const STATES = {
  11: "Rondônia", 12: "Acre", 13: "Amazonas", 14: "Roraima", 15: "Pará", 16: "Amapá", 17: "Tocantins",
  21: "Maranhão", 22: "Piauí", 23: "Ceará", 24: "Rio Grande do Norte", 25: "Paraíba", 26: "Pernambuco",
  27: "Alagoas", 28: "Sergipe", 29: "Bahia", 31: "Minas Gerais", 32: "Espírito Santo", 33: "Rio de Janeiro",
  35: "São Paulo", 41: "Paraná", 42: "Santa Catarina", 43: "Rio Grande do Sul", 50: "Mato Grosso do Sul",
  51: "Mato Grosso", 52: "Goiás", 53: "Distrito Federal",
};

const raw = JSON.parse(readFileSync("tools/raw/geojs-100-mun.json", "utf8"));
function insideRing(p, ring) {
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [xi, yi] = ring[i], [xj, yj] = ring[j];
    if ((yi > p[1]) !== (yj > p[1]) && p[0] < ((xj - xi) * (p[1] - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}
// A fonte guarda ilhas como anéis do mesmo polígono, e o continente nem sempre vem primeiro.
// Cada anel é uma peça, exceto os que estão dentro de outro maior, que são furos.
function outerRings(rings) {
  const sorted = [...rings].sort((a, b) => area(b) - area(a));
  const kept = [];
  for (const r of sorted) if (!kept.some((k) => insideRing(r[0], k))) kept.push(r);
  return kept.map((r) => r.slice(0, -1));
}
const units = raw.features.map((f) => ({
  name: f.properties.name, state: STATES[String(f.properties.id).slice(0, 2)],
  rings: (f.geometry.type === "Polygon" ? [f.geometry.coordinates] : f.geometry.coordinates).flatMap(outerRings),
}));
const missing = units.filter((u) => !u.state);
if (missing.length) throw new Error("município sem estado: " + missing[0].name);

const { simplifyRing, arcCache } = buildArcs(units, TOLERANCE_DEG);
const output = units.map((u, i) => {
  let pieces = [];
  for (const r of u.rings) {
    const ring = simplifyRing(r, i).map(project).filter((p, k, arr) => k === 0 || key(p) !== key(arr[k - 1]));
    if (ring.length >= 3) pieces.push(ring);
  }
  // Município pequeno demais para a tolerância: usa o anel original, só projetado.
  if (!pieces.length) pieces = u.rings.filter((r) => r.length >= 3).map((r) => r.map(project));
  const flat = pieces.flat();
  const xs = flat.map((p) => p[0]), ys = flat.map((p) => p[1]);
  const biggest = pieces.reduce((a, b) => (area(b) > area(a) ? b : a));
  return {
    n: u.name, uf: u.state, c: centroid(biggest).map((v) => +v.toFixed(2)),
    b: [Math.min(...xs), Math.min(...ys), Math.max(...xs), Math.max(...ys)],
    a: +pieces.reduce((s, r) => s + area(r), 0).toFixed(3), s: pieces.map((r) => r.flat()),
  };
});

const arcs = [];
for (const { points, owners } of arcCache.values()) {
  const ids = [...owners];
  if (ids.length === 2 && units[ids[0]].state === units[ids[1]].state) arcs.push([ids[0], ids[1], points.map(project).flat()]);
}
const json = JSON.stringify({ units: output, arcs });
writeFileSync("data/municipios.json", json);
const verts = output.reduce((s, u) => s + u.s.reduce((a, r) => a + r.length / 2, 0), 0);
const lineVerts = arcs.reduce((s, a) => s + a[2].length / 2, 0);
console.log(`municípios=${output.length} vértices=${verts} arcos=${arcs.length} vértices de divisa=${lineVerts} bytes=${json.length}`);
