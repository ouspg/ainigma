import { GraduationCap } from "lucide-react";
import { navigate } from "astro:transitions/client";
import { createElement, type MouseEvent } from "react";
import type { AppPath } from "../routes";

interface CourseMarkProps {
  href?: AppPath;
  isCollapsed: boolean;
  mark: string;
}

export function CourseMark({ href, isCollapsed, mark }: CourseMarkProps) {
  const openCourse = (event: MouseEvent<HTMLSpanElement>) => {
    if (!isCollapsed || !href) return;
    event.preventDefault();
    event.stopPropagation();
    void navigate(href);
  };

  return createElement(
    "span",
    {
      className: "course-nav-mark",
      "aria-hidden": true,
      onClick: openCourse,
    },
    isCollapsed
      ? createElement("span", { className: "course-nav-monogram" }, mark)
      : createElement(GraduationCap),
  );
}

export function getCourseIcon(_slug: string) {
  return GraduationCap;
}
