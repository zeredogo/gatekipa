"use server";

import { cookies } from "next/headers";
import { auth } from "@/lib/firebaseAdmin";

export async function createSession(idToken: string) {
  try {
    const expiresIn = 60 * 60 * 24 * 5 * 1000; // 5 days
    const sessionCookie = await auth.createSessionCookie(idToken, { expiresIn });
    
    const cookieStore = await cookies();
    cookieStore.set("session", sessionCookie, {
      maxAge: expiresIn / 1000,
      httpOnly: true,
      secure: process.env.NODE_ENV === "production",
      path: "/",
      sameSite: "lax",
    });
    
    return { success: true };
  } catch (error) {
    console.error("Session creation failed", error);
    return { success: false, error: "Unauthorized" };
  }
}

export async function removeSession() {
  const cookieStore = await cookies();
  cookieStore.delete("session");
  return { success: true };
}
