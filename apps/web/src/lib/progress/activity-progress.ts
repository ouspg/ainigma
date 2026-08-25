export type ActivityStatus = "not-started" | "in-progress" | "completed";

export interface ActivityProgress {
  status: ActivityStatus;
  completedSteps: string[];
}

const STORAGE_PREFIX = "ainigma.progress.v3";
export const PROGRESS_EVENT = "ainigma:progress";

const EMPTY_PROGRESS: ActivityProgress = { status: "not-started", completedSteps: [] };

function getScope(): string {
  if (typeof window === "undefined") return "server";
  return window.location.pathname.replace(/\/+$/, "") || "/";
}

function storageKey(activityId: string): string {
  return `${STORAGE_PREFIX}:${getScope()}:${activityId}`;
}

function parseProgress(value: string | null): ActivityProgress | undefined {
  if (!value) return undefined;
  try {
    const candidate = JSON.parse(value) as Partial<ActivityProgress>;
    if (
      candidate.status !== "not-started" &&
      candidate.status !== "in-progress" &&
      candidate.status !== "completed"
    ) {
      return undefined;
    }
    return {
      status: candidate.status,
      completedSteps: Array.isArray(candidate.completedSteps)
        ? candidate.completedSteps.filter((step): step is string => typeof step === "string")
        : [],
    };
  } catch {
    return undefined;
  }
}

export function readActivityProgress(activityId: string): ActivityProgress {
  if (typeof window === "undefined") return EMPTY_PROGRESS;
  try {
    return parseProgress(localStorage.getItem(storageKey(activityId))) ?? EMPTY_PROGRESS;
  } catch {
    return EMPTY_PROGRESS;
  }
}

export function writeActivityProgress(activityId: string, progress: ActivityProgress): void {
  if (typeof window === "undefined") return;
  try {
    localStorage.setItem(storageKey(activityId), JSON.stringify(progress));
  } catch {
    // Session state still works when persistent storage is blocked.
  }
  window.dispatchEvent(new CustomEvent(PROGRESS_EVENT, { detail: { activityId, progress } }));
}
