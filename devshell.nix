{ pkgs, devshell, devshellLib, python, pythonEnv, taigaBack, taigaFront, projectRoot, devConfig }:

let
  gunicornCmd = "DJANGO_SETTINGS_MODULE=dev-config PYTHONPATH=\"${projectRoot}:${projectRoot}/settings:${pythonEnv}/${python.sitePackages}:$PRJ_ROOT\" ${pythonEnv}/bin/python -m gunicorn taiga.wsgi:application --name taiga_api --bind 0.0.0.0:8000 --workers 2 --log-level info --access-logfile -";

  managePy = "${pythonEnv}/bin/python ${projectRoot}/manage.py";

  frontConf = pkgs.writeText "conf.json" (builtins.toJSON {
    api = "http://localhost:8000/api/v1/";
    eventsUrl = null;
    baseHref = "/";
    eventsMaxMissedHeartbeats = 5;
    eventsHeartbeatIntervalTime = 60000;
    eventsReconnectTryInterval = 10000;
    debug = true;
    debugInfo = true;
    defaultLanguage = "en";
    themes = [ "taiga" ];
    defaultTheme = "taiga";
    defaultLoginEnabled = true;
    publicRegisterEnabled = true;
    feedbackEnabled = true;
    supportUrl = "https://community.taiga.io/";
    privacyPolicyUrl = null;
    termsOfServiceUrl = null;
    maxUploadFileSize = null;
    contribPlugins = [];
    tagManager = { accountId = null; };
    tribeHost = null;
    enableAsanaImporter = false;
    enableGithubImporter = false;
    enableJiraImporter = false;
    enableTrelloImporter = false;
    gravatar = false;
    rtlLanguages = [ "ar" "fa" "he" ];
  });

  frontRoot = pkgs.runCommand "taiga-front-dev" { } ''
    mkdir -p $out
    cp -r ${taigaFront}/* $out/
    rm -f $out/conf.json
    ln -s ${frontConf} $out/conf.json
  '';

  nginxConf = pkgs.writeText "nginx-taiga-front.conf" ''
    worker_processes 1;
    error_log logs/error.log;

    events {
        worker_connections 64;
    }

    http {
        access_log logs/access.log;

        server {
            listen 9001 default_server;
            client_max_body_size 100m;
            charset utf-8;

            location / {
                alias ${frontRoot}/;
                index index.html;
                try_files $uri $uri/ /index.html;
            }

            location /api/ {
                proxy_pass http://127.0.0.1:8000;
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto $scheme;
            }
        }
    }
  '';

  frontCmd = ''
    NGINX_DIR="$PRJ_DATA_DIR/nginx"
    mkdir -p "$NGINX_DIR"/{logs,body,fastcgi,proxy,uwsgi,scgi}
    nginx -p "$NGINX_DIR" -c ${nginxConf} -g 'daemon off;'
  '';
in
devshellLib.mkShell {
  imports = [ "${devshell}/extra/services/postgres.nix" ];

  devshell = {
    name = "taiga-back";
    motd = ''
      {202}🔨 Welcome to Taiga Backend{reset}
        Frontend: http://localhost:9001
        API:      http://localhost:8000/api/v1/
      $(type -p menu &>/dev/null && menu)
    '';
  };

  packages = with pkgs; [
    python
    python.pkgs.pip
    python.pkgs.pytest
    python.pkgs.pytest-django
    python.pkgs.factory-boy
    python.pkgs.flake8
    python.pkgs.coverage
    gettext
    rabbitmq-server
    curl
    nginx
  ];

  env = [
    {
      name = "DJANGO_SETTINGS_MODULE";
      value = "dev-config";
    }
    {
      name = "PYTHONPATH";
      eval = "${projectRoot}:${projectRoot}/settings:${pythonEnv}/${python.sitePackages}:$PRJ_ROOT";
    }
    {
      name = "TAIGA_DEV_CONFIG";
      value = "${devConfig}";
    }
    {
      name = "RABBITMQ_MNESIA_BASE";
      eval = "$PRJ_DATA_DIR/rabbitmq/mnesia";
    }
    {
      name = "RABBITMQ_LOG_BASE";
      eval = "$PRJ_DATA_DIR/rabbitmq/log";
    }
    {
      name = "RABBITMQ_ENABLED_PLUGINS_FILE";
      eval = "$PRJ_DATA_DIR/rabbitmq/enabled_plugins";
    }
  ];

  devshell.startup.link-dev-config = {
    text = ''
      cp "$TAIGA_DEV_CONFIG" "$PRJ_ROOT/dev-config.py"
    '';
  };

  serviceGroups = {
    db = {
      description = "database (PostgreSQL)";
      services.postgres.command = "postgres";
    };
    queue = {
      description = "message queue (RabbitMQ)";
      services.rabbitmq.command = "mkdir -p $PRJ_DATA_DIR/rabbitmq/mnesia $PRJ_DATA_DIR/rabbitmq/log && rabbitmq-server";
    };
    api = {
      description = "taiga API (Gunicorn)";
      services.taiga.command = gunicornCmd;
    };
    front = {
      description = "taiga frontend (nginx on :9001)";
      services.front.command = frontCmd;
    };
    services = {
      description = "all services (PostgreSQL + RabbitMQ + Taiga API + Frontend)";
      services = {
        postgres.command = "postgres";
        rabbitmq.command = "mkdir -p $PRJ_DATA_DIR/rabbitmq/mnesia $PRJ_DATA_DIR/rabbitmq/log && rabbitmq-server";
        taiga.command = gunicornCmd;
        front.command = frontCmd;
      };
    };
  };

  commands = [
    {
      name = "setup-db";
      category = "database";
      help = "Create the taiga database and run migrations";
      command = ''
        createdb taiga 2>/dev/null || true
        ${managePy} migrate
        ${managePy} loaddata initial_project_templates || true
      '';
    }
    {
      name = "reset-db";
      category = "database";
      help = "Drop and recreate the taiga database with sample data";
      command = ''
        dropdb --if-exists taiga
        createdb taiga
        ${managePy} migrate
        ${managePy} loaddata initial_project_templates || true
      '';
    }
    {
      name = "runserver";
      category = "development";
      help = "Start the Django development server (auto-reload)";
      command = "${managePy} runserver 0.0.0.0:8000";
    }
    {
      name = "test";
      category = "development";
      help = "Run the test suite with pytest";
      command = ''
        export DJANGO_SETTINGS_MODULE=tests.config
        pytest "$@"
      '';
    }
    {
      name = "lint";
      category = "development";
      help = "Run flake8 linter";
      command = "flake8 ${projectRoot}";
    }
  ];
}
