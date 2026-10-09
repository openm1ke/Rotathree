import type { LanguageChoice } from './catalog';
import { T } from './Text';

function Flag({ language }: { language: 'ru' | 'en' }) {
  return <svg viewBox="0 0 32 24" width="32" height="24" aria-hidden="true" className="language-flag">
    {language === 'ru' ? <>
      <path fill="#fff" d="M0 0h32v8H0z" />
      <path fill="#2256b4" d="M0 8h32v8H0z" />
      <path fill="#d83947" d="M0 16h32v8H0z" />
    </> : <>
      <path fill="#173674" d="M0 0h32v24H0z" />
      <path stroke="#fff" strokeWidth="6" d="m0 0 32 24M32 0 0 24" />
      <path stroke="#d83947" strokeWidth="2" d="m0 0 32 24M32 0 0 24" />
      <path stroke="#fff" strokeWidth="9" d="M16 0v24M0 12h32" />
      <path stroke="#d83947" strokeWidth="5" d="M16 0v24M0 12h32" />
    </>}
  </svg>;
}

export function LanguagePicker({ value, onChange }: { value: LanguageChoice; onChange: (value: LanguageChoice) => void }) {
  return <section className="group">
    <h3><T>Язык</T></h3>
    <div className="language-options">
      {(['auto', 'ru', 'en'] as const).map((choice) => <button
        key={choice} type="button" data-nav data-language={choice}
        className={`language-option ${choice === value ? 'is-active' : ''}`}
        aria-pressed={choice === value} onClick={() => onChange(choice)}>
        {choice === 'auto'
          ? <svg viewBox="0 0 24 24" width="24" height="24" aria-hidden="true" fill="none" stroke="currentColor" strokeWidth="1.5">
              <circle cx="12" cy="12" r="10" /><ellipse cx="12" cy="12" rx="4" ry="10" /><path d="M2 12h20M4 6h16M4 18h16" />
            </svg>
          : <Flag language={choice} />}
        <span>{choice === 'auto' ? <T>Авто</T> : choice === 'ru' ? 'Русский' : 'English'}</span>
      </button>)}
    </div>
    <p className="hint"><T>Авто — по языку браузера</T></p>
  </section>;
}
