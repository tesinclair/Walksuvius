# Walksuvius

A CLI tool for finding and cutting joins in cube predictions before we reach meshing.

Where two wraps of papyrus sit close together, the surface prediction sometimes fuses them into one connected blob. Marching cubes then happily meshes straight across the join, and the trace jumps sheets. Walksuvius works on the prediction cubes before any of that happens: it looks at each 2D slice, finds the places where two wraps have been bridged, and cuts the bridge.

The cut doesn't need to be wide. It only needs to *disconnect* the voxels — once the two wraps are no longer one connected component, marching cubes emits two separate surfaces on its own, and nothing downstream ever has to be told about it. That means the output is just corrected TIFFs, and they drop straight into your existing pipeline with no changes.

## Viewsuvius

A CLI tool for viewing cubes by slice, currently integrated into walksuvius via the `view` command but soon to be its own binary.

## Roadmap

- [x] Phase 1: Finds and catalogues suspected junctions which require cutting
- [ ] Phase 2: Determine each junctions type, and remove the minimum required pixels to separate the layers

# Usage

### Prerequisites

You'll need Odin, which is simple to install and setup, a tutorial can be found [here](https://odin-lang.org/docs/install/)

You may also need to compile the raylib binaries (built into Odin) -- you will be told if this is the case.

You will also need a directory of predicted cubes. See [Input format](#input-format) below for what walksuvius expects them to look like, because it's fussier than you'd hope.

## Quick Commands

Once you have Odin and make installed you can run these commands:

```
git clone --depth=1 https://github.com/tesinclair/walksuvius
cd walksuvius
odin build -out:bin/walksuvius -o:speed -define:GIT_SHA=$$(git rev-parse HEAD || "") .
```

While there is a Makefile most of these are specific to my setup and you may not wish to use it--though you may.

After the binary is built you can run:

`bin/walksuvius walk <path/to/cubes_PRED> -- -log`

Which will output a breakdown of its findings along with a set of tagged cubes to `out/log/cubes_TAGGED` you can view with viewsuvius.

Technically you can cut as-is, and output to out/cubes_CUT by omitting the `-log` flag, however this isn't recommended, as the current cuts are not behaving.


To view the tagged cubes:

`bin/walksuvius view PRED:<path/to/cubes_PRED> TAGGED:out/log/cubes_TAGGED`

The PRED cubes are optional here and are only useful for comparison. You can also use view for any cubes you wish, including raw. The only requirement is that
for colour coding to be enabled for the tagged cube output, the TAGGED: label must be used. (Hence, TAGGED:out/cubes_TAGGED).

Arrow keys move you around: up and down step through the 128 slices of the current cube, left and right step between cubes. Space cycles through whichever tags you passed in. The colour scheme for tagged output is in [tagging.md](tagging.md).

### Options

Options go after the `--`, and only apply to `walk`:

- `-log` — write colour-tagged cubes to `out/log/cubes_TAGGED/` instead of cut cubes to `out/cubes_CUT/`
- `-verbose` — print progress per cube and per slice, plus the blobs found. Mostly used for debug, and does not give super useful info for non-debugging purposes

## Input format

Right now the input format is fairly unforgiving since tiff parsing is done manually. Walksuvius expects:

- **128×128×128 cubes, one byte per voxel.** These are binary on/off surface predictions, not the raw u16 scan data.
- **Filenames of the form `z_y_x.tif`** — three underscore-separated coordinates, which is where the cube gets its world position from.
- **The cube directory itself**, not a parent directory of cube directories.

One more thing worth knowing: the TIFF reader doesn't parse IFDs. It assumes a fixed 256-byte header, then the voxel data, then a fixed-size footer, and it copies the header and footer through untouched so the output stays byte-compatible with the input. That works fine for cubes produced the same way mine were, and *should* work for most but if it breaks this may be why. In that event raise an issue and I'll start on better tiff parsing.

## Known limitations

Phase 1 works, but I'd rather tell you where it's weak than let you find out yourself:

- **Nothing here is benchmarked against ground truth yet.** I have no numbers on how many real bridges it catches or how many it invents. My local prediction grid doesn't overlap the public labelled cubes, so this needs prediction cubes fetched at the GT coordinates first.
- **The "touches two or more borders" discard filter is unsound.** It was meant to throw out gaps that run clean through the cube, but real bridges don't always touch fewer than two borders, so some genuine merges are being dropped before they're ever considered.
- **Junction detection over-reports.** Walking a junction continues down all three branches, so junctions get flagged on paths that weren't suspected. Requiring a target's neighbour to be tagged suspect helped a lot but didn't fix it completely.
- **There's a stray cut pixel bug.** Occasionally a single cut pixel appears disconnected from the rest of the cut line. I think it's a coordinate wrap-around in the neighbour lookup.
- **`walk` only reads cubes under the `PRED` tag.** If you tag your input directory as anything else, it won't find them.
- **Cut geometry is Phase 2.** Right now the cut line is chosen by a rough smallest-clump heuristic, and it's often the wrong line even when the junction itself was correctly found.

## Licence

MIT. See [LICENSE](LICENSE).


## AI Note

This is for anyone wishing to contribute. AI authored code is not allowed in this repository unless in the following cases:

1. All documentation may be written with AI.
2. Scripts may be written with AI, but should never exist outside of the `scripts/` directory
