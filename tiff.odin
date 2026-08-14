package main

import "core:os"
import "core:fmt"
import "core:io"

FILE_SIZE :: 128 * 128 * 128

TiffData :: [FILE_SIZE]byte

TiffFile :: struct{
    is_little_endian: bool,
    data: ^TiffData,
}

tiff_read :: proc(filepath: string) -> TiffFile{
    t := TiffFile{}


    f, err := os.open(filepath)
    if err != nil{
        fmt.panicf("Failed to open file: %v. With error: %v", filepath, err)
    }
    defer os.close(f)

    raw := make([]byte, 2)
    defer delete(raw)
    
    n, errr := os.read(f, raw)
    if errr != nil || n != 2{
        fmt.panicf("Failed to read from file: %v. n: %v, Err: %v", filepath, n, errr)
    }

    t.is_little_endian = raw[0] == 'I'
    when ODIN_DEBUG{
        if !t.is_little_endian do fmt.printf("M: %v, I: %v, RAW[0]: %v, RAW[1]: %v", byte('M'), byte('I'), raw[0], raw[1])
    }

    t.data = new(TiffData)
    os.seek(f, 256, .Start)

    n, errr = os.read(f, ([]byte)(t.data^[:]))
    if n != FILE_SIZE || errr != nil{
        fmt.panicf("Failed to read all of file: %v. n: %v (wanted: %v), Err: %v", filepath, n, FILE_SIZE, errr)
    }

    return t
}

tiff_destroy :: proc(t: ^TiffFile){
    free(t.data)
}
