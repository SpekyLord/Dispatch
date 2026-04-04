export type FeedPostKind = "standard" | "assessment";

export type FeedAssessmentDetails = {
  affected_area: string;
  damage_level: string;
  estimated_casualties: number;
  displaced_persons: number;
  description?: string | null;
};

export const FEED_DAMAGE_LEVEL_OPTIONS = [
  { value: "minor", label: "Minor" },
  { value: "moderate", label: "Moderate" },
  { value: "severe", label: "Severe" },
  { value: "critical", label: "Critical" },
] as const;

export function normalizeFeedPostKind(value?: string | null): FeedPostKind {
  return value === "assessment" ? "assessment" : "standard";
}

export function getAssessmentDamageLevelLabel(value?: string | null) {
  const match = FEED_DAMAGE_LEVEL_OPTIONS.find((option) => option.value === value);
  return match?.label ?? "Minor";
}

export function isAssessmentPost(post: {
  post_kind?: string | null;
  assessment_details?: FeedAssessmentDetails | null;
}) {
  return normalizeFeedPostKind(post.post_kind) === "assessment" && Boolean(post.assessment_details);
}

function getAssessmentDamageTone(value?: string | null) {
  switch (value) {
    case "critical":
      return {
        pillClassName: "bg-[#ffddd6] text-[#8d321e]",
        statAccentClassName: "text-[#8d321e]",
        chartFillClassName: "bg-[linear-gradient(90deg,#ca5a3d_0%,#e88468_100%)]",
        meterColor: "#b6472d",
        meterTrackColor: "rgba(182, 71, 45, 0.14)",
      };
    case "severe":
      return {
        pillClassName: "bg-[#ffe8cf] text-[#9c531d]",
        statAccentClassName: "text-[#9c531d]",
        chartFillClassName: "bg-[linear-gradient(90deg,#d48942_0%,#efb56f_100%)]",
        meterColor: "#c26e1f",
        meterTrackColor: "rgba(194, 110, 31, 0.14)",
      };
    case "moderate":
      return {
        pillClassName: "bg-[#fff1c9] text-[#8b6920]",
        statAccentClassName: "text-[#8b6920]",
        chartFillClassName: "bg-[linear-gradient(90deg,#d8b34e_0%,#ead47e_100%)]",
        meterColor: "#b58b2a",
        meterTrackColor: "rgba(181, 139, 42, 0.14)",
      };
    default:
      return {
        pillClassName: "bg-[#e3f1df] text-[#43683b]",
        statAccentClassName: "text-[#43683b]",
        chartFillClassName: "bg-[linear-gradient(90deg,#6b9a63_0%,#9ec294_100%)]",
        meterColor: "#5b8b53",
        meterTrackColor: "rgba(91, 139, 83, 0.14)",
      };
  }
}

function getAssessmentDamageScore(value?: string | null) {
  switch (value) {
    case "critical":
      return 100;
    case "severe":
      return 76;
    case "moderate":
      return 52;
    default:
      return 28;
  }
}

function formatAssessmentCount(value: number) {
  return new Intl.NumberFormat("en-US").format(Math.max(0, value));
}

