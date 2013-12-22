/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

/* special uses: */
#define _ISOC99_SOURCE 1
#include <stdlib.h> /* with _ISOC99_SOURCE true, provides strtof() and
                       strtold() */

/* exports: */
#include <tcodes.h>

/* uses: */
#include <stdio.h>
#include <errno.h>
#define __USE_GNU
#include <string.h>
#include <ctype.h> /* for isspace() and isdigit() */
#include <math.h>
#include <dlfcn.h>
#include <run.h>
#include <hashcell.h>
#include <bcalloc.h>
#include <bytecode_file.h>
#include <rtti.h>
#include <allocx.h>
#include <stringx.h>
#include <cxprintf.h>
#include <assert.h>

typedef struct {
    void *function;
    char *name;
} tcode_name_t;

tcode_name_t tcode_names[] = {

#include "generated/byte_integer.tab.c"
#include "generated/short_integer.tab.c"
#include "generated/int_integer.tab.c"
#include "generated/long_integer.tab.c"
#include "generated/llong_integer.tab.c"

#include "generated/float_float.tab.c"
#include "generated/double_float.tab.c"
#include "generated/ldouble_float.tab.c"

#include "generated/byte_intfloat.tab.c"
#include "generated/short_intfloat.tab.c"
#include "generated/int_intfloat.tab.c"
#include "generated/long_intfloat.tab.c"
#include "generated/llong_intfloat.tab.c"
#include "generated/float_intfloat.tab.c"
#include "generated/double_intfloat.tab.c"
#include "generated/ldouble_intfloat.tab.c"

#include "generated/tcodes.tab.c"
  { NULL, NULL }
};

typedef struct {
    tcode_name_t *opcodes;
    char *table_name;
    void *library;
} tcode_table_t;

static tcode_table_t *extra_tcode_tables;

static ssize_t tcode_table_array_length( tcode_table_t *tables )
{
    ssize_t length = 0;

    if( tables ) {
	while( tables->table_name ) {
	    length ++;
	    tables ++;
	}
    }
    return length;
}

static ssize_t tcode_name_array_length( char **names )
{
    ssize_t length = 0;

    if( names ) {
	while( *names ) {
	    length ++;
	    names ++;
	}
    }
    return length;
}

void tcode_add_table( char *table_name, void *library,
		      char **names, cexception_t *ex )
{
    size_t table_length, names_length, i;
    tcode_name_t *opcodes;

    if( !extra_tcode_tables ) {
	table_length = 0;
    } else {
	table_length = tcode_table_array_length( extra_tcode_tables );
    }


    extra_tcode_tables = reallocx( extra_tcode_tables,
                                   sizeof(*extra_tcode_tables) *
                                   (table_length + 2), ex );
	
    extra_tcode_tables[table_length+1].table_name = NULL;
    extra_tcode_tables[table_length+1].opcodes = NULL;
    extra_tcode_tables[table_length+1].library = NULL;

    extra_tcode_tables[table_length].table_name = strdupx( table_name, ex );
    extra_tcode_tables[table_length].library = library;

    if( !names ) {
	names_length = 0;
    } else {
	names_length = tcode_name_array_length( names );
    }

    opcodes =
	callocx( sizeof(extra_tcode_tables[0].opcodes[0]),
		 names_length + 1, ex );

    extra_tcode_tables[table_length].opcodes = opcodes;

    for( i = 0; i <= names_length; i++ ) {
	opcodes[i].name = names[i];
	opcodes[i].function = NULL;
    }
}

void *tcode_lookup( char *name )
{
    int i;

    for( i = 0; tcode_names[i].name != NULL; i++ ) {
        if( strcmp( name, tcode_names[i].name ) == 0 ) {
	    return tcode_names[i].function;
	}
    }
    return NULL;
}

void *tcode_lookup_library_opcode( char *lib_name, char *name )
{
    int i, j;

    if( !extra_tcode_tables ) return NULL;

    for( i = 0; extra_tcode_tables[i].table_name != NULL; i++ ) {
        if( strcmp( lib_name, extra_tcode_tables[i].table_name ) == 0 ) {
	    tcode_name_t *opcodes = extra_tcode_tables[i].opcodes;
	    for( j = 0; opcodes[j].name != NULL; j++ ) {
		if( strcmp( name, opcodes[j].name ) == 0 ) {
		    if( !opcodes[j].function ) {
			opcodes[j].function =
			    dlsym( extra_tcode_tables[i].library,
				   opcodes[j].name );
		    }
		    return opcodes[j].function;
		}
	    }
	}
    }
    return NULL;
}

char *tcode_lookup_name( void *funct )
{
    int i;
    for( i = 0; tcode_names[i].name != NULL; i++ ) {
        if( funct == tcode_names[i].function ) {
	    return tcode_names[i].name;
	}
    }
    return NULL;
}

#define BC_CHECK_PTR( ptr ) \
    if( !(ptr) ) { \
        bc_merror( EXCEPTION ); \
        return 0; \
    }

#ifndef TRACE
#define TRACE
#endif

#if 0
#define EXCEPTION (NULL)
#else
#define EXCEPTION (istate.ex)
#endif

#ifdef TRACE_FUNCTION
#undef TRACE_FUNCTION
#endif

#ifdef TRACE
#define TRACE_FUNCTION() \
    if( trace ) printf( "%s\t" \
                        "%4ld(%9p) %4ld(%9p) " \
                        "%4ld(%9p) %4ld(%9p) " \
                        "%4ld(%9p) %4ld(%9p) ...\n", \
                        __FUNCTION__, \
                        (long)istate.ep[0].num.i, istate.ep[0].PTR, \
                        (long)istate.ep[1].num.i, istate.ep[1].PTR, \
                        (long)istate.ep[2].num.i, istate.ep[2].PTR, \
                        (long)istate.ep[3].num.i, istate.ep[3].PTR, \
                        (long)istate.ep[4].num.i, istate.ep[4].PTR, \
                        (long)istate.ep[5].num.i, istate.ep[5].PTR )
#else
#define TRACE_FUNCTION()
#endif

#include "generated/byte_integer.c"
#include "generated/short_integer.c"
#include "generated/int_integer.c"
#include "generated/long_integer.c"
#include "generated/llong_integer.c"

#include "generated/float_float.c"
#include "generated/double_float.c"
#include "generated/ldouble_float.c"

#include "generated/byte_intfloat.c"
#include "generated/short_intfloat.c"
#include "generated/int_intfloat.c"
#include "generated/long_intfloat.c"
#include "generated/llong_intfloat.c"
#include "generated/float_intfloat.c"
#include "generated/double_intfloat.c"
#include "generated/ldouble_intfloat.c"

#ifdef I
#undef I
#endif

/*
** Generic opcodes (opcodes that do not depend on particular stackcell
** field):
*/

int NOP( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();
    return 1;
}

int DUP( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    istate.ep --;
    istate.ep[0] = istate.ep[1];

    return 1;
}

int OVER( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    istate.ep --;
    istate.ep[0] = istate.ep[2];

    return 1;
}

int SWAP( INSTRUCTION_FN_ARGS )
{
    stackcell_t tmp;

    TRACE_FUNCTION();

    tmp = istate.ep[0];
    istate.ep[0] = istate.ep[1];
    istate.ep[1] = tmp;

    return 1;
}

int DROP( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    istate.ep ++;
    return 1;
}

int DROPN( INSTRUCTION_FN_ARGS )
{
    int ncells = istate.code[istate.ip+1].ssizeval;

    TRACE_FUNCTION();

    istate.ep += ncells;
    return 2;
}

int PDROP( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    STACKCELL_ZERO_PTR( *istate.ep );
    istate.ep ++;
    return 1;
}

int PDROPN( INSTRUCTION_FN_ARGS )
{
    int ncells = istate.code[istate.ip+1].ssizeval;

    TRACE_FUNCTION();

    memset( istate.ep, '\0', sizeof(istate.ep[0]) * ncells );
    istate.ep += ncells;
    return 2;
}

int ROT( INSTRUCTION_FN_ARGS )
{
    stackcell_t tmp;

    TRACE_FUNCTION();

    tmp = istate.ep[0];
    istate.ep[0] = istate.ep[1];
    istate.ep[1] = istate.ep[2];
    istate.ep[2] = tmp;

    return 1;
}

int COPY( INSTRUCTION_FN_ARGS )
{
    alloccell_t *ptr0 = STACKCELL_PTR( istate.ep[0] );
    alloccell_t *ptr1 = STACKCELL_PTR( istate.ep[1] );
    ssize_t size0 = ptr0 ? (ptr0[-1].element_size * ptr0[-1].length ) : 0;
    ssize_t size1 = ptr1 ? (ptr1[-1].element_size * ptr1[-1].length ) : 0;
    ssize_t size = size1 < size0 ? size1 : size0;
    ssize_t length = 0;

    if( ptr0 && ptr1 ) {
        length = ptr0[-1].length < ptr1[-1].length ?
            ptr0[-1].length : ptr1[-1].length;
    }

    TRACE_FUNCTION();

    if( ptr0 && ptr1 ) {
        ssize_t nref0 = length >= 0 && ptr0[-1].nref < length ?
            ptr0[-1].nref : length;
        ssize_t nref1 = length >= 0 && ptr1[-1].nref < length ?
            ptr1[-1].nref : length;
        assert( nref0 == nref1 );
	memcpy( ptr1, ptr0, size );
    }

    STACKCELL_ZERO_PTR( istate.ep[0] );
    STACKCELL_ZERO_PTR( istate.ep[1] );

    istate.ep += 2;

    return 1;
}

/*
 * OFFSET compute an address of the structure field
 * 
 * bytecode:
 * OFFSET field_offset
 * 
 * stack:
 * address -> field_address
 * 
 */

int OFFSET( INSTRUCTION_FN_ARGS )
{
    ssize_t field_offset = istate.code[istate.ip+1].ssizeval;

    TRACE_FUNCTION();

    STACKCELL_OFFSET_PTR( istate.ep[0], field_offset );

    return 2;
}

/*
 LD (load variable)

 bytcode:
 LD offset

 stack:
 --> value

 'offset' identifies local variable relative to 'istate.fp', and the value
 of this variable is loaded onto the stack

 */

int LD( INSTRUCTION_FN_ARGS )
{
    ssize_t offset = istate.code[istate.ip+1].ssizeval;

    TRACE_FUNCTION();

    istate.ep --;
    istate.ep[0] = istate.fp[offset];

    return 2;
}

/*
 LDG (load global variable)

 bytcode:
 LDG offset

 stack:
 --> value

 'offset' identifies a global variable relative to 'istate.gp', and
 the value of this variable is loaded onto the stack

 */

int LDG( INSTRUCTION_FN_ARGS )
{
    ssize_t offset = istate.code[istate.ip+1].ssizeval;

    TRACE_FUNCTION();

    istate.ep --;
    istate.ep[0] = istate.gp[offset];

    return 2;
}

/*
 LDA (load variable address)

 bytcode:
 LDA offset

 stack:
 --> address

 'offset' identifies local variable relative to 'istate.fp', and the ADDRESS
 of this variable is loaded onto the stack

 */

int LDA( INSTRUCTION_FN_ARGS )
{
    ssize_t offset = istate.code[istate.ip+1].ssizeval;

    TRACE_FUNCTION();

    istate.ep --;
    STACKCELL_SET_ADDR( istate.ep[0], &istate.fp[offset] );

    return 2;
}

/*
 LDGA (load global variable address)

 bytcode:
 LDGA offset

 stack:
 --> address

 'offset' identifies local variable relative to 'istate.gp', and the ADDRESS
 of this variable is loaded onto the stack

 */

int LDGA( INSTRUCTION_FN_ARGS )
{
    ssize_t offset = istate.code[istate.ip+1].ssizeval;

    TRACE_FUNCTION();

    istate.ep --;
    STACKCELL_SET_ADDR( istate.ep[0], &istate.gp[offset] );

    return 2;
}

/*
 ST (store variable)

 bytcode:
 ST offset

 stack:
 value --> 

 'offset' identifies local variable relative to 'istate.fp', and the
 value from stack is stored to this offset.

 */

int ST( INSTRUCTION_FN_ARGS )
{
    ssize_t offset = istate.code[istate.ip+1].ssizeval;

    TRACE_FUNCTION();

    istate.fp[offset] = istate.ep[0];
    STACKCELL_ZERO_PTR( istate.ep[0] ); /* must zero ptr, since the
					   stored stackcell could have
					   been reference... */
    istate.ep ++;

    return 2;
}

/*
 STG (store global variable)

 bytcode:
 STG offset

 stack:
 value --> 

 'offset' identifies local variable relative to 'istate.gp', and the
 value from stack is stored to this offset.

 */

int STG( INSTRUCTION_FN_ARGS )
{
    ssize_t offset = istate.code[istate.ip+1].ssizeval;

    TRACE_FUNCTION();

    istate.gp[offset] = istate.ep[0];
    STACKCELL_ZERO_PTR( istate.ep[0] ); /* must zero ptr, since the
					   stored stackcell could have
					   been reference... */
    istate.ep ++;

    return 2;
}

/*
 * LDI (load indirect)
 *
 * bytecode:
 * LDI size
 * 
 * address --> value
 *
 */

int LDI( INSTRUCTION_FN_ARGS )
{
    ssize_t size = istate.code[istate.ip+1].ssizeval;
    ssize_t offset = STACKCELL_OFFSET( istate.ep[0] );
    alloccell_t *src_header = (alloccell_t*)(istate.ep[0].PTR) - 1;
    ssize_t element_size = src_header->element_size;
    ssize_t length = src_header->length;

    TRACE_FUNCTION();

    if( offset >= 0 ) {
        memcpy( &istate.ep[0].num, STACKCELL_PTR(istate.ep[0]), size );
        STACKCELL_ZERO_PTR( istate.ep[0] );
    } else {
#if 0
        istate.ep[0].PTR = *(void**)STACKCELL_PTR(istate.ep[0]);
        istate.ep[0].num.offs = 0;
#else
        void** ref_src = (void**)STACKCELL_PTR(istate.ep[0]);
        if( length == -1 && element_size > -offset ) {
            /* NB.: offset < 0 */
            /* We have a field of generic type, and need to store the
               numeric stackcell at the positive offset: */
            void* num_src = (char*)istate.ep[0].PTR - offset;
            memcpy( &istate.ep[0].num, num_src, sizeof(istate.ep[0].num));
            // printf( ">>> loaded positive part as well: %d\n", *(int*)num_src );
        } else {
            istate.ep[0].num.offs = 0;
        }
        istate.ep[0].PTR = *ref_src;
#endif
    }

    return 2;
}

/*
 * STI (store indirect)
 *
 * bytecode:
 * STI size
 * 
 * ..., address, value --> 
 *
 */

