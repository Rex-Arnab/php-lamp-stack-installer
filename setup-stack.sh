#!/bin/bash
# ==============================================================================
# Interactive LAMP/LEMP Stack Setup Script
# Menu-driven web development stack installer for Ubuntu/Debian
# ==============================================================================

set -e

# ── Section 1: Bootstrap ─────────────────────────────────────────────────────

# Color helpers
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Script failed at line $BASH_LINENO with exit code $exit_code"
        log_error "Check the output above for details."
    fi
    # Remove temp files
    rm -f /tmp/stack_dialog_* 2>/dev/null
    exit $exit_code
}
trap cleanup EXIT

# Root check
if [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be run as root (use sudo)."
    exit 1
fi

# Detect dialog tool
DIALOG_BIN=""
if command -v dialog >/dev/null 2>&1; then
    DIALOG_BIN="dialog"
elif command -v whiptail >/dev/null 2>&1; then
    DIALOG_BIN="whiptail"
else
    log_info "Installing dialog..."
    apt-get update -y -qq
    apt-get install -y -qq dialog
    DIALOG_BIN="dialog"
fi

log_info "Using $DIALOG_BIN for interactive menus."

# Initial apt update
log_info "Updating package lists..."
apt-get update -y -qq

# ── Selection variables ───────────────────────────────────────────────────────

SEL_WEBSERVER=""
SEL_MYSQL="off"
SEL_MARIADB="off"
SEL_POSTGRESQL="off"
SEL_MONGODB="off"
SEL_PHP_EXTS=""
SEL_UPLOAD_MAX="64M"
SEL_POST_MAX="128M"
SEL_MEMORY_LIMIT="256M"
SEL_MAX_EXEC_TIME="300"
SEL_MAX_INPUT_VARS="3000"
SEL_DOCROOT="/var/www/html"
SEL_PORT="80"

# ── Section 2: Interactive Menus ──────────────────────────────────────────────

# Helper: run dialog/whiptail and capture output
# Both tools write user selection to stderr, so we redirect to a temp file
run_dialog() {
    local tmpfile="/tmp/stack_dialog_result"
    if [ "$DIALOG_BIN" = "dialog" ]; then
        "$DIALOG_BIN" "$@" 2>"$tmpfile"
    else
        "$DIALOG_BIN" "$@" 2>"$tmpfile"
    fi
    local rc=$?
    cat "$tmpfile"
    return $rc
}

# ── Step 1: Web Server ────────────────────────────────────────────────────────

pick_webserver() {
    local result
    if [ "$DIALOG_BIN" = "dialog" ]; then
        result=$(run_dialog --title "Web Server" \
            --radiolist "Select a web server:\n(Use SPACE to select, ENTER to confirm)" 12 50 2 \
            "apache2" "Apache HTTP Server" on \
            "nginx"   "Nginx Web Server"   off) || { log_error "Cancelled."; exit 1; }
    else
        result=$(run_dialog --title "Web Server" \
            --radiolist "Select a web server:\n(Use SPACE to select, ENTER to confirm)" 12 50 2 \
            "apache2" "Apache HTTP Server" on \
            "nginx"   "Nginx Web Server"   off) || { log_error "Cancelled."; exit 1; }
    fi
    SEL_WEBSERVER="$result"
}

# ── Step 2: SQL Databases ────────────────────────────────────────────────────

pick_sql_databases() {
    local result
    result=$(run_dialog --title "SQL Databases" \
        --checklist "Select SQL databases to install:\n(SPACE to toggle, ENTER to confirm)" 14 55 3 \
        "mysql"      "MySQL Server"      off \
        "mariadb"    "MariaDB Server"    off \
        "postgresql" "PostgreSQL Server" off) || { log_warn "No SQL database selected."; return 0; }

    case "$result" in
        *mysql*)      SEL_MYSQL="on" ;;
    esac
    case "$result" in
        *mariadb*)    SEL_MARIADB="on" ;;
    esac
    case "$result" in
        *postgresql*) SEL_POSTGRESQL="on" ;;
    esac
}

# ── Step 3: MongoDB ──────────────────────────────────────────────────────────

pick_mongodb() {
    if "$DIALOG_BIN" --title "NoSQL Database" \
        --yesno "Install MongoDB?" 7 40 2>/dev/null; then
        SEL_MONGODB="on"
    fi
}

# ── Step 4: PHP Extensions ───────────────────────────────────────────────────

