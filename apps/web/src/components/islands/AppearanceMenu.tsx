import {
  DropdownMenu,
  DropdownMenuDivider,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
} from "@astryxdesign/core/DropdownMenu";
import { Text } from "@astryxdesign/core/Text";
import { Palette } from "lucide-react";
import { appearanceThemes, isAppearanceTheme, isColorMode } from "../../lib/appearance";
import { getMessages, type Locale } from "../../lib/i18n";
import { useAppearance } from "../theme/useAppearance";
import AppearanceThemeIcon from "../theme/AppearanceThemeIcon";
import ColorModeIcon from "../theme/ColorModeIcon";

interface Props {
  locale: Locale;
}

export default function AppearanceMenu({ locale }: Props) {
  const copy = getMessages(locale).appearance;
  const { appearanceTheme, colorMode, setAppearanceTheme, setColorMode } = useAppearance();

  return (
    <DropdownMenu
      alignment="end"
      button={{
        label: copy.label,
        icon: <Palette size={17} aria-hidden="true" />,
        isIconOnly: true,
        size: "sm",
        tooltip: copy.label,
        variant: "ghost",
      }}
      hasChevron={false}
      menuWidth={264}
    >
      <Text
        className="appearance-menu-heading"
        type="supporting"
        color="secondary"
        weight="semibold"
      >
        {copy.theme}
      </Text>
      <DropdownMenuRadioGroup
        value={appearanceTheme}
        onChange={(value) => isAppearanceTheme(value) && setAppearanceTheme(value)}
        label={copy.theme}
      >
        {appearanceThemes.map((theme) => (
          <DropdownMenuRadioItem
            icon={<AppearanceThemeIcon theme={theme} />}
            key={theme}
            value={theme}
            label={copy.themeNames[theme]}
          />
        ))}
      </DropdownMenuRadioGroup>
      <DropdownMenuDivider className="appearance-menu-divider" style={{}} />
      <Text
        className="appearance-menu-heading"
        type="supporting"
        color="secondary"
        weight="semibold"
      >
        {copy.colorMode}
      </Text>
      <DropdownMenuRadioGroup
        value={colorMode}
        onChange={(value) => isColorMode(value) && setColorMode(value)}
        label={copy.colorMode}
      >
        <DropdownMenuRadioItem
          value="system"
          icon={<ColorModeIcon mode="system" />}
          label={copy.system}
        />
        <DropdownMenuRadioItem
          value="light"
          icon={<ColorModeIcon mode="light" />}
          label={copy.light}
        />
        <DropdownMenuRadioItem
          value="dark"
          icon={<ColorModeIcon mode="dark" />}
          label={copy.dark}
        />
      </DropdownMenuRadioGroup>
    </DropdownMenu>
  );
}
