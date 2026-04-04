export type Locale = "en" | "fil";

export type MessageParams = Record<string, number | string>;
type MessageValue = string | ((params: MessageParams) => string);

const messages = {
  en: {
    "shell.signOut": "Sign out",
    "shell.signIn": "Sign in",
    "shell.language": "Language",
    "shell.english": "EN",
    "shell.filipino": "FIL",
    "shell.signOutConfirmTitle": "Are you sure you want to sign out?",
    "shell.signOutConfirmBody":
      "You'll be signed out of Dispatch and returned to the home page.",
    "shell.cancel": "Cancel",
    "shell.signingOut": "Signing out...",

    "nav.myReports": "My Reports",
    "nav.newReport": "New Report",
    "nav.feed": "Feed",
    "nav.newsFeed": "News Feed",
    "nav.notifications": "Notifications",
    "nav.profile": "Profile",
    "nav.dashboard": "Dashboard",
    "nav.incidentBoard": "Incident Board",
    "nav.createPost": "Create Post",
    "nav.assessments": "Assessments",
    "nav.overview": "Overview",
    "nav.reports": "Reports",
    "nav.analytics": "Analytics",
    "nav.escalations": "Escalations",
    "nav.verification": "Verification",
    "nav.departments": "Departments",
    "nav.meshSar": "Mesh & SAR",

    "sidebar.citizen.title": "Citizen Hub",
    "sidebar.citizen.subtitle": "Incident Reporting",
    "sidebar.department.title": "Dept. Ops",
    "sidebar.department.subtitle": "Response Command",
    "sidebar.municipality.title": "Municipal Admin",
    "sidebar.municipality.subtitle": "Regional Oversight",

    "reports.title": "All Reports",
    "reports.subtitle": "System-wide incident overview",
    "reports.filter.allStatuses": "All statuses",
    "reports.filter.allCategories": "All categories",
    "reports.filter.allEscalation": "All escalation",
    "reports.filter.escalated": "Escalated",
    "reports.filter.notEscalated": "Not escalated",
    "reports.filter.fromDate": "From date",
    "reports.filter.toDate": "To date",
    "reports.refresh": "Refresh",
    "reports.count": ({ count }) => `${count} report${count === 1 ? "" : "s"}`,
    "reports.loading": "Loading reports...",
    "reports.empty": "No reports match the current filters.",
    "reports.meshBadge": "Mesh",
    "reports.escalatedBadge": "Escalated",

    "analytics.title": "Analytics",
    "analytics.subtitle": "Insights & metrics",
    "analytics.failed": "Failed to load analytics.",
    "analytics.totalReports": "Total Reports",
    "analytics.avgResponse": "Avg Response",
    "analytics.unattended": "Unattended",
    "analytics.resolved": "Resolved",
    "analytics.reportsByStatus": "Reports by Status",
    "analytics.categoryBreakdown": "Category Breakdown",
    "analytics.noCategoryData": "No category data yet.",
    "analytics.departmentActivity": "Department Activity",
    "analytics.noDepartmentActivity": "No department activity recorded.",
    "analytics.department": "Department",
    "analytics.accepts": "Accepts",
    "analytics.declines": "Declines",
    "analytics.refresh": "Refresh Data",

    "assessments.title": "Assessments",
    "assessments.subtitle": "Damage assessment overview",
    "assessments.loading": "Loading assessments...",
    "assessments.empty": "No damage assessments submitted yet.",
    "assessments.byDepartment": ({ name }) => `By ${name}`,
    "assessments.casualties": ({ count }) => `${count} casualties`,
    "assessments.displaced": ({ count }) => `${count} displaced`,
    "assessments.imageAlt": ({ index }) => `Assessment ${index}`,

    "departmentAssessments.title": "Assessments",
    "departmentAssessments.subtitle": "Damage assessment reporting",
    "departmentAssessments.submitTitle": "Submit Assessment",
    "departmentAssessments.error": "Failed to submit assessment.",
    "departmentAssessments.success": "Assessment submitted successfully.",
    "departmentAssessments.affectedArea": "Affected Area",
    "departmentAssessments.damageLevel": "Damage Level",
    "departmentAssessments.estimatedCasualties": "Estimated Casualties",
    "departmentAssessments.displacedPersons": "Displaced Persons",
    "departmentAssessments.location": "Location",
    "departmentAssessments.description": "Description",
    "departmentAssessments.images": "Images (max 3)",
    "departmentAssessments.imagesSelected": ({ count }) =>
      `${count} file${count === 1 ? "" : "s"} selected`,
    "departmentAssessments.submit": "Submit Assessment",
    "departmentAssessments.submitting": "Submitting...",
    "departmentAssessments.previousTitle": "Previous Assessments",
    "departmentAssessments.empty": "No assessments submitted yet.",
    "departmentAssessments.placeholderArea": "e.g. Barangay Centro",
    "departmentAssessments.placeholderLocation": "Address or coordinates",
    "departmentAssessments.placeholderDescription":
      "Describe the damage and conditions...",
    "departmentAssessments.required": "Required",

    "detail.subtitle": "Report details",
    "detail.loadingTitle": "Loading...",
    "detail.errorTitle": "Error",
    "detail.error": "Failed to load report.",
    "detail.notFound": "Report not found.",
    "detail.backToReports": "Back to reports",
    "detail.incidentDetails": "Incident Details",
    "detail.submitted": ({ date }) => `Submitted ${date}`,
    "detail.meshOrigin": "Mesh Origin",
    "detail.escalated": "Escalated",
    "detail.attachedEvidence": "Attached Evidence",
    "detail.reportImageAlt": ({ index }) => `Report image ${index}`,
    "detail.timeline": "Report Timeline",
    "detail.noActivity": "No activity yet.",
    "detail.departmentResponses": "Department Responses",
    "detail.reason": ({ reason }) => `Reason: ${reason}`,
    "detail.noGps": "No GPS coordinates available",
    "detail.summary": "Report Summary",
    "detail.status": "Status",
    "detail.category": "Category",
    "detail.severity": "Severity",
    "detail.escalatedLabel": "Escalated",
    "detail.yes": "Yes",
    "detail.no": "No",
  },
  fil: {
    "shell.signOut": "Mag-sign out",
    "shell.signIn": "Mag-sign in",
    "shell.language": "Wika",
    "shell.english": "EN",
    "shell.filipino": "FIL",
    "shell.signOutConfirmTitle":
      "Sigurado ka bang gusto mong mag-sign out?",
    "shell.signOutConfirmBody":
      "Masa-sign out ka sa Dispatch at ibabalik sa home page.",
    "shell.cancel": "Kanselahin",
    "shell.signingOut": "Nagsa-sign out...",

    "nav.myReports": "Aking Ulat",
    "nav.newReport": "Bagong Ulat",
    "nav.feed": "Feed",
    "nav.newsFeed": "News Feed",
    "nav.notifications": "Mga Abiso",
    "nav.profile": "Profile",
    "nav.dashboard": "Dashboard",
    "nav.incidentBoard": "Lupon ng Insidente",
    "nav.createPost": "Create Post",
    "nav.assessments": "Mga Pagtatasa",
    "nav.overview": "Buod",
    "nav.reports": "Mga Ulat",
    "nav.analytics": "Analitika",
    "nav.escalations": "Mga Eskalasyon",
    "nav.verification": "Beripikasyon",
    "nav.departments": "Mga Departamento",
    "nav.meshSar": "Mesh at SAR",

    "sidebar.citizen.title": "Citizen Hub",
    "sidebar.citizen.subtitle": "Pag-uulat ng Insidente",
    "sidebar.department.title": "Dept. Ops",
    "sidebar.department.subtitle": "Response Command",
    "sidebar.municipality.title": "Municipal Admin",
    "sidebar.municipality.subtitle": "Regional Oversight",

    "reports.title": "Lahat ng Ulat",
    "reports.subtitle": "Pangkalahatang buod ng mga insidente",
    "reports.filter.allStatuses": "Lahat ng status",
    "reports.filter.allCategories": "Lahat ng kategorya",
    "reports.filter.allEscalation": "Lahat ng escalation",
    "reports.filter.escalated": "Na-escalate",
    "reports.filter.notEscalated": "Hindi na-escalate",
    "reports.filter.fromDate": "Petsa mula",
    "reports.filter.toDate": "Petsa hanggang",
    "reports.refresh": "I-refresh",
    "reports.count": ({ count }) => `${count} ulat`,
    "reports.loading": "Nilo-load ang mga ulat...",
    "reports.empty": "Walang ulat na tumutugma sa mga kasalukuyang filter.",
    "reports.meshBadge": "Mesh",
    "reports.escalatedBadge": "Na-escalate",

    "analytics.title": "Analitika",
    "analytics.subtitle": "Mga insight at sukatan",
    "analytics.failed": "Hindi ma-load ang analytics.",
    "analytics.totalReports": "Kabuuang Ulat",
    "analytics.avgResponse": "Karaniwang Tugon",
    "analytics.unattended": "Hindi Natutukan",
    "analytics.resolved": "Nalutas",
    "analytics.reportsByStatus": "Mga Ulat Ayon sa Status",
    "analytics.categoryBreakdown": "Hati ng Kategorya",
    "analytics.noCategoryData": "Wala pang datos ng kategorya.",
    "analytics.departmentActivity": "Aktibidad ng Departamento",
    "analytics.noDepartmentActivity": "Wala pang naitalang aktibidad ng departamento.",
    "analytics.department": "Departamento",
    "analytics.accepts": "Tinanggap",
    "analytics.declines": "Tinanggihan",
    "analytics.refresh": "I-refresh ang Datos",

    "assessments.title": "Mga Pagtatasa",
    "assessments.subtitle": "Pangkalahatang buod ng damage assessment",
    "assessments.loading": "Nilo-load ang mga pagtatasa...",
    "assessments.empty": "Wala pang naisusumiteng damage assessment.",
    "assessments.byDepartment": ({ name }) => `Ni ${name}`,
    "assessments.casualties": ({ count }) => `${count} nasawi`,
    "assessments.displaced": ({ count }) => `${count} lumikas`,
    "assessments.imageAlt": ({ index }) => `Pagtatasa ${index}`,

    "departmentAssessments.title": "Mga Pagtatasa",
    "departmentAssessments.subtitle": "Pag-uulat ng damage assessment",
    "departmentAssessments.submitTitle": "Magsumite ng Pagtatasa",
    "departmentAssessments.error": "Hindi naisumite ang pagtatasa.",
    "departmentAssessments.success": "Matagumpay na naisumite ang pagtatasa.",
    "departmentAssessments.affectedArea": "Apektadong Lugar",
    "departmentAssessments.damageLevel": "Antas ng Pinsala",
    "departmentAssessments.estimatedCasualties": "Tinatayang Nasawi",
    "departmentAssessments.displacedPersons": "Mga Lumikas",
    "departmentAssessments.location": "Lokasyon",
    "departmentAssessments.description": "Paglalarawan",
    "departmentAssessments.images": "Mga Larawan (hanggang 3)",
    "departmentAssessments.imagesSelected": ({ count }) =>
      `${count} file ang napili`,
    "departmentAssessments.submit": "Isumite ang Pagtatasa",
    "departmentAssessments.submitting": "Isinusumite...",
    "departmentAssessments.previousTitle": "Mga Naunang Pagtatasa",
    "departmentAssessments.empty": "Wala pang naisusumiteng pagtatasa.",
    "departmentAssessments.placeholderArea": "hal. Barangay Centro",
    "departmentAssessments.placeholderLocation": "Address o coordinates",
    "departmentAssessments.placeholderDescription":
      "Ilarawan ang pinsala at kalagayan...",
    "departmentAssessments.required": "Kailangan",

    "detail.subtitle": "Detalye ng ulat",
    "detail.loadingTitle": "Nilo-load...",
    "detail.errorTitle": "Error",
    "detail.error": "Hindi ma-load ang ulat.",
    "detail.notFound": "Hindi nakita ang ulat.",
    "detail.backToReports": "Bumalik sa mga ulat",
    "detail.incidentDetails": "Detalye ng Insidente",
    "detail.submitted": ({ date }) => `Isinumite ${date}`,
    "detail.meshOrigin": "Mula sa Mesh",
    "detail.escalated": "Na-escalate",
    "detail.attachedEvidence": "Kalakip na Ebidensiya",
    "detail.reportImageAlt": ({ index }) => `Larawan ng ulat ${index}`,
    "detail.timeline": "Timeline ng Ulat",
    "detail.noActivity": "Wala pang aktibidad.",
    "detail.departmentResponses": "Mga Tugon ng Departamento",
    "detail.reason": ({ reason }) => `Dahilan: ${reason}`,
    "detail.noGps": "Walang available na GPS coordinates",
    "detail.summary": "Buod ng Ulat",
    "detail.status": "Status",
    "detail.category": "Kategorya",
    "detail.severity": "Tindi",
    "detail.escalatedLabel": "Na-escalate",
    "detail.yes": "Oo",
    "detail.no": "Hindi",
  },
} satisfies Record<Locale, Record<string, MessageValue>>;

