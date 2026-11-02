// A throwaway prototype of a 3D mode of RotaThree. The screen shows the cross
// as the 2D game does, and the game is played on that picture: each cell
// shows the nearest block behind it, lines of what is seen pop, and what is
// seen falls (rules.js). The third dimension shows when the hub is tipped
// over (↑/↓) and while V is held, and as a faint tunnel at the centre: the
// glasses in front of and behind the screen, whose sticks fly along the line
// of sight. Holding ↑/↓ shows how the hub would lie before it is tipped.
// Drawn the way the game draws its cross (src/render). Dev server only:
// /proto3d/.
//
// URL: ?centre=7&arm=8&colors=4&seed=1
import * as THREE from 'three';
import { LineSegments2 } from 'three/examples/jsm/lines/LineSegments2.js';
import { LineSegmentsGeometry } from 'three/examples/jsm/lines/LineSegmentsGeometry.js';
import { LineMaterial } from 'three/examples/jsm/lines/LineMaterial.js';
import '@fontsource/exo-2/400.css';
import '@fontsource/exo-2/700.css';
import '@fontsource/exo-2/900-italic.css';
import { Game, SIDES, dot, normalOf, pieceCells, sideOfNormal } from './rules.js';

const query = new URLSearchParams(location.search);
const num = (key, fallback) => (query.has(key) ? Number(query.get(key)) : fallback);

/** Side of the shared centre cube; odd, so that it has a middle layer. */
const CENTRE = num('centre', 7) | 1;
/** Length of each arm. */
const ARM = num('arm', 8);
const COLOR_COUNT = num('colors', 4);
const SEED = query.has('seed') ? Number(query.get('seed')) : null;

/** The classic set of the game and the tones of its bevel
 * (src/render/theme.ts `toneOf`). */
const PALETTE = ['#ff3d5e', '#3b82ff', '#ffc531', '#2fd985', '#a65cff'];
const channels = (hex) => {
  const n = parseInt(hex.slice(1), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
};
const lighter = (rgb) => rgb.map((c) => c + (255 - c) * 0.45);
const darker = (rgb) => rgb.map((c) => c * (1 - 0.35));
const TONES = PALETTE.map((hex) => {
  const colour = (rgb) => new THREE.Color().setRGB(...rgb.map((c) => c / 255), THREE.SRGBColorSpace);
  const rgb = channels(hex);
  return { hex, base: colour(rgb), light: colour(lighter(rgb)), dark: colour(darker(rgb)) };
});
const WHITE = new THREE.Color('#ffffff');
/** Accent of the active glass (THEME.accent). */
const ACCENT = new THREE.Color('#78cdff');
const TURN_SECONDS = 0.36;
/** How far the hub turns to be looked at while V is held. */
const PEEK = new THREE.Quaternion().setFromEuler(new THREE.Euler(0.45, -0.55, 0));
/** Depth is squashed this flat when the picture is the game: the nearest
 * block of every cell still wins, but nothing looks deeper than another. */
const FLAT = 0.02;

const N = CENTRE + 2 * ARM;
const HALF = N / 2;
const H = CENTRE / 2;
const REACH = H + ARM;

/** Settings: each has a key and a box in the settings panel, and is kept
 * between visits. */
const SETTINGS = [
  { id: 'depthSticks', key: 'KeyT', label: 'Показывать фигуры спереди и сзади, которыми не управляешь', initial: false },
  { id: 'depthFalls', key: 'KeyY', label: 'Передний и задний стаканы падают сами (медленно)', initial: false },
  { id: 'inactiveFalls', key: 'KeyI', label: 'Фигуры падают и в других стаканах', initial: true },
  { id: 'behind', key: 'KeyB', label: 'Метка: цвет блока за клеткой', initial: true },
  { id: 'lane', key: 'KeyG', label: 'Дорожка до места посадки', initial: true },
];
const STORE = 'rotathree-proto3d-settings';
const options = { help: true, paused: false, peek: false };
{
  let saved = {};
  try {
    saved = JSON.parse(localStorage.getItem(STORE) ?? '{}');
  } catch {
    // A private window or blocked storage: the defaults will do.
  }
  for (const s of SETTINGS) options[s.id] = typeof saved[s.id] === 'boolean' ? saved[s.id] : s.initial;
}
const saveSettings = () => {
  try {
    localStorage.setItem(STORE, JSON.stringify(Object.fromEntries(SETTINGS.map((s) => [s.id, options[s.id]]))));
  } catch {
    // Not kept, then.
  }
};

const makeGame = () => new Game({
  centre: CENTRE,
  arm: ARM,
  numberOfColors: COLOR_COUNT,
  seed: SEED,
  inactiveFalls: options.inactiveFalls,
  depthFalls: options.depthFalls,
});
let game = makeGame();

// ------------------------------------------------------------------ scene

const canvas = document.getElementById('scene');
// Transparent, over the game's own backdrop (index.html).
const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true, preserveDrawingBuffer: true });
const dpr = Math.min(window.devicePixelRatio, 2);
renderer.setPixelRatio(dpr);
renderer.setClearColor(0x000000, 0);

const scene = new THREE.Scene();
// Far away and narrow, so that the cross looks flat.
const DISTANCE = 4.2 * REACH;
const camera = new THREE.PerspectiveCamera(30, 1, 1, DISTANCE * 3);
camera.position.set(0, 0, DISTANCE);
camera.lookAt(0, 0, 0);

