"use server";

import { z } from "zod";
import nodemailer from "nodemailer";

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

  try {
    const transporter = nodemailer.createTransport({
      host: process.env.SMTP_HOST || "smtp.gmail.com",
      port: parseInt(process.env.SMTP_PORT || "465"),
      secure: true,
      auth: {
        user: process.env.SMTP_USER,
        pass: process.env.SMTP_PASS,
      },
    });

    await transporter.sendMail({
      from: `"Gatekipa Contact Form" <${process.env.SMTP_USER || "noreply@gatekipa.com"}>`,
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
