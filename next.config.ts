import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Empty turbopack config to silence the webpack warning
  turbopack: {},

  // Webpack config for fallback
  webpack: (config, { isServer }) => {
    // Resolve fallbacks for Node.js modules used by WalletConnect
    if (!isServer) {
      config.resolve.fallback = {
        ...config.resolve.fallback,
        fs: false,
        net: false,
        tls: false,
      };
    }
    return config;
  },
};

export default nextConfig;
