#\!/bin/bash
# ==============================================================================
# Installation functions for all services
# ==============================================================================

install_php() {
    log_info "Installing PHP..."

    local php_ver=""

    case "$DISTRO" in
        debian)
            pkg_install software-properties-common
            add-apt-repository -y ppa:ondrej/php
            pkg_update

            # Find the latest PHP version that has all core packages available
            php_ver=""
            for ver in $(apt-cache search '^php[0-9]+\.[0-9]+-fpm$' 2>/dev/null | grep -o 'php[0-9]*\.[0-9]*' | sed 's/^php//' | sort -rV); do
                if apt-cache show "php${ver}-common" >/dev/null 2>&1 && apt-cache show "php${ver}-opcache" >/dev/null 2>&1; then
                    php_ver="$ver"
                    break
                fi
            done
            [ -z "$php_ver" ] && php_ver="8.4"
            log_info "Installing PHP $php_ver..."

            local exts_to_install=""
            local raw_exts
            raw_exts=$(echo "$SEL_PHP_EXTS" | sed 's/"//g')
            for ext in $raw_exts; do
                local base_ext
                base_ext=$(echo "$ext" | sed "s/^php[0-9]*\.[0-9]*-/php${php_ver}-/; s/^php-/php${php_ver}-/")
                exts_to_install="$exts_to_install $base_ext"
            done
            # shellcheck disable=SC2086
            pkg_install php${php_ver} $exts_to_install
            ;;
        fedora)
            pkg_install php php-fpm php-cli php-common
            php_ver=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo "8.2")
            log_info "Installing PHP $php_ver extensions..."

            local raw_exts
            raw_exts=$(echo "$SEL_PHP_EXTS" | sed 's/"//g')
            for ext in $raw_exts; do
                local fedora_ext
                # Map debian-style names to fedora names
                fedora_ext=$(echo "$ext" | sed 's/^php[0-9]*\.[0-9]*-/php-/; s/^php-mysql$/php-mysqlnd/; s/^php-sqlite3$/php-pdo/')
                pkg_install "$fedora_ext" 2>/dev/null || log_warn "Extension $fedora_ext not found, skipping."
            done
            ;;
        macos)
            pkg_install php
            php_ver=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo "8.3")
            log_info "Installed PHP $php_ver"

            # Configure PHP-FPM to use unix socket (Homebrew defaults to TCP 9000)
            local fpm_conf="/opt/homebrew/etc/php/${php_ver}/php-fpm.d/www.conf"
            if [ -f "$fpm_conf" ]; then
                sed_i 's|^listen = 127\.0\.0\.1:9000|listen = /tmp/php-fpm.sock|' "$fpm_conf"
                # Ensure socket permissions allow Apache to connect
                sed_i 's|^;listen.owner = .*|listen.owner = '"$(whoami)"'|' "$fpm_conf"
                sed_i 's|^;listen.group = .*|listen.group = staff|' "$fpm_conf"
                sed_i 's|^;listen.mode = .*|listen.mode = 0660|' "$fpm_conf"
                log_info "Configured PHP-FPM to use unix socket at /tmp/php-fpm.sock"
            fi

            # Install PECL extensions if selected
            local raw_exts
            raw_exts=$(echo "$SEL_PHP_EXTS" | sed 's/"//g')

            # Install brew dependencies needed by PECL extensions
            local need_imagemagick=false
            local need_igbinary=false
            local need_yaml=false
            local need_memcached=false
            for ext in $raw_exts; do
                case "$ext" in
                    pecl-imagick) need_imagemagick=true ;;
                    pecl-igbinary|pecl-redis) need_igbinary=true ;;
                    pecl-yaml) need_yaml=true ;;
                    pecl-memcached) need_memcached=true ;;
                esac
            done
            $need_imagemagick && { log_info "Installing ImageMagick (dependency)..."; pkg_install imagemagick; }
            $need_yaml && { log_info "Installing libyaml (dependency)..."; pkg_install libyaml; }
            $need_memcached && { log_info "Installing libmemcached (dependency)..."; pkg_install libmemcached; }

            # Install igbinary first if needed (redis depends on it)
            if $need_igbinary; then
                log_info "Installing PECL extension: igbinary..."
                if pecl list 2>/dev/null | grep -q igbinary; then
                    log_success "igbinary already installed."
                else
                    printf "\n" | pecl install igbinary 2>/dev/null || log_warn "PECL extension igbinary failed, skipping."
                fi
            fi

            for ext in $raw_exts; do
                case "$ext" in
                    pecl-igbinary) ;; # already installed above
                    pecl-*)
                        local pecl_name
                        pecl_name=$(echo "$ext" | sed 's/^pecl-//')
                        if pecl list 2>/dev/null | grep -q "$pecl_name"; then
                            log_success "${pecl_name} already installed."
                        else
                            log_info "Installing PECL extension: ${pecl_name}..."
                            printf "\n\n\n\n\n\n\n" | pecl install "$pecl_name" 2>/dev/null \
                                || log_warn "PECL extension $pecl_name failed, skipping."
                        fi
                        ;;
                esac
            done
            ;;
    esac

    log_success "PHP $php_ver installed."
    PHP_VER="$php_ver"
}

