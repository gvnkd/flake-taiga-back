{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.services.taiga;

  formatBool = v: if v then "True" else "False";

  pyStr = s: "\"" + (replaceStrings ["\"" "\\"] ["\\\"" "\\\\"] s) + "\"";

  settingsFile = pkgs.writeText "config.py" ''
    from settings.common import *
    import os

    #########################################
    ## GENERIC
    #########################################
    DEBUG = ${formatBool cfg.debug}
    SECRET_KEY = ${pyStr cfg.secretKey}

    DATABASES = {
        'default': {
            'ENGINE': 'django.db.backends.postgresql',
            'NAME': ${pyStr cfg.database.name},
            'USER': ${pyStr cfg.database.user},
            'PASSWORD': open(${pyStr cfg.database.passwordFile}).read().strip() if os.path.isfile(${pyStr cfg.database.passwordFile}) else ${pyStr cfg.database.password},
            'HOST': ${pyStr cfg.database.host},
            'PORT': "${toString cfg.database.port}",
        }
    }

    TAIGA_SITES_SCHEME = ${pyStr cfg.scheme}
    TAIGA_SITES_DOMAIN = ${pyStr cfg.domain}
    TAIGA_URL = f"{TAIGA_SITES_SCHEME}://{TAIGA_SITES_DOMAIN}"

    SITES = {
        "api": { "name": "api", "scheme": TAIGA_SITES_SCHEME, "domain": TAIGA_SITES_DOMAIN },
        "front": { "name": "front", "scheme": TAIGA_SITES_SCHEME, "domain": TAIGA_SITES_DOMAIN },
    }

    MEDIA_URL = f"{TAIGA_URL}/media/"
    STATIC_URL = f"{TAIGA_URL}/static/"
    MEDIA_ROOT = ${pyStr cfg.mediaRoot}
    STATIC_ROOT = ${pyStr cfg.staticRoot}

    LANGUAGE_CODE = ${pyStr cfg.languageCode}

    #########################################
    ## EVENTS
    #########################################
    EVENTS_PUSH_BACKEND = "taiga.events.backends.rabbitmq.EventsPushBackend"
    EVENTS_PUSH_BACKEND_OPTIONS = {
        "url": ${pyStr cfg.events.rabbitmqUrl}
    }

    #########################################
    ## CELERY
    #########################################
    CELERY_ENABLED = ${formatBool cfg.enableCelery}
    CELERY_BROKER_URL = ${pyStr cfg.celery.brokerUrl}
    CELERY_RESULT_BACKEND = None
    CELERY_ACCEPT_CONTENT = ['pickle', ]
    CELERY_TASK_SERIALIZER = "pickle"
    CELERY_RESULT_SERIALIZER = "pickle"
    CELERY_TIMEZONE = ${pyStr cfg.celery.timezone}
    CELERY_TASK_DEFAULT_QUEUE = 'tasks'
    CELERY_QUEUES = (
        Queue('tasks', routing_key='task.#'),
        Queue('transient', routing_key='transient.#', delivery_mode=1)
    )
    CELERY_TASK_DEFAULT_EXCHANGE = 'tasks'
    CELERY_TASK_DEFAULT_EXCHANGE_TYPE = 'topic'
    CELERY_TASK_DEFAULT_ROUTING_KEY = 'task.default'

    #########################################
    ## EMAIL
    #########################################
    EMAIL_BACKEND = ${pyStr cfg.email.backend}
    DEFAULT_FROM_EMAIL = ${pyStr cfg.email.fromAddress}
    EMAIL_USE_TLS = ${formatBool cfg.email.useTls}
    EMAIL_USE_SSL = ${formatBool cfg.email.useSsl}
    EMAIL_HOST = ${pyStr cfg.email.host}
    EMAIL_PORT = ${toString cfg.email.port}
    EMAIL_HOST_USER = ${pyStr cfg.email.user}
    CHANGE_NOTIFICATIONS_MIN_INTERVAL = ${toString cfg.email.changeNotificationsInterval}

    #########################################
    ## SESSION
    #########################################
    SESSION_COOKIE_SECURE = ${formatBool cfg.sessionCookieSecure}
    CSRF_COOKIE_SECURE = ${formatBool cfg.csrfCookieSecure}

    #########################################
    ## MISC
    #########################################
    WEBHOOKS_ENABLED = ${formatBool cfg.webhooksEnabled}
    PUBLIC_REGISTER_ENABLED = ${formatBool cfg.publicRegisterEnabled}
    ENABLE_TELEMETRY = ${formatBool cfg.enableTelemetry}
    DEFAULT_PROJECT_SLUG_PREFIX = ${formatBool cfg.defaultProjectSlugPrefix}
  '';

  pkg = cfg.package;

  settingsDir = pkgs.runCommand "taiga-settings" { } ''
    mkdir -p $out/settings
    cp ${pkg}/app/settings/__init__.py $out/settings/
    cp ${settingsFile} $out/settings/config.py
  '';

  taigaPython = pkgs.writeShellScriptBin "taiga-python" ''
    export DJANGO_SETTINGS_MODULE=settings.config
    export PYTHONPATH="${settingsDir}:${pkg}/app:${pkg}/deps"
    exec "$(readlink -f ${pkg}/bin/python)" "$@"
  '';

  taigaGunicorn = pkgs.writeShellScriptBin "taiga-gunicorn" ''
    exec ${taigaPython}/bin/taiga-python -m gunicorn "$@"
  '';

  taigaCelery = pkgs.writeShellScriptBin "taiga-celery" ''
    exec ${taigaPython}/bin/taiga-python -m celery "$@"
  '';

  managePy = "${taigaPython}/bin/taiga-python ${pkg}/manage.py";
in
{
  options.services.taiga = {
    enable = mkEnableOption "Taiga project management backend";

    package = mkOption {
      type = types.package;
      description = "The taiga-back package to use.";
    };

    user = mkOption {
      type = types.str;
      default = "taiga";
      description = "User account under which taiga runs.";
    };

    group = mkOption {
      type = types.str;
      default = "taiga";
      description = "Group under which taiga runs.";
    };

    secretKey = mkOption {
      type = types.str;
      description = "Django SECRET_KEY.";
    };

    scheme = mkOption {
      type = types.str;
      default = "http";
      description = "URL scheme (http or https).";
    };

    domain = mkOption {
      type = types.str;
      example = "taiga.example.com";
      description = "Public domain name for this Taiga instance.";
    };

    languageCode = mkOption {
      type = types.str;
      default = "en-us";
      description = "Default language code.";
    };

    debug = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Django DEBUG mode.";
    };

    mediaRoot = mkOption {
      type = types.str;
      default = "/var/lib/taiga/media";
      description = "Directory for uploaded media files.";
    };

    staticRoot = mkOption {
      type = types.str;
      default = "/var/lib/taiga/static";
      description = "Directory for collected static files.";
    };

    enableCelery = mkOption {
      type = types.bool;
      default = true;
      description = "Enable the Celery async worker.";
    };

    webhooksEnabled = mkOption {
      type = types.bool;
      default = true;
      description = "Enable outgoing webhooks.";
    };

    publicRegisterEnabled = mkOption {
      type = types.bool;
      default = false;
      description = "Allow public registration.";
    };

    enableTelemetry = mkOption {
      type = types.bool;
      default = false;
      description = "Enable telemetry.";
    };

    defaultProjectSlugPrefix = mkOption {
      type = types.bool;
      default = false;
      description = "Prefix project slugs with the username.";
    };

    sessionCookieSecure = mkOption {
      type = types.bool;
      default = true;
      description = "Set SESSION_COOKIE_SECURE.";
    };

    csrfCookieSecure = mkOption {
      type = types.bool;
      default = true;
      description = "Set CSRF_COOKIE_SECURE.";
    };

    gunicorn = {
      bind = mkOption {
        type = types.str;
        default = "127.0.0.1:8000";
        description = "Gunicorn bind address.";
      };
      workers = mkOption {
        type = types.int;
        default = 3;
        description = "Number of gunicorn workers.";
      };
      extraArgs = mkOption {
        type = types.str;
        default = "";
        description = "Extra arguments passed to gunicorn.";
      };
    };

    nginx = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable nginx reverse proxy in front of Gunicorn.";
      };
      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Nginx listen address.";
      };
      port = mkOption {
        type = types.int;
        default = 80;
        description = "Nginx listen port.";
      };
      serverName = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Nginx server_name. Defaults to cfg.domain.";
      };
      enableACME = mkOption {
        type = types.bool;
        default = false;
        description = "Enable ACME (Let's Encrypt) TLS certificate.";
      };
      forceSSL = mkOption {
        type = types.bool;
        default = false;
        description = "Force HTTPS, redirect HTTP to HTTPS.";
      };
      extraConfig = mkOption {
        type = types.lines;
        default = "";
        description = "Extra nginx config lines inserted into the server block.";
      };
      maxBodySize = mkOption {
        type = types.str;
        default = "100m";
        description = "Nginx client_max_body_size (for file uploads).";
      };
      proxyTimeout = mkOption {
        type = types.str;
        default = "120s";
        description = "Nginx proxy_read timeout.";
      };
    };

    database = {
      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "PostgreSQL host.";
      };
      port = mkOption {
        type = types.int;
        default = 5432;
        description = "PostgreSQL port.";
      };
      name = mkOption {
        type = types.str;
        default = "taiga";
        description = "Database name.";
      };
      user = mkOption {
        type = types.str;
        default = "taiga";
        description = "Database user.";
      };
      password = mkOption {
        type = types.str;
        default = "";
        description = "Database password (plain text). Prefer passwordFile.";
      };
      passwordFile = mkOption {
        type = types.str;
        default = "";
        description = "File containing the database password.";
      };
      createLocally = mkOption {
        type = types.bool;
        default = true;
        description = "Create a local PostgreSQL database and user via services.postgresql.";
      };
    };

    events = {
      rabbitmqUrl = mkOption {
        type = types.str;
        example = "amqp://taiga:changeme@localhost:5672/taiga";
        description = "RabbitMQ URL for the events push backend.";
      };
    };

    celery = {
      brokerUrl = mkOption {
        type = types.str;
        example = "amqp://taiga:changeme@localhost:5672/taiga";
        description = "Celery broker URL.";
      };
      timezone = mkOption {
        type = types.str;
        default = "Europe/Madrid";
        description = "Celery timezone.";
      };
      concurrency = mkOption {
        type = types.int;
        default = 4;
        description = "Celery worker concurrency.";
      };
      extraArgs = mkOption {
        type = types.str;
        default = "";
        description = "Extra arguments passed to celery worker.";
      };
    };

    email = {
      backend = mkOption {
        type = types.str;
        default = "django.core.mail.backends.console.EmailBackend";
        description = "Django email backend.";
      };
      fromAddress = mkOption {
        type = types.str;
        default = "system@taiga.io";
        description = "Default From address.";
      };
      host = mkOption {
        type = types.str;
        default = "localhost";
        description = "SMTP host.";
      };
      port = mkOption {
        type = types.int;
        default = 587;
        description = "SMTP port.";
      };
      user = mkOption {
        type = types.str;
        default = "";
        description = "SMTP user.";
      };
      passwordFile = mkOption {
        type = types.str;
        default = "";
        description = "File containing the SMTP password.";
      };
      useTls = mkOption {
        type = types.bool;
        default = false;
        description = "Use TLS for SMTP.";
      };
      useSsl = mkOption {
        type = types.bool;
        default = false;
        description = "Use SSL for SMTP.";
      };
      changeNotificationsInterval = mkOption {
        type = types.int;
        default = 120;
        description = "Minimum interval (seconds) between change notification batches.";
      };
    };
  };

  config = mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = "/var/lib/taiga";
      createHome = true;
    };
    users.groups.${cfg.group} = { };

    services.postgresql = mkIf cfg.database.createLocally {
      enable = true;
      ensureDatabases = [ cfg.database.name ];
      ensureUsers = [{
        name = cfg.database.user;
        ensureDBOwnership = true;
      }];
      authentication = ''
        local   ${cfg.database.name}   ${cfg.database.user}   peer
        host    ${cfg.database.name}   ${cfg.database.user}   127.0.0.1/32   md5
      '';
    };

    services.rabbitmq = mkIf cfg.database.createLocally {
      enable = true;
    };

    systemd.services.taiga-setup = {
      description = "Taiga – one-time setup (migrate + collectstatic + initial data)";
      wantedBy = [ "multi-user.target" ];
      before = [ "taiga.service" ] ++ lib.optionals cfg.enableCelery [ "taiga-celery.service" ];
      after = [ "postgresql.service" "rabbitmq.service" ];
      wants = [ "postgresql.service" "rabbitmq.service" ];
      path = [ pkg pkgs.coreutils ];
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
        StateDirectory = "taiga";
        RemainAfterExit = true;
      };
      script = ''
        ${managePy} migrate
        ${managePy} loaddata initial_project_templates || true
        ${managePy} collectstatic --noinput
        mkdir -p ${cfg.mediaRoot}/exports
      '';
    };

    systemd.services.taiga = {
      description = "Taiga – Gunicorn WSGI server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "postgresql.service" "rabbitmq.service" "taiga-setup.service" ];
      wants = [ "postgresql.service" "rabbitmq.service" "taiga-setup.service" ];
      requires = [ "taiga-setup.service" ];
      serviceConfig = {
        Type = "notify";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = "${pkg}";
        ExecStart = ''
          ${taigaGunicorn}/bin/taiga-gunicorn taiga.wsgi:application \
            --name taiga_api \
            --bind ${cfg.gunicorn.bind} \
            --workers ${toString cfg.gunicorn.workers} \
            --worker-tmp-dir /dev/shm \
            --log-level info \
            --access-logfile - \
            ${cfg.gunicorn.extraArgs}
        '';
        Restart = "on-failure";
        StateDirectory = "taiga";
      };
    };

    systemd.services.taiga-celery = mkIf cfg.enableCelery {
      description = "Taiga – Celery async worker";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "rabbitmq.service" "taiga-setup.service" ];
      wants = [ "rabbitmq.service" ];
      requires = [ "taiga-setup.service" ];
      serviceConfig = {
        Type = "forking";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = "${pkg}";
        ExecStart = ''
          ${taigaCelery}/bin/taiga-celery -A taiga.celery worker -B \
            --concurrency ${toString cfg.celery.concurrency} \
            -l INFO \
            ${cfg.celery.extraArgs}
        '';
        Restart = "on-failure";
        StateDirectory = "taiga";
      };
    };

    services.nginx = mkIf cfg.nginx.enable {
      enable = true;
      recommendedProxySettings = true;
      virtualHosts.${cfg.domain} = {
        inherit (cfg.nginx) enableACME forceSSL;
        serverName = if cfg.nginx.serverName != null then cfg.nginx.serverName else cfg.domain;
        listen = lib.mkDefault [{
          addr = cfg.nginx.host;
          port = cfg.nginx.port;
          ssl = cfg.nginx.enableACME;
        }];
        locations."/" = {
          proxyPass = "http://${cfg.gunicorn.bind}";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_read_timeout ${cfg.nginx.proxyTimeout};
            client_max_body_size ${cfg.nginx.maxBodySize};
          '';
        };
        locations."= /favicon.ico".extraConfig = ''
          access_log off;
          log_not_found off;
        '';
        locations."/static/" = {
          alias = "${cfg.staticRoot}/";
        };
        locations."/media/" = {
          alias = "${cfg.mediaRoot}/";
        };
        extraConfig = cfg.nginx.extraConfig;
      };
    };
  };
}
