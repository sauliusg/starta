#------------------------------------------------------------------------------
#$Author$
#$Revision$
#$Date$
#$URL$
#------------------------------------------------------------------------------

MAKECONF_EXAMPLES = ${filter-out %~, ${wildcard Makeconf*.example}}

MAKECONF_FILES = ${filter-out %~, ${wildcard Makeconf*}} \
	${MAKECONF_EXAMPLES:%.example=%}

ifneq ("${MAKECONF_FILES}","")
include ${MAKECONF_FILES}
endif

INCLUDES = -I. ${addprefix -I, ${sort ${SRC_DIR} ${OTHER_DIRS} ${LIB_DIRS}}}

CC = gcc
CFLAGS = -g -Wall ${INCLUDES}

C  = ${wildcard *.c}
X  = ${C:%.c=%}
XO = ${C:%.c=%_o}

.PHONY: all test tests alltests listdiff
.PHONY: bench benchmark benchmarks
.PHONY: clean cleanAll distclean

all: ${X} ## ${XO}

# A file can be create from a repository-committed example; used for
# Makeconfig files:

%: %.example
	cp $< $@

%.o: %.c
	${CC} ${CFLAGS} $< -o $@

lsopcodes: lsopcodes.o
	${CC} ${LDFLAFS} $< -o $@ -ldl

clean cleanAll distclean:
	rm -f ${X} ${XO} interpret.o

test tests alltests bench benchmark benchmarks listdiff : # do nothing
	@true
