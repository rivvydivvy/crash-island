--!strict
-- Answers "does this player own this vehicle?" for the server.
-- Milestone 1: everyone owns the starter vehicles and nothing else. Milestone 3 replaces the
-- body of these functions with saved-profile lookups; callers stay the same.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catalog = require(ReplicatedStorage.Shared.VehicleCatalog)

local Ownership = {}

function Ownership.owns(_player: Player, vehicleId: string): boolean
	local entry = Catalog.get(vehicleId)
	return entry ~= nil and entry.starter
end

function Ownership.ownedIds(player: Player): { string }
	local ids = {}
	for _, entry in Catalog.all() do
		if Ownership.owns(player, entry.id) then
			table.insert(ids, entry.id)
		end
	end
	return ids
end

return Ownership
