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
    ENTER_INSERT_MODE,
    ENTER_YANK_HISTORY_MODE,
    ENTER_HIGHLIGHT_MODE,
    ENTER_GREP_SEARCH_MODE,
    ENTER_SEARCH_MODE,
    ENTER_FILE_BROWSER_MODE,
    ENTER_GO_TO_LINE_MODE,
    ENTER_FIND_AND_REPLACE_MODE,
    ENTER_HELP_MODE,

    /*
        SWAP BETWEEN FILES
    */
    NEXT_FILE,
    PREVIOUS_FILE,
    
    ESCAPE,
}

@(private="package")
mapped_keybinds : map[KODERUM_KEY]i32 = {}

@(private="package")
check_for_keybind :: proc(option_name: string, value: string) -> (do_continue: bool = true) {
    switch option_name {
    case "move_up":
        mapped_keybinds[.MOVE_UP] = i32(strconv.atoi(value))
    case "move_down":
        mapped_keybinds[.MOVE_DOWN] = i32(strconv.atoi(value))
    case "move_left":
        mapped_keybinds[.MOVE_LEFT] = i32(strconv.atoi(value))
    case "move_right":
        mapped_keybinds[.MOVE_RIGHT] = i32(strconv.atoi(value))
    case "move_forward_word":
        mapped_keybinds[.MOVE_FORWARD_WORD] = i32(strconv.atoi(value))
    case "move_backward_word":
        mapped_keybinds[.MOVE_UP] = i32(strconv.atoi(value))
    case "enter_insert_mode":
        mapped_keybinds[.ENTER_INSERT_MODE] = i32(strconv.atoi(value))
    case "enter_yank_history_mode":
        mapped_keybinds[.ENTER_YANK_HISTORY_MODE] = i32(strconv.atoi(value))
    case "enter_highlight_mode":
        mapped_keybinds[.ENTER_HIGHLIGHT_MODE] = i32(strconv.atoi(value))
    case "enter_grep_search_mode":
        mapped_keybinds[.ENTER_GREP_SEARCH_MODE] = i32(strconv.atoi(value))
    case "enter_search_mode":
        mapped_keybinds[.ENTER_SEARCH_MODE] = i32(strconv.atoi(value))
    case "enter_file_browser_mode":
        mapped_keybinds[.ENTER_FILE_BROWSER_MODE] = i32(strconv.atoi(value))
    case "enter_go_to_line_mode":
        mapped_keybinds[.ENTER_GO_TO_LINE_MODE] = i32(strconv.atoi(value))
    case "enter_find_and_replace_mode":
        mapped_keybinds[.ENTER_FIND_AND_REPLACE_MODE] = i32(strconv.atoi(value))
    case "enter_help_mode":
        mapped_keybinds[.ENTER_HELP_MODE] = i32(strconv.atoi(value))
    case "next_file":
        mapped_keybinds[.NEXT_FILE] = i32(strconv.atoi(value))
    case "previous_file":
        mapped_keybinds[.PREVIOUS_FILE] = i32(strconv.atoi(value))
    case "escape":
        mapped_keybinds[.ESCAPE] = i32(strconv.atoi(value))
    }
    
    return do_continue
}