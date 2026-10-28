# audit.ps1 — 对 npm 上的 DSH 插件做静态安全审查（不安装进任何 profile）
#
# 用法:
#   powershell -NoProfile -ExecutionPolicy Bypass -File audit.ps1 -Spec "包名@版本"
#   powershell ... -File audit.ps1 -Spec "dsh-open-market" -Registry "https://registry.npmjs.org"
#
# 产物: 元数据 / 文件清单 / 安装钩子 / 危险模式命中(文件:行号) / 出站域名 / 依赖 / 结论提示
# 说明: 只做静态检查。A 级结论仍然不是安全担保。

param(
    [Parameter(Mandatory = $true)][string]$Spec,
    [string]$WorkDir = (Join-Path $env:TEMP 'dsh-audit'),
    [string]$Registry,
    [int]$MaxHitsPerPattern = 6
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$OutputEncoding = [Text.Encoding]::UTF8

$regArg = @()
if ($Registry) { $regArg = @('--registry', $Registry) }

function Section($title) { Write-Output ""; Write-Output ("=" * 70); Write-Output "== $title"; Write-Output ("=" * 70) }

# ---------- 1. 元数据 ----------
Section "1. METADATA  ($Spec)"
Write-Output "npm registry : $((& npm config get registry) -join '')"

$metaJson = & npm view $Spec --json @regArg 2>$null
if (-not $metaJson) { throw "npm view 失败：包不存在或网络不可达 —— $Spec" }
$meta = $metaJson | ConvertFrom-Json

$name = $meta.name
$scope = if ($name -match '^@([^/]+)/') { $Matches[1] } else { $null }
$org = if ($meta.repository.url -match 'github\.com[/:]([^/]+)/') { $Matches[1] } else { $null }
$maint = (@($meta.maintainers | ForEach-Object { if ($_ -is [string]) { $_ } elseif ($_.name) { $_.name } elseif ($_.username) { $_.username } }) -join ', ')

Write-Output "name        : $name"
Write-Output "version     : $($meta.version)"
Write-Output "description : $($meta.description)"
Write-Output "license     : $($meta.license)"
Write-Output "repository  : $($meta.repository.url)"
Write-Output "maintainers : $maint"
Write-Output "tarball     : $($meta.dist.tarball)   host: $(([uri]$meta.dist.tarball).Host)"
Write-Output "shasum      : $($meta.dist.shasum)"
Write-Output "integrity   : $($meta.dist.integrity)"
if ($meta.engines.dsh) { Write-Output "engines.dsh : $($meta.engines.dsh)" }
else { Write-Output "engines.dsh : (未声明 —— 安装时不做 DSH 版本检查)" }
if ($meta.engines.node) { Write-Output "engines.node: $($meta.engines.node)" }

$t = & npm view $Spec time --json @regArg 2>$null | ConvertFrom-Json
if ($t) {
    Write-Output "first publish : $($t.created)"
    Write-Output "last publish  : $($t.modified)"
    $versions = @($t.PSObject.Properties.Name | Where-Object { $_ -notin @('created', 'modified') })
    Write-Output "version count : $($versions.Count)   latest: $(($versions | Select-Object -Last 4) -join ', ')"
}

if ($scope -and $org) {
    if ($scope -ne $org) { Write-Output "[!] scope @$scope 与仓库组织 '$org' 不一致，确认是否同一维护者" }
    else { Write-Output "ok  scope @$scope 与仓库组织一致" }
}

# ---------- 2. 取包，不安装 ----------
Section "2. EXTRACT  (npm pack，不写入任何 profile)"
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$dir = Join-Path $WorkDir "$($name -replace '[/@]', '_')-$stamp"
New-Item -ItemType Directory -Force -Path $dir | Out-Null

$packOut = & npm pack $Spec --pack-destination $dir --json @regArg 2>$null | ConvertFrom-Json
$tgz = Join-Path $dir $packOut.filename
if (-not (Test-Path $tgz)) { throw "npm pack 未产出 tarball：$tgz" }
Write-Output "tarball : $tgz"
Write-Output "size    : $([math]::Round((Get-Item $tgz).Length / 1KB, 1)) KB   files: $($packOut.entryCount)   unpacked: $([math]::Round($packOut.unpackedSize / 1KB, 1)) KB"

$extract = Join-Path $dir 'x'
New-Item -ItemType Directory -Force -Path $extract | Out-Null
& tar -xzf $tgz -C $extract
$root = Join-Path $extract 'package'

# ---------- 3. 文件清单 ----------
Section "3. FILES"
$files = Get-ChildItem $root -Recurse -File | Where-Object { $_.FullName -notmatch '\\node_modules\\' }
Write-Output "file count : $($files.Count)"
Write-Output "ext map    : $((($files | Group-Object Extension | Sort-Object Count -Descending | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join '  '))"
$hasSrc = Test-Path (Join-Path $root 'src')
$hasDist = (Test-Path (Join-Path $root 'lib')) -or (Test-Path (Join-Path $root 'dist'))
if ($hasSrc) { Write-Output "source     : src/ 存在（可读源码）" }
elseif ($hasDist) { Write-Output "[!] source : 没有 src/，只有构建产物 —— 静态审查只能覆盖编译后代码" }
else { Write-Output "[!] source : 未发现 src/lib/dist，检查包结构" }

# ---------- 4. 安装钩子 ----------
Section "4. INSTALL HOOKS"
$pkg = Get-Content (Join-Path $root 'package.json') -Raw | ConvertFrom-Json
$scripts = $pkg.scripts
$hooks = @()
if ($scripts) {
    foreach ($p in $scripts.PSObject.Properties) { Write-Output ("  {0,-14} {1}" -f $p.Name, $p.Value) }
    $hooks = @($scripts.PSObject.Properties.Name | Where-Object { $_ -in @('preinstall', 'install', 'postinstall', 'prepare', 'prepublish') })
    if ($hooks.Count -gt 0) { Write-Output "[!] 生命周期脚本：$($hooks -join ', ') —— 安装即执行，逐行看" }
    else { Write-Output "ok 无 install/postinstall 钩子" }
}
else { Write-Output "ok 没有 scripts 字段" }

# ---------- 5. 静态扫描 ----------
Section "5. STATIC SCAN"
$patterns = @(
    @{ Label = 'child_process/exec'; Regex = 'child_process|execSync|spawnSync|\bexec\(|\bspawn\(' },
    @{ Label = 'eval/vm/Function'; Regex = '\beval\(|new Function|vm\.(run|compile|createContext)' },
    @{ Label = 'dynamic import/require'; Regex = 'require\(\s*[^"''\s]|import\(\s*[^"''\s]' },
    @{ Label = 'process.env'; Regex = 'process\.env' },
    @{ Label = 'credential paths'; Regex = '\.dsh[\\/]|\.ssh|\.aws|credentials|id_rsa|\.netrc|Login Data|Cookies|keychain' },
    @{ Label = 'base64/atob'; Regex = 'Buffer\.from\([^)]*base64|atob\(' },
    @{ Label = 'network/upload'; Regex = 'fetch\(|axios|node-fetch|https?\.request|FormData|upload' }
)

$scanExt = @('.js', '.mjs', '.cjs', '.ts', '.json', '.yml', '.yaml')
$scanFiles = $files | Where-Object { $scanExt -contains $_.Extension.ToLower() } |
    Where-Object { $_.Name -notin @('package-lock.json', 'pnpm-lock.yaml') }

$hosts = New-Object System.Collections.Generic.HashSet[string]
$findings = @{}
foreach ($f in $scanFiles) {
    $lines = Get-Content -LiteralPath $f.FullName -ErrorAction SilentlyContinue
    if (-not $lines) { continue }
    $rel = $f.FullName.Substring($root.Length).TrimStart('\')
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line.Length -gt 400) {
            if (-not $findings.ContainsKey('压缩/混淆嫌疑')) { $findings['压缩/混淆嫌疑'] = @() }
            if ($findings['压缩/混淆嫌疑'].Count -lt $MaxHitsPerPattern) { $findings['压缩/混淆嫌疑'] += "${rel}:$($i+1): <$($line.Length) chars>" }
        }
        foreach ($p in $patterns) {
            if ($line -match $p.Regex) {
                if (-not $findings.ContainsKey($p.Label)) { $findings[$p.Label] = @() }
                if ($findings[$p.Label].Count -lt $MaxHitsPerPattern) {
                    $trim = if ($line.Trim().Length -gt 160) { $line.Trim().Substring(0, 160) + '…' } else { $line.Trim() }
                    $findings[$p.Label] += "${rel}:$($i+1): $trim"
                }
            }
        }
        foreach ($m in [regex]::Matches($line, 'https?://([a-zA-Z0-9\.\-]+)')) { [void]$hosts.Add($m.Groups[1].Value) }
    }
}

