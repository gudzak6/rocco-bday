import path from "node:path";
import type { NextConfig } from "next";

const config: NextConfig = {
  transpilePackages: ["@birthday-go/shared"],
  poweredByHeader: false,
  experimental: { typedEnv: true },
  turbopack: { root: path.resolve(__dirname, "../..") },
  allowedDevOrigins: ["127.0.0.1"],
};

export default config;
