function create_tags()
	return {
		none = nil,
		bool = true,
		number = 42.42,
		string = "foobar",
		list = {
			nil,
			true,
			42.42,
			"foobar"
		},
		dictionary = {
			none = nil,
			bool = true,
			number = 42.42,
			string = "foobar",
		}
	}
end

function apply_tags(player)
	local stack = player.cursor_stack
	if stack == nil or not stack.is_blueprint then
		player.print("Hold the blueprint to be modified in your hand!")
		return
	end
	for i = 1, stack.get_blueprint_entity_count() do
		stack.set_blueprint_entity_tags(i, create_tags())
	end
	player.print("Modified blueprint!")
end

apply_tags(game.player)


--[[ seems that the BP must be in the inventory but not in the library? (1.1.19) ]]
