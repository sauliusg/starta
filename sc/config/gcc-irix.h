/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

/* defines IRIX and gcc specific constants */

#ifndef __CONFIG_GCC_IRIX_H
#define __CONFIG_GCC_IRIX_H

#define HAVE_LONG_LONG   1
#define HAVE_LONG_DOUBLE 1
#define HAVE_SSIZE_T     1
#define HAVE_SIZE_T      1
#define HAVE_SNPRINTF    0

#define LONG_LONG_FMT           "L"
#define UNSIGNED_LONG_LONG_FMT  "L"
#define LONG_FMT                "l"
#define UNSIGNED_LONG_FMT       "ul"
#define SIZE_FMT                "ul"
#define SSIZE_FMT               "l"
#define LONG_DOUBLE_FMT         "l"

#endif
