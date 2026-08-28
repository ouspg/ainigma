import { useMemo, useState } from "react";
import { Button } from "@astryxdesign/core/Button";
import { Card } from "@astryxdesign/core/Card";
import { Layout, LayoutContent, LayoutPanel } from "@astryxdesign/core/Layout";
import { List, ListItem } from "@astryxdesign/core/List";
import { ProgressBar } from "@astryxdesign/core/ProgressBar";
import { SegmentedControl, SegmentedControlItem } from "@astryxdesign/core/SegmentedControl";
import { HStack, StackItem, VStack } from "@astryxdesign/core/Stack";
import { StatusDot } from "@astryxdesign/core/StatusDot";
import { Heading, Text } from "@astryxdesign/core/Text";
import { Link } from "@astryxdesign/core/Link";
import {
  ArrowRight,
  BookOpen,
  Check,
  ChevronRight,
  Clock3,
  FlaskConical,
  Wrench,
} from "lucide-react";
import CourseUpdatesList from "../pages/CourseUpdatesList";
import type {
  AgendaItem,
  AgendaStatus,
  CourseInfo,
  LearningWorkspace,
} from "../../lib/learning/types";
import { getMessages, type Locale } from "../../lib/i18n";
import { getCourseIcon } from "../../lib/learning/course-icons";
import { localizedPath, routes } from "../../lib/routes";

interface Props {
  workspace: LearningWorkspace;
  locale: Locale;
}

type AgendaFilter = "upcoming" | "completed" | "all";

const SHOW_PROGRESS_NOTE = false;

const statusVariants: Record<CourseInfo["status"], "neutral" | "accent" | "success"> = {
  "not-started": "neutral",
  "in-progress": "accent",
  completed: "success",
};

const agendaIcons = {
  lab: FlaskConical,
  reading: BookOpen,
  setup: Wrench,
} as const;

function filterAgenda(items: AgendaItem[], filter: AgendaFilter): AgendaItem[] {
  if (filter === "completed") {
    return items.filter((item) => item.status === "completed");
  }
  if (filter === "upcoming") {
    return items.filter((item) => item.status !== "completed");
  }
  return items;
}

function agendaStatusLabel(status: AgendaStatus, labels: Record<AgendaStatus, string>): string {
  return labels[status];
}

function formatCourseDate(value: string, locale: Locale): string {
  return new Intl.DateTimeFormat(locale === "fi" ? "fi-FI" : "en-GB", {
    day: "numeric",
    month: "short",
    timeZone: "UTC",
    year: "numeric",
  }).format(new Date(`${value}T00:00:00Z`));
}

