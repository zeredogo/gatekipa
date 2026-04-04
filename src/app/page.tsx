import { Suspense } from "react";
import Navbar from "@/components/Navbar";
import HeroSection from "@/components/HeroSection";
import PainSection from "@/components/PainSection";
import InsightSection from "@/components/InsightSection";
import HowItWorksSection from "@/components/HowItWorksSection";
import FeaturesSection from "@/components/FeaturesSection";
import SecuritySection from "@/components/SecuritySection";
import FAQSection from "@/components/FAQSection";
import ContactSection from "@/components/ContactSection";
import WaitlistSection from "@/components/WaitlistSection";
import FinalCTASection from "@/components/FinalCTASection";
import Footer from "@/components/Footer";

export default function Home() {
  return (
    <main>
      <Navbar />
      <HeroSection />
      <PainSection />
      <InsightSection />
      <HowItWorksSection />
      <FeaturesSection />
      <SecuritySection />
      <FAQSection />
      <ContactSection />
      <Suspense fallback={null}>
        <WaitlistSection />
      </Suspense>
      <FinalCTASection />
      <Footer />
    </main>
  );
}
