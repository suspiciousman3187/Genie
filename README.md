# Genie

A Windower 4 addon that automates **Nyzul Isle Investigation** in FFXI.

Genie reads each floor's objective from chat and then automatically clears or assists with clearing it — solves all Runic Lamp floors, guides you to (or even warps to) target mobs and NMs on all Enemy Kill Floors, tracks your timer and token reward, and allows designating one character to manage the Rune of Transfer upon floor completion.

---

## Is It Safe?
Probably not.

## Install

1. Copy the `Genie` folder into your Windower `addons` directory.
2. `//lua load Genie`.
3. Genie activates when inside Nyzul Isle.

---

## Features
Genie is able to either automatically solve or heavily assist with solving all types of floors in Nyzul Isle. Below is how it handles each floor.

- **Lamp Solver (Order, All, Certify)** — Completes all lamp floors automatically. Handles three types of lamp floor: order, all, and certification lamps. Auto-pauses during combat and resumes after. Certification Lamp Floors are handled through sending IPC commands to all clients to poke the certification lamp once found.
- **Eliminate All Enemies** — Widescans the floor and shows a live list of every remaining enemy with distance, direction, and HP. If auto-warp is turned on, it will warp to the each monster in sequence as you kill them until the floor is clear.
- **Eliminate Enemy Leader** — Finds the floor NM through widescan, then falling back to DAT scan, then plain polling (widescan → DAT → polling) and pins it to the HUD. If auto-warp is turned on, it will warp to the NM directly as soon as it is found.
- **Eliminate Specified Enemy** — `/check`s mobs to find the "Impossible to gauge" target, then displays it on the HUD. If auto-warp is turned on, it will warp to the mob directly as soon as it is found.
- **Eliminate Specified Enemies (Family)** — Uses widescan to find and deduce the family of special monsters and then displays them on HUD. If auto-warp is turned on, it will warp to each mob in the family until all mobs are cleared.
- **Rune of Transfer Automation** — Define a "runner" who handles interacting with the Rune Of Transfer on objective complete (`up` to advance, `exit` to leave).
- **HUD** — Run timer (with penalties), floor number / time / average, token-reward estimate, objective text, plus target/lamp/Archaic Gear lists with color-coded distances.

---

## Commands

Works under any prefix: `//genie`, `//ge`, or `//gn`.

### Automation
| Command | Description |
|---|---|
| `auto` | Toggle auto-solve on lamp floors (default OFF). |
| `warp` | Show all auto-warp toggle states. |
| `warp nm` / `all` / `family` / `single` | Toggle auto-warp for that floor type. |
| `autocertify` | Toggle responding to IPC certify broadcasts for Certification Lamp Floors (default ON). |

### Lamp Solver
| Command | Description |
|---|---|
| `solve` | Start the lamp solver manually. |
| `pause` / `resume` / `cancel` | Pause, resume, or stop the solver. |
| `certify` | Tell all party members (IPC) to poke the certification lamp. |

### Rune Runner
| Command | Description |
|---|---|
| `runner <name>` / `me` / `none` | Set / self-assign / clear the rune clicker. No arg = show current. |
| `mode [up\|exit]` | Set Rune Of Transfer mode (no arg = toggle). Broadcast via IPC. |
| `runnow` | Force the runner to click the rune now. |
| `runtest` | Ping all instances; each reports if it's the runner. |

### Navigation / Targets
| Command | Description |
|---|---|
| `next` | Teleport to the nearest living enemy. |
| `nm` *(or `gotonm`)* | Teleport to the floor NM. |
| `findnm` | Locate the NM and report its position (no teleport). |
| `goto <index>` | Teleport to an entity by index. |
| `wsnm` | Find the NM via widescan. |
| `wsgo` | Widescan-find the NM and teleport. |
| `wscount` | Count / list all enemies via widescan. |
| `scan [all]` | List NMs (or every NPC entity with `all`). |
| `nmlist` | List confirmed NM DAT indices. |

### Misc
| Command | Description |
|---|---|
| `release` | Release a stuck NPC menu / unstuck. Does not always work. |
| `settings` | Print all current character settings. |
| `save` | Save settings to disk. |
| `help` | Print the in-game command list. |

---

## Settings

Saved per character to `data/genie_state_<name>.lua` (toggles + runner) and `data/settings.xml` (HUD position/colors). `rune_mode`, `autocertify`, and `debug` reset to defaults on load.