/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

#ifndef __VARTAB_H
#define __VARTAB_H

/* symbol table to store defined variables */

typedef struct VARTAB VARTAB; /* variable symbol table */

#include <dnode.h>
#include <cexceptions.h>

VARTAB *new_vartab( cexception_t *ex );
void delete_vartab( VARTAB *table );

int vartab_current_scope( VARTAB *vartab );

void vartab_insert_named_vars( VARTAB *table, DNODE *dnode_list,
			       cexception_t *ex );

void vartab_insert_named( VARTAB *table, DNODE *dnode, cexception_t *ex );

void vartab_insert( VARTAB *table, const char *name,
		    DNODE *tnode, cexception_t *ex );

void vartab_copy_table( VARTAB *dst, VARTAB *src, cexception_t *ex );

DNODE *vartab_lookup( VARTAB *table, const char *name );

void vartab_begin_scope( VARTAB* table, cexception_t *ex );
void vartab_end_scope( VARTAB* table, cexception_t *ex );

void vartab_begin_subscope( VARTAB* table, cexception_t *ex );
void vartab_end_subscope( VARTAB* table, cexception_t *ex );

#endif
