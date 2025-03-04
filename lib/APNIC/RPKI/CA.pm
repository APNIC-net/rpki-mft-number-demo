package APNIC::RPKI::CA;

use warnings;
use strict;

use DateTime;
use DateTime::Format::Strptime;
use Digest::SHA qw(sha256_hex);
use File::Slurp qw(read_file
                   write_file);
use File::Temp qw(tempdir);
use HTTP::Daemon;
use HTTP::Status qw(:constants);
use Net::IP;
use LWP::UserAgent;
use Storable;
use XML::LibXML;
use YAML;
use MIME::Base64 qw(encode_base64url
                    encode_base64);

use APNIC::RPKI::Manifest;
use APNIC::RPKI::OpenSSL;
use APNIC::RPKI::ROA;
use APNIC::RPKI::Utils qw(system_ad);

use constant CA_CONFIG_PARAMETERS => qw(dir ca
                                        root_ca_ext_extra
                                        ca_ext_extra
                                        signing_ca_ext_extra
                                        copy_extensions);

use constant CA_CONFIG => <<EOF;
[ default ]
ca                      = root-ca
dir                     = .

[ req ]
default_bits            = 2048
encrypt_key             = yes
default_md              = sha256
utf8                    = no
string_mask             = nombstr
prompt                  = no
distinguished_name      = ca_dn
req_extensions          = ca_reqext

[ ca_dn ]
commonName              = "root"

[ ca_reqext ]
keyUsage                = critical,keyCertSign,cRLSign
basicConstraints        = critical,CA:true
subjectKeyIdentifier    = hash

[ pqs ]
policyIdentifier        = 1.3.6.1.5.5.7.14.2

[ ca ]
default_ca              = root_ca

[ root_ca ]
certificate             = {dir}/ca/{ca}.crt
private_key             = {dir}/ca/{ca}/private/{ca}.key
new_certs_dir           = {dir}/ca/{ca}
serial                  = {dir}/ca/{ca}/db/{ca}.crt.srl
crlnumber               = {dir}/ca/{ca}/db/{ca}.crl.srl
database                = {dir}/ca/{ca}/db/{ca}.db
unique_subject          = no
default_days            = 3652
default_md              = sha256
policy                  = match_pol
email_in_dn             = no
preserve                = no
name_opt                = ca_default
cert_opt                = ca_default
copy_extensions         = {copy_extensions}
x509_extensions         = signing_ca_ext
default_crl_days        = 1
crl_extensions          = crl_ext

[ match_pol ]
commonName              = supplied

[ any_pol ]
domainComponent         = optional
countryName             = optional
stateOrProvinceName     = optional
localityName            = optional
organizationName        = optional
organizationalUnitName  = optional
commonName              = optional
emailAddress            = optional

[ root_ca_ext ]
keyUsage                = critical,keyCertSign,cRLSign
basicConstraints        = critical,CA:true
subjectKeyIdentifier    = hash
authorityKeyIdentifier  = keyid:always
certificatePolicies     = critical,\@pqs
{root_ca_ext_extra}

[ ca_ext ]
keyUsage                = critical,keyCertSign,cRLSign
basicConstraints        = critical,CA:true
subjectKeyIdentifier    = hash
{ca_ext_extra}

[ signing_ca_ext ]
keyUsage                = critical,digitalSignature
subjectKeyIdentifier    = hash
authorityKeyIdentifier  = keyid:always
certificatePolicies     = critical,\@pqs
{signing_ca_ext_extra}

[ ee_ext ]
keyUsage                = critical,digitalSignature
subjectKeyIdentifier    = hash

[ crl_ext ]
authorityKeyIdentifier  = keyid:always
EOF

use constant EE_CSR_FILENAME  => 'ee.csr';
use constant EE_CERT_FILENAME => 'ee.crt';
use constant EE_KEY_FILENAME  => 'ee.key';
use constant CRL_FILENAME     => 'crl.pem';

use constant ID_CT_MFT  => '1.2.840.113549.1.9.16.1.26';
use constant ID_CT_ROA  => '1.2.840.113549.1.9.16.1.24';

use constant ID_SIA_REPO         => '1.3.6.1.5.5.7.48.5';
use constant ID_SIA_MANIFEST     => '1.3.6.1.5.5.7.48.10';
use constant ID_SIA_RRDP         => '1.3.6.1.5.5.7.48.13';
use constant ID_SIA_SIGNEDOBJECT => '1.3.6.1.5.5.7.48.11';

our $DEBUG = 0;

our $VERSION = '0.1';

my $strp =
    DateTime::Format::Strptime->new(
        pattern   => '%FT%T',
        time_zone => 'UTC'
    );

