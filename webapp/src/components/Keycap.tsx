import { T } from '../i18n/Text';
import { keyLabel } from '../input/bindings';

/** A key drawn as a keycap. */
export function Keycap({ code }: { code: string }) {
  return <kbd className="keycap"><T>{keyLabel(code)}</T></kbd>;
}

/** The keys of one action, or a dash when it has none. */
export function Keys({ codes }: { codes: readonly string[] }) {
  if (codes.length === 0) return <span className="keys keys--none"><T>—</T></span>;
  return (
    <span className="keys">
      {codes.map((code) => (
        <Keycap key={code} code={code} />
      ))}
    </span>
  );
}