/** The hub's edges and numbers: turned as a whole; the data never turns. */
const hubGroup = new THREE.Group();
scene.add(hubGroup);
/** The cross of the 2D game, fixed to the screen: it fades while the hub
 * turns, as the grid of the 2D game does. */
const crossGroup = new THREE.Group();
scene.add(crossGroup);

/** Centre of a data cell in the hub's own frame. */
const local = (p, out = new THREE.Vector3()) => out.set(p[0] + 0.5 - HALF, p[1] + 0.5 - HALF, p[2] + 0.5 - HALF);

const lineMaterials = [];
/** Thin lines of one colour, a pixel or so wide. */
const makeLines = (positions, { color = WHITE, opacity = 1, width = 1, parent = hubGroup } = {}) => {
  const geometry = new LineSegmentsGeometry();
  geometry.setPositions(positions);
  const material = new LineMaterial({ color, opacity, linewidth: width * dpr, transparent: true, depthWrite: false });
  material.userData.opacity = opacity;
  lineMaterials.push(material);
  const mesh = new LineSegments2(geometry, material);
  parent.add(mesh);
  return mesh;
};

const makePane = (x, y, width, height, opacity, parent) => {
  const material = new THREE.MeshBasicMaterial({ color: WHITE, transparent: true, opacity, depthWrite: false });
  material.userData.opacity = opacity;
  const mesh = new THREE.Mesh(new THREE.PlaneGeometry(width, height), material);
  mesh.position.set(x, y, -0.5);
  parent.add(mesh);
  return mesh;
};

// --- The cross (src/render/renderer.ts drawField): a faint fill and grid for
// each arm and for the centre, outlines a little brighter, the glass on top
// in the accent. Behind the blocks.
const cross = (() => {
  const z = -0.5;
  const arms = [0, 1, 2, 3].map((quarter) => {
    // Drawn for the arm on top, then turned a quarter at a time.
    const group = new THREE.Group();
    group.rotation.z = (-quarter * Math.PI) / 2;
    crossGroup.add(group);
    makePane(0, H + ARM / 2, CENTRE, ARM, 0.022, group);
    const grid = [];
    for (let i = 1; i < CENTRE; i++) grid.push(-H + i, H, z, -H + i, REACH, z);
    for (let j = 1; j < ARM; j++) grid.push(-H, H + j, z, H, H + j, z);
    makeLines(grid, { opacity: 0.045, parent: group });
    const outline = [-H, H, z, -H, REACH, z, -H, REACH, z, H, REACH, z, H, REACH, z, H, H, z];
    return makeLines(outline, { opacity: 0.16, width: 1.5, parent: group });
  });
  makePane(0, 0, CENTRE, CENTRE, 0.05, crossGroup);
  const grid = [];
  for (let i = 1; i < CENTRE; i++) grid.push(-H + i, -H, z, -H + i, H, z, -H, -H + i, z, H, -H + i, z);
  makeLines(grid, { opacity: 0.07, parent: crossGroup });
  makeLines([-H, -H, z, H, -H, z, H, -H, z, H, H, z, H, H, z, -H, H, z, -H, H, z, -H, -H, z], { opacity: 0.22, width: 1.5, parent: crossGroup });
  // The glass on top: its outline in the accent.
  arms[0].material.color.copy(ACCENT);
  arms[0].material.userData.opacity = arms[0].material.opacity = 0.6;
  return crossGroup;
})();

// --- The hub itself, faintly: the edges of all six glasses and of the
// centre cube. Seen straight on, the glasses in front and behind are a short
// tunnel at the centre — the hint that there is more than the cross.
const armPoint = (side, t, a, b) => {
  const { axis, sign } = SIDES[side];
  const [k1, k2] = [0, 1, 2].filter((i) => i !== axis);
  const p = [0, 0, 0];
  p[axis] = sign * (H + t);
  p[k1] = a;
  p[k2] = b;
  return p;
};
const CORNERS = [[-H, -H], [H, -H], [H, H], [-H, H]];
const hubLines = SIDES.map((s) => {
  const p = [];
  CORNERS.forEach(([a, b], i) => {
    const [na, nb] = CORNERS[(i + 1) % 4];
    p.push(...armPoint(s.id, 0, a, b), ...armPoint(s.id, ARM, a, b));
    p.push(...armPoint(s.id, ARM, a, b), ...armPoint(s.id, ARM, na, nb));
  });
  return makeLines(p, { opacity: 0.1 });
});
{
  const p = [];
  for (const a of [-H, H]) for (const b of [-H, H]) p.push(-H, a, b, H, a, b, a, -H, b, a, H, b, a, b, -H, a, b, H);
  hubLines.push(makeLines(p, { opacity: 0.12 }));
}

