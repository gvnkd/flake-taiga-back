{ pkgs, src, pythonEnv, python }:

pkgs.stdenv.mkDerivation rec {
  pname = "taiga-back";
  version = "6.10.0";

  inherit src;

  nativeBuildInputs = with pkgs; [
    gettext
    makeWrapper
  ];

  buildInputs = [ pythonEnv ];

  buildPhase = ''
    runHook preBuild
    export DJANGO_SETTINGS_MODULE=settings.common
    export PYTHONPATH=${pythonEnv}/${python.sitePackages}
    ${pythonEnv}/bin/python manage.py compilemessages
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/app $out/bin $out/deps

    cp -r taiga $out/app/
    cp -r settings $out/app/
    cp manage.py $out/

    ln -s ${pythonEnv}/${python.sitePackages} $out/deps/python

    makeWrapper ${pythonEnv}/bin/python $out/bin/python \
      --prefix PYTHONPATH : "$out/app:$out/deps/python" \
      --set DJANGO_SETTINGS_MODULE settings.config
    makeWrapper $out/bin/python $out/bin/gunicorn \
      --argv0 gunicorn \
      --add-flags "-m gunicorn"
    makeWrapper $out/bin/python $out/bin/celery \
      --argv0 celery \
      --add-flags "-m celery"

    runHook postInstall
  '';

  doCheck = false;

  meta = with pkgs.lib; {
    description = "Taiga project management platform backend";
    homepage = "https://taiga.io";
    license = licenses.mpl20;
    platforms = platforms.linux;
  };
}
