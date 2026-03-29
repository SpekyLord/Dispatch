import { useEffect, useRef, useState, type ReactNode } from "react";
import { Link } from "react-router-dom";

import { cn } from "@/lib/utils";

export type FeedDepartmentPreview = {
  id: string;
  name: string;
  type: string;
  profile_picture?: string | null;
  description?: string | null;
  address?: string | null;
  area_of_responsibility?: string | null;
  contact_number?: string | null;
  verification_status?: string | null;
};

function formatDepartmentType(value?: string | null) {
  if (!value) {
    return "Department";
  }
  return value
    .split("_")
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

function formatHandle(name?: string | null) {
  if (!name) {
    return "@department";
  }
  return `@${name.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "")}`;
}

function compactText(value?: string | null, fallback = "Not yet provided.") {
  const trimmed = value?.trim();
  if (!trimmed) {
    return fallback;
  }
  return trimmed.length > 88 ? `${trimmed.slice(0, 85).trimEnd()}...` : trimmed;
}

function compactSecondaryLine(department: FeedDepartmentPreview) {
  const parts = [
    formatDepartmentType(department.type),
    department.area_of_responsibility?.trim(),
    department.address?.trim(),
  ].filter(Boolean);
  return parts.join(" | ");
}

type DepartmentHoverPreviewProps = {
  department?: FeedDepartmentPreview | null;
  children: ReactNode;
  className?: string;
  panelClassName?: string;
  profilePath?: string;
};

export function DepartmentHoverPreview({
  department,
  children,
  className,
  panelClassName,
  profilePath,
}: DepartmentHoverPreviewProps) {
  const [isVisible, setIsVisible] = useState(false);
  const hoverTimeoutRef = useRef<number | null>(null);

  if (!department) {
    return <div className={className}>{children}</div>;
  }

  const coverage = compactText(
    department.area_of_responsibility || department.address,
    "Coverage area pending update.",
  );
  const verificationLabel =
    department.verification_status === "approved"
      ? "Verified department"
      : department.verification_status
        ? `${department.verification_status.replace("_", " ")} status`
        : "Profile preview";

  function handleMouseEnter() {
    if (hoverTimeoutRef.current) {
      window.clearTimeout(hoverTimeoutRef.current);
    }
    hoverTimeoutRef.current = window.setTimeout(() => {
      setIsVisible(true);
      hoverTimeoutRef.current = null;
    }, 1000);
  }

  function handleMouseLeave() {
    if (hoverTimeoutRef.current) {
      window.clearTimeout(hoverTimeoutRef.current);
      hoverTimeoutRef.current = null;
    }
    setIsVisible(false);
  }

  useEffect(() => {
    return () => {
      if (hoverTimeoutRef.current) {
        window.clearTimeout(hoverTimeoutRef.current);
      }
    };
  }, []);

  return (
    <div
      className={cn("group/publisher relative", className)}
      onMouseEnter={handleMouseEnter}
      onMouseLeave={handleMouseLeave}
    >
      <div
        className={cn(
          "transition-all duration-200 ease-out",
          isVisible ? "opacity-80" : "opacity-100",
        )}
      >
        {children}
      </div>

      <div
        className={cn(
          "absolute top-full z-40 hidden w-[352px] max-w-[calc(100vw-2rem)] pt-3 md:block",
          isVisible ? "pointer-events-auto" : "pointer-events-none",
          panelClassName ?? "left-0",
        )}
      >
        <div
          className={cn(
            "rounded-[24px] border border-[#ecd8cf] bg-[#fffdf8] p-5 shadow-[0_20px_40px_rgba(56,56,49,0.1)] transition-all duration-200 ease-out",
            isVisible
              ? "translate-y-0 scale-100 opacity-100"
              : "translate-y-2 scale-[0.98] opacity-0",
          )}
        >
          <div className="flex items-start justify-between gap-4">
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2">
                <p className="truncate font-headline text-[1.55rem] leading-[1.05] text-on-surface">
                  {department.name}
                </p>
                {department.verification_status === "approved" && (
                  <span className="material-symbols-outlined text-[18px] text-[#a14b2f]">
                    verified
                  </span>
                )}
              </div>
              <p className="mt-1 text-xs font-medium text-on-surface-variant">
                {formatHandle(department.name)}
              </p>
            </div>
            <div className="flex h-14 w-14 shrink-0 items-center justify-center overflow-hidden rounded-full border border-[#ecd8cf] bg-[#f7efe7]">
              {department.profile_picture ? (
                <img
                  alt={`${department.name} profile`}
                  className="h-full w-full object-cover"
                  src={department.profile_picture}
                />
              ) : (
                <span className="material-symbols-outlined text-[#a14b2f]">shield_person</span>
              )}
            </div>
          </div>

          <p className="mt-4 text-sm leading-relaxed text-on-surface-variant">
            {compactText(
              department.description,
              "This publisher has not added a public description yet.",
            )}
          </p>

          <div className="mt-4 flex gap-3">
            {profilePath ? (
              <Link
                className="flex-1 rounded-xl bg-[#a14b2f] px-4 py-2.5 text-center text-sm font-semibold text-white"
                to={profilePath}
              >
                View Profile
              </Link>
            ) : (
              <button
                className="flex-1 rounded-xl bg-[#a14b2f] px-4 py-2.5 text-sm font-semibold text-white"
                type="button"
              >
                View Profile
              </button>
            )}
            <button
              className="flex-1 rounded-xl border border-[#ecd8cf] bg-[#fff8f3] px-4 py-2.5 text-sm font-semibold text-on-surface"
              type="button"
            >
              Message
            </button>
          </div>

          <div className="mt-4 rounded-2xl border border-[#ecd8cf] bg-[#f9f3ed] p-3.5">
            <div className="flex items-center gap-3">
              <div className="flex h-11 w-11 shrink-0 items-center justify-center overflow-hidden rounded-xl border border-[#ecd8cf] bg-[#fffdf8]">
                {department.profile_picture ? (
                  <img
                    alt={`${department.name} profile`}
                    className="h-full w-full object-cover"
                    src={department.profile_picture}
                  />
                ) : (
                  <span className="material-symbols-outlined text-[#a14b2f]">shield_person</span>
                )}
              </div>
              <div className="min-w-0">
                <p className="truncate text-sm font-semibold text-on-surface">{department.name}</p>
                <p className="truncate text-xs text-on-surface-variant">
                  {compactSecondaryLine(department) || coverage}
                </p>
              </div>
            </div>
          </div>

          <div className="mt-3 flex items-center justify-between text-[11px] text-on-surface-variant">
            <span>{verificationLabel}</span>
            {department.contact_number?.trim() && (
              <span>{department.contact_number}</span>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