/** The glasses' numbers, beside a corner of each rim. */
const labels = SIDES.map((s) => {
  const label = document.createElement('canvas');
  label.width = label.height = 128;
  const sprite = new THREE.Sprite(new THREE.SpriteMaterial({ map: new THREE.CanvasTexture(label), depthTest: false, transparent: true }));
  sprite.position.set(...armPoint(s.id, ARM - 0.2, H + 0.75, H + 0.75));
  sprite.scale.set(1.15, 1.15, 1);
  sprite.renderOrder = 20;
  hubGroup.add(sprite);
  return { sprite, canvas: label };
});
const drawLabels = () => labels.forEach(({ sprite, canvas: label }, side) => {
  const g = label.getContext('2d');
  g.clearRect(0, 0, 128, 128);
  g.font = '900 italic 88px "Exo 2", system-ui';
  g.textAlign = 'center';
  g.textBaseline = 'middle';
  g.fillStyle = '#eceff9';
  g.fillText(SIDES[side].label, 64, 68);
  sprite.material.map.needsUpdate = true;
});

// --- Blocks. Solid ones are drawn like the game's sprite: a bevel going
// from light at the top of the screen to dark at the bottom, around a flat
// face with a soft shine across its top. Placed in the scene by hand, so that
// depth can be squashed flat.
const MAX_CUBES = N * N * N + 64;

function cubeLayer(material, attributes, renderOrder) {
  const geometry = new THREE.BoxGeometry(1, 1, 1);
  const buffers = {};
  for (const [name, size] of Object.entries(attributes)) {
    buffers[name] = new THREE.InstancedBufferAttribute(new Float32Array(MAX_CUBES * size), size);
    buffers[name].setUsage(THREE.DynamicDrawUsage);
    geometry.setAttribute(name, buffers[name]);
  }
  const mesh = new THREE.InstancedMesh(geometry, material, MAX_CUBES);
  mesh.frustumCulled = false;
  mesh.renderOrder = renderOrder;
  mesh.count = 0;
  scene.add(mesh);
  return { mesh, buffers, items: [] };
}

const sharedUniforms = {
  screenUp: { value: new THREE.Vector3(0, 1, 0) },
  light: { value: new THREE.Vector3(0.2, 0.45, 1).normalize() },
};

const solid = cubeLayer(new THREE.ShaderMaterial({
  uniforms: sharedUniforms,
  vertexShader: /* glsl */ `
    uniform vec3 screenUp;
    attribute vec3 aBase;
    attribute vec3 aLight;
    attribute vec3 aDark;
    attribute vec2 aLook;
    varying vec3 vLocal;
    varying vec3 vNormal;
    varying float vUp;
    varying vec3 vBase;
    varying vec3 vLight;
    varying vec3 vDark;
    varying vec2 vLook;
    void main() {
      vLocal = position;
      vBase = aBase;
      vLight = aLight;
      vDark = aDark;
      vLook = aLook;
      mat4 model = modelMatrix * instanceMatrix;
      mat3 turn = mat3(model);
      vNormal = normalize(turn * normal);
      // How far up the screen this point is from the cube's centre.
      vUp = dot(turn * position, screenUp) / length(turn[0]);
      gl_Position = projectionMatrix * viewMatrix * model * vec4(position, 1.0);
    }`,
  fragmentShader: /* glsl */ `
    uniform vec3 light;
    varying vec3 vLocal;
    varying vec3 vNormal;
    varying float vUp;
    varying vec3 vBase;
    varying vec3 vLight;
    varying vec3 vDark;
    varying vec2 vLook; // brightness, white flash
    void main() {
      vec3 a = abs(vLocal);
      // The two coordinates across the face this point is on.
      vec2 uv = a.x >= a.y && a.x >= a.z ? a.yz : a.y >= a.z ? a.xz : a.xy;
      // The flat face: a rounded square set into the bevel.
      const float inset = 0.13;
      const float radius = 0.07;
      vec2 q = uv - vec2(0.5 - inset - radius);
      float sdf = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
      float aa = fwidth(sdf) + 1e-4;
      float face = 1.0 - smoothstep(-aa, aa, sdf);
      // 0 at the top of the block on screen, 1 at its bottom.
      float y = clamp(0.5 - vUp * 0.98, 0.0, 1.0);
      vec3 bevel = y < 0.3 ? mix(vLight, vBase, y / 0.3) : mix(vBase, vDark, (y - 0.3) / 0.7);
      float fy = clamp((y - inset) / (1.0 - 2.0 * inset), 0.0, 1.0);
      vec3 plain = mix(vBase, vec3(1.0), 0.3 * max(0.0, 1.0 - fy * 2.0));
      vec3 colour = mix(bevel, plain, face);
      colour *= (0.7 + 0.3 * max(dot(normalize(vNormal), light), 0.0)) * vLook.x;
      colour = mix(colour, vec3(1.0), vLook.y);
      gl_FragColor = vec4(colour, 1.0);
      #include <tonemapping_fragment>
      #include <colorspace_fragment>
    }`,
}), { aBase: 3, aLight: 3, aDark: 3, aLook: 2 }, 1);

/** Outlines and see-through cubes: the landing spot, the aiming lane, the
 * sticks in front and behind. Far to near. */
