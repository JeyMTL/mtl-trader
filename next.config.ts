import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  transpilePackages: ['xlsx'],
  typescript: {
    ignoreBuildErrors: true,
  },
};

export default nextConfig;
