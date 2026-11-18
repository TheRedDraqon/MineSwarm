# MineSwarm for CC:Tweaked / ATM9

MineSwarm is a Lua swarm controller for CC:Tweaked. It contains a touchscreen
master, a forward-base deployer, mining turtles, and GPS-host setup. The project
uses the ore ranges from `PROJECT.md`; verify those ranges against the exact ATM9
server version before starting a large job.

## What it does

- The master discovers labeled turtles by heartbeat, persists its registry,
  active job, yields, and unbreakable-block waypoints, and hosts four monitor
  tabs: overview, job setup, drone inspector, and ledger.
- Jobs use inclusive X/Z bounds and the selected inclusive Y range. Osmium is
  Y=-21 through -1 (21 levels). A job's N available turtles receive a balanced
  rectangular tiling of the **entire** requested X/Z area.
- A turtle mines one vertical column at each assigned X/Z coordinate, descending
  from `y2` to `y1`, then returns above that column. It saves progress after each
  column so a reboot can resume.
- Allthemodium, Vibranium, Unobtainium, bedrock, and other blocks that cannot be
  dug are reported with world coordinates. A protected block causes the turtle
  to skip the rest of that vertical column; it does not attempt to mine it.
- Turtles report GPS, fuel, inventory slots, state, task progress, and deposited
  item counts. Pause, resume, recall, and reboot commands are supported.
- The deployer retrieves a turtle item from the chest in front, places it below
  itself by default, turns on the adjacent turtle peripheral, and assigns a
  stable `Miner_<computerId>` label.
- The installer downloads role-specific files from a trusted raw source URL and
  writes the role's `startup.lua`.

### Subdivision example

Four turtles assigned to a 100x100 total area each receive a 50x50 sector, so
the four sectors cover all 10,000 X/Z coordinates. A 25x25 sector for each of
four turtles would cover only one quarter of that total area. The grid may use
unequal sector dimensions for odd area sizes or turtle counts, but it never
overlaps or leaves unassigned X/Z coordinates.

## Hardware and network setup

1. **GPS:** Install a wireless modem and a GPS host computer at each of at least
   four known, non-coplanar coordinates in the same dimension as the turtles.
   Run the installer with role `gps` on each host and enter that host's actual
   world X/Y/Z. The generated startup runs CC:Tweaked's built-in `gps host`.
   Check `gps.locate()` on a test computer before deploying miners.
2. **Master:** Attach an Advanced Monitor and modem. The monitor may be a
   multi-block arrangement. Its touch events operate the four tabs.
3. **Forward base:** Use an advanced mining turtle with a wireless/Ender modem,
   a supply chest in front, and a drop-off/refuel inventory in front of the
   miner's configured home position. Configure the deployer placement space so
   a turtle can be placed below it. The deployer needs one clear placement
   block per launch; it does not automatically fan out multiple turtle items
   into a staging grid.
4. **Miners:** GPS must work at the deployer's dimension. Each turtle needs a
   mining upgrade, modem, sufficient initial fuel, and enough free inventory
   slots. Install the `drone` role on each turtle before powering it down and
   storing it as an item; otherwise the deployer will boot it without the
   MineSwarm startup program. Calibration checks all four directions for an
   opening and compares GPS readings before and after a one-block move. If
   fully enclosed, it digs only the block directly in front (never a protected
   block) to make a test opening, then backs up. Verify GPS works at the
   turtle's location if calibration still fails.
5. Use one dedicated modem channel. The default is `9001`; every node must use
   the same channel and protocol. Restrict access to that modem network: packets
   are not cryptographically authenticated.

## Installing

Enable CC:Tweaked HTTP in the server configuration. On each computer, download
the installer from this repository and run it:

```text
wget https://raw.githubusercontent.com/TheRedDraqon/MineSwarm/refs/heads/master/installer.lua installer.lua
installer
```

The installer defaults to
`https://raw.githubusercontent.com/TheRedDraqon/MineSwarm/refs/heads/master`
and downloads the role-specific files from that same base URL. Press Enter to
accept it, or enter another raw base URL to install from a different branch or
fork. Then select one role:

- `master` on the C2 computer
- `deployer` on the forward-base turtle
- `drone` on each mining turtle
- `gps` on each GPS host; enter that computer's actual coordinates

The installer installs the matching files, configures startup, and reboots.
On every subsequent startup, MineSwarm fetches `manifest.txt`. If its semantic
version is higher than `/mineswarm/version`, the updater downloads the files for
that computer's role, stages them, and updates the local version. It does not
ask for a role or label, and does not replace configuration, swarm state, or
GPS coordinates. When GitHub is unavailable or a download fails, it reports
the error and continues with installed files. Updates are checked at startup,
not while a program is running.

