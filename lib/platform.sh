#!/bin/bash
# ==============================================================================
# Platform detection and OS abstraction layer
# Supports: Ubuntu/Debian, Fedora/RHEL, macOS
# ==============================================================================

# ── Color helpers ────────────────────────────────────────────────────────────

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

# ── OS-specific path variables ───────────────────────────────────────────────

DISTRO=""
PKG_MGR=""
SVC_MGR=""
WEB_USER=""
WEB_GROUP=""
APACHE_PKG=""
APACHE_SVC=""
APACHE_CONF_DIR=""
APACHE_SITES_DIR=""
APACHE_LOG_DIR=""
NGINX_CONF_DIR=""
NGINX_LOG_DIR=""
PHP_CONF_DIR=""
FPM_SOCK_DIR=""
MYSQL_LOG=""
PG_LOG_DIR=""
MONGO_LOG=""
DEFAULT_DOCROOT=""

# ── OS detection ─────────────────────────────────────────────────────────────

detect_os() {
    case "$(uname -s)" in
        Darwin)
            DISTRO="macos"
            PKG_MGR="brew"
            SVC_MGR="brew"
            WEB_USER="$(whoami)"
            WEB_GROUP="staff"
            APACHE_PKG="httpd"
            APACHE_SVC="httpd"
            APACHE_CONF_DIR="/opt/homebrew/etc/httpd"
            APACHE_SITES_DIR="/opt/homebrew/etc/httpd/extra"
            APACHE_LOG_DIR="/opt/homebrew/var/log/httpd"
            NGINX_CONF_DIR="/opt/homebrew/etc/nginx"
            NGINX_LOG_DIR="/opt/homebrew/var/log/nginx"
            PHP_CONF_DIR="/opt/homebrew/etc/php"
            FPM_SOCK_DIR="/tmp"
            MYSQL_LOG="/opt/homebrew/var/log/mysql/error.log"
            PG_LOG_DIR="/opt/homebrew/var/log/postgresql"
            MONGO_LOG="/opt/homebrew/var/log/mongodb/mongod.log"
            DEFAULT_DOCROOT="/opt/homebrew/var/www"
            ;;
        Linux)
            if [ -f /etc/os-release ]; then
                # shellcheck disable=SC1091
                . /etc/os-release
                case "$ID" in
                    ubuntu|debian|linuxmint|pop)
                        DISTRO="debian"
                        ;;
                    fedora|rhel|centos|rocky|alma)
                        DISTRO="fedora"
                        ;;
                    *)
                        case "${ID_LIKE:-}" in
                            *debian*|*ubuntu*) DISTRO="debian" ;;
                            *fedora*|*rhel*)   DISTRO="fedora" ;;
                            *) log_error "Unsupported Linux distribution: $ID"; exit 1 ;;
                        esac
                        ;;
                esac
            else
                log_error "Cannot detect Linux distribution (no /etc/os-release)."
                exit 1
            fi

            SVC_MGR="systemctl"

            if [ "$DISTRO" = "debian" ]; then
                PKG_MGR="apt"
                WEB_USER="www-data"
                WEB_GROUP="www-data"
                APACHE_PKG="apache2"
                APACHE_SVC="apache2"
                APACHE_CONF_DIR="/etc/apache2"
                APACHE_SITES_DIR="/etc/apache2/sites-available"
                APACHE_LOG_DIR="/var/log/apache2"
                NGINX_CONF_DIR="/etc/nginx"
                NGINX_LOG_DIR="/var/log/nginx"
                PHP_CONF_DIR="/etc/php"
                FPM_SOCK_DIR="/run/php"
                MYSQL_LOG="/var/log/mysql/error.log"
                PG_LOG_DIR="/var/log/postgresql"
                MONGO_LOG="/var/log/mongodb/mongod.log"
                DEFAULT_DOCROOT="/var/www/html"
            else
                PKG_MGR="dnf"
                WEB_USER="apache"
                WEB_GROUP="apache"
                APACHE_PKG="httpd"
                APACHE_SVC="httpd"
                APACHE_CONF_DIR="/etc/httpd"
                APACHE_SITES_DIR="/etc/httpd/conf.d"
                APACHE_LOG_DIR="/var/log/httpd"
                NGINX_CONF_DIR="/etc/nginx"
                NGINX_LOG_DIR="/var/log/nginx"
                PHP_CONF_DIR="/etc"
                FPM_SOCK_DIR="/run/php-fpm"
                MYSQL_LOG="/var/log/mysql/mysqld.log"
                PG_LOG_DIR="/var/lib/pgsql/data/log"
                MONGO_LOG="/var/log/mongodb/mongod.log"
                DEFAULT_DOCROOT="/var/www/html"
            fi
            ;;
        *)
            log_error "Unsupported operating system: $(uname -s)"
            exit 1
            ;;
    esac

    log_info "Detected platform: ${DISTRO}"
}

