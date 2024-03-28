package APNIC::RPKI::ROA;

use warnings;
use strict;

use Convert::ASN1;
use Digest::SHA qw(sha256);
use DateTime;
use Net::IP::XS qw(ip_bintoip);

use constant ID_SMIME  => '1.2.840.113549.1.9.16';
use constant ID_CT     => ID_SMIME . '.1';
use constant ID_CT_ROA => ID_CT . '.24';

use constant ID_SHA256 => '2.16.840.1.101.3.4.2.1';

use constant ROA_VERSION_DEFAULT => 0;

use constant ROA_ASN1 => q(
  RouteOriginAttestation ::= SEQUENCE {
     version [0] INTEGER OPTIONAL, -- DEFAULT 0,
     asID  ASID,
     ipAddrBlocks SEQUENCE OF ROAIPAddressFamily }

  ASID ::= INTEGER

  ROAIPAddressFamily ::= SEQUENCE {
     addressFamily OCTET STRING, -- (SIZE (2..3)),
     addresses SEQUENCE OF ROAIPAddress }

  ROAIPAddress ::= SEQUENCE {
    address IPAddress,
    maxLength INTEGER OPTIONAL }

  IPAddress ::= BIT STRING
);

use base qw(Class::Accessor);
APNIC::RPKI::ROA->mk_accessors(qw(
    version
    as_id
    prefix_objects
));

my %afi2fam = (
    "\x00\x01" => '4',
    "\x00\x02" => '6',
);

my %fam2afi = reverse(%afi2fam);

sub new
{
    my ($class) = @_;

    my $parser = Convert::ASN1->new();
    $parser->configure(
        encoding => "DER",
        encode   => { time => "utctime" },
        decode   => { time => "utctime" },
        tagdefault => 'EXPLICIT',
    );
    my $res = $parser->prepare(ROA_ASN1());
    if (not $res) {
        die $parser->error();
    }
    $parser = $parser->find('RouteOriginAttestation');

    my $self = { parser => $parser };
    bless $self, $class;
    return $self;
}

sub _decode_ipaddr
{
    my ($fam, $roa_addr, $fill) = @_;

    my $addr   = $roa_addr->{'address'};
    my $maxlen = $roa_addr->{'maxLength'};

    my $famlen = ($fam == 4 ? 32 : 128);

    my $plen = $addr->[1];
    my $flen = $famlen - $plen;
    my $val = unpack("B$plen", $addr->[0]).($fill x $flen);
    my $ip = ip_bintoip($val, $fam);
    $ip .= '/'.$plen;

    return {
        prefix => $ip,
        ((defined $maxlen)
            ? ('max-length' => $maxlen)
            : ())
    };
}

sub _decode_ipaddr_family
{
    my ($ipaddr) = @_;

    my $afi = substr($ipaddr->{'addressFamily'}, 0, 2);
    my $safi = substr($ipaddr->{'addressFamily'}, 2);
    if ($safi) {
        die "No SAFI allowed";
    }

    my $fam = $afi2fam{$afi};
    if (not $fam) {
        die "Unsupported AFI";
    }

    my @result;
    foreach my $i (@{$ipaddr->{addresses}}) {
        push @result, _decode_ipaddr($fam, $i, 0);
    }

    return @result;
}

sub decode
{
    my ($self, $roa) = @_;

    my $parser = $self->{'parser'};
    my $data = $parser->decode($roa);
    if (not $data) {
        die $parser->error();
    }

    $self->version($data->{'version'});
    $self->as_id($data->{'asID'});
    $self->prefix_objects([]);

    for my $ip_blk (@{$data->{'ipAddrBlocks'}}) {
        push @{$self->prefix_objects()},
             _decode_ipaddr_family($ip_blk);
    }

    return $roa;
}

sub _match_bits_from_end
{
    my ($val, $from, $match) = @_;

    my $bit = 0;

    my $len = length($val) - 1;

    for ($bit = $len; $bit >= $from ; $bit--) {
        if (substr($val, $bit, 1) ne $match) {
            return ($bit);
        }
    }

    return $bit;
}

sub _bin_string_to_num
{
    my ($val) = @_;

    my $len  = length($val) - 1;
    my $xval = 0;
    my $pval = 0;

    for ( my $i = 0 ; $i <= $len ; $i++ ) {
        $xval = $pval << 1;
        $pval = ($xval + ((substr($val, $i, 1) eq "1") ? 1 : 0));
    }

    return $pval;
}

sub _encode_ipaddr
{
    my ($val, $zlen) = @_;

    my $dval;
    my $octets = do { use integer; ( $zlen + 7 ) / 8 };

    for (my $i = 0; $i < $octets; $i++) {
        my $oct = substr($val, $i * 8, 8);
        my $bval = _bin_string_to_num($oct);
        $dval .= chr($bval);
    }

    return [$dval, $zlen];
}

sub _match_length
{
    my ($lhs, $rhs) = @_;

    my $bit;

    my $len = length($lhs);
    $len == length($rhs)
        or die "both binary strings must have the same length";

    $len--;
    for ($bit = 0; $bit <= $len; $bit++) {
        if (substr($lhs, $bit, 1) ne substr($rhs, $bit, 1)) {
            return $bit;
        }
    }

    return $bit;
}

sub _encode_prefix
{
    my ($ip) = @_;

    my $result;

    my $fam = ($ip =~ /\./ ? 4 : 6);

    my $type = "ipv$fam";

    my $net_ip = Net::IP::XS->new($ip);
    my $sbits = $net_ip->binip();
    my $ebits = $net_ip->last_bin();
    my $size  = length($ebits);

    my $en = _match_length($sbits, $ebits);

    substr($sbits, $en) =~ /^0*$/ and substr($ebits, $en) =~ /^1*$/
        or die "not a CIDR prefix: ".$net_ip->print();

    my $zeropos = _match_bits_from_end($sbits, $en, 0);

    return _encode_ipaddr($sbits, $zeropos + 1);
}

sub encode
{
    my ($self) = @_;

    my %prefixes;
    for my $prefix_object (@{$self->prefix_objects()}) {
        my $prefix = $prefix_object->{'prefix'};
        my $max_length = $prefix_object->{'max-length'};
        if (not defined $max_length) {
            ($max_length) = ($prefix =~ /.*\/(\d+)$/);
        }

        my $version = ($prefix =~ /\./) ? 4 : 6;
        my $afi = $fam2afi{$version};

        my %data = (
            address => _encode_prefix($prefix)
        );

        if (defined $max_length) {
            $data{maxLength} = $max_length;
        }

        push @{$prefixes{$afi}}, \%data;
    }

    my @blocks;
    for my $afi (sort keys %prefixes) {
        push @blocks,
             { addressFamily => $afi,
               addresses     => $prefixes{$afi} };
    }

    my $parser = $self->{'parser'};

    my @data = (
        asID         => $self->as_id(),
        ipAddrBlocks => \@blocks,
    );

    my $roa = $parser->encode(@data);
    if (not $roa) {
        die $parser->error();
    }

    return $roa;
}

1;
