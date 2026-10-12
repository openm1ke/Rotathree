# Effects and performance

## Implemented

- `effects.fieldBackground`: stops both the glass motifs and the game-screen background animation; static gradients and grids remain. Menu animation remains independent.
- `effects.explosion = off`: creates no burst shards, rings, flashes, confetti or drop sparks. Existing bursts are cleared immediately. Matched cells disappear without swelling/flashing; engine phases, scores and movement keep their original timing.
- Missing settings keep the previous defaults, so existing saves migrate without changing the user's preferences. Both choices persist in native/browser storage and VK backups.
- Native bursts are bounded to 1500 live particles, matching the existing browser budget. New particles beyond that budget are skipped before allocation.
- Native game tickers stop while the app is inactive and restart without simulating the time spent in the background. Game/menu backgrounds freeze under pause/dialogs.
- At zero shake, both implementations avoid generating random jitter every frame.

The browser already caches sprites/glows and lowers field pixel resolution when a measured frame window is too slow (`webapp/src/render/quality.ts`). Native repaint notifications and browser canvas drawing already skip frozen pictures. Disabling decorative effects reduces actual work, rather than only hiding it.

## Next experiments, after measuring on weaker hardware

1. Profile a release/profile build with four glasses and a large simultaneous clear. Compare frame/raster time and allocation peaks with both new settings on/off. Debug builds do not establish release FPS.
2. Consider an optional economy preset: backgrounds/bursts/shake off, an explicit render-resolution cap for browsers, and a lower particle budget when effects remain enabled. Keep logical geometry and hit testing consistent.
3. Test caching the static field grid as a picture/offscreen image, invalidated by size, glass growth, palette and camera geometry. Separate static and moving layers only if profiling shows a benefit; rotating the cross can make cache/compositor costs outweigh savings.
4. Profile paused/hidden screens and consider suspending the remaining browser frame loop entirely with explicit wake-up on visibility, input and settings changes.

No percentage/FPS improvement is claimed without a target-device measurement.

References: [MDN canvas optimization](https://developer.mozilla.org/en-US/docs/Web/API/Canvas_API/Tutorial/Optimizing_canvas), [Flutter performance best practices](https://docs.flutter.dev/perf/best-practices), [Flutter performance profiling](https://docs.flutter.dev/perf/ui-performance).
