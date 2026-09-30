{ config, lib, pkgs, ... }:
let
  cfg = config.programs.pi;

  builtinProviders = [
    "amazon-bedrock" "ant-ling" "anthropic" "azure-openai-responses" "baseten"
    "cerebras" "cloudflare-ai-gateway" "cloudflare-workers-ai" "deepseek"
    "fireworks" "github-copilot" "google" "google-vertex" "groq" "huggingface"
    "kimi-coding" "meta" "minimax" "minimax-cn" "mistral" "moonshotai"
    "moonshotai-cn" "nvidia" "openai" "openai-codex" "opencode" "opencode-go"
    "openrouter" "qwen-token-plan" "qwen-token-plan-cn"
    "qwen-token-plan-individual" "radius" "together" "vercel-ai-gateway" "xai"
    "xiaomi" "xiaomi-token-plan-ams" "xiaomi-token-plan-cn"
    "xiaomi-token-plan-sgp" "zai" "zai-coding-cn"
  ];

  # Recursively drop null fields so pi sees absent rather than `null`.
  stripNulls = v:
    if builtins.isAttrs v then
      lib.filterAttrs (_: n: n != null) (lib.mapAttrs (_: stripNulls) v)
    else if builtins.isList v then map stripNulls v
    else v;

  modelType = lib.types.submoduleWith {
    modules = [{
      freeformType = lib.types.attrs;
      options = {
        id = lib.mkOption { type = lib.types.str; description = "Model identifier"; };
        name = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; description = "Display name (pi falls back to id)"; };
        baseUrl = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; description = "API base URL (defaults to provider baseUrl)"; };
        api = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; description = "API protocol (defaults to provider api)"; };
        reasoning = lib.mkOption { type = lib.types.nullOr lib.types.bool; default = null; description = "Whether the model supports reasoning"; };
        input = lib.mkOption { type = lib.types.listOf (lib.types.enum [ "text" "image" ]); default = [ "text" ]; description = "Input modalities"; };
        contextWindow = lib.mkOption { type = lib.types.nullOr lib.types.int; default = null; description = "Context window size (pi default: 128000)"; };
        maxTokens = lib.mkOption { type = lib.types.nullOr lib.types.int; default = null; description = "Max output tokens (pi default: 16384)"; };
      };
    }];
  };

  # pi's PackageSource: either a bare specifier string or an object that
  # filters which resources to load from the package.
  packageSourceType = lib.types.either lib.types.str (lib.types.submodule {
    options = {
      source = lib.mkOption {
        type = lib.types.str;
        description = "Package specifier (npm:... or git:...)";
      };
      autoload = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        description = "If false, start empty and only apply explicit resource filters";
      };
      extensions = lib.mkOption {
        type = lib.types.nullOr (lib.types.listOf lib.types.str);
        default = null;
        description = "If set, only load these named extensions from the package";
      };
      skills = lib.mkOption {
        type = lib.types.nullOr (lib.types.listOf lib.types.str);
        default = null;
        description = "If set, only load these named skills from the package";
      };
      prompts = lib.mkOption {
        type = lib.types.nullOr (lib.types.listOf lib.types.str);
        default = null;
        description = "If set, only load these named prompts from the package";
      };
      themes = lib.mkOption {
        type = lib.types.nullOr (lib.types.listOf lib.types.str);
        default = null;
        description = "If set, only load these named themes from the package";
      };
    };
  });

  # Strip null fields so pi sees absent rather than `null` for omitted filters.
  packageSourceToJSON = src:
    if builtins.isString src then src
    else lib.filterAttrs (_: v: v != null) src;

  providerType = lib.types.submoduleWith {
    modules = [{
      freeformType = lib.types.attrs;
      options = {
        name = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; description = "Display name (pi falls back to provider id)"; };
        baseUrl = lib.mkOption { type = lib.types.str; description = "API base URL"; };
        api = lib.mkOption { type = lib.types.str; default = "openai-completions"; description = "API protocol"; };
        apiKey = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; description = "API key, env var ($VAR), or deferred command (!cmd)"; };
        oauth = lib.mkOption { type = lib.types.nullOr (lib.types.enum [ "radius" ]); default = null; description = "Provider OAuth mode (only radius is supported)"; };
        authHeader = lib.mkOption { type = lib.types.nullOr lib.types.bool; default = null; description = "Send keys/headers as the auth header"; };
        models = lib.mkOption { type = lib.types.listOf modelType; default = []; description = "Available models"; };
      };
    }];
  };

  authEntryType = lib.types.submoduleWith {
    modules = [{
      freeformType = lib.types.attrs;
      options = {
        type = lib.mkOption { type = lib.types.str; default = "api_key"; description = "Auth type (api_key or oauth)"; };
        secret = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; description = "API key, env var ($VAR), or deferred command (!cmd). Emitted as key"; };
        env = lib.mkOption { type = lib.types.attrsOf lib.types.str; default = { }; description = "Extra env vars visible to key interpolation"; };
      };
    }];
  };

  authEntryToJSON = e:
    let
      s = stripNulls e;
      s' = if s ? secret then s // { key = s.secret; } else s;
    in
    if s'.env == { } then lib.removeAttrs s' [ "env" "secret" ]
    else lib.removeAttrs s' [ "secret" ];

  thinkingLevelType = lib.types.enum [ "off" "minimal" "low" "medium" "high" "xhigh" "max" ];

  # Nested settings objects: declared fields default to null (stripped from
  # JSON), freeform attrs let unknown fields pass through verbatim.
  compactionType = lib.types.submoduleWith {
    modules = [{
      freeformType = lib.types.attrs;
      options = {
        enabled = lib.mkOption { type = lib.types.nullOr lib.types.bool; default = null; };
        reserveTokens = lib.mkOption { type = lib.types.nullOr lib.types.ints.positive; default = null; };
        keepRecentTokens = lib.mkOption { type = lib.types.nullOr lib.types.ints.positive; default = null; };
        modelOverrides = lib.mkOption {
          type = lib.types.attrsOf (lib.types.submoduleWith {
            modules = [{
              freeformType = lib.types.attrs;
              options = {
                reserveTokens = lib.mkOption { type = lib.types.nullOr lib.types.ints.positive; default = null; };
                keepRecentTokens = lib.mkOption { type = lib.types.nullOr lib.types.ints.positive; default = null; };
              };
            }];
          });
          default = { };
        };
      };
    }];
  };

  branchSummaryType = lib.types.submoduleWith {
    modules = [{
      freeformType = lib.types.attrs;
      options = {
        reserveTokens = lib.mkOption { type = lib.types.nullOr lib.types.ints.positive; default = null; };
        skipPrompt = lib.mkOption { type = lib.types.nullOr lib.types.bool; default = null; };
      };
    }];
  };

  retryType = lib.types.submoduleWith {
    modules = [{
      freeformType = lib.types.attrs;
      options = {
        enabled = lib.mkOption { type = lib.types.nullOr lib.types.bool; default = null; };
        maxRetries = lib.mkOption { type = lib.types.nullOr lib.types.ints.unsigned; default = null; };
        baseDelayMs = lib.mkOption { type = lib.types.nullOr lib.types.ints.unsigned; default = null; };
        maxAgentDelayMs = lib.mkOption { type = lib.types.nullOr lib.types.ints.unsigned; default = null; };
        provider = lib.mkOption {
          type = lib.types.nullOr (lib.types.submoduleWith {
            modules = [{
              freeformType = lib.types.attrs;
              options = {
                timeoutMs = lib.mkOption { type = lib.types.nullOr lib.types.ints.unsigned; default = null; };
                maxRetries = lib.mkOption { type = lib.types.nullOr lib.types.ints.unsigned; default = null; };
                maxRetryDelayMs = lib.mkOption { type = lib.types.nullOr lib.types.ints.unsigned; default = null; };
              };
            }];
          });
          default = null;
        };
      };
    }];
  };

  terminalType = lib.types.submoduleWith {
    modules = [{
      freeformType = lib.types.attrs;
      options = {
        showImages = lib.mkOption { type = lib.types.nullOr lib.types.bool; default = null; };
        imageWidthCells = lib.mkOption { type = lib.types.nullOr lib.types.ints.positive; default = null; };
        clearOnShrink = lib.mkOption { type = lib.types.nullOr lib.types.bool; default = null; };
        showTerminalProgress = lib.mkOption { type = lib.types.nullOr lib.types.bool; default = null; };
        hyperlinks = lib.mkOption { type = lib.types.nullOr (lib.types.either lib.types.bool (lib.types.enum [ "auto" ])); default = null; };
        images = lib.mkOption { type = lib.types.nullOr (lib.types.either (lib.types.enum [ "kitty" "iterm2" "auto" ]) lib.types.bool); default = null; };
        trueColor = lib.mkOption { type = lib.types.nullOr (lib.types.either lib.types.bool (lib.types.enum [ "auto" ])); default = null; };
      };
    }];
  };

  imagesType = lib.types.submoduleWith {
    modules = [{
      freeformType = lib.types.attrs;
      options = {
        autoResize = lib.mkOption { type = lib.types.nullOr lib.types.bool; default = null; };
        blockImages = lib.mkOption { type = lib.types.nullOr lib.types.bool; default = null; };
      };
    }];
  };

  markdownType = lib.types.submoduleWith {
    modules = [{
      freeformType = lib.types.attrs;
      options = {
        codeBlockIndent = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
        mermaid = lib.mkOption { type = lib.types.nullOr (lib.types.enum [ "off" "final" "streaming" ]); default = null; };
      };
    }];
  };

  warningsType = lib.types.submoduleWith {
    modules = [{
      freeformType = lib.types.attrs;
      options = {
        anthropicExtraUsage = lib.mkOption { type = lib.types.nullOr lib.types.bool; default = null; };
      };
    }];
  };

  thinkingBudgetsType = lib.types.submoduleWith {
    modules = [{
      freeformType = lib.types.attrs;
      options = {
        minimal = lib.mkOption { type = lib.types.nullOr lib.types.ints.positive; default = null; };
        low = lib.mkOption { type = lib.types.nullOr lib.types.ints.positive; default = null; };
        medium = lib.mkOption { type = lib.types.nullOr lib.types.ints.positive; default = null; };
        high = lib.mkOption { type = lib.types.nullOr lib.types.ints.positive; default = null; };
      };
    }];
  };

  # Assembled settings JSON. Null (and empty-list where pi treats empty as
  # "unset") fields are stripped so pi sees absent rather than `null`.
  settingsBase = {
    defaultProvider = cfg.provider;
    defaultModel = cfg.model;
    defaultThinkingLevel = cfg.defaultThinkingLevel;
    modelThinkingLevels = if cfg.modelThinkingLevels == { } then null else cfg.modelThinkingLevels;
    transport = cfg.transport;
    theme = cfg.theme;
    packages = map packageSourceToJSON cfg.packages;
    extensions = if cfg.extensions == [] then null else cfg.extensions;
    skills = if cfg.skills == [] then null else cfg.skills;
    prompts = if cfg.prompts == [] then null else cfg.prompts;
    themes = if cfg.themes == [] then null else cfg.themes;
    steeringMode = cfg.steeringMode;
    followUpMode = cfg.followUpMode;
    compaction = cfg.compaction;
    branchSummary = cfg.branchSummary;
    retry = cfg.retry;
    hideThinkingBlock = cfg.hideThinkingBlock;
    showCacheMissNotices = cfg.showCacheMissNotices;
    externalEditor = cfg.externalEditor;
    shellPath = cfg.shellPath;
    quietStartup = cfg.quietStartup;
    defaultProjectTrust = cfg.defaultProjectTrust;
    shellCommandPrefix = cfg.shellCommandPrefix;
    npmCommand = if cfg.npmCommand == [] then null else cfg.npmCommand;
    collapseChangelog = cfg.collapseChangelog;
    enableInstallTelemetry = cfg.enableInstallTelemetry;
    enableAnalytics = cfg.enableAnalytics;
    trackingId = cfg.trackingId;
    lastChangelogVersion = cfg.lastChangelogVersion;
    enableSkillCommands = cfg.enableSkillCommands;
    terminal = cfg.terminal;
    images = cfg.images;
    enabledModels = if cfg.enabledModels == [] then null else cfg.enabledModels;
    defaultTools = if cfg.defaultTools == [] then null else cfg.defaultTools;
    doubleEscapeAction = cfg.doubleEscapeAction;
    treeFilterMode = cfg.treeFilterMode;
    thinkingBudgets = cfg.thinkingBudgets;
    editorPaddingX = cfg.editorPaddingX;
    outputPad = cfg.outputPad;
    autocompleteMaxVisible = cfg.autocompleteMaxVisible;
    showHardwareCursor = cfg.showHardwareCursor;
    markdown = cfg.markdown;
    warnings = cfg.warnings;
    sessionDir = cfg.sessionDir;
    httpProxy = cfg.httpProxy;
    httpIdleTimeoutMs = cfg.httpIdleTimeoutMs;
    cacheWarming = cfg.cacheWarming;
    websocketConnectTimeoutMs = cfg.websocketConnectTimeoutMs;
    tuiMode = cfg.tuiMode;
    fullscreenExitOutput = cfg.fullscreenExitOutput;
    fullscreenScrollbar = cfg.fullscreenScrollbar;
    fullscreenCopyOnSelect = cfg.fullscreenCopyOnSelect;
  } // cfg.settings;

  settingsJson = builtins.toJSON (stripNulls settingsBase);

  npmEnv = "NPM_CONFIG_PREFIX=$HOME/.pi/npm PATH=${cfg.nodejs}/bin:$PATH";

  # Settings script depends on mutableSettings
  settingsScript = if cfg.mutableSettings then ''
    if [[ ! -f "$settings_file" ]]; then
      mkdir -p "$(dirname "$settings_file")"
      echo '${settingsJson}' > "$settings_file"
    fi
  '' else ''
    mkdir -p "$(dirname "$settings_file")"
    echo '${settingsJson}' > "$settings_file"
  '';

  # Wrapper pre-launch hook
  preLaunchScript = lib.optionalString (cfg.preLaunchHook != "") ''
    ${cfg.preLaunchHook}
  '';

  piWrapper = pkgs.writeShellScriptBin "pi" ''
    # npm on PATH for extension management (pi install)
    export NPM_CONFIG_PREFIX="$HOME/.pi/npm"
    export PATH="${cfg.nodejs}/bin:$PATH"

    settings_file="$HOME/.pi/agent/settings.json"

    ${settingsScript}
    ${preLaunchScript}

    exec ${cfg.package}/bin/pi "$@"
  '';
