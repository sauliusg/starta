
FIRST = 
DIRS  = ${FIRST} ${filter-out ${FIRST}, ${dir ${wildcard */Makefile}}}

.PHONY: all clean cleanAll pdf

all clean cleanAll:
	@for d in ${DIRS}; do ${MAKE} -C $$d $@; done
