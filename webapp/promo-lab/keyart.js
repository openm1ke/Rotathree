// The key art of RotaThree, a fantasy on the game rather than a picture of
// it, in the light of the 1980s films of glowing lines: a glass drawn only by
// its edges stands in a coordinate plane, sticks of three fall into it with
// trails of light, and through the grid the stack below glows and waits.
// render.mjs photographs it in every format.
import * as THREE from 'three';
import { EffectComposer } from 'three/examples/jsm/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/examples/jsm/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/examples/jsm/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/examples/jsm/postprocessing/OutputPass.js';
import { LineSegments2 } from 'three/examples/jsm/lines/LineSegments2.js';
import { LineSegmentsGeometry } from 'three/examples/jsm/lines/LineSegmentsGeometry.js';
import { LineMaterial } from 'three/examples/jsm/lines/LineMaterial.js';
import '@fontsource/exo-2/600.css';
import '@fontsource/exo-2/900-italic.css';

const query = new URLSearchParams(location.search);
const format = query.get('format') ?? '16x9';
const words = query.get('text') ?? 'en';
const art = document.getElementById('art');
art.dataset.format = format;
const TAGLINES = {
  en: '<b>Turn</b> the cross. <b>Match</b> three.',
  ru: '<b>Поверни</b> крест. <b>Собери</b> три.',
};
document.getElementById('copy').hidden = !(words in TAGLINES);
document.getElementById('tagline').innerHTML = TAGLINES[words] ?? '';

/** The classic set of the game (src/render/theme.ts). */
const COLOURS = ['#ff3d5e', '#3b82ff', '#ffc531', '#2fd985', '#a65cff'];
const GRID = new THREE.Color('#25e3f2');
const FAR = new THREE.Color('#ff3da6');
const EDGE = '#c9fbff';
const W = 2; // half the glass's width: a 4 × 4 shaft
const TOP = 9;
const BOTTOM = -6;

/** The eye stands at the upper edge of the glass, to its left, and looks
 * down into it at the stack gathering below, per format. `shift` moves the
 * picture across the frame (a share of its width and height), to leave room
 * for the words. */
const VIEWS = {
  '16x9': { fov: 60, eye: [-4.2, -5.8, 14.6], look: [0.3, 0.5, -3], shift: [0.17, -0.02] },
  feature: { fov: 54, eye: [-4.2, -5.8, 14.6], look: [0.3, 0.5, -3], shift: [0.21, -0.02] },
  '9x16': { fov: 72, eye: [-3.2, -4.6, 14.8], look: [0.2, 0.3, -3.2], shift: [0, 0.08] },
  '1x1': { fov: 64, eye: [-3.8, -5.3, 14.7], look: [0.3, 0.4, -3], shift: [0, 0.1] },
};
const view = { ...VIEWS[format] ?? VIEWS['16x9'] };
if (!(words in TAGLINES)) view.shift = [0, 0];

const canvas = document.getElementById('scene');
const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, preserveDrawingBuffer: true });
renderer.setPixelRatio(window.devicePixelRatio);
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.0;
const dpr = window.devicePixelRatio;

const scene = new THREE.Scene();
{
  // Far off, the plane dissolves into a violet haze at the top of the frame.
  const sky = document.createElement('canvas');
  sky.width = 2;
  sky.height = 512;
  const s = sky.getContext('2d');
  const haze = s.createLinearGradient(0, 0, 0, 512);
  haze.addColorStop(0, '#2b0a46');
  haze.addColorStop(0.35, '#12072a');
  haze.addColorStop(0.7, '#05040f');
  haze.addColorStop(1, '#020207');
  s.fillStyle = haze;
  s.fillRect(0, 0, 2, 512);
  const texture = new THREE.CanvasTexture(sky);
  texture.colorSpace = THREE.SRGBColorSpace;
  scene.background = texture;
}

const camera = new THREE.PerspectiveCamera(view.fov, 1, 0.5, 900);
camera.up.set(0, 0, 1);
camera.position.set(...view.eye);
camera.lookAt(...view.look);

scene.add(new THREE.HemisphereLight('#7fe9ff', '#1a0630', 0.6));
const key = new THREE.DirectionalLight('#ffffff', 0.9);
key.position.set(-20, -16, 30);
scene.add(key);

