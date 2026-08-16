package main

import rl "vendor:raylib"
import "core:fmt"

VSImage :: struct{
    raw_img: rl.Image,
    texture: rl.Texture,
}

@(private="file")
image: [128*128]u32

colour_map: [256]u32

// Uses the data inside s, so s MUST be alive for as long as VSIMage is
vs_image_from_raw_slice2d :: proc(s: Slice2D, coloured := false) -> VSImage{
    i := VSImage{}
    
    i.raw_img.width, i.raw_img.height = 128, 128
    i.raw_img.mipmaps = 1

    if coloured{
        i.raw_img.format = .UNCOMPRESSED_R8G8B8A8

        idx := 0
        for pixel in s.data{
            if pixel == 255 do image[idx] = 0xFFFFFFFF
            else{
                image[idx] = COLOUR_MAP[BlobTag(pixel)]
            } 

            idx += 1
        }
        i.raw_img.data = rawptr(&image)
    }else{
        i.raw_img.format = .UNCOMPRESSED_GRAYSCALE
        i.raw_img.data = rawptr(s.data)
    }

    i.texture = rl.LoadTextureFromImage(i.raw_img)

    return i
}

vs_image_destroy :: proc(i: ^VSImage){
    //rl.UnloadImage(i.raw_img)  // Right now using Slice2D data which is freed by slice2d
    rl.UnloadTexture(i.texture)
}

vs_image :: proc{
    vs_image_from_raw_slice2d,
}
