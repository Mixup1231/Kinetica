package input

import "base:runtime"
import "vendor:glfw"

Key :: struct {
	code:     Key_Code,
	modifier: Key_Modifiers,
	action:   Key_Action,
}

Mapping_Context :: struct {
	toggles: map[Key]Toggle,
	binds:   map[Key]proc(),
}

@(private)
Key_Code :: enum i32 {
	A             = glfw.KEY_A,
	B             = glfw.KEY_B,
	C             = glfw.KEY_C,
	D             = glfw.KEY_D,
	E             = glfw.KEY_E,
	F             = glfw.KEY_F,
	G             = glfw.KEY_G,
	H             = glfw.KEY_H,
	I             = glfw.KEY_I,
	J             = glfw.KEY_J,
	K             = glfw.KEY_K,
	L             = glfw.KEY_L,
	M             = glfw.KEY_M,
	N             = glfw.KEY_N,
	O             = glfw.KEY_O,
	P             = glfw.KEY_P,
	Q             = glfw.KEY_Q,
	R             = glfw.KEY_R,
	S             = glfw.KEY_S,
	T             = glfw.KEY_T,
	U             = glfw.KEY_U,
	V             = glfw.KEY_V,
	W             = glfw.KEY_W,
	X             = glfw.KEY_X,
	Y             = glfw.KEY_Y,
	Z             = glfw.KEY_Z,
	_0            = glfw.KEY_0,
	_1            = glfw.KEY_1,
	_2            = glfw.KEY_2,
	_3            = glfw.KEY_3,
	_4            = glfw.KEY_4,
	_5            = glfw.KEY_5,
	_6            = glfw.KEY_6,
	_7            = glfw.KEY_7,
	_8            = glfw.KEY_8,
	_9            = glfw.KEY_9,
	SPACE         = glfw.KEY_SPACE,
	APOSTROPHE    = glfw.KEY_APOSTROPHE,
	COMMA         = glfw.KEY_COMMA,
	MINUS         = glfw.KEY_MINUS,
	PERIOD        = glfw.KEY_PERIOD,
	SLASH         = glfw.KEY_SLASH,
	SEMICOLON     = glfw.KEY_SEMICOLON,
	EQUAL         = glfw.KEY_EQUAL,
	LEFT_BRACKET  = glfw.KEY_LEFT_BRACKET,
	BACKSLASH     = glfw.KEY_BACKSLASH,
	RIGHT_BRACKET = glfw.KEY_RIGHT_BRACKET,
	GRAVE_ACCENT  = glfw.KEY_GRAVE_ACCENT,
	ESCAPE        = glfw.KEY_ESCAPE,
	ENTER         = glfw.KEY_ENTER,
	TAB           = glfw.KEY_TAB,
	BACKSPACE     = glfw.KEY_BACKSPACE,
	INSERT        = glfw.KEY_INSERT,
	DELETE        = glfw.KEY_DELETE,
	RIGHT         = glfw.KEY_RIGHT,
	LEFT          = glfw.KEY_LEFT,
	DOWN          = glfw.KEY_DOWN,
	UP            = glfw.KEY_UP,
	PAGE_UP       = glfw.KEY_PAGE_UP,
	PAGE_DOWN     = glfw.KEY_PAGE_DOWN,
	HOME          = glfw.KEY_HOME,
	END           = glfw.KEY_END,
	CAPS_LOCK     = glfw.KEY_CAPS_LOCK,
	SCROLL_LOCK   = glfw.KEY_SCROLL_LOCK,
	NUM_LOCK      = glfw.KEY_NUM_LOCK,
	PRINT_SCREEN  = glfw.KEY_PRINT_SCREEN,
	PAUSE         = glfw.KEY_PAUSE,
	F1            = glfw.KEY_F1,
	F2            = glfw.KEY_F2,
	F3            = glfw.KEY_F3,
	F4            = glfw.KEY_F4,
	F5            = glfw.KEY_F5,
	F6            = glfw.KEY_F6,
	F7            = glfw.KEY_F7,
	F8            = glfw.KEY_F8,
	F9            = glfw.KEY_F9,
	F10           = glfw.KEY_F10,
	F11           = glfw.KEY_F11,
	F12           = glfw.KEY_F12,
}

@(private)
Modifier :: enum i32 {
	Shift,
	Ctrl,
	Alt,
}
@(private)
Key_Modifiers :: bit_set[Modifier;i32]

@(private)
Key_Action :: enum i32 {
	Release = glfw.RELEASE,
	Press   = glfw.PRESS,
	Repeat  = glfw.REPEAT,
}

@(private)
Toggle :: struct {
	first:  proc(),
	second: proc(),
}

@(private)
Input_Context :: struct {
	odin_ctx:    runtime.Context,
	global_map:  Mapping_Context,
	current_map: ^Mapping_Context,
	initialised: bool,
}

