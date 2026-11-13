extends SceneTree

const MODELS := [
    "Zombie",
    "ZombieSmooth",
    "BaseCharacter",
    "BlueSoldier_Female",
    "BlueSoldier_Male",
    "Soldier_Female"
]

const REQUIRED := {
    "Zombie": ["ZombieIdle", "ZombieWalk", "ZombieRun"],
    "ZombieSmooth": ["ZombieIdle", "ZombieWalk", "ZombieRun"],
    "BaseCharacter": ["Idle", "Walk", "Run", "Shoot_OneHanded", "Death"],
    "BlueSoldier_Female": ["Idle", "Walk", "Run", "Shoot_OneHanded", "Death"],
    "BlueSoldier_Male": ["Idle", "Walk", "Run", "Shoot_OneHanded", "Death"],
    "Soldier_Female": ["Idle", "Walk", "Run", "Shoot_OneHanded", "Death"]
}

func _initialize() -> void:
    call_deferred("_validate")

func _validate() -> void:
    var errors: Array[String] = []
    var report: Array[String] = []

    report.append("PHANTOM OPS - QUATERNIUS CHARACTER VALIDATION")
    report.append("Godot 4.3 native FBX import")
    report.append("")

    for model in MODELS:
        var path := "res://assets/%s.fbx" % model
        print("\n========== ", model, " ==========")

        if not ResourceLoader.exists(path):
            errors.append("%s: source resource missing" % model)
            report.append("FAIL: %s - source missing" % model)
            continue

        var resource = ResourceLoader.load(path)

        if not resource is PackedScene:
            errors.append("%s: FBX did not import as PackedScene" % model)
            report.append("FAIL: %s - not a PackedScene" % model)
            continue

        var packed := resource as PackedScene
        var instance := packed.instantiate()

        var skeletons := instance.find_children(
            "*", "Skeleton3D", true, false
        )
        var players := instance.find_children(
            "*", "AnimationPlayer", true, false
        )

        var animations: Array[String] = []

        for node in players:
            var player := node as AnimationPlayer
            for animation_name in player.get_animation_list():
                if animation_name != "RESET":
                    animations.append(animation_name)

        print("Skeletons: ", skeletons.size())
        print("Animation players: ", players.size())
        print("Animations: ", animations)

        var model_errors: Array[String] = []

        if skeletons.is_empty():
            model_errors.append("Skeleton3D missing")

        if players.is_empty() or animations.is_empty():
            model_errors.append("AnimationPlayer or animations missing")

        for required_name in REQUIRED[model]:
            var found := false

            for actual_name in animations:
                if actual_name.contains(required_name):
                    found = true
                    break

            if not found:
                model_errors.append(
                    "Required animation missing: %s" % required_name
                )

        if model_errors.is_empty():
            print("RESULT: PASS")
            report.append("PASS: %s" % model)
        else:
            print("RESULT: FAIL - ", model_errors)
            for problem in model_errors:
                errors.append("%s: %s" % [model, problem])
            report.append("FAIL: %s - %s" % [
                model, ", ".join(model_errors)
            ])

        report.append("Skeletons: %d" % skeletons.size())
        report.append("Animations: %s" % ", ".join(animations))
        report.append("")

        instance.free()

    report.append("")
    report.append("TOTAL MODELS: %d" % MODELS.size())
    report.append("ERRORS: %d" % errors.size())

    var output := FileAccess.open(
        "res://validation-report.txt",
        FileAccess.WRITE
    )

    if output:
        output.store_string("\n".join(report))
        output.close()

    print("\n========================================")
    print("VALIDATION ERRORS: ", errors.size())
    print("========================================")

    if not errors.is_empty():
        for problem in errors:
            push_error(problem)
        quit(1)
    else:
        print("ALL SIX CHARACTER MODELS PASSED")
        quit(0)
