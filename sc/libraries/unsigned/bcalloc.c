/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

/* exports: */
#include <bcalloc.h>

/* uses: */
#include <string.h>
#include <alloccell.h>
#include <refsize.h>
#include <run.h>
#include <opcodes.h>
#include <thrcode.h> /* for thrcode_heapdebug_is_on() */
#include <cexceptions.h>
#include <assert.h>

static alloccell_t *allocated = NULL;

static void *alloc_min, *alloc_max;

static ssize_t total_allocated_bytes = 0;
static ssize_t byte_allocation_limit = 0;

static gc_policy_t gc_policy = GC_ON_LIMIT_HIT;

void bcalloc_set_gc_collector_policy( gc_policy_t new_policy )
{
    gc_policy = new_policy;
}

gc_policy_t bcalloc_gc_collector_policy( void )
{
    return gc_policy;
}

void bc_merror( cexception_t *ex )
{
    interpret_raise_exception_with_static_message( INTERPRET_OUT_OF_MEMORY,
						   "could not allocate memory",
						   /*module*/ NULL,
						   SL_EXCEPTION_OUT_OF_MEMORY,
						   ex );
}

#if 0
static struct {
    alloccell_t alloc_header;
    char text[100];
} err_message = {
    {BC_MAGIC}
};
#endif

void *bcalloc( ssize_t size, ssize_t element_size,
               ssize_t length, ssize_t nref,
               cexception_t *ex )
{
    alloccell_t *ptr = NULL;
    // ssize_t size = (length < 0 ? 1 : length) * element_size;

    if( gc_policy != GC_NEVER ) {
	if( gc_policy == GC_ALWAYS ) {
	    thrcode_gc_mark_and_sweep( ex );
	} else {
	    if( total_allocated_bytes + size > byte_allocation_limit ) {
		thrcode_gc_mark_and_sweep( ex );
		byte_allocation_limit = (total_allocated_bytes + size) * 2;
	    }
	}
    }

    ptr = calloc( 1, sizeof(alloccell_t) + size );

    if( ptr && nref < 0 ) {
	ptr = (alloccell_t*)((void**)ptr + (-nref));
    }

    if( ptr != NULL ) {
	if( allocated )
	    allocated->prev = ptr;
	ptr->next = allocated;
	allocated = ptr;
	ptr->rcount = 1;
	ptr->magic = BC_MAGIC;
	ptr->size = size;
	ptr->element_size = element_size;
	ptr->length = length;
	ptr->nref = nref;
	total_allocated_bytes += size;
	if( !alloc_min || alloc_min > (void*)ptr )
	    alloc_min = ptr;
	if( !alloc_max || alloc_max < (void*)ptr + size + sizeof(ptr[0]) )
	    alloc_max = (void*)ptr + size + sizeof(ptr[0]);
	return &ptr[1];
    } else {
	return NULL;
    }
}

void *bcalloc_blob( size_t size, cexception_t *ex )
{
    return bcalloc_array( 1, size, 0, ex );
}

char* bcstrdup( char *str, cexception_t *ex )
{
    char *ptr = NULL;
    ssize_t len;

    if( str ) {
	len = strlen( str );
	ptr = bcalloc_array( sizeof(str[0]), len+1, 0, ex );
	if( ptr ) {
	    strcpy( ptr, str );
	}
    }
    return ptr;
}

void *bcalloc_array( size_t element_size, ssize_t length, ssize_t nref,
                     cexception_t *ex )
{
    alloccell_t *ptr;
    assert( nref == 1 || nref == 0 );
    ptr = bcalloc( element_size * length, element_size,
                   length, nref * length, ex );
    if( ptr && nref != 0 ) {
        ptr[-1].flags |= AF_HAS_REFS;
    }
    return ptr;
}

void *bcalloc_mdarray( void **array, ssize_t element_size,
		       ssize_t nref, ssize_t length, int level,
                       cexception_t *ex )
{
    if( level == 0 ) {
	return bcalloc_array( element_size, length, nref, ex );
    } else {
	alloccell_t *header = (alloccell_t*)array;
	ssize_t layer_len = header[-1].length;
	ssize_t i;

	if( !array ) {
	    return NULL;
	}

	for( i = 0; i < layer_len; i++ ) {
	    /* printf( ">>> allocating element %d of layer %d\n", i, level ); */
	    array[i] = bcalloc_mdarray( array[i], element_size, nref, length,
					level - 1, ex );
	    if( !array[i] ) {
		return NULL;
	    }
	}
    }
    return array;
}

