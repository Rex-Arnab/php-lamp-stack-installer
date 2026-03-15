#!/bin/bash
# ==============================================================================
# Control panel functions — inline terminal prompts (no dialog dependency)
# ==============================================================================

# ── Section 4: Control Panel ─────────────────────────────────────────────────

STACK_CONFIG=""
STACK_CREDS=""

# Set config/creds paths based on OS (called after detect_os)
_init_stack_paths() {
    [ -n "$STACK_CONFIG" ] && return
    if [ "$DISTRO" = "macos" ]; then
        STACK_CONFIG="$HOME/.stack-panel.conf"
        STACK_CREDS="$HOME/.stack-panel.creds"
    else
        STACK_CONFIG="/etc/stack-panel.conf"
        STACK_CREDS="/etc/stack-panel.creds"
    fi
}

generate_password() {
    LC_ALL=C tr -dc 'A-Za-z0-9!@#$%&*' < /dev/urandom | head -c 20 || true
}

save_credential() {
    _init_stack_paths
    local service="$1" user="$2" password="$3"
    if [ ! -f "$STACK_CREDS" ]; then
        touch "$STACK_CREDS"
        chmod 600 "$STACK_CREDS"
    fi
    sed_i "/^${service}|/d" "$STACK_CREDS"
    echo "${service}|${user}|${password}" >> "$STACK_CREDS"
}

save_stack_config() {
    _init_stack_paths
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
DISTRO=${DISTRO}
EOF
    log_success "Stack config saved to $STACK_CONFIG"
}

load_stack_config() {
    _init_stack_paths
    if [ ! -f "$STACK_CONFIG" ]; then
        log_error "No stack config found at $STACK_CONFIG"
        log_error "Run the installer first, or re-run without --panel."
        exit 1
    fi
    # shellcheck disable=SC1090
    . "$STACK_CONFIG"
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
    case "$DISTRO" in
        macos)
            open "$url" 2>/dev/null &
            log_success "Opened $url in browser."
            return
            ;;
    esac

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
        [ "$DISTRO" != "macos" ] && set_web_owner "$target"
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
    [ "$DISTRO" != "macos" ] && set_web_owner "$target"
    log_success "File explorer deployed to $target"
}

install_phpmyadmin() {
    local docroot="${DOCROOT:-$SEL_DOCROOT}"
    local webserver="${WEBSERVER:-$SEL_WEBSERVER}"

    log_info "Installing phpMyAdmin..."

    case "$DISTRO" in
        debian)
            DEBIAN_FRONTEND=noninteractive pkg_install phpmyadmin
            if [ "$webserver" = "nginx" ]; then
                ln -sf /usr/share/phpmyadmin "${docroot}/phpmyadmin"
            fi
            ;;
        fedora)
            pkg_install phpMyAdmin
            if [ "$webserver" = "nginx" ]; then
                ln -sf /usr/share/phpMyAdmin "${docroot}/phpmyadmin"
            fi
            ;;
        macos)
            local pma_ver="5.2.3"
            local pma_url="https://files.phpmyadmin.net/phpMyAdmin/${pma_ver}/phpMyAdmin-${pma_ver}-all-languages.zip"
            local pma_tmp="/tmp/phpmyadmin.zip"

            log_info "Downloading phpMyAdmin ${pma_ver}..."
            curl -fsSL -o "$pma_tmp" "$pma_url" || { log_error "Download failed."; return 1; }

            log_info "Extracting to ${docroot}/phpmyadmin..."
            rm -rf "${docroot}/phpmyadmin" 2>/dev/null
            unzip -q "$pma_tmp" -d "$docroot"
            mv "${docroot}/phpMyAdmin-${pma_ver}-all-languages" "${docroot}/phpmyadmin"
            rm -f "$pma_tmp"

            # Create config with proper types for PHP 8.5 compatibility
            local blowfish_secret
            blowfish_secret=$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32 || true)
            cat > "${docroot}/phpmyadmin/config.inc.php" <<PMACONF