int STI( INSTRUCTION_FN_ARGS )
{
    ssize_t size = istate.code[istate.ip+1].ssizeval;
    ssize_t offset = STACKCELL_OFFSET( istate.ep[1] );
    alloccell_t *dst_header = (alloccell_t*)(istate.ep[1].PTR) - 1;
    ssize_t element_size = dst_header->element_size;
    ssize_t length = dst_header->length;

    TRACE_FUNCTION();

    if( offset >= 0 ) {
        memcpy( STACKCELL_PTR(istate.ep[1]), &istate.ep[0].num, size );
    } else {
        *(void**)STACKCELL_PTR(istate.ep[1]) = istate.ep[0].PTR;
        //*((void**)STACKCELL_PTR(istate.ep[1])) = STACKCELL_PTR( istate.ep[0] );
        if( length == -1 && element_size > -offset ) {
            /* offset < 0 here */
            /* We have a field of generic type, and need to store the
               numeric stackcell at the positive offset: */
            // printf( ">>> storing positive part as well: %d\n", istate.ep[0].num.i );
            void* dst = (char*)istate.ep[1].PTR - offset;
            memcpy( dst, &istate.ep[0].num, sizeof(istate.ep[0].num));
        }
    }

    STACKCELL_ZERO_PTR( istate.ep[0] );
    STACKCELL_ZERO_PTR( istate.ep[1] );

    istate.ep += 2;

    return 2;
}

/*
 * EXIT Call libc exit() to exit the program.
 * 
 * bytecode:
 * EXIT
 * 
 * stack:
 * int_exit_code --> ...
 * 
 */

int EXIT( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    exit( istate.ep[0].num.i );

    return 1;
}

/*
 * NEWLINE (print a newline character)
 * 
 * bytecode:
 * NEWLINE
 * 
 * stack:
 * -->
 * 
 * Print an '\n' to stdout.
 */

int NEWLINE( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    printf( "\n" );

    return 1;
}

/*
 * SPACE (print a space character)
 * 
 * bytecode:
 * SPACE
 * 
 * stack:
 * -->
 * 
 * Print an ' ' (space) to stdout.
 */

int SPACE( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    printf( " " );

    return 1;
}

/*
 * ALLOC (allocate memory of given size, initialised with zeros)
 *
 * bytecode:
 * ALLOC size nref
 *
 * stack:
 * --> mem_ptr
 */

int ALLOC( INSTRUCTION_FN_ARGS )
{
    void *ptr;
    ssize_t size = istate.code[istate.ip+1].ssizeval;
    ssize_t nref = istate.code[istate.ip+2].ssizeval;

    TRACE_FUNCTION();

    ptr = bcalloc( size, nref );

    BC_CHECK_PTR( ptr );

    istate.ep --;
    STACKCELL_SET_ADDR( istate.ep[0], ptr );
    return 3;
}

/*
 * ALLOCVMT (allocate memory, initialised with zeros, set VMT)
 *
 * bytecode:
 * ALLOCVMT size nref vmt_pointer
 *
 * stack:
 * --> mem_ptr
 */

int ALLOCVMT( INSTRUCTION_FN_ARGS )
{
    void *ptr;
    alloccell_t *header;
    ssize_t **itable;
    ssize_t size = istate.code[istate.ip+1].ssizeval;
    ssize_t nref = istate.code[istate.ip+2].ssizeval;
    ssize_t vmt_offset  = istate.code[istate.ip+3].ssizeval;

    TRACE_FUNCTION();

    ptr = bcalloc( size, nref );

    BC_CHECK_PTR( ptr );

    istate.ep --;
    STACKCELL_SET_ADDR( istate.ep[0], ptr );

    header = (alloccell_t*)ptr;
    itable = &header[-1].vmt_offset;

    *itable = (ssize_t*)(istate.static_data + vmt_offset);

    return 4;
}

/*
 * MKARRAY (create array from computed expressions on the stack)
 *
 * bytecode:
 * MKARRAY size nref nelements
 *
 * stack:
 * ..., elem1, ..., elemN --> mem_ptr
 */

int MKARRAY( INSTRUCTION_FN_ARGS )
{
    void *ptr;
    ssize_t size = istate.code[istate.ip+1].ssizeval;
    ssize_t nref = istate.code[istate.ip+2].ssizeval;
    ssize_t nele = istate.code[istate.ip+3].ssizeval;
    ssize_t i;

    TRACE_FUNCTION();

    ptr = bcalloc_array( size, nele, nref );

    BC_CHECK_PTR( ptr );

    for( i = 0; i < nele; i ++ ) {
	memcpy( ((char*)ptr) + i * size, &istate.ep[nele - 1 - i], size );
    }

    istate.ep += nele - 1;
    STACKCELL_SET_ADDR( istate.ep[0], ptr );

    return 4;
}

/*
 * PMKARRAY (create array from pointers)
 *
 * bytecode:
 * PMKARRAY nelements
 *
 * stack:
 * ..., elem1, ..., elemN --> mem_ptr
 */

int PMKARRAY( INSTRUCTION_FN_ARGS )
{
    void *ptr;
    ssize_t nele = istate.code[istate.ip+1].ssizeval;
    ssize_t i;

    TRACE_FUNCTION();

    ptr = bcalloc_array( sizeof(void*), nele, 1 );

    BC_CHECK_PTR( ptr );

    for( i = 0; i < nele; i ++ ) {
	((void**)ptr)[i] = STACKCELL_PTR( istate.ep[nele - 1 - i] );
	STACKCELL_ZERO_PTR( istate.ep[nele - 1 - i] );
    }

    istate.ep += nele - 1;
    STACKCELL_SET_ADDR( istate.ep[0], ptr );

    return 2;
}

/*
 * CLONE (clone object on the top of the stack)
 *
 * bytecode:
 * CLONE
 *
 * stack:
 * object_ref --> copy_ref
 */

int CLONE( INSTRUCTION_FN_ARGS )
{
    alloccell_t *array = STACKCELL_PTR( istate.ep[0] );
    alloccell_t *ptr;
    ssize_t nref, element_size, nele;

    TRACE_FUNCTION();

    if( !array ) return 1;

    element_size = array[-1].element_size;
    nref = array[-1].nref;
    nele = array[-1].length;

    if( nele >= 0 ) {
        assert( nref == 0 || nref == nele );
        ptr = bcalloc_array( element_size, nele, nref == 0 ? 0 : 1 );
    } else {
        ptr = bcalloc( element_size, nref );
    }

    BC_CHECK_PTR( ptr );

    memcpy( ptr, array,
            nele >= 0 ? (ssize_t)element_size * (ssize_t)nele : element_size );

    if( nref < 0 ) {
        ssize_t ref_size = (ssize_t)abs(nref) * (ssize_t)REF_SIZE;
        void *ref_dst = (char*)ptr - sizeof(alloccell_t) - ref_size;
        void *ref_src = (char*)array - sizeof(alloccell_t) - ref_size;
        memcpy( ref_dst, ref_src, ref_size );
    }

    STACKCELL_SET_ADDR( istate.ep[0], ptr );

    return 1;
}

/*
 * MEMCPY (copy memory)
 *
 * bytecode:
 * MEMCPY size
 *
 * stack:
 * ..., src_ptr, dst_ptr  --> ..., src_ptr, dst_ptr
 */

int MEMCPY( INSTRUCTION_FN_ARGS )
{
    void *dst = STACKCELL_PTR( istate.ep[0] );
    void *src = STACKCELL_PTR( istate.ep[1] );
    ssize_t size = istate.code[istate.ip+1].ssizeval;

    TRACE_FUNCTION();

    if( !src || !dst ) {
	/* assert( 0 ); */
	return 1;
    }

    memcpy( dst, src, size );

    return 2;
}

/*
 ZLDC (load constant)

 bytcode:
 ZLDC ssize_t_value

 stack:
 --> ssize_t_value

 'ssize_t_value', an ssize_t large integer constant, is taken from the
 bytecode and loaded onto the stack.

 */

int ZLDC( INSTRUCTION_FN_ARGS )
{
    ssize_t value = istate.code[istate.ip+1].ssizeval;

    TRACE_FUNCTION();

    istate.ep --;
    istate.ep[0].num.ssize = value;

    return 2;
}

/*
 ENTER (enter function)

 bytecode:
 ENTER nvars

 stack:
 -->

 Allocate 'nvar' local variables on the function (call) stack
 and fill them with zeros.

 */

int ENTER( INSTRUCTION_FN_ARGS )
{
    ssize_t nvars = istate.code[istate.ip+1].ssizeval;

    TRACE_FUNCTION();

    istate.sp -= nvars;
    memset( istate.sp, 0, sizeof(*istate.sp) * nvars );

    return 2;
}

/*
 CALL (call a bytecode function)

 bytecode:
 CALL offset

 stack:
 --> 
 
 */

int CALL( INSTRUCTION_FN_ARGS )
{
    ssize_t offset = istate.code[istate.ip+1].ssizeval;

    TRACE_FUNCTION();

    (--istate.sp)->num.ssize = istate.ip + 2; /* push the return address */
    (--istate.sp)->num.ptr = istate.fp;       /* push old frame pointer */
    istate.fp = istate.sp;                    /* set the frame pointer for the
						 called procedure */
    STACKCELL_ZERO_PTR( istate.sp[0] );
    STACKCELL_ZERO_PTR( istate.sp[1] );
#if 0
    istate.ip += offset;
    return 0; /* jump to the called procedure -- relative offset */
#else
    istate.ip = offset;
    return 0; /* jump to the called procedure -- absolute offset */
#endif
}

/*
 ICALL (indirect call of a bytecode function)

 bytecode:
 ICALL

 stack:
 function_address --> 
 
 */

int ICALL( INSTRUCTION_FN_ARGS )
{
    thrcode_t* fn_ptr = STACKCELL_PTR( istate.ep[0] );

    TRACE_FUNCTION();

    (--istate.sp)->num.ssize = istate.ip + 1; /* push the return address */
    (--istate.sp)->num.ptr = istate.fp;       /* push old frame pointer */
    istate.fp = istate.sp;                    /* set the frame pointer
						 for the called procedure */
    STACKCELL_ZERO_PTR( istate.sp[0] );
    STACKCELL_ZERO_PTR( istate.sp[1] );

    if( fn_ptr < istate.code || fn_ptr > istate.code + istate.code_length ) {
        /* we are calling a closure: */
        fn_ptr = ((void**)(((alloccell_t*)(fn_ptr))-1))[-1];
    } else {
        /* we are calling a function: */
        istate.ep ++;
    }

    istate.ip = fn_ptr - istate.code;
    return 0; /* jump to the called procedure -- absolute offset */
}

/*
 VCALL (call virtual method (virtual function))

 bytecode:
 VCALL interface_nr virtual_function_nr

 stack:
 object_address --> 
 
 */

int VCALL( INSTRUCTION_FN_ARGS )
{
    ssize_t interface_nr = istate.code[istate.ip+1].ssizeval;
    ssize_t virtual_function_nr = istate.code[istate.ip+2].ssizeval;
    thrcode_t* object_ptr = STACKCELL_PTR( istate.ep[0] );
    alloccell_t *header;
    ssize_t *itable, *vtable;
    ssize_t virtual_function_offset;

    TRACE_FUNCTION();

    header = (alloccell_t*)object_ptr;
    itable = header[-1].vmt_offset;
    /* in future, test that the virtual function or interface index is
       not outside the virtual function table. */
    vtable = (ssize_t*)(istate.static_data + itable[interface_nr + 1]);
    virtual_function_offset = vtable[virtual_function_nr];

    istate.ep ++;

    (--istate.sp)->num.ssize = istate.ip + 3; /* push the return address */
    (--istate.sp)->num.ptr = istate.fp;       /* push old frame pointer */
    istate.fp = istate.sp;                    /* set the frame pointer for the
						 called procedure */
    STACKCELL_ZERO_PTR( istate.sp[0] );
    STACKCELL_ZERO_PTR( istate.sp[1] );

    istate.ip = virtual_function_offset;
    return 0; /* jump to the called procedure -- absolute offset */
}

/*
 DUMPVMT (Dump Virtual Method Table of an object, for debug purposes)

 bytecode:
 DUMPVMT

 stack:
 object_address --> 
 
 */

int DUMPVMT( INSTRUCTION_FN_ARGS )
{
    thrcode_t* object_ptr = STACKCELL_PTR( istate.ep[0] );
    alloccell_t *header;
    ssize_t *itable, *vtable;
    ssize_t interface_nr, vm_nr, i, j;

    TRACE_FUNCTION();

    header = (alloccell_t*)object_ptr;
    itable = header[-1].vmt_offset;

    istate.ep ++;

    interface_nr = itable[0];
    for( i = 0; i <= interface_nr; i++ ) {
	if( i == 0 ) {
	    printf( "NUMBER OF INTERFCES = %d\n", itable[i] );
	    continue;
	}

	printf( "INTERFACE[%d]: vmt offset = %d\n", i, itable[i] );
        if( itable[i] == 0 ) continue;

	vtable = (ssize_t*)(istate.static_data + itable[i]);
	vm_nr = vtable[0];
	for( j = 0; j <= vm_nr; j++ ) {
	    printf( "VMT[%d]: %d\n", j, vtable[j] );
	}
    }

    return 1;
}

/*
 RTOR (transfer Reference TO the Return stack)

 bytecode:
 RTOR

 stack:
 reference --> ; rertun stack: --> reference
 
 */

int RTOR( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    // (--istate.sp)->ssize = (istate.ep++)->ssize;
    --istate.sp;
    STACKCELL_SET_ADDR( istate.sp[0], STACKCELL_PTR( istate.ep[0] ));
    istate.ep++;
    return 1;
}

/*
 RFROMR (transfer Reference FROM the Return stack)

 bytecode:
 RFROMR

 stack:
 --> reference ; rertun stack: reference -->
 
 */

int RFROMR( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    // (--istate.ep)->ssize = (istate.sp++)->ssize ;
    --istate.ep;
    STACKCELL_SET_ADDR( istate.ep[0], STACKCELL_PTR( istate.sp[0] ));
    istate.sp++;
    return 1;
}

/*
 LDFN (LoaD FunctioN address)

 bytecode:
 LDFS function_offset

 stack:
 --> function_address
 */

int LDFN( INSTRUCTION_FN_ARGS )
{
    ssize_t offset = istate.code[istate.ip+1].ssizeval;

    TRACE_FUNCTION();

    istate.ep--;
    STACKCELL_SET_ADDR( istate.ep[0], istate.code + offset );

    return 2;
}

/*
 RET (return from a bytecode function)

 bytecode:
 RET

 stack:
 --> 
 
 */

int RET( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    istate.sp = istate.fp;
    istate.fp = (istate.sp++)->num.ptr;
    istate.ip = (istate.sp++)->num.ssize;

    return 0;
}

/*
 PUSHFRM (push a function call frame)

 bytecode:
 PUSHFRM

 stack:
 --> 
 
 */

