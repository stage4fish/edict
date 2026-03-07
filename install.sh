#!/bin/bash
# ══════════════════════════════════════════════════════════════
# 三省六部 · OpenClaw Multi-Agent System 一键安装脚本
# ══════════════════════════════════════════════════════════════
set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCLAW_PROFILE="${OPENCLAW_PROFILE:-edict36}"
OC_HOME="$HOME/.openclaw-${OPENCLAW_PROFILE}"
OC_CFG="$OC_HOME/openclaw.json"
OPENCLAW_STATE_DIR="$OC_HOME"
EDICT_GATEWAY_PORT="${EDICT_GATEWAY_PORT:-18790}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

banner() {
  echo ""
  echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║  🏛️  三省六部 · OpenClaw Multi-Agent    ║${NC}"
  echo -e "${BLUE}║       安装向导                            ║${NC}"
  echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
  echo ""
}

log()   { echo -e "${GREEN}✅ $1${NC}"; }
warn()  { echo -e "${YELLOW}⚠️  $1${NC}"; }
error() { echo -e "${RED}❌ $1${NC}"; }
info()  { echo -e "${BLUE}ℹ️  $1${NC}"; }

# ── Step 0: 依赖检查 ──────────────────────────────────────────
check_deps() {
  info "检查依赖..."
  
  if ! command -v openclaw &>/dev/null; then
    error "未找到 openclaw CLI。请先安装 OpenClaw: https://openclaw.ai"
    exit 1
  fi
  log "OpenClaw CLI: $(openclaw --version 2>/dev/null || echo 'OK')"

  if ! command -v python3 &>/dev/null; then
    error "未找到 python3"
    exit 1
  fi
  log "Python3: $(python3 --version)"

  # 检查主 openclaw 是否已初始化（需要 credentials）
  if [ ! -f "$HOME/.openclaw/openclaw.json" ]; then
    error "未找到 ~/.openclaw/openclaw.json。请先运行 openclaw 完成初始化。"
    exit 1
  fi
  log "主 openclaw 配置: $HOME/.openclaw/openclaw.json"
  info "edict 将使用独立 profile: --profile ${OPENCLAW_PROFILE} (${OC_HOME})"
}

# ── Step 0.5: 备份已有 Agent 数据 ──────────────────────────────
backup_existing() {
  AGENTS_DIR="$OC_HOME"
  BACKUP_DIR="$OC_HOME/backups/pre-install-$(date +%Y%m%d-%H%M%S)"
  HAS_EXISTING=false

  # 检查是否有已存在的 workspace
  for d in "$AGENTS_DIR"/workspace-*/; do
    if [ -d "$d" ]; then
      HAS_EXISTING=true
      break
    fi
  done

  if $HAS_EXISTING; then
    info "检测到已有 Agent Workspace，自动备份中..."
    mkdir -p "$BACKUP_DIR"

    # 备份所有 workspace 目录
    for d in "$AGENTS_DIR"/workspace-*/; do
      if [ -d "$d" ]; then
        ws_name=$(basename "$d")
        cp -R "$d" "$BACKUP_DIR/$ws_name"
      fi
    done

    # 备份 openclaw.json
    if [ -f "$OC_CFG" ]; then
      cp "$OC_CFG" "$BACKUP_DIR/openclaw.json"
    fi

    # 备份 agents 目录（agent 注册信息）
    if [ -d "$AGENTS_DIR/agents" ]; then
      cp -R "$AGENTS_DIR/agents" "$BACKUP_DIR/agents"
    fi

    log "已备份到: $BACKUP_DIR"
    info "如需恢复，运行: cp -R $BACKUP_DIR/workspace-* $AGENTS_DIR/"
  fi
}

