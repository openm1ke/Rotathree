/** A message over the field: a level finished, a new stage, a new glass. */
export interface BannerData {
  id: number;
  kicker: string;
  title: string;
  sub?: string;
  /** Colours of the stage, shown as dots. */
  colours?: string[];
  /** How long it stays, in seconds. */
  seconds: number;
}

export function LevelBanner({ banner }: { banner: BannerData }) {
  return (
    <div className="banner" key={banner.id} role="status" style={{ ['--life' as string]: `${banner.seconds}s` }}>
      <div className="banner__sweep" />
      <div className="banner__card">
        <span className="banner__kicker">{banner.kicker}</span>
        <span className="banner__title">{banner.title}</span>
        {banner.sub && <span className="banner__sub">{banner.sub}</span>}
        {banner.colours && (
          <span className="banner__dots">
            {banner.colours.map((colour, i) => (
              <i key={i} style={{ background: colour }} />
            ))}
          </span>
        )}
      </div>
    </div>
  );
}
