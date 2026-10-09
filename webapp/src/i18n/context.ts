import { createContext, useContext, useEffect, useMemo, useState } from 'react';
import { resolveLanguage, translate, type Language, type LanguageChoice } from './catalog';

export interface I18n {
  language: Language;
  t: (source: string) => string;
}

export const I18nContext = createContext<I18n>({ language: 'ru', t: (source) => source });
export const useI18n = () => useContext(I18nContext);

export function useLanguage(choice: LanguageChoice): I18n {
  const [preferred, setPreferred] = useState(() => [...navigator.languages]);
  useEffect(() => {
    const update = () => setPreferred([...navigator.languages]);
    window.addEventListener('languagechange', update);
    return () => window.removeEventListener('languagechange', update);
  }, []);
  const language = resolveLanguage(choice, preferred);
  useEffect(() => {
    document.documentElement.lang = language;
  }, [language]);
  return useMemo(() => ({ language, t: (source: string) => translate(source, language) }), [language]);
}
