# asterCC 迁移测试环境部署

一键部署 CentOS 7 + MySQL 5.6 + Asterisk 1.8.32.3 + astercc-4.1，用于验证旧 UCServer 呼叫中心系统的数据迁移可行性。

> **警告**：这套环境全栈 EOL（CentOS 7 / MySQL 5.6 / PHP 7.4 / Asterisk 1.8 均已停止维护），**仅供测试验证，严禁上线**。正式部署请用 ViciBox 12 或 Asterisk 22 LTS。

## 这个仓库解决什么问题

asterCC 官方一键安装脚本是 2012-2021 年的产物，依赖一整套已下线的 IUS 生态。在 2026 年的环境里直接跑会连续踩坑：yum 源失效、内核重启、mysql56u 装不上、镜像域名失效、密码特殊字符死循环，而且脚本即使打印 `install finish`，Web 目录、配置文件、守护进程、数据库表、菜单数据**全都没做完**。

本仓库把两天实测踩过的 20 个坑全部内置为预防步骤，分阶段执行，一次成功。

## 文件结构

```
astriskCC/
├── README.md               本说明
├── deploy.sh               主部署脚本（preflight / phase1 / phase2 / verify）
├── .env.example            密码配置模板
├── .gitignore              排除真实密码与大文件
├── 推送到GitHub.md         推送操作记录
└── docs/
    ├── 最终部署文档.md      干净的重装指南（推荐先看）
    ├── 排错手册.md          完整排错记录（遇到问题时查）
    ├── ViciBox12部署清单.md 正式方案
    └── md2html.py           文档转 HTML 工具
```

> 提示：文档可在本地用 `python3 docs/md2html.py docs/最终部署文档.md 输出.html` 转成 HTML 阅读版。

## 快速开始

### 前置准备

1. 最小化安装 **CentOS 7.9**（64 位，4 核 8G 80G）
2. 下载 MySQL 离线包 `MySQL-5.6.51-1.el7.x86_64.rpm-bundle.tar`（约 243MB），放到 `/root/`
   - 下载页：https://downloads.mysql.com/archives/community/ → Version 5.6.51 / OS Red Hat 7
3. 以 root 登录，把本仓库拉下来：
   ```bash
   yum install -y git   # 若没装 git（换源前可能装不上，见下方说明）
   git clone https://github.com/dai1991/astriskCC.git /root/astercc-deploy
   cd /root/astercc-deploy
   ```

### 第 0 步：配置密码（重要）

**密码只能用字母数字，绝对不要 `!` 等特殊字符**——asterCC 脚本内部用裸的 `-p$密码` 传参，特殊字符会被 shell 处理导致密码死循环。

```bash
cp .env.example .env
vi .env
# 设 MYSQL_ROOT_PASS 和 WEB_ADMIN_PASS，保存
source .env
```

### 第 1 步：环境检查 + 阶段 1

```bash
bash deploy.sh preflight
bash deploy.sh phase1           # 换源、装依赖、关防火墙、离线装 MySQL 5.6
```

> 若 git 都装不上（官方源失效），先手动换源：
> ```bash
> mkdir -p /etc/yum.repos.d/bak && mv /etc/yum.repos.d/CentOS-*.repo /etc/yum.repos.d/bak/
> cat > /etc/yum.repos.d/CentOS-Base.repo <<'EOF'
> [base]
> name=CentOS7
> baseurl=https://mirrors.aliyun.com/centos-vault/7.9.2009/os/x86_64/
> gpgcheck=0
> enabled=1
> [updates]
> name=updates
> baseurl=https://mirrors.aliyun.com/centos-vault/7.9.2009/updates/x86_64/
> gpgcheck=0
> enabled=1
> EOF
> yum clean all && yum makecache && yum install -y git wget
> ```

### 第 2 步：asterCC 官方脚本（两轮，含交互）

这一步必须手工，因为有交互提示和一次重启：