const clear = cubeLayer(new THREE.ShaderMaterial({
  transparent: true,
  depthWrite: false,
  vertexShader: /* glsl */ `
    attribute vec3 aColor;
    attribute vec3 aLook;
    varying vec3 vLocal;
    varying vec3 vColor;
    varying vec3 vLook;
    void main() {
      vLocal = position;
      vColor = aColor;
      vLook = aLook;
      gl_Position = projectionMatrix * viewMatrix * modelMatrix * instanceMatrix * vec4(position, 1.0);
    }`,
  fragmentShader: /* glsl */ `
    varying vec3 vLocal;
    varying vec3 vColor;
    varying vec3 vLook; // alpha, fill, edge
    void main() {
      vec3 a = abs(vLocal) * 2.0;
      // 1 on the face itself; the second largest is 1 on an edge.
      float d = 1.0 - max(min(a.x, a.y), min(max(a.x, a.y), a.z));
      float w = fwidth(d) + 1e-4;
      float edge = 1.0 - smoothstep(w * 0.8, w * 1.8, d);
      gl_FragColor = vec4(vColor, vLook.x * max(vLook.y, edge * vLook.z));
      #include <tonemapping_fragment>
      #include <colorspace_fragment>
    }`,
}), { aColor: 3, aLook: 3 }, 6);

/** `at` is in the hub's frame. `lift` moves a cube towards the eye (or away)
 * while the picture is flat: the sticks in front of and behind the screen
 * are drawn over and under it. `nudge` shifts it on the screen, for the
 * small marks in the corners of cells. */
function pushSolid(at, color, { brightness = 1, flash = 0, size = 0.91, lift = 0, nudge = null } = {}) {
  solid.items.push({ at: at.clone(), size: [size, size, size], lift, nudge, tone: TONES[color], brightness, flash });
}

function pushClear(at, color, alpha, fill, edge, { size = [0.91, 0.91, 0.91], lift = 0, nudge = null } = {}) {
  clear.items.push({ at: at.clone(), size, lift, nudge, color, alpha, fill, edge, depth: 0 });
}

/** A mark in a corner of a cell, over the picture: `x`, `y` say which. */
const corner = (x, y) => new THREE.Vector3(0.27 * x, 0.27 * y, 0.5);
const MARK = 0.3;
/** The mark of a square that would hide: a dark hole. */
const HOLE = new THREE.Color('#05050a');

const matrix = new THREE.Matrix4();
const scaleVector = new THREE.Vector3();
/** How much of the depth is shown: FLAT while playing, 1 mid-turn and while
 * V is held. */
let depthShown = FLAT;

/** Where a cube of the hub's frame is drawn in the scene. */
function place(item) {
  const at = item.at.applyQuaternion(hubGroup.quaternion);
  at.z = at.z * depthShown + item.lift * (1 - depthShown);
  if (item.nudge) at.add(item.nudge);
  return at;
}

function flushLayers() {
  solid.items.forEach((item, i) => {
    // A size in the hub's frame: turn it the way the hub is turned.
    scaleVector.set(...item.size);
    matrix.compose(place(item), hubGroup.quaternion, scaleVector);
    solid.mesh.setMatrixAt(i, matrix);
    const { base, light, dark } = item.tone;
    solid.buffers.aBase.setXYZ(i, base.r, base.g, base.b);
    solid.buffers.aLight.setXYZ(i, light.r, light.g, light.b);
    solid.buffers.aDark.setXYZ(i, dark.r, dark.g, dark.b);
    solid.buffers.aLook.setXY(i, item.brightness, item.flash);
  });
  for (const item of clear.items) {
    place(item);
    item.depth = item.at.distanceToSquared(camera.position);
  }
  clear.items.sort((a, b) => b.depth - a.depth);
  clear.items.forEach((item, i) => {
    scaleVector.set(...item.size);
    matrix.compose(item.at, hubGroup.quaternion, scaleVector);
    clear.mesh.setMatrixAt(i, matrix);
    clear.buffers.aColor.setXYZ(i, item.color.r, item.color.g, item.color.b);
    clear.buffers.aLook.setXYZ(i, item.alpha, item.fill, item.edge);
  });
  for (const layer of [solid, clear]) {
    layer.mesh.count = layer.items.length;
    layer.mesh.instanceMatrix.needsUpdate = true;
    for (const buffer of Object.values(layer.buffers)) buffer.needsUpdate = true;
    layer.items.length = 0;
  }
}

function resize() {
  const width = window.innerWidth;
  const height = window.innerHeight;
  renderer.setSize(width, height, false);
  lineMaterials.forEach((m) => m.resolution.set(width * dpr, height * dpr));
  camera.aspect = width / height;
  // The whole cross and its numbers fit, whichever side of the screen is short.
  const half = REACH + 1.4;
  const tan = half / (DISTANCE - H) / Math.min(1, camera.aspect);
  camera.fov = THREE.MathUtils.radToDeg(2 * Math.atan(tan));
  camera.updateProjectionMatrix();
}
window.addEventListener('resize', resize);

// ------------------------------------------------------------- the turns

/** Where the hub is turned to; the picture eases towards it. Always a whole
 * number of quarter turns, so data axes map onto scene axes. */
const targetQ = new THREE.Quaternion();
const turnFrom = new THREE.Quaternion();
const turned = new THREE.Quaternion();
const turn = { t: 1 };
/** 0 when the picture is the game, 1 while V is held. */
let peek = 0;
const SCENE_RIGHT = new THREE.Vector3(1, 0, 0);
const SCENE_UP = new THREE.Vector3(0, 1, 0);
const SCENE_TOWARD = new THREE.Vector3(0, 0, 1);

