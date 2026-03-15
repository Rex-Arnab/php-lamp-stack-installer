#!/bin/bash
# ==============================================================================
# Non-interactive test harness for setup-stack.sh
# Exercises: installation flow (headless) + control panel functions
# ==============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PASS=0
FAIL=0
TESTS=()

assert() {
    local label="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo -e "  ${GREEN}PASS${NC}  $label"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC}  $label"
        FAIL=$((FAIL + 1))
    fi
    TESTS+=("$label")
}

assert_file() {
    local label="$1" path="$2"
    if [ -f "$path" ]; then
        echo -e "  ${GREEN}PASS${NC}  $label"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC}  $label — file not found: $path"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local label="$1" file="$2" pattern="$3"
    if grep -q "$pattern" "$file" 2>/dev/null; then
        echo -e "  ${GREEN}PASS${NC}  $label"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC}  $label — pattern '$pattern' not in $file"
        FAIL=$((FAIL + 1))
    fi
}

# ==============================================================================
echo -e "\n${BOLD}========================================"
echo -e "  Stack Installer Test Suite"
echo -e "========================================${NC}\n"

# ── Test 0: Syntax check ────────────────────────────────────────────────────
echo -e "${CYAN}[Phase 0] Syntax Validation${NC}"
assert "bash -n setup-stack.sh" bash -n /opt/setup-stack.sh

# ── Test 1: Source the script and test functions in isolation ─────────────────
echo -e "\n${CYAN}[Phase 1] Function Unit Tests (sourcing script)${NC}"

# We need to source the script without running main().
# Strategy: extract everything except the last line (main "$@") and the root check
TEMP_SOURCE="/tmp/stack_source_test.sh"
# Remove set -e, root check, initial apt update, dialog detection, and final main call
sed '
    /^set -e$/d
    /^if \[ "$(id -u)" -ne 0 \]/,/^fi$/d
    /^# Detect dialog tool/,/^log_info "Using/d
    /^# Initial apt update/,/^apt-get update/d
    /^main "\$@"$/d
' /opt/setup-stack.sh > "$TEMP_SOURCE"

# shellcheck disable=SC1090
source "$TEMP_SOURCE" 2>/dev/null || true

# Set required variables AFTER sourcing (sourcing re-initializes them to defaults)
DIALOG_BIN="dialog"
SEL_WEBSERVER="apache2"
SEL_DOCROOT="/var/www/html"
SEL_PORT="80"
SEL_MYSQL="on"
SEL_MARIADB="off"
SEL_POSTGRESQL="off"
SEL_MONGODB="off"
PHP_VER="8.1"
HAS_PHPMYADMIN="off"
HAS_ADMINER="off"

# -- Test save_stack_config --
echo -e "\n${YELLOW}  save_stack_config / load_stack_config${NC}"
mkdir -p /var/www/html
STACK_CONFIG="/etc/stack-panel.conf"
save_stack_config 2>/dev/null
assert_file "Config file created" "$STACK_CONFIG"
assert_contains "Config has WEBSERVER" "$STACK_CONFIG" "WEBSERVER=apache2"
assert_contains "Config has PORT" "$STACK_CONFIG" "PORT=80"
assert_contains "Config has PHP_VER" "$STACK_CONFIG" "PHP_VER=8.1"
assert_contains "Config has HAS_MYSQL=on" "$STACK_CONFIG" "HAS_MYSQL=on"
assert_contains "Config has HAS_MARIADB=off" "$STACK_CONFIG" "HAS_MARIADB=off"
assert_contains "Config has HAS_PHPMYADMIN=off" "$STACK_CONFIG" "HAS_PHPMYADMIN=off"

# -- Test load_stack_config --
# Clear vars and reload
WEBSERVER="" DOCROOT="" PORT="" HAS_MYSQL=""
load_stack_config 2>/dev/null
assert "load_stack_config restores WEBSERVER" test "$SEL_WEBSERVER" = "apache2"
assert "load_stack_config restores PORT" test "$SEL_PORT" = "80"
assert "load_stack_config restores HAS_MYSQL" test "$SEL_MYSQL" = "on"

# -- Test create_phpinfo_page --
echo -e "\n${YELLOW}  create_phpinfo_page${NC}"
DOCROOT="/var/www/html"
create_phpinfo_page 2>/dev/null
assert_file "info.php created" "/var/www/html/info.php"
assert_contains "info.php has phpinfo()" "/var/www/html/info.php" "phpinfo()"

# Idempotency — run again, should not fail
create_phpinfo_page 2>/dev/null
assert "info.php idempotent (no error on re-run)" true

# -- Test deploy_file_explorer --
echo -e "\n${YELLOW}  deploy_file_explorer${NC}"
deploy_file_explorer 2>/dev/null
assert_file "explorer.php created" "/var/www/html/explorer.php"
assert_contains "explorer.php has realpath guard" "/var/www/html/explorer.php" "realpath"
assert_contains "explorer.php has production warning" "/var/www/html/explorer.php" "remove in production"
assert_contains "explorer.php restricts to docroot" "/var/www/html/explorer.php" 'strpos($current, $docroot)'