sub new
{
    my $class = shift;

    my %args = @_;
    my $self = \%args;
    bless $self, $class;

    if (not $self->{'ca_path'}) {
        die "'ca_path' argument must be provided.";
    }
    if (not $self->{'openssl'}) {
        $self->{'openssl'} = APNIC::RPKI::OpenSSL->new();
    }

    return $self;
}

sub _chdir_ca
{
    my ($self) = @_;

    chdir $self->{'ca_path'} or die "$! (".$self->{'ca_path'}.")";

    return 1;
}

sub _system
{
    my (@args) = @_;

    my $cmd = join " ", @args;

    return system_ad($cmd, $DEBUG);
}

sub is_initialised
{
    my ($self) = @_;

    $self->_chdir_ca();

    return (-e "ca.cnf");
}

sub _generate_config
{
    my ($self, %parameters) = @_;

    $parameters{'copy_extensions'} ||= 'none';

    my $config = CA_CONFIG();
    my $ca_path = $self->{'ca_path'};
    $config =~ s/{dir}/$ca_path/g;
    $config =~ s/{ca}/ca/g;

    for my $key (keys %parameters) {
        my $value = $parameters{$key};
        $config =~ s/{$key}/$value/g;
    }

    for my $key (CA_CONFIG_PARAMETERS()) {
        $config =~ s/{$key}//g;
    }

    write_file('ca.cnf', $config);

    return 1;
}

sub initialise
{
    my ($self, $common_name, $key_only, $stg_repo_dir, $repo_dir,
        $repo_dirname, $host, $port, $ip_resources, $as_resources,
        $rrdp_dir, $rrdp_dirname, $rrdp_host, $rrdp_port) = @_;

    if (not defined $port) {
        $port = 873;
    }
    if (not $host or not $port or not $stg_repo_dir or not $repo_dir) {
        die "Expected extra arguments";
    }
    my $port_str = ($port == 873) ? "" : ":$port";
    my $host_and_port = $host.$port_str;

    if (not defined $rrdp_port) {
        $rrdp_port = 443;
    }
    if (not defined $rrdp_host) {
        $rrdp_host = "";
    }
    my $rrdp_port_str = ($rrdp_port == 443) ? "" : ":$rrdp_port";
    my $rrdp_host_and_port = $rrdp_host.$rrdp_port_str;

    $self->_chdir_ca();

    if ($self->is_initialised()) {
        die "CA has already been initialised.";
    }

    $self->_generate_config();

    for my $dir (qw(newcerts ca ca/ca ca/ca/private ca/ca/db)) {
        mkdir $dir or die $!;
    }
    for my $file (qw(ca/ca/db/ca.db ca/ca/db/ca.db.attr index.txt)) {
        _system("touch $file");
    }
    for my $serial_file (qw(ca.crt.srl ca.crl.srl)) {
        write_file("ca/ca/db/$serial_file", "01");
    }

    my $path = $self->{'ca_path'};
    my ($name) = ($path =~ /.*\/(.*)\/?/);

    my $openssl = $self->{'openssl'}->get_openssl_path();
    _system("$openssl genrsa -out ca/ca/private/ca.key 2048 >/dev/null 2>&1");
    my $key_data = read_file("ca/ca/private/ca.key");
    my $gski = $self->{'openssl'}->get_key_ski($key_data);
    # Leading hyphens can cause problems with command line calls.
    if ($gski =~ /^-/) {
        $gski = "Z".$gski;
    }

    my $stg_repo = $stg_repo_dir.'/'.$repo_dirname;
    mkdir $stg_repo or die $!;
    my $repo = $repo_dir.'/'.$repo_dirname;
    mkdir $repo or die $!;

    my $aia = undef;
    my $sia = ID_SIA_REPO().";URI:rsync://$host_and_port/repo/$repo_dirname/";
    my $mft_sia = ID_SIA_MANIFEST().";URI:rsync://$host_and_port/repo/$repo_dirname/$gski.mft";
    my $rrdp_sia = "";
    my $rrdp_session_id = "";
    $rrdp_dirname ||= "";
    if ($rrdp_dir) {
        $rrdp_sia = ID_SIA_RRDP().";URI:https://$rrdp_host_and_port/$rrdp_dirname/notification.xml";
        ($rrdp_session_id) = `uuidgen`;
        chomp $rrdp_session_id;
    }

    my $tal_path = "$repo_dir/$gski.tal";

    if (not $key_only) {
        my $extra = $self->_generate_sbgp_config($ip_resources, $as_resources);
        $extra = "subjectInfoAccess=$sia,$mft_sia".
                 ($rrdp_sia ? ",$rrdp_sia" : "")."\n".
                 $extra;
        $self->_generate_config(root_ca_ext_extra => $extra);

        _system("$openssl req -new -config ca.cnf -extensions root_ca_ext ".
                "-x509 -key ca/ca/private/ca.key -out ca/ca.crt -subj '/CN=$common_name'");
        _system("$openssl x509 -in ca/ca.crt -outform DER -out ca/ca.der.cer");
        _system("cp ca/ca.der.cer $repo_dir/$gski.cer");

        my $ft = File::Temp->new();
        my $fn = $ft->filename();
        my @key_data = `$openssl x509 -in ca/ca.crt -noout -pubkey`;
        shift @key_data;
        pop @key_data;
        my $kd_str = join '', @key_data;

        $aia = "rsync://$host_and_port/repo/$gski.cer";
        write_file($tal_path, <<EOF);
$aia

$kd_str
EOF
    }

    my $own_config = {
        name            => $name,
        host            => $host,
        port            => $port,
        host_and_port   => $host_and_port,
        repo_dirname    => $repo_dirname,
        stg_repo        => $stg_repo,
        repo            => $repo,
        self_signed     => (not $key_only),
        aia             => $aia,
        gski            => $gski,
        sia             => $sia,
        mft_sia         => $mft_sia,
        rrdp_sia        => $rrdp_sia,
        manifest_number => 0,
        mft_filename    => "$gski.mft",
        crl_filename    => "$gski.crl",
        ip_resources    => $ip_resources,
        as_resources    => $as_resources,
        common_name     => $common_name,
        repo_dir        => $repo_dir,
        rrdp_dir        => $rrdp_dir,
        rrdp_dirname    => $rrdp_dirname,
        rrdp_host       => $rrdp_host,
        rrdp_port       => $rrdp_port,
        rrdp_session_id => $rrdp_session_id,
        rrdp_serial     => 0,
        rsync_base      => "rsync://$host_and_port/repo/$repo_dirname",
        rrdp_base       => "https://$rrdp_host_and_port/$rrdp_dirname",
    };
    YAML::DumpFile('config.yml', $own_config);

    return ($key_only ? 1 : $tal_path);
}

