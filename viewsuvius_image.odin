package main

import rl "vendor:raylib"
import "core:fmt"

VSImage :: struct{
    raw_img: rl.Image,
    texture: rl.Texture,
}

// Uses the data inside s, so s MUST be alive for as long as VSIMage is
vs_image_from_raw_slice2d :: proc(s: Slice2D) -> VSImage{
    i := VSImage{}
    
    i.raw_img.data = rawptr(s.data)
    i.raw_img.width, i.raw_img.height = 128, 128
    i.raw_img.format = .UNCOMPRESSED_GRAYSCALE
    i.raw_img.mipmaps = 1

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
