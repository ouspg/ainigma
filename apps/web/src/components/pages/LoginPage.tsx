import { Button } from "@astryxdesign/core/Button";
import { Card } from "@astryxdesign/core/Card";
import { Center } from "@astryxdesign/core/Center";
import { Link } from "@astryxdesign/core/Link";
import { VStack } from "@astryxdesign/core/Stack";
import { Heading, Text } from "@astryxdesign/core/Text";
import { InternationalizationProvider } from "@astryxdesign/core/i18n";
import fiFI from "@astryxdesign/core/locales/fi-FI.json";
import { KeyRound } from "lucide-react";
import { getAstryxLocale, getMessages, localizedPath, type Locale } from "../../lib/i18n";
import PublicHeader from "../shell/PublicHeader";
import SiteFooter from "../shell/SiteFooter";
import { AppearanceThemeProvider } from "../theme/AppearanceThemeProvider";

interface Props {
  locale: Locale;
}

export default function LoginPage({ locale }: Props) {
  const messages = getMessages(locale);
  const copy = messages.login;

  const signIn = () => window.location.assign(localizedPath(locale, "/desk/"));

  return (
    <InternationalizationProvider locale={getAstryxLocale(locale)} messages={{ "fi-FI": fiFI }}>
      <AppearanceThemeProvider>
        <VStack className="login-page">
          <PublicHeader currentPath="/login/" locale={locale} />
          <Center className="login-center" axis="both" minHeight="fill">
            <VStack className="login-panel" gap={5} hAlign="stretch">
              <VStack gap={2} hAlign="center">
                <Text className="page-eyebrow" type="supporting" color="secondary" weight="medium">
                  {copy.university}
                </Text>
                <Heading className="login-title" level={1}>
                  {copy.title}
                </Heading>
                <Text type="body" color="secondary" justify="center">
                  {copy.intro}
                </Text>
              </VStack>
              <Card padding={6}>
                <VStack gap={4}>
                  <Button
                    icon={<KeyRound size={17} />}
                    label={copy.continue}
                    onClick={signIn}
                    size="lg"
                    variant="primary"
                    width="100%"
                  />
                  <Text type="supporting" color="secondary">
                    {copy.note}
                  </Text>
                </VStack>
              </Card>
              <Text type="supporting" color="secondary" justify="center">
                {copy.access}{" "}
                <Link href="https://opas.peppi.oulu.fi" target="_blank">
                  {copy.peppi}
                </Link>
                .
              </Text>
            </VStack>
          </Center>
          <SiteFooter locale={locale} />
        </VStack>
      </AppearanceThemeProvider>
    </InternationalizationProvider>
  );
}
