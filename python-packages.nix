{ pkgs }:

let
  python = pkgs.python311;

  packageOverrides = self: super: {
    django-sampledatahelper = super.buildPythonPackage rec {
      pname = "django-sampledatahelper";
      version = "0.5";
      src = super.fetchPypi {
        inherit pname version;
        hash = "sha256-P7xVM/EFX50ZRAl/YnHosY/PTtXMWCtRhhZEUUUwABU=";
      };
      propagatedBuildInputs = [ self.django ];
      nativeBuildInputs = [ super.versiontools ];
      doCheck = false;
    };

    django-sr = super.buildPythonPackage rec {
      pname = "django-sr";
      version = "0.0.4";
      src = super.fetchPypi {
        inherit pname version;
        hash = "sha256-NYa4Uq6K8bSyeWWQU0sLhntSP0eld5ssy2zgEO/FfjQ=";
      };
      propagatedBuildInputs = [ self.django ];
      doCheck = false;
    };

    django-sites = super.buildPythonPackage rec {
      pname = "django-sites";
      version = "0.11";
      src = super.fetchPypi {
        inherit pname version;
        hash = "sha256-HL7nFP3yv76S5PUFXeTmxBtk67MuH5axAWwHSCEJKLg=";
      };
      propagatedBuildInputs = [ self.django ];
      doCheck = false;
      meta = pkgs.lib.optionalAttrs (super.django-sites ? meta) super.django-sites.meta // { broken = false; };
    };

    rudder-sdk-python = super.buildPythonPackage rec {
      pname = "rudder-sdk-python";
      version = "1.0.0b1";
      src = super.fetchPypi {
        inherit pname version;
        hash = "sha256-IDW48SemYrFEc7JHSyZWnXomcryqTarx/VhQ9BYZnwA=";
      };
      propagatedBuildInputs = [ super.requests super.backoff super.monotonic super.python-dateutil ];
      doCheck = false;
    };

    premailer = super.buildPythonPackage rec {
      pname = "premailer";
      version = "3.10.0";
      src = super.fetchPypi {
        inherit pname version;
        hash = "sha256-0YdahBH13JK1Pvnxk9tsD4edw3jWGOCtKScj44i/5MI=";
      };
      propagatedBuildInputs = [ super.requests super.cssutils super.lxml super.beautifulsoup4 super.cachetools ];
      doCheck = false;
    };

    billiard = super.billiard.overridePythonAttrs (old: { doCheck = false; });

    easy-thumbnails = super.buildPythonPackage rec {
      pname = "easy-thumbnails";
      version = "2.8.5";
      src = super.fetchPypi {
        inherit pname version;
        hash = "sha256-fk6RJgn8m2Czof72VX7BXd+cT5RiZ6kuaSDf1N12XjU=";
      };
      propagatedBuildInputs = [ self.django super.pillow ];
      doCheck = false;
    };

    debugpy = super.debugpy.overridePythonAttrs (old: { doCheck = false; });

    pytest-django = super.pytest-django.overridePythonAttrs (old: { doCheck = false; });

    bleach = super.buildPythonPackage rec {
      pname = "bleach";
      version = "4.1.0";
      src = super.fetchPypi {
        inherit pname version;
        hash = "sha256-CQDYs366YagC7kCsAGH4wrXe4pwZJ90dIz4HXr9acdo=";
      };
      propagatedBuildInputs = [ super.packaging super.six super.webencodings ];
      doCheck = false;
    };

    django-picklefield = super.buildPythonPackage rec {
      pname = "django-picklefield";
      version = "3.2";
      src = super.fetchPypi {
        inherit pname version;
        hash = "sha256-qkY/XXnUl9vnifFLRRgPAKUdDWcAZ9BynzUqOUHN+k0=";
      };
      propagatedBuildInputs = [ self.django ];
      doCheck = false;
    };

    django = super.buildPythonPackage rec {
      pname = "Django";
      version = "3.2.25";
      src = super.fetchPypi {
        inherit pname version;
        hash = "sha256-fKOKeGVK7nI3hZTWPlFjbAS44oV09VBd/2MIlbVHJ3c=";
      };
      propagatedBuildInputs = [ super.asgiref super.pytz super.sqlparse ];
      doCheck = false;
    };

    imageio = super.imageio.overridePythonAttrs (old: { doCheck = false; });
    scikit-image = super.scikit-image.overridePythonAttrs (old: { doCheck = false; });
    astropy = super.astropy.overridePythonAttrs (old: { doCheck = false; });
    pytest-doctestplus = super.pytest-doctestplus.overridePythonAttrs (old: { doCheck = false; });
  };

  pythonEnv = (python.override { inherit packageOverrides; }).withPackages (ps: with ps; [
    django
    celery
    gunicorn
    psycopg2
    redis

    django-sampledatahelper
    django-sites
    django-sr
    djmail

    bleach
    diff-match-patch
    django-ipware
    django-jinja
    django-picklefield
    django-pglocks
    easy-thumbnails
    netaddr
    premailer
    psd-tools
    python-dateutil
    python-magic
    pytz
    requests
    requests-oauthlib
    rudder-sdk-python
    sentry-sdk
    serpy
    webcolors
    cairosvg
    markdown
    pymdown-extensions
    pillow
    unidecode
    pygments
    oauthlib
    html5lib

    asana

    pyjwt
    jinja2
    kombu
    lxml
    cssutils
    cssselect
  ]);
in
{
  inherit python pythonEnv;
}
