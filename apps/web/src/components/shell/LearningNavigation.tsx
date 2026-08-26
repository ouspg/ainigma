import { useEffect, useState } from "react";
import { createPortal } from "react-dom";
import { MobileNav } from "@astryxdesign/core/MobileNav";
import { NavIcon } from "@astryxdesign/core/NavIcon";
import {
  SideNav,
  SideNavItem,
  SideNavSection,
  type SideNavCollapsibleConfig,
} from "@astryxdesign/core/SideNav";
import { Text } from "@astryxdesign/core/Text";
import { TopNavHeading } from "@astryxdesign/core/TopNav";
import { InternationalizationProvider, useTranslator } from "@astryxdesign/core/i18n";
import fiFI from "@astryxdesign/core/locales/fi-FI.json";
import { Bell, BookOpenCheck, Home, Megaphone } from "lucide-react";
import { getAstryxLocale, getMessages, type Locale } from "../../lib/i18n";
import { CourseMark } from "../../lib/learning/course-icons";
import {
  MOBILE_NAV_REQUEST_EVENT,
  MOBILE_NAV_STATE_EVENT,
  type MobileNavRequestDetail,
  type MobileNavStateDetail,
} from "../../lib/learning/mobile-navigation";
import type { CourseInfo } from "../../lib/learning/types";
import { localizedPath, routes, type AppPath } from "../../lib/routes";

interface Props {
  currentPath: AppPath;
  courses: CourseInfo[];
  locale: Locale;
}