# ── Step 1: 创建 Workspace ──────────────────────────────────
create_workspaces() {
  info "创建 Agent Workspace..."
  
  AGENTS=(taizi zhongshu menxia shangshu hubu libu bingbu xingbu gongbu libu_hr zaochao)
  for agent in "${AGENTS[@]}"; do
    ws="$OC_HOME/workspace-$agent"
    mkdir -p "$ws/skills"
    if [ -f "$REPO_DIR/agents/$agent/SOUL.md" ]; then
      if [ -f "$ws/SOUL.md" ]; then
        # 已存在的 SOUL.md，先备份再覆盖
        cp "$ws/SOUL.md" "$ws/SOUL.md.bak.$(date +%Y%m%d-%H%M%S)"
        warn "已备份旧 SOUL.md → $ws/SOUL.md.bak.*"
      fi
      sed "s|__REPO_DIR__|$REPO_DIR|g" "$REPO_DIR/agents/$agent/SOUL.md" > "$ws/SOUL.md"
    fi
    log "Workspace 已创建: $ws"
  done

  # 通用 AGENTS.md（工作协议）
  for agent in "${AGENTS[@]}"; do
    cat > "$OC_HOME/workspace-$agent/AGENTS.md" << 'AGENTS_EOF'
# AGENTS.md · 工作协议

1. 接到任务先回复"已接旨"。
2. 输出必须包含：任务ID、结果、证据/文件路径、阻塞项。
3. 需要协作时，回复尚书省请求转派，不跨部直连。
4. 涉及删除/外发动作必须明确标注并等待批准。
AGENTS_EOF
  done
}

# ── Step 2: 注册 Agents ─────────────────────────────────────
register_agents() {
  info "注册三省六部 Agents (profile: ${OPENCLAW_PROFILE})..."

  # 初始化隔离 profile 的 openclaw.json（若不存在则从主配置复制 credentials/models 部分）
  if [ ! -f "$OC_CFG" ]; then
    info "初始化 ${OC_HOME}/openclaw.json ..."
    mkdir -p "$OC_HOME"
    python3 << PYEOF_INIT
import json, pathlib, os
src = pathlib.Path.home() / '.openclaw' / 'openclaw.json'
dst = pathlib.Path(os.environ['OC_HOME']) / 'openclaw.json'
src_cfg = json.loads(src.read_text())
# 只复制 credentials/models/gateway 基础配置，不复制 agents
new_cfg = {}
for k in ('meta', 'auth', 'models', 'gateway', 'tools', 'messages', 'commands', 'session', 'hooks', 'channels', 'skills', 'plugins', 'env', 'wizard'):
    if k in src_cfg:
        new_cfg[k] = src_cfg[k]
# 覆盖 gateway 端口为 edict 专用端口
new_cfg.setdefault('gateway', {})['port'] = int(os.environ.get('EDICT_GATEWAY_PORT', '18790'))
new_cfg['agents'] = {'defaults': src_cfg.get('agents', {}).get('defaults', {}), 'list': []}
dst.write_text(json.dumps(new_cfg, ensure_ascii=False, indent=2))
print(f'初始化完成: {dst}')
PYEOF_INIT
  fi

  # 备份配置
  cp "$OC_CFG" "$OC_CFG.bak.sansheng-$(date +%Y%m%d-%H%M%S)"
  log "已备份配置: $OC_CFG.bak.*"

  python3 << PYEOF
import json, pathlib, sys, os

cfg_path = pathlib.Path(os.environ['OC_HOME']) / 'openclaw.json'
cfg = json.loads(cfg_path.read_text())

AGENTS = [
  {"id": "taizi",    "subagents": {"allowAgents": ["zhongshu"]}},
    {"id": "zhongshu", "subagents": {"allowAgents": ["menxia", "shangshu"]}},
    {"id": "menxia",   "subagents": {"allowAgents": ["shangshu", "zhongshu"]}},
  {"id": "shangshu", "subagents": {"allowAgents": ["zhongshu", "menxia", "hubu", "libu", "bingbu", "xingbu", "gongbu", "libu_hr"]}},
    {"id": "hubu",     "subagents": {"allowAgents": ["shangshu"]}},
    {"id": "libu",     "subagents": {"allowAgents": ["shangshu"]}},
    {"id": "bingbu",   "subagents": {"allowAgents": ["shangshu"]}},
    {"id": "xingbu",   "subagents": {"allowAgents": ["shangshu"]}},
    {"id": "gongbu",   "subagents": {"allowAgents": ["shangshu"]}},
  {"id": "libu_hr",  "subagents": {"allowAgents": ["shangshu"]}},
  {"id": "zaochao",  "subagents": {"allowAgents": []}},
]

agents_cfg = cfg.setdefault('agents', {})
agents_list = agents_cfg.get('list', [])
existing_ids = {a['id'] for a in agents_list}

added = 0
for ag in AGENTS:
    ag_id = ag['id']
    ws = str(pathlib.Path(os.environ['OC_HOME']) / f'workspace-{ag_id}')
    if ag_id not in existing_ids:
        entry = {'id': ag_id, 'workspace': ws, **{k:v for k,v in ag.items() if k!='id'}}
        agents_list.append(entry)
        added += 1
        print(f'  + added: {ag_id}')
    else:
        print(f'  ~ exists: {ag_id} (skipped)')

agents_cfg['list'] = agents_list
cfg_path.write_text(json.dumps(cfg, ensure_ascii=False, indent=2))
print(f'Done: {added} agents added')
PYEOF

  log "Agents 注册完成"
}

