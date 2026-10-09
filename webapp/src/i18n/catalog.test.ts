import { describe, expect, it } from 'vitest';
import english from '../../../assets/i18n/en.json';
import { languageChoice, resolveLanguage, translate } from './catalog';
import { defaultSettings, sanitizeSettings } from '../services/storage';

describe('language selection', () => {
  it('detects preferred locales and falls back to English', () => {
    expect(resolveLanguage('auto', ['ru-RU'])).toBe('ru');
    expect(resolveLanguage('auto', ['en-GB', 'ru-RU'])).toBe('en');
    expect(resolveLanguage('auto', ['fr-FR', 'ru-RU'])).toBe('ru');
    expect(resolveLanguage('auto', ['RU_ru'])).toBe('ru');
    expect(resolveLanguage('auto', ['ja-JP'])).toBe('en');
    expect(resolveLanguage('auto', [])).toBe('en');
    expect(resolveLanguage('ru', ['en-US'])).toBe('ru');
    expect(resolveLanguage('en', ['ru-RU'])).toBe('en');
  });
  it('persists manual choices without disturbing existing settings', () => {
    for (const language of ['auto', 'ru', 'en'] as const) {
      const settings = { ...defaultSettings(), language, handling: { dasMs: 210, arrMs: 20 } };
      expect(sanitizeSettings(JSON.parse(JSON.stringify(settings)))).toEqual(settings);
    }
    expect(sanitizeSettings({ handling: { dasMs: 210 } }).language).toBe('auto');
    expect(sanitizeSettings({ language: 'de' }).language).toBe('auto');
    expect(languageChoice(null)).toBe('auto');
  });
});

describe('shared translation catalog', () => {
  it('preserves parameters and Russian source messages', () => {
    const params = (text: string) => new Set([...text.matchAll(/\{\w+\}/g)].map((m) => m[0]));
    for (const [source, target] of Object.entries(english)) {
      expect(params(target), source).toEqual(params(source));
      expect(translate(source, 'ru'), source).toBe(source);
      if (!source.includes('{')) expect(translate(source, 'en'), source).toBe(target);
      expect(translate(source.replace(/\{\w+\}/g, '42'), 'en'), source).toBe(target.replace(/\{\w+\}/g, '42'));
    }
  });
  it('translates dynamic UI and Russian messages restored from older saves', () => {
    const t = (source: string) => translate(source, 'en');
    expect(t('Уровень 7 пройден')).toBe('Level 7 complete');
    expect(t('УРОВЕНЬ 7 ПРОЙДЕН')).toBe('LEVEL 7 COMPLETE');
    expect(t('Дальше: 6 цв. · 4 ст. · цель 12 000')).toBe('Next: colors 6 · glasses 4 · target 12,000');
    expect(t('4 ст. · 1,2 с/шаг')).toBe('Glasses 4 · 1.2s/step');
    expect(t('150 мс')).toBe('150 ms');
    expect(t('Левая: → · Правая: ↻')).toBe('Left: → · Right: ↻');
    expect(t('Кампания · уровень 3')).toBe('Campaign · level 3');
    expect(t('  движение ')).toBe('  move ');
  });
});
