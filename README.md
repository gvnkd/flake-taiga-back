# flake-taiga-back

Nix flake that packages [taiga-back](https://github.com/taigaio/taiga-back) 6.10.0 and provides:

- A **NixOS module** (`services.taiga.*`) for production deployment with Gunicorn, Celery, PostgreSQL, RabbitMQ, and nginx
- A **dev shell** with ephemeral PostgreSQL + RabbitMQ + Taiga API via `services:start`

## Quick Start — Dev Shell

```shell-session
$ nix develop
🔨 Welcome to Taiga Backend

taiga-back$ setup-postgres          # first time: initialize PG data dir
taiga-back$ services:start          # start PostgreSQL + RabbitMQ + Taiga API
taiga-back$ setup-db                # first time: create DB, run migrations
taiga-back$ curl -s localhost:8000/api/v1/ | head -3
"locales": "http://localhost:8000/api/v1/locales", ...
taiga-back$ services:stop
```

The Taiga API listens on `0.0.0.0:8000`. All ephemeral data lives in `.data/` (gitignored).

## Quick Start — NixOS Module

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    flake-taiga-back.url = "github:gvnkd/flake-taiga-back";
  };

  outputs = { nixpkgs, flake-taiga-back, ... }:
    {
      nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./configuration.nix
          flake-taiga-back.nixosModules.default
        ];
      };
    };
}
```

```nix
# configuration.nix
{ ... }:
{
  services.taiga = {
    enable = true;
    domain = "taiga.example.com";
    secretKey = "run: openssl rand -hex 50";

    database.passwordFile = "/run/keys/taiga-db-password";
    events.rabbitmqUrl = "amqp://taiga:changeme@localhost:5672/taiga";
    celery.brokerUrl = "amqp://taiga:changeme@localhost:5672/taiga";
  };
}
```

This enables everything with sensible defaults:

- PostgreSQL database `taiga` with user `taiga`
- RabbitMQ for events and Celery
- Gunicorn on `127.0.0.1:8000`
- Celery worker (4 concurrent workers)
- nginx on port 80 reverse-proxying to Gunicorn, serving `/static/` and `/media/`

## Dev Shell Reference

The dev shell uses [numtide/devshell](https://github.com/numtide/devshell). Enter it with `nix develop`.

### Service Groups

Ephemeral services managed via honcho. Data stored in `$PRJ_DATA_DIR` (`.data/`):

| Command | Description |
|---|---|
| `services:start` | Start PostgreSQL + RabbitMQ + Taiga API |
| `services:stop` | Stop all services |
| `db:start` / `db:stop` | Start/stop PostgreSQL only |
| `queue:start` / `queue:stop` | Start/stop RabbitMQ only |
| `api:start` / `api:stop` | Start/stop Taiga API (Gunicorn) only |

### Dev Commands

| Command | Category | Description |
|---|---|---|
| `setup-postgres` | — | Initialize PostgreSQL data directory (first time) |
| `setup-db` | database | Create the `taiga` database and run migrations |
| `reset-db` | database | Drop and recreate the `taiga` database |
| `runserver` | development | Django dev server with auto-reload on `0.0.0.0:8000` |
| `test` | development | Run the test suite (`pytest`, uses `tests.config` settings) |
| `lint` | development | Run flake8 on taiga-back source |
| `menu` | — | Show all available commands |

### Typical Workflow

```shell-session
$ nix develop

# First-time setup
taiga-back$ setup-postgres
taiga-back$ db:start
taiga-back$ setup-db
taiga-back$ db:stop

# Daily workflow — start everything at once
taiga-back$ services:start
# API available at http://localhost:8000/api/v1/

# Or start services individually
taiga-back$ db:start
taiga-back$ queue:start
taiga-back$ api:start

# Development with auto-reload (instead of api:start)
taiga-back$ db:start
taiga-back$ runserver

# Run tests (needs PostgreSQL running)
taiga-back$ db:start
taiga-back$ test

# Clean up
taiga-back$ services:stop
```

### Dev Configuration

The dev shell uses `dev-config.py` which inherits from `settings.common` and overrides:

- `DEBUG = True`
- Local PostgreSQL (peer auth, database `taiga`)
- RabbitMQ at `amqp://localhost:5672`
- Celery disabled (for simpler dev)
- Webhooks and telemetry disabled
- Public registration enabled

This config is symlinked into `$PRJ_ROOT` on shell entry.

## NixOS Module — Architecture

The module creates four systemd services:

