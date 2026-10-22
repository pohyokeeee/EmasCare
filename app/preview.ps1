param(
    [ValidateSet('preview', 'build', 'serve', 'check', 'dev')]
    [string]$Mode = 'preview',
    [ValidateRange(1024, 65535)]
    [int]$Port = 8090,
    [string]$FlutterRoot = ''
)
$ErrorActionPreference = 'Stop'
Push-Location -LiteralPath $PSScriptRoot
try {
    if ($Mode -ne 'serve') {
        if (-not $FlutterRoot) { $FlutterRoot = $env:FLUTTER_ROOT }
        if (-not $FlutterRoot) {
            $flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
            if ($flutterCommand) { $FlutterRoot = Split-Path -Path (Split-Path -Path $flutterCommand.Source -Parent) -Parent }
        }
        if (-not $FlutterRoot) {
            $localSdk = Join-Path -Path $env:USERPROFILE -ChildPath 'Documents/VS CODE/flutter'
            if (Test-Path -LiteralPath $localSdk) { $FlutterRoot = $localSdk }
        }
        if (-not $FlutterRoot) { throw 'Flutter SDK not found. Pass -FlutterRoot with your Flutter folder.' }
        $dartExecutable = Join-Path -Path $FlutterRoot -ChildPath 'bin/cache/dart-sdk/bin/dart.exe'
        $flutterSnapshot = Join-Path -Path $FlutterRoot -ChildPath 'bin/cache/flutter_tools.snapshot'
        if (-not (Test-Path -LiteralPath $flutterSnapshot)) { throw 'Initialize the Flutter SDK with flutter doctor first.' }
        function Invoke-LocalFlutter {
            & $dartExecutable $flutterSnapshot --suppress-analytics --no-version-check @args
            if ($LASTEXITCODE -ne 0) { throw "Flutter command failed (exit $LASTEXITCODE)." }
        }
        # Use the SDK entry point directly: this machine's flutter.bat launcher stalls.
        Invoke-LocalFlutter pub get
        if ($Mode -eq 'check') {
            Invoke-LocalFlutter analyze --no-pub
            Invoke-LocalFlutter test --no-pub
            & node 'tool/browser_bridge.test.cjs'
            if ($LASTEXITCODE -ne 0) { throw 'Browser bridge tests failed.' }
            & node --test 'tool/firebase_bootstrap.test.cjs'
            if ($LASTEXITCODE -ne 0) { throw 'Firebase initialization tests failed.' }
            & node --test 'tool/voice_bridge.test.cjs'
            if ($LASTEXITCODE -ne 0) { throw 'Voice booking bridge tests failed.' }
        } elseif ($Mode -eq 'dev') {
            Invoke-LocalFlutter run -d web-server --web-hostname 127.0.0.1 --web-port $Port
        } else {
            Invoke-LocalFlutter build web --release --no-pub --no-web-resources-cdn --no-wasm-dry-run --pwa-strategy=none
        }
    }
    if ($Mode -in @('preview', 'serve')) {
        & node 'tool/serve.cjs' $Port
        if ($LASTEXITCODE -ne 0) { throw 'Preview server failed.' }
    }
} finally { Pop-Location }
