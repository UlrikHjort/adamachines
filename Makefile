# Adamachines: tiny cars racing round the house, in Ada
# Copyright (c) 2026 Ulrik Hørlyk Hjort
# SPDX-License-Identifier: MIT
#
#   make         build the game
#   make run     build and start it
#   make test    the headless race checks, and a race over the network between two processes
#   make check   see that what the build needs is installed (make does this first)
#   make clean

all: game

check:
	@./check-deps.sh

game: check
	gprbuild -p -P adamachines.gpr -j0

run: game
	./bin/adamachines

test: check
	gprbuild -p -P simtest.gpr -j0
	./bin/simtest
	./bin/nettest host & H=$$!; sleep 0.5; ./bin/nettest join 127.0.0.1 && wait $$H
	./bin/nettest host & H=$$!; sleep 0.5; ./bin/nettest second && ./bin/nettest join find && wait $$H
	./bin/nettest host late & H=$$!; sleep 0.5; ./bin/nettest join 127.0.0.1 & J=$$!; sleep 1.5; ./bin/nettest late 127.0.0.1 && wait $$J && wait $$H

clean:
	gprclean -q -P adamachines.gpr
	gprclean -q -P simtest.gpr

.PHONY: all check game run test clean
