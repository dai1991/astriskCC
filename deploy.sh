#!/bin/bash
# ============================================================
# asterCC 迁移测试环境 · 一键部署脚本（ CentOS 7 + MySQL 5.6 + astercc-4.1 ）
#
# 整合 2026-11 实测踩坑经验，所有坑已内置为预防步骤。
# 用途：验证旧 UCServer（CentOS 6.9 + Asterisk 1.8.32.3）的数据迁移可行性。
# 警告：全栈 EOL，仅供测试，严禁上线。
#
# 用法：
#   1. 最小化安装 CentOS 7.9 后，以 root 登录
#   2. 把 MySQL 离线包放到 /root/
#   3. bash deploy.sh preflight        # 阶段0：检查环境
#   4. bash deploy.sh phase1           # 阶段1：系统初始化 + MySQL 离线安装
#      （离线包路径不对时用：bash deploy.sh phase1 /path/to/bundle.tar）
#   5. 下载并手工跑 asterCC 官方脚本两轮（含 reboot），见 README
#   6. bash deploy.sh phase2           # 阶段2：补齐 asterCC 应用层收尾
#   7. bash deploy.sh verify           # 阶段3：验收检查
#
# 密码通过环境变量配置（见 .env.example），例如：
#   export MYSQL_ROOT_PASS='YourPass123'
#   export WEB_ADMIN_PASS='admin123'
# 不设则用脚本内默认值（测试用，生产务必修改）。
# ============================================================

set -euo pipefail

# ---------- 可配置参数（环境变量覆盖，全部纯字母数字） ----------
MYSQL_ROOT_PASS="${MYSQL_ROOT_PASS:-TestPass123}"
WEB_ADMIN_PASS="${WEB_ADMIN_PASS:-admin123}"
MYSQL_VER="5.6.51"
BUNDLE="MySQL-${MYSQL_VER}-1.el7.x86_64.rpm-bundle.tar"

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[$(date +%H:%M:%S)] $*${NC}"; }
warn() { echo -e "${YELLOW}[WARN] $*${NC}"; }
err()  { echo -e "${RED}[ERROR] $*${NC}"; exit 1; }
need_root() { [ "$(id -u)" -eq 0 ] || err "请用 root 用户执行"; }
need_c7()   { grep -qE 'CentOS Linux release 7' /etc/redhat-release || err "仅适用于 CentOS 7"; }
# 导入 SQL 的辅助函数（前置 sql_mode 绕过 MySQL 5.6 严格模式的 BLOB/TEXT default 报错）
imp_sql() {
  { echo "SET SESSION sql_mode='';"; cat "$1"; } > /tmp/astercc_imp.sql
  mysql -u astercc -p'asterccsecret' astercc10 < /tmp/astercc_imp.sql 2>/dev/null
}

# ============================================================
# 阶段 0：环境检查
# ============================================================
phase_preflight() {
  need_root; need_c7
  log "系统：$(cat /etc/redhat-release)"
  log "内核：$(uname -r)"
  log "内存：$(free -h | awk '/Mem/{print $2}')"
  log "磁盘：$(df -h / | awk 'NR==2{print $2" 可用 "$4}')"
  echo ""
  log "检查离线包："
  for p in "/root/$BUNDLE" "/mnt/$BUNDLE"; do
    [ -f "$p" ] && log "  找到：$p ($(du -h "$p" | cut -f1))"
  done
  if [ ! -f "/root/$BUNDLE" ] && [ ! -f "/mnt/$BUNDLE" ]; then
    warn "未找到 $BUNDLE，phase1 会尝试从官方归档站下载（需联网）"
  fi
  log "检查通过，可执行 phase1"
}