To publish an update, increment `version=` in `manifest.txt`, update the file
lists there when needed, and push the changed files to the configured branch.
The first install still uses `installer.lua` to select the role and set any
initial label/GPS coordinates. Existing installations must run the updated
installer once to install the updater-enabled `startup.lua`; after that,
ordinary version updates require no role or label prompts.

On the master, edit `/mineswarm/master_config` before launching a job:

```lua
{
  configured = true,
  home = { x = 0, y = 80, z = 0, dir = 0 },
  origin = { x = 0, z = 0 },
  deployerLabel = "Deployer"
}
```

Replace `home` with the exact FOB miner parking position from GPS. Its `dir`
points toward the front-facing drop-off/refuel inventory (`0=north, 1=east,
2=south, 3=west`). Set `origin` to the lower X/Z corner of the quarry; setting
it equal to the FOB's X/Z uses the FOB origin, while a different pair sets a
custom origin. Set `configured=true` only after verifying these coordinates.
The default `/mineswarm/deployer_config` assumes the supply chest is in front
and deployment is downward.

## Running jobs

1. Press **C** on the master computer to open the configuration editor. Enter
   the FOB miner parking X/Y/Z, its facing (`0=north, 1=east, 2=south, 3=west`),
   the quarry origin X/Z, and the deployer computer label. Press Enter to keep
   any displayed value. Saving marks the master configured.
2. Confirm online labeled turtles on the **DRONES** tab.
3. On **JOB SETUP**, choose `ORE` or `LAYER`, select a range, set width/length
   and (for layers) depth, then launch. Tap a dimension value to select it; the
   field highlights, and you can type an exact positive integer on the master
   keyboard and press Enter. Ore mode always uses the database's inclusive
   sweet range. Layer depth starts at the preset's maximum Y and extends
   downward, bounded by that layer's minimum.
4. The origin is the configured quarry X/Z. Width extends toward positive X and
   length toward positive Z.
5. Use **OVERVIEW** for status and **LEDGER** for waypoints and deposited yield.
   Clearing a waypoint removes only its ledger entry; it does not mine or
   otherwise change the world.

Press **Q** on the master computer to exit the C2 program and return to the
shell. This does not pause or recall turtles; use the monitor controls first if
the swarm should stop.

The master uses all online idle/complete turtles available at launch. A turtle
in `ERROR` is deliberately not reused until its fault is investigated.
The number of turtles cannot exceed the number of X/Z cells. It marks a turtle
offline after 20 seconds without a heartbeat. To avoid assigning a sector while
a slow or disconnected turtle may still be mining it, the current version does
**not** automatically reassign an offline turtle's sector. Inspect the turtle
and its sector before manually recovering or restarting that job.

## Safety and current boundaries

- The miner is a column excavator, not a general 3D pathfinder. It clears the
  chosen vertical column, logs protected/undiggable blocks, and continues at
  the next column. It does not route around obstacles within a column.
- Transit uses `transitY = 250` in `shared/config.lua`; set it to a safe,
  accessible altitude for the dimension and server. Transit climbs at the FOB,
  then descends through a separate access shaft just outside the job bounds.
  The miner also needs an air/movement layer at `y2 + 1`; blocks there may be
  cleared to enter and move between columns, so the mined access space can
  extend one layer above the selected ore range.
- If a blocked movement prevents reaching a sector, the task stops and reports
  an error rather than claiming completion.
- The drop-off chest must be directly in front of the configured home position.
  The miner checks that drops succeeded and only reports a yield after unloading.
- Fuel reservation is estimated conservatively from transit altitude, sector
  distance, and column depth. Keep ample fuel at both deployment and refueling
  points. Test a small job before large-area operation.
- Progress is **X/Z columns visited**, not a count of blocks successfully
  removed. Empty blocks, protected blocks, and undiggable blocks make exact
  block-removal percentages unavailable.
- A deployer requires the placed turtle to appear as an adjacent turtle
  peripheral. If the server does not expose that peripheral or `turnOn`, start
  the placed turtle manually; the deployer will report a timeout.
- Yields count item stacks deposited at the FOB, not items dropped or consumed
  by refueling.

## Tests

Run the host-side tests from this directory with Lua 5.2+:

```sh
lua tests/partition.lua && lua tests/pose.lua && lua tests/ui.lua \
  && lua tests/update.lua && lua tests/config_editor.lua
```

For syntax validation, run `luac -p` on each Lua file. CC:Tweaked in-world
testing is still required for peripheral layout, the ATM9 ore distribution,
modem range, and fuel/drop-off behavior.
