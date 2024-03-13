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
    less
COPY cms.diff .
RUN wget https://ftp.openssl.org/source/openssl-1.0.2p.tar.gz \
    && tar xf openssl-1.0.2p.tar.gz \
    && cd openssl-1.0.2p \
    && patch -p1 < /cms.diff \
    && ./config enable-rfc3779 \
    && make \
    && make install
RUN cpanm Set::IntSpan Net::CIDR::Set
RUN apt-get install -y \
    libdatetime-perl
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
RUN apt-get install -y git zlib1g-dev
RUN wget https://ftp.openbsd.org/pub/OpenBSD/rpki-client/rpki-client-8.7.tar.gz \
    && tar xf rpki-client-8.7.tar.gz \
    && cd rpki-client-8.7 \
    && ./configure --with-user=rpki-client \
    && make \
    && make install \
    && cd ..
RUN git clone https://github.com/kristapsdz/openrsync.git \
    && cd openrsync \
    && ./configure \
    && make \
    && make install \
    && cd ..
COPY . /root/rpki-mft-number-demo
RUN cd /root/rpki-mft-number-demo/ && perl Makefile.PL && make && make install
COPY rsyncd.conf /etc/
RUN sed -i 's/RSYNC_ENABLE=false/RSYNC_ENABLE=true/' /etc/default/rsync
RUN rm -rf /root/rpki-mft-number-demo/
