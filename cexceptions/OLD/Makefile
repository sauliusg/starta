
vpath %.c ./tests
vpath %.h ./include

INSTALL_DIR = ${HOME}
INCLUDE_DIR = ${INSTALL_DIR}/include
LIB_DIR     = ${INSTALL_DIR}/lib

CC = gcc

CFLAGS    = -g -Wall -I./include -I./tests
CFILES    = ${wildcard *.c}
TESTFILES = ${wildcard tests/t*.c}
OBJFILES  = ${CFILES:%.c=%.o}
EXEFILES  = ${TESTFILES:tests/%.c=%}

LIB = libcex.a

#------------------------------------------------------------------------------

.PHONY: all tests install clean cleanAll

all: ${LIB}

tests: ${EXEFILES}

#------------------------------------------------------------------------------

tsubsystems: tsubsystems.o subsystem_a.o subsystem_b.o ${OBJFILES}
	${CC} -o $@ $^

texceptions: texceptions.o ${OBJFILES}
	${CC} -o $@ $^

tstrdupx: tstrdupx.o ${OBJFILES}
	${CC} -o $@ $^

tfinaly: tfinaly.o ${OBJFILES}
	${CC} -o $@ $^

${OBJFILES}: cexceptions.h

${LIB}: ${OBJFILES}
	${AR} -rs $@ $^

#------------------------------------------------------------------------------

install: ${LIB}
	cp include/*.h ${INCLUDE_DIR}
	cp ${LIB} ${LIB_DIR}

#------------------------------------------------------------------------------

clean:
	rm -f a.out *.o
	rm -f tests/*.o
	rm -f ${EXEFILES}

cleanAll: clean
	rm -f ${LIB}
	rm -f .*.d
