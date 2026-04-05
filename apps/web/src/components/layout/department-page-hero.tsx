import type { DepartmentInfo } from "@/lib/auth/session-store";

type DepartmentPageHeroProps = {
  eyebrow: string;
  title: string;
  icon: string;
  department?: Pick<DepartmentInfo, "type" | "area_of_responsibility"> | null;
  chips?: string[];
  dataTestId?: string;
  headingTone?: "default" | "soft-light";
};

function formatDepartmentType(value?: string | null) {
  if (!value) {
    return "Department";
  }

  return value
    .replace(/_/g, " ")
    .trim()
    .replace(/\b\w/g, (char) => char.toUpperCase());
}

function resolveHeaderChips({
  department,
  chips,
}: Pick<DepartmentPageHeroProps, "department" | "chips">) {
  if (chips?.length) {
    return chips.filter(Boolean);
  }

  if (!department) {
    return [];
  }

  const coverageLabel =
    department.area_of_responsibility?.trim() || "Municipal coverage";

  return [formatDepartmentType(department.type), coverageLabel];
}

export function DepartmentPageHero({
  eyebrow,
  title,
  icon,
  department,
  chips,
  dataTestId,
  headingTone = "default",
}: DepartmentPageHeroProps) {
  const headerChips = resolveHeaderChips({ department, chips });
  const useSoftLightHeading = headingTone === "soft-light";

  return (
    <section
      className="relative mb-8 overflow-hidden rounded-[32px] bg-[linear-gradient(90deg,#a86549_0%,#c27c58_32%,#d7a37f_70%,#e7d0bb_100%)] p-[1.5px] shadow-[0_22px_46px_-32px_rgba(109,67,45,0.32)]"
      data-testid={dataTestId}
    >
      <div className="relative overflow-hidden rounded-[30px] bg-[linear-gradient(90deg,#bc7756_0%,#cf8b63_34%,#dfae89_72%,#edd9c7_100%)] px-6 py-3 lg:px-8 lg:py-4">
        <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_12%_20%,rgba(86,46,30,0.08),transparent_24%),radial-gradient(circle_at_86%_14%,rgba(248,233,219,0.1),transparent_26%)]" />

        <div className="relative flex flex-col gap-2.5 lg:flex-row lg:items-end lg:justify-between">
          <div className="max-w-3xl">
            <div className="flex items-start gap-2.5 sm:gap-3">
              <span
                className={`material-symbols-outlined mt-0.5 shrink-0 text-[22px] ${
                  useSoftLightHeading ? "text-[#fff2e6]" : "text-[#5a3121]"
                }`}
              >
                {icon}
              </span>

              <div className="min-w-0 flex-1">
                <p
                  className={`mb-1.5 text-xs font-bold uppercase tracking-widest ${
                    useSoftLightHeading ? "text-[#f6eadf]" : "text-[#6a3d2b]"
                  }`}
                >
                  {eyebrow}
                </p>
                <h1
                  className={`font-headline text-4xl font-bold leading-[0.94] tracking-tight lg:text-[3.2rem] ${
                    useSoftLightHeading ? "text-[#fff7f1]" : "text-[#241915]"
                  }`}
                >
                  {title}
                </h1>
                <div
                  className={`mt-1 h-[2px] w-full max-w-[26rem] rounded-full ${
                    useSoftLightHeading
                      ? "bg-[linear-gradient(90deg,rgba(255,247,241,0.82)_0%,rgba(255,247,241,0.34)_54%,rgba(255,247,241,0.06)_100%)]"
                      : "bg-[linear-gradient(90deg,rgba(77,40,26,0.52)_0%,rgba(77,40,26,0.22)_54%,rgba(77,40,26,0.04)_100%)]"
                  }`}
                />
              </div>
            </div>
          </div>

          {headerChips.length > 0 ? (
            <div className="flex flex-wrap gap-2.5">
              {headerChips.map((chip) => (
                <div
                  className="rounded-full border border-[#7d4c36]/20 bg-[#f6e7d9]/18 px-4 py-1 text-[11px] font-semibold uppercase tracking-[0.18em] text-[#241915]"
                  key={chip}
                >
                  {chip}
                </div>
              ))}
            </div>
          ) : null}
        </div>
      </div>
    </section>
  );
}
