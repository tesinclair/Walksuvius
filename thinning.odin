package main

raw_skel :: [SLICE_SIZE]byte

SkeletonSlice :: struct{
    data: ^raw_skel,
}
skeleton_create :: proc(s: Slice2D) -> SkeletonSlice{
    ss := SkeletonSlice{}
    ss.data = new(raw_skel)
   
    rs: raw_slice
    idx := 0
    for x in 0..<SLICE_HEIGHT{
        for y in 0..<SLICE_HEIGHT{
            idx = x + y * SLICE_HEIGHT
            rs[idx] = u8(slice2d_get_pixel(s, {x, y}, proc(p: Pixel) -> Pixel{return p == 255 ? 1 : 0}))
        }
    }
    thin(&rs, ss.data)
    return ss
}

skeleton_destroy :: proc(ss: ^SkeletonSlice){
    free(ss.data)
}

@(private="file")
thin :: proc(s: ^raw_slice, data: ^raw_skel){
    // Guo Hall Thinning according to "Parallel Thinning with Two-Subiteration Algorithms: ZICHENG GUO and RICHARDW. HALL"
    // Taking off grid reads to be 0. All non 255 entries are taken as 0.

    N1 :: proc(nb: PixelNeighbours) -> (ret: Pixel){
        ret += nb[0] | nb[1]
        ret += nb[2] | nb[3]
        ret += nb[4] | nb[5]
        ret += nb[6] | nb[7]
        return
    }

    N2 :: proc(nb: PixelNeighbours) -> (ret: Pixel){
        ret += nb[1] | nb[2]
        ret += nb[3] | nb[4]
        ret += nb[5] | nb[6]
        ret += nb[7] | nb[0]
        return
    }

    N :: proc(nb: PixelNeighbours) -> Pixel{ return min(N1(nb), N2(nb)) }

    Cs :: proc(nb: PixelNeighbours) -> (ret: Pixel) {
        ret += ~nb[1] & (nb[2] | nb[3])
        ret += ~nb[3] & (nb[4] | nb[5])
        ret += ~nb[5] & (nb[6] | nb[7])
        ret += ~nb[7] & (nb[0] | nb[1])

        return
    }

    cond_a :: proc(csp: Pixel) -> bool {return csp == 1}
    cond_b :: proc(np: Pixel) -> bool {return (np >= 2) && (np <= 3)}
    cond_c_odd :: proc(nb: PixelNeighbours) -> bool {return (nb[1] | nb[2] | ~nb[4]) & nb[3] == 0}
    cond_c_even :: proc(nb: PixelNeighbours) -> bool {return (nb[5] | nb[6] | ~nb[0]) & nb[7] == 0}

    parity :: proc(count: int) -> bool{return count % 2 == 0}

    pass :: proc(s: ^raw_slice, write: ^raw_skel, parity: bool) -> int{ // even is true
        deletions := 0
        idx := 0
        for x in 0..<SLICE_HEIGHT{
            for y in 0..<SLICE_HEIGHT{
                idx = x + y * SLICE_HEIGHT
                p := slice2d_get_pixel(s^, {x, y})
                if p == 1{
                    nb := slice2d_get_neighbours(s^, {x, y})
                    ca := cond_a(Cs(nb))
                    cb := cond_b(N(nb))
                    cc := parity ? cond_c_even(nb) : cond_c_odd(nb)

                    if ca && cb && cc{
                        deletions += 1
                        p = 0
                    }
                }

                write[idx] = u8(p)

            }
        }
        return deletions
    }

    pass_count := 0
    prev_del := 0
    curr_del := 0
    for {
        pass_count += 1
        curr_del = pass(s, data, parity(pass_count))
        if curr_del == 0 && prev_del == 0{
            break
        }

        prev_del = curr_del

        s^, data^ = data^, s^
    }
}

