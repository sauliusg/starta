#! /home/saulius/bin/sl0 --
# --*- C -*--
//
// Read a CCP4 map.
//

use std;
use CCP4Map;

/*
# From /xray/install/ccp4/ccp4-6.2.0-bin/doc/maplib.doc, line 81:
#
# 2) DETAILED DESCRIPTION OF THE MAP FORMAT
# 
#    The overall layout of the file is as follows:
#     1. File header (256 longwords)
#     2. Symmetry information
#     3. Map, stored as a 3-dimensional array
# 
#    The header is organised as 56 words followed by space for ten 80
#    character text labels as follows:
# 
#  1      NC              # of Columns    (fastest changing in map)
#  2      NR              # of Rows
#  3      NS              # of Sections   (slowest changing in map)
#  4      MODE            Data type
#                           0 = envelope stored as signed bytes (from
#                               -128 lowest to 127 highest)
#                           1 = Image     stored as Integer*2
#                           2 = Image     stored as Reals
#                           3 = Transform stored as Complex Integer*2
#                           4 = Transform stored as Complex Reals
#                           5 == 0
# 
#                           Note: Mode 2 is the normal mode used in
#                                 the CCP4 programs. Other modes than 2 and 0
#                                 may NOT WORK
# 
#  5      NCSTART         Number of first COLUMN  in map
#  6      NRSTART         Number of first ROW     in map
#  7      NSSTART         Number of first SECTION in map
#  8      NX              Number of intervals along X
#  9      NY              Number of intervals along Y
# 10      NZ              Number of intervals along Z
# 11      X length        Cell Dimensions (Angstroms)
# 12      Y length                     "
# 13      Z length                     "
# 14      Alpha           Cell Angles     (Degrees)
# 15      Beta                         "
# 16      Gamma                        "
# 17      MAPC            Which axis corresponds to Cols.  (1,2,3 for X,Y,Z)
# 18      MAPR            Which axis corresponds to Rows   (1,2,3 for X,Y,Z)
# 19      MAPS            Which axis corresponds to Sects. (1,2,3 for X,Y,Z)
# 20      AMIN            Minimum density value
# 21      AMAX            Maximum density value
# 22      AMEAN           Mean    density value    (Average)
# 23      ISPG            Space group number
# 24      NSYMBT          Number of bytes used for storing symmetry operators
# 25      LSKFLG          Flag for skew transformation, =0 none, =1 if foll
# 26-34   SKWMAT          Skew matrix S (in order S11, S12, S13, S21 etc) if
#                         LSKFLG .ne. 0.
# 35-37   SKWTRN          Skew translation t if LSKFLG .ne. 0.
#                         Skew transformation is from standard orthogonal
#                         coordinate frame (as used for atoms) to orthogonal
#                         map frame, as
# 
#                                 Xo(map) = S * (Xo(atoms) - t)
# 
# 38      future use       (some of these are used by the MSUBSX routines
#  .          "              in MAPBRICK, MAPCONT and FRODO)
#  .          "   (all set to zero by default)
#  .          "
# 52          "
# 
# 53      MAP             Character string 'MAP ' to identify file type
# 54      MACHST          Machine stamp indicating the machine type
#                         which wrote file
# 55      ARMS            Rms deviation of map from mean density
# 56      NLABL           Number of labels being used
# 57-256  LABEL(20,10)    10  80 character text labels (ie. A4 format)
# 
# 
#    Symmetry records follow - if any - stored as text as in International
#    Tables, operators separated by * and grouped into 'lines' of 80
#    characters (i.e. symmetry operators do not cross the ends of the
#    80-character 'lines' and the 'lines' do not terminate in a *).
# 
#    Map data array follows.
*/

exception MAP_SIGNATURE_ERROR;
exception NULL_VECTOR_ERROR;

use Math;

var Pi : float = 4.0 * atan2f(1,1);

use Spacegroups;

function spacegroup_name_lookup( int sg_number ) : string
{
    var sg = Spacegroups::lookup( Spacegroups::table, sg_number );
    if( sg ) { return sg.hermann_mauguin }
    else { return "??" }
}

procedure print_cryst1( float[] cell; string sg_name = null;
                        int sg_number = 1; int Z = 1 )
{
    if( sg_name == null ) {
        if( sg_number != 0 ) {
            sg_name = spacegroup_name_lookup( sg_number );
        } else {
            sg_name = "????"
        }
    }

    . "CRYST1" _
        "%9.3f" %% cell[0] _
        "%9.3f" %% cell[1] _
        "%9.3f" %% cell[2] _
        "%7.2f" %% cell[3] _
        "%7.2f" %% cell[4] _
        "%7.2f" %% cell[5] _
        " %-11s" %% sg_name _
        "%4d" %% Z;
}

