/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

/* representation of the thrcode for the interpreter, assembler and
   code generator */

/* exports: */
#include <thrcode.h>

/* uses: */
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <run.h>
#include <tcodes.h>
#include <stackcell.h>
#include <fixup.h>
#include <allocx.h>
#include <assert.h>
#include <cxprintf.h>
#include <stringx.h>
#include <implementation.h>

void *thrcode_subsystem = &thrcode_subsystem;

int thrcode_debug = 0;
static int thrcode_stackdebug = 0;
static int thrcode_heapdebug = 0;

void thrcode_debug_on( void )
{
    thrcode_debug = 1;
}

int thrcode_debug_is_on( void )
{
    return thrcode_debug;
}

void thrcode_debug_off( void )
{
    thrcode_debug = 0;
}

void thrcode_stackdebug_on( void )
{
    thrcode_stackdebug = 1;
}

int thrcode_stackdebug_is_on( void )
{
    return thrcode_stackdebug;
}

void thrcode_stackdebug_off( void )
{
    thrcode_stackdebug = 0;
}

void thrcode_heapdebug_on( void )
{
    thrcode_heapdebug = 1;
}

int thrcode_heapdebug_is_on( void )
{
    return thrcode_heapdebug;
}

void thrcode_heapdebug_off( void )
{
    thrcode_heapdebug = 0;
}

typedef struct RUNTIME_DATA_NODE {
    struct RUNTIME_DATA_NODE *next;
    union {
        double d;
        ldouble ld;
    } value;
} RUNTIME_DATA_NODE;

static RUNTIME_DATA_NODE*
alloc_runtime_data_node( ssize_t size, cexception_t *ex )
{
    RUNTIME_DATA_NODE *rdnode;

    return callocx( 1, sizeof(*rdnode) + size - sizeof(rdnode->value), ex );
}

void delete_runtime_data_nodes( RUNTIME_DATA_NODE *nodes )
{
    RUNTIME_DATA_NODE *next;

    while( nodes ) {
        next = nodes->next;
        freex( nodes );
        nodes = next;
    }
}

typedef enum {
    THRF_NONE = 0,
    THRF_IMMEDIATE_PRINTOUT = 0x01
} thrcode_flag_t;

struct THRCODE {
    thrcode_flag_t flags;    /* bit-set flags, see thrcode_flag_t for values */
    size_t length;           /* number of vector 'opcodes' elemets used
			        for storing thrcode (i.e. actual length of
			        the thrcode) */
    size_t capacity;         /* actual number of elements allocated
			        on the vector 'opcodes'. At any given moment,
			        the following must hold:
			        thrcode->length <= thrcode->capacity */
    size_t rcount;           /* reference count */
    FIXUP *fixups;           /* locations containing forward
				references that need to be fixed up in
				this code. */
    FIXUP *forward_function_calls;
                             /* functions that were called but not
				defined must be accurately reported,
				therefore fixup list for such
				functions is kept separately. */
    FIXUP *op_continue_fixups; /* fixups of the 'continue' operators */
    FIXUP *op_break_fixups;    /* fixups of the 'break' operators */

    char **lines;            /* human-readable emitted code lines that
			        should be printed out in debug output
			        mode. Last pointer must be NULL; */
    thrcode_t *opcodes;
    thrcode_t last_opcode;   /* last assembled opcode */
    char *data;              /* static data used by some commands */
    ssize_t data_size;
    RUNTIME_DATA_NODE *extra_data;     
    /* Extra data, allocated during run time and not garbage collected
       -- for instance, binary representations allocated for the
       optimized DLDC (double load constant) commands. These data
       should live as long as the code is necessary (since there may
       be pointers in the code to those nodes) and can be free'd when
       the interpreter finishes. */
};

THRCODE *new_thrcode( cexception_t *ex )
{
    THRCODE *tc = callocx( 1, sizeof(THRCODE), ex );
    tc->rcount = 1;
    return tc;
}

THRCODE *share_thrcode( THRCODE *bc )
{
    if( bc )
        bc->rcount ++;
    return bc;
}

