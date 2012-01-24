#! /home/saulius/bin/sl0 --
//--*- C -*---------------------------------------------------------------------
//$Author: saulius $
//$Date: 2012-01-24 20:51:42 +0200 (Tue, 24 Jan 2012) $
//$Revision: 27 $
//$URL: svn+ssh://saulius-grazulis.lt/home/saulius/svn-repositories/sgem-xray/trunk/bin/ccp4mapfill.sl $
//------------------------------------------------------------------------------
//*
// Read a CCP4 map, fill it with dummy atoms.
//**

use std;

use Math;
use SOptions;

use CCP4Map;
use UnitCell;
use PDB;
use Spacegroups;
use GNUrand48;

exception NULL_VECTOR_ERROR;

function symop_apply( double symop[][]; double xyz[] ) : array of double;
function symop_ortho_from_fract( float cell[] ) : array [][] of double;
function symop_fract_from_ortho( float[] cell ) : array [][] of double;

procedure print_map_header_remarks( CCP4MapHeader hdr );

var opt_seed = new OptionValue;
var opt_natoms = new OptionValue;
var opt_atoms_per_res = new OptionValue;
var opt_level = new OptionValue;
var opt_threshold = new OptionValue;
var opt_density = new OptionValue;
var opt_atom_name = new OptionValue;
var opt_residue_name = new OptionValue;
var opt_randomise = new OptionValue;

function help( string argv[]; int i ): string;

var options = 
[
 make_option( "-S", "--seed",         OT_INT    OptionType, opt_seed ),
 make_option( "-n", "--natoms",       OT_INT    OptionType, opt_natoms ),
 make_option( "-l", "--level",        OT_FLOAT  OptionType, opt_level ),
 make_option( "-t", "--threshold",    OT_FLOAT  OptionType, opt_threshold ),
 make_option( "-d", "--density",      OT_FLOAT  OptionType, opt_density ),
 make_option( "-a", "--atom-name",    OT_STRING OptionType, opt_atom_name ),
 make_option( "-r", "--residue-name", OT_STRING OptionType, opt_residue_name ),

 make_option( "-A", "--atoms-per-residue",
              OT_INT OptionType, opt_atoms_per_res ),

 make_option( "-R", "--randomise",
              OT_BOOLEAN_TRUE  OptionType, opt_randomise ),

 make_option( "-R-","--dont-randomise",
              OT_BOOLEAN_FALSE OptionType, opt_randomise ),

 make_option( null, "--help", OT_FUNCTION OptionType, proc => help ),
];

function help( string argv[]; int i ): string
{
    var string progname = argv[0];
    . progname, ": help";
    exit(0);
    return "";
}

program ( argv : array of string; stdio : array of file );

var stdout = stdio[1];
var stderr = stdio[2];

var files = get_options( argv, options );

