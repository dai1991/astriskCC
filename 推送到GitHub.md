# 推送到 GitHub

仓库已在本机准备好并完成首次提交（8 个文件，已脱敏、无真实密码）。推送只需三步。

## 前提

需要你自己的 GitHub 账号和 Personal Access Token（PAT）。生成 Token：
- GitHub → 右上角头像 → Settings → Developer settings → Personal access tokens → Tokens (classic)
- Generate new token，勾选 `repo` 权限，生成后复制保存（只显示一次）

## 第一步：在 GitHub 建空仓库

打开 https://github.com/new ：
- Repository name：`astercc-deploy`（或你喜欢的名字）
- 选 **Private**（推荐，虽然已脱敏）或 Public
- **不要**勾选 "Add a README file"（保持空仓库）
- 点 Create repository

## 第二步：推送

打开终端（Git Bash / PowerShell），执行（把 `你的用户名` 换成实际 GitHub 用户名）：

```bash
cd "C:/Users/Eason/WorkBuddy/2026-11-17-14-41-17/astercc-github-repo"
git remote add origin https://github.com/你的用户名/astercc-deploy.git
git branch -M main
git push -u origin main
```

推送时会弹窗要求登录，或提示输入用户名/密码——**用户名填 GitHub 用户名，密码填上面生成的 PAT**（不是 GitHub 登录密码）。

## 第三步：验证

浏览器打开 `https://github.com/你的用户名/astercc-deploy`，应看到：

```
.env.example
.gitignore
README.md
deploy.sh
docs/
  ├── ViciBox12部署清单.md
  ├── md2html.py
  ├── 排错手册.md
  └── 最终部署文档.md
```

## 下次部署时拉取

在新的 CentOS 7 机器上：

```bash
yum install -y git    # 若官方源失效，先按 README 里的步骤换 vault 源
git clone https://github.com/你的用户名/astercc-deploy.git
cd astercc-deploy
bash deploy.sh preflight
```

详细部署流程见 README.md。

## 关于自动推送

当前环境的 GitHub 连接器虽然已授权，但它的工具未注册到本次会话（重连后仍不可用），所以我无法直接帮你推送。如果下次会话工具正常加载，你只需说一句"把 astercc-github-repo 推到 GitHub"，我就能直接用连接器完成。

## 安全确认

- 所有真实密码已替换为 `<YOUR_DB_PASS>` 占位符
- `.env`（真实密码文件）已加入 `.gitignore`，未提交
- 个人信息（邮箱、公司联系方式）已扫描清除
- 仓库仅含脚本和文档，无敏感数据