void delete_thrcode( THRCODE *bc )
{
    if( bc ) {
#ifdef ALLOCX_DEBUG_COUNTS
        checkptr( bc );
#endif
        if( bc->rcount <= 0 ) {
	    printf( "!!! thrcode->rcount = %ld (%p)!!!\n", bc->rcount, bc );
	    assert( bc->rcount > 0 );
	}
        if( --bc->rcount > 0 )
	    return;
	delete_fixup_list( bc->fixups );
	delete_fixup_list( bc->forward_function_calls );
	delete_fixup_list( bc->op_continue_fixups );
	delete_fixup_list( bc->op_break_fixups );
        delete_runtime_data_nodes( bc->extra_data );
	if( bc->lines ) {
	    int i;
	    for( i = 0; bc->lines[i] != NULL; i++ ) {
		freex( bc->lines[i] );
	    }
	    freex( bc->lines );
	}
        if( bc->opcodes ) freex( bc->opcodes );
	if( bc->data ) freex( bc->data );
	freex( bc );
    }
}

void create_thrcode( THRCODE * volatile *thrcode, cexception_t *ex )
{
    assert( thrcode );
    assert( !(*thrcode) );

    *thrcode = new_thrcode( ex );
}

void dispose_thrcode( THRCODE * volatile *thrcode )
{
    assert( thrcode );
    if( *thrcode ) {
	delete_thrcode( *thrcode );
	*thrcode = NULL;
    }
}

void *thrcode_alloc_extra_data( THRCODE *tc, ssize_t size )
{
    RUNTIME_DATA_NODE *current = tc->extra_data;
    cexception_t inner;
    void *volatile data = NULL;

    cexception_guard( inner ) {
        data = alloc_runtime_data_node( size, &inner );
    }
    tc->extra_data = data;

    if( tc->extra_data ) {
        tc->extra_data->next = current;
        return &(tc->extra_data->value);
    } else {
        tc->extra_data = current;
        return NULL;
    }
}

void *thrcode_instructions( THRCODE *bc )
{
    assert( bc );
    return bc->opcodes;
}

size_t thrcode_length( THRCODE *bc )
{
    assert( bc );
    return bc->length;
}

size_t thrcode_capacity( THRCODE *bc )
{
    assert( bc );
    return bc->capacity;
}

void thrcode_set_immediate_printout( THRCODE *tc,
				     int immediate_printout )
{
    assert( tc );
    
    if( immediate_printout ) {
	tc->flags |= THRF_IMMEDIATE_PRINTOUT;
    } else {
	tc->flags &= ~((int)THRF_IMMEDIATE_PRINTOUT);
    }
}

void thrcode_insert_static_data( THRCODE *tc, char *data, ssize_t data_size )
{
    assert( tc );
    tc->data = data;
    tc->data_size = data_size;
}

char* thrcode_static_data( THRCODE *tc, ssize_t *data_size )
{
    assert( tc );
    assert( data_size );
    *data_size = tc->data_size;
    return tc->data;
}

static ssize_t thrcode_line_count( THRCODE *tc )
{
    ssize_t len = 0;

    assert( tc );
    if( tc->lines )
      while( tc->lines[len] )
	len ++;

    return len;
}

static THRCODE *thrcode_insert_string( THRCODE *tc, char * volatile *str,
				       cexception_t *ex )
{
    ssize_t len = thrcode_line_count( tc );;

    assert( tc );
    assert( str );

    tc->lines = reallocx( tc->lines, sizeof(tc->lines[0]) * (len + 2), ex );
    tc->lines[len+1] = NULL;
    tc->lines[len] = *str;
    *str = NULL;

    return tc;
}

void thrcode_printf( THRCODE *tc, cexception_t *ex, const char *format, ... )
{
    cexception_t inner;
    va_list ap;

    va_start( ap, format );
    assert( format );
    assert( tc );
    cexception_guard( inner ) {
	thrcode_printf_va( tc, &inner, format, ap );
    }
    cexception_catch {
	va_end( ap );	
	cexception_reraise( inner, ex );
    }
    va_end( ap );
}
    
void thrcode_printf_va( THRCODE *tc, cexception_t *ex, const char *format,
                        va_list ap )
{
    cexception_t inner;
    va_list ap2;

    if( tc->flags & THRF_IMMEDIATE_PRINTOUT ) {
	vprintf( format, ap );
    } else {
	cexception_t innermost;
	char * volatile str = NULL;
	char buff[80];
	ssize_t len = sizeof( buff );
	ssize_t chars;
        va_copy( ap2, ap );
	chars = vsnprintf( buff, len, format, ap );
        cexception_guard( inner ) {
            if( chars > 0 ) {
                if( chars < len ) {
                    str = strdupx( buff, &inner );
                } else {
                    str = mallocx( chars + 1, &inner );
                    vsnprintf( str, chars + 1, format, ap2 );
                }
                cexception_guard( innermost ) {
                    thrcode_insert_string( tc, &str, &inner );
                }
                cexception_catch {
                    freex( str );
                    cexception_reraise( innermost, &inner );
                }
            }
        }
        cexception_catch {
            va_end( ap2 );
            cexception_reraise( inner, ex );
        }
        va_end( ap2 );
    }
}

