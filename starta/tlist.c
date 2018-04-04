/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

/* exports: */
#include <tlist.h>

/* uses: */
#include <sllist.h>

void delete_tlist( TLIST *list )
{
    delete_sllist( (SLLIST*)list );
}

TLIST* new_tlist( TNODE *tnode,
                  TLIST *next,
                  cexception_t *ex )
{
    return (TLIST*)new_sllist( tnode, (delete_function_t) delete_tnode,
                               (SLLIST*) next, ex );
}

void create_tlist( TLIST * volatile *list,
                   TNODE * volatile *data,
                   TLIST *next, cexception_t *ex )
{
    create_sllist( (SLLIST * volatile *)list,
		   (void * volatile *)data,
		   (dispose_function_t) dispose_tnode,
		   (SLLIST*) next, ex );
}

void dispose_tlist( TLIST* volatile *list )
{
    dispose_sllist( (SLLIST* volatile *)list );
}

TNODE* tlist_data( TLIST *list )
{
    return (TNODE*) sllist_data( (SLLIST *)list );
}

TNODE* tlist_extract_data( TLIST *list )
{
    return (TNODE*) sllist_extract_data( (SLLIST *)list );
}

void tlist_set_data( TLIST *list, TNODE * volatile *code )
{
    sllist_set_data( (SLLIST *)list, (void * volatile*)code );
}

TLIST* tlist_next( TLIST *list )
{
    return (TLIST*) sllist_next( (SLLIST *)list );
}

void tlist_disconnect( TLIST *list )
{
    sllist_disconnect( (SLLIST *)list );
}

void tlist_push( TLIST *volatile *list,
		   TLIST *volatile *node,
		   cexception_t *ex )
{
    sllist_push( (SLLIST *volatile *)list,
		 (SLLIST *volatile *)node,
		 ex );
}

void tlist_push_data( TLIST *volatile *list,
			TNODE *volatile *data,
			tnode_delete_function_t delete_fn,
			tnode_dispose_function_t dispose_fn,
			cexception_t *ex )
{
    sllist_push_data( (SLLIST *volatile *)list,
		      (void *volatile *)data,
		      (delete_function_t) delete_fn,
		      (dispose_function_t) dispose_fn,
		      ex );
}

void tlist_push_tnode( TLIST *volatile *list,
		      TNODE *volatile *data,
		      cexception_t *ex )
{
    sllist_push_data( (SLLIST *volatile *)list,
		      (void *volatile *)data,
		      (delete_function_t) delete_tnode,
		      NULL,
		      ex );
}

TLIST* tlist_pop( TLIST * volatile *list )
{
    return (TLIST*) sllist_pop( (SLLIST * volatile *)list );
}

TNODE* tlist_pop_data( TLIST * volatile *list )
{
    return (TNODE*) sllist_pop_data( (SLLIST * volatile *)list );
}

void tlist_drop( TLIST * volatile *list )
{
    sllist_drop( (SLLIST * volatile *)list );
}

void tlist_swap( TLIST * volatile *list )
{
    sllist_swap( (SLLIST * volatile *)list );
}