procedure print_atom( float xyz[];
                      int residue_number;
                      int atom_number = 0;
                      string atom_name = " C1 ";
                      string residue_name = "XXX";
                      char alt_loc = ' ';
                      char chain = ' ';
                      float occupancy = 1.0;
                      float b_factor = 10.0;
                      string segment = null;
                      string chem_type = null;
                      int charge = 0;
                      char insertion_code = ' ';
                      string keyword = "ATOM  "
                      )
{
    < "%-6s" %% keyword;
    < "%5d " %% atom_number;
    < "%-4s" %% atom_name;
    < "%1c" %% alt_loc;
    < "%3s " %% residue_name;
    < "%1c" %% chain;
    < "%4d" %% residue_number;
    < "%1c   " %% insertion_code;
    < "%8.3f" %% xyz[0];
    < "%8.3f" %% xyz[1];
    < "%8.3f" %% xyz[2];
    < "%6.2f" %% occupancy;
    < "%6.2f" %% b_factor;
    // < "%6s" %% " ";      // filler
    < "    ";            // filler
    < "%-4s" %% (segment ? segment : "");
    < "%2s" %% (chem_type ? chem_type : "");
    < "%2d" %% charge;
    . ""
}

function symop_apply( float symop[][]; float xyz[] ) : array of float;
function symop_ortho_from_fract( float cell[] ) : array [][] of float;

program ( argv : array of string; stdio : array of file );

var stdout = stdio[1];
var stderr = stdio[2];

for( var argnr = 1; argnr <= last(argv); argnr++ ) {
    try {
        var map = fload( argv[argnr] );

        // my @map_header = unpack( "L10f6L3f3L15x60a4LfLa800", $bin_header );

        var iheader = unpack int[] ( map, 0, "i4x10,x4x6,i4x3" );
        var cell = unpack float[] ( map, 40, "f4x6" );
        var fheader = unpack float[] ( map, 19*4, "f4x3,X4x32,f4x1" );
        var signature = unpack string ( map, 52*4, "s4" );
        var nlabels = unpack int ( map, 55*4, "i4" );
        var labels = unpack string[] ( map, 56*4, "s80x10"  );

        var future = unpack int[] ( map, 37*4, "i4x" _ "%d" %% (52-38+1) );
        . "REMARK future words:", length(future);

// 25      LSKFLG          Flag for skew transformation, =0 none, =1 if foll
// 26-34   SKWMAT          Skew matrix S (in order S11, S12, S13, S21 etc) if
//                         LSKFLG .ne. 0.
// 35-37   SKWTRN          Skew translation t if LSKFLG .ne. 0.

        var skew_flag = unpack int ( map, 24*4, "i4" );
        var skew_matrix = unpack float[3][] ( map, 25*4, "f4x3" );
        var skew_transl = unpack float[] ( map, 34*4, "f4x3" );

        . "REMARK skew flag", skew_flag;
        for( var i = 0; i < length(skew_matrix); i ++ ) {
            < "REMARK skew matrix ";
            for( var j = 0; j < length(skew_matrix[i]); j ++ ) {
                < skew_matrix[i][j];
                < " ";
            }
            . "";
        }

        < "REMARK skew transl ";
        for( var i = 0; i < length(skew_transl); i++ ) {
            < skew_transl[i];
            < " ";
        }
        . "";

        var mstamp = unpack int ( map, 53*4, "i4" );
        . "REMARK machine stamp:", "0x%04X" %% mstamp;
    
        var sg_number = unpack int( map, 22*4, "i4" );

        if( signature != "MAP " ) {
            raise MAP_SIGNATURE_ERROR
                ( "file '" _ argv[argnr] _ "' is not a CCP4 map" );
        }

        print_cryst1( cell, sg_number => sg_number, Z => 1 );

        for( var i = 0;
             i < (nlabels < length(labels) ? nlabels : length(labels));
             i ++ ) {
            . "REMARK MAP LABEL[", i, "]", labels[i];
        }

        // var raster = unpack float[iheader[0]][iheader[1]][]
        //     ( map, 1024, "f4x" _ "%d" %% iheader[2] );

        var columns  = iheader[0];
        var rows     = iheader[1];
        var sections = iheader[2];

        var mode = iheader[3];

        var cstart = iheader[4];
        var rstart = iheader[5];
        var sstart = iheader[6];

        var xintervals = iheader[7];
        var yintervals = iheader[8];
        var zintervals = iheader[9];

        var mapCol = iheader[10]-1;
        var mapRow = iheader[11]-1;
        var mapSec = iheader[12]-1;

        var mapX = mapCol == 0 ? 0 : ( mapRow == 0 ? 1 : 2);
        var mapY = mapCol == 1 ? 0 : ( mapRow == 1 ? 1 : 2);
        var mapZ = mapCol == 2 ? 0 : ( mapRow == 2 ? 1 : 2);

        var crs_size = [ columns, rows, sections ];

        var xsize = crs_size[mapX];
        var ysize = crs_size[mapY];
        var zsize = crs_size[mapZ];

        var raster = new float[xsize][ysize][zsize];

        var row_format = "f4" _ "x%d" %% columns;

        . "REMARK xsize, ysize, zsize =", xintervals, yintervals, zintervals;
        . "REMARK cstart, rstart, sstart =", cstart, rstart, sstart;

        var symop_bytes = unpack int( map, 23*4, "i4" );

        . "REMARK symop bytes", symop_bytes;

        for var int s = 0 to sections - 1 {
            for var int r = 0 to rows - 1 {
                var row =
                    unpack float[]( map,
                                  1024 + symop_bytes +
                                  s * rows * columns * 4 + 
                                  r * columns * 4,
                                  row_format );
                for var int c = 0 to columns - 1 {
                    var ix, iy, iz : int;
                    var crs = [ c, r, s ];
                    ix, iy, iz = crs[mapX], crs[mapY], crs[mapZ];
                    raster[ix][iy][iz] = row[c];
                }
            }
        }

        var double sum;
        for var i = 0 to last(raster) {
            for var j = 0 to last(raster[i]) {
                for var k = 0 to last(raster[i][j]) {
                   sum += <double>raster[i][j][k]
                }
            }
        }
        var average = sum / <double>(iheader[0] * iheader[1] * iheader[2]);
        . "REMARK calculated average   =", average;
        . "REMARK map reported average =", fheader[2];
        . "REMARK map reported rms     =", fheader[3];

        var map_sigma = fheader[3];

        // generate atoms within the map:

        var xyzstart = [ cstart, rstart, sstart ];
        var xstart = xyzstart[mapX];
        var ystart = xyzstart[mapY];
        var zstart = xyzstart[mapZ];

        var atom_number, residue_number : int;

        var f2o = symop_ortho_from_fract( cell );
        if( !f2o ) {
            raise NULL_VECTOR_ERROR("NULL f2o symop");
        }

        for var i = 0 to last(raster) {
            for var j = 0 to last(raster[i]) {
                for var k = 0 to last(raster[i][j]) {
                    if( raster[i][j][k] > map_sigma ) {
                        atom_number ++;
                        residue_number = atom_number / 100 + 1;

                        var fx, fy, fz : float;
                        fx = <float>(i+xstart)/<float>xintervals;
                        fy = <float>(j+ystart)/<float>yintervals;
                        fz = <float>(k+zstart)/<float>zintervals;

                        var xyz = symop_apply( f2o, [fx, fy, fz] );

                        var atom_name =
                        " O" _ "%d" %% atom_number % 100;

                        if( 1 ) {
                            print_atom( xyz,
                                        residue_number,
                                        atom_number,
                                        atom_name => atom_name,
                                        residue_name => "HOH" );
                        } else {
                            < "%-6s" %% "ATOM  ";
                            < "%5d " %% atom_number;
                            < "%-4s" %% " C1 ";
                            < "%1c" %% ' 'c;
                            < "%3s " %% "XYZ";
                            < "%1c" %% ' 'c;
                            < "%4d" %% residue_number;
                            < "%1c   " %% ' 'c;
                            < "%8.3f" %% <float>(i-xstart);
                            < "%8.3f" %% <float>(j-ystart);
                            < "%8.3f" %% <float>(k-zstart);
                            < "%6.2f" %% 1.0;
                            < "%6.2f" %% 10.0;
                            < "%6s" %% "";   // filler
                            // < "    ";            // filler
                            < "%-4s" %% "";
                            < "%2s" %% "";
                            < "%2d" %% 0;
                            . "";
                        }
                    }
                }
            }
        }

    }
    catch( var message : string ) {
        <stderr> << argv[0] _ ": " _ message _ "\n";
    }

    do . "" if argnr < last(argv);
}