/** Lines of a width in screen pixels, coloured per vertex. */
const lineMaterials = [];
const lines = (positions, colors, width, { additive = false, opacity = 1 } = {}) => {
  const geometry = new LineSegmentsGeometry();
  geometry.setPositions(positions);
  geometry.setColors(colors);
  const material = new LineMaterial({
    vertexColors: true,
    linewidth: width * dpr,
    transparent: additive || opacity < 1,
    opacity,
    blending: additive ? THREE.AdditiveBlending : THREE.NormalBlending,
    depthWrite: !additive,
  });
  lineMaterials.push(material);
  const mesh = new LineSegments2(geometry, material);
  scene.add(mesh);
  return mesh;
};
const rgb = (colour, scale = 1) => {
  const c = new THREE.Color(colour);
  return [c.r * scale, c.g * scale, c.b * scale];
};

// --- The coordinate plane: a glowing grid, cyan near, magenta far, with a
// dark veil over what lies below it.
{
  const material = new THREE.ShaderMaterial({
    transparent: true,
    depthWrite: false,
    uniforms: { near: { value: GRID }, far: { value: FAR } },
    vertexShader: /* glsl */ `
      varying vec3 vWorld;
      void main() {
        vec4 world = modelMatrix * vec4(position, 1.0);
        vWorld = world.xyz;
        gl_Position = projectionMatrix * viewMatrix * world;
      }`,
    fragmentShader: /* glsl */ `
      uniform vec3 near;
      uniform vec3 far;
      varying vec3 vWorld;
      float grid(vec2 p, float cell, float width) {
        vec2 q = p / cell;
        vec2 g = abs(fract(q - 0.5) - 0.5) / fwidth(q);
        return 1.0 - min(min(g.x, g.y) / width, 1.0);
      }
      void main() {
        float d = length(vWorld.xy);
        float fade = exp(-d * 0.024);
        float minor = grid(vWorld.xy, 1.0, 0.8) * 0.16;
        float major = grid(vWorld.xy, 4.0, 1.3) * 0.85;
        // Over the mouth of the glass the cells of the plane show plainly,
        // a pane of light one looks through at the stack below.
        float inside = step(abs(vWorld.x), 2.0) * step(abs(vWorld.y), 2.0);
        float cells = grid(vWorld.xy, 1.0, 1.0) * inside * 0.28;
        float line = max(max(minor, major) * fade * (1.0 + 1.4 * exp(-d * 0.18)), cells);
        vec3 tone = mix(far, near, smoothstep(0.0, 1.0, fade * 1.8));
        float veil = 0.66 * exp(-d * 0.018) * (1.0 - 0.7 * inside);
        float alpha = line + veil * (1.0 - line);
        vec3 pane = vec3(0.05, 0.22, 0.32) * inside;
        vec3 colour = (tone * line + (vec3(0.0, 0.015, 0.05) + pane) * veil * (1.0 - line)) / max(alpha, 0.001);
        gl_FragColor = vec4(colour, alpha);
      }`,
  });
  const plane = new THREE.Mesh(new THREE.PlaneGeometry(800, 800), material);
  plane.renderOrder = 2;
  scene.add(plane);
}

