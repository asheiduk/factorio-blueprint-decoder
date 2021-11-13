
function rotated_turrets(player, name)
	local x, y, delta = 0, 0, 3
	local entities = {}
	for direction = 0, 8, 2 do
		x = 0
		for orientation = 0.0, 1.0, 0.25 do
			local entity = {
				name = name,
				entity_number = #entities + 1,
				position = { x, y },
				direction = direction,
				orientation = orientation,
				--[[ copy just for debugging: ]]
				tags = {
					orientation = orientation,
					direction = direction
				}
			}
			table.insert(entities, entity)
			x = x + delta
		end
		y = y + delta
	end
	player.cursor_stack.set_blueprint_entities(entities)
end

--[[ choose one: ]]
rotated_turrets(game.player, "gun-turret")
rotated_turrets(game.player, "laser-turret")
rotated_turrets(game.player, "flamethrower-turret")
rotated_turrets(game.player, "artillery-turret")