install_apache() {
    log_info "Installing Apache..."

    local fpm_sock
    fpm_sock=$(get_fpm_sock "$PHP_VER")

    case "$DISTRO" in
        debian)
            pkg_install apache2 libapache2-mod-fcgid
            a2enmod rewrite
            a2enmod proxy_fcgi
            a2enmod setenvif
            a2dissite 000-default.conf 2>/dev/null || true

            cat > "${APACHE_SITES_DIR}/custom-stack.conf" <<VHOST
<VirtualHost *:${SEL_PORT}>
    ServerAdmin webmaster@localhost
    DocumentRoot ${SEL_DOCROOT}

    <Directory ${SEL_DOCROOT}>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    <FilesMatch \.php\$>
        SetHandler "proxy:unix:${fpm_sock}|fcgi://localhost"
    </FilesMatch>

    ErrorLog \${APACHE_LOG_DIR}/custom-stack-error.log
    CustomLog \${APACHE_LOG_DIR}/custom-stack-access.log combined
</VirtualHost>
VHOST

            if [ "$SEL_PORT" != "80" ]; then
                if ! grep -q "Listen ${SEL_PORT}" "${APACHE_CONF_DIR}/ports.conf"; then
                    echo "Listen ${SEL_PORT}" >> "${APACHE_CONF_DIR}/ports.conf"
                fi
            fi
            a2ensite custom-stack.conf
            ;;
        fedora)
            pkg_install httpd mod_fcgid

            cat > "${APACHE_SITES_DIR}/custom-stack.conf" <<VHOST
Listen ${SEL_PORT}
<VirtualHost *:${SEL_PORT}>
    ServerAdmin webmaster@localhost
    DocumentRoot ${SEL_DOCROOT}

    <Directory ${SEL_DOCROOT}>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    <FilesMatch \.php\$>
        SetHandler "proxy:unix:${fpm_sock}|fcgi://localhost"
    </FilesMatch>

    ErrorLog ${APACHE_LOG_DIR}/custom-stack-error.log
    CustomLog ${APACHE_LOG_DIR}/custom-stack-access.log combined
</VirtualHost>
VHOST
            ;;
        macos)
            pkg_install httpd

            cat > "${APACHE_SITES_DIR}/custom-stack.conf" <<VHOST
Listen ${SEL_PORT}
<VirtualHost *:${SEL_PORT}>
    ServerAdmin webmaster@localhost
    DocumentRoot ${SEL_DOCROOT}

    <Directory ${SEL_DOCROOT}>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    <FilesMatch \.php\$>
        SetHandler "proxy:unix:${fpm_sock}|fcgi://localhost"
    </FilesMatch>

    ErrorLog ${APACHE_LOG_DIR}/custom-stack-error.log
    CustomLog ${APACHE_LOG_DIR}/custom-stack-access.log combined
</VirtualHost>
VHOST
            # Include the custom config
            if ! grep -q "custom-stack.conf" "${APACHE_CONF_DIR}/httpd.conf" 2>/dev/null; then
                echo "Include ${APACHE_SITES_DIR}/custom-stack.conf" >> "${APACHE_CONF_DIR}/httpd.conf"
            fi
            ;;
    esac

    log_success "Apache installed and configured."
}

