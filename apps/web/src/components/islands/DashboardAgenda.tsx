import { useMemo, useState } from "react";
import { List, ListItem } from "@astryxdesign/core/List";
import { SegmentedControl, SegmentedControlItem } from "@astryxdesign/core/SegmentedControl";
import { HStack, StackItem, VStack } from "@astryxdesign/core/Stack";
import { Heading, Text } from "@astryxdesign/core/Text";
import { BookOpen, Check, ChevronRight, FlaskConical, Wrench } from "lucide-react";
import { getMessages, type Locale } from "../../lib/i18n";
import type { AgendaItem, CourseInfo } from "../../lib/learning/types";
import { localizedPath } from "../../lib/routes";

interface Props {
  agenda: AgendaItem[];
  courses: CourseInfo[];
  locale: Locale;
}

type AgendaFilter = "upcoming" | "completed" | "all";

const agendaIcons = {
  lab: FlaskConical,
  reading: BookOpen,
  setup: Wrench,
} as const;

function filterAgenda(items: AgendaItem[], filter: AgendaFilter): AgendaItem[] {
  if (filter === "completed") return items.filter((item) => item.status === "completed");
  if (filter === "upcoming") return items.filter((item) => item.status !== "completed");
  return items;
}

export default function DashboardAgenda({ agenda, courses, locale }: Props) {
  const [filter, setFilter] = useState<AgendaFilter>("upcoming");
  const courseByOfferingKey = useMemo(
    () => new Map(courses.map((course) => [course.offeringKey, course])),
    [courses],
  );
  const copy = getMessages(locale).dashboard;
  const visibleAgenda = filterAgenda(agenda, filter);

  return (
    <VStack as="section" id="week-plan" aria-labelledby="week-plan-heading" gap={3}>
      <HStack className="section-heading-row" gap={4} vAlign="center" wrap="wrap">
        <StackItem size="fill">
          <VStack gap={1}>
            <Heading id="week-plan-heading" level={2}>
              {copy.thisWeek}
            </Heading>
            <Text type="supporting" color="secondary">
              {copy.weeklyPlan}
            </Text>
          </VStack>
        </StackItem>
        <SegmentedControl
          label={copy.filterActivities}
          onChange={(value) => setFilter(value as AgendaFilter)}
          size="sm"
          value={filter}
        >
          <SegmentedControlItem label={copy.todo} value="upcoming" />
          <SegmentedControlItem label={copy.completed} value="completed" />
          <SegmentedControlItem label={copy.all} value="all" />
        </SegmentedControl>
      </HStack>

      <List
        className="agenda-list"
        density="balanced"
        hasDividers
        header={<Text className="visually-hidden">{copy.weeklyActivities}</Text>}
      >
        {visibleAgenda.map((item) => {
          const course = courseByOfferingKey.get(item.offeringKey);
          const AgendaIcon = agendaIcons[item.type];
          const isCompleted = item.status === "completed";
          return (
            <ListItem
              description={
                <Text type="supporting" color="secondary">
                  {course?.title} · {item.supporting}
                </Text>
              }
              endContent={
                <HStack className="agenda-end" gap={3} vAlign="center">
                  <VStack gap={0.5} hAlign="end">
                    <Text type="supporting" weight="medium">
                      {item.dueLabel}
                    </Text>
                    <Text type="supporting" color="secondary">
                      {copy.agendaStatus[item.status]}
                    </Text>
                  </VStack>
                  <ChevronRight size={17} aria-hidden="true" />
                </HStack>
              }
              href={localizedPath(locale, item.href)}
              key={item.id}
              label={
                <Text
                  type="body"
                  weight="medium"
                  hasStrikethrough={isCompleted}
                  color={isCompleted ? "secondary" : "primary"}
                >
                  {item.title}
                </Text>
              }
              startContent={
                <span className={`agenda-icon type-${item.type}`} aria-hidden="true">
                  {isCompleted ? <Check size={17} /> : <AgendaIcon size={17} />}
                </span>
              }
            />
          );
        })}
      </List>
    </VStack>
  );
}
