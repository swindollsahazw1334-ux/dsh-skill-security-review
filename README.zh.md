# dsh-skill-security-review

给 DeepSeek Harness（DSH）装一个技能：**在安装任何第三方插件之前，先做一遍带证据的安全审查**。

装的是技能，不是权限控制。它让 agent 在你说“审一下这个包”时，按固定流程走：拉元数据 → 解包静态扫描 → 人工复核 → A/B/C 分级 → 必要时扔进隔离环境试毒。

## 安装

```bash
dsh plugin --profile desktop add dsh-skill-security-review
```

重启 DSH 后，技能 `plugin-security-review` 出现在技能目录里。也可以被显式调用。

## 它让 agent 做什么

1. **元数据**：npm 上的发布者、首发时间、版本节奏、仓库是否与 scope 对得上、`engines.dsh` 兼容性。
2. **静态扫描**（`scripts/audit.ps1`，只 `npm pack` 到临时目录，不安装）：
   - 安装钩子（`preinstall` / `install` / `postinstall` / `prepare`）
   - `child_process` / `exec` 调用
   - `eval` / `new Function` / `vm`
   - 出站域名、上传类调用
   - 对 `~/.dsh`、`~/.ssh`、`credentials` 等凭据路径的访问
   - base64 / 混淆特征
   - 依赖树
3. **人工复核**：脚本只报位置，语义要读——比如 fetch 的目标域名和插件宣称的功能是否一致。
4. **分级**：
   - **A 可装**：源码可读、无钩子、网络与文件访问和功能一致
   - **B 有条件**：无源码 / 压缩产物 / 依赖多 → 只在 quarantine 里试
   - **C 不建议**：混淆、安装即下载执行、读凭据、权限与功能不符
5. **隔离验证**：用独立 `DSH_HOME` + 只读沙箱的 profile 跑一遍，再决定要不要进主环境。

## 报告长什么样

```
插件：dsh-open-market@0.2.5        判定：B
来源：npm                          作者：polang233   首发：2026-10-24

红线：无
关注：client.js:174 / client.js:222 向 dshopen.org 发 likes 请求
      无 src/，只有打包后的 JS，存在 595 字符超长行
盲区：不可充分审查
建议：只在 quarantine 试
```

## 已知限制

- 同一用户账号下无法真正隔离：只读沙箱阻止写入和提权，**不阻止读取和外发**。
- 静态扫描挡不住运行时拼接调用、依赖投毒、npm 账号被盗后的新版。
- 结论是风险判断，不是安全担保。

## 许可证

MIT
