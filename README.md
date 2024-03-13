## rpki-mft-number-demo

For demonstrating how RPKI validators handle specific manifest
numbers and related transitions.  See
[draft-harrison-sidrops-manifest-numbers](https://datatracker.ietf.org/doc/draft-harrison-sidrops-manifest-numbers/).

### Build

    $ docker build -t apnic/rpki-mft-number-demo .

### Usage

    $ docker run -it apnic/rpki-mft-number-demo /bin/bash

#### rpki-client

##### Manifest number decrease

    # /sbin/service rsync start
    # setup-ca --name ta --resources 1234
    writing RSA key
    TAL path: /data/repo/005995B51ECFB445FDF5A3038A7472F5CD48BE6C.tal
    TAL path written to /last-tal-path
    # init-validator /tmp/test last-tal-path rpki-client 9.0
    # run-validator /tmp/test
    # reissue-crl-and-mft --name ta --mft-number 3
    # run-validator /tmp/test
    # reissue-crl-and-mft --name ta --mft-number 2
    # run-validator /tmp/test
    rpki-client: .rsync/localhost/repo/ta/005995B51ECFB445FDF5A3038A7472F5CD48BE6C.mft: unexpected manifest number (want >= #03, got #02)
    rpki-client: localhost/repo/ta/005995B51ECFB445FDF5A3038A7472F5CD48BE6C.mft#03: bad message digest for 005995B51ECFB445FDF5A3038A7472F5CD48BE6C.mft
    rpki-client: localhost/repo/ta/005995B51ECFB445FDF5A3038A7472F5CD48BE6C.mft: no valid manifest available
    #

##### Manifest number reaches largest value

    # /sbin/service rsync start
    # setup-ca --name ta --resources 1234
    writing RSA key
    TAL path: /data/repo/283DF6F22488B083BEFC00E2CA93BAE8F5B8FE53.tal
    TAL path written to /last-tal-path
    # init-rpki-client /tmp/test last-tal-path 9.0
    # run-rpki-client /tmp/test
    # reissue-crl-and-mft --name ta --mft-number 1461501637330902918203684832716283019655932542975
    # run-rpki-client /tmp/test
    # reissue-crl-and-mft --name ta --mft-number 1461501637330902918203684832716283019655932542975
    # run-rpki-client /tmp/test
    rpki-client: .rsync/localhost/repo/ta/283DF6F22488B083BEFC00E2CA93BAE8F5B8FE53.mft: manifest issued at 1710310280 and 1710310273 with same manifest number #FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
    rpki-client: localhost/repo/ta/283DF6F22488B083BEFC00E2CA93BAE8F5B8FE53.mft#FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF: bad message digest for 283DF6F22488B083BEFC00E2CA93BAE8F5B8FE53.mft
    rpki-client: localhost/repo/ta/283DF6F22488B083BEFC00E2CA93BAE8F5B8FE53.mft: no valid manifest available
    #

##### Manifest number too large

    # /sbin/service rsync start
    # setup-ca --name ta --resources 1234
    writing RSA key
    TAL path: /data/repo/1638FC53CD18243FB1BBCCB3910D57280CD82CC6.tal
    TAL path written to /last-tal-path
    # init-rpki-client /tmp/test last-tal-path 9.0
    # run-rpki-client /tmp/test
    # reissue-crl-and-mft --name ta --mft-number 1461501637330902918203684832716283019655932542976
    # run-rpki-client /tmp/test
    rpki-client: x509_convert_seqnum: .rsync/localhost/repo/ta/1638FC53CD18243FB1BBCCB3910D57280CD82CC6.mft: want 20 octets or fewer, have more.
    #

#### FORT

##### Manifest number too large

    # /sbin/service rsync start
    # setup-ca --name ta --resources 1234
    writing RSA key
    TAL path: /data/repo/A0492AB066B5D8E301221AE29787ACD8026635F9.tal
    TAL path written to /last-tal-path
    # init-fort /tmp/test last-tal-path 1.6.1
    # run-fort /tmp/test
    # reissue-crl-and-mft --name ta --mft-number 1461501637330902918203684832716283019655932542976
    # run-fort /tmp/test
    Mar 13 04:38:47 ERR: /tmp/test/tals/tal.tal: None of the URIs of the TAL '/tmp/test/tals/tal.tal' yielded a successful traversal.
    Mar 13 04:38:47 WRN: Validation from TAL '/tmp/test/tals/tal.tal' yielded error -22 (Invalid argument); discarding all validation results.
    Mar 13 04:38:47 ERR: Validation unsuccessful; results unusable.
    #

#### Routinator

##### Manifest number too large

    # /sbin/service rsync start
    # setup-ca --name ta --resources 1234
    writing RSA key
    TAL path: /data/repo/1BD16657AF8350D29CCFF67592AE199DD352A035.tal
    TAL path written to /last-tal-path
    # init-routinator /tmp/test last-tal-path 0.13.2
    # run-routinator /tmp/test
    # reissue-crl-and-mft --name ta --mft-number 1461501637330902918203684832716283019655932542976
    # run-routinator /tmp/test
    [2024-03-13T05:05:23] [WARN] rsync://localhost/repo/ta/1BD16657AF8350D29CCFF67592AE199DD352A035.mft: failed to decode manifest.
    #

#### OctoRPKI

##### Manifest number too large

    # /sbin/service rsync start
    # setup-ca --name ta --resources 1234
    writing RSA key
    TAL path: /data/repo/307AAE1C246A49E53CDCB39B00CBA04A08B47AD5.tal
    TAL path written to /last-tal-path
    # init-octorpki /tmp/test last-tal-path 1.5.10
    # run-octorpki /tmp/test
    INFO[0000] Validator started
    INFO[0000] Still exploring. Revalidating now
    INFO[0000] Root certificate for tals/tal.tal will be downloaded using rsync: rsync://localhost/repo/307AAE1C246A49E53CDCB39B00CBA04A08B47AD5.cer
    INFO[0000] Rsync sync rsync://localhost/repo/307AAE1C246A49E53CDCB39B00CBA04A08B47AD5.cer
    INFO[0000] Stable, terminating
    # reissue-crl-and-mft --name ta --mft-number 1461501637330902918203684832716283019655932542976
    # run-octorpki /tmp/test
    INFO[0000] Validator started
    INFO[0000] Still exploring. Revalidating now
    INFO[0000] Root certificate for tals/tal.tal will be downloaded using rsync: rsync://localhost/repo/307AAE1C246A49E53CDCB39B00CBA04A08B47AD5.cer
    INFO[0000] Rsync sync rsync://localhost/repo/307AAE1C246A49E53CDCB39B00CBA04A08B47AD5.cer
    INFO[0000] Stable, terminating
    #

### Todo

 - Documentation/tidying of code.

### License

See [LICENSE](./LICENSE).
