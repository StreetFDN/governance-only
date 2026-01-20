'use client';

import * as React from 'react';
import {
  RainbowKitProvider,
  getDefaultConfig,
  darkTheme,
} from '@rainbow-me/rainbowkit';
import { WagmiProvider } from 'wagmi';
import { base, baseSepolia, mainnet } from 'wagmi/chains';
import { QueryClientProvider, QueryClient } from "@tanstack/react-query";

// Base Sepolia for development, Base for production
const config = getDefaultConfig({
  appName: 'Street Governance',
  projectId: 'YOUR_PROJECT_ID', // Get a free one at cloud.walletconnect.com
  chains: [baseSepolia, base, mainnet], // Base Sepolia first for testnet
  ssr: true,
});

// Export chain IDs for network gating
export const SUPPORTED_CHAINS = {
  BASE: base.id,
  BASE_SEPOLIA: baseSepolia.id,
} as const;

const queryClient = new QueryClient();

export function Providers({ children }: { children: React.ReactNode }) {
  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <RainbowKitProvider theme={darkTheme({
          accentColor: '#BDB9FF', // Fallback accent
          borderRadius: 'medium',
          overlayBlur: 'small',
        })}>
          {children}
        </RainbowKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  );
}