package main

import "core:fmt"
import "base:intrinsics"
import "core:math"

MAX_BLOB_SIZE :: 128 * 128
MAX_BLOBS :: 128 * 128 / 2

BlobTag :: enum{
    Normal, // Not a suspected blob
    Suspect, // Less than two edges, but no crossing
    TargetBlob, // Less than two edges and crossing point(s) found
    TargetPixel, // Crossing point
    TargetClump, // Smallest area +- 5 from crossing point -- place to cut
    Skeleton, // The thinned skeleton
}

Colour :: u32

COLOUR_MAP := [BlobTag]Colour{
    .Normal = 0xFF9A9D83,
    .Suspect = 0xFF47E2E7,
    .TargetBlob = 0xFF4B96EE,
    .TargetPixel = 0xFFCC2020,
    .TargetClump = 0xFF210ABB,
    .Skeleton = 0xFF000000,
}

Blob :: struct{
    items: ^[dynamic]Vec2,
    items_small: ^[dynamic]Vec2,
    max, min: Vec2,
    index: int,
    edges: bit_set[SliceEdges],
    tag: BlobTag,
    targets: [dynamic]Vec2, // Target Pixels
    deleted: ^[dynamic][dynamic]Vec2
}

BlobPack :: struct{
    blobs: ^(#soa [dynamic]Blob),
}

blob_blobify :: proc(s: ^Slice2D, s_small: Slice2D) -> BlobPack{
    b := BlobPack{}

    b.blobs = new(#soa [dynamic]Blob)

    idx := 1
    // This could REALLY do with some optimization
    for x in 0..<SLICE_HEIGHT{
        loop: for y in 0..<SLICE_HEIGHT{
            if slice2d_get_pixel(s^, Vec2{x, y}) != 0 do continue loop

            append(b.blobs, blob_create(s, Vec2{x, y}, idx, s_small))
            if (card(b.blobs[idx - 1].edges) >= 2) || (len(b.blobs[idx - 1].items) <= 10) do b.blobs[idx - 1].tag = .Normal
            else do b.blobs[idx - 1].tag = .TargetBlob

            idx += 1
        }
    }
    
    return b
}

blob_unblobify :: proc(b: ^BlobPack){
    for blob in b.blobs{
        free(blob.items)
        delete(blob.targets)
    }
    free(b.blobs)
}

blob_create :: proc(s: ^Slice2D, p: Vec2, index: int, s_small: Slice2D) -> Blob{
    b := Blob{}

    b.max = {-1, -1}
    b.min = {SLICE_HEIGHT, SLICE_HEIGHT}
    b.items = new([dynamic]Vec2)
    b.items_small = new([dynamic]Vec2)
    b.index = index
    b.deleted = new([dynamic][dynamic]Vec2)

    dfs(&b, s, p, s_small)

    return b
}

blob_destroy :: proc(b: ^Blob){
    for d in b.deleted{
        delete(d)
    }
    free(b.deleted)

    free(b.items)
    free(b.items_small)
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

blob_contains_small :: proc(b: Blob, p: Vec2) -> bool{
    if p.x > b.max.x ||
       p.y > b.max.y ||
       p.x < b.min.x ||
       p.y < b.min.y {return false}

    for i in 0..<len(b.items_small){
        if b.items_small[i] == p do return true
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
            blob.tag = .Suspect
        }
    }
}

// Skel: Skeleton slice
// s: original slice
blob_find_shortest :: proc(b: ^BlobPack, skel: ^Slice2D, s: ^Slice2D, n := 5){
    walk :: proc(skel: Slice2D, p: Vec2, visited: ^[dynamic]Vec2, depth: ^int, n: int, targets: ^[dynamic]Vec2){
        for pv in visited do if pv == p do return
        if depth^ > n do return

        nb := slice2d_get_neighbours(skel, p)
        for neighbour, idx in nb{
            if neighbour == 255 do continue
            np := slice2d_get_neighbour_as_point(p, idx + 1)
            append(visited, np)
            depth^ += 1

            if depth^ != 0 do append(targets, np)

            walk(skel, np, visited, depth, n, targets)
        }
    }
    for &blob in b.blobs{
        for t in blob.targets{
            visited := new([dynamic]Vec2)
            defer free(visited)

            targets := new([dynamic]Vec2)
            defer free(targets)

            depth := 0

            walk(skel^, t, visited, &depth, n, targets)

            append(blob.deleted, get_smallest_clump(targets[:], s^, blob))
        }
    }
}

@(private="file")
get_smallest_clump :: proc(targets: []Vec2, s: Slice2D, b: Blob) -> [dynamic]Vec2{
    target_clumps := make([dynamic][dynamic]Vec2)

    directions := [4][2]Vec2{
        {{0, 1}, {0, -1}},
        {{1, 0}, {-1, 0}},
        {{1, 1}, {-1, -1}},
        {{-1, 1}, {1, -1}}
    }
    for t in targets{
        distances1: [4]int
        distances2: [4]int
        for pair, idx in directions{
            distances1[idx] = raycast(pair[0], t, 0, s)
            distances2[idx] = raycast(pair[1], t, 0, s)
        }

        smallest_distance := min(abs(distances1[0] + distances2[0]), 
                                 abs(distances1[1] + distances2[1]), 
                                 distances1[2] + distances2[2], 
                                 distances1[3] + distances2[3])
        dir: int
        for _, idx in distances1 do if smallest_distance == distances1[idx] + distances2[idx] do dir = idx

        clump := make([dynamic]Vec2)

        p1 := t
        p2 := t
        append(&clump, p1)
        for i := 1; i <= distances1[dir]; i += 1 do append(&clump, p1 + directions[dir][0] * i)
        for i := 1; i <= distances2[dir]; i += 1 do append(&clump, p1 + directions[dir][1] * i)
        append(&target_clumps, clump)
    }

    smallest := 0
    len_smallest := SLICE_SIZE + 1

    for clump, i in target_clumps{
        allowed := false
        for p in clump{
            if blob_contains_small(b, p){
                allowed = true
                break
            }
        }
        if !allowed do continue
        
        if len(clump) < len_smallest{
            smallest = i
            len_smallest = len(clump)
        }
    }
    return target_clumps[smallest]
}

@(private="file")
raycast :: proc(dir: Vec2, start: Vec2, dest: Pixel, s: Slice2D) -> int{
    pos := start
    for{
        if pix := slice2d_get_pixel(s, pos); pix == dest do return distance(start, pos)
        else if pix == -1 do return -1
        pos = {pos.x + dir.x, pos.y + dir.y}
    }
}

@(private="file")
distance :: proc(p1: Vec2, p2: Vec2) -> int{
    return int(math.sqrt(f32((p1.x - p2.x)*(p1.x - p2.x) + (p1.y - p2.y)*(p1.y - p2.y))))
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
dfs :: proc(b: ^Blob, s: ^Slice2D, p: Vec2, s_small: Slice2D){
    if (p.x < 0 || p.x >= SLICE_HEIGHT || p.y < 0 || p.y >= SLICE_HEIGHT) ||
       slice2d_get_pixel(s^, p) != 0{
        return
    }
    slice2d_set_pixel(s, p, 1)

    append(b.items, p)
    if slice2d_get_pixel(s_small, p) == 0 do append(b.items_small, p)

    if p.x == SLICE_HEIGHT - 1 && .Right not_in b.edges do b.edges += { .Right }
    if p.x == 0 && .Left not_in b.edges do b.edges += { .Left}
    if p.y == SLICE_HEIGHT - 1 && .Bottom not_in b.edges do b.edges += { .Bottom}
    if p.y == 0 && .Top not_in b.edges do b.edges += { .Top}

    b.max = Vec2{max(p.x, b.max.x), max(p.y, b.max.y)}
    b.min = Vec2{min(p.x, b.min.x), min(p.y, b.min.y)}

    dfs(b, s, Vec2{p.x + 1, p.y}, s_small)
    dfs(b, s, Vec2{p.x - 1, p.y}, s_small)
    dfs(b, s, Vec2{p.x, p.y + 1}, s_small)
    dfs(b, s, Vec2{p.x, p.y - 1}, s_small)
}


