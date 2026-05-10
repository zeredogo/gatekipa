"use client";

import React, { useState, useEffect } from "react";
import { useSearchParams } from "next/navigation";
import { joinWaitlist, getWaitlistStats } from "@/app/actions/waitlist";

const WaitlistSection = () => {
  const [email, setEmail] = useState("");
  const [submitted, setSubmitted] = useState(false);
  const [referralCode, setReferralCode] = useState("");
  const [referralLink, setReferralLink] = useState("");
  const [position, setPosition] = useState(1204);
  const [totalCount, setTotalCount] = useState(1204);
  const [loading, setLoading] = useState(false);
  const [errorMessage, setErrorMessage] = useState("");
  const [toast, setToast] = useState<{title: string, desc?: string, type: "success" | "error"} | null>(null);

  const showToast = (title: string, desc?: string, type: "success" | "error" = "success") => {
    setToast({title, desc, type});
    setTimeout(() => setToast(null), 4000);
  };

  const searchParams = useSearchParams();
  const referredBy = searchParams.get("ref");

  useEffect(() => {
    // Fetch live stats on load
    const fetchStats = async () => {
      const stats = await getWaitlistStats();
      setTotalCount(stats.count);
    };
    fetchStats();
  }, []);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!email) return;

    setLoading(true);
    setErrorMessage("");

    try {
      const formData = new FormData();
      formData.append("email", email);
      if (referredBy) formData.append("referredBy", referredBy);

      const result = await joinWaitlist(formData);

      if (result.success) {
        setReferralCode(result.referralCode || "");
        setReferralLink(`${window.location.origin}?ref=${result.referralCode}`);
        setPosition(result.position);
        setSubmitted(true);
        showToast("Success!", "You're successfully on the waitlist.", "success");
      } else if (result.error) {
        setErrorMessage(result.error);
        showToast("Error", result.error, "error");
      }
    } catch (err) {
      setErrorMessage("Something went wrong. Please try again.");
      showToast("Error", "Something went wrong. Please try again.", "error");
    } finally {
      setLoading(false);
    }
  };

  const copyToClipboard = () => {
     if (typeof window !== "undefined") {
        navigator.clipboard.writeText(referralLink);
        showToast("Link Copied!", "Share it to move up the waitlist.", "success");
     }
  };

  return (
    <section id="waitlist" className="py-32 px-4 relative overflow-hidden bg-anime-pattern">
      {/* Background Decor */}
      <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 size-[600px] bg-primary/20 blur-[150px] animate-pulse rounded-full" />
      
      <div className="max-w-[1600px] mx-auto px-4 sm:px-12 relative z-10">
        {!submitted ? (
          <div className="max-w-4xl mx-auto text-center flex flex-col items-center">
            <div className="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-primary/10 border border-primary/20 text-primary text-xs font-bold tracking-widest uppercase mb-12 animate-bounce">
              <span className="size-2 bg-primary rounded-full animate-ping" />
              Secure your spot
            </div>
            
            <h2 className="text-5xl sm:text-8xl font-extrabold text-foreground mb-6 tracking-tighter leading-none">
              Get <br/>
              <span className="text-primary uppercase italic">Early Access</span>
            </h2>
            
            <p className="text-2xl text-foreground/60 max-w-2xl font-medium mb-12">
              Join the waitlist to get early access.
            </p>

            <form
              onSubmit={handleSubmit}
              className="w-full max-w-2xl bg-secondary/10 p-4 rounded-3xl border border-primary/20 backdrop-blur-2xl flex flex-col sm:flex-row gap-4"
            >
              <input
                type="email"
                required
                placeholder="Enter your email address"
                className="flex-1 bg-transparent px-8 py-5 text-xl text-foreground outline-none border-none placeholder:text-foreground/30 font-medium"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                disabled={loading}
              />
              <button
                type="submit"
                disabled={loading}
                className="btn-primary py-5 px-10 text-xl font-bold shadow-2xl hover:scale-[1.02] disabled:opacity-50 disabled:cursor-not-allowed min-w-[200px]"
              >
                {loading ? (
                   <span className="flex items-center gap-2">
                     <svg className="animate-spin h-5 w-5 text-white" fill="none" viewBox="0 0 24 24"><circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle><path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path></svg>
                     Joining...
                   </span>
                ) : "Join the Waitlist"}
              </button>
            </form>

            {errorMessage && (
               <p className="mt-4 text-red-400 font-bold animate-pulse">{errorMessage}</p>
            )}

            <p className="mt-8 text-sm text-foreground/40 font-bold uppercase tracking-widest">
              Move up the waitlist when you invite friends.
            </p>
          </div>
        ) : (
          <div className="max-w-3xl mx-auto text-center animate-in fade-in zoom-in-95 duration-700">
            <div className="size-24 bg-primary rounded-full flex items-center justify-center mx-auto mb-10 shadow-2xl shadow-primary/30 animate-float">
               <svg className="size-14 text-background" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                 <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={3} d="M5 13l4 4L19 7" />
               </svg>
            </div>
            
            <h2 className="text-5xl sm:text-7xl font-extrabold text-foreground mb-8 tracking-tighter">
              YOU&apos;RE ON THE <span className="text-primary uppercase italic">LIST.</span>
            </h2>

            <p className="text-xl text-foreground/60 font-medium italic mb-12">
               Move up faster by inviting friends.
            </p>
            
            <div className="anime-card p-12 bg-secondary/20 mb-12 flex flex-col items-center gap-8 border-primary/30">
               <div>
                  <div className="text-sm font-bold text-primary/60 uppercase tracking-widest mb-2">Your Position</div>
                  <div className="text-7xl font-extrabold text-foreground">#{position}</div>
               </div>
               
               <div className="w-full h-px bg-primary/10" />
               
               <div className="w-full">
                  <div className="text-sm font-bold text-foreground/60 uppercase tracking-widest mb-6">Refer Friends to Move Up</div>
                  <div className="flex bg-background/50 p-2 rounded-2xl border border-primary/20 items-center justify-between">
                     <span className="px-6 font-mono font-bold text-primary text-xl truncate">
                        {referralLink}
                     </span>
                     <button
                        onClick={copyToClipboard}
                        className="btn-primary py-3 px-6 text-sm font-bold whitespace-nowrap"
                      >
                        Copy Link
                     </button>
                  </div>
               </div>

               <div className="w-full h-px bg-primary/10" />

               <div className="text-left w-full space-y-4">
                  <div className="text-sm font-bold text-primary/60 uppercase tracking-widest">Your Incentives:</div>
                  <ul className="grid sm:grid-cols-3 gap-4 text-sm font-bold text-foreground/80 italic">
                    <li className="flex items-center gap-2"><div className="size-2 bg-primary rounded-full animate-pulse"/> Early access</li>
                    <li className="flex items-center gap-2"><div className="size-2 bg-primary rounded-full animate-pulse"/> Priority onboarding</li>
                    <li className="flex items-center gap-2"><div className="size-2 bg-primary rounded-full animate-pulse"/> Early premium access</li>
                  </ul>
               </div>
            </div>

            <p className="text-xl text-foreground/60 font-medium italic animate-pulse-glow">
              Confirm your email to keep your rank!
            </p>
          </div>
        )}
      </div>

      {/* Professional Floating Toast Element */}
      <div 
        className={`fixed bottom-8 right-8 lg:bottom-12 lg:right-12 z-[100] transform transition-all duration-500 ease-[cubic-bezier(0.16,1,0.3,1)] flex items-center gap-4 bg-background border ${toast?.type === "error" ? "border-red-500/30" : "border-primary/30"} px-6 py-4 rounded-2xl shadow-[0_20px_40px_-15px_rgba(0,0,0,0.1)] min-w-[300px] ${
          toast ? 'translate-y-0 opacity-100 scale-100' : 'translate-y-12 opacity-0 scale-95 pointer-events-none'
        }`}
      >
        <div className={`size-10 rounded-full flex items-stretch shrink-0 justify-center ${toast?.type === "error" ? "bg-red-500/10 text-red-500" : "bg-primary/10 text-primary"}`}>
          {toast?.type === "error" ? (
             <svg className="m-auto size-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" /></svg>
          ) : (
             <svg className="m-auto size-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" /></svg>
          )}
        </div>
        <div className="flex flex-col">
          <span className="font-bold text-foreground tracking-wide">{toast?.title}</span>
          {toast?.desc && <span className="text-sm text-foreground/60 font-medium">{toast.desc}</span>}
        </div>
      </div>
    </section>
  );
};

export default WaitlistSection;
