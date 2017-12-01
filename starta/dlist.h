/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

#ifndef __DLIST_H
#define __DLIST_H

#include <dnode.h>

typedef struct DLIST DLIST;

typedef void (*dnode_delete_function_t)( DNODE* );
typedef void (*dnode_dispose_function_t)( DNODE* volatile * );

void delete_dlist( DLIST *list );
DLIST* new_dlist( DNODE *dnode,
		      dnode_delete_function_t delete_fn,
		      DLIST *next,
		      cexception_t *ex );
void create_dlist( DLIST * volatile *list,
		     DNODE * volatile *data,
		     dnode_dispose_function_t dispose_fn,
		     DLIST *next, cexception_t *ex );
void dispose_dlist( DLIST* volatile *list );
DNODE* dlist_data( DLIST *list );
DNODE* dlist_extract_data( DLIST *list );
void dlist_set_data( DLIST *list, DNODE * volatile *code );
DLIST* dlist_next( DLIST *list );
void dlist_disconnect( DLIST *list );
void dlist_push( DLIST *volatile *list,
		   DLIST *volatile *node,
		   cexception_t *ex );
void dlist_push_data( DLIST *volatile *list,
			DNODE *volatile *data,
			dnode_delete_function_t delete_fn,
			dnode_dispose_function_t dispose_fn,
			cexception_t *ex );
void dlist_push_dnode( DLIST *volatile *list,
		       DNODE *volatile *data,
		       cexception_t *ex );
DLIST* dlist_pop( DLIST * volatile *list );
DNODE* dlist_pop_data( DLIST * volatile *list );
void dlist_drop( DLIST * volatile *list );
void dlist_swap( DLIST * volatile *list );

#endif
