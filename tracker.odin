package main

import "core:os"
import "core:fmt"
import "core:time"
import "core:encoding/uuid"
import "core:encoding/json"
import "core:strconv"
import "core:encoding/csv"
import "core:slice"

VERSION_SHA :: #config(GIT_SHA, "")

Tracker :: struct{
    cubes: ^[dynamic]cube_data,
    suspects: ^[dynamic]suspect_data,
    json: ^json_data,
    output_dir: string,
}

@(private="file")
cube_data :: struct{
    id: string,
    x, y, z,
    slices_scanned,
    slices_with_suspects,
    n_candidates, n_kept, n_discarded,
    n_cuts_total, n_pixels_cut: int
}

@(private="file")
suspect_data :: struct{
    id: string,
    cube_id: string, //foreign key: cube_data
    x, y, z,
    depth: int,
    n_cuts, n_pixels_cut: int,
    kept: bool,
    discard_reason: string,
}

@(private="file")
json_data :: struct{
    run_id: uuid.Identifier,
    walksuvius_sha: string,
    run_started_utc: time.Time,
    input_dir,
    scroll: string,
    cubes_scanned: int,
}

tracker_create :: proc(output_dir := "") -> Tracker{
    t := Tracker{}

    t.cubes = new([dynamic]cube_data)
    t.suspects = new([dynamic]suspect_data)
    t.json = new(json_data)

    t.output_dir = output_dir
    return t
}

tracker_destroy :: proc(t: ^Tracker){
    free(t.cubes)
    free(t.suspects)
    free(t.json)
}

tracker_add :: proc{
    tracker_add_suspect,
    tracker_add_cube,
    tracker_add_json
}

tracker_add_json :: proc(t: ^Tracker, started: time.Time, input_dir, scroll: string, N: int){
    t.json.run_id = uuid.generate_v6()
    t.json.walksuvius_sha = VERSION_SHA
    t.json.run_started_utc = started
    t.json.input_dir = input_dir
    t.json.scroll = scroll
    t.json.cubes_scanned = N

    when VERSION_SHA == "" do fmt.println("No Version SHA set. None will be provided.")
}

tracker_add_suspect :: proc(t: ^Tracker, s: Slice2D, b: BlobPack, cid: string){
    for blob, idx in b.blobs{
        sd := suspect_data{}

        sd.id = fmt.aprintf("%v_%v_%v:%v", s.x, s.y, s.z, idx)
        sd.cube_id = cid
        sd.x, sd.y, sd.z = s.x, s.y, s.z
        sd.depth = s.depth
        sd.n_cuts = len(blob.deleted)
        for d in blob.deleted{ // deleted is an array all the cut lines
            sd.n_pixels_cut += len(d) // d is an array of points to cut
        }

        sd.kept = blob.tag == .TargetBlob
        sd.discard_reason = proc(b: BlobTag) -> string{
            #partial switch b{
            case .Normal:
                return "Touches 2+ edges"
            case .Suspect:
                return "No junction found"
            case:
                return ""
            }
        }(blob.tag)

        append(t.suspects, sd)
    }
}

tracker_add_cube :: proc(t: ^Tracker, c: TiffFile){
    cube := cube_data{}

    cube.id = c.filename_no_suffix
    cube.x, cube.y, cube.z = c.x, c.y, c.z

    cube.slices_scanned = 128
    
    unique_slices: bit_set[0..<128]  

    for suspect in t.suspects{
        if suspect.cube_id != cube.id do continue 
        
        if suspect.kept do cube.n_kept += 1
        if !suspect.kept do cube.n_discarded += 1
        cube.n_candidates += 1

        cube.n_cuts_total += suspect.n_cuts
        cube.n_pixels_cut += suspect.n_pixels_cut
        
        if suspect.kept do unique_slices += { suspect.depth }
    }

    cube.slices_with_suspects = card(unique_slices)

    append(t.cubes, cube)
}

/* 
 * AI GENERATED
 *
 * The following functions are AI generated
 * this is allowed by the contribution guidelines since
 * they are both documentation functions and only output predefined data
 *
 * That being said, this is not ideal and will be changed later
*/

@(private="file")
run_json :: struct{
    run_id:            string,
    walksuvius_sha:    string,
    run_started_utc:   string,
    input_dir, scroll: string,
    cubes_scanned:     int,
}

@(private="file")
rfc3339_utc :: proc(t: time.Time) -> string {
    y, mo, d := time.date(t)
    h, mi, s := time.clock_from_time(t)
    return fmt.tprintf("%04d-%02d-%02dT%02d:%02d:%02dZ", y, int(mo), d, h, mi, s)
}