<?php
\$cfg['blowfish_secret'] = '${blowfish_secret}';
\$i = 0;
\$i++;
\$cfg['Servers'][\$i]['auth_type'] = 'cookie';
\$cfg['Servers'][\$i]['host'] = '127.0.0.1';
\$cfg['Servers'][\$i]['compress'] = false;
\$cfg['Servers'][\$i]['AllowNoPassword'] = false;
\$cfg['UploadDir'] = '';
\$cfg['SaveDir'] = '';
PMACONF
            ;;
    esac

    if [ -f "$STACK_CONFIG" ]; then
        sed_i 's/^HAS_PHPMYADMIN=.*/HAS_PHPMYADMIN=on/' "$STACK_CONFIG"
    fi
    HAS_PHPMYADMIN="on"
    log_success "phpMyAdmin installed."
}

install_adminer() {
    local docroot="${DOCROOT:-$SEL_DOCROOT}"
    local target="${docroot}/adminer.php"

    log_info "Downloading Adminer..."
    curl -fsSL -o "$target" "https://www.adminer.org/latest.php"
    [ "$DISTRO" != "macos" ] && set_web_owner "$target"

    if [ -f "$STACK_CONFIG" ]; then
        sed_i 's/^HAS_ADMINER=.*/HAS_ADMINER=on/' "$STACK_CONFIG"
    fi
    HAS_ADMINER="on"
    log_success "Adminer installed at $target"
}

# ── Service status & restart ────────────────────────────────────────────────

_get_service_list() {
    local webserver="${WEBSERVER:-$SEL_WEBSERVER}"
    local php_ver="${PHP_VER}"
    local services=""

    local ws_svc=""
    [ "$webserver" = "apache" ] && ws_svc="$APACHE_SVC"
    [ "$webserver" = "nginx" ] && ws_svc="nginx"

    local fpm_svc
    fpm_svc=$(get_fpm_service "$php_ver")

    services="$ws_svc $fpm_svc"

    if [ "${HAS_MYSQL:-${SEL_MYSQL:-off}}" = "on" ]; then
        local mysql_svc="mysql"
        [ "$DISTRO" = "fedora" ] && mysql_svc="mysqld"
        services="$services $mysql_svc"
    fi
    [ "${HAS_MARIADB:-${SEL_MARIADB:-off}}" = "on" ] && services="$services mariadb"
    if [ "${HAS_POSTGRESQL:-${SEL_POSTGRESQL:-off}}" = "on" ]; then
        local pg_svc="postgresql"
        [ "$DISTRO" = "macos" ] && pg_svc="postgresql@16"
        services="$services $pg_svc"
    fi
    if [ "${HAS_MONGODB:-${SEL_MONGODB:-off}}" = "on" ]; then
        local mongo_svc="mongod"
        [ "$DISTRO" = "macos" ] && mongo_svc="mongodb-community"
        services="$services $mongo_svc"
    fi

    echo "$services"
}

show_service_status() {
    local services
    services=$(_get_service_list)

    echo ""
    echo -e "${BOLD}── Service Status ──${NC}"
    for svc in $services; do
        [ -z "$svc" ] && continue
        local state
        state=$(svc_status "$svc")
        case "$state" in
            active)   echo -e "  ${GREEN}RUNNING${NC}  $svc" ;;
            inactive) echo -e "  ${YELLOW}STOPPED${NC}  $svc" ;;
            failed)   echo -e "  ${RED}FAILED${NC}   $svc" ;;
            *)        echo -e "  ${YELLOW}${state}${NC}     $svc" ;;
        esac
    done
    echo ""
}

panel_restart_services() {
    local services
    services=$(_get_service_list)

    echo ""
    echo -e "${BOLD}── Restarting Services ──${NC}"
    for svc in $services; do
        [ -z "$svc" ] && continue
        if svc_restart "$svc" 2>/dev/null; then
            log_success "$svc restarted."
        else
            log_error "$svc FAILED to restart."
        fi
    done
    echo ""
}

# ── Logs ────────────────────────────────────────────────────────────────────

