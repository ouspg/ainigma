import { useEffect, useState, type SubmitEvent } from "react";
import { Button } from "@astryxdesign/core/Button";
import { Card } from "@astryxdesign/core/Card";
import { TextInput, type TextInputStatus } from "@astryxdesign/core/TextInput";
import { HStack, StackItem, VStack } from "@astryxdesign/core/Stack";
import { StatusDot } from "@astryxdesign/core/StatusDot";
import { Heading, Text } from "@astryxdesign/core/Text";
import { submitChallenge } from "../../lib/challenges/client";
import type { FlagChallengeData } from "../../lib/challenges/types";
import type { CourseOfferingKey } from "../../lib/learning/identifiers";
import { readActivityProgress, writeActivityProgress } from "../../lib/progress/activity-progress";

interface Props {
  taskId: string;
  challenge: FlagChallengeData;
  offeringKey: CourseOfferingKey;
}

type Result = "idle" | "incorrect" | "correct";

export default function FlagChallengeIsland({ taskId, challenge, offeringKey }: Props) {
  const [value, setValue] = useState("");
  const [result, setResult] = useState<Result>("idle");
  const [message, setMessage] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);

  useEffect(() => {
    if (readActivityProgress(taskId).status === "completed") setResult("correct");
  }, [taskId]);

  const status: TextInputStatus | undefined =
    result === "correct"
      ? { type: "success", message: message || "Checkpoint complete." }
      : result === "incorrect"
        ? { type: "error", message }
        : undefined;

  const submit = async (event: SubmitEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!value.trim()) {
      setResult("incorrect");
      setMessage("Enter a flag before checking it.");
      return;
    }
    setIsSubmitting(true);
    const evaluation = await submitChallenge(offeringKey, { type: "flag", taskId, value });
    if (!evaluation) {
      setResult("incorrect");
      setMessage("The activity is temporarily unavailable.");
      setIsSubmitting(false);
      return;
    }
    setResult(evaluation.isCorrect ? "correct" : "incorrect");
    setMessage(evaluation.message);
    setIsSubmitting(false);
    if (evaluation.isCorrect) {
      writeActivityProgress(taskId, { status: "completed", completedSteps: [] });
    }
  };

  return (
    <Card className="task-island" padding={5}>
      <form onSubmit={(event) => void submit(event)}>
        <VStack gap={4}>
          <HStack gap={3} vAlign="start">
            <StackItem size="fill">
              <VStack gap={1}>
                <Text type="supporting" color="secondary" weight="medium">
                  Final checkpoint
                </Text>
                <Heading level={3}>{challenge.title}</Heading>
                <Text type="body" color="secondary">
                  {challenge.description}
                </Text>
              </VStack>
            </StackItem>
            <HStack gap={2} vAlign="center">
              <StatusDot
                label={result === "correct" ? "Completed" : "Open"}
                variant={result === "correct" ? "success" : "neutral"}
              />
              <Text type="supporting" color="secondary">
                {result === "correct" ? "Complete" : "Open"}
              </Text>
            </HStack>
          </HStack>

          <TextInput
            hasClear
            isDisabled={result === "correct"}
            isRequired
            label="Flag"
            onChange={(nextValue) => {
              setValue(nextValue);
              if (result === "incorrect") {
                setResult("idle");
                setMessage("");
              }
            }}
            placeholder={challenge.placeholder}
            {...(status ? { status } : {})}
            value={value}
            width="100%"
          />

          <HStack gap={3} vAlign="center" wrap="wrap">
            <Button
              isDisabled={result === "correct"}
              isLoading={isSubmitting}
              label={result === "correct" ? "Flag accepted" : "Check flag"}
              type="submit"
              variant="primary"
            />
            <Text type="supporting" color="secondary">
              Expected form: {challenge.expectedFormat}
            </Text>
          </HStack>
        </VStack>
      </form>
    </Card>
  );
}
