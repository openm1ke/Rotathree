let locale: string | undefined;

/** The language the hosting platform reports, or undefined outside one. When
 * set it decides the automatic language on its own: an unsupported one falls
 * back to English rather than to the browser's. */
export const platformLocale = () => locale;

export function setPlatformLocale(value: string | undefined): void {
  locale = value || undefined;
}
