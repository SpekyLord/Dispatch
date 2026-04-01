import { AppRouter } from "@/app/router";
import { LocaleProvider } from "@/lib/i18n/locale-context";

export default function App() {
  return (
    <LocaleProvider>
      <AppRouter />
    </LocaleProvider>
  );
}
