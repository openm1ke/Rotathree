import { useI18n } from '../i18n/context';
import { T } from '../i18n/Text';
import { formatScore } from './hudState';

interface Props {
  level: number;
  into: number;
  target: number;
  animated: boolean;
  compact?: boolean;
}

/** A score-keyed pulse finishes once; an idle bar does no animation work. */
export function CampaignProgress({ level, into, target, animated, compact = false }: Props) {
  const { t } = useI18n();
  if (target <= 0) return null;
  const earned = Math.max(0, into);
  const remaining = Math.max(0, target - earned);
  const fraction = Math.min(1, earned / target);
  return <div
    className={`campaign-progress ${compact ? 'campaign-progress--compact' : ''}`}
    role="progressbar"
    aria-label={t(`Прогресс уровня ${level}`)}
    aria-valuemin={0}
    aria-valuemax={target}
    aria-valuenow={Math.min(target, earned)}
    aria-valuetext={t(`${formatScore(earned)} / ${formatScore(target)}. Ещё ${formatScore(remaining)}.`)}
    data-animated={animated}
  >
    <div className="campaign-progress__track">
      <div className="campaign-progress__fill" style={{ width: `${fraction * 100}%` }} />
      {earned > 0 && <div className="campaign-progress__pulse" key={`${level}:${earned}`} />}
    </div>
    <div className="campaign-progress__text" aria-hidden="true">
      <strong><T>{formatScore(earned)} / {formatScore(target)}</T></strong>
    </div>
  </div>;
}
