import { useSyncExternalStore } from "react";

const THEME_STORAGE_KEY = "dispatch-temp-theme";
const THEME_CHANGE_EVENT = "dispatch-temp-theme-change";

function readDarkMode() {
  if (typeof window === "undefined") {
    return false;
  }

  return window.localStorage.getItem(THEME_STORAGE_KEY) === "dark";
}

function subscribe(onStoreChange: () => void) {
  if (typeof window === "undefined") {
    return () => {};
  }

  const handleStorage = (event: StorageEvent) => {
    if (event.key === THEME_STORAGE_KEY) {
      onStoreChange();
    }
  };
  const handleThemeChange = () => onStoreChange();

  window.addEventListener("storage", handleStorage);
  window.addEventListener(THEME_CHANGE_EVENT, handleThemeChange);

  return () => {
    window.removeEventListener("storage", handleStorage);
    window.removeEventListener(THEME_CHANGE_EVENT, handleThemeChange);
  };
}

export function setAppShellDarkMode(isDarkMode: boolean) {
  if (typeof window === "undefined") {
    return;
  }

  window.localStorage.setItem(THEME_STORAGE_KEY, isDarkMode ? "dark" : "light");
  window.dispatchEvent(new Event(THEME_CHANGE_EVENT));
}

export function useAppShellTheme() {
  const isDarkMode = useSyncExternalStore(subscribe, readDarkMode, () => false);

  return {
    isDarkMode,
    setIsDarkMode: setAppShellDarkMode,
  };
}