int PUSHFRM( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    (--istate.sp)->ptr = istate.fp;     /* push old frame pointer */
    istate.fp = istate.sp;              /* set the frame pointer for the
					   called procedure */
    return 1;
}

/*
 POPFRM (pop a function stack frame)

 bytecode:
 POPFRM

 stack:
 --> 
 
 */

int POPFRM( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    istate.sp = istate.fp;
    istate.fp = (istate.sp++)->ptr;

    return 1;
}

/*
 JMP (unconditional jump)

 bytecode:
 JMP offset

 stack:
 --> 
 
 */

int JMP( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    istate.ip += istate.code[istate.ip+1].ssizeval;

    return 0;
}

/*
 ALLOCARGV -- allocate array of strings with program arguments.

 bytecode:
 ALLOCARGV

 stack:
 --> array of string
 
 */

int ALLOCARGV( INSTRUCTION_FN_ARGS )
{
    char **ptr = NULL;
    int i;

    TRACE_FUNCTION();

    istate.ep --;

    if( istate.argc >= 0 && istate.argv != NULL ) {

	ptr = bcalloc_array( REF_SIZE, istate.argc + 1, 1 );

	BC_CHECK_PTR( ptr );
	STACKCELL_SET_ADDR( istate.ep[0], ptr );

	for( i = 0; i <= istate.argc; i++ ) {
	    ptr[i] = bcalloc_blob( strlen( istate.argv[i]) + 1 );
	    BC_CHECK_PTR( ptr[i] );
	    strcpy( ptr[i], istate.argv[i] );
	}
    }

    return 1;
}

/*
 ALLOCENV -- allocate array of strings with environment variables.

 bytecode:
 ALLOCENV

 stack:
 --> array of string
 
 */

int ALLOCENV( INSTRUCTION_FN_ARGS )
{
    char **env = NULL;
    int i, n;

    TRACE_FUNCTION();

    istate.ep --;

    if( istate.env ) {
	for( n = 0; istate.env[n] != NULL; ) {
	    n++;
	}
	if( n > 0 ) {
	    env = bcalloc_array( REF_SIZE, n, 1 );

	    BC_CHECK_PTR( env );
	    STACKCELL_SET_ADDR( istate.ep[0], env );
	    
	    for( i = 0; i < n; i++ ) {
		env[i] = bcalloc_blob( strlen( istate.env[i]) + 1 );
		BC_CHECK_PTR( env[i] );
		strcpy( env[i], istate.env[i] );
	    }
	} else {
	    STACKCELL_SET_ADDR( istate.ep[0], NULL );
	}
    }

    return 1;
}

/*
** Exception handling bytecode operators.
*/

int TRY( INSTRUCTION_FN_ARGS )
{
    ssize_t offset = istate.code[istate.ip+1].ssizeval;
    ssize_t tryreg = istate.code[istate.ip+2].ssizeval;
    interpret_exception_t *rg_store = bcalloc
        ( sizeof(interpret_exception_t), INTERPRET_EXCEPTION_PTRS );

    TRACE_FUNCTION();

    BC_CHECK_PTR( rg_store );
    STACKCELL_SET_ADDR( istate.fp[tryreg], rg_store );

    rg_store->old_xp.ptr = istate.xp;
    rg_store->ip = istate.ip;
    rg_store->sp = istate.sp;
    rg_store->fp = istate.fp;
    rg_store->ep = istate.ep;
    rg_store->error_code = 0;
    rg_store->message.ptr = NULL;
    rg_store->module = NULL;
    rg_store->exception_id = 0;
    rg_store->catch_offset = offset;

    istate.xp = rg_store;

    return 3;
}

int RESTORE( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();
    istate.xp = istate.xp->old_xp.ptr;
    return 1;
}

int RAISEX( INSTRUCTION_FN_ARGS )
{
    int err_code = istate.ep[1].num.i;
    char *message = STACKCELL_PTR( istate.ep[0] );

    TRACE_FUNCTION();

    /* No need to adjust ep since it will be restored from exception
       structure anyway */

    interpret_raise_exception( err_code, message, /*module*/ NULL, 0,
			       EXCEPTION );

    return 0;
}

/*
 RAISE -- raise hard-coded exception

 bytecode:
 RAISE module_id exception_id

 stack:
 error_code, message --> ... (stack will be unwound by the thrown exception)
 */

int RAISE( INSTRUCTION_FN_ARGS )
{
    char *module_id = istate.code[istate.ip+1].ptr;
    int exception_id = istate.code[istate.ip+2].ssizeval;
    int err_code = istate.ep[1].num.i;
    char *message = STACKCELL_PTR( istate.ep[0] );

    TRACE_FUNCTION();

    /* No need to adjust ep since it will be restored from exception
       structure anyway */

    interpret_raise_exception( err_code, message, module_id, exception_id,
			       EXCEPTION );

    return 0;
}

/*
 RERAISE -- reraise exception from the catch block

 bytecode:
 RERAISE exception_var_offset

 stack:
 ... --> ... (stack will be unwound further by the thrown exception)
 */

int RERAISE( INSTRUCTION_FN_ARGS )
{
    ssize_t xp_offset = istate.code[istate.ip+1].ssizeval;
    interpret_exception_t *xp;

    TRACE_FUNCTION();

    xp = STACKCELL_PTR( istate.fp[xp_offset] );

    /* No need to adjust ep since it will be restored from exception
       structure anyway */

    if( xp ) {
	interpret_raise_exception( xp->error_code, xp->message.ptr,
				   xp->module, xp->exception_id,
				   EXCEPTION );
    }

    return 0;
}

/*
 EXCEPTIONEQ -- check whether exception number maches integer on the
 top of the evaluation stack.

 bytecode:
 EXCEPTIONEQ

 stack:
 exception, integer --> boolean
 
 */

int EXCEPTIONEQ( INSTRUCTION_FN_ARGS )
{
    
    TRACE_FUNCTION();

    istate.ep[1].num.b = (istate.ep[1].num.i == istate.ep[0].num.i);
    STACKCELL_ZERO_PTR( istate.ep[1] );
    istate.ep ++;
    return 1;
}

/*
 ERRORMSG -- store the message of the exception on the top of the
 evaluation stack.

 bytecode:
 ERRORMSG

 stack:
 exception --> string
 
 */

int ERRORMSG( INSTRUCTION_FN_ARGS )
{
    interpret_exception_t *xp;

    TRACE_FUNCTION();

    xp = STACKCELL_PTR( istate.ep[0] );

    if( xp ) {
	STACKCELL_SET_ADDR( istate.ep[0], xp->message.ptr );
    } else {
	STACKCELL_ZERO_PTR( istate.ep[0] );
    }
    return 1;
}

/*
 ERRORCODE -- store number of the error code of the exception on the
 top of the evaluation stack.

 bytecode:
 ERRORCODE

 stack:
 exception --> int
 
 */

int ERRORCODE( INSTRUCTION_FN_ARGS )
{
    interpret_exception_t *xp;

    TRACE_FUNCTION();

    xp = STACKCELL_PTR( istate.ep[0] );

    if( xp ) {
	istate.ep[0].num.i = xp->error_code;
    } else {
	istate.ep[0].num.i = 0;
    }
    STACKCELL_ZERO_PTR( istate.ep[0] );
    return 1;
}

/*
 EXCEPTIONID -- store the module-unique exception number on the top of
 the evaluation stack.

 bytecode:
 EXCEPTIONID

 stack:
 exception --> int
 
 */

int EXCEPTIONID( INSTRUCTION_FN_ARGS )
{
    interpret_exception_t *xp;

    TRACE_FUNCTION();

    xp = STACKCELL_PTR( istate.ep[0] );

    if( xp ) {
	istate.ep[0].num.i = xp->exception_id;
    } else {
	istate.ep[0].num.i = 0;
    }
    STACKCELL_ZERO_PTR( istate.ep[0] );
    return 1;
}

/*
 EXCEPTIONMODULE -- store a module identifier on the top of the evaluation
 stack.

 bytecode:
 EXCEPTIONMODULE

 stack:
 exception --> char*
 
 */

int EXCEPTIONMODULE( INSTRUCTION_FN_ARGS )
{
    interpret_exception_t *xp;

    TRACE_FUNCTION();

    xp = STACKCELL_PTR( istate.ep[0] );

    if( xp ) {
	istate.ep[0].ptr = xp->module;
    } else {
	istate.ep[0].ptr = NULL;
    }
    return 1;
}

/*
** File management bytecode operators.
*/

/*
 ALLOCSTDIO -- allocate array of file variables.

 bytecode:
 ALLOCSTDIO

 stack:
 --> array of file
 
 */

int ALLOCSTDIO( INSTRUCTION_FN_ARGS )
{
    bytecode_file_hdr_t **files = NULL;
    int i;
    const int n = 3;

    TRACE_FUNCTION();

    istate.ep --;

    files = bcalloc_array( REF_SIZE, n, 1 );
    BC_CHECK_PTR( files );
    STACKCELL_SET_ADDR( istate.ep[0], files );

    for( i = 0; i < n; i++ ) {
        bytecode_file_hdr_t* current_file;
	files[i] =
            bcalloc( sizeof(bytecode_file_hdr_t), INTERPRET_FILE_PTRS );
	BC_CHECK_PTR( files[i] );
        current_file = (bytecode_file_hdr_t*)files[i];

        current_file->fd = i;
	switch(i) {
	case 0:
	    current_file->fp = stdin;
	    current_file->filename = bcstrdup( "-" );
	    break;
	case 1:
	    current_file->fp = stdout;
	    current_file->filename = bcstrdup( "-" );
	    break;
	case 2:
	    current_file->fp = stderr;
	    current_file->filename = bcstrdup( "<stderr>" );
	    break;
	default:
	    assert( 0 );
	}
	BC_CHECK_PTR( current_file->filename );
    }
    return 1;
}

/*
 FDFILE -- create file structure for a specified file descriptor

 bytecode:
 FDFILE fd

 stack:
 --> file
 
 */

int FDFILE( INSTRUCTION_FN_ARGS )
{
    ssize_t fd = istate.code[istate.ip+1].lval;
    bytecode_file_hdr_t *file = NULL;

    TRACE_FUNCTION();

    istate.ep --;

    file = bcalloc( sizeof(bytecode_file_hdr_t), INTERPRET_FILE_PTRS );
    BC_CHECK_PTR( file );
    STACKCELL_SET_ADDR( istate.ep[0], file );

    file->fd = fd;
    switch(fd) {
    case 0:
        file->fp = stdin;
        file->filename = bcstrdup( "-" );
        break;
    case 1:
        file->fp = stdout;
        file->filename = bcstrdup( "-" );
        break;
    case 2:
        file->fp = stderr;
        file->filename = bcstrdup( "<stderr>" );
        break;
    default:
        assert( 0 );
    }

    return 2;
}

/*
 FNAME -- return the name of a file

 bytecode:
 FNAME

 stack:
 file --> string
 
 */

int FNAME( INSTRUCTION_FN_ARGS )
{
    bytecode_file_hdr_t *fhdr = STACKCELL_PTR( istate.ep[0] );
    char *filename = NULL;

    TRACE_FUNCTION();

    if( fhdr ) {
	filename = fhdr->filename;
    }

    STACKCELL_SET_ADDR( istate.ep[0], filename );

    return 1;
}

/*
 * FOPEN -- open file with a given name and mode
 *
 * bytecode:
 * FOPEN
 *
 * stack:
 * ..., filename, mode --> ..., file
 *
 */

int FOPEN( INSTRUCTION_FN_ARGS )
{
    char *mode = STACKCELL_PTR(istate.ep[0]);
    char *name = STACKCELL_PTR(istate.ep[1]);
    FILE *fp;
    bytecode_file_hdr_t *file;

    TRACE_FUNCTION();

    file = bcalloc( sizeof(*file), INTERPRET_FILE_PTRS );

    BC_CHECK_PTR( file );
    fp = fopen( name, mode );

    if( fp ) {
	file->fp = fp;
	file->filename = name;

	STACKCELL_ZERO_PTR( istate.ep[0] );
	istate.ep ++;
	STACKCELL_SET_ADDR( istate.ep[0], file );
	return 1;
    } else {
	char *modename;
	char *message;
	char modepad[80];

	if( mode[0] == 'r' && mode[1] == '\0' ) {
	    modename = "reading";
	} else
	if( mode[0] == 'w' && mode[1] == '\0' ) {
	    modename = "writing";
	} else {
	    snprintf( modepad, sizeof(modepad), "mode %s", mode );
	    modename = modepad;
	}

	message =
	    (char*)cxprintf( "could not open file '%s' for %s: %s",
			     name, modename, strerror( errno ));

	interpret_raise_exception_with_bcalloc_message( /* err_code = */  errno,
							/* message = */   message,
							/* module_id = */ 0,
							/* exception_id = */
							SL_EXCEPTION_SYSTEM_ERROR,
							EXCEPTION );
	return 0;
    }
}

int FCLOSE( INSTRUCTION_FN_ARGS )
{
    bytecode_file_hdr_t *file = STACKCELL_PTR(istate.ep[0]);

    TRACE_FUNCTION();

    fclose( file->fp );
    file->fp = NULL;
    file->filename = NULL;

    STACKCELL_ZERO_PTR( istate.ep[0] );
    istate.ep ++;

    return 1;
}


/*
 * FREAD -- read bytes from a file
 *
 * bytecode:
 * FREAD
 *
 * stack:
 * ..., file, array --> ..., ssize_t
 *
 */

int FREAD( INSTRUCTION_FN_ARGS )
{
    void *blob = istate.ep[0].PTR;
    alloccell_t *blob_header = &((alloccell_t*)blob)[-1];
    bytecode_file_hdr_t *file = STACKCELL_PTR(istate.ep[1]);
    FILE *fp = file ? file->fp : NULL;
    /* Below we must check blob, not blob_header, for NULL: */
    ssize_t blob_size = blob ? blob_header->length : 0;
    ssize_t elements_read = 0;

    TRACE_FUNCTION();

    if( !file ) {
	interpret_raise_exception_with_bcalloc_message( /* err_code = */ -1,
							/* message = */
							"attempt to read from a file "
							"which was never opened",
							/* module_id = */ 0,
							/* exception_id = */
							SL_EXCEPTION_NULL_ERROR,
							EXCEPTION );
	return 0;
    }

    if( !fp ) {
	interpret_raise_exception_with_bcalloc_message( /* err_code = */ -1,
							/* message = */
							"attempt to read from a closed file",
							/* module_id = */ 0,
							/* exception_id = */
							SL_EXCEPTION_NULL_ERROR,
							EXCEPTION );
	return 0;
    }

    if( blob && blob_header->nref != 0 ) {
	interpret_raise_exception_with_bcalloc_message( /* err_code = */ -1,
							/* message = */
							"reading structures with references from files is will "
							"crash your program, for sure",
							/* module_id = */ 0,
							/* exception_id = */
							SL_EXCEPTION_NULL_ERROR,
							EXCEPTION );
	return 0;
    }

    if( blob ) {

	elements_read = fread( blob, 1, blob_size, fp );

	if( elements_read < 0 ) {
	    char *message =
		(char*)cxprintf( "could not read file '%s': %s",
				 file->filename, strerror( errno ));
	    interpret_raise_exception_with_bcalloc_message( /* err_code = */  errno,
							    /* message = */   message,
							    /* module_id = */ 0,
							    /* exception_id = */
							    SL_EXCEPTION_SYSTEM_ERROR,
							    EXCEPTION );
	    return 0;
	} else {
	    STACKCELL_ZERO_PTR( istate.ep[0] );
	    STACKCELL_ZERO_PTR( istate.ep[1] );
	    istate.ep ++;
	    istate.ep[0].num.ssize = elements_read;
	}
    }
    return 1;
}

