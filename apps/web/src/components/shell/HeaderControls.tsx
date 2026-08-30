import { useEffect, useState } from "react";
import { Button } from "@astryxdesign/core/Button";
import { DropdownMenu } from "@astryxdesign/core/DropdownMenu";
import { HStack } from "@astryxdesign/core/Stack";
import { InternationalizationProvider, useTranslator } from "@astryxdesign/core/i18n";
import fiFI from "@astryxdesign/core/locales/fi-FI.json";
import { Menu, UserRound } from "lucide-react";
import { features } from "../../lib/features";
import { getAstryxLocale, getMessages, getOtherLocale, type Locale } from "../../lib/i18n";
import {
  MOBILE_NAV_REQUEST_EVENT,
  MOBILE_NAV_STATE_EVENT,
  type MobileNavRequestDetail,
  type MobileNavStateDetail,
} from "../../lib/learning/mobile-navigation";
import type {
  AcademicTerm,
  CourseInfo,
  LearnerActivity,
  StudentProfile,
} from "../../lib/learning/types";
import { createBrowserSupabaseClient } from "../../lib/supabase/browser";
import { localizedPath, routes, type AppPath } from "../../lib/routes";
import ActivityCenter from "../islands/ActivityCenter";
import AppearanceMenu from "../islands/AppearanceMenu";
import LocaleSwitcher from "../islands/LocaleSwitcher";

interface Props {
  currentPath: AppPath;
  courses: CourseInfo[];
  profile?: StudentProfile;
  term?: AcademicTerm;
  activities: LearnerActivity[];
  locale: Locale;
  isWorkspace: boolean;
  showMobileNav: boolean;
  showSignIn: boolean;
}

function goTo(path: AppPath) {
  window.location.assign(path);
}

function HeaderControlsContent({
  currentPath,
  courses,
  profile,
  term,
  activities,
  locale,
  isWorkspace,
  showMobileNav,
  showSignIn,
}: Props) {
  const translateAstryx = useTranslator();
  const messages = getMessages(locale);
  const copy = messages.navigation;
  const otherLocale = getOtherLocale(locale);
  const languageOption = messages.languageSwitcher.options[otherLocale];
  const [isMobileNavOpen, setMobileNavOpen] = useState(false);

  useEffect(() => {
    const synchronize = (event: Event) => {
      setMobileNavOpen((event as CustomEvent<MobileNavStateDetail>).detail.isOpen);
    };

    window.addEventListener(MOBILE_NAV_STATE_EVENT, synchronize);
    return () => window.removeEventListener(MOBILE_NAV_STATE_EVENT, synchronize);
  }, []);

  const requestMobileNav = () => {
    const nextIsOpen = !isMobileNavOpen;
    setMobileNavOpen(nextIsOpen);
    window.dispatchEvent(
      new CustomEvent<MobileNavRequestDetail>(MOBILE_NAV_REQUEST_EVENT, {
        detail: { isOpen: nextIsOpen },
      }),
    );
  };

  const signOut = async () => {
    const supabase = createBrowserSupabaseClient();
    const { error } = await supabase.auth.signOut();
    if (!error) goTo(localizedPath(locale, routes.home.path()));
  };

  return (
    <HStack gap={2} vAlign="center">
      {isWorkspace && profile ? (
        <ActivityCenter activities={activities} courses={courses} locale={locale} />
      ) : null}
      {profile ? (
        <DropdownMenu
          button={{
            label: profile.displayName,
            variant: "ghost",
            icon: <UserRound size={17} aria-hidden="true" />,
            children: <span className="account-label">{profile.displayName}</span>,
          }}
          items={[
            { label: term ? `${term.label} · ${copy.student}` : copy.student, isDisabled: true },
            { type: "divider" },
            {
              label: copy.support,
              onClick: () =>
                goTo(`${localizedPath(locale, routes.desk.path())}#announcements` as AppPath),
            },
            ...(features.finnish
              ? [
                  {
                    label: languageOption.switchLabel,
                    onClick: () => goTo(localizedPath(otherLocale, currentPath)),
                  },
                ]
              : []),
            {
              label: copy.signOut,
              onClick: signOut,
            },
          ]}
          menuWidth={224}
        />
      ) : showSignIn ? (
        <Button
          href={localizedPath(locale, routes.login.path())}
          icon={<UserRound size={17} aria-hidden="true" />}
          label={messages.publicHome.signIn}
          size="sm"
          variant="primary"
        />
      ) : null}
      <span className="header-locale">
        <LocaleSwitcher locale={locale} path={currentPath} />
      </span>
      <AppearanceMenu locale={locale} />
      {showMobileNav ? (
        <Button
          aria-controls="ainigma-mobile-navigation"
          aria-expanded={isMobileNavOpen}
          className="learning-mobile-nav-toggle"
          data-testid="mobile-nav-toggle"
          icon={<Menu size={20} aria-hidden="true" />}
          isIconOnly
          label={translateAstryx("@astryx.mobileNav.toggle.open")}
          onClick={requestMobileNav}
          variant="ghost"
        />
      ) : null}
    </HStack>
  );
}

export default function HeaderControls(props: Props) {
  return (
    <InternationalizationProvider
      locale={getAstryxLocale(props.locale)}
      messages={{ "fi-FI": fiFI }}
    >
      <HeaderControlsContent {...props} />
    </InternationalizationProvider>
  );
}
