/**
 * Lightweight mock DOM test for Graphviz Editor Emoji Picker & Logic
 */
const fs = require("fs");

console.log("=== Testing Graphviz Editor Emoji Picker Logic ===");

// 1. Load markdown_emojis.js
const emojiCode = fs.readFileSync("/root/ctlabs/ctlabs/js/markdown_emojis.js", "utf8");
const emojiSandbox = {
  window: {},
  document: {
    addEventListener: () => {}
  }
};
const fnEmojis = new Function("window", "document", emojiCode);
fnEmojis(emojiSandbox.window, emojiSandbox.document);

const GITHUB_EMOJI_LIST = emojiSandbox.window.GITHUB_EMOJI_LIST;
const GITHUB_EMOJI_MAP = emojiSandbox.window.GITHUB_EMOJI_MAP;
const replaceEmojiShortcodes = emojiSandbox.window.replaceEmojiShortcodes;

console.log("1. Loaded GITHUB_EMOJI_LIST count:", GITHUB_EMOJI_LIST.length);
console.log("   Loaded GITHUB_EMOJI_MAP count:", Object.keys(GITHUB_EMOJI_MAP).length);

if (!GITHUB_EMOJI_LIST || GITHUB_EMOJI_LIST.length < 1900) {
  throw new Error("GITHUB_EMOJI_LIST not properly populated");
}

console.log("2. Testing emoji categories in list:");
const categories = {};
GITHUB_EMOJI_LIST.forEach(item => {
  categories[item.cat] = (categories[item.cat] || 0) + 1;
});
console.log("   Categories distribution:", categories);
if (!categories["github"] || !categories["tech"] || !categories["status"]) {
  throw new Error("Missing expected categories");
}

console.log("3. Testing search & filter logic for Graphviz:");
function filterEmojis(cat, query) {
  const clean = query.trim().toLowerCase();
  return GITHUB_EMOJI_LIST.filter(item => {
    if (cat !== "all" && item.cat !== cat) return false;
    if (clean) {
      return item.code.toLowerCase().includes(clean) || item.name.toLowerCase().includes(clean);
    }
    return true;
  });
}

const rocketMatches = filterEmojis("all", "rocket");
console.log("   Search 'rocket' returned:", rocketMatches.map(m => m.code + " -> " + m.char));
if (rocketMatches.length === 0 || rocketMatches[0].char !== "🚀") {
  throw new Error("Failed to find rocket emoji");
}

const firewallMatches = filterEmojis("all", "firewall");
console.log("   Search 'firewall' returned:", firewallMatches.map(m => m.code + " -> " + m.char));
if (firewallMatches.length === 0 || firewallMatches[0].char !== "🛡️") {
  throw new Error("Failed to find firewall alias");
}

const databaseMatches = filterEmojis("all", "database");
console.log("   Search 'database' returned:", databaseMatches.map(m => m.code + " -> " + m.char));
if (databaseMatches.length === 0 || databaseMatches[0].char !== "🗄️") {
  throw new Error("Failed to find database alias");
}

console.log("4. Testing shortcode replacement on DOT diagram sources:");
const dotSourceWithCodes = `
digraph Architecture {
  rankdir=LR;
  client [label="Web Browser :globe_with_meridians:"];
  lb [label="Load Balancer :twisted_rightwards_arrows:"];
  web [label="App Server :rocket:", fillcolor="#0284c7"];
  fw [label="WAF :firewall: :shield:", fillcolor="#ef4444"];
  db [label="Cluster :database: :file_cabinet:", fillcolor="#10b981"];

  client -> lb [label=":lock: HTTPS"];
  lb -> fw;
  fw -> web [label=":white_check_mark: Allowed"];
  web -> db [label=":key: Auth"];
}
`;

const expanded = replaceEmojiShortcodes(dotSourceWithCodes);
console.log("   Expanded DOT source with emojis:");
console.log(expanded);

if (!expanded.includes("App Server 🚀")) throw new Error("Missing 🚀 in expanded DOT");
if (!expanded.includes("WAF 🛡️ 🛡")) throw new Error("Missing 🛡 in expanded DOT");
if (!expanded.includes("Cluster 🗄️ 🗄")) throw new Error("Missing 🗄 in expanded DOT");
if (!expanded.includes("🔒 HTTPS")) throw new Error("Missing 🔒 in expanded DOT");
if (!expanded.includes("✅ Allowed")) throw new Error("Missing ✅ in expanded DOT");
if (!expanded.includes("🔑 Auth")) throw new Error("Missing 🔑 in expanded DOT");

console.log("ALL GRAPHVIZ EMOJI LOGIC TESTS PASSED!");
