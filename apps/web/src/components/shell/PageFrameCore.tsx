import type { ReactNode } from "react";
import { AppShell } from "@astryxdesign/core/AppShell";
import { NavIcon } from "@astryxdesign/core/NavIcon";
import { VStack } from "@astryxdesign/core/Stack";
import { TopNav, TopNavHeading } from "@astryxdesign/core/TopNav";
import { InternationalizationProvider } from "@astryxdesign/core/i18n";
import fiFI from "@astryxdesign/core/locales/fi-FI.json";
import { BookOpenCheck } from "lucide-react";
import { getAstryxLocale, getMessages, type Locale } from "../../lib/i18n";
import { localizedPath, routes } from "../../lib/routes";
import SiteHeader from "./SiteHeader";

interface Props {
  children: ReactNode;
  hasNavigation: boolean;
  headerControls?: ReactNode;
  isAuthenticated: boolean;
  isHome: boolean;
  locale: Locale;
  sideNav?: ReactNode;
}

/**
 * The single React boundary needed by Astryx's provider and AppShell.
 * Route policy and island composition stay in PageFrame.astro.
 */
export default function PageFrameCore({
  children,
  hasNavigation,
  headerControls,
  isAuthenticated,
  isHome,
  locale,
  sideNav,
}: Props) {
  const copy = getMessages(locale).navigation;
  const usesWorkspaceHeader = hasNavigation && isAuthenticated;
  const className = [
    hasNavigation ? "learning-frame" : "public-shell",
    hasNavigation && !isAuthenticated ? "public-shell" : "",
    isHome ? "public-home-shell" : "",
  ]
    .filter(Boolean)
    .join(" ");

  return (
    <InternationalizationProvider locale={getAstryxLocale(locale)} messages={{ "fi-FI": fiFI }}>
      <AppShell
        className={className}
        contentPadding={0}
        height="auto"
        mobileNav={hasNavigation ? { breakpoint: "lg", hasToggle: false } : false}
        variant="section"
        topNav={
          usesWorkspaceHeader ? (
            <TopNav
              label={copy.navigation}
              heading={
                <TopNavHeading
                  heading="Ainigma"
                  headingHref={localizedPath(locale, routes.desk.path())}
                  logo={<NavIcon icon={<BookOpenCheck size={17} aria-hidden="true" />} />}
                  superheading={copy.university}
                />
              }
              endContent={headerControls}
            />
          ) : (
            <SiteHeader locale={locale}>{headerControls}</SiteHeader>
          )
        }
        sideNav={sideNav}
      >
        {hasNavigation ? (
          children
        ) : (
          <VStack className="public-page" gap={0} hAlign="stretch">
            {children}
          </VStack>
        )}
      </AppShell>
    </InternationalizationProvider>
  );
}
