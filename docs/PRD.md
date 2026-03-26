# Product Requirements Document (PRD)

## DRRM Emergency Response Platform

**Version:** 1.0
**Date:** March 26, 2026
**Status:** Draft

---

## 1. Executive Summary

The DRRM Emergency Response Platform is a verified, real-time emergency coordination system that connects three user types — Citizens, Departments (e.g., BFP, MDRRMO, PNP), and Municipalities — into a unified platform. It streamlines disaster preparedness, incident reporting, emergency response, and post-disaster recovery through a web and mobile application.

The platform ensures that only verified responders operate within the system, incident reports are automatically categorized and routed to the correct departments, and official information is disseminated through a controlled social media feed to minimize misinformation.

---

## 2. Problem Statement

During emergencies and disasters in the Philippines, coordination between citizens, local government units, and response departments is fragmented. Key problems include:

- **Delayed reporting:** Citizens lack a direct, structured channel to report incidents to the appropriate department.
- **Manual routing:** Incident reports are often sent to the wrong agency, causing delays in response.
- **Misinformation:** Unverified social media posts spread false information during emergencies, causing panic and confusion.
- **No centralized hub:** Post-disaster damage assessments, situational reports, and recovery updates are scattered across multiple channels.
- **Unverified responders:** There is no standardized system to verify that departments and agencies operating during emergencies are legitimate.
- **No inter-department visibility:** When a primary responding unit cannot handle an incident (e.g., the nearest BFP station has no water), there is no real-time way for other departments to see this and step in. Information is relayed manually through phone calls and radio, wasting critical minutes. By the time a backup unit learns they need to respond, it may already be too late.

---

## 3. Goals & Objectives

| Goal | Success Metric |
|------|---------------|
| Reduce incident report routing time | Reports reach the correct department within seconds of submission |
| Ensure responder legitimacy | 100% of active departments are municipality-verified |
| Minimize misinformation | Only verified departments can publish to the public feed |
| Centralize disaster data | All reports, assessments, and updates accessible from one dashboard |
| Improve response tracking | Citizens can track report status in real-time from submission to resolution |
| Enable inter-department coordination | All relevant departments see real-time response status; if no one has responded, the next available unit can immediately step in without waiting for manual relay |

---

## 4. User Roles & Personas

### 4.1 Municipality

The top-level administrative account. Responsible for trust, oversight, and system-wide monitoring.

- Reviews and approves/rejects department registration requests
- Monitors all incident reports system-wide
- Manages system announcements
- Moderates public feed content (optional)
- Views analytics and dashboards

### 4.2 Department (BFP, MDRRMO, PNP, etc.)

Verified emergency response units. They can only operate after Municipality approval.

- Registers and submits verification request
- Receives incident reports routed automatically based on category
- Accepts, responds to, and updates report status
- Posts official announcements, warnings, and safety tips to the public feed
- Uploads damage assessments and situational reports (post-disaster)

### 4.3 Citizen

General public users. The people on the ground.

- Registers a basic account
- Submits incident reports with photo, description, and location
- Tracks report status in real-time
- Browses the public feed for official announcements from verified departments

---

## 5. Core Features

### 5.1 Authentication & Account Management

| Feature | Description |
|---------|-------------|
| User Registration | Separate flows for Citizen and Department accounts |
| Login / Logout | Session-based authentication with secure token management |
| Role-Based Access Control | Three roles: Municipality, Department, Citizen — each with scoped permissions |
| Department Verification Workflow | Departments submit verification request → Municipality reviews → Approve/Reject |
| Profile Management | Basic info for Citizens; department details, contact info, and area of responsibility for Departments |

### 5.2 Municipality Dashboard

Accessible only by Municipality accounts.

- Department verification queue (approve / reject with reason)
- List of all registered and verified departments
- System-wide incident report overview with filters (type, status, date, location)
- Analytics dashboard (report volume, response times, department activity)
- System announcement management

### 5.3 Department Panel

Accessible only by verified Department accounts.

