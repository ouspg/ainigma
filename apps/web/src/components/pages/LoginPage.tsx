import { useState } from "react";
import { Button } from "@astryxdesign/core/Button";
import { Card } from "@astryxdesign/core/Card";
import { Center } from "@astryxdesign/core/Center";
import { Link } from "@astryxdesign/core/Link";
import { VStack } from "@astryxdesign/core/Stack";
import { Heading, Text } from "@astryxdesign/core/Text";
import { InternationalizationProvider } from "@astryxdesign/core/i18n";
import fiFI from "@astryxdesign/core/locales/fi-FI.json";
import { KeyRound } from "lucide-react";
import { externalLinks } from "../../lib/external-links";
import { getAstryxLocale, getMessages, type Locale } from "../../lib/i18n";
import { routes, type AppPath } from "../../lib/routes";
import { createBrowserSupabaseClient } from "../../lib/supabase/browser";
import PublicHeader from "../shell/PublicHeader";
import SiteFooter from "../shell/SiteFooter";
import { AppearanceThemeProvider } from "../theme/AppearanceThemeProvider";

interface Props {
  authError: boolean;
  locale: Locale;
  next: AppPath;
}

export default function LoginPage({ authError, locale, next }: Props) {
  const messages = getMessages(locale);
  const copy = messages.login;
  const [isSigningIn, setSigningIn] = useState(false);
  const [startError, setStartError] = useState(false);

  const signIn = async () => {
    setSigningIn(true);
    setStartError(false);

    try {
      const callbackUrl = new URL(routes.authCallback.path(), window.location.origin);
      callbackUrl.searchParams.set("next", next);
      const supabase = createBrowserSupabaseClient();
      const { error } = await supabase.auth.signInWithOAuth({
        provider: "github",
        options: { redirectTo: callbackUrl.toString() },
      });

      if (error) throw error;
    } catch {
      setStartError(true);
      setSigningIn(false);
    }
  };

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
                  <Button
                    icon={<KeyRound size={17} />}
                    isLoading={isSigningIn}
                    label={copy.continue}
                    onClick={signIn}
                    size="lg"
                    variant="primary"
                    width="100%"
                  />
                  <Text type="supporting" color="secondary">
                    {copy.note}
                  </Text>
                  {authError || startError ? (
                    <Text className="login-auth-error" type="supporting">
                      {startError ? copy.startError : copy.authError}
                    </Text>
                  ) : null}
                </VStack>
              </Card>
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