show_logs_menu() {
    local webserver="${WEBSERVER:-$SEL_WEBSERVER}"
    local php_ver="${PHP_VER}"

    local log_names=""
    local log_count=0

    if [ "$webserver" = "apache" ]; then
        log_names="$log_names apache-error apache-access"
        log_count=$((log_count + 2))
    elif [ "$webserver" = "nginx" ]; then
        log_names="$log_names nginx-error nginx-access"
        log_count=$((log_count + 2))
    fi
    [ -n "$php_ver" ] && { log_names="$log_names php-fpm"; log_count=$((log_count + 1)); }
    [ "${HAS_MYSQL:-${SEL_MYSQL:-off}}" = "on" ] && { log_names="$log_names mysql"; log_count=$((log_count + 1)); }
    [ "${HAS_POSTGRESQL:-${SEL_POSTGRESQL:-off}}" = "on" ] && { log_names="$log_names postgresql"; log_count=$((log_count + 1)); }
    [ "${HAS_MONGODB:-${SEL_MONGODB:-off}}" = "on" ] && { log_names="$log_names mongodb"; log_count=$((log_count + 1)); }

    if [ "$log_count" -eq 0 ]; then
        log_warn "No log sources found."
        return
    fi

    echo ""
    echo -e "${BOLD}── View Logs ──${NC}"
    local i=0
    for name in $log_names; do
        i=$((i + 1))
        echo "  $i) $name"
    done
    echo "  0) Back"
    echo ""

    local choice
    read -p "  Choose: " choice
    [ -z "$choice" ] || [ "$choice" = "0" ] && return

    # Get the Nth item
    local selected=""
    i=0
    for name in $log_names; do
        i=$((i + 1))
        [ "$i" = "$choice" ] && { selected="$name"; break; }
    done
    [ -z "$selected" ] && { log_warn "Invalid choice."; return; }

    local logfile=""
    case "$selected" in
        apache-error)  logfile="${APACHE_LOG_DIR}/custom-stack-error.log" ;;
        apache-access) logfile="${APACHE_LOG_DIR}/custom-stack-access.log" ;;
        nginx-error)   logfile="${NGINX_LOG_DIR}/custom-stack-error.log" ;;
        nginx-access)  logfile="${NGINX_LOG_DIR}/custom-stack-access.log" ;;
        php-fpm)
            case "$DISTRO" in
                debian) logfile="/var/log/php${php_ver}-fpm.log" ;;
                fedora) logfile="/var/log/php-fpm/error.log" ;;
                macos)  logfile="/opt/homebrew/var/log/php-fpm.log" ;;
            esac
            ;;
        mysql)     logfile="$MYSQL_LOG" ;;
        postgresql)
            logfile=$(find "$PG_LOG_DIR" -name "*.log" -type f 2>/dev/null | head -1)
            ;;
        mongodb)   logfile="$MONGO_LOG" ;;
    esac

    if [ -z "$logfile" ] || [ ! -f "$logfile" ]; then
        log_warn "Log file not found: ${logfile:-unknown}"
        return
    fi

    echo ""
    echo -e "${BOLD}── ${selected} — last 50 lines ──${NC}"
    echo ""
    tail -50 "$logfile" 2>/dev/null || echo "(empty or unreadable)"
    echo ""
}

# ── DB Credentials ──────────────────────────────────────────────────────────

show_db_credentials() {
    _init_stack_paths
    if [ ! -f "$STACK_CREDS" ] || [ ! -s "$STACK_CREDS" ]; then
        echo ""
        log_warn "No credentials stored."
        echo "  This can happen if databases were installed before this feature"
        echo "  or no databases were installed."
        echo ""
        echo "  Check manually:"
        echo "    MySQL/MariaDB: sudo mysql"
        echo "    PostgreSQL:    sudo -u postgres psql"
        echo ""
        return
    fi

    echo ""
    echo -e "${BOLD}── DB Credentials ──${NC}"
    echo ""

    while IFS='|' read -r service user password; do
        [ -z "$service" ] && continue

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

        echo -e "  Service:  ${CYAN}${service}${NC}"
        echo "  User:     ${user}"
        echo "  Password: ${password}"
        if [ "$status" = "VALID" ]; then
            echo -e "  Status:   ${GREEN}[VALID]${NC}"
        else
            echo -e "  Status:   ${YELLOW}[CHANGED externally]${NC}"
        fi
        echo ""
    done < "$STACK_CREDS"

    echo "  If status shows CHANGED, the password was modified"
    echo "  outside this tool (via phpMyAdmin, CLI, etc)."
    echo -e "  File: ${CYAN}${STACK_CREDS}${NC} (chmod 600)"
    echo ""
}

# ── Change DB Password ──────────────────────────────────────────────────────

