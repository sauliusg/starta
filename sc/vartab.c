/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

/* symbol table to store defined variables */

/* exports: */
#include <vartab.h>

/* uses: */
#include <string.h> /* for strcmp() */
#include <dnode.h>
#include <cexceptions.h>
#include <allocx.h>
#include <stringx.h>
#include <yy.h>
#include <assert.h>

typedef struct VAR_NODE {
    int rcount;
    int scope;
    int subscope;
    char *name;
    DNODE *dnode;
    struct VAR_NODE *next;
} VAR_NODE;

#include <varnode_a.ci>

static VAR_NODE *new_var_node( cexception_t *ex )
{
    return alloc_var_node( ex );
}

static VAR_NODE *new_var_node_linked( VAR_NODE *next, cexception_t *ex )
{
    VAR_NODE *node = alloc_var_node( ex );
    node->next = next;
    return node;
}

static void delete_var_node( VAR_NODE *node )
{
    if( node ) {
        freex( node->name );
	delete_dnode( node->dnode );
        /* freex( node ); */
        free_var_node( node );
    }
}

static void delete_var_node_list( VAR_NODE *node )
{
    VAR_NODE *next;
    while( node ) {
        next = node->next;
	delete_var_node( node );
	node = next;
    }
}

struct VARTAB {
    int rcount;
    int current_scope;
    int current_subscope;
    VAR_NODE *duplicates;
    VAR_NODE *node;
};

#include <vartab_a.ci>

VARTAB *new_vartab( cexception_t *ex )
{
    return alloc_vartab( ex );
}

void delete_vartab( VARTAB *table )
{
    if( !table ) return;
    delete_var_node_list( table->duplicates );
    delete_var_node_list( table->node );
    free_vartab( table );
}

int vartab_current_scope( VARTAB *vartab )
{
    assert( vartab );
    return vartab->current_scope;
}

void vartab_insert_named_vars( VARTAB *table, DNODE *dnode_list,
			       cexception_t *ex )
{
    DNODE *dnode;
    char *name;

    assert( table );
    assert( dnode_list );

    dnode = dnode_list;
    name = dnode_name( dnode );
    assert( name );
    vartab_insert( table, name, dnode, ex );

    while( ( dnode = dnode_next( dnode )) != NULL ) {
        name = dnode_name( dnode );
	assert( name );
	vartab_insert( table, name, share_dnode( dnode ), ex );
    }
}

void vartab_insert_named( VARTAB *table, DNODE *dnode, cexception_t *ex )
{
    assert( table );
    vartab_insert( table, dnode_name(dnode), dnode, ex );
}

static VAR_NODE *vartab_lookup_varnode( VARTAB *table, const char *name );

void vartab_insert( VARTAB *table, const char *name,
		    DNODE *dnode, cexception_t *ex )
{
    cexception_t inner;
    VAR_NODE * volatile node = NULL;
    VAR_NODE * volatile newnode = NULL;
    assert( table );
    cexception_guard( inner ) {
	if( (node = vartab_lookup_varnode( table, name )) != NULL ) {
	    if( node->scope == table->current_scope ) {
		yyerrorf( "symbol '%s' already declared in the current scope",
			   name );
		table->duplicates =
		    new_var_node_linked( table->duplicates, &inner );
		table->duplicates->dnode = dnode;
#if 0
	    } else {
		fprintf( stderr, "name '%s' shadows previous declaration "
			 "in scope %d (currently in scope %d)\n",
			 name, node->scope, table->current_scope );
#endif
	    }
	}
	if( !node || node->scope != table->current_scope ) {
	    newnode = new_var_node( ex );
	    newnode->dnode = dnode;
	    newnode->name  = strdupx( (char*)name, &inner );
	    newnode->next  = table->node;
	    newnode->scope = table->current_scope;
	    newnode->subscope = table->current_subscope;
	    table->node = newnode;
	    dnode_set_scope( dnode, table->current_scope );
	}
    }
    cexception_catch {
        delete_var_node( newnode );
	cexception_reraise( inner, ex );
    }
}

void vartab_copy_table( VARTAB *dst, VARTAB *src, cexception_t *ex )
{
    VAR_NODE *curr;

    assert( dst );
    assert( src );

    for( curr = src->node; curr != NULL; curr = curr->next ) {
	char *name = curr->name;
	DNODE *dnode = curr->dnode;
	vartab_insert( dst, name, share_dnode( dnode ), ex );
    }
}

DNODE *vartab_lookup( VARTAB *table, const char *name )
{
    VAR_NODE *node = vartab_lookup_varnode( table, name );
    return node ? node->dnode : NULL;
}

static VAR_NODE *vartab_lookup_varnode( VARTAB *table, const char *name )
{
    VAR_NODE *node;
    assert( table );
    for( node = table->node; node != NULL; node = node->next ) {
        if( strcmp( name, node->name ) == 0 ) {
	    assert( node->dnode );
	    return node;
	}
    }
    return NULL;
}

void vartab_begin_scope( VARTAB* table, cexception_t *ex )
{
    assert( table );
    table->current_scope ++;
}

void vartab_end_scope( VARTAB* table, cexception_t *ex )
{
    VAR_NODE *tn, *next;

    assert( table );
    assert( table->current_scope > 0 );

    tn = table->node;
    while( tn != NULL ) {
        next = tn->next;
	if( table->current_scope != tn->scope ) {
	    break;
	} else {
	    delete_var_node( tn );
	}
	tn = next;
    }
    table->node = tn;

    assert( table->current_scope > 0 );
    table->current_scope --;
    return;
}

void vartab_begin_subscope( VARTAB* table, cexception_t *ex )
{
    assert( table );
    table->current_subscope ++;
}

void vartab_end_subscope( VARTAB* table, cexception_t *ex )
{
    VAR_NODE *tn, *next;

    assert( table );

    tn = table->node;
    while( tn != NULL ) {
        next = tn->next;
	if( table->current_subscope != tn->subscope  ) {
	    break;
	} else {
	    delete_var_node( tn );
	}
	tn = next;
    }
    table->node = tn;
    assert( table->current_subscope > 0 );
    table->current_subscope --;
    return;
}
