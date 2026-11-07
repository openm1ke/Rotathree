import { useEffect, useRef } from 'react';
import { drawBlockRow } from '../render/blockLook';
import { toneOf, type BlockSkin } from '../render/theme';

/** A row of blocks of `colours` in `skin`, drawn as the field draws them:
 * for the settings to show a look before it is chosen, and for banners. */
export function BlockRow({ skin, colours, unit = 30 }: { skin: BlockSkin; colours: readonly string[]; unit?: number }) {
  const ref = useRef<HTMLCanvasElement>(null);
  const key = colours.join(',');
  useEffect(() => {
    if (ref.current) drawBlockRow(ref.current, skin, key.split(',').map(toneOf), unit);
  }, [skin, key, unit]);
  return <canvas ref={ref} className="block-row" aria-hidden="true" />;
}