change_db_password() {
    _init_stack_paths
    if [ ! -f "$STACK_CREDS" ] || [ ! -s "$STACK_CREDS" ]; then
        log_warn "No databases with stored credentials found."
        return
    fi

    echo ""
    echo -e "${BOLD}── Change DB Password ──${NC}"
    echo "  Select database:"

    local i=0
    local svc_list=""
    while IFS='|' read -r service user password; do
        [ -z "$service" ] && continue
        i=$((i + 1))
        echo "  $i) ${service} (user: ${user})"
        svc_list="${svc_list}${service}|${user}|${password}\n"
    done < "$STACK_CREDS"
    echo "  0) Back"
    echo ""

    if [ "$i" -eq 0 ]; then
        log_warn "No databases with stored credentials found."
        return
    fi

    local choice
    read -p "  Choose: " choice
    [ -z "$choice" ] || [ "$choice" = "0" ] && return

    local selected="" db_user="" old_pass=""
    local j=0
    while IFS='|' read -r service user password; do
        [ -z "$service" ] && continue
        j=$((j + 1))
        if [ "$j" = "$choice" ]; then
            selected="$service"
            db_user="$user"
            old_pass="$password"
            break
        fi
    done < "$STACK_CREDS"

    [ -z "$selected" ] && { log_warn "Invalid choice."; return; }

    echo ""
    echo "  1) Auto-generate secure password"
    echo "  2) Enter password manually"
    local method
    read -p "  Choose [1]: " method

    local new_pass=""
    if [ "$method" = "2" ]; then
        read -p "  Enter new password: " new_pass
        if [ -z "$new_pass" ]; then
            log_error "Password cannot be empty."
            return
        fi
    else
        new_pass=$(generate_password)
    fi

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
            if [ "$DISTRO" = "macos" ]; then
                if psql -U "$db_user" -d postgres -c "ALTER USER ${db_user} PASSWORD '${new_pass}';" 2>/tmp/stack_pw_err; then
                    success=true
                else
                    error_msg=$(cat /tmp/stack_pw_err)
                fi
            else
                if su - postgres -c "psql -c \"ALTER USER ${db_user} PASSWORD '${new_pass}';\"" 2>/tmp/stack_pw_err; then
                    success=true
                else
                    error_msg=$(cat /tmp/stack_pw_err)
                fi
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
        echo ""
        log_success "${selected} password updated."
        echo "  User:     ${db_user}"
        echo "  Password: ${new_pass}"
        echo ""
    else
        log_error "Failed to change ${selected} password."
        [ -n "$error_msg" ] && echo "  $error_msg"
        echo ""
    fi
}

# ── Create DB User ──────────────────────────────────────────────────────────

