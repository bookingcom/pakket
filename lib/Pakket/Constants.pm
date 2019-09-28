package Pakket::Constants; ## no critic (Subroutines::ProhibitExportingUndeclaredSubs)
# ABSTRACT: Constants used in Pakket

use v5.22;
use strict;
use warnings;
use parent 'Exporter';

use constant {
    'PARCEL_EXTENSION'     => 'pkt',
    'PARCEL_FILES_DIR'     => 'files',
    'PARCEL_METADATA_FILE' => 'meta.json',

    # CATEGORY/PACKAGE                 == latest version, latest release
    # CATEGORY/PACKAGE=VERSION         == Exact version, latest release
    # CATEGORY/PACKAGE=VERSION:RELEASE == Exact version and release
    'PAKKET_PACKAGE_SPEC'  => qr{
        ^
        ( [^/]+ )       # category
        /
        ( [^=]+ )       # name
        (?:
            =
            ( [^:]+ )   # optional version
            (?:
                :
                (.*)    # optional release
            )?
        )?
        $
    }xms,

    'PAKKET_DEFAULT_RELEASE' => 1,
    'PAKKET_INFO_FILE'       => 'info.json',
    'PAKKET_VALID_PHASES'    => {
        'configure' => 1,
        'develop'   => 1,
        'runtime'   => 1,
        'test'      => 1,
    },
};

our @EXPORT_OK = qw<
    PARCEL_EXTENSION
    PARCEL_FILES_DIR
    PARCEL_METADATA_FILE
    PAKKET_PACKAGE_SPEC
    PAKKET_DEFAULT_RELEASE
    PAKKET_INFO_FILE
    PAKKET_VALID_PHASES
>;

1;
