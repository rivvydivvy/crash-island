-- Minimal, idempotent patches to the Racing-template car scripts (ServerStorage.Vehicles.StarterCar).
-- Run in Edit mode:  node tools/mcp.js lua Edit build/patch_car.luau
--
-- 1. ClientController only reacted to *changes* of DriverSeat.Occupant. Crash Island seats the
--    player in the same frame the car appears, so the car can replicate already occupied and the
--    controller never starts. Evaluate the seat once at startup as well.

local car = game:GetService("ServerStorage"):WaitForChild("Vehicles"):WaitForChild("StarterCar")
local log = {}

local controller = car.Scripts.Client.ClientController
local MARKER = "-- Crash Island patch: handle a driver seated before this script started"
if not string.find(controller.Source, MARKER, 1, true) then
	controller.Source ..= "\n" .. MARKER .. "\nonOccupantChanged()\n"
	table.insert(log, "patched ClientController (initial occupant check)")
end

return if #log > 0 then table.concat(log, "\n") else "already patched"
