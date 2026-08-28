export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  public: {
    Tables: {
      course_memberships: {
        Row: {
          course_id: string
          created_at: string
          created_from_access_request_id: string | null
          profile_id: string
          revoked_at: string | null
          role: string
          status: string
          suspended_at: string | null
        }
        Insert: {
          course_id: string
          created_at?: string
          created_from_access_request_id?: string | null
          profile_id: string
          revoked_at?: string | null
          role: string
          status?: string
          suspended_at?: string | null
        }
        Update: {
          course_id?: string
          created_at?: string
          created_from_access_request_id?: string | null
          profile_id?: string
          revoked_at?: string | null
          role?: string
          status?: string
          suspended_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "course_memberships_course_id_fkey"
            columns: ["course_id"]
            isOneToOne: false
            referencedRelation: "courses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "course_memberships_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      courses: {
        Row: {
          code: string
          course_definition_key: string
          course_definition_release_id: string
          created_at: string
          ends_at: string | null
          enrollment_mode: string
          external_url: string | null
          id: string
          offering_key: string
          starts_at: string | null
          status: string
          updated_at: string
        }
        Insert: {
          code: string
          course_definition_key: string
          course_definition_release_id: string
          created_at?: string
          ends_at?: string | null
          enrollment_mode?: string
          external_url?: string | null
          id?: string
          offering_key: string
          starts_at?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          code?: string
          course_definition_key?: string
          course_definition_release_id?: string
          created_at?: string
          ends_at?: string | null
          enrollment_mode?: string
          external_url?: string | null
          id?: string
          offering_key?: string
          starts_at?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: []
      }
      profiles: {
        Row: {
          created_at: string
          display_name: string
          id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          display_name?: string
          id?: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          display_name?: string
          id?: string
          updated_at?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      approve_course_access_requests: {
        Args: { p_offering_key: string; p_request_ids?: string[] }
        Returns: number
      }
      get_my_profile: {
        Args: never
        Returns: {
          created_at: string
          display_name: string
          updated_at: string
        }[]
      }
      list_course_access_requests: {
        Args: {
          p_authorization_filter?: string
          p_offering_key: string
          p_status?: string
        }
        Returns: {
          authorization_status: string
          decided_at: string
          display_name: string
          github_access_state: string
          github_username: string
          offering_key: string
          reason: string
          request_id: string
          requested_at: string
          status: string
          verified_email: string
        }[]
      }
      list_course_roster: {
        Args: { p_offering_key: string }
        Returns: {
          created_at: string
          display_name: string
          revoked_at: string
          role: string
          status: string
          suspended_at: string
        }[]
      }
      list_my_course_access_requests: {
        Args: never
        Returns: {
          decided_at: string
          github_access_state: string
          offering_key: string
          reason: string
          request_id: string
          requested_at: string
          status: string
        }[]
      }
      list_my_courses: { Args: never; Returns: Json }
      reject_course_access_requests: {
        Args: {
          p_decision_reason?: string
          p_offering_key: string
          p_request_ids?: string[]
        }
        Returns: number
      }
      request_course_access: {
        Args: { p_offering_key: string; p_reason?: string }
        Returns: Json
      }
      update_my_profile: {
        Args: { p_display_name: string }
        Returns: {
          created_at: string
          display_name: string
          updated_at: string
        }[]
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const

