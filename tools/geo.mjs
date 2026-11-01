// Funções comuns dos geradores de dados do mapa: projeção Robinson, simplificação e arcos.
const WIDTH = 2000;

const ROB_X = [1,0.9986,0.9954,0.99,0.9822,0.973,0.96,0.9427,0.9216,0.8962,0.8679,0.835,0.7986,0.7597,0.7186,0.6732,0.6213,0.5722,0.5322];
const ROB_Y = [0,0.062,0.124,0.186,0.248,0.31,0.372,0.434,0.4958,0.5571,0.6176,0.6769,0.7346,0.7903,0.8435,0.8936,0.9394,0.9761,1];
export function project([lon, lat]) {
  const al = Math.min(Math.abs(lat), 89.999);
  const i = Math.floor(al / 5), f = al / 5 - i;
  const px = ROB_X[i] + (ROB_X[i + 1] - ROB_X[i]) * f;
  const py = ROB_Y[i] + (ROB_Y[i + 1] - ROB_Y[i]) * f;
  return [+(lon * px * WIDTH / 360).toFixed(2), +(-Math.sign(lat) * py * WIDTH * 0.2535).toFixed(2)];
}

export function simplify(points, tol) {
  if (points.length < 3) return points;
  const keep = new Uint8Array(points.length);
  keep[0] = keep[points.length - 1] = 1;
  const stack = [[0, points.length - 1]];
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

export function area(r) {
  let a = 0;
  for (let i = 0, j = r.length - 1; i < r.length; j = i++) a += r[j][0] * r[i][1] - r[i][0] * r[j][1];
  return Math.abs(a) / 2;
}
export function centroid(r) {
  let a = 0, cx = 0, cy = 0;
  for (let i = 0, j = r.length - 1; i < r.length; j = i++) {
    const c = r[j][0] * r[i][1] - r[i][0] * r[j][1];
    a += c; cx += (r[j][0] + r[i][0]) * c; cy += (r[j][1] + r[i][1]) * c;
  }
  return a ? [cx / (3 * a), cy / (3 * a)] : r[0];
}
export const key = (p) => p[0] + "," + p[1];

// Divide os anéis em arcos e simplifica cada arco uma vez só: uma divisa fica idêntica nos dois lados.
export function buildArcs(units, tolerance) {
  // Grau de cada vértice no grafo de divisas: mais de dois vizinhos marca o fim de um arco.
  const neighbors = new Map();
  const note = (a, b) => {
    let s = neighbors.get(a);
    if (!s) neighbors.set(a, (s = new Set()));
    s.add(b);
  };
  for (const u of units) {
    for (const r of u.rings) {
      for (let i = 0; i < r.length; i++) {
        const a = key(r[i]), b = key(r[(i + 1) % r.length]);
        note(a, b); note(b, a);
      }
    }
  }
  const isJunction = (p) => (neighbors.get(key(p))?.size ?? 0) > 2;

  // Cada arco é guardado em direção canônica, para os dois lados obterem os mesmos pontos.
  const arcCache = new Map();
  function canonicalArc(run) {
    const n = run.length;
    const fwd = key(run[0]) + "|" + key(run[1]) + "|" + key(run[n - 2]) + "|" + key(run[n - 1]) + "|" + n;
    const rev = key(run[n - 1]) + "|" + key(run[n - 2]) + "|" + key(run[1]) + "|" + key(run[0]) + "|" + n;
    const reversed = rev < fwd;
    const id = reversed ? rev : fwd;
    let entry = arcCache.get(id);
    if (!entry) {
      entry = { points: simplify(reversed ? [...run].reverse() : run, tolerance), owners: new Set() };
      arcCache.set(id, entry);
    }
    return { entry, reversed };
  }

  function simplifyRing(ring, unitIndex) {
    const n = ring.length;
    let start = -1;
    for (let i = 0; i < n; i++) if (isJunction(ring[i])) { start = i; break; }
    if (start < 0) return simplify([...ring, ring[0]], tolerance).slice(0, -1);
    const out = [];
    let run = [ring[start]];
    for (let k = 1; k <= n; k++) {
      const p = ring[(start + k) % n];
      run.push(p);
      if (isJunction(p)) {
        const { entry, reversed } = canonicalArc(run);
        entry.owners.add(unitIndex);
        const pts = reversed ? [...entry.points].reverse() : entry.points;
        for (let i = 0; i < pts.length - 1; i++) out.push(pts[i]);
        run = [p];
      }
    }
    return out;
  }

  return { simplifyRing, arcCache };
}