for( var argnr = 1; argnr <= last(argv); argnr++ ) {
    try {
        var map = fload( argv[argnr] );
        var hdr = CCP4Map::unpack_header( map );
        var raster = CCP4Map::unpack_raster( map, hdr );

        print_map_header_remarks( hdr );

        // calculate map average, sigma and the number of "high points"
        // (i.e. points above the declared threshold), from the raster:

        var llong nhigh;
        var double dmap_sigma = hdr.rmsDeviation;
        var double sum, sum2, value;
        for var i = 0 to last(raster) {
            for var j = 0 to last(raster[i]) {
                for var k = 0 to last(raster[i][j]) {
                   value = raster[i][j][k];
                   sum += value;
                   sum2 += value * value;
                   if( value > dmap_sigma ) {
                       nhigh ++;
                   }
                }
            }
        }

        var npoints = 
            <llong>hdr.crs[0] * <llong>hdr.crs[1] * <llong>hdr.crs[2];
        var average =
            sum / <double>npoints;
        var sigma = 
            sqrt((sum2 - (sum*sum)/<double>npoints)/<double>(npoints - 1LL));
        var high_percentage =
             <double>nhigh / <double>npoints;

        var xstep = hdr.cell[0]/<float>hdr.xyzIntervals[0];
        var ystep = hdr.cell[1]/<float>hdr.xyzIntervals[1];
        var zstep = hdr.cell[2]/<float>hdr.xyzIntervals[2];
        var voxel_volume =
            cell_volume( [ xstep, ystep, zstep,
                           hdr.cell[3], hdr.cell[4], hdr.cell[5] ] );
        var high_volume = voxel_volume * <double>nhigh;

        . "REMARK calculated average   =", average;
        . "REMARK map reported average =", hdr.meanDensity;
        . "REMARK calculated average   =", sigma;
        . "REMARK map reported rms     =", hdr.rmsDeviation;
        . "REMARK cell volume          =",
              <double>hdr.cell[0] * <double>hdr.cell[1] *  <double>hdr.cell[2];
        . "REMARK high volume          =", high_volume;

        // CRYST1 record should be printed after all remarks:

        print_cryst1( hdr.cell, sg_number => hdr.spaceGroup, Z => 1 );

        // generate atoms within the map:

        var xstart = hdr.start[hdr.mapX];
        var ystart = hdr.start[hdr.mapY];
        var zstart = hdr.start[hdr.mapZ];

        var xsize = hdr.crs[hdr.mapX];
        var ysize = hdr.crs[hdr.mapY];
        var zsize = hdr.crs[hdr.mapZ];

        var xintervals = hdr.xyzIntervals[0];
        var yintervals = hdr.xyzIntervals[1];
        var zintervals = hdr.xyzIntervals[2];

        var o2f = symop_fract_from_ortho( hdr.cell );
        if( !o2f ) {
            raise NULL_VECTOR_ERROR("NULL f2o symop");
        }

        var f2o = symop_ortho_from_fract( hdr.cell );
        if( !f2o ) {
            raise NULL_VECTOR_ERROR("NULL f2o symop");
        }

        srand48( 12278 );

        var atom_number, residue_number : int;

        var map_sigma = hdr.rmsDeviation;
        var n = 0;
        for( var i = 0L; i < 500000L; i++ ) {
            var ix, iy, iz : long;
            var rx, ry, rz : double;
            var gx, gy, gz : double;
            var fx, fy, fz : double;
            var xyz : array [] of double;

            rx, ry, rz = drand48(), drand48(), drand48();

            gx, gy, gz =
                rx * <double>(xsize - 1),
                ry * <double>(ysize - 1),
                rz * <double>(zsize - 1);

            ix, iy, iz = iround( gx ), iround( gy ), iround( gz );

            fx, fy, fz =
                (gx + <double>xstart) / <double>(xintervals),
                (gy + <double>ystart) / <double>(yintervals),
                (gz + <double>zstart) / <double>(zintervals);

            if( ix < 0L || ix > <long>last(raster) ) {
                raise ArrayOverflowException
                    ( "ix value "+("%d"%%ix)+" is out of range");
            }
            if( iy < 0L || iy > <long>last(raster) ) {
                raise ArrayOverflowException
                    ( "iy value "+("%d"%%iy)+" is out of range");
            }
            if( iz < 0L || iz > <long>last(raster) ) {
                raise ArrayOverflowException
                    ( "iz value "+("%d"%%iz)+" is out of range");
            }

            if( raster[ix][iy][iz] > map_sigma ) {
                n++;
                residue_number = n / 100 + 1;
                var atom_name =
                    " O" _ "%d" %% n % 100;
                xyz = symop_apply( f2o, [fx, fy, fz] );
                print_atom( xyz, residue_number, n, atom_name => atom_name,
                            residue_name => "HOH" );
            }
        }

    }
    catch( var message : string ) {
        <stderr> << argv[0] _ ": " _ argv[argnr] _ ": " _ message _ "\n";
    }

    do . "" if argnr < last(argv);
}

