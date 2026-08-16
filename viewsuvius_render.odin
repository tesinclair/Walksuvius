package main

import rl "vendor:raylib"
import "core:strings"
import "core:fmt"
import "core:math/rand"

SCALE :: 10
WIDTH :: 128 * SCALE
HEIGHT :: 128 * SCALE
PADDING :: 32

vs_init :: proc(){
    rl.SetConfigFlags({})

    rl.SetTraceLogLevel(.WARNING)

    rl.SetTargetFPS(25)

    rl.InitWindow(WIDTH, HEIGHT + PADDING, "Viewsuvius")

    colour_map[0] = u32(0)
    colour_map[255] = 0xFFFFFFFF
    for idx in 1..<255{
        colour_map[idx] = rand.uint32()
    }
}

vs_deinit :: proc(){
    rl.CloseWindow()
}

vs_render_image :: proc(i: VSImage, depth: int, cube_idx: int, tag: string){
    s := fmt.tprintf("Depth: %v | Cube: %v | ViewType: %v", depth, cube_idx, tag)
    text := strings.clone_to_cstring(s)
    defer delete(text)

    rl.DrawText(text, (WIDTH - rl.MeasureText(text, 32)) / 2, 2, 32, rl.WHITE)
    rl.DrawTextureEx(i.texture, {0, PADDING}, 0, SCALE, rl.WHITE)
}

vs_run :: proc(callback: proc(input: rl.KeyboardKey, data: rawptr), user_data: rawptr){
    for !rl.WindowShouldClose(){
        rl.BeginDrawing()
        rl.ClearBackground(rl.BLACK)
        
        key := rl.GetKeyPressed()
        if rl.IsKeyPressed(.DOWN) || rl.IsKeyPressedRepeat(.DOWN) do key = .DOWN
        if rl.IsKeyPressed(.UP) || rl.IsKeyPressedRepeat(.UP) do key = .UP
        if rl.IsKeyPressed(.LEFT) || rl.IsKeyPressedRepeat(.LEFT) do key = .LEFT
        if rl.IsKeyPressed(.RIGHT) || rl.IsKeyPressedRepeat(.RIGHT) do key = .RIGHT

        callback(key, user_data)

        rl.EndDrawing()
    }
}
