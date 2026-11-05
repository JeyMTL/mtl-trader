export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.17"
  }
  public: {
    Tables: {
      ai_reviews: {
        Row: {
          created_at: string | null
          id: string
          model: string | null
          provider: string | null
          review: Json
          similar: Json | null
          stats: Json | null
          summary_hash: string
          user_id: string
        }
        Insert: {
          created_at?: string | null
          id?: string
          model?: string | null
          provider?: string | null
          review: Json
          similar?: Json | null
          stats?: Json | null
          summary_hash: string
          user_id: string
        }
        Update: {
          created_at?: string | null
          id?: string
          model?: string | null
          provider?: string | null
          review?: Json
          similar?: Json | null
          stats?: Json | null
          summary_hash?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_reviews_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      backtests: {
        Row: {
          assumptions: Json
          bar_count: number
          benchmark: Json | null
          config: Json
          created_at: string
          equity_curve: Json | null
          id: string
          metrics: Json
          name: string
          period_end: string
          period_start: string
          split_metrics: Json | null
          strategy_id: string
          strategy_params: Json
          stress: Json | null
          symbol: string
          timeframe: string
          trades: Json | null
          user_id: string
          warnings: Json
        }
        Insert: {
          assumptions?: Json
          bar_count: number
          benchmark?: Json | null
          config: Json
          created_at?: string
          equity_curve?: Json | null
          id?: string
          metrics: Json
          name: string
          period_end: string
          period_start: string
          split_metrics?: Json | null
          strategy_id: string
          strategy_params?: Json
          stress?: Json | null
          symbol: string
          timeframe?: string
          trades?: Json | null
          user_id: string
          warnings?: Json
        }
        Update: {
          assumptions?: Json
          bar_count?: number
          benchmark?: Json | null
          config?: Json
          created_at?: string
          equity_curve?: Json | null
          id?: string
          metrics?: Json
          name?: string
          period_end?: string
          period_start?: string
          split_metrics?: Json | null
          strategy_id?: string
          strategy_params?: Json
          stress?: Json | null
          symbol?: string
          timeframe?: string
          trades?: Json | null
          user_id?: string
          warnings?: Json
        }
        Relationships: [
          {
            foreignKeyName: "backtests_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      billing_subscriptions: {
        Row: {
          created_at: string
          email: string | null
          id: string
          provider: string
          remote_plan_id: string | null
          status: string
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          email?: string | null
          id?: string
          provider: string
          remote_plan_id?: string | null
          status?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          email?: string | null
          id?: string
          provider?: string
          remote_plan_id?: string | null
          status?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "billing_subscriptions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      broker_connections: {
        Row: {
          account_login: string
          broker_name: string
          created_at: string
          credential_cipher: string
          last_attempt_at: string | null
          last_error: string | null
          last_sync_at: string | null
          provider: string
          server: string
          status: string
          updated_at: string
          user_id: string
        }
        Insert: {
          account_login: string
          broker_name: string
          created_at?: string
          credential_cipher: string
          last_attempt_at?: string | null
          last_error?: string | null
          last_sync_at?: string | null
          provider?: string
          server: string
          status?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          account_login?: string
          broker_name?: string
          created_at?: string
          credential_cipher?: string
          last_attempt_at?: string | null
          last_error?: string | null
          last_sync_at?: string | null
          provider?: string
          server?: string
          status?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "broker_connections_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      deposits: {
        Row: {
          amount: number
          created_at: string | null
          description: string | null
          id: string
          type: string
          user_id: string | null
        }
        Insert: {
          amount: number
          created_at?: string | null
          description?: string | null
          id?: string
          type?: string
          user_id?: string | null
        }
        Update: {
          amount?: number
          created_at?: string | null
          description?: string | null
          id?: string
          type?: string
          user_id?: string | null
        }
        Relationships: []
      }
      google_play_subscriptions: {
        Row: {
          acknowledged: boolean
          expires_at: string | null
          interval: string
          plan_id: string
          product_id: string
          purchase_token: string
          state: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          acknowledged?: boolean
          expires_at?: string | null
          interval?: string
          plan_id: string
          product_id: string
          purchase_token: string
          state?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          acknowledged?: boolean
          expires_at?: string | null
          interval?: string
          plan_id?: string
          product_id?: string
          purchase_token?: string
          state?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "google_play_subscriptions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      notification_sends: {
        Row: {
          id: string
          kind: string
          sent_at: string
          user_id: string
          window_key: string
        }
        Insert: {
          id?: string
          kind: string
          sent_at?: string
          user_id: string
          window_key: string
        }
        Update: {
          id?: string
          kind?: string
          sent_at?: string
          user_id?: string
          window_key?: string
        }
        Relationships: [
          {
            foreignKeyName: "notification_sends_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      payment_events: {
        Row: {
          amount: number
          created_at: string | null
          id: string
          plan_id: string
          provider: string
          provider_event_id: string
          status: string
          user_id: string | null
        }
        Insert: {
          amount: number
          created_at?: string | null
          id?: string
          plan_id: string
          provider?: string
          provider_event_id: string
          status?: string
          user_id?: string | null
        }
        Update: {
          amount?: number
          created_at?: string | null
          id?: string
          plan_id?: string
          provider?: string
          provider_event_id?: string
          status?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "payment_events_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      payment_requests: {
        Row: {
          amount: number
          created_at: string | null
          id: string
          plan_id: string
          reference: string
          reviewed_at: string | null
          reviewed_by: string | null
          status: string
          user_id: string
        }
        Insert: {
          amount: number
          created_at?: string | null
          id?: string
          plan_id: string
          reference: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
          user_id: string
        }
        Update: {
          amount?: number
          created_at?: string | null
          id?: string
          plan_id?: string
          reference?: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "payment_requests_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      prop_rules: {
        Row: {
          account_size: number
          max_daily_loss_pct: number
          max_drawdown_pct: number
          min_trading_days: number
          profit_target_pct: number
          started_on: string
          trailing_drawdown: boolean
          updated_at: string
          user_id: string
        }
        Insert: {
          account_size: number
          max_daily_loss_pct?: number
          max_drawdown_pct?: number
          min_trading_days?: number
          profit_target_pct?: number
          started_on?: string
          trailing_drawdown?: boolean
          updated_at?: string
          user_id: string
        }
        Update: {
          account_size?: number
          max_daily_loss_pct?: number
          max_drawdown_pct?: number
          min_trading_days?: number
          profit_target_pct?: number
          started_on?: string
          trailing_drawdown?: boolean
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "prop_rules_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      rate_limits: {
        Row: {
          count: number
          key: string
          reset_at: string
        }
        Insert: {
          count: number
          key: string
          reset_at: string
        }
        Update: {
          count?: number
          key?: string
          reset_at?: string
        }
        Relationships: []
      }
      sync_suppressions: {
        Row: {
          deleted_at: string
          position_id: number
          user_id: string
        }
        Insert: {
          deleted_at?: string
          position_id: number
          user_id: string
        }
        Update: {
          deleted_at?: string
          position_id?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "sync_suppressions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      telemetry_events: {
        Row: {
          app_version: string | null
          created_at: string
          event: string
          id: number
          platform: string
          properties: Json
          session_id: string
          user_id: string | null
        }
        Insert: {
          app_version?: string | null
          created_at?: string
          event: string
          id?: number
          platform: string
          properties?: Json
          session_id: string
          user_id?: string | null
        }
        Update: {
          app_version?: string | null
          created_at?: string
          event?: string
          id?: number
          platform?: string
          properties?: Json
          session_id?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "telemetry_events_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      trade_attachments: {
        Row: {
          created_at: string
          duration_seconds: number | null
          file_name: string | null
          id: string
          kind: string
          mime_type: string | null
          size_bytes: number | null
          storage_path: string
          trade_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          duration_seconds?: number | null
          file_name?: string | null
          id?: string
          kind: string
          mime_type?: string | null
          size_bytes?: number | null
          storage_path: string
          trade_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          duration_seconds?: number | null
          file_name?: string | null
          id?: string
          kind?: string
          mime_type?: string | null
          size_bytes?: number | null
          storage_path?: string
          trade_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "trade_attachments_trade_id_fkey"
            columns: ["trade_id"]
            isOneToOne: false
            referencedRelation: "trades"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "trade_attachments_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      trades: {
        Row: {
          close_time: string | null
          commission: number | null
          created_at: string | null
          entry_price: number
          exit_price: number
          id: string
          import_id: string | null
          lot_size: number | null
          notes: string | null
          open_time: string | null
          pnl: number
          position_id: number | null
          stop_loss: number | null
          strategy: string | null
          swap: number | null
          symbol: string
          tags: string[] | null
          take_profit: number | null
          ticket: number | null
          timeframe: string | null
          type: string
          user_id: string | null
        }
        Insert: {
          close_time?: string | null
          commission?: number | null
          created_at?: string | null
          entry_price: number
          exit_price: number
          id?: string
          import_id?: string | null
          lot_size?: number | null
          notes?: string | null
          open_time?: string | null
          pnl: number
          position_id?: number | null
          stop_loss?: number | null
          strategy?: string | null
          swap?: number | null
          symbol: string
          tags?: string[] | null
          take_profit?: number | null
          ticket?: number | null
          timeframe?: string | null
          type: string
          user_id?: string | null
        }
        Update: {
          close_time?: string | null
          commission?: number | null
          created_at?: string | null
          entry_price?: number
          exit_price?: number
          id?: string
          import_id?: string | null
          lot_size?: number | null
          notes?: string | null
          open_time?: string | null
          pnl?: number
          position_id?: number | null
          stop_loss?: number | null
          strategy?: string | null
          swap?: number | null
          symbol?: string
          tags?: string[] | null
          take_profit?: number | null
          ticket?: number | null
          timeframe?: string | null
          type?: string
          user_id?: string | null
        }
        Relationships: []
      }
      users: {
        Row: {
          agent_token: string | null
          cancel_at_period_end: boolean
          created_at: string | null
          currency: string | null
          current_period_end: string | null
          current_period_start: string | null
          email: string
          full_name: string | null
          id: string
          is_admin: boolean
          last_payment_at: string | null
          max_trades: number | null
          notifications_daily: boolean | null
          notifications_email: boolean | null
          notifications_journal_reminders: boolean | null
          notifications_marketing: boolean | null
          notifications_monthly_email: boolean | null
          notifications_monthly_overview: boolean | null
          notifications_weekly: boolean | null
          stripe_customer_id: string | null
          subscription_status: string | null
          subscription_tier: string | null
          timezone: string | null
          trades_remaining: number | null
          trial_ends_at: string | null
        }
        Insert: {
          agent_token?: string | null
          cancel_at_period_end?: boolean
          created_at?: string | null
          currency?: string | null
          current_period_end?: string | null
          current_period_start?: string | null
          email: string
          full_name?: string | null
          id?: string
          is_admin?: boolean
          last_payment_at?: string | null
          max_trades?: number | null
          notifications_daily?: boolean | null
          notifications_email?: boolean | null
          notifications_journal_reminders?: boolean | null
          notifications_marketing?: boolean | null
          notifications_monthly_email?: boolean | null
          notifications_monthly_overview?: boolean | null
          notifications_weekly?: boolean | null
          stripe_customer_id?: string | null
          subscription_status?: string | null
          subscription_tier?: string | null
          timezone?: string | null
          trades_remaining?: number | null
          trial_ends_at?: string | null
        }
        Update: {
          agent_token?: string | null
          cancel_at_period_end?: boolean
          created_at?: string | null
          currency?: string | null
          current_period_end?: string | null
          current_period_start?: string | null
          email?: string
          full_name?: string | null
          id?: string
          is_admin?: boolean
          last_payment_at?: string | null
          max_trades?: number | null
          notifications_daily?: boolean | null
          notifications_email?: boolean | null
          notifications_journal_reminders?: boolean | null
          notifications_marketing?: boolean | null
          notifications_monthly_email?: boolean | null
          notifications_monthly_overview?: boolean | null
          notifications_weekly?: boolean | null
          stripe_customer_id?: string | null
          subscription_status?: string | null
          subscription_tier?: string | null
          timezone?: string | null
          trades_remaining?: number | null
          trial_ends_at?: string | null
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      apply_annual_order: {
        Args: {
          p_amount: number
          p_plan_id: string
          p_provider: string
          p_provider_event_id: string
          p_user_id: string
        }
        Returns: string
      }
      apply_paid_order: {
        Args: {
          p_amount: number
          p_plan_id: string
          p_provider: string
          p_provider_event_id: string
          p_user_id: string
        }
        Returns: string
      }
      check_rate_limit: {
        Args: { p_key: string; p_limit: number; p_window_ms: number }
        Returns: {
          allowed: boolean
          remaining: number
          retry_after_ms: number
        }[]
      }
      daily_pnl: { Args: { p_from: string; p_to: string }; Returns: Json }
      day_trades: { Args: { p_day: string }; Returns: Json }
      delete_account_data: { Args: { p_user_id: string }; Returns: string }
      deposits_total: { Args: never; Returns: number }
      equity_curve: { Args: never; Returns: Json }
      expire_lapsed_subscriptions: { Args: never; Returns: number }
      journal_feed: { Args: { p_limit?: number }; Returns: Json }
      latest_trade_day: { Args: never; Returns: string }
      month_trade_count: { Args: never; Returns: number }
      notification_trades: {
        Args: { p_since: string; p_user_id: string }
        Returns: Json
      }
      prop_status: { Args: { p_user_id: string }; Returns: Json }
      prune_telemetry: { Args: { p_keep_days?: number }; Returns: number }
      review_bank_payment_request: {
        Args: { p_action: string; p_request_id: string; p_reviewer_id: string }
        Returns: string
      }
      revoke_paid_order: {
        Args: {
          p_amount: number
          p_plan_id: string
          p_provider: string
          p_provider_event_id: string
          p_user_id: string
        }
        Returns: string
      }
      session_stats: { Args: never; Returns: Json }
      strategy_labels: {
        Args: { p_limit?: number }
        Returns: {
          label: string
          trades: number
        }[]
      }
      strategy_stats: {
        Args: { p_limit?: number }
        Returns: {
          losses: number
          pnl: number
          strategy: string
          trades: number
          win_rate: number
          wins: number
        }[]
      }
      sweep_rate_limits: { Args: never; Returns: number }
      symbol_stats: { Args: { p_limit?: number }; Returns: Json }
      tag_stats: {
        Args: { p_limit?: number }
        Returns: {
          losses: number
          pnl: number
          tag: string
          trades: number
          win_rate: number
          wins: number
        }[]
      }
      time_stats: { Args: never; Returns: Json }
      trade_breakdowns: { Args: never; Returns: Json }
      trade_page: {
        Args: {
          p_filter?: string
          p_limit?: number
          p_offset?: number
          p_search?: string
          p_session?: string
        }
        Returns: Json
      }
      trade_summary: { Args: never; Returns: Json }
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
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
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
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
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
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
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
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
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
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
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