function DashboardContent({ workspace, locale }: Props) {
  const [filter, setFilter] = useState<AgendaFilter>("upcoming");
  const courseByOfferingKey = useMemo(
    () => new Map(workspace.courses.map((course) => [course.offeringKey, course])),
    [workspace.courses],
  );
  const visibleAgenda = filterAgenda(workspace.agenda, filter);
  const copy = getMessages(locale).dashboard;
  const focusCourse =
    workspace.courses.find((course) => course.status === "in-progress") ?? workspace.courses[0];

  if (!focusCourse) {
    return null;
  }

  return (
    <VStack className="dashboard-page" gap={8} padding={8}>
      <VStack as="header" className="dashboard-header" gap={2}>
        <Text className="page-eyebrow" type="supporting" color="secondary" weight="medium">
          {workspace.term.dateLabel} · {copy.week} {workspace.term.currentWeek}
        </Text>
        <Heading level={1}>
          {copy.welcome} {workspace.profile.firstName}.
        </Heading>
        <Text type="body" color="secondary">
          {copy.welcomeText}
        </Text>
      </VStack>

      <Layout
        height="auto"
        end={
          <LayoutPanel
            className="dashboard-planner-panel"
            isScrollable={false}
            label={copy.studyOverview}
            padding={0}
            width={320}
          >
            <VStack gap={6}>
              <VStack as="section" id="announcements" gap={3}>
                <VStack gap={1}>
                  <Link href={localizedPath(locale, routes.announcements.path())}>
                    <Heading level={2}>{copy.recentUpdates}</Heading>
                  </Link>
                  <Text type="supporting" color="secondary">
                    {copy.activeCoursesSource}
                  </Text>
                </VStack>
                <CourseUpdatesList
                  announcements={workspace.announcements}
                  courses={workspace.courses}
                  locale={locale}
                />
              </VStack>

              {SHOW_PROGRESS_NOTE && (
                <VStack as="section" className="study-note" gap={2}>
                  <Text type="supporting" color="secondary" weight="medium">
                    {copy.progressNote}
                  </Text>
                  <Text type="body">{copy.progressNoteText}</Text>
                </VStack>
              )}
            </VStack>
          </LayoutPanel>
        }
      >
        <LayoutContent isScrollable={false} label={copy.continueLearning} padding={0}>
          <VStack className="dashboard-main-column" gap={8}>
            <VStack as="section" aria-labelledby="continue-heading" gap={3}>
              <HStack gap={3} vAlign="center">
                <Heading id="continue-heading" level={2}>
                  {copy.continueLearning}
                </Heading>
                <StackItem size="fill" />
                <Text type="supporting" color="secondary">
                  {focusCourse.nextActivity.savedLabel}
                </Text>
              </HStack>

              <Card className="continue-card" padding={6}>
                <VStack gap={5}>
                  <VStack gap={2}>
                    <HStack gap={2} vAlign="center" wrap="wrap">
                      <span
                        className={`course-swatch tone-${focusCourse.tone}`}
                        aria-hidden="true"
                      />
                      <Text type="supporting" color="secondary" weight="medium">
                        {focusCourse.code} · {focusCourse.nextActivity.eyebrow}
                      </Text>
                    </HStack>
                    <Heading level={3}>{focusCourse.nextActivity.title}</Heading>
                    <Text type="body" color="secondary">
                      {focusCourse.nextActivity.description}
                    </Text>
                  </VStack>

                  <VStack gap={2}>
                    <HStack gap={3} vAlign="center">
                      <Text type="supporting" color="secondary">
                        {focusCourse.nextActivity.completedSteps} of{" "}
                        {focusCourse.nextActivity.totalSteps} {copy.checkpoints}
                      </Text>
                      <StackItem size="fill" />
                      <HStack gap={1} vAlign="center">
                        <Clock3 size={14} aria-hidden="true" />
                        <Text type="supporting" color="secondary">
                          {copy.aboutMinutes} {focusCourse.nextActivity.estimatedMinutes} min
                        </Text>
                      </HStack>
                    </HStack>
                    <ProgressBar
                      isLabelHidden
                      label={`${focusCourse.nextActivity.title} ${copy.progress}`}
                      max={focusCourse.nextActivity.totalSteps}
                      value={focusCourse.nextActivity.completedSteps}
                    />
                  </VStack>

                  <HStack gap={3} vAlign="center" wrap="wrap">
                    <Button
                      endContent={<ArrowRight size={16} />}
                      href={localizedPath(locale, focusCourse.nextActivity.href)}
                      label={copy.resume}
                      size="lg"
                      variant="primary"
                    />
                    <Button
                      href={localizedPath(locale, focusCourse.href)}
                      label={copy.viewCourse}
                      size="lg"
                      variant="ghost"
                    />
                  </HStack>
                </VStack>
              </Card>
            </VStack>

            <VStack as="section" id="week-plan" aria-labelledby="week-plan-heading" gap={3}>
              <HStack className="section-heading-row" gap={4} vAlign="center" wrap="wrap">
                <StackItem size="fill">
                  <VStack gap={1}>
                    <Heading id="week-plan-heading" level={2}>
                      {copy.thisWeek}
                    </Heading>
                    <Text type="supporting" color="secondary">
                      {copy.weeklyPlan}
                    </Text>
                  </VStack>
                </StackItem>
                <SegmentedControl
                  label={copy.filterActivities}
                  onChange={(value) => setFilter(value as AgendaFilter)}
                  size="sm"
                  value={filter}
                >
                  <SegmentedControlItem label={copy.todo} value="upcoming" />
                  <SegmentedControlItem label={copy.completed} value="completed" />
                  <SegmentedControlItem label={copy.all} value="all" />
                </SegmentedControl>
              </HStack>

              <List
                className="agenda-list"
                density="balanced"
                hasDividers
                header={<Text className="visually-hidden">{copy.weeklyActivities}</Text>}
              >
                {visibleAgenda.map((item) => {
                  const course = courseByOfferingKey.get(item.offeringKey);
                  const AgendaIcon = agendaIcons[item.type];
                  const isCompleted = item.status === "completed";
                  return (
                    <ListItem
                      description={
                        <Text type="supporting" color="secondary">
                          {course?.title} · {item.supporting}
                        </Text>
                      }
                      endContent={
                        <HStack className="agenda-end" gap={3} vAlign="center">
                          <VStack gap={0.5} hAlign="end">
                            <Text type="supporting" weight="medium">
                              {item.dueLabel}
                            </Text>
                            <Text type="supporting" color="secondary">
                              {agendaStatusLabel(item.status, copy.agendaStatus)}
                            </Text>
                          </VStack>
                          <ChevronRight size={17} aria-hidden="true" />
                        </HStack>
                      }
                      href={localizedPath(locale, item.href)}
                      key={item.id}
                      label={
                        <Text
                          type="body"
                          weight="medium"
                          hasStrikethrough={isCompleted}
                          color={isCompleted ? "secondary" : "primary"}
                        >
                          {item.title}
                        </Text>
                      }
                      startContent={
                        <span className={`agenda-icon type-${item.type}`} aria-hidden="true">
                          {isCompleted ? <Check size={17} /> : <AgendaIcon size={17} />}
                        </span>
                      }
                    />
                  );
                })}
              </List>
            </VStack>

            <VStack as="section" id="courses" aria-labelledby="courses-heading" gap={3}>
              <VStack gap={1}>
                <Heading id="courses-heading" level={2}>
                  {copy.courseProgress}
                </Heading>
                <Text type="supporting" color="secondary">
                  {workspace.term.label} · {workspace.courses.length} {copy.activeEnrollments}
                </Text>
              </VStack>
              <List
                className="course-list"
                density="spacious"
                hasDividers
                header={<Text className="visually-hidden">{copy.enrolledCourses}</Text>}
              >
                {workspace.courses.map((course) => {
                  const CourseIcon = getCourseIcon(course.courseDefinitionSlug);

                  return (
                    <ListItem
                      description={
                        <VStack gap={0.5}>
                          <Text type="supporting" color="secondary" maxLines={1}>
                            {course.code} · {course.summary}
                          </Text>
                          <Text type="supporting" color="secondary">
                            <span className="visually-hidden">{copy.courseDates}: </span>
                            <time dateTime={course.startDate}>
                              {formatCourseDate(course.startDate, locale)}
                            </time>{" "}
                            –{" "}
                            <time dateTime={course.endDate}>
                              {formatCourseDate(course.endDate, locale)}
                            </time>
                          </Text>
                        </VStack>
                      }
                      endContent={
                        <VStack className="course-progress-cell" gap={1}>
                          <HStack gap={2} vAlign="center">
                            <StatusDot
                              label={copy.status[course.status]}
                              variant={statusVariants[course.status]}
                            />
                            <Text type="supporting" color="secondary">
                              {copy.status[course.status]}
                            </Text>
                            <StackItem size="fill" />
                            <Text type="supporting" hasTabularNumbers>
                              {course.progress}%
                            </Text>
                          </HStack>
                          <ProgressBar
                            isLabelHidden
                            label={`${course.title} ${copy.progress}`}
                            value={course.progress}
                            variant={course.progress === 100 ? "success" : "accent"}
                          />
                        </VStack>
                      }
                      href={localizedPath(locale, course.href)}
                      key={course.offeringKey}
                      label={
                        <Text type="large" weight="semibold">
                          {course.title}
                        </Text>
                      }
                      startContent={<CourseIcon size={20} aria-hidden="true" />}
                    />
                  );
                })}
              </List>
            </VStack>
          </VStack>
        </LayoutContent>
      </Layout>
    </VStack>
  );
}

// Astro probes framework components during SSR renderer detection by invoking
// the exported function once. Keep that probe hook-free; the actual component
// with hooks is rendered by React in the returned element tree.
export default function DashboardIsland(props: Props) {
  return <DashboardContent {...props} />;
}