void thrcode_flush_lines( THRCODE *tc )
{
    ssize_t i = 0;

    assert( tc );

    if( tc->lines ) {
	for( i = 0; tc->lines[i] != NULL; i ++ ) {
	    printf( "%s", tc->lines[i] );
	    freex( tc->lines[i] );
	    tc->lines[i] = NULL;
	}
	freex( tc->lines );
	tc->lines = NULL;
    }
}

#define ALLOC_CHUNK 8

static void thrcode_alloc( THRCODE *bc, size_t delta, cexception_t *ex )
{
    size_t new_capacity;

    assert( delta >= 0 );
    assert( bc->length <= bc->capacity );

    if( bc->length + delta <= bc->capacity )
        return;

    new_capacity = bc->capacity + (ALLOC_CHUNK > delta ? ALLOC_CHUNK : delta);
    bc->opcodes =
        reallocx( bc->opcodes, new_capacity * sizeof(bc->opcodes[0]), ex );
    bc->capacity = new_capacity;
}

static void thrcode_emit_tcode( THRCODE *tc, void *tcode,
			        cexception_t *ex )
{
    thrcode_alloc( tc, 1, ex );
    tc->opcodes[tc->length++].fn = tcode;
}

#if 0
static void thrcode_emit_int( THRCODE *tc, int ival,
			      cexception_t *ex )
{
    thrcode_alloc( tc, 1, ex );
    tc->opcodes[tc->length++].ival = ival;
}
#endif

static void thrcode_emit_ssize_t( THRCODE *tc, ssize_t sszval,
				  cexception_t *ex )
{
    thrcode_alloc( tc, 1, ex );
    tc->opcodes[tc->length++].ssizeval = sszval;
}

static void thrcode_emit_ptr( THRCODE *tc, void *pval,
			      cexception_t *ex )
{
    thrcode_alloc( tc, 1, ex );
    tc->opcodes[tc->length++].ptr = pval;
}

static void thrcode_emit_float( THRCODE *tc, float fval,
			        cexception_t *ex )
{
    thrcode_alloc( tc, 1, ex );
    tc->opcodes[tc->length++].fval = fval;
}

/*
  Format specifiers for thrcode_emit():
  '\n' print new line if bytecode printout requested; assembles nothing
  c assembles tcode (pointer to a function)
  C assembles tcode (from char* to an opcode (function) name)
  i assembles integer
  I assembles ssize_t from an integer value; must get an integer value.
  e assembles ssize_t, must get an address of the ssize_t variable.
  s assembles element size of ssize_t, must get an address of the ssize_t variable.
    May be ignored by those implementations that do not need it (e.g. which 
    have all element slots of the same size).
  f assembles float
  p assembles pointer
  S assembles string
  T does not emit enything, but prints the argument string (char*)
    if the debug mode is on. Usefull for introducing comments
    into the output of the emitter.
  M assembles the next opcode as belonging to package given by (char*)
  N shows variable name when in debug mode
 */

void thrcode_emit( THRCODE *tc, cexception_t *ex, const char *format, ... )
{
    cexception_t inner;
    va_list ap;

    assert( format );

    va_start( ap, format );
    cexception_guard( inner ) {
	thrcode_emit_va( tc, &inner, format, ap );
    }
    cexception_catch {
	va_end(ap);
	cexception_reraise( inner, ex );
    }
    va_end(ap);
}

