all: build

build-dev:
	odin build -debug -out:bin/walksuvius .

walk: build-dev
	bin/walksuvius walk ../GRID64/cubes_PRED

build-view: build-walk build-dev
	bin/walksuvius view PRED:../GRID64/cubes_PRED TAGGED:out/log/cubes_TAGGED RAW:../GRID64/cubes_RAW

build-walk: build-dev
	bin/walksuvius walk ../GRID64/cubes_PRED -- -log

view:
	bin/walksuvius view PRED:../GRID64/cubes_PRED TAGGED:out/log/cubes_TAGGED RAW:../GRID64/cubes_RAW

debugger: build-dev
	gdb --args bin/walksuvius walk ../GRID64/cubes_PRED -- -log

build:
	odin build -out:bin/walksuvius -show-timings -thread-count:25 .

benchmark:
	uv run scripts/gt_bench.py -n 64
