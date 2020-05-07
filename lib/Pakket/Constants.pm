package Pakket::Constants; ## no critic [Subroutines::ProhibitExportingUndeclaredSubs]

# ABSTRACT: Constants used in Pakket

use v5.22;
use strict;
use warnings;

# exports
use namespace::clean;
use Exporter qw(import);
our @EXPORT_OK = qw(
    PAKKET_INFO_FILE
    PAKKET_PACKAGE_SPEC
    PAKKET_VALID_PHASES
    PAKKET_VALID_PREREQ_TYPES
    PARCEL_FILES_DIR
    PARCEL_METADATA_FILE
);

use constant {
    'PAKKET_INFO_FILE' => 'info.json',

    # CATEGORY/PACKAGE                 == latest version, latest release
    # CATEGORY/PACKAGE=VERSION         == Exact version, latest release
    # CATEGORY/PACKAGE=VERSION:RELEASE == Exact version and release
    'PAKKET_PACKAGE_SPEC' => qr{
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

    'PAKKET_VALID_PHASES' => {
        'build'     => 1,
        'configure' => 1,
        'develop'   => 1,
        'runtime'   => 1,
        'test'      => 1,
    },
    'PAKKET_VALID_PREREQ_TYPES' => {
        'requires'   => 1,
        'recommends' => 1,
        'suggests'   => 1,
    },
    'PARCEL_FILES_DIR'     => 'files',
    'PARCEL_METADATA_FILE' => 'meta.json',
};

1;

__END__
