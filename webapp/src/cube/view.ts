// The picture of Cube. The screen shows the cross as the flat game does, and
// the game is played on that picture: each cell shows the nearest block
// behind it, lines of what is seen pop, and what is seen falls (rules.ts).
// The third dimension shows in the sticks of the glasses in front of and
// behind the screen, which fly along the line of sight; as the hub leaning
// over like a tower of blocks when it is tipped; and in the open while the
// volume is looked into. A tip can be looked at before it is made, and while
// paused, or once the game is over, the hub can be turned any way.
//
// Drawn the way the flat game draws its cross (src/render), with three.js.
import * as THREE from 'three';
import { LineSegments2 } from 'three/examples/jsm/lines/LineSegments2.js';
import { LineSegmentsGeometry } from 'three/examples/jsm/lines/LineSegmentsGeometry.js';
import { LineMaterial } from 'three/examples/jsm/lines/LineMaterial.js';
import { RoundedBoxGeometry } from 'three/examples/jsm/geometries/RoundedBoxGeometry.js';
import { paletteRevision, paletteTones } from '../render/theme';
import {
  SIDES,
  dot,
  normalOf,
  pieceCells,
  sideOfNormal,
  type CubeEvent,
  type CubeGame,
  type Stick,
  type StickCell,
  type TurnPreview,
  type Vec,
} from './rules';

/** What the picture shows besides the game itself (settings). */
export interface CubeLook {
  /** The sticks in front and behind that are not being steered. */
  depthSticks: boolean;
  /** A mark in a corner of a cell with the colour of the block behind it. */
  behind: boolean;
  /** The edges of the hub's glasses. */
  edges: boolean;
  /** The glasses' numbers. */
  numbers: boolean;
  /** The aiming lane under the stick on top. */
  lane: boolean;
}

/** Which way the hub is turned to be looked at, while paused. */
export type LookAxis = 'upright' | 'across' | 'sight';

/** The glass the player steers, as the screen shows it. */
export type Steering = 'top' | 'front' | 'back';

interface Tone {
  base: THREE.Color;
  light: THREE.Color;
  dark: THREE.Color;
}

interface Placed {
  at: THREE.Vector3;
  lift: number;
  nudge: THREE.Vector3 | null;
  spin: THREE.Quaternion | null;
  frame: THREE.Quaternion | null;
  depth: number;
}

interface TileItem extends Placed {
  size: number;
  tone: Tone;
  brightness: number;
  flash: number;
  alpha: number;
}

interface ClearItem extends Placed {
  size: [number, number, number];
  color: THREE.Color;
  alpha: number;
  fill: number;
  edge: number;
}

interface Layer<Item> {
  mesh: THREE.InstancedMesh;
  buffers: Record<string, THREE.InstancedBufferAttribute>;
  items: Item[];
}

/** Where a falling stick is drawn, kept while its stick is the same one:
 * `base` is the way it lay when first seen, `aim` the turn that takes `base`
 * to the way it lies now, `spin` the turn drawn, easing towards `aim`. `from`
 * is where a tip found it, to carry it from there. */
interface StickView {
  colors: number[];
  at: THREE.Vector3;
  base: THREE.Vector3;
  dir: THREE.Vector3;
  aim: THREE.Quaternion;
  spin: THREE.Quaternion;
  from: { at: THREE.Vector3; turn: THREE.Quaternion; dir: THREE.Vector3 } | null;
}

interface DrawnStick {
  piece: Stick;
  at: THREE.Vector3;
  spin: THREE.Quaternion;
  base: THREE.Vector3;
}

const WHITE = new THREE.Color('#ffffff');
/** Accent of the active glass (THEME.accent). */
const ACCENT = new THREE.Color('rgb(120, 205, 255)');
/** The mark of a square that would hide: a dark hole. */
const HOLE = new THREE.Color('#05050a');
/** Tipping the hub over takes a little longer than turning the cross. */
const TILT_SECONDS = 0.65;
/** How far the hub turns to be looked into: from above or below, from the
 * right or the left. */
const PEEK_PITCH = 0.45;
const PEEK_YAW = 0.55;
/** Depth is squashed this flat when the picture is the game: the nearest
 * block of every cell still wins, but nothing looks deeper than another. */
const FLAT = 0.02;
/** How much of a cell a block fills, and how round its edges are: the 2D
 * sprite is a rounded tile with a narrow gap round it. */
const TILE = 0.96;
const ROUND = 0.13;
/** The small marks in the corners of cells. */
const MARK = 0.3;
const corner = (x: number, y: number) => new THREE.Vector3(0.27 * x, 0.27 * y, 0.5);

const SCENE_RIGHT = new THREE.Vector3(1, 0, 0);
const SCENE_UP = new THREE.Vector3(0, 1, 0);
const SCENE_TOWARD = new THREE.Vector3(0, 0, 1);
const IDENTITY = new THREE.Quaternion();

const ease = (t: number) => (t < 0.5 ? 4 * t * t * t : 1 - (-2 * t + 2) ** 3 / 2);

/** A scene direction in the data frame of a turn `q`. */
const dataIn = (q: THREE.Quaternion, v: THREE.Vector3): Vec => {
  const w = v.clone().applyQuaternion(q.clone().invert());
  return [Math.round(w.x), Math.round(w.y), Math.round(w.z)];
};

/** `base` after a quarter turn about a scene axis, snapped so that the
 * rounding drift of many turns never builds up. */
function quarterTurned(axis: THREE.Vector3, quarters: number, base: THREE.Quaternion): THREE.Quaternion {
  const q = new THREE.Quaternion().setFromAxisAngle(axis, (quarters * Math.PI) / 2).multiply(base);
  const m = new THREE.Matrix4().makeRotationFromQuaternion(q);
  m.elements.forEach((e, i) => {
    m.elements[i] = Math.round(e);
  });
  return q.setFromRotationMatrix(m);
}

// The game's block in 3D: a cube with rounded edges. Seen face on it is the
// 2D sprite — the rounded rim graded from light at the top of the screen
// through the colour to dark at the bottom, around a flat face of the plain
// colour with a soft shine across its top. Faces turned from the eye are a
// little darker, so that the hub reads as solid while it is open.
const TILE_VERTEX = /* glsl */ `
  uniform vec3 screenUp;
  attribute vec3 aBase;
  attribute vec3 aLight;
  attribute vec3 aDark;
  attribute vec3 aLook;
  varying vec3 vObjectNormal;
  varying vec3 vFaceNormal;
  varying float vUp;
  varying vec3 vBase;
  varying vec3 vLight;
  varying vec3 vDark;
  varying vec3 vLook;
  void main() {
    vBase = aBase;
    vLight = aLight;
    vDark = aDark;
    vLook = aLook;
    mat4 model = modelMatrix * instanceMatrix;
    mat3 turn = mat3(model);
    vObjectNormal = normal;
    // Which face of the cube this point belongs to, rim included.
    vec3 a = abs(normal);
    vec3 face = a.x >= a.y && a.x >= a.z ? vec3(sign(normal.x), 0.0, 0.0)
      : a.y >= a.z ? vec3(0.0, sign(normal.y), 0.0) : vec3(0.0, 0.0, sign(normal.z));
    vFaceNormal = normalize(turn * face);
    // How far up the screen this point is from the cube's centre.
    vUp = dot(turn * position, screenUp) / length(turn[0]);
    gl_Position = projectionMatrix * viewMatrix * model * vec4(position, 1.0);
  }`;
