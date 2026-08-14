package main

import "core:fmt"
import "core:os"
import rl "vendor:raylib"

ViewData :: struct{
    tiff: TiffFile,
    current_depth: int,
    img: VSImage,
    slice: Slice2D,
    raw: bool,
    cube_paths: CubePack,
    current_cube: int,
}

main :: proc(){
    if len(os.args) < 2 do print_usage()

    switch os.args[1]{
    case "view":
        main_view()
    case "walk":
        main_walk()
    case:
        fmt.printf("Unknown Command: %v.\n\n", os.args[1])
        print_usage()
    }
}

main_walk :: proc(){
    cp := cube_walker_walk()
    defer cube_walker_destroy(&cp)

    for cube in cp.pred{
        {
            t := tiff_read(cube)
            defer tiff_destroy(&t)

            for depth in 0..<128{
                s := slice2d_create(t, depth)
                defer slice2d_destroy(&s)


            }
        }
    }
}

main_view :: proc(){
    cp := cube_walker_walk()
    defer cube_walker_destroy(&cp)

    vs_init()
    defer vs_deinit()

    t := tiff_read(cp.pred[0])

    data := ViewData{}
    data.tiff = t
    data.current_depth = 0
    data.slice = slice2d_create(t, 0)
    data.img = vs_image(data.slice)
    data.current_cube = 0
    data.cube_paths = cp
    
    vs_run(proc(input: rl.KeyboardKey, data: rawptr){
        data := (^ViewData)(data)

        prev_depth := data.current_depth
        prev_cube := data.current_cube
        prev_raw := data.raw

        if input == .UP do data.current_depth = max(data.current_depth - 1, 0)
        if input == .DOWN do data.current_depth = min(data.current_depth + 1, 127)
        if input == .LEFT do data.current_cube = max(data.current_cube - 1, 0)
        if input == .RIGHT do data.current_cube = min(data.current_cube + 1, CUBE_COUNT - 1)
        if input == .SPACE do data.raw = !data.raw

        if prev_raw != data.raw || prev_cube != data.current_cube{
            tiff_destroy(&data.tiff) 

            data.tiff = data.raw ? tiff_read(data.cube_paths.raw[data.current_cube]) : tiff_read(data.cube_paths.pred[data.current_cube])

            prev_depth = data.current_depth + 1
        }

        if prev_depth != data.current_depth{
            slice2d_destroy(&data.slice)
            vs_image_destroy(&data.img)

            data.slice = slice2d_create(data.tiff, data.current_depth)
            data.img = vs_image(data.slice)
        }

        vs_render_image(data.img, data.current_depth, data.current_cube, data.raw)

    }, rawptr(&data))

    tiff_destroy(&data.tiff) 
    slice2d_destroy(&data.slice)
    vs_image_destroy(&data.img)
}

print_usage :: proc(){
    fmt.printf("Usage: %v [ Command ] \n\nCommands:\n\tview  \tRuns Viewsuvius on the cubes to visualise live", os.args[0])
    os.exit(1)
}
