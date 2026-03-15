#!/bin/bash
# ==============================================================================
# Interactive dialog menus for stack selection
# ==============================================================================

run_dialog() {
    local tmpfile="/tmp/stack_dialog_result"
    "$DIALOG_BIN" "$@" 2>"$tmpfile"
    local rc=$?
    cat "$tmpfile"
    return $rc
}

pick_webserver() {
    local result
    local apache_label="Apache HTTP Server"
    [ "$DISTRO" = "fedora" ] && apache_label="Apache (httpd)"
    result=$(run_dialog --title "Web Server" \
        --radiolist "Select a web server:\n(Use SPACE to select, ENTER to confirm)" 12 50 2 \
        "apache" "$apache_label" on \
        "nginx"  "Nginx Web Server" off) || { log_error "Cancelled."; exit 1; }
    SEL_WEBSERVER="$result"
}

pick_sql_databases() {
    local result
    local items="\"mysql\" \"MySQL Server\" off \"mariadb\" \"MariaDB Server\" off"
    items="$items \"postgresql\" \"PostgreSQL Server\" off"

    result=$(eval run_dialog --title \"SQL Databases\" \
        --checklist \"'Select SQL databases to install:\n(SPACE to toggle, ENTER to confirm)'\" 14 55 3 \
        "$items") || { log_warn "No SQL database selected."; return 0; }

    case "$result" in *mysql*)      SEL_MYSQL="on" ;; esac
    case "$result" in *mariadb*)    SEL_MARIADB="on" ;; esac
    case "$result" in *postgresql*) SEL_POSTGRESQL="on" ;; esac
}

pick_mongodb() {
    if "$DIALOG_BIN" --title "NoSQL Database" \
        --yesno "Install MongoDB?" 7 40 2>/dev/null; then
        SEL_MONGODB="on"
    fi
}

pick_php_extensions() {
    local items=""

    if [ "$DISTRO" = "macos" ]; then
        items="$items php-redis      'Redis extension'    on"
        items="$items php-imagick    'ImageMagick'        on"
        if [ "$SEL_MONGODB" = "on" ]; then
            items="$items php-mongodb 'MongoDB driver' on"
        fi
        local item_count
        item_count=$(echo "$items" | xargs -n3 2>/dev/null | wc -l | tr -d ' ')
        if [ "$item_count" -eq 0 ]; then
            log_info "PHP on macOS includes most extensions by default."
            SEL_PHP_EXTS=""
            return
        fi
    else
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

        if [ "$SEL_MYSQL" = "on" ] || [ "$SEL_MARIADB" = "on" ]; then
            items="$items php-mysql 'MySQL/MariaDB driver' on"
        fi
        if [ "$SEL_POSTGRESQL" = "on" ]; then
            items="$items php-pgsql 'PostgreSQL driver' on"
        fi
        if [ "$SEL_MONGODB" = "on" ]; then
            items="$items php-mongodb 'MongoDB driver' on"
        fi
    fi

    local item_count
    item_count=$(echo "$items" | xargs -n3 | wc -l | tr -d ' ')

    local height=$((item_count + 8))
    [ "$height" -gt 30 ] && height=30

    local result
    result=$(eval run_dialog --title \"PHP Extensions\" \
        --checklist \"'Select PHP extensions to install:'\" "$height" 60 "$item_count" \
        "$items") || { log_error "Cancelled."; exit 1; }

    SEL_PHP_EXTS="$result"
}

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
        local val
        val=$(run_dialog --title "PHP Settings" --inputbox "upload_max_filesize:" 8 50 "$SEL_UPLOAD_MAX") && SEL_UPLOAD_MAX="$val"
        val=$(run_dialog --title "PHP Settings" --inputbox "post_max_size:" 8 50 "$SEL_POST_MAX") && SEL_POST_MAX="$val"
        val=$(run_dialog --title "PHP Settings" --inputbox "memory_limit:" 8 50 "$SEL_MEMORY_LIMIT") && SEL_MEMORY_LIMIT="$val"
        val=$(run_dialog --title "PHP Settings" --inputbox "max_execution_time:" 8 50 "$SEL_MAX_EXEC_TIME") && SEL_MAX_EXEC_TIME="$val"
        val=$(run_dialog --title "PHP Settings" --inputbox "max_input_vars:" 8 50 "$SEL_MAX_INPUT_VARS") && SEL_MAX_INPUT_VARS="$val"
    fi
}

pick_docroot() {
    local result
    result=$(run_dialog --title "Document Root" \
        --inputbox "Enter the document root path:" 8 60 "$SEL_DOCROOT") || { log_error "Cancelled."; exit 1; }
    [ -n "$result" ] && SEL_DOCROOT="$result"
}

pick_port() {
    local result
    result=$(run_dialog --title "Server Port" \
        --inputbox "Enter the port number:" 8 50 "$SEL_PORT") || { log_error "Cancelled."; exit 1; }
    [ -n "$result" ] && SEL_PORT="$result"
}

confirm_selections() {
    local db_list=""
    [ "$SEL_MYSQL" = "on" ] && db_list="${db_list}MySQL "
    [ "$SEL_MARIADB" = "on" ] && db_list="${db_list}MariaDB "
    [ "$SEL_POSTGRESQL" = "on" ] && db_list="${db_list}PostgreSQL "
    [ "$SEL_MONGODB" = "on" ] && db_list="${db_list}MongoDB "
    [ -z "$db_list" ] && db_list="None"

    local ext_display
    ext_display=$(echo "$SEL_PHP_EXTS" | sed 's/"//g' | tr ' ' '\n' | sort | tr '\n' ' ')

    local summary="
Platform:           ${DISTRO}
Web Server:         ${SEL_WEBSERVER}
Databases:          ${db_list}
PHP Extensions:     ${ext_display}

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
        --yesno "Review your selections:\n$summary\nProceed with installation?" 28 70 2>/dev/null \
        || { log_error "Installation cancelled."; exit 1; }
}