sub update_mft_filename
{
    my ($self, $mft_filename) = @_;

    my $own_config = $self->get_config();
    $own_config->{'mft_filename'} = $mft_filename;
    my $host_and_port = $own_config->{'host_and_port'};
    my $name = $own_config->{'name'};
    my $repo_dirname = $own_config->{'repo_dirname'};
    my $mft_sia = ID_SIA_MANIFEST().";URI:rsync://$host_and_port/repo/$repo_dirname/$mft_filename";
    $own_config->{'mft_sia'} = $mft_sia;

    my $ip_resources = $own_config->{'ip_resources'};
    my $as_resources = $own_config->{'as_resources'};
    my $extra = $self->_generate_sbgp_config($ip_resources, $as_resources);
    my $sia = ID_SIA_REPO().";URI:rsync://$host_and_port/repo/$repo_dirname/";
    $extra = "subjectInfoAccess=$sia,$mft_sia\n$extra";
    $self->_generate_config(root_ca_ext_extra => $extra);

    my $common_name = $own_config->{'common_name'};
    my $repo_dir = $own_config->{'repo_dir'};
    my $gski = $own_config->{'gski'};

    my $openssl = $self->{'openssl'}->get_openssl_path();
    _system("$openssl req -new -config ca.cnf -extensions root_ca_ext ".
	    "-x509 -key ca/ca/private/ca.key -out ca/ca.crt -subj '/CN=$common_name'");
    _system("$openssl x509 -in ca/ca.crt -outform DER -out ca/ca.der.cer");
    _system("cp ca/ca.der.cer $repo_dir/$gski.cer");

    $self->_chdir_ca();
    YAML::DumpFile('config.yml', $own_config);

    return 1;
}

sub get_config
{
    my ($self) = @_;

    $self->_chdir_ca();
    return YAML::LoadFile('config.yml');
}

sub get_cert_rsync_url
{
    my ($self) = @_;

    my $own_config = YAML::LoadFile('config.yml');
    return $own_config->{'aia'};
}

sub get_ca_request
{
    my ($self, $common_name, $ip_resources, $as_resources) = @_;

    $self->_chdir_ca();

    my $own_config = $self->get_config();
    my $sia = $own_config->{'sia'};
    my $mft_sia = $own_config->{'mft_sia'};
    my $rrdp_sia = $own_config->{'rrdp_sia'};
    my $extra = $self->_generate_sbgp_config($ip_resources, $as_resources);
    $extra = "subjectInfoAccess=$sia,$mft_sia".
             ($rrdp_sia ? ",$rrdp_sia" : "")."\n".
             $extra;
    $self->_generate_config(ca_ext_extra => $extra);

    my $openssl = $self->{'openssl'}->get_openssl_path();
    _system("$openssl req -new ".
            "-config ca.cnf -reqexts ca_ext ".
            "-key ca/ca/private/ca.key ".
            "-out ca/ca.req -subj '/CN=$common_name'");

    my $data = read_file('ca/ca.req');
    return $data;
}

