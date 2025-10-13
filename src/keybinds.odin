#+private file
#+feature dynamic-literals
package main

import "vendor:glfw"
import "core:strconv"

@(private="package")
KODERUM_KEY :: enum {
    /*
        MOVEMENT  
    */
    MOVE_UP,
    MOVE_DOWN,
    MOVE_LEFT,
    MOVE_RIGHT,
    MOVE_FORWARD_WORD,
    MOVE_BACKWARD_WORD,
    
    /*
      MODE SWITCHES  
    */
    TOGGLE_YANK_HISTORY_MODE,
    TOGGLE_HIGHLIGHT_MODE,
    TOGGLE_HELP_MODE,
    TOGGLE_BUFFER_INFO,
    TOGGLE_TERMINAL,
    
    ENTER_GREP_SEARCH_MODE,
    GREP_SEARCH_MODIFIER,
    
    ENTER_INSERT_MODE,
    ENTER_SEARCH_MODE,
    ENTER_FILE_BROWSER_MODE,
    ENTER_GO_TO_LINE_MODE,
    ENTER_FIND_AND_REPLACE_MODE,
    ENTER_TERMINAL_INSERT_MODE,
    
    /*
        FILE BROWSER
    */
    RENAME_FILE,
    DELETE_FILE,
    CREATE_FILE,
    GO_UP_DIRECTORY,
    SET_CWD,
    
    /*
        SWAP BETWEEN FILES
    */
    NEXT_FILE,
    PREVIOUS_FILE,
    
    RELOAD_FILE,
    CLOSE_FILE,
    
    /*
        LSP
    */
    RESTART_LSP,
    GO_TO_DEFINITION,
    PREVIOUS_COMPLETION,
    NEXT_COMPLETION,
    INSERT_COMPLETION,
    CUT_LINE,
    DELETE_LINE,
    
    YANK,
    CUT,
    DELETE,
    PASTE,
    INJECT_LINE,
    
    GO_TO_END,
    GO_TO_START,
    
    GO_BACK,
    
    REDO,
    UNDO,
    
    INDENT,
    UNINDENT,
    
    ESCAPE,
    EXIT,
    
    FILE_BROWSER_TOGGLE_EXPAND_FOLDERS,
    
    /*
        non-configurable,
        might be in the future though
    */
    REMOVE_CHARACTER,
    ENTER,
}

@(private="package")
KEY_CODE :: distinct i32

@(private="package")
mapped_keybinds : map[KODERUM_KEY]KEY_CODE = {
    .REMOVE_CHARACTER = glfw.KEY_BACKSPACE,
    .ENTER = glfw.KEY_ENTER,
}

