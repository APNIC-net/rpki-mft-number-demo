#!/usr/bin/perl

use warnings;
use strict;

use File::Temp qw(tempdir);
use APNIC::RPKI::CA;

use Test::More tests => 8;

{
    my $stg_repo = tempdir();
    my $repo     = tempdir();
    my $hostname = 'localhost';

    my $ta_dirname      = APNIC::RPKI::CA::make_random_string();
    my $ta_path         = tempdir();
    my $ta_name         = 'test-ta';
    my @ta_ip_resources = ('1.0.0.0/8');
    my @ta_as_resources = ('60000-61000');

    my $ta = APNIC::RPKI::CA->new(ca_path => $ta_path);
    my $tal_path =
        $ta->initialise($ta_name, undef, $stg_repo, $repo,
                        $ta_dirname, 'localhost', 873,
                        \@ta_ip_resources, \@ta_as_resources);

    my $ca_dirname      = APNIC::RPKI::CA::make_random_string();
    my $ca_path         = tempdir();
    my $ca_name         = 'test-ca';
    my $ca_rrdp_dir     = tempdir();
    my $ca_rrdp_dirname = 'rrdp-dirname';
    my $ca_rrdp_host    = 'localhost';
    my $ca_rrdp_port    = 443;
    my @ca_ip_resources = ('1.0.0.0/16');
    my @ca_as_resources = ('60000-60010');

    my $ca = APNIC::RPKI::CA->new(ca_path => $ca_path);
    $ca->initialise($ca_name, 1, $stg_repo, $repo,
                    $ca_dirname, 'localhost', 873,
                    \@ca_ip_resources, \@ca_as_resources,
                    $ca_rrdp_dir, $ca_rrdp_dirname,
                    $ca_rrdp_host, $ca_rrdp_port);
    my $request =
        $ca->get_ca_request($ca_name, \@ca_ip_resources,
                            \@ca_as_resources);
    my ($response, $url) =
        $ta->sign_ca_request($request, \@ca_ip_resources,
                             \@ca_as_resources);
    $ca->install_ca_certificate($response, $url);

    $ca->issue_roa("1.0.0.0/16", 70000);
    $ca->publish();

    my @files = `ls $repo/$ca_dirname`;
    is(@files, 3, 'Three files in repository');
    my @crls = grep { /\.crl$/ } @files;
    my @mfts = grep { /\.mft$/ } @files;
    my @roas = grep { /\.roa$/ } @files;
    is(@crls, 1, 'One CRL in repository');
    is(@mfts, 1, 'One manifest in repository');
    is(@roas, 1, 'One ROA in repository');

    $ca->issue_roa("1.0.0.0/24", 70000);
    $ca->publish();

    @files = `ls $repo/$ca_dirname`;
    is(@files, 3, 'Three files in repository');
    @crls = grep { /\.crl$/ } @files;
    @mfts = grep { /\.mft$/ } @files;
    @roas = grep { /\.roa$/ } @files;
    is(@crls, 1, 'One CRL in repository');
    is(@mfts, 1, 'One manifest in repository');
    is(@roas, 1, 'One ROA in repository');
}

1;
