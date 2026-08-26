import { lazy, Suspense } from "react";
import { Button } from "@astryxdesign/core/Button";
import { Card } from "@astryxdesign/core/Card";
import { Center } from "@astryxdesign/core/Center";
import { Link } from "@astryxdesign/core/Link";
import { VStack } from "@astryxdesign/core/Stack";
import { Heading, Text } from "@astryxdesign/core/Text";
import { InternationalizationProvider } from "@astryxdesign/core/i18n";
import fiFI from "@astryxdesign/core/locales/fi-FI.json";
import { KeyRound } from "lucide-react";
import type { LocalAuthPersonaOption } from "../../dev/dev-local-auth";
import { externalLinks } from "../../lib/external-links";
import { getAstryxLocale, getMessages, type Locale } from "../../lib/i18n";
import { routes, type AppPath } from "../../lib/routes";
import PublicHeader from "../shell/PublicHeader";
import SiteFooter from "../shell/SiteFooter";
import { AppearanceThemeProvider } from "../theme/AppearanceThemeProvider";

const LocalAuthPicker = import.meta.env.DEV
  ? lazy(() => import("../../dev/DevLocalAuthPicker"))
  : null;

interface Props {
  authError: boolean;
  locale: Locale;
  next: AppPath;
  localAuth: boolean;
  localAuthPersonas: readonly LocalAuthPersonaOption[];
}

export default function LoginPage({
  authError,
  locale,
  next,
  localAuth,
  localAuthPersonas,
}: Props) {
  const messages = getMessages(locale);
  const copy = messages.login;

  return (
    <InternationalizationProvider locale={getAstryxLocale(locale)} messages={{ "fi-FI": fiFI }}>
      <AppearanceThemeProvider>
        <VStack className="login-page">
          <PublicHeader currentPath={routes.login.path()} locale={locale} />
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
                  <form action={routes.authStart.path()} method="post">
                    <input name="next" type="hidden" value={next} />
                    <Button
                      icon={<KeyRound size={17} />}
                      label={copy.continue}
                      size="lg"
                      type="submit"
                      variant="primary"
                      width="100%"
                    />
                  </form>
                  <Text type="supporting" color="secondary">
                    {copy.note}
                  </Text>
                  {authError ? (
                    <Text className="login-auth-error" type="supporting">
                      {copy.authError}
                    </Text>
                  ) : null}
                </VStack>
              </Card>
              {localAuth && LocalAuthPicker ? (
                <Suspense fallback={null}>
                  <LocalAuthPicker locale={locale} next={next} personas={localAuthPersonas} />
                </Suspense>
              ) : null}
              <Text type="supporting" color="secondary" justify="center">
                {copy.access}{" "}
                <Link href={externalLinks.peppi} target="_blank">
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