// --- The glass: only its edges, bright where they cross the plane.
{
  const p = [];
  const c = [];
  const segment = (a, b, colour, scale = 1) => {
    p.push(...a, ...b);
    c.push(...rgb(colour, scale), ...rgb(colour, scale));
  };
  const corners = [[-W, -W], [W, -W], [W, W], [-W, W]];
  corners.forEach(([x, y]) => {
    segment([x, y, 0], [x, y, TOP], EDGE, 0.58);
    p.push(x, y, BOTTOM, x, y, 0);
    c.push(0, 0, 0, ...rgb(EDGE, 0.5));
  });
  const ring = (z, colour, scale) => corners.forEach(([x, y], i) => {
    const [nx, ny] = corners[(i + 1) % 4];
    segment([x, y, z], [nx, ny, z], colour, scale);
  });
  ring(TOP, EDGE, 0.7);
  ring(0, '#d8fbff', 0.62);
  lines(p, c, 2.6);

  // Faint rings up the glass, and the lanes of its cells on its walls.
  const q = [];
  const k = [];
  const faint = (a, b, scale) => {
    q.push(...a, ...b);
    k.push(...rgb('#2fd7ff', scale), ...rgb('#2fd7ff', scale));
  };
  for (let z = BOTTOM + 1; z < TOP; z++) {
    if (z === 0) continue;
    corners.forEach(([x, y], i) => {
      const [nx, ny] = corners[(i + 1) % 4];
      faint([x, y, z], [nx, ny, z], (z % 4 === 0 ? 0.3 : 0.12) * (z < 0 ? 0.6 * (1 + z / -BOTTOM) : 1));
    });
  }
  for (let t = -W + 1; t < W; t++) {
    faint([t, -W, 0], [t, -W, TOP], 0.12);
    faint([t, W, 0], [t, W, TOP], 0.12);
    faint([-W, t, 0], [-W, t, TOP], 0.12);
    faint([W, t, 0], [W, t, TOP], 0.12);
  }
  lines(q, k, 1.3, { additive: true });

  // The mouth of the glass: corner marks above it.
  const m = [];
  const n = [];
  corners.forEach(([x, y]) => {
    const sx = Math.sign(x);
    const sy = Math.sign(y);
    const z = TOP + 0.01;
    m.push(x, y, z, x - sx * 1.1, y, z, x, y, z, x, y - sy * 1.1, z, x, y, z, x, y, z + 1.1);
    for (let i = 0; i < 6; i++) n.push(...rgb('#ff3da6', 0.95));
  });
  lines(m, n, 3.6);
}

// --- Cubes of light: dark faces, bright edges in the colours of the game.
const cubeFaces = new THREE.BoxGeometry(0.9, 0.9, 0.9);
const faceMaterials = new Map();
const edgePositions = [];
const edgeColors = [];
const cubeEdges = (() => {
  const h = 0.45;
  const v = [[-h, -h, -h], [h, -h, -h], [h, h, -h], [-h, h, -h], [-h, -h, h], [h, -h, h], [h, h, h], [-h, h, h]];
  return [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4], [0, 4], [1, 5], [2, 6], [3, 7]].map(([a, b]) => [v[a], v[b]]);
})();
const cube = (x, y, z, colour, glow) => {
  const id = `${colour}:${glow}`;
  if (!faceMaterials.has(id)) {
    const base = new THREE.Color(colour);
    faceMaterials.set(id, new THREE.MeshStandardMaterial({
      color: base.clone().multiplyScalar(0.12),
      emissive: base,
      emissiveIntensity: (glow > 1.2 ? 0.45 : 0.34) * glow,
      roughness: 0.35,
      metalness: 0.6,
      transparent: true,
      opacity: 0.88,
    }));
  }
  const mesh = new THREE.Mesh(cubeFaces, faceMaterials.get(id));
  mesh.position.set(x + 0.5, y + 0.5, z + 0.5);
  scene.add(mesh);
  // The edges keep the cube's colour, as bright as it goes but under the
  // bloom's threshold, so green and yellow do not burn into a white haze.
  const tint = new THREE.Color(colour);
  const luma = 0.299 * tint.r + 0.587 * tint.g + 0.114 * tint.b;
  tint.multiplyScalar(Math.min(glow, 0.44 / luma, 1 / Math.max(tint.r, tint.g, tint.b)));
  cubeEdges.forEach(([a, b]) => {
    edgePositions.push(x + 0.5 + a[0], y + 0.5 + a[1], z + 0.5 + a[2], x + 0.5 + b[0], y + 0.5 + b[1], z + 0.5 + b[2]);
    edgeColors.push(tint.r, tint.g, tint.b, tint.r, tint.g, tint.b);
  });
};

const random = mulberry32(19);
const pick = () => COLOURS[Math.floor(random() * COLOURS.length)];

// The stack under the plane: layers of sticks, crosswise in turn, brightest
// on top where the next stick will land.
const LAYERS = 4;
for (let layer = 0; layer < LAYERS; layer++) {
  const z = BOTTOM + layer;
  const glow = 0.4 + (layer / (LAYERS - 1)) * 0.7;
  const along = layer % 2 === 0;
  for (let lane = -W; lane < W; lane++) {
    if (layer === LAYERS - 1 && (lane === -1 || lane === 1)) continue; // the top layer is not full
    const start = random() < 0.5 ? -W : -W + 1;
    for (let i = 0; i < 3; i++) {
      const [x, y] = along ? [start + i, lane] : [lane, start + i];
      cube(x, y, z, pick(), glow);
    }
  }
}