void thrcode_emit_va( THRCODE *tc, cexception_t *ex, const char *format, 
		      va_list ap )
{
    void *tcode;
    int ival;
    ssize_t sszval;
    float fval;
    char *sval;
    void *pval;
    char *lib_name;

    tc->last_opcode.fn = NULL;
    while( *format ) {
        switch( *format ) {
	    case 'c':
	        tcode = va_arg( ap, void* );
		tc->last_opcode.fn = tcode;
		thrcode_emit_tcode( tc, tcode, ex );
		if( thrcode_debug )
		    thrcode_printf( tc, ex, "%-4s ", tcode ?
			    tcode_lookup_name( tcode ) : "STOP" );
		break;
	    case 'C':
	        sval = va_arg( ap, char* );
	        tcode = tcode_lookup( sval );
		tc->last_opcode.fn = tcode;
		if( tcode != NULL ) {
		    thrcode_emit_tcode( tc, tcode, ex );
		    if( thrcode_debug )
			thrcode_printf( tc, ex, "%-4s ",
					tcode_lookup_name( tcode ));
		} else {
		    cexception_raise_in( ex, thrcode_subsystem,
					 THRCODE_UNRECOGNISED_OPCODE,
					 cxprintf( "bytecode operation '%s' "
						   "is not defined", sval ));
		}
		break;
	    case 'M':
		lib_name = va_arg( ap, char* );
		if( format[1] != 'C' ) {
		    cexception_raise_in( ex, thrcode_subsystem,
					 THRCODE_WRONG_FORMAT,
					 cxprintf( "format 'M' must be "
						   "followed by 'C', but "
						   "it was followed by '%c'",
						   format[-1] ));
		} else {
		    sval = va_arg( ap, char* );
		    tcode = tcode_lookup_library_opcode( lib_name, sval );
		    if( tcode != NULL ) {
			thrcode_emit_tcode( tc, tcode, ex );
			if( thrcode_debug )
			    thrcode_printf( tc, ex, "%-4s ",
					    tcode_lookup_name( tcode ));
		    } else {
			cexception_raise_in( ex, thrcode_subsystem,
					     THRCODE_UNRECOGNISED_OPCODE,
					     cxprintf( "bytecode operation '%s' "
						       "is not defined", sval ));
		    }
		}
                format++;
		break;
#if 0
	    case 'i':
	        ival = va_arg( ap, int );
		thrcode_emit_int( tc, ival, ex );
		if( thrcode_debug )
		    thrcode_printf( tc, ex, "%d ", ival );
		break;
#endif
	    case 'I':
	        ival = va_arg( ap, int );
		thrcode_emit_ssize_t( tc, (ssize_t)ival, ex );
		if( thrcode_debug )
		    thrcode_printf( tc, ex, "%d ", ival );
		break;
            case 's': /* element size */
	    case 'e':
                sszval = *va_arg( ap, ssize_t* );
                if( *format == 'e' || implementation_has_format( *format )) {
                    thrcode_emit_ssize_t( tc, sszval, ex );
                    if( thrcode_debug )
                        thrcode_printf( tc, ex, "%Ld ", (llong)sszval );
                }
                break;
	    case 'p':
	        pval = va_arg( ap, void* );
		thrcode_emit_ptr( tc, pval, ex );
		if( thrcode_debug )
		    thrcode_printf( tc, ex, "%p ", pval );
		break;
	    case 'f':
	        fval = va_arg( ap, double );
		thrcode_emit_float( tc, fval, ex );
		if( thrcode_debug )
		    thrcode_printf( tc, ex, "%f ", fval );
		break;
	    case 'N':
	        sval = va_arg( ap, char* );
		if( thrcode_debug )
		    thrcode_printf( tc, ex, "(* %s *) ", sval );
		break;
#if 0
	    case 'S':
	        sval = va_arg( ap, char* );
		thrcode_emit_chars( bc, sval, ex );
		if( thrcode_debug )
		    thrcode_printf( tc, ex, "\"%s\" ", sval );
		break;
#endif
	    case 'T':
	        sval = va_arg( ap, char* );
		if( thrcode_debug )
		    thrcode_printf( tc, ex, "%s", sval );
		break;
	    case ':':
	        sval = va_arg( ap, char* );
		if( thrcode_debug && sval && *sval )
		    thrcode_printf( tc, ex, "%s:", sval );
		break;
	    case '\n':
	        if( thrcode_debug )
		    thrcode_printf( tc, ex, "\n" );
		break;
	    case '\t':
	        if( thrcode_debug )
		    thrcode_printf( tc, ex, "        " );
		break;
	    case ' ':
	        if( thrcode_debug ) {
		    thrcode_printf( tc, ex, " " );
		    while( *format == ' ' ) {
			thrcode_printf( tc, ex, " " );
			format++;
		    }
		}
		break;
	    default:
	        assert( 0 );
		break;
	}
        format++;
    }
}

