.DELETE_ON_ERROR:

# basics
dats    = $(wildcard *.dat)
exports = $(wildcard *.export)

# derived from basic
diffs 	= $(exports:.export=.diff)
extrs	= $(exports:.export=.extr)

.PHONY: all json out extr diff clean

all: json out diff diff-report.txt

json: $(exports:.export=.json)

out: $(dats:.dat=.out)

clean:
	-rm -f *.out *.err
	-rm -f *.json
	-rm -f *.diff *.extr
	-rm -f diff-report.txt

# decode *.export to json

%.json: %.export
	../../decode-export-string < $< | jq -S . > $@

# decode *.dat to *.out / *.err

%.out %.err: %.dat
	../../decode -d $< > $*.out 2> $*.err

# extract each top-level object from *.out into *-$N.extr with $N = (index_number+1)

extr: $(extrs)

# libraries with only one object
%.extr: %.out
	jq '.blueprint_book.blueprints[0] | del(.index)' < $*.out > $*.extr

# libraries with multiple objects
%.extr:
	../tools/split-lib $<

# compare each *.json to *.extr

diff: $(diffs)


%.diff: %.json %.extr
	diff $*.json $*.extr > $@ 2>&1

# merge all *.diff into one report
diff-report.txt: $(diffs)
	for d in $(sort $(diffs)); do echo "#### $$d"; cat $$d; done > $@ 2>&1

# ---------------------
# dependencies between libraries with multiple objects to their extracted objects
# ---------------------

bps-combined-1.extr bps-combined-2.extr bps-combined-3.extr bps-combined-4.extr \
bps-combined-5.extr bps-combined-6.extr bps-combined-7.extr bps-combined-8.extr \
bps-combined-9.extr bps-combined-10.extr bps-combined-11.extr bps-combined-12.extr \
bps-combined-13.extr bps-combined-14.extr bps-combined-15.extr bps-combined-16.extr \
bps-combined-17.extr bps-combined-18.extr bps-combined-19.extr bps-combined-20.extr \
bps-combined-21.extr bps-combined-22.extr bps-combined-23.extr bps-combined-24.extr \
bps-combined-25.extr bps-combined-26.extr bps-combined-27.extr bps-combined-28.extr \
bps-combined-29.extr bps-combined-30.extr bps-combined-31.extr bps-combined-32.extr \
bps-combined-33.extr bps-combined-34.extr bps-combined-37.extr bps-combined-38.extr \
bps-combined-39.extr bps-combined-43.extr bps-combined-44.extr bps-combined-45.extr \
bps-combined-46.extr bps-combined-47.extr bps-combined-48.extr : bps-combined.out
