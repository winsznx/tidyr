import { AnnouncementStrip } from "@/components/landing/announcement-strip";
import { LandingNav } from "@/components/landing/nav";
import { Hero } from "@/components/landing/hero";
import { ProductPreview } from "@/components/landing/product-preview";
import { Problem } from "@/components/landing/problem";
import { Workflow } from "@/components/landing/workflow";
import { MonadSection } from "@/components/landing/monad-section";
import { SecuritySection } from "@/components/landing/security-section";
import { ContractsTable } from "@/components/landing/contracts-table";
import { DemoCta } from "@/components/landing/demo-cta";
import { Footer } from "@/components/landing/footer";

export default function LandingPage() {
  return (
    <>
      <AnnouncementStrip />
      <LandingNav />
      <main>
        <Hero />
        <ProductPreview />
        <Problem />
        <Workflow />
        <MonadSection />
        <SecuritySection />
        <ContractsTable />
        <DemoCta />
      </main>
      <Footer />
    </>
  );
}
