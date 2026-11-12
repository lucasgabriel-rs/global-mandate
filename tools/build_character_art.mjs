// Draws the pieces of the stickman character in VectorCraft and exports the PNGs used by the game.
// Usage: node tools/build_character_art.mjs   (from the project root; needs vectorcraft-cli)
//
// Each piece has up to four layers, stacked in this order:
//   ink:  black outline, drawn underneath and slightly larger
//   base: fixed-color details under the chosen color (sclera, dark trousers)
//   fill: white, painted at game time with the chosen color (skin, hair, eyes, clothes)
//   top:  fixed-color details on top (pupil, tie, mouth)
import { execFileSync } from "node:child_process";
import { mkdirSync, writeFileSync, rmSync } from "node:fs";
import { resolve } from "node:path";

const OUT = resolve("assets/character");
const SCALE = 2;
const OUTLINE = 1.8;
const INK = "#2a2a30";

// Primitives: { d } is a closed path; { line, w } is a line with round ends.
const closed = (d, color) => ({ d, color });
const line = (pts, w, color) => ({ pts, w, color });
const circle = (x, y, r, color) => closed(`M${x - r} ${y} A${r} ${r} 0 1 1 ${x + r} ${y} A${r} ${r} 0 1 1 ${x - r} ${y} Z`, color);
const ellipse = (x, y, rx, ry, color) => closed(`M${x - rx} ${y} A${rx} ${ry} 0 1 1 ${x + rx} ${y} A${rx} ${ry} 0 1 1 ${x - rx} ${y} Z`, color);
const poly = (pts, color) => closed("M" + pts.map((p) => p.join(" ")).join(" L") + " Z", color);
const part = (fill = [], extra = {}) => ({ fill, ink: extra.ink ?? fill, base: extra.base ?? [], top: extra.top ?? [] });

// --- Faces: all with the same top of the head, so any hair fits any face.
const TOP = "M62 62 A38 40 0 0 1 138 62";
const FACES = [
  ["Redondo", `${TOP} A38 40 0 0 1 62 62 Z`],
  ["Oval", `${TOP} C138 92 118 112 100 112 C82 112 62 92 62 62 Z`],
  ["Quadrado", `${TOP} L138 90 Q138 103 125 103 L75 103 Q62 103 62 90 Z`],
  ["Triangular", `${TOP} C138 80 112 108 100 110 C88 108 62 80 62 62 Z`],
  ["Coração", `${TOP} C140 84 118 96 100 114 C82 96 60 84 62 62 Z`],
  ["Retangular", `${TOP} L136 98 Q136 112 122 112 L78 112 Q64 112 64 98 Z`],
];
const MOUTH = line([[92, 88], [100, 91], [108, 88]], 2.4, INK);

// --- Eyes: fixed sclera, iris in the chosen color, fixed pupil.
const EYE_X = [85, 115];
const both = (fn) => EYE_X.flatMap(fn);
const EYES = [
  ["Pontos", () => ({ fill: both((x) => [circle(x, 60, 4.2)]), ink: both((x) => [circle(x, 60, 4.2)]) })],
  ["Redondos", () => ({ base: both((x) => [circle(x, 60, 8.5, "#ffffff")]), fill: both((x) => [circle(x, 60, 5)]), top: both((x) => [circle(x, 60, 2.2, "#101014")]), ink: both((x) => [circle(x, 60, 8.5)]) })],
  ["Grandes", () => ({ base: both((x) => [circle(x, 59, 11, "#ffffff")]), fill: both((x) => [circle(x, 60, 7)]), top: both((x) => [circle(x, 60, 3, "#101014"), circle(x - 2, 57, 1.5, "#ffffff")]), ink: both((x) => [circle(x, 59, 11)]) })],
  ["Amendoados", () => {
    const shape = (x, c) => closed(`M${x - 10} 60 Q${x} 50 ${x + 10} 60 Q${x} 68 ${x - 10} 60 Z`, c);
    return { base: both((x) => [shape(x, "#ffffff")]), fill: both((x) => [circle(x, 59.5, 4.2)]), top: both((x) => [circle(x, 59.5, 1.9, "#101014")]), ink: both((x) => [shape(x)]) };
  }],
  ["Sonolentos", () => {
    const lid = (x) => closed(`M${x - 10} 59 Q${x} 49 ${x + 10} 59 Z`, "#2a2a30");
    return { base: both((x) => [circle(x, 60, 8.5, "#ffffff")]), fill: both((x) => [circle(x, 61, 5)]), top: both((x) => [circle(x, 61, 2.2, "#101014"), lid(x)]), ink: both((x) => [circle(x, 60, 8.5)]) };
  }],
  ["Felizes", () => ({ fill: [], ink: both((x) => [line([[x - 8, 62], [x, 54], [x + 8, 62]], 3)]) })],
];

