/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

#ifndef __SLLIST_H
#define __SLLIST_H

#include <cexceptions.h>

typedef struct SLLIST SLLIST;

typedef void* (*share_function_t)( void* );
typedef void (*delete_function_t)( void* );
typedef void (*dispose_function_t)( void* volatile * );
typedef void* (*break_cycle_function_t)( void* );

#define foreach_sllist_node( NODE, LIST ) \
    for( (NODE) = (LIST); (NODE) != NULL; (NODE) = sllist_next(NODE) )

void delete_sllist( SLLIST *list );

void sllist_break_cycles( SLLIST *list );

SLLIST* new_sllist( void *data,
		    break_cycle_function_t break_cycles_fn,
		    delete_function_t delete_fn,
		    SLLIST *next,
		    cexception_t *ex );

SLLIST *share_sllist( SLLIST *list );

void create_sllist( SLLIST * volatile *list,
		    void * volatile *data,
		    break_cycle_function_t break_cycles_fn,
		    dispose_function_t dispose_fn,
		    SLLIST *next, cexception_t *ex );

void dispose_sllist( SLLIST* volatile *list );

void* sllist_data( SLLIST *list );

void* sllist_extract_data( SLLIST *list );

void sllist_set_data( SLLIST *list, void * volatile *data );

SLLIST* sllist_next( SLLIST *list );

void sllist_disconnect( SLLIST *list );

void sllist_push( SLLIST *volatile *list,
		  SLLIST *volatile *node,
		  cexception_t *ex );

void sllist_push_data( SLLIST *volatile *list,
		       void *volatile *data,
                       break_cycle_function_t break_cycles_fn,
		       delete_function_t delete_fn,
		       dispose_function_t dispose_fn,
		       cexception_t *ex );

void sllist_push_shared_data( SLLIST *volatile *list,
			      void *data,
                              break_cycle_function_t break_cycles_fn,
			      delete_function_t delete_fn,
			      dispose_function_t dispose_fn,
			      share_function_t share_fn,
			      cexception_t *ex );

SLLIST* sllist_pop( SLLIST * volatile *list );

void* sllist_pop_data( SLLIST * volatile *list );

void sllist_drop( SLLIST * volatile *list );

void sllist_swap( SLLIST * volatile *list );

#endif
