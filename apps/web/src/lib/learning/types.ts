import type { ExternalUrl } from "../external-links";
import type { AppPath } from "../routes";
import type { CourseDefinitionKey } from "./identifiers";

export type CourseStatus = "not-started" | "in-progress" | "completed";
export type AgendaStatus = "todo" | "in-progress" | "completed";
export type CourseTone = "blue" | "orange" | "teal";
export type ActivityKind = "attempt" | "grading" | "artifact" | "instance";

export interface PublicCourseInfo {
  slug: CourseDefinitionKey;
  code: string;
  title: string;
  summary: string;
  tone: CourseTone;
  catalogUrl?: ExternalUrl;
}

export interface TaskInfo {
  slug: string;
  title: string;
  summary: string;
  href: AppPath;
  estimatedMinutes: number;
  points: number;
}

export interface WeekInfo {
  slug: string;
  number: number;
  title: string;
  summary: string;
  href: AppPath;
  status: CourseStatus;
  tasks: TaskInfo[];
}

export interface CoursePageInfo {
  page: "announcements" | "materials";
  title: string;
  label: string;
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

export interface CourseInfo {
  slug: CourseDefinitionKey;
  courseKey: string;
  code: string;
  navMark: string;
  startDate: string;
  endDate: string;
  title: string;
  summary: string;
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
  courseSlug: CourseDefinitionKey;
  type: "lab" | "reading" | "setup";
  title: string;
  supporting: string;
  dueLabel: string;
  href: AppPath;
  status: AgendaStatus;
}

export interface Announcement {
  id: string;
  courseSlug: CourseDefinitionKey;
  title: string;
  timeLabel: string;
  href: AppPath;
}

export interface LearnerActivity {
  id: string;
  courseSlug: CourseDefinitionKey;
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
