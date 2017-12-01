/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

#ifndef __TYPESIZE_H
#define __TYPESIZE_H

#include <stdlib.h>
#include <unistd.h>
#include <config.h>

typedef unsigned char byte;
typedef unsigned char ubyte;
typedef signed   char sbyte;

#if defined( HAVE_SIZE_T )
    typedef size_t address_t;
#define ADDRESS_FMT SIZE_FMT
#else
#if defined( HAVE_LONG_LONG )
    typedef long long address_t;
#define ADDRESS_FMT LONG_LONG_FMT
#else
    typedef long address_t;
#define ADDRESS_FMT UNSIGNED_LONG_FMT
#endif
#endif

#if defined( HAVE_SSIZE_T )
    typedef ssize_t offset_t;
#else
#if defined( HAVE_SIZE_T )
    typedef long long offset_t;
#elif defined( HAVE_LONG_LONG )
    typedef long long offset_t;
#else
    typedef long offset_t;
#endif
#endif

#if defined( HAVE_LONG_LONG )
    typedef long long longest;
#define LONGEST_FMT LONG_LONG_FMT
#else
#if defined( HAVE_SSIZE_T )
    typedef ssize_t longest;
#define LONGEST_FMT SSIZE_FMT
#else
    typedef long longest;
#define LONGEST_FMT LONG_FMT
#endif
#endif

#if defined( HAVE_LONG_LONG )
    typedef long long llong;
    typedef unsigned long long ullong;
#else
    typedef long llong;
    typedef unsigned long ullong;
#endif

#if defined( HAVE_LONG_DOUBLE )
    typedef long double ldouble;
#else
    typedef double ldouble;
#endif

#endif
