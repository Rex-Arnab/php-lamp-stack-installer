#\!/bin/bash
# ==============================================================================
# Control panel functions
# ==============================================================================

# ── Section 4: Control Panel ─────────────────────────────────────────────────

STACK_CONFIG="/etc/stack-panel.conf"
STACK_CREDS="/etc/stack-panel.creds"

# macOS: use user-level config since /etc requires root
if [ "$DISTRO" = "macos" ]; then
    STACK_CONFIG="$HOME/.stack-panel.conf"
    STACK_CREDS="$HOME/.stack-panel.creds"
fi

generate_password() {
    tr -dc 'A-Za-z0-9!@#$%&*' < /dev/urandom | head -c 20 || true
}

save_credential() {
    local service="$1" user="$2" password="$3"
    if [ ! -f "$STACK_CREDS" ]; then
        touch "$STACK_CREDS"
        chmod 600 "$STACK_CREDS"
    fi
    sed_i "/^${service}|/d" "$STACK_CREDS"
    echo "${service}|${user}|${password}" >> "$STACK_CREDS"
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
DISTRO=${DISTRO}
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
            log_warn "phpMyAdmin: download manually from https://www.phpmyadmin.net/"
            log_warn "Extract to ${docroot}/phpmyadmin"
            return
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

show_service_status() {
    local webserver="${WEBSERVER:-$SEL_WEBSERVER}"
    local php_ver="${PHP_VER}"
    local status_text=""

    # Web server
    local ws_svc=""
    if [ "$webserver" = "apache" ]; then
        ws_svc="$APACHE_SVC"
    elif [ "$webserver" = "nginx" ]; then
        ws_svc="nginx"
    fi

    local fpm_svc
    fpm_svc=$(get_fpm_service "$php_ver")

    local services="$ws_svc $fpm_svc"

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

    for svc in $services; do
        [ -z "$svc" ] && continue
        local state
        state=$(svc_status "$svc")
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

    local ws_svc=""
    [ "$webserver" = "apache" ] && ws_svc="$APACHE_SVC"
    [ "$webserver" = "nginx" ] && ws_svc="nginx"

    local fpm_svc
    fpm_svc=$(get_fpm_service "$php_ver")

    local services="$ws_svc $fpm_svc"

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

    local result_text=""
    for svc in $services; do
        [ -z "$svc" ] && continue
        if svc_restart "$svc" 2>/dev/null; then
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

    if [ "$webserver" = "apache" ]; then
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
        "$DIALOG_BIN" --title "Log" --msgbox "Log file not found:\n${logfile:-unknown}" 8 50 2>/dev/null
        return
    fi

    local tmplog="/tmp/stack_dialog_logview"
    tail -50 "$logfile" > "$tmplog" 2>/dev/null || echo "(empty or unreadable)" > "$tmplog"
    "$DIALOG_BIN" --title "$choice — last 50 lines" \
        --textbox "$tmplog" 24 80 2>/dev/null
    rm -f "$tmplog"
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
    cred_text="${cred_text}File: ${STACK_CREDS} (chmod 600)"

    "$DIALOG_BIN" --title "DB Credentials" \
        --msgbox "$cred_text" 26 55 2>/dev/null
}

change_db_password() {
    if [ ! -f "$STACK_CREDS" ] || [ ! -s "$STACK_CREDS" ]; then
        "$DIALOG_BIN" --title "Change Password" \
            --msgbox "No databases with stored credentials found." 7 50 2>/dev/null
        return
    fi

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

    local db_user=""
    while IFS='|' read -r service user password; do
        if [ "$service" = "$selected" ]; then
            db_user="$user"
            break
        fi
    done < "$STACK_CREDS"

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
        "$DIALOG_BIN" --title "Password Changed" \
            --msgbox "${selected} password updated successfully.\n\n  User:     ${db_user}\n  Password: ${new_pass}\n\nThis has been saved to the credentials store." 12 55 2>/dev/null
    else
        "$DIALOG_BIN" --title "Error" \
            --msgbox "Failed to change ${selected} password.\n\n${error_msg}" 12 60 2>/dev/null
    fi
}

create_db_user() {
    local items=""
    local tag_count=0
    if [ "${HAS_MYSQL:-${SEL_MYSQL:-off}}" = "on" ]; then
        items="$items MySQL 'MySQL Server' off"
        tag_count=$((tag_count + 1))
    fi
    if [ "${HAS_MARIADB:-${SEL_MARIADB:-off}}" = "on" ]; then
        items="$items MariaDB 'MariaDB Server' off"
        tag_count=$((tag_count + 1))
    fi
    if [ "${HAS_POSTGRESQL:-${SEL_POSTGRESQL:-off}}" = "on" ]; then
        items="$items PostgreSQL 'PostgreSQL Server' off"
        tag_count=$((tag_count + 1))
    fi
    if [ "${HAS_MONGODB:-${SEL_MONGODB:-off}}" = "on" ]; then
        items="$items MongoDB 'MongoDB Server' off"
        tag_count=$((tag_count + 1))
    fi

    if [ "$tag_count" -eq 0 ]; then
        "$DIALOG_BIN" --title "Create DB User" \
            --msgbox "No databases installed." 7 40 2>/dev/null
        return
    fi

    local height=$((tag_count + 8))
    local selected
    selected=$(eval run_dialog --title \"Create DB User\" \
        --radiolist \"'Select database:'\" "$height" 55 "$tag_count" \
        "$items") || return 0

    [ -z "$selected" ] && return 0

    local new_user
    new_user=$(run_dialog --title "Create User — ${selected}" \
        --inputbox "Enter username:" 8 55 "") || return 0
    if [ -z "$new_user" ]; then
        "$DIALOG_BIN" --title "Error" --msgbox "Username cannot be empty." 7 40 2>/dev/null
        return
    fi

    local new_pass=""
    local method
    method=$(run_dialog --title "Password for ${new_user}" \
        --menu "How would you like to set the password?" 12 55 2 \
        "auto"   "Auto-generate secure password" \
        "manual" "Enter password manually") || return 0

    if [ "$method" = "auto" ]; then
        new_pass=$(generate_password)
    else
        new_pass=$(run_dialog --title "Password for ${new_user}" \
            --inputbox "Enter password:" 8 55 "") || return 0
        if [ -z "$new_pass" ]; then
            "$DIALOG_BIN" --title "Error" --msgbox "Password cannot be empty." 7 40 2>/dev/null
            return
        fi
    fi

    local grant_db=""
    if [ "$selected" != "MongoDB" ]; then
        local db_choice
        db_choice=$(run_dialog --title "Grant Privileges" \
            --menu "Grant this user access to:" 12 55 3 \
            "all"      "All databases (full privileges)" \
            "specific" "A specific database" \
            "none"     "No grants (create user only)") || return 0

        if [ "$db_choice" = "specific" ]; then
            grant_db=$(run_dialog --title "Database Name" \
                --inputbox "Enter database name to grant access to:" 8 55 "") || return 0
            if [ -z "$grant_db" ]; then
                "$DIALOG_BIN" --title "Error" --msgbox "Database name cannot be empty." 7 45 2>/dev/null
                return
            fi
        elif [ "$db_choice" = "all" ]; then
            grant_db="*"
        fi
    fi

    local mongo_db="admin"
    local mongo_role="readWrite"
    if [ "$selected" = "MongoDB" ]; then
        mongo_db=$(run_dialog --title "MongoDB Database" \
            --inputbox "Auth/target database:" 8 55 "admin") || return 0
        [ -z "$mongo_db" ] && mongo_db="admin"

        mongo_role=$(run_dialog --title "MongoDB Role" \
            --menu "Select role for ${new_user}:" 14 55 5 \
            "readWrite"     "Read and write to the database" \
            "read"          "Read-only access" \
            "dbAdmin"       "Database administration" \
            "userAdmin"     "User administration" \
            "root"          "Superuser (all privileges)") || return 0
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

        local detail="User:     ${new_user}\n  Password: ${new_pass}"
        case "$selected" in
            MongoDB)
                detail="${detail}\n  Database: ${mongo_db}\n  Role:     ${mongo_role}" ;;
            *)
                if [ "$grant_db" = "*" ]; then
                    detail="${detail}\n  Grants:   ALL PRIVILEGES (superuser)"
                elif [ -n "$grant_db" ]; then
                    detail="${detail}\n  Grants:   ALL on ${grant_db}"
                else
                    detail="${detail}\n  Grants:   None (login only)"
                fi
                ;;
        esac

        "$DIALOG_BIN" --title "User Created" \
            --msgbox "${selected} user created successfully.\n\n  ${detail}\n\nSaved to credentials store." 16 58 2>/dev/null
    else
        "$DIALOG_BIN" --title "Error" \
            --msgbox "Failed to create ${selected} user.\n\n${error_msg}" 12 60 2>/dev/null
    fi
}

