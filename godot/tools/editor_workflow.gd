extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var shell: Control = load("res://src/editor_shell.tscn").instantiate()
	root.add_child(shell)
	await shell.startup_completed
	await preload("res://verification/workflow_driver.gd").new().run_on_shell(shell)
