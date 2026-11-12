
#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

cd "$HOME/Phantom-Ops"

echo "=== PHANTOM OPS INSTALLER ==="

# Project directories
mkdir -p \
  .github/workflows \
  project/scenes \
  project/scripts \
  project/assets/ui \
  build

# 1. Godot project configuration
cat > project/project.godot <<'EOF'
config_version=5

[application]
config/name="Phantom Ops"
run/main_scene="res://scenes/main_menu.tscn"
config/features=PackedStringArray("4.2", "Mobile")

[autoload]
GameManager="*res://scripts/game_manager.gd"

[display]
window/size/viewport_width=1920
window/size/viewport_height=1080
window/stretch/mode="viewport"
window/stretch/aspect="expand"
window/handheld/orientation=1

[rendering]
renderer/rendering_method="mobile"
renderer/rendering_method.mobile="mobile"
textures/default_filters/use_nearest_mipmap_filter=false
EOF

# 2. Player controller
cat > project/scripts/player.gd <<'EOF'
extends CharacterBody3D

signal health_changed(current, maximum)
signal player_died

@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.5
@export var jump_velocity: float = 4.5
@export var max_health: float = 100.0

var current_health: float = 100.0
var is_dead: bool = false
var gravity: float = 9.8
var mobile_move: Vector2 = Vector2.ZERO

@onready var camera: Camera3D = $Head/Camera3D

func _ready():
    current_health = max_health

func _physics_process(delta):
    if is_dead:
        return

    if not is_on_floor():
        velocity.y -= gravity * delta

    var input_dir = mobile_move

    if OS.get_name() not in ["Android", "iOS"]:
        input_dir = Input.get_vector(
            "ui_left", "ui_right", "ui_up", "ui_down"
        )

    var direction = (
        transform.basis * Vector3(input_dir.x, 0, input_dir.y)
    ).normalized()

    var speed = walk_speed

    if Input.is_action_pressed("ui_accept"):
        speed = sprint_speed

    velocity.x = direction.x * speed
    velocity.z = direction.z * speed

    if Input.is_action_just_pressed("ui_select") and is_on_floor():
        velocity.y = jump_velocity

    move_and_slide()

func take_damage(damage: float):
    if is_dead:
        return

    current_health = maxf(0.0, current_health - damage)
    health_changed.emit(current_health, max_health)

    if current_health <= 0:
        is_dead = true
        player_died.emit()
EOF

# 3. Procedural Kasserine city generator
cat > project/scripts/kasserine_city_generator.gd <<'EOF'
extends Node3D
class_name KasserineCityGenerator

@export var city_size: Vector2 = Vector2(120, 120)
@export var building_count: int = 25

var mat_sand = StandardMaterial3D.new()
var mat_wall = StandardMaterial3D.new()

func _ready():
    randomize()

    mat_sand.albedo_color = Color(0.82, 0.72, 0.55)
    mat_wall.albedo_color = Color(0.78, 0.68, 0.55)

    _build_city()

func _build_city():
    # Ground
    var ground = StaticBody3D.new()
    ground.name = "Ground"

    var ground_mesh = MeshInstance3D.new()
    var plane = PlaneMesh.new()
    plane.size = city_size * 2.0
    plane.material = mat_sand
    ground_mesh.mesh = plane
    ground.add_child(ground_mesh)

    var ground_collision = CollisionShape3D.new()
    var ground_shape = BoxShape3D.new()
    ground_shape.size = Vector3(
        city_size.x * 2.0, 0.2, city_size.y * 2.0
    )
    ground_collision.shape = ground_shape
    ground_collision.position.y = -0.1
    ground.add_child(ground_collision)

    add_child(ground)

    # Buildings
    for i in range(building_count):
        _create_building(i)

    # Sun
    var sun = DirectionalLight3D.new()
    sun.name = "Sun"
    sun.rotation_degrees = Vector3(-45, 30, 0)
    sun.shadow_enabled = true
    sun.light_energy = 1.0
    add_child(sun)

func _create_building(index: int):
    var building = StaticBody3D.new()
    building.name = "Building_%02d" % index

    var mesh_instance = MeshInstance3D.new()
    var box = BoxMesh.new()

    var sx = randf_range(6.0, 14.0)
    var sy = randf_range(4.0, 12.0)
    var sz = randf_range(6.0, 14.0)

    box.size = Vector3(sx, sy, sz)
    box.material = mat_wall

    mesh_instance.mesh = box
    mesh_instance.position.y = sy / 2.0
    building.add_child(mesh_instance)

    var collision = CollisionShape3D.new()
    var shape = BoxShape3D.new()
    shape.size = box.size
    collision.shape = shape
    collision.position.y = sy / 2.0
    building.add_child(collision)

    # Keep the central spawn area clear.
    var position := Vector3.ZERO

    for attempt in range(30):
        position = Vector3(
            randf_range(-45, 45),
            0,
            randf_range(-45, 45)
        )

        if position.length() > 18.0:
            break

    building.position = position
    add_child(building)
