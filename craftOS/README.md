<img align="left" width="200" src="https://github.com/user-attachments/assets/cf3a2b1f-3cf3-4acc-99da-fdd5a1967cb1" />

**craftOS**

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Lua](https://img.shields.io/badge/Lua-5.1-blue.svg)](https://www.lua.org)

CC:Tweaked turtle scripts for ComputerCraft. Includes an intelligent ore miner with vein detection, automatic refueling, and Rednet remote query support, plus a scanner to monitor active turtles on the network.

## scripts

### mine.lua — Intelligent Ore Miner

Select an ore type from the menu, and the turtle navigates to the optimal Y layer, mines a straight tunnel while detecting and fully excavating ore veins using DFS, and returns home when fuel runs low or inventory is full. Supports Rednet for remote status queries.

### scanner.lua — Rednet Scanner

Scan the Rednet network for active mining turtles using the `turtle-status` protocol. View their position, fuel level, inventory, and current status from a pocket computer or any Rednet-connected terminal.

## usage

```bash
# On an advanced turtle:
wget https://raw.githubusercontent.com/josemri/projects/main/craftOS/mine.lua
mine.lua

# On a pocket computer:
wget https://raw.githubusercontent.com/josemri/projects/main/craftOS/scanner.lua
scanner.lua
```

## project structure

```
craftOS/
├── mine.lua      # Intelligent ore miner
└── scanner.lua   # Rednet turtle scanner
```

## license

[![GNU GPLv3](https://www.gnu.org/graphics/gplv3-127x51.png)](https://www.gnu.org/licenses/gpl-3.0.en.html)

**craftOS** is Free Software under the [GNU General Public License v3](https://www.gnu.org/licenses/gpl-3.0.en.html).

---

<div align="center">
  <b>Made with ⛏️ by<a href="https://github.com/Cchi11">Cchi11 & <a href="https://github.com/josemri">josemri</a></b>
</div>
