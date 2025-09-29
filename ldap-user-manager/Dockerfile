FROM php:8-apache

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        libldb-dev libldap2-dev libldap-common \
        libfreetype6-dev \
        libjpeg-dev \
        libpng-dev \
        ca-certificates \
        wget && \
    rm -rf /var/lib/apt/lists/*

RUN docker-php-ext-configure gd --with-freetype && \
    docker-php-ext-install -j$(nproc) gd && \
    docker-php-ext-configure ldap --with-libdir=lib/aarch64-linux-gnu && \
    docker-php-ext-install -j$(nproc) ldap

RUN wget --no-check-certificate -O /tmp/v6.10.0.tar.gz https://github.com/PHPMailer/PHPMailer/archive/refs/tags/v6.10.0.tar.gz

RUN a2enmod rewrite ssl && a2dissite 000-default default-ssl

EXPOSE 80
EXPOSE 443

COPY www/ /opt/ldap_user_manager
RUN tar -xzf /tmp/v6.10.0.tar.gz -C /opt && mv /opt/PHPMailer-6.10.0 /opt/PHPMailer

COPY entrypoint /usr/local/bin/entrypoint
RUN chmod a+x /usr/local/bin/entrypoint && touch /etc/ldap/ldap.conf

CMD ["apache2-foreground"]
ENTRYPOINT ["/usr/local/bin/entrypoint"]
