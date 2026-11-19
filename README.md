# MineSwarm Simple

Control individual CC:Tweaked mining turtles from an Advanced Monitor. Each
drone independently excavates an inclusive rectangular X/Z area over a
selected ore's Y range or a custom Y range. There is no deployer, subdivision,
FOB configuration, or shared swarm job.

## Requirements

- One master computer with an Advanced Monitor (at least 48x19 characters at
  text scale 0.5) and a modem.
- A labeled mining turtle with a modem, mining upgrade and enough fuel.
- Working CC:Tweaked GPS coverage at each turtle, using at least four GPS
  hosts in the turtle's dimension. All MineSwarm nodes use channel 9001;
  wireless modems need sufficient range. Use Ender Modems if necessary.
- Optionally, put a chest directly behind the stationary turtle before
  assigning its job. A block whose ID ends in `chest` is recognized as a chest.

Restrict modem access to trusted players: messages are not authenticated.

Drone labels must contain only ASCII letters and digits, such as `Drone1`.
Spaces, underscores, quotes, slashes, and other punctuation are not allowed.
An unnamed drone receives a name such as `Miner123`.

Before upgrading a drone with an older invalid label (including `Miner_123`),
finish its active job. After updating, the drone will refuse to start until it
is renamed at its shell, for example with `label set Miner123`. Jobs are tied
to the old label, so renaming a drone during an active job does not reconnect
that job to the new label.

## Install

After these files are pushed to the `Simple` branch, run on each computer:

```text
wget https://raw.githubusercontent.com/TheRedDraqon/MineSwarm/refs/heads/Simple/installer.lua installer.lua
installer
```

Choose `master`, `drone`, or `gps`; enter GPS host coordinates when prompted.
Each installed computer checks `Simple/manifest.txt` for a newer version at
startup and updates its role files without asking for its role or label again.
Changes must be published to that branch before machines can download them.

**Migrating from the old master branch:** stop or finish all old jobs first,
then run the Simple-branch installer once on both the master and each drone.
Old startup updaters point at `master`, not `Simple`, and the two versions use
different network protocols. Existing GPS hosts can remain unchanged. The new
system uses separate state files and does not resume or erase old jobs,
configuration, or state.

## Assigning a job

1. Start the turtle with GPS available and wait for it to appear on **DRONES**.
   Select its label and touch **SET UP JOB**.
2. Tap **END X** and **END Z**, type a coordinate on the master computer
   keyboard, and press Enter. A plain number is an absolute coordinate; `~`
   means the drone's current coordinate, and `~10` / `~-10` are offsets.
3. Use **ORE** to select a sweet-spot Y range, or select **Custom** and enter
   inclusive minimum and maximum Y values. Verify the displayed bounds, then
   touch **ASSIGN JOB**.

The drone's current GPS X/Z and the entered endpoints are opposite corners,
both inclusive. For example, from `(100, 100, 100)`, `~10`, `~10`, and
Osmium produce X `100..110`, Y `-21..-1`, Z `100..110`: 11 by 11 columns,
21 levels each. Negative offsets and absolute coordinates work in either
direction. The master rejects an assignment if the drone is busy/offline or
its X/Z footprint overlaps an active job, including an offline job. A drone
rejects an assignment if its position changed since the last heartbeat.

Use **DRONES** to see positions, fuel, inventory and active column progress,
or to pause and resume that drone. The master can be closed with **Q**
without stopping drones. Completion leaves a drone at its last column.

## Inventory and safety

At assignment the drone checks behind itself for a chest and saves that
location. When all 16 slots are occupied, it returns to that chest, verifies
it is still present, deposits the inventory, and resumes the job. If the
chest is missing, full, unreachable, or fuel is exhausted, the job reports
an error. A full-inventory return will not dig new blocks on the way, to avoid
losing items; keep the return path clear. Keep enough fuel for mining and
return trips; automatic refueling is not provided.

If no chest was detected, a full inventory pauses the drone in place. Manually
clear at least one slot, then select that drone on the master and touch
**RESUME**. A resume request while all slots are occupied leaves it paused.
The inventory is considered full when no empty slot remains, even if an
existing stack has room.

Turtles attempt to dig blocks without filtering their names or tags. This
includes chests and other breakable blocks, so keep valuables and other turtles
out of the quarry and travel paths. If a dig reports an unbreakable block, only
`allthemodium:allthemodium_ore` and
`allthemodium:allthemodium_slate_ore` are recorded on **WAYPOINTS**. The rest
of an affected column is skipped; bedrock and other unbreakable blocks are not
waypointed. Other dig failures stop the job with an error. Progress counts
visited columns, not necessarily successfully removed blocks. A blocked travel
or return path also stops the job with an error.

This is not a general pathfinder: travel may dig a vertical shaft from the
starting position to one block above the selected Y range, and it may clear
blocks in that movement layer. Check the area and test a small job first.
It does not automatically reassign offline drones. The ore presets came from
the previous ATM9 Mining Dimension configuration and should be checked against
the server's actual pack version and dimension.

## Disk space

Updates stage changed files next to installed files for rollback. To check free
space, exit to the shell, run `lua`, then enter `print(fs.getFreeSpace("/"))`.
Remove unneeded files or ask the server admin to increase the computer disk
limit; do not delete saved state or configuration without backing it up. A
full wipe is not required.

## Tests

From the project directory:

```sh
lua tests/quarries.lua && lua tests/master_jobs.lua && lua tests/ui.lua && lua tests/miner.lua \
  && lua tests/drone_pause.lua && lua tests/drone_labels.lua \
  && lua tests/installer_labels.lua && lua tests/pose.lua && lua tests/update.lua
```

Also run `luac -p` on Lua files. Test GPS, chest access, fuel, and protected
blocks in the actual game before launching a large quarry.
