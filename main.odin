package main

import "core:fmt"
import "core:os"
import "core:strings"
import rl "vendor:raylib"

Vec2 :: [2]int
Vec3 :: struct{x,y,z: int}

ViewData :: struct{
    tiff: TiffFile,
    current_depth: int,
    img: VSImage,
    slice: Slice2D,
    cube_paths: CubePack,
    current_cube: int,
    tag_idx: int,
    tags: []string,
}

WALK_OPTS :: [?]string{"-log", "-verbose"}
WalkFlags :: enum{
    Log,
    Verbose,
}

main :: proc(){
    if len(os.args) < 3 do print_usage()

    opt_idx := len(os.args) + 1
    for arg, idx in os.args{
        if arg == "--" do opt_idx = idx + 1
    }

    raw_list := os.args[2:opt_idx - 1]
    tags, dirs: [dynamic]string
    defer {delete(tags); delete(dirs)}

    switch os.args[1]{
    case "view":
        for raw in raw_list{
            if len(strings.split(raw, ":")) < 2{
                fmt.printfln("Each input must have a matching tag. Recommended to use the directory cubes suffix, e.g. PRED for cubes_PRED") 
                print_usage()
            }
            append(&tags, strings.split(raw, ":")[0])
            append(&dirs, strings.split(raw, ":")[1])
        }
        main_view(tags[:], dirs[:])
    case "walk":
        if len(raw_list) > 1{
            fmt.println("Too many input directories. Wanted 1 Got ", len(raw_list))
            print_usage()
        }
        raw := raw_list[0]

        if len(strings.split(raw, ":")) == 1{
            append(&tags, "PRED")
            append(&dirs, raw)
        }else{
            append(&tags, strings.split(raw, ":")[0])
            append(&dirs, strings.split(raw, ":")[1])
        }

        flags: bit_set[WalkFlags]

        if opt_idx < len(os.args){}
        for flag in os.args[opt_idx:]{
            prev := flags
            for opt, idx in WALK_OPTS{
                if opt == flag do flags += { WalkFlags(idx) }
            }
            if prev == flags{ 
                fmt.printfln("Unknown option: %v.", flag)
                print_usage()
            }
        }

        main_walk(flags, tags[:], dirs[:])
    case:
        fmt.printf("Unknown Command: %v.\n\n", os.args[1])
        print_usage()
    }
}

main_walk :: proc(flags: bit_set[WalkFlags], tags, dirs: []string){
    cp := cube_walker_walk(tags, dirs)
    defer cube_walker_destroy(&cp)

    for cube, cube_idx in cp["PRED"]{
        if .Verbose in flags do fmt.printfln("Walking Cube: %v", cube_idx + 1)
        t := tiff_read(cube)
        defer tiff_destroy(&t)

        for depth in 0..<128{
            if .Verbose in flags do fmt.printfln("Blobbing Cube: %v, Slice: %v", cube_idx + 1, depth)

            s := slice2d_create(t, depth)
            defer {
                slice2d_destroy(&s)
            }

            skel := skeleton_create(s)
            defer {
                skeleton_destroy(&skel)
            }

            skel_slice := slice2d_create(skel.data^, s.depth, s.position)
            defer {
                slice2d_destroy(&skel_slice)
            }
            slice2d_map_pixels(&skel_slice, proc(p: Pixel) -> Pixel{ return p * 255 })

            b := blob_blobify(&skel_slice, s)
            defer {
                blob_unblobify(&b)
            }

            blob_find_crossings(&b, &skel_slice)
            blob_find_shortest(&b, &skel_slice, &s)

            if .Verbose in flags{
                for blob in b.blobs{
                    fmt.println("Found target blobs: ", blob.deleted[:])
                }
            }

            if .Log in flags do slice2d_colour(&s, b, skel_slice)
            else do slice2d_delete(&s, b)
            tiff_replace_with_slice(&t, s)

            if .Verbose in flags do fmt.printfln("Got blobs: %v", b.blobs)
        }

        if .Log in flags{
            fmt.printfln("Writing cube %v to %v%v", cube_idx + 1, "out/log/cubes_TAGGED/", t.filename)
            tiff_write(t, "out/log/cubes_TAGGED/")
        }else{
            fmt.printfln("Writing cut cube %v to %v%v", cube_idx + 1, "out/cubes_CUT", t.filename)
            tiff_write(t, "out/cubes_CUT/")
        }
    }
}

main_view :: proc(tags: []string, dirs: []string){
    cp := cube_walker_walk(tags, dirs)
    defer cube_walker_destroy(&cp)

    vs_init()
    defer vs_deinit()

    t := tiff_read(cp[tags[0]][0])

    data := ViewData{}
    data.tiff = t
    data.current_depth = 0
    data.slice = slice2d_create(t, 0)
    data.tag_idx = 0
    data.tags = tags
    data.img = vs_image(data.slice, data.tags[data.tag_idx] == "TAGGED")
    data.current_cube = 0
    data.cube_paths = cp
    
    vs_run(proc(input: rl.KeyboardKey, data: rawptr){
        data := (^ViewData)(data)

        prev_depth := data.current_depth
        prev_cube := data.current_cube
        prev_tag := data.tag_idx

        if input == .UP do data.current_depth = max(data.current_depth - 1, 0)
        if input == .DOWN do data.current_depth = min(data.current_depth + 1, 127)
        if input == .LEFT do data.current_cube = max(data.current_cube - 1, 0)
        if input == .RIGHT do data.current_cube = min(data.current_cube + 1, CUBE_COUNT - 1)
        if input == .SPACE{
            data.tag_idx += 1
            data.tag_idx %= len(data.tags)
        }

        if prev_tag != data.tag_idx || prev_cube != data.current_cube{
            tiff_destroy(&data.tiff) 

            data.tiff = tiff_read(data.cube_paths[data.tags[data.tag_idx]][data.current_cube])

            prev_depth = data.current_depth + 1
        }

        if prev_depth != data.current_depth{
            slice2d_destroy(&data.slice)
            vs_image_destroy(&data.img)

            data.slice = slice2d_create(data.tiff, data.current_depth)
            data.img = vs_image(data.slice, data.tags[data.tag_idx] == "TAGGED")
        }

        vs_render_image(data.img, data.current_depth, data.current_cube, data.tags[data.tag_idx])

    }, rawptr(&data))

    tiff_destroy(&data.tiff) 
    slice2d_destroy(&data.slice)
    vs_image_destroy(&data.img)
}

print_usage :: proc(){
    fmt.printf(`
Usage: %v [ Command ] -- [ Options ]
    Commands:
        walk <directory>                 Walks through the cubes and cuts out any bridges
        view LIST[<tag>:<directory>]     Runs Viewsuvius on the cubes in the directory lists

    Options:
        walk:
            -log                        outputs tagged cubes to out/log/cubes_TAGGED/, according to the colour scheme in tagging.md
            -verbose                    prints verbose output


    Example:
        %v view PRED:../GRID/cubes_PRED TAGGED:out/log/cubes_TAGGED
`, os.args[0])
    os.exit(1)
}
