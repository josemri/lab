# snake

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![C](https://img.shields.io/badge/C-C99-blue.svg)](https://en.wikipedia.org/wiki/C99)

A classic Snake game that runs entirely in the terminal using ANSI escape codes. Multiple apples can spawn at once, and the snake grows with each one eaten. Collision with walls or yourself ends the game.

## features

- **Terminal-native rendering** — Uses ANSI escape sequences, no external libraries
- **Multiple apples** — Up to 10 apples can appear on the map simultaneously
- **Configurable map size** — Set dimensions via command line arguments (10–100)

## usage

```bash
gcc main.c draw.c input.c -o snake
./snake <map_width> <map_height>
```

Controls: `WASD` to move, `Q` to quit.

## project structure

```
snake/
├── main.c     # Game loop, logic, and entry point
├── draw.c     # Terminal rendering via ANSI codes
├── draw.h     # Rendering interface
├── input.c    # Raw terminal input handling
└── input.h    # Input interface
```

## license

[![GNU GPLv3](https://www.gnu.org/graphics/gplv3-127x51.png)](https://www.gnu.org/licenses/gpl-3.0.en.html)

**snake** is Free Software under the [GNU General Public License v3](https://www.gnu.org/licenses/gpl-3.0.en.html).

---

<div align="center">
  <b>Made with 🐍 by <a href="https://github.com/josemri">josemri</a></b>
</div>
