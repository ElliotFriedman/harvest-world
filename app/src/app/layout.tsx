import type { Metadata } from "next";
import "./globals.css";
import { MiniKitProvider } from "./minikit-provider";

export const metadata: Metadata = {
  title: "Harvest",
  description: "DeFi, for humans. Yield aggregator on World Chain.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>
        <MiniKitProvider>{children}</MiniKitProvider>
      </body>
    </html>
  );
}