- **Category-Filtered Incident Board:** Reports are auto-categorized (e.g., "Fire") and broadcast to all departments of the matching type (e.g., all BFP stations see fire reports, all PNP units see road accident reports). Departments are NOT flooded with irrelevant reports.
- **Accept / Decline System:** Departments can Accept a report (committing to respond) or Decline with a reason (e.g., "No water supply", "Units already deployed elsewhere", "Out of jurisdiction").
- **Inter-Department Visibility:** All departments within the same category can see which sibling departments have accepted, declined (with reason), or not yet responded to a report. If a report has no responder, any available department of that type knows they need to step in immediately.
- **Report Status Flow:** `Pending` → `Accepted` → `Responding` → `Resolved`
- **Escalation Awareness:** Reports that remain in "Pending" with multiple declines are visually flagged as urgent/unattended. If all departments of the primary category decline, the report escalates and becomes visible to broader department types (e.g., MDRRMO as a catch-all).
- Announcement / post creation (warnings, safety tips, situational updates)
- Damage assessment upload (post-disaster)
- Department profile management

### 5.4 Citizen Interface

- Incident report submission form:
  - Photo upload (required)
  - Description field (required)
  - Location via GPS auto-detect or manual pin (optional with fallback)
- Report history with real-time status tracking
- Public feed browsing (announcements from departments)
- Basic profile management

### 5.5 Incident Reporting & Routing Engine

This is the core system logic. Reports are **auto-categorized, then broadcast to all departments of the matching type** — not routed to a single department. Within that category, any department can accept or decline.

| Component | Description |
|-----------|-------------|
| Report Submission | Structured form with image, description, and geolocation |
| Image Upload Handling | Accepts common image formats (JPEG, PNG); stored in Supabase Storage |
| Auto-Categorization | Classifies incident type based on text input and/or image analysis (e.g., fire, flood, road accident, medical emergency) |
| Category-Based Routing | System maps the category to the relevant department type (fire → BFP, road accident → PNP, medical → medical units, etc.) and broadcasts to ALL departments of that type |
| Accept / Decline Workflow | Any department of the matching type can Accept (takes ownership) or Decline with a reason. Multiple departments can accept the same report for coordinated response. |
| Inter-Department Visibility | All departments of the same type see a live list of who has accepted, declined (with reason), or not yet responded to each report |
| Escalation Flagging | If no department of the primary type accepts (or all decline), the report escalates and becomes visible to broader department types (e.g., MDRRMO, Municipality) |
| Status Tracking | Full lifecycle tracking from submission to resolution |

**Category-to-Department Mapping:**

| Report Category | Routed To |
|----------------|-----------|
| Fire | All BFP stations |
| Flood | All MDRRMO units |
| Earthquake | All MDRRMO units |
| Road Accident | All PNP / traffic units |
| Medical Emergency | All medical / rescue units |
| Structural Damage | All engineering / MDRRMO units |
| Other | MDRRMO (default catch-all) |

### 5.6 Social Media / Information Dissemination Feed

A controlled public information feed designed to combat misinformation.

- Only verified departments can create posts
- Post types: Alerts, Warnings, Safety Tips, Situational Updates
- Citizens can view and interact (view, react, comment — scope TBD)
- Municipality can moderate content (optional)
- Chronological feed with category filters

### 5.7 Notification & Alert System

| Trigger | Recipient | Channel |
|---------|-----------|---------|
| New incident report submitted | Relevant Department(s) | In-app notification |
| Report status updated | Reporting Citizen | In-app notification |
| New announcement posted | All Citizens | In-app feed update |
| Department verification decision | Requesting Department | In-app notification |
| Optional expansion | All relevant users | Push notification / SMS |

### 5.8 Dashboard & Analytics

For Municipality and Department decision-making.

- Incident overview by type, status, and location
- Department activity tracking (reports handled, response times)
- Report volume statistics over time
- Response time metrics per department
- Visual graphs and charts (bar, line, pie)

---

## 6. Tech Stack

### 6.1 Frontend — Web

| Layer | Technology |
|-------|-----------|
| Framework | React (with Vite) |
| UI Library | shadcn/ui |
| Styling | Tailwind CSS |
| State Management | React Context / Zustand (TBD) |
| HTTP Client | Axios or Fetch API |
| Routing | React Router |
| Maps | Leaflet or Mapbox GL JS |

### 6.2 Frontend — Mobile

| Layer | Technology |
|-------|-----------|
| Framework | Flutter |
| State Management | Riverpod or Provider |
| HTTP Client | Dio |
| Maps | Google Maps Flutter / flutter_map |
| Camera / Image Picker | image_picker package |
| Push Notifications | Firebase Cloud Messaging (FCM) |