# ── Package manager abstraction ──────────────────────────────────────────────

pkg_update() {
    case "$PKG_MGR" in
        apt)  apt-get update -y -qq ;;
        dnf)  dnf check-update -y -q 2>/dev/null || true ;;
        brew) brew update ;;
    esac
}

pkg_install() {
    case "$PKG_MGR" in
        apt)  apt-get install -y -qq "$@" ;;
        dnf)  dnf install -y -q "$@" ;;
        brew) brew install --quiet "$@" 2>/dev/null || brew upgrade --quiet "$@" 2>/dev/null || true ;;
    esac
}

pkg_remove() {
    local action="${PURGE_MODE:-remove}"
    case "$PKG_MGR" in
        apt)
            if [ "$action" = "purge" ]; then
                apt-get purge -y -qq "$@"
            else
                apt-get remove -y -qq "$@"
            fi
            ;;
        dnf) dnf remove -y -q "$@" ;;
        brew) brew uninstall --quiet "$@" 2>/dev/null || true ;;
    esac
}

pkg_autoremove() {
    case "$PKG_MGR" in
        apt)  apt-get autoremove -y -qq 2>/dev/null || true ;;
        dnf)  dnf autoremove -y -q 2>/dev/null || true ;;
        brew) brew autoremove --quiet 2>/dev/null || true ;;
    esac
}

pkg_is_installed() {
    case "$PKG_MGR" in
        apt)  dpkg -l "$1" >/dev/null 2>&1 ;;
        dnf)  rpm -q "$1" >/dev/null 2>&1 ;;
        brew) brew list "$1" >/dev/null 2>&1 ;;
    esac
}

# ── Service manager abstraction ──────────────────────────────────────────────

_systemctl_available() {
    [ "$SVC_MGR" = "systemctl" ] && pidof systemd >/dev/null 2>&1
}

svc_start() {
    case "$SVC_MGR" in
        systemctl)
            if _systemctl_available; then
                systemctl start "$1"
            else
                service "$1" start 2>/dev/null || log_warn "Could not start $1 (no systemd). Try manually."
            fi
            ;;
        brew) brew services start "$1" ;;
    esac
}

svc_stop() {
    case "$SVC_MGR" in
        systemctl)
            if _systemctl_available; then
                systemctl stop "$1" 2>/dev/null || true
            else
                service "$1" stop 2>/dev/null || true
            fi
            ;;
        brew) brew services stop "$1" 2>/dev/null || true ;;
    esac
}

svc_restart() {
    case "$SVC_MGR" in
        systemctl)
            if _systemctl_available; then
                systemctl restart "$1"
            else
                service "$1" restart 2>/dev/null || log_warn "Could not restart $1 (no systemd). Try manually."
            fi
            ;;
        brew) brew services restart "$1" ;;
    esac
}

svc_enable() {
    case "$SVC_MGR" in
        systemctl)
            if _systemctl_available; then
                systemctl enable "$1"
            fi
            ;;
        brew) ;;
    esac
}

svc_status() {
    case "$SVC_MGR" in
        systemctl)
            if _systemctl_available; then
                systemctl is-active "$1" 2>/dev/null || echo "not-found"
            else
                service "$1" status >/dev/null 2>&1 && echo "active" || echo "inactive"
            fi
            ;;
        brew)
            if brew services list 2>/dev/null | grep -q "^$1.*started"; then
                echo "active"
            else
                echo "inactive"
            fi
            ;;
    esac
}

svc_daemon_reload() {
    case "$SVC_MGR" in
        systemctl)
            if _systemctl_available; then
                systemctl daemon-reload
            fi
            ;;
        brew) ;;
    esac
}

# ── Portable helpers ─────────────────────────────────────────────────────────

sed_i() {
    if [ "$DISTRO" = "macos" ]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

set_web_owner() {
    chown -R "${WEB_USER}:${WEB_GROUP}" "$@"
}

get_fpm_sock() {
    local php_ver="$1"
    case "$DISTRO" in
        debian) echo "${FPM_SOCK_DIR}/php${php_ver}-fpm.sock" ;;
        fedora) echo "${FPM_SOCK_DIR}/www.sock" ;;
        macos)  echo "${FPM_SOCK_DIR}/php-fpm.sock" ;;
    esac
}

get_fpm_service() {
    local php_ver="$1"
    case "$DISTRO" in
        debian) echo "php${php_ver}-fpm" ;;
        fedora) echo "php-fpm" ;;
        macos)  echo "php" ;;
    esac
}
