FROM ubuntu:23.04

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update -y
RUN apt-get install -y \
    libhttp-daemon-perl \
    liblist-moreutils-perl \
    libwww-perl \
    libcarp-always-perl \
    libconvert-asn1-perl \
    libclass-accessor-perl \
    cpanminus \
    libssl-dev \
    libyaml-perl \
    libxml-libxml-perl \
    libio-capture-perl \
    libnet-ip-perl \
    make \
    wget \
    patch \
    gcc \
    rsync \
    vim \
    libtls26 \
    libtls-dev \
    libdigest-sha-perl \
    libexpat1-dev \
    sudo \
    less \
    libdatetime-perl \
    git \
    zlib1g-dev \
    libautodie-perl \
    libipc-system-simple-perl \
    autoconf \
    automake \
    build-essential \
    libjansson-dev \
    pkg-config \
    libcurl4-openssl-dev \
    libxml2-dev \
    curl

RUN cpanm Set::IntSpan Net::CIDR::Set
RUN yes | unminimize

RUN addgroup \
    --gid 2000 \
    rpki-client && \
  adduser \
    --home /var/lib/rpki-client \
    --disabled-password \
    --gid 2000 \
    --uid 2000 \
    rpki-client
RUN mkdir /opt/rpki-client-7.0
RUN wget https://ftp.openbsd.org/pub/OpenBSD/rpki-client/rpki-client-7.0.tar.gz \
    && tar xf rpki-client-7.0.tar.gz \
    && cd rpki-client-7.0 \
    && ./configure --with-user=rpki-client --prefix=/opt/rpki-client-7.0 \
    && make \
    && make install \
    && cd ..
RUN mkdir /opt/rpki-client-8.7
RUN wget https://ftp.openbsd.org/pub/OpenBSD/rpki-client/rpki-client-8.7.tar.gz \
    && tar xf rpki-client-8.7.tar.gz \
    && cd rpki-client-8.7 \
    && ./configure --with-user=rpki-client --prefix=/opt/rpki-client-8.7 \
    && make \
    && make install \
    && cd ..
RUN mkdir /opt/rpki-client-9.0
RUN wget https://ftp.openbsd.org/pub/OpenBSD/rpki-client/rpki-client-9.0.tar.gz \
    && tar xf rpki-client-9.0.tar.gz \
    && cd rpki-client-9.0 \
    && ./configure --with-user=rpki-client --prefix=/opt/rpki-client-9.0 \
    && make \
    && make install \
    && cd ..
RUN mkdir /opt/rpki-client-9.3
RUN wget https://ftp.openbsd.org/pub/OpenBSD/rpki-client/rpki-client-9.3.tar.gz \
    && tar xf rpki-client-9.3.tar.gz \
    && cd rpki-client-9.3 \
    && ./configure --with-user=rpki-client --prefix=/opt/rpki-client-9.3 \
    && make \
    && make install \
    && cd ..
RUN git clone https://github.com/kristapsdz/openrsync.git \
    && cd openrsync \
    && ./configure \
    && make \
    && make install \
    && cd ..

RUN mkdir /opt/fort-1.6.4
RUN wget https://github.com/NICMx/FORT-validator/releases/download/1.6.4/fort-1.6.4.tar.gz \
    && tar xf fort-1.6.4.tar.gz \
    && cd fort-1.6.4 \
    && ./configure --prefix=/opt/fort-1.6.4 \
    && make \
    && make install \
    && cd ..
RUN mkdir /opt/fort-1.6.1
RUN wget https://github.com/NICMx/FORT-validator/releases/download/1.6.1/fort-1.6.1.tar.gz \
    && tar xf fort-1.6.1.tar.gz \
    && cd fort-1.6.1 \
    && ./configure --prefix=/opt/fort-1.6.1 \
    && make \
    && make install \
    && cd ..
RUN mkdir /opt/fort-1.5.4
RUN wget https://github.com/NICMx/FORT-validator/releases/download/1.5.4/fort-1.5.4.tar.gz \
    && tar xf fort-1.5.4.tar.gz \
    && cd fort-1.5.4 \
    && ./configure --prefix=/opt/fort-1.5.4 \
    && make \
    && make install \
    && cd ..
