# INTERNAL BUILD TOOL. Do not edit for new mods or version changes.
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Generate', 'Debug', 'Release')]
    [string]$Action,

    [Parameter(Mandatory = $true)]
    [string]$ProjectPath,

    [string]$GeneratedPath,
    [string]$AssemblyPath
)

$ErrorActionPreference = 'Stop'
$ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
$ConfigPath = Join-Path $ProjectPath 'ModConfig.props'
$ManifestPath = Join-Path $ProjectPath 'manifest.json'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

if (!(Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "Missing configuration: $ConfigPath"
}
[xml]$ConfigXml = [IO.File]::ReadAllText($ConfigPath)
$Settings = $ConfigXml.Project.PropertyGroup
$ModName = [string]$Settings.ModName
$Version = [string]$Settings.ModVersion
$Guid = [string]$Settings.ModGuid
$Description = [string]$Settings.ModDescription
$Website = [string]$Settings.ModWebsite
$Dependencies = @(([string]$Settings.ModDependencies -split '[;\r\n]+') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$DeployPath = [string]$Settings.ModDeployPath

if ($ModName -cnotmatch '^[A-Za-z][A-Za-z0-9_]*$') {
    throw 'ModName must begin with a letter and contain only letters, digits, and underscores.'
}
if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    throw 'ModVersion must have the format X.Y.Z.'
}
if ([string]::IsNullOrWhiteSpace($Guid)) {
    throw 'ModGuid must not be empty.'
}
function Write-Utf8([string]$FilePath, [string]$Content) {
    [IO.File]::WriteAllText($FilePath, $Content, $Utf8NoBom)
}

function Get-CurrentManifest {
    if (Test-Path -LiteralPath $ManifestPath -PathType Leaf) {
        $Manifest = [IO.File]::ReadAllText($ManifestPath) | ConvertFrom-Json
    }
    else {
        $Manifest = [PSCustomObject]@{}
    }

    $Values = @{
        name           = $ModName
        version_number = $Version
        description    = $Description
        website_url    = $Website
        dependencies   = @($Dependencies)
    }

    foreach ($Key in $Values.Keys) {
        if ($Manifest.PSObject.Properties.Name -contains $Key) {
            $Manifest.$Key = $Values[$Key]
        }
        else {
            $Manifest | Add-Member -NotePropertyName $Key -NotePropertyValue $Values[$Key]
        }
    }
    return $Manifest
}

function Write-Manifest([string]$Destination) {
    $Manifest = Get-CurrentManifest
    Write-Utf8 $Destination (($Manifest | ConvertTo-Json -Depth 10) + [Environment]::NewLine)
}

if ($Action -eq 'Generate') {
    if ([string]::IsNullOrWhiteSpace($GeneratedPath)) {
        throw 'Generate requires -GeneratedPath.'
    }
    # Generate constant strings suitable for use in a BepInPlugin attribute.
    function CSharp-Literal([string]$Value) {
        return '"' + $Value.Replace('\', '\\').Replace('"', '\"').Replace("`r", '\r').Replace("`n", '\n') + '"'
    }

    $GeneratedCode = @"
// Generated automatically from ModConfig.props. Do not edit.
namespace $ModName
{
    internal static class ModIdentity
    {
        public const string Guid = $(CSharp-Literal $Guid);
        public const string Name = $(CSharp-Literal $ModName);
        public const string Version = $(CSharp-Literal $Version);
    }
}
"@

    # Compile a generated copy of Plugin.cs with the configured namespace.
    # The editable Plugin.cs is never modified during builds.
    $PluginSource = Join-Path $ProjectPath 'Plugin.cs'
    if (!(Test-Path -LiteralPath $PluginSource -PathType Leaf)) {
        throw "Missing plugin source: $PluginSource"
    }
    $PluginText = [IO.File]::ReadAllText($PluginSource)
    $NamespacePattern = '(?m)^(\s*namespace\s+)[A-Za-z_][A-Za-z_0-9.]*'
    if (!([regex]::IsMatch($PluginText, $NamespacePattern))) {
        throw 'Plugin.cs must contain a namespace declaration.'
    }
    $PluginText = [regex]::new($NamespacePattern).Replace($PluginText, {
            param($match)
            return $match.Groups[1].Value + $ModName
        }, 1)
    $GeneratedDirectory = Split-Path -Parent $GeneratedPath
    $GeneratedPlugin = Join-Path $GeneratedDirectory 'Plugin.g.cs'
    New-Item -ItemType Directory -Path $GeneratedDirectory -Force | Out-Null
    Write-Utf8 $GeneratedPlugin ($PluginText + [Environment]::NewLine)
    New-Item -ItemType Directory -Path $GeneratedDirectory -Force | Out-Null
    Write-Utf8 $GeneratedPath ($GeneratedCode + [Environment]::NewLine)
    # The repository manifest also stays synchronized; dependency list is preserved.
    Write-Manifest $ManifestPath
    return
}

if ([string]::IsNullOrWhiteSpace($AssemblyPath) -or
    !(Test-Path -LiteralPath $AssemblyPath -PathType Leaf)) {
    throw "Compiled DLL not found: $AssemblyPath"
}

$AssemblyName = [IO.Path]::GetFileNameWithoutExtension($AssemblyPath)
$OutputPath = Split-Path -Parent $AssemblyPath

if ($Action -eq 'Debug') {
    if ([string]::IsNullOrWhiteSpace($DeployPath)) {
        throw 'Set ModDeployPath in ModConfig.props.'
    }
    $PluginFolder = Join-Path $DeployPath $AssemblyName
    New-Item -ItemType Directory -Path $PluginFolder -Force | Out-Null
    Copy-Item -LiteralPath $AssemblyPath -Destination $PluginFolder -Force

    foreach ($Symbol in @("$AssemblyName.pdb", "$AssemblyName.dll.mdb")) {
        $SymbolPath = Join-Path $OutputPath $Symbol
        if (Test-Path -LiteralPath $SymbolPath -PathType Leaf) {
            Copy-Item -LiteralPath $SymbolPath -Destination $PluginFolder -Force
        }
    }
    Write-Manifest (Join-Path $PluginFolder 'manifest.json')
    Write-Host "Debug deployed: $PluginFolder"
    return
}

# Release ZIP. Only source assets are packaged, not local files or build dependencies.
foreach ($File in @('README.md', 'icon.png')) {
    if (!(Test-Path -LiteralPath (Join-Path $ProjectPath $File) -PathType Leaf)) {
        throw "Missing package file: $File"
    }
}

$PackagePath = Join-Path $ProjectPath 'Package'
$PluginsPath = Join-Path $PackagePath 'plugins'
$ReleasesPath = Join-Path (Split-Path -Parent $ProjectPath) 'Releases'

if (Test-Path -LiteralPath $PackagePath) {
    Remove-Item -LiteralPath $PackagePath -Recurse -Force
}
New-Item -ItemType Directory -Path $PluginsPath -Force | Out-Null
Copy-Item -LiteralPath $AssemblyPath -Destination $PluginsPath -Force

foreach ($File in @('README.md', 'CHANGELOG.md')) {
    $Source = Join-Path $ProjectPath $File
    if (Test-Path -LiteralPath $Source -PathType Leaf) {
        Write-Utf8 (Join-Path $PackagePath $File) ([IO.File]::ReadAllText($Source))
    }
}
Copy-Item -LiteralPath (Join-Path $ProjectPath 'icon.png') -Destination $PackagePath -Force
Write-Manifest (Join-Path $PackagePath 'manifest.json')

New-Item -ItemType Directory -Path $ReleasesPath -Force | Out-Null
$ZipPath = Join-Path $ReleasesPath "$ModName-$Version.zip"
Compress-Archive -Path (Join-Path $PackagePath '*') -DestinationPath $ZipPath -Force
Write-Host "Thunderstore ZIP: $ZipPath"