EOF

# 4. Enemy AI
cat > project/scripts/enemy_ai.gd <<'EOF'
extends CharacterBody3D
class_name EnemyAI

signal enemy_died(enemy)

@export var max_health: float = 60.0
@export var speed: float = 3.5
@export var damage: float = 10.0

var current_health: float = 60.0
var target: Node3D = null
var is_dead: bool = false
var gravity: float = 9.8

func _ready():
    current_health = max_health

func _physics_process(delta):
    if is_dead:
        return

    if not is_on_floor():
        velocity.y -= gravity * delta

    if not is_instance_valid(target):
        velocity.x = 0
        velocity.z = 0
        move_and_slide()
        return

    var difference = target.global_position - global_position
    var distance = difference.length()

    if distance > 0.1:
        var direction = difference.normalized()
        velocity.x = direction.x * speed
        velocity.z = direction.z * speed

    if distance < 2.0 and target.has_method("take_damage"):
        target.take_damage(damage * delta)

    move_and_slide()

func take_damage(amount: float):
    if is_dead:
        return

    current_health -= amount

    if current_health <= 0:
        is_dead = true
        enemy_died.emit(self)
        queue_free()
EOF

# 5. Game manager
cat > project/scripts/game_manager.gd <<'EOF'
extends Node

var score: int = 0
var kills: int = 0

func add_score(points: int):
    score += points

func add_kill():
    kills += 1

func reset_game():
    score = 0
    kills = 0
EOF

# 6. Main menu controller
cat > project/scripts/main_menu.gd <<'EOF'
extends Control

func _ready():
    $Play.pressed.connect(_on_deploy_pressed)

func _on_deploy_pressed():
    get_tree().change_scene_to_file(
        "res://scenes/main_game.tscn"
    )
EOF

# 7. Main menu scene
cat > project/scenes/main_menu.tscn <<'EOF'
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/main_menu.gd" id="1"]

