## Generates all possible movement for a unit and stores this information for display and pathing.

extends Reference

const HexUtils = preload("res://scripts/helpers/HexUtils.gd")
const SortingUtils = preload("res://scripts/helpers/SortingUtils.gd")
const PriorityQueue = preload("res://scripts/helpers/PriorityQueue.gd")
const MovementModes = preload("res://scripts/game/MovementModes.gd")


static func calculate_movement(world_map, move_unit):
	var unit_info = move_unit.unit_info
	
	var current_mode = move_unit.current_activation.movement_mode
	
	## calculate pathing for each movement mode and then merge the results
	var possible_moves = {}
	for movement_mode in unit_info.get_movement_modes():
		#once we start using a movement mode, we can only use movement modes that
		#share the same movement type for the rest of the turn
		if current_mode && current_mode.type_id != movement_mode.type_id:
			continue
		
		#don't use reverse movement on units that don't have a facing
		if !move_unit.has_facing() && movement_mode.reversed:
			continue
		
		var movement = new(world_map, move_unit, movement_mode)
		for cell_pos in movement.possible_moves:
			var move_info = movement.possible_moves[cell_pos]
			
			if !possible_moves.has(cell_pos) || _move_priority_compare(possible_moves[cell_pos], move_info):
				possible_moves[cell_pos] = move_info
	return possible_moves

static func _move_priority_compare(left, right):
	return SortingUtils.lexical_sort(_move_priority_lexical(left), _move_priority_lexical(right))

static func _move_priority_lexical(move_info):
	return [
		1 if !move_info.hazard else -1, #non-hazardous over hazardous moves
		1 if move_info.movement_mode.free_rotate else -1, #prefer free rotations
		-move_info.move_count, #prefer less movement actions used
		move_info.turns_remaining if move_info.turns_remaining else 1000, #prefer more turns remaining
		move_info.moves_remaining, #prefer more moves remaining
		hash(move_info), #lastly, sort by hash to ensure determinism
	]

##### Movement Pathing #####

var move_unit #the unit whose movement we are considering
var unit_info
var world_map #reference to the world map the unit is located on
var movement_mode

var _track_turns #flag if we should track facing and turn rate

## a dictionary of the grid positions this unit can reach from the start_loc
## each position is mapped to a dictionary of information (e.g. movement costs, facing at that hex, turning angle used)
var possible_moves = {}

## cached data
var _grid_spacing
var _movement_rate #amount of movement per move action
var _turning_rate  #amount of turning per move action

func _init(world_map, move_unit, movement_mode):
	self.move_unit = move_unit
	self.unit_info = move_unit.unit_info
	self.world_map = world_map
	self.movement_mode = movement_mode
	
	_grid_spacing = HexUtils.pixels2units(world_map.UNITGRID_WIDTH)
	
	_movement_rate = movement_mode.speed
	_turning_rate = movement_mode.turn_rate
	_track_turns = unit_info.use_facing() && !movement_mode.free_rotate
	
	var start_loc = move_unit.cell_position
	var start_dir = move_unit.facing
	if movement_mode.reversed:
		start_dir = HexUtils.reverse_dir(start_dir) ## reverse the facing
	
	var visited = _search_possible_moves(start_loc, start_dir)
	for cell_pos in visited:
		if cell_pos != start_loc && _can_stop(cell_pos):
			var move_info = visited[cell_pos]
			
			if movement_mode.reversed:
				move_info.facing = HexUtils.reverse_dir(move_info.facing) ## un-reverse the facing
			
			possible_moves[cell_pos] = move_info


## setups a movement state for the beginning of a move action
func _init_move_info(move_count, facing, move_path, init_moves=null, init_turns=null):
	return {
		move_count = move_count, #the number of move actions used
		movement_mode = movement_mode,
		facing = facing,
		prev_facing = null,
		moves_remaining = init_moves if init_moves != null else _movement_rate,
		turns_remaining = init_turns if init_turns != null else _turning_rate,
		hazard = false,
		path = move_path,
	}

## lower priority moves are explored first
func _move_priority(move_state):
	var turns = move_state.turns_remaining if move_state.turns_remaining else 0
	var moves = move_state.moves_remaining
	var hazard = 10000 if move_state.hazard else 0
	return -(turns * 10*moves) + hazard

func _search_possible_moves(start_loc, start_dir):
	var cur_activation = move_unit.current_activation
	var max_moves = cur_activation.move_actions
	var init_moves = cur_activation.partial_moves
	var init_turns = cur_activation.partial_turns
	var initial_state = _init_move_info(0, start_dir, [ start_loc ], init_moves, init_turns)
	
	var visited = { start_loc: initial_state }
	var next_move = {}
	
	var move_queue = PriorityQueue.new()
	move_queue.add(start_loc, _move_priority(visited[start_loc]))
	
	for move_count in range(max_moves):
		_search_move_action(move_queue, visited, next_move)
		
		## add the next move start positions to the queue
		assert(move_queue.size() == 0)
		for next_pos in next_move:
			if !visited.has(next_pos):
				visited[next_pos] = next_move[next_pos]
			move_queue.add(next_pos, _move_priority(visited[next_pos]))
	
	## don't use any of the positions in next_move on the final move
	_search_move_action(move_queue, visited, next_move)
	
	return visited