sub _generate_sbgp_config
{
    my ($self, $ip_resources, $as_resources) = @_;

    my $ipv4_index = 0;
    my $ipv6_index = 0;

    my @ip_lines;
    if ((ref $ip_resources) eq 'ARRAY') {
        for my $ip_resource (@{$ip_resources}) {
            my $type = Net::IP->new($ip_resource)->version();
            if ($type == 4) {
                push @ip_lines, "IPv4.$ipv4_index = $ip_resource";
                $ipv4_index++;
            } else {
                push @ip_lines, "IPv6.$ipv6_index = $ip_resource";
                $ipv6_index++;
            }
        }
    } elsif (not defined $ip_resources) {
        @ip_lines = (
            'IPv4 = inherit',
            'IPv6 = inherit'
        );
    }

    my $ip_content =
        (@ip_lines)
            ? "[ ip-section ]\n".(join "\n", @ip_lines)."\n\n"
            : "";

    my $as_index = 0;
    my @as_lines;
    if ((ref $as_resources) eq 'ARRAY') {
        for my $as_resource (@{$as_resources}) {
            push @as_lines, "AS.$as_index = $as_resource";
            $as_index++;
        }
    } elsif (not defined $as_resources) {
        @as_lines = (
            'AS = inherit'
        );
    }

    my $as_content =
        (@as_lines)
            ? "[ as-section ]\n".(join "\n", @as_lines)."\n\n"
            : "";

    my @preliminary = (
        ((@ip_lines)
            ? 'sbgp-ipAddrBlock = critical, @ip-section'
            : ''),
        ((@as_lines)
            ? 'sbgp-autonomousSysNum = critical, @as-section'
            : '')
    );

    my $result =
        join "\n",
            ((@preliminary), "\n", $ip_content, $as_content);
    return $result;
}

sub mod_gutmannize
{
    my $data = shift
        or return;

    $data or return '';

    my $base64url_data = encode_base64url($data);
    my $output         = $base64url_data;
    chomp $output;
    $output =~ s/=$//;

    return $output;
}

sub sign_ca_request
{
    my ($self, $request, $ip_resources, $as_resources) = @_;

    $self->_chdir_ca();

    my $ft_request = File::Temp->new();
    print $ft_request $request;
    $ft_request->flush();
    my $fn_request = $ft_request->filename();

    $ip_resources ||= [];
    $as_resources ||= [];

    my $extra = $self->_generate_sbgp_config($ip_resources, $as_resources);
    my $openssl = $self->{'openssl'}->get_openssl_path();

    my @req_pubkey = `$openssl req -in $fn_request -pubkey -noout`;
    chomp for @req_pubkey;
    my $req_pubkey_str = join '', @req_pubkey;
    my @ca_pubkey = `$openssl x509 -in ca/ca.crt -pubkey -noout`;
    chomp for @ca_pubkey;
    my $ca_pubkey_str = join '', @ca_pubkey;

    my $own_config = YAML::LoadFile('config.yml');
    my $aia = $own_config->{'aia'};
    my $gski = $own_config->{'gski'};
    my $crl_filename = $own_config->{'crl_filename'};
    my $host_and_port = $own_config->{'host_and_port'};
    my $repo_dirname = $own_config->{'repo_dirname'};
    my $stg_repo = $own_config->{'stg_repo'};

    my $path = $self->{'ca_path'};
    my ($name) = ($path =~ /.*\/(.*)\/?/);

    if ($req_pubkey_str ne $ca_pubkey_str) {
        $extra = 'authorityInfoAccess=caIssuers;URI:'.
                 "$aia\n".
                 'crlDistributionPoints=URI:'.
                 "rsync://$host_and_port/repo/$repo_dirname/$crl_filename\n".
                  $extra;
    }

    $self->_generate_config(root_ca_ext_extra => $extra,
                            copy_extensions   => 'copy');

    my $ft_output = File::Temp->new();
    my $fn_output = $ft_output->filename();

    _system("$openssl ca -batch -config ca.cnf -extensions root_ca_ext ".
            "-out $fn_output ".
            "-in $fn_request -days 365");

    my $data = read_file($fn_output);
    my $ski = $self->{'openssl'}->get_ski($data);
    my $bin_ski = pack('H*', $ski);
    my $cert_gski = mod_gutmannize($bin_ski);

    _system("$openssl x509 -in $fn_output -inform PEM -outform DER ".
            "-out $stg_repo/$cert_gski.cer");
    $self->publish();

    return ($data, "rsync://$host_and_port/repo/$repo_dirname/$cert_gski.cer");
}