create_db_user() {
    local items=""
    local i=0

    echo ""
    echo -e "${BOLD}── Create DB User ──${NC}"
    echo "  Select database:"

    if [ "${HAS_MYSQL:-${SEL_MYSQL:-off}}" = "on" ]; then
        i=$((i + 1)); echo "  $i) MySQL"
        items="${items}MySQL\n"
    fi
    if [ "${HAS_MARIADB:-${SEL_MARIADB:-off}}" = "on" ]; then
        i=$((i + 1)); echo "  $i) MariaDB"
        items="${items}MariaDB\n"
    fi
    if [ "${HAS_POSTGRESQL:-${SEL_POSTGRESQL:-off}}" = "on" ]; then
        i=$((i + 1)); echo "  $i) PostgreSQL"
        items="${items}PostgreSQL\n"
    fi
    if [ "${HAS_MONGODB:-${SEL_MONGODB:-off}}" = "on" ]; then
        i=$((i + 1)); echo "  $i) MongoDB"
        items="${items}MongoDB\n"
    fi
    echo "  0) Back"
    echo ""

    if [ "$i" -eq 0 ]; then
        log_warn "No databases installed."
        return
    fi

    local choice
    read -p "  Choose: " choice
    [ -z "$choice" ] || [ "$choice" = "0" ] && return

    local selected=""
    local j=0
    while IFS= read -r db; do
        [ -z "$db" ] && continue
        j=$((j + 1))
        [ "$j" = "$choice" ] && { selected="$db"; break; }
    done < <(printf "$items")

    [ -z "$selected" ] && { log_warn "Invalid choice."; return; }

    local new_user
    read -p "  Enter username: " new_user
    if [ -z "$new_user" ]; then
        log_error "Username cannot be empty."
        return
    fi

    echo ""
    echo "  1) Auto-generate secure password"
    echo "  2) Enter password manually"
    local method
    read -p "  Choose [1]: " method

    local new_pass=""
    if [ "$method" = "2" ]; then
        read -p "  Enter password: " new_pass
        if [ -z "$new_pass" ]; then
            log_error "Password cannot be empty."
            return
        fi
    else
        new_pass=$(generate_password)
    fi

    local grant_db=""
    if [ "$selected" != "MongoDB" ]; then
        echo ""
        echo "  Grant privileges:"
        echo "  1) All databases (full privileges)"
        echo "  2) A specific database"
        echo "  3) No grants (create user only)"
        local grant_choice
        read -p "  Choose [3]: " grant_choice

        case "$grant_choice" in
            1) grant_db="*" ;;
            2)
                read -p "  Enter database name: " grant_db
                if [ -z "$grant_db" ]; then
                    log_error "Database name cannot be empty."
                    return
                fi
                ;;
        esac
    fi

    local mongo_db="admin"
    local mongo_role="readWrite"
    if [ "$selected" = "MongoDB" ]; then
        read -p "  Auth/target database [admin]: " mongo_db
        [ -z "$mongo_db" ] && mongo_db="admin"

        echo ""
        echo "  Select role:"
        echo "  1) readWrite  — Read and write"
        echo "  2) read       — Read-only"
        echo "  3) dbAdmin    — Database admin"
        echo "  4) userAdmin  — User admin"
        echo "  5) root       — Superuser"
        local role_choice
        read -p "  Choose [1]: " role_choice
        case "$role_choice" in
            2) mongo_role="read" ;;
            3) mongo_role="dbAdmin" ;;
            4) mongo_role="userAdmin" ;;
            5) mongo_role="root" ;;
            *) mongo_role="readWrite" ;;
        esac
    fi

    local success=false
    local error_msg=""
    case "$selected" in
        MySQL)
            local sql="CREATE USER '${new_user}'@'localhost' IDENTIFIED BY '${new_pass}';"
            if [ "$grant_db" = "*" ]; then
                sql="$sql GRANT ALL PRIVILEGES ON *.* TO '${new_user}'@'localhost' WITH GRANT OPTION;"
            elif [ -n "$grant_db" ]; then
                sql="$sql GRANT ALL PRIVILEGES ON \`${grant_db}\`.* TO '${new_user}'@'localhost';"
            fi
            sql="$sql FLUSH PRIVILEGES;"
            if mysql -e "$sql" 2>/tmp/stack_pw_err; then
                success=true
            else
                error_msg=$(cat /tmp/stack_pw_err)
            fi
            ;;
        MariaDB)
            local sql="CREATE USER '${new_user}'@'localhost' IDENTIFIED BY '${new_pass}';"
            if [ "$grant_db" = "*" ]; then
                sql="$sql GRANT ALL PRIVILEGES ON *.* TO '${new_user}'@'localhost' WITH GRANT OPTION;"
            elif [ -n "$grant_db" ]; then
                sql="$sql GRANT ALL PRIVILEGES ON \`${grant_db}\`.* TO '${new_user}'@'localhost';"
            fi
            sql="$sql FLUSH PRIVILEGES;"
            if mariadb -e "$sql" 2>/tmp/stack_pw_err; then
                success=true
            else
                error_msg=$(cat /tmp/stack_pw_err)
            fi
            ;;
        PostgreSQL)
            local sql="CREATE USER ${new_user} WITH PASSWORD '${new_pass}';"
            if [ "$grant_db" = "*" ]; then
                sql="$sql ALTER USER ${new_user} WITH SUPERUSER;"
            elif [ -n "$grant_db" ]; then
                sql="$sql GRANT ALL PRIVILEGES ON DATABASE ${grant_db} TO ${new_user};"
            fi
            if [ "$DISTRO" = "macos" ]; then
                if psql -U "$(whoami)" -d postgres -c "$sql" 2>/tmp/stack_pw_err; then
                    success=true
                else
                    error_msg=$(cat /tmp/stack_pw_err)
                fi
            else
                if su - postgres -c "psql -c \"$sql\"" 2>/tmp/stack_pw_err; then
                    success=true
                else
                    error_msg=$(cat /tmp/stack_pw_err)
                fi
            fi
            ;;
        MongoDB)
            if mongosh --quiet --eval "
                use ${mongo_db};
                db.createUser({
                    user: '${new_user}',
                    pwd: '${new_pass}',
                    roles: [{role: '${mongo_role}', db: '${mongo_db}'}]
                });
            " 2>/tmp/stack_pw_err; then
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
        save_credential "${selected}:${new_user}" "$new_user" "$new_pass"

        echo ""
        log_success "${selected} user created."
        echo "  User:     ${new_user}"
        echo "  Password: ${new_pass}"
        case "$selected" in
            MongoDB)
                echo "  Database: ${mongo_db}"
                echo "  Role:     ${mongo_role}" ;;
            *)
                if [ "$grant_db" = "*" ]; then
                    echo "  Grants:   ALL PRIVILEGES (superuser)"
                elif [ -n "$grant_db" ]; then
                    echo "  Grants:   ALL on ${grant_db}"
                else
                    echo "  Grants:   None (login only)"
                fi
                ;;
        esac
        echo ""
    else
        log_error "Failed to create ${selected} user."
        [ -n "$error_msg" ] && echo "  $error_msg"
        echo ""
    fi
}

