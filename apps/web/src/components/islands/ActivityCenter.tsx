import { useEffect, useMemo, useState } from "react";
import { Badge } from "@astryxdesign/core/Badge";
import { Button } from "@astryxdesign/core/Button";
import { Divider } from "@astryxdesign/core/Divider";
import { EmptyState } from "@astryxdesign/core/EmptyState";
import { IconButton } from "@astryxdesign/core/IconButton";
import { List, ListItem } from "@astryxdesign/core/List";
import { Popover } from "@astryxdesign/core/Popover";
import { HStack, StackItem, VStack } from "@astryxdesign/core/Stack";
import { Heading, Text } from "@astryxdesign/core/Text";
import { Bell, CheckCircle2, ChevronRight, ClipboardCheck, Download, Server } from "lucide-react";
import { getMessages, localizedPath, type Locale } from "../../lib/i18n";
import type { CourseInfo, LearnerActivity } from "../../lib/learning/types";

interface Props {
  activities: LearnerActivity[];
  courses: CourseInfo[];
  locale: Locale;
}

const dismissedStorageKey = "ainigma.recent-activity.dismissed.v1";

const activityIcons = {
  attempt: CheckCircle2,
  grading: ClipboardCheck,
  artifact: Download,
  instance: Server,
} as const;

function readDismissedIds(): Set<string> {
  try {
    const stored = window.localStorage.getItem(dismissedStorageKey);
    if (!stored) return new Set();
    const parsed: unknown = JSON.parse(stored);
    return new Set(
      Array.isArray(parsed) ? parsed.filter((id): id is string => typeof id === "string") : [],
    );
  } catch {
    return new Set();
  }
}

export default function ActivityCenter({ activities, courses, locale }: Props) {
  const copy = getMessages(locale).activity;
  const [dismissedIds, setDismissedIds] = useState<Set<string>>(new Set());
  const courseBySlug = useMemo(
    () => new Map(courses.map((course) => [course.slug, course])),
    [courses],
  );

  useEffect(() => {
    setDismissedIds(readDismissedIds());
  }, []);

  const recentActivities = activities.filter(
    (activity) => activity.isRecent && !dismissedIds.has(activity.id),
  );
  const unreadCount = recentActivities.filter((activity) => activity.isUnread).length;
  const triggerLabel =
    unreadCount > 0 ? copy.triggerUnread.replace("{count}", String(unreadCount)) : copy.trigger;

  const clearRecent = () => {
    setDismissedIds((current) => {
      const next = new Set(current);
      recentActivities.forEach((activity) => next.add(activity.id));
      try {
        window.localStorage.setItem(dismissedStorageKey, JSON.stringify([...next]));
      } catch {
        // The panel still clears for this session when storage is unavailable.
      }
      return next;
    });
  };

  return (
    <Popover
      alignment="end"
      className="activity-popover-layer"
      closeButtonLabel={copy.close}
      label={copy.recent}
      placement="below"
      style={{}}
      width="min(24rem, calc(100vw - var(--spacing-4)))"
      content={
        <VStack className="activity-popover" gap={3} hAlign="stretch">
          <HStack gap={3} vAlign="start">
            <VStack gap={0.5}>
              <Heading level={3}>{copy.recent}</Heading>
              <Text type="supporting" color="secondary">
                {copy.recentDescription}
              </Text>
            </VStack>
            <StackItem size="fill" />
            <Button
              isDisabled={recentActivities.length === 0}
              label={copy.clear}
              onClick={clearRecent}
              size="sm"
              variant="ghost"
            />
          </HStack>

          <Divider />

          {recentActivities.length > 0 ? (
            <List
              className="activity-recent-list"
              density="compact"
              hasDividers
              header={<Text className="visually-hidden">{copy.eventList}</Text>}
            >
              {recentActivities.map((activity) => {
                const ActivityIcon = activityIcons[activity.kind];
                const course = courseBySlug.get(activity.courseSlug);
                return (
                  <ListItem
                    description={
                      <VStack gap={0.5}>
                        <Text type="supporting" color="secondary" maxLines={2}>
                          {activity.description}
                        </Text>
                        <Text type="supporting" color="secondary">
                          {course?.code} · {activity.timeLabel}
                        </Text>
                      </VStack>
                    }
                    endContent={<ChevronRight size={16} aria-hidden="true" />}
                    href={localizedPath(locale, activity.href)}
                    key={activity.id}
                    label={
                      <Text type="body" weight="medium" maxLines={2}>
                        {activity.title}
                      </Text>
                    }
                    startContent={
                      <span className={`activity-kind-icon kind-${activity.kind}`}>
                        <ActivityIcon size={16} aria-hidden="true" />
                      </span>
                    }
                  />
                );
              })}
            </List>
          ) : (
            <EmptyState
              actions={
                <Button
                  href={localizedPath(locale, "/activity/")}
                  label={copy.historyLink}
                  size="sm"
                  variant="secondary"
                />
              }
              description={copy.emptyDescription}
              headingLevel={3}
              icon={<Bell size={20} />}
              isCompact
              title={copy.emptyTitle}
            />
          )}

          {recentActivities.length > 0 ? (
            <>
              <Divider />
              <Button
                href={localizedPath(locale, "/activity/")}
                label={copy.historyLink}
                size="sm"
                variant="secondary"
                width="100%"
              />
            </>
          ) : null}
        </VStack>
      }
    >
      <span className="activity-trigger-wrap">
        <IconButton
          icon={<Bell size={17} aria-hidden="true" />}
          label={triggerLabel}
          size="sm"
          tooltip={copy.trigger}
          variant="ghost"
        />
        {unreadCount > 0 ? (
          <span className="activity-count" aria-hidden="true">
            <Badge label={unreadCount} />
          </span>
        ) : null}
      </span>
    </Popover>
  );
}