void thrcode_append( THRCODE *code, THRCODE *source, cexception_t *ex )
{
    ssize_t src_len;

    if( !source ) return;
    src_len = thrcode_length( source );

    if( src_len > 0 ) {
	thrcode_alloc( code, src_len, ex );
	memcpy( &code->opcodes[code->length], source->opcodes,
	         sizeof(code->opcodes[0]) * src_len );
	code->length += src_len;
    }
}

void thrcode_patch( THRCODE *code, ssize_t address, ssize_t value )
{
    assert( code );
    assert( address >= 0 );
    assert( address < code->length );

    code->opcodes[address].ssizeval = value;
}

void thrcode_push_forward_function( THRCODE *thrcode,
				    const char *name,
				    ssize_t address,
				    cexception_t *ex )
{
    thrcode->forward_function_calls =
	new_fixup_absolute( name, address,
			    thrcode->forward_function_calls, ex );
}

void thrcode_fixup_function_calls( THRCODE *thrcode,
				   const char *function_name,
				   int address )
{
    FIXUP *fixup, *next , *unused = NULL;

    for( fixup = thrcode->forward_function_calls; fixup != NULL; ) {
        next = fixup_next( fixup );

        if( strcmp( function_name, fixup_name( fixup )) == 0 ) {
	    thrcode_fixup( thrcode, fixup, address );
	    delete_fixup( fixup );
	} else {
	    unused = fixup_append( fixup, unused );
	}
	fixup = next;
    }
    thrcode->forward_function_calls = unused;
}

void thrcode_fixup_op_continue( THRCODE *thrcode,
				const char *loop_label,
				int address )
{
    FIXUP *fixup, *next , *unused = NULL;

    for( fixup = thrcode->op_continue_fixups; fixup != NULL; ) {
        next = fixup_next( fixup );

        if( strcmp( loop_label, fixup_name( fixup )) == 0 ) {
	    thrcode_fixup( thrcode, fixup, address );
	    delete_fixup( fixup );
	} else {
	    unused = fixup_append( fixup, unused );
	}
	fixup = next;
    }
    thrcode->op_continue_fixups = unused;
}

void thrcode_fixup_op_break( THRCODE *thrcode,
			     const char *loop_label,
			     int address )
{
    FIXUP *fixup, *next , *unused = NULL;

    for( fixup = thrcode->op_break_fixups; fixup != NULL; ) {
        next = fixup_next( fixup );

        if( strcmp( loop_label, fixup_name( fixup )) == 0 ) {
	    thrcode_fixup( thrcode, fixup, address );
	    delete_fixup( fixup );
	} else {
	    unused = fixup_append( fixup, unused );
	}
	fixup = next;
    }
    thrcode->op_break_fixups = unused;
}

FIXUP *thrcode_forward_functions( THRCODE *thrcode )
{
    assert( thrcode );
    return thrcode->forward_function_calls;
}

void thrcode_push_relative_fixup_here( THRCODE *thrcode,
				       const char *name,
				       cexception_t *ex )
{
    thrcode->fixups = 
	new_fixup_relative( name, thrcode_length(thrcode) + 1,
			    thrcode->fixups, ex );
}

void thrcode_push_absolute_fixup_here( THRCODE *thrcode,
				       const char *name,
				       cexception_t *ex )
{
    thrcode->fixups = 
	new_fixup_absolute( name, thrcode_length(thrcode) + 1,
			    thrcode->fixups, ex );
}

void thrcode_push_op_continue_fixup( THRCODE *thrcode,
				     const char *name,
				     cexception_t *ex )
{
    thrcode->op_continue_fixups =
	new_fixup_relative( name, thrcode_length(thrcode) + 1,
			    thrcode->op_continue_fixups, ex );
}

void thrcode_push_op_break_fixup( THRCODE *thrcode,
				  const char *name,
				  cexception_t *ex )
{
    thrcode->op_break_fixups =
	new_fixup_relative( name, thrcode_length(thrcode) + 1,
			    thrcode->op_break_fixups, ex );
}

void thrcode_internal_fixup( THRCODE *thrcode, int value )
{
    int address;

    address = fixup_address( thrcode->fixups );
    if( fixup_is_absolute( thrcode->fixups )) {
	thrcode_patch( thrcode, address, value );
    } else {
	thrcode_patch( thrcode, address, value - address + 1 );
    }
    thrcode->fixups = pop_fixup( thrcode->fixups );
}

void thrcode_internal_fixup_here( THRCODE *code )
{
    thrcode_internal_fixup( code, thrcode_length( code ));
}

void thrcode_internal_fixup_swap( THRCODE *code )
{
    code->fixups = fixup_swap( code->fixups );
}

