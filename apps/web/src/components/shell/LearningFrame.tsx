import type { ReactNode } from "react";
import { AppShell } from "@astryxdesign/core/AppShell";
import { NavIcon } from "@astryxdesign/core/NavIcon";
import { TopNav, TopNavHeading } from "@astryxdesign/core/TopNav";
import { InternationalizationProvider } from "@astryxdesign/core/i18n";
import fiFI from "@astryxdesign/core/locales/fi-FI.json";
import { BookOpenCheck } from "lucide-react";
import { getAstryxLocale, getMessages, type Locale } from "../../lib/i18n";
import { localizedPath, routes } from "../../lib/routes";

interface Props {
  locale: Locale;
  children: ReactNode;
  sideNav?: ReactNode;
  topNavEnd?: ReactNode;
}

/**
 * The non-interactive learning shell.
 *
 * Astro renders this component on the server. Interactive navigation and
 * header controls arrive through named slots, so page content is no longer a
 * child of one application-sized client island.
 */
export default function LearningFrame({ locale, children, sideNav, topNavEnd }: Props) {
  const copy = getMessages(locale).navigation;

  // Keep this AppShell composition in sync with the established learning UI.
  // Its props and component nesting intentionally match the previous client
  // shell so moving the hydration boundaries does not move the interface.
  return (
    <InternationalizationProvider locale={getAstryxLocale(locale)} messages={{ "fi-FI": fiFI }}>
      <AppShell
        className="learning-frame"
        contentPadding={0}
        height="auto"
        mobileNav={{ breakpoint: "lg", hasToggle: false }}
        variant="section"
        topNav={
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
            endContent={topNavEnd}
          />
        }
        sideNav={sideNav}
      >
        {children}
      </AppShell>
    </InternationalizationProvider>
  );
}
