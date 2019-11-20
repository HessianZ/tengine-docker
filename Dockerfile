FROM alpine:3.10

# 生产环境配置
ENV TENGINE_VERSION="2.3.2" 

RUN set -x \
# create nginx user/group first, to be consistent throughout docker variants
    && export ALPINE_VERSION=$(sed 's/\.\d\+$//' /etc/alpine-release) \
    && echo "https://mirrors.cloud.tencent.com/alpine/v${ALPINE_VERSION}/main" > /etc/apk/repositories \
    && echo "https://mirrors.cloud.tencent.com/alpine/v${ALPINE_VERSION}/community" >> /etc/apk/repositories \
    && apk update \
    && addgroup -g 101 -S nginx \
    && adduser -S -D -H -u 101 -h /var/cache/nginx -s /sbin/nologin -G nginx -g nginx nginx \
    && apkArch="$(cat /etc/apk/arch)" \
    && nginxPackages=" \
        nginx=${NGINX_VERSION}-r${PKG_RELEASE} \
        nginx-module-xslt=${NGINX_VERSION}-r${PKG_RELEASE} \
        nginx-module-geoip=${NGINX_VERSION}-r${PKG_RELEASE} \
        nginx-module-image-filter=${NGINX_VERSION}-r${PKG_RELEASE} \
        nginx-module-njs=${NGINX_VERSION}.${NJS_VERSION}-r${PKG_RELEASE} \
    " \
    && tempDir="$(mktemp -d)" \
    && chown nobody:nobody $tempDir \
    && apk add --no-cache --virtual .build-deps \
        gcc \
        libc-dev \
        make \
        openssl-dev \
        pcre-dev \
        zlib-dev \
        linux-headers \
        libxslt-dev \
        gd-dev \
        geoip-dev \
        perl-dev \
        libedit-dev \
        mercurial \
        bash \
        alpine-sdk \
        findutils \
    && su nobody -s /bin/sh -c " \
        export HOME=${tempDir} \
        && cd ${tempDir} \
        && wget http://tengine.taobao.org/download/tengine-${TENGINE_VERSION}.tar.gz \
        && tar zxf tengine-${TENGINE_VERSION}.tar.gz \
        && cd tengine-${TENGINE_VERSION} \
        && ./configure --prefix=/usr --conf-paht=/etc/nginx/nginx.conf --pid-paht=/var/run/nginx.pid \
        && make \
        && make install" \
    && apk del .build-deps \
# if we have leftovers from building, let's purge them (including extra, unnecessary build deps)
    && if [ -n "$tempDir" ]; then rm -rf "$tempDir"; fi \
# Bring in gettext so we can get `envsubst`, then throw
# the rest away. To do this, we need to install `gettext`
# then move `envsubst` out of the way so `gettext` can
# be deleted completely, then move `envsubst` back.
    && apk add --no-cache --virtual .gettext gettext \
    && mv /usr/bin/envsubst /tmp/ \
    && runDeps="$( \
        scanelf --needed --nobanner /tmp/envsubst \
            | awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' \
            | sort -u \
            | xargs -r apk info --installed \
            | sort -u \
    )" \
    && apk add --no-cache $runDeps \
    && apk del .gettext \
    && mv /tmp/envsubst /usr/local/bin/ \
# Bring in tzdata so users could set the timezones through the environment
# variables
    && apk add --no-cache tzdata \
# forward request and error logs to docker log collector
    && mkdir -p /var/log/nginx \
    && chown nginx:nginx -R /var/log/nginx \
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log

EXPOSE 80

STOPSIGNAL SIGTERM

CMD ["nginx", "-g", "daemon off;"]
