/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

/* Representation of type attributes. */

/* exports: */
#include <anode.h>

/* uses: */
#include <tnode.h>
#include <cexceptions.h>
#include <allocx.h>
#include <assert.h>

#include <stdio.h>

struct ANODE {
    anode_kind_t kind;
    char *name;
    union {
	char *s;
	ssize_t n;
    } value;
    ssize_t rcount;
};

#include <anode_a.ci>

void delete_anode( ANODE* node )
{
    if( node ) {
	if( node->rcount <= 0 ) {
	    printf( "!!! anode->rcound == %d !!!\n", node->rcount );
	    assert( node->rcount > 0 );
	}
        if( --node->rcount > 0 )
	    return;
	freex( node->name );
	if( node->kind == AK_STRING_ATTRIBUTE ) {
	    freex( node->value.s );
	}
        free_anode( node );
    }
}

static ANODE *new_anode( cexception_t *ex )
{
    ANODE *anode = alloc_anode( ex );
    anode->rcount = 1;
    return anode;
}

ANODE *new_anode_string_attribute( char *name,
				   char *value,
				   cexception_t *ex )
{
    cexception_t inner;
    ANODE * volatile anode = new_anode( ex );

    cexception_guard( inner ) {
	anode->kind = AK_STRING_ATTRIBUTE;
	anode->name = strdupx( name, &inner );
	anode->value.s = strdupx( value, &inner );
    }
    cexception_catch {
	delete_anode( anode );
	cexception_reraise( inner, ex );
    }

    return anode;
}

ANODE *new_anode_integer_attribute( char *name,
				    ssize_t value,
				    cexception_t *ex )
{
    cexception_t inner;
    ANODE * volatile anode = new_anode( ex );

    cexception_guard( inner ) {
	anode->kind = AK_INTEGER_ATTRIBUTE;
	anode->name = strdupx( name, &inner );
	anode->value.n = value;
    }
    cexception_catch {
	delete_anode( anode );
	cexception_reraise( inner, ex );
    }

    return anode;
}

char *anode_name( ANODE *anode )
{
    assert( anode );
    return anode->name;
}

anode_kind_t anode_kind( ANODE *anode )
{
    assert( anode );

    return anode->kind;
}

ssize_t anode_integer_value( ANODE *anode )
{
    assert( anode );

    if( anode->kind == AK_INTEGER_ATTRIBUTE ) {
	return anode->value.n;
    } else {
	return 0;
    }
}

char *anode_string_value( ANODE *anode )
{
    assert( anode );

    if( anode->kind == AK_STRING_ATTRIBUTE ) {
	return anode->value.s;
    } else {
	return NULL;
    }
}

char *attribute_kind_name( anode_kind_t akind )
{
    static char pad[80];

    switch( akind ) {
        case AK_INTEGER_ATTRIBUTE: return "AK_INTEGER_ATTRIBUTE";
        case AK_STRING_ATTRIBUTE:  return "AK_STRING_ATTRIBUTE";
        default:
	    snprintf( pad, sizeof(pad)-1, "type attribute of kind %d", akind );
	    return pad;
    }
}
