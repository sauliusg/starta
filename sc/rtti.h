/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

/* Run-time type information (RTTI), retained by the compiler for the
   runtime system in the static data are. */

#ifndef __RTTI_H
#define __RTTI_H

typedef struct rtti_t {
    ssize_t size;
    ssize_t nref;
} rtti_t;

#endif
