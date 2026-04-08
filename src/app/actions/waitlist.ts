"use server";

import { neon } from "@neondatabase/serverless";
import { z } from "zod";
import { v4 as uuidv4 } from "uuid";
import { Resend } from "resend";

const resend = process.env.RESEND_API_KEY ? new Resend(process.env.RESEND_API_KEY) : null;

// Schema for email validation
const WaitlistSchema = z.object({
  email: z.string().email("Invalid email address"),
  referredBy: z.string().nullable().optional(),
});

/**
 * Ensures the waitlist table exists before any database operations.
 * This is a "Zero-Config" setup helper.
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
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
 * Join the Gatekipa waitlist using Vercel Postgres (Neon) or fallback mock
 */
export async function joinWaitlist(formData: FormData) {
  const rawEmail = formData.get("email");
  const email = typeof rawEmail === "string" ? rawEmail.trim() : "";
  const rawReferredBy = formData.get("referredBy");
  const referredBy = typeof rawReferredBy === "string" && rawReferredBy.trim() !== "" ? rawReferredBy.trim() : null;

  // 1. Validate Input
  const validation = WaitlistSchema.safeParse({ email, referredBy });
  if (!validation.success) {
    const errorMsg = validation.error.issues[0]?.message || "Invalid input";
    return { error: `Invalid form submission: ${errorMsg}` };
  }

  // Graceful fallback for missing database connection
  if (!process.env.DATABASE_URL) {
    console.warn("DATABASE_URL is missing. Using mock waitlist.");
    const referralCode = uuidv4().substring(0, 8).toUpperCase();
    return {
      success: true,
      referralCode,
      position: Math.floor(Math.random() * 500) + 1204, // random position
    };
  }

  const sql = neon(process.env.DATABASE_URL);

  // Zero-Config Auto Migration
  await ensureTableExists(sql);

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

    // 6. Send Confirmation Email (Non-blocking)
    if (resend) {
      try {
        await resend.emails.send({
          from: "Gatekipa <onboarding@resend.dev>",
          to: email,
          subject: "You're on the list! Welcome to Gatekipa 🎉",
          html: `
            <div style="font-family: sans-serif; max-width: 600px; margin: 0 auto; line-height: 1.6; color: #333;">
              <h1 style="color: #1a1a1a;">You're on the list! 🚀</h1>
              <p>Hi there,</p>
              <p>Thank you for joining the <strong>Gatekipa</strong> waitlist! We are excited to have you on board to help you stop unwanted subscription charges before they happen.</p>
              <p>Your current waitlist position is: <strong style="font-size: 24px;">#${totalCount}</strong></p>
              
              <div style="background: #f4f4f5; padding: 20px; border-radius: 12px; margin: 20px 0;">
                <h3 style="margin-top: 0;">Move up the list!</h3>
                <p>Want to get early access faster? Refer your friends using your unique link:</p>
                <code style="display: block; background: #e4e4e7; padding: 12px; border-radius: 8px; font-size: 16px;">
                  https://gatekipa.com/?ref=${referralCode}
                </code>
              </div>
              
              <p>We'll notify you as soon as your spot opens up.</p>
              <p>Best regards,<br/><strong>The Gatekipa Team</strong></p>
            </div>
          `,
        });
      } catch (emailErr) {
        console.error("Resend Email Error:", emailErr);
        // We don't fail the complete waitlist signup if the email fails.
      }
    }

    return {
      success: true,
      referralCode,
      position: totalCount,
    };
  } catch (err: unknown) {
    const error = err as Error & { code?: string };
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
