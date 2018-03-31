/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

/* exports: */
#include <thrlist.h>

/* uses: */
#include <sllist.h>

void delete_thrlist( THRLIST *list )
{
#ifdef ALLOCX_DEBUG_COUNTS
    checkptr( list );
#endif
    delete_sllist( (SLLIST*)list );
}

THRLIST* new_thrlist( THRCODE *thrcode,
		      thrcode_delete_function_t delete_fn,
		      THRLIST *next,
		      cexception_t *ex )
{
    return (THRLIST*)new_sllist( thrcode, (delete_function_t) delete_fn,
				 (SLLIST*) next, ex );
}

void create_thrlist( THRLIST * volatile *list,
		     THRCODE * volatile *data,
		     thrcode_dispose_function_t dispose_fn,
		     THRLIST *next, cexception_t *ex )
{
#ifdef ALLOCX_DEBUG_COUNTS
    checkptr( data );
#endif
    create_sllist( (SLLIST * volatile *)list,
		   (void * volatile *)data,
		   (dispose_function_t) dispose_fn,
		   (SLLIST*) next, ex );
}

void dispose_thrlist( THRLIST* volatile *list )
{
    dispose_sllist( (SLLIST* volatile *)list );
}

THRCODE* thrlist_data( THRLIST *list )
{
#ifdef ALLOCX_DEBUG_COUNTS
    checkptr( list );
#endif
    return (THRCODE*) sllist_data( (SLLIST *)list );
}

THRCODE* thrlist_extract_data( THRLIST *list )
{
    return (THRCODE*) sllist_extract_data( (SLLIST *)list );
}

void thrlist_set_data( THRLIST *list, THRCODE * volatile *code )
{
    sllist_set_data( (SLLIST *)list, (void * volatile*)code );
}

THRLIST* thrlist_next( THRLIST *list )
{
    return (THRLIST*) sllist_next( (SLLIST *)list );
}

void thrlist_disconnect( THRLIST *list )
{
    sllist_disconnect( (SLLIST *)list );
}

void thrlist_push( THRLIST *volatile *list,
		   THRLIST *volatile *node,
		   cexception_t *ex )
{
    sllist_push( (SLLIST *volatile *)list,
		 (SLLIST *volatile *)node,
		 ex );
}

void thrlist_push_data( THRLIST *volatile *list,
			THRCODE *volatile *data,
			thrcode_delete_function_t delete_fn,
			thrcode_dispose_function_t dispose_fn,
			cexception_t *ex )
{
    sllist_push_data( (SLLIST *volatile *)list,
		      (void *volatile *)data,
		      (delete_function_t) delete_fn,
		      (dispose_function_t) dispose_fn,
		      ex );
}

THRLIST* thrlist_pop( THRLIST * volatile *list )
{
    return (THRLIST*) sllist_pop( (SLLIST * volatile *)list );
}

THRCODE* thrlist_pop_data( THRLIST * volatile *list )
{
    return (THRCODE*) sllist_pop_data( (SLLIST * volatile *)list );
}

void thrlist_drop( THRLIST * volatile *list )
{
    sllist_drop( (SLLIST * volatile *)list );
}

void thrlist_swap( THRLIST * volatile *list )
{
    sllist_swap( (SLLIST * volatile *)list );
}
