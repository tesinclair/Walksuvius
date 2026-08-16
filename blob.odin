package main

import "core:fmt"

MAX_BLOB_SIZE :: 128 * 128
MAX_BLOBS :: 128 * 128 / 2

BlobTag :: enum{
    Discarded,
    Suspect,
}

Blob :: struct{
    items: ^[dynamic]Vec2,
    max, min: Vec2,
    index: int,
    edges: bit_set[SliceEdges],
    tag: BlobTag,
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
            if card(b.blobs[idx - 1].edges) >= 2 do b.blobs[idx - 1].tag = .Discarded

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
}

blob_contains :: proc(b: Blob, p: Vec2) -> bool{
    if p.x > b.max.x ||
       p.y > b.max.y ||
       p.x < b.min.x ||
       p.y < b.min.y {return false}

    // Probably could do with a better method
    for i in 0..<len(b.items){
        if b.items[i] == p do return true
    }

    return false
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