// --- Hair: fill and back are drawn with the same color; back stays behind the body.
const HAIR = [
  ["Careca", {}, {}],
  ["Curto", { fill: [closed("M59 66 C56 28 80 18 100 18 C120 18 144 28 141 66 C134 48 122 42 100 42 C78 42 66 48 59 66 Z")] }, {}],
  ["Repartido", { fill: [closed("M58 68 C54 26 80 16 104 16 C128 16 146 30 142 68 C138 52 132 44 122 38 C104 48 80 50 66 48 C62 54 60 60 58 68 Z")] }, {}],
  ["Arrepiado", { fill: [poly([[58, 62], [52, 38], [68, 40], [66, 16], [84, 30], [92, 8], [106, 28], [122, 10], [126, 34], [146, 26], [138, 46], [148, 62], [128, 46], [100, 42], [76, 46]])] }, {}],
  ["Moicano", { fill: [poly([[90, 40], [84, 22], [92, 26], [90, 6], [100, 18], [106, 2], [110, 22], [116, 16], [110, 40]])] }, {}],
  ["Longo", { fill: [closed("M58 70 C54 26 80 16 100 16 C120 16 146 26 142 70 C136 50 122 42 100 42 C78 42 64 50 58 70 Z")] }, { fill: [closed("M56 60 C50 90 50 128 54 150 L146 150 C150 128 150 90 144 60 Z")] }],
  ["Rabo de cavalo", { fill: [closed("M59 66 C56 28 80 18 100 18 C120 18 144 28 141 66 C134 48 122 42 100 42 C78 42 66 48 59 66 Z")] }, { fill: [closed("M128 34 C160 36 168 76 156 120 C150 100 146 76 132 56 Z")] }],
  ["Coque", { fill: [closed("M59 66 C56 28 80 18 100 18 C120 18 144 28 141 66 C134 48 122 42 100 42 C78 42 66 48 59 66 Z"), circle(100, 12, 11)] }, {}],
  ["Black power", { fill: [closed("M60 58 C66 44 80 40 100 40 C120 40 134 44 140 58 C142 40 124 26 100 26 C76 26 58 40 60 58 Z")] }, { fill: [circle(100, 52, 54)] }],
  ["Cacheado", { fill: [circle(66, 44, 11), circle(78, 30, 12), circle(94, 24, 12), circle(110, 24, 12), circle(124, 31, 12), circle(135, 46, 11), closed("M64 56 C70 44 84 40 100 40 C116 40 130 44 136 56 C128 34 72 34 64 56 Z")] }, {}],
];

// --- Bodies: restroom-sign silhouette. Wide torso with rounded shoulders, thick straight
// arms and legs, separated only by a gap, which the outline fills.
const BODIES = [
  { name: "Médio", arm: 20, leg: 27, sx: 35, wx: 32, hx: 29, sy: 106, hy: 198, fy: 290, torso: "box" },
  { name: "Esguio", arm: 16, leg: 22, sx: 28, wx: 24, hx: 24, sy: 106, hy: 200, fy: 290, torso: "box" },
  { name: "Atlético", arm: 23, leg: 27, sx: 43, wx: 30, hx: 29, sy: 106, hy: 198, fy: 290, torso: "box" },
  { name: "Robusto", arm: 23, leg: 31, sx: 40, wx: 45, hx: 35, sy: 106, hy: 202, fy: 290, torso: "belly" },
  { name: "Alto", arm: 18, leg: 24, sx: 31, wx: 27, hx: 26, sy: 104, hy: 208, fy: 297, torso: "box" },
  { name: "Baixo", arm: 20, leg: 28, sx: 36, wx: 33, hx: 30, sy: 106, hy: 178, fy: 250, torso: "box" },
];
const GAP = 3;
function joints(b) {
  const handY = b.sy + (b.hy - b.sy) * 0.98;
  const inner = (b.leg + GAP) / 2;
  return {
    arms: [-1, 1].map((s) => {
      const x = 100 + s * (b.sx + GAP + b.arm / 2);
      return [[x, b.sy + b.arm / 2 + 3], [x + s * 1.5, handY]];
    }),
    legs: [-1, 1].map((s) => [[100 + s * inner, b.hy - 4], [100 + s * inner, b.fy - b.leg / 2]]),
  };
}
function torsoShape(b, grow = 0) {
  const g = grow, r = 12, l = 100 - b.sx - g, R = 100 + b.sx + g, t = b.sy - g;
  const bottom = b.hy + 4 + g;
  const shoulders = `M${l} ${t + r} Q${l} ${t} ${l + r} ${t} L${R - r} ${t} Q${R} ${t} ${R} ${t + r}`;
  if (b.torso === "belly") {
    return closed(`${shoulders} C${100 + b.wx + g + 3} ${t + 45} ${100 + b.wx + g} ${bottom - 20} ${100 + b.hx + g} ${bottom} L${100 - b.hx - g} ${bottom} C${100 - b.wx - g} ${bottom - 20} ${100 - b.wx - g - 3} ${t + 45} ${l} ${t + r} Z`);
  }
  return closed(`${shoulders} L${100 + b.wx + g} ${t + 55} L${100 + b.hx + g} ${bottom} L${100 - b.hx - g} ${bottom} L${100 - b.wx - g} ${t + 55} Z`);
}
function bodyPart(b) {
  const j = joints(b);
  const prims = [];
  for (const a of j.arms) prims.push(line(a, b.arm));
  for (const l of j.legs) prims.push(line(l, b.leg));
  prims.push(torsoShape(b));
  return part(prims);
}

