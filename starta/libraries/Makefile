
FIRST = 
DIRS  = ${FIRST} ${filter-out ${FIRST}, ${dir ${wildcard */Makefile}}}

.PHONY: all clean cleanAll distclean pdf

all clean cleanAll distclean:
	@for d in ${DIRS}; do ${MAKE} -C $$d $@; done
