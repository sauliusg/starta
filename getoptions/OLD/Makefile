
vpath %.c ./tests
vpath %.h ./include

INSTALL_DIR = ${HOME}
INCLUDE_DIR = ${INSTALL_DIR}/include
LIB_DIR     = ${INSTALL_DIR}/lib

HEADER_FILES = ${wildcard *.h}
LIB = libgetopt.a

CFLAGS    = -g -Wall -I. -I./include -I./tests -I${HOME}/include
LDFLAGS   = -L${HOME}/lib -lcex
CFILES    = ${wildcard *.c}
TESTFILES = ${wildcard tests/t*.c}
OBJFILES  = ${CFILES:%.c=%.o}
EXEFILES  = ${TESTFILES:tests/%.c=%}

CC = gcc

#------------------------------------------------------------------------------

.PHONY: all tests install clean cleanAll

all: ${LIB} tests

tests: ${EXEFILES}

#------------------------------------------------------------------------------

${LIB}: ${OBJFILES}
	${AR} -rs $@ $^

%: %.c ${LIB}
	${CC} ${CFLAGS} $^ -o $@ ${LDFLAGS}

#------------------------------------------------------------------------------

install: ${LIB}
	cp ${HEADER_FILES} ${INCLUDE_DIR}
	cp ${LIB} ${LIB_DIR}

uninstall:
	rm -f ${INCLUDE_DIR}/${HEADER_FILES}
	rm -f ${LIB_DIR}/${LIB}

#------------------------------------------------------------------------------

clean:
	rm -f a.out *.o
	rm -f tests/*.o
	rm -f ${EXEFILES}

cleanAll: clean
	rm -f ${LIB}
	rm -f .*.d
