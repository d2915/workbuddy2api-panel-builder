param(
    [Parameter(Mandatory=$true)]
    [string]$GitHubUser,
    [string]$RepoName = "workbuddy2api-panel-builder"
)

$ErrorActionPreference = "Stop"

$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $dir

$owner = $GitHubUser.ToLower()

# 1) write GitHub owner into nas/docker-compose.yml
$nasCompose = Join-Path $dir "nas\docker-compose.yml"
$content = [System.IO.File]::ReadAllText($nasCompose)
$content = $content -replace "ghcr\.io/OWNER/", "ghcr.io/$owner/"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($nasCompose, $content, $utf8NoBom)
Write-Host "[OK] nas/docker-compose.yml  ->  ghcr.io/$owner/workbuddy2api-panel:latest" -ForegroundColor Green

# 2) init git repo
if (-not (Test-Path ".git")) {
    git init | Out-Null
    Write-Host "[OK] git init"
}

# 3) commit
git add -A
$status = git status --porcelain
if ($status) {
    git -c user.name="builder" -c user.email="builder@local" commit -m "chore: 初始化 GHCR 构建流程" | Out-Null
    Write-Host "[OK] commit"
} else {
    Write-Host "[--] 无改动需要提交"
}

git branch -M main

# 4) push
$remote = "https://github.com/$GitHubUser/$RepoName.git"
$remotes = @(git remote)
if ($remotes -contains "origin") {
    git remote set-url origin $remote
} else {
    git remote add origin $remote
}
Write-Host "[..] pushing to $remote"
git push -u origin main
Write-Host "[OK] push 完成" -ForegroundColor Green
Write-Host ""
Write-Host "下一步：打开 https://github.com/$GitHubUser/$RepoName/actions 看构建是否变绿"