pick_php_extensions() {
    # Build the checklist items
    # Base extensions (pre-checked)
    local items=""
    items="$items php-cli        'PHP CLI'           on"
    items="$items php-fpm        'FastCGI Process Manager' on"
    items="$items php-common     'Common files'      on"
    items="$items php-curl       'cURL support'      on"
    items="$items php-gd         'GD graphics'       on"
    items="$items php-mbstring   'Multibyte strings'  on"
    items="$items php-xml        'XML support'       on"
    items="$items php-zip        'ZIP support'       on"
    items="$items php-intl       'Internationalization' on"
    items="$items php-bcmath     'BC Math'           on"
    items="$items php-soap       'SOAP support'      on"
    items="$items php-redis      'Redis extension'   on"
    items="$items php-imagick    'ImageMagick'       on"
    items="$items php-sqlite3    'SQLite3 support'   on"
    items="$items php-tokenizer  'Tokenizer'         on"
    items="$items php-fileinfo   'File info'         on"
    items="$items php-opcache    'OPcache'           on"
    items="$items php-readline   'Readline'          on"

    # Conditional extensions
    if [ "$SEL_MYSQL" = "on" ] || [ "$SEL_MARIADB" = "on" ]; then
        items="$items php-mysql 'MySQL/MariaDB driver' on"
    fi
    if [ "$SEL_POSTGRESQL" = "on" ]; then
        items="$items php-pgsql 'PostgreSQL driver' on"
    fi
    if [ "$SEL_MONGODB" = "on" ]; then
        items="$items php-mongodb 'MongoDB driver' on"
    fi

    # Count items (each item has 3 fields)
    local item_count
    item_count=$(echo "$items" | xargs -n3 | wc -l | tr -d ' ')

    local height=$((item_count + 8))
    if [ "$height" -gt 30 ]; then
        height=30
    fi

    local result
    result=$(eval run_dialog --title \"PHP Extensions\" \
        --checklist \"'Select PHP extensions to install:'\" "$height" 60 "$item_count" \
        "$items") || { log_error "Cancelled."; exit 1; }

    SEL_PHP_EXTS="$result"
}

# ── Step 5: PHP Settings ────────────────────────────────────────────────────

pick_php_settings() {
    local tmpfile="/tmp/stack_dialog_result"

    if [ "$DIALOG_BIN" = "dialog" ]; then
        dialog --title "PHP Settings" \
            --form "Configure PHP ini values:" 15 60 5 \
            "upload_max_filesize:" 1 1 "$SEL_UPLOAD_MAX"     1 22 10 0 \
            "post_max_size:"      2 1 "$SEL_POST_MAX"        2 22 10 0 \
            "memory_limit:"       3 1 "$SEL_MEMORY_LIMIT"    3 22 10 0 \
            "max_execution_time:" 4 1 "$SEL_MAX_EXEC_TIME"   4 22 10 0 \
            "max_input_vars:"     5 1 "$SEL_MAX_INPUT_VARS"  5 22 10 0 \
            2>"$tmpfile" || { log_error "Cancelled."; exit 1; }

        # dialog --form outputs one value per line
        local line_num=0
        while IFS= read -r line; do
            line_num=$((line_num + 1))
            case $line_num in
                1) [ -n "$line" ] && SEL_UPLOAD_MAX="$line" ;;
                2) [ -n "$line" ] && SEL_POST_MAX="$line" ;;
                3) [ -n "$line" ] && SEL_MEMORY_LIMIT="$line" ;;
                4) [ -n "$line" ] && SEL_MAX_EXEC_TIME="$line" ;;
                5) [ -n "$line" ] && SEL_MAX_INPUT_VARS="$line" ;;
            esac
        done < "$tmpfile"
    else
        # whiptail doesn't support --form, use individual inputboxes
        local val
        val=$(run_dialog --title "PHP Settings" --inputbox "upload_max_filesize:" 8 50 "$SEL_UPLOAD_MAX") && SEL_UPLOAD_MAX="$val"
        val=$(run_dialog --title "PHP Settings" --inputbox "post_max_size:" 8 50 "$SEL_POST_MAX") && SEL_POST_MAX="$val"
        val=$(run_dialog --title "PHP Settings" --inputbox "memory_limit:" 8 50 "$SEL_MEMORY_LIMIT") && SEL_MEMORY_LIMIT="$val"
        val=$(run_dialog --title "PHP Settings" --inputbox "max_execution_time:" 8 50 "$SEL_MAX_EXEC_TIME") && SEL_MAX_EXEC_TIME="$val"
        val=$(run_dialog --title "PHP Settings" --inputbox "max_input_vars:" 8 50 "$SEL_MAX_INPUT_VARS") && SEL_MAX_INPUT_VARS="$val"
    fi
}

# ── Step 6: Document Root ────────────────────────────────────────────────────

pick_docroot() {
    local result
    result=$(run_dialog --title "Document Root" \
        --inputbox "Enter the document root path:" 8 60 "$SEL_DOCROOT") || { log_error "Cancelled."; exit 1; }
    [ -n "$result" ] && SEL_DOCROOT="$result"
}

# ── Step 7: Port ─────────────────────────────────────────────────────────────

pick_port() {
    local result
    result=$(run_dialog --title "Server Port" \
        --inputbox "Enter the port number:" 8 50 "$SEL_PORT") || { log_error "Cancelled."; exit 1; }
    [ -n "$result" ] && SEL_PORT="$result"
}

# ── Step 8: Confirmation ─────────────────────────────────────────────────────

confirm_selections() {
    local db_list=""
    [ "$SEL_MYSQL" = "on" ] && db_list="${db_list}MySQL "
    [ "$SEL_MARIADB" = "on" ] && db_list="${db_list}MariaDB "
    [ "$SEL_POSTGRESQL" = "on" ] && db_list="${db_list}PostgreSQL "
    [ "$SEL_MONGODB" = "on" ] && db_list="${db_list}MongoDB "
    [ -z "$db_list" ] && db_list="None"

    # Clean up extension list for display
    local ext_display
    ext_display=$(echo "$SEL_PHP_EXTS" | sed 's/"//g' | tr ' ' '\n' | sort | tr '\n' ' ')

    local summary="
Web Server:         $SEL_WEBSERVER
Databases:          $db_list
PHP Extensions:     $ext_display

PHP Settings:
  upload_max_filesize = $SEL_UPLOAD_MAX
  post_max_size       = $SEL_POST_MAX
  memory_limit        = $SEL_MEMORY_LIMIT
  max_execution_time  = $SEL_MAX_EXEC_TIME
  max_input_vars      = $SEL_MAX_INPUT_VARS

Document Root:      $SEL_DOCROOT
Port:               $SEL_PORT
"

    "$DIALOG_BIN" --title "Confirm Installation" \
        --yesno "Review your selections:\n$summary\nProceed with installation?" 26 70 2>/dev/null \
        || { log_error "Installation cancelled."; exit 1; }
}

