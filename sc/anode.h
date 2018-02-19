/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

#ifndef __ANODE_H
#define __ANODE_H

typedef struct ANODE ANODE;

#include <unistd.h> /* for ssize_t */
#include <cexceptions.h>
#include <stringx.h>

typedef enum {
    AK_NONE = 0,
    AK_STRING_ATTRIBUTE,
    AK_INTEGER_ATTRIBUTE,
    last_ANODE_KIND
} anode_kind_t;

void delete_anode( ANODE* node );

ANODE *new_anode_string_attribute( char *name,
				   char *value,
				   cexception_t *ex );

ANODE *new_anode_integer_attribute( char *name,
				    ssize_t value,
				    cexception_t *ex );

char *anode_name( ANODE *anode );

anode_kind_t anode_kind( ANODE *anode );

ssize_t anode_integer_value( ANODE *anode );

char *anode_string_value( ANODE *anode );

char *attribute_kind_name( anode_kind_t akind );

#endif
