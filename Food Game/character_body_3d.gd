extends CharacterBody3D

# Player Nodes

@onready var neck: Node3D = $neck
@onready var head: Node3D = $neck/Head
@onready var eyes: Node3D = $neck/Head/Eyes
@onready var player_camera: Camera3D = $neck/Head/Eyes/PlayerCamera

@onready var crouching_collision_shape: CollisionShape3D = $CrouchingCollisionShape
@onready var standing_collision_shape: CollisionShape3D = $StandingCollisionShape

@onready var animation_player: AnimationPlayer = $neck/Head/Eyes/AnimationPlayer

# RayCast Nodes

@onready var ray_cast_ceiling: RayCast3D = $RayCastCeiling
@onready var right: RayCast3D = $Checks/Right
@onready var left: RayCast3D = $Checks/Left

# Speed Vars
var current_speed = 5.0
const walking_speed = 5.0
const sprinting_speed = 8.0
const crouching_speed = 2.0

var lerp_speed = 10.0
var air_lerp_speed = 4.0

# Input Vars
const mouse_sens = 0.3
var direction = Vector3.ZERO

# Movement vars
var crouching_depth = -0.8

const jump_velocity = 4.5
var last_velocity = Vector3.ZERO
var free_look_tilt_amount = 10

# Slide Vars
var slide_timer = 0.0
var slide_timer_max = 1.0
var slide_vector = Vector2.ZERO
var slide_cooldown_timer = 0.0
var slide_cooldown_max = 0.3
var can_slide = false

# States
var is_walking  = false
var is_sprinting = false
var is_crouching = false
var is_free_looking = false
var is_sliding = false
var is_wall_running = false
var can_crouch = true

# Head Bobbing Vars
const head_bobbing_sprinting_speed = 22.0
const head_bobbing_walking_speed = 14.0
const head_bobbing_crouching_speed = 10.0

const head_bobbing_sprinting_intensity = 0.2
const head_bobbing_walking_intensity = 0.1
const head_bobbing_crouching_intensity = 0.05

var head_bobbing_vector = Vector2.ZERO
var head_bobbing_index = 0.0
var head_bobbing_current_intensity = 0.0

## Wall Run Vars
var wall_run_timer = 0.0  # Timer variable to track time since last jump
const JUMP_TO_WALL_RUN_TIMER = 0.5  # Time buffer before sticking to the wall
const MIN_WALL_RUN_SPEED = 3.0

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event):
	
	## Mouse Looking Logic
	if event is InputEventMouseMotion:
		if is_free_looking:
			neck.rotate_y(deg_to_rad(-event.relative.x * mouse_sens))
			neck.rotation.x = clamp(head.rotation.x, deg_to_rad(-120), deg_to_rad(120))
		else:
			rotate_y(deg_to_rad(-event.relative.x * mouse_sens))
			head.rotate_x(deg_to_rad(-event.relative.y * mouse_sens))
			head.rotation.x = clamp(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))

func _physics_process(delta: float) -> void:
	
	## Get the input direction
	var input_dir := Input.get_vector("left", "right", "forward", "back")
	
	## Handle Movement State
	
	## Crouching
	if Input.is_action_pressed("crouch") || is_sliding:
		# Gradually set the current speed to the crouching speed
		current_speed = lerp(current_speed, crouching_speed, delta * lerp_speed)
		# change the player camera view to match that of the crouching_collision shape
		head.position.y = lerp(head.position.y, crouching_depth, delta * lerp_speed)
		
		# change the collidsion shape
		standing_collision_shape.disabled = true
		crouching_collision_shape.disabled = false
	
		## Slide INIT Logic
		if is_sprinting && input_dir != Vector2.ZERO:
			# set the state of the player
			is_sliding = true
			is_free_looking = true
			
			# start the slide timer
			slide_timer = slide_timer_max
			slide_vector = input_dir
			
			## DEBUG
			print("-- Slide Begin --")
		
		# set the state of the player
		is_walking = false
		is_sprinting = false
		is_crouching = true
	
	elif !ray_cast_ceiling.is_colliding():
		
		## Standing
		
		# change the player camera view to match that of the crouching_collision shape
		head.position.y = lerp(head.position.y, 0.0, delta*(lerp_speed/3))
		
		# change the collision shape
		standing_collision_shape.disabled = false
		crouching_collision_shape.disabled = true
		
		## Sprinting
		if Input.is_action_pressed("sprint"):
			is_sprinting = true
			is_walking = false
			is_crouching = false
			
			# Gradually set the current speed to the sprinting speed
			current_speed = lerp(current_speed, sprinting_speed, delta * lerp_speed)
		else:
			
			## Walking
			is_sprinting = false
			is_walking = true
			is_crouching = false
			
			# Gradually set the current speed to the walking speed
			current_speed = lerp(current_speed, walking_speed, delta * lerp_speed)
		
	
	## Handle Free Looking
	if Input.is_action_pressed("free_look") || is_sliding:
		is_free_looking = true
		
		if is_sliding:
			eyes.rotation.z = lerp(eyes.rotation.z, -deg_to_rad(7.0), delta * lerp_speed)
		else:
			eyes.rotation.z = -deg_to_rad(neck.rotation.y * free_look_tilt_amount)
		
	else:
		is_free_looking = false
		neck.rotation.y = lerp(neck.rotation.y, 0.0, delta * lerp_speed)
		eyes.rotation.z = lerp(eyes.rotation.z, 0.0, delta * lerp_speed)
	
	## Handle Sliding
	if is_sliding: 
		slide_timer -= delta
		if slide_timer <= 0.0:
			is_sliding = false
			is_free_looking = false
			
			## DEBUG
			print("-- Slide End --")
	
	## Handle Head Bob
	if is_sprinting:
		head_bobbing_current_intensity = head_bobbing_sprinting_intensity
		head_bobbing_index += head_bobbing_sprinting_speed * delta
	elif is_walking:
		head_bobbing_current_intensity = head_bobbing_walking_intensity
		head_bobbing_index += head_bobbing_walking_speed * delta
	elif is_crouching:
		head_bobbing_current_intensity = head_bobbing_crouching_intensity
		head_bobbing_index += head_bobbing_crouching_speed * delta
	
	if is_on_floor() && !is_sliding && input_dir != Vector2.ZERO:
		head_bobbing_vector.y = sin(head_bobbing_index)
		head_bobbing_vector.x = sin(head_bobbing_index / 2) + 0.5
		
		eyes.position.y = lerp(eyes.position.y, head_bobbing_vector.y * (head_bobbing_current_intensity / 2.0), delta * lerp_speed)
		eyes.position.x = lerp(eyes.position.x, head_bobbing_vector.x * head_bobbing_current_intensity, delta * lerp_speed)
	else:
		eyes.position.y = lerp(eyes.position.y, 0.0, delta * lerp_speed)
		eyes.position.x = lerp(eyes.position.x,  0.0, delta * lerp_speed)
	
	## Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	## Handle jump.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity
	
	## Handle landing
	if last_velocity.y <= -6.0 && is_on_floor():
		animation_player.play("Landing")
	
	last_velocity = velocity
	
	## Handle movement
	direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if is_sliding:
		direction = (transform.basis * Vector3(slide_vector.x, 0, input_dir.y)).normalized()
		current_speed = (slide_timer + 0.1) * current_speed
	
	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)
	
	move_and_slide()