remove_services() {
    local webserver="${WEBSERVER:-$SEL_WEBSERVER}"
    local php_ver="${PHP_VER}"

    local items=""
    local tag_count=0

    if [ -n "$webserver" ] && pkg_is_installed "$APACHE_PKG" 2>/dev/null && [ "$webserver" = "apache" ]; then
        items="$items apache 'Apache Web Server' off"
        tag_count=$((tag_count + 1))
    fi
    if [ -n "$webserver" ] && pkg_is_installed "nginx" 2>/dev/null && [ "$webserver" = "nginx" ]; then
        items="$items nginx 'Nginx Web Server' off"
        tag_count=$((tag_count + 1))
    fi

    if [ -n "$php_ver" ]; then
        local php_check_pkg="php${php_ver}-fpm"
        [ "$DISTRO" = "fedora" ] && php_check_pkg="php-fpm"
        [ "$DISTRO" = "macos" ] && php_check_pkg="php"
        if pkg_is_installed "$php_check_pkg" 2>/dev/null; then
            items="$items php 'PHP ${php_ver} + all extensions' off"
            tag_count=$((tag_count + 1))
        fi
    fi

    if [ "${HAS_MYSQL:-${SEL_MYSQL:-off}}" = "on" ]; then
        items="$items mysql 'MySQL Server' off"
        tag_count=$((tag_count + 1))
    fi
    if [ "${HAS_MARIADB:-${SEL_MARIADB:-off}}" = "on" ]; then
        items="$items mariadb 'MariaDB Server' off"
        tag_count=$((tag_count + 1))
    fi
    if [ "${HAS_POSTGRESQL:-${SEL_POSTGRESQL:-off}}" = "on" ]; then
        items="$items postgresql 'PostgreSQL Server' off"
        tag_count=$((tag_count + 1))
    fi
    if [ "${HAS_MONGODB:-${SEL_MONGODB:-off}}" = "on" ]; then
        items="$items mongodb 'MongoDB Server' off"
        tag_count=$((tag_count + 1))
    fi
    if [ "${HAS_PHPMYADMIN:-off}" = "on" ]; then
        items="$items phpmyadmin 'phpMyAdmin' off"
        tag_count=$((tag_count + 1))
    fi
    if [ "${HAS_ADMINER:-off}" = "on" ]; then
        items="$items adminer 'Adminer' off"
        tag_count=$((tag_count + 1))
    fi

    if [ "$tag_count" -eq 0 ]; then
        "$DIALOG_BIN" --title "Remove Services" \
            --msgbox "No removable services found." 7 40 2>/dev/null
        return
    fi

    local height=$((tag_count + 8))
    [ "$height" -gt 22 ] && height=22
    local selected
    selected=$(eval run_dialog --title \"Remove Services\" \
        --checklist \"'Select services to remove:\n(SPACE to toggle, ENTER to confirm)'\" "$height" 58 "$tag_count" \
        "$items") || return 0

    [ -z "$selected" ] && return 0

    local clean_list
    clean_list=$(echo "$selected" | sed 's/"//g' | tr ' ' ', ')
    "$DIALOG_BIN" --title "Confirm Removal" \
        --yesno "This will STOP and REMOVE the following services:\n\n  ${clean_list}\n\nDatabase data may be lost!\nAre you sure?" 12 58 2>/dev/null \
        || return 0

    local purge_data=false
    if [ "$DISTRO" != "macos" ]; then
        "$DIALOG_BIN" --title "Remove Data?" \
            --yesno "Also remove all configuration and data files?\n\n  Yes = purge (clean slate)\n  No  = remove packages only (data kept)" 10 55 2>/dev/null \
            && purge_data=true
    fi

    [ "$purge_data" = true ] && export PURGE_MODE="purge"

    local result_text=""
    local raw_selected
    raw_selected=$(echo "$selected" | sed 's/"//g')

    for svc in $raw_selected; do
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

    "$DIALOG_BIN" --title "Removal Complete" \
        --msgbox "The following services were removed:\n\n${result_text}\nConfig and credentials updated." 16 55 2>/dev/null
}

control_panel() {
    local docroot="${DOCROOT:-$SEL_DOCROOT}"
    local port="${PORT:-$SEL_PORT}"

    while true; do
        local choice
        choice=$(run_dialog --title "Stack Control Panel (${DISTRO})" \
            --menu "Select an action:" 26 60 13 \
            "open-site"   "Open Site in Browser" \
            "phpinfo"     "PHP Info Page" \
            "files"       "File Explorer" \
            "phpmyadmin"  "phpMyAdmin" \
            "adminer"     "Adminer (DB Manager)" \
            "db-creds"    "Show DB Credentials" \
            "db-passwd"   "Change DB Password" \
            "db-user"     "Create DB User" \
            "status"      "Service Status" \
            "restart"     "Restart All Services" \
            "remove"      "Remove Services" \
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
            db-user)
                create_db_user
                ;;
            status)
                show_service_status
                ;;
            restart)
                panel_restart_services
                ;;
            remove)
                remove_services
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

