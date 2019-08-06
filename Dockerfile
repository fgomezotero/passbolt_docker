FROM php:7.2-fpm

LABEL maintainer="diego@passbolt.com"

ARG PASSBOLT_VERSION="2.10.0"
ARG PASSBOLT_URL="https://github.com/passbolt/passbolt_api/archive/v${PASSBOLT_VERSION}.tar.gz"
ARG PASSBOLT_CURL_HEADERS=""

ARG PHP_EXTENSIONS="gd \
      intl \
      pdo_mysql \
      opcache \
      xsl \
      ldap"

ARG PECL_PASSBOLT_EXTENSIONS="gnupg \
      redis \
      mcrypt"

ARG PASSBOLT_DEV_PACKAGES="libgpgme11-dev \
      libpng-dev \
      libjpeg62-turbo-dev \
      libicu-dev \
      libxslt1-dev \
      libmcrypt-dev \
      unzip"

ARG PASSBOLT_BASE_PACKAGES="nginx \
         gnupg \
         libgpgme11 \
         libmcrypt4 \
         mysql-client \
         supervisor \
         libldap2-dev"

ENV PECL_BASE_URL="https://pecl.php.net/get"
ENV PHP_EXT_DIR="/usr/src/php/ext"

WORKDIR /var/www/passbolt
RUN chgrp -R 0 /var/www/passbolt && \
    chmod -R g=u /var/www/passbolt
RUN apt-get update \
    && apt-get -y install --no-install-recommends \
      $PASSBOLT_DEV_PACKAGES \
      $PASSBOLT_BASE_PACKAGES \
    && mkdir /home/www-data \
    && chown -R www-data:0 /home/www-data \
    && usermod -d /home/www-data www-data \
    && docker-php-source extract \
    && for i in $PECL_PASSBOLT_EXTENSIONS; do \
         mkdir $PHP_EXT_DIR/$i; \
         curl -sSL $PECL_BASE_URL/$i | tar zxf - -C $PHP_EXT_DIR/$i --strip-components 1; \
       done \
    && docker-php-ext-configure gd --with-jpeg-dir=/usr/include/ \
    && docker-php-ext-install -j4 $PHP_EXTENSIONS $PECL_PASSBOLT_EXTENSIONS \
    && docker-php-ext-enable $PHP_EXTENSIONS $PECL_PASSBOLT_EXTENSIONS \
    && docker-php-source delete \
    && EXPECTED_SIGNATURE=$(curl -s https://composer.github.io/installer.sig) \
    && curl -o composer-setup.php https://getcomposer.org/installer \
    && ACTUAL_SIGNATURE=$(php -r "echo hash_file('SHA384', 'composer-setup.php');") \
    && if [ "$EXPECTED_SIGNATURE" != "$ACTUAL_SIGNATURE" ]; then \
         >&2 echo 'ERROR: Invalid installer signature'; \
         rm composer-setup.php; \
         exit 1; \
       fi \
    && php composer-setup.php \
    && mv composer.phar /usr/local/bin/composer \
    && rm composer-setup.php \
    && curl -sSL -H "$PASSBOLT_CURL_HEADERS" "$PASSBOLT_URL" | tar zxf - -C . --strip-components 1 \
    && composer install -n --no-dev --optimize-autoloader \
    && chown -R www-data:0 . \
    && chmod 777 $(find /var/www/passbolt/tmp -type d) \
    && chmod 666 $(find /var/www/passbolt/tmp -type f) \
    && chmod 777 $(find /var/www/passbolt/webroot/img/public -type d) \
    && chmod 666 $(find /var/www/passbolt/webroot/img/public -type f) \
    && rm /etc/nginx/sites-enabled/default \
    && apt-get purge -y --auto-remove $PASSBOLT_DEV_PACKAGES \
    && rm -rf /var/lib/apt/lists/* \
    && rm /usr/local/bin/composer \
    && echo 'php_flag[expose_php] = off' > /usr/local/etc/php-fpm.d/expose.conf \
    && sed -i 's/# server_tokens/server_tokens/' /etc/nginx/nginx.conf \
    && mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini" 
    
COPY conf/passbolt.conf /etc/nginx/conf.d/default.conf
COPY conf/supervisor/*.conf /etc/supervisor/conf.d/
#COPY supervisord.conf /etc/supervisor/
COPY bin/* /
COPY scripts/wait-for.sh /usr/bin/wait-for.sh

RUN   chmod g=u /etc/passwd && chgrp 0 /etc/passwd && \
      chgrp 0 /etc/group && chmod g=u /etc/group && \
      chgrp -R 0 /etc/environment && chmod -R g=u /etc/environment && \
      chgrp -R 0 /home/www-data && chmod -R g=u /home/www-data && \
      chgrp -R 0 /etc/ssl && chmod -R g=u /etc/ssl && \
      chgrp -R 0 /var/spool/ && chmod -R g=u /var/spool/ && \ 
      chgrp -R 0 /etc/supervisor && chmod -R g=u /etc/supervisor && \ 
      chgrp -R 0 /var/run && chmod -R g=u /var/run && \
      chgrp -R 0 /var/log && chmod -R g=u /var/log && \
      chgrp -R 0 /var/lib && chmod -R g=u /var/lib && \
      chgrp -R 0 /usr/bin && chmod -R g=u /usr/bin && \
      chgrp -R 0 /run && chmod -R g=u /run && \
      chgrp -R 0 /etc/nginx && chmod -R g=u /etc/nginx
EXPOSE 8080 4443

VOLUME [ "/var/www/passbolt" ]

ENTRYPOINT [ "/uid_entrypoint" ]
CMD ["/docker-entrypoint.sh"]
