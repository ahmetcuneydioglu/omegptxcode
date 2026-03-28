const { requireAuth } = require('./auth');
const { ADMIN_PANEL_PASSWORD } = require('../config/env');

function requireAdmin(req, res, next) {
  if (req.auth?.role === 'admin') {
    return next();
  }
  return res.status(403).json({ error: 'Admin yetkisi gerekli' });
}

function requireAdminAccess(req, res, next) {
  const headerPassword = String(req.headers['x-admin-password'] || '').trim();
  if (headerPassword && headerPassword === ADMIN_PANEL_PASSWORD) {
    req.auth = {
      userId: 'admin-panel',
      role: 'admin',
      email: null,
    };
    return next();
  }

  return requireAuth(req, res, () => requireAdmin(req, res, next));
}

module.exports = {
  requireAdmin,
  requireAdminAccess,
};