# ── Step 3: 初始化 Data ─────────────────────────────────────
init_data() {
  info "初始化数据目录..."
  
  mkdir -p "$REPO_DIR/data"
  
  # 初始化空文件
  for f in live_status.json agent_config.json model_change_log.json; do
    if [ ! -f "$REPO_DIR/data/$f" ]; then
      echo '{}' > "$REPO_DIR/data/$f"
    fi
  done
  echo '[]' > "$REPO_DIR/data/pending_model_changes.json"

  # 初始任务文件
  if [ ! -f "$REPO_DIR/data/tasks_source.json" ]; then
    python3 << 'PYEOF'
import json, pathlib
tasks = [
    {
        "id": "JJC-DEMO-001",
        "title": "🎉 系统初始化完成",
        "official": "工部尚书",
        "org": "工部",
        "state": "Done",
        "now": "三省六部系统已就绪",
        "eta": "-",
        "block": "无",
        "output": "",
        "ac": "系统正常运行",
        "flow_log": [
            {"at": "2024-01-01T00:00:00Z", "from": "皇上", "to": "中书省", "remark": "下旨初始化三省六部系统"},
            {"at": "2024-01-01T00:01:00Z", "from": "中书省", "to": "门下省", "remark": "规划方案提交审核"},
            {"at": "2024-01-01T00:02:00Z", "from": "门下省", "to": "尚书省", "remark": "✅ 准奏"},
            {"at": "2024-01-01T00:03:00Z", "from": "尚书省", "to": "工部", "remark": "派发：系统初始化"},
            {"at": "2024-01-01T00:04:00Z", "from": "工部", "to": "尚书省", "remark": "✅ 完成"},
        ]
    }
]
p = pathlib.Path(__file__).parent if '__file__' in dir() else pathlib.Path('.')
# Write to data dir
import os
data_dir = pathlib.Path(os.environ.get('REPO_DIR', '.')) / 'data'
data_dir.mkdir(exist_ok=True)
(data_dir / 'tasks_source.json').write_text(json.dumps(tasks, ensure_ascii=False, indent=2))
print('tasks_source.json 已初始化')
PYEOF
  fi

  log "数据目录初始化完成: $REPO_DIR/data"
}

# ── Step 4: 构建前端 ──────────────────────────────────────────
build_frontend() {
  info "构建 React 前端..."

  if ! command -v node &>/dev/null; then
    warn "未找到 node，跳过前端构建。看板将使用预构建版本（如果存在）"
    warn "请安装 Node.js 18+ 后运行: cd edict/frontend && npm install && npm run build"
    return
  fi

  if [ -f "$REPO_DIR/edict/frontend/package.json" ]; then
    cd "$REPO_DIR/edict/frontend"
    npm install --silent 2>/dev/null || npm install
    npm run build 2>/dev/null
    cd "$REPO_DIR"
    if [ -f "$REPO_DIR/dashboard/dist/index.html" ]; then
      log "前端构建完成: dashboard/dist/"
    else
      warn "前端构建可能失败，请手动检查"
    fi
  else
    warn "未找到 edict/frontend/package.json，跳过前端构建"
  fi
}

