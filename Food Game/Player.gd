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
@onready var front: RayCast3D = $Checks/Front
@onready var front_right: RayCast3D = $Checks/Front_right
@onready var right: RayCast3D = $Checks/Right
@onready var back_right: RayCast3D = $Checks/Back_right
@onready var back: RayCast3D = $Checks/Back
@onready var back_left: RayCast3D = $Checks/Back_left
@onready var left: RayCast3D = $Checks/Left
@onready var front_left: RayCast3D = $Checks/Front_left

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
	if Input.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	if Input.is_action_pressed("shoot"):
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	# Mouse Looking Logic
	if event is InputEventMouseMotion:
		if is_free_looking:
			neck.rotate_y(deg_to_rad(-event.relative.x * mouse_sens))
			neck.rotation.y = clamp(neck.rotation.y, deg_to_rad(-120), deg_to_rad(120))
		else:
			rotate_y(deg_to_rad(-event.relative.x * mouse_sens))
		head.rotate_x(deg_to_rad(-event.relative.y * mouse_sens))
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))
func slide(delta, input_dir):
	# Update slide cooldown timer
	if slide_cooldown_timer > 0:
		slide_cooldown_timer -= delta
	
	# Initiate slide
	if Input.is_action_just_pressed("crouch") and current_speed > walking_speed and is_on_floor() and input_dir != Vector2.ZERO and slide_cooldown_timer <= 0:
		is_sliding = true
		can_crouch = false
		is_free_looking = false
		
		animation_player.play("Slide")
		
		slide_vector = input_dir
		slide_timer = slide_timer_max
	
	# Handle sliding state
	if is_sliding:
		
		slide_timer -= delta
		
		if slide_timer <= 0 or Input.is_action_just_released("crouch"):
			is_sliding = false
			is_crouching = slide_timer > 0 && Input.is_action_just_released("crouch")
			is_walking = false if is_crouching else true
			is_sprinting = false
			is_free_looking = false
			
			can_crouch = true
			can_slide = false
			
			slide_cooldown_timer = slide_cooldown_max  # Start the cooldown
func wall_run(delta):
	
	if is_on_floor() && Input.is_action_just_pressed("jump"):
		# Start timer when the player jumps
		wall_run_timer = JUMP_TO_WALL_RUN_TIMER
	
	# Update wall_run_timer if in the air
	if !is_on_floor() and wall_run_timer >= 0:
		wall_run_timer -= delta
	
	# Check wall run conditions and timer
	if (right.is_colliding() or left.is_colliding()) and wall_run_timer <= 0:
		if Input.is_action_pressed("jump") and Input.is_action_pressed("forward"):
			is_wall_running = true
			is_sliding = false
			is_free_looking = true
			velocity.y = 0
			
			if velocity.length() < MIN_WALL_RUN_SPEED:
				is_wall_running = false
				head.rotation.y = lerp(neck.rotation.y, 0.0, delta*lerp_speed)
			# Raycasting to check for wall collision
			else:
				if right.is_colliding() and !front_right.is_colliding():
					# Move player to the right until ray: right_front.is_colliding is false
					translate(Vector3.RIGHT * delta)  # Adjust this line as needed for your game
					
					#rotate the head
					head.rotation.z = lerp(head.rotation.z, 12.0, delta*lerp_speed)
					
				elif left.is_colliding() and !front_left.is_colliding():
					# Move player to the left until ray: left_front.is_colliding is false
					translate(Vector3.LEFT * delta)  # Adjust this line as needed for your game
					
					#rotate the head
					head.rotation.z = lerp(head.rotation.z, -12.0, delta*lerp_speed)
	else:
		is_wall_running = false
		# rotate the head back
		head.rotation.z = lerp(neck.rotation.z, 0.0, delta*lerp_speed)
	
	# Handle Wall Run Jump
	if Input.is_action_just_released("jump") && left.is_colliding():
		is_wall_running = false
		# Apply jump force
		velocity.y += jump_velocity
		# apply a left force (away from wall)
		velocity.x += jump_velocity * 1.0
		wall_run_timer = 0  # End wall run immediately
	elif Input.is_action_just_released("jump") && right.is_colliding():
		is_wall_running = false
		# Apply jump force
		velocity.y += jump_velocity
		# apply a left force (away from wall)
		velocity.x += jump_velocity * -1.0
		wall_run_timer = 0  # End wall run immediately