// --- Clothes: one version for each body, over the same silhouette. Only what is in fill receives the color.
const DARK = "#2b2f3a";
const pants = (b, color) => joints(b).legs.map((l) => line([l[0], [l[1][0], l[1][1] - b.leg * 0.2]], b.leg + 1, color));
const armEnd = (a, f) => [a[0][0] + (a[1][0] - a[0][0]) * f, a[0][1] + (a[1][1] - a[0][1]) * f];
const sleeves = (b, f, extra = 1) => joints(b).arms.map((a) => line([a[0], armEnd(a, f)], b.arm + extra));
const shirt = (b) => [torsoShape(b, 1), ...sleeves(b, 0.8)];
const hipBand = (b) => poly([[100 - b.hx - 2, b.hy - 2], [100 + b.hx + 2, b.hy - 2], [100 + b.hx + 2, b.hy + 9], [100 - b.hx - 2, b.hy + 9]], DARK);
const tie = (b, color) => poly([[96, b.sy], [104, b.sy], [106, b.sy + 36], [100, b.sy + 46], [94, b.sy + 36]], color);
const OUTFITS = [
  ["Camiseta", (b) => ({ fill: [torsoShape(b, 1), ...sleeves(b, 0.42)], base: [...pants(b, DARK), hipBand(b)], ink: [torsoShape(b, 1), ...sleeves(b, 0.42), ...pants(b), hipBand(b)] })],
  ["Camisa e gravata", (b) => ({ fill: shirt(b), base: [...pants(b, DARK), hipBand(b)], top: [tie(b, "#7a2230")], ink: [...shirt(b), ...pants(b), hipBand(b)] })],
  ["Terno", (b) => ({ fill: [...shirt(b), ...pants(b)], top: [poly([[100 - 13, b.sy - 1], [100 + 13, b.sy - 1], [100, b.sy + 42]], "#f2f2ee"), tie(b, "#7a2230")], ink: [...shirt(b), ...pants(b)] })],
  ["Vestido", (b) => {
    const hem = b.hy + (b.fy - b.hy) * 0.62;
    const dress = closed(`M${100 - b.sx - 1} ${b.sy + 12} Q${100 - b.sx - 1} ${b.sy - 1} ${100 - b.sx + 11} ${b.sy - 1} L${100 + b.sx - 11} ${b.sy - 1} Q${100 + b.sx + 1} ${b.sy - 1} ${100 + b.sx + 1} ${b.sy + 12} L${100 + b.wx + 4} ${b.sy + 52} L${100 + b.hx + 26} ${hem} L${100 - b.hx - 26} ${hem} L${100 - b.wx - 4} ${b.sy + 52} Z`);
    return { fill: [dress], ink: [dress] };
  }],
  ["Farda", (b) => ({ fill: [...shirt(b), ...pants(b)], top: [poly([[100 - b.hx - 2, b.hy - 12], [100 + b.hx + 2, b.hy - 12], [100 + b.hx + 2, b.hy - 5], [100 - b.hx - 2, b.hy - 5]], "#22222a"), circle(100 + b.sx * 0.5, b.sy + 18, 3, "#e7c65a"), circle(100 - b.sx * 0.5, b.sy + 18, 3, "#c9362b")], ink: [...shirt(b), ...pants(b)] })],
  ["Macacão", (b) => ({ fill: [...shirt(b), ...pants(b)], top: [line([[100, b.sy + 2], [100, b.hy]], 1.8, "#2a2a30")], ink: [...shirt(b), ...pants(b)] })],
  ["Moletom", (b) => ({ fill: [...shirt(b), closed(`M74 ${b.sy + 2} Q100 ${b.sy - 22} 126 ${b.sy + 2} Q100 ${b.sy + 14} 74 ${b.sy + 2} Z`)], base: [...pants(b, DARK), hipBand(b)], top: [line([[94, b.sy + 8], [94, b.sy + 30]], 1.8, "#2a2a30"), line([[106, b.sy + 8], [106, b.sy + 30]], 1.8, "#2a2a30")], ink: [...shirt(b), ...pants(b), hipBand(b)] })],
  ["Túnica", (b) => {
    const robe = closed(`M${100 - b.sx - 1} ${b.sy + 12} Q${100 - b.sx - 1} ${b.sy - 1} ${100 - b.sx + 11} ${b.sy - 1} L${100 + b.sx - 11} ${b.sy - 1} Q${100 + b.sx + 1} ${b.sy - 1} ${100 + b.sx + 1} ${b.sy + 12} L${100 + b.hx + 22} ${b.fy - 12} L${100 - b.hx - 22} ${b.fy - 12} Z`);
    return { fill: [robe, ...sleeves(b, 0.85, 2)], ink: [robe, ...sleeves(b, 0.85, 2)] };
  }],
];

