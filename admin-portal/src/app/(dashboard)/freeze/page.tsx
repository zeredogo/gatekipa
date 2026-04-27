import { db } from "@/lib/firebaseAdmin";
import FreezeClient from "./FreezeClient";

export const dynamic = "force-dynamic";

export default async function GlobalFreezePage() {
  const globalStateDoc = await db.collection("system_state").doc("global").get();
  const systemState = globalStateDoc.exists ? globalStateDoc.data() : { mode: "NORMAL" };
  const initialIsFrozen = systemState?.mode === "LOCKDOWN";

  return <FreezeClient initialIsFrozen={initialIsFrozen} />;
}