// Sticks falling into the glass, and one more above its mouth.
const falling = [
  { cells: [[-1, -1], [0, -1], [1, -1]], z: 2.2, colours: ['#ff3d5e', '#3b82ff', '#ff3d5e'] },
  { cells: [[0, -2], [0, -1], [0, 0]], z: 5.6, colours: ['#2fd985', '#a65cff', '#2fd985'] },
];
const trailPositions = [];
const trailColors = [];
falling.forEach(({ cells, z, colours }, s) => {
  cells.forEach(([x, y], i) => {
    cube(x, y, z, colours[i], 1.35);
    // Light trails rise from the top corners of each cube and fade.
    const tint = new THREE.Color(colours[i]);
    const length = s === 1 ? 2.6 : 3.6;
    [[0.05, 0.05], [0.95, 0.05], [0.95, 0.95], [0.05, 0.95]].forEach(([dx, dy]) => {
      trailPositions.push(x + dx, y + dy, z + 0.95, x + dx, y + dy, z + 0.95 + length);
      trailColors.push(tint.r * 0.6, tint.g * 0.6, tint.b * 0.6, 0, 0, 0);
    });
  });
});

// Where the lowest stick will land: an outline on the stack, under the plane.
const ghost = [];
const ghostColours = [];
[[-1, -1], [0, -1], [1, -1]].forEach(([x, y]) => {
  const z = BOTTOM + LAYERS;
  cubeEdges.forEach(([a, b]) => {
    ghost.push(x + 0.5 + a[0], y + 0.5 + a[1], z + 0.5 + a[2], x + 0.5 + b[0], y + 0.5 + b[1], z + 0.5 + b[2]);
    ghostColours.push(...rgb('#ff3d5e', 0.9), ...rgb('#ff3d5e', 0.9));
  });
});

lines(trailPositions, trailColors, 2.2, { additive: true });
lines(ghost, ghostColours, 1.4, { additive: true });

// A glow welling up out of the glass through the plane.
{
  const well = document.createElement('canvas');
  well.width = well.height = 128;
  const g = well.getContext('2d');
  const light = g.createRadialGradient(64, 64, 0, 64, 64, 64);
  light.addColorStop(0, 'rgba(120, 230, 255, 0.04)');
  light.addColorStop(0.3, 'rgba(110, 200, 255, 0.12)');
  light.addColorStop(0.6, 'rgba(90, 120, 255, 0.05)');
  light.addColorStop(1, 'rgba(60, 40, 160, 0)');
  g.fillStyle = light;
  g.fillRect(0, 0, 128, 128);
  const mesh = new THREE.Mesh(
    new THREE.PlaneGeometry(22, 22),
    new THREE.MeshBasicMaterial({ map: new THREE.CanvasTexture(well), transparent: true, blending: THREE.AdditiveBlending, depthWrite: false }),
  );
  mesh.position.z = 0.02;
  mesh.renderOrder = 3;
  scene.add(mesh);
}