sub install_ca_certificate
{
    my ($self, $certificate, $aia) = @_;

    $self->_chdir_ca();

    my $ft_cert = File::Temp->new();
    print $ft_cert $certificate;
    $ft_cert->flush();
    my $fn_cert = $ft_cert->filename();

    my $openssl = $self->{'openssl'}->get_openssl_path();
    _system("$openssl x509 -in $fn_cert -out ca/ca.crt");
    _system("$openssl x509 -in ca/ca.crt -outform DER -out ca/ca.der.cer");

    my ($gski) = ($aia =~ /.*\/(.*).cer/);
    my $own_config = YAML::LoadFile('config.yml');
    $own_config->{'aia'} = $aia;
    $own_config->{'gski'} = $gski;
    my $host_and_port = $own_config->{'host_and_port'};
    my $repo_dirname = $own_config->{'repo_dirname'};

    my $path = $self->{'ca_path'};
    my ($name) = ($path =~ /.*\/(.*)\/?/);

    $own_config->{'mft_sia'} =
        ID_SIA_MANIFEST().";URI:rsync://$host_and_port/repo/$repo_dirname/$gski.mft";

    YAML::DumpFile('config.yml', $own_config);

    return 1;
}

sub revoke_current_ee_certificate
{
    my ($self) = @_;

    $self->_chdir_ca();

    if (-e "ee.crt") {
        my $openssl = $self->{'openssl'}->get_openssl_path();
        _system("$openssl ca -batch -config ca.cnf ".
                "-revoke ".EE_CERT_FILENAME());
    }

    return 1;
}

sub issue_new_ee_key
{
    my ($self) = @_;

    $self->_chdir_ca();

    my $openssl = $self->{'openssl'}->get_openssl_path();
    _system("$openssl genrsa ".
            "-out ".EE_KEY_FILENAME()." 2048");

    return 1;
}

sub issue_new_ee_certificate
{
    my ($self, $ip_resources, $as_resources, $sias,
        $start_date, $expiry_date) = @_;

    $start_date  ||= DateTime->now(time_zone => 'UTC');
    $expiry_date ||= $start_date->clone()->add(years => 1); 

    $self->_chdir_ca();

    my $own_config = YAML::LoadFile('config.yml');
    my $aia = $own_config->{'aia'};
    my $gski = $own_config->{'gski'};
    my $crl_filename = $own_config->{'crl_filename'};
    my $host_and_port = $own_config->{'host_and_port'};
    my $repo_dirname = $own_config->{'repo_dirname'};

    my $extra = $self->_generate_sbgp_config($ip_resources, $as_resources);
    my $path = $self->{'ca_path'};
    my ($name) = ($path =~ /.*\/(.*)\/?/);
    $extra = 'authorityInfoAccess=caIssuers;URI:'.
             "$aia\n".
             'crlDistributionPoints=URI:'.
             "rsync://$host_and_port/repo/$repo_dirname/$crl_filename\n".
             ($sias ? 'subjectInfoAccess='.(join ',', @{$sias})."\n" : '').
             $extra;

    $self->_generate_config(signing_ca_ext_extra => $extra);

    my $openssl = $self->{'openssl'}->get_openssl_path();
    my ($cn) = `uuidgen`;
    chomp $cn;
    _system("$openssl req -new ".
            "-config ca.cnf -extensions ee_ext ".
            "-key ".EE_KEY_FILENAME()." ".
            "-out ".EE_CSR_FILENAME()." ".
            "-subj '/CN=$cn'");
    _system("$openssl ca -batch -config ca.cnf ".
            "-out ".EE_CERT_FILENAME()." ".
            "-extensions signing_ca_ext ".
            "-in ".EE_CSR_FILENAME()." -days 365");

    my $data = read_file(EE_CERT_FILENAME());

    return $data;
}

sub make_random_string
{
    my @chars = ('a'..'z', 0..9);

    return join '', map { $chars[int(rand(@chars))] } (1..8);
}