/*
 * FWRITE -- write bytes to a file
 *
 * bytecode:
 * FWRITE
 *
 * stack:
 * ..., file, blob --> ..., ssize_t
 *
 */

int FWRITE( INSTRUCTION_FN_ARGS )
{
    void *blob = istate.ep[0].PTR;
    alloccell_t *blob_header = &((alloccell_t*)blob)[-1];
    bytecode_file_hdr_t *file = STACKCELL_PTR(istate.ep[1]);
    FILE *fp = file ? file->fp : NULL;
    /* Below we must check blob, not blob_header, for NULL: */
    ssize_t blob_size = blob ? blob_header->length : 0;
    ssize_t elements_written = 0;

    TRACE_FUNCTION();

    if( !file ) {
	interpret_raise_exception_with_bcalloc_message( /* err_code = */ -1,
							/* message = */
							"attempt to write to a file "
							"which was never opened",
							/* module_id = */ 0,
							/* exception_id = */
							SL_EXCEPTION_NULL_ERROR,
							EXCEPTION );
	return 0;
    }

    if( !fp ) {
	interpret_raise_exception_with_bcalloc_message( /* err_code = */ -1,
							/* message = */
							"attempt to write to a closed file",
							/* module_id = */ 0,
							/* exception_id = */
							SL_EXCEPTION_NULL_ERROR,
							EXCEPTION );
	return 0;
    }

    if( blob ) {

	elements_written = fwrite( blob, 1, blob_size, fp );

	if( errno != 0 /*ERROK???*/ ) {
	    char *message =
		(char*)cxprintf( "could not write file '%s': %s",
				 file->filename, strerror( errno ));
	    interpret_raise_exception_with_bcalloc_message( /* err_code = */  errno,
							    /* message = */   message,
							    /* module_id = */ 0,
							    /* exception_id = */
							    SL_EXCEPTION_SYSTEM_ERROR,
							    EXCEPTION );
	    return 0;
	} else {
	    STACKCELL_ZERO_PTR( istate.ep[0] );
	    STACKCELL_ZERO_PTR( istate.ep[1] );
	    istate.ep ++;
	    istate.ep[0].num.ssize = elements_written;
	}
    }
    return 1;
}

/*
 * FSEEK -- write bytes to a file
 *
 * bytecode:
 * FSEEK
 *
 * stack:
 * ..., file, offset, whence --> ...,
 *
 */

int FSEEK( INSTRUCTION_FN_ARGS )
{
    int whence = istate.ep[0].num.i;
    long offset = istate.ep[1].num.l;
    bytecode_file_hdr_t *file = STACKCELL_PTR(istate.ep[2]);
    FILE *fp = file ? file->fp : NULL;
    int err_code;

    TRACE_FUNCTION();

    if( !file ) {
	interpret_raise_exception_with_bcalloc_message( /* err_code = */ -1,
							/* message = */
							"attempt to write to a file "
							"which was never opened",
							/* module_id = */ 0,
							/* exception_id = */
							SL_EXCEPTION_NULL_ERROR,
							EXCEPTION );
	return 0;
    }

    if( !fp ) {
	interpret_raise_exception_with_bcalloc_message( /* err_code = */ -1,
							/* message = */
							"attempt to write to a closed file",
							/* module_id = */ 0,
							/* exception_id = */
							SL_EXCEPTION_NULL_ERROR,
							EXCEPTION );
	return 0;
    }

    switch( whence ) {
    case 0:
	whence = SEEK_SET;
	break;
    case 1:
	whence = SEEK_CUR;
	break;
    case 2:
	whence = SEEK_END;
	break;
    default:
	interpret_raise_exception_with_bcalloc_message( /* err_code = */ -2,
							/* message = */
							"unknown 'whence' parameter for fseek",
							/* module_id = */ 0,
							/* exception_id = */
							SL_EXCEPTION_NULL_ERROR,
							EXCEPTION );
	return 0;
	break;
    }

    err_code = fseek( fp, offset, whence );

    if( err_code != 0 /*ERROK???*/ ) {
	char *message =
	    (char*)cxprintf( "could not seek file '%s': %s",
			     file->filename, strerror( errno ));
	interpret_raise_exception_with_bcalloc_message( /* err_code = */  errno,
							/* message = */   message,
							/* module_id = */ 0,
							/* exception_id = */
							SL_EXCEPTION_SYSTEM_ERROR,
							EXCEPTION );
	return 0;
    } else {
	STACKCELL_ZERO_PTR( istate.ep[2] );
	istate.ep += 3;
    }
    return 1;
}

/*
 * FTELL -- return the current position in a seekable file
 *
 * bytecode:
 * FTELL
 *
 * stack:
 * ..., file --> ..., position
 *
 */

int FTELL( INSTRUCTION_FN_ARGS )
{
    bytecode_file_hdr_t *file = STACKCELL_PTR(istate.ep[0]);
    FILE *fp = file ? file->fp : NULL;
    long pos = fp ? ftell( fp ) : -1;

    STACKCELL_ZERO_PTR( istate.ep[0] );

    istate.ep[0].num.l = pos;

    return 1;
}

/*
 * FEOF -- check end-of-file status of the file.
 *
 * bytecode:
 * FEOF
 *
 * stack:
 * ..., file --> ..., eof-flag (bool)
 *
 */

int FEOF( INSTRUCTION_FN_ARGS )
{
    bytecode_file_hdr_t *file = STACKCELL_PTR(istate.ep[0]);
    FILE *fp = file ? file->fp : NULL;
    int eof_flag = fp ? feof( fp ) : 1;

    STACKCELL_ZERO_PTR( istate.ep[0] );

    istate.ep[0].num.b = eof_flag;

    return 1;
}

/*
** Type conversion opcodes:
*/

/*
 * EXTEND converts integer value on the top of the stack to long integer 
 * 
 * bytecode:
 * EXTEND
 * 
 * stack:
 * int -> long
 * 
 */

int EXTEND( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    istate.ep[0].num.l = istate.ep[0].num.i;

    return 1;
}

/*
 * HEXTEND converts short integer value on the top of the stack into integer 
 * 
 * bytecode:
 * HEXTEND
 * 
 * stack:
 * short -> int
 * 
 */

int HEXTEND( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    istate.ep[0].num.i = istate.ep[0].num.s;

    return 1;
}

/*
 * LEXTEND converts long integer value on the top of the stack to a
 * long long integer
 * 
 * bytecode:
 * LEXTEND
 * 
 * stack:
 * long -> llong
 * 
 */

int LEXTEND( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    istate.ep[0].num.ll = istate.ep[0].num.l;

    return 1;
}

/*
 * LOWBYTE take low byte of a short number and present them as a byte;
 *         raise exception if the result does not fit into the result.
 * 
 * bytecode:
 * LOWBYTE
 * 
 * stack:
 * short -> byte
 * 
 */

int LOWBYTE( INSTRUCTION_FN_ARGS )
{
    byte b;

    TRACE_FUNCTION();

    b = istate.ep[0].num.s;
    if( istate.ep[0].num.s == b ) {
        istate.ep[0].num.b = b;
    } else {
	interpret_raise_exception_with_bcalloc_message
	    ( /* err_code = */ -1,
	      /* message = */
	      "short integer value does not fit into a byte on conversion",
	      /* module_id = */ 0,
	      /* exception_id = */ SL_EXCEPTION_TRUNCATED_INTEGER,
	      EXCEPTION );
	return 0;
    }

    return 1;
}

/*
 * LOWSHORT take low bytes of an int number and present them as short;
 *          raise exception if the result does not fit into the result.
 * 
 * bytecode:
 * LOWSHORT
 * 
 * stack:
 * int -> short
 * 
 */

int LOWSHORT( INSTRUCTION_FN_ARGS )
{
    short s;

    TRACE_FUNCTION();

    s = istate.ep[0].num.i;
    if( istate.ep[0].num.i == s ) {
        istate.ep[0].num.s = s;
    } else {
	interpret_raise_exception_with_bcalloc_message
	    ( /* err_code = */ -2,
	      /* message = */
	      "integer value does not fit into short int on conversion",
	      /* module_id = */ 0,
	      /* exception_id = */ SL_EXCEPTION_TRUNCATED_INTEGER,
	      EXCEPTION );
	return 0;
    }

    return 1;
}

/*
 * LOWINT take low bytes of a long number and present them as int;
 *        raise exception if the result does not fit into the integer.
 * 
 * bytecode:
 * LOWINT
 * 
 * stack:
 * long -> int
 * 
 */

int LOWINT( INSTRUCTION_FN_ARGS )
{
    int i;

    TRACE_FUNCTION();

    i = istate.ep[0].num.l;
    if( istate.ep[0].num.l == i ) {
        istate.ep[0].num.i = i;
    } else {
	interpret_raise_exception_with_bcalloc_message
	    ( /* err_code = */ -3,
	      /* message = */
	      "long value does not fit into integer on conversion",
	      /* module_id = */ 0,
	      /* exception_id = */ SL_EXCEPTION_TRUNCATED_INTEGER,
	      EXCEPTION );
	return 0;
    }

    return 1;
}

/*
 * LOWLONG take low bytes of a long number and present them as int;
 *         raise exception if the result does not fit into the result.
 * 
 * bytecode:
 * LOWLONG
 * 
 * stack:
 * llong -> long
 * 
 */

int LOWLONG( INSTRUCTION_FN_ARGS )
{
    long l;

    TRACE_FUNCTION();

    l = istate.ep[0].num.ll;
    if( istate.ep[0].num.ll == l ) {
        istate.ep[0].num.l = l;
    } else {
	interpret_raise_exception_with_bcalloc_message
	    ( /* err_code = */ -4,
	      /* message = */
	      "llong value does not fit into long on conversion",
	      /* module_id = */ 0,
	      /* exception_id = */ SL_EXCEPTION_TRUNCATED_INTEGER,
	      EXCEPTION );
	return 0;
    }

    return 1;
}

/*
 * I2F converts integer value on the top of the stack to a floating point 
 * 
 * bytecode:
 * I2F
 * 
 * stack:
 * int -> float
 * 
 */

int I2F( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    istate.ep[0].num.f = istate.ep[0].num.i;

    return 1;
}

/*
 * L2F converts a long integer value on the top of the stack to a
 * floating point number.
 * 
 * bytecode:
 * L2F
 * 
 * stack:
 * long -> float
 * 
 */

int L2F( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    istate.ep[0].num.f = istate.ep[0].num.l;

    return 1;
}

/*
 * LL2F converts a long long integer value on the top of the stack to
 * a floating point number.
 * 
 * bytecode:
 * LL2F
 * 
 * stack:
 * llong -> float
 * 
 */

int LL2F( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    istate.ep[0].num.f = istate.ep[0].num.ll;

    return 1;
}

/*
 * I2D converts integer value on the top of the stack into a double value
 * 
 * bytecode:
 * I2D
 * 
 * stack:
 * int -> double
 * 
 */

int I2D( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    istate.ep[0].num.d = istate.ep[0].num.i;

    return 1;
}

/*
 * L2D converts a long integer value on the top of the stack into a
 * double precission floating point number.
 * 
 * bytecode:
 * L2D
 * 
 * stack:
 * long -> double
 * 
 */

int L2D( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    istate.ep[0].num.d = istate.ep[0].num.l;

    return 1;
}

/*
 * LL2D converts a long long integer value on the top of the stack into
 * a double precission floating point number.
 * 
 * bytecode:
 * LL2D
 * 
 * stack:
 * llong -> double
 * 
 */

int LL2D( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    istate.ep[0].num.d = istate.ep[0].num.ll;

    return 1;
}

/*
 * F2D converts a floatong point value on the top of the stack into
 * a double precission floating point number.
 * 
 * bytecode:
 * F2D
 * 
 * stack:
 * float -> double
 * 
 */

int F2D( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    istate.ep[0].num.d = istate.ep[0].num.f;

    return 1;
}

#if 0
/*
 * LFLOORD converts a double precission floating pooint value on the
 * top of the stack to a long integer number.
 * 
 * bytecode:
 * LFLOORD
 * 
 * stack:
 * double -> long
 * 
 */

int LFLOORD( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    istate.ep[0].num.l = (long)floor( istate.ep[0].num.d );

    return 1;
}
#endif

/*
 * I2LD converts integer value on the top of the stack to a ldouble 
 * 
 * bytecode:
 * I2LD
 * 
 * stack:
 * int -> ldouble
 * 
 */

int I2LD( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    istate.ep[0].num.ld = istate.ep[0].num.i;

    return 1;
}

/*
 * L2LD converts a long integer value on the top of the stack to a
 * long double floating point number.
 * 
 * bytecode:
 * L2LD
 * 
 * stack:
 * long -> ldouble
 * 
 */

int L2LD( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    istate.ep[0].num.ld = istate.ep[0].num.l;

    return 1;
}

/*
 * LL2LD converts a long long integer value on the top of the stack to
 * a long double number.
 * 
 * bytecode:
 * LL2LD
 * 
 * stack:
 * llong -> ldouble
 * 
 */

int LL2LD( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    istate.ep[0].num.ld = istate.ep[0].num.ll;

    return 1;
}

/*
 * F2LD converts a floating point value on the top of the stack into
 * a long double floating point number.
 * 
 * bytecode:
 * F2LD
 * 
 * stack:
 * float -> ldouble
 * 
 */

int F2LD( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    istate.ep[0].num.ld = istate.ep[0].num.f;

    return 1;
}

/*
 * D2LD converts a double value on the top of the stack into
 * a long double floating point number.
 * 
 * bytecode:
 * D2LD
 * 
 * stack:
 * double -> ldouble
 * 
 */

int D2LD( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    istate.ep[0].num.ld = istate.ep[0].num.d;

    return 1;
}

#if 0
/*
 * LLFLOORLD converts a long double floating value on the top of the
 * stack into a long long number.
 * 
 * bytecode:
 * LLFLOORLD
 * 
 * stack:
 * ldouble -> llong
 * 
 */

int LLFLOORLD( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    istate.ep[0].num.l = (long)floor( istate.ep[0].num.ld );

    return 1;
}
#endif