export type MessageKey = keyof (typeof messages)["en"];

const statusLabels: Record<Locale, Record<string, string>> = {
  en: {
    pending: "Pending",
    accepted: "Accepted",
    responding: "Responding",
    resolved: "Resolved",
    declined: "Declined",
  },
  fil: {
    pending: "Nakabinbin",
    accepted: "Tinanggap",
    responding: "Tumutugon",
    resolved: "Nalutas",
    declined: "Tinanggihan",
  },
};

const categoryLabels: Record<Locale, Record<string, string>> = {
  en: {
    fire: "Fire",
    flood: "Flood",
    earthquake: "Earthquake",
    road_accident: "Road Accident",
    medical: "Medical",
    structural: "Structural",
    other: "Other",
  },
  fil: {
    fire: "Sunog",
    flood: "Baha",
    earthquake: "Lindol",
    road_accident: "Aksidente sa Kalsada",
    medical: "Medikal",
    structural: "Istruktural",
    other: "Iba pa",
  },
};

const damageLevelLabels: Record<Locale, Record<string, string>> = {
  en: {
    minor: "Minor",
    moderate: "Moderate",
    severe: "Severe",
    critical: "Critical",
  },
  fil: {
    minor: "Magaan",
    moderate: "Katamtaman",
    severe: "Malubha",
    critical: "Kritikal",
  },
};

