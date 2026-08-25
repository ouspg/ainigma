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

export interface FlagChallengeDefinition extends FlagChallengeData {
  answer: string;
  successMessage: string;
  errorMessage: string;
}

export interface MultipartStepDefinition extends Omit<MultipartStepData, "requiresAnswer"> {
  answer?: string;
  successMessage?: string;
  errorMessage?: string;
}

export interface MultipartChallengeDefinition extends Omit<MultipartChallengeData, "steps"> {
  steps: MultipartStepDefinition[];
}

export type ChallengeDefinition = FlagChallengeDefinition | MultipartChallengeDefinition;

export interface EvaluationResult {
  isCorrect: boolean;
  message: string;
}

export interface ChallengeEvaluator {
  evaluateFlag(activityId: string, value: string): Promise<EvaluationResult>;
  evaluateStep(activityId: string, stepId: string, value: string): Promise<EvaluationResult>;
}