# ============================================================
# 阶段 1：系统初始化 + MySQL 5.6 离线安装
# ============================================================
phase1() {
  need_root; need_c7
  local bundle_arg="${1:-}"

  log "===== 1.1 换 vault yum 源 ====="
  mkdir -p /etc/yum.repos.d/bak
  mv /etc/yum.repos.d/CentOS-*.repo /etc/yum.repos.d/bak/ 2>/dev/null || true
  cat > /etc/yum.repos.d/CentOS-Base.repo <<'EOF'
[base]
name=CentOS 7 - Base
baseurl=https://mirrors.aliyun.com/centos-vault/7.9.2009/os/x86_64/
gpgcheck=0
enabled=1
[updates]
name=CentOS 7 - Updates
baseurl=https://mirrors.aliyun.com/centos-vault/7.9.2009/updates/x86_64/
gpgcheck=0
enabled=1
[extras]
name=CentOS 7 - Extras
baseurl=https://mirrors.aliyun.com/centos-vault/7.9.2009/extras/x86_64/
gpgcheck=0
enabled=1
EOF
  yum clean all >/dev/null && yum makecache >/dev/null
  log "yum 源已换为阿里云 vault"

  log "===== 1.2 装依赖（含 perl-Data-Dumper，MySQL 初始化必需） ====="
  yum install -y wget vim net-tools perl perl-Data-Dumper libaio numactl chrony tar

  log "===== 1.3 关 SELinux / 防火墙（预防权限与访问问题） ====="
  setenforce 0 2>/dev/null || true
  sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
  systemctl stop firewalld 2>/dev/null || true
  systemctl disable firewalld 2>/dev/null || true
  log "SELinux=$(getenforce)，firewalld 已关闭"

  log "===== 1.4 校时 + wget 超时 ====="
  timedatectl set-timezone Asia/Shanghai
  systemctl enable --now chronyd 2>/dev/null || true
  chronyc -a makestep 2>/dev/null || true
  grep -q 'timeout=30' /root/.wgetrc 2>/dev/null || echo -e 'timeout=30\ntries=5' >> /root/.wgetrc

  log "===== 1.5 建 mysql 用户（否则 RPM 报 user does not exist） ====="
  groupadd mysql 2>/dev/null || true
  useradd -r -g mysql -s /bin/false mysql 2>/dev/null || true
  id mysql

  log "===== 1.6 定位 MySQL 离线包 ====="
  local bundle_path="$bundle_arg"
  if [ -z "$bundle_path" ]; then
    for p in "/root/$BUNDLE" "/mnt/$BUNDLE" "$PWD/$BUNDLE"; do
      [ -f "$p" ] && { bundle_path="$p"; break; }
    done
  fi
  if [ -z "$bundle_path" ] || [ ! -f "$bundle_path" ]; then
    warn "未找到离线包，尝试从官方归档站下载："
    mkdir -p /root/mysql56-offline && cd /root/mysql56-offline
    wget -c --timeout=30 "https://downloads.mysql.com/archives/get/p/23/file/$BUNDLE" -O "$BUNDLE" \
      || err "下载失败。请在有网机器下载 $BUNDLE 后传到 /root/，再跑：bash deploy.sh phase1 /path/to/$BUNDLE"
    bundle_path="/root/mysql56-offline/$BUNDLE"
  fi
  log "使用离线包：$bundle_path ($(du -h "$bundle_path" | cut -f1))"

  log "===== 1.7 清理残留 + 解压 + 按序装 RPM ====="
  systemctl stop mysqld mariadb 2>/dev/null || true
  rpm -qa | grep -iE '^(mariadb|mysql|MySQL)' | xargs -r rpm -e --nodeps 2>/dev/null || true
  [ -d /var/lib/mysql ] && mv /var/lib/mysql "/var/lib/mysql.old.$(date +%s)"
  mkdir -p /root/mysql56-offline && cd /root/mysql56-offline
  tar -xvf "$bundle_path" >/dev/null || err "解压失败，离线包可能损坏"
  # 关键修正：--nodigest --nosignature（不用 --nogpgcheck，实测 rpm 报 unknown option）
  rpm -ivh --nodeps --force --nodigest --nosignature MySQL-shared-compat-${MYSQL_VER}-1.el7.x86_64.rpm
  rpm -ivh --nodeps --force --nodigest --nosignature MySQL-client-${MYSQL_VER}-1.el7.x86_64.rpm
  rpm -ivh --nodeps --force --nodigest --nosignature MySQL-devel-${MYSQL_VER}-1.el7.x86_64.rpm
  rpm -ivh --nodeps --force --nodigest --nosignature MySQL-server-${MYSQL_VER}-1.el7.x86_64.rpm
  log "RPM 安装完成"

  log "===== 1.8 初始化数据目录 + 建 service ====="
  rm -rf /var/lib/mysql/*
  mysql_install_db --user=mysql --datadir=/var/lib/mysql >/dev/null 2>&1 || err "mysql_install_db 失败，检查 perl-Data-Dumper"
  chown -R mysql:mysql /var/lib/mysql
  cat > /usr/lib/systemd/system/mysqld.service <<'EOF'
[Unit]
Description=MySQL Server
After=network.target
[Service]
Type=forking
User=mysql
Group=mysql
ExecStart=/usr/bin/mysqld_safe --datadir=/var/lib/mysql
ExecStop=/usr/bin/mysqladmin --user=root shutdown
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
  mkdir -p /var/run/mysqld && chown mysql:mysql /var/run/mysqld
  systemctl daemon-reload
  systemctl start mysqld && systemctl enable mysqld >/dev/null
  local v; v="$(mysql -u root -N -e 'select version();' 2>/dev/null)"
  [ -n "$v" ] || err "MySQL 连接失败"
  log "===== 阶段1 完成：MySQL $v，root 空密码（留给 asterCC 脚本设置） ====="
  echo ""
  echo "下一步（README 第 3 节）："
  echo "  1) cd /root && wget http://download1.astercc.org/install_asterCC_Commercial_CentOS7_php7.sh"
  echo "  2) sed -i 's#jaist\\.dl\\.sourceforge\\.net#downloads.sourceforge.net#g' install_asterCC_Commercial_CentOS7_php7.sh"
  echo "  3) 预下载 Asterisk 包（见 README），然后跑脚本两轮（含 reboot）"
  echo "  4) 回来执行：bash deploy.sh phase2"
}

# ============================================================
# 阶段 2：补齐 asterCC 应用层（脚本跳过的收尾）
# ============================================================
phase2() {
  need_root
  local app="/usr/src/astercc-4.1"

  log "===== 2.0 再次关闭防火墙（asterCC 脚本会复活 firewalld，导致宿主机访问不到 Web） ====="
  systemctl stop firewalld 2>/dev/null || true
  systemctl disable firewalld 2>/dev/null || true

  log "===== 2.1 Web 目录软链（否则 404） ====="
  [ -e /var/www/html/asterCC ] && [ ! -L /var/www/html/asterCC ] && mv /var/www/html/asterCC /var/www/html/asterCC.empty
  ln -sfn "$app" /var/www/html/asterCC
  ln -sfn "$app" /var/www/html/astercc
  chmod -R 777 "$app/app/tmp"
  mkdir -p /var/www/html/asterCC/http-log && chown -R asterisk:asterisk /var/www/html/asterCC/http-log 2>/dev/null || true
  systemctl reload nginx 2>/dev/null || true

  log "===== 2.2 守护进程配置 + 路径软链 ====="
  [ -f /etc/astercc.conf ] || cp "$app/scripts/astercc.conf" /etc/astercc.conf
  mkdir -p /opt/asterisk/scripts
  ln -sfn "$app/scripts/64" /opt/asterisk/scripts/astercc
  # AMI 密码对齐 + read 权限（避开方括号正则，实测输入环境会转义 [ ]）
  sed -i "s/^secret *=.*/secret = ${MYSQL_ROOT_PASS}/" /etc/astercc.conf
  sed -i 's/^read *=.*/read = all/' /etc/asterisk/manager.conf
  asterisk -rx 'manager reload' 2>/dev/null || true

  log "===== 2.3 建 asterCC 专用数据库账号 ====="
  mysql -u root -p"${MYSQL_ROOT_PASS}" -e "
    GRANT ALL PRIVILEGES ON astercc10.* TO 'astercc'@'localhost' IDENTIFIED BY 'asterccsecret';
    GRANT ALL PRIVILEGES ON astercc10.* TO 'astercc'@'127.0.0.1' IDENTIFIED BY 'asterccsecret';
    FLUSH PRIVILEGES;" 2>/dev/null || warn "建账号失败，检查 root 密码是否正确"

  log "===== 2.4 补建 325 张表 + 初始化数据（含菜单） ====="
  cd "$app/sql"
  imp_sql astercc10.sql
  imp_sql default_settings_en.sql
  imp_sql astercc_default_leftlist.sql
  for f in astercc_privilegesID.sql astercc_role_privilegesID.sql astercc_search_fields.sql astercc_pbxtmplates.sql; do
    [ -f "$f" ] && imp_sql "$f"
  done
  local tables; tables=$(mysql -u astercc -p'asterccsecret' -N -e "use astercc10; show tables;" 2>/dev/null | wc -l)
  log "数据库表数量：$tables"

  log "===== 2.5 Web 数据库配置 ====="
  sed -i "s/'login' => 'root'/'login' => 'astercc'/g; s/'password' => ''/'password' => 'asterccsecret'/g; s/'password' => 'astercc'/'password' => 'asterccsecret'/g" "$app/app/config/database.php"
  chown -R asterisk:asterisk /etc/asterisk

  log "===== 2.6 重置 Web 管理员密码 ====="
  mysql -u astercc -p'asterccsecret' -e "use astercc10; update cc10_accounts set password=md5('${WEB_ADMIN_PASS}') where username='admin';" 2>/dev/null

  log "===== 2.7 启动全部守护进程 ====="
  cd /opt/asterisk/scripts/astercc
  ./asterccc -d 2>/dev/null || true
  for p in astcc_realtime readevents astcc_datamover astcc_dialer astcc_statistics astcc_sysevents; do
    [ -x "./$p" ] && ./$p -d 2>/dev/null || true
  done

  log "===== 2.8 配开机自启 ====="
  cat > /etc/rc.d/rc.local <<'EOF'
#!/bin/bash
sleep 15
systemctl start mysqld
systemctl start asterisk
systemctl start nginx
systemctl start redis
cd /opt/asterisk/scripts/astercc
./asterccc -d
for p in astcc_realtime readevents astcc_datamover astcc_dialer astcc_statistics astcc_sysevents; do [ -x "./$p" ] && ./$p -d; done
EOF
  chmod +x /etc/rc.d/rc.local

  log "===== 阶段2 完成 ====="
  echo "浏览器访问 http://本机IP，用 admin / ${WEB_ADMIN_PASS} 登录"
}

