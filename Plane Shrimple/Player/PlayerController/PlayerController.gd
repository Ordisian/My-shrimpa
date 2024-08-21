extends CharacterBody3D

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

#Signals
signal health_changed(health_value)

# Player Nodes

@onready var head: Node3D = $Head
@onready var player_camera: Camera3D = $Head/PlayerCamera

@onready var crouching_collision_shape: CollisionShape3D = $CrouchingCollisionShape
@onready var standing_collision_shape: CollisionShape3D = $StandingCollisionShape

@onready var animation_player: AnimationPlayer = $neck/Head/Eyes/AnimationPlayer
@onready var gun_animations: AnimationPlayer = $GunAnimations
@onready var muzzle_flash: GPUParticles3D = $neck/Head/Eyes/PlayerCamera/Pistol/MuzzleFlash


# RayCast Nodes
@onready var ray_cast_ceiling: RayCast3D = $Checks/RayCastCeiling
@onready var right: RayCast3D = $Checks/Right
@onready var left: RayCast3D = $Checks/Left
@onready var front: RayCast3D = $Checks/Front
@onready var back: RayCast3D = $Checks/Back

@onready var player_detection_ray: RayCast3D = $neck/Head/Eyes/PlayerCamera/Player_Detection_Ray

## HEAD BOBBING VARIABLES
const HEADBOB_MOVE_AMOUNT = 0.06
const HEADBOB_FREQUENCY = 2.4
var headbob_time := 0.0

var crouching_depth := -0.8

# Health Vars
var health := 100
const health_max := 100
var damage := 0

var lerp_speed := 10.0
var air_lerp_speed := 4.0

## Input Vars
const mouse_sens := 0.006
var direction := Vector3.ZERO

## Movement vars
const jump_velocity := 6.0
const walk_speed = 5.0
const sprint_speed := 8.0
const crouch_speed := 2.0

var auto_bhop := true

var wish_dir := Vector3.ZERO

var ground_accel := 14.0
var ground_decel := 10.0
var ground_friction := 6.0

var air_cap := 0.85
var air_accel := 800.0
var air_move_speed := 500.0

## SLIDING VARIABLES
var slide_timer := 0.0
var slide_timer_max := 1.5
var slide_vector := Vector2.ZERO
var slide_cooldown_timer := 0.0
var slide_cooldown_max := 0.3
const slide_speed := 10.0

## WALL RUNNING VARIABLES
const MIN_WALL_RUN_SPEED := 3.0
var wall_run_timer := 0.0
const JUMP_TO_WALL_RUN_TIMER := 0.5
var wall_jump_cooldown := 0.0
const wall_jump_cooldown_max := 0.7

## STATE VARIABLES
var PLAYER_STATE : Array[String] = ["Sliding", "WallRunning"]
var current_state := PLAYER_STATE[0]


func get_move_speed() -> float:
	if Input.is_action_pressed("sprint"):
		return sprint_speed
	else:
		return walk_speed

func _head_bob(delta):
	## Handle Head Bobbing
	headbob_time += delta * self.velocity.length()
	player_camera.transform.origin = Vector3(
		cos(headbob_time * HEADBOB_FREQUENCY * 0.5) * HEADBOB_MOVE_AMOUNT,
		sin(headbob_time * HEADBOB_FREQUENCY) * HEADBOB_MOVE_AMOUNT,
		0
	)

func _handle_ground_physics(delta) -> void:
	var cur_speed_in_wish_dir = self.velocity.dot(wish_dir)
	var add_speed_till_cap = get_move_speed() - cur_speed_in_wish_dir
	if add_speed_till_cap > 0:
		var accel_speed = ground_accel * delta * get_move_speed()
		accel_speed = min(accel_speed, add_speed_till_cap)
		self.velocity += accel_speed * wish_dir
	
	## Apply Friction
	var control = max(self.velocity.length(), ground_decel)
	var drop = control * ground_friction * delta
	var new_speed = max(self.velocity.length() - drop, 0.0)
	if self.velocity.length() > 0:
		new_speed /= self.velocity.length()
	self.velocity *= new_speed
	
	_head_bob(delta)

func _handle_air_physics(delta) -> void:
	self.velocity.y -= gravity * delta
	
	## Source-like Air Strafing
	var cur_speed_in_wish_dir = self.velocity.dot(wish_dir)
	var capped_speed = min((air_move_speed * wish_dir).length(), air_cap)
	var add_speed_till_cap = capped_speed - cur_speed_in_wish_dir
	if add_speed_till_cap > 0:
		var accel_speed = air_accel * delta * air_move_speed
		accel_speed = min(accel_speed, add_speed_till_cap)
		self.velocity += accel_speed * wish_dir

