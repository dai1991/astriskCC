# ViciBox 12 部署清单（路线 A）

**目标**：用官方预打包 ISO 快速搭起一套持续维护的开源呼叫中心（VICIdial），替代老旧的澍品 UCServer（asterCC）。

**为什么选它**：官方 ISO 把操作系统 + Asterisk + MariaDB + Web + VICIdial 全部打包，一条命令完成安装，避开手工编译和 EOL 源的坑；VICIdial 项目至今每周更新，满足"产品能持续更新"的要求。

**本清单信息来源**：vicidial.com / download.vicidial.com 官方站、ViciBox 12 安装指南（2026 年资料），核实日期 2026-11-18。

---

## 0. 重要认知（先读）

| 项 | 说明 |
|---|---|
| ViciBox 版本 | **12.0.2**（当前稳定版），基于 openSUSE Leap 15.6 |
| 内置组件 | Asterisk 18 + MariaDB 10.11.9 + PHP 8.2 + Apache + VICIdial 2.14b0.5 |
| Asterisk 18 状态 | 已于 2025-10 EOL，但比旧系统的 1.8/13 新太多，且 VICIdial 官方支持它 |
| 持续更新 | **VICIdial 应用层每周更新**（SVN trunk），这是"产品能更新"的核心 |
| 旧数据迁移 | VICIdial 与 asterCC 数据结构**完全不同**，不能整库导入；只能导出客户名单/录音/ CDR 后做字段映射导入 |
| 与路线 B 的关系 | 本方案先快速验证可行性；若要 Asterisk 22 LTS + 最新架构，可在验证通过后走路线 B（另文） |

---

## 1. 准备

### 1.1 下载 ISO

- 官方地址：`https://download.vicidial.com/iso/vicibox/server/`
- 文件名：`ViciBox_v12.x86_64.iso`（约 1–2 GB）
- 两个版本：
  - **Standard**：单盘 / 硬件 RAID / 虚拟机 → **测试环境选这个**
  - MD：双盘软件 RAID1，生产环境用

### 1.2 虚拟机配置

| 项 | 最低 | 建议 |
|---|---|---|
| CPU | 4 核 @ 2.0 GHz | 6+ 核 |
| 内存 | 8 GB | 16 GB |
| 硬盘 | 160 GB **SSD** | 500 GB SSD |
| 网卡 | 1 Gbps，桥接模式 | 独立网卡 |
| 光驱 | 挂载 ISO | — |

> SSD 是硬性要求，不是建议——录音写入和数据库查询都吃 IO。

---

## 2. 安装系统（Phase 1，约 10 分钟）

1. 新建 VM，挂载 ISO，启动，选 **Install ViciBox**。
2. 按提示配置：
   - 安装磁盘（选目标盘）；
   - root 密码（牢记）；
   - 键盘 / 语言 / 时区。
3. 安装完成后 `reboot`，**安装时会清空目标盘**，确认选对磁盘。
4. 重启后用 root 登录。

---

## 3. 安装前配置（关键，别跳过）

### 3.1 设静态 IP

VICIdial 的配置**永久绑定服务器 IP**，后期改 IP 要改十几张表，务必一开始就设对：

```bash
yast lan
```
选网卡 → "Statically assigned IP Address" → 填 IP/掩码/网关/DNS → Alt-O 保存。
验证：`ping -4 google.com`

### 3.2 设时区（必须用 ViciBox 专用命令）

```bash
vicibox-timezone
```
> 注意：不要用普通 `yast` 设时区，它不会更新 PHP 的时区，会导致 CDR 时间错乱。

### 3.3 更新系统

```bash
zypper ref
zypper up
reboot
```
> **只能用 `zypper up`，绝不能用 `zypper dup`**——后者是发行版升级，会降级 MariaDB 或破坏 DAHDI，有生产事故案例。

---

## 4. 安装 VICIdial（Phase 2，一条命令）

单机部署（测试环境）：

```bash
vicibox-express
```

