## rpki-mft-number-demo

For demonstrating how RPKI validators handle specific manifest
numbers and related transitions.  See
[draft-harrison-sidrops-manifest-numbers](https://datatracker.ietf.org/doc/draft-harrison-sidrops-manifest-numbers/).

### Build

    $ docker build -t apnic/rpki-mft-number-demo .

### Usage

    $ docker run -it apnic/rpki-mft-number-demo /bin/bash
    # run-test
    Usage: /usr/local/bin/run-test {test-name} {validator-name} {validator-version}

    Test names:
      - manifest-number-decrease
      - manifest-number-largest-value
      - manifest-number-too-large
    Validators:
      - fort (1.5.3, 1.5.4, 1.6.1)
      - octorpki (1.4.3, 1.4.4, 1.5.10)
      - routinator (0.11.0, 0.12.0, 0.13.2)
      - rpki-client (7.0, 8.7, 9.0)

    The string 'all' can also be used for each option,
    to test multiple versions of a validator, or multiple
    validators, or multiple tests.
    # run-test manifest-number-decrease rpki-client 9.0
    manifest-number-decrease (rpki-client v9.0)
    writing RSA key
    TAL path: /data/repo/56DC0E8346EE557E329FA89D6D34D01FA403F16D.tal
    TAL path written to /last-tal-path
    Initial validator run:
    End validator run
    Validator run (manifest number 3):
    End validator run
    Validator run (manifest number 2):
    rpki-client: .rsync/localhost/repo/tlz1kazc/56DC0E8346EE557E329FA89D6D34D01FA403F16D.mft: unexpected manifest number (want >= #03, got #02)
    End validator run
    ---
    #

Various commands are provided for writing the tests.  For example,
`manifest-number-decrease` can be stepped through in more detail like
so:

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
    #

### Todo

 - Documentation/tidying of code.

### License

See [LICENSE](./LICENSE).
