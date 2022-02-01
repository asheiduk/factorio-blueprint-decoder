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
