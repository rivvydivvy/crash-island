--!strict
-- Every tunable number for Crash Island lives here (vehicle handling lives in VehicleCatalog).

local Config = {}

Config.World = {
	-- Lower than Roblox's 196.2 so ramp jumps and crashes have satisfying hang time.
	Gravity = 150,
	-- Island centre used for plane boundaries and recovery.
	Center = Vector3.new(0, 0, 0),
	-- Ground surface is Y=2 and the sea surface Y=-2; floating cars sit around Y=-4.7.
	-- A vehicle whose root drops below this height (in the sea) is recovered.
	RecoveryHeight = -1,
	-- Planes past this horizontal distance get steered back towards the island.
	PlaneSoftRadius = 1750,
	-- Planes past this distance (or above the hard ceiling) are recovered to the airfield.
	PlaneHardRadius = 2400,
	PlaneCeiling = 650,
	PlaneHardCeiling = 900,
	-- Seconds a vehicle must stay out of bounds before it is recovered.
	OutOfBoundsGrace = 1.5,
}

Config.Vehicles = {
	-- Seconds between spawn/respawn requests per player.
	SpawnCooldown = 3,
	-- Extra clearance (studs) around a vehicle's bounding box when checking a pad for obstructions.
	PadClearance = Vector3.new(4, 2, 4),
	-- Height above the pad surface a vehicle is placed at before it settles.
	SpawnLift = 1.5,
	-- Seconds between flip requests per player.
	FlipCooldown = 2,
	-- How often (seconds) the server checks active vehicles for out-of-bounds recovery.
	RecoveryCheckInterval = 0.5,
}

Config.Net = {
	-- Remote requests a single player may make per second before being ignored.
	RequestsPerSecond = 6,
}

Config.Ui = {
	NotificationSeconds = 3.5,
	ControlsHintSeconds = 10,
}

Config.Tags = {
	VehiclePad = "VehiclePad",
	HqSpawn = "HqSpawn",
	VehicleBlocker = "VehicleBlocker",
}

Config.CollisionGroups = {
	Vehicle = "Vehicle",
	Character = "Character",
	-- Invisible-to-players walls that only stop vehicles (protected plaza, airfield fence).
	VehicleBlocker = "VehicleBlocker",
}

return Config
