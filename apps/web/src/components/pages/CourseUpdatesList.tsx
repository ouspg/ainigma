import { List, ListItem } from "@astryxdesign/core/List";
import { Text } from "@astryxdesign/core/Text";
import { ChevronRight } from "lucide-react";
import { getMessages, localizedPath, type Locale } from "../../lib/i18n";
import type { Announcement, CourseInfo } from "../../lib/learning/types";

interface Props {
  announcements: Announcement[];
  courses: CourseInfo[];
  locale: Locale;
}

export default function CourseUpdatesList({ announcements, courses, locale }: Props) {
  const copy = getMessages(locale).dashboard;
  const courseBySlug = new Map(courses.map((course) => [course.slug, course]));

  return (
    <List
      density="compact"
      hasDividers
      header={<Text className="visually-hidden">{copy.courseUpdates}</Text>}
    >
      {announcements.map((announcement) => {
        const course = courseBySlug.get(announcement.courseSlug);
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
