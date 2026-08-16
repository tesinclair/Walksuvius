package main

import "core:fmt"
import "base:intrinsics"

MAX_BLOB_SIZE :: 128 * 128
MAX_BLOBS :: 128 * 128 / 2

BlobTag :: enum{
    Normal,
    SuspectNoJunc,
    Suspect,
    TargetPixel,
    TargetClump,
}

Colour :: u32

COLOUR_MAP := [BlobTag]Colour{
    .Normal = 0xFF9A9D83,
    .SuspectNoJunc = 0xFF47E2E7,
    .Suspect = 0xFF4B96EE,
    .TargetPixel = 0xFF272625,
    .TargetClump = 0xFF210ABB
}

Blob :: struct{
    items: ^[dynamic]Vec2,
    max, min: Vec2,
    index: int,
    edges: bit_set[SliceEdges],
    tag: BlobTag,
    targets: [dynamic]Vec2, // The place we are cutting
}

BlobPack :: struct{
    blobs: ^(#soa [dynamic]Blob),
}

blob_blobify :: proc(s: ^Slice2D) -> BlobPack{
    b := BlobPack{}

    b.blobs = new(#soa [dynamic]Blob)

    idx := 1
    // This could REALLY do with some optimization
    for x in 0..<SLICE_HEIGHT{
        loop: for y in 0..<SLICE_HEIGHT{
            if slice2d_get_pixel(s^, Vec2{x, y}) != 0 do continue loop

            append(b.blobs, blob_create(s, Vec2{x, y}, idx))
            if (card(b.blobs[idx - 1].edges) >= 2) || (len(b.blobs[idx - 1].items) <= 10) do b.blobs[idx - 1].tag = .Normal
            else do b.blobs[idx - 1].tag = .Suspect

            idx += 1
        }
    }
    
    return b
}

blob_unblobify :: proc(b: ^BlobPack){
    for blob in b.blobs{
        free(blob.items)
    }
    free(b.blobs)
}

blob_create :: proc(s: ^Slice2D, p: Vec2, index: int) -> Blob{
    b := Blob{}

    b.max = {-1, -1}
    b.min = {SLICE_HEIGHT, SLICE_HEIGHT}
    b.items = new([dynamic]Vec2)
    b.index = index

    idx := 0
    dfs(&b, s, p, &idx)

    return b
}

blob_destroy :: proc(b: ^Blob){
    free(b.items)
    delete(b.targets)
}

blob_contains :: proc(b: Blob, p: Vec2) -> bool{
    if p.x > b.max.x ||
       p.y > b.max.y ||
       p.x < b.min.x ||
       p.y < b.min.y {return false}

    for i in 0..<len(b.items){
        if b.items[i] == p do return true
    }

    return false
}

blob_find_crossings :: proc(b: ^BlobPack, s: ^Slice2D){
    for &blob in b.blobs{
        if blob.tag == .Normal do continue
        edge := -1
        pos: Vec2
        finding_edge: for p in blob.items{
            pos = p
            nb := slice2d_get_neighbours(s^, pos)

            for p2, idx in nb{
                if p2 == 255{
                    edge = idx + 1
                    break finding_edge
                }
            }
        }
        if edge == -1 do continue // SHouldn't happen though
        
        pos = slice2d_get_neighbour_as_point(pos, edge)
        if pos == {-1, -1} do continue // Shouldn't happen though

        walk_edge :: proc(s: Slice2D, p: Vec2, targets: ^[dynamic]Vec2, visited: ^raw_slice, b: Blob){
            if slice2d_get_pixel(visited^, p) == 1{ return }
            is_adj := false
            for adj, idx in slice2d_get_neighbours(s, p){
                if adj == 255 do continue
                if blob_contains(b, slice2d_get_neighbour_as_point(p, idx + 1)) do is_adj = true
            }
            if !is_adj do return
            slice2d_set_pixel(visited, p, 1)
            nb := slice2d_get_neighbours(s, p)
            
            if blob_get_chunks_unique(nb) >= 3{
                append(targets, p)
            }

            for n, idx in nb{
                if n == 255 do walk_edge(s, slice2d_get_neighbour_as_point(p, idx + 1), targets, visited, b)
            }
        }

        visited: raw_slice
        walk_edge(s^, pos, &blob.targets, &visited, blob)

        if len(blob.targets) < 1{
            blob.tag = .SuspectNoJunc
        }
    }
}

blob_get_chunks_unique :: proc(nb: PixelNeighbours) -> int{
    x: u64

    for i in 0..<8{
        x <<= 1
        x += nb[i] == 255 ? 1 : 0 
    }

    return int(intrinsics.count_ones(x & ~(((x << 1) | (x >> 7)) & 0xFF)) + (x == 0xFF ? 1 : 0))
}

@(private="file")
dfs :: proc(b: ^Blob, s: ^Slice2D, p: Vec2, idx: ^int){
    if (p.x < 0 || p.x >= SLICE_HEIGHT || p.y < 0 || p.y >= SLICE_HEIGHT) ||
       slice2d_get_pixel(s^, p) != 0{
        return
    }
    slice2d_set_pixel(s, p, u8(b.index))

    append(b.items, p)

    if p.x == SLICE_HEIGHT - 1 && .Right not_in b.edges do b.edges += { .Right }
    if p.x == 0 && .Left not_in b.edges do b.edges += { .Left}
    if p.y == SLICE_HEIGHT - 1 && .Bottom not_in b.edges do b.edges += { .Bottom}
    if p.y == 0 && .Top not_in b.edges do b.edges += { .Top}

    idx^ += 1

    b.max = Vec2{max(p.x, b.max.x), max(p.y, b.max.y)}
    b.min = Vec2{min(p.x, b.min.x), min(p.y, b.min.y)}

    dfs(b, s, Vec2{p.x + 1, p.y}, idx)
    dfs(b, s, Vec2{p.x - 1, p.y}, idx)
    dfs(b, s, Vec2{p.x, p.y + 1}, idx)
    dfs(b, s, Vec2{p.x, p.y - 1}, idx)
}