它会一次性配置 MariaDB、Apache、Asterisk、VICIdial 和全部 AGC 脚本。交互中需要：
- MySQL root 密码（设置一个并记住）；
- 服务器 IP（确认是第 3.1 步设的静态 IP）；
- 时区（确认正确）。

约 5–7 分钟完成，然后 `reboot`。

---

## 5. 一个必须立即修的 Bug

ViciBox 12 自带的 MariaDB 弃用了隐式 TIMESTAMP 行为，会**静默破坏表结构**。装完立刻执行：

```bash
echo "explicit_defaults_for_timestamp = Off" >> /etc/my.cnf.d/general.cnf
systemctl restart mariadb
```

---

## 6. 验证安装成功

```bash
# 应该看到 10-12 个 screen 会话（VICIdial 各守护进程）
screen -ls

# Asterisk 版本
asterisk -V

# 数据库版本
mysql --version
```

浏览器访问：
```
http://<服务器IP>/vicidial/welcome.php
```
默认账号：**6666 / 1234** —— **登录后立即改密码**。

---

## 7. 旧数据安全加固（测试环境也建议）

- 不要把 SIP 5060 和 Web 界面暴露到公网；用防火墙限定运营商和坐席来源 IP；
- 坐席和管理界面启用 HTTPS；
- 定期 `zypper up` 保持更新。

---

## 8. 旧数据导入（asterCC → VICIdial）

### 8.1 能导什么、怎么导

| 旧系统数据 | 导出方式 | 导入 VICIdial |
|---|---|---|
| 客户名单 | 从旧 MySQL `mysqldump` 相关表 → 转 CSV | 用 VICIdial 后台 "Lists" → Upload Leads（CSV） |
| 通话记录 CDR |mysqldump CDR 表 → CSV | 可作为历史档案留存；VICIdial 的 `call_log` 表结构不同，需字段映射脚本才能导入 |
| 录音文件 | 打包 `/var/spool/asterisk/monitor/` 等录音目录 | 放到 VICIdial 录音目录，按约定命名（`<lead_id>-<timestamp>.wav`），并在数据库登记路径 |
| IVR 流程 | 人工记录旧 `extensions.conf` 的逻辑 | 在 VICIdial 后台重新配置 IVR 菜单，无法自动转换 |

### 8.2 现实提醒

- **不存在一键整库迁移**：asterCC 和 VICIdial 是两套完全不同的数据模型；
- 真正有价值且容易迁移的是**客户名单（CSV）**和**录音文件（改名归档）**；
- CDR 历史和 IVR 流程要么人工重建，要么作为参考档案保留，不必强求导入；
- 既然目标是"上持续更新的新系统"，把旧数据当作**参考**而非**必须完整搬迁**，投入产出比最高。

---

## 9. 时间线预期

| 阶段 | 耗时 |
|---|---|
| 下载 ISO + 建 VM | 10–20 分钟 |
| Phase 1 装系统 | 约 10 分钟 |
| Phase 2 装 VICIdial | 5–7 分钟 |
| 修 Bug + 验证 | 5 分钟 |
| 客户名单导入 + 坐席测试 | 视数据量，1–2 小时 |

**总计：一个下午可完成从零到可测试的呼叫中心。**

---

## 10. 与旧方案的对比

| 维度 | 旧：澍品 UCServer (asterCC) | 新：ViciBox 12 (VICIdial) |
|---|---|---|
| 安装 | 手工编译，依赖已下线的 IUS 源 | 官方 ISO，一条命令 |
| Asterisk | 1.8.32.3（EOL 11 年） | 18（VICIdial 官方支持） |
| PHP | 5.6（EOL） | 8.2 |
| 数据库 | MySQL 5.1 / 5.6 | MariaDB 10.11 |
| 应用层维护 | 厂商 4 人、资质过期 | 开源社区每周更新 |
| Web 源码 | ionCube 加密，不可改 | 开放可审计 |
| 持续更新 | 无 | 有（zypper + SVN） |

---

*文档生成时间：2026-11-18。安装命令与版本号基于 2026 年官方文档与指南核实；实际以 ISO 内向导提示为准。*
