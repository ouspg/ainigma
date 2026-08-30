import type { AppearanceTheme } from "./appearance";

export const locales = ["en", "fi"] as const;
export type Locale = (typeof locales)[number];
export const defaultLocale: Locale = "en";

export interface AppMessages {
  appearance: {
    label: string;
    theme: string;
    themeNames: Record<AppearanceTheme, string>;
    colorMode: string;
    system: string;
    light: string;
    dark: string;
  };
  languageSwitcher: {
    options: Record<
      Locale,
      {
        name: string;
        switchLabel: string;
      }
    >;
  };
  metadata: {
    homeTitle: string;
    homeDescription: string;
    loginTitle: string;
    loginDescription: string;
    deskTitle: string;
    deskDescription: string;
    activityTitle: string;
    activityDescription: string;
    aboutTitle: string;
    aboutDescription: string;
    privacyTitle: string;
    privacyDescription: string;
  };
  publicHome: {
    signIn: string;
    unit: string;
    title: string;
    intro: string;
    alphaLabel: string;
    alphaText: string;
    coursesSectionLabel: string;
    courseSpaces: string;
    published: string;
    accessSectionLabel: string;
    access: string;
    accessText: string;
    viewCourse: string;
    peppi: string;
    peppiCourse: string;
    opensInNewTab: string;
    courseListLabel: string;
  };
  footer: {
    identity: string;
    navigation: string;
    about: string;
    privacy: string;
    sourceCode: string;
  };
  publicInfo: {
    aboutTitle: string;
    aboutIntro: string;
    aboutSectionTitle: string;
    aboutPlaceholder: string;
    privacyTitle: string;
    privacyIntro: string;
  };
  errors: {
    notFoundTitle: string;
    notFoundMessage: string;
    accessDeniedTitle: string;
    accessDeniedMessage: string;
    unavailableTitle: string;
    unavailableMessage: string;
    serverErrorTitle: string;
    serverErrorMessage: string;
    returnHome: string;
  };
  login: {
    university: string;
    title: string;
    intro: string;
    continue: string;
    note: string;
    localTitle: string;
    localDescription: string;
    localNote: string;
    authError: string;
    startError: string;
    access: string;
    peppi: string;
  };
  navigation: {
    navigation: string;
    university: string;
    workspace: string;
    desk: string;
    announcements: string;
    activity: string;
    courses: string;
    availableCoursesTitle: string;
    activeCourses: string;
    availableCourses: string;
    support: string;
    colorMode: string;
    toggleColorMode: string;
    signOut: string;
    student: string;
    collapse: string;
  };
  activity: {
    trigger: string;
    triggerUnread: string;
    recent: string;
    recentDescription: string;
    clear: string;
    close: string;
    historyLink: string;
    emptyTitle: string;
    emptyDescription: string;
    historyTitle: string;
    historyDescription: string;
    eventList: string;
    kind: Record<"attempt" | "grading" | "artifact" | "instance", string>;
  };
  course: {
    status: Record<"not-started" | "in-progress" | "completed", string>;
    workspace: string;
    details: string;
    record: string;
    progress: string;
    complete: string;
    points: string;
    weeks: string;
    links: string;
    courseLinks: string;
    peppi: string;
    overview: string;
    next: string;
    continue: string;
    start: string;
    minutes: string;
    map: string;
    mapDescription: string;
    week: string;
    activity: string;
    activities: string;
    about: string;
    accessGate: Record<
      "anonymous" | "empty" | "pending" | "accepted",
      { eyebrow: string; title: string; description: string; action: string }
    >;
  };
  reading: {
    onThisPage: string;
    material: string;
    navigation: string;
  };
  dashboard: {
    status: Record<"not-started" | "in-progress" | "completed", string>;
    agendaStatus: Record<"todo" | "in-progress" | "completed", string>;
    studyOverview: string;
    week: string;
    progress: string;
    semesterOverview: string;
    activitiesDone: string;
    remaining: string;
    recentUpdates: string;
    activeCoursesSource: string;
    courseUpdates: string;
    welcome: string;
    welcomeText: string;
    continueLearning: string;
    thisWeek: string;
    weeklyPlan: string;
    filterActivities: string;
    todo: string;
    completed: string;
    all: string;
    weeklyActivities: string;
    resume: string;
    viewCourse: string;
    checkpoints: string;
    aboutMinutes: string;
    courseProgress: string;
    activeEnrollments: string;
    enrolledCourses: string;
    courseDates: string;
    browseCourses: string;
    browseCoursesText: string;
  };
}

