# Stack Installer

Interactive LAMP/LEMP stack setup script with a post-installation control panel. Built for Ubuntu/Debian servers using `dialog`/`whiptail` TUI menus.

## What It Does

**Installation wizard** — walks you through selecting:
- Web server (Apache2 or Nginx)
- SQL databases (MySQL, MariaDB, PostgreSQL)
- NoSQL database (MongoDB)
- PHP extensions (18+ pre-checked, conditional DB drivers)
- PHP ini settings (upload size, memory limit, execution time, etc.)
- Document root and port

**Control panel** — accessible after install or anytime via `--panel`:

| Action | Description |
|--------|-------------|
| Open Site | Opens `http://localhost:<port>` in browser |
| PHP Info | Creates/opens `info.php` |
| File Explorer | Deploys a secure single-file PHP file browser (read-only, no traversal) |
| phpMyAdmin | Installs if missing, then opens in browser |
| Adminer | Downloads single-file DB manager to docroot |
| DB Credentials | Shows stored database usernames/passwords with live validation |
| Change DB Password | Reset a database password (auto-generate or enter manually) |
| Create DB User | Create a new database user with password and privilege grants |
| Service Status | Shows running/stopped state of all installed services |
| Restart Services | Restarts web server, PHP-FPM, and all databases |
| View Logs | Pick a service log and view the last 50 lines |

## Usage

### Fresh Server Setup

1. **Clone the repo** on your Ubuntu/Debian server:
   ```bash
   git clone https://github.com/Rex-Arnab/php-lamp-stack-installer.git
   cd php-lamp-stack-installer
   ```

2. **Make it executable and run**:
   ```bash
   chmod +x setup-stack.sh
   sudo ./setup-stack.sh
   ```

3. **Walk through the menus** — the script will present dialog screens in order:
   - **Web Server** — pick Apache2 or Nginx (radio buttons, SPACE to select, ENTER to confirm)
   - **SQL Databases** — check any combination of MySQL, MariaDB, PostgreSQL (checklist)
   - **MongoDB** — yes/no prompt
   - **PHP Extensions** — 18+ pre-selected with conditional DB drivers (checklist)
   - **PHP Settings** — edit upload size, memory limit, execution time, etc. (form)
   - **Document Root** — defaults to `/var/www/html`
   - **Port** — defaults to `80`
   - **Confirmation** — review all selections before installing

4. **Installation runs automatically** — PHP, web server, databases, firewall, all configured.

5. **Control panel launches** after install completes — manage your stack immediately.

### Using the Control Panel

After installation, the control panel launches automatically. To access it later:

```bash
sudo ./setup-stack.sh --panel
```

Navigate with arrow keys and ENTER. The menu loops until you choose **Exit**.

**What each option does:**

- **Open Site in Browser** — opens `http://localhost:<port>` via `xdg-open`. If no display is detected (SSH session), prints the URL instead.
- **PHP Info** — creates `info.php` in your document root (if missing) and opens it. Useful for verifying PHP version and loaded extensions.
- **File Explorer** — deploys a single-file PHP browser at `explorer.php`. Browse files in your document root with sizes and dates. Read-only, no traversal outside docroot.
- **phpMyAdmin** — if not installed, prompts to install it (`apt-get install phpmyadmin`). For Nginx, auto-symlinks into your docroot. Then opens in browser.
- **Adminer** — downloads the single-file `adminer.php` database manager into your docroot. Supports MySQL, MariaDB, PostgreSQL, MongoDB — all in one file.
- **Show DB Credentials** — displays stored database usernames and passwords. Each credential is live-validated against the actual database — if someone changed the password via phpMyAdmin, CLI, or any other tool, it shows `[CHANGED externally]` instead of `[VALID]`. Credentials are stored in `/etc/stack-panel.creds` (root-only, `chmod 600`).
- **Change DB Password** — pick an installed database, then choose to auto-generate a secure 20-char password or enter one manually. The new password is applied directly to the database and the credentials store is updated. Supports MySQL, MariaDB, PostgreSQL, and MongoDB.
- **Create DB User** — create a new user on any installed database. Prompts for username, password (auto or manual), and privilege level. For MySQL/MariaDB/PostgreSQL you can grant all privileges, access to a specific database, or no grants. For MongoDB you pick the auth database and role (readWrite, read, dbAdmin, userAdmin, root). New credentials are saved to the store.
- **Service Status** — shows whether each installed service (web server, PHP-FPM, databases) is running, stopped, or failed.
- **Restart All Services** — restarts every installed service and reports success/failure for each.
- **View Logs** — sub-menu to pick a service log (Apache/Nginx error/access, PHP-FPM, MySQL, PostgreSQL, MongoDB). Displays the last 50 lines.
- **Exit** — closes the panel and returns to the terminal.

