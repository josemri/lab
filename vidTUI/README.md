<img  width="300" align="left" src="https://github.com/user-attachments/assets/62728998-aed2-42e9-b123-284407d17187" />

**vidTUI**

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Rust](https://img.shields.io/badge/Rust-2021+-orange.svg)](https://www.rust-lang.org)

A terminal user interface for browsing movies from TMDB and playing them via a headless Firefox instance. Posters are rendered as ANSI half-block art, and video playback is streamed to the terminal with a minimal progress bar overlay.
<br clear="both"/>

## features

- **TMDB search** — Browse movies by title with paginated results
- **ANSI poster rendering** — Fetches and displays posters as terminal art using half-block characters
- **Carousel UI** — Navigate results with poster previews on the sides
- **Headless playback** — Plays movies in headless Firefox with canvas-based frame capture
- **Playback controls** — Play/pause, seek forward/backward, progress bar with time display

## usage

```bash
# Set your TMDB API key in src/tmdb.rs first
cargo run --release
```

Requires Firefox to be installed. Geckodriver is auto-downloaded on first run.

Controls: Type to search, `Enter` to select, `P` to play, `Space` to pause, arrow keys to navigate/seek, `Q` or `Esc` to go back or quit.

## project structure

```
vidTUI/
├── Cargo.toml
└── src/
    ├── main.rs   # Entry point, event loop, download scheduling
    ├── tmdb.rs   # TMDB API client and poster image loading
    ├── ui.rs     # Ratatui widgets: search bar, carousel, overlays
    └── video.rs  # Headless Firefox playback, canvas capture, progress UI
```

## credits

[TMDB](https://www.themoviedb.org/) — Movie metadata and poster images

## license

[![GNU GPLv3](https://www.gnu.org/graphics/gplv3-127x51.png)](https://www.gnu.org/licenses/gpl-3.0.en.html)

**vidTUI** is Free Software under the [GNU General Public License v3](https://www.gnu.org/licenses/gpl-3.0.en.html).

---

<div align="center">
  <b>Made with 🎬 by <a href="https://github.com/josemri">josemri</a></b>
</div>
