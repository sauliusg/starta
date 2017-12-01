
FIRST = cexceptions getoptions lists starta

DIRS  = ${FIRST} ${filter-out ${FIRST}, ${dir ${wildcard */Makefile}}}

.PHONY: all test tests alltests listdiff
.PHONY: bench benchmark benchmarks
.PHONY: clean cleanAll

all test tests shtests shtest alltests bench benchmark benchmarks listdiff:
	for i in ${DIRS} ; do \
	    ${MAKE} -C $$i $@; \
	done

clean:
	find . -name Makefile -exec dirname {} \; |\
	grep -vE '^\.$$' |\
	sed -e 's,^\./,,' |\
	xargs -n1 -t ${MAKE} $@ -C

cleanAll:
	find . -name Makefile -exec dirname {} \; |\
	grep -vE '^\.$$' |\
	sed -e 's,^\./,,' |\
	xargs -n1 -t ${MAKE} $@ -C
