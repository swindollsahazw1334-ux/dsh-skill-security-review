# 发布清单

包已经做完了，卡在两件需要你本人账号的事上。

## 现状

| 项 | 状态 |
|---|---|
| 包结构 | `dsh-skill-security-review@0.1.0`，9 个文件，22.7 KB |
| 本地验证 | `lib/index.js` 的 provider 契约通过：skill 名 `plugin-security-review`、rank 600、frontmatter 已剥离 |
| 隔离验证 | 已装进 `quarantine` profile 并成功启动，无加载错误 |
| git | 已 init 并提交（commit `3f7c1c0`） |
| npm 登录 | **没有**（`npm whoami` → ENEEDAUTH） |
| GitHub 仓库 | **没有**（`gh` 未安装） |

## 0. 包名说明

`dsh-plugin-security-review` 已被别人占用（`shanhaifish`，2026-08-21 首发）。本包用的是 **`dsh-skill-security-review`**，当前可用。

## 1. npm 登录并发布

```powershell
npm login          # 浏览器/OTP 交互，需要你本人操作
npm publish        # 目录：C:\Users\13601\Documents\deepseek-harness\default-workspace\dsh-skill-security-review
```

`publishConfig.access = public` 已配好；`engines.dsh: >=0.2.1-rc.2 <0.3.0` 已声明，插件市场会据此算兼容性。

发布后验证：

```powershell
npm view dsh-skill-security-review version dist.integrity
```

## 2. 推到 GitHub

仓库还没有，先把提交身份改成你自己：

```powershell
git config user.name  "你的名字"
git config user.email "你的邮箱"
git commit --amend --reset-author --no-edit
```

然后在 GitHub 建一个 public 仓库，推送：

```powershell
git remote add origin https://github.com/<你的用户名>/dsh-skill-security-review.git
git push -u origin main
```

## 3. 提交 dshopen 收录

入口：<https://github.com/polang233/dsh-plugin-index/issues/new?template=plugin-add.yml>

正文草稿：

```markdown
- 包名：dsh-skill-security-review
- 版本：0.1.0
- 仓库：https://github.com/<用户名>/dsh-skill-security-review
- 许可证：MIT
- 分类：工具 / 安全
- 简介：给 DSH 装一个技能——在安装第三方插件前先做带证据的安全审查：npm 元数据、解包静态扫描（安装钩子/child_process/eval/凭据路径/出站域名）、A/B/C 分级、以及用独立 DSH_HOME + 只读沙箱的 quarantine profile 做动态验证。
- 说明：包内含 1 个技能（plugin-security-review）和 1 个 PowerShell 审计脚本（scripts/audit.ps1），零运行时依赖，不修改宿主配置。
```

## 4. 发布后自检

```powershell
dsh plugin --profile desktop add dsh-skill-security-review
```

重启后技能目录里应出现 `plugin-security-review`。若没有，检查 `dsh --profile desktop --dump-config` 里有没有 `skill-security-review` 这一行。
