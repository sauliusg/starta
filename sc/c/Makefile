
CC = gcc
CFLAGS = -g -Wall -I.

C  = ${wildcard *.c}
X  = ${C:%.c=%}
XO = ${C:%.c=%_o}

.PHONY: all test tests alltests listdiff
.PHONY: bench benchmark benchmarks
.PHONY: clean cleanAll

all: ${X} ## ${XO}

%_o: %.c
	${CC} ${CFLAGS} $< -o $@

lsopcodes: lsopcodes.o
	${CC} ${LDFLAFS} $< -o $@ -ldl

clean cleanAll:
	rm -f ${X} ${XO} interpret.o

test tests alltests bench benchmark benchmarks listdiff : # do nothing
	@true