### 6.3 Backend

| Layer | Technology |
|-------|-----------|
| Framework | Flask (Python) |
| API Style | RESTful API |
| Authentication | Supabase Auth (JWT-based) |
| File Uploads | Supabase Storage |
| AI/ML Categorization | Python ML libraries (scikit-learn, or Hugging Face model for Filipino text) |
| Task Queue | Celery + Redis (optional, for async processing) |

### 6.4 Database & Infrastructure

| Layer | Technology |
|-------|-----------|
| Database | Supabase (PostgreSQL) |
| Object Storage | Supabase Storage (incident photos, attachments) |
| Real-time | Supabase Realtime (live status updates, notifications) |
| Hosting (Backend) | TBD (Railway, Render, or VPS) |
| Hosting (Frontend) | Vercel or Netlify |

---

## 7. Data Models

### 7.1 Users

```
users
├── id (UUID, PK)
├── email (string, unique)
├── password_hash (string)
├── role (enum: citizen, department, municipality)
├── full_name (string)
├── phone (string, nullable)
├── avatar_url (string, nullable)
├── is_verified (boolean, default false)
├── created_at (timestamp)
└── updated_at (timestamp)
```

### 7.2 Departments

```
departments
├── id (UUID, PK)
├── user_id (FK → users.id)
├── name (string) — e.g., "BFP Quezon City"
├── type (enum: fire, police, medical, disaster, rescue, other)
├── description (text)
├── contact_number (string)
├── address (string)
├── area_of_responsibility (string)
├── verification_status (enum: pending, approved, rejected)
├── verified_by (FK → users.id, nullable)
├── verified_at (timestamp, nullable)
├── rejection_reason (string, nullable)
├── created_at (timestamp)
└── updated_at (timestamp)
```

### 7.3 Incident Reports

```
incident_reports
├── id (UUID, PK)
├── reporter_id (FK → users.id)
├── title (string)
├── description (text)
├── category (enum: fire, flood, earthquake, road_accident, medical, structural, other)
├── severity (enum: low, medium, high, critical)
├── status (enum: pending, accepted, responding, resolved, rejected)
├── latitude (float, nullable)
├── longitude (float, nullable)
├── address (string, nullable)
├── image_urls (string array)
├── is_escalated (boolean, default false) — flagged when no department has accepted
├── resolved_at (timestamp, nullable)
├── created_at (timestamp)
└── updated_at (timestamp)
```

**Note:** Reports are NOT assigned to a single department. Instead, they are broadcast to all departments of the matching type (based on auto-categorization) and each responds via the `department_responses` table below.

### 7.4 Department Responses

This is the core table that enables inter-department coordination. Each row represents one department's response decision on one report.

```
department_responses
├── id (UUID, PK)
├── report_id (FK → incident_reports.id)
├── department_id (FK → departments.id)
├── action (enum: accepted, declined)
├── decline_reason (string, nullable) — e.g., "No water supply", "Units deployed elsewhere"
├── responded_at (timestamp)
├── notes (text, nullable)
└── created_at (timestamp)
```

**How it works:**
- When a citizen submits a report, the system auto-categorizes it (e.g., "Fire").
- The report is broadcast to all departments of the matching type (e.g., all BFP stations).
- Each station can Accept or Decline (with reason).
- All departments of that type can see the full list of responses in real-time:
  - "BFP Station 1 — Declined (No water supply)"
  - "BFP Station 3 — Accepted"
  - "BFP Station 2 — No response yet"
- If all departments of the primary type decline or no one accepts after a threshold, the report escalates to broader types (e.g., MDRRMO) and the Municipality is notified.
- Multiple departments can accept the same report for coordinated response.

### 7.5 Report Status History

```
report_status_history
├── id (UUID, PK)
├── report_id (FK → incident_reports.id)
├── old_status (enum)
├── new_status (enum)
├── changed_by (FK → users.id)
├── notes (text, nullable)
└── created_at (timestamp)
```

### 7.5 Posts (Social Feed)

```
posts
├── id (UUID, PK)
├── department_id (FK → departments.id)
├── author_id (FK → users.id)
├── title (string)
├── content (text)
├── category (enum: alert, warning, safety_tip, update, situational_report)
├── image_urls (string array, nullable)
├── is_pinned (boolean, default false)
├── created_at (timestamp)
└── updated_at (timestamp)
```

