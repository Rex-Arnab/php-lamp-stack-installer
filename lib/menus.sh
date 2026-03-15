#!/bin/bash
# ==============================================================================
# Interactive inline menus for stack selection
# Simple terminal prompts — no full-screen dialog needed
# ==============================================================================

pick_webserver() {
    echo ""
    echo -e "${BOLD}── Web Server ──${NC}"
    echo "  1) Apache"
    echo "  2) Nginx"
    echo ""
    local choice
    read -p "  Choose [1]: " choice
    case "$choice" in
        2) SEL_WEBSERVER="nginx" ;;
        *) SEL_WEBSERVER="apache" ;;
    esac
    log_success "Web server: ${SEL_WEBSERVER}"
}

pick_sql_databases() {
    echo ""
    echo -e "${BOLD}── SQL Databases ──${NC}"
    echo "  Select which databases to install (y/N for each):"
    echo ""

    local yn
    read -p "  MySQL?      (y/N): " yn
    [[ "$yn" =~ ^[Yy]$ ]] && SEL_MYSQL="on"

    read -p "  MariaDB?    (y/N): " yn
    [[ "$yn" =~ ^[Yy]$ ]] && SEL_MARIADB="on"

    read -p "  PostgreSQL? (y/N): " yn
    [[ "$yn" =~ ^[Yy]$ ]] && SEL_POSTGRESQL="on"

    local db_list=""
    [ "$SEL_MYSQL" = "on" ] && db_list="${db_list}MySQL "
    [ "$SEL_MARIADB" = "on" ] && db_list="${db_list}MariaDB "
    [ "$SEL_POSTGRESQL" = "on" ] && db_list="${db_list}PostgreSQL "
    [ -z "$db_list" ] && db_list="None"
    log_success "SQL databases: ${db_list}"
}

pick_mongodb() {
    echo ""
    echo -e "${BOLD}── NoSQL Database ──${NC}"
    local yn
    read -p "  Install MongoDB? (y/N): " yn
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        SEL_MONGODB="on"
        log_success "MongoDB: yes"
    else
        log_success "MongoDB: no"
    fi
}

pick_php_extensions() {
    echo ""
    echo -e "${BOLD}── PHP Extensions ──${NC}"

    local ext_names=""

    if [ "$DISTRO" = "macos" ]; then
        # macOS: Homebrew PHP includes most core extensions (curl, gd, mbstring, xml, etc.)
        # These are PECL extensions that need separate install
        ext_names="pecl-redis pecl-imagick pecl-xdebug pecl-memcached pecl-igbinary pecl-yaml pecl-apcu"
        [ "$SEL_MONGODB" = "on" ] && ext_names="$ext_names pecl-mongodb"
    else
        # Linux: core extensions (installed via apt/dnf with php version prefix)
        ext_names="php-cli php-fpm php-common php-curl php-gd php-mbstring php-xml php-zip php-intl php-bcmath php-soap php-redis php-imagick php-sqlite3 php-tokenizer php-fileinfo php-opcache php-readline php-bz2 php-gmp php-ldap php-imap php-memcached php-apcu php-xdebug php-yaml php-igbinary php-uuid php-raphf"
        [ "$SEL_MYSQL" = "on" ] || [ "$SEL_MARIADB" = "on" ] && ext_names="$ext_names php-mysql"
        [ "$SEL_POSTGRESQL" = "on" ] && ext_names="$ext_names php-pgsql"
        [ "$SEL_MONGODB" = "on" ] && ext_names="$ext_names php-mongodb"
    fi

    echo "  Default extensions:"
    local i=0
    for ext in $ext_names; do
        i=$((i + 1))
        echo "    ${ext}"
    done
    echo ""
    echo "  Total: ${i} extensions"
    echo ""

    local customize
    read -p "  Install all defaults? (Y/n): " customize
    if [[ "$customize" =~ ^[Nn]$ ]]; then
        echo ""
        echo "  Select extensions (y/N for each):"
        local selected=""
        for ext in $ext_names; do
            local yn
            read -p "    ${ext}? (y/N): " yn
            [[ "$yn" =~ ^[Yy]$ ]] && selected="${selected} ${ext}"
        done
        SEL_PHP_EXTS="$selected"
    else
        SEL_PHP_EXTS="$ext_names"
    fi

    local count
    count=$(echo "$SEL_PHP_EXTS" | wc -w | tr -d ' ')
    log_success "PHP extensions: ${count} selected"
}

