{ pkgs, devshell, devshellLib, python, projectRoot }:

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
  ];

  env = [
    {
      name = "DJANGO_SETTINGS_MODULE";
      value = "tests.config";
    }
    {
      name = "PYTHONPATH";
      value = "${projectRoot}:${projectRoot}/settings";
    }
    {
      name = "TAIGA_TEST_DB_NAME";
      value = "taiga";
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

  serviceGroups = {
    db = {
      description = "database (PostgreSQL)";
      services = {
        postgres.command = "postgres";
      };
    };
    queue = {
      description = "message queue (RabbitMQ)";
      services = {
        rabbitmq.command = "mkdir -p $PRJ_DATA_DIR/rabbitmq/mnesia $PRJ_DATA_DIR/rabbitmq/log && rabbitmq-server";
      };
    };
    services = {
      description = "all services (PostgreSQL + RabbitMQ)";
      services = {
        postgres.command = "postgres";
        rabbitmq.command = "mkdir -p $PRJ_DATA_DIR/rabbitmq/mnesia $PRJ_DATA_DIR/rabbitmq/log && rabbitmq-server";
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
        python manage.py migrate
        python manage.py loaddata initial_project_templates || true
      '';
    }
    {
      name = "reset-db";
      category = "database";
      help = "Drop and recreate the taiga database with sample data";
      command = ''
        dropdb --if-exists taiga
        createdb taiga
        python manage.py migrate
        python manage.py loaddata initial_project_templates || true
      '';
    }
    {
      name = "runserver";
      category = "development";
      help = "Start the Django development server";
      command = "python manage.py runserver";
    }
    {
      name = "test";
      category = "development";
      help = "Run the test suite with pytest";
      command = "pytest \"$@\"";
    }
    {
      name = "lint";
      category = "development";
      help = "Run flake8 linter";
      command = "flake8 .";
    }
  ];
}
