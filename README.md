# 让 workbuddy2api-panel 自动更新

## 为什么之前 Watchtower 不生效

Watchtower 只做一件事：**去镜像仓库拉同名镜像**。它不看源码、不执行 `git pull`、不构建。

- `cli-proxy-api` 能自动更新，因为它是 `image: eceasy/cli-proxy-api:latest`（Docker Hub 远程镜像）。
- `workbuddy2api-panel` 不能，因为它是 `build: .`（NAS 本地构建的镜像 `workbuddy2api-panel-wb2api`）。这个镜像名在 Docker Hub 上不存在，Watchtower 每天去查都拉不到，只能跳过。

你的 watchtower 配置**没有写错**，`workbuddy2api-panel` 已经在它的更新列表里。缺的只是一个"可拉取的远程镜像"。

## 解决思路

```
上游 GitHub 发新版
   ↓  每天自动检查（GitHub Actions，云端）
云端编译 linux/amd64 镜像
   ↓  推送到 GHCR
NAS 上的 Watchtower（每天 04:00）
   ↓  拉取新镜像
自动替换 workbuddy2api-panel 容器
```

好处：NAS 不需要 Go、不需要 git、不需要开机你的电脑；Watchtower 配置一个字都不用改。

## 目录内容

```
ghcr-builder/
├─ .github/workflows/build.yml   云端构建脚本（上传到 GitHub）
├─ .upstream-baseline.json       上游部署文件基线（变更拦截用）
├─ nas/docker-compose.yml        NAS 上要替换的 compose
└─ README.md                     本文件
```

## 前置条件

- 一个 GitHub 账号（免费注册：https://github.com/signup）
- NAS 上能执行 docker 命令（你现在 root shell 就可以）

## 操作步骤

### 第 1 步：在 GitHub 建一个空仓库

1. 打开 https://github.com/new
2. Repository name 填：`workbuddy2api-panel-builder`
3. 选 **Public**（推荐，后面镜像拉取免登录；选 Private 也能用，但要多配一步）
4. **不要**勾选 Add a README / .gitignore / license
5. 点 Create repository

### 第 2 步：把本目录文件传上去

在 Windows 上打开 PowerShell：

```powershell
cd "D:\AI\安全工作区\2API\ghcr-builder"
git init
git add .
git commit -m "初始化构建流程"
git branch -M main
git remote add origin https://github.com/你的用户名/workbuddy2api-panel-builder.git
git push -u origin main
```

第一次推送会弹出 GitHub 登录窗口，按提示授权即可。

推送成功后，GitHub 仓库的 **Actions** 标签页会自动开始第一次构建。等它变绿（约 3-5 分钟）。

### 第 3 步：把镜像设为公开

构建完成后：

1. 打开 `https://github.com/你的用户名?tab=packages`
2. 点进 `workbuddy2api-panel`
3. 右侧 **Package settings** → 拉到底 **Danger Zone** → **Change visibility** → 选 **Public**

（不设为公开也行，但 NAS 上要 `docker login ghcr.io` 并给 Watchtower 配凭据，麻烦得多。）

### 第 4 步：NAS 上切换到远程镜像

SSH 到 NAS，或者直接在 DSM 的 root shell 里：

```bash
cd /volume1/docker/2API/workbuddy2api-panel

# 先备份现有 compose
cp docker-compose.yml docker-compose.yml.bak.$(date +%Y%m%d)

# 用新的 compose 替换（把 OWNER 换成你的 GitHub 用户名，全小写）
vi docker-compose.yml
```

把 `nas/docker-compose.yml` 的内容粘进去，注意替换 `OWNER`。

然后首次手动拉取并重建：

```bash
cd /volume1/docker/2API/workbuddy2api-panel

docker compose pull wb2api
docker compose up -d --force-recreate --no-build wb2api

# 确认容器起来了
docker compose ps
docker compose logs --tail=50 wb2api
```

浏览器打开 `http://192.168.5.2:7863/panel/` 确认面板正常。

### 第 5 步：确认 Watchtower 会管它

你的 `watchtower-cpa/docker-compose.yml` 里 `command` 列表已经包含 `workbuddy2api-panel`，**不用改**。

Watchtower 每天 04:00（`WATCHTOWER_SCHEDULE: "0 0 4 * * *"`）执行一次。GitHub Actions 每天 UTC 18:00（北京 02:00）构建，比它早 2 小时，时间对得上。

想立刻验证一次，可以手动跑：

```bash
docker exec watchtower-cpa /watchtower --run-once workbuddy2api-panel
```

如果镜像已是最新，它会提示无需更新；这本身就说明配置通了。

## 上游改了 Dockerfile / compose 怎么办

你选择了"上游变了就提示我确认"。这个逻辑已经写在 `build.yml` 里：

- 构建前会比对上游 `Dockerfile` 和 `docker-compose.yml` 的哈希
- 与 `.upstream-baseline.json` 里的基线不一致时 → **停止构建**，Actions 标红
- 日志里会打印新旧哈希

确认上游改动没问题后，把 `.upstream-baseline.json` 里的两个哈希改成日志中打印的"上游"值，提交推送即可放行。

想临时跳过检查强制构建：在 Actions 页面点 **Run workflow**，勾选 `force_build`。

## 注意

- `auths/`、`data/`、`config.json` 是宿主机挂载，重建容器不会丢。
- 不要执行 `docker system prune --volumes`。
- 旧的本地镜像 `workbuddy2api-panel-wb2api` 会残留在 NAS 上，占约 100MB，可以之后手动删。