func _enter_tree() -> void:
	set_multiplayer_authority((str(name).to_int()))

func _ready():
	if not is_multiplayer_authority(): return
	
	## Hide Player Model From Player
	for child in %WorldView.find_children("*", "VisualInstance3D"):
		child.set_layer_mask_value(1, false)
		child.set_layer_mask_value(2, true)
	
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	player_camera.current = true

func _unhandled_input(event):
	if not is_multiplayer_authority(): return
	
	if Input.is_action_pressed("shoot"):
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	elif Input.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseMotion:
			rotate_y(-event.relative.x * mouse_sens)
			player_camera.rotate_x(-event.relative.y * mouse_sens)
			player_camera.rotation.x = clamp(player_camera.rotation.x, deg_to_rad(-90), deg_to_rad(90))
	
	#if Input.is_action_just_pressed("shoot") and gun_animations.current_animation != "Pistol_Shoot":
		#play_pistol_shoot_effect.rpc()
		#Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		#if player_detection_ray.is_colliding():
			#var hit_player = player_detection_ray.get_collider()
			#damage = 35
			#hit_player.receive_damage.rpc_id(hit_player.get_multiplayer_authority(), damage)

func _physics_process(delta):
	if not is_multiplayer_authority(): return
	
	## Get the input direction
	var input_dir = Input.get_vector("left", "right", "forward", "back").normalized()
	
	## Depending on which way the character is facing
	wish_dir = self.global_transform.basis * Vector3(input_dir.x, 0, input_dir.y)
	
	# Move
	if is_on_floor():
		_handle_ground_physics(delta)
		
		## Handle Jump
		if Input.is_action_just_pressed("jump") or (auto_bhop and Input.is_action_pressed("jump")):
			self.velocity.y = jump_velocity
	else:
		_handle_air_physics(delta)
	
	#state_machine(delta, input_dir)
	#_handle_cooldowns(delta)
	#play_gun_animations(input_dir)
	
	move_and_slide()


#func state_machine(delta, input_dir):
	#
	## Set the current state
	#match current_state:
		#"Sliding":
			#_handle_sliding(delta, input_dir)
		#"WallRunning":
			#_handle_wall_running(delta)
	#
	#slide_cooldown_timer -= delta
	#
	## Handle the conditions of each state
	#if is_on_floor():
		#if Input.is_action_pressed("crouch"):
			## Set the hitbox to the crouching version
			#standing_collision_shape.disabled = true
			#crouching_collision_shape.disabled = false
			#
			## Set the camera's view to crouching view
			#head.position.y = lerp(head.position.y, crouching_depth, delta * lerp_speed)
			#
			## Check for slide, if not sliding crouch
			#if Input.is_action_pressed("crouch") and get_move_speed() > walk_speed and slide_cooldown_timer <= 0 || current_state == "Sliding":
				#if current_state != "Sliding":
					#animation_player.stop()
					#animation_player.play("Slide")
					#slide_vector = input_dir
					#slide_timer = slide_timer_max
					#_set_state("Sliding")
			#elif current_state != "Crouching":
				#_set_state("Crouching")
		#
		#elif !ray_cast_ceiling.is_colliding():
			## Set the hitbox to the standing version
			#standing_collision_shape.disabled = false
			#crouching_collision_shape.disabled = true
			#
			## Set the camera's view to standing view
			#head.position.y = lerp(head.position.y, 0.0, delta * (lerp_speed / 3))
			#
			## Check for sprinting
			#if Input.is_action_pressed("sprint") and Input.is_action_pressed("forward") and !Input.is_action_pressed("left") and !Input.is_action_pressed("right") and !Input.is_action_pressed("back"):
				#if current_state != "Sprinting":
					#_set_state("Sprinting")
			## Otherwise walk
			#elif current_state != "Walking":
				#_set_state("Walking")
#
#func _handle_walking(delta: float) -> void:
	### Logic for walking state
	#
	## Change Speed
	#current_speed_modifier = lerp(get_move_speed(), walk_speed, delta * (lerp_speed / 3))
#
#func _handle_sprinting(delta: float) -> void:
	## Logic for sprinting state
	#
	## Change Speed
	#current_speed_modifier = lerp(current_speed_modifier, sprinting_speed_modifier, delta*(lerp_speed/3))