/*
 * DFLOAT round a double-precision number to a single precision float
 * 
 * bytecode:
 * DFLOAT
 * 
 * stack:
 * double -> rounded_float
 * 
 */

int DFLOAT( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    istate.ep[0].num.f = istate.ep[0].num.d;

    return 1;
}

/*
 * LDDOUBLE round a double-precision number to a single precision float
 * 
 * bytecode:
 * LDDOBLE
 * 
 * stack:
 * long_double -> rounded_double
 * 
 */

int LDDOUBLE( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    istate.ep[0].num.d = istate.ep[0].num.ld;

    return 1;
}

/*
** String opcodes:
*/

/*
 SLDC (load string constant)

 bytcode:
 SLDC static_string_offset

 stack:
 --> string_address

 'static_string_offset', an offset into istate.static_data, is taken
 from the bytecode and a computed pointer is loaded onto the stack.

 */

int SLDC( INSTRUCTION_FN_ARGS )
{
    ssize_t offset = istate.code[istate.ip+1].ssizeval;
    char *str;

    TRACE_FUNCTION();

    istate.ep --;
    str = istate.static_data + offset;

    STACKCELL_SET_ADDR( istate.ep[0], str );

    return 2;
}

/*
 * SPRINT (print a string value from the top of stack)
 * 
 * bytecode:
 * SPRINT
 * 
 * stack:
 * string -->
 * 
 * Print an string value, given as char* pointer, from the top of stack and
 * remove it.
 */

int SPRINT( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    printf( "%s", (char*)STACKCELL_PTR( istate.ep[0] ));
    STACKCELL_ZERO_PTR( *istate.ep );
    istate.ep ++;

    return 1;
}

/*
 * SFILEPRINT (print string value from the top of stack to a file)
 * 
 * bytecode:
 * SFILEPRINT
 * 
 * stack:
 * ..., file, string --> file
 * 
 * Print a string value to a file from the top of stack and remove it;
 * leave the file value on the top. The format for printing is taken
 * from the file structure.
 */

int SFILEPRINT( INSTRUCTION_FN_ARGS )
{
    bytecode_file_hdr_t *file = STACKCELL_PTR( istate.ep[1] );
    FILE *fp = file ? file->fp : NULL;
    char *format = file ? file->string_format : NULL;

    TRACE_FUNCTION();

    if( !file ) {
	interpret_raise_exception_with_bcalloc_message( /* err_code = */ -1,
							/* message = */
							"attempt to print to a file "
							"which was never opened",
							/* module_id = */ 0,
							/* exception_id = */
							SL_EXCEPTION_NULL_ERROR,
							EXCEPTION );
	return 0;
    }

    if( !fp ) {
	interpret_raise_exception_with_bcalloc_message( /* err_code = */ -1,
							/* message = */
							"attempt to print to a closed file",
							/* module_id = */ 0,
							/* exception_id = */
							SL_EXCEPTION_NULL_ERROR,
							EXCEPTION );
	return 0;
    }

    if( !format ) {
	format = "%s";
    }

    fprintf( fp, format, (char*)STACKCELL_PTR( istate.ep[0] ) );
    STACKCELL_ZERO_PTR( *istate.ep );
    istate.ep ++;

    return 1;
}

/*
 * SFILESCAN (load a string value to the top of stack from a file)
 * 
 * bytecode:
 * SFILESCAN
 * 
 * stack:
 * ..., file --> ..., file, string
 * 
 * Read (scan) a string value from a file from the top of stack; leave
 * the file value and the string value on the top of the stack. The
 * format is taken from the SL file structure. The buffer size is
 * determined from the format.
 */

#include <alloccell.h>

int SFILESCAN( INSTRUCTION_FN_ARGS )
{
    bytecode_file_hdr_t *file = STACKCELL_PTR( istate.ep[0] );
    FILE *fp = file ? file->fp : NULL;
    char *format = file ? file->string_scanf_format : NULL;
    char *length_str = NULL;
    char *buff = NULL;
    ssize_t length, delta_length, old_length;
    int result;
    int ch = 0;

    TRACE_FUNCTION();

    if( !file ) {
	interpret_raise_exception_with_bcalloc_message
            ( /* err_code = */ -1,
              /* message = */
              "attempt to scan a string from a file which was never opened",
              /* module_id = */ 0,
              /* exception_id = */ SL_EXCEPTION_NULL_ERROR,
              EXCEPTION );
	return 0;
    }

    if( !fp ) {
	interpret_raise_exception_with_bcalloc_message
            ( /* err_code = */ -1,
              /* message = */
              "attempt to scan a string from a closed file",
              /* module_id = */ 0,
              /* exception_id = */ SL_EXCEPTION_NULL_ERROR,
              EXCEPTION );
	return 0;
    }

    if( format ) {
	length_str = strstr( format, "%" );
	if( length_str ) length_str ++;
    }

    if( !format || !isdigit( *length_str )) {
	format = "%32s";
	length_str = format + 1;
    }

    delta_length = atoi( length_str );
    length = 0;

    istate.ep --;

    do {
	old_length = length;
	length += delta_length;

	assert( !buff || ((alloccell_t*)buff)[-1].magic == BC_MAGIC );

	buff = bcrealloc_blob( buff, length + 1 );
	BC_CHECK_PTR( buff );
	STACKCELL_SET_ADDR( istate.ep[0], buff );

	result = fscanf( fp, format, buff + old_length );

	if( !feof( fp )) {
	    ch = getc( fp );
	    ungetc( ch, fp );
	}
    } while( result >= 0 && !feof(fp) && !isspace(ch) );

    length = strlen( buff );

    if( length > 0 ) {
	buff = bcrealloc_blob( buff, length+1 );
	BC_CHECK_PTR( buff );
    } else {
	buff = NULL;
    }
    STACKCELL_SET_ADDR( istate.ep[0], buff );

    return 1;
}

/*
 * SFILEREADLN (load file line as a string onto the top of the stack).
 * 
 * bytecode:
 * SFILEREADLN
 * 
 * stack:
 * ..., file, eol_char --> ..., file, string
 * 
 * Read (scan) one line from a file into a string value at the top of
 * stack; leave the file value and the string value on the top of the
 * stack.
 */

#include <alloccell.h>

int SFILEREADLN( INSTRUCTION_FN_ARGS )
{
    char eol_char = istate.ep[0].num.c;
    bytecode_file_hdr_t *file = STACKCELL_PTR( istate.ep[1] );
    FILE *fp = file ? file->fp : NULL;
    char *buff = NULL;
    ssize_t length = 0, delta_length = 20, char_count = 0;
    int ch = 0;

    TRACE_FUNCTION();

    if( !file ) {
	interpret_raise_exception_with_bcalloc_message
            ( /* err_code = */ -1,
              /* message = */
              "attempt to scan a string from a file which was never opened",
              /* module_id = */ 0,
              /* exception_id = */ SL_EXCEPTION_NULL_ERROR,
              EXCEPTION );
	return 0;
    }

    if( !fp ) {
	interpret_raise_exception_with_bcalloc_message
            ( /* err_code = */ -1,
              /* message = */
              "attempt to scan a string from a closed file",
              /* module_id = */ 0,
              /* exception_id = */ SL_EXCEPTION_NULL_ERROR,
              EXCEPTION );
	return 0;
    }

    while( (ch = getc( fp )) != EOF ) {
	if( ferror( fp )) {
	    interpret_raise_exception_with_bcalloc_message
                ( /* err_code = */ -1,
                  /* message = */ strerror(errno),
                  /* module_id = */ 0,
                  /* exception_id = */ SL_EXCEPTION_NULL_ERROR,
                  EXCEPTION );
	    return 0;
	}
	if( ch == eol_char ) {
	    break;
	}
	if( char_count >= length ) {
	    length += delta_length;
	    assert( !buff || ((alloccell_t*)buff)[-1].magic == BC_MAGIC );
	    buff = bcrealloc_blob( buff, length + 1 );
	    BC_CHECK_PTR( buff );
	    STACKCELL_SET_ADDR( istate.ep[0], buff );
	}

	buff[char_count] = ch;
	char_count ++;
    }

    if( buff ) {
	buff = bcrealloc_blob( buff, char_count+1 );
	BC_CHECK_PTR( buff );
	buff[char_count] = '\0';
    } else {
	if( ch == eol_char ) {
	    buff = bcrealloc_blob( buff, 1 );
	    BC_CHECK_PTR( buff );
	    buff[char_count] = '\0';
	}
    }

    STACKCELL_SET_ADDR( istate.ep[0], buff );

    return 1;
}

/*
** reference processing opcodes:
*/

/*
 * PLDZ  load zero pointer (reference).
 *
 * bytecode:
 * PLDZ
 *
 * stack:
 * -> null
 *
 */

int PLDZ( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    istate.ep --;
    STACKCELL_SET_ADDR( istate.ep[0], NULL );

    return 1;
}

/*
 PLD (load reference)

 bytcode:
 PLD offset

 stack:
 --> value

 'offset' identifies local variable relative to 'istate.fp', and the value
 of this variable is loaded onto the stack. The value is reference to
 an allocated (and garbage-collectable) data block.

 */

int PLD( INSTRUCTION_FN_ARGS )
{
    ssize_t offset = istate.code[istate.ip+1].ssizeval;

    TRACE_FUNCTION();

    istate.ep --;
    STACKCELL_MOVE_PTR( istate.ep[0], istate.fp[offset] );

    return 2;
}

/*
 PLDA (load reference-variable address)

 bytcode:
 PLDA offset

 stack:
 --> value

 'offset' identifies local variable relative to 'istate.fp', and the ADDRESS
 of this variable is loaded onto the stack

 */

int PLDA( INSTRUCTION_FN_ARGS )
{
    ssize_t offset = istate.code[istate.ip+1].ssizeval;

    TRACE_FUNCTION();

    istate.ep --;
    STACKCELL_SET_ADDR( istate.ep[0], &(istate.fp[offset].PTR) );

    return 2;
}

/*
 PST (store variable)

 bytcode:
 PST offset

 stack:
 value --> 

 'offset' identifies local variable relative to 'istate.fp', and the value from
 stack is stored to this offset.

*/

int PST( INSTRUCTION_FN_ARGS )
{
    ssize_t offset = istate.code[istate.ip+1].ssizeval;

    TRACE_FUNCTION();

    STACKCELL_MOVE_PTR( istate.fp[offset], istate.ep[0] );
    STACKCELL_ZERO_PTR( istate.ep[0] );
    istate.ep ++;

    return 2;
}

/*
 PLDG (load global reference)

 bytcode:
 PLDG offset

 stack:
 --> value

 'offset' identifies a global variable relative to 'istate.gp', and
 the value of this variable is loaded onto the stack. The value is a
 reference to an allocated (and garbage-collectable) data block.
*/

int PLDG( INSTRUCTION_FN_ARGS )
{
    ssize_t offset = istate.code[istate.ip+1].ssizeval;

    TRACE_FUNCTION();

    istate.ep --;
    STACKCELL_MOVE_PTR( istate.ep[0], istate.gp[offset] );

    return 2;
}

/*
 PLDGA (load global reference-variable address)

 bytcode:
 PLDGA offset

 stack:
 --> value

 'offset' identifies a global variable relative to 'istate.gp', and
 the ADDRESS of this variable is loaded onto the stack.

*/

int PLDGA( INSTRUCTION_FN_ARGS )
{
    ssize_t offset = istate.code[istate.ip+1].ssizeval;

    TRACE_FUNCTION();

    istate.ep --;
    STACKCELL_SET_ADDR( istate.ep[0], &(istate.gp[offset].PTR) );

    return 2;
}

/*
 PSTG (store global reference variable)

 bytcode:
 PSTG offset

 stack:
 reference-value --> 

 'offset' identifies a global variable relative to 'istate.gp', and
 the reference value from stack is stored to this offset.

*/

int PSTG( INSTRUCTION_FN_ARGS )
{
    ssize_t offset = istate.code[istate.ip+1].ssizeval;

    TRACE_FUNCTION();

    STACKCELL_MOVE_PTR( istate.gp[offset], istate.ep[0] );
    STACKCELL_ZERO_PTR( istate.ep[0] );
    istate.ep ++;

    return 2;
}

/*
 * PLDI (pointer load indirect)
 * 
 * pointer address --> pointer
 *
 */

int PLDI( INSTRUCTION_FN_ARGS )
{
    void *addr;

    TRACE_FUNCTION();

    addr = *((void**)STACKCELL_PTR(istate.ep[0]));
    STACKCELL_SET_ADDR( istate.ep[0], addr );

    return 1;
}

/*
 PSTI (pointer store indirect)
 
 pointer address, pointer value --> 
 
 */

int PSTI( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    *((void**)STACKCELL_PTR(istate.ep[1])) = STACKCELL_PTR( istate.ep[0] );
    STACKCELL_ZERO_PTR( istate.ep[1] );
    STACKCELL_ZERO_PTR( istate.ep[0] );

    istate.ep += 2;

    return 1;
}

/*
 PJZ (jump if pointer is zero)

 bytecode:
 PJZ offset

 stack:
 tested_value --> 
 
 Perform jump if the pointer value on the top of stack is NULL;
 otherwise proceed to the next instruction.
 */

int PJZ( INSTRUCTION_FN_ARGS )
{
    void *ptr = STACKCELL_PTR( *istate.ep );

    TRACE_FUNCTION();

    STACKCELL_ZERO_PTR( *istate.ep );
    istate.ep++;

    if( ptr == NULL ) {
	istate.ip += istate.code[istate.ip+1].ssizeval;
	return 0;
    } else {
	return 2;
    }
}

/*
 PJNZ (jump if pointer not zero)

 bytecode:
 PJNZ offset

 stack:
 tested_value --> 
 
 Perform jump if the pointer value on the top of stack is not NULL;
 otherwise proceed to the next instruction.
 */

int PJNZ( INSTRUCTION_FN_ARGS )
{
    void *ptr = STACKCELL_PTR( *istate.ep );

    TRACE_FUNCTION();

    STACKCELL_ZERO_PTR( *istate.ep );
    istate.ep++;

    if( ptr != NULL ) {
	istate.ip += istate.code[istate.ip+1].ssizeval;
	return 0;
    } else {
	return 2;
    }
}

/*
** Character processing opcodes that should be probably made from
** integer.cin.
*/

/*
 CLDI (load indirect)
 
 address --> value
 
*/

int CLDI( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    istate.ep[0].num.c = *((char*)STACKCELL_PTR(istate.ep[0]));
    STACKCELL_ZERO_PTR( istate.ep[0] );

    return 1;
}

/*
 * CPRINT (print character value from the top of stack)
 * 
 * bytecode:
 * CPRINT
 * 
 * stack:
 * value -->
 * 
 * Print a char value from the top of stack and remove it.
 */

int CPRINT( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    printf( "%c", istate.ep[0].num.c );
    istate.ep ++;

    return 1;
}