# ── Section 3: Installation Functions ─────────────────────────────────────────

install_php() {
    log_info "Adding ondrej/php PPA..."
    apt-get install -y -qq software-properties-common
    add-apt-repository -y ppa:ondrej/php
    apt-get update -y -qq

    # Determine latest PHP version from the PPA
    local php_ver
    php_ver=$(apt-cache showpkg php-fpm 2>/dev/null | grep -oP 'php\K[0-9]+\.[0-9]+' | sort -V | tail -1)
    if [ -z "$php_ver" ]; then
        php_ver="8.3"
    fi
    log_info "Installing PHP $php_ver..."

    # Build extension list with version prefix
    local exts_to_install=""
    local raw_exts
    raw_exts=$(echo "$SEL_PHP_EXTS" | sed 's/"//g')

    for ext in $raw_exts; do
        # Strip any existing version prefix and re-add the correct one
        local base_ext
        base_ext=$(echo "$ext" | sed "s/^php[0-9]*\.[0-9]*-/php${php_ver}-/; s/^php-/php${php_ver}-/")
        exts_to_install="$exts_to_install $base_ext"
    done

    # Install PHP and extensions
    # shellcheck disable=SC2086
    apt-get install -y -qq php${php_ver} $exts_to_install

    log_success "PHP $php_ver installed with extensions."

    # Export for later use
    PHP_VER="$php_ver"
}

install_apache() {
    log_info "Installing Apache2..."
    apt-get install -y -qq apache2 libapache2-mod-fcgid

    # Enable required modules
    a2enmod rewrite
    a2enmod proxy_fcgi
    a2enmod setenvif

    # Disable default site
    a2dissite 000-default.conf 2>/dev/null || true

    # Write custom vhost
    local vhost_file="/etc/apache2/sites-available/custom-stack.conf"
    cat > "$vhost_file" <<VHOST
<VirtualHost *:${SEL_PORT}>
    ServerAdmin webmaster@localhost
    DocumentRoot ${SEL_DOCROOT}

    <Directory ${SEL_DOCROOT}>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    <FilesMatch \.php\$>
        SetHandler "proxy:unix:/run/php/php${PHP_VER}-fpm.sock|fcgi://localhost"
    </FilesMatch>

    ErrorLog \${APACHE_LOG_DIR}/custom-stack-error.log
    CustomLog \${APACHE_LOG_DIR}/custom-stack-access.log combined
</VirtualHost>
VHOST

    # Update ports.conf if non-standard port
    if [ "$SEL_PORT" != "80" ]; then
        if ! grep -q "Listen ${SEL_PORT}" /etc/apache2/ports.conf; then
            echo "Listen ${SEL_PORT}" >> /etc/apache2/ports.conf
        fi
    fi

    a2ensite custom-stack.conf

    log_success "Apache2 installed and configured."
}

install_nginx() {
    log_info "Installing Nginx..."
    apt-get install -y -qq nginx

    # Disable default site
    rm -f /etc/nginx/sites-enabled/default

    # Write server block
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
        fastcgi_pass unix:/run/php/php${PHP_VER}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }

    error_log /var/log/nginx/custom-stack-error.log;
    access_log /var/log/nginx/custom-stack-access.log;
}
NGINX

    ln -sf "$block_file" /etc/nginx/sites-enabled/custom-stack

    log_success "Nginx installed and configured."
}

install_mysql() {
    log_info "Installing MySQL Server..."
    apt-get install -y -qq mysql-server

    systemctl enable mysql
    systemctl start mysql

    # Set root password
    local root_pass
    root_pass=$(generate_password)
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${root_pass}'; FLUSH PRIVILEGES;" 2>/dev/null \
        && save_credential "MySQL" "root" "$root_pass" \
        || log_warn "Could not set MySQL root password — using default auth."

    log_success "MySQL installed."

    "$DIALOG_BIN" --title "MySQL Security" \
        --yesno "Run mysql_secure_installation now?\n(Recommended for production servers)\n\nNote: root password was auto-set. You can change it during this step." 10 55 2>/dev/null \
        && mysql_secure_installation || log_warn "Skipped mysql_secure_installation."
}

install_mariadb() {
    log_info "Installing MariaDB Server..."
    apt-get install -y -qq mariadb-server

    systemctl enable mariadb
    systemctl start mariadb

    # Set root password
    local root_pass
    root_pass=$(generate_password)
    mariadb -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${root_pass}'; FLUSH PRIVILEGES;" 2>/dev/null \
        && save_credential "MariaDB" "root" "$root_pass" \
        || log_warn "Could not set MariaDB root password — using default auth."

    log_success "MariaDB installed."

    "$DIALOG_BIN" --title "MariaDB Security" \
        --yesno "Run mariadb-secure-installation now?\n(Recommended for production servers)\n\nNote: root password was auto-set. You can change it during this step." 10 55 2>/dev/null \
        && mariadb-secure-installation || log_warn "Skipped mariadb-secure-installation."
}

install_postgresql() {
    log_info "Installing PostgreSQL..."
    apt-get install -y -qq postgresql postgresql-contrib

    systemctl enable postgresql
    systemctl start postgresql

    # Set postgres user password
    local pg_pass
    pg_pass=$(generate_password)
    su - postgres -c "psql -c \"ALTER USER postgres PASSWORD '${pg_pass}';\"" 2>/dev/null \
        && save_credential "PostgreSQL" "postgres" "$pg_pass" \
        || log_warn "Could not set PostgreSQL password — using default peer auth."

    log_success "PostgreSQL installed."
}

