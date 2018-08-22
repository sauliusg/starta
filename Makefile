
FIRST = common cexceptions getoptions lists starta

DIRS  = ${FIRST} \
	$(filter-out $(addsuffix /,${FIRST}), $(dir $(wildcard */Makefile)))

.PHONY: all test tests alltests listdiff
.PHONY: bench benchmark benchmarks
.PHONY: clean cleanAll distclean

all test tests shtests shtest alltests bench benchmark benchmarks listdiff:
	for i in ${DIRS} ; do \
	    ${MAKE} -C $$i $@; \
	done

clean:
	find . -name Makefile -exec dirname {} \; |\
	grep -vE '^\.$$' |\
	sed -e 's,^\./,,' |\
	xargs -n1 -t ${MAKE} $@ -C

cleanAll distclean:
	find . -name Makefile -exec dirname {} \; |\
	grep -vE '^\.$$' |\
	sed -e 's,^\./,,' |\
	xargs -n1 -t ${MAKE} $@ -C