const TILE_FRAGMENT = /* glsl */ `
  varying vec3 vObjectNormal;
  varying vec3 vFaceNormal;
  varying float vUp;
  varying vec3 vBase;
  varying vec3 vLight;
  varying vec3 vDark;
  varying vec3 vLook; // brightness, white flash, opacity
  void main() {
    vec3 n = normalize(vObjectNormal);
    // 1 on the flat of a face, 0 on its rounded rim.
    float flatness = max(max(abs(n.x), abs(n.y)), abs(n.z));
    float onFace = smoothstep(0.985, 0.999, flatness);
    // The rim: light at the top of the screen, the colour, dark at the bottom.
    float y = clamp(0.5 - vUp, 0.0, 1.0);
    vec3 rim = y < 0.3 ? mix(vLight, vBase, y / 0.3) : mix(vBase, vDark, (y - 0.3) / 0.7);
    // The face: the plain colour, a shine across its top where it looks at the eye.
    float toEye = max(vFaceNormal.z, 0.0);
    float fy = clamp((0.37 - vUp) / 0.74, 0.0, 1.0);
    vec3 face = mix(vBase, vec3(1.0), 0.34 * max(0.0, 1.0 - fy * 2.0) * toEye);
    vec3 colour = mix(rim, face, onFace);
    colour *= clamp(0.72 + 0.28 * toEye + 0.12 * vFaceNormal.y, 0.0, 1.0) * vLook.x;
    colour = mix(colour, vec3(1.0), vLook.y);
    gl_FragColor = vec4(colour, vLook.z);
    #include <tonemapping_fragment>
    #include <colorspace_fragment>
  }`;
// Outlines and see-through cubes: the landing spot, the aiming lane, the
// sticks in front and behind.
const CLEAR_VERTEX = /* glsl */ `
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
  }`;
const CLEAR_FRAGMENT = /* glsl */ `
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
  }`;

/** Draws a game of Cube on a canvas and turns the player's intentions into
 * its moves: which way is left on the screen, which glass is on top, what
 * the hub looks like as it tips. The screen owns the game loop and calls
 * `frame` once per animation frame. */
export class CubeView {
  look: CubeLook = { depthSticks: false, behind: true, edges: false, numbers: false, lane: true };
  /** How long the cross takes to turn in the screen; 0 turns it at once. */
  turnSeconds = 0.36;
  /** Paused: the sticks in front and behind all show. */
  paused = false;
  /** The volume is being looked into; from where: +1 above / right, −1
   * below / left. */
  peeking = false;
  peekPitch = 1;
  peekYaw = 1;

  private readonly renderer: THREE.WebGLRenderer;
  private readonly scene = new THREE.Scene();
  private readonly camera: THREE.PerspectiveCamera;
  private readonly distance: number;
  private readonly n: number;
  private readonly halfHub: number;
  private readonly h: number;
  private readonly reach: number;
  private readonly hubGroup = new THREE.Group();
  private readonly crossGroup = new THREE.Group();
  private readonly lineMaterials: LineMaterial[] = [];
  private readonly hubLines: LineSegments2[] = [];
  private readonly labels: { sprite: THREE.Sprite; canvas: HTMLCanvasElement }[] = [];
  private readonly solid: Layer<TileItem>;
  private readonly fading: Layer<TileItem>;
  private readonly clear: Layer<ClearItem>;
  private readonly disposables: { dispose(): void }[] = [];
  private tones: Tone[] = [];
  private tonesRevision = -1;

  private readonly perspective = new THREE.Matrix4();
  private readonly orthographic = new THREE.Matrix4();
  /** How much of the depth is shown: FLAT while playing, 1 mid-tip and while
   * the volume is looked into. */
  private depthShown = FLAT;

  /** Where the hub is turned to; the picture eases towards it. Always a
   * whole number of quarter turns, so data axes map onto scene axes. */
  private readonly targetQ = new THREE.Quaternion();
  private readonly turnFrom = new THREE.Quaternion();
  private readonly turned = new THREE.Quaternion();
  /** The hub's frame as the tip began, with the look into the volume: what
   * the sticks that stay put are drawn in meanwhile. */
  private readonly tiltFrom = new THREE.Quaternion();
  /** The turn under way: `tilt` when it leans the hub over rather than
   * turning the cross in the screen. */
  private readonly turn = { t: 1, tilt: false, carry: false, steeredFrom: 0 };
  /** 0 when the picture is the game, 1 while the volume is looked into. */
  private peek = 0;
  private readonly peekFrom = new THREE.Quaternion();
  private readonly peekTo = new THREE.Quaternion();
  /** Turned to be looked at, while paused or once the game is over. */
  private inspect: THREE.Quaternion | null = null;
  /** A tip looked at before it is made. */
  private preview: { up: boolean; q: THREE.Quaternion; version: number; result: TurnPreview | null } | null = null;

  private readonly pieceViews = new Map<number, StickView>();
  /** Cells that have just landed flash white for a moment. */
  private readonly flashes = new Map<number, number>();
  private clock = 0;
  private readonly behindCache = { key: '', marks: [] as { at: THREE.Vector3; color: number }[] };
  private readonly linesCache = { key: '', cells: new Set<number>(), runs: 0 };
  private labelsDrawn = false;

  private readonly matrix = new THREE.Matrix4();
  private readonly scaleVector = new THREE.Vector3();
  private readonly turnScratch = new THREE.Quaternion();
  private readonly sharedUniforms = { screenUp: { value: new THREE.Vector3(0, 1, 0) } };

