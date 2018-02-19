/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

/* An object to store all symbol tables of a compiler (variables,
   constants, types). */

/* exports: */
#include <symtab.h>

/* uses: */
#include <vartab.h>
#include <typetab.h>
#include <allocx.h>
#include <assert.h>

struct SYMTAB {
    VARTAB *vartab;   /* declared variables, with scopes */
    VARTAB *consts;   /* declared constants, with scopes */
    TYPETAB *typetab; /* declared types and their scopes */
    VARTAB *operators; /* operators declared outside types */
};

SYMTAB *new_symtab( VARTAB *vartab,
		    VARTAB *consts,
		    TYPETAB *typetab,
		    VARTAB *operators,
		    cexception_t *ex )
{
    SYMTAB *symtab = callocx( sizeof(SYMTAB), 1, ex );

    symtab->vartab = vartab;
    symtab->consts = consts;
    symtab->typetab = typetab;
    symtab->operators = operators;

    return symtab;
}

void delete_symtab( SYMTAB *table )
{
    if( !table ) return;
    delete_vartab( table->vartab );
    delete_vartab( table->consts );
    delete_typetab( table->typetab );
    delete_vartab( table->operators );
    freex( table );
}

void obtain_tables_from_symtab( SYMTAB *symtab,
				VARTAB **vartab,
				VARTAB **consts,
				TYPETAB **typetab,
				VARTAB **operators )
{
    assert( symtab );
    assert( vartab );
    assert( consts );
    assert( typetab );

    *vartab = symtab->vartab;
    *consts = symtab->consts;
    *typetab = symtab->typetab;
    *operators = symtab->operators;

    symtab->vartab = NULL;
    symtab->consts = NULL;
    symtab->typetab = NULL;
    symtab->operators = NULL;
}

TYPETAB *symtab_typetab( SYMTAB *st )
{
    assert( st );
    return st->typetab;
}

VARTAB *symtab_vartab( SYMTAB *st )
{
    assert( st );
    return st->vartab;
}

VARTAB *symtab_consttab( SYMTAB *st )
{
    assert( st );
    return st->consts;
}

VARTAB *symtab_optab( SYMTAB *st )
{
    assert( st );
    return st->operators;
}