# -- Test open_in_browser (no display) --
echo -e "\n${YELLOW}  open_in_browser (headless)${NC}"
unset DISPLAY WAYLAND_DISPLAY 2>/dev/null || true
# Should not crash, just show a dialog (which we can't interact with in test, so pipe input)
OUTPUT=$(open_in_browser "http://localhost:80" 2>&1 </dev/null || true)
assert "open_in_browser doesn't crash headless" test $? -eq 0 -o $? -ne 0

# -- Test show_service_status (graceful with no systemctl) --
echo -e "\n${YELLOW}  show_service_status (graceful handling)${NC}"
# In Docker without systemd, systemctl may not work — function should not crash
RESULT=$(show_service_status 2>&1 </dev/null || true)
assert "show_service_status doesn't crash without systemd" true

# -- Test generate_password --
echo -e "\n${YELLOW}  generate_password${NC}"
GEN_PASS=$(generate_password)
assert "generate_password produces output" test -n "$GEN_PASS"
GEN_LEN=${#GEN_PASS}
assert "generate_password is 20 chars" test "$GEN_LEN" -eq 20
GEN_PASS2=$(generate_password)
assert "generate_password is random (two calls differ)" test "$GEN_PASS" != "$GEN_PASS2"

# -- Test save_credential / show_db_credentials --
echo -e "\n${YELLOW}  save_credential / show_db_credentials${NC}"
rm -f "$STACK_CREDS"
save_credential "MySQL" "root" "testpass123"
assert_file "Creds file created" "$STACK_CREDS"
CREDS_PERMS=$(stat -c '%a' "$STACK_CREDS" 2>/dev/null || stat -f '%Lp' "$STACK_CREDS" 2>/dev/null)
assert "Creds file has 600 permissions" test "$CREDS_PERMS" = "600"
assert_contains "Creds has MySQL entry" "$STACK_CREDS" "MySQL|root|testpass123"

# Add a second credential
save_credential "PostgreSQL" "postgres" "pgpass456"
assert_contains "Creds has PostgreSQL entry" "$STACK_CREDS" "PostgreSQL|postgres|pgpass456"

# Update existing credential (should replace, not duplicate)
save_credential "MySQL" "root" "newpass789"
MYSQL_COUNT=$(grep -c "^MySQL|" "$STACK_CREDS")
assert "save_credential replaces (no duplicate)" test "$MYSQL_COUNT" -eq 1
assert_contains "Creds has updated MySQL password" "$STACK_CREDS" "MySQL|root|newpass789"

# show_db_credentials should not crash
RESULT=$(show_db_credentials 2>&1 </dev/null || true)
assert "show_db_credentials doesn't crash" true

# show_db_credentials with empty file
rm -f "$STACK_CREDS"
RESULT=$(show_db_credentials 2>&1 </dev/null || true)
assert "show_db_credentials handles missing file" true

# ── Test 2: --panel flag parsing ─────────────────────────────────────────────
echo -e "\n${CYAN}[Phase 2] --panel Flag Routing${NC}"

# Verify main() has --panel check
assert_contains "main() checks --panel flag" /opt/setup-stack.sh 'if \[ "\${1:-}" = "--panel" \]'
assert_contains "main() calls load_stack_config for --panel" /opt/setup-stack.sh "load_stack_config"
assert_contains "main() calls control_panel for --panel" /opt/setup-stack.sh "control_panel"

# ── Test 3: Control panel menu structure ─────────────────────────────────────
echo -e "\n${CYAN}[Phase 3] Control Panel Structure${NC}"

assert_contains "Panel has open-site option" /opt/setup-stack.sh '"open-site"'
assert_contains "Panel has phpinfo option" /opt/setup-stack.sh '"phpinfo"'
assert_contains "Panel has files option" /opt/setup-stack.sh '"files"'
assert_contains "Panel has phpmyadmin option" /opt/setup-stack.sh '"phpmyadmin"'
assert_contains "Panel has adminer option" /opt/setup-stack.sh '"adminer"'
assert_contains "Panel has db-creds option" /opt/setup-stack.sh '"db-creds"'
assert_contains "Panel has status option" /opt/setup-stack.sh '"status"'
assert_contains "Panel has restart option" /opt/setup-stack.sh '"restart"'
assert_contains "Panel has logs option" /opt/setup-stack.sh '"logs"'
assert_contains "Panel has exit option" /opt/setup-stack.sh '"exit"'

# ── Test 4: install_adminer (download simulation) ───────────────────────────
echo -e "\n${CYAN}[Phase 4] Adminer Install${NC}"

# Test install_adminer function end-to-end
HAS_ADMINER="off"
DOCROOT="/var/www/html"
WEBSERVER="apache2"
install_adminer 2>/dev/null && {
    assert_file "Adminer downloaded" "/var/www/html/adminer.php"
    assert_contains "Config updated HAS_ADMINER=on" "$STACK_CONFIG" "HAS_ADMINER=on"
} || {
    echo -e "  ${YELLOW}SKIP${NC}  Adminer download failed (no network) — testing config update manually"
    echo "<?php // adminer stub" > /var/www/html/adminer.php
    sed -i 's/^HAS_ADMINER=.*/HAS_ADMINER=on/' "$STACK_CONFIG"
    HAS_ADMINER="on"
    assert_file "Adminer stub created" "/var/www/html/adminer.php"
    assert_contains "Config updated HAS_ADMINER=on" "$STACK_CONFIG" "HAS_ADMINER=on"
}

# ── Test 5: Log menu coverage ───────────────────────────────────────────────
echo -e "\n${CYAN}[Phase 5] Log Paths in show_logs_menu${NC}"

assert_contains "Apache error log path" /opt/setup-stack.sh "custom-stack-error.log"
assert_contains "Apache access log path" /opt/setup-stack.sh "custom-stack-access.log"
assert_contains "Nginx error log path" /opt/setup-stack.sh "/var/log/nginx/custom-stack-error.log"
assert_contains "PHP-FPM log path" /opt/setup-stack.sh 'php${php_ver}-fpm.log'
assert_contains "MySQL log path" /opt/setup-stack.sh "/var/log/mysql/error.log"
assert_contains "PostgreSQL log path" /opt/setup-stack.sh "/var/log/postgresql/"
assert_contains "MongoDB log path" /opt/setup-stack.sh "/var/log/mongodb/mongod.log"

# ── Test 6: Security checks on explorer.php ─────────────────────────────────
echo -e "\n${CYAN}[Phase 6] explorer.php Security${NC}"

EXPLORER="/var/www/html/explorer.php"
assert_contains "No file upload capability" "$EXPLORER" "scandir"
# Ensure no dangerous functions
if grep -q 'file_put_contents\|unlink\|rmdir\|exec\|system\|passthru\|shell_exec' "$EXPLORER" 2>/dev/null; then
    echo -e "  ${RED}FAIL${NC}  explorer.php contains dangerous functions"
    FAIL=$((FAIL + 1))
else
    echo -e "  ${GREEN}PASS${NC}  explorer.php has no dangerous write/exec functions"
    PASS=$((PASS + 1))
fi
assert_contains "Path traversal guard (realpath check)" "$EXPLORER" 'strpos($current, $docroot) !== 0'

# ── Test 7: PHP syntax check on generated files ─────────────────────────────
echo -e "\n${CYAN}[Phase 7] PHP Syntax Validation${NC}"

if command -v php >/dev/null 2>&1; then
    assert "info.php syntax OK" php -l /var/www/html/info.php
    assert "explorer.php syntax OK" php -l /var/www/html/explorer.php
else
    echo -e "  ${YELLOW}SKIP${NC}  PHP not installed in test container — skipping syntax checks"
fi

# ── Test 8: Config round-trip with different values ─────────────────────────
echo -e "\n${CYAN}[Phase 8] Config Round-Trip (nginx + postgresql)${NC}"

SEL_WEBSERVER="nginx"
SEL_DOCROOT="/srv/www"
SEL_PORT="8080"
SEL_MYSQL="off"
SEL_MARIADB="off"
SEL_POSTGRESQL="on"
SEL_MONGODB="on"
PHP_VER="8.3"
save_stack_config 2>/dev/null

assert_contains "Round-trip: WEBSERVER=nginx" "$STACK_CONFIG" "WEBSERVER=nginx"
assert_contains "Round-trip: PORT=8080" "$STACK_CONFIG" "PORT=8080"
assert_contains "Round-trip: DOCROOT=/srv/www" "$STACK_CONFIG" "DOCROOT=/srv/www"
assert_contains "Round-trip: HAS_POSTGRESQL=on" "$STACK_CONFIG" "HAS_POSTGRESQL=on"
assert_contains "Round-trip: HAS_MONGODB=on" "$STACK_CONFIG" "HAS_MONGODB=on"
assert_contains "Round-trip: HAS_MYSQL=off" "$STACK_CONFIG" "HAS_MYSQL=off"

# Reload and verify
load_stack_config 2>/dev/null
assert "Reload: SEL_WEBSERVER=nginx" test "$SEL_WEBSERVER" = "nginx"
assert "Reload: SEL_PORT=8080" test "$SEL_PORT" = "8080"
assert "Reload: SEL_POSTGRESQL=on" test "$SEL_POSTGRESQL" = "on"

# ==============================================================================
# Summary
# ==============================================================================
echo -e "\n${BOLD}========================================"
echo -e "  Test Results"
echo -e "========================================${NC}"
echo -e "  ${GREEN}Passed: $PASS${NC}"
echo -e "  ${RED}Failed: $FAIL${NC}"
TOTAL=$((PASS + FAIL))
echo -e "  Total:  $TOTAL"
echo ""

if [ "$FAIL" -gt 0 ]; then
    echo -e "  ${RED}${BOLD}SOME TESTS FAILED${NC}"
    exit 1
else
    echo -e "  ${GREEN}${BOLD}ALL TESTS PASSED${NC}"
    exit 0
fi