  constructor(
    canvas: HTMLCanvasElement,
    public game: CubeGame,
  ) {
    const { centre, arm } = game.config;
    this.n = centre + 2 * arm;
    this.halfHub = this.n / 2;
    this.h = centre / 2;
    this.reach = this.h + arm;
    // Transparent, over the game's own backdrop.
    this.renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true });
    this.renderer.setClearColor(0x000000, 0);
    // Far away and narrow, so that the cross looks flat.
    this.distance = 4.2 * this.reach;
    this.camera = new THREE.PerspectiveCamera(30, 1, 1, this.distance * 3);
    this.camera.position.set(0, 0, this.distance);
    this.camera.lookAt(0, 0, 0);
    this.scene.add(this.hubGroup, this.crossGroup);
    this.buildCross();
    this.buildHub();
    const maxCubes = this.n * this.n * this.n + 64;
    const tileAttributes = { aBase: 3, aLight: 3, aDark: 3, aLook: 3 };
    this.solid = this.cubeLayer(this.tileMaterial(false), tileAttributes, 1, maxCubes, new RoundedBoxGeometry(1, 1, 1, 3, ROUND));
    // Blocks fading in or out — sticks going out of sight or coming into it
    // as the hub tips over — drawn see-through, far to near, after the others.
    this.fading = this.cubeLayer(this.tileMaterial(true), tileAttributes, 2, maxCubes, new RoundedBoxGeometry(1, 1, 1, 3, ROUND));
    const clearMaterial = new THREE.ShaderMaterial({
      transparent: true,
      depthWrite: false,
      vertexShader: CLEAR_VERTEX,
      fragmentShader: CLEAR_FRAGMENT,
    });
    this.clear = this.cubeLayer(clearMaterial, { aColor: 3, aLook: 3 }, 6, 512, new THREE.BoxGeometry(1, 1, 1));
  }

  // ------------------------------------------------------------ the scene

  /** Thin lines of one colour, a pixel or so wide. */
  private makeLines(positions: number[], parent: THREE.Object3D, { color = WHITE, opacity = 1, width = 1 } = {}): LineSegments2 {
    const geometry = new LineSegmentsGeometry();
    geometry.setPositions(positions);
    const material = new LineMaterial({ color, opacity, linewidth: width, transparent: true, depthWrite: false });
    material.userData.opacity = opacity;
    material.userData.width = width;
    this.lineMaterials.push(material);
    this.disposables.push(geometry, material);
    const mesh = new LineSegments2(geometry, material);
    parent.add(mesh);
    return mesh;
  }

  private makePane(x: number, y: number, width: number, height: number, opacity: number, parent: THREE.Object3D): void {
    const material = new THREE.MeshBasicMaterial({ color: WHITE, transparent: true, opacity, depthWrite: false });
    material.userData.opacity = opacity;
    const geometry = new THREE.PlaneGeometry(width, height);
    this.disposables.push(geometry, material);
    const mesh = new THREE.Mesh(geometry, material);
    mesh.position.set(x, y, -0.5);
    parent.add(mesh);
  }

  /** The cross of the flat game, fixed to the screen (src/render/renderer.ts
   * drawField): a faint fill and grid for each arm and for the centre,
   * outlines a little brighter, the glass on top in the accent. It fades
   * while the hub opens up. */
  private buildCross(): void {
    const { h, reach } = this;
    const { centre, arm } = this.game.config;
    const z = -0.5;
    const arms = [0, 1, 2, 3].map((quarter) => {
      // Drawn for the arm on top, then turned a quarter at a time.
      const group = new THREE.Group();
      group.rotation.z = (-quarter * Math.PI) / 2;
      this.crossGroup.add(group);
      this.makePane(0, h + arm / 2, centre, arm, 0.022, group);
      const grid: number[] = [];
      for (let i = 1; i < centre; i++) grid.push(-h + i, h, z, -h + i, reach, z);
      for (let j = 1; j < arm; j++) grid.push(-h, h + j, z, h, h + j, z);
      this.makeLines(grid, group, { opacity: 0.045 });
      const outline = [-h, h, z, -h, reach, z, -h, reach, z, h, reach, z, h, reach, z, h, h, z];
      return this.makeLines(outline, group, { opacity: 0.16, width: 1.5 });
    });
    this.makePane(0, 0, centre, centre, 0.05, this.crossGroup);
    const grid: number[] = [];
    for (let i = 1; i < centre; i++) grid.push(-h + i, -h, z, -h + i, h, z, -h, -h + i, z, h, -h + i, z);
    this.makeLines(grid, this.crossGroup, { opacity: 0.07 });
    this.makeLines([-h, -h, z, h, -h, z, h, -h, z, h, h, z, h, h, z, -h, h, z, -h, h, z, -h, -h, z], this.crossGroup, {
      opacity: 0.22,
      width: 1.5,
    });
    // The glass on top: its outline in the accent.
    arms[0].material.color.copy(ACCENT);
    arms[0].material.userData.opacity = arms[0].material.opacity = 0.6;
  }

  /** The hub itself: the edges of all six glasses and of the centre cube,
   * and the glasses' numbers beside a corner of each rim. Both only when
   * asked for. */
  private buildHub(): void {
    const { h } = this;
    const { arm } = this.game.config;
    const armPoint = (side: number, t: number, a: number, b: number): number[] => {
      const { axis, sign } = SIDES[side];
      const [k1, k2] = [0, 1, 2].filter((i) => i !== axis);
      const p = [0, 0, 0];
      p[axis] = sign * (h + t);
      p[k1] = a;
      p[k2] = b;
      return p;
    };
    const corners = [
      [-h, -h],
      [h, -h],
      [h, h],
      [-h, h],
    ];
    for (const s of SIDES) {
      const p: number[] = [];
      corners.forEach(([a, b], i) => {
        const [na, nb] = corners[(i + 1) % 4];
        p.push(...armPoint(s.id, 0, a, b), ...armPoint(s.id, arm, a, b));
        p.push(...armPoint(s.id, arm, a, b), ...armPoint(s.id, arm, na, nb));
      });
      this.hubLines.push(this.makeLines(p, this.hubGroup, { opacity: 0.1 }));
    }
    const p: number[] = [];
    for (const a of [-h, h]) for (const b of [-h, h]) p.push(-h, a, b, h, a, b, a, -h, b, a, h, b, a, b, -h, a, b, h);
    this.hubLines.push(this.makeLines(p, this.hubGroup, { opacity: 0.12 }));
    for (const s of SIDES) {
      const canvas = document.createElement('canvas');
      canvas.width = canvas.height = 128;
      const texture = new THREE.CanvasTexture(canvas);
      const material = new THREE.SpriteMaterial({ map: texture, depthTest: false, transparent: true });
      this.disposables.push(texture, material);
      const sprite = new THREE.Sprite(material);
      sprite.position.set(...(armPoint(s.id, arm - 0.2, h + 0.75, h + 0.75) as Vec));
      sprite.scale.set(1.15, 1.15, 1);
      sprite.renderOrder = 20;
      this.hubGroup.add(sprite);
      this.labels.push({ sprite, canvas });
    }
  }

  private drawLabels(): void {
    this.labels.forEach(({ sprite, canvas }, side) => {
      const g = canvas.getContext('2d');
      if (!g) return;
      g.clearRect(0, 0, 128, 128);
      g.font = '900 italic 88px "Exo 2", system-ui';
      g.textAlign = 'center';
      g.textBaseline = 'middle';
      g.fillStyle = '#eceff9';
      g.fillText(SIDES[side].label, 64, 68);
      sprite.material.map!.needsUpdate = true;
    });
  }

  private tileMaterial(fading: boolean): THREE.ShaderMaterial {
    return new THREE.ShaderMaterial({
      uniforms: this.sharedUniforms,
      transparent: fading,
      depthWrite: !fading,
      vertexShader: TILE_VERTEX,
      fragmentShader: TILE_FRAGMENT,
    });
  }

  private cubeLayer<Item>(
    material: THREE.Material,
    attributes: Record<string, number>,
    renderOrder: number,
    capacity: number,
    geometry: THREE.BufferGeometry,
  ): Layer<Item> {
    const buffers: Record<string, THREE.InstancedBufferAttribute> = {};
    for (const [name, size] of Object.entries(attributes)) {
      buffers[name] = new THREE.InstancedBufferAttribute(new Float32Array(capacity * size), size);
      buffers[name].setUsage(THREE.DynamicDrawUsage);
      geometry.setAttribute(name, buffers[name]);
    }
    const mesh = new THREE.InstancedMesh(geometry, material, capacity);
    mesh.frustumCulled = false;
    mesh.renderOrder = renderOrder;
    mesh.count = 0;
    this.scene.add(mesh);
    this.disposables.push(geometry, material);
    return { mesh, buffers, items: [] };
  }

  /** The block colours follow the active set. */
  private refreshTones(): void {
    if (this.tonesRevision === paletteRevision()) return;
    this.tonesRevision = paletteRevision();
    const colour = (css: string) => new THREE.Color().setStyle(css, THREE.SRGBColorSpace);
    this.tones = paletteTones().map((t) => ({ base: colour(t.base), light: colour(t.light), dark: colour(t.dark) }));
  }

  /** Centre of a data cell in the hub's own frame. */
  private local(p: readonly number[], out = new THREE.Vector3()): THREE.Vector3 {
    const half = this.halfHub;
    return out.set(p[0] + 0.5 - half, p[1] + 0.5 - half, p[2] + 0.5 - half);
  }

  /** `at` is in the hub's frame. `lift` moves a cube towards the eye (or
   * away) while the picture is flat: the sticks in front of and behind the
   * screen are drawn over and under it. `nudge` shifts it on the screen, for
   * the small marks in the corners of cells. */
  private pushSolid(
    at: THREE.Vector3,
    color: number,
    { brightness = 1, flash = 0, size = TILE, lift = 0, nudge = null as THREE.Vector3 | null, spin = null as THREE.Quaternion | null, frame = null as THREE.Quaternion | null, alpha = 1 } = {},
  ): void {
    if (alpha <= 0.01) return;
    const tone = this.tones[color] ?? this.tones[0];
    (alpha < 0.99 ? this.fading : this.solid).items.push({
      at: at.clone(), size, lift, nudge, spin, frame, tone, brightness, flash, alpha, depth: 0,
    });
  }

  private pushClear(
    at: THREE.Vector3,
    color: THREE.Color,
    alpha: number,
    fill: number,
    edge: number,
    { size = [0.91, 0.91, 0.91] as [number, number, number], lift = 0, nudge = null as THREE.Vector3 | null, spin = null as THREE.Quaternion | null } = {},
  ): void {
    this.clear.items.push({ at: at.clone(), size, lift, nudge, spin, frame: null, color, alpha, fill, edge, depth: 0 });
  }

  /** Where a cube of the hub's frame is drawn in the scene. */
  private place(item: Placed): THREE.Vector3 {
    const at = item.at.applyQuaternion(item.frame ?? this.hubGroup.quaternion);
    at.z = at.z * this.depthShown + item.lift * (1 - this.depthShown);
    if (item.nudge) at.add(item.nudge);
    return at;
  }

  /** How a cube is turned on the screen: with the hub (or the frame it is
   * drawn in), and then by its own turn, if it is a stick turning. */
  private turnOf(item: Placed): THREE.Quaternion {
    const frame = item.frame ?? this.hubGroup.quaternion;
    return item.spin ? this.turnScratch.copy(frame).multiply(item.spin) : frame;
  }

  private flushLayers(): void {
    const { solid, fading, clear, matrix, scaleVector, camera } = this;
    for (const item of fading.items) {
      this.place(item);
      item.depth = item.at.distanceToSquared(camera.position);
    }
    fading.items.sort((a, b) => b.depth - a.depth);
    for (const layer of [solid, fading]) {
      const capacity = layer.mesh.instanceMatrix.count;
      if (layer.items.length > capacity) layer.items.length = capacity;
      layer.items.forEach((item, i) => {
        scaleVector.set(item.size, item.size, item.size);
        matrix.compose(layer === fading ? item.at : this.place(item), this.turnOf(item), scaleVector);
        layer.mesh.setMatrixAt(i, matrix);
        const { base, light, dark } = item.tone;
        const { buffers } = layer;
        buffers.aBase.setXYZ(i, base.r, base.g, base.b);
        buffers.aLight.setXYZ(i, light.r, light.g, light.b);
        buffers.aDark.setXYZ(i, dark.r, dark.g, dark.b);
        buffers.aLook.setXYZ(i, item.brightness, item.flash, item.alpha);
      });
    }
    for (const item of clear.items) {
      this.place(item);
      item.depth = item.at.distanceToSquared(camera.position);
    }
    clear.items.sort((a, b) => b.depth - a.depth);
    if (clear.items.length > clear.mesh.instanceMatrix.count) clear.items.length = clear.mesh.instanceMatrix.count;
    clear.items.forEach((item, i) => {
      scaleVector.set(...item.size);
      matrix.compose(item.at, this.turnOf(item), scaleVector);
      clear.mesh.setMatrixAt(i, matrix);
      clear.buffers.aColor.setXYZ(i, item.color.r, item.color.g, item.color.b);
      clear.buffers.aLook.setXYZ(i, item.alpha, item.fill, item.edge);
    });
    for (const layer of [solid, fading, clear] as Layer<Placed>[]) {
      layer.mesh.count = layer.items.length;
      layer.mesh.instanceMatrix.needsUpdate = true;
      for (const buffer of Object.values(layer.buffers)) buffer.needsUpdate = true;
      layer.items.length = 0;
    }
  }

  /** The canvas is `width` × `height` CSS pixels. The whole cross fits,
   * whichever side is short. */
  resize(width: number, height: number, dpr: number): void {
    if (width <= 0 || height <= 0) return;
    this.renderer.setPixelRatio(dpr);
    this.renderer.setSize(width, height, false);
    for (const m of this.lineMaterials) {
      m.resolution.set(width * dpr, height * dpr);
      m.linewidth = (m.userData.width as number) * dpr;
    }
    const { camera } = this;
    camera.aspect = width / height;
    const half = this.reach + 0.6;
    const tan = half / (this.distance - this.h) / Math.min(1, camera.aspect);
    camera.fov = THREE.MathUtils.radToDeg(2 * Math.atan(tan));
    camera.updateProjectionMatrix();
    this.perspective.copy(camera.projectionMatrix);
    // The same size at the cross's own plane, with nothing seen from the side.
    const high = this.distance * Math.tan(THREE.MathUtils.degToRad(camera.fov / 2));
    const wide = high * camera.aspect;
    this.orthographic.makeOrthographic(-wide, wide, high, -high, camera.near, camera.far);
    // A canvas sized anew is blank: what was drawn is drawn again at once,
    // or a field that changes size frame after frame would flicker.
    this.project(this.depthShown === FLAT ? 0 : (this.depthShown - FLAT) / (1 - FLAT));
    this.renderer.render(this.scene, this.camera);
  }

  /** The flat picture is drawn straight on, like the flat game — no block
   * shows a side, however far it is from the middle. As the hub opens up the
   * eye eases into perspective; the cross's own plane keeps its size. */
  private project(opened: number): void {
    const e = this.camera.projectionMatrix.elements;
    const o = this.orthographic.elements;
    const p = this.perspective.elements;
    for (let i = 0; i < 16; i++) e[i] = o[i] + (p[i] - o[i]) * opened;
    this.camera.projectionMatrixInverse.copy(this.camera.projectionMatrix).invert();
  }

  /** Shows another game of the same size from scratch, as a new game lies:
   * the tutorial's lessons. */
  reset(game: CubeGame): void {
    this.game = game;
    for (const q of [this.targetQ, this.turnFrom, this.turned, this.tiltFrom]) q.identity();
    Object.assign(this.turn, { t: 1, tilt: false, carry: false, steeredFrom: game.active });
    this.preview = null;
    this.inspect = null;
    this.pieceViews.clear();
    this.flashes.clear();
    this.behindCache.key = '';
    this.linesCache.key = '';
  }

  dispose(): void {
    for (const item of this.disposables) item.dispose();
    this.renderer.dispose();
  }

  // ------------------------------------------------------------ the turns

  /** A scene direction in the data frame, once the turn under way is over. */
  private toData(v: THREE.Vector3): Vec {
    return dataIn(this.targetQ, v);
  }

  /** A data direction in the scene, once the turn under way is over. */
  private toScene(d: Vec): THREE.Vector3 {
    return new THREE.Vector3(...d).applyQuaternion(this.targetQ).round();
  }

  /** The game's hub seen from the side a turn `q` faces the eye, on the
   * same blocks (read only). */
  private viewAt(q: THREE.Quaternion): CubeGame {
    return this.game.lookFrom(dataIn(q, SCENE_TOWARD), { right: dataIn(q, SCENE_RIGHT), up: dataIn(q, SCENE_UP) }, this.game.hub);
  }

  /** Where the turn under way ends. */
  private goalQ(): THREE.Quaternion {
    return this.preview?.q ?? this.inspect ?? this.targetQ;
  }

  /** A tip of the game (or its preview) under way: the rules lay the sticks
   * on the new side, and those on its axis stay put on the screen. */
  private carrying(): boolean {
    return this.turn.t < 1 && this.turn.carry;
  }

  /** The hub leans over: the game holds still meanwhile. */
  get tilting(): boolean {
    return this.turn.t < 1 && this.turn.tilt;
  }

  /** Shows the hub turning, as one body. Tipped over — or turned to be
   * looked at about anything but the line of sight — it leans like a tower
   * of blocks and opens up into depth on the way, flattening again as it
   * lands. Turned in the screen it stays flat, as the 2D cross turns.
   * `steered`: the glass steered on the side the turn starts from. */
  private transition(axis: THREE.Vector3 | null, { carry = false, steered = this.game.active } = {}): void {
    this.turnFrom.copy(this.turned);
    this.turn.t = 0;
    this.turn.tilt = axis !== SCENE_TOWARD;
    this.turn.carry = carry && this.turn.tilt;
    this.turn.steeredFrom = steered;
    // Where each stick is and how it lies on the screen as a tip begins, to
    // carry it from there (`stickViews`).
    for (const view of this.pieceViews.values()) {
      if (!this.turn.carry) {
        view.from = null;
        continue;
      }
      const onScreen = this.turnFrom.clone().multiply(view.spin);
      view.from = { at: view.at.clone(), turn: onScreen, dir: view.base.clone().applyQuaternion(onScreen) };
    }
  }

  /** Whether the flat picture shows the stick of `side` with the hub turned
   * by `q` and `steered` the glass steered: always for a glass across the
   * screen; in front or behind only when steered, or asked for, or paused. */
  private shownFlat(side: number, q: THREE.Quaternion, steered: number): boolean {
    const across = Math.abs(new THREE.Vector3(...normalOf(side)).applyQuaternion(q).z) < 0.5;
    return across || side === steered || this.look.depthSticks || this.paused;
  }

  /** The glasses that lie across the screen both before and after a tip (on
   * its axis): their sticks stay where the screen shows them rather than
   * turn with the hub, and the rules lay them there on the new side too. */
  private staysPut(side: number, from: THREE.Quaternion, to: THREE.Quaternion): boolean {
    const before = new THREE.Vector3(...normalOf(side)).applyQuaternion(from);
    const after = new THREE.Vector3(...normalOf(side)).applyQuaternion(to);
    return Math.abs(before.z) < 0.5 && Math.abs(after.z) < 0.5 && before.dot(after) > 0.5;
  }

  /** Once a tip that carried the sticks has landed, the views of those that
   * stayed put are moved into the hub's new frame, where they show the
   * same: the rules have laid them just there. */
  private landCarried(): void {
    const to = this.goalQ();
    const shift = to.clone().invert().multiply(this.turnFrom);
    for (const [side, view] of this.pieceViews) {
      view.from = null;
      if (!this.staysPut(side, this.turnFrom, to)) {
        // Already where it lies; the same turn, as the views keep it.
        view.spin.copy(view.aim);
        continue;
      }
      view.at.applyQuaternion(shift);
      view.dir.applyQuaternion(shift).round();
      view.aim.premultiply(shift);
      view.spin.premultiply(shift);
    }
  }

  /** Turns the hub a quarter turn about a scene axis: about the line of
   * sight as the 2D cross turns, or about the screen's horizontal, so that
   * the glass behind or in front comes over the top and the new picture
   * settles and pops. The glass on top is steered. `shown`: a preview has
   * already shown it, settled. */
  private turnHub(axis: THREE.Vector3, quarters: number, shown = false): void {
    const to = quarterTurned(axis, quarters, this.targetQ);
    if (!shown) this.transition(axis, { carry: true });
    this.targetQ.copy(to);
    const tipped = axis !== SCENE_TOWARD;
    const { game } = this;
    game.turn(sideOfNormal(this.toData(SCENE_UP)), this.toData(SCENE_TOWARD), { right: this.toData(SCENE_RIGHT), up: this.toData(SCENE_UP) }, tipped);
    // The preview showed the blocks where they come to rest: no fall again.
    if (shown && game.phase === 'settling') game.phaseElapsed = game.phaseDuration;
  }

  // ------------------------------------------------------------ the player

  /** The glass steered, as the screen shows it. */
  get steering(): Steering {
    const z = this.toScene(normalOf(this.game.active)).z;
    return z > 0 ? 'front' : z < 0 ? 'back' : 'top';
  }

  /** Where a glass is on the screen now. */
  placeOf(side: number): 'top' | 'right' | 'bottom' | 'left' | 'front' | 'back' {
    const at = this.toScene(normalOf(side));
    return at.z > 0 ? 'front' : at.z < 0 ? 'back' : at.y > 0 ? 'top' : at.y < 0 ? 'bottom' : at.x > 0 ? 'right' : 'left';
  }

  /** What the tip held would give: how many blocks would pop in how many
   * rounds. Null while none is held. */
  get tipPreview(): { up: boolean; popped: number; rounds: number } | null {
    const result = this.preview?.result;
    return result ? { up: this.preview!.up, popped: result.popped, rounds: result.rounds } : null;
  }

  /** Turned to be looked at: how many lines show from there. */
  get inspecting(): { runs: number; blocks: number } | null {
    if (!this.inspect) return null;
    const { runs, cells } = this.inspectLines();
    return { runs, blocks: cells.size };
  }

  /** Left or right on the screen. */
  move(direction: -1 | 1): void {
    this.game.move(this.toData(SCENE_RIGHT.clone().multiplyScalar(direction)));
  }

  /** Up or down on the screen: for a stick in front or behind. */
  shift(direction: -1 | 1): void {
    if (this.steering === 'top') return;
    this.game.move(this.toData(SCENE_UP.clone().multiplyScalar(direction)));
  }

  /** A quarter turn of the stick in the screen. */
  rotate(clockwise: boolean): void {
    this.game.rotate(this.toData(clockwise ? SCENE_TOWARD.clone().negate() : SCENE_TOWARD));
  }

  drop(): void {
    this.game.dropActive();
  }

  softDrop(held: boolean): void {
    this.game.softDrop = held;
  }

  /** The cross turns in the screen, as in 2D: the glass on the left (−1) or
   * right (+1) comes to the top, and nothing falls. */
  turnCross(quarters: -1 | 1): void {
    if (this.preview || this.inspect) return;
    this.turnHub(SCENE_TOWARD, quarters);
  }

  /** Steers the stick in front or behind; the same again goes back to the
   * glass on top. `cycle`: top, front, back, top. */
  steer(which: 'front' | 'back' | 'cycle'): void {
    if (this.preview || this.inspect) return;
    const front = sideOfNormal(this.toData(SCENE_TOWARD));
    const back = sideOfNormal(this.toData(SCENE_TOWARD.clone().negate()));
    const top = sideOfNormal(this.toData(SCENE_UP));
    const now = this.steering;
    const next = which === 'cycle'
      ? now === 'top' ? front : now === 'front' ? back : top
      : which === 'front' ? now === 'front' ? top : front
      : now === 'back' ? top : back;
    this.game.control(next);
  }

  /** Starts showing how the hub would lie with the glass behind (`up`) or in
   * front tipped over the top; the other way while one is shown puts it
   * back. Letting go (`commitTip`) tips it. */
  startTip(up: boolean): void {
    if (this.inspect || this.game.isGameOver) return;
    if (this.preview) {
      if (this.preview.up !== up) this.cancelTip();
      return;
    }
    const quarters = up ? 1 : -1;
    this.preview = { up, q: quarterTurned(SCENE_RIGHT, quarters, this.targetQ), version: -1, result: null };
    this.refreshPreview();
    this.transition(SCENE_RIGHT, { carry: true });
  }

  /** True when the hub was tipped. */
  commitTip(up: boolean): boolean {
    if (this.preview?.up !== up) return false;
    this.preview = null;
    this.turnHub(SCENE_RIGHT, up ? 1 : -1, true);
    return true;
  }

  cancelTip(): void {
    if (!this.preview) return;
    // From the preview's side, where its top glass was the one steered.
    this.transition(SCENE_RIGHT, { carry: true, steered: this.preview.result?.view.active ?? this.game.active });
    this.preview = null;
  }

  /** Works the preview out again when the board has changed under it. */
  private refreshPreview(): void {
    const { preview } = this;
    if (!preview || preview.version === this.game.hub.version) return;
    preview.version = this.game.hub.version;
    const { q } = preview;
    preview.result = this.game.previewTurn(dataIn(q, SCENE_TOWARD), { right: dataIn(q, SCENE_RIGHT), up: dataIn(q, SCENE_UP) });
  }

  /** While paused, or once the game is over, the hub can be turned any way
   * to be looked at: about the screen's upright, its horizontal or the line
   * of sight. Nothing in the game changes; `endInspect` brings it back. */
  inspectTurn(axis: LookAxis, quarters: -1 | 1): void {
    this.cancelTip();
    const from = this.inspect ?? this.targetQ;
    const about = axis === 'upright' ? SCENE_UP : axis === 'across' ? SCENE_RIGHT : SCENE_TOWARD;
    const to = quarterTurned(about, quarters, from);
    this.transition(about);
    this.inspect = to;
  }

  endInspect(): void {
    if (!this.inspect) return;
    this.transition(null);
    this.inspect = null;
  }

  // ------------------------------------------------------------ the frame

  /** Advances the picture by `dt` seconds, and the game too unless `play`
   * is false (paused, hidden) or the hub is leaning over. Returns what the
   * game did, for the sounds and the readout. */
  frame(dt: number, play: boolean): CubeEvent[] {
    const { game, turn } = this;
    if (!this.labelsDrawn && document.fonts.status === 'loaded') {
      this.labelsDrawn = true;
      this.drawLabels();
    }
    this.refreshTones();
    if (play && !this.tilting) {
      this.clock += dt;
      game.update(dt);
    }
    const events = game.events.splice(0);
    for (const event of events) {
      if (event.type === 'landed') for (const { p } of event.cells) this.flashes.set(game.hub.index(p), this.clock);
    }
    if (turn.t < 1) {
      const seconds = turn.tilt ? TILT_SECONDS : this.turnSeconds;
      turn.t = seconds > 0 ? Math.min(1, turn.t + dt / seconds) : 1;
      if (turn.t >= 1 && turn.carry) this.landCarried();
    }
    this.refreshPreview();
    const goal = this.goalQ();
    if (turn.t < 1) this.turned.slerpQuaternions(this.turnFrom, goal, ease(turn.t));
    else this.turned.copy(goal);
    this.peek += ((this.peeking ? 1 : 0) - this.peek) * (1 - Math.exp(-dt * 10));
    this.peekTo.setFromEuler(new THREE.Euler(PEEK_PITCH * this.peekPitch, -PEEK_YAW * this.peekYaw, 0));
    this.peekFrom.slerp(this.peekTo, 1 - Math.exp(-dt * 8));
    const peeked = ease(this.peek);
    this.hubGroup.quaternion.slerpQuaternions(IDENTITY, this.peekFrom, peeked).multiply(this.turned);
    this.tiltFrom.slerpQuaternions(IDENTITY, this.peekFrom, peeked).multiply(this.turnFrom);
    // Depth opens while the volume is looked into and half-way through a
    // tip: the cross of the screen fades meanwhile.
    const opened = Math.max(this.peek, this.tilting ? Math.sin(Math.PI * turn.t) : 0);
    this.depthShown = FLAT + (1 - FLAT) * opened;
    const shown = (1 - opened) ** 2;
    this.crossGroup.traverse((object) => {
      const material = (object as THREE.Mesh).material as THREE.Material | undefined;
      if (material) material.opacity = (material.userData.opacity as number) * shown;
    });
    this.project(opened);
    // The edges of the hub and the glasses' numbers only when asked for:
    // with them off it looks like the flat game, and the other glasses are
    // kept in mind.
    for (const line of this.hubLines) {
      line.visible = this.look.edges;
      line.material.opacity = 0.1 + 0.25 * opened;
    }
    this.labels.forEach(({ sprite }, side) => {
      sprite.visible = this.look.numbers;
      sprite.material.opacity = side === game.active ? 0.95 : 0.4;
    });
    this.buildBlocks(dt);
    this.renderer.render(this.scene, this.camera);
    return events;
  }

  /** The picture is flat enough for marks in the corners of cells. */
  private flat(): boolean {
    return this.depthShown < FLAT + 0.01;
  }

  /** In a corner of every cell that hides another block, a small square of
   * that block's colour: what a pop there would show. Worked out once per
   * board and view. */
  private pushBehindMarks(view: CubeGame, key: string): void {
    if (!this.look.behind || !this.flat()) return;
    const cache = this.behindCache;
    if (cache.key !== key) {
      cache.key = key;
      cache.marks = [];
      for (let sx = -view.middle; sx <= view.middle; sx++) {
        for (let sy = -view.middle; sy <= view.middle; sy++) {
          const stack = view.stackAt(sx, sy);
          if (stack.length > 1) cache.marks.push({ at: this.local(stack[0]), color: view.hub.at(stack[1]) });
        }
      }
    }
    for (const { at, color } of cache.marks) this.pushSolid(at, color, { size: MARK, nudge: corner(1, -1) });
  }

  /** Falling sticks ease into their cells and turn towards their new way as
   * one body about their middle square, so that a stick turned by the
   * player or laid somewhere else by a tip turns and slides there instead of
   * jumping. While the hub leans over they turn with it like the blocks.
   * `plane` looks at the eye, in the hub's frame: a half turn spins about
   * it, flat on the screen. */
  private stickViews(pieces: Map<number, Stick>, dt: number, plane: Vec): DrawnStick[] {
    const k = this.tilting ? 0 : 1 - Math.exp(-dt * 18);
    for (const [side, view] of this.pieceViews) if (pieces.get(side)?.colors !== view.colors) this.pieceViews.delete(side);
    return [...pieces.values()].map((piece) => {
      const goal = this.local(piece.pivot);
      const dir = new THREE.Vector3(...piece.dir);
      let view = this.pieceViews.get(piece.side);
      if (!view) {
        view = {
          colors: piece.colors,
          at: goal.clone(),
          base: dir.clone(),
          dir: dir.clone(),
          aim: new THREE.Quaternion(),
          spin: new THREE.Quaternion(),
          from: null,
        };
        this.pieceViews.set(piece.side, view);
      }
      if (view.dir.distanceToSquared(dir) > 1e-6) {
        const by = new THREE.Quaternion();
        if (view.dir.dot(dir) > -0.5) by.setFromUnitVectors(view.dir, dir);
        else {
          const axis = new THREE.Vector3(...plane);
          if (Math.abs(axis.dot(dir)) > 0.5) axis.set(dir.y, dir.z, dir.x);
          by.setFromAxisAngle(axis, Math.PI);
        }
        view.aim.premultiply(by);
        view.dir.copy(dir);
      }
      if (this.carrying() && view.from && !this.staysPut(piece.side, this.turnFrom, this.goalQ())) {
        // Carried by a tip to lie some other way: it moves round with the
        // hub and at the same time turns, on the screen, from the way it lay
        // to the way it will lie — flat to the eye all along, never end on.
        const e = ease(this.turn.t);
        view.at.copy(view.from.at).lerp(goal, e);
        const end = dir.clone().applyQuaternion(this.goalQ());
        const swing = new THREE.Quaternion();
        if (view.from.dir.dot(end) > -0.99) swing.setFromUnitVectors(view.from.dir, end);
        else swing.setFromAxisAngle(SCENE_TOWARD, Math.PI);
        const onScreen = new THREE.Quaternion().slerp(swing, e).multiply(view.from.turn);
        view.spin.copy(this.turned).invert().multiply(onScreen);
      } else {
        view.at.lerp(goal, k);
        view.spin.slerp(view.aim, k);
      }
      return { piece, at: view.at, spin: view.spin, base: view.base };
    });
  }

  /** Draws sticks of `source` (the game, or a view of it) seen from the
   * side `q` turns to the eye. Those of the glasses across the screen are
   * solid; so is every stick while the hub is open (`solid`). On the flat
   * picture those of the glasses in front and behind fly along the line of
   * sight: outlines over the picture (in front) or under it (behind), and
   * only the steered one unless the setting asks for all, or the game is
   * paused. The steered one says, square by square, how it will land
   * (`marks`): filled and with a mark of its colour if it will be seen, an
   * empty outline and a dark hole if it will hide. */
  private drawSticks(source: CubeGame, q: THREE.Quaternion, sticks: DrawnStick[], { marks = true, solid = false } = {}): void {
    const open = solid || !this.flat();
    const carried = this.carrying();
    const goal = this.goalQ();
    const steeredTo = sideOfNormal(dataIn(goal, SCENE_UP));
    for (const { piece, at, spin, base } of sticks) {
      const steered = piece.side === source.active;
      // While a tip carries the sticks, those on its axis stay on the screen
      // as they were, drawn in the hub's frame from before the tip; one that
      // the flat picture shows on one side of the tip and not on the other
      // fades out (going in front of the eye or behind) or in as it turns.
      const frame = carried && this.staysPut(piece.side, this.turnFrom, goal) ? this.tiltFrom : null;
      let alpha = 1;
      if (carried) {
        const before = this.shownFlat(piece.side, this.turnFrom, this.turn.steeredFrom);
        const after = this.shownFlat(piece.side, goal, steeredTo);
        const e = ease(this.turn.t);
        if (before && !after) alpha = 1 - e;
        else if (!before && after) alpha = e;
      }
      const cell = (i: number) => at.clone().addScaledVector(base.clone().applyQuaternion(spin), i - 1);
      if (open || source.inPlane(piece.side)) {
        piece.colors.forEach((color, i) => this.pushSolid(cell(i), color, { spin, frame, alpha }));
        continue;
      }
      if (!steered && !this.look.depthSticks && !this.paused) continue;
      const lift = new THREE.Vector3(...normalOf(piece.side)).applyQuaternion(q).z * 0.6;
      const landing = steered && marks ? source.landing(piece.side) : null;
      piece.colors.forEach((color, i) => {
        const tone = this.tones[color] ?? this.tones[0];
        if (!steered) {
          this.pushClear(cell(i), tone.base, 0.8, 0.06, 0.5, { lift, spin });
          return;
        }
        const seen = landing?.seen[i] ?? true;
        this.pushClear(cell(i), tone.light, 1, seen ? 0.42 : 0, 1, { lift, spin });
        if (!landing || !this.flat()) return;
        if (seen) this.pushSolid(cell(i), color, { size: MARK, lift: 0.6, nudge: corner(-1, 1) });
        else this.pushClear(cell(i), HOLE, 1, 0.8, 1, { size: [MARK, MARK, MARK], lift: 0.6, nudge: corner(-1, 1) });
      });
    }
  }

  /** While a tip is held and the hub has turned: the board as it would
   * settle, what would pop first blinking, and the sticks in flight where
   * the tip would lay them. */
  private buildPreview(dt: number, preview: NonNullable<CubeView['preview']>, result: TurnPreview): void {
    const { view, match } = result;
    const blink = 0.2 + 0.25 * (0.5 + 0.5 * Math.sin(performance.now() / 110));
    view.hub.forEachBlock((p, color, index) => this.pushSolid(this.local(p), color, { flash: match.cells.has(index) ? blink : 0 }));
    this.drawSticks(view, preview.q, this.stickViews(view.pieces, dt, view.plane));
    this.pushBehindMarks(view, `preview:${preview.up}:${preview.version}`);
    this.flushLayers();
  }

  /** Lines the hub would show from the side it is looked at from: worked
   * out once per board and side. */
  private inspectLines(): { cells: Set<number>; runs: number } {
    const cache = this.linesCache;
    const key = `${this.game.hub.version}:${this.inspect!.toArray().join()}`;
    if (cache.key !== key) {
      const match = this.viewAt(this.inspect!).findMatches();
      Object.assign(cache, { key, cells: match.cells, runs: match.runs.length });
    }
    return cache;
  }

  /** Turned to be looked at: the blocks as seen from there, those that make
   * lines from there blinking. */
  private buildInspect(dt: number, inspect: THREE.Quaternion): void {
    const { game } = this;
    const { cells } = this.inspectLines();
    const blink = 0.2 + 0.3 * (0.5 + 0.5 * Math.sin(performance.now() / 110));
    game.hub.forEachBlock((p, color, index) => this.pushSolid(this.local(p), color, { flash: cells.has(index) ? blink : 0 }));
    // The sticks in flight turn with the hub, all of them solid: from here
    // the glasses in front and behind may well be across the screen.
    this.drawSticks(game, inspect, this.stickViews(game.pieces, dt, game.plane), { marks: false, solid: true });
    this.pushBehindMarks(this.viewAt(inspect), `inspect:${this.linesCache.key}`);
    this.flushLayers();
  }

  private buildBlocks(dt: number): void {
    const { game, preview, inspect } = this;
    if (preview?.result && this.turn.t >= 1) {
      this.buildPreview(dt, preview, preview.result);
      return;
    }
    if (inspect) {
      this.buildInspect(dt, inspect);
      return;
    }
    const hub = game.hub;
    const phase = game.phase;
    const progress = game.phaseDuration > 0 ? Math.min(1, game.phaseElapsed / game.phaseDuration) : 1;
    const matched = game.activeMatch?.cells;
    const falling = new Set<number>();
    if (phase === 'settling') for (const move of game.moves) falling.add(hub.index(move.to));

    // Every block, solid. While the picture is flat the nearest one of each
    // cell hides the others; mid-tip and while the volume is open all show.
    hub.forEachBlock((p, color, index) => {
      if (falling.has(index)) return;
      let flash = 0;
      let size = TILE;
      if (matched?.has(index)) {
        if (phase === 'matching') flash = 0.25 + 0.4 * Math.sin(progress * Math.PI);
        if (phase === 'clearing') {
          flash = 0.6;
          size = TILE * (1 - progress);
        }
      }
      const landed = this.flashes.get(index);
      if (landed !== undefined) {
        const age = this.clock - landed;
        if (age > 0.25) this.flashes.delete(index);
        else flash = Math.max(flash, 0.45 * (1 - age / 0.25));
      }
      if (size > 0.02) this.pushSolid(this.local(p), color, { flash, size });
    });
    if (phase === 'settling') {
      const t = Math.min(1, game.phaseElapsed / Math.max(0.01, game.phaseDuration - game.config.fallBounceSeconds));
      const to = new THREE.Vector3();
      for (const move of game.moves) this.pushSolid(this.local(move.from).lerp(this.local(move.to, to), t * t), move.color);
    }

    // While a tip carries them, the sticks head for where it lays them: the
    // preview's, or the game's once the tip is made.
    const heading = this.carrying() ? (preview?.result?.view.pieces ?? game.pieces) : game.pieces;
    const sticks = this.stickViews(heading, dt, game.plane);
    if (phase === 'dropping' && game.drop) {
      const { piece, from } = game.drop;
      // Seen as it lies in its glass, not turned to a view: its view is gone.
      sticks.push({
        piece,
        at: this.local(from).lerp(this.local(piece.pivot), progress * progress),
        spin: new THREE.Quaternion(),
        base: new THREE.Vector3(...piece.dir),
      });
    }
    this.drawSticks(game, this.targetQ, sticks);

    // Where the stick on top will land, and the lane down to it. A stick in
    // front or behind lands in the cells it is over, and says so itself.
    const piece = game.activePiece;
    if (piece && game.inPlane(piece.side) && !game.isGameOver) {
      const ghost = game.ghost();
      const cells = pieceCells(piece);
      if (ghost && !ghost.every(({ p }, i) => p.every((v, j) => v === cells[i].p[j]))) {
        for (const { p, color } of ghost) this.pushClear(this.local(p), (this.tones[color] ?? this.tones[0]).light, 1, 0.16, 1);
        if (this.look.lane) this.pushLanes(piece, ghost);
      }
    }
    this.pushBehindMarks(game, `game:${hub.version}:${this.targetQ.toArray().join()}`);
    this.flushLayers();
  }

  /** A faint column under each lane of the stick, down to the landing spot —
   * the flat game's aiming lane. */
  private pushLanes(piece: Stick, ghost: StickCell[]): void {
    const n = normalOf(piece.side);
    const { axis } = SIDES[piece.side];
    const lanes = new Map<string, { p: Vec; height: number; ghost: Vec }>();
    pieceCells(piece).forEach(({ p }, i) => {
      const key = p.filter((_, j) => j !== axis).join();
      const low = lanes.get(key);
      const height = dot(p, n);
      if (!low || height < low.height) lanes.set(key, { p, height, ghost: ghost[i].p });
    });
    const normal = new THREE.Vector3(...n);
    for (const lane of lanes.values()) {
      const top = this.local(lane.p).addScaledVector(normal, -0.5);
      const bottom = this.local(lane.ghost).addScaledVector(normal, 0.5);
      const length = top.distanceTo(bottom);
      if (length < 0.05) continue;
      const size: [number, number, number] = [0.91, 0.91, 0.91];
      size[axis] = length;
      this.pushClear(top.add(bottom).multiplyScalar(0.5), WHITE, 1, 0.07, 0, { size });
    }
  }
}
