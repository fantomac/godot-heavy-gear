extends Node

## enumerate movement type IDs
const WALKER = "walker"
const GROUND = "ground"
const INFANTRY = "infantry"


## TODO split to another file
const INFO = {
	WALKER : {
		name = "Walker",   #display name
		road_bonus = 1.0,  #bonus movement when on roads
		turn_rate = null,  #the max direction steps the unit can turn in a single move action, or null for unlimited (see Direction.gd)
	},
	GROUND : {
		name = "Ground",
		road_bonus = 2.0,
		turn_rate = 3,
	},
	INFANTRY : {
		name = "Foot",
		road_bonus = 1.0,
		turn_rate = null,
	},
	## TODO hover and flying movement types - probably need to sort out terrain elevation first
}

static func get_info(move_type_id):
	return INFO[move_type_id]