@(private="package")
check_for_keybind :: proc(option_name: string, value: string) -> (do_continue: bool = true) {
    key := KEY_CODE(GLFW_Keymap[value])
    
    switch option_name {
    case "move_up":
        mapped_keybinds[.MOVE_UP] = key
    case "move_down":
        mapped_keybinds[.MOVE_DOWN] = key
    case "move_left":
        mapped_keybinds[.MOVE_LEFT] = key
    case "move_right":
        mapped_keybinds[.MOVE_RIGHT] = key
    case "move_forward_word":
        mapped_keybinds[.MOVE_FORWARD_WORD] = key
    case "move_backward_word":
        mapped_keybinds[.MOVE_BACKWARD_WORD] = key
    case "toggle_yank_history_mode":
        mapped_keybinds[.TOGGLE_YANK_HISTORY_MODE] = key
    case "toggle_highlight_mode":
        mapped_keybinds[.TOGGLE_HIGHLIGHT_MODE] = key
    case "toggle_help_mode":
        mapped_keybinds[.TOGGLE_HELP_MODE] = key
    case "toggle_buffer_info":
        mapped_keybinds[.TOGGLE_BUFFER_INFO] = key
    case "enter_insert_mode":
        mapped_keybinds[.ENTER_INSERT_MODE] = key
    case "enter_grep_search_mode":
        mapped_keybinds[.ENTER_GREP_SEARCH_MODE] = key
    case "grep_search_modifier":
        mapped_keybinds[.GREP_SEARCH_MODIFIER] = key
    case "enter_search_mode":
        mapped_keybinds[.ENTER_SEARCH_MODE] = key
    case "enter_file_browser_mode":
        mapped_keybinds[.ENTER_FILE_BROWSER_MODE] = key
    case "enter_go_to_line_mode":
        mapped_keybinds[.ENTER_GO_TO_LINE_MODE] = key
    case "enter_find_and_replace_mode":
        mapped_keybinds[.ENTER_FIND_AND_REPLACE_MODE] = key
    case "enter_terminal_insert_mode":
        mapped_keybinds[.ENTER_TERMINAL_INSERT_MODE] = key
    case "rename_file":
        mapped_keybinds[.RENAME_FILE] = key
    case "delete_file":
        mapped_keybinds[.DELETE_FILE] = key
    case "create_file":
        mapped_keybinds[.CREATE_FILE] = key
    case "go_up_directory":
        mapped_keybinds[.GO_UP_DIRECTORY] = key
    case "set_cwd":
        mapped_keybinds[.SET_CWD] = key
    case "next_file":
        mapped_keybinds[.NEXT_FILE] = key
    case "previous_file":
        mapped_keybinds[.PREVIOUS_FILE] = key
    case "reload_file":
        mapped_keybinds[.RELOAD_FILE] = key
    case "close_file":
        mapped_keybinds[.CLOSE_FILE] = key
    case "restart_lsp":
        mapped_keybinds[.RESTART_LSP] = key
    case "go_to_definition":
        mapped_keybinds[.GO_TO_DEFINITION] = key
    case "previous_completion":
        mapped_keybinds[.PREVIOUS_COMPLETION] = key
    case "next_completion":
        mapped_keybinds[.NEXT_COMPLETION] = key
    case "insert_completion":
        mapped_keybinds[.INSERT_COMPLETION] = key
    case "cut_line":
        mapped_keybinds[.CUT_LINE] = key
    case "delete_line":
        mapped_keybinds[.DELETE_LINE] = key
    case "yank":
        mapped_keybinds[.YANK] = key
    case "cut":
        mapped_keybinds[.CUT] = key
    case "delete":
        mapped_keybinds[.DELETE] = key
    case "paste":
        mapped_keybinds[.PASTE] = key
    case "toggle_terminal":
        mapped_keybinds[.TOGGLE_TERMINAL] = key
    case "inject_line":
        mapped_keybinds[.INJECT_LINE] = key
    case "go_to_end":
        mapped_keybinds[.GO_TO_END] = key
    case "go_to_start":
        mapped_keybinds[.GO_TO_START] = key
    case "go_back":
        mapped_keybinds[.GO_BACK] = key
    case "indent":
        mapped_keybinds[.INDENT] = key
    case "unindent":
        mapped_keybinds[.UNINDENT] = key
    case "redo":
        mapped_keybinds[.REDO] = key
    case "undo":
        mapped_keybinds[.UNDO] = key
    case "escape":
        mapped_keybinds[.ESCAPE] = key
    case "exit":
        mapped_keybinds[.EXIT] = key    
    case "file_browser_toggle_expand_folders":
        mapped_keybinds[.FILE_BROWSER_TOGGLE_EXPAND_FOLDERS] = key
    }
    
    return do_continue
}

@(private="package")
GLFW_Keymap := map[string]i32 {
	"space" = 32,
	"apostrophe" = 39,
	"comma" = 44,
	"minus" = 45,
	"period" = 46,
	"slash" = 47,
	"0" = 48,
	"1" = 49,
	"2" = 50,
	"3" = 51,
	"4" = 52,
	"5" = 53,
	"6" = 54,
	"7" = 55,
	"8" = 56,
	"9" = 57,
	"semicolon" = 59,
	"equal" = 61,
	"a" = 65,
	"b" = 66,
	"c" = 67,
	"d" = 68,
	"e" = 69,
	"f" = 70,
	"g" = 71,
	"h" = 72,
	"i" = 73,
	"j" = 74,
	"k" = 75,
	"l" = 76,
	"m" = 77,
	"n" = 78,
	"o" = 79,
	"p" = 80,
	"q" = 81,
	"r" = 82,
	"s" = 83,
	"t" = 84,
	"u" = 85,
	"v" = 86,
	"w" = 87,
	"x" = 88,
	"y" = 89,
	"z" = 90,
	"left_bracket" = 91,
	"backslash" = 92,
	"right_bracket" = 93,
	"grave_accent" = 96,
	"world_1" = 161,
	"world_2" = 162,
	"escape" = 256,
	"enter" = 257,
	"tab" = 258,
	"backspace" = 259,
	"insert" = 260,
	"delete" = 261,
	"right" = 262,
	"left" = 263,
	"down" = 264,
	"up" = 265,
	"page_up" = 266,
	"page_down" = 267,
	"home" = 268,
	"end" = 269,
	"caps_lock" = 280,
	"scroll_lock" = 281,
	"num_lock" = 282,
	"print_screen" = 283,
	"pause" = 284,
	"f1" = 290,
	"f2" = 291,
	"f3" = 292,
	"f4" = 293,
	"f5" = 294,
	"f6" = 295,
	"f7" = 296,
	"f8" = 297,
	"f9" = 298,
	"f10" = 299,
	"f11" = 300,
	"f12" = 301,
	"f13" = 302,
	"f14" = 303,
	"f15" = 304,
	"f16" = 305,
	"f17" = 306,
	"f18" = 307,
	"f19" = 308,
	"f20" = 309,
	"f21" = 310,
	"f22" = 311,
	"f23" = 312,
	"f24" = 313,
	"f25" = 314,
	"kp_0" = 320,
	"kp_1" = 321,
	"kp_2" = 322,
	"kp_3" = 323,
	"kp_4" = 324,
	"kp_5" = 325,
	"kp_6" = 326,
	"kp_7" = 327,
	"kp_8" = 328,
	"kp_9" = 329,
	"kp_decimal" = 330,
	"kp_divide" = 331,
	"kp_multiply" = 332,
	"kp_subtract" = 333,
	"kp_add" = 334,
	"kp_enter" = 335,
	"kp_equal" = 336,
	"left_shift" = 340,
	"left_control" = 341,
	"left_alt" = 342,
	"left_super" = 343,
	"right_shift" = 344,
	"right_control" = 345,
	"right_alt" = 346,
	"right_super" = 347,
	"menu" = 348,
}