install_mongodb() {
    log_info "Installing MongoDB from official repository..."

    apt-get install -y -qq gnupg curl

    # Import MongoDB GPG key
    curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | \
        gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg

    # Detect Ubuntu codename
    local codename
    codename=$(lsb_release -cs 2>/dev/null || echo "jammy")

    # Add MongoDB repo
    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu ${codename}/mongodb-org/7.0 multiverse" \
        > /etc/apt/sources.list.d/mongodb-org-7.0.list

    apt-get update -y -qq
    apt-get install -y -qq mongodb-org

    systemctl daemon-reload
    systemctl enable mongod
    systemctl start mongod

    # Create admin user with password
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

    log_success "MongoDB 7.0 installed."
}

configure_php_ini() {
    log_info "Configuring PHP ini settings..."

    # Find all php.ini files (cli, fpm, apache2)
    local ini_files
    ini_files=$(find /etc/php -name "php.ini" -type f 2>/dev/null)

    if [ -z "$ini_files" ]; then
        log_warn "No php.ini files found. Skipping configuration."
        return 0
    fi

    for ini_file in $ini_files; do
        log_info "  Updating $ini_file"

        sed -i "s/^upload_max_filesize\s*=.*/upload_max_filesize = ${SEL_UPLOAD_MAX}/" "$ini_file"
        sed -i "s/^post_max_size\s*=.*/post_max_size = ${SEL_POST_MAX}/" "$ini_file"
        sed -i "s/^memory_limit\s*=.*/memory_limit = ${SEL_MEMORY_LIMIT}/" "$ini_file"
        sed -i "s/^max_execution_time\s*=.*/max_execution_time = ${SEL_MAX_EXEC_TIME}/" "$ini_file"
        sed -i "s/^;*\s*max_input_vars\s*=.*/max_input_vars = ${SEL_MAX_INPUT_VARS}/" "$ini_file"
    done

    log_success "PHP ini settings configured."
}

setup_document_root() {
    log_info "Setting up document root at $SEL_DOCROOT..."

    mkdir -p "$SEL_DOCROOT"
    chown -R www-data:www-data "$SEL_DOCROOT"
    chmod -R 755 "$SEL_DOCROOT"

    # Drop a test index.php
    cat > "${SEL_DOCROOT}/index.php" <<'PHPINFO'
<?php
phpinfo();
PHPINFO

    chown www-data:www-data "${SEL_DOCROOT}/index.php"

    log_success "Document root ready with test index.php."
}

configure_firewall() {
    log_info "Configuring UFW firewall..."

    if ! command -v ufw >/dev/null 2>&1; then
        apt-get install -y -qq ufw
    fi

    ufw --force enable
    ufw allow 22/tcp    # SSH
    ufw allow "${SEL_PORT}/tcp"

    log_success "UFW enabled: SSH (22) and port ${SEL_PORT} allowed."
}

restart_services() {
    log_info "Restarting services..."

    # PHP-FPM
    if systemctl list-units --type=service | grep -q "php.*-fpm"; then
        systemctl restart "php${PHP_VER}-fpm"
        log_success "  php${PHP_VER}-fpm restarted."
    fi

    # Web server
    if [ "$SEL_WEBSERVER" = "apache2" ]; then
        systemctl restart apache2
        log_success "  Apache2 restarted."
    elif [ "$SEL_WEBSERVER" = "nginx" ]; then
        systemctl restart nginx
        log_success "  Nginx restarted."
    fi

    # Databases
    if [ "$SEL_MYSQL" = "on" ]; then
        systemctl restart mysql
        log_success "  MySQL restarted."
    fi
    if [ "$SEL_MARIADB" = "on" ]; then
        systemctl restart mariadb
        log_success "  MariaDB restarted."
    fi
    if [ "$SEL_POSTGRESQL" = "on" ]; then
        systemctl restart postgresql
        log_success "  PostgreSQL restarted."
    fi
    if [ "$SEL_MONGODB" = "on" ]; then
        systemctl restart mongod
        log_success "  MongoDB restarted."
    fi
}

# ── Section 4: Control Panel ─────────────────────────────────────────────────

STACK_CONFIG="/etc/stack-panel.conf"
STACK_CREDS="/etc/stack-panel.creds"

generate_password() {
    tr -dc 'A-Za-z0-9!@#$%&*' < /dev/urandom | head -c 20 || true
}

save_credential() {
    local service="$1" user="$2" password="$3"
    # Create creds file with strict permissions if it doesn't exist
    if [ ! -f "$STACK_CREDS" ]; then
        touch "$STACK_CREDS"
        chmod 600 "$STACK_CREDS"
    fi
    # Remove old entry for this service, then append new one
    sed -i "/^${service}|/d" "$STACK_CREDS"
    echo "${service}|${user}|${password}" >> "$STACK_CREDS"
}

