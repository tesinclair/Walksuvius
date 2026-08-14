package main

import "base:intrinsics"

SLICE_SIZE :: 128 * 128

@(private="file")
raw_slice :: [SLICE_SIZE]byte

Slice2D :: struct{
    data: ^raw_slice,
    depth: int,
}

slice2d_create :: proc(t: TiffFile, depth: int) -> Slice2D{
    s := Slice2D{}
    
    s.data = new(raw_slice)
    
    intrinsics.mem_copy(rawptr(&s.data^[0]), rawptr(&t.data[depth * SLICE_SIZE]), SLICE_SIZE)

    s.depth = depth

    return s
}

slice2d_destroy :: proc(s: ^Slice2D){
    free(s.data)
}
