const ACTIVITY_COMPONENTS = new Set(["FlagChallenge", "MultipartLab"]);

function getStringAttribute(node, name) {
  const attribute = node.attributes?.find(
    (candidate) => candidate.type === "mdxJsxAttribute" && candidate.name === name,
  );
  return typeof attribute?.value === "string" ? attribute.value : undefined;
}

export function remarkActivityOutline() {
  return (tree, file) => {
    let headingIndex = -1;
    const activityIdsByHeading = new Map();

    const visit = (node) => {
      if (node.type === "heading") {
        headingIndex += 1;
      }

      if (node.type === "mdxJsxFlowElement" && ACTIVITY_COMPONENTS.has(node.name)) {
        const activityId = getStringAttribute(node, "taskId");
        if (activityId && headingIndex >= 0) {
          const activityIds = activityIdsByHeading.get(headingIndex) ?? [];
          activityIds.push(activityId);
          activityIdsByHeading.set(headingIndex, activityIds);
        }
      }

      for (const child of node.children ?? []) {
        visit(child);
      }
    };

    visit(tree);

    file.data.astro ??= {};
    file.data.astro.frontmatter ??= {};
    file.data.astro.frontmatter.activityOutline = Array.from(
      activityIdsByHeading,
      ([index, activityIds]) => ({ headingIndex: index, activityIds }),
    );
  };
}
