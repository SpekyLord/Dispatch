import {
  createContext,
  type ReactNode,
  useContext,
  useMemo,
  useState,
} from "react";

import {
  type Locale,
  type MessageKey,
  type MessageParams,
  getCategoryLabel,
  getDamageLevelLabel,
  getResponseActionLabel,
  getSeverityLabel,
  getStatusLabel,
  translate,
} from "@/lib/i18n/messages";

type LocaleContextValue = {
  locale: Locale;
  setLocale: (locale: Locale) => void;
  t: (key: MessageKey, params?: MessageParams) => string;
  getStatusLabel: (status: string) => string;
  getCategoryLabel: (category: string) => string;
  getDamageLevelLabel: (level: string) => string;
  getSeverityLabel: (severity: string) => string;
  getResponseActionLabel: (action: string) => string;
};

const defaultLocale: Locale = "en";

const LocaleContext = createContext<LocaleContextValue>({
  locale: defaultLocale,
  setLocale: () => undefined,
  t: (key, params) => translate(defaultLocale, key, params),
  getStatusLabel: (status) => getStatusLabel(defaultLocale, status),
  getCategoryLabel: (category) => getCategoryLabel(defaultLocale, category),
  getDamageLevelLabel: (level) => getDamageLevelLabel(defaultLocale, level),
  getSeverityLabel: (severity) => getSeverityLabel(defaultLocale, severity),
  getResponseActionLabel: (action) =>
    getResponseActionLabel(defaultLocale, action),
});

type LocaleProviderProps = {
  children: ReactNode;
  initialLocale?: Locale;
};

export function LocaleProvider({
  children,
  initialLocale = defaultLocale,
}: LocaleProviderProps) {
  const [locale, setLocale] = useState<Locale>(initialLocale);

  const value = useMemo<LocaleContextValue>(
    () => ({
      locale,
      setLocale,
      t: (key, params) => translate(locale, key, params),
      getStatusLabel: (status) => getStatusLabel(locale, status),
      getCategoryLabel: (category) => getCategoryLabel(locale, category),
      getDamageLevelLabel: (level) => getDamageLevelLabel(locale, level),
      getSeverityLabel: (severity) => getSeverityLabel(locale, severity),
      getResponseActionLabel: (action) =>
        getResponseActionLabel(locale, action),
    }),
    [locale],
  );

  return (
    <LocaleContext.Provider value={value}>{children}</LocaleContext.Provider>
  );
}

export function useLocale() {
  return useContext(LocaleContext);
}
