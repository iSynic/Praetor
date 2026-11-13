param(
    [Parameter(Mandatory=$true)][string]$Output,
    [string]$Godot = 'Godot_v4.7.1-stable_win64_console.exe',
    [string]$Runtime = ''
)
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$outputPath = [IO.Path]::GetFullPath($Output, $taskRoot)
$artifactRoot = Join-Path $taskRoot 'artifacts'
if (-not $outputPath.StartsWith($artifactRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Build output must be a new directory under this workspace artifacts folder.'
}
if (Test-Path -LiteralPath $outputPath) { throw 'Build output already exists.' }
$ancestor = [IO.DirectoryInfo]::new((Split-Path $outputPath -Parent))
while ($null -ne $ancestor) {
    if ($ancestor.Exists -and ($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Build outputs cannot traverse a link or junction.' }
    $ancestor = $ancestor.Parent
}
$targetDir = if ($env:CARGO_TARGET_DIR) { [IO.Path]::GetFullPath($env:CARGO_TARGET_DIR) } else { Join-Path $taskRoot 'target' }
Push-Location $taskRoot
try {
    cargo build --workspace --release
    if ($LASTEXITCODE -ne 0) { throw 'Rust release build failed.' }
    New-Item -ItemType Directory -Path $outputPath | Out-Null
    $executable = Join-Path $outputPath 'Praetor.exe'
    & $Godot --headless --path (Join-Path $taskRoot 'godot') --export-release 'Windows Desktop' $executable
    if ($LASTEXITCODE -ne 0) { throw 'Godot export failed.' }
    foreach ($binary in @('centurions-adapter.exe','centurions-editor.exe')) {
        Copy-Item -LiteralPath (Join-Path $targetDir "release\$binary") -Destination $outputPath
    }
    if ($Runtime -ne '') {
        # Play needs the replay tool and the application beside the editor; they are copied from a runtime build, never from the installation.
        $runtimeRoot = [IO.Path]::GetFullPath($Runtime, $taskRoot)
        Copy-Item -LiteralPath (Join-Path $runtimeRoot 'centurions-tools.exe') -Destination $outputPath
        Copy-Item -LiteralPath (Join-Path $runtimeRoot 'centurions-desktop.exe') -Destination (Join-Path $outputPath 'The New Centurions.exe')
    }
    foreach ($file in @('LICENSE','NOTICE','README.md')) {
        Copy-Item -LiteralPath (Join-Path $taskRoot $file) -Destination $outputPath
    }
    Copy-Item -LiteralPath (Join-Path $taskRoot 'docs') -Destination (Join-Path $outputPath 'docs') -Recurse
    & $Godot --headless --path (Join-Path $taskRoot 'godot') --script res://tools/export_licenses.gd -- $outputPath
    if ($LASTEXITCODE -ne 0) { throw 'Engine license export failed.' }
    $receipt = [ordered]@{kind='local-centurions-editor-build';published=$true;originalAssetsIncluded=$false;files=@{}}
    $receipt.source_files = @{}
    git ls-files --cached --others --exclude-standard | ForEach-Object {
        if (Test-Path -LiteralPath $_ -PathType Leaf) {
            $receipt.source_files[$_] = (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    Get-ChildItem -LiteralPath $outputPath -File -Recurse | ForEach-Object {
        $relative = [IO.Path]::GetRelativePath($outputPath,$_.FullName).Replace('\','/')
        $receipt.files[$relative] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $receipt | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $outputPath 'build.json') -Encoding utf8
    Write-Output $executable
} finally { Pop-Location }
