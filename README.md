## rpki-mft-number-demo

For demonstrating how RPKI validators handle specific manifest numbers
(and other manifest/CRL fields) and related transitions.  See
[draft-harrison-sidrops-manifest-numbers](https://datatracker.ietf.org/doc/draft-harrison-sidrops-manifest-numbers/).

### Build

    $ docker build -t apnic/rpki-mft-number-demo .

### Usage

    $ docker run -it apnic/rpki-mft-number-demo /bin/bash
    # run-test
    Usage: /usr/local/bin/run-test {test-name} {validator-name} {validator-version}

    Test names:
      - manifest-number-reuse
      - manifest-number-reuse-new-fn
      - manifest-number-regression
      - manifest-number-regression-new-fn
      - manifest-number-largest-value-159
      - manifest-number-too-large-159
      - manifest-number-largest-value-160
      - manifest-number-too-large-160
      - manifest-thisupdate-reuse
      - manifest-thisupdate-reuse-new-fn
      - manifest-thisupdate-regression
      - manifest-thisupdate-regression-new-fn
      - manifest-thisupdate-largest-value
      - crl-number-reuse
      - crl-number-reuse-new-fn
      - crl-number-regression
      - crl-number-regression-new-fn
      - crl-number-largest-value-159
      - crl-number-too-large-159
      - crl-number-largest-value-160
      - crl-number-too-large-160
      - crl-lastupdate-reuse
      - crl-lastupdate-reuse-new-fn
      - crl-lastupdate-regression
      - crl-lastupdate-regression-new-fn
      - crl-lastupdate-largest-value
    Validators:
      - fort (1.5.3, 1.5.4, 1.6.1)
      - octorpki (1.4.3, 1.4.4, 1.5.10)
      - ripe-validator (2.24)
      - ripe-validator-3 (3.2-2021.04.07.12.55)
      - routinator (0.11.0, 0.12.0, 0.13.2, main)
      - rpki-client (7.0, 8.7, 9.0)

    The string 'all' can also be used for each option,
    to test multiple versions of a validator, or multiple
    validators, or multiple tests.
    # run-test manifest-number-regression rpki-client 9.0
    manifest-number-regression (rpki-client v9.0)
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
`manifest-number-regression` can be stepped through in more detail like
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

### Current results

See [current-results.txt](current-results.txt) for the output from
running all tests for all validators.

#### Summary of current results

 - manifest-number-reuse
 - manifest-number-regression
    - Routinator >= r385e74d and rpki-client >= 8.7 report errors for
      these problems, while the other validators do not.
 - manifest-number-reuse-new-fn
 - manifest-number-regression-new-fn
    - Routinator >= r385e74d and rpki-client >= 8.7 reset (in effect)
      the locally-stored manifest number for the CA when the manifest
      filename changes.
 - manifest-number-largest-value-159
 - manifest-number-too-large-159
    - Routinator and FORT limit the manifest number to the largest
      signed 160-bit value.
    - OctoRPKI and rpki-client appear to process the repository
      successfully.
 - manifest-number-largest-value-160
 - manifest-number-too-large-160
    - Since Routinator limits the manifest number to the largest
      signed 160-bit value, it reports errors for these tests (which
      use the largest unsigned 160-bit value).
    - As with the 159 tests, FORT reports generic errors for both of
      these tests.
    - OctoRPKI appears to process the repository successfully (i.e. it
      does not check for a manifest number that is too large).
    - rpki-client reports specific errors on attempting to validate a
      manifest with a value that exceeds the largest unsigned 160-bit
      value.
 - manifest-thisupdate-reuse
 - manifest-thisupdate-regression
    - rpki-client >= 9.0 reports errors for these problems, while the
      other validators do not.
 - manifest-thisupdate-reuse-new-fn
 - manifest-thisupdate-regression-new-fn
    - rpki-client >= 9.0 reset (in effect) the locally-stored
      this-update value for the CA when the manifest filename changes.
    - FORT reports errors on changing the filename.
 - manifest-thisupdate-largest-value
    - FORT does not appear to support this value, but reverting to an
      earlier value will yield a successful validation result.
    - OctoRPKI does not appear to support this value, and reverting to
      an earlier value does not fix the problem.
    - Routinator v0.11.0 rejects the manifests that have the largest
      thisUpdate value, returning a non-specific error message.
      Reverting to an earlier value fixes the problem.  The later
      versions of Routinator reject the manifests with a "premature
      manifest" error, and reverting to an earlier value fixes the
      problem.
    - rpki-client rejects the manifests due to their not yet being
      valid, because of thisUpdate being in the future.  Reverting to
      an earlier value fixes the problem.
 - crl-number-reuse
 - crl-number-regression
 - crl-number-reuse-new-fn
 - crl-number-regression-new-fn
    - CRL number reuse/regression does not cause problems in any
      validator.
    - Changing the CRL filename is fine for all validators except
      Routinator.  (It is possible that this is a problem in the test
      itself, though, since it reports that the certificate's CRL
      differs from the manifest's.)
 - crl-number-largest-value-159
 - crl-number-too-large-159
    - As with manifest numbers, Routinator limits the CRL number to
      the largest signed 160-bit value.
    - The other validators appear to process the repository
      successfully for both tests.
 - crl-number-largest-value-160
 - crl-number-too-large-160
    - rpki-client >= 8.7 limits the CRL number to the largest unsigned
      160-bit value.
    - The other validators (aside from Routinator, which limits the
      number to the largest signed 160-bit value) appear to process
      the repository successfully for both tests.
 - crl-lastupdate-reuse
 - crl-lastupdate-regression
 - crl-lastupdate-reuse-new-fn
 - crl-lastupdate-regression-new-fn
    - Each validator appears to process the repository successfully
      for each test.
 - crl-lastupdate-largest-value
    - FORT does not appear to support this value, but reverting to an
      earlier value will yield a successful validation result.
    - OctoRPKI appears to support this value.
    - The other validators appear to process the repository
      successfully for each test.

(This summary excludes the RIPE validators, since they have been
formally deprecated for many years now.)

### Todo

 - Documentation/tidying of code.

### License

See [LICENSE](./LICENSE).