/*
 CLDCS (load character constant)

 bytcode:
 CLDCS static_string_offset

 stack:
 --> char

 'static_string_offset', an offset into istate.static_data, is taken
 from the bytecode and a character at this offset is loaded onto the
 stack.

 */

int CLDCS( INSTRUCTION_FN_ARGS )
{
    ssize_t offset = istate.code[istate.ip+1].ssizeval;
    char *str;

    TRACE_FUNCTION();

    istate.ep --;
    str = istate.static_data + offset;

    istate.ep[0].num.c = str[0];

    return 2;
}

/*
** Experimental opcodes for efficiency tests:
*/

/*
 * INDEXVAR Index array using index variable.
 *
 * bytecode:
 * INDEXVAR idxvar(i)
 *
 * stack:
 * array(m) -> indexed address (m + size * i)
 *
 */

int INDEXVAR( INSTRUCTION_FN_ARGS )
{
    alloccell_t *array_ptr = istate.ep[0].PTR;
    ssize_t element_size = array_ptr[-1].element_size;
    ssize_t idxvar = istate.code[istate.ip+1].ssizeval;
    int idx = istate.fp[idxvar].num.i;

    TRACE_FUNCTION();

    STACKCELL_OFFSET_PTR( istate.ep[0], idx * element_size );

    return 2;
}

/*
 * ILDXVAR Load integer using an index variable.
 *
 * bytecode:
 * ILDXVAR idxvar(i)
 *
 * stack:
 * array(m) -> indexed value (m[i])
 *
 */

int ILDXVAR( INSTRUCTION_FN_ARGS )
{
    ssize_t idxvar = istate.code[istate.ip+1].ssizeval;
    int idx = istate.fp[idxvar].num.i;

    TRACE_FUNCTION();

    istate.ep[0].num.i = ((int*)STACKCELL_PTR( istate.ep[0] ))[idx];
    STACKCELL_ZERO_PTR( istate.ep[0] );

    return 2;
}

/*
 * PLDXVAR2 Load pointer from indexed variable and index.
 *
 * bytecode:
 * PLDXVAR2 array(m) idxvar(i)
 *
 * stack:
 * -> indexed value (m[i])
 *
 */

int PLDXVAR2( INSTRUCTION_FN_ARGS )
{
    ssize_t arrayvar = istate.code[istate.ip+1].ssizeval;
    void** array = STACKCELL_PTR( istate.fp[arrayvar] );
    ssize_t idxvar = istate.code[istate.ip+2].ssizeval;
    int idx = istate.fp[idxvar].num.i;

    TRACE_FUNCTION();

    istate.ep --;
    STACKCELL_SET_ADDR( istate.ep[0], array[idx] );

    return 3;
}

int PEQBOOL( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    istate.ep[1].num.b =
	STACKCELL_PTR( istate.ep[1] ) == STACKCELL_PTR( istate.ep[0] );
    istate.ep ++;

    return 1;
}

int PNEBOOL( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    istate.ep[1].num.b =
	STACKCELL_PTR( istate.ep[1] ) != STACKCELL_PTR( istate.ep[0] );
    istate.ep ++;

    return 1;
}

int PZBOOL( INSTRUCTION_FN_ARGS )
{
    char result;

    TRACE_FUNCTION();

    result = (STACKCELL_PTR( istate.ep[0] ) == NULL);
    STACKCELL_ZERO_PTR( istate.ep[0] );
    istate.ep[0].num.b = result;

    return 1;
}

/*
 * STRCAT STRing conCATenate
 */

int STRCAT( INSTRUCTION_FN_ARGS )
{
    ssize_t len1, len2, length;
    char *str1, *str2;
    char *dst;

    TRACE_FUNCTION();

    str1 = STACKCELL_PTR( istate.ep[1] );
    str2 = STACKCELL_PTR( istate.ep[0] );

    len1 = str1 ? strlen( str1 ) : 0;
    len2 = str2 ? strlen( str2 ) : 0;
    length = len1 + len2;

    dst = bcalloc_array( 1, length + 1, 0 );
    BC_CHECK_PTR( dst );
    STACKCELL_SET_ADDR( istate.ep[1], dst );
    STACKCELL_ZERO_PTR( istate.ep[0] );

    if( str1 ) strcpy( dst, str1 );
    if( str2 ) strcat( dst, str2 );

    istate.ep ++;

    return 1;
}

/*
 * STRSTART Does a string start with the prefix 'start'? 
 *
 * bytecode:
 * STRSTART
 *
 * stack:
 * ..., start, string -> ..., bool
 */

int STRSTART( INSTRUCTION_FN_ARGS )
{
    char *start = STACKCELL_PTR( istate.ep[1] );
    char *str = STACKCELL_PTR( istate.ep[0] );

    TRACE_FUNCTION();

    STACKCELL_ZERO_PTR( istate.ep[0] );
    STACKCELL_ZERO_PTR( istate.ep[1] );

    istate.ep++;

    if( !start || !str ) {
	istate.ep[0].num.b = (start == str);
    } else {
	istate.ep[0].num.b =
            (strncmp( start, str, strlen( start )) == 0);
    }

    return 1;
}

/*
 * STREND Does a string end with the prefix 'start'? 
 *
 * bytecode:
 * STREND
 *
 * stack:
 * ..., end, string -> ..., bool
 */

int STREND( INSTRUCTION_FN_ARGS )
{
    char *strend = STACKCELL_PTR( istate.ep[1] );
    char *str = STACKCELL_PTR( istate.ep[0] );

    TRACE_FUNCTION();

    STACKCELL_ZERO_PTR( istate.ep[0] );
    STACKCELL_ZERO_PTR( istate.ep[1] );

    istate.ep++;

    if( !strend || !str ) {
	istate.ep[0].num.b = (strend == str);
    } else {
        ssize_t str_len = strlen( str );
        ssize_t strend_len = strlen( strend );

        if( strend_len > str_len ) { 
            /* suffix may not be longer than a string itself: */
            istate.ep[0].num.b = 0;
        } else {
            char *e1, *e2;

            e1 = str + str_len - 1;
            e2 = strend + strend_len - 1;

            istate.ep[0].num.b = 1;

            while( e1 >= str && e2 >= strend ) {
                if( *e1 != *e2 ) {
                    istate.ep[0].num.b = 0;
                    break;
                }
                e1--; e2--;
            }
        }
    }

    return 1;
}

/*
 * STREQ Are two strings equal? (as string values)
 *
 * bytecode:
 * STREQ
 *
 * stack:
 * ..., str1, str2 -> ..., bool
 */

int STREQ( INSTRUCTION_FN_ARGS )
{
    char *str1 = STACKCELL_PTR( istate.ep[1] );
    char *str2 = STACKCELL_PTR( istate.ep[0] );

    TRACE_FUNCTION();

    STACKCELL_ZERO_PTR( istate.ep[0] );
    STACKCELL_ZERO_PTR( istate.ep[1] );

    istate.ep++;

    if( !str1 || !str2 ) {
	istate.ep[0].num.b = (str1 == str2);
    } else {
	istate.ep[0].num.b = (strcmp( str1, str2 ) == 0);
    }

    return 1;
}

/*
 * STRNE Are two strings not equal? (as string values)
 *
 * bytecode:
 * STRNE
 *
 * stack:
 * ..., str1, str2 -> ..., bool
 */

int STRNE( INSTRUCTION_FN_ARGS )
{
    char *str1 = STACKCELL_PTR( istate.ep[1] );
    char *str2 = STACKCELL_PTR( istate.ep[0] );

    TRACE_FUNCTION();

    STACKCELL_ZERO_PTR( istate.ep[0] );
    STACKCELL_ZERO_PTR( istate.ep[1] );

    istate.ep++;

    if( !str1 || !str2 ) {
	istate.ep[0].num.b = (str1 != str2);
    } else {
	istate.ep[0].num.b = (strcmp( str1, str2 ) != 0);
    }

    return 1;
}

/*
 * STRGT Is string str1 lexicographically greater than str2?
 *
 * bytecode:
 * STRGT
 *
 * stack:
 * ..., str1, str2 -> ..., bool
 */

int STRGT( INSTRUCTION_FN_ARGS )
{
    char *str1 = STACKCELL_PTR( istate.ep[1] );
    char *str2 = STACKCELL_PTR( istate.ep[0] );

    TRACE_FUNCTION();

    STACKCELL_ZERO_PTR( istate.ep[0] );
    STACKCELL_ZERO_PTR( istate.ep[1] );

    istate.ep++;

    if( !str1 || !str2 ) {
	istate.ep[0].num.b = (str1 > str2);
    } else {
	istate.ep[0].num.b = (strcmp( str1, str2 ) > 0);
    }

    return 1;
}

/*
 * STRLT Is string str1 lexicographically less than str2?
 *
 * bytecode:
 * STRLT
 *
 * stack:
 * ..., str1, str2 -> ..., bool
 */

int STRLT( INSTRUCTION_FN_ARGS )
{
    char *str1 = STACKCELL_PTR( istate.ep[1] );
    char *str2 = STACKCELL_PTR( istate.ep[0] );

    TRACE_FUNCTION();

    STACKCELL_ZERO_PTR( istate.ep[0] );
    STACKCELL_ZERO_PTR( istate.ep[1] );

    istate.ep++;

    if( !str1 || !str2 ) {
	istate.ep[0].num.b = (str1 < str2);
    } else {
	istate.ep[0].num.b = (strcmp( str1, str2 ) < 0);
    }

    return 1;
}

/*
 * STRGE Is string str1 lexicographically greater than or equal to str2?
 *
 * bytecode:
 * STRGE
 *
 * stack:
 * ..., str1, str2 -> ..., bool
 */

int STRGE( INSTRUCTION_FN_ARGS )
{
    char *str1 = STACKCELL_PTR( istate.ep[1] );
    char *str2 = STACKCELL_PTR( istate.ep[0] );

    TRACE_FUNCTION();

    STACKCELL_ZERO_PTR( istate.ep[0] );
    STACKCELL_ZERO_PTR( istate.ep[1] );

    istate.ep++;

    if( !str1 || !str2 ) {
	istate.ep[0].num.b = (str1 >= str2);
    } else {
	istate.ep[0].num.b = (strcmp( str1, str2 ) >= 0);
    }

    return 1;
}

/*
 * STRLE Is string str1 lexicographically less than or equal to str2?
 *
 * bytecode:
 * STRLE
 *
 * stack:
 * ..., str1, str2 -> ..., bool
 */

int STRLE( INSTRUCTION_FN_ARGS )
{
    char *str1 = STACKCELL_PTR( istate.ep[1] );
    char *str2 = STACKCELL_PTR( istate.ep[0] );

    TRACE_FUNCTION();

    STACKCELL_ZERO_PTR( istate.ep[0] );
    STACKCELL_ZERO_PTR( istate.ep[1] );

    istate.ep++;

    if( !str1 || !str2 ) {
	istate.ep[0].num.b = (str1 <= str2);
    } else {
	istate.ep[0].num.b = (strcmp( str1, str2 ) <= 0);
    }

    return 1;
}

/*
 * STRLEN  Length of the string a-la C
 *
 * bytecode:
 * STRLEN
 *
 * stack:
 * ..., str -> ..., ssize_t
 */

int STRLEN( INSTRUCTION_FN_ARGS )
{
    char *str = STACKCELL_PTR( istate.ep[0] );
    alloccell_t *block = istate.ep[0].PTR;
    ssize_t size = block[-1].length;

    TRACE_FUNCTION();

    STACKCELL_ZERO_PTR( istate.ep[0] );

    if( !str ) {
	istate.ep[0].num.ssize = 0;
    } else {
        istate.ep[0].num.ssize = strnlen( str, size );
    }

    return 1;
}

/*
 * STRINDEX  Does one string contain another?
 *
 * bytecode:
 * STRINDEX
 *
 * stack:
 * ..., str1, str2 -> ..., ssize_t
 */

int STRINDEX( INSTRUCTION_FN_ARGS )
{
    char *str1 = STACKCELL_PTR( istate.ep[1] );
    char *str2 = STACKCELL_PTR( istate.ep[0] );
    char *idx;

    TRACE_FUNCTION();

    STACKCELL_ZERO_PTR( istate.ep[0] );
    STACKCELL_ZERO_PTR( istate.ep[1] );

    istate.ep++;

    if( !str1 || !str2 ) {
	istate.ep[0].num.ssize = -1;
    } else {
	idx = strstr( str1, str2 );
	if( !idx ) {
	    istate.ep[0].num.ssize = -1;
	} else {
	    istate.ep[0].num.ssize = idx - str1;
	}
    }

    return 1;
}


/*
 * STRCHR  Does a string contain a character?
 *
 * bytecode:
 * STRCHR
 *
 * stack:
 * ..., str, chr -> ..., ssize_t
 */

int STRCHR( INSTRUCTION_FN_ARGS )
{
    char *str = STACKCELL_PTR( istate.ep[1] );
    char chr = istate.ep[0].num.c;
    char *idx;

    TRACE_FUNCTION();

    STACKCELL_ZERO_PTR( istate.ep[0] );
    STACKCELL_ZERO_PTR( istate.ep[1] );

    istate.ep++;

    if( !str ) {
	istate.ep[0].num.ssize = -1;
    } else {
	idx = strchr( str, chr );
	if( !idx ) {
	    istate.ep[0].num.ssize = -1;
	} else {
	    istate.ep[0].num.ssize = idx - str;
	}
    }

    return 1;
}

/*
 * STRRCHR  Does a string contain a character? Finds the last occurence.
 *
 * bytecode:
 * STRRCHR
 *
 * stack:
 * ..., str, chr -> ..., ssize_t
 */

int STRRCHR( INSTRUCTION_FN_ARGS )
{
    char *str = STACKCELL_PTR( istate.ep[1] );
    char chr = istate.ep[0].num.c;
    char *idx;

    TRACE_FUNCTION();

    STACKCELL_ZERO_PTR( istate.ep[0] );
    STACKCELL_ZERO_PTR( istate.ep[1] );

    istate.ep++;

    if( !str ) {
	istate.ep[0].num.ssize = -1;
    } else {
	idx = strrchr( str, chr );
	if( !idx ) {
	    istate.ep[0].num.ssize = -1;
	} else {
	    istate.ep[0].num.ssize = idx - str;
	}
    }

    return 1;
}

/*
Perl hashing function, from http://www.perl.com/lpt/a/679 :

# Return the hashed value of a string: $hash = perlhash("key")
# (Defined by the PERL_HASH macro in hv.h)
sub perlhash
{
    $hash = 0;
    foreach (split //, shift) {
        $hash = $hash*33 + ord($_);
    }
    return $hash;
}
*/

static size_t hash_value( char *string )
{
    size_t val = 0;

    if( string ) {
	while( *string ) {
	    val = val * 33 + *string++;
	}
    }
    return val;
}

/*
 * HASHADDR 
 *
 * bytecode:
 * HASHADDR element_size
 *
 * stack:
 * ..., hash, string -> ..., adressof
 */