sub issue_roa
{
    my ($self, $prefixes, $asn, $sia) = @_;

    $self->_chdir_ca();
    my $own_config = YAML::LoadFile('config.yml');

    my %ip_resources;
    my $roa = APNIC::RPKI::ROA->new();
    $roa->prefix_objects([]);
    for my $prefix (split /\s*,\s*/, $prefixes) {
        my ($p, $ml) = split /-/, $prefix;
        $ip_resources{$p} = 1;
        my $prefix_obj = {
            'prefix'     => $p,
            'max-length' => $ml,
        };
        push @{$roa->prefix_objects()}, $prefix_obj;
    }
    $roa->as_id($asn);

    my $host_and_port = $own_config->{'host_and_port'};
    my $repo_dirname = $own_config->{'repo_dirname'};
    my $name = $own_config->{'name'};
    $self->issue_new_ee_key();
    my $key_data = read_file(EE_KEY_FILENAME());
    my $gski = $self->{'openssl'}->get_key_ski($key_data);
    # Leading hyphens can cause problems with command line calls.
    if ($gski =~ /^-/) {
        $gski = "Z".$gski;
    }
    my $roa_filename = "$gski.roa";
    if (not defined $sia) {
        $sia =
            ID_SIA_SIGNEDOBJECT().";URI:rsync://$host_and_port".
                                  "/repo/$repo_dirname/$roa_filename";
    }

    my @ip_resources_list = keys %ip_resources;
    $self->issue_new_ee_certificate(\@ip_resources_list, [], [$sia]);

    my $stg_repo = $own_config->{'stg_repo'};
    my $roa_proper = $self->sign_cms($roa->encode(), ID_CT_ROA());
    write_file("$stg_repo/$roa_filename", $roa_proper);

    return 1;
}

sub issue_crl
{
    my ($self, $crl_number, $crl_filename,
        $crl_last_update_arg, $crl_next_update_arg) = @_;

    $self->_chdir_ca();

    if (defined $crl_number) {
        my $crlnum_path = "ca/ca/db/ca.crl.srl";
        my $crl_number_bi = Math::BigInt->new($crl_number);
        my $new_crlnum = $crl_number_bi->as_hex();
        $new_crlnum =~ s/^0x//;
        my $len = length($new_crlnum);
        if (($len % 2) != 0) {
            $new_crlnum = "0$new_crlnum";
        }
        write_file($crlnum_path, $new_crlnum);
    }

    my $crl_last_update;
    if ($crl_last_update_arg) {
        $crl_last_update = $strp->parse_datetime($crl_last_update_arg);
        if (not $crl_last_update) {
            die "'$crl_last_update_arg' is not a valid datetime string";
        }
    } else {
        $crl_last_update = DateTime->now(time_zone => 'UTC');
    }

    my $crl_next_update;
    if ($crl_next_update_arg) {
        $crl_next_update = $strp->parse_datetime($crl_next_update_arg);
        if (not $crl_next_update) {
            die "'$crl_next_update_arg' is not a valid datetime string";
        }
    } else {
        $crl_next_update = $crl_last_update->clone()->add(days => 1);
    }

    my $openssl = $self->{'openssl'}->get_openssl_path();
    my $crl_last_update_str = $crl_last_update->strftime('%Y%m%d%H%M%SZ');
    my $crl_next_update_str = $crl_next_update->strftime('%Y%m%d%H%M%SZ');
    _system("$openssl ca -batch -crlexts crl_ext -config ca.cnf -gencrl ".
            "-out ".CRL_FILENAME().
            " -crl_lastupdate $crl_last_update_str ".
            " -crl_nextupdate $crl_next_update_str");
    _system("$openssl crl -in ".CRL_FILENAME()." -outform DER -out ".
            "crl.der.crl");

    my $own_config = YAML::LoadFile('config.yml');
    my $aia = $own_config->{'aia'};
    my $gski = $own_config->{'gski'};
    if ($crl_filename) {
        $own_config->{'crl_filename'} = $crl_filename;
        YAML::DumpFile('config.yml', $own_config);
    }
    $crl_filename = $own_config->{'crl_filename'};
    my $stg_repo = $own_config->{'stg_repo'};

    system("cp crl.der.crl $stg_repo/$crl_filename");

    return 1;
}

sub get_crl
{
    my ($self) = @_;

    $self->_chdir_ca();

    my $data = read_file(CRL_FILENAME());
    return $data;
}

sub get_ee
{
    my ($self) = @_;

    $self->_chdir_ca();

    my $data = read_file(EE_CERT_FILENAME());
    return $data;
}

