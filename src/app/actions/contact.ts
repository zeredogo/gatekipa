"use server";

import { z } from "zod";
import { Resend } from "resend";

const resend = new Resend(process.env.RESEND_API_KEY);

const ContactSchema = z.object({
  name: z.string().min(1, "Name is required"),
  email: z.string().email("Invalid email address"),
  message: z.string().min(1, "Message is required"),
});

export async function submitContactForm(formData: FormData) {
  const rawName = formData.get("name");
  const name = typeof rawName === "string" ? rawName.trim() : "";
  const rawEmail = formData.get("email");
  const email = typeof rawEmail === "string" ? rawEmail.trim() : "";
  const rawMessage = formData.get("message");
  const message = typeof rawMessage === "string" ? rawMessage.trim() : "";

  const validation = ContactSchema.safeParse({ name, email, message });
  if (!validation.success) {
    const errorMsg = validation.error.issues[0]?.message || "Invalid input";
    return { error: `Invalid form submission: ${errorMsg}` };
  }

  if (!process.env.RESEND_API_KEY) {
    console.warn("RESEND_API_KEY is missing. Simulating contact success.");
    return { success: true };
  }

  try {
    await resend.emails.send({
      from: "Gatekipa Contact Form <onboarding@resend.dev>", // Needs to be a verified domain, resend defaults to this for testing or update to verified later.
      replyTo: email,
      to: "hello@gatekipa.com",
      subject: `New Contact Message from ${name}`,
      text: `Name: ${name}\nEmail: ${email}\nMessage:\n${message}`,
    });

    return {
      success: true,
    };
  } catch (err: unknown) {
    const error = err as Error;
    console.error("Contact Error:", error);
    return { error: "Something went wrong sending your message. Please try again later." };
  }
}