pick_php_settings() {
    echo ""
    echo -e "${BOLD}── PHP Settings ──${NC}"
    echo "  Press ENTER to keep defaults shown in [brackets]."
    echo ""

    local val
    read -p "  upload_max_filesize [${SEL_UPLOAD_MAX}]: " val
    [ -n "$val" ] && SEL_UPLOAD_MAX="$val"

    read -p "  post_max_size       [${SEL_POST_MAX}]: " val
    [ -n "$val" ] && SEL_POST_MAX="$val"

    read -p "  memory_limit        [${SEL_MEMORY_LIMIT}]: " val
    [ -n "$val" ] && SEL_MEMORY_LIMIT="$val"

    read -p "  max_execution_time  [${SEL_MAX_EXEC_TIME}]: " val
    [ -n "$val" ] && SEL_MAX_EXEC_TIME="$val"

    read -p "  max_input_vars      [${SEL_MAX_INPUT_VARS}]: " val
    [ -n "$val" ] && SEL_MAX_INPUT_VARS="$val"

    log_success "PHP settings configured"
}

pick_docroot() {
    echo ""
    echo -e "${BOLD}── Document Root ──${NC}"
    local val
    read -p "  Path [${SEL_DOCROOT}]: " val
    [ -n "$val" ] && SEL_DOCROOT="$val"
    log_success "Document root: ${SEL_DOCROOT}"
}

pick_port() {
    echo ""
    echo -e "${BOLD}── Server Port ──${NC}"
    local val
    read -p "  Port [${SEL_PORT}]: " val
    [ -n "$val" ] && SEL_PORT="$val"
    log_success "Port: ${SEL_PORT}"
}

confirm_selections() {
    local db_list=""
    [ "$SEL_MYSQL" = "on" ] && db_list="${db_list}MySQL "
    [ "$SEL_MARIADB" = "on" ] && db_list="${db_list}MariaDB "
    [ "$SEL_POSTGRESQL" = "on" ] && db_list="${db_list}PostgreSQL "
    [ "$SEL_MONGODB" = "on" ] && db_list="${db_list}MongoDB "
    [ -z "$db_list" ] && db_list="None"

    local ext_count
    ext_count=$(echo "$SEL_PHP_EXTS" | wc -w | tr -d ' ')

    echo ""
    echo -e "${BOLD}========================================${NC}"
    echo -e "${BOLD}  Review Your Selections${NC}"
    echo -e "${BOLD}========================================${NC}"
    echo ""
    echo -e "  Platform:           ${CYAN}${DISTRO}${NC}"
    echo -e "  Web Server:         ${CYAN}${SEL_WEBSERVER}${NC}"
    echo -e "  Databases:          ${CYAN}${db_list}${NC}"
    echo -e "  PHP Extensions:     ${CYAN}${ext_count} selected${NC}"
    echo ""
    echo -e "  ${BOLD}PHP Settings:${NC}"
    echo "    upload_max_filesize = $SEL_UPLOAD_MAX"
    echo "    post_max_size       = $SEL_POST_MAX"
    echo "    memory_limit        = $SEL_MEMORY_LIMIT"
    echo "    max_execution_time  = $SEL_MAX_EXEC_TIME"
    echo "    max_input_vars      = $SEL_MAX_INPUT_VARS"
    echo ""
    echo -e "  Document Root:      ${CYAN}$SEL_DOCROOT${NC}"
    echo -e "  Port:               ${CYAN}$SEL_PORT${NC}"
    echo ""

    local yn
    read -p "  Proceed with installation? (Y/n): " yn
    if [[ "$yn" =~ ^[Nn]$ ]]; then
        log_error "Installation cancelled."
        exit 1
    fi
}
