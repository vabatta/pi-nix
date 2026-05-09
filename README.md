# pi-nix

Nix home-manager module for [pi.dev](https://pi.dev) coding agent.

![pi-coding-agent-v0.74.0](https://img.shields.io/badge/pi--coding--agent-v0.74.0-blue)

Pi is installed and updated via npm at runtime — this module manages configuration, not the binary. No `buildNpmPackage` hashing pain.

## What the module does

- Wraps `pi` with encapsulated Node.js (not on global PATH)
- Generates `settings.json` (seed-once or overwrite per launch)
- Manages `auth.json` and `models.json` via `home.file`
- Provides `pi-setup`, `pi-update`, `pi-reset-config` shell aliases
- First-run guard with helpful install message
- `preLaunchHook` for theme sync or custom pre-launch logic

## Usage

### Flake input

```nix
{
  inputs.pi-nix.url = "github:vabatta/pi-nix";
}
```

### Home-manager import

```nix
# In your darwin or home-manager config:
home-manager.users.<user>.imports = [
  inputs.pi-nix.homeManagerModules.default
];
```

### Configuration

```nix
programs.pi = {
  enable = true;
  provider = "openrouter";
  model = "nvidia/nemotron-3-nano-30b-a3b:free";
  theme = "dark"; # or any installed theme name

  auth.openrouter = {
    type = "api_key";
    key = "your-api-key"; # or "!op read '...'" for 1password
  };

  packages = [
    "npm:pi-mcp-adapter"
    "npm:pi-subagents"
    "npm:pi-web-access"
  ];

  # Custom providers (e.g. local ollama)
  customProviders.ollama-local = {
    name = "Ollama (local)";
    baseUrl = "http://localhost:11434/v1";
    apiKey = "ollama";
    models = [
      { id = "gemma4:26b"; name = "Gemma 4 26B"; input = ["text" "image"]; }
    ];
  };

  mutableSettings = true; # seed once, pi config TUI edits persist
  settings = {}; # extra settings.json keys
  preLaunchHook = ""; # shell commands before pi launches
};
```

### First-time setup

After `darwin-rebuild switch` (or `home-manager switch`):

```bash
pi-setup    # installs pi via npm
pi          # ready to use
```

### Updating pi

```bash
pi-update   # updates to latest npm release
```

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable pi |
| `nodejs` | package | `pkgs.nodejs` | Node.js (encapsulated) |
| `provider` | enum/str | `"openrouter"` | Default provider |
| `model` | str | `""` | Default model |
| `theme` | null/str | `null` | Theme name (null = pi auto-detect) |
| `auth` | attrsOf | `{}` | Auth credentials per provider |
| `customProviders` | attrsOf | `{}` | Custom providers (models.json) |
| `packages` | listOf str | `[]` | Extension packages |
| `mutableSettings` | bool | `true` | Seed-once vs overwrite |
| `settings` | attrs | `{}` | Extra settings.json keys |
| `preLaunchHook` | lines | `""` | Pre-launch shell hook |

## Auto-update

A GitHub Actions workflow checks npm for new pi releases every 6 hours and creates tagged releases to track versions.

## License

MIT
