all: build

build-dev:
	odin build -debug -out:bin/walksuvius -define:GIT_SHA=$$(git rev-parse HEAD || "") .

walk: build-dev
	bin/walksuvius walk ../GRID64/cubes_PRED

build-view: build-dev
	bin/walksuvius view PRED:../GRID64/cubes_PRED TAGGED:out/cubes_TAGGED RAW:../GRID64/cubes_RAW

build-walk: build-dev
	bin/walksuvius walk ../GRID64/cubes_PRED

view:
	bin/walksuvius view PRED:../GRID64/cubes_PRED TAGGED:out/cubes_TAGGED RAW:../GRID64/cubes_RAW

debug: build-dev
	gdb --args bin/walksuvius walk ../GRID64/cubes_PRED

build:
	odin build -out:bin/walksuvius -show-timings -thread-count:25 -define:GIT_SHA=$$(git rev-parse HEAD) .