### Examples

```bash
# Set up a LEMP stack with PostgreSQL on port 8080
sudo ./setup-stack.sh
# → pick nginx, check postgresql, set port to 8080 in the menus

# Later, check if services are running
sudo ./setup-stack.sh --panel
# → select "Service Status"

# View Nginx error logs after a 500 error
sudo ./setup-stack.sh --panel
# → select "View Logs" → "Nginx Error Log"

# Add Adminer to manage your database
sudo ./setup-stack.sh --panel
# → select "Adminer" (auto-downloads if not present)

# Forgot your MySQL password? Reset it
sudo ./setup-stack.sh --panel
# → select "Change DB Password" → pick MySQL → auto-generate

# Create a new user for your app's database
sudo ./setup-stack.sh --panel
# → select "Create DB User" → pick database → set username/password/grants
```

## Config

After installation, the script saves state to `/etc/stack-panel.conf`:

```
WEBSERVER=apache2
DOCROOT=/var/www/html
PORT=80
PHP_VER=8.3
HAS_MYSQL=on
HAS_MARIADB=off
HAS_POSTGRESQL=off
HAS_MONGODB=off
HAS_PHPMYADMIN=off
HAS_ADMINER=off
```

This config is read by `--panel` to detect what's installed.

## Requirements

- Ubuntu/Debian (tested on Ubuntu 22.04)
- Root access (`sudo`)
- `dialog` or `whiptail` (auto-installed if missing)

## Testing

Tests run in Docker to avoid touching the host system.

### Run Tests

```bash
# Build and run
docker build -t stack-test .
docker run --rm stack-test
```

### Test Phases and Results