install_nginx() {
    log_info "Installing Nginx..."
    pkg_install nginx

    local fpm_sock
    fpm_sock=$(get_fpm_sock "$PHP_VER")

    case "$DISTRO" in
        debian)
            rm -f /etc/nginx/sites-enabled/default
            local block_file="/etc/nginx/sites-available/custom-stack"
            cat > "$block_file" <<NGINX
server {
    listen ${SEL_PORT};
    server_name _;
    root ${SEL_DOCROOT};
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:${fpm_sock};
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht { deny all; }

    error_log ${NGINX_LOG_DIR}/custom-stack-error.log;
    access_log ${NGINX_LOG_DIR}/custom-stack-access.log;
}
NGINX
            ln -sf "$block_file" /etc/nginx/sites-enabled/custom-stack
            ;;
        fedora)
            local block_file="${NGINX_CONF_DIR}/conf.d/custom-stack.conf"
            cat > "$block_file" <<NGINX
server {
    listen ${SEL_PORT};
    server_name _;
    root ${SEL_DOCROOT};
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        fastcgi_pass unix:${fpm_sock};
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht { deny all; }

    error_log ${NGINX_LOG_DIR}/custom-stack-error.log;
    access_log ${NGINX_LOG_DIR}/custom-stack-access.log;
}
NGINX
            ;;
        macos)
            local block_file="${NGINX_CONF_DIR}/servers/custom-stack.conf"
            mkdir -p "${NGINX_CONF_DIR}/servers"
            cat > "$block_file" <<NGINX
server {
    listen ${SEL_PORT};
    server_name _;
    root ${SEL_DOCROOT};
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        fastcgi_pass unix:${fpm_sock};
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    error_log ${NGINX_LOG_DIR}/custom-stack-error.log;
    access_log ${NGINX_LOG_DIR}/custom-stack-access.log;
}
NGINX
            ;;
    esac

    log_success "Nginx installed and configured."
}

install_mysql() {
    log_info "Installing MySQL Server..."

    local mysql_svc="mysql"
    [ "$DISTRO" = "fedora" ] && mysql_svc="mysqld"

    case "$DISTRO" in
        debian)
            # MySQL post-install may fail in containers (can't stop mysqld).
            # Install with || true, then fix pending dpkg if needed.
            pkg_install mysql-server || {
                log_warn "MySQL post-install had errors (common in containers). Fixing..."
                # Kill any leftover mysqld from failed post-install
                killall mysqld 2>/dev/null; sleep 2
                dpkg --configure -a 2>/dev/null || true
            }
            ;;
        fedora) pkg_install mysql-server ;;
        macos)  pkg_install mysql ;;
    esac

    svc_enable "$mysql_svc"
    svc_start "$mysql_svc"

    local root_pass
    root_pass=$(generate_password)
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${root_pass}'; FLUSH PRIVILEGES;" 2>/dev/null \
        && save_credential "MySQL" "root" "$root_pass" \
        || log_warn "Could not set MySQL root password — using default auth."

    log_success "MySQL installed."

    if [ "$DISTRO" != "macos" ]; then
        local run_secure
        read -p "  Run mysql_secure_installation? (Recommended for production) (y/N): " run_secure
        if [[ "$run_secure" =~ ^[Yy]$ ]]; then
            mysql_secure_installation || log_warn "mysql_secure_installation failed."
        else
            log_warn "Skipped mysql_secure_installation."
        fi
    fi
}

install_mariadb() {
    log_info "Installing MariaDB Server..."

    case "$DISTRO" in
        debian)
            pkg_install mariadb-server || {
                log_warn "MariaDB post-install had errors (common in containers). Fixing..."
                killall mariadbd mysqld 2>/dev/null; sleep 2
                dpkg --configure -a 2>/dev/null || true
            }
            ;;
        fedora) pkg_install mariadb-server ;;
        macos)  pkg_install mariadb ;;
    esac

    svc_enable mariadb
    svc_start mariadb

    local root_pass
    root_pass=$(generate_password)
    mariadb -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${root_pass}'; FLUSH PRIVILEGES;" 2>/dev/null \
        && save_credential "MariaDB" "root" "$root_pass" \
        || log_warn "Could not set MariaDB root password — using default auth."

    log_success "MariaDB installed."

    if [ "$DISTRO" != "macos" ]; then
        local run_secure
        read -p "  Run mariadb-secure-installation? (Recommended for production) (y/N): " run_secure
        if [[ "$run_secure" =~ ^[Yy]$ ]]; then
            mariadb-secure-installation || log_warn "mariadb-secure-installation failed."
        else
            log_warn "Skipped mariadb-secure-installation."
        fi
    fi
}

