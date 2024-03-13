use strict;
use warnings;

use ExtUtils::MakeMaker;
use ExtUtils::MakeMaker::Config;

my $output = WriteMakefile(
    NAME           => 'APNIC::RPKI::CA',
    AUTHOR         => 'Software <software@apnic.net>',
    LICENSE        => 'bsd',
    VERSION_FROM   => 'lib/APNIC/RPKI/CA.pm',
    META_MERGE     => {
        resources => {
            repository => 'https://github.com/APNIC-net/rpki-mft-number-demo'
        }
    },
    EXE_FILES      => [ qw(bin/setup-ca
                           bin/show-ca-cert
                           bin/reissue-crl-and-mft
                           bin/init-rpki-client
                           bin/run-rpki-client
                           bin/init-fort
                           bin/run-fort
                           bin/init-routinator
                           bin/run-routinator
                           bin/init-octorpki
                           bin/run-octorpki
                           bin/init-validator
                           bin/run-validator) ],
    PREREQ_PM      => { 'Test::More'             => 0,
                        'HTTP::Daemon'           => 0,
                        'YAML'                   => 0,
                        'LWP::UserAgent'         => 0,
                        'List::MoreUtils'        => 0,
                        'IO::Capture::Stderr'    => 0, }
);

1;