#	
#func _handle_crouching(delta: float) -> void:
	## Logic for crouching state
	#
	## Change Speed
	#current_speed_modifier = lerp(current_speed_modifier, crouching_speed_modifier, delta*(lerp_speed/3))
#
#@warning_ignore("unused_parameter")
#func _handle_sliding(delta: float, input_dir) -> void:
	#
	### Handle slide
	#slide_timer -= delta
	#
	#velocity = Vector3(slide_vector.x, velocity.y, slide_vector.y)
	##position.y -= 0.1  # Adjust position for smooth sliding
	#
	#direction = transform.basis * Vector3(slide_vector.x, 0, slide_vector.y).normalized()
	##current_speed_modifier = slide_speed * (slide_timer / slide_timer_max)
#
	## Handle slide jumping
	#if Input.is_action_pressed("jump") and is_on_floor():
		#velocity.y += jump_velocity
	#
	## End sliding
	#if slide_timer <= 0 or Input.is_action_just_released("crouch"):
		#slide_cooldown_timer = slide_cooldown_max
		#slide_timer = slide_timer_max
#
#@warning_ignore("unused_parameter")
#func _handle_wall_running(delta: float) -> void:
#
	### Transition to another state
	#if is_on_floor() || Input.is_action_just_released("jump") \
	#&& (!left.is_colliding() || !right.is_colliding()):
		#if Input.is_action_pressed("sprint"):
			#_set_state("Sprinting")
		#else:
			#_set_state("Walking")
#
	### WALL RUNNING LOGIC
	#if current_state == "WallRunning":
#
		## Disable Gravity
		#velocity.y = 0 
#
		### Stick the player to either the left or right wall
		#if right.is_colliding():
				#var wall_normal = right.get_collision_normal()
				#velocity = velocity.slide(wall_normal)
		#elif left.is_colliding():
				#var wall_normal = left.get_collision_normal()
				#velocity = velocity.slide(wall_normal)
#
#func _set_state(new_state: String) -> void:
	#if new_state in PLAYER_STATE:
		#current_state = new_state
		#print("State changed to: ", current_state)
	#else:
		#print("Invalid state: ", new_state)
#
#func _handle_wall_running_camera_tilt(delta):
#
	#if current_state == "WallRunning":
		## Change camera tilt
		#if right.is_colliding():
			#head.rotation.z = lerp(head.rotation.y, 1.0, delta*lerp_speed)
		#elif left.is_colliding():
			#head.rotation.z = lerp(head.rotation.y, -1.0, delta*lerp_speed)
#
	#else:
		## Revert Changes
		#head.rotation.z = lerp(head.rotation.z, 0.0, delta*lerp_speed)
		#head.rotation.y = lerp(head.rotation.y, 0.0, delta*lerp_speed)
#
#func _handle_cooldowns(delta):
	### Update timers and cooldowns
#
	## This timer delays the amount of time between wall runs
	## disallowing the player from infinitely jumping up a wall
	#if wall_jump_cooldown > 0.0 && current_state != "WallRunning":
		#wall_jump_cooldown -= delta
#
	### This timer allows the player to gain height before initiating the wall run
	#if is_on_floor():
		#if Input.is_action_just_pressed("jump"): # Start timer when the player jumps
			#wall_run_timer = JUMP_TO_WALL_RUN_TIMER
	#elif wall_run_timer >= 0: # Update wall_run_timer if in the air
		#wall_run_timer -= delta
#
#@rpc("any_peer")
#func play_gun_animations(input_dir):
	#if gun_animations.current_animation == "Pistol_Shoot":
		#pass
	#elif input_dir != Vector2.ZERO and is_on_floor():
		#gun_animations.play("Pistol_Move")
	#else:
		#gun_animations.play("Pistol_Idle")
#
#@rpc("call_local")
#func play_pistol_shoot_effect():
	#gun_animations.stop()
	#gun_animations.play("Pistol_Shoot")
	#muzzle_flash.restart()
	#muzzle_flash.emitting = true
#
#@rpc("any_peer")
#@warning_ignore("shadowed_variable")
#func receive_damage(damage):
	#health -= damage
	#if health <= 0:
		#position = Vector3.ZERO
		#health = 100
	#health_changed.emit(health)
#
#@rpc("any_peer")
#func _on_gun_animations_animation_finished(anim_name: StringName) -> void:
	#if anim_name == "Pistol_Shoot":
		#gun_animations.play("Pistol_Idle")
	
