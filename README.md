## rpki-mft-number-demo

For demonstrating how RPKI validators handle specific manifest
numbers and related transitions.  See
[draft-harrison-sidrops-manifest-numbers](https://datatracker.ietf.org/doc/draft-harrison-sidrops-manifest-numbers/).

### Build

    $ docker build -t apnic/rpki-mft-number-demo .

### Usage

    $ docker run -it apnic/rpki-mft-number-demo /bin/bash

#### rpki-client testing

    # /sbin/service rsync start
    # setup-ca --name ta --resources 1234
    writing RSA key
    TAL path: /data/repo/677B94AA2BA507C6B3B1586BEC9B7362EC5B6317.tal
    TAL path written to /last-tal-path
    # sudo -u rpki-client -H bash
    # export TAL_PATH=$(cat last-tal-path)
    # mkdir /tmp/test
    # cd /tmp/test
    # mkdir cache output
    # cp $TAL_PATH tal
    # rpki-client -c -t tal -d cache output >/dev/null
    # exit
    # reissue-crl-and-mft --name ta --mft-number 3
    # sudo -u rpki-client -H bash
    # cd /tmp/test
    # rpki-client -c -t tal -d cache output >/dev/null
    # exit
    # reissue-crl-and-mft --name ta --mft-number 2
    # sudo -u rpki-client -H bash
    # cd /tmp/test
    # rpki-client -c -t tal -d cache output >/dev/null
    rpki-client: .rsync/localhost/repo/ta/677B94AA2BA507C6B3B1586BEC9B7362EC5B6317.mft: unexpected manifest number (want >= #03, got #02)
    rpki-client: localhost/repo/ta/677B94AA2BA507C6B3B1586BEC9B7362EC5B6317.mft#03: bad message digest for 677B94AA2BA507C6B3B1586BEC9B7362EC5B6317.mft
    #

### Todo

 - Documentation/tidying of code.

### License

See [LICENSE](./LICENSE).