show_db_credentials() {
    if [ ! -f "$STACK_CREDS" ] || [ ! -s "$STACK_CREDS" ]; then
        "$DIALOG_BIN" --title "DB Credentials" \
            --msgbox "No credentials stored.\n\nThis can happen if:\n- Databases were installed before this feature\n- No databases were installed\n\nCheck manually:\n  MySQL/MariaDB: sudo mysql\n  PostgreSQL: sudo -u postgres psql" 14 55 2>/dev/null
        return
    fi

    local cred_text="Stored Database Credentials\n"
    cred_text="${cred_text}$(printf '=%.0s' {1..40})\n\n"

    while IFS='|' read -r service user password; do
        [ -z "$service" ] && continue

        # Verify if the stored password still works
        local status="?"
        case "$service" in
            MySQL)
                mysql -u"$user" -p"$password" -e "SELECT 1;" >/dev/null 2>&1 \
                    && status="VALID" || status="CHANGED"
                ;;
            MariaDB)
                mariadb -u"$user" -p"$password" -e "SELECT 1;" >/dev/null 2>&1 \
                    && status="VALID" || status="CHANGED"
                ;;
            PostgreSQL)
                PGPASSWORD="$password" psql -U "$user" -d postgres -c "SELECT 1;" >/dev/null 2>&1 \
                    && status="VALID" || status="CHANGED"
                ;;
            MongoDB)
                mongosh --quiet -u "$user" -p "$password" --authenticationDatabase admin --eval "db.runCommand({ping:1})" >/dev/null 2>&1 \
                    && status="VALID" || status="CHANGED"
                ;;
        esac

        cred_text="${cred_text}  Service:  ${service}\n"
        cred_text="${cred_text}  User:     ${user}\n"
        cred_text="${cred_text}  Password: ${password}\n"
        if [ "$status" = "VALID" ]; then
            cred_text="${cred_text}  Status:   [VALID]\n\n"
        else
            cred_text="${cred_text}  Status:   [CHANGED externally]\n\n"
        fi
    done < "$STACK_CREDS"

    cred_text="${cred_text}$(printf '-%.0s' {1..40})\n"
    cred_text="${cred_text}If status shows CHANGED, the password\n"
    cred_text="${cred_text}was modified outside this tool\n"
    cred_text="${cred_text}(via phpMyAdmin, CLI, etc).\n\n"
    cred_text="${cred_text}File: ${STACK_CREDS} (root-only, 600)"

    "$DIALOG_BIN" --title "DB Credentials" \
        --msgbox "$cred_text" 26 55 2>/dev/null
}

save_stack_config() {
    cat > "$STACK_CONFIG" <<EOF
WEBSERVER=${SEL_WEBSERVER}
DOCROOT=${SEL_DOCROOT}
PORT=${SEL_PORT}
PHP_VER=${PHP_VER}
HAS_MYSQL=${SEL_MYSQL}
HAS_MARIADB=${SEL_MARIADB}
HAS_POSTGRESQL=${SEL_POSTGRESQL}
HAS_MONGODB=${SEL_MONGODB}
HAS_PHPMYADMIN=off
HAS_ADMINER=off
EOF
    log_success "Stack config saved to $STACK_CONFIG"
}

load_stack_config() {
    if [ ! -f "$STACK_CONFIG" ]; then
        log_error "No stack config found at $STACK_CONFIG"
        log_error "Run the installer first, or re-run without --panel."
        exit 1
    fi
    # shellcheck disable=SC1090
    . "$STACK_CONFIG"
    # Map config vars to selection vars used elsewhere
    SEL_WEBSERVER="$WEBSERVER"
    SEL_DOCROOT="$DOCROOT"
    SEL_PORT="$PORT"
    SEL_MYSQL="$HAS_MYSQL"
    SEL_MARIADB="$HAS_MARIADB"
    SEL_POSTGRESQL="$HAS_POSTGRESQL"
    SEL_MONGODB="$HAS_MONGODB"
}

