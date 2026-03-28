# Report Inputs & Image Constraints

## Required Fields

| Field | Type | Notes |
|---|---|---|
| `description` | text | Non-empty, free-form description of the incident |
| `category` | enum | One of: `fire`, `flood`, `earthquake`, `road_accident`, `medical`, `structural`, `other` |

## Optional Fields

| Field | Type | Default | Notes |
|---|---|---|---|
| `severity` | enum | `medium` | One of: `low`, `medium`, `high`, `critical` |
| `address` | text | null | Free-text address or location description |
| `latitude` | float | null | GPS auto-detect or manual map pin |
| `longitude` | float | null | GPS auto-detect or manual map pin |

## Image Constraints

| Rule | Value |
|---|---|
| Max images per report | 3 |
| Allowed formats | JPEG, PNG |
| Max file size | 5 MB per image |
| Upload method | Separate `POST /api/reports/:id/upload` call per image after report creation |
| Storage | Supabase Storage `report-images` bucket, path: `{user_id}/{domain}/{uuid}.ext` |

## Status Defaults

When a report is created:
- `status` = `pending`
- `is_escalated` = `false`
- An initial `report_status_history` entry is created with `old_status = null`, `new_status = pending`

## Platform Differences

| Feature | Web | Mobile |
|---|---|---|
| GPS auto-detect | `navigator.geolocation` | Geolocator plugin |
| Manual location | Leaflet map pin click | flutter_map LocationPicker tap |
| Image selection | File input (click/drag) | Camera or gallery via ImagePicker |
| Image preview | Grid thumbnails with remove | Horizontal scroll thumbnails with remove |
