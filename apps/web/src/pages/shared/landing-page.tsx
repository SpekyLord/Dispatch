import { Link } from "react-router-dom";
import { DispatchLogo } from "@/components/branding/dispatch-logo";

/**
 * Phase 1 — Landing page.
 * Aegis-styled hero with serif headline, trust badges, and CTA buttons
 * for sign-in and registration.
 */

function createDeterministicRandom(seed: number) {
  let current = seed >>> 0;

  return () => {
    current = (current * 1664525 + 1013904223) >>> 0;
    return current / 4294967295;
  };
}

function buildStarShadow(
  seed: number,
  count: number,
  color: string,
  maxX = 2200,
  maxY = 1400,
  loopHeight = 1600,
) {
  const random = createDeterministicRandom(seed);

  return Array.from({ length: count }, () => {
    const x = Math.round(random() * maxX);
    const y = Math.round(random() * maxY);
    return [`${x}px ${y}px ${color}`, `${x}px ${y + loopHeight}px ${color}`];
  })
    .flat()
    .join(", ");
}

const registerStarLayers = [
  {
    animation: "registerStarsFloatA 52s linear infinite",
    blur: "drop-shadow(0 0 5px rgba(214,120,60,0.28))",
    opacity: 0.96,
    shadow: buildStarShadow(11, 220, "rgba(201,109,52,0.98)"),
    size: 1.8,
  },
  {
    animation: "registerStarsFloatB 78s linear infinite",
    blur: "drop-shadow(0 0 7px rgba(230,146,86,0.24))",
    opacity: 0.82,
    shadow: buildStarShadow(27, 140, "rgba(229,144,78,0.86)"),
    size: 2.6,
  },
  {
    animation: "registerStarsFloatC 108s linear infinite",
    blur: "drop-shadow(0 0 11px rgba(238,171,116,0.24))",
    opacity: 0.72,
    shadow: buildStarShadow(53, 88, "rgba(244,184,130,0.8)"),
    size: 3.6,
  },
] as const;

export function LandingPage() {
  return (
    <div className="relative isolate flex min-h-screen flex-col overflow-hidden bg-[linear-gradient(180deg,#ffffff_0%,#fdf8f3_36%,#f7e6d8_68%,#efc3a6_100%)]">
      <style>{`
        @keyframes registerStarsFloatA {
          from {
            transform: translate3d(0, 0, 0);
          }
          to {
            transform: translate3d(0, -1600px, 0);
          }
        }

        @keyframes registerStarsFloatB {
          from {
            transform: translate3d(0, 0, 0);
          }
          to {
            transform: translate3d(0, -1600px, 0);
          }
        }

        @keyframes registerStarsFloatC {
          from {
            transform: translate3d(0, 0, 0);
          }
          to {
            transform: translate3d(0, -1600px, 0);
          }
        }
      `}</style>

      <div aria-hidden="true" className="pointer-events-none absolute inset-0">
        <div className="absolute inset-0 bg-[radial-gradient(circle_at_top,rgba(255,255,255,0.72)_0%,rgba(255,255,255,0.14)_24%,transparent_52%)]" />
        {registerStarLayers.map((layer) => (
          <div
            key={layer.animation}
            className="absolute left-0 top-0"
            style={{
              animation: layer.animation,
              boxShadow: layer.shadow,
              filter: layer.blur,
              height: `${layer.size}px`,
              opacity: layer.opacity,
              willChange: "transform",
              width: `${layer.size}px`,
            }}
          />
        ))}
      </div>

      <div className="relative z-10 flex min-h-screen flex-col">
        {/* Top bar */}
        <header className="bg-surface-container w-full">
          <div className="flex justify-between items-center w-full px-12 py-6 max-w-[1440px] mx-auto">
            <Link to="/" aria-label="Dispatch home">
              <DispatchLogo className="h-12 w-12" />
            </Link>
            <nav className="hidden md:flex items-center gap-8">
              <Link
                to="/feed"
                className="text-on-surface-variant hover:text-on-surface transition-colors text-sm font-medium"
              >
                Feed
              </Link>
              <Link
                to="/auth/login"
                className="text-on-surface-variant hover:text-on-surface transition-colors text-sm font-medium"
              >
                Sign In
              </Link>
            </nav>
          </div>
        </header>

        {/* Hero */}
        <main className="flex-grow flex items-center justify-center px-6 py-20 relative overflow-hidden">
          <div className="absolute top-[-10%] left-[-5%] w-[40%] h-[60%] bg-surface-container opacity-40 blur-[120px] rounded-full pointer-events-none" />
          <div className="absolute bottom-[-10%] right-[-5%] w-[30%] h-[50%] bg-secondary-container opacity-20 blur-[100px] rounded-full pointer-events-none" />

          <div className="max-w-4xl w-full relative z-10 text-center">
            <span className="text-secondary text-xs font-bold tracking-[0.2em] uppercase mb-6 block">
              Emergency Response Platform
            </span>
            <h1 className="font-headline italic text-5xl md:text-7xl leading-tight text-on-surface mb-8">
              Cultivating resilience through community-driven response.
            </h1>
            <p className="max-w-2xl mx-auto text-lg text-on-surface-variant leading-relaxed mb-12">
              Dispatch connects citizens, departments, and municipalities in a
              unified crisis coordination platform. Report incidents, verify
              responders, and track real-time status updates.
            </p>

            <div className="flex flex-wrap justify-center gap-4 mb-16">
              <Link
                to="/auth/register"
                className="bg-gradient-to-br from-[#c77440] to-[#a14b2f] text-[#faf7f3] px-8 py-4 rounded-md text-sm font-semibold tracking-widest uppercase shadow-lg hover:opacity-95 active:scale-[0.98] transition-all"
              >
                Get Started
              </Link>
              <Link
                to="/auth/login"
                className="border border-outline-variant/30 bg-surface-container-lowest px-8 py-4 rounded-md text-sm font-semibold text-on-surface hover:bg-surface-container transition-all"
              >
                Sign In
              </Link>
            </div>

            {/* Trust badges */}
            <div className="flex flex-wrap justify-center gap-8">
              {[
                { icon: "groups", label: "Citizens" },
                { icon: "local_fire_department", label: "Departments" },
                { icon: "account_balance", label: "Municipality" },
              ].map((item) => (
                <div key={item.label} className="flex items-center gap-3">
                  <div className="w-10 h-10 rounded-full bg-white flex items-center justify-center shadow-[0_10px_22px_-12px_rgba(120,78,58,0.18),0_5px_5px_0_#00000010]">
                    <span className="material-symbols-outlined text-secondary scale-75">
                      {item.icon}
                    </span>
                  </div>
                  <span className="text-sm font-medium text-on-surface-variant">
                    {item.label}
                  </span>
                </div>
              ))}
            </div>
          </div>
        </main>

        {/* Footer */}
        <footer className="border-t border-outline-variant/15 bg-surface-container/90 backdrop-blur-sm">
          <div className="w-full px-12 py-8 flex flex-col md:flex-row justify-between items-center max-w-[1440px] mx-auto">
            <div className="mb-4 md:mb-0">
              <DispatchLogo className="h-10 w-10" />
            </div>
            <div className="text-[10px] uppercase tracking-widest text-on-surface-variant">
              &copy; 2026 Dispatch. Community-driven crisis management.
            </div>
          </div>
        </footer>
      </div>
    </div>
  );
}