## Starting at the unit's current position, we want to search through all possible connecting hexes that we can move to.
## We want to perform a breadth first search, and vist each new grid position only once.
func _search_move_action(move_queue, visited, next_move):
	while !move_queue.empty():
		var cur_pos = move_queue.pop_min()
		var neighbors = _visit_cell_neighbors(cur_pos, visited, next_move)
		for next_pos in neighbors:
			visited[next_pos] = neighbors[next_pos]
			move_queue.add(next_pos, _move_priority(neighbors[next_pos]))

func _visit_cell_neighbors(cur_pos, visited, next_move):
	var next_visited = {}
	
	## unpack current state
	var cur_state = visited[cur_pos]
	var facing = cur_state.facing
	var prev_facing = cur_state.prev_facing
	var move_count = cur_state.move_count
	var hazard = cur_state.hazard
	
	var neighbors = HexUtils.get_neighbors(cur_pos)
	for move_dir in neighbors:
		var next_pos = neighbors[move_dir]
		var moves_remaining = cur_state.moves_remaining
		var turns_remaining = cur_state.turns_remaining
		
		if visited.has(next_pos):
			continue ## already visited
		
		if not _can_enter(cur_pos, next_pos):
			continue ## can't go this direction, period
		
		var extra_move = false #if we need to start a new move action to visit the next_pos
		
		## handle turning costs
		var turn_cost = 0
		if _track_turns:
			turn_cost = abs(HexUtils.get_shortest_turn(facing, move_dir))
			
			## if we return to our previous facing, refund the turn cost
			## this allows "straight" zig-zagging, which hopefully lessens 
			## the distortion on movement caused by using a hex grid
			if move_dir == prev_facing:
				turn_cost *= -1
			
			## do we need to start a new move to face this direction?
			if turns_remaining < turn_cost:
				extra_move = true
				moves_remaining = 0 #movement only carries over if we are able to make the turn
		
		## handle movement costs
		var move_cost = _move_cost(cur_pos, next_pos)
		
		## do we need to start a new move to make it to the next_pos?
		if moves_remaining < move_cost:
			extra_move = true
		
		var next_path = cur_state.path.duplicate()
		next_path.push_back(next_pos)		
		
		## visit the next_pos
		if !extra_move:
			## continue the current move action
			var next_state = cur_state.duplicate()
			
			next_state.facing = move_dir
			next_state.prev_facing = facing
			next_state.moves_remaining -= move_cost
			if _track_turns:
				next_state.turns_remaining -= turn_cost
			next_state.hazard = hazard || _is_dangerous(next_pos)
			next_state.path = next_path
		
			next_visited[next_pos] = next_state
		else:
			## even if we take a whole new move action, we still may not be able to reach the next_pos, so check that
			if _movement_rate + moves_remaining >= move_cost && (!_track_turns || _turning_rate + turns_remaining >= turn_cost):
				## it's important that prev_facing is cleared when we reset turns_remaining
				## that way on the next iteration we can't be refunded turns we haven't spent.
				var next_state = _init_move_info(move_count + 1, move_dir, next_path)
				
				## carry over remaining movement
				next_state.moves_remaining += moves_remaining - move_cost
				if _track_turns:
					## turns don't carry over. however we can use the remaining turns to pay off any remaining cost.
					next_state.turns_remaining += min(turns_remaining - turn_cost, 0)
				
				## carry over hazard flag
				next_state.hazard = hazard || _is_dangerous(next_pos)
				
				next_move[next_pos] = next_state
	
	return next_visited


## Figure out if the unit can enter the given cell position
func _can_enter(from_cell, to_cell):
	return world_map.unit_can_pass(move_unit, movement_mode, from_cell, to_cell)

## we may be able to enter but not finish our movement in certain cells
func _can_stop(cell_pos):
	return world_map.unit_can_place(move_unit, cell_pos)

## How much movement must we expend to move from a cell in a given direction?
func _move_cost(from_cell, to_cell):
	var midpoint = 0.5*(world_map.get_grid_pos(from_cell) + world_map.get_grid_pos(to_cell))
	var terrain_info = world_map.get_terrain_at(midpoint)
	return _grid_spacing * unit_info.get_move_cost_on_terrain(movement_mode, terrain_info)

## If entering a given cell will trigger a dangerous terrain check
func _is_dangerous(cell_pos):
	return false #TODO
