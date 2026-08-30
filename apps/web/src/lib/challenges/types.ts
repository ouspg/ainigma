export interface FlagChallengeData {
  type: "flag";
  title: string;
  description: string;
  placeholder: string;
  expectedFormat: string;
}

export interface MultipartStepData {
  id: string;
  title: string;
  description: string;
  requiresAnswer: boolean;
  actionLabel?: string;
  completedLabel?: string;
  inputLabel?: string;
  placeholder?: string;
}

export interface MultipartChallengeData {
  type: "multipart";
  title: string;
  description: string;
  steps: MultipartStepData[];
}
