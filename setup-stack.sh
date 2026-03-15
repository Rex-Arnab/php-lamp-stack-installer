#!/bin/bash
# ==============================================================================
# Interactive LAMP/LEMP Stack Setup Script
# Menu-driven web development stack installer
# Supports: Ubuntu/Debian, Fedora/RHEL, macOS
# ==============================================================================

set -e

# Resolve script directory (works with symlinks)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Source modules ───────────────────────────────────────────────────────────

source "${SCRIPT_DIR}/lib/platform.sh"
source "${SCRIPT_DIR}/lib/menus.sh"
source "${SCRIPT_DIR}/lib/install.sh"
source "${SCRIPT_DIR}/lib/panel.sh"

# ── Bootstrap ────────────────────────────────────────────────────────────────

cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Script failed at line $BASH_LINENO with exit code $exit_code"
        log_error "Check the output above for details."
    fi
    rm -f /tmp/stack_dialog_* 2>/dev/null
    exit $exit_code
}
trap cleanup EXIT

# Detect OS and set all platform variables
detect_os

# ── Selection variables ──────────────────────────────────────────────────────

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
SEL_DOCROOT="$DEFAULT_DOCROOT"
SEL_PORT="80"

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
    # Check for --panel flag (skip root check and pkg update)
    if [ "${1:-}" = "--panel" ]; then
        load_stack_config
        control_panel
        exit 0
    fi

    # Root check (not needed on macOS with Homebrew)
    if [ "$DISTRO" != "macos" ]; then
        if [ "$(id -u)" -ne 0 ]; then
            log_error "This script must be run as root (use sudo)."
            exit 1
        fi
    fi

    # Package list update
    if [ "$DISTRO" = "macos" ]; then
        read -p "[?] Update Homebrew package list? This may take a minute. (y/N): " brew_update_choice
        if [[ "$brew_update_choice" =~ ^[Yy]$ ]]; then
            log_info "Updating Homebrew..."
            pkg_update
        else
            log_info "Skipping Homebrew update."
        fi
    else
        log_info "Updating package lists..."
        pkg_update
    fi

    # Interactive menus
    echo ""
    echo -e "${BOLD}========================================${NC}"
    echo -e "${BOLD}  Stack Installation Wizard${NC}"
    echo -e "${BOLD}========================================${NC}"
    echo -e "  Configure your web development stack."
    echo -e "  Press ${CYAN}ENTER${NC} to accept defaults shown in [brackets]."
    pick_webserver
    pick_sql_databases
    pick_mongodb
    pick_php_extensions
    pick_php_settings
    pick_docroot
    pick_port
    confirm_selections

    echo ""
    echo -e "${BOLD}========================================${NC}"
    echo -e "${BOLD}  Starting Stack Installation (${DISTRO})${NC}"
    echo -e "${BOLD}========================================${NC}"
    echo ""

    # 1. Install PHP first (needed for web server config)
    PHP_VER=""
    install_php

    # 2. Install web server
    if [ "$SEL_WEBSERVER" = "apache" ]; then
        install_apache
    elif [ "$SEL_WEBSERVER" = "nginx" ]; then
        install_nginx
    fi

    # 3. Install databases
    [ "$SEL_MYSQL" = "on" ] && install_mysql
    [ "$SEL_MARIADB" = "on" ] && install_mariadb
    [ "$SEL_POSTGRESQL" = "on" ] && install_postgresql
    [ "$SEL_MONGODB" = "on" ] && install_mongodb

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
    if [ "$DISTRO" = "macos" ]; then
        server_ip=$(ipconfig getifaddr en0 2>/dev/null || echo "localhost")
    else
        server_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    [ -z "$server_ip" ] && server_ip="<server-ip>"

    echo ""
    echo -e "${BOLD}========================================${NC}"
    echo -e "${GREEN}${BOLD}  Installation Complete!${NC}"
    echo -e "${BOLD}========================================${NC}"
    echo ""
    echo -e "  Platform:      ${CYAN}${DISTRO}${NC}"
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
