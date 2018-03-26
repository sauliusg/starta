/*---------------------------------------------------------------------------*\
**$Author: saulius $
**$Date$ 
**$Revision$
**$URL: svn+ssh://kolibris.ibt.lt/home/saulius/svn-repositories/compilers/sl/thrcode.h $
\*---------------------------------------------------------------------------*/

#ifndef __THRCODE_T_H
#define __THRCODE_T_H

#include <unistd.h>
#include <typesize.h>

typedef union thrcode_t thrcode_t;

union thrcode_t {
    int (*fn)( void );
    void *ptr;
    sbyte sbval;
    short sval;
#if 0
    int ival;
#endif
    long lval;
    llong *llptr;
    float fval;
    double *dptr;
    ldouble *ldptr;
    ssize_t ssizeval;
};

#endif
