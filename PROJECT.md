# SYSTEM DESIGN BRIEF & CODE GENERATION PROMPT: ATM9 SWARM QUARRY C2 SYSTEM

## 1. PROJECT OVERVIEW
Build a distributed, fault-tolerant, multi-turtle autonomous mining and Command & Control (C2) system for **CC: Tweaked (Minecraft 1.20.1 / All the Mods 9)**. The system coordinates a swarm of Advanced Mining Turtles in the **ATM9 Mining Dimension** via cross-dimensional **Ender Modems** and a local **GPS Satellite Cluster**, controlled remotely from a Master C2 Computer connected to a large **Advanced Monitor** (3x4 or 4x4 blocks).

---

## 2. ARCHITECTURE & HARDWARE TOPOLOGY
Generate a clean, modular multi-file Lua architecture divided into three distinct node types:

1. **`master/` (Base C2 Computer + 3x4 or 4x4 Advanced Monitor + Ender Modem):**
   - Acts as the central brain, task scheduler, telemetry aggregator, and touchscreen GUI host.
   - Persists state to disk (`swarm_state.json` / `textutils.serialize`) so server restarts do not lose active job progress, turtle assignments, or logged Allthemodium coordinates.
2. **`deployer/` (Forward Operating Base Deployment Turtle/Computer + Chest + Ender Modem):**
   - Located in the Mining Dimension next to a Supply Chest (containing labeled Advanced Mining Turtles, Ender Modems, Diamond Pickaxes, and Fuel) and an Output/Drop-off Chest (or Ender Chest).
   - Receives deployment commands from Master C2, places turtles into the world, boots them via peripheral call (`peripheral.call(side, "turnOn")`), and assigns their initial GPS/sector parameters.
3. **`drone/` (Advanced Mining Turtles + Diamond Pickaxe + Ender Modem):**
   - Identified strictly by their OS label (`os.getComputerLabel()`).
   - Uses `gps.locate()` on boot and after every state recovery to maintain absolute 3D world coordinates `(X, Y, Z)` and facing direction (`0=North, 1=East, 2=South, 3=West`).

---

## 3. ATM9 MINING DIMENSION STRATA & ORE DATABASE
Hardcode a lookup table in `master/ore_db.lua` using the exact ATM9 Mining Dimension Y-level distributions so the user can launch jobs by **Layer Preset** or **Target Ore Sweet Range**:

### A. Dimension Layer Presets
- **Stone Layer:** `Y: 129 to 247`
- **Deepslate Layer:** `Y: 65 to 128`
- **Nether Layer:** `Y: 1 to 64`
- **End Layer:** `Y: -63 to 0`

### B. Target Ore "Sweet Ranges" (Auto-calculates Y-min and Y-max)
- **Coal:** `Y: 146 to 166` (Full: 65–247)
- **Iron:** `Y: 146 to 166` (Full: 65–247)
- **Copper:** `Y: 146 to 166` (Full: 65–247)
- **Emerald:** `Y: 146 to 166` (Full: 65–247)
- **Redstone:** `Y: 128 to 148` (Full: 71–205)
- **Diamond:** `Y: 125 to 145` (Full: 97–173)
- **Aluminum:** `Y: 117 to 137` (Full: 6–247)
- **Lapis Lazuli:** `Y: 99 to 119` (Full: 72–146)
- **Allthemodium:** `Y: 86 to 96` (Full: 70–114) *[LOG ONLY - DO NOT ATTEMPT TO MINE]*
- **Tin:** `Y: 70 to 90` (Full: -25–185)
- **Gold:** `Y: 59 to 79` (Full: 4–134)
- **Quartz:** `Y: 61 to 64` (Full: 61–64)
- **Uranium:** `Y: 40 to 80` (Full: 29–92)
- **Ancient Debris (Netherite):** `Y: 30 to 50` (Full: 16–65)
- **Zinc:** `Y: 17 to 47` (Full: -53–118)
- **Crimson Iron:** `Y: 17 to 47` (Full: 1–64)
- **Platinum:** `Y: 3 to 19` (Full: -58–25)
- **Silver:** `Y: -15 to 20` (Full: -63–54)
- **Nickel:** `Y: -17 to 3` (Full: -61–46)
- **Osmium:** `Y: -21 to -1` (Full: -56–21)
- **Lead:** `Y: -56 to -26` (Full: -63 to -19)

*Example Job Behavior:* If the user selects **Target Ore: Osmium** with area **100x100**, Master C2 automatically creates a `100 x 100 x 21` volume spanning `Y: -1` down to `Y: -21`. If the user selects **Stone Layer** with `100x100x50`, it slices a 50-block tall volume within `Y: 129–247`.

---

## 4. SWARM SUBDIVISION & DIVIDE-AND-CONQUER LOGIC
1. **Dynamic Grid Partitioning:**
   - Given an overarching bounding box `(X1, Y1, Z1)` to `(X2, Y2, Z2)` and `N` active/available turtles, Master C2 divides the XZ plane into `N` non-overlapping rectangular sub-sectors (stripes or grid cells).
   - If a turtle goes offline or runs out of fuel/dies, Master C2 detects a missed heartbeat (`>15 seconds`) and dynamically reassigns its incomplete sector to an idle turtle or newly deployed replacement.
2. **Collision Avoidance & Pathing:**
   - Turtles travel to their assigned sector at a dedicated **Transit Altitude** (e.g., `Y = 250` above terrain, or via reserved transit lanes) before descending to their sector's `Y_max`.
   - If `turtle.forward()` fails and `turtle.inspect()` detects another turtle (`computercraft:turtle_advanced` or `turtle_normal`), the turtle waits a randomized backoff (`0.5s - 2.0s`) and retries rather than breaking or jamming.
