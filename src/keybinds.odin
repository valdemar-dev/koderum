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
