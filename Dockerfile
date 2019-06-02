FROM alpine:latest as builder

ENV CONFIG="\
    --prefix=/etc/nginx \
    --sbin-path=/usr/sbin/nginx \
    --modules-path=/usr/lib/nginx/modules \
    --conf-path=/etc/nginx/nginx.conf \
    --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log \
    --pid-path=/var/run/nginx.pid \
    --lock-path=/var/run/nginx.lock \
    --http-client-body-temp-path=/var/cache/nginx/client_temp \
    --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
    --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
    --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
    --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
    --user=nginx \
    --group=nginx \
    --with-http_ssl_module \
    --with-http_realip_module \
    --with-http_addition_module \
    --with-http_sub_module \
    --with-http_dav_module \
    --with-http_gunzip_module \
    --with-http_gzip_static_module \
    --with-http_random_index_module \
    --with-http_secure_link_module \
    --with-http_stub_status_module \
    --with-http_auth_request_module \
    --with-stream \
    --with-stream_ssl_module \
    --with-stream_ssl_preread_module \
    --with-stream_realip_module \
    --with-http_slice_module \
    --with-compat \
    --with-file-aio \
    --with-http_v2_module \
    --with-openssl=/usr/src/boringssl \
    --with-cc-opt=-I'/usr/src/boringssl/.openssl/include/' \
    --with-openssl-opt=enable-tls1_3 \
"

RUN apk add --no-cache build-base cmake git go perl zlib-dev linux-headers pcre-dev libc-dev
RUN git clone --depth 1 https://boringssl.googlesource.com/boringssl /usr/src/boringssl
RUN git clone --depth 1 https://github.com/nginx/nginx /usr/src/nginx
COPY ./patches /patches

RUN cd /usr/src/boringssl && \
         git apply < /patches/disable_aes128.patch && \
         mkdir build && \
         cd build && \
         cmake DCMAKE_BUILD_TYPE=Release ../ && \
         make ssl -j$(nproc) && \
         mkdir -p ../.openssl/lib && \
         cd ../.openssl/ && \
         ln -s ../include && \
         cd .. && \
         cp "build/crypto/libcrypto.a" "build/ssl/libssl.a" ".openssl/lib"

RUN cd /usr/src/nginx && \
         ./auto/configure ${CONFIG} && \
         mkdir -p /usr/src/boringssl/.openssl/include/openssl/ && \
         touch /usr/src/boringssl/.openssl/include/openssl/ssl.h && \
         make -j$(nproc) && \
         make install

FROM alpine:latest
RUN apk add --no-cache zlib pcre
COPY --from=builder "/usr/sbin/nginx" "/usr/sbin/nginx"
RUN adduser nginx -h /var/cache/nginx -s /bin/false -D

EXPOSE 80 443
STOPSIGNAL SIGTERM
CMD ["nginx", "-g", "daemon off;"]
