extends Node2D

const LINE_SPEED: int = 320
const LINE_WIDTH: int = 320
const TARGET_MODIFICATOR: int = 285 # сдвиг для попадания сигнала в пик картинки
const CONFIG_FILE: String = "user://scores.cfg"

var high_score: int = 0
var score: int = 0:
	set(new_value):
		score = new_value
		score_label.text = str(score)
var is_started: bool = false # линия ритма запущена
var is_dead: bool = false # жизнь закончилась
var in_hit_animation: bool = false # выполняется анимация нажатия
var pressed_on_hit: bool = false # было нажатие в текущем периоде
var target_pos: float = 360 # текущая координата начала линии учитывая повторы
var modulate_a: int = 255: # текущий уровень прозрачности/остаток жизни
	set(new_value):
		modulate_a = clampi(new_value, 0, 255)

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var audio_stream_player: AudioStreamPlayer = $AudioStreamPlayer
@onready var score_label: Label = $UI/ScoreLabel
@onready var high_score_label: Label = $UI/CenterContainer/HighScoreLabel
@onready var center_container: CenterContainer = %CenterContainer
@onready var line: TextureRect = %Line
@onready var timer: Timer = %Timer
@onready var color_rect: ColorRect = %ColorRect


func _ready() -> void:
	read_score()
	center_container.scale = Vector2.ZERO
	center_container.show()
	animation_player.play("show_high_score")
	await animation_player.animation_finished
	#if not is_started: 
	start()


func _unhandled_input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		if is_started: # в процессе игры - выход
			check_write_high_score()
			get_tree().quit()
		elif not is_dead: # во время показа рекорда - переход к игре
			animation_player.stop()
			animation_player.animation_finished.emit()
		elif is_dead: # во время длинного сигнала - переход в демо-сцену
			to_demo()
	elif (is_started and (event is InputEventMouseButton or event is InputEventKey)
			and not in_hit_animation and not is_dead):
		if event.is_pressed():
			pressed_on_hit = true
			check_hit()


func _physics_process(delta: float) -> void:
	if is_started:
		line.position.x -= LINE_SPEED * delta
		line.size.x += LINE_SPEED * delta
		if line.position.x <= target_pos:
			target_pos -= LINE_WIDTH
			audio_stream_player.play(.4)
			await get_tree().create_timer(.3).timeout
			audio_stream_player.stop()
			if not pressed_on_hit:
				check_hit()
			else:
				pressed_on_hit = false
		if line.position.x < -LINE_WIDTH:
			target_pos += LINE_WIDTH
			line.position.x += LINE_WIDTH
			line.size.x -= LINE_WIDTH


func start() -> void:
	# проигрываем беззвучно файл, чтобы подгрузить заранее и не было пролага в игре
	var current_volume = audio_stream_player.volume_db
	print(current_volume)
	audio_stream_player.volume_db = -80
	audio_stream_player.play(0)
	audio_stream_player.stop()
	audio_stream_player.volume_db = current_volume
	
	is_started = true
	center_container.hide()
	timer.start()
	color_rect.show()
	score_label.show()


func check_write_high_score() -> void:
	if score > high_score:
		high_score = score
		write_score()


func to_demo() -> void:
	check_write_high_score()
	get_tree().change_scene_to_file("res://demo/demo.tscn")


func check_hit() -> void:
	var delta_pos: float = absf(line.position.x - target_pos - TARGET_MODIFICATOR)
	if delta_pos <= 5:
		hit_animation("Perfect")
	elif delta_pos <= 10:
		modulate_a -= 2
		line.self_modulate.a = modulate_a / 255.0
		hit_animation("Good")
	elif delta_pos <= 25:
		modulate_a -= 5
		line.self_modulate.a = modulate_a / 255.0
		hit_animation("Bad")
	else:
		modulate_a -= 10
		line.self_modulate.a = modulate_a / 255.0
		hit_animation("Miss")

	if modulate_a <= 0:
		is_dead = true
		is_started = false
		timer.stop()
		await get_tree().create_timer(.3).timeout # пауза чтобы закончился короткий пииик
		audio_stream_player.play(15)
		score_label.hide()
		color_rect.hide()
		var tween = create_tween()
		tween.tween_property(audio_stream_player, "volume_db", -11, 13)
		await get_tree().create_timer(13).timeout
		to_demo()


func hit_animation(anim_name: String) -> void:
	if modulate_a <= 0: # конец игры
		return
	in_hit_animation = true
	var cur_color = line.self_modulate
	var anim_color = Color.BLACK
	match anim_name:
		"Perfect":
			anim_color = Color.GREEN
		"Good":
			anim_color = Color.YELLOW
		"Bad":
			anim_color = Color.RED
	var tween: = create_tween().set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(line, "self_modulate", anim_color, 0.1)
	tween.tween_property(line, "self_modulate", cur_color, 0.1)
	await tween.finished
	in_hit_animation = false


# читаем предыдущий рекорд
func read_score() -> void:
	var config = ConfigFile.new()
	if config.load(CONFIG_FILE) != OK:
		return
	high_score = config.get_value("SCORE", "score", 0)
	high_score_label.text = str(high_score)


# пишем новый рекорд
func write_score() -> void:
	var config = ConfigFile.new()
	config.set_value("SCORE", "score", high_score)
	config.save(CONFIG_FILE)


func _on_timer_timeout() -> void:
	score += 1