foreach ($k in $patterns.Label) {
    if ($findings.ContainsKey($k)) {
        Write-Output ""
        Write-Output "[$k] 至少 $($findings[$k].Count) 处:"
        $findings[$k] | ForEach-Object { Write-Output "  $_" }
    }
}
if ($findings.ContainsKey('压缩/混淆嫌疑')) {
    Write-Output ""
    Write-Output "[压缩/混淆嫌疑] 超长行:"
    $findings['压缩/混淆嫌疑'] | ForEach-Object { Write-Output "  $_" }
}

Write-Output ""
Write-Output "出站域名 ($($hosts.Count)):"
if ($hosts.Count -eq 0) { Write-Output "  (无)" } else { $hosts | Sort-Object | ForEach-Object { Write-Output "  $_" } }

# ---------- 6. 依赖 ----------
Section "6. DEPENDENCIES"
$deps = @()
if ($pkg.dependencies) { $deps += $pkg.dependencies.PSObject.Properties | ForEach-Object { "dep  $($_.Name)@$($_.Value)" } }
if ($pkg.peerDependencies) { $deps += $pkg.peerDependencies.PSObject.Properties | ForEach-Object { "peer $($_.Name)@$($_.Value)" } }
if ($deps.Count -eq 0) { Write-Output "  (无依赖)" } else { $deps | ForEach-Object { Write-Output "  $_" } }
Write-Output "count: $($deps.Count)"

# ---------- 7. 结论提示 ----------
Section "7. VERDICT HINT"
$flags = @()
if ($hooks.Count -gt 0) { $flags += "安装钩子" }
if ($findings.ContainsKey('eval/vm/Function')) { $flags += "eval/vm" }
if ($findings.ContainsKey('credential paths')) { $flags += "读取凭据路径" }
if ($findings.ContainsKey('压缩/混淆嫌疑')) { $flags += "疑似压缩/混淆" }
if (-not $hasSrc) { $flags += "无源码" }
if ($flags.Count -eq 0) {
    Write-Output "未发现明显红线。仍须人工复核第 5 节的网络与 env 使用，并确认发布者身份。"
} else {
    Write-Output ("需人工重点确认: " + ($flags -join ' / '))
}
Write-Output ""
Write-Output "解包目录: $root"
