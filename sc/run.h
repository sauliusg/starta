/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

#ifndef __RUN_H
#define __RUN_H

#include <stackcell.h>
#include <cexceptions.h>
#include <thrcode_t.h>
#include <thrcode.h>

typedef struct interpret_exception_t interpret_exception_t;

typedef enum { 
  INTERPRET_OK = 0,
  INTERPRET_BAD_OPCODE,
  INTERPRET_ESTACK_OVERFLOW,
  INTERPRET_ESTACK_UNDERFLOW,
  INTERPRET_RSTACK_OVERFLOW,
  INTERPRET_RSTACK_UNDERFLOW,
  INTERPRET_JUMP_OUTSIDE_LIMITS,
  INTERPRET_UNHANDLED_EXCEPTION,
  INTERPRET_OUT_OF_MEMORY,
  INTERPRET_FILE_OPEN_ERROR,
  INTERPRET_FILE_READ_ERROR,
  INTERPRET_FILE_WRITE_ERROR,
  INTERPRET_EXTERNAL_LIBRARY_ERROR,

  last_INTERPRET_ERROR
} interpret_error_t;

/* sl_exception_t

   These are the default SL language exceptions raised by the
   interpreter standard ifunctions (interpreting functions). If you
   add a new exception here, you will most probably want to add its
   name into the 'default_exceptions' array, so that
   snail_insert_default_exceptions() adds it into the symbol table and
   SL programs can catch it by name. */

typedef enum {
  SL_EXCEPTION_NULL = 0,

  SL_EXCEPTION_TEST_EXCEPTION, /* just for testing purposes... */
  SL_EXCEPTION_OUT_OF_MEMORY,
  SL_EXCEPTION_FILE_OPEN_ERROR,
  SL_EXCEPTION_FILE_READ_ERROR,
  SL_EXCEPTION_FILE_WRITE_ERROR,
  SL_EXCEPTION_NULL_ERROR,     /* null pointer dereferencing, also in
				  file read/write */
  SL_EXCEPTION_INTERPRETER_ERROR,
  SL_EXCEPTION_SYSTEM_ERROR,
  SL_EXCEPTION_EXTERNAL_LIB_ERROR,
  SL_EXCEPTION_MISSING_INCLUDE_PATH,
  SL_EXCEPTION_HASH_FULL,
  SL_EXCEPTION_BOUND_ERROR, /* array or string indexing beyond the bounds */
  SL_EXCEPTION_BLOB_OVERFLOW,
  SL_EXCEPTION_BLOB_BAD_DESCR, /* unsuitable "unpack" or "pack" description */
  SL_EXCEPTION_ARRAY_OVERFLOW,
  SL_EXCEPTION_TRUNCATED_INTEGER,

  last_SL_EXCEPTION
} sl_exception_t;

extern void *interpret_subsystem;

struct interpret_exception_t {
  stackcell_t old_xp;    /* old value of the exception pointer
				    xp, which must be restored to the
				    bytecode interpreter's xp
				    "register" when the current
				    try-scope is left */
  stackcell_t message;   /* human-readable message describing what has
			    happened */
  ssize_t ip;            /* saved bytecode instruction pointer */
  stackcell_t *fp;       /* saved function/procedure call frame
                            pointer */
  stackcell_t *sp;       /* saved stack pointer */
#if 0
  stackcell_t *gp;       /* Global pointer, or ground pointer --
			    points to the stack frame of the main
			    program (the very first stack frame) */
#endif
  stackcell_t *ep;       /* saved evalueation stack pointer */
  ssize_t catch_offset;  /* offset to the catch code (exception
			    handler), relative to the ip value saved
			    in this structure */
  int error_code;        /* A user-defined error code associated with
			    the exception. */
  char *module;          /* identifier (unique name) of the module
			    that raises given exception. Note: this
			    pointer should be neither garbage
			    collected nor freed, it will point to a
			    static or otherwise controlled memory. */
  int exception_id;      /* number (unique identifier) of the
			    exception that has been raised */
};

/* INTERPRET_EXCEPTION_PTRS is a number of garbage collected pointers
   in interpret_exception_t, to be used when allocating
   interpret_exception_t on the heap.
 */

#define INTERPRET_EXCEPTION_PTRS 2

/* istate_t describes a state of the bytecode interpreter.
   This structure should be all we need to save and restore when switching
   contexts, e.g. when switching threads or interpreting another piece
   of bytecode (subcode).
 */

typedef struct runtime_data_node runtime_data_node;

typedef struct {
    thrcode_t *code;      /* array of 'opcodes' (funtion addresses) */
    size_t code_length;   /* length of the vector *code */
    char *static_data;    /* static data used by some commands */
    ssize_t static_data_size;
    runtime_data_node *extra_data;     
    /* Extra data, allocated during run time and not garbage collected
       -- for instance, binary representations allocated for the
       optimized DLDC (double load constant) commands. These data
       should live as long as the code is necessary (since there may
       be pointers in the code to those nodes) and can be free'd when
       the interpreter finishes. */

    stackcell_t *sp, *fp; /* stack pointer, frame pointer */
    stackcell_t *ep;      /* evaluation stack pointer */
    ssize_t ip;           /* bytecode instruction pointer: */
    stackcell_t *gp;      /* Global pointer, or ground pointer --
			     points to the stack frame of the main
			     program (the very first stack frame);
			     that's where all global variable will be
			     placed. */
    stackcell_t *bottom, *top;  /* stack upper and lower limits */
    stackcell_t *ep_bottom, *ep_top; /* limits of evaluation stack */
    interpret_exception_t *xp;  /* exception frame pointer -- describes the
				   most recent TRY-frame that will catch
				   exceptions */
    cexception_t *ex;     /* exception to be raised into C-caller when
			     no bytecode handler (in xp) is available */
    char **argv;
    int argc;
    char **env;
} istate_t;

extern istate_t istate;

extern int trace;

void interpret( THRCODE *code, int argc, char *argv[], char *env[],
		cexception_t *ex );

void run( THRCODE *code, cexception_t *ex );

double *interpret_alloc_double( istate_t *is );
ldouble *interpret_alloc_ldouble( istate_t *is );

void thrcode_trace_on( void );
void thrcode_trace_off( void );
int thrcode_trace_is_on( void );

void thrcode_gc_debug_on( void );
void thrcode_gc_debug_off( void );
int thrcode_gc_debug_is_on( void );

void interpreter_print_eval_stack();

int interpret_exception_size();

void interpret_raise_exception_with_bcalloc_message( int error_code,
						     char *message,
						     char *module_id,
						     int exception_id,
						     cexception_t *ex );

void interpret_raise_exception_with_static_message( int error_code,
						    char *message,
						    char *module_id,
						    int exception_id,
						    cexception_t *ex );

void interpret_raise_exception( int error_code,
				char *message,
				char *module_id,
				int exception_id,
				cexception_t *ex );

void thrcode_gc_mark_and_sweep( void );

#endif