in
{
  options.programs.pi = {
    enable = lib.mkEnableOption "pi coding agent";

    package = lib.mkOption {
      type = lib.types.package;
      description = "The pi package to use";
    };

    nodejs = lib.mkOption {
      type = lib.types.package;
      default = pkgs.nodejs;
      description = "Node.js package for extension management (encapsulated, not on global PATH)";
    };

    provider = lib.mkOption {
      type = lib.types.either (lib.types.enum builtinProviders) lib.types.str;
      default = "openrouter";
      description = "Default AI provider";
    };

    model = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Default model identifier";
    };

    theme = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Default theme name (pi built-in: dark/light, or from installed theme packages). Null uses pi's auto-detection. Manageable at runtime via /settings.";
    };

    auth = lib.mkOption {
      type = lib.types.attrsOf authEntryType;
      default = { };
      description = "Per-provider authentication credentials. Unknown fields pass through verbatim (e.g. OAuth refresh/access/expires).";
    };

    customProviders = lib.mkOption {
      type = lib.types.attrsOf providerType;
      default = { };
      description = "Custom provider definitions (written to models.json). Unknown fields pass through verbatim (e.g. headers, compat, modelOverrides).";
    };

    packages = lib.mkOption {
      type = lib.types.listOf packageSourceType;
      default = [];
      example = lib.literalExpression ''
        [
          "npm:some-pi-pack"
          { source = "git:https://github.com/user/repo"; skills = [ "review" ]; }
        ]
      '';
      description = ''
        Package sources (npm:... or git:...). Each entry is either a bare
        specifier string, or an object with a `source` plus optional
        `autoload` and `extensions` / `skills` / `prompts` / `themes` filters
        that restrict which resources are loaded from that package.
      '';
    };

    extensions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Local extension file paths or directories.";
    };

    skills = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Local skill file paths or directories.";
    };

    prompts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Local prompt template paths or directories.";
    };

    themes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Local theme file paths or directories.";
    };

    defaultThinkingLevel = lib.mkOption {
      type = lib.types.nullOr thinkingLevelType;
      default = null;
      description = "Default thinking budget level. Null leaves pi's runtime default.";
    };

    modelThinkingLevels = lib.mkOption {
      type = lib.types.attrsOf thinkingLevelType;
      default = { };
      description = "Per-model thinking level, keyed by \"provider/modelId\".";
    };

    steeringMode = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum [ "all" "one-at-a-time" ]);
      default = null;
      description = "How queued messages are applied. Null leaves pi's runtime default (`one-at-a-time`).";
    };

    followUpMode = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum [ "all" "one-at-a-time" ]);
      default = null;
      description = "How follow-up messages are applied. Null leaves pi's runtime default (`one-at-a-time`).";
    };

    compaction = lib.mkOption {
      type = lib.types.nullOr compactionType;
      default = null;
      description = "Context compaction settings (enabled, reserveTokens, keepRecentTokens, modelOverrides).";
    };

    branchSummary = lib.mkOption {
      type = lib.types.nullOr branchSummaryType;
      default = null;
      description = "Branch summary settings (reserveTokens, skipPrompt).";
    };

    retry = lib.mkOption {
      type = lib.types.nullOr retryType;
      default = null;
      description = "Retry settings (enabled, maxRetries, baseDelayMs, maxAgentDelayMs, provider.timeoutMs/maxRetries/maxRetryDelayMs).";
    };

    hideThinkingBlock = lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
      description = "Hide thinking blocks in the transcript.";
    };

    showCacheMissNotices = lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
      description = "Show cache miss notices.";
    };

    externalEditor = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Editor command for Ctrl+G. Null leaves pi's $VISUAL/$EDITOR detection.";
    };

    shellPath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Shell used by the bash tool. Null leaves pi's platform default.";
    };

    quietStartup = lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
      description = "Suppress startup banner.";
    };

    defaultProjectTrust = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum [ "ask" "always" "never" ]);
      default = null;
      description = "Trust policy for project dirs (global-only). Null leaves pi's runtime default (`ask`).";
    };

    shellCommandPrefix = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Prefix prepended to every bash command.";
    };

    npmCommand = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "npm command as argv. Empty leaves pi's runtime default (`npm`).";
    };

    collapseChangelog = lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
      description = "Collapse changelog entries in the changelog view.";
    };

    enableInstallTelemetry = lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
      description = "Send anonymous install telemetry.";
    };

    enableAnalytics = lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
      description = "Send anonymous usage analytics.";
    };

    trackingId = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Analytics tracking id. pi generates one at runtime; set only to pin it.";
    };

    lastChangelogVersion = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Internal: last viewed changelog version. pi manages this at runtime; set only to pin it.";
    };

    enableSkillCommands = lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
      description = "Expose skills as slash commands. Null leaves pi's runtime default (enabled).";
    };

    terminal = lib.mkOption {
      type = lib.types.nullOr terminalType;
      default = null;
      description = "Terminal rendering settings (showImages, imageWidthCells, clearOnShrink, showTerminalProgress, hyperlinks, images, trueColor).";
    };

    images = lib.mkOption {
      type = lib.types.nullOr imagesType;
      default = null;
      description = "Image input settings (autoResize, blockImages).";
    };

    enabledModels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Model cycling patterns (same format as --models). Empty leaves pi's runtime default (all available models).";
    };

    defaultTools = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Enabled tool ids. Empty leaves pi's full built-in set.";
    };

    doubleEscapeAction = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum [ "fork" "tree" "none" ]);
      default = null;
      description = "Action for double-Escape. Null leaves pi's runtime default (`tree`).";
    };

    treeFilterMode = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum [ "default" "no-tools" "user-only" "labeled-only" "all" ]);
      default = null;
      description = "Which messages the tree view shows. Null leaves pi's runtime default.";
    };

    thinkingBudgets = lib.mkOption {
      type = lib.types.nullOr thinkingBudgetsType;
      default = null;
      description = "Token budgets for thinking levels (minimal, low, medium, high).";
    };

    editorPaddingX = lib.mkOption {
      type = lib.types.nullOr (lib.types.ints.between 0 3);
      default = null;
      description = "Horizontal padding of the editor (0-3).";
    };

    outputPad = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum [ 0 1 ]);
      default = null;
      description = "Blank line after output blocks.";
    };

    autocompleteMaxVisible = lib.mkOption {
      type = lib.types.nullOr (lib.types.ints.between 3 20);
      default = null;
      description = "Max visible autocomplete rows (3-20).";
    };

    showHardwareCursor = lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
      description = "Use the hardware cursor.";
    };

    markdown = lib.mkOption {
      type = lib.types.nullOr markdownType;
      default = null;
      description = "Markdown rendering settings (codeBlockIndent, mermaid).";
    };

    warnings = lib.mkOption {
      type = lib.types.nullOr warningsType;
      default = null;
      description = "Warning toggles (anthropicExtraUsage).";
    };

    sessionDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Session storage dir. Overridden by PI_CODING_AGENT_SESSION_DIR / --session-dir.";
    };

    httpProxy = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Proxy URL fed to HTTP_PROXY/HTTPS_PROXY (global-only).";
    };

    httpIdleTimeoutMs = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.unsigned;
      default = null;
      description = "HTTP idle timeout in ms; 0 disables. Null leaves pi's runtime default (300000).";
    };

    cacheWarming = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum [ "off" "streaming" "idle" ]);
      default = null;
      description = "Prompt cache warming mode (global-only). Null leaves pi's runtime default (`streaming`).";
    };

    websocketConnectTimeoutMs = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.unsigned;
      default = null;
      description = "WebSocket connect timeout in ms; 0 disables. Null leaves pi's runtime default (15000).";
    };

    tuiMode = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum [ "regular" "fullscreen" ]);
      default = null;
      description = "TUI layout. Null leaves pi's runtime default (`regular`).";
    };

    fullscreenExitOutput = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum [ "transcript" "resume-hint" ]);
      default = null;
      description = "What fullscreen mode prints on exit. Null leaves pi's runtime default (`transcript`).";
    };

    fullscreenScrollbar = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum [ "hidden" "auto" "always" ]);
      default = null;
      description = "Fullscreen scrollbar mode. Null leaves pi's runtime default (`auto`).";
    };

    fullscreenCopyOnSelect = lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
      description = "Copy selection to clipboard immediately in fullscreen mode.";
    };

    transport = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum [ "auto" "sse" "websocket" "websocket-cached" ]);
      default = null;
      description = "HTTP streaming transport. Null leaves pi's runtime default (`auto`).";
    };

    mutableSettings = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Seed settings once (true) vs overwrite every launch (false)";
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = "Extra settings merged into settings.json";
    };

    preLaunchHook = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Shell commands to run before launching pi (after settings.json is written). Has access to $settings_file. Useful for theme sync or env-based overrides.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ piWrapper ];

    home.shellAliases = lib.optionalAttrs cfg.mutableSettings {
      "pi-reset-config" = "rm -f $HOME/.pi/agent/settings.json && echo 'Settings reset. Next pi launch will re-seed from nix config.'";
    };

    home.file = {
      ".pi/agent/auth.json" = lib.mkIf (cfg.auth != { }) {
        text = builtins.toJSON (lib.mapAttrs (_: authEntryToJSON) cfg.auth);
      };
      ".pi/agent/models.json" = lib.mkIf (cfg.customProviders != { }) {
        text = builtins.toJSON (stripNulls { providers = cfg.customProviders; });
      };
    };
  };
}