### 7.6 Notifications

```
notifications
├── id (UUID, PK)
├── user_id (FK → users.id)
├── type (enum: report_update, new_report, verification_decision, announcement)
├── title (string)
├── message (text)
├── reference_id (UUID, nullable) — links to report/post/department
├── reference_type (string, nullable)
├── is_read (boolean, default false)
├── created_at (timestamp)
└── read_at (timestamp, nullable)
```

### 7.7 Damage Assessments (Post-Disaster)

```
damage_assessments
├── id (UUID, PK)
├── department_id (FK → departments.id)
├── author_id (FK → users.id)
├── title (string)
├── description (text)
├── affected_area (string)
├── damage_level (enum: minor, moderate, severe, critical)
├── casualties (integer, default 0)
├── displaced_persons (integer, default 0)
├── image_urls (string array, nullable)
├── latitude (float, nullable)
├── longitude (float, nullable)
├── created_at (timestamp)
└── updated_at (timestamp)
```

---

## 8. API Endpoints (Overview)

### Auth
- `POST /api/auth/register` — Register citizen or department
- `POST /api/auth/login` — Login
- `POST /api/auth/logout` — Logout
- `GET /api/auth/me` — Get current user profile

### Users & Profiles
- `GET /api/users/profile` — Get own profile
- `PUT /api/users/profile` — Update profile

### Municipality
- `GET /api/municipality/departments` — List all departments
- `GET /api/municipality/departments/pending` — List pending verification requests
- `PUT /api/municipality/departments/:id/verify` — Approve or reject department
- `GET /api/municipality/reports` — View all reports system-wide
- `GET /api/municipality/analytics` — Dashboard analytics data

### Departments
- `GET /api/departments/profile` — Get department profile
- `PUT /api/departments/profile` — Update department profile
- `GET /api/departments/reports` — Get all reports (live board, visible to all departments)
- `POST /api/departments/reports/:id/accept` — Accept a report (commit to responding)
- `POST /api/departments/reports/:id/decline` — Decline a report (with reason)
- `GET /api/departments/reports/:id/responses` — Get all department responses for a report (who accepted, declined, reason)
- `PUT /api/departments/reports/:id/status` — Update report status (responding, resolved)
- `POST /api/departments/posts` — Create announcement/post
- `POST /api/departments/assessments` — Submit damage assessment

### Incident Reports
- `POST /api/reports` — Submit new incident report (Citizen)
- `GET /api/reports` — Get own reports (Citizen)
- `GET /api/reports/:id` — Get report details with status history
- `POST /api/reports/:id/upload` — Upload images for a report

### Social Feed
- `GET /api/feed` — Get public feed (all users)
- `GET /api/feed/:id` — Get single post details

### Notifications
- `GET /api/notifications` — Get user notifications
- `PUT /api/notifications/:id/read` — Mark notification as read
- `PUT /api/notifications/read-all` — Mark all as read

---

## 9. User Flows

### 9.1 Citizen Submits an Incident Report

```
Citizen opens app
  → Taps "Report Incident"
  → Takes/uploads photo
  → Writes description
  → Location auto-detected (or manual input)
  → Submits report
  → System auto-categorizes (e.g., "Fire")
  → System routes to all departments of matching type (e.g., all BFP stations)
  → Report appears on every BFP station's live board in real-time
  → Citizen sees report status: "Pending"
  → BFP stations decide individually to Accept or Decline
  → Once a station accepts → Status: "Accepted"
  → Station dispatches response → Status: "Responding"
  → Incident resolved → Status: "Resolved"
  → Citizen receives notification at each status change
```

### 9.2 Key Scenario: Inter-Department Coordination (Fire Example)

This is the core differentiator of the platform.