// --- Generation -----------------------------------------------------------------------
const steps = [];
const cmd = (command, params = {}) => steps.push({ command, params });
function drawPrim(p, mode) {
    // ink: everything black and thickened. fill: everything white. base and top: the detail's own color.
  const color = mode === "ink" ? INK : mode === "fill" ? "#ffffff" : (p.color ?? INK);
  const grow = mode === "ink" ? OUTLINE * 2 : 0;
  if (p.pts) {
    cmd("paint.setFill", { none: true });
    cmd("paint.setStroke", { color });
    cmd("stroke.set", { weight: p.w + grow, cap: "round", join: "round" });
    cmd("path.create", { anchors: p.pts.map(([x, y]) => ({ x, y })), closed: false });
  } else {
    cmd("paint.setFill", { color });
    if (grow) {
      cmd("paint.setStroke", { color });
      cmd("stroke.set", { weight: grow, cap: "round", join: "round" });
    } else {
      cmd("paint.setStroke", { none: true });
    }
    cmd("path.create", { d: p.d });
  }
  cmd("select.none");
}
function exportLayer(name, prims, mode, layers, tint) {
  if (!prims.length) return;
  const file = `${name}_${mode}.png`;
  cmd("file.new", { width: 200, height: 300, units: "Pixels", backgroundContents: "transparent" });
  for (const p of prims) drawPrim(p, mode);
  cmd("file.export", { path: `${OUT}/${file}`, scale: SCALE });
  cmd("file.close");
  layers.push(mode === "fill" ? { file, tint } : { file });
}
function exportPart(name, spec, tint) {
  const layers = [];
  for (const mode of ["ink", "base", "fill", "top"]) exportLayer(name, (spec[mode] ?? []).filter(Boolean), mode, layers, tint);
  return layers;
}

rmSync(OUT, { recursive: true, force: true });
mkdirSync(OUT, { recursive: true });
const manifest = { hair: [], eyes: [], face: [], body: [], outfit: [] };
HAIR.forEach(([label, front, back], i) => manifest.hair.push({
  label, front: exportPart(`hair_${i}_front`, front, "hair"), back: exportPart(`hair_${i}_back`, back, "hair"),
}));
EYES.forEach(([label, fn], i) => manifest.eyes.push({ label, layers: exportPart(`eyes_${i}`, fn(), "eyes") }));
FACES.forEach(([label, d], i) => manifest.face.push({ label, layers: exportPart(`face_${i}`, { fill: [closed(d)], ink: [closed(d)], top: [MOUTH] }, "skin") }));
BODIES.forEach((b, i) => manifest.body.push({ label: b.name, layers: exportPart(`body_${i}`, bodyPart(b), "skin") }));
OUTFITS.forEach(([label, fn], o) => manifest.outfit.push({ label, byBody: BODIES.map((b, i) => exportPart(`outfit_${o}_${i}`, fn(b), "clothes")) }));

const result = execFileSync("vectorcraft-cli", ["run", "--commands", "-"], { input: JSON.stringify(steps), maxBuffer: 1 << 28 }).toString();
const failures = result.split("\n").filter((l) => l.includes('"error"'));
if (failures.length) throw new Error(`VectorCraft: ${failures.length} erros\n${failures.slice(0, 3).join("\n")}`);
writeFileSync(`${OUT}/manifest.json`, JSON.stringify(manifest));
console.log(`passos=${steps.length} imagens=${steps.filter((s) => s.command === "file.export").length}`);