export function AssessmentPostSummary({
  details,
  locationLabel,
  compact = false,
  className = "",
}: {
  details: FeedAssessmentDetails;
  locationLabel?: string | null;
  compact?: boolean;
  className?: string;
}) {
  const tone = getAssessmentDamageTone(details.damage_level);
  const damageScore = getAssessmentDamageScore(details.damage_level);
  const damageDegrees = Math.round((damageScore / 100) * 360);
  const totalImpactCount = Math.max(0, details.estimated_casualties) + Math.max(0, details.displaced_persons);
  const maxImpactMetric = Math.max(details.estimated_casualties, details.displaced_persons, 1);
  const impactMetrics = [
    {
      label: "Estimated casualties",
      value: Math.max(0, details.estimated_casualties),
      valueClassName: tone.statAccentClassName,
      fillClassName: tone.chartFillClassName,
      trackClassName: "bg-[#f2e4d9]",
    },
    {
      label: "Displaced persons",
      value: Math.max(0, details.displaced_persons),
      valueClassName: "text-[#5d4437]",
      fillClassName: "bg-[linear-gradient(90deg,#8a6d5b_0%,#c3a997_100%)]",
      trackClassName: "bg-[#f1e7df]",
    },
  ];
  const statCardClassName = compact
    ? "flex min-h-[112px] flex-col rounded-[18px] border border-[#ead9cc] bg-[#fffdfb] px-3.5 py-3.5"
    : "flex min-h-[124px] flex-col rounded-[20px] border border-[#ead9cc] bg-[#fffdfb] px-4 py-4";

  return (
    <section
      className={`rounded-[28px] border border-[#ead9cc] bg-[#fff9f5] p-5 shadow-[0_18px_38px_-32px_rgba(92,58,40,0.28)] ${className}`.trim()}
    >
      <div
        className={`grid gap-5 ${
          compact
            ? "xl:grid-cols-[minmax(0,1.28fr)_minmax(250px,0.88fr)]"
            : "xl:grid-cols-[minmax(0,1.45fr)_minmax(290px,0.95fr)]"
        }`}
      >
        <div className="min-w-0">
          <div className="flex flex-wrap items-start gap-4">
            <div className="min-w-0 flex-1">
              <p className="text-[10px] font-bold uppercase tracking-[0.18em] text-[#b16f52]">
                Assessment Snapshot
              </p>
              <h4 className={`mt-2 font-headline text-[#4d2b1e] ${compact ? "text-[1.2rem] leading-6" : "text-[1.45rem] leading-7"}`}>
                {details.affected_area}
              </h4>
              {details.description ? (
                <p className={`mt-2 text-[#705d52] ${compact ? "text-[12px] leading-5" : "text-[13px] leading-6"}`}>
                  {details.description}
                </p>
              ) : null}
            </div>
            <span className={`rounded-full px-3 py-1 text-[10px] font-bold uppercase tracking-[0.18em] ${tone.pillClassName}`}>
              {getAssessmentDamageLevelLabel(details.damage_level)}
            </span>
          </div>

          <div className={`mt-5 rounded-[24px] border border-[#ead9cc] bg-[#fffdfb] ${compact ? "p-4" : "p-5"}`}>
            <div className="grid gap-3 md:grid-cols-[auto_minmax(0,1fr)] md:items-start md:gap-6">
              <div className="min-w-[84px]">
                <p className="text-[10px] font-bold uppercase tracking-[0.16em] text-[#ae8a74]">
                  Population Impact
                </p>
                <p className={`mt-1 font-headline text-[#4d2b1e] ${compact ? "text-[1.35rem]" : "text-[1.55rem]"}`}>
                  {formatAssessmentCount(totalImpactCount)}
                </p>
              </div>
              <p className="max-w-[320px] text-[11px] leading-5 text-[#7b6659] md:pt-1 md:text-right md:justify-self-end">
                Combined reported casualties and displaced residents.
              </p>
            </div>

            <div className="mt-5 space-y-4">
              {impactMetrics.map((metric) => {
                const widthPercent = Math.max(12, Math.round((metric.value / maxImpactMetric) * 100));
                return (
                  <div key={metric.label}>
                    <div className="flex items-end justify-between gap-3">
                      <p className="text-[10px] font-bold uppercase tracking-[0.16em] text-[#9f7f6b]">
                        {metric.label}
                      </p>
                      <p className={`text-sm font-semibold ${metric.valueClassName}`}>
                        {formatAssessmentCount(metric.value)}
                      </p>
                    </div>
                    <div className={`mt-2 h-2.5 overflow-hidden rounded-full ${metric.trackClassName}`}>
                      <div className={`h-full rounded-full ${metric.fillClassName}`} style={{ width: `${widthPercent}%` }} />
                    </div>
                  </div>
                );
              })}
            </div>
          </div>

          {locationLabel ? (
            <div className="mt-5 inline-flex max-w-full items-center gap-2 rounded-full border border-[#ead9cc] bg-[#fffdfb] px-3 py-2 text-[11px] text-[#775f52]">
              <span className="material-symbols-outlined text-[14px] text-[#d97757]">location_on</span>
              <span className="truncate">{locationLabel}</span>
            </div>
          ) : null}
        </div>

        <div className="grid gap-4">
          <div className={`rounded-[24px] border border-[#ead9cc] bg-[#fffdfb] ${compact ? "p-4" : "p-5"}`}>
            <p className="text-[10px] font-bold uppercase tracking-[0.16em] text-[#ae8a74]">
              Damage Meter
            </p>
            <div className="mt-4 grid gap-4 sm:grid-cols-[auto_minmax(0,1fr)] sm:items-center sm:gap-5">
              <div
                className={`relative flex shrink-0 items-center justify-center rounded-full ${compact ? "h-[92px] w-[92px]" : "h-[104px] w-[104px]"}`}
                style={{
                  background: `conic-gradient(${tone.meterColor} 0deg ${damageDegrees}deg, ${tone.meterTrackColor} ${damageDegrees}deg 360deg)`,
                }}
              >
                <div className="flex h-[72%] w-[72%] flex-col items-center justify-center rounded-full bg-[#fff9f5] text-center shadow-[inset_0_0_0_1px_rgba(226,209,199,0.8)]">
                  <span className={`font-headline leading-none ${compact ? "text-[1.15rem]" : "text-[1.3rem]"} ${tone.statAccentClassName}`}>
                    {damageScore}
                  </span>
                  <span className="mt-1 text-[9px] font-bold uppercase tracking-[0.16em] text-[#a48471]">
                    Index
                  </span>
                </div>
              </div>
              <div className="min-w-0 self-center">
                <p className={`font-semibold ${compact ? "text-[1rem]" : "text-[1.05rem]"} ${tone.statAccentClassName}`}>
                  {getAssessmentDamageLevelLabel(details.damage_level)}
                </p>
                <p className="mt-1 max-w-[280px] text-[12px] leading-5 text-[#756256]">
                  Visual severity reference for responders reviewing the assessment bulletin.
                </p>
              </div>
            </div>
          </div>

          <div className={`grid grid-cols-1 sm:grid-cols-3 ${compact ? "gap-2.5" : "gap-3"}`}>
            <div className={statCardClassName}>
              <div className="min-h-[2.4rem]">
                <p className="text-[9px] font-bold uppercase tracking-[0.16em] text-[#ae8a74]">
                  Casualties
                </p>
              </div>
              <p className={`mt-auto font-headline ${compact ? "text-[1.2rem]" : "text-[1.4rem]"} ${tone.statAccentClassName}`}>
                {formatAssessmentCount(details.estimated_casualties)}
              </p>
            </div>
            <div className={statCardClassName}>
              <div className="min-h-[2.4rem]">
                <p className="text-[9px] font-bold uppercase tracking-[0.16em] text-[#ae8a74]">
                  Displaced
                </p>
              </div>
              <p className={`mt-auto font-headline ${compact ? "text-[1.2rem]" : "text-[1.4rem]"} text-[#5d4437]`}>
                {formatAssessmentCount(details.displaced_persons)}
              </p>
            </div>
            <div className={statCardClassName}>
              <div className="min-h-[2.4rem]">
                <p className="text-[9px] font-bold uppercase tracking-[0.16em] text-[#ae8a74]">
                  Area Status
                </p>
              </div>
              <p className={`mt-auto font-semibold leading-5 ${compact ? "text-[0.92rem]" : "text-[0.98rem]"} ${tone.statAccentClassName}`}>
                {getAssessmentDamageLevelLabel(details.damage_level)}
              </p>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
