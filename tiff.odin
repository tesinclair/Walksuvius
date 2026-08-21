package main

import "core:os"
import "core:fmt"
import "core:io"
import "core:strings"
import "core:strconv"
import "base:intrinsics"
import "core:bytes"

FILE_SIZE :: 128 * 128 * 128

TiffData :: [FILE_SIZE]byte

TiffFile :: struct{
    ok: bool,
    data: ^TiffData,
    using position: Vec3,
    filename: string,
    filename_no_suffix: string,
    header_data: []byte,
    footer_data: []byte,
    input_dir: string,
}

TiffError :: enum{
    None,
    BadFilename,
}

tiff_read :: proc(filepath: string) -> TiffFile{
    t := TiffFile{}
    name_err: TiffError

    t.position, t.filename, t.filename_no_suffix, name_err = tiff_get_pos(filepath)
    if name_err == .BadFilename{
        return t
    }

    t.input_dir = strings.trim_suffix(filepath, t.filename)

    f, err := os.open(filepath)
    if err != nil{
        fmt.panicf("Failed to open file: %v. With error: %v", filepath, err)
    }
    defer os.close(f)

    t.header_data = make([]byte, 256)
    n, errr := os.read(f, t.header_data)
    if errr != nil || n <= 0{
        fmt.panicf("Failed to read from file: %v. n: %v, Err: %v", filepath, n, errr)
    }

    t.data = new(TiffData)
    os.seek(f, 256, .Start)

    n, errr = os.read(f, ([]byte)(t.data^[:]))
    if n != FILE_SIZE || errr != nil{
        fmt.panicf("Failed to read all of file: %v. n: %v (wanted: %v), Err: %v", filepath, n, FILE_SIZE, errr)
    }
    
    t.footer_data = make([]byte, 127 * 166)
    n, errr = os.read(f, t.footer_data) 
    if errr != nil || n <= 0{
        fmt.panicf("Failed to read from file: %v. n: %v, Err: %v", filepath, n, errr)
    }

    t.ok = true

    return t
}

tiff_destroy :: proc(t: ^TiffFile){
    free(t.data)
    delete(t.header_data)
    delete(t.footer_data)
}

// Takes a Tiff Cube File Path and returns its coordinates and the filename
tiff_get_pos :: proc(filepath: string) -> (Vec3, string, string, TiffError){
    p := Vec3{}

    split_fp := strings.split(filepath, "/")
    raw_name := split_fp[len(split_fp) - 1]
    name := strings.split(raw_name, ".")[0]
    raw := strings.split(name, "_")

    if len(raw) != 3{
        return p, "", "", TiffError.BadFilename
    }

    z_s, y_s, x_s := raw[0], raw[1], raw[2]
    p.x, _ = strconv.parse_int(x_s)
    p.y, _ = strconv.parse_int(y_s)
    p.z, _ = strconv.parse_int(z_s)

    return p, raw_name, name, TiffError.None
}

tiff_replace_with_slice :: proc(t: ^TiffFile, s: Slice2D){
    intrinsics.mem_copy(rawptr(&t.data[s.depth * SLICE_SIZE]), rawptr(&s.data^[0]), SLICE_SIZE)
}

tiff_write :: proc(t: TiffFile, path: string){
    fullpath := fmt.tprintf("%v%v", path, t.filename)

    data_arr := [?][]byte{t.header_data, t.data^[:], t.footer_data}
    raw_data, err := bytes.concatenate_safe(data_arr[:], context.temp_allocator)
    if err != nil do fmt.panicf("Failed to concatinate data. Err: %v. Sorry...", err)

    if errr := os.make_directory_all(path); errr != nil && errr != .Exist{
        fmt.panicf("Failed to create cube directory: %v. Err: %v", path, errr)
    }
    if errr := os.write_entire_file_from_bytes(fullpath, raw_data); errr != nil{
        fmt.panicf("Failed to write cube to file: %v, err: %v", fullpath, errr)
    }
}
