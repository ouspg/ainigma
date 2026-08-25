import { useEffect, useState, type FormEvent } from "react";
import { Button } from "@astryxdesign/core/Button";
import { Card } from "@astryxdesign/core/Card";
import { Divider } from "@astryxdesign/core/Divider";
import { ProgressBar } from "@astryxdesign/core/ProgressBar";
import { TextInput, type TextInputStatus } from "@astryxdesign/core/TextInput";
import { HStack, StackItem, VStack } from "@astryxdesign/core/Stack";
import { StatusDot } from "@astryxdesign/core/StatusDot";
import { Heading, Text } from "@astryxdesign/core/Text";
import type { MultipartChallengeData } from "../../lib/challenges/types";
import { mockChallengeEvaluator } from "../../lib/challenges/mock-evaluator";
import { readActivityProgress, writeActivityProgress } from "../../lib/progress/activity-progress";

interface Props {
  taskId: string;
  challenge: MultipartChallengeData;
}

export default function MultipartLabIsland({ taskId, challenge }: Props) {
  const [completed, setCompleted] = useState<boolean[]>(() => challenge.steps.map(() => false));
  const [values, setValues] = useState<Record<string, string>>({});
  const [feedback, setFeedback] = useState<Record<string, { isCorrect: boolean; message: string }>>(
    {},
  );
  const [isProgressReady, setIsProgressReady] = useState(false);

  useEffect(() => {
    const stored = readActivityProgress(taskId);
    const completedIds = new Set(stored.completedSteps);
    setCompleted(
      challenge.steps.map((step) => stored.status === "completed" || completedIds.has(step.id)),
    );
    setIsProgressReady(true);
  }, [challenge.steps, taskId]);

  const completedSteps = completed.filter(Boolean).length;
  const isComplete = completedSteps === challenge.steps.length;

  useEffect(() => {
    if (!isProgressReady) return;
    writeActivityProgress(taskId, {
      status: isComplete ? "completed" : completedSteps > 0 ? "in-progress" : "not-started",
      completedSteps: challenge.steps.filter((_, index) => completed[index]).map((step) => step.id),
    });
  }, [challenge.steps, completed, completedSteps, isComplete, isProgressReady, taskId]);

  const checkStep = async (index: number, event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const step = challenge.steps[index];
    if (!step?.requiresAnswer) return;
    const evaluation = await mockChallengeEvaluator.evaluateStep(
      taskId,
      step.id,
      values[step.id] ?? "",
    );
    setFeedback((current) => ({ ...current, [step.id]: evaluation }));
    if (evaluation.isCorrect) {
      setCompleted((current) =>
        current.map((value, stepIndex) => (stepIndex === index ? true : value)),
      );
    }
  };

  const markStepComplete = (index: number) => {
    setCompleted((current) =>
      current.map((value, stepIndex) => (stepIndex === index ? true : value)),
    );
  };

  return (
    <Card className="task-island" padding={5}>
      <VStack gap={4}>
        <HStack gap={3} vAlign="start">
          <StackItem size="fill">
            <VStack gap={1}>
              <Text type="supporting" color="secondary" weight="medium">
                Guided analysis
              </Text>
              <Heading level={3}>{challenge.title}</Heading>
              <Text type="body" color="secondary">
                {challenge.description}
              </Text>
            </VStack>
          </StackItem>
          <Text type="supporting" color="secondary" hasTabularNumbers>
            {completedSteps} of {challenge.steps.length}
          </Text>
        </HStack>

        <ProgressBar
          isLabelHidden
          label={`${challenge.title} progress`}
          max={challenge.steps.length}
          value={completedSteps}
          variant={isComplete ? "success" : "accent"}
        />

        {challenge.steps.map((step, index) => {
          const stepIsComplete = completed[index] ?? false;
          const previousIsComplete = index === 0 || completed[index - 1];
          const stepFeedback = feedback[step.id];
          const inputStatus: TextInputStatus | undefined = stepIsComplete
            ? { type: "success", message: stepFeedback?.message ?? "Checkpoint complete." }
            : stepFeedback
              ? { type: "error", message: stepFeedback.message }
              : undefined;

          return (
            <VStack key={step.id} gap={3}>
              {index > 0 && <Divider />}
              <HStack gap={3} vAlign="start">
                <StatusDot
                  label={stepIsComplete ? "Completed" : "Not completed"}
                  variant={stepIsComplete ? "success" : "neutral"}
                />
                <StackItem size="fill">
                  <VStack gap={3}>
                    <VStack gap={1}>
                      <Text type="body" weight="medium">
                        {index + 1}. {step.title}
                      </Text>
                      <Text type="supporting" color="secondary">
                        {step.description}
                      </Text>
                    </VStack>
                    {step.requiresAnswer ? (
                      <form onSubmit={(event) => void checkStep(index, event)}>
                        <VStack gap={3}>
                          <TextInput
                            isDisabled={!previousIsComplete || stepIsComplete}
                            {...(!previousIsComplete
                              ? { disabledMessage: "Complete the previous checkpoint first" }
                              : {})}
                            isRequired
                            label={step.inputLabel ?? step.title}
                            onChange={(nextValue) => {
                              setValues((current) => ({ ...current, [step.id]: nextValue }));
                              setFeedback((current) => {
                                const next = { ...current };
                                delete next[step.id];
                                return next;
                              });
                            }}
                            {...(step.placeholder ? { placeholder: step.placeholder } : {})}
                            {...(inputStatus ? { status: inputStatus } : {})}
                            value={values[step.id] ?? ""}
                            width="100%"
                          />
                          <Button
                            isDisabled={!previousIsComplete || stepIsComplete}
                            label={stepIsComplete ? "Answer accepted" : "Check answer"}
                            type="submit"
                            variant="primary"
                          />
                        </VStack>
                      </form>
                    ) : (
                      <Button
                        isDisabled={!previousIsComplete || stepIsComplete}
                        label={
                          stepIsComplete
                            ? (step.completedLabel ?? "Completed")
                            : (step.actionLabel ?? "Mark complete")
                        }
                        onClick={() => markStepComplete(index)}
                        size="sm"
                        variant="secondary"
                      />
                    )}
                  </VStack>
                </StackItem>
              </HStack>
            </VStack>
          );
        })}
      </VStack>
    </Card>
  );
}