/** A scene direction in the data frame, as integers. */
const toData = (v) => {
  const w = v.clone().applyQuaternion(targetQ.clone().invert());
  return [Math.round(w.x), Math.round(w.y), Math.round(w.z)];
};
/** A data direction in the scene, once the turn under way is over. */
const toScene = (d) => new THREE.Vector3(...d).applyQuaternion(targetQ).round();

const topGlass = () => sideOfNormal(toData(SCENE_UP));

/** `targetQ` after a quarter turn about a scene axis, snapped so that the
 * rounding drift of many turns never builds up. */
function quarterTurned(axis, quarters) {
  const q = new THREE.Quaternion().setFromAxisAngle(axis, (quarters * Math.PI) / 2).multiply(targetQ);
  const m = new THREE.Matrix4().makeRotationFromQuaternion(q);
  m.elements.forEach((e, i) => { m.elements[i] = Math.round(e); });
  return q.setFromRotationMatrix(m);
}

/** A scene direction in the data frame of a turn `q`. */
const dataIn = (q, v) => {
  const w = v.clone().applyQuaternion(q.clone().invert());
  return [Math.round(w.x), Math.round(w.y), Math.round(w.z)];
};

/** Turns the hub a quarter turn about a scene axis: about the line of sight
 * as the 2D cross turns (the number keys of the side glasses), or about the
 * screen's horizontal (↑/↓), so that the glass behind or in front comes over
 * the top and the new picture settles and pops. The glass on top is steered. */
function turnHub(axis, quarters) {
  turnFrom.copy(turned);
  turn.t = 0;
  targetQ.copy(quarterTurned(axis, quarters));
  const tipped = axis !== SCENE_TOWARD;
  game.turn(topGlass(), toData(SCENE_TOWARD), { right: toData(SCENE_RIGHT), up: toData(SCENE_UP) }, tipped);
}

/** A tip of the hub looked at before it is made, while ↑/↓ is held: the
 * hub turns, and shows how it would settle and what would pop. Letting go
 * tips it; Esc puts it back. */
let preview = null;

function startPreview(code) {
  const quarters = code === 'ArrowUp' ? 1 : -1;
  preview = { code, quarters, q: quarterTurned(SCENE_RIGHT, quarters), version: -1, result: null };
  turnFrom.copy(turned);
  turn.t = 0;
  refreshPreview();
}

/** Works the preview out again when the board has changed under it. */
function refreshPreview() {
  if (!preview || preview.version === game.hub.version) return;
  preview.version = game.hub.version;
  const { q } = preview;
  preview.result = game.previewTurn(dataIn(q, SCENE_TOWARD), { right: dataIn(q, SCENE_RIGHT), up: dataIn(q, SCENE_UP) });
}

function commitPreview(code) {
  if (preview?.code !== code) return;
  const { quarters } = preview;
  preview = null;
  turnHub(SCENE_RIGHT, quarters);
}

function cancelPreview() {
  if (!preview) return;
  preview = null;
  turnFrom.copy(turned);
  turn.t = 0;
}

/** A number key: a glass around the cross is turned to the top, as in the
 * 2D game; the one in front or behind is steered where it is. */
function takeGlass(side) {
  const at = toScene(normalOf(side));
  if (at.z !== 0) game.control(side);
  else if (at.x === -1) turnHub(SCENE_TOWARD, -1);
  else if (at.x === 1) turnHub(SCENE_TOWARD, 1);
  else if (at.y === -1) turnHub(SCENE_TOWARD, 2);
  else game.control(side);
}

// ------------------------------------------------------------------ input

/** How often each key was pressed, for the notes on how many are needed. */
const keyCount = {};

function toggle(id) {
  options[id] = !options[id];
  if (id === 'inactiveFalls' || id === 'depthFalls') game.config[id] = options[id];
  saveSettings();
  renderSettings();
}

function press(code, { repeat = false } = {}) {
  const move = (v) => game.move(toData(v));
  const turnStick = (clockwise) => game.rotate(toData(clockwise ? SCENE_TOWARD.clone().negate() : SCENE_TOWARD));
  const setting = SETTINGS.find((s) => s.key === code);
  if (code === 'KeyA') move(SCENE_RIGHT.clone().negate());
  else if (code === 'KeyD') move(SCENE_RIGHT);
  else if (code === 'KeyW') game.screenUp();
  else if (code === 'KeyS') game.screenDown();
  else if (code === 'KeyQ') turnStick(false);
  else if (code === 'KeyE') turnStick(true);
  else if (code === 'Space') {
    if (!repeat) game.dropActive();
  } else if (code === 'ArrowUp' || code === 'ArrowDown') {
    if (!repeat && !preview) startPreview(code);
  } else if (code === 'Escape') cancelPreview();
  else if (/^Digit[1-6]$/.test(code)) {
    if (!repeat) takeGlass(SIDES.findIndex((s) => s.label === code.slice(5)));
  } else if (code === 'KeyV') options.peek = true;
  else if (setting) toggle(setting.id);
  else if (code === 'KeyF') game.fillForTesting();
  else if (code === 'KeyP') options.paused = !options.paused;
  else if (code === 'KeyH') options.help = !options.help;
  else if (code === 'KeyN') restart();
  else return false;
  if (!repeat) keyCount[code] = (keyCount[code] ?? 0) + 1;
  renderKeys();
  return true;
}