# ── Remove Services ─────────────────────────────────────────────────────────

remove_services() {
    _init_stack_paths
    local webserver="${WEBSERVER:-$SEL_WEBSERVER}"
    local php_ver="${PHP_VER}"

    echo ""
    echo -e "${BOLD}── Remove Services ──${NC}"
    echo "  Select services to remove (y/N for each):"
    echo ""

    local to_remove=""

    if [ -n "$webserver" ] && [ "$webserver" = "apache" ]; then
        local yn; read -p "  Remove Apache?     (y/N): " yn
        [[ "$yn" =~ ^[Yy]$ ]] && to_remove="$to_remove apache"
    fi
    if [ -n "$webserver" ] && [ "$webserver" = "nginx" ]; then
        local yn; read -p "  Remove Nginx?      (y/N): " yn
        [[ "$yn" =~ ^[Yy]$ ]] && to_remove="$to_remove nginx"
    fi
    if [ -n "$php_ver" ]; then
        local yn; read -p "  Remove PHP ${php_ver}?    (y/N): " yn
        [[ "$yn" =~ ^[Yy]$ ]] && to_remove="$to_remove php"
    fi
    if [ "${HAS_MYSQL:-${SEL_MYSQL:-off}}" = "on" ]; then
        local yn; read -p "  Remove MySQL?      (y/N): " yn
        [[ "$yn" =~ ^[Yy]$ ]] && to_remove="$to_remove mysql"
    fi
    if [ "${HAS_MARIADB:-${SEL_MARIADB:-off}}" = "on" ]; then
        local yn; read -p "  Remove MariaDB?    (y/N): " yn
        [[ "$yn" =~ ^[Yy]$ ]] && to_remove="$to_remove mariadb"
    fi
    if [ "${HAS_POSTGRESQL:-${SEL_POSTGRESQL:-off}}" = "on" ]; then
        local yn; read -p "  Remove PostgreSQL? (y/N): " yn
        [[ "$yn" =~ ^[Yy]$ ]] && to_remove="$to_remove postgresql"
    fi
    if [ "${HAS_MONGODB:-${SEL_MONGODB:-off}}" = "on" ]; then
        local yn; read -p "  Remove MongoDB?    (y/N): " yn
        [[ "$yn" =~ ^[Yy]$ ]] && to_remove="$to_remove mongodb"
    fi
    if [ "${HAS_PHPMYADMIN:-off}" = "on" ]; then
        local yn; read -p "  Remove phpMyAdmin? (y/N): " yn
        [[ "$yn" =~ ^[Yy]$ ]] && to_remove="$to_remove phpmyadmin"
    fi
    if [ "${HAS_ADMINER:-off}" = "on" ]; then
        local yn; read -p "  Remove Adminer?    (y/N): " yn
        [[ "$yn" =~ ^[Yy]$ ]] && to_remove="$to_remove adminer"
    fi

    if [ -z "$to_remove" ]; then
        log_info "Nothing selected."
        return
    fi

    echo ""
    echo -e "  Will remove:${CYAN}${to_remove}${NC}"
    local confirm
    read -p "  Are you sure? (y/N): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && { log_info "Cancelled."; return; }

    local purge_data=false
    if [ "$DISTRO" != "macos" ]; then
        local pd
        read -p "  Also purge data files? (y/N): " pd
        [[ "$pd" =~ ^[Yy]$ ]] && purge_data=true
    fi

    [ "$purge_data" = true ] && export PURGE_MODE="purge"

    echo ""
    local result_text=""
    for svc in $to_remove; do
        case "$svc" in
            apache)
                svc_stop "$APACHE_SVC"
                pkg_remove "$APACHE_PKG" 2>/dev/null
                [ "$DISTRO" = "debian" ] && pkg_remove libapache2-mod-fcgid 2>/dev/null
                [ "$DISTRO" = "fedora" ] && pkg_remove mod_fcgid 2>/dev/null
                result_text="${result_text}  Apache: removed\n"
                [ -f "$STACK_CONFIG" ] && sed_i 's/^WEBSERVER=.*/WEBSERVER=/' "$STACK_CONFIG"
                ;;
            nginx)
                svc_stop nginx
                pkg_remove nginx 2>/dev/null
                result_text="${result_text}  Nginx: removed\n"
                [ -f "$STACK_CONFIG" ] && sed_i 's/^WEBSERVER=.*/WEBSERVER=/' "$STACK_CONFIG"
                ;;
            php)
                local fpm_svc
                fpm_svc=$(get_fpm_service "$php_ver")
                svc_stop "$fpm_svc"
                case "$DISTRO" in
                    debian) pkg_remove "php${php_ver}*" 2>/dev/null ;;
                    fedora) pkg_remove php php-fpm "php-*" 2>/dev/null ;;
                    macos)  pkg_remove php 2>/dev/null ;;
                esac
                result_text="${result_text}  PHP ${php_ver}: removed\n"
                [ -f "$STACK_CONFIG" ] && sed_i 's/^PHP_VER=.*/PHP_VER=/' "$STACK_CONFIG"
                ;;
            mysql)
                local mysql_svc="mysql"
                [ "$DISTRO" = "fedora" ] && mysql_svc="mysqld"
                svc_stop "$mysql_svc"
                case "$DISTRO" in
                    debian) pkg_remove mysql-server mysql-client mysql-common 2>/dev/null ;;
                    fedora) pkg_remove mysql-server 2>/dev/null ;;
                    macos)  pkg_remove mysql 2>/dev/null ;;
                esac
                result_text="${result_text}  MySQL: removed\n"
                [ -f "$STACK_CONFIG" ] && sed_i 's/^HAS_MYSQL=.*/HAS_MYSQL=off/' "$STACK_CONFIG"
                [ -f "$STACK_CREDS" ] && sed_i '/^MySQL/d' "$STACK_CREDS"
                ;;
            mariadb)
                svc_stop mariadb
                case "$DISTRO" in
                    debian) pkg_remove mariadb-server mariadb-client mariadb-common 2>/dev/null ;;
                    fedora) pkg_remove mariadb-server 2>/dev/null ;;
                    macos)  pkg_remove mariadb 2>/dev/null ;;
                esac
                result_text="${result_text}  MariaDB: removed\n"
                [ -f "$STACK_CONFIG" ] && sed_i 's/^HAS_MARIADB=.*/HAS_MARIADB=off/' "$STACK_CONFIG"
                [ -f "$STACK_CREDS" ] && sed_i '/^MariaDB/d' "$STACK_CREDS"
                ;;
            postgresql)
                local pg_svc="postgresql"
                [ "$DISTRO" = "macos" ] && pg_svc="postgresql@16"
                svc_stop "$pg_svc"
                case "$DISTRO" in
                    debian) pkg_remove postgresql postgresql-contrib 2>/dev/null ;;
                    fedora) pkg_remove postgresql-server postgresql-contrib 2>/dev/null ;;
                    macos)  pkg_remove postgresql@16 2>/dev/null ;;
                esac
                result_text="${result_text}  PostgreSQL: removed\n"
                [ -f "$STACK_CONFIG" ] && sed_i 's/^HAS_POSTGRESQL=.*/HAS_POSTGRESQL=off/' "$STACK_CONFIG"
                [ -f "$STACK_CREDS" ] && sed_i '/^PostgreSQL/d' "$STACK_CREDS"
                ;;
            mongodb)
                local mongo_svc="mongod"
                [ "$DISTRO" = "macos" ] && mongo_svc="mongodb-community"
                svc_stop "$mongo_svc"
                case "$DISTRO" in
                    debian) pkg_remove mongodb-org 2>/dev/null ;;
                    fedora) pkg_remove mongodb-org 2>/dev/null ;;
                    macos)  pkg_remove mongodb-community 2>/dev/null ;;
                esac
                result_text="${result_text}  MongoDB: removed\n"
                [ -f "$STACK_CONFIG" ] && sed_i 's/^HAS_MONGODB=.*/HAS_MONGODB=off/' "$STACK_CONFIG"
                [ -f "$STACK_CREDS" ] && sed_i '/^MongoDB/d' "$STACK_CREDS"
                ;;
            phpmyadmin)
                case "$DISTRO" in
                    debian) pkg_remove phpmyadmin 2>/dev/null ;;
                    fedora) pkg_remove phpMyAdmin 2>/dev/null ;;
                esac
                local docroot="${DOCROOT:-$SEL_DOCROOT}"
                rm -f "${docroot}/phpmyadmin" 2>/dev/null
                result_text="${result_text}  phpMyAdmin: removed\n"
                [ -f "$STACK_CONFIG" ] && sed_i 's/^HAS_PHPMYADMIN=.*/HAS_PHPMYADMIN=off/' "$STACK_CONFIG"
                ;;
            adminer)
                local docroot="${DOCROOT:-$SEL_DOCROOT}"
                rm -f "${docroot}/adminer.php" 2>/dev/null
                result_text="${result_text}  Adminer: removed\n"
                [ -f "$STACK_CONFIG" ] && sed_i 's/^HAS_ADMINER=.*/HAS_ADMINER=off/' "$STACK_CONFIG"
                ;;
        esac
    done

    unset PURGE_MODE
    pkg_autoremove

    [ -f "$STACK_CONFIG" ] && load_stack_config 2>/dev/null || true

    echo ""
    echo -e "${BOLD}── Removal Complete ──${NC}"
    echo -e "$result_text"
}