open_in_browser() {
    local url="$1"
    if [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
        if command -v xdg-open >/dev/null 2>&1; then
            xdg-open "$url" 2>/dev/null &
        elif command -v sensible-browser >/dev/null 2>&1; then
            sensible-browser "$url" 2>/dev/null &
        else
            log_warn "No browser launcher found."
            log_info "Open manually: $url"
            return
        fi
        log_success "Opened $url in browser."
    else
        log_info "No display detected. Open this URL manually:"
        echo -e "  ${GREEN}${url}${NC}"
        "$DIALOG_BIN" --title "URL" --msgbox "No display detected.\nOpen this URL in your browser:\n\n$url" 10 60 2>/dev/null
    fi
}

create_phpinfo_page() {
    local target="${DOCROOT:-$SEL_DOCROOT}/info.php"
    if [ -f "$target" ]; then
        log_info "info.php already exists at $target"
    else
        cat > "$target" <<'PHPFILE'
<?php phpinfo();
PHPFILE
        chown www-data:www-data "$target"
        log_success "Created $target"
    fi
}

deploy_file_explorer() {
    local docroot="${DOCROOT:-$SEL_DOCROOT}"
    local target="${docroot}/explorer.php"
    cat > "$target" <<'EXPLORER'
<?php
/**
 * Minimal PHP File Explorer — Development Tool
 * WARNING: Remove this file in production!
 */

$docroot = realpath(__DIR__);
$requested = isset($_GET['path']) ? $_GET['path'] : '';
$current = realpath($docroot . '/' . $requested);

if ($current === false || strpos($current, $docroot) !== 0) {
    $current = $docroot;
    $requested = '';
}
?>
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>File Explorer</title>
<style>
    body { font-family: monospace; background: #1a1a2e; color: #e0e0e0; margin: 20px; }
    .warn { background: #ff6b35; color: #000; padding: 8px 16px; border-radius: 4px; margin-bottom: 16px; font-weight: bold; }
    table { border-collapse: collapse; width: 100%; }
    th, td { text-align: left; padding: 6px 12px; border-bottom: 1px solid #333; }
    th { background: #16213e; }
    a { color: #4fc3f7; text-decoration: none; }
    a:hover { text-decoration: underline; }
    .size { color: #aaa; }
    .date { color: #888; }
</style>
</head>
<body>
<div class="warn">Development tool — remove in production!</div>
<h2>File Explorer</h2>
<p>Current: <code><?php echo htmlspecialchars($current); ?></code></p>
<?php if ($current !== $docroot): ?>
    <?php
    $parent = dirname($requested);
    if ($parent === '.') $parent = '';
    ?>
    <p><a href="?path=<?php echo urlencode($parent); ?>">[.. Parent Directory]</a></p>
<?php endif; ?>
<table>
<tr><th>Name</th><th>Size</th><th>Modified</th></tr>
<?php
$items = scandir($current);
foreach ($items as $item) {
    if ($item === '.' || $item === '..') continue;
    $fullpath = $current . '/' . $item;
    $relpath = ($requested !== '' ? $requested . '/' : '') . $item;
    $is_dir = is_dir($fullpath);
    $size = $is_dir ? '-' : number_format(filesize($fullpath)) . ' B';
    $mtime = date('Y-m-d H:i', filemtime($fullpath));
    $display = htmlspecialchars($item) . ($is_dir ? '/' : '');
    if ($is_dir) {
        echo "<tr><td><a href=\"?path=" . urlencode($relpath) . "\">$display</a></td>";
    } else {
        echo "<tr><td>$display</td>";
    }
    echo "<td class=\"size\">$size</td><td class=\"date\">$mtime</td></tr>\n";
}
?>
</table>
</body>
</html>
EXPLORER
    chown www-data:www-data "$target"
    log_success "File explorer deployed to $target"
}

install_phpmyadmin() {
    local docroot="${DOCROOT:-$SEL_DOCROOT}"
    local webserver="${WEBSERVER:-$SEL_WEBSERVER}"

    log_info "Installing phpMyAdmin..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq phpmyadmin

    if [ "$webserver" = "nginx" ]; then
        ln -sf /usr/share/phpmyadmin "${docroot}/phpmyadmin"
        log_info "Symlinked phpMyAdmin into $docroot for Nginx."
    fi

    # Update config
    if [ -f "$STACK_CONFIG" ]; then
        sed -i 's/^HAS_PHPMYADMIN=.*/HAS_PHPMYADMIN=on/' "$STACK_CONFIG"
    fi
    HAS_PHPMYADMIN="on"
    log_success "phpMyAdmin installed."
}

install_adminer() {
    local docroot="${DOCROOT:-$SEL_DOCROOT}"
    local target="${docroot}/adminer.php"

    log_info "Downloading Adminer..."
    curl -fsSL -o "$target" "https://www.adminer.org/latest.php"
    chown www-data:www-data "$target"

    if [ -f "$STACK_CONFIG" ]; then
        sed -i 's/^HAS_ADMINER=.*/HAS_ADMINER=on/' "$STACK_CONFIG"
    fi
    HAS_ADMINER="on"
    log_success "Adminer installed at $target"
}

show_service_status() {
    local webserver="${WEBSERVER:-$SEL_WEBSERVER}"
    local php_ver="${PHP_VER}"
    local status_text=""

    local services=""
    services="$webserver php${php_ver}-fpm"
    [ "${HAS_MYSQL:-${SEL_MYSQL:-off}}" = "on" ] && services="$services mysql"
    [ "${HAS_MARIADB:-${SEL_MARIADB:-off}}" = "on" ] && services="$services mariadb"
    [ "${HAS_POSTGRESQL:-${SEL_POSTGRESQL:-off}}" = "on" ] && services="$services postgresql"
    [ "${HAS_MONGODB:-${SEL_MONGODB:-off}}" = "on" ] && services="$services mongod"

    for svc in $services; do
        local state
        state=$(systemctl is-active "$svc" 2>/dev/null || echo "not-found")
        local label
        case "$state" in
            active)    label="RUNNING" ;;
            inactive)  label="STOPPED" ;;
            failed)    label="FAILED"  ;;
            *)         label="$state"  ;;
        esac
        status_text="${status_text}  ${svc}: ${label}\n"
    done

    "$DIALOG_BIN" --title "Service Status" \
        --msgbox "$status_text" 16 50 2>/dev/null
}

panel_restart_services() {
    local webserver="${WEBSERVER:-$SEL_WEBSERVER}"
    local php_ver="${PHP_VER}"

    local services="$webserver php${php_ver}-fpm"
    [ "${HAS_MYSQL:-${SEL_MYSQL:-off}}" = "on" ] && services="$services mysql"
    [ "${HAS_MARIADB:-${SEL_MARIADB:-off}}" = "on" ] && services="$services mariadb"
    [ "${HAS_POSTGRESQL:-${SEL_POSTGRESQL:-off}}" = "on" ] && services="$services postgresql"
    [ "${HAS_MONGODB:-${SEL_MONGODB:-off}}" = "on" ] && services="$services mongod"

    local result_text=""
    for svc in $services; do
        if systemctl restart "$svc" 2>/dev/null; then
            result_text="${result_text}  ${svc}: restarted OK\n"
        else
            result_text="${result_text}  ${svc}: FAILED to restart\n"
        fi
    done

    "$DIALOG_BIN" --title "Restart Results" \
        --msgbox "$result_text" 16 50 2>/dev/null
}

show_logs_menu() {
    local webserver="${WEBSERVER:-$SEL_WEBSERVER}"
    local php_ver="${PHP_VER}"
    local items=""
    local tag_count=0

    if [ "$webserver" = "apache2" ]; then
        items="$items apache-error  'Apache Error Log'  off"
        items="$items apache-access 'Apache Access Log' off"
        tag_count=$((tag_count + 2))
    elif [ "$webserver" = "nginx" ]; then
        items="$items nginx-error  'Nginx Error Log'  off"
        items="$items nginx-access 'Nginx Access Log' off"
        tag_count=$((tag_count + 2))
    fi

    if [ -n "$php_ver" ]; then
        items="$items php-fpm 'PHP-FPM Log' off"
        tag_count=$((tag_count + 1))
    fi

    if [ "${HAS_MYSQL:-${SEL_MYSQL:-off}}" = "on" ]; then
        items="$items mysql 'MySQL Error Log' off"
        tag_count=$((tag_count + 1))
    fi
    if [ "${HAS_POSTGRESQL:-${SEL_POSTGRESQL:-off}}" = "on" ]; then
        items="$items postgresql 'PostgreSQL Log' off"
        tag_count=$((tag_count + 1))
    fi
    if [ "${HAS_MONGODB:-${SEL_MONGODB:-off}}" = "on" ]; then
        items="$items mongodb 'MongoDB Log' off"
        tag_count=$((tag_count + 1))
    fi

    if [ "$tag_count" -eq 0 ]; then
        "$DIALOG_BIN" --title "Logs" --msgbox "No log sources found." 7 40 2>/dev/null
        return
    fi

    local height=$((tag_count + 8))
    local choice
    choice=$(eval run_dialog --title \"View Logs\" \
        --radiolist \"'Select a log to view:'\" "$height" 55 "$tag_count" \
        "$items") || return 0

    local logfile=""
    case "$choice" in
        apache-error)  logfile="/var/log/apache2/custom-stack-error.log" ;;
        apache-access) logfile="/var/log/apache2/custom-stack-access.log" ;;
        nginx-error)   logfile="/var/log/nginx/custom-stack-error.log" ;;
        nginx-access)  logfile="/var/log/nginx/custom-stack-access.log" ;;
        php-fpm)       logfile="/var/log/php${php_ver}-fpm.log" ;;
        mysql)         logfile="/var/log/mysql/error.log" ;;
        postgresql)    logfile=$(find /var/log/postgresql/ -name "*.log" -type f 2>/dev/null | head -1) ;;
        mongodb)       logfile="/var/log/mongodb/mongod.log" ;;
    esac

    if [ -z "$logfile" ] || [ ! -f "$logfile" ]; then
        "$DIALOG_BIN" --title "Log" --msgbox "Log file not found:\n${logfile:-unknown}" 8 50 2>/dev/null
        return
    fi

    local tmplog="/tmp/stack_dialog_logview"
    tail -50 "$logfile" > "$tmplog" 2>/dev/null || echo "(empty or unreadable)" > "$tmplog"
    "$DIALOG_BIN" --title "$choice — last 50 lines" \
        --textbox "$tmplog" 24 80 2>/dev/null
    rm -f "$tmplog"
}

