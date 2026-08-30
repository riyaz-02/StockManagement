const { exec } = require('child_process');
const logger = require('./logger');

const toPositiveInteger = (value) => {
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : 0;
};

const createIdleShutdown = () => {
  const idleMinutes = toPositiveInteger(process.env.AUTO_STOP_AFTER_IDLE_MINUTES);
  const shutdownCommand = (process.env.AUTO_STOP_COMMAND || '').trim();

  if (!idleMinutes) {
    return {
      middleware: (req, res, next) => next(),
      start: () => {},
    };
  }

  if (!shutdownCommand) {
    logger.warn(
      '[IdleShutdown] AUTO_STOP_AFTER_IDLE_MINUTES is set, but AUTO_STOP_COMMAND is empty. Auto-stop is disabled.'
    );
    return {
      middleware: (req, res, next) => next(),
      start: () => {},
    };
  }

  const idleMs = idleMinutes * 60 * 1000;
  const checkMs = Math.min(Math.max(Math.floor(idleMs / 3), 60 * 1000), 5 * 60 * 1000);
  let lastActivityAt = Date.now();
  let shutdownStarted = false;

  const middleware = (req, res, next) => {
    if (req.path.startsWith('/api/')) {
      lastActivityAt = Date.now();
    }
    next();
  };

  const start = () => {
    logger.info(`[IdleShutdown] Enabled: stopping after ${idleMinutes} idle minute(s).`);

    const timer = setInterval(() => {
      if (shutdownStarted) return;

      const idleForMs = Date.now() - lastActivityAt;
      if (idleForMs < idleMs) return;

      shutdownStarted = true;
      logger.warn(`[IdleShutdown] Idle for ${Math.round(idleForMs / 1000)}s. Running auto-stop command.`);

      exec(shutdownCommand, (error, stdout, stderr) => {
        if (stdout) logger.info(`[IdleShutdown] ${stdout.trim()}`);
        if (stderr) logger.warn(`[IdleShutdown] ${stderr.trim()}`);
        if (error) {
          shutdownStarted = false;
          lastActivityAt = Date.now();
          logger.error(`[IdleShutdown] Auto-stop command failed: ${error.message}`);
        }
      });
    }, checkMs);

    if (timer.unref) timer.unref();
  };

  return { middleware, start };
};

module.exports = { createIdleShutdown };
