package main

import "core:os"
import "core:fmt"
import "core:strings"

CUBE_COUNT :: 64

PRED_BASE_PATH :: "../GRID64/cubes_PRED/"
RAW_BASE_PATH :: "../GRID64/cubes_RAW/"

CubePackArr :: [CUBE_COUNT]string

CubePack :: struct{
    raw: ^CubePackArr,
    pred: ^CubePackArr,
}

// Wants the full path for either raw or pred assumes cubes have same name
cube_walker_walk :: proc() -> CubePack{
    cp := CubePack{}

    fi, err := os.read_directory_by_path(PRED_BASE_PATH, 64, context.allocator)
    if err != nil{
        fmt.panicf("Failed to walk dir: %v. Err: %v", PRED_BASE_PATH, err)
    }
    
    cp.raw = new(CubePackArr)
    cp.pred = new(CubePackArr)

    for f, idx in fi{
        cp.pred[idx] = fmt.aprintf("%s%s", PRED_BASE_PATH, f.name)
        cp.raw[idx] = fmt.aprintf("%s%s", RAW_BASE_PATH, f.name)
    }

    return cp
}

cube_walker_destroy :: proc(cp: ^CubePack){
    for idx in 0..<CUBE_COUNT{
        delete(cp.raw[idx])
        delete(cp.pred[idx])
    }
    free(cp.raw)
    free(cp.pred)
}