/*
  WARNING!

  The bcrealloc_blob() function is inherently unsafe (as the realloc
  itself): if more references exist to the block being reallocated,
  all those references become invalid and the garbage collector will
  not be able to rectify this (acrtually, it will probably segfault).

  The only safe way to use bcrealloc_blob() is to make sure that the
  reference it gets is the only live reference to the datablock that
  exists. This is safe in functions that allocated a block of some
  default size, and then occasionally reallocate it to fit larger
  demand.

  It is *not* safe to reallocate a block that has already been
  returned to the interpreter system. In particular, the
  'bcrealloc_blob()' function should not be exposed via some sort of
  generic REALLOC opcode. Safe reallocs in the interpreter must either
  garbage-collect the reallocated block first (and take into account
  all references to the reallocated block), which may be very slow; or
  the interpreter realloc must always allocate a new copy of a larger
  block, which essentially makes it ALLOC or CLONE synonime.

  Saulius Grazulis
  2012.01.06
 */

void *bcrealloc_blob( void *memory, size_t size, cexception_t *ex )
{
    alloccell_t *ptr, *old;
    ssize_t old_size;

    if( !memory ) 
        return bcalloc_blob( size, ex );

    old = memory;
    old --;
    old_size = old->length;

    assert( old->magic == BC_MAGIC );
    assert( old == allocated || old->prev );
    assert( old->nref == 0 );

    if( old->next )
        old->next->prev = old->prev;
    if( old->prev )
        old->prev->next = old->next;
    if( allocated == old )
        allocated = old->next;

    ptr = realloc( old, sizeof(alloccell_t) + size );
    if( !ptr ) {
	/* GNU Linux Programmer's Manual, malloc(3): "If realloc()
           fails the original block is left untouched; it is not freed
           or moved." */
	old->next = allocated;
	allocated = old;
	return NULL;
    } else {
	total_allocated_bytes += size - old_size;
    }

    if( ptr != NULL ) {
	if( allocated )
	    allocated->prev = ptr;
	ptr->next = allocated;
	allocated = ptr;
	assert( ptr->magic == BC_MAGIC );
        ptr->size = size;
        ptr->length = size;
	if( !alloc_min || alloc_min > (void*)ptr )
	    alloc_min = ptr;
	if( !alloc_max || alloc_max < (void*)ptr + size + sizeof(ptr[0]) )
	    alloc_max = (void*)ptr + size + sizeof(ptr[0]);
	return &ptr[1];
    } else {
	return NULL;
    }
}

static void bcfree( void *mem )
{
    ssize_t nref;

    assert( ((alloccell_t*)mem)->magic == BC_MAGIC );
    ((alloccell_t*)mem)->magic = ~BC_MAGIC;

    nref = ((alloccell_t*)mem)->nref;

    if ( nref >= 0 ) {
	free( mem );
    } else {
	free( (void**)mem - (-nref) );
    }
}

#include <stdio.h>

ssize_t bccollect( cexception_t *ex )
{
    alloccell_t *curr, *prev, *next;
    ssize_t reclaimed = 0;

    prev = NULL;
    curr = allocated;

    while( curr != NULL ) {
        next = curr->next;
	/* printf( "%p %ld\n", curr, curr->rcount ); */
	if( thrcode_heapdebug_is_on()) {
	    if( (curr->flags & AF_USED) == 0 ) {
		printf( "collecting " );
	    } else {
		printf( "leaving    " );
	    }
	    printf( "%p (%p) (size = %ld bytes)\n",
                    curr, curr+1, (long)curr->size );
	}
        if( (curr->flags & AF_USED) == 0 ) {
	    if( curr != allocated ) {
	        prev->next = next;
		if( prev->next )
		    prev->next->prev = prev;
	    } else {
	        prev = allocated = next;
	    }
	    reclaimed += curr->size;
            thrcode_run_destructor_if_needed( istate_ptr, curr, ex );
	    bcfree( curr );
	} else {
	    curr->prev = prev;
	    prev = curr;
	}
        curr = next;
    }
    total_allocated_bytes -= reclaimed;
    if( total_allocated_bytes < 0 ) {
#if 0
        printf( ">>> total = %d, reclaimed = %d\n", total_allocated_bytes, reclaimed );
#endif
	assert( total_allocated_bytes >= 0 );
	total_allocated_bytes = 0;
    }
    return reclaimed;
}

void bcalloc_run_all_destructors( cexception_t *ex )
{
    alloccell_t *curr;
    alloccell_t *finalised;
    int i = 0;
    do {
        finalised = allocated; allocated = NULL;
        for( curr = finalised; curr != NULL; curr = curr->next ) {
            thrcode_run_destructor_if_needed( istate_ptr, curr, ex );
        }
        if( ++i >= 1000 ) {
            fprintf( stderr, "%d destructor cycles did not eliminte "
                     "unallocated objects -- bailing out...\n", i );
            fflush( NULL );
            exit( 98 );
        }
    } while( allocated );
}

int bcalloc_is_in_heap( void *p )
{
    return p >= alloc_min && p <= alloc_max;
}

void bcalloc_reset_allocated_nodes( void )
{
    alloccell_t *curr;

    for( curr = allocated; curr != NULL; curr = curr->next ) {
	curr->rcount = 0;
	curr->prev = NULL;
	curr->flags &= ~AF_USED;
    }
}