// --- Under the plane the stack is a centre shared by more glasses: four
// reach out to the sides and one goes down, fading into the dark, each with
// a stick of its own falling towards the centre. Ours is only one way in.
const LOW = -6; // the shared centre spans LOW..HIGH under the plane
const HIGH = -2;
{
  const p = [];
  const c = [];
  const tone = '#8fa6ff';
  const span = 15;
  const arm = (point) => {
    // `point(a, b, t)`: the corner (a, b) of the cross-section, t along the arm.
    const corners = [[0, 0], [1, 0], [1, 1], [0, 1]];
    corners.forEach(([a, b]) => {
      p.push(...point(a, b, 0), ...point(a, b, span));
      c.push(...rgb(tone, 0.5), 0, 0, 0);
    });
    for (let t = 2; t < span; t += 2) {
      const fade = 0.28 * (1 - t / span);
      corners.forEach(([a, b], i) => {
        const [na, nb] = corners[(i + 1) % 4];
        p.push(...point(a, b, t), ...point(na, nb, t));
        c.push(...rgb(tone, fade), ...rgb(tone, fade));
      });
    }
  };
  const across = (a) => -W + a * 2 * W;
  const deep = (b) => LOW + b * (HIGH - LOW);
  arm((a, b, t) => [W + t, across(a), deep(b)]);
  arm((a, b, t) => [-W - t, across(a), deep(b)]);
  arm((a, b, t) => [across(a), W + t, deep(b)]);
  arm((a, b, t) => [across(a), -W - t, deep(b)]);
  arm((a, b, t) => [across(a), across(b), LOW - t]);
  // The shared centre itself.
  [LOW, HIGH].forEach((z) => [[-W, -W], [W, -W], [W, W], [-W, W]].forEach(([x, y], i, all) => {
    const [nx, ny] = all[(i + 1) % 4];
    p.push(x, y, z, nx, ny, z);
    c.push(...rgb(tone, 0.45), ...rgb(tone, 0.45));
  }));
  lines(p, c, 1.6, { additive: true });

  // A stick in each, falling towards the centre, its trail behind it.
  const q = [];
  const k = [];
  const stick = (cells, away) => cells.forEach(([x, y, z]) => {
    const colour = pick();
    cube(x, y, z, colour, 0.42);
    const tint = new THREE.Color(colour);
    [[0.1, 0.1], [0.9, 0.1], [0.9, 0.9], [0.1, 0.9]].forEach(([u, v]) => {
      const start = away[0] !== 0 ? [x + (away[0] > 0 ? 1 : 0), y + u, z + v]
        : away[1] !== 0 ? [x + u, y + (away[1] > 0 ? 1 : 0), z + v]
        : [x + u, y + v, z];
      q.push(...start, start[0] + away[0] * 2.5, start[1] + away[1] * 2.5, start[2] + away[2] * 2.5);
      k.push(tint.r * 0.35, tint.g * 0.35, tint.b * 0.35, 0, 0, 0);
    });
  });
  stick([[7, -1, -4], [7, 0, -4], [7, 1, -4]], [1, 0, 0]);
  stick([[-9, -1, -5], [-9, 0, -5], [-9, 1, -5]], [-1, 0, 0]);
  stick([[-1, 8, -4], [0, 8, -4], [1, 8, -4]], [0, 1, 0]);
  stick([[-1, -10, -5], [0, -10, -5], [1, -10, -5]], [0, -1, 0]);
  stick([[-1, 0, -13], [0, 0, -13], [1, 0, -13]], [0, 0, -1]);
  lines(q, k, 1.6, { additive: true });
}

// --- Walls of light left by racers on the grid, turning at right angles.
const wall = (path, colour, headSize = 0.5) => {
  const height = 0.9;
  const p = [];
  const c = [];
  path.forEach(([x, y], i) => {
    if (i === 0) return;
    const [px, py] = path[i - 1];
    p.push(px, py, height, x, y, height, px, py, 0.02, x, y, 0.02);
    const fade = i / (path.length - 1);
    c.push(...rgb(colour, 0.22 + 0.55 * fade), ...rgb(colour, 0.22 + 0.55 * fade), ...rgb(colour, 0.15), ...rgb(colour, 0.15));
    const sheet = new THREE.Mesh(
      new THREE.PlaneGeometry(Math.hypot(x - px, y - py), height),
      new THREE.MeshBasicMaterial({ color: colour, transparent: true, opacity: 0.05 + 0.09 * fade, side: THREE.DoubleSide, depthWrite: false, blending: THREE.AdditiveBlending }),
    );
    sheet.position.set((x + px) / 2, (y + py) / 2, height / 2);
    sheet.rotation.set(Math.PI / 2, Math.atan2(y - py, x - px), 0, 'ZXY');
    scene.add(sheet);
  });
  lines(p, c, 1.8);
  const [hx, hy] = path[path.length - 1];
  const head = new THREE.Mesh(new THREE.BoxGeometry(headSize, headSize, headSize), new THREE.MeshBasicMaterial({ color: new THREE.Color(colour).multiplyScalar(1.3) }));
  head.position.set(hx, hy, headSize * 0.8);
  scene.add(head);
};
wall([[-28, 7], [-16, 7], [-16, 1], [-12, 1]], '#25e3f2', 0.3);
wall([[18, -9], [6, -9], [6, -5], [9, -5]], '#ff9a2e');