function release(code) {
  if (code === 'ArrowUp' || code === 'ArrowDown') {
    commitPreview(code);
    return true;
  }
  if (code !== 'KeyV') return false;
  options.peek = false;
  return true;
}

window.addEventListener('keydown', (event) => {
  if (event.metaKey || event.ctrlKey || event.altKey) return;
  if (press(event.code, { repeat: event.repeat })) event.preventDefault();
});
window.addEventListener('keyup', (event) => {
  if (release(event.code)) event.preventDefault();
});
window.addEventListener('blur', () => {
  release('KeyV');
  cancelPreview();
});

function restart() {
  preview = null;
  game = makeGame();
  targetQ.identity();
  turned.identity();
  turn.t = 1;
  pieceViews.clear();
  flashes.clear();
  document.getElementById('banner').hidden = true;
}

// ------------------------------------------------------------------ frame

/** Where each falling stick is drawn: it eases into its cell. */
const pieceViews = new Map();
/** Cells that have just landed flash white for a moment. */
const flashes = new Map();
let clock = 0;

const ease = (t) => (t < 0.5 ? 4 * t * t * t : 1 - (-2 * t + 2) ** 3 / 2);

function consumeEvents() {
  for (const event of game.events) {
    if (event.type === 'landed') {
      for (const { p } of event.cells) flashes.set(game.hub.index(p), clock);
    } else if (event.type === 'gameEnded') {
      document.getElementById('banner-text').textContent =
        `Стакан ${SIDES[event.side].label} заполнен до края. Очки: ${game.score}.`;
      document.getElementById('banner').hidden = false;
    }
  }
  game.events.length = 0;
}

/** The picture is flat enough for marks in the corners of cells. */
const flat = () => depthShown < FLAT + 0.01;

/** In a corner of every cell that hides another block, a small square of
 * that block's colour: what a pop there would show. Worked out once per
 * board and view. */
const behindCache = { key: '', marks: [] };
function pushBehindMarks(view, key) {
  if (!options.behind || !flat()) return;
  if (behindCache.key !== key) {
    behindCache.key = key;
    behindCache.marks = [];
    for (let sx = -view.middle; sx <= view.middle; sx++) {
      for (let sy = -view.middle; sy <= view.middle; sy++) {
        const stack = view.stackAt(sx, sy);
        if (stack.length > 1) behindCache.marks.push({ at: local(stack[0]), color: view.hub.at(stack[1]) });
      }
    }
  }
  for (const { at, color } of behindCache.marks) pushSolid(at, color, { size: MARK, nudge: corner(1, -1) });
}

/** While ↑/↓ is held and the hub has turned: the board as it would settle,
 * what would pop first blinking. No sticks. */
function buildPreview() {
  const { view, match } = preview.result;
  const blink = 0.2 + 0.25 * (0.5 + 0.5 * Math.sin(performance.now() / 110));
  view.hub.forEachBlock((p, color, index) => pushSolid(local(p), color, { flash: match.cells.has(index) ? blink : 0 }));
  pushBehindMarks(view, `preview:${preview.code}:${preview.version}`);
  flushLayers();
}

