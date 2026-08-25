export type CourseStatus = "not-started" | "in-progress" | "completed";
export type AgendaStatus = "todo" | "in-progress" | "completed";
export type CourseTone = "blue" | "orange" | "teal";
export type ActivityKind = "attempt" | "grading" | "artifact" | "instance";

export interface PublicCourseInfo {
  slug: string;
  code: string;
  title: string;
  summary: string;
  tone: CourseTone;
  catalogUrl?: string;
}

export interface TaskInfo {
  slug: string;
  title: string;
  summary: string;
  href: string;
  estimatedMinutes: number;
  points: number;
}

export interface WeekInfo {
  slug: string;
  number: number;
  title: string;
  summary: string;
  href: string;
  status: CourseStatus;
  tasks: TaskInfo[];
}

export interface CoursePageInfo {
  page: "announcements" | "materials";
  title: string;
  label: string;
  href: string;
}

export interface NextActivity {
  eyebrow: string;
  title: string;
  description: string;
  href: string;
  estimatedMinutes: number;
  completedSteps: number;
  totalSteps: number;
  savedLabel: string;
}

export interface CourseInfo {
  slug: string;
  courseKey: string;
  code: string;
  navMark: string;
  startDate: string;
  endDate: string;
  title: string;
  summary: string;
  href: string;
  catalogUrl?: string;
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
  courseSlug: string;
  type: "lab" | "reading" | "setup";
  title: string;
  supporting: string;
  dueLabel: string;
  href: string;
  status: AgendaStatus;
}

export interface Announcement {
  id: string;
  courseSlug: string;
  title: string;
  timeLabel: string;
  href: string;
}

export interface LearnerActivity {
  id: string;
  courseSlug: string;
  kind: ActivityKind;
  title: string;
  description: string;
  timeLabel: string;
  occurredAt: string;
  href: string;
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