```
========================================
  Stack Installer Test Suite
========================================

[Phase 0] Syntax Validation
  PASS  bash -n setup-stack.sh

[Phase 1] Function Unit Tests (sourcing script)

  save_stack_config / load_stack_config
  PASS  Config file created
  PASS  Config has WEBSERVER
  PASS  Config has PORT
  PASS  Config has PHP_VER
  PASS  Config has HAS_MYSQL=on
  PASS  Config has HAS_MARIADB=off
  PASS  Config has HAS_PHPMYADMIN=off
  PASS  load_stack_config restores WEBSERVER
  PASS  load_stack_config restores PORT
  PASS  load_stack_config restores HAS_MYSQL

  create_phpinfo_page
  PASS  info.php created
  PASS  info.php has phpinfo()
  PASS  info.php idempotent (no error on re-run)

  deploy_file_explorer
  PASS  explorer.php created
  PASS  explorer.php has realpath guard
  PASS  explorer.php has production warning
  PASS  explorer.php restricts to docroot

  open_in_browser (headless)
  PASS  open_in_browser doesn't crash headless

  show_service_status (graceful handling)
  PASS  show_service_status doesn't crash without systemd

  generate_password
  PASS  generate_password produces output
  PASS  generate_password is 20 chars
  PASS  generate_password is random (two calls differ)

  save_credential / show_db_credentials
  PASS  Creds file created
  PASS  Creds file has 600 permissions
  PASS  Creds has MySQL entry
  PASS  Creds has PostgreSQL entry
  PASS  save_credential replaces (no duplicate)
  PASS  Creds has updated MySQL password
  PASS  show_db_credentials doesn't crash
  PASS  show_db_credentials handles missing file

  change_db_password
  PASS  change_db_password handles missing creds file
  PASS  change_db_password handles empty creds file
  PASS  change_db_password handles MySQL
  PASS  change_db_password handles MariaDB
  PASS  change_db_password handles PostgreSQL
  PASS  change_db_password handles MongoDB
  PASS  change_db_password offers auto-generate
  PASS  change_db_password offers manual entry
  PASS  change_db_password saves updated cred

  create_db_user
  PASS  create_db_user handles no databases
  PASS  create_db_user has MySQL CREATE USER
  PASS  create_db_user has PostgreSQL CREATE USER
  PASS  create_db_user has MongoDB createUser
  PASS  create_db_user supports grant all
  PASS  create_db_user supports grant specific db
  PASS  create_db_user supports MongoDB roles
  PASS  create_db_user saves new credential
  PASS  Multiple users per DB in creds file

[Phase 2] --panel Flag Routing
  PASS  main() checks --panel flag
  PASS  main() calls load_stack_config for --panel
  PASS  main() calls control_panel for --panel

[Phase 3] Control Panel Structure
  PASS  Panel has open-site option
  PASS  Panel has phpinfo option
  PASS  Panel has files option
  PASS  Panel has phpmyadmin option
  PASS  Panel has adminer option
  PASS  Panel has db-creds option
  PASS  Panel has db-passwd option
  PASS  Panel has db-user option
  PASS  Panel has status option
  PASS  Panel has restart option
  PASS  Panel has logs option
  PASS  Panel has exit option

[Phase 4] Adminer Install
  PASS  Adminer downloaded
  PASS  Config updated HAS_ADMINER=on

[Phase 5] Log Paths in show_logs_menu
  PASS  Apache error log path
  PASS  Apache access log path
  PASS  Nginx error log path
  PASS  PHP-FPM log path
  PASS  MySQL log path
  PASS  PostgreSQL log path
  PASS  MongoDB log path

[Phase 6] explorer.php Security
  PASS  No file upload capability
  PASS  explorer.php has no dangerous write/exec functions
  PASS  Path traversal guard (realpath check)

[Phase 7] PHP Syntax Validation
  SKIP  PHP not installed in test container — skipping syntax checks

[Phase 8] Config Round-Trip (nginx + postgresql)
  PASS  Round-trip: WEBSERVER=nginx
  PASS  Round-trip: PORT=8080
  PASS  Round-trip: DOCROOT=/srv/www
  PASS  Round-trip: HAS_POSTGRESQL=on
  PASS  Round-trip: HAS_MONGODB=on
  PASS  Round-trip: HAS_MYSQL=off
  PASS  Reload: SEL_WEBSERVER=nginx
  PASS  Reload: SEL_PORT=8080
  PASS  Reload: SEL_POSTGRESQL=on

========================================
  Test Results
========================================
  Passed: 85
  Failed: 0
  Total:  85

  ALL TESTS PASSED
```

### Test Coverage

| Phase | Area | Tests |
|-------|------|-------|
| 0 | Bash syntax (`bash -n`) | 1 |
| 1 | Config save/load, phpinfo, file explorer, browser open, service status, password generation, credential storage/display, password change, user creation | 49 |
| 2 | `--panel` flag routing in `main()` | 3 |
| 3 | All 12 control panel menu items present | 12 |
| 4 | Adminer download + config update | 2 |
| 5 | Log file paths for all services | 7 |
| 6 | explorer.php security (no dangerous functions, traversal guard) | 3 |
| 7 | PHP syntax validation (skipped without PHP) | 0 |
| 8 | Config round-trip with alternate values | 9 |

## File Structure

```
stack-installer/
├── setup-stack.sh   # Main installer + control panel (1038 lines)
├── test-stack.sh    # Non-interactive Docker test harness
├── Dockerfile       # Ubuntu 22.04 test container
└── README.md
```

## Security Notes

- `explorer.php` is read-only — no upload, delete, or edit. Paths are validated with `realpath()` to prevent directory traversal.
- `info.php` and `explorer.php` display a warning banner: remove them in production.
- phpMyAdmin and Adminer are development tools — restrict access or remove before going live.
- DB credentials are stored in `/etc/stack-panel.creds` with `chmod 600` (root-only). Passwords are auto-generated (20 chars, alphanumeric + symbols) during installation. The panel live-validates stored passwords against the actual database — if a password was changed externally (via phpMyAdmin, CLI, etc.), it shows `[CHANGED externally]` so you know the stored value is stale.
