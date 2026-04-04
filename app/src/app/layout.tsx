import type { Metadata } from "next";
import { JetBrains_Mono } from "next/font/google";
import "./globals.css";
import { MiniKitProvider } from "./minikit-provider";

const jetbrainsMono = JetBrains_Mono({
  subsets: ["latin"],
  weight: ["300", "400", "700"],
  variable: "--font-harvest-loaded",
  display: "swap",
});

export const metadata: Metadata = {
  title: "Harvest",
  description: "DeFi, for humans. The first yield aggregator on World Chain.",
  manifest: "/manifest.json",
  icons: {
    icon: "/icon.svg",
    apple: "/app-icon.svg",
  },
  appleWebApp: {
    capable: true,
    title: "Harvest",
    statusBarStyle: "black-translucent",
  },
  openGraph: {
    title: "Harvest",
    description: "DeFi, for humans. The first yield aggregator on World Chain.",
    images: [{ url: "/og-image.svg", width: 1200, height: 630 }],
  },
  twitter: {
    card: "summary_large_image",
    title: "Harvest",
    description: "DeFi, for humans. The first yield aggregator on World Chain.",
    images: ["/og-image.svg"],
  },
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" className={jetbrainsMono.variable}>
      <body>
        <MiniKitProvider>{children}</MiniKitProvider>
      </body>
    </html>
  );
}
