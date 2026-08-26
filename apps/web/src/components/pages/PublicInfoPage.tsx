import { Section } from "@astryxdesign/core/Section";
import { VStack } from "@astryxdesign/core/Stack";
import { Heading, Text } from "@astryxdesign/core/Text";
import { getMessages, type Locale } from "../../lib/i18n";
import { routes } from "../../lib/routes";
import PublicPageFrame from "../shell/PublicPageFrame";

type PageKind = "about" | "privacy";

interface Props {
  kind: PageKind;
  locale: Locale;
}

export default function PublicInfoPage({ kind, locale }: Props) {
  const messages = getMessages(locale);
  const copy = messages.publicInfo;
  const isAbout = kind === "about";
  const title = isAbout ? copy.aboutTitle : copy.privacyTitle;
  const intro = isAbout ? copy.aboutIntro : copy.privacyIntro;
  const sectionTitle = isAbout ? copy.aboutSectionTitle : copy.privacySectionTitle;
  const placeholder = isAbout ? copy.aboutPlaceholder : copy.privacyPlaceholder;
  const currentPath = isAbout ? routes.about.path() : routes.privacy.path();

  return (
    <PublicPageFrame currentPath={currentPath} locale={locale}>
      <Section className="public-info-intro" padding={0} variant="transparent">
        <VStack className="public-intro-copy" gap={3} hAlign="start">
          <Text className="page-eyebrow" type="supporting" color="secondary" weight="medium">
            {messages.navigation.university}
          </Text>
          <Heading className="public-title" level={1}>
            {title}
          </Heading>
          <Text className="public-lede" type="large" color="secondary">
            {intro}
          </Text>
        </VStack>
      </Section>

      <Section className="public-info-section" dividers={["top"]} padding={0} variant="transparent">
        <VStack className="public-section-heading" gap={3}>
          <Heading level={2}>{sectionTitle}</Heading>
          <Text type="body" color="secondary">
            {placeholder}
          </Text>
        </VStack>
      </Section>
    </PublicPageFrame>
  );
}
