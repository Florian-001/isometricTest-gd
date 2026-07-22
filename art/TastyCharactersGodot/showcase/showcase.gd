extends Node2D

const PACKS := ["castle", "forest", "sea", "village"]
const PACK_LABELS := ["Castle", "Forest", "Sea", "Village"]
const CHARACTER_COUNT := 16
const COLUMN_WIDTH := 145.0
const ROW_HEIGHT := 170.0
const START := Vector2(120.0, 150.0)

@onready var camera: Camera2D = $Camera2D
var dragging := false


func _ready() -> void:
    for pack_index in PACKS.size():
        var label := Label.new()
        label.text = PACK_LABELS[pack_index]
        label.position = Vector2(20.0, START.y + pack_index * ROW_HEIGHT - 85.0)
        label.add_theme_font_size_override("font_size", 20)
        label.add_theme_color_override("font_color", Color(0.8, 0.86, 0.96))
        add_child(label)
        for character_index in CHARACTER_COUNT:
            var path := "res://characters/reference/%s/chara_%02d.tscn" % [PACKS[pack_index], character_index]
            var packed := load(path) as PackedScene
            if packed == null:
                continue
            var character := packed.instantiate()
            character.position = START + Vector2(character_index * COLUMN_WIDTH, pack_index * ROW_HEIGHT)
            add_child(character)


func _process(delta: float) -> void:
    var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
    camera.position += direction * 520.0 * delta / camera.zoom.x
    camera.position.x = clampf(camera.position.x, 320.0, 2200.0)
    camera.position.y = clampf(camera.position.y, 250.0, 610.0)


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT:
            dragging = event.pressed
        elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
            camera.zoom = (camera.zoom * 1.1).clamp(Vector2(0.6, 0.6), Vector2(2.0, 2.0))
        elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            camera.zoom = (camera.zoom / 1.1).clamp(Vector2(0.6, 0.6), Vector2(2.0, 2.0))
    elif event is InputEventMouseMotion and dragging:
        camera.position -= event.relative / camera.zoom
    elif event is InputEventKey and event.pressed and event.keycode == KEY_R:
        camera.position = Vector2(640.0, 360.0)
        camera.zoom = Vector2.ONE
