import { Children, Fragment, type ReactNode } from 'react';
import { useI18n } from './context';

/** No extra DOM. Join text fragments before translating formatted messages. */
export function T({ children, translate = true }: { children: ReactNode; translate?: boolean }) {
  const { t } = useI18n();
  if (!translate) return <>{children}</>;
  const pieces: ReactNode[] = [];
  let text = '';
  const flush = () => {
    if (text) pieces.push(t(text));
    text = '';
  };
  Children.forEach(children, (child) => {
    if (typeof child === 'string' || typeof child === 'number') text += child;
    else if (child != null && child !== false) {
      flush();
      pieces.push(child);
    }
  });
  flush();
  return <>{pieces.map((piece, i) => <Fragment key={i}>{piece}</Fragment>)}</>;
}