# ============================================================
# 阶段 3：验收
# ============================================================
phase_verify() {
  need_root
  log "===== 验收检查 ====="
  echo ""
  printf "%-24s" "Asterisk 版本:"; asterisk -V 2>/dev/null || echo "未安装"
  printf "%-24s" "Asterisk 服务:"; systemctl is-active asterisk 2>/dev/null || true
  printf "%-24s" "MySQL 版本:"; mysql -u root -p"${MYSQL_ROOT_PASS}" -N -e 'select version();' 2>/dev/null || echo "失败"
  printf "%-24s" "astercc10 表数:"; mysql -u astercc -p'asterccsecret' -N -e "use astercc10; show tables;" 2>/dev/null | wc -l
  printf "%-24s" "Web HTTP:"; curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1 2>/dev/null || echo "失败"
  echo ""
  printf "%-24s" "asterccc 进程数:"; ps aux | grep -i '[a]sterccc' | wc -l
  printf "%-24s" "astcc_* 进程数:"; ps aux | grep -iE '[a]stcc_|[r]eadevents' | wc -l
  echo ""
  log "最终验收标准：软电话注册分机，打一通真实电话（CTI 警告可忽略）"
}

case "${1:-}" in
  preflight) phase_preflight ;;
  phase1)    shift; phase1 "$@" ;;
  phase2)    phase2 ;;
  verify)    phase_verify ;;
  *)
    echo "用法：$0 {preflight|phase1|phase2|verify}"
    echo "  preflight      检查环境"
    echo "  phase1 [包路径] 系统初始化 + MySQL 离线安装"
    echo "  phase2         补齐 asterCC 应用层收尾"
    echo "  verify         验收检查"
    exit 1 ;;
esac