tracker_write :: proc(t: Tracker){
    if err := os.make_directory_all(t.output_dir); err != nil && err != .Exist{
        fmt.panicf("Failed to create cube directory: %v. Err: %v", t.output_dir, err)
    }

    id := uuid.to_string(t.json.run_id, context.temp_allocator)

    // run.json
    {
        r := run_json{
            run_id          = id,
            walksuvius_sha  = t.json.walksuvius_sha,
            run_started_utc = rfc3339_utc(t.json.run_started_utc),
            input_dir       = t.json.input_dir,
            scroll          = t.json.scroll,
            cubes_scanned   = t.json.cubes_scanned,
        }
        data, merr := json.marshal(r, {pretty = true, use_spaces = true, spaces = 2}, context.temp_allocator)
        if merr != nil {
            fmt.eprintfln("tracker: marshal failed: %v", merr)
        } else {
            f, oerr := os.create(fmt.tprintf("%s/run.json", t.output_dir))
            if oerr != nil {
                fmt.eprintfln("tracker: run.json: %v", oerr)
            } else {
                defer os.close(f)
                os.write(f, data)
            }
        }
    }

    // cubes_{run_id}.csv

    if f, oerr := os.create(fmt.tprintf("%s/cubes_%s.csv", t.output_dir, id)); oerr != nil {
        fmt.eprintfln("tracker: cubes csv: %v", oerr)
    } else {
        defer os.close(f)
        w: csv.Writer
        csv.writer_init(&w, os.to_writer(f))
        defer csv.writer_flush(&w)

        csv.write(&w, []string{
            "id", "x", "y", "z", "slices_scanned", "slices_with_suspects",
            "n_candidates", "n_kept", "n_discarded", "n_cuts_total", "n_pixels_cut",
        })
        for c in t.cubes^ {
            b: [10][24]u8
            csv.write(&w, []string{
                c.id,
                strconv.write_int(b[0][:], i64(c.x), 10),
                strconv.write_int(b[1][:], i64(c.y), 10),
                strconv.write_int(b[2][:], i64(c.z), 10),
                strconv.write_int(b[3][:], i64(c.slices_scanned), 10),
                strconv.write_int(b[4][:], i64(c.slices_with_suspects), 10),
                strconv.write_int(b[5][:], i64(c.n_candidates), 10),
                strconv.write_int(b[6][:], i64(c.n_kept), 10),
                strconv.write_int(b[7][:], i64(c.n_discarded), 10),
                strconv.write_int(b[8][:], i64(c.n_cuts_total), 10),
                strconv.write_int(b[9][:], i64(c.n_pixels_cut), 10),
            })
        }
    }

    // suspects_{run_id}.csv
    if f, oerr := os.create(fmt.tprintf("%s/suspects_%s.csv", t.output_dir, id)); oerr != nil {
        fmt.eprintfln("tracker: suspects csv: %v", oerr)
    } else {
        defer os.close(f)
        w: csv.Writer
        csv.writer_init(&w, os.to_writer(f))
        defer csv.writer_flush(&w)

        csv.write(&w, []string{
            "id", "cube_id", "x", "y", "z", "depth",
            "n_cuts", "n_pixels_cut", "kept", "discard_reason",
        })
        for s in t.suspects^ {
            b: [6][24]u8
            csv.write(&w, []string{
                s.id,
                s.cube_id,
                strconv.write_int(b[0][:], i64(s.x), 10),
                strconv.write_int(b[1][:], i64(s.y), 10),
                strconv.write_int(b[2][:], i64(s.z), 10),
                strconv.write_int(b[3][:], i64(s.depth), 10),
                strconv.write_int(b[4][:], i64(s.n_cuts), 10),
                strconv.write_int(b[5][:], i64(s.n_pixels_cut), 10),
                s.kept ? "true" : "false",
                s.discard_reason,
            })
        }
    }
}

tracker_print :: proc(t: Tracker){
    tot: cube_data
    for c in t.cubes^ {
        tot.slices_scanned       += c.slices_scanned
        tot.slices_with_suspects += c.slices_with_suspects
        tot.n_candidates         += c.n_candidates
        tot.n_kept               += c.n_kept
        tot.n_discarded          += c.n_discarded
        tot.n_cuts_total         += c.n_cuts_total
        tot.n_pixels_cut         += c.n_pixels_cut
    }

    id  := uuid.to_string(t.json.run_id, context.temp_allocator)
    sha := t.json.walksuvius_sha[:min(8, len(t.json.walksuvius_sha))]

    fmt.printfln("run %s | %s | scroll %s", id[:8], sha, t.json.scroll)
    fmt.printfln("cubes    %d", len(t.cubes^))
    fmt.printfln("slices   %d (%d with suspects)", tot.slices_scanned, tot.slices_with_suspects)
    fmt.printfln("suspects %d -> %d kept, %d discarded", tot.n_candidates, tot.n_kept, tot.n_discarded)
    fmt.printfln("cuts     %d (%d px)", tot.n_cuts_total, tot.n_pixels_cut)

    Reason :: struct{ text: string, n: int }
    counts := make(map[string]int, context.temp_allocator)
    for s in t.suspects^ do if !s.kept do counts[s.discard_reason] += 1
    if len(counts) > 0 {
        rs := make([dynamic]Reason, 0, len(counts), context.temp_allocator)
        for text, n in counts do append(&rs, Reason{text, n})
        slice.sort_by(rs[:], proc(a, b: Reason) -> bool { return a.n > b.n })
        for r in rs do fmt.printfln("  %-24s %d", r.text, r.n)
    }
}