const severityLabels: Record<Locale, Record<string, string>> = {
  en: {
    low: "Low",
    medium: "Medium",
    high: "High",
    critical: "Critical",
  },
  fil: {
    low: "Mababa",
    medium: "Katamtaman",
    high: "Mataas",
    critical: "Kritikal",
  },
};

const responseActionLabels: Record<Locale, Record<string, string>> = {
  en: {
    accepted: "Accepted",
    declined: "Declined",
  },
  fil: {
    accepted: "Tinanggap",
    declined: "Tinanggihan",
  },
};

function fallbackLabel(value: string) {
  return value.replace(/_/g, " ");
}

export function translate(
  locale: Locale,
  key: MessageKey,
  params?: MessageParams,
) {
  const value = messages[locale][key] ?? messages.en[key];
  return typeof value === "function" ? value(params ?? {}) : value;
}

export function getStatusLabel(locale: Locale, status: string) {
  return statusLabels[locale][status] ?? fallbackLabel(status);
}

export function getCategoryLabel(locale: Locale, category: string) {
  return categoryLabels[locale][category] ?? fallbackLabel(category);
}

export function getDamageLevelLabel(locale: Locale, level: string) {
  return damageLevelLabels[locale][level] ?? fallbackLabel(level);
}

export function getSeverityLabel(locale: Locale, severity: string) {
  return severityLabels[locale][severity] ?? fallbackLabel(severity);
}

export function getResponseActionLabel(locale: Locale, action: string) {
  return responseActionLabels[locale][action] ?? fallbackLabel(action);
}