int HASHADDR( INSTRUCTION_FN_ARGS )
{
    ssize_t element_size = istate.code[istate.ip+1].ssizeval;
    char *key = STACKCELL_PTR( istate.ep[0] );
    void *hash_table = STACKCELL_PTR( istate.ep[1] );
    char **hash_keys = (char**)hash_table;
    ssize_t hash_length;
    ssize_t hash_index, current_index;
    char **current_hash_key;
    int all_searched = 0;

    TRACE_FUNCTION();

    if( !key || !hash_table ) {
	STACKCELL_ZERO_PTR( istate.ep[0] );
	memset( &istate.ep[1], '\0', sizeof( istate.ep[1] ));	
    } else {
	hash_length = ((alloccell_t*)hash_table)[-1].length;
	hash_index = hash_value( key ) % hash_length;

	current_index = hash_index;

	while( !all_searched ) {
	    current_hash_key = hash_keys + current_index;
	    if( !*current_hash_key || strcmp( key, *current_hash_key ) == 0 ) {
		break;
	    }
	    current_index = (current_index + 1) % hash_length;
	    if( current_index == hash_index ) {
		all_searched = 1;
	    }
	}
	if( all_searched ) {
	    interpret_raise_exception_with_bcalloc_message(
	        /* err_code = */ -1,
		/* message = */
		"hash table full",
		/* module_id = */ 0,
		/* exception_id = */
		SL_EXCEPTION_HASH_FULL,
		EXCEPTION );
	    return 0;
	} else {
            ssize_t hash_cells_offset = REF_SIZE * hash_length;
	    if( !*current_hash_key ) {
		*current_hash_key = key;
	    }

	    STACKCELL_SET_PTR( istate.ep[1], hash_table,
                               hash_cells_offset +
                               element_size * current_index );

	    STACKCELL_ZERO_PTR( istate.ep[0] );
	}
    }
    istate.ep ++;
    return 2;
}

/*
 * HASHVAL
 *
 * bytecode:
 * HASHVAL element_size
 *
 * stack:
 * ..., hash, string -> ..., value
 */

int HASHVAL( INSTRUCTION_FN_ARGS )
{
    ssize_t element_size = istate.code[istate.ip+1].ssizeval;
    char *key = STACKCELL_PTR( istate.ep[0] );
    void *hash_table = STACKCELL_PTR( istate.ep[1] );
    char **hash_keys = (char**)hash_table;
    ssize_t hash_length;
    ssize_t hash_index, current_index;
    char **current_hash_key;
    int all_searched = 0;

    TRACE_FUNCTION();

    assert( element_size >= 0 );
    assert( element_size <= sizeof(union stackunion) );

    if( !key || !hash_table ) {
	STACKCELL_ZERO_PTR( istate.ep[0] );
	memset( &istate.ep[1], '\0', sizeof( istate.ep[1] ));
    } else {
	hash_length = ((alloccell_t*)hash_table)[-1].length;
	hash_index = hash_value( key ) % hash_length;

	current_index = hash_index;

	while( !all_searched ) {
	    current_hash_key = hash_keys + current_index;
	    if( !*current_hash_key || strcmp( key, *current_hash_key ) == 0 ) {
		break;
	    }
	    current_index = (current_index + 1) % hash_length;
	    if( current_index == hash_index ) {
		all_searched = 1;
	    }
	}
	if( all_searched ) {
	    memset( &istate.ep[1], '\0', sizeof( istate.ep[1] ));
	} else {
	    if( *current_hash_key ) {
                char **hash_cells = (char**)hash_table + hash_length;
		memcpy( &istate.ep[1],
			(char*)hash_cells + current_index * element_size,
			element_size );
	    } else {
		memset( &istate.ep[1], '\0', sizeof( istate.ep[1] ));
	    }
	}
    }
    STACKCELL_ZERO_PTR( istate.ep[0] );
    istate.ep ++;
    return 2;
}

/*
 * HASHPTR
 *
 * bytecode:
 * HASHPTR
 *
 * stack:
 * ..., hash, string -> ..., ref_value
 */

int HASHPTR( INSTRUCTION_FN_ARGS )
{
    ssize_t element_size = REF_SIZE;
    char *key = STACKCELL_PTR( istate.ep[0] );
    void *hash_table = STACKCELL_PTR( istate.ep[1] );
    char **hash_keys = (char**)hash_table;
    ssize_t hash_length;
    ssize_t hash_index, current_index;
    char **current_hash_key;
    int all_searched = 0;

    TRACE_FUNCTION();

    assert( element_size >= 0 );
    assert( element_size <= sizeof(union stackunion) );

    if( !key || !hash_table ) {
	STACKCELL_ZERO_PTR( istate.ep[0] );
	memset( &istate.ep[1], '\0', sizeof( istate.ep[1] ));
    } else {
	hash_length = ((alloccell_t*)hash_table)[-1].length;
	hash_index = hash_value( key ) % hash_length;

	current_index = hash_index;

	while( !all_searched ) {
	    current_hash_key = hash_keys + current_index;
	    if( !*current_hash_key || strcmp( key, *current_hash_key ) == 0 ) {
		break;
	    }
	    current_index = (current_index + 1) % hash_length;
	    if( current_index == hash_index ) {
		all_searched = 1;
	    }
	}
	if( all_searched ) {
	    memset( &istate.ep[1], '\0', sizeof( istate.ep[1] ));
	} else {
	    if( *current_hash_key ) {
                char **hash_cells = (char**)hash_table + hash_length;
		void **ptr =
                    (void**)((char*)hash_cells + current_index * element_size);
		STACKCELL_SET_ADDR( istate.ep[1], *ptr );
	    } else {
		STACKCELL_ZERO_PTR( istate.ep[1] );
	    }
	}
    }
    STACKCELL_ZERO_PTR( istate.ep[0] );
    istate.ep ++;
    return 1;
}

/*
 * HASHDUMP
 *
 * bytecode:
 * HASHDUMP
 *
 * stack:
 * ..., hash -> ...
 */

int HASHDUMP( INSTRUCTION_FN_ARGS )
{
    void *hash_table = STACKCELL_PTR( istate.ep[0] );
    char **hash_keys = (char**)hash_table;
    alloccell_t *hash_header = &((alloccell_t*)hash_table)[-1];
    ssize_t hash_length = hash_header->length;
    ssize_t hash_nref = hash_header->nref;
    /* ssize_t element_size = hash_header->element_size; */
    char **hash_cells = hash_keys + hash_length;

    ssize_t i;

    for( i = 0; i < hash_length; i ++ ) {
        if( hash_nref > hash_length ) {
            printf( "%d: '%s' -> (%p) '%s'\n", i, hash_keys[i],
                    hash_cells[i], hash_cells[i] );
        } else {
            printf( "%d: '%s'\n", i, hash_keys[i] );
        }
    }

    STACKCELL_ZERO_PTR( istate.ep[0] );
    istate.ep ++;
    return 1;
}

/*
 * RAISE_TEST Raise test exception
 *
 * 
 */

int RAISE_TEST( INSTRUCTION_FN_ARGS )
{
    static struct {
	alloccell_t alloc_header;
	char text[20];
    } err_message = {
	{BC_MAGIC}
    };

    TRACE_FUNCTION();

    /* No need to adjust ep since it will be restored from exception
       structure anyway */
    strncpy( err_message.text, "test exception", sizeof( err_message.text ));
    interpret_raise_exception( /* err_code = */  1,
			       /* message = */   err_message.text,
			       /* module_id = */ 0,
			       /* exception_id = */
			       SL_EXCEPTION_TEST_EXCEPTION,
			       EXCEPTION );

    return 0;
}


/*
 * ESPRINT print a dump of the evalueation stack
 *
 * 
 */

int ESPRINT( INSTRUCTION_FN_ARGS )
{
    interpreter_print_eval_stack();
    return 1;
}

/*
 * SSPRINTF (String Print Formatted)
 * 
 * bytecode:
 * SSPRINTF
 * 
 * stack:
 * string --> string
 * 
 * Print a string value from the top of stack into a string, and
 * leave that string on the top of the stack
 */

int SSPRINTF( INSTRUCTION_FN_ARGS )
{
    char *format = STACKCELL_PTR(istate.ep[1]);
    char *str = STACKCELL_PTR(istate.ep[0]);
    char *buffer;
    ssize_t length;
    ssize_t needed;

    TRACE_FUNCTION();

    length = strlen( format ) + strlen( str ) + 1;

    buffer = bcalloc_blob( length + 1 );
    STACKCELL_SET_ADDR( istate.ep[1], buffer ); /* Prevent 'buffer' from
						   being garbage collected
						   upon realloc */

    if( buffer ) {
	needed = snprintf( buffer, length, format, str );
	if( needed > length - 1 ) {
	    buffer = bcrealloc_blob( buffer, needed + 1 );
	    if( buffer ) {
		snprintf( buffer, needed + 1, format, str );
	    }
	} else {
	    /* This code branch is not tested do far since I did not
	       had libc < 2.1 handy and was lasy to write my own
	       snprintf for testing purposes... S.G. */
	    while( needed < 0 ) {
		length *= 2;
		buffer = bcrealloc_blob( buffer, length );
		STACKCELL_SET_ADDR( istate.ep[1], buffer );
		if( buffer ) {
		    needed = snprintf( buffer, length, format, str );
		} else {
		    break;
		}
	    }
	}
    }

    BC_CHECK_PTR( buffer );
    STACKCELL_SET_ADDR( istate.ep[1], buffer );
    STACKCELL_ZERO_PTR( istate.ep[0] );

    istate.ep ++;

    return 1;
}

/*
 * Ad-hoc bytecode operators; they should be moved into the .so
 * libraries and modules when dynamic library loading is implemented.
 */

/*
 * ASWAPW swap bytes in words (i.e. two-byte blocks) of an array
 *
 * bytecode:
 * ASWAPW
 *
 * stack:
 * ..., array -> ...
 * 
 */

int ASWAPW( INSTRUCTION_FN_ARGS )
{
    unsigned char *array = istate.ep[0].PTR;
    alloccell_t *array_header = &((alloccell_t*)array)[-1];
    ssize_t array_size = array ? array_header->element_size : 0;
    ssize_t nwords = array_size / 2;
    ssize_t i;
    unsigned char tmp;

    for( i = 0; i < nwords; i++ ) {
	tmp = array[0];
	array[0] = array[1];
	array[1] = tmp;
	array += 2;
    }

    STACKCELL_ZERO_PTR( istate.ep[0] );
    istate.ep ++;

    return 1;
}

/*
 * ASWAPD swap bytes in double-words (i.e. four-byte blocks) of an array
 *
 * bytecode:
 * ASWAPD
 *
 * stack:
 * ..., array -> ...
 * 
 */

int ASWAPD( INSTRUCTION_FN_ARGS )
{
    unsigned char *array = istate.ep[0].PTR;
    alloccell_t *array_header = &((alloccell_t*)array)[-1];
    ssize_t array_size = array ? array_header->element_size : 0;
    ssize_t nwords = array_size / 4;
    ssize_t i;
    unsigned char tmp;

    for( i = 0; i < nwords; i++ ) {
	tmp = array[0];
	array[0] = array[3];
	array[3] = tmp;
	tmp = array[1];
	array[1] = array[2];
	array[2] = tmp;
	array += 4;
    }

    STACKCELL_ZERO_PTR( istate.ep[0] );
    istate.ep ++;

    return 1;
}

/*
 ZEROSTACK (enter function)

 bytecode:
 ZEROSTACK startoffset nvars

 stack:
 -->

 Zero out nvar stackcells, starting with offset, on the function
 parameter (call) stack.

 */

int ZEROSTACK( INSTRUCTION_FN_ARGS )
{
    ssize_t offset = istate.code[istate.ip+1].ssizeval;
    ssize_t nvars = istate.code[istate.ip+2].ssizeval;

    TRACE_FUNCTION();

    memset( istate.fp + offset, 0, sizeof(*istate.sp) * nvars );

    return 3;
}

static int
pack_string_value( void *str, char typechar, ssize_t size,
                   ssize_t *offset, byte *blob )
{
    char *value = *(char**)str;
    alloccell_t *blob_header = ((alloccell_t*)blob) - 1;

    assert( blob_header->magic == BC_MAGIC );

    if( blob_header->length < size + *offset ) {
	interpret_raise_exception_with_bcalloc_message
	    ( /* err_code = */ -1,
	      /* message = */
	      "attempting to pack values past the end of a blob",
	      /* module_id = */ 0,
	      /* exception_id = */ SL_EXCEPTION_BLOB_OVERFLOW,
	      EXCEPTION );
	return 0;
    }

    if( size <= 0 ) {
        size = strlen( value ) + 1;
    }

    switch( typechar ) {
    case 'c':
	memcpy( blob + *offset, value, size ); 
	break;
    case 'z':
    case 's':
	strncpy( (char*)blob + *offset, value, size ); 
        ((char*)blob)[*offset + size - 1] = '\0';
	break;
    default:
        interpret_raise_exception_with_bcalloc_message
	    ( /* err_code = */ -1,
	      /* message = */
	      (char*)
	      cxprintf( "unsupported pack type '%c' for type 'char *'",
			typechar ),
	      /* module_id = */ 0,
	      /* exception_id = */ SL_EXCEPTION_BLOB_BAD_DESCR,
	      EXCEPTION );        
	return 0;
        break;
    }

    *offset += size;

    return 1;
}

/*
 * STRPACK (pack a value into a blob (an unstructured array of bytes))
 * 
 * bytecode:
 * STRPACK
 * 
 * stack:
 * ..., blob, offset, description, value --> ...
 * 
 */

int STRPACK( INSTRUCTION_FN_ARGS )
{
    char *value = STACKCELL_PTR( istate.ep[0] );
    char *description = STACKCELL_PTR( istate.ep[1] );
    ssize_t offset = istate.ep[2].num.ssize;
    byte *blob = STACKCELL_PTR( istate.ep[3] );
    alloccell_t *blob_header = ((alloccell_t*)blob) - 1;
    char typechar;
    ssize_t size;

    TRACE_FUNCTION();

    assert( blob_header->magic == BC_MAGIC );

    if( !description ) {
	interpret_raise_exception_with_bcalloc_message
	    ( /* err_code = */ -1,
	      /* message = */ "pack description not specified",
	      /* module_id = */ 0,
	      /* exception_id = */ SL_EXCEPTION_BLOB_BAD_DESCR,
	      EXCEPTION );        
	return 0;
    }

    typechar = description[0];

    if( description[0] != '\0' && description[1] != '\0' ) {
        size = atol( description + 1 );
    } else {
        size = strlen( value ) + 1;
    }

    if( pack_value( &istate.ep[0].PTR, typechar, size, &offset, 
                    blob, pack_string_value, EXCEPTION ) == 0 ) {
	return 0;
    }

    istate.ep += 4;
    return 1;
}

