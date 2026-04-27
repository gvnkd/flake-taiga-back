# Taiga Backend NixOS Module

This flake packages [taiga-back](https://github.com/taigaio/taiga-back) and provides a NixOS module that deploys the full stack: Django API server (Gunicorn), Celery async worker, PostgreSQL, RabbitMQ, and an nginx reverse proxy.

## Quick Start

Add the flake to your system inputs:

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    taiga-back.url = "github:taigaio/taiga-back";
  };

  outputs = { nixpkgs, taiga-back, ... }@inputs: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        taiga-back.nixosModules.default
      ];
    };
  };
}
```

Then in your `configuration.nix`:

```nix
{ ... }:

{
  services.taiga = {
    enable = true;

    domain = "taiga.example.com";
    secretKey = "some-long-random-string";

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
- nginx on port 80 reverse-proxying to Gunicorn, serving `/static/` and `/media/` directly

## Architecture

The module creates four systemd services and their dependencies:

| Service | Role |
|---|---|
| `taiga-setup.service` | One-shot: runs `migrate`, `loaddata`, `collectstatic`. Runs before the other services. |
| `taiga.service` | Gunicorn WSGI server serving the Django API. |
| `taiga-celery.service` | Celery worker with beat scheduler for async tasks (email, webhooks, telemetry). |
| `nginx.service` | Reverse proxy: routes `/api/v1/` requests to Gunicorn, serves static/media files directly. |

When `database.createLocally` is `true` (default), the module also enables `postgresql.service` and `rabbitmq.service`.

## Configuration Reference

All options live under `services.taiga`.

### Core

| Option | Type | Default | Description |
|---|---|---|---|
| `enable` | `bool` | `false` | Enable the Taiga backend module. |
| `package` | `package` | flake default | The `taiga-back` derivation to use. |
| `user` | `str` | `"taiga"` | System user for all Taiga services. |
| `group` | `str` | `"taiga"` | System group. |
| `secretKey` | `str` | *(required)* | Django `SECRET_KEY`. |
| `domain` | `str` | *(required)* | Public domain (e.g. `taiga.example.com`). Used as nginx `server_name` and in Django's `SITES` / `TAIGA_URL`. |
| `scheme` | `str` | `"http"` | URL scheme. Set to `"https"` when using TLS. |
| `languageCode` | `str` | `"en-us"` | Django `LANGUAGE_CODE`. |
| `debug` | `bool` | `false` | Django `DEBUG` mode. |
| `mediaRoot` | `str` | `"/var/lib/taiga/media"` | Path for uploaded files. nginx serves this at `/media/`. |
| `staticRoot` | `str` | `"/var/lib/taiga/static"` | Path for `collectstatic` output. nginx serves this at `/static/`. |
| `enableCelery` | `bool` | `true` | Enable the Celery worker service. |
| `webhooksEnabled` | `bool` | `true` | Enable outgoing webhooks. |
| `publicRegisterEnabled` | `bool` | `false` | Allow public user registration. |
| `enableTelemetry` | `bool` | `false` | Enable telemetry reporting. |
| `defaultProjectSlugPrefix` | `bool` | `false` | Prefix project URL slugs with the owner's username. |
| `sessionCookieSecure` | `bool` | `true` | Set `SESSION_COOKIE_SECURE`. |
| `csrfCookieSecure` | `bool` | `true` | Set `CSRF_COOKIE_SECURE`. |

### `gunicorn` — WSGI Server

| Option | Type | Default | Description |
|---|---|---|---|
| `gunicorn.bind` | `str` | `"127.0.0.1:8000"` | Gunicorn listen address. nginx proxies to this. |
| `gunicorn.workers` | `int` | `3` | Number of worker processes. |
| `gunicorn.extraArgs` | `str` | `""` | Extra CLI flags passed to `gunicorn`. |

### `nginx` — Reverse Proxy

| Option | Type | Default | Description |
|---|---|---|---|
| `nginx.enable` | `bool` | `true` | Enable the nginx virtual host. |
| `nginx.host` | `str` | `"127.0.0.1"` | Listen address. Use `"0.0.0.0"` to expose externally. |
| `nginx.port` | `int` | `80` | Listen port. |
| `nginx.serverName` | `nullOr str` | `null` | Override `server_name`. Defaults to `services.taiga.domain`. |
| `nginx.enableACME` | `bool` | `false` | Provision a Let's Encrypt certificate via `security.acme`. |
| `nginx.forceSSL` | `bool` | `false` | Redirect HTTP to HTTPS. |
| `nginx.maxBodySize` | `str` | `"100m"` | `client_max_body_size` — controls max upload size. |
| `nginx.proxyTimeout` | `str` | `"120s"` | `proxy_read_timeout` for long-running requests. |
| `nginx.extraConfig` | `lines` | `""` | Extra directives injected into the `server` block. |

The nginx virtual host configures these locations:

- **`/`** — reverse proxy to Gunicorn with WebSocket support, `X-Forwarded-Proto`, configurable timeout and body size.
- **`/static/`** — serves files directly from `staticRoot` (no proxy overhead).
- **`/media/`** — serves uploaded files directly from `mediaRoot`.
- **`= /favicon.ico`** — silenced access log.

### `database` — PostgreSQL

| Option | Type | Default | Description |
|---|---|---|---|
| `database.host` | `str` | `"127.0.0.1"` | PostgreSQL host. |
| `database.port` | `int` | `5432` | PostgreSQL port. |
| `database.name` | `str` | `"taiga"` | Database name. |
| `database.user` | `str` | `"taiga"` | Database user. |
| `database.password` | `str` | `""` | Database password in plaintext. Prefer `passwordFile`. |
| `database.passwordFile` | `str` | `""` | Path to a file containing the database password. Takes precedence over `password`. |
| `database.createLocally` | `bool` | `true` | Automatically enable `services.postgresql` and create the database and user. Set to `false` if you manage PostgreSQL yourself. |

When `createLocally` is `true`, the module configures `peer` auth for local connections and `md5` for TCP connections to this database.

### `events` — Real-Time Push

| Option | Type | Default | Description |
|---|---|---|---|
| `events.rabbitmqUrl` | `str` | *(required)* | AMQP URL for the Django events push backend. Example: `"amqp://taiga:secret@localhost:5672/taiga"`. |

### `celery` — Async Task Worker

| Option | Type | Default | Description |
|---|---|---|---|
| `celery.brokerUrl` | `str` | *(required)* | AMQP URL for the Celery broker. Often the same as `events.rabbitmqUrl`. |
| `celery.timezone` | `str` | `"Europe/Madrid"` | Celery scheduler timezone. |
| `celery.concurrency` | `int` | `4` | Number of concurrent worker processes. |
| `celery.extraArgs` | `str` | `""` | Extra CLI flags passed to `celery worker`. |

### `email` — SMTP

| Option | Type | Default | Description |
|---|---|---|---|
| `email.backend` | `str` | `"django.core.mail.backends.console.EmailBackend"` | Django email backend. Use `"django.core.mail.backends.smtp.EmailBackend"` for production. |
| `email.fromAddress` | `str` | `"system@taiga.io"` | Default `From` address. |
| `email.host` | `str` | `"localhost"` | SMTP server hostname. |
| `email.port` | `int` | `587` | SMTP server port. |
| `email.user` | `str` | `""` | SMTP username. |
| `email.passwordFile` | `str` | `""` | Path to a file containing the SMTP password. |
| `email.useTls` | `bool` | `false` | Use TLS for SMTP. |
| `email.useSsl` | `bool` | `false` | Use SSL for SMTP. |
| `email.changeNotificationsInterval` | `int` | `120` | Seconds between change notification email batches. |

## Example Configurations

### Minimal (HTTP, local PostgreSQL, local RabbitMQ)

```nix
services.taiga = {
  enable = true;
  domain = "taiga.example.com";
  secretKey = "run: openssl rand -hex 50";
  database.password = "changeme";
  events.rabbitmqUrl = "amqp://taiga:changeme@localhost:5672/taiga";
  celery.brokerUrl = "amqp://taiga:changeme@localhost:5672/taiga";
};
```

### Production with HTTPS, secrets from files

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
    maxBodySize = "200m";
  };

  database = {
    createLocally = false;
    host = "db.internal";
    port = 5432;
    name = "taiga";
    user = "taiga";
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

### Without nginx (use your own reverse proxy)

```nix
services.taiga = {
  enable = true;
  domain = "taiga.example.com";
  secretKey = "changeme";

  nginx.enable = false;

  gunicorn.bind = "unix:/run/taiga/gunicorn.sock";

  # ... database, events, celery ...
};
```

### Without Celery (synchronous-only)

```nix
services.taiga = {
  enable = true;
  domain = "taiga.example.com";
  secretKey = "changeme";
  enableCelery = false;
  events.rabbitmqUrl = "amqp://taiga:changeme@localhost:5672/taiga";
  # celery.brokerUrl is not needed when enableCelery is false
  database.password = "changeme";
};
```

## Service Lifecycle

1. **`taiga-setup`** runs first (oneshot): runs Django migrations, loads `initial_project_templates`, runs `collectstatic`, and creates the media exports directory.
2. **`taiga`** starts after setup: Gunicorn serves the WSGI application.
3. **`taiga-celery`** starts after setup (if enabled): Celery worker + beat scheduler.
4. **`nginx`** proxies external traffic to Gunicorn and serves static/media files.

All three application services require `taiga-setup` to complete successfully. If setup fails, the API and Celery services will not start.

## Managing the Database

Run management commands via the packaged `python` wrapper:

```shell-session
# Run pending migrations
sudo -u taiga taiga-back-env/bin/python /path/to/manage.py migrate

# Create a superuser
sudo -u taiga taiga-back-env/bin/python /path/to/manage.py createsuperuser

# Regenerate sample data (destructive)
sudo -u taiga taiga-back-env/bin/python /path/to/manage.py sample_data
```

Or use `systemctl restart taiga-setup` to re-run the setup script (migrations, collectstatic, etc.).

## Dev Shell

Enter a development environment with all tooling:

```shell
nix develop
```

This provides Python 3.11, pytest, flake8, coverage, PostgreSQL, RabbitMQ, and gettext with `DJANGO_SETTINGS_MODULE` set to `tests.config`.

The dev shell uses [numtide/devshell](https://github.com/numtide/devshell) and provides these commands:

### Service Groups

Ephemeral PostgreSQL and RabbitMQ services managed via honcho:

| Command | Description |
|---|---|
| `services:start` | Start PostgreSQL + RabbitMQ together |
| `services:stop` | Stop all services |
| `db:start` | Start only PostgreSQL |
| `db:stop` | Stop PostgreSQL |
| `queue:start` | Start only RabbitMQ |
| `queue:stop` | Stop RabbitMQ |

PostgreSQL data is stored in `$PRJ_DATA_DIR/postgres` (i.e. `.data/postgres` in the project root). A database named after your user is created automatically on first setup.

### Dev Commands

| Command | Category | Description |
|---|---|---|
| `setup-db` | database | Create the `taiga` database and run migrations |
| `reset-db` | database | Drop and recreate the `taiga` database with sample data |
| `runserver` | development | Start the Django development server (`manage.py runserver`) |
| `test` | development | Run the test suite (`pytest`) |
| `lint` | development | Run flake8 linter |
| `menu` | — | Show all available commands |

### Typical Workflow

```shell-session
$ nix develop
🔨 Welcome to Taiga Backend

# Start services
taiga-back$ services:start

# In another terminal (or after backgrounding)
taiga-back$ setup-db

# Run the dev server
taiga-back$ runserver

# Run tests
taiga-back$ test

# Stop services when done
taiga-back$ services:stop
```
