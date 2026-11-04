/// What kind of software a package is. The store's repository JSON declares
/// it per package (`"category": "game" | "app"`) and it decides which registry
/// subfolder an install lands in (`~/software/games` vs `~/software/apps`);
/// when loading from disk the subfolder itself is the source of truth.
enum SoftwareCategory {
  game,
  app;

  /// Parses the repository JSON value; null for anything unknown (callers
  /// decide whether that's a hard error or a default).
  static SoftwareCategory? fromName(String value) => switch (value.trim()) {
    'game' => SoftwareCategory.game,
    'app' => SoftwareCategory.app,
    _ => null,
  };

  /// Plural pt-BR label for filter chips ("Jogos" / "Apps").
  String get label => this == SoftwareCategory.game ? 'Jogos' : 'Apps';

  /// Singular pt-BR label for detail/confirm copy ("Jogo" / "App"). Named
  /// [singularLabel] rather than `name` so it never shadows `Enum.name`.
  String get singularLabel =>
      this == SoftwareCategory.game ? 'Jogo' : 'App';
}