```
A fire breaks out in Barangay X.
  → Citizen submits report with photo + location
  → System auto-categorizes as "Fire"
  → System routes to ALL BFP stations (not PNP, not medical — only fire-relevant departments)

  → BFP Station 1 (nearest) sees the report
     → They have no water supply
     → They DECLINE with reason: "No water supply available"

  → All other BFP stations see in real-time:
     "BFP Station 1 — Declined (No water supply)"
     "BFP Station 2 — No response yet"
     "BFP Station 3 — No response yet"

  → Report is flagged: ⚠️ NO RESPONDER YET

  → BFP Station 3 sees no one has accepted
     → They ACCEPT the report immediately
     → Status updates to "Accepted" → "Responding"

  → Other stations now see:
     "BFP Station 1 — Declined (No water supply)"
     "BFP Station 3 — Accepted ✅"

  → Fire resolved → Status: "Resolved"
  → Total time saved: minutes that would have been lost
    to phone calls, radio relay, and manual coordination

  ESCALATION CASE:
  → If ALL BFP stations decline or no one accepts within a time threshold
  → Report escalates and becomes visible to MDRRMO (catch-all)
  → Municipality is also notified of the unattended emergency
```

**Without this app:** BFP Station 1 can't respond → calls Station 2 → busy → calls Station 3 → explains the situation → Station 3 finally dispatches. Critical minutes wasted.

**With this app:** Every BFP station sees the report and each other's responses in real-time. The moment Station 1 declines, Station 3 already knows and can act immediately. No phone calls. No relay. No wasted time.

### 9.2 Department Registration & Verification

```
Department representative opens app
  → Registers with department details
  → Account created with status: "Pending Verification"
  → Municipality receives verification request
  → Municipality reviews department info
  → Municipality approves → Department status: "Approved"
  → Department can now receive reports and post to feed
  (OR)
  → Municipality rejects with reason → Department status: "Rejected"
  → Department can update info and re-submit
```

### 9.4 Department Responds to a Report

```
New report appears on department's live incident board
  → Department opens report details (photo, description, location on map)
  → Department sees response status from other departments
  → Decision:
     ACCEPT → Department commits to responding
       → Updates status: "Responding"
       → Adds notes/updates as needed
       → Incident resolved → Updates status: "Resolved"
       → Citizen and other departments notified at each step
     DECLINE → Provides reason (e.g., "No resources available")
       → Decline reason visible to all other departments in real-time
       → Other departments can step in
```

### 9.4 Department Posts an Announcement

```
Department opens "Create Post"
  → Selects post category (Alert, Warning, Safety Tip, Update)
  → Writes title and content
  → Optionally attaches image
  → Publishes to public feed
  → All citizens can view in their feed
```

### 9.5 Post-Disaster: Damage Assessment

```
Department opens "Damage Assessment"
  → Fills out affected area, damage level, casualties, displaced persons
  → Uploads photos of damage
  → Submits assessment
  → Municipality can view all assessments in dashboard
  → Data contributes to recovery planning analytics
```

---

## 10. Auto-Categorization Logic

The system uses a combination of keyword matching and optional ML to classify incident reports.

### Rule-Based (MVP)

| Category | Keywords / Triggers |
|----------|-------------------|
| Fire | fire, sunog, blaze, smoke, usok, burning |
| Flood | flood, baha, rising water, submerged, tubig |
| Earthquake | earthquake, lindol, shaking, collapsed, gumuho |
| Road Accident | accident, car crash, vehicular, banggaan, nasagasaan |
| Medical Emergency | medical, injured, sugatan, unconscious, hinimatay, bleeding |
| Structural Damage | collapsed building, crack, sira, gumiba, landslide |

### ML-Enhanced (Stretch Goal)

- Use a Filipino-language NLP model (e.g., `jcblaise/roberta-tagalog-base` from Hugging Face) to classify report descriptions
- Optional image classification using a lightweight model to detect fire, flood, etc.
- Confidence scoring: if below threshold, flag for manual categorization by department

---

## 11. Non-Functional Requirements

| Requirement | Target |
|-------------|--------|
| Performance | API response time < 500ms for standard operations |
| Scalability | Support up to 10,000 concurrent users per municipality |
| Availability | 99.5% uptime target |
| Security | HTTPS everywhere, password hashing (bcrypt), JWT auth with expiry, input sanitization |
| Data Privacy | Comply with Philippine Data Privacy Act (RA 10173); user data encrypted at rest |
| Image Upload Limits | Max 5MB per image, max 3 images per report |
| Mobile Responsiveness | Web app fully responsive on tablets and phones |
| Real-time Updates | Report status changes reflected within 2 seconds via Supabase Realtime |
| Localization | Support English and Filipino (Tagalog) for UI labels |

---

## 12. Security Considerations

