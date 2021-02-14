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

bps-1.0.0-tests-1.extr bps-1.0.0-tests-2.extr bps-1.0.0-tests-3.extr bps-1.0.0-tests-4.extr \
bps-1.0.0-tests-5.extr bps-1.0.0-tests-6.extr bps-1.0.0-tests-7.extr bps-1.0.0-tests-8.extr \
bps-1.0.0-tests-9.extr bps-1.0.0-tests-10.extr bps-1.0.0-tests-11.extr bps-1.0.0-tests-12.extr \
bps-1.0.0-tests-13.extr bps-1.0.0-tests-14.extr bps-1.0.0-tests-15.extr bps-1.0.0-tests-16.extr \
bps-1.0.0-tests-17.extr bps-1.0.0-tests-18.extr bps-1.0.0-tests-19.extr bps-1.0.0-tests-20.extr \
bps-1.0.0-tests-21.extr bps-1.0.0-tests-22.extr bps-1.0.0-tests-23.extr bps-1.0.0-tests-24.extr \
bps-1.0.0-tests-25.extr bps-1.0.0-tests-26.extr bps-1.0.0-tests-27.extr bps-1.0.0-tests-28.extr \
bps-1.0.0-tests-29.extr bps-1.0.0-tests-30.extr bps-1.0.0-tests-31.extr bps-1.0.0-tests-32.extr \
bps-1.0.0-tests-33.extr bps-1.0.0-tests-34.extr bps-1.0.0-tests-35.extr bps-1.0.0-tests-37.extr \
bps-1.0.0-tests-38.extr bps-1.0.0-tests-39.extr bps-1.0.0-tests-40.extr bps-1.0.0-tests-43.extr \
bps-1.0.0-tests-44.extr bps-1.0.0-tests-45.extr bps-1.0.0-tests-46.extr bps-1.0.0-tests-47.extr \
bps-1.0.0-tests-48.extr : bps-1.0.0-tests.out