function LearningNavigationContent({ currentPath, courses, locale }: Props) {
  const translateAstryx = useTranslator();
  const copy = getMessages(locale).navigation;
  const [isSidebarCollapsed, setSidebarCollapsed] = useState(false);
  const [isMobileNavOpen, setMobileNavOpen] = useState(false);
  const [isMobile, setIsMobile] = useState(false);
  const activeCourseKey = courses.find((course) => currentPath.startsWith(course.href))?.slug;
  const [expandedCourseKey, setExpandedCourseKey] = useState<string | undefined>(activeCourseKey);

  useEffect(() => {
    setExpandedCourseKey(activeCourseKey);
  }, [activeCourseKey]);

  const activeWeekKey = courses
    .flatMap((course) =>
      course.weeks.map((week) => ({ key: `${course.slug}/${week.slug}`, href: week.href })),
    )
    .find(({ href }) => currentPath.startsWith(href))?.key;
  const [expandedWeekKey, setExpandedWeekKey] = useState<string | undefined>(activeWeekKey);

  useEffect(() => {
    setExpandedWeekKey(activeWeekKey);
  }, [activeWeekKey]);

  useEffect(() => {
    const media = window.matchMedia("(max-width: 1024px)");
    const synchronizeViewport = () => {
      setIsMobile(media.matches);
      if (!media.matches) {
        setMobileNavOpen(false);
      }
    };
    const handleRequest = (event: Event) => {
      setMobileNavOpen((event as CustomEvent<MobileNavRequestDetail>).detail.isOpen);
    };

    synchronizeViewport();
    media.addEventListener("change", synchronizeViewport);
    window.addEventListener(MOBILE_NAV_REQUEST_EVENT, handleRequest);
    return () => {
      media.removeEventListener("change", synchronizeViewport);
      window.removeEventListener(MOBILE_NAV_REQUEST_EVENT, handleRequest);
    };
  }, []);

  const setMobileNavigationOpen = (isOpen: boolean) => {
    setMobileNavOpen(isOpen);
    window.dispatchEvent(
      new CustomEvent<MobileNavStateDetail>(MOBILE_NAV_STATE_EVENT, { detail: { isOpen } }),
    );
  };

  const collapsible: SideNavCollapsibleConfig = {
    buttonLabel: copy.collapse,
    isCollapsed: isSidebarCollapsed,
    onCollapsedChange: setSidebarCollapsed,
  };

  const courseNavigation = (course: CourseInfo) => {
    const hasChildren = course.pages.length > 0 || course.weeks.length > 0;

    return (
      <SideNavItem
        {...(hasChildren
          ? {
              collapsible: {
                isCollapsed: expandedCourseKey !== course.slug,
                onCollapsedChange: (isCollapsed) =>
                  setExpandedCourseKey(isCollapsed ? undefined : course.slug),
              },
            }
          : {})}
        endContent={
          <Text type="supporting" color="secondary" hasTabularNumbers>
            {course.progress}%
          </Text>
        }
        href={localizedPath(locale, course.href)}
        icon={
          <CourseMark
            href={localizedPath(locale, course.href)}
            isCollapsed={isSidebarCollapsed}
            mark={course.navMark}
          />
        }
        isSelected={currentPath === course.href}
        key={course.slug}
        label={course.title}
        onClick={() => setExpandedCourseKey(course.slug)}
      >
        {hasChildren ? (
          <>
            {course.pages.map((page) => (
              <SideNavItem
                href={localizedPath(locale, page.href)}
                isSelected={currentPath === page.href}
                key={page.page}
                label={page.label}
                size="sm"
              />
            ))}
            {course.weeks.map((week) => (
              <SideNavItem
                {...(week.tasks.length > 0
                  ? {
                      collapsible: {
                        isCollapsed: expandedWeekKey !== `${course.slug}/${week.slug}`,
                        onCollapsedChange: (isCollapsed) =>
                          setExpandedWeekKey(
                            isCollapsed ? undefined : `${course.slug}/${week.slug}`,
                          ),
                      },
                    }
                  : {})}
                href={localizedPath(locale, week.href)}
                isSelected={currentPath === week.href}
                key={week.slug}
                label={`Week ${week.number} · ${week.title}`}
                size="sm"
              >
                {week.tasks.length > 0
                  ? week.tasks.map((task) => (
                      <SideNavItem
                        href={localizedPath(locale, task.href)}
                        isSelected={currentPath === task.href}
                        key={task.slug}
                        label={task.title}
                        size="sm"
                      />
                    ))
                  : undefined}
              </SideNavItem>
            ))}
          </>
        ) : null}
      </SideNavItem>
    );
  };

  const navigationSections = (
    <>
      <SideNavSection title={copy.workspace} isHeaderHidden>
        <SideNavItem
          href={localizedPath(locale, routes.desk.path())}
          icon={Home}
          isSelected={currentPath === routes.desk.path()}
          label={copy.desk}
        />
        <SideNavItem
          href={localizedPath(locale, routes.activity.path())}
          icon={Bell}
          isSelected={currentPath === routes.activity.path()}
          label={copy.activity}
        />
        <SideNavItem
          href={localizedPath(locale, routes.announcements.path())}
          icon={Megaphone}
          isSelected={currentPath === routes.announcements.path()}
          label={copy.announcements}
        />
      </SideNavSection>

      <SideNavSection title={copy.courses} subtitle={`${courses.length} ${copy.activeCourses}`}>
        {courses.map((course) => courseNavigation(course))}
      </SideNavSection>
    </>
  );

  return (
    <>
      <SideNav
        collapsible={collapsible}
        resizable={{
          defaultWidth: 256,
          minWidth: 224,
          maxWidth: 320,
        }}
      >
        {navigationSections}
      </SideNav>

      {isMobile
        ? createPortal(
            <MobileNav
              data-testid="ainigma-mobile-navigation"
              header={
                <TopNavHeading
                  heading="Ainigma"
                  headingHref={localizedPath(locale, routes.desk.path())}
                  logo={<NavIcon icon={<BookOpenCheck size={17} aria-hidden="true" />} />}
                  superheading={copy.university}
                />
              }
              id="ainigma-mobile-navigation"
              isOpen={isMobileNavOpen}
              label={translateAstryx("@astryx.mobileNav.navigation")}
              onClick={(event) => {
                if (event.target instanceof Element && event.target.closest("a[href]")) {
                  setMobileNavigationOpen(false);
                }
              }}
              onOpenChange={setMobileNavigationOpen}
              side="end"
            >
              {navigationSections}
            </MobileNav>,
            document.body,
          )
        : null}
    </>
  );
}

export default function LearningNavigation(props: Props) {
  return (
    <InternationalizationProvider
      locale={getAstryxLocale(props.locale)}
      messages={{ "fi-FI": fiFI }}
    >
      <LearningNavigationContent {...props} />
    </InternationalizationProvider>
  );
}
