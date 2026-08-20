package main

import "base:intrinsics"
import "core:fmt"

SLICE_SIZE :: 128 * 128
SLICE_HEIGHT :: 128

raw_slice :: [SLICE_SIZE]byte

SliceEdges :: enum{ Top, Bottom, Left, Right }

Pixel :: int

PixelNeighbours :: [8]Pixel

Slice2D :: struct{
    data: ^raw_slice,
    using position: Vec3,
    depth: int,
}

slice2d_create_tiff :: proc(t: TiffFile, depth: int) -> Slice2D{
    s := Slice2D{}
    
    s.data = new(raw_slice)
    
    intrinsics.mem_copy(rawptr(s.data), rawptr(&t.data[depth * SLICE_SIZE]), SLICE_SIZE)

    s.position = t.position
    s.z += depth

    s.depth = depth

    return s
}

slice2d_create_raw :: proc(data: raw_slice, depth: int, position: Vec3 = {-1, -1, -1}) -> Slice2D{
    data := data
    s := Slice2D{}

    s.data = new(raw_slice)
    intrinsics.mem_copy(rawptr(s.data), rawptr(&data), SLICE_SIZE)

    s.position = position

    s.depth = depth
    return s
}

slice2d_create :: proc{
    slice2d_create_raw,
    slice2d_create_tiff
}

slice2d_destroy :: proc(s: ^Slice2D){
    free(s.data)
}

// Returns -1 for off the grid
slice2d_get_pixel_slice :: proc(
    s: Slice2D, 
    p: Vec2, 
    m := proc(p: Pixel) -> Pixel{return p}) -> Pixel{
    offset := p.x + (p.y * SLICE_HEIGHT)
    
    if offset >= SLICE_SIZE || offset < 0 do return m(-1)
    else do return m(Pixel(s.data[offset]))
}

slice2d_get_pixel_raw :: proc(
    s: raw_slice,
    p: Vec2,
    m := proc(p: Pixel) -> Pixel{return p}) -> Pixel{
    offset := p.x + (p.y * SLICE_HEIGHT)
    
    if offset >= SLICE_SIZE || offset < 0 do return m(-1)
    else do return m(Pixel(s[offset]))
}

slice2d_get_pixel :: proc{
    slice2d_get_pixel_raw,
    slice2d_get_pixel_slice
}

slice2d_set_pixel_slice :: proc(s: ^Slice2D, p: Vec2, v: u8){
    offset := p.x + (p.y * SLICE_HEIGHT)
    if offset >= SLICE_SIZE || offset < 0{return} // silently return
    s.data[offset] = v
}
slice2d_set_pixel_raw :: proc(s: ^raw_slice, p: Vec2, v: u8){
    offset := p.x + (p.y * SLICE_HEIGHT)
    if offset >= SLICE_SIZE || offset < 0{return} // silently return
    s[offset] = v
}

slice2d_set_pixel :: proc{
    slice2d_set_pixel_raw,
    slice2d_set_pixel_slice
}

slice2d_map_pixels :: proc(s: ^Slice2D, m: proc(p: Pixel) -> Pixel){
    for x in 0..<SLICE_HEIGHT{
        for y in 0..<SLICE_HEIGHT{
            idx := x + y * SLICE_HEIGHT
            s.data[idx] = u8(slice2d_get_pixel(s^, {x, y}, m))
        }
    }
}

// Colours a slice according to the colour key in tagging.md based on the blobs tags
slice2d_colour :: proc(s: ^Slice2D, b: BlobPack, skel: Slice2D){
    for blob in b.blobs{
        for p in blob.items_small{
            slice2d_set_pixel(s, p, u8(blob.tag))

        }

    }

    for x in 0..<SLICE_HEIGHT{
        for y in 0..<SLICE_HEIGHT{
            if slice2d_get_pixel(skel, {x, y}) != 255 do continue
            slice2d_set_pixel(s, {x, y}, u8(BlobTag.Skeleton))
        }
    }

    for blob in b.blobs{
        for d in blob.deleted{
            for p in d{
                slice2d_set_pixel(s, p, u8(BlobTag.TargetClump))
            }
        }
        for p in blob.targets{
            slice2d_set_pixel(s, p, u8(BlobTag.TargetPixel))
        }
    }
}

slice2d_delete :: proc(s: ^Slice2D, b: BlobPack){
    for blob in b.blobs{
        for d in blob.deleted{
            for p in d{
                slice2d_set_pixel(s, p, 0)
            }
        }
    }
}


// Returns neighbours according to the Guo-Hall Thinning alg spec
// p1 p2 p3
// p8 p  p4
// p7 p6 p5
//
// p1-p8 => neighbours[0-7]
//
// m: A mapping function to control how pixels are returned, useful for mapping 255 -> 1, !255 -> 0
slice2d_get_neighbours :: proc{
    slice2d_get_neighbours_raw,
    slice2d_get_neighbours_slice
}
slice2d_get_neighbours_slice :: proc(
    s: Slice2D, 
    p: Vec2, 
    m := proc(p: Pixel) -> Pixel{return p}) -> PixelNeighbours{
    neighbours: PixelNeighbours
    neighbours[0] = m(slice2d_get_pixel(s, {p.x-1, p.y-1}))
    neighbours[1] = m(slice2d_get_pixel(s, {p.x, p.y-1}))
    neighbours[2] = m(slice2d_get_pixel(s, {p.x+1, p.y-1}))
    neighbours[3] = m(slice2d_get_pixel(s, {p.x+1, p.y}))
    neighbours[4] = m(slice2d_get_pixel(s, {p.x+1, p.y+1}))
    neighbours[5] = m(slice2d_get_pixel(s, {p.x, p.y+1}))
    neighbours[6] = m(slice2d_get_pixel(s, {p.x-1, p.y+1}))
    neighbours[7] = m(slice2d_get_pixel(s, {p.x-1, p.y}))

    return neighbours
}

slice2d_get_neighbours_raw :: proc(
    s: raw_slice, 
    p: Vec2, 
    m := proc(p: Pixel) -> Pixel{return p}) -> PixelNeighbours{
    neighbours: PixelNeighbours
    neighbours[0] = m(slice2d_get_pixel(s, {p.x-1, p.y-1}))
    neighbours[1] = m(slice2d_get_pixel(s, {p.x, p.y-1}))
    neighbours[2] = m(slice2d_get_pixel(s, {p.x+1, p.y-1}))
    neighbours[3] = m(slice2d_get_pixel(s, {p.x+1, p.y}))
    neighbours[4] = m(slice2d_get_pixel(s, {p.x+1, p.y+1}))
    neighbours[5] = m(slice2d_get_pixel(s, {p.x, p.y+1}))
    neighbours[6] = m(slice2d_get_pixel(s, {p.x-1, p.y+1}))
    neighbours[7] = m(slice2d_get_pixel(s, {p.x-1, p.y}))

    return neighbours
}

// n is the neighbour, 1-8
slice2d_get_neighbour_as_point :: proc(p: Vec2, n: int) -> Vec2{
    switch n{
    case 1:
        return {p.x-1, p.y-1}
    case 2:
        return {p.x, p.y - 1}
    case 3:
        return {p.x+1, p.y-1}
    case 4:
        return {p.x+1, p.y}
    case 5:
        return {p.x+1, p.y+1}
    case 6:
        return {p.x, p.y + 1}
    case 7:
        return {p.x - 1, p.y + 1}
    case 8:
        return {p.x - 1, p.y}
    case:
        return {-1, -1}
    }
}
