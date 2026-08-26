import type { ReactNode } from "react";
import { AppShell } from "@astryxdesign/core/AppShell";
import { VStack } from "@astryxdesign/core/Stack";
import { InternationalizationProvider } from "@astryxdesign/core/i18n";
import fiFI from "@astryxdesign/core/locales/fi-FI.json";
import { getAstryxLocale, type Locale } from "../../lib/i18n";
import { routes, type AppPath } from "../../lib/routes";
import { AppearanceThemeProvider } from "../theme/AppearanceThemeProvider";
import PublicHeader from "./PublicHeader";
import SiteFooter from "./SiteFooter";

interface Props {
  children: ReactNode;
  currentPath: AppPath;
  locale: Locale;
}

export default function PublicPageFrame({ children, currentPath, locale }: Props) {
  return (
    <InternationalizationProvider locale={getAstryxLocale(locale)} messages={{ "fi-FI": fiFI }}>
      <AppearanceThemeProvider>
        <AppShell
          className={`public-shell${currentPath === routes.home.path() ? " public-home-shell" : ""}`}
          contentPadding={0}
          height="auto"
          mobileNav={false}
          variant="section"
          topNav={
            <PublicHeader
              currentPath={currentPath}
              locale={locale}
              showSignIn={currentPath === routes.home.path()}
            />
          }
        >
          <VStack className="public-page" gap={0} hAlign="stretch">
            {children}
            {currentPath === routes.home.path() ? <SiteFooter locale={locale} /> : null}
          </VStack>
        </AppShell>
      </AppearanceThemeProvider>
    </InternationalizationProvider>
  );
}
