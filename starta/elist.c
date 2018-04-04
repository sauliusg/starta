/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

/* exports: */
#include <elist.h>

/* uses: */
#include <sllist.h>

void delete_elist( ELIST *list )
{
    delete_sllist( (SLLIST*)list );
}

ELIST* new_elist( ENODE *enode,
                  enode_delete_function_t delete_fn,
                  ELIST *next,
                  cexception_t *ex )
{
    return (ELIST*)new_sllist( enode, (break_cycle_function_t)NULL,
                               (delete_function_t) delete_fn,
                               (SLLIST*) next, ex );
}

void create_elist( ELIST * volatile *list,
                   ENODE * volatile *data,
                   enode_dispose_function_t dispose_fn,
                   ELIST *next, cexception_t *ex )
{
    create_sllist( (SLLIST * volatile *)list,
		   (void * volatile *)data,
                   (break_cycle_function_t)NULL,
		   (dispose_function_t) dispose_fn,
		   (SLLIST*) next, ex );
}

void dispose_elist( ELIST* volatile *list )
{
    dispose_sllist( (SLLIST* volatile *)list );
}

ENODE* elist_data( ELIST *list )
{
    return (ENODE*) sllist_data( (SLLIST *)list );
}

ENODE* elist_extract_data( ELIST *list )
{
    return (ENODE*) sllist_extract_data( (SLLIST *)list );
}

void elist_set_data( ELIST *list, ENODE * volatile *code )
{
    sllist_set_data( (SLLIST *)list, (void * volatile*)code );
}

ELIST* elist_next( ELIST *list )
{
    return (ELIST*) sllist_next( (SLLIST *)list );
}

void elist_disconnect( ELIST *list )
{
    sllist_disconnect( (SLLIST *)list );
}

void elist_push( ELIST *volatile *list,
		   ELIST *volatile *node,
		   cexception_t *ex )
{
    sllist_push( (SLLIST *volatile *)list,
		 (SLLIST *volatile *)node,
		 ex );
}

void elist_push_data( ELIST *volatile *list,
			ENODE *volatile *data,
			enode_delete_function_t delete_fn,
			enode_dispose_function_t dispose_fn,
			cexception_t *ex )
{
    sllist_push_data( (SLLIST *volatile *)list,
		      (void *volatile *)data,
                      (break_cycle_function_t)NULL,
		      (delete_function_t) delete_fn,
		      (dispose_function_t) dispose_fn,
		      ex );
}

ELIST* elist_pop( ELIST * volatile *list )
{
    return (ELIST*) sllist_pop( (SLLIST * volatile *)list );
}

ENODE* elist_pop_data( ELIST * volatile *list )
{
    return (ENODE*) sllist_pop_data( (SLLIST * volatile *)list );
}

void elist_drop( ELIST * volatile *list )
{
    sllist_drop( (SLLIST * volatile *)list );
}

void elist_swap( ELIST * volatile *list )
{
    sllist_swap( (SLLIST * volatile *)list );
}