void thrcode_fixup( THRCODE *code, FIXUP *fixup, ssize_t value )
{
    int address;

    address = fixup_address( fixup );
    if( fixup_is_absolute( fixup )) {
	thrcode_patch( code, address, value );
    } else {
	thrcode_patch( code, address, value - address + 1 );
    }
}

void thrcode_fixup_offsetted( THRCODE *code, FIXUP *fixup,
			      ssize_t start, ssize_t value )
{
    int address;

    address = fixup_address( fixup );
    if( fixup_is_absolute( fixup )) {
	thrcode_patch( code, start + address, value );
    } else {
	thrcode_patch( code, start + address, value - address + 1 );
    }
}

void thrcode_fixup_here( THRCODE *code, FIXUP *fixup )
{
    thrcode_fixup( code, fixup, thrcode_length( code ));
}

static void thrcode_merge_line_lists( THRCODE *code1, THRCODE *code2,
				      cexception_t *ex )
{
    ssize_t i;
    ssize_t len1 = thrcode_line_count( code1 );
    ssize_t len2 = thrcode_line_count( code2 );
    ssize_t len = len1 + len2;

    if( code1->flags & THRF_IMMEDIATE_PRINTOUT ) {
	thrcode_flush_lines( code2 );
    } else {
	code1->lines = reallocx( code1->lines,
				 sizeof(code1->lines[0]) * (len + 1), ex );

	memmove( code1->lines + len1, code2->lines,
		 sizeof(code1->lines[0]) * len2 );

	code1->lines[len] = NULL;
    
	for( i = 0; i < len2; i ++ ) {
	    code2->lines[i] = NULL;
	}
    }
}

static FIXUP *_merge_fixup_lists( FIXUP *dst_list, FIXUP *src_list,
				  ssize_t dst_end, cexception_t *ex )
{
    FIXUP *src_fixup;

    foreach_fixup( src_fixup, src_list ) {
	int is_abs = fixup_is_absolute( src_fixup );
	ssize_t addr = fixup_address( src_fixup );
	const char *name = fixup_name( src_fixup );
	dst_list = new_fixup( name, addr + dst_end, is_abs, dst_list, ex );
    }

    return dst_list;
}

THRCODE *thrcode_merge( THRCODE *dst, THRCODE *src, cexception_t *ex )
{
    ssize_t src_len, dst_len;
    thrcode_t *src_code, *dst_code;

    src_len = thrcode_length( src );
    dst_len = thrcode_length( dst );

    thrcode_alloc( dst, src_len, ex );

    src_code = thrcode_instructions( src );
    dst_code = thrcode_instructions( dst );

    memcpy( dst_code + dst_len, src_code, src_len * sizeof( src_code[0] ));

    dst->length += src_len;

    dst->fixups =
	_merge_fixup_lists( dst->fixups, src->fixups, dst_len, ex );

    dst->forward_function_calls =
	_merge_fixup_lists( dst->forward_function_calls,
			    src->forward_function_calls, dst_len, ex );

    dst->op_continue_fixups =
	_merge_fixup_lists( dst->op_continue_fixups,
			    src->op_continue_fixups, dst_len, ex );

    dst->op_break_fixups =
	_merge_fixup_lists( dst->op_break_fixups,
			    src->op_break_fixups, dst_len, ex );

    thrcode_merge_line_lists( dst, src, ex );
    
    return dst;
}

void thrcode_dump( THRCODE *code )
{
    int i;

    for( i = 0; i < code->length; i++ ) {
	thrcode_t *opcode = &code->opcodes[i];
	char *name = tcode_lookup_name( opcode->fn );

	printf( "%08d ", i );
	printf( "%-10s ", name ? name : "" );
	printf( "%10Ld ", (llong)opcode->ssizeval );
	printf( "%12.7f ", opcode->fval );
	printf( "%10p\n", opcode->ptr );
    }
}

thrcode_t *obtain_thrcode( THRCODE *thrcode, ssize_t *length )
{
    thrcode_t *opcodes;

    assert( thrcode );

    if( length ) {
	*length = thrcode->length;
    }

    opcodes = thrcode->opcodes;

    thrcode->opcodes = NULL;
    thrcode->length = 0;
    thrcode->capacity = 0;

    return opcodes;
}

thrcode_t thrcode_last_opcode( THRCODE *thrcode )
{
    assert( thrcode );
    return thrcode->last_opcode;
}