sub issue_manifest
{
    my ($self, $mft_number, $mft_filename,
        $this_update_arg, $next_update_arg) = @_;

    if ($mft_filename) {
        $self->update_mft_filename($mft_filename);
    }
    my $own_config = YAML::LoadFile('config.yml');
    my $new_mft_filename = $own_config->{'mft_filename'};

    my $this_update;
    if ($this_update_arg) {
        $this_update = $strp->parse_datetime($this_update_arg);
        if (not $this_update) {
            die "'$this_update_arg' is not a valid datetime string";
        }
    } else {
        $this_update = DateTime->now(time_zone => 'UTC');
    }
    my $next_update;
    if ($next_update_arg) {
        $next_update = $strp->parse_datetime($next_update_arg);
        if (not $next_update) {
            die "'$next_update_arg' is not a valid datetime string";
        }
    } else {
        $next_update = $this_update->clone()->add(days => 1);
    }

    my $sia = $own_config->{'mft_sia'};
    $sia =~ s/\.10;/.11;/;
    $self->issue_new_ee_key();
    $self->issue_new_ee_certificate(undef, undef, [$sia],
                                    $this_update, $next_update);
    my $aia = $own_config->{'aia'};

    if (defined $mft_number) {
        $own_config->{'manifest_number'} = $mft_number;
    } else {
        $own_config->{'manifest_number'}++;
    }
    my $manifest_number = $own_config->{'manifest_number'};

    my $stg_repo = $own_config->{'stg_repo'};
    my @files = `ls $stg_repo`;
    chomp for @files;
    my @mft_files;
    for my $file (@files) {
        if ($file =~ /\.mft$/) {
            next;
        }
        my ($ss) = `sha256sum $stg_repo/$file`;
        chomp $ss;
        $ss =~ s/ .*//;
        push @mft_files, {
            filename => $file,
            hash => pack('H*', $ss)
        };
    }

    my $mft = APNIC::RPKI::Manifest->new();
    $mft->manifest_number($manifest_number);
    $mft->this_update($this_update);
    $mft->next_update($next_update);
    $mft->files(\@mft_files);

    my $mft_proper = $self->sign_cms($mft->encode(), ID_CT_MFT());
    write_file("$stg_repo/$new_mft_filename", $mft_proper);
    YAML::DumpFile('config.yml', $own_config);

    return 1;
}

sub publish_file
{
    my ($self, $filename, $data) = @_;

    my $own_config = YAML::LoadFile('config.yml');
    my $stg_repo = $own_config->{'stg_repo'};
    write_file("$stg_repo/$filename", $data);

    return 1;
}

