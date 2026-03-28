// App router — role-based route guards with Phase 2 department, feed, and notification routes.

import { BrowserRouter, Navigate, Route, Routes } from "react-router-dom";

import { ProtectedRoute } from "@/lib/auth/protected-route";
import { LoginPage } from "@/pages/auth/login-page";
import { RegisterPage } from "@/pages/auth/register-page";
import { CitizenHomePage } from "@/pages/citizen/citizen-home-page";
import { CitizenReportFormPage } from "@/pages/citizen/citizen-report-form-page";
import { CitizenReportDetailPage } from "@/pages/citizen/citizen-report-detail-page";
import { DepartmentHomePage } from "@/pages/department/department-home-page";
import { DepartmentReportsPage } from "@/pages/department/department-reports-page";
import { DepartmentReportDetailPage } from "@/pages/department/department-report-detail-page";
import { DepartmentCreatePostPage } from "@/pages/department/department-create-post-page";
import { MunicipalityHomePage } from "@/pages/municipality/municipality-home-page";
import { MunicipalityVerificationPage } from "@/pages/municipality/municipality-verification-page";
import { MunicipalityDepartmentsPage } from "@/pages/municipality/municipality-departments-page";
import { MunicipalityEscalatedReportsPage } from "@/pages/municipality/municipality-escalated-reports-page";
import { FeedPage } from "@/pages/shared/feed-page";
import { FeedDetailPage } from "@/pages/shared/feed-detail-page";
import { LandingPage } from "@/pages/shared/landing-page";
import { NotFoundPage } from "@/pages/shared/not-found-page";
import { NotificationsPage } from "@/pages/shared/notifications-page";
import { ProfilePage } from "@/pages/shared/profile-page";

export function AppRouter() {
  return (
    <BrowserRouter>
      <Routes>
        <Route element={<LandingPage />} path="/" />
        <Route element={<FeedPage />} path="/feed" />
        <Route element={<FeedDetailPage />} path="/feed/:postId" />
        <Route element={<LoginPage />} path="/auth/login" />
        <Route element={<RegisterPage />} path="/auth/register" />

        <Route element={<ProtectedRoute allowedRoles={["citizen"]} />}>
          <Route element={<CitizenHomePage />} path="/citizen" />
          <Route element={<CitizenReportFormPage />} path="/citizen/report/new" />
          <Route element={<CitizenReportDetailPage />} path="/citizen/report/:reportId" />
        </Route>

        <Route element={<ProtectedRoute allowedRoles={["department"]} />}>
          <Route element={<DepartmentHomePage />} path="/department" />
          <Route element={<DepartmentReportsPage />} path="/department/reports" />
          <Route element={<DepartmentReportDetailPage />} path="/department/reports/:reportId" />
          <Route element={<DepartmentCreatePostPage />} path="/department/posts/new" />
        </Route>

        <Route element={<ProtectedRoute allowedRoles={["municipality"]} />}>
          <Route element={<MunicipalityHomePage />} path="/municipality" />
          <Route element={<MunicipalityEscalatedReportsPage />} path="/municipality/reports/escalated" />
          <Route element={<MunicipalityVerificationPage />} path="/municipality/verification" />
          <Route element={<MunicipalityDepartmentsPage />} path="/municipality/departments" />
        </Route>

        <Route element={<ProtectedRoute />}>
          <Route element={<ProfilePage />} path="/profile" />
          <Route element={<NotificationsPage />} path="/notifications" />
        </Route>

        <Route element={<Navigate replace to="/" />} path="/auth" />
        <Route element={<NotFoundPage />} path="*" />
      </Routes>
    </BrowserRouter>
  );
}
