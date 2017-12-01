
FIRST = 
DIRS  = ${FIRST} ${filter-out ${FIRST}, ${dir ${wildcard */Makefile}}}

ALL_TARGETS = all clean cleanAll test tests shtests alltests listdiff \
    bench benchmark benchmarks

.PHONY: ${ALL_TARGETS}

${ALL_TARGETS}:
	@for d in ${DIRS}; do ${MAKE} -C $$d $@; done