install_postgresql() {
    log_info "Installing PostgreSQL..."

    case "$DISTRO" in
        debian) pkg_install postgresql postgresql-contrib ;;
        fedora)
            pkg_install postgresql-server postgresql-contrib
            postgresql-setup --initdb 2>/dev/null || true
            ;;
        macos)  pkg_install postgresql@16 ;;
    esac

    local pg_svc="postgresql"
    [ "$DISTRO" = "macos" ] && pg_svc="postgresql@16"

    svc_enable "$pg_svc"
    svc_start "$pg_svc"

    local pg_pass
    pg_pass=$(generate_password)

    case "$DISTRO" in
        macos)
            psql -U "$(whoami)" -d postgres -c "ALTER USER $(whoami) PASSWORD '${pg_pass}';" 2>/dev/null \
                && save_credential "PostgreSQL" "$(whoami)" "$pg_pass" \
                || log_warn "Could not set PostgreSQL password."
            ;;
        *)
            su - postgres -c "psql -c \"ALTER USER postgres PASSWORD '${pg_pass}';\"" 2>/dev/null \
                && save_credential "PostgreSQL" "postgres" "$pg_pass" \
                || log_warn "Could not set PostgreSQL password — using default peer auth."
            ;;
    esac

    log_success "PostgreSQL installed."
}

install_mongodb() {
    log_info "Installing MongoDB..."

    case "$DISTRO" in
        debian)
            pkg_install gnupg curl
            curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | \
                gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg
            local codename
            codename=$(lsb_release -cs 2>/dev/null || echo "jammy")
            echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu ${codename}/mongodb-org/7.0 multiverse" \
                > /etc/apt/sources.list.d/mongodb-org-7.0.list
            pkg_update
            pkg_install mongodb-org
            ;;
        fedora)
            cat > /etc/yum.repos.d/mongodb-org-7.0.repo <<'REPO'
[mongodb-org-7.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/$releasever/mongodb-org/7.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://pgp.mongodb.com/server-7.0.asc
REPO
            pkg_install mongodb-org
            ;;
        macos)
            brew tap mongodb/brew 2>/dev/null || true
            pkg_install mongodb-community
            ;;
    esac

    local mongo_svc="mongod"
    [ "$DISTRO" = "macos" ] && mongo_svc="mongodb-community"

    svc_daemon_reload
    svc_enable "$mongo_svc"
    svc_start "$mongo_svc"

    local mongo_pass
    mongo_pass=$(generate_password)
    mongosh --quiet --eval "
        use admin;
        db.createUser({
            user: 'admin',
            pwd: '${mongo_pass}',
            roles: ['root']
        });
    " 2>/dev/null \
        && save_credential "MongoDB" "admin" "$mongo_pass" \
        || log_warn "Could not create MongoDB admin user — using default (no auth)."

    log_success "MongoDB installed."
}

configure_php_ini() {
    log_info "Configuring PHP ini settings..."

    local ini_files=""

    case "$DISTRO" in
        debian)
            ini_files=$(find /etc/php -name "php.ini" -type f 2>/dev/null)
            ;;
        fedora)
            ini_files=$(find /etc -name "php.ini" -type f 2>/dev/null)
            ;;
        macos)
            # Homebrew PHP
            local brew_php_dir
            brew_php_dir=$(find /opt/homebrew/etc/php -maxdepth 1 -type d 2>/dev/null | tail -1)
            if [ -n "$brew_php_dir" ]; then
                if [ ! -f "${brew_php_dir}/php.ini" ] && [ -f "${brew_php_dir}/php.ini.default" ]; then
                    cp "${brew_php_dir}/php.ini.default" "${brew_php_dir}/php.ini"
                fi
                ini_files="${brew_php_dir}/php.ini"
            fi
            ;;
    esac

    if [ -z "$ini_files" ]; then
        log_warn "No php.ini files found. Skipping configuration."
        return 0
    fi

    for ini_file in $ini_files; do
        log_info "  Updating $ini_file"
        sed_i "s/^upload_max_filesize\s*=.*/upload_max_filesize = ${SEL_UPLOAD_MAX}/" "$ini_file"
        sed_i "s/^post_max_size\s*=.*/post_max_size = ${SEL_POST_MAX}/" "$ini_file"
        sed_i "s/^memory_limit\s*=.*/memory_limit = ${SEL_MEMORY_LIMIT}/" "$ini_file"
        sed_i "s/^max_execution_time\s*=.*/max_execution_time = ${SEL_MAX_EXEC_TIME}/" "$ini_file"
        sed_i "s/^;*\s*max_input_vars\s*=.*/max_input_vars = ${SEL_MAX_INPUT_VARS}/" "$ini_file"
    done

    log_success "PHP ini settings configured."
}

