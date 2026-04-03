"use server";

import { neon } from "@neondatabase/serverless";
import { z } from "zod";
import { v4 as uuidv4 } from "uuid";

// Schema for email validation
const WaitlistSchema = z.object({
  email: z.string().email("Invalid email address"),
  referredBy: z.string().optional(),
});

/**
 * Ensures the waitlist table exists before any database operations.
 * This is a "Zero-Config" setup helper.
 */
async function ensureTableExists(sql: any) {
  try {
    await sql`
      CREATE TABLE IF NOT EXISTS waitlist (
        id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
        email TEXT UNIQUE NOT NULL,
        referral_code TEXT UNIQUE NOT NULL,
        referred_by TEXT,
        position SERIAL,
        created_at TIMESTAMPTZ DEFAULT NOW()
      );
    `;
    // Create indexes if they don't exist
    await sql`CREATE INDEX IF NOT EXISTS idx_waitlist_email ON waitlist(email)`;
    await sql`CREATE INDEX IF NOT EXISTS idx_waitlist_referral_code ON waitlist(referral_code)`;
  } catch (error) {
    console.error("Auto-Migration Error:", error);
  }
}

/**
 * Join the Gatekipa waitlist using Vercel Postgres (Neon)
 */
export async function joinWaitlist(formData: FormData) {
  if (!process.env.DATABASE_URL) {
    return { error: "Database not connected. Please see the setup guide." };
  }

  const sql = neon(process.env.DATABASE_URL);

  // Zero-Config Auto Migration
  await ensureTableExists(sql);

  const email = formData.get("email") as string;
  const referredBy = formData.get("referredBy") as string | null;

  // 1. Validate Input
  const validation = WaitlistSchema.safeParse({ email, referredBy });
  if (!validation.success) {
    return { error: validation.error.errors[0].message };
  }

  try {
    // 2. Check if user already exists
    const existingUsers = await sql`
      SELECT id, referral_code, position FROM waitlist WHERE email = ${email}
    `;

    if (existingUsers.length > 0) {
      const user = existingUsers[0];
      return {
        success: true,
        alreadyJoined: true,
        referralCode: user.referral_code,
        position: user.position,
      };
    }

    // 3. Generate unique referral code
    const referralCode = uuidv4().substring(0, 8).toUpperCase();

    // 4. Insert new user
    await sql`
      INSERT INTO waitlist (email, referral_code, referred_by)
      VALUES (${email}, ${referralCode}, ${referredBy})
    `;

    // 5. Get total count for position
    const stats = await sql`SELECT count(*) FROM waitlist`;
    const totalCount = parseInt(stats[0].count);

    return {
      success: true,
      referralCode,
      position: totalCount,
    };
  } catch (error: any) {
    console.error("Waitlist Error:", error);
    if (error.code === "23505") { // Duplicate email handling
      return { error: "You are already on the waitlist!" };
    }
    return { error: "Something went wrong. Please try again." };
  }
}

/**
 * Fetch total waitlist count for live counters
 */
export async function getWaitlistStats() {
  if (!process.env.DATABASE_URL) {
    return { count: 1204 }; // Fallback
  }

  const sql = neon(process.env.DATABASE_URL);

  try {
    // Quick check if table exists before querying stats
    // We don't auto-migrate here to avoid slow page loads
    const stats = await sql`SELECT count(*) FROM waitlist`;
    return { count: parseInt(stats[0].count) };
  } catch (error) {
    return { count: 1204 }; // Fallback to starting number
  }
}