| Service | Role |
|---|---|
| `taiga-setup.service` | One-shot: runs `migrate`, `loaddata`, `collectstatic` |
| `taiga.service` | Gunicorn WSGI server |
| `taiga-celery.service` | Celery worker + beat scheduler (optional) |
| `nginx.service` | Reverse proxy (optional) |

All application services require `taiga-setup` to complete first.

## NixOS Module — Configuration Reference

All options live under `services.taiga`.

### Core

| Option | Type | Default | Description |
|---|---|---|---|
| `enable` | `bool` | `false` | Enable the module. |
| `package` | `package` | flake default | The `taiga-back` derivation. |
| `user` | `str` | `"taiga"` | System user. |
| `group` | `str` | `"taiga"` | System group. |
| `secretKey` | `str` | *(required)* | Django `SECRET_KEY`. |
| `domain` | `str` | *(required)* | Public domain. Used as nginx `server_name` and in Django `SITES`. |
| `scheme` | `str` | `"http"` | URL scheme (`"https"` for TLS). |
| `languageCode` | `str` | `"en-us"` | Django `LANGUAGE_CODE`. |
| `debug` | `bool` | `false` | Django `DEBUG` mode. |
| `mediaRoot` | `str` | `"/var/lib/taiga/media"` | Uploaded files directory. |
| `staticRoot` | `str` | `"/var/lib/taiga/static"` | `collectstatic` output directory. |
| `enableCelery` | `bool` | `true` | Enable the Celery worker. |
| `webhooksEnabled` | `bool` | `true` | Enable outgoing webhooks. |
| `publicRegisterEnabled` | `bool` | `false` | Allow public registration. |
| `enableTelemetry` | `bool` | `false` | Enable telemetry. |
| `defaultProjectSlugPrefix` | `bool` | `false` | Prefix project slugs with username. |
| `sessionCookieSecure` | `bool` | `true` | `SESSION_COOKIE_SECURE`. |
| `csrfCookieSecure` | `bool` | `true` | `CSRF_COOKIE_SECURE`. |

### `gunicorn`

| Option | Type | Default | Description |
|---|---|---|---|
| `gunicorn.bind` | `str` | `"127.0.0.1:8000"` | Listen address. |
| `gunicorn.workers` | `int` | `3` | Number of workers. |
| `gunicorn.extraArgs` | `str` | `""` | Extra CLI flags. |

### `nginx`

| Option | Type | Default | Description |
|---|---|---|---|
| `nginx.enable` | `bool` | `true` | Enable nginx virtual host. |
| `nginx.host` | `str` | `"127.0.0.1"` | Listen address. |
| `nginx.port` | `int` | `80` | Listen port. |
| `nginx.serverName` | `nullOr str` | `null` | Override `server_name`. Defaults to `domain`. |
| `nginx.enableACME` | `bool` | `false` | Let's Encrypt TLS certificate. |
| `nginx.forceSSL` | `bool` | `false` | Redirect HTTP to HTTPS. |
| `nginx.maxBodySize` | `str` | `"100m"` | `client_max_body_size`. |
| `nginx.proxyTimeout` | `str` | `"120s"` | `proxy_read_timeout`. |
| `nginx.extraConfig` | `lines` | `""` | Extra nginx directives. |

### `database`

| Option | Type | Default | Description |
|---|---|---|---|
| `database.host` | `str` | `"127.0.0.1"` | PostgreSQL host. |
| `database.port` | `int` | `5432` | PostgreSQL port. |
| `database.name` | `str` | `"taiga"` | Database name. |
| `database.user` | `str` | `"taiga"` | Database user. |
| `database.password` | `str` | `""` | Password in plaintext. Prefer `passwordFile`. |
| `database.passwordFile` | `str` | `""` | File containing the password. |
| `database.createLocally` | `bool` | `true` | Auto-enable PostgreSQL and create the DB/user. |

### `events`

| Option | Type | Default | Description |
|---|---|---|---|
| `events.rabbitmqUrl` | `str` | *(required)* | AMQP URL for events push backend. |

### `celery`

| Option | Type | Default | Description |
|---|---|---|---|
| `celery.brokerUrl` | `str` | *(required)* | AMQP URL for Celery broker. |
| `celery.timezone` | `str` | `"Europe/Madrid"` | Scheduler timezone. |
| `celery.concurrency` | `int` | `4` | Worker concurrency. |
| `celery.extraArgs` | `str` | `""` | Extra CLI flags. |

### `email`