setup_document_root() {
    log_info "Setting up document root at $SEL_DOCROOT..."

    mkdir -p "$SEL_DOCROOT"

    if [ "$DISTRO" != "macos" ]; then
        set_web_owner "$SEL_DOCROOT"
        chmod -R 755 "$SEL_DOCROOT"
    fi

    cat > "${SEL_DOCROOT}/index.php" <<'PHPINFO'
<?php
phpinfo();
PHPINFO

    [ "$DISTRO" != "macos" ] && set_web_owner "${SEL_DOCROOT}/index.php"

    log_success "Document root ready with test index.php."
}

configure_firewall() {
    case "$DISTRO" in
        debian)
            log_info "Configuring UFW firewall..."
            if ! command -v ufw >/dev/null 2>&1; then
                pkg_install ufw
            fi
            if ufw --force enable 2>/dev/null; then
                ufw allow 22/tcp
                ufw allow "${SEL_PORT}/tcp"
                log_success "UFW enabled: SSH (22) and port ${SEL_PORT} allowed."
            else
                log_warn "UFW not available (container/VM?). Skipping firewall."
            fi
            ;;
        fedora)
            log_info "Configuring firewalld..."
            if ! command -v firewall-cmd >/dev/null 2>&1; then
                pkg_install firewalld
                svc_enable firewalld
                svc_start firewalld
            fi
            firewall-cmd --permanent --add-port="${SEL_PORT}/tcp" 2>/dev/null || true
            firewall-cmd --permanent --add-service=ssh 2>/dev/null || true
            firewall-cmd --reload 2>/dev/null || true
            log_success "firewalld: SSH and port ${SEL_PORT} allowed."
            ;;
        macos)
            log_info "macOS: Firewall configuration skipped (use System Settings > Firewall)."
            ;;
    esac
}

restart_services() {
    log_info "Restarting services..."

    local fpm_svc
    fpm_svc=$(get_fpm_service "$PHP_VER")
    svc_restart "$fpm_svc" 2>/dev/null && log_success "  $fpm_svc restarted." || true

    if [ "$SEL_WEBSERVER" = "apache" ]; then
        svc_restart "$APACHE_SVC"
        log_success "  $APACHE_SVC restarted."
    elif [ "$SEL_WEBSERVER" = "nginx" ]; then
        svc_restart nginx
        log_success "  Nginx restarted."
    fi

    if [ "$SEL_MYSQL" = "on" ]; then
        local mysql_svc="mysql"
        [ "$DISTRO" = "fedora" ] && mysql_svc="mysqld"
        svc_restart "$mysql_svc"
        log_success "  MySQL restarted."
    fi
    if [ "$SEL_MARIADB" = "on" ]; then
        svc_restart mariadb
        log_success "  MariaDB restarted."
    fi
    if [ "$SEL_POSTGRESQL" = "on" ]; then
        local pg_svc="postgresql"
        [ "$DISTRO" = "macos" ] && pg_svc="postgresql@16"
        svc_restart "$pg_svc"
        log_success "  PostgreSQL restarted."
    fi
    if [ "$SEL_MONGODB" = "on" ]; then
        local mongo_svc="mongod"
        [ "$DISTRO" = "macos" ] && mongo_svc="mongodb-community"
        svc_restart "$mongo_svc"
        log_success "  MongoDB restarted."
    fi
}

