#!/usr/bin/env python3
"""Export VK upload icons at the exact sizes provided by the owner.

Requires librsvg (rsvg-convert) and Pillow. Does not alter app launcher assets.
"""
import hashlib
import json
from pathlib import Path
import shutil
import zipfile

from PIL import Image
from generate_icons import render, svg_variant

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'build/releases/vk/design'
SLOTS = [('universal', 576), ('catalog', 278), ('small', 150)]


def main():
    if not shutil.which('rsvg-convert'):
        raise SystemExit('Install librsvg first: brew install librsvg')
    OUTPUT.mkdir(parents=True, exist_ok=True)
    files = []
    art = svg_variant()
    for slot, size in SLOTS:
        png = OUTPUT / 'icons' / f'icon-{slot}-{size}.png'
        render(art, png, size, opaque=True)
        with Image.open(png) as original:
            image = original.convert('RGB')
        # Strip metadata and keep an opaque, non-interlaced RGB PNG.
        image.save(png, optimize=True)
        jpg = png.with_suffix('.jpg')
        image.save(jpg, quality=92, subsampling=0, optimize=True, progressive=False)
        for path, expected_format in [(png, 'PNG'), (jpg, 'JPEG')]:
            with Image.open(path) as check:
                assert check.size == (size, size)
                assert check.mode == 'RGB' and check.format == expected_format
                check.verify()
            files.append(path)

    # VK accepts JPG/PNG/GIF at exactly 32 px, up to 50 KB.
    for old_name in ['favicon-16.png', 'favicon-48.png', 'favicon.ico']:
        (OUTPUT / 'favicon' / old_name).unlink(missing_ok=True)
    favicon = OUTPUT / 'favicon/favicon-32.png'
    render(art, favicon, 32, opaque=True)
    with Image.open(favicon) as source:
        image = source.convert('RGB')
    image.save(favicon, optimize=True)
    image.save(favicon.with_suffix('.jpg'), quality=95, subsampling=0, optimize=True, progressive=False)
    image.quantize(colors=256).save(favicon.with_suffix('.gif'))
    for suffix, format_name in [('.png', 'PNG'), ('.jpg', 'JPEG'), ('.gif', 'GIF')]:
        path = favicon.with_suffix(suffix)
        with Image.open(path) as check:
            assert check.format == format_name and check.size == (32, 32)
            assert not getattr(check, 'is_animated', False)
            check.verify()
        assert path.stat().st_size <= 50000
        files.append(path)

    # Capture the running production game at these viewports via Playwright;
    # export only when every source has exactly the required dimensions.
    captures = [
        ('vk-01-menu-1200x600.png', 'screenshots/01-main-menu-1200x600.jpg', (1200, 600)),
        ('vk-02-campaign-1200x600.png', 'screenshots/02-campaign-1200x600.jpg', (1200, 600)),
        ('vk-03-gameplay-1200x600.png', 'screenshots/03-gameplay-1200x600.jpg', (1200, 600)),
        ('vk-snippet-1120x630.png', 'images/big-snippet-1120x630.jpg', (1120, 630)),
    ]
    capture_root = ROOT / 'output/playwright'
    present = [(capture_root / source).is_file() for source, _, _ in captures]
    if any(present) and not all(present):
        raise SystemExit('Capture all three screenshots and the large snippet before packaging.')
    if all(present):
        for source, target, dimensions in captures:
            with Image.open(capture_root / source) as screenshot:
                assert screenshot.size == dimensions, f'Wrong screenshot size: {source}'
                path = OUTPUT / target
                path.parent.mkdir(parents=True, exist_ok=True)
                screenshot.convert('RGB').save(path, quality=92, subsampling=0, optimize=True, progressive=False)
            with Image.open(path) as check:
                assert check.size == dimensions and check.format == 'JPEG'
                check.verify()
            files.append(path)

    report = []
    for path in files:
        with Image.open(path) as image:
            report.append({
                'file': path.relative_to(OUTPUT).as_posix(),
                'width': image.width, 'height': image.height,
                'format': image.format, 'bytes': path.stat().st_size,
                'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            })
    manifest = OUTPUT / 'manifest.json'
    manifest.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    readme = OUTPUT / 'README.txt'
    readme.write_text('''Файлы для вкладки «Оформление» VK

Универсальная иконка: icons/icon-universal-576.png — ровно 576 × 576 px.
Иконка каталога и сниппетов: icons/icon-catalog-278.png — ровно 278 × 278 px.
Маленькая иконка: icons/icon-small-150.png — ровно 150 × 150 px.

Начните с PNG. Рядом есть JPG тех же размеров как альтернативный формат.
Все три иконки непрозрачные RGB, с утверждённым тёмно-синим фоном и сеткой.
Ограничение веса файлов в предоставленной форме не указано; вес есть в manifest.json.

Фавикон: favicon/favicon-32.png — ровно 32 × 32 px, PNG, меньше 50 КБ.
При ошибке PNG попробуйте favicon/favicon-32.jpg, затем favicon/favicon-32.gif.
Все варианты статичные, 32 × 32 px, меньше 50 КБ, без необязательных метаданных.
Сообщение VK «Невозможно установить значение» не указывает причину сбоя.

Большой сниппет: images/big-snippet-1120x630.jpg — ровно 1120 × 630 px.
Скриншоты: screenshots/*.jpg — ровно 1200 × 600 px, альбомная ориентация.
Сняты с работающей production-сборки игры на локальном стенде VK Bridge.
Панель стенда в кадры не входит. Это не проверка запуска на реальной платформе VK.
Если изображения ещё не сняты, их файлов в архиве нет.

Видео и экран запуска не подготовлены: их требования в форме не предоставлены.
''')
    archive_path = OUTPUT.parent / 'Rotathree-vk-design.zip'
    with zipfile.ZipFile(archive_path, 'w', zipfile.ZIP_DEFLATED) as archive:
        for path in files + [manifest, readme]:
            archive.write(path, path.relative_to(OUTPUT))
        assert archive.testzip() is None
    print(json.dumps({'archive': str(archive_path), 'files': report}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