RUN mkdir /opt/fort-1.5.3
RUN wget https://github.com/NICMx/FORT-validator/releases/download/1.5.3/fort-1.5.3.tar.gz \
    && tar xf fort-1.5.3.tar.gz \
    && cd fort-1.5.3 \
    && ./configure --prefix=/opt/fort-1.5.3 \
    && make \
    && make install \
    && cd ..

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
RUN echo 'source root/.cargo/env' >> root/.bashrc
ENV PATH="/root/.cargo/bin:${PATH}"
RUN mkdir /opt/routinator-0.14.0
RUN cargo install --locked --force routinator --root /opt/routinator-0.14.0 --version 0.14.0
# Doesn't build, so disabling for now.
#
# error[E0282]: type annotations needed for `Box<_>`
#   --> /root/.cargo/registry/src/index.crates.io-6f17d22bba15001f/time-0.3.31/src/format_description/parse/mod.rs:83:9
#    |
# 83 |     let items = format_items
#    |         ^^^^^
# ...
# 86 |     Ok(items.into())
#    |              ---- type must be known at this point
#    |
#    = note: this is an inference error on crate `time` caused by an API change in Rust 1.80.0; update `time` to version `>=0.3.35` by calling `cargo update`
# RUN mkdir /opt/routinator-0.13.2
# RUN cargo install --locked --force routinator --root /opt/routinator-0.13.2 --version 0.13.2
RUN mkdir /opt/routinator-0.12.0
RUN cargo install --locked --force routinator --root /opt/routinator-0.12.0 --version 0.12.0
RUN mkdir /opt/routinator-0.11.0
RUN cargo install --locked --force routinator --root /opt/routinator-0.11.0 --version 0.11.0
RUN mkdir /opt/routinator-main
RUN mkdir /opt/routinator-main-build
RUN cd /opt/routinator-main-build \
    && git clone https://github.com/NLnetLabs/routinator \
    && cd routinator \
    && cargo install --path . --root /opt/routinator-main

RUN mkdir -p /opt/octorpki-1.5.10/bin
RUN wget https://github.com/cloudflare/cfrpki/releases/download/v1.5.10/octorpki-v1.5.10-linux-x86_64 -O /opt/octorpki-1.5.10/bin/octorpki
RUN chmod 755 /opt/octorpki-1.5.10/bin/octorpki
RUN mkdir -p /opt/octorpki-1.4.4/bin
RUN wget https://github.com/cloudflare/cfrpki/releases/download/v1.4.4/octorpki-v1.4.4-linux-x86_64 -O /opt/octorpki-1.4.4/bin/octorpki
RUN chmod 755 /opt/octorpki-1.4.4/bin/octorpki
RUN mkdir -p /opt/octorpki-1.4.3/bin
RUN wget https://github.com/cloudflare/cfrpki/releases/download/v1.4.3/octorpki-v1.4.3-linux-x86_64 -O /opt/octorpki-1.4.3/bin/octorpki
RUN chmod 755 /opt/octorpki-1.4.3/bin/octorpki

RUN wget https://github.com/RIPE-NCC/rpki-validator-3/archive/refs/tags/3.2-2021.04.07.12.55.tar.gz
RUN apt-get install -y unzip zip rpm

SHELL ["/bin/bash", "-c"]
RUN curl -s "https://get.sdkman.io" | bash
RUN mkdir -p /opt/ripe-validator-3/3.2-2021.04.07.12.55
RUN source "/root/.sdkman/bin/sdkman-init.sh" \
    && sdk install java 8.0.392-tem \
    && sdk install maven 3.9.6

RUN tar xf 3.2-2021.04.07.12.55.tar.gz \
    && cd ./rpki-validator-3-3.2-2021.04.07.12.55 \
    && cd rpki-validator \
    && sed 's/30_000/0/' -i src/main/java/net/ripe/rpki/validator3/background/ValidationScheduler.java \
    && sed 's/futureDate(10, SECOND)/futureDate(2, SECOND)/' -i src/main/java/net/ripe/rpki/validator3/background/BackgroundJobs.java \
    && source "/root/.sdkman/bin/sdkman-init.sh" \
    && sdk use java 8.0.392-tem \
    && sdk use maven 3.9.6 \
    && mvn install -Dmaven.test.skip=true

RUN wget https://github.com/RIPE-NCC/rpki-validator/archive/refs/tags/rpki-validator-2.24.tar.gz
RUN tar xf rpki-validator-2.24.tar.gz \
    && cd ./rpki-validator-rpki-validator-2.24/rpki-validator-cli \
    && source "/root/.sdkman/bin/sdkman-init.sh" \
    && sdk use java 8.0.392-tem \
    && sdk use maven 3.9.6 \
    && mvn install -Dmaven.test.skip=true

RUN apt-get update -y
RUN apt-get install -y \
    libdatetime-format-strptime-perl \
    libnet-ip-xs-perl \
    jq \
    libjson-xs-perl \
    net-tools \
    psmisc \
    uuid-runtime

RUN echo 'source /root/.sdkman/bin/sdkman-init.sh' >> root/.bashrc
COPY . /root/rpki-mft-number-demo
RUN cd /root/rpki-mft-number-demo/ && perl Makefile.PL && make && make install
COPY rsyncd.conf /etc/
RUN sed -i 's/RSYNC_ENABLE=false/RSYNC_ENABLE=true/' /etc/default/rsync

RUN rm -rf /root/rpki-mft-number-demo/
