import type { ReactNode } from "react";
import { Button } from "@astryxdesign/core/Button";
import { Card } from "@astryxdesign/core/Card";
import { Divider } from "@astryxdesign/core/Divider";
import { Layout, LayoutContent, LayoutPanel } from "@astryxdesign/core/Layout";
import { List, ListItem } from "@astryxdesign/core/List";
import { ProgressBar } from "@astryxdesign/core/ProgressBar";
import { HStack, VStack } from "@astryxdesign/core/Stack";
import { StatusDot } from "@astryxdesign/core/StatusDot";
import { Heading, Text } from "@astryxdesign/core/Text";
import {
  ArrowRight,
  BookMarked,
  CalendarDays,
  Check,
  ChevronRight,
  Circle,
  Clock3,
  ExternalLink,
} from "lucide-react";
import type { CourseInfo, CourseStatus } from "../../lib/learning/types";
import { getMessages, localizedPath, type Locale } from "../../lib/i18n";

interface Props {
  course: CourseInfo;
  locale: Locale;
  children: ReactNode;
}

const statusVariants: Record<CourseStatus, "neutral" | "accent" | "success"> = {
  "not-started": "neutral",
  "in-progress": "accent",
  completed: "success",
};

export default function CourseOverview({ course, locale, children }: Props) {
  const completedWeeks = course.weeks.filter((week) => week.status === "completed").length;
  const copy = getMessages(locale).course;
  const labels = copy.status;

  return (
    <VStack className="course-workspace" gap={8} padding={8}>
      <VStack as="header" className="course-header" gap={3}>
        <HStack gap={2} vAlign="center" wrap="wrap">
          <Text className="page-eyebrow" type="supporting" color="secondary" weight="medium">
            {course.code} · {copy.workspace}
          </Text>
          <StatusDot label={labels[course.status]} variant={statusVariants[course.status]} />
          <Text type="supporting" color="secondary">
            {labels[course.status]}
          </Text>
        </HStack>
        <Heading className="course-title" level={1}>
          {course.title}
        </Heading>
        <Text type="large" color="secondary">
          {course.summary}
        </Text>
      </VStack>

      <Layout
        className="course-overview-layout"
        height="auto"
        end={
          <LayoutPanel
            className="course-overview-panel"
            isScrollable={false}
            label={copy.details}
            padding={0}
            width={240}
          >
            <VStack gap={6}>
              <Card padding={5}>
                <VStack gap={4}>
                  <VStack gap={1}>
                    <Text type="supporting" color="secondary" weight="medium">
                      {copy.record}
                    </Text>
                    <Heading level={2}>{copy.progress}</Heading>
                  </VStack>
                  <HStack gap={2} vAlign="end">
                    <Text className="term-percentage" type="display-3" hasTabularNumbers>
                      {course.progress}%
                    </Text>
                    <Text type="supporting" color="secondary">
                      {copy.complete}
                    </Text>
                  </HStack>
                  <ProgressBar
                    isLabelHidden
                    label={`${course.title} completion`}
                    value={course.progress}
                  />
                  <Divider />
                  <HStack gap={4}>
                    <VStack gap={0.5}>
                      <Text type="large" hasTabularNumbers>
                        {course.earnedPoints}
                      </Text>
                      <Text type="supporting" color="secondary">
                        {copy.points}
                      </Text>
                    </VStack>
                    <VStack gap={0.5}>
                      <Text type="large" hasTabularNumbers>
                        {completedWeeks}/{course.weeks.length}
                      </Text>
                      <Text type="supporting" color="secondary">
                        {copy.weeks}
                      </Text>
                    </VStack>
                  </HStack>
                </VStack>
              </Card>

              {(course.pages.length > 0 || course.catalogUrl) && (
                <VStack as="section" gap={3}>
                  <Heading level={2}>{copy.links}</Heading>
                  <List
                    density="compact"
                    hasDividers
                    header={<Text className="visually-hidden">{copy.courseLinks}</Text>}
                  >
                    {course.pages.map((page) => (
                      <ListItem
                        endContent={<ChevronRight size={16} aria-hidden="true" />}
                        href={localizedPath(locale, page.href)}
                        key={page.page}
                        label={page.label}
                        startContent={<BookMarked size={17} aria-hidden="true" />}
                      />
                    ))}
                    {course.catalogUrl && (
                      <ListItem
                        endContent={<ExternalLink size={15} aria-hidden="true" />}
                        href={course.catalogUrl}
                        label={copy.peppi}
                        startContent={<CalendarDays size={17} aria-hidden="true" />}
                        target="_blank"
                      />
                    )}
                  </List>
                </VStack>
              )}
            </VStack>
          </LayoutPanel>
        }
      >
        <LayoutContent isScrollable={false} label={copy.overview} padding={0}>
          <VStack gap={8}>
            <VStack as="section" aria-labelledby="next-activity-heading" gap={3}>
              <Heading id="next-activity-heading" level={2}>
                {copy.next}
              </Heading>
              <Card className="continue-card" padding={5}>
                <VStack gap={4}>
                  <VStack gap={1}>
                    <Text type="supporting" color="secondary" weight="medium">
                      {course.nextActivity.eyebrow}
                    </Text>
                    <Heading level={3}>{course.nextActivity.title}</Heading>
                    <Text type="body" color="secondary">
                      {course.nextActivity.description}
                    </Text>
                  </VStack>
                  <HStack gap={3} vAlign="center" wrap="wrap">
                    <Button
                      endContent={<ArrowRight size={16} />}
                      href={localizedPath(locale, course.nextActivity.href)}
                      label={course.progress > 0 ? copy.continue : copy.start}
                      variant="primary"
                    />
                    <HStack gap={1} vAlign="center">
                      <Clock3 size={14} aria-hidden="true" />
                      <Text type="supporting" color="secondary">
                        {course.nextActivity.estimatedMinutes} {copy.minutes}
                      </Text>
                    </HStack>
                  </HStack>
                </VStack>
              </Card>
            </VStack>

            {course.weeks.length > 0 && (
              <VStack as="section" aria-labelledby="course-map-heading" gap={3}>
                <VStack gap={1}>
                  <Heading id="course-map-heading" level={2}>
                    {copy.map}
                  </Heading>
                  <Text type="supporting" color="secondary">
                    {copy.mapDescription}
                  </Text>
                </VStack>
                <nav className="course-map" aria-label={copy.map}>
                  {course.weeks.map((week) => (
                    <a
                      className="course-map-row"
                      href={localizedPath(locale, week.href)}
                      key={week.slug}
                    >
                      <HStack gap={4} vAlign="start">
                        <span className={`week-state is-${week.status}`} aria-hidden="true">
                          {week.status === "completed" ? <Check size={16} /> : <Circle size={13} />}
                        </span>
                        <VStack gap={1}>
                          <Text type="supporting" color="secondary" weight="medium">
                            {copy.week} {week.number}
                          </Text>
                          <Heading level={3}>{week.title}</Heading>
                          <Text type="supporting" color="secondary">
                            {week.summary}
                          </Text>
                        </VStack>
                      </HStack>
                      <VStack className="course-map-meta" gap={1} hAlign="end">
                        <Text type="supporting" weight="medium">
                          {labels[week.status]}
                        </Text>
                        <Text type="supporting" color="secondary">
                          {week.tasks.length}{" "}
                          {week.tasks.length === 1 ? copy.activity : copy.activities}
                        </Text>
                      </VStack>
                    </a>
                  ))}
                </nav>
              </VStack>
            )}

            <VStack as="section" aria-labelledby="about-course-heading" gap={4}>
              <Heading id="about-course-heading" level={2}>
                {copy.about}
              </Heading>
              <article className="course-prose">{children}</article>
            </VStack>
          </VStack>
        </LayoutContent>
      </Layout>
    </VStack>
  );
}
