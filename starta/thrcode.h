/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

#ifndef __THRCODE_H
#define __THRCODE_H

#include <stdlib.h>
#include <stdarg.h>
#include <thrcode_t.h>
#include <fixup.h>
#include <cexceptions.h>

typedef struct THRCODE THRCODE;

typedef enum { 
  THRCODE_OK = 0,
  THRCODE_WRONG_ALIGNMENT,
  THRCODE_UNRECOGNISED_OPCODE,
  THRCODE_WRONG_FORMAT,

  last_THRCODE_ERROR
} THRCODE_ERROR;

extern int thrcode_debug;
extern int thrcode_trace;
extern void *thrcode_subsystem;

void thrcode_debug_on( void );
void thrcode_debug_off( void );
int thrcode_debug_is_on( void );

void thrcode_stackdebug_on( void );
int thrcode_stackdebug_is_on( void );
void thrcode_stackdebug_off( void );

void thrcode_heapdebug_on( void );
int thrcode_heapdebug_is_on( void );
void thrcode_heapdebug_off( void );

THRCODE *new_thrcode( cexception_t *ex );

void delete_thrcode( THRCODE *bc );

void create_thrcode( THRCODE * volatile *thrcode, cexception_t *ex );

void dispose_thrcode( THRCODE * volatile *thrcode );

void *thrcode_alloc_extra_data( THRCODE *tc, ssize_t size );

void *thrcode_instructions( THRCODE *bc );

size_t thrcode_length( THRCODE *bc );

size_t thrcode_capacity( THRCODE *bc );

void thrcode_set_immediate_printout( THRCODE *tc,
				     int immediate_printout );

void thrcode_insert_static_data( THRCODE *tc, char *data, ssize_t data_size );

char* thrcode_static_data( THRCODE *tc, ssize_t *data_size );

void thrcode_printf( THRCODE *tc, cexception_t *ex, const char *format, ... );

void thrcode_printf_va( THRCODE *tc, cexception_t *ex, const char *format,
			va_list ap );

void thrcode_flush_lines( THRCODE *tc );

void thrcode_emit( THRCODE *tc, cexception_t *ex, const char *format, ... );

void thrcode_emit_va( THRCODE *tc, cexception_t *ex, const char *format, 
		      va_list ap );

void thrcode_append( THRCODE *code, THRCODE *source, cexception_t *ex );

void thrcode_patch( THRCODE *code, ssize_t address, ssize_t value );

void thrcode_push_forward_function( THRCODE *thrcode,
				    const char *name,
				    ssize_t address,
				    cexception_t *ex );

void thrcode_fixup_function_calls( THRCODE *thrcode,
				   const char *function_name,
				   int address );

void thrcode_fixup_op_continue( THRCODE *thrcode,
				const char *loop_label,
				int address );

void thrcode_fixup_op_break( THRCODE *thrcode,
			     const char *loop_label,
			     int address );

FIXUP *thrcode_forward_functions( THRCODE *thrcode );

void thrcode_push_relative_fixup_here( THRCODE *thrcode,
				       const char *name,
				       cexception_t *ex );

void thrcode_push_absolute_fixup_here( THRCODE *thrcode,
				       const char *name,
				       cexception_t *ex );

void thrcode_push_op_continue_fixup( THRCODE *thrcode, const char *name,
				     cexception_t *ex );

void thrcode_push_op_break_fixup( THRCODE *thrcode, const char *name,
				  cexception_t *ex );

void thrcode_internal_fixup( THRCODE *code, int value );

void thrcode_internal_fixup_here( THRCODE *code );

void thrcode_internal_fixup_swap( THRCODE *code );

void thrcode_fixup( THRCODE *code, FIXUP *fixup, ssize_t value );

void thrcode_fixup_offsetted( THRCODE *code, FIXUP *fixup,
			      ssize_t start, ssize_t value );

void thrcode_fixup_here( THRCODE *code, FIXUP *fixup );

THRCODE *thrcode_merge( THRCODE *dst, THRCODE *src, cexception_t *ex );

void thrcode_dump( THRCODE *code );

thrcode_t *obtain_thrcode( THRCODE *thrcode, ssize_t *length );

thrcode_t thrcode_last_opcode( THRCODE *thrcode );

#endif