change_db_password() {
    if [ ! -f "$STACK_CREDS" ] || [ ! -s "$STACK_CREDS" ]; then
        "$DIALOG_BIN" --title "Change Password" \
            --msgbox "No databases with stored credentials found." 7 50 2>/dev/null
        return
    fi

    # Build menu from stored credentials
    local items=""
    local tag_count=0
    while IFS='|' read -r service user password; do
        [ -z "$service" ] && continue
        items="$items \"${service}\" \"User: ${user}\" off"
        tag_count=$((tag_count + 1))
    done < "$STACK_CREDS"

    if [ "$tag_count" -eq 0 ]; then
        "$DIALOG_BIN" --title "Change Password" \
            --msgbox "No databases with stored credentials found." 7 50 2>/dev/null
        return
    fi

    local height=$((tag_count + 8))
    local selected
    selected=$(eval run_dialog --title \"Change DB Password\" \
        --radiolist \"'Select database:'\" "$height" 55 "$tag_count" \
        "$items") || return 0

    [ -z "$selected" ] && return 0

    # Ask: auto-generate or enter manually
    local new_pass=""
    local method
    method=$(run_dialog --title "New Password for ${selected}" \
        --menu "How would you like to set the new password?" 12 55 2 \
        "auto"   "Auto-generate secure password" \
        "manual" "Enter password manually") || return 0

    if [ "$method" = "auto" ]; then
        new_pass=$(generate_password)
    else
        new_pass=$(run_dialog --title "New Password for ${selected}" \
            --inputbox "Enter new password:" 8 55 "") || return 0
        if [ -z "$new_pass" ]; then
            "$DIALOG_BIN" --title "Error" --msgbox "Password cannot be empty." 7 40 2>/dev/null
            return
        fi
    fi

    # Read current user for this service
    local db_user=""
    while IFS='|' read -r service user password; do
        if [ "$service" = "$selected" ]; then
            db_user="$user"
            break
        fi
    done < "$STACK_CREDS"

    # Execute the password change
    local success=false
    local error_msg=""
    case "$selected" in
        MySQL)
            if mysql -e "ALTER USER '${db_user}'@'localhost' IDENTIFIED BY '${new_pass}'; FLUSH PRIVILEGES;" 2>/tmp/stack_pw_err; then
                success=true
            else
                error_msg=$(cat /tmp/stack_pw_err)
            fi
            ;;
        MariaDB)
            if mariadb -e "ALTER USER '${db_user}'@'localhost' IDENTIFIED BY '${new_pass}'; FLUSH PRIVILEGES;" 2>/tmp/stack_pw_err; then
                success=true
            else
                error_msg=$(cat /tmp/stack_pw_err)
            fi
            ;;
        PostgreSQL)
            if su - postgres -c "psql -c \"ALTER USER ${db_user} PASSWORD '${new_pass}';\"" 2>/tmp/stack_pw_err; then
                success=true
            else
                error_msg=$(cat /tmp/stack_pw_err)
            fi
            ;;
        MongoDB)
            if mongosh --quiet --eval "use admin; db.changeUserPassword('${db_user}', '${new_pass}');" 2>/tmp/stack_pw_err; then
                success=true
            else
                error_msg=$(cat /tmp/stack_pw_err)
            fi
            ;;
        *)
            error_msg="Unknown database service: $selected"
            ;;
    esac
    rm -f /tmp/stack_pw_err

    if [ "$success" = true ]; then
        save_credential "$selected" "$db_user" "$new_pass"
        "$DIALOG_BIN" --title "Password Changed" \
            --msgbox "${selected} password updated successfully.\n\n  User:     ${db_user}\n  Password: ${new_pass}\n\nThis has been saved to the credentials store." 12 55 2>/dev/null
    else
        "$DIALOG_BIN" --title "Error" \
            --msgbox "Failed to change ${selected} password.\n\n${error_msg}" 12 60 2>/dev/null
    fi
}