@(private="package")
Human_Readable_Keys := map[KEY_CODE]string{
	32 = "Space",
	39 = "Apostrophe",
	44 = "Comma",
	45 = "Minus",
	46 = "Period",
	47 = "Slash",
	48 = "0",
	49 = "1",
	50 = "2",
	51 = "3",
	52 = "4",
	53 = "5",
	54 = "6",
	55 = "7",
	56 = "8",
	57 = "9",
	59 = "Semicolon",
	61 = "Equal",
	65 = "A",
	66 = "B",
	67 = "C",
	68 = "D",
	69 = "E",
	70 = "F",
	71 = "G",
	72 = "H",
	73 = "I",
	74 = "J",
	75 = "K",
	76 = "L",
	77 = "M",
	78 = "N",
	79 = "O",
	80 = "P",
	81 = "Q",
	82 = "R",
	83 = "S",
	84 = "T",
	85 = "U",
	86 = "V",
	87 = "W",
	88 = "X",
	89 = "Y",
	90 = "Z",
	91 = "Left Bracket",
	92 = "Backslash",
	93 = "Right Bracket",
	96 = "Grave Accent",
	161 = "World 1",
	162 = "World 2",
	256 = "Escape",
	257 = "Enter",
	258 = "Tab",
	259 = "Backspace",
	260 = "Insert",
	261 = "Delete",
	262 = "Right",
	263 = "Left",
	264 = "Down",
	265 = "Up",
	266 = "Page Up",
	267 = "Page Down",
	268 = "Home",
	269 = "End",
	280 = "Caps Lock",
	281 = "Scroll Lock",
	282 = "Num Lock",
	283 = "Print Screen",
	284 = "Pause",
	290 = "F1",
	291 = "F2",
	292 = "F3",
	293 = "F4",
	294 = "F5",
	295 = "F6",
	296 = "F7",
	297 = "F8",
	298 = "F9",
	299 = "F10",
	300 = "F11",
	301 = "F12",
	302 = "F13",
	303 = "F14",
	304 = "F15",
	305 = "F16",
	306 = "F17",
	307 = "F18",
	308 = "F19",
	309 = "F20",
	310 = "F21",
	311 = "F22",
	312 = "F23",
	313 = "F24",
	314 = "F25",
	320 = "Keypad 0",
	321 = "Keypad 1",
	322 = "Keypad 2",
	323 = "Keypad 3",
	324 = "Keypad 4",
	325 = "Keypad 5",
	326 = "Keypad 6",
	327 = "Keypad 7",
	328 = "Keypad 8",
	329 = "Keypad 9",
	330 = "Keypad Decimal",
	331 = "Keypad Divide",
	332 = "Keypad Multiply",
	333 = "Keypad Subtract",
	334 = "Keypad Add",
	335 = "Keypad Enter",
	336 = "Keypad Equal",
	340 = "Left Shift",
	341 = "Left Control",
	342 = "Left Alt",
	343 = "Left Super",
	344 = "Right Shift",
	345 = "Right Control",
	346 = "Right Alt",
	347 = "Right Super",
	348 = "Menu",
}
