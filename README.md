# Walksuvius

A CLI tool for finding the places where a surface prediction has fused two wraps of papyrus into one.

Where two wraps sit close together, the prediction sometimes joins them into a single connected blob. Marching cubes then meshes straight across the join, and the trace jumps sheets. Walksuvius works on the prediction cubes before any of that happens: it goes slice by slice, finds where two wraps have been bridged, and writes out a catalogue of every one it found.

It can also cut them. That part is experimental and I'd not trust it yet -- see [Cutting](#cutting) below.

*Note:* Viewsuvius is a CLI tool for viewing cubes by slice, currently bolted onto walksuvius via the `view` command but soon to be its own binary.

## How it finds them

Take a clean cross-section of a scroll. Each wrap crosses that slice as its own separate arc, so if you skeletonise the prediction you should get a forest -- a set of curves with no loops in them.

A loop means two arcs have been joined at two points. That is a merge. So the detector is really just a loop finder: skeletonise each slice, flood fill the space *between* the skeleton curves, and any region that comes back enclosed is a cycle, and a cycle is a candidate bridge. Walk its boundary, find the branch points, and those are where the two wraps are stuck together.

That's the whole idea. It's cheap, it needs no model and no training data, and it runs on predictions you already have.


## Roadmap

- [x] Phase 1: Set up basic architecture, find suspected merges, and document

- [ ] Phase 2: Perfect merge detection, and improve documentation method
    - [ ] Replace the border filter with a connectivity test

- [ ] Phase 3: Fully integrate with existing pipeline

# Usage

### Prerequisites

You'll need Odin, which is simple to install and set up, a tutorial can be found [here](https://odin-lang.org/docs/install/).

You may also need to compile the raylib binaries (built into Odin) -- you will be told if this is the case.