# ── Control Panel Main Menu ─────────────────────────────────────────────────

control_panel() {
    local docroot="${DOCROOT:-$SEL_DOCROOT}"
    local port="${PORT:-$SEL_PORT}"

    while true; do
        echo ""
        echo -e "${BOLD}========================================${NC}"
        echo -e "${BOLD}  Stack Control Panel (${DISTRO})${NC}"
        echo -e "${BOLD}========================================${NC}"
        echo ""
        echo "   1) Open Site in Browser"
        echo "   2) PHP Info Page"
        echo "   3) File Explorer"
        echo "   4) phpMyAdmin"
        echo "   5) Adminer (DB Manager)"
        echo "   6) Show DB Credentials"
        echo "   7) Change DB Password"
        echo "   8) Create DB User"
        echo "   9) Service Status"
        echo "  10) Restart All Services"
        echo "  11) Remove Services"
        echo "  12) View Logs"
        echo "   0) Exit"
        echo ""

        local choice
        read -p "  Choose: " choice

        case "$choice" in
            1)
                open_in_browser "http://localhost:${port}"
                ;;
            2)
                create_phpinfo_page
                open_in_browser "http://localhost:${port}/info.php"
                ;;
            3)
                deploy_file_explorer
                open_in_browser "http://localhost:${port}/explorer.php"
                ;;
            4)
                if [ "${HAS_PHPMYADMIN:-off}" != "on" ]; then
                    local yn
                    read -p "  phpMyAdmin not installed. Install now? (y/N): " yn
                    [[ "$yn" =~ ^[Yy]$ ]] && install_phpmyadmin || continue
                fi
                open_in_browser "http://localhost:${port}/phpmyadmin"
                ;;
            5)
                if [ "${HAS_ADMINER:-off}" != "on" ] || [ ! -f "${docroot}/adminer.php" ]; then
                    install_adminer
                fi
                open_in_browser "http://localhost:${port}/adminer.php"
                ;;
            6)  show_db_credentials ;;
            7)  change_db_password ;;
            8)  create_db_user ;;
            9)  show_service_status ;;
            10) panel_restart_services ;;
            11) remove_services ;;
            12) show_logs_menu ;;
            0)  break ;;
            *)  log_warn "Invalid choice." ;;
        esac
    done

    log_info "Control panel closed."
}