control_panel() {
    local docroot="${DOCROOT:-$SEL_DOCROOT}"
    local port="${PORT:-$SEL_PORT}"

    while true; do
        local choice
        choice=$(run_dialog --title "Stack Control Panel" \
            --menu "Select an action:" 24 60 11 \
            "open-site"   "Open Site in Browser" \
            "phpinfo"     "PHP Info Page" \
            "files"       "File Explorer" \
            "phpmyadmin"  "phpMyAdmin" \
            "adminer"     "Adminer (DB Manager)" \
            "db-creds"    "Show DB Credentials" \
            "db-passwd"   "Change DB Password" \
            "status"      "Service Status" \
            "restart"     "Restart All Services" \
            "logs"        "View Logs" \
            "exit"        "Exit Panel") || break

        case "$choice" in
            open-site)
                open_in_browser "http://localhost:${port}"
                ;;
            phpinfo)
                create_phpinfo_page
                open_in_browser "http://localhost:${port}/info.php"
                ;;
            files)
                deploy_file_explorer
                open_in_browser "http://localhost:${port}/explorer.php"
                ;;
            phpmyadmin)
                if [ "${HAS_PHPMYADMIN:-off}" != "on" ]; then
                    "$DIALOG_BIN" --title "phpMyAdmin" \
                        --yesno "phpMyAdmin is not installed.\nInstall it now?" 8 45 2>/dev/null \
                        && install_phpmyadmin || continue
                fi
                open_in_browser "http://localhost:${port}/phpmyadmin"
                ;;
            adminer)
                if [ "${HAS_ADMINER:-off}" != "on" ] || [ ! -f "${docroot}/adminer.php" ]; then
                    install_adminer
                fi
                open_in_browser "http://localhost:${port}/adminer.php"
                ;;
            db-creds)
                show_db_credentials
                ;;
            db-passwd)
                change_db_password
                ;;
            status)
                show_service_status
                ;;
            restart)
                panel_restart_services
                ;;
            logs)
                show_logs_menu
                ;;
            exit)
                break
                ;;
        esac
    done

    clear
    log_info "Control panel closed."
}

# ── Section 5: Execution Flow ────────────────────────────────────────────────

main() {
    # Check for --panel flag
    if [ "${1:-}" = "--panel" ]; then
        load_stack_config
        control_panel
        exit 0
    fi

    # Interactive menus
    pick_webserver
    pick_sql_databases
    pick_mongodb
    pick_php_extensions
    pick_php_settings
    pick_docroot
    pick_port
    confirm_selections

    # Clear dialog screen
    clear

    echo ""
    echo -e "${BOLD}========================================${NC}"
    echo -e "${BOLD}  Starting Stack Installation${NC}"
    echo -e "${BOLD}========================================${NC}"
    echo ""

    # 1. Install PHP first (needed for web server config)
    PHP_VER=""
    install_php

    # 2. Install web server
    if [ "$SEL_WEBSERVER" = "apache2" ]; then
        install_apache
    elif [ "$SEL_WEBSERVER" = "nginx" ]; then
        install_nginx
    fi

    # 3. Install databases
    if [ "$SEL_MYSQL" = "on" ]; then
        install_mysql
    fi
    if [ "$SEL_MARIADB" = "on" ]; then
        install_mariadb
    fi
    if [ "$SEL_POSTGRESQL" = "on" ]; then
        install_postgresql
    fi
    if [ "$SEL_MONGODB" = "on" ]; then
        install_mongodb
    fi

    # 4. Configure PHP ini
    configure_php_ini

    # 5. Set up document root
    setup_document_root

    # 6. Configure firewall
    configure_firewall

    # 7. Restart all services
    restart_services

    # 8. Final summary
    local server_ip
    server_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    [ -z "$server_ip" ] && server_ip="<server-ip>"

    echo ""
    echo -e "${BOLD}========================================${NC}"
    echo -e "${GREEN}${BOLD}  Installation Complete!${NC}"
    echo -e "${BOLD}========================================${NC}"
    echo ""
    echo -e "  Web Server:    ${CYAN}${SEL_WEBSERVER}${NC}"
    echo -e "  PHP Version:   ${CYAN}${PHP_VER}${NC}"
    echo -e "  Document Root: ${CYAN}${SEL_DOCROOT}${NC}"
    echo -e "  Port:          ${CYAN}${SEL_PORT}${NC}"
    echo ""
    echo -e "  ${BOLD}Access your server:${NC}"
    if [ "$SEL_PORT" = "80" ]; then
        echo -e "  ${GREEN}http://${server_ip}/${NC}"
    else
        echo -e "  ${GREEN}http://${server_ip}:${SEL_PORT}/${NC}"
    fi
    echo ""
    echo -e "  A test ${CYAN}index.php${NC} (phpinfo) has been placed in the document root."
    echo -e "  ${YELLOW}Remember to remove it in production!${NC}"
    echo ""

    # Save config for later --panel access
    save_stack_config

    # Launch control panel
    echo -e "  ${BOLD}Launching Control Panel...${NC}"
    echo -e "  ${CYAN}(You can access it later with: sudo $0 --panel)${NC}"
    echo ""
    sleep 2
    control_panel
}

main "$@"
