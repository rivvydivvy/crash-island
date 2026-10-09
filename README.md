# Crash Island: Cars & Planes

A Roblox multiplayer playground: drive cars, fly planes, hit ramps, crash into things.
Built in small, playtested milestones (see the build guide's section 12).

**Status:** Milestone 1 (Drive and Fly) is done and playtested. Milestone 2 (Crash With Friends) is next.

## Playtest it

1. Open `CrashIsland.rbxl` in Roblox Studio.
2. Press **Play** (F5) for solo, or **Test > Start Test Session > Server and Clients** with 2+ clients for multiplayer.
3. Press **Vehicles**, or walk to the yellow kiosk at HQ and press E, then pick **Spawn at Car Bay** or **Spawn at Airfield**. You're seated automatically.

## Controls

| | Car (Racing-template chassis) | Plane |
|---|---|---|
| Keyboard | W/S gas/brake/reverse, A/D steer, Space handbrake, Shift nitro, C camera, E exit | Shift/Ctrl throttle up/down, W/S climb/dive, A/D turn, E exit (on the ground) |
| Touch | Steering arc, pedals, handbrake and nitro buttons, exit/camera top-right | Stick (bottom-left) to climb and turn, + / - THROTTLE buttons (bottom-right) |
| Gamepad | Chassis defaults (triggers, left stick, X exit) | RT/LT throttle, left stick climb/turn, X exit |
| Both | **R** or the **Flip** button flips you upright. **Respawn** gives you a fresh copy of the same vehicle. **Return to HQ** teleports you to HQ. | |

To take off: hold Shift until "Takeoff speed!" appears, then press W. To land: close the throttle, dip the nose gently, then level out near the ground.

## Project structure

```
src/                                  game code (synced into Studio by tools/sync.js)
  ReplicatedStorage/Shared/           Config, VehicleCatalog, Net (remote names)
  ServerScriptService/CrashIsland/    Main (boot), VehicleService, Collision, Ownership
  StarterPlayerScripts/CrashIsland/   Hud, PlaneController, VehicleClient
build/                                Edit-mode Luau build scripts (run via tools/mcp.js)
  prepare_place.luau                  turns the official Racing template into the base place
  patch_car.luau                      small patches to the template car's scripts
  plane_template.luau                 builds ServerStorage.Vehicles.StarterPlane
  map.luau                            builds the graybox island (rebuilds Workspace.Map/Props)
tools/
  mcp.js                              client for Studio's built-in MCP server
  sync.js                             pushes src/ into the open place (one-way, mirrors managed folders)
CrashIsland.rbxl                      the place file (template assets + built map + synced code)
```

In the place:
- **ServerStorage.Vehicles:** the `StarterCar` and `StarterPlane` templates.
- **Workspace.Map:** the static island, including pads (tagged `VehiclePad`), the HQ spawn (tagged `HqSpawn`) and vehicle-only walls (tagged `VehicleBlocker`).
- **Workspace.Props:** loose crates and barrels.
- **Workspace.ActiveVehicles:** spawned vehicles, created at runtime.

### Dev workflow

1. In Studio, turn on **Assistant > ... > Settings > MCP Servers > Enable Studio as MCP server**. Studio's Assistant panel is the icon left of the notifications bell.
2. Edit files in `src/`, then run `node tools/sync.js`. `tools/mcp.js` targets the Studio instance whose name matches `CrashIsland`, or whatever `STUDIO_ID` you set. It never guesses.
3. Run build scripts with `node tools/mcp.js lua Edit build/<script>.luau`.
4. Save the place with **File > Save to File**.

To rebuild from scratch:
1. Create a new place from the **Racing** template.
2. Run `prepare_place`, `patch_car`, `plane_template` and `map` in that order.
3. Run `node tools/sync.js`.

## Where to tune things

| What | Where |
|---|---|
| Gravity, recovery height, plane boundaries/ceiling | `Config.World` |
| Spawn cooldown, pad clearance, flip cooldown | `Config.Vehicles` |
| Request rate limit | `Config.Net` |
| Vehicle list, prices, colours, handling, damage numbers | `VehicleCatalog` |
| Car tuning | `handling = { Engine = {...}, Steering = {...}, ... }`. These override the chassis' own attributes, in mph. |
| Plane tuning | `handling = { maxSpeed, takeoffSpeed, turnRate, ... }`, in studs/s and degrees |
| Map layout | `build/map.luau`, then re-run it. It wipes and rebuilds `Workspace.Map`, `Workspace.Props` and the terrain. |

## How the systems work

- **Spawning:** the server owns all spawning (`VehicleService`).
  1. It validates the vehicle ID against the catalog, checks ownership, and enforces a 3 s cooldown and a per-player busy lock.
  2. It picks the nearest pad of the right category whose whole bounding box is clear of vehicles, debris and other players.
  3. If every pad is blocked, the spawn is refused and your current vehicle is kept. The old vehicle is only removed once the new one is placed.
- **Ownership:**
  - One active vehicle per player.
  - Only the owner can drive it: the drive prompt checks the owner, and the server ejects anyone else from the seat.
  - Leaving the server deletes your vehicle.
- **Collisions:** vehicles collide with each other but not with characters, so nobody gets run over and you can't touch-sit someone's car. `VehicleBlocker` walls stop vehicles only. They protect the HQ plaza and fence the airfield off from cars.
- **Recovery:**
  - Vehicles that end up in the sea are moved back to a free pad after 1.5 s, with the driver still seated.
  - Planes past the soft radius are steered back automatically. Planes past the hard radius or ceiling are recovered.
- **Planes:** a client-side arcade controller drives LinearVelocity + AlignOrientation on the plane body (the pilot owns its physics).
  - On the ground, gravity handles height.
  - Below takeoff speed it can't climb and sinks gently instead of stalling.
  - Exiting in mid-air is refused.

## Save data

Milestone 1 doesn't save anything yet: everyone owns the two starter vehicles. `Ownership.luau` is the seam that Milestone 3 replaces with profile-backed data. Plan for Milestone 3:
- Session-locked profiles (ProfileStore, after reviewing its current docs) on DataStoreService.
- A separate dev datastore name.
- No purchases or rewards until the profile has loaded safely.
- Never overwrite saved data with defaults after a failed load.
- A schema version field for migrations.

## Asset sources and usage terms

| Asset | Source | Terms |
|---|---|---|
| Starter car model, its scripts, audio, Sky/Lighting | Roblox official **Racing** template (Studio > Templates) | Roblox-provided template content for use in Roblox experiences (Roblox Terms of Use) |
| Plane, map, signs, props | Built from plain parts by this project's build scripts | Original |

No Toolbox/Creator Store or other third-party assets are used.

## Known issues and limitations

- **Test coverage:** all playtests ran in Studio on this PC. Real phones haven't been tested.
  - Touch layouts were checked in the iPhone 7 device simulator, which is the smallest landscape screen.
  - Touch *driving* (dragging the stick or wheel) wasn't simulated; only the layout and buttons were checked.
- **Car touch controls:** the chassis picks its controls from the last input type, so in Studio's device simulator it shows keyboard hints until the first tap. Real phones start with touch.
- **Pads:** only one aircraft pad and two car bays, as Milestone 1 specifies. With 6–8 players the pads will often be blocked and players see the "try again" message. Milestone 2 or 3 should add more pads.
- **Jumps and travel times:** jumps are modest. The small ramp gives 0.5 s of air and the big one 0.8 s, with gravity at 150. Tuning is deferred to Milestone 5.
- **Placeholders:** the garage plots and the challenge board are placeholders. Nothing awards Crash Cash yet.
- **No damage yet:** crashing has no effect on vehicles yet. That's Milestone 2.
- **Travel time:** HQ to the Stunt Park or Crash Yard is about 1,000 studs of road. That's an estimated 11–14 s at the measured 91 studs/s top speed, which the car reaches in under 2 s. This is an estimate, not a timed full drive.

## Next: Milestone 2 (Crash With Friends)

- Staged damage: light, medium, then heavy, at which point the vehicle becomes a wreck and offers a quick respawn.
- Breakaway parts, kept separate from the parts the car needs to drive.
- A debris cap and lifetime.
- Breakable barriers in the Crash Yard.
- Basic challenge detection.
- A multi-player crash test.
