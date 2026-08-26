import { Button } from "@astryxdesign/core/Button";
import { Section } from "@astryxdesign/core/Section";
import { HStack, VStack } from "@astryxdesign/core/Stack";
import { Heading, Text } from "@astryxdesign/core/Text";
import { getMessages, type Locale } from "../../lib/i18n";
import { localizedPath, routes } from "../../lib/routes";
import PublicPageFrame from "../shell/PublicPageFrame";

export type ErrorStatus = 403 | 404 | 500 | 503;

interface Props {
  status: ErrorStatus;
  locale: Locale;
}

export default function ErrorPage({ status, locale }: Props) {
  const messages = getMessages(locale);
  const copy =
    status === 403
      ? { title: messages.errors.accessDeniedTitle, message: messages.errors.accessDeniedMessage }
      : status === 500
        ? { title: messages.errors.serverErrorTitle, message: messages.errors.serverErrorMessage }
        : status === 503
          ? { title: messages.errors.unavailableTitle, message: messages.errors.unavailableMessage }
          : { title: messages.errors.notFoundTitle, message: messages.errors.notFoundMessage };

  return (
    <PublicPageFrame currentPath={routes.status.path({ code: String(status) })} locale={locale}>
      <Section className="public-info-intro error-page" padding={0} variant="transparent">
        <VStack className="public-intro-copy" gap={4} hAlign="start">
          <Text className="page-eyebrow" type="supporting" color="secondary" weight="medium">
            {status}
          </Text>
          <Heading className="public-title" level={1}>
            {copy.title}
          </Heading>
          <Text className="public-lede" type="large" color="secondary">
            {copy.message}
          </Text>
          <HStack>
            <Button
              href={localizedPath(locale, routes.home.path())}
              label={messages.errors.returnHome}
              variant="primary"
            />
          </HStack>
        </VStack>
      </Section>
    </PublicPageFrame>
  );
}
