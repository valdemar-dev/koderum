#+private file
#+feature dynamic-literals
package main

import ft "../../alt-odin-freetype"
import "core:fmt"
import "core:strings"
import "vendor:glfw/bindings"
import "core:mem"
import "core:math"

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
    
    small_text := math.round_f32(font_base_px * small_text_scale)
    normal_text := math.round_f32(font_base_px * normal_text_scale)

    em := font_base_px
    margin := small_text

    reset_rect_cache(&rect_cache)
    reset_rect_cache(&text_rect_cache)

    pen_y := fb_size.y - (margin * 3)
    
    line_thickness := font_base_px * line_thickness_em

    for alert in alert_queue {
        content_size := measure_text(small_text, alert.content, 500)
        title_size := measure_text(small_text, alert.title)

        time_bar_height := alert.show_seconds != -1 ? small_text * line_thickness_em : 0
        gap : f32 = em / 4

        alert_height := content_size.y + title_size.y + time_bar_height + gap + (margin * 2)

        alert_width := max(
            max(content_size.x, title_size.x) + (margin * 2),
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
            1200,
        )

        border_rect := rect{
            bg_rect.x - line_thickness,
            bg_rect.y - line_thickness,
            bg_rect.width + (line_thickness * 2),
            bg_rect.height + (line_thickness * 2),
        }

        add_rect(
            &rect_cache,
            border_rect,
            no_texture,
            BG_MAIN_30,
            vec2{},
            1200,
        )

        // Draw Content
        pen := vec2{
            start_pen.x + margin,
            start_pen.y + margin,
        }

        add_text(&text_rect_cache,
            pen,
            TEXT_MAIN,
            normal_text,
            alert.title,
            1201,
        )

        error := ft.set_pixel_sizes(primary_font, 0, u32(small_text))
        assert(error == .Ok)

        ascend := primary_font.size.metrics.ascender >> 6
        descend := primary_font.size.metrics.descender >> 6
        line_height := f32(ascend - descend)

        pen.y += line_height + gap

        add_text(&text_rect_cache,
            pen,
            TEXT_DARKER,
            small_text,
            alert.content,
            1201,
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
                BG_ACCENT_00,
                vec2{},
                1201,
            )
        }
    }

    draw_rects(&rect_cache)
    draw_rects(&text_rect_cache)
}

@(private="package")
tick_alerts :: proc() {
    for alert, index in alert_queue {
        tick_alert(alert, index)
    }
}

tick_alert :: proc(alert: ^Alert, index: int) {
    em := font_base_px * normal_text_scale
    small_text := font_base_px * small_text_scale

    alert^.remaining_seconds -= frame_time

    content_size := measure_text(small_text, alert.content, 500)

    title_size := measure_text(small_text, alert.title)

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
            delete(alert.content, alert.allocator)
            delete(alert.title, alert.allocator)

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

    em := math.round_f32(font_base_px * normal_text_scale)
    normal_text := em
    margin := em
    small_text := math.round_f32(font_base_px * small_text_scale)

    reset_rect_cache(&rect_cache)
    reset_rect_cache(&text_rect_cache)

    notification := notification_queue[0]

    line_thickness := math.round_f32(font_base_px * line_thickness_em)
        
    content_size := measure_text(small_text, notification.content)

    copy_text_size := notification.copy_text == "" ? vec2{0,0} :
        measure_text(small_text, notification.content)

    title_size := measure_text(em, notification.title)

    dismiss_size := measure_text(
        small_text,
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
            bg_rect.x - line_thickness,
            bg_rect.y - line_thickness,
            bg_rect.width + (line_thickness * 2),
            bg_rect.height + (line_thickness * 2),
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
            normal_text,
            notification.title,
            13,
        )

        error := ft.set_pixel_sizes(primary_font, 0, u32(normal_text))
        assert(error == .Ok)

        ascend := primary_font.size.metrics.ascender >> 6
        descend := primary_font.size.metrics.descender >> 6

        line_height := f32(ascend - descend)

        pen.y += line_height

        add_text(&text_rect_cache,
            pen,
            TEXT_DARKER,
            small_text,
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
            small_text,
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
            small_text,
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

    normal_text := math.round_f32(font_base_px * normal_text_scale)
    small_text := math.round_f32(font_base_px * small_text_scale)
    
    em := normal_text

    notification := notification_queue[0]

    content_size := measure_text(small_text, notification.content)
    title_size := measure_text(normal_text, notification.title)

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
        content = strings.clone(content, allocator),
        title = strings.clone(title, allocator),

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
    delete(alert.title, alert.allocator)
    delete(alert.content, alert.allocator)

    alert^.title = strings.clone(title)
    alert^.content = strings.clone(content)
}