procedure print_map_header_remarks( CCP4MapHeader hdr )
{
    . "REMARK future words:", length(hdr.future);

    . "REMARK skew flag", hdr.skewFlag;
    for( var i = 0; i < length(hdr.skewMatrix); i ++ ) {
        < "REMARK skew matrix ";
        for( var j = 0; j < length(hdr.skewMatrix[i]); j ++ ) {
            < hdr.skewMatrix[i][j];
            < " ";
        }
        . "";
    }

    < "REMARK skew transl ";
    for( var i = 0; i < length(hdr.skewTranslation); i++ ) {
        < hdr.skewTranslation[i];
        < " ";
    }
    . "";

    . "REMARK machine stamp:", "0x%04X" %% 
          hdr.machineStamp[1] << 8 | hdr.machineStamp[0];

    for( var i = 0;
         i < (hdr.labelNr < length(hdr.labels) ?
              hdr.labelNr : length(hdr.labels));
         i ++ ) {
        . "REMARK MAP LABEL[", i, "]", hdr.labels[i];
    }

    . "REMARK MAP MODE", hdr.mode;
    . "REMARK xsize, ysize, zsize =", 
          hdr.xyzIntervals[0], hdr.xyzIntervals[1], hdr.xyzIntervals[2];
    . "REMARK cstart, rstart, sstart =",
          hdr.start[0], hdr.start[1], hdr.start[2];
    . "REMARK symop bytes", hdr.symmetryBytes;
}

function matrix3x3_times_vector( double m[][]; double v[] ) : array of double
{
    return
        [
         m[0][0] * v[0] + m[0][1] * v[1] + m[0][2] * v[2],
         m[1][0] * v[0] + m[1][1] * v[1] + m[1][2] * v[2],
         m[2][0] * v[0] + m[2][1] * v[1] + m[2][2] * v[2]
        ];
}

function symop_apply( double symop[][]; double vector[] ) : array of double
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

function symop_fract_from_ortho( float[] cell ) : array [][] of double
{
    var a, b, c, alpha, beta, gamma : double;
    var sg, ca, cb, cg : double;

    a, b, c = cell[0], cell[1], cell[2];
    alpha = Pi * <double>cell[3] / 180.0D;
    beta  = Pi * <double>cell[4] / 180.0D;
    gamma = Pi * <double>cell[5] / 180.0D;

    ca = cos( alpha );
    cb = cos( beta );
    cg = cos( gamma );

    sg = sin( gamma );

    var ctg = cg/sg;
    var D = sqrt(sg*sg - cb*cb - ca*ca + 2.0D*ca*cb*cg);

    return [
        [ 1.0D/a, -(1.D/a)*ctg,  (ca*cg-cb)/(a*D)    ],
        [   0.0D,   1.D/(b*sg), -(ca-cb*cg)/(b*D*sg) ],
        [   0.0D,   0.0D,             sg/(c*D) ],
        [   0.0D,   0.0D, 0.0D ] // zero translation vector
    ];
}

function symop_ortho_from_fract( float cell[] ) : array [][] of double
{
    var a, b, c, alpha, beta, gamma : double;
    var sg, ca, cb, cg : double;

    a, b, c = cell[0], cell[1], cell[2];
    alpha = Pi * <double>cell[3] / 180.0D;
    beta  = Pi * <double>cell[4] / 180.0D;
    gamma = Pi * <double>cell[5] / 180.0D;

    ca = cos( alpha );
    cb = cos( beta );
    cg = cos( gamma );

    sg = sin( gamma );

    return [
        [ a,    b*cg, c*cb            ],
        [ 0.0D, b*sg, c*(ca-cb*cg)/sg ],
        [ 0.0D, 0.0D, c*sqrt(sg*sg-ca*ca-cb*cb+2.0D*ca*cb*cg)/sg ],
        [ 0.0D, 0.0D, 0.0D ] // zero translation vector
    ];
}
