--!strict
-- Central vehicle catalog. Adding a vehicle should mostly mean adding a template model to
-- ServerStorage.Vehicles and an entry here.
--
-- Car handling keys are attribute overrides for the Racing-template chassis, grouped by the
-- folder that owns them (Engine, Steering, Wheels, Suspension, AntiRoll). Speeds are in mph
-- (the chassis treats 1 stud as 1 foot). Plane handling is read by PlaneController (studs/s, degrees).

export type Category = "car" | "plane"

export type Entry = {
	id: string,
	displayName: string,
	category: Category,
	price: number,
	starter: boolean,
	model: string, -- child of ServerStorage.Vehicles
	spawnCategory: string, -- matches the SpawnCategory attribute on VehiclePad parts
	color: Color3,
	preview: string, -- image id, or "" for the placeholder swatch
	description: string,
	handling: { [string]: any },
	damage: { [string]: number },
}

local Catalog = {}

local entries: { Entry } = {
	{
		id = "starter_car",
		displayName = "Starter Compact",
		category = "car",
		price = 0,
		starter = true,
		model = "StarterCar",
		spawnCategory = "car",
		color = Color3.fromRGB(46, 160, 67),
		preview = "",
		description = "Nimble little runabout. Free!",
		handling = {
			Engine = { forwardMaxSpeed = 62, reverseMaxSpeed = 28, acceleration = 38 },
		},
		damage = { maxHealth = 100, lightImpact = 45, heavyImpact = 110 },
	},
	{
		id = "starter_plane",
		displayName = "Starter Prop Plane",
		category = "plane",
		price = 0,
		starter = true,
		model = "StarterPlane",
		spawnCategory = "plane",
		color = Color3.fromRGB(33, 118, 214),
		preview = "",
		description = "Forgiving propeller plane. Free!",
		handling = {
			maxSpeed = 150, -- studs/s at full throttle
			takeoffSpeed = 60, -- studs/s needed before W lifts the nose
			acceleration = 28,
			deceleration = 14,
			groundBrake = 45, -- deceleration on the ground with the throttle closed
			throttleRate = 0.55, -- throttle change per second while holding the key
			turnRate = 55, -- degrees/s of heading change in the air
			groundTurnRate = 50,
			pitchRate = 45,
			maxPitch = 45,
			bankAngle = 35,
			autoLevelRate = 18, -- degrees/s the nose returns to level with no pitch input
			sinkRate = 28, -- studs/s descent when slower than takeoff speed in the air
		},
		damage = { maxHealth = 100, lightImpact = 50, heavyImpact = 120 },
	},
}

local byId: { [string]: Entry } = {}
for _, entry in entries do
	assert(byId[entry.id] == nil, "duplicate vehicle id " .. entry.id)
	byId[entry.id] = entry
end

function Catalog.get(id: string): Entry?
	return byId[id]
end

function Catalog.all(): { Entry }
	return table.clone(entries)
end

function Catalog.byCategory(category: Category): { Entry }
	local list = {}
	for _, entry in entries do
		if entry.category == category then
			table.insert(list, entry)
		end
	end
	return list
end

return Catalog
