# Rotathree logo

`logo.svg` is the shared production source: nine colored squares, an almost-black
cool background and a faint grid aligned to the squares. `approved-concept.png`
preserves the owner's selected concept; `asset-manifest.json` records provenance.
`logo.png` is the full-bleed 1024 px export.

Regenerate all platform assets from the repository root:

```sh
brew install librsvg # once, on macOS
python3 tool/generate_icons.py
```

No image-generation service or Python image package is needed to export the icons.
The script writes the existing iOS AppIcon slots as opaque RGB PNGs, Android legacy
density icons and adaptive vectors, and browser favicons/home-screen icons.
Android has separate background, color and monochrome layers; the mark stays
within the 66 dp safe circle. iOS supplies its own outer mask. Browser favicons and
legacy Android icons have rounded corners; maskable web icons include safe padding.
The web manifest describes home-screen icons; it does not add offline support.
