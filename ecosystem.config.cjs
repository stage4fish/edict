module.exports = {
  apps: [
    {
      name: 'edict-gateway',
      script: '/bin/bash',
      args: '-c "exec /usr/local/bin/openclaw --profile edict36 gateway run --port 18790"',
      watch: false,
      autorestart: true,
      max_restarts: 10,
      restart_delay: 3000,
      env: {
        OPENCLAW_STATE_DIR: '/Users/eskiyin/.openclaw-edict36',
      },
    },
    {
      name: 'edict-dashboard',
      script: 'dashboard/server.py',
      interpreter: 'python3',
      args: '--port 7891',
      cwd: '/Users/eskiyin/Documents/GitHub/edict',
      watch: false,
      autorestart: true,
      max_restarts: 10,
      restart_delay: 2000,
      env: {
        OPENCLAW_STATE_DIR: '/Users/eskiyin/.openclaw-edict36',
      },
    },
    {
      name: 'edict-loop',
      script: 'scripts/run_loop.sh',
      interpreter: 'bash',
      cwd: '/Users/eskiyin/Documents/GitHub/edict',
      watch: false,
      autorestart: true,
      max_restarts: 10,
      restart_delay: 5000,
      env: {
        OPENCLAW_STATE_DIR: '/Users/eskiyin/.openclaw-edict36',
      },
    },
  ],
};
