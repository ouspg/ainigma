import { List, ListItem } from "@astryxdesign/core/List";
import { Text } from "@astryxdesign/core/Text";
import { ChevronRight } from "lucide-react";
import { getMessages, type Locale } from "../../lib/i18n";
import type { Announcement, CourseInfo } from "../../lib/learning/types";
import { localizedPath } from "../../lib/routes";

interface Props {
  announcements: Announcement[];
  courses: CourseInfo[];
  locale: Locale;
}

export default function CourseUpdatesList({ announcements, courses, locale }: Props) {
  const copy = getMessages(locale).dashboard;
  const courseByOfferingKey = new Map(courses.map((course) => [course.offeringKey, course]));

  return (
    <List
      density="compact"
      hasDividers
      header={<Text className="visually-hidden">{copy.courseUpdates}</Text>}
    >
      {announcements.map((announcement) => {
        const course = courseByOfferingKey.get(announcement.offeringKey);
        return (
          <ListItem
            description={
              <Text type="supporting" color="secondary">
                {course?.code} · {announcement.timeLabel}
              </Text>
            }
            endContent={<ChevronRight size={16} aria-hidden="true" />}
            href={localizedPath(locale, announcement.href)}
            key={announcement.id}
            label={announcement.title}
          />
        );
      })}
    </List>
  );
}
