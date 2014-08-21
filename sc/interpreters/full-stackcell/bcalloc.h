/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

#ifndef __BCALLOC_H
#define __BCALLOC_H

#include <stdlib.h>
#include <stackcell.h>
#include <cexceptions.h>

/* Garbage collector invocation policy: how often should garbage
   collector be involved: */

typedef enum {
    GC_ON_LIMIT_HIT, /* Invoke garbage collector when a dynamic limit is hit */
    GC_ALWAYS,       /* Invoke garbage collector before each allocation */
    GC_NEVER,        /* Never invoke the garbage collector */
    last_GC_POLICY,
} gc_policy_t;

void bcalloc_set_gc_collector_policy( gc_policy_t new_policy );
gc_policy_t bcalloc_gc_collector_policy( void );
void bc_merror( cexception_t *ex );
void *bcalloc( size_t size, ssize_t length, ssize_t nref );
void *bcalloc_blob( size_t size );
char* bcstrdup( char *str );
void *bcalloc_stackcells( ssize_t length, ssize_t nref );
void *bcalloc_array( size_t element_size, ssize_t length, ssize_t nref );
void *bcrealloc_blob( void *memory, size_t size );
ssize_t bccollect( void );
void *bcalloc_stackcell_layer( stackcell_t *array, ssize_t length,
                               ssize_t nref, int level );

int bcalloc_is_in_heap( void *p );
void bcalloc_reset_allocated_nodes( void );

#endif
