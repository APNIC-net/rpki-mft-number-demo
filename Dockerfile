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

COPY cms.diff .
RUN wget https://ftp.openssl.org/source/openssl-1.0.2p.tar.gz \
    && tar xf openssl-1.0.2p.tar.gz \
    && cd openssl-1.0.2p \
    && patch -p1 < /cms.diff \
    && ./config enable-rfc3779 \
    && make \
    && make install
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
RUN git clone https://github.com/kristapsdz/openrsync.git \
    && cd openrsync \
    && ./configure \
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
RUN mkdir /opt/routinator-0.13.2
RUN cargo install --locked --force routinator --root /opt/routinator-0.13.2 --version 0.13.2
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

RUN apt-get install -y libdatetime-format-strptime-perl
RUN apt-get install -y faketime

RUN echo 'source /root/.sdkman/bin/sdkman-init.sh' >> root/.bashrc
COPY . /root/rpki-mft-number-demo
RUN cd /root/rpki-mft-number-demo/ && perl Makefile.PL && make && make install
COPY rsyncd.conf /etc/
RUN sed -i 's/RSYNC_ENABLE=false/RSYNC_ENABLE=true/' /etc/default/rsync

RUN rm -rf /root/rpki-mft-number-demo/
