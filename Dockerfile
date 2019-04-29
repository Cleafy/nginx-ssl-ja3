FROM debian:sid

LABEL maintainer "fooinha@gmail.com"

# Build arguments
ARG DEBIAN_REPO_HOST=httpredir.debian.org

# Mirror to my location
RUN echo "deb http://${DEBIAN_REPO_HOST}/debian sid main" > /etc/apt/sources.list
RUN echo "deb-src http://${DEBIAN_REPO_HOST}/debian sid main" >> /etc/apt/sources.list

# Update
RUN DEBIAN_FRONTEND=noninteractive apt-get update || true

# Install build dependencies
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y --fix-missing \
    apt-utils \
    autoconf \
    automake \
    bind9-host \
    build-essential \
    dh-autoreconf \
    cpanminus \
    curl \
    devscripts \
    exuberant-ctags \
    git-core \
    jq \
    llvm \
    libgeoip1 \
    libgeoip-dev \
    libpcre3 \
    libpcre3-dbg \
    libpcre3-dev \
    libperl-dev \
    libmagic-dev \
    libtool \
    lsof \
    make \
    mercurial \
    ngrep \
    procps \
    python \
    telnet \
    tcpflow \
    valgrind \
    vim \
    wget \
    zlib1g \
    zlib1g-dev

# Create build directory
RUN mkdir -p /build/nginx-ssl-ja3

WORKDIR /build

# Get test framework
RUN git clone https://github.com/nginx/nginx-tests

# Get openssl master from git
RUN git clone https://github.com/openssl/openssl

# Build and install openssl
WORKDIR /build/openssl

RUN git checkout OpenSSL_1_1_1 -b patched
COPY nginx-ja3/patches/openssl.extensions.patch /build/openssl
RUN patch -p1 < openssl.extensions.patch
RUN ./config -d
RUN make
RUN make install

# Clone from nginx
WORKDIR /build
RUN hg clone http://hg.nginx.org/nginx

# Patch nginx for fetching ssl client extensions
WORKDIR /build/nginx
COPY nginx-ja3/patches/nginx.latest.patch /build/nginx
RUN patch -p1 < nginx.latest.patch

# Install files
RUN mkdir -p /usr/local/nginx/conf/

# Install self-signed certificate
RUN LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/lib /usr/local/bin/openssl req -new -x509 -days 365 -nodes -out /usr/local/nginx/conf/cert.pem -keyout /usr/local/nginx/conf/rsa.key -subj "/C=PT/ST=Lisbon/L=Lisbon/O=Development/CN=foo.local"

# vim config
COPY ./nginx/vimrc /etc/vim/vimrc

RUN echo 'export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/lib' | tee -a /root/.bashrc
RUN echo 'export PATH=$PATH:/usr/local/bin:/usr/local/nginx/sbin' | tee -a /root/.bashrc
RUN echo '' | tee -a /root/.bashrc
RUN echo 'export ASAN_OPTIONS=symbolize=1' | tee -a /root/.bashrc
RUN echo 'export ASAN_SYMBOLIZER_PATH=/usr/bin/llvm-symbolizer' | tee -a /root/.bashrc
RUN echo '' | tee -a /root/.bashrc

COPY nginx-ja3/ /build/nginx-ssl-ja3

WORKDIR /build/nginx
RUN ASAN_OPTIONS=detect_leaks=0:symbolize=1 ./auto/configure \
    --add-module=/build/nginx-ssl-ja3 \
    --with-http_ssl_module \
    --with-stream_ssl_module \
    --with-debug \
    --with-stream \ 
    --with-http_auth_request_module \
    --with-cc-opt="-fsanitize=address -O -fno-omit-frame-pointer" \
    --with-ld-opt="-L/usr/local/lib -Wl,-E -lasan"
RUN make install 

EXPOSE 443
CMD ["/usr/local/nginx/sbin/nginx"]