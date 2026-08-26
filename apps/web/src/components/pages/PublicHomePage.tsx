import { Button } from "@astryxdesign/core/Button";
import { Card } from "@astryxdesign/core/Card";
import { Link } from "@astryxdesign/core/Link";
import { List, ListItem } from "@astryxdesign/core/List";
import { Section } from "@astryxdesign/core/Section";
import { HStack, VStack } from "@astryxdesign/core/Stack";
import { Heading, Text } from "@astryxdesign/core/Text";
import { ArrowRight } from "lucide-react";
import { externalLinks } from "../../lib/external-links";
import type { PublicCourseInfo } from "../../lib/learning/types";
import { getMessages, type Locale } from "../../lib/i18n";
import { localizedPath, routes } from "../../lib/routes";
import PublicPageFrame from "../shell/PublicPageFrame";

interface Props {
  courses: PublicCourseInfo[];
  locale: Locale;
}

export default function PublicHomePage({ courses, locale }: Props) {
  const copy = getMessages(locale).publicHome;

  return (
    <PublicPageFrame currentPath={routes.home.path()} locale={locale}>
      <Section className="public-intro" padding={0} variant="transparent">
        <section className="public-intro-grid">
          <VStack className="public-intro-copy" gap={4} hAlign="start">
            <Text className="public-unit" type="supporting" color="secondary" weight="medium">
              {copy.unit}
            </Text>
            <Heading className="public-title" level={1}>
              {copy.title}
            </Heading>
            <Text className="public-lede" type="large" color="secondary">
              {copy.intro}
            </Text>
            <aside className="public-alpha-note" aria-label={copy.alphaLabel}>
              <span className="public-alpha-label">{copy.alphaLabel}</span>
              <Text type="supporting" color="secondary">
                {copy.alphaText}
              </Text>
            </aside>
          </VStack>

          <Card className="public-access-card public-access-panel" padding={6}>
            <VStack gap={4}>
              <Text className="public-panel-index" type="supporting" color="secondary">
                01 / {copy.accessSectionLabel}
              </Text>
              <Heading level={2}>{copy.access}</Heading>
              <Text type="body" color="secondary">
                {copy.accessText}
              </Text>
              <HStack className="public-access-actions" gap={4} wrap="wrap">
                <Link
                  href={externalLinks.peppi}
                  isExternalLink
                  isStandalone
                  newTabLabel={copy.opensInNewTab}
                >
                  {copy.peppi}
                </Link>
              </HStack>
            </VStack>
          </Card>
        </section>
      </Section>

      <Section className="public-section" id="course-spaces" padding={0} variant="transparent">
        <VStack className="public-course-card" gap={5}>
          <HStack className="public-course-heading" gap={6} vAlign="end" wrap="wrap">
            <VStack className="public-section-heading" gap={2}>
              <Text className="public-panel-index" type="supporting" color="secondary">
                02 / {copy.coursesSectionLabel}
              </Text>
              <Heading level={2}>{copy.courseSpaces}</Heading>
            </VStack>
            <Text className="public-course-count" type="body" color="secondary">
              {courses.length} {copy.published}
            </Text>
          </HStack>
          <List
            className="public-course-list"
            density="spacious"
            hasDividers
            header={<Text className="visually-hidden">{copy.courseListLabel}</Text>}
          >
            {courses.map((course) => (
              <ListItem
                description={
                  <Text type="supporting" color="secondary">
                    {course.summary}
                  </Text>
                }
                endContent={
                  <HStack className="public-course-actions" gap={4} vAlign="center" wrap="wrap">
                    <Button
                      endContent={<ArrowRight size={15} aria-hidden="true" />}
                      href={localizedPath(locale, routes.course.path({ course: course.slug }))}
                      label={copy.viewCourse}
                      size="sm"
                      variant="primary"
                    />
                    {course.catalogUrl ? (
                      <Link
                        href={course.catalogUrl}
                        isExternalLink
                        isStandalone
                        newTabLabel={copy.opensInNewTab}
                      >
                        {copy.peppiCourse}
                      </Link>
                    ) : null}
                  </HStack>
                }
                key={course.slug}
                label={
                  <Text type="large" weight="semibold">
                    {course.title}
                  </Text>
                }
                startContent={
                  <Text className="public-course-code" type="supporting" color="secondary">
                    {course.code}
                  </Text>
                }
              />
            ))}
          </List>
        </VStack>
      </Section>
    </PublicPageFrame>
  );
}
