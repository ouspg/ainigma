import { describe, expect, it } from "vite-plus/test";
import { featureDefinitions, resolveFeatureFlags } from "./features";
import { getAstryxLocale, getLocale, getMessages } from "./i18n";
import { localizedPath } from "./routes";

describe("localization helpers", () => {
  it("maps Astro locales to the supported app locales", () => {
    expect(getLocale("fi-FI")).toBe("fi");
    expect(getLocale("fi")).toBe("fi");
    expect(getLocale("sv")).toBe("en");
    expect(getAstryxLocale("fi")).toBe("fi-FI");
  });

  it("keeps the default locale unprefixed and prefixes Finnish routes", () => {
    expect(localizedPath("en", "/desk/")).toBe("/desk/");
    expect(localizedPath("fi", "/desk/")).toBe("/fi/desk/");
    expect(localizedPath("fi", "/")).toBe("/fi/");
    expect(localizedPath("fi", "/courses/security/?tab=map")).toBe("/fi/courses/security/?tab=map");
  });

  it("serves all app copy from the locale catalog", () => {
    expect(getMessages("fi").navigation.desk).toBe("Oma oppiminen");
    expect(getMessages("fi").metadata.deskTitle).toContain("Oma oppiminen");
    expect(getMessages("en").languageSwitcher.options.fi).toEqual({
      name: "Suomi",
      switchLabel: "Switch language to Finnish",
    });
    expect(getMessages("fi").languageSwitcher.options.en.switchLabel).toBe(
      "Vaihda kieleksi englanti",
    );
    expect(getMessages("en").footer.privacy).toBe("Privacy policy");
    expect(getMessages("en").footer.sourceCode).toBe("Source Code");
    expect(getMessages("en").footer.identity).toBe(
      "Ainigma · Oulu University Secure Programming Group",
    );
    expect(getMessages("fi").footer.about).toBe("Tietoa palvelusta");
    expect(getMessages("fi").footer.sourceCode).toBe("Lähdekoodi");
    expect(getMessages("en").publicHome.unit).toBe(
      "By Oulu University Secure Programming Group (OUSPG)",
    );
  });
});

describe("feature flags", () => {
  it("keeps unfinished Finnish content disabled by default", () => {
    expect(featureDefinitions.finnish.defaultEnabled).toBe(false);
    expect(resolveFeatureFlags({}).finnish).toBe(false);
  });

  it("accepts explicit environment switches", () => {
    expect(resolveFeatureFlags({ PUBLIC_FEATURE_FINNISH: "true" }).finnish).toBe(true);
    expect(resolveFeatureFlags({ PUBLIC_FEATURE_FINNISH: "off" }).finnish).toBe(false);
  });
});
