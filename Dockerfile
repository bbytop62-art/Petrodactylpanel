FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC
ENV APP_URL=http://0.0.0.0:8030
ENV DB_HOST=database
ENV DB_PORT=3306
ENV DB_DATABASE=panel
ENV DB_USERNAME=pterodactyl
ENV DB_PASSWORD=admin123

# Install all dependencies with PHP 8.2
RUN apt update && apt install -y \
    curl wget git unzip tar gnupg ca-certificates lsb-release \
    software-properties-common apt-transport-https \
    nginx mariadb-server redis-server \
    php8.2 php8.2-cli php8.2-fpm php8.2-common \
    php8.2-mysql php8.2-mbstring php8.2-bcmath php8.2-xml \
    php8.2-zip php8.2-curl php8.2-gd php8.2-tokenizer \
    php8.2-ctype php8.2-simplexml php8.2-dom \
    python3 python3-pip python3-venv \
    nodejs npm \
    && apt clean && rm -rf /var/lib/apt/lists/*

# Install PM2
RUN npm install -g pm2

# Install Composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Setup MariaDB
RUN service mariadb start && \
    mysql -e "CREATE DATABASE IF NOT EXISTS panel;" && \
    mysql -e "CREATE USER IF NOT EXISTS 'pterodactyl'@'%' IDENTIFIED BY 'admin123';" && \
    mysql -e "GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'%';" && \
    mysql -e "FLUSH PRIVILEGES;"

# Download Pterodactyl Panel
WORKDIR /var/www/pterodactyl
RUN curl -Lso panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz && \
    tar -xzf panel.tar.gz && \
    rm panel.tar.gz && \
    chmod -R 755 storage/* bootstrap/cache/

# Setup .env
RUN cp .env.example .env && \
    sed -i "s|APP_URL=.*|APP_URL=http://0.0.0.0:8030|g" .env && \
    sed -i "s|DB_HOST=.*|DB_HOST=database|g" .env && \
    sed -i "s|DB_PORT=.*|DB_PORT=3306|g" .env && \
    sed -i "s|DB_DATABASE=.*|DB_DATABASE=panel|g" .env && \
    sed -i "s|DB_USERNAME=.*|DB_USERNAME=pterodactyl|g" .env && \
    sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=admin123|g" .env && \
    echo "APP_ENVIRONMENT_ONLY=false" >> .env

# Install PHP dependencies
RUN composer install --no-dev --optimize-autoloader

# Generate key + Migrate
RUN php artisan key:generate --force && \
    service mariadb start && \
    php artisan migrate --seed --force

# Create Admin User (bbytop12@gmail.com / bbytop@12)
RUN php artisan p:user:make --email=bbytop12@gmail.com --username=bbytop12 --password="bbytop@12" --admin=1 --no-interaction

# Setup Nginx
RUN rm /etc/nginx/sites-enabled/default && \
    echo 'server { \
    listen 8030; \
    root /var/www/pterodactyl/public; \
    index index.php; \
    server_name _; \
    location / { \
        try_files $uri $uri/ /index.php?$query_string; \
    } \
    location ~ \.php$ { \
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock; \
        fastcgi_index index.php; \
        include /etc/nginx/fastcgi_params; \
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name; \
    } \
}' > /etc/nginx/sites-available/pterodactyl && \
    ln -s /etc/nginx/sites-available/pterodactyl /etc/nginx/sites-enabled/

# Python Eggs Import
RUN curl -sSL https://raw.githubusercontent.com/pterodactyl/eggs/refs/heads/master/generic/python/egg-python.json > /tmp/python.json && \
    php artisan p:egg:import /tmp/python.json 2>/dev/null || true && \
    curl -sSL https://raw.githubusercontent.com/pterodactyl/eggs/refs/heads/master/generic/flask/egg-flask.json > /tmp/flask.json && \
    php artisan p:egg:import /tmp/flask.json 2>/dev/null || true

EXPOSE 8030

CMD service mariadb start && service redis-server start && service php8.2-fpm start && service nginx start && tail -f /var/log/nginx/*.log
