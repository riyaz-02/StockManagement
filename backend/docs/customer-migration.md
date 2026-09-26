# Customer data: LGPAdmin website → new app (migration guide)

The **LGPAdmin website** currently saves customers itself (database
`clusterlgpadmin` on the LGP Atlas cluster, collections `customers` and
`customer_finance`). Later that data moves into the new app. The app was built
so this is a mechanical, repeatable, *insert-only* copy — nothing is edited or
deleted in either system.

> Snapshot when this was written: the `clusterlgpadmin` database on Atlas was
> **empty** (0 collections), so the website's real data may live elsewhere
> (e.g. a local MongoDB). The mapping below comes from the website's source
> (`src/panel/add_customer.php`, `modals/add_customer_modal.php`,
> `includes/db_config.php`). Re-check the real data before running for real.

## How the app stores a customer

| Where | What |
|---|---|
| `shopmanage.customers` (legacy, shared with the older web admin) | Only fields that collection already has: name, Bengali name, address, phones (4 slots), email, nickname, `reference_customer_id`, `anniversaries`, `sl_no`, timestamps. |
| `app_customer_profiles` (new, app-owned) | Everything richer: **`customerCode`**, branch, membership, gender, DOB, full `contacts[]` list, `referredBy`, tax IDs, opening balance, notes… plus `source` / `sourceId` provenance. |
| `app_branches` (app DB) | Branches / shops. `main` is a built-in virtual branch. |

Every new customer gets a **`customerCode` in the website's own format**
(`LGP` + `yymmdd` + 3 hex chars, e.g. `LGP260919A3F`). Migrated customers keep
their original `Customer_ID` as `customerCode`, so IDs never change.

## Field mapping

| LGPAdmin (`customers`) | New app | Notes |
|---|---|---|
| `Customer_ID` | `profile.customerCode` (+ `sourceId`) | Kept verbatim; unique → makes re-runs safe. |
| `Name` | `customers.customer_name` | HTML-decode first (see pitfalls). |
| `Name_Bn` | `customers.customer_name_bengali` | |
| `Nickname` / `Nickname_Bn` | `customers.nickname` / `profile.nicknameBn` | |
| `Gender` (`Male`/`Female`/`Other`) | `profile.gender` | Same values. |
| `Mobile_No1` | `contacts[0]` (WhatsApp) → `customers.whatsapp_no` | Normalised to 10 digits. |
| `Mobile_No2` | `contacts[1]` → `customers.mobile_no` | |
| `Email` | `customers.email` | |
| `Address` / `Address_Bn` | `customers.address` / `profile.addressBn` | |
| `dob` (string `YYYY-MM-DD`) | `profile.dob` (Date) | |
| `Referred_By` (free text) | `profile.referredBy` | Auto-linked when it equals a known `Customer_ID` or a unique mobile; otherwise kept as `referredBy.text`. |
| `Membership_Status` (`Regular`/`VIP`) | `profile.membershipStatus` | Unknown values → `Regular` (reported). |
| `Notes` | `profile.notes` | |
| `profilePic` (S3 URL) | `profile.profilePicUrl` | URL only; files stay in S3. |
| `Account_Creation` | `customers.created_at` | |
| `customer_finance.*` (`Total_Due`, `LGP_Wallet`, `Total_Purchases`, `Last_Payment_Date`) | `app_customer_finance` | Copied 1:1, keyed by `customerId` + `customerCode`. |

## Pitfalls the script already handles

1. **HTML-escaped text.** The website passes every string through
   `htmlspecialchars` *before* saving, so `O'Brien & Sons` is stored as
   `O&#039;Brien &amp; Sons`. The script decodes these. Never copy names raw.
2. **`dob` is a string**, not a date.
3. **Phones**: stored from `<input type="number">`, so leading zeros can be
   lost and formatting varies. Numbers are normalised (`+91`, spaces, leading
   `0` removed). Anything that is not a valid 10-digit number is **not
   dropped**: it goes to the report and into the customer's `notes`.
4. **Duplicates**: a customer whose phone already exists in the target is
   skipped and listed (never merged automatically).
5. **Re-runnable**: `customerCode` is the idempotency key; already-migrated
   customers are skipped.
6. **Serial numbers**: `sl_no` continues from the target's current maximum.
7. **Branch**: everything goes to `main` unless `--branch <id>` is given.

## Running it

Always **dry-run first** (the default — reads only, writes nothing):

```bash
SOURCE_URI="mongodb://…"  SOURCE_DB=clusterlgpadmin \
TARGET_URI="mongodb://…/shopmanage" \
node scripts/migrate-lgpadmin-customers.js --report report.json
```

Review `report.json` (invalid phones, duplicates, unknown memberships), then:

```bash
… node scripts/migrate-lgpadmin-customers.js --apply
```

`--apply` refuses a non-local target unless `--allow-remote` is also passed —
this is a deliberate speed bump for production. Take a backup / Atlas snapshot
before any production run.

## Rules for future changes (so migration stays painless)

* Add new customer fields to the **profile** collection, never to the legacy
  `customers` documents.
* Keep `customerCode` immutable and unique.
* Every record carries `branchId` / `branchName`; legacy data = `main`.
* Keep `source` / `sourceId` on migrated rows.
