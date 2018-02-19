/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

/* exports: */
#include <fixup.h>

/* uses: */
#include <cexceptions.h>
#include <allocx.h>
#include <stringx.h>
#include <assert.h>

struct FIXUP {
    char *name;
    char is_absolute;
    ssize_t address;
    struct FIXUP *next;
};

int fixup_is_absolute( FIXUP *fixup )
{
    assert( fixup );
    return fixup->is_absolute;
}

FIXUP *fixup_next( FIXUP *fixup )
{
    assert( fixup );
    return fixup->next;
}

char *fixup_name( FIXUP *fixup )
{
    assert( fixup );
    return fixup->name;
}

ssize_t fixup_address( FIXUP *fixup )
{
    assert( fixup );
    return fixup->address;
}

FIXUP *fixup_append( FIXUP *head, FIXUP *tail )
{
    assert( head );
    head->next = tail;
    return head;
}

FIXUP *fixup_list_merge( FIXUP *head, FIXUP *tail )
{
    FIXUP *fixup;

    if( !head ) {
        return tail;
    } else {
        fixup = head;
	while( fixup->next != NULL ) {
	    fixup = fixup->next;
	}
	fixup->next = tail;
	return head;
    }
}

void delete_fixup( FIXUP * fixup )
{
    if( fixup ) {
        if( fixup->name ) freex( fixup->name );
	freex( fixup );
    }
}

FIXUP *pop_fixup( FIXUP * fixup )
{
    FIXUP *next;
    if( fixup ) {
	next = fixup->next;
        if( fixup->name ) freex( fixup->name );
	freex( fixup );
	return next;
    } else {
	return NULL;
    }
}

FIXUP *new_fixup( const char *name,
		  ssize_t address,
		  int is_absolute,
		  FIXUP *next,
		  cexception_t *ex )
{
    cexception_t inner;
    FIXUP * volatile fixup = callocx( sizeof(*fixup), 1, ex );

    cexception_guard( inner ) {
        fixup->name = strdupx( (char*)name, &inner );
	fixup->address = address;
	fixup->is_absolute = is_absolute;
	fixup->next = next;
    }
    cexception_catch {
        delete_fixup( fixup );
	cexception_reraise( inner, ex );
    }
    return fixup;
}

FIXUP *new_fixup_relative( const char *name,
			   ssize_t address,
			   FIXUP *next,
			   cexception_t *ex )
{
    FIXUP * volatile fixup = new_fixup( name, address, 0, next, ex );
    return fixup;
}

FIXUP *new_fixup_absolute( const char *name,
			   ssize_t address,
			   FIXUP *next,
			   cexception_t *ex )
{
    FIXUP * volatile fixup = new_fixup( name, address, 1, next, ex );
    return fixup;
}

void delete_fixup_list( FIXUP * fixup_list )
{
    FIXUP *next;
    while( fixup_list ) {
        next = fixup_list->next;
	delete_fixup( fixup_list );
	fixup_list = next;
    }
}

FIXUP *fixup_swap( FIXUP *list )
{
    FIXUP *first, *second;

    first = list;
    second = list->next;
    assert( second );

    first->next = second->next;
    second->next = first;

    return second;
}

FIXUP *fixup_adjust_address( FIXUP *fixup, ssize_t address )
{
    assert( fixup );
    fixup->address -= address;
    return fixup;
}

void fixup_list_adjust_addresses( FIXUP *fixup_list, ssize_t address )
{
    FIXUP *fixup;

    for( fixup = fixup_list; fixup != NULL; fixup = fixup->next ) {
	fixup_adjust_address( fixup, address );
    }
}