function matrix3x3_times_vector( float m[][]; float v[] ) : array of float
{
    return
        [
         m[0][0] * v[0] + m[0][1] * v[1] + m[0][2] * v[2],
         m[1][0] * v[0] + m[1][1] * v[1] + m[1][2] * v[2],
         m[2][0] * v[0] + m[2][1] * v[1] + m[2][2] * v[2]
        ];
}


function symop_apply( float symop[][]; float vector[] ) : array of float
{
    if( !vector ) {
        raise NULL_VECTOR_ERROR("NULL parameter in symop_apply");
    }

    var v = matrix3x3_times_vector( symop, vector );

    if( !v ) {
        raise NULL_VECTOR_ERROR("NULL vector v in symop_apply");
    }

    return [
	    v[0] + symop[3][0],
	    v[1] + symop[3][1],
	    v[2] + symop[3][2]
	   ];
}

function symop_ortho_from_fract( float cell[] ) : array [][] of float
{
    var a, b, c, alpha, beta, gamma : float;
    var sg, ca, cb, cg : float;

    a, b, c = cell[0], cell[1], cell[2];
    alpha = Pi * cell[3] / 180.0;
    beta  = Pi * cell[4] / 180.0;
    gamma = Pi * cell[5] / 180.0;

    ca = cosf( alpha );
    cb = cosf( beta );
    cg = cosf( gamma );

    sg = sinf( gamma );

    return [
        [ a,   b*cg, c*cb            ],
        [ 0.0, b*sg, c*(ca-cb*cg)/sg ],
        [ 0.0,  0.0, c*sqrtf(sg*sg-ca*ca-cb*cb+2.0*ca*cb*cg)/sg ],
        [ 0.0, 0.0, 0.0 ] // zero translation vector
    ];
}
