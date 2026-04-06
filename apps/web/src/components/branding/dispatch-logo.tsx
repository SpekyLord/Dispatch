import dispatchLogoUrl from "@/assets/dispatch-logo.svg";

type DispatchLogoProps = {
  alt?: string;
  className?: string;
};

export function DispatchLogo({
  alt = "Dispatch",
  className = "h-12 w-[82px]",
}: DispatchLogoProps) {
  return (
    <img
      alt={alt}
      className={`rounded-[18px] object-contain shadow-[0_12px_28px_-16px_rgba(56,36,27,0.5)] ${className}`}
      src={dispatchLogoUrl}
    />
  );
}
