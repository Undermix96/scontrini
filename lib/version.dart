/// Versione dell'app, passata dal workflow di build con `--dart-define`.
///
/// Nome = data della build (CalVer, es. 2026.11.5), build = numero
/// dell'esecuzione del workflow. Nelle build locali sono vuoti.
const appVersion = String.fromEnvironment('APP_VERSION');
const appBuild = String.fromEnvironment('APP_BUILD');

/// "2026.11.5 (build 57)", oppure "sviluppo" per le build locali.
String versionLabel({String version = appVersion, String build = appBuild}) {
  if (version.isEmpty) return 'sviluppo';
  return build.isEmpty ? version : '$version (build $build)';
}
