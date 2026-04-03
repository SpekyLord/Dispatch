import { cn } from "@/lib/utils";

type LoadingDotsProps = {
  className?: string;
  dotClassName?: string;
  sizeClassName?: string;
};

export function LoadingDots({
  className,
  dotClassName,
  sizeClassName = "h-4 w-4",
}: LoadingDotsProps) {
  return (
    <>
      <style>{`
        @keyframes dispatch-loading-dot-pulse {
          0% {
            transform: scale(0.82);
            background-color: #efb08e;
            box-shadow: 0 0 0 0 rgba(217, 119, 87, 0.36);
          }

          50% {
            transform: scale(1.18);
            background-color: #d97757;
            box-shadow: 0 0 0 10px rgba(217, 119, 87, 0);
          }

          100% {
            transform: scale(0.82);
            background-color: #efb08e;
            box-shadow: 0 0 0 0 rgba(217, 119, 87, 0.36);
          }
        }
      `}</style>
      <div
        aria-label="Loading"
        className={cn("flex items-center justify-center gap-2.5", className)}
        role="status"
      >
        {[0, 1, 2].map((index) => (
          <span
            key={index}
            className={cn(
              "rounded-full bg-[#efb08e]",
              sizeClassName,
              dotClassName,
            )}
            style={{
              animation: "dispatch-loading-dot-pulse 1.5s infinite ease-in-out",
              animationDelay: `${[-0.3, -0.1, 0.1][index]}s`,
            }}
          />
        ))}
      </div>
    </>
  );
}
