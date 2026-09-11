extends LibSM64Mario
class_name RLMario

var rl_stick := Vector2.ZERO
var rl_cam_look := Vector2(0, -1)
var rl_button_a := false
var rl_button_b := false
var rl_button_z := false

func _make_mario_inputs() -> LibSM64MarioInputs:
	var mario_inputs := LibSM64MarioInputs.new()

	mario_inputs.stick = rl_stick
	mario_inputs.cam_look = rl_cam_look

	mario_inputs.button_a = rl_button_a
	mario_inputs.button_b = rl_button_b
	mario_inputs.button_z = rl_button_z

	return mario_inputs