/*
 * STRPACKARRAY (pack an array into a blob (an unstructured array of bytes))
 * 
 * bytecode:
 * STRPACKARRAY
 * 
 * stack:
 * ..., blob, offset, description, value --> ...
 * 
 */

int STRPACKARRAY( INSTRUCTION_FN_ARGS )
{
    void **array = STACKCELL_PTR( istate.ep[0] );
    char *description = STACKCELL_PTR( istate.ep[1] );
    ssize_t offset = istate.ep[2].num.ssize;
    byte *blob = STACKCELL_PTR( istate.ep[3] );
    alloccell_t *blob_header = ((alloccell_t*)blob) - 1;

    TRACE_FUNCTION();

    assert( blob_header->magic == BC_MAGIC );

    if( !description ) {
	interpret_raise_exception_with_bcalloc_message
	    ( /* err_code = */ -1,
	      /* message = */
	      "pack description not specified",
	      /* module_id = */ 0,
	      /* exception_id = */ SL_EXCEPTION_BLOB_BAD_DESCR,
	      EXCEPTION );        
	return 0;
    }

    if( !pack_array_values( blob, array, description, &offset,
                            pack_string_value, EXCEPTION )) {
	return 0;
    }

    STACKCELL_ZERO_PTR( istate.ep[0] ); /* zero array reference */
    STACKCELL_ZERO_PTR( istate.ep[1] ); /* zero descrition string reference */
    STACKCELL_ZERO_PTR( istate.ep[3] ); /* zero blob reference */
    istate.ep += 4;
    return 1;
}

/*
 * STRPACKMDARRAY (pack a multidimentional array into a blob)
 * 
 * bytecode:
 * STRPACKMDARRAY level
 * 
 * stack:
 * ..., blob, offset, description, md_array_value --> ...
 * 
 */

int STRPACKMDARRAY( INSTRUCTION_FN_ARGS )
{
    int level = istate.code[istate.ip+1].ssizeval - 1;

    void **array = STACKCELL_PTR( istate.ep[0] );
    char *description = STACKCELL_PTR( istate.ep[1] );
    ssize_t offset = istate.ep[2].num.ssize;
    byte *blob = STACKCELL_PTR( istate.ep[3] );
    alloccell_t *blob_header = ((alloccell_t*)blob) - 1;

    TRACE_FUNCTION();

    if( !blob ) {
	STACKCELL_ZERO_PTR( istate.ep[0] ); /* zero array reference */
	STACKCELL_ZERO_PTR( istate.ep[1] ); /* zero descrition string ref. */
	STACKCELL_ZERO_PTR( istate.ep[3] ); /* zero blob reference */
	istate.ep += 4;
	return 2;
    }

    assert( blob_header->magic == BC_MAGIC );

    if( !description ) {
	interpret_raise_exception_with_bcalloc_message
	    ( /* err_code = */ -1,
	      /* message = */
	      "pack description not specified",
	      /* module_id = */ 0,
	      /* exception_id = */ SL_EXCEPTION_BLOB_BAD_DESCR,
	      EXCEPTION );        
	return 0;
    }

    if( !pack_array_layer( blob, array, description, &offset,
                           level, pack_string_value, EXCEPTION )) {
	return 0;
    }

    STACKCELL_ZERO_PTR( istate.ep[0] ); /* zero array reference */
    STACKCELL_ZERO_PTR( istate.ep[1] ); /* zero descrition string reference */
    STACKCELL_ZERO_PTR( istate.ep[3] ); /* zero blob reference */
    istate.ep += 4;
    return 2;
}

static int
unpack_string_value( void *value_ptr, char typechar,
                     ssize_t size, ssize_t *offset, byte *blob,
                     cexception_t *ex )
{
    char *value;
    ssize_t length;

    alloccell_t *blob_header = ((alloccell_t*)blob) - 1;

    assert( blob_header->magic == BC_MAGIC );

    if( size <= 0 ) {
        length = strnlen( (char*)blob + *offset,
                          blob_header->length - *offset );
        size = length + 1;
    } else {
        length = size;
    }

    /* At this point, either size == length || size == length + 1 */

    if( blob_header->length < length + *offset ||
        blob_header->length <= *offset ) {
	interpret_raise_exception_with_bcalloc_message
	    ( /* err_code = */ -1,
	      /* message = */
	      "attempting to unpack values past the end of a blob",
	      /* module_id = */ 0,
	      /* exception_id = */ SL_EXCEPTION_BLOB_OVERFLOW,
	      ex );
	return 0;
    }

    value = bcalloc_array( size + 1, size + 1, 0 );
    if( !value ) return 0;

    /* STACKCELL_SET_ADDR( *stackcell, value ); */
    *(char**)value_ptr = value;

    switch( typechar ) {
    case 'c':
    case 'z':
    case 's':
	strncpy( value, (char*)blob + *offset, length );
        break;
    default:
        interpret_raise_exception_with_bcalloc_message
	    ( /* err_code = */ -1,
	      /* message = */
	      (char*)
	      cxprintf( "unsupported unpack type '%c' for type 'char *'",
			typechar ),
	      /* module_id = */ 0,
	      /* exception_id = */ SL_EXCEPTION_BLOB_BAD_DESCR,
	      ex );
	return 0;
        break;
    }

    value[size] = '\0';
    *offset += size;

    return 1;
}

/*
 * STRUNPACK (unpack a value from a blob )
 * 
 * bytecode:
 * STRUNPACK
 * 
 * stack:
 * blob, offset, description --> value
 * 
 */

int STRUNPACK( INSTRUCTION_FN_ARGS )
{
    char *description = STACKCELL_PTR( istate.ep[0] );
    ssize_t size;
    char typechar;
    ssize_t offset = istate.ep[1].num.ssize;
    byte *blob = STACKCELL_PTR( istate.ep[2] );
    alloccell_t *blob_header = ((alloccell_t*)blob) - 1;

    TRACE_FUNCTION();

    assert( blob_header->magic == BC_MAGIC );

    if( !description ) {
	interpret_raise_exception_with_bcalloc_message
	    ( /* err_code = */ -1,
	      /* message = */
	      "unpack description not specified",
	      /* module_id = */ 0,
	      /* exception_id = */ SL_EXCEPTION_BLOB_BAD_DESCR,
	      EXCEPTION );
	return 0;
    }

    typechar = description[0];

    if( description[0] != '\0' && description[1] != '\0' ) {
        size = atol( description + 1 );
    } else {
	size = 0; /* The string value unpacker will determine string
                     length itself. */
    }

    if( unpack_value( (void*)&istate.ep[2].ptr, typechar, size, &offset, blob,
                      unpack_string_value, EXCEPTION ) == 0 ) {
	return 0;
    }

    STACKCELL_ZERO_PTR( istate.ep[0] );

    istate.ep += 2;

    return 1;
}

/*
 * STRUNPACKARRAY (unpack an array of values from a blob )
 * 
 * bytecode:
 * STRUNPACKARRAY
 * 
 * stack:
 * blob, offset, description --> array_value
 * 
 */

int STRUNPACKARRAY( INSTRUCTION_FN_ARGS )
{
    char *description = STACKCELL_PTR( istate.ep[0] );
    ssize_t offset = istate.ep[1].num.ssize;
    byte *blob = STACKCELL_PTR( istate.ep[2] );
    alloccell_t *blob_header = ((alloccell_t*)blob) - 1;

    TRACE_FUNCTION();

    assert( blob_header->magic == BC_MAGIC );

    if( !description ) {
	interpret_raise_exception_with_bcalloc_message
	    ( /* err_code = */ -1,
	      /* message = */
	      "unpack description not specified",
	      /* module_id = */ 0,
	      /* exception_id = */ SL_EXCEPTION_BLOB_BAD_DESCR,
	      EXCEPTION );
        return 0;
    }

    STACKCELL_SET_ADDR(istate.ep[1], STACKCELL_PTR( istate.ep[2] ));

    if( !unpack_array_values( blob, &istate.ep[2].ptr,
                              /* element_size = */ sizeof(char*),
                              /* element_nref = */ 1,
                              description, &offset, unpack_string_value,
                              EXCEPTION )) {
        return 0;
    }

    STACKCELL_ZERO_PTR( istate.ep[1] );
    STACKCELL_ZERO_PTR( istate.ep[0] );

    istate.ep += 2;

    return 1;
}

/*
 * STRUNPACKMDARRAY (unpack an array of values from a blob )
 * 
 * bytecode:
 * STRUNPACKMDARRAY level
 * 
 * stack:
 * dstptr, blob, offset, description --> dstptr
 * 
 */

int STRUNPACKMDARRAY( INSTRUCTION_FN_ARGS )
{
    int level = istate.code[istate.ip+1].ssizeval;

    char *description = STACKCELL_PTR( istate.ep[0] );
    ssize_t offset = istate.ep[1].num.ssize;
    byte *blob = STACKCELL_PTR( istate.ep[2] );

    TRACE_FUNCTION();

    if( !description ) {
	interpret_raise_exception_with_bcalloc_message
	    ( /* err_code = */ -1,
	      /* message = */ "unpack description not specified",
	      /* module_id = */ 0,
	      /* exception_id = */ SL_EXCEPTION_BLOB_BAD_DESCR,
	      EXCEPTION );        
    }

    if( !unpack_array_layer( blob, &istate.ep[3].ptr,
                             /* element_nref = */ sizeof(char*),
                             /* element_nref = */ 1,
                             description, &offset, level, unpack_string_value,
                             EXCEPTION )) {
        return 0;
    }

    STACKCELL_ZERO_PTR( istate.ep[2] );
    STACKCELL_ZERO_PTR( istate.ep[1] );
    STACKCELL_ZERO_PTR( istate.ep[0] );

    istate.ep += 3;

    return 2;
}

/*
 * CHECKREF Check reference on the top of the stack and raise
 * exception if it is null:
 * 
 * bytecode:
 * CHECKREF
 * 
 * stack:
 * ref -> same_ref
 */

int CHECKREF( INSTRUCTION_FN_ARGS )
{
    void *ref = STACKCELL_PTR( istate.ep[0] );

    if( !ref ) {
	interpret_raise_exception_with_bcalloc_message
            ( /* err_code = */ -98,
              /* message = */
              "reference was checked for nullity and found null",
              /* module_id = */ 0,
              /* exception_id = */
              SL_EXCEPTION_NULL_ERROR,
              EXCEPTION );
        
    }

    return 1;
}

/*
 * FILLARRAY Fill array with a specified value.
 * 
 * bytecode:
 * FILLARRAY
 * 
 * stack:
 * value, array_ref ->
 */

int FILLARRAY( INSTRUCTION_FN_ARGS )
{
    void* array_ref = STACKCELL_PTR( istate.ep[0] );
    alloccell_t *array_hdr = (alloccell_t*)array_ref - 1;
    stackcell_t value = istate.ep[1];
    ssize_t length, el_size, i;

    TRACE_FUNCTION();

    if( !array_ref ) {
        STACKCELL_ZERO_PTR( istate.ep[0] );
        STACKCELL_ZERO_PTR( istate.ep[1] );
        istate.ep ++;
        return 0;
    }

    length = array_hdr->length;
    el_size = array_hdr->element_size;

    if( array_hdr->nref == 0 ) {
        for( i = 0; i < length; i++ ) {
            memcpy( (char*)array_ref + i * el_size, &value.num, el_size );
        }
    } else {
        for( i = 0; i < length; i++ ) {
            ((void**)array_ref)[i] = value.PTR;
        }
    }

    STACKCELL_ZERO_PTR( istate.ep[0] );
    STACKCELL_SET_ADDR( istate.ep[1], array_ref );

    istate.ep ++;

    return 1;
}

/*
 * FILLMDARRAY Fill multidimensional array with a specified value.
 * 
 * bytecode:
 * FILLMDARRAY level
 * 
 * stack:
 * value, array_ref ->
 */

static int
fill_md_array( void **array_ref, ssize_t level, stackcell_t *value )
{
    alloccell_t *array_hdr = (alloccell_t*)array_ref - 1;
    ssize_t length = array_hdr->length;
    ssize_t i;

    if( level == 0 ) {
        if( array_hdr->nref == 0 ) {
            ssize_t el_size = array_hdr->element_size;
            for( i = 0; i < length; i++ ) {
                memcpy( (char*)array_ref + i * el_size, &value->num, el_size );
            }
        } else {
            assert( array_hdr->nref == array_hdr->length );
            assert( array_hdr->nref >= 0 );
            for( i = 0; i < length; i++ ) {
                array_ref[i] = value->PTR;
            }
        }
    } else {
        for( i = 0; i < length; i++ ) {
            fill_md_array( array_ref[i], level-1, value );
        }
    }

    return 0;
}

int FILLMDARRAY( INSTRUCTION_FN_ARGS )
{
    void **array_ref = STACKCELL_PTR( istate.ep[0] );
    stackcell_t value = istate.ep[1];
    int level = istate.code[istate.ip+1].ssizeval;

    TRACE_FUNCTION();

    if( !array_ref ) {
        STACKCELL_ZERO_PTR( istate.ep[0] );
        STACKCELL_ZERO_PTR( istate.ep[1] );
        istate.ep ++;
        return 0;
    }

    fill_md_array( array_ref, level, &value );

    STACKCELL_ZERO_PTR( istate.ep[0] );
    STACKCELL_SET_ADDR( istate.ep[1], array_ref );

    istate.ep ++;

    return 2;
}

int ASSERT( INSTRUCTION_FN_ARGS )
{
    int assertion_ok = istate.ep[0].num.b;
    ssize_t line_no = istate.code[istate.ip+1].ssizeval;
    char *filename = istate.static_data + istate.code[istate.ip+2].ssizeval;
    char *message = istate.static_data + istate.code[istate.ip+3].ssizeval;

    if( !assertion_ok ) {
        fprintf( stderr, "Assertion '%s' failed: line %d, file '%s'\n",
                 message, line_no, filename );
    }

    istate.ep ++;

    return 4;
}


/*
 * DEBUG Does nothing but provides convenient points to insert
 *       debugger breakpoints into the bytecode.
 * 
 * bytecode:
 * DEBUG
 * 
 * stack:
 * ... -> ...
 */

int DEBUG( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();
    return 1;
}

/*
 * RTTIDUMP Print out the RTTI information left by compiler.
 * 
 * bytecode:
 * RTTY
 * 
 * stack:
 * type_of_var -> 
 */

int RTTIDUMP( INSTRUCTION_FN_ARGS )
{
    rtti_t *type_descr = STACKCELL_PTR( istate.ep[0] );

    TRACE_FUNCTION();

    if( type_descr ) {
        printf( "RTTIDUMP: size = %d, nref = %d\n",
                type_descr->size, type_descr->nref );
    } else {
        printf( "RTTIDUMP: null type descriptor\n" );
    }

    STACKCELL_ZERO_PTR( istate.ep[0] );
    istate.ep ++;
    return 1;
}
