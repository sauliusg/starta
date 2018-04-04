/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

/* exports: */
#include <stlist.h>

/* uses: */
#include <sllist.h>

void delete_stlist( STLIST *list )
{
    delete_sllist( (SLLIST*)list );
}

STLIST* new_stlist( SYMTAB *symtab,
                    symtab_delete_function_t delete_fn,
                    STLIST *next,
                    cexception_t *ex )
{
    return (STLIST*)new_sllist( symtab, (break_cycle_function_t)NULL,
                                (delete_function_t) delete_fn,
                                (SLLIST*) next, ex );
}

void create_stlist( STLIST * volatile *list,
                    SYMTAB * volatile *data,
                    symtab_dispose_function_t dispose_fn,
                    STLIST *next, cexception_t *ex )
{
    create_sllist( (SLLIST * volatile *)list,
		   (void * volatile *)data,
                   (break_cycle_function_t)NULL,
		   (dispose_function_t) dispose_fn,
		   (SLLIST*) next, ex );
}

void dispose_stlist( STLIST* volatile *list )
{
    dispose_sllist( (SLLIST* volatile *)list );
}

SYMTAB* stlist_data( STLIST *list )
{
    return (SYMTAB*) sllist_data( (SLLIST *)list );
}

SYMTAB* stlist_extract_data( STLIST *list )
{
    return (SYMTAB*) sllist_extract_data( (SLLIST *)list );
}

void stlist_set_data( STLIST *list, SYMTAB * volatile *code )
{
    sllist_set_data( (SLLIST *)list, (void * volatile*)code );
}

STLIST* stlist_next( STLIST *list )
{
    return (STLIST*) sllist_next( (SLLIST *)list );
}

void stlist_disconnect( STLIST *list )
{
    sllist_disconnect( (SLLIST *)list );
}

void stlist_push( STLIST *volatile *list,
                  STLIST *volatile *node,
                  cexception_t *ex )
{
    sllist_push( (SLLIST *volatile *)list,
		 (SLLIST *volatile *)node,
		 ex );
}

void stlist_push_data( STLIST *volatile *list,
                       SYMTAB *volatile *data,
                       symtab_delete_function_t delete_fn,
                       symtab_dispose_function_t dispose_fn,
                       cexception_t *ex )
{
    sllist_push_data( (SLLIST *volatile *)list,
		      (void *volatile *)data,
                      (break_cycle_function_t)NULL,
		      (delete_function_t) delete_fn,
		      (dispose_function_t) dispose_fn,
		      ex );
}

void stlist_push_symtab( STLIST *volatile *list,
		      SYMTAB *volatile *data,
		      cexception_t *ex )
{
    sllist_push_data( (SLLIST *volatile *)list,
		      (void *volatile *)data,
                      (break_cycle_function_t)NULL,
		      (delete_function_t) delete_symtab,
		      NULL,
		      ex );
}

STLIST* stlist_pop( STLIST * volatile *list )
{
    return (STLIST*) sllist_pop( (SLLIST * volatile *)list );
}

SYMTAB* stlist_pop_data( STLIST * volatile *list )
{
    return (SYMTAB*) sllist_pop_data( (SLLIST * volatile *)list );
}

void stlist_drop( STLIST * volatile *list )
{
    sllist_drop( (SLLIST * volatile *)list );
}

void stlist_swap( STLIST * volatile *list )
{
    sllist_swap( (SLLIST * volatile *)list );
}
