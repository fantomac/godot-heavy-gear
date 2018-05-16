## holds data about a unit's crew. This includes game-related data like skills 
## as well as fluff-related data like names, rank and gender

extends Reference

const RandomUtils = preload("res://scripts/helpers/RandomUtils.gd")

const MALE = "male"
const FEMALE = "female"

var parent_faction
var rank
var gender
var first_name
var last_name

var skills = {}

## planned skills:
## Athletics
## Piloting
## Gunnery
## Electronic Warfare
## Leadership

func _init(faction, crew_spec):
	parent_faction = faction
	
	gender = RandomUtils.get_random_item([ MALE, FEMALE ])
	last_name = RandomUtils.get_random_item(faction.namelists.surnames)
	first_name = RandomUtils.get_random_item(faction.namelists[gender])
	
	rank = crew_spec.rank
	skills = crew_spec.skills
