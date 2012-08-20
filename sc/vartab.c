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

typedef enum {
    VNF_NONE = 0,
    VNF_IS_IMPORTED /* identifies nodes imported from modules into
                       other namespaces. */
} var_node_flag_t;

typedef struct VAR_NODE {
    int flags;
    int rcount;
    int count; /* counts how may times an object with this name was
                  imported from different modules. */
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
	    if( node->scope == table->current_scope &&
                (node->flags & VNF_IS_IMPORTED) == 0 ) {
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
	if( !node || node->scope != table->current_scope ||
            (node->flags & VNF_IS_IMPORTED) != 0 ) {
	    newnode = new_var_node( ex );
	    newnode->dnode = dnode;
	    newnode->name  = strdupx( (char*)name, &inner );
	    newnode->next  = table->node;
	    newnode->scope = table->current_scope;
            newnode->count = 1;
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

void vartab_insert_modules_name( VARTAB *table, const char *name,
                                 DNODE *dnode, cexception_t *ex )
{
    cexception_t inner;
    VAR_NODE * volatile node = NULL;
    VAR_NODE * volatile newnode = NULL;
    assert( table );
    cexception_guard( inner ) {
	if( (node = vartab_lookup_varnode( table, name )) != NULL ) {
	    if( node->scope == table->current_scope ) {
                if( (node->flags & VNF_IS_IMPORTED) == 0 ) {
                    /* a non-imported name exists -- silently ignore
                       the imported name:*/
                    table->duplicates =
                        new_var_node_linked( table->duplicates, &inner );
                    table->duplicates->dnode = dnode;
                } else {
                    /* another imported name exists: add the new
                       imported name, but mark that it is present
                       multiple times: */
                    newnode = new_var_node( ex );
                    newnode->dnode = dnode;
                    newnode->name  = strdupx( (char*)name, &inner );
                    newnode->next  = table->node;
                    newnode->scope = table->current_scope;
                    newnode->count = node->count + 1;
                    newnode->flags |= VNF_IS_IMPORTED;
                    newnode->subscope = table->current_subscope;
                    table->node = newnode;
                    dnode_set_scope( dnode, table->current_scope );
                }
            }
	}
        /* No node with the same name is present in the current scope:
           add it: */
	if( !node || node->scope != table->current_scope ) {
	    newnode = new_var_node( ex );
	    newnode->dnode = dnode;
	    newnode->name  = strdupx( (char*)name, &inner );
	    newnode->next  = table->node;
	    newnode->scope = table->current_scope;
            newnode->count = 1;
            newnode->flags |= VNF_IS_IMPORTED;
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
	vartab_insert_modules_name( dst, name, share_dnode( dnode ), ex );
    }
}

DNODE *vartab_lookup( VARTAB *table, const char *name )
{
    VAR_NODE *node = vartab_lookup_varnode( table, name );
    if( node && node->count > 1 ) {
        yyerrorf( "name '%s' is imported more than once -- "
                  "please use explicit package name for disambiguation" );
    }
    return node ? node->dnode : NULL;
}

DNODE *vartab_lookup_silently( VARTAB *table, const char *name, 
                               int *count, int *is_imported )
{
    VAR_NODE *node = vartab_lookup_varnode( table, name );
    assert( count );
    assert( is_imported );
    if( node ) {
        *count = node->count;
        *is_imported = ((node->flags & VNF_IS_IMPORTED) != 0);
    }
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