const en: AppMessages = {
  appearance: {
    label: "Appearance",
    theme: "Theme",
    themeNames: {
      academic: "Academic",
      terminal: "Terminal",
    },
    colorMode: "Color mode",
    system: "Use system setting",
    light: "Light",
    dark: "Dark",
  },
  languageSwitcher: {
    options: {
      en: { name: "English", switchLabel: "Switch language to English" },
      fi: { name: "Suomi", switchLabel: "Switch language to Finnish" },
    },
  },
  metadata: {
    homeTitle: "Ainigma | Interactive cyber security coursework",
    homeDescription:
      "A focused academic workspace for interactive cyber security coursework at the University of Oulu.",
    loginTitle: "Sign in | Ainigma",
    loginDescription: "Sign in to your Ainigma learning space.",
    deskTitle: "My learning | Ainigma",
    deskDescription: "Your courses, weekly study plan, and learning progress in Ainigma.",
    activityTitle: "Activity history | Ainigma",
    activityDescription: "Announcements, generated artifacts, and lab instance events.",
    aboutTitle: "About | Ainigma",
    aboutDescription: "Information about the Ainigma learning environment.",
    privacyTitle: "Privacy policy | Ainigma",
    privacyDescription:
      "How Ainigma processes personal data in the University of Oulu learning environment.",
  },
  publicHome: {
    signIn: "Sign in",
    unit: "By Oulu University Secure Programming Group (OUSPG)",
    title: "Cybersecurity courses at the University of Oulu",
    intro:
      "This site contains course material and interactive exercises for participating cybersecurity courses. Personal coursework and progress are available to enrolled students after sign-in.",
    alphaLabel: "Alpha",
    alphaText:
      "Ainigma is currently in alpha. Course content and features are still (rapidly) evolving.",
    coursesSectionLabel: "Courses",
    courseSpaces: "Course spaces",
    published: "course spaces are currently published on Ainigma.",
    accessSectionLabel: "Start here",
    access: "Access",
    accessText:
      "Use the GitHub account linked to your university email. To access courses, authenticate through the University of Oulu GitHub Enterprise SSO. If an expected course is missing, contact the course staff.",
    viewCourse: "View course",
    peppi: "Peppi study guide",
    peppiCourse: "Peppi",
    opensInNewTab: "(opens in a new tab)",
    courseListLabel: "Ainigma course spaces",
  },
  footer: {
    identity: "Ainigma · Oulu University Secure Programming Group",
    navigation: "Service information",
    about: "About",
    privacy: "Privacy policy",
    sourceCode: "Source Code",
  },
  publicInfo: {
    aboutTitle: "About Ainigma",
    aboutIntro:
      "Ainigma is an academic learning environment for course materials, interactive exercises, and learner-specific lab work.",
    aboutSectionTitle: "About this service",
    aboutPlaceholder:
      "This is a placeholder. Ownership, responsible unit, accessibility information, support contacts, and service details will be added before launch.",
    privacyTitle: "Privacy policy",
    privacyIntro:
      "This notice explains how personal data is processed in the Ainigma learning environment and what rights you have.",
  },
  errors: {
    notFoundTitle: "Page not found",
    notFoundMessage: "The page may have moved, or the address may be incorrect.",
    accessDeniedTitle: "Course access required",
    accessDeniedMessage: "Your account does not currently have access to this course.",
    unavailableTitle: "Temporarily unavailable",
    unavailableMessage: "We could not verify your access right now. Please try again shortly.",
    serverErrorTitle: "Something went wrong",
    serverErrorMessage: "An unexpected error occurred. Please try again later.",
    returnHome: "Return to the front page",
  },
  login: {
    university: "University of Oulu",
    title: "Sign in to your learning space",
    intro:
      "Use the GitHub identity connected to your university email. You must pass Univerity's SSO in order to access courses.",
    continue: "Continue with GitHub",
    note: "Ainigma uses your verified GitHub identity to check course access and bind lab work to the correct learner.",
    localTitle: "Local development users",
    localDescription:
      "Use a seeded Supabase user to test an application state without GitHub OAuth.",
    localNote: "Visible only when local authentication mode is enabled.",
    authError: "GitHub sign-in could not be completed. Please try again.",
    startError: "GitHub sign-in could not be started. Please try again.",
    access: "Need access? Contact your course staff or review the",
    peppi: "Peppi study guide",
  },
  navigation: {
    navigation: "Ainigma navigation",
    university: "University of Oulu",
    workspace: "Workspace",
    desk: "My learning",
    announcements: "Course updates",
    activity: "Activity",
    courses: "My courses",
    availableCoursesTitle: "Available courses",
    activeCourses: "active courses",
    availableCourses: "available courses",
    support: "Learning support",
    colorMode: "Color mode",
    toggleColorMode: "Toggle light and dark mode",
    signOut: "Sign out",
    student: "Student",
    collapse: "Collapse course navigation",
  },
  activity: {
    trigger: "Activity",
    triggerUnread: "Activity, {count} unread items",
    recent: "Recent activity",
    recentDescription:
      "Task attempts, grading, artifacts, and lab events that may need your attention.",
    clear: "Clear recent",
    close: "Close activity",
    historyLink: "View activity history",
    emptyTitle: "Recent activity cleared",
    emptyDescription: "These events remain available in your activity history.",
    historyTitle: "Activity history",
    historyDescription:
      "A lasting record of task attempts, grading, generated artifacts, and lab instance events across your courses.",
    eventList: "Learner activity",
    kind: {
      attempt: "Task attempt",
      grading: "Grading",
      artifact: "Artifact ready",
      instance: "Lab instance",
    },
  },
  course: {
    status: { "not-started": "Not started", "in-progress": "In progress", completed: "Completed" },
    workspace: "Course workspace",
    details: "Course details",
    record: "Your record",
    progress: "Course progress",
    complete: "complete",
    points: "Points earned",
    weeks: "Weeks complete",
    links: "Course links",
    courseLinks: "Course links",
    peppi: "Peppi study guide",
    overview: "Course overview",
    next: "Next activity",
    continue: "Continue",
    start: "Start course",
    minutes: "minutes",
    map: "Course map",
    mapDescription: "Follow the suggested order, or return to any available week.",
    week: "Week",
    activity: "activity",
    activities: "activities",
    about: "About this course",
    accessGate: {
      anonymous: {
        eyebrow: "Interactive activity",
        title: "Sign in required",
        description: "Sign in with your university account to use this interactive activity.",
        action: "Sign in to continue",
      },
      empty: {
        eyebrow: "Interactive activity",
        title: "Course access required",
        description: "Request access to this course before starting its interactive activities.",
        action: "Request course access",
      },
      pending: {
        eyebrow: "Interactive activity",
        title: "Access request pending",
        description:
          "Course staff must accept your request before this interactive activity opens.",
        action: "Request pending",
      },
      accepted: {
        eyebrow: "Interactive activity",
        title: "Interactive activity",
        description: "",
        action: "",
      },
    },
  },
  reading: {
    onThisPage: "On this page",
    material: "Learning material",
    navigation: "Previous and next learning material",
  },
  dashboard: {
    status: { "not-started": "Not started", "in-progress": "In progress", completed: "Completed" },
    agendaStatus: { todo: "To do", "in-progress": "In progress", completed: "Completed" },
    studyOverview: "Study overview",
    week: "Week",
    progress: "progress",
    semesterOverview: "Semester overview",
    activitiesDone: "Activities done",
    remaining: "Remaining",
    recentUpdates: "Recent updates",
    activeCoursesSource: "From your active courses",
    courseUpdates: "Course updates",
    welcome: "Welcome back,",
    welcomeText: "Continue where you left off or review what needs attention this week.",
    continueLearning: "Continue learning",
    thisWeek: "This week",
    weeklyPlan: "A plan across all enrolled courses",
    filterActivities: "Filter weekly activities",
    todo: "To do",
    completed: "Completed",
    all: "All",
    weeklyActivities: "Weekly learning activities",
    resume: "Resume activity",
    viewCourse: "View course",
    checkpoints: "checkpoints",
    aboutMinutes: "About",
    courseProgress: "Course progress",
    activeEnrollments: "active enrollments",
    enrolledCourses: "Enrolled courses",
    courseDates: "Course dates",
    browseCourses: "Browse courses",
    browseCoursesText:
      "Published course materials are available to everyone. Request access when you are ready to use the interactive activities.",
  },
};

