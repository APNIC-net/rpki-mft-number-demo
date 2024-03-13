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
    TAL path: /data/repo/677B94AA2BA507C6B3B1586BEC9B7362EC5B6317.tal
    TAL path written to /last-tal-path
    # init-rpki-client /tmp/test last-tal-path 8.7
    # run-rpki-client /tmp/test
    # reissue-crl-and-mft --name ta --mft-number 3
    # run-rpki-client /tmp/test
    # reissue-crl-and-mft --name ta --mft-number 2
    # run-rpki-client /tmp/test
    rpki-client: .rsync/localhost/repo/ta/677B94AA2BA507C6B3B1586BEC9B7362EC5B6317.mft: unexpected manifest number (want >= #03, got #02)
    rpki-client: localhost/repo/ta/677B94AA2BA507C6B3B1586BEC9B7362EC5B6317.mft#03: bad message digest for 677B94AA2BA507C6B3B1586BEC9B7362EC5B6317.mft
    #

##### Manifest number reaches largest value

    # /sbin/service rsync start
    # setup-ca --name ta --resources 1234
    writing RSA key
    TAL path: /data/repo/9F12FA661A2B6C7BB958B2DECE6B38D1DF7A4434.tal
    TAL path written to /last-tal-path
    # init-rpki-client /tmp/test last-tal-path 8.7
    # run-rpki-client /tmp/test
    # reissue-crl-and-mft --name ta --mft-number 1461501637330902918203684832716283019655932542975
    # run-rpki-client /tmp/test
    # reissue-crl-and-mft --name ta --mft-number 1461501637330902918203684832716283019655932542975
    # run-rpki-client /tmp/test
    rpki-client: .rsync/localhost/repo/ta/9F12FA661A2B6C7BB958B2DECE6B38D1DF7A4434.mft: manifest misissuance, #FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF was recycled
    rpki-client: localhost/repo/ta/9F12FA661A2B6C7BB958B2DECE6B38D1DF7A4434.mft#FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF: bad message digest for 9F12FA661A2B6C7BB958B2DECE6B38D1DF7A4434.mft
    #

##### Manifest number too large

    # /sbin/service rsync start
    # setup-ca --name ta --resources 1234
    writing RSA key
    TAL path: /data/repo/406B4A8A719CAD0ACB35099DBC5A3034FB276FDE.tal
    TAL path written to /last-tal-path
    # init-rpki-client /tmp/test last-tal-path 8.7
    # run-rpki-client /tmp/test
    # reissue-crl-and-mft --name ta --mft-number 1461501637330902918203684832716283019655932542976
    # run-rpki-client /tmp/test
    rpki-client: x509_convert_seqnum: .rsync/localhost/repo/ta/406B4A8A719CAD0ACB35099DBC5A3034FB276FDE.mft: want 20 octets or fewer, have more.
    #

### Todo

 - Documentation/tidying of code.

### License

See [LICENSE](./LICENSE).