- Password hashing using bcrypt
- JWT-based authentication with refresh tokens
- Role-based middleware on all protected routes
- Input validation and sanitization on all forms
- Rate limiting on report submission to prevent spam / fake reports
- Image upload validation (file type, size, malware scan if feasible)
- Supabase Row-Level Security (RLS) policies for database access
- CORS configuration for API endpoints
- Anti-spam measures: cooldown period between report submissions per user

---

## 13. Out of Scope (v1)

The following are explicitly excluded from the initial build:

- Bluetooth mesh networking (handled by another team)
- SMS / push notification integration (stretch goal)
- Citizen-to-citizen messaging
- Multi-municipality support (v1 is single municipality)
- Payment or donation features
- Advanced AI image recognition (v1 uses rule-based categorization)
- Native desktop application
- Offline-first functionality (assumes internet connectivity)

---

## 14. Milestones & Phases

### Phase 1 — Core Foundation

- Authentication system (registration, login, role-based access)
- Municipality dashboard (department verification)
- Citizen report submission (photo + description + location)
- Basic report routing (manual category selection as fallback)
- Report status tracking

### Phase 2 — Department & Feed

- Department panel (receive, manage, update reports)
- Social media feed (department posts, citizen browsing)
- Notification system (in-app)
- Auto-categorization (rule-based keyword matching)

### Phase 3 — Analytics & Polish

- Dashboard analytics (charts, response metrics, report volume)
- Damage assessment module
- Report status history timeline
- UI/UX polish and mobile optimization
- Filipino language support

### Phase 4 — Stretch Goals

- ML-based auto-categorization (Filipino NLP model)
- Image-based classification
- Push notifications (FCM)
- Content moderation tools for Municipality
- Map-based incident visualization

---

## 15. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Fake/spam reports overwhelming the system | High | Rate limiting, report verification by departments, cooldown periods |
| No department accepts a report | Critical | Escalation flagging after threshold (time or decline count); Municipality notified; visual urgency indicators on all department boards |
| Misinformation on the feed | High | Only verified departments can post; optional Municipality moderation |
| Slow auto-categorization accuracy | Medium | Fallback to manual category selection by citizen; department can re-categorize |
| Supabase free tier limits | Medium | Monitor usage; optimize queries and storage; upgrade plan if needed |
| Low department adoption | Medium | Simple onboarding flow; minimal training required |
| Location accuracy issues | Low | Allow manual location input as fallback; address field option |

---

## 16. Appendix

### A. Report Status Flow

```
                          ┌──────────────────────────────────────────┐
                          │         DEPARTMENT RESPONSES             │
                          │  (per-department, visible to everyone)   │
                          │                                          │
                          │  ┌──────────┐         ┌──────────────┐  │
                          │  │ Accepted │         │ Declined     │  │
                          │  │          │         │ (with reason)│  │
                          │  └──────────┘         └──────────────┘  │
                          └──────────────────────────────────────────┘

┌─────────┐     ┌──────────┐     ┌────────────┐     ┌──────────┐
│ Pending  │ ──► │ Accepted │ ──► │ Responding │ ──► │ Resolved │
└─────────┘     └──────────┘     └────────────┘     └──────────┘
      │
      ▼ (if no one accepts)
┌─────────────┐
│ ⚠️ Escalated │
└─────────────┘
```

- **Pending:** Report submitted, broadcast to all departments of the matching category. No one has accepted yet.
- **Accepted:** At least one department has accepted and committed to respond.
- **Responding:** Department is actively dispatching / on-scene.
- **Resolved:** Incident handled and closed.
- **Escalated:** All departments of the primary category declined or no one accepted within the time threshold. Report becomes visible to broader department types (e.g., MDRRMO) and Municipality is notified.

### B. Department Verification Flow

```
┌─────────┐     ┌──────────┐     ┌──────────┐
│ Pending  │ ──► │ Approved │ ──► │  Active  │
└─────────┘     └──────────┘     └──────────┘
      │                                
      ▼                                
┌──────────┐                           
│ Rejected │ ──► Can resubmit          
└──────────┘                           
```

### C. Tech Stack Summary

```
Frontend (Web):   React + Vite + shadcn/ui + Tailwind CSS
Frontend (Mobile): Flutter
Backend:          Flask (Python)
Database:         Supabase (PostgreSQL)
Storage:          Supabase Storage
Real-time:        Supabase Realtime
Auth:             Supabase Auth
```
