import { readFileSync } from "node:fs";
import { defineConfig } from "vite";

function protectedProxy(target: string | undefined, tokenFile: string | undefined, rewrite = ""): object | undefined {
  if (!target) return undefined;
  const token = tokenFile ? readFileSync(tokenFile, "utf8").trim() || undefined : undefined;
  return {
    target, changeOrigin: false,
    rewrite: (path: string) => path.replace(rewrite ? new RegExp(`^${rewrite}`) : /^\/hud/, ""),
    configure: (proxy: { on: (event: string, callback: (request: { setHeader: (key: string, value: string) => void }) => void) => void }) => {
      if (token) proxy.on("proxyReq", (request) => request.setHeader("authorization", `Bearer ${token}`));
    },
  };
}

// Extra development Hosts, so a phone can reach several Hosts through this one
// dev server without holding any credential itself. Each entry names a path
// under /hud, its Host target and a 0600 token file:
//   HERDEN_HUD_PROXY_EXTRA='[{"path":"/hud/agneta","target":"http://100.119.219.37:8791","tokenFile":"/home/ted/.config/herden/glasses-agneta-token"}]'
interface ExtraProxy { path: string; target: string; tokenFile?: string }
const extras: Record<string, object> = {};
for (const extra of JSON.parse(process.env.HERDEN_HUD_PROXY_EXTRA ?? "[]") as ExtraProxy[]) {
  const proxy = protectedProxy(extra.target, extra.tokenFile, extra.path);
  if (proxy) extras[extra.path] = proxy;
}

const primary = protectedProxy(process.env.HERDEN_HUD_PROXY_TARGET, process.env.HERDEN_HUD_PROXY_TOKEN_FILE);
const fansvine = protectedProxy(process.env.HERDEN_HUD_PROXY_FANSVINE_TARGET, process.env.HERDEN_HUD_PROXY_FANSVINE_TOKEN_FILE, "/hud/fansvine");

export default defineConfig({
  base: "./",
  server: {
    host: true, port: 5173, allowedHosts: true,
    // Development-only localhost proxy. It holds credentials in 0600 files;
    // the simulator receives only non-secret localhost placeholders. More
    // specific paths must precede "/hud", which would otherwise match them.
    proxy: { ...extras, ...(fansvine ? { "/hud/fansvine": fansvine } : {}), ...(primary ? { "/hud": primary } : {}) },
  },
  build: { target: "es2022", assetsInlineLimit: 0 },
});
