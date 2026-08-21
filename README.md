# Walksuvius

A CLI tool for finding the places where a surface prediction has fused two wraps of papyrus into one.

Where two wraps sit close together, the prediction sometimes joins them into a single connected blob. Marching cubes then meshes straight across the join, and the trace jumps sheets. Walksuvius works on the prediction cubes before any of that happens: it goes slice by slice, finds where two wraps have been bridged, and writes out a catalogue of every one it found.

It can also cut them. That part is experimental and I'd not trust it yet -- see [Cutting](#cutting) below.

## How it finds them

Take a clean cross-section of a scroll. Each wrap crosses that slice as its own separate arc, so if you skeletonise the prediction you should get a forest -- a set of curves with no loops in them.

A loop means two arcs have been joined at two points. That is a merge. So the detector is really just a loop finder: skeletonise each slice, flood fill the space *between* the skeleton curves, and any region that comes back enclosed is a cycle, and a cycle is a candidate bridge. Walk its boundary, find the branch points, and those are where the two wraps are stuck together.

That's the whole idea. It's cheap, it needs no model and no training data, and it runs on predictions you already have.

## Cutting

The cut doesn't need to be wide. It only needs to *disconnect* the voxels -- once the two wraps are no longer one connected component, marching cubes emits two separate surfaces on its own, and nothing downstream ever has to be told about it. The output is just corrected TIFFs, and they drop back into your existing pipeline with no changes.

That's the goal. What's implemented right now is a rough heuristic that raycasts out from the branch point in eight directions and cuts along whichever span is shortest, and it picks the wrong line often enough that I'd not run it on anything you care about. It's behind a flag for that reason.

Phase 2 is to replace it with a proper minimum cut. "Remove the fewest voxels needed to separate the layers" is the definition of a min cut, so it should be solved as one -- max-flow on the voxel graph in a small box around the junction, seeded on either sheet, weighted by the model's confidence so the cut follows the weakest evidence rather than the shortest line. That also fixes the 3D problem described in [Known limitations](#known-limitations).

## Viewsuvius

A CLI tool for viewing cubes by slice, currently bolted onto walksuvius via the `view` command but soon to be its own binary.

## Roadmap

- [x] Phase 1: find and catalogue the merges
- [ ] Replace the border filter with a connectivity test (see limitations)
- [ ] Benchmark against ground truth
- [ ] Phase 2: cut by min-cut rather than by heuristic
- [ ] Read Zarr

# Usage

### Prerequisites

You'll need Odin, which is simple to install and set up, a tutorial can be found [here](https://odin-lang.org/docs/install/).

You may also need to compile the raylib binaries (built into Odin) -- you will be told if this is the case.

You will also need a directory of predicted cubes. See [Input format](#input-format) below for what walksuvius expects them to look like, because it's fussier than you'd hope.

## Quick commands

```
git clone --depth=1 https://github.com/tesinclair/walksuvius
cd walksuvius
odin build -out:bin/walksuvius -o:speed -define:GIT_SHA=$$(git rev-parse HEAD || "") .
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
- **Filenames of the form `z_y_x.tif`** -- three underscore-separated coordinates, which is where the cube gets its world position from.
- **The cube directory itself**, not a parent directory of cube directories.

The TIFF reader doesn't parse IFDs. It assumes a fixed 256-byte header, then the voxel data, then a fixed-size footer, and copies the header and footer through untouched so the output stays byte-compatible with the input. That works for cubes produced the same way mine were, and *should* work for most, but if it breaks this is probably why. Raise an issue and I'll get on with proper parsing.

## Known limitations

I'd rather tell you where this is weak than let you find out yourself.

- **Nothing is benchmarked yet.** I have no numbers on how many real merges it catches or how many it invents. My prediction grid doesn't overlap the public labelled cubes, so this needs predictions run at the ground truth coordinates first. Synthetic merges injected into clean regions would at least give a recall figure in the meantime.

- **The "touches two or more borders" discard filter is unsound.** It's a proxy for "is this loop enclosed", and the cube border isn't a real feature -- it's just where I happened to crop. A merge sitting near an edge gets thrown out. The proper test is whether the two skeleton arcs either side of a gap belong to the same connected component: if they do it's a merge, however many borders it touches. That's a union-find and it's cheaper than what's there now.

- **Cutting slice by slice doesn't guarantee a 3D separation.** Marching cubes works in 3D. If the cut line in one slice sits a pixel off the cut in the next, the two sheets stay diagonally connected and the merge survives meshing even though the output looks cut. Nothing currently enforces continuity of the cut in z. This is the main reason cutting is behind a flag.

- **The slicing axis is arbitrary.** Slices are taken along the cube's local z, which has no particular relationship to the scroll's axis. Wraps only read as clean concentric arcs when you slice roughly perpendicular to the roll; off-axis, one wrap can appear as several arcs and the loop count stops meaning what I want it to mean. I haven't measured how much this costs.

- **Junction detection over-reports.** Walking a junction continues down all three branches, so junctions get flagged on paths that weren't suspected. Requiring a target's neighbour to be tagged suspect helped but didn't fix it. Requiring the junction to actually close a cycle should fix the rest.

- **Neighbour lookups wrap around the slice.** The pixel lookup indexes with `x + y*128` and only bounds-checks the offset, not x -- so the left neighbour of a column-0 pixel is a valid index pointing at the end of the row above. This is the stray cut pixel, and it quietly corrupts blob membership and junction detection near the vertical borders too. Known, being fixed.

- **It only reads binary predictions.** The model's soft probabilities and the raw scan are both thrown away, and both are better evidence than geometry for telling a prediction artefact apart from two sheets that genuinely touch. A real merge is usually a low-confidence region with an attenuation dip still visible underneath.

- **The catalogue records the slice position, not the position of the find.** So it tells you which slice a merge is in but not where in it, which makes it harder to go and look at than it should be. Centroid and bounding box are coming.

- **TIFF only.** No Zarr, which is what everything else in the pipeline actually streams.

- **It won't scale to a full grid yet.** There are per-slice leaks, and the per-cube summary rescans the whole accumulated suspect list, so it goes quadratic. Fine on 64 cubes, not fine on a scroll.

- **`walk` only reads cubes under the `PRED` tag.** Tag your input directory as anything else and it won't find them.

## Licence

MIT. See [LICENSE](LICENSE).

## AI Note

For anyone wishing to contribute. AI authored code is not allowed in this repository except in the following cases:

1. All documentation may be written with AI.
2. Scripts may be written with AI, but should never exist outside of the `scripts/` directory.
