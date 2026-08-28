import type { ExternalUrl } from "../external-links";
import type { AppPath } from "../routes";
import type {
  CourseDefinitionKey,
  CourseDefinitionReleaseId,
  CourseDefinitionSlug,
  CourseOfferingKey,
} from "./identifiers";

export type CourseStatus = "not-started" | "in-progress" | "completed";
export type AgendaStatus = "todo" | "in-progress" | "completed";
export type CourseTone = "blue" | "orange" | "teal";
export type ActivityKind = "attempt" | "grading" | "artifact" | "instance";

interface CourseOverviewFields {
  code: string;
  title: string;
  summary: string;
  tone: CourseTone;
}

export interface PublicCourseInfo extends CourseOverviewFields {
  courseDefinitionSlug: CourseDefinitionSlug;
  courseDefinitionKey: CourseDefinitionKey;
  catalogUrl?: ExternalUrl;
}

interface CourseSchedule {
  startDate: string;
  endDate: string;
}

interface TaskDefinition {
  slug: string;
  title: string;
  summary: string;
  estimatedMinutes: number;
  points: number;
}

export interface TaskInfo extends TaskDefinition {
  href: AppPath;
}

interface WeekDefinition {
  slug: string;
  number: number;
  title: string;
  summary: string;
  tasks: TaskDefinition[];
}

interface PageDefinition {
  page: "announcements" | "materials";
  title: string;
  label: string;
}

export interface CourseDefinition extends CourseOverviewFields {
  courseDefinitionSlug: string;
  courseDefinitionKey: string;
  navMark: string;
  catalogUrl: ExternalUrl | null;
  catalogOrder: number;
  draft: boolean;
  weeks: WeekDefinition[];
  pages: PageDefinition[];
  taskCount: number;
}

export interface WeekInfo extends Omit<WeekDefinition, "tasks"> {
  href: AppPath;
  status: CourseStatus;
  tasks: TaskInfo[];
}

export interface CoursePageInfo extends PageDefinition {
  href: AppPath;
}

export interface NextActivity {
  eyebrow: string;
  title: string;
  description: string;
  href: AppPath;
  estimatedMinutes: number;
  completedSteps: number;
  totalSteps: number;
  savedLabel: string;
}

export interface CourseInfo extends CourseOverviewFields, CourseSchedule {
  offeringKey: CourseOfferingKey;
  courseDefinitionSlug: CourseDefinitionSlug;
  courseDefinitionKey: CourseDefinitionKey;
  courseDefinitionReleaseId: CourseDefinitionReleaseId;
  navMark: string;
  href: AppPath;
  catalogUrl?: ExternalUrl;
  tone: CourseTone;
  progress: number;
  status: CourseStatus;
  earnedPoints: number;
  availablePoints: number;
  weeks: WeekInfo[];
  pages: CoursePageInfo[];
  taskCount: number;
  nextActivity: NextActivity;
}

export interface AgendaItem {
  id: string;
  offeringKey: CourseOfferingKey;
  type: "lab" | "reading" | "setup";
  title: string;
  supporting: string;
  dueLabel: string;
  href: AppPath;
  status: AgendaStatus;
}

export interface Announcement {
  id: string;
  offeringKey: CourseOfferingKey;
  title: string;
  timeLabel: string;
  href: AppPath;
}

export interface LearnerActivity {
  id: string;
  offeringKey: CourseOfferingKey;
  kind: ActivityKind;
  title: string;
  description: string;
  timeLabel: string;
  occurredAt: string;
  href: AppPath;
  isUnread: boolean;
  isRecent: boolean;
}

export interface StudentProfile {
  displayName: string;
  firstName: string;
}

export interface AcademicTerm {
  label: string;
  dateLabel: string;
  currentWeek: number;
  weekCount: number;
  completedActivities: number;
  totalActivities: number;
}

export interface LearningWorkspace {
  profile: StudentProfile;
  term: AcademicTerm;
  courses: CourseInfo[];
  agenda: AgendaItem[];
  announcements: Announcement[];
  activity: LearnerActivity[];
}
