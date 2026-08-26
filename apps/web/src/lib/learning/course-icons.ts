import { GraduationCap } from "lucide-react";
import { useSideNavCollapse } from "@astryxdesign/core/SideNav";
import { navigate } from "astro:transitions/client";
import { createElement, type MouseEvent } from "react";
import type { AppPath } from "../routes";

interface CourseMarkProps {
  href?: AppPath;
  mark: string;
}

export function CourseMark({ href, mark }: CourseMarkProps) {
  const { isCollapsed } = useSideNavCollapse();

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