[node name="MainMenu" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
script = ExtResource("1")

[node name="BG" type="ColorRect" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
color = Color(0.07, 0.075, 0.09, 1)

[node name="Title" type="Label" parent="."]
layout_mode = 1
anchors_preset = 5
anchor_left = 0.5
anchor_right = 0.5
offset_left = -350.0
offset_top = 120.0
offset_right = 350.0
offset_bottom = 190.0
theme_override_font_sizes/font_size = 36
text = "PHANTOM OPS"
horizontal_alignment = 1

[node name="Subtitle" type="Label" parent="."]
layout_mode = 1
anchors_preset = 5
anchor_left = 0.5
anchor_right = 0.5
offset_left = -250.0
offset_top = 195.0
offset_right = 250.0
offset_bottom = 235.0
text = "KASSERINE - OPERATIONS"
horizontal_alignment = 1

[node name="Play" type="Button" parent="."]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -130.0
offset_top = -25.0
offset_right = 130.0
offset_bottom = 35.0
theme_override_font_sizes/font_size = 24
text = "DEPLOY"
EOF

# 8. Main gameplay scene
cat > project/scenes/main_game.tscn <<'EOF'
[gd_scene load_steps=4 format=3]

[ext_resource type="Script" path="res://scripts/kasserine_city_generator.gd" id="1"]
[ext_resource type="Script" path="res://scripts/player.gd" id="2"]

[sub_resource type="CapsuleShape3D" id="CapsuleShape3D_player"]
radius = 0.4
height = 1.8

[node name="MainGame" type="Node3D"]

[node name="City" type="Node3D" parent="."]
script = ExtResource("1")

[node name="Player" type="CharacterBody3D" parent="."]
position = Vector3(0, 0.95, 10)
script = ExtResource("2")

[node name="CollisionShape3D" type="CollisionShape3D" parent="Player"]
shape = SubResource("CapsuleShape3D_player")

[node name="Head" type="Node3D" parent="Player"]
position = Vector3(0, 0.55, 0)

[node name="Camera3D" type="Camera3D" parent="Player/Head"]
current = true
position = Vector3(0, 0, 0)
EOF

# 9. Android export preset
cat > project/export_presets.cfg <<'EOF'
[preset.0]

name="Android"
platform="Android"
runnable=true
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path="../build/PhantomOps.apk"
encryption_include_filters=""
encryption_exclude_filters=""
encrypt_pck=false
encrypt_directory=false

[preset.0.options]

custom_template/debug=""
custom_template/release=""
gradle_build/use_gradle_build=false
gradle_build/export_format=0
gradle_build/min_sdk="24"
gradle_build/target_sdk="33"
architectures/armeabi-v7a=false
architectures/arm64-v8a=true
architectures/x86=false
architectures/x86_64=false
keystore/debug="debug.keystore"
keystore/debug_user="androiddebugkey"
keystore/debug_password="android"
keystore/release=""
keystore/release_user=""
keystore/release_password=""
version/code=1
version/name="0.1.0"
package/unique_name="com.phantomops.kasserine"
package/name="Phantom Ops"
package/signed=true
package/classify_as_game=true
screen/immersive_mode=true
user_permissions/0="android.permission.VIBRATE"
user_permissions/1="android.permission.INTERNET"
EOF

# 10. GitHub Actions Android build
cat > .github/workflows/build-android.yml <<'EOF'
name: Build Phantom Ops Android APK

on:
  push:
    branches:
      - main
  workflow_dispatch:

permissions:
  contents: read

jobs:
  build:
    name: Build Godot Android APK
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Java 17
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'

      - name: Setup Android SDK
        uses: android-actions/setup-android@v3

      - name: Install Android SDK components
        run: |
          yes | sdkmanager --licenses || true
          sdkmanager \
            "platform-tools" \
            "platforms;android-33" \
            "build-tools;33.0.2"

      - name: Install Godot 4.2.2
        run: |
          wget -q \
            https://github.com/godotengine/godot/releases/download/4.2.2-stable/Godot_v4.2.2-stable_linux.x86_64.zip \
            -O godot.zip

          unzip -q godot.zip

          sudo install \
            Godot_v4.2.2-stable_linux.x86_64 \
            /usr/local/bin/godot

          godot --version

      - name: Install Godot export templates
        run: |
          mkdir -p ~/.local/share/godot/export_templates/4.2.2.stable

          wget -q \
            https://github.com/godotengine/godot/releases/download/4.2.2-stable/Godot_v4.2.2-stable_export_templates.tpz \
            -O templates.tpz

          mkdir templates
          unzip -q templates.tpz -d templates

          cp -r templates/templates/. \
            ~/.local/share/godot/export_templates/4.2.2.stable/

      - name: Configure Android signing
        run: |
          keytool -genkeypair \
            -v \
            -keystore project/debug.keystore \
            -alias androiddebugkey \
            -keyalg RSA \
            -keysize 2048 \
            -validity 10000 \
            -storepass android \
            -keypass android \
            -dname "CN=Android Debug,O=Android,C=US"

          mkdir -p ~/.config/godot

          cat > ~/.config/godot/editor_settings-4.tres <<EOF2
          [gd_resource type="EditorSettings" format=3]

          [resource]
          export/android/android_sdk_path = "$ANDROID_HOME"
          export/android/java_sdk_path = "$JAVA_HOME"
          export/android/debug_keystore = "$GITHUB_WORKSPACE/project/debug.keystore"
          export/android/debug_keystore_user = "androiddebugkey"
          export/android/debug_keystore_pass = "android"
          EOF2

      - name: Validate and import project
        run: |
          godot --headless \
            --editor \
            --path project \
            --quit

      - name: Export Android APK
        run: |
          mkdir -p build

          godot --headless \
            --path project \
            --export-debug \
            "Android" \
            "$GITHUB_WORKSPACE/build/PhantomOps.apk"

          test -s build/PhantomOps.apk

      - name: Upload APK artifact
        uses: actions/upload-artifact@v4
        with:
          name: PhantomOps-Release-APK
          path: build/PhantomOps.apk
          if-no-files-found: error
          retention-days: 14
EOF

# 11. Git ignore
cat > .gitignore <<'EOF'
.godot/
build/
*.tmp
*.log
EOF

echo
echo "=================================="
echo " PHANTOM OPS FILES CREATED"
echo "=================================="
echo
echo "Project: $HOME/Phantom-Ops/project"
echo "Workflow: .github/workflows/build-android.yml"
echo "APK artifact: PhantomOps-Release-APK"
echo
echo "Next: validate the project and push to GitHub."