# ── Step 5: 首次数据同步 ────────────────────────────────────
first_sync() {
  info "执行首次数据同步..."
  cd "$REPO_DIR"
  
  REPO_DIR="$REPO_DIR" OPENCLAW_STATE_DIR="$OPENCLAW_STATE_DIR" python3 scripts/sync_agent_config.py || warn "sync_agent_config 有警告"
  python3 scripts/refresh_live_data.py || warn "refresh_live_data 有警告"
  
  log "首次同步完成"
}

# ── Step 6: 生成 pm2 配置并启动 ─────────────────────────────
setup_pm2() {
  info "配置 pm2 进程管理..."

  # 生成 ecosystem.config.cjs（动态填入实际路径）
  cat > "$REPO_DIR/ecosystem.config.cjs" << ECOSYSTEM_EOF
module.exports = {
  apps: [
    {
      name: 'edict-gateway',
      script: 'openclaw',
      args: '--profile ${OPENCLAW_PROFILE} gateway run --port ${EDICT_GATEWAY_PORT}',
      watch: false,
      autorestart: true,
      max_restarts: 10,
      restart_delay: 3000,
      env: {
        OPENCLAW_STATE_DIR: '${OPENCLAW_STATE_DIR}',
      },
    },
    {
      name: 'edict-dashboard',
      script: 'dashboard/server.py',
      interpreter: 'python3',
      args: '--port 7891',
      cwd: '${REPO_DIR}',
      watch: false,
      autorestart: true,
      max_restarts: 10,
      restart_delay: 2000,
      env: {
        OPENCLAW_STATE_DIR: '${OPENCLAW_STATE_DIR}',
      },
    },
    {
      name: 'edict-loop',
      script: 'scripts/run_loop.sh',
      interpreter: 'bash',
      cwd: '${REPO_DIR}',
      watch: false,
      autorestart: true,
      max_restarts: 10,
      restart_delay: 5000,
      env: {
        OPENCLAW_STATE_DIR: '${OPENCLAW_STATE_DIR}',
      },
    },
  ],
};
ECOSYSTEM_EOF

  log "ecosystem.config.cjs 已生成: $REPO_DIR/ecosystem.config.cjs"

  if ! command -v pm2 &>/dev/null; then
    warn "未找到 pm2，请先安装: npm install -g pm2"
    warn "安装后运行: cd $REPO_DIR && pm2 start ecosystem.config.cjs"
    return
  fi

  cd "$REPO_DIR"
  # 停止已有的同名进程（避免重复启动）
  pm2 delete edict-gateway edict-dashboard edict-loop 2>/dev/null || true
  pm2 start ecosystem.config.cjs
  pm2 save
  log "pm2 进程已启动"
}

# ── Main ────────────────────────────────────────────────────
banner
check_deps
backup_existing
create_workspaces
register_agents
init_data
build_frontend
first_sync
setup_pm2

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  🎉  三省六部安装完成！                          ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo "Profile 隔离目录: ${OC_HOME}"
echo "edict Gateway 端口: ${EDICT_GATEWAY_PORT} (本地 openclaw: 18789, 互不干扰)"
echo ""
echo "pm2 常用命令："
echo "  pm2 list                    查看所有进程状态"
echo "  pm2 logs edict-dashboard    查看看板日志"
echo "  pm2 logs edict-loop         查看数据刷新日志"
echo "  pm2 logs edict-gateway      查看 Gateway 日志"
echo "  pm2 restart edict-gateway   重启 Gateway"
echo "  pm2 stop all                停止所有 edict 进程"
echo ""
echo "打开看板: http://127.0.0.1:7891"
echo ""
info "文档: docs/getting-started.md"
