import { Button } from "@astryxdesign/core/Button";
import { Card } from "@astryxdesign/core/Card";
import { VStack } from "@astryxdesign/core/Stack";
import { Heading, Text } from "@astryxdesign/core/Text";
import type { LocalAuthPersonaOption } from "../lib/auth/dev-local-auth";
import { getMessages, type Locale } from "../lib/i18n";
import { routes, type AppPath } from "../lib/routes";

interface Props {
  locale: Locale;
  next: AppPath;
  personas: readonly LocalAuthPersonaOption[];
}

export default function LocalAuthPicker({ locale, next, personas }: Props) {
  const copy = getMessages(locale).login;

  const signInAsLocalPersona = (persona: LocalAuthPersonaOption["key"]) => {
    const localAuthUrl = new URL(routes.authLocal.path(), window.location.origin);
    localAuthUrl.searchParams.set("next", next);
    localAuthUrl.searchParams.set("persona", persona);
    window.location.assign(localAuthUrl);
  };

  return (
    <Card padding={6}>
      <VStack gap={3}>
        <VStack gap={1}>
          <Heading level={2}>{copy.localTitle}</Heading>
          <Text type="supporting" color="secondary">
            {copy.localDescription}
          </Text>
        </VStack>
        {personas.map((persona) => (
          <VStack key={persona.key} gap={1}>
            <Button
              label={persona.label}
              onClick={() => signInAsLocalPersona(persona.key)}
              size="md"
              variant="secondary"
              width="100%"
            />
            <Text type="supporting" color="secondary">
              {persona.description}
            </Text>
          </VStack>
        ))}
        <Text type="supporting" color="secondary">
          {copy.localNote}
        </Text>
      </VStack>
    </Card>
  );
}
