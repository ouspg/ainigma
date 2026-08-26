import { z } from "astro/zod";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "../supabase/database.types";
import type { StudentProfile } from "../learning/types";

const profileRowSchema = z.object({
  display_name: z.string().trim().min(1),
});

export async function loadStudentProfile(
  supabase: SupabaseClient<Database>,
): Promise<StudentProfile> {
  const { data, error } = await supabase.rpc("get_my_profile");
  if (error) {
    throw new Error("Unable to load the authenticated profile.", { cause: error });
  }
  const profile = profileRowSchema.parse(data[0]);
  const displayName = profile.display_name.trim();

  return {
    displayName,
    firstName: displayName.split(/\s+/)[0] ?? displayName,
  };
}
