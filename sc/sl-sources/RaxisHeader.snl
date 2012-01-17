struct RigakuHeader {
   char  name[10];     /* type of instrument */
   char  vers[10];     /* version */
   char  crnm[20];     /* crystal name */
   char  crsy[12];     /* crystal system */
    /* +52 bytes, +13 ints int32 */
   float alng;         /* a */
   float blng;         /* b */
   float clng;         /* c */
   float alfa;         /* alpha */
   float beta;         /* beta */
   float gamm;         /* gamma */

    /* 19 ints */
   char  spgr[12];     /* space group symbol */

    /* 22 ints */
   float mosc;         /* mosaic spread */

    /* 23 ints */
   char  memo[80];     /* memo, comments */
   char  res1[84];     /* reserved space for future use */

    /* 64 ints */
   char  date[12];     /* date of measurement */
   char  opnm[20];     /* username of account collecting image */
   char  trgt[4];      /* type of X-ray target (Cu, Mo, etc.) */

    /* 73 ints */
   float wlng;         /* X-ray wavelength */
   char  mcro[20];     /* type of monochromator */
   float m2ta;         /* monochromator 2theta (deg) */
   char  colm[20];     /* collimator size and type */
   char  filt[4];      /* filter type (Ni, etc.) */
   float camr;         /* crystal-to-detector distance */
   float vltg;         /* generator voltage (kV) */
   float crnt;         /* generator current (mA) */
   char  focs[12];     /* focus info */

    /* 95 ints */
   char  optc[80];     /* xray memo */
   int  cyld;         /* IP shape, 0=flat,1=cylinder */
   float weis;         /* Weissenberg oscillation 1 */
   char  res2[56];     /* reserved space for future use */
 
   char  mnax[4];      /* crystal mount axis closest to spindle axis */
   char  bmax[4];      /* crystal mount axis closest to beam axis */

    /* 131 */
   float phi0;         /* datum phi angle (deg) */
   float phis;         /* phi oscillation start angle (deg) */
   float phie;         /* phi oscillation end angle (deg) */
   int  oscn;         /* frame number */

    /* 134 */
   float fext;         /* exposure time (min) */
   float drtx;         /* direct beam X position */
   float drtz;         /* direct beam Z position */
   float omga;         /* goniostat angle omega */
   float fkai;         /* goniostat angle chi */
   float thta;         /* goniostat angle 2theta */
   float mu;           /* spindle inclination angle */
   char  scan[204];    /* reserved space for future use */
                       /* This space is now used for storing the scan
                          template information - tlh, 01 Feb 1999 */
    int  xpxl;         /* number of pixels in X direction */
   int  zpxl;         /* number of pixels in Z direction */
   float xsiz;         /* size of pixel in X direction (mm) */
   float zsiz;         /* size of pixel in Z direction (mm) */
   int  rlng;         /* record length (bytes) */
   int  rnum;         /* number of records (lines) in image */
   int  ipst;         /* starting line number */
   int  ipnm;         /* IP number */
   float rato;         /* photomultiplier output hi/lo ratio */
   float ft_1;         /* fading time, end of exposure to start of read */
   float ft_2;         /* fading time, end of exposure to end of read */
   char  host[10];     /* type of computer (IRIS, VAX) => endian */
   char  ip[10];       /* type of IP */
   int  dr_x;         /* horizontal scanning code: 0=left->right, 1=>right->left */
   int  dr_z;         /* vertical scanning code: 0=down->up, 1=up->down */
   int  drxz;          /* front/back scanning code: 0=front, 1=back */
   float shft;         /* pixel shift, R-AXIS V */
   float ineo;         /* intensity ratio E/O R-AXIS V */
   int  majc;         /* magic number to indicate next values are legit */
   int  naxs;         /* Number of goniometer axes */
   float gvec[5][3];   /* Goniometer axis vectors */
   float gst[5];       /* Start angles for each of 5 axes */
   float gend[5];      /* End angles for each of 5 axes */
   float goff[5];      /* Offset values for each of 5 axes */
   int  saxs;         /* Which axis is the scan axis? */
   char  gnom[40];     /* Names of the axes (space or comma separated?) */
 
 /*
  * Most of below is program dependent.  Different programs use
  * this part of the header for different things.  So it is essentially
  * a big "common block" area for dumping transient information.
  */
   char  file[16];     /* */
   char  cmnt[20];     /* */
   char  smpl[20];     /* */
   int  iext;         /* */
   int  reso;         /* */
   int  save;         /* */
   int  dint;         /* */
   int  byte;         /* */
   int  init;         /* */
   int  ipus;         /* */
   int  dexp;         /* */
   int  expn;         /* */
   int  posx[20];     /* */
   int  posy[20];     /* */
   int   xray;         /* */
   char  res5[768];    /* reserved space for future use */
 };
 

