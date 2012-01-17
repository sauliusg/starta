/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

#ifndef __STLIST_H
#define __STLIST_H

#include <symtab.h>

typedef struct STLIST STLIST;

typedef void (*symtab_delete_function_t)( SYMTAB* );
typedef void (*symtab_dispose_function_t)( SYMTAB* volatile * );

void delete_stlist( STLIST *list );
STLIST* new_stlist( SYMTAB *symtab,
		      symtab_delete_function_t delete_fn,
		      STLIST *next,
		      cexception_t *ex );
void create_stlist( STLIST * volatile *list,
		     SYMTAB * volatile *data,
		     symtab_dispose_function_t dispose_fn,
		     STLIST *next, cexception_t *ex );
void dispose_stlist( STLIST* volatile *list );
SYMTAB* stlist_data( STLIST *list );
SYMTAB* stlist_extract_data( STLIST *list );
void stlist_set_data( STLIST *list, SYMTAB * volatile *code );
STLIST* stlist_next( STLIST *list );
void stlist_disconnect( STLIST *list );
void stlist_push( STLIST *volatile *list,
		   STLIST *volatile *node,
		   cexception_t *ex );
void stlist_push_data( STLIST *volatile *list,
			SYMTAB *volatile *data,
			symtab_delete_function_t delete_fn,
			symtab_dispose_function_t dispose_fn,
			cexception_t *ex );
void stlist_push_symtab( STLIST *volatile *list,
		       SYMTAB *volatile *data,
		       cexception_t *ex );
STLIST* stlist_pop( STLIST * volatile *list );
SYMTAB* stlist_pop_data( STLIST * volatile *list );
void stlist_drop( STLIST * volatile *list );
void stlist_swap( STLIST * volatile *list );

#endif