function buildBlocks(dt) {
  if (preview?.result && turn.t >= 1) {
    buildPreview();
    return;
  }
  const hub = game.hub;
  const phase = game.phase;
  const progress = game.phaseDuration > 0 ? Math.min(1, game.phaseElapsed / game.phaseDuration) : 1;
  const matched = game.activeMatch?.cells;
  const falling = new Set();
  if (phase === 'settling') for (const move of game.moves) falling.add(hub.index(move.to));

  // Every block, solid. While the picture is flat the nearest one of each
  // cell hides the others; mid-turn and while V is held all of them show.
  hub.forEachBlock((p, color, index) => {
    if (falling.has(index)) return;
    let flash = 0;
    let size = 0.91;
    if (matched?.has(index)) {
      if (phase === 'matching') flash = 0.25 + 0.4 * Math.sin(progress * Math.PI);
      if (phase === 'clearing') {
        flash = 0.6;
        size = 0.91 * (1 - progress);
      }
    }
    const landed = flashes.get(index);
    if (landed !== undefined) {
      const age = clock - landed;
      if (age > 0.25) flashes.delete(index);
      else flash = Math.max(flash, 0.45 * (1 - age / 0.25));
    }
    if (size > 0.02) pushSolid(local(p), color, { flash, size });
  });
  if (phase === 'settling') {
    const t = Math.min(1, game.phaseElapsed / Math.max(0.01, game.phaseDuration - game.config.fallBounceSeconds));
    const to = new THREE.Vector3();
    for (const move of game.moves) pushSolid(local(move.from).lerp(local(move.to, to), t * t), move.color);
  }

  // Falling sticks ease into their cells. Those of the glasses in front and
  // behind fly along the line of sight: drawn as outlines over the picture
  // (in front) or under it (behind), and only the steered one unless the
  // setting asks for all.
  const k = 1 - Math.exp(-dt * 24);
  for (const [side, view] of pieceViews) if (game.pieces.get(side) !== view.piece) pieceViews.delete(side);
  const sticks = [...game.pieces.values()].map((piece) => {
    let view = pieceViews.get(piece.side);
    const goal = local(piece.pivot);
    if (!view) {
      view = { piece, at: goal.clone() };
      pieceViews.set(piece.side, view);
    }
    view.at.lerp(goal, k);
    return { piece, at: view.at };
  });
  if (phase === 'dropping' && game.drop) {
    const { piece, from } = game.drop;
    sticks.push({ piece, at: local(from).lerp(local(piece.pivot), progress * progress) });
  }
  for (const { piece, at } of sticks) {
    const dir = new THREE.Vector3(...piece.dir);
    const steered = piece.side === game.active;
    if (game.inPlane(piece.side)) {
      piece.colors.forEach((color, i) => pushSolid(at.clone().addScaledVector(dir, i - 1), color));
      continue;
    }
    if (!steered && !options.depthSticks) continue;
    const lift = toScene(normalOf(piece.side)).z * 0.6;
    // The steered one says, square by square, how it will land: filled and
    // with a mark of its colour if it will be seen, an empty outline and a
    // dark hole if it will hide behind what is there.
    const landing = steered ? game.landing(piece.side) : null;
    piece.colors.forEach((color, i) => {
      const cell = at.clone().addScaledVector(dir, i - 1);
      if (!steered) {
        pushClear(cell, TONES[color].base, 0.8, 0.06, 0.5, { lift });
        return;
      }
      const seen = landing?.seen[i] ?? true;
      pushClear(cell, TONES[color].light, 1, seen ? 0.42 : 0, 1, { lift });
      if (!flat()) return;
      if (seen) pushSolid(cell, color, { size: MARK, lift: 0.6, nudge: corner(-1, 1) });
      else pushClear(cell, HOLE, 1, 0.8, 1, { size: [MARK, MARK, MARK], lift: 0.6, nudge: corner(-1, 1) });
    });
  }

  // Where the stick on top will land, and the lane down to it. A stick in
  // front or behind lands in the cells it is over; the panel says how deep.
  const piece = game.activePiece;
  if (piece && game.inPlane(piece.side)) {
    const ghost = game.ghost();
    const landed = ghost.every(({ p }, i) => p.every((v, j) => v === pieceCells(piece)[i].p[j]));
    if (!landed) {
      for (const { p, color } of ghost) pushClear(local(p), TONES[color].light, 1, 0.16, 1);
      if (options.lane) pushLanes(piece, ghost);
    }
  }
  pushBehindMarks(game, `game:${hub.version}:${targetQ.toArray().join()}`);
  flushLayers();
}

/** A faint column under each lane of the stick, down to the landing spot —
 * the game's aiming lane. */
function pushLanes(piece, ghost) {
  const n = normalOf(piece.side);
  const { axis } = SIDES[piece.side];
  const lanes = new Map();
  pieceCells(piece).forEach(({ p }, i) => {
    const key = p.filter((_, j) => j !== axis).join();
    const low = lanes.get(key);
    const height = dot(p, n);
    if (!low || height < low.height) lanes.set(key, { p, height, ghost: ghost[i].p });
  });
  for (const lane of lanes.values()) {
    const top = local(lane.p).addScaledVector(new THREE.Vector3(...n), -0.5);
    const bottom = local(lane.ghost).addScaledVector(new THREE.Vector3(...n), 0.5);
    const length = top.distanceTo(bottom);
    if (length < 0.05) continue;
    const size = [0.91, 0.91, 0.91];
    size[axis] = length;
    pushClear(top.add(bottom).multiplyScalar(0.5), WHITE, 1, 0.07, 0, { size });
  }
}

// ------------------------------------------------------------------- HUD

const $ = (id) => document.getElementById(id);
/** Where each glass is on the screen, by where it points. */
const PLACES = { '0,1,0': '▲ сверху', '0,-1,0': '▼ снизу', '-1,0,0': '◀ слева', '1,0,0': '▶ справа', '0,0,1': '⊙ спереди', '0,0,-1': '⊗ сзади' };
const glassRows = SIDES.map((s) => {
  const row = document.createElement('div');
  row.className = 'glass';
  row.innerHTML = `<span class="num">${s.label}</span><span class="key"></span><span class="bar"><i></i></span><span class="pct"></span>`;
  return row;
});
[...glassRows].sort((a, b) => a.firstChild.textContent - b.firstChild.textContent).forEach((row) => $('glasses').append(row));
let hudKey = '';
let nextKey = '';

