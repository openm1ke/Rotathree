import { useI18n } from '../i18n/context';
import { T } from '../i18n/Text';
import { useRef } from 'react';
import { MODE_NAMES, type ModeId } from '../game/modes';
import type { ModeStats, Progress, RunRecord, Stats } from '../services/storage';
import { Screen } from './ui';
import { useScreenKeys } from './nav';
import { formatDuration, formatNumber } from './format';

interface Props {
  stats: Stats;
  progress: Progress;
  onBack: () => void;
  active: boolean;
}

const MODES: ModeId[] = ['campaign', 'insane', 'custom'];

const DESCRIPTIONS: Record<ModeId, string> = {
  campaign: 'Пятнадцать уровней, каждый со своей целью очков',
  insane: 'Шесть цветов, четыре стакана, скорость растёт',
  custom: 'Своя настройка, скорость — по желанию',
};

/** Totals and records of every mode, and the last runs. */
export function StatisticsScreen({ stats, progress, onBack, active }: Props) {
  const { language } = useI18n();
  const rootRef = useRef<HTMLElement>(null);
  useScreenKeys(rootRef, active, onBack);
  return (
    <Screen rootRef={rootRef} kicker="Результаты" title="Статистика" onBack={onBack}>
      <div className="stat-grid">
        {MODES.map((mode) => (
          <ModeCard key={mode} mode={mode} stats={stats.modes[mode]} progress={progress} />
        ))}
      </div>

      <section className="runs">
        <h2><T>Последние партии</T></h2>
        {stats.recent.length === 0 ? (
          <p className="empty"><T>Пока ни одной партии. Первая появится здесь после конца игры.</T></p>
        ) : (
          <table>
            <thead>
              <tr>
                <th><T>Когда</T></th>
                <th><T>Режим</T></th>
                <th><T>Итог</T></th>
                <th><T>Очки</T></th>
                <th><T>Фигуры</T></th>
                <th><T>Комбо</T></th>
                <th><T>Время</T></th>
              </tr>
            </thead>
            <tbody>
              {stats.recent.map((run) => (
                <tr key={run.id}>
                  <td><T>
                    {new Date(run.at).toLocaleString(language === 'ru' ? 'ru-RU' : 'en-US', {
                      day: '2-digit',
                      month: '2-digit',
                      hour: '2-digit',
                      minute: '2-digit',
                    })}
                  </T></td>
                  <td><T>{MODE_NAMES[run.mode]}</T></td>
                  <td><T>{outcome(run)}</T></td>
                  <td><T>{formatNumber(run.score)}</T></td>
                  <td><T>{run.pieces}</T></td>
                  <td><T>×{run.bestCombo}</T></td>
                  <td><T>{formatDuration(run.seconds)}</T></td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </section>
    </Screen>
  );
}

function outcome(run: RunRecord): string {
  if (run.interrupted) return 'партия прервана';
  if (run.mode === 'campaign') return run.completed ? 'кампания пройдена' : `уровень ${run.level}`;
  return `скорость ${run.level}`;
}

function ModeCard({ mode, stats, progress }: { mode: ModeId; stats: ModeStats; progress: Progress }) {
  const average = stats.games > 0 ? Math.round(stats.totalPieces / stats.games) : 0;
  return (
    <section className="mode-card">
      <header>
        <span className="kicker"><T>
          {mode === 'campaign' ? `${progress.completed ? 'пройдена' : `уровень ${progress.unlocked + 1}`}` : 'режим'}
        </T></span>
        <h2><T>{MODE_NAMES[mode]}</T></h2>
        <p><T>{DESCRIPTIONS[mode]}</T></p>
      </header>
      <dl>
        <Line label="Партий" value={String(stats.games)} />
        {mode === 'campaign' && (
          <Line label="Кампания пройдена" value={stats.completed > 0 ? `${stats.completed} раз` : 'нет'} />
        )}
        <Line label="Лучший счёт" value={formatNumber(stats.bestScore)} main />
        <Line label="Очков всего" value={formatNumber(stats.totalScore)} />
        <Line label="Фигур всего" value={formatNumber(stats.totalPieces)} />
        <Line label="Фигур за партию" value={String(average)} />
        <Line label="Матчей всего" value={formatNumber(stats.totalMatches)} />
        <Line label="Лучшее комбо" value={`×${stats.bestCombo}`} />
        <Line
          label={mode === 'campaign' ? 'Лучший уровень' : 'Лучшая скорость'}
          value={mode === 'campaign' ? String(stats.bestLevel) : `×${stats.bestLevel}`}
        />
        <Line label="Время в играх" value={formatDuration(stats.totalSeconds)} />
      </dl>
    </section>
  );
}

function Line({ label, value, main }: { label: string; value: string; main?: boolean }) {
  return (
    <div className={`line ${main ? 'line--main' : ''}`}>
      <dt><T>{label}</T></dt>
      <dd><T>{value}</T></dd>
    </div>
  );
}
