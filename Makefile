# Adamachines: tiny cars racing round the house, in Ada
# Copyright (c) 2026 Ulrik Hørlyk Hjort
# SPDX-License-Identifier: MIT
#
#   make         build the game
#   make run     build and start it
#   make test    the headless race check
#   make clean

all: game

game:
	gprbuild -p -P adamachines.gpr -j0

run: game
	./bin/adamachines

test:
	gprbuild -p -P simtest.gpr -j0
	./bin/simtest

clean:
	gprclean -q -P adamachines.gpr
	gprclean -q -P simtest.gpr

.PHONY: all game run test clean