function renderHud() {
  $('score').textContent = game.score.toLocaleString('ru-RU');
  $('combo').textContent = game.combo > 1 ? `×${game.combo}` : game.bestCombo > 1 ? `лучшее ×${game.bestCombo}` : '—';
  $('placed').textContent = game.placed;
  const where = PLACES[toScene(normalOf(game.active)).toArray().join()] ?? '';
  let depth = '';
  if (game.activePiece && !game.inPlane(game.active)) {
    const landing = game.landing();
    if (landing) {
      const layer = landing.layer > 0 ? `+${landing.layer}` : landing.layer;
      const of = landing.seen.length;
      const seen = landing.count === of ? 'будет видна' : landing.count === 0 ? 'спрячется за блоками' : `видно ${landing.count} из ${of}`;
      depth = ` · сядет в слой ${layer}, ${seen}`;
    }
  }
  let line = `стакан ${SIDES[game.active].label} ${where.slice(2)}${depth}`;
  if (preview?.result) {
    const { popped, rounds } = preview.result;
    const pops = popped === 0 ? 'ничего не лопнет' : `лопнет ${popped}${rounds > 1 ? `, каскад ×${rounds}` : ''}`;
    line = `опрокинуть: отпусти ${preview.code === 'ArrowUp' ? '↑' : '↓'}, Esc — отмена · ${pops}`;
  }
  $('phase').textContent = `${options.paused ? 'пауза · ' : ''}${line}`;
  const next = game.nextColors.join();
  if (next !== nextKey) {
    nextKey = next;
    const css = (rgb) => `rgb(${rgb.map(Math.round).join(' ')})`;
    $('next').innerHTML = game.nextColors.map((c) => {
      const rgb = channels(TONES[c].hex);
      return `<i style="--base:${TONES[c].hex};--light:${css(lighter(rgb))};--dark:${css(darker(rgb))}"></i>`;
    }).join('');
  }
  const key = `${game.hub.version}:${game.active}:${targetQ.toArray().join()}`;
  if (key === hudKey) return;
  hudKey = key;
  const depthOfGlass = game.hub.depth();
  SIDES.forEach((s, i) => {
    const row = glassRows[i];
    const room = game.headroom(s.id);
    const place = PLACES[toScene(normalOf(s.id)).toArray().join()] ?? '?';
    row.classList.toggle('active', s.id === game.active);
    row.classList.toggle('crowded', room <= 2);
    row.querySelector('.key').textContent = place.slice(0, 1);
    row.querySelector('.bar i').style.width = `${Math.round(((depthOfGlass - room) / depthOfGlass) * 100)}%`;
    row.querySelector('.pct').textContent = `${room}`;
    row.title = `${place.slice(2)} · свободных рядов у края: ${room}`;
  });
}

function renderKeys() {
  $('keys').hidden = !options.help;
  $('keys').innerHTML = [
    '<b>A D</b> — влево, вправо',
    '<b>W</b> — повернуть (передний/задний — вверх)',
    '<b>S</b> — вниз на клетку · <b>Пробел</b> — сбросить',
    '<b>Q E</b> — повернуть против / по часовой',
    '<b>1–6</b> — взять стакан: боковой повернуть наверх, передний/задний вести на месте',
    '<b>↑ ↓</b> (держать) — показать, как ляжет хаб, если задний / передний стакан опрокинуть наверх; отпустить — опрокинуть; <b>Esc</b> — отмена',
    '<b>V</b> (держать) — заглянуть в объём',
    '<b>F</b> — набросать блоков · <b>P</b> — пауза',
    '<b>N</b> — заново · <b>H</b> — спрятать подсказку',
  ].map((line) => `<div>${line}</div>`).join('');
}

/** The settings panel: a box per setting, its key beside it. */
function renderSettings() {
  $('settings-list').innerHTML = SETTINGS.map((s) => `
    <label><input type="checkbox" data-id="${s.id}" ${options[s.id] ? 'checked' : ''} />
    <span>${s.label}</span><kbd>${s.key.slice(3)}</kbd></label>`).join('');
}
$('settings-list').addEventListener('change', (event) => {
  const id = event.target.dataset?.id;
  if (id) toggle(id);
  event.target.blur();
});

// ------------------------------------------------------------------ loop

let last = performance.now();
function frame(now) {
  const dt = Math.min(0.1, (now - last) / 1000);
  last = now;
  if (!options.paused) {
    clock += dt;
    game.update(dt);
  }
  consumeEvents();
  // A pause stops the turn too, so that it can be looked at half-way.
  if (turn.t < 1 && !options.paused) turn.t = Math.min(1, turn.t + dt / TURN_SECONDS);
  refreshPreview();
  const goal = preview ? preview.q : targetQ;
  if (turn.t < 1) turned.slerpQuaternions(turnFrom, goal, ease(turn.t));
  else turned.copy(goal);
  peek += ((options.peek ? 1 : 0) - peek) * (1 - Math.exp(-dt * 10));
  hubGroup.quaternion.slerpQuaternions(new THREE.Quaternion(), PEEK, ease(peek)).multiply(turned);
  // Depth shows mid-turn and while peeking; the cross of the screen fades
  // meanwhile, and the edges of the hub stand out.
  const opened = Math.max(turn.t < 1 ? Math.sin(Math.PI * turn.t) : 0, peek);
  depthShown = FLAT + (1 - FLAT) * opened;
  const shown = (1 - opened) ** 2;
  cross.traverse((object) => {
    if (object.material) object.material.opacity = object.material.userData.opacity * shown;
  });
  hubLines.forEach((line) => { line.material.opacity = 0.1 + 0.25 * opened; });
  labels.forEach(({ sprite }, side) => {
    sprite.material.opacity = side === game.active ? 0.95 : 0.4;
  });
  buildBlocks(dt);
  renderHud();
  renderer.render(scene, camera);
  requestAnimationFrame(frame);
}

resize();
renderKeys();
renderSettings();
await document.fonts.ready;
drawLabels();
requestAnimationFrame(frame);

/** For scripted play-tests (shots.mjs) and the console. */
window.__proto3d = {
  get game() { return game; },
  press,
  release,
  keyCount,
  options,
  /** A data direction as the screen shows it once the turn is over:
   * +x right, +y up, +z towards the eye. */
  toScene: (d) => toScene(d).toArray(),
  get turning() { return turn.t < 1; },
  ready: true,
};