| Option | Type | Default | Description |
|---|---|---|---|
| `email.backend` | `str` | `"django.core.mail.backends.console.EmailBackend"` | Django email backend. |
| `email.fromAddress` | `str` | `"system@taiga.io"` | Default `From` address. |
| `email.host` | `str` | `"localhost"` | SMTP host. |
| `email.port` | `int` | `587` | SMTP port. |
| `email.user` | `str` | `""` | SMTP user. |
| `email.passwordFile` | `str` | `""` | File containing SMTP password. |
| `email.useTls` | `bool` | `false` | Use TLS. |
| `email.useSsl` | `bool` | `false` | Use SSL. |
| `email.changeNotificationsInterval` | `int` | `120` | Seconds between notification batches. |

## Example NixOS Configurations

### Minimal (HTTP, local services)

```nix
services.taiga = {
  enable = true;
  domain = "taiga.example.com";
  secretKey = "openssl rand -hex 50";
  database.password = "changeme";
  events.rabbitmqUrl = "amqp://taiga:changeme@localhost:5672/taiga";
  celery.brokerUrl = "amqp://taiga:changeme@localhost:5672/taiga";
};
```

### Production (HTTPS, secrets from files)

```nix
services.taiga = {
  enable = true;
  scheme = "https";
  domain = "taiga.example.com";
  secretKeyFile = "/run/keys/taiga-secret-key";

  nginx = {
    enableACME = true;
    forceSSL = true;
    host = "0.0.0.0";
    port = 443;
  };

  database = {
    createLocally = false;
    host = "db.internal";
    passwordFile = "/run/keys/taiga-db-password";
  };

  events.rabbitmqUrl = "amqp://taiga:changeme@rabbitmq.internal:5672/taiga";
  celery.brokerUrl = "amqp://taiga:changeme@rabbitmq.internal:5672/taiga";

  email = {
    backend = "django.core.mail.backends.smtp.EmailBackend";
    host = "smtp.example.com";
    port = 587;
    user = "taiga@example.com";
    passwordFile = "/run/keys/taiga-smtp-password";
    useTls = true;
  };
};
```

### Without nginx

```nix
services.taiga = {
  enable = true;
  domain = "taiga.example.com";
  secretKey = "changeme";
  nginx.enable = false;
  gunicorn.bind = "unix:/run/taiga/gunicorn.sock";
  events.rabbitmqUrl = "amqp://taiga:changeme@localhost:5672/taiga";
  celery.brokerUrl = "amqp://taiga:changeme@localhost:5672/taiga";
};
```

### Without Celery

```nix
services.taiga = {
  enable = true;
  domain = "taiga.example.com";
  secretKey = "changeme";
  enableCelery = false;
  events.rabbitmqUrl = "amqp://taiga:changeme@localhost:5672/taiga";
  database.password = "changeme";
};
```

## Building

```shell
nix build                    # build the taiga-back package
nix build .#taiga-back       # explicit attribute
nix run                      # run gunicorn directly
```

The build produces a derivation with `bin/python`, `bin/gunicorn`, and `bin/celery`. The app source is in `$out/app/` and Python dependencies in `$out/deps/python/`.

## Managing the Database (NixOS)

```shell-session
# Run pending migrations
sudo -u taiga taiga-back-env/bin/python manage.py migrate

# Create a superuser
sudo -u taiga taiga-back-env/bin/python manage.py createsuperuser

# Re-run setup (migrate + collectstatic)
systemctl restart taiga-setup
```

## File Structure

```
flake.nix              # Flake entry point — wires inputs to modules
flake.lock             # Pinned dependencies
dev-config.py          # Dev shell Django settings (overrides settings.common)
devshell.nix           # Dev shell definition (services, commands)
python-packages.nix    # Python 3.11 overrides and env (Django 3.2, etc.)
package.nix            # taiga-back derivation
nixos-module.nix       # NixOS module (options + config)
.gitignore
README.md
```

## Key Decisions

- **Python 3.11** — nixpkgs 25.05's celery/sphinx chain requires 3.11+
- **Django 3.2.25** — nixpkgs default is 4.x, project requires `<4`
- **`bleach` 4.1.0** — v5+ changed `ALLOWED_TAGS` from list to frozenset
- **`easy-thumbnails` 2.8.5** — 2.10+ requires Django 4.2
- **`django-picklefield` 3.2** — 3.3+ requires Django 4.2
- **`flake = false`** on the taiga-back input — upstream has no `flake.nix`
- Celery uses `pickle` serialization (upstream behavior)
- Source filter excludes `.git`, `__pycache__`, `result*`
