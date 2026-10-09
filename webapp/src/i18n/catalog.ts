import english from '../../../assets/i18n/en.json';

export type Language = 'ru' | 'en';
export type LanguageChoice = 'auto' | Language;
export const languageChoice = (value: unknown): LanguageChoice =>
  value === 'ru' || value === 'en' ? value : 'auto';

export function resolveLanguage(choice: LanguageChoice, preferred: readonly string[]): Language {
  if (choice !== 'auto') return choice;
  for (const locale of preferred) {
    const code = locale.toLowerCase().split(/[-_]/)[0];
    if (code === 'ru' || code === 'en') return code;
  }
  return 'en';
}

const catalog: Record<string, string> = english;
const parameter = /\{(\w+)\}/g;
const escape = (text: string) => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const templates = Object.entries(catalog)
  .filter(([source]) => source.includes('{'))
  .map(([source, translation]) => {
    const parameters: string[] = [];
    let expression = '^', end = 0;
    for (const match of source.matchAll(parameter)) {
      expression += escape(source.slice(end, match.index)) + '(.+?)';
      parameters.push(match[1]);
      end = match.index + match[0].length;
    }
    expression += escape(source.slice(end)) + '$';
    return {
      pattern: new RegExp(expression),
      upperPattern: new RegExp(expression, 'i'),
      parameters,
      translation,
      specificity: source.replace(parameter, '').length,
    };
  })
  .sort((a, b) => b.specificity - a.specificity);

const numbers = (value: string) => value
  .replace(/(\d)[\u00a0\u202f](?=\d{3}(?:\D|$))/g, '$1,')
  .replace(/(\d),(\d{1,2})(?=\D|$)/g, '$1.$2');

/** Translate only presentation, including Russian banners from older saves. */
export function translate(source: string, language: Language, depth = 0): string {
  if (language === 'ru' || depth > 4 || !source) return source;
  const normalized = source.trim().replace(/[\t\r\n ]+/g, ' ');
  const upper = /[А-ЯЁ]/.test(normalized) && normalized === normalized.toUpperCase();
  const key = upper
    ? Object.keys(catalog).find((key) => key.toUpperCase() === normalized) ?? normalized
    : normalized;
  let result: string | undefined = catalog[key];
  if (result === undefined) {
    for (const template of templates) {
      const match = normalized.match(upper ? template.upperPattern : template.pattern);
      if (!match) continue;
      result = template.translation.replace(parameter, (_, name: string) =>
        translate(match[template.parameters.indexOf(name) + 1], language, depth + 1),
      );
      break;
    }
  }
  if (result === undefined) return numbers(source);
  if (upper) result = result.toUpperCase();
  return source.match(/^\s*/)![0] + numbers(result) + source.match(/\s*$/)![0];
}