sub dir_to_rrdp_data
{
    my ($rsync_base, $dir) = @_;

    my @files = map { chomp; s/.*\//\//; $_ } `ls $dir`;
    my %data;
    for my $file (@files) {
        my $path    = "$dir/$file";
        my $content = read_file($path);
        my $b64e    = encode_base64($content);
        my $hash    = sha256_hex($content);

        my $uri  = "$rsync_base/$file";
        $data{$file} = {
            file => $file,
            uri  => $uri,
            b64e => $b64e,
            hash => $hash,
        };
    }
    return \%data;
}

sub publish
{
    my ($self, $mft_number, $mft_filename,
        $this_update_arg, $next_update_arg,
        $crl_number, $crl_filename,
        $crl_last_update_arg, $crl_next_update_arg) = @_;

    $self->issue_crl($crl_number, $crl_filename,
                     $crl_last_update_arg, $crl_next_update_arg);
    $self->issue_manifest($mft_number, $mft_filename,
                          $this_update_arg, $next_update_arg);

    $self->_chdir_ca();
    my $own_config = YAML::LoadFile('config.yml');
    my $stg_repo = $own_config->{'stg_repo'};

    my $aia  = $own_config->{'aia'};
    my $gski = $own_config->{'gski'};
    my $repo = $own_config->{'repo'};

    my $rrdp_dir = $own_config->{'rrdp_dir'};
    if ($rrdp_dir) {
        my $rrdp_dirname = $own_config->{'rrdp_dirname'};
        my $rrdp_base_dir = "$rrdp_dir/$rrdp_dirname";
        system("mkdir -p $rrdp_base_dir");
        my $session_id = $own_config->{'rrdp_session_id'};
        $own_config->{'rrdp_serial'}++;
        my $serial = $own_config->{'rrdp_serial'};
        my $rrdp_base = $own_config->{'rrdp_base'};
        my $rsync_base = $own_config->{'rsync_base'};

        my %current_data = %{dir_to_rrdp_data($rsync_base, $repo)};
        my %staging_data = %{dir_to_rrdp_data($rsync_base, $stg_repo)};

        my @delta_data;
        if ($serial > 1) {
            for my $cd_entry (values %current_data) {
                my $file = $cd_entry->{'file'};
                my $sd_entry = $staging_data{$file};
                if (not $sd_entry) {
                    my $uri  = $cd_entry->{'uri'};
                    my $hash = $cd_entry->{'hash'};
                    push @delta_data,
                         "<withdraw uri=\"$uri\" ".
                            "hash=\"$hash\" />";
                } else {
                    my $uri     = $sd_entry->{'uri'};
                    my $b64e    = $sd_entry->{'b64e'};
                    my $cd_hash = $cd_entry->{'hash'};
                    push @delta_data,
                         "<publish uri=\"$uri\" ".
                            "hash=\"$cd_hash\">$b64e</publish>";
                }
            }
            for my $sd_entry (values %staging_data) {
                my $file = $sd_entry->{'file'};
                my $cd_entry = $current_data{$file};
                if (not $cd_entry) {
                    my $uri  = $sd_entry->{'uri'};
                    my $b64e = $sd_entry->{'b64e'};
                    push @delta_data,
                         "<publish uri=\"$uri\">$b64e</publish>";
                }
            }
            if (not @delta_data) {
                goto post_rrdp;
            }
            my $delta_content = <<EOF;
<delta version="1"
       session_id="$session_id"
       serial="$serial"
       xmlns="http://www.ripe.net/rpki/rrdp">
    @delta_data
</delta>
EOF
            write_file("$rrdp_base_dir/$serial.xml", $delta_content);
        }

        my @ss_publishes =
            map { my $uri = $_->{'uri'};
                  my $b64e = $_->{'b64e'};
                  "<publish uri=\"$uri\">\n$b64e\n</publish>\n" }
                values %staging_data;
        my $ss_content = <<EOF;
<snapshot version="1"
          session_id="$session_id"
          serial="$serial"
          xmlns="http://www.ripe.net/rpki/rrdp">
    @ss_publishes
</snapshot>
EOF
        write_file("$rrdp_base_dir/snapshot.xml", $ss_content);

        my @nds =
            map { my $d = $_;
                  my $data = read_file("$rrdp_base_dir/$d.xml");
                  my $h = sha256_hex($data);
                  "<delta serial=\"$d\" uri=\"$rrdp_base/$d.xml\" ".
                         "hash=\"$h\" />\n" }
                (reverse(2..$serial));

        my $ss_hash = sha256_hex($ss_content);
        my $notification_content = <<EOF;
<notification version="1"
              session_id="$session_id"
              serial="$serial"
              xmlns="http://www.ripe.net/rpki/rrdp">
    <snapshot uri="$rrdp_base/snapshot.xml"
              hash="$ss_hash" />
    @nds
</notification>
EOF
        write_file("$rrdp_base_dir/notification.xml",
                   $notification_content);
    }
    post_rrdp:

    my $res = system("rm -f $repo/*");
    if ($res != 0) {
        die "Unable to clear current repository state";
    }
    $res = system("cp $stg_repo/* $repo/");
    if ($res != 0) {
        die "Unable to copy staging state to repository";
    }
    $res = system("rm -f $stg_repo/*");
    if ($res != 0) {
        die "Unable to clear current staging repository state";
    }

    YAML::DumpFile('config.yml', $own_config);

    return 1;
}

sub sign_cms
{
    my ($self, $input, $content_type) = @_;

    $self->_chdir_ca();

    my $ft_input = File::Temp->new();
    print $ft_input $input;
    $ft_input->flush();
    my $fn_input = $ft_input->filename();

    my $ft_output= File::Temp->new();
    my $fn_output = $ft_output->filename();

    my $openssl = $self->{'openssl'}->get_openssl_path();
    my $res = _system("$openssl cms -sign -nodetach -binary -outform DER ".
                      "-nosmimecap ".
                      "-keyid -md sha256 -econtent_type $content_type ".
                      "-signer ".EE_CERT_FILENAME()." ".
                      "-inkey ".EE_KEY_FILENAME()." ".
                      "-in $fn_input -out $fn_output");

    return read_file($fn_output);
}

sub get_ca_pem
{
    my ($self) = @_;

    $self->_chdir_ca();

    my @lines = read_file('ca/ca.crt');

    pop @lines;
    shift @lines;

    my $bpki_ta = join '', @lines;
    chomp $bpki_ta;

    return $bpki_ta;
}

sub get_issuer
{
    my ($self) = @_;

    $self->_chdir_ca();

    my $openssl_path = $self->{'openssl'}->{'path'};
    my ($issuer) = `$openssl_path x509 -in ca/ca.crt -noout -issuer`;
    chomp $issuer;
    $issuer =~ s/.*=//;
    return $issuer;
}

sub get_subject
{
    my ($self) = @_;

    $self->_chdir_ca();

    my $openssl_path = $self->{'openssl'}->{'path'};
    my ($subject) = `$openssl_path x509 -in ca/ca.crt -noout -subject`;
    chomp $subject;
    $subject =~ s/.*=//;
    return $subject;
}

1;