func movement_states(delta):
	# Handle Movement States
	# crouching
	if (is_on_floor() && Input.is_action_pressed("crouch")) && can_crouch || is_sliding:
		# crouching
		current_speed = lerp(current_speed, crouching_speed, delta*lerp_speed)
		
		head.position.y = lerp(head.position.y, crouching_depth, delta*lerp_speed)
		
		standing_collision_shape.disabled = true
		crouching_collision_shape.disabled = false
		
		is_walking  = false
		is_sprinting = false
		is_crouching = true
		
	elif !ray_cast_ceiling.is_colliding() && is_on_floor():
		
		# standing
		head.position.y = lerp(head.position.y, 0.0, delta*(lerp_speed/3))
		
		standing_collision_shape.disabled = false
		crouching_collision_shape.disabled = true
		
		if Input.is_action_pressed("sprint") && Input.is_action_pressed("forward") && !Input.is_action_pressed("left") && !Input.is_action_pressed("right") && !Input.is_action_pressed("back"):
			current_speed = lerp(current_speed, sprinting_speed, delta*(lerp_speed/3))
			is_walking  = false
			is_sprinting = true
			is_crouching = false
		else: 
			# walking
			current_speed = lerp(current_speed, walking_speed, delta*(lerp_speed/3))
			is_walking  = true
			is_sprinting = false
			is_crouching = false
func move(delta, input_dir):
	# Get the input direction
	input_dir = Input.get_vector("left", "right", "forward", "back")
	
	# Handle the movement
	if is_on_floor():
		direction = lerp(direction,(transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized(), delta*lerp_speed)
	else:
		direction = lerp(direction,(transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized(), delta*air_lerp_speed)
	
	if is_sliding:
		direction = transform.basis * Vector3(slide_vector.x, 0, slide_vector.y).normalized()
		current_speed = ((slide_timer + 0.7)) + current_speed
	
	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)
func free_look(delta):
	# Handle Free Looking
	if Input.is_action_pressed("free_look"):
		is_free_looking = true
		if is_sliding:
			# Allow free look to modify the camera rotation based on wall run status
			eyes.rotation.z = lerp(eyes.rotation.z, -deg_to_rad(-34.0), delta * lerp_speed)
		else:
			# Calculate tilt based on neck rotation and free look tilt amount
			eyes.rotation.z = lerp(eyes.rotation.z, -deg_to_rad(neck.rotation.y * free_look_tilt_amount), delta * lerp_speed)
	else:
		is_free_looking = false
		# Smoothly reset camera rotation to default
		eyes.rotation.z = lerp(eyes.rotation.z, 0.0, delta * lerp_speed)
		neck.rotation.y = lerp(neck.rotation.y, 0.0, delta * lerp_speed)
func head_bob(input_dir, delta):
	# Handle Head bob
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
func jump():
	# Handle jump.
	# Normal
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = velocity.y + jump_velocity + (current_speed/10)
		can_crouch = true
		animation_player.play("Jump")
	
	# Air control
	if Input.is_action_just_pressed("left") && Input.is_action_just_pressed("right") && Input.is_action_just_pressed("back"):
		air_lerp_speed = 10.0
	else:
		air_lerp_speed = 1.0
func _physics_process(delta):
	# Get the input direction
	var input_dir = Input.get_vector("left", "right", "forward", "back")
	
	slide(delta, input_dir)
	jump()
	head_bob(input_dir, delta)
	free_look(delta)
	move(delta, input_dir)
	movement_states(delta)
	wall_run(delta)
	
	# Add the gravity.
	if not is_on_floor():
		velocity.y -= (gravity * delta)
	
	# Handle landing
	if last_velocity.y <= -6.0 && is_on_floor():
		animation_player.play("Landing")
	
	last_velocity = velocity
	
	move_and_slide()