You will also need a directory of predicted cubes. See [Input format](#input-format) below for what walksuvius expects them to look like, because it's fussier than you'd hope.

## Quick commands

```
git clone --depth=1 https://github.com/tesinclair/walksuvius
cd walksuvius
odin build -out:bin/walksuvius -o:speed -define:GIT_SHA=$(git rev-parse HEAD || "") .
```

There is a Makefile, but most of it is specific to my setup and you may not wish to use it -- though you may.

Then:

`bin/walksuvius walk <path/to/cubes_PRED>`

That writes the catalogue to `out/data/` and a set of colour-tagged cubes to `out/log/cubes_TAGGED/` you can page through with viewsuvius. To view them:

`bin/walksuvius view PRED:<path/to/cubes_PRED> TAGGED:out/log/cubes_TAGGED`

The PRED cubes are optional and only useful for comparison. You can point `view` at any cubes you like, including raw. The one requirement is that the `TAGGED:` label must be used for colour coding to switch on.

Arrow keys move you around: up and down step through the 128 slices of the current cube, left and right step between cubes. Space cycles through whichever tags you passed in. The colour key is in [tagging.md](tagging.md).

## Output

**out/data/**:

1. `cubes_<run_id>.csv` -- a breakdown of the findings per cube
2. `suspects_<run_id>.csv` -- a breakdown per suspected merge
3. `run.json` -- a high level overview of the run

These are also condensed and printed to the console.

**out/log/cubes_TAGGED/** -- the colour-coded cubes, for viewing.

**out/cut/cubes_CUT/** -- only written with `-cut`. See [Cutting](#cutting).

### Options

Options go after the `--`, and only apply to `walk`:

- `-cut` -- write cut cubes instead of tagged ones. Experimental, and currently wrong more often than it's right.
- `-verbose` -- print progress per cube and per slice, plus the blobs found. Mostly for debugging, and not much use otherwise.

## Input format

The input format is unforgiving, since TIFF parsing is done by hand. Walksuvius expects:

- **128x128x128 cubes, one byte per voxel.** Binary on/off surface predictions, not raw u16 scan data.
- **Filenames of three underscore-separated integers**, `z00000_y00000_x00000.tif`, which is where the cube gets its world position from.
- **The cube directory itself**, not a parent directory of cube directories.

### Where the cubes come from

Mine were carved out of the open data bucket with `carve_grid_tifs.py` from [scrollfiesta](https://github.com/Hob3rMallow/scrollfiesta_public), which bridges the Zarr world to exactly this TIFF grid layout:

```
uv run --project python python/scripts/carve_grid_tifs.py \
  --pred-zarr s3://vesuvius-challenge-open-data/PHerc0139/representations/predictions/surfaces/20250728140407-surface-20260413222639-surface-m7-L0-th0.2.zarr \
  --raw-zarr  s3://vesuvius-challenge-open-data/PHerc0139/volumes/20250728140407-9.362um-1.2m-113keV-masked.zarr \
  --bbox 4352 4864 3328 3840 2816 3328 \
  --umbilicus 3405 2878 \
  --out GRID64
```

That's PHerc. 139, a 4x4x4 block of cubes, which is what everything here has been developed against. It writes `cubes_PRED/`, `cubes_RAW/`, and a `manifest.json` recording the bbox, the umbilicus and both source URLs. Run it from inside the scrollfiesta checkout -- `--project python` matters, since it imports from `python/src`.

### On the TIFF reader

The TIFF reader is very very minimal right now.

It doesn't parse IFDs. It assumes a fixed 256-byte header, then the voxel data, then a fixed-size footer, and copies the header and footer through untouched so the output stays byte-compatible with the input.

Those constants aren't arbitrary, and they're narrower than I'd like. `carve_grid_tifs` calls `tifffile.imwrite` on a 128^3 uint8 array with no compression and one strip per row-block, which puts page 0's header and IFD inside the first 256 bytes, lays the pixel data down contiguously, and appends the other 127 IFDs at the end -- 127 x 166 = 21082 bytes, which is the footer. So the reader works on the output of that one call, at that version of tifffile. It'll likely work on anything else written the same shape, but if it breaks, this is why. Raise an issue and I'll get on with proper parsing.

## Known limitations

There are quite a few limitations in its current state:

The format is \[Issue\]. \<summary\> (Phase)

- **The "touches two or more borders" discard filter is unsound.** It's a proxy for "is this loop enclosed". A merge sitting near an edge gets thrown out. The proper test is whether the two skeleton arcs either side of a gap belong to the same connected component: if they do it's a merge, however many borders it touches. (Phase 2)

- **Cutting slice by slice doesn't guarantee a 3D separation.** Marching cubes works in 3D. If the cut line in one slice sits a pixel off the cut in the next, the two sheets stay diagonally connected and the merge survives meshing even though the output looks cut. Nothing currently enforces continuity of the cut in z. This is the main reason cutting is behind a flag. (Phase 2)

- **The slicing axis is arbitrary.** Slices are taken along the cube's local z, which has no particular relationship to the scroll's axis. Wraps only read as clean concentric arcs when you slice roughly perpendicular to the roll; off-axis, one wrap can appear as several arcs and the loop count stops meaning what I want it to mean. The umbilicus is sitting in the manifest and would give the radial direction at any voxel -- a real merge bridges two sheets adjacent in radius, so the bridge ought to run roughly radially, and a fold generally won't. Not used yet. (Phase 2)

- **Junction detection over-reports.** Walking a junction continues down all three branches, so junctions get flagged on paths that weren't suspected. Requiring a target's neighbour to be tagged suspect helped but didn't fix it. Requiring the junction to actually close a cycle should fix the rest. (Phase 2)

- **The manifest is ignored.** The umbilicus is generally available but walksuvius doesn't read it yet (hence why scroll name is still Unknown) (Phase 2)

- **TIFF only.** No Zarr yet. In fact cubes should only be in the format given (Phase 3)

- **Not scalable.** Right now there is a lot of rescanning, no multithreading, and no gpu acceleration, so it is quite slow per cube. (Phase 3)

## Licence

MIT. See [LICENSE](LICENSE).

## AI Note

For anyone wishing to contribute. AI authored code is not allowed in this repository except in the following cases:

1. All documentation may be written with AI.
2. Scripts may be written with AI, but should never exist outside of the `scripts/` directory.

# Experimental Features

## Cutting

The cut doesn't need to be wide. It only needs to *disconnect* the voxels -- once the two wraps are no longer one connected component, marching cubes emits two separate surfaces on its own, and nothing downstream ever has to be told about it. The output is just corrected TIFFs, and they drop back into your existing pipeline with no changes.

That's the goal. What's implemented right now is a rough heuristic that raycasts out from the branch point in eight directions and cuts along whichever span is shortest, and it picks the wrong line often enough that I'd not run it on anything you care about. It's behind a flag for that reason.

Phase 2 is to replace it with a proper minimum cut. "Remove the fewest voxels needed to separate the layers" is the definition of a min cut, so it should be solved as one -- max-flow on the voxel graph in a small box around the junction, seeded on either sheet. That's better formed than what's there now: it works in 3D rather than slice by slice, it's provably minimal, and it can follow an oblique bridge instead of being stuck on the eight raycast directions.

It doesn't, on its own, fix the deeper problem. Inside a fused blob every voxel is a 1, so there's nothing in the mask that says one line through the bridge is better than another. Unweighted, a min cut is still just a shorter shortest line. The signal that would actually settle it is how confident the model was -- a spurious merge is usually a low-probability ridge between two high-probability sheets, and thresholding flattens that to a uniform 1 before walksuvius ever sees it. So the plan is to take a second, unthresholded cube as an optional input and weight the cut by it, falling back to geometry when one isn't supplied. `carve_grid_tifs` already writes `cubes_RAW/` on the same grid with the same filenames, so the attenuation is there to try even before anyone re-runs inference. Binary is the right input for finding the merges; it just isn't enough for choosing where to cut them.

