import type { Language } from '../i18n/catalog';

const NAMES: Record<Language, string> = { ru: 'Русский', en: 'English' };

/**
 * A globe on the main menu that switches to the other language, named in that
 * language. Playgama asks for the language choice to be reachable by someone
 * who cannot read the current one; the full picker stays in the settings.
 */
export function LanguageSwitch({ language, onChange }: { language: Language; onChange: (language: Language) => void }) {
  const next: Language = language === 'ru' ? 'en' : 'ru';
  return (
    <button type="button" className="language-switch" lang={next} onClick={() => onChange(next)}>
      <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" fill="none" stroke="currentColor" strokeWidth="1.5">
        <circle cx="12" cy="12" r="10" />
        <ellipse cx="12" cy="12" rx="4" ry="10" />
        <path d="M2 12h20M4 6h16M4 18h16" />
      </svg>
      <span>{NAMES[next]}</span>
    </button>
  );
}
