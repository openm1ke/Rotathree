import type { CubeOptions } from '../services/storage';
import { Toggle } from './ui';

type Look = 'nextPiece' | 'grid' | 'volumeEdges' | 'depthHint' | 'xray' | 'behind' | 'lane' | 'depthSticks' | 'edges' | 'numbers';

/** What Cube's picture shows besides the game, each one a switch. */
const CUBE_LOOK: readonly (readonly [Look, string])[] = [
  ['nextPiece', 'Следующие фигуры над стаканами'],
  ['grid', 'Сетка клеток в стаканах'],
  ['volumeEdges', 'Рёбра стаканов в объёме (3D-сетка)'],
  ['depthHint', 'Линии объёма вокруг стаканов'],
  ['xray', 'Спрятанные фигуры сквозь блоки в объёме'],
  ['behind', 'Спрятанные блоки: метка цвета за клеткой'],
  ['lane', 'Дорожка до места посадки'],
  ['depthSticks', 'Фигуры спереди и сзади, которыми не управляете'],
  ['edges', 'Рёбра стаканов и во время игры'],
  ['numbers', 'Номера стаканов'],
];

/** The switches of Cube's look, the same on its own screen and in the
 * settings. */
export function CubeLookToggles({ cube, onChange }: { cube: CubeOptions; onChange: (cube: CubeOptions) => void }) {
  return (
    <>
      {CUBE_LOOK.map(([key, label]) => (
        <Toggle
          key={key}
          label={label}
          value={cube[key]}
          on="показывать"
          off="скрыть"
          onChange={(value) => onChange({ ...cube, [key]: value })}
        />
      ))}
    </>
  );
}
