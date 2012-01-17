/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

#ifndef __SYMTAB_H
#define __SYMTAB_H

/* symbol table to store defined variables */

typedef struct SYMTAB SYMTAB; /* variable symbol table */

#include <vartab.h>
#include <typetab.h>
#include <cexceptions.h>

SYMTAB *new_symtab( VARTAB *vartab,
		    VARTAB *consts,
		    TYPETAB *typetab,
		    cexception_t *ex );

void delete_symtab( SYMTAB *table );

void obtain_tables_from_symtab( SYMTAB *symtab,
				VARTAB **vartab,
				VARTAB **consts,
				TYPETAB **typetab );

#endif