```bash
cd /root
wget http://download1.astercc.org/install_asterCC_Commercial_CentOS7_php7.sh
chmod +x install_asterCC_Commercial_CentOS7_php7.sh
# 替换失效的 jaist 镜像域名（该域名已 NXDOMAIN）
sed -i 's#jaist\.dl\.sourceforge\.net#downloads.sourceforge.net#g' install_asterCC_Commercial_CentOS7_php7.sh

# 预下载 Asterisk 源码包（源很慢易挂起，提前下好让脚本跳过）
cd /usr/src
wget -c http://download3.astercc.org/asterisk-1.8.32.3.tar.gz
# 上面源不通就换官方源：
# wget -c https://downloads.asterisk.org/pub/telephony/asterisk/old-releases/asterisk-1.8.32.3.tar.gz -O asterisk-1.8.32.3.tar.gz
cd /root
# 加 -nc 防止脚本重下覆盖
sed -i 's#wget http://download3.astercc.org/asterisk-1.8.32.3.tar.gz#wget -nc http://download3.astercc.org/asterisk-1.8.32.3.tar.gz#' install_asterCC_Commercial_CentOS7_php7.sh

# 第一轮：装依赖和内核，结束会要求 reboot
./install_asterCC_Commercial_CentOS7_php7.sh 2>&1 | tee -a astercc_install.log
reboot
```

重启后重新登录，**确认 MySQL 还在**（`mysql -u root -e "select version();"`），再跑第二轮：

```bash
cd /root && ./install_asterCC_Commercial_CentOS7_php7.sh 2>&1 | tee -a astercc_install.log
```

交互提示这样填（**逐条输入，不要一次粘贴多行**）：

| 提示 | 输入 |
|---|---|
| `please enter your mysql root passwd` | `.env` 里的 `MYSQL_ROOT_PASS` |
| `Please select the mirror...` (1/2/3) | `3`（China Server） |
| `please give an AMI user` | `astercc` |
| AMI password（若问） | 同 `MYSQL_ROOT_PASS` |

验证 Asterisk（**不要信脚本的 finish**）：
```bash
asterisk -V    # 应输出 Asterisk 1.8.32.3
```

### 第 3 步：阶段 2（补齐应用层收尾）

```bash
cd /root/astercc-deploy && source .env   # clone 后的本地目录名，可自定义
bash deploy.sh phase2
```

这一步自动完成：Web 目录软链、astercc.conf 复制、路径软链、数据库账号授权、补建 325 张表 + 菜单数据、Web 数据库配置、admin 密码重置、启动全部守护进程、开机自启。

### 第 4 步：验收

```bash
bash deploy.sh verify
```

浏览器访问 `http://VM_IP`，用 `admin` / `.env` 里的 `WEB_ADMIN_PASS` 登录，左侧应有完整菜单（PBX 管理下配分机）。

**最终验收**：软电话注册分机，打一通真实电话。CTI 显示"警告"可忽略——内线正常 + AMI 连着即代表可用。

## 常见问题

| 现象 | 原因 | 解决 |
|---|---|---|
| `yum install` 全失败 | CentOS 7 官方源下线 | 换 vault 源（见第 1 步） |
| `ERROR 1045` 密码死循环 | 密码含 `!` | 用纯字母数字密码 |
| Asterisk 源码下载卡死 | 源慢/挂起 | 预下载 + `-nc`（第 2 步） |
| 页面 404 / 500 | Web 目录空 / 配置错 | phase2 自动修复 |
| 菜单只有"退出登陆" | 菜单数据未导 | phase2 自动修复 |
| 宿主机浏览器超时 | firewalld 复活 | phase1 已 disable |
| 命令里 `[xxx]` 变成 `$$xxx$$` | 输入环境转义 | 脚本已避开方括号正则 |

详细排错过程见 `docs/排错手册.md`。

## 说明

- 本项目不含任何真实密码，`.env` 已加入 `.gitignore`，不会提交。
- Asterisk 装的是 1.8.32.3（与旧生产系统同版本），配置可直接拷——这是迁移验证的关键前提。
- 想升级到新版本 Asterisk？见末尾"升级路径"说明——那需要换整套系统，不是原地升级。
