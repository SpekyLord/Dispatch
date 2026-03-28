# Phase 1 User Flows

## Citizen Flow

1. **Register** — Choose "Citizen" role, enter full name, email, and password
2. **Login** — Email + password, auto-redirects to citizen dashboard
3. **Submit Report** — Fill description, select category (manual), optionally set severity, add up to 3 photos (JPEG/PNG, max 5 MB each), auto-detect GPS or pin on map, enter address
4. **View Reports** — Report history shows all submitted reports with status badges (pending/accepted/responding/resolved)
5. **View Report Detail** — Full report with description, category, severity, status timeline, uploaded images, and map preview
6. **Edit Profile** — Update full name and phone number

## Department Flow

1. **Register** — Choose "Department" role, enter organization name, department type (fire/police/medical/disaster/rescue/other), contact number, address, area of responsibility, plus email and password
2. **Login** — Email + password
3. **Awaiting Verification** — After registration, the department sees a "Pending Verification" screen. No operational features are accessible.
4. **Approved** — Once the municipality approves, the department sees its verified profile and can access operational features (Phase 2: incident board, accept/decline reports, post announcements)
5. **Rejected** — If rejected, the department sees the rejection reason and can edit its profile fields and resubmit. The API automatically moves the status back to "pending" on profile update.

## Municipality Flow (Web Only)

1. **Login** — Email + password (municipality accounts are seeded, not self-registered)
2. **Dashboard** — Shows pending verification count, total departments
3. **Verification Queue** — View pending department applications with full details
4. **Approve** — One click to approve a department. Sets `verification_status = approved` and `is_verified = true`
5. **Reject** — Click reject, enter a mandatory rejection reason. Sets `verification_status = rejected` with the reason stored

## Approved vs Unapproved Department Behavior

| Capability | Unapproved (pending/rejected) | Approved |
|---|---|---|
| Login | Yes | Yes |
| View own profile/status | Yes | Yes |
| Edit profile (resubmit) | Yes (if rejected) | Yes |
| Access incident board | No (403) | Yes (Phase 2) |
| Accept/decline reports | No (403) | Yes (Phase 2) |
| Create announcements | No (403) | Yes (Phase 2) |

The API enforces this via role guards that check `verification_status = approved` on all department-operational endpoints.