const fi: AppMessages = {
  appearance: {
    label: "Ulkoasu",
    theme: "Teema",
    themeNames: {
      academic: "Akateeminen",
      terminal: "Terminaali",
    },
    colorMode: "Väritila",
    system: "Käytä järjestelmän asetusta",
    light: "Vaalea",
    dark: "Tumma",
  },
  languageSwitcher: {
    options: {
      en: { name: "English", switchLabel: "Vaihda kieleksi englanti" },
      fi: { name: "Suomi", switchLabel: "Vaihda kieleksi suomi" },
    },
  },
  metadata: {
    homeTitle: "Ainigma | Interaktiiviset kyberturvallisuuskurssit",
    homeDescription:
      "Oulun yliopiston akateeminen työtila interaktiivisille kyberturvallisuuskursseille.",
    loginTitle: "Kirjautuminen | Ainigma",
    loginDescription: "Kirjaudu Ainigma-oppimistilaan.",
    deskTitle: "Oma oppiminen | Ainigma",
    deskDescription: "Kurssisi, viikoittainen opiskelusuunnitelma ja edistymisesi Ainigmaassa.",
    activityTitle: "Tapahtumahistoria | Ainigma",
    activityDescription: "Ilmoitukset, luodut artefaktit ja laboratorioympäristöjen tapahtumat.",
    aboutTitle: "Tietoa palvelusta | Ainigma",
    aboutDescription: "Tietoa Ainigma-oppimisympäristöstä.",
    privacyTitle: "Tietosuojaseloste | Ainigma",
    privacyDescription:
      "Miten Ainigma käsittelee henkilötietoja Oulun yliopiston oppimisympäristössä.",
  },
  publicHome: {
    signIn: "Kirjaudu",
    unit: "Oulun yliopiston Secure Programming Group (OUSPG)",
    title: "Kyberturvallisuuden kurssit ja interaktiiviset laboratoriot Oulun yliopistossa",
    intro:
      "Tämä sivusto sisältää osallistuvien kyberturvallisuuskurssien kurssimateriaaleja ja interaktiivisia harjoituksia. Henkilökohtaiset tehtävät ja edistyminen ovat ilmoittautuneiden opiskelijoiden käytettävissä kirjautumisen jälkeen.",
    alphaLabel: "Alphaversio",
    alphaText:
      "Ainigma on tällä hetkellä alphavaiheessa. Kurssisisältö ja ominaisuudet kehittyvät (merkittävästi) vielä.",
    coursesSectionLabel: "Kurssit",
    courseSpaces: "Kurssitilat",
    published: "kurssitilaa on julkaistu Ainigmaan.",
    accessSectionLabel: "Aloita tästä",
    access: "Käyttöoikeus",
    accessText:
      "Opiskelijat kirjautuvat kurssilleen ilmoittautumiseen liitetyllä GitHub-tunnuksella. Jos odottamasi kurssi ei ole käytettävissä, ota yhteyttä kurssin henkilökuntaan.",
    viewCourse: "Näytä kurssi",
    peppi: "Peppi-opas",
    peppiCourse: "Peppi",
    opensInNewTab: "(avautuu uuteen välilehteen)",
    courseListLabel: "Ainigma-kurssitilat",
  },
  footer: {
    identity: "Ainigma · Oulu University Secure Programming Group",
    navigation: "Palvelun tiedot",
    about: "Tietoa palvelusta",
    privacy: "Tietosuojaseloste",
    sourceCode: "Lähdekoodi",
  },
  publicInfo: {
    aboutTitle: "Tietoa Ainigmasta",
    aboutIntro:
      "Ainigma on akateeminen oppimisympäristö kurssimateriaaleille, interaktiivisille harjoituksille ja opiskelijakohtaisille laboratoriotehtäville.",
    aboutSectionTitle: "Tietoa palvelusta",
    aboutPlaceholder:
      "Tämä on paikkamerkki. Palvelun omistaja, vastuuyksikkö, saavutettavuustiedot, tukiyhteystiedot ja palvelun tarkemmat tiedot lisätään ennen käyttöönottoa.",
    privacyTitle: "Tietosuojaseloste",
    privacyIntro:
      "Tässä selosteessa kerrotaan, miten henkilötietoja käsitellään Ainigma-oppimisympäristössä ja mitä oikeuksia sinulla on.",
  },
  errors: {
    notFoundTitle: "Sivua ei löytynyt",
    notFoundMessage: "Sivu on ehkä siirretty tai osoite on virheellinen.",
    accessDeniedTitle: "Kurssin käyttöoikeus vaaditaan",
    accessDeniedMessage: "Tililläsi ei tällä hetkellä ole käyttöoikeutta tälle kurssille.",
    unavailableTitle: "Palvelu on tilapäisesti poissa käytöstä",
    unavailableMessage: "Käyttöoikeuttasi ei voitu tarkistaa. Yritä hetken kuluttua uudelleen.",
    serverErrorTitle: "Jokin meni vikaan",
    serverErrorMessage: "Tapahtui odottamaton virhe. Yritä myöhemmin uudelleen.",
    returnHome: "Palaa etusivulle",
  },
  login: {
    university: "Oulun yliopisto",
    title: "Kirjaudu oppimistilaan",
    intro: "Käytä kurssi-ilmoittautumiseesi liitettyä GitHub-tunnusta.",
    continue: "Jatka GitHubilla",
    note: "Ainigma käyttää vahvistettua GitHub-identiteettiä kurssioikeuksien tarkistamiseen ja tehtävien yhdistämiseen oikeaan opiskelijaan.",
    localTitle: "Paikallisen kehityksen käyttäjät",
    localDescription: "Testaa Supabaseen kylvettyä käyttäjää ilman GitHub OAuth -kirjautumista.",
    localNote: "Näkyy vain, kun paikallinen kirjautumistila on käytössä.",
    authError: "GitHub-kirjautumista ei voitu viimeistellä. Yritä uudelleen.",
    startError: "GitHub-kirjautumista ei voitu aloittaa. Yritä uudelleen.",
    access: "Tarvitsetko käyttöoikeuden? Ota yhteyttä kurssin henkilökuntaan tai tutustu",
    peppi: "Peppi-oppaaseen",
  },
  navigation: {
    navigation: "Ainigma-navigaatio",
    university: "Oulun yliopisto",
    workspace: "Työtila",
    desk: "Oma oppiminen",
    announcements: "Kurssipäivitykset",
    activity: "Tapahtumat",
    courses: "Kurssini",
    availableCoursesTitle: "Saatavilla olevat kurssit",
    activeCourses: "aktiivista kurssia",
    availableCourses: "saatavilla olevaa kurssia",
    support: "Oppimisen tuki",
    colorMode: "Väritila",
    toggleColorMode: "Vaihda vaalean ja tumman tilan välillä",
    signOut: "Kirjaudu ulos",
    student: "Opiskelija",
    collapse: "Tiivistä kurssinavigaatio",
  },
  activity: {
    trigger: "Tapahtumat",
    triggerUnread: "Tapahtumat, {count} lukematonta kohdetta",
    recent: "Viimeisimmät tapahtumat",
    recentDescription:
      "Huomiotasi mahdollisesti vaativat tehtäväyritykset, arvioinnit, artefaktit ja laboratorioympäristöjen tapahtumat.",
    clear: "Tyhjennä viimeisimmät",
    close: "Sulje tapahtumat",
    historyLink: "Näytä tapahtumahistoria",
    emptyTitle: "Viimeisimmät tapahtumat tyhjennetty",
    emptyDescription: "Tapahtumat säilyvät tapahtumahistoriassasi.",
    historyTitle: "Tapahtumahistoria",
    historyDescription:
      "Pysyvä luettelo tehtäväyrityksistä, arvioinneista, luoduista artefakteista ja laboratorioympäristöjen tapahtumista.",
    eventList: "Opiskelijan tapahtumat",
    kind: {
      attempt: "Tehtäväyritys",
      grading: "Arviointi",
      artifact: "Artefakti valmis",
      instance: "Laboratorioympäristö",
    },
  },
  course: {
    status: { "not-started": "Ei aloitettu", "in-progress": "Kesken", completed: "Valmis" },
    workspace: "Kurssityötila",
    details: "Kurssin tiedot",
    record: "Suoritustietosi",
    progress: "Kurssin edistyminen",
    complete: "valmis",
    points: "Pistettä ansaittu",
    weeks: "Viikkoa valmis",
    links: "Kurssin linkit",
    courseLinks: "Kurssin linkit",
    peppi: "Peppi-opas",
    overview: "Kurssin yleiskatsaus",
    next: "Seuraava tehtävä",
    continue: "Jatka",
    start: "Aloita kurssi",
    minutes: "minuuttia",
    map: "Kurssikartta",
    mapDescription:
      "Seuraa ehdotettua järjestystä tai palaa mihin tahansa käytettävissä olevaan viikkoon.",
    week: "Viikko",
    activity: "tehtävä",
    activities: "tehtävää",
    about: "Tietoa kurssista",
    accessGate: {
      anonymous: {
        eyebrow: "Interaktiivinen tehtävä",
        title: "Kirjautuminen vaaditaan",
        description: "Kirjaudu yliopistotunnuksellasi käyttääksesi tätä interaktiivista tehtävää.",
        action: "Kirjaudu jatkaaksesi",
      },
      empty: {
        eyebrow: "Interaktiivinen tehtävä",
        title: "Kurssin käyttöoikeus vaaditaan",
        description: "Pyydä kurssin käyttöoikeutta ennen interaktiivisten tehtävien aloittamista.",
        action: "Pyydä kurssin käyttöoikeutta",
      },
      pending: {
        eyebrow: "Interaktiivinen tehtävä",
        title: "Käyttöoikeuspyyntö odottaa",
        description: "Kurssin henkilökunnan on hyväksyttävä pyyntösi ennen tehtävän avaamista.",
        action: "Pyyntö odottaa",
      },
      accepted: {
        eyebrow: "Interaktiivinen tehtävä",
        title: "Interaktiivinen tehtävä",
        description: "",
        action: "",
      },
    },
  },
  reading: {
    onThisPage: "Tällä sivulla",
    material: "Oppimateriaali",
    navigation: "Edellinen ja seuraava oppimateriaali",
  },
  dashboard: {
    status: { "not-started": "Ei aloitettu", "in-progress": "Kesken", completed: "Valmis" },
    agendaStatus: { todo: "Tehtävä", "in-progress": "Kesken", completed: "Valmis" },
    studyOverview: "Opintojen yleiskatsaus",
    week: "Viikko",
    progress: "edistyminen",
    semesterOverview: "Lukukauden yleiskatsaus",
    activitiesDone: "Tehtävää tehty",
    remaining: "Jäljellä",
    recentUpdates: "Viimeisimmät päivitykset",
    activeCoursesSource: "Aktiivisilta kursseilta",
    courseUpdates: "Kurssipäivitykset",
    welcome: "Tervetuloa takaisin,",
    welcomeText: "Jatka siitä, mihin jäit, tai tarkista tämän viikon tehtävät.",
    continueLearning: "Jatka opiskelua",
    thisWeek: "Tällä viikolla",
    weeklyPlan: "Suunnitelma kaikille ilmoittautumillesi kursseille",
    filterActivities: "Suodata viikon tehtäviä",
    todo: "Tehtävät",
    completed: "Valmiit",
    all: "Kaikki",
    weeklyActivities: "Viikon oppimistehtävät",
    resume: "Jatka tehtävää",
    viewCourse: "Näytä kurssi",
    checkpoints: "tarkistuspistettä",
    aboutMinutes: "Noin",
    courseProgress: "Kurssien edistyminen",
    activeEnrollments: "aktiivista ilmoittautumista",
    enrolledCourses: "Ilmoittautuneet kurssit",
    courseDates: "Kurssin ajankohta",
    browseCourses: "Selaa kursseja",
    browseCoursesText:
      "Julkaistut kurssimateriaalit ovat kaikkien saatavilla. Pyydä käyttöoikeutta, kun haluat käyttää interaktiivisia tehtäviä.",
  },
};

export const appMessages: Record<Locale, AppMessages> = { en, fi };

export function getMessages(locale: Locale): AppMessages {
  return appMessages[locale];
}

export function getLocale(value: string | undefined): Locale {
  return value?.toLowerCase().startsWith("fi") ? "fi" : "en";
}

export function getAstryxLocale(locale: Locale): "en" | "fi-FI" {
  return locale === "fi" ? "fi-FI" : "en";
}

export function getOtherLocale(locale: Locale): Locale {
  return locale === "fi" ? "en" : "fi";
}
