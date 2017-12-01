/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

/* defines Linux and gcc specific constants */

#ifndef __CONFIG_GCC_LINUX_H
#define __CONFIG_GCC_LINUX_H

#define HAVE_LONG_LONG   1
#define HAVE_LONG_DOUBLE 1
#define HAVE_SSIZE_T     1
#define HAVE_SIZE_T      1
#define HAVE_SNPRINTF    1

#undef HAVE_SSIZE_T

#define LONG_LONG_FMT           "L"
#define UNSIGNED_LONG_LONG_FMT  "L"
#define LONG_FMT                "l"
#define UNSIGNED_LONG_FMT       "ul"
#define SIZE_FMT                "uz"
#define SSIZE_FMT               "z"
#define LONG_DOUBLE_FMT         "l"

#endif
