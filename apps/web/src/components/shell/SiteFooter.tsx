import { Link } from "@astryxdesign/core/Link";
import { Section } from "@astryxdesign/core/Section";
import { HStack, StackItem } from "@astryxdesign/core/Stack";
import { Text } from "@astryxdesign/core/Text";
import { getMessages, localizedPath, type Locale } from "../../lib/i18n";

interface Props {
  locale: Locale;
}

const SOURCE_CODE_URL = "https://github.com/ouspg/ainigma";

export default function SiteFooter({ locale }: Props) {
  const copy = getMessages(locale).footer;

  return (
    <footer className="site-footer">
      <Section className="public-footer" dividers={["top"]} padding={0} variant="transparent">
        <HStack className="public-footer-row" gap={4} vAlign="center" wrap="wrap">
          <Text type="supporting" color="secondary">
            {copy.identity}
          </Text>
          <StackItem size="fill" />
          <HStack as="nav" aria-label={copy.navigation} gap={4} vAlign="center" wrap="wrap">
            <Link href={localizedPath(locale, "/about/")}>{copy.about}</Link>
            <Link href={localizedPath(locale, "/privacy/")}>{copy.privacy}</Link>
            <Link href={SOURCE_CODE_URL} target="_blank">
              {copy.sourceCode}
            </Link>
          </HStack>
        </HStack>
      </Section>
    </footer>
  );
}
