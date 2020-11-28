
parsable_dats = \
	bps-inserters.dat \
	bps-connected-inserters.dat \
	bps-inserters-circuit.dat \
	bps-three-blueprints.dat \
	bps-constant-combinator.dat \
	bps-signal-names.dat \
	bps-one-empty-blueprint.dat \
	bps-chests.dat \
	bps-pipes.dat \
	bps-with-tiles.dat \
	bps-empty.dat \
	bps-books.dat \
	bps-planner.dat \
	bps-planner-ids.dat \
	bps-belts.dat \
	bps-electric-poles.dat \
	bps-mining.dat \
	bps-assembler.dat \
	bps-furnaces.dat \
	bps-tanks-pumps.dat \
	bps-rails.dat \
	bps-rail-signals.dat \
	bps-train-stops.dat \
	bps-power-entities.dat \
	bps-combat-simple.dat \
	bps-misc.dat \
	bps-combinators.dat \
	bps-lamps.dat \
	bps-speakers.dat \
	bps-power-switch.dat \
	bps-switch+combinator.dat \

unparsable_dats = \
	bps-most-buildings.dat \

exports = $(wildcard *.export)

.PHONY: all json test clean

all: json test

json: $(exports:.export=.json)

test: $(parsable_dats:.dat=.out)

clean:
	-rm -f *.out
	-rm -f *.json
	-rm -f *.tst

%.json: %.export
	../decode-export-string < $< | jq -S . > $@

%.out: %.dat
	../decode.pl $< > $*.tst
	mv $*.tst $@
