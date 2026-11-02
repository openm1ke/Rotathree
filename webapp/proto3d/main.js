// A throwaway prototype of a 3D RotaThree, to find out by hand whether it is
// playable: six glasses around a small cube of a centre. It is drawn the way
// the game draws its cross (src/render): faint glass with thin lines, solid
// blocks with a bevel lit from the top of the screen, the landing spot as an
// outline in the stick's colours. The eye stands above the rim of the active
// glass and looks down into it about 30° off its axis, so aiming is a 2D grid
// and depth is the direction of the fall. Dev server only: /proto3d/.
//
// URL: ?centre=4&arm=6&colors=4&seed=1&tilt=30
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

/** Side of the shared centre cube; every arm has this cross-section. */
const CENTRE = num('centre', 4);
/** Length of each arm. */
const ARM = num('arm', 6);
const COLOR_COUNT = num('colors', 4);
const SEED = query.has('seed') ? Number(query.get('seed')) : null;

/** The classic set of the game and the tones of its bevel
 * (src/render/theme.ts `toneOf`). */
const PALETTE = ['#ff3d5e', '#3b82ff', '#ffc531', '#2fd985', '#a65cff'];
const TONES = PALETTE.map((hex) => {
  const n = parseInt(hex.slice(1), 16);
  const rgb = [(n >> 16) & 255, (n >> 8) & 255, n & 255];
  const colour = (channels) => new THREE.Color().setRGB(...channels.map((c) => c / 255), THREE.SRGBColorSpace);
  return {
    hex,
    base: colour(rgb),
    light: colour(rgb.map((c) => c + (255 - c) * 0.45)),
    dark: colour(rgb.map((c) => c * (1 - 0.35))),
  };
});
const WHITE = new THREE.Color('#ffffff');
/** Accent of the active glass (THEME.accent). */
const ACCENT = new THREE.Color('#78cdff');
const TURN_SECONDS = 0.34;
/** Degrees between the eye and the axis of the active glass; V cycles. */
const TILTS = [30, 45, 60, 0];
const XRAY = ['выкл', 'оболочка центра', 'срез у тени'];

const N = CENTRE + 2 * ARM;
const HALF = N / 2;
const H = CENTRE / 2;

const options = {
  xray: 0,
  inactiveFalls: false,
  rings: true,
  lane: true,
  othersClear: true,
  tilt: Math.max(0, TILTS.indexOf(num('tilt', 30))),
  help: true,
  paused: false,
};