// --- Pixels of light rising off the plane at the sides.
{
  const pixel = document.createElement('canvas');
  pixel.width = pixel.height = 32;
  const q = pixel.getContext('2d');
  q.shadowColor = '#ffffff';
  q.shadowBlur = 8;
  q.fillStyle = '#ffffff';
  q.fillRect(10, 10, 12, 12);
  const positions = [];
  const colors = [];
  const tones = ['#25e3f2', '#ff3da6', '#ffc531', '#2fd985', '#a65cff'].map((t) => new THREE.Color(t));
  for (let i = 0; i < 140; i++) {
    const angle = random() * Math.PI * 2;
    const reach = 9 + random() * 30;
    positions.push(Math.cos(angle) * reach, Math.sin(angle) * reach, 0.5 + random() ** 1.6 * 14);
    const t = tones[Math.floor(random() * tones.length)];
    colors.push(t.r * 1.4, t.g * 1.4, t.b * 1.4);
  }
  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
  geometry.setAttribute('color', new THREE.Float32BufferAttribute(colors, 3));
  const points = new THREE.Points(geometry, new THREE.PointsMaterial({
    size: 7 * dpr, sizeAttenuation: false, map: new THREE.CanvasTexture(pixel), vertexColors: true,
    transparent: true, blending: THREE.AdditiveBlending, depthWrite: false,
  }));
  points.renderOrder = 4;
  scene.add(points);
}

// --- Bits of light drifting over the plane.
{
  const dot = document.createElement('canvas');
  dot.width = dot.height = 32;
  const d = dot.getContext('2d');
  const spot = d.createRadialGradient(16, 16, 0, 16, 16, 16);
  spot.addColorStop(0, 'rgba(255,255,255,1)');
  spot.addColorStop(0.35, 'rgba(255,255,255,0.6)');
  spot.addColorStop(1, 'rgba(255,255,255,0)');
  d.fillStyle = spot;
  d.fillRect(0, 0, 32, 32);
  const positions = [];
  const colors = [];
  const tones = ['#25e3f2', '#ff3da6', '#ffb347', '#7f8bff'].map((c) => new THREE.Color(c));
  for (let i = 0; i < 160; i++) {
    const angle = random() * Math.PI * 2;
    const reach = 5 + random() ** 0.8 * 70;
    positions.push(Math.cos(angle) * reach, Math.sin(angle) * reach, random() < 0.6 ? 0.05 : random() * 22);
    const t = tones[Math.floor(random() * tones.length)];
    colors.push(t.r, t.g, t.b);
  }
  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
  geometry.setAttribute('color', new THREE.Float32BufferAttribute(colors, 3));
  const points = new THREE.Points(geometry, new THREE.PointsMaterial({
    size: 4 * dpr, sizeAttenuation: false, map: new THREE.CanvasTexture(dot), vertexColors: true,
    transparent: true, blending: THREE.AdditiveBlending, depthWrite: false,
  }));
  points.renderOrder = 4;
  scene.add(points);
}

// Every cube's edges, now that all the cubes exist.
lines(edgePositions, edgeColors, 2.4);

// --- Post: a strong bloom for the glow of the lines.
const composer = new EffectComposer(renderer, new THREE.WebGLRenderTarget(1, 1, { type: THREE.HalfFloatType, samples: 4 }));
composer.addPass(new RenderPass(scene, camera));
const bloom = new UnrealBloomPass(new THREE.Vector2(1, 1), 0.9, 0.55, 0.55);
composer.addPass(bloom);
composer.addPass(new OutputPass());

function resize() {
  const width = art.clientWidth;
  const height = art.clientHeight;
  renderer.setSize(width, height, false);
  composer.setPixelRatio(dpr);
  composer.setSize(width, height);
  lineMaterials.forEach((m) => m.resolution.set(width * dpr, height * dpr));
  camera.aspect = width / height;
  camera.setViewOffset(width, height, -view.shift[0] * width, view.shift[1] * height, width, height);
  camera.updateProjectionMatrix();
  composer.render();
}

function mulberry32(seed) {
  return () => {
    seed |= 0;
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

window.addEventListener('resize', resize);
await document.fonts.ready;
resize();
window.__keyartReady = true;
