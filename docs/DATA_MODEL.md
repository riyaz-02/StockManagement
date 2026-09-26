# Data model (essentials)

**Primary DB** (`jewellery_stock` / `_dev`): users, items, containers, tallies, bookings, repairs, purchases, etc. (Mongoose models in `backend/models/`), plus app-owned:
`app_request_locks` (idempotency) · `app_audit_log` · `app_gst_settings` · `app_gst_filings` · `app_gst_reminder_log` · `app_gst_documents` · `app_branches` · `app_customer_profiles`.

**Branches:** `app_branches` (name, prefix, state, optional own `gstin`), `users.branchId`. Stock/ops models (Item, Container, TallySession, Booking, RepairLog, OutwardMovement, InventorySnapshot, Sale, Purchase, StockEntry, BulkWeight) carry `branchId` (missing = `main`), stamped and filtered automatically by `utils/branchScope.js`. Invoices carry `branch_id`/`branch_name`. **Registrations** (`services/registrations.js`): the default GSTIN covers main + branches without a GSTIN; a branch with its own valid GSTIN is a separate registration. `app_gst_settings.key` = `main` | `gstin:<GSTIN>`; `app_gst_filings.gstin` ('' = default) with unique (gstin, returnType, period).

**shopmanage DB** (website's, **prod is read + guarded insert only**): `invoices` (snake_case), `shop_info` (numbering counters, seller GSTIN/state).
Invoice fields the app writes beyond the website's: `discount_mode` ("before_gst" | "after_gst"), `discount_given`, `discount_before_gst`, `gross_taxable`, `bill_before_discount`, `metal_value`, `gst_type` (CGST_SGST | IGST), `seller_gstin`, `supply_state_code`, `additional_charges_gst`, `payments[]`/`payment_history`. Line fields: `certification`, `hallmark_charge`, `huid`, `item_name`, `extras`, `stone_charge`, `purity`, `gross_wt`, `product_code`, `item_id`.
Item optional billing detail: `grossWeight`, `lessWeight`, `stoneValue`, `stoneNote`, `makingCharge`, `supplier`, `size` (null/'' = not set). Conversion doc↔API shape: `services/billingView.js` (`toView`, `toRow`).

**LGP admin cluster**: user/customer directory, read+insert only in prod.

Legacy invoices (website-made) use `discount_mode` absent → treated as `after_gst`; never rewrite them.
