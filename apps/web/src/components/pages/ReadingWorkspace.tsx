import type { ReactNode } from "react";
import { Button } from "@astryxdesign/core/Button";
import { Layout, LayoutContent, LayoutPanel } from "@astryxdesign/core/Layout";
import { HStack, StackItem, VStack } from "@astryxdesign/core/Stack";
import { Heading, Text } from "@astryxdesign/core/Text";
import { ArrowLeft, ArrowRight, Clock3 } from "lucide-react";
import type { OutlineSection } from "../../lib/learning/catalog";
import { getMessages, type Locale } from "../../lib/i18n";
import { localizedPath, type AppPath } from "../../lib/routes";

interface PageLink {
  href: AppPath;
  label: string;
}

interface Props {
  eyebrow: string;
  title: string;
  summary: string;
  meta?: string[];
  outline?: OutlineSection[];
  previous?: PageLink;
  next?: PageLink;
  locale: Locale;
  children: ReactNode;
}

export default function ReadingWorkspace({
  eyebrow,
  title,
  summary,
  meta = [],
  outline = [],
  previous,
  next,
  locale,
  children,
}: Props) {
  const copy = getMessages(locale).reading;

  return (
    <VStack className="reading-workspace" gap={8} padding={8}>
      <VStack as="header" className="reading-header" gap={3}>
        <Text className="page-eyebrow" type="supporting" color="secondary" weight="medium">
          {eyebrow}
        </Text>
        <Heading className="reading-title" level={1}>
          {title}
        </Heading>
        <Text type="large" color="secondary">
          {summary}
        </Text>
        {meta.length > 0 && (
          <HStack gap={3} vAlign="center" wrap="wrap">
            {meta.map((item, index) => (
              <HStack gap={1} vAlign="center" key={item}>
                {index === 0 && <Clock3 size={14} aria-hidden="true" />}
                <Text type="supporting" color="secondary">
                  {item}
                </Text>
              </HStack>
            ))}
          </HStack>
        )}
      </VStack>

      <Layout
        className="reading-layout"
        height="auto"
        end={
          outline.length > 0 ? (
            <LayoutPanel
              className="reading-outline-panel"
              isScrollable={false}
              label="On this page"
              padding={0}
              width={240}
            >
              <nav className="outline-nav" aria-label={copy.onThisPage}>
                <VStack gap={2}>
                  <Text type="supporting" color="secondary" weight="medium">
                    {copy.onThisPage}
                  </Text>
                  <VStack gap={0}>
                    {outline.map((section) => (
                      <a
                        className={`outline-link${section.depth === 3 ? " is-nested" : ""}`}
                        href={`#${section.slug}`}
                        key={section.slug}
                      >
                        {section.text}
                      </a>
                    ))}
                  </VStack>
                </VStack>
              </nav>
            </LayoutPanel>
          ) : undefined
        }
      >
        <LayoutContent isScrollable={false} label={copy.material} padding={0}>
          <article className="reading-prose">{children}</article>

          {(previous || next) && (
            <nav className="lesson-navigation" aria-label={copy.navigation}>
              <HStack gap={3} vAlign="center" wrap="wrap">
                {previous ? (
                  <Button
                    href={localizedPath(locale, previous.href)}
                    icon={<ArrowLeft size={16} />}
                    label={previous.label}
                    variant="secondary"
                  />
                ) : (
                  <span />
                )}
                <StackItem size="fill" />
                {next && (
                  <Button
                    endContent={<ArrowRight size={16} />}
                    href={localizedPath(locale, next.href)}
                    label={next.label}
                    variant="primary"
                  />
                )}
              </HStack>
            </nav>
          )}
        </LayoutContent>
      </Layout>
    </VStack>
  );
}
