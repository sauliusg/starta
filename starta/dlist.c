/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

/* exports: */
#include <dlist.h>

/* uses: */
#include <sllist.h>

void delete_dlist( DLIST *list )
{
    delete_sllist( (SLLIST*)list );
}

DLIST* new_dlist( DNODE *dnode,
                  DLIST *next,
                  cexception_t *ex )
{
    return (DLIST*)new_sllist( dnode, (delete_function_t) delete_dnode,
                               (SLLIST*) next, ex );
}

void create_dlist( DLIST * volatile *list,
                   DNODE * volatile *data,
                   DLIST *next, cexception_t *ex )
{
    create_sllist( (SLLIST * volatile *)list,
		   (void * volatile *)data,
		   (dispose_function_t) dispose_dnode,
		   (SLLIST*) next, ex );
}

void dispose_dlist( DLIST* volatile *list )
{
    dispose_sllist( (SLLIST* volatile *)list );
}

DNODE* dlist_data( DLIST *list )
{
    return (DNODE*) sllist_data( (SLLIST *)list );
}

DNODE* dlist_extract_data( DLIST *list )
{
    return (DNODE*) sllist_extract_data( (SLLIST *)list );
}

void dlist_set_data( DLIST *list, DNODE * volatile *code )
{
    sllist_set_data( (SLLIST *)list, (void * volatile*)code );
}

DLIST* dlist_next( DLIST *list )
{
    return (DLIST*) sllist_next( (SLLIST *)list );
}

void dlist_disconnect( DLIST *list )
{
    sllist_disconnect( (SLLIST *)list );
}

void dlist_push( DLIST *volatile *list,
		   DLIST *volatile *node,
		   cexception_t *ex )
{
    sllist_push( (SLLIST *volatile *)list,
		 (SLLIST *volatile *)node,
		 ex );
}

void dlist_push_data( DLIST *volatile *list,
			DNODE *volatile *data,
			dnode_delete_function_t delete_fn,
			dnode_dispose_function_t dispose_fn,
			cexception_t *ex )
{
    sllist_push_data( (SLLIST *volatile *)list,
		      (void *volatile *)data,
		      (delete_function_t) delete_fn,
		      (dispose_function_t) dispose_fn,
		      ex );
}

void dlist_push_dnode( DLIST *volatile *list,
		      DNODE *volatile *data,
		      cexception_t *ex )
{
    sllist_push_data( (SLLIST *volatile *)list,
		      (void *volatile *)data,
		      (delete_function_t) delete_dnode,
		      NULL,
		      ex );
}

DLIST* dlist_pop( DLIST * volatile *list )
{
    return (DLIST*) sllist_pop( (SLLIST * volatile *)list );
}

DNODE* dlist_pop_data( DLIST * volatile *list )
{
    return (DNODE*) sllist_pop_data( (SLLIST * volatile *)list );
}

void dlist_drop( DLIST * volatile *list )
{
    sllist_drop( (SLLIST * volatile *)list );
}

void dlist_swap( DLIST * volatile *list )
{
    sllist_swap( (SLLIST * volatile *)list );
}
