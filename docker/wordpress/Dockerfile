FROM wordpress:php8.2-fpm

RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x wp-cli.phar \
    && mv wp-cli.phar /usr/local/bin/wp

RUN docker-php-ext-install exif

COPY php.ini /usr/local/etc/php/conf.d/custom.ini

EXPOSE 9000