3. **Unbreakable Block Handling (Allthemodium / Vibranium / Unobtainium):**
   - Before every dig (`inspect`, `inspectUp`, `inspectDown`), the turtle checks `data.name` or `data.tags`.
   - If the block matches `allthemodium`, `vibranium`, `unobtainium`, or bedrock, or if `turtle.dig()` returns `false` on a solid non-fluid block:
     - The turtle computes the **exact world coordinates `(X, Y, Z)`** of that target block using its GPS position and facing vector.
     - It transmits a high-priority `UNBREAKABLE_FOUND` packet to Master C2 with block ID and exact `(X, Y, Z)`.
     - It executes a 3D pathfinding maneuver to **route around** the unbreakable block and resume its serpentine layer pattern without halting.
4. **Logistics (Inventory, Trash Filtering, & Refueling):**
   - **Auto-Refuel:** Burns mined coal/charcoal automatically when fuel drops below 2,000. If fuel drops below `return_fuel_cost * 1.5`, the turtle pauses mining, returns to the FOB Drop-off/Refuel station via GPS, pulls fuel from the Refuel Chest, and resumes at its exact saved `(X, Y, Z)` checkpoint.
   - **Inventory Full:** When all 16 slots are occupied, the turtle navigates to the FOB Drop-off Chest, deposits all items, updates Master C2 with exact item counts deposited, and resumes mining.

---

## 5. MASTER C2 TOUCHSCREEN MONITOR UI (3x4 / 4x4 ADVANCED MONITOR)
Design a responsive, mouse/touch-driven UI (`monitor_touch` events) scaled at `0.5` text scale with a top navigation bar supporting **4 Interactive Tabs**:

1. **[ TAB 1: OVERVIEW & MAP ]**
   - Live 2D top-down ASCII/pixel grid radar of the active quarry bounding box showing subdivided sectors, each turtle's live `(X, Z)` dot color-coded by state (`GREEN = Mining`, `YELLOW = Returning/Refueling`, `RED = Error/Stuck`), and `MAGENTA` markers for logged Allthemodium veins.
   - Global progress bar (`% blocks cleared`, `ETA`, `Active Drones`).
   - Global Master Buttons: `[ PAUSE ALL ]`, `[ RESUME ALL ]`, `[ RECALL ALL TO BASE ]`, `[ DEPLOY +1 DRONE ]`.
2. **[ TAB 2: JOB CONFIGURATOR ]**
   - Interactive touchscreen selectors for:
     - **Mode:** `[ LAYER PRESET ]` vs `[ TARGET ORE SWEET RANGE ]`
     - **Preset/Ore Selector:** Scrollable/clickable list from Section 3 (e.g., `Stone`, `Deepslate`, `Nether`, `End`, `Osmium`, `Diamond`, `Ancient Debris`, etc.).
     - **Dimensions:** Buttons to increment/decrement `Width (X)` and `Length (Z)` (`+16`, `+64`, `+100`, `-16`) and `Custom Depth` (or `Auto-Sweet-Range`).
     - **Origin Anchor:** `[ USE FOB ORIGIN ]` or `[ SET CUSTOM X/Z ]`.
   - Big green `[ LAUNCH SWARM JOB ]` button that computes subdivisions and dispatches orders.
3. **[ TAB 3: DRONE INSPECTOR ]**
   - Left sidebar: Scrollable list of all registered turtles by **Label** (e.g., `Miner_01`, `Miner_02`).
   - Right panel (for selected turtle):
     - Live GPS `(X, Y, Z)`, Facing Direction, Fuel Level (`current / 100,000`), Current Task/Sector, and Inventory Fill (`X/16 slots`).
     - Individual Drone Override Buttons: `[ PAUSE ]`, `[ RESUME ]`, `[ RETURN & UNLOAD ]`, `[ REBOOT ]`.
4. **[ TAB 4: ORE LEDGER & WAYPOINTS ]**
   - **Left Column (Allthemodium & Unbreakable Waypoints):** Scrollable list of exact world coordinates (e.g., `allthemodium_ore @ X: 412, Y: 91, Z: -108`) with a `[ CLEAR ]` button for mined veins.
   - **Right Column (Swarm Yield Counter):** Live aggregated totals of every ore/item mined across the entire swarm.

---

## 6. NETWORK PROTOCOL SPECIFICATION
Use a dedicated Ender Modem channel (e.g., `CHANNEL = 9001`) with structured JSON/Lua table packets:
- `HEARTBEAT`: `{ type="HB", label=string, pos={x,y,z}, dir=int, fuel=int, state=string, sector_progress=float }`
- `ASSIGN_SECTOR`: `{ type="TASK", target_label=string, bounds={x1,y1,z1,x2,y2,z2}, home={x,y,z} }`
- `UNBREAKABLE_ALERT`: `{ type="ALERT", label=string, block=string, pos={x,y,z} }`
- `YIELD_REPORT`: `{ type="YIELD", label=string, items={ [item_name]=count } }`
- `CMD_CONTROL`: `{ type="CMD", target=string ("ALL" or label), action=string ("PAUSE"|"RESUME"|"RECALL"|"DEPLOY") }`

---

## 7. DELIVERABLES & CODE QUALITY REQUIREMENTS
1. Write **complete, production-ready Lua code**—do not leave placeholder comments like `-- TODO: implement pathfinding`.
2. Ensure compatibility with **CC: Tweaked** APIs (`peripheral.find`, `gps.locate`, `turtle.inspect`, `textutils.serializeJSON`, `monitor.setTextScale`).
3. Include a clean `installer.lua` script that downloads/writes all required files onto the Master Computer, Deployer, and Turtles, and configures `startup.lua` on each device so the entire swarm auto-boots and reconnects seamlessly on world load.
