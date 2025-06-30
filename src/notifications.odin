#+private file
#+feature dynamic-literals
package main

import ft "../../alt-odin-freetype"
import "core:fmt"
import "core:strings"
import "vendor:glfw/bindings"
import "core:mem"

@(private="package")
Alert :: struct {
    title: string,
    content: string,

    show_seconds: f32,
    remaining_seconds: f32,

    allocator: mem.Allocator,

    should_hide: bool,
    x_pos: f32,
}

@(private="package")
Notification :: struct {
    title: string,
    content: string,

    copy_text: string,
}

@(private="package")
alert_queue : [dynamic]^Alert = {}

@(private="package")
notification_queue : [dynamic]^Notification = {}

suppress := true

notification_should_hide := true

x_pos : f32 = 0

@(private="package")
draw_alerts :: proc() {
    if len(alert_queue) == 0 {
        return
    }

    em := ui_general_font_size
    margin := em

    reset_rect_cache(&rect_cache)
    reset_rect_cache(&text_rect_cache)

    pen_y := fb_size.y - margin

    for alert in alert_queue {
        content_size := measure_text(ui_smaller_font_size, alert.content, 500)
        title_size := measure_text(ui_smaller_font_size, alert.title)

        time_bar_height := alert.show_seconds != -1 ? general_line_thickness_px : 0
        gap : f32 = 5

        alert_height := content_size.y + title_size.y + time_bar_height + gap + (em * 2)

        alert_width := max(
            max(content_size.x, title_size.x) + (em * 2),
            300,
        )

        pen_y -= alert_height
        defer pen_y -= em

        start_pen := vec2{
            alert.x_pos,
            pen_y,
        }

        bg_rect := rect{
            start_pen.x,
            start_pen.y,
            alert_width,
            alert_height,
        }

        // Draw Background
        add_rect(
            &rect_cache,
            bg_rect,
            no_texture,
            BG_MAIN_10,
            vec2{},
            12,
        )

        border_rect := rect{
            bg_rect.x - general_line_thickness_px,
            bg_rect.y - general_line_thickness_px,
            bg_rect.width + (general_line_thickness_px * 2),
            bg_rect.height + (general_line_thickness_px * 2),
        }

        add_rect(
            &rect_cache,
            border_rect,
            no_texture,
            BG_MAIN_30,
            vec2{},
            12,
        )

        // Draw Content
        pen := vec2{
            start_pen.x + em,
            start_pen.y + em,
        }

        add_text(&text_rect_cache,
            pen,
            TEXT_MAIN,
            ui_smaller_font_size,
            alert.title,
            13,
        )

        error := ft.set_pixel_sizes(primary_font, 0, u32(ui_smaller_font_size))
        assert(error == .Ok)

        ascend := primary_font.size.metrics.ascender >> 6
        descend := primary_font.size.metrics.descender >> 6
        line_height := f32(ascend - descend)

        pen.y += line_height + gap

        add_text(&text_rect_cache,
            pen,
            TEXT_DARKER,
            ui_smaller_font_size,
            alert.content,
            13,
            false,
            500,
            true,
            true,
        )

        // Draw time remaining
        if alert.show_seconds != -1 {
            bar_rect := rect{
                bg_rect.x,
                bg_rect.y + bg_rect.height - time_bar_height,
                bg_rect.width * (alert.remaining_seconds / alert.show_seconds),
                time_bar_height,
            }

            add_rect(
                &rect_cache,
                bar_rect,
                no_texture,
                BLUE,
                vec2{},
                13,
            )
        }
    }

    draw_rects(&rect_cache)
    draw_rects(&text_rect_cache)
}


