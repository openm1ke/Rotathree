import music from '../../../assets/credits/music.json';
import { T } from '../i18n/Text';

export function LicensesTab() {
  return <>
    <section className="group">
      <h3><T>Музыка</T></h3>
      <p className="hint"><T>Спасибо авторам, чья музыка звучит в RotaThree.</T></p>
      <div className="license-list">
        {music.map((track) => <article className="license-card" key={track.id}>
          <strong>{track.title}</strong>
          <p>{track.author ?? <T>Автор уточняется</T>} · {track.license ?? <T>Условия использования уточняются</T>}</p>
          {track.source && <a href={track.source} target="_blank" rel="noopener noreferrer"><T>Источник</T> ↗</a>}
        </article>)}
      </div>
      <p className="hint"><T>Громкость треков выровнена, добавлены затухания в начале и конце.</T></p>
      <a href="https://creativecommons.org/publicdomain/zero/1.0/" target="_blank" rel="noopener noreferrer">CC0 1.0 ↗</a>
    </section>
    <section className="group">
      <h3><T>Библиотеки и шрифт</T></h3>
      <div className="license-list">
        <article className="license-card"><strong>React / React DOM</strong><p>Meta Platforms, Inc. and affiliates · MIT</p><a href="./licenses/React-MIT.txt" target="_blank" rel="noopener noreferrer">React — MIT ↗</a>{' · '}<a href="./licenses/ReactDOM-MIT.txt" target="_blank" rel="noopener noreferrer">React DOM — MIT ↗</a></article>
        <article className="license-card"><strong>Exo 2</strong><p>The Exo 2 Project Authors · SIL OFL 1.1</p><a href="./licenses/Exo2-OFL.txt" target="_blank" rel="noopener noreferrer">SIL OFL 1.1 ↗</a></article>
      </div>
    </section>
    <section className="group">
      <h3><T>Автор</T></h3>
      <div className="license-list">
        <article className="license-card"><strong>Mikhail Shmyrev</strong><p><a href="mailto:muxaujish@yandex.ru">muxaujish@yandex.ru</a></p></article>
      </div>
    </section>
  </>;
}
