{ pkgs, devshell, devshellLib, python, pythonEnv, taigaBack, projectRoot, devConfig }:

let
  gunicornCmd = "DJANGO_SETTINGS_MODULE=dev-config PYTHONPATH=\"${projectRoot}:${projectRoot}/settings:${pythonEnv}/${python.sitePackages}:$PRJ_ROOT\" ${pythonEnv}/bin/python -m gunicorn taiga.wsgi:application --name taiga_api --bind 0.0.0.0:8000 --workers 2 --log-level info --access-logfile -";

  managePy = "${pythonEnv}/bin/python ${projectRoot}/manage.py";
in
devshellLib.mkShell {
  imports = [ "${devshell}/extra/services/postgres.nix" ];

  devshell = {
    name = "taiga-back";
    motd = ''
      {202}🔨 Welcome to Taiga Backend{reset}
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
      ln -sf "$TAIGA_DEV_CONFIG" "$PRJ_ROOT/dev-config.py"
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
    services = {
      description = "all services (PostgreSQL + RabbitMQ + Taiga API)";
      services = {
        postgres.command = "postgres";
        rabbitmq.command = "mkdir -p $PRJ_DATA_DIR/rabbitmq/mnesia $PRJ_DATA_DIR/rabbitmq/log && rabbitmq-server";
        taiga.command = gunicornCmd;
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