/*
@(private="package")
draw_alerts :: proc() {
    if suppress_alert {
        return
    }

    em := ui_general_font_size
    margin := em

    reset_rect_cache(&rect_cache)
    reset_rect_cache(&text_rect_cache)

    alert := alert_queue[0]

    content_size := measure_text(ui_smaller_font_size, alert.content, 500)

    title_size := measure_text(ui_smaller_font_size, alert.title)

    time_bar_height := alert.show_seconds != -1 ? general_line_thickness_px : 0

    gap : f32 = 5

    alert_height := content_size.y + title_size.y + time_bar_height + gap + (em * 2)

    alert_width := max(
        max(content_size.x, title_size.x) + (em * 2),
        300,
    )

    start_pen := vec2{
        alert.x_pos,
        fb_size.y - alert_height - margin,
    }

    bg_rect := rect{
        start_pen.x,
        start_pen.y,
        alert_width,
        alert_height,
    }

    // Draw Background,
    {
        add_rect(
            &rect_cache,
            bg_rect,
            no_texture,
            BG_MAIN_10,
            vec2{},
            12,
        )

        border_rect := rect{
            bg_rect.x - general_line_thickness_px,
            bg_rect.y - general_line_thickness_px,
            bg_rect.width + (general_line_thickness_px * 2),
            bg_rect.height + (general_line_thickness_px * 2),
        }

        add_rect(
            &rect_cache,
            border_rect,
            no_texture,
            BG_MAIN_30,
            vec2{},
            12,
        )
    }

    // Draw Content
    {
        pen := vec2{
            start_pen.x + em,
            start_pen.y + em,
        }

        add_text(&text_rect_cache,
            pen,
            TEXT_MAIN,
            ui_smaller_font_size,
            alert.title,
            13,
        )

        error := ft.set_pixel_sizes(primary_font, 0, u32(ui_smaller_font_size))
        assert(error == .Ok)

        ascend := primary_font.size.metrics.ascender >> 6
        descend := primary_font.size.metrics.descender >> 6

        line_height := f32(ascend - descend)

        pen.y += line_height + gap 

        add_text(&text_rect_cache,
            pen,
            TEXT_DARKER,
            ui_smaller_font_size,
            alert.content,
            13,
            false,
            500,
            true,
            true,
        )
    }

    // Draw time remaining
    if alert.show_seconds != -1 {
        bar_rect := rect{
            bg_rect.x,
            bg_rect.y + bg_rect.height - time_bar_height,
            bg_rect.width * (alert.remaining_seconds / alert.show_seconds),
            time_bar_height,
        }

        add_rect(
            &rect_cache,
            bar_rect,
            no_texture,
            BLUE,
            vec2{},
            13,
        )
    }

    draw_rects(&rect_cache)
    draw_rects(&text_rect_cache)
}
*/

@(private="package")
tick_alerts :: proc() {
    for alert, index in alert_queue {
        tick_alert(alert, index)
    }
}

tick_alert :: proc(alert: ^Alert, index: int) {
    em := ui_general_font_size

    alert^.remaining_seconds -= frame_time

    content_size := measure_text(ui_smaller_font_size, alert.content, 500)

    title_size := measure_text(ui_smaller_font_size, alert.title)

    alert_width := max(
        max(content_size.x, title_size.x) + (em * 2),
        300,
    )

    if alert.remaining_seconds < 0 && alert.show_seconds != -1 {
        alert.should_hide = true
    }

    if alert.should_hide {
        alert.x_pos = smooth_lerp(alert.x_pos, 0 - alert_width, 20, frame_time)

        if int(alert.x_pos) <= int(0 - alert_width + 5) {

            delete(alert.content)
            delete(alert.title)

            free(alert, alert.allocator)

            unordered_remove(&alert_queue, index)
        }
    } else {
        alert.x_pos = smooth_lerp(alert.x_pos, em, 20, frame_time)
    }
}

