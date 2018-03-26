/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

#ifndef __HASHCELL_H
#define __HASHCELL_H

#include <stackcell.h>

typedef struct hashcell_t {
    stackcell_t key;
    stackcell_t value;
} hashcell_t;

#endif
