import { Button } from "@astryxdesign/core/Button";
import { features } from "../../lib/features";
import { getMessages, getOtherLocale, type Locale } from "../../lib/i18n";
import { localizedPath, type AppPath } from "../../lib/routes";

interface Props {
  locale: Locale;
  path: AppPath;
}

export default function LocaleSwitcher({ locale, path }: Props) {
  if (!features.finnish) return null;

  const otherLocale = getOtherLocale(locale);
  const option = getMessages(locale).languageSwitcher.options[otherLocale];

  return (
    <Button
      className="locale-switcher"
      href={localizedPath(otherLocale, path)}
      {...{ hrefLang: otherLocale }}
      label={`${option.name}: ${option.switchLabel}`}
      rel="alternate"
      size="sm"
      variant="ghost"
    >
      <span lang={otherLocale}>{option.name}</span>
    </Button>
  );
}