@(private="package")
draw_notification :: proc() {
    if suppress {
        return
    }

    em := ui_general_font_size
    margin := em

    reset_rect_cache(&rect_cache)
    reset_rect_cache(&text_rect_cache)

    notification := notification_queue[0]

    content_size := measure_text(ui_smaller_font_size, notification.content)

    copy_text_size := notification.copy_text == "" ? vec2{0,0} :
        measure_text(ui_smaller_font_size, notification.content)

    title_size := measure_text(ui_general_font_size, notification.title)

    dismiss_size := measure_text(
        ui_smaller_font_size,
        "Dismiss: Ctrl + Esc\nCopy Command: Ctrl + Shift + C",
    )

    notification_height := content_size.y + title_size.y + dismiss_size.y + copy_text_size.y + (em * 4)

    notification_width := max(
        max(content_size.x, title_size.x) + (em * 2),
        300,
    )

    start_pen := vec2{
        x_pos,
        fb_size.y - notification_height - margin,
    }

    bg_rect := rect{
        start_pen.x,
        start_pen.y,
        notification_width,
        notification_height,
    }

    // Draw Background,
    {
        add_rect(
            &rect_cache,
            bg_rect,
            no_texture,
            BG_MAIN_10,
            vec2{},
            12,
        )

        border_rect := rect{
            bg_rect.x - general_line_thickness_px,
            bg_rect.y - general_line_thickness_px,
            bg_rect.width + (general_line_thickness_px * 2),
            bg_rect.height + (general_line_thickness_px * 2),
        }

        add_rect(
            &rect_cache,
            border_rect,
            no_texture,
            BG_MAIN_30,
            vec2{},
            12,
        )
    }

    // Draw Content
    {
        pen := vec2{
            start_pen.x + em,
            start_pen.y + em,
        }

        add_text(&text_rect_cache,
            pen,
            TEXT_MAIN,
            ui_general_font_size,
            notification.title,
            13,
        )

        error := ft.set_pixel_sizes(primary_font, 0, u32(ui_general_font_size))
        assert(error == .Ok)

        ascend := primary_font.size.metrics.ascender >> 6
        descend := primary_font.size.metrics.descender >> 6

        line_height := f32(ascend - descend)

        pen.y += line_height

        add_text(&text_rect_cache,
            pen,
            TEXT_DARKER,
            ui_smaller_font_size,
            notification.content,
            13,
            false,
            500,
            true,
            true,
        )

        pen.y += line_height

        add_text(&text_rect_cache,
            pen,
            TEXT_DARKER,
            ui_smaller_font_size,
            notification.copy_text,
            13,
            false,
            -1,
            false,
            true,
        )
    }

    // Draw Controls
    {
        add_text(&text_rect_cache,
            vec2{
                bg_rect.x + margin,
                bg_rect.y + bg_rect.height - dismiss_size.y - margin,
            },
            TEXT_DARKEST,
            ui_smaller_font_size,
            "Dismiss: Ctrl + Esc\nCopy Command: Ctrl + Shift + C",
            14,
            false,
            -1,
            false,
            true,
        )
    }

    draw_rects(&rect_cache)
    draw_rects(&text_rect_cache)
}

@(private="package")
tick_notifications :: proc() {
    if len(notification_queue) == 0 {
        suppress = true

        return
    }

    if suppress == true {
        suppress = false
        notification_should_hide = false

        x_pos := fb_size.x
    }

    em := ui_general_font_size

    notification := notification_queue[0]

    content_size := measure_text(ui_smaller_font_size, notification.content)
    title_size := measure_text(ui_general_font_size, notification.title)

    notification_width := max(
        max(content_size.x, title_size.x) + (em * 2),
        300,
    )

    if notification_should_hide {
        x_pos = smooth_lerp(x_pos, fb_size.x, 20, frame_time)

        if int(x_pos) >= int(fb_size.x - 1) {
            suppress = true
            free(notification)
            ordered_remove(&notification_queue, 0)
        }
    } else {
        x_pos = smooth_lerp(x_pos, fb_size.x - notification_width - em, 20, frame_time)
    }
}

@(private="package")
copy_notification_command :: proc() {
    if len(notification_queue) == 0 {
        return
    }

    notification := notification_queue[0]

    if len(notification.copy_text) == 0 {
        return
    }

    cstr := strings.clone_to_cstring(notification.copy_text)
 
    bindings.SetClipboardString(window, cstr)

    dismiss_notification()
}

@(private="package")
dismiss_notification :: proc() {
    notification_should_hide = true
}

@(private="package")
dismiss_alert :: proc(alert: ^Alert) {
    alert^.should_hide = true
}

@(private="package")
create_alert :: proc(
    title, content: string,
    show_seconds: f32,
    allocator: mem.Allocator,
) -> ^Alert {
    alert := new(Alert, allocator)

    alert^ = Alert{
        content = strings.clone(content),
        title = strings.clone(title),

        show_seconds = show_seconds,
        remaining_seconds = show_seconds,
    }

    append(&alert_queue, alert)

    return alert
}

@(private="package")
edit_alert :: proc(
    alert: ^Alert,
    title: string,
    content: string,
) {
    delete(alert.title)
    delete(alert.content)

    alert^.title = strings.clone(title)
    alert^.content = strings.clone(content)
}



















