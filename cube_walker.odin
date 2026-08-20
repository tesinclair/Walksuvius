package main

import "core:os"
import "core:fmt"
import "core:strings"

CubePackArr :: [dynamic]string

CubePack :: map[string]^CubePackArr


// Wants the full path for either raw or pred assumes cubes have same name
cube_walker_walk :: proc(tags: []string, dirs: []string) -> CubePack{
    cp := make(CubePack)

    fi, err := os.read_directory_by_path(dirs[0], -1, context.allocator)
    if err != nil{
        fmt.panicf("Failed to walk dir: %v. Err: %v", dirs[0], err)
    }
    defer {
        for f in fi do os.file_info_delete(f, context.allocator)
    }

    for tag in tags{
        cp[tag] = new(CubePackArr)
    }

    for f, idx in fi{
        for tag, i in tags{
            dir := strings.trim_suffix(dirs[i], "/")
            filepath := fmt.aprintf("%s/%s", dir, f.name)

            if _, _, err := tiff_get_pos(filepath); err != .None{
                delete(filepath)
                continue
            }

            append(cp[tag], filepath)
        }
    }

    return cp
}

cube_walker_destroy :: proc(cp: ^CubePack){
    for _, arr in cp{
        for s in arr{
            delete(s)
        }
        delete(arr^)
        free(arr)
    }
    delete(cp^)
}