const makeGame = () => new Game({
  centre: CENTRE,
  arm: ARM,
  numberOfColors: COLOR_COUNT,
  seed: SEED,
  inactiveFalls: options.inactiveFalls,
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
const camera = new THREE.PerspectiveCamera(55, 1, 0.3, 200);
// Screen-up is the far side of the hub for every tilt, straight down included.
camera.up.set(0, 0, -1);

/** Turned as a whole; the data never turns. */
const hubGroup = new THREE.Group();
scene.add(hubGroup);

/** Centre of a data cell in the hub's own frame. */
const local = (p, out = new THREE.Vector3()) => out.set(p[0] + 0.5 - HALF, p[1] + 0.5 - HALF, p[2] + 0.5 - HALF);

const lineMaterials = [];
/** Thin lines of one colour, a pixel or so wide. */
const makeLines = (positions, { color = WHITE, opacity = 1, width = 1, parent = hubGroup } = {}) => {
  const geometry = new LineSegmentsGeometry();
  geometry.setPositions(positions);
  const material = new LineMaterial({ color, opacity, linewidth: width * dpr, transparent: true, depthWrite: false });
  lineMaterials.push(material);
  const mesh = new LineSegments2(geometry, material);
  parent.add(mesh);
  return mesh;
};

/** A faint pane, like the fill of an arm in the game. */
const makePane = (width, height, opacity) => {
  const mesh = new THREE.Mesh(
    new THREE.PlaneGeometry(width, height),
    new THREE.MeshBasicMaterial({ color: WHITE, transparent: true, opacity, side: THREE.DoubleSide, depthWrite: false }),
  );
  hubGroup.add(mesh);
  return mesh;
};

/** A point of the arm of `side`: `t` cells out from the centre's face, at
 * (a, b) across it, both in −H..H. */
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

/** Per glass: its outline, the cells on its walls, its walls, the grid of
 * its floor and its number. */
const glasses = SIDES.map((s) => {
  const outline = [];
  const cells = [];
  CORNERS.forEach(([a, b], i) => {
    const [na, nb] = CORNERS[(i + 1) % 4];
    outline.push(...armPoint(s.id, 0, a, b), ...armPoint(s.id, ARM, a, b));
    outline.push(...armPoint(s.id, ARM, a, b), ...armPoint(s.id, ARM, na, nb));
    for (let t = 1; t < ARM; t++) cells.push(...armPoint(s.id, t, a, b), ...armPoint(s.id, t, na, nb));
  });
  for (let j = 1; j < CENTRE; j++) {
    const v = -H + j;
    for (const w of [-H, H]) {
      cells.push(...armPoint(s.id, 0, v, w), ...armPoint(s.id, ARM, v, w));
      cells.push(...armPoint(s.id, 0, w, v), ...armPoint(s.id, ARM, w, v));
    }
  }

  const walls = CORNERS.map(([a, b], i) => {
    const [na, nb] = CORNERS[(i + 1) % 4];
    const pane = makePane(CENTRE, ARM, 0.022);
    // Centre of the wall, and its two directions: across, and along the arm.
    const centre = new THREE.Vector3(...armPoint(s.id, ARM / 2, (a + na) / 2, (b + nb) / 2));
    const across = new THREE.Vector3(...armPoint(s.id, 0, na, nb)).sub(new THREE.Vector3(...armPoint(s.id, 0, a, b))).normalize();
    const along = new THREE.Vector3(...normalOf(s.id));
    pane.position.copy(centre);
    pane.quaternion.setFromRotationMatrix(new THREE.Matrix4().makeBasis(across, along, across.clone().cross(along)));
    return pane;
  });

  // The floor of this glass is the far face of the centre.
  const floor = [];
  const at = (a, b) => armPoint(s.id, -CENTRE, a, b);
  for (let j = 0; j <= CENTRE; j++) {
    const v = -H + j;
    floor.push(...at(v, -H), ...at(v, H), ...at(-H, v), ...at(H, v));
  }

  const label = document.createElement('canvas');
  label.width = label.height = 128;
  const sprite = new THREE.Sprite(new THREE.SpriteMaterial({ map: new THREE.CanvasTexture(label), depthWrite: false, transparent: true }));
  // Beside a corner of the rim, so that from straight above it does not
  // stand over the glass.
  sprite.position.set(...armPoint(s.id, ARM + 0.4, -H - 0.8, -H - 0.8));
  sprite.scale.set(1.1, 1.1, 1);
  sprite.renderOrder = 20;
  hubGroup.add(sprite);

  return {
    outline: makeLines(outline, { width: 1.5 }),
    cells: makeLines(cells),
    walls,
    floor: makeLines(floor, { color: ACCENT, opacity: 0.32, width: 1.2 }),
    sprite,
    label,
  };
});

const drawLabels = () => glasses.forEach((glass, side) => {
  const g = glass.label.getContext('2d');
  g.clearRect(0, 0, 128, 128);
  g.font = '900 italic 88px "Exo 2", system-ui';
  g.textAlign = 'center';
  g.textBaseline = 'middle';
  g.fillStyle = '#eceff9';
  g.fillText(SIDES[side].label, 64, 68);
  glass.sprite.material.map.needsUpdate = true;
});

// The centre: a faint box, its outline and the cells on its faces.
{
  const box = new THREE.Mesh(
    new THREE.BoxGeometry(CENTRE, CENTRE, CENTRE),
    new THREE.MeshBasicMaterial({ color: WHITE, transparent: true, opacity: 0.03, side: THREE.DoubleSide, depthWrite: false }),
  );
  hubGroup.add(box);
  const outline = [];
  for (const a of [-H, H]) for (const b of [-H, H]) outline.push(-H, a, b, H, a, b, a, -H, b, a, H, b, a, b, -H, a, b, H);
  makeLines(outline, { opacity: 0.3, width: 1.5 });
  const grid = [];
  for (let axis = 0; axis < 3; axis++) {
    for (const face of [-H, H]) {
      for (let j = 1; j < CENTRE; j++) {
        const t = -H + j;
        for (const [from, to] of [[[t, -H], [t, H]], [[-H, t], [H, t]]]) {
          const a = [0, 0, 0];
          const b = [0, 0, 0];
          a[axis] = b[axis] = face;
          [a[(axis + 1) % 3], a[(axis + 2) % 3]] = from;
          [b[(axis + 1) % 3], b[(axis + 2) % 3]] = to;
          grid.push(...a, ...b);
        }
      }
    }
  }
  makeLines(grid, { opacity: 0.08 });
}

/** A square around the active glass at a given depth: under the stick, and
 * under where it will land. One per axis, moved along it. */
const makeRing = (color, opacity) => [0, 1, 2].map((axis) => {
  const p = [];
  CORNERS.forEach(([a, b], i) => {
    const [na, nb] = CORNERS[(i + 1) % 4];
    const at = (x, y) => {
      const v = [0, 0, 0];
      v[(axis + 1) % 3] = x;
      v[(axis + 2) % 3] = y;
      return v;
    };
    p.push(...at(a, b), ...at(na, nb));
  });
  const ring = makeLines(p, { color, opacity, width: 1.5 });
  ring.visible = false;
  return ring;
});
const pieceRing = makeRing(WHITE, 0.4);
const ghostRing = makeRing(ACCENT, 0.75);

// --- Blocks. Solid ones are drawn like the game's sprite: a bevel going
// from light at the top of the screen to dark at the bottom, around a flat
// face with a soft shine across its top; faces turned from the light are a
// little darker so the cube reads as one.
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
  hubGroup.add(mesh);
  return { mesh, buffers, items: [] };
}

const sharedUniforms = {
  screenUp: { value: new THREE.Vector3(0, 0, -1) },
  light: { value: new THREE.Vector3(0.25, 1, 0.4).normalize() },
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
      float y = clamp(0.5 - vUp * 0.62, 0.0, 1.0);
      vec3 bevel = y < 0.3 ? mix(vLight, vBase, y / 0.3) : mix(vBase, vDark, (y - 0.3) / 0.7);
      float fy = clamp((y - inset) / (1.0 - 2.0 * inset), 0.0, 1.0);
      vec3 plain = mix(vBase, vec3(1.0), 0.3 * max(0.0, 1.0 - fy * 2.0));
      vec3 colour = mix(bevel, plain, face);
      colour *= (0.68 + 0.32 * max(dot(normalize(vNormal), light), 0.0)) * vLook.x;
      colour = mix(colour, vec3(1.0), vLook.y);
      gl_FragColor = vec4(colour, 1.0);
      #include <tonemapping_fragment>
      #include <colorspace_fragment>
    }`,
}), { aBase: 3, aLight: 3, aDark: 3, aLook: 2 }, 1);

/** Outlines and see-through cubes: the landing spot, x-rayed blocks, the
 * lane down to the landing spot. Drawn far to near over the solid ones. */
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

function pushSolid(at, color, { brightness = 1, flash = 0, size = 0.92 } = {}) {
  solid.items.push({ x: at.x, y: at.y, z: at.z, sx: size, sy: size, sz: size, tone: TONES[color], brightness, flash });
}

function pushClear(at, color, alpha, fill, edge, size = [0.92, 0.92, 0.92]) {
  clear.items.push({ x: at.x, y: at.y, z: at.z, sx: size[0], sy: size[1], sz: size[2], color, alpha, fill, edge, depth: 0 });
}

const matrix = new THREE.Matrix4();
const tmp = new THREE.Vector3();

function flushLayers() {
  solid.items.forEach((item, i) => {
    matrix.makeScale(item.sx, item.sy, item.sz).setPosition(item.x, item.y, item.z);
    solid.mesh.setMatrixAt(i, matrix);
    const { base, light, dark } = item.tone;
    solid.buffers.aBase.setXYZ(i, base.r, base.g, base.b);
    solid.buffers.aLight.setXYZ(i, light.r, light.g, light.b);
    solid.buffers.aDark.setXYZ(i, dark.r, dark.g, dark.b);
    solid.buffers.aLook.setXY(i, item.brightness, item.flash);
  });
  // Far to near, so the see-through faces blend in order.
  hubGroup.updateMatrixWorld();
  for (const item of clear.items) {
    tmp.set(item.x, item.y, item.z).applyMatrix4(hubGroup.matrixWorld);
    item.depth = tmp.distanceToSquared(camera.position);
  }
  clear.items.sort((a, b) => b.depth - a.depth);
  clear.items.forEach((item, i) => {
    matrix.makeScale(item.sx, item.sy, item.sz).setPosition(item.x, item.y, item.z);
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
  camera.updateProjectionMatrix();
}
window.addEventListener('resize', resize);

// ------------------------------------------------------------- the turns

/** Where the hub is turned to; the picture eases towards it. Always a whole
 * number of quarter turns, so data axes map onto scene axes. */
const targetQ = new THREE.Quaternion();
const turn = { from: new THREE.Quaternion(), t: 1 };
const SCENE_RIGHT = new THREE.Vector3(1, 0, 0);
const SCENE_FAR = new THREE.Vector3(0, 0, -1);
const SCENE_UP = new THREE.Vector3(0, 1, 0);

/** A scene direction in the data frame, as integers. */
const toData = (v) => {
  const w = v.clone().applyQuaternion(targetQ.clone().invert());
  return [Math.round(w.x), Math.round(w.y), Math.round(w.z)];
};
/** A data direction in the scene, once the turn under way is over. */
const toScene = (d) => new THREE.Vector3(...d).applyQuaternion(targetQ).round();

const viewActive = () => sideOfNormal(toData(SCENE_UP));

function syncView() {
  game.viewFrame = { right: toData(SCENE_RIGHT), far: toData(SCENE_FAR) };
  const active = viewActive();
  glasses.forEach((glass, side) => {
    const on = side === active;
    glass.outline.material.color.copy(on ? ACCENT : WHITE);
    glass.outline.material.opacity = on ? 0.75 : 0.2;
    glass.cells.material.opacity = on ? 0.1 : 0.05;
    glass.walls.forEach((wall) => { wall.material.opacity = on ? 0.035 : 0.022; });
    glass.floor.visible = on;
    glass.sprite.material.opacity = on ? 0.8 : 0.35;
  });
}

/** Turns the hub a quarter turn about a scene axis, so that a neighbouring
 * glass comes up to the top. */
function turnHub(axis, quarter) {
  turn.from.copy(hubGroup.quaternion);
  turn.t = 0;
  targetQ.premultiply(new THREE.Quaternion().setFromAxisAngle(axis, (quarter * Math.PI) / 2));
  // Snap away the rounding drift of many turns.
  const m = new THREE.Matrix4().makeRotationFromQuaternion(targetQ);
  m.elements.forEach((e, i) => { m.elements[i] = Math.round(e); });
  targetQ.setFromRotationMatrix(m);
  game.switchTo(viewActive());
  syncView();
}

// ------------------------------------------------------------------ input

const KEYS = {
  KeyW: () => game.move(toData(SCENE_FAR)),
  KeyS: () => game.move(toData(SCENE_FAR.clone().negate())),
  KeyA: () => game.move(toData(SCENE_RIGHT.clone().negate())),
  KeyD: () => game.move(toData(SCENE_RIGHT)),
};
// Quarter turns of the stick about a scene axis; Shift turns the other way.
// Q rolls (left–right ↔ standing), E pitches (far–near ↔ standing), R spins
// it flat (left–right ↔ far–near).
const ROTATIONS = { KeyQ: SCENE_FAR, KeyE: SCENE_RIGHT, KeyR: SCENE_UP };
const TURNS = {
  ArrowLeft: [new THREE.Vector3(0, 0, 1), -1],
  ArrowRight: [new THREE.Vector3(0, 0, 1), 1],
  ArrowUp: [new THREE.Vector3(1, 0, 0), 1],
  ArrowDown: [new THREE.Vector3(1, 0, 0), -1],
};
/** How often each key was pressed, for the notes on how many are needed. */
const keyCount = {};

function press(code, { shift = false, repeat = false } = {}) {
  if (KEYS[code]) KEYS[code]();
  else if (ROTATIONS[code]) {
    const axis = toData(ROTATIONS[code]);
    game.rotate(shift ? axis.map((v) => -v) : axis);
  } else if (TURNS[code]) {
    if (!repeat) turnHub(...TURNS[code]);
  } else if (code === 'Space') {
    if (!repeat) game.dropActive();
  } else if (code === 'KeyX') options.xray = (options.xray + 1) % XRAY.length;
  else if (code === 'KeyI') {
    options.inactiveFalls = !options.inactiveFalls;
    game.config.inactiveFalls = options.inactiveFalls;
  } else if (code === 'KeyV') options.tilt = (options.tilt + 1) % TILTS.length;
  else if (code === 'KeyO') options.rings = !options.rings;
  else if (code === 'KeyG') options.lane = !options.lane;
  else if (code === 'KeyT') options.othersClear = !options.othersClear;
  else if (code === 'KeyF') game.fillForTesting();
  else if (code === 'KeyP') options.paused = !options.paused;
  else if (code === 'KeyH') options.help = !options.help;
  else if (code === 'KeyN') restart();
  else return false;
  keyCount[code] = (keyCount[code] ?? 0) + 1;
  renderKeys();
  return true;
}

window.addEventListener('keydown', (event) => {
  if (event.metaKey || event.ctrlKey || event.altKey) return;
  if (press(event.code, { shift: event.shiftKey, repeat: event.repeat })) event.preventDefault();
});

function restart() {
  game = makeGame();
  pieceViews.clear();
  flashes.clear();
  syncView();
  document.getElementById('banner').hidden = true;
}

// ------------------------------------------------------------------ frame

/** Where each falling stick is drawn: it eases into its cell. */
const pieceViews = new Map();
/** Cells that have just landed flash white for a moment. */
const flashes = new Map();
let clock = 0;

const tilt = { deg: TILTS[options.tilt] };
const target = new THREE.Vector3(0, ARM / 2 - 0.5, 0);
const DISTANCE = 1.5 * (ARM + CENTRE);

function placeCamera(dt) {
  const goal = TILTS[options.tilt];
  tilt.deg += (goal - tilt.deg) * (1 - Math.exp(-dt * 8));
  const a = THREE.MathUtils.degToRad(tilt.deg);
  const distance = DISTANCE * (camera.aspect < 1 ? 1.45 : 1);
  camera.position.set(0, target.y + distance * Math.cos(a), distance * Math.sin(a));
  camera.lookAt(target);
  camera.updateMatrixWorld();
  sharedUniforms.screenUp.value.set(0, 1, 0).applyQuaternion(camera.quaternion);
}

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

function buildBlocks(dt) {
  const hub = game.hub;
  const active = game.active;
  const phase = game.phase;
  const progress = game.phaseDuration > 0 ? Math.min(1, game.phaseElapsed / game.phaseDuration) : 1;

  const ghost = game.ghost();
  // Rows of the active glass that the slice keeps: the ghost's and the one
  // it rests on.
  let sliceTop = 0;
  let sliceBottom = hub.depth() - 1;
  if (ghost) {
    const rows = ghost.map(({ p }) => hub.fromWorld(active, p).row);
    sliceTop = Math.min(...rows);
    sliceBottom = Math.max(...rows) + 1;
  }
  const xrayed = (p) => {
    if (options.xray === 1) return hub.isCentreShell(p);
    if (options.xray === 2) {
      const at = hub.fromWorld(active, p);
      return !at || at.row < sliceTop || at.row > sliceBottom;
    }
    return false;
  };

  const matched = game.activeMatch?.cells;
  const falling = new Set();
  if (phase === 'settling') for (const move of game.moves) falling.add(hub.index(move.to));

  hub.forEachBlock((p, color, index) => {
    if (falling.has(index)) return;
    const at = local(p, tmp);
    if (xrayed(p)) {
      pushClear(at, TONES[color].base, 1, 0.07, 0.4);
      return;
    }
    // Blocks out of the active glass are see-through: the far glass lies
    // right behind the active one on screen, and solid blocks there look as
    // if they were inside it.
    if (options.othersClear && !hub.inGlass(active, p) && !matched?.has(index)) {
      pushClear(at, TONES[color].base, 1, 0.3, 0.75);
      return;
    }
    const brightness = hub.inGlass(active, p) ? 1 : 0.78;
    let flash = 0;
    let size = 0.92;
    if (matched?.has(index)) {
      if (phase === 'matching') flash = 0.25 + 0.4 * Math.sin(progress * Math.PI);
      if (phase === 'clearing') {
        flash = 0.6;
        size = 0.92 * (1 - progress);
      }
    }
    const landed = flashes.get(index);
    if (landed !== undefined) {
      const age = clock - landed;
      if (age > 0.25) flashes.delete(index);
      else flash = Math.max(flash, 0.45 * (1 - age / 0.25));
    }
    if (size > 0.02) pushSolid(at, color, { brightness, flash, size });
  });

  if (phase === 'settling') {
    const t = Math.min(1, game.phaseElapsed / Math.max(0.01, game.phaseDuration - game.config.fallBounceSeconds));
    const from = new THREE.Vector3();
    const to = new THREE.Vector3();
    for (const move of game.moves) {
      local(move.from, from);
      local(move.to, to);
      pushSolid(from.lerp(to, t * t), move.color);
    }
  }

  // Falling sticks ease into their cells; the ones nobody steers are dim.
  const k = 1 - Math.exp(-dt * 24);
  for (const [side, view] of pieceViews) if (game.pieces.get(side) !== view.piece) pieceViews.delete(side);
  for (const piece of game.pieces.values()) {
    let view = pieceViews.get(piece.side);
    const goal = local(piece.pivot, new THREE.Vector3());
    if (!view) {
      view = { piece, at: goal.clone() };
      pieceViews.set(piece.side, view);
    }
    view.at.lerp(goal, k);
    const dir = new THREE.Vector3(...piece.dir);
    piece.colors.forEach((color, i) => {
      const at = view.at.clone().addScaledVector(dir, i - 1);
      if (piece.side === active) pushSolid(at, color);
      else if (options.othersClear) pushClear(at, TONES[color].base, 1, 0.3, 0.75);
      else pushSolid(at, color, { brightness: 0.55 });
    });
  }
  if (phase === 'dropping' && game.drop) {
    const { piece, from } = game.drop;
    const at = local(from, new THREE.Vector3()).lerp(local(piece.pivot, new THREE.Vector3()), progress * progress);
    const dir = new THREE.Vector3(...piece.dir);
    piece.colors.forEach((color, i) => pushSolid(at.clone().addScaledVector(dir, i - 1), color));
  }

  // Where the active stick will land, and the lane down to it.
  const piece = game.activePiece;
  const landed = !ghost || !piece || ghost.every(({ p }, i) => p.every((v, j) => v === pieceCells(piece)[i].p[j]));
  if (!landed) {
    // The game's outline in the stick's colours, in a lighter tone so that
    // it shows over blocks of the same colour.
    for (const { p, color } of ghost) pushClear(local(p, tmp), TONES[color].light, 1, 0.16, 1);
    if (options.lane) pushLanes(piece, ghost);
  }
  placeRings(landed ? null : piece, ghost);
  flushLayers();
}

/** A faint column under each lane of the stick, down to the landing spot —
 * the game's aiming lane. */
function pushLanes(piece, ghost) {
  const side = piece.side;
  const n = normalOf(side);
  const { axis } = SIDES[side];
  const lanes = new Map();
  pieceCells(piece).forEach(({ p }, i) => {
    const key = p.filter((_, j) => j !== axis).join();
    const low = lanes.get(key);
    const height = dot(p, n);
    if (!low || height < low.height) lanes.set(key, { p, height, ghost: ghost[i].p });
  });
  for (const lane of lanes.values()) {
    // From under the stick's lowest square to over the top of the ghost.
    const top = local(lane.p, new THREE.Vector3()).addScaledVector(new THREE.Vector3(...n), -0.5);
    const bottom = local(lane.ghost, new THREE.Vector3()).addScaledVector(new THREE.Vector3(...n), 0.5);
    const length = top.distanceTo(bottom);
    if (length < 0.05) continue;
    const size = [0.92, 0.92, 0.92];
    size[axis] = length;
    pushClear(top.add(bottom).multiplyScalar(0.5), WHITE, 1, 0.07, 0, size);
  }
}

/** The face of the lowest of `cells` that looks towards the floor, as a
 * coordinate along the glass's axis in the hub's frame. */
function floorFace(cells, side) {
  const { axis, sign } = SIDES[side];
  const n = normalOf(side);
  const lowest = cells.reduce((low, c) => (dot(c.p, n) < dot(low.p, n) ? c : low));
  return lowest.p[axis] + 0.5 - HALF - 0.5 * sign;
}

function placeRings(piece, ghost) {
  [pieceRing, ghostRing].forEach((rings) => rings.forEach((ring) => { ring.visible = false; }));
  if (!options.rings || !piece || !ghost) return;
  const { axis } = SIDES[piece.side];
  pieceRing[axis].visible = true;
  pieceRing[axis].position.set(0, 0, 0).setComponent(axis, floorFace(pieceCells(piece), piece.side));
  ghostRing[axis].visible = true;
  ghostRing[axis].position.set(0, 0, 0).setComponent(axis, floorFace(ghost, piece.side));
}

// ------------------------------------------------------------------- HUD

const $ = (id) => document.getElementById(id);
/** The arrow key that brings each glass to the top, by where it points. */
const ARROWS = { '0,1,0': '●', '0,-1,0': '↑↑', '-1,0,0': '←', '1,0,0': '→', '0,0,-1': '↑', '0,0,1': '↓' };
const glassRows = SIDES.map((s) => {
  const row = document.createElement('div');
  row.className = 'glass';
  row.innerHTML = `<span class="num">${s.label}</span><span class="key"></span><span class="bar"><i></i></span><span class="pct"></span>`;
  return row;
});
[...glassRows].sort((a, b) => a.firstChild.textContent - b.firstChild.textContent).forEach((row) => $('glasses').append(row));
let hudVersion = -1;
let hudActive = -1;
let nextKey = '';

function renderHud() {
  $('score').textContent = game.score.toLocaleString('ru-RU');
  $('combo').textContent = game.combo > 1 ? `×${game.combo}` : game.bestCombo > 1 ? `лучшее ×${game.bestCombo}` : '—';
  $('placed').textContent = game.placed;
  $('phase').textContent = options.paused ? 'пауза' : game.phase;
  const next = game.nextColors.join();
  if (next !== nextKey) {
    nextKey = next;
    $('next').innerHTML = game.nextColors.map((c) => {
      const n = parseInt(TONES[c].hex.slice(1), 16);
      const rgb = [(n >> 16) & 255, (n >> 8) & 255, n & 255];
      const css = (channels) => `rgb(${channels.map(Math.round).join(' ')})`;
      return `<i style="--base:${TONES[c].hex};--light:${css(rgb.map((v) => v + (255 - v) * 0.45))};--dark:${css(rgb.map((v) => v * 0.65))}"></i>`;
    }).join('');
  }
  const active = viewActive();
  if (game.hub.version === hudVersion && active === hudActive) return;
  hudVersion = game.hub.version;
  hudActive = active;
  const depth = game.hub.depth();
  SIDES.forEach((s, i) => {
    const row = glassRows[i];
    const room = game.hub.headroom(s.id);
    row.classList.toggle('active', s.id === active);
    row.classList.toggle('crowded', room <= 2);
    row.querySelector('.key').textContent = ARROWS[toScene(normalOf(s.id)).toArray().join()] ?? '?';
    row.querySelector('.bar i').style.width = `${Math.round(((depth - room) / depth) * 100)}%`;
    row.querySelector('.pct').textContent = `${room}`;
    row.title = `свободных рядов у края: ${room}`;
  });
}

function renderKeys() {
  const on = (flag, text) => `<span class="${flag ? 'on' : ''}">${text}</span>`;
  const yes = (flag) => on(flag, flag ? 'да' : 'нет');
  $('keys').hidden = !options.help;
  $('keys').innerHTML = [
    '<b>W A S D</b> — двигать по сечению (как на экране)',
    '<b>Q</b> — наклон влево-вправо ⇄ стоя',
    '<b>E</b> — наклон вперёд-назад ⇄ стоя',
    '<b>R</b> — поворот плашмя; <b>Shift</b> — в другую сторону',
    '<b>Пробел</b> — сбросить',
    '<b>← → ↑ ↓</b> — повернуть хаб: этот сосед наверх',
    `<b>X</b> — рентген: ${on(options.xray > 0, XRAY[options.xray])}`,
    `<b>I</b> — падают и в других: ${yes(options.inactiveFalls)}`,
    `<b>V</b> — камера: ${TILTS[options.tilt]}° от оси`,
    `<b>O</b> — рамки глубины: ${yes(options.rings)} · <b>G</b> — дорожка: ${yes(options.lane)}`,
    `<b>T</b> — другие стаканы прозрачные: ${yes(options.othersClear)}`,
    '<b>F</b> — набросать блоков · <b>P</b> — пауза',
    '<b>N</b> — заново · <b>H</b> — спрятать подсказку',
  ].map((line) => `<div>${line}</div>`).join('');
}

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
  if (turn.t < 1) {
    // A pause stops the turn too, so that it can be looked at half-way.
    if (!options.paused) turn.t = Math.min(1, turn.t + dt / TURN_SECONDS);
    hubGroup.quaternion.slerpQuaternions(turn.from, targetQ, ease(turn.t));
  } else {
    hubGroup.quaternion.copy(targetQ);
  }
  placeCamera(dt);
  buildBlocks(dt);
  renderHud();
  renderer.render(scene, camera);
  requestAnimationFrame(frame);
}

resize();
syncView();
renderKeys();
await document.fonts.ready;
drawLabels();
requestAnimationFrame(frame);

/** For scripted play-tests (shots.mjs) and the console. */
window.__proto3d = {
  get game() { return game; },
  press,
  keyCount,
  /** A data direction as the scene shows it once the turn is over:
   * +x is screen-right, −z is screen-up, +y is towards the eye. */
  toScene: (d) => toScene(d).toArray(),
  options,
  /** Lets `seconds` of game time pass at once. */
  advance(seconds) {
    for (let t = 0; t < seconds; t += 1 / 60) game.update(1 / 60);
    consumeEvents();
  },
  ready: true,
};
