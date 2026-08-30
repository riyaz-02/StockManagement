/**
 * permissions.js — canonical permission taxonomy for the role/permission
 * system. This is the single source of truth: seeding, validation (reject
 * unknown keys), the /api/permissions/definitions endpoint, and the
 * Flutter Permission Manager screen all read from here.
 *
 * Admin/Owner are NOT represented here — they bypass every check in code
 * (see middleware/auth.js requirePermission). Only Manager/Staff/Viewer
 * have configurable grids.
 *
 * `viewerDefault` marks the keys a Viewer gets by default (read-only
 * capabilities). Everything not marked stays false for Viewer.
 */

const GROUPS = [
    {
        group: 'Items',
        keys: [
            { key: 'items.view', label: 'View items', viewerDefault: true },
            { key: 'items.create', label: 'Create items' },
            { key: 'items.edit', label: 'Edit items' },
            { key: 'items.sell', label: 'Mark items sold' },
            { key: 'items.delete', label: 'Delete items (recycle bin)' },
            { key: 'items.restore', label: 'Restore items from recycle bin' },
            { key: 'items.permanentDelete', label: 'Permanently delete items' },
        ],
    },
    {
        group: 'Containers',
        keys: [
            { key: 'containers.view', label: 'View containers', viewerDefault: true },
            { key: 'containers.create', label: 'Create containers' },
            { key: 'containers.edit', label: 'Edit containers' },
            { key: 'containers.delete', label: 'Delete containers' },
        ],
    },
    {
        group: 'Tally',
        keys: [
            { key: 'tally.view', label: 'View tally sessions', viewerDefault: true },
            { key: 'tally.create', label: 'Start new tally' },
            { key: 'tally.scan', label: 'Scan items during tally' },
            { key: 'tally.addItem', label: 'Add missing item during tally' },
            { key: 'tally.removeItem', label: 'Delete unscanned item during tally' },
            { key: 'tally.lock', label: 'Lock tally' },
            { key: 'tally.updateInventory', label: 'Generate inventory snapshot' },
            { key: 'tally.deleteSession', label: 'Delete a tally session' },
        ],
    },
    {
        group: 'Bookings',
        keys: [
            { key: 'bookings.view', label: 'View bookings', viewerDefault: true },
            { key: 'bookings.create', label: 'Create bookings' },
            { key: 'bookings.edit', label: 'Edit bookings' },
            { key: 'bookings.cancel', label: 'Cancel bookings' },
            { key: 'bookings.complete', label: 'Complete bookings' },
        ],
    },
    {
        group: 'Repair / Outward Movement',
        keys: [
            { key: 'repair.view', label: 'View repair/outward movement history', viewerDefault: true },
            { key: 'repair.send', label: 'Send item to repair/outward movement' },
            { key: 'repair.return', label: 'Return item from repair/outward movement' },
        ],
    },
    {
        group: 'Tag Printing',
        keys: [
            { key: 'tags.print', label: 'Print barcode tags' },
            { key: 'tags.manageSettings', label: 'Manage tag print settings' },
        ],
    },
    {
        group: 'GST / Billing',
        keys: [
            { key: 'gst.viewConfig', label: 'View GST configuration', viewerDefault: true },
            { key: 'gst.editConfig', label: 'Edit GST configuration' },
        ],
    },
    {
        group: 'Purchases',
        keys: [
            { key: 'purchases.view', label: 'View purchases', viewerDefault: true },
            { key: 'purchases.create', label: 'Create purchases' },
            { key: 'purchases.edit', label: 'Edit purchases' },
            { key: 'purchases.delete', label: 'Delete purchases' },
        ],
    },
    {
        group: 'Invoices',
        keys: [
            { key: 'invoices.view', label: 'View invoices', viewerDefault: true },
            { key: 'invoices.create', label: 'Create invoices' },
            { key: 'invoices.edit', label: 'Edit invoices' },
            { key: 'invoices.delete', label: 'Delete invoices' },
        ],
    },
    {
        group: 'Stock (Store Management)',
        keys: [
            { key: 'stock.view', label: 'View stock dashboard/reconciliation', viewerDefault: true },
            { key: 'stock.manageBulkWeights', label: 'Manage bulk weight entries' },
        ],
    },
    {
        group: 'Reports / Analytics',
        keys: [
            { key: 'reports.view', label: 'View reports and analytics', viewerDefault: true },
        ],
    },
    {
        group: 'Settings',
        keys: [
            { key: 'settings.manageItemTypes', label: 'Manage item type/metal/purity settings' },
            { key: 'settings.manageContainerTypes', label: 'Manage container type settings' },
        ],
    },
    {
        group: 'Media',
        keys: [
            { key: 'media.upload', label: 'Upload images' },
        ],
    },
    {
        group: 'Users',
        keys: [
            { key: 'users.manage', label: 'Create/edit/delete users' },
            { key: 'users.resetPassword', label: "Reset another user's password" },
        ],
    },
    {
        group: 'Notifications',
        keys: [
            { key: 'notifications.send', label: 'Send push notifications' },
            { key: 'notifications.viewHistory', label: 'View notification history' },
        ],
    },
    {
        group: 'App Updates',
        keys: [
            { key: 'appUpdate.manage', label: 'Manage app update settings' },
        ],
    },
];

// Flat list of every valid key, for validation.
const ALL_KEY_DEFS = GROUPS.flatMap(g => g.keys);
const ALL_KEYS = ALL_KEY_DEFS.map(k => k.key);

// Keys that stay false by default for Manager/Staff (admin-only in practice).
const ADMIN_ONLY_KEYS = [
    'users.manage',
    'users.resetPassword',
    'notifications.send',
    'notifications.viewHistory',
    'appUpdate.manage',
];

function buildDefaultGrid(role) {
    const grid = {};
    for (const { key, viewerDefault } of ALL_KEY_DEFS) {
        if (role === 'viewer') {
            grid[key] = !!viewerDefault;
        } else {
            // manager & staff: everything except the admin-only set
            grid[key] = !ADMIN_ONLY_KEYS.includes(key);
        }
    }
    return grid;
}

const DEFAULT_GRIDS = {
    manager: buildDefaultGrid('manager'),
    staff: buildDefaultGrid('staff'),
    viewer: buildDefaultGrid('viewer'),
};

module.exports = {
    GROUPS,
    ALL_KEYS,
    ADMIN_ONLY_KEYS,
    DEFAULT_GRIDS,
    CONFIGURABLE_ROLES: ['manager', 'staff', 'viewer'],
};
