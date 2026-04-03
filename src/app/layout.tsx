import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Gatekipa — Stop Unwanted Subscription Charges",
  description:
    "Gatekipa blocks forgotten and unwanted subscription charges automatically, for you and your business. Control every subscription across personal use, teams, and clients before the next charge hits.",
  keywords: [
    "subscription management",
    "virtual cards",
    "subscription control",
    "fintech Nigeria",
    "stop unwanted charges",
    "free trial protection",
  ],
  openGraph: {
    title: "Gatekipa — Stop Unwanted Subscription Charges",
    description:
      "Gatekipa blocks forgotten and unwanted subscription charges automatically. Join the waitlist.",
    type: "website",
    url: "https://gatekipa.com",
  },
  twitter: {
    card: "summary_large_image",
    title: "Gatekipa — Stop Unwanted Subscription Charges",
    description:
      "Gatekipa blocks forgotten and unwanted subscription charges automatically. Join the waitlist.",
  },
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <head>
        <link
          rel="stylesheet"
          href="https://cdn.jsdelivr.net/npm/geist@1/dist/font/css/all.min.css"
        />
      </head>
      <body className="noise-overlay">{children}</body>
    </html>
  );
}
