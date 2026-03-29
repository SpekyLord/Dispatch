import { AppShell } from "@/components/layout/app-shell";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { useSessionStore } from "@/lib/auth/session-store";

const profileTabs = ["Activity", "Briefings", "Bookmarks", "Archive"] as const;

const spotlightEntries = [
  {
    label: "Coordination update",
    title: "Regional readiness checkpoints for the week ahead.",
    summary:
      "Temporary placeholder layout for the municipality profile feed. This area can later show real status updates, coordination notes, or published regional highlights.",
    stats: { comments: "18", hearts: "64" },
  },
  {
    label: "Field memo",
    title: "Public service continuity planning across critical offices.",
    summary:
      "Use this preview page as the temporary shell for the redesigned municipality profile experience while we connect the actual account data and profile actions later.",
    stats: { comments: "11", hearts: "39" },
  },
  {
    label: "Archive note",
    title: "Reference materials for local resilience communication.",
    summary:
      "This third block is intentionally placeholder-only and follows the visual rhythm of the provided reference so we can refine the real content model afterward.",
    stats: { comments: "7", hearts: "22" },
  },
] as const;

export function MunicipalityProfilePage() {
  const user = useSessionStore((state) => state.user);
  const displayName = user?.full_name || "Municipal Command Office";
  const handle = user?.email?.split("@")[0] ?? "municipal_admin";

  return (
    <AppShell subtitle="Municipality profile preview" title="Profile">
      <div className="space-y-8">
        <section className="overflow-hidden rounded-[30px] border border-[#e2d1c7] bg-[#fff8f3] shadow-sm">
          <div className="h-52 bg-[radial-gradient(circle_at_top_left,_rgba(255,248,243,0.2),_transparent_36%),linear-gradient(135deg,_#7d6e67,_#5d514c_42%,_#a14b2f_100%)] md:h-64" />
          <div className="relative px-6 pb-6 md:px-8">
            <div className="-mt-16 flex flex-col gap-6 md:-mt-20 md:flex-row md:items-end md:justify-between">
              <div className="flex flex-1 flex-col gap-5 md:flex-row md:items-end">
                <div className="flex h-28 w-28 items-center justify-center rounded-full border-4 border-[#fff8f3] bg-[#f2e7de] text-[#8f4427] shadow-sm md:h-36 md:w-36">
                  <span className="material-symbols-outlined text-[56px] md:text-[68px]">shield_person</span>
                </div>
                <div className="max-w-3xl pt-2">
                  <div className="flex flex-wrap items-center gap-2">
                    <h2 className="font-headline text-3xl text-on-surface md:text-4xl">
                      {displayName}
                    </h2>
                    <span
                      className="material-symbols-outlined text-[#a14b2f]"
                      style={{ fontVariationSettings: "\"FILL\" 1" }}
                    >
                      verified
                    </span>
                  </div>
                  <p className="mt-1 text-sm text-on-surface-variant">@{handle}</p>
                  <p className="mt-4 max-w-2xl font-headline text-xl italic leading-relaxed text-on-surface">
                    Placeholder municipality profile inspired by the provided reference. We can
                    wire the real profile data, actions, and content modules here later.
                  </p>
                  <div className="mt-5 flex flex-wrap items-center gap-5 text-sm text-on-surface-variant">
                    <span className="inline-flex items-center gap-2">
                      <span className="material-symbols-outlined text-[18px]">location_on</span>
                      Regional Operations Center
                    </span>
                    <span>
                      <strong className="text-on-surface">12</strong> linked departments
                    </span>
                    <span>
                      <strong className="text-on-surface">24/7</strong> monitoring window
                    </span>
                  </div>
                </div>
              </div>

              <div className="flex flex-wrap gap-3">
                <Button type="button" variant="secondary">
                  Follow Updates
                </Button>
                <button className="rounded-lg border border-[#dbc6b9] px-5 py-3 text-xs font-bold uppercase tracking-widest text-on-surface transition-colors hover:bg-[#f3e7de]">
                  Message
                </button>
              </div>
            </div>
          </div>
        </section>

        <nav className="overflow-x-auto border-b border-outline-variant/15">
          <div className="flex min-w-max gap-8 px-2">
            {profileTabs.map((tab, index) => (
              <button
                key={tab}
                className={`border-b-2 px-1 pb-4 text-xs font-bold uppercase tracking-widest transition-colors ${
                  index === 0
                    ? "border-[#a14b2f] text-on-surface"
                    : "border-transparent text-on-surface-variant hover:text-on-surface"
                }`}
                type="button"
              >
                {tab}
              </button>
            ))}
          </div>
        </nav>

        <div className="space-y-8">
          {spotlightEntries.map((entry, index) => (
            <article
              key={entry.title}
              className={`space-y-4 ${index === 0 ? "" : "border-t border-outline-variant/15 pt-8"}`}
            >
              <div className="flex gap-4">
                <div className="flex h-10 w-10 items-center justify-center rounded-full bg-[#f2e7de] text-[#8f4427]">
                  <span className="material-symbols-outlined">account_balance</span>
                </div>
                <div>
                  <div className="flex items-center gap-2">
                    <span className="font-semibold text-on-surface">{displayName}</span>
                    <span className="text-sm text-on-surface-variant">
                      {index === 0 ? "Just now" : index === 1 ? "Today" : "Yesterday"}
                    </span>
                  </div>
                  <p className="text-[11px] font-bold uppercase tracking-widest text-[#a14b2f]">
                    {entry.label}
                  </p>
                </div>
              </div>

              <div className="pl-0 md:pl-14">
                <h3 className="font-headline text-3xl leading-tight text-on-surface">
                  {entry.title}
                </h3>
                <p className="mt-3 max-w-3xl text-base leading-relaxed text-on-surface-variant">
                  {entry.summary}
                </p>

                <div className="mt-5 flex items-center gap-6 text-on-surface-variant">
                  <button className="flex items-center gap-2 transition-colors hover:text-[#a14b2f]" type="button">
                    <span className="material-symbols-outlined">chat_bubble</span>
                    <span className="text-xs font-bold">{entry.stats.comments}</span>
                  </button>
                  <button className="flex items-center gap-2 transition-colors hover:text-[#a14b2f]" type="button">
                    <span className="material-symbols-outlined">favorite</span>
                    <span className="text-xs font-bold">{entry.stats.hearts}</span>
                  </button>
                  <button className="flex items-center gap-2 transition-colors hover:text-[#a14b2f]" type="button">
                    <span className="material-symbols-outlined">bookmark</span>
                    <span className="text-xs font-bold">Save</span>
                  </button>
                  <button className="ml-auto transition-colors hover:text-[#a14b2f]" type="button">
                    <span className="material-symbols-outlined">share</span>
                  </button>
                </div>
              </div>
            </article>
          ))}
        </div>

        <Card className="border-[#e2d1c7] bg-[#fff8f3]">
          <p className="text-[11px] font-bold uppercase tracking-widest text-[#a14b2f]">
            Temporary Placeholder
          </p>
          <p className="mt-3 max-w-3xl text-sm leading-relaxed text-on-surface-variant">
            This municipality profile page is currently UI-only and based on the provided
            reference. We can connect actual profile editing, posts, media, and account details in
            the next pass.
          </p>
        </Card>
      </div>
    </AppShell>
  );
}
